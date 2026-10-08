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
const MISSION_SCRIPT := preload("res://scripts/mission.gd")
const WEAPON_TEST := preload("res://scripts/weapon_test.gd")
const DREAD := preload("res://scripts/dread.gd")
const STEAM_NET := preload("res://scripts/steam_net.gd")
const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Weapons := preload("res://scripts/weapons.gd")
const HORROR_FX := preload("res://scripts/horror_fx.gd")
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
	# obraz horroru (winieta, ziarno, aberracja, ostrzeżenie o zdrowiu) — tylko w grafice HD; `--nofx` wyłącza
	if Sprites.newitem and DisplayServer.get_name() != "headless" and not ("--nofx" in OS.get_cmdline_user_args()):
		var hfx := HORROR_FX.new()
		hfx.name = "HorrorFx"
		add_child(hfx)
		move_child(hfx, $UI.get_index())

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
			else:
				_restart_mission(false)
		return
	# po udanej ekstrakcji (albo końcu serii Nocnego Dyżuru) host zaczyna nową misję
	if mission.phase == MISSION_SCRIPT.Phase.SUCCESS or mission.phase == MISSION_SCRIPT.Phase.FAILED:
		if Input.is_action_just_pressed("restart"):
			_continue_after_result.call_deferred()       # jak wyjście z kryjówki: zmiana mapy poza krokiem fizyki
		return
	if mission.kind == "hub":
		_hub_server_tick(delta)
		return
	if _all_down():
		print("[WIPE] all players down -> mission restart in %.0fs" % WIPE_DELAY)
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
	for car in get_tree().get_nodes_in_group("handcar"):
		car.reset_handcar()
	level.reset_collapse()
	for c in _players.get_children():
		c.request_full_reset(carry)
	level.clear_pickups()
	mission.on_restart(new_run)
	Scrap.reset_loot()                   # wipe / nowa misja: łup z poprzedniej próby przepada (po sukcesie już trafił do banku)
	_departing = false
	hub_ready.clear()
	hub_mine = false
	hub_ready_n = 0
	hub_countdown = -1.0
	if level.objective == "hub":
		NoiseMgr.calm()                  # w kryjówce jest cicho

# ---------------------------------------------------------------- mapy / kampania

# ---------------------------------------------------------------- gotowość w kryjówce

const HUB_COUNTDOWN := 2.0           ## tyle sekund po zgłoszeniu gotowości przez wszystkich ludzi do wyjścia na misję

var hub_ready := {}                  ## serwer: id peera (jako tekst) -> gotowy
var hub_mine := false                ## ten peer: czy jestem gotowy (HUD)
var hub_ready_n := 0                 ## ilu ludzi gotowych / ilu w ogóle (replikowane serwerem do HUD)
var hub_total := 0
var hub_countdown := -1.0            ## < 0: nie odliczamy
var _hub_sync_t := 0.0

## Każdy człowiek w kryjówce przełącza gotowość [Enter]em. Gdy wszyscy ludzie są gotowi, po krótkim odliczaniu
## drużyna rusza na misję; odznaczenie przez kogokolwiek przerywa odliczanie. Boty się nie liczą.
func _hub_input() -> void:
	if mission == null or mission.kind != "hub":
		return
	if hub_countdown > 0.0 and NoiseMgr.has_network() and not multiplayer.is_server():
		hub_countdown = maxf(0.0, hub_countdown - get_physics_process_delta_time())     # klient odlicza sam, serwer w _hub_server_tick
	if not Input.is_action_just_pressed("restart"):
		return
	hub_mine = not hub_mine
	Audio.play("ui_click", Audio.BUS_UI, -8.0)
	if not NoiseMgr.has_network() or multiplayer.is_server():
		_hub_set_ready(NoiseMgr.local_id(), hub_mine)
	else:
		_hub_ready_rpc.rpc_id(1, hub_mine)

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
	var n := 0
	for k in humans:
		if hub_ready.has(k):
			n += 1
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
			_hub_state.rpc(hub_ready.keys(), hub_total, hub_countdown)

@rpc("authority", "call_remote", "reliable")
func _hub_state(ready_ids: Array, total: int, countdown: float) -> void:
	hub_ready_n = ready_ids.size()
	hub_total = total
	hub_countdown = countdown
	hub_mine = ready_ids.has(str(multiplayer.get_unique_id()))

## Wyjście z kryjówki (wszyscy ludzie gotowi): wyjście do kolejnej misji kampanii z zachowanym ekwipunkiem.
func _depart_hub() -> void:
	var target := after_hub if after_hub != "" else String(level.CAMPAIGN[0])
	after_hub = ""
	_restart_mission(true, target, true)

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
	mission.rebind()
	print("[MISSION] map: %s (%s)" % [level.map_id, level.title])

func _next_campaign_map() -> String:
	var order: Array = level.CAMPAIGN
	return order[(order.find(level.map_id) + 1) % order.size()]

