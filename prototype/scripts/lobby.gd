extends Control
## Lobby: host / join (LAN po IP, Steam po lobby ID), trudność, mikrofon, tryb startu (kampania / kryjówka / Nocny Dyżur), ściąga sterowania.
## Budowane w kodzie na wspólnym motywie (ui_theme.gd). main.gd słucha sygnałów i ustawia status.
##
## Układ (viewport 640×360, karta wyśrodkowana): nagłówek → MULTIPLAYER (dwa wiersze o tych samych
## kolumnach: przycisk hosta | pole | przycisk dołączania) → OPTIONS (trudność, mikrofon) →
## status → CONTROLS w dwóch kolumnach. Całość mieści się z zapasem — wcześniej lista sterowania
## była ucinana przy dolnej krawędzi.

signal host_requested
signal join_requested(ip: String)
signal steam_host_requested
signal steam_join_requested(lobby_id: String)
signal back_requested                ## wróć do menu głównego
signal settings_requested            ## ustawienia (menu pauzy w trybie ustawień)

const UiTheme := preload("res://scripts/ui_theme.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Actions := preload("res://scripts/actions.gd")

const CARD_W := 600.0               ## szeroka karta: sterowanie w trzech kolumnach mieści się w 360 px wysokości (viewport 640×360)
const BTN_W := 108.0                ## stała szerokość przycisków bocznych — kolumny wierszy się pokrywają

enum Mode { CAMPAIGN, SAFE_ROOM, NIGHT_SHIFT }
const MODE_NAMES := ["CAMPAIGN", "SAFE ROOM", "NIGHT SHIFT"]
const MODE_HINTS := [
	"Campaign: Zone I missions in order, with the safe room between them.",
	"Safe room: start in the hideout — swap guns, read the board and the results wall, ready up to head out on the campaign.",
	"Night Shift: five missions in a row, each harder, with random modifiers. A squad wipe ends the run.",
]
const DEFAULT_HINT := "Host a game, or enter the host's IP and join."

## Wybrany tryb startu hosta (main.gd czyta przy hostowaniu): kampania, kryjówka albo Nocny Dyżur.
var mode: int = Mode.CAMPAIGN
var start_in_hub: bool:
	get:
		return mode == Mode.SAFE_ROOM

var _ip: LineEdit
var _status: Label
var _host: Button
var _diff: Button
var _mode: Button
var _steam_host: Button
var _steam_join: Button
var _steam_id: LineEdit
var _mic: Button
var _back: Button
var _title: Label
var _t := 0.0

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	_build_header(box)
	_build_multiplayer(box)
	_build_options(box)
	_build_status(box)
	_build_controls(box)
	_build_footer(box)

	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_host.grab_focus())
	_host.call_deferred("grab_focus")

# ---------------------------------------------------------------- sekcje

