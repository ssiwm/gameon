extends "res://scripts/stalker_test.gd"
## Test headless zwłok w świecie (MIMIC_PLAN.md M3–M4, corpse.gd):
##
##   godot --headless --path . -- --host --mission=z1_m1 --corpsetest --autoquit=60
##
## 1. Dane: zwłoki z CORPSES na mapie (strój, ułożenie, flagi), na 1.1 przy każdym nieśmiertelniku leży ciało.
## 2. Trzymanie [E] (prawdziwe wejście): postęp rośnie, podpowiedź HUD, puszczenie przerywa (postęp od zera).
## 3. Z daleka i bot: serwer odrzuca przeszukującego poza zasięgiem i bota.
## 4. Przeszukanie: łup z wymuszonego losowania (złom, bateria, naboje albo nic + komunikat), szelest (hałas), dziennik `corpse_search`,
##    przeszukane tylko raz.
## 5. Wipe zostawia przeszukane, nowa misja na tej samej mapie kładzie zwłoki od nowa.
## 6. Losowanie łupu (D3): ok. 60% coś, reszta nic; proporcje rodzajów.
## Mapa 1.1, reszta świata wyciszona jak w stalker_test.gd. Wynik: linie [CORPSE-TEST] i kod wyjścia.

const SessionLog := preload("res://scripts/session_log.gd")
const CORPSE := preload("res://scripts/corpse.gd")
const Actions := preload("res://scripts/actions.gd")
const LOG_DIR := "user://test_corpse_sessions"

var bot: CharacterBody2D

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[CORPSE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[CORPSE-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[CORPSE-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(0.5).timeout
	if not m.companion_on:                          # test potrzebuje bota (bez zmiany zapisanych ustawień)
		m.companion_on = true
		m._reconcile_bots()
	for _i in 40:
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
	SessionLog.enabled = true
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "corpse"})
	_data()
	await _hold_input()
	await _reach_and_bot()
	await _search_loot()
	await _wipe()
	_loot_ratio()
	_cleanup_log()
	_finish()

func _corpses() -> Array:
	return get_tree().get_nodes_in_group("corpses").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())

func _corpse(n: String) -> Node2D:
	return level.get_node_or_null(n) as Node2D

func _pickups(kind: String) -> Array:
	return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == kind and not n.is_queued_for_deletion())

## Gracz przy ciele, bez ruchu (stopy na tej samej podłodze, kawałek z boku).
func _stand_by(cp: Node2D) -> void:
	_place_player(cp.global_position + Vector2(-8.0, -1.0))

# ---------------------------------------------------------------- 1. dane

func _data() -> void:
	var defs: Array = level._corpses
	var cs := _corpses()
	check("1.1: %d zwłok z CORPSES, tyle węzłów (%d)" % [defs.size(), cs.size()], defs.size() >= 6 and cs.size() == defs.size())
	var ok := true
	for cp in cs:
		if not ["back", "side", "curl"].has(cp.pose) or not ["patrol", "tech", "miner"].has(cp.outfit):
			ok = false
			info("%s: ułożenie %s, strój %s" % [cp.name, cp.pose, cp.outfit])
		var col := int(cp.global_position.x / level.TILE)
		var row := int(cp.global_position.y / level.TILE) - 1
		var rows: Array = level._map
		if not "#CM-=".contains(String(rows[row + 1])[col]) or "#CM".contains(String(rows[row])[col]):
			ok = false
			info("%s: nie leży na podłodze (%s)" % [cp.name, cp.global_position])
	check("ułożenie i strój ze znanych, każde ciało na podłodze w powietrzu", ok)
	var tags := _pickups("tag")
	var near_all := true
	for cp in cs:
		if not bool(cp.flags.get("tag", false)):
			continue
		var has := tags.any(func(t: Node2D) -> bool: return t.global_position.distance_to(cp.global_position) < 2.5 * level.TILE)
		if not has:
			near_all = false
			info("%s bez nieśmiertelnika obok" % cp.name)
	var with_tag := cs.filter(func(c: Node) -> bool: return bool(c.flags.get("tag", false))).size()
	check("1.1: ciało przy każdym nieśmiertelniku (%d z flagą `tag`, %d nieśmiertelników)" % [with_tag, tags.size()], near_all and with_tag == tags.size())

