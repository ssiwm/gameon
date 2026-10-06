extends Node2D
## Widok broni gracza — wszystko, co o broni widać i słychać POZA logiką strzału:
## sprite z animacjami (odrzut, dobycie, przeładowanie, cios), rozbłysk i jego światło,
## promień LR-7, płomień HKM-9, żar ładowanej szyny, pętle dźwięku oraz (tylko dla lokalnego
## człowieka) celownik z rozrzutem, paskiem ciepła, pierścieniem przeładowania i hitmarkerami.
##
## Działa na KAŻDYM peerze i czyta tylko to, co jest zreplikowane w graczu (weapon, w_state,
## w_charge, w_firing, aim_dir) plus sygnały kontrolera — dlatego cudze bronie wyglądają tak
## samo jak własna.

const Weapons := preload("res://scripts/weapons.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Controller := preload("res://scripts/weapon_controller.gd")
const Combat := preload("res://scripts/combat.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")

const HAND := Vector2(13, 14)         ## dłoń w klatce broni 72×28 w pikselach arkusza (obrót wokół niej; y = środek klatki, więc flip_v nie przesuwa); zgodne z tools/gun_icons_hd.py
const FLASH_TIME := 0.055
const HIT_TIME := 0.2
const CROSS_DIST := 72.0              ## px od wylotu, gdy celujesz klawiaturą
## Rozmiar celownika (promień, ramiona, łuki, hitmarker i grubość linii) względem wersji 1.6: −30%.
## Skaluje całość razem, więc proporcje między rozrzutem, ciepłem i przeładowaniem zostają.
const CROSS_SCALE := 0.7

var player: CharacterBody2D
var ctrl: Node

var _gun: Sprite2D
var _atlas: AtlasTexture
var _glow: Sprite2D                    ## warstwa świecąca broni (taśma LR-7, cewki WIDMO-1…), unshaded
var _glow_atlas: AtlasTexture
var _fx: Node2D                        ## nakładka bez cieniowania: rozbłysk, promień, celownik
var _flash_light: PointLight2D
var _beam_light: PointLight2D
var _flame: CPUParticles2D
var _flash_t := 0.0
var _flash_seed := 0.0
var _swing_t := -1.0                   ## 0..1 trwającego ciosu, <0 = brak
var _swing_w := Weapons.MACZETA
var _hit_t := 0.0
var _hit_kind := 0
var _hit_snd_ms := 0
var _loop_id := ""
var _loop_on := false
var _spark_t := 0.0
var _beam_end := Vector2.ZERO
var _beam_wall := false
var _beam_normal := Vector2.ZERO
var _draw_anim := 0.0
var _prev_state := 0
var _tint := Color.WHITE
var _facing := 1.0
var _sq := 1.0
var _sheet_ok := false
var _local := false

func setup(p: CharacterBody2D, c: Node) -> void:
	player = p
	ctrl = c
	name = "WeaponView"
	_loop_id = "wl_%d" % p.get_instance_id()
	_sheet_ok = Sprites.has("guns")
	if _sheet_ok:
		_gun = Sprite2D.new()
		_gun.name = "Gun"
		# arkusz ma 2× gęstość pikseli (skala 0,5 → rozmiar jak dawniej); filtr liniowy wygładza obrót pod dowolnym kątem
		_gun.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_gun.centered = false
		_gun.offset = -HAND
		_gun.scale = Vector2.ONE * Sprites.scale_of("guns")
		_atlas = AtlasTexture.new()
		_atlas.filter_clip = true                 # nie podciągaj pikseli sąsiedniej klatki przy filtrowaniu
		_atlas.atlas = Sprites.texture(Sprites.DIR + "guns.png")
		_gun.texture = _atlas
		add_child(_gun)
		# świecące elementy modelu (guns_glow.png, te same klatki) — widać je w ciemności jak oczy wrogów
		var glow_tex := Sprites.texture(Sprites.DIR + "guns_glow.png")
		if glow_tex != null:
			_glow = Sprite2D.new()
			_glow.name = "GunGlow"
			_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			_glow.centered = false
			_glow.offset = -HAND
			_glow.scale = _gun.scale
			_glow.material = Lights.unshaded()
			_glow_atlas = AtlasTexture.new()
			_glow_atlas.filter_clip = true
			_glow_atlas.atlas = glow_tex
			_glow.texture = _glow_atlas
			add_child(_glow)
	_fx = Node2D.new()
	_fx.name = "Fx"
	_fx.material = Lights.unshaded()
	_fx.z_index = 4
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_flash_light = Lights.make_light(Lights.radial(), 4.0, Color(1.0, 0.8, 0.45), 1.4, false)
	_flash_light.enabled = false
	add_child(_flash_light)
	_beam_light = Lights.make_light(Lights.radial(), 2.2, Color(0.55, 0.9, 1.0), 0.9, false)
	_beam_light.enabled = false
	add_child(_beam_light)
	_flame = _make_flame()
	add_child(_flame)
	ctrl.shot.connect(_on_shot)
	ctrl.melee_swung.connect(_on_swing)
	# lokalny człowiek: celownik zamiast kursora, hitmarkery z serwera
	_local = not p.is_bot and p.is_multiplayer_authority()
	if _local:
		Arsenal.hit_confirmed.connect(_on_confirm)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _exit_tree() -> void:
	_stop_loop()
	if _local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _make_flame() -> CPUParticles2D:
	var f := CPUParticles2D.new()
	f.emitting = false
	f.amount = 46
	f.lifetime = 0.5
	f.local_coords = false
	f.direction = Vector2.RIGHT
	f.spread = 14.0
	f.initial_velocity_min = 90.0
	f.initial_velocity_max = 150.0
	f.gravity = Vector2(0, -35)
	f.scale_amount_min = 1.4
	f.scale_amount_max = 3.4
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.65, 0.95), Color(1.0, 0.5, 0.12, 0.85), Color(0.25, 0.1, 0.06, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	f.color_ramp = g
	f.material = Lights.unshaded()
	f.z_index = 3
	return f

# ---------------------------------------------------------------- zdarzenia

func _on_shot(w: int) -> void:
	var d := Weapons.def(w)
	if d.flash_size > 0.0:
		_flash_t = FLASH_TIME * (1.0 + d.flash_size / 12.0)
		_flash_seed = randf() * TAU
		_flash_light.color = d.flash_color
		_flash_light.energy = d.flash_light

func _on_swing(w: int) -> void:
	_swing_t = 0.0
	_swing_w = w

func _on_confirm(kind: int, _pos: Vector2) -> void:
	_hit_t = HIT_TIME
	_hit_kind = kind
	# dźwięk potwierdzenia (UI): krótki, żeby nie męczył przy 9 trafieniach/s; strzelba (8 śrucin
	# naraz) i tak gra jeden
	var now := Time.get_ticks_msec()
	if kind != Arsenal.Confirm.KILL and now - _hit_snd_ms < 45:
		return
	_hit_snd_ms = now
	match kind:
		Arsenal.Confirm.CRIT:
			Audio.play("hitmark_crit", Audio.BUS_UI, -9.0)
		Arsenal.Confirm.KILL:
			Audio.play("killmark", Audio.BUS_UI, -8.0)
		Arsenal.Confirm.ARMOR:
			Audio.play("armor_tick", Audio.BUS_UI, -10.0)
		_:
			Audio.play_variant("hitmark", 2, Audio.BUS_UI, -12.0, 1.0, 0.04)

# ---------------------------------------------------------------- klatka

## Wołane co klatkę z player._process. `tint` = kolor ciała (błysk trafienia, migotanie).
func update(delta: float, tint: Color, facing: float, squash_y: float) -> void:
	_tint = tint
	_facing = facing
	_sq = squash_y
	var d := Weapons.def(player.weapon)
	_flash_t = maxf(0.0, _flash_t - delta)
	_hit_t = maxf(0.0, _hit_t - delta)
	_spark_t = maxf(0.0, _spark_t - delta)
	if player.w_state == Controller.State.DRAW and _prev_state != Controller.State.DRAW:
		_draw_anim = 1.0
	_prev_state = player.w_state
	_draw_anim = maxf(0.0, _draw_anim - delta / maxf(d.draw_time, 0.1))
	if _swing_t >= 0.0:
		_swing_t += delta / maxf(Weapons.def(_swing_w).cooldown, 0.1)
		if _swing_t >= 1.0:
			_swing_t = -1.0
	_update_gun(d)
	_update_flash_light(d)
	_update_continuous(d, delta)
	_fx.queue_redraw()

func muzzle_local(d: WeaponDef) -> Vector2:
	var pos := _gun_pos()
	return pos + player.aim_dir * d.gun_len

func _gun_pos() -> Vector2:
	return Vector2(_facing * 1.0, -8.0 if player.crouching else -12.0) * Vector2(1, _sq)

func _update_gun(d: WeaponDef) -> void:
	if not _sheet_ok or _gun == null:
		return
	var swinging := _swing_t >= 0.0
	var wd := Weapons.def(_swing_w) if swinging else d
	var fs := Sprites.frame_size("guns")
	_atlas.region = Rect2(0, wd.gun_row * fs.y, fs.x, fs.y)
	_gun.visible = not player.dead
	var aim: Vector2 = player.aim_dir
	var flip: bool = aim.x < -0.05
	var rot: float = aim.angle()
	var sgn := -1.0 if flip else 1.0
	var pos := _gun_pos()
	var kick := 0.0
	var extra := 0.0
	if swinging:
		# cios: zamach do tyłu, cięcie przez łuk, powrót; pchnięcie do przodu w momencie trafienia
		var t := _swing_t
		var arc := 1.9
		extra = sgn * lerpf(-arc * 0.55, arc * 0.45, ease(clampf(t * 1.6, 0.0, 1.0), 0.45)) * (1.0 - clampf((t - 0.7) / 0.3, 0.0, 1.0))
		kick = sin(clampf(t * 2.0, 0.0, 1.0) * PI) * 3.0
	else:
		kick = ctrl.recoil * d.recoil
		match player.w_state:
			Controller.State.RELOAD:
				var prog: float = ctrl.reload_progress() if ctrl.is_owner() else 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
				# magazynek: broń opada, kołysze się i wraca
				extra = sgn * (0.85 * sin(prog * PI)) * 0.9
				pos.y += 2.0 * sin(prog * PI)
			Controller.State.CHARGE:
				kick = -player.w_charge * 1.2
				pos += Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)) * player.w_charge
		if _draw_anim > 0.0:
			extra = sgn * 1.1 * ease(_draw_anim, 2.2)
	_gun.position = pos - aim * kick
	_gun.rotation = rot + extra
	_gun.flip_v = flip
	_gun.modulate = _tint
	if _glow != null:
		_glow_atlas.region = _atlas.region
		_glow.visible = _gun.visible
		_glow.position = _gun.position
		_glow.rotation = _gun.rotation
		_glow.flip_v = flip
		# żar narasta z ładowaniem szyny, przy przeładowaniu przygasa; kolor ciała (błysk trafienia) nie wpływa
		var lum := 1.0
		if player.w_state == Controller.State.CHARGE:
			lum = 0.75 + 0.5 * clampf(player.w_charge, 0.0, 1.0)
		elif player.w_state == Controller.State.RELOAD:
			lum = 0.55
		_glow.modulate = Color(lum, lum, lum, _tint.a)

