extends Control
## Menu pauzy (Esc / P): ustawienia, bestiariusz, opisy broni i ściąga sterowania (zakładki). Budowane w kodzie na wspólnym motywie.
##
## Gra solo (żaden zdalny gracz) jest naprawdę zatrzymywana. W kooperacji świat idzie dalej — host jest
## autorytetem, a zatrzymanie go zamroziłoby kolegów — i menu mówi to wprost. Na czas menu akcje gry
## są wycięte z InputMap (Settings.block_game_input), więc klik w przycisk nie strzela.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Lobby := preload("res://scripts/lobby.gd")
const Codex := preload("res://scripts/codex.gd")
const CodexPage := preload("res://scripts/codex_page.gd")

const CARD_W := 450.0
const PAGE_H := 270.0                ## stała wysokość zakładek — karta nie skacze przy przełączaniu
const TABS := ["SETTINGS", "BESTIARY", "WEAPONS", "GEAR", "PERKS", "CONTROLS"]
const BASE_SCALE := 0.7              ## jak HUD (hud.gd UI_SCALE): menu rysowane w 70%, razem z ustawieniem HUD SIZE

var _settings_page: VBoxContainer
var _controls_page: VBoxContainer
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _tab := 0
var _sub: Label
var _values := {}                    ## klucz → Label z bieżącą wartością
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _open := false

func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS       # menu działa także przy zatrzymanym drzewie (solo)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	visible = false
	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_fit)
	_fit()

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	var card_bg := UiTheme.panel_box()
	card_bg.bg_color.a = 1.0                       # pełne krycie: napisy świata (tablice, ściana wyników) nie prześwitują przez opisy
	card.add_theme_stylebox_override("panel", card_bg)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	box.add_child(UiTheme.heading("PAUSED", 24, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_sub = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_sub)
	box.add_child(_rule())

	# zakładki
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	for i in TABS.size():
		var tb := Button.new()
		_compact(tb)
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	box.add_child(tabs)

	_settings_page = VBoxContainer.new()
	_settings_page.add_theme_constant_override("separation", 3)
	_build_settings()
	_controls_page = VBoxContainer.new()
	_build_controls()
	# kolejność = TABS; bestiariusz i bronie powstają przy pierwszym otwarciu zakładki
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, PAGE_H)
	box.add_child(holder)
	var bestiary := CodexPage.new()
	var arsenal := CodexPage.new()
	var gear := CodexPage.new()
	var perks := CodexPage.new()
	_pages = [_settings_page, bestiary, arsenal, gear, perks, _controls_page]
	for p in _pages:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		holder.add_child(p)
	bestiary.setup(Codex.bestiary())
	arsenal.setup(Codex.arsenal())
	gear.setup(Codex.gear())
	perks.setup(Codex.perks())

	box.add_child(_rule())
	var btns := HBoxContainer.new()
	var resume := Button.new()
	resume.text = "RESUME"
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.pressed.connect(close)
	btns.add_child(resume)
	var quit := Button.new()
	quit.text = "QUIT GAME"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.tooltip_text = "Closes the game (your squad keeps playing if you are the client)"
	quit.pressed.connect(func() -> void:
		close()
		get_tree().quit())
	btns.add_child(quit)
	box.add_child(btns)
	Settings.changed.connect(_refresh)
	Voice.changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if _open:
		close()

## Rozmiar logiczny = viewport / skala (tak samo jak HUD), żeby menu mieściło się na ekranie.
func _fit() -> void:
	var k := BASE_SCALE * Settings.ui_mult()
	scale = Vector2(k, k)
	size = get_viewport_rect().size / k

# ---------------------------------------------------------------- budowa

func _build_settings() -> void:
	_settings_page.add_child(_caption("AUDIO"))
	_stepper("master", "Master volume")
	_stepper("music", "Music & ambience")
	_stepper("sfx", "Effects")
	_settings_page.add_child(_caption("GAMEPLAY"))
	_cycler("shake", "Screen shake", Settings.cycle_shake)
	_cycler("wfx", "Weather effects", Settings.cycle_weather_fx)
	_cycler("hints", "Tips for new players", Settings.toggle_hints)
	_cycler("mic", "Microphone scream", Voice.cycle)
	_settings_page.add_child(_caption("DISPLAY"))
	_cycler("ui", "HUD size", Settings.cycle_ui)
	_cycler("full", "Fullscreen  (F11)", Settings.toggle_fullscreen)
	_cycler("hd", "Graphics (restart)", Settings.toggle_hd)
	_cycler("c3d", "Characters (restart)", Settings.toggle_char3d)

