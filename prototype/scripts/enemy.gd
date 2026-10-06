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
		"cooldown": 0.9, "leap": true, "hear": 200.0, "wake_near": 90.0, "sight": 260.0,
		"pack": true, "fears": true, "phototaxis": true,
		"color": Color(0.62, 0.2, 0.22), "size": Vector2(10, 14), "knock": 70.0, "knock_mult": 1.0, "head": 0.0,
	},
	# Ćma (1.7.5): światłolubna — wisi pod sufitem, budzi ją światło (latarka, flara) i leci na nie.
	# Przy flarze spala się, przy latarce gryzie gracza: rzuć flarę daleko, żeby ją odciągnąć.
	"cma": {
		"hp": 18.0, "speed": 74.0, "damage": 1, "windup": 0.2, "reach": 10.0,
		"cooldown": 1.2, "leap": false, "hear": 0.0, "wake_near": 0.0, "sight": 0.0,
		"fly": true, "moth": true, "phototaxis": true,
		"color": Color(0.74, 0.7, 0.55), "size": Vector2(10, 8), "knock": 40.0, "knock_mult": 1.0, "head": 0.0,
	},
	# Skoczek (GDD §7.1): wisi pod sufitem nad przejściem i spada na tego, kto pod nim przejdzie (2 obrażenia).
	"skoczek": {
		"hp": 40.0, "speed": 84.0, "damage": 1, "windup": 0.3, "reach": 13.0,
		"cooldown": 1.0, "leap": true, "hear": 230.0, "wake_near": 60.0, "sight": 280.0,
		"hang": true,
		"color": Color(0.62, 0.6, 0.5), "size": Vector2(12, 14), "knock": 60.0, "knock_mult": 0.9, "head": 0.0,
	},
	# Mimik (GDD §7.1): udaje kolegę z drużyny — stoi jak człowiek i wzywa pomocy głosem gracza.
	# Zdradzają go: brak serduszek nad głową, brak kroków i oddechu, oczy świecące w ciemności,
	# dziwny numer w etykiecie. Latarka, strzał albo podejście (46 px) go demaskują.
	"mimik": {
		"hp": 70.0, "speed": 95.0, "damage": 2, "windup": 0.4, "reach": 14.0,
		"cooldown": 1.2, "leap": true, "hear": 0.0, "wake_near": 46.0, "sight": 220.0,
		"mimic": true,
		"color": Color(0.6, 0.72, 0.6), "size": Vector2(10, 16), "knock": 50.0, "knock_mult": 0.8, "head": 0.0,
	},
	# Ślepiec (GDD §7.1): nie widzi, tylko słyszy — idzie do źródła hałasu; kucanie i cisza go mijają.
	"slepiec": {
		"hp": 60.0, "speed": 70.0, "damage": 1, "windup": 0.35, "reach": 14.0,
		"cooldown": 1.1, "leap": false, "hear": 300.0, "wake_near": 36.0, "sight": 26.0,
		"keen": true, "min_noise": 0.25, "blind": true,
		"color": Color(0.8, 0.78, 0.76), "size": Vector2(12, 17), "knock": 40.0, "knock_mult": 0.6, "head": 0.0,
	},
	# Podsłuchacz (GDD §7.1): stoi nieruchomo i nasłuchuje; zobaczy albo usłyszy — krzyczy i ściąga hordę.
	"podsluchacz": {
		"hp": 35.0, "speed": 0.0, "damage": 0, "windup": 0.9, "reach": 0.0,
		"cooldown": 6.0, "leap": false, "hear": 170.0, "wake_near": 0.0, "sight": 240.0,
		"color": Color(0.58, 0.5, 0.57), "size": Vector2(12, 24), "knock": 30.0, "knock_mult": 0.5, "head": 0.0,
	},
	"wolek": {
		"hp": 140.0, "speed": 36.0, "damage": 2, "windup": 0.6, "reach": 20.0,
		"cooldown": 1.6, "leap": false, "hear": 150.0, "wake_near": 70.0, "sight": 200.0,
		"bruiser": true,
		"color": Color(0.36, 0.27, 0.34), "size": Vector2(20, 26), "knock": 14.0, "knock_mult": 0.2, "head": 0.28,
	},
}

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Nav := preload("res://scripts/nav.gd")
const Surfaces := preload("res://scripts/surfaces.gd")
const NightShift := preload("res://scripts/night_shift.gd")

