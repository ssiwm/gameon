extends SceneTree
## Test zegara pogody (scripts/weather_clock.gd, WEATHER_PLAN.md W1): siła, wiatr, podmuchy i błyskawice wyłącznie z ziarna i czasu —
## ta sama wartość niezależnie od kolejności zapytań i od tego, czy harmonogram liczono od zera (dołączający gracz), zakresy siły
## wg pogody, gładkość, fronty, częstość podmuchów, błyskawice tylko w burzy z odległością, kierunkiem i opóźnieniem grzmotu.
##   godot --headless --path prototype -s tools/test_weather_clock.gd     → ostatni wiersz: PASS / FAIL

const WC := preload("res://scripts/weather_clock.gd")
const IDS := ["clear", "rain", "storm", "fog"]
const SEEDS := [1, 42, 9001, 123456789, -77]

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[WEATHER-CLOCK] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _init() -> void:
	# deterministyka: zapytanie „od końca” (dołączający po 20 min) i od nowa daje to samo co marsz od zera
	var same := true
	for sd in SEEDS:
		for id in IDS:
			WC.clear_cache()
			var late := [WC.intensity(id, sd, 1500.0), WC.gust(id, sd, 1500.0), WC.wind(id, sd, 1500.0), WC.bolts_between(sd, 1400.0, 1500.0).size()]
			WC.clear_cache()
			var t := 0.0
			while t < 1500.0:
				WC.intensity(id, sd, t)
				WC.gust(id, sd, t)
				WC.bolts_between(sd, t, t + 0.5)
				t += 0.5
			var walk := [WC.intensity(id, sd, 1500.0), WC.gust(id, sd, 1500.0), WC.wind(id, sd, 1500.0), WC.bolts_between(sd, 1400.0, 1500.0).size()]
			same = same and late == walk
	_check("ta sama pogoda bez względu na kolejność zapytań (dołączający gracz)", same)
	var differ := WC.intensity("rain", 1, 300.0) != WC.intensity("rain", 2, 300.0) or WC.gust("rain", 1, 300.0) != WC.gust("rain", 2, 300.0)
	_check("inne ziarno — inna pogoda", differ)

	# zakresy, gładkość, fronty
	var in_range := true
	var smooth := true
	var fronts := true
	var worst_step := 0.0
	for sd in SEEDS:
		for id in IDS:
			var lv: Array = WC.LEVELS[id]
			var lo := INF
			var hi := -INF
			var prev := WC.intensity(id, sd, 0.0)
			var t := 0.25
			while t < 1200.0:
				var v := WC.intensity(id, sd, t)
				lo = minf(lo, v)
				hi = maxf(hi, v)
				worst_step = maxf(worst_step, absf(v - prev) / 0.25)
				prev = v
				t += 0.25
			in_range = in_range and lo >= float(lv[0]) - 0.04 and hi <= 1.0
			fronts = fronts and hi - lo >= 0.12
	smooth = worst_step < 0.06
	_check("siła w zakresie pogody (min ≥ słabszy front − falowanie)", in_range)
	_check("siła zmienia się płynnie (najszybciej %.3f /s < 0,06)" % worst_step, smooth)
	_check("w 20 min są fronty mocniejsze i słabsze (rozpiętość ≥ 0,12)", fronts)
	_check("nieznana pogoda (kryjówka) — siła 0", WC.intensity("", 1, 10.0) == 0.0)

	# podmuchy: zakres i częstość wg pogody
	var counts := {}
	var gust_ok := true
	for id in IDS:
		var n := 0
		var was := false
		var t := 0.0
		while t < 1200.0:
			var g := WC.gust(id, 42, t)
			gust_ok = gust_ok and g >= 0.0 and g <= 1.0
			var on := g > 0.2
			if on and not was:
				n += 1
			was = on
			t += 0.1
		counts[id] = n
	print("[WEATHER-CLOCK] podmuchy w 20 min: %s" % str(counts))
	_check("podmuchy 0..1", gust_ok)
	_check("burza ma najwięcej podmuchów, mgła najmniej", int(counts["storm"]) > int(counts["rain"]) and int(counts["rain"]) > int(counts["fog"]) and int(counts["fog"]) >= 1)
	var w_order := WC.wind("storm", 42, 100.0) > WC.wind("rain", 42, 100.0) and WC.wind("rain", 42, 100.0) > WC.wind("fog", 42, 100.0)
	_check("wiatr: burza > deszcz > mgła", w_order)

	# zapowiedź: wiatr reaguje na siłę pogody za WIND_LEAD_S
	var lead_ok := true
	for sd in SEEDS:
		var t := 0.0
		var best := 0.0
		var best_t := 0.0
		while t < 900.0:
			var d := WC.intensity("rain", sd, t + 1.0) - WC.intensity("rain", sd, t)
			if d > best:
				best = d
				best_t = t
			t += 1.0
		var calm := WC.wind("rain", sd, best_t - WC.WIND_LEAD_S - 20.0) / (1.0 + 0.45 * WC.gust("rain", sd, best_t - WC.WIND_LEAD_S - 20.0))
		var omen := WC.wind("rain", sd, best_t - WC.WIND_LEAD_S + 10.0) / (1.0 + 0.45 * WC.gust("rain", sd, best_t - WC.WIND_LEAD_S + 10.0))
		lead_ok = lead_ok and (best < 0.005 or omen > calm)
	_check("wiatr rośnie przed narastaniem deszczu (zapowiedź)", lead_ok)

	# kierunek wiatru: obie strony
	var dirs := {}
	for sd in range(40):
		dirs[WC.direction(sd)] = true
	_check("kierunek wiatru ±1, obie strony w 40 ziarnach", dirs.has(1.0) and dirs.has(-1.0) and dirs.size() == 2)

	# błyskawice
	var all: Array = []
	for sd in SEEDS:
		all.append_array(WC.bolts_between(sd, 0.0, 1800.0))
	var gaps_ok := true
	var dist_ok := true
	var near := 0
	for sd in SEEDS:
		var b := WC.bolts_between(sd, 0.0, 1800.0)
		for j in range(1, b.size()):
			gaps_ok = gaps_ok and float(b[j]["t"]) - float(b[j - 1]["t"]) >= WC.BOLT_GAP.x * 0.7 - 0.01
	for b in all:
		var d := float(b["dist"])
		dist_ok = dist_ok and d >= WC.BOLT_DIST.x and d <= WC.BOLT_DIST.y and absf(float(b["az"])) <= 1.0 and float(b["k"]) > 0.0 and float(b["k"]) <= 1.0
		if d < WC.NEAR_KM:
			near += 1
	var frac := float(near) / float(maxi(all.size(), 1))
	print("[WEATHER-CLOCK] błyskawice: %d w 5 × 30 min, bliskich %.0f%%" % [all.size(), frac * 100.0])
	_check("błyskawic 50–1000 na 5 × 30 min, odstępy ≥ %.1f s" % (WC.BOLT_GAP.x * 0.7), all.size() >= 50 and all.size() <= 1000 and gaps_ok)
	_check("odległość, azymut i siła błyskawic w zakresie", dist_ok)
	_check("bliskich (< 1,5 km) 5–25%", frac >= 0.05 and frac <= 0.25)
	var mono := WC.thunder_delay(0.4) < WC.thunder_delay(2.0) and WC.thunder_delay(2.0) < WC.thunder_delay(4.0) and WC.thunder_delay(8.0) <= WC.THUNDER_MAX_S
	_check("grzmot: opóźnienie rośnie z odległością (0,4 km %.1f s, 2 km %.1f s, 8 km %.1f s)" % [WC.thunder_delay(0.4), WC.thunder_delay(2.0), WC.thunder_delay(8.0)], mono)
	_check("siła błysku maleje z odległością", WC.bolt_strength(0.5) > WC.bolt_strength(3.0) and WC.bolt_strength(3.0) > WC.bolt_strength(8.0))
	var halves := WC.bolts_between(42, 0.0, 600.0).size() == WC.bolts_between(42, 0.0, 300.0).size() + WC.bolts_between(42, 300.0, 600.0).size()
	_check("okna czasu się nie nakładają (każdy błysk raz)", halves)

	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
