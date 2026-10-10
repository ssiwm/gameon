extends Node2D
## Smuga światła w powietrzu pod lampą (plan ATMOSPHERE_PLAN.md, F1): rozszerzający się w dół stożek z przewijanym szumem, rysowany
## addytywnie i „unshaded”, oraz kilka drobin kurzu pływających w smudze. Czysta kosmetyka, lokalna — nic nie rozstrzyga rozgrywki.
## Długość wyznacza promień w dół do podłogi (nie wychodzi pod ziemię). Poziom jakości (Settings.quality_idx): LOW — brak smugi,
## MEDIUM — smuga statyczna, HIGH — animowany szum i kurz; „Reduce effects” zatrzymuje ruch i kurz.

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")

const SHADER := """
shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float strength = 0.2;
uniform float t = 0.0;
uniform float top_w = 0.10;        // szerokość stożka przy lampie względem szerokości przy podłodze
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float along = UV.y;                                        // 0 przy lampie, 1 przy podłodze
	float x = (UV.x * 2.0 - 1.0) / mix(top_w, 1.0, along);     // 1 = krawędź stożka
	float cone = 1.0 - smoothstep(0.35, 1.0, abs(x));
	float fall = pow(1.0 - along, 1.25) * smoothstep(0.0, 0.06, along);
	float n = vnoise(vec2(x * 2.5 + t * 0.04, along * 3.0 - t * 0.10));
	float n2 = vnoise(vec2(x * 6.0 - t * 0.07, along * 8.0 + t * 0.04));
	float shaft = cone * fall * (0.55 + 0.55 * n + 0.3 * n2);
	COLOR = vec4(tint.rgb, shaft * strength);
}
"""

const WIDTH := 70.0                   ## szerokość u podłogi (px świata)
const BASE_STRENGTH := 0.22

var _rect: ColorRect
var _mat: ShaderMaterial
var _dust: CPUParticles2D
var _t := 0.0
var _len := 120.0
var _quality := -1

func _ready() -> void:
	z_index = 3
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	_set_length(_len)
	_dust = CPUParticles2D.new()
	_dust.amount = 16
	_dust.lifetime = 7.0
	_dust.preprocess = 7.0
	_dust.local_coords = true
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.direction = Vector2(0.3, 1.0)
	_dust.spread = 180.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 4.0
	_dust.gravity = Vector2(0.0, 0.5)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.1
	_dust.color = Color(1.0, 0.9, 0.7, 0.55)
	_dust.material = Lights.unshaded()
	Vfx.soften(_dust)
	add_child(_dust)
	_apply_quality()
	_probe_floor.call_deferred()

## Długość smugi: promień w dół od lampy do podłogi (maska świata 1), z rozsądnym zakresem.
func _probe_floor() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	var space := get_world_2d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, 260.0), 1)
	var hit := space.intersect_ray(q)
	_set_length(clampf(float(hit["position"].y) - from.y, 36.0, 240.0) if not hit.is_empty() else 150.0)

func _set_length(l: float) -> void:
	_len = l
	_rect.position = Vector2(-WIDTH * 0.5, 0.0)
	_rect.size = Vector2(WIDTH, l)
	if _dust != null:
		_dust.position = Vector2(0.0, l * 0.55)
		_dust.emission_rect_extents = Vector2(WIDTH * 0.22, l * 0.4)

## Poziom migotania lampy (≈ 0,86–1,0): smuga drga razem ze światłem.
func set_level(f: float) -> void:
	_mat.set_shader_parameter("strength", BASE_STRENGTH * f)

func _apply_quality() -> void:
	var q: int = Settings.quality_idx
	_quality = q
	visible = q >= 1
	_dust.emitting = q >= 2 and Settings.fx_mult() > 0.0
	_dust.visible = q >= 2

func _process(delta: float) -> void:
	if _quality != Settings.quality_idx:
		_apply_quality()
	if not visible:
		return
	if _quality >= 2 and Settings.fx_mult() > 0.0:
		_t += delta
		_mat.set_shader_parameter("t", _t)
