extends Control
## Miniatura broni (wiersz = `gun_row`) z arkusza gun_icons.png (64×24, wysoka jakość); gdy go brak — ze starego
## guns.png. Sylwetka z obrysem i cieniem, warstwa świecąca, opcjonalnie „płytka" (ciemne tło z poświatą i paskiem
## w kolorze smugi pocisku). Rysowana ostro: filtr NEAREST i skala dobrana tak, by piksel rysunku = całkowita liczba
## pikseli ekranu albo 1/2, 1/3… (pixel_art.gd). `k` = żądana skala lokalna; `tint` przygasza bronie niewybrane.

const PixelArt := preload("res://scripts/pixel_art.gd")
const Sprites := preload("res://scripts/sprites.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
## Wiersze guns.png, dla których jest broń HD (gunhd_<klucz>.png): z --newui --newgun miniatura używa jej zamiast pikselowej.
const HD_KEYS := {0: "m83", 1: "spread12", 2: "p64", 3: "srut8", 4: "lr7", 5: "hkm9", 6: "gniew4", 7: "sokol6", 8: "widmo1", 9: "ciegno6", 10: "maczeta", 11: "kilof"}

var row := -1
var k := 0.375
var plate := false
var accent := Color(1.0, 0.85, 0.35)
var tint := Color.WHITE

## Tekstury ładujemy W KONSTRUKTORZE, nie w `_draw`: tekstura wczytana po raz pierwszy w trakcie rysowania daje w Godocie
## białe prostokąty (sprawdzone w silniku 4.7) i zostaje taka, dopóki kontrolka się nie przerysuje.
var _info := {}

## Arkusz do miniatur: {tex, glow, fw, fh}; tex = null, gdy nie ma żadnego.
static func sheet_info() -> Dictionary:
	var sheet := "gun_icons" if Sprites.has("gun_icons") else "guns"
	if not Sprites.has(sheet):
		return {"tex": null, "glow": null, "fw": 24, "fh": 9}
	var fs := Sprites.frame_size(sheet)
	return {"tex": Sprites.texture(Sprites.DIR + sheet + ".png"), "glow": Sprites.texture(Sprites.DIR + sheet + "_glow.png"),
		"fw": int(fs.x), "fh": int(fs.y)}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_info = sheet_info()

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

## Miniatura z broni HD (albedo bez światła) wpisana w pole z zachowaniem proporcji, z miękkim cieniem — tylko dla broni, które mają model HD.
func _draw_hd(ct: CanvasTexture, rect: Rect2, px: float) -> void:
	var tex: Texture2D = ct.diffuse_texture
	if tex == null or rect.size.x <= 0.0:
		return
	var body := plate_inset()
	var avail := body - Vector2(6.0, 6.0)
	var s := minf(avail.x / rect.size.x, avail.y / rect.size.y)
	var dst := Rect2((body - rect.size * s) * 0.5, rect.size * s)
	draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, 1.2), dst.size), rect, Color(0, 0, 0, 0.5 * tint.a))
	draw_texture_rect_region(tex, dst, rect, tint)

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
	if UiTheme.hd_on() and HD_KEYS.has(row) and Sprites.newgun:
		var key: String = HD_KEYS[row]
		var ct := Sprites.gun_hd(key)
		if ct != null:
			_draw_hd(ct, Sprites.gun_hd_rect(key), px)
			return
	var info := _info
	var tex: Texture2D = info["tex"]
	if row < 0 or tex == null:
		return
	var fw: int = info["fw"]
	var fh: int = info["fh"]
	var s := PixelArt.snap_scale(self, k)
	var gs := Vector2(fw, fh) * s
	var body := plate_inset()
	var dst := Rect2(PixelArt.snap(self, (body - gs) * 0.5 + Vector2(0, 1)), gs)
	var src := Rect2(0, row * fh, fw, fh)
	# cień pod bronią i obrys 1 px ekranu (nie 0,5 piksela rysunku)
	draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, maxf(px, s)), dst.size), src, Color(0, 0, 0, 0.55))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_texture_rect_region(tex, Rect2(dst.position + o * px, dst.size), src, Color(0, 0, 0, 0.85 * tint.a))
	draw_texture_rect_region(tex, dst, src, tint)
	var glow: Texture2D = info["glow"]
	if glow != null:
		draw_texture_rect_region(glow, dst, src, Color(1, 1, 1, tint.a))
