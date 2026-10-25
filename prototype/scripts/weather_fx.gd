extends CanvasLayer
## Stan efektów pogody (weather.gd, GDD §10.3 „Radiostacja") i jej dźwięk. Obraz (deszcz, mgła, niebo, księżyc, błysk) składa widok 3D
## z tego stanu (view3d.gd: `_sync_weather` czyta `_id`, `_k`, `_sky` i `_flash`) — sam węzeł nic nie rysuje.
##
## Czysta kosmetyka, lokalna: nic tu nie rozstrzyga gameplayu. Otwartość nieba nad lokalnym graczem (nad nim nie ma bryły aż do górnej
## krawędzi mapy) i podziemia sterują pętlami deszczu na zewnątrz / pod dachem i tłem miejsca. Burza ma błyskawice: harmonogram wynika z ziarna misji (`Weather.seed`, replikowane razem z pogodą) i zegara misji
## (`mission.elapsed`), więc u wszystkich graczy błyska mniej więcej w tej samej chwili bez żadnego RPC.
## Ustawienie Weather effects: FULL (pełny błysk) / REDUCED (miękka poświata zamiast błysku, mniej cząsteczek — domyślnie) / OFF.

const Weather := preload("res://scripts/weather.gd")

const FADE_IN := 0.25                       ## 1/s: ok. 4 s narastania po starcie misji
const FADE_OUT := 0.5
## Dźwięk (faza C): bazowa głośność pętli [dB] przy pełnej pogodzie. `rain` = deszcz pod otwartym niebem (amb_rain), `roof` = deszcz nad głową
## (amb_rain_roof, pod dachem), `wind` = wiatr (amb_wind). Efektywna głośność = baza + 20·log10(siła pogody × udział nieba).
const AUDIO := {
	"rain": {"rain": -12.0, "roof": -15.0, "wind": -99.0},
	"storm": {"rain": -8.0, "roof": -11.0, "wind": -15.0},
	"fog": {"rain": -99.0, "roof": -99.0, "wind": -24.0},
}
const UNDERGROUND_DB := -14.0               ## deszcz słychać w podziemiach jak przez grubą warstwę ziemi
const SILENT_DB := -55.0                    ## poniżej: pętla zatrzymana
## Tło wg miejsca (_beds): las na otwartej przestrzeni / pod dachem, powietrze budynku pod dachem, kapanie w podziemiach.
const BED_FOREST_OPEN_DB := -13.0
const BED_FOREST_ROOF_DB := -19.0
const BED_AIR_DB := -20.0
const BED_DRIPS_DB := -22.0

## Dev (--shotflash[=K]): stała siła błysku 0..1 zamiast harmonogramu (zrzuty i pomiary; 0 = bez błysków); −1 = harmonogram.
static var dev_flash := -1.0

var _thunder_done := {}                     ## indeksy błysków, których grzmot już zagrał (dla bieżącego ziarna)
var _thunder_seed := -1
var _loops_on := {}                         ## klucze pętli dźwięku uruchomionych przez pogodę
var _k := 0.0                               ## wygładzona siła pogody 0..1
var _sky := 0.0                             ## wygładzona „otwartość nieba" nad lokalnym graczem 0..1
var _deep := 0.0                            ## wygładzone „jestem w podziemiach" 0..1
var _beds_on := {}                          ## pętle tła wg miejsca, które teraz grają
var _id := ""                               ## pogoda, dla której ustawiono parametry cząsteczek
var _t := 0.0
var _flash_seed := -1
var _flashes: Array = []                    ## czasy błysków (s zegara misji) policzone z ziarna
var _level: Node
var _main: Node

func _ready() -> void:
	layer = 1

func _exit_tree() -> void:
	_stop_audio()

func _process(delta: float) -> void:
	_t += delta
	var mode: int = Settings.weather_fx_effective()
	var id := Weather.active_id() if mode != Settings.WEATHER_FX_OFF else ""
	_k = move_toward(_k, 1.0 if id != "" else 0.0, (FADE_IN if id != "" else FADE_OUT) * delta)
	if id != "":
		_use_weather(id, mode)
	var lp := _local_player()
	var open := 1.0 if (lp != null and _sky_open(lp)) else 0.0
	_sky = move_toward(_sky, open, 2.0 * delta)
	_deep = move_toward(_deep, 1.0 if (lp != null and _level != null and lp.global_position.y >= float(_level.underground_y)) else 0.0, 1.0 * delta)
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

