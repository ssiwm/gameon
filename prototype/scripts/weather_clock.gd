extends RefCounted
## Zegar pogody (WEATHER_PLAN.md W1): siła pogody w czasie, wiatr z podmuchami i błyskawice liczone wyłącznie z ziarna misji
## (`Weather.seed`, replikowane z pogodą) i zegara misji (`mission.elapsed`). Czyste funkcje bez stanu sieciowego — u każdego gracza
## i u dołączającego wychodzi to samo bez żadnego RPC. Czytają go `weather_fx.gd` (dźwięk, stan dla obrazu) i `view3d.gd` (obraz).
##
## Zegar zmienia tylko obraz i dźwięk: mnożniki rozgrywki (`weather.gd`) zostają stałe (decyzja D2 planu).
##
## - Siła `intensity(id, sd, t)` 0..1: fronty po 100–260 s na przemian mocniejsze i słabsze (narastanie, ulewa, przejaśnienie),
##   przejścia 25–45 s, drobne falowanie ±0,03.
## - Wiatr `wind(id, sd, t)`: siła bazowa pogody (dawne WIND_K widoku 3D) rośnie ok. 25 s PRZED wzrostem siły pogody (zapowiedź jak
##   w Rain World), do tego podmuchy `gust(id, sd, t)` 0..1 z własnego harmonogramu. Kierunek `direction(sd)` stały na misję.
## - Błyskawice `bolts_between(sd, t0, t1)` tylko w burzy: czas, odległość 0,4–8 km, azymut −1..1 (lewo..prawo), siła z odległości;
##   w ulewie częściej. Grzmot przychodzi po `thunder_delay(dist)` — odległość / prędkość dźwięku.

const LEVELS := {                       ## [słabszy front min, słabszy max, mocniejszy min, mocniejszy max]
	"clear": [0.45, 0.65, 0.8, 1.0],
	"rain": [0.35, 0.6, 0.78, 1.0],
	"storm": [0.6, 0.75, 0.88, 1.0],
	"fog": [0.5, 0.68, 0.82, 1.0],
}
const FRONT_S := Vector2(100.0, 260.0)  ## długość frontu [s]
const TRANS_S := Vector2(25.0, 45.0)    ## przejście między frontami [s]
const WIND_BASE := {"clear": 0.3, "rain": 0.85, "storm": 1.9, "fog": 0.12}      ## siła wiatru wg pogody (amplituda roślin, `Level3D.set_wind`)
const WIND_LEAD_S := 25.0               ## wiatr wyprzedza zmianę siły pogody
const GUST_GAP := {"clear": Vector2(14.0, 40.0), "rain": Vector2(8.0, 24.0), "storm": Vector2(4.0, 12.0), "fog": Vector2(30.0, 70.0)}
const GUST_AMP := {"clear": 0.35, "rain": 0.45, "storm": 0.6, "fog": 0.2}         ## o ile podmuch podnosi siłę wiatru (× baza)
const GUST_LEN := Vector2(2.0, 6.0)     ## długość podmuchu [s]
const BOLT_GAP := Vector2(9.0, 24.0)    ## odstęp błyskawic przy średniej sile burzy [s]
const BOLT_DIST := Vector2(0.4, 8.0)    ## odległość [km]
const NEAR_KM := 1.5                    ## bliżej: ostry błysk i trzask grzmotu
const SOUND_KMS := 0.343                ## prędkość dźwięku [km/s]
const THUNDER_MAX_S := 14.0             ## najdłuższe opóźnienie grzmotu (dalej by się zgubił w ulewie)
const AHEAD_S := 120.0                  ## harmonogramy generowane z takim zapasem

static var _cache := {}                 ## "rodzaj|ziarno|id" → harmonogram (Array), rozbudowywany leniwie od początku misji

