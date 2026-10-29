extends Node
## Ustawienia gracza (autoload „Settings"): głośność, wstrząsy kamery, rozmiar HUD, podpowiedzi,
## pełny ekran. Zapis w user://settings.cfg (sekcja „game"; sekcję „voice" prowadzi voice.gd — rzeczy gracza (porady, rekordy) od 1.7.426
## w player.cfg aktywnej postaci, characters.gd;
## oba moduły wczytują plik przed zapisem, więc sobie nie przeszkadzają).
##
## Dodatkowo `block_game_input()` wycina akcje gry z InputMap na czas menu pauzy (lista: `Actions.blockable()`):
## wszystkie skrypty czytają je przez Input.is_action_*, więc jedno miejsce wystarcza (żeby klik w menu nie strzelał).

signal changed
signal bindings_changed             ## gracz przypisał / zresetował klawisze (ściągi i podpowiedzi się odświeżają)

const SAVE_PATH := "user://settings.cfg"
const PLAYER_FILE := "player.cfg"
const STEP := 0.1
## Wersja demo: ekran końcowy misji zachęca do dodania gry do listy życzeń. STORE_URL uzupełnić, gdy strona
## sklepu Steam będzie publiczna (puste = bez przycisku [O]).
const DEMO := true
const STORE_URL := ""
## Rodzaj głośności → szyny z default_bus_layout.tres. „Mic" (voice.gd) celowo poza listą.
const VOLUME_BUSES := {"master": ["Master"], "music": ["Music"], "ambience": ["Ambience"], "sfx": ["SFX", "UI"]}
const SHAKE_NAMES := ["FULL", "HALF", "OFF"]
## Efekty pogody (weather_fx.gd): FULL — pełny błysk błyskawic; REDUCED — miękka poświata zamiast błysku i mniej cząsteczek (fotowrażliwość); OFF — bez efektów.
const WEATHER_FX_NAMES := ["FULL", "REDUCED", "OFF"]
const WEATHER_FX_FULL := 0
const WEATHER_FX_REDUCED := 1
const WEATHER_FX_OFF := 2
const SHAKE_MULT := [1.0, 0.5, 0.0]
## Okno i obraz (bez restartu): rozmiar okna w trybie okienkowym, synchronizacja pionowa, limit klatek, jakość efektów.
const RES_LIST := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const VSYNC_NAMES := ["ON", "OFF", "ADAPTIVE"]
const VSYNC_MODES := [DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ADAPTIVE]
const FPS_LIST := [0, 30, 60, 120, 144, 240]                       ## 0 = bez limitu
## Widok z oczu (strzelnica FPP, scripts/range3d/): kąt widzenia w pionie (°) i mnożnik czułości myszy i drążka.
const FP_FOV_LIST := [60, 65, 70, 74, 80, 85, 90, 100]
const FP_FOV_DEFAULT := 3                                          ## 74° — tunel jak w szpicu (RANGE_FPS_PLAN.md §7)
const FP_SENS_LIST := [0.4, 0.6, 0.8, 1.0, 1.25, 1.5, 2.0, 2.5]
const FP_SENS_DEFAULT := 3
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]
## Skala renderu świata 3D (tylko viewport świata; postacie i interfejs jej nie podlegają). Poniżej 100% skaluje AMD FSR 1 —
## w 4K 75% to ok. −3 ms GPU (--perfreport 2026-10-23, RTX 3080); dla słabszych kart największa dźwignia wydajności. Mnoży się ze skalą
## z „Effects quality” (View3D._res_scale: LOW 50%, MEDIUM 75% rozdzielczości okna dla świata i postaci).
const RENDER_SCALE_LIST := [1.0, 0.85, 0.75, 0.67, 0.5]
const VFX_MULT := [0.4, 0.7, 1.0]                                  ## ile cząsteczek i szczątków (Vfx.burst / gibs)
const POST_MULT := [0.0, 0.6, 1.0]                                 ## siła aberracji (horror_fx.gd)
## Tryb dla osób z zaburzeniami widzenia barw: filtr całego obrazu (colorblind_fx.gd).
const COLORBLIND_NAMES := ["OFF", "PROTANOPIA", "DEUTERANOPIA", "TRITANOPIA"]
## Język interfejsu: tabela tłumaczeń w translations/ui.csv (klucz = tekst angielski). Nazwy języków nie są tłumaczone.
const LOCALES := ["en", "pl"]
const LOCALE_NAMES := ["ENGLISH", "POLSKI"]
const CAM_NAMES := ["WIDE", "NORMAL", "CLOSE"]
const CAM_ZOOM := [1.6, 2.0, 2.4]      ## zoom kamery gracza; baza 640×360 → widać 400×225 / 320×180 / 267×150 j. świata
const UI_NAMES := ["SMALL", "NORMAL", "LARGE"]
## Rozmiar HUD-u: SMALL / NORMAL / LARGE. NORMAL = dawne SMALL (0,85), LARGE = dawne NORMAL (1,0); nowy SMALL jest o tyle samo mniejszy (×0,85).
const UI_MULT := [0.72, 0.85, 1.0]
## Jasność obrazu świata: ekspozycja przed tonemappingiem w EV (krokach przysłony), w wąskim zakresie ±1 EV — tyle wystarcza na monitor
## z „zjedzoną” albo podniesioną czernią, a nie pozwala rozjaśnić nocy (GDD §8.3: ciemność jest mechaniką). Ustawia ją ekran kalibracji
## (brightness_screen.gd) albo wiersz „Brightness” w menu.
const BRIGHTNESS_EV := [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]
const BRIGHTNESS_DEFAULT := 4
const Actions := preload("res://scripts/actions.gd")

