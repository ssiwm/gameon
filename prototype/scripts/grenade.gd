extends Node2D
## Granat rzucany (lewy Alt): leci łukiem jak flara, odbija się od podłogi, po zapalniku wybucha. Lot jest deterministyczny
## (parametry startu), więc nie trzeba go synchronizować; wybuch rozstrzyga serwer (Combat.explode / pole ognia),
## efekt widzą wszyscy przez Arsenal/Vfx. Odłamkowy rani też drużynę (Combat.explode), fosforowy zostawia pole ognia.

const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Combat := preload("res://scripts/combat.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const GRAVITY := 520.0
const BOUNCE := 0.35

var kind := "frag"
var vel := Vector2.ZERO
var shooter_id := 0

var _data: Dictionary
var _t := 0.0
var _rest := false
var _light: PointLight2D
var _hd := false

func _ready() -> void:
	add_to_group("grenades")
	_data = Throwables.KINDS[kind]
	z_index = 2
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), 1.6, _data["color"], 0.0, false)
	add_child(_light)
	if Sprites.newitem and ItemsHd.has(kind):
		_hd = true
		ItemsHd.make(kind, self, 1.1 if kind == "frag" else 0.7, 0.3)           # HD: ten sam model co w ekwipunku; światło z _light miga jak zapalnik

func _physics_process(delta: float) -> void:
	_t += delta
	var fuse: float = _data["fuse"]
	if _t >= fuse:
		if NoiseMgr.is_server():
			_detonate()
		queue_free()
		return
	# mruganie przyspiesza do wybuchu
	var rate := 4.0 + 14.0 * (_t / fuse)
	_light.energy = 0.9 if fmod(_t * rate, 1.0) < 0.35 else 0.0
	queue_redraw()
	if _rest:
		return
	vel.y += GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	var n: Vector2 = hit["normal"]
	global_position = hit["position"] + n
	if n.y < -0.5 and absf(vel.y) < 70.0:
		_rest = true
		vel = Vector2.ZERO
		return
	vel = vel.bounce(n) * BOUNCE
	if vel.length() > 40.0:
		Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_WORLD, -12.0, 1.6)

## Serwer: wybuch w miejscu granatu.
func _detonate() -> void:
	match kind:
		"smoke":
			NoiseMgr.add_noise(float(_data["noise"]), global_position)
			var slvl := get_tree().get_first_node_in_group("level")
			if slvl != null:
				slvl.spawn_smoke(global_position + Vector2(0, -6), float(_data["cloud_life"]))
		"frag":
			Combat.explode(get_tree(), global_position + Vector2(0, -4), float(_data["radius"]), float(_data["damage"]), shooter_id, Weapons.GNIEW4)
		"phos":
			NoiseMgr.add_noise(float(_data["noise"]), global_position)
			var lvl := get_tree().get_first_node_in_group("level")
			if lvl == null:
				return
			var space := get_world_2d().direct_space_state
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 64.0), 1 | 16))
			if floor_hit.is_empty():
				return
			var base: Vector2 = (floor_hit["position"] as Vector2) + Vector2(0, -1)
			var cnt := int(_data["field_patches"])
			for i in cnt:
				var off := (float(i) - float(cnt - 1) * 0.5) * 24.0
				lvl.spawn_fire_patch(base + Vector2(off, 0.0), Weapons.HKM9, shooter_id, float(_data["field_life"]))

func _draw() -> void:
	if _hd:
		return
	var c: Color = _data["color"]
	if kind == "frag":
		draw_circle(Vector2(0, -3), 3.0, Color(0.22, 0.3, 0.18))
		draw_rect(Rect2(-1, -7, 2, 2), Color(0.5, 0.5, 0.45))
		draw_circle(Vector2(-1, -4), 1.0, c)
	elif kind == "smoke":
		draw_rect(Rect2(-2, -7, 4, 6), Color(0.38, 0.4, 0.42))
		draw_rect(Rect2(-2, -4, 4, 2), c)
		draw_rect(Rect2(-1, -8, 2, 1), Color(0.6, 0.6, 0.6))
	else:
		draw_rect(Rect2(-2, -7, 4, 6), Color(0.55, 0.55, 0.5))
		draw_rect(Rect2(-2, -5, 4, 2), c)
		draw_rect(Rect2(-1, -8, 2, 1), Color(0.7, 0.7, 0.65))
