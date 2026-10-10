extends Node2D
## Tło parallax (1.5): niebo z księżycem, dwie linie sosen, dryfująca mgła.
## Tekstury generowane w kodzie (deterministycznie). Warstwy są „unshaded" —
## jasność ustawiamy wprost, żeby nie rozjaśnić ciemności strojonej w §8.3
## (niebo ~0,01, sylwetki ledwo odcięte od horyzontu).
##
## Pod artystę (wariant C): podmień tekstury na pliki w res://art/backdrop/
## o tych samych nazwach (sky.png, ridge_far.png, ridge_near.png, fog.png) — dotyczy grafiki klasycznej; HD ma las wektorowy.

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

var _layers: Dictionary = {}           ## nazwa → węzeł warstwy (Sprite2D z teksturą albo MeshInstance2D z wektorowym lasem; HD)

## Pogoda (weather_fx.gd): tło jest „unshaded", ale mnoży je CanvasModulate ciemności (~0,02), więc przy CLEAR NIGHT księżyc i grzbiety
## wzmacniamy modulate (>1) — noc „pogodna" ma widoczny księżyc i niebo; deszcz i burza przyciemniają niebo, mgła rozjaśnia grzbiety i własną warstwę mgły.
func set_weather(id: String, k: float) -> void:
	var sky := 1.0
	var ridge := 1.0
	var mist := 1.0
	match id:
		"clear":
			sky = 1.0 + 6.0 * k
			ridge = 1.0 + 3.0 * k
		"rain":
			sky = 1.0 - 0.5 * k
		"storm":
			sky = 1.0 - 0.6 * k
		"fog":
			ridge = 1.0 + 2.0 * k
			mist = 1.0 + 3.0 * k
	_mod("sky", Color(sky, sky, sky * 1.05))
	for n in ["ridge_far", "ridge_mid", "ridge_near"]:
		_mod(n, Color(ridge, ridge, ridge))
	_mod("fog", Color(mist, mist, mist))

func _mod(n: String, c: Color) -> void:
	if _layers.has(n):
		(_layers[n] as CanvasItem).modulate = c
var _parallax: Dictionary = {}         ## nazwa → Parallax2D

## Tło HD (--newworld): niebo z art/backdrop/hd/sky.png (2048×960, sprite w skali 0,5 → 1024×480 px świata) i wektorowy las (_build_forest).
## Dochodzi warstwa średnia (ridge_mid). Wołane z Level.enable_world_hd.
func enable_hd() -> void:
	var dir := "res://art/backdrop/hd/"
	if not ResourceLoader.exists(dir + "sky.png"):
		return
	if _layers.has("ridge_mid") and _layers["ridge_mid"] is MeshInstance2D:
		return                                           # las wektorowy już zbudowany
	var s: Sprite2D = _layers["sky"]
	s.texture = load(dir + "sky.png")
	s.scale = Vector2(0.5, 0.5)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_forest()

## Las wektorowy (zamiast rastrów 2048×960, które przy zoomie i 4K rozciągały się ok. 5× na teksel): trzy warstwy świerków jako geometria
## z kolorami w wierzchołkach — ostre brzegi przy każdej rozdzielczości, mgła jako gradient u podstawy warstwy (zamiast szumu),
## jedna krawędź księżyca (jaśniejszy wierzchołek korony). Warstwy są powtarzane co W px, hill i drzewa zawijają się w poziomie.
## [nazwa, przesuw parallax, podstawa (ułamek H), rozstaw drzew (px), wysokość min, max, kolor, kolor krawędzi, kolor mgły, siła mgły, ziarno]
const FOREST := [
	["ridge_far", 0.18, 0.66, 7.4, 19.0, 36.0, Color(0.050, 0.058, 0.080), Color(0.062, 0.073, 0.103), Color(0.085, 0.096, 0.126), 0.42, 0x51],
	["ridge_mid", 0.28, 0.71, 11.5, 29.0, 52.0, Color(0.034, 0.040, 0.057), Color(0.043, 0.051, 0.075), Color(0.068, 0.078, 0.104), 0.34, 0x66],
	["ridge_near", 0.38, 0.76, 18.0, 40.0, 75.0, Color(0.020, 0.024, 0.034), Color(0.026, 0.032, 0.046), Color(0.050, 0.058, 0.080), 0.28, 0x77],
]
const FOREST_BOTTOM := 1500.0          ## wypełnienie podnóża sięga daleko w dół (mapy są wyższe niż 480 px tła)

func _build_forest() -> void:
	for n in ["ridge_far", "ridge_mid", "ridge_near", "fog"]:
		if _parallax.has(n):
			(_parallax[n] as Node).queue_free()
			_parallax.erase(n)
			_layers.erase(n)
	var order := []
	for d in FOREST:
		var p := Parallax2D.new()
		p.name = d[0]
		p.scroll_scale = Vector2(float(d[1]), 1.0)
		p.repeat_size = Vector2(W, 0)
		p.repeat_times = 3
		var mi := MeshInstance2D.new()
		mi.mesh = _forest_mesh(d)
		mi.material = Lights.unshaded()
		p.add_child(mi)
		add_child(p)
		_layers[d[0]] = mi
		_parallax[d[0]] = p
		order.append(p)

