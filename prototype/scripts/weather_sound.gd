extends Node
## Dźwięk pogody (WEATHER_PLAN.md W2–W4): deszcz z warstw i z emiterów na materiałach, wiatr z warstw i podmuchów, grzmot warstwowy.
## Węzeł-dziecko `weather_fx.gd`, który co klatkę podaje stan (`update`) i każdy grzmot po opóźnieniu z odległości (`thunder`).
## Czysta kosmetyka, lokalna (D2): wszystko liczy się z zegara pogody (`weather_clock.gd`) i z mapy, bez RPC.
##
## Deszcz (W2):
## - Tło: trzy pętle (lekki, średni, ulewa) przenikane wg siły pogody `I(t)`; pętle ≥ 60 s o długościach względnie pierwszych.
## - Emitery (jak w Hunt: Showdown, w 2D tanio): co SCAN_S kolumny ±SCAN_COLS kafli od słuchacza, w każdej pierwsza bryła od góry
##   (`level.rain_top` — ta sama zasada co tekstura dachów deszczu w widoku 3D) daje materiał kropel. Energia kolumn (bliżej = więcej)
##   sumuje się per materiał i stronę; po jednej pętli kropel na materiał i stronę, w środku ciężkości swoich kolumn → panorama.
## - Pod dachem: deszcz na dachu nad głową z materiału dachu (blacha bębni, deski głucho); okapy — strumień z krawędzi dachu.
## - Pod ziemią: filtr dolnoprzepustowy szyny pogody (AudioDirector `set_weather_underground`) zamiast samego ściszenia.
## - Krople na kapturze i masce: cicha warstwa tylko dla lokalnego gracza pod niebem (D5; mokre kroki ma każdy — audio_director.gd).
## Wiatr (W3): trzy warstwy (niski pomruk, korony, świst) wg siły wiatru `W(t)`, podmuch z harmonogramu W1 z panoramą od strony
## wiatru (narastanie przed szczytem z obwiedni zegara), świst w najbliższym oknie (stłuczona szyba gwiżdże głośniej); emitery
## `amb_gust` / `amb_creak` ważone siłą wiatru (AudioDirector `weather_wind`).
## Grzmot (W4): trzask (tylko < 1,5 km) + toczenie (bliższe jaśniejsze, dalekie ciemne); filtr i głośność z odległości, panorama
## z azymutu błyskawicy, pod dachem ciszej, ciemniej i z drżeniem szyb; napis z kierunkiem (dostępność).
## Wszystko na szynie „Weather” (suwak „Weather”, D4), ściszanej pod ważnymi sygnałami (zasada 5, AudioDirector `duck_weather`).

const WeatherClock := preload("res://scripts/weather_clock.gd")

## Tło deszczu: klucze warstw i ich położenie na osi siły (0 — przejaśnienie, 1 — ulewa).
const BEDS := ["amb_rain_light", "amb_rain_mid", "amb_rain_heavy"]
const BED_AT := [0.0, 0.5, 1.0]
const RAIN_DB := {"rain": -14.0, "storm": -11.0}          ## tło deszczu przy pełnej sile i pod niebem [dB]
const RAIN_DROPS_DB := {"rain": 0.0, "storm": 2.0}        ## emitery kropel względem tabeli DROPS
## Krople na materiale: materiał z `level.rain_top` → [pętla, dB przy pełnej energii jednej strony].
const DROPS := {
	"metal": ["rain_on_metal", -15.0],
	"wood": ["rain_on_wood", -16.0],
	"dirt": ["rain_on_dirt", -18.0],
	"leaves": ["rain_on_leaves", -16.0],
	"concrete": ["rain_on_concrete", -17.0],
	"water": ["rain_on_water", -16.0],
}
## Deszcz na dachu nad głową: materiał dachu → [pętla, dB]; ziemia i skała nad głową tylko głucho dudnią.
const ROOFS := {
	"metal": ["rain_roof_metal", -13.0],
	"wood": ["rain_roof_wood", -14.0],
	"concrete": ["rain_roof_wood", -19.0],
	"dirt": ["rain_roof_wood", -22.0],
	"leaves": ["rain_roof_wood", -22.0],
	"water": ["rain_roof_wood", -22.0],
}
const EAVE := ["rain_eave", -15.0]                        ## strumień z okapu
const MASK := ["rain_mask", -24.0]                        ## krople na kapturze i masce lokalnego gracza
const SCAN_COLS := 12                                     ## zasięg emiterów [kafle w każdą stronę]
const SCAN_S := 0.2
const MAX_DROPS := 8                                      ## najwięcej pętli kropel naraz (pula AudioStreamPlayer2D)
const MAX_EAVES := 2
const FALLOFF_TILES := 4.0                                ## energia kolumny 1 / (1 + (d / FALLOFF)²)
const PAN_SCREEN := 0.45                                  ## skrajna kolumna zasięgu = 45% szerokości kadru od środka (panorama)
const INDOOR_DROPS := 0.25                                ## emitery na zewnątrz słyszane spod dachu (ok. −12 dB)

