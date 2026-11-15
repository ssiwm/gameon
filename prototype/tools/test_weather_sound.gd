extends SceneTree
## Test dźwięku pogody (scripts/weather_sound.gd, WEATHER_PLAN.md W2–W4): materiał deszczu w kolumnach mapy (`level.rain_top`),
## przegląd kolumn (krople per materiał i strona z panoramą, dach nad głową, okapy), przenikanie warstw tła wg siły, krople na kapturze
## tylko lokalnego gracza pod niebem, filtr pod ziemią, ściszanie pogody pod ważnymi sygnałami, warstwy wiatru i wagi emiterów
## `amb_gust` / `amb_creak`, grzmot (klasa z odległości, trzask tylko blisko, filtr, panorama z azymutu, drżenie szyb pod dachem,
## napis z kierunkiem, te same warianty u wszystkich), pętle pogody ≥ 60 s i wszystkie klucze w banku.
##   godot --headless --path prototype -s tools/test_weather_sound.gd     → ostatni wiersz: PASS / FAIL

var _fails := 0
var WS: GDScript               ## weather_sound.gd i level.gd odwołują się do autoloadów — ładowane po pierwszej klatce, nie preload
var LevelScript: GDScript


## Udawany poziom: kolumny z gotowym wynikiem `rain_top`.
class FakeLevel extends Node:
	const TILE := 16
	var sound_grid = null
	var tops := {}
	func rain_top(c: int) -> Array:
		return tops.get(c, [20, "dirt", false])


