extends SubViewport
## Żywe tło ekranów startowych (menu główne, lobby): nocny las z mgłą, wąska ścieżka prowadzi do radiostacji z masztem
## w prześwicie przecinki. Własny świat 3D (`own_world_3d`) — nie miesza się ze sceną misji. Jedna kopia na grę (`shared()`),
## wyświetlana przez `menu_stage.gd`; renderuje się tylko, gdy któryś ekran startowy jest widoczny (`set_active`).
##
## Mgła żyje: `FOG_SHADER` (shader fog) przesuwa pasma szumu z wiatrem; pierwszy plan (do ~20 m od kamery) jest czysty, żeby menu
## było czytelne. Światła przeszkodowe na maszcie pulsują, kamera powoli najeżdża wzdłuż ścieżki. „Reduce effects” zatrzymuje mgłę,
## puls i najazd. Las to te same modele i materiały co na misjach (`Level3D.model_mesh`, wiatr w koronach), w `MultiMesh`.
## Drzewa tylko w bryle widzenia kamery (stała kamera) — mniej geometrii i cieni.
##
## Budowa w kilku klatkach po wczytaniu modeli w wątku (`load_threaded_request`), żeby menu nie zacinało się na starcie; do tego czasu
## `menu_stage.gd` pokazuje statyczny kadr tej sceny (`art/menu/backdrop.jpg`, `tools/menu_forest_shot.gd`). `ready_to_show` po
## ustaleniu się mgły (filtr czasowy mgły wolumetrycznej potrzebuje kilkunastu klatek).

signal ready_to_show

const L3D := preload("res://scripts/level3d.gd")
const W3D := "res://art/world3d/"
const TREES := ["tree_pine_a", "tree_pine_b", "tree_pine_c", "tree_spruce_a", "tree_spruce_b", "tree_spruce_c"]
const YOUNG := ["tree_spruce_young_a", "tree_spruce_young_b", "tree_spruce_young_c"]
const LOW := ["ph_fern_a", "ph_fern_b", "ph_fern_c", "ph_grass_a", "ph_grass_b", "ph_grass_c", "ph_shrub_a", "ph_shrub_b"]
const SEED := 87
## Ścieżka: punkty kontrolne (x, z) w metrach; kamera patrzy w −z.
const PATH_CTRL := [Vector2(0.4, 3), Vector2(0.2, -8), Vector2(1.6, -20), Vector2(0.6, -34), Vector2(2.4, -48), Vector2(4.0, -60)]
const STATION := Vector3(5.6, 0.0, -64.5)          ## środek budki radiostacji (koniec ścieżki + przedsionek)
const MAST := Vector3(6.2, 0.0, -73.5)             ## podstawa masztu — za budką, w prześwicie nieba nad przecinką
const MAST_H := 34.0
const CAM_POS := Vector3(0.2, 1.6, 7.0)
const CAM_LOOK := Vector3(-9.4, 6.0, -64.5)        ## punkt, na który patrzy kamera — budka wypada w ~62% szerokości kadru
const CAM_FOV := 48.0
const DOLLY_M := 1.6                               ## najazd wzdłuż osi widzenia (m), tam i z powrotem
const DOLLY_S := 50.0                              ## s na przejście w jedną stronę
const TREE_COUNT := 520
const UNDER_TRIES := 2200
const DEPTH_BAND := 12.0                           ## głębokość paczki `MultiMesh` (m)
const START_T := 15.0                              ## czas mgły w pierwszej klatce: okno budki odsłonięte (ten sam kadr co tło zastępcze)
const SETTLE_FRAMES := 24
const BACKLIT := 0.06                              ## prześwit igliwia pod księżyc (misje: 0,55–0,62) — sylwetki drzew zostają ciemne                          ## klatek po zbudowaniu, zanim scena zastąpi statyczny kadr

