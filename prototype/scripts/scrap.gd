extends Node
## Autoload „Scrap": złom — waluta drużyny (GDD §10.1). Portfel jest WSPÓLNY, autorytet ma serwer, klienci dostają stan przez sync.
##
## Dwa stany: `loot` to złom zebrany w TEJ misji (jeszcze nie bezpieczny) i `bank` — portfel, z którego płaci się w warsztacie.
## Udana ekstrakcja przenosi loot do banku (`bank_loot`); wipe albo restart misji kasuje loot (GDD §4: „tracicie łup misji") —
## bank zostaje. Bank zapisuje się u hosta w user://progress.cfg i wraca przy starcie hostowania. Nocny Dyżur nie daje złomu.
##
## Źródła: wrogowie (enemy.gd, szansa), skrytki na mapie (znacznik „u", pickup „scrap"), bonus za misję (mission.gd).

signal changed
## Wynik zakupu w warsztacie (u kupującego): id broni, powodzenie, kod: "ok" | "poor" | "owned" | "later" | "invalid".
signal supply_result(kind: String, ok: bool, reason: String)    ## zakup zaopatrzenia: ok / poor / full / invalid / off
signal purchase_result(weapon: int, ok: bool, reason: String)    ## kody zakupu broni: ok/poor/owned/later/invalid
signal part_result(id: String, ok: bool, reason: String)         ## zakup części (parts.gd): ok/poor/owned/locked/invalid
signal clean_result(weapon: int, ok: bool, reason: String)        ## czyszczenie broni przy ławie: ok/poor/invalid
const CLEAN_MAX := 10             ## czyszczenie kosztuje 1 złom za każde rozpoczęte 10 % zużycia (najwyżej tyle)

const NightShift := preload("res://scripts/night_shift.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const Perks := preload("res://scripts/perks.gd")
const Throwables := preload("res://scripts/throwables.gd")

const SAVE_PATH := "user://progress.cfg"

## Stałe balansu w jednym miejscu — do strojenia po playtestach.
const DROP_CHANCE := 0.35              ## szansa na złom z trupa; ile złomu daje rodzaj — pole `scrap` w enemy_defs.gd
const CACHE_VALUE := 6               ## skrytka z mapy
const BOSS_VALUE := 30
const STASH_VALUE := 20               ## ukryta skrytka (cel poboczny misji 1.1)
const BONUS_CLEAR := 30               ## za ukończenie misji
const BONUS_SIDE := 15                ## za cel poboczny
const BONUS_NO_DOWNS := 10            ## za misję bez upadków

## Warsztat (faza B): ceny broni z kryjówki. Broń spoza tej tabeli i spoza LATER jest odblokowana od początku (M-83, SPREAD-12, P-83, maczeta).
const PRICES := {Weapons.LR7: 150, Weapons.HKM9: 200, Weapons.SRUT8: 250, Weapons.GNIEW4: 300, Weapons.WIDMO1: 400}
const LATER := [Weapons.SOKOL6, Weapons.CIEGNO6]       ## stojaki zablokowane do późniejszych stref
## Bronie-trofea: dostępne w warsztacie dopiero po ukończeniu wskazanej misji (id mapy). SPECTER-1 → po Pijawce (B1).
const REWARDS := {Weapons.WIDMO1: "z1_b1"}

var bank := 0
var loot := 0
var parts: Dictionary = {}            ## id części (parts.gd) → true: odblokowane przez drużynę (zapis u hosta); montaż — Profile.fits
var unlocked: Dictionary = {}         ## id broni → true: kupione w warsztacie (zapis u hosta)
var trophies: Dictionary = {}         ## id misji (boss) → true: ukończona, odblokowuje broń-trofeum (zapis u hosta)
var last_gain := 0                    ## ile trafiło do banku po ostatniej misji (karta wyniku, ściana wyników)
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie czytają ani nie nadpisują prawdziwego zapisu

func _ready() -> void:
	load_progress()
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if NoiseMgr.is_server():
			_sync.rpc_id(id, bank, loot, last_gain, unlocked.keys(), parts.keys(), trophies.keys()))

