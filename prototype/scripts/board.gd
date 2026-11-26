extends Node2D
## Tablica z odprawą w kryjówce (znacznik „n"). Gdy lokalny gracz stoi przy niej, HUD pokazuje odprawę następnej misji
## (tytuł, cel, zagrożenia policzone ze znaczników mapy). [Interakcja] przy tablicy przełącza cel wyjścia na kolejną odblokowaną misję
## kampanii (main.request_brief_cycle, rozstrzyga serwer; od 1.7.392).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Interact := preload("res://scripts/interact.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")

const REACH_X := 56.0
const REACH_Y := 40.0

var local_in_range := false
var _hd := false

func _ready() -> void:
	add_to_group("board")
	add_to_group(Interact.GROUP)
	z_index = 0
	if Sprites.newitem and ItemsHd.has("board"):
		_hd = true                                     # HD: korek w drewnianej ramie, kartki z pinezkami i czerwony sznurek
		ItemsHd.make("board", self)

## Podpowiedź paska akcji, gdy tablica misji jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	# tablica oferuje [E] tylko przy ≥ 2 odblokowanych misjach (interact_offer)
	var main := get_tree().current_scene
	var opts: int = main.campaign_unlocked().size() if main != null and main.has_method("campaign_unlocked") else 0
	return {"text": tr("[%s]  Change mission  ·  %d unlocked") % [Actions.key("interact"), opts], "col": UiTheme.ACCENT}

## Oferta [E] (interact.gd): zmiana misji, gdy kampania ma więcej niż jedną odblokowaną (tak jak podpowiedź w HUD), a panel stanowisk
## jest zamknięty.
func interact_offer(me: Node2D) -> Dictionary:
	if me.dead or absf(me.global_position.x - global_position.x) > REACH_X or absf(me.global_position.y - global_position.y) > REACH_Y:
		return {}
	var main := get_tree().current_scene
	if main == null or not main.has_method("campaign_unlocked") or NightShift.active or main.campaign_unlocked().size() <= 1:
		return {}
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	if ui != null and ui.is_open():
		return {}
	return Interact.offer(self, me, Interact.Kind.PRESS, Interact.P_EXIT, true, Rect2(global_position + Vector2(-20.0, -40.0), Vector2(40.0, 26.0)))

func _physics_process(_delta: float) -> void:
	local_in_range = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			local_in_range = absf(p.global_position.x - global_position.x) <= REACH_X and absf(p.global_position.y - global_position.y) <= REACH_Y
			break
	if local_in_range and Interact.pressed(self):
		var ui := get_tree().get_first_node_in_group("workshop_ui")
		var main := get_tree().current_scene
		if (ui == null or not ui.is_open()) and main != null and main.has_method("request_brief_cycle"):
			main.request_brief_cycle()               # następna odblokowana misja kampanii jako cel wyjścia (PROGRESSION_PLAN.md P1.1)