var volume := {"master": 1.0, "music": 1.0, "ambience": 1.0, "sfx": 1.0}
var shake_idx := 0
var weather_fx_idx := WEATHER_FX_REDUCED
var ui_idx := 1
var cam_idx := 1                       ## zbliżenie kamery: WIDE / NORMAL / CLOSE (CAM_ZOOM) — większe postacie kosztem pola widzenia
var hints_on := true
## AI towarzysz (NOBOT_PLAN.md): host może grać bez bota — sam (upadek = wykrwawienie i powrót na start, druga śmierć w próbie = wipe)
## albo w dwie osoby. Decyduje host; zmiana tylko w lobby i w kryjówce (`Main.companion_editable`). Dev: `--nobot` (bez zapisu).
var ai_companion := true
var res_idx := 0                       ## rozmiar okna z RES_LIST (tylko tryb okienkowy)
var vsync_idx := 0
var fps_idx := 0
var fp_fov_idx := FP_FOV_DEFAULT       ## widok z oczu: indeks FP_FOV_LIST
var fp_sens_idx := FP_SENS_DEFAULT     ## widok z oczu: indeks FP_SENS_LIST
var fp_brace_toggle := false          ## osobny tryb oparcia na strzelnicy: HOLD domyślnie, TOGGLE opcjonalnie
var fp_invert_y := false               ## widok z oczu: ruch myszy / drążka w górę pochyla w dół
var quality_idx := 2                   ## LOW / MEDIUM / HIGH — cząsteczki, aberracja, efekty pogody
var render_scale_idx := 0              ## indeks RENDER_SCALE_LIST (0 = 100%)
var mono_audio := false                ## bez panoramy w dźwięku pozycyjnym (osoby z jednostronnym słuchem)
var captions := false                  ## napisy dla dźwięków (HUD, captions.gd)
var reduce_fx := false                 ## „Reduce Effects": bez wstrząsów, aberracji, pulsu zdrowia, błysku burzy i migotania
var crouch_toggle := false             ## skradanie przełączane klawiszem zamiast trzymania
## Niezawodność broni (GUNSMITH_PLAN §6): OFF — bez zużycia i zacięć, STANDARD, VETERAN — zużycie i szansa zacięcia ×2.
const RELIABILITY_NAMES := ["OFF", "STANDARD", "VETERAN"]
const RELIABILITY_MULT := [0.0, 1.0, 2.0]
## Nowy gracz (bez zapisu ustawień) gra rdzeń bez nauki warsztatu (GDD §16.0a): zacięcia OFF i obsługa CLASSIC. Do 1.7.397 domyślnie
## STANDARD i REALISTIC; zapisany wybór gracza zostaje bez zmian.
const RELIABILITY_DEFAULT := 0
const REALISTIC_DEFAULT := false
var reliability_idx := RELIABILITY_DEFAULT
var realistic_handling := REALISTIC_DEFAULT  ## obsługa broni: podrzut przy myszy, oparcie o krawędź, gorąca lufa i dwa przeładowania (REALISTIC) albo dawne zachowanie (CLASSIC) — GUNSMITH_PLAN etap 3
var colorblind_idx := 0
var locale_idx := 0
var brightness_idx := BRIGHTNESS_DEFAULT
var brightness_calibrated := false     ## gracz przeszedł już ekran kalibracji (inaczej menu główne pokazuje go przy pierwszym starcie)
var _res_dirty := false                ## gracz zmienił rozmiar okna (inaczej zostaje domyślny z projektu)
var dev_nohud: bool = "--nohud" in OS.get_cmdline_user_args()   ## dev: ukrywa HUD, celownik i plakietki graczy (nagrania i zrzuty do materiałów promocyjnych)
var fullscreen := false
var seen_tips: Array = []              ## identyfikatory podpowiedzi, które gracz już widział
var shift_best_cleared := 0            ## Nocny Dyżur: najwięcej ukończonych misji w jednej serii (rekord lokalny)
var shift_best_time := 0.0             ## Nocny Dyżur: najkrótszy czas pełnej serii w s (0 = jeszcze nikt nie ukończył)
var range_board: Array = []            ## strzelnica FPP: tablica drużyny [{who, t, w}, …] rosnąco po czasie; trzyma ją host (range_door.gd)

