extends RefCounted
## Wejście strefy wydobycia w widoku 3D (DIG_ENTRANCE_PLAN.md E2): osypisko urobku u stopy czoła i odrzwia na końcu obudowy korytarza.
## Czoło po E1 wyglądało jak zasyp, ale stało gołe na równej podłodze — w zasypanej sztolni u stopy leży stożek urobku, a obudowa kończy się
## ramą. Tylko obraz u każdego peera (bez kolizji i sieci, symulacja 2D bez zmian). Geometria liczona ze strefy (`entrance`, `face_bulge`,
## mapa z `setup`) i stałego ziarna, więc ten sam obraz u wszystkich, a `tools/test_dig_face.gd` sprawdza ją bez sceny.

const Mats := preload("res://scripts/dig_materials.gd")

const TILE := 16.0
const TALUS_H := {"gravel": 0.5, "dirt": 0.34, "rock": 0.26, "vein": 0.26}   ## m: wysokość osypiska przy czole — żwir sypie stożek, skała i ziemia kupkę brył
const TALUS_SLOPE := 0.72                 ## tangens stoku (żwir ok. 36°): długość osypiska = wysokość / stok
const TALUS_IN := 0.15                    ## m: stopa osypiska zaczyna się w czole — bez szczeliny między nim a garbami
const TALUS_PATH := Vector2(0.3, 0.85)    ## |z| m: do 0,3 od płaszczyzny gry przydeptana ścieżka (postać przy czole), od 0,85 pełna wysokość
const TALUS_TROD := 0.12                  ## udział wysokości na ścieżce — stopy postaci nie toną w urobku
const TALUS_FRONT_K := 0.55               ## przed płaszczyzną gry niżej: osypisko nie zasłania nóg postaci kamerze
const TALUS_FRONT_FADE := 0.4             ## m: przy przodzie mapy schodzi do zera (bez otwartego przekroju siatki)
const TALUS_BACK_GAP := 0.32              ## m: tylny brzeg przed tylną ścianą (płyta 0,3 m na −DEPTH_BACK + 0,15)
const TALUS_SINK := 0.015                 ## m: brzeg pod podłogą — bez migotania styku
const TALUS_NU := 9                       ## wierzchołków od czoła do brzegu
const TALUS_DZ := 0.12                    ## m: odstęp wierzchołków w głąb
const TALUS_SHADE := Vector2(0.38, 0.62)  ## jasność urobku (× odcień materiału): luźny, w cieniu — ciemniejszy od świeżego czoła w garbach
const TALUS_ROCKS := {"gravel": 30, "dirt": 22, "rock": 26, "vein": 26}      ## bryłek na powierzchni osypiska
const TALUS_ROCK_S := {"gravel": Vector2(0.14, 0.32), "dirt": Vector2(0.2, 0.42), "rock": Vector2(0.28, 0.62), "vein": Vector2(0.28, 0.62)}   ## skala bryły z `fracture_rock` (ok. 0,4 m)

const FRAME_W := 0.2                      ## m: przekrój stojaka i stropnicy (jak stemple strefy, view3d SUPPORT_W)
const FRAME_POST_Z := 0.35                ## m: oś stojaka przed tylną ścianą (od −DEPTH_BACK)
const FRAME_CAP_Z := 0.6                  ## m: stropnica do z = +0,6 — przód obudowy jest w przekroju, jak kapa stempli wykopu
const FRAME_GAP := 0.03                   ## m: stojak przy czole, nie w nim (najdalszy garb na jego wysokości)

## Kolumna korytarza przy wejściu strefy i wiersz podłogi (kafle mapy) — {} bez wejścia z boku.
static func _air_col(e: Dictionary) -> Vector2i:
	var out := -int(e["dir"])
	var c := int(float(e["wall_x"]) / TILE) + (0 if out > 0 else -1)
	return Vector2i(c, int(float(e["floor_y"]) / TILE) - 1)

