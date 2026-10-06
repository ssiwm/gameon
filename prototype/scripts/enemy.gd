extends CharacterBody2D
## Wróg podstawowy: Trzosek (wataha, szybki) i Wołek (tank). GDD §7.1.
## Symulacja TYLKO na serwerze; klienci interpolują pozycję i rysują.
##
## Wróg śpi, dopóki nie usłyszy głośnego zdarzenia (strzał, granat — NIE kroki)
## w swoim promieniu słyszenia albo gracz nie podejdzie za blisko. Dzięki temu
## cisza i skradanie mają realną wartość także wobec zwykłych wrogów (filar 2).

const KINDS := {
	"trzosek": {
		"hp": 30.0, "speed": 88.0, "damage": 1, "windup": 0.28, "reach": 13.0,
		"cooldown": 0.9, "leap": true, "hear": 200.0, "wake_near": 90.0, "sight": 260.0,
		"color": Color(0.62, 0.2, 0.22), "size": Vector2(10, 14), "knock": 70.0, "knock_mult": 1.0, "head": 0.0,
	},
	# Ślepiec (GDD §7.1): nie widzi, tylko słyszy — idzie do źródła hałasu; kucanie i cisza go mijają.
	"slepiec": {
		"hp": 60.0, "speed": 70.0, "damage": 1, "windup": 0.35, "reach": 14.0,
		"cooldown": 1.1, "leap": false, "hear": 300.0, "wake_near": 36.0, "sight": 26.0,
		"keen": true, "min_noise": 0.25, "blind": true,
		"color": Color(0.8, 0.78, 0.76), "size": Vector2(12, 17), "knock": 40.0, "knock_mult": 0.6, "head": 0.0,
	},
	# Podsłuchacz (GDD §7.1): stoi nieruchomo i nasłuchuje; zobaczy albo usłyszy — krzyczy i ściąga hordę.
	"podsluchacz": {
		"hp": 35.0, "speed": 0.0, "damage": 0, "windup": 0.9, "reach": 0.0,
		"cooldown": 6.0, "leap": false, "hear": 170.0, "wake_near": 0.0, "sight": 240.0,
		"color": Color(0.58, 0.5, 0.57), "size": Vector2(12, 24), "knock": 30.0, "knock_mult": 0.5, "head": 0.0,
	},
	"wolek": {
		"hp": 140.0, "speed": 36.0, "damage": 2, "windup": 0.6, "reach": 20.0,
		"cooldown": 1.6, "leap": false, "hear": 150.0, "wake_near": 70.0, "sight": 200.0,
		"color": Color(0.36, 0.27, 0.34), "size": Vector2(20, 26), "knock": 14.0, "knock_mult": 0.2, "head": 0.28,
	},
}

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Nav := preload("res://scripts/nav.gd")

const GRAVITY := 900.0
const MAX_FALL := 620.0
## Kroki (0,25 na tick) nie budzą; każdy strzał tak — także pierwszy z zimnej
## lufy M-83 (0,6). Przy progu 1,0 pojedyncze strzały M-83 były dla wrogów nieme.
const MIN_WAKE_NOISE := 0.5
const AMMO_DROP := {"trzosek": 0.22, "wolek": 0.6, "slepiec": 0.3, "podsluchacz": 0.15}   ## szansa na skrzynkę z amunicją do broni, którą ktoś nosi
const HEALTH_DROP := {"wolek": 0.75}   ## szansa na apteczkę (1.5) — tylko mocniejsi wrogowie
const SIBLING_WAKE_RADIUS := 140.0
const DEATH_FX_COLOR_VAR := 0.15
const BURN_DPS := 8.0
## Percepcja (1.7): wróg goni tylko to, co widzi (promień wzroku + linia bez ściany), albo idzie
## na ostatni znany ślad (hałas, ostatnia pozycja gracza), rozgląda się, a po dłuższym braku
## kontaktu wraca do domu i zasypia. Wcześniej obudzony wróg znał położenie gracza na całej mapie.
const SEARCH_TIME := 3.5         ## s rozglądania się po dojściu na ślad
const GIVE_UP_TIME := 9.0        ## s bez kontaktu, po których porzuca ślad
const HOME_SLEEP_TIME := 1.2     ## s w domu, po których znów zasypia
const PERCEIVE_DT := 0.12        ## co tyle sprawdzamy wzrok (promień)
const CROUCH_SIGHT := 0.6        ## kucającego widać z mniejszej odległości
const JUMP_V := -275.0           ## skok po grafie A* (42 px, tyle co gracz)
const PLATFORM_BIT := 5          ## warstwa kładek w masce (zeskok)
const DROP_TIME := 0.25
## Podsłuchacz: krzyk to hałas (podnosi Uwagę, budzi okolicę) i wskazuje hordzie źródło.
const SCREAM_NOISE := 14.0
const ALARM_R := 420.0           ## wrogowie w tym promieniu dostają ślad do krzyku

