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
## 6. Etap 1: drzwi w kryjówce (range_door.gd) — [E] przy drzwiach wchodzi, postać zaparkowana (`in_range`), wynik przebiegu trafia
##    na tablicę drużyny przez serwer; serwer odrzuca wynik niewiarygodny, z innej broni i od gracza spoza strzelnicy.
## 7. Etap 2: przyrządy z modelu (gun_proc.py → sight_rear / sight_front) leżą w osi kamery przy celowaniu, ćwiczenie z przeładowaniem
##    (4 blachy, 2 naboje w magazynku, wynik z przeładowaniem na osobnej części tablicy), rekordy osobiste broni w profilu (czas, grupa).
## Wynik: linie [RANGE-TEST] i kod wyjścia (0 = OK).

const RangeDoor := preload("res://scripts/range3d/range_door.gd")
const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Actions := preload("res://scripts/actions.gd")
const RangeView := preload("res://scripts/range3d/range_view.gd")
const Char3D := preload("res://scripts/char3d.gd")

var main: Node2D
var player: CharacterBody2D
var door: Node2D
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
	Profile.range_best = {}                                    # rekordy osobiste z prawdziwego profilu nie mieszają się do testu
	await get_tree().create_timer(1.5).timeout
	player = m.get_node("Players").get_node_or_null("1")
	door = get_tree().get_first_node_in_group("range_door") as Node2D
	check("kryjówka, gracz i drzwi strzelnicy", player != null and door != null)
	if player == null or door == null:
		_finish()
		return
	door.board = []                                              # tablica z ustawień gracza (Settings.range_board) nie miesza się do testu
	await _t_static()
	_t_sights()
	_t_records()
	await _t_door()
	await _t_options()
	await _t_plates()
	_t_special_sim()
	_t_extras_sim()
	await _t_special_hook()
	await _t_coop_pose()
	await _t_server()
	await _t_drill()
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

## Przyrządy celownicze: przy pełnym celowaniu szczerbinka i muszka modelu (gun_<klucz>.json z gun_proc.py) leżą na osi kamery (x = y = 0,
## przed okiem, muszka dalej) — linia przyrządów to linia strzału ze środka ekranu.
func _t_sights() -> void:
	var bad := PackedStringArray()
	var n := 0
	for key in ["m83", "spread12", "p64", "sokol6", "gniew4"]:
		var inf: Dictionary = Char3D.gun_info(key)
		if not inf.has("sight_rear") or not inf.has("sight_front"):
			bad.append("%s: brak punktów" % key)
			continue
		var ap: Array = RangeView.ads_pose(inf, 0.0, RangeView.ADS_GRIP_Z)
		var rot := Basis(Vector3.RIGHT, -float(ap[1]))
		var o: Vector3 = ap[0]
		var pr := rot * (o + RangeView.GUN_BASIS * (inf["sight_rear"] as Vector3))
		var pf := rot * (o + RangeView.GUN_BASIS * (inf["sight_front"] as Vector3))
		var off := maxf(Vector2(pr.x, pr.y).length(), Vector2(pf.x, pf.y).length())
		if off > 0.0005 or not (pf.z < pr.z and pr.z < 0.0):
			bad.append("%s: odchyłka %.1f mm, z %.3f / %.3f" % [key, off * 1000.0, pr.z, pf.z])
		n += 1
	check("przyrządy z modelu w osi kamery przy celowaniu (%d broni)%s" % [n, (": " + ", ".join(bad)) if not bad.is_empty() else ""], bad.is_empty() and n == 5)
	var opt := [String(Char3D.gun_info("gniew4").get("sight_optic", "")), String(Char3D.gun_info("sokol6").get("sight_optic", "")),
		String(Char3D.gun_info("m83").get("sight_optic", ""))]
	check("optyka na linii przyrządów: WRATH-4 %s, FALCON-6 %s (noktowizor zasłania szczerbinkę), M-83 bez (%s)" % opt, opt == ["dot", "nv", ""])
	var lr: Dictionary = Char3D.gun_info("lr7")
	check("broń bez przyrządów (LR-7): linia nad modelem, bez pochylenia", not lr.has("sight_rear") and float(RangeView.ads_pose(lr, 0.1, RangeView.ADS_GRIP_Z)[1]) == 0.0)

