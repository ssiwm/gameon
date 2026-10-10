extends Node3D
## Spike 3D (Bramka B z ATMOSPHERE_PLAN.md): misja 1.1 jako prawdziwa scena 3D — bez ruszania gry. Geometria powstaje z tej samej mapy ASCII
## (`scripts/maps/z1_m1.gd`), postać to model z potoku 3D (`char3d.gd`, ta sama poza i broń, ale oświetlana światłami sceny), a środowisko ma
## perspektywę, światło księżyca z cieniami, latarkę gracza (reflektor), ogniska i flarę wyjścia jako światła 3D, mgłę i las w głębi.
##
## Uruchomienie: godot --path prototype res://scenes/spike_mission3d.tscn
## Sterowanie: A/D chód, SPACJA skok, mysz celowanie, LPM strzał (smuga + błysk), L latarka, [ ] zmiana FOV, F1 podpowiedź.
## Zrzut: `-- --shot3d=PLIK.png [--at=KOLUMNA] [--delay=S] [--fov=°]` (zapisuje obraz i kończy).
## To NIE jest port rozgrywki: brak wrogów, celu, sieci i dźwięku — ocena wyglądu, wydajności i kosztu portu (MISSION_3D_SPIKE.md).

const MapData := preload("res://scripts/maps/z1_m1.gd")
const Char3DScript := preload("res://scripts/char3d.gd")

const PX := 1.8 / 22.0                     ## metrów na piksel świata (postać 22 px = 1,8 m)
const TILE := 16.0                         ## px
const T := TILE * PX                       ## kafel w metrach (≈ 1,31 m)
const DEPTH_FRONT := 1.1                   ## m: wysunięcie bryły przed płaszczyznę gry
const DEPTH_BACK := 2.4                    ## m: w głąb
const SPEED := 95.0                        ## px/s (jak w player.gd)
const JUMP_V := -275.0
const GRAVITY := 900.0
const HALF_W := 4.5                        ## px: pół szerokości postaci
const HEIGHT := 22.0                       ## px

var _rows: PackedStringArray = PackedStringArray()
var _cols := 0
var _nrows := 0
var _pos := Vector2.ZERO                   ## px świata, stopy postaci (x środek, y podłoga)
var _vel := Vector2.ZERO
var _on_floor := false
var _facing := 1.0
var _aim := Vector2.RIGHT                  ## px, y w dół (jak w grze)
var _t := 0.0
var _coyote := 0.0
var _flash_t := 0.0

var _cam: Camera3D
var _fov := 38.0
var _actor: Node3D
var _rig: Node2D                           ## Char3D (Node2D) — tu tylko jako nosiciel poz i modelu
var _flashlight: SpotLight3D
var _muzzle_light: OmniLight3D
var _tracers: Array = []                   ## [Node3D, czas życia]
var _lights_flicker: Array = []            ## [OmniLight3D, baza, faza]
var _hud: Label
var _shot_path := ""
var _shot_delay := 2.5
var _shot_col := -1
var _fps_acc := 0.0
var _fps_n := 0
var _fps_txt := ""
var _anim_override := ""
var _anim_now := ""
var _shot_aim_x := 1.0                     ## tylko zrzut: kierunek celowania (−1 = w lewo)
var _bench_s := 0.0                        ## > 0: pomiar czasu klatki bez vsync przez tyle sekund (po 1,5 s rozgrzewki), wynik na stdout
var _bench: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot3d="):
			_shot_path = a.substr(9)
		elif a.begins_with("--at="):
			_shot_col = int(a.substr(5))
		elif a.begins_with("--delay="):
			_shot_delay = float(a.substr(8))
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a.begins_with("--anim="):
			_anim_override = a.substr(7)
		elif a.begins_with("--aimx="):
			_shot_aim_x = float(a.substr(7))
		elif a.begins_with("--bench="):
			_bench_s = float(a.substr(8))
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rows = PackedStringArray(MapData.MAP)
	_nrows = _rows.size()
	_cols = _rows[0].length()
	_build_environment()
	_build_level()
	_build_forest()
	_build_player()
	_build_hud()
	_place_player()
	_follow_camera(1.0)
	var inst := 0
	var lights := 0
	for n in find_children("*", "MultiMeshInstance3D", true, false):
		inst += (n as MultiMeshInstance3D).multimesh.instance_count
	for n in find_children("*", "Light3D", true, false):
		lights += 1
	print("[SPIKE3D] instancji MultiMesh: %d, świateł: %d, mapa %d×%d" % [inst, lights, _cols, _nrows])

