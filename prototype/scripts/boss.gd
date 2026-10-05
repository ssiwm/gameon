extends CharacterBody2D
## Żyła — matka gniazd. Boss misji „Gniazdo" (GDD §7.1 Żyła: HP 200, splot
## 5–10 m, rodzi Trzoski; §16.0 pkt 1: demo = misja w całości z bossem).
##
## Gniazda są jej odnóżami: dopóki choć jedno żyje, Żyła śpi i jest
## nietykalna (pociski się odbijają). Zniszczenie ostatniego budzi ją —
## dopiero jej śmierć otwiera ekstrakcję (mission.gd).
##
## Uczciwość (jak Stalker, §8.5): smagnięcie macką ma zapowiedź — macka
## unosi się i czerwienieje — więc z zasięgu da się uciec.
##
## Bez „kampienia" na rusztowaniach (1.3.8): z półek nad Żyłą dało się ją
## zabić bezkarnie. Dlatego (1) GRZBIET jest pancerny — pocisk lecący z góry
## pod stromym kątem zadaje 20% obrażeń i rykoszetuje; słaby punkt to
## paszcza, w którą trafia się z poziomu ziemi; (2) gracza poza zasięgiem
## macki, a w zasięgu SPIT_RANGE, Żyła opluwa zarodnikami: 0,8 s nabrzmiewa
## (zapowiedź), potem wolny pocisk po łuku w miejsce, gdzie stał — kto się
## ruszy, unika.
## Symulacja TYLKO na serwerze; klienci dostają stan przez _sync.

signal died

const Lights := preload("res://scripts/lights.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

enum State { DORMANT, AWAKE, DEAD }

const BASE_HP := 200.0
const HP_PER_EXTRA_HUMAN := 100.0
const LASH_RANGE_X := 64.0
const LASH_RANGE_Y := 70.0
const LASH_WINDUP := 0.75
const LASH_COOLDOWN := 2.6
const LASH_COOLDOWN_ENRAGED := 1.9
const BROOD_EVERY := 7.0
const BROOD_EVERY_ENRAGED := 5.0
const BROOD_MAX := 3              ## żyjącego potomstwa naraz (+1 za dodatkowego człowieka)
const N_SCREAM := 15.0            ## przebudzenie: krzyk słychać w całym tartaku
const ARMOR_MULT := 0.2           ## obrażenia w pancerny grzbiet
const ARMOR_DOWN := 0.45          ## pocisk „z góry": składowa pionowa kierunku > tego
const SPIT_RANGE := 300.0
const SPIT_WINDUP := 0.8
const SPIT_COOLDOWN := 3.2
const SPIT_COOLDOWN_ENRAGED := 2.4
const SPIT_GRAVITY := 520.0
const SPIT_HIT_R := 11.0
const N_SPLASH := 2.0
const N_DEATH := 20.0

var state: int = State.DORMANT
var hp := BASE_HP
var max_hp := BASE_HP
var winding := false
var spitting := false             ## zapowiedź plucia (nabrzmiewanie) — synchronizowane
var enraged := false
var nests_left := 3

var _lash_cd := 0.0
var _windup := 0.0
var _brood_t := 0.0
var _brood_serial := 0
var _brood: Array[Node] = []
var _flash := 0.0
var _flinch := 0.0
var _net_t := 0.0
var _light: PointLight2D
var _overlay: Node2D
var _spit_cd := 0.0
var _spit_windup := 0.0
var _spit_target := Vector2.ZERO
var _spits: Array[Dictionary] = []    ## serwer: {pos, vel} — obrażenia liczy tylko serwer
var _armor_snd_ms := 0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	_light = Lights.make_light(Lights.radial(), 3.5, Color(1.0, 0.35, 0.25), 0.5, false)
	_light.position = Vector2(0, -20)
	add_child(_light)
	_overlay = Lights.add_overlay(self)

## Boty strzelają tylko do obudzonej (śpiąca jest nietykalna — strata amunicji i hałas).
func is_threat() -> bool:
	return state == State.AWAKE

func is_alive() -> bool:
	return state != State.DEAD

# ---------------------------------------------------------------- misja (serwer)

## Gniazdo zniszczone: wstrząs. Wołane przez mission.gd.
func on_nest_lost(left: int) -> void:
	nests_left = left
	_flinch = 0.6
	Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.6)
	_send_state(true)