## Rekordy osobiste w profilu (bez zapisu do pliku w headless): mniej = lepiej, gorszy wynik nie nadpisuje, ćwiczenia i bronie osobno.
func _t_records() -> void:
	var a := Profile.range_record("plates", "test_gun", 5.0)
	var b := Profile.range_record("plates", "test_gun", 6.0)
	var c := Profile.range_record("plates", "test_gun", 4.5)
	var r := Profile.range_record("reload", "test_gun", 9.0)
	check("rekord osobisty: pierwszy %s, gorszy %s, lepszy %s → %.1f s; przeładowanie osobno %.1f s" % [a, b, c, Profile.range_best_of("plates", "test_gun"), Profile.range_best_of("reload", "test_gun")],
		a and not b and c and Profile.range_best_of("plates", "test_gun") == 4.5 and r and Profile.range_best_of("reload", "test_gun") == 9.0
		and Profile.range_best_of("plates", "other_gun") < 0.0)
	var path := "user://range_test_profile.cfg"
	Profile.save_to(path)
	Profile.range_best.clear()
	Profile.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check("rekordy osobiste zapisane w profilu i wczytane (%.1f s)" % Profile.range_best_of("plates", "test_gun"), Profile.range_best_of("plates", "test_gun") == 4.5)
	Profile.range_best.erase("plates:test_gun")
	Profile.range_best.erase("reload:test_gun")

## Sim z ustawionym zegarem przewijany krokami fizyki (pociski w locie rozstrzyga `tick`).
func _run_sim(sim: RangeSim, secs: float) -> void:
	var t := 0.0
	while t < secs:
		sim.tick(1.0 / 60.0)
		t += 1.0 / 60.0

## Bazę kierunku z oka na punkt (−z bazy = kierunek strzału).
func _aim_basis(eye: Vector3, to: Vector3) -> Basis:
	var dir := (to - eye).normalized()
	return Basis.looking_at(dir, Vector3.UP)

