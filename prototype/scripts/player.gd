extends CharacterBody2D
## Gracz: ruch 8-kierunkowy (Contra), strzelanie, hałas, Przesterowanie,
## down/revive (GDD §4) i czucie gry (GDD §23).
##
## Synchronizacja (GDD §19 poz. 2): stan idzie przez MultiplayerSynchronizer
## (delta + interpolacja zamiast „snajp z ręki"), a pociski są SERWEROWE
## (spawn i kolizje rozstrzyga serwer, klienci tylko rysują).

const Weapons := preload("res://scripts/weapons.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Perks := preload("res://scripts/perks.gd")
const WeaponController := preload("res://scripts/weapon_controller.gd")
const WeaponView := preload("res://scripts/weapon_view.gd")
const Lights := preload("res://scripts/lights.gd")
const Nav := preload("res://scripts/nav.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Sprites := preload("res://scripts/sprites.gd")

const SPEED := 95.0
const CROUCH_SPEED := 45.0
const JUMP_VELOCITY := -275.0
const GRAVITY := 900.0
const MAX_FALL := 620.0
# Fizyka ruchu (1.5): bezwładność zamiast natychmiastowego startu/stopu.
# Wznoszenie bez zmian (skok 42 px — poziomy i nawigacja bota na tym stoją),
# opadanie szybsze: skok jest „cięższy" i bardziej kontrolowany.
const ACCEL := 1100.0          ## px/s² na ziemi
const DECEL := 1500.0          ## hamowanie bez wejścia
const TURN_ACCEL := 2400.0     ## zwrot w przeciwną stronę
const AIR_ACCEL := 650.0       ## kontrola w powietrzu
const FALL_MULT := 1.35        ## grawitacja przy opadaniu
const Surfaces := preload("res://scripts/surfaces.gd")
const MAX_HP := 3
## Apteczki kumulują się ponad MAX_HP aż do tego sufitu (złote serca); respawn i nowa misja wracają do MAX_HP.
const STACK_HP := 6
## Sekundy leżenia, po których perk „Second chance" stawia gracza na nogi (nie więcej niż 80% czasu wykrwawienia).
const SECOND_CHANCE_FRAC := 0.8
const BONUS_HEART := Color(1.0, 0.8, 0.25)

# Czucie gry (GDD §23)
const COYOTE_TIME := 0.10       ## skok jeszcze chwilę po zejściu z krawędzi
const JUMP_BUFFER := 0.10       ## skok wciśnięty tuż przed lądowaniem się liczy
const JUMP_CUT := 0.45          ## puszczenie skoku skraca go (zmienna wysokość)
const INVULN_AFTER_HIT := 0.6   ## chroni przed „serią\" trafień z kilku wrogów naraz
const KICK_DECAY := 600.0
const DROP_TIME := 0.25         ## tyle trwa zeskok przez kładkę (dół + skok)
const PLATFORM_LAYER_BIT := 5   ## warstwa kładek = 16 (level.gd LAYER_PLATFORM)
const FF_KICK := 70.0          ## odrzut od pocisku kolegi (px/s, wygasa KICK_DECAY)
const FF_COOLDOWN := 0.6       ## krzyk/hałas od FF najwyżej raz na tyle sekund

# Down / revive (GDD §4)
const NAME_SIZE := 4            ## etykieta nad głową (px świata) — mała, żeby nie dominowała nad sylwetką
const BLEED_TIME := 10.0
const REVIVE_TIME := 4.0
const REVIVE_RANGE := 26.0
const REVIVE_HP := 2
const REVIVE_SYNC_MS := 100     ## postęp podnoszenia wysyłany do innych peerów 10 Hz

# Bot a cisza (filar 2): bot nie może sam psuć skradania ani Przesterowania
const BOT_ENGAGE_RANGE := 220.0   ## ≤ zasięg M-83 (240 px): bot nie strzela pociskami, które zgasną w locie
const BOT_SELF_DEFENSE := 70.0  ## w tym promieniu strzela zawsze — obrona własna
const BOT_Q_HOLD := 8.0         ## po Q wstrzymuje ogień, żeby nie nadpisać celu stalkera
const BOT_EVADE_RANGE := 46.0   ## wróg bliżej niż tyle: bot rozważa unik
const BOT_CAR_LAG := 150.0      ## drezyna (handcar.gd): bot dalej od niej niż tyle px, gdy już jedzie, goni ją...
const BOT_CAR_LAG_T := 1.5      ## ... i po tylu sekundach bez dogonienia ląduje na pokładzie (bot chodzi wolniej niż drezyna)
const BOT_KITE_RANGE := 30.0    ## ... i cofa się, gdy jest bliżej niż to (strzela w biegu, M-83 nie ma minimalnego zasięgu)
const BOT_MEDKIT_RANGE := 180.0 ## ranny bot szuka apteczki w takim promieniu

# Latarka (GDD §6.6 / §8.3): stożek 8 m, bateria 3 min, światło = hałas
const BATTERY_MAX := 180.0
## Prototyp: bateria wolno się odnawia przy zgaszonej latarce (do playtestu —
## GDD nie mówi o ładowaniu; bez tego po 3 min misja byłaby czarna).
const BATTERY_RECHARGE := 0.25
const LIGHT_NOISE_EVERY := 10.0   ## +1 Uwagi co tyle sekund świecenia

const BODY_COLORS := [
	Color(0.91, 0.69, 0.29),
	Color(0.29, 0.84, 0.91),
	Color(0.91, 0.29, 0.44),
	Color(0.49, 0.91, 0.29),
]
const BOT_COLOR := Color(0.62, 0.62, 0.70)

@export var is_bot := false

var player_id := 1
var display_id := 1
var hp := MAX_HP
var aim_dir := Vector2.RIGHT
var crouching := false
## `dead` znaczy „down": gracz leży i wykrwawia się, ale można go podnieść.
var dead := false
var grabbed := false            ## chwycony przez Pijawkę (leech.gd): przypięty w miejscu, nie chodzi ani nie skacze, ale może strzelać i bić
var grab_pos := Vector2.ZERO
var pumping := false            ## drezyna (handcar.gd): gracz pompuje — nie chodzi, nie skacze i nie strzela
var bleed_left := 0.0
var weapon := 0                 ## id broni w ręku (replikowane); ustawia kontroler
## Stan broni dla widoku u pozostałych peerów (replikowane): faza, ładowanie szyny, ogień ciągły,
## zestaw (główna A, główna B, biała) — serwer z niego dobiera, do jakiej broni upuszczać amunicję.
var w_state := 0
var w_charge := 0.0
var w_firing := false
## Założone perki jako indeksy z `Perks.ORDER` (-1 = pusty slot); replikowane, ustawia je właściciel z lokalnego profilu.
var perks := Vector2i(-1, -1)
var _second_used := false
var _down_t := 0.0
var kit := Vector3i(Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_MELEE)
## Celowanie myszą (swobodne) a klawiaturą (8 kierunków) — celownik rysuje się odpowiednio.
var aim_by_mouse := false
var weapons: WeaponController
var view: WeaponView
## Postęp podnoszenia widoczny TYLKO lokalnie u podnoszącego (rysowany nad leżącym).
var revive_progress := 0.0
## Latarka włączona — replikowane, bo snop widzą wszyscy, a wrogowie
## (serwer) reagują na światło.
var flashlight := false
var battery := BATTERY_MAX

var _run_noise_tick := 0.0
var _flash := 0.0
var _invuln := 0.0
var _kick := 0.0
var _ff_cd := 0.0
var _coyote := 0.0
var _drop_t := 0.0
var _run_vx := 0.0              ## składowa ruchu z wejścia (bez odrzutu)
## Skala ciała: rozciąganie przy wybiciu, przysiad przy lądowaniu (każdy peer
## wylicza ją z replikowanej prędkości — działa też dla zdalnych i bota).
var squash := Vector2.ONE
var _prev_vy := 0.0
var _prev_floor_y := 0.0
var _splash_t := 0.0
var _spr: Array = []            ## [ciało, glow] — AnimatedSprite2D (sprites.gd)
var _spr_scale := 1.0           ## skala rysowania arkusza (2× gęstość pikseli → 0,5); mnoży ściśnięcie (squash)
var _facing := 1.0
var _light_noise_t := 0.0
var _aura: PointLight2D
var _beam: PointLight2D
var _overlay: Node2D
var _jump_buf := 0.0
var _was_on_floor := true
var _spawn_point := Vector2.ZERO
var _is_remote := true
var _revive_hold := 0.0
var _revive_target_ref: Node2D = null
var _revive_sent_ms := 0
## Kroki liczymy z przebytej drogi, nie z czasu — inaczej krok „leci" w miejscu
## po stopniowaniu w dół albo lata w powietrzu.
var _step_dist := 0.0
var _last_step_pos := Vector2.ZERO
var _breath_on := false
var _air_time_accum := 0.0

@onready var _camera: Camera2D = $Camera2D

## Synchronizator tworzymy w _init, a autorytet ustawiamy w _enter_tree
## (rekurencyjnie, więc obejmuje też synchronizator). Wcześniej synchronizator
## powstawał w _ready PO set_multiplayer_authority() i miał domyślny autorytet 1:
## serwer nadpisywał stan postaci klienta swoją nieruchomą kopią (ruch, HP
## i obrażenia klienta znikały). Zmiana autorytetu w _ready jest za późna dla
## spawnera („no network ID") — Godot wymaga _enter_tree.
func _init() -> void:
	_setup_sync()
	# Kontroler broni też w _init: jego RPC (strzał, cios, przyznanie broni) muszą dziedziczyć
	# autorytet gracza z _enter_tree, a węzeł dodany później by go nie dostał.
	weapons = WeaponController.new()
	weapons.name = "Weapons"
	add_child(weapons)

func _enter_tree() -> void:
	player_id = name.to_int()
	if player_id <= 0:
		player_id = 1
	# Nazwa węzła = id peera. Autorytet ustawiamy na KAŻDYM peerze, bo spawner
	# nie przenosi go na klientów — bez tego własna postać klienta miała
	# autorytet 1 i is_multiplayer_authority() zawodziło (HUD, obrażenia).
	# Boty: autorytet 1 (serwer) — ustawiony przez main.gd.
	if not is_bot:
		set_multiplayer_authority(player_id)

func _ready() -> void:
	add_to_group("players")
	_spawn_point = position
	_setup_lights()
	call_deferred("_setup_local")

## Światła postaci (każdy peer): aura 6 m, snop latarki 8 m, rozbłysk lufy.
## Etykiety i paski idą na nakładkę „unshaded" — w ciemności mają być czytelne.
func _setup_lights() -> void:
	var chest := Vector2(0, -9)
	_aura = Lights.make_light(Lights.radial(), Lights.BASE_M, Color(1.0, 0.9, 0.78), Lights.AURA_ENERGY, true)
	_aura.position = chest
	add_child(_aura)
	_beam = Lights.make_light(Lights.cone(), Lights.FLASHLIGHT_M, Color(1.0, 0.96, 0.84), 0.85, true)
	_beam.position = chest
	_beam.enabled = false
	add_child(_beam)
	_setup_sprites()
	view = WeaponView.new()
	view.setup(self, weapons)
	add_child(view)
	_overlay = Lights.add_overlay(self)   # ostatnie dziecko: etykiety nad sprite'ami

## Pixel-art z art/sprites (bake_sprites.py). Bez arkuszy zostaje rysowanie w kodzie.
func _setup_sprites() -> void:
	var sheet := "bot" if is_bot else "player_%d" % ((display_id - 1) % 4 + 1)
	if not Sprites.has(sheet):
		return
	_spr = Sprites.attach(self, sheet)
	_spr_scale = Sprites.scale_of(sheet)

## Animacja z (replikowanego) stanu — działa też dla zdalnych graczy i bota.
func _update_sprite() -> void:
	if _spr.is_empty():
		return
	var body: AnimatedSprite2D = _spr[0]
	var grounded := is_on_floor() if not _is_remote else absf(velocity.y) < 5.0
	if absf(aim_dir.x) > 0.1:
		_facing = signf(aim_dir.x)
	elif absf(velocity.x) > 10.0:
		_facing = signf(velocity.x)
	var anim := "idle"
	if dead:
		anim = "down"
	elif not grounded:
		anim = "jump" if velocity.y < 0.0 else "fall"
	elif crouching:
		anim = "crouch_walk" if absf(velocity.x) > 8.0 else "crouch"
	elif absf(velocity.x) > 10.0:
		anim = "run"
	body.scale = squash * _spr_scale
	Sprites.play(_spr, anim, _facing < 0.0)
	body.modulate = _tint_color()

## Kolor ciała: błysk po trafieniu i migotanie nietykalności (broń dostaje ten sam).
func _tint_color() -> Color:
	var m := Color.WHITE
	if _flash > 0.0:
		m = Color(2.4, 2.4, 2.4)
	elif _invuln > 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0:
		m.a = 0.45
	return m

## Facing z celowania/ruchu — wspólny dla sprite'a ciała i broni.
func _update_facing() -> void:
	if absf(aim_dir.x) > 0.1:
		_facing = signf(aim_dir.x)
	elif absf(velocity.x) > 10.0:
		_facing = signf(velocity.x)

## Synchronizacja stanu przez MultiplayerSynchronizer (GDD §19 poz. 2).
## Zamiast ręcznych RPC 20 Hz mamy delta-sync z wbudowaną interpolacją.
func _setup_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	# replication_config MUSI być ustawione PRZED add_child, inaczej replikacja
	# startuje z pustym configiem (ERR_UNCONFIGURED)
	sync.root_path = NodePath("..")
	sync.replication_interval = 0.05
	sync.delta_interval = 0.05
	var cfg := SceneReplicationConfig.new()
	for path in [":position", ":velocity", ":aim_dir", ":hp", ":crouching", ":dead", ":display_id", ":is_bot", ":bleed_left", ":weapon", ":flashlight", ":w_state", ":w_charge", ":w_firing", ":kit", ":perks"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path in [":position", ":velocity", ":hp", ":crouching", ":dead", ":is_bot", ":display_id"]:
		cfg.property_set_spawn(path, true)
	sync.replication_config = cfg
	add_child(sync)

func _setup_local() -> void:
	# Człowiek: autorytet = jego peer. Bot: autorytet = serwer (steruje nim host).
	_is_remote = not is_multiplayer_authority()
	var local_human := not is_bot and not _is_remote
	_camera.enabled = local_human
	if local_human:
		_camera.make_current()
		_camera.add_child(_dust_motes())
		_apply_level_bounds()
	var lvl_node := get_tree().get_first_node_in_group("level")
	if lvl_node != null:
		lvl_node.map_changed.connect(_on_map_changed)
	if local_human:
		Profile.changed.connect(_sync_perks)
		_sync_perks()
	print("[NET] player ready id=%d display=%d remote=%s bot=%s" % [player_id, display_id, str(_is_remote), str(is_bot)])

## Perki ------------------------------------------------------------------------------------------------------------------

func has_perk(id: String) -> bool:
	var i := Perks.ORDER.find(id)
	return i >= 0 and (perks.x == i or perks.y == i)

func perk_param(id: String, key: String, fallback: float) -> float:
	return Perks.param(id, key, fallback) if has_perk(id) else fallback

## Lokalny człowiek publikuje założone perki (zmieniają się tylko w kryjówce); zmiana perka „Veteran" od razu dolicza/odejmuje serce.
func _sync_perks() -> void:
	var before := max_hp()
	perks = Perks.to_indexes(Profile.equipped)
	var after := max_hp()
	if dead or after == before:
		return
	if hp == before:
		hp = after                      # pełne zdrowie zostaje pełne
	hp = mini(hp, stack_hp())

func max_hp() -> int:
	return MAX_HP + int(perk_param("veteran", "extra_hearts", 0.0))

func stack_hp() -> int:
	return STACK_HP + int(perk_param("veteran", "extra_hearts", 0.0))

## Granice kamery z mapy (level.gd) zamiast stałych z player.tscn.
func _apply_level_bounds() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null and _camera != null:
		var b: Rect2 = lvl.bounds
		_camera.limit_left = int(b.position.x)
		_camera.limit_top = int(b.position.y)
		_camera.limit_right = int(b.end.x)
		_camera.limit_bottom = int(b.end.y)

## Nowa mapa (level.load_map): punkt startu i granice kamery z nowej mapy, postać wraca na start.
func _on_map_changed(_id: String) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	_spawn_point = lvl.spawn_for(display_id)
	global_position = _spawn_point
	velocity = Vector2.ZERO
	_apply_level_bounds()

## Rysowanie odświeżamy na każdym peerze (zdalni gracze też zmieniają celowanie,
## kucanie i HP), a kamera dostaje lokalny shake.
func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_scream_ring = maxf(0.0, _scream_ring - delta)
	if _camera.enabled:
		_camera.offset = Feel.shake_offset()
	if _is_remote or is_bot:
		_update_footsteps_passive()
	_update_lights()
	_update_squash(delta)
	_update_facing()
	_update_sprite()
	if view != null:
		view.update(delta, _tint_color(), _facing, squash.y)
	queue_redraw()
	_overlay.queue_redraw()

## Węzeł na efekty: poziom (NIE „Players" — main.gd traktuje każde dziecko
## Players jako gracza, a cząsteczki i łuski tam psuły wipe/restart).
func _fx_root() -> Node:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl if lvl != null else get_tree().current_scene

## Pył w powietrzu wokół kadru — cieniowany, więc widać go tylko w świetle
## (snop latarki „ma objętość"). Emitowany w świecie, nie w kadrze.
func _dust_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(230, 140)
	p.direction = Vector2(1, -0.2)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector2(0.6, 1.2)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = Color(0.8, 0.78, 0.7, 0.55)
	return p

## Popychanie skrzyń/beczek: CharacterBody2D sam nie pcha ciał fizycznych.
func _push_props(_delta: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var b := col.get_collider()
		if b != null and b.is_in_group("props") and absf(col.get_normal().x) > 0.6:
			b.push(-signf(col.get_normal().x))

## Nazwa powierzchni pod stopami (kafel), np. "dirt", "water", "oil".
func _floor_surface() -> String:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl.surface_at(global_position) if lvl != null else "dirt"

func _in_water() -> bool:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl != null and lvl.surface_at(global_position) == "water"

## Rozciąganie/przysiad i efekty ruchu (kurz, rozbryzgi) z prędkości — na
## każdym peerze, bez dodatkowej synchronizacji.
func _update_squash(delta: float) -> void:
	var vy := velocity.y
	var parent := _fx_root()
	if not dead:
		if _prev_vy > 140.0 and absf(vy) < 30.0:
			# lądowanie: przysiad tym głębszy, im szybciej spadał
			var k := clampf((_prev_vy - 140.0) / 420.0, 0.0, 1.0)
			squash = Vector2(1.0 + 0.35 * k + 0.1, 1.0 - 0.3 * k - 0.08)
			if _in_water():
				Vfx.splash(parent, global_position, 0.6 + k)
			else:
				Vfx.dust(parent, global_position, 0.5 + k)
		elif vy < -180.0 and _prev_vy > -60.0:
			squash = Vector2(0.78, 1.22)          # wybicie
			Vfx.dust(parent, global_position, 0.35)
		# brodzenie: drobne rozbryzgi przy biegu w wodzie
		_splash_t -= delta
		if absf(velocity.x) > 30.0 and absf(vy) < 5.0 and _splash_t <= 0.0 and _in_water():
			_splash_t = 0.22
			Vfx.splash(parent, global_position + Vector2(-signf(velocity.x) * 4.0, 0), 0.25)
	_prev_vy = vy
	squash = squash.lerp(Vector2.ONE, minf(1.0, delta * 12.0))

func _update_lights() -> void:
	var fl := Lights.flicker_mult()
	_aura.enabled = not dead
	_aura.energy = Lights.AURA_ENERGY * (1.0 if not crouching else 0.75) * fl
	_beam.enabled = flashlight and not dead
	if _beam.enabled:
		_beam.rotation = aim_dir.angle()
		# lekkie drżenie snopu — latarka w ręku, nie reflektor
		_beam.energy = (0.85 + 0.04 * sin(Time.get_ticks_msec() * 0.023)) * fl

## Latarka: bateria, hałas „+1 Uwagi co 10 s" (GDD §6.6). Tylko właściciel.
func _update_flashlight(delta: float) -> void:
	if flashlight and not dead:
		battery = maxf(0.0, battery - delta)
		_light_noise_t += delta
		if _light_noise_t >= LIGHT_NOISE_EVERY:
			_light_noise_t = 0.0
			NoiseMgr.add_noise(1.0, global_position)
		if battery <= 0.0:
			flashlight = false
			if not is_bot:
				Audio.play("dry_fire", Audio.BUS_UI, -10.0, 0.6)
	else:
		battery = minf(BATTERY_MAX, battery + delta * BATTERY_RECHARGE)

func _toggle_flashlight() -> void:
	if not flashlight and battery < 1.0:
		Audio.play("ui_deny", Audio.BUS_UI, -10.0)
		return
	flashlight = not flashlight
	_light_noise_t = 0.0
	Audio.play("ui_click", Audio.BUS_PLAYER, -10.0, 0.7 if flashlight else 0.55)

## Zdalni gracze: pozycję interpoluje synchronizator, więc nie ruszamy tu nic.
func _physics_process(delta: float) -> void:
	if _is_remote:
		return

	_invuln = maxf(0.0, _invuln - delta)
	_ff_cd = maxf(0.0, _ff_cd - delta)

	_update_flashlight(delta)
	if dead:
		_down_physics(delta)
		return
	if grabbed:
		global_position = grab_pos          # trzyma go Pijawka: pozycja jest narzucona (gracz mógłby się uwolnić tylko przez obrażenia bossa)
		velocity = Vector2.ZERO
		_run_vx = 0.0
		_kick = 0.0

	if is_bot:
		weapons.tick_bot(delta)
		_bot_brain(delta)
		return

	_local_brain(delta)

# ---------------------------------------------------------------- local input

func _local_brain(delta: float) -> void:
	var reviving := _handle_revive(delta, Input.is_action_pressed("interact"))
	var gear_busy := _gear_tick(delta)
	var busy := reviving or pumping or gear_busy
	weapons.tick_local(delta, busy)

	var move_x := 0.0 if (busy or grabbed) else Input.get_axis("move_left", "move_right")
	var aim_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	crouching = Input.is_action_pressed("crouch") and is_on_floor()

	if aim_input != Vector2.ZERO:
		# klawiatura/pad: 8 kierunków (klasyka Contry)
		aim_dir = _snap8(aim_input)
		aim_by_mouse = false
	elif Input.get_last_mouse_velocity().length() > 20.0:
		# mysz: celowanie swobodne — snap do 8 kierunków czuje się dziwnie
		var to_mouse := get_global_mouse_position() - (global_position + Vector2(0, -9))
		if to_mouse.length() > 6.0:
			aim_dir = to_mouse.normalized()
			aim_by_mouse = true

	# powierzchnia pod stopami (surfaces.gd): bagno i błoto spowalniają, olej i lód ślizgają
	var surf: Dictionary = Surfaces.of(_floor_surface()) if is_on_floor() else Surfaces.of("dirt")
	var speed := (CROUCH_SPEED if crouching else SPEED) * float(surf["speed"])
	_kick = move_toward(_kick, 0.0, KICK_DECAY * delta)
	var target := move_x * speed
	var rate := AIR_ACCEL
	if is_on_floor():
		if absf(target) < 0.01:
			rate = DECEL * float(surf["decel"])
		elif signf(target) != signf(_run_vx) and absf(_run_vx) > 1.0:
			rate = TURN_ACCEL * float(surf["turn"])
		else:
			rate = ACCEL * float(surf["accel"])
	_run_vx = move_toward(_run_vx, target, rate * delta)
	velocity.x = _run_vx + _kick

	# --- skok: coyote time + jump buffer + zmienna wysokość (GDD §23)
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	_update_drop(delta, on_floor)

	if not on_floor:
		var g := GRAVITY * (FALL_MULT if velocity.y > 0.0 else 1.0)
		velocity.y = minf(velocity.y + g * delta, MAX_FALL)

	if _jump_buf > 0.0 and _coyote > 0.0 and not crouching and not busy and not grabbed:
		velocity.y = JUMP_VELOCITY * float(surf["jump"])
		_jump_buf = 0.0
		_coyote = 0.0
		Audio.play_variant("effort", 2, Audio.BUS_PLAYER, -20.0)

	# puszczenie skoku w górze lotu skraca go
	if Input.is_action_just_released("jump") and velocity.y < JUMP_VELOCITY * JUMP_CUT:
		velocity.y = JUMP_VELOCITY * JUMP_CUT

	if not _was_on_floor and is_on_floor():
		NoiseMgr.mark_local_activity()
		# Twarde lądowanie — tym głośniejsze, im większy spadek, bo GDD §8.1
		# traktuje lądowanie jako aktywność podnoszącą Uwagę.
		var drop := _air_time_accum
		if drop > 0.25:
			Audio.play_at("land_hard", global_position, Audio.BUS_PLAYER,
				lerpf(-24.0, -8.0, clampf(drop / 1.2, 0.0, 1.0)))
			Feel.shake(clampf(drop * 2.0, 0.0, 2.0))
		_air_time_accum = 0.0
	elif not is_on_floor():
		_air_time_accum += delta
	_was_on_floor = is_on_floor()

	move_and_slide()
	_push_props(delta)
	_update_footsteps()
	_update_breath()

	# bieganie = hałas (GDD §8.1: 0,5/s — jedna wartość, solo i sieć)
	if absf(velocity.x) > 5.0 and is_on_floor() and not crouching:
		_run_noise_tick += delta
		if _run_noise_tick >= 0.5:
			_run_noise_tick = 0.0
			NoiseMgr.add_noise(NoiseMgr.N_RUN_PER_SEC * 0.5 * float(surf["noise"]) * perk_param("quiet_steps", "run_noise_mult", 1.0), global_position)

	if Input.is_action_just_pressed("overcharge"):
		_try_overcharge()
	if Input.is_action_just_pressed("scream"):
		Voice.try_scream(self)
	if Input.is_action_just_pressed("flare"):
		_throw_flare()

	if Input.is_action_just_pressed("flashlight"):
		_toggle_flashlight()

## Zeskok z kładki: dół + skok, stojąc na kładce. Na chwilę wyłączamy
## kolizję z warstwą kładek; skok jest wtedy „zjedzony".
func _update_drop(delta: float, on_floor: bool) -> void:
	if _tick_drop(delta):
		return
	if _jump_buf <= 0.0 or not on_floor or not Input.is_action_pressed("move_down"):
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.is_platform_at(global_position):
		return
	_jump_buf = 0.0
	_start_drop()

func _start_drop() -> void:
	if _drop_t > 0.0:
		return
	_drop_t = DROP_TIME
	set_collision_mask_value(PLATFORM_LAYER_BIT, false)
	position.y += 1.0

## Zwraca true, dopóki trwa zeskok.
func _tick_drop(delta: float) -> bool:
	if _drop_t <= 0.0:
		return false
	_drop_t -= delta
	if _drop_t <= 0.0:
		set_collision_mask_value(PLATFORM_LAYER_BIT, true)
	return true

## Flara (F): rzut łukiem w stronę celowania; pulę i spawn rozstrzyga serwer (NoiseMgr.request_flare).
func _throw_flare() -> void:
	if dead or is_bot:
		return
	var origin := global_position + Vector2(aim_dir.x * 6.0, -12.0)
	var vel := aim_dir.normalized() * 190.0 + Vector2(velocity.x * 0.5, -70.0)
	NoiseMgr.request_flare(origin, vel)

# ---------------------------------------------------------------- ekwipunek zużywalny (lewy Alt / X)

## Skaner „Sowa”: ile sekund jeszcze działa (lokalny gracz); nakładkę rysuje scanner_view.gd.
var scan_left := 0.0
## Tekst i postęp środkowego paska HUD dla narzędzi (apteczka, defibrylator) — tylko lokalny człowiek.
var gear_text := ""
var gear_progress := 0.0
var _med_hold := 0.0
var _med_hp := 0
var _defib_hold := 0.0
var _defib_ref: Node2D = null
var _scan_noise_t := 0.0
var _scan_view: Node2D = null

## Co klatkę (lokalny człowiek): X zmienia wybór, T używa wybranego przedmiotu. Zwraca true, gdy postać jest „zajęta”
## (apteczka i defibrylator wymagają stania w miejscu i nie strzelania, jak podnoszenie).
func _gear_tick(delta: float) -> bool:
	gear_text = ""
	gear_progress = 0.0
	if scan_left > 0.0:
		scan_left = maxf(0.0, scan_left - delta)
		_scan_noise_t += delta
		if _scan_noise_t >= 1.0:
			_scan_noise_t = 0.0
			NoiseMgr.add_noise(float(Throwables.KINDS["scanner"]["noise"]), global_position)     # skaner emituje hałas 1/s
	if dead or is_bot:
		_gear_cancel()
		return false
	if Input.is_action_just_pressed("throw_next"):
		Arsenal.cycle_throwable()
		Audio.play("ui_click", Audio.BUS_UI, -12.0, 1.1)
	var kind := Arsenal.selected_throwable()
	match Throwables.mode_of(kind):
		"throw", "place":
			_gear_cancel()
			if Input.is_action_just_pressed("throw"):
				_throw_item(kind)
			return false
		"use":
			match kind:
				"medkit":
					return _tick_medkit(delta, Input.is_action_pressed("throw"))
				"defib":
					return _tick_defib(delta, Input.is_action_pressed("throw"))
				"scanner":
					_gear_cancel()
					if Input.is_action_just_pressed("throw"):
						_start_scan()
					elif scan_left <= 0.0 and Arsenal.get_throwable("scanner") > 0:
						gear_text = "[%s]  Owl scanner — %d s, shows enemies through walls (emits noise)" % [Throwables.key_name(), int(Throwables.KINDS["scanner"]["time"])]
	return false

func _gear_cancel() -> void:
	if _med_hold > 0.0:
		_med_hold = 0.0
	if _defib_hold > 0.0 or _defib_ref != null:
		_defib_hold = 0.0
		if _defib_ref != null and is_instance_valid(_defib_ref):
			_defib_ref.set_revive_progress(0.0)
		_defib_ref = null

## Rzut / postawienie (lewy Alt): wybrany rodzaj (X). Brak zapasu = suchy klik.
func _throw_item(kind: String) -> void:
	if Arsenal.get_throwable(kind) <= 0:
		Audio.play("dry_fire", Audio.BUS_WEAPONS, -10.0, 1.2)
		return
	var origin := global_position + Vector2(aim_dir.x * 6.0, -12.0)
	var vel := (aim_dir.normalized() * 230.0 + Vector2(velocity.x * 0.5, -90.0)) * perk_param("wide_arm", "throw_mult", 1.0)
	if Throwables.mode_of(kind) == "place":
		origin = global_position + Vector2(0, -6.0)
		vel = aim_dir.normalized()                 # mina: kierunek stożka = celowanie; ładunek ignoruje
	Audio.play_variant("foley_gear", 3, Audio.BUS_PLAYER, -10.0, 0.8)
	Arsenal.request_throw(kind, origin, vel)

## Najbliższy ranny towarzysz w zasięgu apteczki (z lewej/prawej), a gdy nikogo — ja sam, jeśli jestem ranny.
func _medkit_target() -> Node2D:
	var best: Node2D = null
	var best_d := float(Throwables.KINDS["medkit"]["range"])
	for q in get_tree().get_nodes_in_group("players"):
		var pp := q as Node2D
		if pp == null or pp == self or pp.dead or pp.hp >= pp.max_hp():
			continue
		if absf(pp.global_position.y - global_position.y) > 30.0:
			continue
		var dx := absf(pp.global_position.x - global_position.x)
		if dx < best_d:
			best_d = dx
			best = pp
	if best == null and hp < max_hp():
		return self
	return best

func _tick_medkit(delta: float, held: bool) -> bool:
	var data: Dictionary = Throwables.KINDS["medkit"]
	var t := _medkit_target()
	if Arsenal.get_throwable("medkit") <= 0 or t == null:
		_med_hold = 0.0
		return false
	var who := "yourself" if t == self else ("the bot" if t.is_bot else "P%d" % t.display_id)
	if not held:
		_med_hold = 0.0
		gear_text = "Hold [%s]  Use the medkit on %s  (%d s)" % [Throwables.key_name(), who, int(data["time"])]
		return false
	if _med_hold <= 0.0:
		_med_hp = hp
	elif hp < _med_hp:
		_med_hold = 0.0                         # oberwał w trakcie — przerwane
		return false
	_med_hold += delta
	gear_text = "Healing %s…" % who
	gear_progress = clampf(_med_hold / float(data["time"]), 0.0, 1.0)
	if _med_hold >= float(data["time"]):
		_med_hold = 0.0
		Arsenal.request_use("medkit", int(t.player_id))
	return true

## Najbliższy leżący towarzysz w zasięgu defibrylatora i w linii wzroku.
func _defib_target() -> Node2D:
	var best: Node2D = null
	var best_d := float(Throwables.KINDS["defib"]["range"])
	var space := get_world_2d().direct_space_state
	for q in get_tree().get_nodes_in_group("players"):
		var pp := q as Node2D
		if pp == null or pp == self or not pp.dead:
			continue
		var d := pp.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		var ray := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -9), pp.global_position + Vector2(0, -6), 1)
		if not space.intersect_ray(ray).is_empty():
			continue
		best_d = d
		best = pp
	return best

func _tick_defib(delta: float, held: bool) -> bool:
	var data: Dictionary = Throwables.KINDS["defib"]
	var t := _defib_target()
	if Arsenal.get_throwable("defib") <= 0 or t == null:
		_gear_cancel()
		return false
	var who := "the bot" if t.is_bot else "P%d" % t.display_id
	if not held:
		_gear_cancel()
		gear_text = "Hold [%s]  Defibrillate %s  (%d m away)" % [Throwables.key_name(), who, int(t.global_position.distance_to(global_position) / 16.0)]
		return false
	if t != _defib_ref:
		if _defib_ref != null and is_instance_valid(_defib_ref):
			_defib_ref.set_revive_progress(0.0)
		_defib_ref = t
		_defib_hold = 0.0
	_defib_hold += delta
	gear_text = "Defibrillating %s…" % who
	gear_progress = clampf(_defib_hold / float(data["time"]), 0.0, 1.0)
	t.set_revive_progress(gear_progress)
	if _defib_hold >= float(data["time"]):
		_defib_hold = 0.0
		t.set_revive_progress(0.0)
		_defib_ref = null
		Arsenal.request_use("defib", int(t.player_id))
	return true

func _start_scan() -> void:
	if scan_left > 0.0 or Arsenal.get_throwable("scanner") <= 0:
		return
	Arsenal.request_use("scanner", 0)
	scan_left = float(Throwables.KINDS["scanner"]["time"])
	_scan_noise_t = 0.0
	Audio.play("ui_click", Audio.BUS_UI, -6.0, 0.7)
	if _scan_view == null:
		_scan_view = (load("res://scripts/scanner_view.gd") as GDScript).new()
		_scan_view.player = self
		add_child(_scan_view)

## Krzyk (mikrofon albo G, voice.gd): hałas + przyciągnięcie wrogów; efekt widzą wszyscy.
func do_scream(amount: float) -> void:
	if dead or is_bot or not is_multiplayer_authority():
		return
	NoiseMgr.add_scream(amount, global_position)
	if NoiseMgr.has_network():
		_scream_fx.rpc()
	else:
		_scream_fx()

var _scream_ring := 0.0

@rpc("authority", "call_local", "reliable")
func _scream_fx() -> void:
	_scream_ring = 0.6
	Audio.play_variant_at("player_hurt", 2, global_position, Audio.BUS_WORLD, 1.0, 0.8)
	if is_multiplayer_authority():
		Feel.shake(1.8)

func _try_overcharge() -> void:
	# Dźwięk od razu, niezależnie od tego czy ładunek się uda — klik ma potwierdzać
	# akcję, a nie rozstrzygać (rozstrzyga use_overcharge).
	Audio.play("oc_load", Audio.BUS_UI, -10.0)
	var pos := global_position
	if not NoiseMgr.has_network():
		NoiseMgr.use_overcharge(pos)
	elif multiplayer.is_server():
		NoiseMgr.use_overcharge(pos)
	else:
		_noise_manager_request.rpc_id(1, pos)

@rpc("any_peer", "call_remote", "reliable")
func _noise_manager_request(pos: Vector2) -> void:
	if multiplayer.is_server():
		NoiseMgr.use_overcharge(pos)

# ---------------------------------------------------------------- down / revive

## Leżący gracz: wykrwawia się, spada na ziemię i czeka na pomoc.
func _down_physics(delta: float) -> void:
	bleed_left = maxf(0.0, bleed_left - delta)
	_down_t += delta
	if not _second_used and has_perk("second_chance") and bleed_left > 0.0 \
			and _down_t >= minf(perk_param("second_chance", "self_revive_after", 8.0), bleed_time() * SECOND_CHANCE_FRAC):
		_second_used = true
		_do_revive()
		hp = 1                          # wstaje na jednym sercu (REVIVE_HP daje dwa)
		return
	velocity.x = 0.0
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	move_and_slide()
	_revive_hold = 0.0
	if bleed_left <= 0.0:
		# kara dystansem i czasem, nie ekranem „game over" (GDD §4)
		_respawn(1)

func bleed_time() -> float:
	return BLEED_TIME * Difficulty.m("bleed")

func _revive_time() -> float:
	return perk_param("blood_flow", "revive_time", REVIVE_TIME) * Difficulty.m("revive")

func _go_down() -> void:
	grabbed = false
	hp = 0
	dead = true
	bleed_left = bleed_time()
	_down_t = 0.0
	velocity = Vector2.ZERO
	crouching = false
	weapons.on_down()
	Audio.play("player_down", Audio.BUS_PLAYER, -5.0)
	if _breath_on:
		_breath_on = false
		Audio.stop_loop("breath_loop")

## Najbliższy leżący towarzysz w zasięgu podnoszenia (poza sobą).
func _revive_target() -> Node2D:
	var best: Node2D = null
	var best_d := REVIVE_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp == self or not pp.dead:
			continue
		var dx := absf(pp.global_position.x - global_position.x)
		var dy := absf(pp.global_position.y - global_position.y)
		if dy > 30.0:
			continue
		if dx < best_d:
			best_d = dx
			best = pp
	return best

## Trzymanie przycisku przy leżącym koledze. Zwraca true, gdy postać jest
## „zajęta" podnoszeniem (stoi w miejscu i nie strzela).
func _handle_revive(delta: float, holding: bool) -> bool:
	var t: Node2D = _revive_target() if holding else null
	if t != _revive_target_ref:
		if _revive_target_ref != null and is_instance_valid(_revive_target_ref):
			_revive_target_ref.set_revive_progress(0.0)
		_revive_hold = 0.0
		_revive_target_ref = t
	if t == null:
		return false
	_revive_hold += delta
	t.set_revive_progress(clampf(_revive_hold / _revive_time(), 0.0, 1.0))
	if _revive_hold >= _revive_time():
		_revive_hold = 0.0
		t.set_revive_progress(0.0)
		t.request_revive()
		_revive_target_ref = null
		if not is_bot and is_multiplayer_authority():
			Profile.add_xp(Profile.XP_REVIVE, "Revive")           # XP za podniesienie kolegi (lokalny profil podnoszącego)
	return true

## Postęp liczy podnoszący, ale widzieć go musi też leżący (i reszta drużyny),
## więc rozsyłamy go do wszystkich peerów (10 Hz, zero zawsze od razu).
func set_revive_progress(v: float) -> void:
	if is_equal_approx(v, revive_progress):
		return
	revive_progress = v
	if not NoiseMgr.has_network():
		return
	var now := Time.get_ticks_msec()
	if v <= 0.0 or now - _revive_sent_ms >= REVIVE_SYNC_MS:
		_revive_sent_ms = now
		_revive_progress_rpc.rpc(v)

@rpc("any_peer", "call_remote", "reliable")
func _revive_progress_rpc(v: float) -> void:
	revive_progress = v

## Podpowiedź dla HUD (tylko lokalny człowiek).
func revive_hint() -> String:
	if dead:
		return ""
	var t := _revive_target()
	if t == null:
		return ""
	return "Hold [E] to revive %s" % ("the bot" if t.is_bot else "P%d" % t.display_id)

## Prośba o podniesienie — rozstrzyga właściciel leżącej postaci.
func request_revive() -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		_do_revive()
	else:
		_revive_rpc.rpc_id(get_multiplayer_authority())

@rpc("any_peer", "call_remote", "reliable")
func _revive_rpc() -> void:
	if is_multiplayer_authority():
		_do_revive()

func _do_revive() -> void:
	if not dead:
		return
	dead = false
	hp = REVIVE_HP
	bleed_left = 0.0
	revive_progress = 0.0
	_invuln = 1.2
	Audio.play("revive", Audio.BUS_PLAYER, -9.0)
	if not is_bot:
		Feel.shake(1.5)

func _respawn(hp_amount: int) -> void:
	dead = false
	hp = hp_amount
	bleed_left = 0.0
	revive_progress = 0.0
	global_position = _spawn_point
	velocity = Vector2.ZERO
	_invuln = 1.5
	weapons.on_down()
	weapons.cool()
	_run_vx = 0.0
	_last_step_pos = global_position
	_step_dist = 0.0
	Audio.play("revive", Audio.BUS_PLAYER, -9.0)

## Restart po wipe (wszyscy leżą): pełne zdrowie w punkcie startu.
func full_reset(keep_loadout := false) -> void:
	_second_used = false            # „Second chance" — raz na misję
	_respawn(max_hp())
	if not keep_loadout:
		weapons.reset()            # przejście między misjami kampanii (kryjówka) zachowuje ekwipunek
	_kick = 0.0
	_revive_hold = 0.0
	_revive_target_ref = null

## Wołane przez serwer po wipe — reset wykonuje właściciel postaci, bo tylko on
## ma autorytet nad jej pozycją i HP (synchronizator by to nadpisał).
func request_full_reset(keep_loadout := false) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		full_reset(keep_loadout)
	else:
		_full_reset_rpc.rpc_id(get_multiplayer_authority(), keep_loadout)

## „any_peer", bo woła serwer na postaci należącej do klienta; przyjmujemy
## tylko od serwera.
@rpc("any_peer", "call_remote", "reliable")
func _full_reset_rpc(keep_loadout: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		full_reset(keep_loadout)

# ---------------------------------------------------------------- audio

## Kroki: krok co ~22 px drogi. Przy kucaniu dłuższy interwał, bo chód
## kucając jest ciszej i wolniejszy (GDD §8.1: kucanie = 0 hałasu).
func _update_footsteps() -> void:
	if not is_on_floor() or dead:
		return
	var moved := global_position - _last_step_pos
	_last_step_pos = global_position
	if moved.length() < 0.5:
		return
	_step_dist += moved.length()
	var stride := 34.0 if crouching else 22.0
	if _step_dist >= stride:
		_step_dist = 0.0
		Audio.play_footstep(global_position, crouching)


## Kroki CUDZYCH postaci (zdalni gracze, bot). Wcześniej kroki grała tylko
## własna postać — kolegi i bota nie było słychać wcale, a w co-op horrorze
## kroki drużyny to informacja „gdzie jest reszta". is_on_floor() nie działa
## dla pozycji z synchronizatora, więc ziemię rozpoznajemy po braku ruchu
## w pionie. Ciszej niż własne, i pozycyjnie (okluzja przez ściany).
func _update_footsteps_passive() -> void:
	var moved := global_position - _last_step_pos
	_last_step_pos = global_position
	# w powietrzu, leży albo teleport (respawn/wipe) — bez kroku
	if dead or absf(moved.y) > 0.6 or moved.length() > 40.0:
		_step_dist = 0.0
		return
	_step_dist += absf(moved.x)
	var stride := 34.0 if crouching else 22.0
	if _step_dist >= stride:
		_step_dist = 0.0
		Audio.play_footstep(global_position, crouching, -13.0)

## Oddech: ciągły przy wysiłku (skradanie w napięciu, bieg) i cisza gdy stoisz.
func _update_breath() -> void:
	var exertion := 0.0
	if crouching:
		exertion = 0.55
	if absf(velocity.x) > 5.0 and is_on_floor() and not crouching:
		exertion = 1.0
	var want := exertion > 0.0
	if want and not _breath_on:
		_breath_on = true
		Audio.start_loop("breath_loop", Audio.BUS_PLAYER, -32.0)
	elif want and Audio.loop_playing("breath_loop"):
		Audio.set_loop_volume("breath_loop", lerpf(-38.0, -26.0, exertion))
	elif not want and _breath_on:
		_breath_on = false
		Audio.stop_loop("breath_loop")

# ---------------------------------------------------------------- bot AI

const LEADER_SWITCH := 60.0

var _bot_target_pos := Vector2.ZERO
## Ścieżka A* (nav.gd): lista kroków {pos, kind, id}; _bot_path_i = następny krok.
var _bot_path: Array = []
var _bot_path_i := 0
var _bot_stuck := 0.0
var _bot_prev_x := 0.0
var _bot_leader: Node2D = null
var _bot_wants_jump := false
var _bot_repath := 0.0
var _bot_car_lag := 0.0

## Zasilona drezyna z człowiekiem w pobliżu: boty wsiadają i jadą z drużyną (null = zwykłe podążanie za dowódcą).
func _bot_car() -> Node2D:
	for c in get_tree().get_nodes_in_group("handcar"):
		if c.wants_riders():
			return c
	return null

## Unik przed kwasem Pijawki (acid_spit.gd): nadlatujący pocisk w pobliżu → bot odskakuje w przeciwną stronę i skacze.
func _bot_dodge_acid() -> void:
	for a in get_tree().get_nodes_in_group("acid"):
		var d := (a as Node2D).global_position - (global_position + Vector2(0, -9))
		var incoming: bool = d.length() < 80.0 and signf(a.vel.x) == signf(-d.x)
		if incoming or d.length() < 28.0:
			velocity.x = -signf(d.x if absf(d.x) > 1.0 else 1.0) * SPEED
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
			return

var _bot_gear_hold := 0.0
var _bot_gear_kind := ""
var _bot_gear_target := 0

## Bot używa zapasu drużyny: defibrylatorem stawia leżącego CZŁOWIEKA w zasięgu 10 m i linii wzroku (1,5 s), a gdy nikt nie jest
## zagrożony — apteczką leczy rannego człowieka obok (5 s), na końcu siebie. Stoi w miejscu na czas użycia. Zwraca true, gdy zajęty.
func _bot_gear(delta: float, downed: Node2D) -> bool:
	if not NoiseMgr.is_server() or dead:
		_bot_gear_hold = 0.0
		return false
	var kind := ""
	var target: Node2D = null
	var space := get_world_2d().direct_space_state
	if downed != null and not downed.is_bot and Arsenal.get_throwable("defib") > 0:
		var dd := downed.global_position.distance_to(global_position)
		var ray := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -9), downed.global_position + Vector2(0, -6), 1)
		if dd <= float(Throwables.KINDS["defib"]["range"]) and space.intersect_ray(ray).is_empty():
			kind = "defib"
			target = downed
	if kind == "" and Arsenal.get_throwable("medkit") > 0 and _nearest_enemy(150.0) == null:
		var best_d := float(Throwables.KINDS["medkit"]["range"])
		for q in get_tree().get_nodes_in_group("players"):
			var pp := q as Node2D
			if pp == null or pp == self or pp.dead or pp.is_bot or pp.hp >= pp.max_hp():
				continue
			var dx := absf(pp.global_position.x - global_position.x)
			if dx < best_d and absf(pp.global_position.y - global_position.y) < 30.0:
				best_d = dx
				target = pp
		if target == null and hp < max_hp():
			target = self
		if target != null:
			kind = "medkit"
	if kind == "":
		_bot_gear_hold = 0.0
		return false
	if kind != _bot_gear_kind or int(target.player_id) != _bot_gear_target:
		_bot_gear_kind = kind
		_bot_gear_target = int(target.player_id)
		_bot_gear_hold = 0.0
	_bot_gear_hold += delta
	if _bot_gear_hold >= float(Throwables.KINDS[kind]["time"]):
		_bot_gear_hold = 0.0
		Arsenal.use_as(kind, int(target.player_id), int(player_id))
	return true

func _bot_brain(delta: float) -> void:
	_tick_drop(delta)
	_bot_repath -= delta
	var car := _bot_car()
	var on_deck: bool = car != null and car.aboard(self)
	# drezyna jedzie szybciej niż bot chodzi — zostawiony w tyle ląduje na pokładzie (nie zostaje sam w tunelu)
	if car != null and not on_deck and car.speed > 20.0 and absf(car.global_position.x - global_position.x) > BOT_CAR_LAG:
		_bot_car_lag += delta
		if _bot_car_lag > BOT_CAR_LAG_T:
			_bot_car_lag = 0.0
			global_position = Vector2(car.slot_x(display_id), car.global_position.y - 1.0)
			velocity = Vector2.ZERO
			on_deck = true
	else:
		_bot_car_lag = 0.0
	# trasę liczymy tylko z ziemi — w locie najbliższy węzeł jest „pod nami"
	if _bot_repath <= 0.0 and is_on_floor():
		_bot_repath = 0.4
		_pick_bot_goal()
		_bot_plan()

	# podnoszenie leżącego towarzysza — bot nie jest szybszy od człowieka (GDD §4)
	var downed := _downed_teammate()
	var near_downed := downed != null \
		and absf(downed.global_position.x - global_position.x) < REVIVE_RANGE - 6.0 \
		and absf(downed.global_position.y - global_position.y) < 30.0
	var reviving := _handle_revive(delta, near_downed)
	reviving = _bot_gear(delta, downed) or reviving
	_bot_dodge_acid()

	# ruch w stronę celu (poziomo), skok przy przeszkodzie lub celu wyżej
	# bot naśladuje skradanie dowódcy — inaczej drużyna nie może grać cicho
	var leader := _leader()
	var stealth: bool = leader != null and not leader.dead and leader.crouching
	crouching = stealth and is_on_floor()
	# latarka jak u dowódcy — bot nie świeci sam (światło = hałas, §8.3)
	flashlight = leader != null and leader.flashlight and not crouching and battery > 1.0

	# Ruch po ścieżce A*; bez grafu — po staremu (prosto do celu + skok przy ścianie).
	# Na pokładzie drezyny: stoi w swoim slocie (albo przy leżącym koledze z pokładu) — bez A*, bez uników
	# i skoków, które zrzuciłyby go z jadącej platformy; ruch drezyny załatwia handcar.gd.
	var has_path := not _bot_path.is_empty() and not on_deck
	var goal_x := _bot_target_pos.x
	if on_deck:
		goal_x = car.slot_x(display_id)
		if downed != null and car.aboard(downed):
			goal_x = downed.global_position.x
	elif has_path:
		goal_x = _bot_follow_path()
	var dx := goal_x - global_position.x
	var dy := _bot_target_pos.y - global_position.y
	var done := on_deck or _bot_path_i >= _bot_path.size()
	var dead_zone := 8.0 if done else 3.0
	if reviving or absf(dx) < dead_zone:
		velocity.x = 0.0
	else:
		var spd := SPEED if not is_on_floor() else (CROUCH_SPEED if crouching else SPEED * 0.85) * float(Surfaces.of(_floor_surface())["speed"])
		if car != null and is_on_floor():
			spd = SPEED * 0.5 if on_deck else SPEED       # dojście do drezyny biegiem, na pokładzie powoli
		velocity.x = signf(dx) * spd
	# unik: wróg w zasięgu ciosu albo w zapowiedzi → bot odskakuje (nie stoi, żeby oberwać)
	if not reviving and is_on_floor() and not on_deck:
		var close := _nearest_enemy(BOT_EVADE_RANGE)
		if close != null and (bool(close.get("winding")) or absf(close.global_position.x - global_position.x) < BOT_KITE_RANGE):
			var away := signf(global_position.x - close.global_position.x)
			velocity.x = (away if away != 0.0 else -_facing) * SPEED
			if is_on_wall():
				_bot_wants_jump = true
				crouching = false
	# skrzynia / beczka na drodze: przeskakujemy ją (graf A* nie zna rekwizytów)
	if is_on_floor() and not reviving and absf(velocity.x) > 0.0 and _prop_ahead(signf(velocity.x)):
		_bot_wants_jump = true
		crouching = false
	_bot_check_stuck(delta, done or reviving)
	# odrzut (np. od pocisku kolegi) działa też na bota
	_kick = move_toward(_kick, 0.0, KICK_DECAY * delta)
	velocity.x += _kick
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	elif _bot_wants_jump or (not has_path and not on_deck and not crouching and ((absf(dx) > 6.0 and is_on_wall()) or (dy < -24.0 and absf(dx) < 70.0))):
		velocity.y = JUMP_VELOCITY
	_bot_wants_jump = false
	move_and_slide()
	_push_props(delta)

	if reviving:
		return

	# celowanie w najbliższego aktywnego wroga (nigdy w śpiących — nie psuje ciszy)
	var enemy := _nearest_enemy(BOT_ENGAGE_RANGE)
	if enemy != null:
		var d := (enemy.global_position - global_position)
		if d.length() > 6.0:
			aim_dir = _snap8(d)
		var los := _los_state(enemy) if weapons.cd <= 0.0 else Los.WALL
		if los == Los.TEAMMATE and is_on_floor() and not crouching and not on_deck:
			# kolega na linii — podskok daje czystą linię nad nim
			_bot_wants_jump = true
		if weapons.cd <= 0.0 and _aim_ok(d) and _bot_may_fire(d) and los == Los.CLEAR:
			# Boty symulowane są tylko na serwerze; serwer gra też ich dźwięk i efekty.
			weapons.bot_fire(aim_dir)

## Dyscyplina ognia bota (filar 2). Strzał to hałas, a każdy nowy hałas
## przekierowuje stalkera — bot strzelający „bo widzi wroga" kasował Q drużyny
## i nie pozwalał Uwadze opaść. Z bliska broni się zawsze.
func _bot_may_fire(d: Vector2) -> bool:
	if d.length() <= BOT_SELF_DEFENSE:
		return true
	if crouching:
		return false
	return NoiseMgr.seconds_since_overcharge() >= BOT_Q_HOLD

enum Los { CLEAR, WALL, TEAMMATE }

## Linia strzału bota: ściana (strzał w nią to sam hałas) albo stojący kolega.
## Wcześniej promień widział tylko ściany (maska 1), więc bot strzelał
## w wroga przez plecy człowieka. Leżących kolegów pomijamy — pocisk i tak
## przez nich przelatuje (projectile.gd).
func _los_state(target: Node2D) -> int:
	var from := global_position + Vector2(0, -9)
	var to := target.global_position + Vector2(0, -6)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 2)
	var exclude: Array[RID] = [get_rid()]
	var space := get_world_2d().direct_space_state
	for _i in 4:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return Los.CLEAR
		var c: Object = hit["collider"]
		if c is Node and (c as Node).is_in_group("players"):
			if c.dead:
				exclude.append(hit["rid"])
				continue
			return Los.TEAMMATE
		return Los.WALL
	return Los.CLEAR

