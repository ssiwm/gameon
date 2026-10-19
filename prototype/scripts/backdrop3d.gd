extends RefCounted
## Dalekie punkty orientacyjne tła widoku 3D (`BACKDROP` w danych mapy, czyta `level.gd`): maszt radiowy z mrugającymi czerwonymi lampami,
## linia energetyczna (kratowe słupy i zwisające przewody) i drewniana wieża obserwacyjna z ledwie tlącym się oknem. Stoją za lasem albo w jego
## dalekim pasie, wystają ponad czubki drzew i rysują się sylwetką na niebie z księżycem — mapa dostaje własny horyzont (1.1: daleki maszt
## radiostacji z 1.2, 1.2: maszty stacji i linia, która je zasila, 1.3: ta sama linia i stacja za lasem).
## Bryły leżą na warstwie lasu (`Level3D.LAYER_FOREST`): obrysowuje je `MoonRim`, a lampki i okno to sama emisja bez świateł sceny, więc
## ciemność przy postaciach się nie zmienia (GDD §8.3). Mgła głębi ich nie barwi (byłyby jaśniejsze od nieba nad lasem), zamglenie koron tak.
## Wpis: {"kind": "mast" | "power" | "tower", ...}; pola: "col" (kolumna mapy; dla "power" "c0" i "c1"), "z" (m w głąb, ujemne), "h" (wysokość [m]),
## "step" (odstęp słupów linii [m]), "lit" (wieża: okno się tli). Brakujące pola biorą wartości domyślne z `DEFAULTS`.

const Level3D := preload("res://scripts/level3d.gd")
const T := Level3D.T

const DEFAULTS := {
	"mast": {"z": -140.0, "h": 95.0},
	"power": {"z": -80.0, "h": 38.0, "step": 62.0},
	"tower": {"z": -34.0, "h": 18.0, "lit": false},
}
const LAMP_SPACING := 14.0                  ## m: piętra czerwonych lamp masztu (co tyle od góry w dół; część zawsze wystaje nad las w kadrze)

