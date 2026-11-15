extends CanvasLayer
## Stan efektów pogody (weather.gd, GDD §10.3 „Radiostacja") i jej dźwięk. Obraz (deszcz, mgła, niebo, księżyc, błysk) składa widok 3D
## z tego stanu (view3d.gd: `_sync_weather` czyta `_id`, `_k`, `_sky` i `_flash`) — sam węzeł nic nie rysuje.
##
## Czysta kosmetyka, lokalna: nic tu nie rozstrzyga gameplayu. Otwartość nieba nad lokalnym graczem (nad nim nie ma bryły aż do górnej
## krawędzi mapy) i podziemia sterują pętlami deszczu na zewnątrz / pod dachem i tłem miejsca. Burza ma błyskawice: harmonogram wynika z ziarna misji (`Weather.seed`, replikowane razem z pogodą) i zegara misji
## (`mission.elapsed`), więc u wszystkich graczy błyska mniej więcej w tej samej chwili bez żadnego RPC.
## Ustawienie Weather effects: FULL (pełny błysk) / REDUCED (miękka poświata zamiast błysku, mniej cząsteczek — domyślnie) / OFF.
## OFF (WEATHER_PLAN.md D3) wyłącza cząsteczki, błyski i dźwięk pogody, ale nie mgłę ani niebo: gracz z OFF widzi w co-op tyle co inni.
##
## Zegar pogody (WEATHER_PLAN.md W1, `weather_clock.gd`): siła `_i` zmienia się frontami, wiatr `_wind` z podmuchami `_gust` i kierunkiem
## `_wdir` (+1 z prawej), błyskawice mają odległość i kierunek (`_bolt`), a grzmot przychodzi po odległość / 343 m/s. Wszystko z ziarna.

const Weather := preload("res://scripts/weather.gd")
const WeatherClock := preload("res://scripts/weather_clock.gd")

const FADE_IN := 0.25                       ## 1/s: ok. 4 s narastania po starcie misji
const FADE_OUT := 0.5
## Dźwięk pogody (WEATHER_PLAN.md W2–W4): deszcz z warstw i emiterów na materiałach, wiatr z podmuchami, grzmot warstwowy z kierunkiem —
## składa go `weather_sound.gd` (dziecko tego węzła) z tego samego stanu co obraz. Pogody z dźwiękiem:
const SOUND_KINDS := ["rain", "storm", "fog"]
const WeatherSound := preload("res://scripts/weather_sound.gd")
const SILENT_DB := -55.0                    ## poniżej: pętla tła miejsca zatrzymana
## Tło wg miejsca (_beds): las na otwartej przestrzeni / pod dachem, powietrze budynku pod dachem, kapanie w podziemiach.
const BED_FOREST_OPEN_DB := -13.0
const BED_FOREST_ROOF_DB := -19.0
const BED_AIR_DB := -20.0
const BED_DRIPS_DB := -22.0
const BED_CAVE_DRIPS := 0.5                 ## kapanie w wykopie pod skałą: połowa amplitudy podziemi (−6 dB) — płytko, a krople ze stropu gra view3d.gd

## Dev (--shotflash[=K]): stała siła błysku 0..1 zamiast harmonogramu (zrzuty i pomiary; 0 = bez błysków); −1 = harmonogram.
static var dev_flash := -1.0
## Dev (--weathert=S): zegar pogody przesunięty o S s (zrzuty konkretnej chwili frontu, podmuchu, błyskawicy); −1 = zegar misji.
static var dev_t := -1.0

var _thunder_done := {}                     ## indeksy błysków, których grzmot już zagrał (dla bieżącego ziarna)
var _thunder_seed := -1
var _snd: Node                              ## weather_sound.gd: deszcz, wiatr, grzmot
var _k := 0.0                               ## wygładzone „pogoda trwa” 0..1 (narastanie po starcie misji)
var _i := 0.0                               ## siła pogody z zegara 0..1 (fronty: ulewa, przejaśnienie)
var _wind := 0.5                            ## siła wiatru (skala `WeatherClock.WIND_BASE`, z podmuchem); bez pogody 0,5
var _gust := 0.0                            ## podmuch 0..1
var _wdir := 1.0                            ## kierunek wiatru: +1 z prawej, −1 z lewej
var _bolt := {}                             ## ostatnia błyskawica (słownik z `WeatherClock.bolts_between`), pusty — brak
var _clock := 0.0                           ## chwila zegara pogody [s] w tej klatce
var _sky := 0.0                             ## wygładzona „otwartość nieba" nad lokalnym graczem 0..1
var _deep := 0.0                            ## wygładzone „jestem w podziemiach" 0..1
var _cave := 0.0                            ## wygładzone „jestem w wykopie pod skałą” 0..1 (strefa wydobycia, level.gd `dig_cover_at`)
var _beds_on := {}                          ## pętle tła wg miejsca, które teraz grają
var _id := ""                               ## pogoda, dla której ustawiono parametry cząsteczek
var _t := 0.0
var _level: Node
var _main: Node

