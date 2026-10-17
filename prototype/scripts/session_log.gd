extends RefCounted
## Dziennik sesji (REVIEW_PLAN.md R3): co się działo w misji, w liczbach — do playtestów (GDD §16.0, §23.3).
##
## Jeden plik na uruchomienie gry: `user://sessions/<data>_<godzina>.jsonl`, jeden wiersz JSON na zdarzenie. Pisze tylko
## serwer (host widzi całą symulację), plik zostaje na jego dysku i nigdzie nie jest wysyłany. Tryb headless nie pisze
## (jak profil i zapis złomu), chyba że test poda katalog flagą `--sessionlog=KATALOG`.
##
## Zdarzenia (`ev`), każde z `t` = sekundy od startu misji:
##   mission_start  build, audio, map, kind, difficulty, mode, attempt, humans, bots, weather
##   phase          phase (OBJECTIVE / BOSS / EXTRACT / SUCCESS / FAILED)
##   down           who, bot, source (rodzaj wroga / stalker / vein / leech / acid / blast / prop), noise, weapon, pos, phase
##   revive         who, bot, after (s leżenia)
##   bleed_out      who, bot (wykrwawienie: powrót na start misji)
##   stalker        what (awake / asleep / swing_hit / swing_miss), noise, target, bot
##   overcharge     pos, noise, stale
##   pos            phase, noise, p: lista graczy [{who, bot, pos, hp, crouch, dead}] — próbka co POS_EVERY s (mapy cieplne tras, MAPS_PLAN.md P1)
##   objective      what (tag / stash / generator / nest / boss), n, of, pos, who, bot — zaliczony cel lub cel poboczny (czas odcinków trasy, P2)
##   mission_end    result (success / failed / wipe), time, downs, attempts, peak_noise, side, players, weapons, noise
## Wipe w kampanii kończy próbę wierszem mission_end, po którym idzie mission_start z kolejnym numerem próby.
## `weapons`: klucz broni → {shots, noise, dmg, kills}; `noise`: źródło → {n, sum} (strzały pod kluczem `shot`).

const DIR := "user://sessions"
const PHASES := ["OBJECTIVE", "BOSS", "EXTRACT", "SUCCESS", "FAILED"]
const POS_EVERY := 3.0                 ## s między próbkami pozycji graczy (zdarzenie `pos`): ok. 120 B na gracza, 10 min w duecie ≈ 50 KB

static var enabled := DisplayServer.get_name() != "headless"
static var dir := DIR                  ## katalog plików; testy podmieniają go flagą --sessionlog=
static var path := ""                  ## plik bieżącej sesji ("" = jeszcze nieotwarty)
static var _file: FileAccess
static var _open_failed := false
static var _in_mission := false
static var _t0 := 0                    ## ms zegara silnika w chwili startu misji
static var _noise := {}                ## źródło → [liczba zdarzeń, suma Uwagi]
static var _weapons := {}              ## klucz broni → {shots, noise, dmg, kills}
static var _dmg_by := {}               ## id gracza → {klucz broni → obrażenia}
static var _build := ""

static func active() -> bool:
	return enabled and not _open_failed and NoiseMgr.is_server()

## Czy zdarzenie zostałoby teraz zapisane — żeby nie składać wiersza (np. próbki pozycji) na próżno.
static func recording() -> bool:
	return active() and _in_mission

## Wersja buildu: `config/version` z project.godot + skrót commita. Eksport dostaje skrót z pliku `build_stamp.txt`
## (tools/export_build.sh), gra uruchomiona ze źródeł pyta gita. Ta sama wartość jest w stopce menu głównego.
static func build() -> String:
	if _build == "":
		var stamp := ""
		if FileAccess.file_exists("res://build_stamp.txt"):
			stamp = FileAccess.get_file_as_string("res://build_stamp.txt").strip_edges()
		elif OS.has_feature("editor"):
			var out: Array = []
			if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out) == 0 and not out.is_empty():
				stamp = String(out[0]).strip_edges()
		var v := String(ProjectSettings.get_setting("application/config/version", "dev"))
		_build = v if stamp == "" else "%s+%s" % [v, stamp]
	return _build

static func xy(v: Vector2) -> Array:
	return [roundi(v.x), roundi(v.y)]