## Etap 3: bronie specjalne w samej symulacji tunelu (bez gracza).
func _t_special_sim() -> void:
	var eye := Vector3(0.0, RangeSim.EYE_STAND, 0.0)
	# WRATH-4: granat leci (blacha stoi zaraz po strzale), uzbrojony wybucha przy blasze 13 m; z bliska (ława, < 6,5 m) — niewypał
	var sim := RangeSim.new()
	var g4 := Weapons.def(Weapons.GNIEW4)
	var landed: Array = []
	sim.landed.connect(func(_p: Vector3, _n: Vector3, kind: String, _k: String, exploded: bool, _r: float) -> void: landed.append([kind, exploded]))
	var flights: Array = []
	sim.flight.connect(func(pts: PackedVector3Array, secs: float, _k: String) -> void: flights.append([pts.size(), secs]))
	sim.shoot(eye, _aim_basis(eye, sim.plates[2]["pos"]), g4, 1, 0.0)
	var up_now: bool = not sim.plates[2]["down"]
	_run_sim(sim, 0.6)
	check("WRATH-4: lot %.2f s (%d pkt toru), blacha 13 m stoi do uderzenia, potem wybuch i leży" % [float(flights[0][1]) if not flights.is_empty() else -1.0, int(flights[0][0]) if not flights.is_empty() else 0],
		up_now and not flights.is_empty() and float(flights[0][1]) > 0.08 and sim.plates[2]["down"] and landed.size() == 1 and bool(landed[0][1]))
	var drop_y: float = (sim.trace(eye, Vector3(0, 0, -1)).get("pos", Vector3.ZERO) as Vector3).y
	landed.clear()
	sim.shoot(eye, _aim_basis(eye, Vector3(0.0, RangeSim.BENCH_H, -2.0)), g4, 2, 0.0)
	_run_sim(sim, 0.4)
	check("WRATH-4: trafienie przed uzbrojeniem (2 m) — niewypał %s" % str(landed), landed.size() == 1 and not bool(landed[0][1]))
	# łuk: granat w poziomie opada (prawdziwe g), kula nie
	var ends: Array = []                                         # tablica, bo lambda nie zmienia zmiennych z zewnątrz
	var sim2 := RangeSim.new()
	sim2.flight.connect(func(pts: PackedVector3Array, _s: float, _k: String) -> void: ends.append(pts[pts.size() - 1]))
	sim2.shoot(eye, Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), g4, 3, -g4.jitter_deg)
	var end_y: float = (ends[0] as Vector3).y if not ends.is_empty() else eye.y
	check("WRATH-4: tor łukowy — strzał w poziomie kończy się %.2f m niżej (kula: %.2f m)" % [eye.y - end_y, eye.y - drop_y], eye.y - end_y > 0.15 and is_equal_approx(drop_y, eye.y))
	# FALCON-6: rakieta celowana obok blachy 7 m skręca na nią (naprowadzanie), bez naprowadzania by chybiła
	var sim3 := RangeSim.new()
	var f6 := Weapons.def(Weapons.SOKOL6)
	var off: Vector3 = (sim3.plates[0]["pos"] as Vector3) + Vector3(0.9, 0.0, 0.0)
	var straight := sim3.trace(eye, (off - eye).normalized())
	sim3.shoot(eye, _aim_basis(eye, off), f6, 0, -f6.jitter_deg)                     # bez rozrzutu: sam tor naprowadzania
	_run_sim(sim3, 1.0)
	check("FALCON-6: celowana 0,9 m obok blachy 7 m (prosto: %s) — skręca i ją przewraca" % straight.get("kind", "?"),
		straight.get("kind", "") != "plate" and sim3.plates[0]["down"])
	# SPECTER-1: szyna na linii dwóch blach przewraca obie jednym strzałem
	var sim4 := RangeSim.new()
	var a: Vector3 = sim4.plates[0]["pos"]
	var b: Vector3 = sim4.plates[2]["pos"]
	var dir := (b - a).normalized()
	var hits := sim4.shoot(a - dir * 2.0, Basis.looking_at(dir, Vector3.UP), Weapons.def(Weapons.WIDMO1), 0, -Weapons.def(Weapons.WIDMO1).jitter_deg)
	check("SPECTER-1: przebija — dwie blachy na linii leżą (%d trafień)" % hits.size(), sim4.plates[0]["down"] and sim4.plates[2]["down"] and hits.size() >= 3)
	# LR-7: promień grzeje blachę 7 m, aż padnie (kilka kroków); blachy 20 m nie sięga (zasięg ok. 14 m)
	var sim5 := RangeSim.new()
	var lr := Weapons.def(Weapons.LR7)
	var n := 0
	while not sim5.plates[0]["down"] and n < 20:
		sim5.shoot(eye, _aim_basis(eye, sim5.plates[0]["pos"]), lr, n, 0.0)
		sim5.tick(lr.cooldown)
		n += 1
	check("LR-7: blacha 7 m pada po %d krokach promienia (nie od pierwszego)" % n, sim5.plates[0]["down"] and n >= 3 and n <= 8)
	for i in 20:
		sim5.shoot(eye, _aim_basis(eye, sim5.plates[4]["pos"]), lr, i, 0.0)
		sim5.tick(lr.cooldown)
	var reach := sim5.beam_to.distance_to(eye)
	check("LR-7: blacha 20 m poza zasięgiem — stoi, promień kończy się po %.1f m" % reach, not sim5.plates[4]["down"] and reach < 15.0 and reach > 13.0)
	# HKM-9: płomień nie sięga najbliższej blachy (7 m), zostawia ogień na podłodze
	var sim6 := RangeSim.new()
	var hk := Weapons.def(Weapons.HKM9)
	for i in 20:
		sim6.shoot(eye, _aim_basis(eye, sim6.plates[0]["pos"]), hk, i, 0.0)
		sim6.tick(hk.cooldown)
	check("HKM-9: zasięg %.1f m — blacha 7 m stoi, ogień na podłodze (%d)" % [sim6.flame_reach, sim6.fires.size()],
		not sim6.plates[0]["down"] and sim6.flame_reach < 6.0 and sim6.fires.size() >= 2)

