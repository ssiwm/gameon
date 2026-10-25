extends CanvasLayer
## Strzelnica FPP — obraz (RANGE_FPS_PLAN.md, etap 0). Własny świat 3D w SubViewport na cały ekran, pod HUD-em: betonowy tunel 30 m z ławą
## i przegrodami stanowisk, przesłony pod stropem, kulochwyt (skośna blacha nad wałem piasku), pięć stalowych blach na słupkach, lampy
## i tablica z czasem przebiegu. Broń w rękach to model z gry (gun_model.gd — części i nacięcia gracza) z prostymi rękawicami i rękawami.
## Na czas strzelnicy widok kryjówki (view3d.gd) jest schowany i nie renderuje się. Geometria zgadza się z range_sim.gd (te same stałe).

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Parts := preload("res://scripts/parts.gd")
const Weapons := preload("res://scripts/weapons.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Actions := preload("res://scripts/actions.gd")
const FpArms := preload("res://scripts/range3d/fp_arms.gd")
const FpRig := preload("res://scripts/range3d/fp_rig.gd")
const RangeFx := preload("res://scripts/range3d/range_fx.gd")
const RangeSpecial := preload("res://scripts/range3d/range_special.gd")
const RangeTargets := preload("res://scripts/range3d/range_targets.gd")
const RangeLocker := preload("res://scripts/range3d/range_locker.gd")
const RangeOthers := preload("res://scripts/range3d/range_others.gd")
const RangeOptic := preload("res://scripts/range3d/range_optic.gd")
const OPTIC_IN := Vector2(0.8, 0.97)          ## postęp przyrządów, w którym model broni z optyką gaśnie, a nakładka optyki wchodzi (range_optic.gd)
const GUN_BASIS := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   ## układ broni (x lufa, y góra, z prawo) → kamera (−z w przód)

const RANGE_EXPOSURE := 1.3                   ## ekspozycja tunelu przy jasności 0 EV (AgX)
const VM_FOV := 58.0                          ## ° — kąt kamery rąk i broni (węższy: bez rozciągania na brzegach, jak w grach FPP)
const LAYER_VM := 2                           ## warstwa rąk i broni: rysuje je tylko kamera rąk, zawsze nad tunelem (bez wchodzenia w ławę)
const TEX := "res://art/world3d/"
const HIP := Vector3(0.15, -0.2, -0.3)        ## m — chwyt broni w układzie kamery (od biodra, broń poniżej i z prawej)
const HIP_PISTOL := Vector3(0.12, -0.15, -0.42)  ## m — pistolet od biodra: niżej, bliżej środka i dalej niż karabin (ręce wyciągnięte przed siebie)
const HIP_YAW := 1.5                         ## ° — broń przy biodrze lekko zwrócona do środka kadru
const ADS_GRIP_Z := -0.27                     ## m — chwyt karabinu przed okiem przy celowaniu (policzek na kolbie)
const ADS_GRIP_Z_PISTOL := -0.55             ## m — pistolet w wyciągniętych rękach
const SIGHT_CLEAR := 0.003                    ## m — linia celownicza tuż nad najwyższym punktem broni (wierzch muszki i szczerbinki);
                                              ## dokładne punkty przyrządów z gun_proc.py — etap 2
const SWAY_LAG := 0.022                       ## s — broń zostaje za obrotem kamery (kąt = prędkość kątowa × opóźnienie)
const SWAY_MAX := 0.07                        ## rad — najwięcej kołysania
const SWAY_RATE := 11.0                       ## 1/s — powrót kołysania
const REC_K := 320.0                          ## sprężyna odrzutu (sztywność, 1/s²)
const REC_C := 30.0                           ## … tłumienie (1/s)
const REC_IMPULSE := Vector3(0.6, 1.0, 0.25)  ## prędkość po strzale: cofnięcie (m/s), uniesienie (rad/s), skręt (± rad/s); × WEAPON_POSE body / climb
const ARMS_RIG := false                       ## ręce FPP z zasobu (fp_rig.gd, chwyty z fp_grip.py) — wyłączone: animacje dłoni za słabej jakości,
                                              ## wrócą z lepszymi narzędziami (RANGE_FPS_PLAN.md §8); broń jest w kadrze sama
const ARMS_FALLBACK := false                 ## ręce dla broni bez ułożonego chwytu (fp_arms.gd, walce) — rozjeżdżały się (SPREAD-12: rękaw
                                              ## przez pół kadru, P-83: bez rąk); do czasu klipów z fp_grip.py taka broń jest sama w kadrze
const HOLES_MAX := 90
const SLEEVE := Color(0.1, 0.11, 0.08)
const GLOVE := Color(0.05, 0.045, 0.04)

var fp: Node                                  ## fp_mode.gd
var _vp: SubViewport
var _screen: TextureRect                      ## obraz SubViewportu na cały ekran (w jednostkach interfejsu)
var _vp_vm: SubViewport                       ## ręce i broń: ten sam świat 3D, przezroczyste tło, własna kamera (VM_FOV)
var _cam_vm: Camera3D
var _world: Node3D
var _cam: Camera3D
var _vm: Node3D                               ## broń w rękach (dziecko kamery)
var _gun: Node3D
var _gun_sig := ""                            ## klucz:części:nacięcia zbudowanego modelu
var _info := {}                               ## Char3D.gun_info z częściami
var _top_y := 0.1                             ## m — najwyższy punkt modelu broni (układ broni)
var _rear_x := -0.3                           ## m — tył broni (stopka kolby)
var _arms: Array = []                         ## zapas bez modelu postaci: [rękaw P, rękawica P, rękaw L, rękawica L]
var _fp_arms: Node3D                          ## ręce z modelu postaci gracza (fp_arms.gd) — broń bez ułożonego chwytu
var _rig: Node3D                              ## ręce FPP z zasobu z ułożonym chwytem (fp_rig.gd); broń jest wtedy jego dzieckiem
var _gun_xf := Transform3D.IDENTITY           ## broń w układzie kamery (bieżąca klatka)
var _rl_was := false                          ## przeładowanie w poprzedniej klatce (początek: czy z pustego)
var _rl_empty := false
var _rl_u := 0.0                              ## postęp przeładowania w poprzedniej klatce (dźwięki klipu w swoich chwilach)
var _pivots: Array = []                       ## zawiasy blach (Node3D)
var _falls: Array = []                        ## 0 stoi … 1 leży (kosmetyka)
var _board: Label3D
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _sway := Vector2.ZERO                     ## rad — kołysanie (odchylenie, pochylenie)
var _last_look := Vector2.ZERO
var _rec := Vector3.ZERO                      ## odrzut: cofnięcie (m), uniesienie (rad), skręt (rad)
var _rec_v := Vector3.ZERO
var _life := 0.0
var _fx: Node3D                               ## łuski i dym w świecie tunelu (range_fx.gd)
var _spec: Node3D                             ## obraz broni specjalnych: pociski w locie, wybuchy, szyna, promień, płomień (range_special.gd)
var _plate_mats: Array = []                   ## materiał tarczy każdej blachy (żar od promienia i płomienia)
var _targets: Node3D                          ## papierowa tarcza i ruchomy cel (range_targets.gd)
var _locker: Node3D                           ## szafa z bronią: stojak w tunelu i lista na ekranie (range_locker.gd)
var _others: Node3D                           ## inni gracze na sąsiednich stanowiskach (range_others.gd)
enum Phase { IN, TUNNEL, OUT, BACK }
const IN_T := 0.55                            ## s — najazd kamery kryjówki na drzwi (view3d.RP_TIME), ostatnie FADE_T to ściemnienie
const FADE_T := 0.25                          ## s — wyłanianie się z czerni i gaśnięcie
var _phase := Phase.IN
var _pt := 0.0
var _black: ColorRect                         ## czerń przejścia (nad światem, pod HUD-em)
var _vm_screen: TextureRect
const VOICES := 8
var _voices: Array = []                       ## głosy 3D w tunelu (_play3d)
var _voice_i := 0
var _holes: Array = []
var _hole_i := 0
var _hole_mat: StandardMaterial3D
var _dot: Control
var _optic: RangeOptic                         ## obraz przez kolimator / noktowizor przy pełnym celowaniu
var _hint: Label
var _hub: Node                                ## schowany View3D
var _msg := ""
var _msg_t := 0.0

func setup(f: Node) -> void:
	fp = f

func _ready() -> void:
	layer = 1
	var parent := get_parent()
	var idx := get_index()
	for n in ["WeatherFx", "HorrorFx", "UI"]:
		var c := parent.get_node_or_null(n)
		if c != null:
			idx = mini(idx, c.get_index())
	parent.move_child(self, idx)                               # nad światem, pod pogodą, winietą i HUD-em
	# render w pikselach okna (_fit_viewport), a nie w pikselach interfejsu: płótno ma 640×360 i jest skalowane do okna, więc
	# SubViewportContainer ze `stretch` renderowałby świat w 640×360 i rozciągał go (rozmyty obraz)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_screen = TextureRect.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.texture = _vp.get_texture()
	add_child(_screen)
	_vp_vm = SubViewport.new()
	_vp_vm.world_3d = _vp.find_world_3d()
	_vp_vm.transparent_bg = true
	_vp_vm.msaa_3d = Viewport.MSAA_4X
	_vp_vm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp_vm)
	var vm_screen := TextureRect.new()
	_vm_screen = vm_screen
	vm_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	vm_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vm_screen.stretch_mode = TextureRect.STRETCH_SCALE
	vm_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_screen.texture = _vp_vm.get_texture()
	add_child(vm_screen)
	_fit_viewport()
	_world = Node3D.new()
	_world.name = "Range"
	_vp.add_child(_world)
	_build_env()
	_build_tunnel()
	_build_lights()
	_build_plates()
	_build_board()
	_fx = RangeFx.new()
	_fx.name = "Fx"
	_world.add_child(_fx)
	_spec = RangeSpecial.new()
	_spec.name = "Special"
	_spec.setup(self, fp.sim)
	_spec.plate_mats = _plate_mats
	_world.add_child(_spec)
	_targets = RangeTargets.new()
	_targets.name = "Targets"
	_targets.setup(self, fp.sim)
	_world.add_child(_targets)
	_locker = RangeLocker.new()
	_locker.name = "Locker"
	_locker.setup(self, fp)
	_world.add_child(_locker)
	_others = RangeOthers.new()
	_others.name = "Others"
	_others.setup(self, fp)
	_world.add_child(_others)
	_vp.audio_listener_enable_3d = true                          # słuchacz 3D = bieżąca kamera tunelu (dźwięki blach i ścian, _play3d)
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.bus = Audio.BUS_WEAPONS
		v.unit_size = 4.0                                         # pełna głośność do ~4 m, dalej spada (blacha na 20 m o ok. 14 dB ciszej)
		v.max_distance = 60.0
		v.attenuation_filter_cutoff_hz = 9000.0                   # dalekie trafienia lekko stłumione (powietrze, tunel)
		v.attenuation_filter_db = -8.0
		v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		_world.add_child(v)
		_voices.append(v)
	_cam = Camera3D.new()
	_cam.fov = Settings.fp_fov()
	_cam.near = 0.02
	_cam.far = 80.0
	_cam.current = true
	_cam.cull_mask = 0xFFFFF & ~(1 << (LAYER_VM - 1))
	_world.add_child(_cam)
	_cam_vm = Camera3D.new()
	_cam_vm.fov = VM_FOV
	_cam_vm.near = 0.1                                            # bliżej jest tylko bark (karczek kurtki) i kolba za okiem — nie zasłaniają kadru
	_cam_vm.far = 4.0
	_cam_vm.cull_mask = 1 << (LAYER_VM - 1)
	_cam_vm.current = true
	_vp_vm.add_child(_cam_vm)
	_vm = Node3D.new()
	_vm.name = "Viewmodel"
	_cam.add_child(_vm)
	for i in 4:
		var mi := MeshInstance3D.new()
		var m: Mesh
		if i % 2 == 0:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.034
			cy.bottom_radius = 0.043
			cy.height = 1.0
			m = cy
		else:
			var cap := CapsuleMesh.new()
			cap.radius = 0.03
			cap.height = 0.11
			m = cap
		mi.mesh = m
		mi.material_override = _flat(SLEEVE if i % 2 == 0 else GLOVE, 0.85)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cam.add_child(mi)
		_arms.append(mi)
	_rig = FpRig.new()                                          # bez rąk (ARMS_RIG) tylko ruchome części broni: zamek przy strzale, spust
	_rig.name = "FpRig"
	_cam.add_child(_rig)
	if ARMS_RIG:
		_rig.setup()
	if ARMS_FALLBACK:
		_fp_arms = FpArms.new()
		_fp_arms.name = "FpArms"
		_cam.add_child(_fp_arms)
		var c3 = fp.player.get("c3d")
		var look := String(c3._char_name) if c3 != null and is_instance_valid(c3) else Char3D.DEFAULT_CHAR
		if not _fp_arms.setup(self, look, int(c3._palette) if c3 != null and is_instance_valid(c3) else 0):
			_fp_arms.queue_free()
			_fp_arms = null
	for a in _arms:
		(a as Node3D).visible = ARMS_FALLBACK and _fp_arms == null
	# słabe wypełnienie tylko dla rąk i broni (z przodu z lewej, chłodne): skóra rękawic i tkanina mają rysunek, a nie płaską plamę w cieniu
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.45, 0.25, -0.35)
	fill.omni_range = 1.8
	fill.light_energy = 0.8
	fill.light_color = Color(0.9, 0.93, 1.0)
	fill.light_cull_mask = 1 << (LAYER_VM - 1)
	fill.layers = 1 << (LAYER_VM - 1)
	_cam.add_child(fill)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.42)
	_flash.omni_range = 7.0
	_flash.light_energy = 0.0
	_flash.layers = 1 | (1 << (LAYER_VM - 1))
	_cam.add_child(_flash)
	_flash_mesh = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.085, 0.085)
	_flash_mesh.mesh = fq
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _radial(Color(1.0, 0.8, 0.45, 1.0), Color(1.0, 0.5, 0.1, 0.0))
	_flash_mesh.material_override = fm
	_flash_mesh.visible = false
	_cam.add_child(_flash_mesh)
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hole_mat.albedo_texture = _radial(Color(0.02, 0.02, 0.02, 0.95), Color(0.1, 0.09, 0.08, 0.0))
	_hole_mat.roughness = 1.0
	_optic = RangeOptic.new()
	add_child(_optic)
	_dot = Control.new()
	_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	add_child(_dot)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.position = Vector2(-200, 10)                           # interfejs ma 640×360 (skalowany): u góry, gdzie w kryjówce stoi karta celu (hud.gd chowa ją
	                                                             # na strzelnicy) — na dole wchodził w rząd miniatur broni po zmianie broni
	_hint.size = Vector2(400, 12)
	_hint.add_theme_font_size_override("font_size", 7)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7, 0.75))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 2)
	_hint.text = Actions.range_line()
	Settings.bindings_changed.connect(func() -> void: _hint.text = Actions.range_line())       # przypisanie klawisza w menu pauzy
	InputSetup.device_changed.connect(func(_pad: bool) -> void: _hint.text = Actions.range_line())
	add_child(_hint)
	fp.sim.plate_down.connect(_on_plate_down)
	fp.sim.finished.connect(_on_finished)
	add_to_group("range_view")                                  # hud.gd: karty kryjówki schowane, dopóki tunel gaśnie
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_hub = get_tree().current_scene.get_node_or_null("View3D")
	if _hub != null and (_hub as CanvasItem).visible:
		_show_tunnel(false)                                     # najpierw najazd na drzwi w kryjówce (view3d._rp), potem czerń i tunel
	else:
		_phase = Phase.TUNNEL
		_hide_hub(true)

