extends "res://scripts/enemy_behavior.gd"
## Mimik (GDD §7.1): udaje kolegę z drużyny (zamaskowany stoi jak żywy, z etykietą jak u gracza, bez serduszek). Woła o pomoc głosem gracza, gdy ktoś jest
## w zasięgu słuchu, ale jeszcze nie przy nim — wabi do zasadzki. Kto podejdzie, poświeci albo strzeli, ten go demaskuje (`wake`): krzyk, fala i chwila na przemianę.

var lure_t := 4.0            ## odstęp między fałszywymi wołaniami

func reset() -> void:
	lure_t = 4.0

## Demaskacja: krzyk, fala i chwila na zmianę postaci (zapowiedź), potem normalny pościg.
func on_wake() -> void:
	NoiseMgr.add_noise(6.0, e.global_position)
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()
	e._windup = 0.35
	e._windup_duration = e._windup
	e.winding = true

func scream_pitch() -> float:
	return 0.85

## Zamaskowany stoi jak żywy kolega, nie „śpi"; nie przygasa i ma etykietę gracza.
func anim(a: String, _moving: bool) -> String:
	return "idle" if not e.active else a

func disguised() -> bool:
	return true

func disguise_label() -> String:
	if e.active:
		return ""
	# imię jak u gracza, ale bez plakietki życia (zdradza go) i z numerem, którego nie ma w drużynie
	return "P%d" % (2 + int(e.get_instance_id() % 3))

## Zamaskowany Mimik woła o pomoc głosem gracza (próbka bólu), gdy ktoś jest w zasięgu słuchu, ale jeszcze
## nie przy nim — wabi do zasadzki. Kto podejdzie, poświeci albo strzeli, ten go demaskuje (e.wake()).
func tick_asleep(delta: float) -> void:
	lure_t -= delta
	if lure_t > 0.0:
		return
	var p = e._nearest_player()
	var d: float = p.global_position.distance_to(e.global_position) if p != null else INF
	if d < 340.0 and d > 70.0:
		lure_t = randf_range(6.0, 10.0)
		if NoiseMgr.has_network():
			e._mimic_call.rpc()
		else:
			e._mimic_call()
	else:
		lure_t = 1.0
