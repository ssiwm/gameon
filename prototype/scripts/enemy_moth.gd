extends "res://scripts/enemy_behavior.gd"
## Ćma (GDD §7.1; rój od 1.7.442): wisi pod sufitem w gnieździe (śpi), dopóki nie zobaczy światła (flara, ogień, latarka, błysk z lufy, wiązka LR-7) — bez
## ściany po drodze. Wtedy leci na nie falistym lotem. Flara i ogień mają pierwszeństwo przed graczem i ściągają cały rój. Na latarkę ćma nurkuje
## (krótka zapowiedź: cofa się i trzepocze w miejscu) i ją obsiada: nie gryzie, ale przesłania szkło (snop krótszy i ciemniejszy, `player.gd: moth_cover`),
## drenuje baterię i trzepocze głośno (hałas przy latarce ściąga Ślepców). Zgaszona latarka strząsa rój po CLING_LINGER s; ćma zabita
## tuż przy graczu wybucha pyłem, a kaszel to hałas. Bez światła wraca pod sufit i znów zasypia. Cały tik ćmy to `tick_special`.
## Od 1.7.443 ćma ma naturalną wielkość (ok. 14 cm rozpiętości) i lata jak ćma: szarpanym lotem z dwóch częstotliwości wahań i nagłymi zrywami
## w bok (JINK_*), z szybkim skrętem (STEER); w snopie latarki świeci (`view_extra` → `lit`, każdy peer).
## Od 1.7.444 zabija ją tylko cios wręcz (`enemy_defs.gd: melee_only`) — maczeta albo kilof, jednym ciosem każdą w łuku. Flara i ogień już nie
## spalają: rój krąży przy płomieniu, dopóki ten płonie, a potem wraca do latarki.
## Od 1.7.445 gniazdo to 12 ćm (`swarm`, meta „nest” z level.gd): trzepot gra jedna ćma na gniazdo (głośniej), hałas trzepotu na latarce ma
## sufit niezależny od liczby ćm (FLUTTER_CAP), a ostatnia ćma gniazda zabita ciosem zostawia złom (`nest_scrap`).

const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")

const MOTH_SEEK_R := 420.0           ## z tej odległości ćma widzi światło
const BURN_R := 8.0                  ## krąży przy płomieniu (flara, ogień) tak blisko — bez obrażeń, zabija tylko cios wręcz
const LOST_MEMORY := 2.0             ## s lotu ku ostatniemu światłu, gdy zgasło (błysk z lufy trwa 0,6 s)
const RETURN_AFTER := 6.0            ## s bez światła, po których wraca pod sufit
const DIVE_R := 30.0                 ## z tej odległości od lampy zawisa przed nurkowaniem
const DIVE_WIND := 0.25              ## s zapowiedzi nurkowania (× trudność `enemy_windup`)
const DIVE_MULT := 2.4               ## mnożnik prędkości nurkowania
const DIVE_TIME := 0.6               ## s nurkowania; nie doleciała → krąży i próbuje znowu
const DIVE_CD := 1.2                 ## przerwa po chybionym nurkowaniu i po strząśnięciu (× trudność `enemy_cd`)
const CLING_R := 6.0                 ## z tej odległości od lampy siada na szkle
const CLING_SPOT := 2.0              ## promień miejsc na szkle latarki (szkło ok. 16 cm)
const CLING_LINGER := 0.8            ## s, przez które trzyma się zgaszonej latarki, zanim odleci
const FLUTTER_NOISE := 0.7           ## hałas trzepotu jednej ćmy na latarce [na s] (tag „moth”, poza budżetem hałasu wrogów)…
const FLUTTER_CAP := 4.0             ## …ale od tylu ćm na latarce więcej już nie hałasuje (cały rój: 2,8 zdarzenia na s, nie 8,4)
const DUST_R := 40.0                 ## ćma zabita tak blisko gracza wybucha pyłem…
const DUST_NOISE := 6.0              ## …a kaszel słychać jak okrzyk bólu (NoiseMgr.N_HURT)
const DUST_ONCE_MS := 400            ## jeden pył na cios, choć cios zabija kilka ćm
const SP_DIVE := 1                   ## `_sp` (replikowany): zapowiedź i nurkowanie
const PLATFORM_LAYER_BIT := 5         ## kładki jednokierunkowe (player.gd PLATFORM_LAYER_BIT)
const SP_CLING := 3                  ## `_sp`: siedzi na latarce — `player.gd` liczy z tego `moth_cover` na każdym peerze
const WAVE_A := 23.0                 ## rad/s: dwie częstotliwości wahań w bok (lot ćmy jest nieregularny, nie sinusoidą)
const WAVE_B := 37.0
const JINK_MIN := 0.12               ## s między zrywami (losowo JINK_MIN..JINK_MAX)…
const JINK_MAX := 0.4
const JINK_SPEED := 1.1              ## …zryw: nagły skok prędkości w losową stronę (× prędkość)
const STEER := 0.32                  ## wygładzanie skrętu na klatkę (było 0.18 — ćma skręcała jak szybowiec)
const LIT_EVERY := 0.1               ## s między sprawdzeniami, czy ćma jest w snopie (raycast, każdy peer)
const LIGHT_EVERY := 0.1             ## s między pełnymi poszukiwaniami światła (raycasty) obudzonej ćmy; pomiędzy — to samo źródło, pozycja na bieżąco
const SLEEP_SYNC := 1.0              ## s między wysyłkami stanu śpiącej ćmy (wisi bez ruchu; budzi się — od razu zwykłe 20 Hz)