@export var kind := "trzosek"

## Nie jest nieśmiertelny, więc boty mogą do niego strzelać, gdy jest aktywny.
var immortal := false
var hp := 30.0
var active := false
var alive := true
var winding := false
var burning := false          ## replikowane wizualnie przez RPC (_ignite_fx); logika tylko na serwerze

var _def: Dictionary
var _home := Vector2.ZERO
var _windup := 0.0
var _windup_target: Node2D = null
var _cd := 0.0
var _leap_cd := 0.0
var _stagger := 0.0
var _burn := 0.0              ## s płonięcia (serwer)
var _panic := 0.0             ## s paniki po podpaleniu (Trzosek ucieka zamiast atakować)
var _flash := 0.0
var _seen_serial := 0
var _net_timer := 0.0
var _remote_pos := Vector2.ZERO
var _max_hp := 30.0
var _overlay: Node2D
var _spr: Array = []
var _facing := 1.0
var _last_x := 0.0
## Percepcja i nawigacja (serwer)
var omniscient := false       ## potomstwo Żyły zawsze zna położenie graczy
var _target: Node2D = null    ## gracz, którego widzi
var _perceive_t := 0.0
var _has_lead := false        ## ma ślad do sprawdzenia
var _last_known := Vector2.ZERO
var _lose_t := 0.0
var _search_t := 0.0
var _home_t := 0.0
var _retreat := 0.0           ## Trzosek odskakuje po ciosie (uderz i uciekaj)
var _path: Array = []
var _path_i := 0
var _repath := 0.0
var _path_goal := Vector2.ZERO
var _drop_t := 0.0
var _blocked := false         ## następny krok grafu to skok, którego nie potrafi
var _scream_cd := 0.0         ## Podsłuchacz: przerwa między krzykami
var _alerted := false         ## Podsłuchacz: już krzyknął (od tej pory boty go widzą jako zagrożenie)
var _ring := 0.0              ## efekt fali krzyku (każdy peer)
var _level_t := 0.0           ## s, przez które cel jest na innym poziomie (histereza: skok gracza to nie zmiana piętra)

func _ready() -> void:
	add_to_group("enemies")
	_def = KINDS.get(kind, KINDS["trzosek"])
	_max_hp = _scaled_hp()
	hp = _max_hp
	Difficulty.changed.connect(_on_difficulty_changed)
	_home = global_position
	_remote_pos = global_position
	_seen_serial = NoiseMgr.noise_serial
	# kształt kolizji per rodzaj (zasób w scenie jest współdzielony — duplikujemy)
	var cs := $CollisionShape2D as CollisionShape2D
	var shape := (cs.shape as RectangleShape2D).duplicate() as RectangleShape2D
	var size: Vector2 = _def["size"]
	shape.size = size
	cs.shape = shape
	cs.position = Vector2(0, -size.y * 0.5)
	# oczy i pasek HP świecą w ciemności — śpiącego wroga widać jako
	# przygaszone oczy, a nie wcale (skradanie musi mieć informację)
	if Sprites.has(kind):
		_spr = Sprites.attach(self, kind)
	_last_x = global_position.x
	_overlay = Lights.add_overlay(self)

## Aktywny, żywy wróg = realne zagrożenie (boty strzelają tylko do takich).
func is_threat() -> bool:
	return alive and active and (kind != "podsluchacz" or _alerted)

