extends Control
## Tło ekranów startowych (menu główne, lobby; MAIN_MENU_PLAN.md P0): key art z klatki gry (`art/menu/backdrop.jpg`, generator
## `tools/menu_backdrop.py`) z powolnym najazdem kamery, dwiema warstwami mgły dryfującej w poziomie, iskrami nad ogniskiem
## i migotaniem jego poświaty. Obraz kryje cały ekran (cover); wszystko poniżej `_pan` leży we współrzędnych obrazu 2560×1440,
## więc najazd przesuwa mgłę, iskry i poświatę razem z kadrem. „Reduce effects" zatrzymuje ruch i migotanie (stały obraz).
## Koszt: jedna tekstura tła, dwie kafelkowane mgły, jedna poświata i ≤ EMBERS kółek — bez shaderów i bez alokacji w klatce.
## Ruchome warstwy (`_pan`, pasy mgły) to Node2D, nie Control: kontrolki mają pozycję zaokrąglaną do piksela bazowego widoku
## (`gui/common/snap_controls_to_pixels`, baza 640×360 → 3 px ekranu w 1080p, 6 px w 4K), więc najazd i mgła szły skokami.

const UiTheme := preload("res://scripts/ui_theme.gd")
const BACKDROP := preload("res://art/menu/backdrop.jpg")
const FOG := preload("res://art/menu/fog.png")
const IMG := Vector2(2560, 1440)
const FOCUS_UV := Vector2(0.65, 0.62)  ## punkt, na który najeżdża kamera: żołnierz (zostaje w miejscu na ekranie)
const FIRE_UV := Vector2(0.86, 0.76)   ## środek poświaty ogniska w kadrze — zależy od źródła w menu_backdrop.py
const FLAME_UV := Vector2(0.95, 0.70)  ## płomień: stąd wylatują iskry
const DOLLY := 0.035                   ## najazd 1,0 → 1,035
const DOLLY_S := 50.0                  ## s na przejście w jedną stronę (tam i z powrotem, ease in-out)
const EMBERS := 24
const FOG_LOW_K := Vector2(1.6, 1.4)   ## skala kafelka mgły przy ziemi
const FOG_HIGH_K := Vector2(2.4, 2.0)  ## … i między drzewami

var _t := 0.0
var _cover := 1.0
var _base := Vector2.ZERO              ## lewy górny róg obrazu przy skali `_cover` (obraz wyśrodkowany)
var _pan: Node2D
var _fog_low: Node2D
var _fog_high: Node2D
var _glow: TextureRect
var _sparks: Sparks

## Iskry z ogniska: stała pula, pozycje i czas życia w tablicach (bez alokacji w klatce), rysowane addytywnie.
class Sparks extends Control:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		rng.seed = 87
		pos.resize(EMBERS)
		vel.resize(EMBERS)
		age.resize(EMBERS)
		life.resize(EMBERS)
		for i in EMBERS:
			_spawn(i)
			age[i] = rng.randf() * life[i]           # rozłożone w czasie od pierwszej klatki

	func _spawn(i: int) -> void:
		pos[i] = FLAME_UV * IMG + Vector2(rng.randf_range(-70.0, 50.0), rng.randf_range(-20.0, 30.0))
		vel[i] = Vector2(rng.randf_range(-22.0, 10.0), rng.randf_range(-95.0, -45.0))
		age[i] = 0.0
		life[i] = rng.randf_range(1.6, 3.4)

	func step(delta: float, t: float) -> void:
		for i in EMBERS:
			age[i] += delta
			if age[i] >= life[i]:
				_spawn(i)
			var v := vel[i]
			v.x += sin(t * 1.7 + float(i)) * 14.0 * delta    # unoszenie i kołysanie w cieple
			vel[i] = v
			pos[i] += v * delta
		queue_redraw()

	func _draw() -> void:
		for i in EMBERS:
			var k := age[i] / life[i]
			var a := minf(k * 6.0, 1.0) * (1.0 - k)
			var r := lerpf(3.2, 1.4, k)
			draw_circle(pos[i], r * 2.6, Color(1.0, 0.45, 0.12, 0.10 * a))
			draw_circle(pos[i], r, Color(1.0, 0.72, 0.35, 0.85 * a))

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_pan = Node2D.new()
	add_child(_pan)
	var art := TextureRect.new()
	art.texture = BACKDROP
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # przy 720p obraz jest pomniejszony o połowę — bez mipmap migocze trawa
	art.size = IMG
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan.add_child(art)
	_fog_high = _fog_layer(0.44, FOG_HIGH_K, Color(0.62, 0.70, 0.82, 0.07))
	_glow = TextureRect.new()
	var g := GradientTexture2D.new()
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(UiTheme.ACCENT, 1.0), Color(UiTheme.ACCENT, 0.0)])
	g.gradient = gg
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 128
	g.height = 128
	_glow.texture = g
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.size = Vector2(900, 560)
	_glow.position = FIRE_UV * IMG - _glow.size * 0.5
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_pan.add_child(_glow)
	_sparks = Sparks.new()
	_sparks.size = IMG
	_pan.add_child(_sparks)
	_fog_low = _fog_layer(0.80, FOG_LOW_K, Color(0.62, 0.70, 0.80, 0.10))
	_apply()

