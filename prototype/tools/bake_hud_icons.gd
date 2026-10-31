extends SceneTree
## Ikony HUD-u z modeli 3D gry: render ortograficzny z przezroczystym tłem, przycięty do zawartości → art/hud/<klucz>.png.
## Duże, bo służą też kartom kodeksu (codex_portrait.gd); HUD zmniejsza je z mipmapami (import: mipmaps/generate=true).
## Bronie: art/char3d/gun_<klucz>.glb (lufa w prawo), sprzęt: art/items3d/<klucz>.glb (lure i flashlight: tools/make_hud_models.py).
##   godot --path prototype --rendering-driver opengl3 --script tools/bake_hud_icons.gd [-- --only=m83,frag]
## Wynik wymaga importu: godot --headless --path prototype --import
const OUT := "res://art/hud/"
const SIZE := 1024
## [klucz ikony, plik, kierunek kamery, obrót wokół osi Z w stopniach, maks. dłuższy bok po przycięciu]
const JOBS := [
	["m83", "res://art/char3d/gun_m83.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["spread12", "res://art/char3d/gun_spread12.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["p64", "res://art/char3d/gun_p64.glb", Vector3(0.12, 0.30, 1.0), 0.0, 480],
	["srut8", "res://art/char3d/gun_srut8.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["lr7", "res://art/char3d/gun_lr7.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["hkm9", "res://art/char3d/gun_hkm9.glb", Vector3(0.12, 0.30, 1.0), 0.0, 600],
	["gniew4", "res://art/char3d/gun_gniew4.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["sokol6", "res://art/char3d/gun_sokol6.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["widmo1", "res://art/char3d/gun_widmo1.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["ciegno6", "res://art/char3d/gun_ciegno6.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["maczeta", "res://art/char3d/gun_maczeta.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["kilof", "res://art/char3d/gun_kilof.glb", Vector3(0.12, 0.30, 1.0), 0.0, 768],
	["frag", "res://art/items3d/frag.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["phos", "res://art/items3d/phos.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["smoke", "res://art/items3d/smoke.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["mine", "res://art/items3d/mine.glb", Vector3(0.6, 0.6, 1.0), 0.0, 384],
	["charge", "res://art/items3d/charge.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["cleankit", "res://art/items3d/cleankit.glb", Vector3(0.45, 0.30, 1.0), 0.0, 384],
	["medkit", "res://art/items3d/medkit.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["defib", "res://art/items3d/defib.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["scanner", "res://art/items3d/scanner.glb", Vector3(0.6, 0.4, 1.0), 0.0, 384],
	["flare", "res://art/items3d/flare.glb", Vector3(0.6, 0.5, 1.0), 0.0, 384],
	["lure", "res://art/items3d/lure.glb", Vector3(0.22, 0.26, 1.0), 0.0, 384],
	["flashlight", "res://art/items3d/flashlight.glb", Vector3(0.45, 0.38, 1.0), 38.0, 384],
	["battery", "res://art/items3d/battery.glb", Vector3(0.5, 0.35, 1.0), 0.0, 384],       # bateria 4,5 V (BATTERY_PLAN.md B2: kodeks)
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
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(-0.5, -0.7, -0.6), Vector3.UP)
	key.light_energy = 1.6
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.7, -0.2, -0.4), Vector3.UP)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.8
	_cam.environment = env
	call_deferred("_next")

func _aabb(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
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
		print("OK ", _jobs.size(), " ikon")
		quit()
		return
	var j: Array = _jobs[_i]
	_cur = (load(j[1]) as PackedScene).instantiate()
	_vp.add_child(_cur)
	if float(j[3]) != 0.0:
		_cur.rotate_z(deg_to_rad(float(j[3])))
	var acc := [null]
	_aabb(_cur, acc)
	var bb: AABB = acc[0]
	var c := bb.get_center()
	var dir: Vector3 = (j[2] as Vector3).normalized()
	_cam.size = maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * 1.2
	_cam.position = c + dir * 10.0
	_cam.look_at(c, Vector3.UP)

func _process(_d: float) -> bool:
	_f += 1
	if _f == 8 and _i >= 0 and _i < _jobs.size():
		var j: Array = _jobs[_i]
		var img := _vp.get_texture().get_image()
		var rect := img.get_used_rect()
		if rect.size.x > 0:
			img = img.get_region(rect)
			var k := float(j[4]) / float(maxi(img.get_width(), img.get_height()))
			if k < 1.0:
				img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT) + "%s.png" % j[0])
		print(j[0], " ", img.get_size())
		_next()
	return false
