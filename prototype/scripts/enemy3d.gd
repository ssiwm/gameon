extends Node3D
## Wróg jako prawdziwy model 3D w widoku 3D (view3d.gd). Model to rig Tripo z `tools/prep_enemy3d.py` (art/enemy3d/<rodzaj>.glb); pozę liczymy
## co klatkę z nazwy animacji 2D (sleep / idle / walk / run / windup), tak jak arkusze HD były wypiekane w `concept/monster_tripo_bake.py` —
## te same pozy (kąty tułowia, kroki, ręce), tylko w czasie rzeczywistym na szkielecie Mixamo (dwukostkowe IK jak w `char3d.gd`).
## Trzosek (czworonóg) odtwarza animację chodu z pliku, reszta póz to skalowanie. Oczy (żółto-pomarańczowe piksele tekstury) świecą emisją.
##
## Układ: Enemy3D (pozycja stóp, skala.x = ±1 odbicie) → pivot (skala dopasowana do rozmiaru sprite'a 2D) → model.
## Model w układzie Godota: +X to przód, Y w górę, Z do kamery (blenderowe −Y); stąd przeliczenia osi względem skryptu wypieku.

const TURN_TIME := 0.16                      ## s: obrót przy zmianie kierunku (jak Char3D.TURN_TIME)
const BODY_YAW := -22.0                      ## °: tułów zwrócony ku kamerze (jak Char3D.BODY_YAW)
const CharClips := preload("res://scripts/char_clips.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")
const Motion := preload("res://scripts/enemy_motion.gd")
const DIR := "res://art/enemy3d/"
const PRE := "mixamorig_"
const PX := 1.8 / 22.0                     ## metrów na piksel świata (jak Level3D.PX)

## fit: [„height" | „length", rozmiar w pikselach świata] — jak w wypieku; frame_h: wysokość ramki sprite'a (Skoczek wisi u jej góry);
## cycle: okres cyklu kroku (s); prof: profil pozy (jak PROF w wypieku); yaw: obrót modelu (stopnie), by przód patrzył w +X.
## walk_clip: zestaw klipów chodu z char_clips.gd — „zombie" (powłóczysty krok) albo „human" (zwykły chód: Mimik udaje człowieka);
## bez tego klucza rodzaj chodzi pozą z kodu. attack_clip: zapowiedź i cios z klipu (zestaw musi je mieć), ręce wtedy z klipu.
const SPEC := {
	# Cykl 0.5 s: dwie długości kroku z retargetowanego klipu / prędkość z DEFS.
	# Przy cyklu 1 s ciało przemieszczało się dwa razy szybciej niż podparcie nóg.
	"wolek": {"fit": ["height", 32.0], "frame_h": 44.0, "cycle": 0.5, "prof": {"lean": 1.0, "lean_walk": 4.0}, "body_motion": true, "walk_clip": "zombie", "clips": true, "clip_amp": 0.6, "stun": true},
	# Rzeźnik (F4e): model z TRELLIS-a z osobnym tasakiem przypiętym do prawej dłoni (`tools/rig_trellis.py`, art/enemy3d/rzeznik.glb)
	"rzeznik": {"fit": ["height", 44.0], "frame_h": 58.0, "cycle": 0.5, "prof": {"windup": "cleave", "lean": 2.0, "lean_walk": 5.0}, "body_motion": true, "walk_clip": "human", "eye_glow": 0.0, "attack_kind": "cleave", "clips": true, "clip_amp": 0.6, "stun": true},
	"slepiec": {"fit": ["height", 27.0], "frame_h": 32.0, "cycle": 1.0, "prof": {"hy": 0.50, "hz": 0.35, "windup": "claw"}, "clips": true, "attack_kind": "claw", "walk_clip": "zombie",
		"death": {"dir": 1.0, "lean": -8.0, "dur": 0.95, "tilt": 86.0}},
	"podsluchacz": {"fit": ["height", 34.0], "frame_h": 40.0, "cycle": 1.0,
		"prof": {"lean": 4.0, "lean_walk": 6.0, "hy": 0.42, "hz": 0.55, "sleep_lean": 14.0, "windup": "point"}, "clips": true, "attack_kind": "scream", "walk_clip": "zombie",
		"death": {"dir": 1.0, "lean": -4.0, "dur": 1.0, "tilt": 88.0}},
	# Kapłan (F4e): model z TRELLIS-a szkieletowany `tools/rig_trellis.py` (art/enemy3d/kaplan.glb); poza i klipy jak u Podsłuchacza
	"kaplan": {"fit": ["height", 44.0], "frame_h": 52.0, "cycle": 1.0,
		"prof": {"lean": 4.0, "lean_walk": 6.0, "hy": 0.42, "hz": 0.55, "sleep_lean": 14.0, "windup": "point"}, "clips": true, "attack_kind": "scream", "walk_clip": "zombie",
		"death": {"dir": 1.0, "lean": -4.0, "dur": 1.0, "tilt": 88.0}},
	"stalker": {"fit": ["height", 54.0], "frame_h": 60.0, "cycle": 1.1,
		"prof": {"lean": 5.0, "lean_walk": 8.0, "hy": 0.42, "hz": 0.62, "stride": 0.28, "windup": "reach"}, "clips": true, "attack_kind": "grab", "walk_clip": "zombie",
		"death": {"dir": 1.0, "lean": 0.0, "dur": 1.0, "tilt": 88.0}},
	"skoczek": {"fit": ["height", 17.0], "frame_h": 26.0, "cycle": 0.5, "crawler": true, "clips": true},
	# Żerca (F4e): model z TRELLIS-a szkieletowany `tools/rig_trellis.py` (art/enemy3d/zerca.glb)
	"zerca": {"fit": ["height", 30.0], "frame_h": 40.0, "cycle": 0.5, "crawler": true, "clips": true},
	"trzosek": {"fit": ["length", 21.0], "frame_h": 22.0, "cycle": 0.55, "quad": true, "yaw": -90.0, "clips": true, "idle_t": 0.0},
	# Mimik to model gracza z kolorem „kolegi” i świecącymi oczami; pozostałe poniżej to modele statyczne animowane deformacją wierzchołków w shaderze
	# (`DEFORM`), tak jak wypiek `concept/static_tripo_bake.py` — poza z numeru klatki sprite'a 2D (animacja idzie w tempie gry).
	"mimik": {"model": "res://art/char3d/mpfb/male_scav.glb", "eye_off": [0.12, 0.095, 0.033], "fit": ["height", 22.0], "fit_mesh": "body", "frame_h": 28.0, "cycle": 0.8, "eyes": true, "turn": true,
		"prof": {"lean": 3.0, "lean_walk": 7.0, "hy": 0.21, "hz": 0.80, "stride": 0.24, "windup": "reach", "sleep_lean": 3.0}, "clips": true, "attack_kind": "grab", "walk_clip": "human",
		"death": {"dir": 1.0, "lean": 8.0, "dur": 1.2, "tilt": 84.0}},
	"cma": {"fit": ["width", 18.0], "frame_h": 20.0, "deform": "cma", "float": true, "clips": true, "death_dur": 0.9},
	"nest": {"fit": ["height", 30.0], "frame_h": 34.0, "deform": "nest", "clips": true, "death_dur": 0.6},
	"vein": {"fit": ["height", 66.0], "frame_h": 80.0, "deform": "vein", "clips": true, "death_dur": 1.8},
	"leech": {"fit": ["height", 66.0], "frame_h": 80.0, "deform": "leech", "death_dur": 1.4},
}

## Materiał: kolor + normalne + ORM z modelu, bez metaliczności; oczy świecą (maska jak `pack_monsters_hd.py::glow_mask`);
## `mod` to modulate sprite'a 2D (błysk trafienia, zapowiedź ataku, przygaszenie śpiącego, przezroczystość Stalkera).
const SHADER := """
shader_type spatial;
//RENDER
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float metallic_factor = 0.0;
uniform float normal_strength = 1.0;
uniform vec4 mod = vec4(1.0);
uniform float eye_glow = 1.4;
uniform float sil = 0.06;              // słaba, chłodna sylwetka widoczna w całkowitej ciemności (jak warstwa `Silhouette` arkuszy HD w 2D)
//VERTEX
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		TANGENT = -TANGENT;
		BINORMAL = -BINORMAL;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	float eye = smoothstep(0.05, 0.075, h.x) * (1.0 - smoothstep(0.17, 0.2, h.x)) * smoothstep(0.55, 0.68, h.y) * smoothstep(0.5, 0.65, h.z);
	ALBEDO = c * clamp(mod.rgb, 0.0, 1.0);
	EMISSION = c * eye * eye_glow + max(mod.rgb - vec3(1.0), vec3(0.0)) * 0.28 + c * vec3(0.55, 0.70, 1.0) * sil;
	//ALPHA
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).xyz;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	if (has_orm) {
		vec4 o = texture(orm_tex, UV);
		AO = o.r;
		ROUGHNESS = o.g;
		METALLIC = o.b * metallic_factor;
	} else {
		ROUGHNESS = 0.85;
		METALLIC = metallic_factor;
	}
}
"""

## Deformacje wierzchołków (modele statyczne). Współrzędne liczone jak w wypieku Blendera: b = (x przód, y bok, z góra) = (VERTEX.x, −VERTEX.z, VERTEX.y);
## model jest ustawiony przez `prep_enemy3d.py` jak w wypieku (obrót, stopy na z = 0, środek w x, y).
const DEFORM := {
	"cma": """
uniform float wing = 0.0;               // kąt machnięcia (°): skrzydła po obu stronach wychylają się w przeciwne strony wokół pionu
void vertex() {
	vec3 b = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	float w = smoothstep(0.012, 0.045, abs(b.y));
	float a = radians(wing) * w * (b.y > 0.0 ? 1.0 : -1.0);
	float c = cos(a);
	float s = sin(a);
	float hinge = 0.025 * sign(b.y);
	float span = b.y - hinge;
	b = vec3(b.x, hinge + span * c - b.z * s, span * s + b.z * c);
	VERTEX = vec3(b.x, b.z, -b.y);
	vec3 n = vec3(NORMAL.x, -NORMAL.z, NORMAL.y);
	n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
	NORMAL = normalize(vec3(n.x, n.z, -n.y));
	vec3 t = vec3(TANGENT.x, -TANGENT.z, TANGENT.y);
	t = vec3(t.x, t.y * c - t.z * s, t.y * s + t.z * c);
	TANGENT = normalize(vec3(t.x, t.z, -t.y));
	vec3 bn = vec3(BINORMAL.x, -BINORMAL.z, BINORMAL.y);
	bn = vec3(bn.x, bn.y * c - bn.z * s, bn.y * s + bn.z * c);
	BINORMAL = normalize(vec3(bn.x, bn.z, -bn.y));
}
""",
	"nest": """
uniform float pulse = 0.0;              // −1..1: puls gniazda (przekrój ±4%, wysokość ±6%)
void vertex() {
	vec3 b = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	b = vec3(b.x * (1.0 + 0.04 * pulse), b.y * (1.0 + 0.04 * pulse), b.z * (1.0 + 0.06 * pulse));
	VERTEX = vec3(b.x, b.z, -b.y);
}
""",
	"vein": """
uniform float jaw = -1.0;               // < 0: szczęka zamknięta (kły się zazębiają), > 0: otwarta (słaby punkt bossa)
uniform vec2 sxz = vec2(1.0, 1.0);      // skala przekroju i wysokości
void vertex() {
	vec3 b = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	float oy = 0.0;
	float dz = 0.0;
	if (b.y < 0.05) {
		float wl = exp(-(pow(b.x / 0.14, 2.0) + pow((b.z - 0.585) / 0.075, 2.0)));
		float wu = exp(-(pow(b.x / 0.14, 2.0) + pow((b.z - 0.70) / 0.05, 2.0)));
		if (jaw >= 0.0) {
			dz = -0.085 * wl * jaw + 0.020 * wu * jaw;
			oy = -0.03 * wl * jaw;
		} else {
			dz = 0.052 * wl * -jaw - 0.022 * wu * -jaw;
		}
	}
	b = vec3(b.x * sxz.x, b.y * sxz.x + oy, (b.z + dz) * sxz.y);
	VERTEX = vec3(b.x, b.z, -b.y);
}
""",
	"leech": """
uniform vec4 p0 = vec4(-50.0, 0.0, 0.0, 1.0);    // yaw (°), bend (rad), dz (ułamek H), sz
uniform vec4 p1 = vec4(0.0, 0.0, 0.0, 0.0);      // close, wide, amp, ph
uniform vec3 p2 = vec3(0.0, 0.0, 0.0);           // shake (m), headtilt (rad), ox (m)
uniform float H = 0.35;
const float SPINE[21] = float[21](0.059, 0.031, 0.030, 0.014, -0.021, -0.027, -0.041, -0.066, -0.058, -0.049, -0.043, -0.027, -0.014, 0.000, 0.006, 0.017, 0.008, 0.022, 0.032, 0.046, 0.053);
float spine_x(float t) {
	float f = clamp(t, 0.0, 1.0) * 20.0;
	int k = min(int(f), 19);
	return mix(SPINE[k], SPINE[k + 1], f - float(k));
}
void vertex() {
	vec3 b = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	float x = b.x;
	float y = b.y;
	float z = b.z;
	float t = clamp(z / H, 0.0, 1.0);
	float R = 0.058;
	float mz = 0.78 * H;
	float d = length(vec2(y, z - mz));
	float w = (1.0 - smoothstep(0.8 * R, 1.7 * R, d)) * smoothstep(0.0, 0.05, x);
	float f = 1.0 - 0.85 * p1.x * w + 0.55 * p1.y * w;
	y = y * f;
	z = mz + (z - mz) * f;
	float c = spine_x(t);
	float s = 1.0 + p1.z * sin(6.28318 * 2.2 * t - p1.w);
	x = c + (x - c) * s;
	y *= s;
	z *= p0.w;
	float k = 1.0 / sqrt(p0.w);
	x = c + (x - c) * k;
	y *= k;
	float tt = clamp((z / H - 0.1) / 0.9, 0.0, 1.0);
	float a = p0.y * pow(tt, 1.3) + p2.y * smoothstep(0.55, 0.95, t);
	float px = spine_x(0.1);
	float pz = 0.10 * H;
	float dx = x - px;
	float dzz = z - pz;
	x = px + dx * cos(a) + dzz * sin(a);
	z = pz - dx * sin(a) + dzz * cos(a);
	y += p2.x * t * t;
	z += p0.z * H;
	float yw = radians(p0.x);
	float cy = cos(yw);
	float sy = sin(yw);
	b = vec3(x * cy - y * sy + p2.z, x * sy + y * cy, z);
	VERTEX = vec3(b.x, b.z, -b.y);
}
""",
}

