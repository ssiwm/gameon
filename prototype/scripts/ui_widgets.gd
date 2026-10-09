extends RefCounted
## Widgety systemu projektowego „Dead Air deck” (UI_PLAN.md / makieta System.dc.html). Wymiary w pikselach referencyjnego ekranu
## 1280×720 — ekran, który ich używa, skaluje korzeń tak, żeby 1 jednostka = 1 piksel makiety (pause_menu.gd, lobby.gd).
##
## Kolory: kość (TEXT) na niemal czarnym tle; krew (DANGER) tylko dla tytułu, aktywnego punktu menu i zagrożenia;
## lampa (ACCENT) dla bezpiecznych miejsc i nagród.

const UiTheme := preload("res://scripts/ui_theme.gd")

# ---------------------------------------------------------------- tekst

## Etykieta z podanym krojem; `spacing` — rozstrzelenie liter w em (np. 0.1).
static func text(s: String, size: int, color: Color, font: Font = null, spacing := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = s
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	if font != null:
		if spacing != 0.0:
			var fv := FontVariation.new()
			fv.base_font = font
			fv.spacing_glyph = int(round(float(size) * spacing))
			l.add_theme_font_override("font", fv)
		else:
			l.add_theme_font_override("font", font)
	return l

static func stencil(s: String, size: int, color: Color = UiTheme.TEXT, spacing := 0.08, align := HORIZONTAL_ALIGNMENT_LEFT, weight := 700) -> Label:
	var l := text(s, size, color, null, 0.0, align)
	l.add_theme_font_override("font", UiTheme.display_font(weight, int(round(float(size) * spacing))))
	return l

static func mono(s: String, size: int, color: Color = UiTheme.MUTED, spacing := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return text(s, size, color, UiTheme.mono_font(), spacing, align)

static func body(s: String, size: int, color: Color = UiTheme.TEXT) -> Label:
	return text(s, size, color)

static func whisper(s: String, size: int, color: Color = UiTheme.BONE_DIM) -> Label:
	return text(s, size, color, UiTheme.whisper_font())

static func hairline(color: Color = UiTheme.HAIR) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func vline(color: Color = UiTheme.HAIR) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(1, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Nagłówek sekcji: rozstrzelony mono + linia do końca wiersza.
static func section(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(mono(title, 12, UiTheme.MUTED, 0.24))
	var r := hairline()
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(r)
	return h

## Kapsel klawisza: ciemne tło, ramka z grubszym dołem.
static func keycap(s: String, size := 12, on_light := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0) if on_light else Color("0d0e0c")
	sb.border_color = UiTheme.DECK_BG if on_light else UiTheme.LINE2
	sb.set_border_width_all(1)
	sb.border_width_bottom = 1 if on_light else 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(mono(s, size, UiTheme.DECK_BG if on_light else UiTheme.TEXT))
	return p

## Chip: mono w ramce (np. CO-OP · THE WORLD KEEPS RUNNING).
static func chip(s: String, color: Color, border: Color, pulse_dot := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if pulse_dot:
		var d := Dot.new()
		d.color = color
		h.add_child(d)
	h.add_child(mono(s, 12, color, 0.1))
	p.add_child(h)
	return p

# ---------------------------------------------------------------- przyciski

## Styl przycisku: "primary" (kość, ciemny tekst), "secondary" (ramka), "danger" (ramka i tekst w kolorze krwi).
static func style_button(b: Button, kind: String, font_size := 22) -> void:
	var fill := Color(0, 0, 0, 0)
	var border := UiTheme.LINE2
	var fg := UiTheme.TEXT
	match kind:
		"primary":
			fill = UiTheme.TEXT
			border = UiTheme.TEXT
			fg = UiTheme.DECK_BG
		"danger":
			border = UiTheme.BLOOD_LINE
			fg = UiTheme.DANGER
	var normal := _box(fill, border)
	var hover := _box(fill.lerp(Color.WHITE, 0.0) if kind == "primary" else Color(1, 1, 1, 0.04), UiTheme.BONE_DIM if kind != "danger" else UiTheme.DANGER)
	if kind == "primary":
		hover = _box(UiTheme.WARM, UiTheme.WARM)
	var pressed := _box(Color(1, 1, 1, 0.1) if kind != "primary" else UiTheme.BONE_DIM, border)
	var focus := _box(Color(0, 0, 0, 0), UiTheme.TEXT, 2)
	var disabled := _box(Color(0, 0, 0, 0), UiTheme.HAIR)
	for s in [normal, hover, pressed, disabled]:
		s.content_margin_left = 24
		s.content_margin_right = 24
		s.content_margin_top = 8
		s.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg if kind == "primary" else (UiTheme.DANGER if kind == "danger" else Color("f1ecdc")))
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", Color("5d5b50"))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", UiTheme.display_font(900 if kind == "primary" else 700, int(round(float(font_size) * 0.1))))
	b.add_theme_constant_override("outline_size", 0)
	b.custom_minimum_size.y = 46

static func _box(bg: Color, edge: Color, width := 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(width)
	return b

# ---------------------------------------------------------------- klasy

## Pulsująca kropka (znacznik „świat idzie dalej").
class Dot extends Control:
	var color := Color.WHITE
	var _t := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(7, 7)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		_t += delta * (0.0 if Settings.fx_mult() <= 0.0 else 1.0)
		queue_redraw()
	func _draw() -> void:
		var a := 0.5 + 0.5 * (0.5 + 0.5 * sin(_t * 4.5))
		draw_circle(Vector2(3.5, 3.5), 3.5, Color(color, a))

## Przełącznik 42×22: ramka, kwadratowa gałka; włączony = kość.
class Toggle extends Control:
	signal toggled(on: bool)
	var on := false
	func _init() -> void:
		custom_minimum_size = Vector2(42, 22)
		focus_mode = Control.FOCUS_ALL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func set_on(v: bool) -> void:
		if on != v:
			on = v
			queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			toggled.emit(not on)
			accept_event()
	func _draw() -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		draw_rect(Rect2(Vector2.ZERO, size), Color("1c1c18") if on else Color("0d0e0c"))
		draw_rect(Rect2(Vector2.ZERO, size), UT.TEXT if on else UT.LINE2, false, 1.0)
		var k := Rect2(Vector2(size.x - 17.0, 4.0) if on else Vector2(3.0, 4.0), Vector2(14, 14))
		draw_rect(k, UT.TEXT if on else Color("7d7a6d"))
		if has_focus():
			draw_rect(Rect2(-3, -3, size.x + 6, size.y + 6), UT.TEXT, false, 2.0)

## Segmenty: ramka z opcjami mono; aktywna wypełniona kością.
class Segmented extends PanelContainer:
	signal selected(i: int)
	var _buttons: Array[Button] = []
	var index := 0
	func setup(options: Array) -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = UT.LINE2
		sb.set_border_width_all(1)
		add_theme_stylebox_override("panel", sb)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 0)
		add_child(h)
		for i in options.size():
			var b := Button.new()
			b.text = String(options[i])
			b.focus_mode = Control.FOCUS_ALL
			b.add_theme_font_override("font", UT.mono_font())
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(func() -> void: selected.emit(i))
			h.add_child(b)
			_buttons.append(b)
		set_index(0)
	func set_index(i: int) -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		index = i
		for k in _buttons.size():
			var b := _buttons[k]
			var on := k == i
			var st := StyleBoxFlat.new()
			st.bg_color = UT.TEXT if on else Color(0, 0, 0, 0)
			st.content_margin_left = 10
			st.content_margin_right = 10
			st.content_margin_top = 3
			st.content_margin_bottom = 3
			if k > 0:
				st.border_color = UT.LINE
				st.border_width_left = 1
			var fo := st.duplicate() as StyleBoxFlat
			fo.border_color = UT.TEXT
			fo.set_border_width_all(2)
			fo.bg_color = st.bg_color
			for name in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(name, st)
			b.add_theme_stylebox_override("focus", fo)
			var c: Color = UT.DECK_BG if on else Color("7d7a6d")
			for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(name, c if name != "font_hover_color" or on else UT.TEXT)

## Pole „rozwijane" (klik przełącza na kolejną wartość): ramka, mono, strzałka ▾.
class Dropdown extends PanelContainer:
	signal clicked
	var _label: Label
	func _init() -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0d0e0c")
		sb.border_color = UT.LINE2
		sb.set_border_width_all(1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		add_theme_stylebox_override("panel", sb)
		focus_mode = Control.FOCUS_ALL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label = Label.new()
		_label.add_theme_font_override("font", UT.mono_font())
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", UT.TEXT)
		_label.add_theme_constant_override("outline_size", 0)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_label)
		var tri := Tri.new()
		h.add_child(tri)
		add_child(h)
	func set_text(s: String) -> void:
		_label.text = s
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			clicked.emit()
			accept_event()
	func _draw() -> void:
		if has_focus():
			draw_rect(Rect2(-3, -3, size.x + 6, size.y + 6), preload("res://scripts/ui_theme.gd").TEXT, false, 2.0)

class Tri extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(10, 6)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(5, 6), Vector2(10, 0)]), Color("8d8a7c"))

