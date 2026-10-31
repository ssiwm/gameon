extends Node
## Dev: pomiar przestojów w oknie (z GPU) przy zdarzeniach, na które skarżą się gracze — podnoszenie znajdziek, wejście do kryjówki,
## start misji z kryjówki:
##
##   godot --verbose --path . -- --host --mission=z1_m1 --hitchtest --autoquit=120
##
## (bez `--verbose` też działa; z nim nad każdym [SPIKE-MARK] stoją wczytane zasoby). Zapisuje profil i postęp — uruchamiać
## z override.cfg na osobny katalog użytkownika (zob. tools/shutdown_render_qa.gd).
## Każda klatka ≥ HITCH_MS po starcie pomiaru drukuje [HITCH] z etykietą ostatniego zdarzenia i czasem od niego; na końcu [HITCH-SUM]
## — najdłuższa klatka i liczba klatek ≥ 33 ms na etykietę. Klatki pod planszą wczytywania („LOADING…”) liczą się osobno (etykieta
## z dopiskiem „/curtain”): gracz ich nie widzi jako przycięcia gry.

const HITCH_MS := 33.0
const KINDS := ["scrap", "ammo", "health", "stash", "part", "supply", "flares", "cache", "power", "tag"]

var main: Node
var _label := "boot"
var _label_t := 0
var _last := 0
var _stats := {}                      ## etykieta → [max ms, liczba ≥ HITCH_MS]
var _v3d: Node

func run(m: Node) -> void:
	main = m
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	process_priority = -1000
	_go.call_deferred()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0:
		var ms := float(now - _last) / 1000.0
		var lab := _label + ("/curtain" if _curtain_up() else "")
		var s: Array = _stats.get(lab, [0.0, 0])
		s[0] = maxf(float(s[0]), ms)
		if ms >= HITCH_MS:
			s[1] = int(s[1]) + 1
			print("[HITCH] %.0f ms  %s  +%.2f s  (render cpu %.0f, gpu %.0f, potoki %s)" % [ms, lab, float(now - _label_t) / 1e6,
				_render_cpu(), _render_gpu(), _pipes()])
		_stats[lab] = s
	_last = now

const PIPES := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"spec": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}
var _pipe_prev := {}

## Kompilacje potoków GPU od poprzedniej długiej klatki (liczniki silnika rosną od startu): które rodzaje i ile.
func _pipes() -> String:
	var out: Array = []
	for k in PIPES:
		var v := int(Performance.get_monitor(PIPES[k]))
		if v != int(_pipe_prev.get(k, v)):
			out.append("%s+%d" % [k, v - int(_pipe_prev[k])])
		_pipe_prev[k] = v
	return ",".join(out) if not out.is_empty() else "-"

## Czas renderu ostatniej klatki (ms): okno i SubViewporty widoku 3D (pomiar włącza session_log.watch_viewports).
func _render_cpu() -> float:
	var t := RenderingServer.get_frame_setup_time_cpu()
	for v in _vps():
		t += RenderingServer.viewport_get_measured_render_time_cpu(v)
	return t

func _render_gpu() -> float:
	var t := 0.0
	for v in _vps():
		t += RenderingServer.viewport_get_measured_render_time_gpu(v)
	return t

func _vps() -> Array:
	var out: Array = [get_viewport().get_viewport_rid()]
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		out.append((n as SubViewport).get_viewport_rid())
	return out

func _mark(label: String) -> void:
	_label = label
	_label_t = Time.get_ticks_usec()
	print("[HITCH-EV] %s" % label)

func _curtain_up() -> bool:
	if _v3d == null:
		for n in get_tree().root.find_children("*", "", true, false):
			if n.has_method("_drag_smear"):
				_v3d = n
				break
	if _v3d == null:
		return false
	var c = _v3d.get("_curtain")
	return bool(_v3d.get("_building")) or int(_v3d.get("_warm_stage")) >= 0 or (c != null and (c as CanvasLayer).visible)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _wait_loaded() -> void:
	await _wait(0.5)
	while _curtain_up():
		await get_tree().process_frame

func _player() -> Node2D:
	return main.get("_players").get_node_or_null("1") as Node2D

