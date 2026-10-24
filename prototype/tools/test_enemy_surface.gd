extends SceneTree
## Regresja prawdziwej geometrii: szczeliny UV, skinning szwów i dolne nogi.
## Godot --headless --path prototype -s tools/test_enemy_surface.gd [-- --report=PLIK]
const Enemy := preload("res://scripts/enemy3d.gd")
const BUDGET := {"wolek": 100, "rzeznik": 300}
var failures := 0
var report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	if condition: return
	failures += 1
	print("FAIL enemy surface: " + label)

func _topology(mi: MeshInstance3D, kind: String) -> Array:
	var seams: Array = []
	var triangles := 0
	var boundary := 0
	var lower_hand := 0.0
	var sk: Skeleton3D = mi.get_node(mi.skeleton)
	var bounds := mi.mesh.get_aabb()
	var leg_lateral := 0.0
	for bind in mi.skin.get_bind_count():
		if String(mi.skin.get_bind_name(bind)).ends_with("Foot"):
			leg_lateral = maxf(leg_lateral, absf(mi.skin.get_bind_pose(bind).affine_inverse().origin.z))
	var leg_samples := 0
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := bones.size() / vertices.size()
		var positions: Dictionary = {}
		var weld: Array[int] = []
		var groups: Dictionary = {}
		for i in vertices.size():
			var key := Vector3i((vertices[i] * 100000.0).round())
			if not positions.has(key): positions[key] = positions.size()
			weld.append(positions[key])
			if not groups.has(key): groups[key] = []
			groups[key].append(i)
			var sum := 0.0
			var hand := 0.0
			for influence in influences:
				var at := i * influences + influence
				var bind := bones[at]
				check(kind + " bind index", bind >= 0 and bind < mi.skin.get_bind_count())
				sum += weights[at]
				var name := String(mi.skin.get_bind_name(bind))
				if name == "": name = String(sk.get_bone_name(mi.skin.get_bind_bone(bind)))
				if name.ends_with("Hand"): hand += weights[at]
			check(kind + " normalized weights", absf(sum - 1.0) < 0.001)
			# Palce Rzeźnika sięgają kolan. Próbkuj korytarz nóg wyznaczony
			# kostkami; sam próg wysokości błędnie obejmowałby dłonie.
			if kind == "rzeznik" and surface == 0 and vertices[i].y < bounds.position.y + bounds.size.y * 0.20 and absf(vertices[i].z) < leg_lateral + bounds.size.y * 0.05:
				lower_hand = maxf(lower_hand, hand)
				leg_samples += 1
		for group in groups.values():
			if group.size() > 1: seams.append([arrays, group])
		var edges: Dictionary = {}
		triangles += indices.size() / 3
		for triangle in indices.size() / 3:
			for corner in 3:
				var a := weld[indices[triangle * 3 + corner]]
				var b := weld[indices[triangle * 3 + (corner + 1) % 3]]
				if a == b: continue
				var key := Vector2i(mini(a, b), maxi(a, b))
				edges[key] = int(edges.get(key, 0)) + 1
		for count in edges.values():
			if count == 1: boundary += 1
	check(kind + " boundary budget", boundary <= int(BUDGET[kind]))
	check(kind + " geometry present", triangles >= (5000 if kind == "wolek" else 20000))
	check(kind + " triangle budget", triangles <= (6000 if kind == "wolek" else 30000))
	check(kind + " lower legs do not follow hands", lower_hand < 0.05)
	if kind == "rzeznik": check(kind + " actual leg samples", leg_samples > 100)
	check(kind + " actual UV seams present", seams.size() > 100)
	check(kind + " body/equipment surfaces", mi.mesh.get_surface_count() == (1 if kind == "wolek" else 2))
	for surface in mi.mesh.get_surface_count():
		var source := mi.mesh.surface_get_material(surface) as StandardMaterial3D
		var material := mi.get_surface_override_material(surface) as ShaderMaterial
		check(kind + " source culling preserved", source != null and material != null and (("cull_disabled" in material.shader.code) == (source.cull_mode == BaseMaterial3D.CULL_DISABLED)))
	report[kind] = {"triangles": triangles, "boundary_edges": boundary, "seam_groups": seams.size(), "lower_leg_hand_weight_max": lower_hand, "poses": {}}
	return seams

func _skin_gap(mi: MeshInstance3D, seams: Array) -> float:
	var sk: Skeleton3D = mi.get_node(mi.skeleton)
	var transforms: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(bind)
		if mi.skin.get_bind_name(bind) != &"": bone = sk.find_bone(mi.skin.get_bind_name(bind))
		transforms.append(sk.global_transform * sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
	var maximum := 0.0
	for seam in seams:
		var arrays: Array = seam[0]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / vertices.size()
		var reference := Vector3.ZERO
		for n in seam[1].size():
			var index: int = seam[1][n]
			var position := Vector3.ZERO
			for influence in per:
				var at := index * per + influence
				position += (transforms[bones[at]] * vertices[index]) * weights[at]
			if n == 0: reference = position
			else: maximum = maxf(maximum, reference.distance_to(position))
	return maximum

func _run() -> void:
	for kind in BUDGET:
		var e := Enemy.new()
		root.add_child(e)
		check(kind + " setup", e.setup(kind))
		var mi: MeshInstance3D = e.get("_mesh")
		var seams := _topology(mi, kind)
		for fps in [30, 60, 120]:
			for stage in ["idle", "walk", "windup", "contact", "recovery"]:
				if stage == "contact": e.trigger("attack")
				for frame in (1 if stage == "contact" else fps):
					e.motion_context({"grounded": true, "horizontal_speed": 1.0, "winding": stage == "windup", "windup_remaining": 0.5, "windup_duration": 0.5})
					e.pose(1.0 / fps, "walk" if stage == "walk" else ("windup" if stage == "windup" else "idle"), false, Color.WHITE)
				var gap := _skin_gap(mi, seams)
				var name := "%s/%d" % [stage, fps]
				report[kind].poses[name] = gap
				check(kind + " " + name + " seam gap <= 1 mm", is_finite(gap) and gap <= 0.001)
		e.free()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.substr(9), FileAccess.WRITE)
			check("report writable", file != null)
			if file != null: file.store_string(JSON.stringify(report, "\t"))
	print(("PASS" if failures == 0 else "FAIL") + " enemy surface: " + JSON.stringify(report))
	quit(0 if failures == 0 else 1)
