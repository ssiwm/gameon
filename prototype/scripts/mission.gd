extends Node2D
## Pętla misji (GDD §4): CEL → EKSTRAKCJA → WYNIK. Autorytet: serwer.
## Rodzaj celu (`kind`) podaje poziom (level.objective): „nests" = misja 1.3, „generators" = misja 1.2.
##
##   OBJECTIVE  zniszcz wszystkie gniazda (grupa „nests") — albo uruchom wszystkie generatory (grupa „generators"),
##              a po ostatnim nadajnik rozbrzmiewa na cały las (skok Uwagi, Stalker idzie na źródło)
##   BOSS       gniazda były odnóżami Żyły (boss.gd) — budzi się; zabij ją
##   EXTRACT    wyjście otwiera się w INNYM miejscu niż start (§4: „po wykonaniu
##              celu pozycja wyjścia się zmienia") — najdalszy od drużyny punkt
##              z EXIT_CANDIDATES, więc trzeba wrócić przez obudzony teren.
##              Wszyscy stojący ludzie muszą być w strefie przez EXTRACT_TIME;
##              leżącego trzeba najpierw podnieść — drużyna wychodzi razem.
##   SUCCESS    ekran wyniku; host zaczyna nową próbę [Enter].
##
## Wipe (main.gd) = nieudana ekstrakcja: misja wraca do OBJECTIVE, licznik prób +1.
## Klienci dostają stan przez _sync (5 Hz + natychmiast przy zmianie fazy).

enum Phase { OBJECTIVE, BOSS, EXTRACT, SUCCESS, FAILED }      # FAILED: tylko Nocny Dyżur (wipe kończy serię)