## Wiatr: warstwy i ich dB przy pełnym udziale; siła wiatru znormalizowana do bazy burzy (`WIND_BASE.storm`).
const WIND_LAYERS := {"amb_wind_low": -17.0, "amb_wind_trees": -18.0, "amb_wind_whistle": -23.0}
const WIND_K := {"storm": 1.0, "rain": 0.8, "fog": 0.6}   ## udział wiatru w pogodzie (bez pogody i w pogodną noc wiatru tu nie ma)
const GUST := ["wind_gust", -13.0]                        ## podmuch z kierunku wiatru (obwiednia `WeatherClock.gust`)
const WINDOW := ["wind_window", -16.0]                    ## świst w oknie
const WINDOW_REACH := 420.0                               ## px: dalej okno nie gwiżdże
const WINDOW_BROKEN := 2.0                                ## stłuczona szyba: ×2 (+6 dB)

## Grzmot: trzask tylko blisko, toczenie bliższe (1–3) i dalekie (4–6).
const THUNDER_CRACK := ["thunder_crack", 3]
const THUNDER_ROLL_NEAR := 3
const THUNDER_ROLL_FAR := 3
const THUNDER_MID_KM := 4.0
const THUNDER_HZ := Vector2(16000.0, 700.0)               ## odcięcie filtra grzmotu: 0,4 km … 8 km
const THUNDER_INDOOR_DB := -5.0
const THUNDER_RATTLE := ["thunder_rattle", 2, -13.0]      ## drżenie szyb pod dachem przy bliskim i średnim grzmocie
const THUNDER_PAN := 0.4                                  ## azymut ±1 → ±40% szerokości kadru

const SILENT_DB := -60.0
const FADE_RATE := 3.0                                    ## 1/s: płynność zmian głośności pętli
const MOVE_RATE := 4.0                                    ## 1/s: płynność przesuwania emiterów

var _players := {}            ## klucz instancji → AudioStreamPlayer albo AudioStreamPlayer2D
var _want := {}               ## klucz instancji → {s: pętla, db, off: Vector2 (pozycyjna) albo null, pitch}
var _drops := {}              ## wynik przeglądu kolumn: "materiał|L/R" → [energia 0..1+, przesunięcie x w kolumnach]
var _eaves: Array = []        ## [przesunięcie x w kolumnach, przesunięcie y w kafelkach, energia]
var _roof := ["", 0]          ## materiał dachu nad słuchaczem, grubość [kafle] ("" — niebo)
var _scan_t := 0.0
var _col_cache := {}          ## kolumna → wynik `rain_top` (dla wersji siatki dźwięku)
var _col_ver := -1
var _full_side := 1.0         ## energia pełnej strony (wszystkie kolumny jednego materiału)
var _thunders: Array[AudioStreamPlayer2D] = []
var _last_thunder := {}       ## ostatni grzmot (testy): {dist, az, cls, keys, db, hz, caption}
var _ear := Vector2.ZERO

func _ready() -> void:
	_full_side = 0.5
	for d in range(1, SCAN_COLS + 1):
		_full_side += _w(float(d))

func _exit_tree() -> void:
	stop_all()

static func _w(d: float) -> float:
	return 1.0 / (1.0 + pow(d / FALLOFF_TILES, 2.0))

static func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 0.0001)) / log(10.0)

