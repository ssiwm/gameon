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
