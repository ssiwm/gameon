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
signal purchase_result(weapon: int, ok: bool, reason: String)    ## kody zakupu: ok/poor/owned/later/invalid; ulepszenia z prefiksem up_ (+ locked, max)

const NightShift := preload("res://scripts/night_shift.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Upgrades := preload("res://scripts/upgrades.gd")

const SAVE_PATH := "user://progress.cfg"

## Stałe balansu w jednym miejscu — do strojenia po playtestach.
const DROP_CHANCE := 0.35
const DROP := {"trzosek": 2, "wolek": 6, "slepiec": 5, "podsluchacz": 4, "mimik": 10, "skoczek": 5, "cma": 4}
const CACHE_VALUE := 6               ## skrytka z mapy
const BOSS_VALUE := 30
const STASH_VALUE := 20               ## ukryta skrytka (cel poboczny misji 1.1)
const BONUS_CLEAR := 30               ## za ukończenie misji
const BONUS_SIDE := 15                ## za cel poboczny
const BONUS_NO_DOWNS := 10            ## za misję bez upadków

## Warsztat (faza B): ceny broni z kryjówki. Broń spoza tej tabeli i spoza LATER jest odblokowana od początku (M-83, SPREAD-12, P-64, maczeta).
const PRICES := {Weapons.LR7: 150, Weapons.HKM9: 200, Weapons.SRUT8: 250, Weapons.GNIEW4: 300, Weapons.WIDMO1: 400}
const LATER := [Weapons.SOKOL6, Weapons.CIEGNO6]       ## stojaki zablokowane do późniejszych stref
## Bronie-trofea: dostępne w warsztacie dopiero po ukończeniu wskazanej misji (id mapy). SPECTER-1 → po Pijawce (B1).
const REWARDS := {Weapons.WIDMO1: "z1_b1"}

var bank := 0
var loot := 0
var levels: Dictionary = Weapons.levels      ## id broni → poziom ulepszenia 0..3 (TEN SAM słownik co Weapons.levels; zmieniamy go tylko w miejscu)
var unlocked: Dictionary = {}         ## id broni → true: kupione w warsztacie (zapis u hosta)
var trophies: Dictionary = {}         ## id misji (boss) → true: ukończona, odblokowuje broń-trofeum (zapis u hosta)
var last_gain := 0                    ## ile trafiło do banku po ostatniej misji (karta wyniku, ściana wyników)
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie czytają ani nie nadpisują prawdziwego zapisu

func _ready() -> void:
	load_progress()
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if NoiseMgr.is_server():
			_sync.rpc_id(id, bank, loot, last_gain, unlocked.keys(), levels, trophies.keys()))

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

## Podmienia poziomy ulepszeń w miejscu (słownik jest współdzielony z Weapons.levels).
func _set_levels(src: Dictionary) -> void:
	levels.clear()
	for k in src:
		levels[int(k)] = int(src[k])

func level_of(w: int) -> int:
	return int(levels.get(w, 0))

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
	return ("%d scrap at the workshop" % price) if price > 0 else "available in a later zone"

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

## Gracz prosi o kolejny poziom ulepszenia broni. Serwer sprawdza odblokowanie, limit poziomów i portfel.
func request_upgrade(w: int) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_upgrade_server(w, NoiseMgr.local_id())
	else:
		_upgrade_rpc.rpc_id(1, w)

@rpc("any_peer", "call_remote", "reliable")
func _upgrade_rpc(w: int) -> void:
	if NoiseMgr.is_server():
		_upgrade_server(w, multiplayer.get_remote_sender_id())

func _upgrade_server(w: int, peer_id: int) -> void:
	var reason := "ok"
	if not Weapons.is_valid(w) or not Upgrades.has_tiers(String(Weapons.base_def(w).key)):
		reason = "invalid"
	elif not is_unlocked(w):
		reason = "locked"
	elif level_of(w) >= Upgrades.MAX_LEVEL:
		reason = "max"
	elif not spend(Upgrades.cost(String(Weapons.base_def(w).key), level_of(w) + 1)):
		reason = "poor"
	else:
		levels[w] = level_of(w) + 1
		save_progress()
		_push()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		purchase_result.emit(w, reason == "ok", "up_" + reason)
	else:
		_result_rpc.rpc_id(peer_id, w, "up_" + reason)

func _push() -> void:
	changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync.rpc(bank, loot, last_gain, unlocked.keys(), levels, trophies.keys())

@rpc("authority", "call_remote", "reliable")
func _sync(b: int, l: int, g: int, unl: Array, lv: Dictionary, tro: Array) -> void:
	bank = b
	loot = l
	last_gain = g
	unlocked.clear()
	for w in unl:
		unlocked[int(w)] = true
	trophies.clear()
	for m in tro:
		trophies[String(m)] = true
	_set_levels(lv)
	changed.emit()

# ---------------------------------------------------------------- zapis (host)

func load_progress() -> void:
	var cfg := ConfigFile.new()
	var ok: bool = persist and cfg.load(SAVE_PATH) == OK
	bank = int(cfg.get_value("scrap", "bank", 0)) if ok else 0
	unlocked.clear()
	trophies.clear()
	levels.clear()
	if ok:
		for w in Array(cfg.get_value("workshop", "unlocked", [])):
			unlocked[int(w)] = true
		for m in Array(cfg.get_value("workshop", "trophies", [])):
			trophies[String(m)] = true
		_set_levels(cfg.get_value("workshop", "levels", {}) as Dictionary)
	loot = 0
	last_gain = 0
	changed.emit()

func save_progress() -> void:
	if not persist or not NoiseMgr.is_server():
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("scrap", "bank", bank)
	cfg.set_value("workshop", "unlocked", unlocked.keys())
	cfg.set_value("workshop", "trophies", trophies.keys())
	cfg.set_value("workshop", "levels", levels)
	cfg.save(SAVE_PATH)
