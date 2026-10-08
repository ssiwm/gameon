extends Node2D
## Lampa w kryjówce (znacznik „l"): wisi pod sufitem na kablu, ciepłe, lekko migoczące światło. Pozycja = punkt pod sufitem.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const RADIUS_M := 9.0
const ENERGY := 0.85

var _light: PointLight2D
var _glow: Node2D
var _t := 0.0
var _hd := false

func _ready() -> void:
	z_index = 2
	_t = randf() * 20.0
	_light = Lights.make_light(Lights.radial(), RADIUS_M, Color(1.0, 0.78, 0.5), ENERGY, false)
	_light.position = Vector2(0, 11)
	add_child(_light)
	if Sprites.newitem and ItemsHd.has("lamp"):
		# HD: sprite lampy — „stopy" sprite'a to dół klatki, więc dół ustawiamy tak, by szczyt (uchwyt kabla) wypadł w punkcie kotwicy pod sufitem
		_hd = true
		var sp := ItemsHd.make("lamp", self, 0.9)
		sp.position = Vector2(0, ItemsHd.body_wp("lamp").y * 0.9)
	_glow = Node2D.new()
	_glow.material = Lights.unshaded()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)

func _process(delta: float) -> void:
	_t += delta
	_light.energy = ENERGY * (0.93 + 0.07 * sin(_t * 9.0) * sin(_t * 3.7))
	_glow.queue_redraw()

func _draw() -> void:
	if _hd:
		return
	draw_line(Vector2(0, 0), Vector2(0, 5), Color(0.1, 0.1, 0.11), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-2, 5), Vector2(2, 5), Vector2(5, 10), Vector2(-5, 10)]), Color(0.2, 0.21, 0.2))

func _draw_glow() -> void:
	var f := 0.8 + 0.2 * sin(_t * 9.0) * sin(_t * 3.7)
	if _hd:
		_glow.draw_circle(Vector2(0, 11), 6.5, Color(1.0, 0.8, 0.5, 0.12 * f))
		return
	_glow.draw_circle(Vector2(0, 11), 1.8, Color(1.0, 0.92, 0.65, f))
	_glow.draw_circle(Vector2(0, 11), 5.5, Color(1.0, 0.8, 0.5, 0.14 * f))
