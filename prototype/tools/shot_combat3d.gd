extends SceneTree
## Powtarzalny podgląd klipów walki TPP i mechaniki broni, z profilem odrzutu używanym w grze.
## godot --path prototype -s tools/shot_combat3d.gd -- --out=/tmp/combat [--reloads]
const Char3D := preload("res://scripts/char3d.gd")
const Motion := preload("res://scripts/weapon_motion.gd")
const CharClips := preload("res://scripts/char_clips.gd")
const CELL := 300
var _frames := 0
var _wait := 40
var _out := "/tmp/hands.png"
var _chars: Array = []
var _cfg: Array = []
var _cams: Array = []                        ## [Char3D, Camera3D, nazwa widoku]
var _views: Array = ["side", "front", "top"]
var _size := 2.2
var _anim := "idle"
var _speed := 0.0
var _swing := -1.0
var _reload_mode := false
var _reload := -1.0
var _kick := 0.0
var _turn: Array = []                        ## klatki po zmianie kierunku (sekwencja obrotu); puste = postać patrzy w prawo

func _initialize() -> void:
	var guns: Array = ["m83", "p64"]
	var aims: Array = [-50, 0, 50]
	var ch := "male_scav"
	for a in OS.get_cmdline_user_args():
		if a == "--reloads":
			_reload_mode = true
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--guns="):
			guns = Array(a.substr(7).split(","))
		elif a.begins_with("--aims="):
			aims = Array(a.substr(7).split(",")).map(func(s): return int(s))
		elif a.begins_with("--views="):
			_views = Array(a.substr(8).split(","))
		elif a.begins_with("--anim="):
			_anim = a.substr(7)
		elif a.begins_with("--charset="):
			Char3D.charset = a.substr(10)
		elif a.begins_with("--char="):
			ch = a.substr(7)
		elif a.begins_with("--size="):
			_size = float(a.substr(7))
		elif a.begins_with("--swing="):
			_swing = float(a.substr(8))
		elif a.begins_with("--reload="):
			_reload = float(a.substr(9))
		elif a.begins_with("--kick="):
			_kick = float(a.substr(7))
		elif a.begins_with("--turn="):
			_turn = Array(a.substr(7).split(",")).map(func(t): return int(t))
		elif a.begins_with("--speed="):
			_speed = float(a.substr(8))
		elif a.begins_with("--frames="):
			_wait = int(a.substr(9))
		elif a == "--noclips":
			CharClips.enabled = false
	_cfg = [
		{"gun": "kilof", "aim": 0, "char": "male_scav", "anim": "idle", "flip": 0, "action": "pickaxe", "recoil": 0.0, "cadence": 0.9},
		{"gun": "kilof", "aim": 50, "char": "female_medic", "anim": "crouch", "flip": 0, "action": "pickaxe", "recoil": 0.0, "cadence": 0.9},
		{"gun": "m83", "aim": 0, "char": "male_scav", "anim": "idle", "flip": 0, "action": "burst", "recoil": 2.5, "cadence": 0.11},
		{"gun": "srut8", "aim": 0, "char": "female_medic", "anim": "idle", "flip": 0, "action": "shot", "recoil": 7.0, "cadence": 0.8},
	]
	if _reload_mode:
		_cfg = [
			{"gun": "p64", "aim": 0, "char": "male_scav", "anim": "idle", "action": "reload", "recoil": 0.0, "cadence": 2.1},
			{"gun": "m83", "aim": 0, "char": "female_medic", "anim": "crouch", "action": "reload", "recoil": 0.0, "cadence": 2.1},
			{"gun": "srut8", "aim": 0, "char": "male_scav", "anim": "idle", "action": "reload", "recoil": 0.0, "cadence": 0.6},
			{"gun": "ciegno6", "aim": 0, "char": "female_medic", "anim": "idle", "action": "reload", "recoil": 0.0, "cadence": 2.1},
		]
	_views = ["side", "front"]
	_wait = 240
	DirAccess.make_dir_recursive_absolute(_out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(CELL * _cfg.size(), CELL * _views.size())
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.23, 0.22)
	bg.size = Vector2(root.size)
	root.add_child(bg)
	for i in _cfg.size():
		var cfg: Dictionary = _cfg[i]
		var c := Char3D.new()
		c.preview = true
		c.position = Vector2(-4000.0, 0.0)                      # sprite postaci poza kadrem: oglądamy jej świat 3D własnymi kamerami
		root.add_child(c)
		if not c.setup(cfg["char"], cfg["gun"]):
			push_error("setup nie powiodło się: %s" % cfg)
		c._set_on_screen(true)
		_chars.append(c)
		for v in _views.size():
			var vp := SubViewport.new()
			vp.size = Vector2i(CELL - 4, CELL - 4)
			vp.transparent_bg = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.world_3d = c._vp.find_world_3d()
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.size = _size
			cam.near = 0.2
			cam.far = 30.0
			cam.cull_mask = 1
			cam.environment = c._cam.environment
			vp.add_child(cam)
			_cams.append([c, cam, String(_views[v])])
			var tr := TextureRect.new()
			tr.texture = vp.get_texture()
			tr.position = Vector2(CELL * i + 2, CELL * v + 2)
			root.add_child(tr)
		var lb := Label.new()
		lb.text = "%s  %d°" % [cfg["gun"], cfg["aim"]]
		lb.position = Vector2(CELL * i + 8, 4)
		root.add_child(lb)

