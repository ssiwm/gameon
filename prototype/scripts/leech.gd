extends CharacterBody2D
## Pijawka — boss misji B1 (GDD §7.1, §9 B1). Żyje pod powierzchnią zalanego basenu areny: ZANURZONA jest prawie niewrażliwa (5%)
## i niewidoczna — jej cień ujawnia dopiero światło (flara w promieniu LIGHT_REVEAL_R albo snop latarki), wtedy dostaje pełne obrażenia.
## Płynie pod najbliższym graczem stojącym w wodzie; pod nim robi ZAPOWIEDŹ (kręgi na wodzie), potem WYNURZA się, rani (1 HP) i zostaje
## na chwilę odsłonięta — wtedy też dostaje pełne obrażenia. Gracze na kładkach nad basenem są poza zasięgiem.
##
## Faza A (rdzeń): zasadzka z obrażeniami, 3 fazy HP (tempo i cooldowny), śmierć otwiera ekstrakcję. Chwyt i QTE (faza B), przyzywanie
## Trzosków i podwójna zasadzka (faza C) dołożone później. Interfejs jak u Żyły (boss.gd): hp / max_hp / phase / died / is_alive(),
## więc pasek bossa w HUD-zie i mission.gd działają bez zmian. Symulacja TYLKO na serwerze; klienci dostają stan przez _sync i _event.

signal died

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const NightShift := preload("res://scripts/night_shift.gd")

enum State { DORMANT, AWAKE, DEAD }
enum Mode { SUB, WIND, UP, GRAB }         ## zanurzona / zapowiedź zasadzki / wynurzona / trzyma ofiarę (QTE drużyny)

const BASE_HP := 600.0
const HP_PER_EXTRA_HUMAN := 200.0
const SUB_MULT := 0.05                    ## zanurzona i nieoświetlona
const SPEED := [105.0, 140.0, 175.0]      ## px/s w fazach 1–3
const WINDUP := [0.85, 0.7, 0.55]         ## zapowiedź zasadzki (s)
const UP_TIME := [1.7, 1.5, 1.3]          ## jak długo wynurzona i odsłonięta
const AMBUSH_CD := [1.8, 1.3, 0.9]        ## przerwa po zasadzce
const STRIKE_HALF_X := 24.0               ## zasięg poziomy ugryzienia
const STRIKE_Y := 20.0                    ## ile nad poziomem wody gracz jest jeszcze w zasięgu
const LIGHT_REVEAL_R := 150.0             ## flara w tym promieniu ujawnia cień
const POOL_FLOOR_TOL := 8.0               ## gracz stoi „w wodzie", gdy jego stopy są przy poziomie dna basenu
const N_AMBUSH := 3.0
const N_DEATH := 18.0
const NOISE_FOLLOW_R := 260.0
const MINION_EVERY := [0.0, 16.0, 10.0]  ## co ile s dosyła Trzoski w fazie 2 / 3 (0 = faza 1: bez Trzosków)
const MINION_MAX := [0, 3, 4]             ## ile Trzosków naraz (+1 za dodatkowego człowieka)
const SECOND_STRIKE_MIN_DX := 40.0        ## drugi punkt zasadzki (faza 3) co najmniej tyle px od pierwszego
const GRAB_TIME := 4.0                    ## tyle trwa wciąganie; potem ofiara trafia pod wodę (down)
const GRAB_FRAC := 0.12                   ## ułamek maks. HP, który drużyna musi zadać w tym oknie, żeby Pijawka puściła
const GRAB_MELEE_MULT := 2.0              ## cios chwyconego (maczeta) liczy się do uwolnienia podwójnie
const GRAB_CD := [3.0, 2.4, 1.8]          ## przerwa po chwycie (puszczonym albo dokończonym)

## Pola, których oczekują wspólne systemy wrogów (boty, haki, testy) — Pijawka udaje „wroga": zapowiedź, żywy, aktywny.
var kind := "leech"
var winding: bool:
	get:
		return mode == Mode.WIND
var alive: bool:
	get:
		return state != State.DEAD
