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

## >0 w trakcie odliczania do restartu po wipe; widoczne na każdym peerze (HUD).
var wipe_left := 0.0
## Pętla misji: cel → ekstrakcja → wynik (mission.gd). Węzeł o stałej nazwie,
## tworzony na każdym peerze, więc RPC trafia w tę samą ścieżkę.
var mission: Node2D

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
	_setup_post()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_lobby.host_requested.connect(host_game)
	_lobby.join_requested.connect(join_game)
	# Ambient startuje dopiero przy sesji — w lobby grałby na pustce.
	_lobby.host_requested.connect(func() -> void: Audio.play("ui_confirm", Audio.BUS_UI, -8.0))
	_lobby.join_requested.connect(func(_ip: String) -> void: Audio.play("ui_click", Audio.BUS_UI, -8.0))
	_handle_cmdline()

# ---------------------------------------------------------------- post-process

## Filtr VHS na świat (warstwa 5) — pod UI (warstwa 10), żeby HUD był czytelny.
## F2 włącza/wyłącza (dostępność: ziarno i aberracja nie każdemu służą).
var _post: CanvasLayer

func _setup_post() -> void:
	$UI.layer = 10
	_post = CanvasLayer.new()
	_post.name = "Post"
	_post.layer = 5
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/vhs.gdshader")
	rect.material = mat
	_post.add_child(rect)
	add_child(_post)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("vhs"):
		_post.visible = not _post.visible

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
			_restart_mission(false)
		return
	# po udanej ekstrakcji host zaczyna nową misję
	if mission.phase == MISSION_SCRIPT.Phase.SUCCESS:
		if Input.is_action_just_pressed("restart"):
			_restart_mission(true)
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
func _restart_mission(new_run: bool) -> void:
	print("[MISSION] restart (%s)" % ("nowa misja" if new_run else "wipe"))
	NoiseMgr.reset_mission()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("reset_enemy"):
			e.reset_enemy()
	for c in _players.get_children():
		c.request_full_reset()
	mission.on_restart(new_run)

func _handle_cmdline() -> void:
	var autoquit := -1.0
	var stealthtest := -1.0
	var wipetest := -1.0
	var missiontest := false
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--port="):
			port = a.substr("--port=".length()).to_int()
	for a in args:
		if a == "--host":
			host_game()
		elif a.begins_with("--join="):
			join_game(a.substr("--join=".length()))
		elif a.begins_with("--autoquit="):
			autoquit = a.substr("--autoquit=".length()).to_float()
		elif a == "--stealthtest":
			stealthtest = 20.0
		elif a.begins_with("--stealthtest="):
			stealthtest = a.substr("--stealthtest=".length()).to_float()
		elif a == "--missiontest":
			missiontest = true
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
	_lobby.visible = false
	Audio.play("oc_load", Audio.BUS_UI, -8.0)
	_start_ambience()
	NoiseMgr.reset_mission()
	_spawn_player(1)
	print("[NET] hosting on port %d" % port)

func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_lobby.set_status("Could not connect (%s)" % error_string(err), true)
		return
	multiplayer.multiplayer_peer = peer
	_lobby.set_status("Connecting to %s…" % ip)
	Audio.play("radio_beep", Audio.BUS_UI, -10.0)


func _on_peer_connected(id: int) -> void:
	print("[NET] peer connected: %d" % id)
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer disconnected: %d" % id)
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
