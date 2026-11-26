extends MeshInstance3D
## Znacznik celu [E] w widoku 3D (INTERACT_KEY_PLAN.md, wcześniej INTERACT_PLAN.md I3): zardzewiały klawisz w środku obiektu, który wybrał
## arbiter interakcji (interact.gd), zamiast czterech narożników wokół niego. Bez podpisu — nazwa akcji zostaje w pasku akcji HUD.
## Wszystko w płaszczyźnie gry (z = 0), bez światła sceny, mgły i cienia, bez testu
## głębi, żeby model obiektu nie zasłaniał klawisza.
##
## Stany (klatki arkusza inspiracji art_src/ui/interact_key_ref.png):
## - pojawienie — po DWELL_S przy tym samym celu klawisz wskakuje ze skali 0,6 z lekkim przestrzeleniem (APPEAR_S);
## - możliwa — bursztynowa poświata z oddechem jasności (stała przy „Reduce effects”);
## - niemożliwa (brak desek, broń zablokowana) — klawisz wyszarzony, bez poświaty, opis powodu szary; [E] wtedy daje czerwone „zakłócenie”
##   (paski obrazu przesunięte w bok, GLITCH_S);
## - naciśnięcie (stanowiska, broń) — klawisz wciśnięty (skala 0,86), litera rozżarzona, mały błysk;
## - przytrzymanie — drut kolczasty owija się wokół klawisza zgodnie z postępem (od góry, zgodnie z zegarem), poświata i drut przechodzą
##   z bursztynu w czerwień, litera się rozżarza, na końcu drutu iskrzy;
## - koniec przytrzymania — wybuch: błysk, promienie, iskry i fala (BURST_S), potem żarzące się okruchy.
## Miejsce klawisza (INTERACT_KEY_PLAN.md „Położenie”): oś pozioma = środek rzutu modeli celu (jak środek dawnej ramki; bez modelu —
## strefa `box` oferty), wysokość = wierzch obiektu ze strefy oferty (podłoga gry): górna krawędź strefy, ale najwyżej SURFACE_PX nad
## podłogą — nad blatem ławy, nad zwłokami, nad sejfem. Wysokości nie bierzemy z rzutu modeli: meble stoją w głębi, więc ich podłoga
## rzutuje się wyżej, a stanowisko to ława, tablica na ścianie i skrzynia naraz (środek ich sumy wisiał w powietrzu).
## Oferta może podać własny punkt `anchor` (px świata, środek klawisza).

const Level3D := preload("res://scripts/level3d.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")

const CAP_TEX := preload("res://art/world3d/interact/key_cap.png")
const RING_TEX := preload("res://art/world3d/interact/key_ring.png")
const CAP_GLB := "res://art/world3d/interact/key_cap.glb"   ## model nakładki z Meshy (tools/blender_key_cap.py), bez litery

const TINT := Color(1.0, 0.72, 0.30)          ## bursztyn podpowiedzi (jak door_hint3d.gd TINT)
const TINT_HOT := Color(1.0, 0.22, 0.08)      ## czerwień pełnego przytrzymania
const TINT_MUTED := Color(0.62, 0.6, 0.55)
const LETTER := Color(0.93, 0.87, 0.74)
const LETTER_HOT := Color(1.6, 0.62, 0.26)    ## rozżarzona litera (HDR — łapie poświatę środowiska)
const DWELL_S := 0.15                         ## s przy tym samym celu, zanim znacznik się pokaże
const FADE_S := 0.2
const APPEAR_S := 0.22
const PULSE_S := 1.2                          ## okres oddechu jasności
const GLITCH_S := 0.32
const PRESS_S := 0.18
const BURST_S := 0.9
const KEY_PX := 4.0                           ## bok klawisza w pikselach świata (gracz ma ok. 22 px; 10 i 6 px były za duże)
const RING_PX := KEY_PX * 1.85                ## bok tekstury pierścienia (drut z kolcami)
const GLOW_PX := KEY_PX * 2.6
const BURST_PX := KEY_PX * 4.0
const TOP_GAP_PX := 0.8                       ## odstęp spodu klawisza od wierzchu obiektu
const SURFACE_PX := 11.0                      ## najwyższy „wierzch” obiektu nad podłogą (ok. 0,9 m — blat ławy)
const Z_M := 0.05                             ## przed płaszczyzną gry [m] (płaska nakładka)
const MODEL_Z_M := 0.6                        ## środek modelu przed płaszczyzną gry [m]: przed meblami (z testem głębi); gracza rysuje kamera graczy na wierzchu
const MODEL_TILT := -20.0                     ## stopnie: lico odchylone w górę, widać dolne fazowanie jak na arkuszu

