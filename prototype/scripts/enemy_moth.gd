extends "res://scripts/enemy_behavior.gd"
## Ćma (GDD §7.1): wisi pod sufitem (śpi), dopóki w zasięgu nie pojawi się światło (flara, ogień, latarka, błysk z lufy, wiązka LR-7); wtedy leci na nie falistym
## lotem. Flara ją spala, latarka — kąsa gracza. Bez światła wraca pod sufit i znów zasypia. Cały tik ćmy to `tick_special`.

const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")

const MOTH_SEEK_R := 420.0           ## z tej odległości ćma wyczuwa światło
const MOTH_BURN_DPS := 6.0           ## spalanie przy flarze

var t_moth := 0.0

func derive_pre() -> int:
	return e.Ai.FLY if e.active else e.Ai.HANG

func anim(a: String, _moving: bool) -> String:
	return "idle" if e.active else a          # trzepocze skrzydłami w locie

func tick_special(delta: float) -> bool:
	_moth_tick(delta)
	return true

## Najbliższe źródło światła dla ćmy: flara albo włączona latarka gracza (w promieniu `max_r`).
func nearest_light(max_r: float) -> Dictionary:
	var best := {}
	var best_d := max_r
	for f in e.get_tree().get_nodes_in_group("flares"):
		var d: float = e.global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = {"pos": f.global_position, "kind": "flare", "node": f}
	for fp in e.get_tree().get_nodes_in_group("fire_patches"):
		var df: float = e.global_position.distance_to(fp.global_position)
		if df < best_d:
			best_d = df
			best = {"pos": fp.global_position + Vector2(0, -4), "kind": "flare", "node": fp}       # ogień na podłodze spala ćmę jak flara
	for f in Lights.active_flashes():
		var shooter: Node = f["node"]
		if shooter == null or not is_instance_valid(shooter):
			continue
		var d3: float = e.global_position.distance_to(f["pos"])
		if d3 < best_d:
			best_d = d3
			best = {"pos": f["pos"], "kind": "player", "node": shooter}                             # błysk z lufy: ćma leci na strzelca
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.dead or not (p.flashlight or beam_lit(p)):
			continue
		var d2: float = e.global_position.distance_to(p.global_position)
		if d2 < best_d:
			best_d = d2
			best = {"pos": p.global_position + Vector2(0, -8), "kind": "player", "node": p}
	return best

## Gracz strzela wiązką (LR-7): świeci jak latarka, ćmy lecą na tę wiązkę.
func beam_lit(p: Node) -> bool:
	return bool(p.w_firing) and Weapons.def(int(p.weapon)).kind == Weapons.Kind.BEAM

## Ćma: wisi (śpi), dopóki w zasięgu nie pojawi się światło; wtedy leci na nie falistym lotem.
## Flara ją spala, latarka — kąsa gracza. Bez światła wraca pod sufit.
func _moth_tick(delta: float) -> void:
	t_moth += delta
	e._cd = maxf(0.0, e._cd - delta)
	var lt := nearest_light(MOTH_SEEK_R)
	if not e.active:
		e.velocity = Vector2.ZERO
		if not lt.is_empty():
			e.wake()
		e._send_state(delta)
		return
	var speed: float = float(e._def["speed"]) * Difficulty.m("enemy_speed")
	var want := Vector2.ZERO
	if not lt.is_empty():
		e._lose_t = 0.0
		var tp: Vector2 = lt["pos"]
		var to: Vector2 = tp - e.global_position
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		want = dir * speed + Vector2(-dir.y, dir.x) * sin(t_moth * 9.0 + float(e.get_instance_id() % 5)) * speed * 0.6
		if lt["kind"] == "flare" and dist < 14.0:
			e.hp -= MOTH_BURN_DPS * delta                 # krąży przy płomieniu i się spala
			want = Vector2(-dir.y, dir.x) * speed * 0.7
			if e.hp <= 0.0:
				e._die()
				return
		elif lt["kind"] == "player" and dist < 12.0 and e._cd <= 0.0:
			var pl: Node = lt["node"]
			pl.deliver_hit(e._scaled_damage(1), e.global_position, e.kind)
			e._cd = float(e._def["cooldown"]) * Difficulty.m("enemy_cd")
	else:
		e._lose_t += delta
		want = Vector2(sin(t_moth * 3.1), cos(t_moth * 2.3)) * speed * 0.35
		if e._lose_t > 6.0:
			# światło zgasło: wraca pod sufit i znów zasypia
			var back: Vector2 = e._home - e.global_position
			want = back.normalized() * speed * 0.7
			if back.length() < 8.0:
				e.active = false
				e.velocity = Vector2.ZERO
				e.global_position = e._home
				e._lose_t = 0.0
	e.velocity = e.velocity.lerp(want, 0.18)
	if e.is_on_wall() or e.is_on_ceiling():
		e.velocity.y += 25.0 * (-1.0 if e.is_on_floor() else 1.0)
	e.move_and_slide()
	e._send_state(delta)
