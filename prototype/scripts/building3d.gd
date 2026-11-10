extends RefCounted
## Budynki 3D z mapy (wariant C: posterunek i Skład 1.3, hala stacji 1.2, kryjówka; typ w `KINDS`: „bunker” — cały żelbet, „hall” — szkielet z cegłą, „vault” — bunkier w skale). Wpis FRONT z przekrojem i kluczem "build" (`Level3D.buildings`) dostaje bryłę
## w prawdziwych wymiarach zamiast pudeł kafli 1,31 m: płaski stropodach żelbetowy 0,25 m na górze kafla dachu z żebrami i podciągami
## do dolnej krawędzi kafla (Skoczek dalej wisi „pod sufitem”), attyka, ściany szczytowe 0,4 m z pilastrami, cokołem, okapem i oknami
## w głębi, drzwi w ościeżnicach w pasie gry, słupy co 4–6 m (albo w kolumnach z klucza "bays" wpisu) przy ścianie tylnej i w płaszczyźnie przekroju (nie w pasie gry), żelbetowa
## ściana tylna. Wszystko, co przecina płaszczyzna przekroju z = SHELL_Z, ma tam jednolity materiał przekroju (`cut`).
## Tylko widok: kolizja, zniszczenia i pierwszy plan zostają na kaflach mapy. Budowane w warstwie świata, w jednym węźle na budynek.
const Level3D := preload("res://scripts/level3d.gd")

const SLAB := 0.25                         ## m: grubość płyty stropodachu (góra = góra kafla dachu, po której się chodzi)
const WALL := 0.4                          ## m: ściany szczytowe
const BACK := 0.3                          ## m: ściana tylna (lico jak dawny mur tła: z = −2,1)
const COL := 0.4                           ## m: przekrój słupa
const BAY := 5.0                           ## m: docelowy rozstaw słupów (na granicach kafli)
const GIRDER := 0.4                        ## m: szerokość podciągu nad słupami
const RIB := 0.16                          ## m: szerokość żebra stropu (co kafel)
const EAVE := 0.3                          ## m: okap płyty poza lico ścian szczytowych i tylnej
const FASCIA := 0.45                       ## m: wysokość czoła okapu (od góry płyty w dół)
const PARAPET := [0.55, 0.2]               ## m: attyka — wysokość nad dachem i grubość
const ROOF_GAP := [-1.25, 1.35]            ## m: przerwa w bocznej attyce nad pasem gry (wejście na dach z boku)
const PLINTH := [0.55, 0.06, 0.3]          ## m: cokół — wysokość nad podłogą, wysunięcie, zejście pod grunt
const PILASTER := [0.5, 0.12]              ## m: pilaster na licu zewnętrznym — szerokość, wysunięcie
const DOOR_HW := {"door": 0.95, "gate": 1.4, "window": 0.95, "hole": 0.95}   ## m: połowa szerokości otworu w pasie gry (w osi z)
const JAMB := 0.1                          ## m: ościeżnica stalowa
const WIN := [1.0, 2.35, 1.5]              ## m: okno w głębi ściany szczytowej — parapet nad podłogą, nadproże, szerokość
const CUT := 0.012                         ## m: grubość nakładki przekroju przed płaszczyzną SHELL_Z

const CHAMFER := 0.025                     ## m: faza krawędzi brył betonowych (mniejsza przy cienkich elementach)

