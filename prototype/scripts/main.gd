extends Node2D
## Lobby + host/join + spawn graczy (MultiplayerSpawner).

const PORT := 8910
## Nadpisywany flagą --port=N (np. testy headless przy otwartym oknie gry).
var port := PORT
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player.tscn")
## Bot NIE jest preload — używamy load() w runtime. Bot scene dziedziczy po
## player.gd, a preload tutaj tworzyłby cykl main->bot->player podczas parsowania.
const BOT_SCENE_PATH := "res://scenes/bot_companion.tscn"
## Wipe (wszyscy down) = nieudana ekstrakcja: restart misji po tylu sekundach (GDD §4).
const WIPE_DELAY := 3.0

const Sprites := preload("res://scripts/sprites.gd")
const Combat := preload("res://scripts/combat.gd")
const Codex := preload("res://scripts/codex.gd")
const Hints := preload("res://scripts/hints.gd")
const Look := preload("res://scripts/look.gd")
const Lights := preload("res://scripts/lights.gd")
const RunLog := preload("res://scripts/run_log.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const MISSION_SCRIPT := preload("res://scripts/mission.gd")
const WEAPON_TEST := preload("res://scripts/weapon_test.gd")
const WORKSHOP_TEST := preload("res://scripts/workshop_test.gd")
const CABINET_TEST := preload("res://scripts/cabinet_test.gd")
const STALKER_TEST := preload("res://scripts/stalker_test.gd")
const BOT_TEST := preload("res://scripts/bot_test.gd")
const NOBOT_TEST := preload("res://scripts/nobot_test.gd")
const FUN_TEST := preload("res://scripts/fun_test.gd")
const BATTERY_TEST := preload("res://scripts/battery_test.gd")
const RESULT_TEST := preload("res://scripts/result_test.gd")
const RANGE_TEST := preload("res://scripts/range3d/range_test.gd")
const FP_RANGE := preload("res://scripts/range3d/fp_mode.gd")
const ENEMY_TEST := preload("res://scripts/enemy_test.gd")
const DREAD := preload("res://scripts/dread.gd")
const STEAM_NET := preload("res://scripts/steam_net.gd")
const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const BRIGHTNESS_SCREEN := preload("res://scripts/brightness_screen.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Weather := preload("res://scripts/weather.gd")
const Weapons := preload("res://scripts/weapons.gd")
const HORROR_FX := preload("res://scripts/horror_fx.gd")
const MAIN_MENU := preload("res://scripts/main_menu.gd")
const OPERATORS_SCREEN := preload("res://scripts/operators_screen.gd")
const CHAT := preload("res://scripts/chat.gd")
const COLORBLIND_FX := preload("res://scripts/colorblind_fx.gd")
const WEATHER_FX := preload("res://scripts/weather_fx.gd")
const VIEW3D := preload("res://scripts/view3d.gd")
const NavGraph := preload("res://scripts/nav.gd")
const ENEMY := preload("res://scripts/enemy.gd")
const Throwables := preload("res://scripts/throwables.gd")

## >0 w trakcie odliczania do restartu po wipe; widoczne na każdym peerze (HUD).
var wipe_left := 0.0
## Pętla misji: cel → ekstrakcja → wynik (mission.gd). Węzeł o stałej nazwie,
## tworzony na każdym peerze, więc RPC trafia w tę samą ścieżkę.
var mission: Node2D
## Steam (opcjonalnie, steam_net.gd): lobby i transport przez GodotSteam.
var steam: Node

@onready var level: Node2D = $Level
@onready var _players: Node2D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _lobby: Control = $UI/Lobby   # lobby.gd

## Czy w argumentach dev jest flaga `p` albo `p=wartość`.
func _has_arg_prefix(p: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == p or a.begins_with(p + "="):
			return true
	return false

func _ready() -> void:
	# Własna funkcja spawnu: dane startowe (pozycja, display_id) dostaje KAŻDY
	# peer, także dołączający później. Synchronizator postaci klienta należy do
	# klienta, więc serwer nie może już przekazać stanu początkowego przez niego.
	_spawner.spawn_function = _spawn_actor
	mission = MISSION_SCRIPT.new()
	mission.name = "Mission"
	add_child(mission)
	var dread := DREAD.new()
	dread.name = "Dread"
	add_child(dread)
	var pause_menu := PAUSE_MENU.new()
	pause_menu.name = "PauseMenu"
	$UI.add_child(pause_menu)             # nad HUD i lobby
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _on_peer_auth
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(_on_peer_auth_failed)
	Audio.quitting.connect(_log_quit.bind("exit"))
	_lobby.host_requested.connect(host_game)
	steam = STEAM_NET.new()
	steam.name = "SteamNet"
	add_child(steam)
	_lobby.set_steam_available(STEAM_NET.is_available())
	_lobby.steam_host_requested.connect(steam.host)
	_lobby.steam_join_requested.connect(steam.join)
	steam.hosting.connect(_on_steam_hosting)
	steam.joining.connect(_on_steam_joining)
	steam.invite_join.connect(func(id: int) -> void: steam.join_lobby(id))
	steam.status.connect(func(t: String) -> void: _lobby.set_status(t))
	steam.failed.connect(func(t: String) -> void: _lobby.set_status(t, true))
	_lobby.join_requested.connect(join_game)
	# Ambient startuje dopiero przy sesji — w lobby grałby na pustce.
	_lobby.host_requested.connect(func() -> void: Audio.play("ui_confirm", Audio.BUS_UI, -8.0))
	_lobby.join_requested.connect(func(_ip: String) -> void: Audio.play("ui_click", Audio.BUS_UI, -8.0))
	_handle_cmdline()
	var chat := CHAT.new()                                    # czat drużyny: ta sama ścieżka na każdym peerze (RPC)
	chat.name = "Chat"
	add_child(chat)
	pause_menu.leave_requested.connect(leave_session)
	_setup_main_menu(pause_menu)
	if _drop_note != "":
		_show_drop_note()
	if "--leavetest" in OS.get_cmdline_user_args():
		_leave_test.call_deferred()
	if DisplayServer.get_name() != "headless":
		var cbfx := COLORBLIND_FX.new()                       # filtr dla osób z zaburzeniami widzenia barw (ustawienie „Color vision”), nad całym obrazem
		cbfx.name = "ColorblindFx"
		add_child(cbfx)
	# efekty pogody (deszcz, burza, tint ciemności): w każdej grafice, tuż przed obrazem horroru (jego winieta kładzie się na wierzch); `--nofx` wyłącza
	var wfx: CanvasLayer = null
	if DisplayServer.get_name() != "headless" and not ("--nofx" in OS.get_cmdline_user_args()):
		wfx = WEATHER_FX.new()
		wfx.name = "WeatherFx"
		add_child(wfx)
		move_child(wfx, $UI.get_index())
	# widok 3D (ustawienie „3D view” / `--view3d`): ten sam świat 2D renderowany w 3D, przełączany w trakcie gry
	Settings.changed.connect(_apply_view3d)
	Settings.changed.connect(_on_companion_setting)
	_apply_view3d.call_deferred()
	# obraz horroru (winieta, aberracja, ostrzeżenie o zdrowiu) — tylko w grafice HD; `--nofx` wyłącza
	if Sprites.newitem and DisplayServer.get_name() != "headless" and not ("--nofx" in OS.get_cmdline_user_args()):
		var hfx := HORROR_FX.new()
		hfx.name = "HorrorFx"
		add_child(hfx)
		move_child(hfx, $UI.get_index())

## Włącza / wyłącza widok 3D (view3d.gd) zgodnie z ustawieniem; węzeł dostaje poziom i kontener graczy, zwalnia się z przywróceniem 2D.
func _apply_view3d() -> void:
	var want := Settings.view3d_active()
	var cur := get_node_or_null("View3D")
	if want and cur == null:
		var v: Node2D = VIEW3D.new()
		add_child(v)
		v.setup(level, _players)
	elif not want and cur != null:
		cur.release()

# ---------------------------------------------------------------- wipe (GDD §4)

func _physics_process(delta: float) -> void:
	_hub_input()
	if not NoiseMgr.has_network() or not multiplayer.is_server():
		# klient tylko odlicza lokalnie to, co ogłosił serwer
		wipe_left = maxf(0.0, wipe_left - delta)
		return
	if wipe_left > 0.0:
		wipe_left -= delta
		if wipe_left <= 0.0:
			wipe_left = 0.0
			if NightShift.active:
				mission.fail_shift()          # Nocny Dyżur: wipe kończy serię
			elif mission.has_checkpoint():
				_restart_from_checkpoint()    # wipe w walce z bossem: od początku walki, nie od startu mapy (FUN_PLAN.md P0.3)
			else:
				_restart_mission(false)
		return
	# po udanej ekstrakcji (albo końcu serii Nocnego Dyżuru) czeka raport po akcji — host zaczyna nową misję z niego (result_action)
	if mission.phase == MISSION_SCRIPT.Phase.SUCCESS or mission.phase == MISSION_SCRIPT.Phase.FAILED:
		return
	if mission.kind == "hub":
		_hub_server_tick(delta)
		return
	_track_solo_fall()
	if _all_down() and not _solo_may_bleed():
		print("[WIPE] all players down -> mission restart in %.0fs" % WIPE_DELAY)
		mission.log_end("wipe")
		_announce_wipe.rpc(WIPE_DELAY)

## Wipe = WSZYSCY (ludzie i boty) leżą jednocześnie.
func _all_down() -> bool:
	var any := false
	for c in _players.get_children():
		if c.is_queued_for_deletion():
			continue
		any = true
		if not c.dead:
			return false
	return any

## Upadek, gdy nikt nie podniesie (NOBOT_PLAN.md D1a): drużyna to jeden człowiek bez bota. Pierwszy upadek w próbie nie kończy jej
## wipe'em — biegnie wykrwawienie i powrót na start z 1 HP (player.gd, kara dystansem z GDD §4), łup zostaje. Drugi upadek w tej
## samej próbie = wipe jak zawsze. Z botem albo drugim człowiekiem wipe bez zmian (wszyscy leżą).
var _solo_falls := 0
var _solo_was_dead := false

func _lone_player() -> Node:
	var lone: Node = null
	for c in _players.get_children():
		if c.is_queued_for_deletion():
			continue
		if lone != null:
			return null
		lone = c
	return lone if lone != null and not lone.is_bot else null

func _track_solo_fall() -> void:
	var lone := _lone_player()
	var d: bool = lone != null and bool(lone.dead)
	if d and not _solo_was_dead:
		_solo_falls += 1
	_solo_was_dead = d

func _solo_may_bleed() -> bool:
	return _lone_player() != null and _solo_falls <= 1

@rpc("authority", "call_local", "reliable")
func _announce_wipe(seconds: float) -> void:
	wipe_left = seconds
	Audio.play("tape_stop", Audio.BUS_UI, -6.0)

## Restart misji (serwer): Uwaga, ładunki Q, wrogowie, gniazda i gracze wracają
## na start. new_run=false to kolejna próba po wipe (licznik prób +1), true to
## nowa misja po udanej ekstrakcji. Łup misji przepadłby tutaj — postęp
## fabularny nie (GDD §4).
func _restart_mission(new_run: bool, map_id := "", carry := false) -> void:
	print("[MISSION] restart (%s)%s" % ["nowa misja" if new_run else "wipe", (" -> " + map_id) if map_id != "" else ""])
	_solo_falls = 0
	_solo_was_dead = false
	if map_id != "" and map_id != level.map_id:
		_set_map(map_id)
	NoiseMgr.reset_mission()
	Arsenal.begin_mission(new_run)       # ekwipunek zużywalny: zapas przechodzi między misjami, wipe wraca do stanu z początku misji
	if not carry:
		Arsenal.reset_mission()          # ekwipunek i amunicja wracają na start; z carry (kryjówka) zostają
	Director.reset()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("reset_enemy"):
			e.reset_enemy()
	for g in get_tree().get_nodes_in_group("generators"):
		g.reset_generator()
	for sb in get_tree().get_nodes_in_group("strongboxes"):
		sb.reset_strongbox()                 # sejfy znów zamknięte (łup próby przepada razem z resztą)
	for car in get_tree().get_nodes_in_group("handcar"):
		car.reset_handcar()
	level.reset_collapse()
	for c in _players.get_children():
		if not carry and not c.is_bot:
			level.register_weapon_kit(int(c.player_id))
		c.deliver_spawn(Vector2.INF)     # punkt kontrolny bossa (jeśli był) przestaje obowiązywać
		c.request_full_reset(carry)
	level.clear_pickups()
	mission.on_restart(new_run)
	Scrap.reset_loot()                   # wipe / nowa misja: łup z poprzedniej próby przepada (po sukcesie już trafił do banku)
	_departing = false
	hub_ready.clear()
	hub_mine = false
	hub_ready_n = 0
	hub_countdown = -1.0
	_update_weather(new_run, carry)
	if level.objective == "hub":
		NoiseMgr.calm()                  # w kryjówce jest cicho

## Wipe w fazie BOSS misji z gniazdami (FUN_PLAN.md P0.3): jak zwykły wipe (Uwaga, ekwipunek z początku misji, wrogowie wracają),
## ale gniazda zostają zniszczone, drużyna staje w punkcie kontrolnym, a boss budzi się po chwili od nowa. Łup wraca do stanu
## z przebudzenia bossa (Scrap.restore_checkpoint_loot) — przepada tylko to, co zebrano w samej walce.
func _restart_from_checkpoint() -> void:
	print("[MISSION] restart od punktu kontrolnego (boss)")
	_solo_falls = 0
	_solo_was_dead = false
	NoiseMgr.reset_mission()
	Arsenal.begin_mission(false)
	Arsenal.reset_mission()
	Director.reset()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_in_group("nests") and e.has_method("reset_enemy"):
			e.reset_enemy()
	for c in _players.get_children():
		if not c.is_bot:
			level.register_weapon_kit(int(c.player_id))
		c.deliver_spawn(mission.checkpoint_pos(c))
		c.request_full_reset(false)
	level.clear_pickups()
	Scrap.restore_checkpoint_loot()
	mission.on_checkpoint()
	NoiseMgr.objective_bonus()           # jak przy pierwszym przebudzeniu bossa
	mission.wake_boss_after_checkpoint()

# ---------------------------------------------------------------- mapy / kampania

# ---------------------------------------------------------------- gotowość w kryjówce

const HUB_COUNTDOWN := 3.0           ## tyle sekund po zgłoszeniu gotowości przez wszystkich ludzi do wyjścia na misję

var hub_ready := {}                  ## serwer: id peera (jako tekst) -> gotowy
var hub_mine := false                ## ten peer: czy jestem gotowy (HUD)
var hub_cancel_flash := 0.0           ## 1 w chwili anulowania odliczania, zanika w pół sekundy (HUD i światła strefy startu)
var _hub_cd_prev := -1.0
var hub_in_zone := false             ## ten peer: czy stoję w strefie startu (HUD: wyjście ze strefy anuluje)
var hub_ready_n := 0                 ## ilu ludzi gotowych / ilu w ogóle (replikowane serwerem do HUD)
var hub_total := 0
var hub_countdown := -1.0            ## < 0: nie odliczamy
var _hub_sync_t := 0.0

## Każdy człowiek w kryjówce przełącza gotowość [Enter]em. Gdy wszyscy ludzie są gotowi, po krótkim odliczaniu
## drużyna rusza na misję; odznaczenie przez kogokolwiek przerywa odliczanie. Boty się nie liczą.
func _hub_input() -> void:
	if mission == null or mission.kind != "hub":
		_hub_cd_prev = -1.0
		return
	_hub_feedback(get_physics_process_delta_time())
	if hub_countdown > 0.0 and NoiseMgr.has_network() and not multiplayer.is_server():
		hub_countdown = maxf(0.0, hub_countdown - get_physics_process_delta_time())     # klient odlicza sam, serwer w _hub_server_tick
	var me: Node2D = _players.get_node_or_null(str(NoiseMgr.local_id())) as Node2D
	hub_in_zone = me != null and level.launch_zone.has_point(me.global_position)
	if not Input.is_action_just_pressed("restart"):
		return
	if me != null and bool(me.get("in_range")):
		return                            # strzelnica FPP: Enter wybiera broń w szafie (fp_mode.gd), nie zgłasza gotowości do misji
	if hub_in_zone:
		return                            # w strefie gotowość trzyma pozycja: żeby ją cofnąć, trzeba z niej wyjść
	hub_mine = not hub_mine
	Audio.play("ui_click", Audio.BUS_UI, -8.0)
	if not NoiseMgr.has_network() or multiplayer.is_server():
		_hub_set_ready(NoiseMgr.local_id(), hub_mine)
	else:
		_hub_ready_rpc.rpc_id(1, hub_mine)

## Dźwięk i błysk odliczania (lokalnie u każdego peera, licznik przychodzi z serwera): tyk co sekundę o rosnącym tonie, potwierdzenie na zerze, odmowa i czerwony błysk przy anulowaniu.
func _hub_feedback(delta: float) -> void:
	hub_cancel_flash = maxf(0.0, hub_cancel_flash - delta * 2.0)
	var cd := hub_countdown
	if cd > 0.0:
		var secs := ceili(cd)
		if _hub_cd_prev < 0.0 or secs != ceili(_hub_cd_prev):
			Audio.play("ui_click", Audio.BUS_UI, -4.0, 0.85 + 0.22 * float(ceili(HUB_COUNTDOWN) - secs))
	elif cd == 0.0 and _hub_cd_prev > 0.0:
		Audio.play("ui_confirm", Audio.BUS_UI, -3.0)
	elif cd < 0.0 and _hub_cd_prev > 0.0 and not _departing:
		hub_cancel_flash = 1.0
		Audio.play("ui_deny", Audio.BUS_UI, -5.0)
	_hub_cd_prev = cd

@rpc("any_peer", "call_remote", "reliable")
func _hub_ready_rpc(on: bool) -> void:
	if multiplayer.is_server():
		_hub_set_ready(multiplayer.get_remote_sender_id(), on)

func _hub_set_ready(peer_id: int, on: bool) -> void:
	var key := str(peer_id)
	if on:
		hub_ready[key] = true
	else:
		hub_ready.erase(key)
	_hub_sync_t = 0.0

## Ludzie stojący w strefie startu kryjówki (level.launch_zone); serwer czyta pozycje graczy tak jak przy ich innych sprawdzeniach zasięgu.
func _hub_zone_ids() -> Array:
	var out := []
	if level.launch_zone.size == Vector2.ZERO:
		return out
	for c in _players.get_children():
		if c.is_queued_for_deletion() or c.is_bot or bool(c.get("dead")):
			continue
		if level.launch_zone.has_point((c as Node2D).global_position):
			out.append(String(c.name))
	return out

func _hub_humans() -> Array:
	var out := []
	for c in _players.get_children():
		if not c.is_queued_for_deletion() and not c.is_bot:
			out.append(String(c.name))
	return out

func _hub_server_tick(delta: float) -> void:
	var humans := _hub_humans()
	for k in hub_ready.keys():
		if not humans.has(k):
			hub_ready.erase(k)                # ktoś wyszedł
	var ready_ids: Array = hub_ready.keys()
	for k in _hub_zone_ids():
		if not ready_ids.has(k):
			ready_ids.append(k)               # gotowy jest ten, kto stoi w strefie startu albo zgłosił się [Enter]em
	var n := 0
	for k in humans:
		if ready_ids.has(k):
			n += 1
	hub_mine = ready_ids.has(str(NoiseMgr.local_id()))
	var all := not humans.is_empty() and n == humans.size()
	var was := hub_countdown
	if not all:
		hub_countdown = -1.0
	elif hub_countdown < 0.0:
		hub_countdown = HUB_COUNTDOWN
	elif hub_countdown > 0.0:
		hub_countdown = maxf(0.0, hub_countdown - delta)
	if all and hub_countdown <= 0.0:
		if not _departing:
			_departing = true
			_depart_hub.call_deferred()          # poza krokiem fizyki: przebudowa mapy w ticku fizyki psuje rysowanie świata (ciemne kwadraty zamiast postaci)
		return
	if n != hub_ready_n or humans.size() != hub_total or (was < 0.0) != (hub_countdown < 0.0):
		_hub_sync_t = 0.0
	hub_ready_n = n
	hub_total = humans.size()
	_hub_sync_t -= delta
	if _hub_sync_t <= 0.0:
		_hub_sync_t = 1.0
		if NoiseMgr.has_network():
			_hub_state.rpc(ready_ids, hub_total, hub_countdown)

@rpc("authority", "call_remote", "reliable")
func _hub_state(ready_ids: Array, total: int, countdown: float) -> void:
	hub_ready_n = ready_ids.size()
	hub_total = total
	hub_countdown = countdown
	hub_mine = ready_ids.has(str(multiplayer.get_unique_id()))

## Pogoda (weather.gd, serwer; klienci dostają ją z mission._sync): w kryjówce losujemy prognozę na następną misję i pogody nie ma,
## po wyjściu z kryjówki (carry) prognoza staje się pogodą misji, wipe (new_run == false) zostawia ją bez zmian, a Nocny Dyżur i misja
## uruchomiona poza kryjówką jej nie mają.
func _update_weather(new_run: bool, carry: bool) -> void:
	if level.objective == "hub":
		Weather.current = ""
		if new_run:
			Weather.forecast = Weather.roll()
	elif new_run:
		Weather.current = Weather.forecast if (carry and not NightShift.active) else ""
		Weather.seed = randi()           # ziarno harmonogramu błyskawic tej misji (replikowane z pogodą)
		if not carry:
			Weather.forecast = "clear"

## Wyjście z kryjówki (wszyscy ludzie gotowi): wyjście do kolejnej misji kampanii z zachowanym ekwipunkiem.
func _depart_hub() -> void:
	var target := after_hub if after_hub != "" else campaign_start_map()
	after_hub = ""
	_restart_mission(true, target, true)

## Postęp kampanii drużyny (Scrap.cleared, zapis hosta; PROGRESSION_PLAN.md P1.1): indeks najdalszej ukończonej misji Strefy I, −1 — żadnej.
func _campaign_furthest() -> int:
	var far := -1
	for i in level.CAMPAIGN.size():
		if Scrap.cleared.has(String(level.CAMPAIGN[i])):
			far = i
	return far

## Misje do wyboru przy tablicy odpraw: wszystkie do najdalszej ukończonej i jedna następna (kolejność nauki zostaje: 1.1 cisza, 1.2 Q…).
func campaign_unlocked() -> Array:
	return level.CAMPAIGN.slice(0, mini(_campaign_furthest() + 2, level.CAMPAIGN.size()))

## Skąd startuje kampania: misja po najdalszej ukończonej; po bossie — znowu od 1.1 (wybór innej przy tablicy odpraw).
func campaign_start_map() -> String:
	var nxt := _campaign_furthest() + 1
	return String(level.CAMPAIGN[nxt if nxt < level.CAMPAIGN.size() else 0])

## Gracz przy tablicy odpraw w kryjówce przełącza cel wyjścia na kolejną odblokowaną misję (serwer rozstrzyga i rozsyła w mission._sync).
func request_brief_cycle() -> void:
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_brief_cycle_server(NoiseMgr.local_id())
	else:
		_brief_cycle_rpc.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _brief_cycle_rpc() -> void:
	if NoiseMgr.is_server():
		_brief_cycle_server(multiplayer.get_remote_sender_id())

## Serwer: żywy człowiek stoi przy tablicy w kryjówce. Tablica stoi w strefie startu, więc zwykle trwa już odliczanie — zmiana celu
## odnawia je do pełnego HUB_COUNTDOWN, żeby drużyna zdążyła przeczytać nową odprawę. Zwraca, czy cel się zmienił.
func _brief_cycle_server(peer_id: int) -> bool:
	if NightShift.active or _departing or Scrap.station_reason(peer_id, "board") != "ok":
		return false
	var opts := campaign_unlocked()
	if opts.size() < 2:
		return false
	after_hub = String(opts[(opts.find(after_hub) + 1) % opts.size()])
	if hub_countdown > 0.0:
		hub_countdown = HUB_COUNTDOWN
		_hub_sync_t = 0.0
	mission._broadcast()
	return true

## Akcja z raportu po akcji (result_screen.gd, po sekwencji albo jej pominięciu): host — "continue" kryjówka / dalej w Nocnym Dyżurze,
## "next" od razu następna misja kampanii; klient — gotowość (informacja dla hosta, RESULTS_PLAN.md §5).
func result_action(kind: String) -> void:
	if mission == null or (mission.phase != MISSION_SCRIPT.Phase.SUCCESS and mission.phase != MISSION_SCRIPT.Phase.FAILED):
		return
	if NoiseMgr.has_network() and not multiplayer.is_server():
		mission.send_ready()
		return
	if kind == "next" and not NightShift.active and mission.phase == MISSION_SCRIPT.Phase.SUCCESS:
		_continue_without_hub.call_deferred()
	else:
		_continue_after_result.call_deferred()       # jak wyjście z kryjówki: zmiana mapy poza krokiem fizyki

## [Enter] na ekranie wyniku (host): kolejna misja kampanii (po ostatniej — od początku) albo kolejna misja / nowa seria
## Nocnego Dyżuru. Po porażce w kampanii (nie występuje: wipe = powtórka) zostałaby ta sama mapa.
func _continue_after_result() -> void:
	var next_map := ""
	if NightShift.active:
		mission.shift_advance()
		next_map = _shift_map()
	elif mission.phase == MISSION_SCRIPT.Phase.SUCCESS:
		after_hub = _next_campaign_map()          # kampania: najpierw kryjówka, potem kolejna misja Strefy I
		_restart_mission(true, "z1_hub", true)
		return
	_restart_mission(true, next_map)

## [Interakcja] na karcie wyniku kampanii (host, FUN_PLAN.md P0.4): od razu następna misja z zachowanym ekwipunkiem, bez kryjówki —
## jak wyjście z niej (carry), z nową prognozą pogody. Kto chce do warsztatu, wybiera [Enter].
func _continue_without_hub() -> void:
	if NightShift.active or mission.phase != MISSION_SCRIPT.Phase.SUCCESS:
		return
	Weather.forecast = Weather.roll()
	after_hub = ""
	mission.start_via = "direct"                  # dziennik: mission_start.via (tools/fun_report.py)
	_restart_mission(true, _next_campaign_map(), true)

## Serwer: przełącza poziom na `id` u wszystkich peerów (przebudowa mapy, nowy punkt startu, nowy cel).
func _set_map(id: String) -> void:
	if not level.MAPS.has(id):
		push_warning("Unknown map: %s" % id)
		return
	if NoiseMgr.has_network():
		_load_map_rpc.rpc(id)
	else:
		_load_map_rpc(id)

@rpc("authority", "call_local", "reliable")
func _load_map_rpc(id: String) -> void:
	level.load_map(id)
	if NoiseMgr.is_server():
		Scrap._action_at.clear()
		Scrap._serviced.clear()          # nowy pobyt w kryjówce, także po nieudanej misji
	mission.rebind()
	if level.objective == "hub" and NoiseMgr.is_server():
		Weather.forecast = Weather.roll()            # start w kryjówce (lobby / nowa kampania): prognoza od razu; klienci dostają ją z mission._sync
		Weather.current = ""
	print("[MISSION] map: %s (%s)" % [level.map_id, level.title])

func _print_squad() -> void:
	var rows: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_queued_for_deletion():
			rows.append([int(p.display_id), String(p.label())])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	print("[SQUAD] " + " | ".join(rows.map(func(r: Array) -> String: return "P%d=%s" % [r[0], r[1]])))

## Test sieci raportu po akcji (--resultnet=N, tools/test_net_session.sh): host — sukces misji; klient — „gotowy” z raportu.
## Po chwili (host 5,5 s, klient 3 s) obie strony wypisują, co widzą: gotowość, poziomy z misji, rozbicie złomu od serwera, otwarty raport.
func _result_net_step() -> void:
	if multiplayer.is_server():
		mission.elapsed = 200.0
		mission._success()
	else:
		result_action("continue")
	await get_tree().create_timer(5.5 if multiplayer.is_server() else 3.0).timeout      # host czeka, aż klient zgłosi gotowość
	var rs := get_tree().root.find_child("ResultScreen", true, false)
	print("[RESULT-NET] %s ready=%s levels=%d gain=%s report=%s" % ["host" if multiplayer.is_server() else "client", str(mission.result_ready.keys()),
		mission.result_levels.size(), str(mission.result_info.get("gain", "-")), str(rs != null and rs.visible)])

## Test sieci baterii 4,5 V (--batterynet=N, tools/test_net_session.sh, BATTERY_PLAN.md B1): klient po N s ma 20% baterii; host po N + 1 s
## kładzie baterię przy postaci klienta (rozstrzyga serwer po replikowanym `bat_pct`, dolicza właściciel przez RPC). Po chwili obie strony
## wypisują, co widzą: host — `bat_pct` klienta i czy bateria zniknęła; klient — własną baterię.
func _battery_net_step() -> void:
	var me: Node = _players.get_node_or_null(str(multiplayer.get_unique_id()))
	if not multiplayer.is_server():
		if me != null:
			me.battery = me.BATTERY_MAX * 0.2
		await get_tree().create_timer(4.0).timeout
		print("[BATTERY-NET] client battery=%d pct=%d" % [roundi(me.battery) if me != null else -1, int(me.bat_pct) if me != null else -1])
		return
	await get_tree().create_timer(1.0).timeout
	var cl: Node2D = null
	for c in _players.get_children():
		if not c.is_bot and int(c.player_id) != 1:
			cl = c
	if cl == null:
		print("[BATTERY-NET] host: brak klienta")
		return
	level.spawn_item("battery", 0, cl.global_position + Vector2(0, -14))
	var item_name := "Item%d" % int(level._pickup_serial)             # nazwa nadana przez spawn_item (bateria może zniknąć jeszcze w podskoku)
	await get_tree().create_timer(0.8).timeout                      # lądowanie po podskoku
	var it: Node2D = level.get_node_or_null(item_name)
	if it != null:
		it.global_position = cl.global_position + Vector2(0, -2)   # podskok mógł odbić ją od postaci
	await get_tree().create_timer(1.5).timeout
	var still: Node = level.get_node_or_null(item_name)
	print("[BATTERY-NET] host client_pct=%d taken=%s" % [int(cl.bat_pct), str(still == null or still.is_queued_for_deletion())])

func _next_campaign_map() -> String:
	var order: Array = level.CAMPAIGN
	return order[(order.find(level.map_id) + 1) % order.size()]

## Nocny Dyżur: każda misja serii na losowej mapie z kampanii.
func _shift_map() -> String:
	var order: Array = level.SHIFT_POOL
	return order[randi() % order.size()]

func _handle_cmdline() -> void:
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--printsquad="):                 # test sieci (test_net_session.sh): etykiety drużyny po N s — kryptonimy, „(2)”, czyszczenie
			get_tree().create_timer(float(sa.substr("--printsquad=".length()))).timeout.connect(_print_squad)
		if sa.begins_with("--resultnet="):                 # test sieci: raport po akcji — host kończy misję po N s, klient po N s zgłasza gotowość
			get_tree().create_timer(float(sa.substr("--resultnet=".length()))).timeout.connect(_result_net_step)
		if sa.begins_with("--batterynet="):                # test sieci: bateria 4,5 V — klient słaby, serwer daje mu baterię z ziemi
			get_tree().create_timer(float(sa.substr("--batterynet=".length()))).timeout.connect(_battery_net_step)
	var autoquit := -1.0
	var stealthtest := -1.0
	var wipetest := -1.0
	var missiontest := false
	var stalkertest := false
	var bottest := false
	var nobottest := false
	var funtest := false
	var batterytest := false
	var resulttest := false
	var rangetest := false
	var range3d := false
	var enemytest := false
	var shifttest := false
	var maptest := false
	var uifittest := false
	var ridetest := false
	var ridehost := false
	var rideclient := false
	var gentest := false
	var tagtest := false
	var sneaktest := false
	var passtest := false
	var finaletest := false
	var leechtest := false
	var leechsim := ""
	var shot_path := ""
	var shot_col := -1
	var shot_delay := 1.5
	var shot_depart := false
	var shot_flicker := false
	var shot_demo := false
	var shot_ws := false
	var shot_result := false
	var shot_boss := false
	var shot_codex := false
	var weapon_mode := ""
	var shots_dir := ""
	var args := OS.get_cmdline_user_args()
	if args.has("--nightshift"):
		NightShift.selected = true               # przed --host: tryb zapada przy starcie sesji
	var hd_world := false
	if Settings.hd_active():                          # zasoby HD zawsze poza trybem headless (testy) — flagi poniżej mogą nadpisać
		Sprites.newchar = "tripo-hd-look"
		Sprites.newgun = true
		Sprites.newmon = true
		Sprites.newitem = true
		Sprites.char3d = true                                 # postacie to zawsze modele 3D
		hd_world = true
	for a in args:
		if a == "--newworld":
			hd_world = true                                                                        # teren i tła HD (art/world/); włączane po pętli (jednorazowo)
		if a.begins_with("--look="):
			Profile.look = int(a.substr("--look=".length()))                                     # dev: wygląd bez odblokowania (nie zapisywany: --shot*/--perf ustawiają persist=false)
			Profile.persist = false
		if a == "--nocompress":
			Sprites.compress_hd = false                                                            # dev: bez kompresji S3TC tekstur HD (porównanie)
		if a == "--newmon":
			Sprites.newmon = true                                                                  # dev: wrogowie HD (<rodzaj>_hd)
		if a == "--newitem":
			Sprites.newitem = true                                                                 # dev: przedmioty i rekwizyty HD (art/items/)
		if a.begins_with("--shotweather="):
			Weather.dev_id = a.substr("--shotweather=".length())                                  # dev: wymuś pogodę (clear|rain|storm|fog) do zrzutów
		if a == "--shotflash":
			WEATHER_FX.dev_flash = 1.0                                                             # dev: błysk błyskawicy na stałe
		elif a.begins_with("--shotflash="):
			WEATHER_FX.dev_flash = clampf(float(a.substr("--shotflash=".length())), 0.0, 1.0)     # dev: stała siła błysku 0..1 (0 = bez błysków; pomiary A/B)
		if a == "--char3d-lq":
			Sprites.char3d = true                                                                  # dev: postać 3D w niskiej jakości (SS 2, bez MSAA) — test kosztu na słabszym GPU
			load("res://scripts/char3d.gd").set_low_quality(true)
		if a.begins_with("--charset="):
			load("res://scripts/char3d.gd").charset = a.substr("--charset=".length())              # dev: zestaw modeli postaci (mpfb — domyślny, tripo — stare stylizowane) — porównania
		if a == "--noclips":
			load("res://scripts/char_clips.gd").enabled = false                                    # dev: bez klipów animacji postaci (same pozy z kodu) — porównania
		if a == "--char3d":
			Sprites.char3d = true                                                                  # dev (spike): postać 3D w czasie rzeczywistym zamiast arkuszy
		if a == "--newgun":
			Sprites.newgun = true                                                                  # dev: sprite HD broni (gunhd_*.png)
		if a == "--newchar" or a.begins_with("--newchar="):
			Sprites.newchar = "mix" if a == "--newchar" else a.substr("--newchar=".length())     # dev: postacie 3D zamiast player_N
		if a.begins_with("--sessionlog="):               # dziennik sesji także w headless, do wskazanego katalogu (testy)
			SessionLog.enabled = true
			SessionLog.dir = a.substr("--sessionlog=".length())
		if a == "--nobot":
			Settings.ai_companion = false                 # dev / testy: gra bez AI towarzysza, bez zapisu ustawień (NOBOT_PLAN.md); przed --host
		if a.begins_with("--fakebuild="):                 # dev: inna wersja przy łączeniu (test sprawdzenia wersji, tools/test_net_session.sh)
			_fake_build = a.substr("--fakebuild=".length())
		if a.begins_with("--port="):
			port = a.substr("--port=".length()).to_int()
		elif a.begins_with("--mission="):
			_start_map = a.substr("--mission=".length())
	if hd_world:
		Sprites.newworld = true
	# testy headless zakładają mapę 1.3 (gniazda, boss), chyba że flaga --mission wskaże inną
	if _start_map == "" and (args.has("--range3d") or args.has("--rangetest") or args.has("--workshoptest") or args.has("--cabinettest") or args.has("--cabinetnet")):
		_start_map = "z1_hub"                       # strzelnica FPP (RANGE_FPS_PLAN.md): szpic startuje w kryjówce
	if _start_map == "":
		for a in args:
			if a.begins_with("--stealthtest") or a.begins_with("--wipetest") or a == "--missiontest" or a == "--shifttest" \
					or a == "--weapontest" or a.begins_with("--weaponshots=") or a == "--weaptestnet" or a == "--weaptestclient" 					or a == "--stalkertest" or a == "--bottest" or a == "--enemytest" or a == "--funtest":
				_start_map = "z1_m3"
	for a in args:
		if a == "--host":
			host_game()
		elif a.begins_with("--join=") and not _session_ended:
			join_game(a.substr("--join=".length()))
		elif a == "--steam-host":
			steam.host.call_deferred()
		elif a.begins_with("--steam-join=") and not _session_ended:
			steam.join.call_deferred(a.substr("--steam-join=".length()))
		elif a.begins_with("--difficulty="):
			var d := Difficulty.parse(a.substr("--difficulty=".length()))
			if d >= 0:
				Difficulty.set_level(d)
			else:
				push_warning("Unknown --difficulty (use easy|normal|hard)")
		elif a.begins_with("--autoquit="):
			autoquit = a.substr("--autoquit=".length()).to_float()
		elif a == "--stealthtest":
			stealthtest = 20.0
		elif a.begins_with("--stealthtest="):
			stealthtest = a.substr("--stealthtest=".length()).to_float()
		elif a == "--missiontest":
			missiontest = true
		elif a == "--stalkertest":
			stalkertest = true
		elif a == "--bottest":
			bottest = true
		elif a == "--nobottest":
			nobottest = true
		elif a == "--funtest":
			funtest = true
		elif a == "--batterytest":
			batterytest = true
		elif a == "--resulttest":
			resulttest = true
		elif a == "--rangetest":
			rangetest = true
		elif a == "--range3d":
			range3d = true
		elif a == "--enemytest":
			enemytest = true
		elif a == "--shifttest":
			shifttest = true
		elif a == "--maptest":
			maptest = true
		elif a == "--uifittest":
			uifittest = true
		elif a == "--gentest":
			gentest = true
		elif a == "--tagtest":
			tagtest = true
		elif a == "--sneaktest":
			sneaktest = true
		elif a == "--passtest":
			passtest = true
		elif a == "--finaletest":
			finaletest = true
		elif a.begins_with("--leechsim"):
			leechsim = a.substr("--leechsim".length())          # --leechsim=ACC,DPS (domyślnie 0.6,73)
		elif a == "--leechtest":
			leechtest = true
		elif a.begins_with("--shot="):
			shot_path = a.substr("--shot=".length())
		elif a == "--shotcodex":
			shot_codex = true
		elif a == "--shotboss":
			shot_boss = true
		elif a == "--shotresult" or a == "--shotresult4" or a.begins_with("--shotresultt="):
			shot_result = true
		elif a == "--shotws":
			shot_ws = true
		elif a == "--shotdemo":
			shot_demo = true
		elif a == "--shotflicker":
			shot_flicker = true
		elif a == "--shotdepart":
			shot_depart = true
		elif a.begins_with("--shotdelay="):
			shot_delay = float(a.substr("--shotdelay=".length()))
		elif a.begins_with("--shotat="):
			shot_col = int(a.substr("--shotat=".length()))
		elif a == "--ridetest":
			ridetest = true
		elif a == "--ridehost":
			ridehost = true
		elif a == "--rideclient":
			rideclient = true
		elif a == "--weapontest":
			weapon_mode = "unit"
		elif a.begins_with("--weaponshots="):
			weapon_mode = "shots"
			shots_dir = a.substr("--weaponshots=".length())
		elif a == "--weaptestnet":
			weapon_mode = "net_host"
		elif a == "--weaptestclient":
			weapon_mode = "net_client"
		elif a == "--wipetest":
			wipetest = 2.0
		elif a.begins_with("--wipetest="):
			wipetest = a.substr("--wipetest=".length()).to_float()
	if stealthtest >= 0.0:
		_stealth_test_loop(stealthtest)
	if wipetest >= 0.0:
		_wipe_test(wipetest)
	if missiontest:
		_mission_test()
	if shifttest:
		_shift_test()
	if maptest:
		_map_test()
	if uifittest:
		_ui_fit_test()
	if gentest:
		_gen_test()
	if tagtest:
		_tag_test()
	if sneaktest:
		_sneak_test()
	if passtest:
		_pass_test()
	if finaletest:
		_finale_test()
	if leechtest:
		_leech_test()
	if leechsim != "" or "--leechsim" in args:
		var parts := leechsim.trim_prefix("=").split(",")
		_leech_sim(float(parts[0]) if parts.size() > 0 and parts[0] != "" else 0.6, float(parts[1]) if parts.size() > 1 else 73.0)
	var perf_secs := -1.0
	for a in args:
		if a.begins_with("--perf="):
			perf_secs = float(a.substr("--perf=".length()))
	var sweep := 0
	for a in args:
		if a.begins_with("--perfsweep="):
			sweep = int(a.substr("--perfsweep=".length()))
	if "--navstat" in args:
		_nav_stat()
	if perf_secs > 0.0 and sweep > 0:
		_perf_sweep(perf_secs, sweep)
	elif perf_secs > 0.0:
		_perf_run(perf_secs, shot_col)
	if shot_path != "":
		_take_shot(shot_path, shot_col, shot_delay, shot_depart, shot_flicker, shot_demo, shot_ws, shot_result, shot_boss, shot_codex)
	if ridetest:
		_ride_test()
	if ridehost:
		_ride_host_test()
	if rideclient:
		_ride_client_test()
	if rangetest:
		var rt := RANGE_TEST.new()
		rt.name = "RangeTest"
		add_child(rt)
		rt.run(self)
	if args.has("--workshoptest"):
		var wt := WORKSHOP_TEST.new()
		wt.name = "WorkshopTest"
		add_child(wt)
		wt.run(self)
	if args.has("--cabinettest") or args.has("--cabinetnet"):
		var ct := CABINET_TEST.new()
		ct.name = "CabinetTest"
		add_child(ct)
		ct.run(self, args.has("--cabinetnet"))
	if range3d:
		_dev_range3d()
	if stalkertest:
		var st := STALKER_TEST.new()
		st.name = "StalkerTest"
		add_child(st)
		st.run(self)
	if bottest:
		var bt := BOT_TEST.new()
		bt.name = "BotTest"
		add_child(bt)
		bt.run(self)
	if nobottest:
		var nt := NOBOT_TEST.new()
		nt.name = "NobotTest"
		add_child(nt)
		nt.run(self)
	if resulttest:
		var rt := RESULT_TEST.new()
		rt.name = "ResultTest"
		add_child(rt)
		rt.run(self)
	if funtest:
		var ft := FUN_TEST.new()
		ft.name = "FunTest"
		add_child(ft)
		ft.run(self)
	if batterytest:
		var bat := BATTERY_TEST.new()
		bat.name = "BatteryTest"
		add_child(bat)
		bat.run(self)
	if enemytest:
		var et := ENEMY_TEST.new()
		et.name = "EnemyTest"
		add_child(et)
		et.run(self)
	if weapon_mode != "":
		var wt := WEAPON_TEST.new()
		wt.name = "WeaponTest"
		add_child(wt)
		match weapon_mode:
			"unit": wt.run_unit(self)
			"net_host": wt.run_net_host(self)
			"net_client": wt.run_net_client(self)
			"shots": wt.run_shots(self, shots_dir)
	if autoquit >= 0.0:
		await get_tree().create_timer(autoquit).timeout
		Audio.quit_game()

## Test weryfikujący, czy da się wygrać ciszą: podnosimy hałas do progu
## przebudzenia stalkera, potem NIE strzelamy i czekamy, aż zasnie (GDD §18).
## --stealthtest=DŁUGOŚĆ w sekundach (domyślnie 20).
func _stealth_test_loop(duration: float) -> void:
	var t := 0.0
	var fired := false
	var overcharged := false
	# Test mierzy SAMĄ pętlę ciszy ze stalkerem. Zwykli wrogowie budziliby się
	# od wstrzykniętego hałasu i robili walkę, a to test czego innego — usuwamy
	# ich. Punkty hałasu liczymy od startu (mapa nie ma stałych współrzędnych).
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("kind") != null:
			e.queue_free()
	var hp_start := _total_hp()
	var slept_at := -1.0
	var stalker := level.get_node_or_null("Stalker")
	var base: Vector2 = level.spawn_for(1)
	var noise_at := base + Vector2(340, 0)
	var q_at := base + Vector2(940, 0)
	while t < duration and is_inside_tree():
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if fired and slept_at < 0.0 and stalker != null and not stalker.awake:
			slept_at = t
			print("[TEST] stealth: stalker asleep at t=%.1fs noise=%.0f" % [t, NoiseMgr.level])
		if not fired:
			NoiseMgr.add_noise(70.0, noise_at)
			fired = true
			print("[TEST] stealth: injected 70 at x=%.0f, waiting for silence" % noise_at.x)
		elif not overcharged and t >= 3.0:
			var ok := NoiseMgr.use_overcharge(q_at)
			overcharged = true
			print("[TEST] overcharge accepted=%s charges=%d target=x=%.0f" % [str(ok), NoiseMgr.overcharge_charges, q_at.x])
	print("[TEST] stealth result: slept=%s hp_lost=%d (PASS = zasnął i 0 HP straty)" % [
		"t=%.1fs" % slept_at if slept_at >= 0.0 else "NIE", hp_start - _total_hp()])

func _total_hp() -> int:
	var sum := 0
	for c in _players.get_children():
		sum += c.hp
	return sum

## Test wipe (GDD §4): po DELAY s zabija jednego wroga i kładzie wszystkich
## graczy (także klientów — przez deliver_hit), potem sprawdza, czy po
## WIPE_DELAY misja wraca do stanu startowego. --wipetest[=DELAY]
func _wipe_test(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not multiplayer.is_server():
		return
	var victim := level.get_node_or_null("Trzosek1")
	if victim != null:
		victim.take_bullet(victim.global_position + Vector2(-10, 0), 999.0)
	NoiseMgr.add_noise(50.0, Vector2(400, 200))
	for c in _players.get_children():
		c.deliver_hit(99, c.global_position, "test")
	await get_tree().create_timer(0.5).timeout
	print("[TEST] wipe: all_down=%s wipe_left=%.1f trzosek1_alive=%s noise=%.0f" % [
		str(_all_down()), wipe_left, str(victim.alive if victim else null), NoiseMgr.level])
	await get_tree().create_timer(WIPE_DELAY + 0.5).timeout
	var states := []
	for c in _players.get_children():
		states.append("%s hp=%d dead=%s" % [c.name, c.hp, str(c.dead)])
	print("[TEST] after restart: %s | trzosek1_alive=%s noise=%.0f charges=%d attempt=%d" % [
		", ".join(states), str(victim.alive if victim else null), NoiseMgr.level, NoiseMgr.overcharge_charges,
		mission.attempts])

## Test pętli misji: niszczy gniazda, sprawdza otwarcie ekstrakcji i bonus Q,
## przenosi ludzi (tylko hosta — jego autorytet) do flary, czeka na sukces,
## potem nowa misja [Enter] symulowana wprost. --missiontest
## Test pętli misji: gniazda → Żyła → ekstrakcja → sukces → nowa misja.
## Ludzi (tylko hosta — jego autorytet) przenosi do flary. --missiontest
func _mission_test() -> void:
	const PH := ["OBJECTIVE", "BOSS", "EXTRACT", "SUCCESS"]
	await get_tree().create_timer(2.0).timeout
	if not multiplayer.is_server():
		return
	var boss := get_tree().get_first_node_in_group("boss")
	if boss != null:
		boss.take_bullet(boss.global_position + Vector2(-20, 0), 50.0)
		print("[TEST] mission: strzał w śpiącą Żyłę -> hp=%.0f (oczekiwane %.0f, nietykalna)" % [boss.hp, boss.BASE_HP])
	var kp: Node2D = _players.get_node_or_null("1")
	if kp != null:
		Profile.server_award_kill(int(kp.player_id), "trzosek")      # dziennik sesji: zabójstwo człowieka → players[id].kinds i xp_kills (PROGRESSION_PLAN.md P0.3)
	var q_before := NoiseMgr.overcharge_charges
	for n in get_tree().get_nodes_in_group("nests"):
		n.take_bullet(n.global_position + Vector2(-10, 0), 999.0)
	await get_tree().create_timer(0.3).timeout
	print("[TEST] mission: faza=%s nests_left=%d q=%d->%d" % [PH[mission.phase], mission.nests_left, q_before, NoiseMgr.overcharge_charges])
	if boss != null:
		await get_tree().create_timer(3.5).timeout
		var brood := level.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Brood"))
		print("[TEST] mission: Żyła hp=%.0f/%.0f potomstwo=%d" % [boss.hp, boss.max_hp, brood.size()])
		boss.take_bullet(boss.global_position + Vector2(-20, 0), 1.0e9)
		await get_tree().create_timer(0.3).timeout
		var alive_brood := brood.filter(func(n: Node) -> bool: return is_instance_valid(n) and n.alive)
		print("[TEST] mission: po śmierci Żyły faza=%s exit=%s żywe_potomstwo=%d" % [PH[mission.phase], mission.exit_pos, alive_brood.size()])
	for c in _players.get_children():
		if not c.is_bot:
			c.global_position = mission.exit_pos
	await get_tree().create_timer(mission.EXTRACT_TIME + 0.6).timeout
	print("[TEST] mission: faza=%s progress=%.2f time=%.1f downs=%d attempts=%d noise=%.0f" % [
		PH[mission.phase], mission.extract_progress, mission.elapsed, mission.downs, mission.attempts, NoiseMgr.level])
	_restart_mission(true)
	await get_tree().create_timer(0.5).timeout
	var alive := 0
	for n in get_tree().get_nodes_in_group("nests"):
		alive += 1 if n.alive else 0
	var left_brood := level.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Brood") and not n.is_queued_for_deletion()).size()
	print("[TEST] mission restart: faza=%s nests_alive=%d attempts=%d Żyła=%s hp=%.0f potomstwo=%d" % [
		PH[mission.phase], alive, mission.attempts, ["śpi", "czuwa", "martwa"][boss.state] if boss else "-", boss.hp if boss else 0.0, left_brood])

## Menu główne przed lobby (PLAY → lobby z BACK, SETTINGS → ustawienia z menu pauzy). Pomijane przy starcie z linii poleceń
## (--host / --join / --steam-*) i w trybie headless — wtedy lobby jest pierwszym ekranem jak dotąd.
func _setup_main_menu(pause_menu: Control) -> void:
	_lobby.settings_requested.connect(pause_menu.open_settings)
	if DisplayServer.get_name() == "headless" or not _lobby.visible or NoiseMgr.has_network():
		return
	var menu: Control = MAIN_MENU.new()
	menu.name = "MainMenu"
	$UI.add_child(menu)
	$UI.move_child(menu, _lobby.get_index() + 1)
	_lobby.visible = false
	_lobby.set_back_enabled(true)
	menu.set_steam_available(STEAM_NET.is_available())
	menu.play_requested.connect(func() -> void:
		menu.visible = false
		_lobby.visible = true
		_lobby.enter(menu.entry))
	menu.settings_requested.connect(pause_menu.open_settings)
	# OPERATORZY (PROFILES_PLAN.md E3): lista postaci nad menu; pierwsze uruchomienie (postać bez kryptonimu) — od razu kreator
	var ops: Control = OPERATORS_SCREEN.new()
	ops.name = "OperatorsScreen"
	$UI.add_child(ops)
	$UI.move_child(ops, menu.get_index() + 1)
	ops.steam_name = func() -> String: return steam.persona_name() if steam != null and steam.has_method("persona_name") else ""
	menu.operators_requested.connect(func() -> void:
		menu.visible = false
		ops.open())
	ops.closed.connect(func() -> void:
		menu.visible = true)
	if Characters.active_id != "" and bool(Characters.meta(Characters.active_id)["needs_name"]):
		menu.visible = false
		ops.open_creator_first_run.call_deferred()
	elif _has_arg_prefix("--shotchars"):
		menu.visible = false
		ops.open.call_deferred()                     # dev: z --shot=PLIK — zrzut ekranu OPERATORZY; =reset / =delete — z oknem dla aktywnej postaci
		for a in OS.get_cmdline_user_args():
			if a in ["--shotchars=reset", "--shotchars=delete"]:
				ops._open_action.call_deferred("campaign" if a.ends_with("reset") else "delete", Characters.active_id)
	if "--shotlobby" in OS.get_cmdline_user_args():
		menu._play.call_deferred("host")              # dev: z --shot=PLIK — zrzut lobby (opcje hosta, np. towarzysz AI) zamiast menu głównego
	_lobby.back_requested.connect(func() -> void:
		_lobby.visible = false
		menu.visible = true)
	if not Settings.brightness_calibrated:
		var bs: Control = BRIGHTNESS_SCREEN.new()       # pierwszy start: kalibracja jasności przed menu (potem tylko z ustawień)
		bs.setup(true)
		$UI.add_child(bs)

## Wyjście z sesji (host i klient) do ekranu startowego: wyłącza dźwięk, zamyka połączenie i lobby Steam i ładuje scenę od nowa,
## więc misja, wrogowie i gracze zaczynają od czystego stanu (profil i zapis złomu zostają).
func leave_session() -> void:
	if not NoiseMgr.has_network():
		return
	_reset_session()

## Komunikat do lobby po końcu sesji bez woli gracza (utrata hosta, inna wersja). Scena ładuje się od nowa, więc trzyma go static.
static var _drop_note := ""
static var _drop_reason := ""       ## to samo jako stały kod do logu i testów (komunikat jest tłumaczony): host_lost / version / auth
## Sesja w tym procesie już raz się skończyła: po przeładowaniu sceny nie dołączamy znowu z --join / --steam-join / +connect_lobby
## (host z --host hostuje ponownie — na tym stoi --leavetest).
static var _session_ended := false
var _resetting := false

## Koniec sesji bez woli gracza: to samo co leave_session (czysta scena, wyjście z lobby Steam, reset pogody i Nocnego Dyżuru),
## a lobby po przeładowaniu pokazuje powód. Wcześniej klient po utracie hosta zostawał w starym świecie i w lobby Steam.
func _end_session(reason: String, note: String) -> void:
	_drop_reason = reason
	_drop_note = note
	_reset_session()

func _reset_session() -> void:
	if _resetting:
		return
	_resetting = true
	_session_ended = true
	_log_quit("leave")
	Audio.stop_all()
	if steam != null:
		steam.leave()
	# Postacie znikają ze świata, zanim zniknie peer: wyjście z menu pauzy przychodzi przed krokiem fizyki, a przeładowanie sceny
	# dopiero na koniec klatki — w tym jednym kroku stanowiska kryjówki i kontroler broni pytały `is_multiplayer_authority()` bez peera
	# (12 × „No multiplayer peer is assigned” w logu).
	for c in _players.get_children():
		c.remove_from_group("players")
		c.process_mode = Node.PROCESS_MODE_DISABLED
	multiplayer.multiplayer_peer = null
	NightShift.reset_state()
	Weather.current = ""
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()

## Misja w toku kończy się w dzienniku wynikiem "quit" (serwer — tylko on pisze dziennik). Wcześniej wyjście z gry albo z sesji
## zostawiało `mission_start` bez `mission_end` i raporty nie odróżniały rezygnacji od urwanego pliku.
func _log_quit(how: String) -> void:
	if NoiseMgr.is_server() and SessionLog.recording() and mission != null:
		mission.log_end("quit", how)

## Po przeładowaniu sceny: lobby z powodem końca sesji zamiast ekranu startowego.
func _show_drop_note() -> void:
	var menu := $UI.get_node_or_null("MainMenu")
	if menu != null:
		menu.visible = false
	_lobby.visible = true
	_lobby.set_status(_drop_note, true)
	print("[NET] po końcu sesji: sieć=%s graczy=%d lobby=%s powód=%s" % [str(NoiseMgr.has_network()), _players.get_child_count(), str(_lobby.visible), _drop_reason])
	_drop_note = ""
	_drop_reason = ""

# ---------------------------------------------------------------- sprawdzenie wersji

var _fake_build := ""

## Wersja, którą peer pokazuje przy łączeniu: SessionLog.build() (config/version + commit, ta sama co w stopce menu).
func net_build() -> String:
	return _fake_build if _fake_build != "" else SessionLog.build()

## Uwierzytelnienie SceneMultiplayer = sprawdzenie wersji, zanim peer w ogóle zostanie połączony (przed mapą, postaciami i RPC).
## Oba końce wysyłają swój build surowymi bajtami — nie RPC, bo numeracja RPC różni się między buildami — i dopuszczają peera tylko
## przy identycznym. Wcześniej klient z innym buildem wchodził do gry, a niezgodne RPC psuły się po cichu.
func _on_peer_authenticating(id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, net_build().to_utf8_buffer())

func _on_peer_auth(id: int, data: PackedByteArray) -> void:
	var theirs := data.get_string_from_utf8()
	if theirs == net_build():
		(multiplayer as SceneMultiplayer).complete_auth(id)
		return
	print("[NET] version mismatch: peer %d has %s, local %s" % [id, theirs, net_build()])
	if multiplayer.is_server():
		return                  # bez complete_auth peer odpada po auth_timeout; powód pokazuje klient
	_end_session.call_deferred("version", tr("Version mismatch — the host has %s, you have %s. Everyone needs the same build.") % [theirs, net_build()])

## Peer nie przeszedł sprawdzenia w czasie `auth_timeout`: po stronie klienta to host, który nic nie wysłał (build sprzed sprawdzenia
## wersji) albo odrzucił nas po swojej stronie.
func _on_peer_auth_failed(id: int) -> void:
	print("[NET] authentication failed: peer %d" % id)
	if multiplayer.is_server() or _resetting:
		return
	_end_session.call_deferred("auth", tr("The host did not pass the version check — it may be running a different build."))

## Test (--host --leavetest): host → leave_session() → scena ładuje się od nowa i hostuje ponownie (flaga --host zostaje):
## sprawdza, że port jest wolny, a stan jest czysty (jeden gracz, brak starych botów). Stan między instancjami trzyma static.
static var _leave_stage := 0

func _leave_test() -> void:
	await get_tree().create_timer(1.0).timeout
	if _leave_stage == 0:
		_leave_stage = 1
		print("[LEAVE-TEST] sesja: sieć=%s graczy=%d — wychodzę" % [str(NoiseMgr.has_network()), _players.get_child_count()])
		# jak przycisk w menu pauzy: gra zatrzymana, a wyjście przychodzi przed krokiem fizyki (wejście jest obsługiwane na początku klatki)
		get_tree().paused = true
		get_tree().physics_frame.connect(leave_session, CONNECT_ONE_SHOT)
		return
	var humans := 0
	for p in _players.get_children():
		humans += 0 if p.is_bot else 1
	var ok := NoiseMgr.has_network() and multiplayer.is_server() and humans == 1 and not NightShift.active
	print("[LEAVE-TEST] %s po ponownym starcie: sieć=%s serwer=%s ludzi=%d (graczy %d)" % ["PASS" if ok else "FAIL", str(NoiseMgr.has_network()), str(multiplayer.is_server()), humans, _players.get_child_count()])
	Audio.quit_game()

func host_game() -> void:
	if NoiseMgr.has_network():
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_lobby.set_status("Could not host on port %d (%s)" % [port, error_string(err)], true)
		return
	multiplayer.multiplayer_peer = peer
	_begin_hosting("port %d" % port)

## Narzędzie deweloperskie (--shot=ŚCIEŻKA [--shotat=KOLUMNA]): po 2,5 s zapisuje obraz z widoku gry (tylko okno gry, bez pulpitu)
## do PNG i kończy. --shotat przenosi człowieka na podłogę w danej kolumnie mapy (np. do obejrzenia strefy kryjówki).
## Dev (--shothp=N): zdrowie gracza 1 na zrzucie (plakietka życia).
## Dev (--perf=SEKUNDY [--shotat=KOLUMNA]): pomiar wydajności po 2 s rozgrzewki — czas klatki bez vsync (średnia, p95, max), wywołania rysowania,
## prymitywy, węzły i pamięć wideo z monitorów silnika; drukuje jedną linię [PERF] i kończy. Nie zastępuje profilera GPU (gl_compatibility nie podaje czasu GPU).
## Dev (--perf=SEK --perfsweep=KROK [--perfwake]): „przejście" mapy — gracz 1 staje co KROK kolumn na każdym piętrze, w każdym miejscu mierzymy SEK sekund
## klatek (bez vsync) i dopisujemy liczbę wrogów w promieniu 400 px. Wynik: tabela najgorszych miejsc (średnia, p95, max, wywołania rysowania, wrogowie).
## `--perfwake` budzi wszystkich wrogów mapy na starcie (najgorszy przypadek: cała mapa goni).
## Dev (--navstat): na bieżącej mapie losuje pary miejsc i liczy trasy dla kogoś, kto nie skacze (Wołek): ile razy zwykła trasa idzie przez skok, a istnieje trasa
## na piechotę (naprawione preferowaniem chodzenia) i ile par jest nieosiągalnych bez skoku (tam wróg stoi pod ścianą i po BLOCK_GIVEUP rezygnuje).
func _nav_stat() -> void:
	await get_tree().create_timer(1.0).timeout
	var nav = level.nav
	var ids: Array = nav.get_point_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var total := 0
	var jump_default := 0
	var fixed := 0
	var blocked := 0
	for i in 600:
		var a: int = ids[rng.randi() % ids.size()]
		var b: int = ids[rng.randi() % ids.size()]
		if a == b or nav.get_point_position(a).distance_to(nav.get_point_position(b)) < 80.0:
			continue
		var pa: Array = nav.find_path(nav.get_point_position(a), nav.get_point_position(b), true)
		if pa.size() < 2:
			continue
		total += 1
		var has_j := false
		for st in pa:
			if int(st["kind"]) == NavGraph.Edge.JUMP:
				has_j = true
		if not has_j:
			continue
		jump_default += 1
		var pw: Array = nav.find_path(nav.get_point_position(a), nav.get_point_position(b), false)
		var still := false
		for st in pw:
			if int(st["kind"]) == NavGraph.Edge.JUMP:
				still = true
		if still:
			blocked += 1
		else:
			fixed += 1
	print("[NAVSTAT] mapa=%s par=%d, zwykła trasa ze skokiem=%d → na piechotę istnieje (naprawione)=%d, nieosiągalne bez skoku=%d" % [level.map_id, total, jump_default, fixed, blocked])
	Audio.quit_game()

func _perf_sweep(secs: float, step: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Profile.persist = false
	await get_tree().create_timer(1.5).timeout
	var p: Node2D = _players.get_node_or_null("1")
	for pl in _players.get_children():
		if pl.get("is_bot") == true:
			pl.queue_free()
	if "--perfwake" in OS.get_cmdline_user_args():
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("wake"):
				e.wake()
	var cols: int = (level._map[0] as String).length()
	var rows: int = level._map.size()
	var stops: Array = []
	for c in range(2, cols - 2, step):
		for r in range(2, rows - 1):
			# podłoga piętra: bryła pod spodem i trzy wolne kafle nad nią (miejsce na gracza)
			if level._is_solid(c, r) and not level._is_solid(c, r - 1) and not level._is_solid(c, r - 2) and not level._is_solid(c, r - 3):
				stops.append(Vector2i(c, r))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)     # ponownie: Settings przy starcie przywraca własny vsync i limit klatek
	Engine.max_fps = 0
	var results: Array = []
	for st in stops:
		p.global_position = Vector2(float(st.x) * 16.0 + 8.0, float(st.y) * 16.0 - 2.0)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.35).timeout
		var times: Array[float] = []
		var calls := 0.0
		var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
		var last := Time.get_ticks_usec()
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			last = now
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		times.sort()
		var n := times.size()
		if n < 3:
			continue
		var sum := 0.0
		for t in times:
			sum += t
		var near := 0
		var awake := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if not (e is RigidBody2D) and p.global_position.distance_to(e.global_position) < 400.0:
				near += 1
				if e.get("active") == true:
					awake += 1
		results.append({"col": st.x, "row": st.y, "avg": sum / float(n), "p95": times[int(float(n) * 0.95)], "max": times[n - 1], "calls": calls / float(n), "near": near, "awake": awake})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["p95"]) > float(b["p95"]))
	var tot := 0.0
	var worst_max := 0.0
	for r in results:
		tot += float(r["avg"])
		worst_max = maxf(worst_max, float(r["max"]))
	print("[SWEEP] mapa=%s przystanków=%d średnia klatka=%.2f ms, najgorsza pojedyncza klatka=%.1f ms" % [level.map_id, results.size(), tot / float(maxi(results.size(), 1)), worst_max])
	for i in mini(results.size(), 12):
		var r: Dictionary = results[i]
		print("[SWEEP]  kol %3d wiersz %2d  avg %.2f  p95 %.2f  max %.1f ms  calls %.0f  wrogów w 400 px: %d (obudzonych %d)" % [r["col"], r["row"], r["avg"], r["p95"], r["max"], r["calls"], r["near"], r["awake"]])
	Audio.quit_game()

func _perf_run(secs: float, col: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Profile.persist = false
	await get_tree().create_timer(1.0).timeout
	if col >= 0:
		var p: Node2D = _players.get_node_or_null("1")
		if p != null:
			var fy := 0.0
			var row0 := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--perfrow="):
					row0 = int(a.substr("--perfrow=".length()))          # piętro: pierwsza podłoga od tego wiersza w dół (np. 51 = podziemia mapy 1.1)
			for r in range(row0, level._map.size()):
				if level._is_solid(col, r) and not level._is_solid(col, r - 1):
					fy = float(r * 16)
					break
			p.global_position = Vector2(float(col) * 16.0 + 8.0, fy - 2.0)
	await get_tree().create_timer(1.0).timeout
	var mobs := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perfmobs="):
			mobs = int(a.substr("--perfmobs=".length()))
	if mobs > 0:
		# test obciążenia: N obudzonych wrogów (mieszanka rodzajów) w promieniu ~250 px wokół gracza
		var pp: Node2D = _players.get_node_or_null("1")
		var kinds := ["trzosek", "wolek", "slepiec", "trzosek", "skoczek", "trzosek"]
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--perfkinds="):
				kinds = Array(a.substr("--perfkinds=".length()).split(","))      # np. kaplan,rzeznik,zerca — elity w teście obciążenia
		var span := 500.0                      # --perfspan=PX: rozstaw wrogów (większy = część poza kadrem)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--perfspan="):
				span = float(a.substr("--perfspan=".length()))
		for i in mobs:
			var off := Vector2(-span * 0.5 + span * float(i) / float(maxi(mobs - 1, 1)), 0.0)
			level._add_enemy("PerfMob%d" % i, kinds[i % kinds.size()], pp.global_position + off)
		await get_tree().create_timer(0.5).timeout
		for i in mobs:
			var en: Node = level.get_node_or_null("PerfMob%d" % i)
			if en != null:
				en.wake()
				if en.get("kind") == "zerca":
					en.set("_sp", 0)                    # ukryty Żerca nic nie rysuje — w teście ujawniony, żeby mierzyć jego model
		await get_tree().create_timer(1.5).timeout
	var flares := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perfflares="):
			flares = int(a.substr("--perfflares=".length()))
	if flares > 0:
		# test obciążenia: K flar rozrzuconych wśród wrogów (każda to światło z cieniami)
		var fp: Node2D = _players.get_node_or_null("1")
		for i in flares:
			level.spawn_flare(fp.global_position + Vector2(-220.0 + 440.0 * float(i) / float(maxi(flares - 1, 1)), -30.0), Vector2.ZERO)
		await get_tree().create_timer(1.5).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)     # ponownie: Settings przy starcie przywraca własny vsync i limit klatek
	Engine.max_fps = 0
	# czas renderu z liczników silnika (okno + SubViewporty widoku 3D) — niezależny od vsync, który sterownik może wymuszać mimo ustawień gry
	var vps: Array[RID] = [get_viewport().get_viewport_rid()]
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		vps.append((n as SubViewport).get_viewport_rid())
	for r in vps:
		RenderingServer.viewport_set_measure_render_time(r, true)
	var gpu_ms: Array[float] = []
	var rcpu := 0.0
	var t_start := Time.get_ticks_msec()
	var spikes: Array = []                       ## [s od startu pomiaru, ms klatki, gpu ms] dla klatek > 40 ms — przestoje do zlokalizowania
	var times: Array[float] = []
	var proc_t := 0.0
	var pairs := 0.0
	var active_o := 0.0
	var phys_t := 0.0
	var calls := 0.0
	var prims := 0.0
	# liczniki skryptów od startu pomiaru (dotąd zawierały też rozgrzewkę i wczytywanie mapy)
	ENEMY.stat_usec = 0
	ENEMY.stat_slide_usec = 0
	NavGraph.stat_calls = 0
	NavGraph.stat_usec = 0
	VIEW3D.stat_usec = 0
	VIEW3D.stat_parts.clear()
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	var fxs := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perffx="):
			fxs = a.substr("--perffx=".length())          # casing,blood,gibs,smoke — sztuczny ruch efektów walki (rzędy wielkości jak przy ogniu ciągłym)
	var fx_acc := {"casing": 0.0, "blood": 0.0, "gibs": 0.0}
	var drag := "--perfdrag" in OS.get_cmdline_user_args()     # smugi ciągnięcia (Żerca): 110 plam na raz, każda klatka dokłada nową
	var v3d: Node = get_tree().get_first_node_in_group("view3d")
	if v3d == null:
		for n in get_tree().root.find_children("*", "", true, false):
			if n.has_method("_drag_smear"):
				v3d = n
				break
	var vfx := load("res://scripts/vfx.gd")
	var pf: Node2D = _players.get_node_or_null("1")
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		var dt_s := float(now - last) / 1e6
		last = now
		if drag and v3d != null and pf != null:
			var dx := randf_range(-200.0, 200.0)
			v3d.call("_drag_smear", pf.global_position + Vector2(dx, 0.0), pf.global_position + Vector2(dx + 16.0, 0.0))
		if fxs != "" and pf != null:
			fx_acc["casing"] += dt_s * 12.0
			fx_acc["blood"] += dt_s * 30.0
			fx_acc["gibs"] += dt_s * 1.5
			while fx_acc["casing"] >= 1.0:
				fx_acc["casing"] -= 1.0
				if "casing" in fxs:
					vfx.casing(level, pf.global_position + Vector2(0, -9), Vector2.RIGHT, false)
			while fx_acc["blood"] >= 1.0:
				fx_acc["blood"] -= 1.0
				if "blood" in fxs:
					vfx.hit(level, pf.global_position + Vector2(randf_range(40.0, 160.0), -10.0), Vector2.LEFT, 0, false, false)
			while fx_acc["gibs"] >= 1.0:
				fx_acc["gibs"] -= 1.0
				if "gibs" in fxs:
					vfx.gibs(level, pf.global_position + Vector2(randf_range(40.0, 160.0), -8.0), Color(0.6, 0.45, 0.35), 9)
		var g := 0.0
		for r in vps:
			g += RenderingServer.viewport_get_measured_render_time_gpu(r)
			rcpu += RenderingServer.viewport_get_measured_render_time_cpu(r)
		rcpu += RenderingServer.get_frame_setup_time_cpu()
		gpu_ms.append(g)
		if times[times.size() - 1] > 40.0:
			spikes.append("%.2fs:%.0fms(gpu %.1f)" % [float(Time.get_ticks_msec() - t_start) / 1000.0, times[times.size() - 1], g])
			if OS.is_stdout_verbose():
				print("[SPIKE-MARK] %.0f ms" % times[times.size() - 1])         # z --verbose: wiersze tuż nad znacznikiem mówią, co się wczytywało
		pairs += Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
		active_o += Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
		proc_t += Performance.get_monitor(Performance.TIME_PROCESS)
		phys_t += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	times.sort()
	var n := times.size()
	var sum := 0.0
	for t in times:
		sum += t
	gpu_ms.sort()
	var gsum := 0.0
	for t in gpu_ms:
		gsum += t
	print("[PERF-SPIKES] ", ", ".join(spikes))
	print("[PERF-GPU] gpu avg=%.2f ms p95=%.2f ms  render_cpu avg=%.2f ms  viewports=%d" % [gsum / float(maxi(gpu_ms.size(), 1)), gpu_ms[int(float(gpu_ms.size()) * 0.95)] if not gpu_ms.is_empty() else 0.0, rcpu / float(maxi(n, 1)), vps.size()])
	print("[PERF] frames=%d avg=%.2f ms (%.0f fps) p50=%.2f p95=%.2f max=%.2f  draw_calls=%.0f prims=%.0f  nodes=%d  vram=%.1f MB  tex_mem=%.1f MB  proc_max=%.2f ms phys_max=%.2f ms  A*=%.0f/s (%.2f ms/frame) enemy_phys=%.2f ms slide=%.2f ms view3d=%.2f ms pairs=%.0f active=%.0f" % [
		n, sum / float(maxi(n, 1)), 1000.0 / maxf(sum / float(maxi(n, 1)), 0.001), times[n / 2], times[int(float(n) * 0.95)], times[n - 1],
		calls / float(maxi(n, 1)), prims / float(maxi(n, 1)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		proc_t / float(maxi(n, 1)) * 1000.0, phys_t / float(maxi(n, 1)) * 1000.0, float(NavGraph.stat_calls) / secs, float(NavGraph.stat_usec) / 1000.0 / float(maxi(n, 1)), float(ENEMY.stat_usec) / 1000.0 / float(maxi(n, 1)), float(ENEMY.stat_slide_usec) / 1000.0 / float(maxi(n, 1)), float(VIEW3D.stat_usec) / 1000.0 / float(maxi(n, 1)), pairs / float(maxi(n, 1)), active_o / float(maxi(n, 1))])
	var parts: Dictionary = VIEW3D.stat_parts
	var pk := parts.keys()
	pk.sort_custom(func(a, b) -> bool: return int(parts[a]) > int(parts[b]))
	print("[PERF-V3D] ", "  ".join(pk.slice(0, 24).map(func(k) -> String: return "%s=%.2f" % [k, float(parts[k]) / 1000.0 / float(maxi(n, 1))])))
	if "--perfreport" in OS.get_cmdline_user_args():
		await _perf_report(vps, v3d)
	Audio.quit_game()

## Dev (--perf=SEK --perfreport): po pomiarze rozbicie kosztu klatki — czas GPU każdego viewportu, najcięższe siatki w kadrze każdej kamery
## widoku 3D (prymitywy wg nazwy węzła, cienie), światła z cieniami w kadrze, największe tekstury materiałów sceny (szacunek pamięci z wymiarów
## i formatu importu) i czas fizyki przy kolejno wyłączanych grupach węzłów (wg skryptu). Wynik: wiersze [PERF-VP], [PERF-MESH], [PERF-LIGHT],
## [PERF-TEX], [PERF-PHYS].
func _perf_report(vps: Array[RID], v3d: Node) -> void:
	# GPU na viewport (pomiar włączony w _perf_run)
	var vp_nodes: Array = [get_viewport()]
	vp_nodes.append_array(get_tree().root.find_children("*", "SubViewport", true, false))
	var vp_gpu := {}
	for i in 90:
		await get_tree().process_frame
		for vp in vp_nodes:
			var r: RID = (vp as Viewport).get_viewport_rid()
			vp_gpu[r] = float(vp_gpu.get(r, 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(r)
	for vp in vp_nodes:
		var v := vp as Viewport
		var sz: Vector2i = (v as SubViewport).size if v is SubViewport else get_viewport().size
		var upd := String(["DISABLED", "ONCE", "WHEN_VISIBLE", "WHEN_PARENT_VISIBLE", "ALWAYS"][(v as SubViewport).render_target_update_mode]) if v is SubViewport else "ROOT"
		print("[PERF-VP] %-18s %5dx%-5d %-8s gpu %.2f ms  msaa3d=%d  3d=%s" % [v.name, sz.x, sz.y, upd, float(vp_gpu.get(v.get_viewport_rid(), 0.0)) / 90.0, v.msaa_3d, str(not v.disable_3d)])
	# siatki w kadrze kamer widoku 3D
	if v3d != null:
		for cam_name in ["_cam_a", "_cam_b"]:
			var cam := v3d.get(cam_name) as Camera3D
			if cam == null:
				continue
			var planes: Array[Plane] = cam.get_frustum()
			var groups := {}
			var tot := 0
			var tot_shadow := 0
			for gi in cam.get_viewport().find_children("*", "GeometryInstance3D", true, false):
				var g := gi as GeometryInstance3D
				if not g.is_visible_in_tree() or (g.layers & cam.cull_mask) == 0:
					continue
				var tris := _perf_tris(g)
				if tris <= 0 or not _perf_in_frustum(g.global_transform * g.get_aabb(), planes):
					continue
				var key := "%s/%s" % [String(g.get_parent().name).rstrip("0123456789"), String(g.name).rstrip("0123456789_")]
				var e: Array = groups.get(key, [0, 0, 0])
				e[0] += tris
				e[1] += 1
				if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					e[2] += tris
					tot_shadow += tris
				groups[key] = e
				tot += tris
			var keys := groups.keys()
			keys.sort_custom(func(a, b) -> bool: return groups[a][0] > groups[b][0])
			print("[PERF-MESH] %s: %d trójkątów w kadrze (bez LOD), w tym rzucających cień %d, grup %d" % [cam_name, tot, tot_shadow, keys.size()])
			for k in keys.slice(0, 15):
				print("[PERF-MESH]   %9d tri  ×%-4d cień %9d  %s" % [groups[k][0], groups[k][1], groups[k][2], k])
			var lights := 0
			var shadowed := 0
			var omni_sh := 0
			for ln in cam.get_viewport().find_children("*", "Light3D", true, false):
				var l := ln as Light3D
				if not l.is_visible_in_tree() or l.light_energy <= 0.0:
					continue
				if l is OmniLight3D or l is SpotLight3D:
					var rng := float(l.get("omni_range") if l is OmniLight3D else l.get("spot_range"))
					if not _perf_in_frustum(AABB(l.global_position - Vector3.ONE * rng, Vector3.ONE * rng * 2.0), planes):
						continue
				lights += 1
				if l.shadow_enabled:
					shadowed += 1
					if l is OmniLight3D:
						omni_sh += 1
			print("[PERF-LIGHT] %s: świateł w kadrze %d, z cieniem %d (omni z cieniem %d — każde to do 6 przebiegów cienia)" % [cam_name, lights, shadowed, omni_sh])
	# tekstury materiałów sceny
	var texs := {}
	for gi in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var mats: Array = [g.material_override, g.material_overlay]
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			for s in (g as MeshInstance3D).get_surface_override_material_count():
				mats.append((g as MeshInstance3D).get_surface_override_material(s))
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				mats.append(mesh.surface_get_material(s))
		for m in mats:
			_perf_collect_textures(m as Material, texs)
	var tex_list := texs.values()
	tex_list.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	var tex_tot := 0.0
	var raw_tot := 0.0
	for t in tex_list:
		tex_tot += t[0]
		if not t[2]:
			raw_tot += t[0]
	print("[PERF-TEX] tekstur w materiałach sceny %d, ok. %.0f MB (z mipmapami), w tym bez kompresji VRAM %.0f MB" % [tex_list.size(), tex_tot, raw_tot])
	for t in tex_list.slice(0, 20):
		print("[PERF-TEX]   %7.1f MB  %s  %s" % [t[0], "VRAM" if t[2] else "RGBA", t[1]])
	# eksperymenty: jedna zmiana naraz na 60 klatek, czas GPU wszystkich viewportów przed i po (zmiana cofana)
	if v3d != null:
		var cam_a := v3d.get("_cam_a") as Camera3D
		var cam_b := v3d.get("_cam_b") as Camera3D
		var env: Environment = cam_a.environment
		var vp_w := cam_a.get_viewport() as SubViewport
		var vp_a := cam_b.get_viewport() as SubViewport
		var moon: DirectionalLight3D = null
		for ln in vp_w.find_children("*", "DirectionalLight3D", true, false):
			if (ln as Node).name == &"Moon":
				moon = ln as DirectionalLight3D
		var forest: Array = vp_w.find_children("*", "MultiMeshInstance3D", true, false)
		var ssil0 := env.ssil_enabled
		var vol0 := env.volumetric_fog_enabled
		# stan sprzed eksperymentów — każda zmiana wraca do niego, a nie do „włączone” (inaczej np. wyłączony w grze cień wracałby włączony)
		var moon_sh0 := moon.shadow_enabled if moon != null else false
		var moon_mode0 := moon.directional_shadow_mode if moon != null else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		var forest_sh0: Array = forest.map(func(f) -> int: return (f as GeometryInstance3D).cast_shadow)
		var msaa_w0 := vp_w.msaa_3d
		var msaa_a0 := vp_a.msaa_3d
		var ssao0 := env.ssao_enabled
		var glow0 := env.glow_enabled
		var scale_mode0 := vp_w.scaling_3d_mode
		var scale0 := vp_w.scaling_3d_scale
		var exps := [
			["cień księżyca wyłączony", func(on: bool) -> void:
				if moon != null: moon.shadow_enabled = false if on else moon_sh0],
			["księżyc: 2 kaskady zamiast 4", func(on: bool) -> void:
				if moon != null: moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if on else moon_mode0],
			["las (multisiatki) bez cienia", func(on: bool) -> void:
				for i in forest.size():
					(forest[i] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else forest_sh0[i]],
			["MSAA 3D wyłączone", func(on: bool) -> void:
				vp_w.msaa_3d = Viewport.MSAA_DISABLED if on else msaa_w0
				vp_a.msaa_3d = Viewport.MSAA_DISABLED if on else msaa_a0],
			["SSIL wyłączone", func(on: bool) -> void:
				env.ssil_enabled = false if on else ssil0],
			["SSAO wyłączone", func(on: bool) -> void:
				env.ssao_enabled = false if on else ssao0],
			["mgła wolumetryczna wyłączona", func(on: bool) -> void:
				env.volumetric_fog_enabled = false if on else vol0],
			["glow wyłączony", func(on: bool) -> void:
				env.glow_enabled = false if on else glow0],
			["świat w skali 0,75 (FSR 1)", func(on: bool) -> void:
				vp_w.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if on else scale_mode0
				vp_w.scaling_3d_scale = 0.75 if on else scale0],
		]
		var base_g := await _perf_gpu_avg(vp_nodes, 60)
		print("[PERF-EXP] GPU wszystkich viewportów: %.2f ms (SSIL %s, mgła wolumetryczna %s)" % [base_g, str(ssil0), str(vol0)])
		var shots := ""                                         # --perfshots=KATALOG: zrzut okna z każdą zmianą (porównanie wyglądu z kosztem)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--perfshots="):
				shots = a.substr("--perfshots=".length())
		if shots != "":
			DirAccess.make_dir_recursive_absolute(shots)
			get_viewport().get_texture().get_image().save_png(shots.path_join("%s_00_base.png" % level.map_id))
		for ei in exps.size():
			var e: Array = exps[ei]
			if (e[0] == "SSIL wyłączone" and not ssil0) or (e[0] == "mgła wolumetryczna wyłączona" and not vol0):
				continue
			(e[1] as Callable).call(true)
			for i in 10:
				await get_tree().process_frame
			var g := await _perf_gpu_avg(vp_nodes, 60)
			if shots != "":
				get_viewport().get_texture().get_image().save_png(shots.path_join("%s_%02d.png" % [level.map_id, ei + 1]))
			(e[1] as Callable).call(false)
			for i in 10:
				await get_tree().process_frame
			if shots != "":
				get_viewport().get_texture().get_image().save_png(shots.path_join("%s_%02d_ref.png" % [level.map_id, ei + 1]))
			var g0 := await _perf_gpu_avg(vp_nodes, 60)
			print("[PERF-EXP]   %-32s %.2f → %.2f ms (%+.2f)" % [e[0], g0, g, g - g0])
	# fizyka: grupy węzłów wg skryptu, każda wyłączona na chwilę
	var by_script := {}
	for nd in get_tree().root.find_children("*", "", true, false):
		if nd.is_physics_processing() and nd.get_script() != null:
			var sp := String((nd.get_script() as Script).resource_path).get_file()
			if not by_script.has(sp):
				by_script[sp] = []
			by_script[sp].append(nd)
	# Performance.TIME_PHYSICS_PROCESS to maksimum z ostatniej sekundy (silnik odświeża je raz na sekundę) — do porównań się nie nadaje.
	# Miarą jest średni czas klatki bez limitu klatek: miarodajny w trybie --headless (bez GPU i vsync), w oknie wyznacza go zwykle GPU.
	Engine.max_fps = 0
	var base := await _perf_frame_avg(0.5)
	print("[PERF-PHYS] średni czas klatki %.2f ms (CPU, jeśli --headless); grupy z _physics_process: %d" % [base, by_script.size()])
	# każda grupa: przed, bez niej, po — zysk względem średniej z przed i po, szum = różnica przed/po
	var rows: Array = []
	for sp in by_script:
		var nodes: Array = by_script[sp]
		var before := await _perf_frame_avg(0.6)
		for nd in nodes:
			if is_instance_valid(nd):
				(nd as Node).set_physics_process(false)
		var t := await _perf_frame_avg(0.6)
		for nd in nodes:
			if is_instance_valid(nd):
				(nd as Node).set_physics_process(true)
		var after := await _perf_frame_avg(0.6)
		rows.append([(before + after) * 0.5 - t, sp, nodes.size(), absf(before - after)])
	rows.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	for r in rows.slice(0, 15):
		print("[PERF-PHYS]   %6.2f ms  ×%-4d %-24s (szum przed/po %.2f ms)" % [r[0], r[2], r[1], r[3]])

## Średni łączny czas GPU (ms) viewportów z N kolejnych klatek.
func _perf_gpu_avg(vp_nodes: Array, n: int) -> float:
	var s := 0.0
	for i in n:
		await get_tree().process_frame
		for vp in vp_nodes:
			if is_instance_valid(vp):
				s += RenderingServer.viewport_get_measured_render_time_gpu((vp as Viewport).get_viewport_rid())
	return s / float(n)

## Średni czas klatki (ms) przez `secs` sekund.
func _perf_frame_avg(secs: float) -> float:
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var n := 0
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		await get_tree().process_frame
		n += 1
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(n, 1))

## Trójkąty geometrii (bez LOD): siatka × liczba instancji multisiatki; 0, gdy brak danych (np. cząsteczki).
func _perf_tris(g: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var count := 1
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
		var mm := (g as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if mesh == null:
		return 0
	var tris := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			var il := am.surface_get_array_index_len(s)
			tris += (il if il > 0 else am.surface_get_array_len(s)) / 3
	else:
		var arr := mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			tris = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			tris = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris * count

## AABB przecina bryłę widzenia (płaszczyzny Camera3D.get_frustum: normalne na zewnątrz).
func _perf_in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for pl in planes:
		var far := Vector3(box.end.x if pl.normal.x < 0.0 else box.position.x, box.end.y if pl.normal.y < 0.0 else box.position.y, box.end.z if pl.normal.z < 0.0 else box.position.z)
		if pl.is_point_over(far):
			return false
	return true

## Tekstury materiału do słownika RID → [MB z mipmapami, ścieżka, kompresja VRAM]; szacunek z wymiarów i pliku importu (.s3tc/.bptc/.etc2 = VRAM).
func _perf_collect_textures(m: Material, out: Dictionary) -> void:
	if m == null:
		return
	var vals: Array = []
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
			vals.append((m as ShaderMaterial).get_shader_parameter(String(u["name"])))
	else:
		for p in m.get_property_list():
			if int(p["type"]) == TYPE_OBJECT:
				vals.append(m.get(String(p["name"])))
	if m.next_pass != null:
		_perf_collect_textures(m.next_pass, out)
	for v in vals:
		if not (v is Texture2D) or out.has((v as Texture2D).get_rid()):
			continue
		var t := v as Texture2D
		var lp := String(t.get("load_path")) if t is CompressedTexture2D else ""
		var vram := lp.contains(".s3tc.") or lp.contains(".bptc.") or lp.contains(".etc2.") or lp.contains(".astc.")
		var bpp := 1.0 if vram else 4.0
		var path := t.resource_path if t.resource_path != "" else ("(%s)" % t.get_class())
		out[t.get_rid()] = [float(t.get_width() * t.get_height()) * bpp * 1.33 / 1048576.0, path, vram]

## Dev `--range3d` (RANGE_FPS_PLAN.md, etap 0): lokalny gracz od razu na strzelnicy FPP; [E] wraca do kryjówki.
func _dev_range3d() -> void:
	await get_tree().create_timer(1.2).timeout
	var p: Node = null
	for i in 50:                                                # klient (--join): własny gracz pojawia się dopiero po połączeniu
		p = _players.get_node_or_null(str(multiplayer.get_unique_id())) if NoiseMgr.has_network() else _players.get_node_or_null("1")
		if p != null:
			break
		await get_tree().create_timer(0.2).timeout
	if p == null and not NoiseMgr.has_network():
		p = _players.get_node_or_null("1")
	if p == null or p.get("fp") != null:
		return
	var door := get_tree().get_first_node_in_group("range_door") as Node2D
	var fp: Node
	if door != null:
		p.global_position = door.global_position + Vector2(0.0, -8.0)      # postać zaparkowana przy drzwiach, jak po [E]
		fp = door.enter(p)
	else:
		fp = FP_RANGE.enter(p)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rangeslot="):
			p.weapons.select_slot(int(a.substr("--rangeslot=".length())))      # broń ze slotu N (0, 1 — długie, 2 — pistolet)
		elif a.begins_with("--rangereload="):                  # --rangereload=S[,empty]: przeładowanie po S s (z pustego magazynka z „,empty”)
			var rr := a.substr("--rangereload=".length()).split(",")
			get_tree().create_timer(float(rr[0])).timeout.connect(func() -> void:
				if rr.size() > 1 and rr[1] == "empty":
					p.weapons.mags[p.weapons.cur().id] = 0
				p.weapons.try_reload())
		elif a.begins_with("--rangeweapon="):                  # --rangeweapon=KLUCZ: ta broń w slocie 1, pełny magazynek (zrzuty broni specjalnych)
			var wkey := a.substr("--rangeweapon=".length())
			for wi in Weapons.COUNT:
				if String(Weapons.def(wi).key) == wkey:
					p.weapons.loadout[0] = wi
					p.weapons.mags[wi] = Weapons.def(wi).mag
					p.weapons.select_slot(1)
					p.weapons.select_slot(0)
		elif a.begins_with("--rangeleave="):                   # --rangeleave=S: wyjście ze strzelnicy po S s (nagranie przejścia do kryjówki)
			get_tree().create_timer(float(a.substr("--rangeleave=".length()))).timeout.connect(func() -> void:
				if is_instance_valid(fp):
					fp.leave())
		elif a.begins_with("--rangeex="):                      # --rangeex=reload: ćwiczenie na starcie (plates / reload)
			fp.sim.set_exercise(a.substr("--rangeex=".length()))
		elif a == "--shotrangeboard":                          # przykładowe serie na papierze do zrzutu tablicy porównania grup
			fp.sim.paper_holes = [Vector2(0.01, 0.0), Vector2(-0.02, 0.03), Vector2(0.03, 0.05), Vector2(0.0, 0.08), Vector2(0.02, 0.11)]
			fp.paper_cond = {"w": Weapons.M83, "real": true, "heat0": 0.08, "heat1": 0.41, "braced": 0, "n": 5}
			fp.paper_prev = {"g": {"n": 5, "moa": 6.2, "vertical": 0.035}, "c": {"w": Weapons.M83, "real": true, "heat0": 0.05, "heat1": 0.3, "braced": 5, "n": 5}}
		elif a == "--rangelocker":                             # otwarta szafa z bronią (zrzut listy)
			fp.toggle_locker.call_deferred()
		elif a == "--rangeparts":                              # szafa w widoku gniazd M-83 z PBS-1 na wylocie (zrzut próby części)
			fp.toggle_locker.call_deferred()
			fp.locker_open_parts.call_deferred(fp.locker_weapons().find(Weapons.M83))
			fp.set_deferred("locker_slot", 2)
			fp.set_deferred("locker_choice", {"feed": "", "barrel": "", "muzzle": "m83_pbs1", "stock": ""})
		elif a == "--rangeads":
			fp.dev_ads = true                                   # przyrządy bez PPM (zrzuty)
		elif a.begins_with("--rangeads="):                     # --rangeads=T: stały postęp przyrządów 0..1 (zrzuty przejścia)
			fp.dev_ads_t = clampf(float(a.substr("--rangeads=".length())), 0.0, 1.0)
		elif a.begins_with("--rangelook="):                    # --rangelook=YAW,PITCH (°): kierunek patrzenia
			var lk := a.substr("--rangelook=".length()).split(",")
			fp.yaw = deg_to_rad(float(lk[0]))
			fp.pitch = deg_to_rad(float(lk[1])) if lk.size() > 1 else 0.0
		elif a.begins_with("--rangefire="):                    # --rangefire=S: spust wciśnięty przez S s od 1 s (seria do zrzutu)
			var hold := float(a.substr("--rangefire=".length()))
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				p.weapons.sim_fire = true
				p.weapons.sim_press = true)                          # broń półautomatyczna strzela z naciśnięcia, nie z trzymania
			get_tree().create_timer(1.0 + hold).timeout.connect(func() -> void: p.weapons.sim_fire = false)

func _take_shot(path: String, col: int, delay: float = 1.5, depart := false, flicker := false, demo := false, workshop := false, result := false, boss := false, codex := false) -> void:
	Profile.persist = false              # zrzuty dev nie zapisują profilu gracza (XP z podglądu karty wyniku itp.)
	if "--bestiaryfresh" in OS.get_cmdline_user_args():
		Profile.bestiary = {"wolek": 2}                       # dev: bestiariusz nowego gracza (spotkał tylko Wołka) — zakryte wpisy na zrzucie i odkrywanie w misji
	await get_tree().create_timer(1.0).timeout
	if codex:
		var pm: Node = $UI.get_node("PauseMenu")             # podgląd bestiariusza: ostatni wpis (boss)
		pm.open()
		pm._show_tab(1)
		var bp: Node = pm.page_of(1)
		var ci: int = bp._entries.size() - 1
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--codexentry="):
				ci = clampi(int(a.substr("--codexentry=".length())), 0, bp._entries.size() - 1)       # dev: wpis bestiariusza do zrzutu
		bp.select(ci)
	if _has_arg_prefix("--shotpause"):
		var spm: Node = $UI.get_node("PauseMenu")           # --shotpause[=N]: menu pauzy na karcie N (0 SETTINGS … 5 CONTROLS; z --lang=pl — przegląd tłumaczeń)
		spm.open()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shotpause="):
				spm._show_tab(clampi(int(a.substr("--shotpause=".length())), 0, 5))
	if "--shotperkcard" in OS.get_cmdline_user_args():
		Profile.reset_for_test()                      # --shotperkcard: karta PERKS w menu pauzy (L4, Smith w slocie 1)
		Profile.add_xp(800, "demo")
		Profile.equip(0, "smith")
		var ppm: Node = $UI.get_node("PauseMenu")
		ppm.open()
		ppm._show_tab(4)
		ppm.page_of(4).select(3)
	if _has_arg_prefix("--shotweapons"):
		var wpm: Node = $UI.get_node("PauseMenu")           # --shotweapons[=N]: karta WEAPONS kodeksu (wpis N, domyślnie P-83)
		wpm.open()
		wpm._show_tab(2)
		var wi := 0
		for ei in wpm.page_of(2)._entries.size():                 # lista pogrupowana wg slotu (1.7.407): P-83 szukamy po id
			if int(wpm.page_of(2)._entries[ei].get("weapon_id", -1)) == Weapons.P64:
				wi = ei
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shotweapons="):
				wi = int(a.substr("--shotweapons=".length()))
		wpm.page_of(2).select(wi)
	if "--shotgear" in OS.get_cmdline_user_args():
		var gpm: Node = $UI.get_node("PauseMenu")           # --shotgear: karta GEAR kodeksu (mina)
		gpm.open()
		gpm._show_tab(3)
		gpm.page_of(3).select(3)
	if boss:
		mission._start_boss()               # podgląd walki z bossem: budzi bossa i rzuca flarę nad jego cień
		await get_tree().create_timer(0.6).timeout
		var bs := get_tree().get_first_node_in_group("boss")
		if bs != null:
			level.spawn_flare(Vector2(bs.global_position.x + 30.0, bs.global_position.y - 20.0), Vector2.ZERO)
			for ca in OS.get_cmdline_user_args():
				if ca.begins_with("--shotclip="):                 # --shotboss --shotclip=death|hit: zdarzenie bossa 1 s po starcie (podgląd klipów modelu 3D)
					get_tree().create_timer(1.0).timeout.connect(_dev_clip.bind(bs, ca.substr("--shotclip=".length())))
			if "--shottide" in OS.get_cmdline_user_args() and bs.has_method("_tick_surge"):
				bs.phase = 2                         # --shottide: od razu faza 2 i fala przypływu (zapowiedź ~2 s, potem wysoka woda)
				bs._surge_cd = 0.05
			if "--shotsweep" in OS.get_cmdline_user_args() and bs.has_method("_tick_wave"):
				bs.call("_begin", 3, 0.9, Vector2.ZERO)        # --shotsweep: Żyła od razu zamachuje się falą (--shotdelay=0.4 zapowiedź, =1.0 fala)
			if "--shotspit" in OS.get_cmdline_user_args() and bs.has_method("_tick_wave"):
				var sp1: Node2D = _players.get_node_or_null("1")       # --shotspit: Żyła pluje w gracza 1 po 0,3 s, gdy --shotat już go przeniósł (--shotdelay=1.0 zapowiedź, =1.6 plwocina w locie)
				get_tree().create_timer(0.3).timeout.connect(func() -> void:
					bs.call("_begin", 2, 0.9, (sp1.global_position if sp1 != null else bs.global_position) + Vector2(0, -8)))
			if "--shotup" in OS.get_cmdline_user_args() and bs.has_method("_surface"):
				bs.call("_surface")         # --shotup: Pijawka od razu wynurzona (podgląd arkusza, z chwytem, jeśli gracz stoi w zasięgu)
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shotextract="):                  # dev: punkt ewakuacji — 0 = tuż obok, 1 = w strefie z postępem, 2 = jak 1 + finał kopalni
			var mode := int(sa.substr("--shotextract=".length()))
			mission._open_extraction(false)
			var xp: Node2D = _players.get_node_or_null("1")
			if xp != null:
				xp.global_position = mission.exit_pos + Vector2(-70.0 if mode == 0 else -8.0, -2.0)
				xp.velocity = Vector2.ZERO
			if mode >= 1:
				mission.extract_progress = 0.15
			if mode >= 2:
				mission.finale = true
	if "--shotacid" in OS.get_cmdline_user_args():
		var ap: Node2D = _players.get_node_or_null("1")       # --shotacid: seria kul kwasu Pijawki lecących łukiem przed graczem (podgląd grafiki pocisku)
		if ap != null:
			for ai in 24:
				get_tree().create_timer(0.3 + 0.12 * float(ai)).timeout.connect(func() -> void:
					var ac: Node2D = load("res://scripts/acid_spit.gd").new()
					ac.set("vel", Vector2(-70.0, -210.0))
					level.add_child(ac)
					ac.global_position = ap.global_position + Vector2(90.0, -14.0))
	if "--shotrun" in OS.get_cmdline_user_args():
		Input.action_press("move_right")                      # --shotrun: gracz 1 biegnie w prawo przez cały podgląd (ocena animacji biegu)
	if "--shotcrouch" in OS.get_cmdline_user_args():
		Input.action_press("crouch")                          # --shotcrouch: gracz 1 skrada się przez cały podgląd
	for fa in OS.get_cmdline_user_args():
		if fa.begins_with("--shotfit="):                       # dev: --shotfit=id,id… — drużyna ma te części, gracz je montuje (podgląd modelu z częściami, parts.gd)
			for pid in fa.substr("--shotfit=".length()).split(","):
				var pp: Dictionary = Weapons.Parts.get_part(pid)
				if not pp.is_empty():
					Scrap.parts[pid] = true
					Profile.set_fit(String(pp["weapon"]), String(pp["slot"]), pid)
	for na in OS.get_cmdline_user_args():
		if na.begins_with("--shotnotch="):                     # dev: --shotnotch=N — każda broń ma N nacięć (w tym jedno głębokie, boss) i 120 zabójstw; profil bez zapisu
			Profile.persist = false
			var nn := int(na.substr("--shotnotch=".length()))
			for wk in Weapons.COUNT:
				Profile.history[String(Weapons.def(wk).key)] = {"k": 120, "e": maxi(0, nn - 1), "b": 1 if nn > 0 else 0}
	for ia in OS.get_cmdline_user_args():
		if ia.begins_with("--shotinspect"):                   # dev: --shotinspect[=N] — gracz przy N-tym stojaku (od lewej) z otwartymi oględzinami broni
			var ip: Node2D = _players.get_node_or_null("1")
			var racks := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "weapon" and n.static_display)
			racks.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
			var ri := int(ia.substr("--shotinspect=".length())) if ia.contains("=") else 0
			if ip != null and ri < racks.size():
				ip.global_position.x = (racks[ri] as Node2D).global_position.x
				ip.velocity = Vector2.ZERO
				get_tree().create_timer(0.4).timeout.connect(func() -> void:
					ip.weapons.inspect_item = racks[ri]
					ip.weapons._inspect_hp = float(ip.hp))
				if "--shotswap" in OS.get_cmdline_user_args():             # …oględziny, potem [E]: zamiana broni po 1,6 s (podgląd postaci po zamianie)
					get_tree().create_timer(1.6).timeout.connect(func() -> void:
						ip.weapons.inspect_item = null
						ip.weapons._try_pickup())
				if "--shotinspectclose" in OS.get_cmdline_user_args():     # …i zamknięcie po 1,6 s (podgląd powrotu do zwykłego widoku)
					get_tree().create_timer(1.6).timeout.connect(func() -> void:
						ip.weapons.inspect_item = null)
				if "--shotinspecttwice" in OS.get_cmdline_user_args() and ri + 1 < racks.size():     # …zamknięcie, potem oględziny następnego stojaka od 2,6 s (z --shotinspectclose: zamknięte po 4,4 s)
					get_tree().create_timer(1.6).timeout.connect(func() -> void:
						ip.weapons.inspect_item = null)
					get_tree().create_timer(2.2).timeout.connect(func() -> void:
						ip.global_position.x = (racks[ri + 1] as Node2D).global_position.x)
					get_tree().create_timer(2.6).timeout.connect(func() -> void:
						ip.weapons.inspect_item = racks[ri + 1]
						ip.weapons._inspect_hp = float(ip.hp))
					if "--shotinspectclose" in OS.get_cmdline_user_args():
						get_tree().create_timer(4.4).timeout.connect(func() -> void:
							ip.weapons.inspect_item = null)
	if "--shotfinale" in OS.get_cmdline_user_args():
		mission.finale = true                                 # --shotfinale: finał kopalni bez przenoszenia gracza (pył ze stropu; użyj z --shotat/--shotrow)
	if "--shotwall" in OS.get_cmdline_user_args():
		var sw := get_tree().get_first_node_in_group("breakables")      # --shotwall: gracz tuż przed zamurowanym przejściem (mapa 1.2)
		var sp: Node2D = _players.get_node_or_null("1")
		if sw != null and sp != null:
			sp.global_position = sw.global_position + Vector2(40.0, -1.0)
			sp.velocity = Vector2.ZERO
	if "--shotscan" in OS.get_cmdline_user_args():
		var scp: Node2D = _players.get_node_or_null("1")     # --shotscan: skaner Sowa włączony (użyj z --shotat=KOLUMNA przy wrogach)
		if scp != null:
			Arsenal.throw_sel = Throwables.ORDER.find("scanner")
			scp.call_deferred("_start_scan")
	if "--shotnade" in OS.get_cmdline_user_args():
		var gp: Node2D = _players.get_node_or_null("1")      # --shotnade: granat fosforowy rzucony przed gracza (pole ognia po ~1,5 s)
		if gp != null:
			Arsenal.cycle_throwable()
			Arsenal.request_throw("phos", gp.global_position + Vector2(50.0, -20.0), Vector2(60.0, -20.0))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotzoom="):                       # dev: powiększenie kamery gracza 1 (zrzuty szczegółów)
			var zp: Node2D = _players.get_node_or_null("1")
			if zp != null:
				zp._camera.zoom *= float(a.substr("--shotzoom=".length()))
				zp._camera.offset += Vector2(-20.0, 26.0)
	if _has_arg_prefix("--shotloot"):
		var lp: Node2D = _players.get_node_or_null("1")       # --shotloot: torby zaopatrzenia z każdą zawartością z puli zrzutów na przemian po obu stronach
		if lp != null:                                        # gracza; --shotloot=ammo: skrzynki amunicji różnych broni (podgląd oznaczeń zawartości); =cache: skrzynie z mapy
			var ammo := "--shotloot=ammo" in OS.get_cmdline_user_args()
			if "--shotloot=cache" in OS.get_cmdline_user_args():     # --shotloot=cache: skrzynie z mapy (sterty zawartości) po obu stronach gracza
				for dx in [-34.0, 40.0]:
					level.spawn_item("cache", 0, lp.global_position + Vector2(dx, -14.0))
			var loot: Array = [] if "--shotloot=cache" in OS.get_cmdline_user_args() else ([9, 1, 7, 8, 0, 3, 4, 5, 6] if ammo else Throwables.DROP_WEIGHTS.keys())
			for li in loot.size():
				var dx := (-1.0 if li % 2 == 0 else 1.0) * (22.0 + (13.0 if ammo else 19.0) * float(li / 2))
				if ammo:
					level.spawn_item("ammo", int(loot[li]), lp.global_position + Vector2(dx, -14.0), 1)
				else:
					level.spawn_item("supply", Throwables.ORDER.find(String(loot[li])), lp.global_position + Vector2(dx, -14.0))
	if "--shothurt" in OS.get_cmdline_user_args():
		var hp1: Node2D = _players.get_node_or_null("1")       # --shothurt: gracz 1 z 1 HP (podgląd ran na ciele i ostrzeżenia obrazem)
		if hp1 != null:
			hp1.hp = 1
			NoiseMgr.level = 60.0
	if "--shotchip" in OS.get_cmdline_user_args():
		var cp: Node2D = _players.get_node_or_null("1")       # --shotchip: gracz 1 z ukrytym pół punktem zabranym głazem Wołka (pół kreski życia)
		if cp != null:
			cp.chip = 0.5
	if "--shottoast" in OS.get_cmdline_user_args():
		_toast("Steam overlay unavailable (start the game from Steam / add it as a non-Steam game). Lobby ID 109775240944 copied — send it to friends: paste + STEAM JOIN.", 20.0)      # --shottoast: podgląd komunikatu F2
	if "--shotgen" in OS.get_cmdline_user_args():
		var g0 := get_tree().get_first_node_in_group("generators")       # --shotgen[=1]: generator w połowie rozruchu (z =run: pracujący) — użyj z --shotat/--shotrow
		if g0 != null:
			if "--shotgenrun" in OS.get_cmdline_user_args():
				g0.running = true
			else:
				g0.progress = 0.55
			level.spawn_flare(g0.global_position + Vector2(-30.0, -50.0), Vector2.ZERO)
	if "--shotstrongbox" in OS.get_cmdline_user_args():
		for sb in get_tree().get_nodes_in_group("strongboxes"):       # --shotstrongbox: sejfy otwarte (podgląd otwartej skrzyni; użyj z --shotat/--shotrow)
			sb._set_open(true, sb.value)
	if "--shothandcar" in OS.get_cmdline_user_args():
		var hc := get_tree().get_first_node_in_group("handcar")       # --shothandcar: drezyna zasilona i oświetlona flarą (podgląd HD; użyj z --shotat/--shotrow)
		if hc != null:
			hc.enabled = true
			level.spawn_flare(hc.global_position + Vector2(-20.0, -40.0), Vector2.ZERO)
			var hp1: Node2D = _players.get_node_or_null("1")
			if hp1 != null and not _has_arg_prefix("--shotat"):            # bez --shotat: gracz 1 staje obok drezyny
				hp1.global_position = hc.global_position + Vector2(-64.0, -4.0)
	if _has_arg_prefix("--shotbreak"):                 # dev: gracz 1 przy pierwszym zamurowanym przejściu; `--shotbreak=1` rozbija je po 1,5 s
		var bw := get_tree().get_first_node_in_group("breakables") as Node2D
		var bp: Node2D = _players.get_node_or_null("1")
		if bw != null and bp != null:
			bp.global_position = bw.global_position + Vector2(-56.0, -4.0)
			bp.velocity = Vector2.ZERO
	if "--shotbreak=1" in OS.get_cmdline_user_args():
		var bw1 := get_tree().get_first_node_in_group("breakables")
		if bw1 != null:
			get_tree().create_timer(1.5).timeout.connect(level.break_wall.bind(String(bw1.name)))
	if "--shotblood" in OS.get_cmdline_user_args():                 # dev: szczątki i krew 60 px przed graczem 1 (podgląd kałuż krwi), bez wrogów
		var blp: Node2D = _players.get_node_or_null("1")
		if blp != null:
			for k in 3:
				load("res://scripts/vfx.gd").gibs(level, blp.global_position + Vector2(50.0 + 30.0 * float(k), -10.0), Color(0.5, 0.1, 0.1), 8)
	if "--shothubreturn" in OS.get_cmdline_user_args():             # dev: po 1 s przejście z misji do kryjówki (jak po wygranej) — test przebudowy sceny
		get_tree().create_timer(1.0).timeout.connect(_restart_mission.bind(true, "z1_hub", true))
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			var hp2: Node2D = _players.get_node_or_null("1")
			var rk := get_tree().get_first_node_in_group("pickups") as Node2D
			for pk in get_tree().get_nodes_in_group("pickups"):
				if pk.get("static_display") == true:
					rk = pk
			if hp2 != null and rk != null:
				hp2.global_position = rk.global_position + Vector2(-40.0, -4.0))
	if "--shotclear" in OS.get_cmdline_user_args():
		for ce in get_tree().get_nodes_in_group("enemies"):       # --shotclear: bez wrogów (spokojny podgląd obiektów świata)
			if not (ce is RigidBody2D):
				ce.queue_free()
	if "--shotextract" in OS.get_cmdline_user_args():
		mission._open_extraction(false)                       # --shotextract: od razu faza ewakuacji (flara z płomieniem i słupem światła), gracz 1 obok niej
		var xp: Node2D = _players.get_node_or_null("1")
		if xp != null:
			xp.global_position = mission.exit_pos + Vector2(-46.0, -2.0)
	if "--shotgibs" in OS.get_cmdline_user_args():
		var gp2: Node2D = _players.get_node_or_null("1")      # --shotgibs: szczątki trzech rodzajów stworów przed graczem (podgląd grafiki szczątków i krwi)
		if gp2 != null:
			var vfx := load("res://scripts/vfx.gd")
			vfx.gibs(level, gp2.global_position + Vector2(40.0, -24.0), Color(0.8, 0.66, 0.46), 14)
			vfx.gibs(level, gp2.global_position + Vector2(70.0, -24.0), Color(0.42, 0.14, 0.18), 14)
			vfx.gibs(level, gp2.global_position + Vector2(100.0, -24.0), Color(0.18, 0.3, 0.26), 14)
			for i in 6:
				vfx.casing(level, gp2.global_position + Vector2(-60.0 + 6.0 * float(i), -14.0), Vector2.RIGHT, i % 3 == 0)
			for i in 5:
				vfx.debris(level, gp2.global_position + Vector2(130.0, -20.0), Vector2(randf_range(-60.0, 60.0), randf_range(-120.0, -40.0)), Vector2(3, 3), Color(0.5, 0.3, 0.24))
	if "--shotsmoke" in OS.get_cmdline_user_args():
		var sp2: Node2D = _players.get_node_or_null("1")      # --shotsmoke: chmura dymu 80 px przed graczem (podgląd granatu dymnego)
		if sp2 != null:
			level.spawn_smoke(sp2.global_position + Vector2(90.0, -10.0), 20.0)
	if "--shotitems" in OS.get_cmdline_user_args():
		var ip: Node2D = _players.get_node_or_null("1")      # --shotitems: rząd przedmiotów na ziemi przed graczem (apteczka, amunicja, złom, skrzynie, flary, skrytka, nieśmiertelnik) + granat, mina, ładunek, flara
		if ip != null:
			var items := [["scrap", 0, 8], ["scrap", 0, 3], ["stash", 0, 20], ["tag", 0, 0], ["cache", 0, 0], ["battery", 0, 0]] if "--shotitems2" in OS.get_cmdline_user_args() else [["health", 0, 0], ["ammo", Weapons.M83, 30], ["ammo", Weapons.SPREAD12, 8], ["scrap", 0, 3], ["scrap", 0, 8], ["cache", 0, 0], ["flares", 0, 2],
				["supply", 0, 0], ["supply", 3, 0], ["supply", 5, 0], ["stash", 0, 20], ["tag", 0, 0]]
			for i in items.size():
				level.spawn_item(items[i][0], items[i][1], ip.global_position + Vector2(-60.0 + 24.0 * float(i), -8.0), items[i][2])
			await get_tree().create_timer(1.5).timeout
			if not "--shotnothrow" in OS.get_cmdline_user_args():
				Arsenal.request_throw("frag", ip.global_position + Vector2(-30.0, -20.0), Vector2(30.0, -30.0))
			level.spawn_flare(ip.global_position + Vector2(-70.0, -20.0), Vector2(40.0, -20.0))
			var pm_: Node2D = load("res://scripts/placed.gd").new()
			pm_.kind = "mine"
			pm_.dir = Vector2.RIGHT
			pm_.position = ip.global_position + Vector2(125.0, 0.0)
			level.add_child(pm_)
			var pc_: Node2D = load("res://scripts/placed.gd").new()
			pc_.kind = "charge"
			pc_.position = ip.global_position + Vector2(145.0, 0.0)
			level.add_child(pc_)
	if _has_arg_prefix("--shotmon"):
		var mp: Node2D = _players.get_node_or_null("1")      # --shotmon: Wołek i dwa Trzoski przed graczem, AI zamrożone (jeden obudzony, reszta śpi) — podgląd sprite'ów wrogów
		if mp != null:
			var kinds_arg := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--shotmon="):
					kinds_arg = a.substr("--shotmon=".length())
			var spots := [["ShotS", "slepiec", 110.0], ["ShotW", "wolek", 150.0], ["ShotT", "trzosek", 205.0], ["ShotT2", "trzosek", 240.0]]
			if kinds_arg == "b":          # --shotmon=b: reszta wrogów (Skoczek, Podsłuchacz, Mimik, Ćma) bez bossów
				spots = [["ShotK", "skoczek", 120.0], ["ShotP", "podsluchacz", 165.0], ["ShotM", "mimik", 205.0], ["ShotC", "cma", 245.0]]
			if kinds_arg == "e":          # --shotmon=e: Ślepiec obok elit (Kapłan, Rzeźnik, Żerca)
				spots = [["ShotS", "slepiec", 110.0], ["ShotKa", "kaplan", 150.0], ["ShotR", "rzeznik", 200.0], ["ShotZ", "zerca", 250.0]]
			level.spawn_flare(mp.global_position + Vector2(190.0, -26.0), Vector2.ZERO)
			for pl in _players.get_children():
				if pl.get("is_bot") == true:
					pl.queue_free()                 # bez bota — żeby nie rozstrzelał podglądu
			for sp in spots:
				level._add_enemy(sp[0], sp[1], mp.global_position + Vector2(float(sp[2]), 0.0))
				var en: Node = level.get_node_or_null(String(sp[0]))
				if en != null:
					var live := "--shotlive" in OS.get_cmdline_user_args()      # --shotlive: AI nie jest zamrożone (podgląd póz ruchu)
					if not live:
						en.set_physics_process(false)
					if "--shotdmg" in OS.get_cmdline_user_args():      # --shotdmg: po 0,8 s wrogowie tracą życie do 80 / 55 / 30 / 12% (paski, ślad obrażeń)
						var frac: float = [0.8, 0.55, 0.3, 0.12][spots.find(sp)]
						get_tree().create_timer(0.8).timeout.connect(func() -> void:
							if is_instance_valid(en):
								en.hp = en._max_hp * frac)
					if sp[0] != "ShotT2" or live:
						en.call("wake")
					if "--shotidle" in OS.get_cmdline_user_args():          # --shotidle: wszyscy obudzeni i stoją w miejscu (poza oczekiwania; Trzosek siedzi)
						en.set("active", true)
					if "--shotwind" in OS.get_cmdline_user_args():          # --shotwind: wszyscy w zapowiedzi ataku (podgląd pozy windup)
						en.set("winding", true)
					var clip_arg := ""
					for ca in OS.get_cmdline_user_args():
						if ca.begins_with("--shotclip="):                 # --shotclip=death|hit|attack: zdarzenie 1 s po starcie (podgląd klipów modeli 3D)
							clip_arg = ca.substr("--shotclip=".length())
					if clip_arg != "":
						get_tree().create_timer(1.0).timeout.connect(_dev_clip.bind(en, clip_arg))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotgunid="):                          # dev: broń o danym id (0–11) w pierwszym slocie gracza 1 — podgląd sprite'ów broni
			var gp: Node2D = _players.get_node_or_null("1")
			if gp != null:
				var gid := int(a.substr("--shotgunid=".length()))
				gp.weapons.loadout[0] = gid
				gp.weapons.slot = 0
				gp.weapons.mags[gid] = 10
				gp.weapons.state = 0
				gp.weapons._sync_player()
	if "--shotlight" in OS.get_cmdline_user_args():
		var lp: Node2D = _players.get_node_or_null("1")      # --shotlight: flara tuż przed graczem (podgląd oświetlenia z mapą normalnych)
		if lp != null:
			level.spawn_flare(lp.global_position + Vector2(34.0, -28.0), Vector2.ZERO)
	if "--shottorch" in OS.get_cmdline_user_args():                 # dev: gracz 1 z włączoną latarką (podgląd snopu światła)
		var tp: Node2D = _players.get_node_or_null("1")
		if tp != null:
			tp.set("flashlight", true)
			tp.set("battery", 999.0)
			if tp.get("aim_dir") != null and "--shotaimup" in OS.get_cmdline_user_args():
				tp.set("aim_dir", Vector2(0.8, -0.6))
	if "--shotshoot" in OS.get_cmdline_user_args():                 # dev: gracz 1 strzela serią w prawo przez cały czas zrzutu (podgląd pocisków i efektów)
		var sp1: Node2D = _players.get_node_or_null("1")
		if sp1 != null:
			_dev_shoot(sp1, delay)
	if "--shotfire" in OS.get_cmdline_user_args():
		var fp: Node2D = _players.get_node_or_null("1")      # --shotfire: trzy plamy ognia HKM-9 przed graczem (podgląd)
		if fp != null:
			for i in 3:
				level.spawn_fire_patch(fp.global_position + Vector2(44.0 + 22.0 * float(i), -1.0), Weapons.HKM9, 1)
	if result:
		# podgląd raportu po akcji (RESULTS_PLAN.md): --shotresult (2 graczy), --shotresult4 (4 graczy, gotowość, awans kolegi),
		# --shotresultt=S — sekwencja zatrzymana w chwili S (zrzut z połowy animacji)
		mission.elapsed = 312.0
		mission.peak_noise = 41.0
		var me := NoiseMgr.local_id()
		mission.player_stats = {me: {"name": "P1", "call": "macvv", "kills": 40, "downs": 0, "revived": 0, "revives": 0, "escapes": 0, "lures": 1, "noise": 64.0},
			2: {"name": "P2", "call": "Wilk", "kills": 22, "downs": 0, "revived": 0, "revives": 0, "escapes": 0, "lures": 0, "noise": 12.0}}
		if "--shotresult4" in OS.get_cmdline_user_args():
			mission.player_stats[3] = {"name": "P3", "call": "Kos", "kills": 9, "downs": 0, "revived": 0, "revives": 0, "escapes": 3, "lures": 0, "noise": 40.0}
			mission.player_stats[4] = {"name": "P4", "call": "Sowa", "kills": 14, "downs": 0, "revived": 0, "revives": 2, "escapes": 0, "lures": 0, "noise": 30.0}
		var shot_pl: Node2D = _players.get_node_or_null(str(me))
		for at in [[14.0, "objective"], [61.0, "objective"], [95.5, "woke"], [120.0, "escape"], [133.0, "lure"], [180.0, "objective"], [240.0, "stash"],
				[262.0, "objective"], [300.0, "extract"]]:
			mission.elapsed = float(at[0])
			mission.mark(String(at[1]), shot_pl)
		mission.elapsed = 312.0
		Scrap.loot = 158
		Scrap.found["m83_pbs1"] = true
		Profile.xp = Profile.xp_for_level(6) - 150             # awans w trakcie licznika XP
		Profile.run_xp = 155
		for sa in OS.get_cmdline_user_args():
			if sa.begins_with("--shotresultt="):
				var rs_node := get_tree().root.find_child("ResultScreen", true, false)
				if rs_node != null:
					rs_node.set("hold_at", float(sa.substr("--shotresultt=".length())))
		mission._success()
		if "--shotresult4" in OS.get_cmdline_user_args():
			mission.result_ready = {2: true, 4: true}
			mission.result_levels = {2: [4, 5]}
	if workshop:
		# podgląd panelu warsztatu: portfel, jedna kupiona broń i ulepszenia (tylko w pamięci; zapis wyłączony w trybie podglądu)
		Scrap.persist = false
		Scrap.bank = 480
		Scrap.unlocked[Weapons.LR7] = true
		for pid in ["m83_rpk40", "m83_rpkbar", "lr7_cell"]:
			Scrap.parts[pid] = true                  # podgląd: kilka odblokowanych części
		Scrap.changed.emit()                         # montaż gracza (player.fits) jak po zakupie w grze
		var wp: Node2D = _players.get_node_or_null("1")
		var bench := get_tree().get_first_node_in_group("workshop") as Node2D
		if wp != null and bench != null:
			wp.global_position = bench.global_position + Vector2(0.0, -2.0)      # przy ławie (panel zamyka się, gdy gracz jest poza jej zasięgiem)
		await get_tree().create_timer(0.5).timeout
		var wui := get_tree().get_first_node_in_group("workshop_ui")
		if wui != null:
			wui.open()
			if "--shotsup" in OS.get_cmdline_user_args():
				wui._set_page(1)                     # --shotsup: zakładka SUPPLIES panelu warsztatu
			for sa in OS.get_cmdline_user_args():
				if sa.begins_with("--shotwssel="):          # --shotwssel=N: wybrany N-ty kafel broni (ława 3D pokazuje tę broń)
					wui._select(int(sa.substr("--shotwssel=".length())))
			for sa in OS.get_cmdline_user_args():
				if sa.begins_with("--shotwsopt="):          # --shotwsopt=N: kursor na N-tej opcji części wybranej broni (domyślnie kafel 0, M-83)
					wui._opt = int(sa.substr("--shotwsopt=".length()))
					wui._refresh()
			if "--shotclean" in OS.get_cmdline_user_args():
				Profile.persist = false              # --shotclean: M-83 w stanie 55 % w trakcie czyszczenia przy stole konserwacji (bez zapisu profilu)
				wui.close()
				var svb := get_tree().get_first_node_in_group("service_bench") as Node2D
				if wp != null and svb != null:
					wp.global_position = svb.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				wui.open("service")
				Profile.cond["m83"] = 55.0
				Profile.worn["m83"] = {"barrel": 35.0, "springs": 30.0}
				wui._opt = 0                         # wiersz czyszczenia (pod nim lufa i sprężyny)
				wui._start_clean(Weapons.M83)
				wui.tick_clean(2.0)
			if "--shotpress" in OS.get_cmdline_user_args():
				wui.close()                          # --shotpress: panel prasy elaboracyjnej z breneką pod kursorem i jedną partią w kolejce (bez zapisu)
				Scrap.persist = false
				var prb := get_tree().get_first_node_in_group("press_bench") as Node2D
				if wp != null and prb != null:
					wp.global_position = prb.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				Scrap.orders = ["ammo_hot762"]
				wui.open("press")
				wui._sup_sel = wui._supply_kinds().find("ammo_slug")
				wui._refresh()
			if "--shotlathe" in OS.get_cmdline_user_args():
				wui.close()                          # --shotlathe: tokarka z LR-7 (schemat soczewki), kursor na niej (bez zapisu)
				Scrap.persist = false
				var ltb := get_tree().get_first_node_in_group("lathe_bench") as Node2D
				if wp != null and ltb != null:
					wp.global_position = ltb.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				Scrap.schematics = {"lr7_lens": true}
				wui.open("lathe")
				wui._select(wui.LIST.find(Weapons.LR7))
				wui._opt = wui._options(Weapons.LR7).find({"slot": "muzzle", "id": "lr7_lens"})
				wui._refresh()
			if "--shotlab" in OS.get_cmdline_user_args():
				wui.close()                          # --shotlab: pracownia z LR-7 (4 próbki w banku, 1 z misji), soczewka pod kursorem (bez zapisu)
				Scrap.persist = false
				var lbb := get_tree().get_first_node_in_group("lab_bench") as Node2D
				if wp != null and lbb != null:
					wp.global_position = lbb.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				Scrap.samples = 4
				Scrap.samples_loot = 1
				wui.open("lab")
				wui._select(wui.LIST.find(Weapons.LR7))
				wui._opt = wui._options(Weapons.LR7).find({"slot": "muzzle", "id": "lr7_lens"})
				wui._refresh()
			if "--shotpyro" in OS.get_cmdline_user_args():
				wui.close()                          # --shotpyro: panel stołu pirotechnicznego z granatem odłamkowym pod kursorem (bez zapisu)
				Scrap.persist = false
				var pyb := get_tree().get_first_node_in_group("pyro_bench") as Node2D
				if wp != null and pyb != null:
					wp.global_position = pyb.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				wui.open("pyro")
				wui._sup_sel = wui._supply_kinds().find("frag")
				wui._refresh()
			if "--shotperks" in OS.get_cmdline_user_args() or "--shotlook" in OS.get_cmdline_user_args():
				wui.close()                          # perki i wygląd są w szafkach osobistych (1.7.349): gracz staje przy nich
				var lks := get_tree().get_first_node_in_group("locker_station") as Node2D
				if wp != null and lks != null:
					wp.global_position = lks.global_position + Vector2(0.0, -2.0)
				await get_tree().create_timer(0.3).timeout
				wui.open("locker")
			if "--shotperks" in OS.get_cmdline_user_args():
				Profile.reset_for_test()             # --shotperks: zakładka PERKS z przykładowym profilem (L4, Smith w slocie 1)
				Profile.add_xp(800, "demo")
				Profile.equip(0, "smith")
				wui._perk_sel = 3
				wui._set_page(2)
			if "--shotlook" in OS.get_cmdline_user_args():
				Profile.reset_for_test()             # --shotlook: zakładka LOOK (poziom 5 — wszystkie stroje odblokowane), wybrana kobieta w stroju Field medic
				Profile.add_xp(800, "demo")
				Profile.set_look(Look.code(1, 2))
				wui._look_sel = 5
				wui._set_page(3)
	if demo:
		RunLog.add("z1_m1", "1.1  MISSING PATROL", 214.0, 0, 1, -1, 86)         # przykładowe wpisy do podglądu ściany wyników
		RunLog.add("z1_m2", "1.2  RADIO SILENCE", 402.0, 2, 1, 1, 148)
		RunLog.add("z1_m3", "1.3  THE NEST", 515.0, 1, 2, -1, 121)
	if depart:
		_hub_set_ready(NoiseMgr.local_id(), true)      # jak [Enter] w kryjówce: gotowość → odliczanie → wyjście z kryjówki w ticku serwera
	if col >= 0:
		var p: Node2D = _players.get_node_or_null("1")
		if p != null:
			var fy := 0.0
			var shot_row0 := 0
			for sa in OS.get_cmdline_user_args():
				if sa.begins_with("--shotrow="):
					shot_row0 = int(sa.substr("--shotrow=".length()))          # piętro zrzutu: pierwsza podłoga od tego wiersza w dół
			for r in range(shot_row0, level._map.size()):
				if level._is_solid(col, r) and not level._is_solid(col, r - 1):
					fy = float(r * 16)
					break
			p.global_position = Vector2(float(col) * 16.0 + 8.0, fy - 2.0)
			p.velocity = Vector2.ZERO
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shothp="):                  # dev: zdrowie gracza 1 na zrzucie (podgląd plakietki życia)
			var hp_p: Node2D = _players.get_node_or_null("1")
			if hp_p != null:
				hp_p.hp = int(sa.substr("--shothp=".length()))
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shotwake="):                 # dev: --shotwake=skoczek — budzi wszystkich wrogów danego rodzaju po 1 s (podgląd zejścia z sufitu)
			for wn in get_tree().get_nodes_in_group("enemies"):
				if String(wn.get("kind")) == sa.substr("--shotwake=".length()):
					get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(wn): wn.call("wake"))
		if sa.begins_with("--shotnest="):                 # dev: --shotnest=death|hit — zdarzenie wszystkich gniazd 1 s po starcie (podgląd klipów)
			for nn in get_tree().get_nodes_in_group("nests"):
				get_tree().create_timer(1.0).timeout.connect(_dev_clip.bind(nn, sa.substr("--shotnest=".length())))
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shotplayer="):               # dev: --shotplayer=hit|down|revive — zdarzenie gracza 1 po 1 s (podgląd animacji postaci 3D)
			get_tree().create_timer(1.0).timeout.connect(_dev_player.bind(sa.substr("--shotplayer=".length())))
	if "--shotpart" in OS.get_cmdline_user_args():
		var pp1: Node2D = _players.get_node_or_null("1")     # dev: --shotpart — części zostawione przez elitę przy graczu 1 (PBS-1 i bęben RPK)
		if pp1 != null:
			level.spawn_item("part", Scrap.part_index("m83_pbs1"), pp1.global_position + Vector2(-22.0, -14.0))
			level.spawn_item("part", Scrap.part_index("m83_drum75"), pp1.global_position + Vector2(24.0, -14.0))
	if "--shotjam" in OS.get_cmdline_user_args():
		var jp1: Node2D = _players.get_node_or_null("1")     # dev: --shotjam — broń gracza 1 brudna (35 %) i zacięta (podgląd HUD, warsztatu, oględzin); profil bez zapisu
		if jp1 != null:
			Profile.persist = false
			for jw in jp1.weapons.loadout:
				Profile.cond[String(Weapons.def(int(jw)).key)] = 35.0
			jp1.weapons.jams[int(jp1.weapon)] = "stovepipe"
			var jwui := get_tree().get_first_node_in_group("workshop_ui")
			if jwui != null and bool(jwui.get("_open")):
				jwui._refresh()
	if "--shotmag" in OS.get_cmdline_user_args():
		var mp1: Node2D = _players.get_node_or_null("1")     # dev: --shotmag — gracz 1 upuszcza magazynek M-83 z 17 nabojami i pusty SPREAD-12 (podgląd)
		if mp1 != null:
			mp1.weapons._spawn_mag(Weapons.M83, 17, 0)
			mp1.weapons._spawn_mag(Weapons.SPREAD12, 0, 0)
	if "--shothot" in OS.get_cmdline_user_args():
		var hp1: Node2D = _players.get_node_or_null("1")     # dev: --shothot — rozgrzana lufa broni gracza 1 (dym i falowanie powietrza nad lufą)
		if hp1 != null:
			hp1.weapons._barrel[int(hp1.weapon)] = 1.0
	if "--shotbrace" in OS.get_cmdline_user_args():
		var bp: Node2D = _players.get_node_or_null("1")      # dev: --shotbrace — skrzynia tuż przed graczem 1: broń oparta, podpórka pod celownikiem
		if bp != null:
			var cr: RigidBody2D = (load("res://scripts/prop.gd") as GDScript).new()
			cr.kind = "crate"
			cr.position = bp.global_position + Vector2(12.5, -1.0)
			level.add_child(cr)
	if flicker:
		Lights.flicker_until_ms = Time.get_ticks_msec() + int(delay * 1000.0) + 3000      # podgląd efektu migotania świateł (dread.gd)
	await get_tree().create_timer(delay).timeout
	var seq_n := 0
	var seq_dt := 0.1
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shotseq="):                 # dev: --shotseq=N:DT zapisuje N klatek co DT s (PLIK_0.png …) zamiast jednej
			var parts := sa.substr("--shotseq=".length()).split(":")
			seq_n = int(parts[0])
			seq_dt = float(parts[1]) if parts.size() > 1 else 0.1
	if seq_n > 0:
		for i in seq_n:
			get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%d.png" % i))
			await get_tree().create_timer(seq_dt).timeout
		print("[SHOT] sekwencja %d klatek: %s" % [seq_n, path])
		Audio.quit_game()
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	Audio.quit_game()

## Dev (--shotplayer): zdarzenia gracza 1 — hit, down, revive, melee / chop (cios maczetą / kilofem), dying (końcówka wykrwawiania), jump (skok), grab (chwycenie przez Pijawkę), reload (przeładowanie), look (zmiana wyglądu).
func _dev_player(what: String) -> void:
	var pl: Node2D = _players.get_node_or_null("1")
	if pl == null:
		return
	match what:
		"hit":
			pl.hp -= 1
			pl.set("_flash", 0.25)
		"down":
			pl.call("_go_down")
		"reload":                                          # przeładowanie aktualnej broni (magazynek opróżniony)
			var wc = pl.weapons
			var gid: int = int(wc.loadout[wc.slot])
			wc.mags[gid] = 0
			wc.try_reload()
		"look":                                            # zmiana wyglądu gracza 1 (warsztat): płeć 1, strój 2 — model 3D musi się wymienić
			pl.set("look", Look.code(1, 2))
		"jump":                                            # skok w miejscu (apeks i lądowanie widać na sekwencji)
			pl.velocity.y = -275.0
		"melee", "chop":                                   # cios maczetą / kilofem, powtarzany co 1,4 s
			for i in 3:
				if not is_instance_valid(pl):
					return
				pl.weapons.melee_id = 11 if what == "chop" else 10
				pl.weapons.try_melee()
				await get_tree().create_timer(1.4).timeout
		"grab":                                            # chwycenie przez Pijawkę (stan `grabbed` na 3 s)
			pl.set("grab_pos", pl.global_position)
			pl.set("grabbed", true)
			await get_tree().create_timer(3.0).timeout
			pl.set("grabbed", false)
		"dying":                                           # powalenie z końcówką wykrwawiania (podgląd drgawek i zapadania)
			pl.call("_go_down")
			pl.set("bleed_left", 1.2)
		"revive":
			pl.call("_go_down")
			await get_tree().create_timer(1.4).timeout
			pl.call("_do_revive")

## Dev (--shotclip): wywołuje zdarzenie wroga, żeby obejrzeć klip modelu 3D: death (śmierć), hit (trafienie), attack (koniec zapowiedzi).
func _dev_clip(en: Node, what: String) -> void:
	if not is_instance_valid(en):
		return
	match what:
		"death":
			if en.has_method("_die"):
				en.call("_die")
			elif en.has_method("_destroy"):
				en.call("_destroy")        # gniazdo
		"hit":
			en.set("_flash", 0.1)
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(en):
				en.set("_flash", 0.0)
		"stun":                                            # oszołomienie Wołka po uderzeniu szarżą (stan `_sp` = 4)
			en.set("_sp", 4)
		"charge":                                          # szarża Wołka (stan `_sp` = 2; AI zamrożone, więc stoi w miejscu)
			en.set("_sp", 2)
		"jump":                                            # skok wroga (poza lotu): wznosi się z prędkością 260 px/s
			en.set_physics_process(true)
			en.velocity.y = -260.0
		"attack":
			en.set("winding", true)
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(en):
				en.set("winding", false)

## Dev (--shotshoot): seria strzałów gracza w prawo co 0,12 s przez `secs` sekund.
func _dev_shoot(p: Node2D, secs: float) -> void:
	var t := 0.0
	while t < secs and is_instance_valid(p):
		if p.weapons != null:
			p.weapons.bot_fire(Vector2(1.0, -0.04).normalized())
		await get_tree().create_timer(0.12).timeout
		t += 0.12

## Symulacja długości walki z Pijawką (--host --mission=z1_b1 --leechsim=CELNOŚĆ,DPS --autoquit=N): nieśmiertelny gracz-przynęta stoi w wodzie przy bossie
## i zadaje DPS × celność tylko wtedy, gdy boss jest wynurzony, oraz w świetle flary (rzucanej co 20 s; liczy się 40%). Czas gry przyspieszony ×4.
## Zwraca czas do śmierci bossa w sekundach gry — to „sufit” dla gracza, który nie ginie i nie marnuje czasu; typowa gra trwa dłużej.
func _leech_sim(acc: float, dps: float) -> void:
	await get_tree().create_timer(1.0).timeout
	Engine.time_scale = 4.0
	var p: Node2D = _players.get_node_or_null("1")
	for pc in _players.get_children():
		if pc.is_bot:
			pc.set_physics_process(false)
			pc.global_position = Vector2(100.0, 400.0)
	var lc: Node2D = get_tree().get_first_node_in_group("boss")
	mission._start_boss()
	await get_tree().create_timer(0.5).timeout
	var t := 0.0
	var surfaced_t := 0.0
	var lit_t := 0.0
	var ambushes := 0
	var prev_mode: int = lc.mode
	var flare_t := 0.0
	var rate := dps * acc
	while lc.state != lc.State.DEAD and t < 900.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		p.hp = 3
		p.dead = false
		p._invuln = 1.0
		if lc.mode == lc.Mode.SUB or lc.mode == lc.Mode.WIND:
			p.global_position = Vector2(clampf(lc.global_position.x + 20.0, lc.pool_x0 + 40.0, lc.pool_x1 - 40.0), lc.surf_y)
			p.velocity = Vector2.ZERO
		flare_t -= dt
		if flare_t <= 0.0:
			flare_t = 20.0
			level.spawn_flare(Vector2(lc.global_position.x + 10.0, lc.surf_y - 30.0), Vector2.ZERO)
		if lc.mode == lc.Mode.UP or lc.mode == lc.Mode.GRAB:
			surfaced_t += dt
			lc.take_hit({"amount": rate * dt, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
		elif lc.revealed:
			lit_t += dt
			lc.take_hit({"amount": rate * dt, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
		if lc.mode == lc.Mode.UP and prev_mode != lc.Mode.UP and prev_mode != lc.Mode.GRAB:
			ambushes += 1
		prev_mode = lc.mode
	Engine.time_scale = 1.0
	print("[LEECH-SIM] celność %.2f, DPS %.0f (%.0f efektywnie): Pijawka %s po %.0f s gry (%.1f min); okna wynurzenia %.0f s (%d), w świetle %.0f s, faza końcowa %d, HP bossa %.0f" % [
		acc, dps, rate, "ginie" if lc.state == lc.State.DEAD else "NIE ginie", t, t / 60.0, surfaced_t, ambushes, lit_t, lc.phase, lc.max_hp])
	Audio.quit_game()

## Czas w bieżącym stanie fali przypływu bossa (test).
func _surge_t_check(b: Node) -> float:
	return float(b._surge_t)

## Test bossa B1 (--host --mission=z1_b1 --leechtest): zanurzona Pijawka dostaje 5% obrażeń, w świetle flary 100%, zasadzka rani gracza
## stojącego w wodzie, a stojący na kładce jest bezpieczny; fazy HP, śmierć → ekstrakcja → sukces; skrzynka z flarami.
func _leech_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[LEECH-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	var bot: Node2D = null
	for pc in _players.get_children():
		if pc.is_bot and not pc.is_queued_for_deletion():
			bot = pc
	if bot != null:
		bot.set_physics_process(false)
		bot.global_position = Vector2(100.0, 400.0)
	var lc: Node2D = get_tree().get_first_node_in_group("boss")
	check.call("start: mapa B1, cel boss, Pijawka śpi (stan %d), basen %.0f–%.0f px" % [lc.state, lc.pool_x0, lc.pool_x1],
		level.map_id == "z1_b1" and mission.kind == "boss" and lc != null and lc.state == lc.State.DORMANT and lc.pool_x1 > lc.pool_x0)
	var surf: float = lc.surf_y
	# stoimy daleko od basenu, więc walka rusza dopiero po czasie / zbliżeniu — wymuszamy start
	mission._start_boss()
	await get_tree().create_timer(0.3).timeout
	check.call("walka: Pijawka obudzona, faza BOSS, HP %.0f (≥ %.0f)" % [lc.hp, lc.BASE_HP], lc.state == lc.State.AWAKE and mission.phase == MISSION_SCRIPT.Phase.BOSS and lc.hp >= lc.BASE_HP)
	var bs: Dictionary = mission.boss_state()
	check.call("dziennik: stan bossa do mission_end %s" % str(bs), bs.get("kind", "") == "leech" and int(bs.get("hp", -1)) == roundi(lc.hp)
		and int(bs.get("max_hp", -1)) == roundi(lc.max_hp) and int(bs.get("phase", 0)) == 1)
	# Trzoski od fazy 1 (1.7.68): po pierwszym odliczeniu pojawiają się z brzegów; potem je usuwamy, żeby nie psuły pomiarów
	lc._minion_t = 0.05
	await get_tree().create_timer(0.6).timeout
	var early_minions := level.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("LeechSpawn") and not n.is_queued_for_deletion())
	check.call("faza 1: Trzoski z brzegów już w fazie 1 (%d, co %.0f s, maks. %d)" % [early_minions.size(), lc.MINION_EVERY[0], lc.MINION_MAX[0]], early_minions.size() >= 2 and lc.MINION_EVERY[0] > 0.0)
	for mn in early_minions:
		mn.queue_free()
	lc._minions.clear()
	lc._minion_t = 99999.0
	# obrażenia: zanurzona w ciemności 5%, w świetle flary 100%
	lc.position.x = 69.0 * 16.0
	lc.mode = lc.Mode.SUB
	lc.revealed = false
	var h0: float = lc.hp
	var r1: Dictionary = lc.take_hit({"amount": 100.0, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
	var dealt_dark: float = h0 - lc.hp
	level.spawn_flare(lc.global_position + Vector2(10.0, -30.0), Vector2.ZERO)
	await get_tree().create_timer(1.2).timeout
	var h1: float = lc.hp
	lc.take_hit({"amount": 100.0, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
	var dealt_lit: float = h1 - lc.hp
	var lit_revealed: bool = lc.revealed
	lc.mode = lc.Mode.UP                                       # wynurzona: pełne obrażenia
	var h2: float = lc.hp
	lc.take_hit({"amount": 100.0, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
	var dealt_up: float = h2 - lc.hp
	lc.mode = lc.Mode.SUB
	check.call("obrażenia: ciemność %.1f (5%%), cień w świetle flary %.1f (40%%), wynurzona %.1f (100%%), cień ujawniony=%s" % [dealt_dark, dealt_lit, dealt_up, str(lit_revealed)],
		is_equal_approx(dealt_dark, 5.0) and is_equal_approx(dealt_lit, 40.0) and is_equal_approx(dealt_up, 100.0) and lit_revealed)
	# zasadzka i chwyt: gracz stoi w wodzie obok Pijawki — zapowiedź, wynurzenie, chwyt
	var ambush := func() -> Dictionary:
		lc.hp = lc.max_hp
		lc.mode = lc.Mode.SUB
		lc._cd = 0.0
		lc._grab_dmg = 0.0
		if p.dead:
			p.dead = false
		p.hp = 3
		p._invuln = 0.0
		lc.position.x = 69.0 * 16.0
		p.global_position = Vector2(lc.global_position.x + 20.0, surf)
		p.velocity = Vector2.ZERO
		var saw_wind := false
		var grabbed_ok := false
		for i in 45:
			await get_tree().create_timer(0.1).timeout
			saw_wind = saw_wind or lc.mode == lc.Mode.WIND
			if lc.mode == lc.Mode.GRAB:
				grabbed_ok = true
				break
		return {"wind": saw_wind, "grab": grabbed_ok}
	var r: Dictionary = await ambush.call()
	var pinned_x: float = p.global_position.x
	await get_tree().create_timer(0.5).timeout
	check.call("zasadzka: zapowiedź=%s, chwyt=%s (ofiara id %d), HP gracza %d, przypięty w miejscu (dx %.1f)" % [str(r["wind"]), str(r["grab"]), lc.grab_victim_id, p.hp, absf(p.global_position.x - pinned_x)],
		bool(r["wind"]) and bool(r["grab"]) and lc.grab_victim_id == p.player_id and p.grabbed and p.hp < 3 and absf(p.global_position.x - pinned_x) < 2.0)
	# QTE: drużyna zadaje 6% maks. HP w oknie → Pijawka puszcza, ofiara żyje
	var hit_before: float = lc.hp
	lc.take_hit({"amount": lc.max_hp * 0.07, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0})
	await get_tree().create_timer(0.4).timeout
	check.call("QTE udane: 7%% HP zadane → Pijawka puściła (tryb %d), gracz wolny=%s i żyje (HP %d)" % [lc.mode, str(not p.grabbed), p.hp], lc.mode == lc.Mode.SUB and not p.grabbed and not p.dead and p.hp > 0 and lc.grab_victim_id == 0)
	# QTE nieudane: bez obrażeń okno mija i ofiara trafia pod wodę (down)
	r = await ambush.call()
	await get_tree().create_timer(lc.GRAB_TIME + 0.8).timeout
	check.call("QTE nieudane: po %.0f s ofiara wciągnięta pod wodę (down=%s), Pijawka wolna (id %d, tryb %d)" % [lc.GRAB_TIME, str(p.dead), lc.grab_victim_id, lc.mode], bool(r["grab"]) and p.dead and not p.grabbed and lc.grab_victim_id == 0 and lc.mode == lc.Mode.SUB)
	# cios chwyconego liczy się podwójnie: 3,5% maks. HP z maczety = 7% → uwolnienie
	p.dead = false
	r = await ambush.call()
	lc.take_hit({"amount": lc.max_hp * 0.035, "pos": lc.global_position, "dir": Vector2.RIGHT, "w": 0, "type": "melee", "shooter": p.player_id})
	await get_tree().create_timer(0.4).timeout
	check.call("QTE: cios chwyconego (maczeta) liczy się podwójnie — uwolniony=%s" % str(not p.grabbed), bool(r["grab"]) and not p.grabbed and lc.mode == lc.Mode.SUB)
	p.dead = false
	p.hp = 3
	# kładka: gracz nad wodą jest poza zasięgiem
	await get_tree().create_timer(2.5).timeout
	p.hp = 3
	p.global_position = Vector2(66.0 * 16.0, 27.0 * 16.0 - 1.0)     # kładka B (rząd 27), cztery kafle nad wodą
	p.velocity = Vector2.ZERO
	lc._cd = 0.0
	await get_tree().create_timer(4.0).timeout
	check.call("wysoka kładka (64 px): gracz nad wodą nietknięty w fazie 1 (HP %d), Pijawka nie wynurza się pod nim (tryb %d)" % [p.hp, lc.mode], p.hp == 3 and lc.mode == lc.Mode.SUB)
	# 1.7.68: niska kładka (32 px nad wodą) i brzeg przy basenie są już w zasięgu zasadzki
	var bitten := func(pos: Vector2) -> bool:
		lc.mode = lc.Mode.SUB
		lc._cd = 0.0
		lc.hp = lc.max_hp
		p.dead = false
		p.hp = 3
		p._invuln = 0.0
		p.grabbed = false
		lc.position.x = clampf(pos.x, lc.pool_x0, lc.pool_x1)
		p.global_position = pos
		p.velocity = Vector2.ZERO
		var hit := false
		for i in 50:
			await get_tree().create_timer(0.1).timeout
			if p.hp < 3 or p.dead:
				hit = true
				break
		lc._release(true) if lc.mode == lc.Mode.GRAB else null
		lc.mode = lc.Mode.SUB
		return hit
	var low_hit: bool = await bitten.call(Vector2(69.0 * 16.0, surf - 32.0))
	await get_tree().create_timer(1.5).timeout
	var shore_hit: bool = await bitten.call(Vector2(lc.pool_x0 - 30.0, surf))
	await get_tree().create_timer(1.5).timeout
	var far_shore: bool = await bitten.call(Vector2(lc.pool_x0 - 120.0, surf))
	check.call("zasięg zasadzki: niska kładka (32 px) ugryziona=%s, brzeg tuż przy basenie ugryziony=%s, dalszy brzeg (120 px) bezpieczny w fazie 1=%s" % [str(low_hit), str(shore_hit), str(not far_shore)], low_hit and shore_hit and not far_shore)
	# odpoczynek od brzegu (opinia testera 2026-10-29): po zasadzce z brzegu Pijawka nie parkuje przy nim, tylko odpływa na środek
	lc._shore_rest = 0.0
	await get_tree().create_timer(1.5).timeout
	var first_bite: bool = await bitten.call(Vector2(lc.pool_x0 - 30.0, surf))
	await get_tree().create_timer(float(lc.UP_TIME[0]) + 0.2).timeout
	p.hp = 3
	p.dead = false
	p._invuln = 0.0
	p.global_position = Vector2(lc.pool_x0 - 30.0, surf)
	p.velocity = Vector2.ZERO
	lc._cd = 0.0
	await get_tree().create_timer(2.0).timeout
	var mid: float = 0.5 * (lc.pool_x0 + lc.pool_x1)
	check.call("po zasadzce z brzegu odpoczynek: gracz na brzegu nietknięty (HP %d), Pijawka odpływa ku środkowi (%.0f px od brzegu, środek %.0f px)" % [p.hp, lc.global_position.x - lc.pool_x0, mid - lc.pool_x0],
		first_bite and p.hp == 3 and not p.dead and lc.global_position.x - lc.pool_x0 > 40.0)
	lc._shore_rest = 0.0
	p.hp = 3
	p.dead = false
	p.grabbed = false
	lc.grab_victim_id = 0
	lc._grab_victim = null
	# fala przypływu dopiero od fazy 2: w fazie 1 mimo „gotowego” odliczania stan zostaje idle
	lc._surge_cd = 0.0
	await get_tree().create_timer(1.0).timeout
	check.call("fala przypływu: w fazie 1 jej nie ma (stan %s)" % lc.surge_state, lc.surge_state == "idle" and lc.phase == 1)
	lc._surge_cd = 99999.0
	# regeneracja w ciemności: bez flar zanurzona Pijawka leczy ~1,5% maks. HP/s (do progu fazy), w świetle nie
	for fl in get_tree().get_nodes_in_group("flares"):
		fl.queue_free()
	await get_tree().create_timer(0.3).timeout
	lc.mode = lc.Mode.SUB
	lc._cd = 99.0
	lc.revealed = false
	p.global_position = Vector2(100.0, 400.0)
	lc.hp = lc.max_hp * 0.5
	var reg0: float = lc.hp
	await get_tree().create_timer(3.0).timeout
	var reg_gain: float = lc.hp - reg0
	check.call("regeneracja: zanurzona w ciemności +%.0f HP w 3 s (≈ %.0f oczekiwane)" % [reg_gain, lc.max_hp * lc.REGEN_FRAC * 3.0], reg_gain > lc.max_hp * lc.REGEN_FRAC * 3.0 * 0.6 and reg_gain < lc.max_hp * lc.REGEN_FRAC * 3.0 * 1.4)
	# flara w wodzie gaśnie po 8 s, na brzegu trwa dalej
	level.spawn_flare(Vector2(60.0 * 16.0, surf - 30.0), Vector2.ZERO)
	level.spawn_flare(Vector2(8.0 * 16.0, surf - 30.0), Vector2.ZERO)
	await get_tree().create_timer(1.5).timeout
	var flares_now := get_tree().get_nodes_in_group("flares")
	var water_life := -1.0
	var shore_life := -1.0
	for fl in flares_now:
		if fl.global_position.x > lc.pool_x0:
			water_life = fl.life
		else:
			shore_life = fl.life
	check.call("flara w wodzie dopala się ≤ 8 s (zostało %.1f), na brzegu jak dawniej (%.1f)" % [water_life, shore_life], water_life > 0.0 and water_life <= 7.0 and shore_life > 20.0)
	for fl in get_tree().get_nodes_in_group("flares"):
		fl.queue_free()
	lc.hp = lc.max_hp
	# fazy HP: faza 2 dosyła Trzoski z brzegów, faza 3 — krzyk (Uwaga na maksimum), kolejne Trzoski i podwójna zasadzka
	var spawns_now := func() -> Array: return level.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("LeechSpawn") and not n.is_queued_for_deletion())
	lc._hit(lc.max_hp * 0.40, true)
	var ph2: int = lc.phase
	await get_tree().create_timer(0.5).timeout
	var minions2: int = spawns_now.call().size()
	for mn in spawns_now.call():
		mn.set_physics_process(false)                      # test: Trzoski nie biegają (nie przeszkadzają w pomiarach)
		mn.set_process(false)
	NoiseMgr.level = 10.0
	lc._hit(lc.max_hp * 0.30, true)
	var ph3: int = lc.phase
	await get_tree().create_timer(0.5).timeout
	var minions3: int = spawns_now.call().size()
	check.call("fazy: po -40%% HP faza %d (Trzoski z brzegów: %d), po -70%% HP faza %d (krzyk: Uwaga %.0f, Trzoski łącznie %d)" % [ph2, minions2, ph3, NoiseMgr.level, minions3],
		ph2 == 2 and minions2 >= 2 and ph3 == 3 and NoiseMgr.level >= NoiseMgr.MAX_LEVEL - 1.0 and minions3 >= minions2 + 3)
	for mn in spawns_now.call():
		mn.set_physics_process(false)
		mn.set_process(false)
	lc._surge_cd = 99999.0                                  # fala przypływu badana osobno niżej
	# plucie kwasem (faza 2+): gracz na wysokiej kładce, poza zasięgiem zasadzki, dostaje kwasem
	p.dead = false
	p.hp = 3
	p._invuln = 0.0
	p.grabbed = false
	lc.mode = lc.Mode.SUB
	lc._cd = 0.0
	lc.hp = lc.max_hp * 0.30
	lc.position.x = 69.0 * 16.0
	p.global_position = Vector2(66.0 * 16.0, 27.0 * 16.0 - 1.0)
	p.velocity = Vector2.ZERO
	var saw_acid := false
	var saw_spit_wind := false
	for i in 70:
		await get_tree().create_timer(0.1).timeout
		saw_acid = saw_acid or get_tree().get_nodes_in_group("acid").size() > 0
		saw_spit_wind = saw_spit_wind or (lc.mode == lc.Mode.WIND and lc._spit_pending)
		if p.hp < 3:
			break
	check.call("plucie kwasem: gracz na wysokiej kładce w fazie %d — zapowiedź=%s, pocisk=%s, trafiony (HP %d)" % [lc.phase, str(saw_spit_wind), str(saw_acid), p.hp], saw_spit_wind and saw_acid and p.hp < 3)
	await get_tree().create_timer(1.5).timeout
	# furia: faza 3 poniżej 15% HP
	lc.hp = lc.max_hp * 0.10
	lc.mode = lc.Mode.SUB
	await get_tree().create_timer(0.4).timeout
	check.call("furia: faza 3 poniżej %.0f%% HP (HP %.0f) — aktywna=%s" % [lc.FURY_HP_FRAC * 100.0, lc.hp, str(lc._fury_on)], lc._fury() and lc._fury_on)
	lc.hp = lc.max_hp * 0.30
	lc._fury_on = false
	p.dead = false
	p.hp = 3
	for ac in get_tree().get_nodes_in_group("acid"):
		ac.queue_free()
	# faza 3: podwójna zasadzka — drugi punkt zapowiedzi (kręgi) w innym miejscu basenu
	lc.mode = lc.Mode.SUB
	lc._cd = 0.0
	lc.position.x = 69.0 * 16.0
	p.dead = false
	p.hp = 3
	p._invuln = 0.0
	p.global_position = Vector2(lc.global_position.x + 20.0, surf)
	p.velocity = Vector2.ZERO
	var saw_second := -1.0
	for i in 40:
		await get_tree().create_timer(0.1).timeout
		if lc.mode == lc.Mode.WIND and lc.second_x >= 0.0:
			saw_second = lc.second_x
			break
	check.call("faza 3: podwójna zasadzka — drugi punkt zapowiedzi x=%.0f (pierwszy %.0f)" % [saw_second, lc.global_position.x], saw_second >= 0.0 and absf(saw_second - lc.global_position.x) >= lc.SECOND_STRIKE_MIN_DX - 1.0)
	await get_tree().create_timer(1.2).timeout
	p.dead = false
	p.hp = 3
	lc.mode = lc.Mode.SUB
	lc._grab_victim = null
	lc.grab_victim_id = 0
	p.grabbed = false
	# fala przypływu (faza 3): zapowiedź → fala; poniżej 48 px nad dnem basenu trafia i gasi flary, wysoka kładka jest bezpieczna
	var surge_round := func(pos: Vector2) -> Dictionary:
		p.dead = false
		p.hp = 3
		p._invuln = 0.0
		p.grabbed = false
		lc.mode = lc.Mode.SUB
		lc._cd = 99.0
		lc.hp = lc.max_hp * 0.30
		p.global_position = pos
		p.velocity = Vector2.ZERO
		level.spawn_flare(pos + Vector2(10.0, -20.0), Vector2.ZERO)
		lc._surge_cd = 0.05
		var saw_warn := false
		var peak := 0.0
		for i in 90:
			await get_tree().create_timer(0.1).timeout
			saw_warn = saw_warn or lc.surge_state == "warn"
			if lc.surge_state == "on":
				peak = maxf(peak, lc.surge_level())
				if _surge_t_check(lc) > 1.0:
					break
		var hp_now: int = p.hp
		var flares_alive := get_tree().get_nodes_in_group("flares").filter(func(f: Node) -> bool: return is_instance_valid(f) and not f.is_queued_for_deletion() and f.life > 0.5).size()
		for i in 70:                                         # czekamy, aż woda opadnie (stan idle)
			await get_tree().create_timer(0.1).timeout
			if lc.surge_state == "idle":
				break
		for f in get_tree().get_nodes_in_group("flares"):
			f.queue_free()
		return {"warn": saw_warn, "hp": hp_now, "level": peak, "flares": flares_alive}
	var low_round: Dictionary = await surge_round.call(Vector2(51.0 * 16.0, 29.0 * 16.0 - 1.0))
	var high_round: Dictionary = await surge_round.call(Vector2(60.0 * 16.0, 27.0 * 16.0 - 1.0))
	check.call("fala przypływu: zapowiedź=%s, woda %.2f; niska kładka — HP %d, flary %d; wysoka kładka — HP %d, flary %d" % [str(low_round["warn"]), float(low_round["level"]), int(low_round["hp"]), int(low_round["flares"]), int(high_round["hp"]), int(high_round["flares"])],
		bool(low_round["warn"]) and float(low_round["level"]) > 0.9 and int(low_round["hp"]) < 3 and int(low_round["flares"]) == 0 and int(high_round["hp"]) == 3 and int(high_round["flares"]) == 1)
	lc._surge_cd = 99999.0
	p.hp = 3
	p.dead = false
	# skalowanie przez Difficulty: EASY < NORMAL < HARD (HP, regeneracja, Trzoski, przerwy, fala)
	var dstats := {}
	for lv in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		Difficulty.set_level(lv)
		dstats[lv] = {"hp": lc.hp_for(1), "hp2": lc.hp_for(2), "regen": Difficulty.m("boss_regen"), "adds": lc._minion_cap(2), "tide": Difficulty.m("boss_tide"), "cd": lc._dmul(), "every": lc._minion_every(2)}
	Difficulty.set_level(Difficulty.Level.NORMAL)
	var de: Dictionary = dstats[Difficulty.Level.EASY]
	var dn: Dictionary = dstats[Difficulty.Level.NORMAL]
	var dh: Dictionary = dstats[Difficulty.Level.HARD]
	check.call("poziomy trudności: HP %.0f / %.0f / %.0f (EASY/NORMAL/HARD, z 2 ludźmi %.0f / %.0f / %.0f), Trzoski maks. %d / %d / %d, przerwy ×%.2f / ×%.2f / ×%.2f" % [de["hp"], dn["hp"], dh["hp"], de["hp2"], dn["hp2"], dh["hp2"], de["adds"], dn["adds"], dh["adds"], de["cd"], dn["cd"], dh["cd"]],
		float(de["hp"]) < float(dn["hp"]) and float(dn["hp"]) < float(dh["hp"]) and absf(float(dn["hp"]) - lc.BASE_HP) < 0.5 and float(dh["hp"]) >= lc.BASE_HP * 1.3
		and float(de["regen"]) < float(dn["regen"]) and float(dn["regen"]) < float(dh["regen"])
		and int(de["adds"]) < int(dn["adds"]) and int(dn["adds"]) < int(dh["adds"])
		and float(de["tide"]) > float(dn["tide"]) and float(dn["tide"]) > float(dh["tide"])
		and float(de["cd"]) > float(dn["cd"]) and float(dn["cd"]) > float(dh["cd"])
		and float(dh["every"]) < float(dn["every"]) and float(dn["every"]) < float(de["every"]))
	# skrzynka z flarami
	NoiseMgr.flares = 1
	var boxes := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "flares")
	var box_ok := false
	if not boxes.is_empty():
		p.global_position = (boxes[0] as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
		box_ok = NoiseMgr.flares == 3
	check.call("skrzynki z flarami: %d na mapie, podniesienie dodaje 2 (flary %d)" % [boxes.size(), NoiseMgr.flares], boxes.size() >= 3 and box_ok)
	# śmierć → ekstrakcja → sukces
	lc._hit(lc.max_hp, true)
	await get_tree().create_timer(0.5).timeout
	check.call("śmierć Pijawki → ekstrakcja (stan %d, faza misji %d), Trzoski bossa padły (żywych %d)" % [lc.state, mission.phase, spawns_now.call().filter(func(n: Node) -> bool: return n.alive).size()],
		lc.state == lc.State.DEAD and mission.phase == MISSION_SCRIPT.Phase.EXTRACT and spawns_now.call().filter(func(n: Node) -> bool: return n.alive).is_empty())
	p.global_position = mission.exit_pos + Vector2(0, -2)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ekstrakcja → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	print("[LEECH-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test misji 1.1 (--host --mission=z1_m1 --tagtest): sześć nieśmiertelników, ekstrakcja, wipe (nieśmiertelniki wracają),
## sukces i złom. Wrogowie są zamrożeni, żeby test był powtarzalny.
func _tag_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[TAG-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)
	var tags_now := func() -> Array: return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "tag" and not n.is_queued_for_deletion())
	var brief: Dictionary = level.briefing("z1_m1")
	var counts: Dictionary = brief["counts"]
	check.call("start: mapa 1.1, cel tags, 6 nieśmiertelników (cel %d, na ziemi %d)" % [mission.goal_total, tags_now.call().size()],
		level.map_id == "z1_m1" and mission.kind == "tags" and mission.goal_total == 6 and tags_now.call().size() == 6 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	check.call("odprawa: tytuł, 6 nieśmiertelników, Trzoski %d, Wołki %d, bez Stalkera i bossa" % [int(counts.get("trzosek", 0)), int(counts.get("wolek", 0))],
		String(brief["title"]) != "" and int(brief["tags"]) == 6 and int(counts.get("trzosek", 0)) >= 8 and int(counts.get("wolek", 0)) >= 2 and not bool(brief["stalker"]) and not bool(brief["boss"]))
	var gallery: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return e is CharacterBody2D and e.global_position.y > 37.0 * 16.0)
	var scrap_caches := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "scrap")
	var gallery_nav: Array = level.nav.find_path(Vector2(274.0 * 16.0 + 8.0, 34.0 * 16.0), Vector2(253.0 * 16.0 + 8.0, 43.0 * 16.0))
	check.call("podziemia: dolna galeria (wrogów %d, skrytek złomu na mapie %d), droga z sali szybem serwisowym (%d węzłów)" % [gallery.size(), scrap_caches.size(), gallery_nav.size()],
		gallery.size() >= 7 and scrap_caches.size() >= 5 and not gallery_nav.is_empty())
	# przedmioty nie wpadają w ściany: podskok w stronę skały zatrzymuje się przed nią, a przedmiot zaczęty w skale jest wypychany
	level.spawn_item("health", 0, Vector2(44.0, 22.0 * 16.0 - 10.0))
	var wall_item := level.get_node_or_null("Item%d" % level._pickup_serial)
	if wall_item != null:
		wall_item._vel = Vector2(-600.0, -120.0)
	level.spawn_item("health", 0, Vector2(16.0, 22.0 * 16.0))
	var stuck_item := level.get_node_or_null("Item%d" % level._pickup_serial)
	await get_tree().create_timer(1.5).timeout
	var xs_ok: bool = wall_item != null and stuck_item != null and wall_item.global_position.x >= 30.0 and stuck_item.global_position.x >= 30.0 and wall_item._landed and stuck_item._landed
	check.call("przedmioty a ściany: podskok w skałę zatrzymany (x %.0f), przedmiot zaczęty w skale wypchnięty (x %.0f)" % [wall_item.global_position.x if wall_item != null else -1.0, stuck_item.global_position.x if stuck_item != null else -1.0], xs_ok)
	var order: Array = tags_now.call()
	order.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
	var positions: Array = order.map(func(n: Node) -> Vector2: return n.global_position)
	# pierwszy nieśmiertelnik: licznik spada, misja trwa
	p.global_position = positions[0] + Vector2(0, -4)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.8).timeout
	check.call("nieśmiertelnik 1: zostało %d / %d, faza %d" % [mission.goal_left, mission.goal_total, mission.phase], mission.goal_left == 5 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE and tags_now.call().size() == 5)
	# wipe: misja wraca na start, nieśmiertelniki wracają
	_restart_mission(false)
	await get_tree().create_timer(0.8).timeout
	check.call("wipe: nieśmiertelniki wróciły (%d na ziemi, cel %d/%d, próba %d)" % [tags_now.call().size(), mission.goal_left, mission.goal_total, mission.attempts],
		tags_now.call().size() == 6 and mission.goal_left == 6 and mission.attempts == 2 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	# cel poboczny: dwie ukryte skrytki (na półkach poza główną trasą), każda wpada do łupu i zalicza licznik
	var stash_nodes := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "stash")
	check.call("skrytki: %d na mapie, cel poboczny 0 / %d, odprawa liczy %d" % [stash_nodes.size(), mission.stash_total, int(brief.get("stashes", 0))], stash_nodes.size() == 2 and mission.stash_total == 2 and int(brief.get("stashes", 0)) == 2 and mission.stashes_found == 0)
	var loot_before := Scrap.loot
	for sn in stash_nodes:
		p.global_position = (sn as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
	check.call("skrytki zebrane: %d / %d, łup +%d, cel poboczny zaliczony=%s" % [mission.stashes_found, mission.stash_total, Scrap.loot - loot_before, str(mission.side_done())],
		mission.stashes_found == 2 and Scrap.loot - loot_before == 2 * Scrap.STASH_VALUE and mission.side_done())
	for i in 6:
		var near: Array = tags_now.call()
		near.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
		p.global_position = (near[0] as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
	check.call("6 nieśmiertelników → EXTRACT (zostało %d, faza %d), wyjście przy starcie (x=%.0f)" % [mission.goal_left, mission.phase, mission.exit_pos.x],
		mission.goal_left == 0 and mission.phase == MISSION_SCRIPT.Phase.EXTRACT and mission.exit_pos.x < 400.0)
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ekstrakcja → SUCCESS, złom: łup skrytek + bonus misji + bonus celu pobocznego (%d)" % Scrap.last_gain,
		mission.phase == MISSION_SCRIPT.Phase.SUCCESS and Scrap.last_gain >= 2 * Scrap.STASH_VALUE + Scrap.BONUS_CLEAR + Scrap.BONUS_SIDE)
	check.call("dziennik: cel poboczny 1.1 zaliczony (side=%s)" % str(RunLog.entries.back()["stealth"]), int(RunLog.entries.back()["stealth"]) == 1)
	check.call("dziennik misji: wpis 1.1", not RunLog.entries.is_empty() and String(RunLog.entries.back()["id"]) == "z1_m1")
	_continue_after_result()
	await get_tree().create_timer(0.6).timeout
	check.call("[Enter] po 1.1 → kryjówka, następna 1.2 (po hubie: %s)" % after_hub, level.map_id == "z1_hub" and after_hub == "z1_m2")
	_depart_hub()
	await get_tree().create_timer(0.6).timeout
	check.call("wyjście z kryjówki → 1.2 (generatory)", level.map_id == "z1_m2" and mission.kind == "generators" and mission.goal_total == 4)
	print("[TAG-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test przechodzącego Stalkera misji 1.1 (--host --mission=z1_m1 --passtest, MAPS_PLAN.md M1b): czeka poza mapą, przed pierwszym nieśmiertelnikiem
## nie wychodzi, potem przy Uwadze ≥ 80 (HARD: 95) wychodzi za plecami drużyny poza kadrem, idzie na hałas, po czasie się wycofuje i znika; przerwa i ponowne uzbrojenie dopiero po spadku
## Uwagi; wipe go resetuje; poza fazą celu nie wychodzi; odprawa go nie zapowiada.
func _pass_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[PASS-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	const HUNT := 1        # stalker.gd Pass.HUNT
	const LEAVE := 2       # stalker.gd Pass.LEAVE
	var st: Node2D = level.get_node_or_null("Stalker")
	check.call("Stalker w trybie przechodzącym czeka poza mapą (niewidoczny, uśpiony)", st != null and st.pass_mode and not st.awake and not st.visible)
	for e in get_tree().get_nodes_in_group("enemies"):          # sam Stalker: zwykli wrogowie budziliby się od hałasu testu
		if e.get("kind") != null:
			e.queue_free()
	var p: Node2D = _players.get_node_or_null("1")
	p.global_position = Vector2(60.0 * 16.0 + 8.0, 23.0 * 16.0)      # polana (nieśmiertelnik 1)
	p.velocity = Vector2.ZERO
	var shout := func(level_now: float) -> void:
		NoiseMgr.level = level_now
		NoiseMgr.add_noise(0.6, p.global_position)
	await get_tree().create_timer(0.5).timeout
	shout.call(70.0)
	await get_tree().create_timer(0.4).timeout
	check.call("Uwaga 70 (próg 80): nie wychodzi", not st.awake)
	shout.call(92.0)
	await get_tree().create_timer(0.4).timeout
	check.call("Uwaga 92 przed pierwszym nieśmiertelnikiem: nie wychodzi", not st.awake)
	mission.on_tag_taken(p, p.global_position)                    # pierwszy nieśmiertelnik (after_goal = 1)
	NoiseMgr.level = 50.0
	await get_tree().create_timer(0.3).timeout
	shout.call(92.0)
	await get_tree().create_timer(0.3).timeout
	var dx: float = st.global_position.x - p.global_position.x
	var dy: float = st.global_position.y - p.global_position.y
	check.call("Uwaga 92: wychodzi za plecami drużyny, poza kadrem (dx %.0f, dy %.0f)" % [dx, dy],
		st.awake and st.visible and int(st.pass_state) == HUNT and dx <= -380.0 and dx >= -640.0 and absf(dy) <= 96.0)
	var d0: float = st.global_position.distance_to(p.global_position)
	for i in 4:
		shout.call(92.0)
		await get_tree().create_timer(0.5).timeout
	var d1: float = st.global_position.distance_to(p.global_position)
	check.call("idzie na hałas (%.0f → %.0f px)" % [d0, d1], d1 < d0 - 60.0)
	st._pass_t = 0.05
	await get_tree().create_timer(0.3).timeout
	check.call("po czasie polowania wycofuje się tam, skąd wyszedł", int(st.pass_state) == LEAVE and st.target_pos == st._pass_from)
	st._pass_t = 0.05
	await get_tree().create_timer(0.3).timeout
	check.call("znika: poza mapą, niewidoczny, przerwa %.0f s" % st._pass_cd,
		not st.awake and not st.visible and int(st.pass_state) == 0 and st._pass_cd > 80.0 and st.global_position == st._home)
	shout.call(95.0)
	await get_tree().create_timer(0.4).timeout
	check.call("w trakcie przerwy nie wychodzi", not st.awake)
	st._pass_cd = 0.0
	shout.call(95.0)
	await get_tree().create_timer(0.4).timeout
	check.call("po przerwie, ale bez spadku Uwagi poniżej progu: nie wychodzi", not st.awake)
	NoiseMgr.level = 50.0
	await get_tree().create_timer(0.3).timeout
	shout.call(90.0)
	await get_tree().create_timer(0.4).timeout
	check.call("spadek Uwagi i nowy skok: wychodzi znowu", st.awake and int(st.pass_state) == HUNT)
	_restart_mission(false)
	await get_tree().create_timer(0.8).timeout
	st = level.get_node_or_null("Stalker")
	check.call("wipe: znów czeka poza mapą", st != null and not st.awake and int(st.pass_state) == 0 and st._pass_cd == 0.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("kind") != null:
			e.queue_free()
	# HARD: wyższy próg (noise_hard 95), bo hałas rośnie tam o 25% szybciej
	var diff_before: int = Difficulty.level
	Difficulty.level = Difficulty.Level.HARD
	p.global_position = Vector2(60.0 * 16.0 + 8.0, 23.0 * 16.0)
	mission.on_tag_taken(p, p.global_position)
	NoiseMgr.level = 50.0
	await get_tree().create_timer(0.3).timeout
	shout.call(92.0)
	await get_tree().create_timer(0.4).timeout
	check.call("HARD, Uwaga 92 (próg %.0f): nie wychodzi" % st.pass_noise(), not st.awake and st.pass_noise() == 95.0)
	shout.call(97.0)
	await get_tree().create_timer(0.4).timeout
	check.call("HARD, Uwaga 97: wychodzi", st.awake)
	Difficulty.level = diff_before
	st.reset_enemy()
	mission.phase = MISSION_SCRIPT.Phase.EXTRACT                 # 1.1 od 1.7.283: powrót przez obudzony las — wychodzi też w ewakuacji
	mission.exit_pos = level.exits[0]                             # wyjście przy starcie (na zachód od gracza) — „za plecami” to wschód
	p.global_position = Vector2(60.0 * 16.0 + 8.0, 23.0 * 16.0)
	mission.on_tag_taken(p, p.global_position)
	NoiseMgr.level = 50.0
	await get_tree().create_timer(0.3).timeout
	shout.call(95.0)
	await get_tree().create_timer(0.4).timeout
	var ev_dx: float = st.global_position.x - p.global_position.x
	check.call("ewakuacja (extract w STALKER_PASS): wychodzi za plecami względem wyjścia (wyjście x %.0f, gracz x %.0f, Stalker dx %.0f)" % [mission.exit_pos.x, p.global_position.x, ev_dx],
		st.awake and signf(ev_dx) == -signf(mission.exit_pos.x - p.global_position.x) and absf(ev_dx) >= 380.0)
	st.reset_enemy()
	mission.phase = MISSION_SCRIPT.Phase.SUCCESS
	NoiseMgr.level = 50.0
	await get_tree().create_timer(0.3).timeout
	shout.call(95.0)
	await get_tree().create_timer(0.4).timeout
	check.call("po sukcesie nie wychodzi", not st.awake)
	var brief: Dictionary = level.briefing("z1_m1")
	check.call("odprawa go nie zapowiada (ostrzega alert hałasu)", not bool(brief["stalker"]))
	print("[PASS-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test samouczka ciszy misji 1.1 (--host --mission=z1_m1 --sneaktest): Trzosek śpiący na półce 4 kafle nad ścieżką nie budzi się
## od kucającego gracza pod nim, ale budzi się od wyprostowanego; podpowiedzi quiet i light łapią swoje warunki.
## Wrogowie działają normalnie (nie są zamrożeni).
func _sneak_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[SNEAK-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	# obóz (MAPS_PLAN.md M1a): wataha śpi w niecce 5 kafli pod zerwanym mostem — kucający na moście jej nie budzi, wyprostowany budzi
	# boty stoją na starcie: idąc za graczem przez nieckę, budziłyby watahę, zanim test zacznie
	var bots: Array = _players.get_children().filter(func(b: Node) -> bool: return b.is_bot)
	for b in bots:
		b.set_physics_process(false)
	var camp: Array = get_tree().get_nodes_in_group("enemies").filter(func(t: Node) -> bool: return t.get("kind") == "trzosek" and t.global_position.x > 77.0 * 16.0 and t.global_position.x < 141.0 * 16.0)
	camp.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
	check.call("obóz: wataha w niecce (%d), śpi" % camp.size(), camp.size() == 5 and camp.all(func(t: Node) -> bool: return t.active == false))
	var under: Node2D = camp[3]                                   # pod wschodnim mostem, dwa kafle od nieśmiertelnika (droga do niego prowadzi nad camp[4])
	Input.action_press("crouch")
	p.global_position = Vector2(126.0 * 16.0 + 8.0, 18.0 * 16.0)  # płaskowyż za obozem (lita ziemia), ponad 90 px od śpiących
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	Input.action_press("move_left")                               # na kucaka po moście nad watahą (jak gracz, bez teleportu)
	for i in 80:
		if p.global_position.x <= under.global_position.x:
			break
		await get_tree().create_timer(0.05).timeout
	Input.action_release("move_left")
	await get_tree().create_timer(1.0).timeout
	check.call("obóz: kucający na moście nad watahą (dy %.0f px, crouching=%s): śpią" % [under.global_position.y - p.global_position.y, str(p.crouching)],
		p.crouching and camp.all(func(t: Node) -> bool: return t.active == false))
	Input.action_release("crouch")
	await get_tree().create_timer(1.2).timeout
	check.call("obóz: ten sam gracz wyprostowany budzi watahę", under.active == true)
	for t in camp:                                                # obudzona wataha nie goni gracza do jaskini (następny krok testu)
		t.set_process(false)
		t.set_physics_process(false)
	for b in bots:
		b.set_physics_process(true)
	# bród (MAPS_PLAN.md §1.4 W3): Wołek na skarpie 4 kafle nad błotem — na kucaka pod nim śpi, wyprostowany go budzi
	for b in bots:
		b.set_physics_process(false)
	var bank: Array = get_tree().get_nodes_in_group("enemies").filter(func(t: Node) -> bool: return t.get("kind") == "wolek" and t.global_position.x < 40.0 * 16.0)
	check.call("bród: Wołek na skarpie (%d), śpi" % bank.size(), bank.size() == 1 and bank[0].active == false)
	var wk: Node2D = bank[0]
	Input.action_press("crouch")
	p.global_position = Vector2(26.0 * 16.0 + 8.0, 23.0 * 16.0)       # płycizna, ponad 70 px od niego
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	Input.action_press("move_right")
	for i in 120:
		if p.global_position.x >= wk.global_position.x:
			break
		await get_tree().create_timer(0.05).timeout
	Input.action_release("move_right")
	await get_tree().create_timer(0.8).timeout
	check.call("bród: kucający w błocie pod Wołkiem (dy %.0f px, x %.0f / %.0f): śpi" % [p.global_position.y - wk.global_position.y, p.global_position.x, wk.global_position.x],
		p.crouching and p.global_position.x >= wk.global_position.x - 4.0 and wk.active == false)
	Input.action_release("crouch")
	await get_tree().create_timer(1.0).timeout
	check.call("bród: wyprostowany pod skarpą budzi Wołka", wk.active == true)
	wk.set_process(false)
	wk.set_physics_process(false)
	for b in bots:
		b.set_physics_process(true)
	var ledge: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return e.get("kind") == "trzosek" and e.global_position.x > 2424.0 and e.global_position.x < 2724.0)
	ledge.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
	check.call("półki: śpiący Trzosek na półce (%d), nieaktywny" % ledge.size(), ledge.size() >= 1 and ledge[0].active == false)
	var e: Node2D = ledge[0]
	var floor_y: float = e.global_position.y + 64.0
	Input.action_press("crouch")
	p.global_position = Vector2(e.global_position.x - 150.0, floor_y)      # najpierw z daleka: kucanie wymaga stania na podłodze
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	p.global_position = Vector2(e.global_position.x, floor_y)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(1.5).timeout
	check.call("kucający gracz pod półką (dy 64 px, crouching=%s): wróg śpi" % str(p.crouching), p.crouching and e.active == false)
	Input.action_release("crouch")
	await get_tree().create_timer(1.2).timeout
	check.call("ten sam gracz wyprostowany: wróg się budzi", e.active == true)
	# podpowiedzi
	Settings.seen_tips.clear()
	var hh := Hints.new()
	NoiseMgr.level = 30.0
	for en in get_tree().get_nodes_in_group("enemies"):
		if en.get("alive") == true and en.get("active") == true:
			en.set_process(false)
			en.set_physics_process(false)
			en.active = false
	p.global_position = Vector2(300.0, floor_y - 2.0)
	hh._collect(p)
	check.call("podpowiedź quiet: Uwaga 30, nic nie goni", hh._queued.has("quiet"))
	p.global_position = Vector2(4028.0, 33.0 * 16.0)
	p.flashlight = false
	hh._collect(p)
	check.call("podpowiedź light: gracz w podziemiach bez latarki", hh._queued.has("light"))
	var hc := Hints.new()                                         # obóz: podpowiedź cichej drogi tylko na podejściu, póki wataha śpi
	p.global_position = Vector2(60.0 * 16.0 + 8.0, 23.0 * 16.0)
	hc._collect(p)
	var camp_far: bool = hc._queued.has("camp")
	p.global_position = Vector2(90.0 * 16.0 + 8.0, 23.0 * 16.0)
	hc._collect(p)
	check.call("podpowiedź camp: na podejściu do obozu tak, na polanie nie (strefa %s)" % str(level.hint_zones.get("camp")),
		hc._queued.has("camp") and not camp_far)
	var hf := Hints.new()                                         # bród: porada o wodzie i błocie przy płyciźnie
	p.global_position = Vector2(20.0 * 16.0 + 8.0, 23.0 * 16.0)
	NoiseMgr.level = 20.0
	hf._collect(p)
	check.call("podpowiedź ford: przy płyciźnie (strefa %s)" % str(level.hint_zones.get("ford")), hf._queued.has("ford"))
	var hm := Hints.new()                                         # strażnica: lekcja flary pod wieżą, póki ćmy wiszą pod dachem
	p.global_position = Vector2(205.0 * 16.0 + 8.0, 23.0 * 16.0)
	hm._collect(p)
	check.call("podpowiedź moths: pod strażnicą (strefa %s)" % str(level.hint_zones.get("moths")), hm._queued.has("moths"))
	print("[SNEAK-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test finału misji 1.1 (--host --mission=z1_m1 --finaletest): po ostatnim nieśmiertelniku wstrząs, zawał rampy (kafle zamieniają się
## w skałę, graf nawigacji traci drogę powrotną, uwięziony gracz ląduje za skałą), wyjście po drugiej stronie, sukces, reset po restarcie.
func _finale_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[FINALE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)
	check.call("dane finału w mapie 1.1: obszar zawału (%d), bez „e” (%d), wyjście „E” przy starcie (%d), grupy finału (%d)" % [level.collapse_rects.size(), level.exits_alt.size(), level.exits.size(), level.finale_spawns.size()],
		level.collapse_rects.size() == 1 and level.exits_alt.is_empty() and level.exits.size() == 1 and level.exits[0].x < 400.0 and not level.finale_spawns.is_empty())
	var hall := Vector2(274.0 * 16.0 + 8.0, 34.0 * 16.0)
	var start: Vector2 = level.spawns[0]
	var ramp_pre := Vector2(254.0 * 16.0 + 8.0, 29.0 * 16.0)
	var area := Rect2(258.0 * 16.0, 25.0 * 16.0, 8.0 * 16.0, 9.0 * 16.0)
	var through := func(path: Array) -> bool:           # czy trasa przechodzi przez obszar zawału
		for n in path:
			if area.has_point(n.pos):
				return true
		return false
	check.call("przed zawałem: rampa wolna (%s), droga z sali w górę rampy biegnie przez nią" % level._ch(260, 30),
		not level._is_solid(260, 30) and through.call(level.nav.find_path(hall, ramp_pre)))
	var tags_now := func() -> Array: return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "tag" and not n.is_queued_for_deletion())
	for i in 6:
		var near: Array = tags_now.call()
		near.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
		p.global_position = (near[0] as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
	check.call("ostatni nieśmiertelnik → finał (finale=%s, faza %d), wyjście przy starcie — powrót przez las (x=%.0f)" % [str(mission.finale), mission.phase, mission.exit_pos.x],
		mission.finale and mission.phase == MISSION_SCRIPT.Phase.EXTRACT and mission.exit_pos.x < 400.0 and level.exits_alt.is_empty())
	var finale_foes := level.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Finale"))
	check.call("obudzony las: finał wypuścił grupy na drogę powrotną (%d z %d)" % [finale_foes.size(), level.finale_spawns.size()],
		finale_foes.size() == level.finale_spawns.size() and finale_foes.size() >= 4)
	# gracz „uwięziony" w obszarze zawału: ma wylądować za skałą (po stronie sali)
	p.global_position = Vector2(261.0 * 16.0, 32.0 * 16.0)
	p.velocity = Vector2.ZERO
	var prepared = level._nav_after                       # graf „po zawale” policzony przy wczytaniu mapy (zawał bez przestoju)
	await get_tree().create_timer(2.6).timeout
	var fresh := NavGraph.new()
	fresh.build((level._map[0] as String).length(), level._map.size(), level._is_solid, level._is_platform_cell)
	var p_now: Array = level.nav.find_path(hall, mission.exit_pos)
	var p_fresh: Array = fresh.find_path(hall, mission.exit_pos)
	check.call("zawał: graf nawigacji gotowy z wczytania mapy (%s), trasa jak w grafie zbudowanym od nowa (%d / %d węzłów)" % [str(prepared != null and level.nav == prepared), p_now.size(), p_fresh.size()],
		prepared != null and level.nav == prepared and p_now.size() == p_fresh.size() and not p_now.is_empty())
	check.call("po zawale: rampa to skała (%s), trasa grafu z sali na rampę nie przechodzi przez zawał (idzie szybem i górą), gracz za skałą (x=%.0f)" % [level._ch(260, 30), p.global_position.x],
		level._is_solid(260, 30) and not through.call(level.nav.find_path(hall, ramp_pre)) and p.global_position.x > 266.0 * 16.0)
	var back_path: Array = level.nav.find_path(hall, mission.exit_pos)
	var via_shaft := back_path.any(func(n: Dictionary) -> bool: return (n.pos as Vector2).x > 290.0 * 16.0)
	check.call("po zawale: z sali szybem na powierzchnię i lasem do wyjścia przy starcie (ścieżka %d węzłów, przez szyb=%s)" % [back_path.size(), str(via_shaft)],
		not back_path.is_empty() and via_shaft)
	check.call("radio patrolu: linie 0 s / 3 s / 6 s / 9 s i cisza po %.1f s" % mission.FINALE_RADIO_END,
		mission.radio_line_at(0.0).begins_with("…Seven") and mission.radio_line_at(3.5).contains("mine") and mission.radio_line_at(6.5).contains("shaft")
		and mission.radio_line_at(9.5).contains("woods") and mission.radio_line_at(mission.FINALE_RADIO_END) == "" and mission.radio_line_at(-1.0) == "")
	check.call("radio na HUD tylko w finale (clock %.1f, linia '%s')" % [mission.finale_clock, mission.finale_radio_line().substr(0, 20)], mission.finale and mission.finale_radio_line() != "")
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ewakuacja przy nowym wyjściu → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	_restart_mission(true)
	await get_tree().create_timer(0.8).timeout
	check.call("restart: radio zresetowane", mission.finale_radio_line() == "" and mission.finale_clock == 0.0)
	check.call("restart: grupy finału zniknęły", level.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Finale")).is_empty())
	check.call("restart: rampa znów wolna, droga wraca, finał zresetowany (finale=%s)" % str(mission.finale),
		not level._is_solid(260, 30) and through.call(level.nav.find_path(hall, ramp_pre)) and not mission.finale and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	check.call("restart: graf „po zawale” przygotowany znowu (następny zawał też bez przestoju)", level._nav_after != null)
	print("[FINALE-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test misji 1.2 (--host --mission=z1_m2 --gentest): cztery generatory (przytrzymanie E), skok Uwagi po ostatnim, ekstrakcja,
## a potem [Enter] → mapa 1.3 i z powrotem. Wrogowie są zamrożeni, żeby test był powtarzalny.
func _gen_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]                      # tablica: lambda kopiuje liczby, a tablicę współdzieli
	var check := func(label: String, ok: bool) -> void:
		print("[GEN-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)
	check.call("start: mapa 1.2, cel generators, 4 generatory", level.map_id == "z1_m2" and mission.kind == "generators" and mission.goal_total == 4)
	# zamurowane przejście w hali (kilof): skrytka za ścianą jest nieosiągalna, dopóki ściana stoi
	var alcove: Array = (level._map_items.get("u", []) as Array).filter(func(v: Vector2) -> bool: return v.x > 2290.0 and v.x < 2400.0)
	var start_id: int = level.nav.get_closest_point(level.spawns[0])
	var sealed := false
	if alcove.size() > 0:
		sealed = level.nav.get_id_path(start_id, level.nav.get_closest_point(alcove[0])).is_empty()
	var wall_node := level.get_node_or_null("BrickWall1")
	check.call("zamurowane przejście: ściana + skrytka za nią (%d × złom), nawigacja jej nie widzi (szczelna: %s)" % [alcove.size(), str(sealed)], wall_node != null and alcove.size() == 2 and sealed and level.walls_total() == 1)
	level.break_wall("BrickWall1")
	await get_tree().create_timer(0.3).timeout
	var open_id: int = level.nav.get_closest_point(alcove[0]) if alcove.size() > 0 else -1
	check.call("po rozbiciu: ściana znika, skrytka osiągalna ze startu", not is_instance_valid(level.get_node_or_null("BrickWall1")) and open_id >= 0 and not level.nav.get_id_path(level.nav.get_closest_point(level.spawns[0]), open_id).is_empty())
	Scrap.add_loot(25)
	level.spawn_item("scrap", 0, p.global_position + Vector2(0, -4), 7)
	var scrap_item := level.get_node_or_null("Item%d" % level._pickup_serial)
	if scrap_item != null:
		scrap_item._vel = Vector2.ZERO          # bez losowego podskoku: test ma być deterministyczny
	await get_tree().create_timer(1.0).timeout
	check.call("złom: pickup 7 wpadł do łupu (loot %d, bank %d)" % [Scrap.loot, Scrap.bank], Scrap.loot == 32 and Scrap.bank == 0)
	Scrap.reset_loot()
	check.call("złom: restart kasuje łup, bank bez zmian", Scrap.loot == 0 and Scrap.bank == 0)
	Scrap.add_loot(25)
	var map_scrap := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "scrap")
	check.call("złom: skrytki na mapie 1.2 (%d)" % map_scrap.size(), map_scrap.size() >= 4)
	var gens: Array = get_tree().get_nodes_in_group("generators")
	gens.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.x < b.global_position.x)
	for i in gens.size():
		p.global_position = gens[i].global_position + Vector2(-10, 0)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.3).timeout
		Input.action_press("interact")
		await get_tree().create_timer(gens[i].WORK_TIME + 0.8).timeout
		Input.action_release("interact")
		check.call("generator %d uruchomiony, zostało %d" % [i + 1, gens.size() - 1 - i], gens[i].running and mission.goal_left == gens.size() - 1 - i)
		if i == 0:
			check.call("stealth po pierwszym generatorze (szczyt Uwagi %.0f < 40)" % mission.peak_noise, mission.stealth_ok())
	check.call("po wszystkich generatorach: EXTRACT, Uwaga %.0f (skok do %.0f), Stalker obudzony=%s" % [NoiseMgr.level, mission.BROADCAST_NOISE, str(NoiseMgr.stalker_awake)],
		mission.phase == MISSION_SCRIPT.Phase.EXTRACT and NoiseMgr.level >= 60.0 and NoiseMgr.stalker_awake)
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ekstrakcja → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	check.call("złom: po misji bank = łup (min. 25) + bonus (min. 40) (bank %d, loot %d, ostatni zysk %d)" % [Scrap.bank, Scrap.loot, Scrap.last_gain],
		Scrap.last_gain >= 65 and Scrap.bank == Scrap.last_gain and Scrap.loot == 0)
	check.call("złom: wpis w dzienniku misji ma zysk", not RunLog.entries.is_empty() and int(RunLog.entries.back()["scrap"]) == Scrap.last_gain)
	var ammo_before: int = Arsenal.get_reserve(Weapons.def(p.weapons.loadout[0]).id)
	var loadout_before: Array = (p.weapons.loadout as Array).duplicate()
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	var foes: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not (e is RigidBody2D))      # rekwizyty (skrzynie) też są w tej grupie
	check.call("[Enter] po 1.2 → kryjówka (następna: %s, wrogów %d)" % [after_hub, foes.size()],
		level.map_id == "z1_hub" and mission.kind == "hub" and after_hub == "z1_m3" and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE
		and foes.is_empty() and p.global_position.distance_to(level.spawn_for(1)) < 40.0)
	var cabinets := 0
	var lamps := 0
	for c in level.get_children():
		if String(c.name).begins_with("Cabinet"):
			cabinets += 1
		elif String(c.name).begins_with("Lamp"):
			lamps += 1
	var in_cab := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "weapon" and n.has_meta("cabinet")).size()
	var brief: Dictionary = level.briefing(after_hub)
	check.call("kryjówka: 2 gabloty z 8 broniami, 12 lamp, tablica, ciepły ambient (%.2f)" % level.ambient.r,
		cabinets == 2 and in_cab == 8 and lamps == 12 and get_tree().get_nodes_in_group("board").size() == 1 and level.ambient.r > 0.1)
	# radiostacja (R, weather.gd): jedna w kryjówce, w kryjówce pogody misji nie ma, prognoza jest znanym rodzajem; mnożniki pogody łączą się z NightShift
	check.call("niebo (deszcz): w kryjówce zamknięte (sufit), ustawienie efektów pogody domyślnie REDUCED (%s)" % Settings.WEATHER_FX_NAMES[Settings.weather_fx_idx],
		not level.sky_open_at(p.global_position) and Settings.WEATHER_FX_NAMES.size() == 3)
	check.call("radiostacja: jedna w kryjówce, prognoza '%s', bez pogody misji" % Weather.forecast,
		get_tree().get_nodes_in_group("radio_set").size() == 1 and Weather.KINDS.has(Weather.forecast) and Weather.current == "")
	var w_saved: String = Weather.current
	Weather.current = "storm"
	var w_ok := is_equal_approx(NightShift.noise_mult(), 0.6) and is_equal_approx(NightShift.ammo_mult(), 0.75)
	Weather.current = "fog"
	w_ok = w_ok and is_equal_approx(NightShift.noise_mult(), 0.85) and is_equal_approx(NightShift.awake_threshold(60.0), 50.0) and is_equal_approx(NightShift.sleep_threshold(30.0), 20.0)
	Weather.current = "rain"
	w_ok = w_ok and is_equal_approx(NightShift.noise_mult(), 0.75) and is_equal_approx(NightShift.start_noise(10.0), 20.0) and is_equal_approx(NightShift.start_noise(35.0), 35.0)
	Weather.current = "clear"
	w_ok = w_ok and is_equal_approx(NightShift.noise_mult(), 1.0) and is_equal_approx(NightShift.ammo_mult(), 1.0) and is_equal_approx(NightShift.awake_threshold(60.0), 60.0)
	Weather.current = w_saved
	w_ok = w_ok and is_equal_approx(NightShift.noise_mult(), 1.0) and is_equal_approx(NightShift.start_noise(20.0), 20.0)
	var w_hud_ok := true
	for wid in Weather.KINDS:
		w_hud_ok = w_hud_ok and Weather.short_of(String(wid)) != "" and Weather.name_of(String(wid)) != "" and Weather.color_of(String(wid)) != Color.WHITE
	check.call("pogoda (HUD, radiostacja): każda pogoda ma nazwę, kolor i krótki opis skutków", w_hud_ok)
	check.call("pogoda (dźwięk): są pętle deszczu i grzmoty (amb_rain, amb_rain_roof, thunder_1..3)",
		Audio.stream("amb_rain") != null and Audio.stream("amb_rain_roof") != null and Audio.variant("thunder", 3) >= 0)
	check.call("pogoda: burza / mgła / deszcz / pogodnie dają swoje mnożniki hałasu, amunicji i progów Stalkera, brak pogody = bez zmian", w_ok)
	check.call("odprawa następnej misji (%s): tytuł, cel, %d rodzajów wrogów, %d gniazd, boss=%s" % [after_hub, (brief["counts"] as Dictionary).size(), int(brief["nests"]), str(brief["boss"])],
		String(brief["title"]) != "" and String(brief["brief"]) != "" and (brief["counts"] as Dictionary).has("trzosek") and int(brief["nests"]) == 4 and bool(brief["boss"]))
	# kryjówka jest bezpieczna: wymuszamy warunki, w których Dyrektor grozy dosypałby wędrowców, i sprawdzamy, że nikt się nie pojawia
	Director._spawn_t = 0.0
	Director._since_enc = 999.0
	Director._relax_t = 0.0
	Director.stress = 0.0
	await get_tree().create_timer(2.0).timeout
	var roamers: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return String(e.name).begins_with("Roamer"))
	var live_foes: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not (e is RigidBody2D))

	# warsztat (faza B złomu): ława, panel, zablokowane stojaki, zakup
	var purchase_bench := get_tree().get_first_node_in_group("workshop") as Node2D
	p.global_position = purchase_bench.global_position + Vector2(0, -2)  # dodatni test zakupu wymaga właściwego stanowiska
	p.velocity = Vector2.ZERO
	var racks_w := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "weapon" and n.static_display)
	var locked_n := racks_w.filter(func(n: Node) -> bool: return level.is_locked_item(n)).size()
	check.call("warsztat: ława + panel, stojaki zablokowane (%d z %d)" % [locked_n, racks_w.size()],
		get_tree().get_nodes_in_group("workshop").size() == 1 and get_tree().get_nodes_in_group("workshop_ui").size() == 1 and racks_w.size() == 8 and locked_n == 7)
	var results: Array = []
	var cb := func(w: int, ok: bool, reason: String) -> void: results.append([w, ok, reason])
	Scrap.purchase_result.connect(cb)
	var saved_bank := Scrap.bank
	Scrap.bank = 100
	Scrap.request_buy(Weapons.LR7)
	Scrap.request_buy(Weapons.SOKOL6)
	Scrap.bank = 400
	Scrap.request_buy(Weapons.LR7)
	Scrap.request_buy(Weapons.LR7)
	var reasons := results.map(func(r: Array) -> String: return String(r[2]))
	check.call("warsztat: zakup (za mało → poor, późniejsza strefa → later, ok, ponownie → owned): %s, portfel %d" % [str(reasons), Scrap.bank],
		reasons == ["poor", "later", "ok", "owned"] and Scrap.bank == 400 - Scrap.price_of(Weapons.LR7) and Scrap.is_unlocked(Weapons.LR7) and not Scrap.is_unlocked(Weapons.HKM9))
	var locked_after := racks_w.filter(func(n: Node) -> bool: return level.is_locked_item(n)).size()
	check.call("warsztat: kupiony stojak się odblokował (zablokowane %d)" % locked_after, locked_after == 6)
	# panel warsztatu (UI faza 3): otwarcie przy ławie, siatka 12 broni, wybór myszą (kafel), zamknięcie przywraca mysz
	var wk_node: Node2D = get_tree().get_first_node_in_group("workshop")
	var wmodels: Array = wk_node.get("station_props")
	check.call("ława: modele 3D stanowiska %s (art/items3d)" % str(wmodels.map(func(e: Array) -> String: return String(e[0]))),
		wmodels.size() == 2 and wmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	p.global_position = wk_node.global_position + Vector2(0, -2)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	wui.open()
	await get_tree().create_timer(0.3).timeout
	var tiles: Array = wui._tiles
	(tiles[3] as Button).pressed.emit()
	var opened_ok: bool = wui.is_open() and tiles.size() == 12 and wui._sel == 3 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var bench_tabs: Array = wui._page_btns.filter(func(b: Button) -> bool: return b.visible).map(func(b: Button) -> String: return b.text)
	var tab_ev := InputEventKey.new()
	tab_ev.physical_keycode = KEY_TAB
	tab_ev.pressed = true
	wui._input(tab_ev)
	var bench_tab1: int = wui._page
	wui._input(tab_ev)
	check.call("ława (1.7.349): zakładki %s, Tab ARMS → SUPPLIES → ARMS (%d, %d)" % [str(bench_tabs), bench_tab1, wui._page],
		bench_tabs == ["ARMS", "SUPPLIES"] and bench_tab1 == 1 and wui._page == 0)
	wui.close()
	# szafki osobiste (WORKSHOP_PLAN.md W1): znacznik „p" w świetlicy, [E] otwiera panel z zakładkami PERKS i LOOK
	var lockers := get_tree().get_nodes_in_group("locker_station")
	var lk_ok := false
	if lockers.size() == 1:
		p.global_position = (lockers[0] as Node2D).global_position + Vector2(0, -2)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.5).timeout
		lk_ok = bool(lockers[0].local_in_range) and not bool(wk_node.local_in_range)
	# stół konserwacji (W2): znacznik „j" obok ławy, zasięgi stołu i ławy się nie nakładają
	var svc_nodes := get_tree().get_nodes_in_group("service_bench")
	var svc_ok := false
	if svc_nodes.size() == 1:
		var lk_pos := p.global_position
		p.global_position = (svc_nodes[0] as Node2D).global_position + Vector2(0, -2)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.5).timeout
		svc_ok = bool(svc_nodes[0].local_in_range) and not bool(wk_node.local_in_range)
		p.global_position = wk_node.global_position + Vector2(0, -2)
		await get_tree().create_timer(0.5).timeout
		svc_ok = svc_ok and not bool(svc_nodes[0].local_in_range) and bool(wk_node.local_in_range)
		p.global_position = lk_pos
		await get_tree().create_timer(0.5).timeout
	check.call("stół konserwacji: %d w kryjówce, zasięg osobno od ławy (%s)" % [svc_nodes.size(), str(svc_ok)], svc_nodes.size() == 1 and svc_ok)
	var smodels: Array = svc_nodes[0].get("station_props") if svc_nodes.size() == 1 else []
	check.call("stół konserwacji: modele 3D stanowiska %s (art/items3d)" % str(smodels.map(func(e: Array) -> String: return String(e[0]))),
		smodels.size() == 3 and smodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	var press_nodes := get_tree().get_nodes_in_group("press_bench")
	check.call("prasa elaboracyjna: %d w kryjówce (dół, kol. 33)" % press_nodes.size(), press_nodes.size() == 1 and int((press_nodes[0] as Node2D).global_position.x / 16.0) == 33)
	var pmodels: Array = press_nodes[0].get("station_props") if press_nodes.size() == 1 else []
	check.call("prasa: modele 3D stanowiska %s (art/items3d)" % str(pmodels.map(func(e: Array) -> String: return String(e[0]))),
		pmodels.size() == 3 and pmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	var lathe_nodes := get_tree().get_nodes_in_group("lathe_bench")
	check.call("tokarka: %d w kryjówce (dół, kol. 11)" % lathe_nodes.size(), lathe_nodes.size() == 1 and int((lathe_nodes[0] as Node2D).global_position.x / 16.0) == 11)
	var lmodels: Array = lathe_nodes[0].get("station_props") if lathe_nodes.size() == 1 else []
	check.call("tokarka: modele 3D stanowiska %s (art/items3d)" % str(lmodels.map(func(e: Array) -> String: return String(e[0]))),
		lmodels.size() == 4 and lmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	var lab_nodes := get_tree().get_nodes_in_group("lab_bench")
	check.call("pracownia: %d w kryjówce (góra, kol. 45)" % lab_nodes.size(), lab_nodes.size() == 1 and int((lab_nodes[0] as Node2D).global_position.x / 16.0) == 45)
	var cmodels: Array = lab_nodes[0].get("station_props") if lab_nodes.size() == 1 else []
	check.call("pracownia: modele 3D stanowiska %s (art/items3d)" % str(cmodels.map(func(e: Array) -> String: return String(e[0]))),
		cmodels.size() == 3 and cmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	var pyro_nodes := get_tree().get_nodes_in_group("pyro_bench")
	check.call("stół pirotechniczny: %d w kryjówce (dół, kol. 46)" % pyro_nodes.size(), pyro_nodes.size() == 1 and int((pyro_nodes[0] as Node2D).global_position.x / 16.0) == 46)
	var zmodels: Array = pyro_nodes[0].get("station_props") if pyro_nodes.size() == 1 else []
	check.call("pirotechnika: modele 3D stanowiska %s (art/items3d)" % str(zmodels.map(func(e: Array) -> String: return String(e[0]))),
		zmodels.size() == 4 and zmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	wui.open("locker")
	await get_tree().create_timer(0.1).timeout
	var locker_tabs: Array = wui._page_btns.filter(func(b: Button) -> bool: return b.visible).map(func(b: Button) -> String: return b.text)
	check.call("szafki osobiste: %d w kryjówce, gracz przy nich (%s), panel LOCKER otwarty na PERKS (%d), zakładki %s" % [lockers.size(), str(lk_ok), wui._page, str(locker_tabs)],
		lockers.size() == 1 and lk_ok and wui.is_open() and wui._page == 2 and locker_tabs == ["PERKS", "LOOK"] and wui._title.text == tr("LOCKER"))
	var kmodels: Array = lockers[0].get("station_props") if lockers.size() == 1 else []
	check.call("szafki: modele 3D stanowiska %s (art/items3d)" % str(kmodels.map(func(e: Array) -> String: return String(e[0]))),
		kmodels.size() == 2 and kmodels.all(func(e: Array) -> bool: return ResourceLoader.exists("res://art/items3d/%s.glb" % String(e[0]))))
	# zakładka PERKS (B2): 8 kafli, zakładanie / zdejmowanie perku przez panel, zablokowany perk nie wchodzi, Tab przechodzi przez 3 zakładki
	Profile.reset_for_test()
	Profile.add_xp(800, "test")                                        # L4: 2 sloty, perki do L4
	wui._set_page(2)
	await get_tree().create_timer(0.1).timeout
	var perk_tiles_n: int = wui._perk_tiles.size()
	wui._perk_sel = 3                                                  # Smith
	wui._perk_slot = 0
	wui._act_perk()
	var perk_on: bool = Profile.equipped[0] == "smith"
	wui._act_perk()
	var perk_off: bool = Profile.equipped[0] == ""
	wui._perk_sel = 7                                                  # Veteran (L6) przy L4
	wui._act_perk()
	var perk_locked: bool = not Profile.equipped.has("veteran")
	wui._input(tab_ev)
	var tab_to_look: bool = wui._page == 3                              # 2 → 3 (LOOK)
	wui._input(tab_ev)
	var tab_wrapped: bool = tab_to_look and wui._page == 2              # 3 → 2 (szafki mają tylko PERKS i LOOK)
	var pm_node: Node = $UI.get_node("PauseMenu")
	check.call("zakładka PERKS: %d kafli, załóż → %s, zdejmij → %s, perk L6 przy L4 zablokowany → %s, Tab przechodzi PERKS → LOOK → PERKS → %s; menu pauzy ma %d kart, kodeks %d perków" % [perk_tiles_n, str(perk_on), str(perk_off), str(perk_locked), str(tab_wrapped), pm_node._pages.size(), Codex.perks().size()],
		perk_tiles_n == 8 and perk_on and perk_off and perk_locked and tab_wrapped and pm_node._pages.size() == 6 and Codex.perks().size() == 8)
	Profile.reset_for_test()
	wui.close()
	check.call("panel warsztatu: otwiera się przy ławie, 12 kafli, kliknięcie kafla wybiera broń (sel %d), mysz widoczna; po zamknięciu zamknięty" % wui._sel, opened_ok and not wui.is_open())
	p.global_position = wk_node.global_position + Vector2(0, -2)        # z powrotem przy ławie (dalsze testy warsztatu)
	p.velocity = Vector2.ZERO
	# części broni (parts.gd, 1.7.319): zakup wspólny dla drużyny, montaż prywatny gracza
	Scrap.purchase_result.disconnect(cb)
	var presults: Array = []
	var pcb := func(id: String, ok: bool, reason: String) -> void: presults.append(reason)
	Scrap.part_result.connect(pcb)
	var base_mag: int = Weapons.base_def(Weapons.M83).mag
	var base_dmg: float = Weapons.base_def(Weapons.M83).damage
	Profile.reset_for_test()
	Scrap.bank = 10
	Scrap.request_part("m83_rpk40")                    # poor
	Scrap.request_part("hkm_tank")                     # locked (broń nie kupiona)
	Scrap.request_part("nie_ma_takiej")                # invalid
	Scrap.bank = 1000
	for pid in ["m83_rpk40", "m83_rpkbar", "m83_pbs1", "m83_pbs1"]:
		Scrap.request_part(pid)                        # 3 × ok, potem owned
	Scrap.request_part("m83_drum75")                   # alternatywa w tym samym gnieździe: kupiona i zamontowana zamiast RPK 40
	Scrap.part_result.disconnect(pcb)
	var ed: RefCounted = Weapons.def_build(Weapons.M83, Weapons.build_of(0, Profile.fit_code(Weapons.M83)))
	check.call("części: poor / locked / invalid / 3×ok / owned / ok: %s, portfel %d" % [str(presults), Scrap.bank],
		presults == ["poor", "locked", "invalid", "ok", "ok", "ok", "owned", "ok"] and Scrap.bank == 1000 - 60 - 120 - 220 - 160 and Scrap.parts_owned(Weapons.M83) == 4)
	check.call("montaż: kupiona część montuje się kupującemu — bęben 75 zamiast RPK 40 (magazynek %d), lufa RPK, PBS-1; obrażenia bez zmian, baza nietknięta" % ed.mag,
		ed.mag == base_mag + 45 and is_equal_approx(ed.damage, base_dmg) and ed.suppressor > 0.0 and ed.jitter_deg < Weapons.base_def(Weapons.M83).jitter_deg
		and Weapons.def(Weapons.M83).mag == base_mag and Profile.fitted("m83", "feed") == "m83_drum75")
	Profile.set_fit("m83", "feed", "")
	check.call("montaż: element fabryczny w gnieździe zasilania (magazynek %d)" % Weapons.def_build(Weapons.M83, Weapons.build_of(0, Profile.fit_code(Weapons.M83))).mag,
		Weapons.def_build(Weapons.M83, Weapons.build_of(0, Profile.fit_code(Weapons.M83))).mag == base_mag)
	# zestawy części (WORKSHOP_PLAN.md U6, 1.7.349): zapis bieżącego montażu, montaż zestawu jednym ruchem, część, której drużyna nie ma, zostaje jak była
	Profile.save_preset("m83", 0)                                    # fabryczne zasilanie, lufa RPK, PBS-1
	Profile.set_fit("m83", "feed", "m83_drum75")
	Profile.set_fit("m83", "muzzle", "")
	Profile.save_preset("m83", 1)                                    # bęben, lufa RPK, fabryczny wylot
	var sk0 := Profile.load_preset("m83", 0)
	var set0_ok: bool = sk0 == 0 and Profile.fitted("m83", "feed") == "" and Profile.fitted("m83", "muzzle") == "m83_pbs1" and Profile.is_preset_fitted("m83", 0) and not Profile.is_preset_fitted("m83", 1)
	Scrap.parts.erase("m83_drum75")                                  # np. inny host: bębna nie ma
	var sk1 := Profile.load_preset("m83", 1)
	Scrap.parts["m83_drum75"] = true                                 # dalsze testy (katalog) liczą kupione części
	check.call("zestawy: zapis i montaż zestawu 1 (%s), zestaw 2 bez bębna, którego drużyna nie ma — pominięty %d, zasilanie zostaje (%s), wylot fabryczny" % [str(set0_ok), sk1, Profile.fitted("m83", "feed")],
		set0_ok and sk1 == 1 and Profile.fitted("m83", "feed") == "" and Profile.fitted("m83", "muzzle") == "" and Profile.preset("m83", 2).is_empty())
	wui.open("bench")
	var pops: Array = wui._options(Weapons.M83)
	wui._sel = 0
	wui._opt = pops.find({"slot": "preset", "id": "2"})
	wui._refresh()
	var empty_txt: String = wui._action.text
	var r_ev := InputEventKey.new()
	r_ev.physical_keycode = KEY_R
	r_ev.pressed = true
	wui._input(r_ev)                                                  # R = menu_alt: zapis bieżącego montażu do zestawu 3
	check.call("panel: wiersze zestawów (%d), pusty zestaw '%s', [R] zapisuje zestaw 3 (%s)" % [pops.filter(func(o: Dictionary) -> bool: return o["slot"] == "preset").size(), empty_txt, str(not Profile.preset("m83", 2).is_empty())],
		pops.filter(func(o: Dictionary) -> bool: return o["slot"] == "preset").size() == Profile.PRESETS and empty_txt == tr("Save current fit as set %d") % 3
		and Profile.is_preset_fitted("m83", 2))
	wui.close()
	Profile.load_preset("m83", 0)                                    # montaż sprzed testu zestawów (katalog niżej go sprawdza)
	var cat := Codex.weapon_entry(Weapons.M83)
	var cat_lr := Codex.weapon_entry(Weapons.SOKOL6)
	var tier_states := (cat["tiers"] as Array).map(func(t: Dictionary) -> int: return int(t["state"]))
	check.call("katalog broni: M-83 pokazuje części (stany %s, tag '%s'), zablokowana broń ma informację o dostępie ('%s')" % [str(tier_states), cat["tag"], (cat_lr["access"] as String)],
		tier_states.size() == Weapons.Parts.of("m83").size() and tier_states.count(0) == 2 and tier_states.count(1) == 2 and (cat["tag"] as String).contains("PARTS 4 /")
		and (cat_lr["access"] as String).begins_with("Locked"))
	Profile.reset_for_test()
	Scrap.parts.clear()
	Scrap.unlocked.clear()
	Scrap.bank = saved_bank
	var wall_nodes := get_tree().get_nodes_in_group("results_wall")
	check.call("ściana wyników: stoi w kryjówce, zapisała misję 1.2 (%d wpis, %s)" % [RunLog.entries.size(), str(RunLog.entries.back()) if not RunLog.entries.is_empty() else "-"],
		wall_nodes.size() == 1 and RunLog.entries.size() >= 1 and String(RunLog.entries.back()["id"]) == "z1_m2" and float(RunLog.entries.back()["time"]) >= 0.0 and int(RunLog.entries.back()["stealth"]) >= 0)
	check.call("kryjówka: Dyrektor nie dosypuje wrogów (wędrowców %d, wrogów %d)" % [roamers.size(), live_foes.size()], roamers.is_empty() and live_foes.is_empty())
	check.call("ekwipunek i amunicja przechodzą do kryjówki", p.weapons.loadout == loadout_before and Arsenal.get_reserve(Weapons.def(loadout_before[0]).id) == ammo_before)
	await get_tree().create_timer(2.5).timeout
	check.call("kryjówka: bez gotowości nie ruszamy (%d/%d)" % [hub_ready_n, hub_total], level.map_id == "z1_hub" and hub_countdown < 0.0)
	var spawn_pos: Vector2 = p.global_position
	p.global_position = Vector2(level.launch_zone.get_center().x, level.launch_zone.end.y - 4.0)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: stanie w strefie startu = gotowość i odliczanie (%.1f s, %d/%d)" % [hub_countdown, hub_ready_n, hub_total], hub_in_zone and hub_mine and hub_countdown > 2.0 and hub_ready_n == hub_total)
	var cd_alert: Dictionary = Msg.current(Msg.Ch.ALERT)
	check.call("komunikaty: odliczanie wyjścia to alert w kanale ALERT (%s)" % str(cd_alert.get("text", "-")), String(cd_alert.get("id", "")) == "hud.hubcount" and bool(cd_alert.get("big", false)))
	check.call("dziennik: akcja journal zarejestrowana (klawisz N), porady przez kanał TIP", InputMap.has_action("journal") and Msg.Ch.TIP == 4)
	p.global_position = spawn_pos
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: wyjście ze strefy anuluje odliczanie", not hub_in_zone and not hub_mine and hub_countdown < 0.0)
	_hub_set_ready(NoiseMgr.local_id(), true)
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: wszyscy ludzie gotowi → odliczanie (%.1f s, %d/%d)" % [hub_countdown, hub_ready_n, hub_total], level.map_id == "z1_hub" and hub_countdown > 0.0 and hub_ready_n == hub_total and hub_total >= 1)
	_hub_set_ready(NoiseMgr.local_id(), false)
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: odznaczenie przerywa odliczanie", level.map_id == "z1_hub" and hub_countdown < 0.0)
	var forecast_before: String = Weather.forecast
	_hub_set_ready(NoiseMgr.local_id(), true)
	await get_tree().create_timer(HUB_COUNTDOWN + 1.0).timeout
	await get_tree().create_timer(0.5).timeout
	check.call("ambient po wyjściu z kryjówki wraca do domyślnego (%.3f)" % level.ambient.r, level.ambient.r < 0.05)
	check.call("[Enter] w kryjówce → mapa 1.3 (gniazda), ekwipunek zachowany",
		level.map_id == "z1_m3" and mission.kind == "nests" and mission.goal_total == 4 and p.weapons.loadout == loadout_before
		and Arsenal.get_reserve(Weapons.def(loadout_before[0]).id) == ammo_before and get_tree().get_nodes_in_group("generators").is_empty())
	check.call("niebo (deszcz): na starcie 1.3 otwarte, nad głową gracza w podziemiach zamknięte", level.sky_open_at(level.spawn_for(1)) and not level.sky_open_at(Vector2(level.spawn_for(1).x, level.underground_y + 40.0)))
	check.call("pogoda misji po wyjściu z kryjówki = prognoza z radiostacji (%s)" % forecast_before, Weather.current == forecast_before)
	mission.elapsed = 5.0
	mission._success()
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	check.call("po 1.3 kryjówka, następna: B1 Pijawka (boss zamyka Strefę I)", level.map_id == "z1_hub" and after_hub == "z1_b1")
	check.call("powrót do kryjówki: pogoda misji znika, nowa prognoza (%s)" % Weather.forecast, Weather.current == "" and Weather.KINDS.has(Weather.forecast))
	var brief_b1: Dictionary = level.briefing("z1_b1")
	check.call("odprawa B1: tytuł '%s', boss '%s', bez Trzosków w odprawie" % [brief_b1["title"], brief_b1.get("boss_name", "")], String(brief_b1["title"]).contains("LEECH") and bool(brief_b1["boss"]) and String(brief_b1.get("boss_name", "")) == "THE LEECH")
	_depart_hub()
	await get_tree().create_timer(0.5).timeout
	check.call("wyjście z kryjówki → B1 (arena z basenem, misja boss, Pijawka śpi)",
		level.map_id == "z1_b1" and mission.kind == "boss" and get_tree().get_first_node_in_group("boss") != null and get_tree().get_nodes_in_group("generators").is_empty())
	mission.elapsed = 9.0
	mission._success()
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	check.call("po B1 kryjówka, następna: 1.1 (kampania w kółko od początku)", level.map_id == "z1_hub" and after_hub == "z1_m1")
	_depart_hub()
	await get_tree().create_timer(0.5).timeout
	check.call("wyjście z kryjówki → 1.1 (6 nieśmiertelników, bez generatorów)",
		level.map_id == "z1_m1" and mission.kind == "tags" and mission.goal_left == 6 and mission.goal_total == 6 and get_tree().get_nodes_in_group("generators").is_empty())
	check.call("kolejność kampanii 1.1 → 1.2 → 1.3 → B1, Nocny Dyżur losuje tylko z 1.2 i 1.3 (pula %s)" % str(level.SHIFT_POOL),
		level.CAMPAIGN == ["z1_m1", "z1_m2", "z1_m3", "z1_b1"] and level.SHIFT_POOL == ["z1_m2", "z1_m3"])
	print("[GEN-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Długość ścieżki A* między dwoma punktami podłogi (px); 0, gdy brak drogi.
func _nav_len(nav: AStar2D, from: Vector2, to: Vector2) -> float:
	var path := nav.get_point_path(nav.get_closest_point(from), nav.get_closest_point(to))
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i].distance_to(path[i - 1])
	return d

## Test drezyny (--host --mission=z1_m2 --ridetest): generatory → zasilenie, wejście na pokład, pompowanie (gracz jedzie
## razem z platformą), dojazd do końca toru, wyjście → SUCCESS. Wrogowie zamrożeni.
func _ride_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var fails := [0]
	var check := func(label: String, ok: bool) -> void:
		print("[RIDE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	var p: Node2D = _players.get_node_or_null("1")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)
	var car: AnimatableBody2D = get_tree().get_first_node_in_group("handcar")
	check.call("drezyna istnieje, bez zasilania", car != null and not car.enabled)
	for g in get_tree().get_nodes_in_group("generators"):
		g._start()
	await get_tree().create_timer(0.3).timeout
	check.call("po generatorach: EXTRACT, drezyna zasilona", mission.phase == MISSION_SCRIPT.Phase.EXTRACT and car.enabled)
	var x0: float = car.global_position.x
	p.global_position = car.global_position + Vector2(0, -8)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	check.call("gracz stoi na pokładzie (stan: %s)" % car.local_state, car.aboard(p) and car.local_state == "aboard")
	Input.action_press("interact")
	await get_tree().create_timer(3.0).timeout
	check.call("pompowanie: prędkość %.0f px/s, drezyna ruszyła o %.0f px" % [car.speed, x0 - car.global_position.x], car.speed > 60.0 and car.global_position.x < x0 - 60.0 and p.pumping)
	check.call("gracz jedzie z drezyną (odległość %.0f px)" % absf(p.global_position.x - car.global_position.x), car.aboard(p))
	var t := 0.0
	while not car.arrived and t < 75.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if int(t * 2) % 10 == 0:
			print("[RIDE-TEST] t=%.0f car.x=%.0f speed=%.0f power=%.1f | p=(%.0f,%.0f) aboard=%s pumping=%s dead=%s" % [t, car.global_position.x, car.speed, car.power, p.global_position.x, p.global_position.y, str(car.aboard(p)), str(p.pumping), str(p.dead)])
	Input.action_release("interact")
	check.call("dojazd do końca toru po %.0f s (x=%.0f, cel %.0f)" % [t, car.global_position.x, car.end_x], car.arrived and absf(car.global_position.x - car.end_x) < 2.0)
	check.call("gracz nadal na pokładzie po całej jeździe", car.aboard(p))
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("wyjście → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	print("[RIDE-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test sieciowy drezyny, strona hosta (--host --mission=z1_m2 --ridehost): czeka na klienta, zasila drezynę
## i obserwuje, czy ruszyła od pompowania KLIENTA (host sam nie wsiada).
func _ride_host_test() -> void:
	var waited := 0.0
	while _players.get_child_count() < 3 and waited < 15.0:      # host + bot + klient
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)
	var car: AnimatableBody2D = get_tree().get_first_node_in_group("handcar")
	var x0: float = car.global_position.x
	for g in get_tree().get_nodes_in_group("generators"):
		g._start()
	for i in 8:
		await get_tree().create_timer(3.0).timeout
		print("[RIDE-HOST] t=%d car.x=%.0f speed=%.0f power=%.1f enabled=%s arrived=%s" % [(i + 1) * 3, car.global_position.x, car.speed, car.power, str(car.enabled), str(car.arrived)])
	var ok: bool = car.global_position.x < x0 - 300.0
	print("[RIDE-HOST] %s (drezyna przejechała %.0f px dzięki pompowaniu klienta)" % ["PASS" if ok else "FAIL", x0 - car.global_position.x])

## Strona klienta (--join=IP --rideclient): po zasileniu drezyny wsiada własnym graczem i pompuje.
func _ride_client_test() -> void:
	var car: AnimatableBody2D = null
	var waited := 0.0
	while waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		car = get_tree().get_first_node_in_group("handcar")
		if car != null and car.enabled:
			break
	if car == null or not car.enabled:
		print("[RIDE-CLIENT] FAIL: drezyna nie została zasilona u klienta")
		return
	var p: Node2D = _players.get_node_or_null(str(multiplayer.get_unique_id()))
	p.global_position = car.global_position + Vector2(10, -8)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	Input.action_press("interact")
	for i in 8:
		await get_tree().create_timer(2.5).timeout
		print("[RIDE-CLIENT] t=%.1f car.x=%.0f speed=%.0f aboard=%s pumping=%s | moja pozycja względem drezyny dx=%.0f" % [(i + 1) * 2.5, car.global_position.x, car.speed, str(car.aboard(p)), str(p.pumping), p.global_position.x - car.global_position.x])
	Input.action_release("interact")

## Test map (--maptest): dla każdej misji kampanii sprawdza kształt siatki i że z punktów startu da się dojść (po grafie
## nawigacji, z uwzględnieniem skoków i spadania) do wszystkich celów, wrogów, przedmiotów i wyjść oraz wrócić na start.
## Test mieszczenia się menu pauzy w każdym języku (--uifittest, tools/test_ui_fit.gd): kończy grę kodem 1 przy błędach.
func _ui_fit_test() -> void:
	await get_tree().process_frame
	var fails: int = await load("res://tools/test_ui_fit.gd").new().run(self)
	get_tree().quit(1 if fails > 0 else 0)

func _map_test() -> void:
	var fails := 0
	var original: String = level.map_id
	for id in level.MAPS.keys():
		level.load_map(id)
		var data = level.MAPS[id]
		var rows: Array = data.MAP
		var w := (rows[0] as String).length()
		var shape_ok := true
		for r in rows:
			if (r as String).length() != w:
				shape_ok = false
		print("[MAPTEST] %s %s: %d x %d, kształt %s" % [id, level.title, w, rows.size(), "OK" if shape_ok else "BŁĄD (różne szerokości wierszy)"])
		if not shape_ok:
			fails += 1
		if level.walls_total() > 0:
			level.open_all_walls_for_test()          # skrytki za zamurowanymi przejściami też muszą być osiągalne po rozbiciu
		var nav: AStar2D = level.nav
		var points: Array = []          # [etykieta, pozycja]
		for i in level.spawns.size():
			points.append(["start %d" % i, level.spawns[i]])
		for i in level.exits.size():
			points.append(["wyjście %d" % i, level.exits[i]])
		for i in level.exits_alt.size():
			points.append(["wyjście po zawale %d" % i, level.exits_alt[i]])
		for g in get_tree().get_nodes_in_group("generators"):
			points.append([String(g.name), g.global_position])
		for car in get_tree().get_nodes_in_group("handcar"):
			points.append(["Drezyna", car.global_position])
		for i in (level._map_items.get("F", []) as Array).size():
			points.append(["Nieśmiertelnik %d" % (i + 1), (level._map_items["F"] as Array)[i]])
		for i in (level._map_items.get("H", []) as Array).size():
			points.append(["Skrytka %d" % (i + 1), (level._map_items["H"] as Array)[i]])
		for b in get_tree().get_nodes_in_group("board"):
			points.append(["Tablica", b.global_position])
		for grp in [["radio_set", "Radiostacja"], ["workshop", "Warsztat"], ["results_wall", "Ściana wyników"]]:       # stanowiska kryjówki (może mieć je na różnych piętrach)
			for n in get_tree().get_nodes_in_group(grp[0]):
				points.append([grp[1], n.global_position])
		for n in get_tree().get_nodes_in_group("nests"):
			points.append([String(n.name), n.global_position])
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.is_in_group("nests") and not e.is_in_group("boss") and str(e.get("kind")) not in ["skoczek", "cma", "<null>"]:
				points.append([String(e.name), e.global_position])
		if level.stalker_home != Vector2.ZERO:
			points.append(["dom Stalkera", level.stalker_home])
		for k in level._map_items:
			for i in (level._map_items[k] as Array).size():
				# broń w gablocie (cabinet.gd) leży do 7,5 px od środka kafla gabloty — rozstawiona na jej szerokości
				points.append(["przedmiot %s%d" % [k, i], level._map_items[k][i], 8.0 if (k == "g" and level._cab_slots > 0) else 2.0])
		var ids := {}
		var bad: Array = []
		for p in points:
			var cid := nav.get_closest_point(p[1])
			if cid < 0 or nav.get_point_position(cid).distance_to(p[1]) > (float(p[2]) if p.size() > 2 else 2.0):
				bad.append("%s nie stoi na podłodze (%s)" % [p[0], str(p[1])])
			ids[p[0]] = cid
		var start_id: int = ids["start 0"]
		for p in points:
			var cid: int = ids[p[0]]
			if cid < 0:
				continue
			if nav.get_id_path(start_id, cid).is_empty():
				bad.append("%s: brak drogi ze startu" % p[0])
			elif nav.get_id_path(cid, start_id).is_empty():
				bad.append("%s: brak drogi powrotnej na start" % p[0])
			# gdzie dojdzie postać, tam musi dojść i dźwięk (siatka propagacji zbudowana i spójna z mapą)
			elif level.sound_grid.route(level.to_local(p[1] - Vector2(0, 8)), level.to_local(level.spawns[0] - Vector2(0, 8))).is_empty():
				bad.append("%s: brak drogi dźwięku ze startu" % p[0])
		if not level.exits.is_empty():           # kryjówka nie ma celów ani wyjścia
			# szacunek długości trasy: start → cele (od lewej) → najdalsze wyjście; sam marsz 95 px/s, bez walki i czekania
			var goals: Array = []
			for p in points:
				if String(p[0]).begins_with("Generator") or String(p[0]).begins_with("Nest") or String(p[0]).begins_with("Nieśmiertelnik"):
					goals.append(p[1])
			if level.boss_home != Vector2.ZERO:
				goals.append(level.boss_home)
			goals.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
			var route := 0.0
			var cur: Vector2 = level.spawns[0]
			for gp in goals:
				route += _nav_len(nav, cur, gp)
				cur = gp
			var far_exit: Vector2 = level.exits[0]
			for ex in level.exits:
				if (ex as Vector2).distance_to(cur) > far_exit.distance_to(cur):
					far_exit = ex
			if not level.exits_alt.is_empty():
				far_exit = level.exits_alt[0]                # finał: wyjście po zawale zamiast powrotu na start
			route += _nav_len(nav, cur, far_exit)
			print("[MAPTEST] %s: trasa start → %d celów → wyjście ≈ %.0f px, sam marsz ≈ %.0f s (%.1f min)" % [id, goals.size(), route, route / 95.0, route / 95.0 / 60.0])
		for b in bad:
			print("[MAPTEST]   BŁĄD: %s" % b)
		fails += bad.size()
		print("[MAPTEST] %s: %d punktów sprawdzonych, błędów %d" % [id, points.size(), bad.size()])
	level.load_map(original)
	print("[MAPTEST] %s (%d błędów)" % ["PASS" if fails == 0 else "FAIL", fails])

## Test Nocnego Dyżuru: przechodzi całą serię (5 × sukces), sprawdza modyfikatory i skalowanie, potem porażkę
## i nową serię. Rekordy w Settings zostają przywrócone. --nightshift --host --shifttest
func _shift_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var best_c: int = Settings.shift_best_cleared
	var best_t: float = Settings.shift_best_time
	var fails := [0]                      # tablica: lambda kopiuje liczby, a tablicę współdzieli
	var check := func(label: String, ok: bool) -> void:
		print("[SHIFT-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])
		if not ok:
			fails[0] += 1
	check.call("start: seria aktywna, misja 1, bez modyfikatorów", NightShift.active and NightShift.stage == 1 and NightShift.mods.is_empty())
	check.call("start: HP wrogów ×1,00", is_equal_approx(NightShift.hp_mult(), 1.0))
	for st in range(1, NightShift.MISSIONS + 1):
		var want: int = NightShift.MODS_PER_MISSION[st - 1]
		check.call("misja %d: %d modyfikatorów (%s), HP ×%.2f" % [st, NightShift.mods.size(), NightShift.mod_names(), NightShift.hp_mult()],
			NightShift.stage == st and NightShift.mods.size() == want and is_equal_approx(NightShift.hp_mult(), 1.0 + NightShift.HP_STEP * (st - 1)))
		mission.elapsed = 60.0
		mission._success()
		check.call("misja %d: sukces zaliczony (%d)" % [st, mission.shift_cleared], mission.shift_cleared == st)
		if st < NightShift.MISSIONS:
			mission.shift_advance()
			_restart_mission(true)
	check.call("po 5 misjach: seria ukończona, czas serii 300 s", mission.shift_complete() and is_equal_approx(mission.shift_time, 300.0))
	mission.shift_advance()
	_restart_mission(true)
	check.call("Enter po serii: nowa seria od misji 1", NightShift.stage == 1 and mission.shift_cleared == 0 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	mission.elapsed = 30.0
	mission._success()
	mission.shift_advance()
	_restart_mission(true)
	mission.elapsed = 12.0
	mission.fail_shift()
	check.call("wipe: seria zakończona (FAILED), 1 misja ukończona", mission.phase == MISSION_SCRIPT.Phase.FAILED and mission.shift_cleared == 1)
	mission.shift_advance()
	_restart_mission(true)
	check.call("Enter po porażce: nowa seria", NightShift.stage == 1 and mission.shift_cleared == 0 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	# modyfikatory: wartości systemowe
	NightShift.mods = ["overload", "famine", "leak", "thin"]
	check.call("modyfikatory: start 50, ammo ×0,5, hałas ×1,5, Stalker 45/15",
		is_equal_approx(NightShift.start_noise(20.0), 50.0) and is_equal_approx(NightShift.ammo_mult(), 0.5)
		and is_equal_approx(NightShift.noise_mult(), 1.5) and is_equal_approx(NightShift.awake_threshold(60.0), 45.0)
		and is_equal_approx(NightShift.sleep_threshold(30.0), 15.0))
	NightShift.mods = []
	Settings.shift_best_cleared = best_c
	Settings.shift_best_time = best_t
	Settings._save()
	print("[SHIFT-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Mapa startowa wymuszona flagą `--mission=ID` (testy headless używają z_1_m3, patrz _handle_cmdline).
var _start_map := ""
## Mapa, do której wyjdzie drużyna z kryjówki (kampania: następna misja po tej, którą właśnie ukończono).
var after_hub := ""
var _departing := false              ## wyjście z kryjówki zaplanowane (odroczone), żeby nie wołać go co tick

## Wspólny koniec startu hosta (ENet i Steam): UI, ambient, nowa misja, gracz hosta.
func _begin_hosting(where: String) -> void:
	_lobby.visible = false
	Audio.play("mission_start", Audio.BUS_UI, -8.0)
	print("[NET] difficulty: %s" % Difficulty.level_name())
	companion_on = Settings.ai_companion
	print("[NET] AI companion: %s" % ("ON" if companion_on else "OFF"))
	if NightShift.selected:
		mission.begin_shift()
	Scrap.load_progress()                # host zaczyna od zapisanego portfela
	if Scrap.cleared.is_empty():
		for m in level.CAMPAIGN:             # zapis sprzed 1.7.392: postęp kampanii z ukończonych misji profilu hosta (jednorazowo)
			if Profile.completed.has(String(m)):
				Scrap.add_cleared(String(m))
	var first_map: String = _start_map if _start_map != "" else ("z1_hub" if _lobby.start_in_hub else (_shift_map() if NightShift.selected else campaign_start_map()))
	if first_map != level.map_id:
		_set_map(first_map)
	if first_map == "z1_hub" and after_hub == "":
		after_hub = campaign_start_map()             # start w kryjówce z lobby: odprawa i „Depart" muszą znać pierwszą misję
	print("[NET] mode: %s" % ("NIGHT SHIFT" if NightShift.active else "CAMPAIGN"))
	_start_ambience()
	NoiseMgr.reset_mission()
	_spawn_player(1)
	print("[NET] hosting on %s" % where)
	mission.log_start.call_deferred()      # pierwsza misja nie przechodzi przez _restart_mission; odroczone, żeby bot już stał

## Steam: peer podpinamy od razu (inaczej się nie odpytuje), a sesję startujemy, gdy lobby
## naprawdę działa (CONNECTION_CONNECTED) — wcześniej NoiseMgr.is_server() jest fałszem.
func _on_steam_hosting(peer: MultiplayerPeer) -> void:
	if NoiseMgr.has_network():
		return
	multiplayer.multiplayer_peer = peer
	var waited := 0.0
	while peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer = null
		_lobby.set_status("Steam lobby did not start in time.", true)
		return
	_begin_hosting("Steam lobby %d" % steam.lobby_id)

func _on_steam_joining(peer: MultiplayerPeer) -> void:
	if NoiseMgr.has_network():
		return
	multiplayer.multiplayer_peer = peer
	_lobby.set_status("Connecting via Steam…")
	Audio.play("radio_beep", Audio.BUS_UI, -10.0)

func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_lobby.set_status("Could not connect (%s)" % error_string(err), true)
		return
	multiplayer.multiplayer_peer = peer
	_lobby.set_status("Connecting to %s…" % ip)
	Audio.play("radio_beep", Audio.BUS_UI, -10.0)


## F2: okno zaproszeń Steam dla bieżącego lobby (host).
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("steam_invite") and steam != null:
		var msg: String = steam.invite()
		if msg != "":
			_lobby.set_status(msg)
			_toast(msg, 7.0)

## Krótki komunikat na górze ekranu (poza lobby, np. w trakcie gry), znika po `secs` s.
func _toast(text: String, secs := 5.0) -> void:
	Msg.post("net.%d" % text.hash(), Msg.Ch.TOAST, text, {"ttl": secs, "style": Msg.Style.WARN, "prio": 70})

func _on_peer_connected(id: int) -> void:
	print("[NET] peer connected: %d" % id)
	if multiplayer.is_server():
		_sync_difficulty.rpc_id(id, Difficulty.level)
		_sync_companion.rpc_id(id, companion_on)
		_load_map_rpc.rpc_id(id, level.map_id)       # mapa zanim pojawi się postać
		level.send_collapse_to(id)                   # zawały, które już się wydarzyły w tej misji
		level.send_walls_to(id)                      # rozbite zamurowane przejścia
		level.send_cabinets_to(id)
		_spawn_player(id)

## AI towarzysz w tej sesji (NOBOT_PLAN.md): serwer bierze go z ustawień hosta (`Settings.ai_companion`), klient dostaje od serwera
## (lobby pokazuje wybór hosta, karta wyniku — „bez bota”). Zmiana tylko poza misją: w lobby i w kryjówce (`companion_editable`).
var companion_on := true

func companion_editable() -> bool:
	if not NoiseMgr.has_network():
		return true
	return multiplayer.is_server() and mission != null and mission.kind == "hub"

func _on_companion_setting() -> void:
	if not NoiseMgr.has_network():
		companion_on = Settings.ai_companion
		return
	if not multiplayer.is_server() or companion_on == Settings.ai_companion or not companion_editable():
		return
	companion_on = Settings.ai_companion
	print("[BOT] AI companion: %s (host, kryjówka)" % ("ON" if companion_on else "OFF"))
	_sync_companion.rpc(companion_on)
	_reconcile_bots()

@rpc("authority", "call_remote", "reliable")
func _sync_companion(on: bool) -> void:
	companion_on = on
	_lobby.show_companion(on, true)
	print("[NET] AI companion (host): %s" % ("ON" if on else "OFF"))

## Trudność ustala host; klient dostaje ją przy dołączeniu (HP wrogów, paski, czasy).
@rpc("authority", "call_remote", "reliable")
func _sync_difficulty(level: int) -> void:
	Difficulty.set_level(level)
	_lobby.lock_difficulty()

func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer disconnected: %d" % id)
	LagComp.forget(id)
	level.forget_weapon_kit(id)
	if not multiplayer.is_server():
		return              # postać wychodzącego usuwa serwer, a MultiplayerSpawner rozsyła to klientom; własne queue_free u klienta wyprzedzało
		                    # ten despawn i silnik zgłaszał „on_despawn_receive … ERR_UNAUTHORIZED” u każdego, kto został w sesji
	var p := _players.get_node_or_null(str(id))
	if p != null:
		p.queue_free()
	_reconcile_bots()

func _on_connected_to_server() -> void:
	_lobby.visible = false
	_start_ambience()
	print("[NET] connected as peer %d" % multiplayer.get_unique_id())


## Podłoże z GDD §13: las + maszyna. Dwie warstwy, obie zapętlone.
## Domyślnie forest (las Obiektu 86 na powierzchni), maszyna w obiekcie.
func _start_ambience() -> void:
	Audio.start_loop("amb_forest", Audio.BUS_AMB, -13.0)
	Audio.start_loop("amb_machine", Audio.BUS_AMB, -20.0)

func _on_connection_failed() -> void:
	_lobby.set_status("Connection failed — check the IP and that the host is running.", true)
	_lobby.visible = true
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	print("[NET] server disconnected")
	_end_session.call_deferred("host_lost", tr("Disconnected from the host."))

func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)):
		return
	level.register_weapon_kit(id)
	var display := _next_display_id()
	var p := _spawner.spawn({"name": str(id), "display": display,
		"pos": _spawn_pos_for(display), "bot": false})
	print("[NET] spawned player %d (display P%d)" % [id, p.display_id])
	_reconcile_bots()

## display_id (P1–P4, kolor slotu w HUD) — nie z liczby graczy (błąd z §19 poz. 6), tylko najniższy wolny numer: człowiek bierze
## najniższy, którego nie ma inny człowiek, bot najwyższy wolny. Wcześniej licznik rósł bez końca, a bot zajmował P2, więc
## czterech ludzi dostawało P1, P3, P4, P5, a P5 miał kolor P1. Gdy 1–4 są zajęte (nie powinno się zdarzyć: MAX_PLAYERS 4 i bot
## znika przy 3+ ludziach) — kolejny numer ponad zajęte.
func _next_display_id(bot := false) -> int:
	var humans := {}
	var taken := {}
	for c in _players.get_children():
		taken[int(c.display_id)] = true            # także usuwane w tej klatce: nowy bot nie może dostać nazwy „bot_N” węzła, który jeszcze jest w drzewie
		if not c.is_bot:
			humans[int(c.display_id)] = true
	var order := range(MAX_PLAYERS, 0, -1) if bot else range(1, MAX_PLAYERS + 1)
	for i in order:
		if not taken.has(i):
			return i
	if not bot:
		for i in range(1, MAX_PLAYERS + 1):
			if not humans.has(i):
				return i
	var top := MAX_PLAYERS
	for k in taken:
		top = maxi(top, int(k))
	return top + 1

## AI towarzysz: wypełnia puste sloty, żeby sesja nie była pusta (GDD §16.3).
## Boty to gracze z is_bot=true, sterowane wyłącznie przez właściciela (serwer/hosta).
func _reconcile_bots() -> void:
	if not NoiseMgr.is_server():
		return
	var humans := 0
	for c in _players.get_children():
		if c is Node2D and not c.is_bot and not (c as Node).dead:
			humans += 1
	var want := _bot_target_count(humans)
	var have := 0
	for c in _players.get_children():
		if c.is_bot:
			have += 1
	if have < want:
		for i in range(want - have):
			_spawn_bot()
	elif have > want:
		# usuń nadmiar botów (ludzie dołączyli)
		for c in _players.get_children():
			if c.is_bot:
				c.queue_free()
				break

func _bot_target_count(humans: int) -> int:
	# solo = 1 bot (gracz + AI); dwa ludzie = 1 bot; 3+ ludzi = 0 botów; host wyłączył towarzysza — 0 (NOBOT_PLAN.md)
	if not companion_on:
		return 0
	if humans <= 1:
		return 1
	if humans == 2:
		return 1
	return 0

## Bot dostaje najwyższy wolny display_id (`_next_display_id(true)`), więc nie zabiera numeru dołączającemu człowiekowi —
## wcześniej numer liczony z ilości graczy kolidował z kolejnym dołączającym (bot i klient = P2).
func _spawn_bot() -> void:
	var slot := _next_display_id(true)
	_spawner.spawn({"name": "bot_%d" % slot, "display": slot,
		"pos": _spawn_pos_for(slot), "bot": true})
	print("[BOT] spawned companion slot %d (display P%d/AI)" % [slot, slot])

## Wołane przez MultiplayerSpawner na serwerze i na każdym kliencie z tymi
## samymi danymi. Autorytet człowieka ustawia player._enter_tree (z nazwy).
func _spawn_actor(data: Dictionary) -> Node:
	var is_bot: bool = data["bot"]
	var scene: PackedScene = load(BOT_SCENE_PATH) if is_bot else PLAYER_SCENE
	var n := scene.instantiate()
	n.name = data["name"]
	n.display_id = data["display"]
	n.position = data["pos"]
	if is_bot:
		n.set_multiplayer_authority(1)  # boty steruje serwer
	return n

## Punkty startu ze znaczników „S" mapy (level.gd).
func _spawn_pos_for(slot: int) -> Vector2:
	return level.spawn_for(slot)