func _ready() -> void:
	layer = 1
	_snd = WeatherSound.new()
	_snd.name = "WeatherSound"
	add_child(_snd)

func _exit_tree() -> void:
	_stop_audio()

func _process(delta: float) -> void:
	_t += delta
	var mode: int = Settings.weather_fx_effective()
	var id := Weather.active_id()                                       # także przy OFF: mgła i niebo zostają (D3), resztę tnie `mode`
	_k = move_toward(_k, 1.0 if id != "" else 0.0, (FADE_IN if id != "" else FADE_OUT) * delta)
	if id != "":
		_use_weather(id, mode)
	_clock = _now()
	var wid := id if id != "" else _id
	if wid != "":
		_i = WeatherClock.intensity(wid, Weather.seed, _clock)
		_gust = WeatherClock.gust(wid, Weather.seed, _clock)
		_wind = WeatherClock.wind(wid, Weather.seed, _clock)
		_wdir = WeatherClock.direction(Weather.seed)
	else:
		_i = 0.0
		_gust = 0.0
		_wind = 0.5
	var lp := _local_player()
	var open := 1.0 if (lp != null and _sky_open(lp)) else 0.0
	_sky = move_toward(_sky, open, 2.0 * delta)
	_deep = move_toward(_deep, 1.0 if (lp != null and _level != null and lp.global_position.y >= float(_level.underground_y)) else 0.0, 1.0 * delta)
	var cave := lp != null and _level != null and _level.has_method("dig_cover_at") and _level.dig_cover_at(lp.global_position) != null
	_cave = move_toward(_cave, 1.0 if cave else 0.0, 1.0 * delta)
	_audio(mode, lp)
	_beds()

## Zapamiętuje bieżącą pogodę (czyta ją widok 3D: deszcz, plusk, mgła i błysk są w scenie — view3d.gd: _sync_weather).
func _use_weather(id: String, _mode: int) -> void:
	_id = id

func _sky_open(p: Node2D) -> bool:
	_level = _level if is_instance_valid(_level) else get_tree().get_first_node_in_group("level")
	return _level != null and _level.sky_open_at(p.global_position)

func _local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.dead and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- błyskawice

## Chwila zegara pogody [s]: zegar misji (u klientów interpolowany między synchronizacjami) + przesunięcie dev `--weathert`.
func _now() -> float:
	_main = _main if is_instance_valid(_main) else get_tree().current_scene
	var m = _main.get("mission") if _main != null else null
	var now := float(m.elapsed) if m != null else _t
	return now + maxf(dev_t, 0.0)

## Siła błysku 0..1 w tej chwili, z odległości błyskawicy (`WeatherClock.bolt_strength`). FULL: bliska (< 2,5 km) ostry dwuimpulsowy
## błysk, daleka miękka poświata chmur; REDUCED: zawsze miękka poświata (wolne narastanie, 40% amplitudy); dev_flash: stały.
## Ustawia `_bolt` na błyskawicę, która właśnie świeci (kierunek i odległość czyta widok 3D).
func _flash(mode: int) -> float:
	if dev_flash >= 0.0:
		return dev_flash
	if mode == Settings.WEATHER_FX_OFF or _id != "storm":
		return 0.0
	var now := _clock
	var best := 0.0
	for b in WeatherClock.bolts_between(Weather.seed, now - 2.0, now + 0.5):
		var dt := now - float(b["t"])
		var bk := float(b["k"])
		var v := 0.0
		if mode == Settings.WEATHER_FX_REDUCED or float(b["dist"]) >= 2.5:
			var soft := 0.4 if mode == Settings.WEATHER_FX_REDUCED else 0.55
			var rise := clampf((dt + 0.5) / 0.5, 0.0, 1.0)             # 0,5 s narastania, potem ok. 1,2 s opadania
			var fall := clampf(1.0 - maxf(dt, 0.0) / 1.2, 0.0, 1.0)
			v = soft * bk * rise * fall
		else:
			var a := 0.0 if dt < 0.0 else (1.0 if dt < 0.07 else exp(-(dt - 0.07) * 14.0))        # pierwszy impuls: błysk i szybki zanik
			var c := 0.0 if dt < 0.22 else (0.8 if dt < 0.3 else exp(-(dt - 0.3) * 6.0) * 0.8)    # drugi, słabszy impuls po krótkiej przerwie
			v = bk * maxf(a, c)
		if v > best:
			best = v
			_bolt = b
	return best