## Stan pogody z `weather_fx.gd` (co klatkę): id, on (dźwięk pogody włączony), k (narastanie 0..1), i (siła), wind, gust, wdir, sky (0..1),
## deep (podziemia 0..1), cave (wykop pod skałą 0..1), lp (lokalny gracz albo null), level.
func update(delta: float, st: Dictionary) -> void:
	_want.clear()
	var id := String(st.get("id", ""))
	var on := bool(st.get("on", false))
	var lvl: Node = st.get("level")
	var lp: Node2D = st.get("lp")
	_ear = Audio.listener_pos()
	var deep := float(st.get("deep", 0.0))
	Audio.set_weather_underground(maxf(deep, 0.6 * float(st.get("cave", 0.0))) if on else 0.0)
	Audio.weather_wind = float(st.get("wind", Audio.WIND_REF)) if on else Audio.WIND_REF
	Audio.weather_wdir = float(st.get("wdir", 1.0))
	if on and RAIN_DB.has(id):
		_scan_t -= delta
		if _scan_t <= 0.0 and lvl != null and lvl.has_method("rain_top"):
			_scan_t = SCAN_S
			_scan(lvl)
		_rain(id, st, lp)
	if on and WIND_K.has(id):
		_wind(id, st)
	_apply(delta)

## Pętle, które teraz powinny grać (testy): klucz instancji → {s, db, off}.
func state() -> Dictionary:
	return _want.duplicate(true)

func last_thunder() -> Dictionary:
	return _last_thunder.duplicate()

func stop_all() -> void:
	for key in _players.keys():
		var p: Node = _players[key]
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	_want.clear()
	for t in _thunders:
		if is_instance_valid(t):
			t.stop()

# ---------------------------------------------------------------- deszcz (W2)

## Przegląd kolumn wokół słuchacza: energia kropel per materiał i strona, okapy, dach nad głową.
func _scan(lvl: Node) -> void:
	var grid = lvl.get("sound_grid")
	var ver := int(grid.version) if grid != null else 0
	if ver != _col_ver:
		_col_cache.clear()
		_col_ver = ver
	var tile := float(lvl.TILE)
	var lc := int(floor(_ear.x / tile))
	var lr := int(floor((_ear.y - 1.0) / tile))
	var cols := {}
	for c in range(lc - SCAN_COLS - 3, lc + SCAN_COLS + 4):
		if not _col_cache.has(c):
			_col_cache[c] = lvl.rain_top(c)
		cols[c] = _col_cache[c]
	# korony nad lasem: grunt do dwóch kolumn od pnia też gra liśćmi
	var leafy := {}
	for c in cols:
		if String(cols[c][1]) == "leaves":
			for dc in range(-2, 3):
				leafy[c + dc] = true
	var own: Array = cols[lc]
	var roofed := int(own[0]) >= 0 and int(own[0]) < lr - 1          # nad słuchaczem jest bryła — deszcz bębni w dach
	_roof = [String(own[1]), lr - int(own[0])] if roofed else ["", 0]
	_drops.clear()
	for c in range(lc - SCAN_COLS, lc + SCAN_COLS + 1):
		var t: Array = cols[c]
		var row := int(t[0])
		if row < 0:
			continue
		if roofed and row < lr - 1:
			continue                                                    # ten dach słychać jako deszcz nad głową
		var mat := String(t[1])
		if mat == "dirt" and leafy.has(c):
			mat = "leaves"
		if not DROPS.has(mat):
			continue
		var dx := float(c - lc)
		var dy := float(row - lr)
		if absf(dy) > 24.0:
			continue
		var e := _w(sqrt(dx * dx + 0.36 * dy * dy))
		var sides := ["L", "R"] if c == lc else (["L"] if c < lc else ["R"])
		for sd in sides:
			var k := "%s|%s" % [mat, sd]
			var acc: Array = _drops.get(k, [0.0, 0.0])
			var we := e / float(sides.size())
			acc[0] = float(acc[0]) + we
			acc[1] = float(acc[1]) + we * dx
			_drops[k] = acc
	for k in _drops:
		var acc: Array = _drops[k]
		_drops[k] = [float(acc[0]) / _full_side, float(acc[1]) / maxf(float(acc[0]), 0.0001)]
	# okapy: sąsiednie kolumny, z których jedna ma dach z powietrzem pod spodem co najmniej 3 kafle wyżej niż grunt drugiej
	_eaves.clear()
	for c in range(lc - SCAN_COLS, lc + SCAN_COLS):
		var a: Array = cols[c]
		var b: Array = cols[c + 1]
		if int(a[0]) < 0 or int(b[0]) < 0:
			continue
		var hi: Array = a if int(a[0]) < int(b[0]) else b
		var lo: Array = b if hi == a else a
		if int(lo[0]) - int(hi[0]) < 3 or not bool(hi[2]):
			continue
		var x := float(c - lc) + 0.5
		var y := float(int(lo[0]) - lr)
		if absf(y) > 16.0:
			continue
		_eaves.append([x, y, _w(sqrt(x * x + 0.36 * y * y))])
	_eaves.sort_custom(func(p: Array, q: Array) -> bool: return float(p[2]) > float(q[2]))
	if _eaves.size() > MAX_EAVES:
		_eaves.resize(MAX_EAVES)

