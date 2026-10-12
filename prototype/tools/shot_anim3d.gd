extends SceneTree
## Porównanie ruchu postaci 3D: ta sama postać parami — z lewej pozy z kodu, z prawej klip animacji (char_clips.gd) z IK na wierzchu.
## Zapisuje klatki PNG (30 kl./s) do katalogu; film składa ffmpeg:
##   godot --path prototype --script tools/shot_anim3d.gd -- --out=/tmp/anim [--frames=90] [--zoom=10]
##   ffmpeg -y -framerate 30 -i /tmp/anim/f_%03d.png -pix_fmt yuv420p /tmp/anim/run.mp4
## Wiersz: {char, gun, aim (°), speed (px/s), back (bieg tyłem), toggle (s: co tyle zmiana bieg ↔ postój, 0 = ciągły bieg), label}
const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const ROWS := [
	{"char": "male_scav", "gun": "m83", "aim": 0, "speed": 95.0, "label": "bieg, karabin"},
	{"char": "female_medic", "gun": "p64", "aim": 30, "speed": 95.0, "label": "inny model, pistolet, cel w górę"},
	{"char": "male_hazmat", "gun": "srut8", "aim": -15, "speed": 95.0, "toggle": 0.7, "label": "start / stop"},
	{"char": "female_scav", "gun": "lr7", "aim": 10, "speed": 95.0, "back": true, "label": "bieg tyłem"},
]
var _out := "/tmp/anim"
var _frames := 90
var _tick := 0
var _saved := 0
var _chars: Array = []

func _initialize() -> void:
	var zoom := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.2, 0.19)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	for i in ROWS.size():
		var cfg: Dictionary = ROWS[i]
		var cell := Vector2(640.0 * (i % 2), 360.0 * (i / 2))
		var ground := ColorRect.new()                         # linia podłoża: widać, czy stopy stoją na ziemi
		ground.color = Color(0.3, 0.34, 0.32)
		ground.position = cell + Vector2(20.0, 318.0)
		ground.size = Vector2(600.0, 2.0)
		root.add_child(ground)
		for k in 2:
			var c := Char3D.new()
			c.position = cell + Vector2(170.0 + 300.0 * k, 318.0)
			c.scale = Vector2(zoom, zoom)
			c.clips_on = k == 1
			root.add_child(c)
			if not c.setup(cfg["char"], cfg["gun"]):
				push_error("setup nie powiodło się: %s" % cfg)
			_chars.append([c, cfg])
			var l := Label.new()
			l.text = "%s — %s" % ["KOD" if k == 0 else "KLIP + IK", cfg["label"]]
			l.position = cell + Vector2(40.0 + 300.0 * k, 328.0)
			l.add_theme_font_size_override("font_size", 14)
			root.add_child(l)

func _process(_d: float) -> bool:
	_tick += 1
	var t := _tick * DT
	for e in _chars:
		var c: Node2D = e[0]
		var cfg: Dictionary = e[1]
		var a := deg_to_rad(float(cfg["aim"]))
		var tg := float(cfg.get("toggle", 0.0))
		var running := tg <= 0.0 or int(t / tg) % 2 == 0
		c.back_run = bool(cfg.get("back", false)) and running
		c.update(DT, "run" if running else "idle", 1.0, Vector2(cos(a), -sin(a)), float(cfg["speed"]) if running else 0.0)
	if _tick > 20 and _tick % 2 == 0:
		root.get_texture().get_image().get_region(Rect2i(0, 0, 1280, 720)).save_png("%s/f_%03d.png" % [_out, _saved])   # okno bywa większe niż 1280×720 (ekran 4K)
		_saved += 1
		if _saved >= _frames:
			print("saved ", _saved, " klatek w ", _out)
			quit()
	return false
