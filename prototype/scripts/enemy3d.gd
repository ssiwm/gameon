extends Node3D
## Wróg jako prawdziwy model 3D w widoku 3D (view3d.gd). Model to rig Tripo z `tools/prep_enemy3d.py` (art/enemy3d/<rodzaj>.glb); pozę liczymy
## co klatkę z nazwy animacji 2D (sleep / idle / walk / run / windup), tak jak arkusze HD były wypiekane w `concept/monster_tripo_bake.py` —
## te same pozy (kąty tułowia, kroki, ręce), tylko w czasie rzeczywistym na szkielecie Mixamo (dwukostkowe IK jak w `char3d.gd`).
## Trzosek (czworonóg) odtwarza animację chodu z pliku, reszta póz to skalowanie. Oczy (żółto-pomarańczowe piksele tekstury) świecą emisją.
##
## Układ: Enemy3D (pozycja stóp, skala.x = ±1 odbicie) → pivot (skala dopasowana do rozmiaru sprite'a 2D) → model.
## Model w układzie Godota: +X to przód, Y w górę, Z do kamery (blenderowe −Y); stąd przeliczenia osi względem skryptu wypieku.

const DIR := "res://art/enemy3d/"
const PRE := "mixamorig_"
const PX := 1.8 / 22.0                     ## metrów na piksel świata (jak Level3D.PX)

