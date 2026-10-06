extends Node
## Ustawienia gracza (autoload „Settings"): głośność, wstrząsy kamery, rozmiar HUD, podpowiedzi,
## pełny ekran. Zapis w user://settings.cfg (sekcja „game"; sekcję „voice" prowadzi voice.gd —
## oba moduły wczytują plik przed zapisem, więc sobie nie przeszkadzają).
##
## Dodatkowo `block_game_input()` wycina akcje gry z InputMap na czas menu pauzy: wszystkie skrypty
## czytają je przez Input.is_action_*, więc jedno miejsce wystarcza (żeby klik w menu nie strzelał).

signal changed

const SAVE_PATH := "user://settings.cfg"
const STEP := 0.1
## Wersja demo: ekran końcowy misji zachęca do dodania gry do listy życzeń. STORE_URL uzupełnić, gdy strona
## sklepu Steam będzie publiczna (puste = bez przycisku [O]).
const DEMO := true
const STORE_URL := ""
## Rodzaj głośności → szyny z default_bus_layout.tres. „Mic" (voice.gd) celowo poza listą.
const VOLUME_BUSES := {"master": ["Master"], "music": ["Music", "Ambience"], "sfx": ["SFX", "UI"]}
const SHAKE_NAMES := ["FULL", "HALF", "OFF"]
const SHAKE_MULT := [1.0, 0.5, 0.0]
const UI_NAMES := ["SMALL", "NORMAL", "LARGE"]
const UI_MULT := [0.85, 1.0, 1.25]
## Akcje wyłączane przy otwartym menu (wszystkie poza „pause").
const GAME_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down", "jump", "fire", "crouch", "overcharge", "scream",
	"flare", "interact", "weapon_1", "weapon_2", "weapon_3", "weapon_next", "weapon_prev", "restart",
	"flashlight", "reload", "melee", "help",
]

var volume := {"master": 1.0, "music": 1.0, "sfx": 1.0}
var shake_idx := 0
var ui_idx := 1
var hints_on := true
var fullscreen := false
var seen_tips: Array = []              ## identyfikatory podpowiedzi, które gracz już widział

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
	return SHAKE_MULT[shake_idx]

func ui_mult() -> float:
	return UI_MULT[ui_idx]

func set_volume(kind: String, v: float) -> void:
	volume[kind] = snappedf(clampf(v, 0.0, 1.0), STEP)
	_apply_volume(kind)
	_commit()

func cycle_shake() -> void:
	shake_idx = (shake_idx + 1) % SHAKE_NAMES.size()
	_commit()

func cycle_ui() -> void:
	ui_idx = (ui_idx + 1) % UI_NAMES.size()
	_commit()

func toggle_hints() -> void:
	hints_on = not hints_on
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
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		toggle_fullscreen()

# ---------------------------------------------------------------- zastosowanie

func _apply_all() -> void:
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

func _commit() -> void:
	_save()
	changed.emit()

# ---------------------------------------------------------------- blokada wejścia (menu pauzy)

func block_game_input(on: bool) -> void:
	if on == blocked:
		return
	blocked = on
	if on:
		for a in GAME_ACTIONS:
			if InputMap.has_action(a):
				_stash[a] = InputMap.action_get_events(a)
				InputMap.action_erase_events(a)
				Input.action_release(a)       # trzymany klawisz nie zostaje „wciśnięty" po wycięciu zdarzeń
	else:
		for a in _stash:
			for e in _stash[a]:
				InputMap.action_add_event(a, e)
		_stash.clear()

# ---------------------------------------------------------------- zapis

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for kind in volume:
		volume[kind] = clampf(float(cf.get_value("game", "vol_" + kind, 1.0)), 0.0, 1.0)
	shake_idx = clampi(int(cf.get_value("game", "shake", 0)), 0, SHAKE_NAMES.size() - 1)
	ui_idx = clampi(int(cf.get_value("game", "ui", 1)), 0, UI_NAMES.size() - 1)
	hints_on = bool(cf.get_value("game", "hints", true))
	fullscreen = bool(cf.get_value("game", "fullscreen", false))
	seen_tips = Array(cf.get_value("game", "seen_tips", []))

func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for kind in volume:
		cf.set_value("game", "vol_" + kind, volume[kind])
	cf.set_value("game", "shake", shake_idx)
	cf.set_value("game", "ui", ui_idx)
	cf.set_value("game", "hints", hints_on)
	cf.set_value("game", "fullscreen", fullscreen)
	cf.set_value("game", "seen_tips", seen_tips)
	cf.save(SAVE_PATH)
