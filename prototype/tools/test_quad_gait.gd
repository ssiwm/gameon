extends SceneTree
## Chód Trzoska w widoku 3D (enemy3d.gd: `QUAD_GAIT_PX`, `QUAD_GAIT_FADE`, długość kroku): stęp i galop mają inną kolejność stawiania
## łap, więc ich mieszanka w tej samej fazie daje łapę machającą 3–4 razy na cykl („przebieranie” w błocie, wodzie, oleju).
## Sprawdza na modelu z klipami: prędkości z podłoży i poziomów trudności dają czysty galop, wataha krążąca w oczekiwaniu idzie stępem,
## zmiana prędkości przechodzi między chodami krótko i bez migotania wokół progu, przednie łapy zmieniają kierunek najwyżej 2 razy na cykl,
## tempo galopu w błocie blisko tempa klipu, a na suchym gruncie bez zmian (cykl 48 px).
##   godot --headless --path prototype -s tools/test_quad_gait.gd     → ostatni wiersz: [QUAD-GAIT] PASS / FAIL

const Enemy3D := preload("res://scripts/enemy3d.gd")
const DT := 1.0 / 60.0
const PAWS := ["tripo__0_Left_Limb_4", "tripo__0_Right_Limb_4", "tripo__1_Left_Limb_4", "tripo__1_Right_Limb_4"]

var _fails := 0
var _e: Node3D
var _done := false


