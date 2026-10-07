extends Node2D
## Skaner „Sowa” (A2): nakładka lokalnego gracza — sylwetki wrogów w promieniu skanera, także za ścianami. Rysowana unshaded,
## więc widać ją w ciemności. Zasięg i czas bierze z throwables.gd; stan (`_scan_left`) trzyma player.gd.

const Lights := preload("res://scripts/lights.gd")
const Throwables := preload("res://scripts/throwables.gd")

var player: Node2D
var _t := 0.0

func _ready() -> void:
	z_index = 5
	material = Lights.unshaded()

func _process(delta: float) -> void:
	_t += delta
	visible = player != null and float(player.scan_left) > 0.0
	if visible:
		queue_redraw()

func _draw() -> void:
	if player == null:
		return
	var r: float = float(Throwables.KINDS["scanner"]["range"])
	var c := player.global_position + Vector2(0, -9)
	var fade := clampf(float(player.scan_left) / 1.5, 0.0, 1.0)
	var pulse := fmod(_t * 0.9, 1.0)
	draw_arc(to_local(c), r * pulse, 0.0, TAU, 48, Color(0.9, 0.9, 0.5, 0.35 * (1.0 - pulse) * fade), 1.0)
	draw_arc(to_local(c), r, 0.0, TAU, 64, Color(0.9, 0.9, 0.5, 0.12 * fade), 1.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n) or not n.visible or n.is_in_group("props") or n.is_in_group("breakables"):
			continue
		if n.get("alive") == false:
			continue
		var d := n.global_position.distance_to(c)
		if d > r:
			continue
		var p := to_local(n.global_position)
		var hot: bool = n.has_method("is_threat") and bool(n.call("is_threat"))
		var col := Color(1.0, 0.35, 0.3, 0.9 * fade) if hot else Color(0.95, 0.9, 0.55, 0.75 * fade)
		var sz: Vector2 = n.get("_def")["size"] if n.get("_def") is Dictionary and (n.get("_def") as Dictionary).has("size") else Vector2(10, 14)
		draw_rect(Rect2(p.x - sz.x * 0.5, p.y - sz.y, sz.x, sz.y), Color(col.r, col.g, col.b, col.a * 0.25))
		draw_rect(Rect2(p.x - sz.x * 0.5, p.y - sz.y, sz.x, sz.y), col, false, 1.0)
		draw_circle(Vector2(p.x, p.y - sz.y - 3.0), 1.5, col)