const GRAVITY := 900.0
const MAX_FALL := 620.0
## Kroki (0,25 na tick) nie budzą; każdy strzał tak — także pierwszy z zimnej
## lufy M-83 (0,6). Przy progu 1,0 pojedyncze strzały M-83 były dla wrogów nieme.
const MIN_WAKE_NOISE := 0.5
const AMMO_DROP := {"trzosek": 0.22, "wolek": 0.6, "slepiec": 0.3, "podsluchacz": 0.15, "mimik": 0.3, "skoczek": 0.25, "cma": 0.0}   ## szansa na skrzynkę z amunicją do broni, którą ktoś nosi
const HEALTH_DROP := {"wolek": 0.75}   ## szansa na apteczkę (1.5) — tylko mocniejsi wrogowie
const SIBLING_WAKE_RADIUS := 140.0
const DEATH_FX_COLOR_VAR := 0.15
const BURN_DPS := 8.0
## Percepcja (1.7): wróg goni tylko to, co widzi (promień wzroku + linia bez ściany), albo idzie
## na ostatni znany ślad (hałas, ostatnia pozycja gracza), rozgląda się, a po dłuższym braku
## kontaktu wraca do domu i zasypia. Wcześniej obudzony wróg znał położenie gracza na całej mapie.
const SEARCH_TIME := 3.5         ## s rozglądania się po dojściu na ślad
const GIVE_UP_TIME := 9.0        ## s bez kontaktu, po których porzuca ślad
const HOME_SLEEP_TIME := 1.2     ## s w domu, po których znów zasypia
const PERCEIVE_DT := 0.12        ## co tyle sprawdzamy wzrok (promień)
const CROUCH_SIGHT := 0.6        ## kucającego widać z mniejszej odległości
const JUMP_V := -275.0           ## skok po grafie A* (42 px, tyle co gracz)
const PLATFORM_BIT := 5          ## warstwa kładek w masce (zeskok)
const DROP_TIME := 0.25
## Słyszalność po trasie (1.7.4): dźwięk nie przechodzi przez ściany ani piętra — liczy się długość
## ścieżki po grafie nawigacji, nie linia prosta. Bez ścieżki (brak węzła) — tłumienie przez mur.
const SOUND_MUFFLE := 3.0
## Wataha (Trzosek): max atakujących naraz, pasmo krążenia, morale, strach przed Stalkerem.
const MAX_ATTACKERS := 2
const HOVER_MIN := 26.0
const HOVER_MAX := 44.0
const PACK_R := 220.0
const FEAR_PER_DEATH := 0.34
const FEAR_ALPHA := 0.7              ## śmierć przewodnika (najstarszy w watasze) łamie morale mocniej
const FEAR_DECAY := 0.12             ## /s
const PANIC_TIME := 2.4
const STALKER_FEAR_R := 260.0
## Wołek (bruiser): szarża z zapowiedzią (rozbija skrzynie i beczki, o ścianę się ogłusza) i rzut skrzynią.
const CHARGE_WINDUP := 0.7
const CHARGE_TIME := 0.9
const CHARGE_MULT := 3.4
const CHARGE_CD := 7.0
const THROW_WINDUP := 0.8
const THROW_CD := 6.0
const CRASH_STUN := 1.3
## Ćma i światło
const MOTH_SEEK_R := 420.0           ## z tej odległości ćma wyczuwa światło
const MOTH_BURN_DPS := 6.0           ## spalanie przy flarze
const LIGHT_LURE_R := 360.0          ## ciekawość Trzosków: flara w tym promieniu (po trasie) daje im ślad
## Skoczek: zasadzka spod sufitu
const AMBUSH_DX := 36.0
const AMBUSH_DY_MAX := 220.0
## Pamięć: wracający do domu wróg sprawdza „gorące miejsce" (gdzie ostatnio strzelano)
const PATROL_RADIUS := 600.0
const PATROL_MAX_AGE := 90.0
## Podsłuchacz: krzyk to hałas (podnosi Uwagę, budzi okolicę) i wskazuje hordzie źródło.
const SCREAM_NOISE := 14.0
const ALARM_R := 420.0           ## wrogowie w tym promieniu dostają ślad do krzyku
const HISTORY_S := 0.5            ## historia pozycji do kompensacji opóźnienia (lag_comp.gd)
const SCREAM_LURE_R := 400.0     ## krzyk GRACZA (voice.gd, GDD §8.2) przyciąga wrogów w 25 m

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
## Percepcja i nawigacja (serwer)
var omniscient := false       ## potomstwo Żyły zawsze zna położenie graczy
var _target: Node2D = null    ## gracz, którego widzi
var _perceive_t := 0.0
var _has_lead := false        ## ma ślad do sprawdzenia
var _last_known := Vector2.ZERO
var _lose_t := 0.0
var _search_t := 0.0
var _home_t := 0.0
var _retreat := 0.0           ## Trzosek odskakuje po ciosie (uderz i uciekaj)
var _path: Array = []
var _path_i := 0
var _repath := 0.0
var _path_goal := Vector2.ZERO
var _drop_t := 0.0
var _blocked := false         ## następny krok grafu to skok, którego nie potrafi
var _hist: Array = []         ## Vector3(czas, x, y) — pozycje z ostatnich HISTORY_S s (serwer)
var _fear := 0.0              ## morale watahy: śmierć kolegów go podnosi, 1.0 = ucieczka
var _flee_src := Vector2.ZERO ## od czego ucieka w panice (ZERO = od gracza)
var _stalker_t := 0.0
var _lure_t := 4.0            ## Mimik: odstęp między fałszywymi wołaniami
var _sp := 0                  ## Wołek: 0 nic, 1 zapowiedź szarży, 2 szarża, 3 zapowiedź rzutu, 4 ogłuszony po uderzeniu
var _sp_t := 0.0
var _sp_dir := 1.0
var _sp_crate: Node = null
var _charge_cd := 3.0
var _throw_cd := 2.0
var _charge_hit := false
var _hanging := false         ## Skoczek / ćma wiszą pod sufitem, dopóki ich nic nie obudzi
var _drop_attack := false     ## Skoczek spada na gracza (obrażenia przy lądowaniu)
var _patrolled := false       ## wracając do domu sprawdził już jedno gorące miejsce
var _t_moth := 0.0
var _scream_cd := 0.0         ## Podsłuchacz: przerwa między krzykami
var _alerted := false         ## Podsłuchacz: już krzyknął (od tej pory boty go widzą jako zagrożenie)
var _ring := 0.0              ## efekt fali krzyku (każdy peer)
var _level_t := 0.0           ## s, przez które cel jest na innym poziomie (histereza: skok gracza to nie zmiana piętra)

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
	_hanging = bool(_def.get("hang", false)) or bool(_def.get("moth", false))
	if _def.get("fly", false):
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING     # ćma lata — bez „podłogi" i grawitacji
	_overlay = Lights.add_overlay(self)

## Aktywny, żywy wróg = realne zagrożenie (boty strzelają tylko do takich).
func is_threat() -> bool:
	return alive and active and (kind != "podsluchacz" or _alerted)

