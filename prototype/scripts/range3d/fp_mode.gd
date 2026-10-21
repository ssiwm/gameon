extends Node
## Strzelnica FPP — tryb z oczu gracza (RANGE_FPS_PLAN.md; wejście [E] przy drzwiach w kryjówce, range_door.gd, dev `--range3d`). Węzeł siedzi
## w graczu (`player.fp`): postać 2D stoi zaparkowana przy drzwiach (`player.in_range`), a gracz patrzy z oczu w tunelu strzelnicy
## (range_view.gd) i strzela tym samym kontrolerem broni co na misji —
## `weapon_controller.range_sink` oddaje strzał tutaj (promień w range_sim.gd zamiast pocisku 2D), `practice` daje amunicję ćwiczebną.
##
## Sterowanie: mysz (albo prawy drążek) rozgląda się, A/D przechodzą między stanowiskami, przytrzymany [Shift] to przyklęk z bronią na blacie
## ławy (oparcie: mniejszy podrzut i rozrzut jak w grze), PPM celuje przez przyrządy (tylko obraz — linia strzału to zawsze środek ekranu),
## [E] wychodzi. Podrzut broni (`wc.climb`, w °) unosi kamerę; ściąga się go myszą jak w grze.

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const RangeView := preload("res://scripts/range3d/range_view.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")

const SENS := 0.0022                  ## rad na piksel ruchu myszy
const PAD_SENS := 2.4                 ## rad/s przy wychyleniu drążka do końca
const PITCH_MAX := deg_to_rad(70.0)
const YAW_MAX := deg_to_rad(75.0)     ## tunel: dalej w bok nie ma czego oglądać
const STATION_SPEED := 2.2            ## m/s przejścia między stanowiskami
const BRACE_SPEED := 4.0              ## 1/s przejścia do przyklęku i z powrotem
const ADS_SPEED := 7.0                ## 1/s podniesienia broni do oka

signal left_range

var player: CharacterBody2D
var sim: RangeSim
var view: Node                        ## range_view.gd (brak w trybie headless)
var yaw := 0.0                        ## rad — w lewo dodatnie
var pitch := 0.0                      ## rad — w górę dodatnie
var station := 1
var braced_pose := false              ## [Shift] przy ławie
var brace_t := 0.0                    ## 0 stoi … 1 przyklęk (obraz i wysokość oczu)
var ads := false
var ads_t := 0.0
var x := 0.0                          ## m — bieżące położenie oczu w poprzek tunelu (goni stanowisko)
var shots_fired := 0
var dev_ads := false                  ## dev `--rangeads`: przyrządy bez PPM (zrzuty)
var dev_ads_t := -1.0                 ## dev `--rangeads=T`: stały postęp przyrządów 0..1 (zrzuty przejścia), < 0 — wyłączone
var door: Node = null                 ## range_door.gd, przez które gracz wszedł: wynik przebiegu idzie przez nie do serwera; zniknięcie drzwi
                                      ## (inna mapa) kończy strzelnicę
var _enter_frame := -1                ## krok fizyki wejścia (to samo naciśnięcie [E] przy drzwiach nie może od razu wyjść)
var shot_climb := 0.0               ## ° — podrzut z początku kroku: strzał leci tam, gdzie celownik tej klatki (jak player._local_brain w grze 2D),
                                      ## a nie z podrzutem doliczonym już za ten sam strzał

## Gracz `p` wchodzi na strzelnicę (lokalny człowiek). Zwraca węzeł trybu.
static func enter(p: CharacterBody2D) -> Node:
	var fp: Node = load("res://scripts/range3d/fp_mode.gd").new()
	fp.name = "FpRange"
	fp.player = p
	p.add_child(fp)
	return fp

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS                    # pauza zwalnia mysz, a powrót znowu ją łapie
	sim = RangeSim.new()
	x = float(RangeSim.STATIONS[station])
	_enter_frame = Engine.get_physics_frames()
	player.fp = self
	player.in_range = true                                    # replikowane: postać stoi zaparkowana, inni widzą „RANGE” na plakietce
	var wc = player.weapons
	wc.range_sink = self
	wc.practice = true
	sim.finished.connect(_on_finished)
	if DisplayServer.get_name() != "headless":
		view = RangeView.new()
		view.name = "RangeView"
		view.setup(self)
		get_tree().current_scene.add_child(view)
	_capture(true)

## Wyjście ze strzelnicy: broń wraca do zwykłego strzelania, obraz do kryjówki.
func leave() -> void:
	var wc = player.weapons
	if wc.range_sink == self:
		wc.range_sink = null
	wc.practice = false
	wc.climb = 0.0
	if player.fp == self:
		player.fp = null
		player.in_range = false
	if view != null and is_instance_valid(view):
		view.release()
	view = null
	_capture(false)
	left_range.emit()
	queue_free()

