extends Node
## Game feel (GDD §23): screen shake i hitstop w jednym miejscu.
##
## Shake jest lokalny (każdy peer trzęsie własną kamerą). Hitstop spowalnia
## tylko lokalny czas na ~50 ms — wywołujemy go rzadko (zabójstwo, własne
## trafienie), bo przy 8 strzałach/s hitstop na każde trafienie zamroziłby grę.

const SHAKE_DECAY := 14.0
const HITSTOP_SCALE := 0.06
const HITSTOP_COOLDOWN_MS := 250

var _amp := 0.0
var _hitstop_until_ms := 0
var _hitstop_ready_at_ms := 0

## amount w pikselach (viewport 640x360, kamera zoom 1.6).
func shake(amount: float) -> void:
	_amp = maxf(_amp, amount)

func shake_offset() -> Vector2:
	if _amp < 0.05:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _amp

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
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0
		_hitstop_until_ms = 0

func _exit_tree() -> void:
	Engine.time_scale = 1.0
