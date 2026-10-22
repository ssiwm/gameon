extends Node3D
## Strzelnica FPP — obraz tarczy papierowej i ruchomego celu (RANGE_FPS_PLAN.md, etap 3). Papier (range_sim.PAPER) na stelażu z listew:
## tarcza z pierścieniami, przestrzeliny bieżącej serii i tabliczka z miarą grupy (rozrzut w cm i MOA, rozciągnięcie w pionie — seria
## ogniem ciągłym ciągnie grupę w górę). Wózek (range_sim.mover_x) jeździ po szynie w poprzek tunelu z blachą na zawiasie; tabliczka
## z trafieniami i próbami. Liczy range_sim.gd, tu tylko obraz i dźwięk (range_view.gd woła `tick` co klatkę).

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const HOLE := 0.009                   ## m — średnica przestrzeliny 9 mm (obraz; kaliber nie zmienia)

var view: Node                        ## range_view.gd
var sim: RangeSim
var _sheet: MeshInstance3D
var _holes: Array = []
var _hole_mat: StandardMaterial3D
var _paper_lbl: Label3D
var _cart: Node3D
var _pivot: Node3D
var _fall := 0.0
var _mover_lbl: Label3D

func setup(v: Node, s: RangeSim) -> void:
	view = v
	sim = s
	sim.paper_hole.connect(_on_hole)
	sim.paper_cleared.connect(_on_cleared)
	sim.mover_hit.connect(_on_mover_hit)

func _ready() -> void:
	_build_paper()
	_build_mover()
	var lamp := SpotLight3D.new()                             # lampa nad papierem i wózkiem: koniec tunelu był ciemny
	lamp.light_color = Color(1.0, 0.86, 0.68)
	lamp.light_energy = 3.0
	lamp.spot_range = 6.0
	lamp.spot_angle = 50.0
	lamp.position = Vector3(0.3, RangeSim.LANE_H - 0.15, (RangeSim.PAPER.z + RangeSim.MOVER_Z) * 0.5 + 1.2)
	lamp.rotation = Vector3(deg_to_rad(-80.0), 0.0, 0.0)
	add_child(lamp)
	view._box(Vector3(0.5, 0.08, 0.2), lamp.position + Vector3(0.0, 0.06, 0.0), view._glow(Color(1.0, 0.9, 0.75), 2.0))

## Wyniki papieru i wózka do tablicy nad linią ognia (range_view._update_board) — tabliczki przy celach są z 25 m nieczytelne.
func board_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var g := sim.paper_group()
	if int(g["n"]) >= 2:
		out.append(tr("paper %d · %.1f cm (%.1f MOA) · ↕ %.1f cm") % [int(g["n"]), float(g["spread"]) * 100.0, float(g["moa"]), float(g["vertical"]) * 100.0])
	elif int(g["n"]) == 1:
		out.append(tr("paper 1"))
	var pb := Profile.range_best_of(RangeSim.EX_PAPER, String(view.fp.player.weapons.cur().key))   # rekord osobisty grupy 5 strzałów tą bronią
	if pb >= 0.0:
		var s := tr("best %d-shot group %.1f MOA") % [RangeSim.PAPER_PB_SHOTS, pb]
		if view.fp.paper_pb_new and sim.clock - view.fp.paper_pb_at < 5.0:
			s += "  ·  " + tr("PERSONAL BEST")
		out.append(s)
	out.append(tr("mover %d / %d") % [sim.mover_hits, sim.mover_tries])
	return out

func tick(delta: float) -> void:
	var x := RangeSim.mover_x(sim.clock)
	_cart.position.x = x
	_fall = move_toward(_fall, 1.0 if sim.mover_down else 0.0, delta * (7.0 if sim.mover_down else 2.5))
	_pivot.rotation.x = -1.42 * (_fall * _fall * (3.0 - 2.0 * _fall))
	var g := sim.paper_group()
	var pl := PackedStringArray([tr("PAPER  %d m") % int(round(-RangeSim.PAPER.z))])      # wiersze tłumaczone osobno (klucze bez \n)
	if int(g["n"]) == 1:
		pl.append(tr("1 hole"))
	elif int(g["n"]) > 1:
		pl.append(tr("%d holes · group %.1f cm (%.1f MOA)") % [int(g["n"]), float(g["spread"]) * 100.0, float(g["moa"])])
		pl.append(tr("vertical %.1f cm") % (float(g["vertical"]) * 100.0))
	_paper_lbl.text = "\n".join(pl)
	_mover_lbl.text = "\n".join(PackedStringArray([tr("MOVER  %d m · %.1f m/s") % [int(round(-RangeSim.MOVER_Z)), RangeSim.MOVER_SPEED],
		tr("hits %d / %d") % [sim.mover_hits, sim.mover_tries]]))

# ---------------------------------------------------------------- papier

func _build_paper() -> void:
	var c := RangeSim.PAPER
	var sz := RangeSim.PAPER_SIZE
	var wood: StandardMaterial3D = view._flat(Color(0.42, 0.3, 0.18), 0.85)
	for sx in [-1.0, 1.0]:                                    # stelaż: dwie listwy wbite w podstawę
		view._box(Vector3(0.04, c.y + sz.y * 0.5 + 0.05, 0.03), Vector3(c.x + sx * (sz.x * 0.5 + 0.03), (c.y + sz.y * 0.5 + 0.05) * 0.5, c.z - 0.02), wood)
	view._box(Vector3(sz.x + 0.2, 0.06, 0.3), Vector3(c.x, 0.03, c.z - 0.02), wood)
	view._box(Vector3(sz.x + 0.1, sz.y + 0.06, 0.012), Vector3(c.x, c.y, c.z - 0.012), view._flat(Color(0.55, 0.45, 0.32), 0.9))   # tektura pod arkuszem
	_sheet = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	_sheet.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = _target_texture()
	m.roughness = 0.95
	_sheet.material_override = m
	_sheet.position = c
	add_child(_sheet)
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hole_mat.albedo_texture = view._radial(Color(0.02, 0.02, 0.02, 1.0), Color(0.25, 0.22, 0.18, 0.0))
	_hole_mat.roughness = 1.0
	_paper_lbl = _label(Vector3(c.x, c.y + sz.y * 0.5 + 0.22, c.z + 0.02), 40)

## Tarcza strzelecka na arkuszu: kremowy papier, czarne pole z pierścieniami 1–10, numery pierścieni, krzyżyk w środku.
func _target_texture() -> ImageTexture:
	var w := 300
	var h := 400
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var paper := Color(0.88, 0.85, 0.76)
	var cx := w * 0.5
	var cy := h * 0.45
	var ring := w * 0.045                                    # szerokość pierścienia (px)
	for y in h:
		for x in w:
			var r := Vector2(x - cx, y - cy).length()
			var k := int(r / ring)                               # 0 — dziesiątka
			var col := paper
			if k < 10:
				var black := k < 6
				col = Color(0.06, 0.06, 0.06) if black else paper
				var edge := absf(r - float(k + 1) * ring) < 0.9
				if edge:
					col = paper if black else Color(0.1, 0.1, 0.1)
			if absf(x - cx) < 0.6 and r < ring * 0.6 or absf(y - cy) < 0.6 and r < ring * 0.6:
				col = paper
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _on_hole(l: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(HOLE * 2.2, HOLE * 2.2)
	mi.mesh = q
	mi.material_override = _hole_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = RangeSim.PAPER + Vector3(l.x, l.y, 0.002)
	add_child(mi)
	_holes.append(mi)
	while _holes.size() > RangeSim.PAPER_MAX:
		(_holes.pop_front() as Node).queue_free()
	view._play3d("impact_hard", 3, RangeSim.PAPER, -22.0, 0.1)    # cichy trzask papieru i tektury

func _on_cleared() -> void:
	for mi in _holes:
		(mi as Node).queue_free()
	_holes.clear()

# ---------------------------------------------------------------- wózek

func _build_mover() -> void:
	var z := RangeSim.MOVER_Z
	var steel: StandardMaterial3D = view._flat(Color(0.3, 0.3, 0.3), 0.5, 0.7)
	for dz in [-0.08, 0.08]:                                   # szyna w poprzek tunelu
		view._box(Vector3(RangeSim.LANE_W - 0.2, 0.04, 0.03), Vector3(0.0, 0.02, z + dz), steel)
	_cart = Node3D.new()
	_cart.position = Vector3(0.0, 0.0, z)
	add_child(_cart)
	view._box(Vector3(0.36, 0.1, 0.26), Vector3(0.0, 0.09, 0.0), view._flat(Color(0.35, 0.33, 0.12), 0.6, 0.3), _cart)
	var hinge_y := RangeSim.MOVER_Y - RangeSim.PLATE_R - 0.03
	var post := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.02
	cy.bottom_radius = 0.024
	cy.height = hinge_y - 0.14
	post.mesh = cy
	post.material_override = steel
	post.position = Vector3(0.0, 0.14 + cy.height * 0.5, 0.0)
	_cart.add_child(post)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, hinge_y, 0.0)
	_cart.add_child(_pivot)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = RangeSim.PLATE_R
	dm.bottom_radius = RangeSim.PLATE_R
	dm.height = 0.012
	dm.radial_segments = 32
	disc.mesh = dm
	disc.material_override = view._flat(Color(0.9, 0.55, 0.12), 0.5, 0.4)      # pomarańczowa — odróżnia się od blach przebiegu
	disc.rotation.x = PI * 0.5
	disc.position = Vector3(0.0, RangeSim.PLATE_R + 0.03, 0.0)
	_pivot.add_child(disc)
	view._box(Vector3(0.05, 0.06, 0.012), Vector3(0.0, 0.03, 0.0), disc.material_override, _pivot)
	_mover_lbl = _label(Vector3(0.0, RangeSim.LANE_H - 0.55, z + 0.3), 44)

func _on_mover_hit() -> void:
	var p := Vector3(RangeSim.mover_x(sim.clock), RangeSim.MOVER_Y, RangeSim.MOVER_Z)
	view._burst(p + Vector3(0, 0, 0.01), Vector3(0, 0, 1), Color(1.0, 0.72, 0.3), 14, 3.5)
	view._play3d("plate_ring", 4, p, 0.0, 0.05)

func _label(pos: Vector3, size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = Color(0.95, 0.85, 0.3)
	l.outline_size = 8
	l.position = pos
	add_child(l)
	return l
