extends Node2D
## Flara rzucana (F, 1.7.5): światło-przynęta. Leci łukiem, ląduje, pali się FLARE_LIFE s.
##
## Odciąga ćmy (światłolubne, enemy.gd `cma`) i budzi ciekawość Trzosków (`see_light`) — wabik BEZ hałasu
## (Q kosztuje Uwagę), za to ograniczony pulą flar (NoiseMgr.flares) i widoczny z daleka. Ćma, która
## doleci do flary, spala się przy niej — flara chroni przed ćmami, jeśli rzucisz ją daleko od siebie.
## Pozycja i lot są deterministyczne z parametrów startu, więc nie trzeba jej synchronizować.

const Lights := preload("res://scripts/lights.gd")

const FLARE_LIFE := 25.0
const GRAVITY := 520.0
const LURE_EVERY := 0.5

var vel := Vector2.ZERO
var life := FLARE_LIFE

var _landed := false
var _light: PointLight2D
var _t := 0.0
var _lure_t := 0.0

func _ready() -> void:
	add_to_group("flares")
	z_index = 2
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), 8.0, Color(1.0, 0.42, 0.2), 1.5, true)
	add_child(_light)
	Audio.play_at("flare_ignite", global_position, Audio.BUS_WORLD, -4.0)

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
			else:
				vel = vel.bounce(n) * 0.4
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

func _draw() -> void:
	var a := minf(1.0, life / 3.0)
	draw_circle(Vector2(0, -1), 2.2, Color(1.0, 0.55, 0.25, 0.35 * a))
	draw_circle(Vector2(0, -1), 1.3, Color(1.0, 0.92, 0.65, a))
