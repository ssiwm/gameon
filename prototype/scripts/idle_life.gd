extends RefCounted
## Warstwa „żywe ciało” wroga w spoczynku (IDLE_PLAN.md, warstwa A, A1–A4): własny zegar oddechu, przenoszenie ciężaru i tiki
## z harmonogramu losowanego z ziarna egzemplarza. Sam widok — nic z tego nie wpływa na symulację ani nie idzie przez sieć.
## Ten sam `seed` daje ten sam przebieg (oddech i harmonogram), więc dwa okna widzą tego samego wroga podobnie, a różne ziarna
## rozjeżdżają fazy — grupa nie oddycha równo jak manekiny (P2).
##
## Użycie: `step(dt, asleep, calm)` co klatkę widoku; potem `breath()`, `breath_phase()`, `shift`, `tic`, `tic_k`, `tic_sign`, `tic_osc()`.
## Profil rodzaju (SPEC `idle` w enemy3d.gd): `breath` (okres oddechu, s), `tics` (nazwy z TICS), `rate` ([min, max] s między tikami u czuwającego).

const BREATH_SPREAD := 0.15          ## ± ułamek okresu oddechu między egzemplarzami
const SLEEP_BREATH := 1.25           ## śpiący oddycha wolniej
const SLEEP_TIC_RATE := 1.7          ## …i rzadziej się wierci
const INHALE := 0.4                  ## ułamek cyklu na wdech (krótszy niż wydech)
const SHIFT_HOLD := [4.0, 9.0]       ## s stania na jednej nodze (czuwający); śpiący ×1,4
const SHIFT_MOVE := 1.2              ## s przenoszenia ciężaru
const CALM_RATE := 4.0               ## 1/s: wygaszanie tików, gdy wróg przestaje być spokojny (reakcja „zauważył”, zapowiedź)
## Tik: [narastanie, przytrzymanie, opadanie] w sekundach. Kształt ruchu nakłada enemy3d.gd (`_idle_post`).
const TICS := {
	"jerk": [0.07, 0.05, 0.5],       ## szarpnięcie głowy (TLOU: tiki zarażonych)
	"shudder": [0.12, 0.45, 0.35],   ## dreszcz całego tułowia
	"twitch": [0.06, 0.0, 0.3],      ## drgnięcie dłoni
	"look": [0.55, 1.6, 0.7],        ## powolny obrót głowy i powrót
	"heave": [0.45, 0.25, 1.1],      ## głęboki, ciężki wdech (sapnięcie dużych)
	"nod": [0.9, 0.5, 0.25],         ## głowa opada (drzemka) i podrywa się
}
const DEFAULT := {"breath": 2.4, "tics": ["jerk"], "rate": [4.0, 10.0]}

var seed := 0
var t := 0.0                         ## zegar spoczynku egzemplarza (s)
var period := 2.4                    ## okres oddechu czuwającego (s), już z rozrzutem egzemplarza
var shift := 0.0                     ## −1..1: ciężar na lewej (−) / prawej (+) nodze
var tic := ""                        ## bieżący tik ("" = brak)
var tic_k := 0.0                     ## 0..1 obwiednia tiku × spokój
var tic_sign := 1.0                  ## kierunek tiku (głowa w lewo / prawo, w dół / w górę)
var calm := 1.0                      ## 0..1: wygładzony „spokój” (tiki tylko u spokojnego)

var _rng := RandomNumberGenerator.new()
var _tics: Array = []
var _rate: Array = []
var _bphase := 0.0                   ## faza oddechu 0..1
var _shift_from := 0.0
var _shift_to := 0.0
var _shift_t := 0.0                  ## s od początku bieżącego odcinka
var _shift_hold := 5.0
var _tic_t := 0.0                    ## s od początku tiku
var _tic_wait := 3.0                 ## s do następnego tiku
var _env := 0.0