func _rain(id: String, st: Dictionary, lp: Node2D) -> void:
	var k := float(st.get("k", 0.0))
	var i := float(st.get("i", 0.0))
	var sky := float(st.get("sky", 1.0))
	var deep := float(st.get("deep", 0.0))
	var force := 0.25 + 0.75 * i                                         # ulewa pełną głośnością, przejaśnienie ok. −10 dB
	# tło: równa moc przenikania trzech warstw wg siły
	var x := clampf((i - 0.3) / 0.7, 0.0, 1.0)
	var ws: Array[float] = []
	var tot := 0.0
	for c in BED_AT:
		var w := maxf(0.0, 1.0 - absf(x - float(c)) / 0.5)
		ws.append(w)
		tot += w
	var bed_k := k * (0.35 + 0.65 * i) * lerpf(0.3, 1.0, sky) * lerpf(1.0, 0.5, deep)
	for j in BEDS.size():
		if ws[j] > 0.0:
			_add(BEDS[j], BEDS[j], float(RAIN_DB[id]) + _db(bed_k * sqrt(ws[j] / tot)))
	# emitery kropel (bez podziemi)
	var vw := get_viewport().get_visible_rect().size.x if get_viewport() != null else 1280.0
	var cand: Array = []
	for key in _drops:
		cand.append([key, _drops[key]])
	cand.sort_custom(func(p: Array, q: Array) -> bool: return float(p[1][0]) > float(q[1][0]))
	var indoor := lerpf(INDOOR_DROPS, 1.0, sky)
	for n in mini(cand.size(), MAX_DROPS):
		var key := String(cand[n][0])
		var e := float(cand[n][1][0])
		var mat := key.get_slice("|", 0)
		var d: Array = DROPS[mat]
		var off := Vector2(clampf(float(cand[n][1][1]) / float(SCAN_COLS), -1.0, 1.0) * vw * PAN_SCREEN, 0.0)
		_add("drop|" + key, String(d[0]), float(d[1]) + float(RAIN_DROPS_DB[id]) + _db(k * force * e * indoor * (1.0 - deep)), off)
	# okapy
	for n in _eaves.size():
		var ev: Array = _eaves[n]
		var off := Vector2(clampf(float(ev[0]) / float(SCAN_COLS), -1.0, 1.0) * vw * PAN_SCREEN, 0.0)
		_add("eave|%d" % n, String(EAVE[0]), float(EAVE[1]) + _db(k * force * float(ev[2]) * lerpf(0.5, 1.0, sky) * (1.0 - deep)), off)
	# deszcz na dachu nad głową
	var roof_mat := String(_roof[0])
	if roof_mat != "" and ROOFS.has(roof_mat):
		var r: Array = ROOFS[roof_mat]
		var thick := 1.0 if int(_roof[1]) <= 4 else 0.35                   # gruby strop (piętro, skała) tłumi bębnienie
		_add("roof", String(r[0]), float(r[1]) + _db(k * force * (1.0 - sky) * thick * (1.0 - deep)))
	# krople na kapturze i masce: tylko lokalny gracz pod niebem
	if lp != null and sky > 0.05:
		_add("mask", String(MASK[0]), float(MASK[1]) + _db(k * force * sky))

# ---------------------------------------------------------------- wiatr (W3)

## Siła wiatru znormalizowana do bazy burzy (ok. 0,7–1,7 w burzy, 0,3–0,7 w deszczu, < 0,1 we mgle).
static func wind_norm(wind: float) -> float:
	return wind / float(WeatherClock.WIND_BASE["storm"])

## Udział warstw wiatru [niski, korony, świst] przy znormalizowanej sile `s` (amplituda liniowa).
static func wind_mix(s: float) -> Array:
	return [clampf(s / 0.6, 0.0, 1.3), 1.2 * smoothstep(0.2, 0.8, s), smoothstep(0.7, 1.5, s)]

