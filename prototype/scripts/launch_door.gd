extends Node2D
## Drzwi wyjścia z kryjówki (strefa startu, LAUNCH_ZONE w danych mapy): stoją na prawym końcu strefy. Sam węzeł niesie tylko stan lampy ON AIR
## (0 — nikt nie gotowy, 1 — część drużyny gotowa, 2 — wszyscy gotowi i trwa odliczanie); drzwi, pasy na podłodze i lampę buduje view3d.gd z grupy „launch_door”.

var zone := Rect2()                   ## strefa startu w pikselach świata (level.launch_zone)
var state := 0                        ## stan lampy ON AIR, liczony co klatkę z gotowości w main.gd
var ready_n := 0                      ## ilu ludzi gotowych (sloty na podłodze strefy)
var total := 0                        ## ilu ludzi w drużynie
var countdown := -1.0                 ## pozostały czas odliczania [s], < 0: brak (cyfra w HUD)
var cancel := 0.0                     ## 1 w chwili anulowania odliczania, zanika (czerwony błysk)

func _ready() -> void:
	add_to_group("launch_door")
	z_index = 0

func _process(_delta: float) -> void:
	var main := get_tree().current_scene
	if main == null or main.get("hub_total") == null:
		return
	ready_n = int(main.get("hub_ready_n"))
	total = int(main.get("hub_total"))
	countdown = float(main.get("hub_countdown"))
	cancel = float(main.get("hub_cancel_flash"))
	if float(main.get("hub_countdown")) >= 0.0:
		state = 2
	elif int(main.get("hub_ready_n")) > 0:
		state = 1
	else:
		state = 0
