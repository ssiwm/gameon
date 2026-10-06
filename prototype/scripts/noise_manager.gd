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
signal overcharge_stale                  ## wabik użyty drugi raz w tym samym miejscu — „przestaje działać"
signal flares_changed(n: int)

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
## Trafienie kolegi (friendly fire bez obrażeń): krzyk zaskoczenia. Mniej niż
## N_HURT, ale z cooldownem per ofiara (player.FF_COOLDOWN), więc ciągła seria
## przez kolegę kosztuje ~6,7 Uwagi/s — tyle co gorąca lufa M-83.
const N_FF := 4.0
const N_OVERCHARGE := 12.0

# Faza niepokoju: Stalker jeszcze śpi, ale słychać szept i HUD ostrzega (GDD §8.1)
const UNEASY_THRESHOLD := 40.0
const AWAKE_THRESHOLD := 60.0
const SLEEP_THRESHOLD := 30.0
const NightShift := preload("res://scripts/night_shift.gd")

var level: float = 0.0

## Flary (F): wspólna pula drużyny, jak ładunki Przesterowania (serwer rozstrzyga, klienci dostają stan).
const FLARE_MAX := 5
const FLARE_START := 3
var flares := FLARE_START

## Pamięć wrogów (1.7.5): gdzie ostatnio używano wabika Q (habituacja) i gdzie ostatnio strzelano
## (wataha, wracając do domu, sprawdza „gorące miejsca").
const Q_MEMORY := 120.0              ## s, przez które powtórka wabika w tym samym miejscu jest „znana"
const Q_RADIUS := 140.0
const N_OVERCHARGE_STALE := 3.0      ## tyle Uwagi kosztuje „zwietrzały" wabik (bez przekierowania)
const HOT_SPOT_MIN := 2.0            ## od tej głośności zdarzenie liczy się jako „strzelanina"
const HOT_SPOT_MAX := 6
var hot_spots: Array = []            ## Vector3(x, y, czas)
var _q_log: Array = []               ## Vector3(x, y, czas)
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
## Gdzie ostatnio użyto Q (serwer) — Żyła daje się tam odciągnąć (boss.gd).
var last_overcharge_pos := Vector2.ZERO

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
	last_overcharge_pos = pos
	if not _regen_needed:
		_regen_needed = true
		_regen_timer = OVERCHARGE_REGEN
	# habituacja: wabik użyty ponownie w tym samym miejscu (Q_RADIUS) w ciągu Q_MEMORY s nie przekierowuje
	# nikogo — kosztuje ładunek i trochę Uwagi, a wrogowie „już to znają". Zmusza do zmiany miejsca.
	var now_s := Time.get_ticks_msec() / 1000.0
	var stale := false
	for e in _q_log:
		var v: Vector3 = e
		if now_s - v.z < Q_MEMORY and Vector2(v.x, v.y).distance_to(pos) < Q_RADIUS:
			stale = true
	_q_log.append(Vector3(pos.x, pos.y, now_s))
	if _q_log.size() > 6:
		_q_log.pop_front()
	if stale:
		_apply(N_OVERCHARGE_STALE, pos, false)
		overcharge_stale.emit()
		if has_network():
			_stale_fx.rpc()
	else:
		_apply(N_OVERCHARGE, pos)
	# przekieruj: last_noise_pos już = pos, stalker pójdzie tutaj (GDD §8.4)
	if has_network():
		_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)
	overcharge_used.emit(overcharge_charges)
	print("[NOISE] overcharge used, charges=%d level=%.0f" % [overcharge_charges, level])
	return true

## Cel główny wykonany: +1 ładunek Przesterowania od razu (GDD §8.4).
func objective_bonus() -> void:
	if not is_server():
		return
	add_flare()
	overcharge_charges = mini(OVERCHARGE_MAX, overcharge_charges + 1)
	if overcharge_charges >= OVERCHARGE_MAX:
		_regen_needed = false
	_push_now()
	overcharge_used.emit(overcharge_charges)

## Udana ekstrakcja: teren cichnie (Uwaga 0, Stalker śpi).
func calm() -> void:
	if not is_server():
		return
	level = 0.0
	stalker_awake = false
	level_changed.emit(level, stalker_awake)
	_push_now()

func _push_now() -> void:
	if has_network():
		_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)

## Ile sekund minęło od ostatniego Q (serwer). Boty wstrzymują wtedy ogień.
func seconds_since_overcharge() -> float:
	return Time.get_ticks_msec() / 1000.0 - _last_overcharge