static func _open() -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	path = "%s/%s.jsonl" % [dir, Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		_open_failed = true
		push_warning("Session log: cannot write %s" % path)
		return false
	print("[SESSION] log: %s" % ProjectSettings.globalize_path(path))
	return true

## Zdarzenie w trakcie misji. Poza misją (kryjówka, menu) nic nie zapisuje.
static func event(ev: String, data := {}) -> void:
	if not active() or not _in_mission:
		return
	_write(ev, data)

static func _write(ev: String, data: Dictionary) -> void:
	if _file == null and not _open():
		return
	var row := {"t": snappedf(float(Time.get_ticks_msec() - _t0) / 1000.0, 0.1), "ev": ev}
	row.merge(data)
	_file.store_line(JSON.stringify(row))
	_file.flush()                       # po każdym wierszu: zawieszenie gry nie zjada dziennika

static func mission_start(data: Dictionary) -> void:
	if not active():
		return
	var row := {"clock": Time.get_datetime_string_from_system(), "build": build()}      # build() pyta gita — przed startem zegara
	_in_mission = true
	_t0 = Time.get_ticks_msec()
	_noise = {}
	_weapons = {}
	_dmg_by = {}
	row.merge(data)
	_write("mission_start", row)

static func mission_end(data: Dictionary) -> void:
	if not active() or not _in_mission:
		return
	var noise := {}
	for k in _noise:
		noise[k] = {"n": int(_noise[k][0]), "sum": snappedf(float(_noise[k][1]), 0.1)}
	var weapons := {}
	for k in _weapons:
		var w: Dictionary = _weapons[k]
		weapons[k] = {"shots": int(w["shots"]), "noise": snappedf(float(w["noise"]), 0.1), "dmg": roundi(float(w["dmg"])), "kills": int(w["kills"])}
	var row := data.duplicate()
	row["weapons"] = weapons
	row["noise"] = noise
	var players: Dictionary = row.get("players", {})
	for id in _dmg_by:
		if players.has(id):
			var by := {}
			for k in _dmg_by[id]:
				by[k] = roundi(float(_dmg_by[id][k]))
			(players[id] as Dictionary)["dmg"] = by
	_write("mission_end", row)
	_in_mission = false

## Koniec misji bez wyniku (wyjście do kryjówki, zmiana mapy) — zdarzenia przestają się zapisywać.
static func leave_mission() -> void:
	_in_mission = false

# ---------------------------------------------------------------- liczniki do mission_end

static func _weapon(key: String) -> Dictionary:
	if not _weapons.has(key):
		_weapons[key] = {"shots": 0, "noise": 0.0, "dmg": 0.0, "kills": 0}
	return _weapons[key]

## Uwaga dodana przez źródło `tag` (noise_manager._apply). Strzały przychodzą jako "shot:<klucz broni>".
static func note_noise(tag: String, amount: float) -> void:
	if not active() or not _in_mission:
		return
	var src := tag if tag != "" else "world"
	if src.begins_with("shot:"):
		var w := _weapon(src.substr(5))
		w["shots"] = int(w["shots"]) + 1
		w["noise"] = float(w["noise"]) + amount
		src = "shot"
	if not _noise.has(src):
		_noise[src] = [0, 0.0]
	_noise[src][0] = int(_noise[src][0]) + 1
	_noise[src][1] = float(_noise[src][1]) + amount

## Obrażenia zadane bronią `key` przez gracza `shooter` (combat.apply, serwer).
static func note_damage(shooter: int, key: String, dealt: float, killed: bool) -> void:
	if not active() or not _in_mission or (dealt <= 0.0 and not killed):
		return
	var w := _weapon(key)
	w["dmg"] = float(w["dmg"]) + dealt
	if killed:
		w["kills"] = int(w["kills"]) + 1
	if not _dmg_by.has(shooter):
		_dmg_by[shooter] = {}
	_dmg_by[shooter][key] = float((_dmg_by[shooter] as Dictionary).get(key, 0.0)) + dealt

## Testy: stan jak po starcie gry (nowy plik przy następnym zdarzeniu).
static func reset_for_test() -> void:
	_file = null
	path = ""
	_open_failed = false
	_in_mission = false
	_noise = {}
	_weapons = {}
	_dmg_by = {}
