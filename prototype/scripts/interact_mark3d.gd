extends MeshInstance3D
## Znacznik celu interakcji w widoku 3D (INTERACT_KEY_PLAN.md; wcześniej ramka z narożników, INTERACT_PLAN.md I3): mały, zardzewiały
## klawisz na wierzchu obiektu, który wybrał arbiter interakcji (interact.gd). Przy broni i gablocie z przypisanymi oględzinami — para
## [E] + [H]; na padzie Classic (oględziny przytrzymaniem) — jeden [B] z drutem przytrzymania 0,4 s. Bez podpisu: nazwa akcji i koszt
## zostają w pasku akcji HUD. Bez światła sceny, mgły i cienia (światło udawane w shaderze modelu).
##
## Stany (klatki arkusza inspiracji art_src/ui/interact_key_ref.png):
## - pojawienie — po DWELL_S przy tym samym celu klawisz wskakuje ze skali 0,6 z lekkim przestrzeleniem (APPEAR_S);
## - możliwa — bursztynowa poświata z oddechem jasności, lekkie kołysanie bryły (bez obu przy „Reduce effects”);
## - niemożliwa (brak desek, broń zablokowana) — klawisz wyszarzony, bez poświaty; naciśnięcie daje czerwone „zakłócenie” (GLITCH_S);
## - naciśnięcie (stanowiska, broń, oględziny) — klawisz wciśnięty w głąb i do 0,86, litera rozżarzona, mały błysk;
## - przytrzymanie — drut kolczasty owija klawisz od góry zgodnie z zegarem do postępu, poświata i drut z bursztynu w czerwień, litera
##   i lico się rozżarzają, na końcu drutu iskrzy;
## - koniec przytrzymania — wybuch: błysk, promienie, iskry i fala (BURST_S), potem żarzące się okruchy.
##
## Położenie (INTERACT_KEY_PLAN.md „Położenie”): oś pozioma = środek rzutu modeli celu (`fit`, bez modelu — strefa `box` oferty),
## wysokość = wierzch obiektu ze strefy oferty w płaszczyźnie gry: górna krawędź strefy, najwyżej SURFACE_PX nad podłogą. Pozycja stała —
## nie reaguje na gracza. Oferta może podać własny punkt `anchor` (px świata, środek klawisza albo pary).
## Plan obrazu: cały znacznik w obrazie świata, MODEL_Z_M przed płaszczyzną gry (przed meblami w głębi); postać gracza rysuje kamera graczy
## na wierzchu — klawisz leży „pomiędzy” meblem a graczem.

const Level3D := preload("res://scripts/level3d.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")

const RING_TEX := preload("res://art/world3d/interact/key_ring.png")
const CAP_GLB := "res://art/world3d/interact/key_cap.glb"   ## model nakładki z Meshy (tools/blender_key_cap.py), bez litery