## fit: [„height" | „length", rozmiar w pikselach świata] — jak w wypieku; frame_h: wysokość ramki sprite'a (Skoczek wisi u jej góry);
## cycle: okres cyklu kroku (s); prof: profil pozy (jak PROF w wypieku); yaw: obrót modelu (stopnie), by przód patrzył w +X.
const SPEC := {
	"wolek": {"fit": ["height", 32.0], "frame_h": 44.0, "cycle": 1.0, "prof": {}},
	"slepiec": {"fit": ["height", 27.0], "frame_h": 32.0, "cycle": 1.0, "prof": {"hy": 0.50, "hz": 0.35}},
	"podsluchacz": {"fit": ["height", 34.0], "frame_h": 40.0, "cycle": 1.0,
		"prof": {"lean": 4.0, "lean_walk": 6.0, "hy": 0.42, "hz": 0.55, "sleep_lean": 14.0, "windup": "point"}},
	"stalker": {"fit": ["height", 54.0], "frame_h": 60.0, "cycle": 1.1,
		"prof": {"lean": 5.0, "lean_walk": 8.0, "hy": 0.42, "hz": 0.62, "stride": 0.28, "windup": "reach"}},
	"skoczek": {"fit": ["height", 17.0], "frame_h": 26.0, "cycle": 0.5, "crawler": true},
	"trzosek": {"fit": ["length", 21.0], "frame_h": 22.0, "cycle": 0.55, "quad": true, "yaw": -90.0},
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
uniform vec4 mod = vec4(1.0);
uniform float eye_glow = 1.4;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	float eye = smoothstep(0.05, 0.075, h.x) * (1.0 - smoothstep(0.17, 0.2, h.x)) * smoothstep(0.55, 0.68, h.y) * smoothstep(0.5, 0.65, h.z);
	ALBEDO = c * clamp(mod.rgb, 0.0, 1.0);
	EMISSION = c * eye * eye_glow + max(mod.rgb - vec3(1.0), vec3(0.0)) * 0.45;
	//ALPHA
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).xyz;
	}
	if (has_orm) {
		vec4 o = texture(orm_tex, UV);
		AO = o.r;
		ROUGHNESS = o.g;
	} else {
		ROUGHNESS = 0.85;
	}
	METALLIC = 0.0;
}
"""

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
var _phase := 0.0
var _prev_anim := ""

static func has_model(k: String) -> bool:
	return SPEC.has(k) and ResourceLoader.exists(DIR + k + ".glb")

## Buduje model. translucent: materiał z przezroczystością (Stalker znika bez światła).
func setup(k: String, translucent := false) -> bool:
	kind = k
	_spec = SPEC.get(k, {})
	if _spec.is_empty():
		return false
	var ps := load(DIR + k + ".glb") as PackedScene
	if ps == null:
		return false
	_pivot = Node3D.new()
	add_child(_pivot)
	_model = ps.instantiate() as Node3D
	_pivot.add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	var mis := _model.find_children("*", "MeshInstance3D", true, false)
	if sks.is_empty() or mis.is_empty():
		return false
	_sk = sks[0]
	_mesh = mis[0]
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0]
	# skala: rozmiar modelu w spoczynku → rozmiar sprite'a 2D (jak w wypieku)
	var bb := _mesh.get_aabb()
	var fit: Array = _spec["fit"]
	var ext := bb.size.y if String(fit[0]) == "height" else maxf(bb.size.x, bb.size.z)
	_scale = float(fit[1]) * PX / maxf(ext, 0.001)
	_pivot.scale = Vector3.ONE * _scale
	var yaw := deg_to_rad(float(_spec.get("yaw", 0.0)))
	_pivot.rotation.y = yaw
	var c := bb.get_center()
	var hc := Basis(Vector3.UP, yaw) * c
	if _spec.get("quad", false) or _spec.get("crawler", false):
		_pivot.position = Vector3(-hc.x * _scale, 0.0, -hc.z * _scale)
	if not _spec.get("quad", false):
		for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
				"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
			var i := _sk.find_bone(PRE + n)
			if i < 0:
				return false
			_b[n] = i
		for side in ["Left", "Right"]:
			_leg_len[side] = [_rest_dist(side + "UpLeg", side + "Leg"), _rest_dist(side + "Leg", side + "Foot")]
			_arm_len[side] = [_rest_dist(side + "Arm", side + "ForeArm"), _rest_dist(side + "ForeArm", side + "Hand")]
		var hips_x := _sk.get_bone_global_rest(_b["Hips"]).origin.x
		_x0 = hips_x - 0.05
		if _spec.get("crawler", false):
			_x0 = c.x
		_pivot.position.x = -_x0 * _scale
	_prepare_materials(translucent)
	return true

func _rest_dist(a: String, b: String) -> float:
	return _sk.get_bone_global_rest(_b[a]).origin.distance_to(_sk.get_bone_global_rest(_b[b]).origin)

func _prepare_materials(translucent: bool) -> void:
	var sh := Shader.new()
	var code := SHADER
	code = code.replace("//RENDER", "render_mode blend_mix, depth_prepass_alpha;" if translucent else "")
	code = code.replace("//ALPHA", "ALPHA = clamp(mod.a, 0.0, 1.0);" if translucent else "")
	sh.code = code
	for i in _mesh.mesh.get_surface_count():
		var src := _mesh.mesh.surface_get_material(i)
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if src is StandardMaterial3D:
			var s := src as StandardMaterial3D
			sm.set_shader_parameter("albedo_tex", s.albedo_texture)
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

## anim: sleep | idle | walk | run | windup (nazwy z arkuszy 2D). flip: sprite odbity (patrzy w lewo). mod: modulate sprite'a.
func pose(delta: float, anim: String, flip: bool, mod: Color) -> void:
	_t += delta
	scale.x = -1.0 if flip else 1.0
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("mod", Vector4(mod.r, mod.g, mod.b, mod.a))
	var moving := anim == "walk" or anim == "run"
	if moving:
		_phase += delta * TAU / float(_spec.get("cycle", 1.0))
	if _spec.get("quad", false):
		_pose_quad(anim)
	elif _spec.get("crawler", false):
		_pose_crawler(anim)
	else:
		_pose_biped(anim)
	_prev_anim = anim

func _pose_quad(anim: String) -> void:
	var sy := 1.0
	var sz := 1.0
	var pitch := 0.0
	var t := 0.0
	if _ap != null:
		var names := _ap.get_animation_list()
		if _ap_name == "" and not names.is_empty():
			_ap_name = names[0]
			var a := _ap.get_animation(_ap_name)
			a.loop_mode = Animation.LOOP_LINEAR
	var len := 1.0
	if _ap != null and _ap_name != "":
		len = _ap.get_animation(_ap_name).length
	match anim:
		"run", "walk":
			t = fposmod(_phase / TAU, 1.0) * len
		"windup":                                  # skok: wyciągnięta faza kroku, nos w dół i drżące ściśnięcie przed odbiciem (bez spłaszczania)
			t = 0.25 * len
			sy = 0.94 + 0.012 * sin(_t * 42.0)
			sz = 1.04
			pitch = deg_to_rad(-5.0)
		"sleep":                                   # zwinięty: spłaszczony, powoli oddycha
			sy = 0.60 + 0.02 * sin(_t * 2.6)
		_:
			sy = 1.0 + 0.018 * sin(_t * 2.6)
	if _ap != null and _ap_name != "":
		_ap.assigned_animation = _ap_name
		_ap.seek(t, true)
	var yaw := deg_to_rad(float(_spec.get("yaw", 0.0)))
	_pivot.basis = Basis(Vector3.BACK, pitch) * Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(_scale, _scale * sy, _scale * sz))

func _pose_crawler(anim: String) -> void:
	_sk.reset_bone_poses()
	var hips: int = _b["Hips"]
	var ph := _t * TAU / 2.4
	var inverted := anim == "sleep"
	if anim == "run" or anim == "walk":
		_move_global(hips, Vector3(0.0, 0.03 * cos(2.0 * _phase), 0.0))
		for side in ["Right", "Left"]:
			var sw := sin(_phase + (0.0 if side == "Right" else PI))
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(-30.0 * sw))
			_rot_world(_b[side + "UpLeg"], Vector3.BACK, deg_to_rad(26.0 * sw))
	elif anim == "windup":
		_move_global(hips, Vector3(0.0, -0.18, 0.0))
		_rot_world(hips, Vector3.BACK, deg_to_rad(-22.0))
		for side in ["Right", "Left"]:
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(35.0))
	else:
		_move_global(hips, Vector3(0.0, 0.012 * sin(ph), 0.0))
	# „sleep": wisi pod sufitem do góry nogami — chwyty u górnej krawędzi ramki sprite'a
	if inverted:
		_pivot.rotation = Vector3(PI, 0.0, 0.0)
		_pivot.position.y = float(_spec["frame_h"]) * PX
	else:
		_pivot.rotation = Vector3.ZERO
		_pivot.position.y = 0.0

func _pose_biped(anim: String) -> void:
	_sk.reset_bone_poses()
	var prof: Dictionary = _spec.get("prof", {})
	var ph := _phase if (anim == "walk" or anim == "run") else _t * TAU / 2.4
	var l0: float = prof.get("lean", 12.0)
	var lw: float = prof.get("lean_walk", 14.0)
	var hy: float = prof.get("hy", 0.62)
	var hz: float = prof.get("hz", 0.42)
	var sl: float = prof.get("sleep_lean", 27.0)
	var stride: float = prof.get("stride", 0.22)
	var lean := l0
	var bob := 0.0
	var drop := 0.0
	# współrzędne celów w układzie Godota: x przód, y wysokość, z do kamery (prawa strona = +z)
	var feet := {"Right": Vector3.ZERO, "Left": Vector3.ZERO}
	var hands := {"Right": Vector3(_x0 + 0.05, hz, hy), "Left": Vector3(_x0 + 0.05, hz, -hy)}
	match anim:
		"idle":
			lean = l0 + 1.6 * sin(ph)
			bob = 0.012 * sin(ph)
			feet = {"Right": Vector3(0.04, 0, 0), "Left": Vector3(-0.04, 0, 0)}
			var sw := 0.06 * sin(ph)
			hands = {"Right": Vector3(_x0 + 0.05 + sw, hz, hy), "Left": Vector3(_x0 + 0.05 - sw, hz, -hy)}
		"walk", "run":
			lean = lw
			bob = 0.035 * cos(2.0 * ph)
			drop = 0.03
			for side in ["Right", "Left"]:
				var phk := ph + (0.0 if side == "Right" else PI)
				feet[side] = Vector3(-stride * cos(phk), 0.14 * maxf(0.0, sin(phk)), 0.0)
			var sw2 := 0.30 * sin(ph)
			var lift := 0.05 * absf(sw2)
			hands = {"Right": Vector3(_x0 + 0.05 + sw2, hz + lift, hy), "Left": Vector3(_x0 + 0.05 - sw2, hz + lift, -hy)}
		"windup":
			lean = -10.0
			drop = 0.04
			feet = {"Right": Vector3(0.12, 0, 0), "Left": Vector3(-0.12, 0, 0)}
			hands = {"Right": Vector3(_x0 + 0.10, 1.70, 0.40), "Left": Vector3(_x0 + 0.10, 1.70, -0.40)}
			var wk := String(prof.get("windup", ""))
			if wk == "point":                          # Podsłuchacz: ręka wskazuje, głowa do tyłu (krzyk)
				lean = -6.0
				hands = {"Right": Vector3(_x0 + 0.62, 1.15, 0.30), "Left": Vector3(_x0 + 0.05, hz, -hy)}
			elif wk == "reach":                        # Stalker: obie ręce wyciągnięte do przodu
				lean = 2.0
				hands = {"Right": Vector3(_x0 + 0.85, 1.30, 0.22), "Left": Vector3(_x0 + 0.85, 1.30, -0.22)}
		"sleep":
			lean = sl + 2.0 * sin(ph)
			drop = 0.06
			bob = 0.01 * sin(ph)
			feet = {"Right": Vector3(0.05, 0, 0), "Left": Vector3(-0.05, 0, 0)}
			hands = {"Right": Vector3(_x0 + 0.26, 0.40, 0.50), "Left": Vector3(_x0 + 0.26, 0.40, -0.50)}
	var hips: int = _b["Hips"]
	_move_global(hips, Vector3(0.0, -drop + bob, 0.0))
	_rot_world(hips, Vector3.BACK, -deg_to_rad(lean))
	_rot_world(_b["Head"], Vector3.BACK, deg_to_rad(lean) * (0.8 if anim != "sleep" else 0.3))
	for side in ["Right", "Left"]:
		var foot: int = _b[side + "Foot"]
		var rest := _sk.get_bone_global_rest(foot)
		var off: Vector3 = feet[side]
		var ankle := rest.origin + off
		_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], foot, _leg_len[side][0], _leg_len[side][1], ankle, Vector3(1.0, 0.1, 0.0))
		var tilt := 0.2 * maxf(0.0, off.y / 0.14)
		_set_global_basis(foot, Basis(Vector3.BACK, -tilt) * rest.basis)
	for side in ["Right", "Left"]:
		var sg := 1.0 if side == "Right" else -1.0                # prawa ręka po stronie kamery (+z)
		_two_bone(_b[side + "Arm"], _b[side + "ForeArm"], _b[side + "Hand"], _arm_len[side][0], _arm_len[side][1], hands[side], Vector3(-0.4, -0.5, sg * 0.8))
