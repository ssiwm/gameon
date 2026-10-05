extends RefCounted
## Efekty wizualne i „kosmetyczna" fizyka (1.5): kurz, iskry, rozbryzgi, krew,
## szczątki i łuski jako lekkie RigidBody2D, plamy krwi na podłożu.
##
## Wszystko lokalne na każdym peerze (bez synchronizacji) — to wizualia, nie
## stan gry. Ciała są na warstwie 64 i widzą tylko świat (1 | 16), więc nie
## zderzają się ze sobą ani z postaciami; liczba jest ograniczona, najstarsze
## znikają pierwsze.

const Lights := preload("res://scripts/lights.gd")

const DEBRIS_LAYER := 64
const DEBRIS_MASK := 1 | 16
const MAX_DEBRIS := 140
const DEBRIS_LIFE := 9.0
const MAX_DECALS := 260

static var _debris: Array = []

# ---------------------------------------------------------------- cząsteczki

static func burst(parent: Node, pos: Vector2, color: Color, amount: int, vmin: float, vmax: float,
		dir := Vector2.UP, spread := 60.0, gravity := 500.0, life := 0.5, size := Vector2(1.0, 2.0),
		unshaded := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = amount
	fx.lifetime = life
	fx.explosiveness = 0.95
	fx.direction = dir
	fx.spread = spread
	fx.initial_velocity_min = vmin
	fx.initial_velocity_max = vmax
	fx.gravity = Vector2(0, gravity)
	fx.scale_amount_min = size.x
	fx.scale_amount_max = size.y
	fx.color = color
	if unshaded:
		fx.material = Lights.unshaded()
	parent.add_child(fx)
	fx.global_position = pos
	parent.get_tree().create_timer(life + 0.3).timeout.connect(fx.queue_free)

## Kurz przy lądowaniu / zeskoku.
static func dust(parent: Node, pos: Vector2, strength := 1.0) -> void:
	burst(parent, pos + Vector2(0, -1), Color(0.55, 0.5, 0.42, 0.75), int(6 + 6 * strength), 15.0, 45.0 * strength,
		Vector2.UP, 80.0, 60.0, 0.45, Vector2(1.0, 2.2))

## Iskry przy trafieniu w bryłę — świecą (unshaded).
static func sparks(parent: Node, pos: Vector2, dir: Vector2) -> void:
	burst(parent, pos, Color(1.0, 0.85, 0.45), 8, 40.0, 130.0, -dir, 55.0, 380.0, 0.25, Vector2(0.8, 1.4), true)

## Rozbryzg wody (tartak).
static func splash(parent: Node, pos: Vector2, strength := 1.0) -> void:
	burst(parent, pos + Vector2(0, -1), Color(0.55, 0.78, 0.9, 0.85), int(8 + 8 * strength), 25.0, 70.0 * strength,
		Vector2.UP, 40.0, 420.0, 0.55, Vector2(0.8, 1.8))

## Krew przy trafieniu.
static func blood(parent: Node, pos: Vector2, dir: Vector2, amount := 8) -> void:
	burst(parent, pos, Color(0.45, 0.04, 0.06), amount, 30.0, 110.0, dir, 45.0, 520.0, 0.5, Vector2(1.0, 2.0))

## Smuga dymu po strzale.
static func smoke(parent: Node, pos: Vector2, dir: Vector2) -> void:
	burst(parent, pos, Color(0.7, 0.7, 0.72, 0.25), 4, 8.0, 24.0, dir, 25.0, -20.0, 0.7, Vector2(1.5, 3.0))

# ---------------------------------------------------------------- szczątki i łuski

## Kawałek ciała / łuska: małe RigidBody2D z kolorowym wielokątem.
static func debris(parent: Node, pos: Vector2, vel: Vector2, size: Vector2, color: Color,
		bounce := 0.25, spin := 8.0, on_hit := Callable()) -> RigidBody2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var b := RigidBody2D.new()
	b.collision_layer = DEBRIS_LAYER
	b.collision_mask = DEBRIS_MASK
	b.gravity_scale = 1.0
	b.linear_velocity = vel
	b.angular_velocity = randf_range(-spin, spin)
	var mat := PhysicsMaterial.new()
	mat.bounce = bounce
	mat.friction = 0.9
	b.physics_material_override = mat
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var poly := Polygon2D.new()
	var h := size * 0.5
	poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	poly.color = color
	b.add_child(poly)
	if on_hit.is_valid():
		b.contact_monitor = true
		b.max_contacts_reported = 1
		var fired := [false]
		b.body_entered.connect(func(_body: Node) -> void:
			if not fired[0]:
				fired[0] = true
				on_hit.call(b))
	# Dodanie odroczone: szczątki powstają zwykle w zdarzeniu kolizji (śmierć
	# od pocisku), a wtedy fizyka nie pozwala dodawać ciał („flushing queries").
	# Rodzice (Level, Players) leżą w (0,0), więc pozycja lokalna = globalna.
	b.position = pos
	b.tree_entered.connect(_track.bind(b), CONNECT_ONE_SHOT)
	parent.add_child.call_deferred(b)
	return b

static func _track(b: Node) -> void:
	_debris = _debris.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	_debris.append(b)
	while _debris.size() > MAX_DEBRIS:
		var old: Node = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := b.create_tween()
	tw.tween_interval(DEBRIS_LIFE)
	tw.tween_property(b, "modulate:a", 0.0, 1.0)
	tw.tween_callback(b.queue_free)

## Szczątki wroga: kilka kawałków rozrzuconych od trafienia + krew na podłożu.
static func gibs(parent: Node, pos: Vector2, color: Color, count: int, push := Vector2.ZERO) -> void:
	for i in count:
		var v := Vector2(randf_range(-90.0, 90.0), randf_range(-220.0, -80.0)) + push * 0.6
		var s := Vector2(randf_range(2.0, 4.0), randf_range(2.0, 3.5))
		var c := color.darkened(randf_range(0.0, 0.35))
		debris(parent, pos + Vector2(randf_range(-4, 4), randf_range(-8, 0)), v, s, c, 0.15, 10.0,
			func(b: RigidBody2D) -> void: splat(b.get_parent(), b.global_position, 2.5))
	blood(parent, pos + Vector2(0, -6), Vector2.UP, 14)
	splat(parent, pos, 6.0)

## Łuska wyrzucona w bok i w górę, przeciwnie do celowania; dźwięczy przy upadku.
static func casing(parent: Node, pos: Vector2, aim: Vector2, big := false) -> void:
	var side := -signf(aim.x) if absf(aim.x) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
	var v := Vector2(side * randf_range(40.0, 80.0), randf_range(-140.0, -90.0))
	var col := Color(0.55, 0.16, 0.12) if big else Color(0.85, 0.68, 0.3)
	debris(parent, pos, v, Vector2(3, 2) if big else Vector2(2, 1), col, 0.45, 20.0,
		func(b: RigidBody2D) -> void:
			Audio.play_variant_at("shell", 3, b.global_position, Audio.BUS_WORLD, -24.0 if not big else -20.0))

# ---------------------------------------------------------------- plamy

## Plama krwi na najbliższej powierzchni pod punktem (rysuje Decals w level.gd).
static func splat(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var lvl := parent.get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.has_method("add_decal"):
		return
	var space := (lvl as Node2D).get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(pos + Vector2(0, -4), pos + Vector2(0, 40), 1 | 16)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	lvl.add_decal(hit["position"], radius)

# ---------------------------------------------------------------- walka (1.6 — overhaul broni)

static var _hit_snd_ms := 0
static var _impact_snd_ms := 0

## Efekt trafienia celu: krew / iskry / drzazgi + dźwięk dobrany do materiału.
## Śrut (8 pocisków naraz) nie gra 8 dźwięków — krótki próg na dźwięk, efekt zawsze.
static func hit(parent: Node, pos: Vector2, dir: Vector2, mat: int, crit: bool, heavy: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	var snd := heavy or now - _hit_snd_ms > 40
	if snd:
		_hit_snd_ms = now
	match mat:
		Arsenal.Mat.FLESH:
			blood(parent, pos, dir, 5 + (5 if heavy else 0) + (4 if crit else 0))
			if snd:
				Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -9.0 + (3.0 if heavy else 0.0) + (2.0 if crit else 0.0),
					1.18 if crit else 1.0)
			if crit:
				# złoty błysk — trafienie w głowę ma być widać i słychać
				burst(parent, pos, Color(1.0, 0.88, 0.45), 7, 40.0, 120.0, -dir, 90.0, 160.0, 0.18, Vector2(0.8, 1.6), true)
		Arsenal.Mat.ARMOR, Arsenal.Mat.METAL:
			sparks(parent, pos, dir)
			if snd:
				Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, -12.0, 1.25)
				Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -17.0, 1.1, 0.12)
		Arsenal.Mat.WOOD:
			burst(parent, pos, Color(0.55, 0.38, 0.2), 7, 30.0, 90.0, -dir, 70.0, 420.0, 0.35, Vector2(1.0, 2.0))
			if snd:
				Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, -14.0, 0.62)

