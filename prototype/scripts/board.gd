extends Node2D
## Tablica z odprawą w kryjówce (znacznik „n"). Gdy lokalny gracz stoi przy niej, HUD pokazuje odprawę następnej misji
## (tytuł, cel, zagrożenia policzone ze znaczników mapy). [Interakcja] przy tablicy przełącza cel wyjścia na kolejną odblokowaną misję
## kampanii (main.request_brief_cycle, rozstrzyga serwer; od 1.7.392).

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
	if local_in_range and Input.is_action_just_pressed("interact"):
		var ui := get_tree().get_first_node_in_group("workshop_ui")
		var main := get_tree().current_scene
		if (ui == null or not ui.is_open()) and main != null and main.has_method("request_brief_cycle"):
			main.request_brief_cycle()               # następna odblokowana misja kampanii jako cel wyjścia (PROGRESSION_PLAN.md P1.1)