const Lights := preload("res://scripts/lights.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Weather := preload("res://scripts/weather.gd")
const RunLog := preload("res://scripts/run_log.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const EXTRACT_TIME := 3.0
const EXIT_RADIUS_X := 34.0
const EXIT_RADIUS_Y := 40.0
const SYNC_INTERVAL := 0.2

const STEALTH_CAP := 40.0              ## cel poboczny misji 1.2: Uwaga poniżej tej wartości do końca celu głównego
const BOSS_WAIT := 40.0               ## s, po których budzi się boss misji „boss", nawet jeśli nikt nie podszedł
const FINALE_DELAY := 2.5             ## s od trzeciego nieśmiertelnika do zawału rampy
const FINALE_NOISE := 14.0            ## skok Uwagi przy wstrząsie (budzi to, co śpi w sali)
## Ostatnia transmisja patrolu w finale: [sekunda od startu finału, linia]; ostatnia wisi do FINALE_RADIO_END.
const FINALE_RADIO := [
	[0.0, "…Seven, last transmission. If you can hear this — you found our tags."],
	[3.0, "It was never the woods listening. It's the mine. It woke when we dug."],
	[6.0, "Don't go back up the ramp. There's an old shaft on the east side — climb."],
	[9.0, "Keep the light off. Stay quiet. The flare is at the top… run."],
]
const FINALE_RADIO_END := 12.5
const BROADCAST_NOISE := 70.0          ## skok Uwagi po uruchomieniu ostatniego generatora

var phase: int = Phase.OBJECTIVE
var kind := "nests"
var goal_total := 0
var goal_left := 0
## Stare nazwy (gniazda) — HUD, testy i misja 1.3 czytają je dalej; to ten sam licznik celu.
var nests_total: int:
	get:
		return goal_total
	set(v):
		goal_total = v
var nests_left: int:
	get:
		return goal_left
	set(v):
		goal_left = v
var peak_noise := 0.0                  ## najwyższa Uwaga od startu do końca celu głównego (cel poboczny)
var exit_pos := Vector2.ZERO
var extract_progress := 0.0
## Statystyki do ekranu wyniku
var elapsed := 0.0
var downs := 0
var attempts := 1
## Nocny Dyżur (night_shift.gd): suma z ukończonych misji serii
var shift_cleared := 0
var shift_time := 0.0
var shift_downs := 0
var shift_record := false     ## seria właśnie pobiła lokalny rekord

var _sync_t := 0.0
var _flare: PointLight2D
var _was_dead := {}          # nazwa gracza -> bool (liczenie upadków, serwer)

var _boss: Node = null
var finale := false                    ## misja 1.1: trzeci nieśmiertelnik wziął kopalnię w obroty (zawał + wyjście po drugiej stronie)
var finale_clock := 0.0               ## s od startu finału (wszystkie peery liczą lokalnie — radio na HUD)
var _finale_t := -1.0                  ## serwer: odliczanie do zawału (s); < 0 = brak
var _boss_wait := 0.0                 ## serwer, misja „boss": odliczanie do przebudzenia bossa, jeśli nikt nie podejdzie do basenu
var stashes_found := 0                 ## cel poboczny 1.1: ukryte skrytki (replikowane)
var stash_total := 0
var _tags_taken := 0                   ## serwer: ile nieśmiertelników już podniesiono (misja 1.1)

func _ready() -> void:
	add_to_group("mission")
	z_index = 5
	# znacznik (słup, strefa, paski) czytelny w ciemności; sama flara to
	# prawdziwe światło 12 m (GDD §8.3) — widać ją z daleka i oświetla wyjście
	material = Lights.unshaded()
	_flare = Lights.make_light(Lights.radial(), Lights.FLARE_M, Color(0.45, 1.0, 0.55), 1.1, true)
	_flare.enabled = false
	add_child(_flare)
	rebind()

## Podpina cel do bieżącego poziomu: gniazda i boss (misja 1.3) albo generatory (misja 1.2). Wołane na starcie i po
## każdej zmianie mapy (main.gd) — encje starej mapy zniknęły razem z nią.
func rebind() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	kind = String(lvl.objective) if lvl != null else "nests"
	_boss = get_tree().get_first_node_in_group("boss")
	_tags_taken = 0
	stashes_found = 0
	if _boss != null and not _boss.died.is_connected(_on_boss_died):
		_boss.died.connect(_on_boss_died)
	# cele są w scenie (ta sama ścieżka na każdym peerze)
	for n in get_tree().get_nodes_in_group("nests"):
		if not n.destroyed.is_connected(_on_nest_destroyed):
			n.destroyed.connect(_on_nest_destroyed)
	for g in get_tree().get_nodes_in_group("generators"):
		if not g.started.is_connected(_on_generator_started):
			g.started.connect(_on_generator_started)
	_count_goal()

func _count_goal() -> void:
	goal_total = 0
	goal_left = 0
	if kind == "tags":
		var lvl := get_tree().get_first_node_in_group("level")
		goal_total = lvl.tag_total() if lvl != null else 0
		goal_left = maxi(0, goal_total - _tags_taken)
		stash_total = lvl.stash_total() if lvl != null else 0
	elif kind == "generators":
		for g in get_tree().get_nodes_in_group("generators"):
			goal_total += 1
			if not g.running:
				goal_left += 1
	else:
		for n in get_tree().get_nodes_in_group("nests"):
			goal_total += 1
			if n.alive:
				goal_left += 1

func is_active() -> bool:
	return NoiseMgr.has_network()

# ---------------------------------------------------------------- serwer

func _physics_process(delta: float) -> void:
	queue_redraw()
	finale_clock = finale_clock + delta if finale else 0.0
	_flare.enabled = phase == Phase.EXTRACT or phase == Phase.SUCCESS
	if _flare.enabled:
		_flare.position = exit_pos + Vector2(0, -6)
		var t := Time.get_ticks_msec() / 1000.0
		_flare.energy = 1.0 + 0.2 * sin(t * 11.0) * sin(t * 4.3)
	if not NoiseMgr.has_network():
		return
	if not multiplayer.is_server():
		if phase != Phase.SUCCESS and phase != Phase.FAILED:
			elapsed += delta     # lokalna interpolacja zegara między synchronizacjami
		return

	if phase != Phase.SUCCESS and phase != Phase.FAILED:
		elapsed += delta
	_track_downs()
	if phase == Phase.OBJECTIVE:
		peak_noise = maxf(peak_noise, NoiseMgr.level)
		_tick_boss_start(delta)
	if phase == Phase.EXTRACT:
		_tick_extract(delta)
		_tick_finale(delta)

	_sync_t -= delta
	if _sync_t <= 0.0:
		_broadcast()

## Misja „boss" (B1): walka zaczyna się, gdy ktoś podejdzie do basenu (promień 160 px od jego krawędzi) albo po BOSS_WAIT s.
func _tick_boss_start(delta: float) -> void:
	if kind != "boss" or _boss == null or not is_instance_valid(_boss):
		return
	_boss_wait += delta
	var near := false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		if p.global_position.x > float(_boss.get("pool_x0")) - 160.0:
			near = true
			break
	if near or _boss_wait >= BOSS_WAIT:
		_start_boss()
		_broadcast()

## Ukryta skrytka znaleziona (pickup.gd, serwer) — cel poboczny misji 1.1; za komplet jest bonus złomu.
func on_stash_found() -> void:
	if not NoiseMgr.is_server() or kind != "tags":
		return
	stashes_found += 1
	print("[MISSION] hidden stash found %d/%d" % [stashes_found, stash_total])
	_event.rpc("generator")
	_broadcast()

## Czy cel poboczny jest zaliczony: 1.1 — komplet skrytek, 1.2 — cicho (Uwaga poniżej progu); inne misje nie mają celu pobocznego.
func side_done() -> bool:
	if kind == "tags":
		return stash_total > 0 and stashes_found >= stash_total
	if kind == "generators":
		return stealth_ok()
	return false

## Nieśmiertelnik podniesiony (pickup.gd, serwer) — misja 1.1. Po ostatnim otwiera się ekstrakcja (bez bossa).
func on_tag_taken() -> void:
	if not NoiseMgr.is_server() or kind != "tags" or phase != Phase.OBJECTIVE:
		return
	_tags_taken += 1
	_count_goal()
	print("[MISSION] dog tag taken, left=%d/%d" % [goal_left, goal_total])
	_event.rpc("generator")
	if goal_left == 0:
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null and not lvl.collapse_rects.is_empty() and not lvl.exits_alt.is_empty():
			_start_finale(lvl)
		else:
			_open_extraction()
	_broadcast()

## Finał misji 1.1: kopalnia się budzi. Wstrząs i skok hałasu teraz, zawał rampy po FINALE_DELAY s, a wyjście przenosi się na drugą stronę
## (znacznik „e"). Zawał nie rani — blokuje drogę, więc nie ma sensu cofać się po pierwszej drodze.
func _start_finale(lvl: Node) -> void:
	finale = true
	_finale_t = FINALE_DELAY
	_open_extraction()
	exit_pos = lvl.exits_alt[0]
	NoiseMgr.script_spike(FINALE_NOISE, _humans_centroid())
	_event.rpc("rumble")
	print("[MISSION] finale: collapse in %.1fs, exit -> %s" % [FINALE_DELAY, str(exit_pos)])

## Linia radia patrolu dla sekundy `t` od startu finału ("" po zakończeniu transmisji).
func radio_line_at(t: float) -> String:
	if t < 0.0 or t >= FINALE_RADIO_END:
		return ""
	var line := ""
	for e in FINALE_RADIO:
		if t >= float(e[0]):
			line = String(e[1])
	return line

func finale_radio_line() -> String:
	return radio_line_at(finale_clock) if finale else ""

func _tick_finale(delta: float) -> void:
	if _finale_t < 0.0:
		return
	_finale_t -= delta
	if _finale_t <= 0.0:
		_finale_t = -1.0
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.collapse(lvl.collapse_rects)
		_event.rpc("collapse")

func _on_nest_destroyed(_nest: Node) -> void:
	if not NoiseMgr.is_server():
		return
	_count_goal()
	print("[MISSION] nest destroyed, left=%d/%d" % [nests_left, nests_total])
	if _boss != null and phase == Phase.OBJECTIVE:
		_boss.on_nest_lost(nests_left)
	if nests_left == 0 and phase == Phase.OBJECTIVE:
		if _boss != null and _boss.is_alive():
			_start_boss()
		else:
			_open_extraction()
	_broadcast()

## Generator ruszył (misja 1.2). Po ostatnim: nadajnik rozbrzmiewa na cały las — skok Uwagi budzi Stalkera i kieruje go
## na źródło, a drużyna musi dotrzeć do wyjścia (lekcja Q: wabik odciąga Stalkera). Cel poboczny liczy Uwagę tylko do tego momentu.
func _on_generator_started(_gen: Node) -> void:
	if not NoiseMgr.is_server():
		return
	_count_goal()
	print("[MISSION] generator started, left=%d/%d peak=%.0f" % [goal_left, goal_total, peak_noise])
	_event.rpc("generator")
	if goal_left == 0 and phase == Phase.OBJECTIVE:
		peak_noise = maxf(peak_noise, NoiseMgr.level)
		var src := _last_generator_pos(_gen)
		_open_extraction()
		NoiseMgr.script_spike(BROADCAST_NOISE, src)
		_event.rpc("broadcast")
	_broadcast()

func _last_generator_pos(gen: Node) -> Vector2:
	return (gen as Node2D).global_position if gen is Node2D else exit_pos

## Czy cel poboczny „Uwaga poniżej 40" jest nadal w grze (misja 1.2).
func stealth_ok() -> bool:
	return peak_noise < STEALTH_CAP

## Ostatnie gniazdo padło — matka się budzi. Ładunek Q wraca tu (GDD §8.4:
## „przy wykonaniu celu"), bo na walkę z Żyłą jest najbardziej potrzebny.
func _start_boss() -> void:
	phase = Phase.BOSS
	NoiseMgr.objective_bonus()
	_boss.awaken()
	print("[MISSION] gniazda zniszczone -> Żyła")

func _on_boss_died() -> void:
	if phase == Phase.BOSS:
		_open_extraction(false)
		_broadcast()

func _open_extraction(q_bonus: bool = true) -> void:
	phase = Phase.EXTRACT
	extract_progress = 0.0
	# najdalszy kandydat od środka drużyny — powrót przez obudzony teren
	var centroid := _humans_centroid()
	# kandydaci = znaczniki „E" mapy (level.gd)
	var cands: Array[Vector2] = get_tree().get_first_node_in_group("level").exits
	var best: Vector2 = cands[0]
	for c in cands:
		if (c as Vector2).distance_to(centroid) > best.distance_to(centroid):
			best = c
	exit_pos = best
	# GDD §8.4: ładunek Przesterowania wraca natychmiast przy celu głównym
	# (z bossem bonus był już przy przebudzeniu)
	if q_bonus:
		NoiseMgr.objective_bonus()
	print("[MISSION] objective complete -> extraction at %s" % exit_pos)
	for c in get_tree().get_nodes_in_group("handcar"):
		c.activate()                 # misja 1.2: zasilanie drezyny — ucieczka podziemnym torem
	_event.rpc("objective")

func _tick_extract(delta: float) -> void:
	var humans := 0
	var inside := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.is_queued_for_deletion():
			continue
		humans += 1
		if not p.dead and _in_exit(p.global_position):
			inside += 1
	if humans > 0 and inside == humans:
		extract_progress = minf(1.0, extract_progress + delta / EXTRACT_TIME)
		if extract_progress >= 1.0:
			_success()
	else:
		extract_progress = maxf(0.0, extract_progress - delta / EXTRACT_TIME * 2.0)

func _in_exit(pos: Vector2) -> bool:
	return absf(pos.x - exit_pos.x) <= EXIT_RADIUS_X and absf(pos.y - exit_pos.y) <= EXIT_RADIUS_Y

func _success() -> void:
	phase = Phase.SUCCESS
	extract_progress = 1.0
	print("[MISSION] SUCCESS time=%.1fs downs=%d attempts=%d" % [elapsed, downs, attempts])
	if kind != "hub" and Scrap.enabled():
		var side_ok := side_done()
		var bonus := Scrap.BONUS_CLEAR + (Scrap.BONUS_SIDE if side_ok else 0) + (Scrap.BONUS_NO_DOWNS if downs == 0 else 0)
		var gain := Scrap.bank_loot(bonus)
		print("[SCRAP] mission banked +%d (bonus %d), wallet %d" % [gain, bonus, Scrap.bank])
		if kind == "boss":
			var tl := get_tree().get_first_node_in_group("level")
			if tl != null:
				Scrap.add_trophy(String(tl.map_id))        # pokonany boss odblokowuje broń-trofeum w warsztacie (SPECTER-1)
	_record_result()
	if kind != "hub":
		var xl := get_tree().get_first_node_in_group("level")
		Profile.server_award_mission(String(xl.map_id) if xl != null else "", side_done(), downs == 0, kind == "boss")      # XP profili ludzi
	if NightShift.active:
		shift_cleared += 1
		shift_time += elapsed
		shift_downs += downs
		if NightShift.stage >= NightShift.MISSIONS:
			shift_record = Settings.record_shift(shift_cleared, shift_time, true)
		print("[SHIFT] mission %d/%d cleared, series time %.1fs" % [NightShift.stage, NightShift.MISSIONS, shift_time])
	# teren cichnie: wrogowie (nie gniazda) wracają do snu, Uwaga spada do zera
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_in_group("nests") and not e.is_in_group("boss") and e.has_method("reset_enemy"):
			e.reset_enemy()
	NoiseMgr.calm()
	_event.rpc("success")
	_broadcast()

## Zapis ukończonej misji do dziennika kampanii (ściana wyników). Każdy peer robi to sam, raz na sukces.
func _record_result() -> void:
	if NightShift.active:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or kind == "hub":
		return
	var id := String(lvl.map_id)
	var title := String(lvl.MAPS[id].TITLE) if lvl.MAPS.has(id) else id
	var stealth := (1 if side_done() else 0) if (kind == "generators" or kind == "tags") else -1
	RunLog.add(id, title, elapsed, downs, attempts, stealth, Scrap.last_gain)

## Upadki ludzi (statystyka). Liczone na serwerze z replikowanego `dead`.
func _track_downs() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var was: bool = _was_dead.get(p.name, false)
		if p.dead and not was and not p.is_bot and phase != Phase.SUCCESS and phase != Phase.FAILED:
			downs += 1
		_was_dead[p.name] = p.dead

func _humans_centroid() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			sum += p.global_position
			n += 1
	return sum / n if n > 0 else Vector2.ZERO

# ---------------------------------------------------------------- Nocny Dyżur (serwer)

## Nowa seria: misja 1, bez modyfikatorów, wyzerowane sumy. Wołane przy starcie sesji w trybie Nocnego Dyżuru
## i po zakończonej serii; po nim main._restart_mission(true).
func begin_shift() -> void:
	NightShift.active = true
	NightShift.stage = 1
	NightShift.mods = []
	shift_cleared = 0
	shift_time = 0.0
	shift_downs = 0
	shift_record = false
	print("[SHIFT] new series")

## [Enter] na ekranie wyniku: kolejna misja serii (z nowymi modyfikatorami), a po ostatniej albo po porażce — nowa seria.
func shift_advance() -> void:
	if phase == Phase.FAILED or NightShift.stage >= NightShift.MISSIONS:
		begin_shift()
	else:
		NightShift.stage += 1
		NightShift.mods = NightShift.roll(NightShift.stage)
		print("[SHIFT] mission %d/%d, modifiers: %s" % [NightShift.stage, NightShift.MISSIONS, NightShift.mod_names()])

## Wipe w Nocnym Dyżurze: koniec serii (zamiast powtórki misji).
func fail_shift() -> void:
	phase = Phase.FAILED
	shift_time += elapsed
	shift_downs += downs
	shift_record = Settings.record_shift(shift_cleared, shift_time, false)
	print("[SHIFT] series over: %d/%d cleared, time %.1fs, record=%s" % [shift_cleared, NightShift.MISSIONS, shift_time, str(shift_record)])
	_event.rpc("shift_over")
	_broadcast()

func shift_complete() -> bool:
	return NightShift.active and phase == Phase.SUCCESS and NightShift.stage >= NightShift.MISSIONS

## Plansza z zasadami misji (HUD, pierwsze sekundy misji w Nocnym Dyżurze).
func shift_banner_visible() -> bool:
	return NightShift.active and phase == Phase.OBJECTIVE and elapsed < 9.0

## Tytuł misji w pierwszych sekundach (kampania; w Nocnym Dyżurze HUD dokłada zasady serii).
func banner_visible() -> bool:
	return phase == Phase.OBJECTIVE and elapsed < (9.0 if NightShift.active else 6.0)

## Wołane przez main._restart_mission() — po wipe (nowa próba) albo nowej misji.
func on_restart(new_run: bool) -> void:
	phase = Phase.OBJECTIVE
	extract_progress = 0.0
	elapsed = 0.0
	if new_run:
		downs = 0
		attempts = 1
	else:
		attempts += 1
	_was_dead.clear()
	_boss_wait = 0.0
	_tags_taken = 0
	stashes_found = 0
	finale = false
	_finale_t = -1.0
	# cele wróciły (reset_enemy / reset_generator) — liczymy od nowa
	peak_noise = 0.0
	_count_goal()
	goal_left = goal_total
	_broadcast()

func _broadcast() -> void:
	_sync_t = SYNC_INTERVAL
	if NoiseMgr.has_network() and multiplayer.is_server():
		_sync.rpc(phase, nests_left, nests_total, exit_pos, extract_progress, elapsed, downs, attempts,
			[NightShift.active, NightShift.stage, NightShift.mods, shift_cleared, shift_time, shift_downs, shift_record, Weather.forecast, Weather.current], peak_noise, finale, stashes_found, stash_total)

@rpc("authority", "call_remote", "reliable")
func _sync(p: int, left: int, total: int, ex: Vector2, prog: float, el: float, d: int, att: int, shift: Array, peak: float, fin: bool, st_found: int, st_total: int) -> void:
	finale = fin
	stashes_found = st_found
	stash_total = st_total
	peak_noise = peak
	NightShift.active = bool(shift[0])
	NightShift.stage = int(shift[1])
	NightShift.mods = Array(shift[2])
	shift_cleared = int(shift[3])
	shift_time = float(shift[4])
	shift_downs = int(shift[5])
	shift_record = bool(shift[6])
	if shift.size() > 8:
		Weather.forecast = String(shift[7])
		Weather.current = String(shift[8])
	var was_success := phase == Phase.SUCCESS
	phase = p
	nests_left = left
	nests_total = total
	exit_pos = ex
	extract_progress = prog
	elapsed = el
	downs = d
	attempts = att
	if phase == Phase.SUCCESS and not was_success:
		_record_result()

## Jednorazowe sygnały dźwiękowe na każdym peerze.
@rpc("authority", "call_local", "reliable")
func _event(kind: String) -> void:
	match kind:
		"objective":
			Audio.play("radio_beep", Audio.BUS_UI, -6.0)
			Audio.sting(1)
		"success":
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
			Audio.play("tape_stop", Audio.BUS_UI, -10.0)
		"rumble":
			Feel.shake(4.0)
			Audio.play("alarm_bell", Audio.BUS_UI, -10.0)
		"collapse":
			Feel.shake(7.0)
			Feel.hitstop(0.08)
			Audio.play("tape_stop", Audio.BUS_UI, -3.0)
		"shift_over":
			Audio.play("tape_stop", Audio.BUS_UI, -4.0)
		"generator":
			Audio.play("ui_confirm", Audio.BUS_UI, -6.0)
		"broadcast":
			Audio.play("alarm_bell", Audio.BUS_UI, -6.0)
			Audio.sting(2)

# ---------------------------------------------------------------- HUD

## Teksty dla HUD (angielski interfejs).
func objective_caption() -> String:
	if kind == "hub":
		return "SAFE ROOM"
	var base := ""
	match phase:
		Phase.OBJECTIVE:
			base = "OBJECTIVE"
		Phase.BOSS:
			base = "BOSS"
		Phase.EXTRACT:
			base = "EXTRACT"
	if base != "" and NightShift.active:
		return "NIGHT SHIFT %d/%d  ·  %s" % [NightShift.stage, NightShift.MISSIONS, base]
	return base

## Tytuł następnej misji (kryjówka): z danych mapy wskazanej przez main.after_hub.
func _hub_next_title() -> String:
	var main := get_tree().current_scene
	var nxt := String(main.get("after_hub")) if main != null else ""
	var lvl := get_tree().get_first_node_in_group("level")
	return String(lvl.MAPS[nxt].TITLE) if lvl != null and lvl.MAPS.has(nxt) else "the next mission"

func objective_text() -> String:
	if kind == "hub":
		return "Next: %s" % _hub_next_title()
	match phase:
		Phase.OBJECTIVE:
			if kind == "boss":
				return "Kill the %s" % (String(_boss.get("boss_name")).to_lower().replace("the ", "") if _boss != null else "boss")
			if kind == "tags":
				return "Find the patrol's dog tags   %d / %d" % [goal_total - goal_left, goal_total]
			if kind == "generators":
				return "Start the radio generators   %d / %d" % [goal_total - goal_left, goal_total]
			return "Destroy the nests   %d / %d" % [nests_total - nests_left, nests_total]
		Phase.BOSS:
			if kind == "boss":
				return "Kill the leech — bait it to surface, then hit it"
			return "Kill The Vein — shoot her mouth while it's OPEN"
		Phase.EXTRACT:
			var me := _local_human()
			var car := get_tree().get_first_node_in_group("handcar")
			if car != null and me != null and not car.arrived:
				var cdx: float = car.global_position.x - me.global_position.x
				if car.speed > 5.0 or car.power > 0.0:
					return "Keep pumping — the exit is %d m ahead" % int(absf(car.global_position.x - exit_pos.x) / 16.0)
				return "Get to the handcar   %s %d m" % ["←" if cdx < 0.0 else "→", int(absf(cdx) / 16.0)]
			if me == null:
				return "Reach the green flare"
			var dx := exit_pos.x - me.global_position.x
			if _in_exit(me.global_position):
				return "At the flare"
			return "Reach the green flare   %s %d m" % ["←" if dx < 0.0 else "→", int(absf(dx) / 16.0)]
	return ""

func objective_hint() -> String:
	if kind == "hub":
		var main := get_tree().current_scene
		if main == null:
			return ""
		if main.hub_countdown >= 0.0:
			return "Departing in %d…   [ENTER] cancel" % int(ceil(main.hub_countdown))
		var status := "%d / %d ready" % [main.hub_ready_n, main.hub_total]
		if main.hub_mine:
			return "READY  ·  %s  ·  [ENTER] cancel" % status
		return "[ENTER]  Ready up  ·  %s" % status
	match phase:
		Phase.OBJECTIVE:
			if kind == "boss":
				return String(_boss.get("boss_hint")) if _boss != null else ""
			if kind == "tags":
				return "Walk over a dog tag to take it  ·  side goal: %d hidden stashes (%d / %d)" % [stash_total, stashes_found, stash_total] if stash_total > 0 else "Walk over a dog tag to take it  ·  shooting is loud — sneak (SHIFT) to stay quiet"
			if kind == "generators":
				if not stealth_ok():
					return "Hold E at a generator  ·  a running one keeps humming  ·  stealth bonus lost"
				return "Hold E at a generator  ·  it is loud  ·  bonus: stay under %d%% Attention" % int(STEALTH_CAP)
			return "Nests are loud when destroyed — they wake what's nearby"
		Phase.BOSS:
			if kind == "boss":
				return "Light shows its shadow, but only a surfaced leech takes full damage"
			return "Light her mouth mid wind-up to stun  ·  Q lures her away"
		Phase.EXTRACT:
			if kind == "generators":
				var car2 := get_tree().get_first_node_in_group("handcar")
				if car2 != null and not car2.arrived:
					return "Hold E aboard to pump  ·  more hands = faster  ·  he is coming — Q lures him"
				return "The transmitter is live — he heard it  ·  Q lures him away"
			if finale:
				return "The mine is coming down — the way back is gone. Climb the shaft to the flare!"
			return "The whole squad, standing, at the flare for 3 s"
	return ""

## Stan ekstrakcji lokalnego gracza (pasek kontekstowy HUD).
func local_extract_state() -> Dictionary:
	var me := _local_human()
	if me == null or phase != Phase.EXTRACT:
		return {}
	return {"inside": not me.dead and _in_exit(me.global_position)}

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p
	return null

# ---------------------------------------------------------------- znacznik wyjścia

func _draw() -> void:
	if phase != Phase.EXTRACT and phase != Phase.SUCCESS:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var p := Vector2(roundf(exit_pos.x), roundf(exit_pos.y))
	var flick := 0.8 + 0.2 * sin(t * 11.0) * sin(t * 4.3)
	var col := Color(0.4, 1.0, 0.5)
	var hot := Color(0.85, 1.0, 0.8)
	var hd_flare := Sprites.newitem and ItemsHd.has("flare_stuck")           # HD: gładkie wsporniki, linia i słup światła (zamiast pikseli)
	# poświata na ziemi: eliptyczna kałuża światła w trzech warstwach i pulsujący pierścień
	for i in 3:
		var rx := EXIT_RADIUS_X * (1.15 - 0.25 * float(i))
		_draw_ellipse(p + Vector2(0, -1), rx, 5.0 - float(i), Color(col, (0.07 + 0.05 * float(i)) * flick))
	var ring := fmod(t, 1.8) / 1.8
	_draw_ellipse(p + Vector2(0, -1), 6.0 + ring * (EXIT_RADIUS_X + 6.0), 1.0 + ring * 3.0, Color(col, 0.28 * (1.0 - ring)), false)
	# słup światła: gradient od podstawy w górę (zwęża się i gaśnie), plus szerszy halo
	var h := 170.0
	if hd_flare:
		# słup z kilku warstw o malejącej szerokości — miękkie brzegi zamiast jednej ostrej krawędzi
		for i in 6:
			var f := float(i) / 5.0
			var wb := lerpf(16.0, 4.0, f)
			var wt := lerpf(7.0, 1.2, f)
			var a := lerpf(0.05, 0.1, f) * flick
			var ht := lerpf(h, h * 0.7, f)
			draw_polygon(PackedVector2Array([p + Vector2(-wb, 0), p + Vector2(wb, 0), p + Vector2(wt, -ht), p + Vector2(-wt, -ht)]),
				PackedColorArray([Color(col.lerp(hot, f * 0.6), a), Color(col.lerp(hot, f * 0.6), a), Color(col, 0.0), Color(col, 0.0)]))
	else:
		draw_polygon(PackedVector2Array([p + Vector2(-13, 0), p + Vector2(13, 0), p + Vector2(5, -h), p + Vector2(-5, -h)]),
		PackedColorArray([Color(col, 0.16 * flick), Color(col, 0.16 * flick), Color(col, 0.0), Color(col, 0.0)]))
	if not hd_flare:
		draw_polygon(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(5, 0), p + Vector2(2, -h * 0.8), p + Vector2(-2, -h * 0.8)]),
			PackedColorArray([Color(hot, 0.28 * flick), Color(hot, 0.28 * flick), Color(hot, 0.0), Color(hot, 0.0)]))
	# strefa ewakuacji: przerywana linia na ziemi i wsporniki na krawędziach
	var dash := 6.0
	var x := -EXIT_RADIUS_X
	var phase_off := fmod(t * 14.0, dash * 2.0)
	while x < EXIT_RADIUS_X:
		var x0 := maxf(-EXIT_RADIUS_X, x + phase_off - dash * 2.0)
		var x1 := minf(EXIT_RADIUS_X, x0 + dash)
		if x1 > x0:
			if hd_flare:
				draw_line(Vector2(p.x + x0 + 0.8, p.y - 0.6), Vector2(p.x + x1 - 0.8, p.y - 0.6), Color(col, 0.18), 3.6, true)
				draw_line(Vector2(p.x + x0 + 0.8, p.y - 0.6), Vector2(p.x + x1 - 0.8, p.y - 0.6), Color(col, 0.7), 1.6, true)
				draw_circle(Vector2(p.x + x0 + 0.8, p.y - 0.6), 0.8, Color(col, 0.7))
				draw_circle(Vector2(p.x + x1 - 0.8, p.y - 0.6), 0.8, Color(col, 0.7))
			else:
				draw_rect(Rect2(p.x + x0, p.y - 1.0, x1 - x0, 2.0), Color(col, 0.6))
		x += dash * 2.0
	for sx in [-1.0, 1.0]:
		var ex: float = p.x + sx * EXIT_RADIUS_X
		if hd_flare:
			var post := PackedVector2Array([Vector2(ex - sx * 4.0, p.y - 12.0), Vector2(ex, p.y - 12.0), Vector2(ex, p.y)])
			draw_polyline(post, Color(col, 0.14), 6.0, true)
			draw_polyline(post, Color(col, 0.75), 2.0, true)
			draw_circle(Vector2(ex, p.y - 12.0), 1.6, Color(hot, 0.95))
			continue
		draw_rect(Rect2(ex - 1.0, p.y - 12.0, 2.0, 12.0), Color(col, 0.7))
		draw_rect(Rect2(ex - (4.0 if sx < 0.0 else 0.0), p.y - 12.0, 4.0, 2.0), Color(col, 0.7))
		draw_rect(Rect2(ex - 1.0, p.y - 12.0, 2.0, 2.0), Color(hot, 0.9))
	# flara: wbita w ziemię tuba (czerwona, z jasnym paskiem), kamyki u podstawy
	if hd_flare:
		ItemsHd.draw(self, "flare_stuck", p, 0.85)
	else:
		draw_rect(Rect2(p.x - 6.0, p.y - 2.0, 3.0, 2.0), Color(0.18, 0.2, 0.17))
		draw_rect(Rect2(p.x + 3.0, p.y - 3.0, 4.0, 3.0), Color(0.16, 0.18, 0.15))
		draw_rect(Rect2(p.x - 2.0, p.y - 11.0, 4.0, 11.0), Color(0.55, 0.12, 0.1))
		draw_rect(Rect2(p.x - 2.0, p.y - 11.0, 1.0, 11.0), Color(0.8, 0.22, 0.16))
		draw_rect(Rect2(p.x - 2.0, p.y - 7.0, 4.0, 1.0), Color(0.9, 0.85, 0.6))
		draw_rect(Rect2(p.x - 2.0, p.y - 12.0, 4.0, 1.0), Color(0.25, 0.25, 0.22))
	# płomień: trzy warstwy (zewnętrzna zieleń, jasny środek, biały rdzeń) migoczą niezależnie
	var fh := 8.0 + 3.0 * sin(t * 17.0) + 2.0 * sin(t * 9.1)
	var fw := 5.0 + 1.0 * sin(t * 13.0)
	var fy := p.y - (13.0 if hd_flare else 12.0)
	draw_circle(Vector2(p.x, fy - 5.0), 11.0, Color(col, 0.10 * flick))
	draw_circle(Vector2(p.x, fy - 4.0), 6.5, Color(col, 0.16 * flick))
	if hd_flare:
		_draw_flame_hd(Vector2(p.x, fy), fh + 3.0, fw, t, col)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - fw, fy), Vector2(p.x + fw, fy), Vector2(p.x + 1.0 + sin(t * 7.0), fy - fh - 3.0), Vector2(p.x - 1.0, fy - fh - 3.0)]), Color(0.3, 0.95, 0.45, 0.85))
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - fw * 0.55, fy), Vector2(p.x + fw * 0.55, fy), Vector2(p.x, fy - fh)]), Color(0.7, 1.0, 0.7, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - 1.5, fy), Vector2(p.x + 1.5, fy), Vector2(p.x, fy - fh * 0.55)]), Color(1.0, 1.0, 0.9, 1.0))
	# iskry: małe piksele unoszą się i gasną (stałe fazy — bez losowania co klatkę)
	for i in 9:
		var life := fmod(t * (0.55 + 0.07 * float(i)) + float(i) * 0.37, 1.0)
		var sx := sin(float(i) * 12.9 + life * 5.0) * (4.0 + 18.0 * life)
		var sy := fy - 4.0 - life * (46.0 + 10.0 * float(i % 3))
		if hd_flare:
			draw_circle(Vector2(p.x + sx, sy), (0.7 if i % 2 == 0 else 1.1) * (1.0 - life * 0.5), Color(hot, (1.0 - life) * 0.9))
		else:
			draw_rect(Rect2(roundf(p.x + sx), roundf(sy), 1.0 if i % 2 == 0 else 2.0, 1.0 if i % 2 == 0 else 2.0), Color(hot, (1.0 - life) * 0.9))
	# dym: trzy przezroczyste kłęby dryfują w górę i rozpływają się
	for i in 3:
		var l2 := fmod(t * 0.28 + float(i) * 0.33, 1.0)
		draw_circle(Vector2(p.x + sin(t * 0.8 + float(i)) * 6.0 * l2 + 3.0 * l2, fy - 8.0 - l2 * 70.0), 3.0 + l2 * 9.0, Color(0.5, 0.62, 0.5, 0.13 * (1.0 - l2)))
	# postęp ewakuacji: ramka z osobnymi segmentami, nad etykietą gracza (P1 ~ -30 px)
	if extract_progress > 0.0:
		var bw := 44.0
		var bx := p.x - bw * 0.5
		var by := p.y - 66.0
		draw_rect(Rect2(bx - 1.0, by - 1.0, bw + 2.0, 7.0), Color(0.04, 0.05, 0.05, 0.9))
		draw_rect(Rect2(bx, by, bw, 5.0), Color(0.12, 0.16, 0.12))
		draw_rect(Rect2(bx, by, bw * extract_progress, 5.0), col)
		draw_rect(Rect2(bx, by, bw * extract_progress, 1.0), hot)
		for k in range(1, 4):
			draw_rect(Rect2(bx + bw * float(k) * 0.25 - 0.5, by, 1.0, 5.0), Color(0.04, 0.05, 0.05, 0.8))

