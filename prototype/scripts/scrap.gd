extends Node
const Ammo := preload("res://scripts/ammo.gd")
## Autoload „Scrap": złom — waluta drużyny (GDD §10.1). Portfel jest WSPÓLNY, autorytet ma serwer, klienci dostają stan przez sync.
##
## Dwa stany: `loot` to złom zebrany w TEJ misji (jeszcze nie bezpieczny) i `bank` — portfel, z którego płaci się w warsztacie.
## Udana ekstrakcja przenosi loot do banku (`bank_loot`); wipe albo restart misji kasuje loot (GDD §4: „tracicie łup misji") —
## bank zostaje. Bank zapisuje się u hosta w progress.cfg aktywnej postaci (characters.gd) i wraca przy starcie hostowania. Nocny Dyżur nie daje złomu.
##
## Źródła: wrogowie (enemy.gd, szansa), skrytki na mapie (znacznik „u", pickup „scrap"), bonus za misję (mission.gd).

signal changed
## Wynik zakupu w warsztacie (u kupującego): id broni, powodzenie, kod: "ok" | "poor" | "owned" | "later" | "invalid".
signal supply_result(kind: String, ok: bool, reason: String)    ## zakup zaopatrzenia: ok / poor / full / invalid / off
signal purchase_result(weapon: int, ok: bool, reason: String)    ## kody zakupu broni: ok/poor/owned/later/invalid
signal part_result(id: String, ok: bool, reason: String)         ## zakup części (parts.gd): ok/poor/owned/locked/invalid
signal part_found(id: String)                                     ## część znaleziona w misji (u wszystkich) — czeka na ekstrakcję
signal service_result(weapon: int, part: String, ok: bool, reason: String)   ## wymiana części eksploatacyjnej: ok / poor / invalid / off
signal research_result(id: String, ok: bool, reason: String)       ## badanie w pracowni: ok / samples / poor / busy / owned / locked / invalid / off
## Pracownia elektroniki i próbek (WORKSHOP_PLAN.md W6a, od 1.7.357): części broni specjalnych (LAB_WEAPONS) nie kupuje się na ławie —
## bada się je za próbki (z elit i bossów, do banku po udanej misji) i połowę ceny w złomie. Od 1.7.358 (W6b) badanie daje SCHEMAT
## (`schematics`), a część wykonuje tokarka (`request_machining`, MACHINE_PRICE ceny części) — każde po jednej udanej misji.
const LAB_WEAPONS := ["lr7", "hkm9", "gniew4", "widmo1", "sokol6", "ciegno6"]
const LAB_SLOTS := 2                  ## badań naraz; do 1.7.454 jedno — 22 części broni specjalnych to było ponad 20 udanych misji, a próbki leżały
signal machining_result(id: String, ok: bool, reason: String)     ## zlecenie na tokarce: ok / poor / busy / owned / noschem / invalid / off
const LATHE_SLOTS := 2                ## zleceń na tokarce naraz (do 1.7.454 jedno)
const MACHINE_PRICE := 0.25           ## materiał na tokarce: ćwierć ceny części (zaokrąglone do 5)
const SAMPLE_ELITE := 1               ## próbek z elity (enemy.gd) …
const SAMPLE_BOSS := 2                ## … z bossa (boss_base.gd) …
const SAMPLE_SIDE := 1                ## … i za cel poboczny udanej misji (mission.gd; GDD §10.1)
## Badanie: 1 próbka za część do tej ceny, 2 za droższą. Do 1.7.458 progi 150 / 250 → 1 / 2 / 3: strefa 1 to 27 próbek przy ~0,8 na udaną
## misję (dziennik), ok. 34 misje — 2,5× dłużej niż zebranie złomu na te same części; teraz 20.
const SAMPLE_CHEAP_MAX := 250
signal order_result(kind: String, ok: bool, reason: String)        ## zamówienie w prasie: ok / poor / busy / full / invalid / off
signal orders_delivered(kinds: Array)                              ## partie z prasy gotowe po misji (u wszystkich)
## Prasa elaboracyjna (WORKSHOP_PLAN.md W4, od 1.7.354): amunicję specjalną się zamawia, a nie kupuje od ręki — partia (pudełko) jest
## gotowa po następnej udanej misji (bank_loot). Najwyżej PRESS_SLOTS partii naraz, cena PRESS_PRICE × cena dawnego sklepu.
const PRESS_SLOTS := 3
const PRESS_PRICE := 0.75
## Stół konserwacji (WORKSHOP_PLAN.md W2, od 1.7.350): cena nowej części eksploatacyjnej (Profile.WEAR_PARTS) w złomie drużyny.
const SERVICE_COST := {"barrel": 40, "springs": 20}