func wake() -> void:
	if not NoiseMgr.is_server() or not alive or active:
		return
	active = true
	if _hanging and _def.get("hang", false):
		# zasadzka: odczepia się od sufitu i spada (lądowanie rani, patrz _land_hit)
		_hanging = false
		_drop_attack = true
		winding = true
		velocity = Vector2(0.0, 40.0)
	if _def.get("mimic", false):
		# demaskacja: krzyk, fala i chwila na zmianę postaci (zapowiedź), potem normalny pościg
		NoiseMgr.add_noise(6.0, global_position)
		if NoiseMgr.has_network():
			_scream_fx.rpc()
		else:
			_scream_fx()
		_windup = 0.35
		winding = true
	if not _has_lead:
		var p := _nearest_player()
		if p != null:
			_lead_at(p.global_position)
	# cała wataha budzi się razem
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.has_method("wake") and e.global_position.distance_to(global_position) < SIBLING_WAKE_RADIUS:
			e.wake()

## HP z uwzględnieniem poziomu trudności (difficulty.gd).
func _scaled_hp() -> float:
	var lvl := get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	return float(_def["hp"]) * Difficulty.m("enemy_hp") * NightShift.hp_mult() * (float(lvl.hp_mult) if lvl != null else 1.0)

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
	_target = null
	_hist.clear()
	_has_lead = false
	_lose_t = 0.0
	_search_t = 0.0
	_retreat = 0.0
	_fear = 0.0
	_flee_src = Vector2.ZERO
	_sp = 0
	_sp_crate = null
	_charge_cd = 3.0
	_throw_cd = 2.0
	_lure_t = 4.0
	_hanging = bool(_def.get("hang", false)) or bool(_def.get("moth", false))
	_drop_attack = false
	_patrolled = false
	_scream_cd = 0.0
	_alerted = false
	_level_t = 0.0
	_home_t = 0.0
	_path.clear()
	_drop_t = 0.0
	set_collision_mask_value(PLATFORM_BIT, true)
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

	_record_history()
	_cd = maxf(0.0, _cd - delta)
	_leap_cd = maxf(0.0, _leap_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_panic = maxf(0.0, _panic - delta)
	_retreat = maxf(0.0, _retreat - delta)
	_fear = maxf(0.0, _fear - FEAR_DECAY * delta)
	_tick_drop(delta)
	_tick_burn(delta)
	if not alive:
		return

	if kind == "podsluchacz":
		_listener_tick(delta)
		return
	if kind == "cma":
		_moth_tick(delta)
		return

	if not active:
		_check_wake()
		if kind == "mimik":
			_mimik_lure(delta)
		if _hanging:
			_check_ambush()
			velocity = Vector2.ZERO          # wisi pod sufitem — bez grawitacji
			_send_state(delta)
			return
		# śpiący wróg stoi i słucha, ale grawitacja działa
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_send_state(delta)
		return

	_listen()
	_perceive(delta)
	var target := _target
	var speed: float = float(_def["speed"]) * Difficulty.m("enemy_speed")
	if _stagger > 0.0:
		speed *= 0.25
	if not _def.get("fly", false):
		speed *= _surface_speed()          # bagno, błoto i olej spowalniają też potwory — da się je tam zwabić

	_stalker_t -= delta
	if _stalker_t <= 0.0:
		_stalker_t = 0.3
		_check_stalker_fear()

	# Wołek: szarża i rzut skrzynią przejmują ruch na czas swoich faz
	if _def.get("bruiser", false) and _bruiser_tick(delta, target):
		_apply_gravity(delta)
		move_and_slide()
		_after_move_bruiser()
		_send_state(delta)
		return

	if _windup > 0.0:
		_windup -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _windup <= 0.0:
			_resolve_attack()
	elif _panic > 0.0:
		# ucieczka: płonący Trzosek (HKM-9), załamane morale watahy, strach przed Stalkerem
		var src_x := _flee_src.x if _flee_src != Vector2.ZERO else (target.global_position.x if target != null else global_position.x - _facing)
		velocity.x = -signf(src_x - global_position.x) * speed * 0.9
	elif target != null and _retreat > 0.0:
		# uderz i uciekaj: po ciosie Trzosek odskakuje, więc wataha nie stoi w miejscu
		velocity.x = -signf(target.global_position.x - global_position.x) * speed * 0.8
	elif target != null:
		_chase(target, speed, delta)
		_try_begin_attack(target)
	elif _has_lead:
		_investigate(speed, delta)
	else:
		_return_home(speed, delta)

	_apply_gravity(delta)
	move_and_slide()
	if _drop_attack and is_on_floor():
		_land_hit()
	_send_state(delta)

## Skoczek lądujący na graczu: 2 obrażenia, łoskot (hałas) i pył.
func _land_hit() -> void:
	_drop_attack = false
	winding = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and absf(p.global_position.x - global_position.x) < 16.0 and absf(p.global_position.y - global_position.y) < 22.0:
			p.deliver_hit(2, global_position)
	NoiseMgr.add_noise(5.0, global_position)
	if NoiseMgr.has_network():
		_crash_fx.rpc()
	else:
		_crash_fx()

## Wiszący Skoczek spada, gdy ktoś stoi (prawie) pod nim i go widać (linia bez ściany).
func _check_ambush() -> void:
	if not _def.get("hang", false):
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var dx := absf(p.global_position.x - global_position.x)
		var dy: float = p.global_position.y - global_position.y
		if dx < AMBUSH_DX and dy > 10.0 and dy < AMBUSH_DY_MAX and _clear_line(p):
			wake()
			return

## Krzyk gracza (mikrofon albo G): wróg w promieniu 25 m rusza do źródła; śpiącego budzi.
func hear_scream(pos: Vector2) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	var lim := SCREAM_LURE_R * Difficulty.m("enemy_hear")
	if _sound_distance(pos, lim) > lim:
		return
	_lead_at(pos)
	wake()

## --- kompensacja opóźnienia (lag_comp.gd) ----------------------------------

func _record_history() -> void:
	var t := LagComp.now()
	_hist.append(Vector3(t, global_position.x, global_position.y))
	while _hist.size() > 2 and (_hist[0] as Vector3).x < t - HISTORY_S:
		_hist.pop_front()

## Prostokąt trafień wroga tak, jak stał w chwili `at_time` (interpolacja z historii).
func lag_rect(at_time: float) -> Rect2:
	var p := global_position
	var n := _hist.size()
	if n > 0 and at_time < (_hist[n - 1] as Vector3).x:
		var first: Vector3 = _hist[0]
		if at_time <= first.x:
			p = Vector2(first.y, first.z)
		else:
			for i in range(n - 1, 0, -1):
				var a: Vector3 = _hist[i - 1]
				var b: Vector3 = _hist[i]
				if at_time >= a.x:
					var k := inverse_lerp(a.x, b.x, at_time)
					p = Vector2(lerpf(a.y, b.y, k), lerpf(a.z, b.z, k))
					break
	var size: Vector2 = _def["size"]
	return Rect2(p.x - size.x * 0.5 - 1.0, p.y - size.y - 1.0, size.x + 2.0, size.y + 2.0)

## Mnożnik prędkości wynikający z powierzchni pod stopami (surfaces.gd).
func _surface_speed() -> float:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return 1.0
	return float(Surfaces.of(lvl.surface_at(global_position))["speed"])

## --- światło ---------------------------------------------------------------

## Flara (flare.gd, serwer) świeci w `pos`: światłolubni (Trzosek) dostają ślad, jeśli to blisko po trasie;
## ślepych i niewidzących światło nie obchodzi. Wabik bez hałasu — za to widoczny.
func see_light(pos: Vector2) -> void:
	if not NoiseMgr.is_server() or not alive or not _def.get("phototaxis", false) or _def.get("moth", false):
		return
	if _target != null:
		return                          # ma gracza przed oczami — nie da się odciągnąć
	if _sound_distance(pos, LIGHT_LURE_R) > LIGHT_LURE_R:
		return
	_lead_at(pos)
	if not active:
		wake()

## Najbliższe źródło światła dla ćmy: flara albo włączona latarka gracza (w promieniu `max_r`).
func _nearest_light(max_r: float) -> Dictionary:
	var best := {}
	var best_d := max_r
	for f in get_tree().get_nodes_in_group("flares"):
		var d := global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = {"pos": f.global_position, "kind": "flare", "node": f}
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or not p.flashlight:
			continue
		var d2 := global_position.distance_to(p.global_position)
		if d2 < best_d:
			best_d = d2
			best = {"pos": p.global_position + Vector2(0, -8), "kind": "player", "node": p}
	return best

## Ćma: wisi (śpi), dopóki w zasięgu nie pojawi się światło; wtedy leci na nie falistym lotem.
## Flara ją spala, latarka — kąsa gracza. Bez światła wraca pod sufit.
func _moth_tick(delta: float) -> void:
	_t_moth += delta
	_cd = maxf(0.0, _cd - delta)
	var lt := _nearest_light(MOTH_SEEK_R)
	if not active:
		velocity = Vector2.ZERO
		if not lt.is_empty():
			wake()
		_send_state(delta)
		return
	var speed: float = float(_def["speed"]) * Difficulty.m("enemy_speed")
	var want := Vector2.ZERO
	if not lt.is_empty():
		_lose_t = 0.0
		var tp: Vector2 = lt["pos"]
		var to := tp - global_position
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		want = dir * speed + Vector2(-dir.y, dir.x) * sin(_t_moth * 9.0 + float(get_instance_id() % 5)) * speed * 0.6
		if lt["kind"] == "flare" and dist < 14.0:
			hp -= MOTH_BURN_DPS * delta                 # krąży przy płomieniu i się spala
			want = Vector2(-dir.y, dir.x) * speed * 0.7
			if hp <= 0.0:
				_die()
				return
		elif lt["kind"] == "player" and dist < 12.0 and _cd <= 0.0:
			var pl: Node = lt["node"]
			pl.deliver_hit(1, global_position)
			_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	else:
		_lose_t += delta
		want = Vector2(sin(_t_moth * 3.1), cos(_t_moth * 2.3)) * speed * 0.35
		if _lose_t > 6.0:
			# światło zgasło: wraca pod sufit i znów zasypia
			var back := _home - global_position
			want = back.normalized() * speed * 0.7
			if back.length() < 8.0:
				active = false
				velocity = Vector2.ZERO
				global_position = _home
				_lose_t = 0.0
	velocity = velocity.lerp(want, 0.18)
	if is_on_wall() or is_on_ceiling():
		velocity.y += 25.0 * (-1.0 if is_on_floor() else 1.0)
	move_and_slide()
	_send_state(delta)

## --- Mimik ----------------------------------------------------------------

## Zamaskowany Mimik woła o pomoc głosem gracza (próbka bólu), gdy ktoś jest w zasięgu słuchu, ale jeszcze
## nie przy nim — wabi do zasadzki. Kto podejdzie, poświeci albo strzeli, ten go demaskuje (wake()).
func _mimik_lure(delta: float) -> void:
	_lure_t -= delta
	if _lure_t > 0.0:
		return
	var p := _nearest_player()
	var d := p.global_position.distance_to(global_position) if p != null else INF
	if d < 340.0 and d > 70.0:
		_lure_t = randf_range(6.0, 10.0)
		if NoiseMgr.has_network():
			_mimic_call.rpc()
		else:
			_mimic_call()
	else:
		_lure_t = 1.0

@rpc("authority", "call_local", "unreliable")
func _mimic_call() -> void:
	Audio.play_variant_at("player_hurt", 2, global_position, Audio.BUS_WORLD, -5.0, randf_range(0.95, 1.1))

## --- Wołek: szarża i rzut skrzynią ------------------------------------------

## Zwraca true, gdy faza specjalna przejęła ruch w tej klatce.
func _bruiser_tick(delta: float, target: Node2D) -> bool:
	_charge_cd = maxf(0.0, _charge_cd - delta)
	_throw_cd = maxf(0.0, _throw_cd - delta)
	match _sp:
		0:
			if target == null or _windup > 0.0 or _stagger > 0.0 or _panic > 0.0:
				return false
			var d := target.global_position - global_position
			if absf(d.y) > 24.0:
				return false
			var ax := absf(d.x)
			if ax > 100.0 and ax < 280.0 and _charge_cd <= 0.0 and _run_clear(signf(d.x), ax):
				_sp = 1
				_sp_t = CHARGE_WINDUP * Difficulty.m("enemy_windup")
				_sp_dir = signf(d.x)
				_charge_hit = false
				winding = true
				return true
			if ax > 60.0 and ax < 220.0 and _throw_cd <= 0.0:
				var c := _find_crate()
				if c != null:
					_sp = 3
					_sp_t = THROW_WINDUP * Difficulty.m("enemy_windup")
					_sp_dir = signf(d.x)
					_sp_crate = c
					winding = true
					return true
			return false
		1:
			velocity.x = 0.0
			_sp_t -= delta
			if _sp_t <= 0.0:
				_sp = 2
				_sp_t = CHARGE_TIME
				winding = false
			return true
		2:
			_sp_t -= delta
			velocity.x = _sp_dir * float(_def["speed"]) * Difficulty.m("enemy_speed") * CHARGE_MULT
			if _sp_t <= 0.0:
				_end_charge()
			return true
		3:
			velocity.x = 0.0
			_sp_t -= delta
			if _sp_t <= 0.0:
				_throw_crate(target)
			return true
		4:
			velocity.x = 0.0
			_sp_t -= delta
			if _sp_t <= 0.0:
				_sp = 0
				winding = false
			return true
	return false

## Czy przed Wołkiem jest wolna droga na rozbieg (bez ściany).
func _run_clear(dir: float, dist: float) -> bool:
	var from := global_position + Vector2(0, -10)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * minf(dist, 200.0), 0), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _end_charge() -> void:
	_sp = 0
	winding = false
	_charge_cd = CHARGE_CD * Difficulty.m("enemy_cd")

