extends RigidBody2D
## Obiekt fizyczny (1.5): skrzynia albo beczka. Symulacja TYLKO na serwerze,
## klienci trzymają ciało zamrożone (kinematyczne) i dostają pozycję/obrót.
##
## Po co w grze o hałasie: upadek z wysokości robi HAŁAS w miejscu upadku —
## zepchnięta z kładki skrzynia to wabik (§8.4 bez ładunku Q). Beczka po
## kilku trafieniach wybucha: rani wszystko w promieniu, odrzuca obiekty,
## odpala sąsiednie beczki — i budzi okolicę (+15) — i zostaje po niej osmalony wrak. Skrzynia (DESTRUCTION_PLAN.md D1)
## po kilku trafieniach pęka: drzazgi z pre-fraktury desek, hałas, czasem złom albo bateria.
##
## W grupie „enemies": pociski (projectile.gd), reset po wipe i po misji obejmują
## obiekty bez osobnego kodu; is_threat = false, więc boty do nich nie strzelają.

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const LAYER := 32
const IMPACT_SPEED := 150.0       ## px/s — szybciej = łoskot (hałas)
const N_IMPACT := 4.0
const BARREL_HP := 30.0
const BLAST_R := 64.0
const BLAST_DMG := 70.0
const N_BLAST := 15.0
const BULLET_PUSH := 7.0          ## impuls na punkt obrażeń pocisku
const CRATE_HP := 40.0            ## skrzynia: pistolet 5 trafień, maczeta 2 ciosy; kilof, granat, wybuch beczki, szarża Wołka i Rzeźnika — od razu
const N_CRATE_BREAK := 4.0        ## hałas pęknięcia skrzyni (jak deski w `breakable.gd`)
const CRATE_SCRAP := 0.6          ## szansa na złom 1–2 ze skrzyni (DESTRUCTION_PLAN.md decyzja 3; × Difficulty „drops”, do strojenia)
const CRATE_BATTERY := 0.05       ## szansa na baterię 4,5 V ze skrzyni
const CRATE_CHUNKS := 6           ## drzazg z pre-fraktury `planks` (widok 3D `mirror_chunk`)
const CRATE_CHIPS := 8            ## drobnych wiórów
const WOOD := Color(0.42, 0.3, 0.18)
const SYNC_DT := 0.05

@export var kind := "crate"

var hp := BARREL_HP
var exploded := false
## Beczka po wybuchu (D1): zostaje wrak — widok 3D rysuje go zgniecionego i osmalonego na podłożu pod miejscem wybuchu; bez kolizji
## i obrażeń jak dotąd (`exploded`), wipe przywraca całą beczkę.
var wreck := false
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
	hp = max_hp()
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
	if Sprites.newitem and ItemsHd.has(kind):
		ItemsHd.make(kind, self)                                  # HD: skrzynia/beczka z mapą normalnych; stopy w (0, 0) jak w kształcie kolizji
	elif Sprites.has("objects"):
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
	wreck = false
	hp = max_hp()
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
	wreck = false
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
			if not p.dead and p.hurt_point(global_position).distance_to(global_position) < 11.0:
				p.deliver_hit(1, global_position, "prop")
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

func max_hp() -> float:
	return CRATE_HP if kind == "crate" else BARREL_HP

## Obrażenia z broni (combat.gd): skrzynia = drewno, beczka = blacha. Płomień tylko popycha (palenie skrzyń — osobno).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or exploded:
		return {}
	var was_exploded := exploded
	if String(info.get("type", "")) == "fire":
		apply_impulse((info["dir"] as Vector2) * float(info["amount"]) * BULLET_PUSH, (info["pos"] as Vector2) - global_position)
	else:
		take_bullet_dir(info["pos"], float(info["amount"]), info["dir"])
	return {"hit": true, "dealt": info["amount"], "killed": exploded and not was_exploded,
		"mat": Arsenal.Mat.WOOD if kind == "crate" else Arsenal.Mat.METAL}

