extends RefCounted
## Skalne nawisy widoku 3D (przegląd budynków 2026-11-19): płyta litej skały wisząca nad ścieżką w lesie (1.1 „jaskinia pod skalnym
## sufitem”) w 3D była blokiem gruntu lasu w powietrzu, z lasem za i pod nim. Wychodnia skalna z wydrążeniem: kafle płyty w materiale
## skały (`Level3D.rock_rects`), za płaszczyzną gry strop jaskini w głąb, tylna ściana, boki i zbocza wychodni schodzące do gruntu po obu
## końcach płyty. Wnętrze zasłonięte od nieba (AO w alfie koloru wierzchołków), skalne dno nad gruntem i nieregularne obrzeże wylotu
## (bez tego wnętrze czytało się z boku jak płaska, prześwitująca tafla). Czysta oprawa: bez kolizji, wpływu na wzrok wrogów, hałas i Uwagę; mapa ASCII, ścieżka i nawigacja bez zmian.
## Wpis w danych mapy (`CAVES`, czyta `level.gd`): {"c0", "c1" (kolumny płyty, włącznie), "r0", "r1" (wiersze płyty, włącznie), "floor" (wiersz
## gruntu pod jaskinią — jego wierzch to dno), "d" (m: głębokość jaskini za ścianą tła; brak = DEPTH), "slope" (m: szerokość zbocza; brak = SLOPE)}.

const Level3D := preload("res://scripts/level3d.gd")
const T := Level3D.T

const DEPTH := 6.5                         ## m: tylna ściana jaskini tyle za tyłem bryły gry (z = −DEPTH_BACK − DEPTH)
const BACK_T := 2.5                        ## m: grubość skały za tylną ścianą (wierzch i zbocza sięgają tak głęboko)
const SLOPE := 14.0                        ## m: zbocze wychodni od końca płyty do gruntu (płyta 17 m nad gruntem: przy 7 m stało jak mur)
const STEP := 0.5                          ## m: gęstość siatki powierzchni
const AMP := 0.6                           ## m: drobna nierówność skały (wzdłuż normalnej)
const AMP_BIG := 1.4                       ## m: duże garby i wnęki tylnej ściany i stropu
const EDGE := 1.2                          ## m: przy krawędzi ściany nierówność gaśnie do zera — sąsiednie ściany stykają się bez szczelin
const TALUS := 2.2                         ## wykładnik profilu zbocza: stromo pod płytą, łagodny piarg przy gruncie
const RIDGE := 1.1                         ## m: nierówność linii zbocza (garby na sylwetce)
const SINK := 0.4                          ## m: dół ścian i zboczy pod wierzchem gruntu (dno lasu bywa nierówne)
const OCC_DEEP := 0.4                      ## zasłonięcie nieba przy tylnej ścianie (alfa koloru → AO shadera skały): wnętrze było jasne jak zbocze
const OCC_CEIL := 0.65                     ## dodatkowo pod samym stropem (płyta zasłania niebo z góry)
const OCC_SIDE := 0.7                      ## dodatkowo przy bokach — ościeże wylotu czyta się jako głębia, nie jako krawędź płaskiej ściany
const SIDE_W := 5.0                        ## m: szerokość przyciemnienia przy bokach
const ALB_DEEP := 0.8                      ## albedo przy tylnej ścianie (wilgoć, sadza) — reszta różnicy z AO
const JAMB := 2.4                          ## m: największy wysięg skalnego obrzeża wylotu w otwór (ościeża i warga stropu): prosty prostokąt wylotu wyglądał na wycięty
const JAMB_D := 1.6                        ## m: grubość obrzeża w głąb za czołem
const FLOOR_UP := 0.25                     ## m: dno jaskini nad wierzchem gruntu (las ciągnął się do środka i wyglądał jak prześwit przez skałę; niżej grunt przebijał plamami)

static var _noise: FastNoiseLite
static var _noise_big: FastNoiseLite
static var _noise_col: FastNoiseLite
static var _mat: Material
static var _occ: Dictionary = {}           ## granice wnętrza budowanej jaskini (`_bounds`), puste dla ścian zewnętrznych — zasłonięcie w `_tri`

