extends CanvasLayer
## Obraz w klimacie horroru (tylko grafika HD): gradacja kolorów (chłodne cienie, ciepłe światła), winieta i aberracja chromatyczna na brzegach kadru — rosną z poziomem Uwagi
## (NoiseMgr.level) — oraz ostrzeżenie o stanie lokalnego gracza: przy niskim życiu obraz traci kolor, rogi czerwienieją i pulsują w rytmie tętna.
## Warstwa leży nad światem, pod HUD-em (UI), więc interfejs zostaje ostry. Jedno przejście shadera po całym ekranie; wyłącza je `--nofx`.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette = 0.4;
uniform float aberration = 0.001;
uniform float desat = 0.0;
uniform float hurt_pulse = 0.0;
uniform float aspect = 1.78;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = length(c * vec2(aspect, 1.0));
	vec2 dir = c * d;
	float ab = aberration * 2.0;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ab).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// gradacja: cienie chłodne (sine), światła ciepłe — kontrast „bezpieczne światło, wrogi mrok"
	col *= mix(vec3(0.88, 1.0, 1.16), vec3(1.12, 1.0, 0.86), smoothstep(0.04, 0.42, lum));
	lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desat);
	float v = smoothstep(0.32, 0.98, d);
	col *= 1.0 - v * vignette;
	col += vec3(0.55, 0.02, 0.03) * hurt_pulse * v;
	COLOR = vec4(col, 1.0);
}
"""

const BASE_VIGNETTE := 0.42
const BASE_ABERRATION := 0.0007

var _mat: ShaderMaterial
var _rect: ColorRect
var _attn := 0.0                     ## wygładzona Uwaga 0..1
var _hurt := 0.0                     ## wygładzony stan zdrowia lokalnego gracza 0..1
var _t := 0.0
var _dev_noise := -1.0               ## dev: --shotnoise=N (jak w hud.gd) — zrzuty przy zadanym poziomie hałasu

func _ready() -> void:
	layer = 1
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotnoise="):
			_dev_noise = float(a.substr("--shotnoise=".length()))

## Lokalny człowiek (autorytet tego peera) — jego stan steruje ostrzeżeniem o zdrowiu.
func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

func _process(delta: float) -> void:
	_t += delta
	var lvl := _dev_noise if _dev_noise >= 0.0 else NoiseMgr.level
	var attn_target := clampf(lvl / 100.0, 0.0, 1.0) if not NoiseMgr.safe_zone else 0.0
	_attn = lerpf(_attn, attn_target, minf(1.0, delta * 1.5))
	var hurt_target := 0.0
	var p := _local_player()
	if p != null:
		var mx: int = p.max_hp()
		if p.dead:
			hurt_target = 1.0
		elif p.hp <= 1:
			hurt_target = 1.0
		elif p.hp == 2 and mx >= 3:
			hurt_target = 0.3
	_hurt = lerpf(_hurt, hurt_target, minf(1.0, delta * 2.0))
	# puls: podwójne uderzenie (≈70 uderzeń/min), ostrzejsze przy 1 HP
	var ph := fposmod(_t * 1.15, 1.0)
	var beat := pow(maxf(0.0, sin(ph * PI * 2.0 * 1.0)), 6.0) * 0.8 + pow(maxf(0.0, sin((ph - 0.18) * PI * 2.0)), 8.0) * 0.5
	var size := get_viewport().get_visible_rect().size
	# jakość (aberracja) i „Reduce Effects" (bez aberracji i pulsu tętna) — ustawienia gracza
	var post: float = Settings.post_mult()
	var calm: float = Settings.fx_mult()
	_mat.set_shader_parameter("vignette", BASE_VIGNETTE + _attn * 0.28 + _hurt * 0.2)
	_mat.set_shader_parameter("aberration", (BASE_ABERRATION + _attn * 0.0025 + _hurt * 0.0022) * post)
	_mat.set_shader_parameter("desat", _hurt * 0.55)
	_mat.set_shader_parameter("hurt_pulse", _hurt * (0.18 + 0.38 * beat * calm))
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
