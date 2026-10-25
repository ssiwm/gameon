extends SceneTree
## Test ustawienia jasności i ekranu kalibracji (scripts/brightness_screen.gd), headless: zakres ±1 EV i mnożnik ekspozycji, suwak zmienia
## ustawienie na żywo, CANCEL przywraca wartość sprzed otwarcia, CONFIRM zapisuje flagę kalibracji, pierwszy start bez CANCEL, wiersz
## „Brightness” w menu pauzy otwiera ekran. Ustawienia gracza (user://settings.cfg) wracają na koniec do stanu sprzed testu.
##   godot --headless --path prototype -s tools/test_brightness.gd     → ostatni wiersz: PASS / FAIL

var _fails := 0
var _settings: Node
var _saved_idx := 0
var _saved_cal := false


func _check(name: String, ok: bool) -> void:
	print("[BRIGHTNESS] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node("Settings")
	_saved_idx = int(_settings.get("brightness_idx"))
	_saved_cal = bool(_settings.get("brightness_calibrated"))
	var evs: Array = _settings.get("BRIGHTNESS_EV")

	# 1. Zakres i ekspozycja
	_check("zakres ±1 EV", is_equal_approx(float(evs[0]), -1.0) and is_equal_approx(float(evs[evs.size() - 1]), 1.0))
	_settings.call("set_brightness", int(_settings.get("BRIGHTNESS_DEFAULT")))
	_check("domyślnie 0 EV → mnożnik 1", is_equal_approx(float(_settings.call("exposure_mult")), 1.0))
	_settings.call("set_brightness", 99)
	_check("indeks przycięty do +1 EV → mnożnik 2", is_equal_approx(float(_settings.call("exposure_mult")), 2.0))
	_settings.call("set_brightness", int(_settings.get("BRIGHTNESS_DEFAULT")))

	# 2. Ekran: suwak, CANCEL przywraca
	var screen_script: GDScript = load("res://scripts/brightness_screen.gd")
	var s: Control = screen_script.new()
	root.add_child(s)
	await process_frame
	var slider: HSlider = s.get("_slider")
	slider.value = 7
	_check("suwak zmienia jasność na żywo", int(_settings.get("brightness_idx")) == 7)
	var env: Environment = s.get("_env")
	_check("karta kalibracji ma ekspozycję z ustawienia", env != null and is_equal_approx(env.tonemap_exposure, float(_settings.call("exposure_mult"))))
	s.call("_cancel")
	_check("CANCEL przywraca wartość sprzed otwarcia", int(_settings.get("brightness_idx")) == int(_settings.get("BRIGHTNESS_DEFAULT")))
	await process_frame
	_check("ekran zamknięty po CANCEL", not is_instance_valid(s))

	# 3. CONFIRM zapisuje i oznacza kalibrację
	_settings.set("brightness_calibrated", false)
	s = screen_script.new()
	root.add_child(s)
	await process_frame
	(s.get("_slider") as HSlider).value = 2
	s.call("_confirm")
	_check("CONFIRM zostawia nową jasność", int(_settings.get("brightness_idx")) == 2)
	_check("CONFIRM oznacza kalibrację", bool(_settings.get("brightness_calibrated")))

	# 4. Pierwszy start: bez CANCEL, Esc zostawia domyślną i nie pyta ponownie
	_settings.set("brightness_calibrated", false)
	_settings.call("set_brightness", int(_settings.get("BRIGHTNESS_DEFAULT")))
	s = screen_script.new()
	s.call("setup", true)
	root.add_child(s)
	await process_frame
	var labels: Array = []
	for b in s.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	_check("pierwszy start bez przycisku CANCEL", not labels.has(TranslationServer.translate("CANCEL")) and labels.size() == 2)
	s.call("_cancel")
	_check("pierwszy start: Esc oznacza kalibrację", bool(_settings.get("brightness_calibrated")))

	# 5. Menu pauzy: wiersz otwiera ekran
	var pm: Control = (load("res://scripts/pause_menu.gd") as GDScript).new()
	var ui := CanvasLayer.new()
	root.add_child(ui)
	ui.add_child(pm)
	await process_frame
	pm.call("open_brightness")
	await process_frame
	var opened := ui.get_children().filter(func(c: Node) -> bool: return c.get_script() == screen_script)
	_check("menu pauzy otwiera ekran kalibracji nad sobą", opened.size() == 1 and opened[0].get_index() > pm.get_index())

	_settings.set("brightness_calibrated", _saved_cal)
	_settings.call("set_brightness", _saved_idx)
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
