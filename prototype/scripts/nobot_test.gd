extends Node
## Test headless gry bez AI towarzysza (NOBOT_PLAN.md):
##
##   godot --headless --path . -- --host --nobot --mission=z1_m2 --nobottest --autoquit=60   # misja z drezyną
##   godot --headless --path . -- --host --nobot --mission=z1_hub --nobottest --autoquit=30  # kryjówka: przełącznik hosta
##
## Misja: bez bota w drużynie; przełącznik zablokowany (zmiana tylko w lobby i kryjówce); samotny człowiek pompuje drezynę z mocą 1,5;
## stojący na jadącej drezynie nie tupie (idący po pokładzie tak); przy wysokiej Uwadze nie bije serce;
## pierwszy upadek nie kończy próby — wykrwawienie i powrót na start z 1 HP; drugi upadek w tej samej próbie = wipe.
## Układ „Drabina” 1.2 (MAPS_PLAN.md §4, D1): stopień nad torem, odrodzenie przy generatorze i przy drezynie, zawał podestu po nadawaniu, restart.
## Kryjówka: włączenie towarzysza dodaje bota od razu, wyłączenie go usuwa. Wynik: linie [NOBOT-TEST] i kod wyjścia.

var main: Node2D
var player: CharacterBody2D
var failed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[NOBOT-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func run(m: Node2D) -> void:
	main = m
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	check("towarzysz wyłączony (--nobot), host widzi OFF", m.companion_on == false and Settings.ai_companion == false)
	check("w drużynie nie ma bota (graczy: %d)" % _team().size(), _bots() == 0 and player != null)
	if player == null:
		_finish()
		return
	if m.mission.kind == "hub":
		await _hub_toggle()
	else:
		check("w misji przełącznik zablokowany (zmiana tylko w lobby i kryjówce)", not m.companion_editable())
		await _handcar()
		await _heart()
		await _ladder()
		await _falls()
	_finish()

func _finish() -> void:
	print("[NOBOT-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func _team() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())

func _bots() -> int:
	return _team().filter(func(p: Node) -> bool: return p.is_bot).size()

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

## Kryjówka: host przełącza towarzysza — bot pojawia się i znika od razu (bez zapisu ustawień: przypisanie + sygnał).
func _hub_toggle() -> void:
	check("w kryjówce przełącznik dostępny dla hosta", main.companion_editable())
	Settings.ai_companion = true
	Settings.changed.emit()
	await _frames(10)
	check("włączenie w kryjówce dodaje bota (botów: %d)" % _bots(), main.companion_on and _bots() == 1)
	Settings.ai_companion = false
	Settings.changed.emit()
	await _frames(10)
	check("wyłączenie w kryjówce usuwa bota (botów: %d)" % _bots(), not main.companion_on and _bots() == 0)

## Drezyna (mapa 1.2): samotny człowiek na pokładzie, pompuje — moc jak człowiek z botem.
func _handcar() -> void:
	var car: Node2D = get_tree().get_first_node_in_group("handcar")
	if car == null:
		print("[NOBOT-TEST] INFO  mapa bez drezyny — pomijam moc pompowania")
		return
	var start := player.global_position
	player.global_position = car.global_position + Vector2(0, -1)
	player.velocity = Vector2.ZERO
	await _frames(2)
	car._workers[String(player.name)] = true
	await _frames(3)
	check("drezyna: sam bez bota pompuje z mocą %.1f (= %.1f)" % [float(car.power), float(car.SOLO_POWER)], is_equal_approx(float(car.power), float(car.SOLO_POWER)))
	await _ride_steps(car)
	car._workers.clear()
	car.reset_handcar()
	player.global_position = start
	await _frames(3)

## Kroki na jadącej drezynie (zgłoszenie po 1.7.436): stojący pasażer nie tupie — wozi go drezyna, nie nogi; idący
## po pokładzie tupie jak dotąd; cudza postać (pozycja z replikacji co 0,05 s, schodkami) też nie tupie, gdy stoi.
func _ride_steps(car: Node2D) -> void:
	car.enabled = true
	player.global_position = car.global_position + Vector2(-30, -1)
	await _frames(3)
	var x0: float = car.global_position.x
	var steps0: int = player.footsteps
	await _frames(120)
	var ride: float = x0 - float(car.global_position.x)
	check("drezyna: stojący na jadącej (%.0f px) nie tupie (kroków %d)" % [ride, player.footsteps - steps0],
		ride > 80.0 and car.aboard(player) and player.footsteps == steps0)
	steps0 = player.footsteps
	Input.action_press("move_right")
	for _i in 60:
		await get_tree().physics_frame
		if player.global_position.x - car.global_position.x > 30.0:
			break
	Input.action_release("move_right")
	check("drezyna: idący po pokładzie (%.0f px od środka) tupie (kroków %d)" % [player.global_position.x - car.global_position.x, player.footsteps - steps0],
		player.footsteps > steps0 and car.aboard(player))
	await _frames(5)
	player.set_physics_process(false)
	var off: float = player.global_position.x - car.global_position.x
	var at := player.global_position
	steps0 = player.footsteps
	x0 = car.global_position.x
	for i in 90:
		await get_tree().physics_frame
		if i % 3 == 0:
			at.x = car.global_position.x + off
		player.global_position = at
		player._update_footsteps_passive()
	player.set_physics_process(true)
	ride = x0 - float(car.global_position.x)
	check("drezyna: cudza postać z replikacji stoi na jadącej (%.0f px) i nie tupie (kroków %d)" % [ride, player.footsteps - steps0],
		ride > 80.0 and player.footsteps == steps0)

## Bicie serca przy wysokiej Uwadze usunięte (kolidowało z muzyką): żadna pętla serca nie gra.
func _heart() -> void:
	var lvl0: float = NoiseMgr.level
	NoiseMgr.level = NoiseMgr.MAX_LEVEL * 0.6
	await _frames(10)
	var playing: bool = Audio.loop_playing("heart_fast_loop") or Audio.loop_playing("heart_slow_loop")
	NoiseMgr.level = lvl0
	await _frames(2)
	check("Uwaga 60%%: serce nie bije (pętla gra: %s)" % [playing], not playing)

## Upadki samotnego gracza: pierwszy → wykrwawienie i start z 1 HP (bez wipe'u), drugi → wipe.
func _falls() -> void:
	var attempts0: int = main.mission.attempts
	player.deliver_hit(player.hp + 3, player.global_position + Vector2(10, 0), "test", true)
	await _frames(120)                                   # 2 s leżenia: w drużynie nikt nie stoi, a wipe się nie zaczyna
	check("pierwszy upadek: gracz leży, bez wipe'u (wipe_left %.1f)" % main.wipe_left, player.dead and main.wipe_left <= 0.0)
	player.bleed_left = 0.05
	await _frames(10)
	var at_start: bool = player.global_position.distance_to(player._spawn_point) < 4.0
	check("wykrwawienie: powrót na start z 1 HP (hp %d, start %s)" % [int(player.hp), str(at_start)], not player.dead and int(player.hp) == 1 and at_start)
	check("ta sama próba (#%d), wipe nie ogłoszony" % main.mission.attempts, main.mission.attempts == attempts0 and main.wipe_left <= 0.0)
	await _frames(100)                                   # nietykalność po powrocie (1,5 s)
	player.deliver_hit(player.hp + 3, player.global_position + Vector2(10, 0), "test", true)
	await _frames(20)
	check("drugi upadek w tej próbie: wipe (wipe_left %.1f)" % main.wipe_left, player.dead and main.wipe_left > 0.0)
	await get_tree().create_timer(3.5).timeout
	check("po wipe'ie nowa próba (#%d)" % main.mission.attempts, main.mission.attempts == attempts0 + 1 and not player.dead)
	player.deliver_hit(player.hp + 3, player.global_position + Vector2(10, 0), "test", true)
	await _frames(120)
	check("nowa próba: znów pierwszy upadek bez wipe'u", player.dead and main.wipe_left <= 0.0)

## Układ „Drabina” 1.2 (MAPS_PLAN.md §4, D1). Stojący na najniższym stopniu zejścia (32 px nad torem) nie jest pasażerem drezyny, stojący
## na torze pod nim tak. Uruchomiony generator staje się punktem odrodzenia. Po ostatnim podest między studnią stacji a tunelem zasypuje się
## po FINALE_DELAY s (bez flagi finału 1.1), a wykrwawiony w ewakuacji wstaje przy drezynie. Wipe przywraca podest, start i drezynę.
func _ladder() -> void:
	var lvl: Node = get_tree().get_first_node_in_group("level")
	var car: Node2D = get_tree().get_first_node_in_group("handcar")
	if lvl == null or car == null or (lvl.collapse_rects as Array).is_empty():
		print("[NOBOT-TEST] INFO  mapa bez zawału przy nadawaniu — pomijam układ „Drabina”")
		return
	var frozen: Array = get_tree().get_nodes_in_group("enemies")
	for e in frozen:
		e.set_physics_process(false)
		e.set_process(false)
	var start: Vector2 = player._spawn_point
	# stopnie w wierszu 49 nad komorami tunelu: przy studni (kol. 68–71) i pod magazynem (kol. 213–215, etap D2)
	var car_x0: float = car.position.x
	for sc in [69, 214]:
		if not lvl._is_platform_cell(sc, 49):
			continue
		var step := Vector2(sc * 16 + 8, 49 * 16)
		car.position.x = step.x
		player.global_position = step + Vector2(0, -2)
		player.velocity = Vector2.ZERO
		await _frames(12)
		check("Drabina: stojący na stopniu w kol. %d (y %.0f, tor %.0f) nie jest pasażerem drezyny" % [sc, player.global_position.y, car.global_position.y],
			player.is_on_floor() and absf(player.global_position.y - step.y) < 2.0 and not car.aboard(player))
		player.global_position = Vector2(step.x, car.global_position.y - 2.0)
		player.velocity = Vector2.ZERO
		await _frames(12)
		check("Drabina: stojący na torze pod stopniem w kol. %d jest pasażerem" % sc, car.aboard(player))
	car.position.x = car_x0
	player.global_position = start
	player.velocity = Vector2.ZERO
	await _frames(3)
	# generatory od zachodu: każdy uruchomiony to nowy punkt odrodzenia
	var gens: Array = get_tree().get_nodes_in_group("generators")
	gens.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.x < b.global_position.x)
	var podest_open: bool = not lvl._is_solid(68, 38) and not lvl._is_solid(69, 40)
	gens[0]._start()
	await _frames(5)
	check("Drabina: po pierwszym generatorze odrodzenie przy nim (%s)" % str(player._spawn_point),
		player._spawn_point.distance_to((gens[0] as Node2D).global_position) < 1.0)
	for i in range(1, gens.size()):
		gens[i]._start()
	await _frames(5)
	var mission: Node = main.mission
	check("Drabina: po ostatnim generatorze EXTRACT, drezyna zasilona, odrodzenie przy ostatnim generatorze, bez flagi finału 1.1",
		mission.phase == mission.Phase.EXTRACT and car.enabled and not mission.finale
		and player._spawn_point.distance_to((gens[gens.size() - 1] as Node2D).global_position) < 1.0)
	check("Drabina: tuż po nadawaniu podest jeszcze wolny", podest_open and not lvl._is_solid(68, 38))
	await get_tree().create_timer(float(mission.FINALE_DELAY) + 0.5).timeout
	check("Drabina: po %.1f s podest pod studnią zasypany (do wyjścia tylko torem)" % float(mission.FINALE_DELAY), lvl._is_solid(68, 38) and lvl._is_solid(69, 40))
	for e in get_tree().get_nodes_in_group("enemies"):    # Stalker obudzony przez nadawanie i grupy finału
		e.set_physics_process(false)
		e.set_process(false)
	# wykrwawienie w ewakuacji: wstaje przy drezynie, nie przy generatorze ani na starcie
	player.global_position = (gens[0] as Node2D).global_position
	player.velocity = Vector2.ZERO
	await _frames(3)
	player.deliver_hit(player.hp + 3, player.global_position + Vector2(10, 0), "test", true)
	await _frames(30)
	player.bleed_left = 0.05
	await _frames(10)
	check("Drabina: wykrwawiony w ewakuacji wstaje przy drezynie (dx %.0f, dy %.0f)" % [player.global_position.x - car.global_position.x, player.global_position.y - car.global_position.y],
		not player.dead and absf(player.global_position.x - car.global_position.x) <= 30.0 and absf(player.global_position.y - car.global_position.y) <= 4.0)
	await main._restart_mission(false)
	await _frames(10)
	check("Drabina: restart przywraca podest, start i drezynę bez zasilania",
		not lvl._is_solid(68, 38) and not lvl._is_solid(69, 40) and player._spawn_point.distance_to(start) < 1.0 and not car.enabled)
	for e in frozen:
		if is_instance_valid(e):
			e.set_physics_process(true)
			e.set_process(true)
	await get_tree().create_timer(1.6).timeout             # nietykalność po restarcie
