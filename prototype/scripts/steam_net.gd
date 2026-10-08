extends Node
## Steam (opcjonalnie): lobby + transport przez GodotSteam (SteamMultiplayerPeer).
##
## Gra działa bez tego — jeśli wtyczki GodotSteam nie ma (albo Steam nie jest uruchomiony),
## przyciski Steam w lobby są wyszarzone, a ENet (host / IP) działa jak dotąd. Cała logika
## sieciowa gry stoi na MultiplayerPeer, więc podmieniamy tylko peera (main.gd).
##
## Do rozwoju i testów używamy App ID 480 („Spacewar", publiczny identyfikator testowy Valve):
## lobby, zaproszenia i relay działają bez opłat; testerzy muszą mieć Steama i być znajomymi
## hosta. Pod wydanie: własny App ID (Steam Direct) — zmienia się tylko APP_ID i steam_appid.txt.
##
## GodotSteam bywa różnie wersjonowany, więc nie linkujemy go statycznie: singleton „Steam" i
## klasa „SteamMultiplayerPeer" są wołane dynamicznie, a argumenty metod dobierane po nazwach.
## Obsługujemy dwa warianty peera: ze wbudowanym lobby (create_lobby / connect_lobby) oraz
## surowy P2P (create_host / create_client + lobby przez Steam.createLobby / joinLobby).

signal hosting(peer: MultiplayerPeer)      ## peer gotowy do podpięcia pod multiplayer (host)
signal joining(peer: MultiplayerPeer)      ## peer gotowy do podpięcia pod multiplayer (klient)
signal lobby_ready(id: int)                ## lobby istnieje — można zapraszać
signal invite_join(id: int)                ## znajomy zaprosił / „Dołącz do gry" z listy znajomych
signal status(text: String)
signal failed(text: String)

const APP_ID := 480
const MAX_MEMBERS := 4
const LOBBY_FRIENDS_ONLY := 1              ## ELobbyType::k_ELobbyTypeFriendsOnly
const LOBBY_TIMEOUT := 10.0
const JOIN_TIMEOUT := 15.0
const GAME_TAG := "deadair87"

var lobby_id := 0
var _steam: Object = null
var _inited := false
var _embedded := false
var _peer: MultiplayerPeer = null
var _mode := ""                            ## "host" | "join" | ""
var _wait := 0.0                           ## s do uznania, że lobby się nie utworzy
var _join_wait := 0.0                      ## s do uznania, że dołączenie się nie powiodło

static func is_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")

func _ready() -> void:
	if not is_available():
		set_process(false)
		return
	# Inicjalizacja od razu: dopiero wtedy działają zaproszenia („Dołącz do gry" z listy znajomych).
	if init_steam():
		_check_launch_args.call_deferred()

func init_steam() -> bool:
	if _inited:
		return true
	if not is_available():
		return false
	_steam = Engine.get_singleton("Steam")
	var ok := false
	if _steam.has_method("steamInitEx"):
		var r: Variant = _call_named("steamInitEx", {"app_id": APP_ID, "embed_callbacks": true, "retrieve_stats": false})
		ok = r is Dictionary and int(r.get("status", -1)) == 0           # k_ESteamAPIInitResult_OK
		_embedded = _has_arg("steamInitEx", "embed_callbacks")
	elif _steam.has_method("steamInit"):
		var r2: Variant = _call_named("steamInit", {"app_id": APP_ID, "retrieve_stats": false, "embed_callbacks": true})
		ok = r2 is Dictionary and int(r2.get("status", -1)) == 1         # starsze API: 1 = OK
		_embedded = _has_arg("steamInit", "embed_callbacks")
	if not ok:
		return false
	_inited = true
	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("join_requested", _on_join_requested)
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.call("initRelayNetworkAccess")   # relay Steam (P2P bez otwierania portów)
	print("[STEAM] initialized (app %d), user %s" % [APP_ID, str(_steam.call("getPersonaName")) if _steam.has_method("getPersonaName") else "?"])
	return true

func _process(delta: float) -> void:
	if not _inited:
		return
	if not _embedded and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")
	# peer z wbudowanym lobby: id lobby bywa dostępne dopiero po chwili
	if _mode == "host" and lobby_id == 0 and _peer != null:
		var id := _peer_lobby_id()
		if id != 0:
			_on_lobby_ready(id)
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and _mode == "host" and lobby_id == 0:
			_mode = ""
			_drop_peer()
			failed.emit("Steam lobby was not created in time — is Steam running?")
	if _join_wait > 0.0 and _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_join_wait = 0.0                       # peer połączony, nawet jeśli sygnał lobby_joined nie przyszedł
	if _join_wait > 0.0:
		_join_wait -= delta
		if _join_wait <= 0.0 and _mode == "join":
			_mode = ""
			_drop_peer()
			failed.emit("Steam: joining the lobby timed out — check the lobby ID and that you are friends with the host.")