func _check(name: String, ok: bool) -> void:
	print("[QUAD-GAIT] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


## Bieg przez `secs` s z prędkością z `speed_at(t)` (px/s). Zwraca: ułamek klatek z mieszanką chodów (0,02 < waga galopu < 0,98)
## po `settle` s, końcową wagę galopu, liczbę zmian chodu, cykle / s, najwięcej zmian kierunku przedniej łapy na cykl i najdłuższy
## ciąg klatek z mieszanką (s).
func _run(speed_at: Callable, secs: float, settle := 0.6) -> Dictionary:
	var sk: Skeleton3D = _e.get("_sk")
	var t := 0.0
	var mixed := 0
	var counted := 0
	var flips := 0
	var last_on: bool = _e.get("_gallop_on")
	var ph0 := 0.0
	var run_mix := 0.0
	var max_mix := 0.0
	var paw := {}
	for p in PAWS:
		paw[p] = []
	while t < secs:
		var v: float = speed_at.call(t)
		_e.pose(DT, "run", false, Color.WHITE, 0.0, 1, true, 0.0, 0, false, v, v * DT)
		t += DT
		var gw: float = _e.get("_gallop_w")
		var on: bool = _e.get("_gallop_on")
		if on != last_on:
			flips += 1
			last_on = on
		var is_mix := gw > 0.02 and gw < 0.98
		run_mix = run_mix + DT if is_mix else 0.0
		max_mix = maxf(max_mix, run_mix)
		if t >= settle:
			if counted == 0:
				ph0 = float(_e.get("_phase"))
			counted += 1
			mixed += 1 if is_mix else 0
			sk.force_update_all_bone_transforms()
			for p in PAWS:
				paw[p].append(sk.get_bone_global_pose(sk.find_bone(p)).origin.z)
	var cycles := (float(_e.get("_phase")) - ph0) / TAU
	var worst := 0.0
	for p in PAWS.slice(0, 2):                  # przednie łapy — w mieszance to one „przebierały”
		worst = maxf(worst, _reversals(paw[p]) / maxf(cycles, 0.001))
	return {"mixed": float(mixed) / maxf(counted, 1), "gw": float(_e.get("_gallop_w")), "flips": flips,
			"hz": cycles / maxf(secs - settle, 0.001), "rev": worst, "max_mix": max_mix}


## Zmiany kierunku ruchu przód–tył (histereza 5% zakresu).
func _reversals(xs: Array) -> float:
	if xs.size() < 3:
		return 0.0
	var lo := INF
	var hi := -INF
	for x in xs:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	var h := 0.05 * (hi - lo)
	var rev := 0
	var dir := 0
	var anchor: float = xs[0]
	for x in xs:
		if dir >= 0 and x < anchor - h:
			rev += 1 if dir > 0 else 0
			dir = -1
			anchor = x
		elif dir <= 0 and x > anchor + h:
			rev += 1 if dir < 0 else 0
			dir = 1
			anchor = x
		elif (dir > 0 and x > anchor) or (dir < 0 and x < anchor):
			anchor = x
	return float(rev)


func _fresh() -> void:
	if _e != null:
		_e.queue_free()
	_e = (Enemy3D as Script).new()
	get_root().add_child(_e)
	if not _e.setup("trzosek"):
		_check("setup(trzosek)", false)


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_fresh()
	if _e.get("_sk") == null or not _e.call("_qhas", "gallop"):
		_check("model Trzoska z klipami walk / gallop", false)
		print("[QUAD-GAIT] FAIL (%d)" % _fails)
		return true
	var ref := 88.0
	var gallop_hz: float = 1.0 / float((_e.get("_ap") as AnimationPlayer).get_animation("gallop").length)
	# podłoża (surfaces.gd: błoto 0,58, woda 0,72, olej 0,9) × poziom trudności (difficulty.gd: 0,85 / 1,0 / 1,15)
	for diff in [["EASY", 0.85], ["NORMAL", 1.0], ["HARD", 1.15]]:
		for surf in [["grunt", 1.0], ["olej", 0.9], ["woda", 0.72], ["błoto", 0.58]]:
			var v: float = ref * float(diff[1]) * float(surf[1])
			_fresh()
			var r := _run(func(_t): return v, 3.0)
			_check("%s %s (%.0f px/s): czysty galop (waga %.2f, mieszanka %.0f%% klatek), przednie łapy %.1f zmian kierunku / cykl" % [diff[0], surf[0], v, r["gw"], 100.0 * r["mixed"], r["rev"]],
					r["gw"] > 0.98 and r["mixed"] == 0.0 and r["rev"] <= 2.2)
			if surf[0] == "błoto":
				_check("%s błoto: tempo galopu %.2f cykli/s = %.2f × klipu (0,6–1,3)" % [diff[0], r["hz"], r["hz"] / gallop_hz],
						r["hz"] / gallop_hz >= 0.6 and r["hz"] / gallop_hz <= 1.3)
	# suchy grunt na NORMAL bez zmian: 48,4 px na cykl jak przed poprawką
	_fresh()
	var dry := _run(func(_t): return ref, 3.0)
	_check("grunt NORMAL: %.2f cykli/s (przed poprawką 88 / 48,4 = %.2f)" % [dry["hz"], ref / (ref * 0.55)], absf(dry["hz"] - ref / (ref * 0.55)) < 0.03)
	# wataha krążąca w oczekiwaniu (enemy_pack.gd `_hover`: ±0,3 × prędkość, sinus) — stęp, bez skoków do galopu
	_fresh()
	var hover := _run(func(t): return absf(sin(t * 4.0)) * ref * 0.3 * 0.75, 4.0)      # okno 0,1 s ścina szczyty sinusa
	_check("krążenie watahy (≤ 20 px/s): stęp (waga galopu %.2f), %d zmian chodu, przednie łapy %.1f zmian kierunku / cykl" % [hover["gw"], hover["flips"], hover["rev"]],
			hover["gw"] < 0.02 and hover["flips"] == 0 and hover["rev"] <= 2.6)
	# drganie prędkości wokół progu — histereza nie przełącza chodu co chwilę
	_fresh()
	var near := _run(func(t): return 22.0 + 3.5 * sin(t * 17.0), 3.0)
	_check("prędkość 22 ± 3,5 px/s (między progami): %d zmian chodu, mieszanka %.0f%% klatek" % [near["flips"], 100.0 * near["mixed"]],
			near["flips"] == 0 and near["mixed"] == 0.0)
	# hamowanie z galopu do stępu i z powrotem: przejście krótkie (zmiany chodu: start → galop, galop → stęp, stęp → galop)
	_fresh()
	var sweep := _run(func(t): return ref * clampf(absf(t - 3.0) / 3.0, 0.1, 1.0), 6.0, 0.1)
	_check("88 → 9 → 88 px/s: %d zmiany chodu, najdłuższa mieszanka %.2f s (≤ 0,2), w mieszance %.0f%% klatek" % [sweep["flips"], sweep["max_mix"], 100.0 * sweep["mixed"]],
			sweep["flips"] == 3 and sweep["max_mix"] <= 0.2 and sweep["mixed"] < 0.08)
	print("[QUAD-GAIT] %s (%d)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return true