## Po ruchu: szarża rozbija skrzynie, detonuje beczki (wybuch rani też Wołka), uderza gracza; ściana ogłusza.
func _after_move_bruiser() -> void:
	if _sp != 2:
		return
	var crashed := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider() as Node
		if col == null:
			continue
		if col.is_in_group("props"):
			if col.has_method("take_bullet"):
				col.take_bullet(global_position, 45.0)
		elif absf(c.get_normal().x) > 0.7:
			crashed = true
	if not _charge_hit:
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and absf(p.global_position.x - global_position.x) < 16.0 and absf(p.global_position.y - global_position.y) < 18.0:
				p.deliver_hit(2, global_position)
				_charge_hit = true
	if crashed:
		_crash()

func _crash() -> void:
	_sp = 4
	_sp_t = CRASH_STUN
	winding = false
	_charge_cd = CHARGE_CD * Difficulty.m("enemy_cd")
	velocity.x = -_sp_dir * 40.0
	NoiseMgr.add_noise(7.0, global_position)
	if NoiseMgr.has_network():
		_crash_fx.rpc()
	else:
		_crash_fx()

@rpc("authority", "call_local", "reliable")
func _crash_fx() -> void:
	Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, 0.0, 0.5)
	Vfx.dust(get_parent(), global_position, 1.0)
	if _local_player_pos().distance_to(global_position) < 300.0:
		Feel.shake(3.5)

func _find_crate() -> Node:
	var best: Node = null
	var best_d := 60.0
	for p in get_tree().get_nodes_in_group("props"):
		if p.get("kind") != "crate" or p.get("exploded") or float(p.get("thrown_t")) > 0.0:
			continue
		var dx := absf(p.global_position.x - global_position.x)
		if dx < best_d and absf(p.global_position.y - global_position.y) < 30.0:
			best_d = dx
			best = p
	return best

## Rzut: balistyczny łuk w gracza (grawitacja ciał fizycznych 980), skrzynia rani przy trafieniu (prop.gd).
func _throw_crate(target: Node2D) -> void:
	var crate := _sp_crate
	_sp = 0
	winding = false
	_throw_cd = THROW_CD * Difficulty.m("enemy_cd")
	_sp_crate = null
	if crate == null or not is_instance_valid(crate) or crate.exploded or target == null or not is_instance_valid(target):
		return
	var from := global_position + Vector2(_sp_dir * 10.0, -26.0)
	var aim := (target.global_position + Vector2(0, -10.0)) - from
	var t := clampf(absf(aim.x) / 300.0, 0.3, 0.8)
	var vel := Vector2(clampf(aim.x / t, -420.0, 420.0), (aim.y - 0.5 * 980.0 * t * t) / t)
	crate.throw_to(from, vel)
	NoiseMgr.add_noise(4.0, global_position)

## --- Podsłuchacz -----------------------------------------------------------

## Stoi i czuwa (zawsze „aktywny", ale się nie rusza). Zobaczy gracza albo usłyszy hałas —
## krzyk z zapowiedzią (0,9 s); zabity po cichu (maczeta w plecy) nie krzyczy.
func _listener_tick(delta: float) -> void:
	active = true
	_scream_cd = maxf(0.0, _scream_cd - delta)
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			winding = false
			_scream()
	else:
		_listen()
		_perceive(delta)
		if _target != null or (_has_lead and _lose_t < 0.3):
			_begin_scream()
	_apply_gravity(delta)
	move_and_slide()
	_send_state(delta)

