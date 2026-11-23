extends Node2D
## Kwas Pijawki (faza 2+): pocisk po łuku, który boss pluje w gracza poza zasięgiem zasadzki (brzeg, kładka). Lot deterministyczny
## z parametrów startu (jak granat), więc nie jest synchronizowany; trafienie (1 HP) rozstrzyga serwer. Znika przy ścianie albo po trafieniu.
## Grupa „acid" — boty widzą go i robią unik (player.gd `_bot_dodge_acid`).
## Osłona z blachy (DESTRUCTION_CONTENT_PLAN.md W6, warstwa Combat.LAYER_COVER) zatrzymuje go jak ściana; serwer zadaje jej trafienie `acid`
## (trzecie ją przeżera). Lot jest ten sam u każdego peera, więc kwas znika na osłonie wszędzie, a jej stan przychodzi od serwera.

const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Sight := preload("res://scripts/sight.gd")

const GRAVITY := 520.0
const HIT_R := 9.0
const LIFE := 3.0
const COVER_LAYER := 2048            ## Combat.LAYER_COVER — osłony B1

var vel := Vector2.ZERO
var _t := 0.0
var _light: Lights.GameLight

func _ready() -> void:
	add_to_group("acid")
	z_index = 3
	material = Lights.unshaded()
	_light = Lights.make_light(Lights.radial(), 1.5, Color(0.55, 1.0, 0.35), 0.8, false)
	add_child(_light)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFE:
		queue_free()
		return
	vel.y += GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	var hit := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1 | COVER_LAYER))
	if not hit.is_empty():
		global_position = hit["position"]
		var bw := Sight.barrier_of(hit["collider"])
		if bw != null and NoiseMgr.is_server() and bw.has_method("take_hit"):
			bw.take_hit({"type": "acid", "amount": 1.0, "pos": hit["position"], "dir": vel.normalized(), "shooter": -1, "src": "leech"})
		_splash()
		return
	global_position = to
	queue_redraw()
	if NoiseMgr.is_server():
		for p in get_tree().get_nodes_in_group("players"):
			if p.dead or p.is_queued_for_deletion():
				continue
			if p.hurt_point(global_position).distance_to(global_position) <= HIT_R + 3.0:
				p.deliver_hit(1, global_position, "acid")
				_splash()
				return

func _splash() -> void:
	Vfx.splash(get_parent(), global_position, 0.8, false)
	Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, -4.0, 1.6)
	queue_free()
