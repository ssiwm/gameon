extends Node2D
## Stół konserwacji w kryjówce (znacznik „j", WORKSHOP_PLAN.md stanowisko 2, od 1.7.350): stół z taboretem obok ławy warsztatu. Gdy lokalny
## gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „service" (workshop_ui.gd) — czyszczenie broni
## (rozłożonej na ławie 3D) i wymiana części eksploatacyjnych: lufy i sprężyn (Profile.WEAR_PARTS, Scrap.SERVICE_COST).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 18.0                   ## węższy niż ława (44 px) — stoją 4 kafle od siebie i zasięgi nie mogą się nakładać
const REACH_Y := 40.0
const TILE := 16.0

var local_in_range := false

func _ready() -> void:
	add_to_group("service_bench")
	z_index = 0
	if Sprites.newitem and ItemsHd.has("table"):
		ItemsHd.make("table", self)                          # widok 3D zamienia przedmiot HD na model art/items3d/table.glb
		if ItemsHd.has("stool"):
			var st := Node2D.new()
			st.position = Vector2(1.4 * TILE, 0.0)
			add_child(st)
			ItemsHd.make("stool", st)

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
			ui.open("service")