func _begin_scream() -> void:
	if _scream_cd > 0.0 or _windup > 0.0:
		return
	_windup = float(_def["windup"]) * Difficulty.m("enemy_windup")
	winding = true

func _scream() -> void:
	_scream_cd = float(_def["cooldown"]) * Difficulty.m("enemy_cd")
	_alerted = true
	_has_lead = false
	NoiseMgr.add_noise(SCREAM_NOISE, global_position)
	# ściąga hordę: wrogowie w promieniu idą do źródła krzyku (śpiących budzi)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or e.kind == "podsluchacz":
			continue
		if e._sound_distance(global_position, ALARM_R) < ALARM_R:
			e._lead_at(global_position)
			e.wake()
	if NoiseMgr.has_network():
		_scream_fx.rpc()
	else:
		_scream_fx()

## Krzyk na każdym peerze: dźwięk, fala, lekki wstrząs kamery.
@rpc("authority", "call_local", "reliable")
func _scream_fx() -> void:
	_ring = 0.7
	Audio.play_variant_at("stalker_shriek", 2, global_position, Audio.BUS_WORLD, -3.0, 1.35)
	if _local_player_pos().distance_to(global_position) < 300.0:
		Feel.shake(2.2)

## --- percepcja ------------------------------------------------------------

func _lead_at(pos: Vector2) -> void:
	_patrolled = false
	_last_known = pos
	_has_lead = true
	_lose_t = 0.0
	_search_t = 0.0

## Nowy głośny dźwięk w pobliżu odświeża ślad (wróg idzie do źródła, nie do gracza).
func _listen() -> void:
	if NoiseMgr.noise_serial == _seen_serial:
		return
	_seen_serial = NoiseMgr.noise_serial
	var reach := _noise_reach(NoiseMgr.last_noise_amount, 1.4)
	if reach > 0.0 and _sound_distance(NoiseMgr.last_noise_pos, reach) < reach:
		_lead_at(NoiseMgr.last_noise_pos)

## Odległość „słyszalna" do punktu: długość trasy po grafie nawigacji (nav.gd), nie linia prosta —
## strzał nad głową przez piętro betonu jest daleko, ten sam strzał w sąsiednim korytarzu blisko.
## Trasa nie bywa krótsza niż linia prosta, więc dla odległych źródeł (≥ limit) nie liczymy A*.
func _sound_distance(pos: Vector2, limit: float) -> float:
	var d := global_position.distance_to(pos)
	if d >= limit or d < 24.0:
		return d
	var lvl := get_tree().get_first_node_in_group("level")
	var nav = lvl.get("nav") if lvl != null else null
	if nav == null:
		return d
	var path: Array = nav.find_path(global_position, pos)
	if path.size() < 2:
		return d * SOUND_MUFFLE
	var total := (path[0].pos as Vector2).distance_to(global_position)
	for i in range(1, path.size()):
		total += (path[i].pos as Vector2).distance_to(path[i - 1].pos)
	total += (path[path.size() - 1].pos as Vector2).distance_to(pos)
	return maxf(d, total)

## Zasięg, z którego wróg usłyszy hałas o danej sile (−1 = za cichy). Ślepiec (`keen`) słyszy
## ciche dźwięki (kroki) z bliska, a głośne z daleka — zasięg rośnie z głośnością.
func _noise_reach(amount: float, mult := 1.0) -> float:
	if amount < float(_def.get("min_noise", MIN_WAKE_NOISE)):
		return -1.0
	var r: float = float(_def["hear"]) * Difficulty.m("enemy_hear") * mult
	if _def.get("keen", false):
		r *= clampf(amount / 1.5, 0.35, 1.5)
	return r

## Najbliższy WIDOCZNY gracz (zasięg wzroku + brak ściany na linii). Co PERCEIVE_DT, nie co klatkę.
func _perceive(delta: float) -> void:
	_perceive_t -= delta
	if _perceive_t > 0.0:
		if _target != null and (not is_instance_valid(_target) or _target.dead):
			_target = null
		return
	_perceive_t = PERCEIVE_DT
	var sight: float = float(_def.get("sight", 240.0)) * Difficulty.m("enemy_hear")
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d >= best_d:
			continue
		if not omniscient:
			if d > sight * (CROUCH_SIGHT if pp.crouching else 1.0) or not _clear_line(pp):
				continue
		best = pp
		best_d = d
	_target = best
	if best != null:
		_lead_at(best.global_position)
	else:
		_lose_t += PERCEIVE_DT

func _clear_line(pp: Node2D) -> bool:
	var h: float = (_def["size"] as Vector2).y * 0.6
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -h), pp.global_position + Vector2(0, -8), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## --- zachowanie bez widocznego celu ----------------------------------------

## Idzie na ostatni ślad, rozgląda się i rezygnuje; po dłuższym braku kontaktu wraca do domu.
func _investigate(speed: float, delta: float) -> void:
	var d := _last_known - global_position
	if absf(d.x) < 10.0 and absf(d.y) < 28.0 or _blocked and _search_t > 0.0:
		velocity.x = 0.0
		_search_t += delta
		if _search_t > SEARCH_TIME:
			_has_lead = false
	else:
		if _blocked:
			_search_t += delta       # stoi pod przeszkodą, której nie przeskoczy — krótko czeka i rezygnuje
			velocity.x = 0.0
		else:
			_steer_to(_last_known, speed * 0.85, delta)
	if _lose_t > GIVE_UP_TIME:
		_has_lead = false