## Etap 3, ciąg dalszy: łuk bełtu SINEW-6, papier (seria i grupa), ruchomy cel (czas lotu kuli).
func _t_extras_sim() -> void:
	var eye := Vector3(0.0, RangeSim.EYE_STAND, 0.0)
	var c6 := Weapons.def(Weapons.CIEGNO6)
	var v := float(c6.speed) / RangeSim.PX_PER_M
	var g := float(c6.gravity) / RangeSim.PX_PER_M
	# bełt w środek blachy 13 m przelatuje pod nią (opad), z poprawką na opad ją przewraca
	var sim := RangeSim.new()
	var secs: Array = []
	sim.flight.connect(func(_pts: PackedVector3Array, s: float, _k: String) -> void: secs.append(s))
	var tgt: Vector3 = sim.plates[2]["pos"]
	sim.shoot(eye, _aim_basis(eye, tgt), c6, 0, -c6.jitter_deg)
	_run_sim(sim, 1.0)
	var low_miss: bool = not sim.plates[2]["down"]
	var dist := eye.distance_to(tgt)
	var hold := 0.5 * g * pow(dist / v, 2.0)
	sim.shoot(eye, _aim_basis(eye, tgt + Vector3(0.0, hold, 0.0)), c6, 1, -c6.jitter_deg)
	_run_sim(sim, 1.0)
	check("SINEW-6: bełt %.0f m/s leci %.2f s, w środek blachy 13 m — pod nią, z poprawką %.2f m — trafia" % [v, float(secs[0]) if not secs.is_empty() else -1.0, hold],
		low_miss and sim.plates[2]["down"] and not secs.is_empty() and float(secs[0]) > 0.3)
	# papier 25 m: seria M-83 zostawia przestrzeliny, grupa w cm i MOA; po przerwie PAPER_GAP następny strzał zaczyna nową serię
	var sp := RangeSim.new()
	var m83 := Weapons.def(Weapons.M83)
	for i in 5:
		sp.shoot(eye, _aim_basis(eye, RangeSim.PAPER), m83, 100 + i, -0.4)        # rozrzut 0,4° — przy 0,8° (ok. 35 cm na 25 m) kule wychodzą poza arkusz
		sp.tick(0.2)
	var grp := sp.paper_group()
	var max_moa := (m83.jitter_deg - 0.4) * 2.0 * 60.0 * 1.05
	check("papier: %d / 5 przestrzelin, grupa %.1f cm (%.1f MOA ≤ %.0f), pion %.1f cm" % [int(grp["n"]), float(grp["spread"]) * 100.0, float(grp["moa"]), max_moa, float(grp["vertical"]) * 100.0],
		int(grp["n"]) >= 3 and float(grp["spread"]) > 0.0 and float(grp["moa"]) <= max_moa)
	_run_sim(sp, RangeSim.PAPER_GAP + 0.2)
	sp.shoot(eye, _aim_basis(eye, RangeSim.PAPER), m83, 200, 0.0)
	check("papier: po %.0f s przerwy nowa seria (%d przestrzelina)" % [RangeSim.PAPER_GAP, sp.paper_holes.size()], sp.paper_holes.size() == 1)
	# wózek 22 m: szybka kula w blachę wózka trafia; bełt bez wyprzedzenia (lot ok. 0,7 s) mija — próba liczy się w obu
	var sm := RangeSim.new()
	var mp := Vector3(RangeSim.mover_x(sm.clock), RangeSim.MOVER_Y, RangeSim.MOVER_Z)
	sm.shoot(eye, _aim_basis(eye, mp), m83, 0, -m83.jitter_deg)
	var fast_hit: bool = sm.mover_down and sm.mover_hits == 1
	_run_sim(sm, RangeSim.MOVER_RESET + 0.1)
	var up_again: bool = not sm.mover_down
	mp = Vector3(RangeSim.mover_x(sm.clock), RangeSim.MOVER_Y, RangeSim.MOVER_Z)
	var bd := eye.distance_to(mp)
	sm.shoot(eye, _aim_basis(eye, mp + Vector3(0.0, 0.5 * g * pow(bd / v, 2.0), 0.0)), c6, 0, -c6.jitter_deg)
	_run_sim(sm, 1.2)
	check("wózek: kula M-83 trafia (%s), blacha wstaje po %.1f s (%s), bełt bez wyprzedzenia mija — trafienia %d / próby %d" % [str(fast_hit), RangeSim.MOVER_RESET, str(up_again), sm.mover_hits, sm.mover_tries],
		fast_hit and up_again and sm.mover_hits == 1 and sm.mover_tries == 2)
	var lead := RangeSim.MOVER_SPEED * bd / v
	info("wyprzedzenie bełtu na wózek %.0f m: %.2f m (lot %.2f s)" % [-RangeSim.MOVER_Z, lead, bd / v])

