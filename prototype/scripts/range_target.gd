extends StaticBody2D
## Stalowa tarcza strzelnicy w kryjówce (GUNSMITH_PLAN.md §7.5, od 1.7.334): okrągła blacha na słupku (popper) — trafiona przewraca się
## z dźwięcznym „dzwonkiem”, wstaje na komendę przebiegu (range_course.gd). Trafienie rozstrzyga serwer (Combat.apply → take_hit), stan
## (leży / stoi) idzie do wszystkich RPC. Bryłę i animację przewracania buduje view3d.gd (grupa „range_targets”).
## Blacha zatrzymuje każdą kulę (pen_cost) i nie daje wprawy ani zabójstw — Combat.report liczy tylko żywe cele (FLESH / ARMOR).

const Combat := preload("res://scripts/combat.gd")

const LAYER := 32                     ## warstwa celów (jak skrzynie i beczki) — pociski ją widzą (Combat.LAYER_TARGET)
const PLATE_R := 4.0                  ## px — promień blachy (ok. 33 cm)

signal knocked(index: int)

var index := 0                        ## numer tarczy w przebiegu (range_course.gd)
var height := 12.0                    ## px — wysokość środka blachy nad podłogą
var down := false
var fall := 0.0                       ## 0 stoi … 1 leży (kosmetyka view3d, każdy peer liczy sam)

var _shape: CollisionShape2D

func _ready() -> void:
	add_to_group("enemies")               # pociski traktują ją jak cel (projectile.gd), nie jak ścianę
	add_to_group("range_targets")
	collision_layer = LAYER
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = PLATE_R
	_shape.shape = c
	_shape.position = Vector2(0.0, -height)
	add_child(_shape)

func _process(delta: float) -> void:
	fall = move_toward(fall, 1.0 if down else 0.0, delta * (6.0 if down else 2.5))

## Stalowa blacha zatrzymuje każdą kulę (projectile.gd: pen_cost).
func pen_cost() -> float:
	return 99.0

func body_center() -> Vector2:
	return global_position + Vector2(0.0, -height)

## Trafienie (serwer): leżąca tarcza nie przyjmuje kul (przelatują nad nią).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or down:
		return {}
	_set_down(true)
	if NoiseMgr.has_network():
		_state_rpc.rpc(true)
	knocked.emit(index)
	return {"hit": true, "dealt": 0.0, "killed": false, "mat": Arsenal.Mat.METAL}

## Serwer: tarcza wstaje (nowy przebieg).
func raise() -> void:
	if not NoiseMgr.is_server() or not down:
		return
	_set_down(false)
	if NoiseMgr.has_network():
		_state_rpc.rpc(false)

@rpc("authority", "call_remote", "reliable")
func _state_rpc(d: bool) -> void:
	_set_down(d)

func _set_down(d: bool) -> void:
	if d == down:
		return
	down = d
	_shape.set_deferred("disabled", d)
	var at := body_center()
	if d:
		Audio.play_variant_at("impact_hard", 3, at, Audio.BUS_WORLD, -4.0, 2.1, 0.06)      # stal: wysoki „dzwonek”
		Audio.play_variant_at("ricochet", 2, at, Audio.BUS_WORLD, -18.0, 1.4, 0.1)
	else:
		Audio.play_variant_at("impact_hard", 3, at, Audio.BUS_WORLD, -16.0, 0.8, 0.06)
