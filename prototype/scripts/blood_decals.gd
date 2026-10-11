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
	var v3 := parent.get_tree().current_scene.get_node_or_null("View3D") if parent.get_tree().current_scene != null else null
	if v3 != null:
		d.visible = false                                 # widok 3D: kapiąca krew zbiera się w kałuże 3D
		v3.call("mirror_blood", pos, radius * 0.6)

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
