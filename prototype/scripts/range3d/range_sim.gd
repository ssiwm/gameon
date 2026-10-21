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
# Bronie specjalne (etap 3): skale świata gry 2D → metry tunelu. Długości (zasięgi, odległość uzbrojenia, promień wybuchu) przez PX_PER_M
# (bełt SINEW-6 i zapalnik WRATH-4 „ok. 6,5 m” z WeaponDef), prędkości przez SPEED_PX (jak kule: dźwięk 1165 px/s ≈ 343 m/s,
# Weapons.SOUND_PX). Grawitacja w tunelu prawdziwa — w grze 2D jest przesadzona, żeby łuk był czytelny na ekranie.
const PX_PER_M := 12.3
const SPEED_PX := 3.4
## Czas gry 2D → czas tunelu: ta sama droga w px i w m przy prędkościach przeliczonych przez SPEED_PX trwa w tunelu tyle razy krócej.
## Przez to mnożymy prędkość skrętu naprowadzania i dzielimy czasy (opóźnienie skrętu, rozpęd silnika) — tor rakiety ma w tunelu ten
## sam kształt co w grze (promień skrętu FALCON-6 ok. 5 m); bez tego zakręcała dopiero za blachami.
const TIME_K := PX_PER_M / SPEED_PX
const G := 9.81
const FLIGHT_DT := 1.0 / 240.0        ## s — krok lotu pocisku (granat, rakieta)
const FLIGHT_MAX_T := 3.0
const FLIGHT_PT_EVERY := 4            ## co tyle kroków punkt toru dla obrazu
const HOMING_DELAY := 0.12            ## s lotu prosto, zanim rakieta zacznie skręcać (jak projectile.gd)
const BLAST_KNOCK := 0.5              ## część promienia wybuchu, w której fala przewraca blachę (dalej tylko odłamki)
const PLATE_HEAT := 30.0              ## obrażenia promienia / płomienia, od których blacha się przewraca (LR-7 z bliska: 0,5 s)
const HEAT_COOL := 12.0               ## 1/s — stygnięcie blachy
const FIRE_T := 3.5                   ## s — ogień na podłodze po płomieniu (HKM-9)
const FIRE_EVERY := 0.5               ## s — co tyle płomień zostawia nową plamę ognia
const FIRE_MAX := 12

signal plate_down(index: int)
signal plates_up
signal finished(t: float, best: float, record: bool)
signal impact(pos: Vector3, normal: Vector3, kind: String, index: int)     ## kind: plate | wall | floor | ceiling | backstop | bench
## Pocisk w locie (WRATH-4, FALCON-6): tor co FLIGHT_PT_EVERY kroków i czas lotu do uderzenia — obraz go animuje.
signal flight(points: PackedVector3Array, secs: float, key: String)
## Uderzenie pocisku z lotu, `exploded` — wybuch uzbrojonego granatu (promień `radius` m), inaczej uderzenie / niewypał.
signal landed(pos: Vector3, normal: Vector3, kind: String, key: String, exploded: bool, radius: float)

var plates: Array = []                ## [{pos: Vector3 (środek blachy), down: bool}, …]
var running := false
var last_time := -1.0                 ## s — ostatni przebieg (−1: jeszcze nie było)
var best := -1.0                      ## s — rekord sesji (−1: brak)
var runs := 0
var shots := 0                        ## strzały (każda śrucina osobno nie — jeden strzał broni)
var hits := 0                         ## trafione blachy
var clock := 0.0                      ## s — czas symulacji (tick); stoper liczy z niego, nie z zegara systemu
var run_shots := 0                    ## strzały bieżącego / ostatniego przebiegu (od tego, który przewrócił pierwszą blachę)
var run_w := -1                       ## broń, z której padła pierwsza blacha przebiegu (wynik na tablicy drużyny, range_door.gd)
var _shot_w := -1
var beam_from := Vector3.ZERO         ## ostatni krok promienia LR-7 (oko → koniec) i jego czas — obraz pokazuje promień, póki świeży
var beam_to := Vector3.ZERO
var beam_at := -1.0
var flame_at := -1.0                  ## ostatni krok płomienia HKM-9 (czas) i jego zasięg w m
var flame_reach := 0.0
var fires: Array = []                 ## plamy ognia na podłodze [{pos: Vector3, until: s}]
var _pending: Array = []              ## pociski w locie [{at: s, hit, key, blast: m (0 — bez wybuchu)}]
var _fire_t := 0.0