func awaken() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	var humans := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			humans += 1
	max_hp = BASE_HP + HP_PER_EXTRA_HUMAN * maxi(0, humans - 1)
	hp = max_hp
	state = State.AWAKE
	_lash_cd = 1.5
	_spit_cd = 2.5
	_brood_t = 2.0
	NoiseMgr.add_noise(N_SCREAM, global_position)
	print("[BOSS] Żyła budzi się, HP=%.0f" % max_hp)
	_event.rpc("awaken")
	_send_state(true)

## Restart misji (wipe / nowa misja).
func reset_enemy() -> void:
	state = State.DORMANT
	hp = BASE_HP
	max_hp = BASE_HP
	winding = false
	spitting = false
	enraged = false
	nests_left = 3
	_windup = 0.0
	_spit_windup = 0.0
	_spits.clear()
	visible = true
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)
	if NoiseMgr.is_server():
		_clear_brood.rpc()
		_send_state(true)

# ---------------------------------------------------------------- symulacja

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_flinch = maxf(0.0, _flinch - delta)
	if not NoiseMgr.is_server():
		return
	if state == State.AWAKE:
		_tick_lash(delta)
		if not winding:
			_tick_spit(delta)
		_tick_brood(delta)
	_tick_spits(delta)
	_net_t -= delta
	if _net_t <= 0.0:
		_send_state(false)

func _tick_lash(delta: float) -> void:
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			winding = false
			var hit := 0
			for p in _players_in_reach(6.0):
				p.deliver_hit(1, global_position)
				hit += 1
			Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.5)
			print("[BOSS] smagnięcie: trafieni %d" % hit)
			_lash_cd = LASH_COOLDOWN_ENRAGED if enraged else LASH_COOLDOWN
			_send_state(true)
		return
	_lash_cd -= delta
	if _lash_cd <= 0.0 and not _players_in_reach(0.0).is_empty():
		_windup = LASH_WINDUP
		winding = true
		_event.rpc("windup")
		_send_state(true)

# ---------------------------------------------------------------- plucie

## Cel plucia: najwyżej stojący żywy gracz poza zasięgiem macki, w SPIT_RANGE.
func _spit_candidate() -> Node2D:
	var best: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if d.length() > SPIT_RANGE:
			continue
		if absf(d.x) <= LASH_RANGE_X and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			continue          # w zasięgu macki — to robota smagnięcia
		if best == null or p.global_position.y < best.global_position.y:
			best = p
	return best

func _tick_spit(delta: float) -> void:
	if _spit_windup > 0.0:
		_spit_windup -= delta
		if _spit_windup <= 0.0:
			spitting = false
			_launch_spit(_spit_target)
			_spit_cd = SPIT_COOLDOWN_ENRAGED if enraged else SPIT_COOLDOWN
			_send_state(true)
		return
	_spit_cd -= delta
	if _spit_cd > 0.0:
		return
	var p := _spit_candidate()
	if p == null:
		return
	# cel ustalony NA POCZĄTKU zapowiedzi — kto się ruszy, ten unika
	_spit_target = p.global_position + Vector2(0, -8)
	_spit_windup = SPIT_WINDUP
	spitting = true
	_event.rpc("spit_windup")
	_send_state(true)

func _launch_spit(target: Vector2) -> void:
	var start := global_position + Vector2(0, -34)
	var dist := start.distance_to(target)
	var t := clampf(dist / 240.0, 0.75, 1.3)
	var vel := (target - start - Vector2(0, 0.5 * SPIT_GRAVITY * t * t)) / t
	_spits.append({"pos": start, "vel": vel})
	_spit_fx.rpc(start, vel)

