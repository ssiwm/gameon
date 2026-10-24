extends RefCounted
## Wspólny zegar akcji TPP i profile odrzutu w jednostkach fizycznych.
## Snapshot jest kosmetyką: nie uruchamia strzału ani trafienia.
const NONE := 0
const MELEE := 1
const RELOAD := 2
const TACTICAL := 0
const EMPTY := 1
const ROUND := 2
const CLEAR := 3

const RECOIL := {
	"m83": [0.025, 1.4, 0.16], "sokol6": [0.022, 1.2, 0.15],
	"p64": [0.035, 3.5, 0.20], "spread12": [0.040, 2.1, 0.23],
	"srut8": [0.045, 2.8, 0.25], "lr7": [0.004, 0.2, 0.12],
	"hkm9": [0.006, 0.3, 0.14], "gniew4": [0.045, 2.0, 0.28],
	"widmo1": [0.040, 1.8, 0.30], "ciegno6": [0.030, 1.6, 0.24],
}

var action := Vector4i.ZERO
var duration := 0.0
var elapsed := 0.0
var phase := -1.0
var started := false

## Faza rośnie mimo powtórzonych/opóźnionych snapshotów; nowy nabój ma osobny numer akcji.
func sample(descriptor: Vector4i, clock: Vector2, delta: float) -> void:
	started = false
	if descriptor.x < action.x:
		return
	if descriptor.x == action.x and action.y == NONE and descriptor.y != NONE:
		return # opóźniony pakiet nie wznawia zakończonej lub przerwanej akcji
	if descriptor.y == NONE or clock.x <= 0.0 or not clock.is_finite():
		action = descriptor
		phase = -1.0
		return
	if descriptor.x != action.x:
		action = descriptor
		duration = clock.x
		elapsed = clampf(clock.y, 0.0, duration)
		phase = elapsed / duration
		started = true
	else:
		duration = clock.x
		elapsed = minf(duration, maxf(elapsed + maxf(delta, 0.0), clock.y))
		phase = maxf(phase, clampf(elapsed / duration, 0.0, 1.0))

## Szybki impuls i krytycznie tłumiony powrót, niezależne od FPS. x = metry, y = radiany.
static func recoil_at(key: String, seconds: float, strength := 1.0) -> Vector2:
	if seconds < 0.0:
		return Vector2.ZERO
	var p: Array = RECOIL.get(key, [0.025, 1.2, 0.18])
	var t := maxf(seconds, 0.0)
	var attack := 1.0 - exp(-t / 0.006)
	var recovery := exp(-t * 6.0 / float(p[2])) * (1.0 + t * 6.0 / float(p[2]))
	return Vector2(float(p[0]), deg_to_rad(float(p[1]))) * attack * recovery * strength

static func fire_clip(key: String) -> String:
	return "combat_fire_pistol" if key == "p64" else ("combat_fire_heavy" if key in ["srut8", "spread12", "gniew4", "widmo1"] else "combat_fire_rifle")
