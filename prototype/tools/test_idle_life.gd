extends SceneTree
## Warstwa spoczynku wrogów (IDLE_PLAN.md I1, idle_life.gd): to samo ziarno daje ten sam przebieg, różne ziarna rozjeżdżają fazę i okres
## oddechu, oddech nie zależy od liczby klatek, ciężar zmienia nogę w zadanym rytmie, tiki mają odstępy z profilu i gasną u niespokojnego.
## Na modelach dwunożnych: przez 30 s snu i czuwania dłonie zostają poniżej barków (tik nie wygląda jak zapowiedź ciosu), a pozy różnych
## egzemplarzy się różnią.
##   godot --headless --path prototype -s tools/test_idle_life.gd
const IdleLife := preload("res://scripts/idle_life.gd")
const Enemy3D := preload("res://scripts/enemy3d.gd")
const KINDS := ["slepiec", "podsluchacz", "stalker", "wolek", "kaplan", "rzeznik", "mimik"]

var _fails := 0
var _frames := 0
var _models: Array = []                      ## [rodzaj, Enemy3D, animacja, max (dłoń − bark) w m, ślad pozy głowy]

func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("[IDLE-LIFE] FAIL ", msg)

func _initialize() -> void:
	_test_determinism()
	_test_desync()
	_test_framerate()
	_test_shift()
	_test_tics()
	for k in KINDS:
		for anim in ["sleep", "idle"]:
			for seed_value in [11, 12]:
				var e: Node3D = Enemy3D.new()
				root.add_child(e)
				e.set("life_seed", seed_value)
				if not e.setup(k):
					_ok(false, "setup %s" % k)
					e.free()
					continue
				_models.append([k, e, anim, -INF, []])

func _trace(seed_value: int, dt: float, secs: float) -> Array:
	var l := IdleLife.new(seed_value, {"tics": ["jerk", "look"], "rate": [2.0, 5.0]})
	var out := []
	var n := int(secs / dt)
	for i in n:
		l.step(dt, false)
		out.append([l.breath(), l.shift, l.tic, l.tic_k])
	return out

func _test_determinism() -> void:
	_ok(_trace(7, 1.0 / 60.0, 30.0) == _trace(7, 1.0 / 60.0, 30.0), "to samo ziarno → ten sam przebieg")
	_ok(_trace(7, 1.0 / 60.0, 30.0) != _trace(8, 1.0 / 60.0, 30.0), "inne ziarno → inny przebieg")

func _test_desync() -> void:
	var phases := []
	var periods := []
	for s in 40:
		var l := IdleLife.new(1000 + s)
		phases.append(l.breath_phase())
		periods.append(l.period)
		_ok(l.period >= 2.4 * (1.0 - IdleLife.BREATH_SPREAD) - 0.001 and l.period <= 2.4 * (1.0 + IdleLife.BREATH_SPREAD) + 0.001, "okres oddechu w rozrzucie: %.3f" % l.period)
	# fazy rozłożone na całym cyklu: w każdej ćwiartce coś jest
	var q := [0, 0, 0, 0]
	for ph in phases:
		q[int(fposmod(float(ph), TAU) / TAU * 4.0) % 4] += 1
	_ok(q.min() >= 4, "fazy oddechu 40 egzemplarzy rozłożone na ćwiartki: %s" % str(q))
	_ok(periods.max() - periods.min() > 0.3, "okresy oddechu różne")

func _test_framerate() -> void:
	# oddech zależy tylko od czasu: 30 i 144 kl./s po 10 s dają to samo wypełnienie płuc
	var a := IdleLife.new(3)
	var b := IdleLife.new(3)
	for i in 300:
		a.step(1.0 / 30.0, false)
	for i in 1440:
		b.step(1.0 / 144.0, false)
	_ok(absf(a.breath() - b.breath()) < 0.02, "oddech niezależny od FPS: %.3f vs %.3f" % [a.breath(), b.breath()])
	var c := IdleLife.new(3)
	var before := c.breath()
	c.step(0.0, false)
	_ok(c.breath() == before, "krok 0 s nic nie zmienia")

func _test_shift() -> void:
	var l := IdleLife.new(5)
	var changes := 0
	var last_side := signf(l.shift)
	var max_abs := 0.0
	var dt := 1.0 / 60.0
	for i in int(120.0 / dt):
		l.step(dt, false)
		max_abs = maxf(max_abs, absf(l.shift))
		var side := signf(l.shift)
		if side != 0.0 and side != last_side:
			changes += 1
			last_side = side
	_ok(max_abs <= 1.0, "ciężar w −1..1")
	# 120 s przy 4–9 s stania + 1,2 s przenoszenia → 11–23 zmian nogi
	_ok(changes >= 10 and changes <= 25, "zmiany nogi w 120 s: %d" % changes)

func _test_tics() -> void:
	var dt := 1.0 / 60.0
	var l := IdleLife.new(9, {"tics": ["jerk"], "rate": [3.0, 6.0]})
	var starts := []
	var was := ""
	var max_k := 0.0
	for i in int(120.0 / dt):
		l.step(dt, false)
		if l.tic != "" and was == "":
			starts.append(l.t)
		was = l.tic
		max_k = maxf(max_k, l.tic_k)
	_ok(starts.size() >= 15 and starts.size() <= 42, "tików w 120 s (odstęp 3–6 s): %d" % starts.size())
	for i in range(1, starts.size()):
		_ok(starts[i] - starts[i - 1] >= 3.0 - 0.05, "odstęp tików ≥ 3 s: %.2f" % (starts[i] - starts[i - 1]))
	_ok(max_k > 0.9 and max_k <= 1.0, "obwiednia tiku do 1: %.2f" % max_k)
	# śpiący wierci się rzadziej
	var s := IdleLife.new(9, {"tics": ["jerk"], "rate": [3.0, 6.0]})
	var n_sleep := 0
	was = ""
	for i in int(120.0 / dt):
		s.step(dt, true)
		if s.tic != "" and was == "":
			n_sleep += 1
		was = s.tic
	_ok(n_sleep < starts.size(), "śpiący ma mniej tików: %d < %d" % [n_sleep, starts.size()])
	# niespokojny (zapowiedź, „zauważył”): tik gaśnie w ≤ 0,3 s i nowy się nie zaczyna
	var u := IdleLife.new(9, {"tics": ["look"], "rate": [0.5, 0.6]})
	while u.tic_k < 0.5:
		u.step(dt, false)
	for i in int(0.3 / dt):
		u.step(dt, false, false)
	_ok(u.tic_k < 0.01, "niespokojny: tik zgaszony (%.3f)" % u.tic_k)
	var started := false
	for i in int(5.0 / dt):
		u.step(dt, false, false)
		started = started or u.tic_k > 0.01
	_ok(not started, "niespokojny: brak nowych tików przez 5 s")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _frames <= 3 + 30 * 60:
		for m in _models:
			var e: Node3D = m[1]
			e.call("pose", 1.0 / 60.0, String(m[2]), false, Color.WHITE)
			var sk: Skeleton3D = e.get("_sk")
			var b: Dictionary = e.get("_b")
			for side in ["Right", "Left"]:
				var hand := sk.get_bone_global_pose(b[side + "Hand"]).origin
				var arm := sk.get_bone_global_pose(b[side + "Arm"]).origin
				m[3] = maxf(float(m[3]), hand.y - arm.y)
			if _frames % 30 == 0:
				(m[4] as Array).append(sk.get_bone_global_pose(b["Head"]).basis.get_euler())
		return false
	var heads := {}
	for m in _models:
		_ok(float(m[3]) < 0.0, "%s %s (ziarno %s): dłoń poniżej barku (max %.3f m)" % [m[0], m[2], m[1].get("life_seed"), float(m[3])])
		var key := "%s/%s" % [m[0], m[2]]
		if not heads.has(key):
			heads[key] = []
		(heads[key] as Array).append(m[4])
	for key in heads:
		var tr: Array = heads[key]
		if tr.size() == 2:
			_ok(tr[0] != tr[1], "%s: dwa egzemplarze ruszają głową inaczej" % key)
		var moved := 0.0
		var t0: Array = tr[0]
		for v in t0:
			moved = maxf(moved, ((v as Vector3) - (t0[0] as Vector3)).length())
		_ok(moved > deg_to_rad(1.0), "%s: głowa nie stoi w miejscu przez 30 s (%.1f°)" % [key, rad_to_deg(moved)])
	print("[IDLE-LIFE] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
	return true