## Pocisk w ścianę: efekt wg powierzchni (kafel mapy), z krótkim progiem na dźwięk.
static func impact(parent: Node, pos: Vector2, normal: Vector2, surface: String, heavy := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var out := normal if normal.length() > 0.1 else Vector2.UP
	var now := Time.get_ticks_msec()
	var snd := heavy or now - _impact_snd_ms > 45
	if snd:
		_impact_snd_ms = now
	match surface:
		"water":
			splash(parent, pos, 0.6)
		"dirt":
			burst(parent, pos, Color(0.5, 0.4, 0.28, 0.8), 6, 20.0, 70.0, out, 60.0, 380.0, 0.35, Vector2(1.0, 2.0))
			if snd:
				Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, -15.0, 0.7)
		"concrete":
			burst(parent, pos, Color(0.6, 0.6, 0.62, 0.9), 5, 30.0, 90.0, out, 55.0, 420.0, 0.3, Vector2(0.8, 1.6))
			sparks(parent, pos, -out)
			if snd:
				Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, -12.0, 1.0)
				if randf() < 0.5:
					Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -20.0, 1.0, 0.12)
		_:
			sparks(parent, pos, -out)
			if snd:
				Audio.play_variant_at("impact_hard", 3, pos, Audio.BUS_WORLD, -12.0, 1.2)
				Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -19.0, 1.0, 0.12)

