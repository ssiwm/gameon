extends Node2D
## Punkt ewakuacji z flarą (EXTRACT_PLAN.md): jedna fizyczna flara wbita w ziemię i jej światło zamiast bramki z interfejsu.
## Węzeł tworzy misja (mission.gd, faza EXTRACT / SUCCESS); wszystko jest lokalną kosmetyką wynikającą z replikowanych `phase`, `exit_pos`,
## `extract_progress` i pozycji graczy — reguły ekstrakcji zostają w misji.
##
## Elementy: flara (model HD + płomień z nieregularnym migotaniem, iskry, dym), światło z cieniami, słup światła (light_shaft.gd),
## granica strefy z sześciu kołków z łuczywami, łuk postępu wokół podstawy i kropki nad głowami graczy, których brakuje w strefie,
## wskaźnik na krawędzi ekranu, gdy flara jest poza kadrem, kurz i odłamki w finale oraz pozycyjny syk flary.
## Jakość (Settings.quality_idx): LOW — flara, łuk, wskaźnik, światło bez smugi i dymu; MEDIUM — + słup, dym, iskry; HIGH — + kurz i odłamki
## w finale i animowana smuga. „Reduce effects” wyłącza wstrząsy światła i odłamki; czytelność (łuk, kołki, wskaźnik) zostaje.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const LightShaft := preload("res://scripts/light_shaft.gd")
const Vfx := preload("res://scripts/vfx.gd")

const STAKE_X := [-34.0, -24.0, -13.0, 13.0, 24.0, 34.0]      ## położenia kołków na granicy strefy (px od flary; EXIT_RADIUS_X = 34)
const SHAFT_H := 112.0
const LOOP_ID := "exit_flare"
const POINTER_MARGIN := Vector4(26.0, 52.0, 26.0, 74.0)     ## lewy, górny, prawy, dolny margines wskaźnika (px logiczne) — omija HUD

var _m: Node2D                       ## misja
var _light: PointLight2D
var _shaft: Node2D
var _smoke: CPUParticles2D
var _dust: CPUParticles2D
var _stakes: Array = []              ## Node2D kołków (z dzieckiem-sprite'em), z metadanymi "phase"
var _built_hd := false
var _t := 0.0
var _quality := -1
var _active := false
var _loop_on := false
var _debris_t := 2.0
var _flick := 1.0                    ## wygładzony, nieregularny mnożnik jasności płomienia (0,7–1,2)
var _pointer: Control                ## wskaźnik poza kadrem (w osobnej warstwie ekranowej)
var _pointer_layer: CanvasLayer

func setup(mission: Node2D) -> void:
	_m = mission
	z_index = 5
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), Lights.FLARE_M, Color(0.45, 1.0, 0.55), 1.0, true)
	_light.position = Vector2(0.0, -6.0)
	_light.enabled = false
	add_child(_light)
	_pointer_layer = CanvasLayer.new()
	_pointer_layer.layer = 0
	add_child(_pointer_layer)
	_pointer = Control.new()
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pointer.draw.connect(_draw_pointer)
	_pointer_layer.add_child(_pointer)

# ---------------------------------------------------------------- stan

func _flare_col() -> Color:
	# filtr „Color vision” zmienia całą paletę — przy nim flara przechodzi na cyjan-biel, który zostaje czytelny dla wszystkich trzech wad
	return Color(0.55, 0.92, 1.0) if Settings.colorblind_idx != 0 else Color(0.4, 1.0, 0.5)

func _humans() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.is_queued_for_deletion():
			continue
		out.append(p)
	return out

func _inside(p: Node2D) -> bool:
	return absf(p.global_position.x - _m.exit_pos.x) <= _m.EXIT_RADIUS_X and absf(p.global_position.y - _m.exit_pos.y) <= _m.EXIT_RADIUS_Y