## Siła błysku 0..1 w tej chwili. FULL: ostry dwuimpulsowy błysk; REDUCED: miękka poświata (wolne narastanie, 40% amplitudy); dev_flash: stały.
func _flash(mode: int) -> float:
	if dev_flash >= 0.0:
		return dev_flash
	if mode == Settings.WEATHER_FX_OFF:
		return 0.0
	_main = _main if is_instance_valid(_main) else get_tree().current_scene
	var m = _main.get("mission") if _main != null else null
	if m == null:
		return 0.0
	var now := float(m.elapsed)
	_refresh_flashes(now)
	var best := 0.0
	for t0 in _flashes:
		var dt := now - float(t0)
		if dt < -0.5 or dt > 2.0:
			continue
		if mode == Settings.WEATHER_FX_REDUCED:
			var rise := clampf((dt + 0.5) / 0.5, 0.0, 1.0)             # 0,5 s narastania, potem ok. 1,2 s opadania
			var fall := clampf(1.0 - maxf(dt, 0.0) / 1.2, 0.0, 1.0)
			best = maxf(best, 0.4 * rise * fall)
		else:
			var a := 0.0 if dt < 0.0 else (1.0 if dt < 0.07 else exp(-(dt - 0.07) * 14.0))        # pierwszy impuls: błysk i szybki zanik
			var b := 0.0 if dt < 0.22 else (0.8 if dt < 0.3 else exp(-(dt - 0.3) * 6.0) * 0.8)    # drugi, słabszy impuls po krótkiej przerwie
			best = maxf(best, maxf(a, b))
	return best

## Harmonogram z ziarna: odstępy 9–24 s, liczony z zapasem 90 s do przodu od zegara misji.
func _refresh_flashes(now: float) -> void:
	if _flash_seed != Weather.seed or _flashes.is_empty() or float(_flashes[_flashes.size() - 1]) < now + 30.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = Weather.seed
		_flash_seed = Weather.seed
		_flashes.clear()
		var t := rng.randf_range(4.0, 12.0)
		while t < now + 90.0:
			_flashes.append(t)
			t += rng.randf_range(9.0, 24.0)

# ---------------------------------------------------------------- dźwięk (faza C)

## Pętle deszczu (na zewnątrz / pod dachem) i wiatru wg pogody i otwartości nieba nad lokalnym graczem; grzmot burzy z harmonogramu błyskawic.
func _audio(mode: int, lp: Node2D) -> void:
	var cfg: Dictionary = AUDIO.get(_id, {})
	var on := mode != Settings.WEATHER_FX_OFF and not cfg.is_empty() and _k > 0.02
	var under := lp != null and _level != null and lp.global_position.y >= float(_level.underground_y)
	var targets := {}
	if on:
		var k := _k
		targets["amb_rain"] = float(cfg["rain"]) + _db(k * _sky)
		targets["amb_rain_roof"] = float(cfg["roof"]) + _db(k * (1.0 - _sky)) + (UNDERGROUND_DB if under else 0.0)
		targets["amb_wind"] = float(cfg["wind"]) + _db(k)
	for key in ["amb_rain", "amb_rain_roof", "amb_wind"]:
		var v: float = targets.get(key, -99.0)
		if v > SILENT_DB:
			Audio.start_loop(key, Audio.BUS_AMB, v)                 # istniejąca pętla tylko zmienia głośność
			_loops_on[key] = true
		elif _loops_on.has(key):
			Audio.stop_loop(key)
			_loops_on.erase(key)
	if on and _id == "storm":
		_thunder()

## Tło wg miejsca (niezależnie od pogody): pod dachem słychać „powietrze" budynku (amb_air), w podziemiach kapanie
## (amb_drips), a las z powierzchni cichnie pod dachem. Działa tylko, gdy gra tło misji (pętla amb_forest z main.gd).
func _beds() -> void:
	var on := Audio.loop_playing("amb_forest")
	if on:
		Audio.set_loop_volume("amb_forest", lerpf(BED_FOREST_ROOF_DB, BED_FOREST_OPEN_DB, _sky))
	var targets := {
		"amb_air": BED_AIR_DB + _db(1.0 - _sky) if on else -99.0,
		"amb_drips": BED_DRIPS_DB + _db(_deep) if on else -99.0,
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
	for key in _loops_on.keys():
		Audio.stop_loop(key)
	_loops_on.clear()
	for key in _beds_on.keys():
		Audio.stop_loop(key)
	_beds_on.clear()

## Grzmot po każdym błysku: opóźnienie 0,5–4 s z ziarna (tak samo u wszystkich graczy); im dłuższe, tym dalszy i cichszy grzmot (3 warianty: blisko → daleko).
func _thunder() -> void:
	_main = _main if is_instance_valid(_main) else get_tree().current_scene
	var m = _main.get("mission") if _main != null else null
	if m == null:
		return
	if _thunder_seed != Weather.seed:
		_thunder_seed = Weather.seed
		_thunder_done.clear()
	var now := float(m.elapsed)
	_refresh_flashes(now)
	for i in _flashes.size():
		if _thunder_done.has(i):
			continue
		var r := RandomNumberGenerator.new()
		r.seed = Weather.seed * 31 + i
		var delay := r.randf_range(0.5, 4.0)
		var due := float(_flashes[i]) + delay
		if now < due:
			break
		_thunder_done[i] = true
		if now - due > 1.0:
			continue                                                  # zaległy (np. dołączenie w trakcie misji) — nie odtwarzamy po fakcie
		var variant := 1 if delay < 1.4 else (2 if delay < 2.6 else 3)
		Audio.play("thunder_%d" % variant, Audio.BUS_AMB, -3.0 - 2.2 * delay, r.randf_range(0.93, 1.07))

