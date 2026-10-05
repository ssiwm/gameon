extends CharacterBody2D
## „ON" — nieśmiertelny stalker. Symulacja TYLKO na serwerze; klienci dostają pozycję.
## Reaguje wyłącznie na hałas, nigdy bezpośrednio na gracza (GDD §8.5).
##
## Reguły z GDD §8.5 (v2):
##   HUNT_SPEED  88 px/s — wolniej od gracza (95), więc da się uciec biegiem
##   LURK_SPEED  55 px/s — w fazie napięcia (niski hałas) jest powolny
##   Po dotarciu do źródła hałasu NASŁUCHUJE (LISTEN_TIME) — nie przeskakuje na gracza
##   Kucający gracz jest zauważany dopiero z REACH_CROUCH
##   Atak ma zapowiedź (WINDUP_TIME): gracz może uciec, cios może chybić
##   Atak NIE generuje hałasu, po ciosie Stalker się cofa
##   Ciało widać tylko z bliska; z daleka są same oczy

const Lights := preload("res://scripts/lights.gd")
const Nav := preload("res://scripts/nav.gd")
const Sprites := preload("res://scripts/sprites.gd")

const AWAKE_THRESHOLD := 60.0
const SLEEP_THRESHOLD := 30.0
const HUNT_SPEED := 88.0
const LURK_SPEED := 55.0
const CLIMB_SPEED := 60.0
const ATTACK_COOLDOWN := 1.5
const RETREAT_DIST := 6.0
const HESITATION := 0.45

const LISTEN_TIME := 4.0
const WINDUP_TIME := 0.55
const REACH_STAND := 14.0
const REACH_CROUCH := 8.0
const REACH_SLACK := 6.0       ## o tyle gracz może się wycofać w trakcie zapowiedzi i nadal oberwać
const MISS_COOLDOWN := 0.8

## Granice ruchu w poziomie — z mapy (level.gd), z marginesem na ściany.
var _x_min := -270.0
var _x_max := 1470.0

# widoczność ciała względem lokalnego gracza
const SEE_FULL := 60.0
const SEE_NONE := 160.0

# nad tym progiem hałasu stalker poluje (szybko), poniżej — czatuje (wolno)
const HUNT_NOISE := 45.0

## Nieśmiertelny — boty nie marnują na niego amunicji (patrz player._nearest_enemy).
var immortal := true
var awake := false
var target_pos := Vector2.ZERO
## Zapowiedź ataku trwa (synchronizowane, żeby klient grał sygnał i rysował błysk)
var winding := false

var _attack_timer := 0.0
var _hesitate := 0.0
var _slow := 0.0
var _retreat_timer := 0.0
var _net_timer := 0.0
var _remote_pos := Vector2.ZERO
var _home := Vector2.ZERO
var _ground_y := 0.0
var _seen_serial := 0
var _arrived := false
var _listen := 0.0
var _windup := 0.0
var _windup_target: Node2D = null

## Audio: pozycyjne i z propagacją przez ściany — „słyszysz, nigdy nie widzisz"
## (GDD §13). Subtitle trzymamy osobno, bo _sync() też je aktualizuje.
var _audible := false
var _growl_timer := 0.0
var _step_accum := 0.0
var _last_aud_pos := Vector2.ZERO
var _hunting_cached := false
var _winding_cached := false
var _overlay: Node2D
var _lit_cd := 0.0
var _spr: Array = []
var _facing := 1.0
var _last_x := 0.0
## Ścieżka A* po powierzchniach (nav.gd) do target_pos.
var _path: Array = []
var _path_i := 0
var _path_goal := Vector2.INF
## Tor bieżącej krawędzi skoku/spadku jako łamana (punkty pośrednie).
var _leg: Array[Vector2] = []
var _leg_for := -1

func _ready() -> void:
	add_to_group("enemies")
	target_pos = global_position
	_remote_pos = global_position
	_home = global_position
	_ground_y = global_position.y
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		_x_min = lvl.bounds.position.x + 40.0
		_x_max = lvl.bounds.end.x - 40.0
	visible = false
	_last_aud_pos = global_position
	if Sprites.has("stalker"):
		_spr = Sprites.attach(self, "stalker")
	_overlay = Lights.add_overlay(self)

