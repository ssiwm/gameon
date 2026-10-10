extends Node
## Ustawienia gracza (autoload „Settings"): głośność, wstrząsy kamery, rozmiar HUD, podpowiedzi,
## pełny ekran. Zapis w user://settings.cfg (sekcja „game"; sekcję „voice" prowadzi voice.gd —
## oba moduły wczytują plik przed zapisem, więc sobie nie przeszkadzają).
##
## Dodatkowo `block_game_input()` wycina akcje gry z InputMap na czas menu pauzy (lista: `Actions.blockable()`):
## wszystkie skrypty czytają je przez Input.is_action_*, więc jedno miejsce wystarcza (żeby klik w menu nie strzelał).

signal changed
signal bindings_changed             ## gracz przypisał / zresetował klawisze (ściągi i podpowiedzi się odświeżają)

const SAVE_PATH := "user://settings.cfg"
const STEP := 0.1
## Wersja demo: ekran końcowy misji zachęca do dodania gry do listy życzeń. STORE_URL uzupełnić, gdy strona
## sklepu Steam będzie publiczna (puste = bez przycisku [O]).
const DEMO := true
const STORE_URL := ""
## Rodzaj głośności → szyny z default_bus_layout.tres. „Mic" (voice.gd) celowo poza listą.
const VOLUME_BUSES := {"master": ["Master"], "music": ["Music", "Ambience"], "sfx": ["SFX", "UI"]}
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
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]
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
const Actions := preload("res://scripts/actions.gd")

var volume := {"master": 1.0, "music": 1.0, "sfx": 1.0}
var shake_idx := 0
var weather_fx_idx := WEATHER_FX_REDUCED
var ui_idx := 1
var cam_idx := 1                       ## zbliżenie kamery: WIDE / NORMAL / CLOSE (CAM_ZOOM) — większe postacie kosztem pola widzenia
var hints_on := true
var res_idx := 0                       ## rozmiar okna z RES_LIST (tylko tryb okienkowy)
var vsync_idx := 0
var fps_idx := 0
var quality_idx := 2                   ## LOW / MEDIUM / HIGH — cząsteczki, aberracja, efekty pogody
var mono_audio := false                ## bez panoramy w dźwięku pozycyjnym (osoby z jednostronnym słuchem)
var captions := false                  ## napisy dla dźwięków (HUD, captions.gd)
var reduce_fx := false                 ## „Reduce Effects": bez wstrząsów, aberracji, pulsu zdrowia, błysku burzy i migotania
var crouch_toggle := false             ## skradanie przełączane klawiszem zamiast trzymania
var colorblind_idx := 0
var locale_idx := 0
var _res_dirty := false                ## gracz zmienił rozmiar okna (inaczej zostaje domyślny z projektu)
var fullscreen := false
var char3d := false                    ## (beta) postacie graczy jako modele 3D w czasie rzeczywistym (char3d.gd) zamiast sprite'ów; tylko z grafiką HD, zmiana wymaga restartu
var graphics_hd := true                ## grafika HD (postacie, bronie, wrogowie, świat, UI z modeli 3D) zamiast klasycznego pixel-artu; zmiana wymaga restartu gry
var seen_tips: Array = []              ## identyfikatory podpowiedzi, które gracz już widział
var shift_best_cleared := 0            ## Nocny Dyżur: najwięcej ukończonych misji w jednej serii (rekord lokalny)
var shift_best_time := 0.0             ## Nocny Dyżur: najkrótszy czas pełnej serii w s (0 = jeszcze nikt nie ukończył)

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

func cycle_quality() -> void:
	quality_idx = (quality_idx + 1) % QUALITY_NAMES.size()
	_commit()

func toggle_mono_audio() -> void:
	mono_audio = not mono_audio
	_commit()

func toggle_captions() -> void:
	captions = not captions
	_commit()

func toggle_reduce_fx() -> void:
	reduce_fx = not reduce_fx
	_commit()

func toggle_crouch_mode() -> void:
	crouch_toggle = not crouch_toggle
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

