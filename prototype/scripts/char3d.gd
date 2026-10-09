extends Node2D
## Postać 3D renderowana w czasie rzeczywistym do tekstury (spike „3D w 2D”).
##
## Model z rigiem Mixamo (art/char3d/*.glb, patrz tools/prep_char3d.py) żyje w małym SubViewport z kamerą
## ortogonalną patrzącą z boku; wynik wyświetla zwykły Sprite2D (obrys + oświetlenie 2D robi gra).
## Pozy to czysty kod: nogi i ręce rozwiązuje dwukostkowe IK, więc broń w obu dłoniach pasuje do KAŻDEGO kąta
## celowania, animacji i broni (chwyty z art/char3d/gun_*.json). Wszystko czyta tylko stan zreplikowany w graczu
## (animacja, aim_dir, kierunek), więc każdy peer widzi to samo; nic tu nie rozstrzyga gameplayu.
##
## Układ: model patrzy w +X, kamera stoi na +Z (bliższa jest prawa strona postaci), stopy w y = 0.
## Odbicie (patrzenie w lewo) to flip_h na sprite'ie — jak w arkuszach 2D.

const CHAR_H_M := 1.8                       ## wysokość postaci odniesienia (m)
const CHAR_H_WP := 22.0                     ## ... w pikselach świata
const WP_PER_M := CHAR_H_WP / CHAR_H_M
const SS := 4                               ## pikseli renderu na piksel świata (jak arkusze HD postaci)
const FRAME_WP := Vector2(44.0, 44.0)       ## ramka w pikselach świata (zapas na broń podniesioną i wyciągniętą)
const CAM_Y := 1.25                         ## wysokość środka ramki (m)
const ORIGIN_X := 0.163                     ## oś ciała (m) — biodra w pozie spoczynkowej
const PRE := "mixamorig_"