func _check(name: String, ok: bool) -> void:
	print("[WEATHER-SOUND] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	await process_frame                                  # autoloady (Audio, NoiseMgr) są w drzewie od pierwszej klatki
	var audio: Node = root.get_node("Audio")
	WS = load("res://scripts/weather_sound.gd")
	LevelScript = load("res://scripts/level.gd")
	if WS == null or LevelScript == null or not WS.can_instantiate():
		print("FAIL: weather_sound.gd / level.gd się nie kompilują")
		quit(1)
		return

	# --- level.rain_top: pierwsza bryła od góry i jej materiał
	var lvl = LevelScript.new()
	lvl._map = [
		"................",
		"..MMMM....------",
		"..........w.....",
		"..........w.....",
		"#####CCCC~~~##mm",
	]
	var exp := {0: [4, "dirt", false], 2: [1, "metal", true], 6: [4, "concrete", false], 9: [4, "water", false],
		10: [1, "wood", true], 11: [1, "wood", true], 12: [1, "wood", true], 14: [1, "wood", true], -1: [-1, "", false], 16: [-1, "", false]}
	var rt_ok := true
	for c in exp:
		var got: Array = lvl.rain_top(int(c))
		if got != exp[c]:
			print("  rain_top(%d) = %s, oczekiwano %s" % [c, got, exp[c]])
			rt_ok = false
	lvl._map = ["..........", "..w.......", "..w.......", "####mm##OO"]
	rt_ok = rt_ok and lvl.rain_top(2) == [3, "leaves", false] and lvl.rain_top(5) == [3, "water", false] and lvl.rain_top(8) == [3, "water", false]
	_check("level.rain_top: blacha, kładka z desek, beton, woda i bagno, grunt pod drzewem = liście, poza mapą pusto", rt_ok)
	lvl.free()

	# --- przegląd kolumn i deszcz
	var snd = WS.new()
	root.add_child(snd)
	var fake := FakeLevel.new()
	root.add_child(fake)
	audio._listener_pos = Vector2(50 * 16 + 8, 20 * 16)        # kolumna 50, stopy na wierzchu wiersza 20
	for c in range(30, 71):
		fake.tops[c] = [20, "metal" if c < 50 else "dirt", false]
	snd._ear = audio._listener_pos
	snd._scan(fake)
	var dr: Dictionary = snd._drops
	var lm: Array = dr.get("metal|L", [0.0, 0.0])
	var rd: Array = dr.get("dirt|R", [0.0, 0.0])
	_check("przegląd: blacha po lewej, ziemia po prawej, środek ciężkości po swojej stronie (%s / %s)" % [lm, rd],
		dr.has("metal|L") and dr.has("dirt|R") and not dr.has("metal|R") and float(lm[1]) < -1.0 and float(rd[1]) > 1.0
		and float(lm[0]) > 0.3 and float(lm[0]) <= 1.01)
	# dach z blachy nad głową, okap na krawędzi dachu
	for c in range(46, 55):
		fake.tops[c] = [14, "metal", true]
	snd._col_ver = -99
	snd._col_cache.clear()
	snd._scan(fake)
	var rf: Array = snd._roof
	var eaves: Array = snd._eaves
	_check("pod blaszanym dachem: deszcz nad głową z blachy, dach nie jest emiterem kropel, dwa okapy po obu stronach (%s, %d)" % [rf, eaves.size()],
		rf[0] == "metal" and int(rf[1]) == 5 and eaves.size() == 2 and float(eaves[0][0]) * float(eaves[1][0]) < 0.0)
	var st := {"id": "rain", "on": true, "k": 1.0, "i": 0.8, "wind": 0.6, "gust": 0.0, "wdir": 1.0, "sky": 0.0, "deep": 0.0, "cave": 0.0,
		"lp": null, "level": fake}
	snd._want.clear()
	snd._rain("rain", st, null)
	var w: Dictionary = snd._want
	_check("pod dachem gra roof (rain_roof_metal) i okapy, nie gra kaptur", w.has("roof") and String(w["roof"]["s"]) == "rain_roof_metal"
		and w.has("eave|0") and not w.has("mask"))
	# tło: przenikanie warstw
	fake.tops.clear()
	snd._col_ver = -98
	snd._col_cache.clear()
	snd._scan(fake)
	var beds := func(i: float) -> Array:
		snd._want.clear()
		var s2 := st.duplicate()
		s2["i"] = i
		s2["sky"] = 1.0
		snd._rain("rain", s2, null)
		var out := []
		var pw := 0.0
		for b in WS.BEDS:
			if snd._want.has(b):
				out.append(b)
				pw += pow(db_to_linear(float(snd._want[b]["db"])), 2.0)
		out.append(pw)
		return out
	var b0: Array = beds.call(0.2)
	var b1: Array = beds.call(0.82)
	var b2: Array = beds.call(1.0)
	_check("tło deszczu: słaby = lekki, średni = średni + ulewa, pełna siła = ulewa (%s | %s | %s)" % [b0.slice(0, -1), b1.slice(0, -1), b2.slice(0, -1)],
		b0.slice(0, -1) == ["amb_rain_light"] and b1.slice(0, -1) == ["amb_rain_mid", "amb_rain_heavy"] and b2.slice(0, -1) == ["amb_rain_heavy"]
		and float(b2[-1]) > float(b0[-1]))
	# kaptur tylko lokalnego gracza pod niebem
	var lp := Node2D.new()
	root.add_child(lp)
	snd._want.clear()
	var s3 := st.duplicate()
	s3["sky"] = 1.0
	snd._rain("rain", s3, lp)
	var mask_sky: bool = snd._want.has("mask")
	snd._want.clear()
	s3["sky"] = 0.0
	snd._rain("rain", s3, lp)
	_check("krople na kapturze: lokalny gracz pod niebem tak, pod dachem nie, bez gracza (serwer) nie", mask_sky and not snd._want.has("mask"))

	# --- pod ziemią: filtr na szynie pogody
	var s4 := st.duplicate()
	s4["deep"] = 1.0
	snd.update(0.016, s4)
	for _f in 40:
		audio._update_weather_mix(0.05)
	var under_hz := float(audio._wunder_fx.cutoff_hz) if audio._wunder_fx != null else -1.0
	s4["deep"] = 0.0
	snd.update(0.016, s4)
	for _f in 40:
		audio._update_weather_mix(0.05)
	var open_hz := float(audio._wunder_fx.cutoff_hz) if audio._wunder_fx != null else -1.0
	_check("pod ziemią szyna pogody ciemnieje (%.0f Hz), na powierzchni otwarta (%.0f Hz)" % [under_hz, open_hz],
		under_hz > 0.0 and under_hz < 800.0 and open_hz > 15000.0)

	# --- ściszanie pod ważnymi sygnałami
	audio._wduck_db = 0.0
	audio._wduck_hold = 0.0
	audio._weather_signal("step_concrete_1")
	audio._update_weather_mix(0.05)
	var quiet: float = audio.weather_duck_db()
	audio._weather_signal("stalker_shriek_1")
	for _f in 4:
		audio._update_weather_mix(0.05)
	var ducked: float = audio.weather_duck_db()
	for _f in 60:
		audio._update_weather_mix(0.05)
	var back: float = audio.weather_duck_db()
	_check("pogoda cichnie pod krzykiem Stalkera (%.1f dB), nie pod krokiem (%.1f dB), wraca (%.1f dB)" % [ducked, quiet, back],
		quiet > -0.1 and ducked < -3.0 and back > -0.3)

	# --- wiatr
	var m_calm: Array = WS.wind_mix(WS.wind_norm(0.1))
	var m_storm: Array = WS.wind_mix(WS.wind_norm(2.2))
	_check("warstwy wiatru: cisza = sam niski pomruk, burza = wszystkie trzy (%s / %s)" % [m_calm, m_storm],
		float(m_calm[0]) > 0.0 and float(m_calm[2]) == 0.0 and float(m_storm[1]) > 1.0 and float(m_storm[2]) > 0.5)
	var gust_e: Array = audio.EMITTERS[0]
	audio.weather_wind = 0.2
	var wc: float = audio._emitter_weight(gust_e)
	audio.weather_wind = 2.0
	var ws_: float = audio._emitter_weight(gust_e)
	audio.weather_wind = audio.WIND_REF
	var wr: float = audio._emitter_weight(gust_e)
	var thud: float = audio._emitter_weight(audio.EMITTERS[2])
	_check("emitery: podmuch rzadki w ciszy (%.2f), częsty w burzy (%.2f), bez pogody jak dotąd (%.2f), uderzenie bez zmian (%.2f)" % [wc, ws_, wr, thud],
		wc < 0.5 and ws_ > 6.0 and is_equal_approx(wr, float(gust_e[5])) and is_equal_approx(thud, float(audio.EMITTERS[2][5])))
	snd._want.clear()
	snd._wind("storm", {"k": 1.0, "wind": 1.9, "gust": 0.8, "wdir": -1.0, "sky": 1.0})
	var gw: Dictionary = snd._want.get("gust", {})
	_check("podmuch nadchodzi od strony wiatru (wiatr z lewej → panorama w lewo)", not gw.is_empty() and (gw["off"] as Vector2).x < 0.0)
	snd.update(0.016, {"id": "", "on": false, "wind": 1.9})
	_check("bez dźwięku pogody emitery wiatru wracają do wagi z EMITTERS", is_equal_approx(audio.weather_wind, audio.WIND_REF))

	# --- grzmot
	var caps: Array = []
	audio.caption.connect(func(t: String, p: Vector2, _pr: int) -> void: caps.append([t, p]))
	snd._ear = Vector2.ZERO
	audio._listener_pos = Vector2.ZERO
	snd.thunder({"dist": 0.8, "az": -0.7, "i": 3}, 1.0, 1234)
	var near: Dictionary = snd.last_thunder()
	snd.thunder({"dist": 7.5, "az": 0.6, "i": 4}, 1.0, 1234)
	var far: Dictionary = snd.last_thunder()
	snd.thunder({"dist": 2.5, "az": 0.0, "i": 5}, 0.0, 1234)
	var indoor: Dictionary = snd.last_thunder()
	var roll_n := func(t: Dictionary) -> int:
		for k in t["keys"]:
			if String(k).begins_with("thunder_roll_"):
				return int(String(k).get_slice("_", 2))
		return -1
	_check("grzmot blisko: trzask + bliższe toczenie, jasny filtr, napis „blisko” z lewej (%s, %.0f Hz)" % [near["keys"], near["hz"]],
		near["cls"] == "near" and str(near["keys"]).contains("thunder_crack_") and roll_n.call(near) in [1, 2, 3]
		and float(near["hz"]) > 8000.0 and near["caption"] == "[Thunder — close]" and caps.size() >= 1 and (caps[0][1] as Vector2).x < 0.0)
	_check("grzmot daleko: bez trzasku, dalekie toczenie, ciemny filtr i ciszej, napis „daleki” z prawej (%s, %.0f Hz, %.1f dB)" % [far["keys"], far["hz"], far["db"]],
		far["cls"] == "far" and not str(far["keys"]).contains("thunder_crack_") and roll_n.call(far) in [4, 5, 6]
		and float(far["hz"]) < 1500.0 and float(far["db"]) < float(near["db"]) - 6.0 and far["caption"] == "[Distant thunder]"
		and caps.size() >= 2 and (caps[1][1] as Vector2).x > 0.0)
	_check("grzmot pod dachem: drżenie szyb, ciemniej (%s, %.0f Hz)" % [indoor["keys"], indoor["hz"]],
		str(indoor["keys"]).contains("thunder_rattle_") and float(indoor["hz"]) < 6000.0)
	snd.thunder({"dist": 0.8, "az": -0.7, "i": 3}, 1.0, 1234)
	_check("ta sama błyskawica = te same warianty (u każdego gracza)", snd.last_thunder()["keys"] == near["keys"])

	# --- bank: wszystkie klucze pogody, pętle ≥ 60 s
	var keys: Array = WS.BEDS + WS.WIND_LAYERS.keys() + [WS.EAVE[0], WS.MASK[0], WS.GUST[0], WS.WINDOW[0]]
	for m in WS.DROPS:
		keys.append(WS.DROPS[m][0])
	for m in WS.ROOFS:
		if not keys.has(WS.ROOFS[m][0]):
			keys.append(WS.ROOFS[m][0])
	var missing: Array = []
	var short: Array = []
	for k in keys:
		var s: AudioStream = audio.stream(String(k))
		if s == null:
			missing.append(k)
		elif s.get_length() < 60.0:
			short.append("%s %.1f s" % [k, s.get_length()])
	for i in range(1, 4):
		if audio.stream("thunder_crack_%d" % i) == null:
			missing.append("thunder_crack_%d" % i)
	for i in range(1, 7):
		if audio.stream("thunder_roll_%d" % i) == null:
			missing.append("thunder_roll_%d" % i)
	for i in range(1, 3):
		if audio.stream("thunder_rattle_%d" % i) == null:
			missing.append("thunder_rattle_%d" % i)
	_check("bank: wszystkie klucze pogody są (brak: %s), pętle ≥ 60 s (krótsze: %s)" % [missing, short], missing.is_empty() and short.is_empty())

	snd.stop_all()
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
