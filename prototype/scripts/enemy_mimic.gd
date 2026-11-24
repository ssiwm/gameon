extends "res://scripts/enemy_behavior.gd"
## Mimik (GDD §7.1, MIMIC_PLAN.md): udaje kolegę z drużyny — stoi jak żywy, z bronią opuszczoną lufą w dół i z imieniem jak u gracza,
## ale bez serduszek. Woła o pomoc krzykiem kolegi, gdy ktoś jest w zasięgu słuchu, ale jeszcze nie przy nim — wabi do zasadzki.
## Kto podejdzie albo strzeli, ten go demaskuje (`wake`): krzyk, fala i chwila na przemianę. Snop latarki demaskuje dopiero po
## LIGHT_REVEAL_S ciągłego światła (M2); w świetle Mimik odwraca twarz, oczy łapią połysk, a klatka piersiowa zaczyna oddychać (widok 3D).
##
## Mimik-zwłoki (M5, `become_corpse`): leży w gnieździe zwłok z danych mapy (corpse.gd), w tej samej pozie i stroju co prawdziwe ciało —
## widok rysuje go jako zwłoki (corpse3d.gd), bez plamy krwi pod ciałem. Nie woła i nie ma etykiety. Demaskuje go: przeszukiwanie
## (po corpse.gd MIMIC_GRAB_S), przejście tuż nad nim (OVER_PX, także bot), trafienie, CORPSE_LIGHT_S ciągłego snopu, krzyk G (do M8).
## Leżąc ma niskie ciało i strefę trafień (LYING), po demaskacji wraca do stojących.

