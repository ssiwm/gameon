extends Node3D
## Strzelnica FPP — obraz broni specjalnych (RANGE_FPS_PLAN.md, etap 3): pociski w locie (granat WRATH-4, rakieta FALCON-6 z dymem
## silnika), wybuch i niewypał, ślad szyny SPECTER-1, promień LR-7, płomień HKM-9 z ogniem na podłodze i rozgrzane blachy. Liczy to
## range_sim.gd (tory, trafienia, wybuchy, ciepło blach); tu jest tylko obraz i dźwięk w świecie tunelu — range_view.gd woła `tick`
## co klatkę z położeniem wylotu lufy.

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const MUZZLE_BLEND := 0.12            ## s — tor pocisku zaczyna się w oku (linia strzału); obraz przechodzi od wylotu lufy w tym czasie
const RAIL_T := 0.45                  ## s — gaśnięcie śladu szyny
const FRESH := 0.15                   ## s — promień i płomień widać tyle po ostatnim kroku ognia (krok co 0,1 s)
const BLAST_T := 0.35                 ## s — błysk wybuchu
const SCORCH_MAX := 24
const BEAM_COL := Color(0.55, 0.9, 1.0)
const RAIL_COL := Color(0.65, 0.92, 1.0)
const FIRE_COL := Color(1.0, 0.55, 0.18)

var view: Node                         ## range_view.gd (dźwięk 3D, iskry, dym, przestrzeliny)
var sim: RangeSim
var plate_mats: Array = []             ## materiał tarczy każdej blachy (range_view._build_plates) — żar od promienia i płomienia
var _flights: Array = []               ## [{node, pts, t, off, smoke}]
var _rails: Array = []                 ## [{node, mat, light, t}]
var _blasts: Array = []                ## [{light, t}]
var _fires := {}                       ## klucz plamy ognia (range_sim.fires) → węzeł
var _scorch: Array = []
var _scorch_i := 0
var _scorch_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _beam_light: OmniLight3D
var _beam_seen := -1.0
var _flame: CPUParticles3D
var _flame_light: OmniLight3D
const STUCK_MAX := 8
var _stuck: Array = []                 ## wbite bełty SINEW-6
var _bolt_dir := Vector3.FORWARD       ## kierunek ostatniego odcinka toru bełtu (wbicie)

func setup(v: Node, s: RangeSim) -> void:
	view = v
	sim = s
	sim.flight.connect(_on_flight)
	sim.landed.connect(_on_landed)

func _ready() -> void:
	_beam_mat = _add_mat(BEAM_COL, 4.0)
	_beam = MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.009
	cy.bottom_radius = 0.009
	cy.height = 1.0
	cy.radial_segments = 8
	_beam.mesh = cy
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_beam_light = _light(BEAM_COL, 3.0)
	_flame = _flame_emitter()
	add_child(_flame)
	_flame_light = _light(FIRE_COL, 4.5)
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.albedo_texture = view._radial(Color(0.02, 0.018, 0.016, 0.9), Color(0.05, 0.04, 0.03, 0.0))
	_scorch_mat.roughness = 1.0

## Co klatkę: pociski w locie, ślady szyny, błyski wybuchów, promień i płomień od wylotu `muzzle` w kierunku `fwd`, ogień na podłodze, żar blach.
func tick(delta: float, muzzle: Vector3, fwd: Vector3) -> void:
	_tick_flights(delta)
	for r in _rails.duplicate():
		r["t"] = float(r["t"]) + delta
		var k := 1.0 - float(r["t"]) / RAIL_T
		if k <= 0.0:
			(r["node"] as Node).queue_free()
			(r["light"] as Node).queue_free()
			_rails.erase(r)
			continue
		(r["mat"] as StandardMaterial3D).albedo_color.a = k
		(r["mat"] as StandardMaterial3D).emission_energy_multiplier = 6.0 * k
		(r["light"] as OmniLight3D).light_energy = 4.0 * k * k
	for b in _blasts.duplicate():
		b["t"] = float(b["t"]) + delta
		var k2 := 1.0 - float(b["t"]) / BLAST_T
		if k2 <= 0.0:
			(b["light"] as Node).queue_free()
			_blasts.erase(b)
		else:
			(b["light"] as OmniLight3D).light_energy = 14.0 * k2 * k2
	# promień LR-7: od wylotu do końca ostatniego kroku, migocze; nowy krok sypie iskrami tam, gdzie gaśnie
	var beam_on := sim.beam_at >= 0.0 and sim.clock - sim.beam_at < FRESH
	_beam.visible = beam_on
	_beam_light.visible = beam_on
	if beam_on:
		_stretch(_beam, muzzle, sim.beam_to)
		var f := 0.75 + 0.25 * sin(sim.clock * 90.0)
		_beam_mat.emission_energy_multiplier = 4.0 * f
		_beam_light.position = sim.beam_to - (sim.beam_to - muzzle).normalized() * 0.15
		_beam_light.light_energy = 2.5 * f
		if sim.beam_at != _beam_seen:
			_beam_seen = sim.beam_at
			view._burst(sim.beam_to, (muzzle - sim.beam_to).normalized(), Color(0.85, 0.95, 1.0), 5, 2.0)
	# płomień HKM-9: stożek cząstek z wylotu do zasięgu kroku
	var flame_on := sim.flame_at >= 0.0 and sim.clock - sim.flame_at < FRESH
	if _flame.emitting != flame_on:
		_flame.emitting = flame_on
	_flame_light.visible = flame_on
	if flame_on:
		_flame.global_position = muzzle
		_flame.direction = fwd
		_flame.initial_velocity_min = sim.flame_reach / _flame.lifetime * 0.75
		_flame.initial_velocity_max = sim.flame_reach / _flame.lifetime * 1.05
		_flame_light.position = muzzle + fwd * sim.flame_reach * 0.6
		_flame_light.light_energy = 1.8 + 0.6 * sin(sim.clock * 37.0) * sin(sim.clock * 13.0)       # mocniej prześwietlało cały tunel
	_tick_fires()
	for i in mini(plate_mats.size(), sim.plates.size()):
		var h := clampf(float(sim.plates[i]["heat"]) / RangeSim.PLATE_HEAT, 0.0, 1.0)
		var m := plate_mats[i] as StandardMaterial3D
		m.emission_enabled = h > 0.02
		m.emission = Color(1.0, 0.25 + 0.35 * h, 0.05)
		m.emission_energy_multiplier = 2.5 * h * h

## Ślad szyny SPECTER-1: jasny pręt od wylotu do końca strzału, gaśnie w RAIL_T, błysk światła na końcu.
func rail(from: Vector3, to: Vector3) -> void:
	var mat := _add_mat(RAIL_COL, 6.0)
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.014
	cy.bottom_radius = 0.014
	cy.height = 1.0
	cy.radial_segments = 8
	mi.mesh = cy
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_stretch(mi, from, to)
	var lt := _light(RAIL_COL, 6.0)
	lt.visible = true
	lt.position = to - (to - from).normalized() * 0.2
	_rails.append({"node": mi, "mat": mat, "light": lt, "t": 0.0})

# ---------------------------------------------------------------- pociski w locie

func _on_flight(points: PackedVector3Array, _secs: float, key: String) -> void:
	var node := Node3D.new()
	add_child(node)
	var smoke: CPUParticles3D = null
	if key == "sokol6":                                       # rakieta Gyrojet: żarzący się silnik i smuga dymu
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		core.mesh = sm
		core.material_override = _add_mat(Color(1.0, 0.75, 0.4), 8.0)
		node.add_child(core)
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.65, 0.3)
		lt.omni_range = 2.0
		lt.light_energy = 1.5
		node.add_child(lt)
		smoke = view._fx._smoke_emitter(40, 0.9, 0.22, 0.06)
		smoke.direction = Vector3.UP
		smoke.spread = 180.0
		add_child(smoke)
		smoke.emitting = true
	elif key == "ciegno6":                                    # bełt kuszy podwodnej: cienki stalowy pręt (50 cm) wzdłuż toru
		node.add_child(_bolt_mesh())
		if points.size() > 1:
			_bolt_dir = (points[points.size() - 1] - points[points.size() - 2]).normalized()
	else:                                                     # granat 40 mm: ciemny walec z mosiężnym dnem
		var body := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.02
		cy.bottom_radius = 0.02
		cy.height = 0.05
		body.mesh = cy
		body.material_override = view._flat(Color(0.25, 0.27, 0.2), 0.6, 0.3)
		body.rotation.x = PI * 0.5
		node.add_child(body)
	var off := Vector3.ZERO
	if points.size() > 1:
		off = _muzzle_now() - points[0]
	_flights.append({"node": node, "pts": points, "t": 0.0, "off": off, "smoke": smoke})
	_tick_flights(0.0)

func _muzzle_now() -> Vector3:
	return view.muzzle_world()

func _tick_flights(delta: float) -> void:
	var dt := RangeSim.FLIGHT_DT * RangeSim.FLIGHT_PT_EVERY
	for f in _flights.duplicate():
		f["t"] = float(f["t"]) + delta
		var pts: PackedVector3Array = f["pts"]
		var fi := float(f["t"]) / dt
		var node := f["node"] as Node3D
		if fi >= float(pts.size() - 1):
			node.queue_free()
			var sm = f["smoke"]
			if sm != null:
				(sm as CPUParticles3D).emitting = false
				get_tree().create_timer(1.2).timeout.connect((sm as Node).queue_free)
			_flights.erase(f)
			continue
		var i := int(fi)
		var p := pts[i].lerp(pts[i + 1], fi - float(i))
		p += (f["off"] as Vector3) * maxf(0.0, 1.0 - float(f["t"]) / MUZZLE_BLEND)
		var dir := pts[i + 1] - pts[i]
		node.global_position = p
		if dir.length() > 1e-4:
			node.look_at(p + dir, Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD)
		var sm2 = f["smoke"]
		if sm2 != null:
			(sm2 as CPUParticles3D).global_position = p

## Uderzenie pocisku z lotu: wybuch (błysk, kula ognia, dym, okopcenie, huk), niewypał albo trafienie rakiety (iskry, przestrzelina).
func _on_landed(pos: Vector3, normal: Vector3, kind: String, key: String, exploded: bool, radius: float) -> void:
	if exploded:
		var lt := _light(Color(1.0, 0.7, 0.35), 8.0 + radius)
		lt.visible = true
		lt.position = pos + normal * 0.4
		_blasts.append({"light": lt, "t": 0.0})
		_fireball(pos + normal * 0.1, normal, radius)
		view._burst(pos + normal * 0.05, normal, Color(1.0, 0.62, 0.22), 60, 9.0)            # iskry i odłamki
		view._burst(pos + normal * 0.05, normal, Color(0.45, 0.4, 0.34), 30, 5.0)
		if kind != "plate":
			_scorch_at(pos, normal, minf(radius * 0.45, 1.6))
		view._play3d("explosion", 2, pos, 2.0, 0.05)
		return
	if kind == "mover":
		return                                                    # iskry i dzwonienie wózka: range_targets.gd
	if kind == "plate":
		view._burst(pos + normal * 0.01, normal, Color(1.0, 0.72, 0.3), 14, 3.5)
		view._play3d("plate_ring", 4, pos, 0.0, 0.05)
	elif key == "ciegno6":                                    # bełt wbija się w beton / piasek i zostaje (STUCK_MAX ostatnich)
		var b := Node3D.new()
		b.add_child(_bolt_mesh())
		add_child(b)
		b.global_position = pos - _bolt_dir * 0.1                 # grot (0,15 m przed węzłem) wchodzi ok. 5 cm w cel
		b.look_at(pos + _bolt_dir, Vector3.UP if absf(_bolt_dir.y) < 0.95 else Vector3.FORWARD)
		_stuck.append(b)
		while _stuck.size() > STUCK_MAX:
			(_stuck.pop_front() as Node).queue_free()
		view._burst(pos + normal * 0.02, normal, Color(0.5, 0.46, 0.4), 6, 1.2)
		view._play3d("impact_hard", 3, pos, -12.0, 0.1)
	else:
		view._hole(pos, normal)
		view._burst(pos + normal * 0.02, normal, Color(0.5, 0.46, 0.4), 10 if key == "gniew4" else 8, 1.6)
		view._play3d("impact_hard", 3, pos, -6.0 if key == "gniew4" else -10.0, 0.08)     # niewypał 40 mm: tępe uderzenie

## Kula ognia (krótka, jasna, addytywna) i ciemny obłok dymu, który po niej zostaje i wolno się rozchodzi; wielkość od promienia wybuchu.
func _fireball(pos: Vector3, n: Vector3, radius: float) -> void:
	var k := clampf(radius / 4.0, 0.5, 1.5)
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.amount = 24
	fire.lifetime = 0.45
	fire.local_coords = false
	fire.direction = n
	fire.spread = 80.0
	fire.initial_velocity_min = 2.0 * k
	fire.initial_velocity_max = 6.0 * k
	fire.damping_min = 6.0
	fire.damping_max = 10.0
	fire.gravity = Vector3(0.0, 1.5, 0.0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1.0, 1.3))
	fire.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.92, 0.7, 0.8), Color(1.0, 0.58, 0.17, 0.7), Color(0.6, 0.18, 0.04, 0.4), Color(0.1, 0.08, 0.06, 0.0)])
	fire.color_ramp = ramp
	fire.mesh = _particle_quad(0.9 * k, true)
	add_child(fire)
	fire.global_position = pos
	fire.emitting = true
	var smoke := view._fx._smoke_emitter(18, 2.6, 0.55, 1.1 * k) as CPUParticles3D
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.direction = n
	smoke.spread = 70.0
	smoke.initial_velocity_min = 0.6 * k
	smoke.initial_velocity_max = 2.2 * k
	var sr := Gradient.new()
	sr.offsets = PackedFloat32Array([0.0, 0.35, 1.0])                 # szary, półprzezroczysty — ciemny (nieoświetlony) wyglądał jak czarna kula
	sr.colors = PackedColorArray([Color(0.6, 0.57, 0.53, 0.0), Color(0.55, 0.53, 0.5, 0.32), Color(0.5, 0.49, 0.48, 0.0)])
	smoke.color_ramp = sr
	smoke.emitting = false                                  # CPUParticles3D emituje od razu po utworzeniu
	add_child(smoke)
	smoke.global_position = pos
	get_tree().create_timer(0.25).timeout.connect(func() -> void: smoke.emitting = true)     # dym po błysku: nieoświetlony na jasnym tle wychodził czarną kulą
	get_tree().create_timer(3.4).timeout.connect(func() -> void:
		fire.queue_free()
		smoke.queue_free())

## Bełt: pręt wzdłuż −z węzła (look_at), grot z przodu.
func _bolt_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.0035
	cy.bottom_radius = 0.0035
	cy.height = 0.5
	cy.radial_segments = 6
	mi.mesh = cy
	mi.material_override = view._flat(Color(0.6, 0.6, 0.58), 0.35, 0.9)
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(0.0, 0.0, 0.1)
	return mi

func _scorch_at(pos: Vector3, n: Vector3, size: float) -> void:
	var mi: MeshInstance3D
	if _scorch.size() < SCORCH_MAX:
		mi = MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		mi.material_override = _scorch_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_scorch.append(mi)
	else:
		mi = _scorch[_scorch_i]
		_scorch_i = (_scorch_i + 1) % SCORCH_MAX
	(mi.mesh as QuadMesh).size = Vector2(size, size)
	var z := n.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var xa := up.cross(z).normalized()
	mi.transform = Transform3D(Basis(xa, z.cross(xa), z), pos + z * 0.006)

# ---------------------------------------------------------------- ogień na podłodze

func _tick_fires() -> void:
	var live := {}
	for e in sim.fires:
		var k := "%.3f|%.3f|%.3f" % [float(e["until"]), (e["pos"] as Vector3).x, (e["pos"] as Vector3).z]
		live[k] = true
		if not _fires.has(k):
			var p := _fire_emitter()
			add_child(p)
			p.global_position = e["pos"]
			p.emitting = true
			var lt := _light(FIRE_COL, 2.5)
			lt.visible = true
			lt.position = (e["pos"] as Vector3) + Vector3(0.0, 0.3, 0.0)
			lt.light_energy = 1.4
			_fires[k] = [p, lt]
			_scorch_at(e["pos"], Vector3.UP, 0.5)
	for k in _fires.keys():
		if not live.has(k):
			var pair: Array = _fires[k]
			(pair[0] as CPUParticles3D).emitting = false
			get_tree().create_timer(1.0).timeout.connect((pair[0] as Node).queue_free)
			(pair[1] as Node).queue_free()
			_fires.erase(k)
		else:
			var lt2 := (_fires[k] as Array)[1] as OmniLight3D
			lt2.light_energy = 1.2 + 0.4 * sin(sim.clock * 23.0 + float(k.hash() % 7))

# ---------------------------------------------------------------- pomocnicze

## Walec o wysokości 1 (CylinderMesh) rozciągnięty od `a` do `b`.
func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := maxf(d.length(), 0.001)
	var y := d / ln
	var xa := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := xa.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(xa, y * ln, z), (a + b) * 0.5)

## Świecący, addytywny materiał (promień, szyna, żar rakiety).
func _add_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _light(c: Color, rng: float) -> OmniLight3D:
	var lt := OmniLight3D.new()
	lt.light_color = c
	lt.omni_range = rng
	lt.light_energy = 0.0
	lt.shadow_enabled = false
	lt.visible = false
	add_child(lt)
	return lt

## Płomień: gęsty strumień cząstek z wylotu (kierunek i prędkość ustawia `tick` wg zasięgu), żółty → pomarańcz → czerwień → dym.
func _flame_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.38
	p.local_coords = false
	p.emitting = false
	p.spread = 9.0
	p.gravity = Vector3(0.0, 1.6, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(0.6, 1.4))
	sc.add_point(Vector2(1.0, 2.0))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.5, 0.55), Color(1.0, 0.5, 0.12, 0.5), Color(0.7, 0.18, 0.04, 0.3), Color(0.15, 0.12, 0.1, 0.0)])
	p.color_ramp = ramp
	p.mesh = _particle_quad(0.22, true)
	return p

## Ogień na podłodze: niskie płomyki z plamy.
func _fire_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.2, 0.02, 0.2)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0.0, 0.8, 0.0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 0.9), Color(1.0, 0.45, 0.1, 0.6), Color(0.4, 0.1, 0.02, 0.0)])
	p.color_ramp = ramp
	p.mesh = _particle_quad(0.16, true)
	return p

func _particle_quad(size: float, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = view._fx._soft_dot()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	return q
