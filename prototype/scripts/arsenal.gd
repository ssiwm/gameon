extends Node
## Autoload „Arsenal": amunicja WSPÓŁDZIELONA drużyny (GDD §6 — „jeden typ na broń")
## i zdarzenia walki rozsyłane przez sieć (efekty trafień, wybuchy, potwierdzenia).
##
## Model amunicji: magazynek należy do gracza (kontroler broni), zapas jest wspólny
## i autorytatywny na serwerze. Gracz prosi o naboje przy KOŃCU przeładowania
## (request_rounds), serwer zdejmuje je z zapasu i odsyła przyznaną liczbę.
## Dzięki temu dwóch graczy z tą samą bronią nie wyda tych samych naboi dwa razy,
## a anulowane przeładowanie nic nie kosztuje.
##
## Kalibry (od 1.7.317, ammo.gd): zapas naboi zwykłych leży pod kluczem kalibru (`Ammo.pool_key`) — SPREAD-12 i PELLET-8 biorą 12/70
## z jednej puli, a jej sufit to największy sufit broni tego kalibru. Amunicja specjalna (typ > 0) nie jest w `reserve`, tylko
## w zapasie zaopatrzenia `stock` pod wpisem `ammo_*` (w nabojach): przechodzi między misjami, wraca po wipe i zapisuje się u hosta
## jak granaty. Funkcje zapasu przyjmują id broni i typ naboju `t` (0 = zwykły).

const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Parts := preload("res://scripts/parts.gd")

## Materiał trafionego celu — dobiera efekt i dźwięk uderzenia.
enum Mat { FLESH, ARMOR, WOOD, METAL, WORLD }
## Co strzelec widzi po trafieniu (hitmarker).
enum Confirm { HIT, CRIT, KILL, ARMOR }

signal reserve_changed
signal hit_confirmed(kind: int, pos: Vector2)
signal weapon_hit(kind: int, weapon: int, rank: int)    ## trafienie lokalnego strzelca z bronią (wprawa §7.3, historia §7.4); tylko żywe cele; rank: 1 elita, 2 boss
signal rounds_granted(weapon: int, count: int)

var reserve: Dictionary = {}
var returned: Dictionary = {}            ## zwykłe naboje zwrócone przy pełnej puli; zużywane przed zapasem, bez mnożnika znajdziek
var stock: Dictionary = {}               ## rzucane przedmioty (throwables.gd): rodzaj → liczba, wspólny zapas drużyny
var throw_sel := 0                       ## wybrany rodzaj u TEGO gracza (indeks w Throwables.ORDER), nie replikowany
signal stock_changed

func _ready() -> void:
	_reset_local()
	multiplayer.peer_connected.connect(_on_peer_connected)

func _reset_local() -> void:
	var special := {}                       # amunicja specjalna nie wraca do zestawu startowego (kupiona — zostaje)
	for k in Throwables.AMMO_ORDER:
		if not NightShift.active and stock.has(k):
			special[k] = stock[k]
	stock = Throwables.issue_stock()
	stock.merge(special)
	stock_changed.emit()
	reserve.clear()
	returned.clear()
	for d in Weapons.defs():
		if d.uses_ammo() and not d.infinite:
			var key := pool(d.id)
			reserve[key] = maxi(int(reserve.get(key, 0)), int(d.reserve_start * NightShift.ammo_mult()))
	reserve_changed.emit()

## Klucz puli naboi zwykłych broni `w` (wspólny dla broni jednego kalibru).
func pool(w: int) -> int:
	return Ammo.pool_key(w, String(Weapons.def(w).caliber))

## Sufit puli: największy sufit broni, które z niej biorą (z ulepszeniami drużyny).
func pool_max(w: int) -> int:
	var key := pool(w)
	var m := 0
	for d in Weapons.defs():
		if pool(d.id) == key:
			m = maxi(m, Weapons.def(d.id).reserve_max)
	return m

## Wpis zaopatrzenia z amunicją specjalną typu `t` dla broni `w` ("" = nabój zwykły z puli misji).
func special_kind(w: int, t: int) -> String:
	return Ammo.kind_of(String(Weapons.def(w).caliber), t)

## Granaty i inne rzucane przedmioty wracają do zapasu startowego przy każdej misji i próbie (też z carry z kryjówki — jak flary).
func reset_throwables() -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		return
	stock = Throwables.issue_stock()
	_snapshot = stock.duplicate()
	_push_stock()

var _snapshot: Dictionary = {}           ## stan zapasu z początku misji — wipe i ponowna próba do niego wracają