func wake() -> void:
	if not NoiseMgr.is_server() or not alive or active:
		return
	active = true
	if not _has_lead:
		var p := _nearest_player()
		if p != null:
			_lead_at(p.global_position)
	# cała wataha budzi się razem
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.has_method("wake") and e.global_position.distance_to(global_position) < SIBLING_WAKE_RADIUS:
			e.wake()

## HP z uwzględnieniem poziomu trudności (difficulty.gd).
func _scaled_hp() -> float:
	return float(_def["hp"]) * Difficulty.m("enemy_hp")

## Zmiana trudności w lobby/na starcie: nietknięty wróg dostaje nowe HP.
func _on_difficulty_changed(_lvl: int) -> void:
	var untouched := is_equal_approx(hp, _max_hp)
	_max_hp = _scaled_hp()
	if untouched:
		hp = _max_hp

## Restart misji (wipe) — wszystko wraca na start.
func reset_enemy() -> void:
	_max_hp = _scaled_hp()
	hp = _max_hp
	active = false
	winding = false
	_windup = 0.0
	_windup_target = null
	_cd = 0.0
	_burn = 0.0
	_panic = 0.0
	_target = null
	_has_lead = false
	_lose_t = 0.0
	_search_t = 0.0
	_retreat = 0.0
	_scream_cd = 0.0
	_alerted = false
	_level_t = 0.0
	_home_t = 0.0
	_path.clear()
	_drop_t = 0.0
	set_collision_mask_value(PLATFORM_BIT, true)
	velocity = Vector2.ZERO
	global_position = _home
	_remote_pos = _home
	_set_alive(true)

func _set_alive(a: bool) -> void:
	alive = a
	visible = a
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", not a)

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if not NoiseMgr.is_server():
		global_position = global_position.lerp(_remote_pos, 0.35)
		return
	if not alive:
		return

	_cd = maxf(0.0, _cd - delta)
	_leap_cd = maxf(0.0, _leap_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_panic = maxf(0.0, _panic - delta)
	_retreat = maxf(0.0, _retreat - delta)
	_tick_drop(delta)
	_tick_burn(delta)
	if not alive:
		return

	if kind == "podsluchacz":
		_listener_tick(delta)
		return

	if not active:
		_check_wake()
		# śpiący wróg stoi i słucha, ale grawitacja działa
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_send_state(delta)
		return

	_listen()
	_perceive(delta)
	var target := _target
	var speed: float = float(_def["speed"]) * Difficulty.m("enemy_speed")
	if _stagger > 0.0:
		speed *= 0.25

	if _windup > 0.0:
		_windup -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _windup <= 0.0:
			_resolve_attack()
	elif target != null and _panic > 0.0:
		# płonący Trzosek ucieka (HKM-9: „strach wśród Trzosków”), nie atakuje
		velocity.x = -signf(target.global_position.x - global_position.x) * speed * 0.9
	elif target != null and _retreat > 0.0:
		# uderz i uciekaj: po ciosie Trzosek odskakuje, więc wataha nie stoi w miejscu
		velocity.x = -signf(target.global_position.x - global_position.x) * speed * 0.8
	elif target != null:
		_chase(target, speed, delta)
		_try_begin_attack(target)
	elif _has_lead:
		_investigate(speed, delta)
	else:
		_return_home(speed, delta)

	_apply_gravity(delta)
	move_and_slide()
	_send_state(delta)

## --- Podsłuchacz -----------------------------------------------------------

## Stoi i czuwa (zawsze „aktywny", ale się nie rusza). Zobaczy gracza albo usłyszy hałas —
## krzyk z zapowiedzią (0,9 s); zabity po cichu (maczeta w plecy) nie krzyczy.
func _listener_tick(delta: float) -> void:
	active = true
	_scream_cd = maxf(0.0, _scream_cd - delta)
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			winding = false
			_scream()
	else:
		_listen()
		_perceive(delta)
		if _target != null or (_has_lead and _lose_t < 0.3):
			_begin_scream()
	_apply_gravity(delta)
	move_and_slide()
	_send_state(delta)

func _begin_scream() -> void:
	if _scream_cd > 0.0 or _windup > 0.0:
		return
	_windup = float(_def["windup"]) * Difficulty.m("enemy_windup")
	winding = true

func _scream() -> void:
	_scream_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	_alerted = true
	_has_lead = false
	NoiseMgr.add_noise(SCREAM_NOISE, global_position)
	# ściąga hordę: wrogowie w promieniu idą do źródła krzyku (śpiących budzi)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or e.kind == "podsluchacz":
			continue
		if e.global_position.distance_to(global_position) < ALARM_R:
			e._lead_at(global_position)
			e.wake()
	if NoiseMgr.has_network():
		_scream_fx.rpc()
	else:
		_scream_fx()

## Krzyk na każdym peerze: dźwięk, fala, lekki wstrząs kamery.
@rpc("authority", "call_local", "reliable")
func _scream_fx() -> void:
	_ring = 0.7
	Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_WORLD, -3.0, 1.35)
	if _local_player_pos().distance_to(global_position) < 300.0:
		Feel.shake(2.2)

