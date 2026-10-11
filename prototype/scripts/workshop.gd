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