## Stalker nie jest zagrożeniem do ostrzelania — boty mają go ignorować.
func is_threat() -> bool:
	return false

## Restart misji (wipe).
func reset_enemy() -> void:
	awake = false
	winding = false
	global_position = _home
	target_pos = _home
	_remote_pos = _home
	_attack_timer = 0.0
	_windup = 0.0
	_windup_target = null
	_listen = 0.0
	_arrived = false
	visible = false
	_path = []
	_path_goal = Vector2.INF

func _physics_process(delta: float) -> void:
	# sprawdzamy NA BIEŻĄCO: peer w _ready() to jeszcze OfflineMultiplayerPeer,
	# więc cache'owany _server_sim bywał błędny i klient wysyłał _sync do serwera
	if not NoiseMgr.is_server():
		global_position = global_position.lerp(_remote_pos, 0.25)
		_redraw()
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_hesitate = maxf(0.0, _hesitate - delta)
	_slow = maxf(0.0, _slow - delta)
	_retreat_timer = maxf(0.0, _retreat_timer - delta)
	_listen = maxf(0.0, _listen - delta)

	var noise := NoiseMgr.level

	if not awake and noise >= AWAKE_THRESHOLD:
		awake = true
		target_pos = NoiseMgr.last_noise_pos
		_seen_serial = NoiseMgr.noise_serial
		_arrived = false
		print("[STALKER] awake at noise %.0f" % noise)
	if awake and noise <= SLEEP_THRESHOLD:
		awake = false
		winding = false
		_windup = 0.0
		print("[STALKER] asleep")

	_lit_cd = maxf(0.0, _lit_cd - delta)
	if awake and _lit_cd <= 0.0:
		# „Światło go przyciąga (latarka na wrogu = śmierć)" (GDD §7.3/§8.3):
		# jedyny wyjątek od reguły „tylko hałas" — snop latarki na Stalkerze
		# ściąga go na świecącego. Sprawdzamy 4×/s, nie co klatkę.
		_lit_cd = 0.25
		var lighter := Lights.flashlight_on(global_position + Vector2(0, -20), get_tree(), get_world_2d().direct_space_state)
		if lighter != null:
			target_pos = lighter.global_position
			_arrived = false
			_listen = 0.0

	if awake:
		# Idzie do ostatniego NOWEGO źródła hałasu — nigdy do gracza.
		if NoiseMgr.noise_serial != _seen_serial:
			_seen_serial = NoiseMgr.noise_serial
			if NoiseMgr.last_noise_pos.distance_to(target_pos) > 2.0:
				target_pos = NoiseMgr.last_noise_pos
				_arrived = false
				_listen = 0.0

		if _windup > 0.0:
			_tick_windup(delta)
		elif _retreat_timer <= 0.0 and _hesitate <= 0.0:
			_move_toward_target(delta, noise)
			if _retreat_timer <= 0.0:
				_try_begin_windup()

	visible = awake
	_update_audio(delta, awake, noise)
	_redraw()
	_send_state(delta)

## Ruch po powierzchniach poziomu: poziomo w stronę celu, wspinaczka tylko
## gdy jest już blisko celu w poziomie (cel na platformie). Ograniczony ścianami.
## Pełne A* przyjdzie z tilemapą poziomu (GDD §16.0).
## Ruch po powierzchniach poziomu ścieżką A* (GDD §8.5, §16.0 pkt 5): poziomo
## własną prędkością, skoki/spadki/zeskoki „wspinaczką" (CLIMB_SPEED).
## Wcześniej szedł prosto i przenikał przez ściany (maska kolizji 0).
func _move_toward_target(delta: float, noise: float) -> void:
	var speed := HUNT_SPEED if noise >= HUNT_NOISE else LURK_SPEED
	if _slow > 0.0:
		speed *= 0.4
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and lvl.nav != null:
		_follow_path(delta, speed, lvl.nav)
		return
	_move_direct(delta, speed)

