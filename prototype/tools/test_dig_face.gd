extends SceneTree
## Czoło strefy wydobycia (DIG_ENTRANCE_PLAN.md E1, `dig_zone.gd` `_ring_out` / `_ring_jag` / `_mat_weights`): strefa żwiru 6 × 4 kafle,
## z prawej korytarz (powietrze mapy), wokół skała. Ściana strefy od strony korytarza nie jest płaską płytą: garby tylko w stronę
## powietrza (nic nie cofa się za brzeg — bez szczeliny na tło), przód i płaszczyzna gry na brzegu (styk z przodem mapy, postać przy
## ścianie), bez ruchu w pionie, materiał strefy (żwir) zamiast gruntu mapy, `face_bulge` zgodny z siatką. Ściany od strony skały mapy
## się nie zmieniają. Uruchom: godot --headless --path prototype -s tools/test_dig_face.gd — ma wypisać [DIG-FACE] PASS.

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
	print("[DIG-FACE] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	z.queue_free()
