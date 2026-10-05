extends CharacterBody2D
## Gracz: ruch 8-kierunkowy (Contra), strzelanie, hałas, Przesterowanie,
## down/revive (GDD §4) i czucie gry (GDD §23).
##
## Synchronizacja (GDD §19 poz. 2): stan idzie przez MultiplayerSynchronizer
## (delta + interpolacja zamiast „snajp z ręki"), a pociski są SERWEROWE
## (spawn i kolizje rozstrzyga serwer, klienci tylko rysują).

const Weapons := preload("res://scripts/weapons.gd")
const Lights := preload("res://scripts/lights.gd")

const SPEED := 95.0
const CROUCH_SPEED := 45.0
const JUMP_VELOCITY := -275.0
const GRAVITY := 900.0
const MAX_FALL := 620.0
const MAX_HP := 3

# Czucie gry (GDD §23)
const COYOTE_TIME := 0.10       ## skok jeszcze chwilę po zejściu z krawędzi
const JUMP_BUFFER := 0.10       ## skok wciśnięty tuż przed lądowaniem się liczy
const JUMP_CUT := 0.45          ## puszczenie skoku skraca go (zmienna wysokość)
const INVULN_AFTER_HIT := 0.6   ## chroni przed „serią\" trafień z kilku wrogów naraz
const KICK_DECAY := 600.0
const DROP_TIME := 0.25         ## tyle trwa zeskok przez kładkę (dół + skok)
const PLATFORM_LAYER_BIT := 5   ## warstwa kładek = 16 (level.gd LAYER_PLATFORM)
const FF_KICK := 70.0          ## odrzut od pocisku kolegi (px/s, wygasa KICK_DECAY)
const FF_COOLDOWN := 0.6       ## krzyk/hałas od FF najwyżej raz na tyle sekund

# Down / revive (GDD §4)
const BLEED_TIME := 25.0
const REVIVE_TIME := 4.0
const REVIVE_RANGE := 26.0
const REVIVE_HP := 2
const REVIVE_SYNC_MS := 100     ## postęp podnoszenia wysyłany do innych peerów 10 Hz

# Bot a cisza (filar 2): bot nie może sam psuć skradania ani Przesterowania
const BOT_ENGAGE_RANGE := 260.0
const BOT_SELF_DEFENSE := 70.0  ## w tym promieniu strzela zawsze — obrona własna
const BOT_Q_HOLD := 8.0         ## po Q wstrzymuje ogień, żeby nie nadpisać celu stalkera

# Latarka (GDD §6.6 / §8.3): stożek 8 m, bateria 3 min, światło = hałas
const BATTERY_MAX := 180.0
## Prototyp: bateria wolno się odnawia przy zgaszonej latarce (do playtestu —
## GDD nie mówi o ładowaniu; bez tego po 3 min misja byłaby czarna).
const BATTERY_RECHARGE := 0.25
const LIGHT_NOISE_EVERY := 10.0   ## +1 Uwagi co tyle sekund świecenia

const BULLET_SCENE := preload("res://scenes/bullet.tscn")

const BODY_COLORS := [
	Color(0.91, 0.69, 0.29),
	Color(0.29, 0.84, 0.91),
	Color(0.91, 0.29, 0.44),
	Color(0.49, 0.91, 0.29),
]
const BOT_COLOR := Color(0.62, 0.62, 0.70)

@export var is_bot := false

var player_id := 1
var display_id := 1
var hp := MAX_HP
var aim_dir := Vector2.RIGHT
var crouching := false
## `dead` znaczy „down": gracz leży i wykrwawia się, ale można go podnieść.
var dead := false
var bleed_left := 0.0
var weapon := 0
## Postęp podnoszenia widoczny TYLKO lokalnie u podnoszącego (rysowany nad leżącym).
var revive_progress := 0.0
## Latarka włączona — replikowane, bo snop widzą wszyscy, a wrogowie
## (serwer) reagują na światło.
var flashlight := false
var battery := BATTERY_MAX

var _fire_timer := 0.0
var _run_noise_tick := 0.0
var _flash := 0.0
var _muzzle := 0.0
var _invuln := 0.0
var _heat := 0.0
var _kick := 0.0
var _ff_cd := 0.0
var _coyote := 0.0
var _drop_t := 0.0
var _light_noise_t := 0.0
var _aura: PointLight2D
var _beam: PointLight2D
var _muzzle_light: PointLight2D
var _overlay: Node2D
var _jump_buf := 0.0
var _was_on_floor := true
var _spawn_point := Vector2.ZERO
var _is_remote := true
var _revive_hold := 0.0
var _revive_target_ref: Node2D = null
var _revive_sent_ms := 0
## Kroki liczymy z przebytej drogi, nie z czasu — inaczej krok „leci" w miejscu
## po stopniowaniu w dół albo lata w powietrzu.
var _step_dist := 0.0
var _last_step_pos := Vector2.ZERO
var _breath_on := false
var _air_time_accum := 0.0

@onready var _camera: Camera2D = $Camera2D

## Synchronizator tworzymy w _init, a autorytet ustawiamy w _enter_tree
## (rekurencyjnie, więc obejmuje też synchronizator). Wcześniej synchronizator
## powstawał w _ready PO set_multiplayer_authority() i miał domyślny autorytet 1:
## serwer nadpisywał stan postaci klienta swoją nieruchomą kopią (ruch, HP
## i obrażenia klienta znikały). Zmiana autorytetu w _ready jest za późna dla
## spawnera („no network ID") — Godot wymaga _enter_tree.
func _init() -> void:
	_setup_sync()

func _enter_tree() -> void:
	player_id = name.to_int()
	if player_id <= 0:
		player_id = 1
	# Nazwa węzła = id peera. Autorytet ustawiamy na KAŻDYM peerze, bo spawner
	# nie przenosi go na klientów — bez tego własna postać klienta miała
	# autorytet 1 i is_multiplayer_authority() zawodziło (HUD, obrażenia).
	# Boty: autorytet 1 (serwer) — ustawiony przez main.gd.
	if not is_bot:
		set_multiplayer_authority(player_id)

func _ready() -> void:
	add_to_group("players")
	_spawn_point = position
	_setup_lights()
	call_deferred("_setup_local")

## Światła postaci (każdy peer): aura 6 m, snop latarki 8 m, rozbłysk lufy.
## Etykiety i paski idą na nakładkę „unshaded" — w ciemności mają być czytelne.
func _setup_lights() -> void:
	var chest := Vector2(0, -9)
	_aura = Lights.make_light(Lights.radial(), Lights.BASE_M, Color(1.0, 0.9, 0.78), Lights.AURA_ENERGY, true)
	_aura.position = chest
	add_child(_aura)
	_beam = Lights.make_light(Lights.cone(), Lights.FLASHLIGHT_M, Color(1.0, 0.96, 0.84), 0.85, true)
	_beam.position = chest
	_beam.enabled = false
	add_child(_beam)
	_muzzle_light = Lights.make_light(Lights.radial(), 4.0, Color(1.0, 0.8, 0.45), 1.4, false)
	_muzzle_light.position = chest
	_muzzle_light.enabled = false
	add_child(_muzzle_light)
	_overlay = Lights.add_overlay(self)

## Synchronizacja stanu przez MultiplayerSynchronizer (GDD §19 poz. 2).
## Zamiast ręcznych RPC 20 Hz mamy delta-sync z wbudowaną interpolacją.
func _setup_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	# replication_config MUSI być ustawione PRZED add_child, inaczej replikacja
	# startuje z pustym configiem (ERR_UNCONFIGURED)
	sync.root_path = NodePath("..")
	sync.replication_interval = 0.05
	sync.delta_interval = 0.05
	var cfg := SceneReplicationConfig.new()
	for path in [":position", ":velocity", ":aim_dir", ":hp", ":crouching", ":dead", ":display_id", ":is_bot", ":bleed_left", ":weapon", ":flashlight"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path in [":position", ":velocity", ":hp", ":crouching", ":dead", ":is_bot", ":display_id"]:
		cfg.property_set_spawn(path, true)
	sync.replication_config = cfg
	add_child(sync)

func _setup_local() -> void:
	# Człowiek: autorytet = jego peer. Bot: autorytet = serwer (steruje nim host).
	_is_remote = not is_multiplayer_authority()
	var local_human := not is_bot and not _is_remote
	_camera.enabled = local_human
	if local_human:
		_camera.make_current()
		# granice kamery z mapy (level.gd) zamiast stałych z player.tscn
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			var b: Rect2 = lvl.bounds
			_camera.limit_left = int(b.position.x)
			_camera.limit_top = int(b.position.y)
			_camera.limit_right = int(b.end.x)
			_camera.limit_bottom = int(b.end.y)
	print("[NET] player ready id=%d display=%d remote=%s bot=%s" % [player_id, display_id, str(_is_remote), str(is_bot)])

## Rysowanie odświeżamy na każdym peerze (zdalni gracze też zmieniają celowanie,
## kucanie i HP), a kamera dostaje lokalny shake.
func _process(delta: float) -> void:
	_muzzle = maxf(0.0, _muzzle - delta)
	_flash = maxf(0.0, _flash - delta)
	if _camera.enabled:
		_camera.offset = Feel.shake_offset()
	if _is_remote or is_bot:
		_update_footsteps_passive()
	_update_lights()
	queue_redraw()
	_overlay.queue_redraw()

func _update_lights() -> void:
	_aura.enabled = not dead
	_aura.energy = Lights.AURA_ENERGY * (1.0 if not crouching else 0.75)
	_beam.enabled = flashlight and not dead
	if _beam.enabled:
		_beam.rotation = aim_dir.angle()
		# lekkie drżenie snopu — latarka w ręku, nie reflektor
		_beam.energy = 0.85 + 0.04 * sin(Time.get_ticks_msec() * 0.023)
	_muzzle_light.enabled = _muzzle > 0.0
	_muzzle_light.position = Vector2(0, -9) + aim_dir * 10.0

## Latarka: bateria, hałas „+1 Uwagi co 10 s" (GDD §6.6). Tylko właściciel.
func _update_flashlight(delta: float) -> void:
	if flashlight and not dead:
		battery = maxf(0.0, battery - delta)
		_light_noise_t += delta
		if _light_noise_t >= LIGHT_NOISE_EVERY:
			_light_noise_t = 0.0
			NoiseMgr.add_noise(1.0, global_position)
		if battery <= 0.0:
			flashlight = false
			if not is_bot:
				Audio.play("dry_fire", Audio.BUS_UI, -10.0, 0.6)
	else:
		battery = minf(BATTERY_MAX, battery + delta * BATTERY_RECHARGE)

func _toggle_flashlight() -> void:
	if not flashlight and battery < 1.0:
		Audio.play("ui_deny", Audio.BUS_UI, -10.0)
		return
	flashlight = not flashlight
	_light_noise_t = 0.0
	Audio.play("ui_click", Audio.BUS_PLAYER, -10.0, 0.7 if flashlight else 0.55)

## Zdalni gracze: pozycję interpoluje synchronizator, więc nie ruszamy tu nic.
func _physics_process(delta: float) -> void:
	if _is_remote:
		return

	_invuln = maxf(0.0, _invuln - delta)
	_ff_cd = maxf(0.0, _ff_cd - delta)
	_heat = maxf(0.0, _heat - Weapons.HEAT_DECAY * delta)

	_update_flashlight(delta)
	if dead:
		_down_physics(delta)
		return

	_fire_timer = maxf(0.0, _fire_timer - delta)

	if is_bot:
		_bot_brain(delta)
		return

	_local_brain(delta)

# ---------------------------------------------------------------- local input

func _local_brain(delta: float) -> void:
	_update_weapon_select()
	var reviving := _handle_revive(delta, Input.is_action_pressed("interact"))

	var move_x := 0.0 if reviving else Input.get_axis("move_left", "move_right")
	var aim_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	crouching = Input.is_action_pressed("crouch") and is_on_floor()

	if aim_input != Vector2.ZERO:
		# klawiatura/pad: 8 kierunków (klasyka Contry)
		aim_dir = _snap8(aim_input)
	elif Input.get_last_mouse_velocity().length() > 20.0:
		# mysz: celowanie swobodne — snap do 8 kierunków czuje się dziwnie
		var to_mouse := get_global_mouse_position() - (global_position + Vector2(0, -9))
		if to_mouse.length() > 6.0:
			aim_dir = to_mouse.normalized()

	var speed := CROUCH_SPEED if crouching else SPEED
	_kick = move_toward(_kick, 0.0, KICK_DECAY * delta)
	velocity.x = move_x * speed + _kick

	# --- skok: coyote time + jump buffer + zmienna wysokość (GDD §23)
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	_update_drop(delta, on_floor)

	if not on_floor:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	if _jump_buf > 0.0 and _coyote > 0.0 and not crouching and not reviving:
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		Audio.play_variant("effort", 2, Audio.BUS_PLAYER, -20.0)

	# puszczenie skoku w górze lotu skraca go
	if Input.is_action_just_released("jump") and velocity.y < JUMP_VELOCITY * JUMP_CUT:
		velocity.y = JUMP_VELOCITY * JUMP_CUT

	if not _was_on_floor and is_on_floor():
		NoiseMgr.mark_local_activity()
		# Twarde lądowanie — tym głośniejsze, im większy spadek, bo GDD §8.1
		# traktuje lądowanie jako aktywność podnoszącą Uwagę.
		var drop := _air_time_accum
		if drop > 0.25:
			Audio.play_at("land_hard", global_position, Audio.BUS_PLAYER,
				lerpf(-24.0, -8.0, clampf(drop / 1.2, 0.0, 1.0)))
			Feel.shake(clampf(drop * 2.0, 0.0, 2.0))
		_air_time_accum = 0.0
	elif not is_on_floor():
		_air_time_accum += delta
	_was_on_floor = is_on_floor()

	move_and_slide()
	_update_footsteps()
	_update_breath()

	# bieganie = hałas (GDD §8.1: 0,5/s — jedna wartość, solo i sieć)
	if absf(velocity.x) > 5.0 and is_on_floor() and not crouching:
		_run_noise_tick += delta
		if _run_noise_tick >= 0.5:
			_run_noise_tick = 0.0
			NoiseMgr.add_noise(NoiseMgr.N_RUN_PER_SEC * 0.5, global_position)

	var d := Weapons.def(weapon)
	var want_fire: bool = Input.is_action_pressed("fire") if d["auto"] else Input.is_action_just_pressed("fire")
	if want_fire and _fire_timer <= 0.0 and not reviving:
		_fire()

	if Input.is_action_just_pressed("overcharge"):
		_try_overcharge()
	if Input.is_action_just_pressed("flashlight"):
		_toggle_flashlight()

## Zeskok z kładki: dół + skok, stojąc na kładce. Na chwilę wyłączamy
## kolizję z warstwą kładek; skok jest wtedy „zjedzony".
func _update_drop(delta: float, on_floor: bool) -> void:
	if _drop_t > 0.0:
		_drop_t -= delta
		if _drop_t <= 0.0:
			set_collision_mask_value(PLATFORM_LAYER_BIT, true)
		return
	if _jump_buf <= 0.0 or not on_floor or not Input.is_action_pressed("move_down"):
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.is_platform_at(global_position):
		return
	_jump_buf = 0.0
	_drop_t = DROP_TIME
	set_collision_mask_value(PLATFORM_LAYER_BIT, false)
	position.y += 1.0

func _update_weapon_select() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_select_weapon(Weapons.M83)
	elif Input.is_action_just_pressed("weapon_2"):
		_select_weapon(Weapons.SPREAD12)
	elif Input.is_action_just_pressed("weapon_3"):
		_select_weapon(Weapons.P64)
	elif Input.is_action_just_pressed("weapon_next"):
		_select_weapon((weapon + 1) % Weapons.COUNT)
	elif Input.is_action_just_pressed("weapon_prev"):
		_select_weapon((weapon + Weapons.COUNT - 1) % Weapons.COUNT)

func _select_weapon(w: int) -> void:
	if w == weapon:
		return
	weapon = w
	_fire_timer = maxf(_fire_timer, 0.15)
	Audio.play("ui_click", Audio.BUS_UI, -12.0)

func _fire() -> void:
	var d := Weapons.def(weapon)
	var cooldown: float = d["cooldown"]
	_fire_timer = cooldown
	_muzzle = 0.06
	Audio.play_variant(d["sfx"], d["sfx_count"], Audio.BUS_WEAPONS, d["sfx_vol"], d["sfx_pitch"])
	Audio.play_variant("whizz", 3, Audio.BUS_WEAPONS, -26.0, 1.0)
	# własny dźwięk już zagrany — serwer nie dubluje go dla strzelającego
	_request_bullet(weapon, false)
	_add_shot_noise()
	Feel.shake(d["shake"])
	var kick: float = d["kick"]
	if kick > 0.0:
		_kick = -aim_dir.x * kick

## Hałas strzału z modelu rozgrzania (weapons.gd); potem lufa się grzeje.
func _add_shot_noise() -> void:
	NoiseMgr.add_noise(Weapons.shot_noise(weapon, _heat), global_position)
	_heat = minf(1.0, _heat + float(Weapons.def(weapon)["heat_gain"]))

func _try_overcharge() -> void:
	# Dźwięk od razu, niezależnie od tego czy ładunek się uda — klik ma potwierdzać
	# akcję, a nie rozstrzygać (rozstrzyga use_overcharge).
	Audio.play("oc_load", Audio.BUS_UI, -10.0)
	var pos := global_position
	if not NoiseMgr.has_network():
		NoiseMgr.use_overcharge(pos)
	elif multiplayer.is_server():
		NoiseMgr.use_overcharge(pos)
	else:
		_noise_manager_request.rpc_id(1, pos)

## Pociski są serwerowe: klient prosi serwer, serwer spawnuje i rozstrzyga trafienia.
func _request_bullet(w: int, play_sfx: bool) -> void:
	var muzzle := global_position + Vector2(0, -9) + aim_dir * 9.0
	if not NoiseMgr.has_network() or multiplayer.is_server():
		_server_fire(muzzle, aim_dir, player_id, w, play_sfx)
	else:
		_fire_request.rpc_id(1, muzzle, aim_dir, w)

@rpc("any_peer", "call_remote", "reliable")
func _fire_request(muzzle: Vector2, dir: Vector2, w: int) -> void:
	if multiplayer.is_server() and not dead:
		_server_fire(muzzle, dir, player_id, clampi(w, 0, Weapons.COUNT - 1), true)

@rpc("any_peer", "call_remote", "reliable")
func _noise_manager_request(pos: Vector2) -> void:
	if multiplayer.is_server():
		NoiseMgr.use_overcharge(pos)

# ---------------------------------------------------------------- down / revive

## Leżący gracz: wykrwawia się, spada na ziemię i czeka na pomoc.
func _down_physics(delta: float) -> void:
	bleed_left = maxf(0.0, bleed_left - delta)
	velocity.x = 0.0
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	move_and_slide()
	_revive_hold = 0.0
	if bleed_left <= 0.0:
		# kara dystansem i czasem, nie ekranem „game over" (GDD §4)
		_respawn(1)

func _go_down() -> void:
	hp = 0
	dead = true
	bleed_left = BLEED_TIME
	velocity = Vector2.ZERO
	crouching = false
	Audio.play("player_down", Audio.BUS_PLAYER, -5.0)
	if _breath_on:
		_breath_on = false
		Audio.stop_loop("breath_loop")

## Najbliższy leżący towarzysz w zasięgu podnoszenia (poza sobą).
func _revive_target() -> Node2D:
	var best: Node2D = null
	var best_d := REVIVE_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp == self or not pp.dead:
			continue
		var dx := absf(pp.global_position.x - global_position.x)
		var dy := absf(pp.global_position.y - global_position.y)
		if dy > 30.0:
			continue
		if dx < best_d:
			best_d = dx
			best = pp
	return best

## Trzymanie przycisku przy leżącym koledze. Zwraca true, gdy postać jest
## „zajęta" podnoszeniem (stoi w miejscu i nie strzela).
func _handle_revive(delta: float, holding: bool) -> bool:
	var t: Node2D = _revive_target() if holding else null
	if t != _revive_target_ref:
		if _revive_target_ref != null and is_instance_valid(_revive_target_ref):
			_revive_target_ref.set_revive_progress(0.0)
		_revive_hold = 0.0
		_revive_target_ref = t
	if t == null:
		return false
	_revive_hold += delta
	t.set_revive_progress(clampf(_revive_hold / REVIVE_TIME, 0.0, 1.0))
	if _revive_hold >= REVIVE_TIME:
		_revive_hold = 0.0
		t.set_revive_progress(0.0)
		t.request_revive()
		_revive_target_ref = null
	return true

## Postęp liczy podnoszący, ale widzieć go musi też leżący (i reszta drużyny),
## więc rozsyłamy go do wszystkich peerów (10 Hz, zero zawsze od razu).
func set_revive_progress(v: float) -> void:
	if is_equal_approx(v, revive_progress):
		return
	revive_progress = v
	if not NoiseMgr.has_network():
		return
	var now := Time.get_ticks_msec()
	if v <= 0.0 or now - _revive_sent_ms >= REVIVE_SYNC_MS:
		_revive_sent_ms = now
		_revive_progress_rpc.rpc(v)

@rpc("any_peer", "call_remote", "reliable")
func _revive_progress_rpc(v: float) -> void:
	revive_progress = v

## Podpowiedź dla HUD (tylko lokalny człowiek).
func revive_hint() -> String:
	if dead:
		return ""
	var t := _revive_target()
	if t == null:
		return ""
	return "Przytrzymaj [E]: podnieś %s" % ("BOT" if t.is_bot else "P%d" % t.display_id)

## Prośba o podniesienie — rozstrzyga właściciel leżącej postaci.
func request_revive() -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		_do_revive()
	else:
		_revive_rpc.rpc_id(get_multiplayer_authority())

@rpc("any_peer", "call_remote", "reliable")
func _revive_rpc() -> void:
	if is_multiplayer_authority():
		_do_revive()

func _do_revive() -> void:
	if not dead:
		return
	dead = false
	hp = REVIVE_HP
	bleed_left = 0.0
	revive_progress = 0.0
	_invuln = 1.2
	Audio.play("revive", Audio.BUS_PLAYER, -9.0)
	if not is_bot:
		Feel.shake(1.5)

func _respawn(hp_amount: int) -> void:
	dead = false
	hp = hp_amount
	bleed_left = 0.0
	revive_progress = 0.0
	global_position = _spawn_point
	velocity = Vector2.ZERO
	_invuln = 1.5
	_heat = 0.0
	_last_step_pos = global_position
	_step_dist = 0.0
	Audio.play("revive", Audio.BUS_PLAYER, -9.0)

## Restart po wipe (wszyscy leżą): pełne zdrowie w punkcie startu.
func full_reset() -> void:
	_respawn(MAX_HP)
	_kick = 0.0
	_revive_hold = 0.0
	_revive_target_ref = null

## Wołane przez serwer po wipe — reset wykonuje właściciel postaci, bo tylko on
## ma autorytet nad jej pozycją i HP (synchronizator by to nadpisał).
func request_full_reset() -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		full_reset()
	else:
		_full_reset_rpc.rpc_id(get_multiplayer_authority())

## „any_peer", bo woła serwer na postaci należącej do klienta; przyjmujemy
## tylko od serwera.
@rpc("any_peer", "call_remote", "reliable")
func _full_reset_rpc() -> void:
	if multiplayer.get_remote_sender_id() == 1:
		full_reset()

# ---------------------------------------------------------------- audio

## Kroki: krok co ~22 px drogi. Przy kucaniu dłuższy interwał, bo chód
## kucając jest ciszej i wolniejszy (GDD §8.1: kucanie = 0 hałasu).
func _update_footsteps() -> void:
	if not is_on_floor() or dead:
		return
	var moved := global_position - _last_step_pos
	_last_step_pos = global_position
	if moved.length() < 0.5:
		return
	_step_dist += moved.length()
	var stride := 34.0 if crouching else 22.0
	if _step_dist >= stride:
		_step_dist = 0.0
		Audio.play_footstep(global_position, crouching)


## Kroki CUDZYCH postaci (zdalni gracze, bot). Wcześniej kroki grała tylko
## własna postać — kolegi i bota nie było słychać wcale, a w co-op horrorze
## kroki drużyny to informacja „gdzie jest reszta". is_on_floor() nie działa
## dla pozycji z synchronizatora, więc ziemię rozpoznajemy po braku ruchu
## w pionie. Ciszej niż własne, i pozycyjnie (okluzja przez ściany).
func _update_footsteps_passive() -> void:
	var moved := global_position - _last_step_pos
	_last_step_pos = global_position
	# w powietrzu, leży albo teleport (respawn/wipe) — bez kroku
	if dead or absf(moved.y) > 0.6 or moved.length() > 40.0:
		_step_dist = 0.0
		return
	_step_dist += absf(moved.x)
	var stride := 34.0 if crouching else 22.0
	if _step_dist >= stride:
		_step_dist = 0.0
		Audio.play_footstep(global_position, crouching, -19.0)

## Oddech: ciągły przy wysiłku (skradanie w napięciu, bieg) i cisza gdy stoisz.
func _update_breath() -> void:
	var exertion := 0.0
	if crouching:
		exertion = 0.55
	if absf(velocity.x) > 5.0 and is_on_floor() and not crouching:
		exertion = 1.0
	var want := exertion > 0.0
	if want and not _breath_on:
		_breath_on = true
		Audio.start_loop("breath_loop", Audio.BUS_PLAYER, -18.0)
	elif want and Audio.loop_playing("breath_loop"):
		Audio.set_loop_volume("breath_loop", lerpf(-24.0, -12.0, exertion))
	elif not want and _breath_on:
		_breath_on = false
		Audio.stop_loop("breath_loop")

# ---------------------------------------------------------------- bot AI

const LEADER_SWITCH := 60.0

var _bot_target_pos := Vector2.ZERO
var _bot_leader: Node2D = null
var _bot_wants_jump := false
var _bot_repath := 0.0

func _bot_brain(delta: float) -> void:
	_bot_repath -= delta
	if _bot_repath <= 0.0:
		_bot_repath = 0.4
		_pick_bot_goal()

	# podnoszenie leżącego towarzysza — bot nie jest szybszy od człowieka (GDD §4)
	var downed := _downed_teammate()
	var near_downed := downed != null \
		and absf(downed.global_position.x - global_position.x) < REVIVE_RANGE - 6.0 \
		and absf(downed.global_position.y - global_position.y) < 30.0
	var reviving := _handle_revive(delta, near_downed)

	# ruch w stronę celu (poziomo), skok przy przeszkodzie lub celu wyżej
	# bot naśladuje skradanie dowódcy — inaczej drużyna nie może grać cicho
	var leader := _leader()
	var stealth: bool = leader != null and not leader.dead and leader.crouching
	crouching = stealth and is_on_floor()
	# latarka jak u dowódcy — bot nie świeci sam (światło = hałas, §8.3)
	flashlight = leader != null and leader.flashlight and not crouching and battery > 1.0

	var dx := _bot_target_pos.x - global_position.x
	var dy := _bot_target_pos.y - global_position.y
	if reviving or absf(dx) < 8.0:
		velocity.x = 0.0
	else:
		velocity.x = signf(dx) * (CROUCH_SPEED if crouching else SPEED * 0.85)
	# odrzut (np. od pocisku kolegi) działa też na bota
	_kick = move_toward(_kick, 0.0, KICK_DECAY * delta)
	velocity.x += _kick
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	elif _bot_wants_jump or (not crouching and ((absf(dx) > 6.0 and is_on_wall()) or (dy < -24.0 and absf(dx) < 70.0))):
		velocity.y = JUMP_VELOCITY
	_bot_wants_jump = false
	move_and_slide()

	if reviving:
		return

	# celowanie w najbliższego aktywnego wroga (nigdy w śpiących — nie psuje ciszy)
	var enemy := _nearest_enemy(BOT_ENGAGE_RANGE)
	if enemy != null:
		var d := (enemy.global_position - global_position)
		if d.length() > 6.0:
			aim_dir = _snap8(d)
		var los := _los_state(enemy) if _fire_timer <= 0.0 else Los.WALL
		if los == Los.TEAMMATE and is_on_floor() and not crouching:
			# kolega na linii — podskok daje czystą linię nad nim
			_bot_wants_jump = true
		if _fire_timer <= 0.0 and _aim_ok(d) and _bot_may_fire(d) and los == Los.CLEAR:
			_fire_timer = float(Weapons.def(Weapons.M83)["cooldown"]) * 1.8
			_muzzle = 0.06
			weapon = Weapons.M83
			# Boty symulowane są tylko na serwerze; serwer gra też ich dźwięk.
			_request_bullet(Weapons.M83, true)
			_add_shot_noise()

## Dyscyplina ognia bota (filar 2). Strzał to hałas, a każdy nowy hałas
## przekierowuje stalkera — bot strzelający „bo widzi wroga" kasował Q drużyny
## i nie pozwalał Uwadze opaść. Z bliska broni się zawsze.
func _bot_may_fire(d: Vector2) -> bool:
	if d.length() <= BOT_SELF_DEFENSE:
		return true
	if crouching:
		return false
	return NoiseMgr.seconds_since_overcharge() >= BOT_Q_HOLD

enum Los { CLEAR, WALL, TEAMMATE }

## Linia strzału bota: ściana (strzał w nią to sam hałas) albo stojący kolega.
## Wcześniej promień widział tylko ściany (maska 1), więc bot strzelał
## w wroga przez plecy człowieka. Leżących kolegów pomijamy — pocisk i tak
## przez nich przelatuje (bullet.gd).
func _los_state(target: Node2D) -> int:
	var from := global_position + Vector2(0, -9)
	var to := target.global_position + Vector2(0, -6)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 2)
	var exclude: Array[RID] = [get_rid()]
	var space := get_world_2d().direct_space_state
	for _i in 4:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return Los.CLEAR
		var c: Object = hit["collider"]
		if c is Node and (c as Node).is_in_group("players"):
			if c.dead:
				exclude.append(hit["rid"])
				continue
			return Los.TEAMMATE
		return Los.WALL
	return Los.CLEAR

