extends SceneTree
## Stykówka przeglądu postaci (CHARACTER_QUALITY_PLAN.md Q0): każdy wygląd w wierszu — pełna postać tył / bok / przód
## i głowa przód / 3/4 / bok, w pozie spoczynkowej modelu, przy stałym świetle.
##   godot --path prototype --script tools/shot_char_review.gd -- --out=C:/tmp/review.png [--bare] [--charset=mpfb] [--looks=male_scav,female_scav]
## --bare chowa nakrycia głowy (hełm, kaptur, maska) — widać włosy i czaszkę; --charset: katalog w art/char3d/ (np. zestaw próbny z generatora).
## Okno (renderuje), bez trybu gry i bez zapisu profilu.
const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_hazmat", "male_medic", "female_medic"]
const HEADGEAR := ["helmet", "m1951", "hood", "gas_mask", "kz45"]
const CELL := Vector2i(300, 420)
## Ujęcia: [obrót modelu wokół pionu (°; model patrzy w +X, kamera w −Z), cała postać?]
const SHOTS := [[90.0, true], [0.0, true], [-90.0, true], [-90.0, false], [-50.0, false], [0.0, false]]
var _out := "/tmp/char_review.png"
var _bare := false
var _charset := "mpfb"
var _looks: Array = LOOKS.duplicate()
var _vp: SubViewport
var _cam: Camera3D
var _sheet: Image
var _i := 0
var _frames := 0
var _inst: Node3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--bare":
			_bare = true
		elif a.begins_with("--charset="):
			_charset = a.substr(10)
		elif a.begins_with("--looks="):
			_looks = Array(a.substr(8).split(","))
	_vp = SubViewport.new()
	_vp.size = CELL
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.22, 0.24, 0.25)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 35, 0)
	key.light_energy = 1.4
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -60, 0)
	fill.light_energy = 0.4
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_cam.current = true
	_sheet = Image.create(CELL.x * SHOTS.size(), CELL.y * _looks.size(), false, Image.FORMAT_RGBA8)
	_spawn()

## Model do bieżącego ujęcia: obrót, kadr (cała postać albo głowa), nakrycia głowy schowane przy --bare.
func _spawn() -> void:
	if _inst:
		_inst.free()
	var look: String = _looks[_i / SHOTS.size()]
	var shot: Array = SHOTS[_i % SHOTS.size()]
	var path := "res://art/char3d/%s/%s.glb" % [_charset, look]
	if not ResourceLoader.exists(path):
		path = "res://art/char3d/%s.glb" % look
	_inst = (load(path) as PackedScene).instantiate()
	_vp.add_child(_inst)
	_inst.rotation_degrees.y = float(shot[0])
	var sk: Skeleton3D = _inst.find_child("Skeleton3D", true, false)
	var head := sk.get_bone_global_rest(sk.find_bone("mixamorig_Head")).origin.y if sk else 1.6
	if bool(shot[1]):
		_cam.size = 2.1
		_cam.position = Vector3(0, 0.98, 10)
	else:
		_cam.size = 0.44
		_cam.position = Vector3(0, head + 0.08, 10)
	if _bare:
		for mi in _inst.find_children("*", "MeshInstance3D", true, false):
			for h in HEADGEAR:
				if String(mi.name).to_lower().contains(h):
					(mi as MeshInstance3D).visible = false

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	_frames = 0
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((_i % SHOTS.size()) * CELL.x, (_i / SHOTS.size()) * CELL.y))
	_i += 1
	if _i >= _looks.size() * SHOTS.size():
		_sheet.save_png(_out)
		print("saved ", _out)
		return true
	_spawn()
	return false
