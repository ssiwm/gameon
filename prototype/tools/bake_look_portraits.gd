extends SceneTree
## Miniatury strojów (szafka → WYGLĄD): ten sam model 3D postaci i ta sama poza spoczynkowa co podgląd w szafce (char3d.gd, tryb `preview`),
## kamera 3/4, przezroczyste tło, przycięte do zawartości → art/portraits/look_<płeć>_<strój>.png (dłuższy bok do 480 px). Paleta domyślna.
## Dotąd kafle stroju rysowały stary arkusz 2D, a duży podgląd obok — model 3D; teraz oba pokazują to samo.
##   godot --path prototype --rendering-driver opengl3 --script tools/bake_look_portraits.gd
## Wynik wymaga importu: godot --headless --path prototype --import
const Char3D := preload("res://scripts/char3d.gd")
const Look := preload("res://scripts/look.gd")
const OUT := "res://art/portraits/"
const SIZE := 1024
const MAX_SIDE := 480
const SETTLE := 30                    ## klatek pozy przed zrzutem
const YAW := 32.0                     ## obrót postaci (stopnie): 3/4 od przodu

var _vp: SubViewport
var _holder: Node2D
var _jobs: Array = []                 ## [płeć, strój]
var _i := -1
var _f := 0
var _cur: Node2D

func _initialize() -> void:
	for g in Look.GENDERS:
		for o in Look.OUTFITS:
			_jobs.append([String(g), String(o)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(SIZE, SIZE)
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_holder = Node2D.new()
	var k := float(SIZE) * 0.92 / 22.0                 # jak Look3DView: postać (22 j. świata) na ~92% wysokości
	_holder.scale = Vector2(k, k)
	_holder.position = Vector2(SIZE * 0.5, SIZE * 0.97)
	_vp.add_child(_holder)
	call_deferred("_next")

func _next() -> void:
	if _cur:
		_cur.queue_free()
		_cur = null
	_i += 1
	_f = 0
	if _i >= _jobs.size():
		print("OK ", _jobs.size(), " miniatur strojów")
		quit()
		return
	var j: Array = _jobs[_i]
	var c := Char3D.new()
	c.preview = true
	c.preview_ss = 16
	_holder.add_child(c)
	if not c.setup(Char3D.char_name_for(String(j[0]), String(j[1]))):
		push_warning("bez modelu: %s %s" % j)
		c.queue_free()
		call_deferred("_next")
		return
	c.set_palette(0)
	_cur = c

func _process(_delta: float) -> bool:
	if _cur == null or _i < 0 or _i >= _jobs.size():
		return false
	_f += 1
	_cur.set_view_yaw(YAW)
	_cur.update(1.0 / 30.0, "idle", 1.0, Vector2(1.0, 0.0), 0.0, true, Color.WHITE)
	if _f == SETTLE:
		var j: Array = _jobs[_i]
		var img := _vp.get_texture().get_image()
		var rect := img.get_used_rect()
		if rect.size.x > 0:
			img = img.get_region(rect)
			var s := float(MAX_SIDE) / float(maxi(img.get_width(), img.get_height()))
			if s < 1.0:
				img.resize(maxi(1, roundi(img.get_width() * s)), maxi(1, roundi(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT) + "look_%s_%s.png" % j)
		print("look_%s_%s " % j, img.get_size())
		_next()
	return false
