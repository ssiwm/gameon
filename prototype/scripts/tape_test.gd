extends Node
## Test taśm (DIG_LOOT_PLAN.md K4, tapes.gd) na mapie 1.1:
##   godot --headless --path prototype -- --host --nobot --mission=z1_m1 --tapetest --autoquit=60
## Dane (6 taśm, po 2 na mapę, źródła zgodne z danymi map, tłumaczenia PL), taśma zakopana w głębokiej strefie 1.1 (miejsce z ziarna,
## wypada jako przedmiot), podniesienie (tylko człowiek, archiwum profilu, komunikat u każdego peera, dziennik `tape`, drugi raz bez
## duplikatu), sejf patrolu daje taśmę, skrytka 1.1 nie, karta ARCHIWUM (zakryta → zebrana, znacznik „nowe”), zapis i odczyt profilu.
## W oknie z `--tapeshots=KATALOG`: zrzuty `k4_tape_ground` (kaseta na ziemi przy postaci) i `k4_archive` (karta ARCHIWUM).

const Tapes := preload("res://scripts/tapes.gd")
const Codex := preload("res://scripts/codex.gd")
const CodexPage := preload("res://scripts/codex_page.gd")
const DigZone := preload("res://scripts/dig_zone.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const LOG_DIR := "user://test_tape_sessions"

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var failed := 0
var total := 0
var _tapes0: Dictionary = {}
var _seen0: Dictionary = {}

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[TAPE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[TAPE-TEST] INFO  %s" % label)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	check("mapa 1.1 z graczem (%s)" % level.map_id, player != null and level.map_id == "z1_m1")
	if player == null or level.map_id != "z1_m1":
		_finish()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	Director.set_process(false)
	_tapes0 = Profile.tapes.duplicate()
	_seen0 = Profile.seen.duplicate()
	Profile.tapes.clear()
	Profile._seen_baseline = false
	SessionLog.enabled = true
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "tapes"})
	_data()
	await _dig()
	await _pickup()
	await _strongbox()
	await _stash()
	await _archive()
	_save_load()
	await _shots()
	_finish()

