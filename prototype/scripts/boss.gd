extends CharacterBody2D
## Żyła — matka gniazd. Boss misji „Gniazdo" (GDD §7.1 Żyła: splot, rodzi
## Trzoski; §16.0 pkt 1: demo = misja w całości z bossem).
##
## Gniazda są jej odnóżami: dopóki choć jedno żyje, Żyła śpi i jest
## nietykalna. Zniszczenie ostatniego budzi ją; jej śmierć otwiera ekstrakcję.
##
## Walka (1.3.9 — wcześniej ~4 s z ziemi, bez użycia filarów gry):
##   RYTM       paszcza jest zamknięta (5% obrażeń); otwiera się na MAW_WINDOW
##              po każdym ataku — unik → okno → ostrzał (otwarta ~40% czasu;
##              symulacja 1.3.9: przy 1,3 s okna i 1,1 s przerwy była otwarta
##              ~2/3 czasu i walka trwała 11 s)
##   LATARKA    snop w paszczę W TRAKCIE ZAPOWIEDZI ataku oślepia ją: atak
##              przerwany, paszcza otwarta STUN_TIME (filar 4, kooperacja: jeden
##              świeci w dobrym momencie, drugi strzela). Poza zapowiedzią nie
##              działa — inaczej stale włączona latarka ogłuszała automatycznie
##   Q          Przesterowanie w pobliżu odciąga ją na DIVERT_TIME: pluje w miejsce
##              Q zamiast w graczy, nie smaga, nie zamiata (filar 2)
##   ATAKI      macka (blisko), zamach ogonem po ziemi (przeskocz albo stań na
##              kładce), plucie zarodnikami (dalej / wyżej) — każdy z zapowiedzią
##   FAZY       66%: furia (szybciej); 33%: krzyk — Uwaga 100%, światła migoczą,
##              budzi się Stalker (kulminacja grozy przed ekstrakcją)
##   GRZBIET    pocisk z góry pod stromym kątem zawsze 5% (kampienie z półek)
##
## Symulacja TYLKO na serwerze; klienci dostają stan przez _sync i _event.

signal died

const Lights := preload("res://scripts/lights.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Vfx := preload("res://scripts/vfx.gd")

enum State { DORMANT, AWAKE, DEAD }
enum Atk { NONE, LASH, SPIT, SWEEP }

const BASE_HP := 750.0
const HP_PER_EXTRA_HUMAN := 250.0
const CLOSED_MULT := 0.05         ## zamknięta paszcza / pancerny grzbiet
const ARMOR_DOWN := 0.45          ## pocisk „z góry": składowa pionowa kierunku > tego
const MAW_WINDOW := 1.0           ## paszcza otwarta po ataku
const STUN_TIME := 2.0            ## oślepienie latarką
const STUN_CD := 10.0
const ATK_GAP := 2.0              ## przerwa między atakami (faza 1)
const ATK_GAP_ENRAGED := 1.5

const LASH_RANGE_X := 64.0
const LASH_RANGE_Y := 70.0
const LASH_WINDUP := 0.75
const LASH_CD := 2.6
const SPIT_RANGE := 300.0
const SPIT_WINDUP := 0.8
const SPIT_CD := 3.4
const SPIT_GRAVITY := 520.0
const SPIT_HIT_R := 11.0
const SWEEP_RANGE := 170.0
const SWEEP_WINDUP := 0.9
const SWEEP_CD := 6.0
const SWEEP_SPEED := 260.0
const SWEEP_HALF := 10.0          ## grubość fali
const DIVERT_TIME := 5.0
const DIVERT_RANGE := 520.0
const ENRAGED_CD := 0.75          ## mnożnik cooldownów w furii

const BROOD_EVERY := 7.0
const BROOD_EVERY_ENRAGED := 5.0
const BROOD_MAX := 3              ## żyjącego potomstwa naraz (+1 za dodatkowego człowieka)
const N_SCREAM := 15.0            ## przebudzenie: krzyk słychać w całym tartaku
const N_STUN := 4.0
const N_SPLASH := 2.0
const N_DEATH := 20.0

var state: int = State.DORMANT
var hp := BASE_HP
var max_hp := BASE_HP
var phase := 1                    ## 1 / 2 (furia, <66%) / 3 (krzyk, <33%)
var atk: int = Atk.NONE           ## trwająca zapowiedź ataku (synchronizowane)
var maw_open := false
var stunned := false
var nests_left := 3
## zgodność z wcześniejszymi testami / rysowaniem
var winding := false
var spitting := false
var enraged := false

var _atk_t := 0.0
var _atk_gap := 0.0
var _lash_cd := 0.0
var _spit_cd := 0.0
var _sweep_cd := 0.0
var _maw_t := 0.0
var _stun_cd := 0.0
var _light_check := 0.0
var _spit_target := Vector2.ZERO
var _spits: Array[Dictionary] = []    ## serwer: {pos, vel}
var _wave_r := -1.0                   ## serwer: promień fali ogona (<0 = brak)
var _wave_hit := {}
var _wave_start_ms := -1              ## każdy peer: rysowanie fali
var _brood_t := 0.0
var _brood_serial := 0
var _brood: Array[Node] = []
var _flash := 0.0
var _flinch := 0.0
var _net_t := 0.0
var _armor_snd_ms := 0
var _light: PointLight2D
var _overlay: Node2D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	nests_left = _nest_count()
	_light = Lights.make_light(Lights.radial(), 3.5, Color(1.0, 0.35, 0.25), 0.5, false)
	_light.position = Vector2(0, -20)
	add_child(_light)
	_overlay = Lights.add_overlay(self)

func is_threat() -> bool:
	return state == State.AWAKE

func is_alive() -> bool:
	return state != State.DEAD

# ---------------------------------------------------------------- misja (serwer)

## Liczba gniazd na mapie (tyle żył świeci, dopóki Żyła śpi).
func _nest_count() -> int:
	return maxi(1, get_tree().get_nodes_in_group("nests").size())

func on_nest_lost(left: int) -> void:
	nests_left = left
	_flinch = 0.6
	Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.6)
	_send_state(true)

func awaken() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	max_hp = (BASE_HP + HP_PER_EXTRA_HUMAN * maxi(0, _humans() - 1)) * Difficulty.m("boss_hp")
	hp = max_hp
	state = State.AWAKE
	phase = 1
	_atk_gap = 1.5
	_lash_cd = 0.0
	_spit_cd = 1.0
	_sweep_cd = 3.0
	_brood_t = 2.0
	NoiseMgr.add_noise(N_SCREAM, global_position)
	print("[BOSS] Żyła budzi się, HP=%.0f" % max_hp)
	_event.rpc("awaken")
	_send_state(true)

func reset_enemy() -> void:
	state = State.DORMANT
	hp = BASE_HP
	max_hp = BASE_HP
	phase = 1
	nests_left = _nest_count()
	_set_atk(Atk.NONE)
	_maw_t = 0.0
	maw_open = false
	stunned = false
	enraged = false
	_spits.clear()
	_wave_r = -1.0
	_wave_start_ms = -1
	visible = true
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)
	if NoiseMgr.is_server():
		_clear_brood.rpc()
		_send_state(true)

func _humans() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			n += 1
	return n

# ---------------------------------------------------------------- symulacja

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_flinch = maxf(0.0, _flinch - delta)
	if not NoiseMgr.is_server():
		return
	if state == State.AWAKE:
		_tick_maw(delta)
		_tick_flashlight(delta)
		_tick_attacks(delta)
		_tick_brood(delta)
	_tick_spits(delta)
	_tick_wave(delta)
	_net_t -= delta
	if _net_t <= 0.0:
		_send_state(false)

func _cd(base: float) -> float:
	return base * (ENRAGED_CD if phase >= 2 else 1.0) * Difficulty.m("boss_cd")

func _set_atk(a: int) -> void:
	atk = a
	winding = a == Atk.LASH
	spitting = a == Atk.SPIT

func _open_maw(t: float, is_stun: bool) -> void:
	_maw_t = maxf(_maw_t, t)
	maw_open = true
	stunned = is_stun
	_send_state(true)

func _tick_maw(delta: float) -> void:
	if _maw_t <= 0.0:
		return
	_maw_t -= delta
	if _maw_t <= 0.0:
		maw_open = false
		stunned = false
		_send_state(true)

