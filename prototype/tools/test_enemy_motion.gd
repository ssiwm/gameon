extends SceneTree
## Regresje ruchu: prędkość, podparcie, zasięg kończyn, zwrot i pełna śmierć każdego modelu.
const Enemy := preload("res://scripts/enemy3d.gd")
const Defs := preload("res://scripts/enemy_defs.gd")
const Motion := preload("res://scripts/enemy_motion.gd")
var ran := false
var failed := 0
var total := 0

func charge_motion(kind: String) -> void:
	if kind not in ["wolek", "rzeznik"]: return
	var reference: float = Defs.DEFS[kind].speed
	var multiplier := 3.2 if kind == "rzeznik" else 2.4
	for fps in [30, 60, 120]:
		var e := Enemy.new()
		root.add_child(e)
		e.setup(kind)
		var low := INF
		var high := -INF
		for frame in fps * 2:
			e.position.x += reference * multiplier * Enemy.PX / fps
			e.pose(1.0 / fps, "walk", false, Color.WHITE, 0.0, 1, true, 0.0, 2, false, reference * multiplier)
			if frame >= fps:
				var p: Dictionary = e.get("_last_p")
				low = minf(low, (p["fR"] as Vector3).x)
				high = maxf(high, (p["fR"] as Vector3).x)
			if frame % 10 == 0: geometry(e, kind)
		var distance := 2.0 * (high - low) * float(e.get("_scale"))
		check(kind + " charge stride follows root at " + str(fps), absf(distance - reference * Enemy.PX) / distance < 0.05)
		e.free()

func stride_calibration(kind: String) -> void:
	if kind not in ["wolek", "rzeznik"]: return
	var e := Enemy.new()
	root.add_child(e)
	e.setup(kind)
	var speed: float = Defs.DEFS[kind].speed
	var low := INF
	var high := -INF
	for frame in 240:
		e.pose(1.0 / 120.0, "walk", false, Color.WHITE, 0.0, 1, true, 0.0, 0, false, speed)
		if frame < 120: continue
		var foot: Transform3D = (e.get("_cfoot") as Dictionary)["Right"]
		low = minf(low, foot.origin.x)
		high = maxf(high, foot.origin.x)
	var distance := 2.0 * (high - low) * float(e.get("_scale"))
	var cycle: float = Enemy.SPEC[kind].cycle
	check(kind + " stride matches actual travel", absf(distance - speed * Enemy.PX * cycle) / distance < 0.05)
	e.free()

func heavy_body(kind: String) -> void:
	if kind not in ["wolek", "rzeznik"]: return
	for fps in [30, 60, 120]:
		var e := Enemy.new()
		root.add_child(e)
		e.setup(kind)
		check(kind + " skeletal locomotion connected", e.get("_tree") != null)
		var sk: Skeleton3D = e.get("_sk")
		var bones: Dictionary = e.get("_b")
		var peak_clearance := -INF
		var reach_error := 0.0
		var blade: Array[Vector3] = []
		var bind := Transform3D.IDENTITY
		if kind == "rzeznik":
			var mesh: MeshInstance3D = e.get("_mesh")
			var arrays := mesh.mesh.surface_get_arrays(1)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var top := vertices[0]
			var bottom := vertices[0]
			for v in vertices:
				if v.y > top.y: top = v
				if v.y < bottom.y: bottom = v
			blade.assign([top, bottom])
			bind = mesh.skin.get_bind_pose(indices[0])
			for vertex in vertices.size():
				check("cleaver rigid grip", weights[vertex * 4] > 0.999 and String(mesh.skin.get_bind_name(indices[vertex * 4])).ends_with("RightHand"))
		var blade_up := -1.0
		for frame in roundi(0.9 * fps):
			e.motion_context({"grounded": true, "winding": true, "windup_duration": 0.9, "windup_remaining": 0.9 - frame / float(fps)})
			e.pose(1.0 / fps, "windup", false, Color.WHITE)
			var hand := sk.get_bone_global_pose(bones["RightHand"])
			var head := sk.get_bone_global_pose(bones["Head"])
			peak_clearance = maxf(peak_clearance, hand.origin.y - head.origin.y)
			var p: Dictionary = e.get("_last_p")
			reach_error = maxf(reach_error, hand.origin.distance_to(p["hR"]))
			if not blade.is_empty():
				var direction := ((hand * bind * blade[1]) - (hand * bind * blade[0])).normalized()
				blade_up = maxf(blade_up, direction.y)
			geometry(e, kind)
		check(kind + " hands rise above head at " + str(fps), peak_clearance > 0.08)
		check(kind + " authored arm goals reachable error=" + str(reach_error), reach_error < 0.045)
		e.motion_context({"grounded": true, "winding": false})
		e.trigger("attack")
		e.pose(1.0 / fps, "idle", false, Color.WHITE)
		if not blade.is_empty():
			var hand := sk.get_bone_global_pose(bones["RightHand"])
			var direction := ((hand * bind * blade[1]) - (hand * bind * blade[0])).normalized()
			check("cleaver lifts blade before contact", blade_up > 0.35)
			check("cleaver edge swings forward at contact", direction.x > 0.7)
			check("cleaver preserves length", absf((hand * bind * blade[1]).distance_to(hand * bind * blade[0]) - blade[0].distance_to(blade[1])) < 0.001)
		e.free()

