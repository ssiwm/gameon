extends Control
## Portret / miniatura wpisu kodeksu (bestiariusz, bronie). Dwa tryby:
##   full — duży portret w menu: tło z gradientem i poświatą w kolorze wpisu, podłoga z cieniem, nawiasy w rogach;
##   thumb — mała miniatura w wierszu listy.
## Pixel-art jest rysowany OSTRO (NEAREST + całkowita skala ekranu, pixel_art.gd), z obrysem i warstwą świecącą.
##
## spec: {type: "sprite", sheet, anim} | {type: "gun", row} | {type: "vein"} | {type: "leech"}; accent: kolor wpisu.

const Sprites := preload("res://scripts/sprites.gd")
const PixelArt := preload("res://scripts/pixel_art.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")

var spec := {}
var accent := Color(1.0, 0.72, 0.28)
var thumb := false
var _t := 0.0
## Tekstury wczytujemy w show_spec (poza `_draw`) — pierwsze wczytanie w trakcie rysowania daje białe prostokąty.
var _tex: Texture2D
var _tex_glow: Texture2D
var _gun_info := {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true

func show_spec(s: Dictionary, col: Color) -> void:
	spec = s
	accent = col
	_t = 0.0
	_tex = null
	_tex_glow = null
	match s.get("type", ""):
		"sprite":
			if Sprites.has(s["sheet"]):
				_tex = Sprites.texture(Sprites.DIR + String(s["sheet"]) + ".png")
				_tex_glow = Sprites.texture(Sprites.DIR + String(s["sheet"]) + "_glow.png")
		"leech":
			if Sprites.has("leech"):                         # wynurzoną Pijawkę rysuje arkusz; bez niego zostaje rysunek z kodu
				_tex = Sprites.texture(Sprites.DIR + "leech.png")
				_tex_glow = Sprites.texture(Sprites.DIR + "leech_glow.png")
		"gun":
			_gun_info = GunIcon.sheet_info()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var t: String = spec.get("type", "")
	if t == "sprite" or t == "vein" or t == "leech" or t == "item":
		_t += delta
		queue_redraw()

func _draw() -> void:
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev
	_draw_backdrop(px)
	# podłoga: tu stoją stwory (bronie wiszą na środku)
	var floor_y := size.y - (3.0 if thumb else 12.0)
	match spec.get("type", ""):
		"sprite":
			_draw_sprite(floor_y)
		"gun":
			_draw_gun()
		"vein":
			_draw_vein(floor_y)
		"leech":
			_draw_leech(floor_y)
		"item":
			_draw_item(floor_y)
	if not thumb:
		_draw_brackets(px)

func _draw_backdrop(px: float) -> void:
	var top := Color(0.025, 0.03, 0.04, 0.95)
	var bot := Color(0.06, 0.07, 0.09, 0.95)
	if thumb:
		draw_rect(Rect2(Vector2.ZERO, size), top.lerp(bot, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r, accent.g, accent.b, 0.07))
		draw_rect(Rect2(0, size.y - px, size.x, px), Color(accent.r, accent.g, accent.b, 0.35))
		return
	# gradient pionowy
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top, bot, bot]))
	# poświata: koncentryczne okręgi o malejącym promieniu, tło i tak jest przycięte do karty
	var c := Vector2(size.x * 0.5, size.y * 0.58)
	for i in 9:
		var r := size.y * (1.05 - i * 0.1)
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, 0.05))
	# podłoga: linia i miękki cień pod stworem
	var fy := size.y - 12.0
	draw_rect(Rect2(0, fy, size.x, px), Color(1, 1, 1, 0.10))
	draw_rect(Rect2(0, fy + px, size.x, size.y - fy), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(0, size.y - px, size.x, px), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(0, 0, size.x, px), Color(1, 1, 1, 0.06))

