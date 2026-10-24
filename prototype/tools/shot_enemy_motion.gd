extends SceneTree
## Odbiór 14 modeli: chód, zapowiedź, kontakt, przerwanie, obrót, lot/lądowanie i śmierć.
## Godot -s tools/shot_enemy_motion.gd -- --dir=KATALOG [--frames=240] [--kinds=wolek,rzeznik --closeup --angle=35]
## Każda komórka ma własną skalę kamery; atlas nie porównuje wzrostu gatunków.
const Enemy := preload("res://scripts/enemy3d.gd")
const Defs := preload("res://scripts/enemy_defs.gd")
var cells: Array = []
var frame := 0
var count := 240
var directory := "/tmp/enemy-motion"
var kinds: Array = Enemy.SPEC.keys()
var cell_size := Vector2i(300, 320)
var columns := 4
var angle := 5.33

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): directory = arg.substr(6)
		if arg.begins_with("--frames="): count = arg.substr(9).to_int()
		if arg.begins_with("--kinds="): kinds = Array(arg.substr(8).split(","))
		if arg == "--closeup": cell_size = Vector2i(600, 640); columns = 2
		if arg.begins_with("--angle="): angle = arg.substr(8).to_float()
	for kind in kinds:
		if not Enemy.SPEC.has(kind):
			push_error("Unknown enemy kind: " + str(kind))
			quit(1)
			return
	columns = mini(columns, kinds.size())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK or not DirAccess.dir_exists_absolute(directory):
		push_error("FAIL enemy motion render: output directory error=" + str(mkdir_error))
		quit(1)
		return
	RenderingServer.frame_post_draw.connect(_capture)
	for i in kinds.size():
		var vp := SubViewport.new()
		vp.size = cell_size
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_2X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.19, 0.21, 0.24)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -25, 0)
		light.light_energy = 1.3
		light.shadow_enabled = true
		vp.add_child(light)
		var floor_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(20, 0.04, 20)
		floor_mesh.mesh = box
		floor_mesh.position.y = -0.03
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.29, 0.31)
		floor_mesh.material_override = mat
		vp.add_child(floor_mesh)
		var e := Enemy.new()
		vp.add_child(e)
		if not e.setup(kinds[i]): push_error("setup " + kinds[i])
		var h: float = maxf(float(e.get("_model_h")) * float(e.get("_scale")), 1.5)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = h * 1.8
		vp.add_child(cam)
		cam.current = true
		var label := Label.new()
		label.position = Vector2(8, cell_size.y - 32)
		label.add_theme_font_size_override("font_size", 16)
		vp.add_child(label)
		cells.append([vp, e, kinds[i], cam, h, label])

func _process(_dt: float) -> bool:
	frame += 1
	var time := frame / 60.0
	for cell in cells:
		var e: Node3D = cell[1]
		var kind: String = cell[2]
		var anim := "idle"
		var vy := 0.0
		var grounded := true
		var flip := time >= 3.6
		var speed := 0.0
		if time < 0.8 or (time >= 3.6 and time < 3.9):
			anim = "walk"
			speed = float((Defs.DEFS.get(kind, {}) as Dictionary).get("speed", 95.0))
			e.position.x += speed * Enemy.PX / 60.0 * (-1.0 if flip else 1.0)
		elif time < 1.7:
			anim = "windup"
		elif time >= 2.8 and time < 3.2:
			anim = "windup"
		if time >= 3.9 and time < 4.6 and not Enemy.SPEC[kind].has("deform"):
			grounded = false
			var u := (time - 3.9) / 0.7
			e.position.y = 0.8 * sin(PI * u)
			vy = -250.0 * cos(PI * u)
		else:
			e.position.y = 0.0
		var remaining := 1.7 - time if time < 2.0 else 3.7 - time
		e.motion_context({"winding": anim == "windup", "windup_remaining": maxf(remaining, 0.0), "windup_duration": 0.9, "grounded": grounded})
		if frame == 102: e.trigger("attack")
		if kind == "vein" and time >= 0.8 and time < 2.8: anim = "spit"
		if kind == "leech" and time >= 0.8 and time < 2.8: anim = "strike"
		if kind == "nest": anim = "open" if time >= 0.8 and time < 2.8 else "idle"
		if frame == 306: e.die()
		if time >= 5.1: anim = "death"
		e.pose(1.0 / 60.0, anim, flip, Color.WHITE, fposmod(frame / 10.0, 6.0), 6, true, vy, 0, false, speed)
		var h: float = cell[4]
		var offset := e.position
		var radians := deg_to_rad(angle)
		(cell[3] as Camera3D).look_at_from_position(offset + Vector3(sin(radians) * h * 3.0, h * 0.75, cos(radians) * h * 3.0), offset + Vector3(0, h * 0.48, 0))
		(cell[5] as Label).text = "%s | %s" % [kind, e.motion_phase() if anim in ["windup", "idle"] and e.motion_phase() != "idle" else ("lot" if not grounded else anim)]
	return false

func _capture() -> void:
	if frame > 0 and frame % 2 == 0:
		var atlas := Image.create(columns * cell_size.x, ceili(cells.size() / float(columns)) * cell_size.y, false, Image.FORMAT_RGBA8)
		atlas.fill(Color(0.12, 0.13, 0.15))
		for i in cells.size():
			var img: Image = cells[i][0].get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, cell_size), Vector2i((i % columns) * cell_size.x, (i / columns) * cell_size.y))
		var save_error := atlas.save_png("%s/f_%03d.png" % [directory, frame / 2 - 1])
		if save_error != OK:
			push_error("FAIL enemy motion render: PNG save error=" + str(save_error))
			quit(1)
			return
		if frame / 2 >= count:
			print("PASS enemy motion render: ", count, " frames, ", cells.size(), " kinds")
			quit()
