extends Node
## Test headless strzelnicy FPP (RANGE_FPS_PLAN.md, etap 0):
##
##   godot --headless --path . -- --host --rangetest --autoquit=40
##
## Kryjówka, gracz wchodzi na strzelnicę (fp_mode.gd) i strzela tym samym kontrolerem broni co na misji (sim_fire):
## 1. Pięć strzałów w środki blach z M-83 przewraca pięć blach, stoper daje czas przebiegu, po RESET_T s blachy wstają.
## 2. Podrzut unosi linię strzału: seria bez ściągania trafia wyżej niż pierwszy strzał.
## 3. Amunicja ćwiczebna: przeładowanie nie zmienia zapasu, strzały nie zużywają broni; magazynek ubywa jak w grze.
## 4. Oparcie przy ławie (przyklęk) to `wc.braced` — jak oparcie o krawędź w grze.
## 5. Wyjście przywraca zwykłe strzelanie (range_sink, practice, player.fp).
## Wynik: linie [RANGE-TEST] i kod wyjścia (0 = OK).

const FpMode := preload("res://scripts/range3d/fp_mode.gd")
const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const Weapons := preload("res://scripts/weapons.gd")

var main: Node2D
var player: CharacterBody2D
var failed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[RANGE-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[RANGE-TEST] INFO  %s" % label)

func run(m: Node2D) -> void:
	main = m
	Profile.persist = false
	await get_tree().create_timer(1.5).timeout
	player = m.get_node("Players").get_node_or_null("1")
	check("kryjówka i gracz", player != null)
	if player == null:
		_finish()
		return
	await _t_static()
	await _t_plates()
	await _t_climb()
	await _t_practice()
	await _t_brace()
	await _t_leave()
	_finish()

func _finish() -> void:
	print("[RANGE-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	get_tree().quit(1 if failed > 0 else 0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Geometria i stożek rozrzutu bez gracza.
func _t_static() -> void:
	var sim := RangeSim.new()
	var eye := Vector3(0.0, RangeSim.EYE_STAND, 0.0)
	var h := sim.trace(eye, sim.aim_at(eye, 2))
	check("promień w środek blachy 3 trafia blachę 3", h.get("kind") == "plate" and int(h.get("index", -1)) == 2)
	var miss := sim.trace(eye, Vector3(0.0, 0.0, -1.0))
	check("promień prosto w tunel trafia kulochwyt (%s)" % miss.get("kind"), miss.get("kind") == "backstop")
	var down := sim.trace(eye, Vector3(0.0, -1.0, -0.2).normalized())
	check("promień w dół trafia ławę (%s)" % down.get("kind"), down.get("kind") == "bench")
	var d := Weapons.def(Weapons.M83)
	var worst := 0.0
	for s in 200:
		for v in RangeSim.pellet_dirs3(d, Basis.IDENTITY, s, 0.0):
			worst = maxf(worst, rad_to_deg((v as Vector3).angle_to(Vector3.FORWARD)))
	check("stożek M-83 nie szerszy niż jitter (%.2f° ≤ %.2f°)" % [worst, d.jitter_deg], worst <= d.jitter_deg + 0.01)
	var sg := Weapons.def(Weapons.SPREAD12)
	var dirs := RangeSim.pellet_dirs3(sg, Basis.IDENTITY, 7, 0.0)
	var wide := 0.0
	for v in dirs:
		wide = maxf(wide, rad_to_deg((v as Vector3).angle_to(Vector3.FORWARD)))
	check("SPREAD-12: %d śrucin, najdalsza %.1f° ≤ %.1f°" % [dirs.size(), wide, sg.cone_half_deg(0.0)], dirs.size() == sg.pellets and wide <= sg.cone_half_deg(0.0) + 0.01)

## Strzał przez kontroler broni w środek blachy `i` (bez podrzutu i rozrzutu z serii).
func _shoot_at(fp: Node, i: int) -> void:
	var wc = player.weapons
	var dir: Vector3 = fp.sim.aim_at(fp.eye(), i)
	fp.yaw = atan2(-dir.x, -dir.z)
	fp.pitch = asin(dir.y)
	wc.climb = 0.0
	wc.bloom = 0.0
	wc.cd = 0.0
	wc.sim_fire = true                                          # M-83 jest automatyczny: strzela przytrzymany spust — jedna klatka = jeden strzał
	await _frames(2)
	wc.sim_fire = false
	await _frames(2)

func _t_plates() -> void:
	var wc = player.weapons
	wc.select_slot(0)
	await _frames(2)
	if int(wc.cur().id) != Weapons.M83:
		wc.loadout[0] = Weapons.M83
		wc.select_slot(0)
	await get_tree().create_timer(1.0).timeout                  # dobycie broni
	wc.mags[Weapons.M83] = 30
	wc.jams.clear()
	var fp: Node = FpMode.enter(player)
	await _frames(2)
	check("wejście: player.fp, range_sink i amunicja ćwiczebna", player.fp == fp and wc.range_sink == fp and wc.practice)
	var mag0: int = wc.mag_of(Weapons.M83)
	var cond0: float = wc.condition_of(Weapons.M83)
	# do skutku, jak gracz: na 16–20 m stożek M-83 (0,8°) jest szerszy niż blacha (⌀ 30 cm), więc część kul chybia
	var tries: Array = []
	for i in fp.sim.plates.size():
		var n := 0
		while not fp.sim.plates[i]["down"] and n < 12:
			await _shoot_at(fp, i)
			wc.jams.clear()
			n += 1
		tries.append(n)
	info("strzały na blachę (7/10/13/16/20 m): %s" % str(tries))
	var down := 0
	for p in fp.sim.plates:
		if p["down"]:
			down += 1
	check("blachy: %d/5 leży" % down, down == 5)
	check("przebieg ukończony, czas %.2f s" % fp.sim.last_time, fp.sim.runs == 1 and fp.sim.last_time > 0.0 and fp.sim.best == fp.sim.last_time)
	check("magazynek: %d → %d po %d strzałach (jak w grze)" % [mag0, wc.mag_of(Weapons.M83), fp.shots_fired], wc.mag_of(Weapons.M83) == mag0 - fp.shots_fired)
	check("strzały nie zużywają broni (%.2f → %.2f)" % [cond0, wc.condition_of(Weapons.M83)], is_equal_approx(cond0, wc.condition_of(Weapons.M83)))
	await get_tree().create_timer(RangeSim.RESET_T + 0.3).timeout
	var up: bool = fp.sim.plates.all(func(p: Dictionary) -> bool: return not p["down"])
	check("po %.0f s blachy wstają" % RangeSim.RESET_T, up)
	fp.leave()
	await _frames(2)

## Podrzut: pięć strzałów ogniem ciągłym bez ruchu myszy — ostatni trafia wyżej niż pierwszy.
func _t_climb() -> void:
	var wc = player.weapons
	if not wc.climb_mode() and not Settings.realistic_handling:
		info("obsługa CLASSIC — pomijam podrzut")
		return
	var fp: Node = FpMode.enter(player)
	await _frames(2)
	fp.yaw = 0.0
	fp.pitch = 0.0
	wc.climb = 0.0
	wc.bloom = 0.0
	wc.mags[Weapons.M83] = 30
	wc.jams.clear()
	var ys: Array = []
	fp.sim.impact.connect(func(pos: Vector3, _n: Vector3, kind: String, _i: int) -> void:
		if kind == "backstop":
			ys.append(pos.y))
	wc.sim_fire = true
	var t := 0.0
	while ys.size() < 6 and t < 3.0:
		wc.jams.clear()
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	wc.sim_fire = false
	check("seria 6 strzałów do kulochwytu (%d)" % ys.size(), ys.size() >= 6)
	if ys.size() >= 6:
		# średnie, nie pojedyncze trafienia: rozrzut (0,8° + narastający w serii) na 30 m jest rzędu podrzutu z 4 strzałów; dłuższa seria
		# (ok. 4°) idzie już w strop tunelu
		var first := (float(ys[0]) + float(ys[1])) / 2.0
		var last := (float(ys[4]) + float(ys[5])) / 2.0
		check("podrzut: strzały 5–6 średnio %.2f m wyżej niż 1–2 (climb %.2f°)" % [last - first, wc.climb], last > first + 0.15 and wc.climb > 1.5)
	fp.leave()
	await _frames(2)

func _t_practice() -> void:
	var wc = player.weapons
	var fp: Node = FpMode.enter(player)
	await _frames(2)
	wc.mags[Weapons.M83] = 3
	wc.jams.clear()
	var res0: int = Arsenal.get_reserve(Weapons.M83, wc.ammo_of(Weapons.M83))
	wc.try_reload()
	await get_tree().create_timer(wc.cur().full_reload_time() + 1.2).timeout
	check("przeładowanie na strzelnicy: magazynek %d" % wc.mag_of(Weapons.M83), wc.mag_of(Weapons.M83) >= wc.cur().mag)
	check("zapas bez zmian (%d → %d)" % [res0, Arsenal.get_reserve(Weapons.M83, wc.ammo_of(Weapons.M83))], Arsenal.get_reserve(Weapons.M83, wc.ammo_of(Weapons.M83)) == res0)
	var mags_on_map := get_tree().get_nodes_in_group("pickups").filter(func(it: Node) -> bool: return it.get("kind") == "mag")
	check("magazynek z resztkami nie ląduje w kryjówce (%d)" % mags_on_map.size(), mags_on_map.is_empty())
	fp.leave()
	await _frames(2)

func _t_brace() -> void:
	var wc = player.weapons
	var fp: Node = FpMode.enter(player)
	await _frames(2)
	Input.action_press("crouch")
	await get_tree().create_timer(0.6).timeout
	check("przyklęk przy ławie: oparcie (braced %s, oczy %.2f m)" % [wc.braced, fp.eye().y], wc.braced and fp.eye().y < RangeSim.EYE_STAND - 0.3)
	Input.action_release("crouch")
	await get_tree().create_timer(0.6).timeout
	check("wstanie: bez oparcia", not wc.braced)
	fp.leave()
	await _frames(2)

func _t_leave() -> void:
	var wc = player.weapons
	var fp: Node = FpMode.enter(player)
	await _frames(2)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(3)
	check("[E] wychodzi: zwykłe strzelanie wraca", player.fp == null and wc.range_sink == null and not wc.practice and not is_instance_valid(fp))