## Strzelnica w co-op: lokalny gracz publikuje stanowisko, kierunek patrzenia, przyklęk i licznik strzałów (replikowane) — z tego inni
## gracze rysują jego postać na sąsiednim stanowisku (range_others.gd).
func _t_coop_pose() -> void:
	var wc = player.weapons
	var fp: Node = _enter()
	await _frames(2)
	fp.yaw = 0.3
	fp.pitch = -0.1
	await _frames(3)
	var pose: Vector4 = player.range_pose
	var s0: int = player.range_shots
	wc.mags[wc.cur().id] = 30
	wc.jams.clear()
	wc.cd = 0.0
	wc.sim_fire = true
	wc.sim_press = true
	await _frames(2)
	wc.sim_fire = false
	await _frames(2)
	check("co-op: poza na strzelnicy (stanowisko %d, odchylenie %.2f, pochylenie %.2f), licznik strzałów %d → %d" % [int(pose.x), pose.y, pose.z, s0, player.range_shots],
		int(pose.x) == int(fp.station) and is_equal_approx(pose.y, 0.3) and absf(pose.z - (-0.1 + fp.climb_rad())) < 0.05 and player.range_shots > s0)
	fp.leave()
	await _frames(2)

## Etap 3 przez kontroler broni: płomień HKM-9 idzie krokami do tunelu, a serwer nie liczy go w kryjówce (bez ognia przy drzwiach).
func _t_special_hook() -> void:
	var wc = player.weapons
	var keep: int = wc.loadout[0]
	wc.loadout[0] = Weapons.HKM9
	wc.mags[Weapons.HKM9] = 80                                   # przed dobyciem: z pustym zbiornikiem dobycie zaczyna przeładowanie (2,6 s)
	wc.select_slot(1)
	await _frames(2)
	wc.select_slot(0)
	await get_tree().create_timer(0.8).timeout                  # dobycie
	var fp: Node = _enter()
	await _frames(2)
	var fires0 := get_tree().get_nodes_in_group("fire_patches").size()
	wc.sim_fire = true
	await get_tree().create_timer(1.2).timeout
	wc.sim_fire = false
	await _frames(3)
	var fires1 := get_tree().get_nodes_in_group("fire_patches").size()
	check("HKM-9 na strzelnicy (%s): płomień w tunelu (zasięg %.1f m, ogień %d), w kryjówce bez ognia (%d → %d)" % [String(wc.cur().key), fp.sim.flame_reach, fp.sim.fires.size(), fires0, fires1],
		fp.sim.flame_at > 0.0 and fp.sim.fires.size() >= 1 and fires1 == fires0)
	fp.leave()
	await _frames(2)
	wc.loadout[0] = keep
	wc.select_slot(1)
	await _frames(2)
	wc.select_slot(0)
	await get_tree().create_timer(0.8).timeout

## Wejście przez drzwi (jak [E]), bez podchodzenia.
func _enter() -> Node:
	return door.enter(player)

## [E] przy drzwiach: wejście, parkowanie postaci, to samo naciśnięcie nie wychodzi od razu; [E] w tunelu wychodzi.
func _t_door() -> void:
	player.global_position = door.global_position + Vector2(0.0, -8.0)
	player.velocity = Vector2.ZERO
	await _frames(30)                                            # opada na podłogę przy drzwiach
	check("przy drzwiach: podpowiedź [E] (local_in_range)", bool(door.local_in_range))
	var pos0 := player.global_position
	Input.action_press("interact")
	await _frames(1)
	Input.action_release("interact")
	await _frames(3)
	var fp: Node = player.fp
	check("[E] przy drzwiach: strzelnica (fp.door, in_range)", fp != null and fp.door == door and player.in_range)
	check("drzwi nie podpowiadają [E], gdy gracz jest w tunelu", not bool(door.local_in_range))
	await _frames(20)
	check("postać zaparkowana przy drzwiach (przesunięcie %.1f px)" % player.global_position.distance_to(pos0), player.global_position.distance_to(pos0) < 4.0 and fp != null and is_instance_valid(fp))
	if fp != null and is_instance_valid(fp):
		fp.leave()
	await _frames(2)
	check("wyjście: in_range zgaszone", not player.in_range and player.fp == null)

