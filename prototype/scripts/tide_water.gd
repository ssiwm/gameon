extends Node2D
## Woda fali przypływu (leech.gd, fazy 2–3): półprzezroczysta tafla nad dnem basenu, rosnąca do SURGE_H, z falującą krawędzią i pianą.
## Stoi w świecie (nie rusza się z Pijawką), rysuje poziom z leech.surge_level(); u wszystkich peerów, unshaded (widać w ciemności).

const Lights := preload("res://scripts/lights.gd")

var leech: Node2D
var _t := 0.0

func _ready() -> void:
	z_index = 4
	material = Lights.unshaded()

func _process(delta: float) -> void:
	_t += delta
	if leech == null or not is_instance_valid(leech):
		return
	visible = leech.surge_state != "idle"
	if visible:
		queue_redraw()

func _draw() -> void:
	if leech == null or not is_instance_valid(leech):
		return
	var lvl: float = leech.surge_level()
	if lvl <= 0.01:
		return
	var h: float = lvl * float(leech.SURGE_H)
	var x0: float = leech.pool_x0 - float(leech.SURGE_PAD)
	var x1: float = leech.pool_x1 + float(leech.SURGE_PAD)
	var y: float = leech.surf_y
	var warn: bool = leech.surge_state == "warn"
	var top_col := Color(0.32, 0.78, 0.88, 0.16 if warn else 0.42)           # jaśniej przy powierzchni, głębiej ciemniej — woda ma być widoczna w ciemności
	var bot_col := Color(0.12, 0.45, 0.58, 0.07 if warn else 0.20)
	var step := 16.0
	var xs := PackedVector2Array()
	var x := x0
	while x <= x1 + 0.1:
		var edge := clampf(minf(x - x0, x1 - x) / 40.0, 0.0, 1.0)             # miękkie brzegi strefy
		var wave := sin(x * 0.07 + _t * 3.2) * 1.6 + sin(x * 0.13 - _t * 2.1) * 1.0
		xs.append(Vector2(x, minf(y - h * edge + wave, y - 0.5)))
		x += step
	for i in xs.size() - 1:                                       # pasy 4-wierzchołkowe: gradient i brak degeneracji przy brzegach strefy
		var a: Vector2 = xs[i]
		var b: Vector2 = xs[i + 1]
		draw_polygon(PackedVector2Array([a, b, Vector2(b.x, y), Vector2(a.x, y)]), PackedColorArray([top_col, top_col, bot_col, bot_col]))
	draw_polyline(xs, Color(0.7, 0.95, 1.0, 0.35 if warn else 0.75), 1.5)
	# piana i kropelki przy powierzchni
	if not warn:
		for i in 30:
			var fx := x0 + fmod(float(i) * 97.3 + _t * 18.0, x1 - x0)
			var fy := y - h + sin(fx * 0.07 + _t * 3.2) * 1.6 - 1.0
			draw_rect(Rect2(fx, fy, 2, 1), Color(0.9, 1.0, 1.0, 0.7))
