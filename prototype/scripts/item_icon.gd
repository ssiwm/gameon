extends Control
## Miniatura przedmiotu ekwipunku zużywalnego (throwables.gd) w stylu miniatur broni (gun_icon.gd): ciemna „płytka" z poświatą
## i paskiem w kolorze przedmiotu, sylwetka z obrysem i cieniem rysowana ostro (piksel rysunku = całkowita liczba pikseli ekranu).
## Bryłę rysuje `draw_glyph` — ten sam kod służy karcie GEAR w kodeksie (codex_portrait.gd).

const PixelArt := preload("res://scripts/pixel_art.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Sprites := preload("res://scripts/sprites.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

var kind := "frag"
var k := 2.0                  ## żądana skala lokalna (piksel rysunku w jednostkach lokalnych)
var plate := true
var tint := Color.WHITE       ## przygasza niedostępne

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if UiTheme.hd_on() else CanvasItem.TEXTURE_FILTER_NEAREST
	_preload_hd()

func set_item(kd: String, t: Color) -> void:
	if kd == kind and t == tint:
		return
	kind = kd
	tint = t
	_preload_hd()
	queue_redraw()

## Tekstury HD wczytujemy poza `_draw` (pierwsze wczytanie w trakcie rysowania daje białe prostokąty).
func _preload_hd() -> void:
	if UiTheme.hd_on() and ItemsHd.has(kind):
		ItemsHd.albedo(kind)
		ItemsHd.glow_texture(kind)

func _draw() -> void:
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev
	var accent: Color = Throwables.KINDS[kind]["color"]
	if plate:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.78))
		draw_rect(Rect2(0, 0, size.x, px), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(0, size.y - 2.0, size.x, 2.0), Color(accent.r, accent.g, accent.b, 0.85))
		for i in 4:
			var inset := 2.0 + i * 4.0
			draw_rect(Rect2(inset, inset * 0.5, size.x - 2.0 * inset, size.y - 2.0 - inset), Color(accent.r, accent.g, accent.b, 0.045))
	var body_h := size.y - (2.0 if plate else 0.0)
	if UiTheme.hd_on() and ItemsHd.has(kind):
		ItemsHd.draw_fit(self, kind, Rect2(4.0, 3.0, size.x - 8.0, body_h - 6.0), tint, Vector2(11.0, 10.0))
		return
	var s := PixelArt.snap_scale(self, k)
	var cx := roundf(size.x * 0.5)
	var base := roundf((body_h + 14.0 * s) * 0.5)               # bryła ma do ~14 jednostek wysokości: środkujemy w pionie
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# cień i obrys 1 px ekranu, potem bryła
	draw_glyph(self, kind, cx, base + maxf(px, s), s, 1.0, accent, Color(0, 0, 0, 0.55))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_glyph(self, kind, cx + o.x * px, base + o.y * px, s, 1.0, accent, Color(0, 0, 0, 0.85 * tint.a))
	draw_glyph(self, kind, cx, base, s, 1.0, accent, Color(0, 0, 0, 0), tint)