var _t0 := 0.0
var _left := 0
var _since_hit := 0.0
var _reset_in := -1.0

func _init() -> void:
	for p in PLATES:
		plates.append({"pos": Vector3(float(p[0]), PLATE_Y, -float(p[1])), "down": false, "heat": 0.0})

func tick(delta: float) -> void:
	clock += delta
	var due := _pending.filter(func(e: Dictionary) -> bool: return float(e["at"]) <= clock)
	if not due.is_empty():
		_pending = _pending.filter(func(e: Dictionary) -> bool: return float(e["at"]) > clock)
		for e in due:
			_resolve(e)
	for p in plates:
		p["heat"] = maxf(0.0, float(p["heat"]) - HEAT_COOL * delta)
	fires = fires.filter(func(f: Dictionary) -> bool: return float(f["until"]) > clock)
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
				p["heat"] = 0.0
			plates_up.emit()

## Strzał z oka `origin` (linia przyrządów = linia strzału) w kierunku `-basis.z`: każda śrucina to osobny promień.
## Zwraca listę trafień {pos, normal, kind, index}.
func shoot(origin: Vector3, basis: Basis, d: WeaponDef, seed: int, extra: float) -> Array:
	shots += 1
	_shot_w = int(d.id)
	if running:
		run_shots += 1                                       # strzał, który zaczyna przebieg, liczy _knock
	match d.kind:
		WeaponDef.Kind.BEAM:
			return _beam(origin, -basis.z, d)
		WeaponDef.Kind.FLAME:
			_flame(origin, -basis.z, d)
			return []
		WeaponDef.Kind.RAIL:
			return _pierce(origin, pellet_dirs3(d, basis, seed, extra)[0])
	if d.kind == WeaponDef.Kind.LAUNCHER or float(d.accel_time) > 0.0 or float(d.homing) > 0.0:
		for dir in pellet_dirs3(d, basis, seed, extra):
			_launch(origin, dir, d)
		return []
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

## Najbliższe przecięcie promienia ze stojącą blachą albo bryłą tunelu do odległości `max_t` (m; „t” w wyniku); pusty słownik, gdy nic.
## `with_plates` false — sama bryła tunelu (szyna i promień liczą blachy osobno, `_plates_on_ray`).
func trace(origin: Vector3, dir: Vector3, max_t := MAX_DIST, with_plates := true) -> Dictionary:
	var best_t := max_t
	var hit := {}
	# blachy: koło na płaszczyźnie z = const, twarzą do strzelca
	for i in plates.size():
		if plates[i]["down"] or not with_plates:
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
	if not hit.is_empty():
		hit["t"] = best_t
	return hit

## Stojące blachy, przez które przechodzi promień do odległości `max_t`, od najbliższej: [{t, index, pos}].
func _plates_on_ray(origin: Vector3, dir: Vector3, max_t: float) -> Array:
	var out: Array = []
	for i in plates.size():
		if plates[i]["down"] or absf(dir.z) < 1e-5:
			continue
		var c: Vector3 = plates[i]["pos"]
		var t := (c.z - origin.z) / dir.z
		if t <= 0.0 or t >= max_t:
			continue
		var p := origin + dir * t
		if Vector2(p.x - c.x, p.y - c.y).length() <= PLATE_R:
			out.append({"t": t, "index": i, "pos": p})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	return out

# ---------------------------------------------------------------- bronie specjalne (etap 3)

