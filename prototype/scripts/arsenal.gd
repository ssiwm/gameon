extends Node
## Autoload „Arsenal": amunicja WSPÓŁDZIELONA drużyny (GDD §6 — „jeden typ na broń")
## i zdarzenia walki rozsyłane przez sieć (efekty trafień, wybuchy, potwierdzenia).
##
## Model amunicji: magazynek należy do gracza (kontroler broni), zapas jest wspólny
## i autorytatywny na serwerze. Gracz prosi o naboje przy KOŃCU przeładowania
## (request_rounds), serwer zdejmuje je z zapasu i odsyła przyznaną liczbę.
## Dzięki temu dwóch graczy z tą samą bronią nie wyda tych samych naboi dwa razy,
## a anulowane przeładowanie nic nie kosztuje.

const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Throwables := preload("res://scripts/throwables.gd")

## Materiał trafionego celu — dobiera efekt i dźwięk uderzenia.
enum Mat { FLESH, ARMOR, WOOD, METAL, WORLD }
## Co strzelec widzi po trafieniu (hitmarker).
enum Confirm { HIT, CRIT, KILL, ARMOR }

signal reserve_changed
signal hit_confirmed(kind: int, pos: Vector2)
signal rounds_granted(weapon: int, count: int)

var reserve: Dictionary = {}
var stock: Dictionary = {}               ## rzucane przedmioty (throwables.gd): rodzaj → liczba, wspólny zapas drużyny
var throw_sel := 0                       ## wybrany rodzaj u TEGO gracza (indeks w Throwables.ORDER), nie replikowany
signal stock_changed

func _ready() -> void:
	_reset_local()
	multiplayer.peer_connected.connect(_on_peer_connected)

func _reset_local() -> void:
	stock = Throwables.start_stock()
	stock_changed.emit()
	reserve.clear()
	for d in Weapons.defs():
		if d.uses_ammo() and not d.infinite:
			reserve[d.id] = int(d.reserve_start * NightShift.ammo_mult())
	reserve_changed.emit()

## Granaty i inne rzucane przedmioty wracają do zapasu startowego przy każdej misji i próbie (też z carry z kryjówki — jak flary).
func reset_throwables() -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		return
	stock = Throwables.start_stock()
	_push_stock()

## Serwer: początek misji / nowa próba. Klienci dostają nowy stan przez sync.
func reset_mission() -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		return
	_reset_local()
	_push()

func get_reserve(w: int) -> int:
	var d := Weapons.def(w)
	if d.infinite:
		return 9999
	return int(reserve.get(w, 0))

func is_full(w: int) -> bool:
	var d := Weapons.def(w)
	return d.infinite or get_reserve(w) >= d.reserve_max

# ---------------------------------------------------------------- zapas (serwer)

## Dodaje naboje do zapasu (skrzynka, znaleziona broń, zwrot z porzuconego magazynka).
## Zwraca ile faktycznie weszło (zapas ma sufit).
func add_reserve(w: int, n: int) -> int:
	if not NoiseMgr.is_server():
		return 0
	var d := Weapons.def(w)
	if d.infinite or not d.uses_ammo():
		return 0
	var before := int(reserve.get(w, 0))
	var gained := n if n <= 0 else maxi(1, int(round(n * NightShift.ammo_mult())))     # AMMO FAMINE: połowa naboi
	var after := mini(d.reserve_max, before + gained)
	reserve[w] = after
	_push()
	return after - before

func take_rounds(w: int, want: int) -> int:
	if not NoiseMgr.is_server():
		return 0
	var d := Weapons.def(w)
	if d.infinite:
		return want
	var have := int(reserve.get(w, 0))
	var got := mini(have, want)
	if got > 0:
		reserve[w] = have - got
		_push()
	return got

func _push() -> void:
	reserve_changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync_reserve.rpc(reserve)

func _on_peer_connected(id: int) -> void:
	if NoiseMgr.is_server():
		_sync_reserve.rpc_id(id, reserve)
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

## Klawisz X: kolejny rodzaj rzucanego przedmiotu (lokalnie).
func cycle_throwable() -> void:
	throw_sel = (throw_sel + 1) % Throwables.ORDER.size()
	stock_changed.emit()

func selected_throwable() -> String:
	return String(Throwables.ORDER[throw_sel % Throwables.ORDER.size()])

## Rzut (T): serwer sprawdza zapas, zdejmuje sztukę i tworzy granat u wszystkich peerów (level.spawn_grenade).
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
	if not Throwables.is_valid(kind) or get_throwable(kind) <= 0:
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
	if lvl != null:
		lvl.spawn_grenade(kind, pos, vel.limit_length(420.0), shooter)

@rpc("authority", "call_remote", "reliable")
func _sync_reserve(data: Dictionary) -> void:
	reserve = data
	reserve_changed.emit()

## Gracz (właściciel magazynka) prosi o `want` naboi na koniec przeładowania.
## Wołane lokalnie na serwerze albo przez sieć z klienta; odpowiedź = rounds_granted.
func request_rounds(w: int, want: int) -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		rounds_granted.emit(w, take_rounds(w, want))
	else:
		_req_rounds.rpc_id(1, w, want)

## Zwrot / porzucenie naboi do wspólnego zapasu (porzucona broń, nadmiar z przerwanego przeładowania).
func deposit(w: int, n: int) -> void:
	if n <= 0:
		return
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		add_reserve(w, n)
	else:
		_deposit_rpc.rpc_id(1, w, n)

@rpc("any_peer", "call_remote", "reliable")
func _deposit_rpc(w: int, n: int) -> void:
	if NoiseMgr.is_server() and Weapons.is_valid(w):
		add_reserve(w, clampi(n, 0, Weapons.def(w).mag))

@rpc("any_peer", "call_remote", "reliable")
func _req_rounds(w: int, want: int) -> void:
	if not NoiseMgr.is_server() or not Weapons.is_valid(w):
		return
	var got := take_rounds(w, clampi(want, 0, Weapons.def(w).mag))
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
			if not d.infinite and get_reserve(w) < int(d.reserve_max * 0.8) and not cands.has(w):
				cands.append(w)
	return -1 if cands.is_empty() else int(cands.pick_random())

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

## Serwer: hitmarker dla strzelca (człowiek — przez sieć, host — lokalnie, bot — nic).
func confirm(shooter_id: int, kind: int, pos: Vector2) -> void:
	if not NoiseMgr.has_network():
		hit_confirmed.emit(kind, pos)
	elif shooter_id == NoiseMgr.local_id():
		hit_confirmed.emit(kind, pos)
	elif multiplayer.get_peers().has(shooter_id):
		_confirm_rpc.rpc_id(shooter_id, kind, pos)

@rpc("authority", "call_remote", "unreliable")
func _confirm_rpc(kind: int, pos: Vector2) -> void:
	hit_confirmed.emit(kind, pos)
