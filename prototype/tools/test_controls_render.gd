extends SceneTree
## Rzeczywisty panel sterowania: klawiatura, pad, fokus, lokalizacja i widoczność kolumn.
## xvfb-run godot --path prototype --rendering-driver opengl3 -s tools/test_controls_render.gd -- --controls-shot=/tmp/controls.png
const A := preload("res://scripts/actions.gd")
var failed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		print("FAIL controls render: ", label)

func _escape() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	A.reset_defaults(false)
	TranslationServer.set_locale("pl")
	var panel: Control = load("res://scripts/pause_menu.gd").new()
	root.add_child(panel)
	panel.open()
	panel._show_tab(5)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	check("profil i przyciski widoczne", panel._rebind_msg.get_global_rect().end.y < panel._pages[5].get_global_rect().end.y)
	var list: VBoxContainer = panel._rebind_list
	check("wszystkie akcje w menu", list.get_child_count() == A.rebindable().size() + 1)
	var row: HBoxContainer = list.get_child(1)
	var last_col: Control = row.get_child(2)
	var scroll: ScrollContainer = list.get_parent()
	check("kolumny mieszczą się bez poziomego przewijania", list.size.x <= scroll.size.x + 1.0 and last_col.get_global_rect().end.x <= scroll.get_global_rect().end.x + 1.0)
	check("polska etykieta profilu", panel._profile_label.text.begins_with("Profil sterowania:"))
	check("fokus przewija listę", scroll.follow_focus)
	var first_key: Button = row.get_child(1).get_child(0).get_child(0)
	check("pierwszy klawisz ruchu", first_key.text == "A")
	first_key.pressed.emit()
	check("przycisk faktycznie uruchamia capture", panel._cap.id == "move_left" and panel._cap.slot == 0)
	panel._capture_event(_escape())
	# Usunięcie drugiego przypisania musi dotyczyć strzałki, nie pierwszego A.
	row = list.get_child(1)
	var second_remove: Button = row.get_child(1).get_child(1).get_child(1)
	second_remove.pressed.emit()
	check("usuń wskazany dodatkowy klawisz", panel._pending_plan.ok and panel._pending_plan.bindings.move_left.size() == 2 and panel._pending_plan.bindings.move_left[0].code == KEY_A)
	panel._confirm_controls.canceled.emit()
	panel._confirm_controls.hide()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--controls-shot="):
			var image := root.get_texture().get_image()
			check("zapis zrzutu", image.save_png(arg.trim_prefix("--controls-shot=")) == OK)
	panel.close()
	panel.queue_free()
	print("%s controls render: %d checks, %d errors" % ["PASS" if failed == 0 else "FAIL", total, failed])
	quit.call_deferred(0 if failed == 0 else 1)
