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
##   Trafienie go spowalnia, ale zatrzymuje najwyżej raz na STAGGER_COOLDOWN — ostrzałem nie da się go unieruchomić
##   Teren spowalnia go tak samo jak gracza (woda, błoto) — na każdej powierzchni zostaje wolniejszy od biegnącego
##   Ciało widać tylko z bliska; z daleka są same oczy
##
## Tryb „przechodzący" (`pass_mode`, mapa z `STALKER_PASS` zamiast znacznika X — misja 1.1, MAPS_PLAN.md M1b): nie śpi na mapie,
## tylko czeka poza nią. Gdy w fazie celu Uwaga przekroczy próg, wychodzi z ciemności za plecami drużyny (poza kadrem), przez
## `time` s poluje na hałas jak zwykle, potem cofa się tam, skąd przyszedł, i znika. Następne przejście dopiero po `cooldown` s
## i po tym, jak Uwaga spadnie poniżej progu — lekcja „hałas ściąga Istotę", nie stałe zagrożenie samouczka.

const Hurtbox := preload("res://scripts/hurtbox.gd")
const HURT_H := 54.0                         ## px: wysokość strefy trafień = model (enemy3d.gd SPEC „fit")
const Lights := preload("res://scripts/lights.gd")
const Nav := preload("res://scripts/nav.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Surfaces := preload("res://scripts/surfaces.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const AWAKE_THRESHOLD := 60.0
const SLEEP_THRESHOLD := 30.0
const NightShift := preload("res://scripts/night_shift.gd")
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
## Trafienie: spowolnienie na HIT_SLOW_TIME s zawsze, zatrzymanie na HIT_STAGGER s najwyżej raz na STAGGER_COOLDOWN s.
## Bez tego limitu strzał co 0,6 s trzymał go w miejscu bez końca (test `--stalkertest`: 1 px z 200 w 10 s).
const HIT_SLOW_TIME := 1.2
const HIT_SLOW := 0.4
const HIT_STAGGER := 0.7
const STAGGER_COOLDOWN := 3.0

## Granice ruchu w poziomie — z mapy (level.gd), z marginesem na ściany.
var _x_min := -270.0
var _x_max := 1470.0

# widoczność ciała względem lokalnego gracza
const SEE_FULL := 60.0
const APPEAR_COOLDOWN := 20.0   ## s między kolejnymi „pojawieniami się" (dźwięk stalker_appear)
const SEE_NONE := 160.0

# nad tym progiem hałasu stalker poluje (szybko), poniżej — czatuje (wolno)
const HUNT_NOISE := 45.0

## Tryb przechodzący: domyślne wartości (mapa nadpisuje kluczami `STALKER_PASS`).
const PASS_DEFAULTS := {"noise": 80.0, "time": 28.0, "leave": 8.0, "cooldown": 90.0, "after_goal": 0.0, "extract": 0.0}
const PASS_DIST_MIN := 380.0          ## px od środka drużyny: poza kadrem (widok ≈ ±200 px) z zapasem — jak wędrowcy Dyrektora
const PASS_DIST_MAX := 640.0
const PASS_DY_MAX := 96.0             ## px w pionie: wychodzi na tym samym piętrze co drużyna (± 6 kafli)
const PASS_CLEAR_R := 300.0           ## px: nie wychodzi bliżej żadnego człowieka
const PASS_GONE_R := 420.0            ## px: wycofujący się znika, gdy jest dalej od wszystkich ludzi
const PASS_RETRY := 1.0               ## s do kolejnej próby, gdy nie ma gdzie wyjść
enum Pass { IDLE, HUNT, LEAVE }

## Nieśmiertelny — boty nie marnują na niego amunicji (patrz player._nearest_enemy).
var immortal := true
## Tryb przechodzący (ustawia level.gd przed dodaniem do sceny) i jego parametry.
var pass_mode := false
var pass_cfg := {}
var pass_state: int = Pass.IDLE
var _pass_t := 0.0                     ## s do końca polowania (HUNT) albo wycofania (LEAVE)
var _pass_cd := 0.0                    ## s do możliwego następnego przejścia
var _pass_armed := true                ## Uwaga spadła poniżej progu od ostatniego przejścia
var _pass_from := Vector2.ZERO         ## skąd wyszedł — tam się wycofuje
var awake := false
var target_pos := Vector2.ZERO
## Zapowiedź ataku trwa (synchronizowane, żeby klient grał sygnał i rysował błysk)
var winding := false

var _attack_timer := 0.0
var _hesitate := 0.0
var _slow := 0.0
var _stagger_cd := 0.0
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
var _shown := false          ## czy lokalny gracz właśnie go widzi (zbocze gra „stalker_appear")
var _appear_cd := 0.0        ## s do następnego możliwego „pojawienia się"
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
	Hurtbox.add(self, 14.0, HURT_H)                           # strefa trafień na wysokość modelu (54 px), ciało ruchu 30 px
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
	if Sprites.has(Sprites.enemy_sheet("stalker")):
		_spr = Sprites.attach(self, Sprites.enemy_sheet("stalker"))
	_overlay = Lights.add_overlay(self)

## Kontrakt widoku (view3d.gd) — patrz enemy.gd: view_info. Stalker jest nieśmiertelny i nie błyska po trafieniu.
func view_info() -> Dictionary:
	return {"kind": "stalker", "alive": true, "winding": winding, "sp": 0, "flash": false}

## Skaner z perkiem „Scout" pokazuje śpiącego (niewidocznego) Stalkera z bliska.
func is_stalker() -> bool:
	return true

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
	_stagger_cd = 0.0
	_windup = 0.0
	_windup_target = null
	_listen = 0.0
	_arrived = false
	visible = false
	_path = []
	_path_goal = Vector2.INF
	pass_state = Pass.IDLE
	_pass_t = 0.0
	_pass_cd = 0.0
	_pass_armed = true

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
	_stagger_cd = maxf(0.0, _stagger_cd - delta)
	_retreat_timer = maxf(0.0, _retreat_timer - delta)
	_listen = maxf(0.0, _listen - delta)

	var noise := NoiseMgr.level

	if pass_mode:
		_tick_pass(delta, noise)
	elif not awake and noise >= NightShift.awake_threshold(AWAKE_THRESHOLD):
		awake = true
		target_pos = NoiseMgr.last_noise_pos
		_seen_serial = NoiseMgr.noise_serial
		_arrived = false
		print("[STALKER] awake at noise %.0f" % noise)
		SessionLog.event("stalker", {"what": "awake", "noise": roundi(noise)})
	if awake and not pass_mode and noise <= NightShift.sleep_threshold(SLEEP_THRESHOLD):
		awake = false
		winding = false
		_windup = 0.0
		print("[STALKER] asleep")
		SessionLog.event("stalker", {"what": "asleep", "noise": roundi(noise)})

	_lit_cd = maxf(0.0, _lit_cd - delta)
	var leaving := pass_mode and pass_state == Pass.LEAVE        # wycofujący się nie reaguje już na światło ani hałas
	if awake and not leaving and _lit_cd <= 0.0:
		# „Światło go przyciąga (latarka na wrogu = śmierć)" (GDD §7.3/§8.3):
		# jedyny wyjątek od reguły „tylko hałas" — snop latarki na Stalkerze
		# ściąga go na świecącego. Sprawdzamy 4×/s, nie co klatkę.
		_lit_cd = 0.25
		var lighter := Lights.flashlight_on(global_position + Vector2(0, -20), get_tree(), get_world_2d().direct_space_state)
		if lighter == null:
			lighter = Lights.light_weapon_on(global_position + Vector2(0, -20), get_tree(), get_world_2d().direct_space_state)   # LR-7 i HKM-9 świecą bez hałasu
		if lighter != null:
			target_pos = lighter.global_position
			_arrived = false
			_listen = 0.0

	if awake:
		# Idzie do ostatniego NOWEGO źródła hałasu — nigdy do gracza.
		if NoiseMgr.noise_serial != _seen_serial and not leaving:
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

## Parametr trybu przechodzącego (mapa albo PASS_DEFAULTS).
func pass_param(key: String) -> float:
	return float(pass_cfg.get(key, PASS_DEFAULTS[key]))

## Próg Uwagi, od którego wychodzi: na HARD osobny (`noise_hard`), bo hałas rośnie tam o 25% szybciej
## (`Difficulty` „noise” ×1,25) — ten sam próg wypuszczał go już przy pierwszej strzelaninie.
func pass_noise() -> float:
	if Difficulty.level == Difficulty.Level.HARD and pass_cfg.has("noise_hard"):
		return float(pass_cfg["noise_hard"])
	return pass_param("noise")

## Czy drużyna zaliczyła już `after_goal` celów misji (1.1: pierwszy nieśmiertelnik) — wcześniej nie wychodzi,
## żeby lekcja hałasu nie przychodziła przed lekcją ruchu i strzału.
func _goal_ok() -> bool:
	var need := int(pass_param("after_goal"))
	if need <= 0:
		return true
	var mis := get_tree().get_first_node_in_group("mission")
	return mis != null and int(mis.get("goal_total")) - int(mis.get("goal_left")) >= need

## Tryb przechodzący (serwer): czeka poza mapą → wychodzi na hałas → poluje → wycofuje się → znika.
func _tick_pass(delta: float, noise: float) -> void:
	_pass_cd = maxf(0.0, _pass_cd - delta)
	match pass_state:
		Pass.IDLE:
			if noise < pass_noise():
				_pass_armed = true
			if _pass_armed and _pass_cd <= 0.0 and noise >= pass_noise() and _phase_ok() and _goal_ok():
				var at: Variant = pick_emerge_point()
				if at == null:
					_pass_cd = PASS_RETRY               # drużyna w miejscu bez zaplecza (np. przy krawędzi mapy) — spróbuje za chwilę
				else:
					_emerge(at, noise)
		Pass.HUNT:
			_pass_t -= delta
			if _pass_t <= 0.0 or not _phase_ok():
				pass_state = Pass.LEAVE
				_pass_t = pass_param("leave")
				target_pos = _pass_from
				_arrived = false
				_listen = 0.0
				winding = false
				_windup = 0.0
				_windup_target = null
		Pass.LEAVE:
			_pass_t -= delta
			if _pass_t <= 0.0 or _arrived or _far_from_humans(PASS_GONE_R):
				_vanish()

## Czy misja jest w fazie, w której wychodzi: cel, a przy `extract` > 0 także ewakuacja (1.1 od 1.7.283: powrót przez obudzony las).
func _phase_ok() -> bool:
	var mis := get_tree().get_first_node_in_group("mission")
	if mis == null:
		return false
	var ph := int(mis.get("phase"))
	return ph == 0 or (ph == 2 and pass_param("extract") > 0.0)

func _humans() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p: Node) -> bool: return not p.is_bot and not p.dead)

