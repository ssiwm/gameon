extends Control
## Menu główne w stylu makiety Main.dc.html: nocny las (menu_scene.gd), tytuł „DEAD AIR '87”, lista punktów z podpisami
## i czerwonym znacznikiem aktywnego, panel „Squad link” po prawej i podpowiedzi klawiszy u dołu.
## HOST GAME / JOIN GAME / NIGHT SHIFT otwierają lobby ustawione na odpowiedni wpis (`entry`); SETTINGS otwiera menu pauzy
## w trybie ustawień, QUIT prosi o potwierdzenie. Pokazuje je main.gd po starcie, gdy gra nie hostuje / nie dołącza z linii poleceń.
##
## Współrzędne w pikselach makiety 1280×720 (korzeń skalowany jak w pause_menu.gd).

signal play_requested                ## otwórz lobby (patrz `entry`)
signal settings_requested

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Scene := preload("res://scripts/menu_scene.gd")
const Actions := preload("res://scripts/actions.gd")
const QUIT_CONFIRM_S := 3.0

## Który wpis otworzył lobby: "host", "join" albo "night" (""/inne = domyślnie host). Czyta go main.gd.
var entry := ""

var _scene: Control
var _root: Control                   ## treść w jednostkach makiety
var _title: Label
var _items: Array = []
var _quit: Control
var _quit_t := 0.0
var _t := 0.0
var _steam_dot: Label
var _players: Label
var _diff_label: Label
var _oper: Label
var _note: Label
var _steam_on := false
var _squad: Control
var _foot: Control
var _nav: Control
var _title_box: Control

## Pozycja listy: etykieta stencil 30 px i podpis mono po prawej; aktywna (fokus / mysz) ma czerwony pasek, trójkąt i poświatę.
class Item extends Control:
	signal pressed
	var label := ""
	var sub := ""
	func _init() -> void:
		custom_minimum_size = Vector2(0, 48)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_ENTER and is_visible_in_tree():
			grab_focus()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()
	func _draw() -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		var on := has_focus()
		var lab := tr(label)
		var f := UT.display_font(700, 2)
		var sf := UT.mono_font()
		if on:
			draw_rect(Rect2(0, 0, 2, size.y), UT.DANGER)
			var c0 := Color(UT.DANGER, 0.16)
			var c1 := Color(UT.DANGER, 0.0)
			draw_polygon(PackedVector2Array([Vector2(2, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(2, size.y)]),
				PackedColorArray([c0, c1, c1, c0]))
			draw_colored_polygon(PackedVector2Array([Vector2(14, size.y * 0.5 - 6), Vector2(24, size.y * 0.5), Vector2(14, size.y * 0.5 + 6)]), UT.DANGER)
		var x := 38.0 if on else 28.0
		var col: Color = Color("f1ecdc") if on else Color("9c9988")
		draw_string(f, Vector2(x, size.y * 0.5 + 10.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
		if sub != "":
			draw_string(sf, Vector2(0, size.y * 0.5 + 4.5), tr(sub), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 16.0, 12,
				Color("bdb8a6") if on else Color("7d7a6d"))

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scene = Scene.new()
	add_child(_scene)
	_root = Control.new()
	add_child(_root)
	_build_title()
	_build_nav()
	_build_squad_panel()
	_build_footer()
	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_fit)
	Difficulty.changed.connect(func(_l: int) -> void: _refresh())
	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_refresh()
			_items[0].grab_focus())
	_fit()
	_refresh()
	_items[0].call_deferred("grab_focus")

func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(vp.x / 1280.0, vp.y / 720.0)       # układ ma sztywną siatkę 1280×720 — rozmiar HUD-u go nie powiększa (lista wychodziła poza ekran)
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	size = vp
	_scene.fit(vp)
	_layout()

func _layout() -> void:
	var w := _root.size.x
	var h := _root.size.y
	_squad.position = Vector2(w - 72.0 - 300.0, 78.0)
	_foot.size = Vector2(w - 88.0 - 72.0, 0)
	_foot.position = Vector2(88.0, h - 34.0 - 20.0)
	_nav.position = Vector2(88.0, 352.0)
	_title_box.position = Vector2(88.0, 74.0)

func _build_title() -> void:
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 6)
	_root.add_child(_title_box)
	_title_box.add_child(W.mono("DON'T MAKE A SOUND", 13, UiTheme.MUTED, 0.34))
	_title = W.stencil("DEAD AIR", 132, Color("d9d4c3"), 0.01, HORIZONTAL_ALIGNMENT_LEFT, 900)
	_title.custom_minimum_size = Vector2(520, 116)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var yr := W.stencil("'87", 64, UiTheme.DANGER, 0.0, HORIZONTAL_ALIGNMENT_LEFT, 900)
	yr.add_theme_color_override("font_outline_color", Color(UiTheme.DANGER, 0.35))
	yr.add_theme_constant_override("outline_size", 6)
	row.add_child(yr)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(200, 1)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.draw.connect(func() -> void:
		rule.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 1), Vector2(0, 1)]),
			PackedColorArray([UiTheme.DANGER, Color(UiTheme.DANGER, 0.0), Color(UiTheme.DANGER, 0.0), UiTheme.DANGER])))
	row.add_child(rule)
	var ns := W.mono("NO SIGNAL", 12, UiTheme.MUTED, 0.2)
	ns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ns)
	_title_box.add_child(row)

