extends Node2D
## Stół pirotechniczny w kryjówce (znacznik „z", WORKSHOP_PLAN.md stanowisko 4, od 1.7.355): stół między skrzyniami na dole, przy wojskowej
## skrzyni. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „pyro" (workshop_ui.gd) —
## granaty, miny, ładunki i naboje 40 mm oraz wybór długości zapalnika dla drużyny (Scrap.request_fuse). Ława zostawia sobie narzędzia.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Interact := preload("res://scripts/interact.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")

const REACH_X := 32.0
const REACH_Y := 40.0
const TILE := 16.0
## Wyposażenie: stół z zapalnikami, skrzynki z korpusami granatów — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["crate", 1.5], ["crate", -1.5]]       ## zapas, gdy brak modeli 3D stanowiska
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół pirotechniczny z osłoną i szafa na materiały wybuchowe,
## Poly Haven CC0 — gaśnica i taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Wojskowa skrzynia magazynu stoi 16 px na lewo od znacznika, beczka 32 px na prawo (HUB_PROPS): stół między znacznikiem a beczką (gracz
## przy [E] go nie zasłania), szafa pod ścianą za skrzynią — dalej w lewo stoi już filar.
const MODELS := [["pyro_bench", 12.0, -1.0], ["expl_locker", -26.0, -1.35], ["pyro_ext", 24.0, -0.9], ["stool_metal", 8.0, -0.45]]
const MODEL_CHECK := "res://art/items3d/pyro_bench.glb"

var station_props: Array = []

var local_in_range := false

func _ready() -> void:
	add_to_group("pyro_bench")
	add_to_group(Interact.GROUP)
	z_index = 0
	if ResourceLoader.exists(MODEL_CHECK):
		station_props = MODELS                                # modele 3D (view3d) zamiast przedmiotów HD
		add_to_group("station_props")
	elif Sprites.newitem:
		for pr in PROPS:
			if not ItemsHd.has(String(pr[0])):
				continue
			var h := Node2D.new()
			h.position = Vector2(float(pr[1]) * TILE, 0.0)
			add_child(h)
			ItemsHd.make(String(pr[0]), h)                   # widok 3D zamienia przedmiot HD na model z art/items3d/

## Podpowiedź paska akcji, gdy stół pirotechniczny jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Pyrotechnics  ·  grenades, mines, fuses") % Actions.key("interact"), "col": UiTheme.ACCENT}

## Oferta [E] (interact.gd): stanowisko otwiera kartę, gdy gracz stoi w zasięgu, a panel stanowisk jest zamknięty. Ustępuje broni,
## ratowaniu i pracom w misji (priorytet P_STATION).
func interact_offer(me: Node2D) -> Dictionary:
	if me.dead or absf(me.global_position.x - global_position.x) > REACH_X or absf(me.global_position.y - global_position.y) > REACH_Y:
		return {}
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	if ui != null and ui.is_open():
		return {}
	return Interact.offer(self, me, Interact.Kind.PRESS, Interact.P_STATION, true, Rect2(global_position + Vector2(-18.0, -24.0), Vector2(36.0, 24.0)))

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
			ui.open("pyro")