func _go() -> void:
	await _wait_loaded()
	_mark("idle_after_load")
	await _wait(3.0)
	for round_i in 2:
		for k in KINDS:
			await _pickup(k, round_i)
	for w in [1, 2, 4, 6]:
		await _weapon_e(w)
	_mark("extract")
	main.mission._open_extraction()
	main.mission._broadcast()
	await _wait(3.0)
	_mark("success")
	main.mission.elapsed = 200.0
	main.mission._success()
	await _wait(3.0)
	_mark("to_hub")
	main._continue_after_result()
	await _wait_loaded()
	_mark("hub_idle")
	await _wait(6.0)
	for k in ["scrap", "ammo"]:
		await _pickup(k, 0, "hub_")
	await _cabinets()
	_mark("hub_depart")
	main._depart_hub()
	await _wait_loaded()
	_mark("next_mission_idle")
	await _wait(6.0)
	_summary()

## Znajdźka 40 px przed graczem (spawn i model osobno), po 1 s przesunięta pod jego stopy — samo podniesienie.
func _pickup(kind: String, round_i: int, prefix := "") -> void:
	var p := _player()
	if p == null:
		return
	if kind == "health":
		p.set("hp", 1)
	var arg := 0
	var rounds := 25
	match kind:
		"ammo":
			var prim: Array = p.kit_primaries()
			arg = int(prim[0]) if not prim.is_empty() else 0
			Arsenal.set_reserve(arg, 0)
		"power":
			arg = 9
			rounds = 30
		"flares":
			NoiseMgr.flares = 0
			rounds = 2
	var lvl: Node = main.level
	var before := lvl.get_child_count()
	_mark("%sspawn_%s#%d" % [prefix, kind, round_i])
	lvl.spawn_item(kind, arg, p.global_position + Vector2(40, -6), rounds)
	await _wait(1.0)
	var item: Node2D = null
	for i in range(lvl.get_child_count() - 1, -1, -1):
		var c := lvl.get_child(i)
		if c.is_in_group("pickups") and String(c.get("kind")) == kind:
			item = c as Node2D
			break
	if item == null or lvl.get_child_count() < before:
		print("[HITCH] brak przedmiotu %s" % kind)
		return
	_mark("%stake_%s#%d" % [prefix, kind, round_i])
	item.global_position = p.global_position + Vector2(0, -4)
	await _wait(1.2)
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		print("[HITCH] %s nie podniesiony" % kind)
		item.queue_free()

func _pulse(action: String) -> void:
	Input.action_press(action)
	for i in 2:
		await get_tree().physics_frame
	Input.action_release(action)
	for i in 3:
		await get_tree().physics_frame

## Broń na ziemi [E]: spawn obok (model osobno), po 1 s podniesienie przyciskiem.
func _weapon_e(w: int) -> void:
	var p := _player()
	var lvl: Node = main.level
	_mark("spawn_weapon_%d" % w)
	lvl.spawn_item("weapon", w, p.global_position + Vector2(10, -6))
	await _wait(1.0)
	_mark("take_weapon_%d" % w)
	await _pulse("interact")
	await _wait(1.2)

## Kryjówka: każda broń z gablot — oględziny przy gablocie, [E] bierze, po chwili następna.
func _cabinets() -> void:
	var p := _player()
	var wc: Node = p.weapons
	for cab in get_tree().get_nodes_in_group("cabinets"):
		for it in get_tree().get_nodes_in_group("pickups"):
			if not is_instance_valid(it) or it.get("kind") != "weapon" or not it.has_meta("cabinet") or it.is_queued_for_deletion():
				continue
			if not (cab as Node2D).global_position.distance_to((it as Node2D).global_position) < 80.0:
				continue
			p.global_position = (cab as Node2D).global_position + Vector2(-20, -2)
			await _wait(0.6)
			_mark("cab_open_%d" % int(it.arg))
			wc.set("inspect_item", it)
			await _wait(0.8)
			_mark("cab_take_%d" % int(it.arg))
			await _pulse("interact")
			await _wait(1.0)
			wc.set("inspect_item", null)
			await _wait(0.3)

func _summary() -> void:
	var keys := _stats.keys()
	for k in keys:
		var s: Array = _stats[k]
		print("[HITCH-SUM] %-28s max %6.0f ms  ≥%.0f ms: %d" % [k, float(s[0]), HITCH_MS, int(s[1])])
	Audio.quit_game()