func _follow_path(delta: float, speed: float, nav: AStar2D) -> void:
	if target_pos != _path_goal:
		_path_goal = target_pos
		_path = nav.find_path(global_position, target_pos)
		_path_i = 1
		_leg_for = -1
	if _path_i >= _path.size():
		if not _arrived:
			# dotarł do źródła hałasu (najbliższy punkt na powierzchni): NASŁUCHUJE
			_arrived = true
			_listen = LISTEN_TIME
			_hesitate = HESITATION
		return
	var wp: Vector2 = _path[_path_i].pos
	var kind: int = _path[_path_i].kind
	var v := speed
	var aim := wp
	if kind != Nav.Edge.WALK:
		v = minf(speed, CLIMB_SPEED)
		if _leg_for != _path_i:
			_leg_for = _path_i
			_leg = _leg_points(global_position, wp, kind)
		while not _leg.is_empty() and global_position.distance_to(_leg[0]) <= 0.5:
			_leg.remove_at(0)
		if not _leg.is_empty():
			aim = _leg[0]
	global_position = global_position.move_toward(aim, v * delta)
	if global_position.distance_to(wp) < 0.5:
		_path_i += 1

## Tor krawędzi zamiast skosu (skos ścinał rogi kafli i przechodził przez
## skrzynie). Odcinki biegną dokładnie korytarzami sprawdzanymi przy budowie
## grafu (nav._jump_clear, spadek w kolumnie obok, zeskok w pionie).
func _leg_points(from: Vector2, to: Vector2, kind: int) -> Array[Vector2]:
	var up := 16.0   # kafel nad wyższym poziomem — przelot nad przeszkodą
	match kind:
		Nav.Edge.JUMP:
			var top := minf(from.y, to.y) - up
			return [Vector2(from.x, top), Vector2(to.x, top), to]
		Nav.Edge.FALL:
			return [Vector2(to.x, from.y), to]
	return [to]

## Bez grafu (np. stara scena): prosto do celu.
func _move_direct(delta: float, speed: float) -> void:
	var to_target := target_pos - global_position
	if to_target.length() <= 5.0:
		if not _arrived:
			# dotarł do źródła hałasu: staje i NASŁUCHUJE
			_arrived = true
			_listen = LISTEN_TIME
			_hesitate = HESITATION
		return
	var nx := move_toward(global_position.x, target_pos.x, speed * delta)
	var ny := global_position.y
	if absf(to_target.x) < 90.0:
		ny = move_toward(ny, target_pos.y, CLIMB_SPEED * delta)
	global_position = Vector2(clampf(nx, _x_min, _x_max), minf(ny, _ground_y))

## Zasięg wykrycia: kucający gracz jest zauważany dopiero z bliska (GDD §8.5).
func _reach_for(pp: Node2D) -> float:
	return REACH_CROUCH if pp.crouching else REACH_STAND

func _try_begin_windup() -> void:
	if _attack_timer > 0.0 or _windup > 0.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		if global_position.distance_to(pp.global_position) <= _reach_for(pp):
			_windup = WINDUP_TIME
			_windup_target = pp
			winding = true
			return

func _tick_windup(delta: float) -> void:
	_windup -= delta
	if _windup > 0.0:
		return
	winding = false
	var pp := _windup_target
	_windup_target = null
	# cios trafia tylko jeśli gracz nie zdążył odejść poza zasięg (+ mała tolerancja)
	if pp != null and is_instance_valid(pp) and not pp.dead \
			and global_position.distance_to(pp.global_position) <= _reach_for(pp) + REACH_SLACK:
		print("[STALKER] attack player %d (noise NOT raised)" % pp.display_id)
		# Atak nie podnosi hałasu (GDD §8.5). Obrażenia idą do właściciela postaci.
		pp.deliver_hit(1, global_position)
		# cofnij się, dając graczowi okno na decyzję
		_retreat_timer = 0.8
		var away := (global_position - pp.global_position).normalized()
		global_position += away * RETREAT_DIST
		_attack_timer = ATTACK_COOLDOWN
	else:
		print("[STALKER] swing missed")
		_attack_timer = MISS_COOLDOWN

