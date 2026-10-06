extends CharacterBody2D
## Gniazdo — cel misji „Gniazdo" (GDD §9, misja 1.3: „spal 3 gniazda").
## Symulacja i HP TYLKO na serwerze; klienci dostają stan przez _sync.
##
## Gniazdo jest w grupie „enemies", bo tak trafiają je pociski (projectile.gd)
## i tak resetuje je wipe (main._restart_mission → reset_enemy). Nie jest
## jednak zagrożeniem: boty go nie ostrzeliwują (is_threat = false), bo
## zniszczenie gniazda jest GŁOŚNE — to decyzja drużyny, nie bota.

signal destroyed(nest: Node)

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Sprites := preload("res://scripts/sprites.gd")

const MAX_HP := 60.0
## Hałas zniszczenia (GDD §8.1): pękające gniazdo budzi okolicę — to cena celu.
const N_DESTROY := 8.0

var hp := MAX_HP
var alive := true

var _flash := 0.0
var _net_timer := 0.0
var _glow: PointLight2D
var _embers: CPUParticles2D
var _spr: Array = []
var _overlay: Node2D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("nests")
	# słaba pomarańczowa poświata — cel misji ma być do znalezienia w mroku,
	# ale nie oświetla okolicy (2,5 m, bez cieni)
	_glow = Lights.make_light(Lights.radial(), 2.5, Color(1.0, 0.45, 0.2), 0.7, false)
	_glow.position = Vector2(0, -8)
	add_child(_glow)
	if Sprites.has("nest"):
		_spr = Sprites.attach(self, "nest")
		Sprites.play(_spr, "pulse", position.x > 1000.0)
	_overlay = Lights.add_overlay(self)
	# żar unoszący się nad gniazdem — widać je z daleka w mroku
	_embers = CPUParticles2D.new()
	_embers.amount = 10
	_embers.lifetime = 1.8
	_embers.position = Vector2(0, -16)
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(12, 3)
	_embers.direction = Vector2.UP
	_embers.spread = 25.0
	_embers.initial_velocity_min = 6.0
	_embers.initial_velocity_max = 16.0
	_embers.gravity = Vector2(0, -4)
	_embers.color = Color(1.0, 0.55, 0.2, 0.8)
	_embers.material = Lights.unshaded()
	add_child(_embers)

func is_threat() -> bool:
	return false

## Restart misji (wipe / nowa próba).
func reset_enemy() -> void:
	hp = MAX_HP
	_set_alive(true)
	_send_state(999.0)

func _set_alive(a: bool) -> void:
	alive = a
	visible = a
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", not a)

## Obrażenia z broni (combat.gd).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not alive:
		return {}
	var dmg: float = info["amount"]
	take_bullet(info["pos"], dmg)
	return {"hit": true, "dealt": dmg, "killed": not alive, "mat": Arsenal.Mat.FLESH}

func take_bullet(_from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	hp -= dmg
	_flash = 0.08
	if hp <= 0.0:
		_destroy()
	else:
		_send_state(999.0)

func _destroy() -> void:
	_set_alive(false)
	NoiseMgr.add_noise(N_DESTROY, global_position)
	_destroy_fx()
	_send_state(999.0)
	destroyed.emit(self)

## Efekty na KAŻDYM peerze (serwer wprost, klient po zmianie alive w _sync).
func _destroy_fx() -> void:
	Audio.play_at("flare_ignite", global_position, Audio.BUS_WORLD, -4.0, 0.7)
	Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -2.0, 0.6)
	if _local_dist() < 240.0:
		Feel.shake(2.5)
	Vfx.gibs(get_parent(), global_position + Vector2(0, -8), Color(0.42, 0.14, 0.18), 9)
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = 40
	fx.lifetime = 0.9
	fx.explosiveness = 0.9
	fx.direction = Vector2(0, -1)
	fx.spread = 60.0
	fx.initial_velocity_min = 40.0
	fx.initial_velocity_max = 130.0
	fx.gravity = Vector2(0, -60)   # płonące strzępy unoszą się
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 2.5
	fx.color = Color(1.0, 0.55, 0.2)
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position + Vector2(0, -8)
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)

func _local_dist() -> float:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp != null and not pp.is_bot and pp.is_multiplayer_authority():
			return pp.global_position.distance_to(global_position)
	return INF

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if NoiseMgr.is_server():
		_send_state(delta)

## Stan rzadko się zmienia — wysyłamy przy zmianie i co 0,5 s (dla dołączających).
func _send_state(delta: float) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 0.5
	_sync.rpc(hp, alive)

@rpc("authority", "call_remote", "reliable")
func _sync(new_hp: float, is_alive: bool) -> void:
	if new_hp < hp - 0.01:
		_flash = 0.08
	hp = new_hp
	if alive and not is_alive:
		_set_alive(false)
		_destroy_fx()
	elif not alive and is_alive:
		_set_alive(true)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
		_overlay.queue_redraw()
		_glow.energy = 0.5 + 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 2.2 + position.x * 0.01))

func _draw() -> void:
	if not _spr.is_empty():
		(_spr[0] as AnimatedSprite2D).modulate = Color(2.4, 2.4, 2.4) if _flash > 0.0 else Color.WHITE
		if _spr[1] != null:
			(_spr[1] as AnimatedSprite2D).frame = (_spr[0] as AnimatedSprite2D).frame
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 2.2 + position.x * 0.01)
	var base := Color(0.32, 0.12, 0.16).lerp(Color(0.45, 0.16, 0.2), pulse)
	if _flash > 0.0:
		base = Color.WHITE
	# organiczny kopiec: kilka nakładających się kół
	draw_circle(Vector2(0, -7), 9.0, base)
	draw_circle(Vector2(-6, -4), 6.0, base.darkened(0.15))
	draw_circle(Vector2(6, -4), 6.0, base.darkened(0.1))
	draw_circle(Vector2(0, -14), 5.5, base.lightened(0.05))

## Żyłki i HP — unshaded, pulsują w ciemności.
func _draw_overlay(ov: Node2D) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 2.2 + position.x * 0.01)
	if _spr.is_empty():
		var glow := Color(1.0, 0.45, 0.25, 0.35 + 0.45 * pulse)
		ov.draw_circle(Vector2(-3, -9), 1.6, glow)
		ov.draw_circle(Vector2(3, -6), 1.3, glow)
		ov.draw_circle(Vector2(0, -15), 1.2, glow)
	if hp < MAX_HP:
		var bar_y := -38.0 if not _spr.is_empty() else -24.0       # sprite gniazda 40x34 jest wyższy niż stary rysunek
		ov.draw_rect(Rect2(-14, bar_y, 28, 2), Color(0.15, 0.05, 0.05))
		ov.draw_rect(Rect2(-14, bar_y, 28.0 * clampf(hp / MAX_HP, 0.0, 1.0), 2), Color(1.0, 0.5, 0.2))
