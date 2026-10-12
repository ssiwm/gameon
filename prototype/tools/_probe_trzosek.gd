extends SceneTree

func _initialize() -> void:
	var f := FileAccess.open("user://_probe_out.txt", FileAccess.WRITE)
	if f == null:
		f = FileAccess.open("res://tools/_probe_out.txt", FileAccess.WRITE)
	var log: Array[String] = []
	log.append("PROBE START")
	var ps: PackedScene = load("res://art/enemy3d/trzosek.glb")
	if ps == null:
		log.append("ERR: cannot load glb")
		_flush(f, log)
		quit()
		return
	var m: Node3D = ps.instantiate()
	var sk: Skeleton3D = null
	for c in m.find_children("*", "Skeleton3D", true, false):
		sk = c
		break
	if sk != null:
		log.append("BONE_COUNT=" + str(sk.get_bone_count()))
		for i in sk.get_bone_count():
			var p := sk.get_bone_parent(i)
			var lo: Vector3 = sk.get_bone_rest(i).origin
			var gr := sk.get_bone_global_rest(i)
			var go: Vector3 = gr.origin
			var d: Vector3 = (gr.origin - (sk.get_bone_global_rest(p).origin if p >= 0 else Vector3.ZERO))
			log.append("BONE %d | %s | parent=%d | restlocal=(%.3f,%.3f,%.3f) | globalrest=(%.3f,%.3f,%.3f) | dir2parent=(%.3f,%.3f,%.3f)" % [i, sk.get_bone_name(i), p, lo.x, lo.y, lo.z, go.x, go.y, go.z, d.x, d.y, d.z])
	else:
		log.append("NO SKELETON")
	for c in m.find_children("*", "AnimationPlayer", true, false):
		var ap: AnimationPlayer = c
		log.append("ANIM_LIST=" + str(ap.get_animation_list()))
		for a in ap.get_animation_list():
			var an: Animation = ap.get_animation(a)
			log.append("ANIM | %s | len=%.3f | loop=%d" % [a, an.length, an.loop_mode])
	_flush(f, log)
	quit()

func _flush(f: FileAccess, log: Array[String]) -> void:
	if f == null:
		return
	for line in log:
		f.store_line(line)
	f.close()