var _base_db := {}                     ## szyna → głośność z układu szyn (bez ustawień gracza)
var _stash := {}                       ## akcja → zdarzenia schowane na czas menu
var blocked := false

func _ready() -> void:
	for kind in VOLUME_BUSES:
		for b in VOLUME_BUSES[kind]:
			var i := AudioServer.get_bus_index(b)
			if i >= 0:
				_base_db[b] = AudioServer.get_bus_volume_db(i)
	_load()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--brightness="):                 # dev: jasność bez zapisu (indeks BRIGHTNESS_EV, 4 = 0 EV) — zrzuty porównawcze
			brightness_idx = clampi(int(a.substr("--brightness=".length())), 0, BRIGHTNESS_EV.size() - 1)
	_apply_all()

func _exit_tree() -> void:
	block_game_input(false)

# ---------------------------------------------------------------- wartości

func shake_mult() -> float:
	return SHAKE_MULT[shake_idx] * fx_mult()

## 0 przy „Reduce Effects", inaczej 1: mnożnik wszystkiego, co drży, błyska albo pulsuje.
func fx_mult() -> float:
	return 0.0 if reduce_fx else 1.0

func vfx_mult() -> float:
	return VFX_MULT[quality_idx]

## Siła obrazu horroru (aberracja): zależy od jakości, a „Reduce Effects" wyłącza ją całkiem.
func post_mult() -> float:
	return POST_MULT[quality_idx] * fx_mult()

## Efekty pogody po uwzględnieniu jakości i „Reduce Effects": pełny błysk zamienia się w miękką poświatę.
func weather_fx_effective() -> int:
	if weather_fx_idx == WEATHER_FX_FULL and (reduce_fx or quality_idx == 0):
		return WEATHER_FX_REDUCED
	return weather_fx_idx

## Mnożnik ekspozycji obrazu świata (Environment.tonemap_exposure) z ustawienia jasności.
func exposure_mult() -> float:
	return pow(2.0, float(BRIGHTNESS_EV[brightness_idx]))

func brightness_ev() -> float:
	return float(BRIGHTNESS_EV[brightness_idx])

func set_brightness(i: int) -> void:
	brightness_idx = clampi(i, 0, BRIGHTNESS_EV.size() - 1)
	_commit()

