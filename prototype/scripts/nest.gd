extends CharacterBody2D
## Gniazdo — cel misji „Gniazdo" (GDD §9, misja 1.3: „zniszcz 4 gniazda”). 60 HP: niszczy je każde trafienie bronią
## (kula, śrut, cios, wybuch, strumień HKM-9); WRATH-4 (AoE) najszybciej. Do 1.7.565 ten komentarz mówił „spal 3 gniazda”
## (pierwotny szkic misji, GDD tego nie wymaga).
## Od 1.7.566 gniazdo się PALI: ogień (strumień HKM-9, amunicja zapalająca, plama ognia z fire_patch.gd) podpala je na co najmniej
## BURN_MIN s; płonące traci BURN_DPS HP/s i co SCORCH_EVERY s parzy każdego gracza (także bota) w zasięgu SCORCH_R
## za pół serca (`player.deliver_chip`, jak głaz Wołka). Ogień to szybka droga do celu, ale nie stój przy nim.
## Symulacja i HP TYLKO na serwerze; klienci dostają stan przez _sync.
##
## Gniazdo jest w grupie „enemies", bo tak trafiają je pociski (projectile.gd)
## i tak resetuje je wipe (main._restart_mission → reset_enemy). Nie jest
## jednak zagrożeniem: boty go nie ostrzeliwują (is_threat = false), bo
## zniszczenie gniazda jest GŁOŚNE — to decyzja drużyny, nie bota.

signal destroyed(nest: Node)

const Hurtbox := preload("res://scripts/hurtbox.gd")
const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Sprites := preload("res://scripts/sprites.gd")

const MAX_HP := 60.0
## Hałas zniszczenia (GDD §8.1): pękające gniazdo budzi okolicę — to cena celu.
const N_DESTROY := 8.0
const BURN_DPS := 8.0          ## HP/s płonięcia (jak wróg, enemy.gd BURN_DPS): 60 HP spala się w 7,5 s
const BURN_MIN := 4.0          ## s: suche gniazdo raz podpalone płonie co najmniej tyle (plama ognia odnawia tylko 1,2 s)
const SCORCH_R := 26.0         ## px od środka gniazda (≈ 2,1 m; gniazdo ma ok. 1,6 m szerokości → ok. 1,5 m od brzegu)
const SCORCH_CHIP := 0.5       ## pół serca za każde sparzenie
const SCORCH_EVERY := 1.0      ## s między sparzeniami
const SCORCH_UP := 15.0        ## px: środek gniazda nad jego podstawą (strefa trafień 20 × 30 px)

var hp := MAX_HP
var alive := true

var _flash := 0.0
var _net_timer := 0.0
var _burn := 0.0               ## s płonięcia (serwer)
var _scorch_t := 0.0           ## s do następnego sparzenia graczy w zasięgu (serwer)
var _fx_left := 0.0            ## s, przez które płomienie u wszystkich jeszcze się palą (serwer odnawia je przed końcem)
var _glow: Lights.GameLight
var _spr: Array = []

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("nests")
	Hurtbox.add(self, 20.0, 30.0)                             # strefa trafień na wysokość modelu (enemy3d.gd SPEC „fit")
	# słaba pomarańczowa poświata — cel misji ma być do znalezienia w mroku,
	# ale nie oświetla okolicy (2,5 m, bez cieni)
	_glow = Lights.make_light(Lights.radial(), 2.5, Color(1.0, 0.45, 0.2), 0.7, false)
	_glow.position = Vector2(0, -8)
	add_child(_glow)
	if Sprites.has(Sprites.enemy_sheet("nest")):
		_spr = Sprites.attach(self, Sprites.enemy_sheet("nest"))
		Sprites.play(_spr, "pulse", position.x > 1000.0)
	# żar unoszący się nad gniazdem (widać je z daleka w mroku) to iskry 3D — view3d.gd: _sync_nests

func is_threat() -> bool:
	return false

## Kontrakt widoku (view3d.gd) — patrz enemy.gd: view_info.
func view_info() -> Dictionary:
	return {"kind": "nest", "alive": alive, "winding": false, "sp": 0, "flash": _flash > 0.0}

## Restart misji (wipe / nowa próba).
func reset_enemy() -> void:
	hp = MAX_HP
	_burn = 0.0
	_fx_left = 0.0
	_set_alive(true)
	_send_state(999.0)

func _set_alive(a: bool) -> void:
	alive = a
	visible = a
	Hurtbox.set_enabled(self, a)

## Obrażenia z broni (combat.gd).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or not alive:
		return {}
	var dmg: float = info["amount"]
	take_bullet(info["pos"], dmg)
	var fire: float = info.get("ignite", 0.0)
	if fire > 0.0 and alive:
		_ignite(fire)
	return {"hit": true, "dealt": dmg, "killed": not alive, "mat": Arsenal.Mat.FLESH}

