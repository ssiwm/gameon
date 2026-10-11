extends Node2D
## Ogień na podłodze (HKM-9, faza 3 przeglądu broni): płomień zostawia w punkcie lądowania żar, który pali się FIRE_LIFE s.
## Kto w nim stoi (wróg, skrzynia), dostaje podpalenie — płonący Trzosek panikuje i ucieka. Dla wrogów z flagą `fire_shy`
## (Trzosek, Ślepiec, Skoczek) ogień jest też fizycznym murem (ciało na warstwie FIRE_LAYER, 40 px) — zamyka przejście i
## zatrzymuje hordę; Wołek i Mimik przechodzą przez płomienie, paląc się. Nie rani drużyny i nie blokuje graczy. Świeci: ćmy lecą na ogień i się w nim spalają (enemy.gd `_nearest_light`).
##
## Powstaje u wszystkich peerów (level.gd `spawn_fire_patch`), a obrażenia liczy tylko serwer. Czas życia liczy każdy peer sam.

const Lights := preload("res://scripts/lights.gd")
const Combat := preload("res://scripts/combat.gd")

const FIRE_LIFE := 4.0
const HALF_W := 14.0              ## px: pół szerokości ognia
const HEIGHT := 22.0              ## px nad podłogą, w których cel się pali
const TICK := 0.25
const TICK_DAMAGE := 0.5          ## obrażenia na tyk — resztę robi podpalenie (enemy.gd BURN_DPS)
const IGNITE := 1.2               ## s podpalenia odnawiane przy każdym tyku
const FIRE_LAYER := 64            ## warstwa „muru ognia” (bit 7): maska wrogów z flagą fire_shy (enemy.gd FIRE_BIT); gracze i reszta jej nie mają
const WALL_HEIGHT := 40.0         ## wyższy niż skok wroga (≈29 px), żeby nie przeskakiwali płomieni

var weapon := 0
var shooter_id := 0
var life := FIRE_LIFE

var _t := 0.0
var _tick_t := 0.0
var _light: PointLight2D
var _seed := 0.0

func _ready() -> void:
	add_to_group("fire_patches")
	z_index = 2
	material = Lights.unshaded()
	_seed = float(absi(String(name).hash()) % 628) / 100.0
	_light = Lights.make_light(Lights.radial(), 3.5, Color(1.0, 0.5, 0.18), 0.9, false)
	_light.position = Vector2(0, -6)
	add_child(_light)
	# mur ognia: ciało statyczne tylko na warstwie FIRE_LAYER — blokuje tchórzliwych wrogów (Trzosek, Ślepiec, Skoczek), nie graczy
	var body := StaticBody2D.new()
	body.collision_layer = FIRE_LAYER
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(HALF_W * 2.0, WALL_HEIGHT)
	cs.shape = rs
	cs.position = Vector2(0, -WALL_HEIGHT * 0.5)
	body.add_child(cs)
	add_child(body)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_t += delta
	var fade := clampf(life / 0.8, 0.0, 1.0)
	_light.energy = (0.85 + 0.25 * sin(_t * 13.0 + _seed) * sin(_t * 4.3)) * fade
	queue_redraw()
	if not NoiseMgr.is_server():
		return
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n.is_in_group("boss") or n.is_in_group("nests"):
			continue
		var c := Combat.center_of(n)
		if absf(c.x - global_position.x) > HALF_W + 4.0 or c.y > global_position.y + 4.0 or c.y < global_position.y - HEIGHT:
			continue
		var info := Combat.make_info(weapon, TICK_DAMAGE, c, Vector2.UP, shooter_id, "fire")
		info["ignite"] = IGNITE
		Combat.apply(n, info)