## Bryła przedmiotu: środek poziomy `cx`, podstawa `y`, `s` = piksele ekranu / lokalne na jednostkę rysunku, `t` = czas (migające diody).
## `flat` z alfą > 0 zamienia wszystkie kolory na jeden (cień, obrys); `mod` mnoży kolory (przygaszenie).
static func draw_glyph(ci: CanvasItem, kd: String, cx: float, y: float, s: float, t: float, accent: Color, flat := Color(0, 0, 0, 0), mod := Color.WHITE) -> void:
	var pulse := 0.6 + 0.4 * sin(t * 5.0)
	var c := accent
	var f := func(col: Color) -> Color: return flat if flat.a > 0.0 else Color(col.r * mod.r, col.g * mod.g, col.b * mod.b, col.a * mod.a)
	var r := func(x: float, yy: float, w: float, h: float, col: Color) -> void: ci.draw_rect(Rect2(cx + x * s, y + yy * s, w * s, h * s), f.call(col))
	match kd:
		"frag":
			ci.draw_circle(Vector2(cx, y - 5.0 * s), 5.0 * s, f.call(Color(0.22, 0.3, 0.18)))
			r.call(-1, -12, 2, 3, Color(0.5, 0.5, 0.45))
			r.call(-4, -9, 3, 1, Color(0.34, 0.44, 0.28))
			ci.draw_circle(Vector2(cx - 2.0 * s, y - 6.0 * s), 1.2 * s, f.call(c.lightened(0.2)))
		"phos":
			r.call(-3, -11, 6, 10, Color(0.55, 0.55, 0.5))
			r.call(-3, -8, 6, 3, c)
			r.call(-1, -13, 2, 2, Color(0.7, 0.7, 0.65))
			r.call(5, -4.0 * pulse, 2, 4.0 * pulse, Color(1.0, 0.5, 0.15))
		"smoke":
			r.call(-3, -10, 6, 9, Color(0.38, 0.4, 0.42))
			r.call(-3, -7, 6, 3, c)
			r.call(-1, -12, 2, 2, Color(0.6, 0.6, 0.6))
			ci.draw_circle(Vector2(cx - 4.0 * s, y - 13.0 * s), 2.2 * s, f.call(Color(0.7, 0.72, 0.75, 0.55)))
			ci.draw_circle(Vector2(cx + 3.0 * s, y - 14.0 * s), 2.6 * s, f.call(Color(0.7, 0.72, 0.75, 0.45)))
		"mine":
			r.call(-8, -4, 16, 4, Color(0.2, 0.22, 0.2))
			r.call(-6, -6, 12, 2, Color(0.34, 0.36, 0.32))
			r.call(-1, -8, 2, 2, c if pulse > 0.7 else Color(0.25, 0.1, 0.1))
			r.call(5, -3, 2, 1, Color(0.5, 0.5, 0.45))
		"charge":
			r.call(-8, -9, 16, 9, Color(0.34, 0.3, 0.2))
			r.call(-8, -9, 16, 2, Color(0.5, 0.45, 0.3))
			r.call(-4, -6, 8, 3, Color(0.12, 0.12, 0.1))
			r.call(-1, -12, 2, 3, c if pulse > 0.7 else Color(0.25, 0.1, 0.05))
		"medkit":
			r.call(-8, -10, 16, 10, Color(0.85, 0.85, 0.82))
			r.call(-8, -10, 16, 1, Color(1.0, 1.0, 0.97))
			r.call(-2, -9, 4, 8, Color(0.8, 0.15, 0.15))
			r.call(-5, -6, 10, 2, Color(0.8, 0.15, 0.15))
		"defib":
			r.call(-8, -10, 16, 10, Color(0.22, 0.26, 0.3))
			r.call(-6, -8, 12, 4, Color(0.1, 0.12, 0.14))
			ci.draw_polyline(PackedVector2Array([Vector2(cx - 4.0 * s, y - 6.0 * s), Vector2(cx - s, y - 6.0 * s), Vector2(cx, y - 8.0 * s), Vector2(cx + s, y - 4.0 * s), Vector2(cx + 4.0 * s, y - 6.0 * s)]), f.call(c), maxf(1.0, s * 0.7))
			r.call(-6, -2, 3, 1, Color(0.5, 0.5, 0.5))
		"scanner":
			r.call(-6, -10, 12, 10, Color(0.25, 0.27, 0.22))
			ci.draw_circle(Vector2(cx, y - 5.0 * s), 3.5 * s, f.call(Color(0.08, 0.12, 0.08)))
			var ph := fmod(t * 0.9, 1.0)
			ci.draw_arc(Vector2(cx, y - 5.0 * s), 3.5 * s * maxf(ph, 0.35), 0.0, TAU, 20, f.call(Color(c.r, c.g, c.b, 1.0 - ph * 0.7)), maxf(1.0, s * 0.5))
			ci.draw_circle(Vector2(cx + 1.5 * s, y - 6.0 * s), 0.7 * s, f.call(c))
