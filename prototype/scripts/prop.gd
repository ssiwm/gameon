extends RigidBody2D
## Obiekt fizyczny (1.5): skrzynia albo beczka. Symulacja TYLKO na serwerze,
## klienci trzymają ciało zamrożone (kinematyczne) i dostają pozycję/obrót.
##
## Po co w grze o hałasie: upadek z wysokości robi HAŁAS w miejscu upadku —
## zepchnięta z kładki skrzynia to wabik (§8.4 bez ładunku Q). Beczka po
## kilku trafieniach wybucha: rani wszystko w promieniu, odrzuca obiekty,
## odpala sąsiednie beczki — i budzi okolicę (+15).
##
## W grupie „enemies": pociski (projectile.gd), reset po wipe i po misji obejmują
## obiekty bez osobnego kodu; is_threat = false, więc boty do nich nie strzelają.

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")

const LAYER := 32
const IMPACT_SPEED := 150.0       ## px/s — szybciej = łoskot (hałas)
const N_IMPACT := 4.0
const BARREL_HP := 30.0
const BLAST_R := 64.0
const BLAST_DMG := 70.0
const N_BLAST := 15.0
const BULLET_PUSH := 7.0          ## impuls na punkt obrażeń pocisku
const SYNC_DT := 0.05

@export var kind := "crate"

var hp := BARREL_HP
var exploded := false
var _home := Vector2.ZERO
var _prev_speed := 0.0
var _net_t := 0.0
var _remote_pos := Vector2.ZERO
var _remote_rot := 0.0
var _push_t := 0.0
var _spr: Array = []
var _reset_pending := false
## Rzut przez Wołka (enemy.gd): skrzynia leci z prędkością `_throw_vel` i przez `thrown_t` s rani gracza przy kontakcie.
var thrown_t := 0.0
var _throw_pending := false
var _throw_pos := Vector2.ZERO
var _throw_vel := Vector2.ZERO

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("props")
	collision_layer = LAYER
	collision_mask = 1 | 16 | LAYER
	mass = 4.0 if kind == "crate" else 3.0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.05
	physics_material_override = mat
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(14, 14) if kind == "crate" else Vector2(10, 15)
	cs.shape = sh
	cs.position = Vector2(0, -sh.size.y * 0.5)
	add_child(cs)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	_home = global_position
	_remote_pos = global_position
	if Sprites.has("objects"):
		_spr = Sprites.attach(self, "objects")
		Sprites.play(_spr, kind, false)
	_apply_authority()

## Zamrożony u klientów: pozycję dyktuje serwer. Sprawdzane też później —
## w _ready peer bywa jeszcze offline (jak w stalker.gd).
func _apply_authority() -> void:
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = not NoiseMgr.is_server()

func is_threat() -> bool:
	return false

func reset_enemy() -> void:
	exploded = false
	hp = BARREL_HP
	visible = true
	# teleport ciała przez _integrate_forces — samo global_position nadpisuje fizyka
	_reset_pending = true
	freeze = not NoiseMgr.is_server()
	_remote_pos = _home
	_remote_rot = 0.0
	set_deferred("collision_layer", LAYER)
	if NoiseMgr.is_server() and NoiseMgr.has_network():
		_reset_rpc.rpc()

@rpc("authority", "call_remote", "reliable")
func _reset_rpc() -> void:
	exploded = false
	visible = true
	global_position = _home
	rotation = 0.0
	_remote_pos = _home
	_remote_rot = 0.0
	collision_layer = LAYER

## Serwer: ciało zostaje przeniesione do `pos` i wystrzelone z prędkością `vel` (przez _integrate_forces).
func throw_to(pos: Vector2, vel: Vector2) -> void:
	if not NoiseMgr.is_server() or exploded:
		return
	_throw_pending = true
	_throw_pos = pos
	_throw_vel = vel
	thrown_t = 1.6
	sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _throw_pending:
		_throw_pending = false
		state.transform = Transform2D(0.0, _throw_pos)
		state.linear_velocity = _throw_vel
		state.angular_velocity = randf_range(-6.0, 6.0)
	if _reset_pending:
		_reset_pending = false
		state.transform = Transform2D(0.0, _home)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0

func _physics_process(delta: float) -> void:
	if not exploded and freeze != (not NoiseMgr.is_server()):
		_apply_authority()
	if not NoiseMgr.is_server():
		global_position = global_position.lerp(_remote_pos, 0.4)
		rotation = lerp_angle(rotation, _remote_rot, 0.4)
		return
	_prev_speed = linear_velocity.length()
	if thrown_t > 0.0:
		thrown_t = maxf(0.0, thrown_t - delta)
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and (p.global_position + Vector2(0, -8)).distance_to(global_position) < 11.0:
				p.deliver_hit(1, global_position)
				thrown_t = 0.0
				break
	_net_t -= delta
	if _net_t <= 0.0 and NoiseMgr.has_network() and not exploded:
		_net_t = SYNC_DT
		_sync.rpc(global_position, rotation)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(pos: Vector2, rot: float) -> void:
	_remote_pos = pos
	_remote_rot = rot

# ---------------------------------------------------------------- popychanie

const PUSH_SPEED := 45.0          ## px/s — skrzynia sunie wolniej niż chód (95)

