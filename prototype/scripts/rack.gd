extends Node2D
## Stojak na broń w kryjówce (dekoracja za przedmiotem „g"): drewniana deska z JEDNĄ kołyską, w której leży broń, i tabliczką.
## Stopy w (0, 0); broń (pickup.gd ze static_display) ma dolną krawędź 6 px nad podłogą (sprite ma jeszcze ~3 px przezroczystego marginesu, więc półka jest wyżej).

func _ready() -> void:
	z_index = 0

func _draw() -> void:
	var wood := Color(0.27, 0.19, 0.12)
	var dark := Color(0.13, 0.09, 0.06)
	var steel := Color(0.55, 0.55, 0.58)
	draw_rect(Rect2(-24, -36, 48, 36), dark)                    # rama
	draw_rect(Rect2(-22, -34, 44, 32), wood)                    # deska
	draw_rect(Rect2(-22, -34, 44, 2), Color(0.42, 0.3, 0.19))
	# jedna kołyska pod bronią: półka z dwoma bocznymi wargami
	draw_rect(Rect2(-10, -9, 20, 2), steel)
	draw_rect(Rect2(-10, -12, 2, 3), steel)
	draw_rect(Rect2(8, -12, 2, 3), steel)
	draw_rect(Rect2(-8, -5, 16, 2), Color(0.7, 0.62, 0.45))     # tabliczka z nazwą
