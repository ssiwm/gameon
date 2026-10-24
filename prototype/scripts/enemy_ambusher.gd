extends "res://scripts/enemy_behavior.gd"
## Skoczek (GDD §7.1): zasadzka spod sufitu. Wisi, dopóki ktoś nie stanie (prawie) pod nim i go widać; wtedy odczepia się i spada (lądowanie rani, `land_hit`).
## Po zasadzce nie wraca na sufit — czatuje tam, gdzie wylądował.

const AMBUSH_DX := 36.0
const AMBUSH_DY_MAX := 220.0

var drop_attack := false     ## spada na gracza (obrażenia przy lądowaniu)

func reset() -> void:
	drop_attack = false

## Obudzony wiszący Skoczek odczepia się od sufitu i spada.
func on_wake() -> void:
	if e._hanging and e._def.get("hang", false):
		e._hanging = false
		drop_attack = true
		e.winding = true
		e.velocity = Vector2(0.0, 40.0)

## Po ruchu klatki: spadł na podłogę — uderza.
func after_slide() -> void:
	if drop_attack and e.is_on_floor():
		land_hit()

## Po zasadzce nie wraca do domu na sufit.
func returns_home() -> bool:
	return false

## Skoczek lądujący na graczu: 2 obrażenia, łoskot (hałas) i pył.
func land_hit() -> void:
	drop_attack = false
	e.winding = false
	e.visual_attack()
	for p in e.get_tree().get_nodes_in_group("players"):
		if not p.dead and absf(p.global_position.x - e.global_position.x) < 16.0 and absf(p.global_position.y - e.global_position.y) < 22.0:
			p.deliver_hit(e._scaled_damage(2), e.global_position, e.kind)
	NoiseMgr.add_noise(5.0, e.global_position)
	if NoiseMgr.has_network():
		e._crash_fx.rpc()
	else:
		e._crash_fx()

## Wiszący Skoczek spada, gdy ktoś stoi (prawie) pod nim i go widać (linia bez ściany).
func tick_hanging() -> void:
	if not e._def.get("hang", false):
		return
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var dx: float = absf(p.global_position.x - e.global_position.x)
		var dy: float = p.global_position.y - e.global_position.y
		if dx < AMBUSH_DX and dy > 10.0 and dy < AMBUSH_DY_MAX and e._clear_line(p):
			e.wake()
			return
