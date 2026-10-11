extends Node2D
## Punkt ewakuacji z flarą (EXTRACT_PLAN.md): jedna fizyczna flara wbita w ziemię i jej światło zamiast bramki z interfejsu.
## Węzeł tworzy misja (mission.gd, faza EXTRACT / SUCCESS); wszystko jest lokalną kosmetyką wynikającą z replikowanych `phase`, `exit_pos`,
## `extract_progress` i pozycji graczy — reguły ekstrakcji zostają w misji.
##
## Elementy: flara (model HD + płomień z nieregularnym migotaniem, iskry, dym), światło z cieniami, słup światła (light_shaft.gd),
## granica strefy z sześciu kołków z łuczywami, łuk postępu wokół podstawy i kropki nad głowami graczy, których brakuje w strefie,
## kurz i odłamki w finale oraz pozycyjny syk flary. (Wskaźnik na krawędzi ekranu był w planie, ale okazał się zbędny — kierunek podaje HUD.)
## Jakość (Settings.quality_idx): LOW — flara, łuk, światło bez smugi i dymu; MEDIUM — + słup, dym, iskry; HIGH — + kurz i odłamki
## w finale i animowana smuga. „Reduce effects” wyłącza wstrząsy światła i odłamki; czytelność (łuk, kołki) zostaje.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Vfx := preload("res://scripts/vfx.gd")

const STAKE_X := [-34.0, -24.0, -13.0, 13.0, 24.0, 34.0]      ## położenia kołków na granicy strefy (px od flary; EXIT_RADIUS_X = 34)
const SHAFT_H := 112.0
const LOOP_ID := "exit_flare"

var _m: Node2D                       ## misja
var _light: Lights.GameLight
var _stakes: Array = []              ## Node2D kołków (z dzieckiem-sprite'em), z metadanymi "phase"
var _built_hd := false
var _t := 0.0
var _quality := -1
var _active := false
var _loop_on := false
var _debris_t := 2.0
var _flick := 1.0                    ## wygładzony, nieregularny mnożnik jasności płomienia (0,7–1,2)

func setup(mission: Node2D) -> void:
	_m = mission
	visible = false
	z_index = 5
	add_to_group("exit_flares")
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), Lights.FLARE_M, Color(0.45, 1.0, 0.55), 1.0, true)
	_light.position = Vector2(0.0, -6.0)
	_light.enabled = false
	add_child(_light)

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
	_tick_finale(delta)
	_tick_audio(prog)
	queue_redraw()

func _set_active(on: bool) -> void:
	# po wyjściu z fazy ekstrakcji (restart misji, nowa mapa) węzeł przestaje się odświeżać — bez ukrycia i przerysowania zostawał
	# ostatni rysunek flary w starym miejscu; kołki, słup i dym są jego dziećmi, więc `visible` chowa też je
	visible = on
	queue_redraw()
	_light.enabled = on
	if not on:
		_light.energy = 0.0
		_stop_audio()
	else:
		_apply_quality()

func _apply_quality() -> void:
	_quality = Settings.quality_idx
	var q := _quality
	_light.shadow_enabled = q >= 1

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

## Znaczniki interfejsu: kropki nad głowami graczy, których brakuje w strefie. Flara, płomień, słup światła, dym i pierścień postępu
## są w scenie 3D (view3d.gd: _sync_fires).
func _draw() -> void:
	if not _active or _m == null:
		return
	var prog: float = _m.extract_progress
	var humans := _humans()
	var inside := 0
	for p in humans:
		if not p.dead and _inside(p):
			inside += 1
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
