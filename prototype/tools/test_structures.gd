extends SceneTree
## Test konstrukcji widoku 3D (`Level3D.post_runs`) na wszystkich mapach z scripts/maps:
## (1) ciągłość: w kolumnie nie ma dwóch słupów przedzielonych jednym kaflem kładki albo znacznika (dziura pod pomostem, słup skrócony przez wroga),
## (2) podstawa: dolny koniec słupa stoi na bryle, kładce albo krawędzi mapy — nie wisi nad powietrzem, tłem ani znacznikiem,
## (3) styk: słup przy kładce dotyka tylnej krawędzi jej pokładu (wchodzi w nią najwyżej POST_BITE) i nie wychodzi przed nią, więc nie zasłania
##     postaci; pozostałe słupy stoją w głębi na POST_Z.
## godot --headless --path prototype -s tools/test_structures.gd      → ma wypisać PASS
var Level3D: GDScript
var _frames := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL  " + msg)
		_fail += 1

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	Level3D = load("res://scripts/level3d.gd")
	var radius: float = Level3D.post_radius()
	print("promień słupa %.3f m, pół głębokości pokładu: deski %.3f m, krata %.3f m" % [radius, Level3D.deck_half("-"), Level3D.deck_half("=")])
	var dir := DirAccess.open("res://scripts/maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	for f in names:
		var rows: Array = (load("res://scripts/maps/" + f) as GDScript).get_script_constant_map().get("MAP", [])
		_check_map(f.get_basename(), rows, radius)
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true

func _check_map(id: String, rows: Array, radius: float) -> void:
	var runs: Array = Level3D.post_runs(rows)
	var by_col := {}
	var touching := 0
	for run in runs:
		var c: int = run["c"]
		var r0: int = run["r0"]
		var r1: int = run["r1"]
		var z: float = run["z"]
		var where := "%s kol. %d rzędy %d–%d" % [id, c, r0, r1 - 1]
		if not by_col.has(c):
			by_col[c] = []
		(by_col[c] as Array).append(run)
		var below: String = Level3D._ch(rows, c, r1)
		_check(Level3D.is_solid_ch(below) or Level3D.is_platform_ch(below), "%s: słup wisi nad „%s”" % [where, below])
		var deck: String = run["deck"]
		if deck == "":
			_check(is_equal_approx(z, Level3D.POST_Z), "%s: słup bez kładki poza POST_Z (z = %.2f)" % [where, z])
			continue
		touching += 1
		var front := z + radius
		var back_edge: float = -Level3D.deck_half(deck)
		_check(front >= back_edge - 0.005, "%s: szczelina %.2f m między słupem a pokładem „%s”" % [where, back_edge - front, deck])
		_check(front <= back_edge + Level3D.POST_BITE + 0.005, "%s: słup wchodzi %.2f m w pokład „%s” (zasłania drogę postaci)" % [where, front - back_edge, deck])
	for c in by_col:
		var list: Array = by_col[c]
		for i in range(1, list.size()):
			var gap_r: int = list[i - 1]["r1"]
			if int(list[i]["r0"]) == gap_r + 1 and not Level3D.is_solid_ch(Level3D._ch(rows, c, gap_r)):      # przez bryłę (podłoga wieży) słup idzie ukryty
				_check(false, "%s kol. %d: słup przerwany w rzędzie %d („%s”)" % [id, c, gap_r, Level3D._ch(rows, c, gap_r)])
	print("ok    %s: %d słupów, %d przy kładkach" % [id, runs.size(), touching])