func mark_brightness_calibrated() -> void:
	brightness_calibrated = true
	_commit()

func ui_mult() -> float:
	return UI_MULT[ui_idx]

## Rozmiar względem NORMAL (1,0 = domyślny): menu (pauza, lobby) skalują się tym, żeby domyślny wygląd się nie zmniejszył.
func ui_rel() -> float:
	return UI_MULT[ui_idx] / UI_MULT[1]

func set_volume(kind: String, v: float) -> void:
	volume[kind] = snappedf(clampf(v, 0.0, 1.0), STEP)
	_apply_volume(kind)
	_commit()

func cycle_shake() -> void:
	shake_idx = (shake_idx + 1) % SHAKE_NAMES.size()
	_commit()

func cycle_weather_fx() -> void:
	weather_fx_idx = (weather_fx_idx + 1) % WEATHER_FX_NAMES.size()
	_commit()

func cam_zoom() -> float:
	return CAM_ZOOM[cam_idx]

func cycle_cam() -> void:
	cam_idx = (cam_idx + 1) % CAM_NAMES.size()
	_commit()

func cycle_ui() -> void:
	ui_idx = (ui_idx + 1) % UI_NAMES.size()
	_commit()

## Zapis po zmianie przypisań klawiszy (woła `Actions.set_binding` / `reset_defaults`).
func save_bindings() -> void:
	_save()
	bindings_changed.emit()

func cycle_res() -> void:
	res_idx = (res_idx + 1) % RES_LIST.size()
	_res_dirty = true
	_apply_window()
	_commit()

func cycle_vsync() -> void:
	vsync_idx = (vsync_idx + 1) % VSYNC_NAMES.size()
	_apply_window()
	_commit()

func cycle_fps() -> void:
	fps_idx = (fps_idx + 1) % FPS_LIST.size()
	_apply_window()
	_commit()

## Widok z oczu: kąt widzenia w pionie (°).
func fp_fov() -> float:
	return float(FP_FOV_LIST[fp_fov_idx])

## Widok z oczu: mnożnik czułości (mysz i drążek).
func fp_sens() -> float:
	return float(FP_SENS_LIST[fp_sens_idx])

func cycle_fp_fov() -> void:
	fp_fov_idx = (fp_fov_idx + 1) % FP_FOV_LIST.size()
	_commit()

func cycle_fp_sens() -> void:
	fp_sens_idx = (fp_sens_idx + 1) % FP_SENS_LIST.size()
	_commit()

func toggle_fp_brace() -> void:
	fp_brace_toggle = not fp_brace_toggle
	_commit()

func toggle_fp_invert_y() -> void:
	fp_invert_y = not fp_invert_y
	_commit()

func cycle_quality() -> void:
	quality_idx = (quality_idx + 1) % QUALITY_NAMES.size()
	_commit()

func cycle_render_scale() -> void:
	render_scale_idx = (render_scale_idx + 1) % RENDER_SCALE_LIST.size()
	_commit()

func render_scale() -> float:
	return float(RENDER_SCALE_LIST[clampi(render_scale_idx, 0, RENDER_SCALE_LIST.size() - 1)])

func toggle_mono_audio() -> void:
	mono_audio = not mono_audio
	_commit()

func toggle_captions() -> void:
	captions = not captions
	_commit()

## Obraz gry jest zawsze w 3D (view3d.gd); wyjątkiem jest tryb headless (testy), który nic nie rysuje.
func view3d_active() -> bool:
	return DisplayServer.get_name() != "headless"

func toggle_reduce_fx() -> void:
	reduce_fx = not reduce_fx
	_commit()

func toggle_crouch_mode() -> void:
	crouch_toggle = not crouch_toggle
	_commit()

func reliability_mult() -> float:
	return float(RELIABILITY_MULT[clampi(reliability_idx, 0, RELIABILITY_MULT.size() - 1)])

func set_reliability(i: int) -> void:
	reliability_idx = clampi(i, 0, RELIABILITY_NAMES.size() - 1)
	_commit()

func toggle_realistic_handling() -> void:
	realistic_handling = not realistic_handling
	_commit()