## Tryb znika bez `leave` (gracz usunięty przy restarcie mapy, rozłączenie): broń i obraz kryjówki i tak wracają.
func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and player.fp == self:
		player.fp = null
		player.in_range = false
		player.weapons.range_sink = null
		player.weapons.practice = false
	if view != null and is_instance_valid(view):
		view.release()
		view = null

## Przebieg ukończony: wynik do serwera przez drzwi (tablica drużyny).
func _on_finished(t: float, _best: float, _record: bool) -> void:
	if door != null and is_instance_valid(door):
		door.submit(t, sim.run_shots, sim.run_w)

func _capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_HIDDEN

func _blocked() -> bool:
	if get_tree().paused:
		return true
	var pm := get_tree().current_scene.get_node_or_null("UI/PauseMenu")
	return pm != null and bool(pm.get("_open"))

func _process(_delta: float) -> void:
	var want := not _blocked()
	if DisplayServer.get_name() != "headless":
		var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if want and not cap:
			_capture(true)
		elif not want and cap:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_look((event as InputEventMouseMotion).relative)

## Ruch myszy o `rel` pikseli: czułość i odwrócona oś Y z ustawień (menu pauzy → FIRST PERSON).
func mouse_look(rel: Vector2) -> void:
	look(-rel.x * SENS * Settings.fp_sens(), -rel.y * SENS * Settings.fp_sens() * _y_sign())

## Odwrócona oś Y z ustawień (Settings.fp_invert_y): ruch w górę pochyla w dół.
func _y_sign() -> float:
	return -1.0 if Settings.fp_invert_y else 1.0

func look(dyaw: float, dpitch: float) -> void:
	yaw = clampf(yaw + dyaw, -YAW_MAX, YAW_MAX)
	pitch = clampf(pitch + dpitch, -PITCH_MAX, PITCH_MAX)

## Wołane przez gracza co krok fizyki zamiast zwykłego sterowania (player._range_brain).
func tick(delta: float) -> void:
	if door != null and not is_instance_valid(door):
		leave.call_deferred()                                  # drzwi zniknęły z mapą (wyjście z kryjówki, restart)
		return
	sim.tick(delta)
	shot_climb = float(player.weapons.climb)
	if _blocked():
		return
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.0:
		look(-stick.x * PAD_SENS * Settings.fp_sens() * delta, -stick.y * PAD_SENS * Settings.fp_sens() * _y_sign() * delta)
	if Input.is_action_just_pressed("move_left"):
		station = maxi(0, station - 1)
	if Input.is_action_just_pressed("move_right"):
		station = mini(RangeSim.STATIONS.size() - 1, station + 1)
	x = move_toward(x, float(RangeSim.STATIONS[station]), STATION_SPEED * delta)
	braced_pose = Input.is_action_pressed("crouch") and is_equal_approx(x, float(RangeSim.STATIONS[station]))
	brace_t = move_toward(brace_t, 1.0 if braced_pose else 0.0, BRACE_SPEED * delta)
	ads = Input.is_action_pressed("aim_sights") or dev_ads
	ads_t = move_toward(ads_t, 1.0 if ads else 0.0, ADS_SPEED * delta)
	if dev_ads_t >= 0.0:
		ads_t = dev_ads_t
	if Input.is_action_just_pressed("interact") and Engine.get_physics_frames() != _enter_frame:   # [E] wejścia przy drzwiach nie wychodzi od razu
		leave.call_deferred()

## Oko w świecie strzelnicy (m).
func eye() -> Vector3:
	return Vector3(x, lerpf(RangeSim.EYE_STAND, RangeSim.EYE_BRACE, brace_t), RangeSim.EYE_Z)

## Uniesienie lufy od podrzutu (rad) — kamera i linia strzału idą razem z nim.
func climb_rad() -> float:
	return deg_to_rad(float(player.weapons.climb))

## Kierunek patrzenia (−z bazy) z bieżącym podrzutem — kamera.
func view_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch + climb_rad(), yaw, 0.0), EULER_ORDER_YXZ)

## Kierunek strzału: podrzut sprzed tego strzału.
func shot_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch + deg_to_rad(shot_climb), yaw, 0.0), EULER_ORDER_YXZ)

# ---------------------------------------------------------------- weapon_controller.range_sink

func range_shot(d: WeaponDef, seed: int, extra: float) -> void:
	shots_fired += 1
	var hits := sim.shoot(eye(), shot_basis(), d, seed, extra)
	if view != null and is_instance_valid(view):
		view.on_shot(d, hits)

## Czy przeładowanie tej broni ma w widoku klip z własnymi dźwiękami mechaniki (weapon_controller._reload_sfx wtedy milczy).
func clip_sounds(d: WeaponDef) -> bool:
	return view != null and is_instance_valid(view) and bool(view.call("has_reload_clip", String(d.key)))

func braced() -> bool:
	return braced_pose and brace_t > 0.9
