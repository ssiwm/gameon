extends CanvasLayer
## Efekty wizualne pogody (weather.gd, GDD §10.3 „Radiostacja"): deszcz i burza z błyskawicami, tint ciemności (faza A; mgła, dźwięk i HUD to kolejne fazy).
##
## Czysta kosmetyka, lokalna: nic tu nie rozstrzyga gameplayu. Warstwa leży tuż przed `horror_fx` (winieta i ziarno kładą się na wierzch) i pod HUD-em.
## Deszcz pada tylko pod otwartym niebem (nad lokalnym graczem nie ma bryły aż do górnej krawędzi mapy), a pod dachem i w podziemiach
## płynnie zanika. Burza ma błyskawice: harmonogram wynika z ziarna misji (`Weather.seed`, replikowane razem z pogodą) i zegara misji
## (`mission.elapsed`), więc u wszystkich graczy błyska mniej więcej w tej samej chwili bez żadnego RPC.
## Ustawienie Weather effects: FULL (pełny błysk) / REDUCED (miękka poświata zamiast błysku, mniej cząsteczek — domyślnie) / OFF.

const Weather := preload("res://scripts/weather.gd")

const FADE_IN := 0.25                       ## 1/s: ok. 4 s narastania po starcie misji
const FADE_OUT := 0.5
## Tint ciemności (mnożnik koloru `level.ambient`) przy pełnej pogodzie.
const TINTS := {
	"clear": Color(1.15, 1.25, 1.5),
	"rain": Color(0.85, 0.95, 1.05),
	"storm": Color(0.7, 0.78, 0.95),
	"fog": Color(1.1, 1.15, 1.1),
}
## Parametry deszczu wg pogody: [kąt od pionu (°), mnożnik gęstości, mnożnik prędkości].
const RAIN := {"rain": [12.0, 1.0, 1.0], "storm": [26.0, 2.3, 1.25]}
## Mgła (FOG): welon w przestrzeni ekranu czytający obraz świata — spłaszcza kontrast i rozmywa jasne miejsca (halo wokół latarki, flar i lamp),
## a ciemność zostaje ciemnością (welon nie świeci sam). Gęstsza przy ziemi, z poziomymi pasmami płynącymi wolno w dwie strony.
const FOG_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float density = 0.0;
uniform float t = 0.0;
uniform float aspect = 1.78;
uniform vec3 fog_tint = vec3(0.62, 0.7, 0.68);
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
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.15;
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	vec2 px = vec2(1.0 / aspect, 1.0);
	vec3 blur = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		blur += texture(screen_tex, uv + vec2(cos(a), sin(a)) * px * 0.012).rgb;
		blur += texture(screen_tex, uv + vec2(cos(a), sin(a)) * px * 0.03).rgb * 0.6;
	}
	blur /= 12.8;
	float n1 = fbm(vec2(uv.x * aspect * 2.4 - t * 0.035, uv.y * 3.2 + t * 0.01));
	float n2 = fbm(vec2(uv.x * aspect * 1.5 + t * 0.022, uv.y * 2.1 - t * 0.008) + 7.3);
	float bands = 0.35 + 0.65 * (n1 * 0.6 + n2 * 0.4) * 1.4;
	float ground = smoothstep(0.15, 0.95, uv.y);
	float d = clamp(density * bands * (0.4 + 0.6 * ground), 0.0, 0.9);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 veil = vec3(lum) * fog_tint * 1.5 + blur * 0.8;
	col = mix(col, veil, d * 0.8) + blur * density * 0.3;
	COLOR = vec4(col, 1.0);
}
"""

const FAR_AMOUNT := 120
const NEAR_AMOUNT := 46
const NEAR_VEL := Vector2(440.0, 520.0)
const FAR_VEL := Vector2(270.0, 320.0)

## Dev (--shotflash): błysk na stałe (zrzuty).
static var dev_flash := false

var _near: CPUParticles2D
var _far: CPUParticles2D
var _splash: CPUParticles2D
var _fog: ColorRect
var _fog_mat: ShaderMaterial
var _bd_id := ""
var _bd_k := -1.0
var _k := 0.0                               ## wygładzona siła pogody 0..1
var _sky := 0.0                             ## wygładzona „otwartość nieba" nad lokalnym graczem 0..1
var _id := ""                               ## pogoda, dla której ustawiono parametry cząsteczek
var _t := 0.0
var _flash_seed := -1
var _flashes: Array = []                    ## czasy błysków (s zegara misji) policzone z ziarna
var _level: Node
var _main: Node

func _ready() -> void:
	layer = 1
	_near = _make_rain(true)
	_far = _make_rain(false)
	_splash = _make_splash()
	_fog = ColorRect.new()
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsh := Shader.new()
	fsh.code = FOG_SHADER
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = fsh
	_fog.material = _fog_mat
	_fog.visible = false
	add_child(_fog)
	add_child(_far)
	add_child(_near)
	add_child(_splash)

func _rain_texture() -> ImageTexture:
	var img := Image.create(2, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		var a := float(y) / 11.0                      # ogon przezroczysty, czoło kropli jasne
		img.set_pixel(0, y, Color(1, 1, 1, a * a))
		img.set_pixel(1, y, Color(1, 1, 1, a * a * 0.6))
	return ImageTexture.create_from_image(img)

func _make_rain(near: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _rain_texture()
	p.amount = NEAR_AMOUNT if near else FAR_AMOUNT
	p.lifetime = 0.9 if near else 1.2
	p.preprocess = 1.0
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(340.0, 2.0)
	p.position = Vector2(320.0, -8.0)
	p.direction = Vector2(-0.2, 1.0)
	p.spread = 1.5
	p.gravity = Vector2.ZERO
	p.particle_flag_align_y = true
	p.initial_velocity_min = (NEAR_VEL if near else FAR_VEL).x
	p.initial_velocity_max = (NEAR_VEL if near else FAR_VEL).y
	p.scale_amount_min = 1.0 if near else 0.6
	p.scale_amount_max = 1.5 if near else 0.9
	p.color = Color(0.75, 0.82, 0.95, 0.5 if near else 0.28)
	p.emitting = false
	return p

func _make_splash() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 22
	p.lifetime = 0.28
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(320.0, 1.5)
	p.direction = Vector2.UP
	p.spread = 80.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 55.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.color = Color(0.8, 0.88, 1.0, 0.45)
	p.emitting = false
	return p

func _exit_tree() -> void:
	_apply_level(Color.WHITE, 0.0)
	_set_backdrop("", 0.0)

func _process(delta: float) -> void:
	_t += delta
	var vs := get_viewport().get_visible_rect().size
	var mode: int = int(Settings.weather_fx_idx)
	var id := Weather.active_id() if mode != Settings.WEATHER_FX_OFF else ""
	_k = move_toward(_k, 1.0 if id != "" else 0.0, (FADE_IN if id != "" else FADE_OUT) * delta)
	if id != "":
		_use_weather(id, mode)
	var lp := _local_player()
	var open := 1.0 if (lp != null and _sky_open(lp)) else 0.0
	_sky = move_toward(_sky, open, 2.0 * delta)
	var raining := RAIN.has(_id)
	var strength := _k * _sky if raining else 0.0
	for p in [_near, _far, _splash]:
		(p as CPUParticles2D).emitting = strength > 0.02
		(p as CPUParticles2D).modulate.a = clampf(strength, 0.0, 1.0)
	if raining:
		_wind(vs)
		_place_splash(lp, vs)
	# mgła: welon ekranowy; pod ziemią słabszy (0,45), pod otwartym niebem pełny
	var fog_d := _k * (0.45 + 0.55 * _sky) if _id == "fog" else 0.0
	_fog.visible = fog_d > 0.01
	if _fog.visible:
		_fog_mat.set_shader_parameter("density", fog_d)
		_fog_mat.set_shader_parameter("t", _t)
		_fog_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	# tło parallax: noc pogodna wzmacnia księżyc i gwiazdy, deszcz przyciemnia niebo, mgła rozjaśnia grzbiety (tylko gdy się zmieniło)
	if _id != _bd_id or absf(_k - _bd_k) > 0.004:
		_bd_id = _id
		_bd_k = _k
		_set_backdrop(_id, _k)
	# tint ciemności + błysk (tylko burza)
	var tint := Color.WHITE
	if TINTS.has(_id):
		tint = Color.WHITE.lerp(TINTS[_id], _k)
	_apply_level(tint, _flash(mode) * _k if _id == "storm" else 0.0)

## Wybór parametrów cząsteczek dla pogody (zmiana pogody = nowe parametry).
func _use_weather(id: String, mode: int) -> void:
	if id == _id:
		return
	_id = id
	if not RAIN.has(id):
		return
	var cfg: Array = RAIN[id]
	var mult := 0.6 if mode == Settings.WEATHER_FX_REDUCED else 1.0
	for pair in [[_near, NEAR_AMOUNT, NEAR_VEL], [_far, FAR_AMOUNT, FAR_VEL]]:
		var p: CPUParticles2D = pair[0]
		var vel: Vector2 = pair[2]
		p.amount = maxi(8, int(float(pair[1]) * float(cfg[1]) * mult))
		p.initial_velocity_min = vel.x * float(cfg[2])
		p.initial_velocity_max = vel.y * float(cfg[2])
		p.restart()

## Kierunek deszczu (kąt od pionu) i podmuchy burzy; emitery wzdłuż górnej krawędzi, szersze o wychylenie.
func _wind(vs: Vector2) -> void:
	var cfg: Array = RAIN[_id]
	var gust := 1.0 + (0.5 * sin(_t * 0.7) * sin(_t * 0.31) if _id == "storm" else 0.0)
	var a := deg_to_rad(float(cfg[0]) * gust)
	var dir := Vector2(-sin(a), cos(a))          # wiatr z prawej: krople lecą w lewo w dół
	var pad := vs.y * tan(a) * 1.1
	for p in [_near, _far]:
		var pp: CPUParticles2D = p
		pp.direction = dir
		pp.emission_rect_extents = Vector2(vs.x * 0.5 + pad, 2.0)
		pp.position = Vector2(vs.x * 0.5 + pad * 0.5, -8.0)

## Plusk: wąski pas przy stopach lokalnego gracza (współrzędna warstwy = współrzędna viewportu, więc wystarcza macierz kamery).
func _place_splash(lp: Node2D, vs: Vector2) -> void:
	if lp == null:
		return
	var foot: Vector2 = get_viewport().get_canvas_transform() * (lp.global_position + Vector2(0, 1))
	_splash.position = Vector2(vs.x * 0.5, foot.y)
	_splash.emission_rect_extents = Vector2(vs.x * 0.5, 1.5)

## Czy nad lokalnym graczem jest otwarte niebo (poziom decyduje: brak bryły do górnej krawędzi mapy, nad ziemią).
func _sky_open(p: Node2D) -> bool:
	_level = _level if is_instance_valid(_level) else get_tree().get_first_node_in_group("level")
	return _level != null and _level.sky_open_at(p.global_position)

func _local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- błyskawice

## Siła błysku 0..1 w tej chwili. FULL: ostry dwuimpulsowy błysk; REDUCED: miękka poświata (wolne narastanie, 40% amplitudy); dev_flash: stały.
func _flash(mode: int) -> float:
	if dev_flash:
		return 1.0
	if mode == Settings.WEATHER_FX_OFF:
		return 0.0
	_main = _main if is_instance_valid(_main) else get_tree().current_scene
	var m = _main.get("mission") if _main != null else null
	if m == null:
		return 0.0
	var now := float(m.elapsed)
	_refresh_flashes(now)
	var best := 0.0
	for t0 in _flashes:
		var dt := now - float(t0)
		if dt < -0.5 or dt > 2.0:
			continue
		if mode == Settings.WEATHER_FX_REDUCED:
			var rise := clampf((dt + 0.5) / 0.5, 0.0, 1.0)             # 0,5 s narastania, potem ok. 1,2 s opadania
			var fall := clampf(1.0 - maxf(dt, 0.0) / 1.2, 0.0, 1.0)
			best = maxf(best, 0.4 * rise * fall)
		else:
			var a := 0.0 if dt < 0.0 else (1.0 if dt < 0.07 else exp(-(dt - 0.07) * 14.0))        # pierwszy impuls: błysk i szybki zanik
			var b := 0.0 if dt < 0.22 else (0.8 if dt < 0.3 else exp(-(dt - 0.3) * 6.0) * 0.8)    # drugi, słabszy impuls po krótkiej przerwie
			best = maxf(best, maxf(a, b))
	return best

## Harmonogram z ziarna: odstępy 9–24 s, liczony z zapasem 90 s do przodu od zegara misji.
func _refresh_flashes(now: float) -> void:
	if _flash_seed != Weather.seed or _flashes.is_empty() or float(_flashes[_flashes.size() - 1]) < now + 30.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = Weather.seed
		_flash_seed = Weather.seed
		_flashes.clear()
		var t := rng.randf_range(4.0, 12.0)
		while t < now + 90.0:
			_flashes.append(t)
			t += rng.randf_range(9.0, 24.0)

func _set_backdrop(id: String, k: float) -> void:
	_level = _level if is_instance_valid(_level) else get_tree().get_first_node_in_group("level")
	if _level != null:
		_level.set_backdrop_weather(id, k)

func _apply_level(tint: Color, flash: float) -> void:
	_level = _level if is_instance_valid(_level) else get_tree().get_first_node_in_group("level")
	if _level != null:
		_level.apply_weather_darkness(tint, flash)