func _process(delta: float) -> void:
	_t += delta
	var on: bool = _m != null and (_m.phase == _m.Phase.EXTRACT or _m.phase == _m.Phase.SUCCESS)
	if on != _active:
		_active = on
		_set_active(on)
	if not on:
		_pointer.queue_redraw()
		return
	position = _m.exit_pos
	if _quality != Settings.quality_idx:
		_apply_quality()
	if Sprites.newitem and not _built_hd:
		_build_hd()
	# nieregularne migotanie: dwa wolne szumy + rzadkie „zachłyśnięcia” (nigdy sinusoida)
	var target := 0.92 + 0.18 * sin(_t * 3.1 + 1.3 * sin(_t * 1.7)) + 0.10 * sin(_t * 9.7) * sin(_t * 2.3)
	if fposmod(_t, 4.7) < 0.12:
		target *= 0.72
	_flick = lerpf(_flick, target, minf(1.0, delta * 14.0))
	if Settings.fx_mult() <= 0.0:
		_flick = 1.0
	var prog: float = _m.extract_progress
	var shake := 0.0
	if _m.finale and Settings.fx_mult() > 0.0:
		shake = clampf(Feel.shake_offset().length() * 0.05, 0.0, 0.4)
	_light.energy = (0.95 + 0.25 * prog) * _flick * (1.0 - shake)
	_light.color = _flare_col().lerp(Color(0.85, 1.0, 0.9), 0.35 * prog)
	for st in _stakes:
		var s := st as Node2D
		var ph: float = s.get_meta("phase")
		var g := 0.72 + 0.35 * prog + 0.10 * sin(_t * 2.2 + ph)
		s.modulate = Color(g, g, g)
	if _shaft != null:
		_shaft.set_level(clampf(0.85 + 0.35 * prog, 0.0, 1.3) * (1.0 - shake * 0.8))
	_tick_finale(delta)
	_tick_audio(prog)
	queue_redraw()
	_pointer.queue_redraw()

func _set_active(on: bool) -> void:
	_light.enabled = on
	if not on:
		_light.energy = 0.0
		_stop_audio()
		if _shaft != null:
			_shaft.visible = false
		if _smoke != null:
			_smoke.emitting = false
		if _dust != null:
			_dust.emitting = false
	else:
		_apply_quality()

func _apply_quality() -> void:
	_quality = Settings.quality_idx
	var q := _quality
	var col := _flare_col()
	_light.shadow_enabled = q >= 1
	if _shaft == null and Sprites.newitem:
		_shaft = LightShaft.new()
		_shaft.name = "Shaft"
		_shaft.fixed_len = SHAFT_H
		_shaft.position = Vector2(0.0, -14.0)               # u źródła (płomień); obrócony o 180° → wąski przy flarze, rozszerza się i gaśnie ku górze
		_shaft.rotation = PI
		add_child(_shaft)
		_shaft.set_tint(Color(col, 1.0), 0.30)
	if _shaft != null:
		_shaft.set_tint(Color(col, 1.0), 0.30)
		_shaft.visible = q >= 1
	if _smoke == null:
		_smoke = CPUParticles2D.new()
		_smoke.position = Vector2(0.0, -16.0)
		_smoke.amount = 14
		_smoke.lifetime = 3.0
		_smoke.local_coords = false
		_smoke.direction = Vector2(0.15, -1.0)
		_smoke.spread = 18.0
		_smoke.initial_velocity_min = 6.0
		_smoke.initial_velocity_max = 14.0
		_smoke.gravity = Vector2(1.5, -2.0)
		_smoke.scale_amount_min = 3.0
		_smoke.scale_amount_max = 6.0
		_smoke.color = Color(0.45, 0.58, 0.46, 0.10)
		_smoke.material = Lights.unshaded()
		Vfx.soften(_smoke)
		add_child(_smoke)
	_smoke.emitting = q >= 1
	if _dust == null:
		_dust = CPUParticles2D.new()
		_dust.position = Vector2(0.0, -96.0)
		_dust.amount = 26
		_dust.lifetime = 1.8
		_dust.local_coords = false
		_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_dust.emission_rect_extents = Vector2(70.0, 6.0)
		_dust.direction = Vector2(0.0, 1.0)
		_dust.spread = 12.0
		_dust.initial_velocity_min = 8.0
		_dust.initial_velocity_max = 22.0
		_dust.gravity = Vector2(0.0, 55.0)
		_dust.scale_amount_min = 0.5
		_dust.scale_amount_max = 1.4
		_dust.color = Color(0.7, 0.72, 0.66, 0.45)
		_dust.material = Lights.unshaded()
		Vfx.soften(_dust)
		add_child(_dust)
	_dust.emitting = q >= 2 and _m != null and _m.finale and Settings.fx_mult() > 0.0

## Kołki z łuczywami na granicy strefy (modele HD z potoku przedmiotów); bez grafiki HD zostaje klasyczny rysunek.
func _build_hd() -> void:
	_built_hd = true
	if not ItemsHd.has("stake"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57AE
	for x in STAKE_X:
		var holder := Node2D.new()
		holder.position = Vector2(float(x) + rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 1.2))
		holder.set_meta("phase", rng.randf_range(0.0, TAU))
		add_child(holder)
		var sc := rng.randf_range(0.85, 1.05)
		ItemsHd.make("stake", holder, sc)
		holder.scale.x = -1.0 if rng.randf() < 0.5 else 1.0
		_stakes.append(holder)

