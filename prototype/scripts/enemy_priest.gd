extends "res://scripts/enemy_behavior.gd"
## Kapłan (GDD §7.2, F4b, ELITE_PLACEMENT_PLAN.md K2): elita dowodząca watahą. Idzie ku graczowi do `priest.hold` px i tam stoi, nie ucieka. Co `heal_every` s leczy rannych
## Trzosków w `heal_r` px (`heal_pct` maks. HP, tylko z czystą linią), a gdy gracz podejdzie bliżej niż `trigger` px — krzyczy: zapowiedź `tele` s z pierścieniem fali, potem wszyscy
## gracze w `radius` px (bez ściany na linii) dostają ogłuszenie `stun` s (`Player.deliver_stun`; strzał, skok i bicie zablokowane, chodzić można). Gdy krzyk jest w przerwie, bije
## w zwarciu. Trafienia go nie chwieją, więc seria nie zagłusza krzyku. Dopóki żyje i zna cel, co `summon.every` s wzywa kolejne Trzoski: gest `summon.channel` s (`summon.break` obrażeń
## go przerywa), po czym idą z ciemności poza kadrem. Wezwani są jak Trzoski bossa: wiedzą, gdzie są gracze, bez XP i łupu. Kontra: cofnąć się z pierścienia i zabić go pierwszego —
## zabity przestaje leczyć, wezwani padają razem z nim, a Trzoski z mapy w pobliżu tracą morale. Dane w `enemy_defs.gd`: `priest`.

const SP_SCREAM := 1
const SP_SUMMON := 2

var scream_cd := 3.0         ## s do następnego krzyku (pierwszy zaraz po wejściu w walkę, ale nie od razu)
var heal_t := 0.0            ## s do następnego tiku leczenia
var tele_t := 0.0            ## s do końca zapowiedzi krzyku albo gestu wezwania (`_sp` = SP_SCREAM / SP_SUMMON)
var summon_t := 6.0          ## s do następnego wezwania (serwer)
var waves := 0               ## wezwania w tej próbie
var channel_hp := 0.0        ## HP na początku gestu wezwania (`summon.break`)
var serial := 0              ## numer w nazwach wezwanych
var minions: Array = []      ## wezwani (serwer)

var tele_duration := 0.0

func cfg() -> Dictionary:
	return e._def.get("priest", {}) as Dictionary

func summon_cfg() -> Dictionary:
	return cfg().get("summon", {}) as Dictionary

func reset() -> void:
	e._sp = 0
	scream_cd = 3.0
	heal_t = 0.0
	tele_t = 0.0
	summon_t = float(summon_cfg().get("first", 6.0))
	waves = 0
	minions.clear()
	if e.is_inside_tree() and NoiseMgr.is_server():
		if NoiseMgr.has_network():
			e._priest_clear.rpc()
		else:
			e._priest_clear()

## Przebudzenie: pierwsze wezwanie po `summon.first` s, także po ponownym zaśnięciu przed pierwszym wezwaniem.
func on_wake() -> void:
	if waves == 0:
		summon_t = float(summon_cfg().get("first", 6.0))

## Bije tylko, gdy krzyk jest w przerwie: z bliska najpierw ogłusza.
func may_attack() -> bool:
	return e._sp == 0 and scream_cd > 0.0

## Cios łapą: bez tego kontakt grałby klip krzyku (`EnemyMotion.KIND`).
func attack_action() -> String:
	return "claw"

func scream_pitch() -> float:
	return 0.75

## Zapowiedź krzyku i leczenie w tiku aktywnego Kapłana; true = zapowiedź przejęła ruch (stoi w miejscu).
func tick_phase(delta: float, _target: Node2D) -> bool:
	scream_cd = maxf(0.0, scream_cd - delta)
	summon_t = maxf(0.0, summon_t - delta)
	if e._sp == SP_SUMMON:
		e.velocity.x = move_toward(e.velocity.x, 0.0, 800.0 * delta)
		if channel_hp - e.hp >= float(summon_cfg().get("break", 60.0)):
			_break_summon()
			return true
		tele_t -= delta
		if tele_t <= 0.0:
			_finish_summon()
		return true
	if e._sp == SP_SCREAM:
		e.velocity.x = move_toward(e.velocity.x, 0.0, 800.0 * delta)
		tele_t -= delta
		if tele_t <= 0.0:
			_scream()
		return true
	_tick_heal(delta)
	if e._windup > 0.0:
		return false
	if scream_cd <= 0.0 and _player_in_trigger():
		e._sp = SP_SCREAM
		e.winding = true
		tele_t = float(cfg().get("tele", 0.7)) * Difficulty.m("enemy_windup")
		tele_duration = tele_t
	elif summon_t <= 0.0:
		if _can_summon():
			e._sp = SP_SUMMON
			e.winding = true
			tele_t = float(summon_cfg().get("channel", 1.2)) * Difficulty.m("enemy_windup")
			tele_duration = tele_t
			channel_hp = e.hp
		else:
			summon_t = float(summon_cfg().get("retry", 3.0))
	return false

