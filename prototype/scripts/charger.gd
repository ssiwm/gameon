extends Node2D
## Ładowarka akumulatorków latarki (BATTERY_PLAN.md B3, GDD §9: „ładowarki” na mapie 3.2). Stoi na znaczniku „Q” mapy.
##
## Gracz stoi w zasięgu ze ZGASZONĄ latarką: bateria rośnie CHARGE_PER_S s na sekundę (od zera do pełna w 30 s). Ładowarka, która ładuje,
## buczy — co HUM_INTERVAL s cichy hałas z jej miejsca (jak uruchomiony generator), więc bezpieczne światło kosztuje ciszę.
## Baterię liczy właściciel postaci (jak zużycie i wolne ładowanie w player.gd): każdy peer dolicza ją swoim postaciom (człowiekowi,
## a serwer także botom). Serwer sam rozstrzyga, czy ładowarka pracuje (kto stoi w zasięgu, żyje, nie świeci i nie ma pełnej baterii) —
## od tego zależy hałas, lampka i dziennik sesji; klienci dostają stan przez `_sync_active`.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const CHARGE_PER_S := 6.0            ## s świecenia na sekundę stania przy ładowarce
const REACH_X := 26.0
const REACH_Y := 40.0
const HUM_NOISE := 0.9               ## buczenie: ≥ progu budzenia (0,5), jak generator — słyszą je śpiący w zasięgu
const HUM_INTERVAL := 4.5
const LAMP_ON := Color(0.4, 1.0, 0.5)
const LAMP_IDLE := Color(1.0, 0.55, 0.25)

var active := false                  ## ktoś się ładuje (serwer rozstrzyga, klienci z _sync_active)
var local_charging := false          ## lokalny człowiek ładuje się w tej chwili (pasek akcji)

var _hum_t := HUM_INTERVAL
var _charging := {}                  ## serwer: nazwa gracza → true (ładuje się; do dziennika — zdarzenie przy wejściu)
var _light: Lights.GameLight
var _hd: ItemsHd.ItemMark

func _ready() -> void:
	add_to_group("chargers")
	z_index = 2
	if Sprites.newitem and ItemsHd.has("charger"):
		_hd = ItemsHd.make("charger", self, 1.0)
		_hd.position = Vector2(ItemsHd.cx("charger"), 0.0)
	_light = Lights.make_light(Lights.radial(), 1.2, LAMP_IDLE, 0.25, false)      # lampka kontrolna: pomarańczowa czeka, zielona ładuje
	_light.position = Vector2(0, -8)
	add_child(_light)

func _exit_tree() -> void:
	Audio.stop_loop(name)

func in_reach(p: Vector2) -> bool:
	return absf(p.x - global_position.x) <= REACH_X and absf(p.y - global_position.y) <= REACH_Y

## Czy postać `p` może się teraz ładować (każdy peer: dla siebie; serwer: dla stanu ładowarki).
func can_charge(p: Node) -> bool:
	return not p.dead and not p.flashlight and not p.is_queued_for_deletion() and in_reach(p.global_position) and p.battery_level() < 1.0

func _physics_process(delta: float) -> void:
	_charge_own(delta)
	if local_charging:
		Msg.hold("charger.local", Msg.Ch.ACTION, tr("Charging the flashlight — keep the light off"),
			{"sub": tr("The charger hums: things nearby can hear it"), "style": Msg.Style.INFO, "prio": 40})
	if not NoiseMgr.is_server():
		return
	var now := {}
	for p in get_tree().get_nodes_in_group("players"):
		if can_charge(p):
			now[String(p.name)] = true
			if not _charging.has(String(p.name)):
				SessionLog.note_battery("charger")
				SessionLog.event("battery", {"who": "P%d" % int(p.display_id), "bot": bool(p.is_bot), "src": "charger",
					"before": roundi(float(p.battery_level()) * 100.0)})
	_charging = now
	var on := not now.is_empty()
	if on != active:
		_set_active(on)
		if NoiseMgr.has_network():
			_sync_active.rpc(on)
	if active:
		_hum_t -= delta
		if _hum_t <= 0.0:
			_hum_t = HUM_INTERVAL
			NoiseMgr.add_noise(HUM_NOISE, global_position, "charger")
	else:
		_hum_t = minf(_hum_t, 1.0)                 # pierwsze buczenie chwilę po podejściu, a nie po pełnych 4,5 s

## Postacie, których baterię liczy ten peer (człowiek u siebie, boty na serwerze): doładowanie przy ładowarce.
func _charge_own(delta: float) -> void:
	local_charging = false
	for p in get_tree().get_nodes_in_group("players"):
		if NoiseMgr.has_network() and not p.is_multiplayer_authority():
			continue
		if not can_charge(p):
			continue
		p.charge_battery(CHARGE_PER_S * delta)
		if not p.is_bot:
			local_charging = true

## Restart misji: ładowarka bez stanu (nikt się nie ładuje, buczenie od nowa).
func reset_charger() -> void:
	_charging.clear()
	_hum_t = HUM_INTERVAL
	if NoiseMgr.is_server():
		_set_active(false)
		if NoiseMgr.has_network():
			_sync_active.rpc(false)

@rpc("authority", "call_remote", "reliable")
func _sync_active(on: bool) -> void:
	_set_active(on)

func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_light.color = LAMP_ON if on else LAMP_IDLE
	_light.energy = 0.7 if on else 0.25
	if on:
		Audio.play_at("radio_beep", global_position, Audio.BUS_WORLD, -10.0)
		Audio.start_loop_at("generator_loop", self, Audio.BUS_WORLD, -18.0, true, name)
	else:
		Audio.stop_loop(name)
