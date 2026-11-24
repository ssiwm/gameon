extends "res://scripts/corpse_test.gd"
## Test headless Mimika udającego zwłoki (MIMIC_PLAN.md M5, corpse.gd `mimic`, enemy_mimic.gd `become_corpse`):
##
##   godot --headless --path . -- --host --mission=z1_m2 --mimicseed=5 --mimiccorpsetest --autoquit=60
##
## 1. Gniazda i ziarno: gniazda `mimic` z CORPSES (1.2 i 1.3 po 3, 1.1 bez), `pick_mimic` — to samo ziarno to samo gniazdo, różne ziarna
##    trafiają we wszystkie gniazda; na mapie tylu Mimików-zwłok, ile MIMIC_CORPSES, w miejscu wybranego ciała, ≥ 4 prawdziwe na jednego (D2).
## 2. Przebranie: niskie ciało i strefa trafień, widok rysuje go jako zwłoki (`as_corpse`), bez etykiety, nie woła, podpowiedź [E] jak przy ciele.
## 3. Demaskacja: snop dopiero po ~2,5 s, przejście tuż nad nim (bot) tak, stanie obok nie; przeszukiwanie — chwyt po 0,3 s zamiast łupu;
##    trafienie; po demaskacji wymiary stojącego, zwłok już nie ma (`present`). Dziennik `mimic_reveal` z `disguise` = corpse.
## 4. Zabity zostawia łup ciała; wipe kładzie go z powrotem; prawdziwe zwłoki przeszukane do końca nie budzą nikogo.
## Wynik: linie [MIMIC-CORPSE] i kod wyjścia.

const MIMIC := preload("res://scripts/enemy_mimic.gd")
const Weapons := preload("res://scripts/weapons.gd")

var mim: CharacterBody2D
var cp_fake: Node2D

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[MIMIC-CORPSE] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[MIMIC-CORPSE] INFO  %s" % label)

func _finish() -> void:
	print("[MIMIC-CORPSE] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(0.5).timeout
	if not m.companion_on:
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
	check("mapa 1.2 z graczem i botem", player != null and bot != null and level.map_id == "z1_m2")
	if player == null or bot == null:
		_finish()
		return
	# świat wyciszony jak w stalker_test.gd, ale Mimik-zwłoki zostaje
	for e in get_tree().get_nodes_in_group("enemies"):
		if not String(e.name).begins_with("MimikCorpse"):
			e.queue_free()
	var st := level.get_node_or_null("Stalker")
	if st != null:
		st.queue_free()
	_park_bot()
	Director.set_process(false)
	SessionLog.enabled = true
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "mimic_corpse"})
	_nests()
	if mim == null or cp_fake == null:
		_finish()
		return
	await _disguise()
	await _light()
	await _over()
	await _search_fake()
	await _hit()
	await _kill_and_wipe()
	await _real_search()
	_check_reveal_log()
	_cleanup_log()
	_finish()

func _park_bot() -> void:
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = Vector2(-4000, -4000)

## Demaskacja w teście: przywróć przebranie (jak wipe dla jednego wroga), gracz i bot z dala.
func _rewind() -> void:
	mim.reset_enemy()
	_park_bot()
	_place_player(cp_fake.global_position + Vector2(-200.0, 0.0))

# ---------------------------------------------------------------- 1. gniazda i ziarno