func _aim_ok(d: Vector2) -> bool:
	# strzela tylko gdy wróg jest mniej więcej na tej samej wysokości lub tuż obok
	return absf(d.y) < 60.0 or absf(d.x) < 40.0

## Nowa trasa A* do _bot_target_pos (krok 0 = miejsce, w którym stoimy).
func _bot_plan() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or lvl.nav == null:
		_bot_path = []
		return
	_bot_path = lvl.nav.find_path(global_position, _bot_target_pos)
	_bot_path_i = 1

func _cell_id(nav: AStar2D) -> int:
	return int(floor((global_position.y - 1.0) / 16.0)) * nav.cols + int(floor(global_position.x / 16.0))

## Zwraca docelowe x na tę klatkę i ustawia chęć skoku / zeskoku.
## Skok: najpierw dojście do punktu wybicia (poprzedni węzeł), w locie sterowanie
## do węzła docelowego. Zeskok: stanąć nad kładką i zeskoczyć.
func _bot_follow_path() -> float:
	if _bot_path_i >= _bot_path.size():
		return _bot_target_pos.x
	var lvl := get_tree().get_first_node_in_group("level")
	var on_floor := is_on_floor()
	if on_floor:
		var me := _cell_id(lvl.nav)
		# węzeł osiągnięty (także po przeskoczeniu kilku naraz)
		for i in range(_bot_path_i, mini(_bot_path_i + 4, _bot_path.size())):
			if _bot_path[i].id == me:
				_bot_path_i = i + 1
				break
		if _bot_path_i >= _bot_path.size():
			return _bot_target_pos.x
	var step: Dictionary = _bot_path[_bot_path_i]
	var prev: Dictionary = _bot_path[_bot_path_i - 1]
	if not on_floor:
		return step.pos.x
	match step.kind:
		Nav.Edge.JUMP:
			if absf(global_position.x - prev.pos.x) <= 4.0:
				_bot_wants_jump = true
				crouching = false
				return step.pos.x
			return prev.pos.x
		Nav.Edge.DROP:
			if absf(global_position.x - prev.pos.x) <= 4.0:
				_start_drop()
			return prev.pos.x
	return step.pos.x

