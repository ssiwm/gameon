extends "res://scripts/enemy_behavior.gd"
## Podsłuchacz (GDD §7.1): stoi i czuwa (zawsze „aktywny", ale się nie rusza). Zobaczy gracza albo usłyszy hałas — krzyk z zapowiedzią (0,9 s); zabity po cichu
## (maczeta w plecy) nie krzyczy. W trakcie krzyku stoi w polu ochronnym (−90% obrażeń), kolejne krzyki sięgają bliżej, a po `scream.max` milknie (F3.8).
## Dane w `enemy_defs.gd`: `scream`, `shield`.

const SCREAM_NOISE := 14.0       ## krzyk to hałas (podnosi Uwagę, budzi okolicę)
const ALARM_R := 420.0           ## wrogowie w tym promieniu dostają ślad do krzyku

var scream_cd := 0.0             ## przerwa między krzykami
var alerted := false             ## już krzyknął (od tej pory boty widzą go jako zagrożenie)
var shield_t := 0.0              ## s pola ochronnego, które chroni go w trakcie krzyku (obrażenia × (1 − `shield.reduce`))
var screams := 0                 ## krzyki od ostatniego spokoju — kolejne mają mniejszy zasięg, a po `scream.max` milknie
var calm_t := 0.0                ## s od ostatniego krzyku (po `scream.calm` bez celu licznik krzyków się zeruje)

func reset() -> void:
	scream_cd = 0.0
	alerted = false
	shield_t = 0.0
	screams = 0
	calm_t = 0.0

## W polu ochronnym boty nie marnują amunicji; przed pierwszym krzykiem nie ma go na liście zagrożeń.
func threat_ok() -> bool:
	return alerted and shield_t <= 0.0

func derive_pre() -> int:
	if shield_t > 0.0:
		return e.Ai.SCREAM
	return e.Ai.WINDUP if e._windup > 0.0 else e.Ai.LISTEN

func damage_mult() -> float:
	if shield_t <= 0.0:
		return 1.0
	return 1.0 - clampf(float((e._def.get("shield", {}) as Dictionary).get("reduce", 0.0)), 0.0, 1.0)

## Punkt, w który patrzy: cel > ślad > najbliższy gracz (INF, gdy nikogo nie ma).
func look_at_point() -> Vector2:
	if e._target != null and is_instance_valid(e._target) and not e._target.dead:
		return e._target.global_position
	if e._has_lead:
		return e._last_known
	var p = e._nearest_player()
	return p.global_position if p != null else Vector2(INF, INF)

## Krzyk i tak zaczyna się od nowa po trafieniu, więc ogłuszenie go nie przerywa.
func can_interrupt_windup() -> bool:
	return false

func on_hit(silent: bool) -> void:
	if not silent:
		begin_scream()

func view_extra(d: Dictionary) -> void:
	d["alert"] = bool(d["alert"]) or e._ai == e.Ai.WINDUP or e._ai == e.Ai.SCREAM        # zapowiedź i krzyk: oczy żarzą się jak przy „zauważył"
	d["shield"] = e._ai == e.Ai.SCREAM

func anim(a: String, _moving: bool) -> String:
	return "windup" if e._ai == e.Ai.SCREAM else a        # krzyk w polu ochronnym trzyma pozę zapowiedzi (otwarte usta)

func server_facing() -> bool:
	return true

func shield_up() -> bool:
	return e._ai == e.Ai.SCREAM

func asleep_lod() -> bool:
	return false

func tick_special(delta: float) -> bool:
	e.active = true
	scream_cd = maxf(0.0, scream_cd - delta)
	shield_t = maxf(0.0, shield_t - delta)
	calm_t += delta
	if screams > 0 and e._target == null and calm_t >= float((e._def.get("scream", {}) as Dictionary).get("calm", 12.0)):
		screams = 0                                   # uspokoił się — znów krzyknie z pełnym zasięgiem
	e.velocity.x = move_toward(e.velocity.x, 0.0, 600.0 * delta)
	if e._windup > 0.0:
		e._windup -= delta
		if e._windup <= 0.0:
			e.winding = false
			scream()
	else:
		e._listen()
		e._perceive(delta)
		if e._target != null or (e._has_lead and e._lose_t < 0.3):
			begin_scream()
	e._apply_gravity(delta)
	e.move_and_slide()
	e._send_state(delta)
	return true

## Zapowiedź krzyku. Podsłuchacz, który tylko usłyszał (nie widzi celu), zbiera się dłużej (`scream.blind`) — cichy gracz ma więcej czasu; po `scream.max`
## krzykach z rzędu (licznik zeruje się po `scream.calm` s spokoju) milknie, bo horda i tak już idzie.
func begin_scream() -> void:
	if scream_cd > 0.0 or e._windup > 0.0 or shield_t > 0.0:
		return
	var cfg := e._def.get("scream", {}) as Dictionary
	if screams >= int(cfg.get("max", 99)):
		return
	var blind := 1.0 if e._target != null else float(cfg.get("blind", 1.0))
	e._windup = float(e._def["windup"]) * Difficulty.m("enemy_windup") * blind
	e._windup_duration = e._windup
	e.winding = true

func scream() -> void:
	e.visual_attack()
	var cfg := e._def.get("scream", {}) as Dictionary
	scream_cd = float(e._def["cooldown"]) * Difficulty.m("enemy_cd")
	screams += 1
	calm_t = 0.0
	shield_t = float((e._def.get("shield", {}) as Dictionary).get("time", 0.0))
	alerted = true
	e._has_lead = false
	NoiseMgr.add_noise(SCREAM_NOISE, e.global_position, "alarm")
	# ściąga hordę: wrogowie w promieniu idą w stronę krzyku (śpiących budzi); kolejne krzyki sięgają bliżej, bo reszta już idzie
	var radius := float(cfg.get("radius", ALARM_R)) * (float(cfg.get("repeat", 1.0)) if screams > 1 else 1.0)
	for o in e.get_tree().get_nodes_in_group("enemies"):
		if o == e or o.get_script() != e.get_script() or not o.alive or o.kind == e.kind:
			continue
		var heard: float = o._sound_distance(e.global_position, radius)
		if heard < radius:
			o.answer_alarm(e.global_position, heard, radius, float(cfg.get("wave", 0.0)))
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()