func _nests() -> void:
	var defs: Array = level._corpses
	var nests: Array = []
	for i in defs.size():
		if bool((defs[i][4] as Dictionary).get("mimic", false)):
			nests.append(i)
	var m1: Array = ((load("res://scripts/maps/z1_m1.gd") as GDScript).get_script_constant_map()["CORPSES"] as Array)
	var m3: Array = ((load("res://scripts/maps/z1_m3.gd") as GDScript).get_script_constant_map()["CORPSES"] as Array)
	var n3 := m3.filter(func(cd: Array) -> bool: return bool((cd[4] as Dictionary).get("mimic", false))).size()
	var n1 := m1.filter(func(cd: Array) -> bool: return bool((cd[4] as Dictionary).get("mimic", false))).size()
	check("gniazda `mimic`: 1.2 — %d, 1.3 — %d, 1.1 — %d (po 3, na 1.1 bez)" % [nests.size(), n3, n1], nests.size() == 3 and n3 == 3 and n1 == 0)
	var same: bool = CORPSE.pick_mimic(defs, 1, 1234) == CORPSE.pick_mimic(defs, 1, 1234)
	var hit := {}
	for s in 40:
		var p: Array = CORPSE.pick_mimic(defs, 1, s * 7919 + 3)
		if p.size() == 1:
			hit[p[0]] = true
	var two: Array = CORPSE.pick_mimic(defs, 2, 99)
	check("ziarno: to samo — to samo gniazdo, 40 ziaren trafia we wszystkie %d gniazda (%d), dwa wybrane różne" % [nests.size(), hit.size()],
		same and hit.size() == nests.size() and hit.keys().all(func(k: int) -> bool: return k in nests) and two.size() == 2 and two[0] != two[1])
	var want: Array = CORPSE.pick_mimic(defs, int(level._mimic_corpses), int(level.mimic_seed))
	var mims := get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return String(e.name).begins_with("MimikCorpse") and not e.is_queued_for_deletion())
	mim = mims[0] if mims.size() == 1 else null
	cp_fake = level.get_node_or_null("Corpse%d" % (int(want[0]) + 1)) if want.size() == 1 else null
	var fakes := _corpses().filter(func(c: Node) -> bool: return c.mimic != null)
	check("ziarno mapy %d (--mimicseed): jeden Mimik-zwłoki w wybranym gnieździe %s, tylko to ciało ma `mimic`" % [level.mimic_seed, str(cp_fake.name) if cp_fake != null else "?"],
		int(level.mimic_seed) == 5 and mim != null and cp_fake != null and cp_fake.mimic == mim and fakes.size() == 1
		and mim.global_position.distance_to(cp_fake.global_position) < 1.0 and mim._beh.corpse == cp_fake)
	check("D2: prawdziwych zwłok %d na jednego Mimika-zwłoki (≥ 4)" % (defs.size() - 1), defs.size() - 1 >= 4)

# ---------------------------------------------------------------- 2. przebranie

