extends "res://scripts/stalker_test.gd"
## Test headless baterii 4,5 V (BATTERY_PLAN.md B0–B1):
##
##   godot --headless --path . -- --host --mission=z1_m1 --batterytest --autoquit=40
##
## 1. Mapa: znaczniki `y` dają baterie na ziemi (MapBattery*).
## 2. Pełna latarka nie bierze baterii; słaba bierze +BATTERY_PICKUP s; ponad BATTERY_MAX nie wchodzi; od BATTERY_TAKE_BELOW w górę leży dalej.
## 3. Bot ustępuje człowiekowi, któremu brakuje baterii; gdy człowiek ma pełną — bot bierze.
## 4. Sejf patrolu zostawia baterię; Ćma nie ma losowego zrzutu (bateria tylko z rozbitego gniazda), Ślepiec ma.
## 5. Dziennik sesji: `bat` w próbce `pos`, zdarzenia `battery` i `battery_empty`, liczniki do `mission_end.battery`.
## Mapa 1.1, reszta świata wyciszona jak w stalker_test.gd. Wynik: linie [BATTERY-TEST] i kod wyjścia.

const SessionLog := preload("res://scripts/session_log.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")
const LOG_DIR := "user://test_battery_sessions"

var bot: CharacterBody2D

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[BATTERY-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[BATTERY-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[BATTERY-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(0.5).timeout
	if not m.companion_on:                          # zapis ustawień może mieć towarzysza wyłączonego — test potrzebuje bota (bez zmiany ustawień)
		m.companion_on = true
		m._reconcile_bots()
	for _i in 40:                                   # bot dołącza chwilę po hoście
		await get_tree().create_timer(0.1).timeout
		player = m.get_node("Players").get_node_or_null("1")
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_bot:
				bot = p
		if player != null and bot != null:
			break
	await get_tree().create_timer(0.5).timeout
	check("mapa ma gracza i bota", player != null and bot != null)
	if player == null or bot == null:
		_finish()
		return
	stalker = level.get_node_or_null("Stalker")
	_isolate()
	if stalker != null:
		stalker.queue_free()
	SessionLog.enabled = true                      # dziennik w headless: osobny katalog testu, kasowany na końcu
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "battery"})
	await _map_items()
	await _take_rules()
	await _bot_yields()
	await _sources()
	await _empty_and_log()
	_cleanup_log()
	_finish()

## Bateria na ziemi o tej nazwie albo null.
func _battery_items() -> Array:
	return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "battery" and not n.is_queued_for_deletion())

func _spawn_at(pos: Vector2) -> Node2D:
	var before := _battery_items()
	level.spawn_item("battery", 0, pos)
	await _frames(0.9)                                             # podskok i lądowanie
	for n in _battery_items():
		if not before.has(n):
			return n
	return null

# ---------------------------------------------------------------- 1. mapa

func _map_items() -> void:
	var on_map := _battery_items().filter(func(n: Node) -> bool: return String(n.name).begins_with("MapBattery"))
	var markers: int = (level._map_items.get("y", []) as Array).size()
	check("znaczniki `y` mapy %s: %d, baterii na ziemi %d" % [level.map_id, markers, on_map.size()], markers >= 2 and on_map.size() == markers)

# ---------------------------------------------------------------- 2. kto i ile bierze

func _take_rules() -> void:
	var item: Node2D = _battery_items()[0] if not _battery_items().is_empty() else null
	if item == null:
		check("bateria na mapie do testu", false)
		return
	await _frames(0.5)
	player.battery = player.BATTERY_MAX
	_place_player(item.global_position)
	await _frames(0.6)
	check("pełna latarka nie bierze baterii", is_instance_valid(item) and not item.is_queued_for_deletion())
	player.battery = player.BATTERY_MAX * 0.2
	await _frames(0.6)
	var got: float = player.battery
	check("20%% → bierze: %.1f s (oczekiwane ok. %.1f), bat_pct %d" % [got, player.BATTERY_MAX * 0.2 + player.BATTERY_PICKUP, player.bat_pct],
		not is_instance_valid(item) or item.is_queued_for_deletion())
	check("+BATTERY_PICKUP s", absf(got - (player.BATTERY_MAX * 0.2 + player.BATTERY_PICKUP)) < 1.0 and player.bat_pct == player.battery_pct())
	# od BATTERY_TAKE_BELOW w górę leży; niżej bierze, ale nie ponad pełną
	player.battery = player.BATTERY_MAX * 0.95
	var it2 := await _spawn_at(player.global_position)
	check("95% → bateria zostaje na ziemi", it2 != null and not it2.is_queued_for_deletion())
	player.battery = player.BATTERY_MAX * 0.8
	await _frames(0.4)
	check("80%% → bierze, bez przekroczenia pełnej (%.1f / %.0f)" % [player.battery, player.BATTERY_MAX],
		(it2 == null or not is_instance_valid(it2) or it2.is_queued_for_deletion()) and is_equal_approx(player.battery, player.BATTERY_MAX))