const NightShift := preload("res://scripts/night_shift.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const Perks := preload("res://scripts/perks.gd")
const Throwables := preload("res://scripts/throwables.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const SAVE_FILE := "progress.cfg"            ## kampania aktywnej postaci (Characters.file, PROFILES_PLAN.md E1; do 1.7.425 user://progress.cfg)

## Stałe balansu w jednym miejscu — do strojenia po playtestach.
const DROP_CHANCE := 0.35              ## szansa na złom z trupa; ile złomu daje rodzaj — pole `scrap` w enemy_defs.gd
const CACHE_VALUE := 6               ## skrytka z mapy
const BOSS_VALUE := 30
const STASH_VALUE := 20               ## ukryta skrytka (cel poboczny misji 1.1)
const BONUS_CLEAR := 30               ## za ukończenie misji
const BONUS_SIDE := 15                ## za cel poboczny
const BONUS_NO_DOWNS := 10            ## za misję bez upadków
const BONUS_SILENT := 30              ## cichy cel: Uwaga nie przekroczyła 60 przez cały cel główny (FUN_PLAN.md P2.1) — podwaja premię za ukończenie
## Części jako znaleziska (GUNSMITH_PLAN §7.1, od 1.7.333): skrytka misji czasem zawiera część, elita czasem ją zostawia. Znaleziona część
## czeka w `found` do ekstrakcji (jak łup złomu) i dopiero wtedy jest odblokowana dla drużyny; wipe ją zabiera. Część broni specjalnej
## (pracownia) daje po ekstrakcji schemat, nie gotową część — trzeba ją jeszcze wytoczyć.
const ELITE_PART_DROP := 0.3
## Do 1.7.453 każda skrytka miała część: dwie skrytki 1.1 były warte więcej niż złom z całej misji, a kupowanie na ławie traciło sens.
const STASH_PART_CHANCE := 0.35
var stash_part_roll := -1.0          ## testy: wymuszony wynik losowania skrytki (0..1); < 0 — randf()

## Warsztat (faza B): ceny broni z kryjówki. Broń spoza tej tabeli i spoza LATER jest odblokowana od początku (M-83, SPREAD-12, P-83, maczeta).
const PRICES := {Weapons.LR7: 150, Weapons.HKM9: 200, Weapons.SRUT8: 250, Weapons.GNIEW4: 300, Weapons.WIDMO1: 400}
const LATER := [Weapons.SOKOL6, Weapons.CIEGNO6]       ## stojaki zablokowane do późniejszych stref
## Bronie-trofea: dostępne w warsztacie dopiero po ukończeniu wskazanej misji (id mapy). SPECTER-1 → po Pijawce (B1).
const REWARDS := {Weapons.WIDMO1: "z1_b1"}

var bank := 0
var loot := 0
var parts: Dictionary = {}            ## id części (parts.gd) → true: odblokowane przez drużynę (zapis u hosta); montaż — Profile.fits
var found: Dictionary = {}            ## id części → true: znalezione w tej misji, odblokowane dopiero po ekstrakcji
var fuses: Dictionary = {}           ## stół pirotechniczny: rodzaj przedmiotu → indeks długości zapalnika (Throwables.FUSES); brak — fabryczny
var samples := 0                     ## próbki w banku drużyny (zapis u hosta)
var samples_loot := 0                 ## próbki zebrane w tej misji — do banku po ekstrakcji, wipe je zabiera
var schematics: Dictionary = {}      ## id części → true: schemat z pracowni, czeka na tokarkę (zapis u hosta)
var lathe: Array = []                 ## tokarka: wykonywane części (id), gotowe po udanej misji (zapis u hosta)
var research: Array = []              ## pracownia: badane części (id z parts.gd), gotowe po udanej misji (zapis u hosta)
var deliveries: Dictionary = {}           ## opłacone naboje oczekujące na miejsce we wspólnym zapasie
var job_paid: Dictionary = {}             ## "research:<id>" / "lathe:<id>" → zapłacony złom (z perkiem Smith mniej); zwrot anulowanego etapu oddaje tyle (serwer, zapis)
var _action_at: Dictionary = {}      ## ograniczenie powtórzeń płatnych żądań tego samego peera
var _serviced: Dictionary = {}       ## jedna wymiana danego elementu na pobyt w kryjówce
var orders: Array = []                ## prasa: zamówione partie (wpisy `ammo_*` z throwables.gd), dostawa po udanej misji (zapis u hosta)
var unlocked: Dictionary = {}         ## id broni → true: kupione w warsztacie (zapis u hosta)
var trophies: Dictionary = {}         ## id misji (boss) → true: ukończona, odblokowuje broń-trofeum (zapis u hosta)
var cleared: Dictionary = {}          ## id misji kampanii → true: ukończona przez tę drużynę (zapis u hosta, [campaign]) — skąd startuje kampania
                                      ## i co można wybrać przy tablicy odpraw (PROGRESSION_PLAN.md P1.1, od 1.7.392)
var last_gain := 0                    ## ile trafiło do banku po ostatniej misji (karta wyniku, ściana wyników)
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie czytają ani nie nadpisują prawdziwego zapisu
var legacy_fits := false              ## stary postęp bez osobnego profilu także korzystał z automatycznego montażu
var _delivery_snapshot: Dictionary = {}
var _delivery_checkpointed := false
var _delivery_committed := false

func _ready() -> void:
	load_progress()
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if NoiseMgr.is_server():
			_sync.rpc_id(id, bank, loot, last_gain, unlocked.keys(), parts.keys(), trophies.keys(), found.keys(), orders, fuses, samples, samples_loot, research, schematics.keys(), lathe, deliveries, cleared.keys()))

## Złom nie obowiązuje w Nocnym Dyżurze (osobna seria z własnymi zasadami).
func enabled() -> bool:
	return not NightShift.active

# ---------------------------------------------------------------- serwer

## Autoryzacja stanowiska dla konkretnego nadawcy; lokalny zasięg UI nie autoryzuje innych peerów.
func station_reason(peer_id: int, group: String) -> String:
	if not NoiseMgr.is_server() or not enabled():
		return "off"
	var level := get_tree().get_first_node_in_group("level")
	if not NoiseMgr.safe_zone or level == null or String(level.map_id) != "z1_hub":
		return "station"
	if peer_id != NoiseMgr.local_id() and (not NoiseMgr.has_network() or not multiplayer.get_peers().has(peer_id)):
		return "station"
	var human: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and int(p.player_id) == peer_id and not p.dead:
			human = p
			break
	if human == null:
		return "station"
	for station in get_tree().get_nodes_in_group(group):
		if absf(human.global_position.x - station.global_position.x) <= float(station.REACH_X) and absf(human.global_position.y - station.global_position.y) <= float(station.REACH_Y):
			return "ok"
	return "station"

## Stacja dostawy/zakupu zależy od rzeczywistego rodzaju przedmiotu, także dla RPC.
func supply_station(kind: String) -> String:
	if Throwables.is_ammo(kind):
		return "pyro_bench" if String(Ammo.from_kind(kind).get("cal", "")) == "40mm" else "press_bench"
	var mode := String(Throwables.KINDS.get(kind, {}).get("mode", ""))
	return "pyro_bench" if mode == "throw" or mode == "place" else "workshop"

## Dziennik sesji: rozstrzygnięta operacja warsztatu (PROGRESSION_PLAN.md P0.4). Bez odmów „station”, „repeat” i „off”
## (gracz poza stanowiskiem, podwójne kliknięcie, Nocny Dyżur) — nie mówią nic o ekonomii.
func _log_buy(kind: String, id: String, cost: int, reason: String, peer_id: int, extra := {}) -> void:
	if reason == "station" or reason == "repeat" or reason == "off":
		return
	var who := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and int(p.player_id) == peer_id:
			who = int(p.display_id)
			break
	var row := {"who": who, "kind": kind, "id": id, "cost": cost, "ok": reason == "ok", "reason": reason, "bank": bank}
	row.merge(extra)
	SessionLog.note("hub_buy", row)

func _permit_action(peer_id: int, action: String) -> bool:
	var key := "%d:%s" % [peer_id, action]
	var now := Time.get_ticks_msec()
	if now - int(_action_at.get(key, -1000)) < 350:
		return false
	_action_at[key] = now
	return true


## Zebrany złom wpada do łupu misji.
func add_loot(n: int) -> void:
	if not NoiseMgr.is_server() or n <= 0 or not enabled():
		return
	loot += n
	_push()

## Ekstrakcja udana: łup + bonusy do banku, znalezione części do odblokowań drużyny, zapis na dysk. Zwraca ile złomu weszło.
func bank_loot(bonus: int) -> int:
	if not NoiseMgr.is_server() or not enabled():
		return 0
	var gain := loot + maxi(0, bonus)
	bank += gain
	last_gain = gain
	loot = 0
	var newp: Array = []
	var found_schem: Array = []
	for id in found.keys():
		if is_lab_part(String(id)):
			found_schem.append(id)                                    # broń specjalna: znalezisko zastępuje badanie, nie tokarkę
			schematics[String(id)] = true                             # przed _reconcile_jobs: równoległe badanie tej części wraca do banku
		else:
			newp.append(id)
			parts[id] = true
	found.clear()
	samples += samples_loot
	samples_loot = 0
	_reconcile_jobs()
	var learned: Array = research.duplicate()
	for id in learned:
		schematics[String(id)] = true                                 # badanie skończone: schemat dla tokarki (W6b)
		job_paid.erase("research:" + String(id))
	research.clear()
	learned.append_array(found_schem)
	var machined: Array = lathe.duplicate()
	for id in machined:
		parts[String(id)] = true                                      # tokarka: część gotowa, odblokowana dla drużyny
		schematics.erase(String(id))
		job_paid.erase("lathe:" + String(id))
	lathe.clear()
	var done: Array = orders.duplicate()
	for k in done:
		deliveries[String(k)] = int(deliveries.get(String(k), 0)) + Throwables.box_of(String(k))
	orders.clear()
	for k in deliveries.keys():
		_deliver_ready(String(k))
	_serviced.clear()
	_action_at.clear()
	_delivery_snapshot = deliveries.duplicate()       # sukces zatwierdza również zwroty nabojów z tej misji
	_delivery_committed = true
	save_progress()
	_push()
	if not newp.is_empty():
		if NoiseMgr.has_network():
			_banked_rpc.rpc(newp)
		else:
			_banked_rpc(newp)
	if not done.is_empty():
		if NoiseMgr.has_network():
			_delivered_rpc.rpc(done)
		else:
			_delivered_rpc(done)
	if not learned.is_empty():
		if NoiseMgr.has_network():
			_learned_rpc.rpc(learned)
		else:
			_learned_rpc(learned)
	if not machined.is_empty():
		if NoiseMgr.has_network():
			_machined_rpc.rpc(machined)
		else:
			_machined_rpc(machined)
	return gain

## Wipe / restart: łup i znalezione części przepadają, bank zostaje.
func reset_loot() -> void:
	if not NoiseMgr.is_server():
		return
	_checkpoint_loot.clear()
	if loot != 0 or not found.is_empty() or samples_loot != 0:
		loot = 0
		found.clear()
		samples_loot = 0
		_push()

## Łup w chwili przebudzenia bossa (mission._save_checkpoint, serwer). Wipe w walce z bossem wraca do niego zamiast do zera:
## restart od punktu kontrolnego zostawia zniszczone gniazda, więc kasowanie złomu, próbek i części sprzed walki zabierało drużynie
## całą drogę przez mapę (opinia testera 2026-10-29: ~10 prób Żyły, znalezione części nigdy nie dotarły do kryjówki).
var _checkpoint_loot := {}

func save_checkpoint_loot() -> void:
	if not NoiseMgr.is_server():
		return
	_checkpoint_loot = {"loot": loot, "found": found.keys(), "samples": samples_loot}

## Wipe w walce z bossem (main._restart_from_checkpoint): łup z samej walki przepada, sprzed niej zostaje. Bez zapisu = reset_loot().
func restore_checkpoint_loot() -> void:
	if not NoiseMgr.is_server():
		return
	if _checkpoint_loot.is_empty():
		reset_loot()
		return
	loot = int(_checkpoint_loot["loot"])
	found.clear()
	for id in _checkpoint_loot["found"]:
		found[String(id)] = true
	samples_loot = int(_checkpoint_loot["samples"])
	_push()

## Część do znalezienia: losowa część z modelem (leży na ziemi albo w skrytce) dla broni, którą drużyna ma, jeszcze nieodblokowana
## i nieznaleziona w tej misji; "" — wszystko już jest.
func pick_find() -> String:
	var pool := find_candidates()
	return "" if pool.is_empty() else String(pool[randi() % pool.size()])

## Część ze skrytki (STASH_PART_CHANCE): "" — skrytka ma tylko złom albo wszystko już jest.
func pick_stash_find() -> String:
	var roll := stash_part_roll if stash_part_roll >= 0.0 else randf()
	return pick_find() if roll < STASH_PART_CHANCE else ""

## Jawna pula pozwala sprawdzić wykluczenia bez probabilistycznego testu losowania.
func find_candidates() -> Array:
	var pool: Array = []
	for id in Parts.all_ids():
		var w := Weapons.index_of(String(Parts.get_part(id)["weapon"]))
		if w < 0 or not is_unlocked(w) or parts.has(id) or found.has(id) or research.has(id) or schematics.has(id) or lathe.has(id) or not GunModel.has_model(id):
			continue
		pool.append(id)
	return pool

## Indeks części w Parts.all_ids() (arg znajdźki „part”).
func part_index(id: String) -> int:
	return Parts.all_ids().find(id)

## Serwer: drużyna znalazła część — czeka do ekstrakcji. false: nieznana, już odblokowana albo już znaleziona.
func find_part(id: String) -> bool:
	if not NoiseMgr.is_server() or not enabled() or not Parts.is_valid(id) or parts.has(id) or found.has(id) or research.has(id) or schematics.has(id) or lathe.has(id):
		return false
	found[id] = true
	_push()
	if NoiseMgr.has_network():
		_found_rpc.rpc(id)
	else:
		_found_rpc(id)
	return true

@rpc("authority", "call_local", "reliable")
func _found_rpc(id: String) -> void:
	part_found.emit(id)
	var sub := tr("After extraction: a schematic for the lathe") if is_lab_part(id) else tr("The squad gets it after extraction")
	Msg.post("find.%s" % id, Msg.Ch.TOAST, tr("Found: %s") % tr(String(Parts.get_part(id).get("name", id))),
		{"sub": sub, "style": Msg.Style.SUCCESS, "ttl": 5.0, "prio": 75})
	Audio.play("weapon_pickup", Audio.BUS_UI, -8.0)

@rpc("authority", "call_local", "reliable")
func _banked_rpc(ids: Array) -> void:
	for id in ids:
		Msg.post("banked.%s" % id, Msg.Ch.TOAST, tr("%s unlocked for the squad") % tr(String(Parts.get_part(String(id)).get("name", id))),
			{"sub": tr("Mount new parts at the workbench"), "style": Msg.Style.SUCCESS, "ttl": 6.0, "prio": 70})

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

## Misja kampanii `map_id` ukończona przez drużynę (mission._success; Nocny Dyżur się nie liczy). Serwer; zapis i sync.
func add_cleared(map_id: String) -> void:
	if not NoiseMgr.is_server() or not enabled() or map_id == "" or cleared.has(map_id):
		return
	cleared[map_id] = true
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
	var reason := station_reason(peer_id, "workshop")
	if reason != "ok":
		pass
	elif not Weapons.is_valid(w):
		reason = "invalid"
	elif LATER.has(w):
		reason = "later"
	elif is_gated(w):
		reason = "reward"
	elif not PRICES.has(w):
		reason = "invalid"
	elif unlocked.has(w):
		reason = "owned"
	elif bank >= int(PRICES[w]) and not _permit_action(peer_id, "weapon:%d" % w):
		reason = "repeat"
	elif not spend(int(PRICES[w])):
		reason = "poor"
	else:
		unlocked[w] = true
		save_progress()
		_push()
	_log_buy("weapon", String(Weapons.def(w).key) if Weapons.is_valid(w) else str(w), price_of(w), reason, peer_id)
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
	var reason := station_reason(peer_id, supply_station(kind))
	var price := Throwables.price_of(kind)
	if reason != "ok":
		pass
	elif not Throwables.is_valid(kind) or price <= 0 or String(Throwables.KINDS[kind]["mode"]) == "ammo":     # amunicja: tylko prasa (1.7.354)
		reason = "invalid"
	elif not enabled():
		reason = "off"
	elif Arsenal.get_throwable(kind) >= int(Throwables.KINDS[kind]["max"]):
		reason = "full"
	elif bank >= price and not _permit_action(peer_id, "supply:" + kind):
		reason = "repeat"
	elif not spend(price):
		reason = "poor"
	else:
		Arsenal.add_throwable(kind, Throwables.box_of(kind))        # amunicja specjalna: całe pudełko naboi (sufit w nabojach)
		save_progress()
	_log_buy("supply", kind, price, reason, peer_id)
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		supply_result.emit(kind, reason == "ok", reason)
	else:
		_supply_result_rpc.rpc_id(peer_id, kind, reason)

@rpc("authority", "call_remote", "reliable")
func _supply_result_rpc(kind: String, reason: String) -> void:
	supply_result.emit(kind, reason == "ok", reason)

## Zapalnik przedmiotu `kind` w sekundach: wybór drużyny przy stole pirotechnicznym albo fabryczny (grenade.gd, placed.gd — u wszystkich ten sam).
func fuse_of(kind: String) -> float:
	var opts: Array = Throwables.FUSES.get(kind, []) as Array
	if opts.is_empty():
		return float(Throwables.KINDS.get(kind, {}).get("fuse", 0.0))
	return float(opts[clampi(int(fuses.get(kind, Throwables.fuse_default(kind))), 0, opts.size() - 1)])

## Indeks wybranego zapalnika `kind`.
func fuse_index(kind: String) -> int:
	return int(fuses.get(kind, Throwables.fuse_default(kind)))

## Gracz przy stole pirotechnicznym zmienia zapalnik `kind` na `idx` (ustawienie drużyny — serwer zapisuje i rozsyła).
func request_fuse(kind: String, idx: int) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_fuse_server(kind, idx, NoiseMgr.local_id())
	else:
		_fuse_rpc.rpc_id(1, kind, idx)

@rpc("any_peer", "call_remote", "reliable")
func _fuse_rpc(kind: String, idx: int) -> void:
	if NoiseMgr.is_server():
		_fuse_server(kind, idx, multiplayer.get_remote_sender_id())

func _fuse_server(kind: String, idx: int, peer_id: int) -> void:
	if station_reason(peer_id, "pyro_bench") != "ok":
		return
	var opts: Array = Throwables.FUSES.get(kind, []) as Array
	if opts.is_empty() or idx < 0 or idx >= opts.size():
		return
	if idx == Throwables.fuse_default(kind):
		fuses.erase(kind)
	else:
		fuses[kind] = idx
	save_progress()
	_push()

## Czy część `id` należy do broni specjalnej (badanie w pracowni zamiast zakupu na ławie).
## Pracownia działa od pierwszej próbki: wcześniej nie ma w niej co robić (WORKSHOP_PLAN.md §6). Raz rozpoczęty łańcuch zostawia ją otwartą.
func lab_open() -> bool:
	return samples > 0 or not research.is_empty() or lathe_open_jobs() or _owns_lab_part()

## Tokarka działa od pierwszego schematu, a przy włączonym zużyciu także jako szlifierka broni białej.
func lathe_open() -> bool:
	return Settings.reliability_mult() > 0.0 or lathe_open_jobs() or _owns_lab_part()

func lathe_open_jobs() -> bool:
	return not schematics.is_empty() or not lathe.is_empty()

func _owns_lab_part() -> bool:
	for id in parts:
		if is_lab_part(String(id)):
			return true
	return false

func is_lab_part(id: String) -> bool:
	return String(Parts.get_part(id).get("weapon", "")) in LAB_WEAPONS

## Koszt badania części `id` dla `peer_id`: x — próbki (1 / 2 wg ceny części, SAMPLE_CHEAP_MAX), y — złom (połowa ceny części × perk Smith, zaokrąglona do 5).
func research_cost(id: String, peer_id := -1) -> Vector2i:
	var c := int(Parts.get_part(id).get("cost", 0))
	return Vector2i(1 if c <= SAMPLE_CHEAP_MAX else 2,int(roundf(float(c) * 0.5 * smith_mult(peer_id) / 5.0)) * 5)

## Serwer: próbki z elity / bossa trafiają do łupu misji (bank dopiero po udanej misji).
func add_samples(n: int) -> void:
	if not NoiseMgr.is_server() or n <= 0 or not enabled():
		return
	samples_loot += n
	_push()
	if NoiseMgr.has_network():
		_sample_rpc.rpc(n)
	else:
		_sample_rpc(n)

@rpc("authority", "call_local", "reliable")
func _sample_rpc(n: int) -> void:
	var sub := tr("After extraction: the LAB bench in the safe room researches special-weapon parts with it") if has_lab_weapon() else tr("Research needs a special weapon from the workshop: LR-7, HKM-9 or WRATH-4")
	Msg.post("sample.%d" % samples_loot, Msg.Ch.TOAST, tr("Sample taken (+%d)") % n,
		{"sub": sub, "style": Msg.Style.SUCCESS, "ttl": 4.0 if has_lab_weapon() else 6.0, "prio": 60})

## Czy drużyna ma broń specjalną, której części bada pracownia — bez niej próbki czekają (PROGRESSION_PLAN.md P1.3).
func has_lab_weapon() -> bool:
	for k in LAB_WEAPONS:
		var w := Weapons.index_of(String(k))
		if w >= 0 and is_unlocked(w):
			return true
	return false

@rpc("authority", "call_local", "reliable")
func _learned_rpc(ids: Array) -> void:
	for id in ids:
		Msg.post("learned.%s" % id, Msg.Ch.TOAST, tr("Schematic ready: %s") % tr(String(Parts.get_part(String(id)).get("name", id))),
			{"sub": tr("Make it on the lathe"), "style": Msg.Style.SUCCESS, "ttl": 6.0, "prio": 70})

@rpc("authority", "call_local", "reliable")
func _machined_rpc(ids: Array) -> void:
	for id in ids:
		Msg.post("machined.%s" % id, Msg.Ch.TOAST, tr("%s machined — unlocked for the squad") % tr(String(Parts.get_part(String(id)).get("name", id))),
			{"style": Msg.Style.SUCCESS, "ttl": 6.0, "prio": 70})

## Cena materiału na tokarce dla części `id` i `peer_id` (perk Smith).
func machine_price(id: String, peer_id := -1) -> int:
	return int(roundf(float(Parts.get_part(id).get("cost", 0)) * MACHINE_PRICE * smith_mult(peer_id) / 5.0)) * 5

## Zlecenie na tokarce: część `id` ze schematu (złom drużyny, serwer).
func request_machining(id: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_machining_server(id, NoiseMgr.local_id())
	else:
		_machining_rpc.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _machining_rpc(id: String) -> void:
	if NoiseMgr.is_server():
		_machining_server(id, multiplayer.get_remote_sender_id())

func _machining_server(id: String, peer_id: int) -> void:
	var reason := station_reason(peer_id, "lathe_bench")
	if reason != "ok":
		pass
	elif Parts.get_part(id).is_empty() or not is_lab_part(id):
		reason = "invalid"
	elif not is_unlocked(Weapons.index_of(String(Parts.get_part(id)["weapon"]))):
		reason = "locked"
	elif not enabled():
		reason = "off"
	elif found.has(id) or parts.has(id) or lathe.has(id):
		reason = "owned"
	elif not schematics.has(id):
		reason = "noschem"
	elif lathe.size() >= LATHE_SLOTS:
		reason = "busy"
	elif bank >= machine_price(id, peer_id) and not _permit_action(peer_id, "machine:" + id):
		reason = "repeat"
	elif not spend(machine_price(id, peer_id)):
		reason = "poor"
	else:
		lathe.append(id)
		job_paid["lathe:" + id] = machine_price(id, peer_id)
		save_progress()
		_push()
	_log_buy("machining", id, machine_price(id, peer_id), reason, peer_id)
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		machining_result.emit(id, reason == "ok", reason)
	else:
		_machining_result_rpc.rpc_id(peer_id, id, reason)

@rpc("authority", "call_remote", "reliable")
func _machining_result_rpc(id: String, reason: String) -> void:
	machining_result.emit(id, reason == "ok", reason)

## Badanie części `id` w pracowni (próbki i złom drużyny, serwer).
func request_research(id: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_research_server(id, NoiseMgr.local_id())
	else:
		_research_rpc.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _research_rpc(id: String) -> void:
	if NoiseMgr.is_server():
		_research_server(id, multiplayer.get_remote_sender_id())

func _research_server(id: String, peer_id: int) -> void:
	var reason := station_reason(peer_id, "lab_bench")
	var w := Weapons.index_of(String(Parts.get_part(id).get("weapon", "")))
	var cost := research_cost(id, peer_id)
	if reason != "ok":
		pass
	elif Parts.get_part(id).is_empty() or w < 0 or not is_lab_part(id):
		reason = "invalid"
	elif not enabled():
		reason = "off"
	elif not is_unlocked(w):
		reason = "locked"
	elif found.has(id) or parts.has(id) or research.has(id) or schematics.has(id) or lathe.has(id):
		reason = "owned"
	elif research.size() >= LAB_SLOTS:
		reason = "busy"
	elif samples < cost.x:
		reason = "samples"
	elif bank >= cost.y and not _permit_action(peer_id, "research:" + id):
		reason = "repeat"
	elif not spend(cost.y):
		reason = "poor"
	else:
		samples -= cost.x
		research.append(id)
		job_paid["research:" + id] = cost.y
		save_progress()
		_push()
	_log_buy("research", id, cost.y, reason, peer_id, {"samples": cost.x})
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		research_result.emit(id, reason == "ok", reason)
	else:
		_research_result_rpc.rpc_id(peer_id, id, reason)

@rpc("authority", "call_remote", "reliable")
func _research_result_rpc(id: String, reason: String) -> void:
	research_result.emit(id, reason == "ok", reason)

## Cena partii `kind` w prasie (zaokrąglona do 5).
func press_price(kind: String) -> int:
	return int(roundf(float(Throwables.price_of(kind)) * PRESS_PRICE / 5.0)) * 5

## Ile partii `kind` czeka w prasie.
func ordered(kind: String) -> int:
	return orders.count(kind)

## Zamówienie partii amunicji specjalnej `kind` w prasie (złom drużyny, serwer).
func request_order(kind: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_order_server(kind, NoiseMgr.local_id())
	else:
		_order_rpc.rpc_id(1, kind)

@rpc("any_peer", "call_remote", "reliable")
func _order_rpc(kind: String) -> void:
	if NoiseMgr.is_server():
		_order_server(kind, multiplayer.get_remote_sender_id())

func _order_server(kind: String, peer_id: int) -> void:
	var reason := station_reason(peer_id, supply_station(kind))
	if reason != "ok":
		pass
	elif not Throwables.is_valid(kind) or String(Throwables.KINDS[kind]["mode"]) != "ammo":
		reason = "invalid"
	elif not enabled():
		reason = "off"
	elif orders.size() >= PRESS_SLOTS:
		reason = "busy"
	elif Arsenal.get_throwable(kind) + int(deliveries.get(kind, 0)) + (ordered(kind) + 1) * Throwables.box_of(kind) > int(Throwables.KINDS[kind]["max"]):
		reason = "full"
	elif bank >= press_price(kind) and not _permit_action(peer_id, "order:" + kind):
		reason = "repeat"
	elif not spend(press_price(kind)):
		reason = "poor"
	else:
		orders.append(kind)
		save_progress()
		_push()
	_log_buy("order", kind, press_price(kind), reason, peer_id)
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		order_result.emit(kind, reason == "ok", reason)
	else:
		_order_result_rpc.rpc_id(peer_id, kind, reason)

@rpc("authority", "call_remote", "reliable")
func _order_result_rpc(kind: String, reason: String) -> void:
	order_result.emit(kind, reason == "ok", reason)

@rpc("authority", "call_local", "reliable")
func _delivered_rpc(kinds: Array) -> void:
	orders_delivered.emit(kinds)
	var names: Array = []
	for k in kinds:
		names.append(tr(String(Throwables.KINDS.get(String(k), {}).get("name", k))))
	Msg.post("press.ready", Msg.Ch.TOAST, tr("Reloading press: %s ready") % ", ".join(names), {"style": Msg.Style.SUCCESS, "ttl": 6.0, "prio": 65})

## Gracz wymienia część eksploatacyjną `part` broni `w` przy stole konserwacji: złom płaci drużyna (serwer), zużycie siedzi w profilu gracza.
## Próg zużycia (Profile.SERVICE_DUE) sprawdza prośba u gracza — serwer nie zna cudzego profilu, więc część mniej zużyta nie wychodzi z klienta.
func request_service(w: int, part: String) -> void:
	if Weapons.is_valid(w) and SERVICE_COST.has(part) and Weapons.def(w).can_jam() and not Profile.service_due(String(Weapons.def(w).key), part):
		service_result.emit(w, part, false, "early")
		return
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_service_server(w, part, NoiseMgr.local_id())
	else:
		_service_rpc.rpc_id(1, w, part)

@rpc("any_peer", "call_remote", "reliable")
func _service_rpc(w: int, part: String) -> void:
	if NoiseMgr.is_server():
		_service_server(w, part, multiplayer.get_remote_sender_id())

func _service_server(w: int, part: String, peer_id: int) -> void:
	var reason := station_reason(peer_id, "service_bench")
	if reason != "ok":
		pass
	elif not Weapons.is_valid(w) or not SERVICE_COST.has(part) or not Weapons.def(w).can_jam():
		reason = "invalid"
	elif not is_unlocked(w):
		reason = "locked"
	elif not enabled():
		reason = "off"
	elif _serviced.has("%d:%d:%s" % [peer_id, w, part]):
		reason = "serviced"
	elif bank >= int(SERVICE_COST[part]) and not _permit_action(peer_id, "service:%d:%s" % [w, part]):
		reason = "repeat"
	elif not spend(int(SERVICE_COST[part])):
		reason = "poor"
	else:
		_serviced["%d:%d:%s" % [peer_id, w, part]] = true
		save_progress()
	_log_buy("service", "%s:%s" % [String(Weapons.def(w).key) if Weapons.is_valid(w) else str(w), part], int(SERVICE_COST.get(part, 0)), reason, peer_id)
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		_service_done(w, part, reason)
	else:
		_service_result_rpc.rpc_id(peer_id, w, part, reason)

@rpc("authority", "call_remote", "reliable")
func _service_result_rpc(w: int, part: String, reason: String) -> void:
	_service_done(w, part, reason)

func _service_done(w: int, part: String, reason: String) -> void:
	if reason == "ok":
		Profile.replace_part(String(Weapons.def(w).key), part)
	service_result.emit(w, part, reason == "ok", reason)

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
	return Parts.cost(id, smith_mult(peer_id))

## Mnożnik złomu za ulepszenia broni dla `peer_id` (domyślnie lokalnego gracza): perk „Smith” obniża ławę, pracownię i tokarkę
## (od 1.7.455; wcześniej tylko ławę, choć opis mówił o wszystkich ulepszeniach). Próbek perk nie zmienia.
func smith_mult(peer_id := -1) -> float:
	if _perks_of(NoiseMgr.local_id() if peer_id < 0 else peer_id).has("smith"):
		return Perks.param("smith", "upgrade_cost_mult", 1.0)
	return 1.0

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
	var reason := station_reason(peer_id, "workshop")
	var p := Parts.get_part(id)
	var w := Weapons.index_of(String(p.get("weapon", "")))
	if reason != "ok":
		pass
	elif p.is_empty() or w < 0:
		reason = "invalid"
	elif not is_unlocked(w):
		reason = "locked"
	elif found.has(id) or parts.has(id):
		reason = "owned"
	elif is_lab_part(id):
		reason = "lab"                                                # część broni specjalnej: badanie w pracowni (W6a)
	elif bank >= part_cost(id, peer_id) and not _permit_action(peer_id, "part:" + id):
		reason = "repeat"
	elif not spend(part_cost(id, peer_id)):
		reason = "poor"
	else:
		parts[id] = true
		save_progress()
		_push()
	_log_buy("part", id, part_cost(id, peer_id) if Parts.is_valid(id) else 0, reason, peer_id)
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
		_sync.rpc(bank, loot, last_gain, unlocked.keys(), parts.keys(), trophies.keys(), found.keys(), orders, fuses, samples, samples_loot, research, schematics.keys(), lathe, deliveries, cleared.keys())

@rpc("authority", "call_remote", "reliable")
func _sync(b: int, l: int, g: int, unl: Array, pts: Array, tro: Array, fnd: Array = [], ord: Array = [], fz: Dictionary = {},
		smp: int = 0, smp_l: int = 0, res: Array = [], sch: Array = [], lth: Array = [], rdy: Dictionary = {}, clr: Array = []) -> void:
	cleared.clear()
	for m in clr:
		cleared[String(m)] = true
	schematics.clear()
	for id in sch:
		schematics[String(id)] = true
	lathe = lth.duplicate()
	deliveries = rdy.duplicate()
	samples = smp
	samples_loot = smp_l
	research = res.duplicate()
	orders = ord.duplicate()
	fuses = fz.duplicate()
	bank = b
	loot = l
	last_gain = g
	found.clear()
	for f in fnd:
		found[String(f)] = true
	unlocked.clear()
	for w in unl:
		unlocked[int(w)] = true
	trophies.clear()
	for m in tro:
		trophies[String(m)] = true
	_set_parts(pts)
	changed.emit()

## Starszy zapis lub równoczesne odblokowanie: część > tokarka > schemat > badanie; anulowany opłacony etap zwraca koszt.
func _reconcile_jobs() -> void:
	var keep: Array = []
	for value in lathe:
		var id := String(value)
		if not Parts.is_valid(id) or not is_lab_part(id):
			continue
		if parts.has(id) or keep.has(id):
			bank += _paid("lathe:" + id, machine_price(id, 0))            # peer 0 = nikt: cena bez perku (zapis sprzed job_paid)
		else:
			keep.append(id)
	lathe = keep
	for id in schematics.keys():
		if parts.has(id) or not is_lab_part(String(id)):
			schematics.erase(id)
	keep = []
	for value in research:
		var id := String(value)
		if not Parts.is_valid(id) or not is_lab_part(id):
			continue
		if parts.has(id) or schematics.has(id) or lathe.has(id) or keep.has(id):
			var cost := research_cost(id, 0)
			bank += _paid("research:" + id, cost.y)
			samples += cost.x
		else:
			keep.append(id)
	research = keep

## Zapłacony złom za etap `key` (i zapomina go); brak wpisu (zapis sprzed 1.7.455) — `fallback`, cena bez perku.
func _paid(key: String, fallback: int) -> int:
	var v := int(job_paid.get(key, fallback))
	job_paid.erase(key)
	return v

## Zwraca liczbę przyjętych nabojów; nieprzyjęta reszta nadal należy do drużyny.
func _deliver_ready(kind: String) -> int:
	var n := int(deliveries.get(kind, 0))
	if n <= 0:
		return 0
	var accepted := Arsenal.add_throwable(kind, n)
	if accepted >= n:
		deliveries.erase(kind)
	else:
		deliveries[kind] = n - accepted
	return accepted

## Naboje odłożone z magazynka podczas misji podlegają tej samej próbie co stock w Arsenal.
func delivery_checkpoint(new_run: bool) -> void:
	if not NoiseMgr.is_server():
		return
	if new_run:
		_delivery_snapshot = deliveries.duplicate()
		_delivery_checkpointed = true
		_delivery_committed = NoiseMgr.safe_zone
		if NoiseMgr.safe_zone:
			save_progress()
	elif _delivery_checkpointed and deliveries != _delivery_snapshot:
		deliveries = _delivery_snapshot.duplicate()
		_push()

func request_claim(kind: String) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_claim_server(kind, NoiseMgr.local_id())
	else:
		_claim_rpc.rpc_id(1, kind)

@rpc("any_peer", "call_remote", "reliable")
func _claim_rpc(kind: String) -> void:
	if NoiseMgr.is_server():
		_claim_server(kind, multiplayer.get_remote_sender_id())

func _claim_server(kind: String, peer_id: int) -> void:
	var reason := station_reason(peer_id, supply_station(kind))
	if reason == "ok":
		if not Throwables.is_ammo(kind) or int(deliveries.get(kind, 0)) <= 0:
			reason = "empty"
		elif _deliver_ready(kind) <= 0:
			reason = "full"
		else:
			save_progress()
			_push()
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		order_result.emit(kind, reason == "ok", reason)
	else:
		_order_result_rpc.rpc_id(peer_id, kind, reason)

# ---------------------------------------------------------------- zapis (host)

func load_progress(path := "") -> void:
	if path == "":
		path = Characters.file(SAVE_FILE)
	var cfg := ConfigFile.new()
	var ok: bool = persist and cfg.load(path) == OK
	legacy_fits = ok and int(cfg.get_value("workshop", "fit_policy_version", 0)) < 1
	_delivery_snapshot.clear()
	_delivery_checkpointed = false
	_delivery_committed = false
	bank = maxi(0, int(cfg.get_value("scrap", "bank", 0))) if ok else 0
	found.clear()
	unlocked.clear()
	trophies.clear()
	cleared.clear()
	parts.clear()
	orders.clear()
	deliveries.clear()
	_action_at.clear()
	_serviced.clear()
	fuses.clear()
	research.clear()
	schematics.clear()
	lathe.clear()
	job_paid.clear()
	samples = 0
	samples_loot = 0
	if ok:
		for id in Array(cfg.get_value("workshop", "schematics", [])):
			if Parts.is_valid(String(id)):
				schematics[String(id)] = true
		for id in Array(cfg.get_value("workshop", "lathe", [])):
			if Parts.is_valid(String(id)):
				lathe.append(String(id))
		samples = maxi(0, int(cfg.get_value("workshop", "samples", 0)))
		for id in Array(cfg.get_value("workshop", "research", [])):
			if Parts.is_valid(String(id)):
				research.append(String(id))
		var paid_in := cfg.get_value("workshop", "job_paid", {}) as Dictionary
		for k in paid_in:
			job_paid[String(k)] = maxi(0, int(paid_in[k]))
		var fz_in := cfg.get_value("workshop", "fuses", {}) as Dictionary
		for k in fz_in:
			if Throwables.FUSES.has(String(k)):
				fuses[String(k)] = clampi(int(fz_in[k]), 0, (Throwables.FUSES[String(k)] as Array).size() - 1)
		for k in Array(cfg.get_value("workshop", "orders", [])):
			if Throwables.is_ammo(String(k)):
				orders.append(String(k))
		for w in Array(cfg.get_value("workshop", "unlocked", [])):
			unlocked[int(w)] = true
		for m in Array(cfg.get_value("workshop", "trophies", [])):
			trophies[String(m)] = true
		for m in Array(cfg.get_value("campaign", "cleared", [])):
			cleared[String(m)] = true
		Arsenal.load_gear(cfg.get_value("gear", "stock", {}) as Dictionary)       # zapas zaopatrzenia z poprzednich sesji
		_set_parts(Array(cfg.get_value("workshop", "parts", [])))
		migrate_levels(cfg.get_value("workshop", "levels", {}) as Dictionary)
		var saved_ready: Dictionary = cfg.get_value("workshop", "deliveries", {}) as Dictionary
		for k in saved_ready:
			if Throwables.is_ammo(String(k)) and int(saved_ready[k]) > 0:
				deliveries[String(k)] = int(saved_ready[k])
		_reconcile_jobs()
		save_progress(path)
	loot = 0
	last_gain = 0
	changed.emit()

## Zapis sprzed 1.7.319: poziomy ulepszeń (id broni → 0..3) → części tych poziomów. Gniazdo bez wyboru gracza montuje je samo
## (Profile.migrate_fits utrwala ten wybór jednorazowo), więc stary zestaw zachowuje części i ich koszty.
func migrate_levels(old_levels: Dictionary) -> void:
	for k in old_levels:
		var w := int(k)
		if Weapons.is_valid(w):
			for id in Parts.from_level(String(Weapons.def(w).key), int(old_levels[k])):
				parts[String(id)] = true

func save_progress(path := "") -> void:
	if not persist or not NoiseMgr.is_server():
		return
	if path == "":
		path = Characters.file(SAVE_FILE)
		if path == "":
			return
	var cfg := ConfigFile.new()
	# Np. trofeum bossa może zapisać postęp jeszcze przed ekstrakcją. Nie utrwalamy przy tym tymczasowych nabojów.
	var use_checkpoint := _delivery_checkpointed and not NoiseMgr.safe_zone and not _delivery_committed
	cfg.load(path)
	cfg.set_value("scrap", "bank", bank)
	cfg.set_value("workshop", "unlocked", unlocked.keys())
	cfg.set_value("workshop", "trophies", trophies.keys())
	cfg.set_value("campaign", "cleared", cleared.keys())
	cfg.set_value("gear", "stock", Arsenal._snapshot if use_checkpoint else Arsenal.stock)
	cfg.set_value("workshop", "parts", parts.keys())
	cfg.set_value("workshop", "fit_policy_version", 1)
	cfg.set_value("workshop", "orders", orders)
	cfg.set_value("workshop", "deliveries", _delivery_snapshot if use_checkpoint else deliveries)
	cfg.set_value("workshop", "fuses", fuses)
	cfg.set_value("workshop", "samples", samples)
	cfg.set_value("workshop", "research", research)
	cfg.set_value("workshop", "schematics", schematics.keys())
	cfg.set_value("workshop", "lathe", lathe)
	cfg.set_value("workshop", "job_paid", job_paid)
	if cfg.has_section_key("workshop", "levels"):
		cfg.erase_section_key("workshop", "levels")             # przeniesione do części (migracja w load_progress)
	cfg.save(path)