var active: bool:
	get:
		return state == State.AWAKE

var boss_name := "THE LEECH"
var boss_hint := "It hides under the water. Light reveals its shadow — throw a flare (F) or use the flashlight (L)"
var state: int = State.DORMANT
var mode: int = Mode.SUB
var hp := BASE_HP
var max_hp := BASE_HP
var phase := 1
var revealed := false                      ## cień widoczny (synchronizowane) — rysowanie i obrażenia
var pool_x0 := 0.0                         ## zakres basenu (px), ustawia level.gd z danych mapy
var pool_x1 := 0.0
var surf_y := 0.0                          ## poziom dna basenu (y stóp postaci)
var home_x := 0.0

var grab_victim_id := 0                    ## player_id chwyconego (synchronizowane do HUD), 0 = nikt
var grab_progress := 0.0                   ## 0..1: ile z wymaganych obrażeń drużyna już zadała
var grab_time_left := 0.0
var _grab_victim: Node2D = null            ## serwer
var _grab_dmg := 0.0
var second_x := -1.0                       ## faza 3: drugi punkt zasadzki (px; < 0 = brak) — zapowiedź na wodzie, ugryzienie bez chwytu
var _minions: Array[Node] = []             ## serwer: Trzoski z brzegów (żywe)
var _minion_serial := 0
var _minion_t := 0.0
var _t_mode := 0.0
var _cd := 0.0
var _target_x := 0.0
var _reveal_t := 0.0
var _net_t := 0.0
var _flash := 0.0
var _x_srv := 0.0
var _have_srv := false
var _show := 0.0                           ## wygładzone ujawnienie 0..1 (rysowanie)
var _light: PointLight2D
var _shape: CollisionShape2D
var _rect := RectangleShape2D.new()
var _ripple_t := 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	collision_layer = 4
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.shape = _rect
	add_child(_shape)
	_set_hitbox(false)
	home_x = position.x
	surf_y = position.y
	_x_srv = position.x
	_light = Lights.make_light(Lights.radial(), 2.2, Color(0.4, 0.8, 0.85), 0.0, false)
	_light.position = Vector2(0, -10)
	add_child(_light)

func is_threat() -> bool:
	return state == State.AWAKE

func is_alive() -> bool:
	return state != State.DEAD

func body_center() -> Vector2:
	return global_position + Vector2(0, -8 if mode == Mode.SUB else -16)

func _set_hitbox(up: bool) -> void:
	_rect.size = Vector2(44, 34) if up else Vector2(44, 14)
	_shape.position = Vector2(0, -17) if up else Vector2(0, -3)

# ---------------------------------------------------------------- misja (serwer)

func _humans() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			n += 1
	return n

func awaken() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	max_hp = (BASE_HP + HP_PER_EXTRA_HUMAN * maxi(0, _humans() - 1)) * Difficulty.m("boss_hp") * NightShift.hp_mult()
	hp = max_hp
	state = State.AWAKE
	phase = 1
	mode = Mode.SUB
	_cd = 2.0
	NoiseMgr.add_noise(6.0, global_position)
	print("[BOSS] Pijawka budzi się, HP=%.0f" % max_hp)
	_event.rpc("awaken")
	_send_state(true)

func on_nest_lost(_left: int) -> void:
	pass                                   # zgodność z mission.gd (gniazda to sprawa Żyły)

func reset_enemy() -> void:
	if _grab_victim != null and is_instance_valid(_grab_victim):
		_grab_victim.deliver_grab(false, Vector2.ZERO)
	_grab_victim = null
	grab_victim_id = 0
	grab_progress = 0.0
	second_x = -1.0
	if NoiseMgr.is_server():
		if NoiseMgr.has_network():
			_clear_minions.rpc()
		else:
			_clear_minions()
	state = State.DORMANT
	mode = Mode.SUB
	hp = BASE_HP
	max_hp = BASE_HP
	phase = 1
	revealed = false
	position.x = home_x
	_x_srv = home_x
	_set_hitbox(false)
	visible = true
	_shape.set_deferred("disabled", false)
	if NoiseMgr.is_server():
		_send_state(true)

