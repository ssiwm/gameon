extends Node2D
## Szafki osobiste w kryjówce (znacznik „p", WORKSHOP_PLAN.md stanowisko 7, od 1.7.349): rząd metalowych szafek w świetlicy. Gdy lokalny gracz
## stoi przy nich, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „locker" (workshop_ui.gd) — perki i wygląd postaci,
## które wcześniej siedziały w zakładkach ławy. Ława zajmuje się już tylko bronią i zaopatrzeniem.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Interact := preload("res://scripts/interact.gd")

const REACH_X := 40.0
const REACH_Y := 40.0
const LOCKERS := [-1.0, 0.0, 1.0]       ## szafki w rzędzie: przesunięcie w kaflach od znacznika (po jednej na gracza drużyny… i jedna zapasowa)
const TILE := 16.0
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — rząd trzech szafek z otwartą środkową (kurtka, hełm, zdjęcia,
## buty) i ławka szatniowa; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Szafki stoją trochę na prawo od znacznika, żeby gracz przy [E] nie zasłaniał otwartej, ławka po lewej — dalej polowe łóżko i krzesło
## świetlicy. Bez modeli: trzy szafki z przedmiotów HD (LOCKERS).
const MODELS := [["locker_row", 8.0, -1.1], ["locker_bench", -15.0, -0.6]]
const MODEL_CHECK := "res://art/items3d/locker_row.glb"

var station_props: Array = []

var local_in_range := false

func _ready() -> void:
	add_to_group("locker_station")
	add_to_group(Interact.GROUP)
	z_index = 0
	if ResourceLoader.exists(MODEL_CHECK):
		station_props = MODELS                                # modele 3D (view3d) zamiast przedmiotów HD
		add_to_group("station_props")
	elif Sprites.newitem and ItemsHd.has("locker"):
		for dx in LOCKERS:
			var holder := Node2D.new()
			holder.position = Vector2(float(dx) * TILE * 0.9, 0.0)
			add_child(holder)
			ItemsHd.make("locker", holder)                     # widok 3D zamienia przedmiot HD na model art/items3d/locker.glb

## Oferta [E] (interact.gd): stanowisko otwiera kartę, gdy gracz stoi w zasięgu, a panel stanowisk jest zamknięty. Ustępuje broni,
## ratowaniu i pracom w misji (priorytet P_STATION).
func interact_offer(me: Node2D) -> Dictionary:
	if me.dead or absf(me.global_position.x - global_position.x) > REACH_X or absf(me.global_position.y - global_position.y) > REACH_Y:
		return {}
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	if ui != null and ui.is_open():
		return {}
	return Interact.offer(self, me, Interact.Kind.PRESS, Interact.P_STATION, true, Rect2(global_position + Vector2(-16.0, -36.0), Vector2(32.0, 36.0)))

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
	if local_in_range and Interact.pressed(self):
		var ui := get_tree().get_first_node_in_group("workshop_ui")
		if ui != null and not ui.is_open():
			ui.open("locker")
