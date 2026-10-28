extends RefCounted
## Pracownia i tokarka (STATION_CARDS_PLAN.md E4, §6 ST-05 / ST-06): tablica korkowa z łańcuchem LAB_STEPS i czerwoną nicią, słoje z próbkami
## (kształty w słojach powoli obracają się w stronę dźwięku — decyzja D2a, tylko tu, wyłącza „Reduce effects”), akta Obiektu 86
## z zaczernieniami, wydruk z drukarki (`PRINTOUT`, perforacja), rysunek części z tabliczką rysunkową cyrylicą, zlecenie na szpikulcu
## i szlifierka z iskrami w trakcie ostrzenia. Tylko prezentacja (workshop_ui.gd wypełnia dane).

const UiTheme := preload("res://scripts/ui_theme.gd")
const NotePalette := preload("res://scripts/note_palette.gd")
const StationKit := preload("res://scripts/station_kit.gd")

static func printout() -> Dictionary:
	return NotePalette.palette(NotePalette.Note.PRINTOUT)

## Tablica korkowa z kartkami kroków (przypięte pinezką, połączone czerwoną nicią). `steps` — [tytuł, podpis], `step` — bieżący,
## `busy` — bieżący w toku. Zrobione z ✓, bieżący w świetle lampy.
class CorkChain extends Control:
	var steps: Array = []
	var step := 0
	var busy := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 62)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("3b2b1a"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("1e150b"), false, 3.0)
		var n := steps.size()
		if n == 0:
			return
		var w := (size.x - 16.0) / float(n)
		var cw := w - 6.0
		var pins: Array = []
		for i in n:
			var cx := 8.0 + w * (i + 0.5)
			pins.append(Vector2(cx, 12.0))
		for i in n - 1:                                       # czerwona nić od pinezki do pinezki
			draw_line(pins[i], pins[i + 1], Color("8a1d18"), 1.5, true)
		var font := UiTheme.heading_font()
		var mono := UiTheme.mono_font()
		var pal := NotePalette.palette(NotePalette.Note.DOSSIER)
		for i in n:
			var c: Vector2 = pins[i]
			var rot := deg_to_rad([-2.0, 1.5, -1.0, 2.0, -1.5][i % 5])
			draw_set_transform(c + Vector2(0, 22.0), rot, Vector2.ONE)
			var r := Rect2(-cw * 0.5, -16.0, cw, 34.0)
			if i == step:
				draw_texture_rect(UiTheme.lamp_pool(), r.grow(14.0), false)
			draw_rect(r, (pal["bg"] as Color).lightened(0.06) if i == step else (pal["bg"] as Color).darkened(0.12 if i > step else 0.0))
			var t := String(steps[i][0]) + (" ✓" if i < step else ("…" if busy and i == step else ""))
			draw_string(font, Vector2(r.position.x, -2.0), t, HORIZONTAL_ALIGNMENT_CENTER, cw, 10, pal["ink"])
			draw_string(mono, Vector2(r.position.x, 11.0), String(steps[i][1]), HORIZONTAL_ALIGNMENT_CENTER, cw, 6, pal["dim"])
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(c, 4.0, Color("b3261e"))
			draw_circle(c + Vector2(-1, -1), 1.4, Color(1, 1, 1, 0.4))

