extends RefCounted
## Shared UI theme: readable in the dark (outlined text), consistent panels,
## buttons and inputs. Built in code so the look lives in one place.

const ACCENT := Color(1.0, 0.72, 0.28)        ## amber — objectives, highlights
const DANGER := Color(1.0, 0.28, 0.22)
const OK := Color(0.45, 1.0, 0.55)
const TEXT := Color(0.92, 0.92, 0.94)
const MUTED := Color(0.62, 0.64, 0.68)
const PANEL_BG := Color(0.03, 0.035, 0.05, 0.72)
const PANEL_EDGE := Color(1, 1, 1, 0.08)

static var _theme: Theme

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 10

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 3)

	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())

	var normal := _box(Color(0.10, 0.11, 0.14, 0.95), Color(1, 1, 1, 0.10))
	var hover := _box(Color(0.16, 0.15, 0.13, 0.98), ACCENT.darkened(0.2))
	var pressed := _box(Color(0.22, 0.17, 0.08, 1.0), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 1)
	for s in [normal, hover, pressed]:
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 5
		s.content_margin_bottom = 5
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_font_size("font_size", "Button", 11)

	var edit := _box(Color(0.02, 0.025, 0.035, 0.95), Color(1, 1, 1, 0.14))
	edit.content_margin_left = 8
	edit.content_margin_right = 8
	edit.content_margin_top = 4
	edit.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), ACCENT, 1))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.3))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 11)

	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	_theme = t
	return t

static func panel_box() -> StyleBoxFlat:
	var b := _box(PANEL_BG, PANEL_EDGE)
	b.set_corner_radius_all(4)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b

static func _box(bg: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(width)
	b.set_corner_radius_all(3)
	return b

## Label helper with size/colour in one call.
static func label(text: String, size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
