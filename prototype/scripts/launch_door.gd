extends Node2D
## Drzwi wyjścia z kryjówki (strefa startu, LAUNCH_ZONE w danych mapy): stoją na prawym końcu strefy. Sam węzeł niesie tylko stan lampy ON AIR
## (0 — nikt nie gotowy, 1 — część drużyny gotowa, 2 — wszyscy gotowi i trwa odliczanie); drzwi, pasy na podłodze i lampę buduje view3d.gd z grupy „launch_door”.

var zone := Rect2()                   ## strefa startu w pikselach świata (level.launch_zone)
var state := 0                        ## stan lampy ON AIR, liczony co klatkę z gotowości w main.gd

func _ready() -> void:
	add_to_group("launch_door")
	z_index = 0

func _process(_delta: float) -> void:
	var main := get_tree().current_scene
	if main == null or main.get("hub_total") == null:
		return
	if float(main.get("hub_countdown")) >= 0.0:
		state = 2
	elif int(main.get("hub_ready_n")) > 0:
		state = 1
	else:
		state = 0