func _wind(id: String, st: Dictionary) -> void:
	var k := float(st.get("k", 0.0)) * float(WIND_K[id])
	var s := wind_norm(float(st.get("wind", 0.5)))
	var g := float(st.get("gust", 0.0))
	var sky := float(st.get("sky", 1.0))
	var mix := wind_mix(s)
	var indoor := [lerpf(0.6, 1.0, sky), lerpf(0.3, 1.0, sky), lerpf(0.8, 1.0, sky)]
	var j := 0
	for key in WIND_LAYERS:
		_add(key, key, float(WIND_LAYERS[key]) + _db(k * float(mix[j]) * float(indoor[j])))
		j += 1
	var vw := get_viewport().get_visible_rect().size.x if get_viewport() != null else 1280.0
	if g > 0.01:
		var wdir := float(st.get("wdir", 1.0))
		_add("gust", String(GUST[0]), float(GUST[1]) + _db(k * g * (0.5 + 0.5 * minf(s, 1.5)) * lerpf(0.5, 1.0, sky)),
			Vector2(wdir * vw * 0.4, 0.0), 0.92 + 0.12 * g)
	# świst w najbliższym oknie
	var best: Node2D = null
	var bd := WINDOW_REACH
	for w in get_tree().get_nodes_in_group("windows"):
		var wn := w as Node2D
		if wn == null:
			continue
		var d := wn.global_position.distance_to(_ear)
		if d < bd:
			bd = d
			best = wn
	if best != null and s > 0.12:
		var amp := clampf(s * (1.0 + 0.6 * g), 0.0, 2.0) * (WINDOW_BROKEN if not bool(best.get("intact")) else 1.0)
		var off := Vector2(clampf(best.global_position.x - _ear.x, -vw * PAN_SCREEN, vw * PAN_SCREEN), 0.0)
		_add("window", String(WINDOW[0]), float(WINDOW[1]) + _db(k * amp * _w(bd / 40.0)), off)

# ---------------------------------------------------------------- grzmot (W4)

## Grzmot błyskawicy `b` ({t, dist [km], az −1..1, k, i}) — woła `weather_fx.gd` po opóźnieniu z odległości. `sky` 0..1 (pod dachem: ciszej,
## ciemniej i drżenie szyb). Warianty z ziarna błyskawicy (u wszystkich graczy te same).
func thunder(b: Dictionary, sky: float, seed_base: int) -> void:
	var dist := float(b.get("dist", 3.0))
	var az := clampf(float(b.get("az", 0.0)), -1.0, 1.0)
	var r := RandomNumberGenerator.new()
	r.seed = seed_base * 31 + int(b.get("i", 0))
	var far := clampf((dist - WeatherClock.BOLT_DIST.x) / (WeatherClock.BOLT_DIST.y - WeatherClock.BOLT_DIST.x), 0.0, 1.0)
	var near := dist < WeatherClock.NEAR_KM
	var cls := "near" if near else ("mid" if dist < THUNDER_MID_KM else "far")
	var roll := (1 + r.randi() % THUNDER_ROLL_NEAR) if cls != "far" else (THUNDER_ROLL_NEAR + 1 + r.randi() % THUNDER_ROLL_FAR)
	var indoor := 1.0 - clampf(sky, 0.0, 1.0)
	var hz := THUNDER_HZ.x * pow(THUNDER_HZ.y / THUNDER_HZ.x, pow(far, 0.7)) * lerpf(1.0, 0.35, indoor)
	Audio.set_thunder_cutoff(hz)
	var vol := (0.0 if near else -3.0) - 11.0 * far + THUNDER_INDOOR_DB * indoor
	var pitch := r.randf_range(0.95, 1.04) * (0.94 if cls == "far" else 1.0)
	var vw := get_viewport().get_visible_rect().size.x if get_viewport() != null else 1280.0
	var off := Vector2(az * vw * THUNDER_PAN, 0.0)
	var keys: Array = ["thunder_roll_%d" % roll]
	_thunder_play(keys[0], vol, pitch, off)
	if near:
		var crack := "%s_%d" % [THUNDER_CRACK[0], 1 + r.randi() % int(THUNDER_CRACK[1])]
		keys.append(crack)
		_thunder_play(crack, vol + 1.0 - 4.0 * indoor, r.randf_range(0.97, 1.03), off)
	if indoor > 0.5 and dist < THUNDER_MID_KM:
		var rattle := "%s_%d" % [THUNDER_RATTLE[0], 1 + r.randi() % int(THUNDER_RATTLE[1])]
		keys.append(rattle)
		_thunder_play(rattle, float(THUNDER_RATTLE[2]) + (3.0 if near else 0.0), r.randf_range(0.95, 1.05), Vector2.ZERO)
	var cap := "[Thunder — close]" if near else ("[Thunder]" if cls == "mid" else "[Distant thunder]")
	_last_thunder = {"dist": dist, "az": az, "cls": cls, "keys": keys, "db": vol, "hz": hz, "caption": cap}
	Audio.caption.emit(cap, _ear + Vector2(az * 300.0, 0.0), 2 if near else 1)

