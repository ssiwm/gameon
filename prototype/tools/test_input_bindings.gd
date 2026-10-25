extends SceneTree
## Regresja kontekstów, atomowych zamian, migracji zapisów i rzeczywistego menu/HUD-u.
## godot --headless --path prototype -s tools/test_input_bindings.gd
const A := preload("res://scripts/actions.gd")
const P := preload("res://scripts/bindings_policy.gd")
var total := 0
var failed := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		print("FAIL input bindings: ", label)

func key_event(code: int, location := KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.location = location
	e.pressed = true
	return e

func mouse_event(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e

func pad_event(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e

func axis_event(axis: int, value := 1.0) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

func accepted(id: String, dev: int, event: InputEvent, slot := -2) -> void:
	var result := A.set_binding(id, dev, event, false, slot)
	check("przypisanie " + id + ": " + String(result.reason), result.ok)
	check("brak konfliktu po " + id, P.conflicts(A._binds).is_empty())

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	A.reset_defaults(false)
	check("Classic bez konfliktów", P.conflicts(A._binds).is_empty())
	check("Modern bez konfliktów", A.plan_preset("modern").ok)
	check("Modern tylko na żądanie", A.preset_name() == "Classic")
	var other_pad := pad_event(JOY_BUTTON_A)
	other_pad.device = 2
	check("wiązania obsługują także kolejny kontroler", InputMap.event_is_action(other_pad, "jump") and InputMap.action_get_events("jump")[1].device == -1)
	for malformed in [{"type": "key", "code": "R"}, {"type": "mouse", "button": 0}, {"type": "axis", "axis": 99, "value": 1.0}, {"type": "axis", "axis": 0, "value": "one"}, {"type": "key", "code": KEY_UNKNOWN}]:
		check("wadliwy format " + str(malformed), P.normalize(malformed).is_empty())
	var before: Dictionary = A._binds.duplicate(true)
	var events := InputMap.action_get_events("fire")
	var unsafe := A.plan_binding("aim_sights", A.DEV_PAD, axis_event(JOY_AXIS_TRIGGER_RIGHT))
	check("ADS RT nie przenosi LT do ognia i krzyku", not unsafe.ok)
	check("odrzucony plan bez mutacji mapy", A._binds == before and events == InputMap.action_get_events("fire"))
	accepted("reload", A.DEV_KEY, key_event(KEY_SHIFT, KEY_LOCATION_LEFT))
	check("LeftShift przeładowuje", InputMap.event_is_action(key_event(KEY_SHIFT, KEY_LOCATION_LEFT), "reload"))
	check("wildcard Shift nie skrada równocześnie", not InputMap.event_is_action(key_event(KEY_SHIFT, KEY_LOCATION_LEFT), "crouch"))
	check("zamiana rozpoznaje ANY/LEFT", InputMap.event_is_action(key_event(KEY_R), "crouch"))
	A.reset_defaults(false)
	accepted("flare", A.DEV_KEY, key_event(KEY_ALT, KEY_LOCATION_RIGHT))
	check("prawy Alt jest prawym", A.bindings("flare")[0].location == KEY_LOCATION_RIGHT)
	check("LeftAlt tylko przedmiot", InputMap.event_is_action(key_event(KEY_ALT, KEY_LOCATION_LEFT), "throw") and not InputMap.event_is_action(key_event(KEY_ALT, KEY_LOCATION_LEFT), "flare"))
	check("RightAlt tylko flara", InputMap.event_is_action(key_event(KEY_ALT, KEY_LOCATION_RIGHT), "flare") and not InputMap.event_is_action(key_event(KEY_ALT, KEY_LOCATION_RIGHT), "throw"))
	A.reset_defaults(false)
	var swap := A.plan_binding("reload", A.DEV_KEY, key_event(KEY_B))
	check("plan pokazuje obie zamieniane akcje", swap.ok and swap.changed.has("reload") and swap.changed.has("firemode") and swap.changed.size() == 2)
	check("plan nie zmienia sterowania", A.key("reload") == "R")
	check("wynik wskazuje drugą akcję niezależnie od kolejności rejestru", swap.swapped == "firemode")
	accepted("flashlight", A.DEV_KEY, mouse_event(MOUSE_BUTTON_MIDDLE))
	check("plan sprzed zmiany odrzucony", not A.apply_plan(swap, false).ok and A.key("reload") == "R")
	for button in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		accepted("inspect_weapon", A.DEV_KEY, mouse_event(button), -1)
	check("trzy przypisania jednej akcji", A.editable_slots("inspect_weapon", A.DEV_KEY).size() == 3)
	var removable: int = A.editable_slots("inspect_weapon", A.DEV_KEY)[1]
	check("usuń dodatkowy przycisk", A.apply_plan(A.plan_remove("inspect_weapon", removable), false).ok)
	check("pozostaje H/M5", A.text("inspect_weapon", false, A.DEV_KEY) == "H / M5")
	A.reset_defaults(false)
	accepted("fire", A.DEV_KEY, mouse_event(MOUSE_BUTTON_RIGHT))
	check("zamiana obejmuje kontekst misji i strzelnicy", not InputMap.event_is_action(mouse_event(MOUSE_BUTTON_RIGHT), "melee") and not InputMap.event_is_action(mouse_event(MOUSE_BUTTON_RIGHT), "aim_sights"))
	A.reset_defaults(false)
	accepted("weapon_prev", A.DEV_KEY, mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	check("kółko obsługuje zamianę", InputMap.event_is_action(mouse_event(MOUSE_BUTTON_WHEEL_UP), "weapon_next"))
	accepted("journal", A.DEV_PAD, pad_event(JOY_BUTTON_MISC1), -1)
	check("puste przypisanie pada można uzupełnić", A.pad_rebindable("journal") and A.text("journal", false, A.DEV_PAD) == "Share")
	check("oś drążka nie przypisuje akcji", not A.plan_binding("journal", A.DEV_PAD, axis_event(JOY_AXIS_LEFT_X)).ok)
	check("nie można usunąć osi ruchu", not A.plan_remove("move_left", A.bindings("move_left").size() - 1).ok)
	check("nie można podmienić Esc", not A.plan_binding("pause", A.DEV_KEY, key_event(KEY_K), 0).ok)
	check("nie można usunąć Esc", not A.plan_remove("pause", 0).ok)
	accepted("pause", A.DEV_KEY, key_event(KEY_K))
	check("pauza zachowuje Esc oraz nowy klawisz", InputMap.event_is_action(key_event(KEY_ESCAPE), "pause") and InputMap.event_is_action(key_event(KEY_K), "pause"))
	check("Esc zarezerwowany", not A.plan_binding("journal", A.DEV_KEY, key_event(KEY_ESCAPE)).ok)
	# Migracja starych zapisów i jawnie pustych tablic.
	A.reset_defaults(false)
	var cf := ConfigFile.new()
	cf.set_value("keys", "throw", [{"type": "key", "code": KEY_ALT, "left": true}])
	cf.set_value("keys", "journal", [])
	cf.set_value("keys", "flashlight", [{"type": "key", "code": KEY_C, "left": false}])
	A.load_from(cf)
	check("stary left migruje", A.bindings("throw")[0].location == KEY_LOCATION_LEFT)
	check("bezpieczne przypisanie pozostaje", A.key("flashlight") == "C" and A.load_repairs.is_empty())
	var saved := ConfigFile.new()
	A.save_to(saved)
	check("puste przypisanie jest zapisywane", saved.has_section_key("keys", "journal") and saved.get_value("keys", "journal") == [])
	A.reset_defaults(false)
	A.load_from(saved)
	check("puste przypisanie wraca po wczytaniu", A.bindings("journal").is_empty())
	A.reset_defaults(false)
	cf = ConfigFile.new()
	cf.set_value("keys", "reload", [{"type": "key", "code": KEY_SHIFT, "left": true}])
	cf.set_value("keys", "flashlight", [{"type": "key", "code": KEY_C}])
	cf.set_value("keys", "flare", [{"type": "mouse", "button": 999}])
	cf.set_value("keys", "pause", [{"type": "key", "code": KEY_K}])
	cf.set_value("keys", "move_left", [])
	A.load_from(cf)
	check("konflikt starego zapisu naprawiony", A.key("reload") == "R" and A.load_repairs.has("reload") and P.conflicts(A._binds).is_empty())
	check("naprawa nie usuwa poprawnego C", A.key("flashlight") == "C")
	check("wadliwa niepusta tablica nie wyłącza akcji", A.key("flare") == "F" and A.load_repairs.has("flare"))
	check("wczytanie zachowuje Esc", InputMap.event_is_action(key_event(KEY_ESCAPE), "pause"))
	check("wczytanie zachowuje stałą oś", InputMap.event_is_action(axis_event(JOY_AXIS_LEFT_X, -1.0), "move_left"))
	A.reset_defaults(false)
	check("Modern aplikuje cały zestaw", A.apply_plan(A.plan_preset("modern"), false).ok and A.preset_name() == "Modern")
	check("Modern C + L", A.text("flashlight", false, A.DEV_KEY) == "C / L")
	check("Modern M4 jako podstawowy przedmiot", A.text("throw", true, A.DEV_KEY) == "M4")
	check("Modern X przeładowuje R3 bije", A.text("reload", false, A.DEV_PAD) == "X" and A.text("melee", false, A.DEV_PAD) == "R3")
	A.pad_family = A.family_of("Sony DualSense Wireless Controller")
	check("PlayStation Triangle / R2", A.text("weapon_next", true, A.DEV_PAD) == "Triangle" and A.text("fire", true, A.DEV_PAD) == "R2")
	A.pad_family = A.family_of("Nintendo Switch Pro Controller")
	check("Nintendo X / ZR", A.text("weapon_next", true, A.DEV_PAD) == "X" and A.text("fire", true, A.DEV_PAD) == "ZR")
	A.pad_family = "xbox"
	A.reset_defaults(false)
	var legacy := ConfigFile.new()
	legacy.set_value("keys", "flare", [{"type": "key", "code": KEY_H}])
	A.load_from(legacy)
	check("nowa akcja nie zabiera zapisanego H", A.key("flare") == "H" and A.bindings("inspect_weapon").is_empty() and P.conflicts(A._binds).is_empty())
	A.reset_defaults(false)
	# Rzeczywiste menu i HUD, nie kopia implementacji w atrapie.
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.port = 8958
	root.add_child(main)
	current_scene = main
	main.host_game()
	await process_frame
	await process_frame
	var pm: Node = main.get_node("UI/PauseMenu")
	var hud: Node = main.get_node("UI/HUD")
	var player: Node = hud._find_local_player()
	hud._player = player
	accepted("overcharge", A.DEV_KEY, key_event(KEY_U))
	accepted("weapon_1", A.DEV_KEY, key_event(KEY_6))
	accepted("weapon_2", A.DEV_KEY, key_event(KEY_8))
	accepted("weapon_3", A.DEV_KEY, key_event(KEY_0))
	hud._drive_weapons()
	check("kafelek HUD z aktualnego przypisania", hud._gear_keys.overcharge.text == "U")
	check("sloty HUD z aktualnych przypisań", hud._slot_labels[0].text == "6" and hud._slot_labels[1].text == "8" and hud._slot_labels[2].text == "0")
	check("ściąga nie sugeruje zakresu 6–0", A.hud_line().contains("6/8/0") and A.hud_line().contains("Z ammo") and A.hud_line().contains("H inspect"))
	A.pad_mode = true
	root.get_node("InputSetup").device_changed.emit(true)
	hud._drive_weapons()
	check("HUD pad nie podaje klawiszy 1/2/3", hud._slot_labels[0].text == "—" and A.key("overcharge") == "LB")
	check("strzelnica pad wskazuje Y", A.range_sheet()[7][0] == "Y")
	A.pad_mode = false
	accepted("pause", A.DEV_KEY, key_event(KEY_K))
	pm.open()
	pm._show_tab(5)
	check("otwarte menu blokuje strzał", root.get_node("Settings").blocked and InputMap.action_get_events("fire").is_empty())
	var capture_button := Button.new()
	pm.add_child(capture_button)
	pm._start_capture("journal", A.DEV_PAD, capture_button, -1)
	root.get_node("InputSetup")._input(axis_event(JOY_AXIS_LEFT_X))
	check("zmiana urządzenia nie anuluje capture", not pm._cap.is_empty())
	pm._capture_event(axis_event(JOY_AXIS_LEFT_X))
	check("ruch drążka nie kończy capture", not pm._cap.is_empty())
	pm._capture_event(key_event(KEY_ESCAPE))
	check("Esc anuluje capture i zachowuje menu", pm._cap.is_empty() and pm._open)
	pm._start_capture("journal", A.DEV_PAD, capture_button, -1)
	pm._capture_event(pad_event(JOY_BUTTON_MISC1))
	check("capture ma plan, nie mutację", pm._pending_plan.ok and A.text("journal", false, A.DEV_PAD) == "—")
	pm._confirm_controls.canceled.emit()
	pm._confirm_controls.hide()
	check("anulowanie planu bez zmiany", pm._pending_plan.is_empty() and A.text("journal", false, A.DEV_PAD) == "—")
	pm._start_capture("journal", A.DEV_PAD, capture_button, -1)
	pm._capture_event(pad_event(JOY_BUTTON_MISC1))
	pm._apply_pending_controls()
	check("zatwierdzenie zmienia schowek wejścia", InputMap.action_get_events("journal").is_empty())
	pm._input(key_event(KEY_ESCAPE))
	check("Esc zamyka po remapie pauzy", not pm._open and not root.get_node("Settings").blocked)
	check("po zamknięciu wraca nowe przypisanie", InputMap.event_is_action(pad_event(JOY_BUTTON_MISC1), "journal"))
	capture_button.free()
	player.set_physics_process(false)
	# Oględziny i flara przy rzeczywistym łupie, z tym samym kontrolerem co w misji.
	A.reset_defaults(false)
	var level: Node = get_first_node_in_group("level")
	level.spawn_item("weapon", 0, player.global_position + Vector2(0, -8))
	var wc: Node = player.weapons
	check("broń obok postaci", wc.nearby_weapon_item() != null)
	Input.action_press("inspect_weapon")
	wc._tick_inspect()
	check("H otwiera oględziny", wc.inspect_item != null)
	Input.action_release("inspect_weapon")
	await process_frame
	await process_frame
	wc.inspect_item = null
	var noise: Node = root.get_node("NoiseMgr")
	var flares_before: int = noise.flares
	Input.action_press("flare")
	wc._tick_inspect()
	check("F nie otwiera oględzin", wc.inspect_item == null)
	player._local_brain(0.0)
	Input.action_release("flare")
	await process_frame
	check("F rzuca flarę przy broni", noise.flares == flares_before - 1)
	# Stan TOGGLE strzelnicy, niezależny od skradania na misji.
	var fp: Node = load("res://scripts/range3d/fp_mode.gd").new()
	fp.x = 0.0
	var st: Node = root.get_node("Settings")
	st.fp_brace_toggle = true
	Input.action_press("crouch")
	fp._update_brace()
	check("podparcie Toggle włącza", fp.braced_pose)
	Input.action_release("crouch")
	await process_frame
	fp._update_brace()
	check("podparcie Toggle pozostaje po zwolnieniu", fp.braced_pose)
	fp._reset_brace()
	check("zmiana stanowiska/nakładka kasuje Toggle", not fp.braced_pose and not fp._brace_latched)
	st.fp_brace_toggle = false
	Input.action_press("crouch")
	fp._update_brace()
	check("podparcie Hold włącza", fp.braced_pose)
	Input.action_release("crouch")
	fp._update_brace()
	check("podparcie Hold znika", not fp.braced_pose)
	fp.free()
	A.reset_defaults(false)
	A.pad_mode = false
	root.get_node("Audio").set_process(false)
	main.free()
	await process_frame
	await process_frame
	print("%s input bindings: %d checks, %d errors" % ["PASS" if failed == 0 else "FAIL", total, failed])
	root.get_node("Audio").quit_game(0 if failed == 0 else 1)
