extends Node2D
## Szafki osobiste w kryjówce (znacznik „p", WORKSHOP_PLAN.md stanowisko 7, od 1.7.349): rząd metalowych szafek w świetlicy. Gdy lokalny gracz
## stoi przy nich, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „locker" (workshop_ui.gd) — perki i wygląd postaci,
## które wcześniej siedziały w zakładkach ławy. Ława zajmuje się już tylko bronią i zaopatrzeniem.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 40.0
const REACH_Y := 40.0
const LOCKERS := [-1.0, 0.0, 1.0]       ## szafki w rzędzie: przesunięcie w kaflach od znacznika (po jednej na gracza drużyny… i jedna zapasowa)
const TILE := 16.0

var local_in_range := false

func _ready() -> void:
	add_to_group("locker_station")
	z_index = 0
	if Sprites.newitem and ItemsHd.has("locker"):
		for dx in LOCKERS:
			var holder := Node2D.new()
			holder.position = Vector2(float(dx) * TILE * 0.9, 0.0)
			add_child(holder)
			ItemsHd.make("locker", holder)                     # widok 3D zamienia przedmiot HD na model art/items3d/locker.glb

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
			ui.open("locker")
