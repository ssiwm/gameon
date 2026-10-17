extends Control
## Dziennik komunikatów (MESSAGES_PLAN.md, etap 4): ostatnie wpisy z `Msg.journal` (najnowsze u góry, z czasem sesji) i spis odkrytych porad.
## Przegapiony komunikat albo porada nie przepadają: klawisz dziennika (akcja `journal`) otwiera panel, ten sam klawisz albo Esc go zamyka.
## Gra toczy się dalej pod panelem (koop w sieci nie pauzuje), więc to lekki, półprzezroczysty podgląd, który nie przechwytuje wejścia.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Hints := preload("res://scripts/hints.gd")
const Actions := preload("res://scripts/actions.gd")

const PANEL_W := 470.0
const LIST_H := 270.0
const BG := Color(0.043, 0.047, 0.043, 0.94)

var open := false

var _panel: PanelContainer
var _head_key: Label
var _list: VBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 9
	_build()

func _ready() -> void:
	Msg.journaled.connect(func(_e: Dictionary) -> void:
		if open:
			refresh())

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = UiTheme.LINE2
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_content_margin_all(10.0)
	if UiTheme.hd_on():
		sb.set_corner_radius_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	var title := UiTheme.heading(tr("JOURNAL"), UiTheme.T_TITLE, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_head_key = UiTheme.mono(UiTheme.label("", UiTheme.T_CAPTION, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	head.add_child(_head_key)
	box.add_child(head)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.1)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(PANEL_W - 22.0, LIST_H)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.custom_minimum_size = Vector2(PANEL_W - 30.0, 0)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(_list)

func set_open(v: bool) -> void:
	open = v
	visible = v
	if v:
		refresh()

func _style_col(style: int) -> Color:
	match style:
		Msg.Style.DANGER:
			return UiTheme.DANGER
		Msg.Style.SUCCESS:
			return UiTheme.OK
		Msg.Style.WARN:
			return UiTheme.WARM
		Msg.Style.ACTION:
			return UiTheme.ACCENT
	return UiTheme.BONE_DIM

func _section(text: String) -> void:
	var l := UiTheme.mono(UiTheme.label(text, UiTheme.T_CAPTION, UiTheme.MUTED))
	l.custom_minimum_size = Vector2(0, 14)
	_list.add_child(l)

func _row(stamp: String, text: String, sub: String, col: Color) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 7)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(3, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(bar)
	var t := UiTheme.mono(UiTheme.label(stamp, UiTheme.T_CAPTION, UiTheme.MUTED))
	t.custom_minimum_size = Vector2(34, 0)
	r.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main := UiTheme.label(text, UiTheme.T_BODY - 1, UiTheme.TEXT)
	main.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.custom_minimum_size = Vector2(PANEL_W - 90.0, 0)
	v.add_child(main)
	if sub != "":
		var s := UiTheme.label(sub, UiTheme.T_CAPTION, UiTheme.MUTED)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(PANEL_W - 90.0, 0)
		v.add_child(s)
	r.add_child(v)
	_list.add_child(r)

static func _mmss(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]

func refresh() -> void:
	_head_key.text = Actions.fmt(tr("[{journal}]  close"))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_section(tr("MESSAGES"))
	var j: Array = Msg.journal
	if j.is_empty():
		_row("", tr("Nothing yet"), "", UiTheme.LINE2)
	for i in range(j.size() - 1, -1, -1):
		var e: Dictionary = j[i]
		_row(_mmss(float(e["t"])), String(e["text"]), String(e["sub"]), _style_col(int(e["style"])))
	var seen := 0
	for tip in Hints.TIPS:
		if Settings.tip_seen(String(tip[0])):
			seen += 1
	_section(tr("TIPS FOUND") + "  %d / %d" % [seen, Hints.TIPS.size()])
	for tip in Hints.TIPS:
		if Settings.tip_seen(String(tip[0])):
			_row("", Actions.fmt(tr(String(tip[1]))), "", UiTheme.ACCENT)

func _process(_delta: float) -> void:
	if not open:
		return
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, maxf(MARGINTOP, (size.y - _panel.size.y) * 0.4))

const MARGINTOP := 40.0
