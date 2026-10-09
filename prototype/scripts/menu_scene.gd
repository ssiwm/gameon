extends Control
## Tło ekranów startowych (menu główne, lobby): nocny las z makiety Main.dc.html — dalsze i bliższe sosny, maszt z mrugającym
## czerwonym światłem, mgła dryfująca w poziomie, lampa w oknie chaty (rzadkie przygasanie) i czasem sylwetka między drzewami.
## Rysowane w kodzie we współrzędnych makiety 1280×720; węzeł sam skaluje się do wysokości ekranu i kotwiczy w lewym dolnym rogu.
## „Reduce effects" zatrzymuje ruch i miganie (stały obraz).

const UiTheme := preload("res://scripts/ui_theme.gd")
const REF_H := 720.0

var _t := 0.0
var _layers: Array[Layer] = []        ## kolejność rysowania: niebo, dalsze sosny, słup i mgła, bliższe sosny, ziemia i winieta
var _far: Strip
var _near: Strip
var _vignette: GradientTexture2D
var _glow: GradientTexture2D

## Warstwa rysowana przez funkcję `fn(canvas)` — dzięki temu pasy drzew mogą leżeć między warstwami we właściwej kolejności.
class Layer extends Control:
	var fn: Callable
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)

## Pas drzew: kafelek 70×170 (trzy piętra trójkątów i pień) powtarzany w poziomie i pionie, przycięty do swojego prostokąta.
class Strip extends Control:
	var tile_w := 70.0
	var tile_h := 170.0
	var k := 1.0
	var x_off := 0.0
	var col := Color.BLACK
	var origin_y := 0.0                   ## y początku kafelków we współrzędnych sceny (jak patternUnits=userSpaceOnUse)

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var tw := tile_w * k
		var th := tile_h * k
		var row := floorf((position.y - origin_y) / th)
		var y := origin_y + row * th - position.y
		while y < size.y:
			var x := fposmod(x_off, tw) - tw
			while x < size.x:
				_tree(Vector2(x, y))
				x += tw
			y += th

	func _tree(o: Vector2) -> void:
		for t in [[35.0, 0.0, 56.0, 52.0, 14.0], [35.0, 32.0, 64.0, 98.0, 6.0], [35.0, 66.0, 68.0, 142.0, 2.0]]:
			var apex := o + Vector2(t[0], t[1]) * k
			var base_y: float = t[3]
			draw_colored_polygon(PackedVector2Array([apex, o + Vector2(t[2], base_y) * k, o + Vector2(t[4], base_y) * k]), col)
		draw_rect(Rect2(o + Vector2(31, 142) * k, Vector2(8, 28) * k), col)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_far = Strip.new()
	_far.col = Color("0b0d0c")
	_far.modulate.a = 0.8
	_near = Strip.new()
	_near.col = Color("030403")
	_near.k = 1.75
	_near.x_off = -24.0
	_layer(_draw_sky)
	add_child(_far)
	_layer(_draw_mid)
	add_child(_near)
	_layer(_draw_front)
	_vignette = GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.34, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.82)])
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.38, 0.46)
	_vignette.fill_to = Vector2(0.38 + 0.88, 0.46)
	_vignette.width = 256
	_vignette.height = 144
	_glow = GradientTexture2D.new()
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(UiTheme.ACCENT, 0.5), Color(UiTheme.ACCENT, 0.0)])
	_glow.gradient = gg
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128

func _layer(fn: Callable) -> void:
	var l := Layer.new()
	l.fn = fn
	add_child(l)
	_layers.append(l)

## Rozmiar sceny w jednostkach makiety dla okna o wymiarach `screen` (px): skala po wysokości, szerokość dopełniona.
func fit(screen: Vector2) -> void:
	var s := screen.y / REF_H
	scale = Vector2(s, s)
	position = Vector2.ZERO
	size = Vector2(maxf(1280.0, screen.x / s), REF_H)
	for l in _layers:
		l.size = size
	_far.position = Vector2(0, 330)
	_far.size = Vector2(size.x, 180)
	_near.position = Vector2(0, 470)
	_near.size = Vector2(size.x, 200)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta * (1.0 if Settings.fx_mult() > 0.0 else 0.0)
	for l in _layers:
		l.queue_redraw()

## Przebieg z progami (jak keyframes CSS): lista [pozycja 0..1, wartość] rosnąca po pozycji.
static func _keys(p: float, keys: Array) -> float:
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if p <= float(b[0]):
			var f := (p - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), f)
	return float(keys[keys.size() - 1][1])

func _fog(c: CanvasItem, r: Rect2, peak: float) -> void:
	var c0 := Color(0.62, 0.70, 0.68, 0.0)
	var c1 := Color(0.62, 0.70, 0.68, peak)
	var mid := r.position.y + r.size.y * 0.5
	var x0 := r.position.x
	var x1 := r.end.x
	c.draw_polygon(PackedVector2Array([Vector2(x0, r.position.y), Vector2(x1, r.position.y), Vector2(x1, mid), Vector2(x0, mid)]),
		PackedColorArray([c0, c0, c1, c1]))
	c.draw_polygon(PackedVector2Array([Vector2(x0, mid), Vector2(x1, mid), Vector2(x1, r.end.y), Vector2(x0, r.end.y)]),
		PackedColorArray([c1, c1, c0, c0]))

