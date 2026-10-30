extends "res://scripts/enemy_behavior.gd"
## Trzosek (GDD §7.1, wataha): atakuje po kolei (max `MAX_ATTACKERS` naraz, reszta krąży), po ciosie odskakuje (uderz i uciekaj), daje znać kolegom o zauważonym
## graczu (F3.4a), ma morale (śmierć kolegów, zwłaszcza przewodnika, rozbija watahę) i ucieka przed Stalkerem oraz ogniem. Stan paniki (`_panic`, `_flee_src`) jest
## wspólny dla wszystkich rodzajów i zostaje w `enemy.gd`; tu są liczniki watahy.

const MAX_ATTACKERS := 2
const HOVER_MIN := 26.0
const HOVER_MAX := 44.0
const PACK_R := 220.0
const SHARE_RADIUS := 220.0          ## px w poziomie: tyle słyszą krzyk kolegi, który zauważył gracza (F3.4a)
const SHARE_DY := 40.0               ## px w pionie: kolega z innego piętra go nie słyszy
const SHARE_COOLDOWN := 3.0          ## s: ten sam wróg daje znać najwyżej raz na tyle
## Morale (1.7.440): przy dawnych 0,34 / 0,7 i zaniku 0,12/s wataha pękała tylko, gdy trzy śmierci zmieściły się w 0,17 s (przewodnik i kolega
## w 0,33 s) — czyli praktycznie tylko od granatu. Teraz pęka przy przewodniku i koledze w ciągu 3 s albo przy trzech śmierciach w ciągu 4 s
## (zwykła walka: zabójstwo co ~1–2 s), a dwie zwykłe śmierci jeszcze jej nie łamią.
const FEAR_PER_DEATH := 0.4
const FEAR_ALPHA := 0.75             ## śmierć przewodnika (najstarszy w watasze) łamie morale mocniej
const FEAR_DECAY := 0.05             ## /s
const PANIC_TIME := 2.4
const STALKER_FEAR_R := 260.0

var share_cd := 0.0          ## s do następnego „dania znać" kolegom o zauważonym graczu (serwer)
var fear := 0.0              ## morale watahy: śmierć kolegów go podnosi, 1.0 = ucieczka
var retreat := 0.0           ## odskakuje po ciosie (uderz i uciekaj)
var stalker_t := 0.0

func reset() -> void:
	share_cd = 0.0
	fear = 0.0
	retreat = 0.0

func tick_prelude(delta: float) -> void:
	share_cd = maxf(0.0, share_cd - delta)
	retreat = maxf(0.0, retreat - delta)
	fear = maxf(0.0, fear - FEAR_DECAY * delta)

## Strach przed Stalkerem sprawdzany co 0,3 s.
func tick_awake(delta: float) -> void:
	stalker_t -= delta
	if stalker_t <= 0.0:
		stalker_t = 0.3
		check_stalker_fear()

## Uderz i uciekaj: po ciosie odskakuje, więc wataha nie stoi w miejscu.
func drive(_delta: float, target: Node2D, speed: float) -> bool:
	if target != null and retreat > 0.0:
		e.velocity.x = -signf(target.global_position.x - e.global_position.x) * speed * 0.8
		return true
	return false

func chase_state() -> int:
	return e.Ai.RETREAT if retreat > 0.0 else e.Ai.CHASE

## Wataha atakuje po kolei: gdy komplet kolegów jest już przy celu, reszta krąży w pasmie i czeka na wolne miejsce.
func chase_hold(target: Node2D, d: Vector2, speed: float) -> bool:
	if _pack_hold(target):
		_hover(d, speed)
		return true
	return false

func on_sighting(pos: Vector2) -> void:
	shout_sighting(pos)

func after_attack() -> void:
	retreat = 0.32

## Płonący Trzosek ucieka zamiast atakować.
func on_ignite() -> void:
	e._panic = maxf(e._panic, 1.2)
	e._flee_src = Vector2.ZERO

func anim(a: String, _moving: bool) -> String:
	return "run" if a == "walk" else a