## Czy tuż przed botem (kierunek dir) stoi rekwizyt fizyczny — skrzynia albo beczka.
## Skok (42 px) przekracza ich wysokość (14–15 px), także dwóch ułożonych na sobie.
func _prop_ahead(dir: float) -> bool:
	var col := KinematicCollision2D.new()
	if not test_move(global_transform, Vector2(dir * 6.0, 0.0), col):
		return false
	var c := col.get_collider() as Node
	return c != null and c.is_in_group("props")

## Zablokowany na ziemi (np. skok nie wyszedł) → nowa trasa i podskok.
func _bot_check_stuck(delta: float, idle: bool) -> void:
	if idle or not is_on_floor() or absf(global_position.x - _bot_prev_x) > 0.5:
		_bot_stuck = 0.0
		_bot_prev_x = global_position.x
		return
	_bot_stuck += delta
	if _bot_stuck > 0.8:
		_bot_stuck = 0.0
		_bot_plan()
		_bot_wants_jump = true

func _pick_bot_goal() -> void:
	var downed := _downed_teammate()
	# 0) drezyna: wsiąść i jechać z ludźmi (leżący przy drezynie i tak ma pierwszeństwo — bot go podniesie z pokładu)
	var car := _bot_car()
	if car != null and (downed == null or not (car.aboard(downed) or downed.global_position.distance_to(global_position) < 90.0)):
		_bot_target_pos = Vector2(car.slot_x(display_id), car.global_position.y)
		return
	# 1) leżący towarzysz do podniesienia
	if downed != null:
		_bot_target_pos = downed.global_position
		return
	# 2) ranny bot idzie po apteczkę (ludzie mają pierwszeństwo — jak w pickup.gd)
	if hp < max_hp():
		var kit := _nearest_medkit(BOT_MEDKIT_RANGE)
		if kit != null:
			_bot_target_pos = kit.global_position
			return
	var leader := _leader()
	if leader != null:
		# trzyma się za dowódcą; kilku botów ustawia się w różnych odstępach, a nie w jednym punkcie
		var side := 1.0 if display_id % 2 == 0 else -1.0
		# strzelnica w kryjówce (tarcze na wschód od linii „RANGE"): bot staje ZA strzelającym, nie w linii ognia
		var rl := get_tree().get_first_node_in_group("range_line")
		if NoiseMgr.safe_zone and rl != null and leader.global_position.x > rl.global_position.x - 70.0:
			_bot_target_pos = leader.global_position - Vector2(34.0 + float(display_id % 3) * 12.0, 0)
			return
		_bot_target_pos = leader.global_position + Vector2(side * (22.0 + float(display_id % 3) * 10.0), 0)
		return
	_bot_target_pos = _spawn_point

