extends "res://scripts/stalker_test.gd"
## Test headless ustawienia bota przy dowódcy (`player._behind_side`):
##
##   godot --headless --path . -- --host --bottest --autoquit=40
##
## 1. Idący dowódca: bot trzyma się za jego plecami w obie strony — nie wchodzi w linię ognia (w dziennikach sesji bot szedł przed
##    człowiekiem w 33% próbek, a friendly fire dawał 9% hałasu).
## 2. Stojący dowódca odwrócony na dłużej: bot przechodzi mu za plecy.
## 3. Krótki obrót (strzał do tyłu): bot zostaje po swojej stronie.
## 4. Linia ognia (`player._los_state`): bot za dowódcą, wróg kilkanaście stopni wyżej — kierunek strzału przycięty do 8 stron
##    jest poziomy, więc kula trafia dowódcę w plecy, choć promień prosto do wroga mija mu głowę. Bot ma uznać, że kolega stoi
##    na linii (dziennik 1.7.399: 61 trafień bota w człowieka w jednej sesji).
## 5. Skradanie (opinia testera 2026-10-29): dowódca kuca, bot w skoku nie kuca — mimo to nie strzela do wroga dalej niż na
##    wyciągnięcie ręki.
## 6. Podnoszenie w locie (opinia testera 2026-10-29): bot spadający obok leżącego nie zaczyna podnosić w powietrzu, dopiero
##    po wylądowaniu.
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
		await _line_of_fire(ground)
		await _stealth_fire()
		await _airborne_revive(ground)
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

## Linia ognia: dowódca 80 px przed botem, cel 200 px przed botem i 45 px wyżej (kąt ok. 13° → strzał poziomo).
func _line_of_fire(ground: Dictionary) -> void:
	var a: Vector2 = ground["a"]
	bot.set_physics_process(false)                 # bez mózgu bota: test sam ustawia miejsca i sam strzela
	_lead(Vector2.ZERO, Vector2(1, 0), a + Vector2(110, 0))
	bot.global_position = a + Vector2(30, 0)
	bot.velocity = Vector2.ZERO
	bot.crouching = false
	var target := Node2D.new()                     # sam punkt celu — bez grupy „enemies”, nic innego go nie widzi
	level.add_child(target)
	target.global_position = a + Vector2(230, -45)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var d := target.global_position - bot.global_position
	var dir: Vector2 = bot._snap8(d)
	check("cel %.0f° wyżej: kierunek strzału bota przycięty do poziomu" % rad_to_deg(-d.angle()), dir.is_equal_approx(Vector2(1, 0)))
	var q := PhysicsRayQueryParameters2D.create(bot.global_position + Vector2(0, -9), target.global_position + Vector2(0, -6), 1 | 2)
	q.exclude = [bot.get_rid()]
	var old_ray := bot.get_world_2d().direct_space_state.intersect_ray(q)
	info("promień prosto do celu (stary test linii) %s" % ("mija dowódcę" if old_ray.is_empty() else "trafia w %s" % old_ray["collider"].name))
	var hits := 0
	for _i in 3:
		player.set("_kick", 0.0)
		bot.weapons.cd = 0.0
		bot.weapons.bot_fire(dir)
		await _frames(0.4)
		if absf(float(player.get("_kick"))) > 0.0:
			hits += 1
	player.set("_kick", 0.0)
	check("kula bota po przyciętym kierunku trafia dowódcę (%d/3)" % hits, hits > 0)
	check("bot widzi kolegę na torze strzału", bot._los_state(target, dir) == bot.Los.TEAMMATE)
	_lead(Vector2.ZERO, Vector2(1, 0), a + Vector2(10, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("dowódca za botem: tor strzału czysty", bot._los_state(target, dir) == bot.Los.CLEAR)
	target.queue_free()
	bot.set_physics_process(true)

## 5. Dyscyplina ognia przy skradaniu liczy się od dowódcy, nie od własnego `crouching` bota (gubi je w skoku i zeskoku).
func _stealth_fire() -> void:
	player.crouching = true
	bot.crouching = false
	var far_ok: bool = not bot._bot_may_fire(Vector2(60.0, 0.0))
	var near_ok: bool = bot._bot_may_fire(Vector2(30.0, 0.0))
	player.crouching = false
	check("dowódca kuca, bot w skoku: wróg 60 px — bez strzału, 30 px — obrona własna", far_ok and near_ok)
	await get_tree().physics_frame

## 6. Bot spada obok leżącego dowódcy: w powietrzu postęp podnoszenia stoi na zero, po wylądowaniu rośnie.
func _airborne_revive(ground: Dictionary) -> void:
	var a: Vector2 = ground["a"]
	_lead(Vector2.ZERO, Vector2(1, 0), a + Vector2(60, 0))
	player.dead = true
	player.revive_progress = 0.0
	bot.global_position = a + Vector2(72, -40)
	bot.velocity = Vector2.ZERO
	var st := {"air": 0, "air_rev": 0, "landed_rev": false}
	await _frames(2.0, func(_t: float, _dt: float) -> void:
		if not bot.is_on_floor():
			st["air"] += 1
			if player.revive_progress > 0.0:
				st["air_rev"] += 1
		elif player.revive_progress > 0.0:
			st["landed_rev"] = true)
	check("bot w powietrzu nie podnosi (%d klatek lotu, %d z postępem), po wylądowaniu podnosi=%s" % [st["air"], st["air_rev"], str(st["landed_rev"])],
		int(st["air"]) > 3 and int(st["air_rev"]) == 0 and bool(st["landed_rev"]))
	player.dead = false
	player.revive_progress = 0.0