const OUTLINE_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.078, 0.055, 0.094, 1.0);
uniform float width = 2.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = 0.0;
	for (int r = 1; r <= 2; r++) {
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			a = max(a, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * (float(r) * 0.5)).a);
		}
	}
	a = smoothstep(0.1, 0.7, a);
	COLOR = vec4(mix(outline_color.rgb, c.rgb / max(c.a, 0.001), c.a), max(a, c.a));
}
"""

var _vp: SubViewport
var _cam: Camera3D
var _sprite: Sprite2D
var _root3d: Node3D
var _sk: Skeleton3D
var _gun: Node3D
var _gun_info := {"rear": Vector3.ZERO, "fore": Vector3(0.35, 0.03, 0.0), "muzzle": Vector3(0.67, 0.08, 0.0)}   ## w układzie Godota (x, y w górę, z do kamery)
var _b := {}                                 ## nazwa kości → indeks
var _leg_len := {}                           ## długości [udo, goleń] (m)
var _arm_len := {}                           ## długości [ramię, przedramię] (m)
var _time := 0.0
var _phase := 0.0
var _squash := Vector2.ONE

## Wyniki ostatniej klatki, w pikselach świata względem stóp (z uwzględnieniem odbicia) — dla efektów.
var muzzle_px := Vector2.ZERO
var grip_px := Vector2.ZERO
var ready_ok := false

func setup(char_path: String, gun_path := "") -> bool:
	if not ResourceLoader.exists(char_path):
		return false
	var scene: Node = (load(char_path) as PackedScene).instantiate()
	_vp = SubViewport.new()
	_vp.name = "Vp"
	_vp.size = Vector2i(int(FRAME_WP.x) * SS, int(FRAME_WP.y) * SS)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	_root3d.add_child(scene)
	_sk = scene.find_child("Skeleton3D", true, false)
	if _sk == null:
		return false
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = FRAME_WP.y / WP_PER_M
	_cam.position = Vector3(ORIGIN_X, CAM_Y, 6.0)
	_cam.near = 0.5
	_cam.far = 20.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	_cam.environment = env
	_root3d.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.96, 0.9)
	_root3d.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.7, -0.2, -0.4), Vector3.UP)
	fill.light_energy = 0.28
	fill.light_color = Color(0.6, 0.7, 1.0)
	_root3d.add_child(fill)

	_sprite = Sprite2D.new()
	_sprite.name = "Body3D"
	_sprite.texture = _vp.get_texture()
	_sprite.scale = Vector2.ONE / float(SS)
	_sprite.position = Vector2(0.0, -CAM_Y * WP_PER_M)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("width", 2.0)
	_sprite.material = mat
	add_child(_sprite)

	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
			"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		_b[n] = _sk.find_bone(PRE + n)
	for side in ["Left", "Right"]:
		_leg_len[side] = [_rest_dist(side + "UpLeg", side + "Leg"), _rest_dist(side + "Leg", side + "Foot")]
		_arm_len[side] = [_rest_dist(side + "Arm", side + "ForeArm"), _rest_dist(side + "ForeArm", side + "Hand")]
	if gun_path != "" and ResourceLoader.exists(gun_path):
		_gun = (load(gun_path) as PackedScene).instantiate()
		_root3d.add_child(_gun)
		_load_gun_info(gun_path.get_basename() + ".json")
	ready_ok = true
	return true

func set_gun(gun_path: String) -> void:
	if _gun != null:
		_gun.queue_free()
		_gun = null
	if gun_path != "" and ResourceLoader.exists(gun_path):
		_gun = (load(gun_path) as PackedScene).instantiate()
		_root3d.add_child(_gun)
		_load_gun_info(gun_path.get_basename() + ".json")

func _load_gun_info(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for k in ["rear", "fore", "muzzle"]:
		var a: Array = d[k]
		_gun_info[k] = Vector3(float(a[0]), float(a[2]), -float(a[1]))      # Blender (x, y, z) → Godot (x, z, −y)

func _rest_dist(a: String, b: String) -> float:
	return _sk.get_bone_global_rest(_b_idx(a)).origin.distance_to(_sk.get_bone_global_rest(_b_idx(b)).origin)

func _b_idx(n: String) -> int:
	return _sk.find_bone(PRE + n)

# ---------------------------------------------------------------- narzędzia kostne

func _gp(i: int) -> Transform3D:
	return _sk.get_bone_global_pose(i)

func _set_global_basis(i: int, gb: Basis) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_rotation(i, (pb.inverse() * gb).orthonormalized().get_rotation_quaternion())

## Obraca kość (i całe jej poddrzewo) wokół jej własnego początku o kąt wokół osi świata.
func _rot_world(i: int, axis: Vector3, ang: float) -> void:
	_set_global_basis(i, Basis(axis, ang) * _gp(i).basis)

## Kość i kieruje się na punkt target (jej dziecko child leży na osi kości).
func _point_bone(i: int, child: int, target: Vector3) -> void:
	var g := _gp(i)
	var from := (_gp(child).origin - g.origin).normalized()
	var to := (target - g.origin).normalized()
	if from.dot(to) > 0.99999:
		return
	_set_global_basis(i, Basis(Quaternion(from, to)) * g.basis)

## Dwukostkowe IK: staw środkowy tak, by koniec sięgał celu; pole = kierunek wygięcia (łokieć / kolano).
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

## anim: idle | run | jump | fall | crouch | crouch_walk | down. aim: kierunek celowania na ekranie (y w dół).
## speed: |prędkość pozioma| w px/s (tempo kroku). kick: odrzut broni 0..1 (cofnięcie wzdłuż lufy).
func update(delta: float, anim: String, facing: float, aim: Vector2, speed := 0.0, kick := 0.0, armed := true, tint := Color.WHITE) -> void:
	if not ready_ok:
		return
	_time += delta
	_sprite.flip_h = facing < 0.0
	_sprite.modulate = tint
	_sk.reset_bone_poses()
	var ax := absf(aim.x)
	var theta := atan2(-aim.y, maxf(ax, 0.0001))               # kąt w górę od poziomu; ax≥0 (lustro załatwia flip_h)
	if ax < 0.05:
		theta = PI * 0.5 * signf(-aim.y)
	theta = clampf(theta, deg_to_rad(-80.0), deg_to_rad(85.0))
	_pose_body(delta, anim, speed, theta)
	if armed and anim != "down":
		_pose_arms(theta, kick)
	else:
		_pose_arms_relaxed()
	_gun_visible(armed and anim != "down")
	_squash = _squash.lerp(Vector2.ONE, minf(delta * 14.0, 1.0))

func _gun_visible(v: bool) -> void:
	if _gun != null:
		_gun.visible = v

func _pose_body(delta: float, anim: String, speed: float, theta: float) -> void:
	var hips := _b["Hips"] as int
	var rest_h := _sk.get_bone_rest(hips).origin
	var run := anim == "run" or anim == "crouch_walk"
	var crouch := anim == "crouch" or anim == "crouch_walk"
	if run:
		_phase += delta * clampf(speed / 95.0, 0.4, 1.4) * TAU * 2.0
	var lean := 4.0
	var drop := 0.0
	var bob := 0.0
	if anim == "idle":
		bob = -0.006 * sin(_time * 2.4)
		lean = 4.0 + 0.8 * sin(_time * 2.4)
	elif anim == "run":
		lean = 13.0
		bob = -0.035 * absf(sin(_phase))
	elif anim == "jump":
		lean = 8.0
	elif anim == "fall":
		lean = 2.0
	elif crouch:
		lean = 20.0
		drop = 0.30
		bob = (0.012 * sin(_phase * 2.0)) if run else 0.0
	if anim == "down":
		_sk.set_bone_pose_position(hips, rest_h + Vector3(0.0, -0.62, 0.0))
		_rot_world(hips, Vector3.BACK, -PI * 0.5)
		return
	_sk.set_bone_pose_position(hips, rest_h + Vector3(0.0, -drop + bob, 0.0))
	_rot_world(hips, Vector3.BACK, -deg_to_rad(lean))
	# tułów zwraca się ku kamerze (broń po bliższej stronie) i pochyla się za celem
	_rot_world(_b["Spine"], Vector3.UP, deg_to_rad(-22.0))
	for n in ["Spine", "Spine1", "Spine2"]:
		_rot_world(_b[n], Vector3.BACK, theta * 0.13 + deg_to_rad(lean) * 0.12)
	_rot_world(_b["Head"], Vector3.BACK, theta * 0.2 - deg_to_rad(lean) * 0.5)
	_pose_legs(anim, run, crouch)

func _pose_legs(anim: String, run: bool, crouch: bool) -> void:
	var gy := 0.077                                              # wysokość kostki na podłożu
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Right" else -1.0
		var rest_foot := _sk.get_bone_global_rest(_b[side + "Foot"]).origin
		var off := Vector3.ZERO
		var tilt := 0.0
		var ph := _phase + (0.0 if side == "Right" else PI)
		if anim == "idle":
			off = Vector3(0.12 * sgn * 0.8, 0.0, 0.0)
		elif anim == "run":
			off = Vector3(0.34 * sin(ph), 0.17 * maxf(0.0, cos(ph)), 0.0)
			tilt = deg_to_rad(-14.0) * maxf(0.0, cos(ph))
		elif anim == "jump":
			off = Vector3(0.28 if sgn > 0 else -0.12, 0.30 if sgn > 0 else 0.16, 0.0)
			tilt = deg_to_rad(-14.0)
		elif anim == "fall":
			off = Vector3(0.10 if sgn > 0 else -0.08, 0.14 if sgn > 0 else 0.22, 0.0)
		elif anim == "crouch":
			off = Vector3(0.18 if sgn > 0 else -0.14, 0.0, 0.0)
		elif anim == "crouch_walk":
			off = Vector3(0.18 * sin(ph) + (0.1 if sgn > 0 else -0.1), 0.07 * maxf(0.0, cos(ph)), 0.0)
		var target := Vector3(ORIGIN_X + off.x - 0.0, gy + off.y, rest_foot.z)
		_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], _b[side + "Foot"], _leg_len[side][0], _leg_len[side][1], target, Vector3(1.0, 0.0, 0.0))
		# stopa płasko (z lekkim obrotem czubka)
		var rest_gb := _sk.get_bone_global_rest(_b[side + "Foot"]).basis
		_set_global_basis(_b[side + "Foot"], Basis(Vector3.BACK, tilt) * rest_gb)

## Chwyt dwuręczny: prawa ręka (bliższa) trzyma chwyt pistoletowy, lewa — łoże; broń obraca się wokół barku.
func _pose_arms(theta: float, kick: float) -> void:
	var sr := _gp(_b["RightArm"]).origin
	var sl := _gp(_b["LeftArm"]).origin
	var dirv := Vector3(cos(theta), sin(theta), 0.0)
	var up := Vector3(-sin(theta), cos(theta), 0.0)
	var fore_d: float = (_gun_info["fore"] as Vector3).x
	var radial := 0.30 + 0.0
	var gun_b := Basis(Vector3.BACK, theta)
	var rear := Vector3.ZERO
	var fore := Vector3.ZERO
	var reach_l: float = _arm_len["Left"][0] + _arm_len["Left"][1]
	for k in 8:                                                  # wsuń broń ku ciału, aż lewa ręka dosięgnie łoża
		rear = sr + dirv * radial - up * 0.11 + Vector3(0.0, 0.0, -0.13)
		rear -= dirv * (kick * 0.05)
		fore = rear + gun_b * (_gun_info["fore"] as Vector3)
		if fore.distance_to(sl) <= reach_l * 0.97:
			break
		radial -= 0.035
	var gx := Transform3D(gun_b, rear)
	if _gun != null:
		_gun.transform = gx
	_two_bone(_b["RightArm"], _b["RightForeArm"], _b["RightHand"], _arm_len["Right"][0], _arm_len["Right"][1], rear, Vector3(-0.35, -1.0, 0.55))
	_two_bone(_b["LeftArm"], _b["LeftForeArm"], _b["LeftHand"], _arm_len["Left"][0], _arm_len["Left"][1], fore, Vector3(-0.25, -1.0, -0.4))
	# dłonie wyrównane do broni
	_set_global_basis(_b["RightHand"], gx.basis * Basis(Vector3.FORWARD, deg_to_rad(8.0)))
	_set_global_basis(_b["LeftHand"], gx.basis)
	var m := gx * (_gun_info["muzzle"] as Vector3)
	muzzle_px = _to_px(m)
	grip_px = _to_px(rear)

func _pose_arms_relaxed() -> void:
	if _gun != null:
		_gun.visible = false
	muzzle_px = Vector2(0.0, -10.0)
	grip_px = muzzle_px

## Punkt 3D (m) → piksele świata względem stóp, z odbiciem.
func _to_px(p: Vector3) -> Vector2:
	var fl := -1.0 if _sprite.flip_h else 1.0
	return Vector2((p.x - ORIGIN_X) * WP_PER_M * fl, -p.y * WP_PER_M)