## Prostokąty kafli płyt [c0, r0, c1, r1] do materiału skały (`Level3D.rock_rects`).
static func rock_rects(caves: Array) -> Array:
	var out: Array = []
	for e: Dictionary in caves:
		out.append([int(e["c0"]), int(e["r0"]), int(e["c1"]), int(e["r1"])])
	return out

## Obrys wychodni w rzucie x–z do `Level3D.niche_holes` ([x0, x1, z bliżej, z dalej]): las tła nie stawia tam drzew (pnie w skale).
static func forest_holes(caves: Array) -> Array:
	var out: Array = []
	for e: Dictionary in caves:
		var b := _bounds(e)
		out.append([b["x0"] - b["w"] - 1.0, b["x1"] + b["w"] + 1.0, -Level3D.DEPTH_BACK + 0.5, b["zb"] - 1.0])
	return out

static func _bounds(e: Dictionary) -> Dictionary:
	var zd := -Level3D.DEPTH_BACK - float(e.get("d", DEPTH))
	return {"x0": float(e["c0"]) * T, "x1": float(int(e["c1"]) + 1) * T, "yt": -float(e["r0"]) * T, "yb": -float(int(e["r1"]) + 1) * T,
		"yg": -float(e["floor"]) * T, "zf": -Level3D.DEPTH_BACK, "zd": zd, "zb": zd - BACK_T, "w": float(e.get("slope", SLOPE))}

## Bryły jaskiń w warstwie świata (z cieniem). Zwraca liczbę zbudowanych jaskiń.
static func build(parent: Node3D, caves: Array) -> int:
	if caves.is_empty():
		return 0
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.45
		_noise.fractal_octaves = 3
		_noise_big = FastNoiseLite.new()
		_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_big.frequency = 0.09
		_noise_big.seed = 7
		_noise_col = FastNoiseLite.new()
		_noise_col.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_col.frequency = 0.05
		_noise_col.fractal_octaves = 2
		_noise_col.seed = 23
	if _mat == null:
		_mat = Level3D.rock_material()                    # ten sam co płyta i wnęka: dwie skale tekstury, odcień z koloru wierzchołków
	var n := 0
	for e: Dictionary in caves:
		var b := _bounds(e)
		var x0: float = b["x0"]
		var x1: float = b["x1"]
		var yt: float = b["yt"]
		var yb: float = b["yb"]
		var yg: float = float(b["yg"]) - SINK
		var zf: float = b["zf"]
		var zd: float = b["zd"]
		var zb: float = b["zb"]
		var w: float = b["w"]
		var mesh := ArrayMesh.new()
		# wnętrze: strop (spód płyty w głąb), tylna ściana, boki, dno — zasłonięte od nieba tym mocniej, im głębiej
		_occ = b
		_rect(mesh, Vector3(x0, yb, zf), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, 0.0, zd - zf), Vector3.DOWN, 1.0)
		_rect(mesh, Vector3(x0, yg, zd), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, yb - yg, 0.0), Vector3.BACK, 1.0)
		_rect(mesh, Vector3(x0, yg, zf), Vector3(0.0, 0.0, zd - zf), Vector3(0.0, yb - yg, 0.0), Vector3.RIGHT, 0.6)
		_rect(mesh, Vector3(x1, yg, zf), Vector3(0.0, 0.0, zd - zf), Vector3(0.0, yb - yg, 0.0), Vector3.LEFT, 0.6)
		_rect(mesh, Vector3(x0, float(b["yg"]) + FLOOR_UP, zf), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, 0.0, zd - zf), Vector3.UP, 0.12)
		_occ = {}
		# obrzeże wylotu: ościeża po bokach i warga pod stropem, nieregularne, z grubością w głąb
		var ya := float(b["yg"])
		var lip_l := []
		var lip_r := []
		var lip_t := []
		var ny := maxi(2, int(ceil((yb - ya) / STEP)))
		for i in ny + 1:
			var y := ya + (yb - ya) * float(i) / ny
			var tl := float(i) / ny
			lip_l.append([Vector2(x0, y), Vector2(x0 + _jag(Vector2(x0, y), tl), y)])
			lip_r.append([Vector2(x1, y), Vector2(x1 - _jag(Vector2(x1, y), tl), y)])
		var nx := maxi(2, int(ceil((x1 - x0) / STEP)))
		for i in nx + 1:
			var x := x0 + (x1 - x0) * float(i) / nx
			lip_t.append([Vector2(x, yb), Vector2(x, yb - _jag(Vector2(x, yb), 1.0) * 0.6)])
		_lip(mesh, lip_l, zf)
		_lip(mesh, lip_r, zf)
		_lip(mesh, lip_t, zf - 0.01)                       # o włos za ościeżami: w rogu wylotu bez migotania; przed tło gry nie wolno
		# zewnątrz: wierzch wychodni i zbocza do gruntu (z przodu czoło zbocza za bryłą gry)
		_rect(mesh, Vector3(x0, yt, zf), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, 0.0, zb - zf), Vector3.UP, 0.5)
		for side in [-1.0, 1.0]:
			var xe := x0 if side < 0.0 else x1
			_slope(mesh, xe, side, yt, yg, w, zf, zb)
		var mi := MeshInstance3D.new()
		mi.name = "Cave%d" % n
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mi)
		n += 1
	return n

