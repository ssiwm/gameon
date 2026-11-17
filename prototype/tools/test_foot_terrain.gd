extends SceneTree
## Stopy postaci 3D na nierównym gruncie (char3d.gd `terrain` / `_terrain_pose`): sonda gruntu jak z player.gd (`_foot_probe`), a model ma
## stać stopami na prawdziwym podłożu — zbocza i schody wykopane w strefach wydobycia (stopień 8 px), krawędź stopnia. Sprawdza:
##  1. płaski grunt: poza nóg i bioder taka sama jak bez sondy (nic się nie zmienia na zwykłej podłodze);
##  2. krawędź stopnia (środek ciała 3 px za krawędzią, w obie strony patrzenia): stopy na niższym stopniu, nie w powietrzu, biodra niżej;
##  3. skos ok. 40°: każda stopa na gruncie pod sobą, stopa nachylona do skosu;
##  4. bieg po schodach: stopa nigdy w gruncie, zejście ciała 2D o stopień (8 px w jednej klatce) nie przestawia bioder skokiem;
##  5. bez sondy (lot): dopasowanie wygasa, stopy jak dawniej.
## godot --headless --path prototype -s tools/test_foot_terrain.gd      → ma wypisać [FOOT-TERRAIN] PASS
const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const SETTLE := 60
const TOL := 0.04                            ## m: stopa nad / pod gruntem w spoczynku
var _c: Node2D
var _fail := 0
var _ground := Callable()                    ## dx px (świat, od stóp ciała) → px w górę
var _body_y := 0.0                           ## px: wysokość stóp ciała 2D (w górę)
var _x := 0.0                                ## px: położenie ciała na schodach (pole — lambda kopiuje zmienne lokalne)

func _initialize() -> void:
	_c = Char3D.new()
	root.add_child(_c)
	if not _c.setup("male_scav", "m83"):
		print("[FOOT-TERRAIN] FAIL: brak modelu postaci")
		quit(1)

