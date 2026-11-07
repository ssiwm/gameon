extends RefCounted
## Wnęki w tylnej ścianie wnętrz widoku 3D (`DEPTH_PLAN.md`): otwór w ścianie tła (z = −DEPTH_BACK) z przestrzenią w głąb i własnym światłem.
## Czysta oprawa: bez kolizji, bez wpływu na wzrok wrogów, hałas i Uwagę; mapa ASCII i nawigacja się nie zmieniają.
## Światło wnęki świeci tylko na jej bryłę (`LAYER_NICHE`, wzór jak `MoonRim` na `Level3D.LAYER_FOREST`), nie oświetla mgły wolumetrycznej
## (ta ignoruje `light_cull_mask`), nie rzuca cienia i kończy się przed ścianą tła — ciemność przy postaciach się nie zmienia (GDD §8.3).
## Wpis w danych mapy (`NICHES`, czyta `level.gd`): {"kind" (rodzaj z `KINDS`), "c0", "c1" (kolumny otworu, włącznie), "r0", "r1" (wiersze otworu,
## włącznie; podłoga wnęki = spód wiersza r1), "d" (m w głąb za ścianą tła; brak = domyślna rodzaju), "lit" (światło z listy rodzaju, "" — bez światła)}.

const Level3D := preload("res://scripts/level3d.gd")
const T := Level3D.T

const LAYER_NICHE := 128                    ## warstwa wizualna brył wnęk (oprócz warstwy świata): tylko ją oświetlają światła wnęk
const WALL_Z := -Level3D.DEPTH_BACK         ## tył płyty ściany tła: od tej głębokości zaczyna się wnęka
const JAMB := 0.26                          ## m: ościeże (cegła) po obu stronach otworu
const LINTEL := 0.38                        ## m: nadproże (belka betonowa) nad otworem
const SKIN := 0.3                           ## m: grubość podłogi, stropu i ścian wnęki
const LIGHT_EDGE := 0.0                     ## światło wnęki kończy się najpóźniej na z = WALL_Z − LIGHT_EDGE (sprawdza `tools/test_niches.gd`)
const TREE_MARGIN := 3.0                    ## m: tyle wokół wnęki las nie stawia drzew (pnie i dolne gałęzie w środku wnęki)
const BULB_RANGE := 3.0                     ## m: zasięg światła (z WALL_Z − 3 m światło sięga dokładnie do ściany tła)
const BULB_DROP := 1.0                      ## m: żarówka wisi tyle pod stropem — niżej niż nadproże w kadrze kamery (oko nad środkiem kadru)
const BULB_GLOW := 2.2                      ## jasność bańki (emisja bez cieniowania, powyżej 1 — gorące źródło z poświatą filtra ekranu `horror_fx`)