var kind := ""
var ok := false
var _spec: Dictionary = {}
var _pivot: Node3D
var _model: Node3D
var _sk: Skeleton3D
var _mesh: MeshInstance3D
var _ap: AnimationPlayer
var _ap_name := ""
var _mats: Array = []
var _b := {}                               ## nazwa kości (bez przedrostka) → indeks
var _leg_len := {}
var _arm_len := {}
var _x0 := 0.0                             ## oś ciała (m, układ modelu)
var _scale := 1.0
var _t := 0.0
var _face := 1.0                             ## −1..1: zwrot w trakcie obrotu (SPEC „turn": Mimik), jak Char3D._face
var _cam_c := 1.0                            ## −1..1: strona kamery względem modelu (znak zwrotu tułowia ku kamerze)
var _phase := 0.0
var _prev_anim := ""
var _foot_locks: Dictionary = {}
var _last_position := Vector3.ZERO
var _last_flip := false
var ground_profile: Dictionary = {}
var _motion_name := ""
var _motion_pending := ""
var _motion_weight := 0.0
var _motion_time := 0.0
var _motion_wind_clock := 0.0
var _motion_remaining := NAN
var _motion_duration := 0.0
var _motion_values: Dictionary = {}
var _contact_frame := false
var _grounded_hint := -1
var _target_world_y := NAN
var _landing_t := 10.0
var _landing_strength := 0.0
var _q_limbs: Dictionary = {}
var _sole_points: Dictionary = {}
var _sole_samples: Dictionary = {}
var _ground_cache: Dictionary = {}
static var _sole_cache: Dictionary = {}

## Migawka zapowiedzi z symulacji. Zegar modelu nie rozstrzyga trafień.
func motion_context(info: Dictionary) -> void:
	_grounded_hint = int(bool(info["grounded"])) if info.has("grounded") else -1
	_target_world_y = -float(info.get("target_y", NAN)) * PX
	_motion_remaining = float(info.get("windup_remaining", NAN)) if bool(info.get("winding", false)) else NAN
	_motion_duration = float(info.get("windup_duration", 0.0))
	if bool(info.get("winding", false)):
		_motion_pending = String(info.get("motion_action", Motion.action(kind)))

func clip_duration(clip: String) -> float:
	return Motion.recovery(_motion_name) if clip == "attack" and _motion_name != "" else float(CLIP_DUR.get(clip, 0.42))

func motion_phase() -> String:
	if _dead or _motion_weight < 0.001: return "idle"
	if _clip == "attack": return "contact" if _clip_t <= 0.0001 else "recovery"
	return "anticipation" if _prev_anim == "windup" else "cancelled"

func _advance_motion(delta: float, anim: String) -> void:
	var active := false
	if anim == "windup" and not _dead and _clip not in ["hit", "attack"]:
		_motion_wind_clock += delta
		_motion_name = _motion_pending if _motion_pending != "" else Motion.action(kind)
		var contact := Motion.contact(_motion_name)
		_motion_time = contact * clampf(1.0 - _motion_remaining / maxf(_motion_duration, 0.001), 0.0, 0.999) if is_finite(_motion_remaining) else minf(_motion_wind_clock, contact * 0.999)
		active = _motion_name != ""
	elif _clip == "attack" and not _dead:
		_motion_time = Motion.contact(_motion_name) + _clip_t
		active = _motion_name != ""
	else:
		_motion_wind_clock = 0.0
	_motion_weight = move_toward(_motion_weight, 1.0 if active and clips_on else 0.0, delta * 12.0)
	_motion_values = Motion.sample(_motion_name, _motion_time) if _motion_weight > 0.001 else {}

func _authored_biped(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var height := _sk.get_bone_global_rest(_b["Hips"]).origin.y
	for channel in _motion_values:
		var key: String = "hk" if channel == "head" else String(channel)
		if not out.has(key): continue
		var value = _motion_values[channel]
		if key in ["hR", "hL"]: value = Vector3(_x0, 0, 0) + (value as Vector3) * height
		elif key in ["drop", "fR", "fL", "shift", "sway"]: value *= height
		out[key] = lerp(out[key], value, _motion_weight)
	if kind == "stalker" and _motion_name == "grab":
		var progress := _motion_time / maxf(Motion.contact("grab"), 0.001)
		var reach := smoothstep(0.05, 0.9, progress)
		if progress > 1.0: reach *= 1.0 - smoothstep(0.35, 1.0, (progress - 1.0) * Motion.contact("grab") / Motion.recovery("grab"))
		reach *= _motion_weight
		var world_y := _target_world_y if is_finite(_target_world_y) else global_position.y + 1.2
		var target := _sk.global_transform.affine_inverse() * Vector3(global_position.x, world_y, global_position.z)
		var lower := 0.0
		for hand in ["hR", "hL"]:
			var goal: Vector3 = out[hand]
			lower = maxf(lower, maxf(goal.y - target.y, 0.0) * 0.28)
			goal.y = lerpf(goal.y, target.y, reach)
			goal.x = lerpf(goal.x, _x0 + height * 0.50, reach)
			out[hand] = goal
		out["drop"] = float(out["drop"]) + minf(lower, height * 0.28) * reach
		out["lean"] = float(out["lean"]) + 6.0 * reach
	return out

## Punkty próbkowania podłoża; widok pyta fizykę 2D, model nie uruchamia fizyki 3D.
func ground_probes() -> Dictionary:
	var points := {}
	if _sk == null or _spec.has("deform"): return points
	if _spec.get("quad", false):
		for key in _q_limbs:
			points[key] = _sk.global_transform * _gp(_q_limbs[key][4]).origin
		return points
	for side in ["Right", "Left"]:
		points[side] = _sk.global_transform * _gp(_b[side + "Foot"]).origin
		if _spec.get("crawler", false):
			points[side + "Hand"] = _sk.global_transform * _gp(_b[side + "Hand"]).origin
	return points

func _ground_y(side: String) -> float:
	if _ground_cache.has(side): return float(_ground_cache[side])
	var rest := _sk.get_bone_global_rest(_b[side + "Foot"])
	if not _sole_points.has(side):
		return rest.origin.y + float((ground_profile.get(side, {}) as Dictionary).get("height", 0.0)) / _scale
	var point := _sk.global_transform * rest.origin
	point.y = _sole_floor(side, rest.basis)
	var height := (_sk.global_transform.affine_inverse() * point).y
	_ground_cache[side] = height
	return height

## Rzeczywiste punkty skóry łapy, względem kości podporowej; uwzględniają inverse bind,
## także przesunięcie bind pose Trzoska. Obliczane raz na model, nie na klatkę.
func _prepare_soles() -> void:
	if _sole_cache.has(kind):
		_sole_points = _sole_cache[kind][0]
		_sole_samples = _sole_cache[kind][1]
		return
	var anchors := {}
	if _spec.get("quad", false):
		for key in _q_limbs: anchors[key] = _q_limbs[key][3]
	elif not _spec.get("crawler", false) and _b.has("RightFoot"):
		for side in ["Right", "Left"]: anchors[side] = _b[side + "Foot"]
	if anchors.is_empty(): return
	var clouds := {}
	var skin_clouds := {}
	for key in anchors: clouds[key] = []
	for key in anchors: skin_clouds[key] = []
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or mi.mesh == null: continue
		var xf := _transform_under(_sk, _model).affine_inverse() * _transform_under(mi, _model)
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES] == null: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var support := {}
				var skin_sample := []
				for slot in per:
					var index := vertex * per + slot
					var weight := weights[index]
					if weight < 0.0001: continue
					var bone := mi.skin.get_bind_bone(bones[index])
					if bone < 0: bone = _sk.find_bone(mi.skin.get_bind_name(bones[index]))
					if bone < 0: continue
					point += _sk.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bones[index]) * (xf * vertices[vertex]) * weight
					skin_sample.append([bone, mi.skin.get_bind_pose(bones[index]) * (xf * vertices[vertex]), weight])
					var name := String(_sk.get_bone_name(bone))
					for key in anchors:
						var match_foot: bool = (name.begins_with(key) and (name.ends_with("Limb_3") or name.ends_with("Limb_4"))) if _spec.get("quad", false) else (key in name and ("Foot" in name or "Toe" in name))
						if match_foot: support[key] = float(support.get(key, 0.0)) + weight
				for key in support:
					if support[key] >= 0.4:
						clouds[key].append(_sk.get_bone_global_rest(anchors[key]).affine_inverse() * point)
						skin_clouds[key].append(skin_sample)
	# Otoczka z 26 skrajnych punktów zachowuje palce i piętę bez kosztu całej siatki.
	for key in clouds:
		if (clouds[key] as Array).is_empty(): continue
		var points := []
		var samples := []
		var selected := []
		for x in [-1.0, 0.0, 1.0]:
			for y in [-1.0, 0.0, 1.0]:
				for z in [-1.0, 0.0, 1.0]:
					var direction := Vector3(x, y, z)
					if direction == Vector3.ZERO: continue
					var best: Vector3 = clouds[key][0]
					var best_index := 0
					for index in (clouds[key] as Array).size():
						var point: Vector3 = clouds[key][index]
						if point.dot(direction) > best.dot(direction):
							best = point
							best_index = index
					if not best in points:
						points.append(best)
						samples.append(skin_clouds[key][best_index])
						selected.append(best_index)
		# Dolna powierzchnia zawiera też punkty o mieszanych wagach piszczeli i palców.
		# Po zgięciu nogi skrajny punkt skóry nie musi być skrajnym punktem rest pose.
		var bottom := range((clouds[key] as Array).size())
		var rest_basis := _sk.get_bone_global_rest(anchors[key]).basis
		bottom.sort_custom(func(a: int, b: int) -> bool: return (rest_basis * (clouds[key][a] as Vector3)).y < (rest_basis * (clouds[key][b] as Vector3)).y)
		# Gęste UV dają wiele kopii tego samego punktu. Limit dotyczy
		# pozycji geometrycznych, aby 64 próbki obejmowały całą podeszwę.
		var bottom_positions: Dictionary = {}
		for index in bottom:
			var position_key := Vector3i(((clouds[key][index] as Vector3) * 100000.0).round())
			if bottom_positions.has(position_key): continue
			bottom_positions[position_key] = true
			if not index in selected:
				samples.append(skin_clouds[key][index])
				selected.append(index)
			if bottom_positions.size() >= 64: break
		if bool(_spec.get("body_motion", false)):
			# Mieszane wagi mogą obniżyć środek podeszwy, a nie jej punkt
			# najniższy w rest pose. Próba na siatce 8x8 pokrywa piętę i palce.
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			var projected: Array[Vector3] = []
			for point in clouds[key]:
				var pos: Vector3 = rest_basis * (point as Vector3)
				projected.append(pos)
				low = low.min(Vector2(pos.x, pos.z))
				high = high.max(Vector2(pos.x, pos.z))
			var span := (high - low).max(Vector2(0.0001, 0.0001))
			var grid: Dictionary = {}
			for index in projected.size():
				var pos := projected[index]
				var at := Vector2i(clampi(int((pos.x - low.x) / span.x * 8.0), 0, 7), clampi(int((pos.z - low.y) / span.y * 8.0), 0, 7))
				if not grid.has(at) or pos.y < projected[int(grid[at])].y: grid[at] = index
			for index in grid.values():
				if not int(index) in selected:
					samples.append(skin_clouds[key][int(index)])
		_sole_points[key] = points
		_sole_samples[key] = samples
	_sole_cache[kind] = [_sole_points, _sole_samples]

func _sole_floor(key: String, foot_basis: Basis) -> float:
	var offset := 0.0
	var first := true
	var basis := _sk.global_transform.basis * foot_basis
	for point in _sole_points.get(key, []):
		var height := (basis * (point as Vector3)).y
		if first or height < offset: offset = height
		first = false
	return global_position.y + float((ground_profile.get(key, {}) as Dictionary).get("height", 0.0)) - offset + 0.003

## Mała próbka faktycznie skinned wierzchołków wykrywa wpływ piszczeli/palców,
## którego nie opisuje sztywna otoczka kości stopy. Nie modyfikujemy wag ani długości kości.
func _sole_penetration(key: String) -> float:
	var lowest := INF
	var poses := {}
	var transform := _sk.global_transform
	for sample in _sole_samples.get(key, []):
		var point := Vector3.ZERO
		for influence in sample:
			var bone: int = influence[0]
			if not poses.has(bone): poses[bone] = _gp(bone)
			point += (poses[bone] as Transform3D) * (influence[1] as Vector3) * float(influence[2])
		lowest = minf(lowest, (transform * point).y)
	if not is_finite(lowest): return 0.0
	return clampf(global_position.y + float((ground_profile.get(key, {}) as Dictionary).get("height", 0.0)) + 0.003 - lowest, 0.0, 0.12)