## Gracz/bot pcha obiekt w stronę `dir` (−1/1). Ustawiamy prędkość pchania
## zamiast impulsu: impuls z jednej klatki był ~10× za słaby wobec tarcia
## (skrzynia o masie 4 stała w miejscu). Klient → RPC do serwera (20 Hz).
func push(dir: float) -> void:
	if exploded:
		return
	if NoiseMgr.is_server():
		_apply_push(dir)
		return
	_push_t -= get_physics_process_delta_time()
	if _push_t <= 0.0:
		_push_t = 0.05
		_push_rpc.rpc_id(1, signf(dir))

@rpc("any_peer", "call_remote", "unreliable")
func _push_rpc(dir: float) -> void:
	if NoiseMgr.is_server() and not exploded:
		_apply_push(clampf(dir, -1.0, 1.0))

func _apply_push(dir: float) -> void:
	sleeping = false
	if signf(linear_velocity.x) != signf(dir) or absf(linear_velocity.x) < PUSH_SPEED:
		linear_velocity.x = dir * PUSH_SPEED

# ---------------------------------------------------------------- trafienia, upadki

## Obrażenia z broni (combat.gd): skrzynia = drewno, beczka = blacha.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or exploded:
		return {}
	var was_exploded := exploded
	take_bullet_dir(info["pos"], float(info["amount"]), info["dir"])
	return {"hit": true, "dealt": info["amount"], "killed": exploded and not was_exploded,
		"mat": Arsenal.Mat.WOOD if kind == "crate" else Arsenal.Mat.METAL}

func take_bullet_dir(from_pos: Vector2, dmg: float, dir: Vector2) -> void:
	if not NoiseMgr.is_server() or exploded:
		return
	apply_impulse(dir * dmg * BULLET_PUSH, from_pos - global_position)
	if kind == "barrel":
		hp -= dmg
		if hp <= 0.0:
			explode()

func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	take_bullet_dir(from_pos, dmg, (global_position - from_pos).normalized())

## Łoskot przy uderzeniu z prędkością > IMPACT_SPEED — hałas w miejscu upadku.
func _on_body_entered(_body: Node) -> void:
	if not NoiseMgr.is_server() or exploded or _prev_speed < IMPACT_SPEED:
		return
	var k := clampf(_prev_speed / 400.0, 0.4, 1.0)
	NoiseMgr.add_noise(N_IMPACT * k * 1.5, global_position)
	_impact_fx.rpc(global_position, k)

@rpc("authority", "call_local", "unreliable")
func _impact_fx(pos: Vector2, k: float) -> void:
	if kind == "crate":
		Audio.play_variant_at("door", 2, pos, Audio.BUS_WORLD, lerpf(-14.0, -4.0, k), 0.55)
	else:
		Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, lerpf(-10.0, 0.0, k), 0.6)
	Vfx.dust(get_parent(), pos, k)

# ---------------------------------------------------------------- wybuch

func explode() -> void:
	if exploded or not NoiseMgr.is_server():
		return
	exploded = true
	var pos := global_position + Vector2(0, -8)
	NoiseMgr.add_noise(N_BLAST, pos)
	print("[PROP] beczka wybucha w %s" % pos.round())
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		var d: float = (e.global_position + Vector2(0, -8)).distance_to(pos)
		if d > BLAST_R:
			continue
		if e.is_in_group("props"):
			var away: Vector2 = ((e.global_position - pos).normalized() + Vector2(0, -0.6)).normalized()
			e.apply_central_impulse(away * 260.0 * (1.0 - d / BLAST_R + 0.3))
			if e.kind == "barrel" and not e.exploded:
				# reakcja łańcuchowa z krótkim opóźnieniem — widać, jak idzie
				get_tree().create_timer(0.15).timeout.connect(e.explode)
		elif e.has_method("take_bullet"):
			e.take_bullet(pos, BLAST_DMG * (1.0 - 0.5 * d / BLAST_R))
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and (p.global_position + Vector2(0, -8)).distance_to(pos) <= BLAST_R:
			p.deliver_hit(1, pos)
	_explode_fx.rpc(pos)

@rpc("authority", "call_local", "reliable")
func _explode_fx(pos: Vector2) -> void:
	exploded = true
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("freeze", true)
	var parent := get_parent()
	Audio.play_variant_at("explosion", 2, pos, Audio.BUS_WORLD, 2.0, 0.9)
	Vfx.burst(parent, pos, Color(1.0, 0.6, 0.2), 30, 60.0, 220.0, Vector2.UP, 180.0, 200.0, 0.5, Vector2(1.5, 3.0), true)
	Vfx.burst(parent, pos, Color(0.25, 0.24, 0.24, 0.6), 14, 20.0, 60.0, Vector2.UP, 70.0, -40.0, 1.6, Vector2(3.0, 5.0))
	for i in 6:
		Vfx.debris(parent, pos, Vector2(randf_range(-160, 160), randf_range(-260, -90)), Vector2(3, 2),
			Color(0.55, 0.14, 0.1).darkened(randf() * 0.4), 0.3, 14.0)
	# błysk światła — oświetla okolicę na moment (w ciemności to sygnał z daleka)
	var flash := Lights.make_light(Lights.radial(), 7.0, Color(1.0, 0.65, 0.3), 2.2, true)
	parent.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "energy", 0.0, 0.45)
	tw.tween_callback(flash.queue_free)
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and p.global_position.distance_to(pos) < 300.0:
			Feel.shake(5.0)
			Feel.hitstop(0.06)