## Snop latarki w paszczę w trakcie zapowiedzi ataku: oślepienie — atak
## przerwany, paszcza otwarta.
func _tick_flashlight(delta: float) -> void:
	_stun_cd = maxf(0.0, _stun_cd - delta)
	_light_check -= delta
	if _light_check > 0.0 or _stun_cd > 0.0 or stunned or atk == Atk.NONE:
		return
	_light_check = 0.1
	var lighter := Lights.flashlight_on(global_position + Vector2(0, -8), get_tree(), get_world_2d().direct_space_state)
	if lighter == null:
		return
	_stun_cd = STUN_CD
	_set_atk(Atk.NONE)
	_open_maw(STUN_TIME, true)
	NoiseMgr.add_noise(N_STUN, global_position)
	print("[BOSS] oślepiona latarką (P%d)" % lighter.display_id)
	_event.rpc("blinded")

## Q w pobliżu: przez DIVERT_TIME atakuje miejsce Przesterowania, nie graczy.
func _diverted() -> bool:
	return NoiseMgr.seconds_since_overcharge() < DIVERT_TIME \
		and NoiseMgr.last_overcharge_pos.distance_to(global_position) < DIVERT_RANGE

func _tick_attacks(delta: float) -> void:
	_lash_cd -= delta
	_spit_cd -= delta
	_sweep_cd -= delta
	if atk != Atk.NONE:
		_atk_t -= delta
		if _atk_t <= 0.0:
			_resolve_attack()
		return
	if stunned:
		return
	_atk_gap -= delta
	if _atk_gap > 0.0:
		return
	if _diverted():
		if _spit_cd <= 0.0:
			_begin(Atk.SPIT, SPIT_WINDUP, NoiseMgr.last_overcharge_pos)
		return
	if _lash_cd <= 0.0 and not _players_in_reach(0.0).is_empty():
		_begin(Atk.LASH, LASH_WINDUP, Vector2.ZERO)
	elif _sweep_cd <= 0.0 and _ground_players_near():
		_begin(Atk.SWEEP, SWEEP_WINDUP, Vector2.ZERO)
	elif _spit_cd <= 0.0:
		var p := _spit_candidate()
		if p != null:
			# cel ustalony NA POCZĄTKU zapowiedzi — kto się ruszy, ten unika
			_begin(Atk.SPIT, SPIT_WINDUP, p.global_position + Vector2(0, -8))

func _begin(a: int, windup: float, target: Vector2) -> void:
	_set_atk(a)
	_atk_t = windup * Difficulty.m("boss_cd")
	_spit_target = target
	_event.rpc(["", "lash_windup", "spit_windup", "sweep_windup"][a])
	_send_state(true)

func _resolve_attack() -> void:
	var a := atk
	_set_atk(Atk.NONE)
	match a:
		Atk.LASH:
			for p in _players_in_reach(6.0):
				p.deliver_hit(1, global_position)
			Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.5)
			_lash_cd = _cd(LASH_CD)
		Atk.SPIT:
			_launch_spit(_spit_target)
			_spit_cd = _cd(SPIT_CD)
		Atk.SWEEP:
			_wave_r = 24.0
			_wave_hit.clear()
			_event.rpc("sweep_go")
			_sweep_cd = _cd(SWEEP_CD)
	# po każdym ataku paszcza się otwiera — okno na ostrzał
	_open_maw(MAW_WINDOW, false)
	_atk_gap = (ATK_GAP_ENRAGED if phase >= 2 else ATK_GAP) * Difficulty.m("boss_cd")

func _players_in_reach(slack: float) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.x) <= LASH_RANGE_X + slack and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			out.append(p)
	return out

## Ktoś stoi na podłodze w zasięgu ogona.
func _ground_players_near() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.y) < 4.0 and absf(d.x) <= SWEEP_RANGE:
			return true
	return false

## Cel plucia: najwyżej stojący żywy gracz poza zasięgiem macki, w SPIT_RANGE.
func _spit_candidate() -> Node2D:
	var best: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if d.length() > SPIT_RANGE:
			continue
		if absf(d.x) <= LASH_RANGE_X and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			continue
		if best == null or p.global_position.y < best.global_position.y:
			best = p
	return best

# ---------------------------------------------------------------- fala ogona