## Działa również podczas setup() przed wejściem modelu do drzewa.
static func _transform_under(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result
var _eyes: Array = []

## Klipy jednorazowe i śmierć (modele z `"clips": true` w SPEC): trafienie, atak, śmierć; poza bazowa przechodzi płynnie (wagi), klip leży na wierzchu.
const CLIP_DUR := {"hit": 0.32, "attack": 0.42}
const DEATH_DUR := {"biped": 1.15, "quad": 0.85}
const CORPSE_HOLD := 0.35                  ## s leżenia po upadku
const CORPSE_SINK := 0.45                  ## s zapadania się w ziemię, potem model znika
const BLEND_RATE := 9.0                    ## 1/s: tempo przechodzenia między pozami bazowymi

var _tilt: Node3D                          ## przechył całego ciała (upadek) wokół stóp
var _w := {}                               ## wagi póz bazowych (idle / walk / windup / sleep)
var _clip := ""
var _clip_t := 0.0
var _dead := false
var _dead_t := 0.0
var _dead_from := {}                       ## poza w chwili śmierci (płynne wejście w upadek)
var finished := false                      ## martwy i po animacji — można ukryć
var _qsamp := {}                           ## próbki animacji czworonoga: nazwa → [rotacje, pozycje]
var _eye_w := 0.0                          ## waga rozżarzenia oczu przy zapowiedzi ciosu 0..1
var _qs := 0.0                             ## waga siadu czworonoga 0..1 (idle = siedzi i czeka)
var _qw := 0.0                             ## waga biegu czworonoga 0..1
var _spine: Array = []                     ## kości kręgosłupa czworonoga
var _last_p := {}                          ## ostatnia poza bazowa biped (po wagach)
var _air_w := 0.0                          ## 0..1 waga pozy skoku / spadania (prędkość pionowa wroga z view3d.gd)
var _air_vy := 0.0                         ## px/s (+ = w dół)
var _airborne := false
var _sp := 0                               ## stan specjalny wroga z gry (Wołek: 1 zapowiedź szarży, 2 szarża, 3 zapowiedź rzutu, 4 oszołomiony)
var _inv_w := 0.0                          ## 0..1 odwrócenia do góry nogami (wiszący Skoczek / śpiąca Ćma): płynny obrót przy budzeniu
var _model_h := 1.0                        ## wysokość modelu w spoczynku (m, natywna skala)
## Klipy animacji (char_clips.gd): chód dwunożnych — biodra i nogi z klipu, postawa i ręce dalej z profilu rodzaju.
var clips_on := true                       ## false = same pozy z kodu (porównania w tools/shot_enemy_clip3d.gd)
var walk_set := ""                         ## zestaw klipów wymuszony przed setup() (porównania); pusty = `walk_clip` ze SPEC
var _cset := ""                            ## zestaw klipów tego wroga
var _tree: AnimationTree
var _ck := 0.0                             ## 0..1 udział klipów w stanach, które je mają (gaśnie po śmierci)
var _cwalk := 0.0                          ## 0..1 łączna waga klipów w tej klatce (stopy i kolana z klipu)
var _carm := 0.0                           ## 0..1 waga stanów, w których ręce idą z klipu (zapowiedź i cios)
var _catt := false                         ## rodzaj ma zapowiedź i cios z klipu
var _windup_t := 0.0                       ## s od wejścia w zapowiedź ciosu (czas klipu)
var _chand := {}                           ## strona → pozycja dłoni z klipu (przestrzeń szkieletu)
var _cw := {}                              ## stan → waga (wejście dla CharClips.drive)
var _cprog := {}
var _cfoot := {}                           ## strona → Transform3D stopy z klipu (przestrzeń szkieletu)
var _cknee := {}                           ## strona → kierunek kolana w klipie (biegun IK nogi)
var _crise := 0.0                          ## o tyle biodra stoją wyżej niż w klipie (jednostki modelu)
var _chips := Vector3.ZERO                 ## przesunięcie bioder z klipu względem spoczynku — ręce idą za ciałem

static func has_model(k: String) -> bool:
	return SPEC.has(k) and ResourceLoader.exists(String((SPEC[k] as Dictionary).get("model", DIR + k + ".glb")))

## Buduje model. translucent: materiał z przezroczystością (Stalker znika bez światła).
func setup(k: String, translucent := false) -> bool:
	kind = k
	_spec = SPEC.get(k, {})
	if _spec.is_empty():
		return false
	var ps := load(String(_spec.get("model", DIR + k + ".glb"))) as PackedScene
	if ps == null:
		return false
	_tilt = Node3D.new()
	add_child(_tilt)
	_pivot = Node3D.new()
	_tilt.add_child(_pivot)
	_model = ps.instantiate() as Node3D
	_pivot.add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	var mis := _model.find_children("*", "MeshInstance3D", true, false)
	var deform := String(_spec.get("deform", ""))
	if mis.is_empty() or (sks.is_empty() and deform == ""):
		return false
	_sk = sks[0] if not sks.is_empty() else null
	_mesh = mis[0]
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0]
	# skala: rozmiar modelu w spoczynku → rozmiar sprite'a 2D (jak w wypieku)
	var bb := _mesh.get_aabb()
	var fit_name := String(_spec.get("fit_mesh", ""))
	if fit_name != "":
		# model gracza (Mimik) ma osobne siatki ekwipunku (plecak, kamizelka…) i `mis[0]` to nie ciało: skala dopasowana do plecaka powiększała postać ok. 3×
		for m in mis:
			if String(m.name) == fit_name:
				bb = (m as MeshInstance3D).get_aabb()
				break
	var fit: Array = _spec["fit"]
	var ext := bb.size.y
	if String(fit[0]) == "length":
		ext = maxf(bb.size.x, bb.size.z)
	elif String(fit[0]) == "width":
		ext = bb.size.x
	_model_h = bb.size.y
	_scale = float(fit[1]) * PX / maxf(ext, 0.001)
	_pivot.scale = Vector3.ONE * _scale
	var yaw := deg_to_rad(float(_spec.get("yaw", 0.0)))
	_pivot.rotation.y = yaw
	var c := bb.get_center()
	var hc := Basis(Vector3.UP, yaw) * c
	if _spec.get("quad", false) or _spec.get("crawler", false):
		_pivot.position = Vector3(-hc.x * _scale, 0.0, -hc.z * _scale)
	if deform == "" and not _spec.get("quad", false):
		for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
				"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
			var i := _sk.find_bone(PRE + n)
			if i < 0:
				return false
			_b[n] = i
		for side in ["Left", "Right"]:
			_leg_len[side] = [_rest_dist(side + "UpLeg", side + "Leg"), _rest_dist(side + "Leg", side + "Foot")]
			_arm_len[side] = [_rest_dist(side + "Arm", side + "ForeArm"), _rest_dist(side + "ForeArm", side + "Hand")]
			var shoulder := _sk.find_bone(PRE + side + "Shoulder")
			if shoulder >= 0: _b[side + "Shoulder"] = shoulder
		var hips_x := _sk.get_bone_global_rest(_b["Hips"]).origin.x
		_x0 = hips_x - 0.05
		if _spec.get("crawler", false):
			_x0 = c.x
		else:
			_cset = walk_set if walk_set != "" else String(_spec.get("walk_clip", ""))
			if _cset != "":
				_tree = CharClips.build(_sk, k, false, _cset)
				if _tree != null:
					_sk.get_parent().add_child(_tree)
					_catt = bool(_spec.get("attack_clip", false)) and CharClips.has("attack", _cset) and CharClips.has("windup", _cset)
		_pivot.position.x = -_x0 * _scale
	if _spec.get("quad", false):
		for n in ["tripo__Spine_0", "tripo__Spine_1", "tripo__Spine_2", "tripo__Spine_3"]:
			var bi := _sk.find_bone(n)
			if bi >= 0:
				_spine.append(bi)
	_prepare_materials(translucent)
	if _spec.get("quad", false):
		for pre in ["tripo__0_Left", "tripo__0_Right", "tripo__1_Left", "tripo__1_Right"]:
			var chain := []
			for segment in 5: chain.append(_sk.find_bone(pre + "_Limb_" + str(segment)))
			if not -1 in chain: _q_limbs[pre] = chain
	_prepare_soles()
	if _spec.get("eyes", false):
		for sd in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.012
			sph.height = 0.024
			sph.radial_segments = 8
			sph.rings = 4
			mi.mesh = sph
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.albedo_color = Color(1.0, 0.8, 0.25)
			mi.material_override = em
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("side", sd)
			_model.add_child(mi)
			_eyes.append(mi)
	return true

func _rest_dist(a: String, b: String) -> float:
	return _sk.get_bone_global_rest(_b[a]).origin.distance_to(_sk.get_bone_global_rest(_b[b]).origin)

