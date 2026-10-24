extends SceneTree
## Kontakt dłoni i anatomia ramion w proceduralnych pozach TPP, w tym skrajne kąty, zwrot, przeładowanie i kilof.
## godot --headless --path prototype -s tools/test_weapon_grips.gd → PASS
class GripChar extends "res://scripts/char3d.gd":
	var targets := {}
	func _arm_ik(side: String, target: Vector3, pole: Vector3) -> void:
		targets[side] = target
		super._arm_ik(side, target, pole)

const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_hazmat", "male_medic", "female_medic"]
const GUNS := ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6", "maczeta", "kilof"]
const AIMS := [-80, -50, 0, 50, 85]
var c: GripChar
var failures := 0
var samples := 0
var worst := {}
var ran := false

func _initialize() -> void:
	c = GripChar.new()
	root.add_child(c)
	if not c.setup("male_scav", "m83"):
		quit(1)
	c._set_on_screen(true)

func check(value: float, limit: float, kind: String, at: String) -> void:
	if value > float(worst.get(kind, [0.0, ""])[0]):
		worst[kind] = [value, at]
	if not is_finite(value) or value > limit:
		failures += 1
		if failures <= 15:
			print("FAIL %s %.5f > %.5f: %s" % [kind, value, limit, at])

func sample(at: String) -> void:
	for side in c.targets:
		var arm := c._gp(c._b[side + "Arm"]).origin
		var elbow := c._gp(c._b[side + "ForeArm"]).origin
		var hand := c._gp(c._b[side + "Hand"])
		var label: String = at + " " + side
		check(hand.origin.distance_to(c.targets[side]), 0.005, "wrist_gap_m", label)
		check(absf(arm.distance_to(elbow) - c._arm_len[side][0]), 0.0005, "upper_length_error_m", label)
		check(absf(elbow.distance_to(hand.origin) - c._arm_len[side][1]), 0.0005, "forearm_length_error_m", label)
		if side == "Right" or c._gun_key != "maczeta":
			var axes: Basis = hand.basis * (c._hand[side]["fix"] as Basis).inverse()
			check(rad_to_deg((hand.origin - elbow).angle_to(axes.x)), 90.0, "wrist_flex_deg", label)
			check(rad_to_deg((elbow - arm).angle_to(hand.origin - elbow)), 146.0, "elbow_bend_deg", label)
		samples += 1

func reset_actions() -> void:
	c.reload_t = -1.0
	c.cycle_t = -1.0
	c.swing_t = -1.0
	c.gun_kick_px = 0.0
	c.recoil_px = 0.0
	c.targets.clear()

## Rzeczywisty przebieg klatek: sam kontakt w kilku pozach nie wykrywa przeskoku głębokości IK.
func continuity() -> void:
	for look in ["male_scav", "female_medic"]:
		c.set_look(look)
		for gun in ["m83", "p64", "srut8", "hkm9", "kilof"]:
			c.set_gun(gun)
			for mode in ["sweep", "turn", "action"]:
				reset_actions()
				for i in 40:
					c.update(1.0 / 60.0, "crouch", 1.0, Vector2.RIGHT, 0.0)
				var previous := c._gun.position
				for i in 180:
					var u := float(i) / 179.0
					var angle := deg_to_rad(-80.0 + 165.0 * sin(u * PI)) if mode == "sweep" else 0.0
					var face := -1.0 if mode == "turn" and i >= 90 else 1.0
					if mode == "action":
						if gun == "kilof":
							c.swing_t = u
						else:
							c.reload_t = u
					c.update(1.0 / 60.0, "crouch", face, Vector2(cos(angle) * face, -sin(angle)), 0.0)
					var at := "%s %s %s frame=%d" % [look, gun, mode, i]
					if i > 20:
						check(c._gun.position.distance_to(previous), 0.12, "gun_frame_step_m", at)
					sample(at)
					previous = c._gun.position

func _process(_dt: float) -> bool:
	if ran:
		return true
	ran = true
	for look in LOOKS:
		c.set_look(look)
		for gun in GUNS:
			c.set_gun(gun)
			for anim in ["idle", "run", "crouch"]:
				for deg in AIMS:
					var angle := deg_to_rad(float(deg))
					for face in [1.0, -1.0]:
						reset_actions()
						var aim := Vector2(cos(angle) * face, -sin(angle))
						var at := "%s %s %s %d° %+.0f" % [look, gun, anim, deg, face]
						for i in 24:
							c.update(1.0 / 60.0, anim, face, aim, 95.0 if anim == "run" else 0.0)
						sample(at)
						if anim == "run":
							continue
						for j in 21:
							var u := float(j) / 20.0
							if gun in ["maczeta", "kilof"]:
								c.swing_t = u
							else:
								c.reload_t = u
							c.update(1.0 / 60.0, anim, face, aim, 0.0)
							sample(at + " action=%.2f" % u)
						reset_actions()
						if gun in ["srut8", "ciegno6"]:
							for j in 21:
								c.cycle_t = float(j) / 20.0
								c.update(1.0 / 60.0, anim, face, aim, 0.0)
								sample(at + " cycle=%.2f" % c.cycle_t)
							reset_actions()
			# Cały obrót, a nie wyłącznie poza po zatrzymaniu twarzą w lewo.
			reset_actions()
			for i in 24:
				c.update(1.0 / 60.0, "idle", 1.0, Vector2.RIGHT, 0.0)
			for i in 12:
				c.update(1.0 / 60.0, "idle", -1.0, Vector2.LEFT, 0.0)
				sample("%s %s turn frame=%d" % [look, gun, i])
		print("GRIPS ", look, " samples=", samples)
	continuity()
	for kind in worst:
		print("GRIPS max %s %.5f: %s" % [kind, worst[kind][0], worst[kind][1]])
	print("PASS weapon grips (%d hand samples)" % samples if failures == 0 else "FAIL weapon grips (%d failures)" % failures)
	quit(0 if failures == 0 else 1)
	return true