## Lot zarodników na serwerze: trafienie gracza albo rozprysk na bryle.
func _tick_spits(delta: float) -> void:
	if _spits.is_empty():
		return
	var lvl := get_parent()
	var keep: Array[Dictionary] = []
	for sp in _spits:
		sp.vel.y += SPIT_GRAVITY * delta
		sp.pos += sp.vel * delta
		var hit := false
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and (p.global_position + Vector2(0, -8)).distance_to(sp.pos) <= SPIT_HIT_R:
				p.deliver_hit(1, sp.pos)
				hit = true
				break
		var cell := Vector2i(int(floor(sp.pos.x / 16.0)), int(floor(sp.pos.y / 16.0)))
		if hit or lvl._is_solid(cell.x, cell.y) or sp.pos.y > lvl.bounds.end.y:
			NoiseMgr.add_noise(N_SPLASH, sp.pos)
			_splash_fx.rpc(sp.pos)
			continue
		keep.append(sp)
	_spits = keep

## Wizualny zarodnik na każdym peerze — ten sam tor (deterministyczny),
## znika na bryle; obrażenia liczy wyłącznie serwer (_tick_spits).
@rpc("authority", "call_local", "reliable")
func _spit_fx(start: Vector2, vel: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, start, Audio.BUS_WORLD, -4.0, 1.4)
	var glob := SpitGlob.new()
	glob.vel = vel
	glob.gravity = SPIT_GRAVITY
	glob.level = get_parent()
	glob.position = start
	glob.material = Lights.unshaded()
	glob.add_child(Lights.make_light(Lights.radial(), 1.5, Color(0.7, 1.0, 0.3), 0.8, false))
	get_parent().add_child(glob)

@rpc("authority", "call_local", "unreliable")
func _splash_fx(pos: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -8.0, 1.2)
	_burst(pos, Color(0.6, 0.95, 0.3), 14)

class SpitGlob extends Node2D:
	var vel := Vector2.ZERO
	var gravity := 520.0
	var level: Node
	var life := 2.5
	func _physics_process(delta: float) -> void:
		vel.y += gravity * delta
		position += vel * delta
		life -= delta
		var c := Vector2i(int(floor(position.x / 16.0)), int(floor(position.y / 16.0)))
		if life <= 0.0 or level._is_solid(c.x, c.y):
			queue_free()
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.5, Color(0.65, 1.0, 0.3))
		draw_circle(-vel.normalized() * 4.0, 2.2, Color(0.5, 0.85, 0.25, 0.6))

func _players_in_reach(slack: float) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.x) <= LASH_RANGE_X + slack and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			out.append(p)
	return out

func _tick_brood(delta: float) -> void:
	_brood = _brood.filter(func(b: Node) -> bool: return is_instance_valid(b) and b.alive)
	_brood_t -= delta
	if _brood_t > 0.0:
		return
	_brood_t = BROOD_EVERY_ENRAGED if enraged else BROOD_EVERY
	var humans := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			humans += 1
	if _brood.size() >= BROOD_MAX + maxi(0, humans - 1):
		return
	_brood_serial += 1
	var side := -1.0 if _brood_serial % 2 == 0 else 1.0
	_spawn_brood.rpc("Brood%d" % _brood_serial, global_position + Vector2(side * 34.0, 0))

## Potomstwo: ten sam węzeł na każdym peerze (stała nazwa → RPC wroga działa).
@rpc("authority", "call_local", "reliable")
func _spawn_brood(n: String, pos: Vector2) -> void:
	var lvl := get_parent()
	if lvl.has_node(n):
		return
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = "trzosek"
	e.position = pos
	lvl.add_child(e)
	_brood.append(e)
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -6.0, 0.55)
	if NoiseMgr.is_server():
		e.wake()

@rpc("authority", "call_local", "reliable")
func _clear_brood() -> void:
	for n in get_parent().get_children():
		if n.name.begins_with("Brood"):
			n.queue_free()
	_brood.clear()

## Trafienie z kierunkiem (bullet.gd): pocisk z góry pod stromym kątem trafia
## w pancerny grzbiet — 20% obrażeń i iskra. Z ziemi (poziomo / w górę) pełne.
func take_bullet_dir(from_pos: Vector2, dmg: float, dir: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	if state == State.AWAKE and dir.y > ARMOR_DOWN and from_pos.y < global_position.y - 26.0:
		dmg *= ARMOR_MULT
		_armor_fx.rpc(from_pos)
	take_bullet(from_pos, dmg)

@rpc("authority", "call_local", "unreliable")
func _armor_fx(pos: Vector2) -> void:
	# rykoszet z grzbietu — dźwięk co najwyżej co 120 ms, iskra zawsze
	var now := Time.get_ticks_msec()
	if now - _armor_snd_ms > 120:
		_armor_snd_ms = now
		Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -12.0, 1.2)
	_burst(pos, Color(1.0, 0.85, 0.4), 6)

