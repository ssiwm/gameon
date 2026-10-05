extends Control
## Lobby: host / join by IP. Built in code with the shared theme.
## main.gd listens to host_requested / join_requested and sets status text.

signal host_requested
signal join_requested(ip: String)

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
	["F1 / F2", "Controls strip / VHS filter"],
]

var _ip: LineEdit
var _status: Label
var _host: Button

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var card := PanelContainer.new()
	card.position = Vector2(150, 22)
	card.size = Vector2(340, 316)
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

func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.DANGER if is_error else UiTheme.MUTED)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
