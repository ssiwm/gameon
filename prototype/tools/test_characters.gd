extends SceneTree
## Test magazynu postaci (scripts/characters.gd, PROFILES_PLAN.md E1) na osobnych katalogach w user:// — zapis gracza zostaje nietknięty:
## migracja starego zapisu (pliki, klucze gracza z settings.cfg, kopie), brak drugiej migracji, nowa postać i wybór aktywnej, kryptonimy,
## świeża instalacja, limit postaci, czas gry.
##   godot --headless --path prototype -s tools/test_characters.gd     → ostatni wiersz: PASS / FAIL

const Store := preload("res://scripts/characters.gd")
const BASE := "user://chartest/"

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[CHARS-TEST] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _store(root: String) -> Node:
	var c: Node = Store.new()
	c.persist = true
	c.use_root(root)
	return c


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _cfg(path: String) -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path)
	return cf


func _init() -> void:
	_rm_tree(BASE)
	var legacy := BASE + "legacy/"
	var backup := BASE + "backup/"
	var root := BASE + "chars/"
	DirAccess.make_dir_recursive_absolute(legacy)
	var pf := ConfigFile.new()
	pf.set_value("profile", "xp", 2918)
	pf.save(legacy + "profile.cfg")
	var gf := ConfigFile.new()
	gf.set_value("scrap", "bank", 82)
	gf.set_value("campaign", "cleared", ["z1_m1", "z1_m2"])
	gf.save(legacy + "progress.cfg")
	var sf := ConfigFile.new()
	sf.set_value("game", "vol_master", 0.5)
	sf.set_value("game", "locale", 1)
	sf.set_value("game", "seen_tips", ["move", "noise"])
	sf.set_value("game", "difficulty", 1)
	sf.set_value("shift", "best_cleared", 3)
	sf.set_value("shift", "best_time", 512.5)
	sf.set_value("range", "board", [{"ex": "plates", "t": 7.7}])
	sf.save(legacy + "settings.cfg")

	# 1. migracja
	var c := _store(root)
	c.ensure_ready(legacy, backup)
	var ids: Array = c.list().map(func(m: Dictionary) -> String: return String(m["id"]))
	var id1: String = ids[0] if not ids.is_empty() else ""
	_check("migracja: jedna postać, aktywna, czeka na kryptonim", ids.size() == 1 and c.active_id == id1 and bool(c.meta(id1)["needs_name"]))
	_check("migracja: profil i kampania w folderze postaci (XP %d, złom %d)" % [int(_cfg(c.dir_of(id1) + "profile.cfg").get_value("profile", "xp", -1)),
		int(_cfg(c.dir_of(id1) + "progress.cfg").get_value("scrap", "bank", -1))],
		int(_cfg(c.file("profile.cfg")).get_value("profile", "xp", -1)) == 2918 and int(_cfg(c.file("progress.cfg")).get_value("scrap", "bank", -1)) == 82)
	_check("migracja: stare pliki zdjęte, kopie zostały", not FileAccess.file_exists(legacy + "profile.cfg") and not FileAccess.file_exists(legacy + "progress.cfg")
		and FileAccess.file_exists(backup + "profile.cfg") and FileAccess.file_exists(backup + "progress.cfg") and FileAccess.file_exists(backup + "settings.cfg"))
	var pl := _cfg(c.file("player.cfg"))
	_check("migracja: klucze gracza w player.cfg (porady, trudność, Nocny Dyżur, strzelnica)", Array(pl.get_value("game", "seen_tips", [])) == ["move", "noise"]
		and int(pl.get_value("game", "difficulty", -1)) == 1 and int(pl.get_value("shift", "best_cleared", -1)) == 3
		and is_equal_approx(float(pl.get_value("shift", "best_time", 0.0)), 512.5) and (pl.get_value("range", "board", []) as Array).size() == 1)
	var st := _cfg(legacy + "settings.cfg")
	_check("migracja: settings.cfg bez kluczy gracza, ustawienia komputera zostały", not st.has_section_key("game", "seen_tips") and not st.has_section_key("game", "difficulty")
		and not st.has_section("shift") and not st.has_section("range") and is_equal_approx(float(st.get_value("game", "vol_master", 0.0)), 0.5) and int(st.get_value("game", "locale", 0)) == 1)
	_check("migracja: kopia settings.cfg ma klucze gracza", _cfg(backup + "settings.cfg").has_section_key("game", "seen_tips"))
	c.free()

	# 2. drugi start: bez drugiej migracji, nawet gdy stare pliki wrócą
	pf.save(legacy + "profile.cfg")
	var c2 := _store(root)
	c2.ensure_ready(legacy, backup)
	_check("drugi start: dalej jedna postać i ta sama aktywna, stary plik nie wchodzi drugi raz", c2.list().size() == 1 and c2.active_id == id1 and FileAccess.file_exists(legacy + "profile.cfg"))

	# 3. nowa postać i wybór aktywnej
	var id2: String = c2.create("Sowa")
	_check("nowa postać: druga na liście, aktywna bez zmian", c2.list().size() == 2 and c2.active_id == id1 and String(c2.meta(id2)["name"]) == "Sowa" and not bool(c2.meta(id2)["needs_name"]))
	var p1: String = c2.file("profile.cfg")
	_check("wybór postaci: inne ścieżki plików", c2.select(id2) and c2.file("profile.cfg") != p1 and c2.file("profile.cfg").begins_with(c2.dir_of(id2)))
	_check("wybór nieistniejącej postaci odrzucony", not c2.select("deadbeef") and c2.active_id == id2)
	c2.free()
	var c3 := _store(root)
	c3.ensure_ready(legacy, backup)
	_check("wybór zapamiętany na następny start", c3.active_id == id2)

	# 4. kryptonimy
	var v := {"": c3.validate_name(""), "A": c3.validate_name("A"), "long": c3.validate_name("Abcdefghijklmnopq"), "chars": c3.validate_name("Sowa!"),
		"taken": c3.validate_name("sOWA", id1), "own": c3.validate_name("sowa", id2), "pl": c3.validate_name("Żaba Łódź"), "space": c3.validate_name("  Iskra   7 ")}
	_check("kryptonim: za krótki, za długi, zły znak, zajęty (%s)" % str(v), v[""] == "short" and v["A"] == "short" and v["long"] == "long" and v["chars"] == "chars" and v["taken"] == "taken")
	_check("kryptonim: własny bez zmian, polskie litery, spacje zwinięte (%s)" % str([v["own"], v["pl"], v["space"], Store.clean_name("  Iskra   7 ")]),
		v["own"] == "" and v["pl"] == "" and v["space"] == "" and Store.clean_name("  Iskra   7 ") == "Iskra 7")
	_check("zmiana nazwy postaci z migracji: zapisana, już nie czeka na kryptonim", c3.rename(id1, "Wilk") == "" and String(c3.meta(id1)["name"]) == "Wilk" and not bool(c3.meta(id1)["needs_name"]))
	_check("zmiana nazwy na zajętą odrzucona", c3.rename(id1, "SOWA") == "taken" and String(c3.meta(id1)["name"]) == "Wilk")

	# 5. limit postaci
	var made := 0
	while c3.create("Op %d" % made) != "":
		made += 1
	_check("limit: %d postaci, kolejna odrzucona" % c3.list().size(), c3.list().size() == Store.MAX)

	# 6. czas gry
	c3._start_ms = Time.get_ticks_msec() - 5000
	c3._flush_time()
	var pt: float = float(c3.meta(id2)["play_time"])
	_check("czas gry dopisany przy wyjściu (%.1f s)" % pt, pt >= 4.9 and pt <= 6.0)
	c3.free()

	# 7. świeża instalacja
	var fresh := _store(BASE + "fresh/")
	fresh.ensure_ready(BASE + "empty/", BASE + "fresh_backup/")
	var fm: Array = fresh.list()
	_check("świeża instalacja: jedna pusta postać czekająca na kryptonim, bez kopii", fm.size() == 1 and bool(fm[0]["needs_name"]) and not FileAccess.file_exists(fresh.file("profile.cfg"))
		and not DirAccess.dir_exists_absolute(BASE + "fresh_backup/"))
	fresh.free()

	_rm_tree(BASE)
	print("[CHARS-TEST] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
