extends Node
## Autoload „Characters” (PROFILES_PLAN.md E1): operatorzy — kilka postaci na jednym komputerze. Każda ma folder `user://characters/<id>/`:
##   profile.cfg    — Profile (XP, perki, wygląd, montaż, stan broni, wprawa, bestiariusz…), jak dawniej `user://profile.cfg`
##   progress.cfg   — Scrap: kampania postaci (złom, bronie, części, próbki, przejdzione misje); liczy się, gdy ta postać hostuje
##   player.cfg     — rzeczy gracza wyjęte z ustawień (PLAYER_KEYS: obejrzane porady, trudność, rekord Nocnego Dyżuru, tablica strzelnicy)
##   character.cfg  — meta: kryptonim, `needs_name`, daty, czas gry, `promotions` (awans — PROFILES_PLAN.md E5)
## Kolejność i aktywna postać w `index.cfg`. Pierwszy na liście autoloadów: Settings, Scrap, Profile i Difficulty biorą ścieżki z `file()`.
## `<id>` to losowy hex, nie kryptonim — zmiana nazwy nie przenosi folderu.
##
## Migracja (D6): zapis sprzed 1.7.426 — `user://profile.cfg`, `user://progress.cfg` i klucze gracza w `user://settings.cfg` — przechodzi do
## postaci nr 1 (z `needs_name`, kreator kryptonimu to etap E3); oryginały zostają w `user://backup_characters_migration/`. Świeża instalacja
## też dostaje postać nr 1. Testy headless nie dotykają zapisu (`persist`); test magazynu: tools/test_characters.gd (osobny katalog `use_root`).

signal changed                        ## inna aktywna postać albo zmiana listy / kryptonimu (menu odświeża kartę i panel)

const ROOT := "user://characters/"
const LEGACY_DIR := "user://"
const BACKUP_DIR := "user://backup_characters_migration/"
const MAX := 6                        ## tyle postaci mieści ekran OPERATORZY (D3)
const NAME_MIN := 2
const NAME_MAX := 16
## Litery łacińskie z polskimi (Latin-1 i Latin Extended-A — kroje UI je mają), cyfry, spacja, „-” i „_” (D2).
const NAME_PATTERN := "^[A-Za-z0-9À-ÖØ-öø-ſ _\\-]+$"
const LEGACY_FILES := ["profile.cfg", "progress.cfg"]
const TRASH := "_trash/"              ## kopie przed resetem / usunięciem (E4) — w katalogu magazynu, ostatnie TRASH_KEEP
const TRASH_KEEP := 3
## Klucze gracza przeniesione z settings.cfg do player.cfg postaci (D5): [sekcja, klucz].
const PLAYER_KEYS := [["game", "seen_tips"], ["game", "difficulty"], ["shift", "best_cleared"], ["shift", "best_time"], ["range", "board"]]

var persist := DisplayServer.get_name() != "headless"      ## testy headless nie ruszają prawdziwego zapisu
var root := ROOT
var active_id := ""
var active_name := ""                 ## kryptonim aktywnej postaci ("" = jeszcze bez kryptonimu — w grze „P<n>”)
var _override_name := ""              ## dev/test: --callsign=NAZWA (bez zapisu)
static var _strip_re: RegEx
var _order: Array = []
var _start_ms := 0
var _time_saved := false
## Ostatnia operacja do cofnięcia (E4, tylko w tej sesji gry): {op, id, copy, index, was_active}; {} = nic.
var _undo := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--callsign="):
			_override_name = a.substr("--callsign=".length())
	if persist:
		ensure_ready()

## Kryptonim, który ta instancja gry pokazuje drużynie (player.callsign; PROFILES_PLAN.md E2). Surowy — każdy peer czyści go `display_clean`.
func callsign() -> String:
	return _override_name if _override_name != "" else active_name

## Katalog magazynu (test: osobny katalog w `user://`, żeby nie dotykać postaci gracza).
func use_root(path: String) -> void:
	root = path.trim_suffix("/") + "/"
	active_id = ""
	_order.clear()