func _thunder_play(key: String, vol: float, pitch: float, off: Vector2) -> void:
	var s := Audio.stream(key)
	if s == null:
		return
	var p: AudioStreamPlayer2D = null
	for t in _thunders:
		if not t.playing:
			p = t
			break
	if p == null:
		if _thunders.size() < 5:
			p = _new_2d()
			_thunders.append(p)
		else:
			p = _thunders[0]                                            # najstarszy (dalekie toczenie) ustępuje nowemu
			_thunders.remove_at(0)
			_thunders.append(p)
	p.stream = s
	p.bus = Audio.BUS_THUNDER
	p.volume_db = vol
	p.pitch_scale = pitch
	p.panning_strength = 0.0 if Settings.mono_audio else 1.0
	p.global_position = _ear + off
	p.play()

# ---------------------------------------------------------------- odtwarzacze

func _add(inst: String, key: String, db: float, off = null, pitch := 1.0) -> void:
	if db <= SILENT_DB:
		return
	_want[inst] = {"s": key, "db": db, "off": off, "pitch": pitch}

func _new_2d() -> AudioStreamPlayer2D:
	var q := AudioStreamPlayer2D.new()
	q.attenuation = 0.0                                                 # głośność liczy ten skrypt (energia kolumn, odległość)
	q.max_distance = 100000.0
	q.bus = Audio.BUS_WEATHER
	add_child(q)
	return q

## Pętle z `_want` grają z płynną głośnością i położeniem; reszta wygasa i znika.
func _apply(delta: float) -> void:
	var fk := 1.0 - exp(-delta * FADE_RATE)
	var mk := 1.0 - exp(-delta * MOVE_RATE)
	for inst in _want:
		var w: Dictionary = _want[inst]
		var p: Node = _players.get(inst)
		if p != null and (not is_instance_valid(p) or String(p.get_meta("key", "")) != String(w["s"])):
			if is_instance_valid(p):
				p.queue_free()
			_players.erase(inst)
			p = null
		if p == null:
			var s := Audio.stream(String(w["s"]))
			if s == null:
				continue
			if w["off"] == null:
				var a := AudioStreamPlayer.new()
				a.bus = Audio.BUS_WEATHER
				add_child(a)
				p = a
			else:
				p = _new_2d()
				(p as AudioStreamPlayer2D).global_position = _ear + (w["off"] as Vector2)
			p.set_meta("key", String(w["s"]))
			p.set_meta("amp", 0.0)
			p.set("stream", s)
			p.set("volume_db", -80.0)
			p.call("play", randf() * maxf(s.get_length() - 0.1, 0.0))   # instancje tej samej pętli nie grają w fazie
			_players[inst] = p
	for inst in _players.keys():
		var p: Node = _players[inst]
		if not is_instance_valid(p):
			_players.erase(inst)
			continue
		var w: Dictionary = _want.get(inst, {})
		var target := db_to_linear(float(w["db"])) if not w.is_empty() else 0.0
		var amp := lerpf(float(p.get_meta("amp", 0.0)), target, fk)
		if w.is_empty() and amp < 0.0012:
			p.queue_free()
			_players.erase(inst)
			continue
		p.set_meta("amp", amp)
		p.set("volume_db", linear_to_db(maxf(amp, 0.00001)))
		if not w.is_empty():
			p.set("pitch_scale", float(w["pitch"]))
		if p is AudioStreamPlayer2D:
			var q := p as AudioStreamPlayer2D
			q.panning_strength = 0.0 if Settings.mono_audio else 1.0
			if not w.is_empty() and w["off"] != null:
				var cur: Vector2 = q.get_meta("off", w["off"])
				cur = cur.lerp(w["off"] as Vector2, mk)
				q.set_meta("off", cur)
			q.global_position = _ear + (q.get_meta("off", Vector2.ZERO) as Vector2)