## Początek misji (serwer): nowa misja (`new_run`) zachowuje zapas z poprzedniej, dopełnia go do zestawu `issue` i zapamiętuje;
## ponowna próba po wipe wraca do zapamiętanego stanu. Nocny Dyżur zawsze dostaje sam zestaw `issue` (bez złomu nie ma zakupów).
func begin_mission(new_run: bool) -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		return
	if NightShift.active:
		stock = Throwables.issue_stock()
	elif new_run or _snapshot.is_empty():
		for k in Throwables.ORDER:
			stock[k] = maxi(get_throwable(String(k)), int(Throwables.KINDS[k]["issue"]))
	else:
		stock = _snapshot.duplicate()
	_snapshot = stock.duplicate()
	_push_stock()
	Scrap.delivery_checkpoint(new_run)       # zwroty z nieudanej misji nie mogą podwoić zachowanego zapasu

## Zapas wczytany z zapisu hosta (scrap.gd) — tylko znane rodzaje, w granicach maksimum.
func load_gear(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	for k in Throwables.SHOP_ORDER:
		if saved.has(k):
			stock[k] = clampi(int(saved[k]), 0, int(Throwables.KINDS[k]["max"]))
	_snapshot = stock.duplicate()
	stock_changed.emit()

## Serwer: początek misji / nowa próba. Klienci dostają nowy stan przez sync.
func reset_mission() -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		return
	_reset_local()
	_push()

func get_reserve(w: int, t := 0) -> int:
	var d := Weapons.def(w)
	if t > 0:
		var sk := special_kind(w, t)
		return get_throwable(sk) if sk != "" else 0
	if d.infinite:
		return 9999
	return int(reserve.get(pool(w), 0)) + int(returned.get(pool(w), 0))

func is_full(w: int, t := 0) -> bool:
	var d := Weapons.def(w)
	if t > 0:
		var sk := special_kind(w, t)
		return sk == "" or get_throwable(sk) >= int(Throwables.KINDS[sk]["max"])
	return d.infinite or get_reserve(w) >= pool_max(w)

## Ustawia zapas (serwer; testy i narzędzia) — pula kalibru albo amunicja specjalna.
func set_reserve(w: int, n: int, t := 0) -> void:
	if t > 0:
		var sk := special_kind(w, t)
		if sk != "":
			stock[sk] = maxi(0, n)
			_push_stock()
		return
	reserve[pool(w)] = maxi(0, n)
	returned.erase(pool(w))
	_push()

# ---------------------------------------------------------------- zapas (serwer)

## Dodaje naboje do zapasu (skrzynka, znaleziona broń, zwrot z porzuconego magazynka).
## Zwraca ile faktycznie weszło (zapas ma sufit).
func add_reserve(w: int, n: int, t := 0) -> int:
	if not NoiseMgr.is_server():
		return 0
	var d := Weapons.def(w)
	if not d.uses_ammo():
		return 0
	if t > 0:
		var sk := special_kind(w, t)
		return add_throwable(sk, n) if sk != "" and n > 0 else 0          # zwrot amunicji specjalnej (wymiana typu, porzucona broń)
	if d.infinite:
		return 0
	var key := pool(w)
	var before := int(reserve.get(key, 0))
	var gained := n if n <= 0 else maxi(1, int(round(n * NightShift.ammo_mult())))     # AMMO FAMINE: połowa naboi
	var after := mini(pool_max(w), before + gained)
	reserve[key] = after
	_push()
	return after - before

func take_rounds(w: int, want: int, t := 0) -> int:
	if not NoiseMgr.is_server():
		return 0
	var d := Weapons.def(w)
	if t > 0:
		var sk := special_kind(w, t)
		var have_s := get_throwable(sk) if sk != "" else 0
		var got_s := mini(have_s, want)
		if got_s > 0:
			stock[sk] = have_s - got_s
			_push_stock()
		return got_s
	if d.infinite:
		return want
	var key := pool(w)
	var held := int(returned.get(key, 0))
	var from_return := mini(held, maxi(0, want))
	if from_return > 0:
		returned[key] = held - from_return
	var have := int(reserve.get(key, 0))
	var got := mini(have, maxi(0, want - from_return))
	if got > 0 or from_return > 0:
		reserve[key] = have - got
		_push()
	return got + from_return

func _push() -> void:
	reserve_changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync_reserve.rpc(reserve, returned)

func _on_peer_connected(id: int) -> void:
	if NoiseMgr.is_server():
		_sync_reserve.rpc_id(id, reserve, returned)
		_sync_stock.rpc_id(id, stock)

# ---------------------------------------------------------------- rzucane przedmioty

func get_throwable(kind: String) -> int:
	return int(stock.get(kind, 0))

## Serwer: dokłada do zapasu (skrzynki, zakup w warsztacie). Zwraca ile weszło (sufit z throwables.gd).
func add_throwable(kind: String, n: int) -> int:
	if not NoiseMgr.is_server() or not Throwables.is_valid(kind):
		return 0
	var before := get_throwable(kind)
	stock[kind] = mini(int(Throwables.KINDS[kind]["max"]), before + n)
	_push_stock()
	return get_throwable(kind) - before

func _push_stock() -> void:
	stock_changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync_stock.rpc(stock)

@rpc("authority", "call_remote", "reliable")
func _sync_stock(data: Dictionary) -> void:
	stock = data
	stock_changed.emit()

## Klawisz X: kolejny rodzaj przedmiotu (lokalnie); puste rodzaje pomijamy, jeśli jest jakiś z zapasem.
func cycle_throwable() -> void:
	var n := Throwables.ORDER.size()
	var next := (throw_sel + 1) % n
	for i in n:
		var cand := (throw_sel + 1 + i) % n
		if get_throwable(String(Throwables.ORDER[cand])) > 0:
			next = cand
			break
	throw_sel = next
	stock_changed.emit()

func selected_throwable() -> String:
	return String(Throwables.ORDER[throw_sel % Throwables.ORDER.size()])

## Rzut (lewy Alt): serwer sprawdza zapas, zdejmuje sztukę i tworzy granat u wszystkich peerów (level.spawn_grenade).
func request_throw(kind: String, pos: Vector2, vel: Vector2) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_throw_server(kind, pos, vel, NoiseMgr.local_id())
	else:
		_throw_request.rpc_id(1, kind, pos, vel)

@rpc("any_peer", "call_remote", "reliable")
func _throw_request(kind: String, pos: Vector2, vel: Vector2) -> void:
	if NoiseMgr.is_server():
		_throw_server(kind, pos, vel, multiplayer.get_remote_sender_id())

func _throw_server(kind: String, pos: Vector2, vel: Vector2, shooter: int) -> void:
	if not Throwables.is_valid(kind) or get_throwable(kind) <= 0 or Throwables.mode_of(kind) in ["use", "ammo"]:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.player_id) == shooter:
			if p.dead:
				return
			if p.global_position.distance_to(pos) > 80.0:
				pos = p.global_position + Vector2(0, -12)         # wylot za daleko od rzucającego — korekta jak przy strzale
			break
	stock[kind] = get_throwable(kind) - 1
	_push_stock()
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return
	match Throwables.mode_of(kind):
		"throw":
			lvl.spawn_grenade(kind, pos, vel.limit_length(420.0), shooter)
		"place":
			lvl.spawn_placed(kind, pos, vel.normalized() if vel.length() > 0.1 else Vector2.RIGHT, shooter)
		_:
			pass

