extends Node
## Kontroler broni gracza — węzeł „Weapons” pod Player (i botem). Cała logika broni
## poza samym ruchem postaci: zestaw i zmiana, magazynek i przeładowanie, rytm ognia,
## rozgrzanie i rozrzut, ładowanie szyny, promień/płomień, cios, podnoszenie broni.
## Dane bierze z weapons.gd, obrażenia zadaje przez combat.gd, wizualia robi weapon_view.gd.
##
## SIEĆ (GDD §19): właściciel postaci jest autorytetem nad swoim magazynkiem i celowaniem
## (kooperacja — zaufanie jak przy pozycji), a SERWER nad skutkiem strzału:
##   1. strzelec natychmiast gra dźwięk, rozbłysk, odrzut i leci jego KOSMETYCZNA kula
##      (predykcja — brak opóźnienia o RTT),
##   2. wysyła do serwera {wylot, kierunek, broń, seed rozrzutu},
##   3. serwer (po prostej walidacji tempa i miejsca) spawnuje kulę AUTORYTATYWNĄ i liczy
##      trafienia, a pozostałym peerom wysyła kosmetyczne kopie (ten sam seed → ten sam rozrzut).
## Promień i płomień nie mają RPC na tyknięcie: serwer czyta zreplikowane `w_firing`,
## `aim_dir` i pozycję gracza (50 ms) i sam liczy obrażenia.

