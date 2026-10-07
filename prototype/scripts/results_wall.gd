extends Node2D
## Ściana wyników w kryjówce (znacznik „v"): zielona tablica, na której kredą wypisane są ostatnie ukończone misje kampanii —
## numer, czas, upadki, złom — i kreski za wszystkie (grupy po pięć). Cała treść jest rysowana na obiekcie świata, bez karty w HUD-zie
## (dane: run_log.gd, każdy peer zapisuje je sam). Gdy lokalny gracz stoi przy tablicy, kreda jaśnieje.

const UiTheme := preload("res://scripts/ui_theme.gd")
const RunLog := preload("res://scripts/run_log.gd")
const REACH_X := 70.0
const REACH_Y := 40.0
const ROWS := 4                       ## tyle ostatnich misji mieści tablica
const FONT := 8

const CHALK := Color(0.86, 0.87, 0.82)
const CHALK_GOLD := Color(0.93, 0.82, 0.5)
const CHALK_RED := Color(0.9, 0.5, 0.42)

var local_in_range := false
var _count := -1
var _was_near := false

func _ready() -> void:
	add_to_group("results_wall")
	z_index = 0

func _physics_process(_delta: float) -> void:
	local_in_range = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			local_in_range = absf(p.global_position.x - global_position.x) <= REACH_X and absf(p.global_position.y - global_position.y) <= REACH_Y
			break
	if _count != RunLog.entries.size() or _was_near != local_in_range:
		_count = RunLog.entries.size()
		_was_near = local_in_range
		queue_redraw()

## Numer misji z tytułu mapy („1.2  RADIO SILENCE" → „1.2").
func _short_id(title: String) -> String:
	return title.split(" ", false)[0] if title != "" else "?"

func _draw() -> void:
	var font := UiTheme.heading_font()
	var a := 1.0 if local_in_range else 0.8
	# drewniana rama, zielona tablica i półka na kredę
	draw_rect(Rect2(-58, -66, 116, 66), Color(0.14, 0.1, 0.07))
	draw_rect(Rect2(-56, -64, 112, 58), Color(0.1, 0.13, 0.12))
	draw_rect(Rect2(-56, -64, 112, 1), Color(0.2, 0.25, 0.22))
	draw_rect(Rect2(-58, -6, 116, 3), Color(0.3, 0.22, 0.14))
	draw_rect(Rect2(-6, -8, 8, 2), Color(CHALK, 0.9))                         # kawałek kredy na półce
	draw_rect(Rect2(14, -8, 4, 2), Color(CHALK_GOLD, 0.7))
	# ślady po wytartej kredzie
	draw_rect(Rect2(-46, -22, 30, 1), Color(CHALK, 0.07))
	draw_rect(Rect2(8, -26, 36, 1), Color(CHALK, 0.06))
	if font == null:
		return
	var es: Array = RunLog.entries
	draw_string(font, Vector2(-50, -54), "RESULTS", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color(CHALK, a))
	draw_string(font, Vector2(50 - 30, -54), "%d" % es.size(), HORIZONTAL_ALIGNMENT_RIGHT, 30, FONT, Color(CHALK, 0.6 * a))
	draw_line(Vector2(-50, -50), Vector2(50, -50), Color(CHALK, 0.4 * a), 1.0)
	if es.is_empty():
		draw_string(font, Vector2(-50, -34), "NO MISSIONS YET", HORIZONTAL_ALIGNMENT_CENTER, 100, FONT, Color(CHALK, 0.35 * a))
		draw_string(font, Vector2(-50, -24), "FINISH ONE", HORIZONTAL_ALIGNMENT_CENTER, 100, FONT, Color(CHALK, 0.25 * a))
	else:
		var shown := 0
		for i in range(es.size() - 1, -1, -1):
			if shown >= ROWS:
				break
			var e: Dictionary = es[i]
			var y := -40.0 + float(shown) * 10.0
			draw_string(font, Vector2(-50, y), _short_id(String(e["title"])), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color(CHALK, a))
			draw_string(font, Vector2(-26, y), RunLog.fmt_time(float(e["time"])), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color(CHALK, 0.85 * a))
			var downs := int(e["downs"])
			draw_string(font, Vector2(4, y), "D%d" % downs, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color(CHALK_RED if downs > 0 else CHALK, (1.0 if downs > 0 else 0.6) * a))
			draw_string(font, Vector2(50 - 36, y), "+%d" % int(e.get("scrap", 0)), HORIZONTAL_ALIGNMENT_RIGHT, 36, FONT, Color(CHALK_GOLD, a))
			shown += 1
	# kreski za wszystkie ukończone misje (grupy po pięć: cztery pionowe i przekreślenie) i łączny czas
	for i in es.size():
		var g := i / 5
		var k := i % 5
		var x := -50.0 + float(g) * 14.0 + float(k) * 2.5
		if k < 4:
			draw_line(Vector2(x, -17), Vector2(x, -9), Color(CHALK, 0.85 * a), 1.0)
		else:
			draw_line(Vector2(x - 11.0, -9), Vector2(x + 1.0, -17), Color(CHALK, 0.85 * a), 1.0)
	if not es.is_empty():
		draw_string(font, Vector2(50 - 40, -9), RunLog.fmt_time(RunLog.total_time()), HORIZONTAL_ALIGNMENT_RIGHT, 40, FONT, Color(CHALK, 0.6 * a))
