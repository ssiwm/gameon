extends CharacterBody2D
## Pijawka — boss misji B1 (GDD §7.1, §9 B1). Żyje pod powierzchnią zalanego basenu areny: ZANURZONA jest prawie niewrażliwa (5%)
## i niewidoczna — jej cień ujawnia dopiero światło (flara w promieniu LIGHT_REVEAL_R albo snop latarki), wtedy dostaje 40% obrażeń;
## pełne obrażenia tylko wynurzona (1.7.70).
## Płynie pod najbliższym graczem stojącym w wodzie; pod nim robi ZAPOWIEDŹ (kręgi na wodzie), potem WYNURZA się, rani (1 HP) i zostaje
## na chwilę odsłonięta — wtedy też dostaje pełne obrażenia. Gracze na kładkach nad basenem są poza zasięgiem.
##
## Faza A (rdzeń): zasadzka z obrażeniami, 3 fazy HP (tempo i cooldowny), śmierć otwiera ekstrakcję. Chwyt i QTE (faza B), przyzywanie
## Trzosków i podwójna zasadzka (faza C) dołożone później. Interfejs jak u Żyły (boss.gd): hp / max_hp / phase / died / is_alive(),
## więc pasek bossa w HUD-zie i mission.gd działają bez zmian. Symulacja TYLKO na serwerze; klienci dostają stan przez _sync i _event.

