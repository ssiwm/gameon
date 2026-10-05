extends Node
## Serwerowy (autorytatywny) menedżer hałasu + zasobu Przesterowania.
## Gracze raportują hałas przez add_noise(); serwer sumuje i rozsyła wartość.
##
## Kluczowe liczby (GDD §8.1/§8.4) — pochodzą z testów prototypu, nie zgadywania:
##   DECAY_SILENT  cicho (kucanie/chód, brak strzałów) → głośnik milknie szybko
##   DECAY_LOUD    w akcji → hałas nie znika natychmiast
##   Przesterowanie daje Uwagę CELOWO i przekierowuje stalkera na swoje źródło.

signal level_changed(level: float, awake: bool)
signal overcharge_used(charges: int)

const MAX_LEVEL := 100.0

# Dekrementy (GDD §8.1). Prototyp v1 miał jeden (7/s) i pętla ciszy była nie do przejścia.
const DECAY_SILENT := 4.0
const DECAY_LOUD := 1.5

# Wartości pojedynczych zdarzeń (GDD §8.1). Strzały bierzemy z weapons.gd
# (model rozgrzania), tu zostają tylko zdarzenia niezwiązane z bronią.
# Te same liczby obowiązują w trybie solo i sieciowym — żadnego „połowienia\".
const N_RUN_PER_SEC := 0.5
const N_SHOOT_SILENT := 1.0
const N_GRENADE := 15.0
const N_SCREAM := 20.0
const N_HURT := 6.0
const N_OVERCHARGE := 12.0

# Faza niepokoju: Stalker jeszcze śpi, ale słychać szept i HUD ostrzega (GDD §8.1)
const UNEASY_THRESHOLD := 40.0
const AWAKE_THRESHOLD := 60.0
const SLEEP_THRESHOLD := 30.0

var level: float = 0.0
var last_noise_pos := Vector2.ZERO
var last_noise_amount := 0.0
## Rośnie przy każdym zdarzeniu hałasu (tylko serwer). Wrogowie i Stalker
## porównują go z własnym, żeby wiedzieć, że usłyszeli COŚ NOWEGO.
var noise_serial := 0
var stalker_awake := false

# Przesterowanie: ładunek startuje w misji, regeneruje się, max 3 (GDD §8.4)
var overcharge_charges := 2
const OVERCHARGE_MAX := 3
const OVERCHARGE_REGEN := 45.0

var _regen_timer := 0.0
var _regen_needed := false
var _sync_timer := 0.0
var _server_last_active := 0.0
## Czas (s, zegar silnika) ostatniego udanego Przesterowania — tylko serwer.
var _last_overcharge := -INF

func has_network() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_server() -> bool:
	return not has_network() or multiplayer.is_server()

func local_id() -> int:
	if not has_network():
		return 1
	return multiplayer.get_unique_id()

## Czy lokalny gracz jest „cichy": kucanie/chód i brak strzału w ostatnich 1,5 s.
func is_local_player_quiet() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return now - _server_last_active > 1.5

func mark_local_activity() -> void:
	if not is_server():
		return
	_server_last_active = Time.get_ticks_msec() / 1000.0

func add_noise(amount: float, pos: Vector2) -> void:
	if is_server():
		_apply(amount, pos)
		if has_network():
			_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)
	else:
		_report.rpc_id(1, amount, pos)

## Przesterowanie: celowy +12 Uwagi i przekierowanie stalkera na to źródło.
## Zwraca true, jeśli ładunek był dostępny.
func use_overcharge(pos: Vector2) -> bool:
	if not is_server():
		return false
	if overcharge_charges <= 0:
		return false
	overcharge_charges -= 1
	_last_overcharge = Time.get_ticks_msec() / 1000.0
	if not _regen_needed:
		_regen_needed = true
		_regen_timer = OVERCHARGE_REGEN
	_apply(N_OVERCHARGE, pos)
	# przekieruj: last_noise_pos już = pos, stalker pójdzie tutaj (GDD §8.4)
	if has_network():
		_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)
	overcharge_used.emit(overcharge_charges)
	print("[NOISE] overcharge used, charges=%d level=%.0f" % [overcharge_charges, level])
	return true

## Ile sekund minęło od ostatniego Q (serwer). Boty wstrzymują wtedy ogień.
func seconds_since_overcharge() -> float:
	return Time.get_ticks_msec() / 1000.0 - _last_overcharge

func reset_mission() -> void:
	_last_overcharge = -INF
	level = 20.0
	stalker_awake = false
	last_noise_pos = Vector2.ZERO
	overcharge_charges = 2
	_regen_needed = false
	_regen_timer = 0.0
	_server_last_active = Time.get_ticks_msec() / 1000.0
	level_changed.emit(level, stalker_awake)
	overcharge_used.emit(overcharge_charges)

@rpc("any_peer", "call_remote", "reliable")
func _report(amount: float, pos: Vector2) -> void:
	if multiplayer.is_server():
		_apply(amount, pos)

@rpc("authority", "call_remote", "unreliable_ordered")
func _push(new_level: float, noise_pos: Vector2, awake: bool, charges: int) -> void:
	level = new_level
	last_noise_pos = noise_pos
	stalker_awake = awake
	overcharge_charges = charges
	level_changed.emit(level, awake)
	overcharge_used.emit(charges)

func _apply(amount: float, pos: Vector2) -> void:
	if amount > 0.0:
		last_noise_pos = pos
		last_noise_amount = amount
		noise_serial += 1
		_server_last_active = Time.get_ticks_msec() / 1000.0
	level = clampf(level + amount, 0.0, MAX_LEVEL)
	if level >= AWAKE_THRESHOLD:
		stalker_awake = true
	level_changed.emit(level, stalker_awake)

func _process(delta: float) -> void:
	if not is_server():
		return

	# regen ładunku przesterowania
	if _regen_needed and overcharge_charges < OVERCHARGE_MAX:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			overcharge_charges += 1
			_regen_timer = OVERCHARGE_REGEN if overcharge_charges < OVERCHARGE_MAX else 0.0
			if overcharge_charges >= OVERCHARGE_MAX:
				_regen_needed = false
			overcharge_used.emit(overcharge_charges)

	if level > 0.0:
		var decay := DECAY_SILENT if is_local_player_quiet() else DECAY_LOUD
		level = maxf(0.0, level - decay * delta)
		if stalker_awake and level <= SLEEP_THRESHOLD:
			stalker_awake = false
			print("[NOISE] level %.0f -> stalker asleep" % level)
		level_changed.emit(level, stalker_awake)

	if has_network():
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 0.1
			_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)