func _process(_d: float) -> bool:
	_frames += 1
	for i in _chars.size():
		var cfg: Dictionary = _cfg[i]
		var c: Node2D = _chars[i]
		var a := deg_to_rad(float(cfg["aim"]))
		var elapsed := maxf(0.0, float(_frames - 60) / 60.0)
		var in_action := _frames >= 60 and elapsed < 2.1
		c.reload_t = fposmod(elapsed, float(cfg.cadence)) / float(cfg.cadence) if _reload_mode and in_action else -1.0
		c.reload_variant = Motion.ROUND if cfg.gun == "srut8" else Motion.EMPTY
		c.swing_t = fposmod(elapsed, 0.9) / 0.9 if in_action and cfg.action == "pickaxe" else -1.0
		var since_shot := fposmod(elapsed, float(cfg.cadence))
		var recoil := Motion.recoil_at(cfg.gun, since_shot) if in_action and not _reload_mode and cfg.action != "pickaxe" else Vector2.ZERO
		c.gun_kick_px = 0.0
		c.recoil_px = 0.0
		c.gun_recoil_m = recoil.x
		c.gun_recoil_rad = recoil.y
		c.fire_t = since_shot if in_action and not _reload_mode and cfg.action != "pickaxe" else -1.0
		c.cycle_t = since_shot / float(cfg.cadence) if in_action and not _reload_mode and cfg.gun == "srut8" else -1.0
		c.update(1.0 / 60.0, cfg.anim, 1.0, Vector2(cos(a), -sin(a)), 0.0)
	for e in _cams:
		var c: Node2D = e[0]
		var cam: Camera3D = e[1]
		var sk: Skeleton3D = c._sk
		var hand := sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
		var sh := sk.get_bone_global_pose(sk.find_bone("mixamorig_RightArm")).origin
		var centre := (hand + sh) * 0.5 + Vector3(0.1, 0.0, 0.0) if _size < 1.6 else Vector3(c._origin_x + 0.15, 1.0, 0.0)
		var dir := Vector3(0.26, 0.0, 0.97)                       # side: kamera gry (obrót 15°)
		if String(e[2]) == "game":                                 # kamera gry w świecie (+Z), przeliczona do układu modelu obróconego o model_yaw
			var yaw := float(c.model_yaw)
			dir = Basis(Vector3.UP, -yaw) * Vector3(0.0, 0.05, 1.0)
			centre = Basis(Vector3.UP, -yaw) * Vector3(0.15 * cos(yaw), 1.0 if _size >= 1.6 else 1.3, 0.0)
		var up := Vector3.UP
		match String(e[2]):
			"front":
				dir = Vector3(0.94, 0.12, 0.34)
			"top":
				dir = Vector3(0.05, 1.0, 0.25)
				up = Vector3(1.0, 0.0, 0.0)
			"back":
				dir = Vector3(0.26, 0.0, -0.97)
		cam.look_at_from_position(centre + dir.normalized() * 6.0, centre, up)
	if _frames >= 42 and _frames % 3 == 0:
		var img := root.get_texture().get_image()
		img.get_region(Rect2i(0, 0, 1200, 600)).save_png(_out.path_join("f_%03d.png" % _frames))
	if _frames == _wait:
		print("saved animation ", _out)
		quit()
	return false