const Lights := preload("res://scripts/lights.gd")
const Player := preload("res://scripts/player.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const LIGHT_REVEAL_S := 1.5          ## s ciągłego snopu latarki do demaskacji (M2)
const DARK_RESET_S := 0.5            ## s ciemności, po których licznik światła wraca do zera
const LIT_EVERY := 0.12              ## s między sprawdzeniami snopu w widoku (każdy peer)
const CALL_R := Vector2(70.0, 340.0) ## px: wabi, gdy najbliższy gracz jest dalej niż x i bliżej niż y
const CALL_GAP := Vector2(6.0, 10.0) ## s między wołaniami
const CALL_BLUR := 48.0              ## px: rozrzut miejsca wołania (kierunek rozmyty jak przez radio)
const LABEL_EVERY := 2.0             ## s między przeliczeniem etykiety (lista drużyny i postaci)
const CORPSE_LIGHT_S := 2.5          ## s ciągłego snopu do demaskacji leżącego (dłużej niż stojący — „wytrzymuje” światło)
const OVER_PX := 10.0                ## px: przejście tuż nad leżącym (ok. 0,6 m) go budzi
const LYING := Vector2(26.0, 5.0)    ## px: ciało ruchu i strefa trafień leżącego (zwłoki mają ok. 26 px długości)
## Kryptonimy, gdy nie ma kogo udawać (sam, bez innych postaci i bez bota) — brzmią jak operatorzy, ale nikt ich nie nosi.
const FALLBACK_NAMES := ["Kret", "Wiór", "Sowa", "Łoś"]

var lure_t := 4.0            ## odstęp między fałszywymi wołaniami
var calls := 0               ## wołania przed demaskacją (dziennik `mimic_reveal`)
var lit_s := 0.0             ## s ciągłego światła na przebranym (serwer)
var _lit_ms := 0             ## zegar ostatniego sprawdzenia światła (serwer)
var _dark_s := 0.0           ## s ciemności od ostatniego światła (serwer)
var _lit := 0.0              ## 0..1: snop na nim w widoku (każdy peer)
var _lit_t := 0.0
var _label := ""
var _label_col := Color.WHITE
var _label_t := 0.0
var corpse: Node2D = null    ## zwłoki, które udaje (M5); null = przebranie stojące
var _stand_body := Vector2.ZERO
var _stand_hurt := Vector2.ZERO

## Mimik-zwłoki (M5): leży w miejscu zwłok `cp` (level.gd przy budowie mapy, u każdego peera tak samo).
func become_corpse(cp: Node2D) -> void:
	corpse = cp
	_lie(true)

func as_corpse() -> bool:
	return corpse != null

## Niskie ciało i strefa trafień leżącego (kule nad ciałem przelatują jak nad zwłokami); `false` — wymiary stojącego.
func _lie(on: bool) -> void:
	var cs := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		return
	var body := cs.shape as RectangleShape2D
	var hurt: RectangleShape2D = e._hit_shape
	if _stand_body == Vector2.ZERO:
		_stand_body = body.size
		_stand_hurt = hurt.size
	var bs := LYING if on else _stand_body
	var hs := LYING if on else _stand_hurt
	body.size = bs
	cs.position = Vector2(0.0, -bs.y * 0.5)
	if hurt != body:
		hurt.size = hs
		var hn = e.get_meta("hurt_shape") if e.has_meta("hurt_shape") else null
		if hn is CollisionShape2D:
			(hn as CollisionShape2D).position = Vector2(0.0, -hs.y * 0.5)

func reset() -> void:
	if corpse != null:
		_lie(true)
	lure_t = 4.0
	calls = 0
	lit_s = 0.0
	_dark_s = 0.0
	_lit_ms = 0
	_label_t = 0.0

## Demaskacja: wpis w dzienniku (M0), krzyk, fala i chwila na zmianę postaci (zapowiedź), potem normalny pościg.
func on_wake() -> void:
	_log_reveal(String(e.wake_cause))
	if corpse != null:
		_lie(false)
	NoiseMgr.add_noise(6.0, e.global_position, "enemy")
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()
	e._windup = 0.35
	e._windup_duration = e._windup
	e.winding = true

## `mimic_reveal` (MIMIC_PLAN.md M0): przyczyna, odległość do najbliższego człowieka, wołania przed demaskacją, rodzaj przebrania, czas światła.
func _log_reveal(cause: String) -> void:
	var best := INF
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		best = minf(best, (p as Node2D).global_position.distance_to(e.global_position))
	SessionLog.event("mimic_reveal", {"cause": cause, "dist": roundi(best) if is_finite(best) else -1, "calls": calls,
		"disguise": "corpse" if corpse != null else "stand", "lit": snappedf(lit_s, 0.1), "pos": SessionLog.xy(e.global_position)})

func scream_pitch() -> float:
	return 0.85

## Zamaskowany stoi jak żywy kolega, nie „śpi"; nie przygasa i ma etykietę gracza.
func anim(a: String, _moving: bool) -> String:
	return "idle" if not e.active else a

func disguised() -> bool:
	return true

## Snop latarki (M2): demaskuje dopiero po LIGHT_REVEAL_S ciągłego światła; po DARK_RESET_S ciemności licznik od zera.
## Sprawdzenia przychodzą co ok. 0,12 s (enemy.gd `_check_wake`), czas między nimi liczy zegar.
func light_wakes(lit: bool) -> bool:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _lit_ms) / 1000.0, 0.0, 0.3) if _lit_ms > 0 else 0.0
	_lit_ms = now
	if lit:
		lit_s += dt
		_dark_s = 0.0
	else:
		_dark_s += dt
		if _dark_s >= DARK_RESET_S:
			lit_s = 0.0
	return lit_s >= (CORPSE_LIGHT_S if corpse != null else LIGHT_REVEAL_S)

## Leżący budzi się dopiero, gdy ktoś przejdzie tuż nad nim (OVER_PX); stojący — przy zwykłym `wake_near`.
func near_mult() -> float:
	return OVER_PX / maxf(float(e._def["wake_near"]), 1.0) if corpse != null else 1.0