# ---------------------------------------------------------------- symulacja

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if not NoiseMgr.is_server():
		_client_tick(delta)
		return
	if state == State.AWAKE:
		_tick_reveal(delta)
		_tick_mode(delta)
		_tick_minions(delta)
	_net_t -= delta
	if _net_t <= 0.0:
		_send_state(false)

func _in_pool(p: Node2D) -> bool:
	return p.global_position.x >= pool_x0 and p.global_position.x <= pool_x1 and absf(p.global_position.y - surf_y) <= POOL_FLOOR_TOL

func _best_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion() or not _in_pool(p):
			continue
		var d := absf(p.global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = p
	return best

## Cień jest widoczny, gdy pływa w świetle flary / latarki albo gdy jest wynurzona.
func _tick_reveal(delta: float) -> void:
	_reveal_t -= delta
	if _reveal_t > 0.0:
		return
	_reveal_t = 0.15
	var lit := mode != Mode.SUB
	if not lit:
		var pt := Vector2(global_position.x, surf_y - 4.0)
		for f in get_tree().get_nodes_in_group("flares"):
			if is_instance_valid(f) and (f as Node2D).global_position.distance_to(pt) < LIGHT_REVEAL_R:
				lit = true
				break
		if not lit and Lights.flashlight_on(pt, get_tree(), get_world_2d().direct_space_state) != null:
			lit = true
	revealed = lit

func _tick_mode(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	var ph := clampi(phase - 1, 0, 2)
	match mode:
		Mode.SUB:
			var tgt := _best_target()
			if tgt != null:
				_target_x = tgt.global_position.x
			elif NoiseMgr.last_noise_pos.distance_to(global_position) < NOISE_FOLLOW_R and NoiseMgr.level > 5.0:
				_target_x = NoiseMgr.last_noise_pos.x
			else:
				_target_x = global_position.x
			_target_x = clampf(_target_x, pool_x0, pool_x1)
			var dx := _target_x - global_position.x
			var step := minf(absf(dx), float(SPEED[ph]) * delta)
			global_position.x = clampf(global_position.x + signf(dx) * step, pool_x0, pool_x1)
			if tgt != null and absf(dx) < 12.0 and _cd <= 0.0:
				mode = Mode.WIND
				_t_mode = float(WINDUP[ph])
				second_x = _pick_second_x(tgt) if phase >= 3 else -1.0
				_event.rpc("windup")
		Mode.WIND:
			_t_mode -= delta
			if _t_mode <= 0.0:
				_surface()
		Mode.GRAB:
			_t_mode -= delta
			grab_time_left = maxf(0.0, _t_mode)
			var need := max_hp * GRAB_FRAC
			grab_progress = clampf(_grab_dmg / need, 0.0, 1.0)
			if _grab_victim == null or not is_instance_valid(_grab_victim) or _grab_victim.dead:
				_release(true)                       # ofiara padła z innej przyczyny albo zniknęła — nic nie trzymamy
			elif _grab_dmg >= need:
				_release(true)
			elif _t_mode <= 0.0:
				_release(false)
		Mode.UP:
			_t_mode -= delta
			if _t_mode <= 0.0:
				mode = Mode.SUB
				_set_hitbox(false)
				_cd = float(AMBUSH_CD[ph])
				_event.rpc("dive")

## Trzoski wychodzące z wody na brzegach: co MINION_EVERY[faza] s para, do limitu żywych.
func _tick_minions(delta: float) -> void:
	_minions = _minions.filter(func(b: Node) -> bool: return is_instance_valid(b) and b.alive)
	var ph := clampi(phase - 1, 0, 2)
	if float(MINION_EVERY[ph]) <= 0.0:
		return
	_minion_t -= delta
	if _minion_t > 0.0:
		return
	_minion_t = float(MINION_EVERY[ph])
	if _minions.size() >= int(MINION_MAX[ph]) + maxi(0, _humans() - 1):
		return
	_spawn_minions(2)

func _spawn_minions(n: int) -> void:
	for i in n:
		_minion_serial += 1
		var west := _minion_serial % 2 == 0
		var x := (pool_x0 - 56.0 - float(i) * 14.0) if west else (pool_x1 + 56.0 + float(i) * 14.0)
		var mn_name := "LeechSpawn%d" % _minion_serial
		if NoiseMgr.has_network():
			_spawn_minion.rpc(mn_name, Vector2(x, surf_y))
		else:
			_spawn_minion(mn_name, Vector2(x, surf_y))

@rpc("authority", "call_local", "reliable")
func _spawn_minion(n: String, pos: Vector2) -> void:
	var lvl := get_parent()
	if lvl.has_node(n):
		return
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = "trzosek"
	e.omniscient = true                         # wie, gdzie są gracze — to wsparcie bossa, nie zwykła wataha
	e.position = pos
	lvl.add_child(e)
	if NoiseMgr.is_server():
		_minions.append(e)
		e.wake()
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -6.0, 0.6)

@rpc("authority", "call_local", "reliable")
func _clear_minions() -> void:
	for n in get_parent().get_children():
		if String(n.name).begins_with("LeechSpawn"):
			n.queue_free()
	_minions.clear()

## Faza 3: drugi punkt zasadzki — inny gracz w wodzie, a gdy go nie ma, punkt kilkadziesiąt px od pierwszego.
func _pick_second_x(first: Node2D) -> float:
	var best := -1.0
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == first or p.dead or p.is_queued_for_deletion() or not _in_pool(p):
			continue
		var d := absf(p.global_position.x - global_position.x)
		if d >= SECOND_STRIKE_MIN_DX and d < best_d:
			best_d = d
			best = p.global_position.x
	if best >= 0.0:
		return best
	var side := 1.0 if randf() < 0.5 else -1.0
	return clampf(global_position.x + side * randf_range(70.0, 130.0), pool_x0, pool_x1)

## Wynurzenie: ugryzienie wszystkich w zasięgu (gracze w wodzie pod pyskiem), potem odsłonięta przez UP_TIME.
func _surface() -> void:
	var ph := clampi(phase - 1, 0, 2)
	mode = Mode.UP
	_t_mode = float(UP_TIME[ph])
	_set_hitbox(true)
	NoiseMgr.add_noise(N_AMBUSH, global_position)
	var victim: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion():
			continue
		if absf(p.global_position.x - global_position.x) <= STRIKE_HALF_X and p.global_position.y >= surf_y - STRIKE_Y:
			p.deliver_hit(1, global_position)
			var d := absf(p.global_position.x - global_position.x) + (0.0 if not p.is_bot else 6.0)     # człowiek ma pierwszeństwo przy remisie
			if p.hp > 0 and d < best_d:
				best_d = d
				victim = p
	_event.rpc("surface")
	if second_x >= 0.0:                         # drugi punkt: samo ugryzienie, bez chwytu
		for p in get_tree().get_nodes_in_group("players"):
			if p.dead or p.is_queued_for_deletion() or p == victim:
				continue
			if absf(p.global_position.x - second_x) <= STRIKE_HALF_X and p.global_position.y >= surf_y - STRIKE_Y:
				p.deliver_hit(1, Vector2(second_x, surf_y))
		_event.rpc("surface2")
		second_x = -1.0
	if victim != null and not victim.dead:
		_begin_grab(victim)

## Chwyt: ofiara przypięta przy pysku, Pijawka odsłonięta na GRAB_TIME; drużyna musi zadać GRAB_FRAC maks. HP, żeby ją puściła.
func _begin_grab(victim: Node2D) -> void:
	_grab_victim = victim
	_grab_dmg = 0.0
	mode = Mode.GRAB
	_t_mode = GRAB_TIME
	grab_victim_id = int(victim.player_id)
	victim.deliver_grab(true, Vector2(global_position.x - 16.0, surf_y))
	_event.rpc("grab")

func _release(success: bool) -> void:
	var ph := clampi(phase - 1, 0, 2)
	var victim := _grab_victim
	_grab_victim = null
	grab_victim_id = 0
	grab_progress = 0.0
	grab_time_left = 0.0
	if victim != null and is_instance_valid(victim):
		victim.deliver_grab(false, Vector2.ZERO)
		if not success:
			victim.deliver_hit(99, global_position)        # wciągnięta pod wodę: down (można podnieść)
	mode = Mode.SUB
	_set_hitbox(false)
	_cd = float(GRAB_CD[ph])
	if success:
		global_position.x = clampf(global_position.x + (60.0 if randf() < 0.5 else -60.0), pool_x0, pool_x1)    # cofa się po dostaniu w pysk
	_event.rpc("released" if success else "dragged")

# ---------------------------------------------------------------- obrażenia

## Pełne obrażenia, gdy odsłonięta (wynurzona albo cień w świetle); zanurzona w ciemności — 5%.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	var exposed := mode == Mode.UP or mode == Mode.GRAB or revealed
	var before := hp
	if mode == Mode.GRAB and _grab_victim != null and String(info.get("type", "")) == "melee" and int(info.get("shooter", -1)) == int(_grab_victim.player_id):
		_grab_dmg += float(info["amount"]) * (GRAB_MELEE_MULT - 1.0)       # cios chwyconego liczy się podwójnie (reszta w _hit)
	_hit(float(info["amount"]), exposed)
	return {"hit": true, "dealt": before - hp, "killed": state == State.DEAD,
		"mat": Arsenal.Mat.FLESH if exposed else Arsenal.Mat.WOOD}

func take_bullet_dir(_from_pos: Vector2, dmg: float, _dir: Vector2) -> void:
	if NoiseMgr.is_server():
		_hit(dmg, mode == Mode.UP or mode == Mode.GRAB or revealed)

func take_bullet(_from_pos: Vector2, dmg: float = 8.0) -> void:
	if NoiseMgr.is_server():
		_hit(dmg, mode == Mode.UP or mode == Mode.GRAB or revealed)

func _hit(dmg: float, exposed: bool) -> void:
	if state != State.AWAKE:
		return
	if not exposed:
		dmg *= SUB_MULT
	else:
		_flash = 0.08
		if mode == Mode.GRAB:
			_grab_dmg += dmg
	hp -= dmg
	if phase == 1 and hp <= max_hp * 0.66:
		phase = 2
		_minion_t = float(MINION_EVERY[1])
		_spawn_minions(2)
		_event.rpc("phase2")
	if phase == 2 and hp <= max_hp * 0.33:
		phase = 3
		_minion_t = float(MINION_EVERY[2])
		NoiseMgr.add_noise(NoiseMgr.MAX_LEVEL, global_position)       # krzyk: Uwaga na maksimum
		_spawn_minions(3)
		_event.rpc("phase3")
	if hp <= 0.0:
		_die()
	else:
		_send_state(false)

func _die() -> void:
	if _grab_victim != null:
		var v := _grab_victim
		_grab_victim = null
		grab_victim_id = 0
		if is_instance_valid(v):
			v.deliver_grab(false, Vector2.ZERO)
	state = State.DEAD
	mode = Mode.UP
	second_x = -1.0
	for mn in _minions:
		if is_instance_valid(mn) and mn.alive:
			mn.take_bullet(global_position, 999.0)
	_minions.clear()
	hp = 0.0
	NoiseMgr.add_noise(N_DEATH, global_position)
	print("[BOSS] Pijawka nie żyje")
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		lvl.spawn_health(global_position + Vector2(-20, -30))
		lvl.spawn_health(global_position + Vector2(20, -30))
		if Scrap.enabled():
			lvl.spawn_item("scrap", 0, global_position + Vector2(0, -30), Scrap.BOSS_VALUE)
	_event.rpc("death")
	_send_state(true)
	died.emit()

# ---------------------------------------------------------------- sieć

func _send_state(now: bool) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	if not now and _net_t > 0.0:
		return
	_net_t = 0.066
	_sync.rpc(state, hp, max_hp, mode, revealed, phase, global_position.x, grab_victim_id, grab_progress, grab_time_left, second_x)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(s: int, h: float, mh: float, m: int, rev: bool, ph: int, x: float, gv: int, gp: float, gt: float, sx: float) -> void:
	second_x = sx
	grab_victim_id = gv
	grab_progress = gp
	grab_time_left = gt
	if h < hp - 0.01 and (m == Mode.UP or rev):
		_flash = 0.08
	state = s
	hp = h
	max_hp = mh
	if m != mode:
		_set_hitbox(m == Mode.UP or m == Mode.GRAB)
	mode = m
	revealed = rev
	phase = ph
	_x_srv = x
	_have_srv = true
	if s != State.DEAD and not visible:
		visible = true
		_shape.set_deferred("disabled", false)

func _client_tick(delta: float) -> void:
	if _have_srv:
		global_position.x = lerpf(global_position.x, _x_srv, minf(1.0, 14.0 * delta))

@rpc("authority", "call_local", "reliable")
func _event(kind: String) -> void:
	var pos := global_position
	match kind:
		"awaken":
			Audio.play_variant_at("stalker_growl", 2, pos, Audio.BUS_STALKER, -4.0, 0.5)
			Audio.sting(1)
		"windup":
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 0.0, 0.55)
		"surface":
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 3.0, 0.5)
			Audio.play_variant_at("stalker_growl", 2, pos, Audio.BUS_STALKER, -2.0, 0.8)
			_shake_near(3.0)
		"grab":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, -4.0, 0.9)
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 2.0, 0.45)
			_shake_near(4.0)
		"released":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, -6.0, 1.15)
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 0.0, 0.8)
		"dragged":
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 4.0, 0.4)
			Audio.play_variant_at("stalker_growl", 2, pos, Audio.BUS_STALKER, 0.0, 0.55)
			_shake_near(5.0)
		"dive":
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, -2.0, 0.7)
		"phase2":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, -3.0, 0.7)
			_shake_near(3.0)
		"phase3":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, 0.0, 0.5)
			Audio.sting(2)
			Lights.flicker_until_ms = Time.get_ticks_msec() + 3000
			_shake_near(6.0)
		"surface2":
			Audio.play_variant_at("step_water", 3, Vector2(second_x if second_x >= 0.0 else pos.x, pos.y), Audio.BUS_WORLD, 2.0, 0.55)
		"death":
			Audio.play_variant_at("explosion", 2, pos, Audio.BUS_WORLD, -2.0, 0.6)
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, -2.0, 0.45)
			_shake_near(6.0)
			Feel.hitstop(0.1)
			Vfx.gibs(get_parent(), pos + Vector2(0, -20), Color(0.18, 0.3, 0.26), 22)
			visible = false
			_shape.set_deferred("disabled", true)

