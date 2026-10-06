extends AnimatableBody2D
## Drezyna (misja 1.2, GDD §9): po nadawaniu drużyna ucieka podziemnym torem z powrotem na początek mapy.
## Stoi na znaczniku „D" mapy (wschodni koniec tunelu), jedzie na zachód do wyjścia („E" + EXIT_GAP).
##
## Napęd: ludzie NA POKŁADZIE trzymają [E] i pompują — prędkość zależy od liczby pompujących (boty na pokładzie
## dokładają połowę, ale tylko gdy ktoś pompuje). Pompujący nie strzela ani nie chodzi (player.pumping), więc
## trzeba wybierać: jechać czy się bronić. Puszczone E = drezyna hamuje. Jazda hałasuje i budzi to, co śpi przy torze.
## Stalker idzie 88 px/s, więc stanie w miejscu oznacza, że ON dogoni.
##
## Autorytet: serwer (prędkość, położenie, hałas). Klienci całkują położenie sami z replikowanej prędkości i
## korygują je o stan z serwera (_sync) — gracz stojący na pokładzie jedzie razem z lokalną kopią drezyny
## (AnimatableBody2D, sync_to_physics), więc nie ma szarpnięć. Każdy gracz zgłasza serwerowi tylko „pompuję / nie".

const Lights := preload("res://scripts/lights.gd")

const HALF_W := 44.0                 ## połowa długości pokładu
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

func _ready() -> void:
	add_to_group("handcar")
	z_index = 3
	sync_to_physics = true
	collision_layer = 16             # warstwa kładek (level.gd LAYER_PLATFORM): gracz staje na pokładzie, pociski przelatują
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(HALF_W * 2.0, 4.0)
	cs.shape = shape
	cs.position = Vector2(0, -4)
	cs.one_way_collision = true
	add_child(cs)
	_lamp = Node2D.new()
	_lamp.material = Lights.unshaded()
	_lamp.draw.connect(_draw_lamp)
	add_child(_lamp)
	_light = Lights.make_light(Lights.radial(), 7.0, Color(1.0, 0.82, 0.5), 0.0, true)
	_light.position = Vector2(-HALF_W + 8.0, -20)
	add_child(_light)
	start_x = position.x
	end_x = start_x
	_x_srv = position.x

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
	if NoiseMgr.is_server():
		_server_tick(delta)
	else:
		_client_tick(delta)
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

func _draw() -> void:
	var body := Color(0.30, 0.27, 0.22)
	var dark := Color(0.12, 0.12, 0.13)
	var rust := Color(0.45, 0.28, 0.16)
	# pokład i rama
	draw_rect(Rect2(-HALF_W, -7, HALF_W * 2.0, 4), body)
	draw_rect(Rect2(-HALF_W, -7, HALF_W * 2.0, 1), Color(0.5, 0.45, 0.36))
	draw_rect(Rect2(-HALF_W + 2, -3, HALF_W * 2.0 - 4, 2), dark)
	# koła z szprychami
	for wx in [-HALF_W + 12.0, HALF_W - 12.0]:
		draw_circle(Vector2(wx, -2), 4.5, dark)
		draw_circle(Vector2(wx, -2), 2.0, rust)
		var a: float = _phase + wx
		draw_line(Vector2(wx, -2), Vector2(wx + cos(a) * 4.0, -2 + sin(a) * 4.0), Color(0.7, 0.6, 0.5), 1.0)
	# podpora i ramię pompy (kiwa się z prędkością)
	draw_rect(Rect2(-3, -17, 6, 10), dark)
	var sway := sin(_phase * 1.6) * (0.35 if speed > 5.0 or power > 0.0 else 0.04)
	var tip := Vector2(sin(sway) * 20.0, -17.0 - cos(sway) * 3.0)
	draw_line(Vector2(0, -16), tip + Vector2(0, 0), Color(0.55, 0.5, 0.42), 2.5)
	draw_line(tip + Vector2(-5, 0), tip + Vector2(5, 0), Color(0.75, 0.65, 0.5), 2.0)
	# latarnia z przodu (zachód)
	draw_rect(Rect2(-HALF_W + 3, -18, 4, 11), dark)
	draw_rect(Rect2(-HALF_W + 1, -21, 8, 4), rust)

func _draw_lamp() -> void:
	var on := enabled
	var col := Color(1.0, 0.85, 0.5) if on else Color(0.5, 0.15, 0.12)
	_lamp.draw_circle(Vector2(-HALF_W + 5, -19), 1.8, col)
	if on:
		_lamp.draw_circle(Vector2(-HALF_W + 5, -19), 4.5, Color(col, 0.18))
		_lamp.draw_polygon(PackedVector2Array([Vector2(-HALF_W + 3, -19), Vector2(-HALF_W - 70, -30), Vector2(-HALF_W - 70, -8)]), PackedColorArray([Color(1.0, 0.9, 0.6, 0.07), Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.9, 0.6, 0.0)]))