func _prepare_materials(translucent: bool) -> void:
	var code := SHADER
	code = code.replace("//VERTEX", String(DEFORM.get(String(_spec.get("deform", "")), "")))
	code = code.replace("//ALPHA", "ALPHA = clamp(mod.a, 0.0, 1.0);" if translucent else "")
	var shaders: Dictionary = {}
	for i in _mesh.mesh.get_surface_count():
		var src := _mesh.mesh.surface_get_material(i)
		var cull := BaseMaterial3D.CULL_BACK
		if src is StandardMaterial3D: cull = (src as StandardMaterial3D).cull_mode
		if not shaders.has(cull):
			var modes: Array[String] = []
			if translucent: modes.append_array(["blend_mix", "depth_prepass_alpha"])
			if cull == BaseMaterial3D.CULL_DISABLED: modes.append("cull_disabled")
			elif cull == BaseMaterial3D.CULL_FRONT: modes.append("cull_front")
			var sh := Shader.new()
			sh.code = code.replace("//RENDER", "render_mode " + ", ".join(modes) + ";" if not modes.is_empty() else "")
			shaders[cull] = sh
		var sm := ShaderMaterial.new()
		sm.shader = shaders[cull]
		# Maska HSV jest bezpieczna tylko dla palet z odrębnym kolorem oczu;
		# pomarańczowa skóra Rzeźnika nie może świecić jak jego oczy.
		sm.set_shader_parameter("eye_glow", float(_spec.get("eye_glow", 1.4)))
		if src is StandardMaterial3D:
			var s := src as StandardMaterial3D
			sm.set_shader_parameter("albedo_tex", s.albedo_texture)
			sm.set_shader_parameter("metallic_factor", s.metallic)
			sm.set_shader_parameter("normal_strength", s.normal_scale)
			if s.normal_texture != null:
				sm.set_shader_parameter("normal_tex", s.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			var orm: Texture2D = s.roughness_texture if s.roughness_texture != null else s.ao_texture
			if orm != null:
				sm.set_shader_parameter("orm_tex", orm)
				sm.set_shader_parameter("has_orm", true)
		_mesh.set_surface_override_material(i, sm)
		_mats.append(sm)

# ---------------------------------------------------------------- narzędzia kostne (jak w char3d.gd)

func _gp(i: int) -> Transform3D:
	return _sk.get_bone_global_pose(i)

func _set_global_basis(i: int, gb: Basis) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_rotation(i, (pb.inverse() * gb).orthonormalized().get_rotation_quaternion())

func _move_global(i: int, delta: Vector3) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_position(i, _sk.get_bone_rest(i).origin + pb.inverse() * delta)

## Jak _move_global, ale od bieżącej pozy (po klipie), nie od spoczynku.
func _shift_global(i: int, delta: Vector3) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_position(i, _sk.get_bone_pose_position(i) + pb.inverse() * delta)

func _rot_world(i: int, axis: Vector3, ang: float) -> void:
	_set_global_basis(i, Basis(axis, ang) * _gp(i).basis)

func _point_bone(i: int, child: int, target: Vector3) -> void:
	var g := _gp(i)
	var from := (_gp(child).origin - g.origin).normalized()
	var to := (target - g.origin).normalized()
	if from.dot(to) > 0.99999:
		return
	_set_global_basis(i, Basis(Quaternion(from, to)) * g.basis)

func _two_bone(a: int, m: int, e: int, la: float, lb: float, target: Vector3, pole: Vector3) -> void:
	var s := _gp(a).origin
	var d := target - s
	var dist := clampf(d.length(), absf(la - lb) + 0.001, (la + lb) * 0.999)
	var dn := d.normalized()
	var x := (la * la - lb * lb + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pv := pole - dn * pole.dot(dn)
	pv = pv.normalized() if pv.length() > 0.0001 else Vector3.UP
	var mid := s + dn * x + pv * h
	_point_bone(a, m, mid)
	_point_bone(m, e, s + dn * dist)

# ---------------------------------------------------------------- klatka

## anim: nazwa animacji sprite'a 2D (sleep / idle / walk / run / windup, bossowie: dormant / open / spit / peek / strike / grab / dive / ...).
## flip: sprite odbity (patrzy w lewo). mod: modulate sprite'a. fr: numer klatki + postęp w klatce, nfr: liczba klatek animacji, loop: czy pętla
## (modele statyczne dostają pozę z numeru klatki, żeby animacja szła w tempie gry — np. trafienie Pijawki na klatce 2).
func pose(delta: float, anim: String, flip: bool, mod: Color, fr := 0.0, nfr := 1, loop := true, air_vy := 0.0, sp := 0, alert := false, horizontal_speed := NAN) -> void:
	_ground_cache.clear()
	_t += delta
	if flip != _last_flip or anim != _prev_anim or global_position.distance_to(_last_position) > 0.8:
		_foot_locks.clear()
	_last_flip = flip
	_last_position = global_position
	if not _spec.has("deform"):
		# Mimik udaje gracza, więc odwraca się jak postać gracza (char3d.gd): obrót przodem do kamery w TURN_TIME, tułów zwrócony ku kamerze
		# w obie strony (_apply_biped). Odbicie lustrem w jednej klatce zdradzało go na tle graczy, którzy od 1.7.216 się obracają.
		if not (_clip == "attack" and _clip_t < clip_duration("attack") * 0.25):
			_face = move_toward(_face, -1.0 if flip else 1.0, delta * 2.0 / TURN_TIME) if _t > delta else (-1.0 if flip else 1.0)
		_cam_c = sin(PI * 0.5 * _face)
		scale.x = 1.0
		rotation.y = -PI * 0.5 + PI * 0.5 * _cam_c
	else:
		scale.x = -1.0 if flip else 1.0
	_sp = sp
	var hang: bool = anim == "sleep" and not _dead and (bool(_spec.get("crawler", false)) or String(_spec.get("deform", "")) == "cma")
	_inv_w = move_toward(_inv_w, 1.0 if hang else 0.0, delta / 0.30)
	var was_airborne := _airborne
	var previous_vy := _air_vy
	_air_vy = air_vy
	_airborne = (_grounded_hint == 0 if _grounded_hint >= 0 else absf(air_vy) > 55.0) and not _spec.has("deform") and not _dead and not hang
	if was_airborne and not _airborne and previous_vy > 55.0 and not _dead:
		_landing_t = 0.0
		_landing_strength = clampf(previous_vy / 380.0, 0.2, 1.0)
	else:
		_landing_t += delta
	_air_w = move_toward(_air_w, 1.0 if _airborne else 0.0, delta * 12.0)
	if _dead:
		_dead_t += delta
		var total: float = _death_dur() + CORPSE_HOLD + CORPSE_SINK
		if _dead_t >= total:
			finished = true
	if _clip != "":
		if _clip == "attack" and _contact_frame:
			_contact_frame = false
		else:
			_clip_t += delta
		if _clip_t >= clip_duration(_clip):
			_clip = ""
	var eye_base := float(_spec.get("eye_glow", 1.4))
	var eye := eye_base
	# zapowiedź ciosu: oczy rozżarzają się i pulsują (zamiast czerwienienia całego modelu); po ciosie gasną do zwykłej jasności
	var hot := (anim == "windup" or alert) and not _dead
	_eye_w = move_toward(_eye_w, 1.0 if hot else 0.0, delta * (9.0 if hot else 4.0))
	eye += _eye_w * ((4.2 + 1.4 * sin(_t * 24.0)) if anim == "windup" else 3.0) * (eye_base / 1.4)        # zapowiedź ciosu pulsuje; reakcja „zauważył" (alert) żarzy się równo i słabiej
	if _dead:
		eye = eye_base * (1.0 - smoothstep(0.0, 0.35, _dead_t))        # oczy gasną po śmierci
	for m in _mats:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("mod", Vector4(mod.r, mod.g, mod.b, mod.a))
		sm.set_shader_parameter("eye_glow", eye)
	var moving := anim == "walk" or anim == "run"
	if moving:
		var reference: float = float((EnemyDefs.DEFS.get(kind, {}) as Dictionary).get("speed", 95.0))
		var rate := absf(horizontal_speed) / maxf(reference, 1.0) if is_finite(horizontal_speed) else (2.4 if _sp == 2 else 1.0)
		var cycle := float(_spec.get("cycle", 1.0))
		if _sp == 2 and bool(_spec.get("body_motion", false)): cycle = 1.0
		_phase += delta * TAU / cycle * rate
		if is_finite(horizontal_speed) and absf(horizontal_speed) < 0.5:
			anim = "idle"
	_advance_motion(delta, anim)
	if _spec.has("deform"):
		_pose_deform(anim, fr, nfr, loop)
	elif _spec.get("quad", false):
		_pose_quad(anim, delta)
	elif _spec.get("crawler", false):
		_pose_crawler(anim)
	else:
		_pose_biped(anim, delta)
		if not _eyes.is_empty():
			_place_eyes()
	_prev_anim = anim

## Zdarzenia z gry (view3d.gd): "hit" — trafienie, "attack" — cios po zapowiedzi. Tylko modele z klipami.
func trigger(clip: String, action := "") -> void:
	if _dead or not _spec.get("clips", false) or not CLIP_DUR.has(clip):
		return
	if clip == "hit" and _clip == "attack" and _clip_t < 0.8 * clip_duration("attack"):
		return                                    # trafienie nie przerywa trwającego ciosu
	_clip = clip
	_clip_t = 0.0
	if clip == "attack":
		_motion_name = action if action != "" else (_motion_pending if _motion_pending != "" else Motion.action(kind))
		_motion_pending = ""
		_motion_weight = 1.0 if clips_on and _motion_name != "" else 0.0
		_contact_frame = _motion_weight > 0.0
	_foot_locks.clear()

## Śmierć: odtwarza upadek, potem leży, zapada się i `finished` = true. Modele bez klipów kończą od razu.
func die() -> void:
	if _dead:
		return
	_dead = true
	_dead_t = 0.0
	_clip = ""
	_dead_from = _last_p.duplicate()
	if not _spec.get("clips", false) and not _spec.has("death_dur"):
		finished = true

## Powrót do życia (respawn / reset wroga).
func revive() -> void:
	_landing_t = 10.0
	_landing_strength = 0.0
	_motion_name = ""
	_motion_wind_clock = 0.0
	_motion_remaining = NAN
	_motion_duration = 0.0
	_motion_weight = 0.0
	_motion_values.clear()
	_motion_pending = ""
	_contact_frame = false
	_grounded_hint = -1
	_target_world_y = NAN
	_airborne = false
	_air_w = 0.0
	_foot_locks.clear()
	_dead = false
	_dead_t = 0.0
	_clip = ""
	finished = false
	_tilt.basis = Basis.IDENTITY
	_tilt.position = Vector3.ZERO

## Oczy Mimika: dwie świecące kulki przy głowie (model gracza nie ma świecących pikseli w teksturze).
func _place_eyes() -> void:
	# oczy: przesunięcie względem kości głowy w pozie spoczynkowej (przód, góra, rozstaw — wg modelu), obracane razem z głową,
	# przeliczone z przestrzeni szkieletu do węzła modelu (szkielet w GLB może mieć własną transformację)
	var hp := _sk.get_bone_global_pose(_b["Head"])
	var rest := _sk.get_bone_global_rest(_b["Head"])
	var rel := _model.global_transform.affine_inverse() * _sk.global_transform
	for e in _eyes:
		var mi := e as MeshInstance3D
		var off: Array = _spec.get("eye_off", [0.085, 0.115, 0.035])
		var p := rest.origin + Vector3(float(off[0]), float(off[1]), float(off[2]) * float(mi.get_meta("side")))
		mi.position = rel * (hp * (rest.affine_inverse() * p))

## Wartość z tabeli klatek (liniowo między klatkami; loop: ostatnia łączy się z pierwszą).
func _tab(a: Array, f: float, loop: bool) -> float:
	var n := a.size()
	if n == 1:
		return float(a[0])
	var i := int(floor(f))
	var k := f - float(i)
	var i0 := posmod(i, n) if loop else clampi(i, 0, n - 1)
	var i1 := posmod(i + 1, n) if loop else clampi(i + 1, 0, n - 1)
	return lerpf(float(a[i0]), float(a[i1]), k)

func _pose_deform(anim: String, fr: float, nfr: int, loop: bool) -> void:
	var d := String(_spec["deform"])
	var n := maxi(nfr, 1)
	var ph := fr / float(n)
	var fh := float(_spec.get("frame_h", 20.0)) * PX
	_pivot.rotation = Vector3.ZERO
	_pivot.position.y = 0.0
	var prm := {}
	match d:
		"cma":
			prm["wing"] = _tab([38.0, 8.0, -26.0, 8.0], fr, true) if anim == "idle" else 70.0
			# wisi do góry nogami pod górną krawędzią ramki (sleep) albo leci wyśrodkowana w pionie; przy budzeniu płynny obrót wokół osi ciała
			var iw := smoothstep(0.0, 1.0, _inv_w)
			_pivot.rotation = Vector3(PI * iw, 0.0, 0.0)
			_pivot.position.y = lerpf(fh * 0.5 - _model_h * _scale * 0.5, fh, iw)
		"nest":
			prm["pulse"] = sin(ph * TAU)
		"vein":
			var k := sin(ph * TAU)
			var jaw := -1.0
			var sx := 1.0
			var sz := 1.0
			match anim:
				"dormant":
					sz = 0.80 + 0.012 * k
					sx = 1.04
				"idle":
					sz = 1.0 + 0.020 * k
					sx = 1.0 - 0.006 * k
				"open":
					jaw = _tab([0.75, 1.0, 1.1, 0.95], fr, true)
					sz = 1.0 + 0.045 * (0.5 + 0.5 * sin(ph * PI))
					sx = 1.0 + 0.02 * ph
				"windup":
					jaw = _tab([-0.9, -0.75, -0.55], fr, true)
					sz = 1.05 + 0.02 * ph
					sx = 1.0 - 0.015 * ph
				"spit":
					jaw = _tab([0.45, 0.9, 0.65], fr, true)
					sz = 1.03 + 0.03 * sin(ph * PI)
					sx = sz
			prm["jaw"] = jaw
			prm["sxz"] = Vector2(sx, sz)
		"leech":
			if _dead:
				anim = "death"
				fr = clampf(_dead_t / _death_dur(), 0.0, 1.0) * 7.0
				n = 8
				loop = false
			var i := int(floor(fr))
			var k2 := fr - float(i)
			var i0 := posmod(i, n) if loop else clampi(i, 0, n - 1)
			var i1 := posmod(i + 1, n) if loop else clampi(i + 1, 0, n - 1)
			var a: Array = _leech_pose(anim, i0, n)
			var b: Array = _leech_pose(anim, i1, n)
			var v: Array = []
			for j in a.size():
				v.append(lerpf(float(a[j]), float(b[j]), k2))
			if anim == "idle":                     # faza fali ciągła (bez cofania na złączeniu pętli)
				v[7] = ph * TAU
			elif anim == "grab":
				v[7] = ph * TAU * 2.0
			prm["p0"] = Vector4(v[0], v[1], v[2], v[3])
			prm["p1"] = Vector4(v[4], v[5], v[6], v[7])
			prm["p2"] = Vector3(v[8], v[9], v[10])
			prm["H"] = _model_h
	_deform_overlay(d, prm, fh)
	for m in _mats:
		for key in prm:
			(m as ShaderMaterial).set_shader_parameter(key, prm[key])

## Klipy zdarzeń dla modeli deformowanych: Ćma (trafienie: drżenie skrzydeł, atak: nurkowanie, śmierć: spadanie koziołkami), gniazdo (trafienie:
## wstrząs, śmierć: nabrzmiewa i zapada się), Żyła (trafienie: wstrząs, śmierć: szczęka szeroko, osiada). Pijawka ma własne klatki hurt / death.
func _deform_overlay(d: String, prm: Dictionary, fh: float) -> void:
	_tilt.basis = Basis.IDENTITY
	var off := Vector3.ZERO
	var sc := Vector3.ONE
	var roll := 0.0
	if not _dead:
		_sink_y = 0.0
	if _dead:
		var dd := _death_dur()
		var u := clampf(_dead_t / dd, 0.0, 1.0)
		match d:
			"cma":
				var ground := float(_pivot.position.y)                    # wysokość lotu nad podłożem
				off.y = -minf(4.5 * _dead_t * _dead_t, ground)
				roll = TAU * 0.85 * minf(_dead_t / 0.55, 1.0)
				prm["wing"] = 70.0 + 45.0 * sin(_dead_t * 32.0) * (1.0 - smoothstep(0.0, 0.7, u))
			"nest":
				var swell := smoothstep(0.0, 0.3, u)
				var burst := smoothstep(0.3, 1.0, u)
				sc = Vector3(1.0 + 0.22 * swell + 0.25 * burst, 1.0 + 0.10 * swell - 0.72 * burst, 1.0 + 0.22 * swell + 0.25 * burst)
				off.x = sin(_dead_t * 70.0) * 0.03 * (1.0 - u)
				prm["pulse"] = 1.0 * swell
			"vein":
				var sag := smoothstep(0.1, 1.0, u)
				prm["jaw"] = 1.2
				prm["sxz"] = Vector2(1.0 + 0.08 * sag, 1.0 - 0.45 * sag)
				off.x = sin(_dead_t * 50.0) * 0.06 * (1.0 - u)
		_sink(_dead_t - dd)
	elif _clip == "hit":
		var u := _clip_t / clip_duration("hit")
		var k := sin(PI * minf(u * 1.35, 1.0)) * (1.0 - u)
		match d:
			"cma":
				prm["wing"] = float(prm.get("wing", 0.0)) + 50.0 * sin(_clip_t * 75.0) * k
				off.x = -0.12 * k
				roll = deg_to_rad(18.0) * k
			"nest":
				prm["pulse"] = 0.9 * k
				sc = Vector3(1.0 + 0.05 * k, 1.0 - 0.08 * k, 1.0 + 0.05 * k)
			"vein":
				off.x = sin(_clip_t * 60.0) * 0.05 * k
				sc.y = 1.0 - 0.04 * k
	elif _clip == "attack" and d == "cma" and _motion_weight < 0.001:
		var u := _clip_t / clip_duration("attack")
		var snap := smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.55, 1.0, u))
		roll = -deg_to_rad(40.0) * snap
		off.x = 0.22 * snap
		off.y = -0.14 * snap
	if not _dead and d == "cma" and not _motion_values.is_empty():
		roll = lerpf(roll, deg_to_rad(float(_motion_values.get("roll", 0.0))), _motion_weight)
		off.x = lerpf(off.x, float(_motion_values.get("shift", 0.0)), _motion_weight)
		off.y = lerpf(off.y, float(_motion_values.get("lift", 0.0)), _motion_weight)
		prm["wing"] = lerpf(float(prm.get("wing", 0.0)), float(_motion_values.get("wing", 0.0)), _motion_weight)
	_tilt.position = Vector3(off.x, off.y + _sink_y, off.z)
	_pivot.scale = Vector3(_scale * sc.x, _scale * sc.y, _scale * sc.z)
	if roll != 0.0 and _pivot.rotation.x == 0.0:                            # (Ćma śpiąca do góry nogami nie przechyla się)
		_pivot.rotation = Vector3(0.0, 0.0, roll)