## --- percepcja ------------------------------------------------------------

func _lead_at(pos: Vector2) -> void:
	_last_known = pos
	_has_lead = true
	_lose_t = 0.0
	_search_t = 0.0

## Nowy głośny dźwięk w pobliżu odświeża ślad (wróg idzie do źródła, nie do gracza).
func _listen() -> void:
	if NoiseMgr.noise_serial == _seen_serial:
		return
	_seen_serial = NoiseMgr.noise_serial
	var reach := _noise_reach(NoiseMgr.last_noise_amount, 1.4)
	if reach > 0.0 and global_position.distance_to(NoiseMgr.last_noise_pos) < reach:
		_lead_at(NoiseMgr.last_noise_pos)

## Zasięg, z którego wróg usłyszy hałas o danej sile (−1 = za cichy). Ślepiec (`keen`) słyszy
## ciche dźwięki (kroki) z bliska, a głośne z daleka — zasięg rośnie z głośnością.
func _noise_reach(amount: float, mult := 1.0) -> float:
	if amount < float(_def.get("min_noise", MIN_WAKE_NOISE)):
		return -1.0
	var r: float = float(_def["hear"]) * Difficulty.m("enemy_hear") * mult
	if _def.get("keen", false):
		r *= clampf(amount / 1.5, 0.35, 1.5)
	return r

## Najbliższy WIDOCZNY gracz (zasięg wzroku + brak ściany na linii). Co PERCEIVE_DT, nie co klatkę.
func _perceive(delta: float) -> void:
	_perceive_t -= delta
	if _perceive_t > 0.0:
		if _target != null and (not is_instance_valid(_target) or _target.dead):
			_target = null
		return
	_perceive_t = PERCEIVE_DT
	var sight: float = float(_def.get("sight", 240.0)) * Difficulty.m("enemy_hear")
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d >= best_d:
			continue
		if not omniscient:
			if d > sight * (CROUCH_SIGHT if pp.crouching else 1.0) or not _clear_line(pp):
				continue
		best = pp
		best_d = d
	_target = best
	if best != null:
		_lead_at(best.global_position)
	else:
		_lose_t += PERCEIVE_DT

func _clear_line(pp: Node2D) -> bool:
	var h: float = (_def["size"] as Vector2).y * 0.6
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -h), pp.global_position + Vector2(0, -8), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## --- zachowanie bez widocznego celu ----------------------------------------

## Idzie na ostatni ślad, rozgląda się i rezygnuje; po dłuższym braku kontaktu wraca do domu.
func _investigate(speed: float, delta: float) -> void:
	var d := _last_known - global_position
	if absf(d.x) < 10.0 and absf(d.y) < 28.0 or _blocked and _search_t > 0.0:
		velocity.x = 0.0
		_search_t += delta
		if _search_t > SEARCH_TIME:
			_has_lead = false
	else:
		if _blocked:
			_search_t += delta       # stoi pod przeszkodą, której nie przeskoczy — krótko czeka i rezygnuje
			velocity.x = 0.0
		else:
			_steer_to(_last_known, speed * 0.85, delta)
	if _lose_t > GIVE_UP_TIME:
		_has_lead = false

