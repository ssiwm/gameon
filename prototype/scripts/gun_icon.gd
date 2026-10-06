extends Control
## Miniatura broni z arkusza guns.png (wiersz = `gun_row`): sylwetka z obrysem i cieniem, warstwa świecąca,
## opcjonalnie „płytka" (ciemne tło z poświatą i paskiem w kolorze smugi pocisku). Całkowita skala `k` —
## ułamki rozmywają pixel-art. `tint` przygasza bronie niewybrane.
const GUN_SHEET := "res://art/sprites/guns.png"
const GUN_GLOW := "res://art/sprites/guns_glow.png"

const FW := 24
const FH := 9

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

var row := -1
var k := 1
var plate := false
var accent := Color(1.0, 0.85, 0.35)
var tint := Color.WHITE

func set_gun(r: int, col: Color, t: Color) -> void:
	if r == row and col == accent and t == tint:
		return
	row = r
	accent = col
	tint = t
	queue_redraw()

func _draw() -> void:
	if plate:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.78))
		draw_rect(Rect2(0, 0, size.x, 1), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(0, size.y - 2, size.x, 2), Color(accent.r, accent.g, accent.b, 0.85))
		# miękka poświata za bronią: kilka coraz mniejszych prostokątów
		for i in 4:
			var inset := 2.0 + i * 4.0
			draw_rect(Rect2(inset, inset * 0.5, size.x - 2.0 * inset, size.y - 2.0 - inset), Color(accent.r, accent.g, accent.b, 0.045))
	if row < 0 or not ResourceLoader.exists(GUN_SHEET):
		return
	var tex: Texture2D = load(GUN_SHEET)
	var gs := Vector2(FW * k, FH * k)
	var body := plate_inset()
	var dst := Rect2(((body - gs) * 0.5).round() + Vector2(0, 1), gs)
	var src := Rect2(0, row * FH, FW, FH)
	draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, k), dst.size), src, Color(0, 0, 0, 0.55))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_texture_rect_region(tex, Rect2(dst.position + o * float(maxi(1, k / 2)), dst.size), src, Color(0, 0, 0, 0.85 * tint.a))
	draw_texture_rect_region(tex, dst, src, tint)
	if ResourceLoader.exists(GUN_GLOW):
		draw_texture_rect_region(load(GUN_GLOW), dst, src, Color(1, 1, 1, tint.a))
## Obszar bez paska akcentu (płytka ma 2 px paska na dole).

func plate_inset() -> Vector2:
	return Vector2(size.x, size.y - (2.0 if plate else 0.0))
