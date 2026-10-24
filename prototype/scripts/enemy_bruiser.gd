extends "res://scripts/enemy_behavior.gd"
## Wołek i Rzeźnik (GDD §7.1–7.2, bruiser; Rzeźnik to te same fazy z danymi `charge`, `throws: false`, `breaks_barricades`): szarża z zapowiedzią (rozbija skrzynie i beczki, o ścianę się ogłusza), rzut skrzynią także w górę i w dół oraz — gdy w pobliżu nie
## ma skrzyni — rzut głazem (F3.9; 0,5 HP, przerwa wg trudności). Stan replikowany (`_sp`: 0 nic, 1 zapowiedź szarży, 2 szarża, 3 zapowiedź rzutu, 4 ogłuszony)
## zostaje w `enemy.gd`; tu są liczniki i logika faz. Dane w `enemy_defs.gd`: `boulder`.

const CHARGE_WINDUP := 0.7
const CHARGE_TIME := 0.9
const CHARGE_MULT := 3.4
const CHARGE_CD := 7.0
const THROW_WINDUP := 0.8
const THROW_CD := 6.0
const THROW_DY_MAX := 160.0          ## px różnicy poziomów, z której Wołek jeszcze rzuca skrzynią (w górę i w dół; ok. 10 kafli)
const CRASH_STUN := 1.3
const RUN_CHECK_MAX := 280.0         ## px: tyle rozbiegu sprawdzamy przed szarżą (ściana i podłoga)
const RUN_FLOOR_STEP := 16.0         ## px: co tyle sprawdzamy, czy pod rozbiegiem jest podłoga (kafel)
const RUN_FLOOR_DEPTH := 28.0        ## px w dół od poziomu stóp: głębiej to już przepaść, nie stopień

var sp_t := 0.0
var sp_dir := 1.0
var sp_crate: Node = null
var sp_boulder := false      ## zapowiedź rzutu (`_sp` 3) dotyczy głazu, nie skrzyni (F3.9)
var boulder_cd := 2.0        ## przerwa między głazami (wg trudności, `enemy_defs.gd: boulder.cd`)
var charge_cd := 3.0
var throw_cd := 2.0
var charge_hit := false

## Parametr szarży z danych rodzaju (`charge`: min, max, windup, time, mult, cd, crash_stun, damage); brak wpisu = stałe Wołka. Dzięki temu Rzeźnik to ten sam kod z innymi liczbami.
func _c(key: String, base: float) -> float:
	return float((e._def.get("charge", {}) as Dictionary).get(key, base))

func reset() -> void:
	e._sp = 0
	sp_crate = null
	sp_boulder = false
	boulder_cd = 2.0
	charge_cd = 3.0
	throw_cd = 2.0

## Zwraca true, gdy faza specjalna przejęła ruch w tej klatce.
func tick_phase(delta: float, target: Node2D) -> bool:
	charge_cd = maxf(0.0, charge_cd - delta)
	throw_cd = maxf(0.0, throw_cd - delta)
	boulder_cd = maxf(0.0, boulder_cd - delta)
	match e._sp:
		0:
			if target == null or e._windup > 0.0 or e._stagger > 0.0 or e._panic > 0.0:
				return false
			var d: Vector2 = target.global_position - e.global_position
			var level := absf(d.y) <= 24.0
			var ax := absf(d.x)
			if level and ax > _c("min", 100.0) and ax < _c("max", 280.0) and charge_cd <= 0.0 and _run_clear(signf(d.x), ax):
				e._sp = 1
				sp_t = _c("windup", CHARGE_WINDUP) * Difficulty.m("enemy_windup")
				sp_dir = signf(d.x)
				charge_hit = false
				e.winding = true
				return true
			# rzut skrzynią także w górę i w dół (Wołek nie jest bezradny wobec gracza na półce nad nim czy w dole): do THROW_DY_MAX px różnicy
			# poziomów, a cel prawie nad / pod nim (ax < 60) też jest w zasięgu; łuk balistyczny liczy `_throw_crate`
			if bool(e._def.get("throws", true)) and ax < 220.0 and (ax > 60.0 or not level) and absf(d.y) <= THROW_DY_MAX:
				var c := _find_crate()
				if c != null:
					if throw_cd <= 0.0 and _throw_clear(target):
						e._sp = 3
						sp_t = THROW_WINDUP * Difficulty.m("enemy_windup")
						sp_dir = signf(d.x) if absf(d.x) > 1.0 else e._facing
						sp_crate = c
						sp_boulder = false
						e.winding = true
						return true
				elif _boulder_ready(ax) and _throw_clear(target):
					# głaz (F3.9): zawsze pod ręką, gdy w pobliżu nie ma skrzyni — słabszy, ale częstszy; przerwa zależy od trudności
					e._sp = 3
					sp_t = float(e._def["boulder"].get("windup", 0.6)) * Difficulty.m("enemy_windup")
					sp_dir = signf(d.x) if absf(d.x) > 1.0 else e._facing
					sp_crate = null
					sp_boulder = true
					e.winding = true
					return true
			return false
		1:
			e.velocity.x = 0.0
			sp_t -= delta
			if sp_t <= 0.0:
				e._sp = 2
				sp_t = _c("time", CHARGE_TIME)
				e.winding = false
				e.visual_attack()
			return true
		2:
			sp_t -= delta
			e.velocity.x = sp_dir * float(e._def["speed"]) * Difficulty.m("enemy_speed") * _c("mult", CHARGE_MULT)
			if sp_t <= 0.0:
				_end_charge()
			return true
		3:
			e.velocity.x = 0.0
			sp_t -= delta
			if sp_t <= 0.0:
				_throw_crate(target)
			return true
		4:
			e.velocity.x = 0.0
			sp_t -= delta
			if sp_t <= 0.0:
				e._sp = 0
				e.winding = false
			return true
	return false

