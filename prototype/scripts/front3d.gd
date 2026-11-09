extends RefCounted
## Pierwszy plan przed płaszczyzną gry (`FOREGROUND_PLAN.md`): rury, kable, łańcuchy i lampy 3,5–5 m przed płaszczyzną gry, w zakresach
## kolumn z wpisu `FRONT` w danych mapy (zestaw rodzajów, pas między stropem a podłogą). Paralaksa: przy kamerze NORMAL element 4 m
## przed płaszczyzną przesuwa się ×1,25 względem niej.
##
## Zasady (plan, „Zasady” i „Poprawki po bramce F2”):
##  - bryły leżą na `LAYER_FRONT`, którą widzi tylko kamera graczy (`VpActors`): gracz przy z ≈ 0 jest zawsze za elementem, a element
##    razem z graczami leży nad obrazem świata i wrogami (F0: trzeci SubViewport kosztował +0,4–0,7 ms za ten sam obraz);
##  - rury z zestawu Poly Haven `modular_industrial_pipes_01` (części z `tools/front_parts.py`, tekstury PBR dekoracji `pipes`):
##    odcinki z kołnierzami, zawór z kołem, trójnik; materiał oświetlany jak gracze — latarka, lampy i kontra postaci (`view3d.gd` dokłada
##    `LAYER_FRONT` do ich masek), otoczenie środowiska graczy przygaszone (`ambient_k`), bez cienia;
##  - element jest przycięty do pasa wpisu w rzucie na płaszczyznę gry (promień z kamery do z = 0), więc rura kończy się na linii
##    stropu i podłogi, a nie wystaje w niebo nad halą;
##  - wygaszanie półprzezroczystością (do krycia MIN_A) tylko tam, gdzie element zasłania sylwetkę gracza albo wroga (prostokąt
##    z miękkim brzegiem FADE_M); waga punktu narasta i gaśnie płynnie w czasie (`view3d.gd`), celownik niczego nie wygasza;
##  - ustawienie „Foreground” (Settings.FRONT_NAMES): ON, REDUCED (bez elementów w pasie wokół środka kadru), OFF; LOW: bez małych elementów.
## Tylko widok: bez kolizji, wzroku, hałasu i wpływu na celowanie.

const Level3D := preload("res://scripts/level3d.gd")

const LAYER_FRONT := 256                   ## warstwa wizualna pierwszego planu (bit 9); kamera świata jej nie widzi
const LAYER_WALL := 512                    ## ściany przekroju (`build_walls`): widzi je kamera graczy, oświetlają lampy i latarka, ale nie kontra postaci (jasny pas boku ściany w ciemności)
const MAX_PTS := 16
const MIN_A := 0.3                         ## krycie elementu na sylwetce postaci
const FADE_M := 0.6                        ## m: miękki brzeg wygaszania wokół prostokąta sylwetki
const FADE_T := 0.25                       ## s: narastanie i gaśnięcie wygaszania (postać wchodzi za rurę / wychodzi)
const BIG_SPACING := Vector2(21.0, 28.0)   ## m: odstęp dużych elementów — najwyżej jeden w kadrze NORMAL (kadr na z = 4 m ma ok. 21 m)
const SMALL_MIN := 6.0                     ## m: mały element najbliżej dużego
const FRAME_H_NORMAL := 180.0 * 1.8 / 22.0   ## m: wysokość kadru NORMAL na płaszczyźnie gry (Settings.CAM_ZOOM 2.0 → 180 px)
const Z_RANGE := Vector2(3.5, 5.0)         ## m: przed płaszczyzną gry
const MARGIN := 2.0                        ## m: od brzegu zakresu
const PLAYER_HALF := Vector2(0.55, 0.95)   ## m: połowa szerokości i wysokości sylwetki gracza (z bronią przy ciele)
const ENEMY_PAD := 0.15                    ## m: zapas wokół prostokąta trafień wroga
const ABOVE := 8.0                         ## m: geometria sięga tyle za pas wpisu (przy kamerze wyżej albo niżej od pasa rzut i tak jest przycięty)
const REDUCED_BAND := 0.3                  ## REDUCED: pół wysokości pasa bez elementów, jako część wysokości kadru
const PIPE_SCALE := 2.0                    ## części z zestawu mają kołnierz 0,21 m; rura pierwszego planu ma kołnierz 0,42 m
const LAMP_H := 0.75                       ## m: wysokość klosza lampy
const LAMP_DROP := Vector2(1.6, 2.4)       ## m: lampa wisi tyle pod linią stropu pasa
## Zestawy: duże (rury) i małe rodzaje, mnożnik koloru. Klucze to wartości "set" we wpisach `FRONT`.
const SETS := {
	"station": {"big": ["pipe", "pipes2"], "small": ["chain", "cables"], "tint": Color(0.8, 0.8, 0.8)},
	"tunnel": {"big": ["pipe", "pipes2"], "small": ["lamp", "cables", "lamp"], "tint": Color(0.7, 0.72, 0.75)},
	"bunker": {"big": ["pipe", "pipes2"], "small": ["cables", "lamp"], "tint": Color(0.85, 0.8, 0.74)},    # kryjówka: bez łańcuchów, lampy na przewodzie
	# las pod gołym niebem (F3): pnie przez cały kadr, zwisające gałęzie świerka u góry i paprocie z trawą u dołu; pas wpisu otwarty
	# w pionie (pień nie kończy się na linii podłogi ani stropu — jego podstawę i koniec zasłania brzeg kadru, zasada 4)
	# las: w każdej przerwie między pniami dwa małe elementy — gałąź u góry kadru (`small`) i kępa u dołu (`small2`); nie zasłaniają się nawzajem
	"forest": {"big": ["pine", "birch", "snag", "pine"], "small": ["bough"], "small2": ["ferns", "grass", "ferns"], "tint": Color(0.62, 0.64, 0.66), "open": true},
}
const BIG_KINDS := ["pipe", "pipes2", "pine", "birch", "snag"]
const PARTS_GLB := "res://art/world3d/front/pipe_parts.glb"
const PIPE_TEX := "res://art/items3d/pipes_modular_industrial_pipes_01_group0%d_%s_1k.jpg"   ## %d grupa 1–2, %s diff / arm / nor_gl
const LAMP_GLB := "res://art/items3d/lamp.glb"
const LAMP_TEX := "res://art/items3d/lamp_%s_14ae6b34-1cdc-422e-9215-833102ba089b.jpg"           ## Color / ORM / NormalGL
const LAMP_EMI := "res://art/items3d/lamp_lamp_emi.jpg"
## Materiały elementu w kolejności powierzchni siatki.
const MATS := ["g1", "g2", "dark", "lamp"]