func take_bullet_dir(from_pos: Vector2, dmg: float, dir: Vector2) -> void:
	if not NoiseMgr.is_server() or exploded:
		return
	apply_impulse(dir * dmg * BULLET_PUSH, from_pos - global_position)
	hp -= dmg
	if hp > 0.0:
		return
	if kind == "barrel":
		explode()
	else:
		shatter(from_pos)

func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	take_bullet_dir(from_pos, dmg, (global_position - from_pos).normalized())

## Łoskot przy uderzeniu z prędkością > IMPACT_SPEED — hałas w miejscu upadku.
func _on_body_entered(_body: Node) -> void:
	if not NoiseMgr.is_server() or exploded or _prev_speed < IMPACT_SPEED:
		return
	var k := clampf(_prev_speed / 400.0, 0.4, 1.0)
	NoiseMgr.add_noise(N_IMPACT * k * 1.5, global_position, "prop")
	_impact_fx.rpc(global_position, k)

@rpc("authority", "call_local", "unreliable")
func _impact_fx(pos: Vector2, k: float) -> void:
	if kind == "crate":
		Audio.play_variant_at("wood_hit", 3, pos, Audio.BUS_WORLD, lerpf(-12.0, -2.0, k), 0.8)      # skrzynia spada: cięższy stuk drewna (B3)
	else:
		Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, lerpf(-10.0, 0.0, k), 0.6)
	Vfx.dust(get_parent(), pos, k)

# ---------------------------------------------------------------- wybuch

func explode() -> void:
	if exploded or not NoiseMgr.is_server():
		return
	exploded = true
	var pos := global_position + Vector2(0, -8)
	NoiseMgr.add_noise(N_BLAST, pos, "prop")
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
			elif e.kind == "crate" and not e.exploded and d < BLAST_R * 0.6:
				e.shatter(pos)                                    # skrzynia tuż przy beczce pęka, dalsza tylko odlatuje
		elif e.has_method("take_bullet"):
			e.take_bullet(pos, BLAST_DMG * (1.0 - 0.5 * d / BLAST_R))
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and p.hurt_point(pos).distance_to(pos) <= BLAST_R:
			p.deliver_hit(1, pos, "prop")
	_explode_fx.rpc(pos, _floor_below(global_position))

## `at` — gdzie leży wrak (podłoże pod beczką, liczone na serwerze: w reakcji łańcuchowej beczka wybucha w locie).
@rpc("authority", "call_local", "reliable")
func _explode_fx(pos: Vector2, at: Vector2) -> void:
	_gone(at)
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

# ---------------------------------------------------------------- pęknięcie skrzyni (DESTRUCTION_PLAN.md D1)

## Serwer: skrzynia pęka — hałas, łup (złom 1–2, rzadko bateria; nie w Nocnym Dyżurze), 1–2 deski do zapasu drużyny na barykady
## (level.gd `add_planks`, D2b — także w Nocnym Dyżurze), drzazgi u wszystkich. `from_pos` — skąd przyszło
## uderzenie (drzazgi lecą od niego); znika jak wybuchła beczka (`exploded`), wraca przy wipe'ie (`reset_enemy`).
func shatter(from_pos := Vector2.INF) -> void:
	if exploded or not NoiseMgr.is_server():
		return
	exploded = true
	var pos := global_position + Vector2(0, -7)
	NoiseMgr.add_noise(N_CRATE_BREAK, pos, "prop")
	var scrap := 0
	var battery := false
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and not NightShift.active:
		if Scrap.enabled() and randf() < minf(1.0, CRATE_SCRAP * Difficulty.m("drops")):
			scrap = randi_range(1, 2)
			lvl.spawn_item("scrap", 0, pos, scrap)
		if randf() < minf(1.0, CRATE_BATTERY * Difficulty.m("drops")):
			battery = true
			lvl.spawn_item("battery", 0, pos + Vector2(4, 0))
	var planks := 0
	if lvl != null and lvl.has_method("add_planks"):
		planks = randi_range(1, 2)
		lvl.add_planks(planks)
	SessionLog.event("crate", {"pos": SessionLog.xy(pos), "scrap": scrap, "battery": battery, "planks": planks, "noise": roundi(NoiseMgr.level)})
	var away := 0.0 if from_pos == Vector2.INF else signf(global_position.x - from_pos.x)
	_shatter_fx.rpc(pos, rotation, away)

