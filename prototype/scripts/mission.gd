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

const EXTRACT_TIME := 3.0
const EXIT_RADIUS_X := 34.0
const EXIT_RADIUS_Y := 40.0
const SYNC_INTERVAL := 0.2

const STEALTH_CAP := 40.0              ## cel poboczny misji 1.2: Uwaga poniżej tej wartości do końca celu głównego
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

func _ready() -> void:
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
	if kind == "generators":
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
	if phase == Phase.EXTRACT:
		_tick_extract(delta)

	_sync_t -= delta
	if _sync_t <= 0.0:
		_broadcast()

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
	# cele wróciły (reset_enemy / reset_generator) — liczymy od nowa
	peak_noise = 0.0
	_count_goal()
	goal_left = goal_total
	_broadcast()

func _broadcast() -> void:
	_sync_t = SYNC_INTERVAL
	if NoiseMgr.has_network() and multiplayer.is_server():
		_sync.rpc(phase, nests_left, nests_total, exit_pos, extract_progress, elapsed, downs, attempts,
			[NightShift.active, NightShift.stage, NightShift.mods, shift_cleared, shift_time, shift_downs, shift_record], peak_noise)

@rpc("authority", "call_remote", "reliable")
func _sync(p: int, left: int, total: int, ex: Vector2, prog: float, el: float, d: int, att: int, shift: Array, peak: float) -> void:
	peak_noise = peak
	NightShift.active = bool(shift[0])
	NightShift.stage = int(shift[1])
	NightShift.mods = Array(shift[2])
	shift_cleared = int(shift[3])
	shift_time = float(shift[4])
	shift_downs = int(shift[5])
	shift_record = bool(shift[6])
	phase = p
	nests_left = left
	nests_total = total
	exit_pos = ex
	extract_progress = prog
	elapsed = el
	downs = d
	attempts = att

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

func objective_text() -> String:
	match phase:
		Phase.OBJECTIVE:
			if kind == "generators":
				return "Start the radio generators   %d / %d" % [goal_total - goal_left, goal_total]
			return "Destroy the nests   %d / %d" % [nests_total - nests_left, nests_total]
		Phase.BOSS:
			return "Kill The Vein — shoot her mouth while it's OPEN"
		Phase.EXTRACT:
			var me := _local_human()
			if me == null:
				return "Reach the green flare"
			var dx := exit_pos.x - me.global_position.x
			if _in_exit(me.global_position):
				return "At the flare"
			return "Reach the green flare   %s %d m" % ["←" if dx < 0.0 else "→", int(absf(dx) / 16.0)]
	return ""

func objective_hint() -> String:
	match phase:
		Phase.OBJECTIVE:
			if kind == "generators":
				if not stealth_ok():
					return "Hold E at a generator  ·  a running one keeps humming  ·  stealth bonus lost"
				return "Hold E at a generator  ·  it is loud  ·  bonus: stay under %d%% Attention" % int(STEALTH_CAP)
			return "Nests are loud when destroyed — they wake what's nearby"
		Phase.BOSS:
			return "Light her mouth mid wind-up to stun  ·  Q lures her away"
		Phase.EXTRACT:
			if kind == "generators":
				return "The transmitter is live — he heard it  ·  Q lures him away"
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
	var p := exit_pos
	var flick := 0.75 + 0.25 * sin(t * 11.0) * sin(t * 4.3)
	var col := Color(0.4, 1.0, 0.5)
	# słup światła flary
	for i in 6:
		var w := 26.0 - i * 4.0
		draw_rect(Rect2(p.x - w * 0.5, p.y - 150.0, w, 150.0), Color(col, 0.035 * flick))
	# strefa ewakuacji
	draw_rect(Rect2(p.x - EXIT_RADIUS_X, p.y - 2.0, EXIT_RADIUS_X * 2.0, 3.0), Color(col, 0.55))
	draw_circle(p + Vector2(0, -4), 3.0, Color(1.0, 0.95, 0.7, flick))
	# postęp ewakuacji
	if extract_progress > 0.0:
		# nad etykietą gracza (P1 ~ -30 px), żeby się nie nakładały
		draw_rect(Rect2(p.x - 20.0, p.y - 62.0, 40.0, 4.0), Color(0.1, 0.1, 0.12, 0.8))
		draw_rect(Rect2(p.x - 20.0, p.y - 62.0, 40.0 * extract_progress, 4.0), col)