const TINT := Color(1.0, 0.72, 0.30)          ## bursztyn podpowiedzi (jak door_hint3d.gd TINT)
const TINT_HOT := Color(1.0, 0.22, 0.08)      ## czerwień pełnego przytrzymania
const TINT_MUTED := Color(0.62, 0.6, 0.55)
const TINT_GLITCH := Color(1.0, 0.2, 0.1)
const LETTER := Color(0.93, 0.87, 0.74)
const LETTER_HOT := Color(1.6, 0.62, 0.26)    ## rozżarzona litera (HDR — łapie poświatę środowiska)
const LETTER_MUTED := Color(0.55, 0.53, 0.5)
const LETTER_GLITCH := Color(1.4, 0.3, 0.2)
const DWELL_S := 0.15                         ## s przy tym samym celu, zanim znacznik się pokaże
const FADE_S := 0.2
const APPEAR_S := 0.22
const PULSE_S := 1.2                          ## okres oddechu jasności
const GLITCH_S := 0.32
const PRESS_S := 0.18
const BURST_S := 0.9
const KEY_PX := 4.0                           ## bok klawisza w pikselach świata (gracz ma ok. 22 px; 10 i 6 px były za duże)
const PAIR_GAP_PX := 1.0                      ## odstęp klawiszy pary [E] + [H]
const RING_PX := KEY_PX * 1.85                ## bok tekstury pierścienia (drut z kolcami)
const GLOW_PX := KEY_PX * 2.6
const SHADE_PX := KEY_PX * 2.2                ## ciemny podkład pod klawiszem (decyzja 3)
const SHADE_ALPHA := 0.7
const BURST_PX := KEY_PX * 4.0
const TOP_GAP_PX := 0.8                       ## odstęp spodu klawisza od wierzchu obiektu
const SURFACE_PX := 11.0                      ## najwyższy „wierzch” obiektu nad podłogą (ok. 0,9 m — blat ławy)
const MODEL_Z_M := 0.6                        ## środek klawisza przed płaszczyzną gry [m]: przed meblami (z testem głębi)
const MODEL_TILT := -20.0                     ## stopnie: lico odchylone w górę, widać dolne fazowanie jak na arkuszu
## Przytrzymanie [B] na padzie Classic (`look`, 0..1 z Actions.INSPECT_HOLD_S): drut dopiero od tej części czasu (0,1 z 0,4 s), żeby
## szybkie stuknięcie (wzięcie broni) nie migało drutem.
const LOOK_RING_FROM := 0.25
const PRESS_BURST := 0.55                     ## siła małego błysku naciśnięcia (pełny wybuch przytrzymania — 1)

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform float k = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
	ALBEDO = tint.rgb;
	ALPHA = g * k;
}
"""

## Ciemny podkład pod klawiszem (albo parą): miękkie przyciemnienie tła, żeby klawisz był czytelny na jasnej ścianie i tablicy narzędzi.
## Za modelem z testem głębi (model go zasłania) i rysowany po poświacie (render_priority wyżej): poświata większa od podkładu zostaje
## bursztynową obwódką wokół ciemnej plamy.
const SHADE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float k = 0.0;
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	ALBEDO = vec3(0.02, 0.015, 0.01);
	ALPHA = (1.0 - smoothstep(0.35, 1.0, d)) * k;
}
"""

## Pierścień: tekstura z Blendera (R jasność, G krycie, B poświata), odsłaniana po kącie od góry zgodnie z zegarem do `prog`.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
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

## Jeden klawisz znacznika: model nakładki z literą, poświata i drut przytrzymania, stan efektów. [E] / [B] i [H] to dwa egzemplarze.
class MarkKey:
	var root: Node3D                           ## miejsce klawisza w parze (x)
	var pivot: Node3D                          ## odchylenie, kołysanie, wciśnięcie
	var letter: Label3D
	var mats: Array = []                       ## ShaderMaterial modelu
	var glow: MeshInstance3D
	var ring: MeshInstance3D
	var action := "interact"                   ## akcja z actions.gd — litera klawisza
	var glitch := 0.0                          ## s zakłócenia
	var press := 0.0                           ## s wciśnięcia
	var heat := 0.0                            ## wygładzony postęp przytrzymania
	var last_prog := -1.0                      ## postęp drutu z poprzedniej klatki (koniec przytrzymania → wybuch)
	var state := "ok"                          ## ok / muted / hold

static var _glow_sh: Shader
static var _ring_sh: Shader
static var _burst_sh: Shader
static var _model_sh: Shader
static var _shade_sh: Shader

var target: Node = null                       ## obiekt, przy którym stoi znacznik (test, view3d)
var alpha := 0.0                              ## bieżąca widoczność 0..1 (bez oddechu)
var state := "hidden"                         ## hidden / ok / muted / hold / burst — stan klawisza [E] dla testu i zrzutów
var pair := false                             ## widać parę [E] + [H]
var keys: Array = []                          ## [MarkKey [E] / [B], MarkKey [H]]
var _dwell := 0.0
var _t := 0.0
var _shown_t := 0.0                           ## s od pojawienia się (wskakiwanie)
var _burst := -1.0                            ## s od początku wybuchu (< 0 — bez wybuchu)
var _burst_pos := Vector3.ZERO
var _look_last := -1.0                        ## przytrzymanie [B] (pad Classic) z poprzedniej klatki — puszczenie przed czasem = naciśnięcie
var _shade: MeshInstance3D
var _burst_mi: MeshInstance3D