@rpc("authority", "call_local", "reliable")
func _shatter_fx(pos: Vector2, rot: float, away: float) -> void:
	_gone()
	var parent := get_parent()
	Audio.play_variant_at("wood_break", 3, pos, Audio.BUS_WORLD, -2.0)       # B3: trzask drewna (dawniej metalowe drzwi i skrzypienie)
	for ch in chunk_plan(_seed(), away):
		var at: Vector2 = pos + (ch[0] as Vector2).rotated(rot)
		var sz: float = ch[2]
		var b := Vfx.debris(parent, at, ch[1], Vector2(sz, sz * 0.3), WOOD, 0.15, 6.0)
		if b != null and Vfx.view3d != null and is_instance_valid(Vfx.view3d):
			Vfx.view3d.call("mirror_chunk", b, "planks", sz, int(ch[3]))
	for i in CRATE_CHIPS:
		Vfx.debris(parent, pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
			Vector2(randf_range(-70.0, 70.0) + away * 30.0, randf_range(-110.0, -30.0)), Vector2(2, 1), WOOD.lightened(0.2))
	Vfx.dust(parent, pos, 0.8)

## Drzazgi skrzyni: [przesunięcie od środka, prędkość, długość px, kształt] — z ziarna mapy i nazwy, u każdego peera te same.
## `away` (−1 / 0 / 1): strona, w którą odlatują (od uderzenia).
func chunk_plan(seed_v: int, away := 0.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array = []
	for i in CRATE_CHUNKS:
		var off := Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
		var vel := Vector2(off.x * rng.randf_range(8.0, 16.0) + away * rng.randf_range(30.0, 70.0), rng.randf_range(-120.0, -40.0))
		out.append([off, vel, rng.randf_range(6.0, 10.0), rng.randi()])
	return out

func _seed() -> int:
	var lvl := get_tree().get_first_node_in_group("level")
	return hash("%s:%s" % [String(lvl.get("map_id")) if lvl != null else "", String(name)])

## Zniknięcie bez efektów: po pęknięciu, po wybuchu i u dołączającego (`send_state_to`). Beczka zostaje wrakiem (`wreck`) w punkcie `at`
## (bez niego — na podłożu pod sobą).
func _gone(at := Vector2.INF) -> void:
	exploded = true
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("freeze", true)
	if kind == "barrel":
		wreck = true
		var p := _floor_below(global_position) if at == Vector2.INF else at
		_remote_pos = p                                    # klient i tak dociąga do `_remote_pos` (`_physics_process`)
		_remote_rot = 0.0
		set_deferred("global_position", p)
		set_deferred("rotation", 0.0)

## Podłoże (grunt albo kładka) pod punktem `p`, do 20 kafli niżej; bez podłoża — sam punkt.
func _floor_below(p: Vector2) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(p + Vector2(0, -4), p + Vector2(0, 320), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p

## Dołączający gracz: rozbita skrzynia znika u niego bez dźwięku, wybuchła beczka zostaje wrakiem tam, gdzie u serwera (level.gd `send_walls_to`).
func send_state_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and exploded:
		_gone_rpc.rpc_id(peer_id, global_position)

@rpc("authority", "call_remote", "reliable")
func _gone_rpc(at: Vector2) -> void:
	_gone(at)
