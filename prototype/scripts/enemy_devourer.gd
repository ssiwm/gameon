extends "res://scripts/enemy_behavior.gd"
## Żerca (GDD §7.2, F4d): elita-porywacz. Wyczuwa krew — LEŻĄCYCH graczy w `devour.sense` px po trasie (żywych ludzi bije jak zwykły wróg) — dopada ich, **porywa** i ciągnie
## do swojego domu ze spowolnieniem (`carry_speed`). Po `devour.time` s od porwania „zjada": gracz wraca na start misji z wyposażeniem początkowym (`Player.deliver_devour`;
## to kara dystansem i czasem, nie śmierć na stałe — GDD §4). Zabity w tym czasie puszcza ofiarę (`Player.deliver_take(false)`): min. 3 s do wykrwawienia, podniesienie normalne.
## Stan porwania żyje w graczu (`taken`, `taken_t`, replikowane); tu są liczniki Żercy. Dane w `enemy_defs.gd`: `devour`.

var prey: Node2D = null      ## porwany gracz (leżący)
var carry_t := 0.0           ## s od porwania
var scan_t := 0.0
var sync_t := 0.0
var cand: Node2D = null      ## najbliższy leżący, ostatnio wypatrzony

func cfg() -> Dictionary:
	return e._def.get("devour", {}) as Dictionary

func reset() -> void:
	_release()
	cand = null
	scan_t = 0.0

## Wyczuty leżący gracz budzi śpiącego Żercę.
func tick_asleep(delta: float) -> void:
	scan_t -= delta
	if scan_t > 0.0:
		return
	scan_t = 0.5
	if _find_prey(float(cfg().get("sense", 320.0))) != null:
		e.wake()

## Pościg za leżącym, porwanie i niesienie; true = przejął ruch.
func tick_phase(delta: float, _target: Node2D) -> bool:
	var c := cfg()
	if prey != null:
		return _carry(delta, c)
	scan_t -= delta
	if scan_t <= 0.0:
		scan_t = 0.25
		cand = _find_prey(float(c.get("sense", 320.0)))
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

func view_extra(d: Dictionary) -> void:
	d["carrying"] = prey != null

## Śmierć Żercy uwalnia ofiarę.
func on_death() -> void:
	_release()

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

func _take(p: Node2D, c: Dictionary) -> void:
	prey = p
	carry_t = 0.0
	sync_t = 0.0
	e._sp = 1
	e.velocity.x = 0.0
	NoiseMgr.add_noise(2.0, e.global_position)
	p.deliver_take(true, e.global_position + Vector2(0.0, -4.0), float(c.get("time", 20.0)))

func _carry(delta: float, c: Dictionary) -> bool:
	if not is_instance_valid(prey) or not prey.dead or not prey.taken:
		_release()                                    # ktoś podniósł / wipe / ofiara zniknęła — wracamy do zwykłego zachowania
		return false
	carry_t += delta
	var remaining := float(c.get("time", 20.0)) - carry_t
	if remaining <= 0.0:
		prey.deliver_devour()                         # „zjedzony": kara, gracz wraca na start
		prey = null
		e._sp = 0
		return false
	var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed") * float(c.get("carry_speed", 0.6))
	if absf(e._home.x - e.global_position.x) > 10.0:
		e._steer_to(e._home, speed, delta)
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
