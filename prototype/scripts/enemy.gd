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
		"color": Color(0.62, 0.2, 0.22), "size": Vector2(10, 14), "knock": 70.0, "knock_mult": 1.0, "head": 0.0,
	},
	"wolek": {
		"hp": 140.0, "speed": 36.0, "damage": 2, "windup": 0.6, "reach": 20.0,
		"cooldown": 1.6, "leap": false, "hear": 150.0, "wake_near": 70.0,
		"color": Color(0.36, 0.27, 0.34), "size": Vector2(20, 26), "knock": 14.0, "knock_mult": 0.2, "head": 0.28,
	},
}

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Sprites := preload("res://scripts/sprites.gd")

const GRAVITY := 900.0
const MAX_FALL := 620.0
## Kroki (0,25 na tick) nie budzą; każdy strzał tak — także pierwszy z zimnej
## lufy M-83 (0,6). Przy progu 1,0 pojedyncze strzały M-83 były dla wrogów nieme.
const MIN_WAKE_NOISE := 0.5
const AMMO_DROP := {"trzosek": 0.22, "wolek": 0.6}   ## szansa na skrzynkę z amunicją do broni, którą ktoś nosi
const HEALTH_DROP := {"wolek": 0.75}   ## szansa na apteczkę (1.5) — tylko mocniejsi wrogowie
const SIBLING_WAKE_RADIUS := 140.0
const DEATH_FX_COLOR_VAR := 0.15
const BURN_DPS := 8.0

@export var kind := "trzosek"

## Nie jest nieśmiertelny, więc boty mogą do niego strzelać, gdy jest aktywny.
var immortal := false
var hp := 30.0
var active := false
var alive := true
var winding := false
var burning := false          ## replikowane wizualnie przez RPC (_ignite_fx); logika tylko na serwerze

var _def: Dictionary
var _home := Vector2.ZERO
var _windup := 0.0
var _windup_target: Node2D = null
var _cd := 0.0
var _leap_cd := 0.0
var _stagger := 0.0
var _burn := 0.0              ## s płonięcia (serwer)
var _panic := 0.0             ## s paniki po podpaleniu (Trzosek ucieka zamiast atakować)
var _flash := 0.0
var _seen_serial := 0
var _net_timer := 0.0
var _remote_pos := Vector2.ZERO
var _max_hp := 30.0
var _overlay: Node2D
var _spr: Array = []
var _facing := 1.0
var _last_x := 0.0

func _ready() -> void:
	add_to_group("enemies")
	_def = KINDS.get(kind, KINDS["trzosek"])
	_max_hp = _scaled_hp()
	hp = _max_hp
	Difficulty.changed.connect(_on_difficulty_changed)
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
	if Sprites.has(kind):
		_spr = Sprites.attach(self, kind)
	_last_x = global_position.x
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

## HP z uwzględnieniem poziomu trudności (difficulty.gd).
func _scaled_hp() -> float:
	return float(_def["hp"]) * Difficulty.m("enemy_hp")

## Zmiana trudności w lobby/na starcie: nietknięty wróg dostaje nowe HP.
func _on_difficulty_changed(_lvl: int) -> void:
	var untouched := is_equal_approx(hp, _max_hp)
	_max_hp = _scaled_hp()
	if untouched:
		hp = _max_hp

## Restart misji (wipe) — wszystko wraca na start.
func reset_enemy() -> void:
	_max_hp = _scaled_hp()
	hp = _max_hp
	active = false
	winding = false
	_windup = 0.0
	_windup_target = null
	_cd = 0.0
	_burn = 0.0
	_panic = 0.0
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
	_panic = maxf(0.0, _panic - delta)
	_tick_burn(delta)
	if not alive:
		return

	if not active:
		_check_wake()
		# śpiący wróg stoi i słucha, ale grawitacja działa
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_send_state(delta)
		return

	var target := _nearest_player()
	var speed: float = float(_def["speed"]) * Difficulty.m("enemy_speed")
	if _stagger > 0.0:
		speed *= 0.25

	if _windup > 0.0:
		_windup -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _windup <= 0.0:
			_resolve_attack()
	elif target != null and _panic > 0.0:
		# płonący Trzosek ucieka (HKM-9: „strach wśród Trzosków”), nie atakuje
		velocity.x = -signf(target.global_position.x - global_position.x) * speed * 0.9
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
				and global_position.distance_to(NoiseMgr.last_noise_pos) < float(_def["hear"]) * Difficulty.m("enemy_hear"):
			wake()
			return
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		# kucający gracz musi podejść bliżej — skradanie się opłaca się
		var near: float = float(_def["wake_near"]) * Difficulty.m("enemy_hear") * (0.5 if pp.crouching else 1.0)
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
		_windup = float(_def["windup"]) * Difficulty.m("enemy_windup")
		_windup_target = target
		winding = true

func _resolve_attack() -> void:
	winding = false
	var pp := _windup_target
	_windup_target = null
	_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	if pp != null and is_instance_valid(pp) and not pp.dead and _in_reach(pp, 6.0):
		pp.deliver_hit(maxi(1, roundi(float(_def["damage"]) * Difficulty.m("enemy_damage"))), global_position)

## --- API walki (combat.gd) -------------------------------------------------

## Górna część sylwetki = głowa; trafienie powyżej tej linii to krytyk. Niski Trzosek (14 px)
## nie ma słabego punktu — strzał z wysokości barku (−12 px) trafiałby go w „głowę” zawsze,
## więc krytyk byłby stałym mnożnikiem, a nie nagrodą za celowanie. Wołek (26 px) ma głowę
## w górnych 28%: trzeba celować w górę, skakać albo strzelać ze wzniesienia.
func head_y() -> float:
	var frac: float = _def.get("head", 0.0)
	if frac <= 0.0:
		return -INF
	return global_position.y - (_def["size"] as Vector2).y * (1.0 - frac)

func body_center() -> Vector2:
	return global_position + Vector2(0, -(_def["size"] as Vector2).y * 0.5)

func hit_radius() -> float:
	var sz: Vector2 = _def["size"]
	return maxf(sz.x, sz.y) * 0.45

## Cios w plecy: wróg patrzy w tę samą stronę, w którą zadajemy cios (atakujący stoi za nim).
func _is_behind(dir: Vector2) -> bool:
	return signf(dir.x) != 0.0 and signf(dir.x) == _facing

## Obrażenia z broni (serwer). Zwraca {hit, dealt, killed, mat}.
## Maczeta zabija śpiącego albo odwróconego plecami wroga natychmiast i po cichu.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not alive:
		return {}
	var dmg: float = info["amount"]
	var silent: bool = info.get("silent", false)
	if info.get("backstab", false) and (not active or _is_behind(info["dir"])):
		dmg = maxf(dmg, hp + 1.0)
		silent = true
		info["crit"] = true
	hp -= dmg
	_flash = 0.1
	_stagger = maxf(_stagger, 0.12 + float(info.get("stun", 0.0)))
	velocity.x += signf(info["dir"].x) * float(info.get("knock", 0.0)) * float(_def["knock_mult"])
	var fire: float = info.get("ignite", 0.0)
	if fire > 0.0:
		_ignite(fire)
	if not active and not silent:
		wake()
	var dead := hp <= 0.0
	if dead:
		_die()
	return {"hit": true, "dealt": dmg, "killed": dead, "mat": 0}

# ---------------------------------------------------------------- ogień

func _ignite(seconds: float) -> void:
	var fresh := _burn <= 0.0
	_burn = maxf(_burn, seconds)
	if kind == "trzosek":
		_panic = maxf(_panic, 1.2)
	if fresh:
		if NoiseMgr.has_network():
			_ignite_fx.rpc(seconds)
		else:
			_ignite_fx(seconds)

func _tick_burn(delta: float) -> void:
	if _burn <= 0.0:
		return
	_burn = maxf(0.0, _burn - delta)
	# 8 HP/s przez czas płonięcia; wynik liczony ciągle, bez tykania co 0,1 s
	hp -= BURN_DPS * delta
	if hp <= 0.0 and alive:
		_die()

## Płomienie na ciele — każdy peer, na czas płonięcia.
@rpc("authority", "call_local", "reliable")
func _ignite_fx(seconds: float) -> void:
	Vfx.burning(self, seconds)

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
	if NoiseMgr.is_server() and randf() < minf(1.0, float(HEALTH_DROP.get(kind, 0.0)) * Difficulty.m("drops")):
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.spawn_health(global_position + Vector2(0, -14))
	if NoiseMgr.is_server() and randf() < minf(1.0, float(AMMO_DROP.get(kind, 0.0)) * Difficulty.m("drops")):
		var w := Arsenal.pick_drop_weapon()
		var lv := get_tree().get_first_node_in_group("level")
		if w >= 0 and lv != null:
			var n: int = maxi(1, int(Weapons.def(w).pickup_rounds * 0.5))
			lv.spawn_item("ammo", w, global_position + Vector2(randf_range(-6.0, 6.0), -14), n)
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
		_update_sprite()
		queue_redraw()
		_overlay.queue_redraw()

## Animacja: sen / zapowiedź / bieg / czuwanie. Kierunek z przesunięcia pozycji
## (u klientów prędkość wroga nie jest replikowana).
func _update_sprite() -> void:
	if _spr.is_empty():
		return
	var dx := global_position.x - _last_x
	_last_x = global_position.x
	if absf(dx) > 0.05:
		_facing = signf(dx)
	var moving := absf(dx) > 0.05
	var anim := "sleep"
	if active:
		if winding:
			anim = "windup"
		elif moving:
			anim = "run" if kind == "trzosek" else "walk"
		else:
			anim = "idle"
	Sprites.play(_spr, anim, _facing < 0.0)
	var body: AnimatedSprite2D = _spr[0]
	var m := Color.WHITE
	if _flash > 0.0:
		m = Color(2.4, 2.4, 2.4)
	elif winding:
		# zapowiedź ciosu: pulsujące czerwienienie (klatka „windup" unosi łapę)
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		m = Color(1.6 + 0.6 * p, 0.55, 0.5)
	elif not active:
		m = Color(0.8, 0.8, 0.8)
	body.modulate = m

func _draw() -> void:
	if not _spr.is_empty():
		return
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
	if winding and _spr.is_empty():
		var body := Rect2(-size.x * 0.5, -size.y + crouch, size.x, size.y - crouch)
		ov.draw_rect(body.grow(1.5), Color(1.0, 0.15, 0.1, 0.8), false, 1.5)
	if _spr.is_empty():
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
