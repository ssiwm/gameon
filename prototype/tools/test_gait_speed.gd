extends SceneTree
## Test prędkości do tempa kroku wrogów w widoku 3D (scripts/gait_speed.gd): symulacja przesuwa wroga co krok fizyki 60 Hz, obraz
## idzie w różnym tempie (30, 45, 60, 75, 120, 144, 240 kl./s, nierówne klatki). Prędkość ma być bliska prawdziwej w każdej klatce
## ruchu (bez zer i skoków 2,4×), droga z niej ma się zgadzać z przebytą, a po zatrzymaniu i przeniesieniu wroga — spaść do zera.
##   godot --headless --path prototype -s tools/test_gait_speed.gd     → ostatni wiersz: PASS / FAIL

const GaitSpeed := preload("res://scripts/gait_speed.gd")
const PHYS := 1.0 / 60.0

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[GAIT] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


## Bieg ze stałą prędkością `v` px/s przez `secs` s przy obrazie `fps` (z wahaniem klatki `jitter` × okres). Zwraca
## [najmniejsza i największa prędkość w klatkach po rozbiegu, droga z prędkości / droga przebyta, droga z `gd` / przebyta].
func _run(v: float, fps: float, secs: float, jitter := 0.0) -> Array:
	var st := {}
	var t := 0.0
	var phys_t := 0.0
	var x := 0.0
	var lo := INF
	var hi := 0.0
	var integ := 0.0
	var steps := 0.0
	var seed := 7
	GaitSpeed.update(st, x, 0.0)
	while t < secs:
		seed = (seed * 1103515245 + 12345) % 2147483648
		var dt := (1.0 / fps) * (1.0 + jitter * (float(seed % 1000) / 500.0 - 1.0))
		t += dt
		while phys_t + PHYS <= t:                   # kroki fizyki, które zmieściły się w tej klatce obrazu
			phys_t += PHYS
			x += v * PHYS
		var s := GaitSpeed.update(st, x, dt)
		integ += s * dt
		steps += float(st["gd"])
		if t > 0.2:
			lo = minf(lo, s)
			hi = maxf(hi, s)
	return [lo, hi, integ / maxf(x, 0.001), steps / maxf(x, 0.001)]


func _initialize() -> void:
	var v := 75.0
	for fps in [30.0, 45.0, 60.0, 75.0, 120.0, 144.0, 240.0]:
		var r := _run(v, fps, 4.0)
		print("[GAIT] %3d kl./s: prędkość %.1f…%.1f px/s, droga z prędkości / przebyta %.3f" % [int(fps), r[0], r[1], r[2]])
		_check("%d kl./s: w ruchu nigdy poniżej 0,8 prędkości (dawniej 0 → „idle”)" % int(fps), float(r[0]) > v * 0.8)
		_check("%d kl./s: w ruchu nigdy ponad 1,2 prędkości (dawniej 2,4×)" % int(fps), float(r[1]) < v * 1.2)
		_check("%d kl./s: droga z prędkości zgodna z przebytą ±2%%" % int(fps), absf(float(r[2]) - 1.0) < 0.02)
		_check("%d kl./s: droga z `gd` (faza kroku) równa przebytej" % int(fps), absf(float(r[3]) - 1.0) < 1e-6)
	var rj := _run(v, 60.0, 4.0, 0.25)
	print("[GAIT] 60 kl./s ±25%%: prędkość %.1f…%.1f px/s, droga %.3f" % [rj[0], rj[1], rj[2]])
	_check("60 kl./s z nierównymi klatkami: bez zer w ruchu", float(rj[0]) > v * 0.4)
	_check("60 kl./s z nierównymi klatkami: droga ±5%", absf(float(rj[2]) - 1.0) < 0.05)
	# zatrzymanie: po oknie bez zmiany pozycji prędkość 0
	var st := {}
	GaitSpeed.update(st, 0.0, 0.0)
	GaitSpeed.update(st, 1.25, PHYS)
	_check("ruch po jednym kroku", GaitSpeed.update(st, 1.25, 0.0) > 70.0)
	var s := 1.0
	var t := 0.0
	while t < GaitSpeed.WINDOW + 0.02:
		t += 1.0 / 144.0
		s = GaitSpeed.update(st, 1.25, 1.0 / 144.0)
	_check("stoi dłużej niż okno → 0", s == 0.0)
	# przeniesienie (odrodzenie, punkt kontrolny): skok pozycji to nie bieg
	_check("skok o 300 px → 0, nie 18 000 px/s", GaitSpeed.update(st, 301.25, PHYS) == 0.0)
	_check("skok o 300 px: faza kroku stoi", float(st["gd"]) == 0.0)
	_check("pierwsza próbka → 0", GaitSpeed.update({}, 50.0, PHYS) == 0.0)
	# drganie w miejscu (rozpychanie, odbicie od ściany): ±1 px co krok fizyki przy 144 kl./s to nie bieg 120 px/s
	var sj := {}
	var tj := 0.0
	var pj := 0.0
	var xj := 0.0
	var hj := 0.0
	GaitSpeed.update(sj, xj, 0.0)
	while tj < 1.0:
		tj += 1.0 / 144.0
		while pj + PHYS <= tj:
			pj += PHYS
			xj = 1.0 - xj
		var sv := GaitSpeed.update(sj, xj, 1.0 / 144.0)
		if tj > 0.2:
			hj = maxf(hj, sv)
	print("[GAIT] drganie ±1 px co krok: najwyżej %.1f px/s" % hj)
	_check("drganie w miejscu: najwyżej 15 px/s", hj <= 15.0)
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