# ---------------------------------------------------------------- finał, dźwięk

func _tick_finale(delta: float) -> void:
	var dusty: bool = _m.finale and Settings.quality_idx >= 2 and Settings.fx_mult() > 0.0
	if _dust != null:
		_dust.emitting = dusty
	if not _m.finale or Settings.quality_idx < 1 or Settings.fx_mult() <= 0.0:
		return
	_debris_t -= delta
	if _debris_t <= 0.0:
		_debris_t = randf_range(1.4, 3.2)
		var p := global_position + Vector2(randf_range(-60.0, 60.0), -120.0)
		Vfx.burst(get_parent(), p, Color(0.28, 0.27, 0.25), 4, 0.0, 14.0, Vector2.DOWN, 20.0, 420.0, 0.9, Vector2(1.2, 2.4))

func _tick_audio(prog: float) -> void:
	# pozycyjny syk flary (istniejąca pętla flare_loop), głośniejszy wraz z postępem ekstrakcji
	var db := -15.0 + 6.0 * prog
	Audio.start_loop_at("flare_loop", self, Audio.BUS_WORLD, db, true, LOOP_ID)
	_loop_on = true

func _stop_audio() -> void:
	if _loop_on:
		Audio.stop_loop(LOOP_ID)
		_loop_on = false

func _exit_tree() -> void:
	_stop_audio()

# ---------------------------------------------------------------- rysowanie

func _draw() -> void:
	if not _active or _m == null:
		return
	var hd := Sprites.newitem and ItemsHd.has("flare_stuck")
	if hd:
		_draw_hd()
	else:
		_draw_classic()
	_draw_progress()

func _draw_hd() -> void:
	var t := _t
	var col := _flare_col()
	var hot := col.lerp(Color(1, 1, 0.92), 0.7)
	var f := _flick
	# plama światła na ziemi (trzy płaskie elipsy) i rzadki pierścień
	for i in 3:
		var rx: float = _m.EXIT_RADIUS_X * (1.1 - 0.22 * float(i))
		_ellipse(Vector2(0, -1), rx, 4.5 - float(i), Color(col, (0.05 + 0.04 * float(i)) * f))
	var ring := fmod(t, 2.2) / 2.2
	_ellipse(Vector2(0, -1), 6.0 + ring * (_m.EXIT_RADIUS_X + 4.0), 1.0 + ring * 2.5, Color(col, 0.22 * (1.0 - ring)), false)
	# światełka łuczyw (jasny punkt + miękka poświata na końcu każdego kołka)
	for st in _stakes:
		var s := st as Node2D
		var ph: float = s.get_meta("phase")
		var a := 0.55 + 0.25 * sin(t * 3.0 + ph) + 0.35 * clampf(_m.extract_progress, 0.0, 1.0)
		var tip: Vector2 = s.position + Vector2(0.0, -8.5)
		draw_circle(tip, 2.3, Color(col, 0.07 * a))
		draw_circle(tip, 0.9, Color(hot, 0.45 * a))
	# flara: wbita tuba i płomień
	ItemsHd.draw(self, "flare_stuck", Vector2.ZERO, 0.85)
	var fh := (9.0 + 2.6 * sin(t * 17.0) + 1.8 * sin(t * 9.1) + 1.2 * sin(t * 4.3)) * f
	var fw := (5.0 + 1.0 * sin(t * 13.0)) * lerpf(0.85, 1.0, clampf(f, 0.7, 1.2) - 0.7)
	var fy := -13.0
	draw_circle(Vector2(0, fy - 5.0), 10.0, Color(col, 0.08 * f))
	draw_circle(Vector2(0, fy - 4.0), 6.0, Color(col, 0.14 * f))
	_flame(Vector2(0, fy), fh + 3.0, fw, t, col)
	# iskry i żar
	for i in 9:
		var life := fmod(t * (0.55 + 0.07 * float(i)) + float(i) * 0.37, 1.0)
		var sx := sin(float(i) * 12.9 + life * 5.0) * (4.0 + 16.0 * life)
		var sy := fy - 4.0 - life * (44.0 + 10.0 * float(i % 3))
		draw_circle(Vector2(sx, sy), (0.7 if i % 2 == 0 else 1.1) * (1.0 - life * 0.5), Color(hot, (1.0 - life) * 0.85))

