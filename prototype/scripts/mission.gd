extends Node2D
## Pętla misji (GDD §4): CEL → EKSTRAKCJA → WYNIK. Autorytet: serwer.
##
##   OBJECTIVE  zniszcz wszystkie gniazda (grupa „nests")
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

enum Phase { OBJECTIVE, BOSS, EXTRACT, SUCCESS }

const Lights := preload("res://scripts/lights.gd")

const EXTRACT_TIME := 3.0
const EXIT_RADIUS_X := 34.0
const EXIT_RADIUS_Y := 40.0
const SYNC_INTERVAL := 0.2

var phase: int = Phase.OBJECTIVE
var nests_total := 0
var nests_left := 0
var exit_pos := Vector2.ZERO
var extract_progress := 0.0
## Statystyki do ekranu wyniku
var elapsed := 0.0
var downs := 0
var attempts := 1

var _sync_t := 0.0
var _flare: PointLight2D
var _was_dead := {}          # nazwa gracza -> bool (liczenie upadków, serwer)

var _boss: Node = null

func _ready() -> void:
	z_index = 5
	_boss = get_tree().get_first_node_in_group("boss")
	if _boss != null:
		_boss.died.connect(_on_boss_died)
	# znacznik (słup, strefa, paski) czytelny w ciemności; sama flara to
	# prawdziwe światło 12 m (GDD §8.3) — widać ją z daleka i oświetla wyjście
	material = Lights.unshaded()
	_flare = Lights.make_light(Lights.radial(), Lights.FLARE_M, Color(0.45, 1.0, 0.55), 1.1, true)
	_flare.enabled = false
	add_child(_flare)
	# gniazda są w scenie (ta sama ścieżka na każdym peerze)
	for n in get_tree().get_nodes_in_group("nests"):
		n.destroyed.connect(_on_nest_destroyed)
	_count_nests()

func _count_nests() -> void:
	nests_total = 0
	nests_left = 0
	for n in get_tree().get_nodes_in_group("nests"):
		nests_total += 1
		if n.alive:
			nests_left += 1

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
		if phase != Phase.SUCCESS:
			elapsed += delta     # lokalna interpolacja zegara między synchronizacjami
		return

	if phase != Phase.SUCCESS:
		elapsed += delta
	_track_downs()
	if phase == Phase.EXTRACT:
		_tick_extract(delta)

	_sync_t -= delta
	if _sync_t <= 0.0:
		_broadcast()

func _on_nest_destroyed(_nest: Node) -> void:
	if not NoiseMgr.is_server():
		return
	_count_nests()
	print("[MISSION] nest destroyed, left=%d/%d" % [nests_left, nests_total])
	if _boss != null and phase == Phase.OBJECTIVE:
		_boss.on_nest_lost(nests_left)
	if nests_left == 0 and phase == Phase.OBJECTIVE:
		if _boss != null and _boss.is_alive():
			_start_boss()
		else:
			_open_extraction()
	_broadcast()

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
		if p.dead and not was and not p.is_bot and phase != Phase.SUCCESS:
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
	# gniazda wróciły (reset_enemy) — liczymy od nowa
	_count_nests()
	nests_left = nests_total
	_broadcast()

func _broadcast() -> void:
	_sync_t = SYNC_INTERVAL
	if NoiseMgr.has_network() and multiplayer.is_server():
		_sync.rpc(phase, nests_left, nests_total, exit_pos, extract_progress, elapsed, downs, attempts)

@rpc("authority", "call_remote", "reliable")
func _sync(p: int, left: int, total: int, ex: Vector2, prog: float, el: float, d: int, att: int) -> void:
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

# ---------------------------------------------------------------- HUD

## Tekst celu dla HUD.
func objective_text() -> String:
	match phase:
		Phase.OBJECTIVE:
			return "CEL: zniszcz gniazda  %d/%d" % [nests_total - nests_left, nests_total]
		Phase.BOSS:
			return "CEL: zabij Żyłę — grzbiet pancerny, celuj w paszczę z dołu"
		Phase.EXTRACT:
			var me := _local_human()
			var dir := ""
			if me != null:
				var dx := exit_pos.x - me.global_position.x
				dir = ("  ← %d m" if dx < 0.0 else "  → %d m") % int(absf(dx) / 16.0)
				if me.dead:
					dir = "  — leżysz: drużyna musi cię podnieść"
				elif _in_exit(me.global_position):
					dir = "  — czekaj na drużynę" if extract_progress <= 0.0 else "  — EWAKUACJA %d%%" % int(extract_progress * 100.0)
			return "EKSTRAKCJA: dotrzyj do flary" + dir
	return ""

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
