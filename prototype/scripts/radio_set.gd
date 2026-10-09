extends Node2D
## Radiostacja w kryjówce (znacznik „R", GDD §10.3): nasłuch prognozy pogody na następną misję kampanii (weather.gd).
## Gdy lokalny gracz stoi przy niej, HUD pokazuje kartę prognozy (jak odprawa przy tablicy). Sama radiostacja tylko się rysuje
## (skrzynka z głośnikiem, tarczą i anteną; zielona dioda i tarcza świecą w ciemności) i mówi HUD, czy ktoś stoi blisko.

const REACH_X := 48.0
const REACH_Y := 40.0

var local_in_range := false
var _t := 0.0

func _ready() -> void:
	add_to_group("radio_set")
	z_index = 0

func _physics_process(_delta: float) -> void:
	local_in_range = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			local_in_range = absf(p.global_position.x - global_position.x) <= REACH_X and absf(p.global_position.y - global_position.y) <= REACH_Y
			break

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var casing := Color(0.2, 0.22, 0.17)
	var edge := Color(0.1, 0.11, 0.08)
	draw_rect(Rect2(-14, -18, 28, 18), edge)                                 # obudowa
	draw_rect(Rect2(-13, -17, 26, 16), casing)
	draw_rect(Rect2(-13, -17, 26, 2), Color(0.3, 0.33, 0.25))                # światło z góry
	# głośnik (kratka)
	draw_rect(Rect2(-11, -14, 10, 10), Color(0.12, 0.13, 0.1))
	for i in 4:
		draw_rect(Rect2(-10, -13 + i * 2.5, 8, 1), Color(0.26, 0.28, 0.22))
	# tarcza strojenia — zielone podświetlenie, wskazówka kołysze się jak szukająca częstotliwości
	draw_rect(Rect2(1, -14, 11, 6), Color(0.05, 0.12, 0.07))
	draw_rect(Rect2(2, -13, 9, 4), Color(0.18, 0.5, 0.28, 0.85))
	var nx := 2.0 + 4.5 + sin(_t * 0.9) * 3.4
	draw_rect(Rect2(nx, -13, 1, 4), Color(0.85, 1.0, 0.7))
	# gałki i dioda (miga jak sygnał)
	draw_circle(Vector2(4, -5), 2.0, Color(0.1, 0.1, 0.08))
	draw_circle(Vector2(9, -5), 2.0, Color(0.1, 0.1, 0.08))
	var blink := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(Vector2(-11, -6), 1.2, Color(0.35 + 0.6 * blink, 0.1, 0.08))
	# antena
	draw_line(Vector2(9, -18), Vector2(15, -34), Color(0.55, 0.57, 0.52), 1.0)
	draw_circle(Vector2(15, -34), 1.0, Color(0.7, 0.2, 0.15))
	# nóżki
	draw_rect(Rect2(-12, -1, 3, 1), edge)
	draw_rect(Rect2(9, -1, 3, 1), edge)