func _shake_near(amount: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 400.0:
			Feel.shake(amount)

# ---------------------------------------------------------------- rysowanie

func _process(delta: float) -> void:
	if not visible:
		return
	_show = move_toward(_show, 1.0 if (revealed or mode != Mode.SUB or state == State.DEAD) else 0.0, delta * 3.0)
	_light.energy = 0.55 if (mode == Mode.UP or mode == Mode.GRAB) else 0.0
	_ripple_t += delta
	queue_redraw()

func _draw() -> void:
	if state == State.DORMANT and not revealed:
		_draw_ripples(0.35)
		return
	var t := Time.get_ticks_msec() / 1000.0
	match mode:
		Mode.SUB:
			_draw_ripples(0.6 if state == State.AWAKE else 0.3)
			if _show > 0.02:
				_draw_shadow(_show)
		Mode.WIND:
			if second_x >= 0.0:                                        # faza 3: drugi punkt zasadzki — kręgi w innym miejscu basenu
				draw_set_transform(Vector2(second_x - global_position.x, 0.0), 0.0, Vector2.ONE)
				_draw_ripples(1.0, 1.7)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_ripples(1.0, 1.7)                                  # szybsze, większe kręgi — zaraz się wynurzy
			_draw_shadow(maxf(_show, 0.5))
			draw_circle(Vector2(0, -2), 5.0 + 3.0 * sin(t * 18.0), Color(0.5, 0.65, 0.62, 0.25))
		Mode.UP, Mode.GRAB:
			_draw_body(t)

## Kręgi na powierzchni wody nad Pijawką — jedyna wskazówka w ciemności (ruch zdradza jej położenie).
func _draw_ripples(strength: float, speed := 1.0) -> void:
	for i in 3:
		var ph := fposmod(_ripple_t * speed * 0.9 + float(i) * 0.33, 1.0)
		var rx := 6.0 + ph * 26.0
		draw_arc(Vector2(0, 0), rx, PI, TAU, 14, Color(0.55, 0.75, 0.72, (1.0 - ph) * 0.55 * strength), 1.0)
		draw_arc(Vector2(0, 1), rx * 0.8, 0.0, PI, 12, Color(0.4, 0.6, 0.58, (1.0 - ph) * 0.3 * strength), 1.0)

## Cień pod wodą: ciemna podłużna sylwetka z dwoma bladymi oczami — widoczna tylko w świetle.
func _draw_shadow(a: float) -> void:
	var col := Color(0.03, 0.08, 0.08, 0.85 * a)
	for i in 5:
		var rx := 24.0 - float(i) * 3.5
		var ox := -float(i) * 5.0
		draw_rect(Rect2(ox - rx * 0.5, 2.0 + float(i % 2), rx, 5.0 - float(i) * 0.4), col)
	draw_rect(Rect2(8, 3, 14, 4), col)
	draw_rect(Rect2(15, 3, 2, 2), Color(0.8, 0.95, 0.9, a))
	draw_rect(Rect2(19, 3, 2, 2), Color(0.8, 0.95, 0.9, a))

## Wynurzona: segmentowy tułów wyrastający z wody, głowa z otwartą paszczą pełną zębów.
func _draw_body(t: float) -> void:
	var dead := state == State.DEAD
	var sway := sin(t * 3.0) * (0.5 if dead else 2.5)
	var skin := Color(0.2, 0.3, 0.26)
	var skin_hi := Color(0.34, 0.46, 0.38)
	var belly := Color(0.5, 0.38, 0.32)
	if _flash > 0.0:
		skin = skin.lerp(Color(1, 1, 1), 0.7)
	var segs := 6
	for i in segs:
		var f := float(i) / float(segs - 1)
		var y := -4.0 - f * 26.0
		var x := sway * f
		var r := 11.0 - f * 3.5
		draw_circle(Vector2(x, y), r, skin)
		draw_arc(Vector2(x, y), r - 1.0, PI * 1.1, PI * 1.9, 8, skin_hi, 1.0)
		draw_rect(Rect2(x - r + 2.0, y + r * 0.35, r * 2.0 - 4.0, 1.0), belly)           # pierścienie brzucha
	var hx := sway
	var hy := -34.0
	draw_circle(Vector2(hx, hy), 9.0, skin)
	# paszcza: otwarta, ząbkowana (zamknięta przy śmierci)
	if not dead:
		draw_circle(Vector2(hx + 5.0, hy + 2.0), 6.0, Color(0.55, 0.1, 0.12))
		for k in 5:
			var ang := -0.5 + float(k) * 0.5
			var tip := Vector2(hx + 5.0, hy + 2.0) + Vector2(cos(ang), sin(ang)) * 7.5
			draw_line(Vector2(hx + 5.0, hy + 2.0) + Vector2(cos(ang), sin(ang)) * 4.0, tip, Color(0.92, 0.9, 0.8), 1.0)
		draw_rect(Rect2(hx - 4.0, hy - 4.0, 2.0, 2.0), Color(0.95, 0.9, 0.5))
	# woda tryska wokół
	draw_arc(Vector2(0, 0), 14.0, PI, TAU, 14, Color(0.6, 0.8, 0.78, 0.55), 1.0)