signal died

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Vfx := preload("res://scripts/vfx.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const NightShift := preload("res://scripts/night_shift.gd")

enum State { DORMANT, AWAKE, DEAD }
enum Mode { SUB, WIND, UP, GRAB }         ## zanurzona / zapowiedź zasadzki / wynurzona / trzyma ofiarę (QTE drużyny)

const BASE_HP := 5000.0                   ## 1.7.70: 600 → 900 → 5000 (walka z 900 HP trwała ~35 s; symulacja --leechsim: duet 77 efektywnych DPS ≈ 130 s)
const HP_PER_EXTRA_HUMAN := 1500.0
const SUB_MULT := 0.05                    ## zanurzona i nieoświetlona
const LIT_MULT := 0.4                     ## zanurzona, ale cień oświetlony flarą / latarką (1.7.70; wcześniej 100%) — pełne obrażenia dopiero, gdy wynurzona
const SPEED := [105.0, 140.0, 175.0]      ## px/s w fazach 1–3
const WINDUP := [0.85, 0.7, 0.55]         ## zapowiedź zasadzki (s)
const UP_TIME := [1.7, 1.5, 1.3]          ## jak długo wynurzona i odsłonięta
const AMBUSH_CD := [1.8, 1.3, 0.9]        ## przerwa po zasadzce
const STRIKE_HALF_X := 24.0               ## zasięg poziomy ugryzienia
const STRIKE_Y := 44.0                    ## ile nad poziomem wody gracz jest jeszcze w zasięgu (niska kładka 32 px — tak, wysoka 64 px — nie)
const SHORE_REACH := 44.0                 ## gracz na brzegu tak blisko basenu też jest celem zasadzki…
const SHORE_LUNGE := 22.0                 ## …a Pijawka wyskakuje z wody dalej (zasięg ugryzienia +22 px), żeby go dosięgnąć
const SPIT_RANGE := 340.0                 ## faza 2+: gracz poza zasięgiem zasadzki w tej odległości dostaje kwasem
const SPIT_WINDUP := [0.0, 0.9, 0.7]      ## zapowiedź plucia (s) w fazach 1–3
const SPIT_CD := [0.0, 5.0, 3.5]          ## przerwa po pluciu
const SPIT_UP := 1.1                      ## ile s jest wynurzona i odsłonięta po plunięciu
const SPIT_SPEED := 250.0
const REGEN_FRAC := 0.005                 ## zanurzona i nieoświetlona leczy się tyle maks. HP na sekundę (nigdy ponad próg bieżącej fazy)
const FURY_HP_FRAC := 0.15                ## faza 3 poniżej tego HP: furia
const FURY_SPEED := 1.4
const FURY_TIMING := 0.7                  ## mnożnik zapowiedzi i przerw w furii
## Fala przypływu (1.7.69, fazy 2–3): woda zalewa niskie kładki i brzeg (do SURGE_H nad dnem basenu). Zapowiedź SURGE_WARN s (woda faluje),
## potem fala: wszyscy poniżej SURGE_H w strefie dostają 1 obrażenie i tracą flary zalane wodą; przez SURGE_ON s woda stoi wysoko, a potem opada.
## Bezpieczne są wysokie kładki (64 px) — gdzie sięga kwas. Odstępy i zapowiedź skaluje Difficulty „boss_tide”.
const SURGE_EVERY := [0.0, 25.0, 20.0]
const SURGE_FIRST := 14.0                 ## pierwsza fala po tylu s od wejścia w fazę 2
const SURGE_WARN := 2.2
const SURGE_ON := 4.5
const SURGE_FALL := 0.9
const SURGE_H := 48.0
const SURGE_PAD := 56.0                   ## strefa zalewu: basen + tyle px na brzeg z każdej strony
const LIGHT_REVEAL_R := 150.0             ## flara w tym promieniu ujawnia cień
const POOL_FLOOR_TOL := 8.0               ## gracz stoi „w wodzie", gdy jego stopy są przy poziomie dna basenu
const N_AMBUSH := 3.0
const N_DEATH := 18.0
const NOISE_FOLLOW_R := 260.0
const MINION_EVERY := [22.0, 12.0, 8.0]   ## co ile s dosyła Trzoski w fazach 1 / 2 / 3 (od 1.7.68 także w fazie 1)
const MINION_MAX := [2, 4, 5]             ## ile Trzosków naraz (+1 za dodatkowego człowieka)
const SECOND_STRIKE_MIN_DX := 40.0        ## drugi punkt zasadzki (faza 3) co najmniej tyle px od pierwszego
const GRAB_TIME := 3.5                    ## tyle trwa wciąganie; potem ofiara trafia pod wodę (down)
const GRAB_FRAC := 0.06                   ## ułamek maks. HP, który drużyna musi zadać w tym oknie, żeby Pijawka puściła
const GRAB_MELEE_MULT := 2.0              ## cios chwyconego (maczeta) liczy się do uwolnienia podwójnie
const SPRITE_DROP := 6.0                  ## o tyle w dół przesuwamy klatkę — linia wody arkusza leży 6 px nad dołem klatki
const RISE_TIME := 0.3                    ## czas animacji „rise" (4 klatki / 14 fps)
const GRAB_CD := [3.0, 2.2, 1.2]          ## przerwa po chwycie (puszczonym albo dokończonym)

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
var boss_hint := "It hides under the water. Light shows its shadow (40% damage) — bait it to surface, then hit it hard"
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
var _spit_pending := false                ## zapowiedź (WIND) kończy się pluciem zamiast ugryzieniem
var _fury_on := false
var _spat := false                        ## ostatnie wynurzenie było pluciem (inna przerwa po nim)
var _spit_ref: Node2D = null
var surge_state := "idle"                  ## idle / warn / on / fall — serwer liczy, klienci dostają zdarzenia (surge_*)
var _surge_t := 0.0
var _surge_cd := 0.0
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
var _spr: Array = []                       ## [ciało, glow] z arkusza leech; puste = rysunek zastępczy (_draw_body)
var _prev_mode := -1
var _rise_t := 0.0                         ## ile jeszcze trwa animacja wynurzenia (potem idle)
var _face_left := false

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
	var tide: Node2D = (load("res://scripts/tide_water.gd") as GDScript).new()           # woda fali przypływu: stała w świecie, rysuje leech.surge_level()
	tide.leech = self
	tide.name = "TideWater"
	get_parent().add_child.call_deferred(tide)
	_light = Lights.make_light(Lights.radial(), 2.2, Color(0.4, 0.8, 0.85), 0.0, false)
	_light.position = Vector2(0, -10)
	add_child(_light)
	if Sprites.has(Sprites.enemy_sheet("leech")):
		_spr = Sprites.attach(self, Sprites.enemy_sheet("leech"))
		for l in _spr:
			if l != null:
				l.position = Vector2(0, SPRITE_DROP)
				l.visible = false

func is_threat() -> bool:
	return state == State.AWAKE

func is_alive() -> bool:
	return state != State.DEAD

func body_center() -> Vector2:
	return global_position + Vector2(0, -8 if mode == Mode.SUB else -16)

func _set_hitbox(up: bool) -> void:
	var h := 48.0 if not _spr.is_empty() else 34.0                  # sprite jest wyższy od rysunku zastępczego
	_rect.size = Vector2(40, h) if up else Vector2(44, 14)
	_shape.position = Vector2(0, -h * 0.5) if up else Vector2(0, -3)

# ---------------------------------------------------------------- misja (serwer)

func _humans() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			n += 1
	return n

## HP bossa dla `humans` ludzi w drużynie na bieżącym poziomie trudności (EASY ×0,7, HARD ×1,4) — jedno miejsce, testowalne.
static func hp_for(humans: int) -> float:
	return (BASE_HP + HP_PER_EXTRA_HUMAN * float(maxi(0, humans - 1))) * Difficulty.m("boss_hp") * NightShift.hp_mult()

## Mnożnik zapowiedzi i przerw bossa z poziomu trudności (HARD 0,8 = o 20% krócej).
func _dmul() -> float:
	return Difficulty.m("boss_cd")

func _minion_every(ph: int) -> float:
	return float(MINION_EVERY[ph]) / Difficulty.m("boss_adds")

func _minion_cap(ph: int) -> int:
	return ceili(float(MINION_MAX[ph]) * Difficulty.m("boss_adds"))

func awaken() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	max_hp = hp_for(_humans())
	hp = max_hp
	state = State.AWAKE
	phase = 1
	mode = Mode.SUB
	_cd = 2.0
	_minion_t = 10.0 / Difficulty.m("boss_adds")    # pierwsze Trzoski z brzegów już w fazie 1, po 10 s
	surge_state = "idle"
	_surge_t = 0.0
	_surge_cd = SURGE_FIRST
	_fury_on = false
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
	_spit_pending = false
	_spat = false
	_fury_on = false
	surge_state = "idle"
	_surge_t = 0.0
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
		_tick_regen(delta)
		_tick_mode(delta)
		_tick_minions(delta)
		_tick_surge(delta)
	_net_t -= delta
	if _net_t <= 0.0:
		_send_state(false)

## Wysokość zasięgu zasadzki nad dnem basenu: w czasie wysokiej wody sięga całej zalanej strefy.
func _strike_y() -> float:
	return SURGE_H + 6.0 if surge_state == "on" else STRIKE_Y

func _in_pool(p: Node2D) -> bool:
	return p.global_position.x >= pool_x0 and p.global_position.x <= pool_x1 and absf(p.global_position.y - surf_y) <= POOL_FLOOR_TOL

## Gracz w zasięgu zasadzki (1.7.68): w basenie albo na niskiej kładce nad nim (≤ STRIKE_Y nad wodą), a także na brzegu do SHORE_REACH od krawędzi.
## Wysokie kładki (64 px) i dalszy brzeg zostają poza zasięgiem — tam sięga tylko kwas (faza 2+).
func _in_reach(p: Node2D) -> bool:
	var px := p.global_position.x
	var py := p.global_position.y
	if px < pool_x0 - SHORE_REACH or px > pool_x1 + SHORE_REACH:
		return false
	return py >= surf_y - _strike_y() and py <= surf_y + POOL_FLOOR_TOL

## Czy gracz leży w zasięgu ugryzienia z punktu `x`: poziomo STRIKE_HALF_X (na brzegu +SHORE_LUNGE), pionowo w STRIKE_Y.
func _strike_hits(p: Node2D, x: float) -> bool:
	var reach := STRIKE_HALF_X
	if p.global_position.x < pool_x0 or p.global_position.x > pool_x1:
		reach += SHORE_LUNGE
	return absf(p.global_position.x - x) <= reach and p.global_position.y >= surf_y - _strike_y()

func _best_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion() or not _in_reach(p):
			continue
		var d := absf(p.global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = p
	return best

## Plucie kwasem (faza 2+): najbliższy żywy gracz w SPIT_RANGE, którego zasadzka nie dosięga (kładka, dalszy brzeg).
func _spit_target() -> Node2D:
	var best: Node2D = null
	var best_d := SPIT_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion() or p.grabbed:
			continue
		var d := absf(p.global_position.x - global_position.x)
		if d < best_d and absf(p.global_position.y - surf_y) < 220.0:
			best_d = d
			best = p
	return best

## Poziom wody 0..1 (do rysowania i obrażeń) z lokalnego zegara stanu — liczą go jednakowo serwer i klienci.
func surge_level() -> float:
	match surge_state:
		"warn":
			return 0.07 + 0.05 * sin(_surge_t * 5.0)
		"on":
			return smoothstep(0.0, 0.8, _surge_t)
		"fall":
			return 1.0 - clampf(_surge_t / SURGE_FALL, 0.0, 1.0)
	return 0.0

func in_surge_zone(pos: Vector2) -> bool:
	return pos.x >= pool_x0 - SURGE_PAD and pos.x <= pool_x1 + SURGE_PAD

## Serwer: stany fali przypływu. Co SURGE_EVERY s w fazach 2–3 (poza chwytem): zapowiedź → fala → wysoka woda → opadanie.
func _tick_surge(delta: float) -> void:
	if phase < 2 or state != State.AWAKE:
		return
	var tide := Difficulty.m("boss_tide")
	match surge_state:
		"idle":
			if mode == Mode.GRAB:
				return
			_surge_cd -= delta
			if _surge_cd <= 0.0:
				surge_state = "warn"
				_surge_t = 0.0
				_event.rpc("surge_warn")
		"warn":
			_surge_t += delta
			if _surge_t >= SURGE_WARN * tide:
				surge_state = "on"
				_surge_t = 0.0
				_event.rpc("surge_on")
				_surge_wave_hit()
		"on":
			_surge_t += delta
			if _surge_t >= SURGE_ON:
				surge_state = "fall"
				_surge_t = 0.0
				_event.rpc("surge_off")
		"fall":
			_surge_t += delta
			if _surge_t >= SURGE_FALL:
				surge_state = "idle"
				_surge_t = 0.0
				_surge_cd = float(SURGE_EVERY[clampi(phase - 1, 0, 2)]) * tide

## Fala uderza: każdy żywy gracz w strefie poniżej SURGE_H traci serce (wysokie kładki są bezpieczne), zalane flary gasną.
func _surge_wave_hit() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion() or p.grabbed:
			continue
		if in_surge_zone(p.global_position) and p.global_position.y > surf_y - SURGE_H and p.global_position.y <= surf_y + POOL_FLOOR_TOL:
			p.deliver_hit(1, Vector2(p.global_position.x, surf_y))
	for f in get_tree().get_nodes_in_group("flares"):
		if is_instance_valid(f) and in_surge_zone((f as Node2D).global_position) and (f as Node2D).global_position.y > surf_y - SURGE_H:
			f.life = minf(f.life, 0.2)

func _fury() -> bool:
	return phase >= 3 and hp <= max_hp * FURY_HP_FRAC

## Zanurzona i nieoświetlona Pijawka się leczy — ale nie ponad próg bieżącej fazy (faza nie cofa się). Strzelanie na ślepo nie ma sensu.
func _tick_regen(delta: float) -> void:
	if mode != Mode.SUB or revealed or hp <= 0.0:
		return
	var cap := max_hp * (1.0 if phase <= 1 else (0.66 if phase == 2 else 0.33))
	if hp < cap:
		hp = minf(cap, hp + max_hp * REGEN_FRAC * Difficulty.m("boss_regen") * delta)

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
			var fury := _fury()
			if fury and not _fury_on:
				_fury_on = true
				_event.rpc("fury")
			var tgt := _best_target()
			var spitter: Node2D = null
			if tgt != null:
				_target_x = tgt.global_position.x
			else:
				spitter = _spit_target() if phase >= 2 else null
				if spitter != null:
					_target_x = spitter.global_position.x          # nikt w zasięgu zasadzki — podpływa pod tego, w którego może pluć
				elif NoiseMgr.last_noise_pos.distance_to(global_position) < NOISE_FOLLOW_R and NoiseMgr.level > 5.0:
					_target_x = NoiseMgr.last_noise_pos.x
				else:
					_target_x = global_position.x
			_target_x = clampf(_target_x, pool_x0, pool_x1)
			var dx := _target_x - global_position.x
			var step := minf(absf(dx), float(SPEED[ph]) * (FURY_SPEED if fury else 1.0) * delta)
			global_position.x = clampf(global_position.x + signf(dx) * step, pool_x0, pool_x1)
			var timing := FURY_TIMING if fury else 1.0
			if tgt != null and absf(dx) < 12.0 and _cd <= 0.0:
				_spit_pending = false
				mode = Mode.WIND
				_t_mode = float(WINDUP[ph]) * timing * _dmul()
				second_x = _pick_second_x(tgt) if phase >= 3 else -1.0
				_event.rpc("windup")
			elif tgt == null and spitter != null and _cd <= 0.0 and absf(spitter.global_position.x - global_position.x) <= SPIT_RANGE * 0.9:
				_spit_pending = true
				_spit_ref = spitter
				mode = Mode.WIND
				_t_mode = float(SPIT_WINDUP[ph]) * timing * _dmul()
				second_x = -1.0
				_event.rpc("windup")
		Mode.WIND:
			_t_mode -= delta
			if _t_mode <= 0.0:
				if _spit_pending:
					_spit()
				else:
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
				_cd = (float(SPIT_CD[ph]) if _spat else float(AMBUSH_CD[ph])) * (FURY_TIMING if _fury() else 1.0) * _dmul()
				_spat = false
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
	_minion_t = _minion_every(ph)
	if _minions.size() >= _minion_cap(ph) + maxi(0, _humans() - 1):
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
		if p == first or p.dead or p.is_queued_for_deletion() or not _in_reach(p):
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
		if _strike_hits(p, global_position.x):
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
			if _strike_hits(p, second_x):
				p.deliver_hit(1, Vector2(second_x, surf_y))
		_event.rpc("surface2")
		second_x = -1.0
	if victim != null and not victim.dead:
		_begin_grab(victim)

## Plucie (faza 2+): wynurza się na SPIT_UP s (odsłonięta — można ją bić), pluje łukiem w gracza spoza zasięgu zasadzki.
func _spit() -> void:
	_spit_pending = false
	_spat = true
	mode = Mode.UP
	_t_mode = SPIT_UP
	_set_hitbox(true)
	NoiseMgr.add_noise(N_AMBUSH * 0.6, global_position)
	var st := _spit_ref if (_spit_ref != null and is_instance_valid(_spit_ref) and not _spit_ref.dead) else _spit_target()
	_spit_ref = null
	_event.rpc("spit")
	if st == null:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return
	var from := global_position + Vector2(0.0, -34.0)
	var aim: Vector2 = st.global_position + Vector2(0.0, -9.0) + st.velocity * 0.35         # z wyprzedzeniem
	var dist := from.distance_to(aim)
	var flight := clampf(dist / SPIT_SPEED, 0.35, 1.2)
	var v := Vector2((aim.x - from.x) / flight, (aim.y - from.y - 0.5 * 520.0 * flight * flight) / flight)
	lvl.spawn_acid(from, v)

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
	_cd = float(GRAB_CD[ph]) * (FURY_TIMING if _fury() else 1.0) * _dmul()
	if success:
		global_position.x = clampf(global_position.x + (60.0 if randf() < 0.5 else -60.0), pool_x0, pool_x1)    # cofa się po dostaniu w pysk
	_event.rpc("released" if success else "dragged")

# ---------------------------------------------------------------- obrażenia

## Pełne obrażenia tylko wynurzona (zasadzka, chwyt, plucie); zanurzona: w świetle flary 40%, w ciemności 5%.
## Światło służy więc do przewidzenia zasadzki i podcinania, a prawdziwe okno obrażeń trzeba wywołać (przynęta) i wykorzystać.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	var surfaced := mode == Mode.UP or mode == Mode.GRAB
	var before := hp
	if mode == Mode.GRAB and _grab_victim != null and String(info.get("type", "")) == "melee" and int(info.get("shooter", -1)) == int(_grab_victim.player_id):
		_grab_dmg += float(info["amount"]) * (GRAB_MELEE_MULT - 1.0)       # cios chwyconego liczy się podwójnie (reszta w _hit)
	_hit(float(info["amount"]), surfaced)
	return {"hit": true, "dealt": before - hp, "killed": state == State.DEAD,
		"mat": Arsenal.Mat.FLESH if (surfaced or revealed) else Arsenal.Mat.WOOD}

func take_bullet_dir(_from_pos: Vector2, dmg: float, _dir: Vector2) -> void:
	if NoiseMgr.is_server():
		_hit(dmg, mode == Mode.UP or mode == Mode.GRAB)

func take_bullet(_from_pos: Vector2, dmg: float = 8.0) -> void:
	if NoiseMgr.is_server():
		_hit(dmg, mode == Mode.UP or mode == Mode.GRAB)

func _hit(dmg: float, surfaced: bool) -> void:
	if state != State.AWAKE:
		return
	if not surfaced:
		dmg *= LIT_MULT if revealed else SUB_MULT
	else:
		_flash = 0.08
		if mode == Mode.GRAB:
			_grab_dmg += dmg
	hp -= dmg
	if phase == 1 and hp <= max_hp * 0.66:
		phase = 2
		_minion_t = _minion_every(1)
		_surge_cd = SURGE_FIRST * Difficulty.m("boss_tide")
		_spawn_minions(2)
		_event.rpc("phase2")
	if phase == 2 and hp <= max_hp * 0.33:
		phase = 3
		_minion_t = _minion_every(2)
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
	_surge_t += delta
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
			Vfx.splash(get_parent(), pos, 1.6)
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
			Vfx.splash(get_parent(), pos, 2.0)
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 4.0, 0.4)
			Audio.play_variant_at("stalker_growl", 2, pos, Audio.BUS_STALKER, 0.0, 0.55)
			_shake_near(5.0)
		"dive":
			Vfx.splash(get_parent(), pos, 0.9)
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, -2.0, 0.7)
		"phase2":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, -3.0, 0.7)
			_shake_near(3.0)
		"phase3":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, 0.0, 0.5)
			Audio.sting(2)
			Lights.flicker_until_ms = Time.get_ticks_msec() + 3000
			_shake_near(6.0)
		"spit":
			Vfx.splash(get_parent(), pos, 1.0)
			Audio.play_variant_at("stalker_growl", 2, pos, Audio.BUS_STALKER, -3.0, 1.1)
			Audio.play_variant_at("step_water", 3, pos, Audio.BUS_WORLD, 1.0, 0.9)
		"surge_warn":
			surge_state = "warn"
			_surge_t = 0.0
			Audio.play_variant_at("amb_thud", 2, Vector2(pool_x0 + (pool_x1 - pool_x0) * 0.5, surf_y), Audio.BUS_AMB, 2.0, 0.5)
			Audio.sting(1)
			_shake_near(1.5)
		"surge_on":
			surge_state = "on"
			_surge_t = 0.0
			var mid := Vector2(pool_x0 + (pool_x1 - pool_x0) * 0.5, surf_y)
			Audio.play_variant_at("step_water", 3, mid, Audio.BUS_WORLD, 6.0, 0.4)
			Audio.play_variant_at("explosion", 2, mid, Audio.BUS_WORLD, -8.0, 0.5)
			for sx in 4:
				Vfx.splash(get_parent(), Vector2(lerpf(pool_x0, pool_x1, (float(sx) + 0.5) / 4.0), surf_y), 1.4)
			_shake_near(4.0)
		"surge_off":
			surge_state = "fall"
			_surge_t = 0.0
			Audio.play_variant_at("step_water", 3, Vector2(pool_x0 + (pool_x1 - pool_x0) * 0.5, surf_y), Audio.BUS_WORLD, 0.0, 0.7)
		"fury":
			Audio.play_variant_at("stalker_shriek", 2, pos, Audio.BUS_STALKER, 1.0, 0.45)
			Lights.flicker_until_ms = Time.get_ticks_msec() + 1800
			_shake_near(5.0)
		"surface2":
			Vfx.splash(get_parent(), Vector2(second_x if second_x >= 0.0 else pos.x, pos.y), 1.3)
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
	_animate_sprite(delta)
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
			if _spr.is_empty():
				_draw_body(t)
			else:
				_draw_ripples(0.45)                                      # ciało i oczy rysuje arkusz; kręgi na wodzie zostają

