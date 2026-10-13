extends SceneTree
## Stykówka ruchu wrogów 3D: dla każdego rodzaju trzy wiersze — poza z kodu (enemy3d.gd), surowy klip animacji na tym samym szkielecie
## i to, co widać w grze (klip + postawa i ręce z profilu rodzaju). Służy do oceny, czy klip z biblioteki pasuje do potwora.
##   godot --path prototype --script tools/shot_enemy_clip3d.gd -- --kinds=wolek,slepiec --anim=walk --clip=walk --out=/tmp/enemy.png [--cols=8] [--px=190]
## Ruch w czasie: `--movie=KATALOG [--frames=90]` zapisuje klatki PNG (30 kl./s; film składa ffmpeg) — górny wiersz poza z kodu, dolny klip + profil.
## --anim: nazwa animacji gry (idle | walk | windup | sleep), --clip: plik z `art/char3d/anim/` (tools/prep_anim3d.py).
const Enemy3D := preload("res://scripts/enemy3d.gd")
const CharClips := preload("res://scripts/char_clips.gd")
const CELL_W := 4.2                          ## m: szerokość komórki (Stalker ma 4,4 m wysokości, ale jest wąski)
const ROW_H := 5.0                           ## m: wysokość wiersza
var _out := "/tmp/enemy.png"
var _frames := 0
var _size := Vector2i(1600, 900)
var _poses: Array = []                       ## [szkielet, klip, czas]
var _coded: Array = []                       ## [wróg, animacja, czas] — pozy z kodu liczymy po kilku klatkach (drzewo klipów musi być w scenie)
var _movie := ""                             ## katalog klatek filmu (pusty = stykówka)
var _movie_n := 90
var _live: Array = []                        ## [wróg, animacja] — film: poza liczona co klatkę
var _saved := 0
var _vp: SubViewport                         ## własny obraz o zadanym rozmiarze (okno gry bywa większe: ekran 4K)

func _initialize() -> void:
	var kinds: Array = ["wolek", "slepiec", "podsluchacz", "stalker"]
	var anim := "walk"
	var clip := "walk"
	var cols := 8
	var px := 190.0                              # szerokość komórki w pikselach
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--kinds="):
			kinds = Array(a.substr(8).split(","))
		elif a.begins_with("--anim="):
			anim = a.substr(7)
		elif a.begins_with("--clip="):
			clip = a.substr(7)
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a.begins_with("--px="):
			px = float(a.substr(5))
		elif a.begins_with("--movie="):
			_movie = a.substr(8)
		elif a.begins_with("--frames="):
			_movie_n = int(a.substr(9))
	if _movie != "":
		cols = kinds.size()
		DirAccess.make_dir_recursive_absolute(_movie)
	var rows := 2 if _movie != "" else kinds.size() * 3
	_size = Vector2i(int(px * cols), int(px * ROW_H / CELL_W * rows))
	_vp = SubViewport.new()
	_vp.size = _size
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.2, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-48, -28, 0)
	dl.light_energy = 1.4
	_vp.add_child(dl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ROW_H * rows
	_vp.add_child(cam)
	var cy := -ROW_H * (rows - 1) * 0.5 + ROW_H * 0.42
	cam.look_at_from_position(Vector3(0.0, cy, 30.0), Vector3(0.0, cy, 0.0), Vector3.UP)
	cam.current = true
	if _movie != "":
		for r in 2:
			for k in cols:
				var em: Node3D = (Enemy3D as Script).new()
				_vp.add_child(em)
				if not em.setup(String(kinds[k])):
					push_error("setup nie powiodło się: %s" % kinds[k])
					continue
				em.position = Vector3((k - (cols - 1) * 0.5) * CELL_W, -ROW_H * r, 0.0)
				em.set("clips_on", r == 1)
				_live.append([em, anim])
				var lm := Label.new()
				lm.text = "%s — %s" % [kinds[k], "kod" if r == 0 else "klip + profil"]
				lm.position = Vector2(px * k + 8.0, float(_size.y) * (r + 1) / 2.0 - 22.0)
				lm.add_theme_font_size_override("font_size", 14)
				_vp.add_child(lm)
		return
	for r in rows:
		var kind := String(kinds[r / 3])
		var use_clip := r % 3 == 1
		for k in cols:
			var e: Node3D = (Enemy3D as Script).new()
			_vp.add_child(e)
			if not e.setup(kind):
				push_error("setup nie powiodło się: %s" % kind)
				continue
			e.position = Vector3((k - (cols - 1) * 0.5) * CELL_W, -ROW_H * r, 0.0)
			var f := float(k) / float(cols)
			if use_clip:
				var sk: Skeleton3D = e.get("_sk")
				var an := CharClips.clip(clip, sk)
				if an == null:
					push_error("brak klipu: %s" % clip)
					continue
				_poses.append([sk, an, an.length * f])
			else:
				e.set("clips_on", r % 3 == 2)
				var cyc := float((Enemy3D.SPEC[kind] as Dictionary).get("cycle", 1.0))
				_coded.append([e, anim, cyc * f if (anim == "walk" or anim == "run") else 2.4 * f])
		var l := Label.new()
		l.text = "%s — %s" % [kind, ["kod: " + anim, "surowy klip " + clip, "w grze: klip + profil"][r % 3]]
		l.position = Vector2(8.0, float(_size.y) * (r + 1) / rows - 22.0)
		l.add_theme_font_size_override("font_size", 14)
		_vp.add_child(l)

func _process(_d: float) -> bool:
	_frames += 1
	if _movie != "":
		for c in _live:
			(c[0] as Node3D).call("pose", 1.0 / 60.0, c[1], false, Color.WHITE)
		if _frames > 40 and _frames % 2 == 0:
			_vp.get_texture().get_image().save_png("%s/f_%03d.png" % [_movie, _saved])
			_saved += 1
			if _saved >= _movie_n:
				print("saved ", _saved, " klatek w ", _movie)
				quit()
		return false
	if _frames == 5:
		for c in _coded:
			(c[0] as Node3D).call("pose", 0.0001, c[1], false, Color.WHITE)
			(c[0] as Node3D).call("pose", 1.0, c[1], false, Color.WHITE)      # przejście wag i udziału klipu do końca
			(c[0] as Node3D).set("_phase", 0.0)
			(c[0] as Node3D).call("pose", float(c[2]), c[1], false, Color.WHITE)
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
		_vp.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
