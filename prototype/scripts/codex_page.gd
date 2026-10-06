extends HBoxContainer
## Strona kodeksu w menu pauzy: lista pozycji po lewej, szczegóły po prawej (portret, statystyki, opis, wskazówka).
## Dane dostarcza codex.gd; ten sam widok służy bestiariuszowi i broniom.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Portrait := preload("res://scripts/codex_portrait.gd")

const LIST_W := 128.0
const DETAIL_W := 290.0
const PORTRAIT_H := 84.0
const THUMB_W := 34.0
const THUMB_H := 20.0

var _entries: Array = []
var _buttons: Array[Button] = []
var _portrait: Portrait
var _title: Label
var _tag: Label
var _stats: GridContainer
var _text: Label
var _tip: Label
var _sel := -1

func setup(entries: Array) -> void:
	_entries = entries
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(LIST_W + DETAIL_W + 8.0, 0)
	# lista
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in entries.size():
		var b := Button.new()
		b.text = entries[i]["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 8)
		b.custom_minimum_size = Vector2(0, THUMB_H + 2.0)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBox = get_theme_stylebox(state, "Button").duplicate()
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			sb.content_margin_left = THUMB_W + 8.0           # miejsce na miniaturę
			b.add_theme_stylebox_override(state, sb)
		var th := Portrait.new()
		th.thumb = true
		th.position = Vector2(2, 1)
		th.size = Vector2(THUMB_W, THUMB_H)
		th.show_spec(entries[i]["portrait"], entries[i]["accent"])
		b.add_child(th)
		b.pressed.connect(select.bind(i))
		list.add_child(b)
		_buttons.append(b)
	# szczegóły
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_theme_constant_override("separation", 3)
	add_child(detail)
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(0, PORTRAIT_H)
	detail.add_child(_portrait)
	_title = UiTheme.label("", 14, UiTheme.ACCENT)
	detail.add_child(_title)
	_tag = UiTheme.label("", 8, UiTheme.MUTED)
	detail.add_child(_tag)
	_stats = GridContainer.new()
	_stats.columns = 4
	_stats.add_theme_constant_override("h_separation", 8)
	_stats.add_theme_constant_override("v_separation", 1)
	detail.add_child(_stats)
	_text = UiTheme.label("", 8, UiTheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_child(_text)
	_tip = UiTheme.label("", 8, UiTheme.ACCENT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_child(_tip)
	select(0)

func select(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	_sel = i
	for j in _buttons.size():
		_buttons[j].set_pressed_no_signal(j == i)
	var e: Dictionary = _entries[i]
	_portrait.show_spec(e["portrait"], e["accent"])
	_title.text = e["title"]
	_tag.text = e["tag"]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	for st in e["stats"]:
		_stats.add_child(UiTheme.label(st[0], 8, UiTheme.MUTED))
		_stats.add_child(UiTheme.label(st[1], 8, UiTheme.TEXT))
	_text.text = e["text"]
	_tip.text = "TIP  " + e["tip"]
