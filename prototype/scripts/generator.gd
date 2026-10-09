extends Node2D
## Generator radiostacji (misja 1.2 „Przerwa w Nadawaniu", GDD §9). Stoi na znaczniku „G" mapy.
##
## Gracz podchodzi i TRZYMA [E] przez WORK_TIME s (dwie osoby = 2× szybciej). Praca robi hałas, a uruchomiony generator
## buczy: co HUM_INTERVAL s zgłasza cichy hałas ze swojego miejsca — przyciąga wrogów, którzy nasłuchują (Ślepiec,
## Podsłuchacz). Autorytet: serwer (postęp i start); klienci dostają stan przez _sync / _sync_state. Każdy gracz
## zgłasza serwerowi tylko „trzymam / puściłem" (_work_rpc), a serwer sam sprawdza zasięg i życie.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const SmokeCloud := preload("res://scripts/smoke_cloud.gd")
const HD_SCALE := 0.85               ## model generatora (35 px szeroki) pomniejszony do dawnych ~30 px

signal started(gen: Node)

const WORK_TIME := 5.5
const REACH_X := 30.0
const REACH_Y := 44.0
const WORK_NOISE_PER_S := 1.6        ## Uwaga na sekundę pracy jednej osoby (start ≈ +9)
const NOISE_CHUNK := 0.3             ## hałas pracy zgłaszamy porcjami, nie co klatkę (każde zgłoszenie to push sieciowy)
const START_BURST := 5.0             ## wybuch hałasu przy uruchomieniu
const HUM_NOISE := 0.9               ## buczenie: ≥ progu budzenia (0,5), więc słyszą je także śpiący w zasięgu
const HUM_INTERVAL := 4.5
const DECAY_PER_S := 0.6             ## postęp cofa się, gdy nikt nie pracuje
const SYNC_INTERVAL := 0.1

var progress := 0.0
var running := false
var local_in_range := false          ## lokalny człowiek stoi w zasięgu (HUD pokazuje podpowiedź)

var _holding := false                ## to, co ten peer ostatnio zgłosił serwerowi
var _workers := {}                   ## serwer: nazwa gracza -> true
var _sync_t := 0.0
var _hum_t := HUM_INTERVAL
var _noise_acc := 0.0
var _sent_progress := -1.0
var _light: PointLight2D
var _lamp: Node2D
var _t := 0.0
var _hd: Sprite2D                    ## grafika HD (Sprites.newitem): model generatora, drga, gdy pracuje

func _ready() -> void:
	add_to_group("generators")
	z_index = 2
	_lamp = Node2D.new()
	_lamp.material = Lights.unshaded()
	_lamp.draw.connect(_draw_lamp)
	add_child(_lamp)
	if Sprites.newitem and ItemsHd.has("generator"):
		_hd = ItemsHd.make("generator", self, HD_SCALE)
		_hd.position = Vector2(ItemsHd.cx("generator") * HD_SCALE, 0.0)
		move_child(_lamp, get_child_count() - 1)              # lampka, dym i pasek postępu nad korpusem
	_light = Lights.make_light(Lights.radial(), 6.0, Color(1.0, 0.78, 0.4), 0.0, false)
	_light.position = Vector2(0, -12)
	add_child(_light)

func _exit_tree() -> void:
	Audio.stop_loop(name)

func _in_reach(p: Vector2, mult := 1.0) -> bool:
	return absf(p.x - global_position.x) <= REACH_X * mult and absf(p.y - global_position.y) <= REACH_Y * mult

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- każdy peer: czy MÓJ gracz pracuje

func _update_local() -> void:
	var me := _local_human()
	var near: bool = me != null and not running and not me.dead and _in_reach(me.global_position)
	local_in_range = near
	var want := false
	if near and Input.is_action_pressed("interact"):
		# ratowanie kolegi i podnoszenie broni mają pierwszeństwo przed generatorem
		want = me.revive_hint() == "" and me.weapons.nearby_weapon_item() == null
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

# ---------------------------------------------------------------- serwer

func _physics_process(delta: float) -> void:
	_t += delta
	_update_local()
	_lamp.queue_redraw()
	queue_redraw()
	if _hd != null:
		var base_x := ItemsHd.cx("generator") * HD_SCALE
		if running:
			_hd.position = Vector2(base_x + sin(_t * 53.0) * 0.22, sin(_t * 61.0) * 0.16)      # drgania pracującego silnika
		else:
			_hd.position = Vector2(base_x, 0.0)
	if not NoiseMgr.is_server():
		return
	_validate_workers()
	if not running:
		if not _workers.is_empty():
			progress = minf(1.0, progress + delta / WORK_TIME * minf(float(_workers.size()), 2.0))
			_noise_acc += WORK_NOISE_PER_S * float(_workers.size()) * delta
			if _noise_acc >= NOISE_CHUNK:
				NoiseMgr.add_noise(_noise_acc, global_position)
				_noise_acc = 0.0
			if progress >= 1.0:
				_start()
		elif progress > 0.0:
			progress = maxf(0.0, progress - DECAY_PER_S * delta)
	else:
		_hum_t -= delta
		if _hum_t <= 0.0:
			_hum_t = HUM_INTERVAL
			NoiseMgr.add_noise(HUM_NOISE, global_position)
	_sync_t -= delta
	if _sync_t <= 0.0 and not is_equal_approx(progress, _sent_progress):
		_sync_t = SYNC_INTERVAL
		_sent_progress = progress
		if NoiseMgr.has_network():
			_sync.rpc(progress)