func _update_flash_light(d: WeaponDef) -> void:
	var on: bool = _flash_t > 0.0 or (player.w_firing and d.is_continuous())
	_flash_light.enabled = on
	if on:
		_flash_light.position = muzzle_local(d)
		if player.w_firing and d.is_continuous():
			_flash_light.color = d.flash_color
			_flash_light.energy = d.flash_light * randf_range(0.75, 1.1)
		else:
			_flash_light.energy = d.flash_light * (_flash_t / (FLASH_TIME * (1.0 + d.flash_size / 12.0)))

# ---------------------------------------------------------------- promień, płomień, pętle

func _update_continuous(d: WeaponDef, delta: float) -> void:
	var firing: bool = player.w_firing and d.is_continuous() and not player.dead
	if firing != _loop_on:
		_loop_on = firing
		if firing and d.sfx_loop != "":
			Audio.start_loop_at(d.sfx_loop, player, Audio.BUS_WEAPONS, d.sfx_vol, true, _loop_id)
		else:
			_stop_loop()
	_flame.emitting = firing and d.kind == WeaponDef.Kind.FLAME
	if d.kind == WeaponDef.Kind.FLAME:
		var m := player.global_position + muzzle_local(d)
		_flame.global_position = m
		_flame.direction = player.aim_dir
		_flame.initial_velocity_min = 80.0
		_flame.initial_velocity_max = d.range_px * 2.1
		_flame.lifetime = 0.5
		_flame.spread = d.arc_deg * 0.75
	if firing and d.kind == WeaponDef.Kind.BEAM:
		var origin := player.global_position + muzzle_local(d)
		var tr := Combat.trace(player.get_world_2d().direct_space_state, origin, player.aim_dir, d.range_px, int(d.pierce), 0.0, [player.get_rid()])
		_beam_end = tr["end"] - player.global_position
		_beam_wall = bool(tr["wall"])
		_beam_normal = tr["wall_normal"]
		_beam_light.enabled = true
		_beam_light.position = _beam_end
		_beam_light.energy = randf_range(0.7, 1.1)
		if _spark_t <= 0.0:
			_spark_t = 0.07
			var parent: Node = player._fx_root()
			if _beam_wall:
				Vfx.sparks(parent, tr["end"], player.aim_dir)
			elif not (tr["hits"] as Array).is_empty():
				Vfx.burst(parent, tr["end"], d.tracer_color, 3, 20.0, 60.0, -player.aim_dir, 70.0, 100.0, 0.2, Vector2(1.0, 1.6), true)
	else:
		_beam_light.enabled = false