## Wysięg obrzeża wylotu w punkcie krawędzi `q` (ułamek wysokości `t`: przy dnie węziej — piarg, wyżej szerzej pod stropem).
static func _jag(q: Vector2, t: float) -> float:
	var n := 0.5 + 0.5 * _noise_big.get_noise_2d(q.x * 2.3, q.y * 2.3) + 0.25 * _noise.get_noise_2d(q.x * 1.7, q.y * 1.7)
	return JAMB * clampf(n, 0.1, 1.0) * lerpf(0.45, 1.0, t)

## Obrzeże wylotu: pary [krawędź otworu, wierzchołek wysięgu] w płaszczyźnie z = `z`; czoło (do kamery) i grzbiet w głąb na JAMB_D,
## zwrócony w otwór (od krawędzi skały ku wierzchołkowi wysięgu).
static func _lip(mesh: ArrayMesh, pairs: Array, z: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pairs.size() - 1:
		var a: Vector2 = pairs[i][0]
		var b: Vector2 = pairs[i][1]
		var c: Vector2 = pairs[i + 1][1]
		var d: Vector2 = pairs[i + 1][0]
		_tri(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3.BACK)
		_tri(st, Vector3(a.x, a.y, z), Vector3(c.x, c.y, z), Vector3(d.x, d.y, z), Vector3.BACK)
		var e := c - b
		var out := Vector3(e.y, -e.x, 0.0).normalized()
		if out.dot(Vector3(b.x - a.x, b.y - a.y, 0.0)) < 0.0:
			out = -out
		var zb := z - JAMB_D
		_tri(st, Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3(c.x, c.y, zb), out)
		_tri(st, Vector3(b.x, b.y, z), Vector3(c.x, c.y, zb), Vector3(b.x, b.y, zb), out)
	_commit(st, mesh)

## Punkt linii zbocza w ułamku `t` (0 — koniec płyty u góry, 1 — grunt): profil piargu (TALUS) z garbami (RIDGE), wspólny dla zbocza i jego czoła.
static func _profile(xe: float, side: float, yt: float, yg: float, w: float, t: float) -> Vector2:
	var x := xe + side * w * t
	var y := yt - (yt - yg) * (1.0 - pow(1.0 - t, TALUS))
	y += _noise_big.get_noise_2d(x * 3.0, 11.0) * RIDGE * sin(PI * t)
	return Vector2(x, y)

## Zbocze wychodni za końcem płyty: powierzchnia z linii profilu ciągniętej w głąb [zf, zb] i płaskie czoło na z = zf (wachlarz od narożnika
## przy gruncie pod końcem płyty).
static func _slope(mesh: ArrayMesh, xe: float, side: float, yt: float, yg: float, w: float, zf: float, zb: float) -> void:
	var nu := maxi(2, int(ceil((w + (yt - yg)) / STEP)))
	var nv := maxi(1, int(ceil(absf(zb - zf) / STEP)))
	var nrm := Vector3(side * (yt - yg), w, 0.0).normalized()
	var pts := []
	for j in nv + 1:
		var row := []
		var z := zf + (zb - zf) * float(j) / nv
		var ez := minf(absf(z - zf), absf(zb - z))
		for i in nu + 1:
			var t := float(i) / nu
			var q := _profile(xe, side, yt, yg, w, t)
			var p := Vector3(q.x, q.y, z)
			var f := smoothstep(0.0, EDGE, ez) * sin(PI * t)
			row.append(p + nrm * (_noise.get_noise_3dv(p) * AMP + _noise_big.get_noise_3dv(p) * AMP_BIG) * f)
		pts.append(row)
	_grid(mesh, pts, nrm)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(xe, yg, zf)
	for i in nu:
		var qa := _profile(xe, side, yt, yg, w, float(i) / nu)
		var qb := _profile(xe, side, yt, yg, w, float(i + 1) / nu)
		_tri(st, c, Vector3(qa.x, qa.y, zf), Vector3(qb.x, qb.y, zf), Vector3.BACK)
	_commit(st, mesh)

## Prostokąt o wierzchołku `o` i bokach `u`, `v` z siatką co STEP, przesunięty wzdłuż `nrm` szumem (`k` — mnożnik nierówności); przy brzegach
## przesunięcie gaśnie (EDGE) — sąsiednie ściany stykają się bez szczelin.
static func _rect(mesh: ArrayMesh, o: Vector3, u: Vector3, v: Vector3, nrm: Vector3, k: float) -> void:
	var nu := maxi(1, int(ceil(u.length() / STEP)))
	var nv := maxi(1, int(ceil(v.length() / STEP)))
	var lu := u.length()
	var lv := v.length()
	var pts := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			var p := o + u * (float(i) / nu) + v * (float(j) / nv)
			var e := minf(minf(float(i) / nu * lu, (1.0 - float(i) / nu) * lu), minf(float(j) / nv * lv, (1.0 - float(j) / nv) * lv))
			var f := smoothstep(0.0, EDGE, e)
			row.append(p + nrm * (_noise.get_noise_3dv(p) * AMP + _noise_big.get_noise_3dv(p) * AMP_BIG) * k * f)
		pts.append(row)
	_grid(mesh, pts, nrm)

## Siatka punktów [wiersz][kolumna] jako osobna powierzchnia siatki (normalne wygładzone tylko w obrębie ściany — wspólne wierzchołki
## z sąsiednią ścianą uśredniały normalne, a od nich zależy mieszanie rzutów tekstury trójpłaszczyznowej: na czole zbocza wychodziła kratka).
static func _grid(mesh: ArrayMesh, pts: Array, nrm: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in pts.size() - 1:
		for i in (pts[j] as Array).size() - 1:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			_tri(st, a, b, c, nrm)
			_tri(st, a, c, d, nrm)
	_commit(st, mesh)

static func _commit(st: SurfaceTool, mesh: ArrayMesh) -> void:
	st.index()
	st.generate_normals()
	st.commit(mesh)

## Trójkąt z przodem po stronie `nrm` (Godot: przód zgodnie z ruchem wskazówek zegara, widziany od przodu); kolor wierzchołka — odcień skały.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var t := b
		b = c
		c = t
	for p: Vector3 in [a, b, c]:
		var k := 0.9 + 0.22 * _noise_col.get_noise_3dv(p)
		var occ := 1.0
		if not _occ.is_empty():
			occ = _occlusion(p)
			k *= lerpf(ALB_DEEP, 1.0, (occ - OCC_DEEP * OCC_CEIL * OCC_SIDE) / (1.0 - OCC_DEEP * OCC_CEIL * OCC_SIDE))
		st.set_color(Color(k, k, k * 0.97, occ))
		st.add_vertex(p)

## Zasłonięcie nieba punktu wnętrza jaskini (1 — otwarte niebo): głębokość za wylotem, bliskość stropu i boków.
static func _occlusion(p: Vector3) -> float:
	var zf: float = _occ["zf"]
	var zd: float = _occ["zd"]
	var yb: float = _occ["yb"]
	var yg: float = _occ["yg"]
	var depth := clampf((zf - p.z) / (zf - zd), 0.0, 1.0)
	var up := clampf((yb - p.y) / (yb - yg), 0.0, 1.0)
	var side := clampf(minf(p.x - float(_occ["x0"]), float(_occ["x1"]) - p.x) / SIDE_W, 0.0, 1.0)
	var occ := lerpf(1.0, OCC_DEEP, pow(depth, 0.6))
	occ *= lerpf(OCC_CEIL, 1.0, smoothstep(0.0, 0.35, up))
	occ *= lerpf(OCC_SIDE, 1.0, smoothstep(0.0, 1.0, side))
	return occ

