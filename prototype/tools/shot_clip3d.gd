extends SceneTree
## Stykówka surowych klipów animacji na modelu postaci (bez IK i bez broni): wiersz = klip, kolumny = kolejne chwile klipu.
## Służy do wyboru klipów z biblioteki, zanim trafią do tabeli CLIPS w char_clips.gd.
##   godot --path prototype --script tools/shot_clip3d.gd -- --clips=down,hit,jump_start --out=/tmp/clips.png [--cols=8] [--char=male_scav] [--zoom=5]
## Nazwy to pliki z `art/char3d/anim/` (tools/prep_anim3d.py). Pod każdą klatką czas w sekundach.
const Char3D := preload("res://scripts/char3d.gd")
const CharClips := preload("res://scripts/char_clips.gd")
var _out := "/tmp/clips.png"
var _frames := 0
var _size := Vector2i(1280, 720)
var _poses: Array = []                       ## [szkielet, klip, czas]

func _initialize() -> void:
	var clips: Array = []
	var cols := 8
	var ch := "male_scav"
	var zoom := 5.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--clips="):
			clips = Array(a.substr(8).split(","))
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a.begins_with("--char="):
			ch = a.substr(7)
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var cw := 22.0 * zoom * 1.45
	var rh := 22.0 * zoom * 1.5
	_size = Vector2i(int(cw * cols + 20.0), int(rh * clips.size() + 10.0))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = _size
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.2, 0.19)
	bg.size = Vector2(_size)
	root.add_child(bg)
	for r in clips.size():
		var y := rh * (r + 1) - 26.0
		var ground := ColorRect.new()
		ground.color = Color(0.3, 0.34, 0.32)
		ground.position = Vector2(6.0, y)
		ground.size = Vector2(_size.x - 12.0, 2.0)
		root.add_child(ground)
		for k in cols:
			var c := Char3D.new()
			c.position = Vector2(10.0 + cw * (k + 0.5), y)
			c.scale = Vector2(zoom, zoom)
			c.clips_on = false
			root.add_child(c)
			if not c.setup(ch, "m83"):
				push_error("setup nie powiodło się: %s" % ch)
				continue
			var sk: Skeleton3D = c._sk
			var an := CharClips.clip(String(clips[r]), sk)
			if an == null:
				push_error("brak klipu: %s" % clips[r])
				continue
			var t := an.length * float(k) / float(maxi(cols - 1, 1))
			_poses.append([sk, an, t])
			var l := Label.new()
			l.text = ("%s  %.2f s" % [clips[r], t]) if k == 0 else "%.2f" % t
			l.position = Vector2(10.0 + cw * k + 4.0, y + 4.0)
			l.add_theme_font_size_override("font_size", 12)
			root.add_child(l)

func _process(_d: float) -> bool:
	_frames += 1
	for e in _poses:                                              # poza ustawiana co klatkę: ustawiona raz przed pierwszą klatką nie trafiała do renderu
		var sk: Skeleton3D = e[0]
		var an: Animation = e[1]
		for tr in an.get_track_count():
			var bi := sk.find_bone(String(an.track_get_path(tr).get_concatenated_subnames()))
			if an.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bi, an.rotation_track_interpolate(tr, float(e[2])))
			else:
				sk.set_bone_pose_position(bi, an.position_track_interpolate(tr, float(e[2])))
	if _frames == 30:
		root.get_texture().get_image().get_region(Rect2i(Vector2i.ZERO, _size)).save_png(_out)   # okno bywa większe niż zadany rozmiar (ekran 4K)
		print("saved ", _out)
		quit()
	return false
