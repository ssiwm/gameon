extends Control
## Ikona HUD-u z modelu 3D (art/hud/<klucz>.png, wypiekana przez tools/bake_hud_icons.gd): wpisana w pole z zachowaniem proporcji,
## wyśrodkowana, z miękkim cieniem pod spodem (zamiast ramki). `tint` przygasza (np. pusty zasób, niewybrana broń).
## Teksturę ładujemy w set_key(), nie w _draw: pierwsze wczytanie w trakcie rysowania daje w Godocie białe prostokąty (jak w gun_icon.gd).

const DIR := "res://art/hud/"

static var _cache := {}

var key := ""
var tint := Color.WHITE
var shadow := true
var _tex: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Tekstura ikony albo null, gdy modelu brak (pamięć podręczna także dla braków).
static func texture_of(k: String) -> Texture2D:
	if k == "":
		return null
	if not _cache.has(k):
		var path := DIR + k + ".png"
		_cache[k] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[k]

func set_key(k: String, t := Color.WHITE) -> void:
	if k == key and t == tint:
		return
	if k != key:
		key = k
		_tex = texture_of(k)
	tint = t
	queue_redraw()

func _draw() -> void:
	if _tex == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var ts := _tex.get_size()
	var s := minf(size.x / ts.x, size.y / ts.y)
	var dst := Rect2((size - ts * s) * 0.5, ts * s)
	if shadow:
		draw_texture_rect(_tex, Rect2(dst.position + Vector2(0.0, size.y * 0.05), dst.size), false, Color(0, 0, 0, 0.55 * tint.a))
	draw_texture_rect(_tex, dst, false, tint)
