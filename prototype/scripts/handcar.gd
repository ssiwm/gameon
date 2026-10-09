extends AnimatableBody2D
## Drezyna (misja 1.2, GDD §9): po nadawaniu drużyna ucieka podziemnym torem z powrotem na początek mapy.
## Stoi na znaczniku „D" mapy (wschodni koniec tunelu), jedzie na zachód do wyjścia („E" + EXIT_GAP).
##
## Napęd: ludzie NA POKŁADZIE trzymają [E] i pompują — prędkość zależy od liczby pompujących (boty na pokładzie
## dokładają połowę, ale tylko gdy ktoś pompuje). Pompujący nie strzela ani nie chodzi (player.pumping), więc
## trzeba wybierać: jechać czy się bronić. Puszczone E = drezyna hamuje. Jazda hałasuje i budzi to, co śpi przy torze.
## Stalker idzie 88 px/s, więc stanie w miejscu oznacza, że ON dogoni.
##
## Pokład jest równo z torem (stopy gracza na y = 0 drezyny, tak jak stopy wrogów na ziemi), więc strzały z pokładu
## lecą na tej samej wysokości co z ziemi. Wcześniej pokład był osobnym, uniesionym o 6 px kolajderem — gracz stojący
## na nim strzelał ponad hitboksami niskich wrogów. Dlatego drezyna nie ma kolizji: wszystko, co stoi w obrysie pokładu,
## przesuwa ona sama (_carry_riders) o ten sam krok co siebie.
##
## Autorytet: serwer (prędkość, położenie, hałas). Klienci całkują położenie sami z replikowanej prędkości i
## korygują je o stan z serwera (_sync). Każdy peer przesuwa razem z drezyną tylko SWOICH graczy (autorytet:
## lokalny człowiek, a na serwerze boty), więc jazda nie szarpie. Każdy gracz zgłasza serwerowi tylko „pompuję / nie".

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const HALF_W := 44.0                 ## połowa długości pokładu
const DECK_TOP := 5.35               ## wysokość górnej krawędzi pokładu nad torem [px świata] — do tej wysokości drezyna zasłania nogi graczy
const FRONT_Z := 10                  ## z względem drezyny: osłona pokładu i koła leżą przed graczami
const SPEED_MAX := 130.0
const SPEED_BASE := 55.0             ## prędkość docelowa przy jednym pompującym = BASE + PER_PUMPER
const SPEED_PER_PUMPER := 40.0
const ACCEL := 80.0
const DECEL := 70.0
const EXIT_GAP := 70.0               ## drezyna staje tyle px na wschód od znacznika wyjścia (resztę trzeba przejść)
const NOISE_EVERY := 1.2
const NOISE_AMOUNT := 0.8            ## ≥ progu budzenia wrogów (0,5) — jazda budzi śpiących przy torze
const SYNC_INTERVAL := 0.066
const SNAP_PX := 48.0
const CARRY_MAX_STEP := 12.0         ## większy skok położenia w jednej klatce (reset, snap do serwera) to teleport — nikogo nie wozimy
const RIDER_RANGE := 220.0           ## człowiek bliżej drezyny niż HALF_W + tyle = boty wsiadają i jadą

var enabled := false                 ## zasilanie (włącza je koniec celu głównego — mission.gd)
var arrived := false
var speed := 0.0                     ## px/s w stronę zachodu
var power := 0.0                     ## efektywna liczba pompujących (do rysowania)
var local_state := ""                ## dla HUD: "" | "nopower" | "near" | "aboard" | "pumping"
var start_x := 0.0
var end_x := 0.0

var _workers := {}                   ## serwer: nazwa gracza -> true
var _holding := false
var _x_srv := 0.0
var _have_srv := false
var _sync_t := 0.0
var _noise_t := NOISE_EVERY
var _t := 0.0
var _phase := 0.0                    ## faza obrotu kół / ramienia pompy
var _light: PointLight2D
var _lamp: Node2D
var _inited := false
var _hd := false
var _hd_wheels: Array = []           ## HD: koła (obracane z _phase)
var _hd_lever: Sprite2D              ## HD: dźwignia pompy (kiwa się)