const CAP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D cap : source_color, filter_linear_mipmap;
uniform float fade = 1.0;
uniform float muted = 0.0;
uniform float glitch = 0.0;
uniform float heat = 0.0;
uniform float t = 0.0;
float h1(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float shift = 0.0;
	if (glitch > 0.0) {
		float band = floor(uv.y * 16.0);
		float r = h1(band + floor(t * 30.0) * 7.0);
		shift = (r - 0.5) * 0.22 * glitch * step(0.5, r);
	}
	vec4 c = texture(cap, uv + vec2(shift, 0.0));
	float cr = texture(cap, uv + vec2(shift + 0.025 * glitch, 0.0)).r;      // rozjechany kanał czerwieni przy zakłóceniu
	vec3 col = vec3(mix(c.r, cr, glitch), c.g, c.b);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(l) * 0.62, muted);
	col = mix(col, col * vec3(1.7, 0.45, 0.4), glitch * 0.7);
	col += vec3(0.5, 0.12, 0.02) * heat * (1.0 - smoothstep(0.0, 0.55, length(uv - 0.5)));   // nagrzana nakładka wokół litery
	ALBEDO = col;
	ALPHA = c.a * fade;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform float k = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
	ALBEDO = tint.rgb;
	ALPHA = g * k;
}
"""

## Ciemny podkład pod klawiszem: miękkie przyciemnienie tła, żeby klawisz i poświata były czytelne także na jasnej ścianie i tablicy narzędzi.
const SHADE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float k = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.02, 0.015, 0.01);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, d)) * k;
}
"""

## Pierścień: tekstura z Blendera (R jasność, G krycie, B poświata), odsłaniana po kącie od góry zgodnie z zegarem do `prog`.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D ring : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform float prog = 0.0;
uniform float hot = 0.0;
uniform float fade = 1.0;
uniform float t = 0.0;
uniform float sparks = 1.0;
const float RAD = 0.83;            // promień osi pierścienia w UV (R / (R + kolec + margines) z blender_barbed_ring.py)
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	vec4 s = texture(ring, UV);
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float a01 = fract(atan(p.x, p.y) / 6.2831853 + 1.0);              // 0 u góry, rośnie zgodnie z zegarem
	float vis = prog >= 0.999 ? 1.0 : 1.0 - smoothstep(prog - 0.01, prog, a01);
	float wire = s.g * vis;
	float glow = s.b * vis;
	vec3 steel = vec3(0.62, 0.6, 0.56) * (0.35 + 0.95 * s.r);
	vec3 hotw = mix(tint.rgb, vec3(1.0, 0.9, 0.7), s.r * 0.6) * (0.7 + 1.1 * s.r);
	vec3 col = mix(steel, hotw, hot) * wire + tint.rgb * glow * (0.35 + 0.65 * hot) * (1.0 - wire);
	float a = wire;
	if (prog > 0.001 && prog < 0.999 && sparks > 0.5) {
		float ha = prog * 6.2831853;
		vec2 head = vec2(sin(ha), cos(ha)) * RAD;
		float dh = length(p - head);
		col += vec3(1.0, 0.85, 0.55) * exp(-dh * dh * 900.0) * 2.5;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float life = fract(t * 2.2 + h1(fi));
			float seed = h1(fi * 3.1 + floor(t * 2.2 + h1(fi)));
			float ang = ha + 1.5708 + (seed - 0.5) * 2.6;
			vec2 sp = head + vec2(sin(ang), cos(ang)) * life * 0.22 + vec2(0.0, -0.18 * life * life);
			float ds = length(p - sp);
			col += vec3(1.0, 0.6, 0.2) * exp(-ds * ds * 6000.0) * (1.0 - life) * 3.0;
		}
	}
	ALBEDO = col * fade;
	ALPHA = a * fade;
}
"""

## Model nakładki: tekstura z Meshy, światło udawane (stałe z lewej góry), więc klawisz wygląda tak samo w jasnej kryjówce i w ciemnym lesie.
const MODEL_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float fade = 1.0;
uniform float muted = 0.0;
uniform float glitch = 0.0;
uniform float heat = 0.0;
uniform float t = 0.0;
varying vec3 v_n;
float h1(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void vertex() {
	v_n = NORMAL;
	if (glitch > 0.0) {
		float band = floor(VERTEX.y * 9.0);
		float r = h1(band + floor(t * 30.0) * 7.0);
		VERTEX.x += (r - 0.5) * 0.3 * glitch * step(0.45, r);
	}
}
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float d = max(dot(n, normalize(vec3(-0.45, 0.7, 0.6))), 0.0);
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	vec3 col = c.rgb * (0.42 + 1.05 * d) + vec3(1.0, 0.8, 0.55) * rim * 0.18;
	// górna ścianka: Meshy nie widział jej na obrazku i wymyślił jaskrawą fakturę — przyciemniona do koloru stali
	float topw = smoothstep(0.45, 0.85, v_n.y);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * 0.45, topw);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(l) * 0.6, muted);
	col = mix(col, col * vec3(1.8, 0.4, 0.35), glitch * 0.75);
	col += vec3(0.55, 0.12, 0.02) * heat * smoothstep(0.6, 1.0, n.z);
	ALBEDO = col;
	// zanikanie bez przezroczystości (nieprzezroczysta bryła sortuje się sama): dithering po pikselach ekranu
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dither > fade) {
		discard;
	}
}
"""