## Osypisko u stopy czoła: {"mesh": ArrayMesh (materiał strefy — dig_ground.gd, alfa 1), "rocks": [{t, v, c, w}] bryłki na wierzchu,
## "mat": klucz materiału, "h": wysokość przy czole}. `bulge` — garb czoła (view3d: (wysokość nad podłogą m, z) → m w stronę powietrza).
## Pusty słownik, gdy strefa nie ma wejścia z boku (wejście od góry — nie ma czoła, pod które coś się osypie).
static func talus(z: Node2D, px: float, front: float, back: float, bulge: Callable) -> Dictionary:
	var e: Dictionary = z.entrance()
	if e.is_empty() or int(e["dir"]) == 0:
		return {}
	var out := float(-int(e["dir"]))
	var wall := float(e["wall_x"]) * px
	var floor_m := -float(e["floor_y"]) * px
	var key: String = z.material_at_px(Vector2(float(e["wall_x"]) - out * 6.0, float(e["floor_y"]) - 6.0))
	var h0: float = TALUS_H.get(key, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(z.seed_v), int(e["wall_x"]), int(e["floor_y"]), "talus"])
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.seed = rng.randi()
	nz.frequency = 1.0
	var zb := back + TALUS_BACK_GAP
	var ze := front - 0.02
	var nzs := maxi(int(ceil((ze - zb) / TALUS_DZ)), 2)
	var tint := Mats.tint(Mats.code(key))
	var w := Vector2(1.0 if key == "gravel" else 0.0, 1.0 if key == "rock" or key == "vein" else 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := []                                              # z każdego wiersza: x0, długość, wysokość
	for j in nzs + 1:
		var zz := lerpf(zb, ze, float(j) / float(nzs))
		var hz := height_at(zz, h0, front) * (0.8 + 0.4 * (0.5 + 0.5 * nz.get_noise_1d(zz * 1.7)))
		var x0 := minf(float(bulge.call(0.05, zz)), float(bulge.call(hz, zz))) - TALUS_IN   # najgłębszy garb na wysokości osypiska: wierzch dotyka czoła
		var ln := TALUS_IN + maxf(hz / TALUS_SLOPE, 0.25)
		cols.append(Vector3(x0, ln, hz))
		for i in TALUS_NU:
			var u := float(i) / float(TALUS_NU - 1)
			var y := _profile(u, hz) + 0.05 * hz * sin(u * PI) * nz.get_noise_2d(u * 3.0, zz * 2.3)
			if i == TALUS_NU - 1:
				y = -TALUS_SINK
			var sh := lerpf(TALUS_SHADE.x, TALUS_SHADE.y, 0.5 + 0.5 * nz.get_noise_2d(u * 5.0 + 9.0, zz * 4.0))
			st.set_color(Color(tint.r * sh, tint.g * sh, tint.b * sh, 1.0))
			st.set_uv2(w)
			st.add_vertex(Vector3(wall + out * (x0 + u * ln), floor_m + y, zz))
	for j in nzs:
		for i in TALUS_NU - 1:
			var a := j * TALUS_NU + i
			var b := a + TALUS_NU
			if out < 0.0:                                           # przód trójkąta zgodnie z ruchem wskazówek (Godot) → normalna w górę
				st.add_index(a); st.add_index(b); st.add_index(a + 1)
				st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
			else:
				st.add_index(a); st.add_index(a + 1); st.add_index(b)
				st.add_index(a + 1); st.add_index(b + 1); st.add_index(b)
	st.generate_normals()
	var rocks: Array = []
	var sz: Vector2 = TALUS_ROCK_S.get(key, Vector2(0.2, 0.4))
	for k in int(TALUS_ROCKS.get(key, 20)):
		var zz := lerpf(zb, ze - TALUS_FRONT_FADE, rng.randf())
		if absf(zz) < TALUS_PATH.x and rng.randf() < 0.85:      # ścieżka przydeptana: tylko pojedyncze okruchy
			continue
		var c: Vector3 = cols[clampi(roundi((zz - zb) / (ze - zb) * float(nzs)), 0, nzs)]
		var u0 := TALUS_IN / c.y                                 # brzeg czoła na stoku
		var u := lerpf(u0, 0.97, pow(rng.randf(), 0.8))
		var sc := rng.randf_range(sz.x, sz.y)
		var p := Vector3(wall + out * (c.x + u * c.y), floor_m + maxf(_profile(u, c.z), 0.0) + sc * 0.12, zz)
		rocks.append({"t": Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * sc), p),
			"v": rng.randi() % 3, "c": Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5), "w": Color(w.x, w.y, 0.0, 0.0)})
	return {"mesh": st.commit(), "rocks": rocks, "mat": key, "h": h0}

