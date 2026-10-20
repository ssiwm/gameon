extends SceneTree
## Test punktów celowania rozgrywki (`Char3D.aim_points`): chwyt i wylot lufy liczone z pozy nominalnej mają (1) nie zależeć od klatki animacji —
## bieg, odrzut, przeładowanie, trafienie i cios nie przesuwają toru pocisków — oraz (2) leżeć tam, gdzie broń modelu w spokojnej pozie, żeby pocisk
## wychodził z lufy, którą widać. Wypisuje też średnie odchylenie barku modelu od nominalnego (stoi / kuca).
## godot --headless --path prototype -s tools/test_aim_points.gd      → ma wypisać PASS
const Char3D := preload("res://scripts/char3d.gd")
const Parts := preload("res://scripts/parts.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const GUNS := ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6"]
const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_medic"]
const AIMS := [-80, -45, -15, 0, 20, 50, 85]
const MAX_REST_PX := 1.5                     ## największe dopuszczalne odchylenie wylotu modelu od wylotu rozgrywki w spokojnej pozie (px świata)
const SETTLE := 40                           ## klatek na ustalenie pozy (mieszanie stanów ok. 80 ms)
var _c: Node2D
var _fail := 0

func _initialize() -> void:
	_c = Char3D.new()
	root.add_child(_c)
	if not _c.setup("male_scav", "m83"):
		print("FAIL: brak modelu postaci")
		quit(1)

func _aim(deg: float, side: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a) * side, -sin(a))

func _settle(anim: String, aim: Vector2, side: float, speed := 0.0) -> void:
	for i in SETTLE:
		_c.update(1.0 / 60.0, anim, side, aim, speed)

func _process(_d: float) -> bool:
	_c._set_on_screen(true)
	var worst := 0.0
	var worst_at := ""
	var sum := [Vector3.ZERO, Vector3.ZERO]
	var cnt := [0, 0]
	for look in LOOKS:
		_c.set_look(look)
		for gun in GUNS:
			_c.set_gun(gun)
			for crouch in [false, true]:
				for deg in AIMS:
					for side in [1.0, -1.0]:
						var aim := _aim(float(deg), side)
						_c.gun_kick_px = 0.0
						_c.recoil_px = 0.0
						_c.reload_t = -1.0
						_c.hit_t = -1.0
						_settle("crouch" if crouch else "idle", aim, side)
						var ap: Array = _c.aim_points(aim, side, crouch, gun)
						var dev := (_c.muzzle_px as Vector2).distance_to(ap[1])
						if dev > worst:
							worst = dev
							worst_at = "%s %s %s %d° %s" % [look, gun, "kuca" if crouch else "stoi", deg, "prawo" if side > 0.0 else "lewo"]
						var wp: Dictionary = Char3D.WEAPON_POSE.get(gun, {})
						var nom: Array = _c._nominal_shoulders(Char3D._aim_theta(aim), crouch, wp)
						var act: Vector3 = _c._gp(_c._b["RightArm"]).origin
						sum[1 if crouch else 0] += act - (nom[0] as Vector3)
						cnt[1 if crouch else 0] += 1
						# niezależność od animacji: te same wejścia → ten sam wynik w biegu, z odrzutem, w przeładowaniu i po trafieniu
						_c.gun_kick_px = 4.0
						_c.recoil_px = 4.0
						_c.reload_t = 0.5
						_c.hit_t = 0.2
						_settle("crouch_walk" if crouch else "run", aim, side, 95.0)
						var ap2: Array = _c.aim_points(aim, side, crouch, gun)
						if not (ap2[0] as Vector2).is_equal_approx(ap[0]) or not (ap2[1] as Vector2).is_equal_approx(ap[1]):
							_fail += 1
							print("FAIL: punkty celowania zależą od animacji: %s %s %d°" % [look, gun, deg])
						# lustro: strona lewa to odbicie prawej
						var apm: Array = _c.aim_points(_aim(float(deg), -side), -side, crouch, gun)
						if absf((apm[1] as Vector2).x + (ap[1] as Vector2).x) > 0.001 or absf((apm[1] as Vector2).y - (ap[1] as Vector2).y) > 0.001:
							_fail += 1
							print("FAIL: strona lewa nie jest odbiciem prawej: %s %s %d°" % [look, gun, deg])
	# części z modelem (1.7.320): wylot rozgrywki z tłumikiem / dłuższą lub krótszą lufą = wylot modelu z tymi częściami
	_c.set_look("male_scav")
	for pc in [["m83", ["m83_pbs1"], 1], ["m83", ["m83_rpkbar", "m83_pbs1"], 1], ["m83", ["m83_short"], -1], ["p64", ["p64_supp"], 1], ["spread12", ["sp12_ported"], 0]]:
		var key := String(pc[0])
		var fit := Parts.encode_ids(key, pc[1])
		_c.set_gun(key, fit)
		var aim := _aim(0.0, 1.0)
		_c.gun_kick_px = 0.0
		_c.recoil_px = 0.0
		_c.reload_t = -1.0
		_c.hit_t = -1.0
		_settle("idle", aim, 1.0)
		var ap: Array = _c.aim_points(aim, 1.0, false, key, fit)
		var ap0: Array = _c.aim_points(aim, 1.0, false, key, 0)
		var dev := (_c.muzzle_px as Vector2).distance_to(ap[1])
		var dx := (ap[1] as Vector2).x - (ap0[1] as Vector2).x
		var dir_ok := (dx > 0.5) if int(pc[2]) > 0 else ((dx < -0.5) if int(pc[2]) < 0 else absf(dx) < 0.01)
		print("części %s %s: wylot modelu − rozgrywki %.2f px, wylot przesunięty o %.1f px" % [key, str(pc[1]), dev, dx])
		if dev > MAX_REST_PX or not dir_ok:
			_fail += 1
			print("FAIL: wylot z częściami %s %s (odchylenie %.2f px, przesunięcie %.1f px)" % [key, str(pc[1]), dev, dx])
	_c.set_gun("m83")
	for i in 2:
		var m: Vector3 = sum[i] / maxf(float(cnt[i]), 1.0)
		print("bark modelu − bark nominalny (%s): (%.3f, %.3f, %.3f) m" % ["kuca" if i == 1 else "stoi", m.x, m.y, m.z])
	print("największe odchylenie wylotu modelu od wylotu rozgrywki w spokojnej pozie: %.2f px świata (%s)" % [worst, worst_at])
	if worst > MAX_REST_PX:
		_fail += 1
		print("FAIL: odchylenie większe niż %.1f px — pocisk nie wychodzi z lufy (poza nominalna rozjechała się z `_pose_body`)" % MAX_REST_PX)
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true