func _return_home(speed: float, delta: float) -> void:
	var d := _home - global_position
	if absf(d.x) < 14.0 and absf(d.y) < 28.0:
		velocity.x = 0.0
		_home_t += delta
		if _home_t > HOME_SLEEP_TIME:
			_home_t = 0.0
			active = false
			winding = false
			_seen_serial = NoiseMgr.noise_serial
	else:
		_home_t = 0.0
		_steer_to(_home, speed * 0.6, delta)

## Pościg za widocznym graczem: na tym samym poziomie prosto (linia czysta), inaczej grafem A*.
func _chase(target: Node2D, speed: float, delta: float) -> void:
	var d := target.global_position - global_position
	_level_t = _level_t + delta if absf(d.y) >= 24.0 else 0.0
	if _level_t > 0.35 and _has_nav():
		_steer_to(target.global_position, speed, delta)
		return
	_blocked = false
	var want := signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
	# rozsuwanie watahy: nie stają w jednym punkcie, tylko w szeregu (można strzelać po kolei)
	if absf(d.x) > float(_def["reach"]):
		want += _separation(speed)
	velocity.x = want
	if is_on_wall() and is_on_floor() and _def["leap"]:
		velocity.y = -230.0

func _separation(speed: float) -> float:
	var push := 0.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or not e.active:
			continue
		var dx: float = global_position.x - e.global_position.x
		if absf(dx) < 9.0 and absf(global_position.y - e.global_position.y) < 12.0:
			push += (signf(dx) if dx != 0.0 else (1.0 if get_instance_id() > e.get_instance_id() else -1.0))
	return clampf(push, -1.0, 1.0) * speed * 0.5

func _has_nav() -> bool:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl != null and lvl.get("nav") != null

## Idzie do celu po grafie nawigacji (nav.gd); blisko celu i na tym samym poziomie — prosto.
func _steer_to(goal: Vector2, speed: float, delta: float) -> void:
	var d := goal - global_position
	var lvl := get_tree().get_first_node_in_group("level")
	var nav = lvl.get("nav") if lvl != null else null
	if nav == null or (absf(d.y) < 20.0 and absf(d.x) < 48.0):
		_blocked = false
		velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
		return
	_repath -= delta
	if is_on_floor() and (_repath <= 0.0 or _path_goal.distance_to(goal) > 40.0):
		_repath = 0.45
		_path_goal = goal
		_path = nav.find_path(global_position, goal)
		_path_i = 1
		_blocked = false
	if _path.size() < 2 or _path_i >= _path.size():
		velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
		return
	if is_on_floor():
		for i in range(_path_i, mini(_path_i + 3, _path.size())):
			if absf(_path[i].pos.x - global_position.x) < 6.0 and absf(_path[i].pos.y - global_position.y) < 20.0:
				_path_i = i + 1
				break
		if _path_i >= _path.size():
			velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
			return
	var step: Dictionary = _path[_path_i]
	var prev: Dictionary = _path[_path_i - 1]
	var sx: float = step.pos.x - global_position.x
	if not is_on_floor():
		velocity.x = signf(sx) * speed if absf(sx) > 3.0 else 0.0
		return
	var px: float = prev.pos.x - global_position.x
	match int(step.kind):
		Nav.Edge.JUMP:
			if absf(px) > 4.0:
				velocity.x = signf(px) * speed
			elif _def["leap"]:
				velocity.y = JUMP_V
				velocity.x = signf(sx) * speed
			else:
				_blocked = true
				velocity.x = 0.0
		Nav.Edge.DROP:
			if absf(px) > 4.0:
				velocity.x = signf(px) * speed
			else:
				velocity.x = 0.0
				_start_drop()
		_:
			velocity.x = signf(sx) * speed if absf(sx) > 3.0 else 0.0

func _start_drop() -> void:
	if _drop_t > 0.0:
		return
	_drop_t = DROP_TIME
	set_collision_mask_value(PLATFORM_BIT, false)
	position.y += 1.0

