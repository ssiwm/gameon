extends SceneTree
## Portrety bestiariusza z modeli 3D gry: ten sam model i ta sama poza spoczynkowa co na misji (enemy3d.gd, klipy i poza z kodu),
## render z przezroczystym tłem, kamera 3/4 od przodu, przycięty do zawartości → art/portraits/<rodzaj>.png (dłuższy bok do 480 px).
## Kodeks (codex_portrait.gd, typ "image") stawia je na podłodze karty z cieniem i poświatą w kolorze wpisu.
##   godot --path prototype --rendering-driver opengl3 --script tools/bake_portraits.gd [-- --only=trzosek,wolek]
## Wynik wymaga importu: godot --headless --path prototype --import
const Enemy3D := preload("res://scripts/enemy3d.gd")
const OUT := "res://art/portraits/"
const SIZE := 1024
const MAX_SIDE := 480
const SETTLE := 24                       ## klatek pozy przed zrzutem (klipy i sprężyny układają się do spoczynku)
## [rodzaj, kierunek kamery (od modelu), animacja]
const JOBS := [
	["trzosek", Vector3(0.75, 0.22, 1.0), "idle"],
	["wolek", Vector3(0.55, 0.12, 1.0), "idle"],
	["skoczek", Vector3(0.55, 0.25, 1.0), "idle"],
	["slepiec", Vector3(1.0, 0.12, 0.6), "idle"],          # model patrzy w +X (widok z boku): kamera bardziej od przodu
	["podsluchacz", Vector3(1.0, 0.12, 0.6), "idle"],          # model patrzy w +X (widok z boku): kamera bardziej od przodu
	["mimik", Vector3(1.0, 0.12, 0.6), "idle"],          # model patrzy w +X (widok z boku): kamera bardziej od przodu
	["cma", Vector3(0.35, 0.35, 1.0), "idle"],
	["kaplan", Vector3(1.0, 0.12, 0.6), "idle"],          # model patrzy w +X (widok z boku): kamera bardziej od przodu
	["rzeznik", Vector3(0.55, 0.12, 1.0), "idle"],
	["zerca", Vector3(0.55, 0.2, 1.0), "idle"],
	["stalker", Vector3(1.0, 0.12, 0.6), "idle"],          # model patrzy w +X (widok z boku): kamera bardziej od przodu
	["nest", Vector3(0.45, 0.25, 1.0), "idle"],
	["vein", Vector3(0.45, 0.18, 1.0), "idle"],
	["leech", Vector3(0.45, 0.3, 1.0), "idle"],
]
var _vp: SubViewport
var _cam: Camera3D
var _jobs: Array = []
var _i := -1
var _f := 0
var _cur: Node3D

func _initialize() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	for j in JOBS:
		if only.is_empty() or String(j[0]) in only:
			_jobs.append(j)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(SIZE, SIZE)
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	# światło jak na karcie kodeksu: ciepłe z góry-przodu, chłodne wypełnienie z boku, lekki kontur od tyłu
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(-0.4, -0.7, -0.7), Vector3.UP)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.94, 0.85)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.8, -0.2, -0.3), Vector3.UP)
	fill.light_energy = 0.45
	fill.light_color = Color(0.8, 0.88, 1.0)
	_vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(Vector3(0.2, -0.3, 1.0), Vector3.UP)
	rim.light_energy = 0.8
	_vp.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	_cam.environment = env
	call_deferred("_next")

func _aabb(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible:
		var mi := n as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
	for c in n.get_children():
		_aabb(c, acc)

func _next() -> void:
	if _cur:
		_cur.queue_free()
		_cur = null
	_i += 1
	_f = 0
	if _i >= _jobs.size():
		print("OK ", _jobs.size(), " portretów")
		quit()
		return
	var j: Array = _jobs[_i]
	var e := Enemy3D.new()
	_vp.add_child(e)
	if not e.setup(String(j[0])):
		push_warning("bez modelu: %s" % j[0])
		e.queue_free()
		call_deferred("_next")
		return
	_cur = e

func _frame_camera(j: Array) -> void:
	var acc := [null]
	_aabb(_cur, acc)
	if acc[0] == null:
		return
	var bb: AABB = acc[0]
	var c := bb.get_center()
	var dir: Vector3 = (j[1] as Vector3).normalized()
	_cam.size = maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * 1.25
	_cam.position = c + dir * maxf(10.0, bb.size.length() * 3.0)
	_cam.far = bb.size.length() * 8.0 + 20.0
	_cam.look_at(c, Vector3.UP)

func _process(delta: float) -> bool:
	if _cur == null or _i < 0 or _i >= _jobs.size():
		return false
	var j: Array = _jobs[_i]
	_f += 1
	_cur.pose(1.0 / 30.0, String(j[2]), false, Color.WHITE)
	if _f == SETTLE:
		_frame_camera(j)
	if _f == SETTLE + 6:
		var img := _vp.get_texture().get_image()
		var rect := img.get_used_rect()
		if rect.size.x > 0:
			img = img.get_region(rect)
			var k := float(MAX_SIDE) / float(maxi(img.get_width(), img.get_height()))
			if k < 1.0:
				img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT) + "%s.png" % j[0])
		print(j[0], " ", img.get_size())
		_next()
	return false