## Dźwięk stalkera: szept gdy czatuje (też w fazie niepokoju, zanim się obudzi),
## ryk przy przebudzeniu i zapowiedzi ataku, kroki gdy poluje.
## Wszystko idzie na bus „Stalker" (poza Ambience), żeby przebić się przez tło.
func _update_audio(delta: float, is_awake: bool, noise: float) -> void:
	var hunting := is_awake and noise >= HUNT_NOISE

	if is_awake and not _audible:
		# przebudzenie — krzyk + krótki stinger, potem szept
		Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -6.0)
		Audio.sting(1)
	elif hunting and not _hunting_cached:
		Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -9.0)
	_hunting_cached = hunting
	_audible = is_awake

	# zapowiedź ataku: ryk w momencie startu; szept milknie (poniżej)
	if winding and not _winding_cached:
		Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -3.0, 1.15)
	_winding_cached = winding

	if not is_awake:
		# Faza niepokoju (GDD §8.1): Stalker śpi, ale gracz już słyszy szept —
		# to ostrzeżenie PRZED karą, okno na decyzję.
		if noise >= NoiseMgr.UNEASY_THRESHOLD:
			var t := clampf((noise - NoiseMgr.UNEASY_THRESHOLD) / (AWAKE_THRESHOLD - NoiseMgr.UNEASY_THRESHOLD), 0.0, 1.0)
			var v := lerpf(-34.0, -20.0, t)
			if Audio.loop_playing("stalker_whisper_loop"):
				Audio.set_loop_volume("stalker_whisper_loop", v)
			else:
				Audio.start_loop_at("stalker_whisper_loop", self, Audio.BUS_STALKER, v)
		else:
			Audio.stop_loop("stalker_whisper_loop")
		_growl_timer = 0.0
		return

	# szept: głośniejszy gdy bliżej, i tylko gdy stalker nie biega (inaczej
	# szept ginie we własnych krokach). W zapowiedzi ataku zapada cisza.
	var wv := -44.0 if winding else _whisper_volume(hunting)
	if Audio.loop_playing("stalker_whisper_loop"):
		Audio.set_loop_volume("stalker_whisper_loop", wv)
	else:
		Audio.start_loop_at("stalker_whisper_loop", self, Audio.BUS_STALKER, wv)

	# kroki: co ~26 px drogi, tylko w fazie polowania
	if hunting:
		_step_accum += global_position.distance_to(_last_aud_pos)
		if _step_accum >= 26.0:
			_step_accum = 0.0
			Audio.play_variant_at("stalker_step", 3, global_position, Audio.BUS_STALKER, -11.0, 0.88)
	_last_aud_pos = global_position

	# warczanie: gdy jest blisko i głośno
	_growl_timer -= delta
	if _growl_timer <= 0.0:
		_growl_timer = randf_range(3.5, 7.0)
		if global_position.distance_to(_local_player_pos()) < 120.0:
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -11.0, 0.9)


func _whisper_volume(hunting: bool) -> float:
	var d := global_position.distance_to(_local_player_pos())
	var near := clampf(1.0 - d / 700.0, 0.0, 1.0)
	var base := -26.0 if hunting else -20.0
	return lerpf(base, -7.0, near)


func _local_player_pos() -> Vector2:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp != null and not pp.is_bot and pp.is_multiplayer_authority():
			return pp.global_position
	return _remote_pos

@rpc("any_peer", "call_local", "unreliable")
func take_bullet(_from_pos: Vector2, _dmg: float = 0.0) -> void:
	if not NoiseMgr.is_server():
		return
	_slow = 1.2
	_hesitate = 0.7

func _send_state(delta: float) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 0.05
	_sync.rpc(global_position, awake, winding)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(pos: Vector2, is_awake: bool, is_winding: bool) -> void:
	_remote_pos = pos
	awake = is_awake
	winding = is_winding
	visible = awake
	# Klient nie symuluje AI (GDD §8.5), więc audio też musi iść tu —
	# inaczej zdalny gracz usłyszy stalkera dopiero przy trafieniu.
	_update_audio(get_process_delta_time(), awake, NoiseMgr.level)
	_redraw()