func check(label: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("[FOOT-TERRAIN] %s  %s" % ["PASS" if ok else "FAIL", label])

## Sonda jak player.gd `_foot_probe`: grunt w zasięgu [−12, +11] px albo NAN. Teren `_ground` jest w układzie świata, ciało stoi w `_body_y`.
func _probe(dx: float) -> float:
	var g: float = _ground.call(dx) - _body_y
	return g if g >= -12.0 and g <= 11.0 else NAN

func _frame(anim: String, side: float, speed := 0.0, terrain := true) -> void:
	_c.terrain(-_body_y, Callable(self, "_probe") if terrain else Callable())     # y świata rośnie w dół: stopy ciała na −_body_y
	_c.update(DT, anim, side, Vector2(side, 0.0), speed)

func _settle(anim: String, side: float, speed := 0.0, terrain := true, n := SETTLE) -> void:
	for i in n:
		_frame(anim, side, speed, terrain)

## Stopa: [wysokość podeszwy nad gruntem pod nią (m), grunt pod stopą (m, względem stóp ciała)] — podeszwa = kostka − wysokość kostki w spoczynku.
func _foot(side: String) -> Array:
	var p: Vector3 = _c._gp(_c._b[side + "Foot"]).origin
	var heel: float = _probe(_c._to_px(p + Vector3(Char3D.FOOT_HEEL, 0.0, 0.0)).x)
	var toe: float = _probe(_c._to_px(p + Vector3(Char3D.FOOT_TOE, 0.0, 0.0)).x)
	var g := 0.0
	if not is_nan(heel) or not is_nan(toe):
		g = maxf(heel if not is_nan(heel) else -INF, toe if not is_nan(toe) else -INF) / Char3D.WP_PER_M
	return [p.y - _c._ankle_y - g, g]

func _hips_y() -> float:
	return (_c._gp(_c._b["Hips"]).origin as Vector3).y

func _process(_d: float) -> bool:
	_c._set_on_screen(true)
	# 1. płasko: z sondą i bez — ta sama poza
	_body_y = 0.0
	_ground = func(_dx: float) -> float: return 0.0
	for anim in ["idle", "run", "crouch"]:
		var spd := 95.0 if anim == "run" else 0.0
		_settle(anim, 1.0, spd, false, SETTLE - 1)
		var ph: float = _c._phase
		var tm: float = _c._time
		_frame(anim, 1.0, spd, false)
		var ref := [_c._gp(_c._b["LeftFoot"]).origin, _c._gp(_c._b["RightFoot"]).origin, _hips_y()]
		_settle(anim, 1.0, spd, true, SETTLE - 1)
		_c._phase = ph
		_c._time = tm
		_frame(anim, 1.0, spd, true)
		var dev := maxf(maxf((_c._gp(_c._b["LeftFoot"]).origin as Vector3).distance_to(ref[0]), (_c._gp(_c._b["RightFoot"]).origin as Vector3).distance_to(ref[1])),
			absf(_hips_y() - float(ref[2])))
		check("płaski grunt (%s): sonda nie zmienia pozy (%.4f m)" % [anim, dev], dev < 0.002)
	# 2. krawędź stopnia 8 px: ciało (prostokąt 10 px) stoi rogiem na wyższym, środek 3 px za krawędzią
	for side in [1.0, -1.0]:
		_ground = func(dx: float) -> float: return 0.0 if dx * side < -3.0 else -8.0
		_settle("idle", side, 0.0, false)
		var air := maxf(float(_foot("Left")[0]), float(_foot("Right")[0]))
		var hips0 := _hips_y()
		_settle("idle", side)
		var l := _foot("Left")
		var r := _foot("Right")
		print("[FOOT-TERRAIN] INFO  krawędź (%s): bez sondy stopa %.2f m nad gruntem; z sondą L %+.3f m nad gruntem %+.2f, P %+.3f nad %+.2f, biodra %+.2f m" %
			["w prawo" if side > 0.0 else "w lewo", air, l[0], l[1], r[0], r[1], _hips_y() - hips0])
		check("krawędź stopnia (%s): bez sondy stopa wisiała (> 0,3 m)" % ("w prawo" if side > 0.0 else "w lewo"), air > 0.3)
		check("krawędź stopnia (%s): obie stopy na gruncie (±%.2f m)" % ["w prawo" if side > 0.0 else "w lewo", TOL],
			absf(float(l[0])) < TOL and absf(float(r[0])) < TOL)
		check("krawędź stopnia: biodra niżej (%.2f m)" % (_hips_y() - hips0), _hips_y() - hips0 < -0.25)
	# 3. skos ok. 40° w dół w stronę patrzenia
	for side in [1.0, -1.0]:
		_ground = func(dx: float) -> float: return -0.84 * dx * side
		_settle("idle", side)
		var l := _foot("Left")
		var r := _foot("Right")
		var tilt_ok: bool = float(_c._foot_tilt["Left"]) < -deg_to_rad(15.0) and float(_c._foot_tilt["Right"]) < -deg_to_rad(15.0)
		check("skos 40° (%s): stopy na gruncie (L %+.3f, P %+.3f m), czubki w dół (%.0f°, %.0f°)" %
			["w prawo" if side > 0.0 else "w lewo", l[0], r[0], rad_to_deg(_c._foot_tilt["Left"]), rad_to_deg(_c._foot_tilt["Right"])],
			absf(float(l[0])) < TOL and absf(float(r[0])) < TOL and tilt_ok)
	# 4. bieg w dół po schodach: stopień 8 px co 12 px; ciało 2D jedzie po krawędziach i spada o stopień w jednej klatce
	_x = -6.0
	_body_y = 0.0
	_ground = func(dx: float) -> float: return -8.0 * floorf(maxf(dx + _x, 0.0) / 12.0)
	_settle("run", 1.0, 95.0)
	var worst_in := 0.0
	var worst_jump := 0.0
	var hip_prev := NAN
	for i in 90:
		_x += 95.0 * DT
		# prostokąt ciała ±5 px stoi na najwyższym punkcie pod sobą
		_body_y = maxf(-8.0 * floorf(maxf(_x - 5.0, 0.0) / 12.0), -8.0 * floorf(maxf(_x + 5.0, 0.0) / 12.0))
		_frame("run", 1.0, 95.0)
		for s in ["Left", "Right"]:
			worst_in = minf(worst_in, float(_foot(s)[0]))
		var hip_world := _hips_y() + _body_y / Char3D.WP_PER_M
		if not is_nan(hip_prev):
			worst_jump = maxf(worst_jump, absf(hip_world - hip_prev))
		hip_prev = hip_world
	check("bieg po schodach: stopa nie wchodzi w grunt (najgłębiej %.3f m)" % worst_in, worst_in > -0.05)
	# schody schodzą średnio 0,086 m na klatkę (8 px co 12 px przy 95 px/s); skok o cały stopień to 0,65 m w jednej klatce
	check("bieg po schodach: biodra bez skoku przy zejściu ciała o stopień (najwięcej %.3f m na klatkę)" % worst_jump, worst_jump < 0.2)
	# 5. lot: bez sondy dopasowanie wygasa
	_settle("fall", 1.0, 0.0, false, 30)
	check("w locie bez sondy: dopasowanie wyłączone (%.2f)" % _c._terrain_w, _c._terrain_w < 0.01 and absf(float(_c.hip_terrain)) < 0.001)
	print("[FOOT-TERRAIN] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail > 0 else 0)
	return true