## Ustawienia widoku z oczu (czułość, oś Y, kąt widzenia), akcje w kontekście „range” i dźwięki blach w manifeście.
func _t_options() -> void:
	var sens0: int = Settings.fp_sens_idx
	var inv0: bool = Settings.fp_invert_y
	var fp: Node = _enter()
	await _frames(2)
	fp.yaw = 0.0
	fp.pitch = 0.0
	Settings.fp_sens_idx = Settings.FP_SENS_DEFAULT
	Settings.fp_invert_y = false
	fp.mouse_look(Vector2(0.0, -20.0))
	var up1: float = fp.pitch
	fp.pitch = 0.0
	Settings.fp_sens_idx = Settings.FP_SENS_LIST.find(2.0)
	fp.mouse_look(Vector2(0.0, -20.0))
	var up2: float = fp.pitch
	fp.pitch = 0.0
	Settings.fp_invert_y = true
	fp.mouse_look(Vector2(0.0, -20.0))
	var up3: float = fp.pitch
	check("czułość ×2 podwaja obrót (%.4f → %.4f rad), mysz w górę patrzy w górę" % [up1, up2], up1 > 0.0 and is_equal_approx(up2, up1 * 2.0))
	check("odwrócona oś Y: mysz w górę patrzy w dół (%.4f)" % up3, up3 < 0.0)
	Settings.fp_sens_idx = sens0
	Settings.fp_invert_y = inv0
	check("kąt widzenia z ustawień: domyślnie %d°" % int(Settings.FP_FOV_LIST[Settings.FP_FOV_DEFAULT]), int(Settings.FP_FOV_LIST[Settings.FP_FOV_DEFAULT]) == 74)
	fp.leave()
	await _frames(2)
	var rows: Array = Actions.range_sheet()
	var keyed := rows.filter(func(r: Array) -> bool: return String(r[0]) != "" and String(r[0]) != "—")
	check("ściąga strzelnicy: %d wierszy, każdy z klawiszem" % rows.size(), rows.size() == Actions.RANGE_SHEET.size() and keyed.size() == rows.size())
	check("przyrządy do przypisania (CONTROLS) i na padzie", Actions.rebindable().has("aim_sights") and Actions.pad_rebindable("aim_sights"))
	check("pasek sterowania strzelnicy: %s" % Actions.range_hud_line().substr(0, 40), Actions.range_hud_line().contains(Actions.key("aim_sights")))
	check("dźwięki blach w manifeście (plate_ring ×4, plate_fall ×2)", Audio.variant("plate_ring", 4) >= 0 and Audio.variant("plate_fall", 2) >= 0)

## Serwer: tablica drużyny przyjmuje tylko wiarygodne wyniki gracza ze strzelnicy, jeden wiersz na gracza i broń.
func _t_server() -> void:
	var d := Weapons.def(Weapons.M83)
	var t_min := 4.0 * d.cooldown
	check("plausible: M-83 5 blach w %.2f s tak, w 0,05 s nie" % t_min, RangeDoor.plausible(t_min, 5, Weapons.M83) and not RangeDoor.plausible(0.05, 5, Weapons.M83))
	check("plausible: mniej niż 5 strzałów z M-83 nie", not RangeDoor.plausible(5.0, 4, Weapons.M83))
	check("plausible: strzelba (śrut) 3 strzały wystarczą", RangeDoor.plausible(3.0, 3, Weapons.SPREAD12) and not RangeDoor.plausible(3.0, 2, Weapons.SPREAD12))
	var n0: int = (door.board as Array).size()
	var best0: float = door.best()
	var rej0: int = door.rejected
	door._accept(1, 0.9, 5, Weapons.M83)                         # gracz poza strzelnicą
	check("odrzucony: gracz nie stoi na strzelnicy", door.rejected == rej0 + 1 and (door.board as Array).size() == n0)
	var fp: Node = _enter()
	await _frames(3)
	door._accept(1, 0.05, 5, Weapons.M83)
	door._accept(1, 2.0, 5, Weapons.SPREAD12 if int(player.weapon) != Weapons.SPREAD12 else Weapons.M83)
	check("odrzucone: za szybki przebieg i inna broń niż w ręku (%d)" % (door.rejected - rej0), door.rejected == rej0 + 3 and door.best() == best0)
	door._accept(1, best0 + 5.0, 5, Weapons.M83)
	var mine := (door.board as Array).filter(func(e: Dictionary) -> bool: return String(e["who"]) == "P1" and int(e["w"]) == Weapons.M83)
	check("wolniejszy przebieg nie dubluje wiersza ani nie psuje rekordu (%d, %.2f s)" % [mine.size(), door.best()], mine.size() == 1 and door.best() == best0)
	check("tablica w Settings (bez zapisu do pliku w headless)", (Settings.range_board as Array).size() == (door.board as Array).size())
	fp.leave()
	await _frames(2)