func _far_from_humans(r: float) -> bool:
	for p in _humans():
		if (p as Node2D).global_position.distance_to(global_position) < r:
			return false
	return true

## Punkt wyjścia: węzeł grafu nawigacji poza kadrem za plecami drużyny, na tym samym piętrze, z drogą do drużyny i z dala od każdego
## człowieka; gdy z tyłu nie ma miejsca — z przodu. `null` = nie ma gdzie. „Za plecami" (`behind_side`): w fazie celu drużyna idzie na
## wschód, więc z zachodu; w ewakuacji — od strony przeciwnej do wyjścia (1.1: powrót na zachód, więc ze wschodu; dotąd wychodził
## przed drużyną, tuż przy wyjściu — playtest 1.7.283).
func pick_emerge_point() -> Variant:
	var lvl := get_tree().get_first_node_in_group("level")
	var humans := _humans()
	if lvl == null or lvl.nav == null or humans.is_empty():
		return null
	var nav: AStar2D = lvl.nav
	var c := Vector2.ZERO
	for p in humans:
		c += (p as Node2D).global_position
	c /= float(humans.size())
	var goal := nav.get_closest_point(c)
	var back := behind_side(c)
	for side: float in [back, -back]:
		var best: Variant = null
		var best_score := INF
		for id in nav.get_point_ids():
			var pos := nav.get_point_position(id)
			var dx := (pos.x - c.x) * side
			var dy := absf(pos.y - c.y)
			if dx < PASS_DIST_MIN or dx > PASS_DIST_MAX or dy > PASS_DY_MAX:
				continue
			var clear := true
			for p in humans:
				if (p as Node2D).global_position.distance_to(pos) < PASS_CLEAR_R:
					clear = false
					break
			if not clear:
				continue
			var score := dy * 2.0 + absf(dx - (PASS_DIST_MIN + PASS_DIST_MAX) * 0.5)
			if score < best_score and not nav.get_id_path(id, goal).is_empty():
				best_score = score
				best = pos
		if best != null:
			return best
	return null

