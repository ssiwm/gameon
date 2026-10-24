extends SceneTree
## Audyt danych siatek i skinningu; pomiar podeszew pomija deformacje shaderowe bossów.
const Enemy := preload("res://scripts/enemy3d.gd")
var done := false
var failures := 0
var output := "/tmp/enemy-assets.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.substr(6)

func meshes(e: Node3D, stats: Dictionary) -> Array:
	var samples := []
	var sk: Skeleton3D = e.get("_sk")
	for node in e.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null: continue
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			stats.vertices += vertices.size()
			stats.triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			if sk == null or mi.skin == null or arrays[Mesh.ARRAY_BONES] == null: continue
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / vertices.size()
			var xf := sk.global_transform.affine_inverse() * mi.global_transform
			var rest_offset = null
			for vertex in vertices.size():
				var sum := 0.0
				var rest := Vector3.ZERO
				var sole_weight := 0.0
				var influences := []
				for slot in per:
					var index := vertex * per + slot
					var weight := weights[index]
					if weight <= 0.0: continue
					if bones[index] < 0 or bones[index] >= mi.skin.get_bind_count():
						stats.invalid_binds += 1
						continue
					var bone := mi.skin.get_bind_bone(bones[index])
					if bone < 0: bone = sk.find_bone(mi.skin.get_bind_name(bones[index]))
					if bone < 0 or bone >= sk.get_bone_count():
						stats.invalid_binds += 1
						continue
					var bind := mi.skin.get_bind_pose(bones[index])
					rest += sk.get_bone_global_rest(bone) * bind * (xf * vertices[vertex]) * weight
					var name := String(sk.get_bone_name(bone))
					if "Foot" in name or "Toe" in name or name.ends_with("Limb_3") or name.ends_with("Limb_4"):
						sole_weight += weight
					influences.append([bone, bind, weight])
					sum += weight
				if not vertices[vertex].is_finite() or absf(sum - 1.0) > 0.01: stats.invalid_weights += 1
				var offset := rest - xf * vertices[vertex]
				if rest_offset == null:
					rest_offset = offset
					if offset.length() > (Vector3(stats.rest_offset[0], stats.rest_offset[1], stats.rest_offset[2])).length():
						stats.rest_offset = [offset.x, offset.y, offset.z]
				stats.rest_error = maxf(stats.rest_error, offset.distance_to(rest_offset as Vector3))
				if sole_weight >= 0.5: samples.append([xf * vertices[vertex], influences])
	return samples

func soles(e: Node3D, samples: Array) -> float:
	var sk: Skeleton3D = e.get("_sk")
	var lowest := INF
	for sample in samples:
		var point := Vector3.ZERO
		for influence in sample[1]:
			point += sk.get_bone_global_pose(influence[0]) * influence[1] * sample[0] * influence[2]
		lowest = minf(lowest, (sk.global_transform * point).y - e.global_position.y)
	return lowest if is_finite(lowest) else 0.0

func _process(_dt: float) -> bool:
	if done: return false
	done = true
	var report := {}
	for kind in Enemy.SPEC:
		var e := Enemy.new()
		root.add_child(e)
		e.setup(kind)
		var stats := {"vertices": 0, "triangles": 0, "invalid_weights": 0, "invalid_binds": 0, "rest_error": 0.0, "rest_offset": [0.0,0.0,0.0], "sole_min": {}}
		var samples := meshes(e, stats)
		for fps in [30, 60, 120]:
			for state in ["idle", "walk", "contact", "recovery"]:
				var low := INF
				if state == "contact": e.trigger("attack")
				for frame in (1 if state == "contact" else fps):
					e.motion_context({"grounded": true})
					e.pose(1.0 / fps, "walk" if state == "walk" else "idle", false, Color.WHITE)
					if not samples.is_empty(): low = minf(low, soles(e, samples))
				if is_finite(low):
					stats.sole_min[state] = minf(float(stats.sole_min.get(state, INF)), low)
					if low < -0.025:
						failures += 1
						print("FAIL enemy assets: %s/%s/%d fps sole=%s" % [kind, state, fps, low])
				else: stats.sole_min[state] = null
		if stats.invalid_weights > 0 or stats.invalid_binds > 0 or stats.rest_error > 0.005: failures += 1
		report[kind] = stats
		e.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save " + output)
		quit(1)
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("%s enemy assets: %d kinds, 30/60/120 fps, %d failures; %s" % ["PASS" if failures == 0 else "FAIL", report.size(), failures, output])
	quit(0 if failures == 0 else 1)
	return false