func _ready() -> void:
	add_to_group("handcar")
	z_index = 3
	collision_layer = 0              # bez kolizji: pokład jest równo z torem, pasażerów wozi _carry_riders
	collision_mask = 0
	sync_to_physics = false          # bez tego position czytane w tej samej klatce jest nieaktualne (dx = 0) i nikogo nie wozimy
	_lamp = Node2D.new()
	_lamp.material = Lights.unshaded()
	_lamp.draw.connect(_draw_lamp)
	add_child(_lamp)
	_light = Lights.make_light(Lights.radial(), 7.0, Color(1.0, 0.82, 0.5), 0.0, true)
	_light.position = Vector2(-HALF_W + 1.5, -17)  # (HD: latarnia stoi 1,5 px dalej, różnica pomijalna)
	add_child(_light)
	start_x = position.x
	end_x = start_x
	_x_srv = position.x
	_setup_hd()

## Grafika HD: koła i dźwignia to osobne sprite'y (obracane/kiwane z `_phase`), reszta — jeden sprite korpusu; stare rysowanie wyłącza `_hd`.
func _setup_hd() -> void:
	if not (Sprites.newitem and ItemsHd.has("handcar") and ItemsHd.has("handcar_wheel") and ItemsHd.has("handcar_lever")):
		return
	_hd = true
	for wx in [-HALF_W + 13.0, HALF_W - 13.0]:
		var w := ItemsHd.make("handcar_wheel", self)
		w.offset = Vector2.ZERO                       # środek tekstury = oś obrotu
		w.position = Vector2(wx, -2.5)
		w.z_index = FRONT_Z + 1                       # koła przed graczami i przed belką podwozia (niżej)
		_hd_wheels.append(w)
	var body := ItemsHd.make("handcar", self)
	body.position = Vector2(0.0, -2.0)                # spód korpusu = dolna krawędź ramy (2 px nad torem)
	# Osłona pokładu: pokład jest równo z torem (stopy graczy na y = 0 drezyny), a rama i deski sięgają ok. 5,3 px nad tor — bez osłony stopy i łydki
	# wystawały pod pokładem. Dolny pas korpusu (rama + deski do górnej krawędzi) rysujemy drugi raz, TĘ SAMĄ teksturą, ale przed graczami.
	var skirt := ItemsHd.make("handcar", self)
	var f := ItemsHd.frame_px("handcar")
	var top_px := f.y - ItemsHd.PAD - DECK_TOP * ItemsHd.ppw("handcar")          # wiersz tekstury z górną krawędzią pokładu
	skirt.region_enabled = true
	skirt.region_rect = Rect2(0.0, top_px, f.x, f.y - top_px)
	skirt.position = body.position
	skirt.offset = body.offset + Vector2(0.0, top_px * 0.5)                          # region wycentrowany tak, by pokrył się z korpusem
	skirt.z_index = FRONT_Z
	# Pod ramą (2 px nad torem) jest szczelina, w której było widać buty graczy stojących na torze — zasłania ją belka podwozia, też przed graczami.
	var apron := Node2D.new()
	apron.name = "Apron"
	apron.z_index = FRONT_Z
	apron.draw.connect(_draw_apron.bind(apron))
	add_child(apron)
	_hd_lever = ItemsHd.make("handcar_lever", self)
	_hd_lever.offset = Vector2.ZERO
	_hd_lever.position = Vector2(0, -13)
	move_child(_lamp, get_child_count() - 1)          # blask latarni nad korpusem

## Belka podwozia między ramą a torem (HD): ciemna stal z jasną krawędzią i nitami; wysokość = szczelina pod ramą + zapas na buty.
func _draw_apron(ci: Node2D) -> void:
	var x0 := -HALF_W + 1.0
	var w := HALF_W * 2.0 - 2.0
	ci.draw_rect(Rect2(x0, -2.4, w, 3.4), Color(0.17, 0.18, 0.21))
	ci.draw_rect(Rect2(x0, -2.4, w, 0.8), Color(0.32, 0.34, 0.39))
	ci.draw_rect(Rect2(x0, 0.4, w, 0.6), Color(0.1, 0.1, 0.12))
	for i in 9:
		ci.draw_circle(Vector2(x0 + 5.0 + float(i) * (w - 10.0) / 8.0, -0.7), 0.45, Color(0.5, 0.52, 0.58))

func _update_hd() -> void:
	for i in _hd_wheels.size():
		(_hd_wheels[i] as Sprite2D).rotation = _phase + float(i) * 0.7
	var moving := speed > 5.0 or power > 0.0
	_hd_lever.rotation = sin(_phase * 1.6) * (0.38 if moving else 0.05)

