extends RefCounted
## Warstwa obrażeń — jedyne miejsce, w którym broń „robi krzywdę".
##
## Pocisk, promień, płomień, cios i wybuch budują `info` (słownik) i wołają
## Combat.apply(cel, info). Cel implementuje take_hit(info) -> Dictionary
## {hit, dealt, killed, mat}; cele bez take_hit dostają dawne take_bullet*,
## więc nic starego się nie psuje. Wszystko rozstrzyga SERWER.
##
## info:
##   w        id broni (Weapons)          amount   obrażenia po spadku z dystansu
##   pos      punkt trafienia              dir      kierunek lotu (jednostkowy)
##   shooter  id peera strzelca            type     "bullet"|"beam"|"rail"|"fire"|"melee"|"blast"
##   knock    odrzut (px/s)                stun     ogłuszenie (s)      ignite  podpalenie (s)
##   crit_mult mnożnik za głowę            backstab cios w plecy/śpiącego (melee)
##   heavy    ciężki efekt (strzelba, wybuch)  silent  nie budzi i nie hałasuje

const Weapons := preload("res://scripts/weapons.gd")

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TARGET := 4 | 32      ## wrogowie, gniazda, boss, Stalker (4) i obiekty (32)

## Obrażenia wybuchu rosną do środka: na brzegu zostaje ta część.
const BLAST_EDGE := 0.5

static func make_info(w: int, amount: float, pos: Vector2, dir: Vector2, shooter: int, type: String) -> Dictionary:
	var d: RefCounted = Weapons.def(w)
	return {
		"w": w, "amount": amount, "pos": pos, "dir": dir, "shooter": shooter, "type": type,
		"knock": d.knock, "stun": d.stun, "ignite": d.ignite, "crit_mult": d.crit_mult,
		"backstab": false, "heavy": d.pellets >= 5 or d.kind == Weapons.Kind.RAIL,
		"silent": false, "crit": false,
	}

## Zadaje obrażenia celowi (serwer). Zwraca {hit, dealt, killed, mat, crit}.
static func apply(target: Node, info: Dictionary) -> Dictionary:
	var res := {"hit": false, "dealt": 0.0, "killed": false, "mat": 0, "crit": false}
	if not NoiseMgr.is_server() or target == null or not is_instance_valid(target):
		return res
	# trafienie w głowę: punkt trafienia w górnej części sylwetki (tylko pociski i cięcia)
	var cm: float = info.get("crit_mult", 1.0)
	var t: String = info.get("type", "bullet")
	if cm > 1.0 and (t == "bullet" or t == "rail") and target.has_method("head_y"):
		if (info["pos"] as Vector2).y <= float(target.call("head_y")):
			info["amount"] = float(info["amount"]) * cm
			info["crit"] = true
	if target.has_method("take_hit"):
		var r: Variant = target.call("take_hit", info)
		if r is Dictionary:
			res.merge(r, true)
	elif target.has_method("take_bullet_dir"):
		target.call("take_bullet_dir", info["pos"], info["amount"], info["dir"])
		res["hit"] = true
		res["dealt"] = info["amount"]
	elif target.has_method("take_bullet"):
		target.call("take_bullet", info["pos"], info["amount"])
		res["hit"] = true
		res["dealt"] = info["amount"]
	res["crit"] = bool(info.get("crit", false)) and bool(res["hit"])
	return res

## Efekt trafienia u wszystkich peerów + hitmarker dla strzelca.
static func report(info: Dictionary, res: Dictionary) -> void:
	if not bool(res.get("hit", false)):
		return
	Arsenal.broadcast_hit(info["pos"], info["dir"], int(res.get("mat", 0)), bool(res.get("crit", false)), bool(info.get("heavy", false)))
	var kind := Arsenal.Confirm.HIT
	if bool(res.get("killed", false)):
		kind = Arsenal.Confirm.KILL
	elif bool(res.get("crit", false)):
		kind = Arsenal.Confirm.CRIT
	elif int(res.get("mat", 0)) == Arsenal.Mat.ARMOR:
		kind = Arsenal.Confirm.ARMOR
	Arsenal.confirm(int(info.get("shooter", 0)), kind, info["pos"])

static func apply_and_report(target: Node, info: Dictionary) -> Dictionary:
	var res := apply(target, info)
	report(info, res)
	return res

# ---------------------------------------------------------------- promień (hitscan)