func _burst(pos: Vector2, col: Color, n: int) -> void:
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = n
	fx.lifetime = 0.35
	fx.explosiveness = 1.0
	fx.spread = 180.0
	fx.initial_velocity_min = 30.0
	fx.initial_velocity_max = 90.0
	fx.gravity = Vector2(0, 300)
	fx.color = col
	fx.material = Lights.unshaded()
	get_parent().add_child(fx)
	fx.global_position = pos
	get_tree().create_timer(0.8).timeout.connect(fx.queue_free)

func take_bullet(_from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server():
		return
	if state != State.AWAKE:
		# śpiąca matka — twarda skorupa, pocisk rykoszetuje
		if state == State.DORMANT:
			Audio.play_variant_at("ricochet", 2, global_position, Audio.BUS_WORLD, -16.0)
		return
	hp -= dmg
	_flash = 0.08
	if not enraged and hp <= max_hp * 0.5:
		enraged = true
		_brood_t = minf(_brood_t, 1.0)
		NoiseMgr.add_noise(N_SCREAM * 0.5, global_position)
		_event.rpc("enrage")
	if hp <= 0.0:
		_die()
	else:
		_send_state(false)

func _die() -> void:
	state = State.DEAD
	winding = false
	hp = 0.0
	NoiseMgr.add_noise(N_DEATH, global_position)
	# potomstwo usycha razem z matką
	for b in _brood:
		if is_instance_valid(b) and b.alive:
			b.take_bullet(global_position, 999.0)
	_brood.clear()
	print("[BOSS] Żyła nie żyje")
	_event.rpc("death")
	_send_state(true)
	died.emit()

# ---------------------------------------------------------------- sieć

func _send_state(now: bool) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	if not now and _net_t > 0.0:
		return
	_net_t = 0.1
	_sync.rpc(state, hp, max_hp, winding, enraged, nests_left, spitting)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(s: int, h: float, mh: float, w: bool, en: bool, nl: int, sp: bool) -> void:
	spitting = sp
	if h < hp - 0.01:
		_flash = 0.08
	state = s
	hp = h
	max_hp = mh
	winding = w
	enraged = en
	if nl < nests_left:
		_flinch = 0.6
	nests_left = nl
	# po restarcie misji klient musi znów zobaczyć matkę (śmierć ją ukryła)
	if s != State.DEAD and not visible:
		visible = true
		($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)

## Jednorazowe efekty na każdym peerze.
@rpc("authority", "call_local", "reliable")
func _event(kind: String) -> void:
	match kind:
		"awaken":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, 0.0, 0.55)
			Audio.sting(2)
			_shake_near(5.0)
		"windup":
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -2.0, 0.75)
		"spit_windup":
			# bulgot nabrzmiewania — inny niż ryk macki, żeby dało się je rozróżnić
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -4.0, 1.35)
		"enrage":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -2.0, 0.7)
			_shake_near(3.0)
		"death":
			Audio.play_variant_at("explosion", 2, global_position, Audio.BUS_WORLD, 0.0, 0.6)
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -2.0, 0.45)
			_shake_near(7.0)
			Feel.hitstop(0.12)
			_death_fx()
			visible = false
			($CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)

