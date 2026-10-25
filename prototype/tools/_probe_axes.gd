extends SceneTree

func _initialize() -> void:
	var f := FileAccess.open("C:/deadair87/gameon/prototype/tools/_probe_axes.txt", FileAccess.WRITE)
	var log: Array[String] = []
	var ps: PackedScene = load("res://art/enemy3d/trzosek.glb")
	if ps == null:
		log.append("ERR load"); _flush(f, log); quit(); return
	var m: Node3D = ps.instantiate()
	var sk: Skeleton3D = null
	for c in m.find_children("*", "Skeleton3D", true, false):
		sk = c; break
	if sk == null:
		log.append("NO SKELETON"); _flush(f, log); quit(); return
	log.append("BONE_COUNT=" + str(sk.get_bone_count()))
	var mn := Vector3(1e9,1e9,1e9); var mx := Vector3(-1e9,-1e9,-1e9)
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_rest(i).origin
		mn = mn.min(g); mx = mx.max(g)
	log.append("BB_MIN=(%.4f,%.4f,%.4f)" % [mn.x,mn.y,mn.z])
	log.append("BB_MAX=(%.4f,%.4f,%.4f)" % [mx.x,mx.y,mx.z])
	log.append("EXTENT x=%.4f y=%.4f z=%.4f" % [mx.x-mn.x, mx.y-mn.y, mx.z-mn.z])
	log.append("=== ALL BONES (i | name | parent | restlocal.origin | globalrest.origin | globalrest.euler XYZ) ===")
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		var p := sk.get_bone_parent(i)
		var lo := sk.get_bone_rest(i).origin
		var gr := sk.get_bone_global_rest(i)
		var go: Vector3 = gr.origin
		var e: Vector3 = gr.basis.get_euler()
		var pd := sk.get_bone_rest(i).origin.length()
		log.append("%02d | %s | par=%d | lo=(%.3f,%.3f,%.3f) | go=(%.3f,%.3f,%.3f) | euler=(%.1f,%.1f,%.1f)" % [i, nm, p, lo.x, lo.y, lo.z, go.x, go.y, go.z, rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
	for c in m.find_children("*", "AnimationPlayer", true, false):
		var ap: AnimationPlayer = c
		for a in ap.get_animation_list():
			var an: Animation = ap.get_animation(a)
			log.append("ANIM | %s | len=%.4f" % [a, an.length])
	_flush(f, log)
	quit()

func _flush(f: FileAccess, log: Array[String]) -> void:
	if f == null:
		for l in log: print(l)
		return
	for line in log: f.store_line(line)
	f.close()
