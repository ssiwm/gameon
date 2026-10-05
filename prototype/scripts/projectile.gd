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
const Vfx := preload("res://scripts/vfx.gd")
const Lights := preload("res://scripts/lights.gd")

const MASK_AUTH := Combat.LAYER_WORLD | Combat.LAYER_PLAYER | Combat.LAYER_TARGET
const MASK_COSMETIC := Combat.LAYER_WORLD | Combat.LAYER_TARGET
const HOMING_DELAY := 0.12          ## s lotu prosto, zanim rakieta zacznie skręcać
const MAX_SEGMENTS := 6             ## ile trafień (przebić, pomijanych kolegów) na jedną klatkę

var weapon := 0
var shooter_id := 1
var authoritative := true
var direction := Vector2.RIGHT

var _def: RefCounted
var _vel := Vector2.ZERO
var _dist := 0.0
var _age := 0.0
var _pierce_left := 0
var _skip: Array[RID] = []
var _target: Node2D = null
var _light: PointLight2D
var _done := false

## Ustawia pocisk przed add_child. `auth` = serwer rozstrzyga trafienia.
func launch(w: int, from: Vector2, dir: Vector2, shooter: int, auth: bool) -> void:
	weapon = w
	_def = Weapons.def(w)
	shooter_id = shooter
	authoritative = auth
	direction = dir.normalized()
	position = from
	_vel = direction * float(_def.speed)
	_pierce_left = int(_def.pierce)

func _ready() -> void:
	# smuga widoczna w ciemności
	material = Lights.unshaded()
	z_index = 3
	rotation = _vel.angle()
	if float(_def.homing) > 0.0 or float(_def.gravity) > 0.0:
		_light = Lights.make_light(Lights.radial(), 1.8, _def.flash_color, 0.7, false)
		add_child(_light)
	if float(_def.homing) > 0.0:
		_target = _acquire_target()
	_check_origin()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if float(_def.homing) > 0.0 and _age > HOMING_DELAY:
		_steer(delta)
	if float(_def.gravity) > 0.0:
		_vel.y += float(_def.gravity) * delta
	var step := _vel * delta
	var from := global_position
	var to := from + step
	var travelled := step.length()
	if _sweep(from, to):
		return
	_dist += travelled
	rotation = _vel.angle()
	var fuse := float(_def.fuse)
	if fuse > 0.0 and _age >= fuse:
		_detonate(global_position, Vector2.UP)
		return
	if _dist >= float(_def.range_px):
		_expire()

# ---------------------------------------------------------------- trafienia

## Odcinek lotu: world → kolega (przelot) → wróg. Zwraca true, gdy pocisk się skończył.
func _sweep(from: Vector2, to: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var cur := from
	for _i in MAX_SEGMENTS:
		var q := PhysicsRayQueryParameters2D.create(cur, to, MASK_AUTH if authoritative else MASK_COSMETIC)
		q.exclude = _skip
		var hit := space.intersect_ray(q)
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
				if sticks_on_hit():
					_stick(p)
				if _def.blast_radius > 0.0:
					_detonate(p, -direction)
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
	var dmg: float = float(_def.damage) * float(_def.falloff(at_dist))
	var info := Combat.make_info(weapon, dmg, p, direction, shooter_id, "bullet")
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
	if _def.blast_radius > 0.0:
		_detonate(p, n)
		return
	_finish(p)

## Strzał z odległości zerowej: wylot wewnątrz wroga lub ściany promień pominąłby.
func _check_origin() -> void:
	var space := get_world_2d().direct_space_state
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = global_position
	pq.collision_mask = Combat.LAYER_WORLD | Combat.LAYER_TARGET
	var found := space.intersect_point(pq, 4)
	for f in found:
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
				if sticks_on_hit():
					_stick(global_position)
				if _def.blast_radius > 0.0:
					_detonate(global_position, -direction)
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

func _finish(_at: Vector2) -> void:
	_done = true
	set_physics_process(false)
	queue_free()

func _expire() -> void:
	if authoritative and sticks_on_hit():
		_stick(global_position)
	if authoritative and _def.blast_radius > 0.0:
		_detonate(global_position, Vector2.UP)
		return
	_finish(global_position)

## Wybuch (granat): serwer liczy obrażenia i hałas, efekt przychodzi do wszystkich przez Arsenal.
func _detonate(at: Vector2, _normal: Vector2) -> void:
	if authoritative:
		Combat.explode(get_tree(), at, float(_def.blast_radius), float(_def.blast_damage), shooter_id, weapon)
	_finish(at)

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

func _draw() -> void:
	var col: Color = _def.tracer_color
	var tail := float(_def.tracer_len)
	if float(_def.gravity) > 0.0:
		# granat: ciemny korpus z żarzącym się zapalnikiem
		draw_circle(Vector2.ZERO, 2.4, Color(0.3, 0.32, 0.2))
		draw_circle(Vector2(-1.5, 0), 1.1, Color(1.0, 0.7, 0.3))
		return
	if sticks_on_hit():
		# bełt: cienki drzewiec z grotem
		draw_line(Vector2(-tail * 0.5, 0), Vector2(1, 0), Color(0.62, 0.5, 0.34), 1.0)
		draw_line(Vector2(1, 0), Vector2(4, 0), Color(0.85, 0.85, 0.9), 1.4)
		return
	if float(_def.homing) > 0.0:
		# rakieta: korpus + gasnący ogon dymu/żaru
		draw_line(Vector2(-tail, 0), Vector2(-2, 0), Color(col.r, col.g, col.b, 0.25), 3.0)
		draw_line(Vector2(-tail * 0.6, 0), Vector2(-1, 0), Color(col.r, col.g, col.b, 0.7), 1.6)
		draw_rect(Rect2(-2, -1, 4, 2), Color(0.9, 0.9, 0.92))
		return
	# kula / śrut: jasna głowa i zanikający ogon wzdłuż toru
	draw_line(Vector2(-tail, 0), Vector2(0, 0), Color(col.r, col.g, col.b, 0.22), 1.2)
	draw_line(Vector2(-tail * 0.5, 0), Vector2(0, 0), Color(col.r, col.g, col.b, 0.7), 1.4)
	draw_rect(Rect2(-1, -0.5, 3, 1), Color(1.0, 0.97, 0.85))
