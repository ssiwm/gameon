extends "res://scripts/enemy_behavior.gd"
## Żerca (GDD §7.2, F4d): elita-porywacz, **zamaskowany do chwili porwania**. Dopóki nikt nie leży, jest niewidoczny i nietrafialny (stan `_sp` = 2, wszystkie peery chowają go
## i jego hurtbox), nie atakuje i nie reaguje na żywych graczy. Wyczuwa krew — LEŻĄCYCH w `devour.sense` px po trasie — skrada się do nich, a w chwili porwania **ujawnia się**
## (krzyk, ring, `_sp` = 1) i ciągnie ofiarę do swojego domu ze spowolnieniem (`carry_speed`). Po `devour.time` s od porwania „zjada": gracz wraca na start misji z wyposażeniem
## początkowym (`Player.deliver_devour`, kara dystansem i czasem, nie śmierć na stałe — GDD §4), a Żerca znów się chowa. Zabity w trakcie puszcza ofiarę (min. 3 s do
## wykrwawienia). Trafiony wybuchem w ukryciu — ujawnia się. Stan porwania żyje w graczu (`taken`, `taken_t`); tu są liczniki Żercy. Dane: `devour`.

var prey: Node2D = null      ## porwany gracz (leżący)
var carry_t := 0.0           ## s od porwania
var scan_t := 0.0
var sync_t := 0.0
var cand: Node2D = null      ## najbliższy leżący, ostatnio wypatrzony
var lair := Vector2.ZERO     ## dokąd ciągnie ofiarę (wybierane przy porwaniu: daleko od żywych graczy)
var warn_t := 0.0            ## s do następnego cichego sygnału tropienia (`voice.warn`)

func cfg() -> Dictionary:
	return e._def.get("devour", {}) as Dictionary

func on_ready() -> void:
	_hide()

func reset() -> void:
	_release()
	warn_t = 0.0
	cand = null
	scan_t = 0.0
	_hide()

## Zamaskowany: niewidoczny i nietrafialny (replikowane przez `_sp`).
func is_hidden() -> bool:
	return e._sp == 2

## Boty nie strzelają do tego, czego nie widać.
func threat_ok() -> bool:
	return e._sp != 2

## Ukryty nie bije; ujawniony (np. po wybuchu) bije jak Skoczek.
func may_attack() -> bool:
	return e._sp != 2

## Ukryty Żerca: cały tik jest tutaj — węszy leżących, skrada się do nich i porywa; żywych ludzi ignoruje (bez percepcji, głosów i reakcji „zauważył").
func tick_special(delta: float) -> bool:
	if e._sp != 2:
		return false
	var c := cfg()
	e.active = true
	scan_t -= delta
	if scan_t <= 0.0:
		scan_t = 0.25
		cand = _find_prey(float(c.get("sense", 520.0)))
	if cand != null and is_instance_valid(cand) and cand.dead and not cand.taken:
		var d: Vector2 = cand.global_position - e.global_position
		if absf(d.x) <= float(c.get("grab_r", 14.0)) and absf(d.y) <= 26.0:
			_take(cand, c)
		else:
			var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed") * e._surface_speed()
			e._lead_at(cand.global_position)
			e._steer_to(cand.global_position, speed, delta)
			_warn(delta)
	else:
		cand = null
		e.velocity.x = move_toward(e.velocity.x, 0.0, 400.0 * delta)
	e._apply_gravity(delta)
	e._slide()
	e._send_state(delta)
	return true

## Ukryty Żerca tropiący co kilka sekund zdradza się ledwo słyszalnym oddechem i szelestem — jedyna zapowiedź, że do leżącego ktoś się skrada.
func _warn(delta: float) -> void:
	warn_t -= delta
	if warn_t > 0.0:
		return
	warn_t = randf_range(3.0, 4.5)
	if NoiseMgr.has_network():
		e._cue_fx.rpc("warn")
	else:
		e._cue_fx("warn")

## Pościg za leżącym, porwanie i niesienie po ujawnieniu; true = przejął ruch.
func tick_phase(delta: float, _target: Node2D) -> bool:
	var c := cfg()
	if prey != null:
		return _carry(delta, c)
	scan_t -= delta
	if scan_t <= 0.0:
		scan_t = 0.25
		cand = _find_prey(float(c.get("sense", 520.0)))
	if cand == null or not is_instance_valid(cand) or not cand.dead or cand.taken:
		cand = null
		return false
	var d: Vector2 = cand.global_position - e.global_position
	if absf(d.x) <= float(c.get("grab_r", 14.0)) and absf(d.y) <= 26.0:
		_take(cand, c)
		return true
	var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed") * e._surface_speed()
	e._lead_at(cand.global_position)
	e._steer_to(cand.global_position, speed, delta)
	return true