func _tick_drop(delta: float) -> void:
	if _drop_t <= 0.0:
		return
	_drop_t -= delta
	if _drop_t <= 0.0:
		set_collision_mask_value(PLATFORM_BIT, true)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

## Budzi się od NOWEGO głośnego zdarzenia w promieniu słyszenia
## albo gdy gracz stoi za blisko.
func _check_wake() -> void:
	if NoiseMgr.noise_serial != _seen_serial:
		_seen_serial = NoiseMgr.noise_serial
		var reach := _noise_reach(NoiseMgr.last_noise_amount)
		if reach > 0.0 and global_position.distance_to(NoiseMgr.last_noise_pos) < reach:
			_lead_at(NoiseMgr.last_noise_pos)     # idzie do źródła hałasu, nie wprost do gracza
			wake()
			return
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		# kucający gracz musi podejść bliżej — skradanie się opłaca się
		var near: float = float(_def["wake_near"]) * Difficulty.m("enemy_hear") * (0.5 if pp.crouching else 1.0)
		if global_position.distance_to(pp.global_position) < near:
			wake()
			return
	# „Światło przyciąga wzrok Trzosków" (GDD §8.3): snop latarki na
	# śpiącym wrogu go budzi — świecenie po pokoju ma cenę.
	if not _def.get("blind", false) \
			and Lights.flashlight_on(global_position + Vector2(0, -6), get_tree(), get_world_2d().direct_space_state) != null:
		wake()

func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	return best

func _in_reach(pp: Node2D, slack: float) -> bool:
	var reach: float = _def["reach"] + slack
	return absf(pp.global_position.x - global_position.x) <= reach \
		and absf(pp.global_position.y - global_position.y) <= 18.0

func _try_begin_attack(target: Node2D) -> void:
	if _cd > 0.0 or _windup > 0.0:
		return
	if _in_reach(target, 0.0):
		_windup = float(_def["windup"]) * Difficulty.m("enemy_windup")
		_windup_target = target
		winding = true

func _resolve_attack() -> void:
	winding = false
	var pp := _windup_target
	_windup_target = null
	_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	if kind == "trzosek":
		_retreat = 0.32
	if pp != null and is_instance_valid(pp) and not pp.dead and _in_reach(pp, 6.0):
		pp.deliver_hit(maxi(1, roundi(float(_def["damage"]) * Difficulty.m("enemy_damage"))), global_position)

## --- API walki (combat.gd) -------------------------------------------------

## Górna część sylwetki = głowa; trafienie powyżej tej linii to krytyk. Niski Trzosek (14 px)
## nie ma słabego punktu — strzał z wysokości barku (−12 px) trafiałby go w „głowę” zawsze,
## więc krytyk byłby stałym mnożnikiem, a nie nagrodą za celowanie. Wołek (26 px) ma głowę
## w górnych 28%: trzeba celować w górę, skakać albo strzelać ze wzniesienia.
func head_y() -> float:
	var frac: float = _def.get("head", 0.0)
	if frac <= 0.0:
		return -INF
	return global_position.y - (_def["size"] as Vector2).y * (1.0 - frac)

func body_center() -> Vector2:
	return global_position + Vector2(0, -(_def["size"] as Vector2).y * 0.5)

func hit_radius() -> float:
	var sz: Vector2 = _def["size"]
	return maxf(sz.x, sz.y) * 0.45

## Cios w plecy: wróg patrzy w tę samą stronę, w którą zadajemy cios (atakujący stoi za nim).
func _is_behind(dir: Vector2) -> bool:
	return signf(dir.x) != 0.0 and signf(dir.x) == _facing

## Obrażenia z broni (serwer). Zwraca {hit, dealt, killed, mat}.
## Maczeta zabija śpiącego albo odwróconego plecami wroga natychmiast i po cichu.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not alive:
		return {}
	var dmg: float = info["amount"]
	var silent: bool = info.get("silent", false)
	if info.get("backstab", false) and (not active or _is_behind(info["dir"])):
		dmg = maxf(dmg, hp + 1.0)
		silent = true
		info["crit"] = true
	hp -= dmg
	_flash = 0.1
	_stagger = maxf(_stagger, 0.12 + float(info.get("stun", 0.0)))
	velocity.x += signf(info["dir"].x) * float(info.get("knock", 0.0)) * float(_def["knock_mult"])
	var fire: float = info.get("ignite", 0.0)
	if fire > 0.0:
		_ignite(fire)
	if not active and not silent:
		wake()
	var dead := hp <= 0.0
	if dead:
		_die()
	elif kind == "podsluchacz" and not silent:
		_begin_scream()
	return {"hit": true, "dealt": dmg, "killed": dead, "mat": 0}