## Las (zestaw „forest”): tekstury kory i kart z `art/world3d/forest/` (te same co karty dalekiego lasu, `world_forest_gen.py`).
const FOREST_TEX := "res://art/world3d/forest/%s.png"
## Pień: rodzaj → [kora, średnica przy podłodze pasa (m), zbieg (m średnicy na m wysokości), v kory na dole i na górze pnia].
## Kora to pionowy pas całego drzewa (u dołu ciemna nasada) — pień w kadrze bierze jego środek, bez powtórzeń.
const TRUNKS := {
	"pine": ["pine_bark", 0.9, 0.012, Vector2(0.92, 0.18)],
	"birch": ["birch_bark", 0.55, 0.008, Vector2(0.80, 0.05)],
	"snag": ["snag_wood", 0.8, 0.018, Vector2(0.95, 0.10)],
}
const TRUNK_SPAN := Vector2(-10.0, 16.0)   ## m: pień od tyle pod do tyle nad podłogą pasa — podstawa i koniec zawsze poza kadrem NORMAL
const BOUGH_Y := Vector2(8.2, 9.4)         ## m nad podłogą pasa: nasada zwisającej gałęzi (nad górnym brzegiem kadru przy z ≈ 4 m)
const FERN_BASE := -6.0                    ## m: podstawa kępy paproci i trawy względem podłogi pasa (pod dolnym brzegiem kadru)
const FERN_TOP := Vector2(-2.3, -1.3)      ## m: wierzch kępy — wchodzi w kadr od dołu na ok. 1–2 m
const FOREST_RIM := 0.9                    ## kontra księżyca na krawędzi pnia (emisja, mnożona przez pogodę jak `MoonRim`)
const FOREST_TRANS := 0.16                 ## prześwit księżyca przez karty igliwia, paproci i trawy
## Igliwie przy górnym brzegu kadru wisi na tle ciemnych koron lasu — bez mocniejszego prześwitu znika jak pień w F0.
const FOREST_TRANS_K := {"bough_side": 2.4, "pine_tuft": 2.2}
## Jasność tekstur lasu w pierwszym planie (`alb_k`): biała kora brzozy i szare drewno martwego pnia w nocy nie mogą świecić jak słup.
const FOREST_ALB := {"birch_bark": 0.3, "snag_wood": 0.7, "grass_a": 0.45, "grass_b": 0.45, "fern_a": 0.7}
const OPEN_PAD := 3.0                      ## m: zapas przycięcia w poziomie dla wpisów otwartych — rzut pnia przy brzegu kadru wychodzi ×1,25 dalej od środka

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emit_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = true;
uniform bool has_arm = true;               // las: tekstury kory i kart bez mapy AO / chropowatość / metal — wtedy base_rough, metal 0
uniform bool cutout = false;               // karty lasu (igliwie, paproć, trawa): alfa z tekstury, odcięcie
uniform float sway = 0.0;                  // karty: kołysanie [m] — wierzch kępy paproci, koniec gałęzi (`sway_uv`)
uniform vec2 sway_uv = vec2(0.0, 1.0);     // waga kołysania z UV: (u, 1 − v)
uniform float rim_k = 0.0;                 // kontra księżyca (las): obrys krawędzi zwróconej ku księżycowi; 0 = brak
uniform float trans_k = 0.0;               // karty lasu: prześwit księżyca przez igliwie i liście
uniform vec3 rim_col : source_color = vec3(0.62, 0.72, 0.95);
uniform vec3 moon_dir = vec3(0.34, 0.215, -0.915);   // `Level3D.MOON_DIR`: za lasem, po prawej, nisko
uniform float moon = 1.0;                  // pogoda i błysk burzy (`set_moon`, jak `MoonRim`)
uniform float alb_k = 1.0;                 // las: mnożnik jasności tekstury (jasna kora brzozy w nocy szarzeje)
uniform bool world_uv = false;             // ściany przekroju (`build_walls`): tekstura świata w rzucie trójpłaszczyznowym jak `Level3D.make_pbr`
uniform float uv_per_m = 0.33;
uniform sampler2D grime_tex : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grime_a = 0.0;               // brud wielkoskalowy jak `next_pass` materiału świata (kafel ok. 14 m)
uniform vec3 base_col : source_color = vec3(0.05);
uniform float base_rough = 0.55;
uniform float base_metal = 0.5;
uniform float emit_energy = 0.0;
uniform float ambient_k = 0.35;            // ile otoczenia środowiska graczy zostaje (jest jaśniejsze niż w obrazie świata)
uniform vec4 pts[16];                      // xy: środek sylwetki na płaszczyźnie gry [m], zw: połowa szerokości i wysokości [m]
uniform float wts[16];                     // waga punktu 0–1 (płynne wejście i wyjście)
uniform int npts = 0;
uniform float min_a = 0.3;
uniform float fade_m = 0.6;
uniform float mid_y = 0.0;                 // środek kadru na płaszczyźnie gry [m]
uniform float band = 0.0;                  // REDUCED: pół wysokości pasa bez pierwszego planu [m]; 0 = wył.
instance uniform vec4 clip = vec4(-1e6, 1e6, -1e6, 1e6);   // x0, x1, y0, y1 na płaszczyźnie gry [m]
instance uniform vec4 tint = vec4(1.0);
instance uniform vec2 ywin = vec2(-1e6, 1e6);  // F2b: fizyczny pas y [m] (podłoga, strop) we wpisach z przekrojem
instance uniform vec4 occ = vec4(1e6, -1e6, 0.0, 0.0);   // F2b: y spodu stropu (dachu), y wierzchu podłogi, z przodu stropu, z przodu podłogi
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	if (sway > 0.0) {
		vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = dot(vec2(UV.x, 1.0 - UV.y), sway_uv);
		VERTEX.x += sway * k * (sin(TIME * 0.9 + w0.x * 0.37) + 0.4 * sin(TIME * 2.3 + w0.x * 1.1));
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float k = cam.z / max(cam.z - wpos.z, 0.001);
	vec2 q = cam.xy + (wpos.xy - cam.xy) * k;      // ten piksel na płaszczyźnie gry (z = 0)
	if (q.x < clip.x || q.x > clip.y || q.y < clip.z || q.y > clip.w) { discard; }
	if (band > 0.0 && abs(q.y - mid_y) < band) { discard; }
	if (wpos.y < ywin.x || wpos.y > ywin.y) { discard; }
	// F2b: strop (dach) i płyta podłogi przekroju są w warstwie świata, pod pierwszym planem — z kamery nad stropem (gracz na dachu
	// hali, w szybie nad tunelem) albo pod podłogą piksel, do którego promień przechodzi przez płytę, odrzucamy analitycznie
	if (cam.y > occ.x && wpos.y < occ.x && mix(wpos.z, cam.z, (occ.x - wpos.y) / (cam.y - wpos.y)) < occ.z) { discard; }
	if (cam.y < occ.y && wpos.y > occ.y && mix(wpos.z, cam.z, (wpos.y - occ.y) / (wpos.y - cam.y)) < occ.w) { discard; }
	float a = 1.0;
	for (int i = 0; i < npts; i++) {
		vec2 d = max(abs(q - pts[i].xy) - pts[i].zw, vec2(0.0));
		a = min(a, mix(1.0, mix(min_a, 1.0, smoothstep(0.0, fade_m, length(d))), wts[i]));
	}
	vec2 uv = UV;
	vec2 guv = UV;
	if (cutout && texture(albedo_tex, uv).a < 0.42) { discard; }
	if (world_uv) {
		vec3 an = abs(normalize(wnrm));
		vec3 p = wpos * vec3(1.0, -1.0, 1.0);
		vec2 pp = an.x > 0.5 ? p.zy : (an.y > 0.5 ? p.xz : p.xy);
		uv = pp * uv_per_m;
		guv = pp * 0.07;
	}
	if (use_tex) {
		vec3 alb = texture(albedo_tex, uv).rgb;
		if (grime_a > 0.0) {
			vec4 g = texture(grime_tex, guv);
			alb = mix(alb, g.rgb, g.a * grime_a);
		}
		ALBEDO = alb * tint.rgb * alb_k;
		if (has_arm) {
			vec3 arm = texture(arm_tex, uv).rgb;
			AO = arm.r * ambient_k;
			ROUGHNESS = arm.g;
			METALLIC = arm.b;
			NORMAL_MAP = texture(normal_tex, uv).rgb;
		} else {
			AO = ambient_k;
			ROUGHNESS = base_rough;
			METALLIC = 0.0;
		}
	} else {
		ALBEDO = base_col * tint.rgb;
		AO = ambient_k;
		ROUGHNESS = base_rough;
		METALLIC = base_metal;
	}
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = texture(emit_tex, UV).rgb * emit_energy;
	if (rim_k > 0.0 || trans_k > 0.0) {
		// kontra księżyca liczona w shaderze (FOREGROUND_PLAN.md zasada 5: bez nowych świateł — `MoonRim` świeci tylko na warstwę lasu):
		// obrys tej krawędzi bryły, która w kadrze jest zwrócona ku tarczy księżyca, i prześwit kart igliwia pod światło
		vec3 mv = normalize((VIEW_MATRIX * vec4(moon_dir, 0.0)).xyz);
		vec3 n = normalize(NORMAL);
		float fr = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
		float side = smoothstep(0.1, 0.85, dot(normalize(n.xy + vec2(1e-4)), normalize(mv.xy)));
		// prześwit niezależny od samej jasności tekstury (+0,06): ciemnozielone igliwie ma albedo liniowe ok. 0,03 i bez tego by nie świeciło
		EMISSION += rim_col * moon * (rim_k * fr * side + trans_k * (ALBEDO + vec3(0.06)));
	}
	ALPHA = a;
}
"""

static var _mats: Dictionary = {}
static var _moon_mats: Array = []          ## materiały lasu z kontrą księżyca (`set_moon`)
static var _shaders: Dictionary = {}
static var _wall_mats: Dictionary = {}
static var _parts: Dictionary = {}
static var _lamp_mesh: Mesh
static var _root: Node3D

## Krycie w odległości `d` [m] od prostokąta sylwetki przy wadze `w` — ta sama funkcja co w shaderze (test).
static func fade(d: float, w := 1.0) -> float:
	return lerpf(1.0, lerpf(MIN_A, 1.0, smoothstep(0.0, FADE_M, d)), w)


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Shader pierwszego planu; `two_sided`: karty lasu (igliwie, paproć) widoczne z obu stron. Jeden obiekt na wariant.
static func _shader(two_sided := false) -> Shader:
	if _shaders.has(two_sided):
		return _shaders[two_sided]
	var sh := Shader.new()
	sh.code = SHADER.replace("cull_back", "cull_disabled") if two_sided else SHADER
	_shaders[two_sided] = sh
	return sh


## Materiał lasu (klucz „f:<tekstura>”): kora (pień) albo karta z alfą (`card`), z kontrą księżyca. Rejestruje go w `_mats`,
## więc wygaszanie przy sylwetkach (`update`) obejmuje go tak samo jak rury.
static func _forest_mat(tex: String, card: bool) -> String:
	var key := "f:" + tex
	materials()
	if _mats.has(key):
		return key
	var m := ShaderMaterial.new()
	m.shader = _shader(card)
	m.set_shader_parameter("min_a", MIN_A)
	m.set_shader_parameter("fade_m", FADE_M)
	m.set_shader_parameter("albedo_tex", _tex(FOREST_TEX % tex))
	m.set_shader_parameter("has_arm", false)
	m.set_shader_parameter("base_rough", 0.9)
	m.set_shader_parameter("alb_k", float(FOREST_ALB.get(tex, 1.0)))
	m.set_shader_parameter("moon_dir", Level3D.MOON_DIR.normalized())
	if card:
		m.set_shader_parameter("cutout", true)
		m.set_shader_parameter("trans_k", FOREST_TRANS * float(FOREST_TRANS_K.get(tex, 1.0)))
		m.set_shader_parameter("sway", 0.05)
		m.set_shader_parameter("sway_uv", Vector2(1.0, 0.0) if tex.begins_with("bough") else Vector2(0.0, 1.0))
	else:
		m.set_shader_parameter("rim_k", FOREST_RIM)
	_mats[key] = m
	_moon_mats.append(m)
	return key


## Pogoda i błysk burzy na kontrze lasu: `k` = energia `MoonRim` / `Level3D.MOON_RIM` (`view3d._sync_weather`).
static func set_moon(k: float) -> void:
	for m: ShaderMaterial in _moon_mats:
		m.set_shader_parameter("moon", k)


## Materiały: g1 / g2 (dwie grupy tekstur zestawu rur), dark (kable, łańcuchy, obejmy), lamp (klosz z emisją żarówki).
static func materials() -> Dictionary:
	if not _mats.is_empty():
		return _mats
	var sh := _shader()
	for key: String in MATS:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("min_a", MIN_A)
		m.set_shader_parameter("fade_m", FADE_M)
		match key:
			"g1", "g2":
				var g := 1 if key == "g1" else 2
				m.set_shader_parameter("albedo_tex", _tex(PIPE_TEX % [g, "diff"]))
				m.set_shader_parameter("arm_tex", _tex(PIPE_TEX % [g, "arm"]))
				m.set_shader_parameter("normal_tex", _tex(PIPE_TEX % [g, "nor_gl"]))
			"dark":
				m.set_shader_parameter("use_tex", false)
				m.set_shader_parameter("base_col", Color(0.045, 0.043, 0.042))
				m.set_shader_parameter("base_rough", 0.5)
				m.set_shader_parameter("base_metal", 0.3)
			"lamp":
				m.set_shader_parameter("albedo_tex", _tex(LAMP_TEX % "Color"))
				m.set_shader_parameter("arm_tex", _tex(LAMP_TEX % "ORM"))
				m.set_shader_parameter("normal_tex", _tex(LAMP_TEX % "NormalGL"))
				m.set_shader_parameter("emit_tex", _tex(LAMP_EMI))
				m.set_shader_parameter("emit_energy", 6.0)
		_mats[key] = m
	return _mats


## Części rur z `pipe_parts.glb`: nazwa → [siatka, grupa tekstur ("g1"/"g2"), wysokość w źródle].
static func parts() -> Dictionary:
	if not _parts.is_empty() or not ResourceLoader.exists(PARTS_GLB):
		return _parts
	var inst := (load(PARTS_GLB) as PackedScene).instantiate()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if not "__g" in nm:
			continue
		var aabb := mi.mesh.get_aabb()
		_parts[nm.get_slice("__", 0)] = [mi.mesh, "g" + nm.get_slice("__g", 1).left(1), aabb.position.y + aabb.size.y]
	inst.free()
	return _parts


static func _lamp() -> Mesh:
	if _lamp_mesh == null and ResourceLoader.exists(LAMP_GLB):
		var inst := (load(LAMP_GLB) as PackedScene).instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			_lamp_mesh = (found[0] as MeshInstance3D).mesh
		inst.free()
	return _lamp_mesh


## Pas wpisu na płaszczyźnie gry [x0, x1, y0, y1] w metrach: kolumny c0..c1, od górnej krawędzi podłogi (r1) do dolnej krawędzi stropu (r0).
static func clip_of(e: Dictionary) -> Vector4:
	var T := Level3D.T
	return Vector4(float(e["c0"]) * T, float(int(e["c1"]) + 1) * T, -float(e["r1"]) * T, -float(int(e["r0"]) + 1) * T)


static func _skipped(x: float, skip: Array) -> bool:
	for s in skip:
		if x >= float(s[0]) * Level3D.T - MARGIN and x <= float(int(s[1]) + 1) * Level3D.T + MARGIN:
			return true
	return false


## Rozmieszczenie (bez węzłów, do testu i budowy): [{kind, x, z, big, clip, set}] dla wpisów `FRONT`, z pominięciem `skip`
## ([c0, c1]); `low` pomija małe elementy. Stałe ziarno z wpisu, więc ten sam układ u wszystkich graczy.
## Czy elementy dwóch pasów (clip: x0, x1, y podłogi, y stropu) mogą stać w jednym kadrze NORMAL. Nie, gdy pasy dzieli więcej niż kadr,
## albo gdy oba mają przekrój (F2b) i jeden leży cały nad drugim: płyta stropu / podłogi sięga do SHELL_Z, a shader (`occ`) chowa za nią
## element innego piętra — z kamery na jednym piętrze widać tylko jego pierwszy plan (piętra kryjówki).
static func apart(a: Vector4, a_shell: bool, b: Vector4, b_shell: bool) -> bool:
	if maxf(0.0, maxf(a.z, b.z) - minf(a.w, b.w)) >= FRAME_H_NORMAL:
		return true
	return a_shell and b_shell and (a.w <= b.z + 0.01 or b.w <= a.z + 0.01)

static func layout(front: Array, skip: Array, low := false, blocked: Array = []) -> Array:
	var out := []
	for e: Dictionary in front:
		var st: Dictionary = SETS.get(String(e.get("set", "")), {})
		if st.is_empty():
			continue
		var clip := clip_of(e)
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xF407 + int(e["c0"]) * 131 + int(e["r0"]) * 7
		# wpisy, których pasy mieszczą się razem w kadrze NORMAL: duży element innego wpisu zajmuje ±BIG_SPACING.x dla dużych
		# i ±SMALL_MIN dla małych, mały — ±SMALL_MIN dla dużych (najwyżej jeden duży element w kadrze także między wpisami)
		var blk_big := blocked.duplicate()
		var blk_small := blocked.duplicate()
		for o: Dictionary in out:
			var oc: Vector4 = o["clip"]
			if apart(oc, bool(o["shell"]), clip, bool(e.get("shell", false)) and not "--noshell" in OS.get_cmdline_user_args()):
				continue
			var ox: float = o["x"]
			if bool(o["big"]):
				blk_big.append(Vector2(ox - BIG_SPACING.x, ox + BIG_SPACING.x))
				blk_small.append(Vector2(ox - SMALL_MIN, ox + SMALL_MIN))
			else:
				blk_big.append(Vector2(ox - SMALL_MIN, ox + SMALL_MIN))
		var xs := []
		var x := clip.x + MARGIN + rng.randf_range(2.0, 8.0)
		while x < clip.y - MARGIN:
			x = _free_x(x, blk_big)
			if x >= clip.y - MARGIN:
				break
			xs.append(x)
			x += rng.randf_range(BIG_SPACING.x, BIG_SPACING.y)
		var bi := 0
		for i in xs.size():
			var xb: float = xs[i]
			if not _skipped(xb, skip):
				var kb: String = st["big"][bi % (st["big"] as Array).size()]
				bi += 1
				out.append({"kind": kb, "x": xb, "z": rng.randf_range(Z_RANGE.x, Z_RANGE.y), "big": true, "clip": clip, "set": e["set"], "shell": bool(e.get("shell", false)) and not "--noshell" in OS.get_cmdline_user_args()})
			var nx: float = xs[i + 1] if i + 1 < xs.size() else clip.y - MARGIN
			var pair := st.has("small2")
			for si in (2 if pair else 1):
				var key := "small2" if si == 1 else "small"
				var frac := (0.36 if si == 0 else 0.66) if pair else 0.5
				var xm := _free_x(lerpf(xb, nx, frac) + rng.randf_range(-3.0, 3.0) * (0.5 if pair else 1.0), blk_small)
				var ks: String = st[key][rng.randi() % (st[key] as Array).size()]
				var want := rng.randf() < 0.6
				if want and not low and xm - xb >= SMALL_MIN and nx - xm >= SMALL_MIN and xm < clip.y - MARGIN and not _skipped(xm, skip):
					out.append({"kind": ks, "x": xm, "z": rng.randf_range(Z_RANGE.x, Z_RANGE.y), "big": false, "clip": clip, "set": e["set"], "shell": bool(e.get("shell", false)) and not "--noshell" in OS.get_cmdline_user_args()})
	return out


## Pierwsze x ≥ `x` poza przedziałami `blocked` ([Vector2(x0, x1)], m).
static func _free_x(x: float, blocked: Array) -> float:
	var moved := true
	while moved:
		moved = false
		for b: Vector2 in blocked:
			if x >= b.x and x <= b.y:
				x = b.y + 0.01
				moved = true
	return x


## Przekrój (F2b): przedziały x, w których element nie może stanąć — kałuża na płycie podłogi (rura stałaby w cieczy) i belka pod stropem
## ±1 m (`Level3D.interior_ribs`; belka w warstwie świata przecinałaby rurę), stanowisko ±`STATION_PAD`. Tylko wpisy z `"shell": true`.
## Znaki mapy stanowisk (`level.gd`: tablice, warsztat, szafki, skrzynka, tokarka, stoły, radio, gabloty) i zapas z boków (m).
const STATION_CH := "vhnRgpjdxzc"
const STATION_PAD := 1.0

static func blocked_x(front: Array, rows: Array) -> Array:
	var out := []
	if rows.is_empty():
		return out
	var T := Level3D.T
	var ribs: Array = Level3D.interior_ribs(rows)
	for e: Dictionary in front:
		if not bool(e.get("shell", false)):
			continue
		var r0 := int(e["r0"])
		var r1 := int(e["r1"])
		for c in range(int(e["c0"]), int(e["c1"]) + 1):
			# kałuża na płycie, a także otwór w stropie albo w podłodze (kratka, właz szybu): rura nie miałaby się na czym oprzeć
			var lo := String(rows[r1]).substr(c, 1)
			if lo in "O~m" or not lo in Level3D.SHELL_CH or not String(rows[r0]).substr(c, 1) in Level3D.SHELL_CH:
				out.append(Vector2(float(c) * T - 0.6, float(c + 1) * T + 0.6))
		for rb: Dictionary in ribs:
			var rc := int(rb["c"])
			if rc >= int(e["c0"]) and rc <= int(e["c1"]):
				var rx := (float(rc) + 0.5) * T
				out.append(Vector2(rx - 1.0, rx + 1.0))
	# stanowiska warsztatu (kryjówka): element przed płaszczyzną gry zasłaniałby stanowisko, a wygaszanie obejmuje tylko postacie
	for e: Dictionary in front:
		if not bool(e.get("shell", false)):
			continue
		for r in range(int(e["r0"]) + 1, int(e["r1"])):
			for c in range(int(e["c0"]), int(e["c1"]) + 1):
				if String(rows[r]).substr(c, 1) in STATION_CH:
					out.append(Vector2(float(c) * T - STATION_PAD, float(c + 1) * T + STATION_PAD))
	# wyciek oleju (plama i przewrócona beczka na płycie przekroju): rura nie stoi w oleju
	for sp: Dictionary in Level3D.oil_spills(rows):
		var xr: Vector2 = sp["xr"]
		out.append(Vector2(xr.x - 0.3, xr.y + 0.3))
	# plama błota na płycie przekroju (`Level3D.mud_spills`): rura nie stoi w błocie
	for sp: Dictionary in Level3D.mud_spills(rows):
		if (sp["zr"] as Vector2).y > Level3D.DEPTH_FRONT:
			out.append(Vector2(float(sp["x0"]) - 1.2, float(sp["x1"]) + 1.2))
	return out


static func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Kolumna rury od `y0` w górę do `y1`: odcinki `seg` w skali `s`; po drodze raz zawór (koło ku kamerze) przy `y_valve`
## i raz trójnik przy `y_tee` (ujemne = bez). Dokłada części do koszyków materiałów `sts`.
static func _pipe_column(sts: Dictionary, x: float, z: float, y0: float, y1: float, s: float, base: String, y_valve: float, y_tee: float) -> void:
	var p := parts()
	var y := y0
	var valve_done := y_valve < y0
	var tee_done := y_tee < y0
	while y < y1:
		var nm := base
		if not valve_done and y + 0.86 * s >= y_valve:
			nm = "valve"
			valve_done = true
		elif not tee_done and y + 0.86 * s >= y_tee:
			nm = "tee"
			tee_done = true
		var part: Array = p.get(nm, [])
		if part.is_empty():
			return
		(sts[part[1]] as SurfaceTool).append_from(part[0], 0, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(x, y, z)))
		y += float(part[2]) * s


## Siatka jednego elementu: środek u góry w (0, y_top), w dół do y_bot; `band` = pas wpisu [y0 podłoga, y1 strop] w metrach.
## Powierzchnie w kolejności MATS (puste koszyki pominięte); zwraca [ArrayMesh, [klucze materiałów]]. Do `lights` dopisuje miejsca żarówek.
static func _element_mesh(kind: String, y_top: float, y_bot: float, band: Vector2, rng: RandomNumberGenerator, lights: Array = [], phys := false) -> Array:
	var lo := 0.0 if phys else 1.0                      # F2b: z przekrojem rura zaczyna się kołnierzem na płycie podłogi
	var sts := {}
	for key: String in MATS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
	var dark := sts["dark"] as SurfaceTool
	var h := y_top - y_bot
	var ym := (y_top + y_bot) * 0.5
	var used := {}
	match kind:
		"pipe":
			# zawór nad głowami (górna część pasa), trójnik nisko — oba w kadrze, kiedy kamera stoi przy podłodze pasa
			var yv := band.y - rng.randf_range(1.6, 3.2)
			var yt := band.x + rng.randf_range(0.6, 1.6) if rng.randf() < 0.6 else -1e6
			_pipe_column(sts, 0.0, 0.0, y_bot + rng.randf_range(-1.7, 0.0) * lo, y_top, PIPE_SCALE, "seg", yv, yt)
			used["g1"] = true
			used["g2"] = true
			for i in 2:                                          # kable wzdłuż rury
				dark.append_from(_cyl(0.026, h, 8), 0, Transform3D(Basis.IDENTITY, Vector3(0.5 + 0.08 * float(i), ym, -0.14)))
			used["dark"] = true
		"pipes2":
			_pipe_column(sts, -0.26, 0.0, y_bot + rng.randf_range(-3.9, 0.0) * lo, y_top, 1.5, "thin", -1e6, -1e6)
			_pipe_column(sts, 0.24, -0.06, y_bot + rng.randf_range(-1.0, 0.0) * lo, y_top, 1.2, "seg", band.y - rng.randf_range(1.8, 3.0), -1e6)
			used["g1"] = true
			used["g2"] = true
			var clamp_m := BoxMesh.new()
			clamp_m.size = Vector3(0.86, 0.08, 0.40)
			var bolt := _cyl(0.035, 0.05, 8)
			var yc := y_bot + rng.randf_range(0.0, 3.0)
			var g1 := sts["g1"] as SurfaceTool
			while yc < y_top:                                    # obejmy co 3 m (malowana stal jak rury), ze śrubami na końcach
				g1.append_from(clamp_m, 0, Transform3D(Basis.IDENTITY, Vector3(-0.01, yc, -0.03)))
				for bx in [-0.38, 0.36]:
					dark.append_from(bolt, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bx, yc, 0.19)))
				yc += 3.0
			used["dark"] = true
		"cables":
			var n := rng.randi_range(3, 5)
			for i in n:
				var tilt := rng.randf_range(-0.035, 0.035)
				var r := rng.randf_range(0.02, 0.036)
				dark.append_from(_cyl(r, h, 10), 0, Transform3D(Basis(Vector3.BACK, tilt), Vector3(float(i) * 0.09 + rng.randf_range(-0.02, 0.02), ym, -0.06 * float(i))))
			var tie := _cyl(0.24, 0.05, 12)
			var yt2 := y_bot + rng.randf_range(0.0, 2.0)
			while yt2 < y_top:                                   # opaski co 2,5 m
				dark.append_from(tie, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.55)), Vector3(float(n - 1) * 0.045, yt2, -0.03 * float(n - 1))))
				yt2 += 2.5
			used["dark"] = true
		"chain":
			var link := TorusMesh.new()
			link.inner_radius = 0.032
			link.outer_radius = 0.058
			link.rings = 12
			link.ring_segments = 8
			var pitch := 0.085
			var len_m := rng.randf_range(3.5, 7.0)               # zwisa ze stropu (przycięcie pasa ucina górę na linii stropu)
			var yl := y_top
			var i := 0
			while yl > y_top - ABOVE - len_m and yl > y_bot:
				var b := Basis(Vector3.RIGHT, PI * 0.5) * (Basis(Vector3.FORWARD, PI * 0.5) if i % 2 == 1 else Basis.IDENTITY)
				dark.append_from(link, 0, Transform3D(b.scaled(Vector3(1.0, 1.0, 1.35)), Vector3(0.0, yl, 0.0)))
				yl -= pitch
				i += 1
			var hook := TorusMesh.new()
			hook.inner_radius = 0.07
			hook.outer_radius = 0.11
			hook.rings = 14
			hook.ring_segments = 8
			dark.append_from(hook, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, yl - 0.1, 0.0)))
			used["dark"] = true
		"pine", "birch", "snag":
			_trunk(sts, used, kind, band.x, rng)
		"bough":
			_bough(sts, used, band.x, rng)
		"ferns", "grass":
			_ferns(sts, used, kind, band.x, rng, 2.2)
		"lamp":
			# lampa na przewodzie: klosz z modelu `lamp` (emisja żarówki), przewód do stropu (przycięcie pasa ucina go na linii stropu)
			var y_lamp := band.y - rng.randf_range(LAMP_DROP.x, LAMP_DROP.y)
			var lm := _lamp()
			if lm != null:
				var la := lm.get_aabb()
				var s := LAMP_H / maxf(la.size.y, 0.001)
				var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(0.0, y_lamp - la.position.y * s, 0.0))
				(sts["lamp"] as SurfaceTool).append_from(lm, 0, xf)
				used["lamp"] = true
				lights.append(Vector3(0.0, y_lamp + 0.12, 0.0))
			var top := y_lamp + LAMP_H
			dark.append_from(_cyl(0.014, y_top - top, 8), 0, Transform3D(Basis.IDENTITY, Vector3(0.0, (y_top + top) * 0.5, 0.0)))
			used["dark"] = true
	var mesh := ArrayMesh.new()
	var keys := []
	for key: String in sts:
		if used.has(key):
			var st := sts[key] as SurfaceTool
			if key != "dark":
				st.generate_tangents()
			st.commit(mesh)
			keys.append(key)
	return [mesh, keys]


# ---------------------------------------------------------------- las (F3)

static func _st(sts: Dictionary, key: String) -> SurfaceTool:
	if not sts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
	return sts[key]


## Stożek ścięty wzdłuż `axis` od `a`: promień `r0` → `r1`, `seg` boków, `rings` odcinków; nierówność kory `rough` (część promienia,
## z ziarna `ph`); UV: u dookoła (`u_rep` powtórzeń), v liniowo `v` (dół → góra); `bend` wygina środek łukiem. Trójkąty bez indeksów.
static func _cone(st: SurfaceTool, a: Vector3, axis: Vector3, length: float, r0: float, r1: float, seg: int, rings: int, v: Vector2, u_rep: float, rough: float, ph: float, bend := Vector3.ZERO) -> void:
	var ax := axis.normalized()
	var side := ax.cross(Vector3.BACK)
	if side.length() < 0.1:
		side = ax.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(ax).normalized()
	var grid := []
	for j in rings + 1:
		var t := float(j) / float(rings)
		var c := a + ax * (length * t) + bend * sin(t * PI)
		var r := lerpf(r0, r1, t)
		var row := []
		for i in seg + 1:
			var ang := TAU * float(i) / float(seg)
			var nrm := side * cos(ang) + up * sin(ang)
			var wob := 1.0 + rough * (sin(3.0 * ang + t * length * 0.9 + ph) * 0.6 + sin(7.0 * ang - t * length * 1.7 + ph * 2.3) * 0.4)
			row.append([c + nrm * r * wob, nrm, Vector2(u_rep * float(i) / float(seg), lerpf(v.x, v.y, t))])
		grid.append(row)
	for j in rings:
		for i in seg:
			var q: Array = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
			for k in [0, 1, 2, 0, 2, 3]:                   # zgodnie z ruchem wskazówek zegara od zewnątrz (przód ściany w Godocie)
				st.set_normal(q[k][1])
				st.set_uv(q[k][2])
				st.add_vertex(q[k][0])


## Karta (prostokąt `w` × `h`) zaczepiona w `at` punktem `pivot` (UV karty: (0.5, 1) = środek podstawy, (0, 0) = lewy górny róg),
## obrót `rz` w płaszczyźnie kadru i `ry` wokół pionu; `flip` odbija w poziomie.
static func _card(st: SurfaceTool, at: Vector3, w: float, h: float, rz: float, ry: float, flip: bool, pivot := Vector2(0.5, 1.0)) -> void:
	var b := Basis(Vector3.UP, ry) * Basis(Vector3.BACK, rz)
	var nrm := (b * Vector3.BACK).normalized()
	var corners := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var pts := []
	for c: Vector2 in corners:
		var lx := (c.x - pivot.x) * w * (-1.0 if flip else 1.0)
		var ly := (pivot.y - c.y) * h
		pts.append([at + b * Vector3(lx, ly, 0.0), c])
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(nrm)
		st.set_uv(pts[k][1])
		st.add_vertex(pts[k][0])


## Pień przez cały kadr (podstawa i koniec poza nim): lekko pochylony i wygięty, nierówna kora; sosna z martwym sękiem i czasem
## gałęzią z igliwiem przy górnym brzegu, martwy pień z połamanymi konarami, brzoza z cienką gałązką. U nasady kępa paproci.
static func _trunk(sts: Dictionary, used: Dictionary, kind: String, y_floor: float, rng: RandomNumberGenerator) -> void:
	var spec: Array = TRUNKS[kind]
	var key := _forest_mat(String(spec[0]), false)
	var st := _st(sts, key)
	used[key] = true
	var y0 := y_floor + TRUNK_SPAN.x
	var length := TRUNK_SPAN.y - TRUNK_SPAN.x
	var d := float(spec[1]) * rng.randf_range(0.85, 1.15)
	var taper := float(spec[2])
	var r0 := (d + taper * -TRUNK_SPAN.x) * 0.5
	var r1 := maxf(r0 - taper * length * 0.5, 0.08)
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 1.0, rng.randf_range(-0.02, 0.02))
	var bend := Vector3(rng.randf_range(0.25, 0.6) * (-1.0 if rng.randf() < 0.5 else 1.0), 0.0, 0.0)
	var ph := rng.randf() * TAU
	var vr: Vector2 = spec[3]
	_cone(st, Vector3(0.0, y0, 0.0), lean, length, r0, r1, 14, 26, vr, 2.0, 0.11 if kind == "snag" else 0.075, ph, bend)
	var v_mid := (vr.x + vr.y) * 0.5
	var limbs := 1
	if kind == "snag":
		limbs = rng.randi_range(3, 5)
	elif kind == "pine":
		limbs = rng.randi_range(1, 2)
	for i in limbs:
		# konary w płaszczyźnie kadru (w lewo albo w prawo, lekko ku kamerze lub od niej) — sylwetka czytelna; martwe konary połamane i krótkie
		var yb := y_floor + (rng.randf_range(1.5, 8.5) if kind == "snag" else rng.randf_range(3.0, 9.0))
		var sgn := -1.0 if (i + rng.randi()) % 2 == 0 else 1.0
		var upk := rng.randf_range(0.6, 1.2) if kind == "birch" else rng.randf_range(0.25, 0.9)
		var dir := Vector3(sgn, upk, rng.randf_range(-0.35, 0.35)).normalized()
		var ln := rng.randf_range(0.9, 2.3)
		if kind == "pine":
			ln = rng.randf_range(0.25, 0.6)
		elif kind == "birch":
			ln = rng.randf_range(1.2, 2.2)
		var rt := _trunk_r(r0, r1, y0, length, yb)
		var rb := rt * (0.22 if kind == "snag" else 0.16)
		var c := _trunk_axis(lean, bend, y0, length, yb)
		var lv := Vector2(0.98, 0.96) if kind == "birch" else Vector2(v_mid, v_mid - 0.05)      # gałązki brzozy ciemne (czarna nasada kory)
		_cone(st, c + dir * rt * 0.6, dir, ln, rb, rb * 0.25, 6, 3, lv, 1.0, 0.1, ph + float(i), Vector3(0.0, -0.08 * ln, 0.0))
	if kind == "pine" and rng.randf() < 0.65:
		# gałąź korony przy górnym brzegu kadru: konar w bok z kępami igliwia na końcu (karty `pine_tuft`)
		var yb := y_floor + rng.randf_range(BOUGH_Y.x - 1.0, BOUGH_Y.y)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var dir := Vector3(sgn, rng.randf_range(0.1, 0.35), rng.randf_range(-0.2, 0.2)).normalized()
		var ln := rng.randf_range(1.8, 3.0)
		var c := _trunk_axis(lean, bend, y0, length, yb)
		var rb := _trunk_r(r0, r1, y0, length, yb) * 0.3
		_cone(st, c, dir, ln, rb, rb * 0.3, 6, 4, Vector2(v_mid, v_mid - 0.1), 1.0, 0.08, ph, Vector3(0.0, -0.15 * ln, 0.0))
		var tk := _forest_mat("pine_tuft", true)
		var tst := _st(sts, tk)
		used[tk] = true
		for j in rng.randi_range(3, 4):
			var at := c + dir * ln * rng.randf_range(0.45, 1.0) + Vector3(0.0, rng.randf_range(-0.35, 0.1), rng.randf_range(-0.25, 0.25))
			var s := rng.randf_range(1.0, 1.5)
			_card(tst, at, s * 1.2, s, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5), rng.randf() < 0.5, Vector2(0.5, 0.6))
	_ferns(sts, used, "ferns", y_floor, rng, 1.2)


## Środek pnia na wysokości `y` (bez nierówności kory) i jego promień.
static func _trunk_axis(lean: Vector3, bend: Vector3, y0: float, length: float, y: float) -> Vector3:
	var t := clampf((y - y0) / length, 0.0, 1.0)
	return Vector3(lean.x / lean.y * (y - y0), y, lean.z / lean.y * (y - y0)) + bend * sin(t * PI)


static func _trunk_r(r0: float, r1: float, y0: float, length: float, y: float) -> float:
	return lerpf(r0, r1, clampf((y - y0) / length, 0.0, 1.0))


## Zwisająca gałąź świerka (`bough_side`): nasada nad górnym brzegiem kadru, gałąź opada w bok i w dół; dwie lub trzy karty
## w lekko innej głębi i pod innym kątem (bryła zamiast płaskiej naklejki).
static func _bough(sts: Dictionary, used: Dictionary, y_floor: float, rng: RandomNumberGenerator) -> void:
	var key := _forest_mat("bough_side", true)
	var st := _st(sts, key)
	used[key] = true
	var flip := rng.randf() < 0.5
	var base := Vector3(0.0, y_floor + rng.randf_range(BOUGH_Y.x, BOUGH_Y.y), 0.0)
	for i in rng.randi_range(2, 3):
		var w := rng.randf_range(2.6, 3.6)
		var droop := rng.randf_range(0.22, 0.5) * (1.0 if flip else -1.0)        # w prawo: zgodnie z ruchem wskazówek (w dół), odbita w lewo: przeciwnie
		var at := base + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.5, 0.2), rng.randf_range(-0.3, 0.3))
		_card(st, at, w, w * 0.5, droop, rng.randf_range(-0.35, 0.35), flip, Vector2(0.0, 0.1))


## Kępa paproci i trawy przy dolnym brzegu kadru (`ferns`: głównie paproć, `grass`: głównie trawa) szeroka na 2 × `spread` m.
static func _ferns(sts: Dictionary, used: Dictionary, kind: String, y_floor: float, rng: RandomNumberGenerator, spread: float) -> void:
	for i in rng.randi_range(3, 5):
		var fern := rng.randf() < (0.7 if kind == "ferns" else 0.2)
		var tex := "fern_a" if fern else ("grass_a" if rng.randf() < 0.55 else "grass_b")
		var key := _forest_mat(tex, true)
		var st := _st(sts, key)
		used[key] = true
		var top := y_floor + rng.randf_range(FERN_TOP.x, FERN_TOP.y)
		var h := top - (y_floor + FERN_BASE)
		var w := h * (1.6 if fern else rng.randf_range(0.9, 1.2))
		var at := Vector3(rng.randf_range(-spread, spread), y_floor + FERN_BASE, rng.randf_range(-0.4, 0.4))
		_card(st, at, w, h, rng.randf_range(-0.12, 0.12), rng.randf_range(-0.6, 0.6), rng.randf() < 0.5)


## Buduje elementy pod `parent` (węzeł „Front”). Zwraca liczbę elementów.
static func build(parent: Node3D, front: Array, skip: Array, low: bool, rows: Array = []) -> int:
	_root = null
	if front.is_empty():
		return 0
	_root = Node3D.new()
	_root.name = "Front"
	parent.add_child(_root)
	var mats := materials()
	var items := layout(front, skip, low, blocked_x(front, rows))
	for it: Dictionary in items:
		var clip: Vector4 = it["clip"]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(it["x"]) * 100.0)
		var bulbs := []
		var phys := bool(it.get("shell", false))
		var occ_z := Level3D.SHELL_Z
		if phys and Level3D.in_trench(int(floorf(float(it["x"]) / Level3D.T)), roundi(-clip.z / Level3D.T)):
			clip.z -= Level3D.TRENCH_D                      # torowisko: płyta przekroju leży na wysokości dna koryta — element stoi na podsypce
		if phys and not rows.is_empty():
			# dach z blachy (hala stacji): stropu nie ma — element wisi pod płatwią, na jej głębokości (najbliższa w Z_RANGE z kołnierzem
			# przed przodem przekroju), i dochodzi do jej spodu; płatew bliżej kamery rzutuje się wyżej, więc rury nie przecina
			var rp := Level3D.roof_purlins(rows, int(floorf(float(it["x"]) / Level3D.T)), roundi(-clip.w / Level3D.T) - 1)
			if not rp.is_empty():
				occ_z = Level3D.SHELL_Z + Level3D.ROOF_EAVE              # blacha dachu wystaje okapem przed przekrój
				var best := float(it["z"])
				var dmin := INF
				for pz: float in rp[1]:
					if pz >= Z_RANGE.x - 0.3 and pz + 0.45 < Level3D.SHELL_Z and absf(pz - float(it["z"])) < dmin:
						dmin = absf(pz - float(it["z"]))
						best = pz
				if dmin < INF:
					it["z"] = best
					clip.w = float(rp[0])
		var res := _element_mesh(String(it["kind"]), clip.w + (0.0 if phys else ABOVE), clip.z - (0.0 if phys else ABOVE), Vector2(clip.z, clip.w), rng, bulbs, phys)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d" % [it["kind"], roundi(float(it["x"]))]
		mi.mesh = res[0]
		var keys: Array = res[1]
		for si in keys.size():
			mi.set_surface_override_material(si, mats[keys[si]])
		mi.layers = LAYER_FRONT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.position = Vector3(float(it["x"]), 0.0, float(it["z"]))
		var st: Dictionary = SETS[it["set"]]
		if phys:
			# F2b: element stoi na płycie przekroju (`Level3D.SHELL_Z`) i dochodzi do stropu — przycięcie fizyczne zamiast w rzucie
			mi.set_instance_shader_parameter("clip", Vector4(-1e6, 1e6, -1e6, 1e6))
			mi.set_instance_shader_parameter("ywin", Vector2(clip.z, clip.w))
			var occ := Vector4(clip.w + 0.02, clip.z - 0.02, occ_z, Level3D.SHELL_Z)
			mi.set_instance_shader_parameter("occ", occ)
			if bool(it["big"]):
				_contact(mi, clip.z, clip.w)
				var plate := mi.get_node_or_null("Plate") as MeshInstance3D
				if plate != null:
					plate.set_instance_shader_parameter("occ", occ)
		elif bool(st.get("open", false)):
			mi.set_instance_shader_parameter("clip", Vector4(clip.x - OPEN_PAD, clip.y + OPEN_PAD, -1e6, 1e6))
		else:
			mi.set_instance_shader_parameter("clip", clip)
		mi.set_instance_shader_parameter("tint", st["tint"])
		_root.add_child(mi)
		for b: Vector3 in bulbs:
			# światło żarówki tylko na pierwszy plan (klosz od środka, przewód, sąsiednia rura): nie rozjaśnia postaci ani świata,
			# więc ciemność przy graczach się nie zmienia (GDD §8.3)
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.78, 0.5)
			ol.light_energy = 1.6
			ol.omni_range = 2.5
			ol.omni_attenuation = 1.4
			ol.light_cull_mask = LAYER_FRONT
			ol.layers = LAYER_FRONT
			ol.shadow_enabled = false
			ol.light_volumetric_fog_energy = 0.0
			ol.position = b
			mi.add_child(ol)
	return items.size()


const CONTACT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.75;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.25, 1.0, r));
}
"""
static var _contact_mat: ShaderMaterial = null