## Poza Pijawki z klatki (jak `leech_pose` w static_tripo_bake.py): [yaw, bend, dz, sz, close, wide, amp, ph, shake, headtilt, ox].
func _leech_pose(anim: String, i: int, n: int) -> Array:
	var yaw := -50.0
	var bend := 0.0
	var dz := 0.0
	var sz := 1.0
	var close := 0.0
	var wide := 0.0
	var amp := 0.0
	var ph := 0.0
	var shake := 0.0
	var ht := 0.0
	var ox := 0.0
	match anim:
		"idle":
			var a := float(i) / 8.0 * TAU
			bend = 0.07 * sin(a)
			sz = 1.0 + 0.018 * sin(a + 1.0)
			amp = 0.07
			ph = a
			wide = 0.10 + 0.10 * (0.5 + 0.5 * sin(a * 2.0))
			yaw = -50.0 + 4.0 * sin(a)
		"peek":
			var a := float(i) / 4.0 * TAU
			yaw = -75.0 + 6.0 * sin(a)
			dz = -0.70 + 0.012 * sin(a)
			close = 0.75
			bend = -0.15
			amp = 0.05
			ph = float(i) * 1.5
		"strike":
			var j := clampi(i, 0, 5)
			yaw = [-70.0, -55.0, -22.0, -20.0, -30.0, -42.0][j]
			dz = [-0.45, -0.20, 0.02, 0.0, -0.02, 0.0][j]
			bend = [-0.55, -0.25, 0.60, 0.65, 0.40, 0.22][j]
			ox = [0.0, 0.0, -0.06, -0.06, -0.03, 0.0][j]
			sz = [0.94, 1.08, 1.10, 1.05, 1.0, 1.0][j]
			close = [0.7, 0.4, 0.0, 0.0, 0.0, 0.0][j]
			wide = [0.0, 0.15, 0.7, 0.75, 0.45, 0.25][j]
			amp = 0.07
			ph = float(j) * 1.3
		"grab":
			var a := float(i) / 6.0 * TAU
			yaw = -30.0
			bend = 0.42 + 0.07 * sin(a * 2.0)
			ht = 0.12 + 0.08 * sin(a * 2.0 + 1.0)
			ox = -0.05
			shake = 0.012 * sin(a * 2.0)
			amp = 0.09
			ph = a * 2.0
			wide = 0.6 if i % 2 == 0 else 0.0
			close = 0.0 if i % 2 == 0 else 0.5
			sz = 1.0 + 0.03 * sin(a * 2.0)
		"spit":
			var j := clampi(i, 0, 5)
			yaw = [-60.0, -60.0, -48.0, -25.0, -30.0, -45.0][j]
			dz = [-0.45, -0.18, 0.0, 0.0, 0.0, 0.0][j]
			bend = [-0.3, -0.45, -0.55, 0.35, 0.2, 0.05][j]
			ox = [0.0, 0.0, 0.0, -0.03, -0.02, 0.0][j]
			close = [0.6, 0.25, 0.0, 0.0, 0.0, 0.0][j]
			wide = [0.0, 0.2, 0.6, 0.85, 0.5, 0.2][j]
			amp = [0.06, 0.12, 0.16, 0.05, 0.05, 0.05][j]
			ph = [0.0, 1.5, 3.0, 4.5, 5.0, 5.5][j]
			sz = [1.06, 1.05, 1.05, 0.96, 1.0, 1.0][j]
		"hurt":
			var j := clampi(i, 0, 1)
			bend = [-0.14, -0.05][j]
			sz = [0.92, 0.97][j]
			wide = [0.45, 0.25][j]
			amp = 0.05
			ph = float(j) * 2.0
			shake = [0.010, -0.005][j]
		"dive":
			var j := clampi(i, 0, 4)
			yaw = [-50.0, -55.0, -60.0, -65.0, -70.0][j]
			bend = [0.12, -0.10, -0.25, -0.35, -0.35][j]
			dz = [-0.05, -0.30, -0.58, -0.80, -0.97][j]
			close = [0.2, 0.5, 0.7, 0.75, 0.75][j]
			sz = [1.04, 1.05, 1.03, 1.0, 1.0][j]
			amp = 0.06
			ph = float(j) * 1.2
		"death":
			var j := clampi(i, 0, 7)
			yaw = [-50.0, -45.0, -40.0, -35.0, -30.0, -30.0, -30.0, -30.0][j]
			bend = [-0.35, 0.20, -0.55, 0.40, 0.80, 1.00, 1.10, 1.15][j]
			ox = [0.0, 0.0, 0.0, -0.02, -0.04, -0.05, -0.05, -0.05][j]
			dz = [0.0, 0.0, 0.0, -0.05, -0.15, -0.35, -0.60, -0.85][j]
			wide = [0.5, 0.7, 0.85, 0.85, 0.75, 0.6, 0.4, 0.2][j]
			shake = [0.014, -0.012, 0.016, -0.010, 0.006, 0.0, 0.0, 0.0][j]
			amp = [0.10, 0.10, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0][j]
			ph = float(j) * 2.2
			sz = [1.0, 1.04, 0.96, 1.05, 1.0, 1.0, 1.0, 1.0][j]
	return [yaw, bend, dz, sz, close, wide, amp, ph, shake, ht, ox]

## Próbka animacji chodu z pliku (rotacje i pozycje kości lokalne) w chwili t.
func _sample_quad(t: float) -> Array:
	_ap.assigned_animation = _ap_name
	_ap.seek(t, true)
	var rots := []
	var poss := []
	for bi in _sk.get_bone_count():
		rots.append(_sk.get_bone_pose_rotation(bi))
		poss.append(_sk.get_bone_pose_position(bi))
	return [rots, poss]

func _pose_quad(anim: String, delta: float) -> void:
	var len := 1.0
	if _ap != null and _ap_name == "":
		var names := _ap.get_animation_list()
		if not names.is_empty():
			_ap_name = names[0]
			_ap.get_animation(_ap_name).loop_mode = Animation.LOOP_LINEAR
	if _ap != null and _ap_name != "":
		len = _ap.get_animation(_ap_name).length
	var idle_t := float(_spec.get("idle_t", 0.0)) * len
	var running := anim == "run" or anim == "walk"
	_qw = move_toward(_qw, 1.0 if running else 0.0, delta * BLEND_RATE * 0.5)
	var sy := 1.0
	if anim == "sleep":                           # zwinięty: spłaszczony, powoli oddycha
		sy = (0.60 if "--nosit" in OS.get_cmdline_user_args() else 1.0) + 0.012 * sin(_t * 1.7)      # siedzi (siad niżej), oddycha wolniej niż obudzony
	else:
		sy = 1.0 + 0.018 * sin(_t * 2.6)
	if _ap != null and _ap_name != "":
		# idle i bieg próbkujemy osobno i mieszamy kość po kości (płynne wejście i wyjście z biegu, bez przeskoku nóg)
		if not _qsamp.has("idle"):
			_qsamp["idle"] = _sample_quad(idle_t)
		if not _qsamp.has("air"):
			_qsamp["air"] = _sample_quad(float(_spec.get("air_t", 0.25)) * len)       # faza „wyciągnięta” chodu = skok
		var ri: Array = _qsamp["idle"][0]
		var pi_: Array = _qsamp["idle"][1]
		if _qw > 0.001:
			var run := _sample_quad(fposmod(_phase / TAU, 1.0) * len)
			var rr: Array = run[0]
			var pr: Array = run[1]
			for bi in ri.size():
				_sk.set_bone_pose_rotation(bi, (ri[bi] as Quaternion).slerp(rr[bi], _qw))
				_sk.set_bone_pose_position(bi, (pi_[bi] as Vector3).lerp(pr[bi], _qw))
		else:
			for bi in ri.size():
				_sk.set_bone_pose_rotation(bi, ri[bi])
				_sk.set_bone_pose_position(bi, pi_[bi])
	# siad: Trzosek nieobudzony (sleep — pozycja startowa na mapie) i obudzony czekający (idle) siedzi; wstaje do biegu, zapowiedzi ataku (windup), ciosu, trafienia i w locie
	if _qsamp.has("idle"):
		var want_sit := (anim == "idle" or anim == "sleep") and not _dead and _clip == "" and _air_w < 0.01 and not "--nosit" in OS.get_cmdline_user_args()
		_qs = move_toward(_qs, 1.0 if want_sit else 0.0, delta * (3.0 if want_sit else 7.0))
		if _qs > 0.001:
			if not _qsamp.has("sit"):
				var keep_r := []
				var keep_p := []
				for bi in _sk.get_bone_count():
					keep_r.append(_sk.get_bone_pose_rotation(bi))
					keep_p.append(_sk.get_bone_pose_position(bi))
				_qsamp["sit"] = _build_sit(_qsamp["idle"])
				for bi in keep_r.size():
					_sk.set_bone_pose_rotation(bi, keep_r[bi])
					_sk.set_bone_pose_position(bi, keep_p[bi])
			var k := _qs * _qs * (3.0 - 2.0 * _qs)
			var rs: Array = _qsamp["sit"][0]
			var ps: Array = _qsamp["sit"][1]
			for bi in rs.size():
				_sk.set_bone_pose_rotation(bi, _sk.get_bone_pose_rotation(bi).slerp(rs[bi], k))
				_sk.set_bone_pose_position(bi, _sk.get_bone_pose_position(bi).lerp(ps[bi], k))
	if _air_w > 0.002 and _qsamp.has("air"):
		# lot: mieszamy z próbką „wyciągnięta” kość po kości (po bazowej pozie idle / bieg)
		var ra: Array = _qsamp["air"][0]
		var pa: Array = _qsamp["air"][1]
		for bi in ra.size():
			_sk.set_bone_pose_rotation(bi, _sk.get_bone_pose_rotation(bi).slerp(ra[bi], _air_w))
			_sk.set_bone_pose_position(bi, _sk.get_bone_pose_position(bi).lerp(pa[bi], _air_w))
	# nakładki: oddech, trafienie, atak, śmierć
	var pitch := 0.0                              # + = nos w górę
	var roll := 0.0
	var shift := 0.0
	var lift := 0.0
	var arch := 0.0                               # rad: wygięcie kręgosłupa (+ = grzbiet w dół, głowa w górę)
	arch += deg_to_rad(1.6) * sin(_t * 2.6)
	if _air_w > 0.002:                            # wznosząc się: nos w górę, spadając: w dół
		pitch += deg_to_rad(22.0) * clampf(-_air_vy / 275.0, -1.0, 1.0) * _air_w
		arch += deg_to_rad(6.0) * clampf(-_air_vy / 275.0, -1.0, 1.0) * _air_w
	if _dead:
		var dd := _death_dur()
		var u := clampf(_dead_t / dd, 0.0, 1.0)
		var yelp := sin(clampf(u / 0.25, 0.0, 1.0) * PI * 0.5)         # 0..1: szarpnięcie głowy w górę
		var fall := smoothstep(0.18, 1.0, u)
		pitch = deg_to_rad(26.0) * yelp * (1.0 - fall) + deg_to_rad(6.0) * fall
		roll = deg_to_rad(-82.0) * fall * fall * (3.0 - 2.0 * fall)
		arch = deg_to_rad(20.0) * yelp * (1.0 - fall) - deg_to_rad(8.0) * fall
		shift = -0.20 * fall
		lift = 0.34 * absf(sin(roll))
		sy = lerpf(1.0, 0.9, fall)
		_sink(_dead_t - dd)
	elif _clip == "hit":
		var u := _clip_t / clip_duration("hit")
		var k := sin(PI * minf(u * 1.35, 1.0)) * (1.0 - u)
		pitch = deg_to_rad(15.0) * k
		arch = deg_to_rad(14.0) * k
		shift = -0.14 * k
	elif _clip == "attack" and _motion_weight < 0.001:
		var u := _clip_t / clip_duration("attack")
		var up := smoothstep(0.0, 0.34, u)                               # zamach: nos w górę, zad się zapada
		var snap := smoothstep(0.34, 0.5, u)                             # kłapnięcie: nos gwałtownie w dół
		var back := smoothstep(0.5, 1.0, u)
		pitch = deg_to_rad(20.0) * up * (1.0 - snap) - deg_to_rad(20.0) * snap * (1.0 - back)
		arch = deg_to_rad(10.0) * up * (1.0 - snap) - deg_to_rad(12.0) * snap * (1.0 - back)
		shift = 0.18 * snap * (1.0 - back) - 0.06 * up * (1.0 - snap)
		sy = lerpf(sy, 0.93, up * (1.0 - snap))
	if not _dead and not _motion_values.is_empty():
		pitch = lerpf(pitch, deg_to_rad(float(_motion_values.get("pitch", 0.0))), _motion_weight)
		arch = lerpf(arch, deg_to_rad(float(_motion_values.get("arch", 0.0))), _motion_weight)
		shift = lerpf(shift, float(_motion_values.get("shift", 0.0)), _motion_weight)
	if _landing_t < Motion.recovery("landing"):
		var landing := Motion.sample("landing", _landing_t)
		pitch += deg_to_rad(float(landing.get("pitch", 0.0))) * _landing_strength
		sy -= float(landing.get("drop", 0.0)) * _landing_strength
	if not _spine.is_empty():
		for bi in _spine:
			_rot_world(bi, Vector3.RIGHT, arch / float(_spine.size()))
	var yaw := deg_to_rad(float(_spec.get("yaw", 0.0)))
	_tilt.basis = Basis.IDENTITY
	_pivot.basis = Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, roll) * Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(_scale, _scale * sy, _scale))
	if not _dead:
		_sink_y = 0.0
	_tilt.position = Vector3(shift, lift + _sink_y, 0.0)
	if not _dead and not _airborne:
		_quad_support()
	else:
		_foot_locks.clear()

