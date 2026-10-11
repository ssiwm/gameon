extends Node2D
## Radiostacja w kryjówce (znacznik „R", GDD §10.3): nasłuch prognozy pogody na następną misję kampanii (weather.gd).
## Gdy lokalny gracz stoi przy niej, HUD pokazuje kartę prognozy (jak odprawa przy tablicy). Sama radiostacja tylko się rysuje
## (skrzynka z głośnikiem, tarczą i anteną; zielona dioda i tarcza świecą w ciemności) i mówi HUD, czy ktoś stoi blisko.

const Weather := preload("res://scripts/weather.gd")

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