const FOG_SHADER := """
shader_type fog;
uniform float density = 0.34;
uniform float scale = 0.06;
uniform vec3 wind = vec3(1.0, 0.05, 0.35);
uniform float t = 0.0;                     // czas mgły (s), z `_process` — zatrzymany przy „Reduce effects”
uniform float height = 2.6;
uniform vec3 albedo : source_color = vec3(0.55, 0.6, 0.7);
uniform vec3 cam = vec3(0.0);
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int k = 0; k < 4; k++) { s += a * vnoise(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; } return s; }
void fog() {
	vec3 p = WORLD_POSITION;
	float n = fbm(p * scale * 1.8 + wind * t * 0.12);           // pasma ~8 m płyną z wiatrem (~1 m/s)
	float m = fbm(p * scale * 0.35 + wind * t * 0.002 + vec3(5.0));   // wielkie kłęby prawie stoją — kadr nie tonie w mgle
	float h = exp(-max(p.y, 0.0) / height);
	DENSITY = density * h * pow(smoothstep(0.42, 0.9, n * 0.8 + m * 0.35), 1.4) * 1.8;
	DENSITY *= smoothstep(5.0, 22.0, distance(p.xz, cam.xz));   // pierwszy plan czysty, mgła żyje w głębi
	ALBEDO = albedo;
}
"""

const PATH_SHADER := """
shader_type spatial;
uniform sampler2D alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.58, 0.52);
varying float edge;
void vertex() { edge = abs(UV.x - 0.5) * 2.0; }
void fragment() {
	vec2 uv = vec2(UV.x * 0.35, UV.y * 0.6);
	vec3 a = texture(alb, uv).rgb * tint;
	float wet = smoothstep(0.75, 0.2, edge);
	ALBEDO = a * mix(1.0, 0.55, wet);
	NORMAL_MAP = texture(nrm, uv).rgb;
	ROUGHNESS = mix(0.95, 0.18, wet * 0.85);
	EMISSION = vec3(0.010, 0.014, 0.020) * wet * (0.6 + 0.4 * texture(alb, uv * 3.0).r);   // mokry połysk: odbicie nieba
}
"""

static var _shared: SubViewport
static var _dark_sh: Shader

var _rng := RandomNumberGenerator.new()
var _tint_rng := RandomNumberGenerator.new()
var _path := PackedVector3Array()
var _root3: Node3D
var _cam: Camera3D
var _fog_mat: ShaderMaterial
var _red: Array = []                 ## [OmniLight3D, materiał kuli]
var _pending: Array = []             ## ścieżki GLB wczytywane w wątku
var _held: Array = []                ## wczytane sceny GLB — trzymane, żeby `load()` w `model_mesh` trafił w pamięć podręczną
var _stage := 0                      ## krok budowy (0 = czeka na modele)
var _settle := 0
var _t := START_T
var _users := 0
var shown := false                   ## scena gotowa do pokazania (po `ready_to_show`)
var frozen := false                  ## czas stoi (zrzut tła zastępczego `tools/menu_forest_shot.gd`)

## Wspólna kopia sceny (menu główne i lobby pokazują ten sam las). Pierwsze wywołanie zaczyna wczytywanie modeli.
static func shared(tree: SceneTree) -> SubViewport:
	if _shared == null or not is_instance_valid(_shared):
		_shared = (load("res://scripts/menu_forest.gd") as GDScript).new()
		tree.root.add_child.call_deferred(_shared)
	return _shared

## Czy ta platforma pokazuje żywą scenę: nie w trybie headless (testy) i nie w trybie zgodności (OpenGL nie ma mgły wolumetrycznej).
static func supported() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "gl_compatibility" \
			and not "--menu2d" in OS.get_cmdline_user_args()

func _init() -> void:
	own_world_3d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(1280, 720)
	_rng.seed = SEED
	for n in TREES + YOUNG + LOW:
		var p: String = L3D.MODEL_DIR + n + ".glb"
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
			_pending.append(p)