# ---------------------------------------------------------------- ogień

func _ignite(seconds: float) -> void:
	var fresh := _burn <= 0.0
	_burn = maxf(_burn, seconds)
	if kind == "trzosek":
		_panic = maxf(_panic, 1.2)
	if fresh:
		if NoiseMgr.has_network():
			_ignite_fx.rpc(seconds)
		else:
			_ignite_fx(seconds)

func _tick_burn(delta: float) -> void:
	if _burn <= 0.0:
		return
	_burn = maxf(0.0, _burn - delta)
	# 8 HP/s przez czas płonięcia; wynik liczony ciągle, bez tykania co 0,1 s
	hp -= BURN_DPS * delta
	if hp <= 0.0 and alive:
		_die()

## Płomienie na ciele — każdy peer, na czas płonięcia.
@rpc("authority", "call_local", "reliable")
func _ignite_fx(seconds: float) -> void:
	Vfx.burning(self, seconds)

## Trafienie pociskiem (tylko serwer). Odrzut i krótkie ogłuszenie dają
## „mięso" strzałowi (GDD §23).
func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	hp -= dmg
	_flash = 0.1
	_stagger = 0.12
	Vfx.blood(get_parent(), global_position + Vector2(0, -8), (global_position - from_pos).normalized(), 5)
	var knock: float = _def["knock"]
	velocity.x += signf(global_position.x - from_pos.x) * knock
	if not active:
		wake()
	if hp <= 0.0:
		_die()
	elif kind == "podsluchacz":
		_begin_scream()

func _die() -> void:
	if NoiseMgr.is_server() and randf() < minf(1.0, float(HEALTH_DROP.get(kind, 0.0)) * Difficulty.m("drops")):
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.spawn_health(global_position + Vector2(0, -14))
	if NoiseMgr.is_server() and randf() < minf(1.0, float(AMMO_DROP.get(kind, 0.0)) * Difficulty.m("drops")):
		var w := Arsenal.pick_drop_weapon()
		var lv := get_tree().get_first_node_in_group("level")
		if w >= 0 and lv != null:
			var n: int = maxi(1, int(Weapons.def(w).pickup_rounds * 0.5))
			lv.spawn_item("ammo", w, global_position + Vector2(randf_range(-6.0, 6.0), -14), n)
	_set_alive(false)
	winding = false
	_windup = 0.0
	_death_fx()
	_send_state(999.0)

## Efekty śmierci na KAŻDYM peerze (serwer wywołuje wprost, klient po zmianie alive).
func _death_fx() -> void:
	Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.8)
	var local := _local_player_pos()
	if local.distance_to(global_position) < 220.0:
		Feel.shake(1.8 if kind == "trzosek" else 3.0)
		Feel.hitstop(0.05 if kind == "trzosek" else 0.09)
	# szczątki (fizyczne, lokalne) + krew na podłożu; odrzut z kierunku trafienia
	Vfx.gibs(get_parent(), global_position + Vector2(0, -6), (_def["color"] as Color).lightened(DEATH_FX_COLOR_VAR),
		6 if kind == "trzosek" else 11, Vector2(signf(velocity.x) * 60.0, 0))

func _local_player_pos() -> Vector2:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp != null and not pp.is_bot and pp.is_multiplayer_authority():
			return pp.global_position
	return Vector2(INF, INF)