## Wczytuje listę; bez listy — migracja starego zapisu z `legacy_dir` (albo pusta postać nr 1). Aktywna postać zawsze istnieje.
func ensure_ready(legacy_dir := LEGACY_DIR, backup_dir := BACKUP_DIR) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	_load_index()
	if _order.is_empty():
		migrate_legacy(legacy_dir, backup_dir)
	if not _order.has(active_id):
		active_id = String(_order[0])
		_save_index()
	_set_meta(active_id, "last_played", int(Time.get_unix_time_from_system()))
	active_name = String(meta(active_id)["name"])
	_start_ms = Time.get_ticks_msec()
	_time_saved = false
	print("[CHARS] %d postaci, aktywna %s" % [_order.size(), active_id])

## Zapis sprzed postaci → postać nr 1. Pliki profilu i kampanii przenosi, klucze gracza wycina z settings.cfg do player.cfg; każdy
## oryginał najpierw kopiuje do `backup_dir`. Zwraca id nowej postaci.
func migrate_legacy(legacy_dir := LEGACY_DIR, backup_dir := BACKUP_DIR) -> String:
	legacy_dir = legacy_dir.trim_suffix("/") + "/"
	backup_dir = backup_dir.trim_suffix("/") + "/"
	var id := create("", true)
	var moved: Array = []
	for f in LEGACY_FILES:
		var src: String = legacy_dir + f
		if not FileAccess.file_exists(src):
			continue
		DirAccess.make_dir_recursive_absolute(backup_dir)
		DirAccess.copy_absolute(src, backup_dir + f)
		if DirAccess.copy_absolute(src, dir_of(id) + f) == OK:
			DirAccess.remove_absolute(src)
			moved.append(f)
	var settings := ConfigFile.new()
	if settings.load(legacy_dir + "settings.cfg") == OK:
		var player := ConfigFile.new()
		var any := false
		for k in PLAYER_KEYS:
			if settings.has_section_key(k[0], k[1]):
				player.set_value(k[0], k[1], settings.get_value(k[0], k[1]))
				settings.erase_section_key(k[0], k[1])
				any = true
		if any:
			DirAccess.make_dir_recursive_absolute(backup_dir)
			DirAccess.copy_absolute(legacy_dir + "settings.cfg", backup_dir + "settings.cfg")
			player.save(dir_of(id) + "player.cfg")
			settings.save(legacy_dir + "settings.cfg")
			moved.append("settings.cfg (klucze gracza)")
	print("[CHARS] migracja do postaci %s: %s" % [id, ", ".join(moved) if not moved.is_empty() else "świeży start"])
	return id

## Nowa postać (pusty folder, meta). "" — limit MAX. Nie zmienia aktywnej postaci.
func create(name: String, needs_name := false) -> String:
	if _order.size() >= MAX:
		return ""
	var id := _new_id()
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	var cf := ConfigFile.new()
	var now := int(Time.get_unix_time_from_system())
	cf.set_value("character", "id", id)
	cf.set_value("character", "name", clean_name(name))
	cf.set_value("character", "needs_name", needs_name)
	cf.set_value("character", "created", now)
	cf.set_value("character", "last_played", now)
	cf.set_value("character", "play_time", 0.0)
	cf.set_value("character", "promotions", 0)
	cf.save(dir_of(id) + "character.cfg")
	_order.append(id)
	if active_id == "":
		active_id = id
	_save_index()
	return id

## Meta wszystkich postaci w kolejności z listy.
func list() -> Array:
	var out: Array = []
	for id in _order:
		out.append(meta(String(id)))
	return out

func meta(id: String) -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(dir_of(id) + "character.cfg")
	return {"id": id, "name": String(cf.get_value("character", "name", "")), "needs_name": bool(cf.get_value("character", "needs_name", false)),
		"created": int(cf.get_value("character", "created", 0)), "last_played": int(cf.get_value("character", "last_played", 0)),
		"play_time": float(cf.get_value("character", "play_time", 0.0)), "promotions": int(cf.get_value("character", "promotions", 0))}

