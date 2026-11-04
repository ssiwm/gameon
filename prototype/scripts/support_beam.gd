extends Node2D
## Stempel (znacznik „!”, DESTRUCTION_PLAN.md D3): drewniana podpora stropu w tunelu, połączona ze strefą zawału „^” obok (level.gd
## `_support_defs`). Nie blokuje ruchu — gracze i wrogowie przechodzą przed nim — ale jest celem: kula, śrut, kilof, granat, ładunek
## (materiał `support` w breakable.gd). Po złamaniu strop trzeszczy (level.gd `CAVE_DELAY`), potem strefa zapada się gruzem, który zamyka
## przejście; gruz da się odkopać (materiał `rubble`). Obrażenia liczy serwer; złamanie idzie do wszystkich przez level.gd (`support_broken`).
## Wipe i punkt kontrolny stawiają stempel z powrotem (`restore`), dołączający dostaje złamany bez efektów.
##
## Stopy w (0, 0) = podłoga, środek kafla w poziomie; `rows` = wysokość w kaflach do stropu.

const Breakable := preload("res://scripts/breakable.gd")
const Vfx := preload("res://scripts/vfx.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const TILE := 16.0
const WIDTH := 5.0                     ## px — belka ok. 30 cm (cel dla kul: wąski, trzeba celować)
const MAT := "support"

## Ciało belki: cel dla kul na warstwie obiektów (32, grupa „shootables” — jak klosz lampy misji): pocisk ją rani i leci dalej.
class BeamBody extends StaticBody2D:
	var beam: Node2D
	func take_hit(info: Dictionary) -> Dictionary:
		return beam.take_hit(info)

var rows := 3
var wall_name := ""                    ## strefa zawału „^”, którą ten stempel trzyma (level.gd)
var intact := true
var hp := -1.0
var _body: BeamBody
var _flash := 0.0

func mat_def() -> Dictionary:
	return Breakable.MATERIALS[MAT]

func max_hp() -> float:
	return float(mat_def()["hp"])

func _ready() -> void:
	add_to_group("supports")
	z_index = -1
	if hp < 0.0:
		hp = max_hp()
	_body = BeamBody.new()
	_body.beam = self
	_body.name = "Beam"
	_body.collision_layer = 32
	_body.collision_mask = 0
	_body.add_to_group("shootables")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(WIDTH, TILE * float(rows))
	cs.shape = rs
	cs.position = Vector2(0, -TILE * float(rows) * 0.5)
	_body.add_child(cs)
	add_child(_body)
	_set_body(intact)

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

## Prostokąt belki w świecie (cios, wybuch, test).
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-WIDTH * 0.5, -TILE * float(rows)), Vector2(WIDTH, TILE * float(rows)))

func body_center() -> Vector2:
	return hit_rect().get_center()

func is_threat() -> bool:
	return false

func hit_radius() -> float:
	return WIDTH

## Serwer: trafienie z listy `breaks` materiału `support` rani belkę; reszta (maczeta) odbija się bez obrażeń. Kula leci dalej (`pass`).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not intact or float(info.get("amount", 0.0)) <= 0.0:
		return {}
	var m := mat_def()
	var kind := Breakable.hit_kind(info)
	if not (m["breaks"] as Array).has(kind):
		return {"hit": false, "pass": true, "dealt": 0.0, "killed": false, "mat": 0}
	hp -= float(info["amount"])
	NoiseMgr.add_noise(float(m["n_hit"]), body_center(), "wall")
	var p: Vector2 = info.get("pos", body_center())
	if NoiseMgr.has_network():
		_hit_fx_rpc.rpc(p)
	else:
		_hit_fx_rpc(p)
	var broken := hp <= 0.0
	if broken:
		NoiseMgr.add_noise(float(m["n_break"]), body_center(), "wall")
		SessionLog.event("support", {"name": String(name), "zone": wall_name, "by": kind, "shooter": int(info.get("shooter", -1))})
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.support_broken(String(name))
	return {"hit": true, "pass": true, "dealt": float(info["amount"]), "killed": broken, "mat": int(m["mat"])}

@rpc("authority", "call_local", "unreliable")
func _hit_fx_rpc(p: Vector2) -> void:
	_flash = 0.12
	queue_redraw()
	var m := mat_def()
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	for i in 3:
		Vfx.debris(parent, p, Vector2(randf_range(-50.0, 50.0), randf_range(-60.0, -10.0)), Vector2(2, 2), m["debris"])
	var snd: Array = m["hit_snd"]
	Audio.play_variant_at(String(snd[0]), int(snd[1]), p, Audio.BUS_WORLD, float(snd[2]), float(snd[3]))

## U wszystkich (level.gd `_support_rpc`): belka pęka — odłamki i trzask (`fx`), ciało znika z kul.
func snap(fx: bool) -> void:
	intact = false
	hp = 0.0
	_set_body(false)
	queue_redraw()
	if not fx:
		return
	var m := mat_def()
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	var rc := hit_rect()
	for i in int(m["chips"]):
		var p := Vector2(rc.position.x + randf() * rc.size.x, rc.position.y + randf() * rc.size.y)
		Vfx.debris(parent, p, Vector2(randf_range(-70.0, 70.0), randf_range(-90.0, -10.0)), Vector2(3, 2), m["debris"])
	Vfx.dust(parent, rc.get_center(), float((m["dust"] as Array)[1]))
	var snd: Array = m["break_snd"]
	Audio.play_variant_at(String(snd[0]), int(snd[1]), global_position, Audio.BUS_WORLD, float(snd[2]), float(snd[3]))

## Wipe / punkt kontrolny (każdy peer): stempel znów stoi, cały.
func restore() -> void:
	intact = true
	hp = max_hp()
	_set_body(true)
	queue_redraw()

func _set_body(on: bool) -> void:
	if _body == null:
		return
	_body.collision_layer = 32 if on else 0

func _draw() -> void:
	var h := TILE * float(rows)
	var col := Color(0.45, 0.32, 0.18) if _flash <= 0.0 else Color(0.9, 0.8, 0.6)
	if intact:
		draw_rect(Rect2(-WIDTH * 0.5, -h, WIDTH, h), col)
		draw_rect(Rect2(-TILE * 0.6, -h, TILE * 1.2, 3.0), col.darkened(0.2))        # podciąg pod stropem
	else:
		draw_rect(Rect2(-WIDTH * 0.5, -h * 0.3, WIDTH, h * 0.3), col.darkened(0.3))  # złamany kikut