## Złom nie obowiązuje w Nocnym Dyżurze (osobna seria z własnymi zasadami).
func enabled() -> bool:
	return not NightShift.active

# ---------------------------------------------------------------- serwer

## Zebrany złom wpada do łupu misji.
func add_loot(n: int) -> void:
	if not NoiseMgr.is_server() or n <= 0 or not enabled():
		return
	loot += n
	_push()

## Ekstrakcja udana: łup + bonusy do banku, zapis na dysk. Zwraca ile weszło.
func bank_loot(bonus: int) -> int:
	if not NoiseMgr.is_server() or not enabled():
		return 0
	var gain := loot + maxi(0, bonus)
	bank += gain
	last_gain = gain
	loot = 0
	save_progress()
	_push()
	return gain

## Wipe / restart: łup przepada, bank zostaje.
func reset_loot() -> void:
	if not NoiseMgr.is_server():
		return
	if loot != 0:
		loot = 0
		_push()

## Wydatek z banku (warsztat, faza B). false = za mało.
func spend(n: int) -> bool:
	if not NoiseMgr.is_server() or n < 0 or bank < n:
		return false
	bank -= n
	save_progress()
	_push()
	return true

# ---------------------------------------------------------------- warsztat: odblokowanie broni

func _set_parts(ids: Array) -> void:
	parts.clear()
	for id in ids:
		if Parts.is_valid(String(id)):
			parts[String(id)] = true

## Ile części broni `w` drużyna odblokowała (kafel warsztatu, kodeks).
func parts_owned(w: int) -> int:
	var n := 0
	for p in Parts.of(String(Weapons.def(w).key)):
		if parts.has(String(p["id"])):
			n += 1
	return n

## Broń-trofeum, której misja jeszcze nie jest ukończona.
func is_gated(w: int) -> bool:
	return REWARDS.has(w) and not trophies.has(String(REWARDS[w]))

## Broń niedostępna do kupienia: późniejsza strefa albo trofeum bez ukończonej misji.
func is_later(w: int) -> bool:
	return LATER.has(w) or is_gated(w)

## Misja ukończona (boss): odblokowuje broń-trofeum. Serwer; zapis i sync.
func add_trophy(map_id: String) -> void:
	if not NoiseMgr.is_server() or not enabled() or trophies.has(map_id):
		return
	trophies[map_id] = true
	save_progress()
	_push()

## Czemu stojak jest zablokowany (HUD, katalog, warsztat).
func lock_text(w: int) -> String:
	if is_gated(w):
		return "reward for the Leech"
	var price := price_of(w)
	return (tr("%d scrap at the workshop") % price) if price > 0 else "available in a later zone"

## Czy broń z kryjówki jest dostępna (stojak odblokowany).
func is_unlocked(w: int) -> bool:
	if is_later(w):
		return false
	return not PRICES.has(w) or unlocked.has(w)

func price_of(w: int) -> int:
	return int(PRICES.get(w, -1))

## Gracz (dowolny peer) prosi o zakup broni. Serwer sprawdza cenę i stan portfela.
func request_buy(w: int) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_buy_server(w, NoiseMgr.local_id())
	else:
		_buy_rpc.rpc_id(1, w)

@rpc("any_peer", "call_remote", "reliable")
func _buy_rpc(w: int) -> void:
	if NoiseMgr.is_server():
		_buy_server(w, multiplayer.get_remote_sender_id())

func _buy_server(w: int, peer_id: int) -> void:
	var reason := "ok"
	if not Weapons.is_valid(w):
		reason = "invalid"
	elif LATER.has(w):
		reason = "later"
	elif is_gated(w):
		reason = "reward"
	elif not PRICES.has(w):
		reason = "invalid"
	elif unlocked.has(w):
		reason = "owned"
	elif not spend(int(PRICES[w])):
		reason = "poor"
	else:
		unlocked[w] = true
		save_progress()
		_push()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		purchase_result.emit(w, reason == "ok", reason)
	else:
		_result_rpc.rpc_id(peer_id, w, reason)

