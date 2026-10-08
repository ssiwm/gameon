extends RefCounted
## Arkusze sprite'ów z tools/bake_sprites.py (wariant A, 1.5) — albo od
## artysty (wariant C): ten sam układ PNG + art/sprites.json, zero zmian w kodzie.
##
## Każda postać ma dwie warstwy o identycznych klatkach:
##   ciało  — cieniowane (widać je tylko w świetle, §8.3)
##   glow   — unshaded (oczy, żyłki) — świeci w ciemności

const Lights := preload("res://scripts/lights.gd")
const Look := preload("res://scripts/look.gd")
const MANIFEST := "res://art/sprites.json"
const DIR := "res://art/sprites/"

static var _data: Dictionary = {}
static var _cache: Dictionary = {}
## Dev (--newchar[=male|female|mix|tripo[-male|-female|-mix]]): zamiast arkuszy player_1..4 rysuj postacie 3D (arkusze playerhd_* z MakeHuman albo
## playerhd3_* z modeli Tripo; tools/pack_chars3d.py). Pusty = wyłączone.
static var newchar := ""
## Dev (--newgun): broń z arkuszy HD `gunhd_<klucz>.png` (+ `_n.png`), jeśli istnieją (na razie m83); reszta broni jak dotąd.
static var newgun := false
## Dev (--newmon): wrogowie z arkuszy HD `<rodzaj>_hd` (Tripo → tools/pack_monsters_hd.py), jeśli istnieją; reszta po staremu.
static var newmon := false

static func enemy_sheet(kind: String) -> String:
	if newmon and has(kind + "_hd"):
		return kind + "_hd"
	return kind
## Dev (--newworld): świat HD — teren z art/world/terrain_hd(.png/_n.png), tła HD i rekwizyty HD (art/world/), jeśli istnieją.
static var newworld := false

static var _gunhd: Dictionary = {}
static var _gunhd_rect: Dictionary = {}

## Warstwa świecenia broni HD (gunhd_<klucz>_glow.png) albo null.
static func gun_hd_glow(key: String) -> Texture2D:
	if not newgun:
		return null
	var path := DIR + "gunhd_%s_glow.png" % key
	if not ResourceLoader.exists(path):
		return null
	return mip_texture(path)

## Prostokąt sylwetki broni HD w pikselach arkusza (po wywołaniu `gun_hd`).
static func gun_hd_rect(key: String) -> Rect2:
	return _gunhd_rect.get(key, Rect2())
static var _mip: Dictionary = {}

## Tekstura HD z mipmapami skompresowana w locie do S3TC (DXT5): ~4× mniej pamięci wideo przy kilku ms na arkusz (zmierzone: 2048×2688 → 5 ms).
## Mapy normalnych dostają kompresję „normal". Gdy kompresja się nie uda (platforma bez S3TC) zostaje RGBA8 z mipmapami.
static func hd_texture(img: Image, normal := false) -> ImageTexture:
	var im := img.duplicate() as Image
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	im.generate_mipmaps()
	if compress_hd:
		var keep := im.duplicate() as Image
		if im.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC) != OK:
			im = keep
	return ImageTexture.create_from_image(im)

## Kompresja tekstur HD (dev): `--nocompress` ją wyłącza do porównań jakości i pamięci.
static var compress_hd := true

## Arkusz z mipmapami (ImageTexture) — dla UI rysującego duże klatki HD w małym rozmiarze (kodeks): bez mipmap zmniejszanie ×4 daje szum.
static func mip_texture(path: String) -> Texture2D:
	if _mip.has(path):
		return _mip[path]
	var t: Texture2D = null
	var src := texture(path)
	if src != null:
		t = hd_texture(src.get_image(), false)
	_mip[path] = t
	return t

## Czy arkusz jest HD (manifest `hd`).
static func is_hd(sheet: String) -> bool:
	return bool(manifest().get("sheets", {}).get(sheet, {}).get("hd", false))

