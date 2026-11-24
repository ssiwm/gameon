extends Node2D
## Zwłoki w świecie (MIMIC_PLAN.md §4, M3–M4): ciało z Patrolu Siedem, obsługi radiostacji albo górników, leżące w punkcie CORPSES z danych
## mapy (level.gd: [kolumna, rząd, ułożenie, strój, flagi]). Bez kolizji i bez wpływu na nawigację — ciało to rekwizyt, który można przeszukać.
##
## Przeszukanie: człowiek TRZYMA [E] przy ciele przez SEARCH_TIME s; puszczenie przerywa (postęp od zera). Szelest to mały hałas
## (RUSTLE_PER_S). Łup wg D3: ok. LOOT_CHANCE drobnego łupu (złom, naboje albo bateria 4,5 V), reszta — nic. Przeszukane zostaje
## przeszukane po wipe'ie (jak znaleziona skrytka); nowa próba misji kładzie zwłoki od nowa. Bot nie przeszukuje — zwłoki to decyzja człowieka.
## Na 1.1 ciała z flagą `tag` leżą przy nieśmiertelnikach patrolu: nieśmiertelnik podnosi się jak dotąd, ciało prowadzi do niego wzrok.
##
## Autorytet: serwer (postęp, łup, stan „przeszukane”); klienci dostają postęp przez _sync, a przeszukanie przez _sync_searched.
## Każdy gracz zgłasza tylko „trzymam / puściłem” (_work_rpc), serwer sam sprawdza zasięg, życie i to, że to człowiek — jak sejf (strongbox.gd).
## Widok 3D (view3d.gd `_sync_corpses`, corpse3d.gd) czyta `outfit`, `pose`, `flip` i `searched`.

const SessionLog := preload("res://scripts/session_log.gd")
const Weapons := preload("res://scripts/weapons.gd")

const SEARCH_TIME := 1.2             ## s trzymania [E] (jak wyjmowanie taśmy, K4b — krócej, bo to tylko kieszenie)
const REACH_X := 24.0                ## px od środka ciała (ciało ma ok. 26 px długości)
const REACH_Y := 30.0
const RUSTLE_PER_S := 0.6            ## Uwaga na sekundę przeszukiwania (szelest, ciszej niż kroki biegu)
const NOISE_CHUNK := 0.3
const SYNC_INTERVAL := 0.1
const LOOT_CHANCE := 0.6             ## D3: drobny łup w ok. 60% ciał, reszta — nic
const SCRAP := Vector2i(3, 6)        ## złom z kieszeni
## Rodzaj łupu, gdy coś jest: [rodzaj, waga].
const LOOT_TABLE := [["scrap", 0.45], ["ammo", 0.3], ["battery", 0.25]]

var index := 0                       ## numer na mapie (dziennik `corpse_search`, `id`)
var outfit := "patrol"
var pose := "back"
var flip := false
var flags := {}
var searched := false
var progress := 0.0
var local_in_range := false          ## lokalny człowiek stoi w zasięgu (HUD pokazuje podpowiedź)
var force_loot := ""                 ## testy: wymuszony wynik losowania („none” albo rodzaj z LOOT_TABLE)

var _holding := false
var _workers := {}
var _sync_t := 0.0
var _noise_acc := 0.0
var _sent_progress := -1.0
var _start_ms := 0

func _ready() -> void:
	add_to_group("corpses")

func _in_reach(p: Vector2, mult := 1.0) -> bool:
	return absf(p.x - global_position.x) <= REACH_X * mult and absf(p.y - global_position.y) <= REACH_Y * mult

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- każdy peer: czy MÓJ gracz przeszukuje

func _update_local() -> void:
	var me := _local_human()
	var near: bool = me != null and not searched and not me.dead and _in_reach(me.global_position)
	local_in_range = near
	var want := false
	if near and Input.is_action_pressed("interact"):
		# ratowanie kolegi i podnoszenie broni mają pierwszeństwo przed zwłokami
		want = me.revive_hint() == "" and me.weapons.nearby_weapon_item() == null
	if want == _holding:
		return
	_holding = want
	if want:
		Audio.play_variant_at("foley_gear", 3, global_position, Audio.BUS_WORLD, -6.0, randf_range(0.85, 1.0))   # szelest kieszeni
	if NoiseMgr.is_server():
		set_worker(NoiseMgr.local_id(), want)
	else:
		_work_rpc.rpc_id(1, want)

@rpc("any_peer", "call_remote", "reliable")
func _work_rpc(on: bool) -> void:
	if multiplayer.is_server():
		set_worker(multiplayer.get_remote_sender_id(), on)

## Serwer: gracz `peer_id` zaczyna albo przestaje przeszukiwać (testy wołają to wprost). Puszczenie przerywa — postęp od zera.
func set_worker(peer_id: int, on: bool) -> void:
	if on:
		_workers[str(peer_id)] = true
	else:
		_workers.erase(str(peer_id))
		if _workers.is_empty() and not searched:
			progress = 0.0

# ---------------------------------------------------------------- serwer

