extends SceneTree
## Stykówka póz snu wrogów (IDLE_PLAN.md I2): dla każdego rodzaju czuwanie i sen obok siebie, z boku (jak w grze, kamera od +Z),
## z prostokątem hitboxa z symulacji (enemy_defs.gd: szerokość `size.x`, wysokość strefy trafień `hurt_h`). Pod komórką: zasięg kości
## w pozie snu względem prostokąta (D1: poza ma się mieścić w hitboxie stojącego).
##   godot --path prototype --script tools/shot_sleep3d.gd -- --out=C:/tmp/sleep.png [--kinds=slepiec,wolek] [--t=4.0] [--px=300] [--seeds=11,14]
## --seeds: ziarna egzemplarzy śpiących (po kolumnie na ziarno; wariant pozy z `IdleLife.pick`, np. drzemiący i węszący Trzosek).
## --wake=0.1,0.25: dodatkowe kolumny — wróg śpi przez --t, potem budzi się (czuwanie) na tyle sekund: wstawanie mieści się w ~0,25 s.
## --heed=-150,-20: śpiący „prawie usłyszał” hałas w tym miejscu względem siebie (px, IDLE_PLAN.md A5) — głowa w stronę źródła.
## --disguise=0,1: dodatkowe kolumny — Mimik w przebraniu (MIMIC_PLAN.md M1–M2: broń w dłoniach) przy danym snopie latarki (0 ciemno, 1 w snopie).
## Okno (render), override.cfg z custom_user_dir jak przy innych zrzutach.
const Enemy3D := preload("res://scripts/enemy3d.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")
const PX := 1.8 / 22.0
const CELL := 5.0                            ## m: komórka (Stalker 4,4 m)
var _out := "C:/tmp/sleep.png"
var _kinds: Array = ["slepiec", "podsluchacz", "stalker", "wolek", "kaplan", "rzeznik", "mimik"]
var _t := 4.0                                ## s pozy przed zrzutem (wagi póz dochodzą do 1)
var _px := 300
var _frames := 0
var _live: Array = []                        ## [wróg, animacja, rodzaj]
var _seeds: Array = [11]
var _wake: Array = []
var _disguise: Array = []
var _heed := Vector3.ZERO
var _vp: SubViewport
var _labels: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--kinds="): _kinds = Array(a.substr(8).split(","))
		elif a.begins_with("--t="): _t = float(a.substr(4))
		elif a.begins_with("--px="): _px = int(a.substr(5))
		elif a.begins_with("--seeds="): _seeds = Array(a.substr(8).split(",")).map(func(x): return int(x))
		elif a.begins_with("--wake="): _wake = Array(a.substr(7).split(",")).map(func(x): return float(x))
		elif a.begins_with("--heed="):
			var hv := a.substr(7).split(",")
			_heed = Vector3(float(hv[0]), float(hv[1]), 1.0)
		elif a.begins_with("--disguise="): _disguise = Array(a.substr(11).split(",")).map(func(x): return float(x))
	var cols := 1 + _seeds.size() + _wake.size() + _disguise.size()  # czuwa, śpi (po ziarnie), budzi się (po czasie), przebrany (po świetle)
	_vp = SubViewport.new()
	_vp.size = Vector2i(_px * cols, _px * _kinds.size())
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
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
	dl.rotation_degrees = Vector3(-40, -20, 0)
	dl.light_energy = 1.4
	_vp.add_child(dl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CELL * _kinds.size()
	_vp.add_child(cam)
	var cy := -CELL * (_kinds.size() - 1) * 0.5 + CELL * 0.4
	cam.look_at_from_position(Vector3(0.0, cy, 40.0), Vector3(0.0, cy, 0.0), Vector3.UP)
	cam.current = true
	for r in _kinds.size():
		var k := String(_kinds[r])
		for c in cols:
			var e: Node3D = (Enemy3D as Script).new()
			_vp.add_child(e)
			var asleep := c > 0 and c <= _seeds.size()
			var waking := c > _seeds.size() and c <= _seeds.size() + _wake.size()
			var disg := c > _seeds.size() + _wake.size()
			var lit: float = float(_disguise[c - 1 - _seeds.size() - _wake.size()]) if disg else -1.0
			e.set("life_seed", int(_seeds[c - 1]) if asleep else 11)
			if not e.setup(k):
				push_error("setup: %s" % k)
				continue
			e.position = Vector3((c - (cols - 1) * 0.5) * CELL, -CELL * r, 0.0)
			if asleep and _heed.z > 0.0:
				e.set("heed", _heed)
			_live.append([e, "sleep" if asleep else "idle", k, float(_wake[c - 1 - _seeds.size()]) if waking else -1.0, lit])
			_box(k, e.position)
			var l := Label.new()
			l.position = Vector2(_px * c + 6, _px * (r + 1) - 40)
			l.add_theme_font_size_override("font_size", 13)
			l.text = "%s — %s" % [k, ("śpi (ziarno %d)%s" % [int(_seeds[c - 1]), " — nasłuch" if _heed.z > 0.0 else ""]) if asleep else (("budzi się +%.2f s" % float(_wake[c - 1 - _seeds.size()])) if waking else (("przebrany, snop %.0f" % lit) if disg else "czuwa"))]
			_vp.add_child(l)
			_labels.append([l, e, asleep])

## Prostokąt hitboxa (od stóp w górę) na płaszczyźnie gry.
func _box(k: String, at: Vector3) -> void:
	var d: Dictionary = EnemyDefs.DEFS.get(k, {})
	if d.is_empty():
		return
	var w := float((d["size"] as Vector2).x) * PX
	var h := maxf(float(d.get("hurt_h", 0.0)), float((d["size"] as Vector2).y)) * PX
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in [Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2, h), Vector2(-w / 2, h), Vector2(-w / 2, 0)]:
		im.surface_add_vertex(Vector3(p.x, p.y, 1.5))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mi.material_override = mat
	mi.position = at
	_vp.add_child(mi)