## F2b: plama okluzji pod kołnierzem na wierzchu płyty (warstwa świata — pierwszy plan nie rzuca cienia) i płytka mocująca pod stropem.
static func _contact(mi: MeshInstance3D, y_floor: float, y_ceil: float) -> void:
	if _contact_mat == null:
		var sh := Shader.new()
		sh.code = CONTACT_SHADER
		_contact_mat = ShaderMaterial.new()
		_contact_mat.shader = sh
	var q := PlaneMesh.new()
	q.size = Vector2(1.9, 1.5)
	var blob := MeshInstance3D.new()
	blob.name = "Contact"
	blob.mesh = q
	blob.material_override = _contact_mat
	blob.layers = 1                                             # LAYER_WORLD (view3d.gd): leży na płycie, pod graczami
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position = Vector3(0.0, y_floor + 0.01, 0.0)
	mi.add_child(blob)
	var plate := BoxMesh.new()
	plate.size = Vector3(0.9, 0.06, 0.7)
	var pm := MeshInstance3D.new()
	pm.name = "Plate"
	pm.mesh = plate
	pm.material_override = materials()["dark"]
	pm.layers = LAYER_FRONT
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.position = Vector3(0.0, y_ceil - 0.03, 0.0)
	mi.add_child(pm)


## Stan z ustawień: widoczność (OFF). `low` zostaje w podpisie dla zgodności z wywołaniem (LOW zmienia tylko rozmieszczenie przy budowie).
static func apply_settings(mode: int, _low: bool) -> void:
	if _root != null and is_instance_valid(_root):
		_root.visible = mode != 2


