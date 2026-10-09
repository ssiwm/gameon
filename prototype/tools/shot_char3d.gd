extends SceneTree
## Zrzut kontrolny postaci 3D (spike): rząd póz × kąty celowania, w prawo i w lewo.
## Uruchomienie: godot --path prototype --script tools/shot_char3d.gd -- --out=/tmp/char3d.png [--wait=40] [--char=male_scav] [--zoom=4]
const Char3D := preload("res://scripts/char3d.gd")
var _frames := 0
var _out := "/tmp/char3d.png"
var _wait := 40
var _chars: Array = []
var _cfg: Array = []

func _initialize() -> void:
	var zoom := 4.0
	var who := "male_scav"
	var part := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--part="):
			part = int(a.substr(7))
		elif a.begins_with("--char="):
			who = a.substr(7)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.2, 0.19)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	# [anim, kąt celowania (°), kierunek (+1 prawo / −1 lewo), prędkość]
	_cfg = [
		["idle", 0, 1, 0], ["run", 0, 1, 95], ["idle", 45, 1, 0], ["idle", -45, 1, 0], ["idle", 80, 1, 0], ["crouch", 0, 1, 0], ["jump", 20, 1, 0], ["run", -30, 1, 95],
		["idle", 0, -1, 0], ["run", 0, -1, 95], ["idle", 45, -1, 0], ["idle", -45, -1, 0], ["idle", 80, -1, 0], ["crouch", 0, -1, 0], ["fall", 10, -1, 0], ["crouch_walk", 0, -1, 60],
	]
	var sel: Array = []
	for i in _cfg.size():
		if part < 0 or i / 4 == part:
			sel.append(_cfg[i])
	_cfg = sel
	for i in _cfg.size():
		var c := Char3D.new()
		var cols := 8 if part < 0 else 4
		var col := i % cols
		var row := i / cols
		var sp := 1280.0 / cols
		c.position = Vector2(sp * (col + 0.5), 330 + row * 330) if part < 0 else Vector2(sp * (col + 0.5), 600)
		c.scale = Vector2(zoom, zoom)
		root.add_child(c)
		if not c.setup("res://art/char3d/%s.glb" % who, "res://art/char3d/gun_m83.glb"):
			push_error("setup nie powiodło się")
		_chars.append(c)

func _process(delta: float) -> bool:
	_frames += 1
	for i in _chars.size():
		var cfg: Array = _cfg[i]
		var a := deg_to_rad(float(cfg[1]))
		var aim := Vector2(cos(a) * float(cfg[2]), -sin(a))
		_chars[i].update(1.0 / 60.0, cfg[0], float(cfg[2]), aim, float(cfg[3]))
	if _frames == _wait:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