# ---------------------------------------------------------------- 2. trzymanie [E]

func _hud() -> Node:
	return main.get_node("UI").find_child("HUD", false, false)

func _prompt_has(text: String) -> bool:
	var hud := _hud()
	if hud == null:
		return false
	return (hud._prompt_candidates() as Array).any(func(c: Dictionary) -> bool: return String(c["text"]) == text)

func _hold_input() -> void:
	var cp := _corpse("Corpse7")                     # ciało bez nieśmiertelnika (przy strażnicy) — [E] nie podnosi nic innego
	check("jest ciało bez nieśmiertelnika", cp != null and not bool(cp.flags.get("tag", false)))
	if cp == null:
		return
	_stand_by(cp)
	await _frames(0.2)
	check("lokalny gracz w zasięgu ciała", cp.local_in_range)
	check("podpowiedź HUD „Trzymaj [E] Przeszukaj ciało”", _prompt_has(Actions.fmt(tr("Hold [{interact}]  Search the body"))))
	Input.action_press("interact")
	await _frames(0.6)
	var mid: float = cp.progress
	check("trzymanie [E]: postęp %.2f po 0,6 s (ok. 0,5)" % mid, mid > 0.35 and mid < 0.7 and not cp.searched)
	check("w trakcie podpowiedź z postępem", _prompt_has(tr("Searching the body…")))
	Input.action_release("interact")
	await _frames(0.15)
	check("puszczenie [E] przerywa (postęp %.2f)" % cp.progress, cp.progress == 0.0 and not cp.searched)

# ---------------------------------------------------------------- 3. zasięg i bot

func _reach_and_bot() -> void:
	var cp := _corpse("Corpse7")
	if cp == null:
		return
	_place_player(cp.global_position + Vector2(-160.0, 0.0))
	cp.set_worker(1, true)
	await _frames(0.5)
	check("z daleka: serwer odrzuca (postęp %.2f)" % cp.progress, cp.progress == 0.0 and cp._workers.is_empty())
	check("z daleka bez podpowiedzi", not cp.local_in_range)
	bot.set_physics_process(true)
	bot.global_position = cp.global_position + Vector2(6.0, -1.0)
	bot.set_physics_process(false)
	cp._workers[String(bot.name)] = true             # nawet gdyby bot się zgłosił — serwer go nie liczy
	await _frames(0.5)
	check("bot nie przeszukuje (postęp %.2f)" % cp.progress, cp.progress == 0.0 and cp._workers.is_empty() and not cp.searched)
	bot.global_position = Vector2(-4000, -4000)

# ---------------------------------------------------------------- 4. przeszukanie i łup

func _search(cp: Node2D, loot: String) -> void:
	cp.force_loot = loot
	_stand_by(cp)
	await _frames(0.1)
	cp.set_worker(1, true)
	var t := 0.0
	while not cp.searched and t < 2.5:
		await _frames(0.05)
		t += 0.05
	cp.set_worker(1, false)