## Wybuch na końcu przytrzymania (`bt` 0..1 przez BURST_S): błysk, promienie, iskry z grawitacją, fala; w drugiej połowie żarzące się okruchy.
const BURST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.15, 1.0);
uniform float bt = 1.0;
uniform float k = 1.0;
uniform float rays = 1.0;
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 col = vec3(0.0);
	float flash = exp(-r * r * 22.0) * (1.0 - smoothstep(0.0, 0.3, bt));
	col += mix(vec3(1.0, 0.9, 0.7), tint.rgb, 0.5) * flash * 0.8;
	float sector = floor((a + 3.14159) / 6.28318 * 40.0);
	float n = h1(sector);
	float len = (0.25 + 0.75 * n) * smoothstep(0.0, 0.25, bt);
	float rayk = smoothstep(0.75, 1.0, n * 0.6 + 0.4 * h1(sector + 9.0)) * step(r, len) * smoothstep(0.08, 0.2, r);
	col += tint.rgb * rayk * (1.0 - smoothstep(0.1, 0.55, bt)) * (1.0 - r / max(len, 0.01)) * 1.6 * rays;
	float wave = exp(-pow((r - (0.25 + 0.7 * bt)) * 22.0, 2.0)) * (1.0 - bt);
	col += tint.rgb * wave * 0.9 * rays;
	for (int i = 0; i < 26; i++) {
		float fi = float(i);
		float ang = h1(fi) * 6.28318;
		float spd = 0.45 + 0.75 * h1(fi + 3.3);
		vec2 sp = vec2(cos(ang), sin(ang)) * (0.12 + spd * bt) + vec2(0.0, -0.55 * bt * bt);
		float ds = length(p - sp);
		float life = 1.0 - smoothstep(0.35 + 0.5 * h1(fi + 7.7), 1.0, bt);
		vec3 sc = mix(vec3(1.0, 0.9, 0.6), vec3(1.0, 0.35, 0.08), smoothstep(0.2, 0.8, bt));
		col += sc * exp(-ds * ds * 3500.0) * life * 2.4;
	}
	ALBEDO = col;
	ALPHA = k;
}
"""

static var _cap_sh: Shader
static var _glow_sh: Shader
static var _ring_sh: Shader
static var _burst_sh: Shader
static var _model_sh: Shader
static var _shade_sh: Shader
## Płaska nakładka (tekstura) zamiast modelu 3D — porównanie wariantów (`--ekeyflat`, tools/shot_interact_key.gd).
static var flat := false

var target: Node = null                       ## obiekt, przy którym stoi znacznik (test, view3d)
var alpha := 0.0                              ## bieżąca widoczność 0..1 (bez oddechu)
var state := "hidden"                         ## hidden / ok / muted / hold / burst — dla testu i zrzutów
var _dwell := 0.0
var _t := 0.0
var _shown_t := 0.0                           ## s od pojawienia się (wskakiwanie)
var _glitch := 0.0
var _press := 0.0
var _burst := -1.0                            ## s od początku wybuchu (< 0 — bez wybuchu)
var _burst_pos := Vector3.ZERO
var _last_prog := -1.0
var _heat := 0.0                              ## wygładzony postęp przytrzymania (kolor, litera)
var _cap_m: ShaderMaterial
var _glow: MeshInstance3D
var _shade: MeshInstance3D
var _ring: MeshInstance3D
var _burst_mi: MeshInstance3D
var _letter: Label3D
var _pivot: Node3D                            ## model nakładki (odchylenie, kołysanie, wciśnięcie)
var _model_mats: Array = []

func _ready() -> void:
	if _cap_sh == null:
		_cap_sh = _shader(CAP_SHADER)
		var depth := "depth_test_disabled, " if flat else ""          # model ma test głębi — poświata i drut też, żeby leżały za nakładką
		_glow_sh = _shader(GLOW_SHADER.replace("depth_test_disabled, ", depth))
		_ring_sh = _shader(RING_SHADER.replace("depth_test_disabled, ", depth))
		_burst_sh = _shader(BURST_SHADER)
		_model_sh = _shader(MODEL_SHADER)
		_shade_sh = _shader(SHADE_SHADER)
	var px := Level3D.PX
	var key_m := KEY_PX * px
	_cap_m = _mat(_cap_sh, 12)
	_cap_m.set_shader_parameter("cap", CAP_TEX)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if flat:
		mesh = _quad(key_m)
		material_override = _cap_m
	else:
		_pivot = Node3D.new()
		_pivot.scale = Vector3.ONE * key_m
		_pivot.rotation_degrees.x = MODEL_TILT
		add_child(_pivot)
		var sc := (load(CAP_GLB) as PackedScene).instantiate()
		_pivot.add_child(sc)
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for si in m3.mesh.get_surface_count():
				var sm := m3.mesh.surface_get_material(si) as BaseMaterial3D
				var mm := _mat(_model_sh, 0)
				mm.set_shader_parameter("albedo_tex", sm.albedo_texture if sm != null else null)
				m3.set_surface_override_material(si, mm)
				_model_mats.append(mm)
	_shade = _child(GLOW_PX * px * 0.9, _mat(_shade_sh, 9))
	_glow = _child(GLOW_PX * px, _mat(_glow_sh, 10))
	_ring = _child(RING_PX * px, _mat(_ring_sh, 11))
	if not flat:
		_glow.position.z = -0.3 * key_m                               # za nakładką
	(_ring.material_override as ShaderMaterial).set_shader_parameter("ring", RING_TEX)
	_letter = Label3D.new()
	_letter.font = load(UiTheme.FONT_BODY_BOLD)
	_letter.font_size = 128
	_letter.outline_size = 18
	_letter.outline_modulate = Color(0.12, 0.07, 0.04, 0.85)
	_letter.render_priority = 13
	_letter.outline_render_priority = 12
	_setup_label3d(_letter)
	if flat:
		_letter.position = Vector3(0.0, KEY_PX * 0.06 * px, 0.002)       # środek pola nakładki (fazowanie klawisza jest niżej)
		add_child(_letter)
	else:
		_letter.position = Vector3(-0.01, 0.01, 0.212)                   # na licu modelu (układ modelu: szerokość 1, lico na z ≈ 0,2)
		_letter.no_depth_test = false
		_pivot.add_child(_letter)
	_burst_mi = MeshInstance3D.new()
	_burst_mi.mesh = _quad(BURST_PX * px)
	_burst_mi.material_override = _mat(_burst_sh, 14)
	_burst_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst_mi.top_level = true                                          # zostaje w miejscu celu, gdy znacznik gaśnie albo przechodzi dalej
	_burst_mi.visible = false
	add_child(_burst_mi)
	visible = false

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func _quad(side_m: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(side_m, side_m)
	return q

func _mat(sh: Shader, prio: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = prio
	return m

func _child(side_m: float, m: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad(side_m)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _setup_label3d(l: Label3D) -> void:
	l.shaded = false
	l.no_depth_test = true
	l.double_sided = true
	l.fixed_size = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Rzut brył `boxes` (AABB w metrach świata 3D) z oka kamery `eye` na płaszczyznę gry (z = 0) — prostokąt w pikselach świata 2D, który
## na ekranie dokładnie obejmuje bryły (perspektywa: model w głębi wychodzi mniejszy, przed płaszczyzną — większy). Pusty bez brył albo
## gdy całe leżą za okiem.
static func project_box(boxes: Array, eye: Vector3) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in boxes:
		var bb: AABB = b
		for i in 8:
			var p := bb.get_endpoint(i)
			if p.z >= eye.z - 0.01:
				continue
			var q := eye + (p - eye) * (eye.z / (eye.z - p.z))
			var px := Vector2(q.x, -q.y) / Level3D.PX
			lo = lo.min(px)
			hi = hi.max(px)
	return Rect2(lo, hi - lo) if lo.x <= hi.x else Rect2()

## Co klatkę: `node` — cel (null — brak), `offer` — jego oferta (interact.gd), `show` — czy znacznik może być widoczny, `calm` — bez oddechu
## i efektów („Reduce effects”), `fit` — rzut modelu celu (`project_box`; pusty — `box` oferty), `pressed` — w tej klatce wciśnięto [E].
func tick(delta: float, node: Node, offer: Dictionary, show: bool, calm: bool, fit := Rect2(), pressed := false) -> void:
	_t += delta
	var box: Rect2 = (fit if fit.size != Vector2.ZERO else offer.get("box", Rect2())) if node != null else Rect2()
	var zone: Rect2 = offer.get("box", box) if node != null else Rect2()   # strefa oferty: podłoga i wysokość w płaszczyźnie gry
	var want := show and node != null and box.size != Vector2.ZERO
	var prog := float(offer.get("prog", -1.0)) if node != null else -1.0
	# koniec przytrzymania: postęp był prawie pełny, a w tej klatce zniknął (cel skończony, zdjęty albo inny) — wybuch w miejscu klawisza
	if _last_prog >= 0.9 and prog < 0.0 and visible and show:
		_start_burst(global_position)
	_last_prog = prog
	if node != target:
		target = node
		_dwell = 0.0
		alpha = 0.0                               # nowy cel: bez przesuwania starego klawisza — pojawia się od nowa
		_shown_t = 0.0
		_heat = 0.0
	if want:
		_dwell += delta
		if _dwell >= DWELL_S:
			alpha = move_toward(alpha, 1.0, delta / FADE_S)
			_shown_t += delta
	else:
		alpha = move_toward(alpha, 0.0, delta / FADE_S)
	visible = alpha > 0.001
	_tick_burst(delta, calm)
	if not visible or box.size == Vector2.ZERO:
		state = "burst" if _burst >= 0.0 else "hidden"
		return
	var muted := bool(offer.get("muted", false))
	var holding := prog > 0.0
	if pressed and muted:
		_glitch = GLITCH_S
	elif pressed and int(offer.get("kind", 0)) == 0:
		_press = PRESS_S
		if not calm:
			_start_burst(global_position, 0.55)
	_glitch = maxf(0.0, _glitch - delta)
	_press = maxf(0.0, _press - delta)
	_heat = move_toward(_heat, clampf(prog, 0.0, 1.0) if holding else 0.0, delta * 4.0)
	state = "muted" if muted else ("hold" if holding else "ok")
	# środek prostokąta w płaszczyźnie gry, przesunięty po promieniu z oka do `z` przed płaszczyzną — na ekranie dalej w środku celu
	var surface := zone.end.y - minf(zone.size.y, SURFACE_PX)
	var anchor: Vector2 = offer.get("anchor", Vector2(box.get_center().x, surface - KEY_PX * 0.5 - TOP_GAP_PX))
	var p0 := Level3D.px_to_m(anchor)
	var z := Z_M if flat else MODEL_Z_M
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.z > z + 0.5:
		var eye := cam.global_position
		position = eye + (p0 - eye) * ((eye.z - z) / eye.z)
	else:
		position = p0 + Vector3(0.0, 0.0, z)
	# wskakiwanie: skala 0,6 → 1 z przestrzeleniem; wciśnięcie: chwilowo 0,86
	var u := clampf(_shown_t / APPEAR_S, 0.0, 1.0)
	var pop := 1.0 if calm else 0.6 + 0.4 * (1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0))
	var dip := 1.0 - 0.14 * sin(PI * (1.0 - _press / PRESS_S)) if _press > 0.0 else 1.0
	var s := pop * dip
	scale = Vector3(s, s, 1.0 if flat else s)
	if _pivot != null:
		_pivot.rotation.y = 0.0 if calm else 0.09 * sin(_t * 1.4)                 # lekkie kołysanie — klawisz jest bryłą
		_pivot.position.z = -0.25 * KEY_PX * Level3D.PX * (1.0 - dip) / 0.14
		for mm in _model_mats:
			var smm := mm as ShaderMaterial
			smm.set_shader_parameter("fade", alpha)
			smm.set_shader_parameter("muted", 1.0 if muted else 0.0)
			smm.set_shader_parameter("glitch", 0.0 if calm else _glitch / GLITCH_S)
			smm.set_shader_parameter("heat", _heat)
			smm.set_shader_parameter("t", _t)
	var breath := 1.0 if (calm or muted or holding) else 0.75 + 0.25 * (0.5 + 0.5 * sin(_t * TAU / PULSE_S))
	var col := TINT_MUTED if muted else TINT.lerp(TINT_HOT, smoothstep(0.15, 0.95, _heat))
	_cap_m.set_shader_parameter("fade", alpha)
	_cap_m.set_shader_parameter("muted", 1.0 if muted else 0.0)
	_cap_m.set_shader_parameter("glitch", 0.0 if calm else _glitch / GLITCH_S)
	_cap_m.set_shader_parameter("heat", _heat)
	_cap_m.set_shader_parameter("t", _t)
	var gm := _glow.material_override as ShaderMaterial
	gm.set_shader_parameter("tint", Color(1.0, 0.2, 0.1) if _glitch > 0.0 else col)
	gm.set_shader_parameter("k", alpha * (0.0 if muted and _glitch <= 0.0 else (0.55 + 0.6 * _heat) * breath))
	(_shade.material_override as ShaderMaterial).set_shader_parameter("k", alpha * 0.55)
	var rm := _ring.material_override as ShaderMaterial
	_ring.visible = holding
	rm.set_shader_parameter("prog", clampf(prog, 0.0, 1.0))
	rm.set_shader_parameter("tint", col)
	rm.set_shader_parameter("hot", smoothstep(0.0, 0.6, _heat))
	rm.set_shader_parameter("fade", alpha)
	rm.set_shader_parameter("t", _t)
	rm.set_shader_parameter("sparks", 0.0 if calm else 1.0)
	_letter.text = Actions.key("interact")
	_letter.pixel_size = (KEY_PX * Level3D.PX if flat else 1.0) * (0.0042 if _letter.text.length() <= 1 else 0.0042 * 1.6 / float(_letter.text.length()))
	var lc := LETTER.lerp(LETTER_HOT, maxf(_heat, _press / PRESS_S))
	if muted:
		lc = Color(0.55, 0.53, 0.5)
	if _glitch > 0.0:
		lc = Color(1.4, 0.3, 0.2)
	_letter.modulate = Color(lc, alpha)
	_letter.outline_modulate = Color(0.12, 0.07, 0.04, 0.85 * alpha)

## Warstwy kamer widoku 3D (view3d.gd): cały znacznik w obrazie świata. Kamera graczy (postacie, pierwszy plan) rysuje się na wierzchu,
## więc klawisz leży „pomiędzy” — nad meblami celu, pod postacią gracza (INTERACT_KEY_PLAN.md „Plan obrazu”). `_actors` zostaje w podpisie
## na wypadek wariantu przed graczem.
func set_view_layers(world: int, _actors: int) -> void:
	layers = world
	for n in find_children("*", "", true, false):
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = world

func _start_burst(at: Vector3, power := 1.0) -> void:
	_burst = 0.0
	_burst_pos = at
	var bm := _burst_mi.material_override as ShaderMaterial
	bm.set_shader_parameter("k", power)
	bm.set_shader_parameter("tint", TINT_HOT.lerp(TINT, 0.35) if power >= 1.0 else TINT)

func _tick_burst(delta: float, calm: bool) -> void:
	if _burst < 0.0:
		_burst_mi.visible = false
		return
	_burst += delta
	var bt := _burst / BURST_S
	if bt >= 1.0:
		_burst = -1.0
		_burst_mi.visible = false
		return
	_burst_mi.visible = true
	_burst_mi.global_position = _burst_pos
	var bm := _burst_mi.material_override as ShaderMaterial
	bm.set_shader_parameter("bt", bt)
	bm.set_shader_parameter("rays", 0.0 if calm else 1.0)