# ---------------------------------------------------------------- 3. bot ustępuje człowiekowi

func _bot_yields() -> void:
	var spot: Vector2 = player.global_position
	player.battery = player.BATTERY_MAX * 0.5
	_place_player(spot + Vector2(-60.0, 0.0))                       # człowiek w zasięgu rezerwy, ale nie dotyka baterii
	bot.global_position = spot
	bot.battery = bot.BATTERY_MAX * 0.1
	var it := await _spawn_at(spot)
	await _frames(0.6)
	check("bot (10%) nie bierze, gdy człowiek obok ma 50%", it != null and not it.is_queued_for_deletion())
	player.battery = player.BATTERY_MAX
	await _frames(0.6)
	check("człowiek pełny → bot bierze (bot %.0f s)" % bot.battery,
		(it == null or not is_instance_valid(it) or it.is_queued_for_deletion()) and absf(bot.battery - (bot.BATTERY_MAX * 0.1 + bot.BATTERY_PICKUP)) < 1.0)
	bot.global_position = Vector2(-4000, -4000)

# ---------------------------------------------------------------- 4. źródła

func _sources() -> void:
	player.battery = player.BATTERY_MAX
	var sb: Node2D = get_tree().get_first_node_in_group("strongboxes")
	if sb == null:
		info("brak sejfu na mapie %s — pomijam" % level.map_id)
	else:
		_place_player(sb.global_position + Vector2(-200.0, 0.0))
		var n0 := _battery_items().size()
		sb._open()
		await _frames(1.0)
		check("sejf zostawia baterię (%d → %d)" % [n0, _battery_items().size()], _battery_items().size() == n0 + 1)
	check("Ćma bez losowego zrzutu, Ślepiec %.2f, Trzosek %.2f" % [EnemyDefs.value("slepiec", "battery"), EnemyDefs.value("trzosek", "battery")],
		EnemyDefs.value("cma", "battery") == 0.0 and EnemyDefs.value("slepiec", "battery") > EnemyDefs.value("trzosek", "battery") and EnemyDefs.value("trzosek", "battery") > 0.0)

# ---------------------------------------------------------------- 5. pusta latarka i dziennik

func _empty_and_log() -> void:
	player.battery = 0.4
	player.flashlight = true
	await _frames(0.8)
	check("pusta bateria gasi latarkę", not player.flashlight)
	check("licznik pustych latarek %d, zebranych %d, wyrzuconych %d" % [int(SessionLog._battery.get("empty", 0)), int(SessionLog._battery.get("picked", 0)),
		int(SessionLog._battery.get("dropped", 0))], int(SessionLog._battery.get("empty", 0)) >= 1 and int(SessionLog._battery.get("picked", 0)) >= 3
		and int(SessionLog._battery.get("dropped", 0)) >= 3)
	var mis := get_tree().get_first_node_in_group("mission")
	if mis != null:
		mis._log_positions()
	var rows := _log_rows()
	var pos_bat := rows.filter(func(r: Dictionary) -> bool: return r.get("ev") == "pos" and (r.get("p", []) as Array).any(func(q: Dictionary) -> bool: return q.has("bat")))
	var picks := rows.filter(func(r: Dictionary) -> bool: return r.get("ev") == "battery" and r.get("src") == "pickup")
	var empties := rows.filter(func(r: Dictionary) -> bool: return r.get("ev") == "battery_empty")
	check("dziennik: pos z `bat` %d, battery %d, battery_empty %d" % [pos_bat.size(), picks.size(), empties.size()],
		not pos_bat.is_empty() and picks.size() >= 3 and not empties.is_empty())

func _log_rows() -> Array:
	var out: Array = []
	if SessionLog.path == "" or not FileAccess.file_exists(SessionLog.path):
		return out
	for line in FileAccess.get_file_as_string(SessionLog.path).split("\n", false):
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			out.append(v)
	return out

func _cleanup_log() -> void:
	SessionLog.reset_for_test()                      # zwalnia plik (inaczej Windows nie da go skasować)
	SessionLog.enabled = false
	var d := DirAccess.open(LOG_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_DIR))