## Fala biegnie od Żyły po podłodze w obie strony. Trafia tylko tych, którzy
## STOJĄ na podłodze, gdy przechodzi — skok albo kładka = unik.
func _tick_wave(delta: float) -> void:
	if _wave_r < 0.0:
		return
	_wave_r += SWEEP_SPEED * delta
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or _wave_hit.has(p.name):
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.y) < 3.0 and absf(absf(d.x) - _wave_r) <= SWEEP_HALF:
			_wave_hit[p.name] = true
			p.deliver_hit(1, global_position)
	if _wave_r > SWEEP_RANGE:
		_wave_r = -1.0

# ---------------------------------------------------------------- plucie

func _launch_spit(target: Vector2) -> void:
	var start := global_position + Vector2(0, -34)
	var dist := start.distance_to(target)
	var t := clampf(dist / 240.0, 0.75, 1.3)
	var vel := (target - start - Vector2(0, 0.5 * SPIT_GRAVITY * t * t)) / t
	_spits.append({"pos": start, "vel": vel})
	_spit_fx.rpc(start, vel)

func _tick_spits(delta: float) -> void:
	if _spits.is_empty():
		return
	var lvl := get_parent()
	var keep: Array[Dictionary] = []
	for sp in _spits:
		sp.vel.y += SPIT_GRAVITY * delta
		sp.pos += sp.vel * delta
		var hit := false
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and (p.global_position + Vector2(0, -8)).distance_to(sp.pos) <= SPIT_HIT_R:
				p.deliver_hit(1, sp.pos)
				hit = true
				break
		var cell := Vector2i(int(floor(sp.pos.x / 16.0)), int(floor(sp.pos.y / 16.0)))
		if hit or lvl._is_solid(cell.x, cell.y) or sp.pos.y > lvl.bounds.end.y:
			NoiseMgr.add_noise(N_SPLASH, sp.pos)
			_splash_fx.rpc(sp.pos)
			continue
		keep.append(sp)
	_spits = keep

@rpc("authority", "call_local", "reliable")
func _spit_fx(start: Vector2, vel: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, start, Audio.BUS_WORLD, -4.0, 1.4)
	var glob := SpitGlob.new()
	glob.vel = vel
	glob.gravity = SPIT_GRAVITY
	glob.level = get_parent()
	glob.position = start
	glob.material = Lights.unshaded()
	glob.add_child(Lights.make_light(Lights.radial(), 1.5, Color(0.7, 1.0, 0.3), 0.8, false))
	get_parent().add_child(glob)

@rpc("authority", "call_local", "unreliable")
func _splash_fx(pos: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -8.0, 1.2)
	_burst(pos, Color(0.6, 0.95, 0.3), 14)

class SpitGlob extends Node2D:
	var vel := Vector2.ZERO
	var gravity := 520.0
	var level: Node
	var life := 2.5
	func _physics_process(delta: float) -> void:
		vel.y += gravity * delta
		position += vel * delta
		life -= delta
		var c := Vector2i(int(floor(position.x / 16.0)), int(floor(position.y / 16.0)))
		if life <= 0.0 or level._is_solid(c.x, c.y):
			queue_free()
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.5, Color(0.65, 1.0, 0.3))
		draw_circle(-vel.normalized() * 4.0, 2.2, Color(0.5, 0.85, 0.25, 0.6))

# ---------------------------------------------------------------- potomstwo

func _tick_brood(delta: float) -> void:
	_brood = _brood.filter(func(b: Node) -> bool: return is_instance_valid(b) and b.alive)
	_brood_t -= delta
	if _brood_t > 0.0:
		return
	_brood_t = BROOD_EVERY_ENRAGED if phase >= 2 else BROOD_EVERY
	if _brood.size() >= BROOD_MAX + maxi(0, _humans() - 1):
		return
	_spawn_one()

func _spawn_one() -> void:
	_brood_serial += 1
	var side := -1.0 if _brood_serial % 2 == 0 else 1.0
	_spawn_brood.rpc("Brood%d" % _brood_serial, global_position + Vector2(side * 34.0, 0))

@rpc("authority", "call_local", "reliable")
func _spawn_brood(n: String, pos: Vector2) -> void:
	var lvl := get_parent()
	if lvl.has_node(n):
		return
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = "trzosek"
	e.position = pos
	lvl.add_child(e)
	_brood.append(e)
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -6.0, 0.55)
	if NoiseMgr.is_server():
		e.wake()

@rpc("authority", "call_local", "reliable")
func _clear_brood() -> void:
	for n in get_parent().get_children():
		if n.name.begins_with("Brood"):
			n.queue_free()
	_brood.clear()