## Najwięcej żywych wezwanych naraz (mnożnik Trzosków bossa: EASY 3, NORMAL 4, HARD 6).
func summon_cap() -> int:
	return ceili(float(summon_cfg().get("cap", 4)) * Difficulty.m("boss_adds"))

## Żywi wezwani; martwi i usunięci wypadają z listy.
func alive_minions() -> Array:
	minions = minions.filter(func(m) -> bool: return is_instance_valid(m) and m.alive)
	return minions

## Wzywa tylko w walce: zna cel albo ślad, a poniżej limitu ma kogo dołożyć.
func _can_summon() -> bool:
	return not NoiseMgr.safe_zone and (e._target != null or e._has_lead) and alive_minions().size() < summon_cap()

## Zbyt mocny ostrzał w trakcie gestu: wezwanie przepada, następne po `summon.break_cd` s.
func _break_summon() -> void:
	e._log_elite("summon_break", {"dmg": roundi(channel_hp - e.hp)})
	e._sp = 0
	e.winding = false
	summon_t = float(summon_cfg().get("break_cd", 6.0))

## Koniec gestu: kontakt klipu, głos, hałas i Trzoski w punkcie poza kadrem i linią wzroku (jak wędrowcy Dyrektora); bez miejsca następna próba po `summon.retry` s.
func _finish_summon() -> void:
	var sc := summon_cfg()
	e.visual_attack("summon")
	e._sp = 0
	e.winding = false
	waves += 1
	summon_t = float(sc.get("every", 14.0)) * Difficulty.m("enemy_cd")
	NoiseMgr.add_noise(float(sc.get("noise", 6.0)), e.global_position, "enemy")
	if NoiseMgr.has_network():
		e._cue_fx.rpc("scream")
	else:
		e._cue_fx("scream")
	var lvl: Node = e.get_tree().get_first_node_in_group("level")
	var humans: Array = Director._humans()
	if lvl == null or lvl.get("nav") == null or humans.is_empty():
		return
	var anchor: Node2D = humans[0]
	for h in humans:
		if (h as Node2D).global_position.distance_to(e.global_position) < anchor.global_position.distance_to(e.global_position):
			anchor = h
	var spot: Vector2 = Director._pick_spot(lvl, anchor.global_position, humans)
	if spot == Vector2.ZERO:
		summon_t = float(sc.get("retry", 3.0))
		return
	spawn_wave(spot)

## Fala wezwanych w `spot` (serwer), przycięta do limitu żywych.
func spawn_wave(spot: Vector2) -> void:
	var sc := summon_cfg()
	var size := int(sc.get("late", 3)) if waves > int(sc.get("late_from", 2)) else int(sc.get("count", 2))
	var n := mini(size, summon_cap() - alive_minions().size())
	for i in n:
		serial += 1
		var mn := "%s%d" % [_minion_prefix(), serial]
		var at := spot + Vector2(float(i) * 14.0, 0.0)
		if NoiseMgr.has_network():
			e._priest_spawn.rpc(mn, at)
		else:
			e._priest_spawn(mn, at)
	e._log_elite("summon", {"n": n, "alive": alive_minions().size(), "wave": waves})

func _minion_prefix() -> String:
	return "PriestSpawn_%s_" % String(e.name)

## Wezwany na każdym peerze (`enemy.gd: _priest_spawn`): jak Trzoski bossa (`boss_base.gd: _summon`) — wie, gdzie są gracze, bez XP i łupu.
func spawn_minion(n: String, pos: Vector2) -> void:
	var lvl: Node = e.get_parent()
	if lvl.has_node(n):
		return
	var m: Node = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	m.name = n
	m.kind = "trzosek"
	m.omniscient = true
	m.summoned = true
	m.position = pos
	lvl.add_child(m)
	if NoiseMgr.is_server():
		m.wake()
		minions.append(m)

## Usuwa wezwanych tego Kapłana (restart misji; `enemy.gd: _priest_clear`).
func clear_minions() -> void:
	for n in e.get_parent().get_children():
		if String(n.name).begins_with(_minion_prefix()):
			n.queue_free()

## Idzie ku graczowi do `hold` px i tam stoi; nie cofa się. Dalej zostawia pościg rdzeniowi.
func chase_hold(_target: Node2D, d: Vector2, _speed: float) -> bool:
	if absf(d.x) <= float(cfg().get("hold", 190.0)):
		e.velocity.x = 0.0
		return true
	return false

