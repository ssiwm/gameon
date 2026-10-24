extends SceneTree
## Regresja postoju: podparcie, płaszczyzna zgięcia kolan i ciągłość przejść, z klipami i bez.
## godot --headless --path prototype -s tools/test_standing_legs.gd
const Char3D := preload("res://scripts/char3d.gd")
const Motion := preload("res://scripts/weapon_motion.gd")
const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_hazmat", "male_medic", "female_medic"]
var c: Char3D
var ran := false
var failed := 0
var total := 0
var worst := {}
var worst_at := {}
var context := ""

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		if failed <= 20:
			print("FAIL standing: ", context, " ", label)

func bound(label: String, value: float, limit: float) -> void:
	if value > float(worst.get(label, 0.0)):
		worst_at[label] = context
	worst[label] = maxf(float(worst.get(label, 0.0)), value)
	check("%s %.6f <= %.6f" % [label, value, limit], is_finite(value) and value <= limit)

func reset() -> void:
	c.swing_t = -1.0
	c.reload_t = -1.0
	c.fire_t = -1.0
	c.gun_recoil_m = 0.0
	c.gun_recoil_rad = 0.0
	c._aw.clear()
	c._down = 0.0

func geometry(static_pose: bool, action: bool) -> void:
	var feet: Array[Vector3] = []
	for side in ["Left", "Right"]:
		var hip := c._gp(c._b[side + "UpLeg"])
		var knee := c._gp(c._b[side + "Leg"])
		var foot := c._gp(c._b[side + "Foot"])
		var rest := c._sk.get_bone_global_rest(c._b[side + "Foot"])
		var upper := knee.origin - hip.origin
		var lower := foot.origin - knee.origin
		bound("thigh_length_m", absf(upper.length() - c._leg_len[side][0]), 0.0005)
		bound("shin_length_m", absf(lower.length() - c._leg_len[side][1]), 0.0005)
		if not static_pose:
			continue
		feet.append(foot.origin)
		bound("ankle_height_m", absf(foot.origin.y - rest.origin.y), 0.003)
		var bend := rad_to_deg(upper.angle_to(lower))
		check("kolano bez przeprostu", bend >= (4.0 if action else 12.0))
		bound("knee_bend_deg", bend, 70.0 if action else 28.0)
		var normal := upper.cross(lower).normalized()
		var rest_hip := c._sk.get_bone_global_rest(c._b[side + "UpLeg"])
		var rest_knee := c._sk.get_bone_global_rest(c._b[side + "Leg"])
		var anatomy := (rest_knee.origin - rest_hip.origin).cross(rest.origin - rest_knee.origin).normalized()
		bound("thigh_roll_deg", rad_to_deg((hip.basis.orthonormalized() * rest_hip.basis.orthonormalized().inverse() * anatomy).angle_to(normal)), 1.0)
		bound("shin_roll_deg", rad_to_deg((knee.basis.orthonormalized() * rest_knee.basis.orthonormalized().inverse() * anatomy).angle_to(normal)), 1.0)
		var sole_up := foot.basis.orthonormalized() * rest.basis.orthonormalized().inverse() * Vector3.UP
		bound("sole_tilt_deg", rad_to_deg(sole_up.angle_to(Vector3.UP)), 1.0)
		var toe: int = c._sk.find_bone(Char3D.PRE + side + "ToeBase")
		if toe >= 0:
			bound("toe_height_m", absf(c._gp(toe).origin.y - c._sk.get_bone_global_rest(toe).origin.y), 0.003)
	if static_pose:
		bound("standing_stagger_m", absf(feet[0].x - feet[1].x), 0.13)
		check("stopy nie krzyżują się", feet[1].z - feet[0].z >= 0.24)
		bound("standing_width_m", feet[1].z - feet[0].z, 0.35)

func standing(fps: int, face: float) -> void:
	var dt := 1.0 / float(fps)
	for mode in ["hold", "fire", "reload", "chop"]:
		context = "%s clips=%s fps=%d face=%.0f %s" % [c._char_name, c.clips_on, fps, face, mode]
		reset()
		c.set_gun("kilof" if mode == "chop" else "m83")
		for i in fps:
			c.update(dt, "idle", face, Vector2(face, 0.0), 0.0)
		var anchor := [c._gp(c._b["LeftFoot"]).origin, c._gp(c._b["RightFoot"]).origin]
		for i in fps:
			var u := float(i) / float(fps - 1)
			var angle := deg_to_rad(-80.0 + 165.0 * u)
			c.swing_t = u if mode == "chop" else -1.0
			c.reload_t = u if mode == "reload" else -1.0
			c.fire_t = fposmod(u, 0.11) if mode == "fire" else -1.0
			var recoil := Motion.recoil_at("m83", c.fire_t) if mode == "fire" else Vector2.ZERO
			c.gun_recoil_m = recoil.x
			c.gun_recoil_rad = recoil.y
			c.update(dt, "idle", face, Vector2(cos(angle) * face, -sin(angle)), 0.0)
			geometry(true, mode != "hold")
			for j in 2:
				var foot := c._gp(c._b[("Left" if j == 0 else "Right") + "Foot"]).origin
				bound("planted_drift_m", foot.distance_to(anchor[j]), 0.003)

func transitions(fps: int) -> void:
	reset()
	c.set_gun("m83")
	var dt := 1.0 / float(fps)
	var previous := {}
	for state in ["idle", "run", "idle", "crouch", "idle", "jump", "fall", "idle", "down", "idle"]:
		var settle_time := 0.0
		for i in (ceili(1.5 * fps) if state == "idle" else fps):
			c.air_vy = -200.0 if state == "jump" else 250.0
			c.update(dt, state, 1.0, Vector2.RIGHT, 95.0 if state == "run" else 0.0)
			settle_time = settle_time + dt if state == "idle" and c._down < 0.001 else 0.0
			geometry(false, false)
			for bone in ["Hips", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]:
				var pos := c._gp(c._b[bone]).origin
				# Po zatrzymaniu lub zakończeniu wstawania musi wygasnąć resztkowa waga
				# klipu, bez późnego skoku podparcia przy progu 0.995.
				if previous.has(bone) and settle_time >= 0.4:
					context = "%s clips=%s fps=%d %s frame=%d %s" % [c._char_name, c.clips_on, fps, state, i, bone]
					bound("settling_speed_m_s", pos.distance_to(previous[bone]) / dt, 0.8)
				previous[bone] = pos
	geometry(true, false)

func _process(_delta: float) -> bool:
	if ran:
		return true
	ran = true
	c = Char3D.new()
	root.add_child(c)
	check("model MPFB", c.setup("male_scav", "m83"))
	c._set_on_screen(true)
	for look in LOOKS:
		check("wygląd " + look, c.set_look(look))
		for clips in [true, false]:
			c.clips_on = clips
			for fps in [30, 60, 120]:
				for face in [1.0, -1.0]:
					standing(fps, face)
				transitions(fps)
		print("STANDING ", look)
	for label in worst:
		print("STANDING max %s %.6f: %s" % [label, worst[label], worst_at.get(label, "")])
	print("PASS standing legs (%d checks)" % total if failed == 0 else "FAIL standing legs (%d/%d failed)" % [failed, total])
	quit(0 if failed == 0 else 1)
	return true
