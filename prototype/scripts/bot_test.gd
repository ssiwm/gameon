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
## 7. Znacznik plwociny Żyły: bot schodzi z niego i nie podnosi pod ostrzałem, po rozbryzgu podnosi.
## 8. Pchanie skrzyni (zgłoszenie z gry na 1.1: postać sunęła za skrzynią w pozie stojącej, bo `velocity` po zderzeniu jest zerowa):
##    gracz z klawiatury pcha skrzynię → `push_state` ±1 i animacja „push”; napór na skrzynię, która stoi → ±2 i „push” bez kroku;
##    pchanie plecami (celuje w drugą stronę) → chód tyłem w tempie skrzyni; odejście od skrzyni tyłem → od razu zwykły chód tyłem;
##    bot (ten sam `_push_props` na serwerze); zdalny gracz rysuje to samo z samego replikowanego `push_state`.
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
	var vein: Node2D = get_tree().get_first_node_in_group("boss")
	if vein != null:
		vein.remove_from_group("enemies")           # Żyła zostaje (punkt 7: znacznik plucia), ale śpi i nie jest celem bota
		vein.set_physics_process(false)
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
		await _spit_dodge(ground)
		await _push_crate(ground)
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

## 7. Znacznik plwociny Żyły (opinia testera 2026-10-29): bot obok leżącego dowódcy nie podnosi go, gdy plwocina ma spaść
##    tutaj — schodzi ze znacznika, a po rozbryzgu wraca i podnosi.
func _spit_dodge(ground: Dictionary) -> void:
	var boss: Node2D = get_tree().get_first_node_in_group("boss")
	if boss == null:
		check("Żyła na mapie do testu plucia", false)
		return
	var a: Vector2 = ground["a"]
	_lead(Vector2.ZERO, Vector2(1, 0), a + Vector2(60, 0))
	player.dead = true
	player.revive_progress = 0.0
	bot.global_position = a + Vector2(68, 0)
	bot.velocity = Vector2.ZERO
	await _frames(0.2)
	boss.atk = 2                                    # Atk.SPIT: zapowiedź trwa, znacznik nie znika
	boss.spit_mark = a + Vector2(64, 0)
	var st := {"rev": 0.0, "far": 0.0}
	await _frames(0.8, func(_t: float, _dt: float) -> void:
		st["rev"] = maxf(float(st["rev"]), player.revive_progress)
		st["far"] = maxf(float(st["far"]), absf(bot.global_position.x - boss.spit_mark.x)))
	boss.atk = 0
	boss.spit_mark = Vector2.INF
	var after := {"rev": 0.0}
	await _frames(1.5, func(_t: float, _dt: float) -> void:
		after["rev"] = maxf(float(after["rev"]), player.revive_progress))
	check("znacznik plucia: bot schodzi (%.0f px od środka), nie podnosi pod nim (postęp %.2f), po rozbryzgu podnosi (%.2f)" % [st["far"], st["rev"], after["rev"]],
		float(st["far"]) >= float(boss.SPIT_HIT_R) + bot.BOT_SPIT_MARGIN - 2.0 and is_zero_approx(float(st["rev"])) and float(after["rev"]) > 0.0)
	player.dead = false
	player.revive_progress = 0.0

# ---------------------------------------------------------------- 8. pchanie skrzyni

const Prop := preload("res://scripts/prop.gd")

func _keys(press: Array, release: Array) -> void:
	for a in release:
		Input.action_release(a)
	for a in press:
		Input.action_press(a)

## Skrzynia stojąca na ziemi tuż przed graczem (ściana skrzyni styka się z jego hitboxem po pierwszym kroku).
func _crate_before(who: Node2D, dir: float) -> RigidBody2D:
	var pr: RigidBody2D = Prop.new()
	pr.kind = "crate"
	level.add_child(pr)
	pr.global_position = who.global_position + Vector2(dir * 13.0, 0.0)
	return pr

