extends RefCounted
## Wnęki w tylnej ścianie wnętrz widoku 3D (`DEPTH_PLAN.md`): otwór w ścianie tła (z = −DEPTH_BACK) z korytarzem w głąb i własnym światłem.
## Czysta oprawa: bez kolizji, bez wpływu na wzrok wrogów, hałas i Uwagę; mapa ASCII i nawigacja się nie zmieniają.
## Światło wnęki świeci tylko na jej bryłę (`LAYER_NICHE`, wzór jak `MoonRim` na `Level3D.LAYER_FOREST`), nie oświetla mgły wolumetrycznej
## (ta ignoruje `light_cull_mask`), nie rzuca cienia i kończy się przed ścianą tła — ciemność przy postaciach się nie zmienia (GDD §8.3).
## Wpis w danych mapy (`NICHES`, czyta `level.gd`): {"kind": "doorway", "c0", "c1" (kolumny otworu, włącznie), "r0", "r1" (wiersze otworu,
## włącznie; podłoga wnęki = spód wiersza r1), "d" (m w głąb za ścianą tła), "lit" ("bulb" — żarówki, "" — bez światła)}.

const Level3D := preload("res://scripts/level3d.gd")
const T := Level3D.T

const LAYER_NICHE := 128                    ## warstwa wizualna brył wnęk (oprócz warstwy świata): tylko ją oświetlają światła wnęk
const WALL_Z := -Level3D.DEPTH_BACK         ## tył płyty ściany tła: od tej głębokości zaczyna się korytarz wnęki
const JAMB := 0.26                          ## m: ościeże (cegła) po obu stronach otworu
const LINTEL := 0.38                        ## m: nadproże (belka betonowa) nad otworem
const SKIN := 0.3                           ## m: grubość podłogi, stropu i ścian korytarza
const LIGHT_EDGE := 0.0                     ## światło wnęki kończy się najpóźniej na z = WALL_Z − LIGHT_EDGE (sprawdza `tools/test_niches.gd`)
const TREE_MARGIN := 3.0                    ## m: tyle wokół korytarza las nie stawia drzew (pnie i dolne gałęzie w środku wnęki)
## Żarówki wzdłuż korytarza: [głębokość od ściany tła (m), energia, kolor]. Bliska cieplejsza i jaśniejsza, daleka słabsza i chłodniejsza —
## dwa punkty światła dają oku skalę odległości. Energię stroi próg jasności otworu (≤ ok. 0,02 luminancji liniowej, `DEPTH_PLAN.md` N0).
const BULBS := [[3.0, 1.8, Color(1.0, 0.72, 0.42)], [7.0, 1.0, Color(0.86, 0.80, 0.70)]]
const BULB_RANGE := 3.0                     ## m: zasięg żarówki (z WALL_Z − 3 m światło sięga dokładnie do ściany tła)
const BULB_DROP := 1.0                      ## m: żarówka wisi tyle pod stropem korytarza — niżej niż nadproże w kadrze kamery (oko nad środkiem kadru)
const BULB_GLOW := 2.2                      ## jasność bańki (emisja bez cieniowania, powyżej 1 — gorące źródło z poświatą filtra ekranu `horror_fx`)

## Kafle mapy (Vector2i) zajęte przez otwory wnęk: tu nie ma płyt ściany tła, pilastrów ani dekali.
static func cells(entries: Array) -> Dictionary:
	var out := {}
	for e in entries:
		var d := e as Dictionary
		for c in range(int(d["c0"]), int(d["c1"]) + 1):
			for r in range(int(d["r0"]), int(d["r1"]) + 1):
				out[Vector2i(c, r)] = true
	return out