## Tekstura HD broni (diffuse + normal) albo null. Ramka 576×224 px, dłoń w (104, 112), 16 px na piksel świata.
static func gun_hd(key: String) -> CanvasTexture:
	if not newgun:
		return null
	if _gunhd.has(key):
		return _gunhd[key]
	var d := texture(DIR + "gunhd_%s.png" % key)
	var ct: CanvasTexture = null
	if d != null:
		var gimg: Image = d.get_image()
		gimg.convert(Image.FORMAT_RGBA8)
		_gunhd_rect[key] = Rect2(gimg.get_used_rect())                     # ciasny prostokąt sylwetki (miniatury w UI)
		ct = CanvasTexture.new()
		ct.diffuse_texture = hd_texture(gimg, false)
		var n := texture(DIR + "gunhd_%s_n.png" % key)
		if n != null:
			ct.normal_texture = hd_texture(n.get_image(), true)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_gunhd[key] = ct
	return ct

## Arkusz bota: przy postaciach HD z Tripo (`--newchar=tripo-hd…`) bot jest kobietą Scavenger '87 (`playerhd3h_female`), inaczej klasyczny „bot".
static func bot_sheet() -> String:
	if newchar.begins_with("tripo-hd") and has("playerhd3h_female"):
		return "playerhd3h_female"
	return "bot"

## Arkusz ciała gracza: dev-postać 3D (jeśli włączona i spakowana) albo klasyczny player_N.
static func player_sheet(display_id: int, look := -1) -> String:
	if newchar == "tripo-hd-look":                  # wygląd z profilu (Look): płeć i strój wybrane w warsztacie; bez replikacji (look < 0) — domyślnie wg numeru gracza
		var c := look if Look.is_valid(look) else Look.code(0 if display_id % 2 == 1 else 1, 0)
		if has(Look.sheet(c)):
			return Look.sheet(c)
	if newchar != "":
		var prefix := "playerhd_"
		var mode := newchar
		if newchar.begins_with("tripo"):
			prefix = "playerhd3_"
			mode = newchar.trim_prefix("tripo").trim_prefix("-")
			if mode.begins_with("hd"):                                   # tripo-hd[-male|-female|-mix]: klatki 256×384 z mapami normalnych
				prefix = "playerhd3h_"
				mode = mode.trim_prefix("hd").trim_prefix("-")
			if mode == "":
				mode = "male"
		var g := mode if mode != "mix" else ("male" if display_id % 2 == 1 else "female")
		if not has(prefix + g):
			g = "male"
		if has(prefix + g):
			return prefix + g
	return "player_%d" % ((display_id - 1) % 4 + 1)

static func manifest() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(MANIFEST):
		_data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return _data

static func has(sheet: String) -> bool:
	return manifest().get("sheets", {}).has(sheet) and ResourceLoader.exists(DIR + sheet + ".png")

## Skala rysowania arkusza w świecie (domyślnie 1). Arkusz broni ma 2× gęstość pikseli i skalę 0,5.
static func scale_of(sheet: String) -> float:
	return float(manifest().get("sheets", {}).get(sheet, {}).get("scale", 1.0))

static func frame_size(sheet: String) -> Vector2:
	var f: Array = manifest()["sheets"][sheet]["frame"]
	return Vector2(f[0], f[1])

static func frames(sheet: String, glow := false) -> SpriteFrames:
	var key := sheet + ("_glow" if glow else "")
	if _cache.has(key):
		return _cache[key]
	if not glow and bool(manifest().get("sheets", {}).get(sheet, {}).get("normal", false)):
		var hd := _frames_hd(sheet)
		if hd != null:
			_cache[key] = hd
			return hd
	var path := DIR + key + ".png"
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var info: Dictionary = manifest()["sheets"][sheet]
	var fw: int = info["frame"][0]
	var fh: int = info["frame"][1]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for an in info["anims"]:
		var a: Dictionary = info["anims"][an]
		sf.add_animation(an)
		sf.set_animation_speed(an, float(a["fps"]))
		sf.set_animation_loop(an, bool(a["loop"]))
		for i in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.filter_clip = scale_of(sheet) != 1.0                       # arkusz w innej gęstości: filtrowanie nie podciąga sąsiedniej klatki
			at.region = Rect2(i * fw, int(a["row"]) * fh, fw, fh)
			sf.add_frame(an, at)
	_cache[key] = sf
	return sf