## Nocny Dyżur: każda misja serii na losowej mapie z kampanii.
func _shift_map() -> String:
	var order: Array = level.SHIFT_POOL
	return order[randi() % order.size()]

func _handle_cmdline() -> void:
	var autoquit := -1.0
	var stealthtest := -1.0
	var wipetest := -1.0
	var missiontest := false
	var shifttest := false
	var maptest := false
	var ridetest := false
	var ridehost := false
	var rideclient := false
	var gentest := false
	var tagtest := false
	var sneaktest := false
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
	if Settings.hd_active():                          # ustawienie „Graphics: HD" (domyślnie) — flagi poniżej mogą nadpisać; `--classic` wyłącza
		Sprites.newchar = "tripo-hd-look"
		Sprites.newgun = true
		Sprites.newmon = true
		Sprites.newitem = true
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
		if a == "--newgun":
			Sprites.newgun = true                                                                  # dev: sprite HD broni (gunhd_*.png)
		if a == "--newchar" or a.begins_with("--newchar="):
			Sprites.newchar = "mix" if a == "--newchar" else a.substr("--newchar=".length())     # dev: postacie 3D zamiast player_N
		if a.begins_with("--port="):
			port = a.substr("--port=".length()).to_int()
		elif a.begins_with("--mission="):
			_start_map = a.substr("--mission=".length())
	if hd_world:
		Sprites.newworld = true
		level.enable_world_hd()
	# testy headless zakładają mapę 1.3 (gniazda, boss), chyba że flaga --mission wskaże inną
	if _start_map == "":
		for a in args:
			if a.begins_with("--stealthtest") or a.begins_with("--wipetest") or a == "--missiontest" or a == "--shifttest" \
					or a == "--weapontest" or a.begins_with("--weaponshots=") or a == "--weaptestnet" or a == "--weaptestclient":
				_start_map = "z1_m3"
	for a in args:
		if a == "--host":
			host_game()
		elif a.begins_with("--join="):
			join_game(a.substr("--join=".length()))
		elif a == "--steam-host":
			steam.host.call_deferred()
		elif a.begins_with("--steam-join="):
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
		elif a == "--shifttest":
			shifttest = true
		elif a == "--maptest":
			maptest = true
		elif a == "--gentest":
			gentest = true
		elif a == "--tagtest":
			tagtest = true
		elif a == "--sneaktest":
			sneaktest = true
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
		elif a == "--shotresult":
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
	if gentest:
		_gen_test()
	if tagtest:
		_tag_test()
	if sneaktest:
		_sneak_test()
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
		get_tree().quit()

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
		c.deliver_hit(99, c.global_position)
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
	get_tree().quit()

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
	get_tree().quit()

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
	var times: Array[float] = []
	var proc_t := 0.0
	var pairs := 0.0
	var active_o := 0.0
	var phys_t := 0.0
	var calls := 0.0
	var prims := 0.0
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	var fxs := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perffx="):
			fxs = a.substr("--perffx=".length())          # casing,blood,gibs,smoke — sztuczny ruch efektów walki (rzędy wielkości jak przy ogniu ciągłym)
	var fx_acc := {"casing": 0.0, "blood": 0.0, "gibs": 0.0}
	var vfx := load("res://scripts/vfx.gd")
	var pf: Node2D = _players.get_node_or_null("1")
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		var dt_s := float(now - last) / 1e6
		last = now
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
	print("[PERF] frames=%d avg=%.2f ms (%.0f fps) p50=%.2f p95=%.2f max=%.2f  draw_calls=%.0f prims=%.0f  nodes=%d  vram=%.1f MB  tex_mem=%.1f MB  idle=%.2f ms phys=%.2f ms  A*=%.0f/s (%.2f ms/frame) enemy_phys=%.2f ms slide=%.2f ms pairs=%.0f active=%.0f" % [
		n, sum / float(maxi(n, 1)), 1000.0 / maxf(sum / float(maxi(n, 1)), 0.001), times[n / 2], times[int(float(n) * 0.95)], times[n - 1],
		calls / float(maxi(n, 1)), prims / float(maxi(n, 1)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		proc_t / float(maxi(n, 1)) * 1000.0, phys_t / float(maxi(n, 1)) * 1000.0, float(NavGraph.stat_calls) / secs, float(NavGraph.stat_usec) / 1000.0 / float(maxi(n, 1)), float(ENEMY.stat_usec) / 1000.0 / float(maxi(n, 1)), float(ENEMY.stat_slide_usec) / 1000.0 / float(maxi(n, 1)), pairs / float(maxi(n, 1)), active_o / float(maxi(n, 1))])
	get_tree().quit()

func _take_shot(path: String, col: int, delay: float = 1.5, depart := false, flicker := false, demo := false, workshop := false, result := false, boss := false, codex := false) -> void:
	Profile.persist = false              # zrzuty dev nie zapisują profilu gracza (XP z podglądu karty wyniku itp.)
	await get_tree().create_timer(1.0).timeout
	if codex:
		var pm: Node = $UI.get_node("PauseMenu")             # podgląd bestiariusza: ostatni wpis (boss)
		pm.open()
		pm._show_tab(1)
		var bp: Node = pm._pages[1]
		var ci: int = bp._entries.size() - 1
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--codexentry="):
				ci = clampi(int(a.substr("--codexentry=".length())), 0, bp._entries.size() - 1)       # dev: wpis bestiariusza do zrzutu
		bp.select(ci)
	if "--shotperkcard" in OS.get_cmdline_user_args():
		Profile.reset_for_test()                      # --shotperkcard: karta PERKS w menu pauzy (L4, Smith w slocie 1)
		Profile.add_xp(800, "demo")
		Profile.equip(0, "smith")
		var ppm: Node = $UI.get_node("PauseMenu")
		ppm.open()
		ppm._show_tab(4)
		(ppm._pages[4]).select(3)
	if _has_arg_prefix("--shotweapons"):
		var wpm: Node = $UI.get_node("PauseMenu")           # --shotweapons[=N]: karta WEAPONS kodeksu (wpis N, domyślnie P-64)
		wpm.open()
		wpm._show_tab(2)
		var wi := 2
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shotweapons="):
				wi = int(a.substr("--shotweapons=".length()))
		(wpm._pages[2]).select(wi)
	if "--shotgear" in OS.get_cmdline_user_args():
		var gpm: Node = $UI.get_node("PauseMenu")           # --shotgear: karta GEAR kodeksu (mina)
		gpm.open()
		gpm._show_tab(3)
		(gpm._pages[3]).select(3)
	if boss:
		mission._start_boss()               # podgląd walki z bossem: budzi bossa i rzuca flarę nad jego cień
		await get_tree().create_timer(0.6).timeout
		var bs := get_tree().get_first_node_in_group("boss")
		if bs != null:
			level.spawn_flare(Vector2(bs.global_position.x + 30.0, bs.global_position.y - 20.0), Vector2.ZERO)
			if "--shottide" in OS.get_cmdline_user_args() and bs.has_method("_tick_surge"):
				bs.phase = 2                         # --shottide: od razu faza 2 i fala przypływu (zapowiedź ~2 s, potem wysoka woda)
				bs._surge_cd = 0.05
			if "--shotup" in OS.get_cmdline_user_args() and bs.has_method("_surface"):
				bs.call("_surface")         # --shotup: Pijawka od razu wynurzona (podgląd arkusza, z chwytem, jeśli gracz stoi w zasięgu)
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
	if "--shothurt" in OS.get_cmdline_user_args():
		var hp1: Node2D = _players.get_node_or_null("1")       # --shothurt: gracz 1 z 1 HP (podgląd ran na ciele i ostrzeżenia obrazem)
		if hp1 != null:
			hp1.hp = 1
			NoiseMgr.level = 60.0
	if "--shottoast" in OS.get_cmdline_user_args():
		_toast("Steam overlay unavailable (start the game from Steam / add it as a non-Steam game). Lobby ID 109775240944 copied — send it to friends: paste + STEAM JOIN.", 20.0)      # --shottoast: podgląd komunikatu F2
	if "--shothandcar" in OS.get_cmdline_user_args():
		var hc := get_tree().get_first_node_in_group("handcar")       # --shothandcar: drezyna zasilona i oświetlona flarą (podgląd HD; użyj z --shotat/--shotrow)
		if hc != null:
			hc.enabled = true
			level.spawn_flare(hc.global_position + Vector2(-20.0, -40.0), Vector2.ZERO)
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
			var items := [["scrap", 0, 8], ["scrap", 0, 3], ["stash", 0, 20], ["tag", 0, 0], ["cache", 0, 0]] if "--shotitems2" in OS.get_cmdline_user_args() else [["health", 0, 0], ["ammo", Weapons.M83, 30], ["ammo", Weapons.SPREAD12, 8], ["scrap", 0, 3], ["scrap", 0, 8], ["cache", 0, 0], ["flares", 0, 2],
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
			level.spawn_flare(mp.global_position + Vector2(190.0, -26.0), Vector2.ZERO)
			for pl in _players.get_children():
				if pl.get("is_bot") == true:
					pl.queue_free()                 # bez bota — żeby nie rozstrzelał podglądu
			for sp in spots:
				level._add_enemy(sp[0], sp[1], mp.global_position + Vector2(float(sp[2]), 0.0))
				var en: Node = level.get_node_or_null(String(sp[0]))
				if en != null:
					en.set_physics_process(false)
					if sp[0] != "ShotT2":
						en.call("wake")
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
	if "--shotfire" in OS.get_cmdline_user_args():
		var fp: Node2D = _players.get_node_or_null("1")      # --shotfire: trzy plamy ognia HKM-9 przed graczem (podgląd)
		if fp != null:
			for i in 3:
				level.spawn_fire_patch(fp.global_position + Vector2(44.0 + 22.0 * float(i), -1.0), Weapons.HKM9, 1)
	if result:
		mission.elapsed = 214.0
		mission._success()                 # podgląd karty wyniku
	if workshop:
		# podgląd panelu warsztatu: portfel, jedna kupiona broń i ulepszenia (tylko w pamięci; zapis wyłączony w trybie podglądu)
		Scrap.persist = false
		Scrap.bank = 480
		Scrap.unlocked[Weapons.LR7] = true
		Scrap.levels[Weapons.M83] = 2
		Scrap.levels[Weapons.LR7] = 1
		var wp: Node2D = _players.get_node_or_null("1")
		if wp != null:
			wp.global_position = Vector2(31.0 * 16.0 + 8.0, 39.0 * 16.0)
		await get_tree().create_timer(0.5).timeout
		var wui := get_tree().get_first_node_in_group("workshop_ui")
		if wui != null:
			wui.open()
			if "--shotsup" in OS.get_cmdline_user_args():
				wui._set_page(1)                     # --shotsup: zakładka SUPPLIES panelu warsztatu
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
	if flicker:
		Lights.flicker_until_ms = Time.get_ticks_msec() + int(delay * 1000.0) + 3000      # podgląd efektu migotania świateł (dread.gd)
	await get_tree().create_timer(delay).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit()

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
	get_tree().quit()

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
	check.call("walka: Pijawka obudzona, faza BOSS, HP %.0f (≥ 5000)" % lc.hp, lc.state == lc.State.AWAKE and mission.phase == MISSION_SCRIPT.Phase.BOSS and lc.hp >= 5000.0)
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
		float(de["hp"]) < float(dn["hp"]) and float(dn["hp"]) < float(dh["hp"]) and absf(float(dn["hp"]) - 5000.0) < 0.5 and float(dh["hp"]) >= 6500.0
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

## Test misji 1.1 (--host --mission=z1_m1 --tagtest): trzy nieśmiertelniki, ekstrakcja, wipe (nieśmiertelniki wracają),
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
	check.call("start: mapa 1.1, cel tags, 3 nieśmiertelniki (cel %d, na ziemi %d)" % [mission.goal_total, tags_now.call().size()],
		level.map_id == "z1_m1" and mission.kind == "tags" and mission.goal_total == 3 and tags_now.call().size() == 3 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
	check.call("odprawa: tytuł, 3 nieśmiertelniki, Trzoski %d, Wołki %d, bez Stalkera i bossa" % [int(counts.get("trzosek", 0)), int(counts.get("wolek", 0))],
		String(brief["title"]) != "" and int(brief["tags"]) == 3 and int(counts.get("trzosek", 0)) >= 8 and int(counts.get("wolek", 0)) >= 2 and not bool(brief["stalker"]) and not bool(brief["boss"]))
	var gallery: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return e is CharacterBody2D and e.global_position.y > 45.0 * 16.0)
	var scrap_caches := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "scrap")
	var gallery_nav: Array = level.nav.find_path(Vector2(166.0 * 16.0 + 8.0, 42.0 * 16.0), Vector2(145.0 * 16.0 + 8.0, 51.0 * 16.0))
	check.call("podziemia: dolna galeria (wrogów %d, skrytek złomu na mapie %d), droga z sali szybem serwisowym (%d węzłów)" % [gallery.size(), scrap_caches.size(), gallery_nav.size()],
		gallery.size() >= 8 and scrap_caches.size() >= 5 and not gallery_nav.is_empty())
	# przedmioty nie wpadają w ściany: podskok w stronę skały zatrzymuje się przed nią, a przedmiot zaczęty w skale jest wypychany
	level.spawn_item("health", 0, Vector2(44.0, 30.0 * 16.0 - 10.0))
	var wall_item := level.get_node_or_null("Item%d" % level._pickup_serial)
	if wall_item != null:
		wall_item._vel = Vector2(-600.0, -120.0)
	level.spawn_item("health", 0, Vector2(16.0, 30.0 * 16.0))
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
	check.call("nieśmiertelnik 1: zostało %d / %d, faza %d" % [mission.goal_left, mission.goal_total, mission.phase], mission.goal_left == 2 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE and tags_now.call().size() == 2)
	# wipe: misja wraca na start, nieśmiertelniki wracają
	_restart_mission(false)
	await get_tree().create_timer(0.8).timeout
	check.call("wipe: nieśmiertelniki wróciły (%d na ziemi, cel %d/%d, próba %d)" % [tags_now.call().size(), mission.goal_left, mission.goal_total, mission.attempts],
		tags_now.call().size() == 3 and mission.goal_left == 3 and mission.attempts == 2 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
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
	for i in 3:
		var near: Array = tags_now.call()
		near.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
		p.global_position = (near[0] as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
	check.call("3 nieśmiertelniki → EXTRACT (zostało %d, faza %d), wyjście po zawale przy szybie (x=%.0f)" % [mission.goal_left, mission.phase, mission.exit_pos.x],
		mission.goal_left == 0 and mission.phase == MISSION_SCRIPT.Phase.EXTRACT and mission.exit_pos.x > 2900.0)
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
	var ledge: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return e.get("kind") == "trzosek" and e.global_position.x > 1400.0 and e.global_position.x < 1700.0)
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
	p.global_position = Vector2(2300.0, 41.0 * 16.0)
	p.flashlight = false
	hh._collect(p)
	check.call("podpowiedź light: gracz w podziemiach bez latarki", hh._queued.has("light"))
	print("[SNEAK-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test finału misji 1.1 (--host --mission=z1_m1 --finaletest): po trzecim nieśmiertelniku wstrząs, zawał rampy (kafle zamieniają się
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
	check.call("dane finału w mapie 1.1: obszar zawału (%d) i wyjście „e” (%d)" % [level.collapse_rects.size(), level.exits_alt.size()],
		level.collapse_rects.size() == 1 and level.exits_alt.size() == 1)
	var hall := Vector2(166.0 * 16.0 + 8.0, 42.0 * 16.0)
	var start: Vector2 = level.spawns[0]
	var ramp_pre := Vector2(146.0 * 16.0 + 8.0, 37.0 * 16.0)
	var area := Rect2(150.0 * 16.0, 33.0 * 16.0, 8.0 * 16.0, 9.0 * 16.0)
	var through := func(path: Array) -> bool:           # czy trasa przechodzi przez obszar zawału
		for n in path:
			if area.has_point(n.pos):
				return true
		return false
	check.call("przed zawałem: rampa wolna (%s), droga z sali w górę rampy biegnie przez nią" % level._ch(152, 38),
		not level._is_solid(152, 38) and through.call(level.nav.find_path(hall, ramp_pre)))
	var tags_now := func() -> Array: return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "tag" and not n.is_queued_for_deletion())
	for i in 3:
		var near: Array = tags_now.call()
		near.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.x < b.global_position.x)
		p.global_position = (near[0] as Node2D).global_position + Vector2(0, -4)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.8).timeout
	check.call("trzeci nieśmiertelnik → finał (finale=%s, faza %d), wyjście po drugiej stronie (x=%.0f)" % [str(mission.finale), mission.phase, mission.exit_pos.x],
		mission.finale and mission.phase == MISSION_SCRIPT.Phase.EXTRACT and mission.exit_pos.x > 2900.0)
	# gracz „uwięziony" w obszarze zawału: ma wylądować za skałą (po stronie sali)
	p.global_position = Vector2(153.0 * 16.0, 40.0 * 16.0)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(2.6).timeout
	check.call("po zawale: rampa to skała (%s), trasa grafu z sali na rampę nie przechodzi przez zawał (idzie szybem i górą), gracz za skałą (x=%.0f)" % [level._ch(152, 38), p.global_position.x],
		level._is_solid(152, 38) and not through.call(level.nav.find_path(hall, ramp_pre)) and p.global_position.x > 158.0 * 16.0)
	var shaft_path: Array = level.nav.find_path(hall, level.exits_alt[0])
	check.call("po zawale: z sali da się wspiąć szybem do flary (ścieżka %d węzłów)" % shaft_path.size(), not shaft_path.is_empty())
	check.call("radio patrolu: linie 0 s / 3 s / 6 s / 9 s i cisza po %.1f s" % mission.FINALE_RADIO_END,
		mission.radio_line_at(0.0).begins_with("…Seven") and mission.radio_line_at(3.5).contains("mine") and mission.radio_line_at(6.5).contains("shaft")
		and mission.radio_line_at(9.5).contains("flare") and mission.radio_line_at(mission.FINALE_RADIO_END) == "" and mission.radio_line_at(-1.0) == "")
	check.call("radio na HUD tylko w finale (clock %.1f, linia '%s')" % [mission.finale_clock, mission.finale_radio_line().substr(0, 20)], mission.finale and mission.finale_radio_line() != "")
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ewakuacja przy nowym wyjściu → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	_restart_mission(true)
	await get_tree().create_timer(0.8).timeout
	check.call("restart: radio zresetowane", mission.finale_radio_line() == "" and mission.finale_clock == 0.0)
	check.call("restart: rampa znów wolna, droga wraca, finał zresetowany (finale=%s)" % str(mission.finale),
		not level._is_solid(152, 38) and through.call(level.nav.find_path(hall, ramp_pre)) and not mission.finale and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE)
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
	var foes: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not (e is RigidBody2D) and not e.is_in_group("range_targets"))      # rekwizyty (skrzynie) też są w tej grupie
	check.call("[Enter] po 1.2 → kryjówka (następna: %s, wrogów %d)" % [after_hub, foes.size()],
		level.map_id == "z1_hub" and mission.kind == "hub" and after_hub == "z1_m3" and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE
		and foes.is_empty() and p.global_position.distance_to(level.spawn_for(1)) < 40.0)
	var racks := 0
	var lamps := 0
	for c in level.get_children():
		if String(c.name).begins_with("Rack"):
			racks += 1
		elif String(c.name).begins_with("Lamp"):
			lamps += 1
	var brief: Dictionary = level.briefing(after_hub)
	check.call("kryjówka: 8 stojaków, 9 lamp, tablica, ciepły ambient (%.2f)" % level.ambient.r,
		racks == 8 and lamps == 9 and get_tree().get_nodes_in_group("board").size() == 1 and level.ambient.r > 0.1)
	check.call("odprawa następnej misji (%s): tytuł, cel, %d rodzajów wrogów, %d gniazd, boss=%s" % [after_hub, (brief["counts"] as Dictionary).size(), int(brief["nests"]), str(brief["boss"])],
		String(brief["title"]) != "" and String(brief["brief"]) != "" and (brief["counts"] as Dictionary).has("trzosek") and int(brief["nests"]) == 4 and bool(brief["boss"]))
	# kryjówka jest bezpieczna: wymuszamy warunki, w których Dyrektor grozy dosypałby wędrowców, i sprawdzamy, że nikt się nie pojawia
	Director._spawn_t = 0.0
	Director._since_enc = 999.0
	Director._relax_t = 0.0
	Director.stress = 0.0
	await get_tree().create_timer(2.0).timeout
	var roamers: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return String(e.name).begins_with("Roamer"))
	var live_foes: Array = get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not (e is RigidBody2D) and not e.is_in_group("range_targets"))
	var rts := get_tree().get_nodes_in_group("range_targets")
	var rt_ok := rts.size() == 1 and get_tree().get_nodes_in_group("range_line").size() == 1
	if rt_ok:
		var tgt: Node2D = rts[0]
		var wid: int = p.weapons.loadout[0]
		var body := Combat.apply(tgt, Combat.make_info(wid, 10.0, tgt.global_position + Vector2(0, -10), Vector2.RIGHT, 1, "bullet"))
		var head := Combat.apply(tgt, Combat.make_info(wid, 10.0, Vector2(tgt.global_position.x, tgt.head_y() - 2.0), Vector2.RIGHT, 1, "bullet"))
		rt_ok = bool(body["hit"]) and not bool(body["killed"]) and bool(head["hit"]) and (bool(head["crit"]) or Weapons.def(wid).crit_mult <= 1.0) and tgt.distance_m > 0.0
	check.call("strzelnica: linia + tarcza (%s), tarcza przyjmuje trafienia, nie ginie, głowa = crit, ma odległość" % ", ".join(rts.map(func(t: Node) -> String: return "%dm" % int(t.distance_m))), rt_ok)

	# warsztat (faza B złomu): ława, panel, zablokowane stojaki, zakup
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
	p.global_position = wk_node.global_position + Vector2(0, -2)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	wui.open()
	await get_tree().create_timer(0.3).timeout
	var tiles: Array = wui._tiles
	(tiles[3] as Button).pressed.emit()
	var opened_ok: bool = wui.is_open() and tiles.size() == 12 and wui._sel == 3 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
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
	var tab_ev := InputEventKey.new()
	tab_ev.keycode = KEY_TAB
	tab_ev.pressed = true
	wui._input(tab_ev)
	var tab_to_look: bool = wui._page == 3                              # 2 → 3 (LOOK)
	wui._input(tab_ev)
	var tab_wrapped: bool = tab_to_look and wui._page == 0              # 3 → 0
	wui._set_page(0)
	var pm_node: Node = $UI.get_node("PauseMenu")
	check.call("zakładka PERKS: %d kafli, załóż → %s, zdejmij → %s, perk L6 przy L4 zablokowany → %s, Tab przechodzi PERKS → LOOK → ARMS → %s; menu pauzy ma %d kart, kodeks %d perków" % [perk_tiles_n, str(perk_on), str(perk_off), str(perk_locked), str(tab_wrapped), pm_node._pages.size(), Codex.perks().size()],
		perk_tiles_n == 8 and perk_on and perk_off and perk_locked and tab_wrapped and pm_node._pages.size() == 6 and Codex.perks().size() == 8)
	Profile.reset_for_test()
	wui.close()
	check.call("panel warsztatu: otwiera się przy ławie, 12 kafli, kliknięcie kafla wybiera broń (sel %d), mysz widoczna; po zamknięciu zamknięty" % wui._sel, opened_ok and not wui.is_open())
	# faza C: ulepszenia
	results.clear()
	var base_mag: int = Weapons.base_def(Weapons.M83).mag
	var base_dmg: float = Weapons.base_def(Weapons.M83).damage
	var base_nmax: float = Weapons.base_def(Weapons.M83).n_max
	Scrap.bank = 10
	Scrap.request_upgrade(Weapons.M83)                 # poor
	Scrap.request_upgrade(Weapons.HKM9)                # locked (nie kupiona)
	Scrap.request_upgrade(Weapons.COUNT)               # invalid (nieistniejąca broń)
	Scrap.bank = 1000
	for i in 4:
		Scrap.request_upgrade(Weapons.M83)             # 3 × ok, potem max
	Scrap.purchase_result.disconnect(cb)
	var rs := results.map(func(r: Array) -> String: return String(r[2]))
	var ed: RefCounted = Weapons.def(Weapons.M83)
	check.call("ulepszenia: poor / locked / invalid / 3×ok / max: %s, portfel %d" % [str(rs), Scrap.bank],
		rs == ["up_poor", "up_locked", "up_invalid", "up_ok", "up_ok", "up_ok", "up_max"] and Scrap.bank == 1000 - 60 - 120 - 220 and Scrap.level_of(Weapons.M83) == 3)
	check.call("ulepszenia: M-83 T3 = magazynek %d→%d, obrażenia %.1f→%.2f, hałas %.2f→%.2f; baza nietknięta" % [base_mag, ed.mag, base_dmg, ed.damage, base_nmax, ed.n_max],
		ed.mag == base_mag + 10 and is_equal_approx(ed.damage, base_dmg * 1.15) and is_equal_approx(ed.n_max, base_nmax * 0.7)
		and Weapons.base_def(Weapons.M83).mag == base_mag and Weapons.def(Weapons.SPREAD12) == Weapons.base_def(Weapons.SPREAD12))
	var cat := Codex.weapon_entry(Weapons.M83)
	var cat_lr := Codex.weapon_entry(Weapons.SOKOL6)
	var tier_states := (cat["tiers"] as Array).map(func(t: Dictionary) -> int: return int(t["state"]))
	check.call("katalog broni: M-83 pokazuje 3 poziomy (stany %s, tag '%s'), zablokowana broń ma informację o dostępie ('%s')" % [str(tier_states), cat["tag"], (cat_lr["access"] as String)],
		tier_states == [0, 0, 0] and (cat["tag"] as String).contains("TIER 3 / 3") and (cat_lr["access"] as String).begins_with("Locked"))
	Scrap.levels.clear()
	Scrap.unlocked.clear()
	Scrap.bank = saved_bank
	var wall_nodes := get_tree().get_nodes_in_group("results_wall")
	check.call("ściana wyników: stoi w kryjówce, zapisała misję 1.2 (%d wpis, %s)" % [RunLog.entries.size(), str(RunLog.entries.back()) if not RunLog.entries.is_empty() else "-"],
		wall_nodes.size() == 1 and RunLog.entries.size() >= 1 and String(RunLog.entries.back()["id"]) == "z1_m2" and float(RunLog.entries.back()["time"]) >= 0.0 and int(RunLog.entries.back()["stealth"]) >= 0)
	check.call("kryjówka: Dyrektor nie dosypuje wrogów (wędrowców %d, wrogów %d)" % [roamers.size(), live_foes.size()], roamers.is_empty() and live_foes.is_empty())
	check.call("ekwipunek i amunicja przechodzą do kryjówki", p.weapons.loadout == loadout_before and Arsenal.get_reserve(Weapons.def(loadout_before[0]).id) == ammo_before)
	await get_tree().create_timer(2.5).timeout
	check.call("kryjówka: bez gotowości nie ruszamy (%d/%d)" % [hub_ready_n, hub_total], level.map_id == "z1_hub" and hub_countdown < 0.0)
	_hub_set_ready(NoiseMgr.local_id(), true)
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: wszyscy ludzie gotowi → odliczanie (%.1f s, %d/%d)" % [hub_countdown, hub_ready_n, hub_total], level.map_id == "z1_hub" and hub_countdown > 0.0 and hub_ready_n == hub_total and hub_total >= 1)
	_hub_set_ready(NoiseMgr.local_id(), false)
	await get_tree().create_timer(0.5).timeout
	check.call("kryjówka: odznaczenie przerywa odliczanie", level.map_id == "z1_hub" and hub_countdown < 0.0)
	_hub_set_ready(NoiseMgr.local_id(), true)
	await get_tree().create_timer(HUB_COUNTDOWN + 1.0).timeout
	await get_tree().create_timer(0.5).timeout
	check.call("ambient po wyjściu z kryjówki wraca do domyślnego (%.3f)" % level.ambient.r, level.ambient.r < 0.05)
	check.call("[Enter] w kryjówce → mapa 1.3 (gniazda), ekwipunek zachowany",
		level.map_id == "z1_m3" and mission.kind == "nests" and mission.goal_total == 4 and p.weapons.loadout == loadout_before
		and Arsenal.get_reserve(Weapons.def(loadout_before[0]).id) == ammo_before and get_tree().get_nodes_in_group("generators").is_empty())
	mission.elapsed = 5.0
	mission._success()
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	check.call("po 1.3 kryjówka, następna: B1 Pijawka (boss zamyka Strefę I)", level.map_id == "z1_hub" and after_hub == "z1_b1")
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
	check.call("wyjście z kryjówki → 1.1 (3 nieśmiertelniki, bez generatorów)",
		level.map_id == "z1_m1" and mission.kind == "tags" and mission.goal_left == 3 and mission.goal_total == 3 and get_tree().get_nodes_in_group("generators").is_empty())
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
		for n in get_tree().get_nodes_in_group("nests"):
			points.append([String(n.name), n.global_position])
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.is_in_group("nests") and not e.is_in_group("boss") and str(e.get("kind")) not in ["skoczek", "cma", "<null>"]:
				points.append([String(e.name), e.global_position])
		if level.stalker_home != Vector2.ZERO:
			points.append(["dom Stalkera", level.stalker_home])
		for k in level._map_items:
			for i in (level._map_items[k] as Array).size():
				points.append(["przedmiot %s%d" % [k, i], level._map_items[k][i]])
		var ids := {}
		var bad: Array = []
		for p in points:
			var cid := nav.get_closest_point(p[1])
			if cid < 0 or nav.get_point_position(cid).distance_to(p[1]) > 2.0:
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
	Audio.play("oc_load", Audio.BUS_UI, -8.0)
	print("[NET] difficulty: %s" % Difficulty.level_name())
	if NightShift.selected:
		mission.begin_shift()
	var first_map: String = _start_map if _start_map != "" else ("z1_hub" if _lobby.start_in_hub else (_shift_map() if NightShift.selected else level.CAMPAIGN[0]))
	Scrap.load_progress()                # host zaczyna od zapisanego portfela
	if first_map != level.map_id:
		_set_map(first_map)
	if first_map == "z1_hub" and after_hub == "":
		after_hub = String(level.CAMPAIGN[0])        # start w kryjówce z lobby: odprawa i „Depart" muszą znać pierwszą misję
	print("[NET] mode: %s" % ("NIGHT SHIFT" if NightShift.active else "CAMPAIGN"))
	_start_ambience()
	NoiseMgr.reset_mission()
	_spawn_player(1)
	print("[NET] hosting on %s" % where)

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
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F2 and steam != null:
		var msg: String = steam.invite()
		if msg != "":
			_lobby.set_status(msg)
			_toast(msg, 7.0)

