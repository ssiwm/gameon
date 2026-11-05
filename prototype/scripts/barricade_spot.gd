extends Node2D
## Miejsce przybijania desek (DESTRUCTION_PLAN.md D2b) przy przegrodzie z desek: rozbite deski `%` i pusty otwór `:` (level.gd `_spawn_walls`).
##
## Gracz stoi przy otworze i TRZYMA [E] przez NAIL_TIME s — przybija jedną deskę (level.gd `nail_board`: koszt, przegroda, sieć); trzyma
## dalej — przybija następną, aż do kompletu (level.gd `BOARDS`). Młotek stuka, więc praca to hałas: Stalker i wrogowie idą na stukanie.
## Puszczenie klawisza przerywa deskę (postęp przepada). Jak generator: peer zgłasza serwerowi tylko „trzymam / puściłem” (`_work_rpc`),
## serwer sam sprawdza zasięg, życie i koszt; postęp idzie do klientów przez `_sync`. Węzeł stoi przez całą misję — przegroda znika
## i wraca, miejsce zostaje. Stopy w (0, 0) jak przegroda.

const NAIL_TIME := 2.0              ## s trzymania [E] na jedną deskę
const REACH_X := 30.0               ## px od środka otworu: stoisz tuż obok albo w nim
const REACH_Y := 20.0
const WORK_NOISE_PER_S := 1.2       ## Uwaga na sekundę stukania (deska ≈ +2,4, z ostatnimi uderzeniami level.gd NAIL_NOISE ≈ +4)
const NOISE_CHUNK := 0.3            ## hałas pracy porcjami, nie co klatkę
const KNOCK_EVERY := 0.4            ## s między stuknięciami młotka (dźwięk u każdego peera, z postępu)
const SYNC_INTERVAL := 0.1

var wall_name := ""
var progress := 0.0
var local_in_range := false         ## lokalny człowiek stoi przy otworze, w którym brakuje desek (HUD pokazuje podpowiedź)
var local_reason := ""              ## level.gd `nail_reason` dla podpowiedzi: ok / blocked / nomat

var _holding := false               ## to, co ten peer ostatnio zgłosił serwerowi
var _workers := {}                  ## serwer: nazwa gracza -> true
var _noise_acc := 0.0
var _sync_t := 0.0
var _sent := -1.0
var _last_p := 0.0
var _rise_t := 0.0
var _knock_t := 0.0

func _ready() -> void:
	add_to_group("barricade_spots")

func _in_reach(p: Vector2, mult := 1.0) -> bool:
	return absf(p.x - global_position.x) <= REACH_X * mult and absf(p.y - global_position.y) <= REACH_Y * mult

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

## Deski w przegrodzie teraz (0 — otwór wolny).
func boards() -> int:
	return int(get_parent().boards_of(wall_name))

# ---------------------------------------------------------------- każdy peer: czy MÓJ gracz przybija

func _update_local() -> void:
	var me := _local_human()
	var near: bool = me != null and not me.dead and _in_reach(me.global_position)
	local_reason = String(get_parent().nail_reason(wall_name)) if near else ""
	local_in_range = near and local_reason != "full" and local_reason != "invalid"
	var want := false
	if local_in_range and local_reason == "ok" and Input.is_action_pressed("interact"):
		# ratowanie kolegi i podnoszenie broni mają pierwszeństwo przed młotkiem
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
	if on:
		_workers[str(peer_id)] = true
	else:
		_workers.erase(str(peer_id))

## Test i bot: serwer traktuje gracza `peer_id` jak trzymającego [E] (dalej sprawdza zasięg i życie).
func force_worker(peer_id: int, on: bool) -> void:
	if NoiseMgr.is_server():
		_set_worker(peer_id, on)

func _process(delta: float) -> void:
	# stukanie młotka u każdego peera: postęp rośnie (u klienta skokami co SYNC_INTERVAL, więc z krótkim zapasem)
	if progress > _last_p:
		_rise_t = 0.25
	_last_p = progress
	_rise_t = maxf(0.0, _rise_t - delta)
	if _rise_t > 0.0 and progress > 0.0:
		_knock_t -= delta
		if _knock_t <= 0.0:
			_knock_t = KNOCK_EVERY
			Audio.play_variant_at("hammer_nail", 3, global_position + Vector2(0, -14), Audio.BUS_WORLD, 0.0)   # młotek w gwóźdź (B3)
	else:
		_knock_t = 0.0

# ---------------------------------------------------------------- serwer

func _physics_process(delta: float) -> void:
	_update_local()
	if not NoiseMgr.is_server():
		return
	_validate_workers()
	var lvl := get_parent()
	if not _workers.is_empty() and String(lvl.nail_reason(wall_name)) == "ok":
		progress = minf(1.0, progress + delta / NAIL_TIME)
		_noise_acc += WORK_NOISE_PER_S * delta
		if _noise_acc >= NOISE_CHUNK:
			NoiseMgr.add_noise(_noise_acc, global_position + Vector2(0, -14), "barricade")
			_noise_acc = 0.0
		if progress >= 1.0:
			lvl.nail_board(wall_name)
			progress = 0.0
	elif progress > 0.0:
		progress = 0.0                                   # puszczony klawisz albo brak desek: deska przepada
	_sync_t -= delta
	if not is_equal_approx(progress, _sent) and (_sync_t <= 0.0 or progress == 0.0):
		_sync_t = SYNC_INTERVAL
		_sent = progress
		if NoiseMgr.has_network():
			_sync.rpc(progress)

## Serwer sam sprawdza, czy zgłaszający nadal stoi przy otworze, żyje i istnieje.
func _validate_workers() -> void:
	if _workers.is_empty():
		return
	var alive := {}
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and not p.is_queued_for_deletion() and _in_reach(p.global_position, 1.4):
			alive[String(p.name)] = true
	for k in _workers.keys():
		if not alive.has(k):
			_workers.erase(k)

## Restart misji i punkt kontrolny (level.gd `_reset_breakables_rpc`): przerwana praca przepada.
func reset_spot() -> void:
	progress = 0.0
	_last_p = 0.0
	_noise_acc = 0.0
	_workers.clear()
	_sent = -1.0

# ---------------------------------------------------------------- klienci

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(p: float) -> void:
	progress = p