func _build_header(box: VBoxContainer) -> void:
	_title = UiTheme.heading("DEAD AIR '87", 24, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	box.add_child(UiTheme.label("Co-op horror run & gun  ·  prototype", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_rule(UiTheme.ACCENT, 0.45))
	box.add_child(_spacer(2))

## Dwa wiersze o wspólnych kolumnach: [przycisk | pole | przycisk] — LAN po IP i Steam po ID lobby.
func _build_multiplayer(box: VBoxContainer) -> void:
	box.add_child(_caption("MULTIPLAYER"))
	_host = _side_button("HOST GAME")
	_host.pressed.connect(func() -> void: host_requested.emit())
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "host IP, e.g. 192.168.0.12"
	_ip.tooltip_text = "LAN / direct: the host's IP address (port 8910)"
	_ip.text_submitted.connect(func(t: String) -> void: join_requested.emit(t.strip_edges()))
	var join := _side_button("JOIN")
	join.pressed.connect(func() -> void: join_requested.emit(_ip.text.strip_edges()))
	box.add_child(_connect_row(_host, _ip, join))

	_steam_host = _side_button("STEAM HOST")
	_steam_host.pressed.connect(func() -> void: steam_host_requested.emit())
	_steam_id = LineEdit.new()
	_steam_id.placeholder_text = "Steam lobby ID"
	_steam_id.text_submitted.connect(func(t: String) -> void: steam_join_requested.emit(t.strip_edges()))
	_steam_join = _side_button("STEAM JOIN")
	_steam_join.pressed.connect(func() -> void: steam_join_requested.emit(_steam_id.text.strip_edges()))
	box.add_child(_connect_row(_steam_host, _steam_id, _steam_join))
	set_steam_available(false)

func _connect_row(left: Button, field: LineEdit, right: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(field)
	row.add_child(right)
	return row

## Trudność, mikrofon (VAD, opt-in) i tryb startu (kampania / kryjówka / Nocny Dyżur). Trudność i tryb wybiera host.
func _build_options(box: VBoxContainer) -> void:
	box.add_child(_caption("OPTIONS"))
	var opts := HBoxContainer.new()
	_diff = _option_button("Chosen by the host. Applies to enemies, the stalker, the boss, noise and drops.")
	_diff.pressed.connect(func() -> void:
		Difficulty.set_level((Difficulty.level + 1) % Difficulty.NAMES.size())
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	Difficulty.changed.connect(func(_l: int) -> void: _refresh_difficulty())
	_refresh_difficulty()
	opts.add_child(_diff)
	_mic = _option_button("Shout into the microphone to scream (same as G). Processed locally, never recorded. Click: OFF > LOW > MED > HIGH sensitivity.")
	_mic.pressed.connect(func() -> void:
		Voice.cycle()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	Voice.changed.connect(func() -> void: _mic.text = Voice.label())
	_mic.text = Voice.label()
	opts.add_child(_mic)
	_mode = _option_button("Chosen by the host. Click to cycle: campaign, safe room, night shift.")
	_mode.pressed.connect(func() -> void:
		mode = (mode + 1) % MODE_NAMES.size()
		NightShift.selected = mode == Mode.NIGHT_SHIFT
		_refresh_mode()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	opts.add_child(_mode)
	_refresh_mode()
	box.add_child(opts)

func _option_button(tip: String) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tip
	return b

## Stała wysokość: układ nie skacze, gdy komunikat zajmuje dwie linie. Bez błędu pokazuje opis wybranego trybu.
func _build_status(box: VBoxContainer) -> void:
	_status = UiTheme.label(DEFAULT_HINT, 9, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 24)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_status)

## Dwie kolumny par [klawisz | opis]; klawisze z rejestru akcji (`actions.gd`).
func _build_controls(box: VBoxContainer) -> void:
	box.add_child(_rule(Color(1, 1, 1), 0.10))
	box.add_child(_caption("CONTROLS"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	_fill_controls(grid)
	InputSetup.device_changed.connect(func(_pad: bool) -> void: _fill_controls(grid))
	Settings.bindings_changed.connect(func() -> void: _fill_controls(grid))

func _fill_controls(grid: GridContainer) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var rows: Array = Actions.sheet()
	var per_col := (rows.size() + 2) / 3
	for i in per_col:
		for c in 3:
			var idx := i + c * per_col
			if idx < rows.size():
				_add_control(grid, rows[idx])
			else:
				grid.add_child(Control.new())
				grid.add_child(Control.new())

## Dolny rząd: BACK (do menu głównego; tylko gdy main.gd je pokazuje) i SETTINGS.
func _build_footer(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	_back = _side_button("BACK")
	_back.visible = false
	_back.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		back_requested.emit())
	row.add_child(_back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var st := _side_button("SETTINGS")
	st.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		settings_requested.emit())
	row.add_child(st)
	box.add_child(row)

## BACK ma sens tylko, gdy istnieje menu główne.
func set_back_enabled(on: bool) -> void:
	_back.visible = on

## Tytuł lekko „migocze" — rzadkie, krótkie zaniki jak przy słabym kontakcie (klimat, nie szum).
func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var dip := 0.55 if (fmod(_t, 7.3) < 0.09 or (fmod(_t, 11.9) > 11.7 and fmod(_t, 0.07) < 0.035)) else 1.0
	_title.modulate.a = dip

func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.DANGER if is_error else UiTheme.MUTED)

## Przyciski Steam działają tylko z wtyczką GodotSteam i uruchomionym klientem Steam.
func set_steam_available(on: bool) -> void:
	var tip := "Steam lobby + invites (App ID 480 test)" if on else "Needs the GodotSteam addon and the Steam client — see README"
	for c in [_steam_host, _steam_join, _steam_id]:
		c.tooltip_text = tip
	_steam_host.disabled = not on
	_steam_join.disabled = not on
	_steam_id.editable = on

## Klient nie wybiera trudności — ustala ją host (main.gd rozsyła wybór).
func lock_difficulty() -> void:
	_diff.disabled = true
	_mode.disabled = true

# ---------------------------------------------------------------- elementy

func _side_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BTN_W, 0)
	return b

func _caption(text: String) -> Label:
	return UiTheme.heading(text, 8, UiTheme.ACCENT.darkened(0.15))

func _rule(color: Color, alpha: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, alpha)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

## Klawisz jako „keycap" (ramka z tłem), opis przygaszony.
func _add_control(grid: GridContainer, row: Array) -> void:
	var key := UiTheme.label(row[0], 7, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
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
	key.add_theme_stylebox_override("normal", cap)
	key.custom_minimum_size = Vector2(60, 0)
	grid.add_child(key)
	var desc := UiTheme.label(row[1], 8, UiTheme.MUTED)
	desc.custom_minimum_size = Vector2(100, 0)
	grid.add_child(desc)

func _refresh_mode() -> void:
	_mode.text = "MODE: < %s >" % MODE_NAMES[mode]
	var col: Color = [UiTheme.TEXT, UiTheme.OK, UiTheme.DANGER][mode]
	for k in ["font_color", "font_hover_color", "font_disabled_color"]:
		_mode.add_theme_color_override(k, col)
	if _status != null:
		set_status(MODE_HINTS[mode])

func _refresh_difficulty() -> void:
	_diff.text = "DIFFICULTY:  < %s >" % Difficulty.level_name()
	var col: Color = [UiTheme.OK, UiTheme.TEXT, UiTheme.DANGER][Difficulty.level]
	for k in ["font_color", "font_hover_color", "font_disabled_color"]:
		_diff.add_theme_color_override(k, col)