enum Mode { SEEK, WIND, DIVE, CLING }

var t_moth := 0.0
var mode := Mode.SEEK
var host: Node2D = null              ## gracz, na którego latarce siedzi
var _mode_t := 0.0
var _dark_t := 0.0                   ## s od zgaszenia latarki gospodarza
var _noise_acc := 0.0
var _slot := 0.0                     ## kąt miejsca na szkle
var _slot_r := 1.0                   ## …i odległość od środka szkła (× CLING_SPOT) — 12 ćm nie siada w jednym punkcie
var _last_pos := Vector2(INF, INF)   ## ostatnie widziane światło
var _loop_on := false
static var _dust_ms := -100000       ## czas ostatniego pyłu (serwer, wspólny dla wszystkich ćm)
static var _voice := {}              ## gniazdo → ćma, która gra trzepot całego roju (każdy peer)
var _jink_t := 0.0                   ## s do następnego zrywu
var _lt := {}                        ## ostatnio znalezione światło (`nearest_light`)
var _lt_t := 0.0                     ## s do następnego pełnego poszukiwania
var _sleep_sync := 0.0
var _lit := 0.0                      ## 0..1 poświaty w snopie latarki (tylko widok)
var _lit_want := 0.0
var _lit_t := 0.0

func on_ready() -> void:
	e.add_to_group("moths")
	_slot = fmod(float(e.get_instance_id() % 997) * 2.39996, TAU)        # złoty kąt: kolejne ćmy rozkładają się równo wokół szkła
	_slot_r = 0.45 + 0.55 * fmod(float(e.get_instance_id() % 991) * 0.618034, 1.0)
	_lt_t = randf() * LIGHT_EVERY                 # rój nie szuka światła w tej samej klatce
	_sleep_sync = randf() * SLEEP_SYNC
	# przelatuje przez szpary w kładkach (warstwa 16, level.gd LAYER_PLATFORM): widzi przez nie (`_sees` bada tylko teren), więc musi też przez nie
	# dolecieć — inaczej rój z dachu strażnicy utykał na podeście nad graczem
	e.set_collision_mask_value(PLATFORM_LAYER_BIT, false)

func reset() -> void:
	_set_mode(Mode.SEEK)
	host = null
	_last_pos = Vector2(INF, INF)
	_noise_acc = 0.0

func derive_pre() -> int:
	return e.Ai.FLY if e.active else e.Ai.HANG

func anim(a: String, _moving: bool) -> String:
	return "idle" if e.active else a          # trzepocze skrzydłami w locie