## Wynurzona Pijawka z arkusza: rise → idle, grab (głowa nisko, szeroka paszcza), dead; zwrócona twarzą do celu.
func _animate_sprite(delta: float) -> void:
	if _spr.is_empty():
		return
	var up := mode == Mode.UP or mode == Mode.GRAB
	var body: AnimatedSprite2D = _spr[0]
	var glow: AnimatedSprite2D = _spr[1]
	body.visible = up
	if glow != null:
		glow.visible = up
	if not up:
		_prev_mode = mode
		return
	if _prev_mode != Mode.UP and _prev_mode != Mode.GRAB:
		_rise_t = RISE_TIME                                              # świeże wynurzenie
		body.frame = 0
	_prev_mode = mode
	_rise_t = maxf(0.0, _rise_t - delta)
	var face := _face_target()
	if absf(face - global_position.x) > 6.0:
		_face_left = face < global_position.x
	var anim := "idle"
	if state == State.DEAD:
		anim = "dead"
	elif mode == Mode.GRAB:
		anim = "grab"
	elif _rise_t > 0.0:
		anim = "rise"
	Sprites.play(_spr, anim, _face_left)
	body.modulate = Color(2.4, 2.2, 2.2) if _flash > 0.0 else Color.WHITE
	if glow != null:
		glow.modulate = Color(1.0, 0.85, 0.7).lerp(Color(1.4, 0.7, 0.6), 0.5 * float(phase - 1))

## Gdzie patrzy: chwycona ofiara, inaczej najbliższy żywy gracz.
func _face_target() -> float:
	var best := global_position.x
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		if mode == Mode.GRAB and grab_victim_id != 0 and int(p.player_id) == grab_victim_id:
			return p.global_position.x
		var d := absf(p.global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = p.global_position.x
	return best

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