## Siła pogody `id` w chwili `t` [s zegara misji], 0..1.
static func intensity(id: String, sd: int, t: float) -> float:
	if not LEVELS.has(id):
		return 0.0
	t = maxf(t, 0.0)
	var k: Array = _ensure(_fronts_key(id, sd), t + TRANS_S.y + 1.0, _gen_fronts.bind(id, sd))
	var i := _bisect(k, t)
	var a: Array = k[i]
	var v := float(a[1])
	if i + 1 < k.size():
		var b: Array = k[i + 1]
		var trn := float(b[2])
		var s := clampf((t - (float(b[0]) - trn)) / trn, 0.0, 1.0)
		v = lerpf(v, float(b[1]), s * s * (3.0 - 2.0 * s))
	var ph := float(posmod(sd, 1000)) * 0.37
	v += 0.03 * sin(t * 0.21 + ph) * sin(t * 0.077 + ph * 1.7)
	return clampf(v, 0.0, 1.0)

## Kierunek wiatru na misję: +1 — z prawej (krople lecą w lewo), −1 — z lewej.
static func direction(sd: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = sd * 13 + 5
	return 1.0 if r.randf() < 0.5 else -1.0

## Podmuch w chwili `t`, 0..1 (narastanie ok. 35% długości, potem wolniejsze opadanie).
static func gust(id: String, sd: int, t: float) -> float:
	if not GUST_GAP.has(id):
		return 0.0
	t = maxf(t, 0.0)
	var ev: Array = _ensure(_gusts_key(id, sd), t + GUST_LEN.y, _gen_gusts.bind(id, sd))
	var best := 0.0
	var i := _bisect(ev, t)
	for j in range(maxi(i - 2, 0), mini(i + 2, ev.size())):
		var e: Array = ev[j]
		var x := (t - float(e[0])) / float(e[1])
		if x <= 0.0 or x >= 1.0:
			continue
		var env := sin(x / 0.35 * PI * 0.5) if x < 0.35 else 0.5 + 0.5 * cos((x - 0.35) / 0.65 * PI)
		best = maxf(best, env * float(e[2]))
	return best

## Siła wiatru w chwili `t` (skala `WIND_BASE`): baza × zapowiedź siły pogody + podmuch.
static func wind(id: String, sd: int, t: float) -> float:
	var base := float(WIND_BASE.get(id, 0.5))
	var lead := intensity(id, sd, t + WIND_LEAD_S)
	return base * (0.7 + 0.45 * lead) * (1.0 + float(GUST_AMP.get(id, 0.3)) * gust(id, sd, t))

## Błyskawice (tylko burza) z czasem w [t0, t1): słowniki {t, dist [km], az −1..1, k 0..1, i (numer)}.
static func bolts_between(sd: int, t0: float, t1: float) -> Array:
	var out: Array = []
	var ev: Array = _ensure(_bolts_key(sd), t1, _gen_bolts.bind(sd))
	for j in range(_bisect(ev, t0), ev.size()):
		var b: Dictionary = ev[j]
		var tb := float(b["t"])
		if tb >= t1:
			break
		if tb >= t0:
			out.append(b)
	return out

## Opóźnienie grzmotu po błysku [s] z odległości [km].
static func thunder_delay(dist_km: float) -> float:
	return clampf(dist_km / SOUND_KMS, 0.4, THUNDER_MAX_S)

## Siła błysku 0..1 z odległości: blisko pełna, 8 km ok. 0,2.
static func bolt_strength(dist_km: float) -> float:
	return clampf(1.25 - dist_km / 5.5, 0.2, 1.0)

static func clear_cache() -> void:
	_cache.clear()

# ---------------------------------------------------------------- harmonogramy

static func _fronts_key(id: String, sd: int) -> String:
	return "f|%d|%s" % [sd, id]

static func _gusts_key(id: String, sd: int) -> String:
	return "g|%d|%s" % [sd, id]

static func _bolts_key(sd: int) -> String:
	return "b|%d" % sd

## Harmonogram pod kluczem rozbudowany co najmniej do `until` (+ zapas). `gen(list, until)` dopisuje kolejne zdarzenia
## deterministycznie (stan generatora siedzi w ostatnim elemencie i w ziarnie), więc kolejność zapytań nie zmienia wyniku.
static func _ensure(key: String, until: float, gen: Callable) -> Array:
	if _cache.size() > 64:
		_cache.clear()
	var st: Dictionary = _cache.get(key, {})
	if st.is_empty():
		st = {"list": [], "upto": -1.0, "rng": RandomNumberGenerator.new(), "init": false}
		_cache[key] = st
	if float(st["upto"]) < until:
		st["upto"] = gen.call(st, until + AHEAD_S)
	return st["list"]

## Fronty: [czas startu, poziom, długość przejścia do tego frontu].
static func _gen_fronts(st: Dictionary, until: float, id: String, sd: int) -> float:
	var r: RandomNumberGenerator = st["rng"]
	var l: Array = st["list"]
	var lv: Array = LEVELS[id]
	if not st["init"]:
		st["init"] = true
		r.seed = sd * 31 + 17 + id.hash()
		st["strong"] = r.randf() < 0.5
		l.append([0.0, r.randf_range(lerpf(float(lv[0]), float(lv[2]), 0.5), float(lv[2])), 0.0])     # start: umiarkowanie
		st["next"] = r.randf_range(FRONT_S.x * 0.6, FRONT_S.y * 0.6)
	while float(st["next"]) < until:
		var strong: bool = st["strong"]
		var v := r.randf_range(float(lv[2]), float(lv[3])) if strong else r.randf_range(float(lv[0]), float(lv[1]))
		l.append([float(st["next"]), v, r.randf_range(TRANS_S.x, TRANS_S.y)])
		st["strong"] = not strong
		st["next"] = float(st["next"]) + r.randf_range(FRONT_S.x, FRONT_S.y)
	return until                                                   # lista kompletna do `until` (następne zdarzenie dopiero dalej)

## Podmuchy: [czas startu, długość, siła].
static func _gen_gusts(st: Dictionary, until: float, id: String, sd: int) -> float:
	var r: RandomNumberGenerator = st["rng"]
	var l: Array = st["list"]
	var gap: Vector2 = GUST_GAP[id]
	if not st["init"]:
		st["init"] = true
		r.seed = sd * 7 + 1 + id.hash()
		st["next"] = r.randf_range(2.0, gap.x)
	while float(st["next"]) < until:
		var t := float(st["next"])
		var glen := r.randf_range(GUST_LEN.x, GUST_LEN.y)
		l.append([t, glen, r.randf_range(0.4, 1.0)])
		st["next"] = t + glen + r.randf_range(gap.x, gap.y)
	return until                                                   # lista kompletna do `until` (następne zdarzenie dopiero dalej)

## Błyskawice: w ulewie częściej (odstęp × 1,6 przy sile 0,6 … × 0,7 przy 1).
static func _gen_bolts(st: Dictionary, until: float, sd: int) -> float:
	var r: RandomNumberGenerator = st["rng"]
	var l: Array = st["list"]
	if not st["init"]:
		st["init"] = true
		r.seed = sd
		st["next"] = r.randf_range(4.0, 12.0)
	while float(st["next"]) < until:
		var t := float(st["next"])
		var d := r.randf_range(BOLT_DIST.x, BOLT_DIST.y)
		l.append({"t": t, "dist": d, "az": r.randf_range(-1.0, 1.0), "k": bolt_strength(d), "i": l.size()})
		var s := clampf((intensity("storm", sd, t) - 0.6) / 0.4, 0.0, 1.0)
		st["next"] = t + r.randf_range(BOLT_GAP.x, BOLT_GAP.y) * lerpf(1.6, 0.7, s)
	return until                                                   # lista kompletna do `until` (następne zdarzenie dopiero dalej)

## Indeks ostatniego elementu z czasem ≤ t (0, gdy wszystkie późniejsze). Element: Array (czas na [0]) albo słownik z "t".
static func _bisect(l: Array, t: float) -> int:
	var lo := 0
	var hi := l.size() - 1
	if hi < 0:
		return 0
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		var e = l[mid]
		var tm := float(e["t"]) if e is Dictionary else float(e[0])
		if tm <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo
