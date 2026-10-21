extends Node3D
## Strzelnica FPP — łuski i dym w świecie tunelu (RANGE_FPS_PLAN.md). Łuska wylatuje z okna wyrzutowego (prędkość w prawo, w górę i lekko
## w tył, rotacja), odbija się od ławy, podłogi i ścian z tłumieniem i stukiem, a potem leży na ziemi — najwyżej CASINGS_MAX naraz
## (najstarsze znikają). Łuski 7,62×39 z tamtych lat były stalowe, lakierowane na zielonoszaro; śrut — czerwona łuska z mosiężnym denkiem.
## Dym: obłoczek z wylotu po każdym strzale i smużki z gorącej lufy (WeaponController.barrel_of). Geometria kolizji jak w range_sim.gd.

const RangeSim := preload("res://scripts/range3d/range_sim.gd")

const CASINGS_MAX := 60
const G := Vector3(0.0, -9.81, 0.0)
const BOUNCE := 0.32                  ## odbicie w pionie (stal o beton / drewno)
const SLIDE := 0.55                   ## tłumienie w poziomie przy odbiciu
const REST_SPEED := 0.22              ## m/s — wolniej leży
const R_RIFLE := 0.0056               ## m — promień łuski 7,62×39 przy denku
const L_RIFLE := 0.039
const R_SHELL := 0.0105               ## m — łuska 12/70
const L_SHELL := 0.07

var _casings: Array = []              ## [{node, v, w (Vector3 rad/s), r, bounces, rest}]
var _mesh_rifle: Mesh
var _mesh_shell: Mesh
var _wisp: CPUParticles3D

func _ready() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045                                       # szyjka
	cm.bottom_radius = R_RIFLE
	cm.height = L_RIFLE
	cm.radial_segments = 12
	cm.rings = 1
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.46, 0.47, 0.34)                # stal lakierowana na zielonoszaro, z połyskiem lakieru
	steel.metallic = 0.6
	steel.roughness = 0.32
	cm.material = steel
	_mesh_rifle = cm
	var sm := CylinderMesh.new()
	sm.top_radius = R_SHELL
	sm.bottom_radius = R_SHELL
	sm.height = L_SHELL
	sm.radial_segments = 14
	sm.rings = 1
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.45, 0.06, 0.05)
	plastic.roughness = 0.55
	sm.material = plastic
	_mesh_shell = sm
	_wisp = _smoke_emitter(24, 2.2, 0.12, 0.06)
	_wisp.emitting = false
	_wisp.one_shot = false
	add_child(_wisp)

## Łuska w świecie: `pos` (m), prędkość `vel` (m/s), `big` — śrut.
func eject(pos: Vector3, vel: Vector3, big := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_shell if big else _mesh_rifle
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.basis = Basis(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(), randf() * TAU)
	var w := Vector3(randf_range(-25.0, 25.0), randf_range(-8.0, 8.0), randf_range(-25.0, 25.0))
	_casings.append({"node": mi, "v": vel, "w": w, "r": (R_SHELL if big else R_RIFLE), "bounces": 0, "rest": false, "big": big})
	while _casings.size() > CASINGS_MAX:
		var old: Dictionary = _casings.pop_front()
		(old["node"] as Node).queue_free()

## Obłoczek dymu z wylotu: `dir` — kierunek lufy w świecie.
func puff(pos: Vector3, dir: Vector3, strength := 1.0) -> void:
	var p := _smoke_emitter(int(8 * strength) + 2, 1.6, 0.14, 0.09)
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = dir
	p.spread = 18.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1 * strength
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

## Smużki z gorącej lufy (wołać co klatkę): `heat` 0..1 — od 0,45 dym, im goręcej, tym gęściej.
func barrel_smoke(pos: Vector3, heat: float) -> void:
	_wisp.global_position = pos
	var on := heat > 0.45
	if on != _wisp.emitting:
		_wisp.emitting = on
	_wisp.color = Color(1.0, 1.0, 1.0, clampf((heat - 0.45) / 0.55, 0.2, 1.0))   # im goręcej, tym gęściej (przezroczystość)

func _smoke_emitter(amount: int, life: float, alpha: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0.0, 0.18, 0.0)                         # ciepły dym unosi się powoli
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.damping_min = 1.2
	p.damping_max = 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.82, 0.82, 0.80, alpha))
	ramp.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED          # dym jasny i półprzezroczysty — oświetlony w ciemnym tunelu dawał czarne tarcze
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

static var _dot: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 64
		_dot.height = 64
	return _dot

func _physics_process(delta: float) -> void:
	for c in _casings:
		if c["rest"]:
			continue
		var n := c["node"] as Node3D
		var v: Vector3 = c["v"] + G * delta
		var p := n.global_position + v * delta
		var r: float = c["r"]
		var floor_y := r
		if p.z <= 0.0 and p.z >= RangeSim.BENCH_Z and absf(p.x) < RangeSim.LANE_W * 0.5 and n.global_position.y >= RangeSim.BENCH_H:
			floor_y = RangeSim.BENCH_H + r                       # blat ławy
		var hit := false
		if p.y < floor_y and v.y < 0.0:
			p.y = floor_y
			v.y = -v.y * BOUNCE
			v.x *= SLIDE
			v.z *= SLIDE
			hit = true
		var px := n.global_position.x
		for dx in RangeSim.DIVIDERS:                             # przegrody stanowisk (łuska odbija się i spada we własnym boksie)
			if (px - dx) * (p.x - dx) <= 0.0 and p.z >= RangeSim.DIVIDER_Z.x and p.z <= RangeSim.DIVIDER_Z.y and p.y >= RangeSim.DIVIDER_Y.x and p.y <= RangeSim.DIVIDER_Y.y:
				p.x = dx - signf(p.x - px) * (0.026 + r)
				v.x = -v.x * 0.35
				hit = true
		for s in [-1.0, 1.0]:                                    # ściany tunelu
			if p.x * s > RangeSim.LANE_W * 0.5 - r:
				p.x = s * (RangeSim.LANE_W * 0.5 - r)
				v.x = -v.x * 0.4
				hit = true
		if hit:
			c["w"] = (c["w"] as Vector3) * 0.5 + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
			var spd := v.length()
			if int(c["bounces"]) < 3 and spd > 0.4:
				Audio.play_variant("shell", 3, Audio.BUS_WEAPONS, lerpf(-30.0, -16.0, clampf(spd / 3.0, 0.0, 1.0)) - (4.0 if c["big"] else 0.0),
					randf_range(0.9, 1.15) * (0.75 if c["big"] else 1.0))
			c["bounces"] = int(c["bounces"]) + 1
			if spd < REST_SPEED and absf(p.y - floor_y) < 0.002:
				c["rest"] = true                                 # leży: oś pozioma, losowy kierunek
				n.basis = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5)
				n.global_position = Vector3(p.x, floor_y, p.z)
				continue
		var w: Vector3 = c["w"]
		if w.length() > 0.001:
			n.basis = Basis(w.normalized(), w.length() * delta) * n.basis
		n.global_position = p
		c["v"] = v
