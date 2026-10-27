extends "res://scripts/stalker_test.gd"
## Test headless pakietu P0 z FUN_PLAN.md:
##
##   godot --headless --path . -- --host --funtest --autoquit=60
##
## 1. Ucieczka o włos: zamach Stalkera, który chybi człowieka tuż obok, liczy się raz na CLOSE_CALL_GAP s (licznik Stalkera,
##    `player_stats.escapes`, impuls `Feel.close_call` u lokalnego gracza); chybienie z daleka się nie liczy; MISS_COOLDOWN = ATTACK_COOLDOWN.
## 2. Wabik: udane Q przytrzymuje Stalkera na miejscu wabika — nowy hałas go nie zawraca, dopóki trwa `lure_left`; `break_lure`
##    (snop latarki) zwalnia go; `player_stats.lures` liczy wabik gracza.
## 3. Wyróżnienia: `Mission.awards` (GHOST, MEDIC, BAIT, CLOSE SHAVE, BUTCHER, progi, pojedynka).
## 4. Punkt kontrolny: zniszczone gniazda → faza BOSS zapisuje pozycje; wipe w walce wraca do niej (gniazda zostają zniszczone,
##    próba +1, Żyła śpi i budzi się po CHECKPOINT_GRACE s), a nie na start mapy.
## 5. Następna misja z karty wyniku: po sukcesie `_continue_without_hub` ładuje następną misję kampanii z pominięciem kryjówki.
## Mapa 1.3 (gniazda, Żyła, Stalker). Zwykli wrogowie usunięci, bot i Dyrektor stoją. Wynik: linie [FUN-TEST] i kod wyjścia.

