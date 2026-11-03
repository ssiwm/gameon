extends Node2D
## Lampa pod sufitem: na kablu, ciepłe, lekko migoczące światło. Pozycja = punkt pod sufitem.
## Znacznik „l" — lampa kryjówki (nietykalna). Znacznik „I" — lampa misji do zestrzelenia (DESTRUCTION_PLAN.md D1, `shootable`): kula, śrut
## albo wybuch ją tłucze (serwer) — gaśnie światło, sypie szkło, krótki brzęk i mały hałas, a pocisk leci dalej. Zapalona zdradza:
## gracza w jej świetle widzi Stalker (`Lights.lamp_lit_player`), ćmy krążą przy niej jak przy płomieniu (`enemy_moth.gd: nearest_light`).
## Wipe i punkt kontrolny zapalają ją z powrotem (`level._reset_breakables_rpc`), dołączający dostaje stłuczone (`send_state_to`).

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Vfx := preload("res://scripts/vfx.gd")
const SessionLog := preload("res://scripts/session_log.gd")

## Cienie postaci od lampy (plan ATMOSPHERE_PLAN.md, F3): włączane tylko, gdy w pobliżu ktoś stoi — MEDIUM bliżej, HIGH dalej, LOW wcale.
const SHADOW_RANGE_PX := [0.0, 190.0, 300.0]

const RADIUS_M := 9.0
const ENERGY := 0.85
const BULB := Vector2(0, 11)        ## żarówka względem punktu pod sufitem (światło, poświata, trafienie)
const HIT_R := 4.0                  ## promień trafienia klosza [px] (ok. 25 cm)
const N_BREAK := 3.0                ## hałas stłuczenia (cichszy od pękającej skrzyni)
const SHARDS := 10                  ## odłamków szkła

## Klosz lampy misji: cel dla kul (warstwa obiektów 32, grupa „shootables” — pocisk go tłucze i leci dalej, `projectile.gd`, `Combat.trace`).
class LampBody extends StaticBody2D:
	var lamp: Node2D
	func take_hit(info: Dictionary) -> Dictionary:
		return lamp.take_hit(info)

var shootable := false              ## lampa misji (znacznik „I")
var lit := true
var _light: Lights.GameLight
var _shadow_check := 0.0
var _t := 0.0

func _ready() -> void:
	add_to_group("lamps")                                 # cień kontaktowy postaci (player.gd) szuka najbliższej lampy
	z_index = 2
	_t = randf() * 20.0
	_light = Lights.make_light(Lights.radial(), RADIUS_M, Color(1.0, 0.78, 0.5), ENERGY, false)
	_light.position = BULB
	add_child(_light)
	if Sprites.newitem and ItemsHd.has("lamp"):
		# HD: sprite lampy — „stopy" sprite'a to dół klatki, więc dół ustawiamy tak, by szczyt (uchwyt kabla) wypadł w punkcie kotwicy pod sufitem
		var sp := ItemsHd.make("lamp", self, 0.9)
		sp.position = Vector2(0, ItemsHd.body_wp("lamp").y * 0.9)
	if shootable:
		add_to_group("mission_lamps")
		var body := LampBody.new()
		body.lamp = self
		body.name = "Bulb"
		body.collision_layer = 32
		body.collision_mask = 0
		body.add_to_group("shootables")
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = HIT_R
		cs.shape = sh
		cs.position = BULB
		body.add_child(cs)
		add_child(body)

func _process(delta: float) -> void:
	if not lit:
		return
	_t += delta
	var f := 0.93 + 0.07 * sin(_t * 9.0) * sin(_t * 3.7)
	_light.energy = ENERGY * f
	_shadow_check -= delta
	if _shadow_check <= 0.0:
		_shadow_check = 0.25
		_update_shadows()

## Cienie włączone, gdy któraś postać jest w zasięgu zależnym od jakości (maks. kilka lamp naraz).
func _update_shadows() -> void:
	var rng: float = SHADOW_RANGE_PX[clampi(Settings.quality_idx, 0, 2)]
	var on := false
	if rng > 0.0:
		for p in get_tree().get_nodes_in_group("players"):
			if p is Node2D and (p as Node2D).global_position.distance_to(global_position) < rng:
				on = true
				break
	_light.shadow_enabled = on

## Punkt żarówki w świecie.
func bulb_pos() -> Vector2:
	return global_position + BULB

## Serwer: każde trafienie z obrażeniami tłucze zapaloną lampę misji; pocisk leci dalej (`pass`). Stłuczona już nic nie przyjmuje.
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not shootable or not lit or float(info.get("amount", 0.0)) <= 0.0:
		return {}
	shatter()
	return {"hit": true, "pass": true, "dealt": 0.0, "mat": Arsenal.Mat.WORLD}

## Serwer: stłuczenie — hałas, wpis do dziennika sesji i efekt u wszystkich.
func shatter() -> void:
	if not NoiseMgr.is_server() or not lit:
		return
	NoiseMgr.add_noise(N_BREAK, bulb_pos(), "glass")
	SessionLog.event("lamp", {"name": String(name)})
	if NoiseMgr.has_network():
		_break_rpc.rpc(true)
	else:
		_break_rpc(true)

@rpc("authority", "call_local", "reliable")
func _break_rpc(fx: bool) -> void:
	lit = false
	_light.enabled = false
	_light.shadow_enabled = false
	if not fx:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	var p := bulb_pos()
	for i in SHARDS:
		Vfx.debris(parent, p + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 2.0)),
			Vector2(randf_range(-55.0, 55.0), randf_range(-40.0, 30.0)), Vector2(2, 2), Color(0.6, 0.7, 0.72))
	Vfx.sparks(parent, p, Vector2.DOWN)
	Audio.play_variant_at("glass_break", 2, p, Audio.BUS_WORLD, -3.0, 1.25)

## Wipe / punkt kontrolny (każdy peer): lampa znów świeci.
func relight() -> void:
	lit = true
	_light.enabled = true

## Dołączający gracz dostaje stłuczoną lampę bez efektów.
func send_state_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and shootable and not lit:
		_break_rpc.rpc_id(peer_id, false)