## Rodzaje wnęk (`DEPTH_PLAN.md` N3): domyślna i najmniejsza głębokość (m) oraz dozwolone światła (pierwsze = typowe).
## doorway — zaplecze z żarówkami i uchylonymi drzwiami; corridor — długi korytarz techniczny z lampami w koszach co 4 m (najmocniejsza głębia);
## grate — pomieszczenie za kratą (pręty sylwetką na tle oświetlonego wnętrza); shelf — płytka wnęka z regałami, bez światła;
## drift — boczna sztolnia w tunelu: obudowa z drewnianych odrzwi, skalne ściany, tory i daleka lampa górnicza.
const KINDS := {
	"doorway": {"d": 8.0, "d_min": 2.0, "lit": ["bulb", ""]},
	"corridor": {"d": 12.0, "d_min": 8.0, "lit": ["cage", ""]},
	"grate": {"d": 4.5, "d_min": 2.5, "lit": ["bulb", ""]},
	"shelf": {"d": 1.2, "d_min": 0.8, "lit": [""]},
	"drift": {"d": 10.0, "d_min": 4.0, "lit": ["mine", ""]},
}
## Żarówki zaplecza: [głębokość od ściany tła (m), energia, kolor]. Bliska cieplejsza i jaśniejsza, daleka słabsza i chłodniejsza —
## dwa punkty światła dają oku skalę odległości. Energię stroi próg jasności otworu (≤ ok. 0,02 luminancji liniowej, `DEPTH_PLAN.md` N0).
const BULBS := [[3.0, 1.8, Color(1.0, 0.72, 0.42)], [7.0, 1.0, Color(0.86, 0.80, 0.70)]]
## Lampy w koszach w korytarzu: co 4 m, na zmianę po prawej i lewej, coraz słabsze i chłodniejsze.
const CAGES := [[2.5, 1.5, Color(1.0, 0.74, 0.46)], [6.5, 1.1, Color(0.95, 0.80, 0.62)], [10.5, 0.8, Color(0.82, 0.80, 0.74)], [14.5, 0.6, Color(0.74, 0.76, 0.76)]]
const GRATE_LAMP := [0.7, 1.2, Color(0.78, 0.88, 0.84)]    ## za kratą: [ułamek głębokości, energia, kolor] — zimna świetlówka magazynu
const MINE_LAMP := [1.6, 1.3, Color(1.0, 0.78, 0.45)]      ## sztolnia: [m przed czołem, energia, kolor] — daleka lampa górnicza
const BAR_STEP := 0.14                      ## m: rozstaw prętów kraty
const SET_STEP := 2.0                       ## m: rozstaw odrzwi obudowy w sztolni

## Głębokość wpisu (m): podana albo domyślna dla rodzaju.
static func depth_of(d: Dictionary) -> float:
	var k: Dictionary = KINDS.get(String(d.get("kind", "")), KINDS["doorway"])
	return float(d.get("d", k["d"]))

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
				WALL_Z + 0.5, WALL_Z - depth_of(d) - TREE_MARGIN])
	return out

## Błędy wpisów względem mapy (pusta tablica = w porządku): otwór na samym tle `b`, z podłogą pod spodem, bez okien `|`, lamp `I`,
## stempli `!`, stref zawału `^` ani znaczników w kaflach otworu, poza strefami wydobycia; rodzaj, światło i głębokość z `KINDS`.
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
		var kind := String(d.get("kind", ""))
		if not KINDS.has(kind):
			errs.append(tag + ": nieznany rodzaj %s" % kind)
			continue
		var k: Dictionary = KINDS[kind]
		if not (k["lit"] as Array).has(String(d.get("lit", ""))):
			errs.append(tag + ": światło „%s” niedozwolone dla rodzaju %s" % [d.get("lit", ""), kind])
		if depth_of(d) < float(k["d_min"]):
			errs.append(tag + ": za płytka (d < %.1f m dla rodzaju %s)" % [float(k["d_min"]), kind])
		if c1 - c0 < 1 or r1 - r0 < 1:
			errs.append(tag + ": otwór węższy lub niższy niż 2 kafle")
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

## Buduje wnęki pod `parent` (węzeł geometrii mapy). `quality`: 0 = LOW (bez świateł, same świecące bańki), 1–2 = światła wnęk.
static func build(parent: Node3D, rows: Array, entries: Array, quality := 2) -> void:
	if entries.is_empty():
		return
	for i in entries.size():
		var d := entries[i] as Dictionary
		var root := Node3D.new()
		root.name = "Niche%d" % i
		parent.add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(rows.size()) + str(d))
		var g := _geom(d)
		match String(d.get("kind", "doorway")):
			"corridor":
				_build_corridor(root, d, g, rng, quality)
			"grate":
				_build_grate(root, d, g, rng, quality)
			"shelf":
				_build_shelf(root, g, rng)
			"drift":
				_build_drift(root, d, g, rng, quality)
			_:
				_build_doorway(root, d, g, rng, quality)
		for n in root.find_children("*", "GeometryInstance3D", true, false):
			(n as VisualInstance3D).layers = 1 | LAYER_NICHE     # warstwa świata (kamera świata) + wnęki (światła wnęk)

