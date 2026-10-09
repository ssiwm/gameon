extends Node
## Czat tekstowy drużyny (klawisz T): wiadomość idzie do serwera, który ją sprawdza (długość, znaki sterujące, tempo — klient nie
## jest zaufany) i rozsyła do wszystkich z etykietą nadawcy (P1, P2…). HUD rysuje linie z sygnału `line_added`.
## Węzeł „Chat" tworzy main.gd na każdym peerze pod tą samą ścieżką (wymóg RPC).

signal line_added(who: String, text: String)

const MAX_LEN := 120
const MIN_GAP_MS := 600

var _last_ms := {}                   ## peer id → czas ostatniej przyjętej wiadomości (ticks ms)

## Usuwa znaki sterujące i ucina do MAX_LEN; "" = nic do wysłania.
static func sanitize(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code != 127:
			out += raw[i]
	return out.strip_edges().substr(0, MAX_LEN).strip_edges()

## Wysyła wiadomość lokalnego gracza (host: wprost do rozsyłki, klient: RPC do serwera).
func send(text: String) -> void:
	var t := sanitize(text)
	if t == "" or not NoiseMgr.has_network():
		return
	if multiplayer.is_server():
		_server_accept(multiplayer.get_unique_id(), t)
	else:
		_to_server.rpc_id(1, t)

@rpc("any_peer", "call_remote", "reliable")
func _to_server(text: String) -> void:
	if multiplayer.is_server():
		_server_accept(multiplayer.get_remote_sender_id(), text)

func _server_accept(id: int, raw: String) -> void:
	var t := sanitize(raw)                         # tekst od klienta sprawdzamy jeszcze raz po stronie serwera
	if t == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -100000)) < MIN_GAP_MS:
		return
	_last_ms[id] = now
	_broadcast.rpc(_who(id), t)

@rpc("authority", "call_local", "reliable")
func _broadcast(who: String, text: String) -> void:
	line_added.emit(who.substr(0, 12), sanitize(text))

func _who(id: int) -> String:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and int(p.player_id) == id:
			return "P%d" % int(p.display_id)
	return "P?"
