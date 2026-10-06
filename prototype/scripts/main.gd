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

const MISSION_SCRIPT := preload("res://scripts/mission.gd")
const WEAPON_TEST := preload("res://scripts/weapon_test.gd")
const DREAD := preload("res://scripts/dread.gd")
const STEAM_NET := preload("res://scripts/steam_net.gd")
const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const NightShift := preload("res://scripts/night_shift.gd")

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

# ---------------------------------------------------------------- wipe (GDD §4)

func _physics_process(delta: float) -> void:
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
			_continue_after_result()
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
func _restart_mission(new_run: bool, map_id := "") -> void:
	print("[MISSION] restart (%s)%s" % ["nowa misja" if new_run else "wipe", (" -> " + map_id) if map_id != "" else ""])
	if map_id != "" and map_id != level.map_id:
		_set_map(map_id)
	NoiseMgr.reset_mission()
	Arsenal.reset_mission()
	Director.reset()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("reset_enemy"):
			e.reset_enemy()
	for g in get_tree().get_nodes_in_group("generators"):
		g.reset_generator()
	for c in _players.get_children():
		c.request_full_reset()
	level.clear_pickups()
	mission.on_restart(new_run)

# ---------------------------------------------------------------- mapy / kampania

## [Enter] na ekranie wyniku (host): kolejna misja kampanii (po ostatniej — od początku) albo kolejna misja / nowa seria
## Nocnego Dyżuru. Po porażce w kampanii (nie występuje: wipe = powtórka) zostałaby ta sama mapa.
func _continue_after_result() -> void:
	var next_map := ""
	if NightShift.active:
		mission.shift_advance()
		next_map = _shift_map()
	elif mission.phase == MISSION_SCRIPT.Phase.SUCCESS:
		next_map = _next_campaign_map()
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
	var order: Array = level.CAMPAIGN
	return order[randi() % order.size()]

func _handle_cmdline() -> void:
	var autoquit := -1.0
	var stealthtest := -1.0
	var wipetest := -1.0
	var missiontest := false
	var shifttest := false
	var maptest := false
	var gentest := false
	var weapon_mode := ""
	var shots_dir := ""
	var args := OS.get_cmdline_user_args()
	if args.has("--nightshift"):
		NightShift.selected = true               # przed --host: tryb zapada przy starcie sesji
	for a in args:
		if a.begins_with("--port="):
			port = a.substr("--port=".length()).to_int()
		elif a.begins_with("--mission="):
			_start_map = a.substr("--mission=".length())
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

## Test misji 1.2 (--host --mission=z1_m2 --gentest): trzy generatory (przytrzymanie E), skok Uwagi po ostatnim, ekstrakcja,
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
	check.call("start: mapa 1.2, cel generators, 3 generatory", level.map_id == "z1_m2" and mission.kind == "generators" and mission.goal_total == 3)
	var gens: Array = get_tree().get_nodes_in_group("generators")
	gens.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.x < b.global_position.x)
	for i in gens.size():
		p.global_position = gens[i].global_position + Vector2(-10, 0)
		p.velocity = Vector2.ZERO
		await get_tree().create_timer(0.3).timeout
		Input.action_press("interact")
		await get_tree().create_timer(gens[i].WORK_TIME + 0.8).timeout
		Input.action_release("interact")
		check.call("generator %d uruchomiony, zostało %d" % [i + 1, 2 - i], gens[i].running and mission.goal_left == 2 - i)
		if i == 0:
			check.call("stealth po pierwszym generatorze (szczyt Uwagi %.0f < 40)" % mission.peak_noise, mission.stealth_ok())
	check.call("po 3 generatorach: EXTRACT, Uwaga %.0f (skok do %.0f), Stalker obudzony=%s" % [NoiseMgr.level, mission.BROADCAST_NOISE, str(NoiseMgr.stalker_awake)],
		mission.phase == MISSION_SCRIPT.Phase.EXTRACT and NoiseMgr.level >= 60.0 and NoiseMgr.stalker_awake)
	p.global_position = mission.exit_pos + Vector2(0, -2)
	await get_tree().create_timer(mission.EXTRACT_TIME + 1.0).timeout
	check.call("ekstrakcja → SUCCESS", mission.phase == MISSION_SCRIPT.Phase.SUCCESS)
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	check.call("[Enter] → mapa 1.3 (gniazda), gracz na starcie nowej mapy",
		level.map_id == "z1_m3" and mission.kind == "nests" and mission.goal_total == 4 and mission.phase == MISSION_SCRIPT.Phase.OBJECTIVE
		and p.global_position.distance_to(level.spawn_for(1)) < 40.0 and get_tree().get_nodes_in_group("generators").is_empty())
	mission.elapsed = 5.0
	mission._success()
	_continue_after_result()
	await get_tree().create_timer(0.5).timeout
	check.call("po ostatniej misji kampania wraca do 1.2 (generatory zresetowane)",
		level.map_id == "z1_m2" and mission.goal_left == 3 and gens.size() == 3 and get_tree().get_nodes_in_group("generators").size() == 3)
	print("[GEN-TEST] %s (%d błędów)" % ["PASS" if fails[0] == 0 else "FAIL", fails[0]])

## Test map (--maptest): dla każdej misji kampanii sprawdza kształt siatki i że z punktów startu da się dojść (po grafie
## nawigacji, z uwzględnieniem skoków i spadania) do wszystkich celów, wrogów, przedmiotów i wyjść oraz wrócić na start.
func _map_test() -> void:
	var fails := 0
	var original: String = level.map_id
	for id in level.CAMPAIGN:
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
		var nav: AStar2D = level.nav
		var points: Array = []          # [etykieta, pozycja]
		for i in level.spawns.size():
			points.append(["start %d" % i, level.spawns[i]])
		for i in level.exits.size():
			points.append(["wyjście %d" % i, level.exits[i]])
		for g in get_tree().get_nodes_in_group("generators"):
			points.append([String(g.name), g.global_position])
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

## Wspólny koniec startu hosta (ENet i Steam): UI, ambient, nowa misja, gracz hosta.
func _begin_hosting(where: String) -> void:
	_lobby.visible = false
	Audio.play("oc_load", Audio.BUS_UI, -8.0)
	print("[NET] difficulty: %s" % Difficulty.level_name())
	if NightShift.selected:
		mission.begin_shift()
	var first_map: String = _start_map if _start_map != "" else (_shift_map() if NightShift.selected else level.CAMPAIGN[0])
	if first_map != level.map_id:
		_set_map(first_map)
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
		steam.invite()

func _on_peer_connected(id: int) -> void:
	print("[NET] peer connected: %d" % id)
	if multiplayer.is_server():
		_sync_difficulty.rpc_id(id, Difficulty.level)
		_load_map_rpc.rpc_id(id, level.map_id)       # mapa zanim pojawi się postać
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