## Arkusz HD z mapą normalnych (`NAZWA_n.png`): każda klatka to osobna `CanvasTexture` (diffuse + normal) z mipmapami — AtlasTexture nie niesie mapy normalnych,
## a mipmapy chronią przed szumem przy zmniejszaniu (np. okno 720p rysuje klatkę 256×384 w ok. 77 px).
static func _frames_hd(sheet: String) -> SpriteFrames:
	var dtex := texture(DIR + sheet + ".png")
	var ntex := texture(DIR + sheet + "_n.png")
	if dtex == null:
		return null
	var info: Dictionary = manifest()["sheets"][sheet]
	var fw: int = info["frame"][0]
	var fh: int = info["frame"][1]
	var dimg: Image = dtex.get_image()
	var nimg: Image = ntex.get_image() if ntex != null else null
	if dimg == null:
		return null
	dimg.convert(Image.FORMAT_RGBA8)
	if nimg != null:
		nimg.convert(Image.FORMAT_RGBA8)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for an in info["anims"]:
		var a: Dictionary = info["anims"][an]
		sf.add_animation(an)
		sf.set_animation_speed(an, float(a["fps"]))
		sf.set_animation_loop(an, bool(a["loop"]))
		for i in int(a["frames"]):
			var r := Rect2i(i * fw, int(a["row"]) * fh, fw, fh)
			var ct := CanvasTexture.new()
			ct.diffuse_texture = hd_texture(dimg.get_region(r), false)
			if nimg != null:
				ct.normal_texture = hd_texture(nimg.get_region(r), true)
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sf.add_frame(an, ct)
	return sf

## Tworzy warstwy postaci pod `host`: [ciało, glow albo null]. Stopy w (0,0).
static func attach(host: Node2D, sheet: String) -> Array:
	var size := frame_size(sheet)
	var sc := scale_of(sheet)
	# arkusz o gęstości ≠ 1 (np. boss 2×, skala 0,5) rysujemy filtrem liniowym — gładki obrót i krawędzie, bez nierównych pikseli
	var filt := CanvasItem.TEXTURE_FILTER_NEAREST if sc == 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR
	if bool(manifest()["sheets"][sheet].get("hd", false)):
		filt = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var body := AnimatedSprite2D.new()
	body.name = "Body"
	body.sprite_frames = frames(sheet)
	body.texture_filter = filt
	body.scale = Vector2(sc, sc)
	body.offset = Vector2(0, -size.y * 0.5)
	host.add_child(body)
	var glow: AnimatedSprite2D = null
	var gf := frames(sheet, true)
	if gf != null:
		glow = AnimatedSprite2D.new()
		glow.name = "Glow"
		glow.sprite_frames = gf
		glow.texture_filter = filt
		glow.scale = body.scale
		glow.offset = body.offset
		glow.material = Lights.unshaded()
		host.add_child(glow)
	return [body, glow]

## Ustawia animację na obu warstwach (glow trzyma tę samą klatkę).
static func play(layers: Array, anim: String, flip: bool) -> void:
	var body: AnimatedSprite2D = layers[0]
	if body.animation != anim:
		body.play(anim)
	body.flip_h = flip
	var glow: AnimatedSprite2D = layers[1]
	if glow != null:
		if glow.animation != anim:
			glow.play(anim)
		glow.frame = body.frame
		glow.flip_h = flip
		glow.scale = body.scale

## Gotowe sprite'y gracza / kafle / dekoracje.
static func texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