@rpc("authority", "call_remote", "reliable")
func _sync_reserve(data: Dictionary, overflow: Dictionary = {}) -> void:
	reserve = data
	returned = overflow
	reserve_changed.emit()

## Gracz (właściciel magazynka) prosi o `want` naboi na koniec przeładowania.
## Wołane lokalnie na serwerze albo przez sieć z klienta; odpowiedź = rounds_granted.
func request_rounds(w: int, want: int, t := 0) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		rounds_granted.emit(w, take_rounds(w, want, t))
	else:
		_req_rounds.rpc_id(1, w, want, t)

## Zwrot / porzucenie naboi do wspólnego zapasu (porzucona broń, nadmiar z przerwanego przeładowania, wymiana typu naboju).
func deposit(w: int, n: int, t := 0) -> void:
	if n <= 0:
		return
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_return_rounds(w, n, t)
	else:
		_deposit_rpc.rpc_id(1, w, n, t)

@rpc("any_peer", "call_remote", "reliable")
func _deposit_rpc(w: int, n: int, t: int) -> void:
	if not NoiseMgr.is_server() or not Weapons.is_valid(w) or not _is_human_peer(multiplayer.get_remote_sender_id()):
		return
	if not Ammo.valid(String(Weapons.def(w).caliber), t):
		return
	_return_rounds(w, clampi(n, 0, Parts.max_capacity(Weapons.def(w))), t)       # magazynek z nabojem w komorze (30+1)