func _physics_process(delta: float) -> void:
	_update_local()
	if not NoiseMgr.is_server() or searched:
		return
	if _validate_workers() > 0:
		if progress <= 0.0:
			_start_ms = Time.get_ticks_msec()
		progress = minf(1.0, progress + delta / SEARCH_TIME)
		_noise_acc += RUSTLE_PER_S * delta
		if _noise_acc >= NOISE_CHUNK:
			NoiseMgr.add_noise(_noise_acc, global_position, "corpse")
			_noise_acc = 0.0
		if progress >= 1.0:
			_finish_search()
	else:
		progress = 0.0
	_sync_t -= delta
	if _sync_t <= 0.0 and not is_equal_approx(progress, _sent_progress):
		_sync_t = SYNC_INTERVAL
		_sent_progress = progress
		if NoiseMgr.has_network():
			_sync.rpc(progress)

## Liczy przeszukujących, którzy są żywymi ludźmi w zasięgu (z zapasem). Bot, martwy i odchodzący gracz wypadają ze zgłoszeń; człowiek poza
## zasięgiem zostaje zgłoszony, ale się nie liczy — pozycja klienta dochodzi do serwera z opóźnieniem, a klient zgłasza „trzymam” tylko raz
## (sam puszcza, gdy u siebie wyjdzie z zasięgu). Bez nikogo w zasięgu postęp wraca do zera (jak puszczenie).
func _validate_workers() -> int:
	if _workers.is_empty():
		return 0
	var alive := {}
	var near := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and not p.is_queued_for_deletion():
			alive[String(p.name)] = true
			if _workers.has(String(p.name)) and _in_reach(p.global_position, 1.4):
				near += 1
	for k in _workers.keys():
		if not alive.has(k):
			_workers.erase(k)
	return near

## Wynik losowania łupu (D3): „none” albo rodzaj z LOOT_TABLE.
static func roll_loot(rng: RandomNumberGenerator) -> String:
	if rng.randf() >= LOOT_CHANCE:
		return "none"
	var r := rng.randf()
	for row in LOOT_TABLE:
		r -= float(row[1])
		if r <= 0.0:
			return String(row[0])
	return String(LOOT_TABLE[0][0])

func _finish_search() -> void:
	var who: Array = _workers.keys()
	_workers.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var loot := force_loot if force_loot != "" else roll_loot(rng)
	var lv := get_tree().get_first_node_in_group("level")
	var at := global_position + Vector2(rng.randf_range(-6.0, 6.0), -14.0)
	var amount := 0
	if lv != null:
		match loot:
			"scrap":
				amount = rng.randi_range(SCRAP.x, SCRAP.y)
				lv.spawn_item("scrap", 0, at, amount)
			"ammo":
				var w := Arsenal.pick_drop_weapon()
				if w >= 0:
					amount = maxi(1, int(Weapons.def(w).pickup_rounds * 0.5))
					lv.spawn_item("ammo", w, at, amount)
				else:                                     # zapasy pełne (albo broń bez amunicji) — garść złomu zamiast naboi
					loot = "scrap"
					amount = rng.randi_range(SCRAP.x, SCRAP.y)
					lv.spawn_item("scrap", 0, at, amount)
			"battery":
				lv.spawn_item("battery", 0, at)
	var held := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	var by := get_tree().current_scene.get_node_or_null("Players/" + String(who[0])) if not who.is_empty() and get_tree().current_scene != null else null
	SessionLog.event("corpse_search", {"map": String(lv.map_id) if lv != null else "", "id": index, "loot": loot, "amount": amount,
		"hold": snappedf(held, 0.1), "who": "P%d" % int(by.display_id) if by != null else "?", "tag": bool(flags.get("tag", false)),
		"pos": SessionLog.xy(global_position)})
	print("[CORPSE] %s searched: %s" % [name, loot])
	if NoiseMgr.has_network():
		_sync_searched.rpc(true, loot)
	_set_searched(true, loot)

## Nowa próba misji na tej samej mapie (main.gd `_restart_mission(true)`): zwłoki znów nieprzeszukane. Wipe ich nie rusza.
func reset_corpse() -> void:
	if not NoiseMgr.is_server():
		return
	progress = 0.0
	_sent_progress = -1.0
	_workers.clear()
	_noise_acc = 0.0
	if NoiseMgr.has_network():
		_sync_searched.rpc(false, "")
		_sync.rpc(0.0)
	_set_searched(false, "")

## Dołączający gracz dostaje przeszukane ciało bez efektów.
func send_state_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and searched:
		_sync_searched.rpc_id(peer_id, true, "")

# ---------------------------------------------------------------- klienci

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(p: float) -> void:
	progress = p

@rpc("authority", "call_remote", "reliable")
func _sync_searched(on: bool, loot: String) -> void:
	_set_searched(on, loot)

func _set_searched(on: bool, loot: String) -> void:
	var was := searched
	searched = on
	progress = 1.0 if on else 0.0
	if not on or was or loot == "":
		return
	Audio.play_variant_at("foley_gear", 3, global_position, Audio.BUS_WORLD, -4.0, randf_range(0.9, 1.05))
	var me := _local_human()
	if loot == "none" and me != null and _in_reach(me.global_position, 1.6):
		Msg.post("corpse.%s" % name, Msg.Ch.TOAST, tr("Nothing useful on the body"), {"style": Msg.Style.INFO, "ttl": 2.0, "prio": 20})
