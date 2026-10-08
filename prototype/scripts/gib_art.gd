extends RefCounted
## Tekstury szczątków HD (mięso, kości, wnętrzności, łuski, odłamki) rysowane raz programowo do małych obrazów — jedna `Sprite2D` na kawałek zamiast
## kilku `Polygon2D`/`Line2D` z wygładzaniem (zmierzone: dziewięć kawałków na zgon kosztowało ~4 ms klatki i ~1000 wywołań rysowania, bo każdy wielokąt
## to osobne wywołanie; tekstury o tym samym obrazie się sklejają). Kolor nadaje `modulate` (mięso, odłamki) albo jest wypalony (kości, flaki, mosiądz).

static var _cache: Dictionary = {}

static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _tex(key: String, build: Callable) -> Texture2D:
	if not _cache.has(key):
		var t := ImageTexture.create_from_image(build.call())
		_cache[key] = t
	return _cache[key]

## Mięso: nieregularna bryłka (kształt z kilku sinusów, wariant 0–3), jasna w środku, ciemna skórka na brzegu, wilgotny połysk. Szarości — tint przez modulate.
static func meat(variant: int) -> Texture2D:
	return _tex("meat%d" % (variant % 4), func() -> Image:
		var n := 32
		var img := _img(n, n)
		var p1 := float(variant) * 1.7
		var p2 := float(variant) * 2.9 + 1.0
		var p3 := float(variant) * 0.8 + 2.0
		for y in n:
			for x in n:
				var px := (float(x) + 0.5) / float(n) * 2.0 - 1.0
				var py := (float(y) + 0.5) / float(n) * 2.0 - 1.0
				var d := Vector2(px, py).length()
				var th := atan2(py, px)
				var r := 0.7 + 0.12 * sin(2.0 * th + p1) + 0.08 * sin(3.0 * th + p2) + 0.05 * sin(5.0 * th + p3)
				var a := clampf((r - d) / 0.07, 0.0, 1.0)
				if a <= 0.0:
					continue
				var t := d / r
				var shade := lerpf(0.95, 0.5, t * t)
				shade *= 1.0 - 0.18 * maxf(0.0, py * 0.8 + px * 0.2)                      # cień od dołu
				var hl := clampf(1.0 - Vector2(px + 0.28, py + 0.3).length() / 0.28, 0.0, 1.0)
				shade = minf(1.0, shade + hl * 0.55)
				img.set_pixel(x, y, Color(shade, shade, shade, a))
		return img)

## Kość: trzon z zgrubieniami na końcach, jasny z góry, ciemniejszy od dołu; jeden koniec splamiony krwią (wypalone kolory).
static func bone() -> Texture2D:
	return _tex("bone", func() -> Image:
		var w := 48
		var h := 16
		var img := _img(w, h)
		for y in h:
			for x in w:
				var px := (float(x) + 0.5) / float(w) * 2.0 - 1.0
				var py := (float(y) + 0.5) / float(h) * 2.0 - 1.0
				var shaft := absf(px) < 0.8 and absf(py) < 0.34
				var dl := Vector2((px + 0.78) * 3.0, py).length()
				var dr := Vector2((px - 0.78) * 3.0, py).length()
				var knob := minf(dl, dr) < 0.62
				if not (shaft or knob):
					continue
				var edge := 1.0
				if shaft and not knob:
					edge = clampf((0.34 - absf(py)) / 0.12, 0.0, 1.0)
				elif knob:
					edge = clampf((0.62 - minf(dl, dr)) / 0.12, 0.0, 1.0)
				var s := 0.92 - 0.28 * clampf(py * 0.5 + 0.5, 0.0, 1.0)
				var col := Color(0.9 * s, 0.84 * s, 0.7 * s, edge)
				if px < -0.82:
					col = col.lerp(Color(0.5, 0.08, 0.1, edge), 0.65)
				img.set_pixel(x, y, col)
		return img)

## Wnętrzności: falująca rurka z ciemnym obrysem, jaśniejszym środkiem i wąskim połyskiem (wypalone różowo-czerwone kolory).
static func gut(variant: int) -> Texture2D:
	return _tex("gut%d" % (variant % 3), func() -> Image:
		var w := 48
		var h := 16
		var img := _img(w, h)
		var ph := float(variant) * 2.1
		for y in h:
			for x in w:
				var u := (float(x) + 0.5) / float(w)
				var cy := 0.5 + 0.2 * sin(u * TAU * 1.3 + ph)
				var v := ((float(y) + 0.5) / float(h) - cy) / 0.2
				var edge_u := clampf(minf(u, 1.0 - u) / 0.06, 0.0, 1.0)
				var dist := absf(v)
				if dist > 1.0:
					continue
				var a := clampf((1.0 - dist) / 0.18, 0.0, 1.0) * edge_u
				var body := lerpf(1.0, 0.5, dist * dist)
				var col := Color(0.78 * body, 0.26 * body, 0.32 * body, a)
				var hl := clampf(1.0 - absf(v + 0.35) / 0.16, 0.0, 1.0) * 0.6
				col = col.lerp(Color(1.0, 0.8, 0.82, a), hl)
				img.set_pixel(x, y, col)
		return img)