## Zabity Mimik-zwłoki zostawia łup ciała, które udawał.
func on_death() -> void:
	if corpse != null and is_instance_valid(corpse) and corpse.has_method("drop_mimic_loot"):
		corpse.drop_mimic_loot()

## Widok (każdy peer): czy jeszcze udaje, i snop na nim — odwraca twarz, połysk oczu, oddech.
func present(delta: float) -> void:
	_lit_t -= delta
	if _lit_t > 0.0:
		return
	_lit_t = LIT_EVERY
	var on: bool = not e.active and e.alive and e.is_inside_tree() \
			and Lights.flashlight_on(e.global_position + Vector2(0, -6), e.get_tree(), e.get_world_2d().direct_space_state) != null
	_lit = 1.0 if on else 0.0

func view_extra(d: Dictionary) -> void:
	d["disguised"] = not e.active
	d["lit"] = _lit
	d["as_corpse"] = corpse != null and not e.active and e.alive          # widok rysuje go jako zwłoki (view3d `_sync_corpses`), nie jako wroga

func disguise_label() -> String:
	if e.active or corpse != null:
		return ""
	_refresh_label()
	return _label

func disguise_color() -> Color:
	return _label_col

## Imię jak u gracza, ale bez plakietki życia (zdradza go). W co-opie kryptonim innego człowieka z drużyny (PROFILES_PLAN.md D2) —
## każdy widzi imię kolegi, nie swoje; sam — inna postać z ekranu OPERATORZY, a bez niej bot albo kryptonim spoza drużyny.
## Kolor jak imię udawanego gracza (MIMIC_PLAN.md M1).
func _refresh_label() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _label != "" and now < _label_t:
		return
	_label_t = now + LABEL_EVERY
	var pick := int(e.get_instance_id() & 0x7fffffff)
	var mates: Array = []
	var bot: Node = null
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion():
			continue
		if p.is_bot:
			bot = p
		elif not p.is_multiplayer_authority():
			mates.append(p)
	if not mates.is_empty():
		mates.sort_custom(func(a: Node, b: Node) -> bool: return int(a.display_id) < int(b.display_id))
		var m: Node = mates[pick % mates.size()]
		_label = String(m.label())
		_label_col = m._body_color()
		return
	var others: Array = []
	if Characters.persist:
		for c in Characters.list():
			var n := Characters.display_clean(String((c as Dictionary).get("name", "")))
			if String(c["id"]) != Characters.active_id and n != "":
				others.append(n)
	var col: Color = Player.BODY_COLORS[1 + pick % (Player.BODY_COLORS.size() - 1)]
	if not others.is_empty():
		_label = String(others[pick % others.size()])
		_label_col = col
	elif bot != null:
		_label = String(bot.label())
		_label_col = Player.BOT_COLOR
	else:
		_label = String(FALLBACK_NAMES[pick % FALLBACK_NAMES.size()])
		_label_col = col

## Zamaskowany Mimik woła o pomoc krzykiem kolegi (ten sam dźwięk co krzyk gracza [G]) z rozmytym kierunkiem i trzaskiem radia,
## gdy ktoś jest w zasięgu słuchu, ale jeszcze nie przy nim — wabi do zasadzki.
func asleep_lod() -> bool:
	return false

func tick_asleep(delta: float) -> void:
	if corpse != null:
		return                                  # zwłoki nie wołają
	lure_t -= delta
	if lure_t > 0.0:
		return
	var p = e._nearest_player()
	var d: float = p.global_position.distance_to(e.global_position) if p != null else INF
	if d < CALL_R.y and d > CALL_R.x:
		lure_t = randf_range(CALL_GAP.x, CALL_GAP.y)
		calls += 1
		var at: Vector2 = e.global_position + Vector2(randf_range(-CALL_BLUR, CALL_BLUR), 0.0)
		if NoiseMgr.has_network():
			e._mimic_call.rpc(at)
		else:
			e._mimic_call(at)
	else:
		lure_t = 1.0
