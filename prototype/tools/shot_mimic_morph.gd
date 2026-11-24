extends SceneTree
## Stykówka przemiany Mimika (MIMIC_PLAN.md M7, enemy3d.gd SPEC `morph`, corpse3d.gd `rise`): wiersz 1 — przebrany stojący od demaskacji
## (klip `morph`: szarpnięcie, skręt głowy, przedramiona, plecak spada, nakładka materiału) w kolejnych chwilach; wiersz 2 — chód przed
## przemianą i `lope` po niej w kilku fazach kroku; wiersz 3 — Mimik-zwłoki wstaje „wstecz” (klip upadku od końca) i model wroga, który
## przejmuje go po RISE_S; wiersz 4 — stojący po przemianie w strojach zwłok (patrol, technik, górnik). Pod komórką czas od demaskacji.
##   godot --path prototype --script tools/shot_mimic_morph.gd -- --out=C:/tmp/mimic_morph.png [--px=300] [--pitch=8] [--night]
## Okno (render), override.cfg z custom_user_dir jak przy innych zrzutach.
const Enemy3D := preload("res://scripts/enemy3d.gd")
const Corpse3D := preload("res://scripts/corpse3d.gd")
const MORPH_S := 0.9                          ## jak enemy_mimic.gd MORPH_S (skrypt symulacji wymaga autoloadów — w narzędziu bez nich)
const RISE_S := 0.75                          ## jak enemy_mimic.gd RISE_S
const DT := 1.0 / 60.0
const CELL := 2.2
const ROW := 2.6
const STAND := [-0.2, 0.08, 0.18, 0.3, 0.45, 0.6, 0.75, 0.88, 1.05, 1.6]
const WALK := [[-1.0, 0.0], [-1.0, 0.25], [-1.0, 0.5], [3.0, 0.0], [3.0, 0.25], [3.0, 0.5], [3.0, 0.75]]
const RISE := [0.0, 0.12, 0.25, 0.37, 0.5, 0.62, 0.75, 0.87, 1.0]
var _out := "C:/tmp/mimic_morph.png"
var _px := 300
var _pitch := 8.0
var _night := false
var _frames := -1
var _vp: SubViewport

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--px="): _px = int(a.substr(5))
		elif a.begins_with("--pitch="): _pitch = float(a.substr(8))
		elif a == "--night": _night = true
	var cols := maxi(STAND.size(), maxi(WALK.size(), RISE.size() + 1))
	var rows := 4
	_vp = SubViewport.new()
	_vp.size = Vector2i(_px * cols, int(float(_px) * ROW / CELL) * rows)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.2, 0.19) if not _night else Color(0.03, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66) if not _night else Color(0.1, 0.12, 0.16)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-40, -25, 0)
	dl.light_energy = 1.3 if not _night else 0.1
	dl.shadow_enabled = true
	_vp.add_child(dl)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.3, 0.27)
	for r in rows:
		var floor_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(CELL * cols + 4.0, 0.02, 1.6)
		floor_mi.mesh = bm
		floor_mi.material_override = fm
		floor_mi.position = Vector3(0.0, -ROW * r - 0.01, -0.3)
		_vp.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ROW * rows
	_vp.add_child(cam)
	var target := Vector3(0.0, -ROW * (rows - 1) * 0.5 + 0.9, 0.0)
	cam.look_at_from_position(target + Vector3(0.0, sin(deg_to_rad(_pitch)), cos(deg_to_rad(_pitch))) * 40.0, target, Vector3.UP)
	cam.current = true
	_fill.call_deferred(-(cols - 1) * 0.5 * CELL)

## Modele pozowane dopiero w drzewie (pozycje świata, grunt pod stopami).
func _fill(x0: float) -> void:
	for c in STAND.size():
		var e := _enemy(Vector3(x0 + c * CELL, 0.0, 0.0), "")
		_play_morph(e, float(STAND[c]))
		_label(c, 0, "t %.2f s" % float(STAND[c]))
	for c in WALK.size():
		var e := _enemy(Vector3(x0 + c * CELL, -ROW, 0.0), "")
		var since := float(WALK[c][0])
		var ph := float(WALK[c][1])
		_walk(e, since, ph)
		_label(c, 1, "%s · faza %.2f" % ["przed" if since < 0.0 else "lope", ph])
	for c in RISE.size():
		var u := float(RISE[c])
		var k: Node3D = (Corpse3D as Script).new()
		_vp.add_child(k)
		k.position = Vector3(x0 + c * CELL, -ROW * 2, 0.0)
		k.call("build", "patrol", "side", 11, 1.0, true)
		k.set_process(false)
		k.call("rise", u, u * RISE_S)
		_label(c, 2, "wstaje %.2f" % u)
	var after := _enemy(Vector3(x0 + RISE.size() * CELL, -ROW * 2, 0.0), "patrol")
	_play_morph(after, RISE_S + 0.05)
	_label(RISE.size(), 2, "model wroga %.2f s" % (RISE_S + 0.05))
	var outfits: Array = Corpse3D.OUTFITS.keys()
	for c in outfits.size():
		var e := _enemy(Vector3(x0 + c * CELL, -ROW * 3, 0.0), String(outfits[c]))
		_play_morph(e, 2.0)
		_label(c, 3, "%s po przemianie" % outfits[c])
	for c in outfits.size():
		var e := _enemy(Vector3(x0 + (c + 4) * CELL, -ROW * 3, 0.0), String(outfits[c]))
		_play_morph(e, -0.2)
		_label(c + 4, 3, "%s przebrany" % outfits[c])

func _enemy(at: Vector3, outfit: String) -> Node3D:
	var e: Node3D = (Enemy3D as Script).new()
	e.set("life_seed", 11)
	if outfit != "":
		e.set("model_path", String(Corpse3D.OUTFITS[outfit]))
		e.set("fit_body_h", Corpse3D.BODY_H)
	_vp.add_child(e)
	e.position = at
	if not e.call("setup", "mimik"):
		push_error("setup mimik %s" % outfit)
	return e

## Przebrany stoi, potem demaskacja i przemiana do `until` s (zapowiedź `morph` jak z symulacji, kontakt na końcu).
func _play_morph(e: Node3D, until: float) -> void:
	var t := -0.6
	var hit := false
	while t < until:
		var since := t if t >= 0.0 else -1.0
		var winding := since >= 0.0 and since < MORPH_S
		if since >= MORPH_S and not hit:
			hit = true
			e.call("trigger", "attack", "morph")
		e.call("motion_context", {"disguised": since < 0.0, "lit": 0.0, "grounded": true, "since_reveal": since, "winding": winding,
			"windup_remaining": MORPH_S - since, "windup_duration": MORPH_S, "motion_action": "morph"})
		e.call("pose", DT, "windup" if winding else "idle", false, Color.WHITE)
		t += DT

## Chód: `since` < 0 — przebrany, inaczej po przemianie; `ph` — ułamek cyklu kroku.
func _walk(e: Node3D, since: float, ph: float) -> void:
	var steps := int((1.0 + ph * 0.8) / DT)
	for i in steps:
		e.call("motion_context", {"disguised": since < 0.0, "lit": 0.0, "grounded": true, "since_reveal": since if since < 0.0 else since + i * DT})
		e.call("pose", DT, "walk", false, Color.WHITE, 0.0, 1, true, 0.0, 0, false, 95.0, 95.0 * DT)

func _label(c: int, r: int, text: String) -> void:
	var l := Label.new()
	l.position = Vector2(_px * c + 6, int(float(_px) * ROW / CELL) * (r + 1) - 22)
	l.add_theme_font_size_override("font_size", 13)
	l.text = text
	_vp.add_child(l)

func _process(_delta: float) -> bool:
	if _frames < 0:
		_frames = 0 if _vp != null and _vp.get_child_count() > 20 else -1
		return false
	_frames += 1
	if _frames < 8:
		return false
	_vp.get_texture().get_image().save_png(_out)
	print("saved ", _out)
	quit(0)
	return true