## Płonie (serwer; testy i widok).
func burning() -> bool:
	return alive and _burn > 0.0

## Podpalenie (serwer): co najmniej BURN_MIN s. Pierwsze sparzenie po pół odstępu — kto stoi obok w chwili podpalenia, ma moment na odskok.
func _ignite(seconds: float) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	if _burn <= 0.0:
		_scorch_t = SCORCH_EVERY * 0.5
	_burn = maxf(_burn, maxf(seconds, BURN_MIN))
	if _fx_left < 0.5 or _burn > _fx_left + 0.5:
		_fx_left = _burn + 0.5
		if NoiseMgr.has_network():
			_ignite_fx.rpc(_fx_left)
		else:
			_ignite_fx(_fx_left)

func _tick_burn(delta: float) -> void:
	_fx_left = maxf(0.0, _fx_left - delta)
	if _burn <= 0.0 or not alive:
		return
	_burn = maxf(0.0, _burn - delta)
	_scorch_t -= delta
	if _scorch_t <= 0.0:
		_scorch_t += SCORCH_EVERY
		_scorch()
	hp -= BURN_DPS * delta
	if hp <= 0.0:
		_destroy()

## Sparzenie: każdy żywy gracz (człowiek i bot), którego środek jest w zasięgu SCORCH_R od środka gniazda.
func _scorch() -> void:
	var c := global_position + Vector2(0.0, -SCORCH_UP)
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or not is_instance_valid(pp) or bool(pp.get("dead")):
			continue
		if (pp.global_position + Vector2(0.0, -9.0)).distance_to(c) <= SCORCH_R:
			pp.deliver_chip(SCORCH_CHIP, c, "nest_fire")

## Płomienie na gnieździe — każdy peer (3D: view3d.gd `mirror_burning`, gasną same, gdy gniazdo pęknie).
@rpc("authority", "call_local", "reliable")
func _ignite_fx(seconds: float) -> void:
	Vfx.burning(self, seconds)

func take_bullet(_from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server() or not alive:
		return
	hp -= dmg
	_flash = 0.08
	if hp <= 0.0:
		_destroy()
	else:
		_send_state(999.0)

func _destroy() -> void:
	_burn = 0.0
	_set_alive(false)
	NoiseMgr.add_noise(N_DESTROY, global_position, "nest")
	_destroy_fx()
	_send_state(999.0)
	destroyed.emit(self)

## Efekty na KAŻDYM peerze (serwer wprost, klient po zmianie alive w _sync).
func _destroy_fx() -> void:
	Audio.play_at("flare_ignite", global_position, Audio.BUS_WORLD, -4.0, 0.7)
	Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -2.0, 0.6)
	if _local_dist() < 240.0:
		Feel.shake(2.5)
	Vfx.gibs(get_parent(), global_position + Vector2(0, -8), Color(0.42, 0.14, 0.18), 9)
	Vfx.burst_fx(global_position + Vector2(0, -8), {"color": Color(1.0, 0.55, 0.2), "amount": 40, "life": 0.9, "explosiveness": 0.9, "dir": Vector2(0, -1),
		"spread": 60.0, "vmin": 40.0, "vmax": 130.0, "gravity": Vector2(0, -60), "smin": 1.0, "smax": 2.5})      # płonące strzępy unoszą się

func _local_dist() -> float:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp != null and not pp.is_bot and pp.is_multiplayer_authority():
			return pp.global_position.distance_to(global_position)
	return INF

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if NoiseMgr.is_server():
		_tick_burn(delta)
		_send_state(delta)

## Stan rzadko się zmienia — wysyłamy przy zmianie i co 0,5 s (dla dołączających).
func _send_state(delta: float) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 0.5
	_sync.rpc(hp, alive)

@rpc("authority", "call_remote", "reliable")
func _sync(new_hp: float, is_alive: bool) -> void:
	if new_hp < hp - 0.01:
		_flash = 0.08
	hp = new_hp
	if alive and not is_alive:
		_set_alive(false)
		_destroy_fx()
	elif not alive and is_alive:
		_set_alive(true)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
		_glow.energy = 0.5 + 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 2.2 + position.x * 0.01))

func _draw() -> void:
	if not _spr.is_empty():
		(_spr[0] as AnimatedSprite2D).modulate = Color(2.4, 2.4, 2.4) if _flash > 0.0 else Color.WHITE
		if _spr[1] != null:
			(_spr[1] as AnimatedSprite2D).frame = (_spr[0] as AnimatedSprite2D).frame

## Stan paska życia nad modelem gniazda (world_bars.gd, warstwa ekranu).
func bar_state() -> Dictionary:
	return {"frac": clampf(hp / MAX_HP, 0.0, 1.0), "alive": alive and is_visible_in_tree(), "elite": false, "w": 28.0, "h": 38.0, "label": ""}
