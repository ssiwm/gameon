extends SceneTree
## Zrzuty kontrolne assetów pierwszego planu (front3d.gd, elementy podłoża, fasady wejść) pojedynczo, w neutralnym świetle:
## godot --path prototype --script tools/shot_front_assets.gd -- --out=C:/tmp/front_assets
## Każdy asset to osobny PNG `<nr>_<nazwa>.png` (1024×1024).
const Front3D := preload("res://scripts/front3d.gd")
const Level3D := preload("res://scripts/level3d.gd")
var _out := "user://front_assets"
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _jobs: Array = []                      # [nazwa, Callable budująca węzeł, Vector3 punkt kamery, Vector3 cel, float fov]
var _i := -1
var _wait := 0

func _initialize() -> void:
	var models: Array = []                     # --models=a,b: tylko te modele z art/items3d w naturalnej skali (porównanie kandydatów)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--models="):
			models = a.substr(9).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1024, 1024)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1024, 1024)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.45, -0.55, -0.7), Vector3.UP)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic")
	_vp.add_child(floor_mi)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	if not models.is_empty():
		for k: String in models:
			_jobs.append([k, _model.bind(k), Vector3.ZERO, Vector3.ZERO, 35.0])
		return
	# pierwszy plan (front3d.gd): pnie w całości i z bliska, krzew, kępy; rury, łańcuch, kable, lampa (tunele, stacje, kryjówka)
	for k in ["pine", "snag"]:
		_jobs.append([k + "_caly", _elem.bind(k, 1), Vector3(0, 8.0, 26.0), Vector3(0, 8.0, 0), 40.0])
		_jobs.append([k + "_z_bliska", _elem.bind(k, 1), Vector3(0, 1.4, 4.2), Vector3(0, 1.1, 0), 40.0])
	for k in ["shrub", "ferns", "grass"]:
		var h := 2.0 if k == "shrub" else 1.2
		_jobs.append([k, _elem.bind(k, 3), Vector3(0, h, 4.5 + h * 1.6), Vector3(0, h * 0.7, 0), 40.0])
	for k in ["pipe", "pipes2", "chain", "cables", "lamp"]:
		_jobs.append([k, _elem.bind(k, 1), Vector3(0, 3.0, 9.0), Vector3(0, 3.0, 0), 40.0])
	# podłoże lasu: elementy z `Front3D.GROUND_PROPS`
	for k in ["rock", "rock_b", "rock_c", "trunk_big", "ph_branches_a", "ph_branches_b", "ph_fern_a", "ph_fern_c", "fence", "logs", "tyre", "bones"]:
		_jobs.append([k, _prop.bind(k), Vector3.ZERO, Vector3.ZERO, 35.0])
	# fasady ścian wejścia budynków (`Level3D._build_facades`)
	_jobs.append(["fasada_drzwi_i_okno", _facade.bind(false), Vector3(-7.5, 4.2, 7.0), Vector3(0, 3.6, 2.6), 45.0])
	_jobs.append(["fasada_brama", _facade.bind(true), Vector3(-7.5, 3.2, 7.0), Vector3(0, 2.6, 2.6), 45.0])

func _elem(kind: String, seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + kind.hash()
	var res: Array = Front3D._element_mesh(kind, 6.0, 0.0, Vector2(0.0, 6.0), rng, [], false)
	var mats := Front3D.materials()
	var mi := MeshInstance3D.new()
	mi.mesh = res[0]
	var keys: Array = res[1]
	for si in keys.size():
		mi.set_surface_override_material(si, mats[keys[si]])
	return mi

func _prop(name: String) -> Node3D:
	var mm := Level3D.model_mesh(name)
	var mi := MeshInstance3D.new()
	if mm.is_empty():
		return mi
	var sz: Vector2 = Front3D.PROP_SIZE.get(name, Vector2(0.6, 1.2))
	var local: Transform3D = mm[1]
	var ab := local * (mm[0] as Mesh).get_aabb()
	var s := (sz.x + sz.y) * 0.5 / maxf(maxf(ab.size.x, ab.size.z), 0.001)
	mi.mesh = mm[0]
	var b := Basis(Vector3.UP, 0.5).scaled(Vector3(s, s, s))
	mi.transform = Transform3D(b, Vector3(0, -(b * ab.position).y, 0)) * local
	return mi

func _model(name: String) -> Node3D:
	var mm := Level3D.model_mesh(name)
	var mi := MeshInstance3D.new()
	if mm.is_empty():
		return mi
	var local: Transform3D = mm[1]
	var ab := local * (mm[0] as Mesh).get_aabb()
	mi.mesh = mm[0]
	mi.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(0, -ab.position.y, 0)) * local
	return mi

func _facade(gate: bool) -> Node3D:
	var n := Node3D.new()
	Level3D.shell_entry_cells = {}
	for r in range(-6, 0):
		Level3D.shell_entry_cells[Vector2i(0, r)] = true
	# kafel r: y od −(r+1)·T do −r·T → wiersze −6..−1 to wysokość 0..7,85 m nad y=0
	if gate:
		Level3D.shell_facades = [{"c": 0, "out": -1, "kind": "gate", "rt": -4, "rb": -1}]
	else:
		Level3D.shell_facades = [{"c": 0, "out": -1, "kind": "door", "rt": -2, "rb": -1}, {"c": 0, "out": -1, "kind": "window", "rt": -5, "rb": -4}]
	var box := BoxMesh.new()
	box.size = Vector3(Level3D.T, Level3D.T, Level3D.DEPTH_FRONT + Level3D.DEPTH_BACK)
	var mats := {
		"C": Level3D.make_pbr("concrete", 0.33, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone"),
		"roof": Level3D.make_pbr("roof", 0.25, Color(0.30, 0.22, 0.20), 0.8, 1.0, 1.0, false, "rust"),
		"M": Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
	}
	Level3D._build_facades(n, box, mats)
	n.position = Vector3(0, -Level3D.T * 0.0 - 0.0, 0)
	return n

func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := _vp.get_texture().get_image()
			var j: Array = _jobs[_i]
			img.save_png("%s/%02d_%s.png" % [_out, _i + 1, j[0]])
		return false
	_i += 1
	if _i >= _jobs.size():
		print("front assets: %d" % _jobs.size())
		quit()
		return true
	for c in _stage.get_children():
		c.queue_free()
	var j: Array = _jobs[_i]
	var node: Node3D = (j[1] as Callable).call()
	_stage.add_child(node)
	var eye: Vector3 = j[2]
	var at: Vector3 = j[3]
	if eye == Vector3.ZERO:                    # element podłoża: kadr z jego bryły
		var ab := (node as MeshInstance3D).get_aabb() if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else AABB()
		ab = node.transform * ab
		var r := maxf(ab.size.length() * 0.5, 0.3)
		at = ab.get_center()
		eye = at + Vector3(0.0, r * 0.7, r * 2.6)
	_cam.fov = float(j[4])
	_cam.look_at_from_position(eye, at, Vector3.UP)
	_wait = 8
	return false
