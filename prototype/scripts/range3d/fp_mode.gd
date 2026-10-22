extends Node
## Strzelnica FPP — tryb z oczu gracza (RANGE_FPS_PLAN.md; wejście [E] przy drzwiach w kryjówce, range_door.gd, dev `--range3d`). Węzeł siedzi
## w graczu (`player.fp`): postać 2D stoi zaparkowana przy drzwiach (`player.in_range`), a gracz patrzy z oczu w tunelu strzelnicy
## (range_view.gd) i strzela tym samym kontrolerem broni co na misji —
## `weapon_controller.range_sink` oddaje strzał tutaj (promień w range_sim.gd zamiast pocisku 2D), `practice` daje amunicję ćwiczebną.
##
## Sterowanie: mysz (albo prawy drążek) rozgląda się, A/D przechodzą między stanowiskami, przytrzymany [Shift] to przyklęk z bronią na blacie
## ławy (oparcie: mniejszy podrzut i rozrzut jak w grze), PPM celuje przez przyrządy (tylko obraz — linia strzału to zawsze środek ekranu),
## [E] wychodzi. Podrzut broni (`wc.climb`, w °) unosi kamerę; ściąga się go myszą jak w grze.
##
## Szafa z bronią ([F], `range_locker`): każda broń palna gry do ręki bez kosztów, tylko na strzelnicy. Zestaw z wejścia (bronie, magazynki, typy
## naboi, zacięcia, lufy) zapisuje `weapon_controller.range_snapshot` i przy wyjściu przywraca go `range_restore` — gracz wychodzi z tym, z czym wszedł.

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const RangeView := preload("res://scripts/range3d/range_view.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")

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
var pb_new := false                   ## ostatni ukończony przebieg to nowy rekord osobisty tej broni (tablica w tunelu)
var paper_pb_new := false             ## ostatnia pełna grupa na papierze to nowy rekord osobisty
var paper_pb_at := -100.0             ## sim.clock tej grupy
var paper_cond := {}                  ## warunki bieżącej serii na papierze: {w (−2 — kilka broni), real (REALISTIC), heat0, heat1 (lufa 0..1
                                      ## przy pierwszej i ostatniej przestrzelinie), braced (przestrzeliny z oparciem), n}
var paper_prev := {}                  ## poprzednia seria do porównania: {g: grupa (sim.paper_last), c: warunki}
var _paper_sig := ""
var locker_open := false              ## otwarta szafa z bronią (obraz: range_locker.gd; mysz wolna, broń nie strzela — player._range_brain)
var locker_sel := 0                   ## zaznaczony wiersz szafy (indeks w `locker_weapons()`)
var locker_parts := false             ## szafa pokazuje gniazda broni `locker_w` (próba części, WORKSHOP_PLAN.md U5) zamiast listy broni
var locker_w := -1                    ## broń, której części gracz przymierza
var locker_slot := 0                  ## zaznaczone gniazdo (indeks w Parts.slots_of)
var locker_choice := {}               ## gniazdo → id części ("" — fabryczna) wybrane w szafie
var _kit := {}                        ## zestaw z wejścia (weapon_controller.range_snapshot), wraca przy wyjściu                  ## broń i obsługa: zmiana zaczyna nową serię (sim.paper_break)
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
	_kit = wc.range_snapshot()
	wc.range_sink = self
	wc.practice = true
	sim.finished.connect(_on_finished)
	sim.paper_hole.connect(_on_paper_hole)
	sim.paper_cleared.connect(_on_paper_cleared)
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
	wc.range_restore(_kit)                                     # sprzęt z wejścia: broń z szafy wraca na miejsce
	_kit = {}
	locker_open = false
	locker_parts = false
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
		player.weapons.range_restore(_kit)
	if view != null and is_instance_valid(view):
		view.release()
		view = null

## Przebieg ukończony: rekord osobisty broni w profilu, wynik do serwera przez drzwi (tablica drużyny).
func _on_finished(t: float, _best: float, _record: bool) -> void:
	if sim.run_w >= 0:
		pb_new = Profile.range_record(sim.exercise, String(Weapons.def(sim.run_w).key), t)
	if door != null and is_instance_valid(door):
		door.submit(t, sim.run_shots, sim.run_w, sim.exercise)

## Przestrzelina w papierze: piąta z serii zamyka grupę — rekord osobisty broni (MOA, mniej = lepiej).
func _on_paper_hole(_local: Vector2) -> void:
	var w := sim._shot_w
	var heat := float(player.weapons.barrel_of(w)) if w >= 0 else 0.0
	if paper_cond.is_empty():
		paper_cond = {"w": w, "real": Settings.realistic_handling, "heat0": heat, "heat1": heat, "braced": 0, "n": 0}
	elif int(paper_cond["w"]) != w:
		paper_cond["w"] = -2
	paper_cond["heat1"] = heat
	paper_cond["n"] = int(paper_cond["n"]) + 1
	if braced():
		paper_cond["braced"] = int(paper_cond["braced"]) + 1
	var g: Dictionary = sim.paper_group()
	if int(g["n"]) == RangeSim.PAPER_PB_SHOTS and sim._shot_w >= 0:
		paper_pb_new = Profile.range_record(RangeSim.EX_PAPER, String(Weapons.def(sim._shot_w).key), float(g["moa"]))
		paper_pb_at = sim.clock

