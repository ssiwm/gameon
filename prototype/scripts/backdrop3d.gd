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