func cycle_locale() -> void:
	locale_idx = (locale_idx + 1) % LOCALES.size()
	TranslationServer.set_locale(LOCALES[locale_idx])
	_commit()

func cycle_colorblind() -> void:
	colorblind_idx = (colorblind_idx + 1) % COLORBLIND_NAMES.size()
	_commit()

func toggle_hints() -> void:
	hints_on = not hints_on
	_commit()

func set_ai_companion(on: bool) -> void:
	if on == ai_companion:
		return
	ai_companion = on
	_commit()

## Zasoby HD (modele, tekstury) są używane zawsze poza trybem headless — testy liczą wariant bez grafiki.
func hd_active() -> bool:
	return DisplayServer.get_name() != "headless"

func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	_apply_window()
	_commit()

func tip_seen(id: String) -> bool:
	return seen_tips.has(id)

func mark_tip(id: String) -> void:
	if not seen_tips.has(id):
		seen_tips.append(id)
		_save()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()

# ---------------------------------------------------------------- zastosowanie

func _apply_all() -> void:
	var loc: String = LOCALES[locale_idx]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			loc = a.substr("--lang=".length())             # dev: język bez zapisu (zrzuty, testy)
	TranslationServer.set_locale(loc)
	for kind in VOLUME_BUSES:
		_apply_volume(kind)
	_apply_window()

func _apply_volume(kind: String) -> void:
	var v: float = volume[kind]
	for b in VOLUME_BUSES[kind]:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, float(_base_db.get(b, 0.0)) + linear_to_db(maxf(v, 0.001)))

func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not fullscreen and _res_dirty:
		var sz: Vector2i = RES_LIST[res_idx]
		DisplayServer.window_set_size(sz)
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen.position + (screen.size - sz) / 2)
	DisplayServer.window_set_vsync_mode(VSYNC_MODES[vsync_idx])
	Engine.max_fps = FPS_LIST[fps_idx]

func _commit() -> void:
	_save()
	changed.emit()

# ---------------------------------------------------------------- blokada wejścia (menu pauzy)

func block_game_input(on: bool) -> void:
	if on == blocked:
		return
	blocked = on
	if on:
		for a in Actions.blockable():           # wszystkie akcje poza oznaczonymi „menu" (pause, F2, F11)
			if InputMap.has_action(a):
				_stash[a] = InputMap.action_get_events(a)
				InputMap.action_erase_events(a)
				Input.action_release(a)       # trzymany klawisz nie zostaje „wciśnięty" po wycięciu zdarzeń
	else:
		for a in _stash:
			for e in _stash[a]:
				InputMap.action_add_event(a, e)
		_stash.clear()

# ---------------------------------------------------------------- Nocny Dyżur: rekord

## Zapisuje wynik serii (host). Rekord = więcej ukończonych misji albo, przy pełnej serii, krótszy czas.
## Zwraca true, gdy wynik jest nowym rekordem.
func record_shift(cleared: int, secs: float, completed: bool) -> bool:
	var better := cleared > shift_best_cleared
	if completed and (shift_best_time <= 0.0 or secs < shift_best_time):
		shift_best_time = secs
		better = true
	if cleared > shift_best_cleared:
		shift_best_cleared = cleared
	if better:
		_save()
	return better

## Zapis tablicy strzelnicy (host, range_door.gd). Testy bez okna nie nadpisują prawdziwych ustawień gracza.
func save_range_board(board: Array) -> void:
	range_board = board.duplicate(true)
	if DisplayServer.get_name() == "headless":
		return
	_save()

# ---------------------------------------------------------------- zapis

## Język przy pierwszym starcie (brak zapisu ustawień): język systemu, jeśli gra go ma (`pl_PL` → POLSKI), inaczej angielski.
## Wcześniej gra zawsze startowała po angielsku, a testerzy dostają instrukcję po polsku.
static func system_locale_idx(os_lang: String) -> int:
	return maxi(LOCALES.find(os_lang.substr(0, 2).to_lower()), 0)

