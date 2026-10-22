extends Node2D
## Stół konserwacji w kryjówce (znacznik „j", WORKSHOP_PLAN.md stanowisko 2, od 1.7.350): stół z taboretem obok ławy warsztatu. Gdy lokalny
## gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „service" (workshop_ui.gd) — czyszczenie broni
## (rozłożonej na ławie 3D) i wymiana części eksploatacyjnych: lufy i sprężyn (Profile.WEAR_PARTS, Scrap.SERVICE_COST).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 18.0                   ## węższy niż ława (44 px) — stoją 4 kafle od siebie i zasięgi nie mogą się nakładać
const REACH_Y := 40.0
const TILE := 16.0
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół rusznikarza z rozłożonym karabinem i szafka na drobne
## części, Poly Haven CC0 — taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Na lewo od znacznika wisi tablica wyników, na prawo (od ok. 42 px) stoi ława: stół i szafka mieszczą się między nimi, stół tuż na
## prawo od znacznika (gracz przy [E] go nie zasłania). Bez modeli: stół i taboret z przedmiotów HD.
const MODELS := [["clean_bench", 15.0, -1.0], ["parts_cabinet", 33.0, -1.2], ["stool_metal", 7.0, -0.45]]
const MODEL_CHECK := "res://art/items3d/clean_bench.glb"

var station_props: Array = []

var local_in_range := false

func _ready() -> void:
	add_to_group("service_bench")
	z_index = 0
	if ResourceLoader.exists(MODEL_CHECK):
		station_props = MODELS                                # modele 3D (view3d) zamiast przedmiotów HD
		add_to_group("station_props")
	elif Sprites.newitem and ItemsHd.has("table"):
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