func _aim_ok(d: Vector2) -> bool:
	# strzela tylko gdy wróg jest mniej więcej na tej samej wysokości lub tuż obok
	return absf(d.y) < 60.0 or absf(d.x) < 40.0

func _pick_bot_goal() -> void:
	# 1) leżący towarzysz do podniesienia
	var downed := _downed_teammate()
	if downed != null:
		_bot_target_pos = downed.global_position
		return
	var leader := _leader()
	if leader != null:
		# trzyma się 2 kafle za dowódcą
		var side := 1.0 if display_id % 2 == 0 else -1.0
		_bot_target_pos = leader.global_position + Vector2(side * 26.0, 0)
		return
	_bot_target_pos = _spawn_point

func _downed_teammate() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp == self or not pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	return best

## Dowódca bota = NAJBLIŻSZY stojący człowiek (dowolny peer). Wcześniej bot
## szedł zawsze za graczem z autorytetem lokalnym — na serwerze to host, więc
## przy 2 ludziach klient nie miał wsparcia, nawet stojąc obok bota.
## Histereza: zmiana dowódcy dopiero gdy inny jest bliżej o LEADER_SWITCH px,
## inaczej bot dygotałby między dwoma graczami w podobnej odległości.
func _leader() -> Node2D:
	var cur := _bot_leader if is_instance_valid(_bot_leader) and not _bot_leader.dead else null
	var cur_d := global_position.distance_to(cur.global_position) if cur != null else INF
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.is_bot or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	if cur == null or (best != null and best_d < cur_d - LEADER_SWITCH):
		_bot_leader = best
	return _bot_leader if is_instance_valid(_bot_leader) else null

func _nearest_enemy(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		var ee := e as Node2D
		if ee == null or not ee.visible:
			continue
		# tylko realne zagrożenia: aktywni wrogowie (nie Stalker, nie śpiący)
		if not ee.has_method("is_threat") or not ee.is_threat():
			continue
		var d := global_position.distance_to(ee.global_position)
		if d < best_d:
			best_d = d
			best = ee
	return best

# ---------------------------------------------------------------- serwer

## Autorytatywny strzał na serwerze: pociski (śrut = kilka), dźwięk dla peerów.
func _server_fire(muzzle: Vector2, dir: Vector2, shooter: int, w: int, play_sfx: bool) -> void:
	var d := Weapons.def(w)
	var pellets: int = d["pellets"]
	var spread: float = d["spread_deg"]
	var jitter: float = d["jitter_deg"]
	var dirs := PackedVector2Array()
	for i in pellets:
		var off := randf_range(-jitter, jitter)
		if pellets > 1:
			off += lerpf(-spread, spread, float(i) / float(pellets - 1))
		dirs.append(dir.rotated(deg_to_rad(off)))
	for dd in dirs:
		_make_bullet(muzzle, dd, shooter, w)
	if play_sfx:
		Audio.play_variant_at(d["sfx"], d["sfx_count"], muzzle, Audio.BUS_WEAPONS,
			float(d["sfx_vol"]) - 3.0, d["sfx_pitch"])
	# wizualne kopie na klientach (call_remote — serwer nie duplikuje u siebie)
	if NoiseMgr.has_network():
		_fire_remote.rpc(muzzle, dirs, shooter, w)

## Mode „any_peer": serwer woła to na węźle należącym do KLIENTA, a tryb
## „authority" by na to nie pozwolił (wcześniej klienci nie widzieli cudzych strzałów).
@rpc("any_peer", "call_remote", "reliable")
func _fire_remote(muzzle: Vector2, dirs: PackedVector2Array, shooter: int, w: int) -> void:
	if NoiseMgr.is_server():
		return
	var d := Weapons.def(w)
	# własny strzał słyszeliśmy lokalnie, cudzy gramy pozycyjnie
	if shooter != NoiseMgr.local_id():
		Audio.play_variant_at(d["sfx"], d["sfx_count"], muzzle, Audio.BUS_WEAPONS,
			float(d["sfx_vol"]) - 3.0, d["sfx_pitch"])
	for dd in dirs:
		_make_bullet(muzzle, dd, shooter, w)

func _make_bullet(muzzle: Vector2, dir: Vector2, shooter: int, w: int) -> void:
	var d := Weapons.def(w)
	var b := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = muzzle
	b.direction = dir
	b.shooter_id = shooter
	b.speed = d["speed"]
	b.damage = d["damage"]
	b.life_max = d["life"]
	b.weapon = w

## Dostarcza obrażenia WŁAŚCICIELOWI postaci. apply_hit ma straż
## is_multiplayer_authority(), więc wywołanie go bezpośrednio na serwerze dla
## cudzej postaci kończyło się po cichu — gracze-klienci nie dostawali obrażeń
## od Stalkera ani od friendly fire. Wszystkie źródła obrażeń wołają tę metodę.
## Friendly fire bez obrażeń (bullet.gd): rozstrzyga właściciel postaci.
func deliver_ff(from_pos: Vector2) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_ff(from_pos)
	else:
		apply_ff.rpc_id(get_multiplayer_authority(), from_pos)

## Trafienie przez kolegę: odrzut, błysk i krzyk = HAŁAS (Uwaga), zero HP.
@rpc("any_peer", "call_remote", "reliable")
func apply_ff(from_pos: Vector2) -> void:
	if not is_multiplayer_authority() or dead:
		return
	_kick = signf(global_position.x - from_pos.x) * FF_KICK
	_flash = maxf(_flash, 0.12)
	if _ff_cd > 0.0:
		return
	_ff_cd = FF_COOLDOWN
	Audio.play_variant_at("player_hurt", 2, global_position, Audio.BUS_PLAYER, -12.0, 1.15)
	NoiseMgr.add_noise(NoiseMgr.N_FF, global_position)
	if not is_bot:
		Feel.shake(1.5)

func deliver_hit(amount: int, from_pos: Vector2) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_hit(amount, from_pos)
	else:
		apply_hit.rpc_id(get_multiplayer_authority(), amount, from_pos)

@rpc("any_peer", "call_remote", "reliable")
func apply_hit(amount: int, _from_pos: Vector2) -> void:
	if not is_multiplayer_authority() or dead or _invuln > 0.0:
		return
	hp -= amount
	_invuln = INVULN_AFTER_HIT
	_flash = 0.25
	Audio.play_variant("player_hurt", 2, Audio.BUS_PLAYER, -8.0)
	# krzyk bólu zawsze, w każdym trybie (wcześniej tylko solo)
	NoiseMgr.add_noise(NoiseMgr.N_HURT, global_position)
	if not is_bot:
		Feel.shake(4.0)
		Feel.hitstop(0.07)
	if hp <= 0:
		_go_down()

func _snap8(v: Vector2) -> Vector2:
	if v == Vector2.ZERO:
		return aim_dir
	return Vector2.from_angle(snappedf(v.angle(), TAU / 8.0))

func _body_color() -> Color:
	if is_bot:
		return BOT_COLOR
	return BODY_COLORS[(display_id - 1) % BODY_COLORS.size()]

# ---------------------------------------------------------------- draw

func _draw() -> void:
	var col := _body_color()
	if _flash > 0.0:
		col = Color.WHITE

	if dead:
		draw_rect(Rect2(-7, -3, 14, 4), Color(0.35, 0.05, 0.08))
		return

	# migotanie podczas niewrażliwości po trafieniu
	if _invuln > 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0:
		col.a = 0.45

	var h := 11.0 if crouching else 17.0
	var top := -h
	draw_rect(Rect2(-7, -1, 14, 3), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-5, top + 7, 10, h - 7), col)
	draw_rect(Rect2(-4, top, 8, 8), col.lightened(0.3))
	var eye_off := Vector2(aim_dir.x * 2.5, clampf(aim_dir.y, -1.0, 0.35) * 2.0)
	draw_rect(Rect2(eye_off.x - 1.0, top + 3.0 + eye_off.y, 2, 2), Color(0.06, 0.06, 0.08))
	var arm_start := Vector2(0, top + 9)
	draw_line(arm_start, arm_start + aim_dir * _gun_len(), Color(0.78, 0.78, 0.85), 2.0 if weapon != Weapons.SPREAD12 else 3.0)

func _gun_len() -> float:
	return 14.0 if weapon == Weapons.SPREAD12 else (9.0 if weapon == Weapons.P64 else 12.0)

## Rzeczy czytelne w ciemności (materiał unshaded): etykieta, HP, rozbłysk,
## stan „DOWN" i pasek podnoszenia.
func _draw_overlay(ov: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var col := _body_color()
	if dead:
		ov.draw_string(font, Vector2(-26, -12), "P%d DOWN %ds" % [display_id, ceili(bleed_left)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.4, 0.4))
		if revive_progress > 0.0:
			ov.draw_rect(Rect2(-12, -22, 24, 4), Color(0.1, 0.1, 0.12))
			ov.draw_rect(Rect2(-12, -22, 24.0 * revive_progress, 4), Color(0.4, 0.95, 0.5))
		return
	var top := -11.0 if crouching else -17.0
	if _muzzle > 0.0:
		ov.draw_circle(Vector2(0, top + 9) + aim_dir * _gun_len(), 3.5, Color(1.0, 0.9, 0.4, 0.9))
	for i in MAX_HP:
		var c := Color(0.92, 0.25, 0.3) if i < hp else Color(0.22, 0.22, 0.26)
		ov.draw_rect(Rect2(-9 + i * 6.0, top - 8.0, 4, 4), c)
	var label := "BOT" if is_bot else "P%d" % display_id
	ov.draw_string(font, Vector2(-18, top - 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
	if is_bot:
		ov.draw_string(font, Vector2(-20, top - 21), "AI", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.5, 0.58))