func authored(e: Node3D, kind: String) -> void:
	var name := Motion.action(kind)
	if name == "": return
	for fps in [30, 60, 120]:
		var dt := 1.0 / float(fps)
		for multiplier in [0.5, 1.0, 1.5]:
			e.revive()
			var frames := maxi(2, roundi(Motion.contact(name) * multiplier * fps))
			var duration := frames * dt
			for frame in frames:
				e.motion_context({"winding": true, "windup_remaining": (frames - frame) * dt, "windup_duration": duration, "grounded": true})
				e.pose(dt, "windup", false, Color.WHITE)
				check(kind + " anticipation before authority", float(e.get("_motion_time")) < Motion.contact(name))
				if frame % 10 == 0: geometry(e, kind)
			e.motion_context({"winding": true, "windup_remaining": 0.0, "windup_duration": duration, "grounded": true})
			e.pose(dt, "windup", false, Color.WHITE)
			check(kind + " zero timer does not attack", e.motion_phase() == "anticipation")
			e.motion_context({"winding": false, "grounded": true})
			e.trigger("attack")
			e.pose(dt, "idle", true, Color.WHITE)
			check(kind + " exact contact first frame", e.motion_phase() == "contact" and absf(float(e.get("_motion_time")) - Motion.contact(name)) < 0.00001)
			check(kind + " contact keeps facing", absf(float(e.get("_face")) - 1.0) < 0.00001)
			check(kind + " individual recovery", absf(e.clip_duration("attack") - Motion.recovery(name)) < 0.00001)
			for frame in ceili(Motion.recovery(name) * fps) + 20:
				e.pose(dt, "idle", false, Color.WHITE)
				if frame % 10 == 0: geometry(e, kind)
			check(kind + " recovery clears", e.motion_phase() == "idle")
		# Przerwanie w połowie zapowiedzi wraca do bazowej pozy bez ciosu.
		e.motion_context({"winding": true, "windup_remaining": 0.2, "windup_duration": 0.4, "grounded": true})
		for frame in 10: e.pose(dt, "windup", false, Color.WHITE)
		e.motion_context({"winding": false, "grounded": true})
		for frame in 30: e.pose(dt, "idle", false, Color.WHITE)
		check(kind + " cancelled no attack", e.motion_phase() == "idle" and String(e.get("_clip")) == "")

func library_check() -> void:
	var library := Motion.library()
	check("authored library exists", library != null)
	if library == null: return
	var generated := Motion.build()
	for name in Motion.KEYS:
		check(name + " clip present", library.has_animation(name))
		var clip := library.get_animation(name)
		var reference := generated.get_animation(name)
		check(name + " markers", float(clip.get_meta("contact")) == Motion.contact(name) and float(clip.get_meta("recovery")) == Motion.recovery(name))
		for track in clip.get_track_count():
			for frame in 121:
				var time := clip.length * frame / 120.0
				var value = clip.value_track_interpolate(track, time)
				var expected = reference.value_track_interpolate(track, time)
				check(name + " baked curve", value.is_equal_approx(expected) if value is Vector3 else absf(float(value) - float(expected)) < 0.0001)
				check(name + " curve finite", value.is_finite() if value is Vector3 else is_finite(float(value)))
			var start = clip.value_track_interpolate(track, 0.0)
			var end = clip.value_track_interpolate(track, clip.length)
			check(name + " returns to base", start.is_equal_approx(end) if start is Vector3 else is_equal_approx(float(start), float(end)))

func stalker_facing() -> void:
	var actor := (load("res://scenes/stalker.tscn") as PackedScene).instantiate()
	root.add_child(actor)
	actor.set_physics_process(false)
	var target := Node2D.new()
	root.add_child(target)
	target.position.x = -10.0
	actor._windup_target = target
	actor.winding = true
	actor._sprite_frame(1.0, false, 0.0)
	check("stalker windup faces victim", bool(actor._spr[0].flip_h))
	actor._windup_target = null
	actor.winding = false
	actor._visual_attack(1, -14.3, -1.0)
	actor.position.x += 6.0
	actor._sprite_frame(1.0, false, 0.0)
	check("stalker backstep keeps victim facing", bool(actor._spr[0].flip_h))
	actor._visual_attack(0, -100.0, 1.0)
	check("stalker old contact keeps target and facing", is_equal_approx(float(actor.view_info()["target_y"]), -14.3) and bool(actor._spr[0].flip_h))
	actor._sync(actor.position, true, false, 0.0, 0.0, -100.0)
	check("stalker delayed snapshot keeps resolved grab", is_equal_approx(float(actor.view_info()["target_y"]), -14.3))
	actor.reset_enemy()
	check("stalker reset clears recovery", actor._grab_recovery_t == 0.0)
	actor.free()
	target.free()