## Grafika przy pierwszym starcie (brak zapisu ustawień): na zintegrowanej karcie (laptop) MEDIUM i 75% rozdzielczości świata zamiast
## HIGH i 100% — pierwsze minuty playtestu nie mogą iść w kilku klatkach na sekundę (pomiaru na słabszym sprzęcie wciąż nie ma,
## REVIEW_PLAN R7). Zwraca [quality_idx, render_scale_idx]; zapis gracza ma pierwszeństwo.
static func first_run_graphics(adapter: int) -> Array:
	if adapter == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return [1, RENDER_SCALE_LIST.find(0.75)]
	return [2, 0]

func _load() -> void:
	_load_global()
	_load_player()

## Rzeczy gracza (PROFILES_PLAN.md D5): obejrzane porady, rekord Nocnego Dyżuru i tablica strzelnicy żyją w `player.cfg` aktywnej postaci
## (Characters.file), nie w ustawieniach komputera. Bez postaci (headless) — tylko w pamięci.
func _load_player() -> void:
	var path := Characters.file(PLAYER_FILE)
	var cf := ConfigFile.new()
	if path == "" or cf.load(path) != OK:
		return
	seen_tips = Array(cf.get_value("game", "seen_tips", []))
	shift_best_cleared = int(cf.get_value("shift", "best_cleared", 0))
	shift_best_time = float(cf.get_value("shift", "best_time", 0.0))
	var rb = cf.get_value("range", "board", [])
	range_board = rb if rb is Array else []

func _save_player() -> void:
	var path := Characters.file(PLAYER_FILE)
	if path == "":
		return
	var cf := ConfigFile.new()
	cf.load(path)                       # trudność (difficulty.gd) leży w tym samym pliku
	cf.set_value("game", "seen_tips", seen_tips)
	cf.set_value("shift", "best_cleared", shift_best_cleared)
	cf.set_value("shift", "best_time", shift_best_time)
	cf.set_value("range", "board", range_board)
	cf.save(path)