func _draw_brackets(px: float) -> void:
	var col := Color(accent.r, accent.g, accent.b, 0.55)
	var l := 8.0
	var m := 3.0
	var w := px * 1.0
	for corner in [Vector2(m, m), Vector2(size.x - m, m), Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		draw_rect(Rect2(corner + Vector2(0, 0), Vector2(l * sx, w * sy)).abs(), col)
		draw_rect(Rect2(corner + Vector2(0, 0), Vector2(w * sx, l * sy)).abs(), col)

func _shadow(center_x: float, floor_y: float, width: float) -> void:
	# elipsa przez przeskalowanie osi Y
	draw_set_transform(Vector2(center_x, floor_y), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, width * 0.5, Color(0, 0, 0, 0.45))
	draw_circle(Vector2.ZERO, width * 0.32, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_sprite(floor_y: float) -> void:
	var sheet: String = spec["sheet"]
	if not Sprites.has(sheet):
		return
	var man: Dictionary = Sprites.manifest()["sheets"][sheet]
	var fr: Array = man["frame"]
	var an: Dictionary = man["anims"].get(spec["anim"], {"row": 0, "frames": 1, "fps": 1})
	var frame := int(_t * float(an["fps"])) % maxi(1, int(an["frames"]))
	var fsz := Vector2(float(fr[0]), float(fr[1]))
	var avail := Vector2(size.x - 6.0, floor_y - 3.0)
	var s := PixelArt.fit(self, fsz, avail, 8 if not thumb else 3)
	var w := fsz * s
	var pos := PixelArt.snap(self, Vector2((size.x - w.x) * 0.5, floor_y - w.y))
	_shadow(pos.x + w.x * 0.5, floor_y, w.x * 1.1)
	var src := Rect2(frame * fsz.x, int(an["row"]) * fsz.y, fsz.x, fsz.y)
	var tex := _tex
	if tex == null:
		return
	draw_texture_rect_region(tex, Rect2(pos, w), src)
	if bool(man.get("glow", false)):
		var g := _tex_glow
		if g != null:
			draw_texture_rect_region(g, Rect2(pos, w), src)

func _draw_gun() -> void:
	var info := _gun_info
	if info.is_empty():
		return
	var tex: Texture2D = info["tex"]
	if tex == null:
		return
	var fsz := Vector2(info["fw"], info["fh"])
	var s := PixelArt.fit(self, fsz, size - Vector2(10.0, 10.0), 12 if not thumb else 2)
	var gs := fsz * s
	var dst := Rect2(PixelArt.snap(self, (size - gs) * 0.5), gs)
	var src := Rect2(0, int(spec["row"]) * fsz.y, fsz.x, fsz.y)
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev
	if not thumb:
		# „planszet": pasek w kolorze smugi pocisku i delikatna linia lufy
		draw_rect(Rect2(0, size.y - 2.0, size.x, 2.0), Color(accent.r, accent.g, accent.b, 0.8))
		draw_rect(Rect2(dst.position.x - 8.0, dst.position.y + gs.y + 4.0, gs.x + 16.0, px), Color(1, 1, 1, 0.08))
	draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, s), dst.size), src, Color(0, 0, 0, 0.5))
	var o := px * maxf(1.0, floorf(s * dev * 0.5))
	for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_texture_rect_region(tex, Rect2(dst.position + d * o, dst.size), src, Color(0, 0, 0, 0.9))
	draw_texture_rect_region(tex, dst, src)
	var g: Texture2D = info["glow"]
	if g != null:
		draw_texture_rect_region(g, dst, src)