func _stop_loop() -> void:
	if _loop_id != "":
		Audio.stop_loop(_loop_id)
	_loop_on = false

# ---------------------------------------------------------------- rysowanie (bez cieniowania)

func _draw_fx() -> void:
	if player == null or player.dead:
		return
	var d := Weapons.def(player.weapon)
	var m := muzzle_local(d)
	if _flash_t > 0.0 and d.flash_size > 0.0:
		_draw_flash(d, m)
	if player.w_state == Controller.State.CHARGE:
		_draw_charge(d, m)
	if player.w_firing and d.kind == WeaponDef.Kind.BEAM:
		_draw_beam(d, m)
	if _local:
		_draw_crosshair(d)

func _draw_flash(d: WeaponDef, m: Vector2) -> void:
	var k := _flash_t / (FLASH_TIME * (1.0 + d.flash_size / 12.0))
	var r := d.flash_size * (0.55 + 0.45 * k)
	var col := d.flash_color
	var spikes := 5
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var a := _flash_seed + float(i) * PI / float(spikes)
		var rr := r * (1.0 if i % 2 == 0 else 0.38) * (0.8 + 0.4 * sin(_flash_seed * 7.0 + float(i)))
		pts.append(m + Vector2.from_angle(a) * rr)
	_fx.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85 * k))
	# wydłużony język ognia wzdłuż lufy + jasne jądro
	_fx.draw_line(m, m + player.aim_dir * r * 1.6, Color(1.0, 0.95, 0.8, 0.9 * k), maxf(r * 0.28, 1.0))
	_fx.draw_circle(m, r * 0.38, Color(1.0, 1.0, 0.92, k))