func _hill(x: float, base: float, seed: int) -> float:
	var ph := TAU * x / float(W)
	return base - 3.0 * sin(2.0 * ph + float(seed)) - 2.0 * sin(5.0 * ph + 1.3 * float(seed))

func _forest_mesh(d: Array) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d[10])
	var base := float(H) * float(d[2])
	var col: Color = d[6]
	var rim: Color = d[7]
	var haze_col: Color = d[8]
	var haze := float(d[9])
	var v := PackedVector2Array()
	var c := PackedColorArray()
	# podnóże: pas mgły przy linii drzew płynnie przechodzący w ciemną bryłę poniżej
	var top_col := col.lerp(haze_col, haze)
	var ground_col := col * 0.7
	ground_col.a = 1.0
	var x := 0.0
	while x < float(W):
		var x2 := minf(x + 8.0, float(W))
		var y1 := _hill(x, base, int(d[10]))
		var y2 := _hill(x2, base, int(d[10]))
		var m1 := y1 + 26.0
		var m2 := y2 + 26.0
		_quad(v, c, Vector2(x, y1), top_col, Vector2(x2, y2), top_col, Vector2(x2, m2), ground_col, Vector2(x, m1), ground_col)
		_quad(v, c, Vector2(x, m1), ground_col, Vector2(x2, m2), ground_col, Vector2(x2, FOREST_BOTTOM), ground_col, Vector2(x, FOREST_BOTTOM), ground_col)
		x = x2
	# drzewa: pień + piętra postrzępionych gałęzi (jak w tools/world_hd_backdrop.py); kopie ±W dla zawijania
	var tx := rng.randf_range(0.0, float(d[3]))
	while tx < float(W):
		var h := rng.randf_range(float(d[4]), float(d[5]))
		var lean := rng.randf_range(-0.02, 0.02)
		var tiers := rng.randi_range(8, 12)
		var seeds: Array = []
		for k in tiers:
			seeds.append([rng.randf_range(-1.0, 1.0), rng.randi_range(5, 7)])
		for ox in [-float(W), 0.0, float(W)]:
			var px: float = tx + ox
			if px < -h or px > float(W) + h:
				continue
			_pine(v, c, px, _hill(tx, base, int(d[10])) + 1.5, h, lean, tiers, seeds, col, rim, haze_col, haze)
		tx += float(d[3]) * rng.randf_range(0.6, 1.5)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _quad(v: PackedVector2Array, c: PackedColorArray, a: Vector2, ca: Color, b: Vector2, cb: Color, d: Vector2, cd: Color, e: Vector2, ce: Color) -> void:
	v.append_array([a, b, d, a, d, e])
	c.append_array([ca, cb, cd, ca, cd, ce])

func _pine(v: PackedVector2Array, c: PackedColorArray, x: float, base_y: float, h: float, lean: float, tiers: int, seeds: Array,
		col: Color, rim: Color, haze_col: Color, haze: float) -> void:
	var tw := maxf(0.8, h * 0.035)
	var trunk_col := col.lerp(haze_col, haze * 0.95)       # pień w kolorze pasa mgły u podnóża — nie odcina się jako ciemny pieniek
	trunk_col.a = 1.0
	_quad(v, c, Vector2(x - tw, base_y - h * 0.22), trunk_col, Vector2(x + tw, base_y - h * 0.22), trunk_col,
		Vector2(x + tw, base_y + 2.0), trunk_col, Vector2(x - tw, base_y + 2.0), trunk_col)
	for k in tiers:
		var t := float(k) / float(maxi(tiers - 1, 1))
		var y := base_y - h * (0.16 + 0.80 * t)
		var wd := h * (0.34 * pow(1.0 - t, 0.85) + 0.035)
		var th := h * (0.20 + 0.04 * (1.0 - t))
		var apex := Vector2(x + lean * t * h, y - th * 0.9)
		var n: int = seeds[k][1]
		var jit: float = seeds[k][0]
		var pts: Array = []
		for i in n + 1:
			var f := float(i) / float(n)
			var px := x + lean * t * h * (1.0 - 0.3 * f) - wd + 2.0 * wd * f
			var py := y + th * 0.10 * jit * (1.0 if i % 2 == 0 else -0.6) + (th * 0.28 if i % 2 == 1 else 0.0)
			pts.append(Vector2(px, py))
		# kolor: czubek korony jaśniejszy (księżyc), im niżej tym bardziej mglisto
		var hz := clampf((y - (base_y - h)) / h, 0.0, 1.0) * haze
		var body := col.lerp(haze_col, hz)
		var tip := rim.lerp(haze_col, hz)
		body.a = 1.0
		tip.a = 1.0
		for i in n:
			v.append_array([apex, pts[i], pts[i + 1]])
			c.append_array([tip, body, body])

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
	_layers[n] = s
	_parallax[n] = p

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