## Zasięg kości (x od środka, najwyższy punkt) w metrach świata, w przestrzeni wroga.
static func extent(e: Node3D) -> Rect2:
	var sk: Skeleton3D = e.get("_sk")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in sk.get_bone_count():
		var p: Vector3 = e.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(i).origin)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var n := int(_t * 60.0)
	if _frames < 3 + n:
		for m in _live:
			var an := String(m[1])
			if float(m[3]) >= 0.0:                       # budzi się: śpi do chwili (koniec − czas wstawania), potem czuwa
				an = "idle" if _frames >= 3 + n - int(float(m[3]) * 60.0) else "sleep"
			if float(m[4]) >= 0.0:
				(m[0] as Node3D).call("motion_context", {"disguised": true, "lit": float(m[4]), "grounded": true})
			(m[0] as Node3D).call("pose", 1.0 / 60.0, an, false, Color.WHITE)
		return false
	if _frames == 3 + n:
		for l in _labels:
			if not bool(l[2]):
				continue
			var e: Node3D = l[1]
			var r := extent(e)
			var k := String(e.get("kind"))
			var d: Dictionary = EnemyDefs.DEFS.get(k, {})
			var w := float((d.get("size", Vector2.ZERO) as Vector2).x) * PX
			var h := maxf(float(d.get("hurt_h", 0.0)), float((d.get("size", Vector2.ZERO) as Vector2).y)) * PX
			(l[0] as Label).text += "\nkości x %.2f…%.2f (±%.2f), góra %.2f / %.2f m" % [r.position.x, r.end.x, w / 2, r.end.y, h]
			var sk: Skeleton3D = e.get("_sk")
			var ll: Dictionary = e.get("_leg_len")
			if not ll.has("Right"):
				print("[SLEEP] %s: x %.2f…%.2f (±%.2f), góra %.2f / %.2f m" % [k, r.position.x, r.end.x, w / 2, r.end.y, h])
				continue
			var bh: Dictionary = e.get("_b")
			var sc := float(e.get("_scale"))
			var hand := sk.get_bone_global_pose(bh["RightHand"]).origin             # przestrzeń szkieletu, jak cel IK
			var lp: Dictionary = e.get("_last_p")
			print("[SLEEP] %s: x %.2f…%.2f (±%.2f), góra %.2f / %.2f m; skala %.3f, noga %.3f+%.3f, środek x %.2f m = %.2f uda; dłoń %s cel %s" % [k,
					r.position.x, r.end.x, w / 2, r.end.y, h, sc, float(ll["Right"][0]), float(ll["Right"][1]), r.get_center().x,
					r.get_center().x / (float(ll["Right"][0]) * sc), str(hand.snapped(Vector3.ONE * 0.01)), str((lp.get("hR", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01))])
		return false
	if _frames < 3 + n + 4:
		return false
	var img := _vp.get_texture().get_image()
	img.save_png(_out)
	print("saved ", _out)
	quit(0)
	return true