## Co klatkę: sylwetki do wygaszenia ([Vector4(x, y, pół szer., pół wys.), waga] na płaszczyźnie gry, w kolejności ważności),
## środek i wysokość kadru [m].
static func update(points: Array, mid_y: float, frame_h: float, reduced: bool) -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_PTS)
	var wts := PackedFloat32Array()
	wts.resize(MAX_PTS)
	var n := mini(points.size(), MAX_PTS)
	for i in n:
		arr[i] = points[i][0]
		wts[i] = float(points[i][1])
	for m: ShaderMaterial in materials().values():
		m.set_shader_parameter("pts", arr)
		m.set_shader_parameter("wts", wts)
		m.set_shader_parameter("npts", n)
		m.set_shader_parameter("mid_y", mid_y)
		m.set_shader_parameter("band", frame_h * REDUCED_BAND if reduced else 0.0)
	for m: ShaderMaterial in _wall_mats.values():           # ściany przekroju: wygaszanie tak samo, ale bez pasa REDUCED (to bryła budynku)
		m.set_shader_parameter("pts", arr)
		m.set_shader_parameter("wts", wts)
		m.set_shader_parameter("npts", n)


# ---------------------------------------------------------------- ściany przekroju (F3, uwaga z gry 2026-11-08)

## Tekstury ścian przekroju jak materiały świata (`Level3D.build_level`: `mats["C"]`, `mats["#"]`): nazwa, kafli na metr, brud.
const WALL_TEX := {"C": ["concrete", 0.33, "stone"], "#": ["terrain", 0.30, "organic"]}