## Strona „za plecami" drużyny o środku `c`: -1 = zachód, 1 = wschód. W ewakuacji — przeciwna do kierunku na wyjście misji.
func behind_side(c: Vector2) -> float:
	var mis := get_tree().get_first_node_in_group("mission")
	if mis != null and int(mis.get("phase")) == 2:
		var ex: Vector2 = mis.get("exit_pos")
		if ex != Vector2.ZERO and absf(ex.x - c.x) > 1.0:
			return -signf(ex.x - c.x)
	return -1.0

func _emerge(at: Vector2, noise: float) -> void:
	global_position = at
	_pass_from = at
	_remote_pos = at
	awake = true
	pass_state = Pass.HUNT
	_pass_t = pass_param("time")
	_pass_armed = false
	target_pos = NoiseMgr.last_noise_pos
	_seen_serial = NoiseMgr.noise_serial
	_arrived = false
	_listen = 0.0
	_path = []
	_path_goal = Vector2.INF
	print("[STALKER] passing: emerges at %s (noise %.0f)" % [str(at.round()), noise])
	SessionLog.event("stalker", {"what": "pass_in", "noise": roundi(noise), "pos": SessionLog.xy(at)})

func _vanish() -> void:
	print("[STALKER] passing: gone at %s" % str(global_position.round()))
	SessionLog.event("stalker", {"what": "pass_out", "noise": roundi(NoiseMgr.level), "pos": SessionLog.xy(global_position)})
	awake = false
	winding = false
	_windup = 0.0
	_windup_target = null
	pass_state = Pass.IDLE
	_pass_cd = pass_param("cooldown")
	global_position = _home
	_remote_pos = _home
	target_pos = _home
	_path = []
	_path_goal = Vector2.INF

