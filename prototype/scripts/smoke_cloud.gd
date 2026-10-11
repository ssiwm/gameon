extends Node2D
## Chmura dymu (granat dymny, A2): rośnie 0,9 s, trwa CLOUD_LIFE s, na końcu rzednie. Wrogowie nie widzą przez nią celu
## (enemy.gd `_clear_line` → `blocks`), a wnętrze jest dla gracza ciemnoszarą mgłą. Dźwięk i węch nie są zasłonięte —
## hałas dalej budzi i przyciąga. Powstaje u wszystkich peerów (level.spawn_smoke); czas życia liczy każdy sam.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")

const FULL_RADIUS := 56.0         ## 3,5 m
const EXPAND_TIME := 0.9
const FADE_TIME := 2.0

var life := 12.0
var radius := 0.0

var _age := 0.0
var _seed := 0.0

func _ready() -> void:
	add_to_group("smoke_clouds")
	z_index = 6
	material = Lights.unshaded()
	_seed = float(absi(String(name).hash()) % 628) / 100.0

func _process(delta: float) -> void:
	_age += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var k := clampf(_age / EXPAND_TIME, 0.0, 1.0)
	radius = FULL_RADIUS * (1.0 - (1.0 - k) * (1.0 - k))
	queue_redraw()

## Czy odcinek a–b przechodzi przez jakąś chmurę (wzrok wroga zasłonięty).
static func blocks(tree: SceneTree, a: Vector2, b: Vector2) -> bool:
	for c in tree.get_nodes_in_group("smoke_clouds"):
		if c.radius < 10.0 or c.life < 0.4:
			continue
		if _seg_dist(a, b, c.global_position) < c.radius * 0.85:
			return true
	return false

static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)

static var _puff_tex: Texture2D

## Kłąb dymu 128×128: szum fraktalny pomnożony przez miękki zanik od środka — nieregularny, postrzępiony na brzegach, bez ostrej krawędzi koła.
static func puff_texture() -> Texture2D:
	if _puff_tex == null:
		var n := 128
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.035
		nz.fractal_octaves = 4
		nz.seed = 5
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(float(x) + 0.5 - n * 0.5, float(y) + 0.5 - n * 0.5).length() / (n * 0.5)
				var fall := clampf(1.0 - d, 0.0, 1.0)
				var v := nz.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var a := clampf(pow(fall, 0.7) * smoothstep(0.22, 0.78, v) * 1.25, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex
