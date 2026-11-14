extends RefCounted
## Fale w widoku 3D: krzyk gracza (voice.gd → player.gd `_scream_fx`) i skaner „Sowa” (scanner_view.gd). Do 1.7.565 oba były okręgami
## rysowanymi w 2D na płaszczyźnie gry (`draw_arc`); teraz to kule rozchodzące się w świecie 3D.
##
## Sposób: kula wokół źródła rysowana od wewnątrz (cull_front) bez testu głębi, więc pokrywa na ekranie cały obszar fali, także gdy kamera
## jest w środku. Shader odtwarza z bufora głębi punkt sceny pod pikselem i liczy jego odległość od źródła — gdzie wypada na czole fali,
## świeci pas. Fala przesuwa się więc po ścianie tła, podłodze, stropie i modelach jak prawdziwa kula: na ścianie 1 m za płaszczyzną gry
## łuk jest mniejszy niż na podłodze przy graczu, na rogu się łamie. Krzyk ma do tego „powietrze”: brzeg kuli lekko załamuje obraz
## (falujące powietrze) — bez tego przy pustym kadrze (niebo, las daleko) nie byłoby czego oświetlić.
##
## Prześwietlenie wrogów (skaner): nakładka (`material_overlay`) na modelach 3D bez testu głębi — obrys od kąta patrzenia (fresnel),
## błysk, gdy mija ich fala, i poziome linie „ekranu” skanera.

const SONAR_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, depth_test_disabled, cull_front, fog_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 center;                   // źródło fali (m, świat)
uniform float radius = 1.0;            // czoło fali (m)
uniform float max_r = 20.0;            // zasięg (m): dalej nic
uniform float width = 0.35;            // grubość czoła (m)
uniform vec4 tint : source_color = vec4(0.9, 0.9, 0.5, 1.0);
uniform float fade = 1.0;              // wygaszanie całości (koniec działania)
uniform float edge = 0.12;             // jasność stałego brzegu zasięgu
uniform float depth_keep = 3.0;        // do tylu m od płaszczyzny gry (w głąb i ku kamerze) fala pełna,
uniform float depth_gone = 9.0;        // od tylu — nic: las w głębi i grunt tuż przed kamerą nie mogą przyćmić pasa gry
uniform float lines = 0.0;             // linie „ekranu” w smudze za czołem (0 — bez; 1 dawało na przekroju skały wzór jak płyta winylowa)
// Płaszczyzny zwrócone prosto do kamery (ściana tła, lico skały) dają okrąg jak w 2D — tam fala tylko przygasa; pełna zostaje na
// podłodze, stropie, bokach i bryłach, gdzie łamie się w przestrzeni. Normalna z pochodnych odtworzonej pozycji.
float facing_keep(vec3 wp) {
	vec3 n = normalize(cross(dFdx(wp), dFdy(wp)));
	return mix(1.0, 0.06, smoothstep(0.8, 0.97, abs(n.z)));
}
void fragment() {
	float z = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(v.xyz / v.w, 1.0)).xyz;
	float d = distance(wp, center);
	float facing = facing_keep(wp);        // pochodne przed `discard` (po nim są niezdefiniowane)
	if (d > max_r + width * 2.0) {
		discard;
	}
	float x = (d - radius) / width;
	float front = exp(-x * x);
	float plane = 1.0 - smoothstep(depth_keep, depth_gone, abs(wp.z - center.z));
	// przekrój bryły przed płaszczyzną gry (Level3D.DEPTH_FRONT = 1,1 m) to płaska ściana do kamery: fala byłaby na niej zwykłym
	// okręgiem jak w 2D — pomijamy wszystko, co wystaje przed płaszczyznę gry dalej niż ~0,8 m
	plane *= 1.0 - smoothstep(0.7, 0.95, wp.z - center.z);
	plane *= facing;
	// smuga za czołem: wygasa w głąb fali, z cienkimi liniami co 0,5 m (urządzenie „rysuje” powierzchnie)
	float tail = (d < radius) ? exp(-(radius - d) / (width * 3.0)) : 0.0;
	float ln = mix(1.0, 0.55 + 0.45 * smoothstep(0.6, 1.0, abs(sin(d * 6.2832))), lines);
	float travel = 1.0 - 0.6 * clamp(radius / max_r, 0.0, 1.0);     // fala słabnie z drogą
	float e = (d - max_r) / 0.12;
	float rim = edge * exp(-e * e);
	ALBEDO = tint.rgb;
	ALPHA = clamp((front * travel + 0.12 * tail * travel * ln + rim) * plane * tint.a * fade, 0.0, 1.0);
}
"""

const SCREAM_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, depth_test_disabled, cull_front, fog_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 center;
uniform float radius = 1.0;
uniform float width = 0.45;
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float fade = 1.0;
uniform float distort = 1.0;           // siła załamania obrazu (0 przy „Reduce effects”)
// Płaszczyzny zwrócone prosto do kamery (ściana tła, lico skały) dają okrąg jak w 2D — tam fala tylko przygasa; pełna zostaje na
// podłodze, stropie, bokach i bryłach, gdzie łamie się w przestrzeni. Normalna z pochodnych odtworzonej pozycji.
float facing_keep(vec3 wp) {
	vec3 n = normalize(cross(dFdx(wp), dFdy(wp)));
	return mix(1.0, 0.06, smoothstep(0.8, 0.97, abs(n.z)));
}
void fragment() {
	float z = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(v.xyz / v.w, 1.0)).xyz;
	// czoło fali na powierzchniach sceny
	float x = (distance(wp, center) - radius) / width;
	float front = exp(-x * x) * (1.0 - smoothstep(2.5, 7.0, abs(wp.z - center.z))) * (1.0 - smoothstep(0.7, 0.95, wp.z - center.z)) * facing_keep(wp);
	// brzeg kuli w powietrzu: najbliższe podejście promienia widzenia (od kamery do sceny) do źródła ≈ promień kuli
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 ray = wp - cam;
	float len = length(ray);
	vec3 dir = ray / max(len, 1e-4);
	float tc = clamp(dot(center - cam, dir), 0.0, len);
	float dmin = distance(cam + dir * tc, center);
	float s = (dmin - radius) / (width * 0.9);
	float shell = exp(-s * s) * step(0.0, dot(center - cam, dir));
	// załamanie: piksele na brzegu kuli przesunięte od środka fali na ekranie
	vec4 cp = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(center, 1.0));
	vec2 cuv = cp.xy / cp.w * 0.5 + 0.5;
	vec2 away = SCREEN_UV - cuv;
	away = away / max(length(away), 1e-4);
	vec2 off = away * shell * 0.012 * distort * fade;
	vec3 bg = texture(screen_tex, SCREEN_UV - off).rgb;
	vec3 glow = tint.rgb * (front * 0.8 + shell * 0.05);
	ALBEDO = bg + glow * fade;
	ALPHA = clamp(max(shell * step(0.001, distort), front) * 1.4, 0.0, 1.0) * fade;
}
"""