## Ustawia aktywną postać (zapamiętaną na następne uruchomienie). Przeładowanie Profile / Scrap / ustawień gracza w trakcie gry — etap E3.
func select(id: String) -> bool:
	if not _order.has(id):
		return false
	if id == active_id:
		active_name = String(meta(id)["name"])      # ta sama postać (przeładowanie po resecie): czas gry liczy się dalej od tego samego startu
		return true
	_flush_time()
	active_id = id
	active_name = String(meta(id)["name"])
	_save_index()
	_set_meta(id, "last_played", int(Time.get_unix_time_from_system()))
	_start_ms = Time.get_ticks_msec()
	_time_saved = false
	return true

## Przełączenie postaci w menu (E3): zapis obecnej, wybór i przeładowanie kampanii (Scrap), profilu, rzeczy gracza (Settings) i trudności.
## Tylko poza sesją — w trakcie gry profil i kampania są w użyciu. false: nieznana postać.
## `save_current` = false po resecie / usunięciu: profil w pamięci należy do starego stanu i nie może nadpisać świeżo wyczyszczonych plików.
func activate(id: String, save_current := true) -> bool:
	if not _order.has(id):
		return false
	var profile := _auto("Profile")
	if save_current and persist and profile != null and active_id != "":
		profile.save()
	select(id)
	# autoloady po nazwie: characters.gd ładują też narzędzia `-s` (tools/test_characters.gd), gdzie autoloadów nie ma
	for step in [["Scrap", "load_progress"], ["Profile", "reload"], ["Settings", "reload_player"], ["Difficulty", "reload_saved"]]:
		var n := _auto(String(step[0]))
		if n != null:
			n.call(String(step[1]))
	changed.emit()
	return true

