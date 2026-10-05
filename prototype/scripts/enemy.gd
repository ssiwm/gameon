extends CharacterBody2D
## Wróg podstawowy: Trzosek (wataha, szybki) i Wołek (tank). GDD §7.1.
## Symulacja TYLKO na serwerze; klienci interpolują pozycję i rysują.
##
## Wróg śpi, dopóki nie usłyszy głośnego zdarzenia (strzał, granat — NIE kroki)
## w swoim promieniu słyszenia albo gracz nie podejdzie za blisko. Dzięki temu
## cisza i skradanie mają realną wartość także wobec zwykłych wrogów (filar 2).

const KINDS := {
	"trzosek": {
		"hp": 30.0, "speed": 88.0, "damage": 1, "windup": 0.28, "reach": 13.0,
		"cooldown": 0.9, "leap": true, "hear": 200.0, "wake_near": 90.0,
		"color": Color(0.62, 0.2, 0.22), "size": Vector2(10, 14), "knock": 70.0,
	},
	"wolek": {
		"hp": 140.0, "speed": 36.0, "damage": 2, "windup": 0.6, "reach": 20.0,
		"cooldown": 1.6, "leap": false, "hear": 150.0, "wake_near": 70.0,
		"color": Color(0.36, 0.27, 0.34), "size": Vector2(20, 26), "knock": 14.0,
	},
}

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")

const GRAVITY := 900.0
const MAX_FALL := 620.0
## Kroki (0,25 na tick) nie budzą; każdy strzał tak — także pierwszy z zimnej
## lufy M-83 (0,6). Przy progu 1,0 pojedyncze strzały M-83 były dla wrogów nieme.
const MIN_WAKE_NOISE := 0.5
const SIBLING_WAKE_RADIUS := 140.0
const DEATH_FX_COLOR_VAR := 0.15

@export var kind := "trzosek"

## Nie jest nieśmiertelny, więc boty mogą do niego strzelać, gdy jest aktywny.
var immortal := false
var hp := 30.0
var active := false
var alive := true
var winding := false

var _def: Dictionary
var _home := Vector2.ZERO
var _windup := 0.0
var _windup_target: Node2D = null
var _cd := 0.0
var _leap_cd := 0.0
var _stagger := 0.0
var _flash := 0.0
var _seen_serial := 0
var _net_timer := 0.0
var _remote_pos := Vector2.ZERO
var _max_hp := 30.0
var _overlay: Node2D

func _ready() -> void:
	add_to_group("enemies")
	_def = KINDS.get(kind, KINDS["trzosek"])
	_max_hp = _def["hp"]
	hp = _max_hp
	_home = global_position
	_remote_pos = global_position
	_seen_serial = NoiseMgr.noise_serial
	# kształt kolizji per rodzaj (zasób w scenie jest współdzielony — duplikujemy)
	var cs := $CollisionShape2D as CollisionShape2D
	var shape := (cs.shape as RectangleShape2D).duplicate() as RectangleShape2D
	var size: Vector2 = _def["size"]
	shape.size = size
	cs.shape = shape
	cs.position = Vector2(0, -size.y * 0.5)
	# oczy i pasek HP świecą w ciemności — śpiącego wroga widać jako
	# przygaszone oczy, a nie wcale (skradanie musi mieć informację)
	_overlay = Lights.add_overlay(self)

## Aktywny, żywy wróg = realne zagrożenie (boty strzelają tylko do takich).
func is_threat() -> bool:
	return alive and active

func wake() -> void:
	if not NoiseMgr.is_server() or not alive or active:
		return
	active = true
	# cała wataha budzi się razem
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.has_method("wake") and e.global_position.distance_to(global_position) < SIBLING_WAKE_RADIUS:
			e.wake()

## Restart misji (wipe) — wszystko wraca na start.
func reset_enemy() -> void:
	hp = _max_hp
	active = false
	winding = false
	_windup = 0.0
	_windup_target = null
	_cd = 0.0
	velocity = Vector2.ZERO
	global_position = _home
	_remote_pos = _home
	_set_alive(true)

