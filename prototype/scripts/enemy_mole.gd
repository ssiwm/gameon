extends "res://scripts/enemy_behavior.gd"
## Łupacz wychodzi z kieszeni przodem do chodnika. Ruch i kontakt rozstrzyga serwer.

const ENTRY_SECONDS := 2.0
const LENGTH_PX := 20.0
const ENTRY_TRAVEL := LENGTH_PX * 1.64 / 1.90346   ## przesunięcie kości Root względem długości modelu
const CONTACT := 19.0 / 24.0
const RECOVERY := 13.0 / 24.0

var entry_time := 0.0
var entry_face := 1.0
var entry_stamp := 0
var recovery_left := 0.0
var hurt: CollisionShape2D

func on_ready() -> void:
	hurt = e.get_meta("hurt_shape")

static func entry_travel(t: float) -> float:
	return ENTRY_TRAVEL * smoothstep(0.0, ENTRY_SECONDS, t)

func begin_entry(face: float, elapsed: float) -> void:
	entry_time = clampf(elapsed, 0.0, ENTRY_SECONDS)
	entry_face = signf(face)
	# W istniejącej migawce _sp = 0 oznacza chodnik, 1 + tik (60 Hz) oznacza wyjście.
	# Klient odzyskuje fazę z następnej migawki także po zagubieniu pakietu.
	entry_stamp = 1 + roundi(entry_time * 60.0)
	e._sp = entry_stamp
	e._facing = entry_face
	e._net_face = entry_face
	e._view_facing = entry_face

func reset() -> void:
	entry_time = 0.0
	entry_stamp = 0
	recovery_left = 0.0
	_fit_hurt(0.0, 0.0)

func tick_special(delta: float) -> bool:
	if e._sp <= 0:
		return false
	var before := entry_travel(entry_time)
	entry_time = minf(ENTRY_SECONDS, entry_time + delta)
	e._sp = 1 + roundi(entry_time * 60.0)
	e.velocity.x = entry_face * (entry_travel(entry_time) - before) / delta
	e._apply_gravity(delta)
	e._slide()
	if entry_time >= ENTRY_SECONDS:
		e._sp = 0
		e.velocity.x = 0.0
	e._send_state(delta)
	return true

func present(delta: float) -> void:
	if not e.is_multiplayer_authority():
		if e._sp > 0:
			var stamp: int = e._sp
			var seconds := (stamp - 1) / 60.0
			entry_time = seconds if stamp != entry_stamp else minf(entry_time + delta, minf(seconds + 0.05, ENTRY_SECONDS))
			entry_stamp = stamp
		recovery_left = maxf(0.0, recovery_left - delta)
		_fit_hurt(e._view_windup_remaining, e._view_windup_duration)

func view_extra(d: Dictionary) -> void:
	if e._sp > 0:
		d["burrow_time"] = entry_time
	if recovery_left > 0.0:
		d["swipe_recovery"] = recovery_left

func server_facing() -> bool:
	return true

func attack_action() -> String:
	return "swipe"

func after_attack() -> void:
	recovery_left = RECOVERY

func tick_prelude(delta: float) -> void:
	recovery_left = maxf(0.0, recovery_left - delta)
	_fit_hurt(e._windup, e._windup_duration)

## Podniesiony bark i głowa wystają nad korytarz. Zmienia się strefa pocisków,
## a niskie ciało poruszające się po wykopie zachowuje swoje wymiary.
func _fit_hurt(remaining: float, duration: float) -> void:
	var frame := 19.0 * (1.0 - remaining / duration) if remaining > 0.0 and duration > 0.0 else 0.0
	var rear := smoothstep(4.0, 12.0, frame) * (1.0 - smoothstep(14.0, 18.0, frame))
	var shape := hurt.shape as RectangleShape2D
	var height := 12.0 + roundf(7.0 * rear)
	if shape.size.y != height:
		shape.size.y = height
		hurt.position.y = -0.5 * height

func holds_still() -> bool:
	return recovery_left > 0.0