func _auto(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(n) if tree != null else null

## Podsumowanie dla karty postaci (E3) prosto z plików, bez wczytywania profilu: meta + XP, wygląd, przejdzione misje, złom.
func summary(id: String) -> Dictionary:
	var m := meta(id)
	var pf := ConfigFile.new()
	pf.load(dir_of(id) + "profile.cfg")
	var gf := ConfigFile.new()
	gf.load(dir_of(id) + "progress.cfg")
	m["xp"] = maxi(0, int(pf.get_value("profile", "xp", 0)))
	m["look"] = int(pf.get_value("profile", "look", 0))
	m["cleared"] = Array(gf.get_value("campaign", "cleared", []))
	m["bank"] = maxi(0, int(gf.get_value("scrap", "bank", 0)))
	m["parts"] = Array(gf.get_value("workshop", "parts", [])).size()
	m["weapons"] = Array(gf.get_value("workshop", "unlocked", [])).size()
	m["samples"] = maxi(0, int(gf.get_value("workshop", "samples", 0)))
	m["perks"] = Array(pf.get_value("profile", "equipped", [])).filter(func(e: Variant) -> bool: return String(e) != "").size()
	return m

func has(id: String) -> bool:
	return _order.has(id)

func count() -> int:
	return _order.size()

## Kryptonim postaci: "" = zmieniony, inaczej kod błędu z validate_name.
func rename(id: String, name: String) -> String:
	var err := validate_name(name, id)
	if err != "":
		return err
	_set_meta(id, "name", clean_name(name))
	_set_meta(id, "needs_name", false)
	if id == active_id:
		active_name = clean_name(name)
	changed.emit()
	return ""

## Ścieżka pliku aktywnej postaci; "" bez postaci (headless).
func file(name: String) -> String:
	return "" if active_id == "" else dir_of(active_id) + name

func dir_of(id: String) -> String:
	return root + id + "/"

## Kryptonim po obcięciu spacji na brzegach i zwinięciu podwójnych; dłuższy niż NAME_MAX — ucięty.
static func clean_name(s: String) -> String:
	var out := s.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.substr(0, NAME_MAX)

## Kryptonim do wyświetlenia z cudzego peera (sieć: kosmetyka bez walidacji serwera, jak wygląd): wycina znaki spoza NAME_PATTERN,
## zwija spacje, przycina do NAME_MAX. Za krótki po czyszczeniu → "" (UI pokaże „P<n>”).
static func display_clean(s: String) -> String:
	if _strip_re == null:
		_strip_re = RegEx.create_from_string("[^A-Za-z0-9À-ÖØ-öø-ſ _\\-]")
	var out := clean_name(_strip_re.sub(s.substr(0, 64), "", true))
	return out if out.length() >= NAME_MIN else ""

## "" — dobry kryptonim; "short" / "long" / "chars" / "taken" (inna postać na tym komputerze, bez rozróżniania wielkości liter).
func validate_name(s: String, except_id := "") -> String:
	var n := s.strip_edges()
	while n.contains("  "):
		n = n.replace("  ", " ")
	if n.length() < NAME_MIN:
		return "short"
	if n.length() > NAME_MAX:
		return "long"
	var re := RegEx.create_from_string(NAME_PATTERN)
	if re.search(n) == null:
		return "chars"
	for id in _order:
		if String(id) != except_id and String(meta(String(id))["name"]).to_lower() == n.to_lower():
			return "taken"
	return ""

# ---------------------------------------------------------------- reset i usuwanie (PROFILES_PLAN.md E4, D4)

## Nowa kampania: zeruje progress.cfg postaci (złom, bronie, części, próbki, przejdzione misje, zapas). Profil, rzeczy gracza i kryptonim
## zostają. Najpierw kopia (Cofnij). Aktywna postać przeładowuje się od razu.
func reset_campaign(id: String) -> bool:
	if not _order.has(id):
		return false
	_backup("campaign", id)
	DirAccess.remove_absolute(dir_of(id) + "progress.cfg")
	_after_change(id)
	return true

## Reset postaci: wszystko poza kryptonimem i wyglądem — profil od zera (z tym samym `look`), kampania, rzeczy gracza, czas gry, awanse.
func reset_character(id: String) -> bool:
	if not _order.has(id):
		return false
	_backup("character", id)
	var pf := ConfigFile.new()
	pf.load(dir_of(id) + "profile.cfg")
	var look := int(pf.get_value("profile", "look", 0))
	for f in ["profile.cfg", "progress.cfg", "player.cfg"]:
		DirAccess.remove_absolute(dir_of(id) + f)
	var fresh := ConfigFile.new()
	fresh.set_value("profile", "look", look)
	fresh.save(dir_of(id) + "profile.cfg")
	_set_meta(id, "play_time", 0.0)
	_set_meta(id, "promotions", 0)
	if id == active_id:
		_start_ms = Time.get_ticks_msec()
		_time_saved = false
	_after_change(id)
	return true

## Usunięcie postaci (folder do kopii, Cofnij). Aktywna → aktywna zostaje pierwsza z listy; ostatnia → nowa pusta postać z `needs_name`
## (menu otworzy kreator). Zwraca id postaci aktywnej po operacji.
func delete(id: String) -> String:
	if not _order.has(id):
		return active_id
	_backup("delete", id)
	_rm_tree(dir_of(id))
	_order.erase(id)
	if _order.is_empty():
		active_id = ""
		create("", true)
	if id == active_id or not _order.has(active_id):
		active_id = ""
		_save_index()
		activate(String(_order[0]), false)
	else:
		_save_index()
	changed.emit()
	return active_id

func can_undo() -> bool:
	return not _undo.is_empty() and DirAccess.dir_exists_absolute(String(_undo["copy"]))

## Opis ostatniej operacji do cofnięcia: {op: "campaign" / "character" / "delete", name}; {} = nic.
func undo_info() -> Dictionary:
	return {"op": _undo["op"], "name": _undo["name"]} if can_undo() else {}

## Cofa ostatni reset albo usunięcie: folder postaci wraca z kopii, usunięta wraca na swoje miejsce na liście (i jako aktywna, jeśli była).
func undo() -> bool:
	if not can_undo():
		return false
	var id := String(_undo["id"])
	var copy := String(_undo["copy"])
	if _order.has(id):
		_rm_tree(dir_of(id))
	_copy_tree(copy, dir_of(id))
	if not _order.has(id):
		_order.insert(clampi(int(_undo["index"]), 0, _order.size()), id)
		# pusta postać utworzona po usunięciu ostatniej znika razem z cofnięciem
		for other in _order.duplicate():
			if String(other) != id and bool(meta(String(other))["needs_name"]) and not FileAccess.file_exists(dir_of(String(other)) + "profile.cfg"):
				_rm_tree(dir_of(String(other)))
				_order.erase(other)
	_save_index()
	var was_active := bool(_undo["was_active"])
	_undo = {}
	if was_active or id == active_id or not _order.has(active_id):
		var profile := _auto("Profile")
		if persist and profile != null and active_id != id and _order.has(active_id):
			profile.save()                  # inna aktywna postać (np. po usunięciu): jej stan zostaje zapisany, zanim wróci przywrócona
		active_id = ""
		activate(id, false)
	else:
		changed.emit()
	return true

func _backup(op: String, id: String) -> void:
	var copy := root + TRASH + "%s_%d_%s/" % [id, int(Time.get_unix_time_from_system()), op]
	_copy_tree(dir_of(id), copy)
	_undo = {"op": op, "id": id, "copy": copy, "index": _order.find(id), "was_active": id == active_id, "name": String(meta(id)["name"])}
	# najstarsze kopie poza TRASH_KEEP znikają (nazwa zaczyna się od id, więc sortujemy po czasie z nazwy)
	var d := DirAccess.open(root + TRASH)
	if d == null:
		return
	var dirs: Array = Array(d.get_directories())
	dirs.sort_custom(func(a: String, b: String) -> bool: return int(a.split("_")[1]) > int(b.split("_")[1]) if a.split("_").size() > 2 and b.split("_").size() > 2 else a > b)
	for i in range(TRASH_KEEP, dirs.size()):
		if root + TRASH + String(dirs[i]) + "/" != copy:
			_rm_tree(root + TRASH + String(dirs[i]))

func _after_change(id: String) -> void:
	if id == active_id:
		activate(id, false)
	else:
		changed.emit()

static func _copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	for sub in d.get_directories():
		_copy_tree(src.path_join(sub), dst.path_join(sub))

static func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path.trim_suffix("/"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush_time()

## Czas gry: przy wyjściu (i przy zmianie postaci) dopisuje czas od startu / wyboru do `play_time` aktywnej postaci.
func _flush_time() -> void:
	if not persist or active_id == "" or _time_saved:
		return
	_time_saved = true
	var m := meta(active_id)
	_set_meta(active_id, "play_time", float(m["play_time"]) + float(Time.get_ticks_msec() - _start_ms) / 1000.0)

func _set_meta(id: String, key: String, value: Variant) -> void:
	var cf := ConfigFile.new()
	cf.load(dir_of(id) + "character.cfg")
	cf.set_value("character", key, value)
	cf.save(dir_of(id) + "character.cfg")

func _load_index() -> void:
	var cf := ConfigFile.new()
	_order.clear()
	active_id = ""
	if cf.load(root + "index.cfg") != OK:
		return
	for id in Array(cf.get_value("characters", "order", [])):
		if DirAccess.dir_exists_absolute(dir_of(String(id))):
			_order.append(String(id))
	active_id = String(cf.get_value("characters", "active", ""))

func _save_index() -> void:
	var cf := ConfigFile.new()
	cf.set_value("characters", "order", _order)
	cf.set_value("characters", "active", active_id)
	cf.save(root + "index.cfg")

func _new_id() -> String:
	var id := ""
	while id == "" or _order.has(id) or DirAccess.dir_exists_absolute(dir_of(id)):
		id = "%08x" % (randi() & 0x7fffffff)
	return id
