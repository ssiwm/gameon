extends Node
## Test headless Stalkera (REVIEW_PLAN.md R1): mierzy trzy zachowania, które GDD §8.5 opisuje regułami.
##
##   godot --headless --path . -- --host --stalkertest --autoquit=60
##
## 1. Ostrzał: czy trafienia zatrzymują Stalkera w miejscu (droga i zamachy przy trafieniu co 0,6 s).
## 2. Teren: prędkość gracza i Stalkera na zwykłym gruncie, w wodzie i w błocie.
## 3. Po ciosie: o ile się cofa i po jakim czasie zamachuje się znowu.
##
## Mapa 1.3 (ma Stalkera, długi pas wody i błoto). Zwykli wrogowie i gniazda są usuwani, bot i Dyrektor grozy stoją —
## każdy obcy hałas zmieniłby cel Stalkera. Wynik: linie [STALKER-TEST] i kod wyjścia (0 = OK) — nadaje się do CI.

const HIT_EVERY := 0.6                ## s między trafieniami w pomiarze ostrzału (rytm spokojnego ognia z P-64)
const HIT_NOISE := 0.5                ## Uwaga jednego takiego strzału (zimna lufa P-64)
const FIRE_TIME := 10.0
const FIRE_DIST := 200.0              ## px między Stalkerem a strzelcem na starcie
const CONTROL_TIME := 2.0

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var stalker: CharacterBody2D
var failed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[STALKER-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[STALKER-TEST] INFO  %s" % label)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	stalker = level.get_node_or_null("Stalker")
	check("mapa ma Stalkera i gracza", stalker != null and player != null)
	if stalker == null or player == null:
		_finish()
		return
	_isolate()
	await get_tree().create_timer(0.3).timeout
	var ground := _longest_run(["dirt", "concrete"])
	check("pas zwykłego gruntu do pomiarów (%d kafli)" % int(ground.get("len", 0)), int(ground.get("len", 0)) >= 16)
	if int(ground.get("len", 0)) >= 16:
		await _measure_fire(ground)
		await _measure_after_hit(ground)
	await _measure_terrain(ground)
	_finish()

func _finish() -> void:
	print("[STALKER-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	get_tree().quit(1 if failed > 0 else 0)

# ---------------------------------------------------------------- przygotowanie sceny

## Zostają tylko gracz i Stalker: reszta świata nie hałasuje i nie wchodzi w zasięg ciosu.
func _isolate() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != stalker:
			e.queue_free()
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			p.set_physics_process(false)
			p.set_process(false)
			p.global_position = Vector2(-4000, -4000)
	Director.set_process(false)

## Najdłuższy poziomy pas kafli o podanych powierzchniach z trzema wolnymi kaflami nad sobą.
## Zwraca {len, a, b}: liczba kafli oraz pozycje stóp na lewym i prawym końcu (świat), albo {} gdy takiego pasa nie ma.
func _longest_run(surfaces: Array) -> Dictionary:
	var rows: Array = level._map
	var best := {}
	for r in range(3, rows.size()):
		var c := 0
		var width := (rows[r] as String).length()
		while c < width:
			if not _walkable(c, r, surfaces):
				c += 1
				continue
			var s := c
			while c < width and _walkable(c, r, surfaces):
				c += 1
			if c - s > int(best.get("len", 0)):
				var t := float(level.TILE)
				best = {"len": c - s, "a": level.to_global(Vector2(s * t + t * 0.5, r * t)), "b": level.to_global(Vector2((c - 1) * t + t * 0.5, r * t))}
	return best

func _walkable(c: int, r: int, surfaces: Array) -> bool:
	if not level._is_solid(c, r) or int(level.KINDS[level._ch(c, r)][2]) != 0:
		return false
	var surf := String(level.KINDS[level._ch(c, r)][1])
	if not surfaces.has(surf if surf != "" else "dirt"):
		return false
	for up in range(1, 4):
		if level._is_solid(c, r - up):
			return false
	return true

func _place_player(pos: Vector2) -> void:
	player.global_position = pos
	player.velocity = Vector2.ZERO

## Stalker w `pos`, bez rozpędu, zamachu i przerw — jak tuż po przebudzeniu.
func _place_stalker(pos: Vector2) -> void:
	stalker.global_position = pos
	stalker._attack_timer = 0.0
	stalker._hesitate = 0.0
	stalker._slow = 0.0
	stalker._retreat_timer = 0.0
	stalker._listen = 0.0
	stalker._windup = 0.0
	stalker._windup_target = null
	stalker.winding = false
	stalker._arrived = false
	stalker._path_goal = Vector2.INF

## Budzi Stalkera hałasem w `target` (Uwaga 95: faza polowania, pełna prędkość).
func _wake(target: Vector2) -> void:
	NoiseMgr.level = 20.0
	NoiseMgr.add_noise(75.0, target)

func _sleep() -> void:
	NoiseMgr.level = 0.0
	NoiseMgr.stalker_awake = false
	stalker.awake = false

func _frames(seconds: float, each := Callable()) -> void:
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < seconds and is_inside_tree():
		await get_tree().physics_frame
		t += dt
		if each.is_valid():
			each.call(t, dt)

# ---------------------------------------------------------------- 1. ostrzał

func _measure_fire(ground: Dictionary) -> void:
	var s0: Vector2 = (ground["a"] as Vector2) + Vector2(24, 0)
	var p0 := s0 + Vector2(FIRE_DIST, 0)
	# bez trafień: punkt odniesienia
	_place_player(p0)
	_place_stalker(s0)
	_wake(p0)
	await _frames(CONTROL_TIME)
	var free_px := stalker.global_position.distance_to(s0)
	check("bez trafień Stalker idzie do źródła hałasu (%.0f px w %.0f s)" % [free_px, CONTROL_TIME], free_px > 100.0)
	# z trafieniem co HIT_EVERY s
	_sleep()
	await _frames(0.2)
	_place_player(p0)
	_place_stalker(s0)
	_wake(p0)
	var hp0: int = player.hp
	var noise0 := NoiseMgr.level
	var st := {"next": 0.0, "windups": 0, "was": false}
	await _frames(FIRE_TIME, func(t: float, _dt: float) -> void:
		if t >= float(st["next"]):
			st["next"] = float(st["next"]) + HIT_EVERY
			stalker.take_hit({"amount": 11.0, "pos": stalker.global_position, "dir": Vector2.LEFT, "w": 2, "shooter": 1})
			NoiseMgr.add_noise(HIT_NOISE, p0)
		if stalker.winding and not bool(st["was"]):
			st["windups"] = int(st["windups"]) + 1
		st["was"] = stalker.winding)
	var fire_px := stalker.global_position.distance_to(s0)
	info("ostrzał co %.1f s przez %.0f s: Stalker przeszedł %.0f px z %.0f, zamachów %d, gracz stracił %d HP, Uwaga %.0f -> %.0f" % [
		HIT_EVERY, FIRE_TIME, fire_px, FIRE_DIST, int(st["windups"]), hp0 - int(player.hp), noise0, NoiseMgr.level])
	_sleep()
	await _frames(0.2)

# ---------------------------------------------------------------- 2. teren

func _measure_terrain(ground: Dictionary) -> void:
	var rows := [["grunt", ground]]
	for surf in ["water", "mud"]:
		var run := _longest_run([surf])
		if int(run.get("len", 0)) >= 5:
			rows.append([surf, run])
		else:
			info("teren %s: brak pasa do pomiaru na tej mapie" % surf)
	for row in rows:
		var name: String = row[0]
		var run: Dictionary = row[1]
		var a: Vector2 = (run["a"] as Vector2) + Vector2(4, 0)
		var b: Vector2 = (run["b"] as Vector2) - Vector2(4, 0)
		var span := minf(a.distance_to(b), 220.0)
		# Stalker: stała prędkość, więc droga / czas
		_place_player(Vector2(-3000, -3000))
		player.set_physics_process(false)
		_place_stalker(a)
		_wake(a + Vector2(span, 0))
		var ts := maxf(0.4, (span - 8.0) / 110.0)
		await _frames(ts)
		var vs := stalker.global_position.distance_to(a) / ts
		_sleep()
		_place_stalker(Vector2(-6000, -6000))
		# gracz: prędkość szczytowa biegu po tym samym pasie
		player.set_physics_process(true)
		_place_player(a)
		await _frames(0.3)
		var peak := [0.0]
		Input.action_press("move_right")
		await _frames(maxf(0.6, span / 60.0), func(_t: float, _dt: float) -> void:
			if player.global_position.x < b.x:
				peak[0] = maxf(float(peak[0]), absf(player.velocity.x)))
		Input.action_release("move_right")
		info("teren %s: gracz %.0f px/s, Stalker %.0f px/s (pas %.0f px)" % [name, float(peak[0]), vs, span])
		_sleep()
		await _frames(0.2)

# ---------------------------------------------------------------- 3. po ciosie

func _measure_after_hit(ground: Dictionary) -> void:
	var s0: Vector2 = (ground["a"] as Vector2) + Vector2(60, 0)
	var p0 := s0 + Vector2(10, 0)
	_place_player(p0)
	await _frames(0.3)
	player.hp = player.max_hp()
	_place_stalker(s0)
	_wake(p0)
	var st := {"hp": int(player.hp), "hit_t": -1.0, "retreat": 0.0, "gap": 0.0, "next_t": -1.0, "was": false, "prev": s0}
	await _frames(8.0, func(t: float, _dt: float) -> void:
		if float(st["hit_t"]) < 0.0 and int(player.hp) < int(st["hp"]):
			st["hit_t"] = t
			st["retreat"] = stalker.global_position.distance_to(st["prev"])
			st["gap"] = stalker.global_position.distance_to(player.global_position)
		elif float(st["hit_t"]) >= 0.0 and float(st["next_t"]) < 0.0 and stalker.winding and not bool(st["was"]):
			st["next_t"] = t
		st["was"] = stalker.winding
		st["prev"] = stalker.global_position)
	check("Stalker stojący przy graczu zadaje cios", float(st["hit_t"]) >= 0.0)
	if float(st["hit_t"]) >= 0.0:
		info("po ciosie: cofnięcie %.0f px, odstęp od gracza %.0f px, następny zamach po %s" % [
			float(st["retreat"]), float(st["gap"]), ("%.1f s" % (float(st["next_t"]) - float(st["hit_t"]))) if float(st["next_t"]) >= 0.0 else "ponad %.0f s" % (8.0 - float(st["hit_t"]))])
	_sleep()
	await _frames(0.2)