## Materiały typu budynku: [klucz tekstury (`world_pbr_import.py`: Poly Haven po gradingu gry), powtórzeń na metr, kolor zastępczy, przyciemnienie,
## warstwa brudu (`Level3D.make_pbr`: plamy i zacieki ok. 14 m w rzucie świata, jak na reszcie betonu mapy)].
## Ściany i słupy: warstwy betonowania; płyta i belki: goły beton z panelami; przekrój: gruboziarnisty; cokół: brudny (porównanie 11 kandydatów 2026-11-09).
const KINDS := {
	"bunker": {"wall": ["bld_wall", 0.5, Color(0.30, 0.31, 0.33), 0.9, "stone"], "slab": ["bld_slab", 0.25, Color(0.30, 0.31, 0.33), 0.9, "stone"],
			"back": ["bld_wall", 0.5, Color(0.22, 0.23, 0.24), 0.8, "stone"], "cut": ["bld_cut", 1.0 / 2.4, Color(0.36, 0.35, 0.335), 0.9, ""],
			"plinth": ["bld_plinth", 1.0 / 2.16, Color(0.17, 0.17, 0.18), 0.9, "organic"]},
	# hala (Skład 1.3, hala stacji 1.2): żelbetowy szkielet (słupy, pilastry, strop) z wypełnieniem z cegły — ta sama cegła co mury mapy
	"hall": {"wall": ["wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, "stone"], "col": ["bld_wall", 0.5, Color(0.30, 0.31, 0.33), 0.9, "stone"],
			"slab": ["bld_slab", 0.25, Color(0.30, 0.31, 0.33), 0.9, "stone"], "back": ["wall", 0.7, Color(0.20, 0.20, 0.22), 0.85, "stone"],
			"cut": ["bld_cut", 1.0 / 2.4, Color(0.36, 0.35, 0.335), 0.9, ""], "plinth": ["bld_plinth", 1.0 / 2.16, Color(0.17, 0.17, 0.18), 0.9, "organic"]},
	# bunkier w skale (kryjówka): materiały jak „hall” (żelbetowy szkielet, ciepła cegła ścian — tu jest bezpiecznie), ale zakopany (`buried`):
	# bez okapu, attyki, cokołu, pilastrów i okien; strop z otworami szybów (kafle wiersza dachu poza murem), słupy z dala od otworów w stropie
	# i w podłodze; kondygnacje to osobne wpisy jeden nad drugim (strop dolnej jest podłogą górnej)
	"vault": {"wall": ["wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, "stone"], "col": ["bld_wall", 0.5, Color(0.30, 0.31, 0.33), 0.9, "stone"],
			"slab": ["bld_slab", 0.25, Color(0.30, 0.31, 0.33), 0.9, "stone"], "back": ["wall", 0.7, Color(0.20, 0.20, 0.22), 0.85, "stone"],
			"cut": ["bld_cut", 1.0 / 2.4, Color(0.36, 0.35, 0.335), 0.9, ""], "plinth": ["bld_plinth", 1.0 / 2.16, Color(0.17, 0.17, 0.18), 0.9, "organic"],
			"buried": true},
}
## Klucz części → rola materiału (rola „col” bez wpisu w typie bierze materiał ścian); części z siatką fazowaną i UV na element (`_box_mesh`) — w `SOLO` każda bryła z własnym przesunięciem tekstury
## (słup, belka, pilaster czytają się jako osobne elementy), reszta w UV świata (kawałki muru wokół otworów łączą się bez szwu).
const ROLE := {"wall": "wall", "col": "col", "slab": "slab", "beam": "slab", "back": "back", "plinth": "plinth"}
const SOLO := ["col", "beam"]

## Materiał roli z UV siatki w metrach (`uv1_scale` = powtórzeń na metr), bez rzutowania triplanarnego.
static func _uv_mat(spec: Array) -> Material:
	var m := _tinted(spec)
	m.uv1_triplanar = false
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(float(spec[1]), float(spec[1]), 1.0)
	return m

## Kopia materiału z `make_pbr` (wspólna pamięć podręczna) z przyciemnieniem albedo; warstwa brudu (`next_pass`) zostaje w rzucie świata.
static func _tinted(spec: Array) -> StandardMaterial3D:
	var m := Level3D.make_pbr(String(spec[0]), float(spec[1]), spec[2], 0.95, 1.0, 1.0, false, String(spec[4])).duplicate() as StandardMaterial3D
	var k := float(spec[3])
	m.albedo_color = Color(k, k, k)
	return m

## Wszystkie budynki z ostatniego `Level3D.set_shells`. Zwraca liczbę skrzynek (test).
static func build(parent: Node3D, rows: Array) -> int:
	var n := 0
	for b: Dictionary in Level3D.buildings:
		var node := Node3D.new()
		node.name = "Building3D_%d_%d" % [int(b["c0"]), int(b["r0"])]
		parent.add_child(node)
		n += build_one(node, b, rows)
	return n

## Skrzynki budynku `b` jako {materiał: [Transform3D pudła 1×1×1]} — osobno od budowy węzłów, żeby test sprawdził wymiary bez renderu.
static func parts(b: Dictionary, rows: Array) -> Dictionary:
	var T := Level3D.T
	var c0 := int(b["c0"])
	var c1 := int(b["c1"])
	var x0 := float(c0) * T
	var x1 := float(c1 + 1) * T
	var yf := -float(int(b["r1"])) * T                      # podłoga (góra kafla podłogi)
	var yr := -float(int(b["r0"])) * T                      # góra dachu
	var yc := -float(int(b["r0"]) + 1) * T                  # spód kafla dachu: spód żeber i podciągów
	var ys := yr - SLAB                                     # spód płyty
	var zb := -Level3D.DEPTH_BACK
	var zc := Level3D.SHELL_Z
	var r0 := int(b["r0"])
	var r1 := int(b["r1"])
	var buried := bool((KINDS.get(String(b["kind"]), KINDS["bunker"]) as Dictionary).get("buried", false))
	var solid := func(c: int, r: int) -> bool: return Level3D._ch(rows, c, r) in Level3D.WALL_CH
	var gaps: Array = []                                    # otwory w stropie (szyby, pomosty w wierszu dachu): [x0, x1]
	for c in range(c0, c1 + 1):
		if not solid.call(c, r0):
			if not gaps.is_empty() and is_equal_approx(float(gaps[-1][1]), float(c) * T):
				gaps[-1][1] = float(c + 1) * T
			else:
				gaps.append([float(c) * T, float(c + 1) * T])
	var in_gap := func(xa: float, xb: float) -> bool:
		for g: Array in gaps:
			if xb > float(g[0]) + 0.001 and xa < float(g[1]) - 0.001:
				return true
		return false
	var spans := func(xa: float, xb: float) -> Array:         # odcinki [xa, xb] bez otworów stropu
		var res: Array = []
		var x := xa
		for g: Array in gaps:
			if float(g[0]) > x:
				res.append([x, minf(float(g[0]), xb)])
			x = maxf(x, float(g[1]))
		if x < xb:
			res.append([x, xb])
		return res
	var out := {"wall": [], "col": [], "slab": [], "beam": [], "back": [], "plinth": [], "steel": [], "leaf": [], "glass": [], "cut": []}
	var box := func(key: String, a: Vector3, b2: Vector3) -> void:
		if absf(b2.x - a.x) < 0.001 or absf(b2.y - a.y) < 0.001 or absf(b2.z - a.z) < 0.001:
			return
		(out[key] as Array).append(Level3D._span_box(a, b2))
		if maxf(a.z, b2.z) >= zc - 0.001 and key != "cut":   # przecięte płaszczyzną przekroju: nakładka z materiałem przekroju
			(out["cut"] as Array).append(Level3D._span_box(Vector3(a.x, a.y, zc), Vector3(b2.x, b2.y, zc + CUT)))
	# stropodach: płyta z okapem, czoło okapu, attyka (z przerwą w bokach nad pasem gry); w skale sama płyta między ścianami, z otworami
	if buried:
		for sp: Array in spans.call(x0, x1):
			box.call("slab", Vector3(float(sp[0]), ys, zb), Vector3(float(sp[1]), yr, zc))
	else:
		box.call("slab", Vector3(x0 - EAVE, ys, zb - EAVE), Vector3(x1 + EAVE, yr, zc))
	for sx in ([] if buried else [-1.0, 1.0]):
		var xe := x0 - EAVE if sx < 0.0 else x1 + EAVE
		box.call("slab", Vector3(xe, yr - FASCIA, zb - EAVE), Vector3(xe - sx * 0.12, ys, zc))
		for seg in [[zb - EAVE, ROOF_GAP[0]], [ROOF_GAP[1], zc]]:
			box.call("slab", Vector3(xe, yr, float(seg[0])), Vector3(xe - sx * PARAPET[1], yr + PARAPET[0], float(seg[1])))
	if not buried:
		box.call("slab", Vector3(x0 - EAVE, yr - FASCIA, zb - EAVE), Vector3(x1 + EAVE, yr + PARAPET[0], zb - EAVE + PARAPET[1]))
		box.call("slab", Vector3(x0 - EAVE, yr, zc - PARAPET[1]), Vector3(x1 + EAVE, yr + PARAPET[0], zc))
	# słupy i podciągi: linie na granicach kafli co ok. BAY
	var ncols := c1 - c0 + 1
	var nbay := maxi(1, roundi((x1 - x0) / BAY))
	var lines: Array = []
	for bc in b.get("bays", []):                             # wpis z kluczem "bays": słupy na granicach pomieszczeń (lewa krawędź kolumny mapy)
		lines.append(float(int(bc)) * T)
	if b.has("bays"):
		nbay = 0
	for i in range(1, nbay):
		var kk := roundi(float(i) * float(ncols) / float(nbay))
		for dk in [0, 1, -1, 2, -2]:                         # granica kafli bez otworu wnęki po żadnej stronie (słup zasłoniłby wnękę)
			var g: int = kk + dk
			var free := g > 1 and g < ncols - 1
			for r in range(int(b["r0"]) + 1, int(b["r1"])):
				free = free and not Level3D.niche_cells.has(Vector2i(c0 + g - 1, r)) and not Level3D.niche_cells.has(Vector2i(c0 + g, r))
			if buried:                                         # w skale: słup nie pod otworem stropu ani nad otworem podłogi (szyb)
				for rr in [r0, r1]:
					free = free and solid.call(c0 + g - 1, rr) and solid.call(c0 + g, rr)
			if free:
				lines.append(x0 + float(g) * T)
				break
	var zin := zb + BACK
	for x: float in lines:
		box.call("col", Vector3(x - COL * 0.5, yf, zin), Vector3(x + COL * 0.5, yc, zin + COL))          # słup przy ścianie tylnej
		box.call("col", Vector3(x - COL * 0.5, yf, zc - COL), Vector3(x + COL * 0.5, yc, zc))           # słup w płaszczyźnie przekroju (wariant A)
		box.call("beam", Vector3(x - GIRDER * 0.5, yc, zin), Vector3(x + GIRDER * 0.5, ys, zc))         # podciąg w głąb
		for zz in [zin + COL, zc - COL]:                             # wuty pod podciągiem przy słupach
			var zd := 0.45 if zz < 0.0 else -0.45
			box.call("beam", Vector3(x - COL * 0.5, yc - 0.3, minf(zz, zz + zd)), Vector3(x + COL * 0.5, yc, maxf(zz, zz + zd)))
	# podciąg wzdłuż ściany tylnej; w płaszczyźnie przekroju bez podciągu — pas 1,3 m nad salą zasłaniał strop z żebrami
	for sp: Array in spans.call(x0 + WALL, x1 - WALL):
		box.call("beam", Vector3(float(sp[0]), yc, zin), Vector3(float(sp[1]), ys, zin + 0.35))
	# żebra stropu co kafel (poza liniami podciągów)
	for k in range(1, ncols):
		var x := x0 + float(k) * T
		var near := false
		for lx: float in lines:
			near = near or absf(lx - x) < 0.5
		if not near and not in_gap.call(x - RIB, x + RIB):
			box.call("beam", Vector3(x - RIB * 0.5, yc, zin + 0.35), Vector3(x + RIB * 0.5, ys, zc))
	# ściana tylna: w wierszach pasa ciągi kafli ze ścianą tła (`Level3D.back_wall_at` — bez otworów wnęk), nad nimi pełny pas pod płytę
	var xl := x0 + WALL
	var xr := x1 - WALL
	for r in range(int(b["r0"]) + 1, int(b["r1"])):
		var y_hi := ys if r == int(b["r0"]) + 1 else -float(r) * T
		var at := func(cc: int) -> bool:                     # tło albo kafel ściany szczytowej (za nim lico ściany tylnej dochodzi do ściany 0,4 m)
			return Level3D.back_wall_at(rows, cc, r) or Level3D.bld_cells.has(Vector2i(cc, r))
		var k := c0
		while k <= c1:
			if not at.call(k):
				k += 1
				continue
			var k1 := k
			while k1 + 1 <= c1 and at.call(k1 + 1):
				k1 += 1
			box.call("back", Vector3(maxf(float(k) * T, xl), -float(r + 1) * T, zb), Vector3(minf(float(k1 + 1) * T, xr), y_hi, zin))
			k = k1 + 1
	# ściany szczytowe z otworami (pas gry) i oknami w głębi
	for side in [-1, 1]:
		var xo := x0 if side < 0 else x1                    # lico zewnętrzne
		var xi := xo - float(side) * WALL                   # lico wewnętrzne
		var holes: Array = []                               # [z0, z1, y0, y1, rodzaj]
		var doors: Array = []
		for o: Dictionary in b["open"]:
			if int(o["side"]) != side:
				continue
			var hw: float = DOOR_HW.get(String(o["kind"]), 0.95)
			var h := [-hw, hw, -float(int(o["rb"]) + 1) * T, minf(-float(int(o["rt"])) * T, ys), String(o["kind"])]
			holes.append(h)
			if String(o["kind"]) in ["door", "gate"]:
				doors.append(h)
		var front0: float = ROOF_GAP[1] + 0.2
		var wlen := zc - COL - front0
		if wlen >= WIN[2] + 0.8 and not buried:                            # okno w odcinku ściany przed pasem gry
			var wz := front0 + wlen * 0.5
			holes.append([wz - WIN[2] * 0.5, wz + WIN[2] * 0.5, yf + WIN[0], yf + WIN[1], "deco"])
		_wall_x(box, "wall", minf(xo, xi), maxf(xo, xi), zb, zc, yf, ys, holes)
		for h: Array in holes:
			_frame(box, side, xo, xi, h)
		if buried:
			continue                                         # w skale: lico zewnętrzne niewidoczne, bez cokołu i pilastrów
		var xout := func(d: float) -> float: return xo + float(side) * d     # x w odległości d na zewnątrz lica
		# cokół (bez progów drzwi), pilastry przy narożniku tylnym i obok drzwi
		var pz: Array = [zb]
		for h: Array in doors:
			pz.append_array([float(h[0]), float(h[1])])
		pz.append(zc)
		for i in range(0, pz.size(), 2):
			box.call("plinth", Vector3(xo, yf - PLINTH[2], float(pz[i])), Vector3(xout.call(PLINTH[1]), yf + PLINTH[0], float(pz[i + 1])))
		var pil: Array = [zb + PILASTER[0] * 0.5]
		for h: Array in doors:
			pil.append_array([float(h[0]) - JAMB - 0.35, float(h[1]) + JAMB + 0.35])
		for z: float in pil:
			box.call("col", Vector3(xo, yf + PLINTH[0], z - PILASTER[0] * 0.5), Vector3(xout.call(PILASTER[1]), ys, z + PILASTER[0] * 0.5))
	return out

## Ściana w płaszczyźnie y-z (x od xa do xb) z prostokątnymi otworami [z0, z1, y0, y1, …]: pasy między kolejnymi krawędziami otworów w z,
## w każdym pasie mur pod, między i nad otworami.
static func _wall_x(box: Callable, key: String, xa: float, xb: float, z0: float, z1: float, y0: float, y1: float, holes: Array) -> void:
	var zs: Array = [z0, z1]
	for h: Array in holes:
		zs.append_array([clampf(float(h[0]), z0, z1), clampf(float(h[1]), z0, z1)])
	zs.sort()
	for i in zs.size() - 1:
		var za: float = zs[i]
		var zb: float = zs[i + 1]
		if zb - za < 0.001:
			continue
		var gaps: Array = []
		for h: Array in holes:
			if float(h[0]) < zb - 0.001 and float(h[1]) > za + 0.001:
				gaps.append([float(h[2]), float(h[3])])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var y := y0
		for g: Array in gaps:
			if float(g[0]) > y:
				box.call(key, Vector3(xa, y, za), Vector3(xb, float(g[0]), zb))
			y = maxf(y, float(g[1]))
		if y < y1:
			box.call(key, Vector3(xa, y, za), Vector3(xb, y1, zb))

## Ościeżnica otworu (stal na całą grubość muru z wysunięciem po obu licach), skrzydła drzwi otwarte na lico zewnętrzne, okno w głębi
## z szybą, szprosem i parapetem.
static func _frame(box: Callable, side: int, xo: float, xi: float, h: Array) -> void:
	var z0: float = h[0]
	var z1: float = h[1]
	var y0: float = h[2]
	var y1: float = h[3]
	var kind: String = h[4]
	var xa := minf(xo, xi) - 0.04
	var xb := maxf(xo, xi) + 0.04
	box.call("steel", Vector3(xa, y0, z0 - JAMB), Vector3(xb, y1 + JAMB, z0))
	box.call("steel", Vector3(xa, y0, z1), Vector3(xb, y1 + JAMB, z1 + JAMB))
	box.call("steel", Vector3(xa, y1, z0 - JAMB), Vector3(xb, y1 + JAMB, z1 + JAMB))
	var s := float(side)
	match kind:
		"door", "gate":
			var hgt := minf(y1 - y0 - 0.05, 2.2 if kind == "door" else 3.4)
			var w := (z1 - z0) * 0.5
			for zz in [[z1 + JAMB + 0.02, z1 + JAMB + 0.02 + w], [z0 - JAMB - 0.02 - w, z0 - JAMB - 0.02]]:   # dwa skrzydła na licu zewnętrznym
				box.call("leaf", Vector3(xo + s * 0.02, y0, float(zz[0])), Vector3(xo + s * 0.07, y0 + hgt, float(zz[1])))
				for yy in [0.5, hgt - 0.5]:                      # przetłoczenia skrzydła
					box.call("leaf", Vector3(xo + s * 0.07, y0 + yy - 0.03, float(zz[0]) + 0.1), Vector3(xo + s * 0.09, y0 + yy + 0.03, float(zz[1]) - 0.1))
		"deco", "window":
			var xm := (xo + xi) * 0.5
			var ym := (y0 + y1) * 0.5
			var zm := (z0 + z1) * 0.5
			if kind == "deco":
				box.call("glass", Vector3(xm - 0.015, y0, z0), Vector3(xm + 0.015, y1, z1))
			box.call("steel", Vector3(xm - 0.04, y0, zm - 0.03), Vector3(xm + 0.04, y1, zm + 0.03))
			box.call("steel", Vector3(xm - 0.04, ym - 0.03, z0), Vector3(xm + 0.04, ym + 0.03, z1))
			var xp := xo + s * 0.1
			box.call("plinth", Vector3(minf(xo - s * 0.1, xp), y0 - 0.08, z0 - 0.15), Vector3(maxf(xo - s * 0.1, xp), y0, z1 + 0.15))   # parapet z kapinosem

static func build_one(parent: Node3D, b: Dictionary, rows: Array) -> int:
	var spec: Dictionary = KINDS.get(String(b["kind"]), KINDS["bunker"])
	var cs: Array = spec["cut"]
	var mats := {
		"steel": Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
		"leaf": Level3D.make_pbr("metal", 0.40, Color(0.22, 0.24, 0.22), 0.55, 1.0, 0.7, false, "rust"),
		"glass": Level3D.make_mat(Color(0.03, 0.035, 0.04), 0.12, 0.06, 0.0),
		"cut": _tinted(cs),   # przekrój: rzut świata — płaszczyzna cięcia jak jeden blok betonu
	}
	for k: String in ROLE:
		mats[k] = _uv_mat(spec.get(ROLE[k], spec["wall"]))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var p := parts(b, rows)
	var n := 0
	for k: String in p:
		n += (p[k] as Array).size()
		if (p[k] as Array).is_empty():
			continue
		if ROLE.has(k):
			var mi := MeshInstance3D.new()
			mi.name = k
			mi.mesh = _box_mesh(p[k], k in SOLO)
			mi.material_override = mats[k]
			parent.add_child(mi)
		else:
			Level3D._multimesh(parent, unit, p[k], mats[k], k != "cut" and k != "glass")
	return n

## Bryły (Transform3D pudła 1×1×1, osiowe) jako jedna siatka: skrzynki z fazą CHAMFER na wszystkich krawędziach (normalne fazy przechodzą
## płynnie między licami — krawędź łapie światło jak zaokrąglony beton), UV w metrach: lica pionowe — poziomo × w dół, poziome — x × z.
## `solo`: każda bryła z własnym przesunięciem tekstury (z jej położenia), inaczej UV świata.
static func _box_mesh(xfs: Array, solo: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for xf: Transform3D in xfs:
		var h := xf.basis.get_scale() * 0.5
		var o := xf.origin
		var c := minf(CHAMFER, minf(h.x, minf(h.y, h.z)) * 0.5)
		var off := Vector2.ZERO
		if solo:
			off = Vector2(fposmod(o.x * 3.17 + o.z * 1.31, 7.0), fposmod(o.y * 2.29 + o.x * 0.77, 7.0))
		for a in 3:
			var ea := Vector3.ZERO
			ea[a] = 1.0
			var b1 := (a + 1) % 3
			var d1 := (a + 2) % 3
			for s in [-1.0, 1.0]:
				var q: Array = []
				for cc in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
					var p := Vector3.ZERO
					p[a] = s * h[a]
					p[b1] = float(cc[0]) * (h[b1] - c)
					p[d1] = float(cc[1]) * (h[d1] - c)
					q.append([p, ea * s])
				_quad(st, o, off, q, a)
			if c <= 0.0:
				continue
			# fazy wzdłuż osi d1 między licem (a, s) i licem (b1, t)
			var eb := Vector3.ZERO
			eb[b1] = 1.0
			for s in [-1.0, 1.0]:
				for t in [-1.0, 1.0]:
					var q: Array = []
					for dd in [-1.0, 1.0]:
						var p1 := Vector3.ZERO
						p1[a] = s * h[a]
						p1[b1] = t * (h[b1] - c)
						p1[d1] = dd * (h[d1] - c)
						q.append([p1, ea * s])
					for dd in [1.0, -1.0]:
						var p2 := Vector3.ZERO
						p2[a] = s * (h[a] - c)
						p2[b1] = t * h[b1]
						p2[d1] = dd * (h[d1] - c)
						q.append([p2, eb * t])
					_quad(st, o, off, q, a)
		if c > 0.0:
			for sx in [-1.0, 1.0]:                                      # narożniki
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var sg := Vector3(sx, sy, sz)
						var pts: Array = []
						for a in 3:
							var p := Vector3(sx * (h.x - c), sy * (h.y - c), sz * (h.z - c))
							p[a] = sg[a] * h[a]
							var nn := Vector3.ZERO
							nn[a] = sg[a]
							pts.append([p, nn])
						_tri(st, o, off, pts[0], pts[1], pts[2], 1)
	st.generate_tangents()
	return st.commit()

static func _quad(st: SurfaceTool, o: Vector3, off: Vector2, q: Array, face: int) -> void:
	_tri(st, o, off, q[0], q[1], q[2], face)
	_tri(st, o, off, q[0], q[2], q[3], face)

## Trójkąt z [punkt lokalny, normalna] ×3; front Godota = zgodnie z ruchem wskazówek zegara patrząc od strony normalnej.
static func _tri(st: SurfaceTool, o: Vector3, off: Vector2, a: Array, b: Array, d: Array, face: int) -> void:
	var n: Vector3 = (a[1] as Vector3) + (b[1] as Vector3) + (d[1] as Vector3)
	var v := [a, b, d]
	if ((b[0] as Vector3) - (a[0] as Vector3)).cross((d[0] as Vector3) - (a[0] as Vector3)).dot(n) > 0.0:
		v = [a, d, b]
	for e: Array in v:
		var w: Vector3 = o + (e[0] as Vector3)
		var uv := Vector2(w.x, w.z) if face == 1 else (Vector2(w.z, -w.y) if face == 0 else Vector2(w.x, -w.y))
		st.set_normal(e[1])
		st.set_uv(uv + off)
		st.add_vertex(w)

