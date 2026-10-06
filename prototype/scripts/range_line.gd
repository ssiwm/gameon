extends Node2D
## Linia strzału strzelnicy w kryjówce (znacznik „r"): pasek na podłodze i tablica „RANGE". Od niej tarcze liczą odległość.

func _ready() -> void:
	add_to_group("range_line")
	z_index = 0

func _draw() -> void:
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(-1, -1, 2, 1), Color(0.9, 0.7, 0.2))
	for i in 4:
		draw_rect(Rect2(-1 + float(i) * 0.0, -1 - float(i) * 0.0, 2, 1), Color(0.9, 0.7, 0.2))
	draw_rect(Rect2(-20, -1, 40, 1), Color(0.85, 0.65, 0.18, 0.55))              # pasek przy podłodze
	for i in 5:
		draw_rect(Rect2(-18 + i * 9, -1, 4, 1), Color(0.08, 0.08, 0.08, 0.7))      # pasy ostrzegawcze
	# tablica
	draw_rect(Rect2(-1, -26, 2, 25), Color(0.14, 0.1, 0.07))
	draw_rect(Rect2(-17, -34, 34, 11), Color(0.14, 0.1, 0.07))
	draw_rect(Rect2(-16, -33, 32, 9), Color(0.1, 0.12, 0.11))
	draw_string(f, Vector2(-16, -26), "RANGE", HORIZONTAL_ALIGNMENT_CENTER, 32.0, 7, Color(0.95, 0.75, 0.3))