func _disguise() -> void:
	var b = mim._beh
	var hurt: RectangleShape2D = mim._hit_shape
	var body := (mim.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	check("leży: ciało ruchu i strefa trafień %s / %s (niskie jak zwłoki)" % [body.size, hurt.size],
		is_equal_approx(hurt.size.y, MIMIC.LYING.y) and is_equal_approx(body.size.y, MIMIC.LYING.y) and not mim.active)
	var vi: Dictionary = mim.view_info()
	check("widok: rysowany jako zwłoki (`as_corpse`), bez etykiety, zwłoki są (`present`)",
		vi.get("as_corpse") == true and mim.bar_state().get("label") == "" and cp_fake.present())
	_place_player(cp_fake.global_position + Vector2(-160.0, 0.0))
	b.lure_t = 0.0
	var c0: int = b.calls
	b.tick_asleep(0.1)
	check("nie woła (zwłoki milczą)", b.calls == c0)
	_place_player(cp_fake.global_position + Vector2(-16.0, -1.0))
	await _frames(0.3)
	check("stanie obok (16 px) nie budzi, podpowiedź [E] jak przy ciele", not mim.active and cp_fake.local_in_range
		and _prompt_has(Actions.fmt(tr("Hold [{interact}]  Search the body"))))
	_place_player(cp_fake.global_position + Vector2(-200.0, 0.0))
	await _frames(0.1)

# ---------------------------------------------------------------- 3. demaskacja

func _light() -> void:
	var b = mim._beh
	mim.set_physics_process(false)
	b.reset()
	var woke_at := -1
	for i in 16:
		b._lit_ms = Time.get_ticks_msec() - 200
		if b.light_wakes(true):
			woke_at = i + 1
			break
	check("snop latarki demaskuje dopiero po ~2,5 s (13. sprawdzenie co 0,2 s, stojący po 8.)", woke_at == 13)
	b.reset()
	mim.set_physics_process(true)
	mim.wake("light")
	check("demaskacja: wymiary stojącego, zwłok już nie ma", is_equal_approx((mim._hit_shape as RectangleShape2D).size.y, 22.0)
		and not cp_fake.present() and mim.view_info().get("as_corpse") == false)
	_rewind()
	await _frames(0.1)
	check("reset: znów leży i udaje zwłoki", not mim.active and cp_fake.present() and is_equal_approx((mim._hit_shape as RectangleShape2D).size.y, MIMIC.LYING.y))

func _over() -> void:
	bot.set_physics_process(true)
	bot.global_position = cp_fake.global_position + Vector2(3.0, -1.0)
	bot.set_physics_process(false)
	await _frames(0.2)
	check("bot przechodzi tuż nad nim: demaskacja (%s)" % mim.wake_cause, mim.active and mim.wake_cause == "near")
	_rewind()
	await _frames(0.1)

func _search_fake() -> void:
	_place_player(cp_fake.global_position + Vector2(-16.0, -1.0))
	await _frames(0.1)
	cp_fake.set_worker(1, true)
	await _frames(0.15)
	var early: bool = not mim.active and cp_fake.progress > 0.0
	await _frames(0.35)
	check("przeszukiwanie: po 0,15 s jeszcze leży, po 0,3 s chwyta (%s), bez łupu i postępu" % mim.wake_cause,
		early and mim.active and mim.wake_cause == "search" and cp_fake.progress == 0.0 and cp_fake._workers.is_empty() and not cp_fake.searched)
	await _frames(0.1)
	check("po demaskacji bez podpowiedzi [E] (zwłok nie ma)", not cp_fake.local_in_range and not cp_fake.present())
	_rewind()
	await _frames(0.1)

func _hit() -> void:
	mim.take_hit({"amount": 5.0, "dir": Vector2.RIGHT, "shooter": 1, "w": Weapons.M83, "type": "bullet", "pos": mim.global_position})
	await _frames(0.05)
	check("trafienie demaskuje (%s)" % mim.wake_cause, mim.active and mim.wake_cause == "hit")
	_rewind()
	await _frames(0.1)

# ---------------------------------------------------------------- 4. śmierć, wipe, prawdziwe zwłoki

func _kill_and_wipe() -> void:
	cp_fake.force_loot = "battery"
	var before := _pickups("battery").map(func(n: Node) -> int: return n.get_instance_id())
	mim.take_hit({"amount": 9999.0, "dir": Vector2.RIGHT, "shooter": 1, "w": Weapons.M83, "type": "bullet", "pos": mim.global_position})
	await _frames(0.3)
	var at: Vector2 = cp_fake.global_position
	var fresh := _pickups("battery").filter(func(n: Node2D) -> bool: return not before.has(n.get_instance_id()) and n.global_position.distance_to(at) < 40.0)
	check("zabity zostawia łup ciała (bateria przy nim, %d), zwłok już nie ma" % fresh.size(), not mim.alive and fresh.size() >= 1 and not cp_fake.present())
	cp_fake.force_loot = ""
	await main._restart_mission(false)
	await _frames(0.3)
	_park_bot()
	check("wipe: Mimik-zwłoki znów leży w gnieździe", mim.alive and not mim.active and cp_fake.present()
		and mim.global_position.distance_to(cp_fake.global_position) < 1.0 and is_equal_approx((mim._hit_shape as RectangleShape2D).size.y, MIMIC.LYING.y))

func _real_search() -> void:
	var real: Node2D = null
	for c in _corpses():
		if c.mimic == null and not c.searched and c.global_position.distance_to(cp_fake.global_position) > 200.0:
			real = c
			break
	if real == null:
		check("jest prawdziwe ciało do przeszukania", false)
		return
	_place_player(real.global_position + Vector2(-8.0, -1.0))
	await _frames(0.1)
	real.force_loot = "none"
	real.set_worker(1, true)
	await _frames(1.6)
	real.set_worker(1, false)
	check("prawdziwe zwłoki (%s): przeszukane do końca, Mimik dalej leży" % real.name, real.searched and not mim.active and cp_fake.present())

func _check_reveal_log() -> void:
	var rows: Array = []
	for line in FileAccess.get_file_as_string(SessionLog.path).split("\n"):
		if line != "":
			rows.append(JSON.parse_string(line))
	var rev: Array = rows.filter(func(r: Dictionary) -> bool: return r["ev"] == "mimic_reveal")
	var causes := {}
	for r in rev:
		if r.get("disguise") == "corpse":
			causes[String(r["cause"])] = true
	check("dziennik: `mimic_reveal` z `disguise` = corpse dla light, near, search, hit %s" % str(causes.keys()),
		causes.has("light") and causes.has("near") and causes.has("search") and causes.has("hit"))