## Koniec strzelnicy: tunel gaśnie do czerni, z niej wraca kryjówka (kamera odjeżdża od drzwi — view3d._rp), potem węzeł znika.
func release() -> void:
	if _phase >= Phase.OUT:
		return
	_locker.hide_ui()
	if _fp_arms != null:
		_fp_arms.release()
		_fp_arms = null
	fp = null
	_phase = Phase.OUT
	_pt = 0.0

## Tunel gaśnie po wyjściu (kryjówka jeszcze schowana).
func fading_out() -> bool:
	return _phase == Phase.OUT

## Obraz tunelu (świat, ręce, celownik, podpowiedź) albo nic — wtedy pod spodem widać kryjówkę.
func _show_tunnel(on: bool) -> void:
	for c in [_screen, _vm_screen, _dot, _hint]:
		(c as CanvasItem).visible = on
	if not on:
		_optic.visible = false

## Przejście kryjówka ↔ tunel: IN najazd na drzwi (ostatnie FADE_T to ściemnienie), TUNNEL wyłania się z czerni, OUT gaśnie, BACK
## kryjówka wyłania się z czerni. Zwraca true, gdy węzeł kończy (BACK minął).
func _drive_phase(delta: float) -> bool:
	_pt += delta
	match _phase:
		Phase.IN:
			_black.color.a = clampf((_pt - (IN_T - FADE_T)) / FADE_T, 0.0, 1.0)
			if _pt >= IN_T:
				_hide_hub(true)
				_show_tunnel(true)
				_phase = Phase.TUNNEL
				_pt = 0.0
		Phase.TUNNEL:
			_black.color.a = clampf(1.0 - _pt / FADE_T, 0.0, 1.0)
		Phase.OUT:
			_black.color.a = clampf(_pt / FADE_T, 0.0, 1.0)
			if _pt >= FADE_T:
				_show_tunnel(false)
				_hide_hub(false)
				_phase = Phase.BACK
				_pt = 0.0
		Phase.BACK:
			_black.color.a = clampf(1.0 - _pt / FADE_T, 0.0, 1.0)
			if _pt >= FADE_T:
				queue_free()
				return true
	return false

