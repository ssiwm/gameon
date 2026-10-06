extends Control
## Miniatura broni z arkusza guns.png (wiersz = `gun_row`): sylwetka z obrysem i cieniem, warstwa świecąca,
## opcjonalnie „płytka" (ciemne tło z poświatą i paskiem w kolorze smugi pocisku). Rysowana ostro:
## filtr NEAREST i skala dobrana tak, by piksel rysunku = całkowita liczba pikseli ekranu (pixel_art.gd).
## `k` = żądana skala lokalna; `tint` przygasza bronie niewybrane.

const PixelArt := preload("res://scripts/pixel_art.gd")

const GUN_SHEET := "res://art/sprites/guns.png"
const GUN_GLOW := "res://art/sprites/guns_glow.png"
const FW := 24
const FH := 9

var row := -1
var k := 1
var plate := false
var accent := Color(1.0, 0.85, 0.35)
var tint := Color.WHITE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_gun(r: int, col: Color, t: Color) -> void:
	if r == row and col == accent and t == tint:
		return
	row = r
	accent = col
	tint = t
	queue_redraw()

## Obszar bez paska akcentu (płytka ma 2 px paska na dole).
func plate_inset() -> Vector2:
	return Vector2(size.x, size.y - (2.0 if plate else 0.0))

func _draw() -> void:
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev                                       # jeden piksel ekranu w jednostkach lokalnych
	if plate:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.78))
		draw_rect(Rect2(0, 0, size.x, px), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(0, size.y - 2.0, size.x, 2.0), Color(accent.r, accent.g, accent.b, 0.85))
		# miękka poświata za bronią: kilka coraz mniejszych prostokątów
		for i in 4:
			var inset := 2.0 + i * 4.0
			draw_rect(Rect2(inset, inset * 0.5, size.x - 2.0 * inset, size.y - 2.0 - inset), Color(accent.r, accent.g, accent.b, 0.045))
	if row < 0 or not ResourceLoader.exists(GUN_SHEET):
		return
	var tex: Texture2D = load(GUN_SHEET)
	var s := PixelArt.snap_scale(self, float(k))
	var gs := Vector2(FW, FH) * s
	var body := plate_inset()
	var dst := Rect2(PixelArt.snap(self, (body - gs) * 0.5 + Vector2(0, 1)), gs)
	var src := Rect2(0, row * FH, FW, FH)
	# cień pod bronią i obrys 1 px ekranu (nie 0,5 piksela rysunku)
	draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, s), dst.size), src, Color(0, 0, 0, 0.55))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_texture_rect_region(tex, Rect2(dst.position + o * px * maxf(1.0, floorf(s * dev * 0.5)), dst.size), src, Color(0, 0, 0, 0.85 * tint.a))
	draw_texture_rect_region(tex, dst, src, tint)
	if ResourceLoader.exists(GUN_GLOW):
		draw_texture_rect_region(load(GUN_GLOW), dst, src, Color(1, 1, 1, tint.a))