## Wysokość osypiska przy czole na głębokości `zz` (bez szumu): ścieżka przy płaszczyźnie gry, niżej przed nią, zero przy przodzie mapy.
static func height_at(zz: float, h0: float, front: float) -> float:
	var h := h0 * lerpf(TALUS_TROD, 1.0, smoothstep(TALUS_PATH.x, TALUS_PATH.y, absf(zz)))
	if zz > 0.0:
		h *= TALUS_FRONT_K
	return h * smoothstep(front - 0.02, front - TALUS_FRONT_FADE, zz)

## Przekrój stoku: od wysokości przy czole (u = 0) do podłogi (u = 1), wklęsły u stopy jak usypany żwir.
static func _profile(u: float, h: float) -> float:
	return h * pow(1.0 - u, 1.5)

## Odrzwia na końcu obudowy korytarza: [{"size", "pos", "rot"}] belek (m, świat) — stojak przy tylnej ścianie, stropnica pod stropem
## korytarza w głąb do przodu obudowy i klin. Tylko gdy kafel korytarza przy czole ma ścianę tła (`lined`: Level3D.back_wall_at — 1.2);
## na 1.1 i 1.3 nie ma obudowy, którą rama by kończyła. Przedniego stojaka nie ma (przód obudowy jest w przekroju) — stałby między
## kamerą a postacią przy czole.
static func frame(z: Node2D, px: float, back: float, bulge: Callable, lined: Callable) -> Array:
	var e: Dictionary = z.entrance()
	if e.is_empty() or int(e["dir"]) == 0:
		return []
	var ac := _air_col(e)
	if not bool(lined.call(ac.x, ac.y)):
		return []
	var r := ac.y
	var solid: Callable = z._solid_at
	while r > 0 and not bool(solid.call(ac.x, r - 1)) and ac.y - r < 12:
		r -= 1
	var out := float(-int(e["dir"]))
	var floor_m := -float(e["floor_y"]) * px
	var ceil_m := -float(r) * TILE * px
	var h := ceil_m - floor_m - FRAME_W
	var pz := back + FRAME_POST_Z
	var reach := 0.0
	for k in 6:
		reach = maxf(reach, float(bulge.call(h * float(k) / 5.0, pz)))
	var x := float(e["wall_x"]) * px + out * (reach + FRAME_W * 0.5 + FRAME_GAP)
	var cap_reach := 0.0
	for k in 8:
		cap_reach = maxf(cap_reach, float(bulge.call(h, lerpf(back + 0.1, FRAME_CAP_Z, float(k) / 7.0))))
	var cx := float(e["wall_x"]) * px + out * (cap_reach + FRAME_W * 0.5 + FRAME_GAP)
	var z0 := back + 0.12
	return [
		{"size": Vector3(FRAME_W, h, FRAME_W), "pos": Vector3(x, floor_m + h * 0.5, pz), "rot": Vector3(0.0, 0.2, out * 0.015)},
		{"size": Vector3(FRAME_W * 1.3, FRAME_W, FRAME_CAP_Z - z0), "pos": Vector3(cx, ceil_m - FRAME_W * 0.5, (FRAME_CAP_Z + z0) * 0.5), "rot": Vector3.ZERO},
		{"size": Vector3(0.22, 0.1, 0.16), "pos": Vector3(x, floor_m + h - 0.05, pz + 0.17), "rot": Vector3(PI, 0.0, 0.0), "wedge": true},
	]
