extends Node2D
## Lampa w kryjówce (znacznik „l"): wisi pod sufitem na kablu, ciepłe, lekko migoczące światło. Pozycja = punkt pod sufitem.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const LightShaft := preload("res://scripts/light_shaft.gd")

## Cienie postaci od lampy (plan ATMOSPHERE_PLAN.md, F3): włączane tylko, gdy w pobliżu ktoś stoi — MEDIUM bliżej, HIGH dalej, LOW wcale.
const SHADOW_RANGE_PX := [0.0, 190.0, 300.0]
const SHADOW_CULL_MASK := 2           ## okludery postaci leżą na warstwie 2, więc nie cieniują ich światła własne (aura, latarka)

const RADIUS_M := 9.0
const ENERGY := 0.85

var _light: PointLight2D
var _shaft: Node2D
var _glow: Node2D
var _shadow_check := 0.0
var _t := 0.0
var _hd := false

func _ready() -> void:
	add_to_group("lamps")                                 # cień kontaktowy postaci (player.gd) szuka najbliższej lampy
	z_index = 2
	_t = randf() * 20.0
	_light = Lights.make_light(Lights.radial(), RADIUS_M, Color(1.0, 0.78, 0.5), ENERGY, false)
	_light.position = Vector2(0, 11)
	_light.shadow_item_cull_mask = SHADOW_CULL_MASK
	_light.shadow_color = Color(0, 0, 0, 0.8)
	add_child(_light)
	_shaft = LightShaft.new()                             # smuga światła w powietrzu
	_shaft.position = Vector2(0, 11)
	add_child(_shaft)
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
	var f := 0.93 + 0.07 * sin(_t * 9.0) * sin(_t * 3.7)
	_light.energy = ENERGY * f
	_shaft.set_level(f)
	_glow.queue_redraw()
	_shadow_check -= delta
	if _shadow_check <= 0.0:
		_shadow_check = 0.25
		_update_shadows()

## Cienie włączone, gdy któraś postać jest w zasięgu zależnym od jakości (maks. kilka lamp naraz).
func _update_shadows() -> void:
	var rng: float = SHADOW_RANGE_PX[clampi(Settings.quality_idx, 0, 2)]
	var on := false
	if rng > 0.0:
		for p in get_tree().get_nodes_in_group("players"):
			if p is Node2D and (p as Node2D).global_position.distance_to(global_position) < rng:
				on = true
				break
	_light.shadow_enabled = on

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
