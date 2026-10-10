extends SceneTree
## Koszt renderu efektów atmosfery (smugi, bloom, cienie) w kryjówce: czas klatki (CPU + GPU, z odczytem do synchronizacji)
## przy poziomach jakości HIGH / MEDIUM / LOW. Nie zależy od vsync (force_draw bez prezentacji); scena stoi w miejscu.
##   godot --path prototype --resolution 1920x1080 --script tools/bench_fx.gd -- [--mission=z1_hub] [--char3d]
var _main: Node
var _started := false

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_d: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false

func _run() -> void:
	var map := "z1_hub"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			map = a.substr(10)
	for i in 5:
		await process_frame
	_main._start_map = map
	_main.host_game()
	for i in 120:
		await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var st := root.get_node("Settings")
	print("[FXBENCH] viewport=", root.get_visible_rect().size, " window=", root.size, " map=", map)
	for q in [2, 1, 0, 2, 1, 0]:
		st.quality_idx = q
		st.changed.emit()
		for i in 30:
			await process_frame
		root.get_texture().get_image()
		var t0 := Time.get_ticks_usec()
		for i in 90:
			RenderingServer.force_draw(false)
			root.get_texture().get_image()
		print("[FXBENCH] quality=%d  %.2f ms/frame" % [q, float(Time.get_ticks_usec() - t0) / 90000.0])
	quit()
