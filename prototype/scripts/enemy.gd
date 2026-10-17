extends CharacterBody2D
## Wróg podstawowy: Trzosek (wataha, szybki) i Wołek (tank). GDD §7.1.
## Symulacja TYLKO na serwerze; klienci interpolują pozycję i rysują.
##
## Wróg śpi, dopóki nie usłyszy głośnego zdarzenia (strzał, granat — NIE kroki)
## w swoim promieniu słyszenia albo gracz nie podejdzie za blisko. Dzięki temu
## cisza i skradanie mają realną wartość także wobec zwykłych wrogów (filar 2).

const EnemyDefs := preload("res://scripts/enemy_defs.gd")
## Dane rodzajów (statystyki, zmysły, dropy, XP, głos) żyją w `enemy_defs.gd`; `Enemy.KINDS` zostaje jako ta sama tabela dla kodeksu, HUD-u i testów.
const KINDS := EnemyDefs.DEFS

const Lights := preload("res://scripts/lights.gd")
const Hurtbox := preload("res://scripts/hurtbox.gd")
const Throwables := preload("res://scripts/throwables.gd")
const SmokeCloud := preload("res://scripts/smoke_cloud.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Nav := preload("res://scripts/nav.gd")
const Surfaces := preload("res://scripts/surfaces.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Behavior := preload("res://scripts/enemy_behavior.gd")

const GRAVITY := 900.0
const MAX_FALL := 620.0
## Kroki (0,25 na tick) nie budzą; każdy strzał tak — także pierwszy z zimnej
## lufy M-83 (0,6). Przy progu 1,0 pojedyncze strzały M-83 były dla wrogów nieme.
const MIN_WAKE_NOISE := 0.5
const SIBLING_WAKE_RADIUS := 140.0
const DEATH_FX_COLOR_VAR := 0.15
const BURN_DPS := 8.0
const ARMOR_MIN_FRAC := 0.4           ## pancerz nigdy nie zbija trafienia poniżej tego ułamka
## Percepcja (1.7): wróg goni tylko to, co widzi (promień wzroku + linia bez ściany), albo idzie
## na ostatni znany ślad (hałas, ostatnia pozycja gracza), rozgląda się, a po dłuższym braku
## kontaktu wraca do domu i zasypia. Wcześniej obudzony wróg znał położenie gracza na całej mapie.
const SEARCH_TIME := 3.5         ## s rozglądania się po dojściu na ślad
const GIVE_UP_TIME := 9.0        ## s bez kontaktu, po których porzuca ślad
const HOME_SLEEP_TIME := 1.2     ## s w domu, po których znów zasypia
const PERCEIVE_DT := 0.12        ## co tyle sprawdzamy wzrok (promień)
const TARGET_BOT_W := 1.3             ## wagi celu (F3.5b), mnożą odległość: bot mniej pożądany, latarka / ogień / ranny / odizolowany bardziej
const TARGET_LIGHT_W := 0.8
const TARGET_FIRING_W := 0.85
const TARGET_WOUNDED_W := 0.9
const TARGET_ISOLATED_W := 0.9
const TARGET_ISOLATED_R := 150.0      ## px: nikt żywy tak blisko gracza = jest odizolowany
const MIN_WINDUP := 0.25              ## s: najkrótsza zapowiedź zwykłego ciosu po trudności (F3.6b) — krócej gracz nie ma szans zareagować
const TARGET_SWITCH_RATIO := 0.7 ## nowy cel musi być bliżej niż 70% odległości do dotychczasowego, żeby wróg go zmienił (histereza)
const ALERT_COOLDOWN := 5.0      ## s: tyle po reakcji „zauważył" wróg nie staje drugi raz (cel migający w polu widzenia)
const ALERT_JITTER := 0.15       ## ±: rozrzut czasu reakcji, żeby wataha nie ruszała w jednej klatce
const CROUCH_SIGHT := 0.6        ## kucającego widać z mniejszej odległości
const JUMP_V := -275.0           ## skok po grafie A* (42 px, tyle co gracz)
const STEP_HOP_V := -200.0           ## przeskok na stopień o 1 kafel dla wrogów, którzy nie skaczą (Ślepiec, Wołek): szczyt ≈ 22 px nad podłogą
const STEP_MAX_RISE := 16.5          ## px: najwyższy stopień (1 kafel)
const PLATFORM_BIT := 5          ## warstwa kładek w masce (zeskok)
const FIRE_BIT := 7              ## warstwa „muru ognia” (fire_patch.gd): blokuje wrogów z flagą fire_shy, drużyny nie rusza
const DROP_TIME := 0.25
## Słyszalność po trasie (1.7.4): dźwięk nie przechodzi przez ściany ani piętra — liczy się długość
## ścieżki po grafie nawigacji, nie linia prosta. Bez ścieżki (brak węzła) — tłumienie przez mur.
const SOUND_MUFFLE := 3.0
const WINDUP_INTERRUPT_STUN := 0.4   ## s ogłuszenia z trafienia, od którego przerywa się zapowiedź ciosu (strzelba, szyna, harpun, maczeta; F3.6)
const WINDUP_INTERRUPT_CD := 0.6     ## s przerwy po przerwanym ciosie (× enemy_cd trudności)
const LIGHT_LURE_R := 360.0          ## ciekawość Trzosków: flara w tym promieniu (po trasie) daje im ślad
## Pamięć: wracający do domu wróg sprawdza „gorące miejsce" (gdzie ostatnio strzelano)
const PATROL_RADIUS := 600.0
const PATROL_MAX_AGE := 90.0
const ALARM_JITTER := 0.2        ## s losowego opóźnienia odpowiedzi na alarm (F3.8), żeby wataha nie ruszała w tej samej klatce
const HISTORY_S := 0.5            ## historia pozycji do kompensacji opóźnienia (lag_comp.gd)
const SCREAM_LURE_R := 400.0     ## krzyk GRACZA (voice.gd, GDD §8.2) przyciąga wrogów w 25 m

@export var kind := "trzosek"
var _beh                       ## zachowanie rodzaju (`enemy_behavior.gd` i podklasy) — haki rdzenia, patrz `enemy_behavior.gd`

## Jawny stan AI (ENEMY_PLAN.md F3): to, co wróg „robi" w tej chwili. Dotąd wynikał z kolejności gałęzi w `_phys_tick`; teraz jest liczony raz na tik
## z tych samych flag (`_derive_ai_state`), replikowany klientom i podawany widokowi 3D (`view_info`). Na razie tylko obserwacja — decyzje wciąż
## podejmują stare gałęzie; kolejne kroki F3 (reakcja „zauważył", flankowanie, wybór celu) będą dopisywać stany i na nich oprzeć decyzje.
enum Ai { DEAD, SLEEP, HANG, LISTEN, FLY, INVESTIGATE, SEARCH, CHASE, WINDUP, RETREAT, PANIC, SPECIAL, RETURN, ALERT, LUNGE, SCREAM }
const AI_NAMES := ["dead", "sleep", "hang", "listen", "fly", "investigate", "search", "chase", "windup", "retreat", "panic", "special", "return", "alert", "lunge", "scream"]
## Zmiana stanu AI (serwer; u klientów po `_sync`): `from_state` → `to_state` (wartości `Ai`).
signal ai_changed(from_state: int, to_state: int)

## Nie jest nieśmiertelny, więc boty mogą do niego strzelać, gdy jest aktywny.
var immortal := false
var hp := 30.0
var active := false
var alive := true
var winding := false
var _voiced_winding := false  ## czy zapowiedź ciosu już się odezwała (zbocze `winding`, lokalnie na każdym peerze)
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
var _facing := 1.0             ## SYMULACJA (serwer): w którą stronę patrzy wróg — cios w plecy, ucieczka w panice; liczone z ruchu w `_update_facing`, bez warstwy animacji
var _phys_x := 0.0
var _view_facing := 1.0        ## PREZENTACJA (każdy peer): zwrot modelu; Podsłuchacz patrzy tu na lokalnego gracza, u klientów kierunek z przesunięcia pozycji
var _last_x := 0.0
## Percepcja i nawigacja (serwer)
var omniscient := false       ## potomstwo Żyły zawsze zna położenie graczy
var summoned := false         ## przywołany przez bossa (potomstwo Żyły, Trzoski Pijawki): bez XP i dropów — inaczej dałoby się na nich farmić
var _target: Node2D = null    ## gracz, którego widzi
var _perceive_t := 0.0
var _flash_check_ms := 0      ## kiedy (ms silnika) śpiący wróg znów sprawdza, czy świeci na niego latarka
var _has_lead := false        ## ma ślad do sprawdzenia
var _last_known := Vector2.ZERO
var _lose_t := 0.0
var _search_t := 0.0
var _blocked_t := 0.0         ## s, od kiedy pościg stoi pod skokiem, którego wróg nie potrafi
var _stuck_t := 0.0           ## s bez ruchu w drodze do domu (`_return_home`)
var _stuck_x := 0.0
var _ignore_t := 0.0          ## s, przez które wróg ignoruje graczy (porzucił nieosiągalny cel)
const BLOCK_GIVEUP := 4.0
const RETURN_STUCK_TIME := 4.0       ## s w miejscu w drodze do domu, po których dom przenosi się na miejsce postoju
const IGNORE_TIME := 8.0
var _home_t := 0.0
var _path: Array = []
var _path_i := 0
var _repath := 0.0
var _path_goal := Vector2.ZERO
var _drop_t := 0.0
var _blocked := false         ## następny krok grafu to skok, którego nie potrafi
var _hist: Array = []         ## Vector3(czas, x, y) — pozycje z ostatnich HISTORY_S s (serwer)
var _flee_src := Vector2.ZERO ## od czego ucieka w panice (ZERO = od gracza)
var _sp := 0                  ## Wołek: 0 nic, 1 zapowiedź szarży, 2 szarża, 3 zapowiedź rzutu, 4 ogłuszony po uderzeniu
var _ai: int = Ai.SLEEP       ## bieżący stan AI (patrz `Ai`)
var _ai_t := 0.0              ## s w bieżącym stanie AI (serwer)
var _alert := 0.0             ## s reakcji „zauważył cię" (stan Ai.ALERT): wróg stoi i patrzy na źródło, zanim ruszy (serwer)
var _sweep_dir := 1.0         ## kierunek przeszukiwania okolicy śladu (Ślepiec)
var _alert_cd := 0.0          ## s do następnej reakcji — ten sam wróg nie staje za każdym razem, gdy cel mignie na granicy wzroku
var _net_face := 0.0          ## kierunek patrzenia z serwera (u klientów; `_sync`) — odwrót przy reakcji „zauważył"
var _hanging := false         ## Skoczek / ćma wiszą pod sufitem, dopóki ich nic nie obudzi
var _patrolled := false       ## wracając do domu sprawdził już jedno gorące miejsce
var _last_attacker := 0               ## player_id ostatniego trafiającego (XP za zabójstwo, profile.gd)
var _ring := 0.0              ## efekt fali krzyku (każdy peer)
var _level_t := 0.0           ## s, przez które cel jest na innym poziomie (histereza: skok gracza to nie zmiana piętra)

func _on_ai_changed(_from: int, to: int) -> void:
	if to == Ai.ALERT and alive:
		_voice("alert")                   # cichy, wysoki warkot — na każdym peerze, z własnej zmiany stanu

func _ready() -> void:
	add_to_group("enemies")
	ai_changed.connect(_on_ai_changed)
	_def = KINDS.get(kind, KINDS["trzosek"])
	_beh = Behavior.create(String(_def.get("behavior", "")), self)
	for ev in ["attack", "alert", "death"]:                 # głosy rodzaju wczytane z góry: pierwszy warkot w walce nie zacina klatki
		var vo: Array = EnemyDefs.voice(kind, ev)
		if not vo.is_empty():
			Audio.warm_family(String(vo[0]), int(vo[1]))
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
	Hurtbox.add(self, float(_def.get("hurt_w", size.x)), _hurt_h())   # strefa trafień na wysokość modelu (ciało ruchu zostaje niższe)
	# oczy i pasek HP świecą w ciemności — śpiącego wroga widać jako
	# przygaszone oczy, a nie wcale (skradanie musi mieć informację)
	if Sprites.has(Sprites.enemy_sheet(kind)):
		_spr = Sprites.attach(self, Sprites.enemy_sheet(kind))
	_last_x = global_position.x
	_phys_x = global_position.x
	if _def.get("fire_shy", false):
		set_collision_mask_value(FIRE_BIT, true)         # ogień na podłodze jest dla nich murem
	_hanging = bool(_def.get("hang", false)) or bool(_def.get("moth", false))
	if _def.get("fly", false):
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING     # ćma lata — bez „podłogi" i grawitacji
	_overlay = Lights.add_overlay(self)

## Aktywny, żywy wróg = realne zagrożenie (boty strzelają tylko do takich).
func is_threat() -> bool:
	return alive and active and _beh.threat_ok()

func wake() -> void:
	if not NoiseMgr.is_server() or not alive or active:
		return
	active = true
	_beh.on_wake()
	if not _has_lead:
		var p := _nearest_player()
		if p != null:
			_lead_at(p.global_position)
	_begin_alert()                       # obudzony hałasem lub światłem: chwila na zorientowanie się, zanim ruszy
	# cała wataha budzi się razem
	for e in _near(global_position, SIBLING_WAKE_RADIUS):
		if is_instance_valid(e) and e != self and e.has_method("wake") and e.global_position.distance_to(global_position) < SIBLING_WAKE_RADIUS:
			e.wake()

## HP z uwzględnieniem poziomu trudności (difficulty.gd).
func _scaled_hp() -> float:
	var lvl := get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	return float(_def["hp"]) * Difficulty.m("enemy_hp") * NightShift.hp_mult() * (float(lvl.hp_mult) if lvl != null else 1.0)

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
	_alert = 0.0
	_alert_cd = 0.0
	_target = null
	_hist.clear()
	_has_lead = false
	_lose_t = 0.0
	_search_t = 0.0
	_flee_src = Vector2.ZERO
	_sp = 0
	_beh.reset()
	_hanging = bool(_def.get("hang", false)) or bool(_def.get("moth", false))
	_patrolled = false
	_level_t = 0.0
	_home_t = 0.0
	_path.clear()
	_drop_t = 0.0
	set_collision_mask_value(PLATFORM_BIT, true)
	velocity = Vector2.ZERO
	global_position = _home
	_remote_pos = _home
	_set_alive(true)
	_ai_t = 0.0
	_set_ai_state(_derive_ai_state())

func _set_alive(a: bool) -> void:
	alive = a
	visible = a
	Hurtbox.set_enabled(self, a)
	if not a:
		_set_ai_state(Ai.DEAD)

## Siatka przestrzenna wrogów (komórka 48 px), budowana raz na klatkę fizyki przy pierwszym zapytaniu: pętle „każdy z każdym" (separacja, budzenie
## watahy, blokada ataku, śmierć w watasze) przeglądają tylko sąsiednie komórki zamiast całej grupy — koszt rośnie liniowo z liczbą wrogów.
const GRID_CELL := 48.0
static var _grid: Dictionary = {}
static var _grid_frame := -1

## Wszyscy z grupy „enemies" (też rekwizyty, gniazda, bossowie) w komórkach pokrywających koło `radius` wokół `pos`; wywołujący filtruje dokładnie.
func _near(pos: Vector2, radius: float) -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _grid_frame:
		_grid_frame = frame
		_grid.clear()
		for e in get_tree().get_nodes_in_group("enemies"):
			var n2 := e as Node2D
			if n2 == null or not is_instance_valid(n2):
				continue
			var key := Vector2i(floori(n2.global_position.x / GRID_CELL), floori(n2.global_position.y / GRID_CELL))
			if _grid.has(key):
				(_grid[key] as Array).append(n2)
			else:
				_grid[key] = [n2]
	var out: Array = []
	var c0 := Vector2i(floori((pos.x - radius) / GRID_CELL), floori((pos.y - radius) / GRID_CELL))
	var c1 := Vector2i(floori((pos.x + radius) / GRID_CELL), floori((pos.y + radius) / GRID_CELL))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cy))
			if cell != null:
				out.append_array(cell)
	return out

## Budżet wyszukiwań A* na klatkę fizyki dla WSZYSTKICH wrogów (`_steer_to`): gdy cała mapa przelicza trasy naraz (gracz skoczył daleko, wataha się obudziła),
## nadmiar czeka do następnej klatki i wróg jedzie po starej trasie — zamiast jednej klatki 30 ms.
const PATH_BUDGET := 6
static var _path_frame := -1
static var _path_used := 0

static func _path_slot() -> bool:
	var f := Engine.get_physics_frames()
	if f != _path_frame:
		_path_frame = f
		_path_used = 0
	if _path_used >= PATH_BUDGET:
		return false
	_path_used += 1
	return true

## Liczniki do pomiarów (main.gd `_perf_run`): czas całego `_physics_process` wrogów, w tym `move_and_slide`.
static var stat_usec := 0
static var stat_slide_usec := 0

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_phys_tick(delta)
	stat_usec += Time.get_ticks_usec() - t0

func _slide() -> void:
	var t0 := Time.get_ticks_usec()
	move_and_slide()
	stat_slide_usec += Time.get_ticks_usec() - t0

func _phys_tick(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if not NoiseMgr.is_server():
		global_position = global_position.lerp(_remote_pos, 0.35)
		return
	if not alive:
		return
	_tick_server(delta)
	_ai_t += delta
	_set_ai_state(_derive_ai_state())

## Stan AI z flag symulacji — w kolejności, w jakiej gałęzie `_tick_server` przejmują ruch (pierwsza prawdziwa wygrywa).
func _derive_ai_state() -> int:
	if not alive:
		return Ai.DEAD
	var pre: int = _beh.derive_pre()
	if pre >= 0:
		return pre
	if not active:
		return Ai.HANG if _hanging else Ai.SLEEP
	if _sp != 0:
		return Ai.SPECIAL
	if _windup > 0.0:
		return Ai.WINDUP
	if _panic > 0.0:
		return Ai.PANIC
	if _alert > 0.0:
		return Ai.ALERT
	var mid: int = _beh.derive_mid()
	if mid >= 0:
		return mid
	if _target != null:
		return _beh.chase_state()
	if _has_lead:
		return Ai.SEARCH if _search_t > 0.0 else Ai.INVESTIGATE
	return Ai.RETURN

func _set_ai_state(s: int) -> void:
	if s == _ai:
		return
	var from := _ai
	_ai = s
	_ai_t = 0.0
	ai_changed.emit(from, s)

## Reakcja „zauważył cię" (F3.1b): wróg z polem `alert` w `enemy_defs.gd` staje na ten czas (skalowany trudnością jak zapowiedź ciosu, ±ALERT_JITTER)
## i odwraca się ku źródłu (cel, inaczej ślad), a dopiero potem goni albo sprawdza ślad. Nie dotyczy przywołanych przez bossa (wiedzą, gdzie są gracze)
## ani rodzajów bez pola; po reakcji ALERT_COOLDOWN s spokoju, a trafienie ją przerywa.
func _begin_alert() -> void:
	var base := float(_def.get("alert", 0.0))
	if base <= 0.0 or summoned or omniscient or _alert > 0.0 or _alert_cd > 0.0 or not alive:
		return
	_alert = base * Difficulty.m("enemy_windup") * randf_range(1.0 - ALERT_JITTER, 1.0 + ALERT_JITTER)
	_alert_cd = ALERT_COOLDOWN
	var src_x := _target.global_position.x if _target != null else _last_known.x
	if absf(src_x - global_position.x) > 4.0:
		_facing = signf(src_x - global_position.x)
	_set_ai_state(Ai.ALERT)                      # od razu, żeby `_sync` i głos w tym tiku niosły nowy stan

## Nazwa stanu AI do logów i testów.
func ai_name() -> String:
	return AI_NAMES[_ai]

## Jeden tik symulacji serwera: percepcja, decyzja, ruch (stan AI liczy `_phys_tick` po nim).
func _tick_server(delta: float) -> void:
	_record_history()
	_update_facing()
	_cd = maxf(0.0, _cd - delta)
	_leap_cd = maxf(0.0, _leap_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_panic = maxf(0.0, _panic - delta)
	_alert = maxf(0.0, _alert - delta)
	_alert_cd = maxf(0.0, _alert_cd - delta)
	_beh.tick_prelude(delta)
	_tick_drop(delta)
	_tick_burn(delta)
	if not alive:
		return
	if _beh.tick_special(delta):
		return

	if not active:
		_check_wake()
		_beh.tick_asleep(delta)
		if _hanging:
			_beh.tick_hanging()
			velocity = Vector2.ZERO          # wisi pod sufitem — bez grawitacji
			_send_state(delta)
			return
		# śpiący wróg stoi i słucha, ale grawitacja działa
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		_slide()
		_send_state(delta)
		return

	_listen()
	_perceive(delta)
	var target := _target
	var speed: float = float(_def["speed"]) * Difficulty.m("enemy_speed")
	if _stagger > 0.0:
		speed *= 0.25
	if not _def.get("fly", false):
		speed *= _surface_speed()          # bagno, błoto i olej spowalniają też potwory — da się je tam zwabić
	_beh.tick_awake(delta)

	# faza specjalna rodzaju (Wołek: szarża i rzuty) przejmuje ruch na czas swoich faz
	if _beh.tick_phase(delta, target):
		_apply_gravity(delta)
		_slide()
		_beh.after_phase_move()
		_send_state(delta)
		return

	if _windup > 0.0:
		_windup -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _windup <= 0.0:
			_resolve_attack()
	elif _panic > 0.0:
		# ucieczka: płonący Trzosek (HKM-9), załamane morale watahy, strach przed Stalkerem
		var src_x := _flee_src.x if _flee_src != Vector2.ZERO else (target.global_position.x if target != null else global_position.x - _facing)
		velocity.x = -signf(src_x - global_position.x) * speed * 0.9
	elif _alert > 0.0 or _beh.holds_still():
		# „zauważył cię" / zapowiedź szarży na dźwięk: staje i patrzy na źródło, zanim ruszy (czas i odwrót w `_begin_alert` / `maybe_lunge`)
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
	elif _beh.drive(delta, target, speed):
		pass
	elif target != null:
		_chase(target, speed, delta)
		_try_begin_attack(target)
	elif _has_lead:
		_investigate(speed, delta)
	else:
		_return_home(speed, delta)

	_apply_gravity(delta)
	_slide()
	_beh.after_slide()
	_send_state(delta)

## Czas zapowiedzi zwykłego ciosu po trudności: `base` × mnożnik, ale nie krócej niż MIN_WINDUP (F3.6b) — Trzosek na trudnym (0,28 × 0,8 = 0,22 s) był poniżej ludzkiej reakcji.
static func windup_time(base: float, mult: float) -> float:
	return maxf(base * mult, MIN_WINDUP)

## Obrażenia ataku wroga po poziomie trudności (zaokrąglane, min. 1) — jedno miejsce dla zwykłego ciosu, lądowania skoczka, szarży Wołka i ćmy.
func _scaled_damage(base: int) -> int:
	return maxi(1, roundi(float(base) * Difficulty.m("enemy_damage")))

## Kierunek patrzenia z faktycznego ruchu (serwer, co tik fizyki) — nie zależy od warstwy animacji, więc cios w plecy działa, nawet gdy jej nie ma.
## Podsłuchacz stoi i patrzy na swój cel (F3.8), a bez celu na ślad hałasu albo najbliższego gracza — kierunek liczy serwer i replikuje go w `_sync`
## (wcześniej każdy peer widział go zwróconego do własnego gracza).
func _update_facing() -> void:
	var dx := global_position.x - _phys_x
	_phys_x = global_position.x
	if absf(dx) > 0.05:
		_facing = signf(dx)
	var look: Vector2 = _beh.look_at_point()
	if is_finite(look.x) and absf(look.x - global_position.x) > 4.0:
		_facing = signf(look.x - global_position.x)


## Mocne ogłuszenie (strzelba, szyna, harpun, maczeta) przerywa zwykły cios w trakcie zapowiedzi (F3.6) — kontra, którą gracz może zaplanować: zapowiedź
## daje czas na unik ALBO na ogłuszenie. Nie dotyczy zapowiedzi specjalnych Wołka (`_sp`), przemiany Mimika (bez celu ciosu) i krzyku Podsłuchacza
## (który i tak zaczyna się od nowa po trafieniu). Po przerwaniu krótka przerwa, żeby wróg nie ponowił ciosu w tej samej chwili.
func _interrupt_windup() -> void:
	if _windup <= 0.0 or _windup_target == null or _sp != 0 or not _beh.can_interrupt_windup():
		return
	_windup = 0.0
	_windup_target = null
	winding = false
	_cd = maxf(_cd, WINDUP_INTERRUPT_CD * Difficulty.m("enemy_cd"))

## Krzyk gracza (mikrofon albo G): wróg w promieniu 25 m rusza do źródła; śpiącego budzi.
func hear_scream(pos: Vector2) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	var lim := SCREAM_LURE_R * Difficulty.m("enemy_hear")
	var heard := _sound_distance(pos, lim)
	if heard > lim:
		return
	_lead_at(_heard_pos(pos, heard, lim, NoiseMgr.N_SCREAM))        # krzyk jest głośny (mały błąd), ale też nie wskazuje punktu co do piksela
	wake()

## --- kompensacja opóźnienia (lag_comp.gd) ----------------------------------

func _record_history() -> void:
	var t := LagComp.now()
	_hist.append(Vector3(t, global_position.x, global_position.y))
	while _hist.size() > 2 and (_hist[0] as Vector3).x < t - HISTORY_S:
		_hist.pop_front()

## Prostokąt trafień wroga tak, jak stał w chwili `at_time` (interpolacja z historii).
func lag_rect(at_time: float) -> Rect2:
	var p := global_position
	var n := _hist.size()
	if n > 0 and at_time < (_hist[n - 1] as Vector3).x:
		var first: Vector3 = _hist[0]
		if at_time <= first.x:
			p = Vector2(first.y, first.z)
		else:
			for i in range(n - 1, 0, -1):
				var a: Vector3 = _hist[i - 1]
				var b: Vector3 = _hist[i]
				if at_time >= a.x:
					var k := inverse_lerp(a.x, b.x, at_time)
					p = Vector2(lerpf(a.y, b.y, k), lerpf(a.z, b.z, k))
					break
	var size := Vector2((_def["size"] as Vector2).x, _hurt_h())
	return Rect2(p.x - size.x * 0.5 - 1.0, p.y - size.y - 1.0, size.x + 2.0, size.y + 2.0)

## Mnożnik prędkości wynikający z powierzchni pod stopami (surfaces.gd).
func _surface_speed() -> float:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return 1.0
	return float(Surfaces.of(lvl.surface_at(global_position))["speed"])

## --- światło ---------------------------------------------------------------

## Flara (flare.gd, serwer) świeci w `pos`: światłolubni (Trzosek) dostają ślad, jeśli to blisko po trasie;
## ślepych i niewidzących światło nie obchodzi. Wabik bez hałasu — za to widoczny.
func see_light(pos: Vector2) -> void:
	if not NoiseMgr.is_server() or not alive or not _def.get("phototaxis", false) or _def.get("moth", false):
		return
	if _target != null:
		return                          # ma gracza przed oczami — nie da się odciągnąć
	if _sound_distance(pos, LIGHT_LURE_R) > LIGHT_LURE_R:
		return
	_lead_at(pos)
	if not active:
		wake()

## --- Mimik ----------------------------------------------------------------

@rpc("authority", "call_local", "unreliable")
func _mimic_call() -> void:
	Audio.play_variant_at("player_hurt", 2, global_position, Audio.BUS_WORLD, -5.0, randf_range(0.95, 1.1))

## Efekt uderzenia Wołka o ścianę (RPC musi żyć w węźle wroga; woła go `enemy_bruiser.gd` i lądowanie Skoczka).
@rpc("authority", "call_local", "reliable")
func _crash_fx() -> void:
	Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, 0.0, 0.5)
	Vfx.dust(get_parent(), global_position, 1.0)
	if _local_player_pos().distance_to(global_position) < 300.0:
		Feel.shake(3.5)

## Odpowiedź na alarm Podsłuchacza (F3.8): ślad z błędem lokalizacji jak przy każdym hałasie (`hear_error` rodzaju), a wrogowie dalej budzą się później —
## głos niesie `wave` px/s plus rozrzut do ALARM_JITTER, więc horda nie rusza w jednej klatce, tylko falą od krzykacza.
func answer_alarm(pos: Vector2, heard: float, radius: float, wave: float) -> void:
	var lead := _heard_pos(pos, heard, radius, NoiseMgr.N_SCREAM)
	var delay := (heard / wave + randf_range(0.0, ALARM_JITTER)) if wave > 0.0 else 0.0
	if delay < 0.02:
		_hear_alarm(lead)
	else:
		get_tree().create_timer(delay).timeout.connect(_hear_alarm.bind(lead))

func _hear_alarm(lead: Vector2) -> void:
	if not alive:
		return
	_lead_at(lead)
	wake()

## Krzyk na każdym peerze: dźwięk, fala, lekki wstrząs kamery.
@rpc("authority", "call_local", "reliable")
func _scream_fx() -> void:
	_ring = 0.7
	Audio.play_variant_at("podsluchacz_scream", 2, global_position, Audio.BUS_WORLD, -3.0, _beh.scream_pitch())
	if _local_player_pos().distance_to(global_position) < 300.0:
		Feel.shake(2.2)

## --- percepcja ------------------------------------------------------------

func _lead_at(pos: Vector2) -> void:
	_patrolled = false
	_last_known = pos
	_has_lead = true
	_lose_t = 0.0
	_search_t = 0.0

## Nowy głośny dźwięk w pobliżu odświeża ślad (wróg idzie do źródła, nie do gracza).
func _listen() -> void:
	if NoiseMgr.noise_serial == _seen_serial:
		return
	var reach := _noise_reach(NoiseMgr.last_noise_amount, 1.4)
	if reach > 0.0 and _sound_needs_path(NoiseMgr.last_noise_pos, reach) and not _sound_slot():
		return                                # budżet A* tej klatki wyczerpany — hałas zostaje nieprzeczytany, wróg usłyszy go w następnej
	_seen_serial = NoiseMgr.noise_serial
	if reach > 0.0:
		var heard := _sound_distance(NoiseMgr.last_noise_pos, reach)
		if heard < reach:
			var lead := _heard_pos(NoiseMgr.last_noise_pos, heard, reach, NoiseMgr.last_noise_amount)
			_lead_at(lead)
			_beh.on_heard_noise(lead, heard, NoiseMgr.last_noise_amount)

## Lokalizacja hałasu z niedokładnością (F3.2): wróg słyszy, że „coś hałasuje stamtąd", ale nie wskazuje punktu co do piksela — im dalej źródło
## (względem zasięgu słyszenia) i im ciszej, tym większy błąd. Tylko w poziomie (pomyłka o piętro wysłałaby wroga na zły poziom); z bliska prawie dokładnie.
## Pole `hear_error` w `enemy_defs.gd` (px na granicy zasięgu przy głośnym zdarzeniu); cicha rzecz (≤ 0,5) myli się 1,5× bardziej.
const HEAR_ERROR := 64.0
const HEAR_ERROR_QUIET := 1.5                 ## mnożnik błędu dla zdarzeń cichych (kroki, ostatnie ułamki strzału z zimnej lufy)

## Przesunięcie poziome [px] źródła hałasu: `rnd` ∈ [−1, 1], `dist` — słyszalna odległość (po trasie), `reach` — zasięg słyszenia, `amount` — głośność zdarzenia.
static func heard_offset(error_max: float, dist: float, reach: float, amount: float, rnd: float) -> float:
	var ratio := clampf(dist / maxf(reach, 1.0), 0.0, 1.0)
	var quiet := lerpf(HEAR_ERROR_QUIET, 1.0, clampf((amount - MIN_WAKE_NOISE) / 1.5, 0.0, 1.0))
	return clampf(rnd, -1.0, 1.0) * error_max * ratio * quiet

func _heard_pos(pos: Vector2, dist: float, reach: float, amount: float) -> Vector2:
	return pos + Vector2(heard_offset(float(_def.get("hear_error", HEAR_ERROR)), dist, reach, amount, randf_range(-1.0, 1.0)), 0.0)

## Budżet wyszukiwań A* na klatkę fizyki dla słuchania hałasu (`_listen`, `_check_wake`): głośny strzał słyszy naraz cała okolica,
## a każdy słyszący liczył własną trasę w tej samej klatce. Nadmiar czeka do następnej klatki (ułamek sekundy opóźnienia reakcji).
const SOUND_BUDGET := 6
static var _snd_frame := -1
static var _snd_used := 0

static func _sound_slot() -> bool:
	var f := Engine.get_physics_frames()
	if f != _snd_frame:
		_snd_frame = f
		_snd_used = 0
	if _snd_used >= SOUND_BUDGET:
		return false
	_snd_used += 1
	return true

## Czy `_sound_distance` policzy dla tego źródła trasę A* (a nie odpowie z linii prostej).
func _sound_needs_path(pos: Vector2, limit: float) -> bool:
	var d := global_position.distance_to(pos)
	if d >= limit or d < 24.0:
		return false
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl != null and lvl.get("nav") != null

## Odległość „słyszalna" do punktu: długość trasy po grafie nawigacji (nav.gd), nie linia prosta —
## strzał nad głową przez piętro betonu jest daleko, ten sam strzał w sąsiednim korytarzu blisko.
## Trasa nie bywa krótsza niż linia prosta, więc dla odległych źródeł (≥ limit) nie liczymy A*.
func _sound_distance(pos: Vector2, limit: float) -> float:
	var d := global_position.distance_to(pos)
	if d >= limit or d < 24.0:
		return d
	var lvl := get_tree().get_first_node_in_group("level")
	var nav = lvl.get("nav") if lvl != null else null
	if nav == null:
		return d
	var path: Array = nav.find_path(global_position, pos)
	if path.size() < 2:
		return d * SOUND_MUFFLE
	var total := (path[0].pos as Vector2).distance_to(global_position)
	for i in range(1, path.size()):
		total += (path[i].pos as Vector2).distance_to(path[i - 1].pos)
	total += (path[path.size() - 1].pos as Vector2).distance_to(pos)
	return maxf(d, total)

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
	_ignore_t = maxf(0.0, _ignore_t - delta)
	if _ignore_t > 0.0:
		_target = null                    # porzucił nieosiągalny cel (stał pod ścianą, której nie przeskoczy) — nie blokuje korytarza, wraca do siebie
		return
	_perceive_t -= delta
	if _perceive_t > 0.0:
		if _target != null and (not is_instance_valid(_target) or _target.dead):
			_target = null
		return
	_perceive_t = PERCEIVE_DT
	var sight: float = float(_def.get("sight", 240.0)) * Difficulty.m("enemy_hear")
	var best: Node2D = null
	var best_score := INF                 # „punkty" celu: odległość × waga (`_target_weight`) — im mniej, tym bardziej pożądany
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		var score := d * _target_weight(pp)
		if score >= best_score:
			continue
		if not omniscient:
			if d > sight * (CROUCH_SIGHT if pp.crouching else 1.0) or not _clear_line(pp):
				continue
		best = pp
		best_score = score
	var had_target := _target != null
	# histereza celu (F3.5): dotychczasowy cel, który wróg wciąż widzi, zostaje, dopóki inny gracz nie jest wyraźnie lepszy (TARGET_SWITCH_RATIO punktów) —
	# przy dwóch graczach w podobnej odległości wróg nie przeskakuje między nimi co 0,12 s i nie zawraca w pół kroku
	if had_target and best != null and best != _target and is_instance_valid(_target) and not _target.dead and _can_see(_target, sight):
		if not _prefer_new_target(global_position.distance_to(_target.global_position) * _target_weight(_target), best_score):
			best = _target
	_target = best
	if best != null and not had_target and _ai in [Ai.INVESTIGATE, Ai.SEARCH, Ai.RETURN]:
		_begin_alert()                    # nowy kontakt wzrokowy po śledztwie / szukaniu / powrocie — nie przy każdym mignięciu celu (ALERT_COOLDOWN)
	if best != null and not had_target:
		_beh.on_sighting(best.global_position)
	if best != null:
		_lead_at(best.global_position)
	else:
		_lose_t += PERCEIVE_DT

## Waga gracza jako celu (F3.5b): mnożnik odległości, im mniejszy, tym chętniej wróg wybiera tego gracza. Człowiek bije bota (bot nie jest wabikiem),
## przyciąga światło latarki (nie ślepca) i ogień, a łatwiejszym łupem jest ranny (≤ 1 serce) i odizolowany od drużyny (nikt żywy w TARGET_ISOLATED_R).
func _target_weight(pp: Node2D) -> float:
	var w := 1.0
	if pp.is_bot:
		w *= TARGET_BOT_W
	if pp.flashlight and not _def.get("blind", false):
		w *= TARGET_LIGHT_W
	if pp.w_firing:
		w *= TARGET_FIRING_W
	if pp.hp <= 1:
		w *= TARGET_WOUNDED_W
	if _isolated(pp):
		w *= TARGET_ISOLATED_W
	return w

## Czy poza `pp` nie ma w TARGET_ISOLATED_R żadnego żywego gracza (sam jedyny gracz też jest „odizolowany" — waga jest wtedy tylko stałym mnożnikiem).
func _isolated(pp: Node2D) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		var o := p as Node2D
		if o != null and o != pp and not o.dead and o.global_position.distance_to(pp.global_position) <= TARGET_ISOLATED_R:
			return false
	return true

## Czy wróg widzi gracza `pp` (promień wzroku z poprawką na kucanie + czysta linia) — ta sama reguła co w pętli `_perceive`.
func _can_see(pp: Node2D, sight: float) -> bool:
	if omniscient:
		return true
	var d := global_position.distance_to(pp.global_position)
	return d <= sight * (CROUCH_SIGHT if pp.crouching else 1.0) and _clear_line(pp)

## Czy przerzucić się na nowy cel: tylko gdy ma wyraźnie mniej punktów (o `1 − TARGET_SWITCH_RATIO`) niż dotychczasowy (punkty = odległość × waga, `_target_weight`).
## `current_d` i `new_d` to punkty dotychczasowego i nowego celu.
static func _prefer_new_target(current_d: float, new_d: float) -> bool:
	return new_d < current_d * TARGET_SWITCH_RATIO

func _clear_line(pp: Node2D) -> bool:
	var h: float = (_def["size"] as Vector2).y * 0.6
	var a := global_position + Vector2(0, -h)
	var b := pp.global_position + Vector2(0, -8)
	if SmokeCloud.blocks(get_tree(), a, b):
		return false                      # dym (granat dymny) zasłania cel — słyszą, ale nie widzą
	var q := PhysicsRayQueryParameters2D.create(a, b, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## --- zachowanie bez widocznego celu ----------------------------------------

## Idzie na ostatni ślad, rozgląda się i rezygnuje; po dłuższym braku kontaktu wraca do domu.
## Przeszukiwanie okolicy śladu (Ślepiec, pole `sweep` = amplituda px): po dojściu do miejsca hałasu nie stoi jak kołek, tylko chodzi tam i z powrotem
## w ±`sweep` px od śladu, aż minie czas szukania (`search`). Gracz stojący na jego drodze w zasięgu dotyku (26 px) zostaje wyczuty.
func _sweep(amp: float, speed: float) -> void:
	var off := global_position.x - _last_known.x
	if absf(off) >= amp:
		_sweep_dir = -signf(off)
	elif is_on_wall():
		_sweep_dir = -_sweep_dir
	velocity.x = _sweep_dir * speed * 0.6

func _investigate(speed: float, delta: float) -> void:
	var d := _last_known - global_position
	var amp := float(_def.get("sweep", 0.0))
	if absf(d.x) < 10.0 and absf(d.y) < 28.0 or _blocked and _search_t > 0.0 or amp > 0.0 and _search_t > 0.0:
		if amp > 0.0 and not _blocked:
			_sweep(amp, speed)                   # Ślepiec: chodzi po okolicy śladu zamiast stać
		else:
			velocity.x = 0.0
		_search_t += delta
		if _search_t > float(_def.get("search", SEARCH_TIME)):
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
	if not _beh.returns_home():
		velocity.x = 0.0            # po zasadzce nie wraca na sufit — czatuje tam, gdzie wylądował
		return
	# pamięć: zanim wróci do domu, raz sprawdza „gorące miejsce" — gdzie drużyna ostatnio strzelała
	if not _patrolled:
		_patrolled = true
		var spot: Variant = NoiseMgr.hot_spot_near(global_position, PATROL_RADIUS, PATROL_MAX_AGE)
		if spot != null and (spot as Vector2).distance_to(_last_known) > 90.0:
			_lead_at(spot)
			_lose_t = GIVE_UP_TIME - 5.0      # krótki obchód, nie pełne poszukiwania
			return
	var d := _home - global_position
	if absf(d.x) < 14.0 and absf(d.y) < 28.0:
		velocity.x = 0.0
		_home_t += delta
		if _home_t > HOME_SLEEP_TIME:
			_home_t = 0.0
			active = false
			winding = false
			_patrolled = false
			_seen_serial = NoiseMgr.noise_serial
	else:
		_home_t = 0.0
		# powrót do domu, którego nie da się dojść (mur, przerwa, stopień powyżej STEP_MAX_RISE): po RETURN_STUCK_TIME s bez ruchu dom przenosi się tam, gdzie stoi —
		# wróg zasypia na miejscu zamiast stać obudzony w nieskończoność
		if absf(global_position.x - _stuck_x) < 2.0:
			_stuck_t += delta
			if _stuck_t > RETURN_STUCK_TIME:
				_home = global_position
				_stuck_t = 0.0
		else:
			_stuck_x = global_position.x
			_stuck_t = 0.0
		_steer_to(_home, speed * 0.6, delta)

## Pościg za widocznym graczem: na tym samym poziomie prosto (linia czysta), inaczej grafem A*.
func _chase(target: Node2D, speed: float, delta: float) -> void:
	var d := target.global_position - global_position
	_level_t = _level_t + delta if absf(d.y) >= 24.0 else 0.0
	if _level_t > 0.35 and _has_nav():
		_steer_to(target.global_position, speed, delta)
		if _blocked:
			_blocked_t += delta
			if _blocked_t > BLOCK_GIVEUP:
				_blocked_t = 0.0
				_blocked = false
				_target = null
				_has_lead = false
				_ignore_t = IGNORE_TIME
		else:
			_blocked_t = 0.0
		return
	_blocked_t = 0.0
	_blocked = false
	if _beh.chase_hold(target, d, speed):
		return
	var want := signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
	# rozsuwanie watahy: nie stają w jednym punkcie, tylko w szeregu (można strzelać po kolei)
	if absf(d.x) > float(_def["reach"]):
		want += _separation(speed)
	velocity.x = want
	if is_on_wall() and is_on_floor() and _def["leap"]:
		velocity.y = -230.0

func _separation(speed: float) -> float:
	var push := 0.0
	for e in _near(global_position, 12.0):
		if not is_instance_valid(e) or e == self or e.get_script() != get_script() or not e.alive or not e.active:
			continue
		var dx: float = global_position.x - e.global_position.x
		if absf(dx) < 9.0 and absf(global_position.y - e.global_position.y) < 12.0:
			push += (signf(dx) if dx != 0.0 else (1.0 if get_instance_id() > e.get_instance_id() else -1.0))
			if absf(push) >= 1.0:
				break                                  # wynik jest przycięty do ±1 — dalsi sąsiedzi nic nie zmienią
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
	if is_on_floor() and (_repath <= 0.0 or _path_goal.distance_to(goal) > 40.0) and _path_slot():
		_repath = 0.45 + randf() * 0.1                  # rozsunięte w czasie, żeby wataha nie liczyła tras w tej samej klatce
		_path_goal = goal
		_path = nav.find_path(global_position, goal, bool(_def["leap"]))         # ci, co nie skaczą (Wołek), wolą trasę na piechotę, jeśli jest
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
			elif _is_step(prev.pos, step.pos):
				velocity.y = STEP_HOP_V                 # stopień o jeden kafel (metalowy blok, krawężnik): wróg, który nie skacze, przechodzi go małym przeskokiem
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
		Nav.Edge.FALL:
			# zejście z krawędzi: idzie dalej, aż straci grunt — wcześniej zatrzymywał się, gdy środek ciała był < 3 px od środka kolumny docelowej,
			# czyli dokładnie na krawędzi (playtest: „stoi na krawędzi uskoku i się nie rusza")
			velocity.x = (signf(sx) if absf(sx) > 0.5 else _facing) * speed
		_:
			velocity.x = signf(sx) * speed if absf(sx) > 3.0 else 0.0

## Czy krawędź JUMP z `a` do `b` to zwykły stopień: do jednego kafla w górę i do jednego kafla w bok (nie skok przez przerwę ani na wyższą półkę).
static func _is_step(a: Vector2, b: Vector2) -> bool:
	var rise := a.y - b.y
	return rise > 0.0 and rise <= STEP_MAX_RISE and absf(b.x - a.x) <= STEP_MAX_RISE + 1.0

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
		var reach := _noise_reach(NoiseMgr.last_noise_amount)
		var wait := reach > 0.0 and _sound_needs_path(NoiseMgr.last_noise_pos, reach) and not _sound_slot()    # budżet A* tej klatki — spróbuje w następnej
		if not wait:
			_seen_serial = NoiseMgr.noise_serial
			var heard := _sound_distance(NoiseMgr.last_noise_pos, reach) if reach > 0.0 else INF
			if reach > 0.0 and heard < reach:
				_lead_at(_heard_pos(NoiseMgr.last_noise_pos, heard, reach, NoiseMgr.last_noise_amount))     # idzie w okolice źródła hałasu (z błędem), nie wprost do gracza
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
	# (sprawdzane co ~0,12 s z losowym przesunięciem na wroga, nie co klatkę: promienie wszystkich śpiących naraz to był koszt bez korzyści)
	var now_ms := Time.get_ticks_msec()
	if now_ms >= _flash_check_ms:
		_flash_check_ms = now_ms + int(PERCEIVE_DT * 1000.0) + randi() % 40
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

## Ściana między wrogiem a celem na tym samym poziomie (cios z bliska nie przechodzi przez mur; dym go nie chroni, więc to nie `_clear_line`).
## Przy różnicy poziomów nie sprawdzamy: poziomy promień trafiałby w bok stopnia, na którym stoi cel.
func _wall_between(pp: Node2D) -> bool:
	if absf(pp.global_position.y - global_position.y) > 6.0:
		return false
	var a := global_position + Vector2(0, -(_def["size"] as Vector2).y * 0.6)
	var q := PhysicsRayQueryParameters2D.create(a, Vector2(pp.global_position.x, a.y), 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _try_begin_attack(target: Node2D) -> void:
	if _cd > 0.0 or _windup > 0.0:
		return
	if _in_reach(target, 0.0) and not _wall_between(target):
		_windup = windup_time(float(_def["windup"]), Difficulty.m("enemy_windup"))
		_windup_target = target
		winding = true

func _resolve_attack() -> void:
	winding = false
	var pp := _windup_target
	_windup_target = null
	_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	_beh.after_attack()
	if pp != null and is_instance_valid(pp) and not pp.dead and _in_reach(pp, 6.0) and not _wall_between(pp):
		pp.deliver_hit(_scaled_damage(int(_def["damage"])), global_position, kind)

## --- API walki (combat.gd) -------------------------------------------------

## Górna część sylwetki (strefy trafień, `_hurt_h`) = głowa; trafienie powyżej tej linii to krytyk. Niski Trzosek (14 px)
## nie ma słabego punktu — strzał z wysokości barku (−12 px) trafiałby go w „głowę” zawsze,
## więc krytyk byłby stałym mnożnikiem, a nie nagrodą za celowanie. Wołek (26 px) ma głowę
## w górnych 28%: trzeba celować w górę, skakać albo strzelać ze wzniesienia.
func head_y() -> float:
	var frac: float = _def.get("head", 0.0)
	if frac <= 0.0:
		return -INF
	return global_position.y - _hurt_h() * (1.0 - frac)

## Wysokość strefy trafień (px): wysokość modelu 3D (`hurt_h` w KINDS = SPEC „fit" z enemy3d.gd), a bez niej — ciało ruchu.
## Ćma (model dopasowany szerokością) wisi w środku ramki 20 px i rozpościera skrzydła na 18 × 16 px — `hurt_h` / `hurt_w` obejmują je całe.
func _hurt_h() -> float:
	return maxf(float(_def.get("hurt_h", 0.0)), (_def["size"] as Vector2).y)

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
	_alert = 0.0                                                       # trafiony nie stoi i nie patrzy — walczy (i nie dostaje reakcji przy budzeniu od tego trafienia)
	_alert_cd = ALERT_COOLDOWN
	_beh.on_damaged()
	_last_attacker = int(info.get("shooter", _last_attacker))          # kto dobił (też od podpalenia) dostaje XP w _die
	if info.get("backstab", false) and (not active or _is_behind(info["dir"])):
		dmg = maxf(dmg, hp + 1.0)
		silent = true
		info["crit"] = true
	var exec: float = info.get("execute", 0.0)
	if exec > 0.0 and hp <= _max_hp * exec:
		dmg = maxf(dmg, hp + 1.0)        # dobicie: maczeta z ulepszeniem „Executioner”
		info["crit"] = true
	var mat := 0
	var armor: float = _def.get("armor", 0.0)
	if armor > 0.0 and (info.get("type", "bullet") == "bullet" or info.get("type", "") == "beam"):
		# pancerz: stała redukcja na trafienie (min. 40% obrażeń) — rozrzut i seria słabną, ciężkie trafienia nie
		var reduced := maxf(dmg - armor, dmg * ARMOR_MIN_FRAC)
		if reduced < dmg * 0.7:
			mat = 1                      # Arsenal.Mat.ARMOR: iskry i szary hitmarker
		dmg = reduced
	var shield_mult: float = _beh.damage_mult()
	if shield_mult < 1.0:
		dmg *= shield_mult
		mat = 1                          # pole ochronne: iskry i szary hitmarker jak przy pancerzu
	hp -= dmg
	_flash = 0.1
	_stagger = maxf(_stagger, 0.12 + float(info.get("stun", 0.0)))
	if float(info.get("stun", 0.0)) >= WINDUP_INTERRUPT_STUN:
		_interrupt_windup()
	velocity.x += signf(info["dir"].x) * float(info.get("knock", 0.0)) * float(_def["knock_mult"])
	var pull: float = info.get("pull", 0.0)
	if pull > 0.0:
		velocity.x = -signf(info["dir"].x) * pull * float(_def["knock_mult"])        # linka: szarpnięcie ku strzelcowi zamiast odrzutu
	var fire: float = info.get("ignite", 0.0)
	if fire > 0.0:
		_ignite(fire)
	if not active and not silent:
		wake()
	var dead := hp <= 0.0
	if dead:
		_die()
	else:
		_beh.on_hit(silent)
	return {"hit": true, "dealt": dmg, "killed": dead, "mat": mat}

# ---------------------------------------------------------------- ogień

func _ignite(seconds: float) -> void:
	var fresh := _burn <= 0.0
	_burn = maxf(_burn, seconds)
	_beh.on_ignite()
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
	hp -= BURN_DPS * delta * _beh.damage_mult()
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
	hp -= dmg * _beh.damage_mult()
	_alert = 0.0
	_alert_cd = ALERT_COOLDOWN
	_beh.on_damaged()
	_flash = 0.1
	_stagger = 0.12
	Vfx.blood(get_parent(), global_position + Vector2(0, -8), (global_position - from_pos).normalized(), 5)
	var knock: float = _def["knock"]
	velocity.x += signf(global_position.x - from_pos.x) * knock
	if not active:
		wake()
	if hp <= 0.0:
		_die()
	else:
		_beh.on_hit(false)

func _die() -> void:
	if NoiseMgr.is_server() and _last_attacker != 0 and not summoned and not String(name).begins_with("LeechSpawn") and not is_in_group("roamers"):
		Profile.server_award_kill(_last_attacker, kind)         # XP profilu strzelca (boty, Trzoski bossa i wędrowcy Dyrektora nie liczą się)
	if NoiseMgr.is_server() and randf() < minf(1.0, EnemyDefs.value(kind, "health") * Difficulty.m("drops")):
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.spawn_health(global_position + Vector2(0, -14))
	if NoiseMgr.is_server() and not summoned and randf() < minf(1.0, EnemyDefs.value(kind, "ammo") * Difficulty.m("drops")):
		var w := Arsenal.pick_drop_weapon()
		var lv := get_tree().get_first_node_in_group("level")
		if w >= 0 and lv != null:
			var n: int = maxi(1, int(Weapons.def(w).pickup_rounds * 0.5))
			lv.spawn_item("ammo", w, global_position + Vector2(randf_range(-6.0, 6.0), -14), n)
	if NoiseMgr.is_server() and not summoned and not NightShift.active and randf() < minf(1.0, EnemyDefs.value(kind, "supply") * Difficulty.m("drops")):
		var lsup := get_tree().get_first_node_in_group("level")
		if lsup != null:
			var sk := Throwables.drop_kind()                     # skrzynka zaopatrzenia: granat, apteczka, mina… do wspólnego zapasu
			lsup.spawn_item("supply", Throwables.ORDER.find(sk), global_position + Vector2(randf_range(-6.0, 6.0), -14))
	if NoiseMgr.is_server() and not summoned and Scrap.enabled() and EnemyDefs.value(kind, "scrap") > 0.0 and randf() < Scrap.DROP_CHANCE:
		var ls := get_tree().get_first_node_in_group("level")
		if ls != null:
			ls.spawn_item("scrap", 0, global_position + Vector2(randf_range(-6.0, 6.0), -14), int(EnemyDefs.value(kind, "scrap")))
	_beh.on_death()
	_set_alive(false)
	winding = false
	_windup = 0.0
	_sp = 0
	_death_fx()
	_send_state(999.0)

## Efekty śmierci na KAŻDYM peerze (serwer wywołuje wprost, klient po zmianie alive).
func _death_fx() -> void:
	Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.8)
	var local := _local_player_pos()
	var fx := _def.get("death_fx", {}) as Dictionary        # drobny wróg (Trzosek) pada ciszej: słabszy wstrząs i mniej szczątków (domyślnie ciężki)
	if local.distance_to(global_position) < 220.0:
		Feel.shake(float(fx.get("shake", 3.0)))
		Feel.hitstop(float(fx.get("hitstop", 0.09)))
	# szczątki (fizyczne, lokalne) + krew na podłożu; odrzut z kierunku trafienia
	Vfx.gibs(get_parent(), global_position + Vector2(0, -6), (_def["color"] as Color).lightened(DEATH_FX_COLOR_VAR),
		int(fx.get("gibs", 11)), Vector2(signf(velocity.x) * 60.0, 0))

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
	_sync.rpc(global_position, hp, active, alive, winding, _sp, _ai, _facing)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(pos: Vector2, new_hp: float, is_active: bool, is_alive: bool, is_winding: bool, new_sp := 0, new_ai := -1, new_face := 0.0) -> void:
	_remote_pos = pos
	if new_hp < hp - 0.01:
		_flash = 0.1
		Vfx.blood(get_parent(), global_position + Vector2(0, -8), Vector2.UP, 5)
	hp = new_hp
	active = is_active
	winding = is_winding
	_sp = new_sp                          # stan specjalny Wołka (szarża, rzut, oszołomienie) — bez niego klient nie widział póz w modelu 3D
	if alive and not is_alive:
		_set_alive(false)
		_death_fx()
	elif not alive and is_alive:
		_set_alive(true)
		global_position = pos
	if new_face != 0.0:
		_net_face = new_face
	if new_ai >= 0:
		_set_ai_state(new_ai)             # stan AI liczy serwer; klient go tylko odtwarza (-1 = starszy nadawca bez pola)

## Kontrakt widoku (view3d.gd: `_sync_enemies`): to, co model 3D musi wiedzieć o wrogu, podane jawnie — zamiast zgadywania z prywatnych pól
## (`_sp`), z koloru sprite'a (błysk trafienia) i ze ścieżki skryptu (rodzaj). Tę samą metodę mają Stalker, Żyła, Pijawka i gniazdo.
## Klucze: kind (rodzaj modelu), alive, winding (zapowiedź ciosu), sp (stan specjalny Wołka), flash (świeże trafienie), ai (stan AI, `Ai`),
## alert (reakcja „zauważył cię": oczy rozżarzone, wróg stoi i patrzy na źródło).
func view_info() -> Dictionary:
	var d := {"kind": kind, "alive": alive, "winding": winding, "sp": _sp, "flash": _flash > 0.0, "ai": _ai, "alert": _ai == Ai.ALERT, "shield": false}
	_beh.view_extra(d)
	return d

## Głos gatunku dla zdarzenia (`enemy_defs.gd`: voice); gatunek bez wpisu milczy.
func _voice(event: String) -> void:
	var v: Array = EnemyDefs.voice(kind, event)
	if not v.is_empty():
		Audio.play_variant_at(String(v[0]), int(v[1]), global_position, Audio.BUS_WORLD, float(v[2]), float(v[3]))

func _process(delta: float) -> void:
	if winding != _voiced_winding:
		_voiced_winding = winding
		if winding and alive and _ring <= 0.0:                  # krzyk demaskacji / alarmu (_scream_fx) zastępuje zapowiedź
			_voice("attack")
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
		_view_facing = signf(dx)
	var moving := absf(dx) > 0.05
	if _ai == Ai.ALERT:
		# „zauważył": odwraca się ku źródłu — serwer (host) zna kierunek, klient dostaje go w `_sync`
		var face := _facing if NoiseMgr.is_server() else _net_face
		if face != 0.0:
			_view_facing = signf(face)
	if _beh.server_facing():
		# stoi w miejscu — patrzy tam, gdzie serwer (F3.8): na cel, ślad albo najbliższego gracza
		var lface := _facing if NoiseMgr.is_server() else _net_face
		if lface != 0.0:
			_view_facing = signf(lface)
	var anim := "sleep"
	if active:
		if winding:
			anim = "windup"
		elif moving:
			anim = "walk"
		else:
			anim = "idle"
	anim = _beh.anim(anim, moving)
	Sprites.play(_spr, anim, _view_facing < 0.0)
	var body: AnimatedSprite2D = _spr[0]
	var m := Color.WHITE
	if _flash > 0.0:
		m = Color(2.4, 2.4, 2.4)
	elif winding:
		# zapowiedź ciosu: pulsujące czerwienienie (klatka „windup" unosi łapę)
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		m = Color(1.6 + 0.6 * p, 0.55, 0.5)
	elif not active and not _beh.disguised():
		m = Color(0.8, 0.8, 0.8)
	body.modulate = m

## Oczy, kontur zapowiedzi ataku i HP — unshaded, widoczne w ciemności.
func _draw_overlay(ov: Node2D) -> void:
	var size: Vector2 = _def["size"]
	_beh.draw_overlay(ov)
	# pasek HP po pierwszym trafieniu
	if hp < _max_hp or bool(_def.get("elite", false)):
		var w := size.x + 4.0
		if Sprites.newitem:
			Vfx.draw_bar(ov, Rect2(-w * 0.5, -size.y - 7.0, w, 2.0), hp / _max_hp, Color(0.15, 0.05, 0.05, 0.9), Color(0.9, 0.25, 0.2))
		else:
			ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w, 2.0), Color(0.15, 0.05, 0.05))
			ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w * clampf(hp / _max_hp, 0.0, 1.0), 2.0), Color(0.9, 0.25, 0.2))