## Smuga o zanikającej jasności (tor szyny, promień, trasa kuli). Rysowana bez cieniowania.
static func streak(parent: Node, a: Vector2, b: Vector2, color: Color, width := 2.0, life := 0.12) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var s := Streak.new()
	s.a = a
	s.b = b
	s.color = color
	s.width = width
	s.life = life
	s.material = Lights.unshaded()
	s.z_index = 3
	parent.add_child(s)

## Fala uderzeniowa wybuchu.
static func shock(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var r := ShockRing.new()
	r.max_r = radius
	r.material = Lights.unshaded()
	r.z_index = 3
	parent.add_child(r)
	r.global_position = pos

## Pełny wybuch (granat, rakieta, beczka): ogień, dym, odłamki, błysk światła i fala.
## `radius` w px; wszystko w skali do promienia, więc jeden efekt obsługuje każdy rozmiar.
static func explosion(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var k := clampf(radius / 64.0, 0.4, 2.0)
	Audio.play_variant_at("explosion", 2, pos, Audio.BUS_WORLD, 2.0, 1.0 / maxf(k * 0.5 + 0.55, 0.7))
	burst(parent, pos, Color(1.0, 0.6, 0.2), int(30.0 * k), 60.0, 220.0 * k, Vector2.UP, 180.0, 200.0, 0.5, Vector2(1.5, 3.0), true)
	burst(parent, pos, Color(0.25, 0.24, 0.24, 0.6), int(14.0 * k), 20.0, 60.0 * k, Vector2.UP, 70.0, -40.0, 1.6, Vector2(3.0, 5.0))
	for i in int(6.0 * k):
		debris(parent, pos, Vector2(randf_range(-160, 160), randf_range(-260, -90)) * k, Vector2(3, 2),
			Color(0.55, 0.14, 0.1).darkened(randf() * 0.4), 0.3, 14.0)
	shock(parent, pos, radius)
	var flash := Lights.make_light(Lights.radial(), 7.0 * k, Color(1.0, 0.65, 0.3), 2.2, true)
	parent.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "energy", 0.0, 0.45)
	tw.tween_callback(flash.queue_free)
	for p in parent.get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			var d: float = p.global_position.distance_to(pos)
			if d < 300.0:
				Feel.shake(5.0 * k * (1.0 - d / 400.0))
				Feel.kick(((p.global_position - pos).normalized()) * 3.0 * k)
				Feel.hitstop(0.06)

## Płomienie na ciele (wróg, beczka) przez `seconds`: cząstki + migoczące światło.
static func burning(host: Node2D, seconds: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx := CPUParticles2D.new()
	fx.amount = 16
	fx.lifetime = 0.5
	fx.local_coords = false
	fx.direction = Vector2.UP
	fx.spread = 30.0
	fx.initial_velocity_min = 14.0
	fx.initial_velocity_max = 34.0
	fx.gravity = Vector2(0, -50)
	fx.scale_amount_min = 1.2
	fx.scale_amount_max = 2.6
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fx.emission_rect_extents = Vector2(4, 5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.5, 0.95), Color(1.0, 0.45, 0.12, 0.8), Color(0.3, 0.1, 0.05, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	fx.color_ramp = g
	fx.material = Lights.unshaded()
	fx.position = Vector2(0, -8)
	host.add_child(fx)
	var lt := Lights.make_light(Lights.radial(), 2.6, Color(1.0, 0.55, 0.22), 0.9, false)
	lt.position = Vector2(0, -8)
	host.add_child(lt)
	# czas życia przez Timer-dziecko: znika razem z wrogiem, bez lambd trzymających zwolnione węzły
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = seconds
	host.add_child(tm)
	tm.timeout.connect(_end_burning.bind(fx, lt))
	tm.start()
	var flick := Timer.new()
	flick.wait_time = 0.08
	host.add_child(flick)
	flick.timeout.connect(_flicker.bind(lt))
	flick.start()

static func _flicker(lt: PointLight2D) -> void:
	if is_instance_valid(lt):
		lt.energy = randf_range(0.6, 1.1)

static func _end_burning(fx: CPUParticles2D, lt: PointLight2D) -> void:
	if is_instance_valid(fx):
		fx.emitting = false
		fx.get_tree().create_timer(0.6).timeout.connect(fx.queue_free)
	if is_instance_valid(lt):
		lt.queue_free()

class Streak extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var color := Color.WHITE
	var width := 2.0
	var life := 0.12
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - _t / life
		# halo + rdzeń: szyna i promień mają „żarzyć się”, nie być kreską
		draw_line(a, b, Color(color.r, color.g, color.b, 0.28 * k), width * 3.0)
		draw_line(a, b, Color(color.r, color.g, color.b, 0.7 * k), width * 1.6)
		draw_line(a, b, Color(1.0, 1.0, 1.0, k), maxf(width * 0.6, 1.0))

class ShockRing extends Node2D:
	var max_r := 48.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.3:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / 0.3
		var r := max_r * (0.25 + 0.85 * (1.0 - pow(1.0 - k, 3.0)))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.85, 0.55, 0.7 * (1.0 - k)), 2.0)
