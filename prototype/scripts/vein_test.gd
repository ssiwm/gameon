extends Node
## Test headless hali Żyły (`VEIN_PLAN.md` E1–E2):
##
##   godot --headless --path prototype -- --host --veintest --autoquit=90
##
## E1: dane hali i pusta hala (bez zwykłych wrogów), uśpiona Żyła bez strefy trafień (nie zasłania gniazda), stan CZEKA po ostatnim
## gnieździe, start walki z wejściem człowieka, brama z korzeni (kolizja, wciąganie bota, odrodzenie za bramą), kamera areny
## (kadr hali, zoom), Stalker trzymany z dala do fazy 3, restart od punktu kontrolnego bez wskrzeszania zabitych przed walką,
## krzyk fazy 3 otwiera bramę, śmierć → ekstrakcja.
## E2: cykl wynurzenie → ryk → seria → zanurzenie → przejście pod podłogą → zapowiedź → wynurzenie w innej gardzieli; pod podłogą
## nietrafialna i bez celu dla botów; cios wynurzenia w stojącego na gardzieli; wybór gardzieli przeciw kampieniu i za obrażenia; „ból”.
## Mapa 1.3. Wynik: linie [VEIN-TEST] i kod wyjścia (0 = OK) — nadaje się do CI.

const Mission := preload("res://scripts/mission.gd")
const Combat := preload("res://scripts/combat.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Hurtbox := preload("res://scripts/hurtbox.gd")

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
	await _turn()
	await _movement()
	await _hump()
	await _anchor_choice()
	await _pain()
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

# ---------------------------------------------------------------- E2: ruch

## Wycisza ataki (cooldowny), żeby test liczył tylko ruch.
func _calm() -> void:
	boss._set_atk(boss.Atk.NONE)
	boss._wave_r = -1.0
	boss.stunned = false
	boss._lash_cd = 99.0
	boss._spit_cd = 99.0
	boss._sweep_cd = 99.0
	boss._atk_gap = 99.0
	boss._brood_t = 99.0
	boss._spits.clear()
	for p in get_tree().get_nodes_in_group("players"):
		p.flashlight = false                      # snop latarki oświetliłby garb w przejściu (E2b) albo oślepił paszczę
	for e in get_tree().get_nodes_in_group("enemies"):
		if String(e.name).begins_with("Brood"):
			e.queue_free()                            # potomstwo gryzie gracza stojącego na gardzieli

func _dealt(open: bool) -> float:
	var hp0: float = boss.hp
	boss.maw_open = open
	var info := Combat.make_info(Weapons.M83, 10.0, boss.global_position + Vector2(-60, -24), Vector2.RIGHT, 1, "bullet")
	var r: Dictionary = boss.take_hit(info)
	var d := float(r.get("dealt", 0.0))
	boss.hp = hp0
	return d

func _movement() -> void:
	_place(player, level.vein_entry(0) + Vector2(4, 0))
	await _ticks(2)
	check("Żyła wynurzona po ryku, zagrożenie dla botów (ruch %d)" % int(boss.move), int(boss.move) == int(boss.Move.UP) and boss.is_threat())
	_calm()
	var a0: int = boss.anchor
	boss._burst_n = boss.BURST
	boss._maw_t = 0.0
	await _ticks(2)
	check("po serii %d ataków zanurza się, paszcza zamknięta" % boss.BURST, int(boss.move) == int(boss.Move.SINK) and not bool(boss.maw_open))
	await get_tree().create_timer(boss.SINK_T + 0.1).timeout
	check("pod podłogą: przejście, poza celami botów, bez strefy trafień", int(boss.move) == int(boss.Move.TRAVEL) and not boss.is_threat()
		and not bool(boss._hurt_on))
	check("pod podłogą kula nic nie robi (%.1f)" % _dealt(true), is_zero_approx(_dealt(true)))
	var from: Vector2 = boss._travel_from
	var to: Vector2 = boss._travel_to
	check("przejście do innej gardzieli (%d → %d), %.1f s (%.1f–%.1f)" % [a0, boss.anchor, boss._travel_dur, boss.TRAVEL_MIN, boss.TRAVEL_MAX],
		boss.anchor != a0 and absf(from.x - to.x) >= 120.0 and boss._travel_dur >= boss.TRAVEL_MIN - 0.01 and boss._travel_dur <= boss.TRAVEL_MAX + 0.01)
	_place(player, to + Vector2(12, 0))           # gracz stoi tam, gdzie wyjdzie
	player.hp = player.max_hp()
	player._invuln = 0.0
	var hp0: int = player.hp
	await get_tree().create_timer(boss._travel_dur * 0.5).timeout
	var mid: float = boss.global_position.x
	check("garb sunie pod podłogą (x %.0f między %.0f a %.0f)" % [mid, from.x, to.x], mid > minf(from.x, to.x) + 8.0 and mid < maxf(from.x, to.x) - 8.0)
	await get_tree().create_timer(boss._travel_dur * 0.5 + 0.1).timeout
	check("zapowiedź wynurzenia: znacznik na gardzieli docelowej, dalej nietrafialna", int(boss.move) == int(boss.Move.EMERGE)
		and boss.emerge_mark == to and not boss.is_threat())
	player._invuln = 0.0
	await get_tree().create_timer(boss.EMERGE_T * Difficulty.m("boss_cd") + 0.1).timeout
	check("wynurzenie rani stojącego na gardzieli (HP %d → %d)" % [hp0, player.hp], player.hp == hp0 - 1)
	check("po wynurzeniu ryk z otwartą paszczą: pełne obrażenia (%.1f)" % _dealt(true),
		int(boss.move) == int(boss.Move.ROAR) and bool(boss.maw_open) and is_equal_approx(_dealt(true), 10.0))
	player.hp = player.max_hp()
	_place(player, level.vein_entry(0) + Vector2(4, 0))
	await get_tree().create_timer(boss.ROAR_T + 0.1).timeout
	check("po ryku znów walczy (seria od zera)", int(boss.move) == int(boss.Move.UP) and int(boss._burst_n) == 0)

# ---------------------------------------------------------------- E2b: obrót, garb

func _turn() -> void:
	_calm()
	var cd := Difficulty.m("boss_cd")
	boss._up_t = 0.0
	boss._burst_n = 0
	boss._pain.clear()
	boss._dmg_by.clear()
	boss.face = 0.0
	boss._face_goal = 0.0
	var bot := _bot()
	if bot != null:
		_place(bot, Vector2(-4000, -4000))
	_place(player, boss.global_position + Vector2(-40, 0))
	await get_tree().create_timer(boss.TURN_T * cd * 0.5 + 0.15).timeout
	check("między atakami obraca się do najbliższego człowieka (lewo, face %.2f)" % boss.face, is_equal_approx(float(boss.face), -1.0))
	check("paszcza przesunięta w stronę obrotu (x %.1f)" % boss._maw_point().x, boss._maw_point().x < -boss.MAW_SIDE_PX + 0.5)
	boss._begin(boss.Atk.LASH, boss.LASH_WINDUP, boss.global_position + Vector2(40, 0))
	var extra: float = float(boss._atk_t) - boss.LASH_WINDUP * cd
	check("atak na drugą stronę: zapowiedź dłuższa o pełny obrót (+%.2f s, obrót %.2f s)" % [extra, boss.TURN_T * cd],
		absf(extra - boss.TURN_T * cd) < 0.02)
	await get_tree().create_timer(boss.TURN_T * cd + 0.1).timeout
	check("obrót w prawo w %.2f s (face %.2f)" % [boss.TURN_T * cd, boss.face], is_equal_approx(float(boss.face), 1.0))
	player.hp = player.max_hp()
	player._invuln = 0.0
	var hp0: int = player.hp
	boss._atk_t = 0.01
	await _ticks(3)
	check("macka nie trafia gracza za plecami (D6, HP %d → %d)" % [hp0, player.hp], player.hp == hp0)
	_place(player, boss.global_position + Vector2(40, 0))
	await _ticks(2)
	boss._begin(boss.Atk.LASH, boss.LASH_WINDUP, player.global_position)
	check("atak na tę samą stronę bez obrotu (%.2f s)" % boss._atk_t, absf(float(boss._atk_t) - boss.LASH_WINDUP * cd) < 0.02)
	player._invuln = 0.0
	boss._atk_t = 0.01
	await _ticks(3)
	check("macka trafia przed sobą (HP %d → %d)" % [hp0, player.hp], player.hp == hp0 - 1)
	player.hp = player.max_hp()
	_calm()
	boss._up_t = 0.0
	boss._burst_n = 0
	_place(player, level.vein_entry(0) + Vector2(4, 0))
	await _ticks(2)

## Trzyma gracza `dx` px od garbu na podłodze, z latarką na garb (gracz idzie za garbem, który sunie 160 px/s).
func _light_hump(dx: float, frames: int) -> void:
	for _i in frames:
		var pt: Vector2 = boss.global_position + Vector2(0, -4)
		_place(player, Vector2(boss.global_position.x + dx, boss.global_position.y))
		player.aim_dir = (pt - (player.global_position + Vector2(0, -9))).normalized()
		await get_tree().physics_frame

func _hump() -> void:
	_calm()
	var bot := _bot()
	if bot != null:
		_place(bot, Vector2(-4000, -4000))
	boss._burst_n = 0
	boss._up_t = 0.0
	boss._begin_sink("test")
	await get_tree().create_timer(boss.SINK_T + 0.1).timeout
	boss._travel_dur = 6.0                        # wolne przejście — kilka prób światła w jednym
	boss._move_t = 6.0
	await _ticks(3)
	var hs: CollisionShape2D = boss.get_meta("hurt_shape")
	check("garb w ciemności: nieoświetlony, bez strefy trafień, kula nic nie robi (%.1f)" % _dealt(true),
		int(boss.move) == int(boss.Move.TRAVEL) and not bool(boss.hump_lit) and hs.disabled and is_zero_approx(_dealt(true)))
	player.flashlight = true
	await _light_hump(-60.0, 12)
	check("snop latarki z 60 px oświetla garb (%s)" % boss._hump_by, bool(boss.hump_lit) and boss._hump_by == "torch")
	var sz: Vector2 = (hs.shape as RectangleShape2D).size
	check("strefa trafień zmniejszona do garbu (%.0f×%.0f) i włączona, ciało ruchu nie" % [sz.x, sz.y],
		sz == boss.HUMP_SIZE and not hs.disabled and (boss.get_node("CollisionShape2D") as CollisionShape2D).disabled)
	var q := PhysicsRayQueryParameters2D.create(boss.global_position + Vector2(-60, -10), boss.global_position + Vector2(60, -10), boss.collision_layer)
	q.collide_with_areas = true
	var hit := Hurtbox.resolve(level.get_world_2d().direct_space_state.intersect_ray(q))
	check("strzał z biodra (10 px nad podłogą) trafia strefę garbu", hit.get("collider") == boss)
	var pain0: int = boss._pain.size()
	var d := _dealt(false)
	check("oświetlony garb: 20%% obrażeń (%.1f z 10), bez reguł paszczy" % d, is_equal_approx(d, 10.0 * boss.HUMP_MULT))
	check("trafienie w garb nie liczy się do „bólu”", boss._pain.size() == pain0)
	player.flashlight = false
	await _light_hump(-60.0, 12)
	check("latarka zgaszona — garb znów w ciemności", not bool(boss.hump_lit))
	level.spawn_flare(boss.global_position + Vector2(-48, -6), Vector2.ZERO)
	await _ticks(2)
	var fl: Node2D = null
	for f in get_tree().get_nodes_in_group("flares"):
		fl = f
	for _i in 12:
		if fl != null:
			fl.global_position = boss.global_position + Vector2(-48, -4)
		_place(player, level.vein_entry(0) + Vector2(4, 0))
		await get_tree().physics_frame
	check("flara 48 px od garbu go oświetla (%s)" % boss._hump_by, bool(boss.hump_lit) and boss._hump_by == "flare")
	for _i in 12:
		if fl != null:
			fl.global_position = boss.global_position + Vector2(-90, -4)
		await get_tree().physics_frame
	check("flara 90 px — za daleko", not bool(boss.hump_lit))
	if fl != null:
		fl.queue_free()
	player.flashlight = true
	await _light_hump(-60.0, 12)
	boss._move_t = 0.01                           # koniec przejścia przy oświetlonym garbie
	await _ticks(3)
	sz = (hs.shape as RectangleShape2D).size
	check("po przejściu: garb zgaszony, strefa wraca do %.0f×%.0f" % [sz.x, sz.y], not bool(boss.hump_lit) and sz == boss.HURT_SIZE)
	player.flashlight = false
	_place(player, level.vein_entry(0) + Vector2(4, 0))
	await get_tree().create_timer(boss.EMERGE_T * Difficulty.m("boss_cd") + boss.ROAR_T + 0.3).timeout
	check("po wynurzeniu strefa trafień pełna i włączona", not hs.disabled and int(boss.move) == int(boss.Move.UP))

func _anchor_choice() -> void:
	var now := Time.get_ticks_msec()
	var save: int = boss.anchor
	boss._dmg_by.clear()
	boss._camp.clear()
	boss._camp[player.name] = [boss._anchors[0], now - int(boss.CAMP_T * 1000.0) - 1000]
	boss.anchor = 2
	var hits := 0
	for _i in 20:
		hits += 1 if boss._pick_anchor() == 0 else 0
	check("gracz stoi 7 s przy zachodniej gardzieli → Żyła wychodzi tam (%d/20)" % hits, hits == 20)
	boss.anchor = 0
	var same := 0
	for _i in 20:
		same += 1 if boss._pick_anchor() == 0 else 0
	check("nigdy ta sama gardziel dwa razy z rzędu (%d/20)" % same, same == 0)
	boss._camp.clear()
	boss._dmg_by.append([now, int(player.player_id), 50.0])
	_place(player, boss._anchors[2] + Vector2(-6, 0))
	boss.anchor = 1
	var dealer := 0
	for _i in 40:
		dealer += 1 if boss._pick_anchor() == 2 else 0
	info("najwięcej obrażeń przy wschodniej gardzieli: tam %d/40 wyborów (+1, los między dwiema najlepszymi)" % dealer)
	check("bez kampienia i obrażeń — losowo między dwiema pozostałymi", dealer > 0)
	boss._dmg_by.clear()
	boss.anchor = save
	_place(player, level.vein_entry(0) + Vector2(4, 0))
	await _ticks(2)

func _pain() -> void:
	_calm()
	boss._burst_n = 0
	boss._up_t = 0.0
	boss._pain = [[Time.get_ticks_msec(), boss.max_hp * 0.13]]
	await _ticks(2)
	check("„ból” (13%% maks. HP w %.0f s) → zanurza się od razu, przed końcem serii" % boss.PAIN_WINDOW, int(boss.move) == int(boss.Move.SINK))

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
	check("po restarcie Żyła znów nad środkową gardzielą, wynurzona (x %.0f)" % boss.global_position.x,
		boss.global_position.distance_to(boss._home) < 1.0 and is_zero_approx(float(boss.sink)) and int(boss.move) != int(boss.Move.TRAVEL))

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