## Żyła: masa cielsk i otwierająca się paszcza — uproszczona wersja tego, co rysuje boss.gd.
## Pijawka w kodeksie: cykl 6 s — cień i kręgi pod wodą, wynurzenie, otwarta paszcza, zanurzenie (jak w walce, uproszczone).
func _draw_leech(floor_y: float) -> void:
	var k := minf(size.x / 150.0, (floor_y + 6.0) / 62.0)
	var cx := size.x * 0.5
	var cyc := fposmod(_t, 6.0)
	var up := 0.0
	if cyc >= 2.4 and cyc < 3.0:
		up = (cyc - 2.4) / 0.6
	elif cyc >= 3.0 and cyc < 5.4:
		up = 1.0
	elif cyc >= 5.4:
		up = 1.0 - (cyc - 5.4) / 0.6
	# woda: pas pod linią podłogi i kręgi
	draw_rect(Rect2(0, floor_y, size.x, size.y - floor_y + 2.0), Color(0.12, 0.3, 0.34, 0.55))
	for i in 3:
		var ph := fposmod(_t * 0.9 + float(i) * 0.33, 1.0)
		draw_arc(Vector2(cx, floor_y), (8.0 + ph * 40.0) * k, PI, TAU, 18, Color(0.55, 0.78, 0.74, (1.0 - ph) * 0.6), 1.0)
	# cień pod wodą (zanim się wynurzy)
	if up < 0.95:
		var a := 0.85 * (1.0 - up)
		draw_set_transform(Vector2(cx, floor_y + 5.0 * k), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2(-6.0 * k, 0), 22.0 * k, Color(0.02, 0.07, 0.07, a))
		draw_circle(Vector2(8.0 * k, 0), 14.0 * k, Color(0.02, 0.07, 0.07, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(cx + 12.0 * k, floor_y + 5.0 * k), 1.6 * k, Color(0.85, 0.95, 0.9, a))
		draw_circle(Vector2(cx + 18.0 * k, floor_y + 5.0 * k), 1.6 * k, Color(0.85, 0.95, 0.9, a))
	if _tex != null:
		if up > 0.02:
			_draw_leech_sprite(floor_y, up, cyc)
		return
	if up > 0.02:
		var skin := Color(0.2, 0.32, 0.27)
		for i in 6:
			var f := float(i) / 5.0
			var y := floor_y - (4.0 + f * 28.0 * up) * k
			var r := (11.0 - f * 3.5) * k
			draw_circle(Vector2(cx + sin(_t * 3.0) * 2.0 * f * k, y), r, skin)
			draw_rect(Rect2(cx - r + 2.0 * k, y + r * 0.35, r * 2.0 - 4.0 * k, maxf(1.0, k)), Color(0.5, 0.38, 0.32))
		var hy := floor_y - (4.0 + 31.0 * up) * k
		draw_circle(Vector2(cx, hy), 9.0 * k, skin)
		draw_circle(Vector2(cx + 5.0 * k, hy + 2.0 * k), 6.0 * k, Color(0.55, 0.1, 0.12))
		for j in 5:
			var ang := -0.5 + float(j) * 0.5
			var o := Vector2(cx + 5.0 * k, hy + 2.0 * k)
			draw_line(o + Vector2(cos(ang), sin(ang)) * 4.0 * k, o + Vector2(cos(ang), sin(ang)) * 7.5 * k, Color(0.92, 0.9, 0.8), maxf(1.0, k * 0.8))
		draw_rect(Rect2(cx - 4.0 * k, hy - 4.0 * k, 2.0 * k, 2.0 * k), Color(0.95, 0.9, 0.5))

## Wynurzona Pijawka z arkusza: wynurza się od góry (okno przycięte przy linii wody), w środku cyklu otwiera paszczę szeroko („grab").
func _draw_leech_sprite(floor_y: float, up: float, cyc: float) -> void:
	var man: Dictionary = Sprites.manifest()["sheets"]["leech"]
	var fr: Array = man["frame"]
	var an_name := "grab" if (cyc >= 3.8 and cyc < 4.9) else "idle"
	var an: Dictionary = man["anims"][an_name]
	var frame := int(_t * float(an["fps"])) % int(an["frames"])
	var top := 8.0                                             # pusty margines nad głową: bez niego skala przeskakuje na 1/2
	var rows := 154.0 - top                                    # wiersze arkusza do dołu piany (linia wody = wiersz 148)
	var fsz := Vector2(float(fr[0]), float(fr[1]))
	var s := PixelArt.fit(self, Vector2(fsz.x, rows), Vector2(size.x - 6.0, floor_y + 6.0), 8 if not thumb else 3)
	var shown := rows * up
	var bottom := floor_y + (154.0 - 148.0) * s * up
	var pos := PixelArt.snap(self, Vector2((size.x - fsz.x * s) * 0.5, bottom - shown * s))
	var src := Rect2(frame * fsz.x, int(an["row"]) * fsz.y + top, fsz.x, shown)
	var dst := Rect2(pos, Vector2(fsz.x * s, shown * s))
	draw_texture_rect_region(_tex, dst, src)
	if _tex_glow != null and bool(man.get("glow", false)):
		draw_texture_rect_region(_tex_glow, dst, src)

## Ekwipunek zużywalny (karta GEAR): ta sama bryła co miniatura w warsztacie (item_icon.gd), większa, z cieniem i obrysem.
func _draw_item(floor_y: float) -> void:
	var kind := String(spec.get("kind", "frag"))
	var dev := PixelArt.device_scale(self)
	var px := 1.0 / dev
	var s := PixelArt.snap_scale(self, maxf(1.0, floorf(size.y * 0.5 / 14.0)))
	var cx := roundf(size.x * 0.5)
	var y := roundf(floor_y - (1.0 if thumb else 5.0))          # miniatura na liście ma ~20 px — bryła nie może wyjść za górną krawędź
	_shadow(cx, floor_y, 22.0 * s * 0.6)
	ItemIcon.draw_glyph(self, kind, cx, y + maxf(px, s), s, _t, accent, Color(0, 0, 0, 0.5))
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		ItemIcon.draw_glyph(self, kind, cx + o.x * px, y + o.y * px, s, _t, accent, Color(0, 0, 0, 0.85))
	ItemIcon.draw_glyph(self, kind, cx, y, s, _t, accent)

func _draw_vein(floor_y: float) -> void:
	var k := minf(size.x / 150.0, (floor_y + 6.0) / 62.0)
	var c := Vector2(size.x * 0.5, floor_y - 22.0 * k)
	_shadow(c.x, floor_y, 90.0 * k)
	var breathe := 1.0 + 0.04 * sin(_t * 2.0)
	var base := Color(0.42, 0.18, 0.22)
	draw_circle(c + Vector2(0, -2) * k, 24.0 * breathe * k, base)
	draw_circle(c + Vector2(-26, 4) * k, 14.0 * breathe * k, base.darkened(0.15))
	draw_circle(c + Vector2(26, 4) * k, 14.0 * breathe * k, base.darkened(0.1))
	draw_circle(c + Vector2(-12, -20) * k, 11.0 * k, base.lightened(0.05))
	draw_circle(c + Vector2(13, -18) * k, 10.0 * k, base.lightened(0.03))
	var maw := (3.0 + 3.0 * (0.5 + 0.5 * sin(_t * 1.3))) * k
	draw_circle(c + Vector2(0, 0), maw + 4.0 * k, Color(0.06, 0.02, 0.03))
	draw_circle(c + Vector2(0, 0), maw, Color(0.75, 0.25, 0.2, 0.75))
	draw_circle(c + Vector2(-9, -9) * k, 2.0 * k, Color(1.0, 0.7, 0.3))
	draw_circle(c + Vector2(9, -9) * k, 2.0 * k, Color(1.0, 0.7, 0.3))