func _exit_tree() -> void:
	Audio.stop_loop(name)

## Tor kończy się przy wyjściu poziomu (pierwszy znacznik „E"); szukamy go leniwie, bo poziom składa się po nas.
func _init_track() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or lvl.exits.is_empty():
		return
	end_x = (lvl.exits[0] as Vector2).x + EXIT_GAP
	_inited = true

func aboard(p: Node2D) -> bool:
	return absf(p.global_position.x - global_position.x) <= HALF_W - 4.0 and p.global_position.y <= global_position.y + 6.0 \
		and p.global_position.y >= global_position.y - 40.0

## Boty jadą, gdy drezyna jest zasilona i jedzie (jeszcze nie dojechała), a któryś żywy człowiek jest przy niej.
func wants_riders() -> bool:
	if not enabled or arrived:
		return false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead or p.is_queued_for_deletion():
			continue
		if absf(p.global_position.x - global_position.x) <= HALF_W + RIDER_RANGE and absf(p.global_position.y - global_position.y) <= 60.0:
			return true
	return false

## Miejsce bota na pokładzie (x w świecie): trzy sloty, żeby boty nie stały w jednym punkcie.
func slot_x(slot: int) -> float:
	return global_position.x + float(slot % 3 - 1) * 26.0

## Wozi graczy stojących w obrysie pokładu o ten sam krok co drezyna. Tylko własnych (autorytet), reszta
## przyjeżdża z replikacją. move_and_collide: pasażer nie wjedzie w ścianę ani w rekwizyt.
func _carry_riders(dx: float) -> void:
	if absf(dx) < 0.001 or absf(dx) > CARRY_MAX_STEP:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion() or not p.is_multiplayer_authority() or not aboard(p):
			continue
		p.move_and_collide(Vector2(dx, 0.0))

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- każdy peer: czy MÓJ gracz pompuje

func _update_local() -> void:
	var me := _local_human()
	var want := false
	local_state = ""
	if me != null and not me.dead:
		var near := absf(me.global_position.x - global_position.x) <= HALF_W + 60.0 and absf(me.global_position.y - global_position.y) <= 50.0
		if not enabled:
			local_state = "nopower" if near else ""
		elif arrived:
			local_state = ""
		elif aboard(me):
			local_state = "aboard"
			if Input.is_action_pressed("interact") and me.revive_hint() == "":
				want = true
				local_state = "pumping"
		elif near:
			local_state = "near"
	if me != null:
		me.pumping = want
	if want == _holding:
		return
	_holding = want
	if NoiseMgr.is_server():
		_set_worker(NoiseMgr.local_id(), want)
	else:
		_work_rpc.rpc_id(1, want)

@rpc("any_peer", "call_remote", "reliable")
func _work_rpc(on: bool) -> void:
	if multiplayer.is_server():
		_set_worker(multiplayer.get_remote_sender_id(), on)

func _set_worker(peer_id: int, on: bool) -> void:
	var key := str(peer_id)
	if on:
		_workers[key] = true
	else:
		_workers.erase(key)

# ---------------------------------------------------------------- symulacja

func _physics_process(delta: float) -> void:
	_t += delta
	if not _inited:
		_init_track()
	_update_local()
	_lamp.queue_redraw()
	queue_redraw()
	if _hd:
		_update_hd()
	var x_before := position.x
	if NoiseMgr.is_server():
		_server_tick(delta)
	else:
		_client_tick(delta)
	_carry_riders(position.x - x_before)
	_phase += speed * delta * 0.09
	_update_audio()

