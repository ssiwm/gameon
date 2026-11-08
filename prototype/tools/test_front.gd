extends SceneTree
## Test pierwszego planu przed płaszczyzną gry (`scripts/front3d.gd`, `FOREGROUND_PLAN.md`) na wszystkich mapach z scripts/maps:
## (1) dane `FRONT` / `FRONT_SKIP`: znany zestaw, kolumny i wiersze w mapie, c0 < c1, r0 < r1,
## (2) rozmieszczenie: z w Z_RANGE, element w zakresie wpisu z zapasem, duże elementy co najmniej BIG_SPACING.x od siebie także
##     między wpisami, których pasy mieszczą się razem w kadrze (najwyżej jeden duży element w kadrze NORMAL), mały element
##     co najmniej SMALL_MIN od dużego, `FRONT_SKIP` pusty, na LOW bez małych, ten sam układ przy każdym wywołaniu,
## (3) bryły: tylko warstwa `LAYER_FRONT` (rozłączna z warstwami świata, lasu, dna lasu i wnęk), bez cienia, bez kolizji,
##     materiał bez oświetlenia sceny (`unshaded`), pas przycięcia w parametrze instancji; OFF chowa całość,
## (4) wygaszanie: `Front3D.fade` (ta sama funkcja co w shaderze) daje MIN_A w punkcie, pełne krycie od r × FADE_OUT, rośnie z odległością.
## godot --headless --path prototype -s tools/test_front.gd       → ma wypisać PASS
const Level3D := preload("res://scripts/level3d.gd")
const Niches3D := preload("res://scripts/niches3d.gd")
const Front3D := preload("res://scripts/front3d.gd")
const LAYER_WORLD := 1                    ## view3d.gd LAYER_WORLD
const LAYER_ACTORS := 2                   ## view3d.gd LAYER_ACTORS
const FRAME_H_NORMAL := 180.0 * 1.8 / 22.0   ## m: wysokość kadru NORMAL na płaszczyźnie gry (Settings.CAM_ZOOM 2.0 → 180 px)
var _frames := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL  " + msg)
		_fail += 1

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var dir := DirAccess.open("res://scripts/maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	var total := 0
	for f in names:
		var consts := (load("res://scripts/maps/" + f) as GDScript).get_script_constant_map()
		var front: Array = consts.get("FRONT", [])
		if front.is_empty():
			continue
		total += front.size()
		_check_map(f.get_basename(), consts.get("MAP", []), front, consts.get("FRONT_SKIP", []))
	_check(total > 0, "żadna mapa nie ma pierwszego planu (pilot na z1_m2)")
	_check_skip()
	_check_layers()
	_check_fade()
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true


func _check_map(map_id: String, rows: Array, front: Array, skip: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	for e: Dictionary in front:
		var tag := "%s %s" % [map_id, e]
		_check(Front3D.SETS.has(String(e.get("set", ""))), tag + ": nieznany zestaw")
		_check(int(e["c0"]) >= 0 and int(e["c1"]) < cols and int(e["c0"]) < int(e["c1"]), tag + ": kolumny poza mapą albo c0 ≥ c1")
		_check(int(e["r0"]) >= 0 and int(e["r1"]) < nrows and int(e["r0"]) < int(e["r1"]), tag + ": wiersze poza mapą albo r0 ≥ r1")
	for s in skip:
		_check(s is Array and (s as Array).size() == 2 and int(s[0]) <= int(s[1]), "%s FRONT_SKIP %s: oczekiwane [c0, c1]" % [map_id, s])
	var items := Front3D.layout(front, skip)
	_check(not items.is_empty(), map_id + ": wpisy FRONT bez żadnego elementu")
	_check(str(items) == str(Front3D.layout(front, skip)), map_id + ": układ różni się między wywołaniami (ziarno)")
	for it: Dictionary in items:
		var clip: Vector4 = it["clip"]
		var x: float = it["x"]
		var z: float = it["z"]
		_check(z >= Front3D.Z_RANGE.x and z <= Front3D.Z_RANGE.y, "%s %s x %.1f: z %.2f poza Z_RANGE" % [map_id, it["kind"], x, z])
		_check(x >= clip.x + Front3D.MARGIN - 0.01 and x <= clip.y - Front3D.MARGIN + 0.01, "%s %s x %.1f: poza zakresem wpisu" % [map_id, it["kind"], x])
		_check(bool(it["big"]) == (String(it["kind"]) in Front3D.BIG_KINDS), "%s %s: zła klasa dużego elementu" % [map_id, it["kind"]])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var ca: Vector4 = a["clip"]
			var cb: Vector4 = b["clip"]
			var gap_y := maxf(0.0, maxf(ca.z, cb.z) - minf(ca.w, cb.w))          # odstęp pionowy pasów
			if gap_y >= FRAME_H_NORMAL:
				continue
			var dx := absf(float(a["x"]) - float(b["x"]))
			if bool(a["big"]) and bool(b["big"]):
				_check(dx >= Front3D.BIG_SPACING.x - 0.01, "%s: dwa duże elementy %.1f m od siebie (x %.1f i %.1f), dwa w jednym kadrze" % [map_id, dx, a["x"], b["x"]])
			elif bool(a["big"]) != bool(b["big"]):
				_check(dx >= Front3D.SMALL_MIN - 0.01, "%s: mały element %.1f m od dużego (x %.1f i %.1f)" % [map_id, dx, a["x"], b["x"]])
	for it: Dictionary in Front3D.layout(front, skip, true):
		_check(bool(it["big"]), "%s: na LOW został mały element %s x %.1f" % [map_id, it["kind"], it["x"]])


## FRONT_SKIP: zakres bez pierwszego planu nie dostaje żadnego elementu (z zapasem MARGIN).
func _check_skip() -> void:
	var front := [{"set": "station", "c0": 0, "c1": 199, "r0": 0, "r1": 8}]
	var skip := [[60, 120]]
	var all := Front3D.layout(front, [])
	var left := Front3D.layout(front, skip)
	_check(left.size() < all.size(), "FRONT_SKIP nic nie zabrał")
	for it: Dictionary in left:
		var x: float = it["x"]
		_check(x < 60.0 * Level3D.T - Front3D.MARGIN or x > 121.0 * Level3D.T + Front3D.MARGIN, "FRONT_SKIP: element %s x %.1f w zakresie pominiętym" % [it["kind"], x])


func _check_layers() -> void:
	var lf := Front3D.LAYER_FRONT
	for other in [LAYER_WORLD, LAYER_ACTORS, Level3D.LAYER_FOREST, Level3D.LAYER_FAR, Niches3D.LAYER_NICHE]:
		_check(lf & int(other) == 0, "LAYER_FRONT nachodzi na warstwę %d" % other)
	var root := Node3D.new()
	get_root().add_child(root)
	var front := [{"set": "station", "c0": 0, "c1": 120, "r0": 2, "r1": 10}, {"set": "tunnel", "c0": 0, "c1": 120, "r0": 30, "r1": 37}]
	var n := Front3D.build(root, front, [], false)
	var fr := root.get_node_or_null("Front")
	_check(fr != null and n > 0, "build nie zbudował węzła Front")
	if fr == null:
		return
	var kinds := {}
	for c in fr.get_children():
		_check(c is MeshInstance3D, "Front: dziecko %s nie jest MeshInstance3D" % c.name)
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		kinds[String(mi.name).get_slice("_", 0)] = true
		_check(mi.layers == lf, "%s: warstwy %d zamiast LAYER_FRONT" % [mi.name, mi.layers])
		_check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: rzuca cień" % mi.name)
		_check(mi.get_child_count() == 0, "%s: ma dzieci (kolizja?)" % mi.name)
		var mat := mi.material_override as ShaderMaterial
		_check(mat != null and "unshaded" in mat.shader.code, "%s: materiał nie jest unshaded (oświetlałyby go lampy i latarka)" % mi.name)
		var clip: Variant = mi.get_instance_shader_parameter("clip")
		_check(clip is Vector4 and (clip as Vector4).y > (clip as Vector4).x and (clip as Vector4).w > (clip as Vector4).z, "%s: brak pasa przycięcia" % mi.name)
	for k in ["pipe", "pipes2", "cables", "chain"]:
		_check(kinds.has(k), "rodzaj %s nie powstał na długim zakresie" % k)
	Front3D.apply_settings(2, false)
	_check(not (fr as Node3D).visible, "OFF nie chowa pierwszego planu")
	Front3D.apply_settings(0, false)
	_check((fr as Node3D).visible, "ON nie pokazuje pierwszego planu")
	_check(Front3D.build(root, [], [], false) == 0, "pusty FRONT coś zbudował")
	root.queue_free()


func _check_fade() -> void:
	var r := 1.8
	_check(is_equal_approx(Front3D.fade(0.0, r), Front3D.MIN_A), "fade w punkcie ≠ MIN_A")
	_check(Front3D.fade(0.0, r) <= 0.15 + 0.001, "krycie w punkcie > 0,15 (zasada 1)")
	_check(is_equal_approx(Front3D.fade(r * Front3D.FADE_OUT, r), 1.0), "fade na r × FADE_OUT ≠ 1")
	var prev := -1.0
	for i in 40:
		var a := Front3D.fade(float(i) * 0.1, r)
		_check(a >= prev - 0.0001, "fade maleje z odległością (d %.1f)" % (float(i) * 0.1))
		prev = a
