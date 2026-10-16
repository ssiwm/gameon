extends Node2D
## Głaz Wołka (ENEMY_PLAN.md F3.9): pocisk po łuku, który Wołek rzuca w gracza, gdy w pobliżu nie ma skrzyni. Lot deterministyczny z parametrów startu
## (jak kwas Pijawki i granat), więc nie jest synchronizowany; trafienie rozstrzyga serwer: 0,5 HP przez `Player.deliver_chip` (dwa głazy = jedno serce).
## Znika przy ścianie, po trafieniu albo po LIFE s. Grupa „boulders" — widok 3D rysuje obracający się kamień (`view3d.gd: _sync_boulders`).

const Vfx := preload("res://scripts/vfx.gd")

const GRAVITY := 980.0           ## jak ciała fizyczne — łuk rzutu liczy `enemy.gd: _throw_boulder` z tą samą grawitacją co rzut skrzynią
const HIT_R := 8.0
const LIFE := 2.5

var vel := Vector2.ZERO
var damage := 0.5
var _t := 0.0

func _ready() -> void:
	add_to_group("boulders")
	z_index = 3

func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFE:
		queue_free()
		return
	vel.y += GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	var hit := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))
	if not hit.is_empty():
		global_position = hit["position"]
		_crash()
		return
	global_position = to
	if NoiseMgr.is_server():
		for p in get_tree().get_nodes_in_group("players"):
			if p.dead or p.is_queued_for_deletion():
				continue
			if p.hurt_point(global_position).distance_to(global_position) <= HIT_R:
				p.deliver_chip(damage, global_position, "boulder")
				_crash()
				return

## Uderzenie: pył i stuk (każdy peer liczy lot sam, więc i efekt).
func _crash() -> void:
	Vfx.burst(get_parent(), global_position, Color(0.55, 0.5, 0.45), 8, 20.0, 70.0, Vector2.UP, 80.0, 400.0, 0.45, Vector2(1.5, 2.5), true)
	Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, -5.0, 0.7)
	queue_free()
