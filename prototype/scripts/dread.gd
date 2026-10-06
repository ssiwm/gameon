extends Node2D
## Groza (dread): lokalne, kosmetyczne straszaki — każdy peer ma własne, nic nie jest
## synchronizowane i nic nie wpływa na symulację (wrogowie, hałas, Stalker).
##
## Cztery narzędzia, wszystkie rzadkie i zależne od Uwagi oraz głębokości:
##   • fałszywe odgłosy — kroki zza pleców, skrzypienie blisko, trzask drzwi, szkło,
##     pomruk daleko; czasem nic z tego nie okazuje się niczym (to jest groza)
##   • migotanie świateł (Lights.flicker_until_ms) z uderzeniem tuż przed
##   • oczy w mroku — para blada na skraju ciemności, znika, gdy podejdziesz
##     albo poświecisz; w odróżnieniu od Stalkera nigdy nie atakuje
##   • w podziemiach świat jest ciemniejszy (CanvasModulate) i straszaki częstsze
##
## Tempo skaluje Difficulty „dread" i Uwaga gracza. W trybie headless (testy) wyłączone.

const Lights := preload("res://scripts/lights.gd")

const DEEP_DARK := 0.6          ## mnożnik ambientu na dnie podziemi
const DEEP_FADE_PX := 120.0     ## na ilu pikselach opadania ściemnia się świat
const EYES_MIN := 130.0
const EYES_MAX := 210.0
const EYES_VANISH_NEAR := 96.0  ## podejście bliżej = znikają
const EYES_VANISH_LIGHT := 150.0

var _t_event := randf_range(20.0, 35.0)
var _t_flicker := randf_range(60.0, 100.0)
var _t_eyes := randf_range(40.0, 70.0)
var _eyes := Node2D.new()
var _eyes_life := 0.0
var _eyes_age := 0.0
var _dark: CanvasModulate
var _busy := false              ## trwa sekwencja (kroki) — nie nakładamy kolejnej

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_dark = get_parent().get_node_or_null("Darkness") as CanvasModulate
	_eyes.name = "Eyes"
	_eyes.material = Lights.unshaded()
	_eyes.visible = false
	_eyes.z_index = 3
	_eyes.draw.connect(_draw_eyes)
	add_child(_eyes)

func _local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead:
			return p
	return null

func _process(delta: float) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var pl := _local_player()
	if lvl == null or pl == null:
		_eyes_life = 0.0
		_eyes.visible = false
		return
	var deep: bool = lvl.is_underground(pl.global_position)
	_update_darkness(delta, pl, lvl)
	if NoiseMgr.safe_zone:
		_eyes_life = 0.0                # kryjówka: bez fałszywych odgłosów, migotania i oczu w mroku
		_eyes.visible = false
		return
	_update_eyes(delta, pl)
	# tempo: Uwaga przyspiesza, podziemia i trudność też
	var pace: float = Difficulty.m("dread") * (1.0 + 1.2 * NoiseMgr.level / NoiseMgr.MAX_LEVEL) * (1.6 if deep else 1.0) * (1.0 + 0.8 * Director.tension)
	_t_event -= delta * pace
	_t_flicker -= delta * pace
	_t_eyes -= delta * pace
	if _t_event <= 0.0 and not _busy:
		_t_event = randf_range(25.0, 45.0)
		_fake_sound(pl, deep)
	if _t_flicker <= 0.0:
		_t_flicker = randf_range(70.0, 120.0)
		_flicker(pl)
	if _t_eyes <= 0.0 and _eyes_life <= 0.0 and not NoiseMgr.stalker_awake:
		_t_eyes = randf_range(45.0, 80.0)
		_spawn_eyes(pl)

# ---------------------------------------------------------------- ciemność

## Głębiej = ciemniej: bez latarki w podziemiach widać tylko aurę gracza.
func _update_darkness(delta: float, pl: Node2D, lvl: Node) -> void:
	if _dark == null:
		return
	var depth := clampf((pl.global_position.y - (lvl.underground_y - DEEP_FADE_PX)) / DEEP_FADE_PX, 0.0, 1.0)
	var a: Color = lvl.ambient
	var target := Color(a.r, a.g, a.b).lerp(Color(a.r * DEEP_DARK, a.g * DEEP_DARK, a.b * DEEP_DARK), depth)
	_dark.color = _dark.color.lerp(target, clampf(delta * 1.5, 0.0, 1.0))

# ---------------------------------------------------------------- odgłosy

