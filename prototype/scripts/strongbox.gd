extends Node2D
## Sejf (FUN_PLAN.md P2.2): zamknięta skrzynia z łupem, którą trzeba wyważyć — ryzyko za nagrodę. Stoi w punktach STRONGBOXES z danych mapy
## (level.gd: [kolumna, rząd, złom]).
##
## Gracz TRZYMA [E] przez PRY_TIME s (dwie osoby = 2× szybciej). Wyważanie jest głośne (PRY_NOISE_PER_S), a otwarcie robi łoskot
## (OPEN_BURST) — Uwaga rośnie świadomie, za łup większy niż ukryta skrytka (Scrap.STASH_VALUE). Łup trafia do łupu misji (przepada przy
## wipe'ie, jak każdy). Autorytet: serwer (postęp i otwarcie); klienci dostają stan przez _sync / _sync_open. Każdy gracz zgłasza tylko
## „trzymam / puściłem" (_work_rpc), a serwer sam sprawdza zasięg i życie — jak generator (generator.gd).

const Lights := preload("res://scripts/lights.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const SessionLog := preload("res://scripts/session_log.gd")

## Stalowa skrzynia sprzętowa zaginionego patrolu (items_proc_bake.py: m_strongbox): zamknięta na kłódkę z łańcuchem; po otwarciu
## osobny model z odchylonym wiekiem i pustym wnętrzem. Modele są w naturalnej skali (1 jednostka = 1 piksel świata), stąd skala 1.
const MODEL := "strongbox"
const MODEL_OPEN := "strongbox_open"
const HD_SCALE := 1.0
const PRY_TIME := 3.0
const REACH_X := 26.0
const REACH_Y := 40.0
const PRY_NOISE_PER_S := 3.0         ## Uwaga na sekundę pracy jednej osoby (całe wyważanie ≈ +9)
const NOISE_CHUNK := 0.5
const OPEN_BURST := 12.0             ## łoskot drzwi przy otwarciu (budzi okolicę — to cena łupu)
const DECAY_PER_S := 0.5
const SYNC_INTERVAL := 0.1

var value := 40                      ## złom w środku (ustawia level.gd przed dodaniem do sceny)
var progress := 0.0
var opened := false
var local_in_range := false          ## lokalny człowiek stoi w zasięgu (HUD pokazuje podpowiedź)

var _holding := false
var _workers := {}
var _sync_t := 0.0
var _noise_acc := 0.0
var _sent_progress := -1.0
var _light: Lights.GameLight
var _hd: ItemsHd.ItemMark
var _hd_open: ItemsHd.ItemMark       ## otwarta skrzynia (ukryta, dopóki sejf zamknięty)
var _t := 0.0

func _ready() -> void:
	add_to_group("strongboxes")
	z_index = 2
	if ItemsHd.has(MODEL):
		_hd = ItemsHd.make(MODEL, self, HD_SCALE, 0.15)
		_hd.position = Vector2(ItemsHd.cx(MODEL) * HD_SCALE, 0.0)
	if ItemsHd.has(MODEL_OPEN):
		_hd_open = ItemsHd.make(MODEL_OPEN, self, HD_SCALE, 0.15)
		_hd_open.position = Vector2(ItemsHd.cx(MODEL_OPEN) * HD_SCALE, 0.0)
		_hd_open.visible = false
	_light = Lights.make_light(Lights.radial(), 1.8, Color(1.0, 0.72, 0.3), 0.5, false)
	_light.position = Vector2(0, -10)
	add_child(_light)

func _in_reach(p: Vector2, mult := 1.0) -> bool:
	return absf(p.x - global_position.x) <= REACH_X * mult and absf(p.y - global_position.y) <= REACH_Y * mult

func _local_human() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

# ---------------------------------------------------------------- każdy peer: czy MÓJ gracz wyważa

func _update_local() -> void:
	var me := _local_human()
	var near: bool = me != null and not opened and not me.dead and _in_reach(me.global_position)
	local_in_range = near
	var want := false
	if near and Input.is_action_pressed("interact"):
		# ratowanie kolegi i podnoszenie broni mają pierwszeństwo przed sejfem
		want = me.revive_hint() == "" and me.weapons.nearby_weapon_item() == null
	if want == _holding:
		return
	_holding = want
	if NoiseMgr.is_server():
		set_worker(NoiseMgr.local_id(), want)
	else:
		_work_rpc.rpc_id(1, want)

@rpc("any_peer", "call_remote", "reliable")
func _work_rpc(on: bool) -> void:
	if multiplayer.is_server():
		set_worker(multiplayer.get_remote_sender_id(), on)

## Serwer: gracz `peer_id` zaczyna albo przestaje wyważać (testy wołają to wprost).
func set_worker(peer_id: int, on: bool) -> void:
	if on:
		_workers[str(peer_id)] = true
	else:
		_workers.erase(str(peer_id))

# ---------------------------------------------------------------- serwer

func _physics_process(delta: float) -> void:
	_t += delta
	_update_local()
	if _light != null:
		_light.energy = 0.0 if opened else 0.45 + 0.15 * sin(_t * 3.0)
	if _hd != null and not opened:
		_hd.position.x = ItemsHd.cx(MODEL) * HD_SCALE + (sin(_t * 47.0) * 0.25 if progress > 0.0 and not _workers.is_empty() else 0.0)
	if not NoiseMgr.is_server() or opened:
		return
	_validate_workers()
	if not _workers.is_empty():
		progress = minf(1.0, progress + delta / PRY_TIME * minf(float(_workers.size()), 2.0))
		_noise_acc += PRY_NOISE_PER_S * float(_workers.size()) * delta
		if _noise_acc >= NOISE_CHUNK:
			NoiseMgr.add_noise(_noise_acc, global_position, "strongbox")
			_noise_acc = 0.0
		if progress >= 1.0:
			_open()
	elif progress > 0.0:
		progress = maxf(0.0, progress - DECAY_PER_S * delta)
	_sync_t -= delta
	if _sync_t <= 0.0 and not is_equal_approx(progress, _sent_progress):
		_sync_t = SYNC_INTERVAL
		_sent_progress = progress
		if NoiseMgr.has_network():
			_sync.rpc(progress)

func _validate_workers() -> void:
	if _workers.is_empty():
		return
	var alive := {}
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and not p.is_queued_for_deletion() and _in_reach(p.global_position, 1.4):
			alive[String(p.name)] = true
	for k in _workers.keys():
		if not alive.has(k):
			_workers.erase(k)

func _open() -> void:
	progress = 1.0
	var who: Array = _workers.keys()
	_workers.clear()
	NoiseMgr.add_noise(OPEN_BURST, global_position, "strongbox")
	Scrap.add_loot(value)
	SessionLog.event("strongbox", {"pos": SessionLog.xy(global_position), "value": value, "noise": roundi(NoiseMgr.level), "workers": who.size()})
	print("[STRONGBOX] %s opened, +%d scrap" % [name, value])
	if NoiseMgr.has_network():
		_sync_open.rpc(true, value)
	_set_open(true, value)

## Restart misji: sejf znów zamknięty (level.gd tworzy go od nowa przy wczytaniu mapy; to — po wipe'ie na tej samej mapie).
func reset_strongbox() -> void:
	if not NoiseMgr.is_server():
		return
	progress = 0.0
	_sent_progress = -1.0
	_workers.clear()
	_noise_acc = 0.0
	if NoiseMgr.has_network():
		_sync_open.rpc(false, value)
		_sync.rpc(0.0)
	_set_open(false, value)

# ---------------------------------------------------------------- klienci

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(p: float) -> void:
	progress = p

@rpc("authority", "call_remote", "reliable")
func _sync_open(is_open: bool, v: int) -> void:
	_set_open(is_open, v)

func _set_open(on: bool, v: int) -> void:
	var was := opened
	opened = on
	if on:
		progress = 1.0
	if on and not was:
		Audio.play_variant_at("door", 2, global_position, Audio.BUS_WORLD, 0.0, 0.7)
		Audio.play_at("scrap_pickup", global_position, Audio.BUS_WORLD, -2.0)
		Feel.shake(1.5 if _local_human() != null and _in_reach(_local_human().global_position, 3.0) else 0.0)
		Msg.post("strongbox.%s" % name, Msg.Ch.TOAST, tr("STRONGBOX OPEN  +%d scrap") % v, {"style": Msg.Style.SUCCESS, "ttl": 2.5, "prio": 40})
	if _hd != null:
		_hd.visible = not on or _hd_open == null           # otwarta: podmiana na skrzynię z odchylonym wiekiem
		_hd.modulate.a = 0.45 if on and _hd_open == null else 1.0
	if _hd_open != null:
		_hd_open.visible = on