func _exit_tree() -> void:
	if _phase != Phase.BACK and _hub != null and is_instance_valid(_hub) and not (_hub as CanvasItem).visible:
		_hide_hub(false)                                        # zwolniony w pół przejścia (zmiana sceny): kryjówka nie może zostać schowana

func _hide_hub(on: bool) -> void:
	if on and (_hub == null or not is_instance_valid(_hub)):
		_hub = get_tree().current_scene.get_node_or_null("View3D")
	if _hub == null or not is_instance_valid(_hub):
		return
	(_hub as CanvasItem).visible = not on
	var mode := SubViewport.UPDATE_DISABLED if on else SubViewport.UPDATE_ALWAYS
	for vp in [_hub.get("_vp_bg"), _hub.get("_vp_fg")]:
		if vp != null:
			(vp as SubViewport).render_target_update_mode = mode

# ---------------------------------------------------------------- klatka

func _process(delta: float) -> void:
	if _drive_phase(delta) or _phase >= Phase.OUT:
		return
	if fp == null or not is_instance_valid(fp):
		return
	_fit_viewport()
	_cam.fov = Settings.fp_fov()                                  # kąt widzenia tunelu z ustawień (menu pauzy w trakcie strzelania); ręce mają stały VM_FOV
	_cam.transform = Transform3D(fp.view_basis(), fp.eye())
	_cam_vm.global_transform = _cam.global_transform
	_sync_gun()
	_pose_gun(delta)
	_vm_layers(_cam)
	for i in _pivots.size():
		var down: bool = fp.sim.plates[i]["down"]
		_falls[i] = move_toward(float(_falls[i]), 1.0 if down else 0.0, delta * (7.0 if down else 2.2))
		var f := float(_falls[i])
		(_pivots[i] as Node3D).rotation.x = -1.42 * (f * f * (3.0 - 2.0 * f))
	_flash_t = maxf(0.0, _flash_t - delta)
	if _gun != null and is_instance_valid(_gun):              # smużki z gorącej lufy
		var wc = fp.player.weapons
		_fx.barrel_smoke(_cam.global_transform * _vm_to_cam(_gun_xf * (_info.get("muzzle", Vector3(0.6, 0.1, 0.0)) as Vector3)), float(wc.barrel_of(wc.cur().id)))
	_spec.tick(delta, muzzle_world(), -_cam.global_transform.basis.z)
	_targets.tick(delta)
	_locker.tick()
	_others.tick(delta)
	_flash.light_energy = 6.0 * (_flash_t / 0.05)
	_flash_mesh.visible = _flash_t > 0.02
	_msg_t = maxf(0.0, _msg_t - delta)
	_update_board()
	_dot.queue_redraw()

