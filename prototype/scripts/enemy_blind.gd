extends "res://scripts/enemy_behavior.gd"
## Ślepiec (GDD §7.1): nie widzi, tylko słyszy. Idzie do źródła hałasu, po dojściu przeszukuje okolicę (`sweep`, `search` — dane rodzaju, obsługuje je rdzeń),
## a na głośny dźwięk szarżuje (mechanika „ślepiec słyszy", niżej). Dane w `enemy_defs.gd`: `lunge`.
##
## Szarża na dźwięk: głośne zdarzenie (≥ `lunge.noise`, np. rozgrzana M-83, strzelba, granat, krzyk) w `lunge.range` px po trasie sprawia, że obudzony Ślepiec staje
## na `lunge.wind` s (stan alert: odwraca się, oczy żarzą się, cichy warkot), a potem na `lunge.time` s pędzi `lunge.mult`× szybciej w stronę źródła — z błędem
## lokalizacji (`hear_error`) i bez sprawdzania drogi. Kontra: po głośnym strzale zejść z miejsca (szarża leci tam, gdzie był dźwięk), kucnąć albo strzelać cicho.
## Cooldown `lunge.cd` s; brak pola `lunge` = rodzaj bez szarży.

var lunge_wind := 0.0        ## s zapowiedzi szarży (stan Ai.ALERT: staje, odwraca się, oczy żarzą się)
var lunge_t := 0.0           ## s trwania szarży (stan Ai.LUNGE: pędzi w stronę źródła dźwięku)
var lunge_dir := 1.0
var lunge_pos := Vector2.ZERO ## dokąd (z błędem lokalizacji) leci szarża
var lunge_cd := 0.0

func reset() -> void:
	lunge_wind = 0.0
	lunge_t = 0.0
	lunge_cd = 0.0

func tick_prelude(delta: float) -> void:
	tick_lunge(delta)

## W zapowiedzi szarży stoi i patrzy na źródło.
func holds_still() -> bool:
	return lunge_wind > 0.0

func derive_mid() -> int:
	if lunge_wind > 0.0:
		return e.Ai.ALERT
	if lunge_t > 0.0:
		return e.Ai.LUNGE
	return -1

## Szarża: pędzi w stronę źródła (z błędem lokalizacji), nie sprawdzając drogi; kończy po czasie albo za źródłem; na styku z graczem bije.
func drive(_delta: float, target: Node2D, speed: float) -> bool:
	if lunge_t > 0.0:
		e.velocity.x = lunge_dir * speed * float((e._def.get("lunge", {}) as Dictionary).get("mult", 2.0))
		if target != null:
			e._try_begin_attack(target)
		return true
	return false

## Trafiony w zapowiedzi szarży nie stoi (zapowiedź przerwana).
func on_damaged() -> void:
	lunge_wind = 0.0

func on_heard_noise(lead: Vector2, dist: float, amount: float) -> void:
	maybe_lunge(lead, dist, amount)

func anim(a: String, _moving: bool) -> String:
	return "run" if (a == "walk" and e._ai == e.Ai.LUNGE) else a

static func lunge_triggers(cfg: Dictionary, amount: float, dist: float) -> bool:
	return not cfg.is_empty() and amount >= float(cfg.get("noise", 2.0)) and dist <= float(cfg.get("range", 140.0))

func maybe_lunge(lead: Vector2, dist: float, amount: float) -> void:
	var cfg := e._def.get("lunge", {}) as Dictionary
	if e._target != null or not lunge_triggers(cfg, amount, dist):
		return
	if lunge_cd > 0.0 or lunge_wind > 0.0 or lunge_t > 0.0 or e._windup > 0.0 or e.summoned or not e.alive:
		return
	lunge_wind = float(cfg.get("wind", 0.3)) * Difficulty.m("enemy_windup")
	lunge_cd = float(cfg.get("cd", 6.0)) * Difficulty.m("enemy_cd")
	lunge_pos = lead
	if absf(lead.x - e.global_position.x) > 4.0:
		e._facing = signf(lead.x - e.global_position.x)
	e._set_ai_state(e.Ai.ALERT)                       # od razu, żeby `_sync` i głos zapowiedzi poszły w tym tiku

func tick_lunge(delta: float) -> void:
	lunge_cd = maxf(0.0, lunge_cd - delta)
	if lunge_wind > 0.0:
		lunge_wind -= delta
		if lunge_wind <= 0.0:
			lunge_wind = 0.0
			lunge_t = float((e._def.get("lunge", {}) as Dictionary).get("time", 0.7))
			lunge_dir = signf(lunge_pos.x - e.global_position.x) if absf(lunge_pos.x - e.global_position.x) > 1.0 else e._facing
	elif lunge_t > 0.0:
		lunge_t -= delta
		if (lunge_pos.x - e.global_position.x) * lunge_dir <= 0.0 or e.is_on_wall():
			lunge_t = 0.0                          # za źródłem albo przy ścianie kończy
