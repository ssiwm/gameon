extends Control
## Miniatura perku (perks.gd) w stylu miniatur broni i przedmiotów (gun_icon.gd, item_icon.gd): ciemna „płytka" z poświatą i paskiem w kolorze perku,
## sylwetka z obrysem i cieniem rysowana ostro (piksel rysunku = całkowita liczba pikseli ekranu). Bryłę rysuje `draw_glyph` — ta sama w warsztacie
## (zakładka PERKS) i w karcie PERKS menu pauzy (codex_portrait.gd). `tint` przygasza zablokowane.

const PixelArt := preload("res://scripts/pixel_art.gd")
const Perks := preload("res://scripts/perks.gd")

var perk := "quiet_steps"
var k := 2.0
var plate := true
var tint := Color.WHITE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_perk(id: String, t: Color) -> void:
	if id == perk and t == tint:
		return
	perk = id
	tint = t
	queue_redraw()

func _draw() -> void:
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev
	var accent: Color = Perks.color_of(perk)
	if plate:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.78))
		draw_rect(Rect2(0, 0, size.x, px), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(0, size.y - 2.0, size.x, 2.0), Color(accent.r, accent.g, accent.b, 0.85))
		for i in 4:
			var inset := 2.0 + i * 4.0
			draw_rect(Rect2(inset, inset * 0.5, size.x - 2.0 * inset, size.y - 2.0 - inset), Color(accent.r, accent.g, accent.b, 0.045))
	var s := PixelArt.snap_scale(self, k)
	var body_h := size.y - (2.0 if plate else 0.0)
	var cx := roundf(size.x * 0.5)
	var base := roundf((body_h + 14.0 * s) * 0.5)
	draw_glyph(self, perk, cx, base + maxf(px, s), s, 1.0, accent, Color(0, 0, 0, 0.55))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_glyph(self, perk, cx + o.x * px, base + o.y * px, s, 1.0, accent, Color(0, 0, 0, 0.85 * tint.a))
	draw_glyph(self, perk, cx, base, s, 1.0, accent, Color(0, 0, 0, 0), tint)

## Serce z pikseli 7 × 6 (kolor `col`), lewy górny róg (x, y) w jednostkach rysunku.
static func _heart(ci: CanvasItem, cx: float, y: float, s: float, x: float, yy: float, col: Color, f: Callable) -> void:
	var rows := ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
	for ry in rows.size():
		for rx in 7:
			if String(rows[ry])[rx] == "1":
				ci.draw_rect(Rect2(cx + (x + float(rx)) * s, y + (yy + float(ry)) * s, s, s), f.call(col))