## Nowa seria na papierze: zamknięta grupa z jej warunkami idzie do porównania (tablica PAPIER w tunelu, range_targets.gd).
func _on_paper_cleared() -> void:
	if not paper_cond.is_empty():
		paper_prev = {"g": sim.paper_last, "c": paper_cond}
	paper_cond = {}

## Ćwiczenie z przeładowaniem: przed startem przebiegu magazynek trzymanej broni ma najwyżej RangeSim.drill_load naboi (przeładowanie przed
## pierwszą blachą nic nie daje — nadmiar znika). Od pierwszej blachy liczy się już zwykły magazynek.
func _arm_drill() -> void:
	if sim.exercise != RangeSim.EX_RELOAD or sim.running:
		return
	var wc = player.weapons
	var d: WeaponDef = wc.cur()
	if not d.uses_ammo() or wc.is_reloading():
		return
	var cap := RangeSim.drill_load(d)
	if wc.mag_of(d.id) > cap:
		wc.mags[d.id] = cap

func _capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_HIDDEN

## Mysz wolna, rozglądanie wstrzymane: pauza albo otwarta szafa.
func _blocked() -> bool:
	return _paused() or locker_open

func _paused() -> bool:
	if get_tree().paused:
		return true
	var pm := get_tree().current_scene.get_node_or_null("UI/PauseMenu")
	return pm != null and bool(pm.get("_open"))

## Bronie w szafie: każda broń palna gry (bez broni białej — na strzelnicy PPM to przyrządy), w kolejności rejestru broni.
static func locker_weapons() -> Array:
	var out := []
	for w in Weapons.COUNT:
		if Weapons.def(w).slot != Weapons.Slot.MELEE:
			out.append(w)
	return out

## [F] otwiera / zamyka szafę; zaznaczenie startuje na trzymanej broni.
func toggle_locker() -> void:
	locker_open = not locker_open
	locker_parts = false
	if locker_open:
		locker_sel = maxi(0, locker_weapons().find(int(player.weapons.cur().id)))
		player.weapons.sim_fire = false

## Broń z wiersza `i` szafy do ręki (weapon_controller.range_take) i szafa się zamyka.
func locker_pick(i: int) -> void:
	var ids := locker_weapons()
	if i < 0 or i >= ids.size():
		return
	locker_sel = i
	player.weapons.range_take(int(ids[i]))
	locker_open = false

## Próba części (WORKSHOP_PLAN.md U5): gniazda broni z wiersza `i` szafy, z częściami, które ma teraz w ręku (albo z montażu gracza).
## Broń bez części zostaje na liście.
func locker_open_parts(i: int) -> void:
	var ids := locker_weapons()
	if i < 0 or i >= ids.size():
		return
	var w := int(ids[i])
	var key := String(Weapons.def(w).key)
	if Parts.slots_of(key).is_empty():
		return
	locker_sel = i
	locker_w = w
	locker_slot = 0
	locker_choice = {}
	var fitted := Parts.decode(key, int(player.weapons.fit_of(w)))
	for s in Parts.slots_of(key):
		locker_choice[s] = ""
		for p in Parts.in_slot(key, String(s)):
			if fitted.has(String(p["id"])):
				locker_choice[s] = String(p["id"])
	locker_parts = true

## Opcje gniazda `slot` broni `locker_w`: "" (fabryczna) i wszystkie części gniazda — odblokowane czy nie.
func locker_slot_options(slot: String) -> Array:
	var out := [""]
	for p in Parts.in_slot(String(Weapons.def(locker_w).key), slot):
		out.append(String(p["id"]))
	return out

## Następna (`d` = 1) albo poprzednia (−1) część w zaznaczonym gnieździe.
func locker_cycle(d: int) -> void:
	var slots := Parts.slots_of(String(Weapons.def(locker_w).key))
	if slots.is_empty():
		return
	var s := String(slots[clampi(locker_slot, 0, slots.size() - 1)])
	var ops := locker_slot_options(s)
	locker_choice[s] = ops[posmod(ops.find(String(locker_choice.get(s, ""))) + d, ops.size())]

## Broń z wybranymi częściami do ręki (weapon_controller.range_try) i szafa się zamyka.
func locker_try() -> void:
	player.weapons.range_try(locker_w, Parts.encode(String(Weapons.def(locker_w).key), locker_choice))
	locker_parts = false
	locker_open = false

