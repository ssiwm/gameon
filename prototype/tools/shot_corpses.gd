extends SceneTree
## Stykówka zwłok (MIMIC_PLAN.md M3, corpse3d.gd): wiersz na strój, kolumna na ułożenie (każde z flip ±1), widok z boku jak kamera gry
## i z góry pod kątem (--pitch); pod komórką wariant i najniższy punkt skóry. Ostatnia kolumna: to samo ciało przeszukane (M4).
##   godot --path prototype --script tools/shot_corpses.gd -- --out=C:/tmp/corpses.png [--px=360] [--pitch=12]
## Okno (render), override.cfg z custom_user_dir jak przy innych zrzutach.
const Corpse3D := preload("res://scripts/corpse3d.gd")
const CELL := 3.0
var _out := "C:/tmp/corpses.png"
var _px := 360
var _pitch := 12.0
var _frames := 0
var _vp: SubViewport

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--px="): _px = int(a.substr(5))
		elif a.begins_with("--pitch="): _pitch = float(a.substr(8))
	var outfits: Array = Corpse3D.OUTFITS.keys()
	var cols: Array = []
	for p in Corpse3D.POSES:
		cols.append([p, 1.0, false])
		cols.append([p, -1.0, false])
	cols.append([Corpse3D.POSES[0], 1.0, true])
	_vp = SubViewport.new()
	_vp.size = Vector2i(_px * cols.size(), int(float(_px) * 1.3 / CELL) * outfits.size())     # ta sama skala w poziomie i pionie
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.2, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-50, -20, 0)
	dl.light_energy = 1.4
	dl.shadow_enabled = true
	_vp.add_child(dl)
	const ROW := 1.3                                     # m między wierszami (pion)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.3, 0.27)
	for r in outfits.size():
		var floor_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(CELL * cols.size() + 4.0, 0.02, 1.6)
		floor_mi.mesh = bm
		floor_mi.material_override = fm
		floor_mi.position = Vector3(0.0, -ROW * r - 0.01, -0.3)
		_vp.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ROW * outfits.size()
	_vp.add_child(cam)
	var target := Vector3(0.0, -ROW * (outfits.size() - 1) * 0.5 + 0.25, 0.0)
	cam.look_at_from_position(target + Vector3(0.0, sin(deg_to_rad(_pitch)), cos(deg_to_rad(_pitch))) * 40.0, target, Vector3.UP)
	cam.current = true
	for r in outfits.size():
		for c in cols.size():
			var cd: Array = cols[c]
			var e: Node3D = (Corpse3D as Script).new()
			_vp.add_child(e)
			e.position = Vector3((c - (cols.size() - 1) * 0.5) * CELL, -ROW * r, 0.0)
			if not e.call("build", String(outfits[r]), String(cd[0]), 11 + c, float(cd[1])):
				push_error("build %s" % outfits[r])
				continue
			if bool(cd[2]):
				e.call("set_searched", true)
			var l := Label.new()
			l.position = Vector2(_px * c + 6, int(float(_px) * 1.3 / CELL) * (r + 1) - 22)
			l.add_theme_font_size_override("font_size", 13)
			l.text = "%s · %s%s%s" % [outfits[r], cd[0], " ⇄" if float(cd[1]) < 0.0 else "", " · przeszukane" if bool(cd[2]) else ""]
			_vp.add_child(l)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	_vp.get_texture().get_image().save_png(_out)
	print("saved ", _out)
	quit(0)
	return true
