extends Node2D
## Chmura dymu (granat dymny, A2): rośnie 0,9 s, trwa CLOUD_LIFE s, na końcu rzednie. Wrogowie nie widzą przez nią celu
## (enemy.gd `_clear_line` → `blocks`), a wnętrze jest dla gracza ciemnoszarą mgłą. Dźwięk i węch nie są zasłonięte —
## hałas dalej budzi i przyciąga. Powstaje u wszystkich peerów (level.spawn_smoke); czas życia liczy każdy sam.

const Lights := preload("res://scripts/lights.gd")

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

func _draw() -> void:
	var fade := clampf(life / FADE_TIME, 0.0, 1.0)
	var r := maxf(radius, 1.0)
	for i in 16:
		var ang := _seed + float(i) * 2.399963
		var rr := r * 0.62 * sqrt(float(i + 1) / 16.0)
		var wob := sin(_age * 0.9 + float(i) * 1.7) * 3.0
		var pos := Vector2(cos(ang), sin(ang) * 0.85) * (rr + wob)
		var shade := 0.22 + 0.06 * sin(float(i) * 2.1)
		draw_circle(pos, r * 0.42, Color(shade, shade + 0.015, shade + 0.03, 0.42 * fade))