func _push_crate(ground: Dictionary) -> void:
	var a: Vector2 = ground["a"]
	bot.set_physics_process(false)
	bot.global_position = Vector2(-4000, -4000)
	player.dead = false
	player.global_position = a + Vector2(40, 0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)               # gracz idzie z klawiatury: prawdziwy `_local_brain` i `move_and_slide`
	await _frames(0.3)
	var crate := _crate_before(player, 1.0)
	var x0 := crate.global_position.x
	var st := {"push": 0, "anim": 0, "n": 0}
	_keys(["move_right", "aim_right"], [])
	await _frames(1.2, func(t: float, _dt: float) -> void:
		if t > 0.4:
			st["n"] = int(st["n"]) + 1
			if player.push_state == 1:
				st["push"] = int(st["push"]) + 1
			var an: Array = player._char_anim()
			if String(an[0]) == "push" and float(an[1]) > 10.0:
				st["anim"] = int(st["anim"]) + 1)
	var moved := crate.global_position.x - x0
	check("pchanie przodem: skrzynia jedzie (%.0f px), push_state = 1 w %d/%d próbek, animacja „push” z krokiem w %d/%d (velocity.x gracza %.0f)" % [moved, st["push"], st["n"], st["anim"], st["n"], player.velocity.x],
		moved > 20.0 and int(st["push"]) >= int(st["n"]) * 0.9 and int(st["anim"]) >= int(st["n"]) * 0.9)
	# skrzynia zaparta o ścianę tuż za nią — napór bez ruchu
	var wall := StaticBody2D.new()
	var wcs := CollisionShape2D.new()
	var wsh := RectangleShape2D.new()
	wsh.size = Vector2(8, 40)
	wcs.shape = wsh
	wall.add_child(wcs)
	level.add_child(wall)
	wall.global_position = crate.global_position + Vector2(7.0 + 4.5, -20.0)
	await _frames(0.3)
	var xs := crate.global_position.x
	var strain := {"ok": 0, "n": 0}
	await _frames(0.8, func(t: float, _dt: float) -> void:
		if t > 0.4:
			strain["n"] = int(strain["n"]) + 1
			var an: Array = player._char_anim()
			if player.push_state == 2 and String(an[0]) == "push" and is_zero_approx(float(an[1])):
				strain["ok"] = int(strain["ok"]) + 1)
	check("napór na stojącą skrzynię: push_state = 2 i „push” bez kroku w %d/%d próbek (skrzynia przesunęła się o %.1f px)" % [strain["ok"], strain["n"], crate.global_position.x - xs],
		int(strain["ok"]) >= int(strain["n"]) * 0.9 and absf(crate.global_position.x - xs) < 1.0)
	wall.queue_free()
	# plecami: idzie w prawo, celuje w lewo — chód tyłem w tempie skrzyni, nie stanie w miejscu
	_keys(["aim_left"], ["aim_right"])
	var back := {"ok": 0, "n": 0}
	await _frames(1.0, func(t: float, _dt: float) -> void:
		if t > 0.4:
			back["n"] = int(back["n"]) + 1
			var an: Array = player._char_anim()
			if player.push_state == 1 and String(an[0]) == "run" and float(an[1]) > 10.0 and player._facing < 0.0:
				back["ok"] = int(back["ok"]) + 1)
	check("pchanie plecami: chód tyłem w tempie skrzyni w %d/%d próbek" % [back["ok"], back["n"]], int(back["ok"]) >= int(back["n"]) * 0.9)
	# odejście od skrzyni tyłem (celuje w skrzynię): stan pchania znika od razu, zwykły chód tyłem
	_keys(["move_left", "aim_right"], ["move_right", "aim_left"])
	var away := {"t": -1.0, "run": 0, "n": 0}
	await _frames(0.6, func(t: float, _dt: float) -> void:
		if player.push_state == 0 and float(away["t"]) < 0.0:
			away["t"] = t
		if t > 0.2:
			away["n"] = int(away["n"]) + 1
			var an: Array = player._char_anim()
			if String(an[0]) == "run" and float(an[1]) < -10.0 and player._facing > 0.0:
				away["run"] = int(away["run"]) + 1)
	check("odejście tyłem: push_state = 0 po %.2f s (≤ 0,15), chód tyłem w %d/%d próbek" % [away["t"], away["run"], away["n"]],
		float(away["t"]) >= 0.0 and float(away["t"]) <= 0.15 and int(away["run"]) >= int(away["n"]) * 0.9)
	_keys([], ["move_left", "aim_right"])
	player.set_physics_process(false)
	# bot: ten sam `_push_props` po jego `move_and_slide` (mózg bota przeskakuje skrzynie, więc ruch prowadzi test)
	bot.global_position = (ground["b"] as Vector2) - Vector2(200, 0)     # z dala od skrzyni gracza i od końca pasa
	bot.velocity = Vector2.ZERO
	bot.is_reviving = false                        # mózg bota stoi od testu plucia: zostałby w klęczeniu przy dowódcy
	bot.crouching = false
	bot.aim_dir = Vector2(1, 0)
	await _frames(0.2, func(_t: float, dt: float) -> void:
		bot.velocity.y += 980.0 * dt
		bot.move_and_slide())
	var bcrate := _crate_before(bot, 1.0)
	var bx0 := bcrate.global_position.x
	var bst := {"ok": 0, "n": 0}
	await _frames(1.0, func(t: float, dt: float) -> void:
		bot.velocity = Vector2(80.0, bot.velocity.y + 980.0 * dt)
		bot.move_and_slide()
		bot._push_props(dt)
		if t > 0.4:
			bst["n"] = int(bst["n"]) + 1
			if bot.push_state == 1 and String(bot._char_anim()[0]) == "push":
				bst["ok"] = int(bst["ok"]) + 1)
	check("bot pcha skrzynię: push_state = 1 i „push” w %d/%d próbek, skrzynia %.0f px (ostatnio %d, %s)" % [bst["ok"], bst["n"], bcrate.global_position.x - bx0, bot.push_state, bot._char_anim()[0]],
		int(bst["ok"]) >= int(bst["n"]) * 0.9 and bcrate.global_position.x - bx0 > 20.0)
	# zdalny gracz: tylko replikowane pola (pozycja, velocity po zderzeniu = 0, push_state) — wybór animacji ten sam
	var sync: MultiplayerSynchronizer = player.get_node_or_null("MultiplayerSynchronizer")
	check("push_state w replikacji gracza", sync != null and sync.replication_config.has_property(":push_state"))
	var was_remote: bool = player._is_remote
	player._is_remote = true
	player.velocity = Vector2.ZERO
	player.aim_dir = Vector2(1, 0)
	player.push_state = 1
	var r1: Array = player._char_anim()
	player.push_state = 2
	var r2: Array = player._char_anim()
	player.aim_dir = Vector2(-1, 0)
	player.push_state = 1
	var r3: Array = player._char_anim()
	player.push_state = 0
	player._is_remote = was_remote
	check("zdalny gracz: pchanie %s/%.0f, napór %s/%.0f, plecami %s/%.0f" % [r1[0], r1[1], r2[0], r2[1], r3[0], r3[1]],
		r1[0] == "push" and float(r1[1]) == Prop.PUSH_SPEED and r2[0] == "push" and float(r2[1]) == 0.0 and r3[0] == "run" and float(r3[1]) > 10.0)
	crate.queue_free()
	bcrate.queue_free()
