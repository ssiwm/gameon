extends Node2D
## Warsztat w kryjówce (znacznik „h"): ława z imadłem, kowadłem i skrzynką na złom. Gdy lokalny gracz stoi przy niej,
## HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „bench" (workshop_ui.gd): bronie, części, czyszczenie i zaopatrzenie za złom.

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const REACH_X := 44.0
const REACH_Y := 40.0
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — ciężka ława rusznikarza z karabinem w imadle i skrzynkami
## części pod blatem oraz wózek na złom; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Na lewo stoi szafka stołu konserwacji (do ok. −26 px), na prawo filar (ok. +30 px). Narzędzia na ścianie zostają w obu wersjach.
const MODELS := [["gunsmith_bench", 8.0, -1.0], ["scrap_bin", 24.0, -0.7]]
const MODEL_CHECK := "res://art/items3d/gunsmith_bench.glb"
## Tablica z narzędziami nad ławą z modeli: w naturalnej wielkości (ok. 1,1 × 0,95 m — źródło ma 30 × 26 px świata) i wyśrodkowana
## nad ławą, dolną krawędzią ok. 35 cm nad blatem (blat 0,99 m) — [skala, x, y stopy w pikselach świata]
const TOOLS_WALL := [0.45, 8.0, -16.5]

var station_props: Array = []

var local_in_range := false
var _hd := false

func _ready() -> void:
	add_to_group("workshop")
	z_index = 0
	var models := ResourceLoader.exists(MODEL_CHECK)
	if models:
		station_props = MODELS                                # modele 3D (view3d) zamiast ławy HD
		add_to_group("station_props")
	if Sprites.newitem and ItemsHd.has("workshop"):
		# HD: ława z imadłem, kowadłem i skrzynką na złom (Tripo) oraz narzędzia na ścianie nad nią (młotek, klucz, piła, lampka)
		_hd = true
		if ItemsHd.has("tools_wall"):
			if models:
				var tw := ItemsHd.make("tools_wall", self, float(TOOLS_WALL[0]))
				tw.position = Vector2(float(TOOLS_WALL[1]), float(TOOLS_WALL[2]))
			else:
				var tw := ItemsHd.make("tools_wall", self, 0.8)
				tw.position = Vector2(4.4 * 0.8, -26.0)
		if not models:
			ItemsHd.make("workshop", self)

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
			ui.open("bench")