## Wiersz: opis po lewej, [−] wartość [+] po prawej.
func _stepper(kind: String, text: String) -> void:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, 9, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_small_button("−", func() -> void:
		Settings.set_volume(kind, float(Settings.volume[kind]) - Settings.STEP)))
	var v := UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(38, 0)
	_values[kind] = v
	row.add_child(v)
	row.add_child(_small_button("+", func() -> void:
		Settings.set_volume(kind, float(Settings.volume[kind]) + Settings.STEP)))
	_settings_page.add_child(row)

## Wiersz: opis po lewej, przycisk przełączający po prawej.
func _cycler(key: String, text: String, action: Callable) -> void:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, 9, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	_compact(b)
	b.custom_minimum_size = Vector2(96, 0)
	b.pressed.connect(func() -> void:
		action.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	_values[key] = b
	row.add_child(b)
	_settings_page.add_child(row)

func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	_compact(b)
	b.text = text
	b.custom_minimum_size = Vector2(22, 0)
	b.pressed.connect(func() -> void:
		action.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	return b

func _build_controls() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	var rows: Array = Lobby.CONTROLS
	var half := (rows.size() + 1) / 2
	for i in half:
		_control(grid, rows[i])
		if i + half < rows.size():
			_control(grid, rows[i + half])
		else:
			grid.add_child(Control.new())
			grid.add_child(Control.new())
	_controls_page.add_child(grid)

func _control(grid: GridContainer, row: Array) -> void:
	var cap := StyleBoxFlat.new()
	cap.bg_color = Color(0.13, 0.14, 0.18, 0.95)
	cap.border_color = Color(1, 1, 1, 0.16)
	cap.set_border_width_all(1)
	cap.border_width_bottom = 2
	cap.set_corner_radius_all(2)
	cap.content_margin_left = 4
	cap.content_margin_right = 4
	cap.content_margin_top = 0
	cap.content_margin_bottom = 1
	var key := UiTheme.label(row[0], 7, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	key.add_theme_stylebox_override("normal", cap)
	key.custom_minimum_size = Vector2(62, 0)
	grid.add_child(key)
	var desc := UiTheme.label(row[1], 8, UiTheme.MUTED)
	desc.custom_minimum_size = Vector2(88, 0)
	grid.add_child(desc)

## Niższy przycisk (mniejsze marginesy pionowe) — wiersze ustawień nie rozpychają karty.
func _compact(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = theme.get_stylebox(state, "Button").duplicate()
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_font_size_override("font_size", 9)

func _caption(text: String) -> Label:
	return UiTheme.label(text, 7, UiTheme.ACCENT.darkened(0.15))

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.10)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------------------------------------------------------- stan

func _refresh() -> void:
	for kind in Settings.volume:
		_values[kind].text = "%d%%" % int(round(float(Settings.volume[kind]) * 100.0))
	_values["shake"].text = Settings.SHAKE_NAMES[Settings.shake_idx]
	_values["wfx"].text = Settings.WEATHER_FX_NAMES[Settings.weather_fx_idx]
	_values["hints"].text = "ON" if Settings.hints_on else "OFF"
	_values["mic"].text = Voice.label().replace("MIC: ", "")
	_values["ui"].text = Settings.UI_NAMES[Settings.ui_idx]
	_values["full"].text = "ON" if Settings.fullscreen else "OFF"
	_values["hd"].text = "HD" if Settings.graphics_hd else "CLASSIC"
	_values["c3d"].text = "3D (BETA)" if Settings.char3d else "SPRITES"

func _show_tab(i: int) -> void:
	_tab = i
	for j in _pages.size():
		_pages[j].visible = j == i
		_tab_buttons[j].set_pressed_no_signal(j == i)

func _lobby_visible() -> bool:
	var lobby := get_node_or_null("../Lobby") as Control
	return lobby != null and lobby.visible

func _solo() -> bool:
	return multiplayer.get_peers().is_empty()

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_sub.text = "The game is paused." if _solo() else "The game keeps running — your squad is still out there."
	get_tree().paused = _solo()
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_tab(_tab)
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(_delta: float) -> void:
	# ktoś dołączył do zatrzymanej gry solo — świat musi ruszyć
	if _open and get_tree().paused and not _solo():
		get_tree().paused = false
		_sub.text = "The game keeps running — your squad is still out there."

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	var ws := get_tree().get_first_node_in_group("workshop_ui")
	if ws != null and ws.is_open():
		return                                  # Esc zamyka panel warsztatu (workshop_ui.gd), nie otwiera pauzy
	if _open:
		close()
	elif NoiseMgr.has_network() and not _lobby_visible():     # w lobby Esc nic nie robi
		open()
	else:
		return
	get_viewport().set_input_as_handled()
