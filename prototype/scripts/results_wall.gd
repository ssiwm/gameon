extends Node2D
## Ściana wyników w kryjówce (znacznik „v"): tablica z kredowymi kreskami — jedna kreska na ukończoną misję kampanii.
## Gdy lokalny gracz stoi przy niej, HUD pokazuje listę (czas, upadki, próby, cel poboczny; run_log.gd).

const RunLog := preload("res://scripts/run_log.gd")
const REACH_X := 56.0
const REACH_Y := 40.0

var local_in_range := false
var _count := -1

func _ready() -> void:
	add_to_group("results_wall")
	z_index = 0

func _physics_process(_delta: float) -> void:
	local_in_range = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			local_in_range = absf(p.global_position.x - global_position.x) <= REACH_X and absf(p.global_position.y - global_position.y) <= REACH_Y
			break
	if _count != RunLog.entries.size():
		_count = RunLog.entries.size()
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-34, -42, 68, 38), Color(0.14, 0.1, 0.07))                 # drewniana rama
	draw_rect(Rect2(-32, -40, 64, 34), Color(0.1, 0.13, 0.12))                 # zielona tablica
	draw_rect(Rect2(-32, -40, 64, 1), Color(0.2, 0.25, 0.22))
	draw_rect(Rect2(-34, -4, 68, 2), Color(0.3, 0.22, 0.14))                   # półka na kredę
	draw_rect(Rect2(-12, -6, 6, 2), Color(0.85, 0.84, 0.78))                   # kreda
	var chalk := Color(0.84, 0.85, 0.8)
	# nagłówek: trzy kreski „napisu"
	draw_rect(Rect2(-20, -36, 40, 1), Color(chalk, 0.5))
	draw_rect(Rect2(-14, -33, 28, 1), Color(chalk, 0.3))
	# tally: grupy po pięć kresek (cztery pionowe + przekreślenie)
	var n := RunLog.entries.size()
	for i in n:
		var g := i / 5
		var k := i % 5
		var x := -26.0 + float(g) * 14.0 + float(k) * 2.5
		if k < 4:
			draw_line(Vector2(x, -28), Vector2(x, -18), chalk, 1.0)
		else:
			draw_line(Vector2(x - 11.0, -17), Vector2(x + 1.0, -29), chalk, 1.0)
	if n == 0:
		for i in 3:
			draw_rect(Rect2(-22 + i * 16, -24, 10, 1), Color(chalk, 0.18))
	# pozostałe tło: ślady po wytartej kredzie
	draw_rect(Rect2(-24, -13, 22, 1), Color(chalk, 0.12))
	draw_rect(Rect2(4, -12, 18, 1), Color(chalk, 0.12))
	draw_rect(Rect2(-2, -6, 4, 2), Color(0.14, 0.1, 0.07))
