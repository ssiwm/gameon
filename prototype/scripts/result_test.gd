extends Node
## Test headless raportu po akcji (RESULTS_PLAN.md, result_screen.gd):
##
##   godot --headless --path . -- --host --mission=z1_m1 --resulttest --autoquit=60
##
## 1. Model (czyste `build_model`): misja 1.1 ze wszystkimi premiami — 4 pieczątki, suma wierszy złomu = zysk, suma XP = zdobyte;
##    utracony cichy cel; warianty 1.2 / 1.3 / B1 / Nocny Dyżur (misja, koniec, porażka); awans o dwa poziomy (dwie pieczątki,
##    odblokowania z obu); drużyna (wyróżnienia przy właściwym graczu, gotowość, solo).
## 2. Na żywo: mission._success() z przebiegiem → result_info od serwera (zysk, premie, znaleziska, taśma), raport otwarty, HUD rozgrywki gaśnie.
## 3. Sekwencja: przy t = 0,5 widać tytuł, nie pieczątki; przy końcu wszystko; skip() → liczniki na wartościach końcowych;
##    „Ogranicz efekty” → stan końcowy od razu.
## 4. Spóźnione XP: etap czeka do DATA_WAIT s i rusza, gdy dane dojdą; bez danych idzie dalej po limicie.
## 5. Rekordy osobiste (Profile.map_best): pierwsze przejście, lepszy czas, gorszy czas, zapis i odczyt.
## 6. Mieszczenie: 1 i 4 graczy, angielski i polski, trzy skale UI — panel na ekranie, żaden napis nie wystaje.
## 7. Wejście: akcja w pierwszych INPUT_LOCK s nic nie robi; pierwsze naciśnięcie pomija, drugie (host) — od razu następna misja.
## Wynik: linie [RESULT-TEST] i kod wyjścia.

const Mission := preload("res://scripts/mission.gd")
const ResultScreen := preload("res://scripts/result_screen.gd")

