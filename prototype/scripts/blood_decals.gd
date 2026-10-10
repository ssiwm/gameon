extends Node2D
## Plamy krwi na podłodze (kapanie rannych graczy): spłaszczone elipsy w świecie, oświetlane jak reszta sceny. Kosmetyka, lokalna;
## limit sztuk i płynne blaknięcie po MAX_AGE — żeby nie rosła lista i nie zaśmiecać poziomu. Poziom jakości HIGH.

const MAX_DECALS := 24
const MAX_AGE := 60.0
const FADE := 10.0

var _items: Array = []            ## [pozycja, promień, wiek, odchylenie koloru]

## Dodaje plamę w `pos` (świat); węzeł powstaje przy pierwszej plamie jako dziecko `parent`.
static func add(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var d := parent.get_node_or_null("BloodDecals") as Node2D
	if d == null:
		d = (load("res://scripts/blood_decals.gd") as GDScript).new()
		d.name = "BloodDecals"
		parent.add_child(d)
	d.call("_push", pos, radius)

func _push(pos: Vector2, radius: float) -> void:
	_items.append([pos, radius, 0.0, randf()])
	if _items.size() > MAX_DECALS:
		_items.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	var changed := false
	for it in _items:
		it[2] = float(it[2]) + delta
		if float(it[2]) > MAX_AGE - FADE:
			changed = true
	while not _items.is_empty() and float(_items[0][2]) >= MAX_AGE:
		_items.pop_front()
		changed = true
	if changed:
		queue_redraw()

func _draw() -> void:
	for it in _items:
		var a := 1.0 - clampf((float(it[2]) - (MAX_AGE - FADE)) / FADE, 0.0, 1.0)
		var r: float = it[1]
		var tint := float(it[3]) * 0.04
		draw_set_transform(it[0], 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, r, Color(0.16 + tint, 0.012, 0.018, 0.78 * a))
		draw_circle(Vector2(0.0, 0.0), r * 0.55, Color(0.11, 0.008, 0.012, 0.85 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
