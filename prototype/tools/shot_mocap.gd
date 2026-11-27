extends SceneTree
## Podgląd klipu ruchu w grze (VOICE_MOCAP_PLAN.md B1): mężczyzna i kobieta obok siebie, klip + IK broni jak w grze. Klip stanu można
## podmienić bez zmiany tabeli `char_clips.gd` (`--clipfile=stan:plik[:rev]`, czytane przez CharClips), więc obecny klip i kandydaci mocap
## renderują się tym samym kodem. Zapisuje klatki PNG (30 kl./s); film składa ffmpeg:
##   godot --path prototype --script tools/shot_mocap.gd -- --anim=run --out=C:/tmp/mc [--speed=95] [--back] [--chars=male_scav,female_scav]
##         [--gun=m83] [--frames=90] [--zoom=9] [--label=TEKST] [--clipfile=run:mc_neutral_fr --clipfile=run_jog:mc_neutral_fr]
##   ffmpeg -y -framerate 30 -i C:/tmp/mc/f_%03d.png -pix_fmt yuv420p mc.mp4
const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const W := 640
const H := 360
var _out := "C:/tmp/mc"
var _frames := 90
var _tick := 0
var _saved := 0
var _anim := "run"
var _speed := -1.0
var _back := false
var _aim := 0.0
var _chars: Array = []

func _initialize() -> void:
	var zoom := 9.0
	var names := ["male_scav", "female_scav"]
	var gun := "m83"
	var label := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--anim="):
			_anim = a.substr(7)
		elif a.begins_with("--speed="):
			_speed = float(a.substr(8))
		elif a == "--back":
			_back = true
		elif a.begins_with("--aim="):
			_aim = float(a.substr(6))
		elif a.begins_with("--chars="):
			names = Array(a.substr(8).split(","))
		elif a.begins_with("--gun="):
			gun = a.substr(6)
		elif a.begins_with("--label="):
			label = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(W, H)
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.2, 0.19)
	bg.size = Vector2(W, H)
	root.add_child(bg)
	var ground := ColorRect.new()                         # linia podłoża: widać, czy stopy stoją na ziemi
	ground.color = Color(0.3, 0.34, 0.32)
	ground.position = Vector2(10.0, 318.0)
	ground.size = Vector2(W - 20.0, 2.0)
	root.add_child(ground)
	if label != "":
		var l := Label.new()
		l.text = label
		l.position = Vector2(14.0, 328.0)
		l.add_theme_font_size_override("font_size", 14)
		l.modulate = Color(1, 1, 1, 0.75)
		root.add_child(l)
	for i in names.size():
		var c := Char3D.new()
		c.position = Vector2(W * (i + 0.5) / names.size(), 318.0)
		c.scale = Vector2(zoom, zoom)
		c.clips_on = true
		root.add_child(c)
		if not c.setup(String(names[i]), gun):
			push_error("setup nie powiodło się: %s" % names[i])
		_chars.append(c)

func _process(_d: float) -> bool:
	_tick += 1
	var a := deg_to_rad(_aim)
	var moving := _anim == "run" or _anim == "crouch_walk"
	var speed := (_speed if _speed >= 0.0 else (45.0 if _anim == "crouch_walk" else 95.0)) if moving else 0.0
	for c in _chars:
		c.back_run = _back and moving
		c.update(DT, _anim, 1.0, Vector2(cos(a), -sin(a)), speed, true)
	if _tick > 30 and _tick % 2 == 0:
		root.get_texture().get_image().get_region(Rect2i(0, 0, W, H)).save_png("%s/f_%03d.png" % [_out, _saved])
		_saved += 1
		if _saved >= _frames:
			print("saved ", _saved, " klatek w ", _out)
			quit()
	return false