var main: Node
var total := 0
var failed := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[RESULT-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func _finish() -> void:
	print("[RESULT-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node) -> void:
	main = m
	await get_tree().create_timer(1.0).timeout
	check("mapa 1.1 (nieśmiertelniki)", m.mission.kind == "tags")
	_model_checks()
	_record_checks()
	await _live_checks()
	await _sequence_checks()
	await _late_xp_checks()
	await _fit_checks()
	await _input_checks()
	_finish()

# ---------------------------------------------------------------- 1. model

## Kontekst jak z ResultScreen.collect — tu złożony ręcznie.
func _ctx(over := {}) -> Dictionary:
	var c := {
		"success": true, "kind": "tags", "map_id": "z1_m1", "map_title": "1.1 LOST PATROL", "difficulty": "EASY", "elapsed": 312.0, "downs": 0,
		"attempts": 1, "goal_total": 6, "nests_total": 0, "stash_found": 2, "stash_total": 2, "peak": 41.0, "silent_counts": true,
		"silent_ok": true, "silent_cap": 60, "stealth_cap": 60, "side_done": true,
		"night": {"active": false, "stage": 1, "missions": 5, "cleared": 0, "time": 0.0, "downs": 0, "record": false, "complete": false, "best_c": 0, "best_t": 0.0},
		"scrap_enabled": true, "scrap_info": {"gain": 243, "bonus": [["clear", 30], ["side", 15], ["no_downs", 10], ["silent", 30]],
			"finds": {"parts": ["m83_pbs1"], "samples": 1, "trophy": false}, "timeline": [[12.0, "objective", 1], [95.5, "woke", 0], [300.0, "extract", 0]]},
		"xp": {"ready": true, "mission": 175, "run": 155, "rows": [["Mission cleared", 100], ["Side objective", 50], ["No downs", 25]], "end": 1810},
		"record": {"map": "z1_m1", "time": 312.0, "prev": 340.0, "best": 312.0, "new": true, "first": false},
		"gains": {"mastery": [["m83", 3, 4]], "beasts": ["rzeznik"]},
		"players": [{"id": 1, "call": "macvv", "slot": 0, "kills": 40, "downs": 0, "revives": 0, "me": true, "host": true, "ready": false, "gone": false}],
		"awards": [["ghost", "macvv", 0.0, 1], ["butcher", "macvv", 40.0, 1]], "levels": {}, "timeline": [[12.0, "objective", 1], [95.5, "woke", 0]],
		"companion": false, "server": true, "local_ready": false, "demo_last": false,
	}
	for k in over:
		c[k] = over[k]
	return c

func _sum(rows: Array) -> int:
	var n := 0
	for r in rows:
		n += int(r[1])
	return n

func _model_checks() -> void:
	var md: Dictionary = ResultScreen.build_model(_ctx())
	var tiles: Array = md["tiles"]
	check("1.1 z premiami: 4 pieczątki zaliczone (%d)" % tiles.size(), tiles.size() == 4 and tiles.all(func(t: Dictionary) -> bool: return bool(t["ok"])))
	check("suma wierszy złomu = zysk (%d = 243)" % _sum(md["scrap"]["rows"]), _sum(md["scrap"]["rows"]) == 243 and int(md["scrap"]["total"]) == 243)
	check("suma wierszy XP = zdobyte (%d = 330)" % _sum(md["xp"]["rows"]), _sum(md["xp"]["rows"]) == 330 and int(md["xp"]["earned"]) == 330)
	check("awans 5 → 6 przy 1480 → 1810 XP (%s)" % str((md["xp"]["levels"] as Array).map(func(l: Dictionary) -> int: return int(l["lv"]))),
		(md["xp"]["levels"] as Array).size() == Profile.level_of(1810) - Profile.level_of(1480))
	var times: Array = tiles.map(func(t: Dictionary) -> float: return float(t["t"]))
	check("pieczątki po kolei co TILE_GAP", is_equal_approx(float(times[1]) - float(times[0]), ResultScreen.TILE_GAP))
	check("znaleziska: rekord, część, próbka, wprawa, kodeks (%d)" % (md["finds"] as Array).size(), (md["finds"] as Array).size() == 5)
	check("taśma przebiegu z dwoma znakami", bool(md["timeline"]["show"]) and (md["timeline"]["marks"] as Array).size() == 2)
	check("koniec sekwencji ≥ T_DONE i po ostatniej pieczątce", float(md["end_t"]) >= ResultScreen.T_DONE)
	check("host: kryjówka i od razu następna misja", (md["prompts"] as Array).size() == 2 and String(md["prompts"][1]["kind"]) == "next")
	check("solo: status SOLO, dwa wyróżnienia na karcie", String(md["squad"][0]["status"]) == tr("SOLO") and (md["squad"][0]["awards"] as Array).size() == 2)
	# utracony cichy cel
	var lost := _ctx({"silent_ok": false, "peak": 78.0})
	lost["scrap_info"] = {"gain": 213, "bonus": [["clear", 30], ["side", 15], ["no_downs", 10]], "finds": {}, "timeline": []}
	var ml: Dictionary = ResultScreen.build_model(lost)
	var sil: Dictionary = (ml["tiles"] as Array).filter(func(t: Dictionary) -> bool: return String(t["id"]) == "silent")[0]
	check("cichy cel stracony: pieczątka ✕ ze szczytem 78, bez +30 w złomie", not bool(sil["ok"]) and String(sil["value"]) == "78"
		and _sum(ml["scrap"]["rows"]) == 213 and String(sil["reward"]) == tr("missed: %s") % (tr("+%d scrap") % 30))
	# warianty
	var gen: Dictionary = ResultScreen.build_model(_ctx({"kind": "generators", "silent_counts": false, "side_done": false, "peak": 77.0}))
	check("1.2: pieczątka UKRYCIE stracona (szczyt 77)", (gen["tiles"] as Array).size() == 3 and String(gen["tiles"][1]["id"]) == "side" and not bool(gen["tiles"][1]["ok"]))
	var nests: Dictionary = ResultScreen.build_model(_ctx({"kind": "nests", "nests_total": 4, "silent_counts": false}))
	check("1.3: gniazda, Żyła, bez upadków", (nests["tiles"] as Array).map(func(t: Dictionary) -> String: return String(t["id"])) == ["main", "vein", "no_downs"])
	var boss: Dictionary = ResultScreen.build_model(_ctx({"kind": "boss", "silent_counts": false}))
	check("B1: tytuł o Pijawce, dwie pieczątki", String(boss["title"]) == tr("THE LEECH IS DEAD") and (boss["tiles"] as Array).size() == 2
		and int(boss["tiles"][0]["xp"]) == Profile.XP_MISSION + Profile.XP_BOSS)
	var night := _ctx({"scrap_enabled": false})
	night["night"] = {"active": true, "stage": 3, "missions": 5, "cleared": 3, "time": 900.0, "downs": 2, "record": false, "complete": false, "best_c": 4, "best_t": 0.0}
	var mn: Dictionary = ResultScreen.build_model(night)
	check("Nocny Dyżur: drabinka 5 misji, 3 zaliczone, bez złomu", bool(mn["ladder"]) and (mn["tiles"] as Array).size() == 5
		and (mn["tiles"] as Array).filter(func(t: Dictionary) -> bool: return bool(t["ok"])).size() == 3 and not bool(mn["scrap"]["show"]))
	night["success"] = false
	night["night"]["cleared"] = 2
	var mf: Dictionary = ResultScreen.build_model(night)
	check("Nocny Dyżur, porażka: SERIA PRZERWANA na czerwono, bez XP", String(mf["title"]) == tr("SERIES BROKEN") and Color(mf["color"]) == ResultScreen.UiTheme.DANGER
		and not bool(mf["xp"]["show"]) and String(mf["prompts"][0]["kind"]) == "continue")
	night["success"] = true
	night["night"]["complete"] = true
	night["night"]["cleared"] = 5
	night["night"]["record"] = true
	var mc: Dictionary = ResultScreen.build_model(night)
	check("Nocny Dyżur, cała seria: DYŻUR ZAKOŃCZONY i NOWY REKORD", String(mc["title"]) == tr("SHIFT COMPLETE") and (mc["finds"] as Array).size() == 1)
	# awans o dwa poziomy: L1 → L3 (0 → 450 XP)
	var two := _ctx({"xp": {"ready": true, "mission": 300, "run": 150, "rows": [["Mission cleared", 100], ["Boss", 200]], "end": 450}})
	var m2: Dictionary = ResultScreen.build_model(two)
	var lvs: Array = m2["xp"]["levels"]
	check("awans 1 → 3: dwie pieczątki, czasy rosną (%s)" % str(lvs.map(func(l: Dictionary) -> int: return int(l["lv"]))),
		lvs.size() == 2 and float(lvs[1]["t"]) > float(lvs[0]["t"]) and float(lvs[1]["t"]) <= ResultScreen.T_XP + ResultScreen.XP_DUR + 0.01)
	check("poziom 2 odblokowuje slot perka", (lvs[0]["unlocks"] as Array).any(func(u: String) -> bool: return u.contains("1")) and not (lvs[0]["unlocks"] as Array).is_empty())
	# drużyna
	var team := _ctx()
	team["players"] = [
		{"id": 1, "call": "macvv", "slot": 0, "kills": 40, "downs": 0, "revives": 0, "me": true, "host": true, "ready": false, "gone": false},
		{"id": 7, "call": "Wilk", "slot": 1, "kills": 22, "downs": 1, "revives": 0, "me": false, "host": false, "ready": true, "gone": false},
		{"id": 9, "call": "Kos", "slot": 2, "kills": 9, "downs": 1, "revives": 0, "me": false, "host": false, "ready": false, "gone": false},
		{"id": 12, "call": "Sowa", "slot": 3, "kills": 14, "downs": 0, "revives": 2, "me": false, "host": false, "ready": false, "gone": true}]
	team["awards"] = [["medic", "Sowa", 2.0, 12], ["butcher", "macvv", 40.0, 1]]
	team["levels"] = {7: [4, 5]}
	var mt: Dictionary = ResultScreen.build_model(team)
	var sq: Array = mt["squad"]
	check("drużyna: SANITARIUSZ u Sowy, RZEŹNIK u hosta", (sq[3]["awards"] as Array).size() == 1 and (sq[0]["awards"] as Array).size() == 1
		and String(sq[3]["awards"][0]["title"]) == tr("MEDIC"))
	check("awans kolegi na jego karcie (Wilk 4 → 5)", (sq[1]["awards"] as Array).any(func(a: Dictionary) -> bool: return String(a["kind"]) == "level"))
	check("gotowość: Wilk GOTOWY, Kos czyta, Sowa rozłączony; host widzi 1 / 2", String(sq[1]["status"]) == tr("READY")
		and String(sq[2]["status"]) == tr("reading…") and String(sq[3]["status"]) == tr("disconnected") and String(mt["ready_note"]) == tr("%d / %d ready") % [1, 2])
	var client := _ctx({"server": false})
	check("klient: jedna akcja — Gotowy", (ResultScreen.build_model(client)["prompts"] as Array).size() == 1)
	client["local_ready"] = true
	var mcl: Dictionary = ResultScreen.build_model(client)
	check("klient po zgłoszeniu: czeka na hosta, bez akcji", (mcl["prompts"] as Array).is_empty() and String(mcl["ready_note"]) == tr("Waiting for the host to continue…"))

# ---------------------------------------------------------------- 5. rekordy

func _record_checks() -> void:
	var keep_best: Dictionary = Profile.map_best.duplicate(true)
	var keep_done: Dictionary = Profile.completed.duplicate()
	var keep_xp: int = Profile.xp
	Profile.map_best.erase("z1_test")
	Profile.completed.erase("z1_test")
	Profile.apply_mission_result("z1_test", false, false, false, false, 340.0)
	var r1: Dictionary = Profile.last_record.duplicate()
	Profile.apply_mission_result("z1_test", false, false, false, false, 312.0)
	var r2: Dictionary = Profile.last_record.duplicate()
	Profile.apply_mission_result("z1_test", false, false, false, false, 400.0)
	var r3: Dictionary = Profile.last_record.duplicate()
	check("pierwsze przejście: rekord i FIRST", bool(r1["first"]) and bool(r1["new"]))
	check("lepszy czas: NOWY REKORD (było 340)", bool(r2["new"]) and not bool(r2["first"]) and is_equal_approx(float(r2["prev"]), 340.0))
	check("gorszy czas: bez rekordu, najlepszy 312", not bool(r3["new"]) and is_equal_approx(float(r3["best"]), 312.0)
		and is_equal_approx(float(Profile.map_best["z1_test"]["time"]), 312.0))
	Profile.apply_mission_result("z1_test", false, false, false, true, 100.0)
	check("Nocny Dyżur nie bije rekordu kampanii", is_equal_approx(float(Profile.map_best["z1_test"]["time"]), 312.0))
	var path := "user://result_test_profile.cfg"
	Profile.save_to(path)
	Profile.map_best = {}
	Profile.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check("rekord przetrwał zapis i odczyt profilu", Profile.map_best.has("z1_test") and is_equal_approx(float(Profile.map_best["z1_test"]["time"]), 312.0))
	Profile.map_best = keep_best
	Profile.completed = keep_done
	Profile.xp = keep_xp

# ---------------------------------------------------------------- 2. na żywo

func _report() -> Node:
	return get_tree().root.find_child("ResultScreen", true, false)

func _live_checks() -> void:
	var mission: Node = main.mission
	mission.mark("objective", main.get_node("Players").get_node_or_null("1"))
	mission.mark("woke")
	mission.elapsed = 214.0
	mission.peak_noise = 30.0
	mission.player_stats = {NoiseMgr.local_id(): {"name": "P1", "call": "Tester", "kills": 14, "downs": 0, "revived": 0, "revives": 1, "escapes": 2, "lures": 1, "noise": 64.0},
		2: {"name": "P2", "call": "Kos", "kills": 9, "downs": 0, "revived": 1, "revives": 0, "escapes": 0, "lures": 0, "noise": 31.0}}
	mission.downs = 0
	Scrap.loot = 120
	mission._success()
	await get_tree().process_frame
	await get_tree().process_frame
	var info: Dictionary = mission.result_info
	var bsum := 0
	for b in Array(info.get("bonus", [])):
		bsum += int(b[1])
	check("result_info: zysk = łup + premie (%d = 120 + %d)" % [int(info.get("gain", -1)), bsum], int(info.get("gain", -1)) == 120 + bsum and bsum == mission.scrap_bonus())
	check("result_info: taśma z celem i przebudzeniem", (info.get("timeline", []) as Array).size() == 2)
	var rs := _report()
	check("raport otwarty po sukcesie", rs != null and rs.visible)
	if rs == null:
		return
	await get_tree().create_timer(0.5).timeout
	var hud: Node = rs.get_parent()
	check("HUD rozgrywki gaśnie pod raportem (karta drużyny alfa %.2f)" % float(hud._squad_card.modulate.a), float(hud._squad_card.modulate.a) < 0.05)
	check("wyróżnienia mają peer id", (Mission.awards(mission.player_stats, true)[0] as Array).size() == 4)
	check("XP od serwera doszło (rows=%d)" % (rs.model["xp"]["rows"] as Array).size(), bool(rs.model["xp"]["ready"]))

# ---------------------------------------------------------------- 3. sekwencja

func _sequence_checks() -> void:
	var rs := _report()
	if rs == null:
		return
	var m: Node = main.mission
	rs.open(m)
	rs.t = 0.5
	rs._animate()
	var title: Control = rs._anims.filter(func(a: Dictionary) -> bool: return String(a["kind"]) == "title")[0]["node"]
	var stamps: Array = rs._anims.filter(func(a: Dictionary) -> bool: return String(a["kind"]) == "stamp")
	check("t = 0,5: tytuł widać, pieczątek nie", title.modulate.a > 0.95 and stamps.all(func(a: Dictionary) -> bool: return (a["node"] as Control).modulate.a < 0.01))
	check("t = 0,5: przycisk akcji przygaszony, podpowiedź pominięcia", rs._prompt_box.modulate.a < 0.5 and rs._skip_hint.visible)
	rs.skip()
	check("skip(): koniec sekwencji, licznik złomu na wartości końcowej (%s)" % rs._scrap_val.text,
		rs.is_done() and rs._scrap_val.text == "+%d" % int(rs.model["scrap"]["total"]) and stamps.all(func(a: Dictionary) -> bool: return (a["node"] as Control).modulate.a > 0.99))
	check("skip(): XP na wartości końcowej (%s)" % rs._xp_val.text, rs._xp_val.text == "+%d" % int(rs.model["xp"]["earned"]))
	Settings.reduce_fx = true
	rs.open(m)
	check("„Ogranicz efekty”: stan końcowy od razu", rs.is_done() and rs.hud_fade() == 0.0)
	Settings.reduce_fx = false
	rs.open(m)
	for i in 70:
		rs.advance(0.1)
	check("po 7 s sekwencja skończona", rs.is_done())

# ---------------------------------------------------------------- 4. spóźnione XP

func _late_xp_checks() -> void:
	var rs := _report()
	if rs == null:
		return
	var keep: int = Profile.result_ms
	Profile.result_ms = 0
	rs.open(main.mission)
	check("bez XP od serwera: etap XP niegotowy", not bool(rs.model["xp"]["ready"]))
	while rs.t < ResultScreen.T_XP:
		rs.advance(0.05)
	rs.advance(1.0)
	check("etap XP czeka (t = %.2f)" % rs.t, rs.t < ResultScreen.T_XP + 0.06)
	Profile.result_ms = Time.get_ticks_msec()
	rs._ctx_t = 0.0
	rs.refresh(0.05)
	rs.advance(0.3)
	check("XP doszło: etap rusza (t = %.2f), licznik liczy" % rs.t, bool(rs.model["xp"]["ready"]) and rs.t > ResultScreen.T_XP + 0.2)
	Profile.result_ms = 0
	rs.open(main.mission)
	while rs.t < ResultScreen.T_XP:
		rs.advance(0.05)
	for i in 25:
		rs.advance(0.1)
	check("XP nie doszło: po DATA_WAIT sekwencja idzie dalej (t = %.2f), licznik „…”" % rs.t, rs.t > ResultScreen.T_XP + 0.5 and rs._xp_val.text == "…")
	Profile.result_ms = keep

# ---------------------------------------------------------------- 6. mieszczenie

func _fit_checks() -> void:
	var rs := _report()
	if rs == null:
		return
	var m: Node = main.mission
	var keep_stats: Dictionary = m.player_stats.duplicate(true)
	var four := {}
	for i in 4:
		four[i + 1 if i == 0 else 100 + i] = {"name": "P%d" % (i + 1), "call": ["Hieronim", "Wilk-Kowalczyk", "Kos", "Sowa"][i], "kills": 40 - i,
			"downs": i, "revived": 0, "revives": i, "escapes": i, "lures": 1, "noise": 10.0 * i}
	var keep_loc := TranslationServer.get_locale()
	var keep_ui: int = Settings.ui_idx
	var hud: Node = rs.get_parent()
	for ui in Settings.UI_MULT.size():
		Settings.ui_idx = ui                       # skala UI: SMALL / NORMAL / LARGE (logiczny ekran ma zawsze 640×360)
		hud._apply_scale()
		for loc in ["en", "pl"]:
			TranslationServer.set_locale(loc)
			for squad in [keep_stats, four]:
				m.player_stats = squad
				rs.open(m)
				rs.skip()
				await get_tree().process_frame
				rs._animate()
				_fit_one(rs, "%s skala UI %d, %d graczy" % [loc, ui, (squad as Dictionary).size()])
	TranslationServer.set_locale(keep_loc)
	Settings.ui_idx = keep_ui
	hud._apply_scale()
	m.player_stats = keep_stats
	rs.open(m)

func _fit_one(rs: Node, what: String) -> void:
	var panel: Control = rs._panel
	var vp := Rect2(Vector2.ZERO, rs.get_viewport_rect().size)
	var pr := panel.get_global_rect()
	var on_screen := vp.grow(1.0).encloses(pr)
	var bad: Array = []
	for n in panel.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text == "" or l.clip_text or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			continue
		var need := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		if need > l.size.x + 1.5:
			bad.append("„%s” %.0f > %.0f" % [l.text.left(30), need, l.size.x])
	for n in panel.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.get_global_rect().end.x > pr.end.x + 1.5:
			bad.append("%s poza panelem" % c.get_class())
			break
	check("mieszczenie %s: panel na ekranie (%s w %s), %d wystających" % [what, pr, vp.size, bad.size()] + ("" if bad.is_empty() else " — " + ", ".join(bad.slice(0, 3))),
		on_screen and bad.is_empty())

# ---------------------------------------------------------------- 7. wejście

func _input_checks() -> void:
	var rs := _report()
	if rs == null:
		return
	var level: Node = main.level
	var nxt: String = main._next_campaign_map()
	rs.open(main.mission)
	check("w pierwszych 0,6 s akcja zablokowana", rs.press("next") == "locked" and level.map_id == "z1_m1")
	rs._age = 1.0
	check("pierwsze naciśnięcie pomija sekwencję", rs.press("next") == "skipped" and rs.is_done())
	check("drugie (host): od razu następna misja", rs.press("next") == "act")
	await get_tree().create_timer(0.6).timeout
	check("następna misja %s załadowana, raport zamknięty" % nxt, level.map_id == nxt and main.mission.phase == Mission.Phase.OBJECTIVE and not rs.visible)