## Rozmiar renderu = piksele okna zajęte przez interfejs (640×360 × skala okna) × skala „Effects quality” (jak view3d._res_scale).
func _fit_viewport() -> void:
	var vp := get_viewport()
	var px := vp.get_visible_rect().size * vp.get_final_transform().get_scale()
	var rs := 0.5 if Settings.quality_idx == 0 else (0.75 if Settings.quality_idx == 1 else 1.0)
	var want := Vector2i(maxi(int(px.x * rs), 64), maxi(int(px.y * rs), 36))
	if _vp.size != want:
		_vp.size = want
		_vp_vm.size = want

## Model broni zgodny z trzymaną bronią (części i nacięcia gracza); przebudowa przy zmianie.
func _sync_gun() -> void:
	var wc = fp.player.weapons
	var d: WeaponDef = wc.cur()
	var key := String(d.key)
	var fit: int = wc.fit_of(d.id)
	var notch: int = wc.notches_of(d.id)
	var sig := "%s:%d:%d" % [key, fit, notch]
	if sig == _gun_sig:
		return
	_gun_sig = sig
	if _gun != null:
		_gun.queue_free()
		_gun = null
	if not ResourceLoader.exists(Char3D.DIR + "gun_%s.glb" % key):
		return
	var ids := Parts.decode(key, fit)
	_info = Char3D.info_with(key, ids)
	_gun = GunModel.build(key, ids, Char3D.gun_info(key)["muzzle"], notch % 16, notch / 16, Char3D.DIR + "fp/")   # tekstury 4K, jeśli są
	for mi in _gun.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm.add_child(_gun)
	_top_y = -1.0
	_rear_x = 0.0
	for mi in _gun.find_children("*", "MeshInstance3D", true, false):
		var xf := (mi as Node3D).transform
		var par := (mi as Node).get_parent()
		while par != _gun and par is Node3D:
			xf = (par as Node3D).transform * xf
			par = par.get_parent()
		var bb := xf * (mi as MeshInstance3D).get_aabb()
		_top_y = maxf(_top_y, bb.end.y)
		_rear_x = minf(_rear_x, bb.position.x)
	# układ broni: x wzdłuż lufy, y w górę, z w prawo → kamera patrzy w −z
	_gun.basis = GUN_BASIS
	if _rig != null and not _rig.set_weapon(key, _gun):          # z ułożonym chwytem broń przechodzi na rękę (gunref)
		_rig.bind_parts(key, _gun)

