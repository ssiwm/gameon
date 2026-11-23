extends RefCounted
## Strażnica 1.1 jako jedna konstrukcja 3D (TOWER_PLAN.md) zamiast ogólnych nóg wieży (`Backdrop3D.build_frames`), dachu i podłogi z wiązarów
## (`Level3D._build_roofs`, `tower_slabs`) i nóg pod podestami (`deck_supports`) — te pomijają kafle wpisu (`Level3D.tower_skip`). Tylko widok:
## kafle, kolizja i trasa bez zmian. Dane z `WATCHTOWER` mapy: {"c0", "c1" — kolumny nóg, "roof" — wiersz dachu, "floor" — wiersz podłogi kabiny,
## "ground" — wiersz gruntu}. Podesty zygzaka to kładki `-` między nogami pod kabiną (szukane w mapie). Dev `--oldtower`: stara strażnica
## z ogólnych reguł (porównania), `--towerlit`: światło podglądowe do zrzutów akceptacji.
##
## Bryła: cztery nogi z bali z rozstawem u dołu na betonowych stopach; oczepy pod każdym podestem z tyłu i po bokach, krzyże stężeń w tylnej
## i bocznych płaszczyznach (przód zostaje otwarty — gra toczy się w płaszczyźnie z = 0); podesty na legarach z poręczą z tyłu, między nimi
## strome drabiny schodowe za płaszczyzną gry; kabina z desek z pasem okien (z tyłu i z boków), przód jak w przekroju — tylko podwalina
## i oczep; dach czterospadowy z papy z okapem, belki stropu pod nim (tam wiszą Ćmy i Skoczek).

const Level3D := preload("res://scripts/level3d.gd")
const T := Level3D.T

const LEG := 0.32                     ## m: przekrój nogi
const BRACE := 0.14                   ## m: stężenia
const GIRT := 0.2                     ## m: oczepy
const Z_BACK := -2.1                  ## m: tylne nogi (za ścianą kabiny)
const Z_FRONT := 0.85                 ## m: przednie nogi (przed pokładem podestów, za krawędzią bryły)
const SPLAY_X := 1.0                  ## m: rozstaw nóg u dołu na zewnątrz w osi x
const SPLAY_Z := 0.7                  ## m: rozstaw tylnych nóg u dołu w głąb
const SILL := 1.0                     ## m: wysokość parapetu okien kabiny nad podłogą
const WIN_TOP := 2.6                  ## m: nadproże pasa okien (wysokie okna: pas nad nimi i spód dachu nie zasłaniają pół kabiny w kadrze z gry)
const EAVE := 0.5                     ## m: okap dachu poza obrysem nóg
const RIDGE_H := 1.35                 ## m: kalenica nad belkami stropu
const LADDER_Z := -0.45               ## m: oś drabin między podestami (za postaciami)
const LADDER_W := 0.62
const BEAM_H := 0.2                   ## m: wysokość belek stropu (górą na spodzie kafla dachu)

## Strażnica z ogólnych reguł zamiast tej (dev `--oldtower`, porównania przed / po).
static func disabled() -> bool:
	return "--oldtower" in OS.get_cmdline_user_args()

## Prostokąt kafli strażnicy (do pomijania starej geometrii w `Level3D` / `Backdrop3D`).
static func rect(d: Dictionary) -> Rect2i:
	return Rect2i(int(d["c0"]) - 1, int(d["roof"]), int(d["c1"]) - int(d["c0"]) + 3, int(d["ground"]) - int(d["roof"]) + 1)

static func _ch(rows: Array, c: int, r: int) -> String:
	if r < 0 or r >= rows.size() or c < 0 or c >= String(rows[r]).length():
		return ""
	return String(rows[r])[c]

## Podesty `-` między nogami pod podłogą kabiny: [{"r", "c0", "c1"}] od dołu.
static func landings(rows: Array, d: Dictionary) -> Array:
	var out: Array = []
	for r in range(int(d["ground"]) - 1, int(d["floor"]), -1):
		var c := int(d["c0"]) + 1
		while c < int(d["c1"]):
			if _ch(rows, c, r) == "-":
				var c1 := c
				while _ch(rows, c1 + 1, r) == "-" and c1 + 1 < int(d["c1"]):
					c1 += 1
				out.append({"r": r, "c0": c, "c1": c1})
				c = c1 + 1
			else:
				c += 1
	return out

