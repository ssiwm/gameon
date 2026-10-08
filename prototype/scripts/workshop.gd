extends Node2D
## Warsztat w kryjówce (znacznik „h"): ława z imadłem, kowadłem i skrzynką na złom. Gdy lokalny gracz stoi przy niej,
## HUD podpowiada [E]; naciśnięcie otwiera panel zakupów (workshop_ui.gd) — odblokowanie broni ze stojaków za złom.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 44.0
const REACH_Y := 40.0

var local_in_range := false
var _hd := false

func _ready() -> void:
	add_to_group("workshop")
	z_index = 0
	if Sprites.newitem and ItemsHd.has("workshop"):
		# HD: ława z imadłem, kowadłem i skrzynką na złom (Tripo) oraz narzędzia na ścianie nad nią (młotek, klucz, piła, lampka)
		_hd = true
		if ItemsHd.has("tools_wall"):
			var tw := ItemsHd.make("tools_wall", self, 0.8)
			tw.position = Vector2(4.4 * 0.8, -26.0)
		ItemsHd.make("workshop", self)

func _physics_process(_delta: float) -> void:
	local_in_range = false
	var me: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			me = p
			break
	if me == null:
		return
	local_in_range = absf(me.global_position.x - global_position.x) <= REACH_X and absf(me.global_position.y - global_position.y) <= REACH_Y
	if local_in_range and Input.is_action_just_pressed("interact"):
		var ui := get_tree().get_first_node_in_group("workshop_ui")
		if ui != null and not ui.is_open():
			ui.open()

func _draw() -> void:
	if _hd:
		return
	var wood := Color(0.34, 0.24, 0.15)
	var wood_hi := Color(0.5, 0.37, 0.23)
	var dark := Color(0.13, 0.1, 0.07)
	var steel := Color(0.46, 0.48, 0.53)
	var steel_dk := Color(0.24, 0.25, 0.29)
	# ława: blat na dwóch kozłach
	draw_rect(Rect2(-24, -14, 48, 4), wood)
	draw_rect(Rect2(-24, -14, 48, 1), wood_hi)
	draw_rect(Rect2(-22, -10, 4, 10), dark)
	draw_rect(Rect2(18, -10, 4, 10), dark)
	draw_rect(Rect2(-22, -4, 44, 2), dark)
	# imadło po lewej
	draw_rect(Rect2(-20, -22, 8, 8), steel_dk)
	draw_rect(Rect2(-20, -22, 8, 2), steel)
	draw_rect(Rect2(-12, -20, 3, 3), steel)
	draw_line(Vector2(-9, -19), Vector2(-5, -19), steel, 1.0)
	# kowadło na środku
	draw_rect(Rect2(-5, -19, 14, 3), steel)
	draw_rect(Rect2(-3, -16, 10, 2), steel_dk)
	draw_rect(Rect2(-8, -19, 4, 2), steel)
	# skrzynka na złom po prawej
	draw_rect(Rect2(12, -22, 10, 8), Color(0.22, 0.24, 0.17))
	draw_rect(Rect2(12, -22, 10, 1), Color(0.4, 0.43, 0.3))
	draw_rect(Rect2(14, -25, 3, 3), steel)
	draw_rect(Rect2(18, -24, 3, 2), Color(0.5, 0.33, 0.2))
	# narzędzia na ścianie nad ławą: młotek, klucz, piła
	draw_rect(Rect2(-17, -40, 1, 11), wood_hi)
	draw_rect(Rect2(-20, -42, 7, 3), steel)
	draw_line(Vector2(-5, -42), Vector2(-5, -29), steel, 1.0)
	draw_circle(Vector2(-5, -43), 2.0, steel)
	draw_rect(Rect2(4, -40, 14, 4), steel_dk)
	for i in 5:
		draw_rect(Rect2(5 + i * 3, -36, 1, 1), steel_dk)
	# lampka robocza
	draw_rect(Rect2(21, -33, 2, 12), dark)
	draw_rect(Rect2(18, -35, 8, 3), Color(0.8, 0.62, 0.25))