func _finish() -> void:
	Profile.tapes = _tapes0
	Profile.seen = _seen0
	print("[TAPE-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func _frames(seconds: float) -> void:
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < seconds and is_inside_tree():
		await get_tree().physics_frame
		t += dt

func _place_player(pos: Vector2) -> void:
	player.global_position = pos
	player.velocity = Vector2.ZERO

## Przedmioty „tape” leżące teraz na mapie.
func _tape_items() -> Array:
	return level.get_children().filter(func(n: Node) -> bool: return n.get("kind") == "tape" and not n.is_queued_for_deletion())

func _log_events(ev: String) -> Array:
	var rows: Array = []
	if SessionLog.path == "" or not FileAccess.file_exists(SessionLog.path):
		return rows
	for line in FileAccess.get_file_as_string(SessionLog.path).split("\n", false):
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary and (v as Dictionary).get("ev") == ev:
			rows.append(v)
	return rows

# ---------------------------------------------------------------- 1. dane

func _data() -> void:
	check("6 taśm w ORDER i TAPES", Tapes.ORDER.size() == 6 and Tapes.TAPES.size() == 6 and Tapes.ORDER.all(func(id: String) -> bool: return Tapes.has(id)))
	var tr_pl := TranslationServer.get_translation_object("pl")
	for map_id in ["z1_m1", "z1_m2", "z1_m3"]:
		var ids: Array = Tapes.ORDER.filter(func(id: String) -> bool: return String(Tapes.TAPES[id]["map"]) == map_id)
		var srcs: Array = ids.map(func(id: String) -> String: return String(Tapes.TAPES[id]["src"]))
		check("%s: dwie taśmy — w strefie i w sejfie albo skrytce (%s)" % [map_id, str(srcs)], ids.size() == 2 and srcs.has("dig") and (srcs.has("box") or srcs.has("stash")))
		var consts: Dictionary = (load("res://scripts/maps/%s.gd" % map_id) as GDScript).get_script_constant_map()
		for id in ids:
			var t: Dictionary = Tapes.TAPES[id]
			match String(t["src"]):
				"dig":
					var zs: Array = (consts.get("DIG_ZONES", []) as Array).filter(func(z: Array) -> bool:
						return z.size() > 7 and z[7] is Dictionary and String((z[7] as Dictionary).get("tape", "")) == id)
					check("%s: strefa wydobycia z taśmą %s (głęboka, budzi wrogów)" % [map_id, id], zs.size() == 1 and bool((zs[0][7] as Dictionary).get("wake", true)))
				"box":
					check("%s: sejf dla taśmy %s" % [map_id, id], (consts.get("STRONGBOXES", []) as Array).size() == 1 and Tapes.for_source(map_id, "box") == id)
				"stash":
					var cell: Vector2i = t["cell"]
					var rows: Array = consts.get("MAP", [])
					var is_h := cell.y < rows.size() and cell.x < String(rows[cell.y]).length() and String(rows[cell.y])[cell.x] == "H"
					check("%s: skrytka `H` na kaflu %s dla taśmy %s" % [map_id, str(cell), id], is_h and Tapes.for_source(map_id, "stash", cell) == id
						and Tapes.for_source(map_id, "stash", cell + Vector2i(1, 0)) == "")
		for id in ids:
			var t: Dictionary = Tapes.TAPES[id]
			var miss: Array = ["title", "who", "date", "text"].filter(func(k: String) -> bool:
				var src := String(t[k])
				return tr_pl == null or String(tr_pl.get_message(src)) == "" or String(tr_pl.get_message(src)) == src)
			check("%s: tłumaczenie PL taśmy %s%s" % [map_id, id, "" if miss.is_empty() else " — brak: " + str(miss)], miss.is_empty())
	var ui_keys := ["ARCHIVE", "Tape: %s", "New in the Archive (pause menu)", "Already in your Archive", "Not found yet", "Found",
		"A lost tape. Find it on a mission to learn what it holds."]
	ui_keys.append_array(Tapes.SRC_TEXT.values())
	var ui_miss: Array = ui_keys.filter(func(k: String) -> bool: return tr_pl == null or String(tr_pl.get_message(k)) == "")
	check("tłumaczenia PL napisów archiwum%s" % ("" if ui_miss.is_empty() else " — brak: " + str(ui_miss)), ui_miss.is_empty())

# ---------------------------------------------------------------- 2. taśma w strefie

func _dig() -> void:
	var z: Node2D = null
	for q in level.dig_zones():
		if String(q.tape) != "":
			z = q
	check("1.1: głęboka strefa z taśmą m1_dig", z != null and String(z.tape) == "m1_dig")
	if z == null:
		return
	var ks: Array = []
	for k in (z.finds as Array).size():
		if String(z.finds[k]["kind0"]) == DigZone.FIND_TAPE:
			ks.append(k)
	check("1.1: jedna taśma wśród %d znajdziek strefy" % (z.finds as Array).size(), ks.size() == 1)
	if ks.size() != 1:
		return
	var f: Dictionary = z.finds[ks[0]]
	var e: Dictionary = z.entrance()
	var ep := Vector2(float(e.get("wall_x", 0.0)), float(e.get("floor_y", 0.0)))
	var dist := (f["pos"] as Vector2).distance_to(ep)
	info("1.1: taśma w %s, wejście %s" % [str(f["pos"]), str(ep)])
	check("1.1: taśma zakopana w skale strefy, %.0f px (%.1f kafla) od wejścia" % [dist, dist / 16.0], int(f["state"]) == DigZone.Find.BURIED
		and z.rect_px().has_point(f["pos"]) and dist >= 6.0 * 16.0)
	var res: Array = z._resolve_find(DigZone.FIND_TAPE)
	check("1.1: odkopana taśma to przedmiot „tape” nr %d (%s)" % [Tapes.index_of("m1_dig"), str(res)], res == ["tape", Tapes.index_of("m1_dig"), -1])
	var n0 := _tape_items().size()
	z._spawn_find(ks[0], f["pos"], 0)
	await _frames(0.3)
	var items := _tape_items()
	check("1.1: odkopana taśma wypada jako przedmiot (%d)" % (items.size() - n0), items.size() == n0 + 1 and int(items[-1].arg) == Tapes.index_of("m1_dig"))
	for it in items:
		level.take_item(String(it.name), true)
	z.reset_to(PackedByteArray())
	await _frames(0.1)

# ---------------------------------------------------------------- 3. podniesienie

func _pickup() -> void:
	var idx := Tapes.index_of("m1_dig")
	var home := player.global_position
	var fx0: int = level.tapes_fx
	# bot jej nie bierze
	player.is_bot = true
	level.spawn_item("tape", idx, home)
	await _frames(0.6)
	var left := _tape_items().size()
	player.is_bot = false
	_place_player(home)                                        # bot mógł odejść
	check("bot nie podnosi taśmy", left == 1 and not Profile.has_tape("m1_dig"))
	await _frames(0.6)
	check("człowiek podnosi taśmę: przedmiot znika, taśma w archiwum, komunikat (%d)" % (level.tapes_fx - fx0),
		_tape_items().is_empty() and Profile.has_tape("m1_dig") and level.tapes_fx - fx0 == 1)
	check("taśma ma znacznik „nowe” do obejrzenia", Profile.is_new("tape:m1_dig"))
	var ev := _log_events("tape")
	check("dziennik `tape` (%d) z id i graczem" % ev.size(), ev.size() == 1 and String(ev[0].get("id", "")) == "m1_dig" and String(ev[0].get("who", "")) == "P1")
	# druga ta sama taśma: komunikat „już masz”, bez duplikatu
	level.spawn_item("tape", idx, home)
	await _frames(0.6)
	check("druga ta sama taśma: podniesiona, bez duplikatu w archiwum", _tape_items().is_empty() and level.tapes_fx - fx0 == 2 and Profile.tapes.size() == 1)
	_place_player(home)

# ---------------------------------------------------------------- 4. sejf i skrytka

func _strongbox() -> void:
	var sb: Node2D = level.get_node_or_null("Strongbox1")
	check("1.1: sejf patrolu na mapie", sb != null)
	if sb == null:
		return
	var n0 := _tape_items().size()
	sb._open()
	await _frames(0.3)
	var items := _tape_items()
	check("sejf po otwarciu daje taśmę patrolu m1_box", items.size() == n0 + 1 and int(items[-1].arg) == Tapes.index_of("m1_box"))
	for it in items:
		level.take_item(String(it.name), true)
	sb.reset_strongbox()
	await _frames(0.1)

func _stash() -> void:
	var st: Node2D = level.get_node_or_null("MapStash0")
	check("1.1: skrytka na mapie", st != null)
	if st == null:
		return
	var home := player.global_position
	var n0 := _tape_items().size()
	_place_player(st.global_position)
	await _frames(0.5)
	check("skrytka 1.1 nie ma taśmy (taśma w skrytce tylko na 1.3)", not is_instance_valid(st) or st.is_queued_for_deletion() or level.get_node_or_null("MapStash0") == null)
	check("po skrytce 1.1 nie leży nowa taśma", _tape_items().size() == n0)
	_place_player(home)
	await _frames(0.1)

# ---------------------------------------------------------------- 5. archiwum

func _archive() -> void:
	var ar := Codex.archive()
	var groups := {}
	for e in ar:
		groups[String(e["group"])] = true
	check("archiwum: 6 wpisów w 3 grupach map", ar.size() == 6 and groups.size() == 3)
	var hid := Codex.tape_view(ar[Tapes.index_of("m2_box")])
	var got := Codex.tape_view(ar[Tapes.index_of("m1_dig")])
	check("archiwum: niezebrana taśma zakryta (??? i gdzie szukać: %s)" % String(hid["stats"][0][1]), String(hid["title"]) == "???"
		and bool(hid["portrait"].get("unknown", false)) and String(hid["stats"][0][1]).begins_with("1.2"))
	check("archiwum: zebrana taśma z tytułem, mówcą i zapisem", String(got["title"]) == String(Tapes.TAPES["m1_dig"]["title"])
		and String(got["tag"]).contains("1987") and String(got["text"]) == String(Tapes.TAPES["m1_dig"]["text"]))
	Profile.add_tape("m1_box")                                # druga taśma (jak z sejfu): kropka na liście, póki wpis nie wybrany
	var page := CodexPage.new()
	add_child(page)
	page.setup(ar)                                            # strona wybiera pierwszy wpis — ten jest już obejrzany
	await get_tree().process_frame
	var dot_before := String(page._buttons[1].text).ends_with("•")
	var first_seen := not Profile.is_new("tape:m1_dig")
	page.select(1)
	check("archiwum: kropka „nowe” do pierwszego obejrzenia, niezebrana bez kropki", dot_before and first_seen and not Profile.is_new("tape:m1_box")
		and not String(page._buttons[1].text).ends_with("•") and not String(page._buttons[2].text).ends_with("•"))
	page.queue_free()

func _save_load() -> void:
	var path := "user://test_tape_profile.cfg"
	Profile.save_to(path)
	Profile.tapes.clear()
	Profile.load_from(path)
	check("zapis profilu: taśmy wracają po odczycie (%s)" % str(Profile.tapes.keys()), Profile.has_tape("m1_dig") and Profile.has_tape("m1_box") and Profile.tapes.size() == 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---------------------------------------------------------------- 6. zrzuty (okno)

func _shot_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tapeshots="):
			return "" if DisplayServer.get_name() == "headless" else a.substr("--tapeshots=".length())
	return ""

func _grab(name: String) -> void:
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	info("zrzut %s" % dir.path_join(name + ".png"))

func _shots() -> void:
	if _shot_dir() == "":
		return
	var lamp: Node2D = level.mission_lamp_at(254, 40)
	if lamp != null:
		_place_player(lamp.global_position + Vector2(-150.0, 30.0))     # pod lampą, z dala od skrzynki i baterii
	await _frames(0.5)
	level.spawn_item("tape", Tapes.index_of("m1_box"), player.global_position + Vector2(44.0, -4.0))   # poza zasięgiem podniesienia
	await _frames(1.2)
	_grab("k4_tape_ground")
	for it in _tape_items():
		level.take_item(String(it.name), true)
	var pm: Control = main.get_node("UI/PauseMenu")
	pm.open()
	await _frames(0.3)
	pm._show_tab(5)
	await _frames(0.3)
	pm.page_of(5).select(1)
	await _frames(0.5)
	_grab("k4_archive")
	pm.page_of(5).select(2)
	await _frames(0.3)
	_grab("k4_archive_hidden")