## Wataha dzieli się tym, co zobaczyła (F3.4a): Trzosek, który właśnie zauważył gracza, „daje znać" pobliskim kolegom — ci, którzy nic nie widzą (śledzą,
## szukają albo wracają), dostają ślad w miejscu gracza i reakcję „zauważył", więc wataha nie atakuje po jednym, tylko schodzi się razem. Śpiących budzi
## osobno `wake()`. Zasięg SHARE_RADIUS w poziomie (w pionie ±SHARE_DY — nie przez piętra), cooldown SHARE_COOLDOWN na krzykacza.
func shout_sighting(pos: Vector2) -> void:
	if share_cd > 0.0 or e.summoned or e.omniscient:
		return
	share_cd = SHARE_COOLDOWN
	for o in e._near(e.global_position, SHARE_RADIUS):
		if not is_instance_valid(o) or o == e or o.get_script() != e.get_script() or o.kind != e.kind:
			continue
		if absf(o.global_position.x - e.global_position.x) <= SHARE_RADIUS and absf(o.global_position.y - e.global_position.y) <= SHARE_DY:
			o._beh.hear_shout(pos)

## Kolega dał znać, gdzie jest gracz: tylko aktywny, nic niewidzący (śledztwo / szukanie / powrót) i niebędący przywołanym bossa.
func hear_shout(pos: Vector2) -> void:
	if not e.alive or not e.active or e._target != null or e.summoned or e.omniscient:
		return
	if not (e._ai in [e.Ai.INVESTIGATE, e.Ai.SEARCH, e.Ai.RETURN]):
		return
	e._lead_at(pos)
	e._begin_alert()

## Wataha atakuje po kolei: gdy MAX_ATTACKERS kolegów już jest przy celu (zapowiedź albo w zasięgu),
## reszta krąży w pasmie HOVER_MIN..HOVER_MAX i czeka na wolne miejsce — zamiast stać w kolejce w jednym punkcie.
func _pack_hold(target: Node2D) -> bool:
	var dx := absf(target.global_position.x - e.global_position.x)
	if e.winding or dx <= float(e._def["reach"]) + 6.0:
		return false
	var committed := 0
	for o in e._near(target.global_position, 120.0):
		if not is_instance_valid(o) or o == e or o.get_script() != e.get_script() or not o.alive or not o.active or o.kind != e.kind:
			continue
		if o._target != target:
			continue
		if o.winding or (absf(o.global_position.x - target.global_position.x) <= float(o._def["reach"]) + 6.0 \
				and absf(o.global_position.y - target.global_position.y) < 18.0):
			committed += 1
			if committed >= MAX_ATTACKERS:
				break                                  # wynik i tak „zajęte" — nie liczymy dalej
	return committed >= MAX_ATTACKERS

func _hover(d: Vector2, speed: float) -> void:
	var ax := absf(d.x)
	if ax > HOVER_MAX:
		e.velocity.x = signf(d.x) * speed
	elif ax < HOVER_MIN:
		e.velocity.x = -signf(d.x) * speed * 0.5
	else:
		e.velocity.x = sin(Time.get_ticks_msec() * 0.004 + float(e.get_instance_id() % 7)) * speed * 0.3

## Morale: śmierć kolegi z watahy w PACK_R podnosi strach; przy 1.0 reszta się rozbiega (PANIC_TIME).
func on_death() -> void:
	var alpha := true
	var mates: Array = []
	for o in e._near(e.global_position, PACK_R):
		if not is_instance_valid(o) or o == e or o.get_script() != e.get_script() or not o.alive or not o.active or o.kind != e.kind:
			continue
		if o.global_position.distance_to(e.global_position) > PACK_R:
			continue
		mates.append(o)
		if o.get_instance_id() < e.get_instance_id():
			alpha = false          # przewodnik = najstarszy w watasze
	for o in mates:
		o._beh.on_packmate_died(alpha, e.global_position)

func on_packmate_died(was_alpha: bool, pos: Vector2) -> void:
	fear += FEAR_ALPHA if was_alpha else FEAR_PER_DEATH
	if fear >= 1.0:
		fear = 0.0
		e._panic = maxf(e._panic, PANIC_TIME)
		e._flee_src = e._target.global_position if e._target != null else pos

## Strach przed Stalkerem: gdy ON jest aktywny i blisko, Trzoski uciekają od niego.
func check_stalker_fear() -> void:
	if not e._def.get("fears", false) or not NoiseMgr.stalker_awake:
		return
	var st := e.get_parent().get_node_or_null("Stalker") as Node2D
	if st != null and e.global_position.distance_to(st.global_position) < STALKER_FEAR_R:
		e._panic = maxf(e._panic, 1.6)
		e._flee_src = st.global_position