# ---------------------------------------------------------------- host / join

func host() -> void:
	if not _ensure_ready():
		return
	_peer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if _peer == null:
		failed.emit("Steam: SteamMultiplayerPeer could not be created (wrong GodotSteam version?).")
		return
	_mode = "host"
	lobby_id = 0
	_wait = LOBBY_TIMEOUT
	_connect_peer_signals()
	status.emit("Creating Steam lobby…")
	if _peer.has_method("create_lobby"):
		_peer.call("create_lobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)
		hosting.emit(_peer)
	elif _steam.has_method("createLobby"):
		_steam.call("createLobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)
	else:
		failed.emit("Steam: unsupported GodotSteam version (no lobby API).")

func join(text: String) -> void:
	var id := text.strip_edges().to_int()
	if id <= 0:
		failed.emit("Enter the Steam lobby ID (the host sees it after hosting).")
		return
	join_lobby(id)

func join_lobby(id: int) -> void:
	if not _ensure_ready():
		return
	_peer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if _peer == null:
		failed.emit("Steam: SteamMultiplayerPeer could not be created (wrong GodotSteam version?).")
		return
	_mode = "join"
	_join_wait = JOIN_TIMEOUT
	_connect_peer_signals()
	status.emit("Joining Steam lobby %d…" % id)
	if _peer.has_method("connect_lobby"):
		_peer.call("connect_lobby", id)
		joining.emit(_peer)
	elif _steam.has_method("joinLobby"):
		_steam.call("joinLobby", id)           # dalej w _on_lobby_joined
	else:
		failed.emit("Steam: unsupported GodotSteam version (no lobby API).")

## Okno zaproszeń Steam (overlay) dla bieżącego lobby. Zwraca komunikat dla gracza (F2 wcześniej nic nie mówiło, gdy overlay był niedostępny).
## Overlay działa tylko wtedy, gdy Steam „wstrzyknie" się do procesu gry — czyli gra uruchomiona ze Steama (np. dodana jako „gra spoza Steam"); gra odpalona
## prosto z pliku .exe zwykle go nie ma. Wtedy ID lobby jest w schowku i trzeba je wysłać znajomym (wklejają je i dają STEAM JOIN).
func invite() -> String:
	if not _inited or _steam == null:
		return "Steam is not running — start Steam before the game."
	if lobby_id == 0:
		return "No Steam lobby — F2 works after STEAM HOST (IP games have no Steam invites)."
	DisplayServer.clipboard_set(str(lobby_id))
	var overlay_ok := true
	if _steam.has_method("isOverlayEnabled"):
		overlay_ok = bool(_steam.call("isOverlayEnabled"))
	if not overlay_ok or not _steam.has_method("activateGameOverlayInviteDialog"):
		return "Steam overlay unavailable (start the game from Steam / add it as a non-Steam game). Lobby ID %d copied — send it to friends: paste + STEAM JOIN." % lobby_id
	_steam.call("activateGameOverlayInviteDialog", lobby_id)
	return "Invite dialog opened. Lobby ID %d copied (backup: friends paste it + STEAM JOIN)." % lobby_id

func leave() -> void:
	if _inited and lobby_id != 0 and _steam.has_method("leaveLobby"):
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0
	_mode = ""
	_wait = 0.0
	_join_wait = 0.0
	_drop_peer()

# ---------------------------------------------------------------- callbacki Steam

func _on_lobby_created(result: int, id: int) -> void:
	if _mode != "host":
		return
	if result != 1:                            # k_EResultOK
		_mode = ""
		_drop_peer()
		failed.emit("Steam lobby failed (code %d)." % result)
		return
	_on_lobby_ready(id)
	# surowy P2P: transport zaczynamy dopiero, gdy lobby istnieje
	if _peer != null and _peer.has_method("create_host") and not _peer.has_method("create_lobby"):
		_peer.call("create_host", 0)
		hosting.emit(_peer)

func _on_lobby_ready(id: int) -> void:
	lobby_id = id
	_wait = 0.0
	if _steam.has_method("setLobbyData"):
		_steam.call("setLobbyData", id, "game", GAME_TAG)
	DisplayServer.clipboard_set(str(id))
	lobby_ready.emit(id)
	status.emit("Steam lobby %d (copied). Invite friends with the Steam overlay or send them the ID." % id)

func _on_lobby_joined(id: int, _permissions := 0, _locked := false, response := 1) -> void:
	if _mode != "join":
		return
	if int(response) != 1:                     # k_EChatRoomEnterResponseSuccess
		_mode = ""
		_join_wait = 0.0
		_drop_peer()
		failed.emit("Could not join the Steam lobby (code %d)." % int(response))
		return
	lobby_id = id
	_join_wait = 0.0
	# peer z wbudowanym lobby podłączył się sam (connect_lobby); surowy P2P łączymy z właścicielem
	if _peer != null and _peer.has_method("create_client") and not _peer.has_method("connect_lobby"):
		var lobby_owner := int(_steam.call("getLobbyOwner", id))
		_peer.call("create_client", lobby_owner, 0)
		joining.emit(_peer)

## Peer z wbudowanym lobby sam zgłasza utworzenie/dołączenie — nie polegamy tylko na sygnałach
## singletona Steam (te mogą nie przyjść, gdy lobby zakłada peer). Liczba argumentów sygnału
## różni się między wersjami, więc handlery przyjmują opcjonalne argumenty.
func _on_peer_lobby_created(a: Variant = 0, b: Variant = 0) -> void:
	if _mode != "host" or lobby_id != 0:
		return
	var id := int(b) if int(b) != 0 else int(a)
	if id <= 1:                                # 1 = samo „OK" bez ID
		id = _peer_lobby_id()
	if id > 1:
		_on_lobby_ready(id)

func _on_peer_lobby_joined(_a: Variant = 0, _b: Variant = 0) -> void:
	if _mode == "join":
		_join_wait = 0.0

func _on_join_requested(id: int, _friend := 0) -> void:
	invite_join.emit(id)

# ---------------------------------------------------------------- start przez zaproszenie

## Gra uruchomiona z „Dołącz do gry": Steam dokleja `+connect_lobby <id>` do wiersza poleceń.
func _check_launch_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			invite_join.emit(args[i + 1].to_int())
			return

# ---------------------------------------------------------------- pomocnicze

func _peer_lobby_id() -> int:
	if _peer == null:
		return 0
	if _peer.has_method("get_lobby_id"):
		return int(_peer.call("get_lobby_id"))
	var v: Variant = _peer.get("lobby_id")
	return int(v) if v != null else 0

func _connect_peer_signals() -> void:
	if _peer == null:
		return
	if _peer.has_signal("lobby_created"):
		_peer.connect("lobby_created", _on_peer_lobby_created)
	if _peer.has_signal("lobby_joined"):
		_peer.connect("lobby_joined", _on_peer_lobby_joined)

func _drop_peer() -> void:
	if _peer != null and _peer.has_method("close"):
		_peer.call("close")
	_peer = null

func _ensure_ready() -> bool:
	if not is_available():
		failed.emit("Steam is not available — install the GodotSteam addon (see README) and start Steam.")
		return false
	if not init_steam():
		failed.emit("Steam could not be initialized — is the Steam client running and logged in?")
		return false
	return true

func _connect_signal(sig: String, cb: Callable) -> void:
	if _steam.has_signal(sig) and not _steam.is_connected(sig, cb):
		_steam.connect(sig, cb)

func _method_info(method: String) -> Dictionary:
	for m in _steam.get_method_list():
		if m["name"] == method:
			return m
	return {}

func _has_arg(method: String, arg: String) -> bool:
	for a in _method_info(method).get("args", []):
		if a["name"] == arg:
			return true
	return false

## Woła metodę GodotSteam, dobierając argumenty po nazwach (sygnatury różnią się między wersjami);
## brakujące argumenty dostają domyślne wartości metody.
func _call_named(method: String, values: Dictionary) -> Variant:
	var info := _method_info(method)
	if info.is_empty():
		return _steam.call(method)
	var defs: Array = info.get("default_args", [])
	var params: Array = info.get("args", [])
	var first_default := params.size() - defs.size()
	var args: Array = []
	for i in params.size():
		var nm: String = params[i]["name"]
		if values.has(nm):
			args.append(values[nm])
		elif i >= first_default:
			args.append(defs[i - first_default])
		else:
			args.append(null)
	return _steam.callv(method, args)
