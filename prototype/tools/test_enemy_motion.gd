extends SceneTree
## Regresje ruchu: prędkość, podparcie, zasięg kończyn, zwrot i pełna śmierć każdego modelu.
const Enemy := preload("res://scripts/enemy3d.gd")
const Defs := preload("res://scripts/enemy_defs.gd")
var ran := false
var failed := 0
var total := 0

func geometry(e: Node3D, kind: String) -> void:
	var sk: Skeleton3D = e.get("_sk")
	var bones: Dictionary = e.get("_b")
	if sk == null or not bones.has("RightFoot"): return
	for side in ["Right", "Left"]:
		var hip: Transform3D = e.call("_gp", bones[side + "UpLeg"])
		var knee: Transform3D = e.call("_gp", bones[side + "Leg"])
		var foot: Transform3D = e.call("_gp", bones[side + "Foot"])
		var lengths: Array = e.get("_leg_len")[side]
		check(kind + " thigh preserved", absf(hip.origin.distance_to(knee.origin) - lengths[0]) < 0.001)
		check(kind + " shin preserved", absf(knee.origin.distance_to(foot.origin) - lengths[1]) < 0.001)
		var locks: Dictionary = e.get("_foot_locks")
		if locks.has(side):
			var error := (sk.global_transform * foot.origin).distance_to(locks[side])
			check(kind + " stance drift=" + str(error), error < 0.04)

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		if failed < 25: print("FAIL enemy motion: ", label)

func _process(_dt: float) -> bool:
	if ran: return false
	ran = true
	for kind in Enemy.SPEC:
		var e: Node3D = Enemy.new()
		root.add_child(e)
		check(kind + " setup", e.setup(kind))
		var reference: float = maxf(float((Defs.DEFS.get(kind, {}) as Dictionary).get("speed", 95.0)), 1.0)
		for fps in [30, 60, 120]:
			var dt := 1.0 / float(fps)
			for rate in [0.0, 0.25, 1.0, 1.5]:
				e.set("_phase", 0.0)
				for f in fps:
					e.position.x += reference * rate * Enemy.PX * dt
					e.pose(dt, "walk", false, Color.WHITE, 0.0, 1, true, 0.0, 0, false, reference * rate)
					if f % 10 == 0: geometry(e, kind)
				var expected: float = TAU / float(Enemy.SPEC[kind].get("cycle", 1.0)) * rate
				check("%s %d fps rate=%s" % [kind, fps, rate], absf(float(e.get("_phase")) - expected) < 0.0001)
		var sk: Skeleton3D = e.get("_sk")
		var bones: Dictionary = e.get("_b")
		if not Enemy.SPEC[kind].has("deform"):
			e.pose(0.04, "idle", true, Color.WHITE)
			check(kind + " continuous turn", e.rotation.y < -0.1 and e.rotation.y > -PI + 0.1)
			for f in 30: e.pose(1.0 / 60.0, "idle", true, Color.WHITE)
			check(kind + " turn completes", absf(e.rotation.y + PI) < 0.001 and e.scale.x > 0.0)
			for f in 30: e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
		if sk != null and bones.has("RightFoot"):
			for anim in ["idle", "windup"]:
				for f in 60: e.pose(1.0 / 60.0, anim, false, Color.WHITE)
				for side in ["Right", "Left"]:
					var foot: Transform3D = e.call("_gp", bones[side + "Foot"])
					var rest := sk.get_bone_global_rest(bones[side + "Foot"])
					check(kind + " ankle finite " + anim, foot.origin.is_finite())
					if not Enemy.SPEC[kind].get("crawler", false):
						check(kind + " planted ankle " + anim + " error=" + str(foot.origin.y - rest.origin.y), absf(foot.origin.y - rest.origin.y) < 0.03)
			if kind in ["slepiec", "stalker"]:
				e.trigger("attack")
				for f in 12: e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
				var p: Dictionary = e.get("_last_p")
				check(kind + " attack lean", absf(float(p["lean"])) < 30.0)
				for side in ["Right", "Left"]:
					var hand: Transform3D = e.call("_gp", bones[side + "Hand"])
					check(kind + " attack hand height", hand.origin.y > 0.75)
			if not Enemy.SPEC[kind].get("crawler", false):
				var normal := Vector3(0.10, 0.995, 0.0).normalized()
				e.set("ground_profile", {"Right": {"height": 0.08, "normal": normal}, "Left": {"height": 0.02, "normal": normal}})
				for f in 90: e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
				for side in ["Right", "Left"]:
					var foot: Transform3D = e.call("_gp", bones[side + "Foot"])
					var rest := sk.get_bone_global_rest(bones[side + "Foot"])
					var expected_y: float = rest.origin.y + (0.08 if side == "Right" else 0.02) / float(e.get("_scale"))
					check(kind + " uneven ground height", absf(foot.origin.y - expected_y) < 0.03)
					var up := (sk.global_transform.basis * foot.basis * rest.basis.inverse() * Vector3.UP).normalized()
					check(kind + " ground normal", up.angle_to(normal) < 0.02)
				e.set("ground_profile", {})
		e.die()
		check(kind + " death remains visible", not bool(e.get("finished")))
		for f in 15: e.pose(1.0 / 60.0, "death", false, Color.WHITE)
		check(kind + " death not cut short", not bool(e.get("finished")))
		for f in 180: e.pose(1.0 / 60.0, "death", false, Color.WHITE)
		check(kind + " death finishes", bool(e.get("finished")))
		e.revive()
		check(kind + " revive", not bool(e.get("finished")))
		e.free()
	print("%s enemy motion: %d checks, %d failed" % ["PASS" if failed == 0 else "FAIL", total, failed])
	quit(0 if failed == 0 else 1)
	return false