@rpc("authority", "call_remote", "reliable")
func _result_rpc(w: int, reason: String) -> void:
	purchase_result.emit(w, reason == "ok", reason)

## Zakup sztuki zaopatrzenia (granat, mina, apteczka…) do wspólnego zapasu drużyny — zakładka SUPPLIES w warsztacie.
func request_buy_supply(kind: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_buy_supply_server(kind, NoiseMgr.local_id())
	else:
		_buy_supply_rpc.rpc_id(1, kind)

@rpc("any_peer", "call_remote", "reliable")
func _buy_supply_rpc(kind: String) -> void:
	if NoiseMgr.is_server():
		_buy_supply_server(kind, multiplayer.get_remote_sender_id())

func _buy_supply_server(kind: String, peer_id: int) -> void:
	var reason := "ok"
	var price := Throwables.price_of(kind)
	if not Throwables.is_valid(kind) or price <= 0:
		reason = "invalid"
	elif not enabled():
		reason = "off"
	elif Arsenal.get_throwable(kind) >= int(Throwables.KINDS[kind]["max"]):
		reason = "full"
	elif not spend(price):
		reason = "poor"
	else:
		Arsenal.add_throwable(kind, Throwables.box_of(kind))        # amunicja specjalna: całe pudełko naboi (sufit w nabojach)
		save_progress()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		supply_result.emit(kind, reason == "ok", reason)
	else:
		_supply_result_rpc.rpc_id(peer_id, kind, reason)

@rpc("authority", "call_remote", "reliable")
func _supply_result_rpc(kind: String, reason: String) -> void:
	supply_result.emit(kind, reason == "ok", reason)

## Koszt czyszczenia broni `w` lokalnego gracza przy ławie (0 — czysta): 1 złom za każde rozpoczęte 10 % zużycia.
func clean_cost(w: int) -> int:
	var c := Profile.condition(String(Weapons.def(w).key))
	return 0 if c >= 99.5 else mini(CLEAN_MAX, int(ceil((100.0 - c) / 10.0)))

## Gracz czyści broń przy ławie (stan siedzi w jego profilu; serwer pobiera tylko złom drużyny — najwyżej CLEAN_MAX).
func request_clean(w: int) -> void:
	var cost := clean_cost(w)
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_clean_server(w, cost, NoiseMgr.local_id())
	else:
		_clean_rpc.rpc_id(1, w, cost)

@rpc("any_peer", "call_remote", "reliable")
func _clean_rpc(w: int, cost: int) -> void:
	if NoiseMgr.is_server():
		_clean_server(w, cost, multiplayer.get_remote_sender_id())

func _clean_server(w: int, cost: int, peer_id: int) -> void:
	var reason := "ok"
	if not Weapons.is_valid(w) or cost < 1 or cost > CLEAN_MAX:
		reason = "invalid"
	elif not spend(cost):
		reason = "poor"
	else:
		save_progress()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		_clean_done(w, reason)
	else:
		_clean_result_rpc.rpc_id(peer_id, w, reason)

@rpc("authority", "call_remote", "reliable")
func _clean_result_rpc(w: int, reason: String) -> void:
	_clean_done(w, reason)

func _clean_done(w: int, reason: String) -> void:
	if reason == "ok":
		Profile.clean(String(Weapons.def(w).key))
	clean_result.emit(w, reason == "ok", reason)

## Gracz prosi o odblokowanie części broni (parts.gd) — zakup za złom drużyny, część dostaje cała drużyna; montuje ją każdy sam.
func request_part(id: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_part_server(id, NoiseMgr.local_id())
	else:
		_part_rpc.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _part_rpc(id: String) -> void:
	if NoiseMgr.is_server():
		_part_server(id, multiplayer.get_remote_sender_id())

## Cena części `id` dla `peer_id` (domyślnie lokalnego gracza) — z perkiem „Smith”; pokazują ją warsztat i kodeks.
func part_cost(id: String, peer_id := -1) -> int:
	var mult := 1.0
	if _perks_of(NoiseMgr.local_id() if peer_id < 0 else peer_id).has("smith"):
		mult = Perks.param("smith", "upgrade_cost_mult", 1.0)
	return Parts.cost(id, mult)

func has_part(id: String) -> bool:
	return parts.has(id)

func _perks_of(peer_id: int) -> Array:
	if peer_id == NoiseMgr.local_id():
		return Profile.equipped
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and int(p.player_id) == peer_id:
			return Perks.ids_of(p.perks)
	return []

func _part_server(id: String, peer_id: int) -> void:
	var reason := "ok"
	var p := Parts.get_part(id)
	var w := Weapons.index_of(String(p.get("weapon", "")))
	if p.is_empty() or w < 0:
		reason = "invalid"
	elif not is_unlocked(w):
		reason = "locked"
	elif parts.has(id):
		reason = "owned"
	elif not spend(part_cost(id, peer_id)):
		reason = "poor"
	else:
		parts[id] = true
		save_progress()
		_push()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		_part_done(id, reason)
	else:
		_part_result_rpc.rpc_id(peer_id, id, reason)

@rpc("authority", "call_remote", "reliable")
func _part_result_rpc(id: String, reason: String) -> void:
	_part_done(id, reason)

## U kupującego: kupioną część od razu montuje w swojej broni (inni gracze zostają przy swoim wyborze).
func _part_done(id: String, reason: String) -> void:
	if reason == "ok":
		var p := Parts.get_part(id)
		Profile.set_fit(String(p["weapon"]), String(p["slot"]), id)
	part_result.emit(id, reason == "ok", reason)

func _push() -> void:
	changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync.rpc(bank, loot, last_gain, unlocked.keys(), parts.keys(), trophies.keys())

@rpc("authority", "call_remote", "reliable")
func _sync(b: int, l: int, g: int, unl: Array, pts: Array, tro: Array) -> void:
	bank = b
	loot = l
	last_gain = g
	unlocked.clear()
	for w in unl:
		unlocked[int(w)] = true
	trophies.clear()
	for m in tro:
		trophies[String(m)] = true
	_set_parts(pts)
	changed.emit()

# ---------------------------------------------------------------- zapis (host)

func load_progress() -> void:
	var cfg := ConfigFile.new()
	var ok: bool = persist and cfg.load(SAVE_PATH) == OK
	bank = int(cfg.get_value("scrap", "bank", 0)) if ok else 0
	unlocked.clear()
	trophies.clear()
	parts.clear()
	if ok:
		for w in Array(cfg.get_value("workshop", "unlocked", [])):
			unlocked[int(w)] = true
		for m in Array(cfg.get_value("workshop", "trophies", [])):
			trophies[String(m)] = true
		Arsenal.load_gear(cfg.get_value("gear", "stock", {}) as Dictionary)       # zapas zaopatrzenia z poprzednich sesji
		_set_parts(Array(cfg.get_value("workshop", "parts", [])))
		migrate_levels(cfg.get_value("workshop", "levels", {}) as Dictionary)
	loot = 0
	last_gain = 0
	changed.emit()

## Zapis sprzed 1.7.319: poziomy ulepszeń (id broni → 0..3) → części tych poziomów. Gniazdo bez wyboru gracza montuje je samo
## (Profile.fitted), więc broń zostaje taka, jaka była — z kosztami, które części dostały w 1.7.319.
func migrate_levels(old_levels: Dictionary) -> void:
	for k in old_levels:
		var w := int(k)
		if Weapons.is_valid(w):
			for id in Parts.from_level(String(Weapons.def(w).key), int(old_levels[k])):
				parts[String(id)] = true

func save_progress() -> void:
	if not persist or not NoiseMgr.is_server():
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("scrap", "bank", bank)
	cfg.set_value("workshop", "unlocked", unlocked.keys())
	cfg.set_value("workshop", "trophies", trophies.keys())
	cfg.set_value("gear", "stock", Arsenal.stock)
	cfg.set_value("workshop", "parts", parts.keys())
	if cfg.has_section_key("workshop", "levels"):
		cfg.erase_section_key("workshop", "levels")             # przeniesione do części (migracja w load_progress)
	cfg.save(SAVE_PATH)
