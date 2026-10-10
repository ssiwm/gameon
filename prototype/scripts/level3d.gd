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

const PBR_DIR := "res://art/world3d/"
static var _pbr_cache := {}

## Materiał PBR ze skanu / generatora (`tools/world_pbr_import.py`, `world_pbr_gen.py`): albedo + normalne + ORM (R = AO, G = roughness, B = metallic),
## rzutowanie triplanarne w jednostkach świata (`per_m` = powtórzeń na metr). Brak plików → szum proceduralny (`make_mat`) z kolorem awaryjnym.
static func make_pbr(name: String, per_m: float, fallback: Color, rough := 0.95, normal_scale := 1.0, metal_mul := 1.0, alpha := false, grime := "") -> StandardMaterial3D:
	var key := "%s:%.3f:%s:%s" % [name, per_m, str(alpha), grime]
	if _pbr_cache.has(key):
		return _pbr_cache[key]
	var path := PBR_DIR + name + "_albedo.png"
	if not ResourceLoader.exists(path) or "--noworldpbr" in OS.get_cmdline_user_args():     # dev: --noworldpbr = stary szum proceduralny (porównanie)
		return make_mat(fallback, rough)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path) as Texture2D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(per_m, per_m, per_m)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var np := PBR_DIR + name + "_normal.png"
	if ResourceLoader.exists(np):
		m.normal_enabled = true
		m.normal_texture = load(np) as Texture2D
		m.normal_scale = normal_scale
	var op := PBR_DIR + name + "_orm.png"
	if ResourceLoader.exists(op):
		var orm := load(op) as Texture2D
		m.ao_enabled = true
		m.ao_texture = orm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = metal_mul
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if grime != "" and not alpha and ResourceLoader.exists(PBR_DIR + "grime_%s.png" % grime) and not "--nograime" in OS.get_cmdline_user_args():
		# warstwa brudu jako osobny przebieg (`next_pass`): wielkoskalowa (kafel ok. 14 m), więc plamy, zacieki i przebarwienia nie powtarzają się
		# razem z kaflem materiału (warstwa „detail” StandardMaterial3D w triplanarze używa siatki UV materiału bazowego)
		var g := StandardMaterial3D.new()
		g.albedo_texture = load(PBR_DIR + "grime_%s.png" % grime) as Texture2D
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.95
		g.uv1_triplanar = true
		g.uv1_world_triplanar = true
		g.uv1_scale = Vector3(0.07, 0.07, 0.07)
		g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.next_pass = g
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pbr_cache[key] = m
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
	var grates: Array = []
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
				(grates if ch == "=" else planks).append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, T * 0.5 - 0.1, 0.0)))
			elif ch == "F" or ch == "l" or ch == "k":
				marks[ch].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
			elif ch == "E" or ch == "e":
				marks["E"].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
	var mats := {
		"#": make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic"),
		"C": make_pbr("concrete", 0.35, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone"),
		"M": make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
		"m": make_pbr("mud", 0.30, Color(0.18, 0.2, 0.1), 1.0, 1.0, 1.0, false, "organic"),
		"O": make_pbr("oil", 0.5, Color(0.05, 0.05, 0.07), 0.2, 0.6, 0.0),
		"~": make_pbr("water", 0.4, Color(0.05, 0.12, 0.2), 0.1, 0.8, 0.0),
	}
	for k in groups:
		_multimesh(parent, box, groups[k], mats[k])
	var gbox := BoxMesh.new()
	gbox.size = Vector3(T, 0.18, DEPTH_FRONT + DEPTH_BACK + 0.1)
	_multimesh(parent, gbox, grass, make_mat(Color(0.07, 0.13, 0.06), 1.0, 0.2, 0.9))
	var wbox := BoxMesh.new()
	wbox.size = Vector3(T, T, 0.3)
	_multimesh(parent, wbox, walls, make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone"), false)
	var pc := CylinderMesh.new()
	pc.top_radius = 0.45
	pc.bottom_radius = 0.55
	pc.height = T
	pc.radial_segments = 10
	_multimesh(parent, pc, posts, make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic"))
	var plb := BoxMesh.new()
	plb.size = Vector3(T, 0.22, 2.0)
	_multimesh(parent, plb, planks, make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"))
	_multimesh(parent, plb, grates, make_pbr("grate", 0.5, Color(0.28, 0.30, 0.34), 0.5, 1.0, 0.7, true))
	return marks

const DECAL_DIR := "res://art/world3d/decals/"
## Dekale (sprite'y z `tools/world_decals_gen.py`): [szerokość, wysokość w kaflach, powierzchnie (b tło, C beton, M metal), waga, odbicie dozwolone].
## Duży wariant (×1) wymaga wolnego prostokąta kafli tej samej powierzchni; gdy go nie ma, próbujemy połowy rozmiaru.
const DECALS := {
	"g_dont_listen": [4, 2, "bC", 1.0, false], "g_they_hear": [4, 2, "bC", 1.0, false], "g_silence": [4, 2, "bC", 0.8, false],
	"g_no_exit": [4, 2, "bC", 0.9, false], "g_patrol7": [4, 2, "bC", 0.9, false], "g_help": [4, 2, "b", 0.8, false],
	"g_run": [4, 2, "bCM", 0.8, false], "g_47": [4, 2, "bCM", 0.5, false], "g_eye": [4, 2, "bC", 0.9, true],
	"g_tally": [4, 2, "bCM", 0.7, true], "g_arrow": [4, 2, "bCM", 0.7, true], "g_xcircle": [4, 2, "bCM", 0.7, true],
	"g_hand": [3, 3, "bC", 0.6, true],
	"d_soot": [4, 4, "bC", 1.1, true], "d_water": [3, 3, "bCM", 1.4, true], "d_crack_a": [3, 3, "bC", 1.2, true],
	"d_crack_b": [3, 3, "bC", 1.2, true], "d_bullets": [3, 3, "bCM", 1.2, true], "d_plaster": [3, 3, "bC", 1.0, true],
	"d_rustbleed": [3, 3, "bM", 1.2, true], "d_damp": [4, 4, "bC", 1.1, true],
}

## Ślady zniszczeń na ścianach: grafiti, pęknięcia, ślady po kulach, sadza, zacieki, odpryski. Rozmieszczenie deterministyczne (ziarno z mapy), więc
## każdy peer widzi to samo; tylko widok. `--nodecals` wyłącza.
static func build_decals(parent: Node3D, rows: Array) -> void:
	if "--nodecals" in OS.get_cmdline_user_args():
		return
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var surf := {}                                              # (c, r) → powierzchnia: "b" (ściana tła), "C" / "M" (odsłonięty kafel)
	for r in nrows:
		for c in cols:
			var ch := _ch(rows, c, r)
			if ch == "b":
				surf[Vector2i(c, r)] = "b"
			elif ch == "C" or ch == "M":
				if not (is_solid_ch(_ch(rows, c - 1, r)) and is_solid_ch(_ch(rows, c + 1, r)) and is_solid_ch(_ch(rows, c, r - 1)) and is_solid_ch(_ch(rows, c, r + 1))):
					surf[Vector2i(c, r)] = ch
	if surf.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rows))
	var names: Array = DECALS.keys()
	var used := {}
	var inst := {}
	var budget := 160
	var anchors: Array = surf.keys()
	for k in anchors:
		if budget <= 0:
			break
		if rng.randf() > 0.07 or used.has(k):
			continue
		var kind: String = surf[k]
		var cand: Array = []
		var tot := 0.0
		for nm in names:
			if (DECALS[nm][2] as String).contains(kind):
				cand.append(nm)
				tot += float(DECALS[nm][3])
		if cand.is_empty():
			continue
		var pick := rng.randf() * tot
		var name: String = cand[0]
		for nm in cand:
			pick -= float(DECALS[nm][3])
			if pick <= 0.0:
				name = nm
				break
		var d: Array = DECALS[name]
		for sc in [1.0, 0.5]:
			var wt := maxi(1, int(round(float(d[0]) * sc)))
			var ht := maxi(1, int(round(float(d[1]) * sc)))
			if not _decal_fits(k, wt, ht, kind, surf, used):
				continue
			for dy in ht:
				for dx in wt:
					used[Vector2i(k.x + dx, k.y + dy)] = true
			var z := (DEPTH_FRONT + 0.012) if kind != "b" else (-DEPTH_BACK + 0.3 + 0.012)
			var ctr := cell_pos(float(k.x), float(k.y)) + Vector3(float(wt - 1) * T * 0.5, -float(ht - 1) * T * 0.5, 0.0)
			ctr.z = z
			var sx := T * float(wt) * (-1.0 if (bool(d[4]) and rng.randf() < 0.5) else 1.0)
			var rot := rng.randf_range(-0.05, 0.05) if bool(d[4]) else 0.0
			var bas := Basis(Vector3.BACK, rot) * Basis.from_scale(Vector3(sx, T * float(ht), 1.0))
			if not inst.has(name):
				inst[name] = []
			inst[name].append(Transform3D(bas, ctr))
			budget -= 1
			break
	for name in inst:
		var path := DECAL_DIR + String(name) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path) as Texture2D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.95
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.render_priority = 1
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var arr: Array = inst[name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = q
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Decals_" + String(name)
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

static func _decal_fits(k: Vector2i, wt: int, ht: int, kind: String, surf: Dictionary, used: Dictionary) -> bool:
	for dy in ht:
		for dx in wt:
			var p := Vector2i(k.x + dx, k.y + dy)
			if used.has(p) or not surf.has(p) or String(surf[p]) != kind:
				return false
	return true

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