# ---------------------------------------------------------------- mapa

func _ch(c: int, r: int) -> String:
	if r < 0 or r >= _nrows or c < 0 or c >= _cols:
		return "#"
	return _rows[r][c]

func _is_solid(c: int, r: int) -> bool:
	var ch := _ch(c, r)
	return ch == "#" or ch == "C" or ch == "M" or ch == "m" or ch == "O" or ch == "~"

func _is_platform(c: int, r: int) -> bool:
	var ch := _ch(c, r)
	return ch == "-" or ch == "="

## Środek kafla (c, r) w metrach świata: x w prawo, y w górę (mapa ma y w dół), z = 0 na płaszczyźnie gry.
func _w(c: float, r: float) -> Vector3:
	return Vector3((c + 0.5) * T, -(r + 0.5) * T, 0.0)

# ---------------------------------------------------------------- środowisko

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.025, 0.06)
	sm.sky_horizon_color = Color(0.06, 0.09, 0.16)
	sm.ground_bottom_color = Color(0.01, 0.015, 0.03)
	sm.ground_horizon_color = Color(0.04, 0.06, 0.1)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.26, 0.42)
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.06, 0.10)
	env.fog_density = 0.018
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.basis = Basis.looking_at(Vector3(0.55, -0.7, -0.45), Vector3.UP)
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.shadow_bias = 0.04
	add_child(moon)

func _mat(col: Color, rough := 0.95, noise_freq := 0.06, bump := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = noise_freq
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = bump
	return m

func _multimesh(mesh: Mesh, xforms: Array, mat: Material, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------------------------------------------------------------- poziom

func _build_level() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(T, T, DEPTH_FRONT + DEPTH_BACK)
	var groups := {"#": [], "C": [], "M": [], "m": [], "O": [], "~": []}
	var grass: Array = []
	var walls: Array = []
	var posts: Array = []
	var planks: Array = []
	var zc := (DEPTH_FRONT - DEPTH_BACK) * 0.5
	for r in _nrows:
		for c in _cols:
			var ch := _ch(c, r)
			if groups.has(ch):
				# tylko odsłonięte kafle (sąsiad z powietrzem lub tłem) — wnętrza skał nie są widoczne
				if _is_solid(c - 1, r) and _is_solid(c + 1, r) and _is_solid(c, r - 1) and _is_solid(c, r + 1):
					continue
				var p := _w(c, r)
				groups[ch].append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.0, zc)))
				if ch == "#" and not _is_solid(c, r - 1):
					var g := Transform3D(Basis.IDENTITY, p + Vector3(0.0, T * 0.5, zc + 0.05))
					grass.append(g)
			elif ch == "b":
				walls.append(Transform3D(Basis.IDENTITY, _w(c, r) + Vector3(0.0, 0.0, -DEPTH_BACK + 0.15)))
			elif ch == "w":
				posts.append(Transform3D(Basis.IDENTITY, _w(c, r) + Vector3(0.0, 0.0, -0.4)))
			elif _is_platform(c, r):
				planks.append(Transform3D(Basis.IDENTITY, _w(c, r) + Vector3(0.0, T * 0.5 - 0.1, 0.0)))
	var mats := {
		"#": _mat(Color(0.20, 0.17, 0.14), 0.97, 0.05),
		"C": _mat(Color(0.30, 0.31, 0.33), 0.9, 0.09, 0.3),
		"M": _mat(Color(0.28, 0.30, 0.34), 0.6, 0.12, 0.2),
		"m": _mat(Color(0.18, 0.2, 0.1), 1.0, 0.04),
		"O": _mat(Color(0.05, 0.05, 0.07), 0.2, 0.03, 0.1),
		"~": _mat(Color(0.05, 0.12, 0.2), 0.1, 0.03, 0.1),
	}
	for k in groups:
		_multimesh(box, groups[k], mats[k])
	var gbox := BoxMesh.new()
	gbox.size = Vector3(T, 0.18, DEPTH_FRONT + DEPTH_BACK + 0.1)
	_multimesh(gbox, grass, _mat(Color(0.07, 0.13, 0.06), 1.0, 0.2, 0.9))
	var wbox := BoxMesh.new()
	wbox.size = Vector3(T, T, 0.3)
	_multimesh(wbox, walls, _mat(Color(0.12, 0.13, 0.15), 0.95, 0.15, 0.7), false)
	var pc := CylinderMesh.new()
	pc.top_radius = 0.45
	pc.bottom_radius = 0.55
	pc.height = T
	pc.radial_segments = 10
	_multimesh(pc, posts, _mat(Color(0.20, 0.14, 0.09), 1.0, 0.25, 1.0))
	var plb := BoxMesh.new()
	plb.size = Vector3(T, 0.22, 2.0)
	_multimesh(plb, planks, _mat(Color(0.34, 0.24, 0.14), 0.9, 0.2, 0.6))
	# znaczniki: ogniska (F), wyjście (E / e), skrzynie (k), amunicja (a)
	for r in _nrows:
		for c in _cols:
			var ch := _ch(c, r)
			var p := _w(c, r) + Vector3(0.0, -T * 0.5, 0.0)
			match ch:
				"F":
					_add_fire(p)
				"e", "E":
					_add_exit_flare(p)
				"k":
					_add_crate(p)

