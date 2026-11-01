extends "res://scripts/enemy_behavior.gd"
## Kapłan (GDD §7.2, F4b, ELITE_PLACEMENT_PLAN.md K2): elita dowodząca watahą. Idzie ku graczowi do `priest.hold` px i tam stoi, nie ucieka. Co `heal_every` s leczy rannych
## Trzosków w `heal_r` px (`heal_pct` maks. HP, tylko z czystą linią), a gdy gracz podejdzie bliżej niż `trigger` px — krzyczy: zapowiedź `tele` s z pierścieniem fali, potem wszyscy
## gracze w `radius` px (bez ściany na linii) dostają ogłuszenie `stun` s (`Player.deliver_stun`; strzał, skok i bicie zablokowane, chodzić można). Gdy krzyk jest w przerwie, bije
## w zwarciu. Trafienia go nie chwieją, więc seria nie zagłusza krzyku. Kontra: cofnąć się z pierścienia albo zabić go, zanim krzyk się skończy. Zabity — przestaje leczyć,
## a Trzoski w pobliżu tracą morale. Dane w `enemy_defs.gd`: `priest`.

var scream_cd := 3.0         ## s do następnego krzyku (pierwszy zaraz po wejściu w walkę, ale nie od razu)
var heal_t := 0.0            ## s do następnego tiku leczenia
var tele_t := 0.0            ## s do końca zapowiedzi krzyku (stan `_sp` = 1)

var tele_duration := 0.0

func cfg() -> Dictionary:
	return e._def.get("priest", {}) as Dictionary

func reset() -> void:
	e._sp = 0
	scream_cd = 3.0
	heal_t = 0.0
	tele_t = 0.0

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
	if e._sp == 1:
		e.velocity.x = move_toward(e.velocity.x, 0.0, 800.0 * delta)
		tele_t -= delta
		if tele_t <= 0.0:
			_scream()
		return true
	_tick_heal(delta)
	if e._windup > 0.0:
		return false
	if scream_cd <= 0.0 and _player_in_trigger():
		e._sp = 1
		e.winding = true
		tele_t = float(cfg().get("tele", 0.7)) * Difficulty.m("enemy_windup")
		tele_duration = tele_t
	return false

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
	if e._sp == 1:
		d["windup_remaining"] = maxf(tele_t, 0.0)
		d["windup_duration"] = tele_duration
	if e.winding:
		d["motion_action"] = "ritual" if e._sp == 1 else "claw"                      # `_sp` zna też klient, `_windup` nie
	d["alert"] = bool(d["alert"]) or e._sp == 1                                      # w zapowiedzi oczy żarzą się
	d["tele"] = float(cfg().get("radius", 96.0)) if (e._sp == 1 and e.winding) else 0.0   # promień (px) pierścienia zapowiedzi fali
	d["beams"] = e._heal_pts if e._heal_fx_t > 0.0 else PackedVector2Array()         # punkty leczonych Trzosków (zielone wiązki)

## Śmierć: Trzoski w pobliżu tracą morale jak po śmierci kolegi z watahy.
func on_death() -> void:
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
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion():
			continue
		if p.hurt_point(origin).distance_to(origin) <= r and not e._wall_between(p):
			p.deliver_stun(float(c.get("stun", 0.8)), "kaplan")
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