## Pas mgły na wysokości `v` (0..1 kadru): kafelek fog.png powtarzany w poziomie, o kafelek szerszy niż kadr. Kafelki leżą
## nieruchomo w Node2D, który przesuwa _apply (pozycja Node2D nie jest zaokrąglana do piksela jak pozycja kontrolki).
func _fog_layer(v: float, k: Vector2, tint: Color) -> Node2D:
	var holder := Node2D.new()
	holder.position.y = v * IMG.y - FOG.get_height() * k.y * 0.5
	holder.scale = k
	holder.modulate = tint
	var f := TextureRect.new()
	f.texture = FOG
	f.stretch_mode = TextureRect.STRETCH_TILE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.size = Vector2(IMG.x / k.x + FOG.get_width() * 2.0, FOG.get_height())
	holder.add_child(f)
	_pan.add_child(holder)
	return holder

## Rozmiar tła dla okna o wymiarach `screen` (px): obraz kryje ekran, nadmiar przycinany po równo z obu stron.
func fit(screen: Vector2) -> void:
	position = Vector2.ZERO
	size = screen
	_cover = maxf(screen.x / IMG.x, screen.y / IMG.y)
	_base = (screen - IMG * _cover) * 0.5
	_apply()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if Settings.fx_mult() <= 0.0:
		if _sparks.visible:
			_t = 0.0
			_sparks.visible = false
			_apply()
		return
	_sparks.visible = true
	_t += delta
	_sparks.step(delta, _t)
	_apply()

## Najazd (skala wokół FOCUS_UV, kadr dalej kryje ekran), dryf mgły i migotanie poświaty dla bieżącego `_t`.
func _apply() -> void:
	var still := Settings.fx_mult() <= 0.0
	var p := fposmod(_t, DOLLY_S * 2.0) / DOLLY_S
	var d := 0.0 if still else 0.5 - 0.5 * cos(PI * (p if p <= 1.0 else 2.0 - p))
	var s := _cover * (1.0 + DOLLY * d)
	var focus := FOCUS_UV * IMG
	_pan.scale = Vector2(s, s)
	_pan.position = _base + focus * (_cover - s)          # punkt FOCUS_UV stoi w miejscu, obraz rośnie wokół niego
	var fw := float(FOG.get_width())
	_fog_low.position.x = -fposmod(_t * 9.0, fw) * _fog_low.scale.x
	_fog_high.position.x = -fposmod(-_t * 5.0, fw) * _fog_high.scale.x
	var flick := 0.0 if still else 0.25 * sin(_t * 7.3) + 0.15 * sin(_t * 13.1 + 1.7) + 0.10 * sin(_t * 23.9 + 0.4)
	_glow.modulate.a = 0.16 * (1.0 + flick)
