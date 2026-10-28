extends SceneTree
## Rendery przedmiotów zaopatrzenia na karty stanowisk (STATION_CARDS_PLAN.md, etap E0): modele z art/items3d/ (te same co w świecie gry),
## pod ciepłą lampą stanowiska, przezroczyste tło, kamera 3/4 z góry-przodu, przycięte do zawartości → art/item_renders/<model>.png
## (dłuższy bok do 320 px — miniatura na kafelku przy 4K i skali stanowisk ×1,4). Które rodzaje dostają który model: `ItemIcon.RENDERS`;
## rodzaje bez modelu (amunicja 40 mm, D3a) zostają przy ikonie i są wypisane na końcu jako lista braków.
##   godot --path prototype --rendering-driver opengl3 --script tools/bake_items.gd [-- --only=frag,mine]
## Wynik wymaga importu (z mipmapami — miniatury są kilka razy mniejsze od renderu): godot --headless --path prototype --import
const ItemIcon := preload("res://scripts/item_icon.gd")
const Throwables := preload("res://scripts/throwables.gd")
const MODEL_DIR := "res://art/items3d/"
const SIZE := 768
const MAX_SIDE := 320
const SETTLE := 4                        ## klatek przed zrzutem (wczytanie tekstur i cieni)
const VIEW := Vector3(0.55, 0.45, 1.0)   ## kierunek kamery od modelu (modele patrzą w +Z, jak w widoku 3D gry)
## Wyjątki od `VIEW`: płaskie i wysokie bryły czytelniejsze z innej strony.
const VIEWS := {
	"mine": Vector3(0.45, 0.6, 1.0),
	"charge": Vector3(0.5, 0.55, 1.0),
}
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
	for m in ItemIcon.render_models():
		if only.is_empty() or String(m) in only:
			_jobs.append(m)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ItemIcon.RENDER_DIR))
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
	# lampa stanowiska: ciepła, z góry i trochę od przodu; słabe chłodne wypełnienie od boku i kontur od tyłu — bryła odcina się od ciemnej karty
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(-0.25, -1.0, -0.45), Vector3.UP)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.86, 0.66)
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.9, -0.15, -0.3), Vector3.UP)
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.84, 1.0)
	_vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(Vector3(0.2, -0.35, 1.0), Vector3.UP)
	rim.light_energy = 0.7
	rim.light_color = Color(1.0, 0.9, 0.78)
	_vp.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.58)
	env.ambient_light_energy = 0.45
	_cam.environment = env
	call_deferred("_next")

func _aabb(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible:
		var mi := n as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
	for c in n.get_children():
		_aabb(c, acc)

## Jak w widoku 3D (`view3d._item_model`): słabszy połysk, bo mapa chropowatości z generatora daje „pogniecione” odbłyski w bliskim świetle.
func _tune(n: Node) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if sm != null:
				sm.metallic_specular = 0.12
				sm.metallic = minf(sm.metallic, 0.6)

func _next() -> void:
	if _cur:
		_cur.queue_free()
		_cur = null
	_i += 1
	_f = 0
	if _i >= _jobs.size():
		print("OK ", _jobs.size(), " renderów")
		var missing: Array = []
		for k in Throwables.SHOP_ORDER:
			if ItemIcon.render_model(String(k)) == "":
				missing.append(k)
		print("bez modelu (zostaje ikona): ", ", ".join(missing))
		quit()
		return
	var path := MODEL_DIR + String(_jobs[_i]) + ".glb"
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("bez modelu: %s" % path)
		call_deferred("_next")
		return
	_cur = ps.instantiate() as Node3D
	_tune(_cur)
	_vp.add_child(_cur)

func _frame_camera(model: String) -> void:
	var acc := [null]
	_aabb(_cur, acc)
	if acc[0] == null:
		return
	var bb: AABB = acc[0]
	var c := bb.get_center()
	var dir: Vector3 = (VIEWS.get(model, VIEW) as Vector3).normalized()
	_cam.size = bb.size.length() * 1.1
	_cam.position = c + dir * maxf(10.0, bb.size.length() * 3.0)
	_cam.near = 0.05
	_cam.far = bb.size.length() * 8.0 + 20.0
	_cam.look_at(c, Vector3.UP)

func _process(_delta: float) -> bool:
	if _cur == null or _i < 0 or _i >= _jobs.size():
		return false
	var model := String(_jobs[_i])
	_f += 1
	if _f == 1:
		_frame_camera(model)
	if _f == SETTLE:
		var img := _vp.get_texture().get_image()
		var rect := img.get_used_rect()
		if rect.size.x > 0:
			img = img.get_region(rect.grow(2).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
			var k := float(MAX_SIDE) / float(maxi(img.get_width(), img.get_height()))
			if k < 1.0:
				img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(ItemIcon.RENDER_DIR) + "%s.png" % model)
		print(model, " ", img.get_size())
		_next()
	return false
