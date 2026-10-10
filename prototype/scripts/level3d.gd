extends RefCounted
## Geometria 3D z mapy ASCII poziomu (używają: widok 3D w grze `view3d.gd` i spike `spike3d/mission3d.gd`). Statyczne funkcje: dostają
## tablicę wierszy mapy i węzeł-rodzic, tworzą `MultiMeshInstance3D`-y (odsłonięte kafle, trawa, ściany tła, pnie, kładki) i las w głębi
## oraz środowisko. Układ: x w prawo, y w górę (mapa ma y w dół), z = 0 płaszczyzna gry, kamera patrzy w −Z.
## Skala: 1 px świata = PX m (postać 22 px = 1,8 m), kafel 16 px = T m.

const PX := 1.8 / 22.0
const TILE := 16.0
const T := TILE * PX
const DEPTH_FRONT := 1.1                   ## m: wysunięcie bryły przed płaszczyznę gry
const DEPTH_BACK := 2.4                    ## m: w głąb

static func is_solid_ch(ch: String) -> bool:
	return ch == "#" or ch == "C" or ch == "M" or ch == "m" or ch == "O" or ch == "~"

static func is_platform_ch(ch: String) -> bool:
	return ch == "-" or ch == "="

## Środek kafla (c, r) w metrach świata.
static func cell_pos(c: float, r: float) -> Vector3:
	return Vector3((c + 0.5) * T, -(r + 0.5) * T, 0.0)

static func px_to_m(p: Vector2) -> Vector3:
	return Vector3(p.x * PX, -p.y * PX, 0.0)

static func _ch(rows: Array, c: int, r: int) -> String:
	if r < 0 or r >= rows.size():
		return "#"
	var row: String = rows[r]
	if c < 0 or c >= row.length():
		return "#"
	return row[c]

static func make_mat(col: Color, rough := 0.95, noise_freq := 0.06, bump := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = noise_freq
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = bump
	return m

static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Bryły, trawa, ściany tła, pnie i kładki z mapy (`rows`: tablica Stringów). Zwraca słownik pozycji znaczników do świateł / rekwizytów:
## {"F": [Vector3…], "E": […], "l": […], "k": […]} (środek kafla, y = podłoga komórki).
static func build_level(parent: Node3D, rows: Array) -> Dictionary:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var box := BoxMesh.new()
	box.size = Vector3(T, T, DEPTH_FRONT + DEPTH_BACK)
	var groups := {"#": [], "C": [], "M": [], "m": [], "O": [], "~": []}
	var grass: Array = []
	var walls: Array = []
	var posts: Array = []
	var planks: Array = []
	var marks := {"F": [], "E": [], "l": [], "k": []}
	var zc := (DEPTH_FRONT - DEPTH_BACK) * 0.5
	for r in nrows:
		for c in cols:
			var ch := _ch(rows, c, r)
			if groups.has(ch):
				# tylko odsłonięte kafle (sąsiad z powietrzem lub tłem) — wnętrza skał nie są widoczne
				if is_solid_ch(_ch(rows, c - 1, r)) and is_solid_ch(_ch(rows, c + 1, r)) and is_solid_ch(_ch(rows, c, r - 1)) and is_solid_ch(_ch(rows, c, r + 1)):
					continue
				var p := cell_pos(c, r)
				groups[ch].append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.0, zc)))
				if ch == "#" and not is_solid_ch(_ch(rows, c, r - 1)):
					grass.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, T * 0.5, zc + 0.05)))
			elif ch == "b":
				walls.append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, 0.0, -DEPTH_BACK + 0.15)))
			elif ch == "w":
				posts.append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, 0.0, -0.4)))
			elif is_platform_ch(ch):
				planks.append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, T * 0.5 - 0.1, 0.0)))
			elif ch == "F" or ch == "l" or ch == "k":
				marks[ch].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
			elif ch == "E" or ch == "e":
				marks["E"].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
	var mats := {
		"#": make_mat(Color(0.20, 0.17, 0.14), 0.97, 0.05),
		"C": make_mat(Color(0.30, 0.31, 0.33), 0.9, 0.09, 0.3),
		"M": make_mat(Color(0.28, 0.30, 0.34), 0.6, 0.12, 0.2),
		"m": make_mat(Color(0.18, 0.2, 0.1), 1.0, 0.04),
		"O": make_mat(Color(0.05, 0.05, 0.07), 0.2, 0.03, 0.1),
		"~": make_mat(Color(0.05, 0.12, 0.2), 0.1, 0.03, 0.1),
	}
	for k in groups:
		_multimesh(parent, box, groups[k], mats[k])
	var gbox := BoxMesh.new()
	gbox.size = Vector3(T, 0.18, DEPTH_FRONT + DEPTH_BACK + 0.1)
	_multimesh(parent, gbox, grass, make_mat(Color(0.07, 0.13, 0.06), 1.0, 0.2, 0.9))
	var wbox := BoxMesh.new()
	wbox.size = Vector3(T, T, 0.3)
	_multimesh(parent, wbox, walls, make_mat(Color(0.20, 0.20, 0.22), 0.95, 0.15, 0.7), false)
	var pc := CylinderMesh.new()
	pc.top_radius = 0.45
	pc.bottom_radius = 0.55
	pc.height = T
	pc.radial_segments = 10
	_multimesh(parent, pc, posts, make_mat(Color(0.20, 0.14, 0.09), 1.0, 0.25, 1.0))
	var plb := BoxMesh.new()
	plb.size = Vector3(T, 0.22, 2.0)
	_multimesh(parent, plb, planks, make_mat(Color(0.34, 0.24, 0.14), 0.9, 0.2, 0.6))
	return marks

## Las w głębi: świerki z `MultiMesh` w płaszczyznach z = −3,5 … −46 m tam, gdzie pod otwartym niebem jest polana (pierwszy kafel bryły nisko).
static func build_forest(parent: Node3D, rows: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1ACE
	var trunks: Array = []
	var low: Array = []
	var mid: Array = []
	var top: Array = []
	for c in range(0, cols, 2):
		var r0 := 0
		while r0 < nrows and not is_solid_ch(_ch(rows, c, r0)):
			r0 += 1
		if r0 < 28:
			continue
		var n := rng.randi_range(2, 4)
		for i in n:
			var z := -rng.randf_range(DEPTH_BACK + 1.0, 46.0)
			var h := rng.randf_range(7.0, 15.0)
			var x := (float(c) + rng.randf()) * T + rng.randf_range(-2.0, 2.0)
			var y := -float(r0) * T
			var s := h / 10.0
			trunks.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, y + h * 0.08, z)))
			low.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, y + h * 0.28, z)))
			mid.append(Transform3D(Basis().scaled(Vector3(s * 0.8, s, s * 0.8)), Vector3(x, y + h * 0.52, z)))
			top.append(Transform3D(Basis().scaled(Vector3(s * 0.6, s, s * 0.6)), Vector3(x, y + h * 0.76, z)))
	var tm := make_mat(Color(0.05, 0.035, 0.025), 1.0, 0.3, 0.8)
	var gm := make_mat(Color(0.03, 0.07, 0.07), 1.0, 0.2, 0.6)
	var tr := CylinderMesh.new()
	tr.top_radius = 0.18
	tr.bottom_radius = 0.28
	tr.height = 2.0
	tr.radial_segments = 7
	_multimesh(parent, tr, trunks, tm, false)
	for spec in [[low, 2.4, 3.8], [mid, 2.0, 3.0], [top, 1.6, 2.2]]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = float(spec[1])
		cm.height = float(spec[2]) + 1.4
		cm.radial_segments = 9
		_multimesh(parent, cm, spec[0], gm, false)

const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
uniform vec3 tint : source_color = vec3(0.30, 0.38, 0.52);
uniform float density = 0.6;
uniform float seed = 0.0;
uniform float speed = 0.05;
varying vec3 wp;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vn(p); p = p * 2.03 + vec2(17.1, 9.7); a *= 0.5; }
	return s;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	vec2 q = vec2(wp.x * 0.11 + TIME * speed + seed * 7.0, wp.y * 0.30 + seed * 3.0);
	float n = fbm(q);
	float n2 = fbm(q * vec2(0.45, 1.2) + vec2(-TIME * speed * 0.6, 4.0));
	float cloud = smoothstep(0.28, 0.80, n * 0.6 + n2 * 0.6);
	float fall = smoothstep(1.0, 0.12, h);
	ALBEDO = tint;
	EMISSION = tint * 0.05;
	ALPHA = clamp(cloud * fall * density, 0.0, 0.85) * COLOR.a;
}
void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * (LIGHT_IS_DIRECTIONAL ? 0.12 : 0.65);       // księżyc ledwie muska mgłę, flary i latarki ją barwią
}
"""
## Mgła przy ziemi: kilka warstw wstęg za płaszczyzną gry (z = -3 … -20 m), tylko nad kolumnami z otwartym niebem (jak las).
## Dryfujący szum fbm, gęsta przy gruncie i rzednąca do góry; oświetlana światłami 3D (flara, ognisko, latarka podbarwiają mgłę).
static func build_ground_fog(parent: Node3D, rows: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var ground: Array = []                                   # y gruntu kolumny (m) albo NAN gdy kolumna nie jest otwarta
	for c in cols:
		var r0 := 0
		while r0 < nrows and not is_solid_ch(_ch(rows, c, r0)):
			r0 += 1
		ground.append(-float(r0) * T if r0 >= 28 and r0 < nrows else NAN)
	var sh := Shader.new()
	sh.code = FOG_SHADER
	var layers := [[-3.2, 0.55, 3.4], [-6.5, 0.5, 4.2], [-12.0, 0.45, 5.4], [-20.0, 0.4, 6.8]]       # z, gęstość, wysokość
	for li in layers.size():
		var spec: Array = layers[li]
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("seed", float(li) * 1.7)
		mat.set_shader_parameter("density", float(spec[1]))
		mat.set_shader_parameter("speed", 0.035 + 0.012 * float(li))
		var hgt := float(spec[2])
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols_c := PackedColorArray()
		var idx := PackedInt32Array()
		var c := 0
		while c < cols:
			if is_nan(ground[c]):
				c += 1
				continue
			var c1 := c
			while c1 < cols and not is_nan(ground[c1]):
				c1 += 1
			if c1 - c >= 2:
				var base := verts.size()
				for k in range(c, c1 + 1):
					var g: float = ground[mini(k, c1 - 1)]
					var edge := 0.0 if (k == c or k == c1) else 1.0
					var x := float(k) * T
					verts.append(Vector3(x, g - 0.4, 0.0))
					verts.append(Vector3(x, g + hgt, 0.0))
					uvs.append(Vector2(x, 0.0))
					uvs.append(Vector2(x, 1.0))
					cols_c.append(Color(1, 1, 1, edge))
					cols_c.append(Color(1, 1, 1, edge))
				for k in range(c1 - c):
					var a := base + k * 2
					idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
			c = c1
		if verts.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols_c
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "GroundFog%d" % li
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.0, float(spec[0]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## Środowisko nocy (niebo, mgła głębi, glow, filmic) i księżyc z cieniami. `ambient` — kolor ciemności poziomu (jak w 2D) służy do ocieplenia
## światła otoczenia (kryjówka); `moon` = false dla wnętrz.
static func build_environment(parent: Node3D, ambient := Color(0.0245, 0.0266, 0.0406), moon := true) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.025, 0.06)
	sm.sky_horizon_color = Color(0.06, 0.09, 0.16)
	sm.ground_bottom_color = Color(0.01, 0.015, 0.03)
	sm.ground_horizon_color = Color(0.04, 0.06, 0.1)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var warm := clampf((ambient.r - ambient.b) * 6.0, 0.0, 1.0)          # kryjówka: bursztynowe otoczenie
	env.ambient_light_color = Color(0.20, 0.26, 0.42).lerp(Color(0.42, 0.30, 0.20), warm)
	env.ambient_light_energy = 0.28 + 0.12 * warm
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.06, 0.10)
	env.fog_density = 0.018
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	parent.add_child(we)
	if moon:
		var l := DirectionalLight3D.new()
		l.name = "Moon"
		l.basis = Basis.looking_at(Vector3(0.55, -0.7, -0.45), Vector3.UP)
		l.light_color = Color(0.55, 0.68, 1.0)
		l.light_energy = 0.55
		l.shadow_enabled = true
		l.directional_shadow_max_distance = 60.0
		l.shadow_bias = 0.04
		parent.add_child(l)
	return env