## Sylwetka — cieniowana: w ciemności (CanvasModulate) niemal niewidoczna,
## w snopie latarki albo przy rozbłysku strzału wychodzi z mroku. Kolor jest
## jaśniejszy niż w wersji bez oświetlenia, inaczej nawet oświetlona byłaby czarna.
func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var hunting := NoiseMgr.level >= HUNT_NOISE
	var reveal := _reveal()
	if not _spr.is_empty():
		_sprite_frame(reveal, hunting, t)
		return
	var body_base := Color(0.20, 0.16, 0.24) if hunting else Color(0.24, 0.21, 0.27)
	var body := Color(body_base.r, body_base.g, body_base.b, reveal)
	if reveal > 0.02:
		draw_rect(Rect2(-8, -28, 16, 28), body)
		draw_rect(Rect2(-6, -36, 12, 10), body.lightened(0.05))
		for i in 6:
			var x := -7.5 + i * 3.0
			var sway := sin(t * 3.0 + i) * 2.5
			draw_line(Vector2(x, -1), Vector2(x + sway, 5), Color(0.14, 0.12, 0.16, reveal), 1.5)

## Sprite: ciało z przezroczystością „reveal", oczy (glow) z jasnością jak
## w rysowanej wersji — słabo z daleka, mocno z bliska i w zapowiedzi.
func _sprite_frame(reveal: float, hunting: bool, t: float) -> void:
	var dx := global_position.x - _last_x
	_last_x = global_position.x
	if absf(dx) > 0.05:
		_facing = signf(dx)
	var anim := "windup" if winding else ("walk" if absf(dx) > 0.05 else "idle")
	Sprites.play(_spr, anim, _facing < 0.0)
	var body: AnimatedSprite2D = _spr[0]
	var tint := Color(0.85, 0.8, 0.9) if hunting else Color.WHITE
	body.modulate = Color(tint, reveal)
	var glow: AnimatedSprite2D = _spr[1]
	if glow != null:
		var d := global_position.distance_to(_local_player_pos())
		var near := clampf(1.0 - (d - SEE_FULL) / (SEE_NONE - SEE_FULL), 0.0, 1.0)
		var pulse := 0.55 + 0.45 * sin(t * (6.0 if hunting else 2.0))
		var eye_a := maxf(near, 0.18 if d < 260.0 else 0.06) * (1.0 if hunting else 0.45)
		if winding:
			eye_a = 1.0
			pulse = 1.0
		glow.modulate = Color(1.0 + pulse, 1.0, 1.0, eye_a)

## „Słyszysz, nigdy nie widzisz": ciało z bliska, w snopie latarki
## i w zapowiedzi ataku; z daleka same oczy.
func _reveal() -> float:
	var d := global_position.distance_to(_local_player_pos())
	var reveal := clampf(1.0 - (d - SEE_FULL) / (SEE_NONE - SEE_FULL), 0.0, 1.0)
	if winding:
		reveal = 1.0
	elif is_inside_tree() and Lights.flashlight_on(global_position + Vector2(0, -20), get_tree(), get_world_2d().direct_space_state) != null:
		reveal = 1.0
	return reveal

## Oczy — unshaded: świecą w ciemności (słabo z daleka, mocno z bliska
## i w zapowiedzi ataku).
func _draw_overlay(ov: Node2D) -> void:
	if not _spr.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var hunting := NoiseMgr.level >= HUNT_NOISE
	var d := global_position.distance_to(_local_player_pos())
	var reveal := clampf(1.0 - (d - SEE_FULL) / (SEE_NONE - SEE_FULL), 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(t * (6.0 if hunting else 2.0))
	var eye_base := 1.0 if hunting else 0.45
	var eye_far := 0.18 if d < 260.0 else 0.06
	var eye_a := maxf(reveal, eye_far) * eye_base
	if winding:
		eye_a = 1.0
		pulse = 1.0
	ov.draw_circle(Vector2(-3, -32), 1.8, Color(1.0, 0.18 * pulse * eye_a, 0.12 * pulse * eye_a, eye_a))
	ov.draw_circle(Vector2(3, -32), 1.8, Color(1.0, 0.18 * pulse * eye_a, 0.12 * pulse * eye_a, eye_a))

func _redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()
