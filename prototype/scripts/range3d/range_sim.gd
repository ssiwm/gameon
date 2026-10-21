extends RefCounted
## Strzelnica FPP — symulacja (RANGE_FPS_PLAN.md, etap 0). Tunel to prostopadłościan w osi −z (linia ognia na z = 0), cele to proste
## kształty, a kula to promień liczony wzorem — bez fizyki 3D, więc test headless liczy dokładnie to samo co gra (wąski wyjątek od zasady
## „symulacja zostaje 2D”, CLAUDE.md). Obraz buduje range_view.gd, sterowanie i połączenie z bronią — fp_mode.gd.
##
## Ćwiczenie „blachy na czas” jak w strzelnicy z 1.7.334: pierwsze trafienie uruchamia stoper, ostatnia blacha go zatrzymuje, po RESET_T s
## blachy wstają; bez trafienia przez ABANDON_T s przebieg przepada. Rekord trzyma tylko ta sesja (zapis i tablica drużyny — etap 1).

const WeaponDef := preload("res://scripts/weapon_def.gd")

const LANE_W := 6.0                   ## m — szerokość tunelu (x od −3 do 3)
const LANE_H := 3.2                   ## m — wysokość stropu
const LANE_L := 30.0                  ## m — od linii ognia do kulochwytu (z = −LANE_L)
const BENCH_H := 0.95                 ## m — blat ławy stanowiska
const BENCH_Z := -0.45                ## m — przednia krawędź ławy (przed graczem)
const EYE_STAND := 1.62               ## m — oczy na stojąco
const EYE_BRACE := 1.24               ## m — przyklęk przy ławie: broń leży na blacie (oparcie)
const EYE_Z := 0.0                    ## m — oczy nad linią ognia
const STATIONS := [-1.6, 0.0, 1.6]    ## m — x stanowisk na linii ognia
const DIVIDERS := [-0.8, 0.8]         ## m — x przegród między stanowiskami (obraz: range_view.gd, łuski: range_fx.gd)
const DIVIDER_Z := Vector2(-0.6, 0.5) ## m — zasięg przegrody wzdłuż toru
const DIVIDER_Y := Vector2(0.1, 2.0)  ## m — wysokość przegrody
const PLATE_R := 0.15                 ## m — promień blachy (popper ⌀ 30 cm)
const PLATE_Y := 1.2                  ## m — wysokość środka blachy
const PLATES := [[-1.2, 7.0], [0.9, 10.0], [-0.5, 13.0], [1.4, 16.0], [-1.5, 20.0]]   ## [x m, odległość m] — od najbliższej
const RESET_T := 3.0
const ABANDON_T := 12.0
const MAX_DIST := 60.0                ## m — dalej promień nie leci (tunel ma 30 m, z zapasem na skos)

signal plate_down(index: int)
signal plates_up
signal finished(t: float, best: float, record: bool)
signal impact(pos: Vector3, normal: Vector3, kind: String, index: int)     ## kind: plate | wall | floor | ceiling | backstop | bench

var plates: Array = []                ## [{pos: Vector3 (środek blachy), down: bool}, …]
var running := false
var last_time := -1.0                 ## s — ostatni przebieg (−1: jeszcze nie było)
var best := -1.0                      ## s — rekord sesji (−1: brak)
var runs := 0
var shots := 0                        ## strzały (każda śrucina osobno nie — jeden strzał broni)
var hits := 0                         ## trafione blachy
var clock := 0.0                      ## s — czas symulacji (tick); stoper liczy z niego, nie z zegara systemu

var _t0 := 0.0
var _left := 0
var _since_hit := 0.0
var _reset_in := -1.0

func _init() -> void:
	for p in PLATES:
		plates.append({"pos": Vector3(float(p[0]), PLATE_Y, -float(p[1])), "down": false})

func tick(delta: float) -> void:
	clock += delta
	if running:
		_since_hit += delta
		if _since_hit > ABANDON_T:
			running = false
			_reset_in = 0.01                                    # przerwany przebieg: blachy wstają od razu
	if _reset_in > 0.0:
		_reset_in -= delta
		if _reset_in <= 0.0:
			_reset_in = -1.0
			for p in plates:
				p["down"] = false
			plates_up.emit()

## Strzał z oka `origin` (linia przyrządów = linia strzału) w kierunku `-basis.z`: każda śrucina to osobny promień.
## Zwraca listę trafień {pos, normal, kind, index}.
func shoot(origin: Vector3, basis: Basis, d: WeaponDef, seed: int, extra: float) -> Array:
	shots += 1
	var out: Array = []
	for dir in pellet_dirs3(d, basis, seed, extra):
		var h := trace(origin, dir)
		if h.is_empty():
			continue
		out.append(h)
		impact.emit(h["pos"], h["normal"], h["kind"], int(h["index"]))
		if h["kind"] == "plate" and not plates[int(h["index"])]["down"]:
			_knock(int(h["index"]))
	return out