## Ruch po powierzchniach poziomu: poziomo w stronę celu, wspinaczka tylko
## gdy jest już blisko celu w poziomie (cel na platformie). Ograniczony ścianami.
## Pełne A* przyjdzie z tilemapą poziomu (GDD §16.0).
## Ruch po powierzchniach poziomu ścieżką A* (GDD §8.5, §16.0 pkt 5): poziomo
## własną prędkością, skoki/spadki/zeskoki „wspinaczką" (CLIMB_SPEED).
## Wcześniej szedł prosto i przenikał przez ściany (maska kolizji 0).
func _move_toward_target(delta: float, noise: float) -> void:
	var speed := (HUNT_SPEED if noise >= HUNT_NOISE else LURK_SPEED) * Difficulty.m("stalker_speed")
	if _slow > 0.0:
		speed *= HIT_SLOW
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		speed *= float(Surfaces.of(lvl.surface_at(global_position))["speed"])      # woda i błoto hamują go jak gracza (GDD §8.5)
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
			_windup = WINDUP_TIME * Difficulty.m("stalker_windup")
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
		SessionLog.event("stalker", {"what": "swing_hit", "noise": roundi(NoiseMgr.level), "target": "P%d" % int(pp.display_id), "bot": bool(pp.is_bot)})
		# Atak nie podnosi hałasu (GDD §8.5). Obrażenia idą do właściciela postaci.
		pp.deliver_hit(1, global_position, "stalker")
		# cofnij się, dając graczowi okno na decyzję
		_retreat_timer = 0.8
		var away := (global_position - pp.global_position).normalized()
		global_position += away * RETREAT_DIST
		_attack_timer = ATTACK_COOLDOWN * Difficulty.m("stalker_cd")
	else:
		print("[STALKER] swing missed")
		var miss := {"what": "swing_miss", "noise": roundi(NoiseMgr.level)}
		if pp != null and is_instance_valid(pp):
			miss["target"] = "P%d" % int(pp.display_id)
			miss["bot"] = bool(pp.is_bot)
		SessionLog.event("stalker", miss)
		_attack_timer = MISS_COOLDOWN * Difficulty.m("stalker_cd")

