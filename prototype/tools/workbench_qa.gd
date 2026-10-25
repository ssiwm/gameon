extends SceneTree
## Render rzeczywistej ławy, opcjonalnie pomiar klatek, bez zapisu profilu i postępu.
## godot --path prototype --resolution 1280x720 --script tools/workbench_qa.gd -- --host --mission=z1_hub --qa-out=bench.png --qa-locale=pl
## --qa-part=m83_drum75 --qa-fit=m83_rpkbar,m83_pbs1 --qa-weapon=0..11 --qa-mount --qa-perf=4
## --qa-legacy=ŚCIEŻKA ładuje wcześniejszy WorkshopUI wyłącznie do porównania prezentacji.
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const Actions := preload("res://scripts/actions.gd")
var _out := "workbench-qa.png"
var _locale := "en"
var _weapon := 0
var _part := ""
var _fit := ""
var _legacy := ""
var _perf := 0.0
var _mount := false
var _large_ui := false
var _pad := false
var _details := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			_out = arg.trim_prefix("--qa-out=")
		elif arg.begins_with("--qa-locale="):
			_locale = arg.trim_prefix("--qa-locale=")
		elif arg.begins_with("--qa-weapon="):
			_weapon = clampi(int(arg.trim_prefix("--qa-weapon=")), 0, 11)
		elif arg.begins_with("--qa-part="):
			_part = arg.trim_prefix("--qa-part=")
		elif arg.begins_with("--qa-fit="):
			_fit = arg.trim_prefix("--qa-fit=")
		elif arg.begins_with("--qa-legacy="):
			_legacy = arg.trim_prefix("--qa-legacy=")
		elif arg.begins_with("--qa-perf="):
			_perf = maxf(0.0, float(arg.trim_prefix("--qa-perf=")))
		elif arg == "--qa-mount":
			_mount = true
		elif arg == "--qa-large-ui":
			_large_ui = true
		elif arg == "--qa-pad":
			_pad = true
		elif arg == "--qa-details":
			_details = true
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("workbench_qa wymaga renderera i okna (bez --headless).")
		root.get_node("Audio").quit_game(1)
		return
	var settings := root.get_node("Settings")
	var profile := root.get_node("Profile")
	var scrap := root.get_node("Scrap")
	profile.persist = false
	scrap.persist = false
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(2.0).timeout
	settings.locale_idx = 1 if _locale == "pl" else 0
	TranslationServer.set_locale(_locale)
	Actions.pad_mode = _pad
	if _large_ui:
		settings.ui_idx = 2
		settings.changed.emit()
	profile.persist = false
	scrap.persist = false
	profile.reset_for_test()
	scrap.bank = 480
	for w in 12:
		scrap.unlocked[w] = true
	for id in ["m83_rpk40", "m83_rpkbar"] + Array(_fit.split(",", false)):
		if Parts.is_valid(String(id)):
			scrap.parts[String(id)] = true
	for id in _fit.split(",", false):
		var data := Parts.get_part(id)
		if not data.is_empty():
			profile.set_fit(String(data["weapon"]), String(data["slot"]), id)
	scrap.changed.emit()
	var player: Node2D
	for actor in get_nodes_in_group("players"):
		if not actor.is_bot and actor.is_multiplayer_authority():
			player = actor
		else:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	if player == null:
		push_error("Brak lokalnego gracza QA; uruchom --host --mission=z1_hub.")
		root.get_node("Audio").quit_game(1)
		return
	player.set_physics_process(false)
	var bench := get_first_node_in_group("workshop") as Node2D
	if bench == null:
		push_error("Brak ławy QA; uruchom --mission=z1_hub.")
		root.get_node("Audio").quit_game(1)
		return
	player.global_position = bench.global_position + Vector2(0, -2)
	await create_timer(0.3).timeout
	var ui := get_first_node_in_group("workshop_ui")
	if _legacy != "":
		var hud := ui.get_parent()
		ui.queue_free()
		await process_frame
		ui = (load(_legacy) as GDScript).new()
		hud.add_child(ui)
	ui.open("bench")
	ui._select(_weapon)
	if _part != "":
		var ops: Array = ui._options(int(ui.LIST[_weapon]))
		var found := false
		for i in ops.size():
			if String(ops[i]["id"]) == _part:
				ui._pick_opt(i)
				found = true
				break
		if not found:
			push_error("Część QA nie należy do wybranej broni: " + _part)
			root.get_node("Audio").quit_game(1)
			return
	elif _legacy != "":
		ui._opt = 0 # oba warianty oglądają tę samą konfigurację fabryczną
		ui._refresh()
	if _details and _legacy == "":
		ui._workbench._toggle_details()
	await create_timer(2.0).timeout
	var result := {"locale": _locale, "weapon": _weapon, "part": _part, "legacy": _legacy != ""}
	if _perf > 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		var samples: Array[float] = []
		var gpu_samples: Array[float] = []
		var render_cpu := 0.0
		var stage_gpu := 0.0
		var viewports: Array[RID] = [root.get_viewport_rid()]
		for node in root.find_children("*", "SubViewport", true, false):
			viewports.append((node as SubViewport).get_viewport_rid())
		for rid in viewports:
			RenderingServer.viewport_set_measure_render_time(rid, true)
		var elapsed := 0.0
		var previous := Time.get_ticks_usec()
		while elapsed < _perf:
			await process_frame
			var now := Time.get_ticks_usec()
			var frame := float(now - previous) / 1000.0
			samples.append(frame)
			var gpu := 0.0
			for rid in viewports:
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
				render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			render_cpu += RenderingServer.get_frame_setup_time_cpu()
			stage_gpu += RenderingServer.viewport_get_measured_render_time_gpu(ui._d_stage._vp.get_viewport_rid())
			gpu_samples.append(gpu)
			elapsed += frame / 1000.0
			previous = now
		var total := 0.0
		for frame in samples:
			total += frame
		samples.sort()
		result["frames"] = samples.size()
		result["mean_ms"] = total / maxf(1, samples.size())
		result["p95_ms"] = samples[mini(samples.size() - 1, int(samples.size() * 0.95))]
		result["max_ms"] = samples.back()
		result["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var gpu_total := 0.0
		for gpu in gpu_samples:
			gpu_total += gpu
		gpu_samples.sort()
		result["gpu_mean_ms"] = gpu_total / maxf(1, samples.size())
		result["gpu_p95_ms"] = gpu_samples[mini(gpu_samples.size() - 1, int(gpu_samples.size() * 0.95))]
		result["render_cpu_ms"] = render_cpu / maxf(1, samples.size())
		result["stage_gpu_ms"] = stage_gpu / maxf(1, samples.size())
	if _mount:
		ui._act()
		await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(_out)
	result["image_size"] = [image.get_width(), image.get_height()]
	var card_rect: Rect2 = ui._card.get_global_rect()
	result["card_rect"] = [card_rect.position.x, card_rect.position.y, card_rect.size.x, card_rect.size.y]
	result["viewport_rect"] = str(root.get_visible_rect())
	result["layout_ok"] = root.get_visible_rect().grow(1).encloses(card_rect) and root.get_visible_rect().grow(1).encloses(ui._action.get_global_rect())
	result["stage_pixels"] = [ui._d_stage._vp.size.x, ui._d_stage._vp.size.y]
	result["mount_time"] = ui._d_stage._mount_time
	var file := FileAccess.open(_out.get_basename() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("[WORKBENCH-QA] ", JSON.stringify(result))
	ui.close()
	root.get_node("Audio").quit_game(0 if error == OK and result["layout_ok"] else 1)