## Ćwiczenie z przeładowaniem: 4 blachy (piąta leży), magazynek przycięty do 2 naboi przed startem, przebieg z przeładowaniem trafia na
## osobną część tablicy drużyny i do rekordu osobistego; rekord wizyty osobno dla każdego ćwiczenia; walidacja serwera liczy przeładowanie.
func _t_drill() -> void:
	var d := Weapons.def(Weapons.M83)
	var t_fast := 3.0 * d.cooldown                                # 4 strzały bez przeładowania
	var t_ok := 3.0 * d.cooldown + d.reload_time
	check("plausible: przeładowanie M-83 w %.2f s nie (bez przeładowania), w %.2f s tak; 5 blach w %.2f s nadal tak" % [t_fast, t_ok, 4.0 * d.cooldown],
		not RangeDoor.plausible(t_fast, 4, Weapons.M83, RangeSim.EX_RELOAD) and RangeDoor.plausible(t_ok, 4, Weapons.M83, RangeSim.EX_RELOAD)
		and RangeDoor.plausible(4.0 * d.cooldown, 5, Weapons.M83) and not RangeDoor.plausible(t_ok, 4, Weapons.M83, "bogus"))
	var s0 := RangeSim.new()
	s0.set_exercise(RangeSim.EX_RELOAD)
	var lying: Array = s0.plates.map(func(p: Dictionary) -> bool: return p["down"])
	check("ćwiczenie z przeładowaniem: %d blachy stoją, reszta leży %s" % [s0.targets(), str(lying)], s0.targets() == 4 and lying == [false, false, false, false, true])
	s0.best = 7.0
	s0.set_exercise(RangeSim.EX_PLATES)
	var b_pl := s0.best
	s0.set_exercise(RangeSim.EX_RELOAD)
	check("rekord wizyty osobno dla ćwiczeń (5 blach %.1f, przeładowanie %.1f)" % [b_pl, s0.best], b_pl < 0.0 and s0.best == 7.0 and s0.next_exercise() == RangeSim.EX_PLATES)
	var wc = player.weapons
	if int(wc.cur().id) != Weapons.M83:
		wc.loadout[0] = Weapons.M83
		wc.select_slot(0)
		await get_tree().create_timer(1.0).timeout
	wc.mags[Weapons.M83] = 30
	wc.jams.clear()
	var fp: Node = _enter()
	await _frames(2)
	Input.action_press("range_exercise")                          # klawisz zmiany ćwiczenia (actions.gd)
	await _frames(2)
	Input.action_release("range_exercise")
	await _frames(2)
	var cap := RangeSim.drill_load(d)
	check("[%s] zmienia ćwiczenie na przeładowanie, magazynek przycięty 30 → %d" % [Actions.key("range_exercise"), wc.mag_of(Weapons.M83)],
		fp.sim.exercise == RangeSim.EX_RELOAD and wc.mag_of(Weapons.M83) == cap)
	wc.try_reload()
	await get_tree().create_timer(d.full_reload_time() + 0.5).timeout
	check("przeładowanie przed startem nic nie daje (%d)" % wc.mag_of(Weapons.M83), wc.mag_of(Weapons.M83) == cap)
	var reloads := 0
	for i in RangeSim.DRILL_PLATES:
		var n := 0
		while not fp.sim.plates[i]["down"] and n < 12:
			if wc.mag_of(Weapons.M83) <= 0:
				if not wc.is_reloading():
					wc.try_reload()
					reloads += 1
				var w := 0
				while wc.is_reloading() and w < 300:
					await get_tree().physics_frame
					w += 1
			await _shoot_at(fp, i)
			wc.jams.clear()
			n += 1
	await _frames(2)
	var rows: Array = door.rows(RangeSim.EX_RELOAD)
	var top: Dictionary = rows[0] if not rows.is_empty() else {}
	check("przebieg z przeładowaniem (%d) w %.2f s: tablica przeładowania %s, 5 blach bez zmian, piąta blacha leży" % [reloads, fp.sim.last_time, str(top)],
		reloads >= 1 and fp.sim.runs == 1 and RangeDoor.ex_of(top) == RangeSim.EX_RELOAD and is_equal_approx(float(top.get("t", -1.0)), fp.sim.last_time)
		and door.best(RangeSim.EX_RELOAD) == fp.sim.last_time and door.rows(RangeSim.EX_PLATES).all(func(e: Dictionary) -> bool: return RangeDoor.ex_of(e) == RangeSim.EX_PLATES)
		and fp.sim.plates[4]["down"])
	check("rekord osobisty przeładowania M-83: %.2f s (nowy: %s)" % [Profile.range_best_of(RangeSim.EX_RELOAD, "m83"), fp.pb_new],
		fp.pb_new and Profile.range_best_of(RangeSim.EX_RELOAD, "m83") == fp.sim.last_time)
	# papier: piąta przestrzelina serii zamyka grupę — rekord osobisty w MOA
	fp.sim.paper_holes = [Vector2(0.0, 0.0), Vector2(0.02, 0.01), Vector2(-0.01, 0.02), Vector2(0.01, -0.02), Vector2(0.0, 0.03)]
	fp.sim._shot_w = Weapons.M83
	fp._on_paper_hole(Vector2.ZERO)
	var moa := float(fp.sim.paper_group()["moa"])
	check("rekord osobisty grupy 5 strzałów M-83: %.1f MOA" % Profile.range_best_of(RangeSim.EX_PAPER, "m83"),
		fp.paper_pb_new and is_equal_approx(Profile.range_best_of(RangeSim.EX_PAPER, "m83"), moa))
	fp.sim.paper_holes.clear()
	fp.sim._reset_in = -1.0
	fp.sim.set_exercise(RangeSim.EX_PLATES)
	fp.leave()
	await _frames(2)
	wc.mags[Weapons.M83] = 30

