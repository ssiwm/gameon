extends SceneTree
## Odcinki trasy 1.2 na grafie nav.gd gry (bez level.gd). Wejście: json {"rows": [...], "legs": [{"name", "a": [c, r], "b": [c, r], "closed": "|q%+", "solid": [[c0, r0, c1, r1]]}]}.
## Uruchomienie: godot --headless --path prototype -s res://tools/m2_route.gd -- <plik json>; zapisuje <plik>_route.json ze ścieżkami (MAPS_PLAN.md §4).
var _rows: Array = []
var _extra: Array = []
var _closed := ""

func _solid(c: int, r: int) -> bool:
	if r < 0 or r >= _rows.size() or c < 0 or c >= (_rows[0] as String).length():
		return true
	for q in _extra:
		if c >= q[0] and c <= q[2] and r >= q[1] and r <= q[3]:
			return true
	var ch: String = (_rows[r] as String)[c]
	if "#CM~misO".contains(ch):
		return true
	# przegroda sięga od znacznika w górę do stropu: szukamy znacznika w dół, dopóki kolumna jest wolna
	if _closed != "":
		var rr := r
		while rr < _rows.size():
			var cc: String = (_rows[rr] as String)[c]
			if _closed.contains(cc):
				return true
			if "#CM~misO=-".contains(cc):
				break
			rr += 1
	return false

func _plat(c: int, r: int) -> bool:
	if r < 0 or r >= _rows.size() or c < 0 or c >= (_rows[0] as String).length():
		return false
	return "=-".contains((_rows[r] as String)[c])

func _p(a: Array) -> Vector2:
	return Vector2(int(a[0]) * 16 + 8, (int(a[1]) + 1) * 16)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_rows = data["rows"]
	var Nav: GDScript = load("res://scripts/nav.gd")
	var out := {}
	var fails := 0
	var cache := {}
	for leg in data["legs"]:
		_closed = String(leg.get("closed", "|q%+"))
		_extra = leg.get("solid", [])
		var key := _closed + str(_extra)
		if not cache.has(key):
			var n = Nav.new()
			n.build((_rows[0] as String).length(), _rows.size(), _solid, _plat)
			cache[key] = n
		var nav = cache[key]
		var a := _p(leg["a"])
		var b := _p(leg["b"])
		var ia: int = nav.get_closest_point(a)
		var ib: int = nav.get_closest_point(b)
		var path: PackedVector2Array = nav.get_point_path(ia, ib)
		var d := 0.0
		var under := 0
		var pts: Array = []
		for k in range(path.size()):
			if k > 0:
				d += path[k].distance_to(path[k - 1])
			if path[k].y > 27 * 16:
				under += 1
			pts.append([path[k].x, path[k].y])
		var snap := maxf(nav.get_point_position(ia).distance_to(a), nav.get_point_position(ib).distance_to(b))
		var ok := path.size() > 0 and snap <= 24.0
		if ok == bool(leg.get("expect_fail", false)):
			fails += 1                    # droga, której ma nie być (expect_fail), też jest błędem
		print("%-58s %6.0f px %5.1f s  pod ziemią %3.0f%%  ok=%s%s" % [leg["name"], d, d / 95.0, 100.0 * under / maxf(1.0, path.size()), str(ok), "  (oczekiwany brak drogi)" if leg.get("expect_fail", false) else ""])
		out[leg["name"]] = {"px": d, "ok": ok, "path": pts}
	var fo := FileAccess.open(String(args[0]).replace(".json", "_route.json"), FileAccess.WRITE)
	fo.store_string(JSON.stringify(out))
	fo.close()
	print("błędów: %d -> %s" % [fails, "PASS" if fails == 0 else "FAIL"])
	quit()
