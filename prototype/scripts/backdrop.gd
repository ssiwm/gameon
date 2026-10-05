extends Node2D
## Tło parallax (1.5): niebo z księżycem, dwie linie sosen, dryfująca mgła.
## Tekstury generowane w kodzie (deterministycznie). Warstwy są „unshaded" —
## jasność ustawiamy wprost, żeby nie rozjaśnić ciemności strojonej w §8.3
## (niebo ~0,01, sylwetki ledwo odcięte od horyzontu).
##
## Pod artystę (wariant C): podmień tekstury na pliki w res://art/backdrop/
## o tych samych nazwach (sky.png, ridge_far.png, ridge_near.png, fog.png).

const Lights := preload("res://scripts/lights.gd")

const W := 1024
const H := 480
const ART_DIR := "res://art/backdrop/"

func _ready() -> void:
	z_index = -100
	# Parallax tylko w poziomie: w pionie warstwy trzymają się świata (mapa ma
	# 480 px wysokości, kamera chodzi nisko) — przy pionowym przesuwie linie
	# drzew uciekały do góry kadru jako cienkie pasy.
	_layer("sky", Vector2(0.04, 1.0), _sky(), Vector2.ZERO)
	_layer("ridge_far", Vector2(0.18, 1.0), _ridge(0x51, 0.66, 10, 34, Color(0.050, 0.058, 0.080)), Vector2.ZERO)
	_layer("ridge_near", Vector2(0.38, 1.0), _ridge(0x77, 0.76, 7, 60, Color(0.020, 0.024, 0.034)), Vector2.ZERO)
	_layer("fog", Vector2(0.55, 1.0), _fog(), Vector2(-6.0, 0.0))

func _layer(n: String, scroll: Vector2, img: Image, auto: Vector2) -> void:
	var p := Parallax2D.new()
	p.name = n
	p.scroll_scale = scroll
	p.repeat_size = Vector2(W, 0)
	p.repeat_times = 3
	p.autoscroll = auto
	var s := Sprite2D.new()
	s.centered = false
	s.texture = _art_or(n, img)
	s.material = Lights.unshaded()
	p.add_child(s)
	add_child(p)

## Plik artysty, jeśli jest — inaczej tekstura wygenerowana.
func _art_or(n: String, img: Image) -> Texture2D:
	var path := ART_DIR + n + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return ImageTexture.create_from_image(img)

func _sky() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var top := Color(0.006, 0.008, 0.016)
	var hor := Color(0.075, 0.08, 0.11)
	for y in H:
		var t := clampf(float(y) / (H * 0.85), 0.0, 1.0)
		var c := top.lerp(hor, t * t)
		for x in W:
			img.set_pixel(x, y, c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A7
	for i in 90:
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, int(H * 0.55)))
		var b := rng.randf_range(0.10, 0.32)
		img.set_pixelv(p, Color(b, b, b * 1.1))
	# księżyc w nowiu-pełni: blada tarcza z poświatą
	var mc := Vector2(720, 70)
	for y in range(0, 170):
		for x in range(600, 840):
			var d := Vector2(x, y).distance_to(mc)
			var base := img.get_pixel(x, y)
			if d < 15.0:
				var shade := 0.55 + 0.08 * sin(x * 0.7) * sin(y * 0.9)
				img.set_pixel(x, y, Color(shade * 0.95, shade, shade * 1.02))
			elif d < 70.0:
				var g := pow(1.0 - (d - 15.0) / 55.0, 2.2) * 0.07
				img.set_pixel(x, y, base + Color(g, g, g * 1.1, 0))
	return img

## Linia sosen: sylwetki z trójkątów na wypełnionym podnóżu.
func _ridge(seed: int, base_frac: float, spacing: int, max_h: int, col: Color) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var base := int(H * base_frac)
	var heights := PackedFloat32Array()
	heights.resize(W)
	for x in W:
		heights[x] = base - 6.0 * sin(x * 0.006 + seed) - 4.0 * sin(x * 0.017)
	var x := 0
	while x < W:
		var h := rng.randi_range(int(max_h * 0.45), max_h)
		var half := maxi(3, int(h * 0.28))
		for dx in range(-half, half + 1):
			var xx := posmod(x + dx, W)
			var top := heights[xx] - h * (1.0 - absf(dx) / float(half + 1))
			heights[xx] = minf(heights[xx], top)
		x += spacing + rng.randi_range(0, spacing)
	for xx in W:
		for y in range(int(heights[xx]), H):
			img.set_pixel(xx, y, col)
	return img

## Pas mgły: miękki szum, bardzo przezroczysty.
func _fog() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var noise := FastNoiseLite.new()
	noise.seed = 0xF06
	noise.frequency = 0.006
	var y0 := int(H * 0.62)
	var y1 := int(H * 0.92)
	for y in range(y0, y1):
		var band := sin(PI * float(y - y0) / float(y1 - y0))
		for x in W:
			# szum zawija się w poziomie (powtarzana warstwa bez szwu)
			var a := TAU * x / W
			var n := noise.get_noise_3d(cos(a) * 160.0, sin(a) * 160.0, y * 1.0) * 0.5 + 0.5
			var alpha := band * n * n * 0.10
			img.set_pixel(x, y, Color(0.55, 0.62, 0.7, alpha))
	return img