## Cztery łapy: cele w świecie i IK bez rozciągania kości, także podczas kłapnięcia pyskiem.
func _quad_support() -> void:
	for key in _q_limbs:
		var chain: Array = _q_limbs[key]
		var toe := _gp(chain[4])
		var world := _sk.global_transform * toe.origin
		var rest := _sk.global_transform * _sk.get_bone_global_rest(chain[4]).origin
		var foot_delta := toe.origin - _gp(chain[3]).origin
		var height: float = _sole_floor(key, _gp(chain[3]).basis) + (_sk.global_transform.basis * foot_delta).y if _sole_points.has(key) else global_position.y + float((ground_profile.get(key, {}) as Dictionary).get("height", 0.0)) + maxf(rest.y - global_position.y, 0.0)
		if world.y > height + 0.12:
			_foot_locks.erase(key)
			continue
		var target := world
		target.y = height
		if not _foot_locks.has(key): _foot_locks[key] = target
		var locked: Vector3 = _foot_locks[key]
		if locked.distance_to(target) > 0.32 or absf(locked.y - target.y) > 0.02:
			_foot_locks[key] = target
		else:
			target = locked
		target = _sk.global_transform.affine_inverse() * target
		var ankle_delta := _gp(chain[3]).origin - _gp(chain[2]).origin
		var ankle_basis := _gp(chain[2]).basis
		var foot_basis := _gp(chain[3]).basis
		var a := _gp(chain[0]).origin
		var mid := _gp(chain[1]).origin
		var end := _gp(chain[2]).origin
		var pole := (mid - (a + end) * 0.5).normalized()
		_two_bone(chain[0], chain[1], chain[2], a.distance_to(mid), mid.distance_to(end), target - foot_delta - ankle_delta, pole)
		# Zachowaj orientację stawu skokowego i palców z klipu. Dodatkowe celowanie
		# krótkimi kośćmi stopy skręcało skórę łapy przy prawie prostym kolanie.
		_set_global_basis(chain[2], ankle_basis)
		_set_global_basis(chain[3], foot_basis)
		for correction in 2:
			var penetration := _sole_penetration(key)
			if penetration < 0.001: break
			var world_target := _sk.global_transform * target
			world_target.y += penetration * 1.25
			target = _sk.global_transform.affine_inverse() * world_target
			_two_bone(chain[0], chain[1], chain[2], a.distance_to(mid), mid.distance_to(end), target - foot_delta - ankle_delta, pole)
			_set_global_basis(chain[2], ankle_basis)
			_set_global_basis(chain[3], foot_basis)
			_foot_locks[key] = world_target
		if (_sk.global_transform * _gp(chain[4]).origin).distance_to(_foot_locks[key]) > 0.02: _foot_locks.erase(key)

## Próbka „siad” czworonoga (Trzosek czeka na atak): budowana raz z pozy idle i zapamiętana jak próbki z animacji, więc `_pose_quad` miesza ją
## kość po kości z postawą stojącą i biegiem. Przestrzeń szkieletu: Y w górę, głowa w −Z, ogon w +Z.
##  - tułów obrócony o SIT_ANGLE wokół osi poprzecznej przez barki (barki zostają na wysokości, zad schodzi do ziemi),
##  - przednie nogi proste, obie łapy równo na ziemi pod barkami (IK; próbka idle to klatka chodu z jedną łapą w górze),
##  - tylne nogi złożone: kolano w przód przy brzuchu, staw skokowy na ziemi pod zadem, śródstopie płasko w przód,
##  - szyja i głowa odgięte z powrotem (pysk poziomo, czujnie), ogon położony na ziemi za psem.
const SIT_ANGLE := 56.0
func _build_sit(idle: Array) -> Array:
	var ri: Array = idle[0]
	var pi_: Array = idle[1]
	for bi in ri.size():
		_sk.set_bone_pose_rotation(bi, ri[bi])
		_sk.set_bone_pose_position(bi, pi_[bi])
	var fl := [_sk.find_bone("tripo__0_Left_Limb_0"), _sk.find_bone("tripo__0_Right_Limb_0")]
	if fl[0] < 0 or fl[1] < 0:
		return idle
	var ground := 1e9                                     # poziom ziemi = najniższy palec w pozie stojącej
	for pre in ["tripo__0_Left", "tripo__0_Right", "tripo__1_Left", "tripo__1_Right"]:
		var t4 := _sk.find_bone(pre + "_Limb_4")
		if t4 >= 0:
			ground = minf(ground, _gp(t4).origin.y)
	var lens := {}                                        # długości odcinków nóg w pozie stojącej
	for pre in ["tripo__0_Left", "tripo__0_Right", "tripo__1_Left", "tripo__1_Right"]:
		var b0 := _sk.find_bone(pre + "_Limb_0")
		var b1 := _sk.find_bone(pre + "_Limb_1")
		var b2 := _sk.find_bone(pre + "_Limb_2")
		lens[pre] = [_gp(b0).origin.distance_to(_gp(b1).origin), _gp(b1).origin.distance_to(_gp(b2).origin)]
	var sh0 := (_gp(fl[0]).origin + _gp(fl[1]).origin) * 0.5
	# tułów: obrót korzenia i powrót barków na miejsce (lekko niżej — pies siedząc opuszcza przód)
	_rot_world(0, Vector3.RIGHT, deg_to_rad(SIT_ANGLE))
	var sh1 := (_gp(fl[0]).origin + _gp(fl[1]).origin) * 0.5
	_sk.set_bone_pose_position(0, _sk.get_bone_pose_position(0) + (sh0 - sh1) + Vector3(0.0, 0.035, -0.05))
	# szyja i głowa: pysk z powrotem do poziomu
	for spec in [["tripo__Spine_4", -0.22], ["tripo__Head_0", -0.50]]:
		var hb := _sk.find_bone(String(spec[0]))
		if hb >= 0:
			_rot_world(hb, Vector3.RIGHT, deg_to_rad(SIT_ANGLE) * float(spec[1]))
	# ogon: po ziemi do tyłu
	var tb := _sk.find_bone("bone_31")
	if tb >= 0:
		_rot_world(tb, Vector3.RIGHT, deg_to_rad(-SIT_ANGLE - 18.0))
	# przednie nogi: proste, łapy równo pod barkami
	for pre in ["tripo__0_Left", "tripo__0_Right"]:
		var a := _sk.find_bone(pre + "_Limb_0")
		var m := _sk.find_bone(pre + "_Limb_1")
		var e := _sk.find_bone(pre + "_Limb_2")
		var f := _sk.find_bone(pre + "_Limb_3")
		var sh := _gp(a).origin
		var wrist := Vector3(sh.x * 1.05, ground + 0.17, sh.z - 0.09)
		_two_bone(a, m, e, float(lens[pre][0]), float(lens[pre][1]), wrist, sh + Vector3(0.0, -0.2, 0.6))
		_point_bone(e, f, _gp(e).origin + Vector3(0.0, -0.12, -0.035))
	# tylne nogi: złożone pod zadem
	for pre in ["tripo__1_Left", "tripo__1_Right"]:
		var a2 := _sk.find_bone(pre + "_Limb_0")
		var m2 := _sk.find_bone(pre + "_Limb_1")
		var e2 := _sk.find_bone(pre + "_Limb_2")
		var f2 := _sk.find_bone(pre + "_Limb_3")
		var hip := _gp(a2).origin
		var side := signf(hip.x)
		var hock := Vector3(hip.x + side * 0.06, ground + 0.07, hip.z + 0.10)
		_two_bone(a2, m2, e2, float(lens[pre][0]), float(lens[pre][1]), hock, hip + Vector3(side * 0.12, 0.05, -0.6))
		_point_bone(e2, f2, _gp(e2).origin + Vector3(side * 0.05, -0.015, -0.25))
	var rots := []
	var poss := []
	for bi in _sk.get_bone_count():
		rots.append(_sk.get_bone_pose_rotation(bi))
		poss.append(_sk.get_bone_pose_position(bi))
	return [rots, poss]

var _sink_y := 0.0

## Zapadanie się ciała w ziemię po upadku (t = czas od końca animacji upadku).
func _sink(t: float) -> void:
	var k := clampf((t - CORPSE_HOLD) / CORPSE_SINK, 0.0, 1.0)
	var depth := clampf(_model_h * _scale * 0.5, 0.5, 2.5)         # duży model zapada się głębiej, żeby zniknąć w terenie
	_sink_y = -depth * k * k

## Czas animacji śmierci (s): profil modelu albo domyślny dla klasy.
func _death_dur() -> float:
	var dk: Dictionary = _spec.get("death", {})
	if dk.has("dur"):
		return float(dk["dur"])
	if _spec.has("death_dur"):
		return float(_spec["death_dur"])
	return float(DEATH_DUR["quad" if _spec.get("quad", false) else "biped"])

func _pose_crawler(anim: String) -> void:
	_sk.reset_bone_poses()
	var hips: int = _b["Hips"]
	var ph := _t * TAU / 2.4
	var tilt := 0.0
	var lift := 0.0
	var curl := 0.0                                # rad: zwijanie kończyn (śmierć)
	var back := 0.0                                # m: przesunięcie bioder
	var lean_x := 0.0                              # stopnie: dodatkowe pochylenie bioder w przód (+)
	var arms_x := 0.0                              # stopnie: wyrzut kończyn w przód (+)
	var hd := Vector3.ZERO                         # przesunięcie bioder (jedno wywołanie _move_global: ustawia pozycję bezwzględnie)
	if anim == "run" or anim == "walk":
		hd = Vector3(0.0, 0.03 * cos(2.0 * _phase), 0.0)
		for side in ["Right", "Left"]:
			var sw := sin(_phase + (0.0 if side == "Right" else PI))
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(-30.0 * sw))
			_rot_world(_b[side + "UpLeg"], Vector3.BACK, deg_to_rad(-26.0 * sw))
	elif anim == "windup":
		hd = Vector3(0.0, -0.18, 0.0)
		_rot_world(hips, Vector3.BACK, deg_to_rad(-22.0))
		for side in ["Right", "Left"]:
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(35.0))
	else:
		hd = Vector3(0.0, 0.012 * sin(ph), 0.0)
	if _dead:
		var dd := _death_dur()
		var u := clampf(_dead_t / dd, 0.0, 1.0)
		var jerk := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.2, 0.45, u))
		var flip := smoothstep(0.25, 0.8, u)
		tilt = deg_to_rad(80.0) * flip * flip                           # przewrót na grzbiet
		lift = 0.18 * absf(sin(tilt))
		curl = deg_to_rad(55.0) * flip + deg_to_rad(8.0) * sin(_dead_t * 34.0) * (1.0 - u) * flip
		lean_x = -18.0 * jerk
		_sink(_dead_t - dd)
	elif _clip == "hit":
		var u := _clip_t / clip_duration("hit")
		var k := sin(PI * minf(u * 1.35, 1.0)) * (1.0 - u)
		back = -0.10 * k
		lean_x = -16.0 * k
		arms_x = -18.0 * k
	elif _clip == "attack" and _motion_weight < 0.001:
		var u := _clip_t / clip_duration("attack")
		var load := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.25, 0.4, u))
		var spring := smoothstep(0.25, 0.45, u) * (1.0 - smoothstep(0.55, 1.0, u))
		back = -0.10 * load + 0.16 * spring
		lean_x = 14.0 * load + 24.0 * spring
		arms_x = -50.0 * spring + 20.0 * load
	if not _dead and not _motion_values.is_empty():
		lean_x = lerpf(lean_x, float(_motion_values.get("lean", 0.0)), _motion_weight)
		arms_x = lerpf(arms_x, float(_motion_values.get("arm", 0.0)), _motion_weight)
		back = lerpf(back, float(_motion_values.get("shift", 0.0)), _motion_weight)
		curl = lerpf(curl, deg_to_rad(float(_motion_values.get("leg", 0.0))), _motion_weight)
	if _air_w > 0.002:                              # skok: ręce wyrzucone do przodu, nogi odrzucone w tył, tułów pochylony — jak w ataku z sufitu
		var rise_c := clampf(-_air_vy / 275.0, 0.0, 1.0)
		lean_x += (16.0 * rise_c + 6.0) * _air_w
		arms_x += -48.0 * _air_w
		curl += deg_to_rad(-26.0) * _air_w * (1.0 - clampf(_air_vy / 380.0, 0.0, 1.0) * 0.7)
	if _landing_t < Motion.recovery("landing"):
		var landing := Motion.sample("landing", _landing_t)
		hd.y -= float(landing.get("drop", 0.0)) * _landing_strength
		lean_x += float(landing.get("lean", 0.0)) * _landing_strength
	_move_global(hips, hd + Vector3(back, 0.0, 0.0))
	if lean_x != 0.0:
		_rot_world(hips, Vector3.BACK, -deg_to_rad(lean_x))
	if arms_x != 0.0:
		for side in ["Right", "Left"]:
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(arms_x))
	if curl != 0.0:
		for side in ["Right", "Left"]:
			_rot_world(_b[side + "Arm"], Vector3.BACK, curl)
			_rot_world(_b[side + "UpLeg"], Vector3.BACK, -curl)
	if not _dead:
		_sink_y = 0.0
	_tilt.basis = Basis(Vector3.BACK, tilt)
	_tilt.position = Vector3(0.0, lift + _sink_y, 0.0)
	# „sleep": wisi pod sufitem do góry nogami (chwyty u górnej krawędzi ramki sprite'a); przy budzeniu i spadaniu płynny obrót wokół osi ciała
	var iw := smoothstep(0.0, 1.0, _inv_w)
	_pivot.rotation = Vector3(PI * iw, 0.0, 0.0)
	_pivot.position.y = float(_spec["frame_h"]) * PX * iw
	if not _dead and not _airborne and _clip == "" and iw < 0.01 and anim in ["idle", "walk", "run"]:
		# Dłonie i stopy pełzaka są punktami podparcia, nie swobodnie obracanymi wahadłami.
		for side in ["Right", "Left"]:
			var phase := _phase + (0.0 if side == "Right" else PI)
			var locomotion := anim in ["walk", "run"]
			for limb in ["arm", "leg"]:
				var endpoint: int = _b[side + ("Hand" if limb == "arm" else "Foot")]
				var rest := _sk.get_bone_global_rest(endpoint)
				var ph_limb := phase + (PI if limb == "leg" else 0.0)
				var target := rest.origin
				var key: String = side + ("Hand" if limb == "arm" else "")
				target.y += float((ground_profile.get(key, {}) as Dictionary).get("height", 0.0)) / _scale
				if locomotion:
					target += Vector3(-0.20 * cos(ph_limb), 0.10 * maxf(0.0, sin(ph_limb)), 0.0)
				var upper: int = _b[side + ("Arm" if limb == "arm" else "UpLeg")]
				var middle: int = _b[side + ("ForeArm" if limb == "arm" else "Leg")]
				var lengths: Array = _arm_len[side] if limb == "arm" else _leg_len[side]
				_two_bone(upper, middle, endpoint, lengths[0], lengths[1], target, Vector3(1.0, 0.2, 0.0))
				_set_global_basis(endpoint, rest.basis)