func reset_mission() -> void:
	_last_overcharge = -INF
	level = NightShift.start_noise(20.0)
	stalker_awake = level >= NightShift.awake_threshold(AWAKE_THRESHOLD)
	last_noise_pos = Vector2.ZERO
	overcharge_charges = 2
	flares = FLARE_START
	hot_spots.clear()
	_q_log.clear()
	_regen_needed = false
	_regen_timer = 0.0
	_server_last_active = Time.get_ticks_msec() / 1000.0
	flares_changed.emit(flares)
	level_changed.emit(level, stalker_awake)
	overcharge_used.emit(overcharge_charges)

## Krzyk gracza (voice.gd, GDD §8.2): hałas + przyciągnięcie wrogów w promieniu 25 m.
func add_scream(amount: float, pos: Vector2) -> void:
	if is_server():
		_apply_scream(amount, pos)
	else:
		_report_scream.rpc_id(1, amount, pos)

@rpc("any_peer", "call_remote", "reliable")
func _report_scream(amount: float, pos: Vector2) -> void:
	if multiplayer.is_server():
		_apply_scream(amount, pos)

func _apply_scream(amount: float, pos: Vector2) -> void:
	_apply(clampf(amount, 0.0, 30.0), pos)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("hear_scream"):
			e.hear_scream(pos)
	if has_network():
		_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)

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

func _apply(amount: float, pos: Vector2, track := true) -> void:
	if amount > 0.0:
		_server_last_active = Time.get_ticks_msec() / 1000.0
	if amount > 0.0 and track:
		last_noise_pos = pos
		last_noise_amount = amount          # surowa głośność: próg budzenia wrogów nie zależy od trudności
		noise_serial += 1
		if amount >= HOT_SPOT_MIN:
			_note_hot_spot(pos)
	level = clampf(level + (amount * Difficulty.m("noise") * NightShift.noise_mult() if amount > 0.0 else amount), 0.0, MAX_LEVEL)
	if level >= NightShift.awake_threshold(AWAKE_THRESHOLD):
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
		if stalker_awake and level <= NightShift.sleep_threshold(SLEEP_THRESHOLD):
			stalker_awake = false
			print("[NOISE] level %.0f -> stalker asleep" % level)
		level_changed.emit(level, stalker_awake)

	if has_network():
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 0.1
			_push.rpc(level, last_noise_pos, stalker_awake, overcharge_charges)


# ---------------------------------------------------------------- pamięć: gorące miejsca

func _note_hot_spot(pos: Vector2) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	for i in hot_spots.size():
		var v: Vector3 = hot_spots[i]
		if Vector2(v.x, v.y).distance_to(pos) < 80.0:
			hot_spots[i] = Vector3(pos.x, pos.y, now_s)
			return
	hot_spots.append(Vector3(pos.x, pos.y, now_s))
	if hot_spots.size() > HOT_SPOT_MAX:
		hot_spots.pop_front()

## Najświeższe „gorące miejsce" w promieniu `radius` od `from` nie starsze niż `max_age` s — albo null.
func hot_spot_near(from: Vector2, radius: float, max_age: float) -> Variant:
	var now_s := Time.get_ticks_msec() / 1000.0
	var best: Variant = null
	var best_t := -INF
	for e in hot_spots:
		var v: Vector3 = e
		if now_s - v.z > max_age or Vector2(v.x, v.y).distance_to(from) > radius:
			continue
		if v.z > best_t:
			best_t = v.z
			best = Vector2(v.x, v.y)
	return best

@rpc("authority", "call_remote", "reliable")
func _stale_fx() -> void:
	overcharge_stale.emit()

# ---------------------------------------------------------------- flary

func add_flare(n := 1) -> void:
	if not is_server():
		return
	flares = mini(FLARE_MAX, flares + n)
	_push_flares()

func _push_flares() -> void:
	flares_changed.emit(flares)
	if has_network():
		_flares_rpc.rpc(flares)

@rpc("authority", "call_remote", "reliable")
func _flares_rpc(n: int) -> void:
	flares = n
	flares_changed.emit(n)

## Rzut flarą (F). Serwer sprawdza pulę i tworzy flarę u wszystkich peerów (level.spawn_flare).
func request_flare(pos: Vector2, vel: Vector2) -> void:
	if is_server():
		_throw_flare(pos, vel)
	else:
		_flare_request.rpc_id(1, pos, vel)

@rpc("any_peer", "call_remote", "reliable")
func _flare_request(pos: Vector2, vel: Vector2) -> void:
	if is_server():
		_throw_flare(pos, vel)

func _throw_flare(pos: Vector2, vel: Vector2) -> void:
	if flares <= 0:
		return
	flares -= 1
	_push_flares()
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		lvl.spawn_flare(pos, vel.limit_length(420.0))