const Weapons := preload("res://scripts/weapons.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Combat := preload("res://scripts/combat.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Projectile := preload("res://scripts/projectile.gd")

enum State { READY, DRAW, RELOAD, CHARGE, MELEE }

const BUFFER := 0.12              ## s — klik tuż przed końcem cooldownu nie przepada
const MELEE_HIT_AT := 0.45        ## ułamek czasu ciosu, w którym liczymy trafienie
const GRANT_TIMEOUT := 1.5        ## s oczekiwania na naboje z serwera, potem przerwanie
const MUZZLE_TOLERANCE := 40.0    ## px — dalszy wylot niż to serwer koryguje do pozycji gracza
const RATE_CAP := 2.5             ## „zapas” strzałów po lagu sieci (token bucket)
const FX_REPORT_EVERY := 0.2      ## efekt trafienia promieniem/płomieniem nie częściej niż co tyle
const NOISE_RELOAD := 0.25
const NOISE_DRY := 0.12

signal shot(w: int)
signal reload_started(w: int)
signal dry_fired(w: int)
signal weapon_changed(w: int)
signal melee_swung(w: int)

var player: CharacterBody2D

# --- zestaw (właściciel; `kit` w graczu replikuje go reszcie)
var loadout: Array[int] = [Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_SIDEARM]
var melee_id := Weapons.START_MELEE
var slot := 0
var mags: Dictionary = {}

# --- stan
var state: int = State.READY
var state_t := 0.0
var charge := 0.0                 ## 0..1 (szyna)
var firing := false               ## promień/płomień w toku
var bloom := 0.0                  ## ° dodatkowego rozrzutu od serii
var recoil := 0.0                 ## 0..1 — wizualne cofnięcie broni (widok)
var cd := 0.0
var melee_total := 0.35
var ammo_enabled := true          ## boty mają nieskończoną amunicję

## Hooki testów headless (--weapontest): symulowany spust. W grze zawsze false.
var sim_fire := false
var sim_press := false
## Licznik strzałów przyjętych przez serwer (test limitu tempa).
var srv_shots := 0

var _heat: Dictionary = {}
var _buf_t := 0.0
var _dry_latch := false
var _rl_total := 0.0
var _rl_left := 0.0
var _rl_req := false
var _rl_pending := 0
var _rl_wait := 0.0
var _melee_pending := false
var _cycle_t := -1.0              ## s do dźwięku/łuski po strzale (pompka)
var _cycle_w := 0
var _cycle_muzzle := Vector2.ZERO
var _cycle_dir := Vector2.RIGHT
var _srv_tokens := 1.5
var _srv_last_ms := 0
var _srv_tick := 0.0
var _srv_fx_t := 0.0
var _prev_w := -1

func _ready() -> void:
	player = get_parent() as CharacterBody2D
	Arsenal.rounds_granted.connect(_on_rounds_granted)
	reset()

# ---------------------------------------------------------------- dostęp

func cur() -> WeaponDef:
	return Weapons.def(loadout[slot])

func def_of_slot(i: int) -> WeaponDef:
	return Weapons.def(loadout[i])

func mag_of(w: int) -> int:
	return int(mags.get(w, 0))

func heat_of(w: int) -> float:
	return float(_heat.get(w, 0.0))

func carries(w: int) -> bool:
	return loadout.has(w) or w == melee_id

func primaries() -> Array:
	return [loadout[0], loadout[1]]

func is_owner() -> bool:
	if player == null:
		return false
	if player.is_bot:
		return NoiseMgr.is_server()
	return player.is_multiplayer_authority()

func is_reloading() -> bool:
	return state == State.RELOAD

## Postęp przeładowania 0..1 (HUD, widok).
func reload_progress() -> float:
	if state != State.RELOAD or _rl_total <= 0.0:
		return 0.0
	return clampf(1.0 - _rl_left / _rl_total, 0.0, 1.0)

func kit() -> Vector3i:
	return Vector3i(loadout[0], loadout[1], melee_id)

## Rozrzut dokładany do bazowego: seria (bloom), bieg, kucanie.
func spread_extra(d: WeaponDef) -> float:
	var e := bloom
	if absf(player.velocity.x) > 60.0 and player.is_on_floor():
		e += 0.8
	if player.crouching:
		e *= float(d.crouch_accuracy)
	return e

## Wylot lufy w świecie: dłoń (jak w widoku broni) + długość lufy wzdłuż celowania.
## Lufa nie wychodzi za ścianę: gdy między dłonią a wylotem jest przeszkoda, wylot stoi tuż przed nią
## (długa broń nie strzela przez cienką ścianę, gdy stoisz przy niej).
func muzzle_pos(dir: Vector2, d: WeaponDef) -> Vector2:
	var side := signf(dir.x) if absf(dir.x) > 0.1 else 1.0
	var hand := player.global_position + Vector2(side, -8.0 if player.crouching else -12.0)
	var tip := hand + dir * d.gun_len
	if not player.is_inside_tree():
		return tip
	var q := PhysicsRayQueryParameters2D.create(hand, tip, Combat.LAYER_WORLD)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"] - dir * 1.0
	return tip

# ---------------------------------------------------------------- reset / zestaw

## Pełny reset (spawn, restart misji): zestaw startowy, pełne magazynki, zimne lufy.
func reset() -> void:
	loadout = [Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_SIDEARM]
	if player != null and player.is_bot:
		loadout = [Weapons.M83, Weapons.M83, Weapons.P64]
		ammo_enabled = false
	melee_id = Weapons.START_MELEE
	slot = 0
	mags.clear()
	for w in loadout:
		mags[w] = Weapons.def(w).mag
	_heat.clear()
	bloom = 0.0
	recoil = 0.0
	cd = 0.0
	charge = 0.0
	firing = false
	state = State.READY
	state_t = 0.0
	_rl_req = false
	_rl_pending = 0
	_melee_pending = false
	_buf_t = 0.0
	_sync_player()

## Gracz padł (down): przerwij wszystko — w tym ciągły ogień, żeby nie palił po śmierci.
func on_down() -> void:
	_cancel_actions()
	firing = false
	_sync_player()

## Zimne lufy i zerowy rozrzut (po wykrwawieniu, bez utraty zestawu).
func cool() -> void:
	_heat.clear()
	bloom = 0.0
	cd = 0.0

func _sync_player() -> void:
	if player == null:
		return
	player.weapon = loadout[slot]
	player.w_state = state
	player.w_charge = charge
	player.w_firing = firing
	player.kit = kit()
	if _prev_w != player.weapon:
		_prev_w = player.weapon
		weapon_changed.emit(player.weapon)

# ---------------------------------------------------------------- tyknięcie właściciela

## Wołane z player.gd co klatkę fizyki (człowiek, żywy). `reviving` blokuje strzał.
func tick_local(delta: float, reviving: bool) -> void:
	_tick_common(delta)
	if reviving:
		_cancel_actions()
		_sync_player()
		return
	_handle_switch_input()
	if Input.is_action_just_pressed("interact"):
		_try_pickup()
	if Input.is_action_just_pressed("melee"):
		try_melee()
	if Input.is_action_just_pressed("reload"):
		try_reload()
	var held := Input.is_action_pressed("fire") or sim_fire
	var pressed := Input.is_action_just_pressed("fire") or sim_press
	sim_press = false
	_handle_fire(held, pressed, delta)
	_sync_player()

## Bot: tylko liczniki; strzela przez bot_fire().
func tick_bot(delta: float) -> void:
	_tick_common(delta)
	_sync_player()

func _tick_common(delta: float) -> void:
	for w in _heat.keys():
		_heat[w] = maxf(0.0, float(_heat[w]) - Weapons.def(w).heat_decay * delta)
	bloom = maxf(0.0, bloom - cur().bloom_decay * delta)
	recoil = maxf(0.0, recoil - delta * 9.0)
	cd = maxf(cd - delta, -delta)
	_buf_t = maxf(0.0, _buf_t - delta)
	if _cycle_t >= 0.0:
		_cycle_t -= delta
		if _cycle_t < 0.0:
			_cycle_t = -1.0
			_cycle_fx()
	match state:
		State.DRAW:
			state_t -= delta
			if state_t <= 0.0:
				state = State.READY
				_auto_reload_if_empty()
		State.MELEE:
			state_t -= delta
			if _melee_pending and state_t <= melee_total * (1.0 - MELEE_HIT_AT):
				_melee_pending = false
				_melee_resolve()
			if state_t <= 0.0:
				state = State.READY
		State.RELOAD:
			_tick_reload(delta)

func _cancel_actions() -> void:
	if state == State.RELOAD:
		_cancel_reload()
	if state == State.CHARGE:
		_cancel_charge()
	if state == State.MELEE:
		state = State.READY
	firing = false

# ---------------------------------------------------------------- zmiana broni

func _handle_switch_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		select_slot(0)
	elif Input.is_action_just_pressed("weapon_2"):
		select_slot(1)
	elif Input.is_action_just_pressed("weapon_3"):
		select_slot(2)
	elif Input.is_action_just_pressed("weapon_next"):
		select_slot((slot + 1) % 3)
	elif Input.is_action_just_pressed("weapon_prev"):
		select_slot((slot + 2) % 3)

func select_slot(i: int) -> void:
	if i == slot or i < 0 or i > 2:
		return
	_cancel_actions()
	slot = i
	var d := cur()
	state = State.DRAW
	state_t = d.draw_time
	cd = maxf(cd, 0.0)
	_dry_latch = false
	Audio.play_variant("foley_gear", 3, Audio.BUS_PLAYER, -14.0, 1.0 + 0.1 * float(i))
	if not player.is_bot:
		Audio.play("ui_click", Audio.BUS_UI, -14.0, 1.2)
	_sync_player()

## Pusty magazynek po zmianie broni → od razu przeładowanie (nikt nie chce celować kliknięciem).
func _auto_reload_if_empty() -> void:
	var d := cur()
	if ammo_enabled and d.uses_ammo() and mag_of(d.id) <= 0:
		try_reload(true)

# ---------------------------------------------------------------- ogień

func _handle_fire(held: bool, pressed: bool, delta: float) -> void:
	var d := cur()
	if pressed:
		_buf_t = BUFFER
	if not held:
		_dry_latch = false
	match d.kind:
		WeaponDef.Kind.BEAM, WeaponDef.Kind.FLAME:
			_handle_continuous(d, held)
		WeaponDef.Kind.RAIL:
			_handle_rail(d, held, delta)
		_:
			_handle_shot(d, held)

func _has_ammo(d: WeaponDef) -> bool:
	return not ammo_enabled or not d.uses_ammo() or mag_of(d.id) >= d.ammo_per_shot

func _handle_shot(d: WeaponDef, held: bool) -> void:
	var want := held if d.auto else _buf_t > 0.0
	if not want:
		return
	# strzelbę/granatnik ładowane po jednym naboju można przerwać strzałem
	if state == State.RELOAD and d.reload_per_round and mag_of(d.id) > 0:
		_cancel_reload()
	if state != State.READY or cd > 0.0:
		return
	if not _has_ammo(d):
		_dry_fire(d)
		return
	_buf_t = 0.0
	_fire_shot(d)

func _dry_fire(d: WeaponDef) -> void:
	if _dry_latch:
		return
	_dry_latch = true
	Audio.play("dry_fire", Audio.BUS_WEAPONS, -8.0, 1.0)
	NoiseMgr.add_noise(NOISE_DRY, player.global_position)
	dry_fired.emit(d.id)
	_buf_t = 0.0
	try_reload(true)

func _handle_continuous(d: WeaponDef, held: bool) -> void:
	if not held or state != State.READY:
		firing = false
		return
	if not _has_ammo(d):
		firing = false
		_dry_fire(d)
		return
	if not firing:
		firing = true
		Audio.play_variant(d.sfx, d.sfx_count, Audio.BUS_WEAPONS, d.sfx_vol, d.sfx_pitch)
		cd = minf(cd, 0.0)
	if cd <= 0.0:
		cd += d.cooldown
		if ammo_enabled:
			mags[d.id] = mag_of(d.id) - d.ammo_per_shot
		NoiseMgr.add_noise(d.noise(0.0), player.global_position)
		recoil = maxf(recoil, 0.25)
		Feel.shake(d.shake)
		shot.emit(d.id)

func _handle_rail(d: WeaponDef, held: bool, delta: float) -> void:
	if state == State.READY and held and cd <= 0.0:
		if not _has_ammo(d):
			_dry_fire(d)
			return
		state = State.CHARGE
		charge = 0.0
		Audio.stop_loop(d.sfx_loop)
		Audio.start_loop(d.sfx_loop, Audio.BUS_WEAPONS, d.sfx_vol - 6.0, 1.0)
	if state != State.CHARGE:
		return
	if held:
		charge = minf(1.0, charge + delta / d.charge_time)
		Feel.shake(0.15 + 0.5 * charge * charge)
	elif charge >= 1.0:
		_fire_shot(d)
	else:
		_cancel_charge()

func _cancel_charge() -> void:
	var d := cur()
	if d.sfx_loop != "":
		Audio.stop_loop(d.sfx_loop)
	charge = 0.0
	if state == State.CHARGE:
		state = State.READY

## Jeden strzał pociskiem / granatem / szyną: koszt, rozgrzanie, hałas, efekty własne, wysyłka.
func _fire_shot(d: WeaponDef) -> void:
	var dir: Vector2 = player.aim_dir
	var muzzle := muzzle_pos(dir, d)
	var extra := spread_extra(d)
	var seed := randi()
	if ammo_enabled and d.uses_ammo():
		mags[d.id] = mag_of(d.id) - d.ammo_per_shot
	var heat := heat_of(d.id)
	NoiseMgr.add_noise(d.noise(heat), player.global_position)
	_heat[d.id] = minf(1.0, heat + d.heat_gain)
	bloom = minf(bloom + d.bloom_per_shot, d.bloom_max)
	cd += d.cooldown
	if d.kind == WeaponDef.Kind.RAIL:
		Audio.stop_loop(d.sfx_loop)
		charge = 0.0
		state = State.READY
	_own_shot_fx(d, muzzle, dir)
	if NoiseMgr.is_server():
		_server_fire(muzzle, dir, d.id, seed, extra, player.player_id, true)
	else:
		_predict(d, muzzle, dir, seed, extra)
		_fire_request.rpc_id(1, muzzle, dir, d.id, seed, extra)
	shot.emit(d.id)
	if d.sfx_cycle != "":
		_schedule_cycle(d, muzzle, dir)

## Strzał bota: M-83 bez kosztu amunicji, tempo ×1,8 (dyscyplina ognia w player.gd).
func bot_fire(dir: Vector2) -> bool:
	var d := Weapons.def(Weapons.M83)
	if cd > 0.0 or state != State.READY:
		return false
	var muzzle := muzzle_pos(dir, d)
	var seed := randi()
	var heat := heat_of(d.id)
	NoiseMgr.add_noise(d.noise(heat), player.global_position)
	_heat[d.id] = minf(1.0, heat + d.heat_gain)
	cd += d.cooldown * 1.8
	recoil = maxf(recoil, 0.6)
	player.weapon = d.id
	_server_fire(muzzle, dir, d.id, seed, 0.0, player.player_id, false)
	shot.emit(d.id)
	return true

# ---------------------------------------------------------------- strzał: efekty

## Efekty strzelca (jego własny peer): dźwięk niepozycyjny, rozbłysk, kamera, odrzut, łuska.
func _own_shot_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	recoil = 1.0
	Audio.play_variant(d.sfx, d.sfx_count, Audio.BUS_WEAPONS, d.sfx_vol, d.sfx_pitch)
	Feel.shake(d.shake)
	if d.cam_kick > 0.0:
		Feel.kick(-dir * d.cam_kick)
	if d.kick > 0.0:
		player.apply_recoil_kick(-dir.x * d.kick)
	_cosmetic_fx(d, muzzle, dir, d.sfx_cycle == "")

## Efekty cudzego strzału (inny człowiek, bot): pozycyjny dźwięk + rozbłysk + łuska.
func _remote_shot_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	Audio.play_variant_at(d.sfx, d.sfx_count, muzzle, Audio.BUS_WEAPONS, d.sfx_vol - 3.0, d.sfx_pitch)
	recoil = 1.0
	_cosmetic_fx(d, muzzle, dir, d.sfx_cycle == "")
	shot.emit(d.id)
	if d.sfx_cycle != "":
		_schedule_cycle(d, muzzle, dir)

func _cosmetic_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2, eject_now: bool) -> void:
	var parent: Node = player._fx_root()
	if eject_now and d.casing > 0:
		Vfx.casing(parent, muzzle - dir * 6.0, dir, d.casing >= 2)
	Vfx.smoke(parent, muzzle, dir)

func _schedule_cycle(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	_cycle_t = 0.38
	_cycle_w = d.id
	_cycle_muzzle = muzzle
	_cycle_dir = dir

## Pompka / zamek po strzale: dźwięk i wyrzut łuski (strzelba wyrzuca ją dopiero tu).
func _cycle_fx() -> void:
	var d := Weapons.def(_cycle_w)
	if d.sfx_cycle != "":
		if is_owner():
			Audio.play_variant(d.sfx_cycle, d.sfx_cycle_count, Audio.BUS_WEAPONS, d.sfx_vol - 5.0, 1.0)
		else:
			Audio.play_variant_at(d.sfx_cycle, d.sfx_cycle_count, _cycle_muzzle, Audio.BUS_WEAPONS, d.sfx_vol - 8.0, 1.0)
	if d.casing > 0:
		Vfx.casing(player._fx_root(), player.global_position + Vector2(0, -9), _cycle_dir, d.casing >= 2)

# ---------------------------------------------------------------- strzał: serwer i sieć

## Strzelec-klient: kosmetyczne kopie pocisków od razu (predykcja).
func _predict(d: WeaponDef, muzzle: Vector2, dir: Vector2, seed: int, extra: float) -> void:
	match d.kind:
		WeaponDef.Kind.RAIL:
			var tr := Combat.trace(player.get_world_2d().direct_space_state, muzzle, dir, d.range_px, int(d.pierce), d.wall_pierce, [player.get_rid()])
			_rail_visual(d, muzzle, tr["end"], tr)
		_:
			_spawn_projectiles(d, muzzle, dir, seed, extra, player.player_id, false)

func _spawn_projectiles(d: WeaponDef, muzzle: Vector2, dir: Vector2, seed: int, extra: float, shooter: int, auth: bool, lag := 0.0) -> void:
	var scene := get_tree().current_scene
	for dd in Weapons.pellet_dirs(d, dir, seed, extra):
		var p := Projectile.new()
		p.launch(d.id, muzzle, dd, shooter, auth, lag)
		scene.add_child(p)

## Serwer: waliduje (tempo, wylot) i wykonuje strzał; resztę peerów informuje o kosmetyce.
@rpc("any_peer", "call_remote", "reliable")
func _fire_request(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if multiplayer.get_remote_sender_id() != player.player_id or not Weapons.is_valid(w):
		return
	var d := Weapons.def(w)
	if d.is_melee() or d.is_continuous():
		return
	# tempo: token bucket — lag może skumulować kilka strzałów, ale nie więcej niż RATE_CAP
	var now := Time.get_ticks_msec()
	_srv_tokens = minf(RATE_CAP, _srv_tokens + float(now - _srv_last_ms) / (maxf(d.cooldown, 0.05) * 1000.0))
	_srv_last_ms = now
	if _srv_tokens < 1.0:
		return
	_srv_tokens -= 1.0
	var expect := muzzle_pos(dir.normalized(), d)
	if muzzle.distance_to(expect) > MUZZLE_TOLERANCE:
		muzzle = expect
	# kompensacja opóźnienia: serwer sam mierzy RTT strzelca (lag_comp.gd), klient niczego nie deklaruje
	var lag := LagComp.rewind_for(player.player_id)
	_server_fire(muzzle, dir.normalized(), w, seed, clampf(extra, 0.0, 12.0), player.player_id, false, lag)

## Autorytatywny strzał (serwer). `own_fx_done` = strzelec (host) już zagrał swoje efekty.
func _server_fire(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float, shooter: int, own_fx_done: bool, lag := 0.0) -> void:
	var d := Weapons.def(w)
	srv_shots += 1
	match d.kind:
		WeaponDef.Kind.RAIL:
			_server_rail(d, muzzle, dir, shooter, lag)
		_:
			_spawn_projectiles(d, muzzle, dir, seed, extra, shooter, true, lag)
	if not own_fx_done:
		_remote_shot_fx(d, muzzle, dir)
	if NoiseMgr.has_network():
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_fire_remote.rpc_id(peer, muzzle, dir, w, seed, extra, shooter)

## Kosmetyka cudzego strzału u klientów (serwer wywołuje na węźle należącym do KLIENTA).
@rpc("any_peer", "call_remote", "unreliable")
func _fire_remote(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float, shooter: int) -> void:
	if NoiseMgr.is_server() or multiplayer.get_remote_sender_id() != 1 or not Weapons.is_valid(w):
		return
	var d := Weapons.def(w)
	if d.kind != WeaponDef.Kind.RAIL:
		_spawn_projectiles(d, muzzle, dir, seed, extra, shooter, false)
	_remote_shot_fx(d, muzzle, dir)

## Szyna: trafienie natychmiastowe, przebija wszystkich (i opcjonalnie cienką ścianę).
## Serwer rysuje tor u siebie; strzelec-klient narysował go sam w predykcji, reszta dostaje RPC.
func _server_rail(d: WeaponDef, muzzle: Vector2, dir: Vector2, shooter: int, lag := 0.0) -> void:
	var space := player.get_world_2d().direct_space_state
	# lag > 0: trafiamy wrogów w pozycjach sprzed `lag` s (szyna jest natychmiastowa — jeden test w przeszłość)
	var tr := Combat.trace(space, muzzle, dir, d.range_px, int(d.pierce), d.wall_pierce, [player.get_rid()], LagComp.now() - lag if lag > 0.0 else -1.0)
	for h in tr["hits"]:
		var info := Combat.make_info(d.id, d.damage, h["pos"], dir, shooter, "rail")
		info["heavy"] = true
		Combat.apply_and_report(h["collider"], info)
	_rail_visual(d, muzzle, tr["end"], tr)
	if NoiseMgr.has_network():
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_tracer_remote.rpc_id(peer, muzzle, tr["end"], d.id, tr["wall"], tr["wall_normal"])

@rpc("any_peer", "call_remote", "unreliable")
func _tracer_remote(from: Vector2, to: Vector2, w: int, wall: bool, normal: Vector2) -> void:
	if NoiseMgr.is_server() or multiplayer.get_remote_sender_id() != 1 or not Weapons.is_valid(w):
		return
	_rail_visual(Weapons.def(w), from, to, {"wall": wall, "wall_normal": normal})

func _rail_visual(d: WeaponDef, from: Vector2, to: Vector2, tr: Dictionary) -> void:
	var parent: Node = player._fx_root()
	Vfx.streak(parent, from, to, d.tracer_color, 2.0, 0.22)
	if bool(tr.get("wall", false)):
		var lvl := get_tree().get_first_node_in_group("level")
		var surface := "metal"
		if lvl != null:
			surface = lvl.surface_at_hit(to, tr["wall_normal"])
		Vfx.impact(parent, to, tr["wall_normal"], surface, true)

# ---------------------------------------------------------------- ciągły ogień (serwer)

func _physics_process(delta: float) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if not player.w_firing:
		_srv_tick = 0.0
		return
	var d := Weapons.def(player.weapon)
	if not d.is_continuous():
		return
	_srv_tick -= delta
	_srv_fx_t -= delta
	if _srv_tick > 0.0:
		return
	_srv_tick += d.cooldown
	if _srv_tick < 0.0:
		_srv_tick = 0.0
	var origin := player.global_position + Vector2(0, -9)
	var dir: Vector2 = player.aim_dir
	var space := player.get_world_2d().direct_space_state
	var report := _srv_fx_t <= 0.0
	if report:
		_srv_fx_t = FX_REPORT_EVERY
	if d.kind == WeaponDef.Kind.BEAM:
		var tr := Combat.trace(space, origin + dir * 6.0, dir, d.range_px, int(d.pierce), 0.0, [player.get_rid()])
		for h in tr["hits"]:
			_continuous_hit(d, h["collider"], h["pos"], dir, "beam", report)
	else:
		for t in Combat.in_cone(get_tree(), space, origin + dir * 4.0, dir, d.range_px, d.arc_deg):
			var c := Combat.center_of(t)
			var dist := c.distance_to(origin)
			var info_amount := d.damage * d.falloff(dist)
			_continuous_hit(d, t, c, dir, "fire", report, info_amount)

func _continuous_hit(d: WeaponDef, target: Node, pos: Vector2, dir: Vector2, type: String, report: bool, amount := -1.0) -> void:
	var info := Combat.make_info(d.id, d.damage if amount < 0.0 else amount, pos, dir, player.player_id, type)
	info["heavy"] = false
	var res := Combat.apply(target, info)
	if report:
		Combat.report(info, res)

# ---------------------------------------------------------------- przeładowanie

func try_reload(auto := false) -> bool:
	var d := cur()
	if not d.uses_ammo() or state != State.READY:
		return false
	if mag_of(d.id) >= d.mag:
		return false
	if not d.infinite and Arsenal.get_reserve(d.id) <= 0 and ammo_enabled:
		if not auto:
			Audio.play("dry_fire", Audio.BUS_WEAPONS, -10.0, 0.8)
		return false
	firing = false
	state = State.RELOAD
	_rl_req = false
	_rl_pending = 0
	_rl_wait = 0.0
	if d.reload_per_round:
		_begin_round(d)
	else:
		_rl_total = d.reload_time + (d.reload_empty_extra if mag_of(d.id) <= 0 else 0.0)
		_rl_left = _rl_total
		_reload_sfx(d)
	NoiseMgr.add_noise(NOISE_RELOAD, player.global_position)
	reload_started.emit(d.id)
	return true

func _reload_sfx(d: WeaponDef) -> void:
	if d.reload_sfx == "":
		return
	if is_owner():
		Audio.play_variant(d.reload_sfx, d.reload_sfx_count, Audio.BUS_WEAPONS, -8.0, 1.0)

func _begin_round(d: WeaponDef) -> void:
	_rl_total = d.reload_time
	_rl_left = _rl_total
	_rl_wait = 0.0
	_rl_req = true
	if d.infinite:
		_rl_req = false
		_rl_pending += 1
	else:
		Arsenal.request_rounds(d.id, 1)
	_reload_sfx(d)

func _tick_reload(delta: float) -> void:
	var d := cur()
	if _rl_req and _rl_left <= 0.0:
		_rl_wait += delta
		if _rl_wait > GRANT_TIMEOUT:
			_cancel_reload()
		return
	_rl_left -= delta
	if _rl_left > 0.0:
		return
	if d.reload_per_round:
		if _rl_pending > 0:
			_rl_pending -= 1
			mags[d.id] = mini(d.mag, mag_of(d.id) + 1)
		if mag_of(d.id) < d.mag and (_rl_req or _rl_pending > 0 or d.infinite or Arsenal.get_reserve(d.id) > 0):
			_begin_round(d)
		elif not _rl_req:
			_finish_reload()
		return
	if not _rl_req:
		_rl_req = true
		_rl_wait = 0.0
		var want := d.mag - mag_of(d.id)
		if d.infinite or not ammo_enabled:
			_on_rounds_granted(d.id, want)
		else:
			Arsenal.request_rounds(d.id, want)

func _finish_reload() -> void:
	state = State.READY
	_rl_req = false
	_rl_pending = 0
	_rl_left = 0.0

func _cancel_reload() -> void:
	var d := cur()
	# naboje już przyznane, a jeszcze niewsunięte (strzelba), lądują w magazynku
	if _rl_pending > 0:
		mags[d.id] = mini(d.mag, mag_of(d.id) + _rl_pending)
	_finish_reload()

func _on_rounds_granted(w: int, n: int) -> void:
	if player == null or not is_owner() or player.is_bot:
		return
	var d := Weapons.def(w)
	var reloading := state == State.RELOAD and cur().id == w
	if reloading and not d.reload_per_round:
		mags[w] = mini(d.mag, mag_of(w) + n)
		_finish_reload()
		return
	if reloading and d.reload_per_round:
		_rl_req = false
		_rl_pending += n
		return
	# przeładowanie przerwane, zanim przyszła odpowiedź — wsuń do magazynka, nadmiar oddaj
	if n > 0 and loadout.has(w):
		var room := d.mag - mag_of(w)
		var put := mini(room, n)
		mags[w] = mag_of(w) + put
		if n > put:
			Arsenal.deposit(w, n - put)
	elif n > 0:
		Arsenal.deposit(w, n)

# ---------------------------------------------------------------- broń biała

func try_melee() -> void:
	if player.dead or state == State.MELEE:
		return
	var md := Weapons.def(melee_id)
	_cancel_actions()
	state = State.MELEE
	melee_total = md.cooldown
	state_t = md.cooldown
	_melee_pending = true
	cd = maxf(cd, 0.2)
	NoiseMgr.add_noise(md.noise(0.0), player.global_position)
	Audio.play_variant(md.sfx, md.sfx_count, Audio.BUS_WEAPONS, md.sfx_vol, 1.0)
	Feel.shake(md.shake * 0.5)
	melee_swung.emit(melee_id)

func _melee_resolve() -> void:
	var origin := player.global_position + Vector2(0, -9)
	var dir: Vector2 = player.aim_dir
	if NoiseMgr.is_server():
		_server_melee(origin, dir, melee_id, player.player_id)
	else:
		_melee_request.rpc_id(1, origin, dir, melee_id)

@rpc("any_peer", "call_remote", "reliable")
func _melee_request(origin: Vector2, dir: Vector2, w: int) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if multiplayer.get_remote_sender_id() != player.player_id or not Weapons.is_valid(w) or not Weapons.def(w).is_melee():
		return
	var expect := player.global_position + Vector2(0, -9)
	if origin.distance_to(expect) > MUZZLE_TOLERANCE:
		origin = expect
	_server_melee(origin, dir.normalized(), w, player.player_id)

func _server_melee(origin: Vector2, dir: Vector2, w: int, shooter: int) -> void:
	var d := Weapons.def(w)
	var space := player.get_world_2d().direct_space_state
	var hit_any := false
	for t in Combat.in_cone(get_tree(), space, origin, dir, d.reach, d.arc_deg):
		var c := Combat.center_of(t)
		var info := Combat.make_info(w, d.damage, c, dir, shooter, "melee")
		info["backstab"] = d.key == "maczeta"
		info["heavy"] = d.damage >= 50.0
		var res := Combat.apply(t, info)
		Combat.report(info, res)
		hit_any = hit_any or bool(res["hit"])
	if not hit_any:
		var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * d.reach, Combat.LAYER_WORLD)
		var wall := space.intersect_ray(q)
		if not wall.is_empty():
			Arsenal.broadcast_hit(wall["position"], -dir, Arsenal.Mat.METAL, false, d.damage >= 50.0)
	if NoiseMgr.has_network():
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_melee_remote.rpc_id(peer, origin, dir, w)
	if shooter != NoiseMgr.local_id() or player.is_bot:
		_remote_melee_fx(d, origin)

@rpc("any_peer", "call_remote", "unreliable")
func _melee_remote(origin: Vector2, _dir: Vector2, w: int) -> void:
	if NoiseMgr.is_server() or multiplayer.get_remote_sender_id() != 1 or not Weapons.is_valid(w):
		return
	_remote_melee_fx(Weapons.def(w), origin)

func _remote_melee_fx(d: WeaponDef, origin: Vector2) -> void:
	Audio.play_variant_at(d.sfx, d.sfx_count, origin, Audio.BUS_WEAPONS, d.sfx_vol - 2.0, 1.0)
	melee_swung.emit(d.id)

# ---------------------------------------------------------------- podnoszenie i zamiana broni

func nearby_weapon_item() -> Node2D:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or player == null:
		return null
	return lvl.weapon_item_near(player.global_position + Vector2(0, -8))

func _try_pickup() -> void:
	var it := nearby_weapon_item()
	if it == null:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl.is_locked_item(it):
		Audio.play("ui_click", Audio.BUS_UI, -14.0)         # zablokowany stojak: najpierw kup w warsztacie
		return
	lvl.request_weapon_pickup(it.name)

## Serwer przyznał broń (po sprawdzeniu odległości). Zastępuje bieżącą główną, jeśli nie masz
## już tej samej; porzucona broń leży pod stopami, jej magazynek wraca do wspólnego zapasu.
@rpc("any_peer", "call_remote", "reliable")
func grant_weapon(w: int) -> void:
	var sender := multiplayer.get_remote_sender_id() if NoiseMgr.has_network() else 0
	if sender != 0 and sender != 1:
		return
	if not Weapons.is_valid(w):
		return
	var d := Weapons.def(w)
	if carries(w):
		return          # znana broń: naboje już poszły do zapasu (level.gd)
	if d.slot == Weapons.Slot.MELEE:
		var old_m := melee_id
		melee_id = w
		_drop(old_m)
		_sync_player()
		return
	if d.slot != Weapons.Slot.PRIMARY:
		return
	var target := slot if slot < 2 else 0
	var old := loadout[target]
	_cancel_actions()
	if mag_of(old) > 0:
		Arsenal.deposit(old, mag_of(old))
	mags.erase(old)
	loadout[target] = w
	mags[w] = 0
	_drop(old)
	if target == slot:
		state = State.DRAW
		state_t = d.draw_time
	Audio.play("weapon_pickup", Audio.BUS_UI, -8.0)
	_sync_player()          # pusty magazynek nowej broni ładuje się sam po dobyciu

func _drop(old: int) -> void:
	if Weapons.def(old).infinite and Weapons.def(old).slot == Weapons.Slot.SIDEARM:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		lvl.request_drop(old, player.global_position + Vector2(0, -4))