## Stoi albo szykuje krzyk: patrzy na cel, ślad lub najbliższego gracza. W marszu patrzy tam, dokąd idzie.
func look_at_point() -> Vector2:
	if not e.active:
		return Vector2(INF, INF)
	if not e.winding and absf(e.velocity.x) > float(e._def["speed"]) * 0.5:
		return Vector2(INF, INF)
	if e._target != null and is_instance_valid(e._target) and not e._target.dead:
		return e._target.global_position
	if e._has_lead:
		return e._last_known
	var p = e._nearest_player()
	return p.global_position if p != null else Vector2(INF, INF)

## Kierunek modelu liczy serwer (`_update_facing`): w ruchu z przesunięcia, a stojąc z `look_at_point`.
func server_facing() -> bool:
	return true

func view_extra(d: Dictionary) -> void:
	if e._sp != 0:
		d["windup_remaining"] = maxf(tele_t, 0.0)
		d["windup_duration"] = tele_duration
	if e.winding:
		d["motion_action"] = {SP_SCREAM: "ritual", SP_SUMMON: "summon"}.get(e._sp, "claw")      # `_sp` zna też klient, `_windup` nie
	d["alert"] = bool(d["alert"]) or e._sp != 0                                      # w zapowiedzi oczy żarzą się
	d["tele"] = float(cfg().get("radius", 96.0)) if (e._sp == SP_SCREAM and e.winding) else 0.0   # promień (px) pierścienia zapowiedzi fali
	d["beams"] = e._heal_pts if e._heal_fx_t > 0.0 else PackedVector2Array()         # punkty leczonych Trzosków (zielone wiązki)

## Śmierć: wezwani padają razem z nim (jak potomstwo bossa), a Trzoski z mapy w pobliżu tracą morale jak po śmierci kolegi z watahy.
func on_death() -> void:
	for m in alive_minions().duplicate():
		m.take_bullet(e.global_position, 9999.0)
	minions.clear()
	var pack_r := 220.0
	for o in e._near(e.global_position, pack_r):
		if not is_instance_valid(o) or o == e or o.get_script() != e.get_script() or not o.alive or not o.active:
			continue
		if o.global_position.distance_to(e.global_position) <= pack_r and o._beh.has_method("on_packmate_died"):
			o._beh.on_packmate_died(false, e.global_position)

func _player_in_trigger() -> bool:
	var trig := float(cfg().get("trigger", 110.0))
	var c: Vector2 = e.body_center()
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion():
			continue
		if p.hurt_point(c).distance_to(c) <= trig and not e._wall_between(p):
			return true
	return false

## Koniec zapowiedzi: fala krzyku — hałas, ogłuszenie graczy w zasięgu, dźwięk i pierścień na wszystkich peerach.
func _scream() -> void:
	e.visual_attack("ritual")
	var c := cfg()
	e._sp = 0
	e.winding = false
	scream_cd = float(c.get("scream_cd", 8.0)) * Difficulty.m("enemy_cd")
	NoiseMgr.add_noise(float(c.get("noise", 8.0)), e.global_position, "enemy")
	var origin: Vector2 = e.body_center()
	var r := float(c.get("radius", 96.0))
	var stunned := 0
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion():
			continue
		if p.hurt_point(origin).distance_to(origin) <= r and not e._wall_between(p):
			p.deliver_stun(float(c.get("stun", 0.8)), "kaplan")
			stunned += 1
	e._log_elite("scream", {"stunned": stunned})
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()

## Leczenie rannych Trzosków w zasięgu z czystą linią; wiązki widzą wszyscy peerzy (`_heal_fx`).
func _tick_heal(delta: float) -> void:
	heal_t -= delta
	if heal_t > 0.0:
		return
	var c := cfg()
	heal_t = float(c.get("heal_every", 1.0))
	var r := float(c.get("heal_r", 112.0))
	var pts := PackedVector2Array()
	for o in e._near(e.global_position, r):
		if not is_instance_valid(o) or o == e or o.get_script() != e.get_script() or not o.alive:
			continue
		if String(o._def.get("behavior", "")) != "pack" or o.hp >= o._max_hp:
			continue
		if o.global_position.distance_to(e.global_position) > r or not _line_clear(o):
			continue
		o.hp = minf(o._max_hp, o.hp + o._max_hp * float(c.get("heal_pct", 0.10)))
		pts.append(o.global_position + Vector2(0.0, -6.0))
	if not pts.is_empty():
		if NoiseMgr.has_network():
			e._heal_fx.rpc(pts)
		else:
			e._heal_fx(pts)

func _line_clear(o: Node2D) -> bool:
	var from: Vector2 = e.global_position + Vector2(0.0, -20.0)
	var q := PhysicsRayQueryParameters2D.create(from, o.global_position + Vector2(0.0, -6.0), 1)
	return e.get_world_2d().direct_space_state.intersect_ray(q).is_empty()
