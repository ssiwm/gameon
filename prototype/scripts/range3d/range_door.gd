extends Node2D
## Drzwi strzelnicy FPP w kryjówce (RANGE_FPS_PLAN.md, etap 1; RANGE_DOOR z danych mapy). Stalowe drzwi w tylnej ścianie dolnego poziomu
## z tablicą rekordów drużyny obok (obraz: view3d.gd, grupa „range_door”). [E] przy drzwiach przenosi lokalnego gracza na strzelnicę
## (fp_mode.gd): jego postać zostaje zaparkowana przy drzwiach (`player.in_range`, replikowane — inni widzą „RANGE” na plakietce).
##
## Wynik ćwiczenia „5 blach na czas” liczy klient (range_sim.gd), ale tablicę prowadzi serwer: przyjmuje wynik tylko od gracza, który stoi
## na strzelnicy z tą bronią w ręku, i tylko wiarygodny (`plausible`: czas nie krótszy niż odstęp między strzałami broni × najmniejsza liczba
## strzałów na pięć blach). Tablicę trzyma host (Settings.range_board) i rozsyła ją wszystkim; dołączający prosi o nią sam.

const FpRange := preload("res://scripts/range3d/fp_mode.gd")
const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const Weapons := preload("res://scripts/weapons.gd")

const REACH_X := 34.0
const REACH_Y := 40.0
const BOARD_MAX := 5                  ## wierszy na tablicy (najlepsze wyniki; jeden wiersz na gracza i broń)
const RATE_SLACK := 0.75              ## tolerancja odstępu między strzałami (części broni, zaokrąglenia kroku fizyki)

var local_in_range := false
var board: Array = []                 ## [{who, t, w}, …] rosnąco po czasie — kopia serwera
var last := {}                        ## ostatni przyjęty wynik {who, t, w, record} (tablica w tunelu, toast)
var rejected := 0                     ## serwer: odrzucone wyniki (testy)

func _ready() -> void:
	add_to_group("range_door")
	if NoiseMgr.is_server():
		board = Settings.range_board.duplicate(true)
		if "--shotrangeboard" in OS.get_cmdline_user_args():             # dev: przykładowa tablica do zrzutów (bez zapisu)
			board = [{"who": "P2", "t": 2.84, "w": Weapons.M83}, {"who": "P1", "t": 3.12, "w": Weapons.SPREAD12}, {"who": "P1", "t": 4.07, "w": Weapons.P64}]
	else:
		_request.call_deferred()

func _request() -> void:
	if NoiseMgr.has_network():
		_request_rpc.rpc_id(1)

func _physics_process(_delta: float) -> void:
	local_in_range = false
	var me := _local_player()
	if me == null or me.get("fp") != null:
		return
	local_in_range = absf(me.global_position.x - global_position.x) <= REACH_X and absf(me.global_position.y - global_position.y) <= REACH_Y
	if local_in_range and Input.is_action_just_pressed("interact"):
		enter(me)

func _local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			return p
	return null

## Lokalny gracz `p` wchodzi na strzelnicę. Zwraca węzeł trybu (fp_mode.gd).
func enter(p: Node2D) -> Node:
	var fp: Node = FpRange.enter(p)
	fp.door = self
	return fp

## Najlepszy czas drużyny (−1: brak).
func best() -> float:
	return float((board[0] as Dictionary)["t"]) if not board.is_empty() else -1.0

## Czy przebieg w `t` s z broni `w` jest możliwy: pierwsza blacha pada przy pierwszym strzale, ostatnia najwcześniej przy strzale nr `min_shots`
## (strzelba: śrut może położyć dwie blachy naraz), a między strzałami musi minąć `cooldown` broni.
static func plausible(t: float, shots: int, w: int) -> bool:
	if w < 0 or w >= Weapons.COUNT or not is_finite(t) or t <= 0.0:
		return false
	var d = Weapons.def(w)
	var plates := RangeSim.PLATES.size()
	var min_shots := plates if int(d.pellets) <= 1 else ceili(float(plates) / 2.0)
	return shots >= min_shots and t >= float(min_shots - 1) * float(d.cooldown) * RATE_SLACK

# ---------------------------------------------------------------- wynik

## Lokalny gracz ukończył przebieg (fp_mode.gd): wynik idzie do serwera.
func submit(t: float, shots: int, w: int) -> void:
	if NoiseMgr.is_server():
		_accept(multiplayer.get_unique_id(), t, shots, w)
	else:
		_submit_rpc.rpc_id(1, t, shots, w)

@rpc("any_peer", "call_remote", "reliable")
func _submit_rpc(t: float, shots: int, w: int) -> void:
	if not NoiseMgr.is_server():
		return
	_accept(multiplayer.get_remote_sender_id(), t, shots, w)

## Serwer: sprawdza wynik i dopisuje go do tablicy (jeden wiersz na gracza i broń, BOARD_MAX najlepszych).
func _accept(peer: int, t: float, shots: int, w: int) -> void:
	var p := _player_of(peer)
	if p == null or not bool(p.get("in_range")) or int(p.get("weapon")) != w or not plausible(t, shots, w):
		rejected += 1
		return
	var who := "P%d" % int(p.get("display_id"))
	var record := board.is_empty() or t < best()
	var nb: Array = []
	var mine := false
	for e in board:
		if String(e["who"]) == who and int(e["w"]) == w:
			mine = true
			nb.append({"who": who, "t": minf(t, float(e["t"])), "w": w})
		else:
			nb.append(e)
	if not mine:
		nb.append({"who": who, "t": t, "w": w})
	nb.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	nb.resize(mini(nb.size(), BOARD_MAX))
	Settings.save_range_board(nb)
	var res := {"who": who, "t": t, "w": w, "record": record}
	if NoiseMgr.has_network():
		_board_rpc.rpc(nb, res)
	else:
		_board_rpc(nb, res)

func _player_of(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and int(p.player_id) == peer and not p.is_queued_for_deletion():
			return p
	return null

@rpc("any_peer", "call_remote", "reliable")
func _request_rpc() -> void:
	if NoiseMgr.is_server():
		_board_rpc.rpc_id(multiplayer.get_remote_sender_id(), board, {})

@rpc("authority", "call_local", "reliable")
func _board_rpc(b: Array, res: Dictionary) -> void:
	board = b
	if res.is_empty():
		return
	last = res
	var wname: String = Weapons.def(int(res["w"])).name
	Msg.post("range.result", Msg.Ch.TOAST, tr("Range: %s — 5 plates in %.2f s (%s)") % [String(res["who"]), float(res["t"]), wname],
		{"sub": tr("New squad record!") if bool(res["record"]) else tr("Squad record: %.2f s") % best(),
		"style": Msg.Style.SUCCESS if bool(res["record"]) else Msg.Style.INFO, "ttl": 5.0, "prio": 70})