## Krótki komunikat na górze ekranu (poza lobby, np. w trakcie gry), znika po `secs` s.
func _toast(text: String, secs := 5.0) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 7)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 2)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -170.0
	l.offset_right = 170.0
	l.offset_top = 62.0
	l.offset_bottom = 100.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(l)
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _on_peer_connected(id: int) -> void:
	print("[NET] peer connected: %d" % id)
	if multiplayer.is_server():
		_sync_difficulty.rpc_id(id, Difficulty.level)
		_load_map_rpc.rpc_id(id, level.map_id)       # mapa zanim pojawi się postać
		level.send_collapse_to(id)                   # zawały, które już się wydarzyły w tej misji
		level.send_walls_to(id)                      # rozbite zamurowane przejścia
		_spawn_player(id)

## Trudność ustala host; klient dostaje ją przy dołączeniu (HP wrogów, paski, czasy).
@rpc("authority", "call_remote", "reliable")
func _sync_difficulty(level: int) -> void:
	Difficulty.set_level(level)
	_lobby.lock_difficulty()

func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer disconnected: %d" % id)
	LagComp.forget(id)
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
	# ambient, serce, szept i muzyka grałyby dalej nad lobby
	Audio.stop_all()
	for c in _players.get_children():
		c.queue_free()
	multiplayer.multiplayer_peer = null
	_lobby.visible = true
	_lobby.set_status("Disconnected from the host.", true)

func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)):
		return
	var display := _next_display_id()
	var p := _spawner.spawn({"name": str(id), "display": display,
		"pos": _spawn_pos_for(display), "bot": false})
	print("[NET] spawned player %d (display P%d)" % [id, p.display_id])
	_reconcile_bots()

## display_id jest stabilny wobec dołączania/rozłączania — nadawany z licznika,
## nie z ilości graczy (błąd z §19 poz. 6).
var _display_counter := 0

func _next_display_id() -> int:
	_display_counter += 1
	return _display_counter

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
	# solo = 1 bot (gracz + AI); dwa ludzie = 1 bot; 3+ ludzi = 0 botów
	if humans <= 1:
		return 1
	if humans == 2:
		return 1
	return 0

## Bot dostaje display_id z tego samego licznika co ludzie — wcześniej numer
## liczony z ilości graczy kolidował z kolejnym dołączającym (bot i klient = P2).
func _spawn_bot() -> void:
	var slot := _next_display_id()
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