func _ready() -> void:
	if _model_sh == null:
		_glow_sh = _shader(GLOW_SHADER)
		_ring_sh = _shader(RING_SHADER)
		_burst_sh = _shader(BURST_SHADER)
		_model_sh = _shader(MODEL_SHADER)
		_shade_sh = _shader(SHADE_SHADER)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var px := Level3D.PX
	_shade = _quad_mi(SHADE_PX * px, _mat(_shade_sh, 11))
	_shade.position.z = -0.35 * KEY_PX * px                             # za nakładką, przed poświatą
	add_child(_shade)
	keys = [_make_key("interact"), _make_key("inspect_weapon")]
	_burst_mi = _quad_mi(BURST_PX * px, _mat(_burst_sh, 14))
	_burst_mi.top_level = true                                          # zostaje w miejscu celu, gdy znacznik gaśnie albo przechodzi dalej
	_burst_mi.visible = false
	add_child(_burst_mi)
	visible = false

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func _mat(sh: Shader, prio: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = prio
	return m

func _quad_mi(side_m: float, m: ShaderMaterial) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(side_m, side_m)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Klawisz: model z Meshy (litera Label3D na licu), poświata za nim i drut przytrzymania wokół.
func _make_key(action: String) -> MarkKey:
	var px := Level3D.PX
	var key_m := KEY_PX * px
	var k := MarkKey.new()
	k.action = action
	k.root = Node3D.new()
	add_child(k.root)
	k.glow = _quad_mi(GLOW_PX * px, _mat(_glow_sh, 10))
	k.glow.position.z = -0.3 * key_m                                    # za nakładką (z testem głębi)
	k.root.add_child(k.glow)
	k.pivot = Node3D.new()
	k.pivot.scale = Vector3.ONE * key_m
	k.pivot.rotation_degrees.x = MODEL_TILT
	k.root.add_child(k.pivot)
	var sc := (load(CAP_GLB) as PackedScene).instantiate()
	k.pivot.add_child(sc)
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m3.mesh.get_surface_count():
			var sm := m3.mesh.surface_get_material(si) as BaseMaterial3D
			var mm := _mat(_model_sh, 0)
			mm.set_shader_parameter("albedo_tex", sm.albedo_texture if sm != null else null)
			m3.set_surface_override_material(si, mm)
			k.mats.append(mm)
	k.letter = Label3D.new()
	k.letter.font = load(UiTheme.FONT_BODY_BOLD)
	k.letter.font_size = 128
	k.letter.outline_size = 18
	k.letter.outline_modulate = Color(0.12, 0.07, 0.04, 0.85)
	k.letter.render_priority = 13
	k.letter.outline_render_priority = 12
	k.letter.shaded = false
	k.letter.double_sided = true
	k.letter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.letter.position = Vector3(-0.01, 0.01, 0.212)                     # na licu modelu (układ modelu: szerokość 1, lico na z ≈ 0,2)
	k.pivot.add_child(k.letter)
	k.ring = _quad_mi(RING_PX * px, _mat(_ring_sh, 11))
	(k.ring.material_override as ShaderMaterial).set_shader_parameter("ring", RING_TEX)
	k.root.add_child(k.ring)
	return k

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

## Punkt klawisza (albo środka pary) w pikselach świata: `anchor` oferty albo oś `fit` na wierzchu strefy `zone` (INTERACT_KEY_PLAN.md
## „Położenie”). Statyczne — sprawdza test_interact.gd.
static func anchor_px(offer: Dictionary, fit: Rect2) -> Vector2:
	var zone: Rect2 = offer.get("box", fit)
	var axis: Rect2 = fit if fit.size != Vector2.ZERO else zone
	var surface := zone.end.y - minf(zone.size.y, SURFACE_PX)
	return offer.get("anchor", Vector2(axis.get_center().x, surface - KEY_PX * 0.5 - TOP_GAP_PX))

## Postęp drutu przy przytrzymaniu [B] na padzie Classic: `look` (0..1 z Actions.INSPECT_HOLD_S, < 0 — nie trzymane) → drut 0..1 od
## LOOK_RING_FROM; przed progiem −1 (krótkie stuknięcie bez drutu).
static func look_ring(look: float) -> float:
	return -1.0 if look < LOOK_RING_FROM else clampf((look - LOOK_RING_FROM) / (1.0 - LOOK_RING_FROM), 0.0, 1.0)

## Co klatkę: `node` — cel (null — brak), `offer` — jego oferta (interact.gd; broń: `alt` — akcja drugiego klawisza, `alt_hold` —
## oględziny przytrzymaniem [B]), `show` — czy znacznik może być widoczny, `calm` — bez oddechu i efektów („Reduce effects”), `fit` — rzut
## modeli celu (`project_box`), `pressed` — w tej klatce wciśnięto [E] / [B], `pressed_alt` — [H], `look` — przytrzymanie [B] na padzie
## Classic (weapon_controller.pad_look_progress).
func tick(delta: float, node: Node, offer: Dictionary, show: bool, calm: bool, fit := Rect2(), pressed := false, pressed_alt := false, look := -1.0) -> void:
	_t += delta
	var box: Rect2 = (fit if fit.size != Vector2.ZERO else offer.get("box", Rect2())) if node != null else Rect2()
	var want := show and node != null and box.size != Vector2.ZERO
	var alt := String(offer.get("alt", "")) if node != null else ""
	var alt_hold := bool(offer.get("alt_hold", false)) if node != null else false
	# [E] / [B]: postęp drutu z oferty (przytrzymanie) albo z przytrzymania [B] na padzie; puszczenie [B] przed czasem = naciśnięcie
	var prog := float(offer.get("prog", -1.0)) if node != null else -1.0
	var press_e := pressed and int(offer.get("kind", 0)) == 0 and not alt_hold
	var glitch_e := pressed and bool(offer.get("muted", false)) and not alt_hold
	if alt_hold:
		prog = look_ring(look)
		if _look_last >= 0.0 and look < 0.0 and _look_last < 1.0 and keys[0].last_prog < 0.9:
			press_e = true                                            # krótkie [B]: wzięcie broni
			glitch_e = bool(offer.get("muted", false))
	_look_last = look if alt_hold else -1.0
	if node != target:
		target = node
		_dwell = 0.0
		alpha = 0.0                               # nowy cel: bez przesuwania starego klawisza — pojawia się od nowa
		_shown_t = 0.0
		for k in keys:
			(k as MarkKey).heat = 0.0
	if want:
		_dwell += delta
		if _dwell >= DWELL_S:
			alpha = move_toward(alpha, 1.0, delta / FADE_S)
			_shown_t += delta
	else:
		alpha = move_toward(alpha, 0.0, delta / FADE_S)
	var was_visible := visible
	visible = alpha > 0.001
	# koniec przytrzymania: drut był prawie pełny, a w tej klatce zniknął (cel skończony, zdjęty, oględziny otwarte) — wybuch w miejscu klawisza
	for k in keys:
		var kk := k as MarkKey
		var kp := prog if kk == keys[0] else -1.0
		if kk.last_prog >= 0.9 and kp < 0.0 and was_visible and kk.root.visible:
			_start_burst(kk.root.global_position, 1.0)
		kk.last_prog = kp
	_tick_burst(delta, calm)
	if not visible or box.size == Vector2.ZERO:
		state = "burst" if _burst >= 0.0 else "hidden"
		return
	# położenie: punkt w płaszczyźnie gry przesunięty po promieniu z oka do MODEL_Z_M przed płaszczyzną — na ekranie zostaje na miejscu
	var p0 := Level3D.px_to_m(anchor_px(offer, fit))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.z > MODEL_Z_M + 0.5:
		var eye := cam.global_position
		position = eye + (p0 - eye) * ((eye.z - MODEL_Z_M) / eye.z)
	else:
		position = p0 + Vector3(0.0, 0.0, MODEL_Z_M)
	pair = alt != ""
	var half := (KEY_PX + PAIR_GAP_PX) * 0.5 * Level3D.PX if pair else 0.0
	keys[0].root.position.x = -half
	keys[1].root.position.x = half
	keys[1].root.visible = pair
	keys[1].action = alt if pair else "inspect_weapon"
	_shade.scale = Vector3(2.0 * half / (KEY_PX * Level3D.PX) + 1.0 if pair else 1.0, 1.0, 1.0)
	(_shade.material_override as ShaderMaterial).set_shader_parameter("k", alpha * SHADE_ALPHA)
	# wskakiwanie: skala 0,6 → 1 z przestrzeleniem
	var u := clampf(_shown_t / APPEAR_S, 0.0, 1.0)
	var pop := 1.0 if calm else 0.6 + 0.4 * (1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0))
	scale = Vector3.ONE * pop
	_tick_key(keys[0], delta, calm, bool(offer.get("muted", false)), prog, press_e, glitch_e)
	if pair:
		# [H]: oględziny są dozwolone także przy broni zablokowanej — klawisz zostaje aktywny
		_tick_key(keys[1], delta, calm, false, -1.0, pressed_alt, false)
	state = keys[0].state