func _add_fire(p: Vector3) -> void:
	var l := OmniLight3D.new()
	l.position = p + Vector3(0.0, 0.8, 0.5)
	l.light_color = Color(1.0, 0.55, 0.22)
	l.light_energy = 3.2
	l.omni_range = 11.0
	l.shadow_enabled = true
	add_child(l)
	_lights_flicker.append([l, 3.2, randf() * TAU])
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.8
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 3.0
	m.material_override = mat
	m.position = p + Vector3(0.0, 0.4, 0.5)
	add_child(m)

func _add_exit_flare(p: Vector3) -> void:
	var l := OmniLight3D.new()
	l.position = p + Vector3(0.0, 1.0, 0.6)
	l.light_color = Color(0.4, 1.0, 0.5)
	l.light_energy = 3.0
	l.omni_range = 14.0
	l.shadow_enabled = true
	add_child(l)
	_lights_flicker.append([l, 3.0, randf() * TAU])
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.9
	tube.mesh = cm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.55, 0.12, 0.1)
	tube.material_override = tm
	tube.position = p + Vector3(0.0, 0.45, 0.6)
	add_child(tube)
	var fl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.45
	fl.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.6, 1.0, 0.7)
	fm.emission_enabled = true
	fm.emission = Color(0.4, 1.0, 0.5)
	fm.emission_energy_multiplier = 4.0
	fl.material_override = fm
	fl.position = p + Vector3(0.0, 1.05, 0.6)
	add_child(fl)

func _add_crate(p: Vector3) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.0, 0.9, 0.9)
	m.mesh = b
	m.material_override = _mat(Color(0.30, 0.20, 0.10), 0.9, 0.3, 0.8)
	m.position = p + Vector3(0.0, 0.45, 0.0)
	add_child(m)

# ---------------------------------------------------------------- las w głębi

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1ACE
	var trunks: Array = []
	var low: Array = []
	var mid: Array = []
	var top: Array = []
	# odcinek, w którym pod otwartym niebem jest polana (pierwszy kafel bryły dopiero nisko)
	for c in range(0, _cols, 2):
		var r0 := 0
		while r0 < _nrows and not _is_solid(c, r0):
			r0 += 1
		if r0 < 28:
			continue
		var n := rng.randi_range(2, 4)
		for i in n:
			var z := -rng.randf_range(DEPTH_BACK + 1.0, 46.0)
			var h := rng.randf_range(7.0, 15.0)
			var x := (float(c) + rng.randf()) * T + rng.randf_range(-2.0, 2.0)
			var y := -float(r0) * T
			var s := h / 10.0
			trunks.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, y + h * 0.08, z)))
			low.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, y + h * 0.28, z)))
			mid.append(Transform3D(Basis().scaled(Vector3(s * 0.8, s, s * 0.8)), Vector3(x, y + h * 0.52, z)))
			top.append(Transform3D(Basis().scaled(Vector3(s * 0.6, s, s * 0.6)), Vector3(x, y + h * 0.76, z)))
	var tm := _mat(Color(0.05, 0.035, 0.025), 1.0, 0.3, 0.8)
	var gm := _mat(Color(0.03, 0.07, 0.07), 1.0, 0.2, 0.6)
	var tr := CylinderMesh.new()
	tr.top_radius = 0.18
	tr.bottom_radius = 0.28
	tr.height = 2.0
	tr.radial_segments = 7
	_multimesh(tr, trunks, tm, false)
	for spec in [[low, 2.4, 3.8], [mid, 2.0, 3.0], [top, 1.6, 2.2]]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = float(spec[1])
		cm.height = float(spec[2]) + 1.4
		cm.radial_segments = 9
		_multimesh(cm, spec[0], gm, false)