## Czy przed Wołkiem jest wolna droga na rozbieg: bez ściany na całym dystansie szarży i z podłogą pod każdym kaflem (nie rozpędza się w przepaść).
func _run_clear(dir: float, dist: float) -> bool:
	var space: PhysicsDirectSpaceState2D = e.get_world_2d().direct_space_state
	var run := minf(dist, _c("max", RUN_CHECK_MAX))
	var from: Vector2 = e.global_position + Vector2(0, -10)
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * run, 0), 1)).is_empty():
		return false
	var x := RUN_FLOOR_STEP
	while x <= run:
		var top: Vector2 = e.global_position + Vector2(dir * x, -4.0)
		var fq := PhysicsRayQueryParameters2D.create(top, top + Vector2(0, RUN_FLOOR_DEPTH), 1 | (1 << (e.PLATFORM_BIT - 1)))
		if space.intersect_ray(fq).is_empty():
			return false
		x += RUN_FLOOR_STEP
	return true

func _end_charge() -> void:
	e._sp = 0
	e.winding = false
	charge_cd = _c("cd", CHARGE_CD) * Difficulty.m("enemy_cd")

## Po ruchu: szarża rozbija skrzynie, detonuje beczki (wybuch rani też Wołka), uderza gracza; ściana ogłusza.
func after_phase_move() -> void:
	if e._sp != 2:
		return
	var crashed := false
	for i in e.get_slide_collision_count():
		var c: KinematicCollision2D = e.get_slide_collision(i)
		var col := c.get_collider() as Node
		if col == null:
			continue
		if col.is_in_group("props"):
			if col.has_method("take_bullet"):
				col.take_bullet(e.global_position, 45.0)
		elif bool(e._def.get("breaks_barricades", false)) and col.get_parent() != null and col.get_parent().is_in_group("breakables"):
			col.get_parent().take_hit({"type": "blast", "amount": 400.0})        # Rzeźnik przebija zamurowane przejścia (`brick_wall.gd`) zamiast się o nie ogłuszać
		elif absf(c.get_normal().x) > 0.7:
			crashed = true
	if not charge_hit:
		for p in e.get_tree().get_nodes_in_group("players"):
			if not p.dead and absf(p.global_position.x - e.global_position.x) < 16.0 and absf(p.global_position.y - e.global_position.y) < 18.0:
				p.deliver_hit(e._scaled_damage(int(_c("damage", 2.0))), e.global_position, e.kind)
				charge_hit = true
	if crashed:
		_crash()

func _crash() -> void:
	e._sp = 4
	sp_t = _c("crash_stun", CRASH_STUN)
	e.winding = false
	charge_cd = _c("cd", CHARGE_CD) * Difficulty.m("enemy_cd")
	e.velocity.x = -sp_dir * 40.0
	NoiseMgr.add_noise(7.0, e.global_position)
	if NoiseMgr.has_network():
		e._crash_fx.rpc()
	else:
		e._crash_fx()