## Stan jednego klawisza: `muted` — oferta niemożliwa, `prog` — drut 0..1 (< 0 — bez przytrzymania), `press` — wciśnięcie w tej klatce,
## `glitch` — naciśnięcie przy niemożliwej.
func _tick_key(k: MarkKey, delta: float, calm: bool, muted: bool, prog: float, press: bool, glitch: bool) -> void:
	var holding := prog >= 0.0
	if glitch:
		k.glitch = GLITCH_S
	elif press and not muted:
		k.press = PRESS_S
		if not calm:
			_start_burst(k.root.global_position, PRESS_BURST)
	k.glitch = maxf(0.0, k.glitch - delta)
	k.press = maxf(0.0, k.press - delta)
	k.heat = move_toward(k.heat, clampf(prog, 0.0, 1.0) if holding else 0.0, delta * 4.0)
	k.state = "muted" if muted else ("hold" if holding else "ok")
	var dip := 1.0 - 0.14 * sin(PI * (1.0 - k.press / PRESS_S)) if k.press > 0.0 else 1.0
	k.pivot.scale = Vector3.ONE * KEY_PX * Level3D.PX * dip
	k.pivot.position.z = -0.25 * KEY_PX * Level3D.PX * (1.0 - dip) / 0.14
	k.pivot.rotation.y = 0.0 if calm else 0.09 * sin(_t * 1.4 + (0.0 if k == keys[0] else 0.9))     # lekkie kołysanie — klawisz jest bryłą
	var gl := 0.0 if calm else k.glitch / GLITCH_S
	for mm in k.mats:
		var smm := mm as ShaderMaterial
		smm.set_shader_parameter("fade", alpha)
		smm.set_shader_parameter("muted", 1.0 if muted else 0.0)
		smm.set_shader_parameter("glitch", gl)
		smm.set_shader_parameter("heat", k.heat)
		smm.set_shader_parameter("t", _t)
	var breath := 1.0 if (calm or muted or holding) else 0.75 + 0.25 * (0.5 + 0.5 * sin(_t * TAU / PULSE_S))
	var col := TINT_MUTED if muted else TINT.lerp(TINT_HOT, smoothstep(0.15, 0.95, k.heat))
	var gm := k.glow.material_override as ShaderMaterial
	gm.set_shader_parameter("tint", TINT_GLITCH if k.glitch > 0.0 else col)
	gm.set_shader_parameter("k", alpha * (0.0 if muted and k.glitch <= 0.0 else (0.45 + 0.6 * k.heat) * breath))
	var rm := k.ring.material_override as ShaderMaterial
	k.ring.visible = holding
	rm.set_shader_parameter("prog", clampf(prog, 0.0, 1.0))
	rm.set_shader_parameter("tint", col)
	rm.set_shader_parameter("hot", smoothstep(0.0, 0.6, k.heat))
	rm.set_shader_parameter("fade", alpha)
	rm.set_shader_parameter("t", _t)
	rm.set_shader_parameter("sparks", 0.0 if calm else 1.0)
	k.letter.text = Actions.key(k.action)
	k.letter.pixel_size = 0.0042 if k.letter.text.length() <= 1 else 0.0042 * 1.6 / float(k.letter.text.length())
	var lc := LETTER.lerp(LETTER_HOT, maxf(k.heat, k.press / PRESS_S))
	if muted:
		lc = LETTER_MUTED
	if k.glitch > 0.0:
		lc = LETTER_GLITCH
	k.letter.modulate = Color(lc, alpha)
	k.letter.outline_modulate = Color(0.12, 0.07, 0.04, 0.85 * alpha)

## Warstwy kamer widoku 3D (view3d.gd): cały znacznik w obrazie świata. Kamera graczy (postacie, pierwszy plan) rysuje się na wierzchu,
## więc klawisz leży „pomiędzy” — nad meblami celu, pod postacią gracza (INTERACT_KEY_PLAN.md „Plan obrazu”).
func set_view_layers(world: int) -> void:
	layers = world
	for n in find_children("*", "", true, false):
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = world

func _start_burst(at: Vector3, power: float) -> void:
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