## Postęp ekstrakcji w świecie: łuk wokół podstawy flary (0 → 360° przez EXTRACT_TIME), kropki nad głowami brakujących graczy.
func _draw_progress() -> void:
	var prog: float = _m.extract_progress
	var col := _flare_col()
	var humans := _humans()
	var inside := 0
	for p in humans:
		if not p.dead and _inside(p):
			inside += 1
	if prog > 0.001 or inside > 0:
		draw_set_transform(Vector2(0.0, -1.0), 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, Color(col, 0.16), 2.4, true)
		if prog > 0.001:
			draw_arc(Vector2.ZERO, 14.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(col.lerp(Color(1, 1, 0.9), 0.55), 0.95), 2.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# kto blokuje wyjście (tylko gdy ktoś już jest w strefie albo licznik biegnie)
	if prog > 0.001 or inside > 0:
		for p in humans:
			if not p.dead and _inside(p):
				continue
			var head: Vector2 = to_local(p.global_position) + Vector2(0.0, -36.0)
			var pc: Color = Color(1.0, 0.35, 0.3) if p.dead else p.call("_body_color")
			var pulse := 0.65 + 0.35 * sin(_t * 6.0)
			draw_circle(head, 2.8, Color(pc, 0.18 * pulse))
			draw_circle(head, 1.5, Color(pc, 0.9 * pulse))

func _flame(base: Vector2, h: float, w: float, t: float, col: Color) -> void:
	var layers := [[1.0, 1.0, Color(col.r * 0.75, col.g * 0.95, col.b * 0.9, 0.8)], [0.6, 0.72, Color(0.7, 1.0, 0.75, 0.95)], [0.28, 0.45, Color(1.0, 1.0, 0.92, 1.0)]]
	for lay in layers:
		var ws: float = lay[0]
		var hs: float = lay[1]
		var pts := PackedVector2Array()
		var n := 12
		for side in [-1.0, 1.0]:
			for i in n + 1:
				if side > 0.0 and i == 0:
					continue
				var fr := float(i) / float(n)
				var y: float = fr if side < 0.0 else 1.0 - fr
				var width := w * ws * pow(maxf(0.0, 1.0 - y), 0.75) * (0.55 + 0.45 * sin(y * PI * 0.9 + 0.25)) * (1.0 + 0.12 * sin(t * 13.0 + y * 7.0))
				var sway := sin(t * 7.0 + y * 2.5) * 1.6 * y * y
				pts.append(base + Vector2(side * width + sway, -y * h * hs))
		draw_colored_polygon(pts, lay[2])

func _ellipse(c: Vector2, rx: float, ry: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, 1.0)

## Klasyczna grafika (bez --newitem): prosty rysunek pikselowy jak dotąd.
func _draw_classic() -> void:
	var t := _t
	var col := Color(0.4, 1.0, 0.5)
	var hot := Color(0.85, 1.0, 0.8)
	var flick := 0.8 + 0.2 * sin(t * 11.0) * sin(t * 4.3)
	var rx0: float = _m.EXIT_RADIUS_X
	for i in 3:
		_ellipse(Vector2(0, -1), rx0 * (1.15 - 0.25 * float(i)), 5.0 - float(i), Color(col, (0.07 + 0.05 * float(i)) * flick))
	var h := 170.0
	draw_polygon(PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(5, -h), Vector2(-5, -h)]),
		PackedColorArray([Color(col, 0.16 * flick), Color(col, 0.16 * flick), Color(col, 0.0), Color(col, 0.0)]))
	draw_polygon(PackedVector2Array([Vector2(-5, 0), Vector2(5, 0), Vector2(2, -h * 0.8), Vector2(-2, -h * 0.8)]),
		PackedColorArray([Color(hot, 0.28 * flick), Color(hot, 0.28 * flick), Color(hot, 0.0), Color(hot, 0.0)]))
	var dash := 6.0
	var x := -rx0
	var phase_off := fmod(t * 14.0, dash * 2.0)
	while x < rx0:
		var x0 := maxf(-rx0, x + phase_off - dash * 2.0)
		var x1 := minf(rx0, x0 + dash)
		if x1 > x0:
			draw_rect(Rect2(x0, -1.0, x1 - x0, 2.0), Color(col, 0.6))
		x += dash * 2.0
	for sx in [-1.0, 1.0]:
		var ex: float = sx * rx0
		draw_rect(Rect2(ex - 1.0, -12.0, 2.0, 12.0), Color(col, 0.7))
		draw_rect(Rect2(ex - (4.0 if sx < 0.0 else 0.0), -12.0, 4.0, 2.0), Color(col, 0.7))
		draw_rect(Rect2(ex - 1.0, -12.0, 2.0, 2.0), Color(hot, 0.9))
	draw_rect(Rect2(-6.0, -2.0, 3.0, 2.0), Color(0.18, 0.2, 0.17))
	draw_rect(Rect2(3.0, -3.0, 4.0, 3.0), Color(0.16, 0.18, 0.15))
	draw_rect(Rect2(-2.0, -11.0, 4.0, 11.0), Color(0.55, 0.12, 0.1))
	draw_rect(Rect2(-2.0, -11.0, 1.0, 11.0), Color(0.8, 0.22, 0.16))
	draw_rect(Rect2(-2.0, -7.0, 4.0, 1.0), Color(0.9, 0.85, 0.6))
	draw_rect(Rect2(-2.0, -12.0, 4.0, 1.0), Color(0.25, 0.25, 0.22))
	var fh := 8.0 + 3.0 * sin(t * 17.0) + 2.0 * sin(t * 9.1)
	var fw := 5.0 + 1.0 * sin(t * 13.0)
	var fy := -12.0
	draw_circle(Vector2(0, fy - 5.0), 11.0, Color(col, 0.10 * flick))
	draw_circle(Vector2(0, fy - 4.0), 6.5, Color(col, 0.16 * flick))
	draw_colored_polygon(PackedVector2Array([Vector2(-fw, fy), Vector2(fw, fy), Vector2(1.0 + sin(t * 7.0), fy - fh - 3.0), Vector2(-1.0, fy - fh - 3.0)]), Color(0.3, 0.95, 0.45, 0.85))
	draw_colored_polygon(PackedVector2Array([Vector2(-fw * 0.55, fy), Vector2(fw * 0.55, fy), Vector2(0, fy - fh)]), Color(0.7, 1.0, 0.7, 0.95))
	draw_colored_polygon(PackedVector2Array([Vector2(-1.5, fy), Vector2(1.5, fy), Vector2(0, fy - fh * 0.55)]), Color(1.0, 1.0, 0.9, 1.0))
	for i in 9:
		var life := fmod(t * (0.55 + 0.07 * float(i)) + float(i) * 0.37, 1.0)
		var sx2 := sin(float(i) * 12.9 + life * 5.0) * (4.0 + 18.0 * life)
		var sy := fy - 4.0 - life * (46.0 + 10.0 * float(i % 3))
		draw_rect(Rect2(roundf(sx2), roundf(sy), 1.0 if i % 2 == 0 else 2.0, 1.0 if i % 2 == 0 else 2.0), Color(hot, (1.0 - life) * 0.9))