# ---------------------------------------------------------------- obrażenia

## Trafienie z kierunkiem (projectile.gd). Pełne obrażenia tylko w OTWARTĄ paszczę
## i nie z góry; reszta (zamknięta paszcza, pancerny grzbiet) — 5% + iskra.
func take_bullet_dir(from_pos: Vector2, dmg: float, dir: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	var from_above := dir.y > ARMOR_DOWN and from_pos.y < global_position.y - 26.0
	_hit(from_pos, dmg, from_above)

func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server():
		return
	_hit(from_pos, dmg, false)

## Obrażenia z broni (combat.gd). Otwarta paszcza i trafienie z poziomu ziemi = pełne
## obrażenia; zamknięta paszcza albo pancerny grzbiet (z góry) = 5% + iskry (efekt
## „twardego” celu rysuje generyczny efekt trafienia, więc _hit nie dubluje go).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	var dir: Vector2 = info["dir"]
	var pos: Vector2 = info["pos"]
	var from_above := dir.y > ARMOR_DOWN and pos.y < global_position.y - 26.0
	var armored := state != State.AWAKE or from_above or not maw_open
	var before := hp
	_hit(pos, float(info["amount"]), from_above, false)
	return {"hit": true, "dealt": before - hp, "killed": state == State.DEAD,
		"mat": Arsenal.Mat.ARMOR if armored else Arsenal.Mat.FLESH}

func _hit(from_pos: Vector2, dmg: float, from_above: bool, fx := true) -> void:
	if state != State.AWAKE:
		if state == State.DORMANT and fx:
			Audio.play_variant_at("ricochet", 2, global_position, Audio.BUS_WORLD, -16.0)
		return
	if from_above or not maw_open:
		dmg *= CLOSED_MULT
		if fx:
			_armor_fx.rpc(from_pos)
	else:
		_flash = 0.08
	hp -= dmg
	if phase == 1 and hp <= max_hp * 0.66:
		phase = 2
		enraged = true
		NoiseMgr.add_noise(N_SCREAM * 0.5, global_position)
		_event.rpc("enrage")
	if phase == 2 and hp <= max_hp * 0.33:
		_phase3()
	if hp <= 0.0:
		_die()
	else:
		_send_state(false)

## Faza 3: krzyk przyzywa Stalkera — Uwaga 100%, światła graczy migoczą.
func _phase3() -> void:
	phase = 3
	NoiseMgr.add_noise(NoiseMgr.MAX_LEVEL, global_position)
	_spawn_one()
	print("[BOSS] faza 3 — krzyk, Uwaga %.0f" % NoiseMgr.level)
	_event.rpc("phase3")

@rpc("authority", "call_local", "unreliable")
func _armor_fx(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - _armor_snd_ms > 120:
		_armor_snd_ms = now
		Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -12.0, 1.2)
	_burst(pos, Color(1.0, 0.85, 0.4), 6)

func _burst(pos: Vector2, col: Color, n: int) -> void:
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = n
	fx.lifetime = 0.35
	fx.explosiveness = 1.0
	fx.spread = 180.0
	fx.initial_velocity_min = 30.0
	fx.initial_velocity_max = 90.0
	fx.gravity = Vector2(0, 300)
	fx.color = col
	fx.material = Lights.unshaded()
	get_parent().add_child(fx)
	fx.global_position = pos
	get_tree().create_timer(0.8).timeout.connect(fx.queue_free)

func _die() -> void:
	state = State.DEAD
	_set_atk(Atk.NONE)
	hp = 0.0
	maw_open = false
	_wave_r = -1.0
	NoiseMgr.add_noise(N_DEATH, global_position)
	for b in _brood:
		if is_instance_valid(b) and b.alive:
			b.take_bullet(global_position, 999.0)
	_brood.clear()
	print("[BOSS] Żyła nie żyje")
	# dwie apteczki na drogę do ekstrakcji przez obudzony teren
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		lvl.spawn_health(global_position + Vector2(-20, -30))
		lvl.spawn_health(global_position + Vector2(20, -30))
	_event.rpc("death")
	_send_state(true)
	died.emit()

# ---------------------------------------------------------------- sieć

func _send_state(now: bool) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	if not now and _net_t > 0.0:
		return
	_net_t = 0.1
	_sync.rpc(state, hp, max_hp, atk, maw_open, stunned, phase, nests_left)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(s: int, h: float, mh: float, a: int, mo: bool, st: bool, ph: int, nl: int) -> void:
	if h < hp - 0.01 and mo:
		_flash = 0.08
	state = s
	hp = h
	max_hp = mh
	_set_atk(a)
	maw_open = mo
	stunned = st
	phase = ph
	enraged = ph >= 2
	if nl < nests_left:
		_flinch = 0.6
	nests_left = nl
	if s != State.DEAD and not visible:
		visible = true
		($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)

@rpc("authority", "call_local", "reliable")
func _event(kind: String) -> void:
	match kind:
		"awaken":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, 0.0, 0.55)
			Audio.sting(2)
			_shake_near(5.0)
		"lash_windup":
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -2.0, 0.75)
		"spit_windup":
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -4.0, 1.35)
		"sweep_windup":
			# dudnienie pod wodą — „zaraz pójdzie fala, skacz"
			Audio.play_variant_at("stalker_step", 3, global_position, Audio.BUS_STALKER, 0.0, 0.5)
			Audio.play_variant_at("stalker_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.55)
		"sweep_go":
			_wave_start_ms = Time.get_ticks_msec()
			Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, 2.0, 0.6)
			_shake_near(2.0)
		"blinded":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -6.0, 1.1)
		"enrage":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -2.0, 0.7)
			_shake_near(3.0)
		"phase3":
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, 2.0, 0.42)
			Audio.sting(2)
			Lights.flicker_until_ms = Time.get_ticks_msec() + 3500
			_shake_near(6.0)
		"death":
			Audio.play_variant_at("explosion", 2, global_position, Audio.BUS_WORLD, 0.0, 0.6)
			Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_STALKER, -2.0, 0.45)
			_shake_near(7.0)
			Feel.hitstop(0.12)
			_death_fx()
			Vfx.gibs(get_parent(), global_position + Vector2(0, -24), Color(0.4, 0.1, 0.14), 26)
			visible = false
			($CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)