func _search_loot() -> void:
	var cp := _corpse("Corpse7")
	if cp == null:
		return
	var heard := [0.0]
	var on_noise := func(add: float, _pos: Vector2, tag: String) -> void:
		if tag == "corpse":
			heard[0] += add
	NoiseMgr.noise_added.connect(on_noise)
	var scrap0 := _pickups("scrap").size()
	var t0 := Time.get_ticks_msec()
	await _search(cp, "scrap")
	var took := float(Time.get_ticks_msec() - t0) / 1000.0
	check("przeszukane po ok. %.1f s trzymania (%.2f s)" % [CORPSE.SEARCH_TIME, took], cp.searched and cp.progress == 1.0)
	check("łup: złom przy ciele (%d → %d)" % [scrap0, _pickups("scrap").size()], _pickups("scrap").size() == scrap0 + 1)
	NoiseMgr.noise_added.disconnect(on_noise)
	check("szelest to cichy hałas (%.2f Uwagi)" % heard[0], heard[0] > 0.3 and heard[0] < 3.0)
	check("po przeszukaniu bez podpowiedzi", not cp.local_in_range)
	cp.set_worker(1, true)
	await _frames(0.4)
	check("przeszukane tylko raz (postęp zostaje 1, bez nowego łupu)", cp.progress == 1.0 and _pickups("scrap").size() == scrap0 + 1)
	cp.set_worker(1, false)
	var rows := _log_rows().filter(func(r: Dictionary) -> bool: return String(r.get("ev", "")) == "corpse_search")
	var row: Dictionary = rows[0] if not rows.is_empty() else {}
	check("dziennik `corpse_search` (mapa, id, łup, ile, kto): %s" % JSON.stringify(row),
		rows.size() == 1 and String(row.get("map", "")) == "z1_m1" and int(row.get("id", -1)) == int(cp.index) and String(row.get("loot", "")) == "scrap"
		and int(row.get("amount", 0)) >= CORPSE.SCRAP.x and String(row.get("who", "")) == "P%d" % int(player.display_id))
	# bateria
	var c2 := _corpse("Corpse1")
	var bat0 := _pickups("battery").size()
	await _search(c2, "battery")
	check("łup: bateria (%d → %d)" % [bat0, _pickups("battery").size()], c2.searched and _pickups("battery").size() == bat0 + 1)
	# naboje (pełne zapasy → złom)
	var c3 := _corpse("Corpse2")
	var ammo0 := _pickups("ammo").size() + _pickups("scrap").size()
	await _search(c3, "ammo")
	check("łup: naboje albo złom przy pełnych zapasach", c3.searched and _pickups("ammo").size() + _pickups("scrap").size() == ammo0 + 1)
	# nic
	var c4 := _corpse("Corpse3")
	var all0 := get_tree().get_nodes_in_group("pickups").duplicate()
	await _search(c4, "none")
	var fresh := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return not all0.has(n))
	check("bez łupu: nic nie wypada (%d nowych)" % fresh.size(), c4.searched and fresh.is_empty())
	check("bez łupu: komunikat „Nothing useful on the body”", Msg.has("corpse.%s" % c4.name))

# ---------------------------------------------------------------- 5. wipe i nowa misja

func _wipe() -> void:
	var searched_before := _corpses().filter(func(c: Node) -> bool: return c.searched).size()
	await main._restart_mission(false)
	await _frames(0.3)
	var after := _corpses().filter(func(c: Node) -> bool: return c.searched).size()
	check("wipe zostawia przeszukane (%d → %d)" % [searched_before, after], searched_before == 4 and after == searched_before)
	await main._restart_mission(true)
	await _frames(0.3)
	var fresh := _corpses().filter(func(c: Node) -> bool: return c.searched or c.progress > 0.0).size()
	check("nowa misja na tej samej mapie: zwłoki nieprzeszukane (%d)" % fresh, fresh == 0 and _corpses().size() == level._corpses.size())

# ---------------------------------------------------------------- 6. losowanie łupu

func _loot_ratio() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var n := 4000
	var cnt := {"none": 0, "scrap": 0, "ammo": 0, "battery": 0}
	for _i in n:
		var k := CORPSE.roll_loot(rng)
		cnt[k] = int(cnt.get(k, 0)) + 1
	var some := float(n - int(cnt["none"])) / float(n)
	var sc := float(cnt["scrap"]) / maxf(1.0, float(n - int(cnt["none"])))
	var am := float(cnt["ammo"]) / maxf(1.0, float(n - int(cnt["none"])))
	var ba := float(cnt["battery"]) / maxf(1.0, float(n - int(cnt["none"])))
	check("losowanie D3: coś w %.0f%% (ok. 60%%), złom %.2f / naboje %.2f / bateria %.2f" % [some * 100.0, sc, am, ba],
		absf(some - CORPSE.LOOT_CHANCE) < 0.04 and absf(sc - 0.45) < 0.05 and absf(am - 0.3) < 0.05 and absf(ba - 0.25) < 0.05)

# ---------------------------------------------------------------- dziennik

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
	SessionLog.reset_for_test()
	SessionLog.enabled = false
	var d := DirAccess.open(LOG_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_DIR))
