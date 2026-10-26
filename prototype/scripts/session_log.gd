extends RefCounted
## Dziennik sesji (REVIEW_PLAN.md R3): co się działo w misji, w liczbach — do playtestów (GDD §16.0, §23.3).
##
## Jeden plik na uruchomienie gry: `user://sessions/<data>_<godzina>.jsonl`, jeden wiersz JSON na zdarzenie. Pisze tylko
## serwer (host widzi całą symulację), plik zostaje na jego dysku i nigdzie nie jest wysyłany. Tryb headless nie pisze
## (jak profil i zapis złomu), chyba że test poda katalog flagą `--sessionlog=KATALOG`.
##
## Zdarzenia (`ev`), każde z `t` = sekundy od startu misji:
##   mission_start  build, audio, map, kind, difficulty, mode, attempt, humans, bots, weather, equipment (ludzie: who, kit, fits, mass, a od 1.7.391
##                  także xp, level, perks, look — profil właściciela replikowany przez player.prof_xp), workshop (stan zapisu hosta), hub_seconds
##   phase          phase (OBJECTIVE / BOSS / EXTRACT / SUCCESS / FAILED)
##   down           who, bot, source (rodzaj wroga / stalker / vein / leech / acid / blast / prop), noise, weapon, pos, phase
##   revive         who, bot, after (s leżenia)
##   bleed_out      who, bot (wykrwawienie: powrót na start misji)
##   stalker        what (awake / asleep / swing_hit / swing_miss / pass_in / pass_out — przechodzący Stalker 1.1), noise, target, bot, pos
##   overcharge     pos, noise, stale
##   pos            phase, noise, p: lista graczy [{who, bot, pos, hp, crouch, dead}] — próbka co POS_EVERY s (mapy cieplne tras, MAPS_PLAN.md P1)
##   objective      what (tag / stash / generator / nest / boss), n, of, pos, who, bot — zaliczony cel lub cel poboczny (czas odcinków trasy, P2)
##   mission_end    result (success / failed / wipe), time, downs, attempts, peak_noise, side, players, weapons, noise, scrap
##   xp             who, mission (XP za wynik misji), rows (etykiety bonusów), xp (łącznie w profilu po misji), level — po udanej misji,
##                  raport właściciela profilu (u klienta przez RPC do hosta); pisany po mission_end (PROGRESSION_PLAN.md P0.1)
##   hub_buy        clock, who, kind (weapon / part / supply / order / research / machining / service), id, cost, ok, reason, bank (po operacji)
##                  — rozstrzygnięta operacja warsztatu na serwerze, także w kryjówce, poza misją (P0.4); bez odmów „station” i „repeat”
##   system         gpu, gpu_vendor, cpu, threads, ram_gb, os, screen, window, fullscreen, quality, render_scale, vsync, fps_cap — raz na plik, przy jego otwarciu
##   perf           map, fps, avg, p50, p95, max (ms klatki), spikes (klatki > PERF_SPIKE_MS), gpu (ms GPU viewportów widoku 3D), up (s od startu gry)
##                  — próbka co PERF_EVERY s, także w kryjówce i u klienta (od 1.7.367): klient pisze własny plik z samymi wierszami system i perf,
##                  bo wydajność jest jego sprzętu, a reszta dziennika to symulacja hosta
## Wipe w kampanii kończy próbę wierszem mission_end, po którym idzie mission_start z kolejnym numerem próby.
## `weapons`: klucz broni → {shots, noise, dmg, kills}; `noise`: źródło → {n, sum} (strzały pod kluczem `shot`).
## `players[id]` (od 1.7.391): oprócz name, kills, downs, revived, dmg także `kinds` (rodzaj wroga → zabójstwa) i `xp_kills` (XP za te zabójstwa) — P0.1, P0.3.
## `scrap` (od 1.7.347, strojenie ekonomii warsztatu): {dropped — złom, który wypadł z wrogów i bossa w tej próbie, loot — zebrany łup,
## bonus — premia za misję (0 przy wipe)}; do banku trafia loot + bonus, tylko przy sukcesie.

const DIR := "user://sessions"
const PHASES := ["OBJECTIVE", "BOSS", "EXTRACT", "SUCCESS", "FAILED"]
const POS_EVERY := 3.0                 ## s między próbkami pozycji graczy (zdarzenie `pos`): ok. 120 B na gracza, 10 min w duecie ≈ 50 KB
const PERF_EVERY := 10.0               ## s między próbkami wydajności (zdarzenie `perf`): ok. 130 B, godzina gry ≈ 47 KB
const PERF_SPIKE_MS := 50.0            ## klatka dłuższa niż tyle ms to przestój (zacięcie widoczne przy 60 kl./s)

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
static var _scrap_drop := 0            ## złom wyrzucony przez wrogów i bossa w tej próbie (podniesiony czy nie)
static var _kills_by := {}             ## id gracza → {rodzaj wroga → zabójstwa} (tylko zabójstwa dające XP: ludzie)
static var _xp_by := {}                ## id gracza → XP za zabójstwa w tej próbie
static var _build := ""
static var _ft := PackedFloat32Array()  ## ms klatek od ostatniej próbki `perf`
static var _gpu := 0.0                 ## suma ms GPU obserwowanych viewportów od ostatniej próbki
static var _perf_t := 0.0
static var _frame_us := 0              ## Time.get_ticks_usec() poprzedniej klatki (frame): czas klatki z zegara, nie z `delta`
static var _gpu_vps: Array = []        ## viewporty widoku 3D z pomiarem czasu GPU (watch_viewports)

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
	var mem := OS.get_memory_info()
	var row := {"t": 0.0, "ev": "system", "build": build(), "gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"cpu": OS.get_processor_name(), "threads": OS.get_processor_count(), "ram_gb": snappedf(float(mem.get("physical", 0)) / 1073741824.0, 0.1),
		"os": OS.get_name(), "screen": xy(Vector2(DisplayServer.screen_get_size())), "window": xy(Vector2(DisplayServer.window_get_size())),
		"fullscreen": Settings.fullscreen, "quality": Settings.QUALITY_NAMES[Settings.quality_idx], "render_scale": Settings.render_scale(), "vsync": Settings.VSYNC_NAMES[Settings.vsync_idx],
		"fps_cap": Settings.FPS_LIST[Settings.fps_idx]}
	_file.store_line(JSON.stringify(row))
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
	_scrap_drop = 0
	_kills_by = {}
	_xp_by = {}
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
	for id in _kills_by:
		if players.has(id):
			(players[id] as Dictionary)["kinds"] = (_kills_by[id] as Dictionary).duplicate()
			(players[id] as Dictionary)["xp_kills"] = int(_xp_by.get(id, 0))
	var scrap: Dictionary = row.get("scrap", {})
	scrap["dropped"] = _scrap_drop
	row["scrap"] = scrap
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