## Pozycja nawigacji sekcji (lewa kolumna menu pauzy): ikona liniowa 18 px + napis stencil; aktywna ma czerwony pasek i poświatę.
class NavItem extends Control:
	signal pressed
	var kind := 0
	var label := ""
	var active := false: set = set_active
	func _init() -> void:
		custom_minimum_size = Vector2(196, 44)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func set_active(v: bool) -> void:
		active = v
		queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()
	func _draw() -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		var hover := get_global_rect().has_point(get_global_mouse_position()) and not active
		if active:
			draw_rect(Rect2(0, 0, 2, size.y), UT.DANGER)
			var c0 := Color(UT.DANGER, 0.16)
			draw_polygon(PackedVector2Array([Vector2(2, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(2, size.y)]),
				PackedColorArray([c0, Color(UT.DANGER, 0.0), Color(UT.DANGER, 0.0), c0]))
		var col: Color = Color("f1ecdc") if active else (UT.TEXT if hover else UT.BONE_DIM)
		_icon(Vector2(18 if active else 20, size.y * 0.5 - 9.0), col)
		var fv := UT.display_font(700, 2)
		var ts := fv.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21)
		draw_string(fv, Vector2(48, size.y * 0.5 + ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, col)
		if has_focus():
			draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), UT.TEXT, false, 2.0)
	func _icon(o: Vector2, c: Color) -> void:
		var w := 1.6
		match kind:
			0:  # suwaki
				for i in 3:
					var y := o.y + 5.0 + 4.0 * i
					draw_line(o + Vector2(3, y - o.y), o + Vector2(15, y - o.y), c, w)
					var cx: float = [6.0, 12.0, 7.0][i]
					draw_circle(o + Vector2(cx, y - o.y), 2.0, Color("0d0e0c"))
					draw_arc(o + Vector2(cx, y - o.y), 2.0, 0, TAU, 12, c, w)
			1:  # tarcza
				draw_arc(o + Vector2(9, 9), 6.0, 0, TAU, 20, c, w)
				draw_arc(o + Vector2(9, 9), 2.0, 0, TAU, 12, c, w)
				for d in [Vector2(9, 1), Vector2(9, 14), Vector2(1, 9), Vector2(14, 9)]:
					draw_line(o + d, o + d + (Vector2(0, 3) if d.x == 9 else Vector2(3, 0)), c, w)
			2:  # karabin
				var pts := PackedVector2Array([Vector2(1, 8), Vector2(5, 8), Vector2(6, 5), Vector2(14, 5), Vector2(14, 8), Vector2(17, 8), Vector2(17, 11),
					Vector2(12, 11), Vector2(11, 15), Vector2(7, 15), Vector2(8, 11), Vector2(4, 11), Vector2(1, 8)])
				for i in pts.size() - 1:
					draw_line(o + pts[i], o + pts[i + 1], c, w)
			3:  # skrzynia
				draw_rect(Rect2(o + Vector2(3, 6), Vector2(12, 9)), c, false, w)
				draw_polyline(PackedVector2Array([o + Vector2(6, 6), o + Vector2(6, 4), o + Vector2(12, 4), o + Vector2(12, 6)]), c, w)
				draw_line(o + Vector2(3, 10), o + Vector2(15, 10), c, w)
			4:  # gwiazda
				var st := PackedVector2Array()
				for i in 10:
					var r := 8.0 if i % 2 == 0 else 3.6
					var a := -PI * 0.5 + TAU * float(i) / 10.0
					st.append(o + Vector2(9, 9.5) + Vector2(cos(a), sin(a)) * r)
				st.append(st[0])
				draw_polyline(st, c, w)
			5:  # klawiatura
				draw_rect(Rect2(o + Vector2(1.5, 5), Vector2(15, 9)), c, false, w)
				for x in [4.5, 7.5, 10.5, 13.0]:
					draw_line(o + Vector2(x, 8), o + Vector2(x + 1.0, 8), c, w)
				draw_line(o + Vector2(5, 11), o + Vector2(13, 11), c, w)