func _draw_charge(d: WeaponDef, m: Vector2) -> void:
	var c := clampf(player.w_charge, 0.0, 1.0)
	var col := d.tracer_color
	_fx.draw_circle(m, 1.5 + 4.5 * c, Color(col.r, col.g, col.b, 0.25 + 0.4 * c))
	_fx.draw_circle(m, 0.8 + 2.0 * c, Color(1, 1, 1, 0.6 + 0.4 * c))
	# iskry zbiegające się do lufy
	for i in 6:
		var a := float(i) * TAU / 6.0 + float(Time.get_ticks_msec()) * 0.004
		var r := (1.0 - fmod(float(Time.get_ticks_msec()) * 0.003 + float(i) * 0.17, 1.0)) * 12.0 * c
		_fx.draw_circle(m + Vector2.from_angle(a) * r, 0.7, Color(col.r, col.g, col.b, 0.8))
	if c >= 1.0:
		_fx.draw_arc(m, 7.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5 + 0.3 * sin(Time.get_ticks_msec() * 0.03)), 1.0)

func _draw_beam(d: WeaponDef, m: Vector2) -> void:
	var col := d.tracer_color
	var fl := randf_range(0.85, 1.0)
	_fx.draw_line(m, _beam_end, Color(col.r, col.g, col.b, 0.22 * fl), 5.0)
	_fx.draw_line(m, _beam_end, Color(col.r, col.g, col.b, 0.6 * fl), 2.4)
	_fx.draw_line(m, _beam_end, Color(1, 1, 1, 0.95 * fl), 1.0)
	_fx.draw_circle(_beam_end, 2.2 * fl, Color(col.r, col.g, col.b, 0.8))
	_fx.draw_circle(m, 2.0, Color(1, 1, 1, 0.8))

