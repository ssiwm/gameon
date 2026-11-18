extends Node
## Test geod (DIG_LOOT_PLAN.md K4, Scrap.geodes) w kryjówce:
##   godot --headless --path prototype -- --host --nobot --mission=z1_hub --geodetest --autoquit=40
## Geoda z żyły idzie do łupu misji (dig_zone.gd FIND_GEODE → Scrap.add_geodes), po udanej misji do banku, wipe i punkt kontrolny bossa
## ją zabierają albo oddają; w pracowni [V] / przycisk rozbija jedną (serwer losuje: próbka, dwie próbki, złom, część; bez brakujących
## części — próbki), odmowy (poza pracownią, brak geod), napis i sygnał u każdego peera, tablica PROJEKTY z wierszem GEODY, podpowiedź
## przy pracowni, wiersz raportu po akcji, dziennik `hub_buy`, zapis i odczyt banku. W oknie z `--geodeshots=KATALOG`: zrzut `k4_geode_lab`.

const Parts := preload("res://scripts/parts.gd")
const DigZone := preload("res://scripts/dig_zone.gd")
const Actions := preload("res://scripts/actions.gd")
const ResultScreen := preload("res://scripts/result_screen.gd")

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var failed := 0
var total := 0
var _saved := {}

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[GEODE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[GEODE-TEST] INFO  %s" % label)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	check("kryjówka z graczem (%s)" % level.map_id, player != null and level.map_id == "z1_hub" and Scrap.enabled())
	if player == null or level.map_id != "z1_hub":
		_finish()
		return
	_saved = {"bank": Scrap.bank, "samples": Scrap.samples, "geodes": Scrap.geodes, "parts": Scrap.parts.duplicate(),
		"schematics": Scrap.schematics.duplicate(), "unlocked": Scrap.unlocked.duplicate()}
	_loot()
	await _open()
	await _card()
	_report()
	_save_load()
	await _shots()
	_finish()

func _finish() -> void:
	if not _saved.is_empty():
		Scrap.bank = int(_saved["bank"])
		Scrap.samples = int(_saved["samples"])
		Scrap.geodes = int(_saved["geodes"])
		Scrap.parts = _saved["parts"]
		Scrap.schematics = _saved["schematics"]
		Scrap.unlocked = _saved["unlocked"]
	Scrap.geode_roll = -1.0
	print("[GEODE-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func _frames(seconds: float) -> void:
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < seconds and is_inside_tree():
		await get_tree().physics_frame
		t += dt

func _to_lab() -> void:
	var lab := get_tree().get_first_node_in_group("lab_bench")
	player.global_position = lab.global_position + Vector2(0, -2)
	player.velocity = Vector2.ZERO

func _away() -> void:
	var lab := get_tree().get_first_node_in_group("lab_bench")
	player.global_position = lab.global_position + Vector2(200, -2)
	player.velocity = Vector2.ZERO

# ---------------------------------------------------------------- 1. łup misji, bank, wipe, punkt kontrolny

func _loot() -> void:
	var dz := DigZone.new()                                     # bez sceny: tylko rozstrzygnięcie znajdźki
	var rg: Array = dz._resolve_find(DigZone.FIND_GEODE)
	dz.free()
	check("geoda z żyły to geoda do łupu (%s), nie próbka" % str(rg), rg == ["geode", 0, 1])
	Scrap.geodes = 0
	Scrap.geodes_loot = 0
	Scrap.add_geodes(1)
	check("geoda w łupie misji (%d), bank bez zmian (%d)" % [Scrap.geodes_loot, Scrap.geodes], Scrap.geodes_loot == 1 and Scrap.geodes == 0)
	Scrap.save_checkpoint_loot()
	Scrap.add_geodes(1)
	Scrap.restore_checkpoint_loot()
	check("wipe w walce z bossem wraca do łupu z przebudzenia (%d)" % Scrap.geodes_loot, Scrap.geodes_loot == 1)
	Scrap.reset_loot()
	check("wipe zabiera geodę z łupu (%d)" % Scrap.geodes_loot, Scrap.geodes_loot == 0 and Scrap.geodes == 0)
	Scrap.add_geodes(2)
	var bank0 := Scrap.bank
	Scrap.bank_loot(0)
	Scrap.bank = bank0
	check("udana misja: geody z łupu do banku (%d, łup %d)" % [Scrap.geodes, Scrap.geodes_loot], Scrap.geodes == 2 and Scrap.geodes_loot == 0)

# ---------------------------------------------------------------- 2. rozbijanie w pracowni

func _crack(roll: float) -> Dictionary:
	var got := {}
	var cb := func(res: Dictionary) -> void: got.merge(res, true)
	Scrap.geode_opened.connect(cb)
	Scrap.geode_roll = roll
	Scrap._action_at.clear()                                    # odstęp między akcjami (_permit_action) — testy klikają szybciej niż gracz
	Scrap.request_open_geode()
	await _frames(0.05)
	Scrap.geode_opened.disconnect(cb)
	return got

func _open() -> void:
	Scrap.geodes = 1
	_away()
	await _frames(0.1)
	var r := await _crack(0.1)
	check("poza pracownią: odmowa „station” (%s), geoda zostaje" % String(r.get("reason", "")), String(r.get("reason", "")) == "station" and Scrap.geodes == 1)
	_to_lab()
	await _frames(0.1)
	var smp0 := Scrap.samples
	r = await _crack(0.1)
	check("przy pracowni: rozbita — 1 próbka do banku (%s, próbki %d → %d, geody %d)" % [str(r.get("kind", "")), smp0, Scrap.samples, Scrap.geodes],
		String(r.get("reason", "")) == "ok" and String(r["kind"]) == "sample" and int(r["n"]) == 1 and Scrap.samples == smp0 + 1 and Scrap.geodes == 0)
	r = await _crack(0.1)
	check("bez geod: odmowa „none” (%s)" % String(r.get("reason", "")), String(r.get("reason", "")) == "none" and Scrap.samples == smp0 + 1)
	Scrap.geodes = 3
	smp0 = Scrap.samples
	r = await _crack(0.6)
	check("losowanie 0,6: dwie próbki (%s ×%d)" % [str(r.get("kind", "")), int(r.get("n", 0))], String(r.get("kind", "")) == "sample" and int(r["n"]) == 2
		and Scrap.samples == smp0 + 2)
	var bank0 := Scrap.bank
	r = await _crack(0.8)
	check("losowanie 0,8: kryształy rudy — złom do banku (%d → %d)" % [bank0, Scrap.bank], String(r.get("kind", "")) == "scrap"
		and Scrap.bank == bank0 + int(r["n"]) and int(r["n"]) > 0)
	var cands: Array = Scrap.find_candidates()
	r = await _crack(0.95)
	var pid := String(r.get("id", ""))
	if cands.is_empty():
		check("losowanie 0,95 bez brakujących części: próbki (%s ×%d)" % [str(r.get("kind", "")), int(r.get("n", 0))],
			String(r.get("kind", "")) == "sample" and int(r["n"]) == Scrap.GEODE_FALLBACK)
	else:
		check("losowanie 0,95: brakująca część broni drużyny (%s) odblokowana albo schemat" % pid, String(r.get("kind", "")) == "part"
			and cands.has(pid) and (Scrap.parts.has(pid) or Scrap.schematics.has(pid)))
	check("trzy geody rozbite, bank geod 0 (%d)" % Scrap.geodes, Scrap.geodes == 0)
	# wszystkie części już są: zamiast części próbki
	var parts0: Dictionary = Scrap.parts.duplicate()
	for id in Scrap.find_candidates():
		Scrap.parts[String(id)] = true
	Scrap.geodes = 1
	smp0 = Scrap.samples
	r = await _crack(0.95)
	Scrap.parts = parts0
	check("część, gdy drużyna ma wszystkie: %d próbki zamiast (%s)" % [Scrap.GEODE_FALLBACK, str(r.get("kind", ""))],
		String(r.get("kind", "")) == "sample" and Scrap.samples == smp0 + Scrap.GEODE_FALLBACK)
	var txt := Scrap.geode_text({"kind": "sample", "n": 2})
	var loc0 := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	var pl1 := Scrap.geode_text({"kind": "sample", "n": 1})
	var pl5 := Scrap.geode_text({"kind": "sample", "n": 5})
	var keys := ["Geode taken (+%d)", "Crack it open at the LAB bench in the safe room", "Geode cracked open", "Ore crystals: +%d scrap",
		"A part fused in the crystal: %s", "GEODES  ·  %d", "[{menu_details}]  Crack one open", "No geodes — dig them out of ore veins.",
		"[%s]  Lab  ·  %d geodes to crack open", "+%d geode for the lab"]
	var miss: Array = keys.filter(func(k: String) -> bool: return tr(k) == k)
	TranslationServer.set_locale(loc0)
	check("napis wyniku „%s”, po polsku „%s” / „%s”" % [txt, pl1, pl5], txt.contains("2") and pl1.ends_with("1 próbka") and pl5.ends_with("5 próbek"))
	check("tłumaczenia PL%s" % ("" if miss.is_empty() else " — brak: " + str(miss)), miss.is_empty())

# ---------------------------------------------------------------- 3. karta pracowni i podpowiedź

func _card() -> void:
	Scrap.geodes = 2
	_to_lab()
	await _frames(0.2)
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	check("panel stanowisk w kryjówce", wui != null)
	if wui == null:
		return
	wui.open("lab")
	await _frames(0.2)
	var btn: Button = wui._lab_board_rows.find_child("CrackGeode", true, false)
	check("tablica PROJEKTY: wiersz GEODY · 2 z przyciskiem", wui._lab_board.visible and btn != null and btn.visible)
	var smp0 := Scrap.samples
	Scrap.geode_roll = 0.1
	Scrap._action_at.clear()
	var ev := InputEventKey.new()                                # panel przyjmuje tylko klawisze i pad
	ev.keycode = KEY_V
	ev.physical_keycode = KEY_V
	ev.pressed = true
	wui._input(ev)
	await _frames(0.2)
	check("[%s] w karcie pracowni rozbija geodę (geody %d, próbki +%d, napis „%s”)" % [Actions.key("menu_details"), Scrap.geodes, Scrap.samples - smp0, wui._msg.text],
		Scrap.geodes == 1 and Scrap.samples == smp0 + 1 and String(wui._msg.text).contains(tr("Geode cracked open")))
	Scrap._action_at.clear()
	btn = wui._lab_board_rows.find_child("CrackGeode", true, false)
	if btn != null:
		btn.pressed.emit()
	await _frames(0.2)
	btn = wui._lab_board_rows.find_child("CrackGeode", true, false)
	check("przycisk rozbija ostatnią; bez geod wiersz znika", Scrap.geodes == 0 and btn == null)
	wui.close()
	Scrap.geode_roll = -1.0

# ---------------------------------------------------------------- 4. raport po akcji

## Wiersz raportu sprawdzany na modelu (ResultScreen.build_model z kontekstem z result_test.gd), nie na tekście źródła — w paczce
## eksportu skrypty są skompilowane i tekstu .gd nie ma. Źródło mission.gd czytamy tylko tam, gdzie jest (ze źródeł, CI).
func _report() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/mission.gd")
	if src.is_empty():
		info("raport po akcji: źródło mission.gd niedostępne (paczka eksportu) — pomijam sprawdzenie tekstu")
	else:
		check("raport po akcji: geody w znaleziskach misji", src.contains("\"geodes\": Scrap.geodes_loot"))
	var rt: Node = load("res://scripts/result_test.gd").new()
	var ctx: Dictionary = rt._ctx()
	rt.free()
	ctx["scrap_info"]["finds"] = {"parts": [], "samples": 0, "geodes": 2, "trophy": false}
	var want := TranslationServer.translate("+%d geode for the lab") % 2
	var rows: Array = ResultScreen.build_model(ctx)["finds"]
	var hit := rows.any(func(r: Dictionary) -> bool: return String(r.get("text", "")) == want)
	check("raport po akcji: wiersz „%s” w modelu raportu" % want, hit)

# ---------------------------------------------------------------- 5. zapis

func _save_load() -> void:
	var path := "user://test_geode_progress.cfg"
	var p0: bool = Scrap.persist
	Scrap.persist = true
	Scrap.geodes = 3
	Scrap.save_progress(path)
	Scrap.geodes = 0
	Scrap.load_progress(path)
	var back := Scrap.geodes
	Scrap.persist = p0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check("zapis banku: geody wracają po odczycie (%d)" % back, back == 3)

# ---------------------------------------------------------------- 6. zrzut (okno)

func _shot_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--geodeshots="):
			return "" if DisplayServer.get_name() == "headless" else a.substr("--geodeshots=".length())
	return ""

func _shots() -> void:
	var dir := _shot_dir()
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	Scrap.geodes = 2
	_to_lab()
	await _frames(0.4)
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	wui.open("lab")
	await _frames(0.6)
	get_viewport().get_texture().get_image().save_png(dir.path_join("k4_geode_lab.png"))
	Scrap.geode_roll = 0.6
	Scrap._action_at.clear()
	wui._v_lab.crack_geode()
	await _frames(0.6)
	get_viewport().get_texture().get_image().save_png(dir.path_join("k4_geode_cracked.png"))
	wui.close()
	info("zrzuty w %s" % dir)