## Trafiony (wybuch, ogień) w ukryciu — ujawnia się.
func on_hit(_silent: bool) -> void:
	if e._sp == 2:
		e._sp = 0

func view_extra(d: Dictionary) -> void:
	d["carrying"] = prey != null
	d["hidden"] = e._sp == 2

## Śmierć Żercy uwalnia ofiarę.
func on_death() -> void:
	_release()

func _hide() -> void:
	e._sp = 2
	e.winding = false
	e.velocity.x = 0.0

## Najbliższy po trasie leżący i jeszcze nieporwany gracz w `sense` px (null, gdy nikogo).
func _find_prey(sense: float) -> Node2D:
	var best: Node2D = null
	var best_d := sense
	for p in e.get_tree().get_nodes_in_group("players"):
		if not p.dead or p.taken or p.is_queued_for_deletion():
			continue
		var d: float = e._sound_distance(p.global_position, sense)
		if d < best_d:
			best_d = d
			best = p
	return best

## Porwanie = ujawnienie: krzyk i pierścień na wszystkich peerach, ofiara przypięta do Żercy z czasem do kary.
func _take(p: Node2D, c: Dictionary) -> void:
	prey = p
	carry_t = 0.0
	sync_t = 0.0
	e._sp = 1
	lair = _pick_lair()
	e.velocity.x = 0.0
	NoiseMgr.add_noise(float(c.get("noise", 6.0)), e.global_position, "enemy")
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()
	p.deliver_take(true, e.global_position + Vector2(0.0, -4.0), float(c.get("time", 20.0)))
	e.visual_attack("snatch")

func _carry(delta: float, c: Dictionary) -> bool:
	if not is_instance_valid(prey) or not prey.dead or not prey.taken:
		_release()                                    # ktoś podniósł / wipe / ofiara zniknęła — wracamy do zwykłego zachowania
		return false
	carry_t += delta
	var remaining := float(c.get("time", 20.0)) - carry_t
	if remaining <= 0.0:
		prey.deliver_devour()                         # „zjedzony": kara, gracz wraca na start
		prey = null
		_hide()                                       # po posiłku znów znika
		return false
	var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed") * float(c.get("carry_speed", 0.6))
	if absf(lair.x - e.global_position.x) > 10.0:
		e._steer_to(lair, speed, delta)
	else:
		e.velocity.x = 0.0
	sync_t -= delta
	if sync_t <= 0.0:
		sync_t = 0.05
		prey.deliver_take(true, e.global_position + Vector2(0.0, -4.0), remaining)
	return true

func _release() -> void:
	if prey != null and is_instance_valid(prey) and prey.taken:
		prey.deliver_take(false, e.global_position)
	prey = null
	e._sp = 0

## Legowisko, do którego ciągnie ofiarę: punkt siatki nawigacji 250–700 px w poziomie od miejsca porwania (±160 px w pionie), możliwie najdalszy od żywych graczy — porwanie
## ma ZABRAĆ ofiarę z kadru, a nie zostawić ją przy dawnym domu Żercy. Bez siatki (testy) i bez żywych: 400 px w stronę, w którą patrzy.
func _pick_lair() -> Vector2:
	var humans: Array = []
	for p in e.get_tree().get_nodes_in_group("players"):
		if not p.dead and not p.is_queued_for_deletion():
			humans.append(p)
	var lvl = e.get_tree().get_first_node_in_group("level")
	var nav = lvl.get("nav") if lvl != null else null
	var here: Vector2 = e.global_position
	var away: float = e._facing
	if not humans.is_empty():
		var nearest: Node2D = humans[0]
		for p in humans:
			if p.global_position.distance_to(here) < nearest.global_position.distance_to(here):
				nearest = p
		away = -signf(nearest.global_position.x - here.x) if absf(nearest.global_position.x - here.x) > 1.0 else e._facing
	var fallback: Vector2 = here + Vector2(away * 400.0, 0.0)
	if nav == null or humans.is_empty():
		return fallback
	var best: Vector2 = fallback
	var best_score := -1.0
	for id in nav.get_point_ids():
		var pt: Vector2 = nav.get_point_position(id)
		var dx: float = absf(pt.x - here.x)
		if dx < 250.0 or dx > 700.0 or absf(pt.y - here.y) > 160.0:
			continue
		var dmin: float = INF
		for p in humans:
			dmin = minf(dmin, pt.distance_to(p.global_position))
		if dmin > best_score:
			best_score = dmin
			best = pt
	return best
