extends Node2D
## Prasa elaboracyjna w kryjówce (znacznik „x", WORKSHOP_PLAN.md stanowisko 3, od 1.7.354): stół z prasą i skrzynkami amunicji w magazynie
## na dole. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „press" (workshop_ui.gd) —
## zamówienia partii amunicji specjalnej (Scrap.request_order), gotowych po następnej udanej misji. Ława nie sprzedaje już amunicji.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 32.0
const REACH_Y := 40.0
const TILE := 16.0
## Wyposażenie: stół (prasa, wagi) i skrzynki z łuskami obok — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["ammo", 1.3], ["ammo", 1.9], ["crate", -1.6]]

var local_in_range := false

func _ready() -> void:
	add_to_group("press_bench")
	z_index = 0
	if Sprites.newitem:
		for pr in PROPS:
			if not ItemsHd.has(String(pr[0])):
				continue
			var h := Node2D.new()
			h.position = Vector2(float(pr[1]) * TILE, 0.0)
			add_child(h)
			ItemsHd.make(String(pr[0]), h)                   # widok 3D zamienia przedmiot HD na model z art/items3d/

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
			ui.open("press")
