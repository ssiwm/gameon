extends SceneTree
## Test pomostów z natury (`scripts/step3d.gd`, STEPS_PLAN.md) na wszystkich mapach z wpisem STEPS:
## (1) dane: rodzaj z `Step3D.KINDS`, każdy pomost wpisu istnieje (początek ciągu `-` / `=` w podanym miejscu), kolumny "posts" mają słup `w`
##     pod pomostem, konary mają sosnę w zasięgu (słup `w` ≥ BOUGH_RUN kafli albo "trunks" na bryle);
## (2) wolny pas: żaden element nie wchodzi w pas gry (|z| < STRIP) od poziomu chodzenia (wierzch bryły albo pomostu) do CLEAR nad nim;
## (3) wierzch: nad każdym kaflem pomostu wpisu jest element w pasie gry z wierzchem na wysokości pokładu (−6 cm … +TOP_TOL);
##     w 1.2 czoło pokładu pokrywa się z punktem chwytu dłoni;
## (4) Level3D: pomosty wpisów bez nóg (`deck_supports`) i bez modelu desek, ukryte słupy i sosny w miejscu słupów konarów.
## godot --headless --path prototype -s tools/test_steps.gd      → ma wypisać PASS
const Level3D := preload("res://scripts/level3d.gd")
const Step3D := preload("res://scripts/step3d.gd")
const Char3D := preload("res://scripts/char3d.gd")
const T := Level3D.T
var _frames := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL  " + msg)
		_fail += 1

