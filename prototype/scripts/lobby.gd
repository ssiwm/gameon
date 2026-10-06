extends Control
## Lobby: host / join by IP. Built in code with the shared theme.
## main.gd listens to host_requested / join_requested and sets status text.

signal host_requested
signal join_requested(ip: String)
signal steam_host_requested
signal steam_join_requested(lobby_id: String)

const UiTheme := preload("res://scripts/ui_theme.gd")

const CONTROLS := [
	["WASD / Arrows", "Move & aim (mouse aims freely)"],
	["Space", "Jump — hold for higher"],
	["Down + Space", "Drop through a catwalk"],
	["Shift", "Sneak — silent"],
	["J / LMB", "Fire — makes NOISE"],
	["1 2 3 / Wheel", "Switch weapon"],
	["Q", "Overcharge — lure HIM away"],
	["L", "Flashlight — light is noise"],
	["Hold E", "Revive a teammate"],
	["F1", "Show / hide controls in game"],
]

var _ip: LineEdit
var _status: Label
var _host: Button
var _diff: Button
var _steam_host: Button
var _steam_join: Button
var _steam_id: LineEdit

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var card := PanelContainer.new()
	card.position = Vector2(150, 4)
	card.size = Vector2(340, 352)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	box.add_child(UiTheme.label("DEAD AIR '87", 26, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiTheme.label("Co-op horror run & gun  ·  prototype", 9, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_spacer(4))

	var ip_row := HBoxContainer.new()
	ip_row.add_child(UiTheme.label("HOST IP", 9, UiTheme.MUTED))
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "e.g. 192.168.0.12"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip.text_submitted.connect(func(t: String) -> void: join_requested.emit(t.strip_edges()))
	ip_row.add_child(_ip)
	box.add_child(ip_row)

	var btns := HBoxContainer.new()
	_host = Button.new()
	_host.text = "HOST GAME"
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.pressed.connect(func() -> void: host_requested.emit())
	btns.add_child(_host)
	var join := Button.new()
	join.text = "JOIN"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void: join_requested.emit(_ip.text.strip_edges()))
	btns.add_child(join)
	box.add_child(btns)

	# Steam: lobby + zaproszenia (steam_net.gd); bez wtyczki GodotSteam przyciski są wyszarzone
	var steam_row := HBoxContainer.new()
	_steam_host = Button.new()
	_steam_host.text = "STEAM HOST"
	_steam_host.pressed.connect(func() -> void: steam_host_requested.emit())
	steam_row.add_child(_steam_host)
	_steam_id = LineEdit.new()
	_steam_id.placeholder_text = "lobby ID"
	_steam_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steam_id.text_submitted.connect(func(t: String) -> void: steam_join_requested.emit(t.strip_edges()))
	steam_row.add_child(_steam_id)
	_steam_join = Button.new()
	_steam_join.text = "STEAM JOIN"
	_steam_join.pressed.connect(func() -> void: steam_join_requested.emit(_steam_id.text.strip_edges()))
	steam_row.add_child(_steam_join)
	box.add_child(steam_row)
	set_steam_available(false)

	_diff = Button.new()
	_diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff.tooltip_text = "Chosen by the host. Applies to enemies, the stalker, the boss, noise and drops."
	_diff.pressed.connect(func() -> void:
		Difficulty.set_level((Difficulty.level + 1) % Difficulty.NAMES.size())
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	box.add_child(_diff)
	Difficulty.changed.connect(func(_l: int) -> void: _refresh_difficulty())
	_refresh_difficulty()

	_status = UiTheme.label("Host a game, or enter the host's IP and join.", 9, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var sep := HSeparator.new()
	box.add_child(sep)
	box.add_child(UiTheme.label("CONTROLS", 8, UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	for row in CONTROLS:
		grid.add_child(UiTheme.label(row[0], 8, UiTheme.TEXT))
		grid.add_child(UiTheme.label(row[1], 8, UiTheme.MUTED))
	box.add_child(grid)

	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_host.grab_focus())
	_host.call_deferred("grab_focus")

## Przyciski Steam działają tylko z wtyczką GodotSteam i uruchomionym klientem Steam.
func set_steam_available(on: bool) -> void:
	var tip := "Steam lobby + invites (App ID 480 test)" if on else "Needs the GodotSteam addon and the Steam client — see README"
	for c in [_steam_host, _steam_join, _steam_id]:
		c.tooltip_text = tip
	_steam_host.disabled = not on
	_steam_join.disabled = not on
	_steam_id.editable = on

func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.DANGER if is_error else UiTheme.MUTED)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _refresh_difficulty() -> void:
	_diff.text = "DIFFICULTY:  < %s >" % Difficulty.level_name()
	var col: Color = [UiTheme.OK, UiTheme.TEXT, UiTheme.DANGER][Difficulty.level]
	for k in ["font_color", "font_hover_color", "font_disabled_color"]:
		_diff.add_theme_color_override(k, col)

## Klient nie wybiera trudności — ustala ją host (main.gd rozsyła wybór).
func lock_difficulty() -> void:
	_diff.disabled = true
