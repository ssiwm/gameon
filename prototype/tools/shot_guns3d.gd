extends SceneTree
## Zrzut kontrolny modeli broni 3D: lufa ma iść w prawo; kropki = tylna dłoń (czerwona), przednia (zielona), wylot (niebieska).
## godot --path prototype --script tools/shot_guns3d.gd -- --out=/tmp/guns3d.png
const KEYS := ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6", "maczeta", "kilof"]
var _frames := 0
var _out := "/tmp/guns3d.png"
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.6
	cam.position = Vector3(3.2, 1.0, 6.0)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.3, -0.5, -0.8), Vector3.UP)
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	cam.environment = env
	for i in KEYS.size():
		var k: String = KEYS[i]
		var path := "res://art/char3d/gun_%s.glb" % k
		var g: Node3D = (load(path) as PackedScene).instantiate()
		g.position = Vector3((i % 4) * 2.0 + 0.5, 1.6 - (i / 4) * 1.3, 0.0)
		vp.add_child(g)
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
		for pair in [["rear", Color.RED], ["fore", Color.GREEN], ["muzzle", Color.CYAN]]:
			var a: Array = d[pair[0]]
			var m := MeshInstance3D.new()
			m.mesh = SphereMesh.new()
			(m.mesh as SphereMesh).radius = 0.03
			(m.mesh as SphereMesh).height = 0.06
			var mat := StandardMaterial3D.new()
			mat.albedo_color = pair[1]
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.material_override = mat
			m.position = Vector3(float(a[0]), float(a[2]), -float(a[1])) + Vector3(0, 0, 0.3)
			g.add_child(m)
		var l := Label3D.new()
		l.text = k
		l.pixel_size = 0.004
		l.position = Vector3(0.3, -0.35, 0.3)
		g.add_child(l)
func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 30:
		root.get_child(root.get_child_count() - 1).get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