## Najbliższa apteczka na ziemi w zasięgu, o ile żaden ranny człowiek nie stoi przy niej.
func _nearest_medkit(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for h in get_tree().get_nodes_in_group("pickups"):
		if h.kind != "health" or h.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(h.global_position)
		if d >= best_d:
			continue
		var taken := false
		for p in get_tree().get_nodes_in_group("players"):
			if not p.is_bot and not p.dead and p.hp < p.max_hp() and p.global_position.distance_to(h.global_position) < 80.0:
				taken = true
		if not taken:
			best = h
			best_d = d
	return best

func _downed_teammate() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp == self or not pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	return best

## Dowódca bota = NAJBLIŻSZY stojący człowiek (dowolny peer). Wcześniej bot
## szedł zawsze za graczem z autorytetem lokalnym — na serwerze to host, więc
## przy 2 ludziach klient nie miał wsparcia, nawet stojąc obok bota.
## Histereza: zmiana dowódcy dopiero gdy inny jest bliżej o LEADER_SWITCH px,
## inaczej bot dygotałby między dwoma graczami w podobnej odległości.
func _leader() -> Node2D:
	var cur := _bot_leader if is_instance_valid(_bot_leader) and not _bot_leader.dead else null
	var cur_d := global_position.distance_to(cur.global_position) if cur != null else INF
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.is_bot or pp.dead:
			continue
		var d := global_position.distance_to(pp.global_position)
		if d < best_d:
			best_d = d
			best = pp
	if cur == null or (best != null and best_d < cur_d - LEADER_SWITCH):
		_bot_leader = best
	return _bot_leader if is_instance_valid(_bot_leader) else null

func _nearest_enemy(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		var ee := e as Node2D
		if ee == null or not ee.visible:
			continue
		# tylko realne zagrożenia: aktywni wrogowie (nie Stalker, nie śpiący)
		if not ee.has_method("is_threat") or not ee.is_threat():
			continue
		var d := global_position.distance_to(ee.global_position)
		if d < best_d:
			best_d = d
			best = ee
	return best

# ---------------------------------------------------------------- serwer

## Dostarcza obrażenia WŁAŚCICIELOWI postaci. apply_hit ma straż
## is_multiplayer_authority(), więc wywołanie go bezpośrednio na serwerze dla
## cudzej postaci kończyło się po cichu — gracze-klienci nie dostawali obrażeń
## od Stalkera ani od friendly fire. Wszystkie źródła obrażeń wołają tę metodę.
## Friendly fire bez obrażeń (projectile.gd): rozstrzyga właściciel postaci.
func deliver_ff(from_pos: Vector2) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_ff(from_pos)
	else:
		apply_ff.rpc_id(get_multiplayer_authority(), from_pos)

## Trafienie przez kolegę: odrzut, błysk i krzyk = HAŁAS (Uwaga), zero HP.
@rpc("any_peer", "call_remote", "reliable")
func apply_ff(from_pos: Vector2) -> void:
	if not is_multiplayer_authority() or dead:
		return
	_kick = signf(global_position.x - from_pos.x) * FF_KICK
	_flash = maxf(_flash, 0.12)
	if _ff_cd > 0.0:
		return
	_ff_cd = FF_COOLDOWN
	Audio.play_variant_at("player_hurt", 2, global_position, Audio.BUS_PLAYER, -12.0, 1.15)
	NoiseMgr.add_noise(NoiseMgr.N_FF, global_position)
	if not is_bot:
		Feel.shake(1.5)

## Leczenie (apteczka): rozstrzyga właściciel postaci — jak obrażenia.
func deliver_heal(amount: int) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_heal(amount)
	else:
		apply_heal.rpc_id(get_multiplayer_authority(), amount)

@rpc("any_peer", "call_remote", "reliable")
func apply_heal(amount: int) -> void:
	if not is_multiplayer_authority() or dead:
		return
	if NoiseMgr.has_network() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return          # tylko serwer (albo lokalnie) może leczyć
	hp = mini(stack_hp(), hp + amount)
	Vfx.burst(_fx_root(), global_position + Vector2(0, -10), Color(0.4, 1.0, 0.5), 10, 15.0, 45.0,
		Vector2.UP, 60.0, -30.0, 0.6, Vector2(1.0, 1.8), true)
	if not is_bot:
		Audio.play("revive", Audio.BUS_PLAYER, -6.0, 1.4)

func deliver_hit(amount: int, from_pos: Vector2) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_hit(amount, from_pos)
	else:
		apply_hit.rpc_id(get_multiplayer_authority(), amount, from_pos)

@rpc("any_peer", "call_remote", "reliable")
func apply_hit(amount: int, _from_pos: Vector2) -> void:
	if not is_multiplayer_authority() or dead or _invuln > 0.0:
		return
	hp -= amount
	_invuln = INVULN_AFTER_HIT
	_flash = 0.25
	Vfx.blood(_fx_root(), global_position + Vector2(0, -9), (global_position - _from_pos).normalized(), 8)
	Audio.play_variant("player_hurt", 2, Audio.BUS_PLAYER, -8.0)
	# krzyk bólu zawsze, w każdym trybie (wcześniej tylko solo)
	NoiseMgr.add_noise(NoiseMgr.N_HURT, global_position)
	if not is_bot:
		Feel.shake(4.0)
		Feel.hitstop(0.07)
		Audio.on_player_hurt(hp <= 1)
	if hp <= 0:
		_go_down()

## Chwyt Pijawki (serwer → właściciel postaci): `on` przypina gracza w `pos`, wyłączenie go uwalnia.
func deliver_grab(on: bool, pos: Vector2) -> void:
	if not NoiseMgr.has_network() or is_multiplayer_authority():
		apply_grab(on, pos)
	else:
		apply_grab.rpc_id(get_multiplayer_authority(), on, pos)

@rpc("any_peer", "call_remote", "reliable")
func apply_grab(on: bool, pos: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	grabbed = on and not dead
	grab_pos = pos
	if grabbed:
		velocity = Vector2.ZERO

## Odrzut broni popycha postać (px/s, wygasa KICK_DECAY).
func apply_recoil_kick(v: float) -> void:
	_kick = v

## Czy gracz nosi daną broń (zestaw replikowany w `kit`; sidearm P-64 ma każdy).
func carries(w: int) -> bool:
	return w == Weapons.P64 or w == kit.x or w == kit.y

func kit_primaries() -> Array:
	return [kit.x, kit.y]

func _snap8(v: Vector2) -> Vector2:
	if v == Vector2.ZERO:
		return aim_dir
	return Vector2.from_angle(snappedf(v.angle(), TAU / 8.0))

func _body_color() -> Color:
	if is_bot:
		return BOT_COLOR
	return BODY_COLORS[(display_id - 1) % BODY_COLORS.size()]

# ---------------------------------------------------------------- draw

func _draw() -> void:
	if not _spr.is_empty():
		if not dead:
			draw_rect(Rect2(-6, -1, 12, 2), Color(0, 0, 0, 0.35))
		return
	var col := _body_color()
	if _flash > 0.0:
		col = Color.WHITE

	if dead:
		draw_rect(Rect2(-7, -3, 14, 4), Color(0.35, 0.05, 0.08))
		return

	# migotanie podczas niewrażliwości po trafieniu
	if _invuln > 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0:
		col.a = 0.45

	var h := 11.0 if crouching else 17.0
	var top := -h
	draw_rect(Rect2(-7, -1, 14, 3), Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, squash)
	draw_rect(Rect2(-5, top + 7, 10, h - 7), col)
	draw_rect(Rect2(-4, top, 8, 8), col.lightened(0.3))
	var eye_off := Vector2(aim_dir.x * 2.5, clampf(aim_dir.y, -1.0, 0.35) * 2.0)
	draw_rect(Rect2(eye_off.x - 1.0, top + 3.0 + eye_off.y, 2, 2), Color(0.06, 0.06, 0.08))
	var arm_start := Vector2(0, top + 9)
	draw_line(arm_start, arm_start + aim_dir * _gun_len(), Color(0.78, 0.78, 0.85), 3.0 if weapons.cur().pellets > 1 else 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _gun_len() -> float:
	return weapons.cur().gun_len

## Rzeczy czytelne w ciemności (materiał unshaded): etykieta, HP, rozbłysk,
## stan „DOWN" i pasek podnoszenia. Teksty wyśrodkowane nad postacią.
func _draw_overlay(ov: Node2D) -> void:
	var font := ThemeDB.fallback_font
	if _scream_ring > 0.0:
		var k := 1.0 - _scream_ring / 0.6
		ov.draw_arc(Vector2(0, -12), 6.0 + k * 52.0, 0.0, TAU, 28, Color(1.0, 0.85, 0.5, (1.0 - k) * 0.7), 1.5)
	var col := _body_color()
	var name_txt := "BOT" if is_bot else "P%d" % display_id
	if dead:
		_center_text(ov, font, name_txt, -26.0, NAME_SIZE, col)
		_center_text(ov, font, "%ds" % ceili(bleed_left), -18.0, NAME_SIZE, Color(0.95, 0.4, 0.4))
		if revive_progress > 0.0:
			ov.draw_rect(Rect2(-12, -12, 24, 3), Color(0.1, 0.1, 0.12))
			ov.draw_rect(Rect2(-12, -12, 24.0 * revive_progress, 3), Color(0.4, 0.95, 0.5))
		return
	var top := -11.0 if crouching else -17.0
	if not _spr.is_empty():
		top = -16.0 if crouching else -22.0
	var hearts := maxi(max_hp(), hp)
	for i in hearts:
		var c := Color(0.92, 0.25, 0.3) if i < hp else Color(0.22, 0.22, 0.26)
		if i >= max_hp():
			c = BONUS_HEART      # serca ponad podstawowe — złote
		ov.draw_rect(Rect2(-8 + i * 6.0 - (hearts - max_hp()) * 3.0, top - 7.0, 4, 3), c)
	_center_text(ov, font, name_txt, top - 9.0, NAME_SIZE, col)

func _center_text(ov: Node2D, font: Font, txt: String, y: float, sz: int, c: Color) -> void:
	# cień pod tekstem — czytelność na jasnym tle (snop latarki, flara)
	ov.draw_string(font, Vector2(-30 + 0.5, y + 0.5), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, sz, Color(0, 0, 0, 0.8))
	ov.draw_string(font, Vector2(-30, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, sz, c)