## Wysokości charakterystyczne (m): grunt, wierzch i spód kafla podłogi kabiny, spód kafla dachu (belki stropu).
static func levels_of(d: Dictionary) -> Dictionary:
	return {"ground": -float(d["ground"]) * T, "floor": -float(d["floor"]) * T, "floor_bot": -float(int(d["floor"]) + 1) * T,
		"ceil": -float(int(d["roof"]) + 1) * T, "xl": (float(d["c0"]) + 0.5) * T, "xr": (float(d["c1"]) + 0.5) * T}

## Punkt na osi nogi na wysokości y: prosto w kabinie, niżej z rozstawem na zewnątrz (x) i w głąb (z, tylko tylne).
static func leg_at(d: Dictionary, side: float, front: bool, y: float) -> Vector3:
	var lv := levels_of(d)
	var y_fb: float = lv["floor_bot"]
	var y_g: float = lv["ground"]
	var t := clampf((y_fb - y) / (y_fb - y_g), 0.0, 1.0)            # 0 pod podłogą kabiny, 1 przy gruncie
	var x: float = (float(lv["xl"]) if side < 0.0 else float(lv["xr"])) + side * SPLAY_X * t
	var z := Z_FRONT if front else Z_BACK - SPLAY_Z * t
	return Vector3(x, y, z)

