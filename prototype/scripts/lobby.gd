extends Control
## Lobby: host / join (LAN po IP, Steam po lobby ID), trudność, mikrofon, tryb startu (kampania / kryjówka / Nocny Dyżur), ściąga sterowania.
## Budowane w kodzie w stylu deski z makiety (ui_widgets.gd) na tym samym tle co menu główne (menu_scene.gd). main.gd słucha
## sygnałów i ustawia status.
##
## Układ w pikselach makiety 1280×720: nagłówek → dwie kolumny (POŁĄCZENIE: host / IP / Steam | OPCJE: trudność, mikrofon, tryb)
## → status → STEROWANIE w trzech kolumnach → stopka (BACK, SETTINGS).

signal host_requested
signal join_requested(ip: String)
signal steam_host_requested
signal steam_join_requested(lobby_id: String)
signal back_requested                ## wróć do menu głównego
signal settings_requested            ## ustawienia (menu pauzy w trybie ustawień)

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Scene := preload("res://scripts/menu_scene.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Actions := preload("res://scripts/actions.gd")

const REF_SCALE := 0.5
const CARD_W := 1060.0

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

var _scene: Control
var _root: Control
var _card: Control
var _ip: LineEdit
var _status: Label
var _host: Button
var _diff: W.Segmented
var _mode: W.Segmented
var _mic: W.Segmented
var _steam_host: Button
var _steam_join: Button
var _steam_id: LineEdit
var _back: Button
var _title: Label
var _t := 0.0

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scene = Scene.new()
	add_child(_scene)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_root = Control.new()
	add_child(_root)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	var deck := StyleBoxFlat.new()
	deck.bg_color = Color(7.0 / 255.0, 8.0 / 255.0, 7.0 / 255.0, 0.94)
	deck.border_color = UiTheme.LINE
	deck.set_border_width_all(1)
	deck.shadow_size = 40
	deck.shadow_color = Color(0, 0, 0, 0.6)
	deck.shadow_offset = Vector2(0, 20)
	deck.set_content_margin_all(0)
	_card.add_theme_stylebox_override("panel", deck)
	_root.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)

	col.add_child(_build_header())
	col.add_child(W.hairline())
	col.add_child(_pad(_build_columns(), 26, 18, 26, 8))
	col.add_child(_pad(_build_status(), 26, 0, 26, 8))
	col.add_child(W.hairline())
	col.add_child(_pad(_build_controls(), 26, 12, 26, 10))
	col.add_child(W.hairline())
	col.add_child(_build_footer())

	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_fit)
	_fit()
	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_host.grab_focus())
	_host.call_deferred("grab_focus")

func _fit() -> void:
	var vp := get_viewport_rect().size
	_card.reset_size()
	var card := Vector2(CARD_W, _card.get_combined_minimum_size().y)
	var k := minf(REF_SCALE * Settings.ui_mult(), minf(vp.x / (card.x + 40.0), vp.y / (card.y + 24.0)))
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	size = vp
	_scene.fit(vp)
	_card.size = card
	_card.position = ((_root.size - card) * 0.5).floor()

