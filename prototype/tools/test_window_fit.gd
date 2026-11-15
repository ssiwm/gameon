extends SceneTree
## Test rozmiaru i położenia okna (scripts/settings.gd): okno pierwszego startu wg ekranu, rozmiary z menu tylko pasujące do ekranu,
## zapisany za duży rozmiar zmniejszony z zachowaniem 16:9, pasek tytułu i dół okna w obszarze roboczym (nad paskiem zadań).
## Ekrany: 1366 × 768, 1920 × 1080 (100% i 125%), 1920 × 1200, 2560 × 1440, 3440 × 1440, 3840 × 2160 (pasek zadań na dole i u góry).
##   godot --headless --path prototype -s tools/test_window_fit.gd     → ostatni wiersz: PASS / FAIL

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[WINDOW] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var S = load("res://scripts/settings.gd")
	var deco := Vector2i(16, 46)                 # ramka Windows 11 (niewidoczne krawędzie do zmiany rozmiaru + pasek tytułu)
	var deco_tl := Vector2i(8, 38)
	# [nazwa, obszar roboczy ekranu (bez paska zadań)]
	var screens := [
		["1366x768", Rect2i(0, 0, 1366, 728)],
		["1920x1080", Rect2i(0, 0, 1920, 1032)],
		["1920x1080 125%", Rect2i(0, 0, 1920, 1020)],
		["1920x1200", Rect2i(0, 0, 1920, 1152)],
		["2560x1440", Rect2i(0, 0, 2560, 1392)],
		["3440x1440", Rect2i(0, 0, 3440, 1392)],
		["3840x2160", Rect2i(0, 0, 3840, 2100)],
		["3840x2160 pasek u góry", Rect2i(0, 60, 3840, 2100)],
		["drugi monitor 1920x1080 po lewej", Rect2i(-1920, 0, 1920, 1040)],
	]
	for sc in screens:
		var nm: String = sc[0]
		var usable: Rect2i = sc[1]
		var auto: Vector2i = S.auto_window_size(usable.size, deco)
		var outer := Rect2i(S.window_pos(auto, usable, deco, deco_tl) - deco_tl, auto + deco)
		_check("%s: okno startu %s w obszarze roboczym" % [nm, str(auto)], usable.encloses(outer))
		_check("%s: okno startu 16:9" % nm, auto.x * 9 == auto.y * 16)
		var fill := float(auto.y + deco.y) / float(usable.size.y)
		_check("%s: okno startu zajmuje 70–80%% wysokości (%.2f)" % [nm, fill], fill > 0.7 and fill <= 0.8 + 0.01)
		var cx := outer.position.x + outer.size.x / 2 - (usable.position.x + usable.size.x / 2)
		var cy := outer.position.y + outer.size.y / 2 - (usable.position.y + usable.size.y / 2)
		_check("%s: okno startu na środku (%d, %d)" % [nm, cx, cy], absi(cx) <= 1 and absi(cy) <= 1)
		var sizes: Array = S.fitting_sizes(usable.size, deco)
		var all_fit := not sizes.is_empty()
		for s in sizes:
			all_fit = all_fit and (s as Vector2i).x + deco.x <= usable.size.x and (s as Vector2i).y + deco.y <= usable.size.y
		_check("%s: rozmiary w menu %s mieszczą się" % [nm, str(sizes)], all_fit)
		for s in S.RES_LIST:
			var f: Vector2i = S.fit_window(s, usable.size, deco)
			var o := Rect2i(S.window_pos(f, usable, deco, deco_tl) - deco_tl, f + deco)
			var same: bool = f == s or not (s in sizes)
			_check("%s: zapisany %s → %s, 16:9, w obszarze roboczym" % [nm, str(s), str(f)], usable.encloses(o) and f.x * 9 == f.y * 16 and same)
	# konkretne wartości (opis w settings.gd i CHANGELOG)
	_check("4K: okno startu 2912 × 1638", S.auto_window_size(Vector2i(3840, 2100), deco) == Vector2i(2912, 1638))
	_check("1080p: okno startu 1392 × 783", S.auto_window_size(Vector2i(1920, 1032), deco) == Vector2i(1392, 783))
	_check("1366 × 768: okno startu 960 × 540", S.auto_window_size(Vector2i(1366, 728), deco) == Vector2i(960, 540))
	_check("4K: w menu jest 3200 × 1800, nie ma 3840 × 2160", S.fitting_sizes(Vector2i(3840, 2100), deco).has(Vector2i(3200, 1800)) and not S.fitting_sizes(Vector2i(3840, 2100), deco).has(Vector2i(3840, 2160)))
	_check("1080p: w menu najwyżej 1600 × 900", S.fitting_sizes(Vector2i(1920, 1032), deco).back() == Vector2i(1600, 900))
	_check("1366 × 768: 1280 × 720 nie mieści się → jedno dopasowane okno", S.fitting_sizes(Vector2i(1366, 728), deco) == [Vector2i(1200, 675)])
	_check("indeksy RES_LIST z dawnych zapisów bez zmian", S.RES_LIST.slice(0, 4) == [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)])
	print("PASS" if _fails == 0 else "FAIL (%d błędów)" % _fails)
	quit(0 if _fails == 0 else 1)
