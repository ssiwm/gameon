extends SceneTree
## Test konstrukcji widoku 3D (`Level3D.post_runs`) na wszystkich mapach z scripts/maps:
## (1) ciągłość: w kolumnie nie ma dwóch słupów przedzielonych jednym kaflem kładki albo znacznika (dziura pod pomostem, słup skrócony przez wroga),
## (2) podstawa: dolny koniec słupa stoi na bryle, kładce albo krawędzi mapy — nie wisi nad powietrzem, tłem ani znacznikiem,
## (3) styk: słup przy kładce dotyka tylnej krawędzi jej pokładu (wchodzi w nią najwyżej POST_BITE) i nie wychodzi przed nią, więc nie zasłania
##     postaci; pozostałe słupy stoją w głębi na POST_Z,
## (4) pnie: ciąg z gołym niebem nad sobą i bez kładki jest drzewem (martwe drzewo z modeli lasu zamiast słupa z okuciami); słup przy kładce — nigdy,
## (5) dachy z blachy: skrzynie stojące na dachu nie dzielą go na łaty (za skrzynią dach biegnie dalej), a szopa bez ścian ma podpory najwyżej
##     co ROOF_SPAN kafli, od końca do końca,
## (6) stopy ścian: ściana `C` nad otwartym parterem dostaje filar do gruntu,
## (7) wieże (`frame_role`): maszt to zawsze para sąsiednich kolumn od góry mapy, noga strażnicy nie jest jednocześnie pniem drzewa,
## (8) pomosty bez słupa, ściany i bryły obok (`deck_supports`): każda noga ma oparcie — grunt lub pomost niżej, albo strop nad pomostem.
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
	var trees := 0
	var thin := 0
	var roles := {"mast": [], "tower": []}
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
		var sky: bool = Level3D._ch(rows, c, r0 - 1) == "."
		_check(bool(run["tree"]) == (deck == "" and sky), "%s: pień rozpoznany źle (tree = %s, kładka „%s”, niebo nad = %s)" % [where, str(run["tree"]), deck, str(sky)])
		if bool(run["tree"]):
			trees += 1
		var role: String = Level3D.frame_role(rows, run)
		if role != "":
			(roles[role] as Array).append(c)
			_check(not bool(run["tree"]), "%s: %s i pień jednocześnie" % [where, role])
		if deck == "":
			_check(is_equal_approx(z, Level3D.POST_Z), "%s: słup bez kładki poza POST_Z (z = %.2f)" % [where, z])
			continue
		touching += 1
		if is_equal_approx(float(run["k"]), Level3D.POST_THIN):
			thin += 1
		var front := z + radius * float(run["k"])
		var back_edge: float = -Level3D.deck_half(deck)
		_check(front >= back_edge - 0.005, "%s: szczelina %.2f m między słupem a pokładem „%s”" % [where, back_edge - front, deck])
		_check(front <= back_edge + Level3D.POST_BITE + 0.005, "%s: słup wchodzi %.2f m w pokład „%s” (zasłania drogę postaci)" % [where, front - back_edge, deck])
	for c in by_col:
		var list: Array = by_col[c]
		for i in range(1, list.size()):
			var gap_r: int = list[i - 1]["r1"]
			if int(list[i]["r0"]) == gap_r + 1 and not Level3D.is_solid_ch(Level3D._ch(rows, c, gap_r)):      # przez bryłę (podłoga wieży) słup idzie ukryty
				_check(false, "%s kol. %d: słup przerwany w rzędzie %d („%s”)" % [id, c, gap_r, Level3D._ch(rows, c, gap_r)])
	for mc in roles["mast"]:
		_check((roles["mast"] as Array).has(int(mc) - 1) or (roles["mast"] as Array).has(int(mc) + 1), "%s kol. %d: maszt bez drugiej kolumny" % [id, mc])
	print("ok    %s: %d słupów, %d przy kładkach (%d cieńszych), %d pni drzew, maszt %s, nogi wieży %s" % [id, runs.size(), touching, thin, trees, str(roles["mast"]), str(roles["tower"])])
	_check_roofs(id, rows)
	_check_decks(id, rows)

func _check_roofs(id: String, rows: Array) -> void:
	var roofs: Array = Level3D.roof_runs(rows)
	var sheds := 0
	for run in roofs:
		var r: int = run["r"]
		var c0: int = run["c0"]
		var c1: int = run["c1"]
		var where := "%s dach rząd %d kol. %d–%d" % [id, r, c0, c1]
		for side in [c0 - 1, c1 + 1]:                           # dach nie urywa się na skrzyni: za nią nie ma dalszego dachu w tym rzędzie
			if Level3D._ch(rows, side, r) == "C" and Level3D._ch(rows, side, r - 1) == "M":
				_check(false, "%s: dach przerwany pod skrzynią w kol. %d" % [where, side])
		if bool(run["steel"]):
			continue
		sheds += 1
		var posts: Array = run["posts"]
		_check(not posts.is_empty(), "%s: szopa bez podpór" % where)
		if posts.is_empty():
			continue
		_check(int(posts[0]) - c0 < Level3D.ROOF_SPAN and c1 - int(posts[-1]) < Level3D.ROOF_SPAN, "%s: koniec szopy dalej niż %d kafli od podpory" % [where, Level3D.ROOF_SPAN])
		for i in range(1, posts.size()):
			_check(int(posts[i]) - int(posts[i - 1]) <= Level3D.ROOF_SPAN, "%s: %d kafli między podporami %d i %d" % [where, int(posts[i]) - int(posts[i - 1]), posts[i - 1], posts[i]])
	var feet: Array = Level3D.wall_feet(rows)
	for f in feet:
		_check(Level3D.is_solid_ch(Level3D._ch(rows, int(f["c"]), int(f["g"]))), "%s kol. %d: filar ściany nie stoi na gruncie" % [id, int(f["c"])])
	print("ok    %s: %d dachów z blachy (%d szop), %d filarów pod ścianami" % [id, roofs.size(), sheds, feet.size()])

func _check_decks(id: String, rows: Array) -> void:
	var list: Array = Level3D.deck_supports(rows)
	var stilts := 0
	var hangs := 0
	for d in list:
		for leg in d["legs"]:
			var kind: String = leg["kind"]
			_check(kind != "", "%s pomost rząd %d kol. %d–%d: noga w kol. %d bez oparcia" % [id, int(d["r"]), int(d["c0"]), int(d["c1"]), int(leg["c"])])
			if kind == "stilt":
				stilts += 1
				var to: String = Level3D._ch(rows, int(leg["c"]), int(leg["to"]))
				_check(Level3D.is_solid_ch(to) or Level3D.is_platform_ch(to), "%s kol. %d: noga pomostu nie stoi na gruncie ani pomoście" % [id, int(leg["c"])])
			elif kind == "hang":
				hangs += 1
	print("ok    %s: %d pomostów bez podpór dostało %d nóg i %d wieszaków" % [id, list.size(), stilts, hangs])
