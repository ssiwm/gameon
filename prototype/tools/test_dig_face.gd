extends SceneTree
## Czoło strefy wydobycia (DIG_ENTRANCE_PLAN.md E1, `dig_zone.gd` `_ring_out` / `_ring_jag` / `_mat_weights`): strefa żwiru 6 × 4 kafle,
## z prawej korytarz (powietrze mapy), wokół skała. Ściana strefy od strony korytarza nie jest płaską płytą: garby tylko w stronę
## powietrza (nic nie cofa się za brzeg — bez szczeliny na tło), przód i płaszczyzna gry na brzegu (styk z przodem mapy, postać przy
## ścianie), bez ruchu w pionie, materiał strefy (żwir) zamiast gruntu mapy, `face_bulge` zgodny z siatką. Ściany od strony skały mapy
## się nie zmieniają. E2 (`dig_entrance3d.gd`): osypisko u stopy czoła (na podłodze, wierzch przy czole, przydeptana ścieżka przy płaszczyźnie
## gry, niżej przed nią, zero przy przodzie, normalne w górę, bryłki poza czołem) i odrzwia (tylko przy obudowie; stojak na podłodze przy
## czole, nie w garbie; stropnica pod stropem korytarza). Uruchom: godot --headless --path prototype -s tools/test_dig_face.gd — ma wypisać [DIG-FACE] PASS.

var DigZone: GDScript                  ## load w _run: dig_zone.gd potrzebuje autoloadów (Scrap)
const Level3D := preload("res://scripts/level3d.gd")

const C0 := 10
const R0 := 10
const C1 := 15
const R1 := 13

var _fails := 0
var _frames := 0