## Materiał ściany przekroju: shader pierwszego planu (wygaszanie na sylwetkach, `occ`) z teksturą świata w rzucie trójpłaszczyznowym.
static func wall_material(key: String) -> ShaderMaterial:
	if _wall_mats.has(key):
		return _wall_mats[key]
	var spec: Array = WALL_TEX.get(key, WALL_TEX["#"])
	var m := ShaderMaterial.new()
	m.shader = _shader()
	m.set_shader_parameter("min_a", MIN_A)
	m.set_shader_parameter("fade_m", FADE_M)
	m.set_shader_parameter("world_uv", true)
	m.set_shader_parameter("uv_per_m", float(spec[1]))
	m.set_shader_parameter("ambient_k", 0.5)
	var dir := Level3D.PBR_DIR + String(spec[0])
	m.set_shader_parameter("albedo_tex", _tex(dir + "_albedo.png"))
	m.set_shader_parameter("arm_tex", _tex(dir + "_orm.png"))
	m.set_shader_parameter("normal_tex", _tex(dir + "_normal.png"))
	var gp := Level3D.PBR_DIR + "grime_%s.png" % String(spec[2])
	if ResourceLoader.exists(gp) and not "--nograime" in OS.get_cmdline_user_args():
		m.set_shader_parameter("grime_tex", _tex(gp))
		m.set_shader_parameter("grime_a", float(Level3D.GRIME_ALPHA.get(String(spec[2]), 1.0)))
	_wall_mats[key] = m
	return m


