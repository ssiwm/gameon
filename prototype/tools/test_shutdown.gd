extends SceneTree
## Regresja własności węzłów i zamykania aktywnego audio; działa też z natywnym oknem.
## --headless --path prototype --script res://tools/test_shutdown.gd
## -- --shutdown-window / --shutdown-exit=7: osobne ścieżki i zachowanie kodu wyjścia.
var _failed := 0
var _total := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	_total += 1
	if not ok:
		_failed += 1
	print("[SHUTDOWN-TEST] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var before := Node.get_orphan_node_ids()
	# Dread odwołuje się do autoloadów; w SceneTree ładujemy go po ich inicjalizacji.
	var dread_script := load("res://scripts/dread.gd") as GDScript
	var detached: Node = dread_script.new()
	detached.free()
	_check("instancja grozy bez wejścia do drzewa nie pozostawia pomocniczego węzła", Node.get_orphan_node_ids() == before)
	var dread: Node = dread_script.new()
	root.add_child(dread)
	_check("groza tworzy oczy wyłącznie przy aktywnym obrazie", dread._eyes == null if DisplayServer.get_name() == "headless" else is_instance_valid(dread._eyes) and dread.is_ancestor_of(dread._eyes))
	dread.free()
	_check("zwolnienie grozy zachowuje listę osieroconych węzłów", Node.get_orphan_node_ids() == before)
	var audio := root.get_node("Audio")
	print("[SHUTDOWN-TEST] audio driver=", AudioServer.get_driver_name())
	audio.set_enabled(true)
	var source := Node2D.new()
	root.add_child(source)
	audio.start_loop("amb_forest", audio.BUS_AMB, -20.0)
	audio.start_loop_at("amb_machine", source, audio.BUS_WORLD, -20.0, false, "shutdown-fixture")
	audio.music_set_layer(2)
	audio.play("ui_click", audio.BUS_UI, -20.0)
	await create_timer(0.2).timeout
	_check("fixture faktycznie uruchamia pętle i stemy przed sprzątaniem", audio._enabled and audio._loops.size() == 1 and audio._pos_loops.size() == 1 and audio._music_started)
	audio.shutdown()
	_check("shutdown zwalnia pętle i cache oraz wyłącza muzykę", audio._loops.is_empty() and audio._pos_loops.is_empty() and audio._cache.is_empty() and not audio._music_started)
	var players: Array = []
	players.append_array(audio._pool)
	players.append_array(audio._pos_pool)
	players.append_array(audio._music)
	_check("odtwarzacze nie trzymają strumieni po shutdown", players.all(func(node: Node) -> bool: return not node.playing and node.stream == null))
	audio.start_loop("amb_forest")
	audio.start_loop_at("amb_machine", source)
	audio.play("ui_click")
	_check("wyłączone audio nie tworzy nowych głosów i pętli", not audio._enabled and audio._loops.is_empty() and audio._pos_loops.is_empty() and audio._cache.is_empty())
	audio.shutdown()
	source.free()
	_check("powtórne shutdown jest bezpieczne", Node.get_orphan_node_ids() == before)
	audio.set_enabled(true)
	audio.start_loop("amb_forest", audio.BUS_AMB, -20.0)
	audio.music_set_layer(1)
	_check("audio można ponownie uruchomić przed żądaniem wyjścia", audio._enabled and audio._music_started and audio._loops.size() == 1)
	_check("zamknięcie okna przechodzi przez callback zamiast auto_accept_quit", not is_auto_accept_quit() and root.close_requested.is_connected(audio.quit_game))
	print("[SHUTDOWN-TEST] ==== %d/%d OK, błędów: %d ====" % [_total - _failed, _total, _failed])
	var code := 1 if _failed else 0
	if "--shutdown-paused" in OS.get_cmdline_user_args():
		paused = true
		Engine.time_scale = 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shutdown-exit=") and _failed == 0:
			code = int(arg.trim_prefix("--shutdown-exit="))
	if "--shutdown-window" in OS.get_cmdline_user_args() and _failed == 0:
		root.close_requested.emit()
	else:
		audio.quit_game(code)
	audio.quit_game(0) # kolejne żądanie nie nadpisuje kodu ani nie uruchamia audio ponownie
	audio.set_enabled(true)
	if not audio._quitting or audio._enabled:
		push_error("Żądanie wyjścia musi zablokować ponowne uruchomienie audio")