## Ćma nie jest celem broni (zabija ją tylko cios wręcz): boty jej nie ostrzeliwują, naprowadzanie jej nie wybiera, skaner jej nie podświetla.
func threat_ok() -> bool:
	return false

## Rój budzi się razem, ale tylko ćmy: obudzona ćma nie budzi Trzosków pod gniazdem, a wataha — ćm.
func sibling_wake_ok(other) -> bool:
	return String(other.get("kind")) == "cma"

func tick_special(delta: float) -> bool:
	_moth_tick(delta)
	return true

## Punkt szkła latarki gracza (snop wychodzi z wylotu broni — `player.gd: _update_lights`, każdy peer).
static func lamp_pos(p: Node2D) -> Vector2:
	var b = p.get("_beam")
	if b != null and is_instance_valid(b) and (b as Node2D).is_inside_tree():
		return (b as Node2D).global_position
	return p.global_position + Vector2(0, -14) + (p.get("aim_dir") as Vector2) * 4.0

## Czy latarka (albo wiązka LR-7) gracza świeci — tylko taką ćma może obsiąść.
func lamp_lit(p: Node) -> bool:
	return p != null and is_instance_valid(p) and not p.dead and (p.flashlight or beam_lit(p))

## Najbliższe widoczne źródło światła w promieniu `max_r` (bez ściany po drodze): {pos, kind ("flare" / "player"), node}. Flara i ogień na podłodze
## mają pierwszeństwo przed graczem, nawet dalej — jaśniejsze, więc rzucona flara ściąga cały rój, także z latarki.
func nearest_light(max_r: float) -> Dictionary:
	var best := {}
	var best_d := max_r
	for f in e.get_tree().get_nodes_in_group("flares"):
		var d: float = e.global_position.distance_to(f.global_position)
		if d < best_d and _sees(f.global_position + Vector2(0, -4)):
			best_d = d
			best = {"pos": f.global_position, "kind": "flare", "node": f}
	for fp in e.get_tree().get_nodes_in_group("fire_patches"):
		var df: float = e.global_position.distance_to(fp.global_position)
		if df < best_d and _sees(fp.global_position + Vector2(0, -4)):
			best_d = df
			best = {"pos": fp.global_position + Vector2(0, -4), "kind": "flare", "node": fp}       # ogień na podłodze wabi ćmę jak flara
	if not best.is_empty():
		return best
	for f in Lights.active_flashes():
		var shooter: Node = f["node"]
		if shooter == null or not is_instance_valid(shooter):
			continue
		var d3: float = e.global_position.distance_to(f["pos"])
		if d3 < best_d and _sees(f["pos"]):
			best_d = d3
			best = {"pos": f["pos"], "kind": "player", "node": shooter}                             # błysk z lufy: ćma leci na strzelca
	for p in e.get_tree().get_nodes_in_group("players"):
		if not lamp_lit(p):
			continue
		var lp := lamp_pos(p)
		var d2: float = e.global_position.distance_to(lp)
		if d2 < best_d and (p == host or _sees(lp)):
			best_d = d2
			best = {"pos": lp, "kind": "player", "node": p}
	return best

## Światło do lotu: śpiąca ćma szuka co klatkę (daleko od świateł bez raycastów — `nearest_light` odsiewa odległością), obudzona co LIGHT_EVERY s
## (rój przy flarze albo latarce to dziesiątki raycastów na klatkę). Między poszukiwaniami leci na to samo źródło, z pozycją liczoną na bieżąco;
## zgaszona latarka albo usunięta flara — od razu pusto.
func _light(delta: float) -> Dictionary:
	_lt_t -= delta
	if not e.active or _lt_t <= 0.0:
		_lt_t = LIGHT_EVERY
		_lt = nearest_light(MOTH_SEEK_R)
		return _lt
	if _lt.is_empty():
		return _lt
	var n = _lt.get("node")
	if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
		_lt = {}
	elif _lt["kind"] == "player":
		if lamp_lit(n):
			_lt["pos"] = lamp_pos(n)
	elif (n as Node).is_in_group("fire_patches"):
		_lt["pos"] = (n as Node2D).global_position + Vector2(0, -4)
	else:
		_lt["pos"] = (n as Node2D).global_position
	return _lt

## Gracz strzela wiązką (LR-7): świeci jak latarka, ćmy lecą na tę wiązkę.
func beam_lit(p: Node) -> bool:
	return bool(p.w_firing) and Weapons.def(int(p.weapon)).kind == Weapons.Kind.BEAM

## Linia bez ściany (warstwa 1 — teren) od ćmy do punktu: ćma w skale nie widzi latarki w sąsiednim korytarzu.
func _sees(pos: Vector2) -> bool:
	if not e.is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters2D.create(e.global_position, pos, 1)
	return e.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _set_mode(m: int) -> void:
	if m != mode:
		mode = m
		_mode_t = 0.0
	if e != null:
		e.winding = m == Mode.WIND
		if m != Mode.WIND:
			e._windup = 0.0
		e._sp = SP_CLING if m == Mode.CLING else (SP_DIVE if m == Mode.WIND or m == Mode.DIVE else 0)

func _moth_tick(delta: float) -> void:
	t_moth += delta
	_mode_t += delta
	var lt := _light(delta)
	if not e.active:
		e.velocity = Vector2.ZERO
		if not lt.is_empty():
			e.wake()
		_sleep_sync -= delta
		if e.active or _sleep_sync <= 0.0:
			_sleep_sync = SLEEP_SYNC
			e._send_state(delta)
		return
	if mode == Mode.CLING:
		_cling_tick(delta, lt)
		e._send_state(delta)
		return
	var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed")
	var want := Vector2.ZERO
	if not lt.is_empty():
		e._lose_t = 0.0
		var tp: Vector2 = lt["pos"]
		_last_pos = tp
		var to: Vector2 = tp - e.global_position
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		var side := Vector2(-dir.y, dir.x)
		var k := float(e.get_instance_id() % 5)
		want = dir * speed + side * (sin(t_moth * WAVE_A + k) * 0.55 + sin(t_moth * WAVE_B + k * 2.0) * 0.35) * speed
		if lt["kind"] == "flare":
			if mode != Mode.SEEK:
				_set_mode(Mode.SEEK)
			if dist < BURN_R:
				want = side * speed * 0.7                     # krąży przy płomieniu
		else:
			var lit: bool = lamp_lit(lt["node"])
			match mode:
				Mode.SEEK:
					if lit and dist < DIVE_R and e._cd <= 0.0:
						_set_mode(Mode.WIND)
						e._windup_duration = DIVE_WIND * Difficulty.m("enemy_windup")
						e._windup = e._windup_duration
				Mode.WIND:
					# zapowiedź: odsuwa się od lampy i trzepocze w miejscu
					want = -dir * speed * 0.35 + side * sin(t_moth * 40.0) * speed * 0.35
					e._windup = maxf(0.0, e._windup_duration - _mode_t)
					if not lit:
						_set_mode(Mode.SEEK)
					elif e._windup <= 0.0:
						_set_mode(Mode.DIVE)
						e.visual_attack()
				Mode.DIVE:
					want = dir * speed * DIVE_MULT
					if lit and dist < CLING_R:
						_attach(lt["node"])
						e._send_state(delta)
						return
					if not lit or _mode_t > DIVE_TIME:
						_set_mode(Mode.SEEK)
						e._cd = DIVE_CD * Difficulty.m("enemy_cd")
	else:
		if mode != Mode.SEEK:
			_set_mode(Mode.SEEK)
		e._lose_t += delta
		want = Vector2(sin(t_moth * 7.3), cos(t_moth * 5.9)) * speed * 0.4
		if e._lose_t < LOST_MEMORY and _last_pos.is_finite():
			want += (_last_pos - e.global_position).limit_length(1.0) * speed * 0.8       # dolatuje tam, gdzie błysnęło
		if e._lose_t > RETURN_AFTER:
			# światło zgasło: wraca pod sufit i znów zasypia
			var back: Vector2 = e._home - e.global_position
			want = back.normalized() * speed * 0.7
			if back.length() < 8.0:
				e.active = false
				e.velocity = Vector2.ZERO
				e.global_position = e._home
				e._lose_t = 0.0
				_last_pos = Vector2(INF, INF)
	if mode != Mode.DIVE:
		_jink_t -= delta
		if _jink_t <= 0.0:
			_jink_t = randf_range(JINK_MIN, JINK_MAX)
			e.velocity += Vector2.from_angle(randf() * TAU) * speed * JINK_SPEED      # zryw: ćma nagle odbija w bok
	e.velocity = e.velocity.lerp(want, STEER if mode != Mode.DIVE else 0.4)
	if e.is_on_wall() or e.is_on_ceiling():
		e.velocity.y += 25.0 * (-1.0 if e.is_on_floor() else 1.0)
	e.move_and_slide()
	e._send_state(delta)

