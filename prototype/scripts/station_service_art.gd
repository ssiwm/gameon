extends RefCounted
## Stół konserwacji i szafka osobista (STATION_CARDS_PLAN.md E3, §6 ST-02 / ST-07): trzy przyrządy z manometrem zamiast karty,
## lista do zrobienia na kartce, drzwi szafki z naszywkami perków, paskami rzepu na sloty, zdjęciem i książeczką wojskową z pieczątkami
## poziomów. Tylko prezentacja (workshop_ui.gd wypełnia dane).

const UiTheme := preload("res://scripts/ui_theme.gd")
const NotePalette := preload("res://scripts/note_palette.gd")
const StationKit := preload("res://scripts/station_kit.gd")

## Tarcza manometru: skala 0–1 na łuku, strefy [[od, do, kolor]], wskazówka `value` (płynnie), cień `ghost` (dokąd dojdzie, < 0 — bez),
## kropka lampy `mark` (granica, np. limit czyszczenia; < 0 — bez). `lit` — przyrząd pod lampą (wybrany).
class Dial extends Control:
	var value := 0.0
	var ghost := -1.0
	var mark := -1.0
	var zones: Array = []
	var lit := false
	var _shown := -1.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120, 64)
	func _process(delta: float) -> void:
		if _shown < 0.0 or Settings.fx_mult() <= 0.0:
			_shown = value
		else:
			_shown = lerpf(_shown, value, minf(1.0, delta * 8.0))
		queue_redraw()
	func _ang(f: float) -> float:
		return lerpf(PI, TAU, clampf(f, 0.0, 1.0))
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y - 6.0)
		var r := minf(size.x * 0.5 - 6.0, size.y - 12.0)
		if lit:
			draw_texture_rect(UiTheme.lamp_pool(), Rect2(c - Vector2(r * 1.3, r * 1.25), Vector2(r * 2.6, r * 1.9)), false)
		draw_arc(c, r, PI, TAU, 40, Color(0, 0, 0, 0.6), 9.0, true)
		draw_arc(c, r, PI, TAU, 40, Color("2b2a25"), 6.0, true)
		for z in zones:
			draw_arc(c, r, _ang(float(z[0])), _ang(float(z[1])), 20, z[2], 6.0, true)
		for i in 11:
			var a := _ang(float(i) / 10.0)
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r - 9.0), c + d * (r - (15.0 if i % 5 == 0 else 12.0)), Color(UiTheme.TEXT, 0.6 if i % 5 == 0 else 0.35), 1.5 if i % 5 == 0 else 1.0)
		if mark >= 0.0:
			var ma := _ang(mark)
			draw_circle(c + Vector2(cos(ma), sin(ma)) * r, 4.0, UiTheme.ACCENT)
		if ghost >= 0.0 and absf(ghost - value) > 0.005:
			var ga := _ang(ghost)
			var gp := c + Vector2(cos(ga), sin(ga)) * (r - 10.0)
			var steps := 9
			for i in steps:
				if i % 2 == 0:
					draw_line(c.lerp(gp, float(i) / steps), c.lerp(gp, float(i + 1) / steps), Color(UiTheme.TEXT, 0.55), 1.5)
		var na := _ang(_shown if _shown >= 0.0 else value)
		var tip := c + Vector2(cos(na), sin(na)) * (r - 8.0)
		draw_line(c, tip, Color(0, 0, 0, 0.6), 4.0, true)
		draw_line(c, tip, UiTheme.WARM if lit else UiTheme.BONE_DIM, 2.0, true)
		draw_circle(c, 6.0, Color("3d3a30"))
		draw_circle(c, 3.0, UiTheme.BONE_DIM)

## Przyrząd stołu konserwacji (ST-02): tarcza, nazwa czynności, liczba po prawej (czas albo cena), podpis stanu. Wybrany — w świetle lampy.
class Gauge extends PanelContainer:
	var dial: Dial
	var title: Label
	var right: Label
	var sub: Label
	var job := ""
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(124, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		dial = Dial.new()
		v.add_child(dial)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		title = UiTheme.heading("", 11, UiTheme.TEXT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(title)
		right = UiTheme.mono(UiTheme.label("", 8, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
		h.add_child(right)
		sub = UiTheme.mono(UiTheme.label("", 7, UiTheme.MUTED))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 112
		v.add_child(sub)
		set_lit(false)
	func set_lit(on: bool) -> void:
		dial.lit = on
		var b := StyleBoxFlat.new()
		b.bg_color = Color("1c1a14") if on else Color("101110")
		b.border_color = UiTheme.LAMP_LINE if on else UiTheme.LINE
		b.set_border_width_all(1)
		b.border_width_bottom = 2 if on else 1
		b.set_content_margin_all(6)
		add_theme_stylebox_override("panel", b)
		title.add_theme_color_override("font_color", UiTheme.WARM if on else UiTheme.BONE_DIM)

## Kartka odręczna (`SCRAWL`) przypięta taśmą: tło z palety nocnej, plamy oleju, pasek taśmy u góry.
class Scrawl extends PanelContainer:
	var stains := true
	func _init() -> void:
		var pal: Dictionary = NotePalette.palette(NotePalette.Note.SCRAWL)
		var b := StyleBoxFlat.new()
		b.bg_color = pal["bg"]
		b.border_color = pal["edge"]
		b.set_border_width_all(1)
		b.content_margin_left = 10
		b.content_margin_right = 10
		b.content_margin_top = 14
		b.content_margin_bottom = 8
		add_theme_stylebox_override("panel", b)
		rotation_degrees = -1.2
	func _draw() -> void:
		var pal: Dictionary = NotePalette.palette(NotePalette.Note.SCRAWL)
		if stains:
			draw_circle(Vector2(size.x * 0.82, size.y * 0.72), 9.0, Color(pal["bg2"], 0.9))
			draw_circle(Vector2(size.x * 0.86, size.y * 0.66), 4.0, Color(pal["bg2"], 0.9))
			draw_arc(Vector2(size.x * 0.18, size.y * 0.85), 11.0, 0.3, 4.6, 16, Color(pal["deco"], 0.5), 1.5)
		draw_rect(Rect2(size.x * 0.5 - 22.0, -5.0, 44.0, 11.0), Color(0.55, 0.53, 0.47, 0.75))     # taśma

## Drzwi szafki osobistej (ST-07): blacha w zieleni munduru, szczeliny wentylacyjne u góry, zawias z boku.
static func locker_door() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color("262b20")
	b.border_color = Color("13160f")
	b.set_border_width_all(2)
	b.set_corner_radius_all(2)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 18
	b.content_margin_bottom = 10
	return b

## Szczeliny wentylacyjne na drzwiach (nakładka pod treścią drzwi).
class Vents extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in 6:
			var x := size.x * 0.5 - 45.0 + i * 16.0
			draw_rect(Rect2(x, 5.0, 11.0, 3.0), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(x, 8.0, 11.0, 1.0), Color(1, 1, 1, 0.05))

## Naszywka perka: tkanina z obszyciem (przerywany ścieg wewnątrz krawędzi). Rysowana pod miniaturą i napisami kafla.
static func patch_box(base: Color, lit: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = base.darkened(0.72).lerp(Color("2a2d22"), 0.5).lightened(0.08 if lit else 0.0)
	b.border_color = UiTheme.LAMP_LINE if lit else Color("15170f")
	b.set_border_width_all(2)
	b.set_corner_radius_all(5)
	return b

## Ścieg naszywki i folia zablokowanego perka (nakładki kafla perka).
class Stitch extends Control:
	var color := Color(1, 1, 1, 0.25)
	var foil := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var dash := 4.0
		var x := r.position.x
		while x < r.end.x:
			draw_line(Vector2(x, r.position.y), Vector2(minf(x + dash, r.end.x), r.position.y), color, 1.0)
			draw_line(Vector2(x, r.end.y), Vector2(minf(x + dash, r.end.x), r.end.y), color, 1.0)
			x += dash * 2.0
		var y := r.position.y
		while y < r.end.y:
			draw_line(Vector2(r.position.x, y), Vector2(r.position.x, minf(y + dash, r.end.y)), color, 1.0)
			draw_line(Vector2(r.end.x, y), Vector2(r.end.x, minf(y + dash, r.end.y)), color, 1.0)
			y += dash * 2.0
		if foil:                                            # zablokowany: w folii — chłodny połysk po skosie
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.8, 0.9, 0.1))
			draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.2, 0), Vector2(size.x * 0.38, 0), Vector2(size.x * 0.18, size.y), Vector2(0, size.y)]), Color(1, 1, 1, 0.08))

## Pasek rzepu pod slot perka: szara taśma z drobnym wzorem haczyków (nakładka pod treścią slotu).
class Velcro extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("2c2d28"))
		var y := 3.0
		while y < size.y - 2.0:
			var x := 3.0 + fmod(y, 6.0)
			while x < size.x - 2.0:
				draw_rect(Rect2(x, y, 1.0, 1.0), Color(1, 1, 1, 0.07))
				x += 4.0
			y += 3.0

## Pieczątki poziomów w książeczce wojskowej: kółko z numerem fioletowym tuszem za każdy osiągnięty poziom (do `top`).
class LevelStamps extends Control:
	var level := 1
	var top := 10
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 22)
	func _draw() -> void:
		var font := UiTheme.heading_font()
		for i in top:
			var c := Vector2(10.0 + i * 21.0, 11.0)
			if c.x > size.x - 8.0:
				break
			if i < level:
				var ink := Color(StationKit.STAMP_INK, 0.85)
				draw_arc(c, 8.5, 0, TAU, 20, ink, 1.6, true)
				draw_string(font, c + Vector2(-8.5, 4.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 17.0, 10, ink)
			else:
				draw_arc(c, 8.5, 0, TAU, 20, Color(0, 0, 0, 0.18), 1.0, true)