## Serwer sam sprawdza, czy zgłaszający nadal stoi przy generatorze, żyje i istnieje.
func _validate_workers() -> void:
	if _workers.is_empty():
		return
	var alive := {}
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and not p.is_queued_for_deletion() and _in_reach(p.global_position, 1.4):
			alive[String(p.name)] = true
	for k in _workers.keys():
		if not alive.has(k):
			_workers.erase(k)

func _start() -> void:
	progress = 1.0
	_workers.clear()
	_hum_t = HUM_INTERVAL
	NoiseMgr.add_noise(START_BURST, global_position)
	_set_running(true)
	if NoiseMgr.has_network():
		_sync_state.rpc(true)
		_sync.rpc(progress)
	started.emit(self)
	print("[GEN] %s started" % name)

## Restart misji (main._restart_mission): generator wraca do stanu wyjściowego u wszystkich.
func reset_generator() -> void:
	if not NoiseMgr.is_server():
		return
	progress = 0.0
	_sent_progress = -1.0
	_workers.clear()
	_noise_acc = 0.0
	_set_running(false)
	if NoiseMgr.has_network():
		_sync_state.rpc(false)
		_sync.rpc(0.0)

# ---------------------------------------------------------------- klienci

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(p: float) -> void:
	progress = p

@rpc("authority", "call_remote", "reliable")
func _sync_state(is_running: bool) -> void:
	_set_running(is_running)
	if is_running:
		progress = 1.0

func _set_running(on: bool) -> void:
	if on == running:
		return
	running = on
	_light.energy = 0.85 if on else 0.0
	if on:
		Audio.play_at("radio_beep", global_position, Audio.BUS_WORLD, -4.0)
		Audio.start_loop_at("generator_loop", self, Audio.BUS_WORLD, -6.0, true, name)
	else:
		Audio.stop_loop(name)

# ---------------------------------------------------------------- rysowanie (stopy w (0, 0))

func _draw() -> void:
	if _hd != null:
		return
	var body := Color(0.24, 0.27, 0.25)
	var dark := Color(0.12, 0.14, 0.13)
	var rust := Color(0.42, 0.26, 0.16)
	# podstawa i korpus
	draw_rect(Rect2(-14, -3, 28, 3), dark)
	draw_rect(Rect2(-13, -17, 26, 14), body)
	draw_rect(Rect2(-13, -17, 26, 2), Color(0.34, 0.38, 0.35))
	# zbiornik z paliwem, kratka wentylatora, rura
	draw_rect(Rect2(-12, -23, 12, 7), rust)
	draw_rect(Rect2(-12, -23, 12, 1), Color(0.55, 0.36, 0.22))
	for i in 4:
		draw_rect(Rect2(2 + i * 3, -14, 2, 8), dark)
	draw_rect(Rect2(8, -26, 3, 9), dark)
	# postęp uruchamiania pokazuje pasek w HUD („Starting the generator…”) — drugiego, nad generatorem, nie rysujemy (był podwójny status)

## Lampka i opary nad rurą — unshaded, widoczne w ciemności.
func _draw_lamp() -> void:
	if _hd != null:
		_draw_lamp_hd()
		return
	var blink := 0.5 + 0.5 * sin(_t * (14.0 if progress > 0.0 and not running else 3.0))
	var col := Color(0.35, 1.0, 0.45) if running else (Color(1.0, 0.7, 0.2, 0.5 + 0.5 * blink) if progress > 0.0 else Color(0.95, 0.22, 0.18, 0.55 + 0.45 * blink))
	_lamp.draw_circle(Vector2(8, -14), 1.6, col)
	_lamp.draw_circle(Vector2(8, -14), 3.4, Color(col, 0.18))
	if running:
		for i in 3:
			var f := fmod(_t * 0.9 + float(i) * 0.33, 1.0)
			_lamp.draw_circle(Vector2(9.5 + sin(_t * 3.0 + i) * 1.5, -28 - f * 22.0), 1.4 + f * 2.2, Color(0.8, 0.85, 0.8, 0.18 * (1.0 - f)))

## HD: lampka w oprawie na panelu (jądro + poświata), miękkie kłęby spalin z tłumika (tekstura dymu).
func _draw_lamp_hd() -> void:
	var blink := 0.5 + 0.5 * sin(_t * (14.0 if progress > 0.0 and not running else 3.0))
	var col := Color(0.35, 1.0, 0.45) if running else (Color(1.0, 0.7, 0.2, 0.5 + 0.5 * blink) if progress > 0.0 else Color(0.95, 0.22, 0.18, 0.55 + 0.45 * blink))
	var lp := Vector2(-4.0, -11.4) * HD_SCALE + Vector2(0.0, 0.0)
	_lamp.draw_circle(lp, 1.0, col)
	_lamp.draw_circle(lp, 2.3, Color(col, 0.28))
	_lamp.draw_circle(lp, 4.4, Color(col, 0.1))
	if running:
		var tex := SmokeCloud.puff_texture()
		var tip := Vector2(10.0, -26.5) * HD_SCALE
		for i in 5:
			var f := fposmod(_t * 0.7 + float(i) * 0.2, 1.0)
			var sz := 2.2 + f * 6.0
			var pos := tip + Vector2(sin(_t * 2.4 + float(i) * 1.7) * (1.0 + f * 3.0) + f * 3.0, -f * 22.0)
			_lamp.draw_texture_rect(tex, Rect2(pos.x - sz, pos.y - sz, sz * 2.0, sz * 2.0), false, Color(0.55, 0.58, 0.58, 0.32 * (1.0 - f)))