## Strzał przez kontroler broni w środek blachy `i` (bez podrzutu i rozrzutu z serii).
func _shoot_at(fp: Node, i: int) -> void:
	var wc = player.weapons
	var dir: Vector3 = fp.sim.aim_at(fp.eye(), i)
	fp.yaw = atan2(-dir.x, -dir.z)
	fp.pitch = asin(dir.y)
	var wait := 0
	while wc.cd > 0.0 and wait < 60:                             # odstęp między strzałami jak w grze: czas przebiegu musi przejść walidację serwera
		await get_tree().physics_frame                           # (RangeDoor.plausible) — wyzerowany `cd` dawał przebieg szybszy niż broń strzela
		wait += 1
	wc.climb = 0.0
	wc.bloom = 0.0
	wc.sim_fire = true                                         # M-83 jest automatyczny: strzela przytrzymany spust — jedna klatka = jeden strzał
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
	var fp: Node = _enter()
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
	check("rekord osobisty 5 blach M-83 w profilu (%.2f s)" % Profile.range_best_of(RangeSim.EX_PLATES, "m83"), fp.pb_new and Profile.range_best_of(RangeSim.EX_PLATES, "m83") == fp.sim.last_time)
	await _frames(2)
	var top: Dictionary = (door.board as Array)[0] if not (door.board as Array).is_empty() else {}
	check("tablica drużyny: %s (strzały przebiegu %d)" % [str(top), fp.sim.run_shots],
		String(top.get("who", "")) == "P1" and int(top.get("w", -1)) == Weapons.M83 and is_equal_approx(float(top.get("t", -1.0)), fp.sim.last_time)
		and bool(door.last.get("record", false)) and fp.sim.run_shots >= 5)
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
	var fp: Node = _enter()
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
	var fp: Node = _enter()
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
	var fp: Node = _enter()
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
	var fp: Node = _enter()
	await _frames(2)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(3)
	check("[E] wychodzi: zwykłe strzelanie wraca", player.fp == null and wc.range_sink == null and not wc.practice and not is_instance_valid(fp) and not player.in_range)