## Części konstrukcji jako przekształcenia pudła 1×1×1, wg roli (test `tools/test_watchtower.gd` sprawdza je osobno):
## "legs", "footings", "girts", "braces", "joists" (legary i obrzeża podestów), "rails" (poręcze podestów), "ladders", "floor", "walls",
## "front" (oczep i podwalina z przodu kabiny), "beams" (belki stropu), "fascia"; "roof": [okap lo, okap hi, y kalenicy].
static func parts(rows: Array, d: Dictionary) -> Dictionary:
	var p := {}
	for k in ["legs", "footings", "girts", "braces", "joists", "rails", "ladders", "floor", "walls", "front", "beams", "fascia"]:
		p[k] = []
	var lv := levels_of(d)
	var xl: float = lv["xl"]
	var xr: float = lv["xr"]
	var y_g: float = lv["ground"]
	var y_f: float = lv["floor"]
	var y_fb: float = lv["floor_bot"]
	var y_c: float = lv["ceil"]
	var deck_h: float = float(Level3D.DECK_H["-"]) * T
	var dh := Level3D.deck_half("-")
	for side in [-1.0, 1.0]:
		for fr in [false, true]:
			var a := leg_at(d, side, fr, y_g - 0.3)
			var b := leg_at(d, side, fr, y_fb)
			p["legs"].append(Level3D._strut(a, b, LEG))
			p["legs"].append(Level3D._strut(b, Vector3(b.x, y_c + BEAM_H, b.z), LEG))
			p["footings"].append(Level3D._span_box(Vector3(a.x - 0.45, y_g - 0.2, a.z - 0.45), Vector3(a.x + 0.45, y_g + 0.28, a.z + 0.45)))
	# poziomy oczepów: przy gruncie, pod każdym podestem, pod podłogą kabiny
	var lands := landings(rows, d)
	var levels: Array = [y_g + 0.45]
	for l in lands:
		var yl := -float(int(l["r"])) * T - deck_h - GIRT * 0.5
		if absf(yl - float(levels[-1])) > 1.0:
			levels.append(yl)
	levels.append(y_fb + 0.05)
	for i in levels.size():
		var y: float = levels[i]
		var bl := leg_at(d, -1.0, false, y)
		var br := leg_at(d, 1.0, false, y)
		var fl := leg_at(d, -1.0, true, y)
		var frr := leg_at(d, 1.0, true, y)
		p["girts"].append(Level3D._strut(bl, br, GIRT))                  # tył
		p["girts"].append(Level3D._strut(bl, fl, GIRT))                  # boki
		p["girts"].append(Level3D._strut(br, frr, GIRT))
	# podwalina z przodu tuż pod deskami podłogi kabiny (niżej, na spodzie kafla podłogi, przecinała głowę postaci na najwyższym podeście);
	# przy gruncie i pod podestami przodu brak — przecinałby postacie
	p["front"].append(Level3D._strut(leg_at(d, -1.0, true, y_f - 0.3), leg_at(d, 1.0, true, y_f - 0.3), GIRT))
	# krzyże stężeń: co dwa poziomy, tył w dwóch przęsłach, boki w jednym
	var cross_lv: Array = [levels[0]]
	for i in range(2, levels.size() - 1, 2):
		cross_lv.append(levels[i])
	if float(cross_lv[-1]) != float(levels[-1]):
		cross_lv.append(levels[-1])
	for i in cross_lv.size() - 1:
		var ya: float = cross_lv[i]
		var yb: float = cross_lv[i + 1]
		for bay in 2:
			var u0 := float(bay) * 0.5
			var u1 := u0 + 0.5
			var p0 := leg_at(d, -1.0, false, ya).lerp(leg_at(d, 1.0, false, ya), u0)
			var p1 := leg_at(d, -1.0, false, ya).lerp(leg_at(d, 1.0, false, ya), u1)
			var q0 := leg_at(d, -1.0, false, yb).lerp(leg_at(d, 1.0, false, yb), u0)
			var q1 := leg_at(d, -1.0, false, yb).lerp(leg_at(d, 1.0, false, yb), u1)
			p["braces"].append(Level3D._strut(p0, q1, BRACE))
			p["braces"].append(Level3D._strut(p1, q0, BRACE))
		for side in [-1.0, 1.0]:
			p["braces"].append(Level3D._strut(leg_at(d, side, false, ya), leg_at(d, side, true, yb), BRACE))
			p["braces"].append(Level3D._strut(leg_at(d, side, true, ya), leg_at(d, side, false, yb), BRACE))
	# podesty: legary od tylnego oczepu do przodu, obrzeże z przodu, poręcz z tyłu; drabiny schodowe między kolejnymi podestami
	var prev: Dictionary = {}
	for l in lands:
		var r: int = l["r"]
		var x0 := float(int(l["c0"])) * T
		var x1 := float(int(l["c1"]) + 1) * T
		var y_top := -float(r) * T
		var y_un := y_top - deck_h
		var zb := leg_at(d, -1.0, false, y_un - GIRT * 0.5).z
		for x in [x0 + 0.15, (x0 + x1) * 0.5, x1 - 0.15]:
			p["joists"].append(Level3D._span_box(Vector3(float(x) - 0.07, y_un - 0.2, zb), Vector3(float(x) + 0.07, y_un, dh + 0.02)))
		p["joists"].append(Level3D._span_box(Vector3(x0, y_un - 0.18, dh - 0.02), Vector3(x1, y_un, dh + 0.06)))     # obrzeże z przodu, pod deskami
		for x in [x0 + 0.08, x1 - 0.08]:                                                                            # poręcz z tyłu podestu
			p["rails"].append(Level3D._span_box(Vector3(float(x) - 0.05, y_top, -dh - 0.12), Vector3(float(x) + 0.05, y_top + 1.05, -dh - 0.02)))
		p["rails"].append(Level3D._span_box(Vector3(x0, y_top + 0.95, -dh - 0.13), Vector3(x1, y_top + 1.05, -dh - 0.01)))
		p["rails"].append(Level3D._span_box(Vector3(x0, y_top + 0.5, -dh - 0.11), Vector3(x1, y_top + 0.57, -dh - 0.03)))
		var from: Vector3
		if prev.is_empty():                                         # z gruntu: obok podestu, po stronie środka wieży
			var xa := x1 + T * 0.55 if float(int(l["c0"])) - float(d["c0"]) < 3.0 else x0 - T * 0.55
			from = Vector3(xa, y_g, LADDER_Z)
		else:
			var px0 := float(int(prev["c0"])) * T
			var px1 := float(int(prev["c1"]) + 1) * T
			from = Vector3(px1 if px1 < x0 else px0, -float(int(prev["r"])) * T, LADDER_Z)
		_ladder(p["ladders"], from, Vector3(x0 if from.x < x0 else x1, y_top, LADDER_Z))
		prev = l
	if not prev.is_empty():                                         # ostatni podest → właz w podłodze kabiny
		var px1 := float(int(prev["c1"]) + 1) * T
		_ladder(p["ladders"], Vector3(px1, -float(int(prev["r"])) * T, LADDER_Z), Vector3(px1 + 0.5, y_f, LADDER_Z))
	# podłoga kabiny: belki w poprzek, deski poza włazem (kafle `-` w wierszu podłogi zostają kładką z modelu)
	for c in range(int(d["c0"]), int(d["c1"]) + 1):
		var x := float(c) * T
		p["floor"].append(Level3D._span_box(Vector3(x + 0.05, y_f - 0.42, Z_BACK), Vector3(x + 0.25, y_f - 0.12, Z_FRONT + 0.1)))
		if _ch(rows, c, int(d["floor"])) == "-":
			p["floor"].append(Level3D._span_box(Vector3(x, y_f - 0.1, Z_BACK - 0.1), Vector3(x + T, y_f, -dh - 0.02)))
			p["floor"].append(Level3D._span_box(Vector3(x, y_f - 0.1, dh + 0.02), Vector3(x + T, y_f, Z_FRONT + 0.15)))
		else:
			p["floor"].append(Level3D._span_box(Vector3(x, y_f - 0.1, Z_BACK - 0.1), Vector3(x + T, y_f, Z_FRONT + 0.15)))
	p["floor"].append(Level3D._span_box(Vector3(xl - 0.4, y_f - 0.1, Z_BACK - 0.1), Vector3(float(int(d["c0"])) * T, y_f, Z_FRONT + 0.15)))
	p["floor"].append(Level3D._span_box(Vector3(float(int(d["c1"]) + 1) * T, y_f - 0.1, Z_BACK - 0.1), Vector3(xr + 0.4, y_f, Z_FRONT + 0.15)))
	# kabina: ściana tylna i boczne z desek z pasem okien, słupki okienne, okiennice; przód otwarty (przekrój)
	var wz := Z_BACK + 0.2
	var wx0 := xl - 0.2
	var wx1 := xr + 0.2
	var y_sill := y_f + SILL
	var y_win := minf(y_f + WIN_TOP, y_c - 0.3)
	p["walls"].append(Level3D._span_box(Vector3(wx0, y_f, wz - 0.06), Vector3(wx1, y_sill, wz)))
	p["walls"].append(Level3D._span_box(Vector3(wx0, y_win, wz - 0.06), Vector3(wx1, y_c, wz)))
	p["walls"].append(Level3D._span_box(Vector3(wx0, y_sill - 0.06, wz - 0.06), Vector3(wx1, y_sill + 0.04, wz + 0.18)))    # parapet
	var nwin := maxi(int(round((wx1 - wx0) / 1.6)), 2)
	for i in nwin + 1:
		var x := lerpf(wx0, wx1, float(i) / float(nwin))
		p["walls"].append(Level3D._span_box(Vector3(x - 0.06, y_sill, wz - 0.07), Vector3(x + 0.06, y_win, wz + 0.01)))
	for i in nwin:                                                  # okiennice: część zamknięta, część wisi krzywo (z ziarna kolumny)
		var xa := lerpf(wx0, wx1, float(i) / float(nwin)) + 0.07
		var xb := lerpf(wx0, wx1, float(i + 1) / float(nwin)) - 0.07
		var hsh := hash(Vector2i(int(d["c0"]), i)) % 5
		if hsh == 0:
			p["walls"].append(Level3D._span_box(Vector3(xa, y_sill, wz - 0.05), Vector3(xb, y_win, wz - 0.01)))
		elif hsh == 1:
			p["walls"].append(Level3D._strut(Vector3(xa + 0.3, y_sill + 0.05, wz - 0.03), Vector3(xa + 0.15, y_win - 0.05, wz - 0.03), (xb - xa) * 0.45))
	for side in [-1.0, 1.0]:
		var x: float = wx0 if side < 0.0 else wx1
		var x_in: float = x - side * 0.06
		p["walls"].append(Level3D._span_box(Vector3(minf(x, x_in), y_f, wz), Vector3(maxf(x, x_in), y_sill, Z_FRONT)))
		p["walls"].append(Level3D._span_box(Vector3(minf(x, x_in), y_win, wz), Vector3(maxf(x, x_in), y_c, Z_FRONT)))
		p["walls"].append(Level3D._span_box(Vector3(x - 0.06, y_sill, (wz + Z_FRONT) * 0.5 - 0.06), Vector3(x + 0.06, y_win, (wz + Z_FRONT) * 0.5 + 0.06)))
	p["front"].append(Level3D._span_box(Vector3(wx0, y_c - 0.28, Z_FRONT - 0.12), Vector3(wx1, y_c, Z_FRONT + 0.12)))     # oczep z przodu
	# belki stropu (w poprzek) górą na spodzie kafla dachu
	var nb := int((xr - xl) / 1.3)
	for i in nb + 1:
		var x := lerpf(xl, xr, float(i) / float(nb))
		p["beams"].append(Level3D._span_box(Vector3(x - 0.08, y_c - BEAM_H, Z_BACK), Vector3(x + 0.08, y_c, Z_FRONT)))
	var lo := Vector3(xl - EAVE, y_c, Z_BACK - EAVE)
	var hi := Vector3(xr + EAVE, y_c, Z_FRONT + EAVE)
	p["roof"] = [lo, hi, y_c + RIDGE_H]
	var ea := [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z)]
	for i in 4:                                                     # deska okapowa dookoła
		p["fascia"].append(Level3D._strut(ea[i] + Vector3(0, -0.1, 0), ea[(i + 1) % 4] + Vector3(0, -0.1, 0), 0.2))
	return p

