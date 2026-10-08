extends RefCounted
## Przedmioty i rekwizyty HD (art/items/, tools/build_items.sh): granaty i sprzęt, apteczka, skrzynie, flara, złom, beczka, stojak, warsztat…
## Każdy przedmiot to albedo z obrysem (`<nazwa>.png`), mapa normalnych (`_n.png`) i opcjonalna warstwa świecąca (`_glow.png`);
## ramka, gęstość (px na piksel świata) i zapas na obrys opisuje `items.json`. Punkt (0, 0) sprite'a = środek dołu bryły („stopy").
## Włączone razem z grafiką HD (`Sprites.newitem`); bez niej rysunek zostaje po staremu (kod w pickup.gd, prop.gd, item_icon.gd…).

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")

const DIR := "res://art/items/"
const PAD := 6.0                 ## zapas ramki wokół bryły [px] — mieści obrys

static var _man: Dictionary = {}
static var _loaded := false
static var _tex: Dictionary = {}
static var _flat: Dictionary = {}
static var _glow: Dictionary = {}

static func enabled() -> bool:
	return Sprites.newitem

static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var txt := FileAccess.get_file_as_string(DIR + "items.json")
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_man = parsed if parsed is Dictionary else {}
	return _man

static func has(name: String) -> bool:
	return manifest().has(name)

static func ppw(name: String) -> float:
	return float(manifest().get(name, {}).get("ppw", 16.0))

## Poziomy środek bryły w układzie modelu (jednostki = piksele świata): sprite jest wyśrodkowany na bryle, więc punkt (0, 0) modelu leży o `cx` w prawo od stóp sprite'a.
## Pozwala zachować współrzędne z modelu (np. lampki generatora): `sprite.position.x = cx * skala`.
static func cx(name: String) -> float:
	return float(manifest().get(name, {}).get("cx", 0.0))

## Rozmiar całej ramki (z zapasem) w pikselach świata.
static func frame_wp(name: String) -> Vector2:
	var m: Dictionary = manifest().get(name, {})
	return Vector2(float(m.get("w", 16)), float(m.get("h", 16))) / ppw(name)

## Rozmiar samej bryły (bez zapasu na obrys) w pikselach świata.
static func body_wp(name: String) -> Vector2:
	var m: Dictionary = manifest().get(name, {})
	return Vector2(float(m.get("w", 16)) - 2.0 * PAD, float(m.get("h", 16)) - 2.0 * PAD) / ppw(name)

## Ramka w pikselach tekstury.
static func frame_px(name: String) -> Vector2:
	var m: Dictionary = manifest().get(name, {})
	return Vector2(float(m.get("w", 16)), float(m.get("h", 16)))

## Tekstura z mipmapami i skompresowana (jak broń HD): diffuse + normal w CanvasTexture (oświetlana światłami 2D).
static func texture(name: String) -> CanvasTexture:
	if _tex.has(name):
		return _tex[name]
	var ct: CanvasTexture = null
	var d := Sprites.texture(DIR + name + ".png")
	if d != null:
		ct = CanvasTexture.new()
		ct.diffuse_texture = Sprites.hd_texture(d.get_image(), false)
		var n := Sprites.texture(DIR + name + "_n.png")
		if n != null:
			ct.normal_texture = Sprites.hd_texture(n.get_image(), true)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex[name] = ct
	return ct

## Samo albedo (do UI, gdzie nie ma świateł): zwykła tekstura z mipmapami.
static func albedo(name: String) -> Texture2D:
	var ct := texture(name)
	return ct.diffuse_texture if ct != null else null

static func glow_texture(name: String) -> Texture2D:
	if _glow.has(name):
		return _glow[name]
	var t: Texture2D = null
	if bool(manifest().get(name, {}).get("glow", false)):
		var g := Sprites.texture(DIR + name + "_glow.png")
		if g != null:
			t = Sprites.hd_texture(g.get_image(), false)
	_glow[name] = t
	return t

## Sprite oświetlany (z normalnymi), stopy w (0, 0) węzła-rodzica; `scale` mnoży rozmiar. Dodaje też warstwę świecącą (unshaded), jeśli jest.
## `dark_vis` > 0 dodaje kopię „unshaded" o tej przezroczystości — przedmiot widać też w ciemności (jak w wersji pikselowej).
## Zwraca główny Sprite2D (warstwa świecąca i kopia są jego dziećmi).
static func make(name: String, parent: Node2D, scale := 1.0, dark_vis := 0.0) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = texture(name)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.centered = true
	var f := frame_px(name)
	sp.offset = Vector2(0.0, PAD - f.y * 0.5)
	sp.scale = Vector2.ONE * scale / ppw(name)
	parent.add_child(sp)
	var g := glow_texture(name)
	if g != null:
		var gs := Sprite2D.new()
		gs.texture = g
		gs.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		gs.centered = true
		gs.offset = sp.offset
		gs.material = Lights.unshaded()
		sp.add_child(gs)
	if dark_vis > 0.0:
		var vs := Sprite2D.new()
		vs.texture = albedo(name)
		vs.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		vs.centered = true
		vs.offset = sp.offset
		vs.material = Lights.unshaded()
		vs.modulate = Color(1, 1, 1, dark_vis)
		sp.add_child(vs)
	return sp

## Rysuje przedmiot w UI wpisany w prostokąt `area` (środek, z miękkim cieniem). Skala jest wspólna dla wszystkich przedmiotów — mierzona względem
## „wzorcowego" rozmiaru `ref` [piksele świata], żeby mały granat nie rósł do wielkości apteczki — i ograniczona tak, by bryła mieściła się w `area`.
static func draw_fit(ci: CanvasItem, name: String, area: Rect2, mod := Color.WHITE, ref := Vector2(16.0, 13.0)) -> void:
	if not has(name):
		return
	var b := body_wp(name)
	var s := minf(minf(area.size.x / ref.x, area.size.y / ref.y), minf(area.size.x / b.x, area.size.y / b.y))
	var foot := Vector2(area.position.x + area.size.x * 0.5, area.position.y + (area.size.y + b.y * s) * 0.5)
	draw(ci, name, foot + Vector2(0.0, maxf(1.0, s * 0.35)), s, Color(0, 0, 0, 0.45 * mod.a), false)
	draw(ci, name, foot, s, mod)

## Rysuje przedmiot w `ci` (np. w `_draw` panelu): `foot` = środek dołu bryły w pikselach lokalnych, `s` = piksele lokalne na piksel świata.
static func draw(ci: CanvasItem, name: String, foot: Vector2, s: float, mod := Color.WHITE, with_glow := true) -> void:
	var tex := albedo(name)
	if tex == null:
		return
	var f := frame_px(name)
	var k := s / ppw(name)
	var dst := Rect2(foot + Vector2(-f.x * 0.5, PAD - f.y) * k, f * k)
	ci.draw_texture_rect(tex, dst, false, mod)
	if with_glow:
		var g := glow_texture(name)
		if g != null:
			ci.draw_texture_rect(g, dst, false, Color(1, 1, 1, mod.a))
