extends Node2D
## Tablica z odprawą w kryjówce (znacznik „n"). Gdy lokalny gracz stoi przy niej, HUD pokazuje odprawę następnej misji
## (tytuł, cel, zagrożenia policzone ze znaczników mapy). Sama tablica tylko się rysuje i mówi HUD, czy ktoś stoi blisko.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 56.0
const REACH_Y := 40.0

var local_in_range := false
var _hd := false

func _ready() -> void:
	add_to_group("board")
	z_index = 0
	if Sprites.newitem and ItemsHd.has("board"):
		_hd = true                                     # HD: korek w drewnianej ramie, kartki z pinezkami i czerwony sznurek
		ItemsHd.make("board", self)

func _physics_process(_delta: float) -> void:
	local_in_range = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			local_in_range = absf(p.global_position.x - global_position.x) <= REACH_X and absf(p.global_position.y - global_position.y) <= REACH_Y
			break

func _draw() -> void:
	if _hd:
		return
	draw_rect(Rect2(-30, -40, 60, 34), Color(0.14, 0.1, 0.07))               # rama
	draw_rect(Rect2(-28, -38, 56, 30), Color(0.5, 0.36, 0.22))               # korek
	draw_rect(Rect2(-28, -38, 56, 2), Color(0.62, 0.46, 0.29))
	var papers := [[-22.0, -34.0, 13.0, 16.0], [-6.0, -35.0, 12.0, 14.0], [8.0, -33.0, 14.0, 17.0], [-14.0, -20.0, 18.0, 9.0]]
	for p in papers:
		draw_rect(Rect2(p[0], p[1], p[2], p[3]), Color(0.86, 0.84, 0.75))
		draw_rect(Rect2(p[0] + 1.5, p[1] + 3.0, p[2] - 3.0, 1.0), Color(0.35, 0.35, 0.38))
		draw_rect(Rect2(p[0] + 1.5, p[1] + 6.0, p[2] - 5.0, 1.0), Color(0.35, 0.35, 0.38))
		draw_circle(Vector2(p[0] + p[2] * 0.5, p[1] + 1.5), 1.2, Color(0.8, 0.15, 0.12))
	draw_rect(Rect2(-2, -6, 4, 6), Color(0.14, 0.1, 0.07))                   # nóżka