# ---------------------------------------------------------------- wskaźnik poza kadrem

## Strzałka na krawędzi ekranu z odległością w metrach, gdy flara jest poza kadrem (marginesy omijają HUD).
func _draw_pointer() -> void:
	if not _active or _m == null or _m.phase != _m.Phase.EXTRACT:
		return
	var me: Node2D = null
	for p in _humans():
		if p.is_multiplayer_authority():
			me = p
			break
	if me == null:
		return
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var sp: Vector2 = vp.get_canvas_transform() * (_m.exit_pos + Vector2(0.0, -12.0))
	var m := POINTER_MARGIN
	var rect := Rect2(Vector2(m.x, m.y), size - Vector2(m.x + m.z, m.y + m.w))
	if rect.has_point(sp):
		return
	var c := size * 0.5
	var d := sp - c
	var k := minf((rect.size.x * 0.5) / maxf(absf(d.x), 0.001), (rect.size.y * 0.5) / maxf(absf(d.y), 0.001))
	var pos := c + d * k
	var dir := d.normalized()
	var col := _flare_col()
	var meters := int(absf(_m.exit_pos.x - me.global_position.x) / 16.0)
	var pulse := 0.65 + 0.35 * sin(_t * clampf(8.0 - float(meters) * 0.05, 2.0, 8.0))
	var a := Color(col, 0.95 * pulse)
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([pos + dir * 9.0, pos - dir * 5.0 + side * 6.0, pos - dir * 5.0 - side * 6.0])
	_pointer.draw_colored_polygon(tri, Color(0.02, 0.04, 0.03, 0.75))
	_pointer.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), a, 1.6, true)
	var font := ThemeDB.fallback_font
	var txt := "%d m" % meters
	var tp := pos - dir * 18.0 - Vector2(float(txt.length()) * 2.6, -3.0)
	_pointer.draw_string(font, tp + Vector2(0.6, 0.6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.8))
	_pointer.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, a)