## Płomień flary w grafice HD: gładka kropla z falującym konturem i kołyszącym się czubkiem, trzy warstwy (zieleń, jasny środek, biały rdzeń).
func _draw_flame_hd(base: Vector2, h: float, w: float, t: float, col: Color) -> void:
	var layers := [[1.0, 1.0, Color(0.3, 0.95, 0.45, 0.8)], [0.6, 0.72, Color(0.7, 1.0, 0.7, 0.95)], [0.28, 0.45, Color(1.0, 1.0, 0.92, 1.0)]]
	for lay in layers:
		var ws: float = lay[0]
		var hs: float = lay[1]
		var pts := PackedVector2Array()
		var n := 12
		for side in [-1.0, 1.0]:
			for i in n + 1:
				if side > 0.0 and i == 0:
					continue                                    # czubek już jest (bez dubla — triangulacja nie lubi zdegenerowanych wielokątów)
				var f := float(i) / float(n)
				var y: float = f if side < 0.0 else 1.0 - f
				var width := w * ws * pow(maxf(0.0, 1.0 - y), 0.75) * (0.55 + 0.45 * sin(y * PI * 0.9 + 0.25)) * (1.0 + 0.12 * sin(t * 13.0 + y * 7.0))
				var sway := sin(t * 7.0 + y * 2.5) * 1.6 * y * y
				pts.append(base + Vector2(side * width + sway, -y * h * hs))
		draw_colored_polygon(pts, lay[2])

## Elipsa (wypełniona albo sam obrys) z N punktów — płaska plama światła na podłodze.
func _draw_ellipse(c: Vector2, rx: float, ry: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, 1.0)