## Zabójstwo wroga `kind` przez człowieka `shooter` za `xp` XP (Profile.server_award_kill, serwer).
static func note_kill(shooter: int, kind: String, xp: int) -> void:
	if not active() or not _in_mission:
		return
	if not _kills_by.has(shooter):
		_kills_by[shooter] = {}
	_kills_by[shooter][kind] = int((_kills_by[shooter] as Dictionary).get(kind, 0)) + 1
	_xp_by[shooter] = int(_xp_by.get(shooter, 0)) + xp

## Zdarzenie spoza próby misji (zakupy w kryjówce, raport XP po mission_end): pisze, gdy dziennik jest aktywny, z zegarem ściennym.
static func note(ev: String, data := {}) -> void:
	if not active():
		return
	var row := {"clock": Time.get_datetime_string_from_system()}
	row.merge(data)
	_write(ev, row)

## Złom `n`, który wypadł z wroga albo bossa (enemy.gd, boss_base.gd; serwer).
static func note_scrap_drop(n: int) -> void:
	if not active() or not _in_mission or n <= 0:
		return
	_scrap_drop += n

# ---------------------------------------------------------------- wydajność (host i klient)

## Viewporty, których czas GPU trafia do próbek `perf` (view3d.setup: świat i warstwa graczy); zastępuje poprzednią listę.
static func watch_viewports(vps: Array) -> void:
	_gpu_vps = vps
	for v in vps:
		RenderingServer.viewport_set_measure_render_time((v as Viewport).get_viewport_rid(), true)

## Co klatkę obrazu (view3d._process): czas klatki do próbki `perf`, zapis co PERF_EVERY s. Pisze każdy peer do własnego pliku.
static func frame(delta: float, map_id: String) -> void:
	if not enabled or _open_failed:
		return
	# `delta` silnik przycina do max_physics_steps_per_frame (8 kroków fizyki ≈ 133 ms przy 60 Hz), więc przestój 0,5 s zapisywał się jako
	# ok. 133–150 ms (dziennik do 1.7.389). Przy przyciętej delcie liczy zegar od poprzedniej klatki; krótsza delta jest dokładna, a zegar
	# po pauzie (węzeł nie dostawał klatek) dałby fałszywy przestój.
	var now := Time.get_ticks_usec()
	var ms := delta * 1000.0
	if ms >= 120.0 and _frame_us != 0:
		ms = maxf(ms, float(now - _frame_us) / 1000.0)
	_frame_us = now
	_ft.append(ms)
	if ms > PERF_SPIKE_MS and OS.is_stdout_verbose():
		print("[SPIKE-MARK] %.0f ms (%s)" % [ms, map_id])       # z --verbose: wiersze tuż nad znacznikiem mówią, co się wczytywało w tej klatce
	for v in _gpu_vps:
		if is_instance_valid(v):
			_gpu += RenderingServer.viewport_get_measured_render_time_gpu((v as Viewport).get_viewport_rid())
	_perf_t += ms / 1000.0
	if _perf_t < PERF_EVERY:
		return
	var n := _ft.size()
	var s := _ft.duplicate()
	s.sort()
	var sum := 0.0
	var spikes := 0
	for t in s:
		sum += t
		if t > PERF_SPIKE_MS:
			spikes += 1
	var row := {"map": map_id, "fps": roundi(float(n) / _perf_t), "avg": snappedf(sum / float(n), 0.01), "p50": snappedf(s[n / 2], 0.01),
		"p95": snappedf(s[mini(n - 1, int(float(n) * 0.95))], 0.01), "max": snappedf(s[n - 1], 0.1), "spikes": spikes,
		"gpu": snappedf(_gpu / float(n), 0.01), "up": snappedf(float(Time.get_ticks_msec()) / 1000.0, 1.0)}
	_ft.clear()
	_gpu = 0.0
	_perf_t = 0.0
	_write("perf", row)

## Testy: stan jak po starcie gry (nowy plik przy następnym zdarzeniu).
static func reset_for_test() -> void:
	_file = null
	path = ""
	_open_failed = false
	_in_mission = false
	_noise = {}
	_weapons = {}
	_dmg_by = {}
