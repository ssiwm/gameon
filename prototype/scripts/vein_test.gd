extends Node
## Test headless hali Żyły (`VEIN_PLAN.md` E1–E2):
##
##   godot --headless --path prototype -- --host --veintest --autoquit=90
##
## E1: dane hali i pusta hala (bez zwykłych wrogów), uśpiona Żyła bez strefy trafień (nie zasłania gniazda), stan CZEKA po ostatnim
## gnieździe, start walki z wejściem człowieka, brama z korzeni (kolizja, wciąganie bota, odrodzenie za bramą), kamera areny
## (kadr hali, zoom), Stalker trzymany z dala do fazy 3, restart od punktu kontrolnego bez wskrzeszania zabitych przed walką,
## krzyk fazy 3 otwiera bramę, śmierć → ekstrakcja.
## Mapa 1.3. Wynik: linie [VEIN-TEST] i kod wyjścia (0 = OK) — nadaje się do CI.

const Mission := preload("res://scripts/mission.gd")

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var boss: Node2D
var stalker: Node2D
var failed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[VEIN-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[VEIN-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[VEIN-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func _ticks(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _place(p: Node2D, pos: Vector2) -> void:
	p.global_position = pos
	p.velocity = Vector2.ZERO

func _bot() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			return p
	return null

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	boss = get_tree().get_first_node_in_group("boss")
	stalker = level.get_node_or_null("Stalker")
	check("mapa 1.3: gracz, Żyła, Stalker i dane hali (VEIN_ARENA)", player != null and boss != null and stalker != null
		and level.map_id == "z1_m3" and not (level.vein_arena as Dictionary).is_empty())
	if player == null or boss == null or stalker == null:
		_finish()
		return
	Director.set_process(false)
	await _hall_layout()
	await _wait_and_start()
	await _camera()
	await _stalker_hold()
	await _checkpoint_restart()
	await _phase3_release()
	await _death()
	_finish()

# ---------------------------------------------------------------- E1: hala

func _hall_layout() -> void:
	var ar: Rect2 = level.arena_rect
	check("hala 400 × 224 px (jest %s), kadr kamery w granicach mapy" % str(ar.size),
		ar.size == Vector2(400, 224) and level.bounds.encloses(level.arena_view))
	check("Żyła na środku hali (x %.0f, środek %.0f)" % [boss.global_position.x, ar.get_center().x],
		level.in_vein_arena(boss.global_position) and absf(boss.global_position.x - ar.get_center().x) < 24.0)
	var nests := get_tree().get_nodes_in_group("nests")
	var hall_nest: Node2D = null
	for n in nests:
		if level.in_vein_arena((n as Node2D).global_position):
			hall_nest = n
	check("ostatnie gniazdo stoi w hali obok Żyły", hall_nest != null and absf(hall_nest.global_position.x - boss.global_position.x) < 32.0)
	var foes := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_in_group("nests") or e.is_in_group("boss") or e == stalker:
			continue
		if level.in_vein_arena((e as Node2D).global_position):
			foes.append(String(e.name))
	check("w hali bez zwykłych wrogów (%s)" % str(foes), foes.is_empty())
	check("uśpiona Żyła bez strefy trafień — nie zasłania gniazda", not bool(boss._hurt_on)
		and (boss.get_node("CollisionShape2D") as CollisionShape2D).disabled)
	var g: Rect2 = level.vein_gate_rect()
	check("brama otwarta na starcie: otwór w ścianie hali przy podłodze", not bool(level.vein_gate_closed) and not _gate_blocks()
		and g.end.y == ar.end.y and g.end.x == ar.position.x)

## Czy w środku otworu bramy stoi bryła terenu (kolizja bramy).
func _gate_blocks() -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = level.vein_gate_rect().get_center()
	q.collision_mask = 1
	for h in level.get_world_2d().direct_space_state.intersect_point(q):
		if h.get("collider") == level._vein_gate:
			return true
	return false

# ---------------------------------------------------------------- E1: CZEKA i start

var _killed_before := ""
var _killed_during := ""

func _wait_and_start() -> void:
	var mission: Node = main.mission
	# wróg zabity przed walką — restart od punktu kontrolnego nie może go wskrzesić (do 1.7.551 wstawał Wołek 144 px od Żyły)
	var victims := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_in_group("nests") and not e.is_in_group("boss") and e != stalker and e.get("alive") == true and e.has_method("take_bullet"):
			victims.append(e)
	if victims.size() >= 2:
		_killed_before = String(victims[0].name)
		_killed_during = String(victims[1].name)
		victims[0].take_bullet(victims[0].global_position + Vector2(-10, 0), 9999.0)
	await _ticks(3)
	_place(player, level.vein_checkpoint(0))
	await _ticks(2)
	for n in get_tree().get_nodes_in_group("nests"):
		n.take_bullet(n.global_position + Vector2(-10, 0), 999.0)
	await _ticks(5)
	check("gniazda zniszczone, gracz w przedsionku: faza BOSS, Żyła CZEKA (śpi)", mission.phase == Mission.Phase.BOSS
		and int(boss.state) == 0 and bool(boss.waiting) and int(boss.nests_left) == 0)
	check("brama otwarta, Stalker nie trzymany, kamera zwykła", not bool(level.vein_gate_closed) and not NoiseMgr.stalker_hold
		and not player.arena_cam_on())
	await get_tree().create_timer(2.0).timeout
	check("bez wejścia Żyła dalej czeka", int(boss.state) == 0)
	var bot := _bot()
	if bot != null:
		_place(bot, level.vein_checkpoint(1))
	_place(player, level.vein_entry(0) + Vector2(48, 0))
	await _ticks(4)
	check("wejście człowieka budzi Żyłę i trzyma Stalkera (stalker_hold)", int(boss.state) == 1 and NoiseMgr.stalker_hold and bool(boss._hurt_on))
	check("jedyny człowiek w hali → brama zamknięta od razu, kolizja w otworze", bool(level.vein_gate_closed))
	await _ticks(2)
	check("brama blokuje otwór (bryła terenu)", _gate_blocks())
	if bot != null:
		check("bot z przedsionka wciągnięty do hali", level.in_vein_arena(bot.global_position))
	else:
		info("bez bota (ustawienia): wciąganie sprawdza tylko gracz")
	check("wykrwawiony wstanie za bramą (%.0f px od wejścia)" % player._spawn_point.distance_to(level.vein_entry(0)),
		player._spawn_point.distance_to(level.vein_entry(0)) < 2.0)
	_place(player, level.vein_checkpoint(0))      # maruder / dołączający za zamkniętą bramą
	await get_tree().create_timer(main.mission.ARENA_PULL_EVERY + 0.3).timeout
	check("żywy za zamkniętą bramą wciągnięty do hali w %.1f s" % main.mission.ARENA_PULL_EVERY, level.in_vein_arena(player.global_position))
	_place(player, level.vein_entry(0) + Vector2(48, 0))

# ---------------------------------------------------------------- E1: kamera areny

func _camera() -> void:
	await get_tree().create_timer(player.ARENA_CAM_T + 0.2).timeout
	var cam: Camera2D = player._camera
	var view: Rect2 = level.arena_view
	var vp: Vector2 = player.get_viewport_rect().size
	var want := minf(Settings.cam_zoom(), minf(vp.x / view.size.x, vp.y / view.size.y))
	var ctr := cam.get_screen_center_position()
	check("kamera areny: kadr hali (środek %s, zoom %.2f, oczekiwany %.2f)" % [str(ctr.round()), cam.zoom.x, want],
		player.arena_cam_on() and is_equal_approx(cam.zoom.x, want) and ctr.distance_to(view.get_center()) < 4.0)
	var half: Vector2 = vp * 0.5 / cam.zoom
	var ar: Rect2 = level.arena_rect
	var play := Rect2(ar.position.x, 288.0 - 48.0, ar.size.x, ar.end.y + 24.0 - 240.0)   # od głów na najwyższej kładce (rząd 18) po pas pod podłogą
	check("cała przestrzeń walki w kadrze (%.0f × %.0f px)" % [half.x * 2.0, half.y * 2.0],
		Rect2(ctr - half, half * 2.0).grow(1.0).encloses(play))
	_place(player, level.vein_entry(0) + Vector2(140, -96))     # gracz w innym miejscu hali — kadr stoi
	await _ticks(3)
	check("kadr stały, gdy gracz chodzi po hali", cam.get_screen_center_position().distance_to(view.get_center()) < 4.0)
	_place(player, level.vein_entry(0) + Vector2(48, 0))

# ---------------------------------------------------------------- E1: Stalker

func _stalker_hold() -> void:
	var lvl0 := NoiseMgr.level
	NoiseMgr.level = 95.0
	await get_tree().create_timer(0.4).timeout
	check("hałas 95 w walce przed fazą 3 nie budzi Stalkera", not bool(stalker.awake))
	stalker.awake = true                          # obudzony wcześniej (np. przed wejściem do hali)
	stalker.global_position = level.vein_entry(0) + Vector2(-200, 0)
	await _ticks(3)
	check("obudzony wcześniej wraca do legowiska (%.0f px od niego)" % stalker.global_position.distance_to(stalker._home),
		not bool(stalker.awake) and stalker.global_position.distance_to(stalker._home) < 2.0)
	NoiseMgr.level = lvl0

# ---------------------------------------------------------------- E1: punkt kontrolny

func _checkpoint_restart() -> void:
	var mission: Node = main.mission
	var during: Node = level.get_node_or_null(_killed_during)
	if during != null:
		during.take_bullet(during.global_position + Vector2(-10, 0), 9999.0)
	await _ticks(3)
	var att: int = mission.attempts
	main._solo_falls = 1                          # sam bez bota: pierwszy upadek byłby wykrwawieniem, a test chce wipe'u
	for c in main.get_node("Players").get_children():
		c.deliver_hit(99, c.global_position, "test")
	await get_tree().create_timer(main.WIPE_DELAY + 0.6).timeout
	check("wipe w hali: restart od punktu kontrolnego (próba %d → %d)" % [att, mission.attempts], mission.attempts == att + 1
		and mission.phase == Mission.Phase.BOSS)
	check("gracz w przedsionku (%.0f px od punktu), brama otwarta" % player.global_position.distance_to(level.vein_checkpoint(0)),
		player.global_position.distance_to(level.vein_checkpoint(0)) < 24.0 and not bool(level.vein_gate_closed) and not _gate_blocks())
	check("Żyła znów czeka na wejście, Stalker wolny", int(boss.state) == 0 and bool(boss.waiting) and not NoiseMgr.stalker_hold)
	var before: Node = level.get_node_or_null(_killed_before)
	during = level.get_node_or_null(_killed_during)
	check("zabity przed walką (%s) nie wstał, zabity w walce (%s) wstał" % [_killed_before, _killed_during],
		before != null and before.get("alive") == false and during != null and during.get("alive") == true)
	await get_tree().create_timer(player.ARENA_CAM_T + 0.2).timeout
	check("poza halą kamera wraca do gracza (zoom %.2f)" % player._camera.zoom.x, not player.arena_cam_on()
		and is_equal_approx(player._camera.zoom.x, Settings.cam_zoom()))
	_place(player, level.vein_entry(0) + Vector2(48, 0))
	await _ticks(4)
	check("ponowne wejście: walka i brama od nowa", int(boss.state) == 1 and bool(level.vein_gate_closed) and NoiseMgr.stalker_hold)

# ---------------------------------------------------------------- E1: faza 3 i śmierć

func _phase3_release() -> void:
	boss.hp = boss.max_hp * 0.34
	boss.phase = 2
	boss.maw_open = true
	boss.take_bullet(boss.global_position + Vector2(-40, -20), boss.max_hp * 0.02)
	await _ticks(3)
	check("krzyk fazy 3 otwiera bramę i wypuszcza Stalkera", int(boss.phase) == 3 and not bool(level.vein_gate_closed)
		and not NoiseMgr.stalker_hold)
	check("przy otwartej bramie wykrwawiony znów wstaje w przedsionku", player._spawn_point.distance_to(level.vein_checkpoint(0)) < 2.0)

func _death() -> void:
	var mission: Node = main.mission
	boss.take_bullet(boss.global_position + Vector2(-20, 0), 1.0e9)
	await _ticks(5)
	check("Żyła martwa → ekstrakcja, brama otwarta", mission.phase == Mission.Phase.EXTRACT and not bool(level.vein_gate_closed))
	await get_tree().create_timer(player.ARENA_CAM_T + 0.2).timeout
	check("po walce kamera wraca do gracza", not player.arena_cam_on())
