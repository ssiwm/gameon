extends Node
## Krzyk (GDD §8.2) — mikrofon jako mechanika grozy, z odpowiednikiem na przycisk (G).
##
## Autoload „Voice". Dwa wejścia, jedno zdarzenie:
##   • mikrofon (opt-in, domyślnie WYŁĄCZONY): wykrywanie aktywności głosowej (VAD) — głośny,
##     utrzymany krzyk (≥ SUSTAIN s powyżej progu) = krzyk gracza; szept i normalna mowa
##     są ignorowane (działają jak interkom, nie generują hałasu)
##   • klawisz G: ten sam efekt bez mikrofonu (streamerzy, dzieci, brak mikrofonu)
## Krzyk = Uwaga +20 i przyciągnięcie wrogów w promieniu 25 m (player.do_scream →
## NoiseMgr.add_scream). Cooldown wspólny, żeby nie dało się go spamować.
##
## Prywatność: dźwięk jest przetwarzany tylko lokalnie (poziom RMS z bufora przechwytującego),
## nie jest nagrywany ani wysyłany — przez sieć idzie wyłącznie zdarzenie „krzyk" i jego głośność.
## Wymaga `audio/driver/enable_input=true` w project.godot; w headless wyłączony.

signal changed

const SCREAM_NOISE := 20.0           ## GDD §8.2: krzyk = Uwaga +20
const SCREAM_COOLDOWN := 2.5
const SUSTAIN := 0.18                ## s powyżej progu, zanim uznamy to za krzyk (kliknięcia i kaszel odpadają)
const HYSTERESIS_DB := 6.0           ## poniżej progu − tyle dB następny krzyk jest „uzbrojony"
## Czułość: [próg bezwzględny dBFS, margines nad szumem tła dB]. Próg = max(oba).
const SENS := [[-17.0, 20.0], [-21.0, 16.0], [-25.0, 12.0]]
const SENS_NAMES := ["LOW", "MED", "HIGH"]
const BUS := "Mic"
const SAVE_PATH := "user://settings.cfg"

var enabled := false
var sens := 1
var status := "OFF"                  ## OFF | ON | NO MIC
var level_db := -80.0                ## wygładzony poziom mikrofonu
var floor_db := -60.0                ## adaptacyjny szum tła
var cooldown := 0.0

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _above := 0.0
var _armed := true
var _bar: Bar

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_load()
	_build_bar()
	if enabled:
		_start_mic()

# ---------------------------------------------------------------- ustawienia

## Przycisk w lobby: OFF → LOW → MED → HIGH → OFF.
func cycle() -> void:
	var s := (sens if enabled else -1) + 1
	if s > 2:
		set_enabled(false)
	else:
		sens = s
		set_enabled(true)
	_save()
	changed.emit()

func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		_start_mic()
	else:
		_stop_mic()
	changed.emit()

func label() -> String:
	if not enabled:
		return "MIC: OFF"
	if status != "ON":
		return "MIC: %s" % status
	return "MIC: ON · %s" % SENS_NAMES[sens]

func threshold_db() -> float:
	var cfg: Array = SENS[sens]
	return maxf(float(cfg[0]), floor_db + float(cfg[1]))

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		enabled = bool(cf.get_value("voice", "mic", false))
		sens = clampi(int(cf.get_value("voice", "sens", 1)), 0, 2)

func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("voice", "mic", enabled)
	cf.set_value("voice", "sens", sens)
	cf.save(SAVE_PATH)

# ---------------------------------------------------------------- mikrofon

func _start_mic() -> void:
	if _player != null:
		status = "ON"
		return
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		status = "NO MIC"
		return
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		# wyciszona szyna „Mic" z przechwytywaniem: sygnał mikrofonu nie trafia do głośników
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_mute(idx, true)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.25
		AudioServer.add_bus_effect(idx, cap)
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	if _capture == null:
		status = "NO MIC"
		return
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	_player.play()
	_above = 0.0
	_armed = true
	status = "ON"

func _stop_mic() -> void:
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	status = "OFF"
	level_db = -80.0

func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if _bar != null:
		var show := enabled and status == "ON" and NoiseMgr.has_network()
		_bar.visible = show
		if show:
			_bar.queue_redraw()
	if _capture == null or not enabled:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	var sum := 0.0
	for v in buf:
		var m := (v.x + v.y) * 0.5
		sum += m * m
	var db := linear_to_db(maxf(sqrt(sum / float(n)), 0.000001))
	level_db = lerpf(level_db, db, 0.5)
	# szum tła: szybko w dół, bardzo wolno w górę (krzyk nie podnosi progu), nigdy powyżej −32 dB
	if db < floor_db:
		floor_db = lerpf(floor_db, db, 0.25)
	else:
		floor_db = minf(-32.0, lerpf(floor_db, db, 0.0008))
	var thr := threshold_db()
	if level_db >= thr:
		_above += delta
		if _above >= SUSTAIN and _armed and cooldown <= 0.0:
			_armed = false
			var loud := clampf((level_db - thr) / 12.0, 0.0, 1.0)
			var p := _local_player()
			if p != null:
				try_scream(p, minf(lerpf(12.0, 26.0, loud), p.perk_param("cold_blood", "scream_cap", 99.0)))   # „Cold blood" ucina krzyk z mikrofonu
	elif level_db < thr - HYSTERESIS_DB:
		_above = 0.0
		_armed = true

# ---------------------------------------------------------------- krzyk

## Wspólne wejście dla mikrofonu i klawisza G. Zwraca true, jeśli krzyk poszedł.
func try_scream(p: Node, amount := SCREAM_NOISE) -> bool:
	if cooldown > 0.0 or p == null or p.dead:
		return false
	cooldown = SCREAM_COOLDOWN
	p.do_scream(amount)
	return true

func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead:
			return p
	return null

# ---------------------------------------------------------------- wskaźnik

class Bar extends Control:
	var voice: Node

	func _draw() -> void:
		var w := 70.0
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, -3), "MIC  ·  G = scream", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.75, 0.8, 0.9))
		draw_rect(Rect2(0, 0, w, 3), Color(0, 0, 0, 0.55))
		var lv := clampf((voice.level_db + 60.0) / 60.0, 0.0, 1.0)
		var hot: bool = voice.level_db >= voice.threshold_db()
		draw_rect(Rect2(0, 0, w * lv, 3), Color(1.0, 0.5, 0.3) if hot else Color(0.45, 0.8, 0.55))
		var tx := clampf((voice.threshold_db() + 60.0) / 60.0, 0.0, 1.0) * w
		draw_rect(Rect2(tx - 0.5, -1, 1, 5), Color(1.0, 0.75, 0.3))
		if voice.cooldown > 0.0:
			draw_rect(Rect2(0, 4, w * voice.cooldown / voice.SCREAM_COOLDOWN, 1), Color(0.6, 0.6, 0.65, 0.8))

func _build_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_bar = Bar.new()
	_bar.voice = self
	_bar.position = Vector2(8, 44)       # pod miernikiem hałasu (lewy górny róg); dół zajmuje karta drużyny
	_bar.visible = false
	layer.add_child(_bar)