## Położenie broni w kadrze: biodro albo przyrządy, odrzut, przeładowanie i usuwanie zacięcia (proste ruchy do szpica).
func _pose_gun(delta: float) -> void:
	if _gun == null:
		for a in _arms:
			(a as Node3D).visible = false
		_optic.visible = false
		_vm_screen.modulate.a = 1.0
		return
	var wc = fp.player.weapons
	_life += delta
	# kołysanie: broń zostaje za obrotem kamery i wraca sprężyście; przy przyrządach słabiej
	var look := Vector2(float(fp.yaw), float(fp.pitch))
	var w := (look - _last_look) / maxf(delta, 0.001)
	_last_look = look
	var k_ads := 1.0 - 0.65 * float(fp.ads_t)
	var tgt := (-w * SWAY_LAG * k_ads).limit_length(SWAY_MAX)
	_sway = _sway.lerp(tgt, 1.0 - exp(-SWAY_RATE * delta))
	# odrzut: sprężyna z tłumieniem (cofnięcie, uniesienie, skręt)
	_rec_v += (-REC_K * _rec - REC_C * _rec_v) * delta
	_rec += _rec_v * delta
	var breath := sin(_life * 1.45) * (1.0 - 0.85 * float(fp.ads_t))
	var grip: Vector3 = _info.get("grip", Vector3.ZERO)
	var muzzle: Vector3 = _info.get("muzzle", Vector3(0.6, 0.1, 0.0))
	var sight := Vector3(grip.x, _top_y + SIGHT_CLEAR, 0.0)
	var pistol := float(_info.get("length", 1.0)) < 0.45
	var gb := GUN_BASIS
	var t := float(fp.ads_t)
	t = t * t * (3.0 - 2.0 * t)
	var ads_z := ADS_GRIP_Z_PISTOL if pistol else ADS_GRIP_Z
	if pistol and _rig != null and String(_rig.key) != "":
		ads_z = -(sight.x - _rig.eye_in_gun().x)                  # pistolet w rękach z zasobu: szczerbinka tak daleko od oka jak w ułożonej postawie
	var hip_o := (HIP_PISTOL if pistol else HIP) - gb * grip
	var ap := ads_pose(_info, _top_y, ads_z)
	var ads_o: Vector3 = ap[0]
	var tilt: float = ap[1]
	var o := hip_o.lerp(ads_o, t)
	var optic := String(_info.get("sight_optic", ""))
	var ko := smoothstep(OPTIC_IN.x, OPTIC_IN.y, float(fp.ads_t)) if optic != "" else 0.0
	_vm_screen.modulate.a = 1.0 - ko                              # zamknięta tuba z bliska zasłoniłaby cel: obraz przez optykę zamiast modelu
	_optic.show_optic(optic, ko)
	var rot := Basis(Vector3.UP, deg_to_rad(HIP_YAW) * (1.0 - t))
	var dip := 0.0
	var roll := 0.0
	var rl: bool = wc.is_reloading()
	if rl and not _rl_was:
		_rl_empty = wc.mag_of(wc.cur().id) <= 0
		_rl_u = 0.0
	_rl_was = rl
	var clip_rl: bool = rl and not wc.clearing and _rig != null and String(_rig.key) != ""
	if rl:
		var s := sin(clampf(wc.reload_progress(), 0.0, 1.0) * PI)
		if not clip_rl:                          # klip przeładowania sam porusza bronią (fp_grip.py GUN_POSES)
			dip = s
			roll = (-0.5 if wc.clearing else 0.45) * s
	rot = Basis(Vector3.UP, _sway.x + _rec.z) * rot * Basis(Vector3.FORWARD, roll + _rec.z * 0.6) * Basis(Vector3.RIGHT, _sway.y + _rec.y - 0.35 * dip + breath * 0.004) \
		* Basis(Vector3.RIGHT, -tilt * t)                         # przy przyrządach linia szczerbinka → muszka w osi kamery (ads_pose)
	_vm.transform = Transform3D(rot, Vector3(0.0, -0.13 * dip + breath * 0.0018, _rec.x) + rot * o)
	# rękawice na chwycie i pod łożem, rękawy do krawędzi kadru
	var xf := _vm.transform * Transform3D(GUN_BASIS, Vector3.ZERO)
	_gun_xf = xf
	var rigged := _rig != null and String(_rig.key) != ""
	if _fp_arms != null:
		_fp_arms.visible = not rigged
	if rigged:
		_rig.animate(clip_rl, _rl_empty, wc.reload_progress(), t)
		_rig.tick_parts(delta, bool(wc.firing) or (Input.is_action_pressed("fire") and not wc.is_reloading()))
		if clip_rl:                                              # dźwięki mechaniki w klatkach klipu (zatrzask, magazynek, suwadło)
			var u: float = wc.reload_progress()
			for e in _rig.events(_rl_empty):
				if float(e[0]) > _rl_u and float(e[0]) <= u:
					Audio.play_variant(String(e[1]), 3, Audio.BUS_WEAPONS, -6.0, randf_range(0.97, 1.03))
			_rl_u = u
		_rig.transform = xf * _rig.anchor().affine_inverse()       # całe ręce tak, by broń z pozy chwytu stała w zadanym miejscu kadru
		for a in _arms:
			(a as Node3D).visible = false
		return
	if _rig != null:                                             # broń bez rąk: zamek przy strzale i spust dalej się ruszają
		_rig.tick_parts(delta, bool(wc.firing) or (Input.is_action_pressed("fire") and not wc.is_reloading()))
	if not ARMS_FALLBACK:
		for a in _arms:
			(a as Node3D).visible = false
		return
	if _fp_arms != null:
		_fp_arms.pose(xf, String(wc.cur().key), _info, _rear_x, wc.reload_progress() if wc.is_reloading() else -1.0, bool(wc.clearing))
		return
	var rh := xf * (grip + Vector3(0.0, -0.01, 0.0))
	var lh := xf * (_info.get("hold", grip + Vector3(0.3, 0.05, 0.0)) as Vector3 + Vector3(0.0, -0.035, 0.0))
	var one_hand := int(_info.get("hands", 2)) < 2
	_limb(_arms[0], rh + Vector3(0.015, -0.03, 0.05), rh + Vector3(0.13, -0.3, 0.22))
	_hand(_arms[1], rh, xf.basis)
	(_arms[2] as Node3D).visible = not one_hand
	(_arms[3] as Node3D).visible = not one_hand
	if not one_hand:
		_limb(_arms[2], lh + Vector3(-0.01, -0.03, 0.03), lh + Vector3(-0.3, -0.3, 0.14))
		_hand(_arms[3], lh, xf.basis)