# ---------------------------------------------------------------- celownik (tylko lokalny człowiek)

func _aim_world() -> Vector2:
	if player.aim_by_mouse:
		return player.get_global_mouse_position()
	var d := Weapons.def(player.weapon)
	return player.global_position + muzzle_local(d) + player.aim_dir * CROSS_DIST

func _draw_crosshair(d: WeaponDef) -> void:
	var k := CROSS_SCALE
	var at := _aim_world() - player.global_position
	var extra: float = ctrl.spread_extra(d) + d.jitter_deg
	var r := (3.0 + extra * 1.1) * k
	var w := maxf(1.0 * k, 0.8)            ## grubość linii nie schodzi poniżej ~1 px sprite'a
	var col := Color(1, 1, 1, 0.85)
	var mag: int = ctrl.mag_of(d.id)
	var low: bool = d.uses_ammo() and not d.infinite and ctrl.ammo_enabled and mag <= maxi(1, int(d.mag * 0.25))
	if low and int(Time.get_ticks_msec() / 160) % 2 == 0:
		col = Color(1.0, 0.45, 0.3, 0.95)
	if player.w_state == Controller.State.RELOAD or player.w_state == Controller.State.DRAW:
		col.a = 0.45
	# cztery ramiona + punkt środka
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_fx.draw_line(at + dir * r, at + dir * (r + 2.6 * k), col, w)
	_fx.draw_circle(at, 0.7 * k, col)
	# pasek ciepła lufy (hałas rośnie z ciepłem): łuk wokół celownika
	var heat: float = ctrl.heat_of(d.id)
	if d.n_max > d.n_min:
		var hc := Color(1, 1, 1, 0.5).lerp(Color(1.0, 0.25, 0.15, 0.95), clampf(heat * 1.2, 0.0, 1.0))
		_fx.draw_arc(at, r + 5.5 * k, -PI * 0.5, -PI * 0.5 + TAU * 0.999, 28, Color(0, 0, 0, 0.25), 1.6 * k)
		if heat > 0.02:
			_fx.draw_arc(at, r + 5.5 * k, -PI * 0.5, -PI * 0.5 + TAU * heat, 28, hc, 1.6 * k)
	# przeładowanie: pierścień postępu
	if player.w_state == Controller.State.RELOAD:
		var prog: float = ctrl.reload_progress()
		_fx.draw_arc(at, r + 9.0 * k, -PI * 0.5, -PI * 0.5 + TAU * prog, 28, Color(0.7, 0.9, 1.0, 0.9), 1.4 * k)
	elif player.w_state == Controller.State.CHARGE:
		_fx.draw_arc(at, r + 9.0 * k, -PI * 0.5, -PI * 0.5 + TAU * player.w_charge, 28, d.tracer_color, 1.6 * k)
	if mag <= 0 and d.uses_ammo() and ctrl.ammo_enabled and player.w_state == Controller.State.READY:
		var xr := 3.0 * k
		_fx.draw_line(at + Vector2(-xr, -xr), at + Vector2(xr, xr), Color(1.0, 0.3, 0.25, 0.95), w)
		_fx.draw_line(at + Vector2(-xr, xr), at + Vector2(xr, -xr), Color(1.0, 0.3, 0.25, 0.95), w)
	# hitmarker
	if _hit_t > 0.0:
		var t := _hit_t / HIT_TIME
		var hcol := Color(1, 1, 1, t)
		var gap := (3.0 + (1.0 - t) * 2.0) * k
		var ln := 3.0 * k
		match _hit_kind:
			Arsenal.Confirm.CRIT:
				hcol = Color(1.0, 0.85, 0.3, t)
				ln = 4.0 * k
			Arsenal.Confirm.KILL:
				hcol = Color(1.0, 0.25, 0.2, t)
				ln = 5.0 * k
				gap = (4.0 + (1.0 - t) * 3.0) * k
			Arsenal.Confirm.ARMOR:
				hcol = Color(0.65, 0.65, 0.7, t)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var dir := Vector2(sx, sy).normalized()
				_fx.draw_line(at + dir * gap, at + dir * (gap + ln), hcol, w)