const Mission := preload("res://scripts/mission.gd")

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[FUN-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[FUN-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[FUN-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	stalker = level.get_node_or_null("Stalker")
	check("mapa 1.3 ma Stalkera, gracza, gniazda i Żyłę", stalker != null and player != null and m.mission.kind == "nests"
		and get_tree().get_first_node_in_group("boss") != null)
	if stalker == null or player == null:
		_finish()
		return
	_quiet_world()
	await get_tree().create_timer(0.3).timeout
	var ground := _longest_run(["dirt", "concrete"])
	if int(ground.get("len", 0)) >= 16:
		await _close_call(ground)
		await _lure(ground)
	else:
		check("pas gruntu do testu Stalkera", false)
	_awards()
	await _checkpoint()
	await _skip_hub()
	_finish()

## Jak stalker_test._isolate, ale gniazda i Żyła zostają (punkt kontrolny i sukces misji).
func _quiet_world() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != stalker and not e.is_in_group("nests") and not e.is_in_group("boss"):
			e.queue_free()
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			p.set_physics_process(false)
			p.set_process(false)
			p.global_position = Vector2(-4000, -4000)
	Director.set_process(false)

func _stats() -> Dictionary:
	return main.mission._stat(player)

# ---------------------------------------------------------------- 1. ucieczka o włos

## Zamach w toku na gracza stojącego `dist` px od Stalkera; czeka, aż się rozstrzygnie.
func _swing_at(dist: float) -> void:
	_place_stalker(stalker.global_position)
	_place_player(stalker.global_position + Vector2(dist, 0))
	stalker._windup = 0.05
	stalker._windup_duration = 0.05
	stalker._windup_target = player
	stalker.winding = true
	await _ticks(6)

func _close_call(ground: Dictionary) -> void:
	check("pudło nie skraca przerwy przed kolejnym zamachem (MISS_COOLDOWN %.1f = ATTACK_COOLDOWN %.1f)" % [stalker.MISS_COOLDOWN, stalker.ATTACK_COOLDOWN],
		is_equal_approx(stalker.MISS_COOLDOWN, stalker.ATTACK_COOLDOWN))
	var mid: Vector2 = (ground["a"] + ground["b"]) * 0.5
	_wake(mid)
	stalker.awake = true
	_place_stalker(mid)
	player.set_physics_process(false)            # pozycję trzyma test: gracz nie spada ani nie odchodzi w trakcie zamachu
	var before: int = stalker.close_calls
	var esc0: int = int(_stats()["escapes"])
	Feel.close_call = 0.0
	var reach: float = stalker.REACH_STAND + stalker.REACH_SLACK
	await _swing_at(reach + 8.0)
	check("chybienie tuż obok = ucieczka o włos (licznik %d → %d)" % [before, stalker.close_calls], stalker.close_calls == before + 1)
	check("ucieczka na koncie gracza (escapes %d → %d)" % [esc0, int(_stats()["escapes"])], int(_stats()["escapes"]) == esc0 + 1)
	check("impuls efektu u lokalnego gracza (Feel.close_call = %.2f)" % Feel.close_call, Feel.close_call > 0.5)
	stalker._attack_timer = 0.0
	await _swing_at(reach + 8.0)
	check("druga ucieczka w ciągu %.0f s się nie liczy (licznik %d)" % [stalker.CLOSE_CALL_GAP, stalker.close_calls], stalker.close_calls == before + 1)
	stalker._close_at.clear()
	stalker._attack_timer = 0.0
	await _swing_at(reach + stalker.CLOSE_CALL_R + 30.0)
	check("chybienie z daleka nie jest ucieczką (licznik %d)" % stalker.close_calls, stalker.close_calls == before + 1)
	player.set_physics_process(true)

# ---------------------------------------------------------------- 2. wabik

func _lure(ground: Dictionary) -> void:
	var a: Vector2 = ground["a"]
	var b: Vector2 = ground["b"]
	_wake((a + b) * 0.5)
	stalker.awake = true
	_place_stalker((a + b) * 0.5)
	stalker._close_at.clear()
	NoiseMgr.overcharge_charges = 2
	NoiseMgr._q_log.clear()
	var lures0: int = int(_stats()["lures"])
	var ok := NoiseMgr.use_overcharge(a, player)
	await _ticks(3)
	check("udane Q przytrzymuje Stalkera (lure_left %.1f s)" % NoiseMgr.lure_left, ok and NoiseMgr.lure_left > NoiseMgr.LURE_LOCK - 1.0)
	check("Stalker idzie do wabika", stalker.target_pos.distance_to(a) < 2.0)
	check("wabik na koncie gracza (lures %d → %d)" % [lures0, int(_stats()["lures"])], int(_stats()["lures"]) == lures0 + 1)
	NoiseMgr.add_noise(10.0, b)
	await _ticks(3)
	check("w czasie przytrzymania nowy hałas go nie zawraca (cel x=%.0f, wabik x=%.0f)" % [stalker.target_pos.x, a.x], stalker.target_pos.distance_to(a) < 2.0)
	NoiseMgr.break_lure()
	NoiseMgr.add_noise(10.0, b)
	await _ticks(3)
	check("po przerwaniu (snop latarki) znów idzie na hałas", NoiseMgr.lure_left <= 0.0 and stalker.target_pos.distance_to(b) < 2.0)
	_sleep()
	await _ticks(3)

# ---------------------------------------------------------------- 3. wyróżnienia

func _awards() -> void:
	var team := {
		1: {"name": "P1", "kills": 12, "revives": 2, "escapes": 0, "lures": 1, "noise": 80.0},
		2: {"name": "P2", "kills": 30, "revives": 0, "escapes": 3, "lures": 0, "noise": 20.0},
	}
	var got := {}
	for r in Mission.awards(team, true):
		got[r[0]] = r[1]
	check("drużyna: GHOST P2, MEDIC P1, BAIT P1, CLOSE SHAVE P2, BUTCHER P2 (%s)" % str(got),
		got == {"ghost": "P2", "medic": "P1", "bait": "P1", "close_shave": "P2", "butcher": "P2"})
	var flat := {1: {"name": "P1", "kills": 0, "noise": 5.0}, 2: {"name": "P2", "kills": 0, "noise": 5.4}}
	check("bez różnic i zer nie ma wyróżnień", Mission.awards(flat, true).is_empty())
	var solo := {1: {"name": "P1", "kills": 4, "noise": 9.0}}
	var ids_quiet: Array = Mission.awards(solo, false).map(func(r: Array) -> String: return r[0])
	var ids_loud: Array = Mission.awards(solo, true).map(func(r: Array) -> String: return r[0])
	check("pojedynka: GHOST tylko, gdy Stalker spał (%s / %s)" % [str(ids_quiet), str(ids_loud)], ids_quiet == ["ghost", "butcher"] and ids_loud == ["butcher"])

# ---------------------------------------------------------------- 4. punkt kontrolny

func _checkpoint() -> void:
	var mission: Node = main.mission
	stalker.set_physics_process(false)            # Stalker nie wtrąca się w walkę z Żyłą
	var nests := get_tree().get_nodes_in_group("nests")
	var nest0: Node2D = nests[0]
	_place_player(nest0.global_position + Vector2(0, -8))
	await get_tree().create_timer(1.0).timeout
	var cp: Vector2 = player.global_position
	for n in nests:
		n.take_bullet(n.global_position + Vector2(-10, 0), 999.0)
	await _ticks(5)
	check("zniszczone gniazda → faza BOSS z punktem kontrolnym", mission.phase == Mission.Phase.BOSS and mission.has_checkpoint())
	check("punkt kontrolny = pozycja w chwili przebudzenia Żyły", mission.checkpoint_pos(player).distance_to(cp) < 2.0)
	var spawn: Vector2 = level.spawn_for(int(player.display_id))
	check("punkt kontrolny daleko od startu mapy (%.0f px)" % cp.distance_to(spawn), cp.distance_to(spawn) > 120.0)
	var att: int = mission.attempts
	main._solo_falls = 1                          # sam bez bota (settings.cfg gracza): pierwszy upadek byłby wykrwawieniem, a test chce wipe'u
	for c in main.get_node("Players").get_children():
		c.deliver_hit(99, c.global_position, "test")
	await get_tree().create_timer(main.WIPE_DELAY + 0.6).timeout
	var boss: Node = get_tree().get_first_node_in_group("boss")
	var alive := 0
	for n in get_tree().get_nodes_in_group("nests"):
		alive += 1 if n.alive else 0
	check("wipe w walce: znów faza BOSS, próba %d → %d" % [att, mission.attempts], mission.phase == Mission.Phase.BOSS and mission.attempts == att + 1)
	check("gniazda zostały zniszczone (żywe: %d)" % alive, alive == 0)
	check("gracz w punkcie kontrolnym (%.0f px od niego), żywy" % player.global_position.distance_to(cp),
		player.global_position.distance_to(cp) < 24.0 and not player.dead)
	check("Żyła śpi chwilę po powrocie", boss != null and int(boss.state) == 0)
	await get_tree().create_timer(mission.CHECKPOINT_GRACE + 0.5).timeout
	check("Żyła budzi się po %.1f s" % mission.CHECKPOINT_GRACE, boss != null and int(boss.state) == 1)
	# wykrwawienie w walce też odradza w punkcie kontrolnym (spawn właściciela postaci)
	check("odrodzenie po wykrwawieniu też w punkcie kontrolnym", player._spawn_point.distance_to(cp) < 2.0)

# ---------------------------------------------------------------- 5. następna misja bez kryjówki

func _skip_hub() -> void:
	var mission: Node = main.mission
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss != null:
		boss.take_bullet(boss.global_position + Vector2(-20, 0), 1.0e9)
	await _ticks(5)
	check("Żyła martwa → ekstrakcja", mission.phase == Mission.Phase.EXTRACT)
	player.set_physics_process(false)
	_place_player(mission.exit_pos)
	await get_tree().create_timer(mission.EXTRACT_TIME + 0.6).timeout
	check("ekstrakcja → SUCCESS", mission.phase == Mission.Phase.SUCCESS)
	player.set_physics_process(true)
	var nxt: String = main._next_campaign_map()
	main._continue_without_hub()
	await get_tree().create_timer(0.5).timeout
	check("[Interakcja] na karcie wyniku → od razu %s, bez kryjówki (mapa %s, faza %d)" % [nxt, level.map_id, mission.phase],
		level.map_id == nxt and mission.kind != "hub" and mission.phase == Mission.Phase.OBJECTIVE)
	check("start nowej misji z mapy, nie z punktu kontrolnego", not player._at_checkpoint)

func _ticks(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
