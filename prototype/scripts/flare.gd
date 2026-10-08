extends Node2D
## Flara rzucana (F, 1.7.5): światło-przynęta. Leci łukiem, ląduje, pali się FLARE_LIFE s.
##
## Odciąga ćmy (światłolubne, enemy.gd `cma`) i budzi ciekawość Trzosków (`see_light`) — wabik BEZ hałasu
## (Q kosztuje Uwagę), za to ograniczony pulą flar (NoiseMgr.flares) i widoczny z daleka. Ćma, która
## doleci do flary, spala się przy niej — flara chroni przed ćmami, jeśli rzucisz ją daleko od siebie.
## Pozycja i lot są deterministyczne z parametrów startu, więc nie trzeba jej synchronizować.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const FLARE_LIFE := 25.0
const GRAVITY := 520.0
const LURE_EVERY := 0.5
const WATER_LIFE := 8.0           ## flara, która spadła do wody (basen areny Pijawki), gaśnie po tylu s — cień trzeba oświetlać stale

var vel := Vector2.ZERO
var life := FLARE_LIFE

var _landed := false
var _light: PointLight2D
var _t := 0.0
var _lure_t := 0.0
## HD (Sprites.newitem): tuba flary (obraca się w locie, leży po lądowaniu) i nakładka z płomieniem na czubku.
const HD_SCALE := 0.5
var _pv: Node2D
var _fx: Node2D
var _spin := 0.0
var _lie := 0.0

func _ready() -> void:
	add_to_group("flares")
	z_index = 2
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), 8.0, Color(1.0, 0.42, 0.2), 1.5, true)
	add_child(_light)
	if Sprites.newitem and ItemsHd.has("flare"):
		_pv = Node2D.new()
		add_child(_pv)
		var sp := ItemsHd.make("flare", _pv, HD_SCALE, 0.3)
		sp.position = Vector2(0, ItemsHd.body_wp("flare").y * HD_SCALE * 0.5)          # środek tuby w punkcie obrotu
		_fx = Node2D.new()
		_fx.material = Lights.unshaded()
		_fx.draw.connect(_draw_fx)
		add_child(_fx)
		_spin = randf_range(-9.0, 9.0)
		_lie = (1.0 if randf() < 0.5 else -1.0) * randf_range(1.35, 1.75)
	Audio.play_at("flare_ignite", global_position, Audio.BUS_WORLD, -4.0)

## Wylądowała na kaflu wody: dopala się tylko WATER_LIFE s (dym i plusk).
func _check_water() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and lvl.has_method("surface_at") and lvl.surface_at(global_position) == "water":
		life = minf(life, WATER_LIFE)
		Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, -6.0, 1.4)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_t += delta
	if not _landed:
		vel.y += GRAVITY * delta
		var from := global_position
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 16)
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
		else:
			var n: Vector2 = hit["normal"]
			global_position = hit["position"] + n
			if n.y < -0.5:
				_landed = true
				vel = Vector2.ZERO
				_check_water()
			else:
				vel = vel.bounce(n) * 0.4
	if _pv != null:
		if _landed:
			_pv.rotation = lerp_angle(_pv.rotation, _lie, minf(1.0, delta * 14.0))
			_pv.position.y = lerpf(_pv.position.y, -1.4, minf(1.0, delta * 14.0))
		else:
			_pv.rotation += _spin * delta
			_pv.position.y = 0.0
		_fx.queue_redraw()
	# dogasanie na końcu i migotanie płomienia
	_light.energy = (1.35 + 0.35 * sin(_t * 17.0) * sin(_t * 5.1)) * minf(1.0, life / 3.0)
	if NoiseMgr.is_server():
		_lure_t -= delta
		if _lure_t <= 0.0:
			_lure_t = LURE_EVERY
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.has_method("see_light"):
					e.see_light(global_position)
	queue_redraw()

## Płomień na czubku flary: jasny rdzeń, pomarańczowa poświata i iskry unoszące się w górę.
func _draw_fx() -> void:
	var a := minf(1.0, life / 3.0)
	var tip := _pv.position + Vector2(0, -ItemsHd.body_wp("flare").y * HD_SCALE * 0.5).rotated(_pv.rotation)
	var fl := 0.85 + 0.15 * sin(_t * 23.0) * sin(_t * 7.3)
	_fx.draw_circle(tip, 4.6 * fl, Color(1.0, 0.45, 0.2, 0.16 * a))
	_fx.draw_circle(tip, 2.6 * fl, Color(1.0, 0.6, 0.25, 0.4 * a))
	_fx.draw_circle(tip, 1.3 * fl, Color(1.0, 0.95, 0.75, a))
	for i in 4:
		var ph := fposmod(_t * 1.6 + float(i) * 0.25, 1.0)
		var sp := tip + Vector2(sin(_t * 9.0 + float(i) * 2.1) * 1.8, -ph * 9.0)
		_fx.draw_circle(sp, 0.55 * (1.0 - ph), Color(1.0, 0.75, 0.4, 0.9 * (1.0 - ph) * a))

func _draw() -> void:
	if _pv != null:
		return
	var a := minf(1.0, life / 3.0)
	draw_circle(Vector2(0, -1), 2.2, Color(1.0, 0.55, 0.25, 0.35 * a))
	draw_circle(Vector2(0, -1), 1.3, Color(1.0, 0.92, 0.65, a))