func _set_alive(a: bool) -> void:
	alive = a
	visible = a
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", not a)

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if not NoiseMgr.is_server():
		global_position = global_position.lerp(_remote_pos, 0.35)
		return
	if not alive:
		return

	_cd = maxf(0.0, _cd - delta)
	_leap_cd = maxf(0.0, _leap_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)

	if not active:
		_check_wake()
		# śpiący wróg stoi i słucha, ale grawitacja działa
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_send_state(delta)
		return

	var target := _nearest_player()
	var speed: float = _def["speed"]
	if _stagger > 0.0:
		speed *= 0.25

	if _windup > 0.0:
		_windup -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _windup <= 0.0:
			_resolve_attack()
	elif target != null:
		var dx := target.global_position.x - global_position.x
		velocity.x = signf(dx) * speed if absf(dx) > 3.0 else 0.0
		# Trzosek doskakuje do gracza na platformie
		if _def["leap"] and is_on_floor() and _leap_cd <= 0.0 \
				and target.global_position.y < global_position.y - 22.0 and absf(dx) < 70.0:
			velocity.y = -250.0
			_leap_cd = 1.2
		elif is_on_wall() and is_on_floor() and _def["leap"]:
			velocity.y = -230.0
		_try_begin_attack(target)
	else:
		velocity.x = 0.0

	_apply_gravity(delta)
	move_and_slide()
	_send_state(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

## Budzi się od NOWEGO głośnego zdarzenia w promieniu słyszenia
## albo gdy gracz stoi za blisko.
func _check_wake() -> void:
	if NoiseMgr.noise_serial != _seen_serial:
		_seen_serial = NoiseMgr.noise_serial
		if NoiseMgr.last_noise_amount >= MIN_WAKE_NOISE \
				and global_position.distance_to(NoiseMgr.last_noise_pos) < float(_def["hear"]):
			wake()
			return
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		# kucający gracz musi podejść bliżej — skradanie się opłaca się
		var near: float = _def["wake_near"] * (0.5 if pp.crouching else 1.0)
		if global_position.distance_to(pp.global_position) < near:
			wake()
			return
	# „Światło przyciąga wzrok Trzosków" (GDD §8.3): snop latarki na
	# śpiącym wrogu go budzi — świecenie po pokoju ma cenę.
	if Lights.flashlight_on(global_position + Vector2(0, -6), get_tree(), get_world_2d().direct_space_state) != null:
		wake()

func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	return best

func _in_reach(pp: Node2D, slack: float) -> bool:
	var reach: float = _def["reach"] + slack
	return absf(pp.global_position.x - global_position.x) <= reach \
		and absf(pp.global_position.y - global_position.y) <= 18.0

func _try_begin_attack(target: Node2D) -> void:
	if _cd > 0.0 or _windup > 0.0:
		return
	if _in_reach(target, 0.0):
		_windup = _def["windup"]
		_windup_target = target
		winding = true

func _resolve_attack() -> void:
	winding = false
	var pp := _windup_target
	_windup_target = null
	_cd = _def["cooldown"]
	if pp != null and is_instance_valid(pp) and not pp.dead and _in_reach(pp, 6.0):
		pp.deliver_hit(_def["damage"], global_position)

## Trafienie pociskiem (tylko serwer). Odrzut i krótkie ogłuszenie dają
## „mięso" strzałowi (GDD §23).
func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	hp -= dmg
	_flash = 0.1
	_stagger = 0.12
	Vfx.blood(get_parent(), global_position + Vector2(0, -8), (global_position - from_pos).normalized(), 5)
	var knock: float = _def["knock"]
	velocity.x += signf(global_position.x - from_pos.x) * knock
	if not active:
		wake()
	if hp <= 0.0:
		_die()

func _die() -> void:
	_set_alive(false)
	winding = false
	_windup = 0.0
	_death_fx()
	_send_state(999.0)

## Efekty śmierci na KAŻDYM peerze (serwer wywołuje wprost, klient po zmianie alive).
func _death_fx() -> void:
	Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.8)
	var local := _local_player_pos()
	if local.distance_to(global_position) < 220.0:
		Feel.shake(1.8 if kind == "trzosek" else 3.0)
		Feel.hitstop(0.05 if kind == "trzosek" else 0.09)
	# szczątki (fizyczne, lokalne) + krew na podłożu; odrzut z kierunku trafienia
	Vfx.gibs(get_parent(), global_position + Vector2(0, -6), (_def["color"] as Color).lightened(DEATH_FX_COLOR_VAR),
		6 if kind == "trzosek" else 11, Vector2(signf(velocity.x) * 60.0, 0))

func _local_player_pos() -> Vector2:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp != null and not pp.is_bot and pp.is_multiplayer_authority():
			return pp.global_position
	return Vector2(INF, INF)

func _send_state(delta: float) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 0.05
	_sync.rpc(global_position, hp, active, alive, winding)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(pos: Vector2, new_hp: float, is_active: bool, is_alive: bool, is_winding: bool) -> void:
	_remote_pos = pos
	if new_hp < hp - 0.01:
		_flash = 0.1
		Vfx.blood(get_parent(), global_position + Vector2(0, -8), Vector2.UP, 5)
	hp = new_hp
	active = is_active
	winding = is_winding
	if alive and not is_alive:
		_set_alive(false)
		_death_fx()
	elif not alive and is_alive:
		_set_alive(true)
		global_position = pos

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
		_overlay.queue_redraw()

func _draw() -> void:
	var size: Vector2 = _def["size"]
	var col: Color = _def["color"]
	if _flash > 0.0:
		col = Color.WHITE
	# śpiący: przygaszony i przygarbiony; zapowiedź ataku: czerwony kontur
	var crouch := 0.0 if active else 3.0
	var body := Rect2(-size.x * 0.5, -size.y + crouch, size.x, size.y - crouch)
	if not active:
		col = col.darkened(0.4)
	draw_rect(body, col)

## Oczy, kontur zapowiedzi ataku i HP — unshaded, widoczne w ciemności.
func _draw_overlay(ov: Node2D) -> void:
	var size: Vector2 = _def["size"]
	var t := Time.get_ticks_msec() / 1000.0
	var crouch := 0.0 if active else 3.0
	if winding:
		var body := Rect2(-size.x * 0.5, -size.y + crouch, size.x, size.y - crouch)
		ov.draw_rect(body.grow(1.5), Color(1.0, 0.15, 0.1, 0.8), false, 1.5)
	var eye_y := -size.y + 4.0 + crouch
	var eye_a := 1.0 if active else 0.25
	var pulse := 0.6 + 0.4 * sin(t * 8.0)
	ov.draw_circle(Vector2(-size.x * 0.22, eye_y), 1.4, Color(1.0, 0.7 * pulse, 0.2, eye_a))
	ov.draw_circle(Vector2(size.x * 0.22, eye_y), 1.4, Color(1.0, 0.7 * pulse, 0.2, eye_a))
	# pasek HP po pierwszym trafieniu
	if hp < _max_hp:
		var w := size.x + 4.0
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w, 2.0), Color(0.15, 0.05, 0.05))
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w * clampf(hp / _max_hp, 0.0, 1.0), 2.0), Color(0.9, 0.25, 0.2))