func _return_home(speed: float, delta: float) -> void:
	if kind == "skoczek":
		velocity.x = 0.0            # po zasadzce nie wraca na sufit — czatuje tam, gdzie wylądował
		return
	# pamięć: zanim wróci do domu, raz sprawdza „gorące miejsce" — gdzie drużyna ostatnio strzelała
	if not _patrolled:
		_patrolled = true
		var spot: Variant = NoiseMgr.hot_spot_near(global_position, PATROL_RADIUS, PATROL_MAX_AGE)
		if spot != null and (spot as Vector2).distance_to(_last_known) > 90.0:
			_lead_at(spot)
			_lose_t = GIVE_UP_TIME - 5.0      # krótki obchód, nie pełne poszukiwania
			return
	var d := _home - global_position
	if absf(d.x) < 14.0 and absf(d.y) < 28.0:
		velocity.x = 0.0
		_home_t += delta
		if _home_t > HOME_SLEEP_TIME:
			_home_t = 0.0
			active = false
			winding = false
			_patrolled = false
			_seen_serial = NoiseMgr.noise_serial
	else:
		_home_t = 0.0
		_steer_to(_home, speed * 0.6, delta)

## Pościg za widocznym graczem: na tym samym poziomie prosto (linia czysta), inaczej grafem A*.
func _chase(target: Node2D, speed: float, delta: float) -> void:
	var d := target.global_position - global_position
	_level_t = _level_t + delta if absf(d.y) >= 24.0 else 0.0
	if _level_t > 0.35 and _has_nav():
		_steer_to(target.global_position, speed, delta)
		return
	_blocked = false
	if _def.get("pack", false) and _pack_hold(target):
		_hover(d, speed)
		return
	var want := signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
	# rozsuwanie watahy: nie stają w jednym punkcie, tylko w szeregu (można strzelać po kolei)
	if absf(d.x) > float(_def["reach"]):
		want += _separation(speed)
	velocity.x = want
	if is_on_wall() and is_on_floor() and _def["leap"]:
		velocity.y = -230.0

## Wataha atakuje po kolei: gdy MAX_ATTACKERS kolegów już jest przy celu (zapowiedź albo w zasięgu),
## reszta krąży w pasmie HOVER_MIN..HOVER_MAX i czeka na wolne miejsce — zamiast stać w kolejce w jednym punkcie.
func _pack_hold(target: Node2D) -> bool:
	var dx := absf(target.global_position.x - global_position.x)
	if winding or dx <= float(_def["reach"]) + 6.0:
		return false
	var committed := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or not e.active or e.kind != kind:
			continue
		if e._target != target:
			continue
		if e.winding or (absf(e.global_position.x - target.global_position.x) <= float(e._def["reach"]) + 6.0 \
				and absf(e.global_position.y - target.global_position.y) < 18.0):
			committed += 1
	return committed >= MAX_ATTACKERS

func _hover(d: Vector2, speed: float) -> void:
	var ax := absf(d.x)
	if ax > HOVER_MAX:
		velocity.x = signf(d.x) * speed
	elif ax < HOVER_MIN:
		velocity.x = -signf(d.x) * speed * 0.5
	else:
		velocity.x = sin(Time.get_ticks_msec() * 0.004 + float(get_instance_id() % 7)) * speed * 0.3

## Morale: śmierć kolegi z watahy w PACK_R podnosi strach; przy 1.0 reszta się rozbiega (PANIC_TIME).
func _notify_pack_death() -> void:
	if not _def.get("pack", false):
		return
	var alpha := true
	var mates: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or not e.active or e.kind != kind:
			continue
		if e.global_position.distance_to(global_position) > PACK_R:
			continue
		mates.append(e)
		if e.get_instance_id() < get_instance_id():
			alpha = false          # przewodnik = najstarszy w watasze
	for e in mates:
		e._on_packmate_died(alpha, global_position)

func _on_packmate_died(was_alpha: bool, pos: Vector2) -> void:
	_fear += FEAR_ALPHA if was_alpha else FEAR_PER_DEATH
	if _fear >= 1.0:
		_fear = 0.0
		_panic = maxf(_panic, PANIC_TIME)
		_flee_src = _target.global_position if _target != null else pos

## Strach przed Stalkerem: gdy ON jest aktywny i blisko, Trzoski uciekają od niego.
func _check_stalker_fear() -> void:
	if not _def.get("fears", false) or not NoiseMgr.stalker_awake:
		return
	var st := get_parent().get_node_or_null("Stalker") as Node2D
	if st != null and global_position.distance_to(st.global_position) < STALKER_FEAR_R:
		_panic = maxf(_panic, 1.6)
		_flee_src = st.global_position

func _separation(speed: float) -> float:
	var push := 0.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.get_script() != get_script() or not e.alive or not e.active:
			continue
		var dx: float = global_position.x - e.global_position.x
		if absf(dx) < 9.0 and absf(global_position.y - e.global_position.y) < 12.0:
			push += (signf(dx) if dx != 0.0 else (1.0 if get_instance_id() > e.get_instance_id() else -1.0))
	return clampf(push, -1.0, 1.0) * speed * 0.5

func _has_nav() -> bool:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl != null and lvl.get("nav") != null