## Czy używać grafiki HD w tej sesji: ustawienie gracza, ale nigdy w trybie headless (testy liczą klasyczny wariant) i nie z `--classic`.
## Aktywne ustawienie jest czytane przy starcie — zmiana w menu działa po restarcie.
func hd_active() -> bool:
	return graphics_hd and DisplayServer.get_name() != "headless" and not ("--classic" in OS.get_cmdline_user_args())

func toggle_hd() -> void:
	graphics_hd = not graphics_hd
	_commit()

func toggle_char3d() -> void:
	char3d = not char3d
	_commit()

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

# ---------------------------------------------------------------- zapis

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for kind in volume:
		volume[kind] = clampf(float(cf.get_value("game", "vol_" + kind, 1.0)), 0.0, 1.0)
	shake_idx = clampi(int(cf.get_value("game", "shake", 0)), 0, SHAKE_NAMES.size() - 1)
	weather_fx_idx = clampi(int(cf.get_value("game", "weather_fx", WEATHER_FX_REDUCED)), 0, WEATHER_FX_NAMES.size() - 1)
	ui_idx = clampi(int(cf.get_value("game", "ui", 1)), 0, UI_NAMES.size() - 1)
	cam_idx = clampi(int(cf.get_value("game", "cam", 1)), 0, CAM_NAMES.size() - 1)
	hints_on = bool(cf.get_value("game", "hints", true))
	fullscreen = bool(cf.get_value("game", "fullscreen", false))
	res_idx = clampi(int(cf.get_value("game", "res", 0)), 0, RES_LIST.size() - 1)
	_res_dirty = cf.has_section_key("game", "res")
	vsync_idx = clampi(int(cf.get_value("game", "vsync", 0)), 0, VSYNC_NAMES.size() - 1)
	fps_idx = clampi(int(cf.get_value("game", "fps", 0)), 0, FPS_LIST.size() - 1)
	quality_idx = clampi(int(cf.get_value("game", "quality", 2)), 0, QUALITY_NAMES.size() - 1)
	reduce_fx = bool(cf.get_value("game", "reduce_fx", false))
	captions = bool(cf.get_value("game", "captions", false))
	mono_audio = bool(cf.get_value("game", "mono_audio", false))
	crouch_toggle = bool(cf.get_value("game", "crouch_toggle", false))
	colorblind_idx = clampi(int(cf.get_value("game", "colorblind", 0)), 0, COLORBLIND_NAMES.size() - 1)
	locale_idx = clampi(int(cf.get_value("game", "locale", 0)), 0, LOCALES.size() - 1)
	graphics_hd = bool(cf.get_value("game", "graphics_hd", true))
	char3d = bool(cf.get_value("game", "char3d", false))
	seen_tips = Array(cf.get_value("game", "seen_tips", []))
	Actions.load_from(cf)
	shift_best_cleared = int(cf.get_value("shift", "best_cleared", 0))
	shift_best_time = float(cf.get_value("shift", "best_time", 0.0))

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
	cf.set_value("game", "fullscreen", fullscreen)
	if _res_dirty:
		cf.set_value("game", "res", res_idx)
	cf.set_value("game", "vsync", vsync_idx)
	cf.set_value("game", "fps", fps_idx)
	cf.set_value("game", "quality", quality_idx)
	cf.set_value("game", "reduce_fx", reduce_fx)
	cf.set_value("game", "captions", captions)
	cf.set_value("game", "mono_audio", mono_audio)
	cf.set_value("game", "crouch_toggle", crouch_toggle)
	cf.set_value("game", "colorblind", colorblind_idx)
	cf.set_value("game", "locale", locale_idx)
	cf.set_value("game", "graphics_hd", graphics_hd)
	cf.set_value("game", "char3d", char3d)
	cf.set_value("game", "seen_tips", seen_tips)
	Actions.save_to(cf)
	cf.set_value("shift", "best_cleared", shift_best_cleared)
	cf.set_value("shift", "best_time", shift_best_time)
	cf.save(SAVE_PATH)
