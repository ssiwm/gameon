extends Node2D
## Odbicie podłogi kryjówki (ATMOSPHERE_PLAN.md, F6): pas pod linią podłogi pokazuje lustrzane odbicie świata ponad nią (z tekstury ekranu),
## przygasające z głębokością i lekko falujące. Czysta kosmetyka, lokalna. Poziom jakości (Settings.quality_idx): LOW — brak,
## MEDIUM — statyczne, HIGH — z falowaniem; „Reduce effects” zatrzymuje falowanie.

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float floor_v = 0.7;        // współrzędna ekranu (0..1) linii podłogi
uniform float strength = 0.30;
uniform float depth = 0.10;         // na jakiej wysokości ekranu (0..1) odbicie gaśnie
uniform float wobble = 0.0;
uniform float t = 0.0;
void fragment() {
	float d = SCREEN_UV.y - floor_v;
	if (d <= 0.0) {
		discard;
	}
	float w = sin(SCREEN_UV.y * 140.0 + t * 1.6) * 0.0016 * wobble + sin(SCREEN_UV.y * 61.0 - t * 1.1) * 0.0012 * wobble;
	vec3 c = texture(screen_tex, vec2(SCREEN_UV.x + w, floor_v - d)).rgb;
	float fade = 1.0 - smoothstep(0.0, depth, d);
	COLOR = vec4(c, strength * fade);
}
"""

const HEIGHT_PX := 56.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _floor_y := 0.0
var _t := 0.0

func setup(width_px: float, floor_y: float) -> void:
	_floor_y = floor_y
	z_index = 4
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.position = Vector2(0.0, floor_y + 1.0)
	_rect.size = Vector2(width_px, HEIGHT_PX)
	add_child(_rect)

func _process(delta: float) -> void:
	var q: int = Settings.quality_idx
	_rect.visible = q >= 1
	if not _rect.visible:
		return
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size
	var floor_screen := (vp.get_canvas_transform() * Vector2(0.0, _floor_y)).y
	_mat.set_shader_parameter("floor_v", floor_screen / maxf(vs.y, 1.0))
	var moving := q >= 2 and Settings.fx_mult() > 0.0
	_mat.set_shader_parameter("wobble", 1.0 if moving else 0.0)
	if moving:
		_t += delta
		_mat.set_shader_parameter("t", _t)