## Parametry pozy bazowej dla animacji 2D (jak w wypieku `monster_tripo_bake.py`).
func _biped_params(anim: String) -> Dictionary:
	var prof: Dictionary = _spec.get("prof", {})
	var ph := _phase if (anim == "walk" or anim == "run" or anim == "charge") else _t * TAU / 2.4
	var l0: float = prof.get("lean", 12.0)
	var lw: float = prof.get("lean_walk", 14.0)
	var hy: float = prof.get("hy", 0.62)
	var hz: float = prof.get("hz", 0.42)
	var sl: float = prof.get("sleep_lean", 27.0)
	var stride: float = prof.get("stride", 0.22)
	var p := {"lean": l0, "bob": 0.0, "drop": 0.0, "hk": 0.8,
		"pelvis_yaw": 0.0, "chest_yaw": 0.0, "shift": 0.0, "sway": 0.0, "wristR": 0.0, "wristL": 0.0,
		"fR": Vector3.ZERO, "fL": Vector3.ZERO,
		"hR": Vector3(_x0 + 0.05, hz, hy), "hL": Vector3(_x0 + 0.05, hz, -hy)}
	match anim:
		"idle":
			p["lean"] = l0 + 1.6 * sin(ph)
			p["bob"] = 0.012 * sin(ph)
			p["fR"] = Vector3(0.04, 0, 0)
			p["fL"] = Vector3(-0.04, 0, 0)
			var sw := 0.06 * sin(ph)
			p["hR"] = Vector3(_x0 + 0.05 + sw, hz, hy)
			p["hL"] = Vector3(_x0 + 0.05 - sw, hz, -hy)
		"walk", "run":
			var own := 1.0 - _ck                       # z klipem chodu kołysanie i tor stóp niesie klip (_apply_biped)
			p["lean"] = lw
			p["bob"] = 0.035 * cos(2.0 * ph) * own
			p["drop"] = 0.03
			p["fR"] = Vector3(-stride * cos(ph), 0.14 * maxf(0.0, sin(ph)), 0.0) * own
			p["fL"] = Vector3(-stride * cos(ph + PI), 0.14 * maxf(0.0, sin(ph + PI)), 0.0) * own
			var sw2 := 0.30 * sin(ph)
			var lift := 0.05 * absf(sw2)
			p["hR"] = Vector3(_x0 + 0.05 + sw2, hz + lift, hy)
			p["hL"] = Vector3(_x0 + 0.05 - sw2, hz + lift, -hy)
		"windup":
			p["lean"] = -10.0
			p["drop"] = 0.04
			p["fR"] = Vector3(0.12, 0, 0)
			p["fL"] = Vector3(-0.12, 0, 0)
			p["hR"] = Vector3(_x0 + 0.10, 1.70, 0.40)
			p["hL"] = Vector3(_x0 + 0.10, 1.70, -0.40)
			var wk := String(prof.get("windup", ""))
			if wk == "point":                          # Podsłuchacz: ręka wskazuje, głowa do tyłu (krzyk)
				p["lean"] = -6.0
				p["hR"] = Vector3(_x0 + 0.62, 1.15, 0.30)
				p["hL"] = Vector3(_x0 + 0.05, hz, -hy)
			elif wk == "reach":                        # Stalker: obie ręce wyciągnięte do przodu
				p["lean"] = 2.0
				p["hR"] = Vector3(_x0 + 0.85, 1.30, 0.22)
				p["hL"] = Vector3(_x0 + 0.85, 1.30, -0.22)
			elif wk == "claw":
				p["lean"] = 4.0
				p["hR"] = Vector3(_x0 - 0.18, 1.35, hy * 1.15)
				p["hL"] = Vector3(_x0 + 0.38, 1.10, -hy)
			elif wk == "cleave":
				p["lean"] = -8.0
				p["hR"] = Vector3(_x0 - 0.15, 1.85, hy * 0.8)
				p["hL"] = Vector3(_x0 + 0.18, 1.05, -hy)
		"stun":
			# oszołomiony: tułów zgarbiony, głowa zwisa i kołysze się, kolana ugięte, ręce bezwładne; ciało zatacza się na boki
			var dz := sin(_t * 3.4)
			p["lean"] = 20.0 + 6.0 * dz
			p["drop"] = 0.22
			p["bob"] = 0.03 * sin(_t * 6.8)
			p["hk"] = 1.7
			p["fR"] = Vector3(0.20 + 0.05 * dz, 0.0, 0.0)
			p["fL"] = Vector3(-0.24 - 0.05 * dz, 0.0, 0.0)
			p["hR"] = Vector3(_x0 + 0.02 + 0.10 * dz, 0.36, hy * 1.1)
			p["hL"] = Vector3(_x0 - 0.02 - 0.10 * dz, 0.36, -hy * 1.1)
		"charge":
			# szarża: tułów mocno do przodu, ręce odrzucone do tyłu, głowa nisko, krok wydłużony
			p["lean"] = 28.0
			p["drop"] = 0.10
			p["bob"] = 0.04 * cos(2.0 * ph)
			p["hk"] = 0.3
			p["fR"] = Vector3(-stride * 1.5 * cos(ph), 0.17 * maxf(0.0, sin(ph)), 0.0)
			p["fL"] = Vector3(-stride * 1.5 * cos(ph + PI), 0.17 * maxf(0.0, sin(ph + PI)), 0.0)
			p["hR"] = Vector3(_x0 - 0.25, hz + 0.15, hy)
			p["hL"] = Vector3(_x0 - 0.25, hz + 0.15, -hy)
			if bool(_spec.get("body_motion", false)):
				# Dłuższy krok zamiast podwajania częstotliwości nóg.
				# Dwa kroki w cyklu pokrywają drogę przebytą przez root;
				# zasięg wynika z anatomii, a podpory są centrowane pod biodrami.
				var reference: float = EnemyDefs.DEFS[kind].speed
				p["drop"] = 0.16
				for side in ["Right", "Left"]:
					var sg := 1.0 if side == "Right" else -1.0
					var lengths: Array = _leg_len[side]
					var step := minf(reference * PX / (4.0 * _scale), float(lengths[0] + lengths[1]) * 0.8)
					var foot := _sk.get_bone_global_rest(_b[side + "Foot"]).origin
					var hip := _sk.get_bone_global_rest(_b[side + "UpLeg"]).origin
					p["fR" if side == "Right" else "fL"] = Vector3(hip.x - foot.x - step * cos(ph) * sg, 0.20 * maxf(0.0, sin(ph) * sg), 0.0)
					var hand := _sk.get_bone_global_rest(_b[side + "Hand"]).origin
					p["hR" if side == "Right" else "hL"] = hand + Vector3(0.16 + 0.12 * cos(ph) * sg, 0.20, 0.0)
		"air":
			# skok / spadanie: tułów lekko do przodu, kolana podciągnięte przy wznoszeniu i sięgające w dół przy spadaniu, ręce unoszone
			var rise := clampf(-_air_vy / 275.0, 0.0, 1.0)
			var fl := clampf(_air_vy / 380.0, 0.0, 1.0)
			p["lean"] = 8.0 - 4.0 * fl
			p["drop"] = -0.03 * rise
			p["fR"] = Vector3(0.20 - 0.08 * fl, 0.30 * (1.0 - fl) + 0.05, 0.0)
			p["fL"] = Vector3(-0.10, 0.20 * (1.0 - fl) + 0.05, 0.0)
			p["hR"] = Vector3(_x0 + 0.34, hz + 0.28, hy)
			p["hL"] = Vector3(_x0 + 0.20, hz + 0.36, -hy)
		"sleep":
			p["lean"] = sl + 2.0 * sin(ph)
			p["drop"] = 0.06
			p["bob"] = 0.01 * sin(ph)
			p["hk"] = 0.3
			p["fR"] = Vector3(0.05, 0, 0)
			p["fL"] = Vector3(-0.05, 0, 0)
			p["hR"] = Vector3(_x0 + 0.26, 0.40, 0.50)
			p["hL"] = Vector3(_x0 + 0.26, 0.40, -0.50)
	if bool(_spec.get("body_motion", false)) and anim in ["idle", "walk", "run"]:
		# Postawa wynika z anatomii źródła; stała wysokość dłoni 0.42 m
		# ciągnęła długie ramiona do podłoża i pogłębiała garb Wołka.
		var moving := anim != "idle"
		var amplitude := 0.07 if moving else 0.015
		for side in ["Right", "Left"]:
			var sg := 1.0 if side == "Right" else -1.0
			var rest := _sk.get_bone_global_rest(_b[side + "Hand"]).origin
			p["hR" if side == "Right" else "hL"] = rest + Vector3(0.05 + amplitude * sin(ph) * sg, 0.015, 0.0)
		p["pelvis_yaw"] = 3.0 * sin(ph) if moving else 0.0
		p["chest_yaw"] = -5.0 * sin(ph) if moving else 0.0
		p["sway"] = 0.012 * sin(ph) if moving else 0.0
		if moving: p["drop"] = 0.01
	return p