## Dźwięk stalkera: szept gdy czatuje (też w fazie niepokoju, zanim się obudzi),
## ryk przy przebudzeniu i zapowiedzi ataku, kroki gdy poluje.
## Wszystko idzie na bus „Stalker" (poza Ambience), żeby przebić się przez tło.
func _update_audio(delta: float, is_awake: bool, noise: float) -> void:
	var hunting := is_awake and noise >= HUNT_NOISE

	if is_awake and not _audible:
		# przebudzenie — krzyk + krótki stinger, potem szept
		Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -6.0)
		Audio.sting(1)
		_appear_cd = maxf(_appear_cd, 2.0)                  # krzyk przebudzenia nie zlewa się z „pojawieniem"
	elif hunting and not _hunting_cached:
		Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -9.0)
	_hunting_cached = hunting
	_audible = is_awake

	# zapowiedź ataku: ryk w momencie startu; szept milknie (poniżej)
	if winding and not _winding_cached:
		Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -3.0, 1.15)
	_winding_cached = winding

	# „Coś się pojawia": chwila, gdy przebudzony Stalker wychodzi z mroku dla lokalnego gracza (z bliska albo w snopie
	# latarki). Znowu dopiero po APPEAR_COOLDOWN — żeby nie grało przy każdym mignięciu latarką. Lokalne i kosmetyczne.
	_appear_cd = maxf(0.0, _appear_cd - delta)
	var shown := is_awake and not winding and _reveal() >= 0.6
	if shown and not _shown and _appear_cd <= 0.0:
		Audio.play_at("stalker_appear", global_position, Audio.BUS_STALKER, -6.0)
		_appear_cd = APPEAR_COOLDOWN
	_shown = shown

	if not is_awake:
		# Faza niepokoju (GDD §8.1): Stalker śpi, ale gracz już słyszy szept —
		# to ostrzeżenie PRZED karą, okno na decyzję.
		if noise >= NoiseMgr.UNEASY_THRESHOLD and not pass_mode:          # przechodzący czeka poza mapą — ostrzega alert hałasu w HUD
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

## Stalker nie ginie od broni (GDD §7.3) — trafienie tylko go spowalnia i zbija z tropu.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	take_bullet(info["pos"], 0.0)
	return {"hit": true, "dealt": 0.0, "killed": false, "mat": Arsenal.Mat.FLESH}

@rpc("any_peer", "call_local", "unreliable")
func take_bullet(_from_pos: Vector2, _dmg: float = 0.0) -> void:
	if not NoiseMgr.is_server():
		return
	_slow = HIT_SLOW_TIME
	if _stagger_cd <= 0.0:
		_hesitate = HIT_STAGGER
		_stagger_cd = STAGGER_COOLDOWN

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
	if pos.distance_to(global_position) > 200.0:
		global_position = pos                 # przeskok (wyjście z ciemności, zniknięcie, restart): bez przelotu przez mapę
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
	if not _spr.is_empty():
		_sprite_frame(_reveal(), NoiseMgr.level >= HUNT_NOISE, Time.get_ticks_msec() / 1000.0)

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

## Oczy świecą w modelu 3D (enemy3d.gd); nakładka 2D nic nie rysuje.
func _draw_overlay(_ov: Node2D) -> void:
	pass

func _redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()
