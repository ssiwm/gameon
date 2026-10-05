extends Node
## Game feel (GDD §23): screen shake i hitstop w jednym miejscu.
##
## Shake jest lokalny (każdy peer trzęsie własną kamerą). Hitstop spowalnia
## tylko lokalny czas na ~50 ms — wywołujemy go rzadko (zabójstwo, własne
## trafienie), bo przy 8 strzałach/s hitstop na każde trafienie zamroziłby grę.

const SHAKE_DECAY := 14.0
const KICK_DECAY := 22.0
const KICK_MAX := 8.0
const HITSTOP_SCALE := 0.06
const HITSTOP_COOLDOWN_MS := 250

var _amp := 0.0
var _kick := Vector2.ZERO        ## szarpnięcie kamery (kierunkowe, wygasa szybciej niż shake)
var _hitstop_until_ms := 0
var _hitstop_ready_at_ms := 0

## amount w pikselach (viewport 640x360, kamera zoom 1.6).
func shake(amount: float) -> void:
	_amp = maxf(_amp, amount)

## Kierunkowe szarpnięcie kamery (odrzut broni, wybuch): `v` w pikselach, kamera
## przesuwa się wzdłuż `v` i wraca sprężyście. Sumuje się z shake.
func kick(v: Vector2) -> void:
	_kick += v
	_kick = _kick.limit_length(KICK_MAX)

func shake_offset() -> Vector2:
	var rnd := Vector2.ZERO
	if _amp >= 0.05:
		rnd = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _amp
	return rnd + _kick

## Krótkie „zamrożenie\" przy ważnym zdarzeniu. Ignorowane, jeśli poprzedni
## hitstop był niedawno — gra ma być responsywna, nie szarpana.
##
## Na hoście z podłączonymi klientami hitstop jest wyłączony: Engine.time_scale
## spowalnia całą symulację serwera (stalker, wrogowie, pociski), więc każde
## zabójstwo przy hoście szarpałoby grę wszystkim klientom. Zostaje shake.
func hitstop(seconds: float) -> void:
	if NoiseMgr.has_network() and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now < _hitstop_ready_at_ms:
		return
	Engine.time_scale = HITSTOP_SCALE
	_hitstop_until_ms = now + int(seconds * 1000.0)
	_hitstop_ready_at_ms = _hitstop_until_ms + HITSTOP_COOLDOWN_MS

func _process(delta: float) -> void:
	# delta jest skalowane time_scale, więc wygaszamy shake czasem rzeczywistym
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_amp = move_toward(_amp, 0.0, SHAKE_DECAY * real_delta)
	_kick = _kick.move_toward(Vector2.ZERO, KICK_DECAY * real_delta * maxf(1.0, _kick.length() * 0.25))
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0
		_hitstop_until_ms = 0

func _exit_tree() -> void:
	Engine.time_scale = 1.0