func _find_crate() -> Node:
	var best: Node = null
	var best_d := 60.0
	for p in e.get_tree().get_nodes_in_group("props"):
		if p.get("kind") != "crate" or p.get("exploded") or float(p.get("thrown_t")) > 0.0:
			continue
		var dx: float = absf(p.global_position.x - e.global_position.x)
		if dx < best_d and absf(p.global_position.y - e.global_position.y) < 30.0:
			best_d = dx
			best = p
	return best

## Czy między wrogiem (wysokość ramienia) a celem nie ma ściany — nie zaczyna rzutu w mur (skrzynia i tak poleciałaby łukiem, ale w zamknięty strop nie ma sensu).
func _throw_clear(target: Node2D) -> bool:
	var from: Vector2 = e.global_position + Vector2(0, -26.0)
	var q := PhysicsRayQueryParameters2D.create(from, target.global_position + Vector2(0, -10.0), 1)
	return e.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## Czy Wołek ma teraz prawo rzucić głazem: rodzaj ma wpis `boulder`, przerwa minęła, a cel jest w jego poziomym zasięgu (`range`).
func _boulder_ready(ax: float) -> bool:
	var cfg := e._def.get("boulder", {}) as Dictionary
	return not cfg.is_empty() and boulder_cd <= 0.0 and ax < float(cfg.get("range", 220.0))

## Przerwa po rzucie głazem wg poziomu trudności (tabela `cd` = [EASY, NORMAL, HARD] — osobne wartości, nie mnożnik `enemy_cd`).
static func boulder_cooldown(cfg: Dictionary, level: int) -> float:
	var cds: Array = cfg.get("cd", [5.0])
	return float(cds[clampi(level, 0, cds.size() - 1)])

## Rzut głazem: ten sam łuk balistyczny co skrzynia (grawitacja 980), ale pocisk to lekki węzeł `boulder.gd` zadający 0,5 HP i znikający po uderzeniu.
func _throw_boulder(target: Node2D) -> void:
	var cfg := e._def.get("boulder", {}) as Dictionary
	e._sp = 0
	sp_boulder = false
	e.winding = false
	boulder_cd = boulder_cooldown(cfg, Difficulty.level)
	if target == null or not is_instance_valid(target):
		return
	var from: Vector2 = e.global_position + Vector2(sp_dir * 10.0, -26.0)
	var aim: Vector2 = (target.global_position + Vector2(0, -10.0)) - from
	var t := clampf(maxf(absf(aim.x) / 360.0, absf(aim.y) / 500.0), 0.35, 0.8)
	var vel := Vector2(clampf(aim.x / t, -420.0, 420.0), (aim.y - 0.5 * 980.0 * t * t) / t)
	var lvl = e.get_tree().get_first_node_in_group("level")
	if lvl != null and lvl.has_method("spawn_boulder"):
		lvl.spawn_boulder(from, vel, float(cfg.get("dmg", 0.5)))
		e.visual_attack()
	NoiseMgr.add_noise(float(cfg.get("noise", 2.0)), e.global_position)

## Rzut: balistyczny łuk w gracza (grawitacja ciał fizycznych 980), skrzynia rani przy trafieniu (prop.gd).
func _throw_crate(target: Node2D) -> void:
	if sp_boulder:
		_throw_boulder(target)
		return
	var crate := sp_crate
	e._sp = 0
	e.winding = false
	throw_cd = THROW_CD * Difficulty.m("enemy_cd")
	sp_crate = null
	if crate == null or not is_instance_valid(crate) or crate.exploded or target == null or not is_instance_valid(target):
		return
	var from: Vector2 = e.global_position + Vector2(sp_dir * 10.0, -26.0)
	var aim: Vector2 = (target.global_position + Vector2(0, -10.0)) - from
	var t := clampf(maxf(absf(aim.x) / 300.0, absf(aim.y) / 500.0), 0.3, 0.9)        # rzut pionowy dostaje więcej czasu lotu (mniejsza prędkość początkowa)
	var vel := Vector2(clampf(aim.x / t, -420.0, 420.0), (aim.y - 0.5 * 980.0 * t * t) / t)
	crate.throw_to(from, vel)
	e.visual_attack()
	NoiseMgr.add_noise(4.0, e.global_position)

