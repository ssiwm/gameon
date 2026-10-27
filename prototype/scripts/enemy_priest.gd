extends "res://scripts/enemy_behavior.gd"
## Kapłan (GDD §7.2, F4b): elita wspierająca. Nie bije w zwarciu; trzyma dystans (`priest.keep`) za Trzoskami, co `heal_every` s leczy rannych Trzosków w `heal_r` px
## (`heal_pct` maks. HP, tylko z czystą linią) i — gdy gracz podejdzie bliżej niż `trigger` px — krzyczy: zapowiedź `tele` s z pierścieniem fali, potem wszyscy gracze w `radius` px
## (bez ściany na linii) dostają ogłuszenie `stun` s (`Player.deliver_stun`; strzał, skok i bicie zablokowane, chodzić można). Kontra: cofnąć się z pierścienia albo
## zabić go, zanim krzyk się skończy. Zabity — przestaje leczyć, a Trzoski w pobliżu tracą morale. Dane w `enemy_defs.gd`: `priest`.

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

## Wsparcie, nie bijatyka.
func may_attack() -> bool:
	return false

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
	if scream_cd <= 0.0 and e._stagger <= 0.0 and _player_in_trigger():
		e._sp = 1
		e.winding = true
		tele_t = float(cfg().get("tele", 0.7)) * Difficulty.m("enemy_windup")
		tele_duration = tele_t
	return false

## Trzyma dystans: za blisko → cofa się (nie z krawędzi), w komfortowym pasie stoi, dalej zostawia pościg rdzeniowi.
func chase_hold(_target: Node2D, d: Vector2, speed: float) -> bool:
	var keep := cfg().get("keep", [110.0, 190.0]) as Array
	var ax := absf(d.x)
	if ax < float(keep[0]):
		var away: float = -signf(d.x) if absf(d.x) > 1.0 else -e._facing
		e.velocity.x = away * speed * 0.8 if (not e.is_on_wall() and _floor_ahead(away)) else 0.0
		return true
	if ax <= float(keep[1]):
		e.velocity.x = 0.0
		return true
	return false

func view_extra(d: Dictionary) -> void:
	if e._sp == 1:
		d["windup_remaining"] = maxf(tele_t, 0.0)
		d["windup_duration"] = tele_duration
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
	e.visual_attack()
	var c := cfg()
	e._sp = 0
	e.winding = false
	scream_cd = float(e._def["cooldown"]) * Difficulty.m("enemy_cd")
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

## Czy za krokiem w kierunku `dir` jest podłoga (Kapłan cofając się nie spada z krawędzi).
func _floor_ahead(dir: float) -> bool:
	var top: Vector2 = e.global_position + Vector2(dir * 12.0, -4.0)
	var q := PhysicsRayQueryParameters2D.create(top, top + Vector2(0.0, 28.0), 1 | (1 << (e.PLATFORM_BIT - 1)))
	return not e.get_world_2d().direct_space_state.intersect_ray(q).is_empty()