## Ręce, broń i błysk (dzieci kamery tunelu) tylko na warstwie kamery rąk. Nowe węzły (zmiana broni, części) — co klatkę, tanio.
func _vm_layers(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and not c is Light3D:              # światło błysku zostaje dla obu kamer (oświetla tunel)
			(c as VisualInstance3D).layers = 1 << (LAYER_VM - 1)
		_vm_layers(c)

func _limb(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mi.visible = true
	var dir := b - a
	var ln := dir.length()
	var y := dir / ln
	var xa := y.cross(Vector3.FORWARD)
	if xa.length() < 0.01:
		xa = Vector3.RIGHT
	xa = xa.normalized()
	var z := xa.cross(y).normalized()
	mi.transform = Transform3D(Basis(xa, y * ln, z), (a + b) * 0.5)

func _hand(mi: MeshInstance3D, at: Vector3, gun_basis: Basis) -> void:
	mi.visible = true
	mi.transform = Transform3D(gun_basis * Basis(Vector3.FORWARD, deg_to_rad(80.0)), at)

func _draw_dot() -> void:
	if fp == null or not is_instance_valid(fp) or float(fp.ads_t) > 0.5 or _gun == null:
		return
	var c := _dot.size * 0.5
	_dot.draw_circle(c, 0.9, Color(0, 0, 0, 0.6))
	_dot.draw_circle(c, 0.5, Color(0.9, 0.95, 0.85, 0.85))

# ---------------------------------------------------------------- zdarzenia

## Broń przy przyrządach: [przesunięcie (układ kamery, przed obrotem broni), pochylenie (rad, obrót wokół osi x kamery: −pochylenie)] tak, by
## linia szczerbinka → muszka (gun_<klucz>.json: `sight_rear` / `sight_front`, z gun_proc.py) leżała w osi kamery, a jej punkt nad chwytem
## w odległości `ads_z` (ta sama odległość co dotąd — policzek na kolbie). Broń bez punktów przyrządów — linia nad najwyższym punktem modelu.
static func ads_pose(info: Dictionary, top_y: float, ads_z: float) -> Array:
	var grip: Vector3 = info.get("grip", Vector3.ZERO)
	if info.has("sight_rear") and info.has("sight_front"):
		var r: Vector3 = info["sight_rear"]
		var f: Vector3 = info["sight_front"]
		if absf(f.x - r.x) > 0.01:
			var tilt := atan2(f.y - r.y, f.x - r.x)
			var a := r + (f - r) * ((grip.x - r.x) / (f.x - r.x))
			return [Basis(Vector3.RIGHT, -tilt).inverse() * Vector3(0.0, 0.0, ads_z) - GUN_BASIS * a, tilt]
	return [Vector3(0.0, 0.0, ads_z) - GUN_BASIS * Vector3(grip.x, top_y + SIGHT_CLEAR, 0.0), 0.0]

## Wylot lufy trzymanej broni w świecie tunelu (z kamery rąk przeliczony na kamerę tunelu).
func muzzle_world() -> Vector3:
	return _cam.global_transform * _vm_to_cam(_gun_xf * (_info.get("muzzle", Vector3(0.6, 0.1, 0.0)) as Vector3))

func on_shot(d: WeaponDef, hits: Array) -> void:
	if d.is_continuous():
		return                                                   # promień / płomień: obraz co klatkę z range_sim (range_special.gd), bez odrzutu i błysku na krok
	var wp: Dictionary = Char3D.WEAPON_POSE.get(String(d.key), {})
	var kb := float(wp.get("body", 1.0)) * (0.55 if fp.braced() else 1.0)
	_rec_v += Vector3(REC_IMPULSE.x * kb, REC_IMPULSE.y * float(wp.get("climb", 1.0)) * (0.5 if fp.braced() else 1.0), randf_range(-REC_IMPULSE.z, REC_IMPULSE.z))
	_flash_t = 0.05 if d.suppressor <= 0.0 else 0.02
	if _rig != null:                                             # zamek / suwadło w tył i spust — z rękami i bez
		_rig.shot()
	if _gun != null:
		var m := _gun_xf * (_info.get("muzzle", Vector3(0.6, 0.1, 0.0)) as Vector3)
		_flash.position = _vm_to_cam(m)                          # światło w świecie, błysk na warstwie rąk
		_flash_mesh.position = m + Vector3(0.0, 0.0, -0.04)
		_fx.puff(_cam.global_transform * _vm_to_cam(m), _cam.global_transform.basis * _gun_xf.basis.x.normalized(), 1.4 if d.suppressor > 0.0 else 1.0)
		if d.casing > 0:
			if d.sfx_cycle == "":
				_eject(d)
			else:
				get_tree().create_timer(0.38).timeout.connect(_eject.bind(d))     # pompka: łuska wylatuje przy przeładowaniu
	if d.kind == WeaponDef.Kind.RAIL and not hits.is_empty():
		_spec.rail(muzzle_world(), hits.back()["pos"])
	for h in hits:
		var kind := String(h["kind"])
		var pos: Vector3 = h["pos"]
		var n: Vector3 = h["normal"]
		if kind == "mover":
			continue                                             # iskry i dzwonienie wózka: range_targets.gd (sygnał mover_hit)
		if kind == "plate":
			_burst(pos + n * 0.01, n, Color(1.0, 0.72, 0.3), 14, 3.5)
			_play3d("plate_ring", 4, pos, 0.0, 0.05)
		else:
			_hole(pos, n)
			_burst(pos + n * 0.02, n, Color(0.5, 0.46, 0.4), 8, 1.4)
			_play3d("impact_hard", 3, pos, -12.0 if kind == "backstop" else -8.0, 0.08)

## Punkt z kamery rąk (VM_FOV) do kamery tunelu (FOV) tak, żeby na ekranie wypadł w tym samym miejscu: obie kamery stoją tak samo,
## różnią się kątem widzenia, więc wystarczy przeskalować x i y o stosunek tangensów połówek kątów.
func _vm_to_cam(p: Vector3) -> Vector3:
	var k := tan(deg_to_rad(_cam.fov) * 0.5) / tan(deg_to_rad(VM_FOV) * 0.5)
	return Vector3(p.x * k, p.y * k, p.z)

## Łuska z okna wyrzutowego (prawa strona komory, za chwytem): w prawo, w górę i lekko w tył, z rozrzutem.
func _eject(d: WeaponDef) -> void:
	if _gun == null or not is_instance_valid(_gun):
		return
	var grip: Vector3 = _info.get("grip", Vector3.ZERO)
	var muzzle: Vector3 = _info.get("muzzle", Vector3(0.6, 0.1, 0.0))
	var pistol := float(_info.get("length", 1.0)) < 0.45
	var port := Vector3(grip.x + (0.07 if pistol else 0.11), muzzle.y - 0.012, 0.02)     # okno wyrzutowe pistoletu tuż przed chwytem
	var cam := _cam.global_transform
	var v := _gun_xf.basis * Vector3(randf_range(-0.9, -0.4), randf_range(1.0, 1.6), randf_range(2.2, 3.0))
	_fx.eject(cam * _vm_to_cam(_gun_xf * port), cam.basis * v, d.casing >= 2)

## Klip przeładowania z dźwiękami mechaniki dla tej broni (fp_rig.gd)?
func has_reload_clip(k: String) -> bool:
	return _rig != null and _rig.has_reload_clip(k)

## Przewrócona blacha uderza w ogranicznik zawiasu, kiedy obraz kończy upadek (_falls: 7/s).
func _on_plate_down(i: int) -> void:
	var at: Vector3 = fp.sim.plates[i]["pos"]
	get_tree().create_timer(0.16).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_play3d("plate_fall", 2, at + Vector3(0.0, -0.25, 0.0), -3.0, 0.06))

## Dźwięk w świecie tunelu: głos 3D (słuchaczem jest kamera tunelu — SubViewport z `audio_listener_enable_3d`), więc blacha na 20 m
## z lewej brzmi z lewej i ciszej. Strzał i mechanika broni zostają niepozycyjne (przy uchu). Najstarszy głos ustępuje nowemu.
func _play3d(base: String, count: int, pos: Vector3, vol_db: float, jitter: float) -> void:
	if Audio.variant(base, count) < 0:
		return
	var s := Audio.stream(Audio.pick(base, count))
	if s == null:
		return
	var p: AudioStreamPlayer3D = _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	p.stop()
	p.stream = s
	p.position = pos
	p.volume_db = vol_db + randf_range(-1.0, 1.0)
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.panning_strength = 0.0 if Settings.mono_audio else 1.0          # ustawienie „Mono audio”
	p.play()

## Koniec przebiegu: czas na tablicy w tunelu; rekord osobisty z tej wizyty (wynik drużyny rozstrzyga serwer — toast z range_door.gd).
func _on_finished(t: float, best: float, record: bool) -> void:
	_msg = tr("%.2f s — best this visit") % t if record else tr("%.2f s  (this visit %.2f s)") % [t, best]
	if fp.pb_new:
		_msg += "  ·  " + tr("PERSONAL BEST")
	_msg_t = 5.0
	Audio.play("ui_click", Audio.BUS_UI, -4.0, 0.8)

func _update_board() -> void:
	var sim = fp.sim
	var lines := PackedStringArray()
	var head := tr("RELOAD DRILL  ·  %d plates, %d rounds") % [RangeSim.DRILL_PLATES, RangeSim.DRILL_LOAD] if sim.exercise == RangeSim.EX_RELOAD else tr("5 PLATES")
	lines.append(head + "   [%s]" % Actions.key("range_exercise"))
	if sim.running:
		lines.append("%.2f s" % (sim.clock - sim._t0))
	elif _msg_t > 0.0:
		lines.append(_msg)
	else:
		var door = fp.door if fp.door != null and is_instance_valid(fp.door) else null
		var sb := ""                                              # rekord drużyny z tablicy serwera (range_door.gd), bez drzwi — sesji
		var top: Array = door.rows(sim.exercise) if door != null else []
		if not top.is_empty():
			var e: Dictionary = top[0]
			sb = "%.2f s %s" % [float(e["t"]), String(e["who"])]
		elif door == null and sim.best >= 0.0:
			sb = "%.2f s" % sim.best
		lines.append(tr("last %s   squad %s") % ["%.2f s" % sim.last_time if sim.last_time >= 0.0 else "—", sb if sb != "" else "—"])
	var key := String(fp.player.weapons.cur().key)                # rekord osobisty trzymanej broni (Profile.range_best)
	var pb := Profile.range_best_of(sim.exercise, key)
	lines.append(tr("personal best %s") % ("%.2f s" % pb if pb >= 0.0 else "—"))
	lines.append(tr("shots %d   hits %d") % [sim.shots, sim.hits])
	lines.append_array(_targets.board_lines())                   # papier (grupa) i wózek (trafienia / próby)
	_board.text = "\n".join(lines)

# ---------------------------------------------------------------- budowa sceny

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.29, 0.28)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_AGX                # AgX: jasne partie (podłoga pod lampą, rękawy) bez przepalenia do bieli
	env.tonemap_exposure = RANGE_EXPOSURE * Settings.exposure_mult()    # jasność z ustawień (ekran kalibracji) także w tunelu
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.08, 0.07)
	env.fog_density = 0.01
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	Settings.changed.connect(func() -> void: env.tonemap_exposure = RANGE_EXPOSURE * Settings.exposure_mult())

