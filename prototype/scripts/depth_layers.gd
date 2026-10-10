extends Node2D
## Plan pierwszy kryjówki (ATMOSPHERE_PLAN.md, F4): ciemne, rozmyte sylwetki mebli (skrzynie, stołki, beczki, stół) tuż przed kamerą,
## przesuwające się szybciej niż świat (parallax 1,35), co daje wrażenie głębi sceny. Sylwetki są widoczne tylko przy bocznych
## krawędziach kadru i gasną w środku, więc nie zasłaniają postaci, celu ani HUD-u. Kosmetyka, lokalna; LOW bez plan pierwszego.

const Lights := preload("res://scripts/lights.gd")

const PARALLAX := 1.35
const SCALE := 1.7
const SPACING := 150.0                ## odstęp sylwetek wzdłuż osi parallaxu (px)
const FADE_FROM := 0.27               ## połowa szerokości kadru (ułamek), do której sylwetka jest w pełni widoczna po stronie krawędzi
const FADE_TO := 0.38

var _items: Array[Sprite2D] = []
var _base_y := 0.0
static var _textures: Array = []

func setup(width_px: float, floor_y: float) -> void:
	_base_y = floor_y
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var tex := _make_textures()
	var span := width_px * PARALLAX + 640.0
	var x := -200.0
	while x < span:
		var s := Sprite2D.new()
		s.texture = tex[rng.randi() % tex.size()]
		s.centered = true
		s.material = Lights.unshaded()                         # nie mnożona przez ciemność sceny: czarna bryła z ciepłym odblaskiem na krawędzi
		s.scale = Vector2(SCALE * (1.0 if rng.randf() < 0.5 else -1.0), SCALE)
		s.modulate = Color(1, 1, 1, 0.0)
		s.position = Vector2(x, _base_y + 6.0 - float(s.texture.get_height()) * SCALE * 0.5 + rng.randf_range(0.0, 14.0))
		add_child(s)
		_items.append(s)
		x += SPACING * rng.randf_range(0.75, 1.35)

func _ready() -> void:
	z_index = 70
	process_priority = 10

func _process(_d: float) -> void:
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size
	var inv := vp.get_canvas_transform().affine_inverse()
	var c: Vector2 = inv * (vs * 0.5)                          # środek kadru w świecie
	var vw: float = (inv * Vector2(vs.x, 0.0)).x - (inv * Vector2.ZERO).x     # szerokość kadru w świecie
	position = Vector2(c.x * (1.0 - PARALLAX), 0.0)
	var on := Settings.quality_idx >= 1 and vw > 1.0
	for s in _items:
		if not on:
			s.modulate.a = 0.0
			continue
		var sx := (s.position.x + position.x - c.x) / vw       # −0,5..0,5 po kadrze
		s.modulate.a = 0.85 * smoothstep(FADE_FROM, FADE_TO, absf(sx)) * (1.0 - smoothstep(0.55, 0.75, absf(sx)))

## Cztery sylwetki z miękkimi krawędziami (pole odległości → alfa): skrzynie, stołek, beczka, stół. Kolor prawie czarny.
func _make_textures() -> Array:
	if not _textures.is_empty():
		return _textures
	var specs := [
		[Vector2i(64, 48), "crate"],
		[Vector2i(40, 56), "stool"],
		[Vector2i(36, 52), "barrel"],
	]
	for sp in specs:
		var sz: Vector2i = sp[0]
		var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
		for y in sz.y:
			for x in sz.x:
				var pp := Vector2(float(x) + 0.5, float(y) + 0.5)
				var d := _sdf(String(sp[1]), pp, Vector2(sz))
				var a := (1.0 - smoothstep(-3.0, 7.5, d)) * 0.8   # bardzo szeroka krawędź = plan pierwszy poza ostrością; bryła lekko przezroczysta
				# ciepły odblask lampy na górnych krawędziach (bez niego czarna sylwetka ginie w ciemnym kadrze)
				var above := _sdf(String(sp[1]), pp - Vector2(0.0, 3.0), Vector2(sz))
				var rim := clampf(above * 0.22, 0.0, 1.0) * clampf(-d * 0.35 + 0.35, 0.0, 1.0) * 0.7
				var base := Color(0.012, 0.014, 0.018).lerp(Color(0.34, 0.22, 0.10), rim)
				img.set_pixel(x, y, Color(base.r, base.g, base.b, clampf(a, 0.0, 1.0)))
		_textures.append(ImageTexture.create_from_image(img))
	return _textures

static func _box(p: Vector2, c: Vector2, h: Vector2) -> float:
	var q := (p - c).abs() - h
	return maxf(q.x, q.y)

func _sdf(kind: String, p: Vector2, sz: Vector2) -> float:
	var floor_y := sz.y - 4.0
	match kind:
		"crate":
			var big := _box(p, Vector2(sz.x * 0.45, floor_y - 12.0), Vector2(22.0, 12.0))
			var small := _box(p, Vector2(sz.x * 0.62, floor_y - 31.0), Vector2(13.0, 8.0))
			return minf(big, small)
		"stool":
			var top := _box(p, Vector2(sz.x * 0.5, floor_y - 30.0), Vector2(14.0, 3.0))
			var l1 := _box(p, Vector2(sz.x * 0.5 - 9.0, floor_y - 14.0), Vector2(1.6, 14.0))
			var l2 := _box(p, Vector2(sz.x * 0.5 + 9.0, floor_y - 14.0), Vector2(1.6, 14.0))
			return minf(top, minf(l1, l2))
		"barrel":
			return _box(p, Vector2(sz.x * 0.5, floor_y - 15.0), Vector2(11.0, 15.0)) - 2.0
		_:
			var top2 := _box(p, Vector2(sz.x * 0.5, floor_y - 30.0), Vector2(42.0, 3.0))
			var l3 := _box(p, Vector2(sz.x * 0.5 - 36.0, floor_y - 14.0), Vector2(2.0, 14.0))
			var l4 := _box(p, Vector2(sz.x * 0.5 + 36.0, floor_y - 14.0), Vector2(2.0, 14.0))
			return minf(top2, minf(l3, l4))