func _build_nav() -> void:
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(440, 0)
	nav.add_theme_constant_override("separation", 2)
	_root.add_child(nav)
	_nav = nav
	_add_item(nav, "HOST GAME", "LAN / STEAM", func() -> void: _play("host"))
	_add_item(nav, "JOIN GAME", "IP OR LOBBY ID", func() -> void: _play("join"))
	_add_item(nav, "NIGHT SHIFT", "ENDLESS · 5 MISSIONS", func() -> void: _play("night"))
	_add_item(nav, "SETTINGS", "", func() -> void: settings_requested.emit())
	_quit = _add_item(nav, "QUIT", "", _on_quit)
	for i in _items.size():
		var it: Control = _items[i]
		it.focus_neighbor_top = _items[(i - 1 + _items.size()) % _items.size()].get_path()
		it.focus_neighbor_bottom = _items[(i + 1) % _items.size()].get_path()

func _add_item(parent: Control, label: String, sub: String, action: Callable) -> Item:
	var it := Item.new()
	it.label = label
	it.sub = sub
	it.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		action.call())
	parent.add_child(it)
	_items.append(it)
	return it

func _play(which: String) -> void:
	entry = which
	play_requested.emit()

func _on_quit() -> void:
	if _quit_t > 0.0:
		get_tree().quit()
		return
	_quit_t = QUIT_CONFIRM_S
	(_quit as Item).label = "CLICK AGAIN TO QUIT"
	_quit.queue_redraw()

## Panel „Squad link”: stan Steama, liczba graczy, trudność (klik przełącza), poziom operatora i szept z radia.
func _build_squad_panel() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(300, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(6.0 / 255.0, 7.0 / 255.0, 6.0 / 255.0, 0.78)
	sb.border_color = UiTheme.LINE
	sb.set_border_width_all(1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	_squad = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var head := HBoxContainer.new()
	var hl := W.mono("SQUAD LINK", 12, UiTheme.MUTED, 0.22)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	_steam_dot = W.mono("● STEAM OFFLINE", 12, UiTheme.MUTED)
	head.add_child(_steam_dot)
	v.add_child(head)
	_players = _kv(v, "Players", "1 / 4  +1 AI")
	_diff_label = _kv(v, "Difficulty", "")
	_diff_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_diff_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_diff_label.tooltip_text = tr("Chosen by the host. Applies to enemies, the stalker, the boss, noise and drops.")
	_diff_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Difficulty.set_level((Difficulty.level + 1) % Difficulty.NAMES.size())
			Audio.play("ui_click", Audio.BUS_UI, -10.0))
	_oper = _kv(v, "Operator", "")
	v.add_child(W.hairline(UiTheme.LINE))
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	sec.add_child(W.mono("LAST BROADCAST", 12, UiTheme.MUTED, 0.18))
	_note = W.whisper("", 14, Color("bdb8a6"))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(264, 0)
	sec.add_child(_note)
	v.add_child(sec)

func _kv(parent: Control, key: String, val: String) -> Label:
	var r := HBoxContainer.new()
	var k := W.body(key, 15, UiTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(k)
	var vl := W.mono(val, 14, UiTheme.TEXT)
	r.add_child(vl)
	parent.add_child(r)
	return vl

func _build_footer() -> void:
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 18)
	_root.add_child(f)
	_foot = f
	var ver := W.mono(tr("v0.1 PROTOTYPE · EARLY ACCESS BUILD"), 12, Color("7d7a6d"), 0.06)
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_child(ver)
	for pair in [["↑↓", "SELECT"], ["ENTER", "CONFIRM"], ["ESC", "SETTINGS"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(W.keycap(pair[0], 12))
		h.add_child(W.mono(pair[1], 12, UiTheme.MUTED))
		f.add_child(h)

func set_steam_available(on: bool) -> void:
	_steam_on = on
	_refresh()

func _refresh() -> void:
	if _steam_dot == null:
		return
	_steam_dot.text = "● " + tr("STEAM ONLINE") if _steam_on else "● " + tr("STEAM OFFLINE")
	_steam_dot.add_theme_color_override("font_color", UiTheme.OK if _steam_on else UiTheme.MUTED)
	var col: Color = [UiTheme.OK, UiTheme.TEXT, UiTheme.DANGER][clampi(Difficulty.level, 0, 2)]
	_diff_label.text = "<  %s  >" % tr(Difficulty.level_name())
	_diff_label.add_theme_color_override("font_color", col)
	var pr := get_node_or_null("/root/Profile")
	if pr != null:
		var prog: Array = pr.level_progress()
		_oper.text = "LV %d  ·  %d / %d XP" % [pr.level(), int(prog[0]), int(prog[1])]
	if _note.text == "":
		_note.text = tr(_NOTES[int(Time.get_ticks_msec() / 1000) % _NOTES.size()])

const _NOTES := [
	"Extraction complete. Nobody went down. It heard us anyway.",
	"Patrol Seven, do you read? ...we went into the trees.",
	"Don't shoot unless you must. Noise carries.",
	"Crouch and the dark can't hear you.",
	"If you hear it breathing, it has already found you.",
]

func focus_first() -> void:
	_items[0].grab_focus()

func _process(delta: float) -> void:
	if visible and NoiseMgr.has_network():
		visible = false                  # sesja ruszyła inną drogą niż PLAY (zaproszenie Steam, dołączenie) — menu nie może zostać na wierzchu
	if not visible:
		return
	if _quit_t > 0.0:
		_quit_t -= delta
		if _quit_t <= 0.0:
			(_quit as Item).label = "QUIT"
			_quit.queue_redraw()
	# tytuł lekko „migocze" — rzadkie, krótkie zaniki; „Reduce effects" wyłącza to razem z resztą
	_t += delta
	var dip := 0.6 if (Settings.fx_mult() > 0.0 and (fmod(_t, 7.3) < 0.09 or (fmod(_t, 11.9) > 11.7 and fmod(_t, 0.07) < 0.035))) else 1.0
	_title.modulate.a = dip
