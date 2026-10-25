extends SceneTree
## Zamykanie gry z prawdziwym rendererem (komunikaty RenderingDevice przy wyjściu widać tylko w oknie, nie w headless): otwiera podane
## stanowiska kryjówki ze wszystkimi stronami, zamyka grę przez Audio.quit_game. Bez zapisu Profile / Scrap.
## godot --path prototype --resolution 1280x720 --script res://tools/shutdown_render_qa.gd -- --host --mission=z1_hub --qa-modes=locker,bench
## Wynik czytać z wyjścia procesu: „Attempted to free invalid ID” albo „RIDs of type … were leaked” = błąd. Ustawienia gracza izolować
## (np. prototype/override.cfg z application/config/custom_user_dir_name, usunąć po przebiegu), bo gra wczytuje i zapisuje settings.cfg.
var _modes: Array = ["bench", "service", "locker", "press", "pyro", "lab", "lathe"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-modes="):
			_modes = Array(arg.trim_prefix("--qa-modes=").split(",", false))
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("shutdown_render_qa wymaga renderera i okna (bez --headless).")
		root.get_node("Audio").quit_game(1)
		return
	root.get_node("Profile").persist = false
	root.get_node("Scrap").persist = false
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(2.0).timeout
	var player: Node2D
	for actor in get_nodes_in_group("players"):
		if not actor.is_bot and actor.is_multiplayer_authority():
			player = actor
	if player == null:
		push_error("Brak lokalnego gracza; uruchom --host --mission=z1_hub.")
		root.get_node("Audio").quit_game(1)
		return
	player.set_physics_process(false)
	var ui := get_first_node_in_group("workshop_ui")
	for mode in _modes:
		var station := get_first_node_in_group(String(ui.MODE_GROUP[mode])) as Node2D
		if station == null:
			continue
		player.global_position = station.global_position + Vector2(0, -2)
		await create_timer(0.4).timeout
		ui.open(mode)
		for page in ui.MODE_PAGES[mode]:
			ui._set_page(int(page))
			await create_timer(0.8).timeout
		ui.close()
		await create_timer(0.3).timeout
		print("[SHUTDOWN-QA] ", mode)
	root.get_node("Audio").quit_game(0)