## Zwrot własnych nabojów nie jest znaleziskiem: pełna pula i AMMO FAMINE nie mogą ich skasować.
func _return_rounds(w: int, n: int, t: int) -> void:
	if not NoiseMgr.is_server() or not Weapons.is_valid(w) or n <= 0:
		return
	var d := Weapons.def(w)
	if not d.uses_ammo() or d.infinite or not Ammo.valid(String(d.caliber), t):
		return
	if t > 0:
		var kind := special_kind(w, t)
		var accepted := add_throwable(kind, n)
		if accepted < n:
			Scrap.deliveries[kind] = int(Scrap.deliveries.get(kind, 0)) + n - accepted
			if NoiseMgr.safe_zone:
				Scrap.save_progress()      # w misji zwrot jest tymczasowy, jak reszta zaopatrzenia
			Scrap._push()
		return
	var key := pool(w)
	var put := mini(n, maxi(0, pool_max(w) - int(reserve.get(key, 0))))
	reserve[key] = int(reserve.get(key, 0)) + put
	if put < n:
		returned[key] = int(returned.get(key, 0)) + n - put
	_push()

## Czy `peer_id` to żywy człowiek w tej sesji (serwer nie przyjmuje zwrotów naboi od obcych).
func _is_human_peer(peer_id: int) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == peer_id and not p.is_bot and not p.dead:
			return true
	return false

@rpc("any_peer", "call_remote", "reliable")
func _req_rounds(w: int, want: int, t: int) -> void:
	if not NoiseMgr.is_server() or not Weapons.is_valid(w):
		return
	var got := 0
	if Ammo.valid(String(Weapons.def(w).caliber), t):
		got = take_rounds(w, clampi(want, 0, Parts.max_capacity(Weapons.def(w))), t)
	_grant.rpc_id(multiplayer.get_remote_sender_id(), w, got)

@rpc("authority", "call_remote", "reliable")
func _grant(w: int, n: int) -> void:
	rounds_granted.emit(w, n)

## Broń, do której warto upuścić amunicję: noszona przez żywego człowieka, z zapasem
## poniżej 80% maksimum (nic nie wypada „na zapas”). -1 = nic nie potrzeba.
func pick_drop_weapon() -> int:
	var cands: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		for w in p.kit_primaries():
			var d := Weapons.def(w)
			if not d.infinite and get_reserve(w) < int(pool_max(w) * 0.8) and not cands.has(w):
				cands.append(w)
	return -1 if cands.is_empty() else int(cands.pick_random())

## Amunicja specjalna do upuszczenia przez elitę (od 1.7.318): losowy typ kalibru, z którego strzela broń noszona przez żywego człowieka,
## o ile zapas tego typu nie jest pełny. "" = nic nie potrzeba.
func pick_special_drop() -> String:
	var cands: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		for w in p.kit_primaries():
			var cal := String(Weapons.def(w).caliber)
			for t in range(1, Ammo.count(cal)):
				var sk := Ammo.kind_of(cal, t)
				if Ammo.is_press_only(cal, t):
					continue                                     # ładunki z prasy (W4) robi się w kryjówce, nie znajduje
				if sk != "" and not cands.has(sk) and get_throwable(sk) < int(Throwables.KINDS[sk]["max"]):
					cands.append(sk)
	return "" if cands.is_empty() else String(cands.pick_random())

# ---------------------------------------------------------------- zdarzenia walki

## Serwer: efekt trafienia widoczny i słyszalny u wszystkich peerów.
func broadcast_hit(pos: Vector2, dir: Vector2, mat: int, crit: bool, heavy: bool) -> void:
	if NoiseMgr.has_network():
		_hit_fx.rpc(pos, dir, mat, crit, heavy)
	else:
		_hit_fx(pos, dir, mat, crit, heavy)

