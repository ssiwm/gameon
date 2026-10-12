extends Node2D
## Postawiony ładunek (A2): mina kierunkowa i ładunek wyburzeniowy. Stoją pod nogami rzucającego; wybuch rozstrzyga serwer,
## wszyscy peerzy dostają zdarzenie `_boom` (efekt + zniknięcie).
##   mine   — po 1 s uzbrojona; pierwszy PRZEBUDZONY wróg w stożku (±38°, 84 px) odpala ją: 120 obrażeń każdemu w stożku. Nie rani drużyny.
##   charge — po 4 s: wybuch 5 m, 150 obrażeń, rozbija zamurowane przejścia, rani też drużynę; najgłośniejszy przedmiot.

const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Combat := preload("res://scripts/combat.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const SCAN_EVERY := 0.1

var kind := "mine"
var dir := Vector2.RIGHT
var shooter_id := 0

var _data: Dictionary
var _t := 0.0
var _scan_t := 0.0
var _done := false
var _hd: ItemsHd.ItemMark
var _hd_on := false
var _beeping := false        ## uzbrojona mina piszczy (pętla pozycyjna, lokalnie na każdym peerze)

func _ready() -> void:
	add_to_group("placed")
	_data = Throwables.KINDS[kind]
	z_index = 2
	material = Lights.unshaded()
	if Sprites.newitem and ItemsHd.has(kind):
		# HD: mina (przód do wroga — odbita w poziomie, gdy celujesz w lewo) i ładunek; dioda uzbrojenia/zapalnika świeci dynamicznie
		_hd_on = true
		_hd = ItemsHd.make(kind, self, 0.8 if kind == "mine" else 0.75, 0.3)
		if kind == "mine" and dir.x < 0.0:
			_hd.scale.x = -_hd.scale.x

func is_armed() -> bool:
	return kind == "mine" and _t >= float(_data["arm"])

func _exit_tree() -> void:
	if _beeping:
		Audio.stop_loop(_beep_id())

func _beep_id() -> String:
	return "mine_%d" % get_instance_id()

func _physics_process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if not _beeping and is_armed():
		# cichy sygnał uzbrojenia: słychać z kilku metrów, wrogów nie budzi (to nie hałas w NoiseMgr)
		_beeping = true
		Audio.start_loop_at("mine_beep_loop", self, Audio.BUS_WORLD, -16.0, true, _beep_id())
	if _done or not NoiseMgr.is_server():
		return
	if kind == "charge":
		if _t >= float(_data["fuse"]):
			_detonate_charge()
		return
	if not is_armed():
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_EVERY
	if _victims(true).size() > 0:
		_detonate_mine()

func _origin() -> Vector2:
	return global_position + Vector2(0, -4)

## Cele w stożku miny. `trigger_only`: tylko przebudzeni wrogowie-zagrożenia (odpalają); inaczej wszystko, co oberwie.
func _victims(trigger_only: bool) -> Array:
	var space := get_world_2d().direct_space_state
	var found := Combat.in_cone(get_tree(), space, _origin(), dir, float(_data["range"]), float(_data["half_deg"]))
	if not trigger_only:
		return found
	return found.filter(func(n: Node) -> bool:
		return n.has_method("is_threat") and bool(n.call("is_threat")) and not n.is_in_group("props") and not n.is_in_group("breakables"))

func _detonate_mine() -> void:
	_done = true
	var origin := _origin()
	NoiseMgr.add_noise(float(_data["noise"]), global_position, "explosive")
	var d: RefCounted = Weapons.def(Weapons.GNIEW4)
	for n in _victims(false):
		var c := Combat.center_of(n)
		var info := Combat.make_info(Weapons.GNIEW4, float(_data["damage"]), c, (c - origin).normalized(), shooter_id, "blast")
		info["knock"] = d.knock
		info["stun"] = d.stun
		info["heavy"] = true
		var res := Combat.apply(n, info)
		if bool(res["hit"]) and bool(res["killed"]):
			Arsenal.confirm(shooter_id, Arsenal.Confirm.KILL, c)
		elif bool(res["hit"]):
			Arsenal.confirm(shooter_id, Arsenal.Confirm.HIT, c)
	Arsenal.broadcast_explosion(origin + dir * float(_data["range"]) * 0.45, 34.0)
	_finish()

func _detonate_charge() -> void:
	_done = true
	NoiseMgr.add_noise(float(_data["noise"]), global_position, "explosive")
	Combat.explode(get_tree(), _origin() + Vector2(0, -2), float(_data["radius"]), float(_data["damage"]), shooter_id, Weapons.GNIEW4, true)
	_finish()

func _finish() -> void:
	if NoiseMgr.has_network():
		_boom.rpc()
	else:
		_boom()

@rpc("authority", "call_local", "reliable")
func _boom() -> void:
	queue_free()