func _mix_p(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var o := {}
	for key in a:
		o[key] = lerp(a[key], b[key], k)
	return o

func _pose_biped(anim: String, delta: float) -> void:
	_sk.reset_bone_poses()
	var key := "walk" if anim == "run" else anim
	if not ["idle", "walk", "windup", "sleep", "air", "stun", "charge"].has(key):
		key = "idle"                                  # nazwa spoza zestawu (np. sprite bossa) — stoi
	if _airborne and not _dead:
		key = "air"                                   # skok / spadanie: poza lotu
	elif _sp == 4 and not _dead and _spec.get("stun", false):
		key = "stun"                                  # oszołomiony po uderzeniu szarżą
	elif _sp == 2 and not _dead and _spec.get("stun", false):
		key = "charge"                                # szarża: tułów nisko, ręce odrzucone, długie kroki
	if _w.is_empty():
		_w[key] = 1.0
	# wagi póz bazowych dążą do 1 dla bieżącej animacji (płynne przejścia idle ↔ chód ↔ zapowiedź ↔ sen)
	var kk := 1.0 - exp(-BLEND_RATE * delta)
	var sum := 0.0
	for n in ["idle", "walk", "windup", "sleep", "air", "stun", "charge"]:
		var cur := float(_w.get(n, 0.0))
		_w[n] = lerpf(cur, 1.0 if n == key else 0.0, kk)
		sum += float(_w[n])
	# klipy: drzewo ustawia biodra, tułów i nogi (chód wg fazy kroku; zapowiedź i cios — klip ataku); stopy, kolana i dłonie z klipu
	# zapamiętujemy jako cele IK
	var has_clip := _tree != null and clips_on and CharClips.has("walk", _cset)
	_ck = move_toward(_ck, 1.0 if (has_clip and not _dead) else 0.0, delta * 8.0)
	if key == "windup":
		_windup_t += delta
	elif float(_w["windup"]) < 0.01 * sum:
		_windup_t = 0.0
	var w_att := 0.0                                              # cios: klip przejmuje pozę na czas ciosu (szybko wchodzi, miękko wraca)
	if _catt and _clip == "attack" and not _dead:
		var ua := _clip_t / clip_duration("attack")
		w_att = smoothstep(0.0, 0.12, ua) * (1.0 - smoothstep(0.8, 1.0, ua)) * _ck
		_cprog["attack"] = ua
	var w_walk := float(_w["walk"]) / maxf(sum, 0.0001) * _ck * (1.0 - w_att)
	var w_wind := (float(_w["windup"]) / maxf(sum, 0.0001) * _ck * (1.0 - w_att)) if _catt else 0.0
	_cw.clear()
	if w_walk > 0.002:
		_cw["walk"] = w_walk
	if w_wind > 0.002:
		_cw["windup"] = w_wind
		_cprog["windup"] = _windup_t
	if w_att > 0.002:
		_cw["attack"] = w_att
	_cwalk = 0.0
	_carm = 0.0
	_crise = 0.0
	if not _cw.is_empty():
		_cwalk = w_walk + w_wind + w_att
		_carm = w_wind + w_att
		CharClips.drive(_tree, _cw, _phase / TAU, _t, _cprog)
		for side in ["Left", "Right"]:
			var cf := _gp(_b[side + "Foot"])
			_cfoot[side] = cf
			_cknee[side] = _gp(_b[side + "Leg"]).origin - (_gp(_b[side + "UpLeg"]).origin + cf.origin) * 0.5
			_chand[side] = _gp(_b[side + "Hand"]).origin
		_chips = _gp(_b["Hips"]).origin - _sk.get_bone_global_rest(_b["Hips"]).origin
		_crise = CharClips.param("walk", "rise", 0.0, _cset) * _sk.get_bone_global_rest(_b["Hips"]).origin.y * w_walk
	var p := {}
	var acc := 0.0
	for n in ["idle", "walk", "windup", "sleep", "air", "stun", "charge"]:
		var w := float(_w[n]) / maxf(sum, 0.0001)
		if w < 0.004:
			continue
		var bp := _biped_params(n)
		if n == "windup" and _catt and _ck > 0.0:
			bp = _mix_p(bp, _biped_params("idle"), _ck)       # zapowiedź z klipu: z profilu zostaje zwykła postawa, ruch niesie klip
		if p.is_empty():
			p = bp
			acc = w
		else:
			acc += w
			p = _mix_p(p, bp, w / acc)
	if p.is_empty():
		p = _biped_params("idle")
	if not _dead and not _motion_values.is_empty():
		p = _authored_biped(p)
		_cwalk *= 1.0 - _motion_weight
	if not _dead and _landing_t < Motion.recovery("landing"):
		var landing := Motion.sample("landing", _landing_t)
		p["drop"] = float(p["drop"]) + float(landing.get("drop", 0.0)) * _landing_strength
		p["lean"] = float(p["lean"]) + float(landing.get("lean", 0.0)) * _landing_strength
		# Tułów amortyzuje i wygasza lot, ale stopy mają kontakt już w klatce lądowania.
		p["fR"].y = 0.0
		p["fL"].y = 0.0
	_last_p = p.duplicate()
	var tilt := 0.0
	var lift := 0.0
	var amp := float(_spec.get("clip_amp", 1.0))
	var hx := _x0
	if _dead:
		var dd := _death_dur()
		var u := clampf(_dead_t / dd, 0.0, 1.0)
		var dk: Dictionary = _spec.get("death", {"dir": -1.0, "lean": 32.0, "tilt": 84.0})
		var dir := float(dk.get("dir", -1.0))                                          # −1: upadek twarzą w przód, +1: na plecy
		var dlean := float(dk.get("lean", 32.0))
		if not _dead_from.is_empty():
			p = _dead_from.duplicate()
		var jerk := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.14, 0.34, u))     # szarpnięcie w tył od trafienia
		var buckle := smoothstep(0.16, 0.6, u)                                         # kolana się uginają, ciało wiotczeje
		var topple := smoothstep(0.52, 1.0, u)                                         # przewraca się
		p["lean"] = lerp(p["lean"], -16.0, jerk) + dlean * buckle
		p["drop"] = lerp(p["drop"], 0.0, jerk) + 0.40 * buckle
		p["bob"] = 0.0
		var limp := 0.3 + 0.7 * buckle
		p["hR"] = (p["hR"] as Vector3).lerp(Vector3(hx + 0.34 * limp, 0.95 - 0.55 * buckle, 0.55), buckle * 0.9 + jerk * 0.3)
		p["hL"] = (p["hL"] as Vector3).lerp(Vector3(hx + 0.34 * limp, 0.95 - 0.55 * buckle, -0.55), buckle * 0.9 + jerk * 0.3)
		p["fR"] = (p["fR"] as Vector3).lerp(Vector3(0.16, 0.0, 0.0), buckle)
		p["fL"] = (p["fL"] as Vector3).lerp(Vector3(-0.20, 0.0, 0.0), buckle)
		tilt = deg_to_rad(float(dk.get("tilt", 84.0))) * dir * topple * topple   # wokół stóp (przyspiesza jak w grawitacji)
		lift = 0.22 * absf(sin(tilt))
		_sink(_dead_t - dd)
	elif _clip == "hit":
		var u := _clip_t / clip_duration("hit")
		var k := sin(PI * minf(u * 1.35, 1.0)) * (1.0 - u) * amp
		p["lean"] = float(p["lean"]) - 14.0 * k
		p["drop"] = float(p["drop"]) + 0.05 * k
		p["hk"] = 0.8 - 0.9 * k
		p["hR"] = (p["hR"] as Vector3) + Vector3(-0.16 * k, 0.10 * k, 0.0)
		p["hL"] = (p["hL"] as Vector3) + Vector3(-0.16 * k, 0.10 * k, 0.0)
	elif _clip == "attack" and _motion_weight < 0.001:
		var u := _clip_t / clip_duration("attack")
		var s_in := smoothstep(0.0, 0.26, u)
		var w := s_in * (1.0 - smoothstep(0.34, 1.0, u))                               # uderzenie szybko, powrót miękko
		if _catt:
			w *= 1.0 - _ck                                                             # cios z klipu: poza z kodu tylko, gdy klip wygasł
		var hy2 := float((_spec.get("prof", {}) as Dictionary).get("hy", 0.62))
		var ak := String(_spec.get("attack_kind", "smash"))
		# lean, drop, x ręki, wysokość ręki, rozstaw rąk (ułamek hy), stopa prawa, stopa lewa, głowa
		var A: Dictionary = {
			"cleave": [18.0, 0.10, 0.12, 1.15, 0.70, 0.14, -0.10, 0.8],
			"smash": [26.0, 0.16, 0.80, 0.45, 0.45, 0.20, -0.14, 0.8],
			"claw": [20.0, 0.10, 0.78, 1.10, 0.90, 0.22, -0.10, 0.8],
			"scream": [-26.0, 0.0, 0.25, 1.72, 0.90, 0.06, -0.06, 1.1],
			"grab": [16.0, 0.08, 0.95, 1.18, 0.40, 0.24, -0.12, 0.8],
		}
		var a: Array = A.get(ak, A["smash"])
		p["lean"] = lerp(float(p["lean"]), float(a[0]), w)
		p["drop"] = lerp(float(p["drop"]), float(a[1]), w)
		p["hR"] = (p["hR"] as Vector3).lerp(Vector3(_x0 + float(a[2]), float(a[3]), hy2 * float(a[4])), w)
		p["hL"] = (p["hL"] as Vector3).lerp(Vector3(_x0 + float(a[2]), float(a[3]), -hy2 * float(a[4])), w)
		if ak == "cleave":
			p["hR"] = (p["hR"] as Vector3).lerp(Vector3(_x0 + 0.85, 0.85, hy2 * 0.7), w)
		p["fR"] = (p["fR"] as Vector3).lerp(Vector3(float(a[5]), 0.0, 0.0), w * 0.8)
		p["fL"] = (p["fL"] as Vector3).lerp(Vector3(float(a[6]), 0.0, 0.0), w * 0.8)
		p["hk"] = lerp(float(p["hk"]), float(a[7]), w)
	if not _dead:
		_sink_y = 0.0
	_tilt.basis = Basis(Vector3.BACK, tilt)
	_tilt.position = Vector3(0.0, lift + _sink_y, 0.0)
	_apply_biped(p)

func _apply_biped(p: Dictionary) -> void:
	var hips: int = _b["Hips"]
	var body_motion := bool(_spec.get("body_motion", false))
	_shift_global(hips, Vector3(float(p["shift"]), -float(p["drop"]) + float(p["bob"]) + _crise, float(p["sway"])))
	var lean := deg_to_rad(float(p["lean"]))
	if body_motion:
		# Łańcuch ruchu: miednica -> kręgosłup -> klatka -> obręcz barkowa.
		# Jedna rotacja bioder zapadała całe ciało i nie dawała kontrrotacji.
		_rot_world(hips, Vector3.UP, deg_to_rad(float(p["pelvis_yaw"])))
		_rot_world(hips, Vector3.BACK, -lean * 0.25)
		for spine in ["Spine", "Spine1", "Spine2"]:
			_rot_world(_b[spine], Vector3.BACK, -lean * 0.25)
			_rot_world(_b[spine], Vector3.UP, deg_to_rad(float(p["chest_yaw"])) / 3.0)
	else:
		_rot_world(hips, Vector3.BACK, -lean)
	if bool(_spec.get("turn", false)):                            # jak postać gracza: tułów zwrócony ku kamerze (Char3D.BODY_YAW)
		_rot_world(_b["Spine"], Vector3.UP, deg_to_rad(BODY_YAW) * _cam_c)
	_rot_world(_b["Head"], Vector3.BACK, lean * float(p["hk"]))
	if not _dead and not _airborne:
		# Korekta bioder do zasięgu obu nóg; samo ograniczenie celu IK unosiłoby podporową stopę.
		var lower := 0.0
		for side in ["Right", "Left"]:
			var rest := _sk.get_bone_global_rest(_b[side + "Foot"])
			var off: Vector3 = p["fR"] if side == "Right" else p["fL"]
			var hip := _gp(_b[side + "UpLeg"]).origin
			var target := rest.origin + off
			target.y += _ground_y(side) - rest.origin.y
			if _cwalk > 0.0:
				target += (_cfoot[side] as Transform3D).origin - rest.origin
			if _foot_locks.has(side) and target.y <= _ground_y(side) + 0.015:
				var locked: Vector3 = _sk.global_transform.affine_inverse() * (_foot_locks[side] as Vector3)
				if locked.distance_to(target) < 0.55:
					target = locked
			var reach: float = (_leg_len[side][0] + _leg_len[side][1]) * 0.97
			var horizontal := Vector2(hip.x - target.x, hip.z - target.z).length_squared()
			var height := sqrt(maxf(reach * reach - horizontal, 0.0))
			lower = maxf(lower, hip.y - target.y - height)
		_shift_global(hips, Vector3(0.0, -minf(lower, 0.25), 0.0))
	for side in ["Right", "Left"]:
		var foot: int = _b[side + "Foot"]
		var rest := _sk.get_bone_global_rest(foot)
		var off: Vector3 = p["fR"] if side == "Right" else p["fL"]
		var target := rest.origin + off
		target.y += _ground_y(side) - rest.origin.y
		var fb := rest.basis
		var pole := Vector3(1.0, 0.1, 0.0)
		if _cwalk > 0.0:                                          # stopa i kolano z klipu (odchylenie od spoczynku niesie już wagę klipu)
			var cf: Transform3D = _cfoot[side]
			target += cf.origin - rest.origin
			target.y = maxf(target.y, _ground_y(side))
			fb = cf.basis
			var ck: Vector3 = _cknee[side]
			if ck.length() > 0.02:
				pole = pole.lerp(ck.normalized(), _cwalk)
		var grounded := not _dead and not _airborne and _inv_w < 0.01
		var planted := grounded and target.y <= _ground_y(side) + 0.015
		if planted:
			target.y = _ground_y(side)
			fb = rest.basis
			var normal: Vector3 = (ground_profile.get(side, {}) as Dictionary).get("normal", Vector3.UP)
			var local_normal := (_sk.global_transform.basis.inverse() * normal).normalized()
			fb = Basis(Quaternion(Vector3.UP, local_normal)) * fb
			var world_target := _sk.global_transform * target
			if not _foot_locks.has(side):
				_foot_locks[side] = world_target
			var locked: Vector3 = _sk.global_transform.affine_inverse() * (_foot_locks[side] as Vector3)
			if absf(locked.y - target.y) > 0.02:
				locked = target
				_foot_locks[side] = world_target
			# Skok pozycji, obrót albo przekroczenie zasięgu kończy podporę zamiast rozciągać kończynę.
			if locked.distance_to(target) < 0.55 and (absf(rotation.y) < 0.05 or absf(rotation.y + PI) < 0.05):
				target = locked
			else:
				_foot_locks.erase(side)
		else:
			_foot_locks.erase(side)
		# Cel ograniczamy zawsze, także przy proceduralnym kroku bez biblioteki klipów.
		if grounded:
			target.y = maxf(target.y, _ground_y(side))
		var tilt_f := 0.0 if planted else 0.2 * maxf(0.0, (target.y - _ground_y(side)) / 0.14)
		fb = Basis(Vector3.BACK, -tilt_f) * fb
		if grounded and _sole_points.has(side):
			var world := _sk.global_transform * target
			world.y = maxf(world.y, _sole_floor(side, fb))
			target = _sk.global_transform.affine_inverse() * world
		_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], foot, _leg_len[side][0], _leg_len[side][1], target, pole)
		if _foot_locks.has(side) and _gp(foot).origin.distance_to(target) > 0.015:
			# IK nie może utrzymać podpory poza zasięgiem: zwolnij kotwicę, nie deklaruj nieruchomej stopy.
			_foot_locks.erase(side)
		_set_global_basis(foot, fb)
		if grounded:
			for correction in 2:
				var penetration := _sole_penetration(side)
				if penetration < 0.001: break
				var world := _sk.global_transform * target
				world.y += penetration * 1.25
				target = _sk.global_transform.affine_inverse() * world
				_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], foot, _leg_len[side][0], _leg_len[side][1], target, pole)
				_set_global_basis(foot, fb)
				if _foot_locks.has(side): _foot_locks[side] = world
	for side in ["Right", "Left"]:
		var sg := 1.0 if side == "Right" else -1.0                # prawa ręka po stronie kamery (+z)
		var target: Vector3 = p["hR"] if side == "Right" else p["hL"]
		if _cwalk > 0.0:
			target += _chips                                      # ręce idą za biodrami z klipu (kołysanie kroku)
			if _carm > 0.0:
				target = target.lerp(_chand[side], _carm)         # zapowiedź i cios: dłoń tam, gdzie w klipie
		var elevation := smoothstep(_gp(_b[side + "Arm"]).origin.y - 0.12, _gp(_b[side + "Arm"]).origin.y + 0.45, target.y)
		var pole := Vector3(-0.4, -0.5, sg * 0.8)
		if body_motion:
			if _b.has(side + "Shoulder"):
				_rot_world(_b[side + "Shoulder"], Vector3.RIGHT, -sg * deg_to_rad(14.0) * elevation)
			pole = pole.lerp(Vector3(0.1, -0.35, sg * 0.9), elevation)
		_two_bone(_b[side + "Arm"], _b[side + "ForeArm"], _b[side + "Hand"], _arm_len[side][0], _arm_len[side][1], target, pole)
		if body_motion:
			var hand: int = _b[side + "Hand"]
			var wrist: float = p["wristR"] if side == "Right" else p["wristL"]
			var authored := Basis(Vector3.BACK, deg_to_rad(wrist)) * _sk.get_bone_global_rest(hand).basis
			var blend := _motion_weight if _motion_name in ["smash", "cleave"] else 0.0
			_set_global_basis(hand, _gp(hand).basis.slerp(authored, blend))