@rpc("authority", "call_local", "unreliable")
func _hit_fx(pos: Vector2, dir: Vector2, mat: int, crit: bool, heavy: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else scene
	Vfx.hit(parent, pos, dir, mat, crit, heavy)

## Serwer: linka SINEW-6 — kreska od strzelca do trafionego wroga u wszystkich peerów.
func broadcast_tether(a: Vector2, b: Vector2) -> void:
	if NoiseMgr.has_network():
		_tether_fx.rpc(a, b)
	else:
		_tether_fx(a, b)

@rpc("authority", "call_local", "unreliable")
func _tether_fx(a: Vector2, b: Vector2) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	Vfx.streak(lvl if lvl != null else get_tree().current_scene, a, b, Color(0.86, 0.8, 0.62), 1.0, 0.45)

## Serwer: wybuch — efekt wszędzie (obrażenia liczy Combat.explode na serwerze).
func broadcast_explosion(pos: Vector2, radius: float) -> void:
	if NoiseMgr.has_network():
		_explosion_fx.rpc(pos, radius)
	else:
		_explosion_fx(pos, radius)

@rpc("authority", "call_local", "reliable")
func _explosion_fx(pos: Vector2, radius: float) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_tree().current_scene
	Vfx.explosion(parent, pos, radius)

## Serwer: hitmarker dla strzelca (człowiek — przez sieć, host — lokalnie, bot — nic). `w` — broń trafienia w żywy cel (−1: skrzynia, beczka).
func confirm(shooter_id: int, kind: int, pos: Vector2, w := -1, rank := 0) -> void:
	if not NoiseMgr.has_network():
		hit_confirmed.emit(kind, pos)
		if shooter_id == NoiseMgr.local_id() and w >= 0:
			weapon_hit.emit(kind, w, rank)
	elif shooter_id == NoiseMgr.local_id():
		hit_confirmed.emit(kind, pos)
		if w >= 0:
			weapon_hit.emit(kind, w, rank)
	elif multiplayer.get_peers().has(shooter_id):
		if rank > 0:
			_confirm_rank_rpc.rpc_id(shooter_id, kind, pos, w, rank)      # zabicie elity / bossa nie może zginąć w sieci (nacięcie)
		else:
			_confirm_rpc.rpc_id(shooter_id, kind, pos, w)

@rpc("authority", "call_remote", "unreliable")
func _confirm_rpc(kind: int, pos: Vector2, w := -1) -> void:
	hit_confirmed.emit(kind, pos)
	if w >= 0:
		weapon_hit.emit(kind, w, 0)

@rpc("authority", "call_remote", "reliable")
func _confirm_rank_rpc(kind: int, pos: Vector2, w: int, rank: int) -> void:
	hit_confirmed.emit(kind, pos)
	if w >= 0:
		weapon_hit.emit(kind, w, rank)

# ---------------------------------------------------------------- narzędzia (apteczka, defibrylator, skaner)

func _player_by_id(id: int) -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.player_id) == id:
			return p
	return null

## Użycie narzędzia (klawisz użycia przy celu): serwer sprawdza zapas, cel i odległość, zdejmuje sztukę i stosuje efekt.
## `target_id` — gracz-cel (apteczka, defibrylator); skaner go nie używa (efekt lokalny u użytkownika).
func request_use(kind: String, target_id: int) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_use_server(kind, target_id, NoiseMgr.local_id())
	else:
		_use_request.rpc_id(1, kind, target_id)

@rpc("any_peer", "call_remote", "reliable")
func _use_request(kind: String, target_id: int) -> void:
	if NoiseMgr.is_server():
		_use_server(kind, target_id, multiplayer.get_remote_sender_id())

## Bot (działa na serwerze) używa narzędzia w imieniu swojej postaci.
func use_as(kind: String, target_id: int, user_id: int) -> void:
	if NoiseMgr.is_server():
		_use_server(kind, target_id, user_id)

func _use_server(kind: String, target_id: int, user_id: int) -> void:
	if not Throwables.is_valid(kind) or Throwables.mode_of(kind) != "use" or get_throwable(kind) <= 0:
		return
	var user := _player_by_id(user_id)
	if user == null or user.dead:
		return
	var data: Dictionary = Throwables.KINDS[kind]
	var ok := false
	match kind:
		"medkit":
			var t := _player_by_id(target_id)
			ok = t != null and not t.dead and t.hp < t.max_hp() and user.global_position.distance_to(t.global_position) <= float(data["range"]) + 24.0
			if ok:
				t.deliver_heal(1)
		"defib":
			var t2 := _player_by_id(target_id)
			ok = t2 != null and t2.dead and user.global_position.distance_to(t2.global_position) <= float(data["range"]) + 24.0
			if ok:
				t2.request_revive()
		"scanner":
			ok = true
		"cleankit":
			ok = true                                       # stan broni siedzi w profilu użytkownika — efekt nakłada jego klient
			if NoiseMgr.has_network() and user_id != NoiseMgr.local_id():
				user.weapons.cleankit_done.rpc_id(user_id)
			else:
				user.weapons.cleankit_done()
	if ok:
		stock[kind] = get_throwable(kind) - 1
		_push_stock()