func landing(e: Node3D, kind: String) -> void:
	if Enemy.SPEC[kind].has("deform"): return
	for vy in [-250.0, 0.0, 250.0]:
		e.motion_context({"grounded": false})
		e.pose(1.0 / 60.0, "idle", false, Color.WHITE, 0.0, 1, true, vy)
		check(kind + " airborne including apex", bool(e.get("_airborne")))
	e.motion_context({"grounded": true})

	e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
	check(kind + " landing starts", not bool(e.get("_airborne")) and float(e.get("_landing_t")) == 0.0)
	if not Enemy.SPEC[kind].get("crawler", false) and not Enemy.SPEC[kind].get("quad", false):
		var p: Dictionary = e.get("_last_p")
		check(kind + " feet contact on landing frame", p["fR"].y == 0.0 and p["fL"].y == 0.0)
	for frame in 30: e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
	check(kind + " landing settles", float(e.get("_landing_t")) > Motion.recovery("landing"))
	if Enemy.SPEC[kind].get("crawler", false):
		e.motion_context({"grounded": false})
		e.pose(1.0 / 60.0, "sleep", false, Color.WHITE)
		check(kind + " ceiling hold not falling", not bool(e.get("_airborne")))
	e.motion_context({"grounded": true})

func grab_height(e: Node3D, kind: String) -> void:
	if kind != "stalker": return
	var sk: Skeleton3D = e.get("_sk")
	var bones: Dictionary = e.get("_b")
	for height in [1.2, 2.8]:
		e.motion_context({"grounded": true, "target_y": -height / Enemy.PX})
		e.trigger("attack")
		e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
		for side in ["Right", "Left"]:
			var hand := sk.global_transform * sk.get_bone_global_pose(bones[side + "Hand"]).origin
			check("stalker grabs actual torso height=" + str(height) + " hand=" + str(hand.y), absf(hand.y - height) < 0.45)
		geometry(e, kind)
	e.revive()

func geometry(e: Node3D, kind: String) -> void:
	var sk: Skeleton3D = e.get("_sk")
	var bones: Dictionary = e.get("_b")
	if sk != null:
		for key in e.get("_q_limbs"):
			var chain: Array = e.get("_q_limbs")[key]
			for index in 4:
				var a: Transform3D = e.call("_gp", chain[index])
				var b: Transform3D = e.call("_gp", chain[index + 1])
				var rest_a := sk.get_bone_global_rest(chain[index])
				var rest_b := sk.get_bone_global_rest(chain[index + 1])
				check(kind + " quad segment preserved", absf(a.origin.distance_to(b.origin) - rest_a.origin.distance_to(rest_b.origin)) < 0.005)
			var locks: Dictionary = e.get("_foot_locks")
			if locks.has(key):
				var toe: Transform3D = e.call("_gp", chain[4])
				check(kind + " quad support drift", (sk.global_transform * toe.origin).distance_to(locks[key]) < 0.04)
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
	library_check()
	stalker_facing()
	for kind in Enemy.SPEC:
		var e: Node3D = Enemy.new()
		root.add_child(e)
		check(kind + " setup", e.setup(kind))
		heavy_body(kind)
		stride_calibration(kind)
		charge_motion(kind)
		authored(e, kind)
		landing(e, kind)
		grab_height(e, kind)
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
					check(kind + " attack hand height", (sk.global_transform * hand.origin).y > 0.65 if kind == "stalker" else hand.origin.y > 0.75)
			if not Enemy.SPEC[kind].get("crawler", false):
				var normal := Vector3(0.10, 0.995, 0.0).normalized()
				e.set("ground_profile", {"Right": {"height": 0.08, "normal": normal}, "Left": {"height": 0.02, "normal": normal}})
				for f in 90: e.pose(1.0 / 60.0, "idle", false, Color.WHITE)
				for side in ["Right", "Left"]:
					var foot: Transform3D = e.call("_gp", bones[side + "Foot"])
					var rest := sk.get_bone_global_rest(bones[side + "Foot"])
					var expected_y: float = rest.origin.y + (0.08 if side == "Right" else 0.02) / float(e.get("_scale"))
					check(kind + " terrain lifts ankle within sole clearance", foot.origin.y >= expected_y - 0.02 and foot.origin.y <= expected_y + 0.10)
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