## Łuska: walec z jasnym paskiem odblasku i ciemniejszym denkiem; `shell` = śrutowa (czerwony korpus, mosiężna stopka).
static func casing(shell: bool) -> Texture2D:
	return _tex("casing_shell" if shell else "casing", func() -> Image:
		var w := 16
		var h := 8
		var img := _img(w, h)
		for y in h:
			for x in w:
				var u := (float(x) + 0.5) / float(w)
				var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
				var a := clampf((1.0 - absf(v)) / 0.3, 0.0, 1.0)
				if a <= 0.0:
					continue
				var body := Color(0.86, 0.68, 0.3) if not shell else Color(0.62, 0.14, 0.1)
				if shell and u < 0.28:
					body = Color(0.86, 0.68, 0.3)
				var s := lerpf(1.1, 0.55, clampf(v * 0.5 + 0.5, 0.0, 1.0))
				var col := Color(minf(1.0, body.r * s), minf(1.0, body.g * s), minf(1.0, body.b * s), a)
				if u < 0.14:
					col = col.darkened(0.25)
				elif absf(v + 0.45) < 0.14 and u < 0.85:
					col = col.lerp(Color(1, 0.95, 0.75, a), 0.5)
				img.set_pixel(x, y, col)
		return img)

## Odłamek (drzazga, cegła, metal): kanciasty wielokąt o 6 ścianach z jaśniejszą górną krawędzią. Szarości — tint przez modulate.
static func shard(variant: int) -> Texture2D:
	return _tex("shard%d" % (variant % 3), func() -> Image:
		var n := 24
		var img := _img(n, n)
		var rs: Array[float] = []
		for k in 6:
			rs.append(0.62 + 0.3 * absf(sin(float(k) * 2.3 + float(variant) * 1.9)))
		for y in n:
			for x in n:
				var px := (float(x) + 0.5) / float(n) * 2.0 - 1.0
				var py := (float(y) + 0.5) / float(n) * 2.0 - 1.0
				var th := atan2(py, px)
				var seg := (th + PI) / TAU * 6.0
				var k0 := int(floor(seg)) % 6
				var k1 := (k0 + 1) % 6
				var r := lerpf(rs[k0], rs[k1], seg - floor(seg)) * 0.78
				var a := clampf((r - Vector2(px, py).length()) / 0.08, 0.0, 1.0)
				if a <= 0.0:
					continue
				var s := 0.85 - 0.3 * clampf(py * 0.5 + 0.5, 0.0, 1.0) + 0.2 * clampf(-py - 0.3, 0.0, 1.0)
				img.set_pixel(x, y, Color(s, s, s, a))
		return img)

## Kałuża krwi na podłodze (64×20, wariant 0–3): miękki brzeg, ciemniejszy środek, wilgotny połysk i kropelki obok. Jedna tekstura na plamę zamiast ~30 kółek rysowanych
## osobno (każdy nowy rozbryzg przerysowuje wszystkie plamy — przy walce to były tysiące wywołań rysowania na klatkę).
static func blood_pool(variant: int) -> Texture2D:
	return _tex("pool%d" % (variant % 4), func() -> Image:
		var w := 64
		var h := 20
		var img := _img(w, h)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + variant
		var blobs: Array = []
		for k in 5:
			blobs.append([rng.randf_range(-0.55, 0.55), rng.randf_range(-0.2, 0.2), rng.randf_range(0.3, 0.55)])
		var drops: Array = []
		for k in 4:
			drops.append([rng.randf_range(-0.95, 0.95), rng.randf_range(-0.5, 0.4), rng.randf_range(0.04, 0.09)])
		for y in h:
			for x in w:
				var px := (float(x) + 0.5) / float(w) * 2.0 - 1.0
				var py := ((float(y) + 0.5) / float(h) * 2.0 - 1.0) * 2.4
				var cover := 0.0
				var depth := 0.0
				for b in blobs:
					var d := Vector2((px - b[0]) / b[2], (py - b[1] * 2.4) / (b[2] * 2.2)).length()
					cover = maxf(cover, clampf((1.0 - d) / 0.35, 0.0, 1.0))
					depth = maxf(depth, clampf(1.0 - d, 0.0, 1.0))
				for dr in drops:
					var dd := Vector2((px - dr[0]) / dr[2], (py - dr[1] * 2.4) / (dr[2] * 2.0)).length()
					cover = maxf(cover, clampf((1.0 - dd) / 0.4, 0.0, 1.0))
				if cover <= 0.0:
					continue
				var col := Color(0.34, 0.03, 0.05).lerp(Color(0.16, 0.01, 0.02), depth)
				var hl := clampf(1.0 - Vector2(px + 0.18, py + 0.45).length() / 0.22, 0.0, 1.0)
				col = col.lerp(Color(0.8, 0.28, 0.28), hl * 0.35)
				col.a = cover * lerpf(0.55, 0.85, depth)
				img.set_pixel(x, y, col)
		return img)

## Sprite jednego kawałka: tekstura o szerokości `w_wp` pikseli świata (wysokość z proporcji), z tintem `tint`.
static func sprite(tex: Texture2D, w_wp: float, tint := Color.WHITE) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var k := w_wp / float(tex.get_width())
	sp.scale = Vector2(k, k)
	sp.modulate = tint
	return sp
