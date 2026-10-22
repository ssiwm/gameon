extends ColorRect
## Strzelnica FPP — obraz przez optykę przy pełnym celowaniu (RANGE_FPS_PLAN.md, etap 2). Kolimator WRATH-4 i noktowizor FALCON-6 to w modelu
## zamknięte tuby na linii przyrządów (gun_proc.py: `sight_optic` w gun_<klucz>.json) — z bliska zasłaniałyby cel, więc pod koniec podnoszenia
## broni do oka model gaśnie (range_view.gd), a ta nakładka pokazuje okrągłe pole widzenia: kolimator — czerwona kropka, noktowizor — zielony,
## ziarnisty obraz z siatką (przyrost jasności jak we wzmacniaczu obrazu). Celownik to interfejs, więc wyjątek od zasady „tylko 3D”.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float k = 0.0;            // 0..1 — wejście w optykę
uniform int kind = 0;             // 0 kolimator, 1 noktowizor
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	vec2 p = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	float r = length(p);
	float R = mix(0.62, 0.34, k);                                       // pole widzenia zwęża się do tuby przy wejściu
	float outside = smoothstep(R, R + 0.015, r);
	vec3 col = base;
	if (kind == 1) {
		float l = dot(base, vec3(0.3, 0.59, 0.11));
		float g = pow(clamp(l * 3.2, 0.0, 1.0), 0.75);                 // wzmacniacz obrazu: ciemny tunel jasny
		g += (hash(floor(FRAGCOORD.xy * 0.5) + floor(TIME * 24.0)) - 0.5) * 0.12;
		col = vec3(0.12, 1.0, 0.32) * g + vec3(0.0, 0.05, 0.01);
		col *= 1.0 - 0.45 * smoothstep(R * 0.55, R, r);                // ciemniejszy brzeg okularu
		float w = 0.0012;                                               // siatka: słupek od dołu do środka i dwie poziome kreski z przerwą
		float post = step(abs(p.x), w) * step(0.0, p.y) * step(p.y, R);
		float bars = step(abs(p.y), w) * step(0.03, abs(p.x)) * step(abs(p.x), R * 0.7);
		col = mix(col, vec3(0.0, 0.08, 0.02), max(post, bars) * 0.85);
	} else {
		col *= 1.0 - 0.35 * smoothstep(R * 0.8, R, r);                // wnętrze tuby
		float d = smoothstep(0.0042, 0.0022, r);                        // kropka i jej poświata
		float halo = exp(-r * r / 0.00009) * 0.5;
		col = mix(col, vec3(1.0, 0.12, 0.06), clamp(d + halo, 0.0, 1.0));
	}
	col = mix(col, vec3(0.0), outside);
	COLOR = vec4(mix(base, col, k), 1.0);
}
"""

var _mat: ShaderMaterial

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)                # przed dodaniem do warstwy (jak obraz tunelu): w _ready rozmiar zostawał 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	visible = false

## Optyka `kind` ("dot" / "nv", "" — brak) przy postępie wejścia `k` 0..1.
func show_optic(kind: String, k: float) -> void:
	visible = kind != "" and k > 0.001
	if not visible:
		return
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("kind", 1 if kind == "nv" else 0)
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
