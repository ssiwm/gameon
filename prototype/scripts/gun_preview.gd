extends Node
## Wspólny, jednorazowy render wyposażonej broni. Jeden viewport dla HUD-u i 32 ostatnie tekstury;
## po wypieku model znika, a viewport przestaje renderować. Nie zapisuje nic do res:// ani profilu.
const GunModel := preload("res://scripts/gun_model.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Parts := preload("res://scripts/parts.gd")
const FRAME := Vector2i(768, 256)
const CACHE_LIMIT := 32
signal rendered(signature: String, texture: Texture2D)
static var _instance: Node
var _cache: Dictionary = {}
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _frames := 0
var render_count := 0

static func service(tree: SceneTree) -> Node:
	if not is_instance_valid(_instance):
		_instance = load("res://scripts/gun_preview.gd").new()
		tree.root.add_child(_instance)
	return _instance

static func signature(key: String, fit: int, notches: int) -> String:
	return "%s:%d:%d" % [key, fit, notches]

## Ten sam montaż, wylot i nacięcia co w Char3D.set_gun; kod fit nie zawiera typu amunicji.
static func compose(key: String, fit: int, notches: int) -> Node3D:
	var info := Char3D.gun_info(key)
	if info.is_empty():
		return null
	return GunModel.build(key, Parts.decode(key, fit), info["muzzle"], notches & 15, notches >> 4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func request(key: String, fit: int, notches: int) -> Texture2D:
	var sig := signature(key, fit, notches)
	if _cache.has(sig):
		var tex: Texture2D = _cache[sig]
		_cache.erase(sig)
		_cache[sig] = tex # kolejność użycia: usuwamy najdawniej używany wpis
		return tex
	if DisplayServer.get_name() == "headless" or _active.get("sig", "") == sig:
		return null
	for job in _queue:
		if job.sig == sig:
			return null
	_queue.append({"sig": sig, "key": key, "fit": fit, "notches": notches})
	set_process(true)
	return null

func _setup() -> void:
	_vp = SubViewport.new()
	_vp.size = FRAME
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.8
	_cam.environment = env
	for spec in [[Vector3(-0.5, -0.7, -0.6), 1.6], [Vector3(0.7, -0.2, -0.4), 0.5]]:
		var light := DirectionalLight3D.new()
		light.basis = Basis.looking_at(spec[0], Vector3.UP)
		light.light_energy = spec[1]
		_vp.add_child(light)

static func bounds(node: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = (n as MeshInstance3D).global_transform * n.get_aabb()
		bb = part if first else bb.merge(part)
		first = false
	return bb

func _next() -> void:
	if _queue.is_empty():
		set_process(false)
		return
	_active = _queue.pop_front()
	if _vp == null:
		_setup()
	_model = compose(_active.key, _active.fit, _active.notches)
	if _model == null:
		rendered.emit(_active.sig, null)
		_active = {}
		return
	_vp.add_child(_model)
	var bb := bounds(_model)
	var center := bb.get_center()
	_cam.position = center + Vector3(0.12, 0.30, 1.0).normalized() * 10.0
	_cam.look_at(center, Vector3.UP)
	# Dopasowanie wszystkich narożników w przestrzeni kamery: tłumik ani bęben nie są przycinane.
	var extent := Vector2.ZERO
	for x in [bb.position.x, bb.end.x]:
		for y in [bb.position.y, bb.end.y]:
			for z in [bb.position.z, bb.end.z]:
				var p := _cam.global_basis.inverse() * (Vector3(x, y, z) - center)
				extent.x = maxf(extent.x, absf(p.x))
				extent.y = maxf(extent.y, absf(p.y))
	_cam.size = maxf(extent.y * 2.0, extent.x * 2.0 / (float(FRAME.x) / FRAME.y)) * 1.12
	_frames = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _process(_delta: float) -> void:
	if _active.is_empty():
		_next()
		return
	_frames += 1
	if _frames < 4:
		return
	var img := _vp.get_texture().get_image()
	var used := img.get_used_rect()
	var tex: Texture2D
	if used.has_area():
		img = img.get_region(used)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		_cache[_active.sig] = tex
		while _cache.size() > CACHE_LIMIT:
			_cache.erase(_cache.keys()[0])
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_model.free()
	_model = null
	render_count += 1
	rendered.emit(_active.sig, tex)
	_active = {}
	_next()