# ---------------------------------------------------------------- dźwięk (faza C)

## Dźwięk pogody (W2–W4, `weather_sound.gd`) ze stanu tej klatki: siła, wiatr, podmuch, niebo i podziemia nad lokalnym graczem;
## grzmot burzy z harmonogramu błyskawic. Przy OFF (D3) i bez pogody — cisza.
func _audio(mode: int, lp: Node2D) -> void:
	var on := mode != Settings.WEATHER_FX_OFF and _id in SOUND_KINDS and _k > 0.02
	if _snd != null:
		_snd.update(get_process_delta_time(), {"id": _id, "on": on, "k": _k, "i": _i, "wind": _wind, "gust": _gust, "wdir": _wdir,
			"sky": _sky, "deep": _deep, "cave": _cave, "lp": lp, "level": _level})
	if on and _id == "storm":
		_thunder()

## Tło wg miejsca (niezależnie od pogody): pod dachem słychać „powietrze" budynku (amb_air), w podziemiach kapanie
## (amb_drips), a las z powierzchni cichnie pod dachem. W wykopie pod skałą (kopanie P2c) zamiast powietrza budynku ciche kapanie. Działa tylko, gdy gra tło misji (pętla amb_forest z main.gd).
func _beds() -> void:
	var on := Audio.loop_playing("amb_forest")
	if on:
		Audio.set_loop_volume("amb_forest", lerpf(BED_FOREST_ROOF_DB, BED_FOREST_OPEN_DB, _sky))
	var targets := {
		"amb_air": BED_AIR_DB + _db((1.0 - _sky) * (1.0 - _cave)) if on else -99.0,
		"amb_drips": BED_DRIPS_DB + _db(maxf(_deep, BED_CAVE_DRIPS * _cave)) if on else -99.0,
	}
	for key in targets:
		var v: float = targets[key]
		if v > SILENT_DB:
			Audio.start_loop(key, Audio.BUS_AMB, v)                 # istniejąca pętla tylko zmienia głośność
			_beds_on[key] = true
		elif _beds_on.has(key):
			Audio.stop_loop(key)
			_beds_on.erase(key)

static func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 0.001)) / log(10.0)

func _stop_audio() -> void:
	if _snd != null and is_instance_valid(_snd):
		_snd.stop_all()
	for key in _beds_on.keys():
		Audio.stop_loop(key)
	_beds_on.clear()

## Grzmot po każdym błysku: opóźnienie = odległość błyskawicy / prędkość dźwięku (`WeatherClock.thunder_delay`, tak samo u wszystkich
## graczy); brzmienie składa `weather_sound.gd` (trzask blisko, toczenie, filtr i panorama z odległości i azymutu, napis z kierunkiem).
## Woła go tylko `_audio` z włączonym dźwiękiem pogody (nie przy OFF).
func _thunder() -> void:
	if _thunder_seed != Weather.seed:
		_thunder_seed = Weather.seed
		_thunder_done.clear()
	var now := _clock
	for b in WeatherClock.bolts_between(Weather.seed, now - WeatherClock.THUNDER_MAX_S - 1.0, now + 0.01):
		var i := int(b["i"])
		if _thunder_done.has(i):
			continue
		var dist := float(b["dist"])
		var due := float(b["t"]) + WeatherClock.thunder_delay(dist)
		if now < due:
			continue
		_thunder_done[i] = true
		if now - due > 1.0:
			continue                                                  # zaległy (np. dołączenie w trakcie misji) — nie odtwarzamy po fakcie
		if _snd != null:
			_snd.thunder(b, _sky, Weather.seed)