## Siada na szkle latarki gracza `p`.
func _attach(p: Node2D) -> void:
	host = p
	_dark_t = 0.0
	_noise_acc = 0.0
	_set_mode(Mode.CLING)

## Odlatuje z latarki (zgaszona, gracz padł, flara obok) — w bok i w górę, z przerwą przed kolejnym nurkowaniem.
func _detach() -> void:
	var from: Vector2 = e.global_position
	if host != null and is_instance_valid(host):
		from = host.global_position + Vector2(0, -8)
	host = null
	_set_mode(Mode.SEEK)
	e._cd = DIVE_CD * Difficulty.m("enemy_cd")
	var away: Vector2 = (e.global_position - from).normalized() if e.global_position.distance_to(from) > 1.0 else Vector2.from_angle(_slot)
	e.velocity = (away + Vector2(0, -0.6)).normalized() * float(e._def["speed"]) * 1.4

## Na latarce: trzyma się szkła (pozycja wprost — bez kolizji, lampa jest w powietrzu przed graczem), trzepocze (hałas) i drenuje baterię
## (to liczy właściciel latarki z `moth_cover`). Flara w zasięgu, zgaszona lampa po CLING_LINGER s albo upadek gracza — odlatuje.
func _cling_tick(delta: float, lt: Dictionary) -> void:
	var p := host
	if p == null or not is_instance_valid(p) or bool(p.dead) or (not lt.is_empty() and lt["kind"] == "flare"):
		_detach()
		return
	if lamp_lit(p):
		_dark_t = 0.0
		_noise_acc += delta * FLUTTER_NOISE * FLUTTER_CAP / maxf(FLUTTER_CAP, float(p.moth_cover))
		if _noise_acc >= 1.0:
			_noise_acc -= 1.0
			NoiseMgr.add_noise(1.0, e.global_position, "moth")
	else:
		_dark_t += delta
		if _dark_t >= CLING_LINGER:
			_detach()
			return
	var wob := sin(t_moth * 7.0 + _slot) * 0.6
	e.global_position = lamp_pos(p) + Vector2.from_angle(_slot + wob) * CLING_SPOT * _slot_r
	e.velocity = Vector2.ZERO

## Zabita ćma tuż przy graczu wybucha pyłem: kaszel to hałas, chmurę widać u wszystkich. Cios zdejmuje kilka ćm naraz — pył (i kaszel) najwyżej
## raz na DUST_ONCE_MS.
func on_death() -> void:
	host = null
	_set_mode(Mode.SEEK)
	if not NoiseMgr.is_server():
		return
	_nest_cleared()
	if Time.get_ticks_msec() - _dust_ms < DUST_ONCE_MS:
		return
	for p in e.get_tree().get_nodes_in_group("players"):
		if not bool(p.dead) and (p as Node2D).global_position.distance_to(e.global_position) < DUST_R + 16.0 \
				and lamp_pos(p).distance_to(e.global_position) < DUST_R:
			_dust_ms = Time.get_ticks_msec()
			NoiseMgr.add_noise(DUST_NOISE, e.global_position, "moth_dust")
			e.behavior_fx("dust")
			return