static func build(parent: Node3D, rows: Array, d: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Watchtower"
	parent.add_child(root)
	var p := parts(rows, d)
	var wood: Array = []
	for k in ["legs", "girts", "braces", "joists", "front", "beams"]:
		wood.append_array(p[k])
	var boards: Array = []
	for k in ["rails", "ladders", "floor", "walls", "fascia"]:
		boards.append_array(p[k])
	var box := BoxMesh.new()
	var post := Level3D.make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic").duplicate() as StandardMaterial3D
	post.albedo_color = Color(0.5, 0.44, 0.38)
	Level3D._multimesh(root, box, wood, post)
	Level3D._multimesh(root, box, boards, Level3D.make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"))
	Level3D._multimesh(root, box, p["footings"], Level3D.make_pbr("concrete", 0.33, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone"))
	var rf: Array = p["roof"]
	_roof(root, rf[0], rf[1], rf[2])

## Dev `--towerlit`: światło podglądowe do zrzutów akceptacji (w grze strażnica jest ciemna) — także przy starej strażnicy, do porównania.
static func preview_lights(parent: Node3D, d: Dictionary) -> void:
	var lv := levels_of(d)
	for i in 3:
		var ol := OmniLight3D.new()
		ol.name = "TowerPreviewLight%d" % i
		ol.position = Vector3(lerpf(float(lv["xl"]) - 3.0, float(lv["xr"]) + 3.0, float(i) / 2.0), lerpf(lv["ground"], lv["ceil"], 0.55 if i == 1 else 0.35), 9.0)
		ol.omni_range = 30.0
		ol.light_energy = 2.2
		ol.light_color = Color(0.85, 0.88, 1.0)
		parent.add_child(ol)

## Stroma drabina schodowa (dwa policzki i stopnie) od `a` (dół) do `b` (góra) w płaszczyźnie z = a.z.
static func _ladder(out: Array, a: Vector3, b: Vector3) -> void:
	for dz in [-LADDER_W * 0.5, LADDER_W * 0.5]:
		out.append(Level3D._strut(a + Vector3(0, 0, dz), b + Vector3(0, 0.9, dz), 0.08))
	var n := int((b.y - a.y) / 0.3)
	for i in range(1, n + 1):
		var q := a.lerp(b, float(i) / float(n + 1))
		out.append(Level3D._span_box(Vector3(q.x - 0.12, q.y - 0.025, a.z - LADDER_W * 0.5), Vector3(q.x + 0.12, q.y + 0.025, a.z + LADDER_W * 0.5)))

## Dach czterospadowy: okap prostokąt (lo.x..hi.x, lo.z..hi.z) na wysokości lo.y, kalenica wzdłuż x na `ridge_y`; papa na deskowaniu,
## obie strony widoczne (bez odrzucania tylnych ścian).
static func _roof(root: Node3D, lo: Vector3, hi: Vector3, ridge_y: float) -> void:
	var zm := (lo.z + hi.z) * 0.5
	var inset := (hi.z - lo.z) * 0.5
	var r0 := Vector3(lo.x + inset, ridge_y, zm)
	var r1 := Vector3(hi.x - inset, ridge_y, zm)
	var a := Vector3(lo.x, lo.y, hi.z)
	var b := Vector3(hi.x, lo.y, hi.z)
	var c := Vector3(hi.x, lo.y, lo.z)
	var e := Vector3(lo.x, lo.y, lo.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [[a, b, r1, r0], [c, e, r0, r1]]:
		_tri(st, q[0], q[1], q[2])
		_tri(st, q[0], q[2], q[3])
	_tri(st, b, c, r1)
	_tri(st, e, a, r0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = st.commit()
	var m := Level3D.make_pbr("roof", 0.25, Color(0.16, 0.15, 0.14), 0.85, 1.0, 1.0, false, "rust").duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.42, 0.40, 0.38)
	mi.material_override = m
	root.add_child(mi)

static func _tri(st: SurfaceTool, p: Vector3, q: Vector3, s: Vector3) -> void:
	st.add_vertex(p)
	st.add_vertex(q)
	st.add_vertex(s)