# ---------------------------------------------------------------- gracz

func _build_player() -> void:
	_rig = Char3DScript.new()
	_rig.name = "Rig"
	add_child(_rig)                                   # Node2D pod Node3D: tylko nosiciel (SubViewport modelu jest wyłączany niżej)
	if not _rig.setup("male_scav", "m83"):
		push_warning("spike3d: brak modelu postaci")
		return
	_actor = Node3D.new()
	_actor.name = "Actor"
	add_child(_actor)
	# model i broń przenosimy ze świata podglądu do sceny gry; poza liczy dalej char3d.gd (`update`), światło daje scena
	(_rig._char_node as Node).reparent(_actor, false)
	(_rig._gun as Node).reparent(_actor, false)
	if _rig._gun_n != null:
		(_rig._gun_n as Node).queue_free()
		_rig._gun_n = null
	_rig._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rig._vpn.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _rig._notifier != null:
		_rig._notifier.queue_free()
		_rig._notifier = null
	_rig._on_screen = true
	_rig._sprite.visible = false
	for mi in _actor.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1

	# światła gracza: latarka (reflektor), błysk lufy
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.96, 0.82)
	_flashlight.light_energy = 7.0
	_flashlight.spot_range = 22.0
	_flashlight.spot_angle = 26.0
	_flashlight.spot_attenuation = 0.7
	_flashlight.shadow_enabled = true
	add_child(_flashlight)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.8, 0.45)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 7.0
	add_child(_muzzle_light)
	var aura := OmniLight3D.new()
	aura.light_color = Color(0.8, 0.9, 1.0)
	aura.light_energy = 0.35
	aura.omni_range = 4.0
	aura.position = Vector3(0.0, 1.2, 1.0)
	_actor.add_child(aura)

func _place_player() -> void:
	var c := _shot_col
	if c < 0:
		for r in _nrows:
			var i := _rows[r].find("S")
			if i >= 0:
				c = i
				break
	if c < 0:
		c = 8
	var r := 0
	while r < _nrows - 1 and not _is_solid(c, r):
		r += 1
	_pos = Vector2((float(c) + 0.5) * TILE, float(r) * TILE - 0.1)

# ---------------------------------------------------------------- HUD / zrzut

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud = Label.new()
	_hud.position = Vector2(12.0, 8.0)
	_hud.add_theme_font_size_override("font_size", 13)
	cl.add_child(_hud)

