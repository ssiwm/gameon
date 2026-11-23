extends SceneTree
## Test strażnicy 1.1 (TOWER_PLAN.md, `watchtower3d.gd`) na każdej mapie z `WATCHTOWER`:
## (1) dane: nogi w kolumnach c0 i c1 to ciągi `w` od podłogi kabiny do gruntu, dach i podłoga to `M` (właz `-`), pod nogami grunt,
## (2) nogi sięgają pod grunt i stoją na betonowych stopach, górą do dachu,
## (3) pod każdym podestem zygzaka są legary górą pod deskami, a między kolejnymi podestami (i od gruntu) drabina,
## (4) drabiny i poręcze podestów stoją za płaszczyzną gry (z ≤ −0,05),
## (5) przed płaszczyzną gry nic szerokiego (> 0,5 m w x) nie wchodzi w pas postaci (0,3–1,85 m nad gruntem, podestem albo podłogą kabiny),
## (6) belki stropu górą na spodzie kafla dachu (tam wiszą Ćmy i Skoczek), dach od tej wysokości w górę, kalenica wyżej,
## (7) stara geometria wieży (`tower_slabs`, nogi `frame_role` „tower”, nogi podestów `deck_supports`) leży cała w prostokącie `rect`,
##     który `Level3D.tower_skip` pomija — bez podwójnych dachów i nóg.
## godot --headless --path prototype -s tools/test_watchtower.gd      → ma wypisać [WATCHTOWER] PASS
var _frames := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	print(("ok    " if ok else "FAIL  ") + msg)
	if not ok:
		_fail += 1

