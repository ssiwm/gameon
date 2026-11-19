extends SceneTree
## Test wnęk w tylnej ścianie wnętrz (`scripts/niches3d.gd`, `DEPTH_PLAN.md`) na wszystkich mapach z scripts/maps:
## (1) dane: otwór leży na samym tle `b` z podłogą pod spodem (okno i kratka z N4: z murem tła pod spodem; przypadki na sztucznej mapie) (bez okien, lamp, stempli, zawału i znaczników), poza strefami wydobycia,
## (2) światło: tylko na warstwę wnęk (`LAYER_NICHE`), bez cienia i bez mgły wolumetrycznej, zasięg kończy się przed ścianą tła; na LOW świateł nie ma,
##     a od MEDIUM ma je każda wnęka z „lit” i żadna bez (wszystkie rodzaje z `Niches3D.KINDS`),
## (3) bryła wnęki jest na warstwie świata i wnęk (oświetlają ją światła mapy i wnęki),
## (4) płyty ściany tła: w otworze ich nie ma, poza nim są te same co bez wnęki,
## (5) las: żadne drzewo nie stoi w korytarzu wnęki (z zapasem `TREE_MARGIN`),
## (6) jaskinie (`scripts/cave3d.gd`, stała `CAVES`): bryła w warstwie świata z cieniem, materiał skały z drugą skalą tekstury (jak płyta), nie wychodzi przed tło gry, obrys lasu obejmuje wychodnię, prostokąty skały w mapie, wnętrze zasłonięte od nieba (AO z alfy koloru) przy pełnym niebie wierzchu, skalne dno nad gruntem.
## godot --headless --path prototype -s tools/test_niches.gd      → ma wypisać PASS
const Level3D := preload("res://scripts/level3d.gd")
const Niches3D := preload("res://scripts/niches3d.gd")
const Cave3D := preload("res://scripts/cave3d.gd")
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
	var dir := DirAccess.open("res://scripts/maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	var total := 0
	var caves := 0
	for f in names:
		var consts := (load("res://scripts/maps/" + f) as GDScript).get_script_constant_map()
		caves += _check_caves(f.get_basename(), consts.get("MAP", []), consts.get("CAVES", []))
		var entries: Array = consts.get("NICHES", [])
		if entries.is_empty():
			continue
		total += entries.size()
		_check_map(f.get_basename(), consts.get("MAP", []), entries, consts.get("DIG_ZONES", []))
	_check(total > 0, "żadna mapa nie ma wnęki (pilot na z1_m2)")
	_check(caves > 0, "żadna mapa nie ma jaskini (pilot na z1_m1)")
	_check_wall_kinds()
	Level3D.set_niches({}, [])
	print("wnęk: %d" % total)
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true

## Rodzaje ścienne (N4) na sztucznej mapie: okno i kratka wiszą w murze tła (pod spodem `b`, nie podłoga), kratka mieści się w jednym kaflu,
## okno potrzebuje wokół muru albo litego kafla (pokój za nim jest większy od otworu; powietrze i kładka odpadają), a zwykła wnęka
## dalej wymaga podłogi i otworu 2 × 2.
func _check_wall_kinds() -> void:
	var rows := ["##########", "#bbbbbbbb#", "#bbbbbbbb#", "#bbbbbbbb#", "#bbbbbbbb#", "#bbbbbbbb#", "##########"]
	var ok := func(e: Dictionary) -> bool: return Niches3D.validate(rows, [e]).is_empty()
	_check(ok.call({"kind": "window", "c0": 3, "c1": 5, "r0": 2, "r1": 3, "lit": "tube"}), "N4: okno w murze tła odrzucone")
	_check(not ok.call({"kind": "window", "c0": 3, "c1": 5, "r0": 4, "r1": 5, "lit": "tube"}), "N4: okno nad podłogą przyjęte (to rodzaj ścienny)")
	_check(ok.call({"kind": "window", "c0": 1, "c1": 3, "r0": 1, "r1": 2, "lit": "tube"}), "N4: okno pod stropem i przy skale odrzucone (lity kafel zasłania pokój)")
	var open := rows.duplicate()
	open[1] = ".bbbbbbbb#"
	open[2] = ".bbbbbbbb#"
	open[3] = ".bbbbbbbb#"
	_check(not Niches3D.validate(open, [{"kind": "window", "c0": 1, "c1": 3, "r0": 2, "r1": 3, "lit": "tube"}]).is_empty(), "N4: okno przy otwartym powietrzu przyjęte (pokój wyjdzie zza muru)")
	var deck := rows.duplicate()
	deck[1] = "#b====bbb#"
	_check(not Niches3D.validate(deck, [{"kind": "window", "c0": 3, "c1": 5, "r0": 2, "r1": 3, "lit": "tube"}]).is_empty(), "N4: okno pod kładką przyjęte")
	_check(not ok.call({"kind": "window", "c0": 3, "c1": 5, "r0": 2, "r1": 2, "lit": "tube"}), "N4: okno niższe niż 2 kafle przyjęte")
	_check(ok.call({"kind": "vent", "c0": 4, "c1": 4, "r0": 2, "r1": 2, "lit": "lamp"}), "N4: kratka w jednym kaflu odrzucona")
	_check(not ok.call({"kind": "vent", "c0": 4, "c1": 4, "r0": 2, "r1": 2, "lit": "bulb"}), "N4: kratka ze światłem „bulb” przyjęta")
	_check(not ok.call({"kind": "doorway", "c0": 3, "c1": 5, "r0": 2, "r1": 3, "lit": "bulb"}), "N4: zaplecze bez podłogi przyjęte")
	_check(ok.call({"kind": "doorway", "c0": 3, "c1": 5, "r0": 4, "r1": 5, "lit": "bulb"}), "N4: zaplecze na podłodze odrzucone")

func _check_map(id: String, rows: Array, entries: Array, dig: Array) -> void:
	for e in Niches3D.validate(rows, entries, dig):
		_check(false, "%s: %s" % [id, e])
	var cells := Niches3D.cells(entries)
	var holes := Niches3D.forest_holes(entries)
	# (2), (3) światła i warstwy na HIGH i na LOW
	for q in [2, 0]:
		var root := Node3D.new()
		Niches3D.build(root, rows, entries, q)
		var lights := root.find_children("*", "Light3D", true, false)
		if q == 0:
			_check(lights.is_empty(), "%s: na LOW są światła wnęk (%d)" % [id, lights.size()])
		else:
			for i in entries.size():
				var lit := String((entries[i] as Dictionary).get("lit", ""))
				var nl := root.get_node("Niche%d" % i).find_children("*", "Light3D", true, false).size()
				_check((nl > 0) == (lit != ""), "%s: wnęka %d (%s, światło „%s”) ma %d świateł" % [id, i, (entries[i] as Dictionary).get("kind", ""), lit, nl])
		for l in lights:
			var o := l as OmniLight3D
			_check(o != null, "%s: światło wnęki inne niż OmniLight3D" % id)
			if o == null:
				continue
			_check(o.light_cull_mask == Niches3D.LAYER_NICHE, "%s: maska światła %d zamiast samej warstwy wnęk" % [id, o.light_cull_mask])
			_check(not o.shadow_enabled, "%s: światło wnęki rzuca cień (decyzja 3: dopiero po pomiarze)" % id)
			_check(is_zero_approx(o.light_volumetric_fog_energy), "%s: światło wnęki świeci w mgle wolumetrycznej" % id)
			var reach := o.position.z + o.omni_range
			_check(reach <= Niches3D.WALL_Z - Niches3D.LIGHT_EDGE + 0.001, "%s: światło sięga z = %.2f, przed ścianę tła (%.2f)" % [id, reach, Niches3D.WALL_Z])
		for g in root.find_children("*", "GeometryInstance3D", true, false):
			var layers := (g as VisualInstance3D).layers
			_check(layers & 1 != 0 and layers & Niches3D.LAYER_NICHE != 0, "%s: %s na warstwach %d (ma być świat + wnęki)" % [id, g.name, layers])
		root.free()
	# (4) płyty ściany tła z wnęką i bez niej (ta sama funkcja, której używa `build_level`)
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	Level3D.set_niches({}, [])
	var plain := {}
	for r in nrows:
		for c in cols:
			if Level3D.back_wall_at(rows, c, r):
				plain[Vector2i(c, r)] = true
	Level3D.set_niches(cells, holes)
	var cut := 0
	var missing := 0
	for r in nrows:
		for c in cols:
			var k := Vector2i(c, r)
			var has := Level3D.back_wall_at(rows, c, r)
			if has:
				cut += 1
			if cells.has(k):
				_check(not has, "%s: płyta ściany tła w otworze wnęki %s" % [id, k])
				_check(plain.has(k), "%s: otwór %s leży tam, gdzie nie było ściany tła" % [id, k])
			elif plain.has(k) != has:
				missing += 1
	_check(missing == 0, "%s: poza otworem zmieniło się %d płyt ściany" % [id, missing])
	# (5) las bez drzew w korytarzu (podstawy drzew z `forest_probe`; bez wnęki ile drzew stałoby w środku — dla porządku)
	Level3D.forest_probe = true
	Level3D.set_niches({}, [])
	var fr := Node3D.new()
	Level3D.build_forest(fr, rows)
	fr.free()
	var before := 0                                  # każde drzewo raz — korytarze sąsiednich wnęk z zapasem `TREE_MARGIN` nachodzą na siebie
	for o in Level3D.forest_origins:
		for h in holes:
			if o.x >= float(h[0]) and o.x <= float(h[1]) and o.z <= float(h[2]) and o.z >= float(h[3]):
				before += 1
				break
	var all_before := Level3D.forest_origins.size()
	Level3D.set_niches(cells, holes)
	fr = Node3D.new()
	Level3D.build_forest(fr, rows)
	fr.free()
	var inside := 0
	for o in Level3D.forest_origins:
		if Level3D.in_niche_hole(o.x, o.z):
			inside += 1
	_check(inside == 0, "%s: %d drzew w korytarzu wnęki" % [id, inside])
	_check(Level3D.forest_origins.size() == all_before - before, "%s: filtr wnęk zmienił las poza korytarzem (%d → %d, w korytarzu %d)" % [id, all_before, Level3D.forest_origins.size(), before])
	Level3D.forest_probe = false
	Level3D.set_niches({}, [])
	print("%s: wnęk %d, kafli otworów %d, płyt ściany %d → %d, drzew w korytarzu bez filtra %d (las %d)" % [id, entries.size(), cells.size(), plain.size(), cut, before, all_before])

## Jaskinia: bryła z `Cave3D.build` w warstwie świata, rzuca cień, cała za tłem gry (z ≤ −DEPTH_BACK), w poziomie w obrysie lasu,
## dół zboczy przy gruncie wpisu; prostokąt skały leży na mapie i jest w nim lity kafel.
func _check_caves(id: String, rows: Array, caves: Array) -> int:
	if caves.is_empty():
		return 0
	var rm := Level3D.rock_material() as ShaderMaterial          # kafel 2,5 m na nawisie 57 m robił kratkę plam: druga skala tekstury w shaderze
	_check(rm != null and rm.get_shader_parameter("alb") != null and rm.shader != null and "scale_b" in rm.shader.code, "%s: materiał skały bez drugiej skali tekstury" % id)
	var root := Node3D.new()
	_check(Cave3D.build(root, caves) == caves.size(), "%s: zbudowano inną liczbę jaskiń niż w CAVES" % id)
	var holes := Cave3D.forest_holes(caves)
	var rects := Cave3D.rock_rects(caves)
	for i in caves.size():
		var mi := root.get_node_or_null("Cave%d" % i) as MeshInstance3D
		_check(mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0, "%s: jaskinia %d bez bryły" % [id, i])
		if mi == null or mi.mesh == null:
			continue
		_check(mi.layers == 1, "%s: jaskinia %d na warstwach %d (ma być sam świat)" % [id, i, mi.layers])
		_check(mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: jaskinia %d nie rzuca cienia" % [id, i])
		_check(mi.material_override == Level3D.rock_material(), "%s: jaskinia %d ma inny materiał niż płyta skały" % [id, i])
		var bb := mi.mesh.get_aabb()
		_check(bb.end.z <= -Level3D.DEPTH_BACK + 0.001, "%s: jaskinia %d wychodzi przed tło gry (z = %.2f)" % [id, i, bb.end.z])
		var h: Array = holes[i]
		_check(bb.position.x >= float(h[0]) and bb.end.x <= float(h[1]), "%s: jaskinia %d poza obrysem lasu w x (%.1f–%.1f)" % [id, i, bb.position.x, bb.end.x])
		var yg := -float((caves[i] as Dictionary)["floor"]) * Level3D.T
		_check(bb.position.y <= yg and bb.position.y >= yg - Cave3D.SINK - Cave3D.AMP - 0.5, "%s: dół jaskini %d na y = %.2f, grunt %.2f" % [id, i, bb.position.y, yg])
		# wnętrze: zasłonięte od nieba (alfa koloru → AO shadera), skalne dno nad gruntem; z zewnątrz pełne niebo
		var occ_sum := 0.0
		var occ_n := 0
		var occ_out := 1.0
		var floor_low := INF
		var zd := -Level3D.DEPTH_BACK - float((caves[i] as Dictionary).get("d", Cave3D.DEPTH))
		var x0 := float((caves[i] as Dictionary)["c0"]) * Level3D.T + Cave3D.SIDE_W
		var x1 := float(int((caves[i] as Dictionary)["c1"]) + 1) * Level3D.T - Cave3D.SIDE_W
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for vi in vs.size():
				var v := vs[vi]
				var a := cs[vi].a
				if v.z < zd + 0.3 and v.x > x0 and v.x < x1:      # środek tylnej ściany (bez rogów przy stropie i bokach)
					occ_sum += a
					occ_n += 1
				if v.y > -float((caves[i] as Dictionary)["r0"]) * Level3D.T - 0.01:
					occ_out = minf(occ_out, a)
				if ns[vi].y > 0.7 and v.z < -Level3D.DEPTH_BACK - 1.0 and v.z > zd + 1.0 and v.x > x0 and v.x < x1 and v.y < yg + 1.0:
					floor_low = minf(floor_low, v.y)
		var occ_avg := occ_sum / maxf(1.0, float(occ_n))
		_check(occ_n > 0 and occ_avg < 0.6, "%s: tylna ściana jaskini %d niezasłonięta od nieba (AO %.2f) — wnętrze jasne jak zbocze" % [id, i, occ_avg])
		_check(occ_out > 0.99, "%s: wierzch jaskini %d przyciemniony jak wnętrze (AO %.2f)" % [id, i, occ_out])
		_check(floor_low > yg, "%s: dno jaskini %d pod gruntem (y = %.2f, grunt %.2f) — las przebija plamami" % [id, i, floor_low, yg])
		var r: Array = rects[i]
		var solid := 0
		for row in range(int(r[1]), int(r[3]) + 1):
			_check(row < rows.size() and int(r[2]) < String(rows[row]).length(), "%s: prostokąt skały %d poza mapą" % [id, i])
			if row < rows.size():
				for c in range(int(r[0]), mini(int(r[2]) + 1, String(rows[row]).length())):
					solid += 1 if String(rows[row])[c] == "#" else 0
		_check(solid > 0, "%s: w prostokącie skały %d nie ma litego kafla" % [id, i])
	root.free()
	return caves.size()