## Lampki i okna: emisja dodawana do obrazu; `vis` ustawia pogoda (`view3d._sync_weather`, `BACKDROP_VIS`). `mode` 0 = stała lampa
## przeszkodowa (jak na masztach lat 80.), 1 = tlące się okno (rzadkie przygasanie), 2 = migające światło na szczycie masztu.
const LAMP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.12, 0.05);
uniform float energy = 3.0;
uniform float vis = 1.0;
uniform int mode = 0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);   // kartka zawsze twarzą do kamery
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = smoothstep(0.22, 0.12, r);
	float glow = pow(max(1.0 - r, 0.0), 2.6) * 0.35;
	float on = 1.0;
	if (mode == 2) {
		float ph = fract(TIME * 0.55);
		on = smoothstep(0.0, 0.06, ph) * smoothstep(0.5, 0.36, ph);        // ok. 0,8 s świecenia, potem przerwa
	} else if (mode == 1) {
		float f = sin(TIME * 0.37) * sin(TIME * 0.11 + 1.3);
		on = 0.75 + 0.25 * sin(TIME * 7.0) * smoothstep(0.6, 0.9, f) - 0.6 * smoothstep(0.85, 0.97, f);   // tli się, czasem drży i przygasa
		core = smoothstep(0.75, 0.55, max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0);
		glow *= 0.5;
	}
	ALBEDO = col * energy * (core + glow) * on * vis;
}
"""

static var _lamp_sh: Shader
static var _mats: Array = []                    ## materiały konstrukcji (bez mgły głębi); w pogodzie „mgła” `set_fog` ją włącza

## Mgła głębi na konstrukcjach: wyłączona w noc pogodną (sylwetka na niebie), włączona w pogodzie „mgła” — wtedy toną w mgle razem z lasem
## zamiast stać czarną sylwetką w prześwitach boru (woła `view3d._sync_weather`, tak jak dla dna lasu).
static func set_fog(on: bool) -> void:
	for m in _mats:
		(m as BaseMaterial3D).disable_fog = not on

## Buduje wszystkie wpisy `entries` pod `parent`. Węzły lampek mają nazwy „BackdropLamp…” (pogoda ustawia im `vis`).
static func build(parent: Node3D, rows: Array, entries: Array) -> void:
	if entries.is_empty():
		return
	var ft := Level3D.forest_terrain(rows)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.07, 0.075, 0.08)
	metal.roughness = 0.8
	metal.metallic_specular = 0.0                 # cienkie belki widziane pod kątem odbijały niebo (Fresnel) i świeciły na biało
	metal.disable_fog = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.10, 0.08, 0.065)
	wood.roughness = 0.95
	wood.metallic_specular = 0.0
	wood.disable_fog = true
	_mats = [metal, wood]
	for e in entries:
		var d: Dictionary = (DEFAULTS.get(String(e.get("kind", "")), {}) as Dictionary).duplicate()
		d.merge(e, true)
		match String(d.get("kind", "")):
			"mast":
				_build_mast(parent, ft, d, metal)
			"power":
				_build_power(parent, ft, d, metal)
			"tower":
				_build_tower(parent, ft, d, wood)

# ---------------------------------------------------------------- konstrukcje w planie gry

const FRAME_SEG := 2.6                      ## m: wysokość przęsła stężeń strażnicy i kratownicy masztu
const TOWER_LEG := 0.3                      ## m: przekrój drewnianej nogi strażnicy
const TOWER_BRACE := 0.13                   ## m: przekrój stężeń strażnicy
const TOWER_FRONT_Z := 0.8                  ## m: przednie nogi strażnicy (za krawędzią bryły; skrajne kolumny wieży, nie jej wnętrze)
const MAST_LEG := 0.16                      ## m: pas kratownicy masztu
const MAST_BRACE := 0.08                    ## m: krzyżulce masztu
const MAST_Z := [-0.64, -2.1]               ## m: przednia (tuż za kratą pomostu z generatorem) i tylna płaszczyzna masztu

## Maszt i strażnica z kolumn `w` mapy (`Level3D.frame_role`) — wcześniej grube słupy z okuciami: maszt w 1.2 to były dwa drewniane pnie
## obok kratowego masztu w tle, a strażnica w 1.1 stała na dwóch nogach z tyłu, bez stężeń. Tylko widok (kolizja kafli bez zmian), cienie włączone,
## warstwa świata (bez poświaty `MoonRim`). Lampy przeszkodowe masztu to sama emisja (jak w tle) — ciemność przy postaciach się nie zmienia.
static func build_frames(parent: Node3D, rows: Array) -> void:
	var runs: Array = Level3D.post_runs(rows)
	var masts := {}
	var legs: Array = []
	for run in runs:
		match Level3D.frame_role(rows, run):
			"mast":
				masts[int(run["c"])] = run
			"tower":
				legs.append(run)
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	for leg in legs:
		var x := (float(leg["c"]) + 0.5) * T
		var zb: float = leg["z"]
		var y0 := -float(leg["r1"]) * T - (0.15 if Level3D.is_solid_ch(Level3D._ch(rows, int(leg["c"]), int(leg["r1"]))) else 0.0)
		var y1 := -float(leg["r0"]) * T
		_beam(wv, wn, Vector3(x, y0, zb), Vector3(x, y1, zb), TOWER_LEG)
		_beam(wv, wn, Vector3(x, y0, TOWER_FRONT_Z), Vector3(x, y1, TOWER_FRONT_Z), TOWER_LEG)
		var nseg := maxi(int(round((y1 - y0) / FRAME_SEG)), 1)
		var h := (y1 - y0) / float(nseg)
		for s in nseg:                                       # stężenia boczne: poziom i przekątna między nogą przednią i tylną
			var ya := y0 + h * float(s)
			var yb := ya + h
			_beam(wv, wn, Vector3(x, yb, zb), Vector3(x, yb, TOWER_FRONT_Z), TOWER_BRACE)
			_beam(wv, wn, Vector3(x, ya if s % 2 == 0 else yb, zb), Vector3(x, yb if s % 2 == 0 else ya, TOWER_FRONT_Z), TOWER_BRACE)
		for other in legs:                                   # stężenia krzyżowe w tylnej płaszczyźnie między nogami tej samej wieży
			var dc := int(other["c"]) - int(leg["c"])
			if dc <= 0 or dc > 16 or int(other["r0"]) != int(leg["r0"]) or int(other["r1"]) != int(leg["r1"]):
				continue
			var x2 := (float(other["c"]) + 0.5) * T
			var z2: float = other["z"]
			# przęsła możliwie kwadratowe (płaskie krzyże przez całą szerokość wieży wyglądały jak gęsta sieć linii): krzyż na całą wysokość odcinka,
			# a niski odcinek (kabina pod dachem) dzielony na kilka krzyży w poziomie; poziomice na górze i na dole
			var nx := maxi(int(round((x2 - x) / (y1 - y0))), 1)
			var bw := (x2 - x) / float(nx)
			_beam(wv, wn, Vector3(x, y1 - 0.2, zb), Vector3(x2, y1 - 0.2, z2), TOWER_BRACE)
			_beam(wv, wn, Vector3(x, y0 + 0.4, zb), Vector3(x2, y0 + 0.4, z2), TOWER_BRACE)
			for i in nx:
				var xa := x + bw * float(i)
				var za := lerpf(zb, z2, float(i) / float(nx))
				var zc := lerpf(zb, z2, float(i + 1) / float(nx))
				_beam(wv, wn, Vector3(xa, y0 + 0.4, za), Vector3(xa + bw, y1 - 0.2, zc), TOWER_BRACE)
				_beam(wv, wn, Vector3(xa + bw, y0 + 0.4, zc), Vector3(xa, y1 - 0.2, za), TOWER_BRACE)
	var mv := PackedVector3Array()
	var mn := PackedVector3Array()
	var lamps: Array = []
	for c in masts:
		if not masts.has(int(c) + 1):
			continue                                         # maszt to para kolumn — rysuje go lewa
		var a: Dictionary = masts[c]
		var b2: Dictionary = masts[int(c) + 1]
		var x0 := float(c) * T + 0.25
		var x1 := float(int(c) + 2) * T - 0.25
		var y0 := -float(maxi(int(a["r1"]), int(b2["r1"]))) * T - 0.15
		var y1 := 0.0
		var corners := [Vector2(x0, MAST_Z[0]), Vector2(x1, MAST_Z[0]), Vector2(x1, MAST_Z[1]), Vector2(x0, MAST_Z[1])]
		var nseg := maxi(int(round((y1 - y0) / FRAME_SEG)), 1)
		var h := (y1 - y0) / float(nseg)
		for s in nseg:
			var ya := y0 + h * float(s)
			var yb := ya + h
			for i in 4:
				var p: Vector2 = corners[i]
				var q: Vector2 = corners[(i + 1) % 4]
				_beam(mv, mn, Vector3(p.x, ya, p.y), Vector3(p.x, yb, p.y), MAST_LEG)
				_beam(mv, mn, Vector3(p.x, yb, p.y), Vector3(q.x, yb, q.y), MAST_BRACE)
				if s % 2 == 0:
					_beam(mv, mn, Vector3(p.x, ya, p.y), Vector3(q.x, yb, q.y), MAST_BRACE)
				else:
					_beam(mv, mn, Vector3(q.x, ya, q.y), Vector3(p.x, yb, p.y), MAST_BRACE)
		var top := Vector3((x0 + x1) * 0.5, y1, (MAST_Z[0] + MAST_Z[1]) * 0.5)
		_beam(mv, mn, top, top + Vector3(0.0, 6.0, 0.0), 0.12)              # antena
		lamps.append([top + Vector3(0.0, 6.2, 0.0), 2])
		var ly := y1 - 1.0
		while ly > y0 + 8.0:
			lamps.append([Vector3(x1 + 0.1, ly, MAST_Z[0]), 0])
			ly -= LAMP_SPACING
	var wood := Level3D.make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic").duplicate() as StandardMaterial3D
	wood.albedo_color = Color(0.45, 0.40, 0.36)
	var steel := Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust")
	_add_frame(parent, "TowerFrame", wv, wn, wood)
	_add_frame(parent, "MastFrame", mv, mn, steel)
	for i in lamps.size():
		_lamp(parent, "BackdropLampMast%d" % i, lamps[i][0], 1.2 if i == 0 else 0.8, Color(1.0, 0.10, 0.04), 3.0 if i == 0 else 1.6, int(lamps[i][1]))

## Siatka konstrukcji w planie gry: warstwa świata, z cieniami (w odróżnieniu od tła na warstwie lasu).
static func _add_frame(parent: Node3D, name: String, v: PackedVector3Array, n: PackedVector3Array, mat: Material) -> void:
	if v.is_empty():
		return
	_add_mesh(parent, name, v, n, mat)
	var mi := parent.get_node(name) as MeshInstance3D
	mi.layers = 1
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## y gruntu pod punktem (x, z): profil dna lasu; za jego końcem (65 m) — wartość z ostatniego węzła (daleki grunt jest i tak zasłonięty lasem).
static func _ground(ft: Dictionary, x: float, z: float) -> float:
	if ft.is_empty():
		return 0.0
	return Level3D.forest_ground_y(ft, x, -z)

# ---------------------------------------------------------------- siatki

## Belka o przekroju kwadratowym `w` od `a` do `b` (cztery ściany, bez denek) — płaskie normalne, żeby kraty łapały obrys księżyca.
static func _beam(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, w: float) -> void:
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var s1 := dir.cross(up).normalized() * (w * 0.5)
	var s2 := dir.cross(s1).normalized() * (w * 0.5)
	var c := [s1 + s2, s1 - s2, -s1 - s2, -s1 + s2]
	for i in 4:
		var p: Vector3 = c[i]
		var q: Vector3 = c[(i + 1) % 4]
		var nn := (p + q).normalized()
		v.append_array(PackedVector3Array([a + p, b + p, b + q, a + p, b + q, a + q]))
		for k in 6:
			n.append(nn)

static func _add_mesh(parent: Node3D, name: String, v: PackedVector3Array, n: PackedVector3Array, mat: Material) -> void:
	if v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | Level3D.LAYER_FOREST
	parent.add_child(mi)

static func _lamp(parent: Node3D, name: String, at: Vector3, size: float, col: Color, energy: float, mode: int) -> void:
	if _lamp_sh == null:
		_lamp_sh = Shader.new()
		_lamp_sh.code = LAMP_SHADER
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = _lamp_sh
	m.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("mode", mode)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.extra_cull_margin = size
	parent.add_child(mi)

## Kratownica: nogi w narożnikach przekroju (`corners(t)` → punkty na wysokości t ∈ 0..1), co `seg` m pierścień poziomy i zygzak przekątnych.
static func _lattice(v: PackedVector3Array, n: PackedVector3Array, base: Vector3, h: float, r0: float, r1: float, legs: int, seg: float, wl: float, wb: float) -> void:
	var nseg := maxi(int(round(h / seg)), 1)
	var ring := func(t: float) -> Array:
		var r := lerpf(r0, r1, t)
		var pts := []
		for i in legs:
			var a := TAU * float(i) / float(legs) + PI * 0.25
			pts.append(base + Vector3(cos(a) * r, h * t, sin(a) * r))
		return pts
	for s in nseg:
		var lo: Array = ring.call(float(s) / float(nseg))
		var hi: Array = ring.call(float(s + 1) / float(nseg))
		for i in legs:
			var j := (i + 1) % legs
			_beam(v, n, lo[i], hi[i], wl)
			_beam(v, n, hi[i], hi[j], wb)
			_beam(v, n, lo[i] if s % 2 == 0 else lo[j], hi[j] if s % 2 == 0 else hi[i], wb)

# ---------------------------------------------------------------- maszt radiowy

## Maszt kratowy o przekroju trójkąta, z odciągami i anteną na szczycie; czerwone lampy przeszkodowe co LAMP_SPACING od szczytu w dół.
static func _build_mast(parent: Node3D, ft: Dictionary, d: Dictionary, mat: Material) -> void:
	var x := (float(d.get("col", 0)) + 0.5) * T
	var z := float(d["z"])
	var h := float(d["h"])
	var base := Vector3(x, _ground(ft, x, z), z)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	_lattice(v, n, base, h, 1.5, 0.9, 3, 3.2, 0.22, 0.09)
	_beam(v, n, base + Vector3(0.0, h, 0.0), base + Vector3(0.0, h + 7.0, 0.0), 0.25)        # antena
	for k in [0.33, 0.66, 1.0]:                                                                # odciągi w trzy strony
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.4
			var anchor := base + Vector3(cos(a), 0.0, sin(a)) * (h * 0.55 * float(k))
			_beam(v, n, base + Vector3(0.0, h * float(k), 0.0), anchor, 0.11)
	_add_mesh(parent, "BackdropMast", v, n, mat)
	var y := h + 7.0
	var i := 0
	while y > h * 0.2:
		_lamp(parent, "BackdropLamp%d" % i, base + Vector3(0.0, y, 0.0), 5.0 if i == 0 else 3.6, Color(1.0, 0.10, 0.04), 4.0 if i == 0 else 2.2, 2 if i == 0 else 0)
		y -= LAMP_SPACING
		i += 1

# ---------------------------------------------------------------- linia energetyczna

## Słupy kratowe co `step` m wzdłuż osi x (od kolumny c0 do c1), dwa ramiona w głąb sceny i przewody: po dwa z każdego ramienia i odgromowy ze
## szczytu, zwisające parabolą między słupami. Przewody to wąskie wstęgi w płaszczyźnie ekranu (kamera patrzy wzdłuż −z).
static func _build_power(parent: Node3D, ft: Dictionary, d: Dictionary, mat: Material) -> void:
	var x0 := float(d.get("c0", 0)) * T
	var x1 := float(d.get("c1", 0)) * T
	var z := float(d["z"])
	var h := float(d["h"])
	var step := float(d["step"])
	var tops: Array = []                                     # dla każdego słupa: punkty zawieszenia przewodów
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var x := x0
	while x <= x1 + 0.1:
		var base := Vector3(x, _ground(ft, x, z), z)
		_lattice(v, n, base, h - 2.0, 2.6, 0.75, 4, 3.0, 0.2, 0.08)
		var top := base + Vector3(0.0, h - 2.0, 0.0)
		_beam(v, n, top, top + Vector3(0.0, 2.0, 0.0), 0.18)
		var pts := [top + Vector3(0.0, 2.0, 0.0)]
		for arm in [[h - 3.0, 5.0], [h - 7.0, 6.5]]:
			var ay := base.y + float(arm[0])
			var al := float(arm[1])
			_beam(v, n, Vector3(x, ay, z - al), Vector3(x, ay, z + al), 0.22)
			for sgn in [-1.0, 1.0]:
				var tip := Vector3(x, ay - 1.6, z + sgn * (al - 0.4))          # izolator zwisa pod końcem ramienia
				_beam(v, n, Vector3(x, ay, z + sgn * (al - 0.4)), tip, 0.12)
				pts.append(tip)
		tops.append(pts)
		x += step
	_add_mesh(parent, "BackdropPylons", v, n, mat)
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	for s in tops.size() - 1:
		var a: Array = tops[s]
		var b: Array = tops[s + 1]
		for k in a.size():
			var pa: Vector3 = a[k]
			var pb: Vector3 = b[k]
			var sag := step * 0.045
			var prev := pa
			for j in range(1, 17):
				var t := float(j) / 16.0
				var p := pa.lerp(pb, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
				var w := 0.07
				cv.append_array(PackedVector3Array([prev + Vector3(0, w, 0), p + Vector3(0, w, 0), p - Vector3(0, w, 0), prev + Vector3(0, w, 0), p - Vector3(0, w, 0), prev - Vector3(0, w, 0)]))
				for q in 6:
					cn.append(Vector3(0.0, 0.4, 0.92))
				prev = p
	_add_mesh(parent, "BackdropCables", cv, cn, mat)

# ---------------------------------------------------------------- wieża obserwacyjna

## Drewniana wieża przeciwpożarowa: cztery zbieżne nogi z krzyżulcami, kabina z daszkiem; przy "lit" okno ku kamerze ledwie się tli.
static func _build_tower(parent: Node3D, ft: Dictionary, d: Dictionary, mat: Material) -> void:
	var x := (float(d.get("col", 0)) + 0.5) * T
	var z := float(d["z"])
	var h := float(d["h"])
	var base := Vector3(x, _ground(ft, x, z), z)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var cab_h := 2.6
	var leg_h := h - cab_h - 1.2
	_lattice(v, n, base, leg_h, 2.6, 1.5, 4, 3.4, 0.32, 0.14)
	var c := base + Vector3(0.0, leg_h, 0.0)
	var hw := 1.7
	for i in 4:                                            # podłoga, słupki narożne, belki pod daszkiem
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var b := TAU * float(i + 1) / 4.0 + PI * 0.25
		var pa := c + Vector3(cos(a), 0.0, sin(a)) * hw * 1.41
		var pb := c + Vector3(cos(b), 0.0, sin(b)) * hw * 1.41
		_beam(v, n, pa, pb, 0.3)
		_beam(v, n, pa, pa + Vector3(0.0, cab_h, 0.0), 0.22)
		_beam(v, n, pa + Vector3(0.0, cab_h, 0.0), pb + Vector3(0.0, cab_h, 0.0), 0.22)
		_beam(v, n, pa + Vector3(0.0, 1.0, 0.0), pb + Vector3(0.0, 1.0, 0.0), 0.12)            # barierka
		_beam(v, n, pa + Vector3(0.0, cab_h, 0.0) + (pa - c).normalized() * 0.5, c + Vector3(0.0, cab_h + 1.4, 0.0), 0.2)   # daszek
	# ściany kabiny od połowy wysokości (pełne deski) — sylwetka „budki” na tle nieba
	_beam(v, n, c + Vector3(0.0, 1.0, 0.0), c + Vector3(0.0, cab_h, 0.0), hw * 1.9)
	_add_mesh(parent, "BackdropTower", v, n, mat)
	if bool(d.get("lit", false)):
		_lamp(parent, "BackdropLampWin", c + Vector3(0.0, 1.8, hw * 0.96 + 0.05), 1.1, Color(1.0, 0.62, 0.26), 0.55, 1)