func _build_tunnel() -> void:
	var w := RangeSim.LANE_W
	var h := RangeSim.LANE_H
	var l := RangeSim.LANE_L
	var back := 2.5                                              # m za linią ognia (ściana za plecami)
	var concrete := _tex_mat("concrete", 0.5)
	var wall := _tex_mat("wall", 0.4)
	var metal := _tex_mat("metal", 0.7)
	var plank := _tex_mat("plank", 0.9)
	var mud := _tex_mat("mud", 0.45)
	var run := l + back
	_box(Vector3(w + 0.6, 0.3, run), Vector3(0, -0.15, -l + run * 0.5), concrete)                  # podłoga
	_box(Vector3(w + 0.6, 0.3, run), Vector3(0, h + 0.15, -l + run * 0.5), concrete)               # strop
	for s in [-1.0, 1.0]:
		_box(Vector3(0.3, h, run), Vector3(s * (w * 0.5 + 0.15), h * 0.5, -l + run * 0.5), wall)      # ściany
	_box(Vector3(w, h, 0.3), Vector3(0, h * 0.5, back + 0.15), wall)                               # za plecami
	_box(Vector3(w, h, 0.3), Vector3(0, h * 0.5, -l - 0.9), concrete)                              # za kulochwytem
	# kulochwyt: wał piasku i skośna blacha nad nim
	var berm := _box(Vector3(w, 1.0, 1.6), Vector3(0, 0.25, -l - 0.1), mud)
	berm.rotation.x = deg_to_rad(-28.0)
	var plate := _box(Vector3(w, h * 1.25, 0.04), Vector3(0, h * 0.55, -l - 0.2), metal)
	plate.rotation.x = deg_to_rad(-35.0)
	# przesłony pod stropem (betonowe belki — nie widać z linii ognia stropu nad kulochwytem)
	for z in [-5.0, -11.0, -17.0, -23.0]:
		_box(Vector3(w, 0.55, 0.25), Vector3(0, h - 0.27, z), concrete)
	# ława stanowiska i przegrody między stanowiskami
	_box(Vector3(w, 0.06, -RangeSim.BENCH_Z), Vector3(0, RangeSim.BENCH_H - 0.03, RangeSim.BENCH_Z * 0.5), plank)
	_box(Vector3(w, RangeSim.BENCH_H - 0.06, 0.04), Vector3(0, (RangeSim.BENCH_H - 0.06) * 0.5, RangeSim.BENCH_Z + 0.04), plank)
	var dz := RangeSim.DIVIDER_Z
	var dy := RangeSim.DIVIDER_Y
	for x in RangeSim.DIVIDERS:
		_box(Vector3(0.05, dy.y - dy.x, dz.y - dz.x), Vector3(x, (dy.x + dy.y) * 0.5, (dz.x + dz.y) * 0.5), plank)
	# żółta linia ognia na podłodze
	var line := _box(Vector3(w, 0.005, 0.08), Vector3(0, 0.003, RangeSim.BENCH_Z - 0.06), _flat(Color(0.75, 0.6, 0.1), 0.7))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_lights() -> void:
	# lampy pod stropem nad torem i jedna nad stanowiskami; cienie tylko w trzech (koszt)
	var spots := [[1.5, 0.3, false], [-3.0, 1.0, false], [-9.0, 1.0, true], [-14.0, 1.2, true], [-20.0, 1.1, true], [-26.0, 0.7, false]]
	for s in spots:
		var z := float(s[0])
		var sl := SpotLight3D.new()
		sl.position = Vector3(0.0, RangeSim.LANE_H - 0.12, z)
		sl.rotation.x = deg_to_rad(-90.0 if z > 0.0 else -72.0)
		sl.spot_angle = 62.0
		sl.spot_range = 12.0
		sl.spot_attenuation = 0.8
		sl.light_energy = 2.6 * float(s[1])
		sl.light_color = Color(1.0, 0.93, 0.82)                      # ok. 3800 K (świetlówka w osłonie), nie pomarańcz
		sl.shadow_enabled = bool(s[2])
		sl.layers = 1 | (1 << (LAYER_VM - 1))                       # światło widzą obie kamery (tunel i ręce)
		_world.add_child(sl)
		var lamp := _box(Vector3(0.5, 0.06, 0.18), Vector3(0.0, RangeSim.LANE_H - 0.05, z), _glow(Color(1.0, 0.95, 0.86), 2.5))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_plates() -> void:
	var steel := _flat(Color(0.82, 0.8, 0.74), 0.45, 0.6)
	var post := _tex_mat("metal", 1.5)
	for i in fp.sim.plates.size():
		var c: Vector3 = fp.sim.plates[i]["pos"]
		_box(Vector3(0.42, 0.07, 0.32), Vector3(c.x, 0.035, c.z), post)
		var hinge_y := c.y - RangeSim.PLATE_R - 0.03
		var pole := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.022
		cy.bottom_radius = 0.026
		cy.height = hinge_y - 0.07
		pole.mesh = cy
		pole.material_override = post
		pole.position = Vector3(c.x, 0.07 + cy.height * 0.5, c.z)
		_world.add_child(pole)
		var pivot := Node3D.new()
		pivot.position = Vector3(c.x, hinge_y, c.z)
		_world.add_child(pivot)
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = RangeSim.PLATE_R
		dm.bottom_radius = RangeSim.PLATE_R
		dm.height = 0.012
		dm.radial_segments = 32
		disc.mesh = dm
		var face := steel.duplicate() as StandardMaterial3D        # własny materiał tarczy: żar od promienia i płomienia (range_special.gd)
		_plate_mats.append(face)
		disc.material_override = face
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(0.0, RangeSim.PLATE_R + 0.03, 0.0)
		pivot.add_child(disc)
		var neck := _box(Vector3(0.05, 0.06, 0.012), Vector3(0.0, 0.03, 0.0), steel, pivot)
		neck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_pivots.append(pivot)
		_falls.append(0.0)
		var lbl := Label3D.new()
		lbl.text = "%d m" % int(round(-c.z))
		lbl.font_size = 48
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.95, 0.85, 0.3)
		lbl.outline_size = 8
		lbl.position = Vector3(c.x, 0.2, c.z + 0.17)
		_world.add_child(lbl)