## Słoje z próbkami: `count` pełnych z `slots`. Ciemny kształt w słoju obraca się w stronę dźwięku (`hear(dir)` — −1 lewo, 1 prawo)
## i wraca powoli do środka. Ruch tylko przy zdarzeniu; „Reduce effects” — bez ruchu.
class Jars extends Control:
	var count := 0
	var slots := 6
	var _look := 0.0
	var _target := 0.0
	var _hold := 0.0
	var _t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 118)
	## Dźwięk z kierunku `dir` (−1 lewo, 1 prawo): kształty w słojach zwracają się ku niemu.
	func hear(dir: float) -> void:
		if Settings.fx_mult() <= 0.0:
			return
		_target = clampf(dir, -1.0, 1.0)
		_hold = 2.5
	func looking() -> float:
		return _look
	func _process(delta: float) -> void:
		_t += delta
		_hold = maxf(0.0, _hold - delta)
		if _hold <= 0.0:
			_target = 0.0
		_look = move_toward(_look, _target, delta * 0.6)        # powoli — jak coś, co słucha
		queue_redraw()
	func _draw() -> void:
		var cols := 3
		var w := (size.x - 8.0) / cols
		var h := (size.y - 8.0) / ceilf(float(slots) / cols)
		for i in slots:
			var r := Rect2(4.0 + (i % cols) * w + 3.0, 4.0 + (i / cols) * h + 3.0, w - 6.0, h - 6.0)
			var full := i < count
			draw_rect(Rect2(r.position, Vector2(r.size.x, 6.0)), Color("2a2a26"))             # zakrętka
			var glass := Rect2(r.position + Vector2(0, 6.0), r.size - Vector2(0, 6.0))
			draw_rect(glass, Color("1f3324") if full else Color("141613"))
			draw_rect(glass, Color(1, 1, 1, 0.08), false, 1.0)
			if full:
				var c := glass.get_center() + Vector2(_look * glass.size.x * 0.12, 0.0)
				var sway := sin(_t * 0.7 + i) * 0.04 if Settings.fx_mult() > 0.0 else 0.0
				draw_set_transform(c, _look * 0.5 + sway, Vector2(1.0, 1.15))
				draw_circle(Vector2.ZERO, glass.size.x * 0.27, Color(0.04, 0.05, 0.04, 0.9))
				draw_circle(Vector2(glass.size.x * 0.1 * (1.0 if _look >= 0.0 else -1.0) * absf(_look), -2.0), glass.size.x * 0.05, Color(0.6, 0.15, 0.1, 0.5 * absf(_look)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_rect(Rect2(glass.position + Vector2(3, 3), Vector2(3, glass.size.y - 8)), Color(1, 1, 1, 0.06))

## Linia akt z zaczernieniami: tekst, w którym „█” oznacza zaczernione słowo (prostokąt tuszu zamiast liter).
class Redacted extends Control:
	var text := ""
	var color := Color.BLACK
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 14)
	func _draw() -> void:
		var font := UiTheme.whisper_font()
		var x := 0.0
		for part in text.split("█"):
			draw_string(font, Vector2(x, 10.0), part, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
			x += font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			if part != text.split("█")[-1] or text.ends_with("█"):
				draw_rect(Rect2(x + 2.0, 1.0, 46.0, 11.0), Color(0.03, 0.02, 0.02, 0.92))
				x += 50.0

## Wydruk z drukarki (`PRINTOUT`): ciemnozielony papier z perforacją po bokach. Styl panelu + nakładka z dziurkami.
static func printout_box() -> StyleBoxFlat:
	var p: Dictionary = NotePalette.palette(NotePalette.Note.PRINTOUT)
	var b := StyleBoxFlat.new()
	b.bg_color = p["bg"]
	b.border_color = p["edge"]
	b.set_border_width_all(1)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

class Perforation extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		# nakładka leży w polu treści panelu — dziurki rysujemy na marginesach (content_margin 18 px po bokach)
		var y := 4.0
		while y < size.y:
			draw_circle(Vector2(-11.0, y), 2.4, Color(0, 0, 0, 0.7))
			draw_circle(Vector2(size.x + 11.0, y), 2.4, Color(0, 0, 0, 0.7))
			y += 14.0
		draw_line(Vector2(-5.0, -8.0), Vector2(-5.0, size.y + 8.0), Color(1, 1, 1, 0.05), 1.0)
		draw_line(Vector2(size.x + 5.0, -8.0), Vector2(size.x + 5.0, size.y + 8.0), Color(1, 1, 1, 0.05), 1.0)

## Rysunek części dla tokarki (wydruk z pracowni): jeden szablon dla wszystkich części — obrys wg gniazda (soczewka, ogniwo, cewka,
## reszta — korpus z otworami), linia osiowa, wymiary i tabliczka rysunkowa (laboratorium Obiektu 86 — cyrylica).
class Blueprint extends Control:
	var slot := ""
	var title := ""
	var line2 := ""
	var dims := Vector2(42, 18)
	var has_schematic := true
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 206)
	func _draw() -> void:
		var p: Dictionary = NotePalette.palette(NotePalette.Note.PRINTOUT)
		var ink: Color = p["ink"]
		var dim: Color = p["dim"]
		var mono := UiTheme.mono_font()
		draw_rect(Rect2(Vector2.ZERO, size), p["bg"])                    # własny arkusz wydruku (zielony na ciemnym), z perforacją
		draw_rect(Rect2(Vector2.ZERO, size), p["edge"], false, 1.0)
		var hy := 8.0
		while hy < size.y - 4.0:
			draw_circle(Vector2(6.0, hy), 2.2, Color(0, 0, 0, 0.7))
			draw_circle(Vector2(size.x - 6.0, hy), 2.2, Color(0, 0, 0, 0.7))
			hy += 14.0
		var frame := Rect2(Vector2(16, 6), size - Vector2(32, 12))
		_dotted_rect(frame, Color(dim, 0.8))
		if not has_schematic:
			draw_string(mono, Vector2(frame.position.x, frame.get_center().y), tr("NO SCHEMATIC — RESEARCH IT AT THE LAB"), HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 9, dim)
			return
		var c := Vector2(frame.position.x + frame.size.x * 0.3, frame.position.y + frame.size.y * 0.4)
		var hh := frame.size.y * 0.27
		var hw := hh * dims.y / maxf(1.0, dims.x)
		_dash_line(Vector2(c.x - hw * 3.0, c.y), Vector2(c.x + hw * 3.0, c.y), Color(dim, 0.8))          # linia osiowa
		_dash_line(Vector2(c.x, c.y - hh * 1.2), Vector2(c.x, c.y + hh * 1.2), Color(dim, 0.5))
		match slot:
			"muzzle":                                          # soczewka: łuki z obu stron
				_outline(_lens(c, hw, hh), ink)
			"feed":                                            # ogniwo (zasilanie): walec z biegunem
				_outline(PackedVector2Array([c + Vector2(-hw, -hh), c + Vector2(hw, -hh), c + Vector2(hw, hh), c + Vector2(-hw, hh), c + Vector2(-hw, -hh)]), ink)
				_outline(PackedVector2Array([c + Vector2(-hw * 0.4, -hh), c + Vector2(-hw * 0.4, -hh - 6), c + Vector2(hw * 0.4, -hh - 6), c + Vector2(hw * 0.4, -hh)]), ink)
			"action":                                          # cewka (mechanizm): zwoje na rdzeniu
				_outline(PackedVector2Array([c + Vector2(-hw * 0.35, -hh), c + Vector2(hw * 0.35, -hh), c + Vector2(hw * 0.35, hh), c + Vector2(-hw * 0.35, hh), c + Vector2(-hw * 0.35, -hh)]), ink)
				for i in 7:
					var y := c.y - hh * 0.8 + i * hh * 0.27
					draw_line(Vector2(c.x - hw, y), Vector2(c.x + hw, y + hh * 0.12), ink, 1.2, true)
			_:
				_outline(PackedVector2Array([c + Vector2(-hw, -hh), c + Vector2(hw, -hh), c + Vector2(hw, hh), c + Vector2(-hw, hh), c + Vector2(-hw, -hh)]), ink)
				draw_arc(c, hw * 0.3, 0, TAU, 16, ink, 1.0, true)
		# wymiary: średnica / wysokość po prawej, szerokość pod spodem
		var xr := c.x + hw + 26.0
		draw_line(Vector2(xr, c.y - hh), Vector2(xr, c.y + hh), ink, 1.0)
		draw_line(Vector2(c.x + hw + 4.0, c.y - hh), Vector2(xr + 4.0, c.y - hh), Color(ink, 0.6), 1.0)
		draw_line(Vector2(c.x + hw + 4.0, c.y + hh), Vector2(xr + 4.0, c.y + hh), Color(ink, 0.6), 1.0)
		draw_string(mono, Vector2(xr + 6.0, c.y + 4.0), "Ø %d h8" % int(dims.x), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ink)
		var yb := c.y + hh + 14.0
		draw_line(Vector2(c.x - hw, yb), Vector2(c.x + hw, yb), ink, 1.0)
		draw_string(mono, Vector2(c.x - 30.0, yb + 12.0), "%d" % int(dims.y), HORIZONTAL_ALIGNMENT_CENTER, 60.0, 9, ink)
		# tabliczka rysunkowa (prawy dolny róg)
		var tb := Rect2(frame.end - Vector2(196, 58), Vector2(192, 54))
		_dotted_rect(tb, ink)
		draw_line(Vector2(tb.position.x, tb.position.y + 20), Vector2(tb.end.x, tb.position.y + 20), Color(ink, 0.6), 1.0)
		draw_line(Vector2(tb.position.x, tb.position.y + 37), Vector2(tb.end.x, tb.position.y + 37), Color(ink, 0.6), 1.0)
		draw_line(Vector2(tb.position.x + 120, tb.position.y + 37), Vector2(tb.position.x + 120, tb.end.y), Color(ink, 0.6), 1.0)
		draw_string(UiTheme.heading_font(), Vector2(tb.position.x + 5, tb.position.y + 15), title, HORIZONTAL_ALIGNMENT_LEFT, tb.size.x - 10, 11, ink)
		draw_string(mono, Vector2(tb.position.x + 5, tb.position.y + 32), line2, HORIZONTAL_ALIGNMENT_LEFT, tb.size.x - 10, 7, dim)
		draw_string(mono, Vector2(tb.position.x + 5, tb.position.y + 49), "ЛАБ. 3 · ОБЪЕКТ 86", HORIZONTAL_ALIGNMENT_LEFT, 112, 7, ink)
		draw_string(mono, Vector2(tb.position.x + 125, tb.position.y + 49), "ЛИСТ 1/1", HORIZONTAL_ALIGNMENT_LEFT, 64, 7, ink)
	func _lens(c: Vector2, hw: float, hh: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 13:
			var y := lerpf(-hh, hh, i / 12.0)
			pts.append(c + Vector2(-hw * 0.6 - hw * 0.4 * (1.0 - pow(y / hh, 2.0)), y))
		for i in 13:
			var y := lerpf(hh, -hh, i / 12.0)
			pts.append(c + Vector2(hw * 0.6 + hw * 0.4 * (1.0 - pow(y / hh, 2.0)), y))
		pts.append(pts[0])
		return pts
	func _outline(pts: PackedVector2Array, col: Color) -> void:
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 3.0))
			for k in n:
				draw_circle(a.lerp(b, float(k) / n), 0.9, col)          # matrycowa drukarka: obrys z kropek
	func _dash_line(a: Vector2, b: Vector2, col: Color) -> void:
		var n := maxi(1, int(a.distance_to(b) / 9.0))
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, 1.0)
	func _dotted_rect(r: Rect2, col: Color) -> void:
		_outline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]), col)

## Szpikulec nad zleceniem (kartka odręczna nabita na pręt).
class Spike extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 8)
	func _draw() -> void:
		draw_line(Vector2(size.x * 0.5, -18.0), Vector2(size.x * 0.5, size.y + 10.0), Color("8a8a84"), 2.0)
		draw_circle(Vector2(size.x * 0.5, size.y + 10.0), 3.0, Color("4a4a44"))

## Szlifierka: iskry tylko w trakcie ostrzenia (`active`), bez nich przy „Reduce effects”.
class Sparks extends Control:
	var active := false
	var _t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 14)
	func _process(delta: float) -> void:
		_t += delta
		if active:
			queue_redraw()
	func _draw() -> void:
		if not active or Settings.fx_mult() <= 0.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_t * 30.0)
		for i in 9:
			var sp := Vector2(size.x * 0.85 + rng.randf_range(-6, 6), rng.randf_range(0, size.y))
			draw_line(sp, sp + Vector2(rng.randf_range(-12, -3), rng.randf_range(-4, 4)), Color(1.0, 0.78, 0.35, rng.randf_range(0.4, 0.9)), 1.2)
