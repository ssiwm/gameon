extends Node2D
## Strzelnica w kryjówce (znacznik „r"): dwa znaczniki na podłodze, z których się strzela do JEDNEJ tarczy (range_target.gd, znacznik „t") —
## 5 i 10 m od niej (odległość mierzona od tarczy, nie od znacznika „r") — oraz tablica „RANGE" przy najdalszym znaczniku.
## Znacznik, na którym stoi gracz, rozbłyska; odległość na żywo pokazuje też tabliczka pod tarczą. Pozwala sprawdzić spadek obrażeń z dystansu.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Vfx := preload("res://scripts/vfx.gd")

const DISTANCES_M := [5, 10]
const STAND_TOLERANCE := 10.0        ## px: tyle od środka znacznika uznajemy za „stoisz na nim"
const AMBER := Color(0.9, 0.7, 0.2)

var _marks: Array = []               ## [{x (lokalnie), m}] od najbliższego tarczy
var _hd := false
var _ov: Node2D
var _active := {}                    ## m -> czy ktoś na nim stoi

func _ready() -> void:
	add_to_group("range_line")
	z_index = 0
	_ov = Node2D.new()
	_ov.draw.connect(func() -> void: _draw_labels(_ov))
	add_child(_ov)
	call_deferred("_setup")

func _setup() -> void:
	if not is_inside_tree():
		return
	var target := get_tree().get_first_node_in_group("range_targets") as Node2D
	if target == null:
		return
	_marks.clear()
	for m: int in DISTANCES_M:
		_marks.append({"x": target.global_position.x - float(m) * 16.0 - global_position.x, "m": m})
	var far: float = _marks[_marks.size() - 1]["x"]
	if Sprites.newitem and ItemsHd.has("range_sign"):
		_hd = true
		var sp := ItemsHd.make("range_sign", self)
		sp.position = Vector2(far, 0)
		move_child(_ov, get_child_count() - 1)              # napisy nad sprite'em tablicy
	queue_redraw()
	_ov.queue_redraw()

func _physics_process(_delta: float) -> void:
	var changed := false
	for mk in _marks:
		var on := false
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and absf(p.global_position.x - (global_position.x + float(mk["x"]))) <= STAND_TOLERANCE and absf(p.global_position.y - global_position.y) < 24.0:
				on = true
				break
		if bool(_active.get(mk["m"], false)) != on:
			_active[mk["m"]] = on
			changed = true
	if changed:
		queue_redraw()
		_ov.queue_redraw()

func _draw() -> void:
	for mk in _marks:
		var on := bool(_active.get(mk["m"], false))
		var x: float = mk["x"]
		var c := Color(AMBER, 0.95 if on else 0.6)
		draw_line(Vector2(x - 9.0, -0.6), Vector2(x + 9.0, -0.6), Color(c, 0.2 if on else 0.1), 3.6, true)
		draw_line(Vector2(x - 9.0, -0.6), Vector2(x + 9.0, -0.6), c, 1.4, true)
		for sx in [-1.0, 1.0]:
			draw_line(Vector2(x + sx * 9.0, -0.6), Vector2(x + sx * 9.0, -4.0), c, 1.2, true)         # krawędzie „pola" do stania
		draw_line(Vector2(x - 6.0, -0.6), Vector2(x - 3.0, -2.6), Color(0.08, 0.08, 0.08, 0.7), 1.0, true)
		draw_line(Vector2(x + 3.0, -2.6), Vector2(x + 6.0, -0.6), Color(0.08, 0.08, 0.08, 0.7), 1.0, true)
	if _hd:
		return
	# klasyczna tablica na słupku za najdalszym znacznikiem
	if _marks.is_empty():
		return
	var f := ThemeDB.fallback_font
	var sx0: float = float(_marks[_marks.size() - 1]["x"])
	draw_rect(Rect2(sx0 - 1, -26, 2, 25), Color(0.14, 0.1, 0.07))
	draw_rect(Rect2(sx0 - 17, -34, 34, 11), Color(0.14, 0.1, 0.07))
	draw_rect(Rect2(sx0 - 16, -33, 32, 9), Color(0.1, 0.12, 0.11))
	draw_string(f, Vector2(sx0 - 16, -26), "RANGE", HORIZONTAL_ALIGNMENT_CENTER, 32.0, 7, Color(0.95, 0.75, 0.3))

## Napisy nad sprite'em tablicy i tabliczki z odległością przy każdym znaczniku.
func _draw_labels(ci: CanvasItem) -> void:
	var f := ThemeDB.fallback_font
	if _marks.is_empty():
		return
	if _hd:
		var sx0: float = float(_marks[_marks.size() - 1]["x"])
		ci.draw_string(f, Vector2(sx0 - 16, -26), "RANGE", HORIZONTAL_ALIGNMENT_CENTER, 32.0, 7, Color(0.95, 0.75, 0.3))
	for mk in _marks:
		var on := bool(_active.get(mk["m"], false))
		var x: float = mk["x"]
		var txt := "%d m" % int(mk["m"])
		var back := Color(0.04, 0.04, 0.05, 0.85)
		if _hd:
			Vfx.draw_bar(ci, Rect2(x - 10.0, -13.0, 20.0, 8.0), 1.0, back, back)
		else:
			ci.draw_rect(Rect2(x - 10.0, -13.0, 20.0, 8.0), back)
		ci.draw_string(f, Vector2(x - 10.0, -6.6), txt, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 7, Color(1.0, 0.85, 0.4) if on else Color(0.8, 0.62, 0.26))