func _server_tick(delta: float) -> void:
	# pompujący: tylko żywi ludzie na pokładzie
	var humans := 0
	var bots := 0
	var alive := {}
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion() or not aboard(p):
			continue
		if p.is_bot:
			bots += 1
		else:
			alive[String(p.name)] = true
	for k in _workers.keys():
		if not alive.has(k):
			_workers.erase(k)
	humans = _workers.size()
	power = float(humans) + (0.5 * float(bots) if humans > 0 else 0.0)
	var target := 0.0
	if enabled and not arrived and power > 0.0:
		target = minf(SPEED_MAX, SPEED_BASE + SPEED_PER_PUMPER * power)
	speed = move_toward(speed, target, (ACCEL if target > speed else DECEL) * delta)
	if speed > 0.0:
		position.x -= speed * delta
		_noise_t -= delta
		if _noise_t <= 0.0 and speed > 20.0:
			_noise_t = NOISE_EVERY
			NoiseMgr.add_noise(NOISE_AMOUNT, global_position)
		if position.x <= end_x and _inited:
			position.x = end_x
			speed = 0.0
			arrived = true
			_workers.clear()
			print("[HANDCAR] arrived at x=%.0f" % position.x)
			if NoiseMgr.has_network():
				_sync_state.rpc(enabled, true)
	_sync_t -= delta
	if _sync_t <= 0.0 and NoiseMgr.has_network():
		_sync_t = SYNC_INTERVAL
		_sync.rpc(position.x, speed, power)

func _client_tick(delta: float) -> void:
	position.x -= speed * delta
	if _have_srv:
		_x_srv -= speed * delta                       # serwerowe położenie też „płynie"
		var d := _x_srv - position.x
		if absf(d) > SNAP_PX:
			position.x = _x_srv
		else:
			position.x += d * minf(1.0, 8.0 * delta)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(x: float, spd: float, pw: float) -> void:
	_x_srv = x
	_have_srv = true
	speed = spd
	power = pw

@rpc("authority", "call_remote", "reliable")
func _sync_state(is_enabled: bool, is_arrived: bool) -> void:
	_apply_state(is_enabled, is_arrived)

func _apply_state(is_enabled: bool, is_arrived: bool) -> void:
	if is_enabled and not enabled:
		Audio.play_at("radio_beep", global_position, Audio.BUS_WORLD, -4.0)
	enabled = is_enabled
	arrived = is_arrived
	_light.energy = 0.9 if enabled else 0.0
	if arrived:
		speed = 0.0

## Zasilanie po celu głównym (serwer).
func activate() -> void:
	if not NoiseMgr.is_server():
		return
	_apply_state(true, false)
	if NoiseMgr.has_network():
		_sync_state.rpc(true, false)
	print("[HANDCAR] powered")

## Restart misji (serwer): z powrotem na stację, bez zasilania.
func reset_handcar() -> void:
	if not NoiseMgr.is_server():
		return
	position.x = start_x
	speed = 0.0
	power = 0.0
	_workers.clear()
	_noise_t = NOISE_EVERY
	_apply_state(false, false)
	if NoiseMgr.has_network():
		_sync_state.rpc(false, false)
		_sync.rpc(position.x, 0.0, 0.0)

func _update_audio() -> void:
	if enabled and speed > 5.0:
		Audio.start_loop_at("amb_machine", self, Audio.BUS_WORLD, -14.0 + speed * 0.04, true, name)
	else:
		Audio.stop_loop(name)

# ---------------------------------------------------------------- rysowanie (stopy w (0, 0), jedzie na zachód = w lewo)
# Pokład leży płasko na torze (wysokość 3 px) — gracz stoi na y = 0, jak na ziemi.