## Szyna (SPECTER-1): przebija wszystkie blachy na linii aż do bryły tunelu. Zwraca trafienia jak `shoot` (blachy, potem koniec).
func _pierce(origin: Vector3, dir: Vector3) -> Array:
	var end := trace(origin, dir, MAX_DIST, false)
	var end_t := float(end.get("t", MAX_DIST))
	var out: Array = []
	for p in _plates_on_ray(origin, dir, end_t):
		var h := {"pos": p["pos"], "normal": Vector3(0, 0, 1), "kind": "plate", "index": int(p["index"]), "t": float(p["t"])}
		out.append(h)
		impact.emit(h["pos"], h["normal"], "plate", h["index"])
		_knock(int(p["index"]))
	if not end.is_empty():
		out.append(end)
		impact.emit(end["pos"], end["normal"], end["kind"], -1)
	return out

## Promień (LR-7), jeden krok ognia ciągłego: do zasięgu broni albo bryły tunelu, przez `pierce` + 1 blach (dalej gaśnie na blasze).
## Blacha grzeje się obrażeniami kroku (ze spadkiem z odległością, WeaponDef.falloff) i przewraca po PLATE_HEAT.
func _beam(origin: Vector3, dir: Vector3, d: WeaponDef) -> Array:
	var reach := float(d.range_px) / PX_PER_M
	var end := trace(origin, dir, reach, false)
	var end_t := float(end.get("t", reach))
	var out: Array = []
	var n := 0
	for p in _plates_on_ray(origin, dir, end_t):
		var i := int(p["index"])
		plates[i]["heat"] = float(plates[i]["heat"]) + float(d.damage) * d.falloff(float(p["t"]) * PX_PER_M)
		out.append({"pos": p["pos"], "normal": Vector3(0, 0, 1), "kind": "plate", "index": i, "t": float(p["t"])})
		if float(plates[i]["heat"]) >= PLATE_HEAT:
			impact.emit(p["pos"], Vector3(0, 0, 1), "plate", i)
			_knock(i)
		n += 1
		if n > int(d.pierce):
			end_t = float(p["t"])                              # promień kończy się na ostatniej blasze, którą przebija
			end = {}
			break
	if not end.is_empty():
		out.append(end)
	beam_from = origin
	beam_to = origin + dir * end_t
	beam_at = clock
	return out

## Płomień (HKM-9), jeden krok ognia ciągłego: stożek `arc_deg` do zasięgu broni (krótki — najbliższa blacha stoi dalej). Blachy w stożku
## grzeją się jak od promienia; koniec płomienia rzutowany na podłogę zostawia co FIRE_EVERY s plamę ognia (jak `_drop_fire_patch` w grze).
func _flame(origin: Vector3, dir: Vector3, d: WeaponDef) -> void:
	var reach := float(d.range_px) / PX_PER_M
	var wall := trace(origin, dir, reach, false)
	flame_reach = float(wall.get("t", reach))
	flame_at = clock
	for i in plates.size():
		if plates[i]["down"]:
			continue
		var to: Vector3 = (plates[i]["pos"] as Vector3) - origin
		if to.length() > flame_reach or rad_to_deg(to.angle_to(dir)) > float(d.arc_deg):
			continue
		plates[i]["heat"] = float(plates[i]["heat"]) + float(d.damage) * d.falloff(to.length() * PX_PER_M)
		if float(plates[i]["heat"]) >= PLATE_HEAT:
			impact.emit(plates[i]["pos"], Vector3(0, 0, 1), "plate", i)
			_knock(i)
	if clock - _fire_t < FIRE_EVERY:
		return
	_fire_t = clock
	var tip := origin + dir * flame_reach * 0.9
	var spot := Vector3(clampf(tip.x, -LANE_W * 0.5 + 0.2, LANE_W * 0.5 - 0.2), 0.0, minf(tip.z, BENCH_Z - 0.3))
	fires.append({"pos": spot, "until": clock + FIRE_T})
	if fires.size() > FIRE_MAX:
		fires.pop_front()