func _check(label: String, ok: bool) -> void:
	print("[DIG-FACE] %s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:                                              # autoloady gotowe
		_run()
	return _frames > 2

func _run() -> void:
	DigZone = load("res://scripts/dig_zone.gd")
	var z: Node2D = DigZone.new()
	root.add_child(z)
	# mapa: korytarz w wierszach strefy na prawo od niej (kolumny > C1), reszta to skała
	var map_solid := func(c: int, r: int) -> bool:
		return not (c > C1 and c < C1 + 12 and r >= R0 and r <= R1)
	z.setup([C0, R0, C1, R1, "gravel", 1201], map_solid, func(_c: int, _r: int) -> bool: return true)
	var px := Level3D.PX
	var front := Level3D.DEPTH_FRONT
	var back := -Level3D.DEPTH_BACK
	var wall := float((C1 + 1) * 16) * px                         # m: prawy brzeg strefy
	var y_top := -float(R0 * 16) * px
	var y_bot := -float((R1 + 1) * 16) * px
	var face := 0
	var inward := 0
	var front_off := 0.0
	var plane_off := 0.0
	var max_out := 0.0
	var outside_y := 0
	var mat_bad := 0
	var rmin := 9.0
	var rmax := 0.0
	var t0 := Time.get_ticks_usec()
	var arrs: Array = []
	for ci in int(z.chunk_count()):
		var m: ArrayMesh = z.chunk_mesh(ci, px, front, back)
		if m.get_surface_count() > 0:
			arrs.append(m.surface_get_arrays(0))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	for a: Array in arrs:
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		for k in vs.size():
			var v := vs[k]
			if absf(v.x - wall) > 0.6 or absf(ns[k].z) > 0.9 or ns[k].x < 0.3:
				continue                                          # tylko ściana z normalną w stronę korytarza (+x)
			face += 1
			var d := v.x - wall
			if d < -0.002:
				inward += 1
			if v.z >= front - 0.001:
				front_off = maxf(front_off, absf(d))
			elif absf(v.z) < 0.2:
				plane_off = maxf(plane_off, absf(d))
			else:
				max_out = maxf(max_out, d)
				if cs[k].a < 0.99 or uv2[k].x < 0.99:
					mat_bad += 1
				rmin = minf(rmin, cs[k].r)
				rmax = maxf(rmax, cs[k].r)
			if v.y > y_top + 0.002 or v.y < y_bot - 0.002:
				outside_y += 1
	print("[DIG-FACE] wierzchołków czoła %d, największy garb %.2f m, przód %.3f m, płaszczyzna gry %.3f m, jasność %.2f–%.2f, siatka %.2f ms"
		% [face, max_out, front_off, plane_off, rmin, rmax, ms])
	_check("czoło od strony korytarza ma wierzchołki", face > 40)
	_check("czoło nie jest płaskie (garb > 0,15 m)", max_out > 0.15)
	_check("garby nie większe niż RING_JAG", max_out <= float(DigZone.get_script_constant_map()["RING_JAG"]) + 0.001)
	_check("nic nie cofa się za brzeg strefy (bez szczeliny na tło)", inward == 0)
	_check("przód na brzegu (styk z przodem mapy)", front_off < 0.002)
	_check("płaszczyzna gry na brzegu (postać przy ścianie nie wchodzi w bryłę)", plane_off < 0.01)
	_check("bez ruchu w pionie poza wiersze strefy", outside_y == 0)
	_check("czoło w materiale strefy (żwir, alfa 1)", mat_bad == 0)
	_check("zagłębienia czoła ciemniejsze od garbów (rozrzut jasności > 0,2)", rmax - rmin > 0.2)
	var fb_plane: float = z.face_bulge(Vector2(wall / px, float(R1 * 16)), 0.0, px, front, back)
	var fb_max := 0.0
	for zz in [-0.9, -1.2, -1.6, 0.8]:
		for yy in [R0 * 16 + 8, R0 * 16 + 30, R1 * 16]:
			fb_max = maxf(fb_max, float(z.face_bulge(Vector2(wall / px, float(yy)), zz, px, front, back)))
	_check("face_bulge: 0 przy płaszczyźnie gry, garb w głębi (%.2f m)" % fb_max, fb_plane == 0.0 and fb_max > 0.05)
	var per := ms / maxf(float(arrs.size()), 1.0)
	_check("siatka fragmentu < 4 ms jak w --digtest (%.2f ms na %d fragm.)" % [per, arrs.size()], per < 4.0)
	_talus(z, px, front, back, wall, y_bot)
	print("[DIG-FACE] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	z.queue_free()

func _talus(z: Node2D, px: float, front: float, back: float, wall: float, floor_m: float) -> void:
	var DE: GDScript = load("res://scripts/dig_entrance3d.gd")
	var e: Dictionary = z.entrance()
	_check("wejście z boku (korytarz z prawej, dir −1)", not e.is_empty() and int(e["dir"]) == -1)
	var bulge := func(y_up: float, zz: float) -> float:
		return float(z.face_bulge(Vector2(float(e["wall_x"]), float(e["floor_y"]) - y_up / px), zz, px, front, back))
	var t: Dictionary = DE.talus(z, px, front, back, bulge)
	_check("osypisko zbudowane, materiał strefy (żwir)", not t.is_empty() and String(t.get("mat", "")) == "gravel")
	if t.is_empty():
		return
	var a: Array = (t["mesh"] as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var below := 0
	var path_h := 0.0
	var back_h := 0.0
	var front_h := 0.0
	var reach := 0.0
	var down := 0
	var gap := 0
	var mat_bad := 0
	var foot := {}
	for k in vs.size():
		var v := vs[k]
		var hy := v.y - floor_m
		if hy < -DE.TALUS_SINK - 0.001:
			below += 1
		if absf(v.z) < 0.3:
			path_h = maxf(path_h, hy)
		elif v.z < -0.85:
			back_h = maxf(back_h, hy)
		if v.z > front - 0.05:
			front_h = maxf(front_h, hy)
		reach = maxf(reach, v.x - wall)
		if ns[k].y < 0.2:
			down += 1
		if cs[k].a < 0.99 or uv2[k].x < 0.99:
			mat_bad += 1
		var zk := roundi(v.z * 100.0)
		if not foot.has(zk) or v.x < (foot[zk] as Vector3).x:
			foot[zk] = v                                              # wierzchołek przy czole w tym plastrze
	for v: Vector3 in foot.values():
		var hy := v.y - floor_m
		if hy > 0.02 and v.x - wall > minf(float(bulge.call(0.05, v.z)), float(bulge.call(hy, v.z))) + 0.001:
			gap += 1                                                  # wierzch osypiska przed czołem — szczelina między nimi
	print("[DIG-FACE] osypisko: %d wierzchołków, ścieżka %.2f m, z tyłu %.2f m, przy przodzie %.3f m, zasięg %.2f m, bryłek %d"
		% [vs.size(), path_h, back_h, front_h, reach, (t["rocks"] as Array).size()])
	_check("osypisko na podłodze (nic pod nią poza brzegiem)", below == 0)
	_check("osypisko przy czole bez szczeliny (wierzch w garbie)", gap == 0)
	_check("ścieżka przy płaszczyźnie gry przydeptana (< 0,1 m)", path_h < 0.1)
	_check("osypisko z tyłu ma wysokość stożka żwiru (> 0,35 m)", back_h > 0.35)
	_check("przy przodzie mapy schodzi do zera", front_h < 0.03)
	_check("zasięg od czoła 0,4–1,3 m", reach > 0.4 and reach < 1.3)
	_check("normalne osypiska w górę", down == 0)
	_check("osypisko w materiale strefy (alfa 1, żwir)", mat_bad == 0)
	var rk_bad := 0
	for r: Dictionary in t["rocks"]:
		var p: Vector3 = (r["t"] as Transform3D).origin
		if p.y < floor_m - 0.01 or p.x < wall or p.z > front - 0.05:
			rk_bad += 1
	_check("bryłki osypiska na podłodze, przed czołem, nie przy przodzie", (t["rocks"] as Array).size() > 10 and rk_bad == 0)
	var stray := 0
	for r: Dictionary in t["rocks"]:
		if r.get("stray", false):
			var p: Vector3 = (r["t"] as Transform3D).origin
			if p.x - wall > 0.5 and absf(p.y - floor_m) < 0.15:   # za stopą osypiska (w tym plastrze), na podłodze
				stray += 1
	_check("dwie bryły na podłodze za osypiskiem (> 0,5 m od czoła)", stray == 2)
	_pick(z, px, wall, floor_m, bulge)
	_check("bez obudowy korytarza nie ma odrzwi", (DE.frame(z, px, back, bulge, func(_c: int, _r: int) -> bool: return false) as Array).is_empty())
	var fr: Array = DE.frame(z, px, back, bulge, func(_c: int, _r: int) -> bool: return true)
	_check("przy obudowie odrzwia: stojak, stropnica, klin", fr.size() == 3)
	if fr.size() < 3:
		return
	var post: Dictionary = fr[0]
	var cap: Dictionary = fr[1]
	var ps: Vector3 = post["size"]
	var pp: Vector3 = post["pos"]
	var reach_post := 0.0
	for k in 11:
		reach_post = maxf(reach_post, float(bulge.call(ps.y * float(k) / 10.0, pp.z)))
	var ceil_m := -float(R0 * 16) * px
	var cs2: Vector3 = cap["size"]
	var cp: Vector3 = cap["pos"]
	_check("stojak na podłodze", absf(pp.y - ps.y * 0.5 - floor_m) < 0.01)
	_check("stojak przy czole, nie w garbie", pp.x - ps.x * 0.5 > wall + reach_post and pp.x - ps.x * 0.5 < wall + reach_post + 0.1)
	_check("stropnica pod stropem korytarza", absf(cp.y + cs2.y * 0.5 - ceil_m) < 0.01)
	_check("stropnica od tylnej ściany do przodu obudowy, przed płaszczyzną gry", cp.z - cs2.z * 0.5 < back + 0.2 and cp.z + cs2.z * 0.5 > 0.3)

func _pick(z: Node2D, px: float, wall: float, floor_m: float, bulge: Callable) -> void:
	var DE: GDScript = load("res://scripts/dig_entrance3d.gd")
	var V3: GDScript = load("res://scripts/view3d.gd")
	var ps := load(V3.DIG_SIGN_PICK) as PackedScene
	_check("model kilofa znaku się wczytuje", ps != null)
	if ps == null:
		return
	var model := ps.instantiate() as Node3D
	var parts: Dictionary = DE.pick_parts(model)
	_check("kilof: siatka głowicy, czubek obucha i koniec trzonka", not parts.is_empty())
	if parts.is_empty():
		model.free()
		return
	var xf: Transform3D = DE.pick_xf(z, px, bulge, parts, float(V3.DIG_SIGN_PICK_K))
	var tip := xf * (parts["tip"] as Vector3)
	var head: AABB = parts["head"]
	var back_tip := xf * Vector3(head.position.x, head.position.y, head.get_center().z)
	var axis := xf * Vector3((parts["tip"] as Vector3).x, head.get_center().y, head.get_center().z)
	var end := xf * (parts["end"] as Vector3)
	var tip_h := tip.y - floor_m
	var embed := wall + float(bulge.call(tip_h, tip.z)) - tip.x
	var inside := 0
	for k in 18:
		var p := axis.lerp(end, 0.15 + 0.85 * float(k) / 17.0)
		if p.x - wall <= float(bulge.call(p.y - floor_m, p.z)) + 0.02:
			inside += 1
	print("[DIG-FACE] kilof: czubek %.2f m nad podłogą, z %.2f, w czole %.3f m; koniec trzonka %.2f m nad podłogą, %.2f m od czoła; drugi koniec obucha %.2f m od czoła"
		% [tip_h, tip.z, embed, end.y - floor_m, end.x - wall, back_tip.x - wall])
	_check("czubek obucha wbity 6–10 cm w garb czoła", embed > 0.06 and embed < 0.1)
	_check("czubek na wysokości piersi (1,0–1,2 m), przed płaszczyzną gry (z 0,6–0,8)", tip_h > 1.0 and tip_h < 1.2 and tip.z > 0.6 and tip.z < 0.8)
	_check("trzonek w dół i od ściany, nad podłogą", end.y < axis.y - 0.3 and end.x - wall > 0.3 and end.y - floor_m > 0.15)
	_check("trzonek poza czołem", inside == 0)
	_check("drugi koniec obucha poza czołem", back_tip.x - wall > float(bulge.call(back_tip.y - floor_m, back_tip.z)) + 0.05)
	model.free()
