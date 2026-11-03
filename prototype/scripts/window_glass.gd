extends Node2D
## Okno ze szkłem w ścianie budynku (znacznik „|", DESTRUCTION_PLAN.md D1): pionowy ciąg kafli `rows`, pozycja = stopy (dół okna).
## Rama (warstwa RAMA_LAYER) zatrzymuje tylko ruch — graczy, bota i wrogów; kule, wzrok i światło przez okno przechodzą zawsze.
## Szyba (`Pane`, warstwa obiektów 32 i SOUND_LAYER, grupa „shootables”): kula, śrut, promień, wybuch albo cios ją tłucze (serwer) — sypie
## szkłem, brzęk, mały hałas, a pocisk leci dalej. Cała szyba tłumi dźwięk dla graczy (okluzja `audio_director.gd`, siatka dźwięku
## `level._is_sound_solid`), stłuczona już nie. Wipe i punkt kontrolny wstawiają szybę z powrotem, dołączający dostaje stłuczoną.

const Vfx := preload("res://scripts/vfx.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const TILE := 16
const FRAME_LAYER := 128            ## rama okna: tylko ruch (maska graczy, bota i wrogów)
const SOUND_LAYER := 256            ## cała szyba: okluzja dźwięku (audio_director.gd OCCLUSION_MASK)
const PANE_LAYER := 32              ## szyba jako cel pocisków (Combat.LAYER_TARGET)
const N_BREAK := 3.0                ## hałas stłuczenia (jak `glass` w breakable.gd)
const SHARDS := 14                  ## odłamków szkła

## Szyba: cel dla kul (grupa „shootables” — pocisk ją tłucze i leci dalej, `projectile.gd`, `Combat.trace`).
class Pane extends StaticBody2D:
	var window: Node2D
	func take_hit(info: Dictionary) -> Dictionary:
		return window.take_hit(info)

var rows := 2
var intact := true
var _pane: Pane

func _ready() -> void:
	add_to_group("windows")
	var size := Vector2(TILE, TILE * float(rows))
	var frame := StaticBody2D.new()
	frame.name = "Frame"
	frame.collision_layer = FRAME_LAYER
	frame.collision_mask = 0
	frame.add_child(_rect_shape(size))
	add_child(frame)
	_pane = Pane.new()
	_pane.window = self
	_pane.name = "Pane"
	_pane.collision_mask = 0
	_pane.add_to_group("shootables")
	_pane.add_child(_rect_shape(Vector2(4.0, size.y)))           # cienka szyba w osi ściany
	add_child(_pane)
	_set_pane(true)

func _rect_shape(size: Vector2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	cs.position = Vector2(0, -size.y * 0.5)
	return cs

func _set_pane(on: bool) -> void:
	intact = on
	_pane.collision_layer = (PANE_LAYER | SOUND_LAYER) if on else 0

## Prostokąt okna w świecie (cios, wybuch).
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-TILE * 0.5, -TILE * float(rows)), Vector2(TILE, TILE * float(rows)))

func body_center() -> Vector2:
	return hit_rect().get_center()

## Serwer: każde trafienie z obrażeniami tłucze całą szybę; pocisk leci dalej (`pass`).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not intact or float(info.get("amount", 0.0)) <= 0.0:
		return {}
	shatter((info.get("dir", Vector2.RIGHT) as Vector2))
	return {"hit": true, "pass": true, "dealt": 0.0, "mat": Arsenal.Mat.WORLD}

## Serwer: stłuczenie — hałas, wpis do dziennika sesji i efekt u wszystkich (odłamki lecą w stronę strzału).
func shatter(dir := Vector2.RIGHT) -> void:
	if not NoiseMgr.is_server() or not intact:
		return
	NoiseMgr.add_noise(N_BREAK, body_center(), "glass")
	SessionLog.event("window", {"name": String(name)})
	var side := 1.0 if dir.x >= 0.0 else -1.0
	if NoiseMgr.has_network():
		_break_rpc.rpc(side)
	else:
		_break_rpc(side)

## `side` — kierunek strzału (odłamki lecą za szybę); 0 = bez efektów (dołączający).
@rpc("authority", "call_local", "reliable")
func _break_rpc(side: float) -> void:
	if not intact:
		return
	_set_pane(false)
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and lvl.has_method("window_changed"):
		lvl.window_changed(self)
	if side == 0.0:
		return
	var parent: Node = lvl if lvl != null else get_parent()
	var rc := hit_rect()
	for i in SHARDS:
		var p := Vector2(global_position.x + randf_range(-1.5, 1.5), rc.position.y + randf() * rc.size.y)
		Vfx.debris(parent, p, Vector2(side * randf_range(20.0, 80.0), randf_range(-50.0, 10.0)), Vector2(2, 2), Color(0.6, 0.7, 0.72))
	Audio.play_variant_at("glass_break", 2, body_center(), Audio.BUS_WORLD, 0.0, 1.0)

## Wipe / punkt kontrolny (każdy peer): szyba wraca.
func restore() -> void:
	if intact:
		return
	_set_pane(true)
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and lvl.has_method("window_changed"):
		lvl.window_changed(self)

## Dołączający gracz dostaje stłuczoną szybę bez efektów.
func send_state_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and not intact:
		_break_rpc.rpc_id(peer_id, 0.0)