const XRAY_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, depth_test_disabled, cull_back, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.3, 1.0);
uniform vec3 center;
uniform float pulse = 0.0;             // czoło fali skanera (m)
uniform float fade = 1.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float x = (distance(wpos, center) - pulse) / 1.1;
	float ping = exp(-x * x);
	float scan = 0.8 + 0.2 * sin(wpos.y * 48.0 - TIME * 7.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp((0.08 + 0.6 * fres + 0.4 * ping) * scan * tint.a * fade, 0.0, 1.0);
}
"""

static var _sonar_sh: Shader
static var _scream_sh: Shader
static var _xray_sh: Shader

static func _shader(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code
	return sh

## Kula fali (siatka o promieniu 1 — skalę ustawia `place`) z materiałem sonaru albo krzyku.
static func make_wave(scream: bool, layer: int) -> MeshInstance3D:
	if _sonar_sh == null:
		_sonar_sh = _shader(SONAR_SHADER)
		_scream_sh = _shader(SCREAM_SHADER)
	var mi := MeshInstance3D.new()
	mi.name = "ScreamWave" if scream else "SonarWave"
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = _scream_sh if scream else _sonar_sh
	m.render_priority = 2                    # po innych przezroczystych (snop, mgła cząsteczek) — fala ma być na wierzchu
	mi.material_override = m
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	mi.visible = false
	return mi

## Ustawia kulę: środek, czoło fali i obejmowany zasięg (siatka musi zakryć cały zasięg, bo shader rysuje tylko wewnątrz niej).
static func place(mi: MeshInstance3D, center: Vector3, radius: float, reach: float, params: Dictionary) -> void:
	mi.position = center
	var s := maxf(reach, 0.2) + 0.6
	mi.scale = Vector3(s, s, s)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("radius", radius)
	for k in params:
		m.set_shader_parameter(k, params[k])
	mi.visible = true

## Materiał prześwietlenia wroga (nakładka na model 3D).
static func make_xray(tint: Color) -> ShaderMaterial:
	if _xray_sh == null:
		_xray_sh = _shader(XRAY_SHADER)
	var m := ShaderMaterial.new()
	m.shader = _xray_sh
	m.set_shader_parameter("tint", tint)
	m.render_priority = 3
	return m

## Materiał znaczników skanera rysowanych co klatkę (romby znajdziek, pudła wrogów bez modelu): kolor z wierzchołków, bez testu głębi.
static func make_marks() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.render_priority = 3
	return m

const OCTA := [Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)]
const OCTA_TRI := [[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1], [5, 2, 1], [5, 3, 2], [5, 4, 3], [5, 1, 4]]
const OCTA_EDGES := [[0, 1], [0, 2], [0, 3], [0, 4], [5, 1], [5, 2], [5, 3], [5, 4], [1, 2], [2, 3], [3, 4], [4, 1]]
const BOX_FACES := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
const BOX_EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]

## Bufor trójkątów znaczników jednej klatki — wszystko idzie do ImmediateMesh jedną powierzchnią (`flush`).
class Marks:
	var v := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		v.append(a)
		v.append(b)
		v.append(d)
		c.append(col)
		c.append(col)
		c.append(col)

	func flush(im: ImmediateMesh) -> void:
		im.clear_surfaces()
		if v.is_empty():
			return
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in v.size():
			im.surface_set_color(c[i])
			im.surface_add_vertex(v[i])
		im.surface_end()
		v.clear()
		c.clear()

## Romb 3D (ośmiościan) obracający się wokół pionu: ściany półprzezroczyste, krawędzie jaśniejsze (wstęgi z trójkątów, bo linie
## w 4K mają 1 px).
static func add_octa(mk: Marks, c: Vector3, r: float, spin: float, fill: Color, line: Color) -> void:
	var b := Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, 0.35)
	var pts: Array[Vector3] = []
	for p in OCTA:
		pts.append(c + b * ((p as Vector3) * Vector3(r * 0.7, r, r * 0.7)))
	for t in OCTA_TRI:
		mk.tri(pts[t[0]], pts[t[1]], pts[t[2]], fill)
	_add_edges(mk, pts, OCTA_EDGES, r * 0.07, line)

## Pudło (prostopadłościan) wokół wroga bez modelu 3D albo ukrytego (uśpiony Stalker z perkiem „Scout”): ściany i krawędzie.
static func add_box(mk: Marks, foot: Vector3, size: Vector3, fill: Color, line: Color) -> void:
	var h := size * 0.5
	var c := foot + Vector3(0.0, h.y, 0.0)
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for f in BOX_FACES:
		mk.tri(pts[f[0]], pts[f[1]], pts[f[2]], fill)
		mk.tri(pts[f[0]], pts[f[2]], pts[f[3]], fill)
	_add_edges(mk, pts, BOX_EDGES, 0.025, line)

## Krawędzie jako cienkie krzyże z dwóch wstęg (czytelne z każdej strony bez billboardu).
static func _add_edges(mk: Marks, pts: Array[Vector3], edges: Array, w: float, col: Color) -> void:
	for e in edges:
		var a: Vector3 = pts[e[0]]
		var b: Vector3 = pts[e[1]]
		var d := (b - a).normalized()
		var n1 := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.UP).normalized() * w
		var n2 := d.cross(n1).normalized() * w
		for n in [n1, n2]:
			mk.tri(a - n, a + n, b + n, col)
			mk.tri(a - n, b + n, b - n, col)