func _load_global() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		locale_idx = system_locale_idx(OS.get_locale_language())
		var gfx := first_run_graphics(RenderingServer.get_video_adapter_type())
		quality_idx = int(gfx[0])
		render_scale_idx = int(gfx[1])
		return
	for kind in volume:
		# otoczenie miało kiedyś wspólny suwak z muzyką: zapis sprzed rozdzielenia daje mu tę samą wartość
		var fallback: float = float(cf.get_value("game", "vol_music", 1.0)) if kind == "ambience" else 1.0
		volume[kind] = clampf(float(cf.get_value("game", "vol_" + kind, fallback)), 0.0, 1.0)
	shake_idx = clampi(int(cf.get_value("game", "shake", 0)), 0, SHAKE_NAMES.size() - 1)
	weather_fx_idx = clampi(int(cf.get_value("game", "weather_fx", WEATHER_FX_REDUCED)), 0, WEATHER_FX_NAMES.size() - 1)
	ui_idx = clampi(int(cf.get_value("game", "ui", 1)), 0, UI_NAMES.size() - 1)
	cam_idx = clampi(int(cf.get_value("game", "cam", 1)), 0, CAM_NAMES.size() - 1)
	hints_on = bool(cf.get_value("game", "hints", true))
	ai_companion = bool(cf.get_value("game", "ai_companion", true))
	fullscreen = bool(cf.get_value("game", "fullscreen", false))
	res_idx = clampi(int(cf.get_value("game", "res", 0)), 0, RES_LIST.size() - 1)
	_res_dirty = cf.has_section_key("game", "res")
	vsync_idx = clampi(int(cf.get_value("game", "vsync", 0)), 0, VSYNC_NAMES.size() - 1)
	fps_idx = clampi(int(cf.get_value("game", "fps", 0)), 0, FPS_LIST.size() - 1)
	fp_fov_idx = clampi(int(cf.get_value("fp", "fov", FP_FOV_DEFAULT)), 0, FP_FOV_LIST.size() - 1)
	fp_sens_idx = clampi(int(cf.get_value("fp", "sens", FP_SENS_DEFAULT)), 0, FP_SENS_LIST.size() - 1)
	fp_brace_toggle = bool(cf.get_value("fp", "brace_toggle", false))
	fp_invert_y = bool(cf.get_value("fp", "invert_y", false))
	quality_idx = clampi(int(cf.get_value("game", "quality", 2)), 0, QUALITY_NAMES.size() - 1)
	render_scale_idx = clampi(int(cf.get_value("game", "render_scale", 0)), 0, RENDER_SCALE_LIST.size() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--renderscale="):                 # dev: skala renderu w procentach (pomiar --perf), bez zmiany zapisu, dopóki gracz nie zmieni ustawień
			var want := float(a.substr("--renderscale=".length())) / 100.0
			for i in RENDER_SCALE_LIST.size():
				if absf(float(RENDER_SCALE_LIST[i]) - want) < absf(float(RENDER_SCALE_LIST[render_scale_idx]) - want):
					render_scale_idx = i
	reduce_fx = bool(cf.get_value("game", "reduce_fx", false))
	captions = bool(cf.get_value("game", "captions", false))
	mono_audio = bool(cf.get_value("game", "mono_audio", false))
	crouch_toggle = bool(cf.get_value("game", "crouch_toggle", false))
	realistic_handling = bool(cf.get_value("game", "realistic_handling", REALISTIC_DEFAULT))
	reliability_idx = clampi(int(cf.get_value("game", "reliability", RELIABILITY_DEFAULT)), 0, RELIABILITY_NAMES.size() - 1)
	colorblind_idx = clampi(int(cf.get_value("game", "colorblind", 0)), 0, COLORBLIND_NAMES.size() - 1)
	locale_idx = clampi(int(cf.get_value("game", "locale", system_locale_idx(OS.get_locale_language()))), 0, LOCALES.size() - 1)
	brightness_idx = clampi(int(cf.get_value("game", "brightness", BRIGHTNESS_DEFAULT)), 0, BRIGHTNESS_EV.size() - 1)
	brightness_calibrated = bool(cf.get_value("game", "brightness_calibrated", false))
	Actions.load_from(cf)

func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for kind in volume:
		cf.set_value("game", "vol_" + kind, volume[kind])
	cf.set_value("game", "shake", shake_idx)
	cf.set_value("game", "weather_fx", weather_fx_idx)
	cf.set_value("game", "ui", ui_idx)
	cf.set_value("game", "cam", cam_idx)
	cf.set_value("game", "hints", hints_on)
	cf.set_value("game", "ai_companion", ai_companion)
	cf.set_value("game", "fullscreen", fullscreen)
	if _res_dirty:
		cf.set_value("game", "res", res_idx)
	cf.set_value("game", "vsync", vsync_idx)
	cf.set_value("game", "fps", fps_idx)
	cf.set_value("fp", "fov", fp_fov_idx)
	cf.set_value("fp", "sens", fp_sens_idx)
	cf.set_value("fp", "brace_toggle", fp_brace_toggle)
	cf.set_value("fp", "invert_y", fp_invert_y)
	cf.set_value("game", "quality", quality_idx)
	cf.set_value("game", "render_scale", render_scale_idx)
	cf.set_value("game", "reduce_fx", reduce_fx)
	cf.set_value("game", "captions", captions)
	cf.set_value("game", "mono_audio", mono_audio)
	cf.set_value("game", "crouch_toggle", crouch_toggle)
	cf.set_value("game", "realistic_handling", realistic_handling)
	cf.set_value("game", "reliability", reliability_idx)
	cf.set_value("game", "colorblind", colorblind_idx)
	cf.set_value("game", "brightness", brightness_idx)
	cf.set_value("game", "brightness_calibrated", brightness_calibrated)
	cf.set_value("game", "locale", locale_idx)
	Actions.save_to(cf)
	# zapis sprzed postaci: po migracji (characters.gd) klucze gracza są już w player.cfg; headless nie migruje, więc nie może ich też skasować
	if Characters.active_id != "":
		for k in Characters.PLAYER_KEYS:
			if cf.has_section_key(k[0], k[1]):
				cf.erase_section_key(k[0], k[1])
	cf.save(SAVE_PATH)
	_save_player()