func _draw() -> void:
	if _hd:
		return
	var plank := Color(0.43, 0.32, 0.20)
	var plank_hi := Color(0.58, 0.45, 0.29)
	var plank_lo := Color(0.27, 0.19, 0.12)
	var steel := Color(0.22, 0.23, 0.26)
	var steel_hi := Color(0.46, 0.48, 0.52)
	var rust := Color(0.50, 0.29, 0.15)
	var yellow := Color(0.85, 0.66, 0.16)
	var moving := speed > 5.0 or power > 0.0
	# koła (za pokładem): żeliwne, z szprychami i piastą
	for wx in [-HALF_W + 13.0, HALF_W - 13.0]:
		var c := Vector2(wx, -2.5)
		draw_circle(c, 3.4, steel)
		draw_arc(c, 3.0, 0.0, TAU, 14, steel_hi, 0.8)
		for k in 4:
			var a: float = _phase + wx + float(k) * PI * 0.5
			draw_line(c, c + Vector2(cos(a), sin(a)) * 2.9, rust, 0.8)
		draw_circle(c, 0.9, yellow)
	# belka ramy pod pokładem + zderzaki na końcach
	draw_rect(Rect2(-HALF_W + 2, -4, HALF_W * 2.0 - 4, 2), steel)
	draw_rect(Rect2(-HALF_W - 3, -5, 4, 3), rust)
	draw_rect(Rect2(HALF_W - 1, -5, 4, 3), rust)
	draw_rect(Rect2(-HALF_W - 3, -5, 4, 1), steel_hi)
	draw_rect(Rect2(HALF_W - 1, -5, 4, 1), steel_hi)
	# pokład: deski z fugami i okuciem
	draw_rect(Rect2(-HALF_W, -5, HALF_W * 2.0, 3), plank)
	draw_rect(Rect2(-HALF_W, -5, HALF_W * 2.0, 1), plank_hi)
	draw_rect(Rect2(-HALF_W, -3, HALF_W * 2.0, 1), plank_lo)
	var gx := -HALF_W + 8.0
	while gx < HALF_W:
		draw_rect(Rect2(gx, -5, 1, 3), plank_lo)
		gx += 11.0
	for bx in [-HALF_W + 3.0, HALF_W - 4.0, -9.0, 8.0]:
		draw_rect(Rect2(bx, -4, 1, 1), steel_hi)
	# słup pompy na środku i dźwignia (wahadło) — kiwa się z prędkością jazdy
	draw_rect(Rect2(-2, -14, 4, 9), steel)
	draw_rect(Rect2(-2, -14, 1, 9), steel_hi)
	draw_rect(Rect2(-4, -7, 8, 2), rust)
	var sway := sin(_phase * 1.6) * (0.38 if moving else 0.05)
	var l := Vector2(cos(sway), sin(sway)) * 22.0
	var pivot := Vector2(0, -13)
	draw_line(pivot - l, pivot + l, Color(0.34, 0.26, 0.17), 3.0)
	draw_line(pivot - l, pivot + l, plank_hi, 1.0)
	for e in [pivot - l, pivot + l]:
		draw_rect(Rect2(e.x - 1.5, e.y - 4, 3, 5), steel)       # uchwyty do pompowania
		draw_rect(Rect2(e.x - 2.0, e.y - 4, 4, 1), yellow)
	draw_circle(pivot, 1.6, yellow)
	# żółto-czarne pasy ostrzegawcze na przodzie belki
	for i in 4:
		draw_rect(Rect2(HALF_W - 9 + float(i) * 2.0, -4, 1, 2), Color(0.1, 0.1, 0.1) if i % 2 == 0 else yellow)
	# latarnia z przodu (zachód): wspornik, obudowa z kratką
	draw_rect(Rect2(-HALF_W + 2, -16, 2, 11), steel)
	draw_rect(Rect2(-HALF_W - 1, -20, 8, 5), steel)
	draw_rect(Rect2(-HALF_W - 1, -20, 8, 1), steel_hi)
	draw_rect(Rect2(-HALF_W, -19, 3, 3), Color(0.05, 0.05, 0.05))

func _draw_lamp() -> void:
	var on := enabled
	var col := Color(1.0, 0.85, 0.5) if on else Color(0.5, 0.15, 0.12)
	if _hd:
		# HD: szkło latarni jako miękki blask (jądro + dwie poświaty) zamiast pełnego dysku; szkło w modelu jest czarne, więc gdy nie ma zasilania, świeci tylko czerwona dioda
		var lc := Vector2(-HALF_W + 3.0, -17.7)
		_lamp.draw_circle(lc, 1.0, col)
		if on:
			_lamp.draw_circle(lc, 2.4, Color(col, 0.35))
			_lamp.draw_circle(lc, 4.6, Color(col, 0.12))
			_lamp.draw_polygon(PackedVector2Array([lc + Vector2(-1, 0), lc + Vector2(-76, -12), lc + Vector2(-76, 13)]), PackedColorArray([Color(1.0, 0.9, 0.6, 0.08), Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.9, 0.6, 0.0)]))
		else:
			_lamp.draw_circle(lc, 2.2, Color(col, 0.2))
		return
	_lamp.draw_circle(Vector2(-HALF_W + 1.5, -17.5), 1.8, col)
	if on:
		_lamp.draw_circle(Vector2(-HALF_W + 1.5, -17.5), 4.5, Color(col, 0.18))
		_lamp.draw_polygon(PackedVector2Array([Vector2(-HALF_W - 1, -17.5), Vector2(-HALF_W - 75, -30), Vector2(-HALF_W - 75, -5)]), PackedColorArray([Color(1.0, 0.9, 0.6, 0.07), Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.9, 0.6, 0.0)]))