## Najbliższe przecięcie promienia ze stojącą blachą albo bryłą tunelu; pusty słownik, gdy nic (nie powinno się zdarzyć w zamkniętym tunelu).
func trace(origin: Vector3, dir: Vector3) -> Dictionary:
	var best_t := MAX_DIST
	var hit := {}
	# blachy: koło na płaszczyźnie z = const, twarzą do strzelca
	for i in plates.size():
		if plates[i]["down"]:
			continue
		var c: Vector3 = plates[i]["pos"]
		if absf(dir.z) < 1e-5:
			continue
		var t := (c.z - origin.z) / dir.z
		if t <= 0.0 or t >= best_t:
			continue
		var p := origin + dir * t
		if Vector2(p.x - c.x, p.y - c.y).length() <= PLATE_R:
			best_t = t
			hit = {"pos": p, "normal": Vector3(0, 0, 1), "kind": "plate", "index": i}
	# ława stanowiska: blat (y = BENCH_H) między z = BENCH_Z a z = 0 — strzał w blat z przyklęku
	if dir.y < 0.0:
		var tb := (BENCH_H - origin.y) / dir.y
		if tb > 0.0 and tb < best_t:
			var pb := origin + dir * tb
			if pb.z <= 0.0 and pb.z >= BENCH_Z and absf(pb.x) <= LANE_W * 0.5:
				best_t = tb
				hit = {"pos": pb, "normal": Vector3.UP, "kind": "bench", "index": -1}
	# ściany, podłoga, strop, kulochwyt
	var planes := [
		[Vector3(1, 0, 0), -LANE_W * 0.5, "wall"], [Vector3(-1, 0, 0), -LANE_W * 0.5, "wall"],
		[Vector3(0, 1, 0), 0.0, "floor"], [Vector3(0, -1, 0), -LANE_H, "ceiling"],
		[Vector3(0, 0, 1), -LANE_L, "backstop"]]
	for pl in planes:
		var n: Vector3 = pl[0]
		var dn := n.dot(dir)
		if dn >= -1e-5:
			continue                                           # promień od płaszczyzny albo równolegle
		var t2 := (float(pl[1]) - n.dot(origin)) / dn
		if t2 > 0.0 and t2 < best_t:
			best_t = t2
			hit = {"pos": origin + dir * t2, "normal": n, "kind": String(pl[2]), "index": -1}
	return hit

## Kierunki śrucin w 3D. Rozrzut z gry 2D (`Weapons.pellet_dirs`: ± jitter w jednej płaszczyźnie) staje się stożkiem o tym samym kącie
## połówkowym (`WeaponDef.cone_half_deg`): punkt równomiernie w kole o promieniu kątowym jitter. Śrut: każda śrucina w losowym miejscu
## własnego wycinka koła o promieniu spread_deg (równe pokrycie bez wzoru), plus ten sam rozrzut losowy.
static func pellet_dirs3(d: WeaponDef, basis: Basis, seed: int, extra_deg: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jitter: float = d.jitter_deg + maxf(extra_deg, 0.0)
	var out: Array = []
	for i in d.pellets:
		var r := jitter * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var yaw := r * cos(a)
		var pitch := r * sin(a)
		if d.pellets > 1:
			var rs := float(d.spread_deg) * sqrt(rng.randf())
			var as_ := TAU * (float(i) + rng.randf()) / float(d.pellets)
			yaw += rs * cos(as_)
			pitch += rs * sin(as_)
		var local := Vector3(tan(deg_to_rad(yaw)), tan(deg_to_rad(pitch)), -1.0).normalized()
		out.append((basis * local).normalized())
	return out

## Kierunek z oka na środek blachy `i` (testy i dev: celowanie wprost).
func aim_at(origin: Vector3, i: int) -> Vector3:
	return ((plates[i]["pos"] as Vector3) - origin).normalized()

func _knock(i: int) -> void:
	plates[i]["down"] = true
	hits += 1
	plate_down.emit(i)
	if not running:
		running = true
		_t0 = clock
		_left = plates.size()
	_left -= 1
	_since_hit = 0.0
	if _left > 0:
		return
	running = false
	runs += 1
	var t := clock - _t0
	var record := best < 0.0 or t < best
	if record:
		best = t
	last_time = t
	_reset_in = RESET_T
	finished.emit(t, best, record)