func _fake_sound(pl: Node2D, deep: bool) -> void:
	var roll := randf()
	var here := pl.global_position
	var behind := Vector2(-signf(pl.aim_dir.x) if absf(pl.aim_dir.x) > 0.1 else 1.0, 0.0)
	var stalker_asleep := not NoiseMgr.stalker_awake
	if stalker_asleep and roll < 0.30:
		_steps_behind(pl, behind)
	elif roll < 0.50:
		Audio.play_variant_at("amb_creak", 3, here + Vector2.from_angle(randf() * TAU) * randf_range(90.0, 150.0),
			Audio.BUS_AMB, -1.0, 0.65 if deep else 1.0)
	elif roll < 0.65:
		Audio.play_variant_at("door", 2, here + Vector2(randf_range(-300.0, 300.0), 0.0), Audio.BUS_WORLD, -6.0, 0.8)
	elif roll < 0.78:
		Audio.play_variant_at("glass_break", 2, here + Vector2(randf_range(-420.0, 420.0), 0.0), Audio.BUS_WORLD, -8.0, 0.9)
	elif stalker_asleep and roll < 0.92:
		Audio.play_variant_at("stalker_growl", 2, here + Vector2(randf_range(-800.0, 800.0), 0.0), Audio.BUS_STALKER, -10.0, 0.5)
	else:
		Audio.play_variant_at("amb_thud", 2, here + Vector2.from_angle(randf() * TAU) * randf_range(220.0, 340.0),
			Audio.BUS_AMB, -3.0, 0.8)

## Cztery kroki zbliżają się zza pleców i urywają. Nic tam nie ma.
func _steps_behind(pl: Node2D, behind: Vector2) -> void:
	_busy = true
	for i in 4:
		if not is_instance_valid(pl) or pl.dead:
			break
		var dist := lerpf(200.0, 110.0, i / 3.0)
		Audio.play_variant_at("stalker_step", 3, pl.global_position + behind * dist, Audio.BUS_WORLD, -9.0, 0.75)
		await get_tree().create_timer(randf_range(0.5, 0.65)).timeout
	_busy = false

# ---------------------------------------------------------------- światło

## Uderzenie, chwila ciszy, światła mrugają jak przy słabym kontakcie.
func _flicker(pl: Node2D) -> void:
	Audio.play_variant_at("amb_thud", 2, pl.global_position + Vector2(randf_range(-90.0, 90.0), -30.0),
		Audio.BUS_AMB, -2.0, 1.1)
	Lights.flicker_until_ms = Time.get_ticks_msec() + randi_range(600, 1500)

# ---------------------------------------------------------------- oczy

## Szuka miejsca na tym samym poziomie, w linii wzroku, na skraju ciemności.
func _spawn_eyes(pl: Node2D) -> void:
	var space := get_world_2d().direct_space_state
	var p := pl.global_position
	for _i in 8:
		var side := 1.0 if randf() < 0.5 else -1.0
		var x := p.x + side * randf_range(EYES_MIN, EYES_MAX)
		var floor_q := PhysicsRayQueryParameters2D.create(Vector2(x, p.y - 20.0), Vector2(x, p.y + 40.0), 1 | 16)
		var floor_hit := space.intersect_ray(floor_q)
		if floor_hit.is_empty():
			continue
		var at := Vector2(x, floor_hit["position"].y - 30.0)
		var wall_q := PhysicsRayQueryParameters2D.create(p + Vector2(0.0, -9.0), at, 1)
		if not space.intersect_ray(wall_q).is_empty():
			continue
		_eyes.global_position = at
		_eyes_life = randf_range(2.5, 4.5)
		_eyes_age = 0.0
		_eyes.visible = true
		_eyes.queue_redraw()
		return

func _update_eyes(delta: float, pl: Node2D) -> void:
	if _eyes_life <= 0.0:
		return
	_eyes_age += delta
	_eyes_life -= delta
	var to_eyes := _eyes.global_position - pl.global_position
	var lit: bool = pl.flashlight and to_eyes.length() < EYES_VANISH_LIGHT \
		and pl.aim_dir.normalized().dot(to_eyes.normalized()) > 0.8
	if _eyes_life <= 0.0 or lit or to_eyes.length() < EYES_VANISH_NEAR:
		_eyes_life = 0.0
		_eyes.visible = false
		return
	_eyes.queue_redraw()

func _draw_eyes() -> void:
	# pojawiają się powoli, na końcu mrugają; nigdy nie świecą pełnią
	var a := minf(_eyes_age / 0.6, 1.0) * 0.55
	if _eyes_life < 0.5 and int(_eyes_life * 14.0) % 2 == 0:
		a = 0.0
	var c := Color(1.0, 0.92, 0.6, a)
	_eyes.draw_circle(Vector2(-3.0, 0.0), 1.4, c)
	_eyes.draw_circle(Vector2(3.0, 0.0), 1.4, c)
