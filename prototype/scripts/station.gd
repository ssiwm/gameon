extends Node2D
## Stanowisko warsztatu w kryjówce (WORKSHOP_IMMERSION_PLAN.md R0.1): wspólna część siedmiu stanowisk — ława, konserwacja, prasa,
## pirotechnika, pracownia, tokarka i szafki. Podklasa podaje dane w `_init()` (tryb panelu, grupa, zasięg, modele 3D, prostokąt klawisza)
## i własną `interact_hint()`; stała `REACH_X` zostaje w podklasie, bo czyta ją test odstępów zasięgów (tools/test_interact.gd).
## Gdy lokalny gracz stoi w zasięgu, [E] otwiera panel stanowisk (workshop_ui.gd) w trybie `mode`; odejście, śmierć albo uśpienie
## stanowiska wysyła `left_range` — panel się wtedy zamyka (R0.2: panel nie sprawdza już zasięgu sam co klatkę).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Interact := preload("res://scripts/interact.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")
const StationShot := preload("res://scripts/station_shot.gd")
const TILE := 16.0

## Lokalny gracz przestał być w zasięgu stanowiska (odszedł, zginął albo stanowisko zasnęło).
signal left_range

var mode := ""                          ## tryb panelu stanowisk (workshop_ui.gd MODE_PAGES)
var group := ""                         ## grupa węzła (czytają ją main.gd, testy i workshop_ui.gd MODE_GROUP)
var reach := Vector2(32.0, 40.0)        ## zasięg [E] w pikselach świata od znacznika: ±x, ±y
var models: Array = []                  ## modele 3D stanowiska: [model z art/items3d/, przesunięcie x w px, głębia z w m] (view3d.gd)
var model_check := ""                   ## model, którego obecność włącza modele 3D zamiast przedmiotów HD
var props: Array = []                   ## zapas bez modeli 3D: [nazwa przedmiotu HD, przesunięcie w kaflach]
var key_box := Rect2(-18.0, -24.0, 36.0, 24.0)   ## prostokąt klawisza [E] w świecie względem znacznika (interact.gd)
## Ujęcie kamery na stół po otwarciu panelu (R1, station_shot.gd DEFAULT): nadpisane pola, np. {"main": 1, "eye_z": 2.4}
var shot: Dictionary = {}

var station_props: Array = []           ## modele 3D, gdy są (view3d.gd, grupa „station_props”)
var local_in_range := false             ## lokalny człowiek stoi w zasięgu (HUD, main.gd)

func _ready() -> void:
	add_to_group(group)
	add_to_group(Interact.GROUP)
	z_index = 0
	var has_models := model_check != "" and ResourceLoader.exists(model_check)
	if has_models:
		station_props = models                                # modele 3D (view3d) zamiast przedmiotów HD
		add_to_group("station_props")
	_build_props(has_models)

## Wyposażenie z przedmiotów HD, gdy nie ma modeli 3D (`props`); widok 3D zamienia przedmiot HD na model z art/items3d/.
## Ława nadpisuje (tablica z narzędziami wisi też przy modelach 3D).
func _build_props(has_models: bool) -> void:
	if has_models or not Sprites.newitem:
		return
	for pr in props:
		if not ItemsHd.has(String(pr[0])):
			continue
		var h := Node2D.new()
		h.position = Vector2(float(pr[1]) * TILE, 0.0)
		add_child(h)
		ItemsHd.make(String(pr[0]), h)

## Stanowisko czynne. Uśpione (`dormant()` w podklasie, HUB_LAYOUT_PLAN.md E4) nie reaguje na [E]; widok 3D gasi nad nim lampę
## i nakrywa je plandeką (view3d.gd `_sync_dormant` — dlatego `dormant()` mają tylko stanowiska, które potrafią zasnąć).
func is_awake() -> bool:
	return not (has_method("dormant") and call("dormant"))

## Kadr kamery świata na stół stanowiska (R1): {eye, basis, fov} dla proporcji ekranu i pasa wolnego od karty (view3d.gd).
func focus_frame(aspect: float, band: Vector2) -> Dictionary:
	return StationShot.frame(global_position, models, shot, aspect, band)

## Punkt celowania ujęcia (blat stołu) w świecie 3D [m] — tu stoi lampa robocza.
func focus_target() -> Vector3:
	return StationShot.target(global_position, models, shot)

func in_reach(p: Node2D) -> bool:
	return absf(p.global_position.x - global_position.x) <= reach.x and absf(p.global_position.y - global_position.y) <= reach.y

## Oferta [E] (interact.gd): stanowisko otwiera kartę, gdy gracz stoi w zasięgu, a panel stanowisk jest zamknięty. Ustępuje broni,
## ratowaniu i pracom w misji (priorytet P_STATION).
func interact_offer(me: Node2D) -> Dictionary:
	if me.dead or not is_awake() or not in_reach(me):
		return {}
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	if ui != null and ui.is_open():
		return {}
	return Interact.offer(self, me, Interact.Kind.PRESS, Interact.P_STATION, true, Rect2(global_position + key_box.position, key_box.size))

func _physics_process(_delta: float) -> void:
	var was := local_in_range
	local_in_range = false
	var me: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			me = p
			break
	if me != null and is_awake():
		local_in_range = in_reach(me)
	if was and not local_in_range:
		left_range.emit()
	if local_in_range and Interact.pressed(self):
		var ui := get_tree().get_first_node_in_group("workshop_ui")
		if ui != null and not ui.is_open():
			ui.open(mode)