## Ściany przekroju (`Level3D.shell_walls`) od DEPTH_FRONT do SHELL_Z: poziome ciągi kafli o tym samym materiale i `occ` jako jedna skrzynka,
## jeden MultiMesh na parę (materiał, occ). Warstwa pierwszego planu (wygaszanie na sylwetkach graczy i wrogów), bez cienia; poza `_root`,
## więc ustawienie „Foreground” OFF ich nie chowa (to bryła budynku, nie dekoracja). Zwraca liczbę skrzynek.
static func build_walls(parent: Node3D) -> int:
	if Level3D.shell_walls.is_empty():
		return 0
	var T := Level3D.T
	var d := Level3D.SHELL_Z - Level3D.DEPTH_FRONT
	var groups := {}                                         # "occ|klucz" → {wiersz: [kolumny]}
	var occs := {}
	for k: Vector2i in Level3D.shell_walls:
		var v: Array = Level3D.shell_walls[k]
		var key := String(v[0]) if WALL_TEX.has(String(v[0])) else "#"
		var gk := "%s|%s" % [str(v[1]), key]
		occs[gk] = v[1]
		if not groups.has(gk):
			groups[gk] = {}
		var g: Dictionary = groups[gk]
		if not g.has(k.y):
			g[k.y] = []
		(g[k.y] as Array).append(k.x)
	var box := BoxMesh.new()
	box.size = Vector3(T, T, d)
	var n_boxes := 0
	for gk: String in groups:
		var xfs := []
		var g: Dictionary = groups[gk]
		for r: int in g:
			var cs: Array = g[r]
			cs.sort()
			var i := 0
			while i < cs.size():
				var j := i
				while j + 1 < cs.size() and int(cs[j + 1]) == int(cs[j]) + 1:
					j += 1
				var n := j - i + 1
				var ctr := (Level3D.cell_pos(int(cs[i]), r) + Level3D.cell_pos(int(cs[j]), r)) * 0.5
				xfs.append(Transform3D(Basis().scaled(Vector3(float(n), 1.0, 1.0)), Vector3(ctr.x, ctr.y, Level3D.DEPTH_FRONT + d * 0.5)))
				i = j + 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "ShellWalls"
		mi.multimesh = mm
		mi.material_override = wall_material(gk.get_slice("|", 1))
		mi.layers = LAYER_WALL
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.set_instance_shader_parameter("occ", occs[gk])
		parent.add_child(mi)
		n_boxes += xfs.size()
	return n_boxes
