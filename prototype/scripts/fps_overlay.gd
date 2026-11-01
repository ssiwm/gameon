extends CanvasLayer
## Licznik płynności w prawym górnym rogu: FPS i najdłuższa klatka z ostatniej sekundy („60 FPS  17 ms”).
## Sama średnia FPS ukrywa przycięcia, dlatego obok jest najgorsza klatka. Działa wszędzie (menu, kryjówka, misja, pauza),
## nad planszą wczytywania. Włącza ustawienie „Show FPS”; zapis tych samych danych do pliku: próbki `perf` w session_log.gd.

const UiTheme := preload("res://scripts/ui_theme.gd")

const LAYER := 101                  ## nad planszą wczytywania (view3d: warstwa 100)
const WINDOW := 1.0                 ## s, co tyle odświeża się tekst; dłużej niż mignięcie, żeby przycięcie dało się odczytać
const BAND := 9.0                   ## wysokość pasa licznika (jednostki viewportu 640×360); karta RUN w HUD-zie schodzi pod niego
const FONT_SIZE := 6
const FPS_WARN := 50                ## poniżej tego kolor ostrzegawczy
const FPS_BAD := 30                 ## poniżej tego kolor czerwony
const WORST_WARN_MS := 34.0         ## najdłuższa klatka powyżej dwóch okresów 60 Hz: widać przeskok
const WORST_BAD_MS := 50.0          ## jak PERF_SPIKE_MS w dzienniku: przestój

var _label: Label
var _hidden := true                 ## bez licznika: headless, zrzuty, nagrania
var _last_us := 0
var _elapsed := 0.0
var _frames := 0
var _worst := 0.0

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hidden = DisplayServer.get_name() == "headless" or hidden_by_args(OS.get_cmdline_user_args(), OS.get_cmdline_args())
	visible = false
	set_process(false)
	if DisplayServer.get_name() == "headless":
		return
	_label = UiTheme.mono(UiTheme.label("", FONT_SIZE, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 2)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.offset_right = -3.0
	add_child(_label)
	Settings.changed.connect(_refresh)
	_refresh()

## Wysokość pasa zajętego przez licznik (0, gdy go nie widać): HUD układa pod nim kartę RUN.
func band() -> float:
	return BAND if visible else 0.0

func _refresh() -> void:
	var show_now := Settings.show_fps and not _hidden
	if show_now == visible:
		return
	visible = show_now
	set_process(show_now)
	_last_us = 0
	_elapsed = 0.0
	_frames = 0
	_worst = 0.0
	_label.text = ""

func _process(_delta: float) -> void:
	# własny zegar: `delta` silnik przycina (session_log.gd), a spowolnienie czasu gry nie może zmieniać wyniku
	var now := Time.get_ticks_usec()
	if _last_us != 0:
		var ms := float(now - _last_us) / 1000.0
		_worst = maxf(_worst, ms)
		_elapsed += ms / 1000.0
		_frames += 1
	_last_us = now
	if _elapsed < WINDOW:
		return
	var fps := roundi(float(_frames) / _elapsed)
	_label.text = label_text(fps, _worst)
	_label.add_theme_color_override("font_color", tone(fps, _worst))
	_elapsed = 0.0
	_frames = 0
	_worst = 0.0

static func label_text(fps: int, worst_ms: float) -> String:
	return "%d FPS  %d ms" % [fps, roundi(worst_ms)]

static func tone(fps: int, worst_ms: float) -> Color:
	if fps < FPS_BAD or worst_ms > WORST_BAD_MS:
		return UiTheme.DANGER
	if fps < FPS_WARN or worst_ms > WORST_WARN_MS:
		return UiTheme.ACCENT
	return UiTheme.MUTED

## Zrzuty, nagrania i narzędzia uruchamiane skryptem mają czysty obraz; `--showfps` wymusza licznik (sprawdzanie układu na zrzucie).
static func hidden_by_args(user_args: PackedStringArray, engine_args: PackedStringArray) -> bool:
	if "--showfps" in user_args:
		return false
	if "--write-movie" in engine_args or "-s" in engine_args or "--script" in engine_args or "--nohud" in user_args:
		return true
	for a in user_args:
		if a.begins_with("--shot") or a.begins_with("--view3dsave"):
			return true
	return false