func _send_state(delta: float) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 0.05
	_sync.rpc(global_position, hp, active, alive, winding)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(pos: Vector2, new_hp: float, is_active: bool, is_alive: bool, is_winding: bool) -> void:
	_remote_pos = pos
	if new_hp < hp - 0.01:
		_flash = 0.1
		Vfx.blood(get_parent(), global_position + Vector2(0, -8), Vector2.UP, 5)
	hp = new_hp
	active = is_active
	winding = is_winding
	if alive and not is_alive:
		_set_alive(false)
		_death_fx()
	elif not alive and is_alive:
		_set_alive(true)
		global_position = pos

func _process(delta: float) -> void:
	_ring = maxf(0.0, _ring - delta)
	if visible:
		_update_sprite()
		queue_redraw()
		_overlay.queue_redraw()

## Animacja: sen / zapowiedź / bieg / czuwanie. Kierunek z przesunięcia pozycji
## (u klientów prędkość wroga nie jest replikowana).
func _update_sprite() -> void:
	if _spr.is_empty():
		return
	var dx := global_position.x - _last_x
	_last_x = global_position.x
	if absf(dx) > 0.05:
		_facing = signf(dx)
	var moving := absf(dx) > 0.05
	if kind == "podsluchacz":
		# stoi w miejscu — patrzy na lokalnego gracza (nasłuchuje)
		var lp := _local_player_pos()
		if is_finite(lp.x) and absf(lp.x - global_position.x) > 4.0:
			_facing = signf(lp.x - global_position.x)
	var anim := "sleep"
	if active:
		if winding:
			anim = "windup"
		elif moving:
			anim = "run" if kind == "trzosek" else "walk"
		else:
			anim = "idle"
	Sprites.play(_spr, anim, _facing < 0.0)
	var body: AnimatedSprite2D = _spr[0]
	var m := Color.WHITE
	if _flash > 0.0:
		m = Color(2.4, 2.4, 2.4)
	elif winding:
		# zapowiedź ciosu: pulsujące czerwienienie (klatka „windup" unosi łapę)
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		m = Color(1.6 + 0.6 * p, 0.55, 0.5)
	elif not active:
		m = Color(0.8, 0.8, 0.8)
	body.modulate = m

func _draw() -> void:
	if not _spr.is_empty():
		return
	var size: Vector2 = _def["size"]
	var col: Color = _def["color"]
	if _flash > 0.0:
		col = Color.WHITE
	# śpiący: przygaszony i przygarbiony; zapowiedź ataku: czerwony kontur
	var crouch := 0.0 if active else 3.0
	var body := Rect2(-size.x * 0.5, -size.y + crouch, size.x, size.y - crouch)
	if not active:
		col = col.darkened(0.4)
	draw_rect(body, col)

## Oczy, kontur zapowiedzi ataku i HP — unshaded, widoczne w ciemności.
func _draw_overlay(ov: Node2D) -> void:
	var size: Vector2 = _def["size"]
	var t := Time.get_ticks_msec() / 1000.0
	var crouch := 0.0 if active else 3.0
	if winding and _spr.is_empty():
		var body := Rect2(-size.x * 0.5, -size.y + crouch, size.x, size.y - crouch)
		ov.draw_rect(body.grow(1.5), Color(1.0, 0.15, 0.1, 0.8), false, 1.5)
	if _spr.is_empty():
		var eye_y := -size.y + 4.0 + crouch
		var eye_a := 1.0 if active else 0.25
		var pulse := 0.6 + 0.4 * sin(t * 8.0)
		ov.draw_circle(Vector2(-size.x * 0.22, eye_y), 1.4, Color(1.0, 0.7 * pulse, 0.2, eye_a))
		ov.draw_circle(Vector2(size.x * 0.22, eye_y), 1.4, Color(1.0, 0.7 * pulse, 0.2, eye_a))
	if _ring > 0.0:
		var k := 1.0 - _ring / 0.7
		ov.draw_arc(Vector2(0, -size.y * 0.7), 8.0 + k * 70.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.35, (1.0 - k) * 0.8), 1.5)
	# pasek HP po pierwszym trafieniu
	if hp < _max_hp:
		var w := size.x + 4.0
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w, 2.0), Color(0.15, 0.05, 0.05))
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w * clampf(hp / _max_hp, 0.0, 1.0), 2.0), Color(0.9, 0.25, 0.2))