## Ekran startowy pokazuje (true) albo chowa (false) scenę; renderuje się, dopóki ktoś ją pokazuje.
func set_active(on: bool) -> void:
	_users = maxi(_users + (1 if on else -1), 0)
	_update_mode()

func _update_mode() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if _users > 0 and _stage > 5 else SubViewport.UPDATE_DISABLED

## Rozmiar renderu: ekran × `scale` (skalę wg jakości wybiera `menu_stage.gd`, który rozciąga obraz na ekran).
func fit(screen: Vector2, scale: float) -> void:
	var s := Vector2i(maxi(int(screen.x * scale), 64), maxi(int(screen.y * scale), 64))
	if size != s:
		size = s

func _process(delta: float) -> void:
	if _stage == 0:
		for p in _pending:
			var st := ResourceLoader.load_threaded_get_status(p)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				return
		for p in _pending:
			_held.append(ResourceLoader.load_threaded_get(p))
		_stage = 1
		return
	if _stage <= 5:                                           # budowa po kawałku, krok na klatkę
		match _stage:
			1: _build_world()
			2: _build_station()
			3: _build_trees()
			4: _build_undergrowth()
			5: _build_fog()
		_stage += 1
		_update_mode()
		return
	if _users == 0:
		return
	var live := Settings.fx_mult() > 0.0 and not frozen
	if live:
		_t += delta
	_fog_mat.set_shader_parameter("t", _t)
	var pulse := 1.0 if not live else 0.55 + 0.45 * sin(_t * 2.4)
	for r in _red:
		(r[0] as OmniLight3D).light_energy = 4.0 * pulse
		(r[1] as StandardMaterial3D).emission_energy_multiplier = 16.0 * (0.4 + 0.6 * pulse)
	var p := fposmod(_t - START_T, DOLLY_S * 2.0) / DOLLY_S
	var d := 0.0 if not live else 0.5 - 0.5 * cos(PI * (p if p <= 1.0 else 2.0 - p))
	var fwd := (CAM_LOOK - CAM_POS).normalized()
	_cam.look_at_from_position(CAM_POS + fwd * DOLLY_M * d, CAM_LOOK + fwd * DOLLY_M * d, Vector3.UP)
	if not shown:
		_settle += 1
		if _settle >= SETTLE_FRAMES:
			shown = true
			ready_to_show.emit()

## Kadr kamery w chwili t = 0 (statyczne tło `tools/menu_forest_shot.gd` i pierwsza klatka sceny są tym samym kadrem).
func camera_rest() -> Transform3D:
	return Transform3D.IDENTITY.looking_at(CAM_LOOK - CAM_POS, Vector3.UP).translated(CAM_POS)

# ------------------------------------------------------------------ budowa

func _build_world() -> void:
	_root3 = Node3D.new()
	add_child(_root3)
	_path = _spline(PATH_CTRL)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.02, 0.035)
	sm.sky_horizon_color = Color(0.05, 0.065, 0.09)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.012)
	sm.ground_horizon_color = Color(0.04, 0.05, 0.065)
	sm.sun_angle_max = 0.0
	sm.sun_curve = 0.02
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.10, 0.13, 0.18)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.35
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.ssr_enabled = true                                   # mokra ścieżka odbija okno i niebo
	e.ssao_enabled = true
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.0045
	e.volumetric_fog_albedo = Color(0.55, 0.62, 0.72)
	e.volumetric_fog_emission = Color(0.035, 0.05, 0.075)
	e.volumetric_fog_emission_energy = 1.0
	e.volumetric_fog_ambient_inject = 0.8
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 140.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.85
	e.adjustment_contrast = 1.08
	we.environment = e
	_root3.add_child(we)
	var moon := DirectionalLight3D.new()                      # księżyc za stacją (kontra): promienie przez korony na widza
	moon.rotation_degrees = Vector3(-30.0, 176.0, 0.0)
	moon.light_color = Color(0.62, 0.72, 0.92)
	moon.light_energy = 0.32
	moon.light_volumetric_fog_energy = 6.0
	moon.shadow_enabled = int(Settings.quality_idx) > 0          # LOW: bez cieni (≈ −1 ms GPU), promienie w mgle słabsze
	moon.directional_shadow_max_distance = 160.0
	_root3.add_child(moon)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.position = Vector3(0, 0, -90)
	ground.material_override = _mat("terrain", 0.25, Color(0.17, 0.18, 0.16))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root3.add_child(ground)
	_root3.add_child(_path_mesh())
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.far = 400.0
	_root3.add_child(_cam)
	_cam.transform = camera_rest()
	_cam.current = true