## Poziomy chodzenia w kolumnie `c`: y wierzchu kafli bryły i pomostów z powietrzem nad sobą. Bez wierzchu pod oknem `|` (rama zatrzymuje
## ruch) i bez ciasnych wnęk z pomostem tuż nad wierzchem (skrzynia `M` o kafel pod pomostem — nikt tam nie stoi wyprostowany).
func _levels(rows: Array, c: int) -> Array:
	var out: Array = []
	for r in rows.size():
		var ch := Level3D._ch(rows, c, r)
		var up := Level3D._ch(rows, c, r - 1)
		if (Level3D.is_solid_ch(ch) or Level3D.is_platform_ch(ch)) and not Level3D.is_solid_ch(up) and up != "|" and not Level3D.is_platform_ch(up):
			out.append(-float(r) * T)
	return out

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var dir := DirAccess.open("res://scripts/maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	var total := 0
	for f in names:
		var consts := (load("res://scripts/maps/" + f) as GDScript).get_script_constant_map()
		var steps: Array = consts.get("STEPS", [])
		if steps.is_empty():
			continue
		var rows: Array = consts.get("MAP", [])
		var map := String(f).get_basename()
		total += steps.size()
		# (1) dane
		for e in steps:
			var kind := String(e.get("kind", ""))
			_check(Step3D.KINDS.has(kind), "%s: nieznany rodzaj %s" % [map, kind])
			for d in e.get("decks", []):
				_check(not Step3D.deck_at(rows, int(d[0]), int(d[1])).is_empty(), "%s: brak początku pomostu w %s" % [map, str(d)])
			var ds := Step3D.decks_of(rows, e)
			for c in e.get("posts", []):
				var found := false
				for d in ds:
					for r in range(int(d["r"]) + 1, int(d["r"]) + 10):
						found = found or Level3D._ch(rows, int(c), r) == "w"
				_check(found, "%s: kolumna posts %d bez słupa `w` pod pomostem" % [map, int(c)])
			if kind == "boughs":
				_check(not Step3D.bough_trunks(rows, e).is_empty(), "%s: konary bez sosny ze słupa" % map)
				for t in e.get("trunks", []):
					_check(Level3D.is_solid_ch(Level3D._ch(rows, int(t[0]), int(t[1]))), "%s: sosna %s nie stoi na bryle" % [map, str(t)])
		# (2) i (3): bryły z ostatniego `build`
		var holder := Node3D.new()
		get_root().add_child(holder)
		Step3D.build(holder, rows, steps)
		_check(not Step3D.parts.is_empty(), "%s: brak elementów" % map)
		var checked := 0
		for p in Step3D.parts:
			var bb: AABB = p[0]
			if bb.position.z >= Step3D.STRIP or bb.end.z <= -Step3D.STRIP:
				continue
			checked += 1
			for c in range(int(floor(bb.position.x / T)), int(floor((bb.end.x - 0.001) / T)) + 1):
				for y in _levels(rows, c):
					var lo: float = y + Step3D.TOP_TOL
					var hi: float = y + Step3D.CLEAR
					if bb.position.y < hi and bb.end.y > lo:
						_check(false, "%s: %s w pasie gry nad poziomem %.2f m w kolumnie %d (y %.2f…%.2f, z %.2f…%.2f)" % [map, String(p[1]), y, c,
							bb.position.y, bb.end.y, bb.position.z, bb.end.z])
		_check(checked > 0, "%s: żaden element nie niesie pomostu w pasie gry" % map)
		var check_edge := map == "z1_m2"
		for e in steps:
			for d in Step3D.decks_of(rows, e):
				var top: float = d["top"]
				for c in range(int(d["c0"]), int(d["c1"]) + 1):
					var x := (float(c) + 0.5) * T
					var ok := false
					var edge_z := -INF
					for p in Step3D.parts:
						var bb: AABB = p[0]
						if bb.position.x > x or bb.end.x < x:
							continue
						if check_edge and absf(bb.end.y - top) <= 0.01:
							edge_z = maxf(edge_z, bb.end.z)
						if bb.position.z < 0.2 and bb.end.z > -0.2 \
								and bb.end.y >= top - 0.06 and bb.end.y <= top + Step3D.TOP_TOL:
							ok = true
							if not check_edge:
								break
					_check(ok, "%s: kafel %d,%d pomostu %s bez wierzchu na wysokości pokładu" % [map, int(d["r"]), c, String(e["kind"])])
					if check_edge:
						_check(is_equal_approx(edge_z, Char3D.MANTLE_EDGE_Z), "%s: kafel %d,%d ma krawędź z = %.3f m, chwyt z = %.3f m" % [
							map, int(d["r"]), c, edge_z, Char3D.MANTLE_EDGE_Z])
		holder.queue_free()
		# (4) Level3D
		var cells := Step3D.cells(rows, steps)
		Level3D.set_steps(cells, Step3D.hidden_posts(rows, steps), Step3D.trunk_cells(rows, steps))
		for d in Level3D.deck_supports(rows):
			_check(not cells.has(Vector2i(int(d["c0"]), int(d["r"]))), "%s: pomost %d,%d wpisu ma nogi" % [map, int(d["r"]), int(d["c0"])])
		for e in steps:
			if not (e.get("posts", []) as Array).is_empty():
				var hid := 0
				for k in Step3D.hidden_posts(rows, [e]):
					hid += 1
				_check(hid >= (e["posts"] as Array).size(), "%s: nie wszystkie słupy posts ukryte (%d)" % [map, hid])
		var lv := Node3D.new()
		get_root().add_child(lv)
		Level3D.build_level(lv, rows)
		var deck_x: Array = []
		for mmi in lv.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var wp := Level3D.model_mesh("walkway_plank")
			if not wp.is_empty() and mm.mesh == wp[0]:
				for i in mm.instance_count:
					deck_x.append(mm.get_instance_transform(i).origin)
		for v in deck_x:
			var cell := Vector2i(int(floor((v as Vector3).x / T)), int(round(-((v as Vector3).y - 0.01) / T)))
			_check(not cells.has(cell), "%s: model desek na pomoście wpisu %s" % [map, str(cell)])
		lv.queue_free()
		Level3D.set_steps({}, {}, {})
	_check(total > 0, "żadna mapa nie ma STEPS")
	print("[STEPS] wpisów %d" % total)
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true