func _shake_near(amount: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 400.0:
			Feel.shake(amount)

func _death_fx() -> void:
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.emitting = true
	fx.amount = 90
	fx.lifetime = 1.4
	fx.explosiveness = 0.95
	fx.direction = Vector2(0, -1)
	fx.spread = 80.0
	fx.initial_velocity_min = 60.0
	fx.initial_velocity_max = 220.0
	fx.gravity = Vector2(0, 380)
	fx.scale_amount_min = 1.5
	fx.scale_amount_max = 3.5
	fx.color = Color(0.55, 0.12, 0.16)
	fx.material = Lights.unshaded()
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector2(0, -20)
	get_tree().create_timer(2.0).timeout.connect(fx.queue_free)

# ---------------------------------------------------------------- rysowanie

func _process(_delta: float) -> void:
	if not visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	_light.energy = (0.9 if awake else 0.35) + 0.25 * sin(t * (5.0 if enraged else 2.0))
	if maw_open:
		_light.energy += 0.4
	queue_redraw()
	_overlay.queue_redraw()

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	var base := Color(0.30, 0.10, 0.14) if awake else Color(0.22, 0.10, 0.14)
	if _flash > 0.0:
		base = Color.WHITE
	var sh := Vector2(sin(t * 40.0), 0) * (2.0 if _flinch > 0.0 or stunned else 0.0)
	var breathe := 1.0 + 0.04 * sin(t * (3.0 if awake else 1.2))
	if spitting:
		breathe = 1.08 + 0.05 * sin(t * 30.0)
	draw_circle(Vector2(0, -18) + sh, 26.0 * breathe, base)
	draw_circle(Vector2(-26, -10) + sh, 16.0 * breathe, base.darkened(0.15))
	draw_circle(Vector2(26, -10) + sh, 16.0 * breathe, base.darkened(0.1))
	draw_circle(Vector2(-12, -38) + sh, 12.0 * breathe, base.lightened(0.05))
	draw_circle(Vector2(14, -36) + sh, 11.0 * breathe, base.lightened(0.03))
	var n := 6
	for i in n:
		var a := -PI + PI * (i + 0.5) / n
		var ln := 30.0 + (14.0 if awake else 4.0) + 6.0 * sin(t * 2.0 + i)
		if atk == Atk.SWEEP:
			ln *= 0.6     # macki chowają się pod wodę przed zamachem
		var p0 := Vector2(cos(a) * 20.0, -14.0 + sin(a) * 14.0)
		var p1 := p0 + Vector2(cos(a), sin(a) * 0.6) * ln + Vector2(sin(t * 3.0 + i) * 4.0, 0)
		draw_line(p0 + sh, p1 + sh, base.darkened(0.2), 4.0)
	# pancerny grzbiet
	var plate := Color(0.30, 0.27, 0.25) if _flash <= 0.0 else Color.WHITE
	for i in 5:
		var a := PI * (1.15 + 0.175 * i)
		var c := Vector2(cos(a) * 24.0, -18.0 + sin(a) * 24.0) * breathe + sh
		draw_circle(c, 7.0, plate)
		draw_circle(c + Vector2(0, -1.5), 4.5, plate.lightened(0.12))
	# paszcza: zamknięta = płyty na krzyż, otwarta = wielka, ciemna jama
	if maw_open:
		draw_circle(Vector2(0, -8) + sh, 12.0 * breathe, Color(0.10, 0.01, 0.03))
	else:
		draw_circle(Vector2(-5, -8) + sh, 7.0, plate.darkened(0.1))
		draw_circle(Vector2(5, -8) + sh, 7.0, plate.darkened(0.15))

func _draw_overlay(ov: Node2D) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	var pulse := 0.5 + 0.5 * sin(t * (6.0 if enraged else (3.0 if awake else 1.5)))
	# trzy żyły na sylwetce niezależnie od liczby gniazd: gasną proporcjonalnie
	var veins := 3 if awake else ceili(3.0 * nests_left / _nest_count())
	var vcol := Color(1.0, 0.35, 0.2, (0.45 + 0.5 * pulse) if awake else (0.25 + 0.25 * pulse))
	var pts := [Vector2(-14, -22), Vector2(4, -30), Vector2(18, -16)]
	for i in 3:
		var c := vcol if i < veins else Color(0.3, 0.1, 0.1, 0.3)
		ov.draw_line(Vector2(0, -12), pts[i], c, 2.0)
		ov.draw_circle(pts[i], 2.2, c)
	# paszcza — słaby punkt: zamknięta tli się, otwarta płonie, oślepiona miga na biało
	var maw := Color(1.0, 0.35, 0.2, 0.18)
	var r := 3.0
	if spitting:
		maw = Color(0.55, 1.0, 0.3, 0.6 + 0.4 * pulse)
		r = 6.5
	elif stunned:
		maw = Color(1.0, 1.0, 0.9, 0.5 + 0.5 * absf(sin(t * 18.0)))
		r = 9.0
	elif maw_open:
		maw = Color(1.0, 0.6, 0.25, 0.75 + 0.25 * pulse)
		r = 8.5
	ov.draw_circle(Vector2(0, -8), r, maw)
	if winding:
		ov.draw_arc(Vector2(0, -10), LASH_RANGE_X, PI * 1.05, PI * 1.95, 24, Color(1.0, 0.15, 0.1, 0.4 + 0.5 * pulse), 2.0)
	# zapowiedź zamachu: drżąca woda na całym zasięgu fali
	if atk == Atk.SWEEP:
		for i in range(-10, 11):
			var x := i * SWEEP_RANGE / 10.0
			var h := 1.5 + 2.5 * absf(sin(t * 25.0 + i))
			ov.draw_rect(Rect2(x - 3.0, -h, 6.0, h), Color(0.5, 0.85, 1.0, 0.35 + 0.4 * pulse))
	# fala: dwa grzbiety biegnące od Żyły
	if _wave_start_ms >= 0:
		var wr := 24.0 + (Time.get_ticks_msec() - _wave_start_ms) / 1000.0 * SWEEP_SPEED
		if wr > SWEEP_RANGE:
			_wave_start_ms = -1
		else:
			for s in [-1.0, 1.0]:
				ov.draw_rect(Rect2(s * wr - 4.0, -14.0, 8.0, 14.0), Color(0.75, 0.95, 1.0, 0.85))
				ov.draw_rect(Rect2(s * wr - 9.0, -6.0, 18.0, 6.0), Color(0.5, 0.85, 1.0, 0.5))
