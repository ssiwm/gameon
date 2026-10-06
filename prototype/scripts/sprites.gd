extends RefCounted
## Arkusze sprite'ów z tools/bake_sprites.py (wariant A, 1.5) — albo od
## artysty (wariant C): ten sam układ PNG + art/sprites.json, zero zmian w kodzie.
##
## Każda postać ma dwie warstwy o identycznych klatkach:
##   ciało  — cieniowane (widać je tylko w świetle, §8.3)
##   glow   — unshaded (oczy, żyłki) — świeci w ciemności

const Lights := preload("res://scripts/lights.gd")
const MANIFEST := "res://art/sprites.json"
const DIR := "res://art/sprites/"

static var _data: Dictionary = {}
static var _cache: Dictionary = {}

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

## Tworzy warstwy postaci pod `host`: [ciało, glow albo null]. Stopy w (0,0).
static func attach(host: Node2D, sheet: String) -> Array:
	var size := frame_size(sheet)
	var sc := scale_of(sheet)
	# arkusz o gęstości ≠ 1 (np. boss 2×, skala 0,5) rysujemy filtrem liniowym — gładki obrót i krawędzie, bez nierównych pikseli
	var filt := CanvasItem.TEXTURE_FILTER_NEAREST if sc == 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR
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