## Sterowanie otwartą szafą: W/S (D-pad) wybór, spacja (A) bierze, → (D-pad) części broni, [F] albo [E] / Esc (B) zamyka. Myszą — klik w wiersz
## (range_locker.gd). W gniazdach: W/S gniazdo, A/D część, spacja bierze broń z tymi częściami, [E] / Esc wraca do listy broni.
func _tick_locker() -> void:
	if locker_parts:
		_tick_locker_parts()
		return
	var n := locker_weapons().size()
	if _locker_key() or (Input.is_action_just_pressed("menu_back") and not Input.is_action_just_pressed("pause")):   # Esc to pauza
		locker_open = false
	elif Input.is_action_just_pressed("menu_up"):
		locker_sel = (locker_sel - 1 + n) % n
	elif Input.is_action_just_pressed("menu_down"):
		locker_sel = (locker_sel + 1) % n
	elif Input.is_action_just_pressed("menu_right"):
		locker_open_parts(locker_sel)
	elif Input.is_action_just_pressed("menu_accept"):
		locker_pick(locker_sel)

## [F] zamyka szafę. Na padzie szafa siedzi pod D-pad →, który jest też `menu_right` (części, następna część) — wtedy wygrywa ruch w prawo,
## a pad zamyka szafę przyciskiem B.
func _locker_key() -> bool:
	return Input.is_action_just_pressed("range_locker") and not Input.is_action_just_pressed("menu_right")

func _tick_locker_parts() -> void:
	var n := Parts.slots_of(String(Weapons.def(locker_w).key)).size()
	if _locker_key():
		locker_parts = false
		locker_open = false
	elif Input.is_action_just_pressed("menu_back") and not Input.is_action_just_pressed("pause"):
		locker_parts = false
	elif Input.is_action_just_pressed("menu_up"):
		locker_slot = (locker_slot - 1 + n) % n
	elif Input.is_action_just_pressed("menu_down"):
		locker_slot = (locker_slot + 1) % n
	elif Input.is_action_just_pressed("menu_left"):
		locker_cycle(-1)
	elif Input.is_action_just_pressed("menu_right"):
		locker_cycle(1)
	elif Input.is_action_just_pressed("menu_accept"):
		locker_try()

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
	if _paused():
		return
	if locker_open:
		_tick_locker()
		return
	if Input.is_action_just_pressed("range_locker") and Engine.get_physics_frames() != _enter_frame:
		toggle_locker()
		return
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.0:
		look(-stick.x * PAD_SENS * Settings.fp_sens() * delta, -stick.y * PAD_SENS * Settings.fp_sens() * _y_sign() * delta)
	if Input.is_action_just_pressed("move_left"):
		station = maxi(0, station - 1)
	if Input.is_action_just_pressed("move_right"):
		station = mini(RangeSim.STATIONS.size() - 1, station + 1)
	if Input.is_action_just_pressed("range_exercise"):
		sim.set_exercise(sim.next_exercise())                  # w trakcie przebiegu nic (set_exercise sam pilnuje)
	_arm_drill()
	var sig := "%d:%s" % [int(player.weapons.cur().id), Settings.realistic_handling]
	if sig != _paper_sig:
		_paper_sig = sig
		sim.paper_break()                                      # inna broń albo obsługa — następna przestrzelina to nowa seria
	x = move_toward(x, float(RangeSim.STATIONS[station]), STATION_SPEED * delta)
	braced_pose = Input.is_action_pressed("crouch") and is_equal_approx(x, float(RangeSim.STATIONS[station]))
	brace_t = move_toward(brace_t, 1.0 if braced_pose else 0.0, BRACE_SPEED * delta)
	ads = Input.is_action_pressed("aim_sights") or dev_ads
	ads_t = move_toward(ads_t, 1.0 if ads else 0.0, ADS_SPEED * delta)
	if dev_ads_t >= 0.0:
		ads_t = dev_ads_t
	player.range_pose = Vector4(float(station), yaw, pitch + climb_rad(), brace_t)     # replikowane: postać na stanowisku u innych graczy
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
	player.range_shots += 1                                       # replikowane: błysk i strzał u innych graczy na strzelnicy
	var hits := sim.shoot(eye(), shot_basis(), d, seed, extra)
	if view != null and is_instance_valid(view):
		view.on_shot(d, hits)

## Czy przeładowanie tej broni ma w widoku klip z własnymi dźwiękami mechaniki (weapon_controller._reload_sfx wtedy milczy).
func clip_sounds(d: WeaponDef) -> bool:
	return view != null and is_instance_valid(view) and bool(view.call("has_reload_clip", String(d.key)))

func braced() -> bool:
	return braced_pose and brace_t > 0.9