func _build_board() -> void:
	var panel := _box(Vector3(1.8, 1.15, 0.05), Vector3(0.0, RangeSim.LANE_H - 0.62, -4.2), _flat(Color(0.05, 0.05, 0.045), 0.9))   # ćwiczenie, wynik, rekord osobisty, strzały, wózek (papier: range_targets — tablica porównania)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_board = Label3D.new()
	_board.font_size = 58
	_board.pixel_size = 0.0035
	_board.modulate = Color(0.95, 0.75, 0.3)
	_board.outline_size = 0
	_board.line_spacing = -6.0
	_board.position = Vector3(0.0, RangeSim.LANE_H - 0.62, -4.17)
	_world.add_child(_board)

# ---------------------------------------------------------------- pomocnicze

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else _world).add_child(mi)
	return mi

func _tex_mat(name: String, scale: float) -> Material:
	var m := ORMMaterial3D.new()
	if ResourceLoader.exists(TEX + name + "_albedo.png"):
		m.albedo_texture = load(TEX + name + "_albedo.png")
	if ResourceLoader.exists(TEX + name + "_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(TEX + name + "_normal.png")
	if ResourceLoader.exists(TEX + name + "_orm.png"):
		m.orm_texture = load(TEX + name + "_orm.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m

func _flat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := _flat(c, 0.5)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _radial(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t

## Przestrzelina w betonie, piasku albo drewnie: ciemna plamka na powierzchni (pierścień HOLES_MAX ostatnich).
func _hole(pos: Vector3, n: Vector3) -> void:
	var mi: MeshInstance3D
	if _holes.size() < HOLES_MAX:
		mi = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.035, 0.035)
		mi.mesh = q
		mi.material_override = _hole_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(mi)
		_holes.append(mi)
	else:
		mi = _holes[_hole_i]
		_hole_i = (_hole_i + 1) % HOLES_MAX
	var z := n.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var xa := up.cross(z).normalized()
	mi.transform = Transform3D(Basis(xa, z.cross(xa), z), pos + z * 0.004)

## Iskry z blachy albo pył z betonu: jednorazowy wybuch cząstek 3D.
func _burst(pos: Vector3, n: Vector3, col: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = n
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	if col.r > 0.8:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	p.material_override = m
	p.position = pos
	_world.add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