## Prostokąty w płaszczyźnie x–z, w których las nie stawia drzew: [x0, x1, z_near, z_far] (m; z_near > z_far, oba ujemne).
static func forest_holes(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		var d := e as Dictionary
		out.append([float(int(d["c0"])) * T - TREE_MARGIN, float(int(d["c1"]) + 1) * T + TREE_MARGIN,
				WALL_Z + 0.5, WALL_Z - float(d.get("d", 8.0)) - TREE_MARGIN])
	return out

## Błędy wpisów względem mapy (pusta tablica = w porządku): otwór na samym tle `b`, z podłogą pod spodem, bez okien `|`, lamp `I`,
## stempli `!`, stref zawału `^` ani znaczników w kaflach otworu, poza strefami wydobycia; światło tylko „bulb” albo brak.
static func validate(rows: Array, entries: Array, dig_zones: Array = []) -> Array:
	var errs: Array = []
	for i in entries.size():
		var d := entries[i] as Dictionary
		var c0 := int(d.get("c0", -1))
		var c1 := int(d.get("c1", -1))
		var r0 := int(d.get("r0", -1))
		var r1 := int(d.get("r1", -1))
		var tag := "wnęka %d (%d–%d × %d–%d)" % [i, c0, c1, r0, r1]
		if c1 < c0 or r1 < r0 or c0 < 0 or r0 < 0:
			errs.append(tag + ": zły prostokąt")
			continue
		if String(d.get("kind", "")) != "doorway":
			errs.append(tag + ": nieznany rodzaj %s" % d.get("kind", ""))
		if not ["bulb", ""].has(String(d.get("lit", ""))):
			errs.append(tag + ": nieznane światło %s" % d.get("lit", ""))
		if float(d.get("d", 8.0)) < 2.0:
			errs.append(tag + ": za płytka (d < 2 m)")
		for c in range(c0, c1 + 1):
			for r in range(r0, r1 + 1):
				var ch := Level3D._ch(rows, c, r)
				if ch != "b":
					errs.append(tag + ": kafel (%d, %d) to „%s”, nie samo tło `b`" % [c, r, ch])
			if not Level3D.is_solid_ch(Level3D._ch(rows, c, r1 + 1)):
				errs.append(tag + ": pod kolumną %d nie ma podłogi" % c)
		for z in dig_zones:
			var zr := Rect2i(int(z[0]), int(z[1]), int(z[2]) - int(z[0]) + 1, int(z[3]) - int(z[1]) + 1)
			if zr.intersects(Rect2i(c0 - 1, r0 - 1, c1 - c0 + 3, r1 - r0 + 3)):
				errs.append(tag + ": zachodzi na strefę wydobycia")
	return errs

## Buduje wnęki pod `parent` (węzeł geometrii mapy). `quality`: 0 = LOW (bez świateł, same świecące żarówki), 1–2 = światła wnęk.
static func build(parent: Node3D, rows: Array, entries: Array, quality := 2) -> void:
	if entries.is_empty():
		return
	for i in entries.size():
		var d := entries[i] as Dictionary
		var root := Node3D.new()
		root.name = "Niche%d" % i
		parent.add_child(root)
		_build_doorway(root, d, quality, hash(str(rows.size()) + str(d)))

static func _build_doorway(root: Node3D, d: Dictionary, quality: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var x0 := float(int(d["c0"])) * T
	var x1 := float(int(d["c1"]) + 1) * T
	var y_top := -float(int(d["r0"])) * T
	var y_floor := -float(int(d["r1"]) + 1) * T
	var depth := float(d.get("d", 8.0))
	var z_back := WALL_Z - depth
	var ix0 := x0 + JAMB                                  # światło otworu
	var ix1 := x1 - JAMB
	var iy1 := y_top - LINTEL
	var wall := Level3D.make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone")
	var conc := Level3D.make_pbr("concrete", 0.33, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone")
	var metal := Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust")
	var front := WALL_Z + 0.3                                 # lico ściany tła (płyta 0,3 m: od −DEPTH_BACK do −DEPTH_BACK + 0,3)
	# ościeża i nadproże w grubości płyty ściany tła — wnęka ma ramę, nie gołe cięcie
	_box(root, "JambL", Vector3(x0, y_floor, WALL_Z), Vector3(ix0, y_top, front), wall)
	_box(root, "JambR", Vector3(ix1, y_floor, WALL_Z), Vector3(x1, y_top, front), wall)
	_box(root, "Lintel", Vector3(ix0, iy1, WALL_Z - 0.05), Vector3(ix1, y_top, front + 0.04), conc)
	# wykruszony brzeg otworu: kilka cegieł i odprysków nierówno na ościeżach i pod nadprożem (zrywa prostokątny zarys)
	for side in [0, 1]:
		var xe := ix0 if side == 0 else ix1
		var sgn := 1.0 if side == 0 else -1.0
		for k in 5:
			var by := rng.randf_range(y_floor + 0.3, iy1 - 0.2)
			var bw := rng.randf_range(0.10, 0.24)
			var bh := rng.randf_range(0.07, 0.16)
			var bz := rng.randf_range(0.05, 0.22)
			_box(root, "Chip%d_%d" % [side, k], Vector3(minf(xe, xe + sgn * bw), by, front - bz), Vector3(maxf(xe, xe + sgn * bw), by + bh, front - 0.01), wall)
	for k in 4:
		var bx := rng.randf_range(ix0 + 0.2, ix1 - 0.4)
		var bw := rng.randf_range(0.18, 0.40)
		_box(root, "LintelChip%d" % k, Vector3(bx, iy1 - rng.randf_range(0.04, 0.12), front - rng.randf_range(0.06, 0.2)), Vector3(bx + bw, iy1, front - 0.01), conc)
	# korytarz: podłoga, strop, boki i ściana końcowa
	_box(root, "Floor", Vector3(ix0 - SKIN, y_floor - SKIN, z_back - SKIN), Vector3(ix1 + SKIN, y_floor, WALL_Z), conc)
	_box(root, "Ceiling", Vector3(ix0 - SKIN, iy1, z_back - SKIN), Vector3(ix1 + SKIN, iy1 + SKIN, WALL_Z), conc)
	_box(root, "SideL", Vector3(ix0 - SKIN, y_floor, z_back - SKIN), Vector3(ix0, iy1, WALL_Z), wall)
	_box(root, "SideR", Vector3(ix1, y_floor, z_back - SKIN), Vector3(ix1 + SKIN, iy1, WALL_Z), wall)
	# ściana końcowa z uchylonymi drzwiami: futryna, za nią ciemna szczelina, skrzydło obrócone ku korytarzowi
	var door_w := 1.0
	var door_h := minf(2.1, iy1 - y_floor - 0.2)
	var dx0 := ix0 + (ix1 - ix0) * 0.62
	_box(root, "BackL", Vector3(ix0, y_floor, z_back - SKIN), Vector3(dx0, iy1, z_back), wall)
	_box(root, "BackR", Vector3(dx0 + door_w, y_floor, z_back - SKIN), Vector3(ix1, iy1, z_back), wall)
	_box(root, "BackTop", Vector3(dx0, y_floor + door_h, z_back - SKIN), Vector3(dx0 + door_w, iy1, z_back), wall)
	_box(root, "DoorVoid", Vector3(dx0, y_floor, z_back - SKIN - 1.2), Vector3(dx0 + door_w, y_floor + door_h, z_back - SKIN - 1.1), Level3D.make_mat(Color(0.01, 0.01, 0.012), 1.0))
	var hinge := Node3D.new()                             # zawias po lewej, skrzydło uchylone do korytarza
	hinge.name = "DoorHinge"
	hinge.position = Vector3(dx0 + 0.02, y_floor, z_back + 0.03)
	hinge.rotation.y = deg_to_rad(-38.0)                  # ujemny kąt: wolny brzeg skrzydła wychodzi ku kamerze (+z)
	root.add_child(hinge)
	_box(hinge, "DoorLeaf", Vector3(0.0, 0.0, -0.025), Vector3(door_w - 0.04, door_h - 0.03, 0.025), metal)
	# rura i korytko kablowe pod stropem wzdłuż korytarza (prowadzą oko w głąb)
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.07
	pipe.bottom_radius = 0.07
	pipe.height = depth + 0.4
	pipe.radial_segments = 10
	var pm := MeshInstance3D.new()
	pm.name = "Pipe"
	pm.mesh = pipe
	pm.material_override = metal
	pm.rotation.x = PI * 0.5
	pm.position = Vector3(ix0 + 0.22, iy1 - 0.16, WALL_Z - depth * 0.5 + 0.1)
	root.add_child(pm)
	_box(root, "Tray", Vector3(ix1 - 0.42, iy1 - 0.12, z_back), Vector3(ix1 - 0.12, iy1 - 0.09, WALL_Z + 0.1), metal)
	# graty pod ścianami: beczka i skrzynia z modeli przedmiotów (jeśli są) — przerywają równą linię podłogi
	_prop(root, "barrel", Vector3(ix1 - 0.45, y_floor, WALL_Z - depth * 0.42), 0.9, rng.randf_range(0.0, TAU))
	_prop(root, "crate", Vector3(ix0 + 0.5, y_floor, WALL_Z - depth * 0.68), 0.7, rng.randf_range(-0.3, 0.3))
	# żarówki: przewód ze stropu, świecąca bańka (emisja, widoczna także na LOW) i światło tylko na bryłę wnęki
	if String(d.get("lit", "")) != "bulb":
		return
	for b in BULBS:
		var bz := WALL_Z - float(b[0])
		if bz < z_back + 0.4:
			continue
		var at := Vector3(ix0 + (ix1 - ix0) * 0.45, iy1 - BULB_DROP, bz)
		_box(root, "Cord", at + Vector3(-0.006, 0.08, -0.006), Vector3(at.x + 0.006, iy1, at.z + 0.006), metal)
		var bulb := SphereMesh.new()
		bulb.radius = 0.06
		bulb.height = 0.12
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = (b[2] as Color) * BULB_GLOW
		var bi := MeshInstance3D.new()
		bi.name = "Bulb"
		bi.mesh = bulb
		bi.material_override = bm
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bi.position = at
		root.add_child(bi)
		if quality <= 0:
			continue
		var l := OmniLight3D.new()
		l.name = "NicheLight"
		l.light_color = b[2]
		l.light_energy = float(b[1])
		l.omni_range = minf(BULB_RANGE, (WALL_Z - LIGHT_EDGE) - at.z)
		l.omni_attenuation = 1.4
		l.light_cull_mask = LAYER_NICHE
		l.light_volumetric_fog_energy = 0.0
		l.light_specular = 0.3
		l.shadow_enabled = false
		l.position = at
		root.add_child(l)
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | LAYER_NICHE     # warstwa świata (kamera świata) + wnęki (światła wnęk)

## Pudło między dwoma narożnikami (dowolna kolejność współrzędnych).
static func _box(root: Node3D, nm: String, a: Vector3, b: Vector3, mat: Material) -> MeshInstance3D:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var bm := BoxMesh.new()
	bm.size = hi - lo
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (lo + hi) * 0.5
	root.add_child(mi)
	return mi

## Model z art/items3d (`Level3D.model_mesh`) postawiony na `foot`, przeskalowany do wysokości `h` (m).
static func _prop(root: Node3D, model: String, foot: Vector3, h: float, yaw: float) -> void:
	var mm := Level3D.model_mesh(model)
	if mm.is_empty():
		return
	var mesh := mm[0] as Mesh
	var xf := mm[1] as Transform3D
	var aabb := xf * mesh.get_aabb()
	if aabb.size.y <= 0.0:
		return
	var k := h / aabb.size.y
	var mi := MeshInstance3D.new()
	mi.name = "Prop_" + model
	mi.mesh = mesh
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k))
	mi.transform = Transform3D(b, foot - b * Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)) * xf
	root.add_child(mi)