## Pocisk z lotem (WRATH-4: łuk z prawdziwą grawitacją i zapalnik; FALCON-6: start wolno, rozpęd silnikiem, naprowadzanie na blachę
## w stożku `homing_cone`). Tor liczony od razu krokami FLIGHT_DT (blachy stoją, póki pocisk leci), trafienie rozstrzyga `tick`
## w chwili uderzenia; obraz dostaje tor (sygnał `flight`).
func _launch(origin: Vector3, dir: Vector3, d: WeaponDef) -> void:
	var vel := dir * float(d.speed_at(0.0)) / SPEED_PX
	var p := origin
	var t := 0.0
	var dist := 0.0
	var pts := PackedVector3Array([p])
	var g := G if float(d.gravity) > 0.0 else 0.0
	var homing := float(d.homing)
	var hit := {}
	var k := 0
	while t < FLIGHT_MAX_T:
		t += FLIGHT_DT
		if float(d.accel_time) > 0.0:
			vel = vel.normalized() * float(d.speed_at(t * TIME_K)) / SPEED_PX
		if homing > 0.0 and t * TIME_K > HOMING_DELAY:
			var tg := _homing_target(p, vel, d)
			if tg >= 0:
				var want: Vector3 = ((plates[tg]["pos"] as Vector3) - p).normalized()
				var ang := vel.normalized().angle_to(want)
				if ang > 1e-4:
					var axis := vel.normalized().cross(want).normalized()
					vel = vel.rotated(axis, minf(ang, homing * TIME_K * FLIGHT_DT))
		vel.y -= g * FLIGHT_DT
		var step := vel * FLIGHT_DT
		var h := trace(p, step.normalized(), step.length())
		if not h.is_empty():
			t += FLIGHT_DT * (float(h["t"]) / step.length() - 1.0)
			dist += float(h["t"])
			hit = h
			pts.append(h["pos"])
			break
		p += step
		dist += step.length()
		k += 1
		if k % FLIGHT_PT_EVERY == 0:
			pts.append(p)
	var armed := dist >= float(d.arm_dist) / PX_PER_M
	_pending.append({"at": clock + t, "hit": hit, "key": String(d.key), "w": int(d.id),
		"blast": float(d.blast_radius) / PX_PER_M if float(d.blast_radius) > 0.0 and armed else 0.0})
	flight.emit(pts, t, String(d.key))

## Najbliższa stojąca blacha w stożku naprowadzania przed rakietą i w jej zasięgu (−1: brak).
func _homing_target(p: Vector3, vel: Vector3, d: WeaponDef) -> int:
	var best := -1
	var bd := float(d.homing_range) / PX_PER_M
	for i in plates.size():
		if plates[i]["down"]:
			continue
		var to: Vector3 = (plates[i]["pos"] as Vector3) - p
		var dl := to.length()
		if dl < bd and dl > 0.3 and rad_to_deg(to.angle_to(vel)) <= float(d.homing_cone):
			bd = dl
			best = i
	return best

## Uderzenie pocisku z lotu w chwili `at`: blacha pada od trafienia; uzbrojony granat wybucha — fala przewraca blachy w BLAST_KNOCK
## promienia; za blisko (przed uzbrojeniem) — niewypał, tylko uderzenie.
func _resolve(e: Dictionary) -> void:
	var h: Dictionary = e["hit"]
	if h.is_empty():
		return
	_shot_w = int(e["w"])
	var blast := float(e["blast"])
	impact.emit(h["pos"], h["normal"], h["kind"], int(h["index"]))
	if h["kind"] == "plate" and not plates[int(h["index"])]["down"]:
		_knock(int(h["index"]))
	if blast > 0.0:
		for i in plates.size():
			if not plates[i]["down"] and ((plates[i]["pos"] as Vector3) - (h["pos"] as Vector3)).length() <= blast * BLAST_KNOCK:
				_knock(i)
	landed.emit(h["pos"], h["normal"], h["kind"], String(e["key"]), blast > 0.0, blast)

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
		run_shots = 1
		run_w = _shot_w
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
