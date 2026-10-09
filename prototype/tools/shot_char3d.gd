extends SceneTree
## Zrzut kontrolny postaci 3D: zestawy póz / broni / wyglądów / stanów broni (przeładowanie, cios, odrzut).
## godot --path prototype --script tools/shot_char3d.gd -- --set=poses|weapons|looks|states [--part=N] [--zoom=6] [--out=/tmp/char3d.png] [--wait=40]
## Wiersz konfiguracji: {anim, aim (°), dir (+1 prawo / −1 lewo), speed, gun, char, extra (rad), kick (px), reload (0..1), swing (0..1)}
const Char3D := preload("res://scripts/char3d.gd")
const WEAPONS := ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6", "maczeta", "kilof"]
const LOOKS := ["male_scav", "male_hazmat", "male_medic", "female_scav", "female_hazmat", "female_medic"]
var _frames := 0
var _out := "/tmp/char3d.png"
var _wait := 40
var _chars: Array = []
var _cfg: Array = []
var _light := false

func _row(anim := "idle", aim := 0, dir := 1, speed := 0, gun := "m83", ch := "male_scav", extra := 0.0, kick := 0.0, reload := -1.0, swing := -1.0, thr := -1.0) -> Dictionary:
	return {"throw": thr, "anim": anim, "aim": aim, "dir": dir, "speed": speed, "gun": gun, "char": ch, "extra": extra, "kick": kick, "reload": reload, "swing": swing}

func _initialize() -> void:
	var zoom := 6.0
	var part := -1
	var set_name := "poses"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--part="):
			part = int(a.substr(7))
		elif a == "--light":
			_light = true
		elif a.begins_with("--set="):
			set_name = a.substr(6)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.2, 0.19)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	if _light:
		var cm := CanvasModulate.new()
		cm.color = Color(0.12, 0.12, 0.15)
		root.add_child(cm)
	var all: Array = []
	match set_name:
		"poses":
			all = [_row("idle", 0), _row("run", 0, 1, 95), _row("idle", 45), _row("idle", -45), _row("idle", 80), _row("crouch", 0), _row("jump", 20), _row("run", -30, 1, 95),
					_row("idle", 0, -1), _row("run", 0, -1, 95), _row("idle", 45, -1), _row("idle", -45, -1), _row("idle", 80, -1), _row("crouch", 0, -1), _row("fall", 10, -1), _row("crouch_walk", 0, -1, 60)]
		"aims":
			for a in [-80, -50, -20, 20, 50, 70, 80, 90]:
				all.append(_row("idle", a, 1))
		"misc":
			all = [_row("down"), _row("idle", 0, 1, 0, "m83", "male_scav", 0.0, 0.0, -1.0, -1.0, 0.1), _row("idle", 20, 1, 0, "m83", "male_scav", 0.0, 0.0, -1.0, -1.0, 0.5), _row("idle", 20, 1, 0, "m83", "male_scav", 0.0, 0.0, -1.0, -1.0, 0.85), _row("down", 0, -1, 0, "m83", "female_scav")]
		"crouch":
			all = [_row("crouch", 0), _row("crouch", 40), _row("crouch", -35), _row("crouch_walk", 0, 1, 60), _row("crouch", 0, -1), _row("crouch_walk", 0, -1, 60), _row("crouch", 0, 1, 0, "p64"), _row("crouch", 0, 1, 0, "maczeta")]
		"cmp":
			all = [_row("idle", 0), _row("crouch", 0)]
		"weapons":
			for w in WEAPONS:
				all.append(_row("idle", 0, 1, 0, w))
		"looks":
			for c in LOOKS:
				all.append(_row("idle", 0, 1, 0, "m83", c))
				all.append(_row("run", 20, -1, 95, "p64", c))
		"states":
			all = [_row("idle", 0, 1, 0, "m83", "male_scav", 0.0, 3.0), _row("idle", 0, 1, 0, "m83", "male_scav", 0.45, 0.0, 0.25), _row("idle", 0, 1, 0, "m83", "male_scav", 0.0, 0.0, 0.5), _row("idle", 0, 1, 0, "m83", "male_scav", 0.5, 0.0, 0.8),
				_row("idle", 0, 1, 0, "maczeta", "male_scav", -1.0, 0.0, -1.0, 0.1), _row("idle", 0, 1, 0, "maczeta", "male_scav", 0.1, 3.0, -1.0, 0.35), _row("idle", 0, 1, 0, "kilof", "male_scav", 0.8, 0.0, -1.0, 0.6), _row("idle", 0, 1, 0, "p64", "male_scav", 0.0, 2.0),
				_row("idle", 0, -1, 0, "gniew4", "female_scav", 0.0, 3.0), _row("idle", 0, -1, 0, "p64", "female_scav", 0.6), _row("run", 30, -1, 95, "lr7", "male_hazmat"), _row("crouch", 0, -1, 0, "ciegno6", "male_medic")]
	for i in all.size():
		if part < 0 or i / 4 == part:
			_cfg.append(all[i])
	var cols := 4 if part >= 0 else maxi(1, mini(8, _cfg.size()))
	for i in _cfg.size():
		var cfg: Dictionary = _cfg[i]
		var c := Char3D.new()
		var col := i % cols
		var row := i / cols
		var sp := 1280.0 / cols
		c.position = Vector2(sp * (col + 0.5), (600.0 if part >= 0 else 330.0 + row * 330.0))
		c.scale = Vector2(zoom, zoom)
		root.add_child(c)
		if not c.setup(cfg["char"], cfg["gun"]):
			push_error("setup nie powiodło się: %s" % cfg)
		_chars.append(c)
		if _light:                                           # światło z prawej-góry każdej postaci (sprawdza relief z mapy normalnych i odbicie flip_h)
			var l := PointLight2D.new()
			var gt := GradientTexture2D.new()
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(1.0, 0.5)
			gt.width = 256
			gt.height = 256
			var g := Gradient.new()
			g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
			gt.gradient = g
			l.texture = gt
			l.texture_scale = zoom * 1.2
			l.height = 80.0
			l.energy = 1.3
			l.position = c.position + Vector2(90.0 * zoom / 6.0, -110.0 * zoom / 6.0)
			root.add_child(l)

func _process(_d: float) -> bool:
	_frames += 1
	for i in _chars.size():
		var cfg: Dictionary = _cfg[i]
		var c: Node2D = _chars[i]
		var a := deg_to_rad(float(cfg["aim"]))
		var aim := Vector2(cos(a) * float(cfg["dir"]), -sin(a))
		c.gun_extra = float(cfg["extra"])
		c.gun_kick_px = float(cfg["kick"])
		c.reload_t = float(cfg["reload"])
		c.swing_t = float(cfg["swing"])
		c.throw_t = float(cfg["throw"])
		c.update(1.0 / 60.0, cfg["anim"], float(cfg["dir"]), aim, float(cfg["speed"]))
	if _frames == _wait:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
