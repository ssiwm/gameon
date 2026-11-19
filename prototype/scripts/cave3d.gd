extends RefCounted
## Skalne nawisy widoku 3D (przegląd budynków 2026-11-19): płyta litej skały wisząca nad ścieżką w lesie (1.1 „jaskinia pod skalnym
## sufitem”) w 3D była blokiem gruntu lasu w powietrzu, z lasem za i pod nim. Wychodnia skalna z wydrążeniem: kafle płyty w materiale
## skały (`Level3D.rock_rects`), za płaszczyzną gry strop jaskini w głąb, tylna ściana, boki i zbocza wychodni schodzące do gruntu po obu
## końcach płyty. Czysta oprawa: bez kolizji, wpływu na wzrok wrogów, hałas i Uwagę; mapa ASCII, ścieżka i nawigacja bez zmian.
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

static var _noise: FastNoiseLite
static var _noise_big: FastNoiseLite
static var _noise_col: FastNoiseLite
static var _mat: Material

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
		# wnętrze: strop (spód płyty w głąb), tylna ściana, boki
		_rect(mesh, Vector3(x0, yb, zf), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, 0.0, zd - zf), Vector3.DOWN, 1.0)
		_rect(mesh, Vector3(x0, yg, zd), Vector3(x1 - x0, 0.0, 0.0), Vector3(0.0, yb - yg, 0.0), Vector3.BACK, 1.0)
		_rect(mesh, Vector3(x0, yg, zf), Vector3(0.0, 0.0, zd - zf), Vector3(0.0, yb - yg, 0.0), Vector3.RIGHT, 0.6)
		_rect(mesh, Vector3(x1, yg, zf), Vector3(0.0, 0.0, zd - zf), Vector3(0.0, yb - yg, 0.0), Vector3.LEFT, 0.6)
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
		st.set_color(Color(k, k, k * 0.97))
		st.add_vertex(p)