## Wymiary otworu i wnęki (m, układ widoku 3D): brzegi otworu, światło otworu w ościeżach, spód nadproża, lico ściany i tył wnęki.
static func _geom(d: Dictionary) -> Dictionary:
	var x0 := float(int(d["c0"])) * T
	var x1 := float(int(d["c1"]) + 1) * T
	var y_top := -float(int(d["r0"])) * T
	var depth := depth_of(d)
	return {"x0": x0, "x1": x1, "y_top": y_top, "y_floor": -float(int(d["r1"]) + 1) * T, "depth": depth, "z_back": WALL_Z - depth,
			"ix0": x0 + JAMB, "ix1": x1 - JAMB, "iy1": y_top - LINTEL, "front": WALL_Z + 0.3}

static func _mats() -> Dictionary:
	return {
		"wall": Level3D.make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone"),
		"conc": Level3D.make_pbr("concrete", 0.33, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone"),
		"metal": Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
		"rock": Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic"),
		"post": Level3D.make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic"),
		"plank": Level3D.make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"),
		"void": Level3D.make_mat(Color(0.01, 0.01, 0.012), 1.0),
	}

## Rama otworu w grubości płyty ściany tła: ościeża, nadproże i wykruszony brzeg (kilka cegieł i odprysków nierówno) — wnęka ma ramę,
## nie gołe prostokątne cięcie (lekcja z `ATMOSPHERE_PLAN.md` F4).
static func _frame(root: Node3D, g: Dictionary, rng: RandomNumberGenerator, side_mat: Material, lintel_mat: Material) -> void:
	_box(root, "JambL", Vector3(g.x0, g.y_floor, WALL_Z), Vector3(g.ix0, g.y_top, g.front), side_mat)
	_box(root, "JambR", Vector3(g.ix1, g.y_floor, WALL_Z), Vector3(g.x1, g.y_top, g.front), side_mat)
	_box(root, "Lintel", Vector3(g.ix0, g.iy1, WALL_Z - 0.05), Vector3(g.ix1, g.y_top, g.front + 0.04), lintel_mat)
	for side in [0, 1]:
		var xe: float = g.ix0 if side == 0 else g.ix1
		var sgn := 1.0 if side == 0 else -1.0
		for k in 5:
			var by := rng.randf_range(g.y_floor + 0.3, g.iy1 - 0.2)
			var bw := rng.randf_range(0.10, 0.24)
			var bh := rng.randf_range(0.07, 0.16)
			var bz := rng.randf_range(0.05, 0.22)
			_box(root, "Chip%d_%d" % [side, k], Vector3(minf(xe, xe + sgn * bw), by, g.front - bz), Vector3(maxf(xe, xe + sgn * bw), by + bh, g.front - 0.01), side_mat)
	for k in 4:
		var bx := rng.randf_range(g.ix0 + 0.2, g.ix1 - 0.4)
		var bw := rng.randf_range(0.18, 0.40)
		_box(root, "LintelChip%d" % k, Vector3(bx, g.iy1 - rng.randf_range(0.04, 0.12), g.front - rng.randf_range(0.06, 0.2)), Vector3(bx + bw, g.iy1, g.front - 0.01), lintel_mat)

## Skorupa wnęki: podłoga, strop i boki od ściany tła do tyłu; ściana końcowa osobno (rodzaje mają w niej drzwi, czoło skały itd.).
static func _shell(root: Node3D, g: Dictionary, floor_mat: Material, ceil_mat: Material, side_mat: Material) -> void:
	_box(root, "Floor", Vector3(g.ix0 - SKIN, g.y_floor - SKIN, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.y_floor, WALL_Z), floor_mat)
	_box(root, "Ceiling", Vector3(g.ix0 - SKIN, g.iy1, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.iy1 + SKIN, WALL_Z), ceil_mat)
	_box(root, "SideL", Vector3(g.ix0 - SKIN, g.y_floor, g.z_back - SKIN), Vector3(g.ix0, g.iy1, WALL_Z), side_mat)
	_box(root, "SideR", Vector3(g.ix1, g.y_floor, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.iy1, WALL_Z), side_mat)

## Świecąca bańka (emisja bez cieniowania, widoczna także na LOW) i — od MEDIUM — światło tylko na bryły wnęk, bez cienia i bez mgły,
## z zasięgiem kończącym się na ścianie tła.
static func _lamp(root: Node3D, at: Vector3, energy: float, col: Color, quality: int, radius := 0.06, glow := BULB_GLOW) -> void:
	var bulb := SphereMesh.new()
	bulb.radius = radius
	bulb.height = radius * 2.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = col * glow
	var bi := MeshInstance3D.new()
	bi.name = "Bulb"
	bi.mesh = bulb
	bi.material_override = bm
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bi.position = at
	root.add_child(bi)
	if quality <= 0:
		return
	var l := OmniLight3D.new()
	l.name = "NicheLight"
	l.light_color = col
	l.light_energy = energy
	l.omni_range = minf(BULB_RANGE, (WALL_Z - LIGHT_EDGE) - at.z)
	l.omni_attenuation = 1.4
	l.light_cull_mask = LAYER_NICHE
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.3
	l.shadow_enabled = false
	l.position = at
	root.add_child(l)

## Rura wzdłuż wnęki pod stropem (prowadzi oko w głąb).
static func _pipe(root: Node3D, nm: String, x: float, y: float, z_back: float, r: float, mat: Material) -> void:
	var pipe := CylinderMesh.new()
	pipe.top_radius = r
	pipe.bottom_radius = r
	pipe.height = (WALL_Z - z_back) + 0.4
	pipe.radial_segments = 10
	var pm := MeshInstance3D.new()
	pm.name = nm
	pm.mesh = pipe
	pm.material_override = mat
	pm.rotation.x = PI * 0.5
	pm.position = Vector3(x, y, (WALL_Z + z_back) * 0.5 + 0.1)
	root.add_child(pm)

## doorway: korytarz zaplecza z uchylonymi drzwiami w ścianie końcowej, rurą, korytkiem, beczką i skrzynią; dwie żarówki („bulb”).
static func _build_doorway(root: Node3D, d: Dictionary, g: Dictionary, rng: RandomNumberGenerator, quality: int) -> void:
	var m := _mats()
	_frame(root, g, rng, m.wall, m.conc)
	_shell(root, g, m.conc, m.conc, m.wall)
	# ściana końcowa z uchylonymi drzwiami: futryna, za nią ciemna szczelina, skrzydło obrócone ku korytarzowi
	var door_w := 1.0
	var door_h := minf(2.1, g.iy1 - g.y_floor - 0.2)
	var dx0: float = g.ix0 + (g.ix1 - g.ix0) * 0.62
	_box(root, "BackL", Vector3(g.ix0, g.y_floor, g.z_back - SKIN), Vector3(dx0, g.iy1, g.z_back), m.wall)
	_box(root, "BackR", Vector3(dx0 + door_w, g.y_floor, g.z_back - SKIN), Vector3(g.ix1, g.iy1, g.z_back), m.wall)
	_box(root, "BackTop", Vector3(dx0, g.y_floor + door_h, g.z_back - SKIN), Vector3(dx0 + door_w, g.iy1, g.z_back), m.wall)
	_box(root, "DoorVoid", Vector3(dx0, g.y_floor, g.z_back - SKIN - 1.2), Vector3(dx0 + door_w, g.y_floor + door_h, g.z_back - SKIN - 1.1), m.void)
	var hinge := Node3D.new()                             # zawias po lewej, skrzydło uchylone do korytarza
	hinge.name = "DoorHinge"
	hinge.position = Vector3(dx0 + 0.02, g.y_floor, g.z_back + 0.03)
	hinge.rotation.y = deg_to_rad(-38.0)                  # ujemny kąt: wolny brzeg skrzydła wychodzi ku kamerze (+z)
	root.add_child(hinge)
	_box(hinge, "DoorLeaf", Vector3(0.0, 0.0, -0.025), Vector3(door_w - 0.04, door_h - 0.03, 0.025), m.metal)
	_pipe(root, "Pipe", g.ix0 + 0.22, g.iy1 - 0.16, g.z_back, 0.07, m.metal)
	_box(root, "Tray", Vector3(g.ix1 - 0.42, g.iy1 - 0.12, g.z_back), Vector3(g.ix1 - 0.12, g.iy1 - 0.09, WALL_Z + 0.1), m.metal)
	_prop(root, "barrel", Vector3(g.ix1 - 0.45, g.y_floor, WALL_Z - g.depth * 0.42), 0.9, rng.randf_range(0.0, TAU))
	_prop(root, "crate", Vector3(g.ix0 + 0.5, g.y_floor, WALL_Z - g.depth * 0.68), 0.7, rng.randf_range(-0.3, 0.3))
	if String(d.get("lit", "")) != "bulb":
		return
	for b in BULBS:
		var bz := WALL_Z - float(b[0])
		if bz < g.z_back + 0.4:
			continue
		var at := Vector3(g.ix0 + (g.ix1 - g.ix0) * 0.45, g.iy1 - BULB_DROP, bz)
		_box(root, "Cord", at + Vector3(-0.006, 0.08, -0.006), Vector3(at.x + 0.006, g.iy1, at.z + 0.006), m.metal)
		_lamp(root, at, float(b[1]), b[2], quality)

## corridor: długi korytarz techniczny (10–15 m) — lampy w koszach na zmianę po bokach, boczne przejście w połowie, dwie rury,
## korytko i zamknięte drzwi na końcu; im dalej, tym ciemniej i chłodniej.
static func _build_corridor(root: Node3D, d: Dictionary, g: Dictionary, rng: RandomNumberGenerator, quality: int) -> void:
	var m := _mats()
	_frame(root, g, rng, m.wall, m.conc)
	_box(root, "Floor", Vector3(g.ix0 - SKIN, g.y_floor - SKIN, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.y_floor, WALL_Z), m.conc)
	_box(root, "Ceiling", Vector3(g.ix0 - SKIN, g.iy1, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.iy1 + SKIN, WALL_Z), m.conc)
	_box(root, "SideR", Vector3(g.ix1, g.y_floor, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.iy1, WALL_Z), m.wall)
	# lewy bok z przejściem w bok w połowie korytarza (ciemna szczelina — korytarz „idzie dalej” poza kadr)
	var zg: float = WALL_Z - g.depth * 0.55
	var gw := 1.1
	var gh := minf(2.1, g.iy1 - g.y_floor - 0.2)
	_box(root, "SideL_a", Vector3(g.ix0 - SKIN, g.y_floor, zg + gw * 0.5), Vector3(g.ix0, g.iy1, WALL_Z), m.wall)
	_box(root, "SideL_b", Vector3(g.ix0 - SKIN, g.y_floor, g.z_back - SKIN), Vector3(g.ix0, g.iy1, zg - gw * 0.5), m.wall)
	_box(root, "SideL_top", Vector3(g.ix0 - SKIN, g.y_floor + gh, zg - gw * 0.5), Vector3(g.ix0, g.iy1, zg + gw * 0.5), m.wall)
	_box(root, "SideVoid", Vector3(g.ix0 - SKIN - 1.3, g.y_floor, zg - gw * 0.5), Vector3(g.ix0 - SKIN - 1.2, g.y_floor + gh, zg + gw * 0.5), m.void)
	_box(root, "Back", Vector3(g.ix0, g.y_floor, g.z_back - SKIN), Vector3(g.ix1, g.iy1, g.z_back), m.wall)
	var door_h := minf(2.05, g.iy1 - g.y_floor - 0.25)
	var dxc: float = (g.ix0 + g.ix1) * 0.5
	_box(root, "EndDoor", Vector3(dxc - 0.45, g.y_floor, g.z_back), Vector3(dxc + 0.45, g.y_floor + door_h, g.z_back + 0.05), m.metal)
	_box(root, "EndFrame", Vector3(dxc - 0.55, g.y_floor + door_h, g.z_back), Vector3(dxc + 0.55, g.y_floor + door_h + 0.08, g.z_back + 0.07), m.metal)
	_pipe(root, "PipeL", g.ix0 + 0.18, g.iy1 - 0.14, g.z_back, 0.08, m.metal)
	_pipe(root, "PipeL2", g.ix0 + 0.40, g.iy1 - 0.12, g.z_back, 0.05, m.metal)
	_box(root, "Tray", Vector3(g.ix1 - 0.40, g.iy1 - 0.12, g.z_back), Vector3(g.ix1 - 0.10, g.iy1 - 0.09, WALL_Z + 0.1), m.metal)
	_prop(root, "barrel", Vector3(g.ix1 - 0.42, g.y_floor, WALL_Z - g.depth * 0.30), 0.9, rng.randf_range(0.0, TAU))
	_prop(root, "mil_crate", Vector3(g.ix0 + 0.45, g.y_floor, WALL_Z - g.depth * 0.82), 0.5, rng.randf_range(-0.4, 0.4))
	if String(d.get("lit", "")) != "cage":
		return
	for i in CAGES.size():
		var b: Array = CAGES[i]
		var bz := WALL_Z - float(b[0])
		if bz < g.z_back + 0.6:
			continue
		var right := i % 2 == 0
		var wx: float = g.ix1 if right else g.ix0
		var sgn := -1.0 if right else 1.0
		var at := Vector3(wx + sgn * 0.20, g.iy1 - BULB_DROP, bz)     # nisko, jak żarówki zaplecza: dalsze lampy nie chowają się za nadprożem
		_box(root, "Bracket%d" % i, Vector3(wx, at.y + 0.08, bz - 0.03), Vector3(wx + sgn * 0.22, at.y + 0.12, bz + 0.03), m.metal)
		_box(root, "Conduit%d" % i, Vector3(wx + sgn * 0.02, at.y + 0.12, bz - 0.012), Vector3(wx + sgn * 0.045, g.iy1, bz + 0.012), m.metal)
		for k in 3:                                       # kosz: trzy pręty wokół bańki
			var a := float(k) * TAU / 3.0
			var p := at + Vector3(cos(a) * 0.075, 0.0, sin(a) * 0.075)
			_box(root, "Cage%d_%d" % [i, k], p + Vector3(-0.006, -0.09, -0.006), p + Vector3(0.006, 0.09, 0.006), m.metal)
		_lamp(root, at, float(b[1]), b[2], quality, 0.05)

## grate: pomieszczenie za kratą — pręty w świetle otworu (sylwetką na tle oświetlonego wnętrza), szafka, regał i kanister,
## zimna świetlówka w głębi („bulb”).
static func _build_grate(root: Node3D, d: Dictionary, g: Dictionary, rng: RandomNumberGenerator, quality: int) -> void:
	var m := _mats()
	_frame(root, g, rng, m.wall, m.conc)
	_shell(root, g, m.conc, m.conc, m.wall)
	_box(root, "Back", Vector3(g.ix0, g.y_floor, g.z_back - SKIN), Vector3(g.ix1, g.iy1, g.z_back), m.wall)
	# krata: pionowe pręty co BAR_STEP i dwie płaskowniki, w grubości ściany tła (jedno wywołanie rysowania na pręty)
	var bz: float = WALL_Z + 0.12
	var h: float = g.iy1 - g.y_floor
	var bar := BoxMesh.new()
	bar.size = Vector3(0.028, h, 0.028)
	var n := int(floor((g.ix1 - g.ix0 - 0.04) / BAR_STEP))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bar
	mm.instance_count = n
	var x_start: float = (g.ix0 + g.ix1) * 0.5 - float(n - 1) * BAR_STEP * 0.5
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x_start + float(i) * BAR_STEP, g.y_floor + h * 0.5, bz)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bars"
	mi.multimesh = mm
	mi.material_override = m.metal
	root.add_child(mi)
	for k in 2:
		var fy: float = g.y_floor + (0.35 if k == 0 else h - 0.35)
		_box(root, "FlatBar%d" % k, Vector3(g.ix0, fy - 0.03, bz - 0.025), Vector3(g.ix1, fy + 0.03, bz + 0.025), m.metal)
	_prop(root, "locker", Vector3(g.ix0 + 0.55, g.y_floor, g.z_back + 0.35), 1.9, rng.randf_range(-0.05, 0.05))
	_prop(root, "rack", Vector3(g.ix1 - 0.75, g.y_floor, g.z_back + 0.45), 1.8, rng.randf_range(-0.05, 0.05))
	_prop(root, "jerrycan", Vector3((g.ix0 + g.ix1) * 0.5 + 0.2, g.y_floor, WALL_Z - g.depth * 0.45), 0.45, rng.randf_range(0.0, TAU))
	if String(d.get("lit", "")) != "bulb":
		return
	var at := Vector3((g.ix0 + g.ix1) * 0.5, g.iy1 - 0.6, WALL_Z - g.depth * float(GRATE_LAMP[0]))
	_box(root, "Tube", at + Vector3(-0.45, -0.02, -0.04), at + Vector3(0.45, 0.03, 0.04), m.metal)
	for sx in [-0.4, 0.4]:
		_box(root, "TubeChain", at + Vector3(sx - 0.004, 0.03, -0.004), Vector3(at.x + sx + 0.004, g.iy1, at.z + 0.004), m.metal)
	_lamp(root, at + Vector3(0.0, -0.05, 0.0), float(GRATE_LAMP[1]), GRATE_LAMP[2], quality, 0.04)