func _process(delta: float) -> void:
	_t += delta
	if _bench_s > 0.0 and _t > 1.5:
		_bench.append(delta * 1000.0)
		if _t > 1.5 + _bench_s:
			var a := _bench.duplicate()
			a.sort()
			var sum := 0.0
			for v in a:
				sum += v
			print("[BENCH3D] %d klatek: średnia %.2f ms (%.0f fps), p50 %.2f, p95 %.2f, max %.2f ms  okno=%s" % [a.size(), sum / float(a.size()), 1000.0 * float(a.size()) / sum,
				a[a.size() / 2], a[int(float(a.size()) * 0.95)], a[a.size() - 1], str(get_window().size)])
			get_tree().quit()
	_fps_acc += delta
	_fps_n += 1
	if _fps_acc >= 0.5:
		_fps_txt = "%.0f fps  %.1f ms" % [float(_fps_n) / _fps_acc, 1000.0 * _fps_acc / float(_fps_n)]
		_fps_acc = 0.0
		_fps_n = 0
	_hud.text = "SPIKE 3D — mission 1.1   %s\nA/D move · SPACE jump · mouse aim · LMB shoot · L flashlight · [ ] FOV %d   anim=%s floor=%s" % [_fps_txt, int(_fov), _anim_now, str(_on_floor)]
	if _actor == null:
		return
	# podkroki ≤ 8 ms i górny limit delty: pierwsza klatka po kompilacji shaderów bywa długa, a przy dużej delcie postać „przeskakiwała” kafel
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, 0.008)
		_physics(dt)
		left -= dt
	_update_actor(delta)
	_update_lights(delta)
	_follow_camera(minf(1.0, delta * 6.0))
	if _shot_path != "" and _t >= _shot_delay:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[SHOT3D] %s (%dx%d)" % [_shot_path, img.get_width(), img.get_height()])
		get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_L:
				if _flashlight != null:
					_flashlight.visible = not _flashlight.visible
			KEY_BRACKETLEFT:
				_fov = clampf(_fov - 4.0, 18.0, 80.0)
			KEY_BRACKETRIGHT:
				_fov = clampf(_fov + 4.0, 18.0, 80.0)
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_shoot()

# ---------------------------------------------------------------- fizyka (px, jak w grze)

func _solid_px(x: float, y: float) -> bool:
	return _is_solid(int(floor(x / TILE)), int(floor(y / TILE)))

func _platform_top(x: float, y_prev: float, y_now: float) -> float:
	# kładka jednokierunkowa (4 px od góry kafla): stopy przecinają jej górę z góry → zwraca y podłoża, inaczej -1
	var c := int(floor(x / TILE))
	var r := int(floor(y_now / TILE))
	if _is_platform(c, r):
		var top := float(r) * TILE
		if y_prev <= top + 0.01 and y_now >= top:
			return top
	return -1.0

