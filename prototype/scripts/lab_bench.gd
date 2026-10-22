extends Node2D
## Pracownia elektroniki i próbek w kryjówce (znacznik „c", WORKSHOP_PLAN.md stanowisko 5, od 1.7.357): stół z aparaturą na górze, pod
## radiostacją. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „lab" (workshop_ui.gd) —
## badania części broni specjalnych za próbki z elit i bossów (Scrap.request_research), gotowe po następnej udanej misji.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 32.0
const REACH_Y := 40.0
const TILE := 16.0
## Wyposażenie: stół z aparaturą, regał z częściami, skaner na stole — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["shelf", 1.6], ["scanner", -0.2]]

var local_in_range := false

func _ready() -> void:
	add_to_group("lab_bench")
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
			ui.open("lab")