## shelf: płytka wnęka (ok. 1–1,5 m) z regałami pod ścianą końcową i drobiazgami przed nimi; bez własnego światła — widać ją
## tylko w świetle sceny (latarka, flary), jak resztę ściany.
static func _build_shelf(root: Node3D, g: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := _mats()
	_frame(root, g, rng, m.wall, m.conc)
	_shell(root, g, m.conc, m.conc, m.wall)
	_box(root, "Back", Vector3(g.ix0, g.y_floor, g.z_back - SKIN), Vector3(g.ix1, g.iy1, g.z_back), m.wall)
	var models := ["shelf", "shelf_n", "shelf_b"]
	var w: float = g.ix1 - g.ix0
	var n := maxi(1, int(floor(w / 1.25)))
	var h := minf(2.0, g.iy1 - g.y_floor - 0.15)
	for i in n:
		var x: float = g.ix0 + w * (float(i) + 0.5) / float(n)
		_prop(root, models[(i + rng.randi_range(0, 2)) % models.size()], Vector3(x, g.y_floor, g.z_back + 0.32), h, rng.randf_range(-0.04, 0.04))
	_prop(root, "jerrycan", Vector3(g.ix0 + w * 0.2, g.y_floor, WALL_Z - g.depth * 0.25), 0.45, rng.randf_range(0.0, TAU))
	_prop(root, "tyre", Vector3(g.ix1 - w * 0.18, g.y_floor, WALL_Z - g.depth * 0.3), 0.32, rng.randf_range(0.0, TAU))

## drift: boczna sztolnia w tunelu — obudowa z drewnianych odrzwi co SET_STEP, nierówne skalne ściany i strop, tory na podkładach,
## czoło skały na końcu i daleka lampa górnicza („mine”): bliska część zostaje ciemna, światło stoi w głębi.
static func _build_drift(root: Node3D, d: Dictionary, g: Dictionary, rng: RandomNumberGenerator, quality: int) -> void:
	var m := _mats()
	_frame(root, g, rng, m.wall, m.wall)                  # otwór przebity w murze obudowy tunelu: ościeża i nadproże z tej samej cegły
	_box(root, "Floor", Vector3(g.ix0 - SKIN, g.y_floor - SKIN, g.z_back - SKIN), Vector3(g.ix1 + SKIN, g.y_floor, WALL_Z), m.rock)
	# skalne boki i strop z odcinków o losowym wcięciu — nierówny zarys zamiast gładkiej rury
	var seg := 1.2
	var z: float = WALL_Z
	var k := 0
	while z > g.z_back:
		var z2 := maxf(z - seg, g.z_back - SKIN)
		var il := rng.randf_range(0.0, 0.22)
		var ir := rng.randf_range(0.0, 0.22)
		var dt := rng.randf_range(0.0, 0.25)
		_box(root, "RockL%d" % k, Vector3(g.ix0 - SKIN, g.y_floor, z2), Vector3(g.ix0 + il, g.iy1, z), m.rock)
		_box(root, "RockR%d" % k, Vector3(g.ix1 - ir, g.y_floor, z2), Vector3(g.ix1 + SKIN, g.iy1, z), m.rock)
		_box(root, "RockTop%d" % k, Vector3(g.ix0 - SKIN, g.iy1 - dt, z2), Vector3(g.ix1 + SKIN, g.iy1 + SKIN, z), m.rock)
		z = z2
		k += 1
	_box(root, "Face", Vector3(g.ix0, g.y_floor, g.z_back - SKIN), Vector3(g.ix1, g.iy1, g.z_back), m.rock)
	# odrzwia: dwa stojaki i stropnica, pierwsze tuż za ścianą tła
	var post_h: float = g.iy1 - g.y_floor - 0.28
	var zs: float = WALL_Z - 0.35
	var s := 0
	while zs > g.z_back + 0.5:
		var lx: float = g.ix0 + 0.28
		var rx: float = g.ix1 - 0.28
		_box(root, "SetL%d" % s, Vector3(lx - 0.11, g.y_floor, zs - 0.11), Vector3(lx + 0.11, g.y_floor + post_h, zs + 0.11), m.post)
		_box(root, "SetR%d" % s, Vector3(rx - 0.11, g.y_floor, zs - 0.11), Vector3(rx + 0.11, g.y_floor + post_h, zs + 0.11), m.post)
		_box(root, "Cap%d" % s, Vector3(lx - 0.22, g.y_floor + post_h, zs - 0.12), Vector3(rx + 0.22, g.y_floor + post_h + 0.24, zs + 0.12), m.post)
		zs -= SET_STEP
		s += 1
	# tory na podkładach do czoła (podkłady jednym wywołaniem rysowania)
	var cx: float = (g.ix0 + g.ix1) * 0.5
	for side in [-1.0, 1.0]:
		_box(root, "Rail%d" % int(side), Vector3(cx + side * 0.36 - 0.025, g.y_floor + 0.08, g.z_back), Vector3(cx + side * 0.36 + 0.025, g.y_floor + 0.14, WALL_Z + 0.05), m.metal)
	var sl := BoxMesh.new()
	sl.size = Vector3(1.05, 0.08, 0.16)
	var ns := int(floor((WALL_Z - g.z_back) / 0.6))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sl
	mm.instance_count = ns
	for i in ns:
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), Vector3(cx, g.y_floor + 0.04, WALL_Z - 0.3 - float(i) * 0.6)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Sleepers"
	mi.multimesh = mm
	mi.material_override = m.plank
	root.add_child(mi)
	_prop(root, "logs", Vector3(g.ix1 - 0.6, g.y_floor, WALL_Z - g.depth * 0.45), 0.45, rng.randf_range(-0.3, 0.3))
	if String(d.get("lit", "")) != "mine":
		return
	var lz: float = g.z_back + float(MINE_LAMP[0])
	var at := Vector3(cx - 0.25, g.y_floor + post_h * 0.6, lz)    # na długim haku: wyżej stropnice bliższych odrzwi zasłaniają lampę w kadrze
	_box(root, "LampHook", Vector3(at.x - 0.005, at.y + 0.05, lz - 0.005), Vector3(at.x + 0.005, g.y_floor + post_h, lz + 0.005), m.metal)
	_box(root, "LampHood", at + Vector3(-0.05, 0.03, -0.05), at + Vector3(0.05, 0.08, 0.05), m.metal)
	_lamp(root, at, float(MINE_LAMP[1]), MINE_LAMP[2], quality, 0.045, 2.4)

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