func _build_station() -> void:
	var h := Node3D.new()
	h.position = STATION
	h.rotation_degrees.y = -18.0
	_root3.add_child(h)
	var wall := _mat("concrete", 0.8, Color(0.55, 0.55, 0.52))
	var roof := _mat("roof", 0.6, Color(0.4, 0.4, 0.4))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.03)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.13, 0.11)
	frame.roughness = 0.8
	_box(h, Vector3(5.2, 0.3, 4.2), Vector3(0, 0.15, 0), wall)                    # cokół
	_box(h, Vector3(5.0, 2.7, 4.0), Vector3(0, 1.65, 0), wall)
	_box(h, Vector3(5.7, 0.16, 4.7), Vector3(0, 3.06, 0.05), roof, Vector3(-3, 0, 0))   # dach z okapem nad drzwiami
	_box(h, Vector3(1.6, 0.9, 1.4), Vector3(-1.4, 3.55, -0.6), wall)              # nadbudówka
	var glass := StandardMaterial3D.new()                     # okno: ciepłe światło radiostacji
	glass.albedo_color = Color(0.1, 0.07, 0.03)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.62, 0.25)
	glass.emission_energy_multiplier = 9.0
	_box(h, Vector3(1.3, 0.75, 0.04), Vector3(-1.1, 1.75, 2.0), glass)
	_box(h, Vector3(1.46, 0.08, 0.1), Vector3(-1.1, 2.16, 2.03), frame)           # rama okna i krzyż
	_box(h, Vector3(1.46, 0.08, 0.14), Vector3(-1.1, 1.34, 2.05), frame)
	_box(h, Vector3(0.06, 0.75, 0.07), Vector3(-1.1, 1.75, 2.03), frame)
	_box(h, Vector3(1.3, 0.05, 0.07), Vector3(-1.1, 1.85, 2.03), frame)
	_box(h, Vector3(0.9, 2.05, 0.05), Vector3(1.3, 1.32, 2.01), dark)             # drzwi z ościeżnicą
	_box(h, Vector3(1.06, 0.08, 0.1), Vector3(1.3, 2.38, 2.03), frame)
	var win := OmniLight3D.new()
	win.position = Vector3(-1.1, 1.7, 2.6)
	win.light_color = Color(1.0, 0.6, 0.28)
	win.light_energy = 6.0
	win.omni_range = 9.0
	win.light_volumetric_fog_energy = 4.0
	h.add_child(win)
	var spot := SpotLight3D.new()                             # lampa nad drzwiami: stożek w mgle
	spot.position = Vector3(1.3, 2.6, 2.3)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color(1.0, 0.78, 0.5)
	spot.light_energy = 3.0
	spot.spot_range = 7.0
	spot.spot_angle = 38.0
	spot.light_volumetric_fog_energy = 3.5
	h.add_child(spot)
	var bulb := StandardMaterial3D.new()
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.8, 0.55)
	bulb.emission_energy_multiplier = 6.0
	_box(h, Vector3(0.18, 0.1, 0.18), Vector3(1.3, 2.62, 2.15), bulb)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.06, 0.06, 0.06)
	steel.metallic = 0.5
	steel.roughness = 0.6
	_beam(h, Vector3(1.8, 3.1, -1.2), Vector3(1.8, 6.6, -1.2), 0.05, steel)       # antena na dachu
	_beam(h, Vector3(1.1, 6.3, -1.2), Vector3(2.5, 6.3, -1.2), 0.03, steel)
	_mast(steel)
	# kabel z masztu do budki
	var top := h.transform * Vector3(-0.6, 3.2, -2.0)
	_beam(_root3, MAST + Vector3(0, 6.0, 0), top, 0.025, steel)

