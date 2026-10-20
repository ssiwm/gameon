extends Node2D
## Pocisk (zastępuje bullet.gd). Jeden skrypt obsługuje kulę, śrut, rakietę z
## naprowadzaniem, granat po łuku i bełt — zachowanie wynika z WeaponDef.
##
## Dwa tryby, ten sam kod ruchu:
##   authoritative (serwer)  liczy trafienia i zadaje obrażenia (combat.gd)
##   kosmetyczny (klient)    leci identycznie i znika przy ścianie / celu —
##                           to wizualizacja (także PRZEWIDYWANA kopia strzelca,
##                           która pojawia się w tej samej klatce co strzał)
##
## Ruch to odcinek [poprzednia, następna pozycja] sprawdzany promieniem, a nie
## przesuwany obszar: szybki bełt czy szyna nie przeskoczą cienkiej ściany ani
## wąskiego wroga niezależnie od klatkażu.

const Weapons := preload("res://scripts/weapons.gd")
const Combat := preload("res://scripts/combat.gd")
const Hurtbox := preload("res://scripts/hurtbox.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Lights := preload("res://scripts/lights.gd")
const Throwables := preload("res://scripts/throwables.gd")

const MASK_AUTH := Combat.LAYER_WORLD | Combat.LAYER_PLAYER | Combat.LAYER_TARGET
const MASK_COSMETIC := Combat.LAYER_WORLD | Combat.LAYER_TARGET
const HOMING_DELAY := 0.12          ## s lotu prosto, zanim rakieta zacznie skręcać
const EVASIVE_KINDS := ["cma", "skoczek", "podsluchacz"]    ## cele „trudne do trafienia" — naprowadzanie (FALCON-6) wybiera je w pierwszej kolejności
const EVASIVE_BONUS := 40.0
const CLUSTER_RADIUS := 0.6         ## bomba kasetowa: ułamek promienia głównego wybuchu…
const CLUSTER_DAMAGE := 0.5         ## …i jego obrażeń
const CLUSTER_SPREAD := 24.0        ## px od punktu wybuchu w bok
const MAX_SEGMENTS := 6             ## ile trafień (przebić, pomijanych kolegów) na jedną klatkę
const FAST_PX := 900.0              ## px/s: od tej prędkości kula w locie to smuga (view3d.gd), a koniec lotu zostawia dogasający ślad
const TRACER_SEC := 0.022           ## s lotu, które obejmuje smuga (długość = prędkość × to; M-83 ok. 53 px ≈ 4,3 m)
const TRACE_LIFE := 0.08            ## s dogasania śladu po trafieniu / końcu zasięgu
const WHIZZ_PX := 18.0              ## px (ok. 1,5 m): kula przelatująca tak blisko głowy gracza świszczy mu koło ucha
const WHIZZ_MIN_FLIGHT := 30.0      ## px lotu, poniżej których świstu nie ma (stoisz przy lufie — słychać wystrzał)

var weapon := 0
var ammo := 0                        ## typ naboju (ammo.gd) — ta sama kula u serwera i klientów
var shooter_id := 1
var authoritative := true
var direction := Vector2.RIGHT
var origin := Vector2.ZERO          ## punkt wylotu (smuga nie sięga za lufę)

var _def: RefCounted
var _vel := Vector2.ZERO
var _dist := 0.0
var _age := 0.0
var _pierce_left := 0
var _skip: Array[RID] = []
var _target: Node2D = null
var _light: Lights.GameLight
var _done := false
var _whizzed := false
var _seg_from := Vector2.INF          ## początek odcinka lotu bieżącej klatki (świst sprawdzany też, gdy kula kończy lot w tej klatce)
static var whizz_count := 0           ## licznik świstów (testy headless)
static var dud_count := 0             ## licznik nieuzbrojonych granatów, które trafiły bez wybuchu (testy headless)
var lag := 0.0                      ## s kompensacji opóźnienia (serwer, strzał klienta) — patrz lag_comp.gd
var _comp_rids: Array[RID] = []     ## wrogowie z historią: w trakcie dogonienia pomijamy ich ciała fizyczne

## Ustawia pocisk przed add_child. `auth` = serwer rozstrzyga trafienia.
func launch(w: int, from: Vector2, dir: Vector2, shooter: int, auth: bool, lag_s := 0.0, ammo_t := 0) -> void:
	lag = lag_s
	weapon = w
	ammo = ammo_t
	_def = Weapons.def_ammo(w, ammo_t)
	shooter_id = shooter
	authoritative = auth
	direction = dir.normalized()
	position = from
	origin = from
	_vel = direction * float(_def.speed_at(0.0))         # rakieta z silnikiem (FALCON-6) startuje wolno i rozpędza się w locie (`_boost`)
	_pierce_left = int(_def.pierce)

func _ready() -> void:
	add_to_group("projectiles")            # widok 3D (view3d.gd) odzwierciedla pociski jako smugi 3D
	# smuga widoczna w ciemności
	material = Lights.unshaded()
	z_index = 3
	rotation = _vel.angle()
	if float(_def.homing) > 0.0 or float(_def.blast_radius) > 0.0:          # żar rakiety i zapalnik granatu (bełt nie świeci, choć też opada)
		_light = Lights.make_light(Lights.radial(), 1.8, _def.flash_color, 0.7, false)
		add_child(_light)
	if float(_def.homing) > 0.0:
		_target = _acquire_target()
	_check_origin()
	if authoritative and lag > 0.0 and not _done:
		_catch_up(lag)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	_boost()
	if float(_def.homing) > 0.0 and _age > HOMING_DELAY:
		_steer(delta)
	if float(_def.gravity) > 0.0:
		_vel.y += float(_def.gravity) * delta
	var step := _vel * delta
	var from := global_position
	var to := from + step
	var travelled := step.length()
	_seg_from = from
	if _sweep(from, to):
		return
	_near_miss(from, global_position)
	_dist += travelled
	rotation = _vel.angle()
	if String(_def.payload) == "illum" and _age > 0.15 and _vel.y >= 0.0:
		_release(global_position)                 # szczyt toru: nabój oświetlający wyrzuca flarę na spadochronie
		return
	var fuse := float(_def.fuse)
	if fuse > 0.0 and _age >= fuse and is_armed():
		_detonate(global_position, Vector2.UP)
		return
	if _dist >= float(_def.range_px):
		_expire()

# ---------------------------------------------------------------- kompensacja opóźnienia

## Pocisk klienta „dogania" czas strzału: leci `lag_s` sekund krokami po LagComp.STEP, testując
## trafienia w pozycje wrogów sprzed (lag_s − postęp) s. Po dogonieniu zwykła fizyka w czasie
## rzeczywistym. Ściany i koledzy: zwykłe promienie, bo świat statyczny się nie cofa.
func _catch_up(lag_s: float) -> void:
	var t_now := LagComp.now()
	_comp_rids = LagComp.rewound_rids()
	var elapsed := 0.0
	while elapsed < lag_s and not _done:
		var dt := minf(LagComp.STEP, lag_s - elapsed)
		_age += dt
		_boost()
		if float(_def.homing) > 0.0 and _age > HOMING_DELAY:
			_steer(dt)
		if float(_def.gravity) > 0.0:
			_vel.y += float(_def.gravity) * dt
		var step := _vel * dt
		var from := global_position
		var rewind_t := t_now - lag_s + elapsed + dt          # chwila, w której pocisk kończy ten krok
		if _sweep(from, from + step, rewind_t):
			return
		_dist += step.length()
		rotation = _vel.angle()
		var fuse := float(_def.fuse)
		if fuse > 0.0 and _age >= fuse and is_armed():
			_detonate(global_position, Vector2.UP)
			return
		if _dist >= float(_def.range_px):
			_expire()
			return
		elapsed += dt
	_comp_rids.clear()

# ---------------------------------------------------------------- trafienia

## Odcinek lotu: world → kolega (przelot) → wróg. Zwraca true, gdy pocisk się skończył.
func _sweep(from: Vector2, to: Vector2, rewind := -1.0) -> bool:
	var space := get_world_2d().direct_space_state
	var cur := from
	var comp := rewind >= 0.0 and authoritative
	for _i in MAX_SEGMENTS:
		var q := PhysicsRayQueryParameters2D.create(cur, to, MASK_AUTH if authoritative else MASK_COSMETIC)
		q.collide_with_areas = true                               # strefy trafień wrogów (hurtbox.gd)
		if comp:
			var ex: Array[RID] = _skip.duplicate()
			ex.append_array(_comp_rids)
			q.exclude = Hurtbox.with_areas(ex)
		else:
			q.exclude = Hurtbox.with_areas(_skip)
		var hit := Hurtbox.resolve(space.intersect_ray(q))
		if comp:
			# wróg w pozycji sprzed `lag` s (jeśli wcześniej niż ściana / kolega) zastępuje trafienie fizyczne
			var lim: Vector2 = to if hit.is_empty() else hit["position"]
			var eh := LagComp.enemy_hit(cur, lim, rewind, _skip)
			if not eh.is_empty() and (hit.is_empty() or cur.distance_to(eh["pos"]) <= cur.distance_to(hit["position"])):
				hit = {"collider": eh["node"], "position": eh["pos"], "normal": -direction, "rid": (eh["node"] as CollisionObject2D).get_rid()}
		if hit.is_empty():
			global_position = to
			return false
		var collider: Object = hit["collider"]
		var p: Vector2 = hit["position"]
		var n: Vector2 = hit["normal"]
		var seg := (p - cur).length()
		var at_dist := _dist + (p - from).length()
		var node := collider as Node
		if node != null and node.is_in_group("players"):
			# własny pocisk (celowanie w dół) i leżący — przelot; kolega — przelot + krzyk (FF)
			_skip.append(hit["rid"])
			if authoritative and node.player_id != shooter_id and not node.dead:
				node.deliver_ff(p)
			cur = p
			continue
		if node != null and node.is_in_group("enemies"):
			if not authoritative:
				_finish(p)
				return true
			var res := _hit_target(node, p, at_dist)
			if bool(res.get("hit", false)):
				if bool(res.get("pass", false)) and _def.blast_radius <= 0.0:
					_skip.append(hit["rid"])         # cel przepuszczający pociski (wynik `pass`): pocisk leci dalej
					cur = p
					continue
				if sticks_on_hit():
					_stick(p)
				if String(_def.payload) != "":
					_release(p)
					return true
				if _def.blast_radius > 0.0:
					if is_armed(at_dist):
						_detonate(p, -direction)
					else:
						_dud(p)
					return true
				if _pierce_left > 0:
					_pierce_left -= 1
					_skip.append(hit["rid"])
					cur = p
					continue
				_finish(p)
				return true
			# cel nie przyjął obrażeń (martwy, nietykalny) — przelot
			_skip.append(hit["rid"])
			cur = p
			continue
		# ściana
		_world_hit(p, n)
		return true
	global_position = to
	return false

func sticks_on_hit() -> bool:
	return bool(_def.sticks)

func _hit_target(node: Node, p: Vector2, at_dist: float) -> Dictionary:
	var dmg: float = float(_def.damage) * float(_def.falloff(at_dist)) * float(_def.boost_damage(_vel.length()))
	var info := Combat.make_info(weapon, dmg, p, direction, shooter_id, "bullet", ammo)
	var res := Combat.apply(node, info)
	Combat.report(info, res)
	return res

func _world_hit(p: Vector2, n: Vector2) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var surface := "dirt"
	if lvl != null:
		surface = lvl.surface_at_hit(p, n)
	Vfx.impact(lvl if lvl != null else get_parent(), p, n, surface, _def.pellets >= 5)
	if authoritative and sticks_on_hit():
		_stick(p)
	if String(_def.payload) != "":
		_release(p + n * 2.0)
		return
	if _def.blast_radius > 0.0:
		if is_armed(_dist + global_position.distance_to(p)):
			_detonate(p, n)
		else:
			_dud(p)
		return
	_finish(p)

## Strzał z odległości zerowej: wylot wewnątrz wroga lub ściany promień pominąłby.
func _check_origin() -> void:
	var space := get_world_2d().direct_space_state
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = global_position
	pq.collision_mask = Combat.LAYER_WORLD | Combat.LAYER_TARGET
	pq.collide_with_areas = true
	var found := space.intersect_point(pq, 8)
	var seen := {}
	for f0 in found:
		var f := Hurtbox.resolve(f0)
		if seen.has(f.get("rid")):
			continue                                          # ciało i jego strefa trafień — jeden cel
		seen[f.get("rid")] = true
		var node := f["collider"] as Node
		if node == null:
			continue
		if node.is_in_group("enemies"):
			if not authoritative:
				_finish(global_position)
				return
			var res := _hit_target(node, global_position, 0.0)
			if bool(res.get("hit", false)):
				_skip.append(f["rid"])
				if bool(res.get("pass", false)) and _def.blast_radius <= 0.0:
					continue
				if sticks_on_hit():
					_stick(global_position)
				if String(_def.payload) != "":
					_release(global_position)
					return
				if _def.blast_radius > 0.0:
					_dud(global_position)                       # przy wylocie zapalnik nigdy nie jest uzbrojony
					return
				if _pierce_left > 0:
					_pierce_left -= 1
					continue
				_finish(global_position)
				return
		elif not node.is_in_group("players"):
			_world_hit(global_position, -direction)
			return

# ---------------------------------------------------------------- koniec lotu

## Świst koło ucha (od 1.7.312): kula cudzego strzału (kolega, bot) przelatuje w odległości WHIZZ_PX od głowy lokalnego gracza.
## Każdy peer ma jedną kopię pocisku (autorytatywną albo kosmetyczną), więc każdy słyszy świst przy własnej postaci; strzelec — nigdy.
func _near_miss(a: Vector2, b: Vector2) -> void:
	if _whizzed or not is_fast() or _dist + a.distance_to(b) < WHIZZ_MIN_FLIGHT:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or not p.is_multiplayer_authority() or int(p.player_id) == shooter_id or p.dead:
			continue
		var ear: Vector2 = (p as Node2D).global_position + Vector2(0.0, -16.0)
		var c := Geometry2D.get_closest_point_to_segment(ear, a, b)
		if c.distance_to(ear) <= WHIZZ_PX:
			_whizzed = true
			whizz_count += 1
			Audio.play_variant_at("whizz", 3, c, Audio.BUS_WORLD, -8.0, 1.0, 0.12)
		return

## Szybka kula (broń palna): w locie smuga, nie widoczny pocisk. Rakieta, bełt i granat mają własne bryły (view3d.gd `_make_proj`).
func is_fast() -> bool:
	return float(_def.speed) >= FAST_PX and float(_def.homing) <= 0.0 and float(_def.gravity) <= 0.0 and not bool(_def.sticks)

## Długość smugi w punkcie `at` (px): prędkość × TRACER_SEC, ale nie dalej niż do wylotu.
func tracer_len_at(at: Vector2) -> float:
	return minf(float(_def.speed) * TRACER_SEC, at.distance_to(origin))

func _finish(at: Vector2) -> void:
	if not _done and _seg_from != Vector2.INF:
		_near_miss(_seg_from, at)               # kula minęła ucho i w tej samej klatce trafiła w mur za graczem
	if is_fast() and not _done:
		# ostatni odcinek lotu dogasa: kula trafiająca w pierwszej klatce (z bliska) też zostawia widoczny tor od lufy
		var tail := tracer_len_at(at)
		if tail > 1.0:
			Vfx.trace(at - direction * tail, at, _def.tracer_color, _def.pellets > 1, TRACE_LIFE)
	_done = true
	set_physics_process(false)
	queue_free()

func _expire() -> void:
	if String(_def.payload) != "":
		_release(global_position)
		return
	if authoritative and sticks_on_hit():
		_stick(global_position)
	if authoritative and _def.blast_radius > 0.0 and is_armed():
		_detonate(global_position, Vector2.UP)
		return
	_finish(global_position)

## Zapalnik uzbrojony: granat przeleciał `arm_dist` (domyślnie do bieżącego punktu lotu). Broń bez odległości uzbrojenia — zawsze.
func is_armed(at_dist := -1.0) -> bool:
	return (_dist if at_dist < 0.0 else at_dist) >= float(_def.arm_dist)

## Granat trafił, zanim zapalnik się uzbroił: tępe uderzenie bez wybuchu i bez hałasu detonacji (trafiony wróg dostał już obrażenia
## i ogłuszenie samego pocisku w `_hit_target`). Jak prawdziwy granat 40 mm — strzał pod nogi nie rani strzelca.
func _dud(at: Vector2) -> void:
	if authoritative:
		dud_count += 1
	Audio.play_variant_at("impact_hard", 3, at, Audio.BUS_WORLD, -8.0, 0.7)
	_finish(at)

## Ładunek naboju 40 mm bez wybuchu (`WeaponDef.payload`): serwer tworzy flarę na spadochronie albo chmurę dymu u wszystkich peerów
## (level.gd RPC); kopie kosmetyczne tylko znikają.
func _release(at: Vector2) -> void:
	if authoritative and not _done:
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			match String(_def.payload):
				"illum":
					lvl.spawn_flare(at, Vector2(_vel.x * 0.15, 0.0), true)
				"smoke":
					lvl.spawn_smoke(at + Vector2(0.0, -6.0), float(Throwables.KINDS["smoke"]["cloud_life"]))
	_finish(at)

## Silnik rakiety (FALCON-6 = Gyrojet): prędkość rośnie z czasem lotu do `speed`; kierunek bez zmian (skręca `_steer`).
func _boost() -> void:
	if float(_def.accel_time) <= 0.0:
		return
	var v := float(_def.speed_at(_age))
	if _vel.length() < v:
		_vel = _vel.normalized() * v

## Wybuch (granat): serwer liczy obrażenia i hałas, efekt przychodzi do wszystkich przez Arsenal.
func _detonate(at: Vector2, normal: Vector2) -> void:
	if authoritative:
		# środek wybuchu 2 px przed powierzchnią: linia wzroku do celów (combat.gd `blast_reaches`) nie zaczyna się w murze
		var c := at + (normal.normalized() * 2.0 if normal.length() > 0.1 else Vector2.ZERO)
		Combat.explode(get_tree(), c, float(_def.blast_radius), float(_def.blast_damage), shooter_id, weapon)
		if int(_def.cluster) > 0:
			_scatter_cluster(at)
	_finish(at)

## Granaty kasetowe (WRATH-4, poziom 3): po głównym wybuchu rozsypują się mniejsze bomby po bokach, kolejno co 0,12 s. Bez dodatkowego hałasu.
func _scatter_cluster(at: Vector2) -> void:
	var tree := get_tree()
	var r := float(_def.blast_radius) * CLUSTER_RADIUS
	var dmg := float(_def.blast_damage) * CLUSTER_DAMAGE
	var sid := shooter_id
	var w := weapon
	for i in int(_def.cluster):
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := at + Vector2(side * (CLUSTER_SPREAD + 10.0 * float(i / 2)), -6.0)
		tree.create_timer(0.12 * float(i + 1)).timeout.connect(func() -> void:
			Combat.explode(tree, pos, r, dmg, sid, w, true))

## Bełt zostaje w świecie jako skrzynka z 1 nabojem (GDD §6.1: „bełt do odzysku”).
func _stick(at: Vector2) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		lvl.spawn_item("ammo", weapon, at + Vector2(0, -2), 1)

# ---------------------------------------------------------------- naprowadzanie

## Najbliższy w kącie celowania wróg-zagrożenie (żywy, aktywny, w zasięgu, w linii wzroku).
func _acquire_target() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	var space := get_world_2d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n) or not n.has_method("is_threat") or not n.call("is_threat"):
			continue
		if n.is_in_group("props"):
			continue
		var c := Combat.center_of(n)
		var v := c - global_position
		var dist := v.length()
		if dist > float(_def.homing_range) or dist < 4.0:
			continue
		var ang := absf(rad_to_deg(direction.angle_to(v)))
		if ang > float(_def.homing_cone):
			continue
		if not Combat.clear_line(space, global_position, c):
			continue
		var score := ang * 2.0 + dist * 0.1
		if n.get("kind") in EVASIVE_KINDS:
			score -= EVASIVE_BONUS           # naprowadzanie woli cele trudne do trafienia z ręki: ćmę, skoczka, podsłuchacza
		if score < best_score:
			best_score = score
			best = n
	return best

func _steer(delta: float) -> void:
	if _target != null and (not is_instance_valid(_target) or not _target.visible or not _target.call("is_threat")):
		_target = null
	if _target == null:
		return
	var want := (Combat.center_of(_target) - global_position).angle()
	var cur := _vel.angle()
	var diff := wrapf(want - cur, -PI, PI)
	var turn := clampf(diff, -float(_def.homing) * delta, float(_def.homing) * delta)
	_vel = Vector2.from_angle(cur + turn) * _vel.length()
	direction = _vel.normalized()

# ---------------------------------------------------------------- rysowanie
