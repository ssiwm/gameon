extends SceneTree
## Sześć wyglądów: postój z boku i od przodu; opcjonalnie przejścia bieg/kucanie → postój.
## godot --path prototype -s tools/shot_standing3d.gd -- --out=/tmp/standing [--motion] [--frames=180]
const Char3D := preload("res://scripts/char3d.gd")
const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_hazmat", "male_medic", "female_medic"]
const WIDTH := 200
const HEIGHT := 300
var _out := "/tmp/standing"
var _tick := 0
var _frames := 180
var _motion := false
var _chars: Array[Node2D] = []
var _cameras: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--frames="):
			_frames = maxi(60, int(arg.substr(9)))
		elif arg == "--motion":
			_motion = true
	DirAccess.make_dir_recursive_absolute(_out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(WIDTH * LOOKS.size(), HEIGHT * 2)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.23, 0.22)
	bg.size = Vector2(root.size)
	root.add_child(bg)
	for i in LOOKS.size():
		var c := Char3D.new()
		c.preview = true
		c.position = Vector2(-4000.0, 0.0)
		root.add_child(c)
		if not c.setup(LOOKS[i], "m83"):
			push_error("brak wyglądu " + LOOKS[i])
			quit(1)
			return
		c._set_on_screen(true)
		_chars.append(c)
		for row in 2:
			var vp := SubViewport.new()
			vp.size = Vector2i(WIDTH - 4, HEIGHT - 4)
			vp.transparent_bg = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.world_3d = c._vp.find_world_3d()
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.keep_aspect = Camera3D.KEEP_HEIGHT
			camera.size = 2.05
			camera.near = 0.2
			camera.far = 30.0
			camera.cull_mask = 1
			camera.environment = c._cam.environment
			vp.add_child(camera)
			_cameras.append([c, camera, row])
			var texture := TextureRect.new()
			texture.texture = vp.get_texture()
			texture.position = Vector2(WIDTH * i + 2, HEIGHT * row + 2)
			root.add_child(texture)
		var label := Label.new()
		label.text = LOOKS[i]
		label.position = Vector2(WIDTH * i + 8, 4)
		root.add_child(label)

func _process(_delta: float) -> bool:
	_tick += 1
	var state := "idle"
	if _motion and _tick > 60:
		var phase := fposmod(maxf(float(_tick - 60), 0.0) / 60.0, 4.0)
		state = "run" if phase < 0.8 else ("crouch" if phase > 2.0 and phase < 2.8 else "idle")
	for c in _chars:
		c.update(1.0 / 60.0, state, 1.0, Vector2.RIGHT, 95.0 if state == "run" else 0.0)
	for item in _cameras:
		var c: Node2D = item[0]
		var camera: Camera3D = item[1]
		var centre := Vector3(c._origin_x + 0.12, 0.94, 0.0)
		var direction := Vector3.BACK if item[2] == 0 else Vector3.RIGHT
		camera.look_at_from_position(centre + direction * 6.0, centre, Vector3.UP)
	if _tick >= 60 and _tick % 3 == 0:
		root.get_texture().get_image().get_region(Rect2i(0, 0, WIDTH * LOOKS.size(), HEIGHT * 2)).save_png(_out.path_join("f_%03d.png" % _tick))
	if _tick >= _frames:
		print("saved standing ", _out)
		quit()
	return false