func _mast(steel: StandardMaterial3D) -> void:
	var n := Node3D.new()
	n.position = MAST
	_root3.add_child(n)
	var legs: Array = []
	for k in 3:
		var a := TAU * float(k) / 3.0
		legs.append(Vector3(cos(a), 0.0, sin(a)) * 0.85)
	for k in 3:
		var p: Vector3 = legs[k]
		_beam(n, p, p + Vector3(0, MAST_H, 0), 0.16, steel)
	var step := 1.6
	for l in int(MAST_H / step):
		var y0 := float(l) * step
		for k in 3:
			var p: Vector3 = legs[k]
			var q: Vector3 = legs[(k + 1) % 3]
			_beam(n, p + Vector3(0, y0, 0), q + Vector3(0, y0 + step, 0), 0.07, steel)
			_beam(n, p + Vector3(0, y0, 0), q + Vector3(0, y0, 0), 0.07, steel)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.2, 0.2, 0.2)
	for k in 3:                                               # odciągi
		var a := TAU * float(k) / 3.0 + 0.5
		var anchor := Vector3(cos(a), 0.0, sin(a)) * 16.0
		_beam(n, Vector3(0, MAST_H * 0.92, 0), anchor, 0.012, wire)
		_beam(n, Vector3(0, MAST_H * 0.5, 0), anchor, 0.012, wire)
	_beam(n, Vector3(0, MAST_H, 0), Vector3(0, MAST_H + 4.0, 0), 0.05, steel)
	for y in [MAST_H + 4.0, MAST_H * 0.5]:                    # światła przeszkodowe
		var red := StandardMaterial3D.new()
		red.emission_enabled = true
		red.emission = Color(1.0, 0.08, 0.04)
		red.emission_energy_multiplier = 16.0
		var s := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.2
		sp.height = 0.4
		s.mesh = sp
		s.material_override = red
		s.position = Vector3(0, y, 0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(s)
		var l := OmniLight3D.new()
		l.position = Vector3(0, y, 0)
		l.light_color = Color(1.0, 0.12, 0.06)
		l.light_energy = 4.0
		l.omni_range = 10.0
		l.light_volumetric_fog_energy = 4.0
		n.add_child(l)
		_red.append([l, red])

## Czy punkt (z zapasem `margin` m) mieści się w bryle widzenia kamery spoczynkowej — dla podrostu (drzewa stoją wszystkie:
## ich cienie poza kadrem tną promienie księżyca w mgle w kadrze; bez nich mgła była dwa razy jaśniejsza).
func _in_view(p: Vector3, margin: float) -> bool:
	var local := camera_rest().affine_inverse() * p
	var depth := -local.z
	if depth < -margin:
		return false
	var half_h := tan(deg_to_rad(CAM_FOV * 0.5)) * 16.0 / 9.0 * 1.25   # zapas na proporcje szersze niż 16:9
	return absf(local.x) < half_h * maxf(depth, 0.0) + margin

## Las: kolejność losowań jak w scenie próbnej zatwierdzonego kadru (`menu_design/las_radiostacja_2026-11-17/menu_forest.gd`,
## ziarno 87) — te same drzewa w tych samych miejscach.
func _build_trees() -> void:
	var lists := {}
	var pts: Array = []
	var tries := 0
	while pts.size() < TREE_COUNT and tries < 20000:
		tries += 1
		var z := _rng.randf_range(-170.0, 6.0)
		var spread := 22.0 + (-z) * 0.55
		var p := Vector3(_rng.randf_range(-spread, spread), 0.0, z)
		var dp := _dist_path(p)
		if dp < 4.5 + _rng.randf() * 3.5 or p.distance_to(CAM_POS) < 9.0:
			continue
		if p.distance_to(STATION) < 13.0 or p.distance_to(MAST) < 6.0:
			continue
		var ok := true
		for q in pts:
			if p.distance_squared_to(q) < 7.0:
				ok = false
				break
		if not ok:
			continue
		pts.append(p)
		var k: String = TREES[_rng.randi() % TREES.size()]
		if p.distance_to(CAM_POS) < 30.0 or dp < 8.0:
			k = TREES[_rng.randi() % 3]                       # przy ścieżce i kamerze sosny: pnie, korony wysoko
		var hgt := _rng.randf_range(15.0, 24.0)
		_add(lists, k, p, hgt, _rng.randf() * TAU)
	_emit(lists, true)

## Podrost (paprocie, trawy, krzewy, młode świerki); losowania jak w scenie próbnej, poza kadrem pomijany po losowaniu.
func _build_undergrowth() -> void:
	var lists := {}
	for i in UNDER_TRIES:
		var z := _rng.randf_range(-120.0, 5.0)
		var spread := 10.0 + (-z) * 0.4
		var p := Vector3(_rng.randf_range(-spread, spread), 0.0, z)
		var dp := _dist_path(p)
		if dp < 0.8 or p.distance_to(CAM_POS) < 2.5 or p.distance_to(STATION) < 5.0:
			continue
		var k := ""
		var hgt := 0.0
		if dp < 3.0 or _rng.randf() < 0.5:
			k = LOW[_rng.randi() % LOW.size()]
			hgt = _rng.randf_range(0.4, 1.1)
		elif _rng.randf() < 0.25:
			k = YOUNG[_rng.randi() % YOUNG.size()]
			hgt = _rng.randf_range(1.5, 4.0)
		else:
			continue
		var rot := _rng.randf() * TAU
		if _in_view(p, 3.0):
			_add(lists, k, p, hgt, rot)
	_emit(lists, false)

func _add(lists: Dictionary, model: String, p: Vector3, hgt: float, rot: float) -> void:
	if not lists.has(model):
		lists[model] = []
	var v := _tint_rng.randf_range(0.85, 1.05)            # osobne losowanie: nie przesuwa kolejności rozmieszczenia
	(lists[model] as Array).append([p, hgt, rot, Color(v * 0.97, v, v * 0.98)])

## Egzemplarze w `MultiMesh` (jak las misji, `Level3D._forest_chunks`): drzewa w skali h/100 jak na misji (wiatr `WIND_SHADER` liczy
## wysokość drzewa z `unit_h` = 100), rośliny `ph_*` z wysokości obrysu modelu; odcień w kolorze egzemplarza.
func _emit(lists: Dictionary, shadows: bool) -> void:
	for model in lists:
		var mdl := L3D.model_mesh(model)
		if mdl.is_empty():
			continue
		var mesh: Mesh = _menu_mesh(mdl[0], String(model))
		var local: Transform3D = mdl[1]
		var mh := maxf((local * mesh.get_aabb()).size.y, 0.01)
		var unit := 100.0 if String(model).begins_with("tree_") else mh
		var out: Array = []
		for e in lists[model]:
			var s := float(e[1]) / unit
			var b := Basis(Vector3.UP, float(e[2])).scaled(Vector3(s, s, s))
			out.append([Transform3D(b, e[0] as Vector3), e[3]])
		var bands := {}                                    # paczki też po głębokości: LOD liczy się dla całej paczki, a kamera patrzy wzdłuż z
		for e in out:
			var key := int(floor((e[0] as Transform3D).origin.z / DEPTH_BAND))
			if not bands.has(key):
				bands[key] = []
			(bands[key] as Array).append(e)
		for key in bands:
			L3D._forest_chunks(_root3, mesh, null, bands[key], shadows, local)

## Drzewa bez podświetlenia igliwia od tyłu: na misjach księżyc jest kontrą z boku kadru, tu stoi za lasem na wprost kamery
## i `BACKLIGHT` rozjaśniał korony w jasnoniebieską ścianę zamiast czarnych sylwetek. Kopia siatki z własnymi materiałami —
## siatka z `Level3D.model_mesh` (las misji) zostaje nietknięta.
func _menu_mesh(mesh: Mesh, model: String) -> Mesh:
	if not model.begins_with("tree_") or not mesh is ArrayMesh:
		return mesh
	var dup := (mesh as ArrayMesh).duplicate() as ArrayMesh
	for si in dup.get_surface_count():
		var m := mesh.surface_get_material(si)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			var sm := (m as ShaderMaterial).duplicate() as ShaderMaterial
			if _dark_sh == null:
				_dark_sh = Shader.new()
				_dark_sh.code = (m as ShaderMaterial).shader.code.replace("BACKLIGHT = vec3(0.55, 0.62, 0.5);", "BACKLIGHT = vec3(%.3f);" % BACKLIT)
			sm.shader = _dark_sh
			dup.surface_set_material(si, sm)
		elif m is BaseMaterial3D and (m as BaseMaterial3D).backlight_enabled:
			var bm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			bm.backlight = Color(BACKLIT, BACKLIT, BACKLIT)
			dup.surface_set_material(si, bm)
	return dup

func _build_fog() -> void:
	var fv := FogVolume.new()
	fv.size = Vector3(160, 30, 220)
	fv.position = Vector3(0, 6, -90)
	_fog_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_fog_mat.shader = sh
	_fog_mat.set_shader_parameter("cam", CAM_POS)
	fv.material = _fog_mat
	_root3.add_child(fv)

# ------------------------------------------------------------------ pomocnicze

func _spline(ctrl: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in 12:
			var t := float(s) / 12.0
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			out.append(Vector3(q.x, 0.0, q.y))
	var last: Vector2 = ctrl[ctrl.size() - 1]
	out.append(Vector3(last.x, 0.0, last.y))
	return out

func _dist_path(p: Vector3) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for i in _path.size() - 1:
		var a := Vector2(_path[i].x, _path[i].z)
		var ab := Vector2(_path[i + 1].x, _path[i + 1].z) - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best

## Wąska dróżka: pas wzdłuż `_path`, szerokość 0,5–0,8 m, mokry środek (`PATH_SHADER`).
func _path_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var acc := 0.0
	for i in _path.size():
		var p := _path[i]
		var d := (_path[mini(i + 1, _path.size() - 1)] - _path[maxi(i - 1, 0)]).normalized()
		var side := Vector3(-d.z, 0, d.x)
		var w := 0.30 + 0.07 * sin(float(i) * 0.9) + 0.04 * sin(float(i) * 2.3)
		if i > 0:
			acc += p.distance_to(_path[i - 1])
		for k in 2:
			st.set_uv(Vector2(float(k), acc / 2.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(p + side * (-1.0 if k == 0 else 1.0) * w + Vector3(0, 0.015, 0))
	for i in _path.size() - 1:
		var a := i * 2
		st.add_index(a); st.add_index(a + 2); st.add_index(a + 1)
		st.add_index(a + 1); st.add_index(a + 2); st.add_index(a + 3)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PATH_SHADER
	sm.shader = sh
	sm.set_shader_parameter("alb", load(W3D + "dig_dirt_albedo.png"))
	sm.set_shader_parameter("nrm", load(W3D + "dig_dirt_normal.png"))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _mat(name: String, scale_uv: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(W3D + name + "_albedo.png")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(W3D + name + "_normal.png")
	m.uv1_scale = Vector3(scale_uv, scale_uv, scale_uv)
	m.uv1_triplanar = true
	m.roughness = 1.0
	return m

func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)

func _beam(parent: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(t, t, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	var up := Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