func _shake_near(amount: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 400.0:
			Feel.shake(amount)

func _death_fx() -> void:
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = 90
	fx.lifetime = 1.4
	fx.explosiveness = 0.95
	fx.direction = Vector2(0, -1)
	fx.spread = 80.0
	fx.initial_velocity_min = 60.0
	fx.initial_velocity_max = 220.0
	fx.gravity = Vector2(0, 380)
	fx.scale_amount_min = 1.5
	fx.scale_amount_max = 3.5
	fx.color = Color(0.55, 0.12, 0.16)
	fx.material = Lights.unshaded()
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector2(0, -20)
	get_tree().create_timer(2.0).timeout.connect(fx.queue_free)

# ---------------------------------------------------------------- rysowanie

func _process(_delta: float) -> void:
	if not visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	_light.energy = (0.9 if awake else 0.35) + 0.25 * sin(t * (5.0 if enraged else 2.0))
	queue_redraw()
	_overlay.queue_redraw()

## Splot: kilka mas + macki. Cieniowane — w mroku widać kształt dopiero w świetle.
func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	var base := Color(0.30, 0.10, 0.14) if awake else Color(0.22, 0.10, 0.14)
	if _flash > 0.0:
		base = Color.WHITE
	var sh := Vector2(sin(t * 40.0), 0) * (2.0 if _flinch > 0.0 else 0.0)
	var breathe := 1.0 + 0.04 * sin(t * (3.0 if awake else 1.2))
	if spitting:
		breathe = 1.08 + 0.05 * sin(t * 30.0)     # nabrzmiewa przed pluciem
	draw_circle(Vector2(0, -18) + sh, 26.0 * breathe, base)
	draw_circle(Vector2(-26, -10) + sh, 16.0 * breathe, base.darkened(0.15))
	draw_circle(Vector2(26, -10) + sh, 16.0 * breathe, base.darkened(0.1))
	draw_circle(Vector2(-12, -38) + sh, 12.0 * breathe, base.lightened(0.05))
	draw_circle(Vector2(14, -36) + sh, 11.0 * breathe, base.lightened(0.03))
	# macki
	var n := 6
	for i in n:
		var a := -PI + PI * (i + 0.5) / n
		var ln := 30.0 + (14.0 if awake else 4.0) + 6.0 * sin(t * 2.0 + i)
		var p0 := Vector2(cos(a) * 20.0, -14.0 + sin(a) * 14.0)
		var p1 := p0 + Vector2(cos(a), sin(a) * 0.6) * ln + Vector2(sin(t * 3.0 + i) * 4.0, 0)
		draw_line(p0 + sh, p1 + sh, base.darkened(0.2), 4.0)
	# pancerny grzbiet: płyty na górze splotu (pociski z góry rykoszetują)
	var plate := Color(0.30, 0.27, 0.25) if _flash <= 0.0 else Color.WHITE
	for i in 5:
		var a := PI * (1.15 + 0.175 * i)
		var c := Vector2(cos(a) * 24.0, -18.0 + sin(a) * 24.0) * breathe + sh
		draw_circle(c, 7.0, plate)
		draw_circle(c + Vector2(0, -1.5), 4.5, plate.lightened(0.12))
	# paszcza — przy ziemi, z przodu: tu trafia się z dołu
	draw_circle(Vector2(0, -8) + sh, 9.0 * breathe, Color(0.12, 0.02, 0.04))

## Żyły (stan gniazd i przebudzenie), macka zapowiedzi ataku — unshaded.
func _draw_overlay(ov: Node2D) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	var pulse := 0.5 + 0.5 * sin(t * (6.0 if enraged else (3.0 if awake else 1.5)))
	# śpiąca: po jednej żyle na żyjące gniazdo (odnóża), obudzona: wszystkie żarzą się
	var veins := 3 if awake else nests_left
	var vcol := Color(1.0, 0.35, 0.2, (0.45 + 0.5 * pulse) if awake else (0.25 + 0.25 * pulse))
	var pts := [Vector2(-14, -22), Vector2(4, -30), Vector2(18, -16)]
	for i in 3:
		var c := vcol if i < veins else Color(0.3, 0.1, 0.1, 0.3)
		ov.draw_line(Vector2(0, -12), pts[i], c, 2.0)
		ov.draw_circle(pts[i], 2.2, c)
	# paszcza żarzy się — słaby punkt; przy pluciu jaskrawozielona
	var maw := Color(0.55, 1.0, 0.3, 0.6 + 0.4 * pulse) if spitting else Color(1.0, 0.35, 0.2, (0.35 + 0.3 * pulse) if awake else 0.12)
	ov.draw_circle(Vector2(0, -8), 4.5 if not spitting else 6.5, maw)
	if winding:
		# macka unosi się nad graczem: czerwony łuk = „uciekaj"
		var r := LASH_RANGE_X
		ov.draw_arc(Vector2(0, -10), r, PI * 1.05, PI * 1.95, 24, Color(1.0, 0.15, 0.1, 0.4 + 0.5 * pulse), 2.0)
