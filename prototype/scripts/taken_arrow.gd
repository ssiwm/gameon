extends Control
## Strzałka na krawędzi ekranu ku porwanemu graczowi (ENEMY_PLAN.md F4d, wariant A): gdy Żerca ciągnie kogoś poza kadrem, przy krawędzi
## ekranu na wysokości ofiary pulsuje czerwony szewron z ramką „P2 PORWANY · 14 s · 23 m". W kadrze strzałki nie ma — wtedy prowadzi
## smuga krwi na ziemi (view3d.gd: `_sync_drag_trails`). Czyta tylko stan replikowany gracza (`taken`, `taken_t`), więc działa na każdym peerze.
## Element interfejsu (wyjątek od zasady „tylko 3D"); rysowany w układzie HUD-u (`hud.gd` skaluje się `scale`).

const UiTheme := preload("res://scripts/ui_theme.gd")

const PX_PER_M := 16.0          ## lights.gd: 1 m projektowy = 16 px świata
const EDGE := 22.0              ## odstęp szewronu od krawędzi ekranu (px HUD-u)
const CHEV := 9.0               ## połowa wysokości szewronu (px HUD-u)

var _t := 0.0
var _marks: Array = []          ## [punkt na krawędzi, kierunek (znormalizowany), etykieta, linia z czasem i odległością]

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	var hud := get_parent() as Control
	if hud == null:
		return
	size = hud.size
	_marks.clear()
	var me = hud.get("_player")
	var ct := get_viewport().get_canvas_transform()
	var sc: Vector2 = hud.scale
	var c := size * 0.5
	var half := c - Vector2(EDGE, EDGE)
	for p in get_tree().get_nodes_in_group("players"):
		if not p.taken or p == me or p.is_queued_for_deletion():
			continue
		var s: Vector2 = (ct * (p.global_position as Vector2)) / sc
		if Rect2(Vector2.ZERO, size).grow(-EDGE).has_point(s):
			continue                                  # ofiara w kadrze: bez strzałki
		var d := s - c
		var k := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
		var who: String = p.label()
		var line := "%d s" % ceili(float(p.taken_t))
		if me != null and is_instance_valid(me):
			line += "  ·  %d m" % roundi((me.global_position as Vector2).distance_to(p.global_position) / PX_PER_M)
		_marks.append([c + d * k, d.normalized(), tr("%s TAKEN") % who, line])
	queue_redraw()

func _draw() -> void:
	if _marks.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var font_h := UiTheme.heading_font()
	var font_d := UiTheme.display_font()
	for m in _marks:
		var at: Vector2 = m[0]
		var dir: Vector2 = m[1]
		# trzy szewrony: najjaśniejszy przy krawędzi, dwa gasnące za nim (pulsują)
		for i in 3:
			var a := (1.0 - 0.32 * i) * lerpf(0.65, 1.0, pulse)
			_chevron(at - dir * (i * CHEV * 1.2), dir, Color(UiTheme.DANGER, a))
		# ramka z opisem — po stronie środka ekranu
		var w := maxf(font_h.get_string_size(String(m[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x,
			font_d.get_string_size(String(m[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x) + 12.0
		var h := 34.0
		var box_c := at - dir * (CHEV * 4.2 + w * 0.5 * absf(dir.x) + h * 0.5 * absf(dir.y))
		var r := Rect2(box_c - Vector2(w, h) * 0.5, Vector2(w, h))
		r.position = r.position.clamp(Vector2(4, 4), size - r.size - Vector2(4, 4))
		draw_rect(r, Color(UiTheme.GROUND, 0.82))
		draw_rect(r, Color(UiTheme.DANGER, 0.9), false, 1.0)
		draw_string(font_h, r.position + Vector2(6, 11), String(m[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiTheme.DANGER)
		draw_string(font_d, r.position + Vector2(6, 29), String(m[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)

## Szewron (grot strzałki) wskazujący `dir`, z czubkiem w `tip`.
func _chevron(tip: Vector2, dir: Vector2, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, tip - dir * CHEV * 1.4 + n * CHEV, tip - dir * CHEV * 1.0, tip - dir * CHEV * 1.4 - n * CHEV])
	draw_colored_polygon(pts, col)