## AABB pudła 1×1×1 po przekształceniu: [min, max].
static func _aabb(xf: Transform3D) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in 8:
		var p := xf * Vector3(-0.5 if i & 1 == 0 else 0.5, -0.5 if i & 2 == 0 else 0.5, -0.5 if i & 4 == 0 else 0.5)
		lo = lo.min(p)
		hi = hi.max(p)
	return [lo, hi]

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var L3: GDScript = load("res://scripts/level3d.gd")
	var W3: GDScript = load("res://scripts/watchtower3d.gd")
	var T: float = L3.T
	var dir := DirAccess.open("res://scripts/maps")
	var seen := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var m: GDScript = load("res://scripts/maps/" + f)
		var consts := m.get_script_constant_map()
		var d: Dictionary = consts.get("WATCHTOWER", {})
		if d.is_empty():
			continue
		seen += 1
		var rows: Array = consts["MAP"]
		var id := String(consts.get("ID", f))
		var c0: int = d["c0"]
		var c1: int = d["c1"]
		var rr: int = d["roof"]
		var rf: int = d["floor"]
		var rg: int = d["ground"]
		# (1) dane
		var data_ok := true
		for c in [c0, c1]:
			for r in range(rf + 1, rg):
				data_ok = data_ok and String(rows[r])[c] == "w"
			data_ok = data_ok and String(rows[rg])[c] == "#"
		for c in range(c0, c1 + 1):
			data_ok = data_ok and String(rows[rr])[c] == "M" and String(rows[rf])[c] in ["M", "-"]
		_check(data_ok, "%s: dane WATCHTOWER — nogi `w` w kol. %d i %d (w. %d–%d), dach `M` w. %d, podłoga `M`/`-` w. %d, grunt w. %d" % [id, c0, c1, rf + 1, rg - 1, rr, rf, rg])
		var p: Dictionary = W3.parts(rows, d)
		var lv: Dictionary = W3.levels_of(d)
		var y_g: float = lv["ground"]
		var y_f: float = lv["floor"]
		var y_c: float = lv["ceil"]
		# (2) nogi i stopy
		var legs: Array = (p["legs"] as Array).map(func(x: Transform3D) -> Array: return _aabb(x))
		var low := legs.filter(func(b: Array) -> bool: return (b[0] as Vector3).y < y_g)
		var tops := legs.filter(func(b: Array) -> bool: return (b[1] as Vector3).y >= y_c)
		var feet_ok := low.size() == 4
		for b in low:
			var foot := (p["footings"] as Array).any(func(x: Transform3D) -> bool:
				var fb := _aabb(x)
				return absf(((fb[0] + fb[1]) * 0.5).x - ((b[0] + b[1]) * 0.5).x) < 0.6 and (fb[1] as Vector3).y > y_g)
			feet_ok = feet_ok and foot
		_check(feet_ok and tops.size() == 4, "%s: 4 nogi pod grunt na stopach (%d) i 4 do belek stropu (%d)" % [id, low.size(), tops.size()])
		# (3) legary i drabiny
		var lands: Array = W3.landings(rows, d)
		var deck_h: float = float(L3.DECK_H["-"]) * T
		var joist_ok := lands.size() >= 2
		for l in lands:
			var y_un := -float(int(l["r"])) * T - deck_h
			var x0 := float(int(l["c0"])) * T
			var x1 := float(int(l["c1"]) + 1) * T
			var n := (p["joists"] as Array).filter(func(x: Transform3D) -> bool:
				var b := _aabb(x)
				return absf((b[1] as Vector3).y - y_un) < 0.02 and (b[0] as Vector3).x >= x0 - 0.01 and (b[1] as Vector3).x <= x1 + 0.01).size()
			joist_ok = joist_ok and n >= 3
		var rungs := (p["ladders"] as Array).size()
		_check(joist_ok and rungs > lands.size() * 8, "%s: %d podestów, każdy na ≥ 3 legarach pod deskami; drabiny: %d elementów" % [id, lands.size(), rungs])
		# (4) za płaszczyzną gry
		var behind := true
		for k in ["ladders", "rails"]:
			for x in p[k]:
				behind = behind and (_aabb(x)[1] as Vector3).z <= -0.05
		_check(behind, "%s: drabiny i poręcze podestów za płaszczyzną gry (z ≤ −0,05)" % id)
		# (5) pas postaci przed płaszczyzną gry
		var surfs: Array = [[y_g, float(c0 - 2) * T, float(c1 + 3) * T], [y_f, float(c0) * T, float(c1 + 1) * T]]
		for l in lands:
			surfs.append([-float(int(l["r"])) * T, float(int(l["c0"])) * T, float(int(l["c1"]) + 1) * T])
		var bad: Array = []
		for k in p:
			if k in ["roof", "legs", "footings"]:
				continue                                         # nogi są wąskie (szerokość w x z samego rozstawu u dołu)
			for x in p[k]:
				var b := _aabb(x)
				var lo: Vector3 = b[0]
				var hi: Vector3 = b[1]
				if hi.z <= 0.05 or hi.x - lo.x <= 0.5:
					continue
				for s in surfs:
					var y0: float = float(s[0]) + 0.3
					var y1: float = float(s[0]) + 1.85
					if hi.x > float(s[1]) and lo.x < float(s[2]) and hi.y > y0 and lo.y < y1:
						bad.append("%s y %.2f–%.2f nad %.2f" % [k, lo.y, hi.y, float(s[0])])
		_check(bad.is_empty(), "%s: przed płaszczyzną gry nic szerokiego w pasie postaci %s" % [id, str(bad.slice(0, 4))])
		# (6) strop i dach
		var beams_ok := not (p["beams"] as Array).is_empty() and (p["beams"] as Array).all(func(x: Transform3D) -> bool: return absf((_aabb(x)[1] as Vector3).y - y_c) < 0.01)
		var roof: Array = p["roof"]
		_check(beams_ok and absf((roof[0] as Vector3).y - y_c) < 0.01 and float(roof[2]) > y_c + 0.5,
			"%s: belki stropu górą na spodzie kafla dachu (y %.2f), okap tam, kalenica %.2f m wyżej" % [id, y_c, float(roof[2]) - y_c])
		# (7) stara geometria w prostokącie pomijania
		var rect: Rect2i = W3.rect(d)
		var old_ok := true
		var n_old := 0
		for s in L3.tower_slabs(rows):
			n_old += 1
			old_ok = old_ok and rect.has_point(Vector2i(int(s["c0"]), int(s["r"]))) and rect.has_point(Vector2i(int(s["c1"]), int(s["r"])))
		for run in L3.post_runs(rows):
			if L3.frame_role(rows, run) == "tower":
				n_old += 1
				old_ok = old_ok and rect.has_point(Vector2i(int(run["c"]), int(run["r0"])))
		for ds in L3.deck_supports(rows):
			if int(ds["c0"]) >= c0 and int(ds["c1"]) <= c1 and int(ds["r"]) > rr and int(ds["r"]) < rg:
				n_old += 1
				old_ok = old_ok and rect.has_point(Vector2i(int(ds["c0"]), int(ds["r"])))
		_check(old_ok and n_old > 0, "%s: stara geometria wieży (%d elementów) w prostokącie pomijania %s" % [id, n_old, str(rect)])
	_check(seen >= 1, "mapy z WATCHTOWER: %d" % seen)
	print("[WATCHTOWER] " + ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)
	return true
