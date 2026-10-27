extends "res://scripts/stalker_test.gd"
## Test headless ustawienia bota przy dowódcy (`player._behind_side`):
##
##   godot --headless --path . -- --host --bottest --autoquit=40
##
## 1. Idący dowódca: bot trzyma się za jego plecami w obie strony — nie wchodzi w linię ognia (w dziennikach sesji bot szedł przed
##    człowiekiem w 33% próbek, a friendly fire dawał 9% hałasu).
## 2. Stojący dowódca odwrócony na dłużej: bot przechodzi mu za plecy.
## 3. Krótki obrót (strzał do tyłu): bot zostaje po swojej stronie.
## Mapa 1.3, reszta świata wyciszona jak w stalker_test.gd (helpery stamtąd). Wynik: linie [BOT-TEST] i kod wyjścia.

const WALK := 60.0                    ## px/s dowódcy — wolniej niż bot (0,85 × 95), żeby nadążał
const AHEAD_MAX := 0.1                ## dopuszczalny ułamek próbek z botem przed idącym dowódcą
const SessionLog := preload("res://scripts/session_log.gd")

var bot: CharacterBody2D

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[BOT-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[BOT-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[BOT-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	stalker = level.get_node_or_null("Stalker")
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			bot = p
	check("mapa ma gracza i bota", player != null and bot != null)
	if player == null or bot == null:
		_finish()
		return
	_isolate()
	if stalker != null:
		stalker.queue_free()
	bot.set_physics_process(true)                  # _isolate wyłącza wszystkich poza graczem
	bot.set_process(true)
	player.set_physics_process(false)              # dowódcę prowadzi test: pozycja, prędkość i celowanie jak u gracza z klawiaturą
	await get_tree().create_timer(0.3).timeout
	var ground := _longest_run(["dirt", "concrete"])
	check("pas zwykłego gruntu (%d kafli)" % int(ground.get("len", 0)), int(ground.get("len", 0)) >= 12)
	if int(ground.get("len", 0)) >= 12:
		var a: Vector2 = ground["a"]
		var b: Vector2 = ground["b"]
		_lead(Vector2.ZERO, Vector2(1, 0), a + Vector2(30, 0))
		bot.global_position = a + Vector2(30, 0)
		bot.velocity = Vector2.ZERO
		await _frames(1.0, func(_t: float, _dt: float) -> void: _lead(Vector2.ZERO, Vector2(1, 0)))
		await _walk(1.0, b.x - 30.0)
		await _walk(-1.0, a.x + 30.0)
		await _turn(ground)
	if SessionLog.recording():
		bot.deliver_ff(player.global_position, int(player.player_id))     # CI: zdarzenie „ff” ze strzelcem w dzienniku (--sessionlog)
	_finish()

## Dowódca: pozycja (opcjonalnie), prędkość i kierunek celowania — to, co serwer widzi u każdego gracza (replikowane).
func _lead(vel: Vector2, aim: Vector2, pos := Vector2.INF) -> void:
	if pos != Vector2.INF:
		player.global_position = pos
	player.velocity = vel
	player.aim_dir = aim

## Idzie w stronę `dir` do x = `stop`; liczy próbki, w których bot jest przed dowódcą (po 1 s na dogonienie).
func _walk(dir: float, stop: float) -> void:
	var st := {"n": 0, "ahead": 0}
	await _frames(absf(stop - player.global_position.x) / WALK, func(t: float, dt: float) -> void:
		_lead(Vector2(dir * WALK, 0), Vector2(dir, 0), player.global_position + Vector2(dir * WALK * dt, 0))
		if t > 1.0 and absf(bot.global_position.y - player.global_position.y) < 20.0:
			st["n"] = int(st["n"]) + 1
			if (bot.global_position.x - player.global_position.x) * dir > 4.0:
				st["ahead"] = int(st["ahead"]) + 1)
	var frac := float(st["ahead"]) / maxf(1.0, float(st["n"]))
	check("dowódca idzie %s: bot przed nim w %.0f%% próbek (≤ %.0f%%)" % ["w prawo" if dir > 0.0 else "w lewo", frac * 100.0, AHEAD_MAX * 100.0],
		int(st["n"]) > 30 and frac <= AHEAD_MAX)

## Stojący dowódca: krótki obrót nie przestawia bota, długi tak.
func _turn(ground: Dictionary) -> void:
	var mid: Vector2 = ((ground["a"] as Vector2) + (ground["b"] as Vector2)) * 0.5
	_lead(Vector2.ZERO, Vector2(1, 0), mid)
	await _frames(2.0, func(_t: float, _dt: float) -> void: _lead(Vector2.ZERO, Vector2(1, 0)))
	var before := signf(bot.global_position.x - player.global_position.x)
	check("stojący dowódca patrzy w prawo: bot po lewej (za plecami)", before < 0.0)
	await _frames(0.3, func(_t: float, _dt: float) -> void: _lead(Vector2.ZERO, Vector2(-1, 0)))
	await _frames(1.0, func(_t: float, _dt: float) -> void: _lead(Vector2.ZERO, Vector2(1, 0)))
	check("krótki obrót do tyłu (0,3 s): bot zostaje po lewej", signf(bot.global_position.x - player.global_position.x) < 0.0)
	await _frames(3.0, func(_t: float, _dt: float) -> void: _lead(Vector2.ZERO, Vector2(-1, 0)))
	check("dowódca odwrócony na dłużej: bot przechodzi na prawo (za plecy)", signf(bot.global_position.x - player.global_position.x) > 0.0)
