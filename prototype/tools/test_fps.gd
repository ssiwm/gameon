extends SceneTree
## Test licznika FPS (scripts/fps_overlay.gd) i próbek płynności w dzienniku sesji (scripts/session_log.gd): tekst, kolory, kiedy licznika nie ma,
## pole p99 i mapa „menu”. Dziennik idzie do osobnego katalogu, zapis gracza nietknięty.
##   godot --headless --path prototype -s tools/test_fps.gd     → ostatni wiersz: PASS / FAIL

const LOG_DIR := "user://_test_fps"

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[FPS] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _clear_dir() -> void:
	var d := DirAccess.open(LOG_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(LOG_DIR)


func _initialize() -> void:
	_run.call_deferred()


## Dopiero po starcie: te skrypty używają autoloadów, których przy kompilacji skryptu `-s` jeszcze nie ma (stąd load, nie preload).
func _run() -> void:
	var Overlay: GDScript = load("res://scripts/fps_overlay.gd")
	var SessionLog: GDScript = load("res://scripts/session_log.gd")
	var UiTheme: GDScript = load("res://scripts/ui_theme.gd")
	var muted: Color = UiTheme.MUTED
	var accent: Color = UiTheme.ACCENT
	var danger: Color = UiTheme.DANGER

	_check("tekst licznika", Overlay.label_text(60, 16.7) == "60 FPS  17 ms")
	_check("płynnie: kolor przygaszony", Overlay.tone(60, 17.0) == muted)
	_check("przeskok klatki: ostrzeżenie mimo 60 FPS", Overlay.tone(60, 40.0) == accent)
	_check("mało FPS: ostrzeżenie", Overlay.tone(45, 25.0) == accent)
	_check("przestój: czerwony mimo 60 FPS", Overlay.tone(60, 80.0) == danger)
	_check("poniżej 30 FPS: czerwony", Overlay.tone(25, 42.0) == danger)

	var none := PackedStringArray()
	_check("zwykła gra: licznik jest", not Overlay.hidden_by_args(PackedStringArray(["--host"]), none))
	_check("zrzut: bez licznika", Overlay.hidden_by_args(PackedStringArray(["--shot=a.png"]), none))
	_check("--nohud: bez licznika", Overlay.hidden_by_args(PackedStringArray(["--nohud"]), none))
	_check("nagranie: bez licznika", Overlay.hidden_by_args(none, PackedStringArray(["--write-movie", "a.avi"])))
	_check("narzędzie -s: bez licznika", Overlay.hidden_by_args(none, PackedStringArray(["-s", "tools/x.gd"])))
	_check("--showfps wymusza licznik na zrzucie", not Overlay.hidden_by_args(PackedStringArray(["--shot=a.png", "--showfps"]), none))
	_check("headless: licznik nie zajmuje miejsca w HUD-zie", root.get_node("FpsOverlay").band() == 0.0)

	_clear_dir()
	SessionLog.enabled = true
	SessionLog.dir = LOG_DIR
	SessionLog.reset_for_test()
	for i in 10:
		SessionLog.frame(0.040, "menu")
	for i in 590:
		SessionLog.frame(0.01667, "menu")
	var row := {}
	var path: String = SessionLog.path
	SessionLog.reset_for_test()
	if path != "":
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary and parsed.get("ev") == "perf":
				row = parsed
	SessionLog.enabled = false
	SessionLog.dir = SessionLog.DIR
	_clear_dir()
	_check("próbka perf zapisana co 10 s", not row.is_empty())
	_check("mapa „menu” w próbce", row.get("map") == "menu")
	_check("p95 pomija 1,7%% przeskoków: %s" % str(row.get("p95")), is_equal_approx(float(row.get("p95", 0.0)), 16.67))
	_check("p99 je łapie: %s" % str(row.get("p99")), is_equal_approx(float(row.get("p99", 0.0)), 40.0))
	_check("FPS: %s" % str(row.get("fps")), absi(int(row.get("fps", 0)) - 58) <= 1)

	print("%s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