func _init(seed_value: int, profile: Dictionary = {}) -> void:
	seed = seed_value
	_rng.seed = hash(seed_value) ^ 0x5eed1d1e
	var prof := DEFAULT.duplicate()
	prof.merge(profile, true)
	period = float(prof["breath"]) * _rng.randf_range(1.0 - BREATH_SPREAD, 1.0 + BREATH_SPREAD)
	_tics = Array(prof["tics"])
	_rate = Array(prof["rate"])
	_bphase = _rng.randf()
	t = _rng.randf_range(0.0, 10.0)
	_shift_to = _rng.randf_range(-1.0, 1.0)
	_shift_from = _shift_to
	shift = _shift_to
	_shift_hold = _rng.randf_range(SHIFT_HOLD[0], SHIFT_HOLD[1]) * _rng.randf()        # pierwszy odcinek ucięty — egzemplarze nie zmieniają nogi razem
	_tic_wait = _rng.randf_range(float(_rate[0]), float(_rate[1])) * _rng.randf_range(0.2, 1.0)

## Jeden krok zegara. `asleep`: wolniejszy oddech, rzadsze tiki i rzadsza zmiana nogi; `still`: wróg stoi spokojnie (bez zapowiedzi,
## reakcji „zauważył”, trafienia) — inaczej tiki gasną, a nowe się nie zaczynają.
func step(dt: float, asleep: bool, still := true) -> void:
	if dt <= 0.0:
		return
	t += dt
	_bphase = fposmod(_bphase + dt / (period * (SLEEP_BREATH if asleep else 1.0)), 1.0)
	calm = move_toward(calm, 1.0 if still else 0.0, dt * CALM_RATE)
	# ciężar: stoi na jednej nodze SHIFT_HOLD s, potem w SHIFT_MOVE s przenosi go na drugą
	_shift_t += dt
	var hold := _shift_hold * (1.4 if asleep else 1.0)
	if _shift_t >= hold + SHIFT_MOVE:
		_shift_t = 0.0
		_shift_from = _shift_to
		_shift_to = -signf(_shift_from if _shift_from != 0.0 else 1.0) * _rng.randf_range(0.55, 1.0)
		_shift_hold = _rng.randf_range(SHIFT_HOLD[0], SHIFT_HOLD[1])
	var m := smoothstep(hold, hold + SHIFT_MOVE, _shift_t) if _shift_t > hold else 0.0
	shift = lerpf(_shift_from, _shift_to, m)
	# tiki
	if tic != "":
		_tic_t += dt
		var env: Array = TICS[tic]
		var a := float(env[0])
		var h := float(env[1])
		var r := float(env[2])
		if _tic_t < a:
			_env = smoothstep(0.0, a, _tic_t)
		elif _tic_t < a + h:
			_env = 1.0
		elif _tic_t < a + h + r:
			_env = 1.0 - smoothstep(a + h, a + h + r, _tic_t)
		else:
			_env = 0.0
			tic = ""
	else:
		_tic_wait -= dt
		if _tic_wait <= 0.0:
			_tic_wait = _rng.randf_range(float(_rate[0]), float(_rate[1])) * (SLEEP_TIC_RATE if asleep else 1.0)
			if calm > 0.95 and not _tics.is_empty():
				tic = String(_tics[_rng.randi() % _tics.size()])
				tic_sign = -1.0 if _rng.randf() < 0.5 else 1.0
				_tic_t = 0.0
				_env = 0.0
	tic_k = _env * calm

## 0..1: wypełnienie płuc — wdech krótszy (INHALE cyklu), wydech dłuższy i miękki.
func breath() -> float:
	if _bphase < INHALE:
		return smoothstep(0.0, INHALE, _bphase)
	return 1.0 - smoothstep(INHALE, 1.0, _bphase)

## Faza cyklu oddechu w radianach (zastępuje wspólne `_t * TAU / 2.4` w pozach z kodu).
func breath_phase() -> float:
	return _bphase * TAU

## Drganie dreszczu (−1..1) w czasie tiku „shudder”.
func tic_osc() -> float:
	return sin(t * TAU * 17.0) * (0.6 + 0.4 * sin(t * TAU * 5.3))