## Bryła perku: środek poziomy `cx`, podstawa `y`, `s` = piksele ekranu / lokalne na jednostkę rysunku, `t` = czas (animacje).
## `flat` z alfą > 0 zamienia wszystkie kolory na jeden (cień, obrys); `mod` mnoży kolory (przygaszenie).
static func draw_glyph(ci: CanvasItem, id: String, cx: float, y: float, s: float, t: float, accent: Color, flat := Color(0, 0, 0, 0), mod := Color.WHITE) -> void:
	var pulse := 0.6 + 0.4 * sin(t * 5.0)
	var f := func(col: Color) -> Color: return flat if flat.a > 0.0 else Color(col.r * mod.r, col.g * mod.g, col.b * mod.b, col.a * mod.a)
	var r := func(x: float, yy: float, w: float, h: float, col: Color) -> void: ci.draw_rect(Rect2(cx + x * s, y + yy * s, w * s, h * s), f.call(col))
	var line := func(a: Vector2, b: Vector2, col: Color, wd: float) -> void: ci.draw_line(Vector2(cx + a.x * s, y + a.y * s), Vector2(cx + b.x * s, y + b.y * s), f.call(col), maxf(1.0, wd * s))
	match id:
		"quiet_steps":
			# dwa ślady butów i przekreślona fala dźwięku
			r.call(-7, -9, 4, 6, Color(0.82, 0.86, 0.9))
			r.call(-6, -3, 3, 3, Color(0.82, 0.86, 0.9))
			r.call(0, -12, 4, 6, Color(0.82, 0.86, 0.9))
			r.call(1, -6, 3, 3, Color(0.82, 0.86, 0.9))
			ci.draw_arc(Vector2(cx + 7.0 * s, y - 8.0 * s), 3.0 * s, -0.9, 0.9, 8, f.call(accent), maxf(1.0, s * 0.7))
			ci.draw_arc(Vector2(cx + 7.0 * s, y - 8.0 * s), 6.0 * s, -0.9, 0.9, 10, f.call(Color(accent.r, accent.g, accent.b, 0.55)), maxf(1.0, s * 0.7))
			line.call(Vector2(-8, -1), Vector2(10, -13), Color(0.95, 0.3, 0.3), 0.9)
		"blood_flow":
			ci.draw_circle(Vector2(cx - 2.0 * s, y - 5.0 * s), 4.5 * s, f.call(Color(0.78, 0.14, 0.16)))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5.2 * s, y - 7.0 * s), Vector2(cx - 2.0 * s, y - 14.0 * s), Vector2(cx + 1.2 * s, y - 7.0 * s)]), f.call(Color(0.78, 0.14, 0.16)))
			r.call(-4, -8, 1.5, 3, Color(1.0, 0.7, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx + 5.0 * s, y - 12.0 * s), Vector2(cx + 8.0 * s, y - 8.0 * s), Vector2(cx + 6.2 * s, y - 8.0 * s), Vector2(cx + 6.2 * s, y - 3.0 * s), Vector2(cx + 3.8 * s, y - 3.0 * s), Vector2(cx + 3.8 * s, y - 8.0 * s), Vector2(cx + 2.0 * s, y - 8.0 * s)]), f.call(accent))
		"wide_arm":
			var pts := PackedVector2Array()
			for i in 9:
				var u := float(i) / 8.0
				pts.append(Vector2(cx + (-8.0 + 16.0 * u) * s, y + (-2.0 - 10.0 * sin(u * PI)) * s))
			ci.draw_polyline(pts, f.call(Color(accent.r, accent.g, accent.b, 0.8)), maxf(1.0, s * 0.8))
			ci.draw_circle(Vector2(cx - 8.0 * s, y - 2.0 * s), 2.2 * s, f.call(Color(0.5, 0.72, 0.4)))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx + 9.0 * s, y - 2.0 * s), Vector2(cx + 5.0 * s, y - 5.0 * s), Vector2(cx + 5.5 * s, y - 0.5 * s)]), f.call(accent))
			r.call(5, -13, 2, 1, Color(1, 1, 1, 0.5))
		"smith":
			r.call(-7, -8, 13, 3, Color(0.62, 0.64, 0.7))
			r.call(-8, -7, 2, 2, Color(0.62, 0.64, 0.7))
			r.call(-3, -5, 5, 3, Color(0.46, 0.48, 0.54))
			r.call(-5, -2, 9, 2, Color(0.34, 0.36, 0.42))
			r.call(-7, -8, 13, 1, Color(0.85, 0.87, 0.92))
			line.call(Vector2(1, -9), Vector2(7, -14), Color(0.55, 0.38, 0.22), 1.4)
			r.call(5, -15, 5, 3, accent)
		"cold_blood":
			r.call(-2, -13, 4, 7, Color(0.78, 0.82, 0.88))
			r.call(-2, -13, 4, 1, Color(1, 1, 1))
			ci.draw_arc(Vector2(cx, y - 7.0 * s), 4.5 * s, 0.0, PI, 10, f.call(Color(0.5, 0.54, 0.6)), maxf(1.0, s * 0.8))
			line.call(Vector2(0, -2.5), Vector2(0, -1), Color(0.5, 0.54, 0.6), 0.9)
			r.call(-3, -1, 6, 1, Color(0.5, 0.54, 0.6))
			r.call(6, -12, 1, 5, accent)
			r.call(4, -10, 5, 1, accent)
			r.call(5, -11, 3, 3, Color(accent.r, accent.g, accent.b, 0.35))
		"scout":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 8.0 * s, y - 6.0 * s), Vector2(cx - 3.0 * s, y - 10.0 * s), Vector2(cx + 3.0 * s, y - 10.0 * s), Vector2(cx + 8.0 * s, y - 6.0 * s), Vector2(cx + 3.0 * s, y - 2.0 * s), Vector2(cx - 3.0 * s, y - 2.0 * s)]), f.call(Color(0.82, 0.86, 0.9)))
			ci.draw_circle(Vector2(cx, y - 6.0 * s), 3.2 * s, f.call(accent))
			ci.draw_circle(Vector2(cx, y - 6.0 * s), 1.4 * s, f.call(Color(0.08, 0.1, 0.08)))
			var ph := fmod(t * 0.9, 1.0)
			ci.draw_arc(Vector2(cx, y - 6.0 * s), (9.0 + 3.0 * ph) * s, -0.6, 0.6, 8, f.call(Color(accent.r, accent.g, accent.b, 0.8 - 0.6 * ph)), maxf(1.0, s * 0.6))
			ci.draw_arc(Vector2(cx, y - 6.0 * s), (9.0 + 3.0 * ph) * s, PI - 0.6, PI + 0.6, 8, f.call(Color(accent.r, accent.g, accent.b, 0.8 - 0.6 * ph)), maxf(1.0, s * 0.6))
		"second_chance":
			_heart(ci, cx, y, s, -3.5, -9.0, Color(0.85, 0.2, 0.25), f)
			ci.draw_arc(Vector2(cx, y - 6.0 * s), 7.5 * s, 0.5, 5.4, 18, f.call(accent), maxf(1.0, s * 0.8))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx + 6.6 * s, y - 1.6 * s), Vector2(cx + 9.6 * s, y - 4.6 * s), Vector2(cx + 4.4 * s, y - 4.8 * s)]), f.call(accent))
		"veteran":
			_heart(ci, cx, y, s, -3.5, -7.0, Color(0.85, 0.2, 0.25), f)
			r.call(-1, -14, 2, 6, accent)
			r.call(-3, -12, 6, 2, accent)
			r.call(-5, -1, 10, 1, Color(accent.r, accent.g, accent.b, 0.9))
			r.call(-4, 1, 8, 1, Color(accent.r, accent.g, accent.b, 0.6))
			r.call(-2, -13, 4, 4, Color(accent.r, accent.g, accent.b, 0.35 * pulse))