func _physics(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir += 1.0
	if _shot_path != "":
		dir = 0.0
	_vel.x = dir * SPEED
	_coyote = 0.1 if _on_floor else maxf(0.0, _coyote - delta)
	if Input.is_key_pressed(KEY_SPACE) and _coyote > 0.0:
		_vel.y = JUMP_V
		_coyote = 0.0
	_vel.y += GRAVITY * delta
	# oś X
	var nx := _pos.x + _vel.x * delta
	var blocked := false
	for hy in [-1.0, -HEIGHT * 0.5, -HEIGHT + 1.0]:
		if _solid_px(nx + signf(_vel.x) * HALF_W, _pos.y + hy):
			blocked = true
	if not blocked:
		_pos.x = nx
	# oś Y
	var prev_y := _pos.y
	var ny := _pos.y + _vel.y * delta
	_on_floor = false
	if _vel.y >= 0.0:
		for sx in [-HALF_W, 0.0, HALF_W]:
			if _solid_px(_pos.x + sx, ny):
				ny = floorf(ny / TILE) * TILE - 0.01
				_vel.y = 0.0
				_on_floor = true
				break
			var pt := _platform_top(_pos.x + sx, prev_y, ny)
			if pt >= 0.0 and not Input.is_key_pressed(KEY_S):
				ny = pt - 0.01
				_vel.y = 0.0
				_on_floor = true
				break
	else:
		for sx in [-HALF_W, 0.0, HALF_W]:
			if _solid_px(_pos.x + sx, ny - HEIGHT):
				ny = (floorf((ny - HEIGHT) / TILE) + 1.0) * TILE + HEIGHT + 0.01
				_vel.y = 0.0
				break
	_pos.y = ny
	# oparcie pod stopami (sonda 1 px niżej), niezależne od długości podkroku
	if _vel.y >= 0.0:
		for sx in [-HALF_W, 0.0, HALF_W]:
			if _solid_px(_pos.x + sx, _pos.y + 1.0):
				_on_floor = true
				break
			if _is_platform(int(floor((_pos.x + sx) / TILE)), int(floor((_pos.y + 1.0) / TILE))) and fposmod(_pos.y + 1.0, TILE) < 2.0:
				_on_floor = true
				break
	if absf(_pos.x - float(_cols) * TILE * 0.5) > float(_cols) * TILE or _pos.y > float(_nrows) * TILE + 200.0:
		_place_player()
		_vel = Vector2.ZERO

# ---------------------------------------------------------------- postać

func _world_pos() -> Vector3:
	return Vector3(_pos.x * PX, -_pos.y * PX, 0.0)

func _mouse_aim() -> Vector2:
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var from := _cam.project_ray_origin(m)
	var dir := _cam.project_ray_normal(m)
	if absf(dir.z) < 0.0001:
		return _aim
	var k := -from.z / dir.z
	var hit := from + dir * k
	var chest := _world_pos() + Vector3(0.0, 1.25, 0.0)
	var d := Vector2(hit.x - chest.x, -(hit.y - chest.y))        # y w dół jak w grze
	return d.normalized() if d.length() > 0.2 else _aim

func _update_actor(delta: float) -> void:
	if _shot_path == "":
		_aim = _mouse_aim()
	else:
		_aim = Vector2(_shot_aim_x, -0.12).normalized()
	if absf(_aim.x) > 0.1:
		_facing = signf(_aim.x)
	var moving := absf(_vel.x) > 1.0
	var anim := "idle"
	if not _on_floor:
		anim = "jump" if _vel.y < 0.0 else "fall"
	elif moving:
		anim = "run"
	if _anim_override != "":
		anim = _anim_override
	_anim_now = anim
	_actor.position = _world_pos()
	_actor.scale = Vector3(_facing, 1.0, 1.0)
	_rig._on_screen = true
	_rig.update(delta, anim, 1.0, Vector2(absf(_aim.x), _aim.y), absf(_vel.x), true, Color.WHITE)
	# reflektor latarki: z piersi wzdłuż celowania (w płaszczyźnie gry), lekko do kamery
	var chest := _world_pos() + Vector3(0.0, 1.25, 0.4)
	_flashlight.position = chest
	var d3 := Vector3(_aim.x, -_aim.y, 0.0).normalized()
	_flashlight.basis = Basis.looking_at(d3 + Vector3(0.0, 0.0, -0.05), Vector3.UP)

func _shoot() -> void:
	if _actor == null:
		return
	var o := _world_pos() + Vector3(0.0, 1.25, 0.2) + Vector3(_aim.x, -_aim.y, 0.0).normalized() * 0.9
	var d3 := Vector3(_aim.x, -_aim.y, 0.0).normalized()
	var tr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.03, 0.03)
	tr.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.emission_energy_multiplier = 6.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tr.material_override = m
	tr.position = o
	tr.basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP) if false else Basis(Vector3(d3.x, d3.y, 0.0), Vector3(-d3.y, d3.x, 0.0), Vector3(0, 0, 1))
	add_child(tr)
	_tracers.append([tr, 0.0, d3])
	_flash_t = 0.07
	_muzzle_light.position = o
	_muzzle_light.light_energy = 6.0

func _update_lights(delta: float) -> void:
	for t in _tracers.duplicate():
		var n: Node3D = t[0]
		t[1] += delta
		n.position += (t[2] as Vector3) * 60.0 * delta
		if t[1] > 0.4:
			n.queue_free()
			_tracers.erase(t)
	_flash_t = maxf(0.0, _flash_t - delta)
	_muzzle_light.light_energy = 6.0 if _flash_t > 0.0 else 0.0
	for f in _lights_flicker:
		var l: OmniLight3D = f[0]
		l.light_energy = float(f[1]) * (0.85 + 0.15 * sin(_t * 9.0 + float(f[2])) * sin(_t * 3.7 + float(f[2]) * 2.0))

# ---------------------------------------------------------------- kamera

func _follow_camera(k: float) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.current = true
		_cam.near = 0.3
		_cam.far = 140.0
		add_child(_cam)
	_cam.fov = _fov
	var target := _world_pos() + Vector3(2.4 * _facing, 1.9, 0.0)
	var want := target + Vector3(0.0, 0.0, 17.0)
	_cam.position = _cam.position.lerp(want, k)
	_cam.look_at(Vector3(_cam.position.x, _cam.position.y - 0.4, 0.0), Vector3.UP)