## Ostatnia żywa ćma gniazda (meta „nest”) zginęła: na pewno zostawia złom `nest_scrap` (serwer). Pojedyncze ćmy złomu nie dają.
func _nest_cleared() -> void:
	var n := int(e.get_meta("nest", 0))
	var amount := int(EnemyDefs.value("cma", "nest_scrap"))
	if n <= 0 or amount <= 0 or not Scrap.enabled():
		return
	for m in e.get_tree().get_nodes_in_group("moths"):
		if m != e and bool(m.alive) and int(m.get_meta("nest", 0)) == n and m.get_parent() == e.get_parent():
			return
	var lv: Node = e.get_tree().get_first_node_in_group("level")
	if lv != null:
		lv.spawn_item("scrap", 0, e.global_position + Vector2(randf_range(-6.0, 6.0), -14), amount)

## Efekt na każdym peerze (`enemy.gd: _behavior_fx`).
func fx(event: String) -> void:
	if event == "dust":
		Vfx.burst(e.get_parent(), e.global_position, Color(0.78, 0.74, 0.6, 0.55), 22, 8.0, 38.0, Vector2.UP, 180.0, 12.0, 1.4, Vector2(2.0, 4.0))
		Audio.play_variant_at("moth_dust", 2, e.global_position, Audio.BUS_WORLD, -4.0, 1.0)

## Poświata w widoku 3D (enemy3d.gd: `lit`).
func view_extra(d: Dictionary) -> void:
	d["lit"] = _lit

## Trzepot skrzydeł (pętla pozycyjna na każdym peerze): cichy w locie, głośny przy nurkowaniu i na latarce — gra go jedna obudzona ćma gniazda
## (`_is_voice`), nie każda z dwunastu. Do tego poświata: ćma na szkle świeci w pełni, w snopie (Lights.flashlight_on — zasięg, kąt, ściana)
## słabiej; sprawdzane co LIT_EVERY s i wygładzane.
func present(delta: float) -> void:
	var awake: bool = e.alive and e.active and e.is_inside_tree()
	var on: bool = awake and _is_voice()
	_lit_t -= delta
	if _lit_t <= 0.0:
		_lit_t = LIT_EVERY
		_lit_want = 0.0
		if awake:
			if int(e._sp) == SP_CLING:
				_lit_want = 1.0
			elif Lights.flashlight_on(e.global_position + Vector2(0, -1), e.get_tree(), e.get_world_2d().direct_space_state) != null:
				_lit_want = 0.7
	_lit = move_toward(_lit, _lit_want, delta * 6.0)
	var id := "moth_%d" % e.get_instance_id()
	if on != _loop_on:
		_loop_on = on
		if on:
			Audio.start_loop_at("moth_flutter_loop", e, Audio.BUS_WORLD, -16.0, true, id)
		else:
			Audio.stop_loop(id)
	if on:
		Audio.set_loop_volume(id, -3.0 if int(e._sp) == SP_CLING else (-6.0 if int(e._sp) == SP_DIVE else -12.0))       # głos całego gniazda — głośniej niż jedna ćma

## Czy ta ćma gra trzepot swojego gniazda: pierwsza obudzona przejmuje głos, a gdy zginie albo zaśnie — następna. Ćma spoza gniazda
## (testy, `--perfmobs`) gra sama.
func _is_voice() -> bool:
	var nest := int(e.get_meta("nest", -int(e.get_instance_id() % 1000000)))
	var v = _voice.get(nest)
	if v == null or not is_instance_valid(v) or not bool(v.alive) or not bool(v.active) or not (v as Node).is_inside_tree():
		_voice[nest] = e
		return true
	return v == e

## Węzeł znika (koniec misji): pętla przypięta do węzła ginie z nim, a wpis w AudioDirector trzeba zwolnić.
func on_exit() -> void:
	if _loop_on:
		_loop_on = false
		Audio.stop_loop("moth_%d" % e.get_instance_id())
