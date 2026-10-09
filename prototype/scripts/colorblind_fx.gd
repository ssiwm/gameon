extends CanvasLayer
## Filtr kolorów dla osób z zaburzeniami widzenia barw (ustawienie „Color vision": protanopia / deuteranopia / tritanopia).
## Daltonizacja całego obrazu — świata i interfejsu — jednym przejściem shadera nad wszystkim: symulacja braku danego czopka
## w przestrzeni LMS, a utracona różnica (czerwień ↔ zieleń itd.) zostaje przesunięta do kanałów, które osoba rozróżnia.
## Wyłączone (OFF) nie dodaje przejścia, więc nic nie kosztuje.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform int mode = 1;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 lms = c * mat3(vec3(17.8824, 43.5161, 4.11935), vec3(3.45565, 27.1554, 3.86714), vec3(0.0299566, 0.184309, 1.46709));
	vec3 s = lms;
	if (mode == 1) {
		s.x = 2.02344 * lms.y - 2.52581 * lms.z;
	} else if (mode == 2) {
		s.y = 0.494207 * lms.x + 1.24827 * lms.z;
	} else {
		s.z = -0.395913 * lms.x + 0.801109 * lms.y;
	}
	vec3 sim = s * mat3(vec3(0.0809444479, -0.130504409, 0.116721066), vec3(-0.0102485335, 0.0540193266, -0.113614708), vec3(-0.000365296938, -0.00412161469, 0.693511405));
	vec3 err = c - sim;
	vec3 corr = vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
	COLOR = vec4(clamp(c + corr, 0.0, 1.0), 1.0);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 100
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	Settings.changed.connect(_apply)
	_apply()

func _apply() -> void:
	var m: int = Settings.colorblind_idx
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--colorblind="):
			m = clampi(int(a.substr("--colorblind=".length())), 0, 3)          # dev: podgląd filtra do zrzutu (1 prot, 2 deut, 3 trit)
	_rect.visible = m > 0
	_mat.set_shader_parameter("mode", m)