## Niebo (gradient w dół) i ciepła poświata od lampy na dole z lewej.
func _draw_sky(c: CanvasItem) -> void:
	var w := size.x
	var top := Color("030405")
	var mid := Color("0a0c0c")
	var bot := Color("12130f")
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 396), Vector2(0, 396)]), PackedColorArray([top, top, mid, mid]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 396), Vector2(w, 396), Vector2(w, 720), Vector2(0, 720)]), PackedColorArray([mid, mid, bot, bot]))
	c.draw_texture_rect(_glow, Rect2(Vector2(0.13 * 1280.0 - 380.0, 0.88 * 720.0 - 190.0), Vector2(760, 380)), false, Color(1, 1, 1, 0.32))

## Za dalszymi sosnami: sylwetka obserwatora (kilka sekund w cyklu 11 s), słup z mrugającym światłem, dryfująca mgła.
func _draw_mid(c: CanvasItem) -> void:
	var w := size.x
	var wp := fposmod(_t, 11.0) / 11.0
	var wa := _keys(wp, [[0.0, 0.0], [0.62, 0.0], [0.66, 0.85], [0.92, 0.85], [0.96, 0.0], [1.0, 0.0]])
	if wa > 0.01:
		var sil := Color(0.027, 0.035, 0.039, wa)
		c.draw_rect(Rect2(800, 300, 9, 150), sil)
		c.draw_colored_polygon(PackedVector2Array([Vector2(788, 330), Vector2(797, 326), Vector2(800, 400), Vector2(791, 402)]), sil)
		c.draw_colored_polygon(PackedVector2Array([Vector2(821, 326), Vector2(812, 322), Vector2(809, 396), Vector2(818, 398)]), sil)
		c.draw_circle(Vector2(804, 300), 13, sil)
		c.draw_circle(Vector2(799, 288), 2.4, Color(0.91, 0.92, 0.87, wa))
		c.draw_circle(Vector2(810, 288), 2.4, Color(0.91, 0.92, 0.87, wa))
	var pole := Color("101211")
	for seg in [[1012, 150, 972, 470], [1012, 150, 1052, 470], [984, 360, 1040, 360], [978, 410, 1046, 410], [992, 300, 1032, 300],
			[1000, 240, 1024, 240], [984, 360, 1032, 300], [1040, 360, 992, 300]]:
		c.draw_line(Vector2(seg[0], seg[1]), Vector2(seg[2], seg[3]), pole, 5.0)
	var bp := fposmod(_t, 4.6) / 4.6
	var beacon := _keys(bp, [[0.0, 0.08], [0.82, 0.08], [0.88, 0.95], [1.0, 0.95]]) if Settings.fx_mult() > 0.0 else 0.6
	c.draw_circle(Vector2(1012, 144), 30.0, Color(UiTheme.DANGER, 0.12 * beacon))
	c.draw_circle(Vector2(1012, 144), 6.0, Color(UiTheme.DANGER, beacon))
	var dp := fposmod(_t, 52.0) / 26.0
	var drift := -60.0 * (dp if dp <= 1.0 else 2.0 - dp)
	_fog(c, Rect2(-80.0 + drift, 400, w + 220.0, 130), 0.16)

## Na wierzchu: ziemia, chata z lampą, niska mgła, winieta.
func _draw_front(c: CanvasItem) -> void:
	var w := size.x
	c.draw_rect(Rect2(0, 640, w, 80), Color("020202"))
	var lp := fposmod(_t, 7.0) / 7.0
	var lamp := _keys(lp, [[0.0, 0.9], [0.08, 0.35], [0.10, 0.95], [0.41, 0.8], [0.43, 0.2], [0.46, 0.9], [0.70, 0.85], [1.0, 0.9]]) if Settings.fx_mult() > 0.0 else 0.85
	c.draw_texture_rect(_glow, Rect2(Vector2(20, 468), Vector2(260, 260)), false, Color(1, 1, 1, lamp))
	c.draw_rect(Rect2(124, 580, 52, 38), Color(UiTheme.ACCENT, 0.85 * lamp))
	c.draw_line(Vector2(150, 580), Vector2(150, 618), Color("1f1408"), 3.0)
	c.draw_line(Vector2(124, 599), Vector2(176, 599), Color("1f1408"), 3.0)
	c.draw_colored_polygon(PackedVector2Array([Vector2(108, 580), Vector2(192, 580), Vector2(150, 548)]), Color("060706"))
	_fog(c, Rect2(0, 420, w, 160), 0.112)
	c.draw_texture_rect(_vignette, Rect2(0, 0, w, 720), false)
