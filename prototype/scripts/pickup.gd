extends Node2D
## Apteczka (1.5): +1 HP. Wypada z Wołków (75%) i z Żyły (2 sztuki).
## Spawn, podniesienie i usunięcie idą przez level.gd (RPC ze stałą nazwą),
## więc istnieje identycznie na każdym peerze. Podniesienie rozstrzyga serwer.

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")

const HEAL := 1
const PICK_R := 12.0
const FALL_G := 700.0

var _vel := Vector2.ZERO
var _floor_y := 0.0
var _landed := false
var _t := 0.0
var _spr: Array = []

func _ready() -> void:
	add_to_group("pickups")
	z_index = 2
	if Sprites.has("objects"):
		_spr = Sprites.attach(self, "objects")
		Sprites.play(_spr, "medkit", false)
	# zielona poświata — apteczkę widać w ciemności, ale nie oświetla okolicy
	var glow := Lights.make_light(Lights.radial(), 1.6, Color(0.4, 1.0, 0.5), 0.6, false)
	glow.position = Vector2(0, -8)
	add_child(glow)
	_vel = Vector2(randf_range(-40.0, 40.0), -170.0)
	_floor_y = _find_floor(global_position)

func _find_floor(from: Vector2) -> float:
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), from + Vector2(0, 200), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else from.y

func _physics_process(delta: float) -> void:
	_t += delta
	if not _landed:
		# podskok i opad na podłogę (bez ciała fizycznego — to tylko znacznik)
		_vel.y += FALL_G * delta
		global_position += _vel * delta
		if _vel.y > 0.0 and global_position.y >= _floor_y:
			global_position.y = _floor_y
			_landed = true
	if not _spr.is_empty():
		var bob := 0.0 if not _landed else sin(_t * 3.0) * 1.5 - 1.5
		(_spr[0] as Node2D).position.y = bob
		if _spr[1] != null:
			(_spr[1] as Node2D).position.y = bob
			(_spr[1] as CanvasItem).modulate.a = 0.6 + 0.4 * sin(_t * 4.0)
	if _landed and NoiseMgr.is_server():
		_try_pickup()

## Serwer: pierwszy ranny w zasięgu. Bot nie zabiera apteczki, gdy obok jest
## ranny człowiek — ludzie mają pierwszeństwo.
func _try_pickup() -> void:
	var hurt_human_near := false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and p.hp < p.MAX_HP and p.global_position.distance_to(global_position) < 80.0:
			hurt_human_near = true
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.hp >= p.MAX_HP:
			continue
		if p.is_bot and hurt_human_near:
			continue
		if (p.global_position + Vector2(0, -8)).distance_to(global_position + Vector2(0, -6)) <= PICK_R + 6.0:
			p.deliver_heal(HEAL)
			get_tree().get_first_node_in_group("level").take_health(name)
			return
