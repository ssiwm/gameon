extends RefCounted
## Materiał stref wydobycia (kopanie P1): osobne skany PBR ziemi, żwiru i skały (Poly Haven CC0, `tools/world_pbr_import.py`, `dig_*`) mieszane
## w jednym shaderze triplanarnym w metrach świata — bez szwów między fragmentami i z sąsiednimi kaflami mapy.
##
## Wagi idą w wierzchołkach siatki (dig_zone.gd `_mat_weights`): UV2.x = żwir, UV2.y = skała (reszta = ziemia; żyła to skała z odcieniem),
## COLOR.a = udział materiału strefy względem gruntu mapy (`terrain`) — przód skały przy brzegu strefy przechodzi w grunt mapy, więc
## nietknięta strefa wygląda jak zwykła mapa, a materiał widać w wykopie. COLOR.rgb = odcień materiału i ściemnienie w głąb (jak dotąd).
## Urobek (view3d.gd `_draw_spoil`, MultiMesh) bierze wagi z INSTANCE_CUSTOM (`spoil = true`).

const Level3D := preload("res://scripts/level3d.gd")

## nazwa zestawu PBR → kafli na metr
const SETS := [["terrain", 0.30], ["dig_dirt", 0.55], ["dig_gravel", 0.8], ["dig_rock", 0.4]]

const SHADER := """
shader_type spatial;
render_mode depth_draw_opaque;

uniform sampler2D a0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n0 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D o0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D o1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D o2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D o3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 per_m = vec4(0.30, 0.55, 0.8, 0.4);
uniform bool spoil = false;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wt;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float g = UV2.x;
	float r = UV2.y;
	float f = COLOR.a;
	if (spoil) {
		g = INSTANCE_CUSTOM.x;
		r = INSTANCE_CUSTOM.y;
		f = 1.0;
	}
	float d = max(1.0 - g - r, 0.0);
	wt = vec4(1.0 - f, d * f, g * f, r * f);
}

// triplanar jednego zestawu: kolor, normalna świata (whiteout), AO i szorstkość
void tri(sampler2D a, sampler2D nm, sampler2D o, float s, vec3 n, vec3 bw, float k, inout vec3 alb, inout vec3 nw, inout vec2 ar) {
	vec2 ux = wpos.zy * s;
	vec2 uy = wpos.xz * s;
	vec2 uz = wpos.xy * s;
	alb += (texture(a, ux).rgb * bw.x + texture(a, uy).rgb * bw.y + texture(a, uz).rgb * bw.z) * k;
	vec3 tx = texture(nm, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(nm, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(nm, uz).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	nw += (tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z) * k;
	ar += (texture(o, ux).rg * bw.x + texture(o, uy).rg * bw.y + texture(o, uz).rg * bw.z) * k;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 alb = vec3(0.0);
	vec3 nw = vec3(0.0);
	vec2 ar = vec2(0.0);
	if (wt.x > 0.01) { tri(a0, n0, o0, per_m.x, n, bw, wt.x, alb, nw, ar); }
	if (wt.y > 0.01) { tri(a1, n1, o1, per_m.y, n, bw, wt.y, alb, nw, ar); }
	if (wt.z > 0.01) { tri(a2, n2, o2, per_m.z, n, bw, wt.z, alb, nw, ar); }
	if (wt.w > 0.01) { tri(a3, n3, o3, per_m.w, n, bw, wt.w, alb, nw, ar); }
	float sum = max(wt.x * step(0.01, wt.x) + wt.y * step(0.01, wt.y) + wt.z * step(0.01, wt.z) + wt.w * step(0.01, wt.w), 0.001);
	ALBEDO = alb / sum * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nw), 0.0)).xyz);
	AO = ar.x / sum;
	ROUGHNESS = ar.y / sum;
	METALLIC = 0.0;
}
"""

static var _shader: Shader

## Materiał ścian (spoil = false) albo urobku (true); null — brak tekstur (`--noworldpbr`, stary zestaw), wtedy zostaje StandardMaterial3D.
static func material(spoil: bool) -> Material:
	if "--noworldpbr" in OS.get_cmdline_user_args():
		return null
	for s in SETS:
		if not ResourceLoader.exists(Level3D.PBR_DIR + String(s[0]) + "_albedo.png"):
			return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	var per := Vector4.ZERO
	for i in SETS.size():
		var nm := String(SETS[i][0])
		m.set_shader_parameter("a%d" % i, load(Level3D.PBR_DIR + nm + "_albedo.png"))
		m.set_shader_parameter("n%d" % i, load(Level3D.PBR_DIR + nm + "_normal.png"))
		m.set_shader_parameter("o%d" % i, load(Level3D.PBR_DIR + nm + "_orm.png"))
		per[i] = float(SETS[i][1])
	m.set_shader_parameter("per_m", per)
	m.set_shader_parameter("spoil", spoil)
	if not spoil:                                               # brud jak na gruncie mapy (ta sama warstwa, ten sam szew)
		var base := Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic")
		if base.next_pass != null:
			m.next_pass = base.next_pass
	return m