## Idzie do celu po grafie nawigacji (nav.gd); blisko celu i na tym samym poziomie — prosto.
func _steer_to(goal: Vector2, speed: float, delta: float) -> void:
	var d := goal - global_position
	var lvl := get_tree().get_first_node_in_group("level")
	var nav = lvl.get("nav") if lvl != null else null
	if nav == null or (absf(d.y) < 20.0 and absf(d.x) < 48.0):
		_blocked = false
		velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
		return
	_repath -= delta
	if is_on_floor() and (_repath <= 0.0 or _path_goal.distance_to(goal) > 40.0):
		_repath = 0.45
		_path_goal = goal
		_path = nav.find_path(global_position, goal)
		_path_i = 1
		_blocked = false
	if _path.size() < 2 or _path_i >= _path.size():
		velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
		return
	if is_on_floor():
		for i in range(_path_i, mini(_path_i + 3, _path.size())):
			if absf(_path[i].pos.x - global_position.x) < 6.0 and absf(_path[i].pos.y - global_position.y) < 20.0:
				_path_i = i + 1
				break
		if _path_i >= _path.size():
			velocity.x = signf(d.x) * speed if absf(d.x) > 3.0 else 0.0
			return
	var step: Dictionary = _path[_path_i]
	var prev: Dictionary = _path[_path_i - 1]
	var sx: float = step.pos.x - global_position.x
	if not is_on_floor():
		velocity.x = signf(sx) * speed if absf(sx) > 3.0 else 0.0
		return
	var px: float = prev.pos.x - global_position.x
	match int(step.kind):
		Nav.Edge.JUMP:
			if absf(px) > 4.0:
				velocity.x = signf(px) * speed
			elif _def["leap"]:
				velocity.y = JUMP_V
				velocity.x = signf(sx) * speed
			else:
				_blocked = true
				velocity.x = 0.0
		Nav.Edge.DROP:
			if absf(px) > 4.0:
				velocity.x = signf(px) * speed
			else:
				velocity.x = 0.0
				_start_drop()
		_:
			velocity.x = signf(sx) * speed if absf(sx) > 3.0 else 0.0

func _start_drop() -> void:
	if _drop_t > 0.0:
		return
	_drop_t = DROP_TIME
	set_collision_mask_value(PLATFORM_BIT, false)
	position.y += 1.0

func _tick_drop(delta: float) -> void:
	if _drop_t <= 0.0:
		return
	_drop_t -= delta
	if _drop_t <= 0.0:
		set_collision_mask_value(PLATFORM_BIT, true)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

## Budzi się od NOWEGO głośnego zdarzenia w promieniu słyszenia
## albo gdy gracz stoi za blisko.
func _check_wake() -> void:
	if NoiseMgr.noise_serial != _seen_serial:
		_seen_serial = NoiseMgr.noise_serial
		var reach := _noise_reach(NoiseMgr.last_noise_amount)
		if reach > 0.0 and _sound_distance(NoiseMgr.last_noise_pos, reach) < reach:
			_lead_at(NoiseMgr.last_noise_pos)     # idzie do źródła hałasu, nie wprost do gracza
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
	if not _def.get("blind", false) \
			and Lights.flashlight_on(global_position + Vector2(0, -6), get_tree(), get_world_2d().direct_space_state) != null:
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
	if kind == "trzosek":
		_retreat = 0.32
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
	elif kind == "podsluchacz" and not silent:
		_begin_scream()
	return {"hit": true, "dealt": dmg, "killed": dead, "mat": 0}

# ---------------------------------------------------------------- ogień

func _ignite(seconds: float) -> void:
	var fresh := _burn <= 0.0
	_burn = maxf(_burn, seconds)
	if kind == "trzosek":
		_panic = maxf(_panic, 1.2)
		_flee_src = Vector2.ZERO
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
	elif kind == "podsluchacz":
		_begin_scream()

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
	if NoiseMgr.is_server() and Scrap.enabled() and Scrap.DROP.has(kind) and randf() < Scrap.DROP_CHANCE:
		var ls := get_tree().get_first_node_in_group("level")
		if ls != null:
			ls.spawn_item("scrap", 0, global_position + Vector2(randf_range(-6.0, 6.0), -14), int(Scrap.DROP[kind]))
	_notify_pack_death()
	_set_alive(false)
	winding = false
	_windup = 0.0
	_sp = 0
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

func _process(delta: float) -> void:
	_ring = maxf(0.0, _ring - delta)
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
	if kind == "podsluchacz":
		# stoi w miejscu — patrzy na lokalnego gracza (nasłuchuje)
		var lp := _local_player_pos()
		if is_finite(lp.x) and absf(lp.x - global_position.x) > 4.0:
			_facing = signf(lp.x - global_position.x)
	var anim := "sleep"
	if active:
		if winding:
			anim = "windup"
		elif moving:
			anim = "run" if kind == "trzosek" else "walk"
		else:
			anim = "idle"
	elif kind == "mimik":
		anim = "idle"          # zamaskowany stoi jak żywy kolega, nie „śpi"
	if kind == "cma" and active:
		anim = "idle"          # trzepocze skrzydłami w locie
	Sprites.play(_spr, anim, _facing < 0.0)
	var body: AnimatedSprite2D = _spr[0]
	var m := Color.WHITE
	if _flash > 0.0:
		m = Color(2.4, 2.4, 2.4)
	elif winding:
		# zapowiedź ciosu: pulsujące czerwienienie (klatka „windup" unosi łapę)
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		m = Color(1.6 + 0.6 * p, 0.55, 0.5)
	elif not active and kind != "mimik":
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
	if kind == "mimik" and not active:
		# etykieta jak u gracza, ale bez serduszek (zdradza go) i z numerem, którego nie ma w drużynie
		var f := ThemeDB.fallback_font
		var txt := "P%d" % (2 + int(get_instance_id() % 3))
		ov.draw_string(f, Vector2(-30 + 0.5, -31 + 0.5), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 4, Color(0, 0, 0, 0.8))
		ov.draw_string(f, Vector2(-30, -31), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 4, Color(0.72, 0.8, 0.72))
	if _ring > 0.0:
		var k := 1.0 - _ring / 0.7
		ov.draw_arc(Vector2(0, -size.y * 0.7), 8.0 + k * 70.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.35, (1.0 - k) * 0.8), 1.5)
	# pasek HP po pierwszym trafieniu
	if hp < _max_hp:
		var w := size.x + 4.0
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w, 2.0), Color(0.15, 0.05, 0.05))
		ov.draw_rect(Rect2(-w * 0.5, -size.y - 7.0, w * clampf(hp / _max_hp, 0.0, 1.0), 2.0), Color(0.9, 0.25, 0.2))