func _pad(c: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(c)
	return m

# ---------------------------------------------------------------- sekcje

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_title = W.stencil("DEAD AIR '87", 40, UiTheme.TEXT, 0.1, HORIZONTAL_ALIGNMENT_LEFT, 900)
	row.add_child(_title)
	var sub := W.mono("Co-op horror run & gun  ·  prototype", 12, UiTheme.MUTED, 0.16)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(sub)
	return _pad(row, 26, 14, 26, 10)

func _build_columns() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	h.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	_build_multiplayer(left)
	_build_options(right)
	return h

## Dwa wiersze [przycisk | pole | przycisk]: LAN po IP i Steam po ID lobby.
func _build_multiplayer(box: VBoxContainer) -> void:
	box.add_child(W.section(tr("MULTIPLAYER")))
	_host = Button.new()
	_host.text = "HOST GAME"
	W.style_button(_host, "primary", 22)
	_host.custom_minimum_size.x = 170
	_host.pressed.connect(func() -> void: host_requested.emit())
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = tr("host IP, e.g. 192.168.0.12")
	_ip.tooltip_text = tr("LAN / direct: the host's IP address (port 8910)")
	W.style_edit(_ip)
	_ip.text_submitted.connect(func(t: String) -> void: join_requested.emit(t.strip_edges()))
	var join := Button.new()
	join.text = "JOIN"
	W.style_button(join, "secondary", 20)
	join.custom_minimum_size.x = 140
	join.pressed.connect(func() -> void: join_requested.emit(_ip.text.strip_edges()))
	box.add_child(_connect_row(_host, _ip, join))

	_steam_host = Button.new()
	_steam_host.text = "STEAM HOST"
	W.style_button(_steam_host, "secondary", 20)
	_steam_host.custom_minimum_size.x = 170
	_steam_host.pressed.connect(func() -> void: steam_host_requested.emit())
	_steam_id = LineEdit.new()
	_steam_id.placeholder_text = tr("Steam lobby ID")
	W.style_edit(_steam_id)
	_steam_id.text_submitted.connect(func(t: String) -> void: steam_join_requested.emit(t.strip_edges()))
	_steam_join = Button.new()
	_steam_join.text = "STEAM JOIN"
	W.style_button(_steam_join, "secondary", 20)
	_steam_join.custom_minimum_size.x = 140
	_steam_join.pressed.connect(func() -> void: steam_join_requested.emit(_steam_id.text.strip_edges()))
	box.add_child(_connect_row(_steam_host, _steam_id, _steam_join))
	set_steam_available(false)

func _connect_row(left: Button, field: LineEdit, right: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(field)
	row.add_child(right)
	return row

## Trudność, mikrofon (VAD, opt-in) i tryb startu. Trudność i tryb wybiera host.
func _build_options(box: VBoxContainer) -> void:
	box.add_child(W.section(tr("OPTIONS")))
	_diff = _seg_row(box, tr("Difficulty"), Difficulty.NAMES, tr("Chosen by the host. Applies to enemies, the stalker, the boss, noise and drops."))
	_diff.selected.connect(func(i: int) -> void:
		Difficulty.set_level(i)
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	Difficulty.changed.connect(func(_l: int) -> void: _diff.set_index(Difficulty.level))
	_diff.set_index(Difficulty.level)
	_mode = _seg_row(box, tr("Mode"), MODE_NAMES, tr("Chosen by the host. Click to cycle: campaign, safe room, night shift."))
	_mode.selected.connect(func(i: int) -> void:
		mode = i
		NightShift.selected = mode == Mode.NIGHT_SHIFT
		_refresh_mode()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	_mic = _seg_row(box, tr("Microphone scream"), ["OFF", "LOW", "MED", "HIGH"],
		tr("Shout into the microphone to scream (same as G). Processed locally, never recorded. Click: OFF > LOW > MED > HIGH sensitivity."))
	_mic.selected.connect(func(i: int) -> void:
		for _k in 4:
			if _mic_idx() == i:
				break
			Voice.cycle()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	Voice.changed.connect(func() -> void: _mic.set_index(_mic_idx()))
	_mic.set_index(_mic_idx())
	_refresh_mode()

func _mic_idx() -> int:
	return (1 + Voice.sens) if Voice.enabled else 0

func _seg_row(box: VBoxContainer, label: String, options: Array, tip: String) -> W.Segmented:
	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(0, 30)
	var l := W.body(label, 16, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(l)
	var names: Array = []
	for o in options:
		names.append(tr(String(o)))
	var s := W.Segmented.new()
	s.setup(names)
	s.tooltip_text = tip
	r.add_child(s)
	box.add_child(r)
	return s

## Stała wysokość: układ nie skacze, gdy komunikat zajmuje dwie linie. Bez błędu pokazuje opis wybranego trybu.
func _build_status() -> Control:
	_status = W.body(tr(DEFAULT_HINT), 15, UiTheme.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(CARD_W - 52.0, 40)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return _status

## Trzy kolumny par [klawisz | opis]; klawisze z rejestru akcji (`actions.gd`).
func _build_controls() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(W.section(tr("CONTROLS")))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	_fill_controls(cols)
	InputSetup.device_changed.connect(func(_pad: bool) -> void: _fill_controls(cols))
	Settings.bindings_changed.connect(func() -> void: _fill_controls(cols))
	return v

func _fill_controls(cols: HBoxContainer) -> void:
	for c in cols.get_children():
		cols.remove_child(c)
		c.queue_free()
	var rows: Array = Actions.sheet()
	var per_col := (rows.size() + 2) / 3
	for c in 3:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 5)
		cols.add_child(colv)
		for i in per_col:
			var idx := i + c * per_col
			if idx >= rows.size():
				break
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var kc := W.keycap(String(rows[idx][0]), 12)
			kc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var kh := HBoxContainer.new()
			kh.custom_minimum_size = Vector2(124, 0)
			kh.add_child(kc)
			row.add_child(kh)
			var d := W.body(String(rows[idx][1]), 14, UiTheme.MUTED)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(d)
			colv.add_child(row)

## Dolny rząd: BACK (do menu głównego; tylko gdy main.gd je pokazuje) i SETTINGS.
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_back = Button.new()
	_back.text = "BACK"
	W.style_button(_back, "secondary", 22)
	_back.visible = false
	_back.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		back_requested.emit())
	row.add_child(_back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var st := Button.new()
	st.text = "SETTINGS"
	W.style_button(st, "secondary", 22)
	st.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		settings_requested.emit())
	row.add_child(st)
	return _pad(row, 26, 12, 26, 12)

## BACK ma sens tylko, gdy istnieje menu główne.
func set_back_enabled(on: bool) -> void:
	_back.visible = on

## Wejście z menu głównego: "host" / "join" (pole IP) / "night" (Nocny Dyżur wybrany od razu).
func enter(which: String) -> void:
	if which == "night":
		mode = Mode.NIGHT_SHIFT
		NightShift.selected = true
		_refresh_mode()
	if which == "join":
		_ip.call_deferred("grab_focus")
		_ip.call_deferred("select_all")
	else:
		_host.call_deferred("grab_focus")

## Tytuł lekko „migocze" — rzadkie, krótkie zaniki jak przy słabym kontakcie (klimat, nie szum).
func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var dip := 0.55 if (Settings.fx_mult() > 0.0 and (fmod(_t, 7.3) < 0.09 or (fmod(_t, 11.9) > 11.7 and fmod(_t, 0.07) < 0.035))) else 1.0
	_title.modulate.a = dip

func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.DANGER if is_error else UiTheme.MUTED)

## Przyciski Steam działają tylko z wtyczką GodotSteam i uruchomionym klientem Steam.
func set_steam_available(on: bool) -> void:
	var tip := tr("Steam lobby + invites (App ID 480 test)") if on else tr("Needs the GodotSteam addon and the Steam client — see README")
	for c in [_steam_host, _steam_join, _steam_id]:
		c.tooltip_text = tip
	_steam_host.disabled = not on
	_steam_join.disabled = not on
	_steam_id.editable = on

## Klient nie wybiera trudności — ustala ją host (main.gd rozsyła wybór).
func lock_difficulty() -> void:
	_diff.set_locked(true)
	_mode.set_locked(true)

func _refresh_mode() -> void:
	_mode.set_index(mode)
	if _status != null:
		set_status(tr(MODE_HINTS[mode]))