## Ślad promienia z przebiciem. Zwraca:
##   end    gdzie promień się kończy (ściana, limit przebić albo zasięg)
##   hits   [{collider, pos, normal, dist}] — cele w kolejności od lufy
##   wall   true, jeśli zatrzymała go ściana
##   wall_pos / wall_normal  punkt i normalna ściany (gdy wall)
## `pierce` = ile dodatkowych celów przebija, `wall_px` = ile px ściany przebija (RAIL).
static func trace(space: PhysicsDirectSpaceState2D, from: Vector2, dir: Vector2, length: float,
		pierce: int, wall_px: float = 0.0, exclude: Array[RID] = []) -> Dictionary:
	var out := {"end": from + dir * length, "hits": [], "wall": false, "wall_pos": Vector2.ZERO, "wall_normal": Vector2.ZERO}
	var ex: Array[RID] = exclude.duplicate()
	var cur := from
	var left := length
	var targets_hit := 0
	var wall_budget := wall_px
	var guard := 0
	while left > 0.5 and guard < 64:
		guard += 1
		var q := PhysicsRayQueryParameters2D.create(cur, cur + dir * left, LAYER_WORLD | LAYER_TARGET)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		var p: Vector2 = hit["position"]
		var n: Vector2 = hit["normal"]
		var is_target: bool = collider is Node and (collider as Node).is_in_group("enemies") and not (collider is TileMapLayer)
		if not is_target:
			# ściana: przebij cienką warstwę, jeśli broń pozwala
			if wall_budget > 0.0:
				var depth := _wall_depth(space, p, dir, wall_budget)
				if depth > 0.0:
					wall_budget -= depth
					cur = p + dir * (depth + 0.5)
					left = length - (cur - from).length()
					ex = ex.duplicate()
					continue
			out["end"] = p
			out["wall"] = true
			out["wall_pos"] = p
			out["wall_normal"] = n
			return out
		(out["hits"] as Array).append({"collider": collider, "pos": p, "normal": n, "dist": (p - from).length()})
		ex.append(hit["rid"])
		targets_hit += 1
		if targets_hit > pierce:
			out["end"] = p
			return out
		# przesuń minimalnie za trafiony cel; wyłączenie RID i tak go pomija
		left = length - (p - from).length()
		cur = p
	return out

## Grubość ściany od punktu wejścia (px), jeśli mieści się w limicie; 0 = zbyt gruba.
static func _wall_depth(space: PhysicsDirectSpaceState2D, enter: Vector2, dir: Vector2, limit: float) -> float:
	var step := 2.0
	var d := step
	while d <= limit:
		var q := PhysicsRayQueryParameters2D.create(enter + dir * d, enter + dir * (d + step), LAYER_WORLD)
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return d
		d += step
	return 0.0

## Środek sylwetki celu (do stożków i wybuchów).
static func center_of(n: Node2D) -> Vector2:
	if n.has_method("body_center"):
		return n.call("body_center")
	return n.global_position + Vector2(0, -8)

## Czy między dwoma punktami nie ma ściany (ciosy i płomień nie sięgają przez mur).
static func clear_line(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(a, b, LAYER_WORLD)
	return space.intersect_ray(q).is_empty()

## Cele w stożku (cios, płomień): w zasięgu `reach`, w kącie ±half_deg od `dir`, w linii wzroku.
static func in_cone(tree: SceneTree, space: PhysicsDirectSpaceState2D, origin: Vector2, dir: Vector2,
		reach: float, half_deg: float) -> Array:
	var found: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		var c := center_of(n)
		var v := c - origin
		var rad: float = n.call("hit_radius") if n.has_method("hit_radius") else 6.0
		var dist := v.length()
		if dist - rad > reach:
			continue
		if dist > 1.0 and absf(rad_to_deg(dir.angle_to(v))) > half_deg + rad_to_deg(atan2(rad, dist)):
			continue
		if not clear_line(space, origin, c):
			continue
		found.append(n)
	return found

# ---------------------------------------------------------------- wybuch

## Wybuch obszarowy (serwer). Wrogowie i obiekty: obrażenia malejące do brzegu (BLAST_EDGE),
## drużyna: 1 HP w promieniu (GDD §6: „friendly fire 100%"; żadna broń palna nie rani kolegów,
## ale wybuch tak — filar 3). Hałas = N_GRENADE, więc granat jest też wabikiem.
static func explode(tree: SceneTree, pos: Vector2, radius: float, damage: float, shooter: int, w: int,
		silent_for_noise := false) -> void:
	if not NoiseMgr.is_server():
		return
	if not silent_for_noise:
		NoiseMgr.add_noise(NoiseMgr.N_GRENADE, pos)
	Arsenal.broadcast_explosion(pos, radius)
	var d: RefCounted = Weapons.def(w)
	for e in tree.get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var c := center_of(n)
		var dist := c.distance_to(pos)
		if dist > radius:
			continue
		var f := lerpf(1.0, BLAST_EDGE, dist / radius)
		var away := (c - pos)
		away = away.normalized() if away.length() > 0.5 else Vector2.UP
		var info := make_info(w, damage * f, c, away, shooter, "blast")
		info["knock"] = d.knock * f
		info["stun"] = d.stun * f
		info["heavy"] = true
		var res := apply(n, info)
		if bool(res["hit"]) and bool(res["killed"]):
			Arsenal.confirm(shooter, Arsenal.Confirm.KILL, c)
		elif bool(res["hit"]):
			Arsenal.confirm(shooter, Arsenal.Confirm.HIT, c)
	for p in tree.get_nodes_in_group("players"):
		if p.dead:
			continue
		if (p.global_position + Vector2(0, -8)).distance_to(pos) <= radius * 0.9:
			p.deliver_hit(1, pos)
