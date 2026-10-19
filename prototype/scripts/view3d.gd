extends Node2D
## Widok 3D (opcja graficzna „3D view”, MISSION_3D_SPIKE.md §5): symulacja zostaje w 2D (fizyka kafli, AI, sieć, rozstrzygnięcia serwera),
## a ten węzeł renderuje ten sam świat w prawdziwym 3D. Nic tu nie rozstrzyga rozgrywki — kamera, geometria i proxy tylko odzwierciedlają stan 2D,
## więc celowanie myszą (współrzędne Camera2D) i cała logika działają bez zmian.
##
## Kanapka warstw (3D nie może się przeplatać z 2D, więc render idzie do dwóch SubViewportów rysowanych jako sprite'y w świecie 2D):
##   tło 3D (z_index −60: teren, las, niebo, światła, wrogowie jako billboardy) → rekwizyty i efekty 2D → gracze 3D (z_index +1) → HUD.
## Oba SubViewporty współdzielą jeden świat 3D, więc światła i cienie są wspólne (teren rzuca cień na graczy, gracze na teren); kamera tła widzi
## warstwę 1, kamera graczy warstwę 2.
##
## Co jest w 3D: geometria z mapy ASCII (`level3d.gd`), niebo, mgła głębi, księżyc; gracze jako modele z `char3d.gd` (model i broń wyjęte ze świata
## podglądu — poza liczy dalej `Char3D.update()`); wrogowie, bossowie i gniazda jako modele 3D z `enemy3d.gd` (billboardy `AnimatedSprite3D` z arkuszy HD tylko przy braku modelu); wszystkie `PointLight2D` świata
## jako światła 3D (do kilkunastu najbliższych). Pozostałe warstwy dynamiczne 2D (pociski, cząsteczki, rekwizyty, pickupy, HUD) zostają bez zmian.
## Kamera 3D jest dopasowana do Camera2D: płaszczyzna z = 0 pokrywa się z kadrem 2D (zoom, wstrząsy, „Camera zoom”).

const Level3D := preload("res://scripts/level3d.gd")
const Lights := preload("res://scripts/lights.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Enemy3D := preload("res://scripts/enemy3d.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Weapons := preload("res://scripts/weapons.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Weather := preload("res://scripts/weather.gd")
const Backdrop3D := preload("res://scripts/backdrop3d.gd")

const PX := Level3D.PX
const FOV := 40.0
const MAX_LIGHTS := 14
const SHADOW_LIGHTS := 5
const LAYER_WORLD := 1                     ## warstwa wizualna terenu, lasu, wrogów
const LAYER_ACTORS := 2                    ## warstwa wizualna graczy (modele 3D)
const ACTOR_AMBIENT := 0.09                ## światło otoczenia dla modeli graczy (tylko warstwa 2)
const ACTOR_HDRI_MISSION := "res://art/world3d/hdri/kloppenheim_07.hdr"          ## Poly Haven „Kloppenheim 07": noc, pole, zachmurzenie
const ACTOR_HDRI_HUB := "res://art/world3d/hdri/debris_basement_corridor.hdr"   ## Poly Haven „Debris Basement Corridor": betonowa piwnica
const ACTOR_SKY_MEAN := 0.34               ## średnia luminancja dawnego nieba proceduralnego (po sferze): HDRI o średniej 1 × ta wartość × `ACTOR_REFLECT` = ta sama jasność odbić
const ACTOR_REFLECT := 0.22                ## jasność „nieba odbić" warstwy graczy: tyle światła odbija stal trzymanej broni (nie więcej niż widać postać)
const LAYER_REFL := 8                      ## znacznik: broń na stojaku przyjmuje odbicia z sondy kryjówki (reflection_mask)
const LAYER_CARD := 16                     ## ekrany odbić widziane tylko przez sondę (żadna kamera ich nie rysuje)
const ACTOR_LIGHT := 1.0                   ## mnożnik świateł pomocniczych graczy (kontra, wypełnienie, obrys)
const AURA_RANGE_M := 2.6                   ## zasięg aury gracza na terenie w widoku 3D [m] (w 2D: 6 m)
const PROP_Z := 0.0                         ## oś skrzyń i beczek: płaszczyzna gry (postacie stoją na nich i przez nie skaczą)
const FLASH_UP_PX := 15.5                   ## wysokość źródła latarki nad stopami gracza w widoku 3D [px świata] (bark / broń)
const AURA_WORLD := 1.0                    ## mnożnik energii aury gracza dla terenu (zwykłe światło omni: 4)
const AURA_ACTOR := 0.55                    ## mnożnik energii aury gracza dla modeli graczy
const FOG_BEGIN_M := 2.0                    ## mgła głębi: początek za płaszczyzną gry [m]
const FOG_END_M := 62.0                     ## mgła głębi: pełna gęstość [m za płaszczyzną gry]
const WADE_SHOT_BLEND_M := 3.0              ## m: na tym odcinku lotu smuga pocisku brodzącego strzelca wraca z wysokości lufy modelu na tor symulacji
const EYE_UP_M := 2.2                       ## wysokość oka kamery ponad środkiem kadru [m] (punkt zbiegu nad głowami postaci)
const Z_BG := -60
const Z_FG := 1

var _level: Node2D
var _players: Node2D
var _vp_bg: SubViewport
var _vp_fg: SubViewport
var _world: Node3D
var _geo: Node3D
var _geo_key := ""
var _geo_alt: Node3D = null                 ## ukryta geometria mapy po zawale (budowana razem z mapą; zawał tylko ją podmienia — bez ok. 0,6 s przestoju)
var _geo_alt_key := ""
var _geo_alt_state := {}
var _rows: Array = []                    ## wiersze bieżącej mapy (rozbryzgi od kroków: rodzaj cieczy pod stopami)
var _splash := {}                        ## id węzła (gracz / wróg) → CPUParticles3D rozbryzgu
var _reeds_mat: ShaderMaterial           ## materiał trzciny przy cieczach (`Level3D.build_liquid_props`): uginanie przy przechodzących
var _reed_push := {}                     ## id postaci / wroga → wygładzona siła uginania 0..1
var _rustle_t := {}                      ## id → s do następnego szelestu
var _mud_mats: Array = []                ## materiały tafli błota (`LiquidTop_m_*`): odciski stóp w uniformie `prints`
var _prints := PackedVector4Array()      ## pierścień MUD_PRINTS odcisków: x, z (m), czas `_life` powstania, kierunek ±1
var _print_i := 0
var _print_last := {}                    ## id → [x ostatniego odcisku (m), strona stopy ±1]
var _wade := {}                          ## mapa brodzenia (`Level3D.wade_map`): o ile opuścić model stojący w cieczy
var _geo_t := 0.0
var _cam_a: Camera3D
var _cam_b: Camera3D
var _spr_bg: Sprite2D
var _spr_fg: Sprite2D
var _rigs := {}                          ## Node gracza → {actor, model, gun, root}
var _enemies := {}                       ## id węzła wroga 2D → [węzeł, Enemy3D] (modele 3D wrogów; null w drugim polu = brak modelu)
var _estate := {}                        ## id węzła wroga 2D → stan do wykrywania zdarzeń (żyje, błysk trafienia, zapowiedź ataku)
var _lights := {}                        ## id światła gry (Lights.GameLight) → [światło, Light3D]
var _frames_cache := {}
var _proj := {}                          ## id pocisku 2D → [Node2D, Node3D proxy]
var _props := {}                         ## id obiektu fizycznego 2D (prop.gd) → [Node2D, Node3D bryła]
var _cabinets := {}                      ## id gabloty (cabinet.gd) → {node, root, door, ghosts: [Node3D], open}
var _guns := {}                          ## id pickupu z bronią → [pickup, Node3D przegub modelu, sprite 2D, z]
var _casings := {}                       ## id ciała łuski 2D → [RigidBody2D, MeshInstance3D, losowe odchylenie]
var _rain: CPUParticles3D                ## deszcz 3D (smugi kropel)
var _ws_lamps := {}                      ## id warsztatu → lampa nad nim (Node3D w geometrii mapy)
var _globs := {}                         ## id plwociny / kwasu → [węzeł 2D, kula 3D]
var _boulders := {}                      ## id głazu Wołka → [węzeł 2D, model 3D]
var _fp := 0.0                           ## 0..1: przejście kamery do widoku z oczu gracza (oględziny broni)
var _fp_hidden: Node3D                   ## model gracza schowany na czas oględzin (do przywrócenia)
var _fp_last: Node2D                     ## ostatni gracz w oględzinach (kamera wraca od jego oczu)
var _fp_player: Node2D                   ## lokalny gracz w oględzinach (jego model jest wtedy schowany)
var _fp_item: Node                       ## broń na stojaku oglądana teraz albo przed chwilą (obraca się i ma własne światła)
var _fp_lights: Array = []               ## światło kluczowe i kontra oględzin (SpotLight3D)
var _rack_probe: ReflectionProbe         ## sonda odbić przy stojakach kryjówki
var _dots_mi: MeshInstance3D             ## świecące punkty (lampki, diody, oczy w mroku) i znaczniki na podłodze — jedna siatka
var _hid2d: Array = []                   ## węzły 2D schowane przez `self_modulate` (do przywrócenia w widoku 2D)
var _worldfx := {}                       ## id obiektu → {"src", "nodes": [węzły 3D], …} (dym generatora, tablica wyników)
var _surf_t := 0.0                       ## do następnego odświeżenia tekstur z rysunkiem 2D [s]
var _nestfx := {}                        ## id gniazda → [węzeł 2D, żar 3D]
var _ring_mi: MeshInstance3D             ## pierścienie alarmu wrogów (jedna siatka na wszystkie)
var _motes: CPUParticles3D               ## pył w powietrzu wokół kamery
var _leechfx := {}                       ## id Pijawki → [węzeł 2D, korzeń 3D efektów na wodzie]
var _lampfx := {}                        ## id lampy → [węzeł 2D, poświata żarówki]
var _bossfx := {}                        ## id Żyły → [węzeł 2D, korzeń 3D efektów]
var _mine_dust: Array = []               ## pył finału kopalni: [drobny pył, strużki] (CPUParticles3D)
var _mine_dust_key := Vector2i(-999, -999)   ## kafel kamery, dla którego wyznaczono punkty stropu
var _rain_open := 0.0                    ## 0..1: gracz jest nad poziomem podziemi (deszcz widać)
var _roof_key := "?"                     ## mapa, dla której policzono wysokości dachów
var _rain_splash: CPUParticles3D         ## plusk kropel na gruncie
var _sky_drift := Vector2.ZERO           ## przesunięcie chmur nieba (narasta z wiatrem pogody, `SKY_WIND`)
var _blood: Array = []                   ## kałuże krwi: [MeshInstance3D, promień docelowy, promień bieżący, wiek]
var _blood_shader: Shader
var _burn := {}                          ## id węzła 2D (plama ognia, płonące ciało, chmura dymu) → [węzeł, Node3D, rodzaj, koniec]
var _fires := {}                         ## id flary 2D → [węzeł, Node3D ognia, rodzaj, pierścień strefy albo null]
var _drawn := {}                         ## id węzła rysowanego kodem (radiostacja, mur) → [węzeł 2D, Node3D]
var _span: Array = []                    ## trasa drezyny (_rail_span)
var _span_map := ""
var _item_tuned := {}                    ## nazwy modeli z już dostrojonymi materiałami
var _item_scenes := {}                   ## nazwa przedmiotu → PackedScene modelu 3D albo null
var _items := {}                         ## id sprite'a przedmiotu HD → [Sprite2D, MeshInstance3D, materiał, z, ukryte węzły 2D]
var _cache_piles := {}                   ## id sprite'a skrzyni z mapy → klucze broni, z których zbudowano jej stertę (_build_cache_pile)
var _scan_t := 0.0
var _life := 0.0
var _saved := false

func setup(level: Node2D, players: Node2D) -> void:
	_level = level
	_players = players
	name = "View3D"
	_vp_bg = SubViewport.new()
	_vp_bg.name = "VpWorld"
	_vp_bg.transparent_bg = false
	_vp_bg.msaa_3d = Viewport.MSAA_2X
	_vp_bg.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp_bg)
	_vp_fg = SubViewport.new()
	_vp_fg.name = "VpActors"
	_vp_fg.transparent_bg = true
	_vp_fg.msaa_3d = Viewport.MSAA_2X
	_vp_fg.world_3d = _vp_bg.world_3d                     # ten sam świat 3D: wspólne światła i cienie
	_vp_fg.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp_fg)
	_world = Node3D.new()
	_world.name = "World"
	_vp_bg.add_child(_world)
	_cam_a = Camera3D.new()
	_cam_a.fov = FOV
	_cam_a.near = 0.3
	_cam_a.far = 160.0
	_cam_a.cull_mask = LAYER_WORLD | Level3D.LAYER_FOREST       # las ma dodatkową warstwę (światło `MoonRim` tylko na nim)
	_cam_a.current = true
	_vp_bg.add_child(_cam_a)
	_cam_b = Camera3D.new()
	_cam_b.fov = FOV
	_cam_b.near = 0.3
	_cam_b.far = 160.0
	_cam_b.cull_mask = LAYER_ACTORS
	_cam_b.current = true
	_vp_fg.add_child(_cam_b)
	_geo = Node3D.new()
	_geo.name = "Geometry"
	_world.add_child(_geo)
	# szczątki wczytane z góry: przy pierwszym zabójstwie w sesji modele (z teksturami) wczytywały się synchronicznie — przestój ok. 0,3–0,4 s
	for names in GIB_MODELS:
		for gn in names:
			Level3D.model_mesh(String(gn))
	# światło tylko dla graczy (warstwa 2): prawie sama kontra (dwa światła zza postaci) — obrys czytelny w ciemności, a bryłę modeluje światło sceny
	# (aura, latarka, flara, ognisko), więc postać nie świeci własnym światłem
	for spec in [[Vector3(-0.35, -0.6, -0.7), Color(0.9, 0.88, 0.8), 0.14], [Vector3(0.25, -0.35, 0.9), Color(0.72, 0.82, 1.0), 0.85], [Vector3(-0.6, -0.15, 0.75), Color(0.6, 0.7, 1.0), 0.35]]:
		var dl := DirectionalLight3D.new()
		dl.basis = Basis.looking_at(spec[0], Vector3.UP)
		dl.light_color = spec[1]
		dl.light_energy = float(spec[2]) * ACTOR_LIGHT
		dl.light_cull_mask = LAYER_ACTORS
		dl.light_volumetric_fog_energy = 0.0               # mgła wolumetryczna nie zna masek warstw — kontra postaci nie może jej rozświetlać
		dl.layers = LAYER_WORLD | LAYER_ACTORS             # Forward+: kamera odcina też same światła maską warstw — światło musi być widoczne dla obu kamer
		_world.add_child(dl)
	_spr_bg = Sprite2D.new()
	_spr_bg.name = "WorldImage"
	_spr_bg.z_index = Z_BG
	_spr_bg.texture = _vp_bg.get_texture()
	_spr_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_spr_bg.material = Lights.unshaded()                      # bez mnożenia przez CanvasModulate „ciemności” 2D (3D ma własne światło)
	add_child(_spr_bg)
	_spr_fg = Sprite2D.new()
	_spr_fg.name = "ActorsImage"
	Vfx.view3d = self
	_spr_fg.z_index = Z_FG
	_spr_fg.texture = _vp_fg.get_texture()
	_spr_fg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_spr_fg.material = Lights.unshaded()                      # bez mnożenia przez CanvasModulate „ciemności” 2D (3D ma własne światło)
	add_child(_spr_fg)

# ---------------------------------------------------------------- cykl życia

func release() -> void:
	Vfx.view3d = null
	if _fp_hidden != null and is_instance_valid(_fp_hidden):
		_fp_hidden.visible = true
	for ci in [_level, _players]:
		if ci is CanvasItem:
			(ci as CanvasItem).modulate.a = 1.0
	for id in _proj.keys():
		var pr: Array = _proj[id]
		if is_instance_valid(pr[0]):
			(pr[0] as CanvasItem).self_modulate = Color.WHITE
	_proj.clear()
	for id in _props.keys():
		var pp: Array = _props[id]
		if is_instance_valid(pp[0]):
			(pp[0] as CanvasItem).modulate = Color.WHITE
	_props.clear()
	for id in _drawn.keys():
		if is_instance_valid(_drawn[id][0]):
			(_drawn[id][0] as CanvasItem).modulate = Color.WHITE
	_drawn.clear()
	_fires.clear()
	for h2 in _hid2d:
		if is_instance_valid(h2):
			(h2 as CanvasItem).self_modulate = Color.WHITE
	_hid2d.clear()
	for id in _worldfx.keys():
		for wn in _worldfx[id]["nodes"]:
			if is_instance_valid(wn):
				(wn as Node).queue_free()
	_worldfx.clear()
	for id in _nestfx.keys():
		if is_instance_valid(_nestfx[id][1]):
			(_nestfx[id][1] as Node).queue_free()
	_nestfx.clear()
	for tab in [_globs, _boulders, _bossfx, _leechfx, _lampfx]:
		for id in tab.keys():
			if is_instance_valid(tab[id][0]):
				(tab[id][0] as CanvasItem).self_modulate = Color.WHITE
			if is_instance_valid(tab[id][1]):
				(tab[id][1] as Node).queue_free()
		tab.clear()
	for dp in _mine_dust:
		if is_instance_valid(dp):
			(dp as Node).queue_free()
	_mine_dust.clear()
	_mine_dust_key = Vector2i(-999, -999)
	for id in _burn.keys():
		if is_instance_valid(_burn[id][0]) and String(_burn[id][2]) != "host":
			(_burn[id][0] as CanvasItem).self_modulate = Color.WHITE
	_burn.clear()
	for id in _casings.keys():
		if is_instance_valid(_casings[id][0]):
			(_casings[id][0] as CanvasItem).modulate = Color.WHITE
		if is_instance_valid(_casings[id][1]):
			(_casings[id][1] as Node).queue_free()
	_casings.clear()
	_guns.clear()
	for id in _items.keys():
		var itv: Array = _items[id]
		var hid: Array = itv[4]
		if not hid.is_empty() and is_instance_valid(hid[0]):
			(hid[0] as CanvasItem).self_modulate = Color.WHITE
		for k in range(1, hid.size()):
			if is_instance_valid(hid[k]):
				(hid[k] as CanvasItem).visible = true
	_items.clear()
	for p in _rigs.keys():
		_release_rig(p)
	_rigs.clear()
	for id in _enemies.keys():
		var pr: Array = _enemies[id]
		if is_instance_valid(pr[0]):
			for c in (pr[0] as Node).get_children():
				if c is AnimatedSprite2D:
					(c as AnimatedSprite2D).self_modulate = Color.WHITE
		if pr[1] != null and is_instance_valid(pr[1]):
			(pr[1] as Node).queue_free()
	_enemies.clear()
	_estate.clear()
	queue_free()

func _process(delta: float) -> void:
	if _level == null or not is_instance_valid(_level):
		return
	_life += delta
	if _life > 3.0 and "--view3dtoggle" in OS.get_cmdline_user_args():
		release()                                       # dev: sprawdzenie, że wyłączenie przywraca obraz 2D
		return
	if _life > 2.5 and not _saved:
		for ar in OS.get_cmdline_user_args():
			if ar.begins_with("--view3dsave="):                 # dev: zapis obrazu warstwy graczy (PNG z alfą) do oceny jasności modeli
				_saved = true
				_vp_fg.get_texture().get_image().save_png(ar.substr(13))
			elif ar.begins_with("--view3dsavebg="):                 # dev: zapis obrazu świata 3D (bez interfejsu i warstw 2D) — ocena materiałów w nocnym oświetleniu
				_saved = true
				_vp_bg.get_texture().get_image().save_png(ar.substr("--view3dsavebg=".length()))
	_sync_camera()
	_geo_t -= delta
	if _geo_t <= 0.0:
		_geo_t = 0.25
		_sync_geometry()
	_sync_rigs()
	_sync_enemies(delta)
	_sync_reeds(delta)
	_sync_mud_prints()
	_sync_projectiles()
	_sync_props()
	_sync_items()
	_build_rails()
	_sync_drawn()
	_sync_launch_doors()
	_sync_hub_props()
	_sync_world_notes()
	_sync_guns()
	_sync_cabinets(delta)
	_sync_fires()
	_sync_weapon_fx()
	_sync_casings()
	_sync_burning()
	_sync_blood(delta)
	_sync_drag_trails()
	_sync_weather(delta)
	_sync_mine_dust()
	_sync_globs()
	_sync_boulders()
	_sync_boss_fx()
	_sync_leech_fx()
	_sync_lamps()
	_sync_nests()
	_sync_enemy_rings()
	_sync_ambient()
	_sync_world_fx(delta)
	# widok z oczu gracza: jego własny model znika z kadru (stałby tuż przed kamerą) i wraca, gdy kamera odjeżdża
	var hide_me: Node3D = null
	if _fp > 0.35 and _fp_last != null and is_instance_valid(_fp_last) and _rigs.has(_fp_last):
		hide_me = _rigs[_fp_last].get("actor") as Node3D
	if _fp_hidden != null and is_instance_valid(_fp_hidden) and _fp_hidden != hide_me:
		_fp_hidden.visible = true
	_fp_hidden = hide_me
	if _fp_hidden != null and is_instance_valid(_fp_hidden):
		_fp_hidden.visible = false
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_scan_lights()
	_sync_lights()

# ---------------------------------------------------------------- kamera i obraz

func _res_scale() -> float:
	match Settings.quality_idx:
		0:
			return 0.5
		1:
			return 0.75
	return 1.0

func _sync_camera() -> void:
	var c2 := get_viewport().get_camera_2d()
	if c2 == null:
		return
	var vis := get_viewport().get_visible_rect().size
	var win := Vector2(get_window().size)
	var scale := minf(win.x / maxf(vis.x, 1.0), win.y / maxf(vis.y, 1.0))
	var h_px := win.y / (maxf(scale, 0.01) * maxf(c2.zoom.y, 0.01))        # wysokość kadru 2D na płaszczyźnie gry [px świata]
	var dist := (h_px * PX * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var ctr := c2.get_screen_center_position()
	# oko kamery stoi EYE_UP_M ponad środkiem kadru, a bryła widzenia jest przesunięta w dół o tyle samo (obiektyw „shift”): płaszczyzna gry
	# pokrywa się z kadrem 2D jak dotąd (celowanie bez zmian), ale punkt zbiegu leży nad głowami — widać wierzch gruntu i kładek zamiast ich spodów
	var xf := Transform3D(Basis.IDENTITY, Vector3(ctr.x * PX, -ctr.y * PX + EYE_UP_M, dist))
	var near := 0.3
	var fsize := 2.0 * near * tan(deg_to_rad(FOV * 0.5))
	var foff := Vector2(0.0, -EYE_UP_M * near / dist)
	# oględziny broni ([F], weapon_controller.gd): kamera dojeżdża do oczu lokalnego gracza i patrzy w głąb sceny (stojak, ściana, las);
	# bryła widzenia przechodzi z przesuniętej na zwykłą perspektywę o szerszym kącie. Tło rozmywa ekran oględzin (weapon_inspect.gd).
	_fp_player = null
	for p in _rigs.keys():
		if is_instance_valid(p) and p.get("is_bot") == false and (p as Node).is_multiplayer_authority() and p.get("weapons") != null and p.weapons.inspect_item != null:
			_fp_player = p
	_fp = move_toward(_fp, 1.0 if _fp_player != null else 0.0, get_process_delta_time() * 3.2)
	if _fp <= 0.0:                                          # po oględzinach światła oględzin gasną do zera
		for sl in _fp_lights:
			(sl as SpotLight3D).light_energy = 0.0
	var fe := smoothstep(0.0, 1.0, _fp)
	if _fp_player != null:
		_fp_last = _fp_player
		_fp_item = _fp_player.weapons.inspect_item
	if fe > 0.0 and _fp_last != null and is_instance_valid(_fp_last):
		var eye := Level3D.px_to_m(_fp_last.global_position) + Vector3(0.0, FP_EYE_M, FP_Z)
		if _fp_item != null and is_instance_valid(_fp_item) and _fp_item.has_meta("cab_x"):
			# gablota: kamera na wprost gabloty, na wysokości jej środka — cała gablota w kadrze (jak na zdjęciach-wzorach)
			eye = Level3D.px_to_m(Vector2(float(_fp_item.get_meta("cab_x")), (_fp_item as Node2D).global_position.y + 2.0)) + Vector3(0.0, CAB_H * 0.52, FP_Z)
		xf.origin = xf.origin.lerp(eye, fe)
		dist = lerpf(dist, FP_Z + 0.5, fe)
		fsize = 2.0 * near * tan(deg_to_rad(lerpf(FOV, FP_FOV, fe) * 0.5))
		foff *= 1.0 - fe
	for ci in [_level, _players]:                              # etykiety i paski 2D nad postaciami nie pasują do widoku z oczu — gasną
		if ci is CanvasItem and absf((ci as CanvasItem).modulate.a - (1.0 - fe)) > 0.001:
			(ci as CanvasItem).modulate.a = 1.0 - fe
	_cam_a.set_frustum(fsize, foff, near, 160.0)
	_cam_b.set_frustum(fsize, foff, near, 160.0)
	_cam_a.global_transform = xf
	if _cam_a.environment != null:                          # mgła głębi zaczyna się tuż za płaszczyzną gry
		_cam_a.environment.fog_depth_begin = dist + FOG_BEGIN_M
		_cam_a.environment.fog_depth_end = dist + FOG_END_M
		_cam_a.environment.volumetric_fog_length = dist + 14.0
	_cam_b.global_transform = xf
	# rozmiar renderu (skala wg „Effects quality”) i dopasowanie sprite'ów do kadru: środek na środku kamery, wysokość = wysokość kadru
	var rs := _res_scale()
	var sz := Vector2i(maxi(int(win.x * rs), 64), maxi(int(win.y * rs), 64))
	if _vp_bg.size != sz:
		_vp_bg.size = sz
		_vp_fg.size = sz
	var k := h_px / float(sz.y)
	for s in [_spr_bg, _spr_fg]:
		(s as Sprite2D).global_position = ctr
		(s as Sprite2D).scale = Vector2(k, k)

# ---------------------------------------------------------------- świat statyczny

func _sync_geometry() -> void:
	var rows: Array = _level.get("_map")
	if rows == null or rows.is_empty():
		return
	var key := "%s:%d:%s" % [String(_level.get("map_id")), str(rows).hash(), str(get_tree().get_first_node_in_group("handcar") != null)]
	if key == _geo_key:
		return
	_geo_key = key
	_span_map = ""
	for ch in _geo.get_children():
		ch.queue_free()
	if _geo_alt != null and is_instance_valid(_geo_alt) and key == _geo_alt_key:
		# zawał (finał 1.1): gotowa geometria „po zawale” przechodzi do sceny; środowisko i kamery zostają
		for ch in _geo_alt.get_children():
			ch.reparent(_geo, false)
		_geo_alt.queue_free()
		_geo_alt = null
		_set_static_lists(_geo_alt_state["lists"])
		_apply_geo_state(_geo_alt_state)
		return
	_drop_geo_alt()
	var amb: Color = _level.get("ambient") if _level.get("ambient") != null else Color(0.0245, 0.0266, 0.0406)
	var hub := String(_level.get("objective")) == "hub"
	Level3D.build_environment(_geo, amb, not hub, Settings.quality_idx)
	var we := _geo.get_node("Env") as WorldEnvironment
	var env_a := we.environment
	we.queue_free()                                       # środowisko przypisujemy kamerom (osobno dla tła i graczy)
	_cam_a.environment = env_a
	var env_b := env_a.duplicate() as Environment         # warstwa graczy: bez nieba i glow (przezroczyste tło), to samo światło otoczenia i mgła
	env_b.background_mode = Environment.BG_CLEAR_COLOR
	env_b.sky = _actor_reflection_sky(hub)                 # tło zostaje przezroczyste; niebo służy tylko odbiciom na metalu trzymanej broni
	env_b.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env_b.glow_enabled = false
	env_b.ssao_enabled = false
	env_b.ssil_enabled = false
	env_b.volumetric_fog_enabled = false
	# jasność postaci: osobne, łagodne światło otoczenia i słabsza mgła tylko dla warstwy graczy (modele leżą w płaszczyźnie gry, kilkanaście metrów od kamery)
	env_b.ambient_light_color = Color(0.50, 0.56, 0.70)
	env_b.ambient_light_energy = ACTOR_AMBIENT
	env_b.fog_enabled = false
	_cam_b.environment = env_b
	_apply_geo_state(_build_world(_geo, rows, hub))
	# mapa z zawałem w danych (finał 1.1): geometria „po zawale” od razu, w czasie wczytywania (ukryta, bez przetwarzania)
	var cr = _level.get("collapse_rects")
	if cr is Array and not (cr as Array).is_empty() and (_level.get("_blocks") as Array).is_empty() and _level.has_method("rows_after"):
		var after: Array = _level.call("rows_after", cr)
		if after != rows:
			_geo_alt = Node3D.new()
			_geo_alt.name = "GeometryAfterCollapse"
			_geo_alt.visible = false
			_geo_alt.process_mode = Node.PROCESS_MODE_DISABLED
			_world.add_child(_geo_alt)
			var keep := _static_lists()                      # builders zapisują materiały wiatru / mgły i trzciny statycznie — widoczna mapa zostaje przy swoich
			_geo_alt_state = _build_world(_geo_alt, after, hub)
			_geo_alt_state["lists"] = _static_lists()
			_set_static_lists(keep)
			_geo_alt_key = "%s:%d:%s" % [String(_level.get("map_id")), str(after).hash(), str(get_tree().get_first_node_in_group("handcar") != null)]

## Statyczne listy builders (materiały wiatru kart lasu i runa, materiały konstrukcji tła pod mgłę, punkty trzcin) — należą do jednej geometrii naraz.
func _static_lists() -> Dictionary:
	return {"cards": Level3D._wind_cards.duplicate(), "grass": Level3D._wind_grass.duplicate(), "reeds": Level3D.reed_spots, "bd": Backdrop3D._mats.duplicate()}

func _set_static_lists(l: Dictionary) -> void:
	Level3D._wind_cards = l["cards"]
	Level3D._wind_grass = l["grass"]
	Level3D.reed_spots = l["reeds"]
	Backdrop3D._mats = l["bd"]
	for m in Level3D._wind_cards + Level3D._wind_grass:                 # wiatr mógł się zmienić od zbudowania tej geometrii
		(m as ShaderMaterial).set_shader_parameter("amp", Level3D._wind.x)
		(m as ShaderMaterial).set_shader_parameter("lean", Level3D._wind.y)

func _drop_geo_alt() -> void:
	if _geo_alt != null and is_instance_valid(_geo_alt):
		_geo_alt.queue_free()
	_geo_alt = null
	_geo_alt_key = ""
	_geo_alt_state = {}

## Geometria mapy z wierszy `rows` pod węzłem `root` (teren, kładki, ciecze, dekale, runo, dekoracje, las, tło, mgła); zwraca stan widoku z niej
## wyliczony (`_apply_geo_state`). Bez środowiska i kamer — te ustawia `_sync_geometry` raz na mapę.
func _build_world(root: Node3D, rows: Array, hub: bool) -> Dictionary:
	var span := _rail_span()
	var trench := {}
	if not span.is_empty():
		trench = {"row": int(float(span[2]) / 16.0), "c0": int(float(span[0]) / 16.0), "c1": int(float(span[1]) / 16.0)}
	Level3D.build_level(root, rows, trench)
	Backdrop3D.build_frames(root, rows)
	Level3D.set_streams(_level.get("streams") if _level.get("streams") != null else [])
	Level3D.build_liquids(root, rows)
	Level3D.build_liquid_props(root, rows)
	Level3D.build_wade_veils(root, rows, LAYER_ACTORS)
	Level3D.build_decals(root, rows)
	Level3D.build_undergrowth(root, rows)
	Level3D.build_front_edge(root, rows)
	_build_deco(root)
	Level3D.build_fog_volumes(root, rows, 0.02 if hub else 0.035)
	if not hub:
		Level3D.build_forest_floor(root, rows)
		Level3D.build_streams(root, rows)
		Level3D.build_forest(root, rows)
		Level3D.build_canopy_haze(root, rows)
		Backdrop3D.build(root, rows, _level.get("backdrop") if _level.get("backdrop") != null else [])
		Level3D.build_ground_fog(root, rows)
	var mud: Array = []
	for mi in root.get_children():
		if mi is MeshInstance3D and String(mi.name).begins_with("LiquidTop_m_"):
			mud.append((mi as MeshInstance3D).material_override)
	var reeds := root.get_node_or_null("ShoreReeds") as MeshInstance3D
	return {"rows": rows, "reeds": reeds.material_override as ShaderMaterial if reeds != null else null, "mud": mud}

## Stan widoku zależny od zbudowanej geometrii (materiały trzcin i błota, ślady stóp w błocie, mapa brodzenia).
func _apply_geo_state(st: Dictionary) -> void:
	_reeds_mat = st.get("reeds")
	_mud_mats.clear()
	_mud_mats.append_array(st.get("mud", []))
	_prints = PackedVector4Array()
	_prints.resize(MUD_PRINTS)
	_print_i = 0
	_print_last.clear()
	_rows = st.get("rows", [])
	_wade = Level3D.wade_map(_rows)

# ---------------------------------------------------------------- gracze (modele 3D)

func _sync_rigs() -> void:
	var alive := {}
	for p in _players.get_children():
		if p.is_queued_for_deletion():
			continue
		alive[p] = true
		var c3 = p.get("c3d")
		if c3 == null or not is_instance_valid(c3) or not c3.ready_ok:
			continue                                 # model jeszcze niegotowy
		if not _rigs.has(p):
			_make_rig(p, c3)
		var rig: Dictionary = _rigs[p]
		var actor: Node3D = rig["actor"]
		var model_now = c3._char_node                      # zmiana wyglądu (warsztat): Char3D buduje nowy model w swoim świecie — przepinamy go do aktora
		if model_now != null and is_instance_valid(model_now) and (model_now as Node).get_parent() != actor:
			(model_now as Node).reparent(actor, false)
			for mi in (model_now as Node).find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.layers == 2:
					m.visible = false                          # kopie z przebiegu normalnych sprite'a 2D
				else:
					m.layers = LAYER_ACTORS
			rig["model"] = model_now
		var gun_now = c3._gun                              # zmiana broni: Char3D tworzy nowy model w swoim świecie — przepinamy go do aktora
		if gun_now != null and is_instance_valid(gun_now) and (gun_now as Node).get_parent() != actor:
			(gun_now as Node).reparent(actor, false)
			for mi in (gun_now as Node).find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).layers = LAYER_ACTORS
			rig["gun"] = gun_now
			if c3._gun_n != null:
				c3._gun_n.visible = false
		# na drezynie: tor leży w korycie przed peronem, a pokład jest równo z peronem — pasażer przesuwa się tylko na oś toru (ku kamerze)
		var want_lift := 0.0
		for hc in get_tree().get_nodes_in_group("handcar"):
			if hc.aboard(p):
				want_lift = TRACK_ZC
		rig["lift"] = lerpf(float(rig.get("lift", 0.0)), want_lift, 0.25)
		rig["wade"] = _wade_step(float(rig.get("wade", 0.0)), p.global_position)
		actor.position = Level3D.px_to_m(p.global_position) + Vector3(0.0, -float(c3.sink_m) - float(rig["wade"]), float(rig["lift"]))
		_splash_update(actor, p.global_position, absf(float(p.get("velocity").x)) if p.get("velocity") != null else 0.0, LAYER_ACTORS, float(rig["wade"]))
		actor.basis = Basis(Vector3.UP, float(c3.model_yaw))         # zwrot postaci: obrót z animacją (Char3D.TURN_TIME), nie odbicie lustrzane
		c3._on_screen = true                       # poza liczymy zawsze (bez powiadomień o ekranie 2D)
	for p in _rigs.keys():
		if not alive.has(p) or not is_instance_valid(p):
			_release_rig(p)
			_rigs.erase(p)

func _make_rig(p: Node, c3: Node) -> void:
	var actor := Node3D.new()
	actor.name = "Actor_" + String(p.name)
	_world.add_child(actor)
	var model: Node = c3._char_node
	var gun: Node = c3._gun
	var root: Node = c3._root3d
	model.reparent(actor, false)
	if gun != null:
		gun.reparent(actor, false)
	# kopie siatek z warstwy normalnych (przebieg normalnych sprite'a 2D) chowamy; siatki modelu i broni przenosimy na warstwę graczy
	for mi in actor.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.layers == 2:
			m.visible = false
		else:
			m.layers = LAYER_ACTORS
	if c3._gun_n != null:
		c3._gun_n.visible = false
	c3._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	c3._vpn.render_target_update_mode = SubViewport.UPDATE_DISABLED
	c3._sprite.visible = false
	_rigs[p] = {"actor": actor, "model": model, "gun": gun, "root": root}

func _release_rig(p) -> void:
	if not _rigs.has(p):
		return
	var rig: Dictionary = _rigs[p]
	if rig.has("wfx"):                                         # efekty strzału 3D: zwolnij i przywróć rysunek 2D
		if is_instance_valid(rig["wfx"]["root"]):
			(rig["wfx"]["root"] as Node).queue_free()
	var c3 = p.get("c3d") if is_instance_valid(p) else null
	if c3 != null and is_instance_valid(c3):
		var root: Node = rig["root"]
		if is_instance_valid(rig["model"]) and is_instance_valid(root):
			(rig["model"] as Node).reparent(root, false)
		if rig["gun"] != null and is_instance_valid(rig["gun"]) and is_instance_valid(root):
			(rig["gun"] as Node).reparent(root, false)
		if is_instance_valid(root):
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if not m.visible and m.layers == 2:
					m.visible = true
				elif m.layers == LAYER_ACTORS:
					m.layers = 1
		c3._vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		c3._vpn.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		c3._sprite.visible = true
		if c3._gun_n != null:
			c3._gun_n.visible = true
	if is_instance_valid(rig["actor"]):
		(rig["actor"] as Node).queue_free()

# ---------------------------------------------------------------- billboardy (wrogowie i reszta animowanych sprite'ów)

## Rodzaj wroga, jeśli ma model 3D (`enemy3d.gd`), inaczej "".
func _enemy_kind(n: Node) -> String:
	var k = n.call("view_info").get("kind") if n.has_method("view_info") else n.get("kind")        # rekwizyty w grupie „enemies” (skrzynie, beczki) nie mają kontraktu ani modelu
	return String(k) if k != null and Enemy3D.has_model(String(k)) else ""

## Wrogowie z modelem 3D: model stoi na pozycji węzła 2D, poza z nazwy animacji sprite'a (`Body`), sprite'y 2D są przezroczyste.
func _sync_enemies(delta: float) -> void:
	for g in ["enemies", "roamers", "boss", "nests"]:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node2D) or n.is_queued_for_deletion():
				continue
			var id: int = n.get_instance_id()
			if _enemies.has(id):
				continue
			var k := _enemy_kind(n)
			if k == "":
				continue
			var e := Enemy3D.new()
			if not e.setup(k, k == "stalker"):
				e.free()
				_enemies[id] = [n, null]                  # bez modelu nic nie widać (wszystkie rodzaje mają modele)
				continue
			for c in n.get_children():
				if c is AnimatedSprite2D:
					(c as AnimatedSprite2D).self_modulate = Color(1, 1, 1, 0)
			_set_layer(e, LAYER_WORLD)
			_world.add_child(e)
			_enemies[id] = [n, e]
	var cam_x := _cam_a.global_position.x
	for id in _enemies.keys():
		var pair: Array = _enemies[id]
		var src_v = pair[0]
		var e_v = pair[1]
		if not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion():
			if e_v != null and is_instance_valid(e_v):
				(e_v as Node).queue_free()
			_enemies.erase(id)
			_estate.erase(id)
			continue
		if e_v == null:
			continue
		var e: Node3D = e_v
		var src: Node2D = src_v
		var body := src.get_node_or_null("Body") as AnimatedSprite2D
		var pos := Level3D.px_to_m(body.global_position if body != null else src.global_position)
		# zdarzenia z symulacji 2D → klipy modelu: śmierć (alive = false; węzeł jest tylko chowany), trafienie (błysk), atak (koniec zapowiedzi)
		var st: Dictionary = _estate.get(id, {"alive": true, "flash": false, "wind": false, "py": NAN, "vy": 0.0})
		var info: Dictionary = src.call("view_info")                          # kontrakt widoku (enemy.gd: view_info) — wszystkie rodzaje z modelem go mają
		var alive: bool = bool(info["alive"])
		var winding: bool = bool(info["winding"])
		if bool(st["alive"]) and not alive:
			e.call("die")
		elif not bool(st["alive"]) and alive:
			e.call("revive")
		var dying: bool = not alive and not bool(e.get("finished"))
		var flash: bool = body != null and bool(info["flash"])
		if alive and body != null:
			if flash and not bool(st["flash"]):
				e.call("trigger", "hit")
			elif bool(st["wind"]) and not winding:
				e.call("trigger", "attack")
		st["alive"] = alive
		st["flash"] = flash
		st["wind"] = winding
		_estate[id] = st
		var show: bool = (src.is_visible_in_tree() or dying) and body != null
		var near: bool = absf(pos.x - cam_x) < 90.0
		if dying and not near:
			e.set("finished", true)
		e.visible = show and near and not (not alive and bool(e.get("finished")))
		if not e.visible:
			continue
		var sp_v2 = float(st.get("vx", 0.0))
		var wades: bool = not ["cma", "nest", "vein", "leech"].has(String(e.get("kind")))
		st["wade"] = _wade_step(float(st.get("wade", 0.0)), src.global_position) if wades else 0.0
		e.position = pos + Vector3(0.0, -float(st["wade"]), 0.3)          # brodzenie: tafla (warstwa świata) sama zakrywa zanurzone nogi
		if wades:
			_splash_update(e, src.global_position, sp_v2, LAYER_WORLD, float(st["wade"]))
		var sf := body.sprite_frames
		var anim := body.animation
		var nfr := sf.get_frame_count(anim) if sf != null and sf.has_animation(anim) else 1
		var lp := sf.get_animation_loop(anim) if sf != null and sf.has_animation(anim) else true
		var md: Color = body.modulate if alive else Color.WHITE
		# sygnały z 2D przekazywane kolorem (biały błysk trafienia, czerwone pulsowanie zapowiedzi ciosu) w 3D pokazuje animacja modelu:
		# klip trafienia i krew, poza zapowiedzi / wstanie z siadu i rozżarzone oczy — model nie zmienia koloru
		if flash or winding:
			md = Color(1.0, 1.0, 1.0, md.a)
		# prędkość pionowa z przesunięcia (u klientów węzeł wroga ma tylko pozycję): skok / spadanie → poza lotu w modelu 3D
		var ypx := body.global_position.y if body != null else src.global_position.y
		var vy_now := 0.0
		if not is_nan(float(st["py"])) and delta > 0.0 and delta < 0.1:
			vy_now = (ypx - float(st["py"])) / delta
		st["py"] = ypx
		var xpx := body.global_position.x if body != null else src.global_position.x
		var vx_now := 0.0
		if not is_nan(float(st.get("px", NAN))) and delta > 0.0 and delta < 0.1:
			vx_now = absf(xpx - float(st["px"])) / delta
		st["px"] = xpx
		st["vx"] = lerpf(float(st.get("vx", 0.0)), vx_now, 0.5)
		st["vy"] = lerpf(float(st["vy"]), vy_now, 0.45)
		_estate[id] = st
		e.call("pose", delta, anim, body.flip_h, md, float(body.frame) + body.frame_progress, nfr, lp, float(st["vy"]), int(info["sp"]), bool(info.get("alert", false)))      # sp: stan specjalny (Wołek: szarża, oszołomienie); alert: reakcja „zauważył" (oczy)

## Rodzaj cieczy pod stopami (0 błoto, 1 olej, 2 woda), −1 gdy stoi na zwykłym gruncie.
func _liquid_kind(px: Vector2) -> int:
	if _rows.is_empty():
		return -1
	var c := int(floor(px.x / 16.0))
	var r := int(floor((px.y + 1.0) / 16.0))
	var ch := Level3D._ch(_rows, c, r)
	if ch == "m" or ch == "O" or ch == "~":
		if not Level3D.is_solid_ch(Level3D._ch(_rows, c, r - 1)):
			return {"m": 0, "O": 1, "~": 2}[ch]
	return -1

## Brodzenie: głębokość zanurzenia modelu goni docelową (`Level3D.wade_at`) — wejście do wody, skok i wyjście bez szarpnięcia.
const REED_PUSHERS := 8                  ## tyle postaci naraz ugina trzcinę (tablica w shaderze REED_SHADER)
const REED_NEAR_X := 0.55                ## m: kępa bliżej niż tyle w poziomie od stóp — postać idzie przez trzcinę
const REED_NEAR_Z := 0.75                ## m: …i tyle w głąb (kępy daleko za płaszczyzną gry stoją w spokoju)

## Trzcina przy cieczach: przechodzący gracze i wrogowie uginają kępy (shader) i szeleszczą nimi (tylko dźwięk w świecie, bez Uwagi —
## kosmetyka lokalna, z pozycji i prędkości już zsynchronizowanych postaci). Szelest wroga w trzcinach to wskazówka dla ucha.
func _sync_reeds(delta: float) -> void:
	if _reeds_mat == null or Level3D.reed_spots.is_empty():
		return
	var spots := Level3D.reed_spots
	var cam_x := _cam_a.global_position.x
	var cand: Array = []                                   # [odległość od kamery, Vector4 dla shadera]
	var seen := {}
	for grp in ["players", "enemies"]:
		for n in get_tree().get_nodes_in_group(grp):
			var b := n as Node2D
			if b == null or not is_instance_valid(b) or not b.is_visible_in_tree() or b.get("dead") == true:
				continue
			var feet := Level3D.px_to_m(b.global_position)
			if absf(feet.x - cam_x) > 30.0:
				continue
			var fz := 0.0 if grp == "players" else 0.3
			var inside := false
			for sp in spots:
				if absf(sp.x - feet.x) < REED_NEAR_X and absf(sp.z - fz) < REED_NEAR_Z and feet.y > sp.y - 0.5 and feet.y < sp.y + 0.8:
					inside = true
					break
			var id := b.get_instance_id()
			seen[id] = true
			var v = b.get("velocity")
			var vx: float = absf((v as Vector2).x) if v is Vector2 else 0.0
			var want := (0.45 + 0.55 * clampf(vx / 80.0, 0.0, 1.0)) if inside else 0.0
			var cur := move_toward(float(_reed_push.get(id, 0.0)), want, delta * (5.0 if want > float(_reed_push.get(id, 0.0)) else 1.6))      # trzcina wraca wolniej, niż się ugina
			_reed_push[id] = cur
			if cur > 0.01:
				cand.append([absf(feet.x - cam_x), Vector4(feet.x, feet.y, fz, cur)])
			# szelest: idący przez kępę, nie częściej niż co ~0,4 s; kucający ciszej
			var rt := float(_rustle_t.get(id, 0.0)) - delta
			if inside and vx > 18.0 and rt <= 0.0:
				var crouch: bool = b.get("crouching") == true
				rt = randf_range(0.32, 0.5) * (1.6 if crouch else 1.0)
				Audio.play_variant_at("foley_gear", 3, b.global_position, Audio.BUS_PLAYER if grp == "players" else Audio.BUS_WORLD,
					(-19.0 if crouch else -11.0), randf_range(0.62, 0.8), 0.15)
			_rustle_t[id] = maxf(rt, 0.0)
	for id in _reed_push.keys():
		if not seen.has(id):
			_reed_push.erase(id)
			_rustle_t.erase(id)
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var arr := PackedVector4Array()
	arr.resize(REED_PUSHERS)
	for i in mini(cand.size(), REED_PUSHERS):
		arr[i] = cand[i][1]
	_reeds_mat.set_shader_parameter("pushers", arr)

const MUD_PRINTS := 48                   ## tyle odcisków naraz (tablica w shaderze LIQUID_TOP); najstarszy znika pierwszy
const MUD_STRIDE := 0.42                 ## m między kolejnymi odciskami jednej postaci
const MUD_FOOT_Z := 0.09                 ## m: lewa / prawa stopa w głąb od osi postaci

## Ślady w błocie: idący gracze i wrogowie zostawiają odciski na tafli błota (kosmetyka lokalna, zanikają po ~35–60 s). Trop wroga, który
## przeszedł przez bagno, zostaje na chwilę widoczny w świetle latarki.
func _sync_mud_prints() -> void:
	if _mud_mats.is_empty():
		return
	var added := false
	for grp in ["players", "enemies"]:
		for n in get_tree().get_nodes_in_group(grp):
			var b := n as Node2D
			if b == null or not is_instance_valid(b) or not b.is_visible_in_tree() or b.get("dead") == true:
				continue
			if str(b.get("kind")) in ["cma", "nest", "vein", "leech"]:
				continue
			var id := b.get_instance_id()
			if _liquid_kind(b.global_position) != 0:
				_print_last.erase(id)
				continue
			var v = b.get("velocity")
			var vel: Vector2 = v if v is Vector2 else Vector2.ZERO
			if absf(vel.y) > 30.0:
				continue                                     # w skoku nie ma odcisków
			var x := Level3D.px_to_m(b.global_position).x
			var last: Array = _print_last.get(id, [x - MUD_STRIDE, 1.0])
			if absf(x - float(last[0])) < MUD_STRIDE:
				continue
			var side := -float(last[1])
			var z := (0.0 if grp == "players" else 0.3) + side * MUD_FOOT_Z
			var dir := signf(vel.x) if absf(vel.x) > 1.0 else 1.0
			_prints[_print_i] = Vector4(x, z, maxf(_life, 0.01), dir)
			_print_i = (_print_i + 1) % MUD_PRINTS
			_print_last[id] = [x, side]
			added = true
	for m in _mud_mats:
		var sm := m as ShaderMaterial
		if added:
			sm.set_shader_parameter("prints", _prints)
		sm.set_shader_parameter("print_now", _life)

func _wade_step(cur: float, feet_px: Vector2) -> float:
	var want := Level3D.wade_at(_wade, feet_px)
	return move_toward(cur, want, get_process_delta_time() * (1.6 if want > cur else 3.0))

## Rozbryzg od kroków w błocie / oleju / wodzie: strumień kropel z poziomu tafli (węzeł `host` to model postaci lub wroga, opuszczony o `wade`).
func _splash_update(host: Node3D, feet_px: Vector2, speed_px: float, layer: int, wade := 0.0) -> void:
	var id := host.get_instance_id()
	var kind := _liquid_kind(feet_px)
	var sp: CPUParticles3D = _splash.get(id)
	if sp != null and not is_instance_valid(sp):
		sp = null
		_splash.erase(id)
	if kind < 0:
		if sp != null:
			sp.emitting = false
		return
	if sp == null:
		sp = CPUParticles3D.new()
		sp.name = "LiquidSplash"
		sp.amount = 22
		sp.lifetime = 0.65
		sp.local_coords = false
		sp.direction = Vector3.UP
		sp.spread = 42.0
		sp.initial_velocity_min = 1.2
		sp.initial_velocity_max = 2.9
		sp.gravity = Vector3(0.0, -8.0, 0.0)
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sp.emission_box_extents = Vector3(0.25, 0.02, 0.18)
		var dm := SphereMesh.new()
		dm.radius = 0.5
		dm.height = 1.0
		dm.radial_segments = 6
		dm.rings = 3
		var mat := StandardMaterial3D.new()                   # cieniowane: krople widać w świetle sceny, w ciemności nie świecą (GDD §8.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
		dm.material = mat
		sp.mesh = dm
		sp.scale_amount_min = 0.025
		sp.scale_amount_max = 0.075
		sp.position = Vector3(0.0, -0.05, 0.2)
		sp.layers = layer
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.set_meta("kind", -1)
		host.add_child(sp)
		_splash[id] = sp
	if int(sp.get_meta("kind")) != kind:
		sp.set_meta("kind", kind)
		var m := (sp.mesh as SphereMesh).material as StandardMaterial3D
		m.albedo_color = [Color(0.075, 0.056, 0.040, 0.95), Color(0.03, 0.03, 0.036, 0.95), Color(0.20, 0.18, 0.12, 0.8)][kind]
	sp.position.y = wade - 0.03
	sp.emitting = speed_px > 22.0

func _set_layer(root: Node, layer: int) -> void:
	for mi in root.find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = layer

# ---------------------------------------------------------------- pociski i cząsteczki (efekty w 3D)

func _emissive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _emissive(col)
	mi.position = at
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _sphere(parent: Node3D, r: float, at: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.material_override = _emissive(col)
	mi.position = at
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Pocisk 2D → smuga 3D (ten sam kształt co `projectile.gd::_draw`: ogon, głowa; granat, rakieta i bełt osobno); rysunek 2D chowamy.
func _make_proj(n: Node2D) -> void:
	var d = n.get("_def")
	if d == null:
		return
	var root := Node3D.new()
	root.name = "Proj_%d" % n.get_instance_id()
	var col: Color = d.tracer_color
	var tail := float(d.tracer_len) * PX
	var fast: bool = n.has_method("is_fast") and n.is_fast()
	if fast:
		# szybka kula: smuga (poświata + rdzeń) od ogona do głowy, rozciągana co klatkę w `_sync_projectiles`
		var pellet := int(d.pellets) > 1
		var halo := _trace_quad(Color(col.r, col.g, col.b, 0.5 if pellet else 0.8))
		var core := _trace_quad(Color(1.0, 0.97, 0.85, 0.85 if pellet else 1.0))
		root.add_child(halo)
		root.add_child(core)
		root.set_meta("trace", [halo, core, TRACE_W_PELLET if pellet else TRACE_W])
	elif n.has_method("sticks_on_hit") and n.sticks_on_hit():
		_box(root, Vector3(maxf(tail, 0.5), 0.035, 0.035), Vector3(-maxf(tail, 0.5) * 0.5, 0.0, 0.0), Color(0.62, 0.5, 0.34))
		_box(root, Vector3(0.3, 0.06, 0.06), Vector3(0.22, 0.0, 0.0), Color(0.85, 0.85, 0.9))
	elif float(d.blast_radius) > 0.0:
		# granat 40 mm: ok. 2× naturalnej średnicy (8 cm), żeby był czytelny z kamery bocznej — wcześniej kula 40 cm; żar zapalnika z tyłu
		_sphere(root, 0.04, Vector3.ZERO, Color(0.3, 0.32, 0.2))
		_sphere(root, 0.028, Vector3(-0.045, 0.0, 0.0), Color(1.0, 0.7, 0.3))
	elif float(d.homing) > 0.0:
		# rakieta (FALCON-6): kadłub 12 cm (wcześniej 32 cm) i smuga wylotowa za nim
		_box(root, Vector3(tail, 0.07, 0.07), Vector3(-tail * 0.5, 0.0, 0.0), Color(col.r, col.g, col.b, 0.25))
		_box(root, Vector3(tail * 0.6, 0.035, 0.035), Vector3(-tail * 0.3, 0.0, 0.0), Color(col.r, col.g, col.b, 0.7))
		_box(root, Vector3(0.12, 0.035, 0.035), Vector3.ZERO, Color(0.9, 0.9, 0.92))
	else:
		_box(root, Vector3(maxf(tail, 0.1), 0.05, 0.05), Vector3(-tail * 0.5, 0.0, 0.0), Color(col.r, col.g, col.b, 0.22))
		_box(root, Vector3(maxf(tail * 0.5, 0.05), 0.07, 0.07), Vector3(-tail * 0.25, 0.0, 0.0), Color(col.r, col.g, col.b, 0.7))
		_box(root, Vector3(0.2, 0.06, 0.06), Vector3(0.04, 0.0, 0.0), Color(1.0, 0.97, 0.85))
	_world.add_child(root)
	n.self_modulate = Color(1, 1, 1, 0)
	# strzał gracza brodzącego w cieczy: jego model (i lufa) stoi niżej niż w symulacji — smuga wychodzi z widocznej lufy i na pierwszych
	# metrach lotu wraca na prawdziwy tor (trafienia liczy serwer z toru symulacji)
	var drop := 0.0
	for p in _rigs.keys():
		if is_instance_valid(p) and (p as Node2D).global_position.distance_to(n.global_position) < 40.0:
			drop = maxf(drop, float(_rigs[p].get("wade", 0.0)))
	_proj[n.get_instance_id()] = [n, root, drop, n.global_position]

func _sync_projectiles() -> void:
	for n in get_tree().get_nodes_in_group("projectiles"):
		if n is Node2D and not n.is_queued_for_deletion() and not _proj.has(n.get_instance_id()):
			_make_proj(n)
	for id in _proj.keys():
		var pr: Array = _proj[id]
		var src = pr[0]
		var px: Node3D = pr[1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(px):
				px.queue_free()
			_proj.erase(id)
			continue
		var s2 := src as Node2D
		var drop := float(pr[2]) * clampf(1.0 - s2.global_position.distance_to(pr[3]) * PX / WADE_SHOT_BLEND_M, 0.0, 1.0)
		if px.has_meta("trace"):
			var tr: Array = px.get_meta("trace")
			var head: Vector2 = s2.global_position
			var tail_at: Vector2 = head - (s2.get("direction") as Vector2) * float(s2.call("tracer_len_at", head))
			var off := Vector3(0.0, -drop, 0.3)
			var w: Vector2 = tr[2]
			_span_quad(tr[0], Level3D.px_to_m(tail_at) + off, Level3D.px_to_m(head) + off, w.x)
			_span_quad(tr[1], Level3D.px_to_m(tail_at) + off, Level3D.px_to_m(head) + off, w.y)
			continue
		px.position = Level3D.px_to_m(s2.global_position) + Vector3(0.0, -drop, 0.3)
		px.rotation = Vector3(0.0, 0.0, -s2.global_rotation)

## Wołane z `Vfx.burst_fx`: jednorazowy wybuch cząsteczek w scenie (billboardy, rozrzut w płaszczyźnie gry); opis w `cfg` — patrz vfx.gd.
func spawn_burst(pos: Vector2, cfg: Dictionary) -> void:
	var life := float(cfg.get("life", 0.5))
	var dir: Vector2 = cfg.get("dir", Vector2.UP)
	var grav: Vector2 = cfg.get("gravity", Vector2(0.0, 500.0))
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = float(cfg.get("explosiveness", 0.95))
	p.amount = maxi(1, int(cfg.get("amount", 8)))
	p.lifetime = life
	p.direction = Vector3(dir.x, -dir.y, 0.0)
	p.spread = float(cfg.get("spread", 60.0))
	p.initial_velocity_min = float(cfg.get("vmin", 20.0)) * PX
	p.initial_velocity_max = float(cfg.get("vmax", 60.0)) * PX
	p.gravity = Vector3(grav.x * PX, -grav.y * PX, 0.0)
	p.scale_amount_min = float(cfg.get("smin", 1.0)) * Vfx.BLOB_SCALE
	p.scale_amount_max = float(cfg.get("smax", 1.0)) * Vfx.BLOB_SCALE
	p.color = cfg.get("color", Color.WHITE)
	p.layers = LAYER_ACTORS
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(8.0, 8.0) * PX
	var m := StandardMaterial3D.new()
	if not bool(cfg.get("shaded", false)):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = Vfx.blob_texture()
	q.material = m
	p.mesh = q
	p.position = Level3D.px_to_m(pos) + Vector3(0.0, 0.0, 0.2)
	_world.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- dekoracje mapy (kamienie, kłody, płoty, kości)

## Indeks dekoracji → [model albo lista wariantów (wybór z pozycji), skala]. 0–7 jak w `bake_sprites.PROPS` (kamienie i kości losuje
## `level.gd: _place_deco`), 8+ tylko z akcentów map (`ACCENTS`). Kamienie i dekoracje 8+ to skany Poly Haven w naturalnej skali.
const DECO_MODELS := {3: [["rock", "rock_b", "rock_c", "rock", "stump"], 1.0], 4: ["bones", 0.7], 6: ["fence", 0.34], 7: ["logs", 1.0],   ## płot: model ma 6,5 m wysokości — w skali 0,34 ok. 2,2 m
	8: ["fire_pit", 1.0], 9: ["stump", 1.0], 10: ["trunk_big", 1.0], 11: ["barrel_stove", 1.0], 12: ["mil_crate", 1.0], 13: ["tyre", 1.0],
	14: ["barrier", 1.0], 15: ["shelf_n", 1.0], 16: ["shelf_b", 1.0], 17: ["pipes", 1.0], 18: ["compressor", 1.0], 19: ["cart", 1.0], 20: ["barrel_n", 1.0], 21: ["jerrycan", 1.0], 22: ["gas_mask", 1.0]}
## Głębokość (z, m) dekoracji stojących w stałym miejscu za płaszczyzną gry; pozostałe leżą losowo w głębi bryły gruntu.
const DECO_Z := {6: -0.9, 7: -0.9, 8: -0.8, 9: -1.3, 10: -1.9, 11: -0.95, 12: -1.0, 13: -0.85, 14: -0.9,
	15: -1.4, 16: -1.4, 17: -1.85, 18: -1.3, 19: -1.2, 20: -1.2, 21: -1.1, 22: -1.95}   ## 15–20: wnętrza Składu i Pompowni; rury przy samej ścianie tła (przód ściany ok. −2,1 m)

## Dekoracje z listy poziomu (`level.gd: _deco_list` — te same miejsca co w 2D) jako modele 3D w `MultiMesh`: kamienie i kości rozrzucone w głąb
## bryły gruntu, płoty, kłody i akcenty map tuż za płaszczyzną gry. Trzciny (5) mają własne bryły przy cieczach (`Level3D.build_liquid_props`).
func _build_deco(root: Node3D = null) -> void:
	if root == null:
		root = _geo
	var list = _level.get("_deco_list")
	if list == null:
		return
	var groups := {}
	for d in list:
		var id := int(d[1])
		if not DECO_MODELS.has(id):
			continue
		var feet: Vector2 = d[0]
		var h := int(feet.x) * 73856093 ^ int(feet.y) * 19349663
		var r1 := float(absi(h) % 1000) / 1000.0
		var r2 := float(absi(h >> 7) % 1000) / 1000.0
		var mdl = DECO_MODELS[id][0]
		var mname := String(mdl[absi(h >> 11) % (mdl as Array).size()]) if mdl is Array else String(mdl)
		var k := PX * float(DECO_MODELS[id][1]) * (0.85 + 0.4 * r2 if id == 3 else 1.0)
		var z: float = DECO_Z.get(id, lerpf(-1.9, -0.45, r1))
		var yaw := (PI if bool(d[2]) else 0.0) + (lerpf(-0.6, 0.6, r2) if id == 3 or id == 4 else lerpf(-0.08, 0.08, r2))
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k))
		if not groups.has(mname):
			groups[mname] = []
		(groups[mname] as Array).append(Transform3D(b, Level3D.px_to_m(feet) + Vector3(0.0, 0.0, z)))
	for mname in groups:
		var ps := _item_scene(String(mname))
		if ps == null:
			continue
		var inst := ps.instantiate()
		var src := inst.find_children("*", "MeshInstance3D", true, false)
		if src.is_empty():
			inst.free()
			continue
		var smi := src[0] as MeshInstance3D
		var base := smi.global_transform if smi.is_inside_tree() else _local_xf(smi, inst)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = smi.mesh
		var xfs: Array = groups[mname]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, (xfs[i] as Transform3D) * base)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Deco_" + String(mname)
		mmi.multimesh = mm
		mmi.layers = LAYER_WORLD
		root.add_child(mmi)
		inst.free()

## Przekształcenie węzła względem korzenia sceny, która nie jest jeszcze w drzewie.
func _local_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if p == root and root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf

# ---------------------------------------------------------------- drzwi wyjścia z kryjówki

const LD_STATE_COLORS := [Color(0.95, 0.16, 0.10), Color(1.0, 0.62, 0.12), Color(0.35, 1.0, 0.45)]   ## lampa ON AIR: nikt / część drużyny / wszyscy gotowi
var _launch_doors := {}                   ## id węzła drzwi (launch_door.gd) → {root, mat, light}

## Drzwi bunkrowe na końcu strefy startu: rama i skrzydło w tylnej ścianie, lampa ON AIR nad nimi (kolor = gotowość drużyny)
## i pasy ostrzegawcze na podłodze strefy. Odtwarzane po przebudowie geometrii mapy (korzeń wisi w `_geo`).
func _sync_launch_doors() -> void:
	for id in _launch_doors.keys():
		if not is_instance_valid((_launch_doors[id] as Dictionary)["root"]):
			_launch_doors.erase(id)
	for n in get_tree().get_nodes_in_group("launch_door"):
		if not (n is Node2D) or _geo_key == "":
			continue
		var d = _launch_doors.get(n.get_instance_id())
		if d == null:
			d = _build_launch_door(n as Node2D)
			_launch_doors[n.get_instance_id()] = d
		var st := clampi(int(n.get("state")), 0, 2)
		var cancel := float(n.get("cancel"))
		var col: Color = (LD_STATE_COLORS[st] as Color).lerp(LD_STATE_COLORS[0], clampf(cancel * 2.0, 0.0, 1.0))
		var t := float(Time.get_ticks_msec()) * 0.001
		var pulse := 0.55 + 0.45 * sin(t * 8.0) if st == 1 else (0.8 + 0.2 * sin(t * 6.0) if st == 2 else 1.0)
		var mat := d["mat"] as StandardMaterial3D
		mat.albedo_color = col
		mat.emission = col
		mat.emission_energy_multiplier = 3.0 * pulse
		var lt := d["light"] as OmniLight3D
		lt.light_color = col
		lt.light_energy = 1.6 * pulse + 2.0 * cancel
		# pad, kurtyna i światło nad strefą: kolor stanu, siła rośnie od pustej strefy przez część drużyny do odliczania
		var pad_a: float = [0.10, 0.24, 0.34][st] * pulse + 0.25 * cancel
		var k: float = [0.0, 0.5, 0.85][st] * pulse + 0.6 * cancel
		(d["pad"] as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, pad_a)
		var cm := d["curtain"] as ShaderMaterial
		cm.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
		cm.set_shader_parameter("k", k)
		var spot := d["spot"] as SpotLight3D
		spot.light_color = col
		spot.light_energy = float([0.0, 1.2, 2.6][st]) * pulse + 2.0 * cancel
		# sloty graczy: jedno pole na człowieka, zapalone u gotowych
		var total := clampi(int(n.get("total")), 1, 4)
		var ready_n := int(n.get("ready_n"))
		var slots: Array = d["slots"]
		for i in slots.size():
			var sm: StandardMaterial3D = slots[i]["mat"]
			var on := i < ready_n
			(slots[i]["mi"] as MeshInstance3D).visible = i < total
			sm.albedo_color = col if on else Color(0.16, 0.13, 0.11)
			sm.emission = col if on else Color(0.0, 0.0, 0.0)
			sm.emission_energy_multiplier = 2.2 if on else 0.0
		# licznik gotowych pod lampą; odliczanie pokazuje tylko HUD (cyfra na drzwiach i kogut usunięte w 1.7.307 — dublowały HUD)
		var count := d["count"] as Label3D
		count.text = "%d / %d" % [ready_n, maxi(1, int(n.get("total")))]
		count.modulate = Color(col.r, col.g, col.b, 0.85)

func _ld_box(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.layers = LAYER_WORLD
	mi.position = pos
	root.add_child(mi)
	return mi

func _build_launch_door(n: Node2D) -> Dictionary:
	var zone: Rect2 = n.get("zone")
	var root := Node3D.new()
	root.name = "LaunchDoor"
	_geo.add_child(root)
	var foot := Level3D.px_to_m(n.global_position)
	root.position = Vector3(foot.x, foot.y, 0.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.16, 0.15)
	steel.metallic = 0.6
	steel.roughness = 0.55
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.21, 0.22, 0.18)
	leaf.metallic = 0.4
	leaf.roughness = 0.7
	_ld_box(root, Vector3(2.1, 2.95, 0.25), Vector3(0.0, 1.475, -1.9), steel)           # rama w tylnej ścianie
	_ld_box(root, Vector3(1.7, 2.65, 0.18), Vector3(0.0, 1.325, -1.76), leaf)           # skrzydło drzwi
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.17
	wheel.outer_radius = 0.22
	var wmi := MeshInstance3D.new()
	wmi.mesh = wheel
	wmi.material_override = steel
	wmi.layers = LAYER_WORLD
	wmi.position = Vector3(0.0, 1.35, -1.64)
	wmi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	root.add_child(wmi)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.emission_enabled = true
	lamp_mat.albedo_color = LD_STATE_COLORS[0]
	lamp_mat.emission = LD_STATE_COLORS[0]
	_ld_box(root, Vector3(0.8, 0.24, 0.1), Vector3(0.0, 3.25, -1.74), lamp_mat)         # lampa ON AIR nad drzwiami
	var light := OmniLight3D.new()
	light.omni_range = 5.5
	light.light_volumetric_fog_energy = 0.8
	light.layers = LAYER_WORLD | LAYER_ACTORS
	light.position = Vector3(0.0, 3.0, -1.2)
	root.add_child(light)
	# pasy ostrzegawcze (żółto-czarne) wzdłuż przodu i tyłu strefy
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, Color(0.92, 0.72, 0.10) if ((x + y) / 4) % 2 == 0 else Color(0.06, 0.06, 0.05))
	var tex := ImageTexture.create_from_image(img)
	var hz := StandardMaterial3D.new()
	hz.albedo_texture = tex
	hz.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hz.roughness = 0.9
	var wm := zone.size.x * PX
	hz.uv1_scale = Vector3(wm / 0.12, 1.0, 1.0)
	var cx := zone.get_center().x * PX - foot.x
	for zz in [0.55, -0.55]:
		_ld_box(root, Vector3(wm, 0.012, 0.12), Vector3(cx, 0.008, zz), hz)
	# pad na podłodze strefy (świecący, z krawędziami), kurtyna światła, światło z sufitu, sloty graczy i napis na ścianie
	var cxm := zone.get_center().x * PX - foot.x
	var pad_mat := StandardMaterial3D.new()
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pad_mat.albedo_color = Color(0.9, 0.2, 0.1, 0.1)
	var pad := _ld_box(root, Vector3(wm, 0.01, 1.3), Vector3(cxm, 0.012, 0.0), pad_mat)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var csh := Shader.new()
	# kurtyna: poświata od padu w górę, gaśnie do zera na 2 m nad podłogą (jasność z wysokości, nie z UV: dawniej świeciła też górna krawędź
	# quada — biały pas nad głowami na całą szerokość strefy, prześwietlony przez glow; usunięty w 1.7.307)
	csh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_disabled, depth_draw_never;\nuniform vec3 col : source_color = vec3(0.3, 1.0, 0.4);\nuniform float k = 0.0;\nuniform float half_h = 1.7;\nvarying float v_h;\nvoid vertex() {\n	v_h = VERTEX.y + half_h;\n}\nvoid fragment() {\n	float v = pow(clamp(1.0 - v_h / 2.0, 0.0, 1.0), 2.0);\n	float h = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);\n	float rays = 0.7 + 0.3 * sin(UV.x * 70.0 + TIME * 1.4);\n	ALBEDO = col * k * 0.45 * v * h * rays;\n}\n"
	var curtain_mat := ShaderMaterial.new()
	curtain_mat.shader = csh
	var cq := QuadMesh.new()
	cq.size = Vector2(wm, 3.4)
	var cmi := MeshInstance3D.new()
	cmi.mesh = cq
	cmi.material_override = curtain_mat
	cmi.layers = LAYER_WORLD
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cmi.position = Vector3(cxm, 1.7, -0.45)
	root.add_child(cmi)
	var spot := SpotLight3D.new()
	spot.spot_range = 9.0
	spot.spot_angle = 52.0
	spot.light_volumetric_fog_energy = 1.2
	spot.layers = LAYER_WORLD | LAYER_ACTORS
	spot.position = Vector3(cxm, 7.8, 0.3)
	spot.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	root.add_child(spot)
	var slots: Array = []
	for i in 4:
		var sm := StandardMaterial3D.new()
		sm.emission_enabled = true
		sm.albedo_color = Color(0.16, 0.13, 0.11)
		var smi := _ld_box(root, Vector3(1.0, 0.025, 0.16), Vector3(cxm + (float(i) - 1.5) * 2.1, 0.02, 0.62), sm)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slots.append({"mat": sm, "mi": smi})
	var font := UiTheme.heading_font()
	var count := Label3D.new()
	count.font_size = 72
	count.pixel_size = 0.007
	count.shaded = false
	count.outline_size = 8
	count.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	count.layers = LAYER_WORLD
	count.position = Vector3(0.0, 3.85, -1.72)
	if font != null:
		count.font = font
	root.add_child(count)
	var sign_l := Label3D.new()
	sign_l.text = tr("LAUNCH ZONE")
	sign_l.font_size = 96
	sign_l.pixel_size = 0.008
	sign_l.shaded = false
	sign_l.modulate = Color(0.85, 0.66, 0.28, 0.85)
	sign_l.outline_size = 6
	sign_l.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	sign_l.layers = LAYER_WORLD
	sign_l.position = Vector3(cxm - wm * 0.5 + 3.2, 4.3, -1.88)
	if font != null:
		sign_l.font = font
	root.add_child(sign_l)
	return {"root": root, "mat": lamp_mat, "light": light, "pad": pad_mat, "curtain": curtain_mat, "spot": spot, "slots": slots, "count": count}

# ---------------------------------------------------------------- papier w świecie (hud.gd: _build_world_notes)

var _wnotes := {}                         ## id SubViewportu notatki → {quad}

## Odprawa i prognoza jako kartki w świecie: quad z teksturą z SubViewportu (grupa „world_note”) przypięty do tablicy odpraw albo do ściany nad radiostacją,
## oświetlony lampami sceny; chowa się, gdy ta sama treść jest pokazana w karcie HUD (gracz stoi blisko).
func _sync_world_notes() -> void:
	for vp in get_tree().get_nodes_in_group("world_note"):
		if not (vp is SubViewport) or _geo_key == "":
			continue
		var kind := String(vp.get_meta("kind", ""))
		var anchor: Node2D = null
		for n in get_tree().get_nodes_in_group("board" if kind == "brief" else "radio_set"):
			anchor = n as Node2D
			break
		var id: int = vp.get_instance_id()
		var d = _wnotes.get(id)
		if anchor == null:
			if d != null and is_instance_valid(d["quad"]):
				(d["quad"] as Node3D).visible = false
			continue
		if d == null or not is_instance_valid(d["quad"]):
			var q := MeshInstance3D.new()
			q.name = "WorldNote_" + kind
			q.mesh = QuadMesh.new()
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = (vp as SubViewport).get_texture()
			mat.roughness = 0.95
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.emission_enabled = true                       # kartka czytelna także poza światłem lampy (jak kreda na tablicy wyników)
			mat.emission_texture = (vp as SubViewport).get_texture()
			mat.emission_energy_multiplier = 0.32
			q.material_override = mat
			q.layers = LAYER_WORLD
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_geo.add_child(q)
			d = {"quad": q}
			_wnotes[id] = d
		var quad := d["quad"] as MeshInstance3D
		quad.visible = not bool(vp.get_meta("hide", false)) and (vp as SubViewport).size.x > 32
		if not quad.visible:
			continue
		var w := 2.3 if kind == "brief" else 2.3
		var sv := (vp as SubViewport).size
		(quad.mesh as QuadMesh).size = Vector2(w, w * float(sv.y) / float(maxi(1, sv.x)))
		var base := Level3D.px_to_m(anchor.global_position)
		if kind == "brief":
			var zf := _model_front(anchor, "board")
			quad.position = base + Vector3(0.0, 1.7, (-1.28 if is_nan(zf) else zf + 0.03))
			quad.rotation = Vector3(0.0, 0.0, deg_to_rad(-1.6))
		else:
			quad.position = base + Vector3(0.0, 2.6, -1.78)
			quad.rotation = Vector3(0.0, 0.0, deg_to_rad(1.2))

# ---------------------------------------------------------------- rekwizyty kryjówki (hub_prop.gd)

const HUB_WINDOW_SHADER := "shader_type spatial;\nrender_mode unshaded;\nuniform int kind = 0;\nuniform float flash = 0.0;\nuniform vec3 sky_top : source_color = vec3(0.02, 0.04, 0.09);\nuniform vec3 sky_bot : source_color = vec3(0.07, 0.10, 0.16);\nvoid fragment() {\n	vec2 uv = UV;\n	vec3 col = mix(sky_top, sky_bot, uv.y);\n	if (kind == 0) {\n		float d = distance(uv, vec2(0.74, 0.3));\n		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.09, 0.07, d);\n		vec2 g = floor(uv * vec2(40.0, 24.0));\n		float h = fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453);\n		col += vec3(0.6) * step(0.985, h) * (0.5 + 0.5 * sin(TIME * 2.0 + h * 20.0));\n	} else if (kind == 1 || kind == 2) {\n		vec2 p = vec2(uv.x * 28.0 + uv.y * 3.0, uv.y * 3.0 - TIME * (kind == 2 ? 2.6 : 2.0));\n		float cell = floor(p.x);\n		float h = fract(sin(cell * 91.3) * 437.5);\n		float y = fract(p.y + h * 5.0);\n		float streak = smoothstep(0.0, 0.05, y) * smoothstep(0.35, 0.1, y) * step(0.45, h);\n		streak *= smoothstep(0.12, 0.02, abs(fract(p.x) - 0.5));\n		col += vec3(0.55, 0.7, 0.9) * streak * 0.5;\n	} else {\n		col = mix(col, vec3(0.31, 0.33, 0.34), 0.7);\n		col += 0.04 * sin(uv.x * 6.0 + TIME * 0.3) * sin(uv.y * 4.0 - TIME * 0.2);\n	}\n	col += vec3(0.8, 0.85, 1.0) * flash;\n	ALBEDO = col;\n}\n"
const HUB_PROP_MODELS := {"generator": 1.0, "compressor": 1.0, "barrel": 1.0, "crate": 1.0, "mil_crate": 1.0, "scrap_pile": 1.0}   ## modele z art/items3d/ i ich skala względem piksela świata
const HUB_PROP_Z := -1.1                  ## głębia rekwizytów maszynowni (przy ścianie, za płaszczyzną gry)
var _hub_props3d := {}                    ## id węzła hub_prop.gd → {root, kind, ...}

## Rekwizyty z HUB_PROPS: modele maszynowni i magazynu, rury pod stropem, zamknięte drzwi D-7 (czerwony pas pod nimi błyska przy stukaniu)
## i okno radiostacji, w którym widać prognozowaną pogodę (clear / rain / storm / fog). Odtwarzane po przebudowie geometrii mapy.
func _sync_hub_props() -> void:
	for id in _hub_props3d.keys():
		if not is_instance_valid((_hub_props3d[id] as Dictionary)["root"]):
			_hub_props3d.erase(id)
	for n in get_tree().get_nodes_in_group("hub_props"):
		if not (n is Node2D) or _geo_key == "":
			continue
		var d = _hub_props3d.get(n.get_instance_id())
		if d == null:
			d = _build_hub_prop(n as Node2D)
			_hub_props3d[n.get_instance_id()] = d
		var t := float(Time.get_ticks_msec()) * 0.001
		match String(d["kind"]):
			"generator":
				var storm: bool = Weather.forecast == "storm"
				var f := 0.85 + 0.15 * sin(t * 9.0) * sin(t * 3.3)
				if storm and sin(t * 1.7) * sin(t * 0.6 + 1.0) > 0.78:
					f = 0.15                                   # burza: lampa przy generatorze na chwilę siada
				(d["light"] as OmniLight3D).light_energy = 2.4 * f
			"d7":
				var k := float(n.get("knock_flash"))
				(d["mat"] as StandardMaterial3D).emission_energy_multiplier = 1.2 + 3.0 * k
				(d["light"] as OmniLight3D).light_energy = 0.5 + 1.6 * k
			"window":
				var fc: String = Weather.forecast
				var kind_i := 0 if fc == "clear" else (1 if fc == "rain" else (2 if fc == "storm" else 3))
				var sm := d["mat"] as ShaderMaterial
				var fl := 0.0
				if fc == "storm":
					fl = pow(maxf(0.0, sin(t * 0.9) * sin(t * 2.3 + 0.7)), 6.0)
				sm.set_shader_parameter("kind", kind_i)
				sm.set_shader_parameter("flash", fl * 0.9)
				var sky_cols := {"clear": [Color(0.02, 0.04, 0.09), Color(0.07, 0.10, 0.16)], "rain": [Color(0.05, 0.06, 0.08), Color(0.10, 0.12, 0.15)],
					"storm": [Color(0.03, 0.03, 0.05), Color(0.08, 0.09, 0.12)], "fog": [Color(0.15, 0.17, 0.18), Color(0.25, 0.27, 0.28)]}
				var sc: Array = sky_cols.get(fc, sky_cols["clear"])
				sm.set_shader_parameter("sky_top", sc[0])
				sm.set_shader_parameter("sky_bot", sc[1])
				(d["light"] as OmniLight3D).light_energy = 0.35 + 3.0 * fl

func _hp_mat(col: Color, metal := 0.4, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

func _build_hub_prop(n: Node2D) -> Dictionary:
	var kind := String(n.get("kind"))
	var args: Array = n.get("args")
	var root := Node3D.new()
	root.name = "HubProp_" + kind
	_geo.add_child(root)
	var foot := Level3D.px_to_m(n.global_position)
	root.position = Vector3(foot.x, foot.y, 0.0)
	var d := {"root": root, "kind": kind}
	if HUB_PROP_MODELS.has(kind):
		var m := _item_model(kind)
		if m != null:
			var sc := float(HUB_PROP_MODELS[kind])
			m.scale = Vector3(PX, PX, PX) * sc
			m.position = Vector3(0.0, 0.0, HUB_PROP_Z + (0.5 if kind == "crate" or kind == "barrel" or kind == "scrap_pile" else 0.0))
			root.add_child(m)
		if kind == "generator":
			var lamp := OmniLight3D.new()                      # lampa w klatce nad generatorem
			lamp.light_color = Color(1.0, 0.82, 0.3)
			lamp.omni_range = 7.0
			lamp.light_energy = 2.4
			lamp.light_volumetric_fog_energy = 1.2
			lamp.layers = LAYER_WORLD | LAYER_ACTORS
			lamp.position = Vector3(0.0, 3.3, -0.5)
			root.add_child(lamp)
			_ld_box(root, Vector3(0.3, 0.12, 0.3), Vector3(0.0, 3.45, -0.5), _hp_mat(Color(0.12, 0.12, 0.1)))
			d["light"] = lamp
	elif kind == "pipes":
		var c1 := int(args[0]) if not args.is_empty() else int(n.position.x / 16.0) + 10
		var span := float(c1 - int(n.position.x / 16.0)) * Level3D.T
		var rust := _hp_mat(Color(0.30, 0.17, 0.10), 0.5, 0.8)
		for yy in [4.7, 5.15]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.13
			cyl.bottom_radius = 0.13
			cyl.height = span
			var mi := MeshInstance3D.new()
			mi.mesh = cyl
			mi.material_override = rust
			mi.layers = LAYER_WORLD
			mi.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
			mi.position = Vector3(span * 0.5, yy, -2.0)
			root.add_child(mi)
			for k in range(1, int(span / 3.2)):
				_ld_box(root, Vector3(0.1, 0.36, 0.36), Vector3(float(k) * 3.2, yy, -2.0), _hp_mat(Color(0.14, 0.12, 0.10), 0.6, 0.6))
	elif kind == "d7":
		var plate := _hp_mat(Color(0.18, 0.17, 0.16), 0.6, 0.6)
		_ld_box(root, Vector3(2.1, 2.95, 0.25), Vector3(0.0, 1.475, -1.9), plate)
		_ld_box(root, Vector3(1.7, 2.65, 0.18), Vector3(0.0, 1.325, -1.76), _hp_mat(Color(0.13, 0.13, 0.12), 0.7, 0.5))
		for sgn in [1.0, -1.0]:
			var brace := _ld_box(root, Vector3(2.0, 0.12, 0.08), Vector3(0.0, 1.325, -1.64), plate)     # zakrzyżowane belki
			brace.rotation = Vector3(0.0, 0.0, deg_to_rad(38.0) * sgn)
		var pad := _item_model("padlock")
		if pad != null:
			pad.scale = Vector3(PX, PX, PX) * float(ITEM_SCALE.get("padlock", 0.4)) * 1.8
			pad.position = Vector3(0.0, 1.2, -1.6)
			root.add_child(pad)
		var lab := Label3D.new()
		lab.text = "D-7"
		lab.font_size = 64
		lab.pixel_size = 0.007
		lab.modulate = Color(0.75, 0.74, 0.68)
		lab.shaded = true
		lab.position = Vector3(0.0, 3.25, -1.74)
		lab.layers = LAYER_WORLD
		root.add_child(lab)
		var red := StandardMaterial3D.new()
		red.emission_enabled = true
		red.albedo_color = Color(0.9, 0.12, 0.08)
		red.emission = Color(1.0, 0.12, 0.08)
		red.emission_energy_multiplier = 1.2
		_ld_box(root, Vector3(1.7, 0.05, 0.1), Vector3(0.0, 0.04, -1.62), red)                       # pas światła spod drzwi
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.14, 0.08)
		lt.omni_range = 4.5
		lt.light_energy = 0.5
		lt.layers = LAYER_WORLD | LAYER_ACTORS
		lt.position = Vector3(0.0, 0.25, -1.0)
		root.add_child(lt)
		d["mat"] = red
		d["light"] = lt
	elif kind == "window":
		var w := (float(args[0]) if not args.is_empty() else 3.0) * Level3D.T
		var h := 2.0
		var y0 := 1.5
		var frame := _hp_mat(Color(0.14, 0.12, 0.10), 0.3, 0.8)
		_ld_box(root, Vector3(w + 0.3, h + 0.3, 0.12), Vector3(0.0, y0 + h * 0.5, -1.9), frame)
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		var gm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = HUB_WINDOW_SHADER
		gm.shader = sh
		var gmi := MeshInstance3D.new()
		gmi.mesh = qm
		gmi.material_override = gm
		gmi.layers = LAYER_WORLD
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gmi.position = Vector3(0.0, y0 + h * 0.5, -1.83)
		root.add_child(gmi)
		for k in [-1, 0, 1]:
			if k == 0:
				_ld_box(root, Vector3(0.08, h, 0.06), Vector3(0.0, y0 + h * 0.5, -1.79), frame)     # słupek okna
		var wl := OmniLight3D.new()                              # zimne światło z okna (błyski burzy rozświetlają pokój)
		wl.light_color = Color(0.55, 0.7, 1.0)
		wl.omni_range = 6.0
		wl.light_energy = 0.35
		wl.light_volumetric_fog_energy = 1.0
		wl.layers = LAYER_WORLD | LAYER_ACTORS
		wl.position = Vector3(0.0, y0 + h * 0.5, -1.2)
		root.add_child(wl)
		d["mat"] = gm
		d["light"] = wl
	return d

# ---------------------------------------------------------------- radiostacja i zamurowane przejścia

## Obiekty rysowane w 2D kodem (`_draw`), bez sprite'a przedmiotu: radiostacja kryjówki dostaje model, a zamurowane przejście — bryłę z cegły
## (materiał PBR ściany). Wersje 2D zostają dla logiki, są przezroczyste; rozbita ściana znika razem ze swoim węzłem.
func _sync_drawn() -> void:
	for n in get_tree().get_nodes_in_group("radio_set"):
		if _drawn.has(n.get_instance_id()) or not (n is Node2D):
			continue
		var m := _item_model("radio_set")
		if m == null:
			continue
		m.scale = Vector3(PX, PX, PX) * float(ITEM_SCALE["radio_set"])
		m.position = Level3D.px_to_m((n as Node2D).global_position) + Vector3(0.0, 0.0, -1.2)
		_world.add_child(m)
		(n as CanvasItem).modulate = Color(1, 1, 1, 0)
		_drawn[n.get_instance_id()] = [n, m]
	# warsztat w kryjówce: lampa wisząca nad ławą i ścianą z narzędziami (jak nad stojakami; odtwarzana po przebudowie geometrii mapy)
	for n in get_tree().get_nodes_in_group("workshop"):
		if not (n is Node2D) or _geo_key == "":
			continue
		var wl = _ws_lamps.get(n.get_instance_id())
		if wl == null or not is_instance_valid(wl):
			_ws_lamps[n.get_instance_id()] = _add_rack_lamp(n as Node2D, WS_LAMP_PX, WS_LAMP_Z, 9.0, 46.0)
	for n in get_tree().get_nodes_in_group("exit_flares"):     # flara wyjścia: tuba wbita w ziemię jako model, płomień i iskry zostają w 2D
		if _drawn.has(n.get_instance_id()) or not (n is Node2D):
			continue
		var fm := _item_model("flare_stuck")
		if fm == null:
			continue
		fm.scale = Vector3(PX, PX, PX) * 0.85
		fm.position = Level3D.px_to_m((n as Node2D).global_position) + Vector3(0.0, -0.03, 0.05)
		_world.add_child(fm)
		_drawn[n.get_instance_id()] = [n, fm, "flare"]
	for n in get_tree().get_nodes_in_group("breakables"):
		if _drawn.has(n.get_instance_id()) or not (n is Node2D) or n.get("rows") == null:
			continue
		var h := float(n.get("rows")) * Level3D.T
		var bm := BoxMesh.new()
		bm.size = Vector3(Level3D.T, h, Level3D.DEPTH_BACK + 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = Level3D.make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone")
		mi.layers = LAYER_WORLD
		mi.position = Level3D.px_to_m((n as Node2D).global_position) + Vector3(0.0, h * 0.5, (0.5 - Level3D.DEPTH_BACK) * 0.5)
		_world.add_child(mi)
		(n as CanvasItem).modulate = Color(1, 1, 1, 0)
		for old in _geo.get_children():                           # ściana odbudowana po restarcie misji: gruz po poprzedniej znika
			if String(old.name).begins_with("Rubble") and absf((old as Node3D).position.x - mi.position.x) < 0.6 and absf((old as Node3D).position.y - (mi.position.y - h * 0.5)) < 0.6:
				old.queue_free()
		_drawn[n.get_instance_id()] = [n, mi, "wall", String(_level.get("map_id")), h]
	for id in _drawn.keys():
		var pr: Array = _drawn[id]
		if not is_instance_valid(pr[0]) or (pr[0] as Node).is_queued_for_deletion():
			if is_instance_valid(pr[1]):
				# rozbite zamurowane przejście (ta sama mapa): na podłodze zostaje gruz, a przy stropie wyszczerbione resztki muru
				if pr.size() > 3 and String(pr[2]) == "wall" and String(pr[3]) == String(_level.get("map_id")):
					_spawn_rubble((pr[1] as Node3D).position - Vector3(0.0, float(pr[4]) * 0.5, 0.0), float(pr[4]))
				(pr[1] as Node).queue_free()
			_drawn.erase(id)
		elif is_instance_valid(pr[1]):
			(pr[1] as Node3D).visible = (pr[0] as CanvasItem).is_visible_in_tree() and (pr.size() < 3 or String(pr[2]) != "flare" or pr[0].get("_active") == true)
			if pr.size() > 2 and String(pr[2]) == "flare":        # flara jest przenoszona na miejsce wyjścia dopiero przy otwarciu ewakuacji
				(pr[1] as Node3D).position = Level3D.px_to_m((pr[0] as Node2D).global_position) + Vector3(0.0, -0.03, 0.05)

# ---------------------------------------------------------------- broń na ziemi i na stojakach

const GUN_DIR := "res://art/char3d/"

const RACK_SCALE := 0.42                    ## stojak w 3D względem sprite'a 2D (48 × 36 px to prawie 4 m szerokości): deska ok. 1,6 m — pod broń w naturalnej długości
const RACK_UP_PX := 9.0                     ## dół stojaka nad podłogą [px świata]
const RACK_Z := -1.80                       ## oś stojaka: plecy deski przy ścianie tła
const RACK_SHELF_PX := 5.3                  ## góra półki w jednostkach modelu stojaka
const LOOT_MIN_M := 0.35                    ## m: najkrótsza broń leżąca na ziemi (P-83 ma 0,19 m — w naturalnej skali ginąłby pod stopami)
const RACK_MIN_M := 0.25                    ## m: najkrótsza broń na stojaku (oglądana z bliska, więc mniejsze minimum)
const RACK_GUN_Z := -1.70                   ## broń leży na półce, tuż przed deską
const RACK_PLATE_Z := -1.50                 ## front półki: tabliczka z ceną

## Gablota na broń w kryjówce (cabinet.gd, ARMORY_PLAN.md): korpus ze stali malowanej proszkowo, ściana listwowa w grafitowym filcu, broń na
## hakach w rzędach (od góry), półka z pistoletem i magazynkami, trzy ciepłe punkty LED w daszku, szklane drzwi uchylane przy oględzinach.
## Początek układu gabloty = środek dołu frontu; plecy przy ścianie tła (CAB_BACK_Z).
const CAB_W := 1.7                          ## szerokość [m] (najdłuższa broń, SPECTER-1, ma 1,15 m)
const CAB_H := 2.1                          ## wysokość [m]
const CAB_D := 0.42                         ## głębokość [m]
const CAB_BACK_Z := -1.80                   ## plecy gabloty (jak deska stojaka)
const CAB_ROWS := [1.74, 1.38, 1.02, 0.66]  ## wysokość osi broni w kolejnych rzędach od góry [m]
const CAB_SHELF_Y := 0.30                   ## półka na dole [m]
const CAB_GUN_Z := 0.12                     ## oś broni przed tłem [m]
const CAB_FELT := Color(0.09, 0.095, 0.1)   ## tło: grafitowy filc (wariant A z projektu)
const CAB_LED := Color(1.0, 0.84, 0.62)     ## punkty LED ok. 3000 K
const CAB_ROMAN := ["I", "II", "III", "IV"]
const RACK_LAMP_PX := 32.0                  ## spód lampy nad podłogą [px świata] (stojak kończy się ok. 24 px nad podłogą)

## Lampa wisząca nad stojakiem z bronią (kryjówka): emaliowany klosz z modelu `lamp`, przewód do stropu i ciepły reflektor w dół — stojak i broń
## oświetla widoczne źródło, a nie poświata „znikąd” (poświata pickupu na stojaku jest w 3D pomijana, zob. `_scan_lights`).
func _add_rack_lamp(rack_item: Node2D, up_px := RACK_LAMP_PX, z := RACK_GUN_Z + 0.42, energy := 7.0, angle := 40.0) -> Node3D:
	var lamp := _item_model("lamp")
	if lamp == null:
		return null
	var foot := rack_item.global_position
	var root := Node3D.new()
	root.name = "RackLamp"
	_geo.add_child(root)                                       # razem z geometrią mapy (znika przy zmianie mapy)
	root.position = Level3D.px_to_m(foot) + Vector3(0.0, up_px * PX, z)
	lamp.scale = Vector3(PX, PX, PX) * 1.25 * float(ITEM_SCALE["lamp"])
	root.add_child(lamp)
	# przewód do stropu: pierwszy lity kafel nad lampą
	var c := int(foot.x / 16.0)
	var r := int(foot.y / 16.0) - 1
	var guard := 0
	while r > 0 and guard < 40 and not Level3D.is_solid_ch(Level3D._ch(_rows, c, r)):
		r -= 1
		guard += 1
	var top_m := -float(r + 1) * Level3D.T
	var lamp_top := root.position.y + 11.7 * PX * 1.25 * float(ITEM_SCALE["lamp"])
	if top_m > lamp_top + 0.05:
		var cord := CylinderMesh.new()
		cord.top_radius = 0.012
		cord.bottom_radius = 0.012
		cord.height = top_m - lamp_top
		var cmi := MeshInstance3D.new()
		cmi.mesh = cord
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.03, 0.03, 0.03)
		cm.roughness = 0.8
		cmi.material_override = cm
		cmi.layers = LAYER_WORLD
		cmi.position = Vector3(0.0, 11.7 * PX * 1.25 + cord.height * 0.5, 0.0)
		root.add_child(cmi)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.76, 0.46)
	sp.light_energy = energy
	sp.spot_range = maxf(5.5, up_px * PX * 1.6)
	sp.spot_angle = angle
	sp.spot_attenuation = 0.9
	sp.spot_angle_attenuation = 0.6
	sp.shadow_enabled = true
	sp.light_volumetric_fog_energy = 1.4
	sp.layers = LAYER_WORLD | LAYER_ACTORS
	sp.position = Vector3(0.0, 0.1, 0.0)
	sp.basis = Basis.looking_at(Vector3(0.0, -1.0, -0.22), Vector3.FORWARD)
	root.add_child(sp)
	var bulb := OmniLight3D.new()                              # żarówka: słaba poświata wokół klosza
	bulb.light_color = Color(1.0, 0.8, 0.5)
	bulb.light_energy = 0.5
	bulb.omni_range = 1.4
	bulb.light_volumetric_fog_energy = 0.4
	bulb.layers = LAYER_WORLD | LAYER_ACTORS
	bulb.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(bulb)
	return root

## Kopie materiałów modelu z mnożnikiem koloru (materiały siatek są współdzielone między egzemplarzami — nadpisujemy je na węzłach).
func _tint_model(root: Node, tint: Color) -> void:
	for mn in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mn as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var bm := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if bm == null:
				continue
			if tint == Color.WHITE:
				mi.set_surface_override_material(si, null)
				continue
			var dm := bm.duplicate() as BaseMaterial3D
			dm.albedo_color = Color(bm.albedo_color.r * tint.r, bm.albedo_color.g * tint.g, bm.albedo_color.b * tint.b, bm.albedo_color.a)
			if dm.emission_enabled:
				dm.emission_energy_multiplier *= tint.v
			mi.set_surface_override_material(si, dm)

## Broń jako łup i na stojakach kryjówki (`pickup.gd`, sprite broni HD poza potokiem przedmiotów) dostaje ten sam model 3D, który trzymają postacie
## (art/char3d/gun_<klucz>.glb), w tej samej, naturalnej długości (LOOT_MIN_M: najkrótsza broń na ziemi nie jest krótsza — pistolet ma ok. 2×,
## jak znajdźki). Dotąd skalę brał z szerokości miniatury HD: łup był 1,3–5,4×, a broń na stojaku 1,7–7× większa niż w rękach. Na stojaku broń
## leży na półce; zablokowana jest przyciemniona,
## wisi na niej kłódka (model), a na froncie półki mosiężna tabliczka z wytłoczoną ceną — nakładka 2D (kłódka i cena) jest wtedy chowana.
func _sync_guns() -> void:
	for n in get_tree().get_nodes_in_group("pickups"):
		var id := n.get_instance_id()
		if _guns.has(id) or not (n is Node2D):
			continue
		var key := String(n.get("_hd_gun")) if n.get("_hd_gun") != null else ""
		var hd = n.get("_hd")
		var path := GUN_DIR + "gun_%s.glb" % key
		if key == "" or hd == null or not is_instance_valid(hd) or not ResourceLoader.exists(path):
			continue
		var on_rack := bool(n.get("static_display"))
		var spr := (hd as Node).get_node_or_null("GunMark") as Node2D
		if spr == null:
			continue
		var model := (load(path) as PackedScene).instantiate() as Node3D
		var box := AABB()
		var first := true
		for mn in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mn as MeshInstance3D
			mi.layers = LAYER_WORLD | (LAYER_REFL if on_rack else 0)
			var bb := _local_xf(mi, model) * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					var sm := mi.mesh.surface_get_material(si) as StandardMaterial3D
					if sm == null:
						continue
					if on_rack:                                    # stojak ma sondę odbić: pełny metal (jak broń w rękach)
						sm.metallic = 1.0
						sm.metallic_specular = 0.5
					else:                                          # łup leży w ciemności bez odbić — pełny metal byłby czarny, więc własna kopia materiału
						var lm := sm.duplicate() as StandardMaterial3D
						lm.metallic = 0.45
						lm.metallic_specular = 0.6
						mi.set_surface_override_material(si, lm)
		var k := maxf(1.0, (RACK_MIN_M if on_rack else LOOT_MIN_M) / maxf(box.size.x, 0.001))      # model broni ma naturalną długość (gun_proc.py)
		var pivot := Node3D.new()
		_world.add_child(pivot)
		pivot.add_child(model)
		model.scale = Vector3(k, k, k)
		model.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
		var lock: Node3D = null
		var plate: Node3D = null
		var label: Label3D = null
		var cab := on_rack and n.has_meta("cabinet")
		if cab:
			# gablota: broń wisi na hakach; zamknięta dostaje czerwoną plombę na kabłąku zamiast kłódki
			lock = _cab_box(pivot, Vector3(0.03, 0.05, 0.02), Vector3(0.06, box.size.y * k * 0.35, 0.05), _cab_mat(Color(0.6, 0.05, 0.04), 0.5))
		if on_rack and not cab:
			model.rotation.x = deg_to_rad(-7.0)                   # oparta o deskę
			lock = _item_model("padlock")
			if lock != null:
				lock.scale = Vector3(PX, PX, PX) * 0.75 * float(ITEM_SCALE["padlock"])
				lock.position = Vector3(0.0, box.size.y * k * 0.5 - 3.4 * PX, 0.10)
				lock.rotation.z = deg_to_rad(6.0)
				pivot.add_child(lock)
		if on_rack:
			plate = Node3D.new()
			pivot.add_child(plate)
			var pm := BoxMesh.new()
			pm.size = Vector3(9.0 * PX, 3.0 * PX, 0.02)
			var pmi := MeshInstance3D.new()
			pmi.mesh = pm
			var brass := StandardMaterial3D.new()
			brass.albedo_color = Color(0.55, 0.42, 0.2)
			brass.metallic = 0.4
			brass.roughness = 0.6
			pmi.material_override = brass
			pmi.layers = LAYER_WORLD
			plate.add_child(pmi)
			for sx in [-1.0, 1.0]:                                   # nity
				var rv := SphereMesh.new()
				rv.radius = 0.016
				rv.height = 0.032
				var rmi := MeshInstance3D.new()
				rmi.mesh = rv
				rmi.material_override = brass
				rmi.layers = LAYER_WORLD
				rmi.position = Vector3(sx * 3.9 * PX, 0.0, 0.012)
				plate.add_child(rmi)
			label = Label3D.new()
			label.font = UiTheme.display_font(700)
			label.font_size = 64
			label.pixel_size = 2.1 * PX / 64.0
			label.modulate = Color(0.13, 0.09, 0.05)
			label.outline_size = 0
			label.shaded = true
			label.double_sided = false
			label.layers = LAYER_WORLD
			label.position = Vector3(0.0, 0.0, 0.013)
			plate.add_child(label)
			plate.position = Vector3(0.0, -(RACK_SHELF_PX - 4.1) * RACK_SCALE * PX - 1.6 * PX, RACK_PLATE_Z - RACK_GUN_Z)
			if cab:                                                # gablota: mała tabliczka pod bronią, na filcu (ok. 26 × 9 cm)
				plate.position = Vector3(0.0, -0.06, -CAB_GUN_Z + 0.035)
				plate.scale = Vector3.ONE * 0.35
		_guns[id] = [n, pivot, spr, RACK_GUN_Z if on_rack else -0.25, on_rack, model, lock, plate, label, -1, null, model.position, k, box.size.y * k]
	for id in _guns.keys():
		var g: Array = _guns[id]
		if not is_instance_valid(g[0]) or (g[0] as Node).is_queued_for_deletion() or not is_instance_valid(g[2]):
			if is_instance_valid(g[1]):
				(g[1] as Node).queue_free()
			_guns.erase(id)
			continue
		var sp := g[2] as Node2D
		var pv := g[1] as Node3D
		pv.visible = sp.is_visible_in_tree()
		if not bool(g[4]):
			pv.position = Level3D.px_to_m(sp.global_position) + Vector3(0.0, 0.0, float(g[3]))
			continue
		# lampa nad stojakiem należy do geometrii mapy, a ta bywa budowana od nowa (wejście do kryjówki po misji, zmiana mapy) —
		# gdy lampy nie ma, stawiamy ją ponownie (wcześniej powstawała raz i znikała przy przebudowie)
		var in_cab := (g[0] as Node).has_meta("cabinet")         # broń w gablocie świeci LED-ami gabloty, bez lampy wiszącej
		if not in_cab and _geo_key != "" and (g[10] == null or not is_instance_valid(g[10])):
			g[10] = _add_rack_lamp(g[0] as Node2D)
		if _geo_key != "" and (_rack_probe == null or not is_instance_valid(_rack_probe)):
			_rack_probe = _add_rack_probe()
		# oględziny: oglądana broń kołysze się wokół pionu i lekko pochyla — odblaski wędrują po stali; reszta leży oparta o deskę
		var sway := smoothstep(0.0, 1.0, _fp) if g[0] == _fp_item else 0.0
		var tt := Time.get_ticks_msec() * 0.001
		var turn := Basis(Vector3.UP, sin(tt * 0.8) * deg_to_rad(17.0) * sway) * Basis(Vector3.RIGHT, sin(tt * 0.55) * deg_to_rad(6.0) * sway)
		var lean := deg_to_rad(-7.0)
		if in_cab:                                                 # gablota: wybrana broń nie kręci się, tylko wysuwa ku szybie i lekko uchyla
			turn = Basis(Vector3.RIGHT, deg_to_rad(8.0) * sway)
			lean = 0.0
		(g[5] as Node3D).transform = Transform3D(turn, Vector3.ZERO) * Transform3D(Basis(Vector3.RIGHT, lean).scaled(Vector3.ONE * float(g[12])), g[11] as Vector3)
		if sway > 0.0:
			_place_inspect_lights(pv.position + (Vector3(0.0, 0.0, 0.0) if not in_cab else Vector3(0.0, 0.1, 0.0)), sway)
		var floor_px := (g[0] as Node2D).global_position
		if in_cab:
			# gablota: broń na haku w swoim rzędzie, na osi gabloty (meta „cab_x"), środek bryły na wysokości rzędu
			var slot := int((g[0] as Node).get_meta("slot"))
			var hh := float(g[13]) * 0.5
			pv.position = Level3D.px_to_m(Vector2(float((g[0] as Node).get_meta("cab_x")), floor_px.y + 2.0)) 					+ Vector3(0.0, float(CAB_ROWS[mini(slot, CAB_ROWS.size() - 1)]) - hh, CAB_BACK_Z + CAB_GUN_Z + 0.07 * sway)
		else:
			# stojak: broń na półce (podłoga = początek pickupu), stan blokady z warsztatu
			pv.position = Level3D.px_to_m(floor_px) + Vector3(0.0, (RACK_UP_PX + RACK_SHELF_PX * RACK_SCALE - 2.6) * PX, float(g[3]))
		var arg = (g[0] as Node).get("arg")
		var locked := not Scrap.is_unlocked(arg)
		var price := int(Scrap.price_of(arg))
		var state := (price if locked else -2)
		if state != int(g[9]):
			g[9] = state
			_tint_model(g[5], Color(0.34, 0.36, 0.42) if locked else Color.WHITE)
			if g[6] != null:
				(g[6] as Node3D).visible = locked
			(g[7] as Node3D).visible = locked or in_cab            # gablota: tabliczka pod każdą bronią — cena albo nazwa
			(g[8] as Label3D).text = (("%d" % price) if price > 0 else "SOON") if locked else String(Weapons.def(int(arg)).name)

# ---------------------------------------------------------------- gablota na broń (kryjówka)

func _cab_mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _cab_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.layers = LAYER_WORLD
	parent.add_child(mi)
	return mi

## Model broni do gabloty (pistolet na półce, ślad pustego haka): naturalna długość z gun_proc.py, środek bryły w (0, 0, 0).
func _cab_gun(key: String) -> Node3D:
	var path := GUN_DIR + "gun_%s.glb" % key
	if not ResourceLoader.exists(path):
		return null
	var g := (load(path) as PackedScene).instantiate() as Node3D
	var box := AABB()
	var first := true
	for n in g.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = LAYER_WORLD
		var bb := _local_xf(mi, g) * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var holder := Node3D.new()
	holder.add_child(g)
	g.position = -box.get_center()
	return holder

## Gabloty: bryła powstaje raz na węzeł gabloty (po przebudowie kryjówki — od nowa); drzwi uchylają się, gdy lokalny gracz ogląda broń z tej
## gabloty, a pusty hak (broń wzięta) pokazuje jaśniejszy ślad broni na filcu.
func _sync_cabinets(delta: float) -> void:
	for n in get_tree().get_nodes_in_group("cabinets"):
		if n is Node2D and not (n as Node).is_queued_for_deletion() and not _cabinets.has(n.get_instance_id()):
			_cabinets[n.get_instance_id()] = _build_cabinet(n as Node2D)
	var held := {}                                             # gablota → rzędy, w których wisi broń
	for pk in get_tree().get_nodes_in_group("pickups"):
		if pk.has_meta("cabinet") and not pk.is_queued_for_deletion():
			held["%d:%d" % [int(pk.get_meta("cabinet")), int(pk.get_meta("slot"))]] = true
	var looking := -1
	if _fp_player != null and _fp_item != null and is_instance_valid(_fp_item) and _fp_item.has_meta("cabinet"):
		looking = int(_fp_item.get_meta("cabinet"))
	for id in _cabinets.keys():
		var c: Dictionary = _cabinets[id]
		var node = c["node"]
		if not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
			if is_instance_valid(c["root"]):
				(c["root"] as Node).queue_free()
			_cabinets.erase(id)
			continue
		var idx := int(node.get("index"))
		c["open"] = move_toward(float(c["open"]), 1.0 if looking == idx else 0.0, delta * 2.2)
		(c["door"] as Node3D).rotation.y = deg_to_rad(-105.0) * smoothstep(0.0, 1.0, float(c["open"]))
		var ghosts: Array = c["ghosts"]
		for s in ghosts.size():
			if ghosts[s] != null:
				(ghosts[s] as Node3D).visible = not held.has("%d:%d" % [idx, s])

func _build_cabinet(n: Node2D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Cabinet%d" % int(n.get("index"))
	_world.add_child(root)
	root.position = Level3D.px_to_m(n.global_position) + Vector3(0.0, 0.0, CAB_BACK_Z + CAB_D)
	var W := CAB_W
	var H := CAB_H
	var D := CAB_D
	var steel := _cab_mat(Color(0.045, 0.045, 0.05), 0.5, 0.35)
	var felt := _cab_mat(CAB_FELT, 0.92)
	var slat := _cab_mat(CAB_FELT.darkened(0.6), 0.95)
	var hook := _cab_mat(Color(0.02, 0.02, 0.02), 0.35, 0.7)
	# korpus: boki, cokół, daszek z listwą LED, plecy z filcu, poziome rowki ściany listwowej co 10 cm
	_cab_box(root, Vector3(0.05, H, D), Vector3(-W * 0.5 + 0.025, H * 0.5, -D * 0.5), steel)
	_cab_box(root, Vector3(0.05, H, D), Vector3(W * 0.5 - 0.025, H * 0.5, -D * 0.5), steel)
	_cab_box(root, Vector3(W, 0.12, D), Vector3(0.0, 0.06, -D * 0.5), steel)
	_cab_box(root, Vector3(W, 0.16, D), Vector3(0.0, H - 0.08, -D * 0.5), steel)
	_cab_box(root, Vector3(W - 0.1, H - 0.28, 0.02), Vector3(0.0, 0.12 + (H - 0.28) * 0.5, -D + 0.01), felt)
	var y := 0.2
	while y < H - 0.18:
		_cab_box(root, Vector3(W - 0.1, 0.012, 0.012), Vector3(0.0, y, -D + 0.026), slat)
		y += 0.1
	# haki pod każdym rzędem broni
	var slots := int(n.get("slots"))
	for s in mini(slots, CAB_ROWS.size()):
		for hx in [-0.2, 0.2]:
			_cab_box(root, Vector3(0.018, 0.05, 0.1), Vector3(hx, float(CAB_ROWS[s]) - 0.11, -D + 0.07), hook)
	# ślady pustych haków: płaska, jaśniejsza sylwetka broni na filcu (widać, czego brakuje — broń jest w czyichś rękach)
	var ghosts: Array = []
	var weps: Array = _level.get("_weapons") if _level.get("_weapons") != null else []
	var ghost_m := _cab_mat(CAB_FELT.lightened(0.16), 0.95)
	for s in mini(slots, CAB_ROWS.size()):
		var wi := int(n.get("index")) * slots + s
		var gh: Node3D = null
		if wi < weps.size():
			gh = _cab_gun(String(Weapons.def(int(weps[wi])).key))
		if gh != null:
			gh.position = Vector3(0.0, float(CAB_ROWS[s]), -D + 0.028)
			gh.scale = Vector3(1.0, 1.0, 0.04)
			for m in gh.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).material_override = ghost_m
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gh.visible = false
			root.add_child(gh)
		ghosts.append(gh)
	# półka: pistolet P-83, cztery magazynki, skrzynka amunicji (dekoracja, jak na zdjęciu-wzorze)
	_cab_box(root, Vector3(W - 0.1, 0.025, D - 0.08), Vector3(0.0, CAB_SHELF_Y, -D * 0.5 - 0.02), steel)
	var p64 := _cab_gun("p64")
	if p64 != null:
		p64.position = Vector3(-0.45, CAB_SHELF_Y + 0.075, -D * 0.5 - 0.02)
		root.add_child(p64)
	var mag_m := _cab_mat(Color(0.1, 0.09, 0.08), 0.55, 0.3)
	for i in 4:
		_cab_box(root, Vector3(0.035, 0.15, 0.028), Vector3(-0.17 + i * 0.065, CAB_SHELF_Y + 0.088, -D * 0.5 - 0.05), mag_m)
	_cab_box(root, Vector3(0.28, 0.17, 0.14), Vector3(0.45, CAB_SHELF_Y + 0.098, -D * 0.5 - 0.02), _cab_mat(Color(0.2, 0.22, 0.12), 0.7))
	# daszek: trzy punkty LED (świecące krążki + reflektory z cieniem — plamy światła i cienie broni na filcu) i napis szablonem
	for lx in [-0.5, 0.0, 0.5]:
		var led := _cab_box(root, Vector3(0.07, 0.01, 0.07), Vector3(lx, H - 0.165, -D * 0.5), _cab_mat(CAB_LED))
		var lm := led.material_override as StandardMaterial3D
		lm.emission_enabled = true
		lm.emission = CAB_LED
		lm.emission_energy_multiplier = 6.0
		var sl := SpotLight3D.new()
		sl.position = Vector3(lx, H - 0.18, -D * 0.5)
		sl.basis = Basis.looking_at(Vector3(0.0, -1.0, -0.18), Vector3.FORWARD)
		sl.spot_angle = 38.0
		sl.spot_range = 2.6
		sl.spot_attenuation = 0.8
		sl.light_energy = 3.0
		sl.light_color = CAB_LED
		sl.shadow_enabled = true
		sl.light_volumetric_fog_energy = 0.0                       # bez mgły w gablocie: wnętrze za szybą było mleczne
		sl.layers = LAYER_WORLD | LAYER_ACTORS
		root.add_child(sl)
	var title := Label3D.new()
	title.text = "ARMORY · %s" % CAB_ROMAN[int(n.get("index")) % CAB_ROMAN.size()]
	title.font = UiTheme.display_font(700)
	title.font_size = 64
	title.pixel_size = 0.0011
	title.modulate = Color(0.85, 0.8, 0.65)
	title.outline_size = 0
	title.shaded = true
	title.double_sided = false
	title.layers = LAYER_WORLD
	title.position = Vector3(0.0, H - 0.08, 0.002)
	root.add_child(title)
	# zamek szyfrowy z zieloną diodą na prawym boku
	_cab_box(root, Vector3(0.07, 0.11, 0.025), Vector3(W * 0.5 + 0.035, 1.15, -0.15), _cab_mat(Color(0.08, 0.08, 0.08), 0.4, 0.5))
	var dio := _cab_box(root, Vector3(0.012, 0.012, 0.006), Vector3(W * 0.5 + 0.035, 1.18, -0.135), _cab_mat(Color(0.2, 1.0, 0.3)))
	(dio.material_override as StandardMaterial3D).emission_enabled = true
	(dio.material_override as StandardMaterial3D).emission = Color(0.2, 1.0, 0.3)
	(dio.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0
	# szklane drzwi: jedno skrzydło na zawiasie przy lewym boku, z wąską ramą
	var door := Node3D.new()
	door.position = Vector3(-W * 0.5 + 0.05, 0.0, -0.005)
	root.add_child(door)
	var glass := _cab_mat(Color(0.75, 0.85, 0.9, 0.04), 0.04)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pane := _cab_box(door, Vector3(W - 0.1, H - 0.28, 0.008), Vector3((W - 0.1) * 0.5, 0.12 + (H - 0.28) * 0.5, 0.0), glass)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for fx in [0.0, W - 0.1]:
		_cab_box(door, Vector3(0.02, H - 0.28, 0.02), Vector3(fx, 0.12 + (H - 0.28) * 0.5, 0.0), steel)
	return {"node": n, "root": root, "door": door, "ghosts": ghosts, "open": 0.0}

## „Niebo" warstwy graczy: nie jest rysowane (tło warstwy jest przezroczyste), daje tylko otoczenie do odbić. Bez niego stal trzymanej broni nie
## miała czego odbijać i wyglądała jak tworzywo. To prawdziwa panorama HDRI z Poly Haven (CC0; `tools/polyhaven_fetch.py --hdri`): w misjach noc
## nad polem, w kryjówce wnętrze piwnicy. Panoramy mają przycięte błyski i średnią luminancję 1, więc jasność trzyma sama `ACTOR_REFLECT`
## (razem z `ACTOR_SKY_MEAN`), żeby broń nie świeciła mocniej, niż widać postać w ciemności (GDD §8.3). Bez pliku — niebo proceduralne.
static func _actor_reflection_sky(hub := false) -> Sky:
	var hdri := ACTOR_HDRI_HUB if hub else ACTOR_HDRI_MISSION
	if ResourceLoader.exists(hdri):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(hdri) as Texture2D
		pm.energy_multiplier = ACTOR_REFLECT * ACTOR_SKY_MEAN
		var psky := Sky.new()
		psky.sky_material = pm
		psky.radiance_size = Sky.RADIANCE_SIZE_64
		return psky
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.62, 0.70, 0.88)
	sm.sky_horizon_color = Color(0.10, 0.11, 0.14)
	sm.sky_curve = 0.35
	sm.ground_horizon_color = Color(0.07, 0.07, 0.08)
	sm.ground_bottom_color = Color(0.30, 0.24, 0.18)
	sm.ground_curve = 0.2
	sm.sun_angle_max = 0.0
	sm.sky_energy_multiplier = ACTOR_REFLECT
	sm.ground_energy_multiplier = ACTOR_REFLECT
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	return sky

## Sonda odbić przy stojakach kryjówki: stal broni na półkach odbija pokój (lampy, mur) i dwa niewidoczne dla kamer ekrany — ciepły od strony
## widza z jaśniejszymi pasami i chłodniejszy pod stropem. Działa tylko na broń ze stojaków (`LAYER_REFL`), nie zmienia reszty sceny.
func _add_rack_probe() -> ReflectionProbe:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for g in _guns.values():
		if bool(g[4]) and is_instance_valid(g[1]):
			lo = lo.min((g[1] as Node3D).position)
			hi = hi.max((g[1] as Node3D).position)
	if lo.x == INF:
		return null
	var mid := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5 + 0.5, RACK_GUN_Z + 0.8)
	var span := hi.x - lo.x + 5.0
	var probe := ReflectionProbe.new()
	probe.name = "RackProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(span, 5.0, 6.0)
	probe.position = mid
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.cull_mask = LAYER_WORLD | LAYER_CARD
	probe.reflection_mask = LAYER_REFL
	probe.layers = LAYER_WORLD
	_geo.add_child(probe)
	# ekran od strony widza: ciepłe światło pokoju z kilkoma jaśniejszymi pasami (okna / lampy), ekran górny: chłodniejsza poświata stropu
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.22, 0.34, 0.38, 0.6, 0.64, 0.78, 0.82, 1.0])
	grad.colors = PackedColorArray([Color(0.05, 0.04, 0.03), Color(0.10, 0.08, 0.06), Color(0.9, 0.78, 0.6), Color(0.9, 0.78, 0.6), Color(0.12, 0.10, 0.08),
			Color(0.08, 0.07, 0.06), Color(0.75, 0.68, 0.58), Color(0.75, 0.68, 0.58), Color(0.10, 0.08, 0.06), Color(0.04, 0.035, 0.03)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 8
	for spec in [[Vector3(0.0, 0.4, 2.6), Vector3(0.0, PI, 0.0), Vector2(span, 3.4), 2.6], [Vector3(0.0, 2.2, 0.6), Vector3(PI * 0.5, 0.0, 0.0), Vector2(span, 3.0), 1.4]]:
		var card := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = spec[2]
		card.mesh = qm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color.BLACK
		cm.emission_enabled = true
		cm.emission_texture = gt
		cm.emission_energy_multiplier = float(spec[3])
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		card.material_override = cm
		card.layers = LAYER_CARD
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.position = mid + (spec[0] as Vector3)
		card.rotation = spec[1]
		_geo.add_child(card)
	return probe

## Światła oględzin: ciepłe kluczowe z lewej od strony widza i chłodna kontra znad broni — przy kołysaniu przesuwają odblaski po krawędziach.
## Świecą tylko na oglądaną broń (wąski stożek), jasność rośnie i gaśnie razem z najazdem kamery.
func _place_inspect_lights(at: Vector3, k: float) -> void:
	if _fp_lights.is_empty():
		for spec in [[Color(1.0, 0.93, 0.82), 26.0], [Color(0.72, 0.84, 1.0), 34.0]]:
			var sl := SpotLight3D.new()
			sl.light_color = spec[0]
			sl.spot_angle = float(spec[1])
			sl.spot_range = 4.0
			sl.spot_attenuation = 0.6
			sl.light_specular = 1.6
			sl.shadow_enabled = false
			sl.light_cull_mask = LAYER_WORLD
			sl.light_volumetric_fog_energy = 0.0
			sl.layers = LAYER_WORLD | LAYER_ACTORS
			_world.add_child(sl)
			_fp_lights.append(sl)
	var aim := at + Vector3(0.0, 0.12, 0.0)
	var key := _fp_lights[0] as SpotLight3D
	key.global_position = at + Vector3(-1.0, 0.5, 1.5)
	key.look_at(aim, Vector3.UP)
	key.light_energy = 2.2 * k
	var rim := _fp_lights[1] as SpotLight3D
	rim.global_position = at + Vector3(0.45, 0.85, 0.12)
	rim.look_at(aim, Vector3.RIGHT)
	rim.light_energy = 5.0 * k

## Gruz po rozbitej ścianie: model `rubble` na podłodze przejścia (w głębi, żeby nie zasłaniał drogi) i dwa wyszczerbione fragmenty muru
## przy stropie — wyrwa zamiast gładkiego otworu. Żyje z geometrią mapy.
func _spawn_rubble(floor_pos: Vector3, wall_h: float) -> void:
	var rb := _item_model("rubble")
	if rb != null:
		rb.name = "Rubble"
		rb.scale = Vector3(PX, PX, PX)
		rb.position = Vector3(floor_pos.x, floor_pos.y - 0.02, -0.95)
		rb.rotation.y = 0.3
		_geo.add_child(rb)
	var brick := Level3D.make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone")
	for spec in [[-0.42, 0.34, 0.36, 0.12], [0.36, 0.26, 0.5, -0.1], [-0.1, 0.16, 0.3, 0.05]]:      # x, wysokość, szerokość, obrót
		var bm := BoxMesh.new()
		bm.size = Vector3(float(spec[2]), float(spec[1]), Level3D.DEPTH_BACK * 0.8)
		var mi := MeshInstance3D.new()
		mi.name = "RubbleStub"
		mi.mesh = bm
		mi.material_override = brick
		mi.layers = LAYER_WORLD
		mi.position = Vector3(floor_pos.x + float(spec[0]), floor_pos.y + wall_h - float(spec[1]) * 0.5, -Level3D.DEPTH_BACK * 0.5)
		mi.rotation.z = float(spec[3])
		_geo.add_child(mi)

# ---------------------------------------------------------------- ogień flar

static var _soft_tex: GradientTexture2D

## Miękka, okrągła plamka do cząsteczek ognia (biały środek → przezroczysty brzeg).
static func _soft() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(0.5, 0.0)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex

func _fire_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

## Ogień flary w 3D: język płomienia z cząsteczek (addytywne, rosną ku górze i gasną), iskry unoszone ciepłem i żarzący się rdzeń.
## `col` — barwa flary, `size` — szerokość płomienia [m]. Światło daje osobno światło 3D z opisu światła flary.
func _make_fire(col: Color, size: float) -> Node3D:
	var root := Node3D.new()
	var hot := col.lerp(Color(1.0, 1.0, 0.9), 0.75)
	var flame := CPUParticles3D.new()
	flame.name = "Flame"
	flame.amount = 34
	flame.lifetime = 0.5
	flame.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size * 0.5, size * 0.5)
	q.material = _fire_mat()
	flame.mesh = q
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = size * 0.07
	flame.direction = Vector3.UP
	flame.spread = 9.0
	flame.gravity = Vector3(0.0, size * 4.5, 0.0)
	flame.initial_velocity_min = size * 0.9
	flame.initial_velocity_max = size * 2.0
	flame.scale_amount_min = 0.7
	flame.scale_amount_max = 1.15
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.7))
	sc.add_point(Vector2(0.15, 1.0))
	sc.add_point(Vector2(1.0, 0.08))
	flame.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(hot.r, hot.g, hot.b, 0.0))
	ramp.add_point(0.1, Color(hot.r, hot.g, hot.b, 0.5))
	ramp.add_point(0.45, Color(col.r, col.g, col.b, 0.38))
	ramp.set_color(ramp.get_point_count() - 1, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0))
	flame.color_ramp = ramp
	flame.layers = LAYER_WORLD
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 16
	sparks.lifetime = 1.3
	sparks.local_coords = false
	var sq := QuadMesh.new()
	sq.size = Vector2(size * 0.14, size * 0.14)
	sq.material = _fire_mat()
	sparks.mesh = sq
	sparks.direction = Vector3.UP
	sparks.spread = 26.0
	sparks.gravity = Vector3(0.0, 0.5, 0.0)
	sparks.initial_velocity_min = size * 2.2
	sparks.initial_velocity_max = size * 4.4
	sparks.damping_min = 0.6
	sparks.damping_max = 1.4
	var sramp := Gradient.new()
	sramp.set_color(0, Color(hot.r, hot.g, hot.b, 1.0))
	sramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	sparks.color_ramp = sramp
	sparks.layers = LAYER_WORLD
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sparks)
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sm := SphereMesh.new()
	sm.radius = size * 0.06
	sm.height = size * 0.12
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(hot.r * 1.6, hot.g * 1.6, hot.b * 1.6)
	core.material_override = cm
	core.layers = LAYER_WORLD
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	return root

## Płomień i iskry flar (rzucanych i flary wyjścia) w scenie 3D zamiast rysunku 2D; flara wyjścia ma też pulsujący pierścień strefy na ziemi.
func _sync_fires() -> void:
	for n in get_tree().get_nodes_in_group("flares"):
		if _fires.has(n.get_instance_id()) or not (n is Node2D) or n.is_queued_for_deletion():
			continue
		var f := _make_fire(Color(1.0, 0.45, 0.18), 0.42)
		_world.add_child(f)
		_fires[n.get_instance_id()] = [n, f, "flare", null]
	for n in get_tree().get_nodes_in_group("exit_flares"):
		if _fires.has(n.get_instance_id()) or not (n is Node2D):
			continue
		var col: Color = n.call("_flare_col")
		var f2 := _make_fire(col, 0.85)
		_world.add_child(f2)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.97
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 6
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.albedo_color = col
		ring.material_override = rm
		ring.layers = LAYER_WORLD
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(ring)
		# słup światła nad flarą (znak wyjścia widoczny z daleka), dym i pierścień postępu ewakuacji — odpowiedniki 3D rysunków z exit_flare.gd
		var shaft := _glow_quad(Color(col.r, col.g, col.b, 0.0))
		shaft.name = "Shaft"
		shaft.layers = LAYER_WORLD
		f2.add_child(shaft)
		var smoke := CPUParticles3D.new()
		smoke.name = "Smoke"
		smoke.amount = 14
		smoke.lifetime = 3.0
		smoke.local_coords = false
		var smq := QuadMesh.new()
		smq.size = Vector2(0.5, 0.5)
		var smm := StandardMaterial3D.new()
		smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smm.billboard_keep_scale = true
		smm.vertex_color_use_as_albedo = true
		smm.albedo_texture = _soft()
		smq.material = smm
		smoke.mesh = smq
		smoke.direction = Vector3(0.15, 1.0, 0.0)
		smoke.spread = 16.0
		smoke.initial_velocity_min = 0.5
		smoke.initial_velocity_max = 1.1
		smoke.gravity = Vector3(0.1, 0.15, 0.0)
		var ssc := Curve.new()
		ssc.add_point(Vector2(0.0, 0.4))
		ssc.add_point(Vector2(1.0, 1.8))
		smoke.scale_amount_curve = ssc
		var sgr := Gradient.new()
		sgr.set_color(0, Color(0.45, 0.58, 0.46, 0.0))
		sgr.add_point(0.2, Color(0.45, 0.58, 0.46, 0.10))
		sgr.set_color(sgr.get_point_count() - 1, Color(0.4, 0.45, 0.42, 0.0))
		smoke.color_ramp = sgr
		smoke.layers = LAYER_WORLD
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f2.add_child(smoke)
		var prog := MeshInstance3D.new()
		prog.name = "Progress"
		prog.mesh = ImmediateMesh.new()
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pm.vertex_color_use_as_albedo = true
		prog.material_override = pm
		prog.layers = LAYER_WORLD
		prog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(prog)
		_fires[n.get_instance_id()] = [n, f2, "exit", ring, prog]
	for id in _fires.keys():
		var fr: Array = _fires[id]
		var src_v = fr[0]
		var fire: Node3D = fr[1]
		if not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion():
			# źródło zgasło: cząsteczki dopalają się same, potem węzeł znika
			for ch in fire.get_children():
				if ch is CPUParticles3D:
					(ch as CPUParticles3D).emitting = false
				else:
					(ch as Node3D).visible = false
			get_tree().create_timer(1.5).timeout.connect(fire.queue_free)
			if fr[3] is Node and is_instance_valid(fr[3]):
				(fr[3] as Node).queue_free()
			if fr.size() > 4 and is_instance_valid(fr[4]):
				(fr[4] as Node).queue_free()
			_fires.erase(id)
			continue
		var src := src_v as Node2D
		if String(fr[2]) == "flare":
			var tip := src.global_position + Vector2(0.0, -1.0)
			var pv = src.get("_pv")
			if pv != null and is_instance_valid(pv):
				tip = src.global_transform * ((pv as Node2D).position + Vector2(0.0, -ItemsHd.body_wp("flare").y * 0.25).rotated((pv as Node2D).rotation))
			fire.position = Level3D.px_to_m(tip) + Vector3(0.0, 0.0, -0.2)
			# model tuby (z `_sync_items`) ma inne proporcje niż sprite — płomień siedzi na czubku modelu, nie w punkcie wyliczonym ze sprite'a
			if pv != null and is_instance_valid(pv):
				for ch in (pv as Node).get_children():
					if ch is ItemsHd.ItemMark and _items.has(ch.get_instance_id()) and bool(_items[ch.get_instance_id()][5]):
						var tube := _items[ch.get_instance_id()][1] as Node3D
						if fr[3] == null:
							var top := 0.0
							for mn in tube.find_children("*", "MeshInstance3D", true, false):
								var bb := _local_xf(mn as Node3D, tube) * (mn as MeshInstance3D).get_aabb()
								top = maxf(top, bb.position.y + bb.size.y)
							fr[3] = top
						fire.position = tube.global_transform * Vector3(0.0, float(fr[3]), 0.0)
						break
			var a := clampf(float(src.get("life")) / 3.0, 0.0, 1.0)             # ostatnie 3 s: płomień przygasa
			fire.scale = Vector3.ONE * lerpf(0.35, 1.0, a)
			fire.visible = src.is_visible_in_tree()
		else:
			var on: bool = src.get("_active") == true
			fire.visible = on
			for ch in fire.get_children():
				if ch is CPUParticles3D:
					(ch as CPUParticles3D).emitting = on
			var fl := float(src.get("_flick")) if src.get("_flick") != null else 1.0
			fire.position = Level3D.px_to_m(src.global_position + Vector2(0.0, -13.0)) + Vector3(0.0, 0.0, 0.05)
			fire.scale = Vector3.ONE * lerpf(0.8, 1.15, clampf(fl, 0.7, 1.2) - 0.2)
			var ring := fr[3] as MeshInstance3D
			ring.visible = on
			if on:
				var m_v = src.get("_m")
				var rx := (float(m_v.EXIT_RADIUS_X) if m_v != null else 40.0) * PX
				var ph := fmod(_life, 2.2) / 2.2
				var r := lerpf(0.4, rx + 0.3, ph)
				ring.position = Level3D.px_to_m(src.global_position) + Vector3(0.0, 0.03, 0.0)
				ring.scale = Vector3(r, 1.0, r * 0.55)
				(ring.material_override as StandardMaterial3D).albedo_color.a = 0.5 * (1.0 - ph)
			var fcol: Color = src.call("_flare_col")
			var shaft := fire.get_node("Shaft") as MeshInstance3D
			var sh_h := 9.0 * fl
			_span_quad(shaft, Vector3(0.0, 0.2, -0.1), Vector3(0.0, sh_h, -0.1), 1.5)
			(shaft.material_override as StandardMaterial3D).albedo_color = Color(fcol.r, fcol.g, fcol.b, 0.10 * fl if Settings.quality_idx >= 1 else 0.0)
			(fire.get_node("Smoke") as CPUParticles3D).emitting = on and Settings.quality_idx >= 1
			# pierścień postępu ewakuacji na ziemi wokół flary (0 → 360°)
			var pmesh := (fr[4] as MeshInstance3D).mesh as ImmediateMesh
			(fr[4] as MeshInstance3D).visible = on
			(fr[4] as MeshInstance3D).position = Level3D.px_to_m(src.global_position) + Vector3(0.0, 0.04, 0.0)
			pmesh.clear_surfaces()
			var m_p = src.get("_m")
			var pr := clampf(float(m_p.extract_progress), 0.0, 1.0) if m_p != null else 0.0
			var inside_n := 0
			for hp in src.call("_humans"):
				if not hp.dead and bool(src.call("_inside", hp)):
					inside_n += 1
			if on and (pr > 0.001 or inside_n > 0):
				var r0 := 14.0 * PX
				var hot := fcol.lerp(Color(1, 1, 0.9), 0.55)
				for pass_i in 2:                                   # 0: blady pełny okrąg, 1: jasny łuk postępu
					var frac := 1.0 if pass_i == 0 else pr
					if frac <= 0.001:
						continue
					var cc := Color(fcol.r, fcol.g, fcol.b, 0.16) if pass_i == 0 else Color(hot.r, hot.g, hot.b, 0.95)
					var w := 0.09 if pass_i == 0 else 0.10
					pmesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
					var segs := maxi(3, int(64.0 * frac))
					for si in segs + 1:
						var ang := -PI * 0.5 + TAU * frac * float(si) / float(segs)
						var dirv := Vector3(cos(ang), 0.0, sin(ang) * 0.55)
						pmesh.surface_set_color(cc)
						pmesh.surface_add_vertex(dirv * (r0 - w))
						pmesh.surface_set_color(cc)
						pmesh.surface_add_vertex(dirv * (r0 + w))
					pmesh.surface_end()

# ---------------------------------------------------------------- efekty strzału

## Addytywna płaszczyzna z miękką plamką (nie billboard): do języków ognia, smug i promieni rozciąganych wzdłuż kierunku.
func _glow_quad(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _soft()
	m.albedo_color = col
	mi.material_override = m
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Ustawia płaszczyznę `mi` jako pas od `a` do `b` (świat 3D) o szerokości `w`, zwróconą do kamery (kamera patrzy wzdłuż −Z).
func _span_quad(mi: MeshInstance3D, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var len := maxf(d.length(), 0.001)
	mi.position = (a + b) * 0.5
	mi.basis = Basis(d / len * len, Vector3(-d.y, d.x, 0.0).normalized() * w, Vector3(0, 0, 1))

## Rozbłysk wylotowy, ładowanie broni energetycznej, promień LR-7 i płomień miotacza w scenie 3D — przy wylocie lufy modelu broni.
## Stan czytany z `weapon_view.gd` gracza (`_flash_t`, `w_state`, `w_firing`, `_beam_end`, `flame_on`).
func _sync_weapon_fx() -> void:
	for p in _rigs.keys():
		if not is_instance_valid(p):
			continue
		var rig: Dictionary = _rigs[p]
		var wv = p.get("view")
		var c3 = p.get("c3d")
		if wv == null or not is_instance_valid(wv) or c3 == null or rig["gun"] == null or not is_instance_valid(rig["gun"]):
			continue
		if not rig.has("wfx"):
			var root := Node3D.new()
			_world.add_child(root)
			var star := _glow_quad(Color.WHITE)                 # jądro rozbłysku (billboard)
			(star.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			var tongue := _glow_quad(Color.WHITE)               # język ognia wzdłuż lufy
			var cross := _glow_quad(Color.WHITE)                # poprzeczny błysk (gwiazda)
			var charge := _glow_quad(Color.WHITE)
			(charge.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			var beam_a := _glow_quad(Color.WHITE)               # poświata promienia
			var beam_b := _glow_quad(Color.WHITE)               # rdzeń promienia
			var beam_hit := _glow_quad(Color.WHITE)
			(beam_hit.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			for n in [star, tongue, cross, charge, beam_a, beam_b, beam_hit]:
				root.add_child(n)
			var flame := CPUParticles3D.new()                    # miotacz: strumień ognia
			flame.emitting = false
			flame.amount = 70
			flame.lifetime = 0.5
			flame.local_coords = false
			var fq := QuadMesh.new()
			fq.size = Vector2(0.34, 0.34)
			fq.material = _fire_mat()
			flame.mesh = fq
			flame.gravity = Vector3(0.0, 0.5, 0.0)
			var fsc := Curve.new()
			fsc.add_point(Vector2(0.0, 0.35))
			fsc.add_point(Vector2(0.6, 1.3))
			fsc.add_point(Vector2(1.0, 1.6))
			flame.scale_amount_curve = fsc
			var fg := Gradient.new()
			fg.set_color(0, Color(1.0, 0.95, 0.65, 0.8))
			fg.add_point(0.4, Color(1.0, 0.5, 0.12, 0.6))
			fg.set_color(fg.get_point_count() - 1, Color(0.25, 0.1, 0.06, 0.0))
			flame.color_ramp = fg
			flame.layers = LAYER_ACTORS
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(flame)
			rig["wfx"] = {"root": root, "star": star, "tongue": tongue, "cross": cross, "charge": charge, "beam_a": beam_a, "beam_b": beam_b, "beam_hit": beam_hit, "flame": flame}
		var fx: Dictionary = rig["wfx"]
		var gun := rig["gun"] as Node3D
		var dead := bool(p.get("dead"))
		var muzzle: Vector3 = gun.global_transform * (c3._gun_info["muzzle"] as Vector3)
		var aim2: Vector2 = p.get("aim_dir")
		var aim := Vector3(aim2.x, -aim2.y, 0.0).normalized()
		var d = wv.Weapons.def(p.get("weapon"))
		# rozbłysk
		var ft := float(wv.get("_flash_t"))
		var on_flash := ft > 0.0 and float(d.flash_size) > 0.0 and not dead and gun.visible
		for k in ["star", "tongue", "cross"]:
			(fx[k] as Node3D).visible = on_flash
		if on_flash:
			var k := clampf(ft / (float(wv.FLASH_TIME) * (1.0 + float(d.flash_size) / 12.0)), 0.0, 1.0)
			var r := float(d.flash_size) * PX * (0.55 + 0.45 * k)
			var col: Color = d.flash_color
			var seed := float(wv.get("_flash_seed"))
			(fx["star"] as Node3D).position = muzzle + aim * r * 0.25
			(fx["star"] as Node3D).scale = Vector3.ONE * r * 1.7
			((fx["star"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.97, 0.85, k)
			_span_quad(fx["tongue"], muzzle, muzzle + aim * r * 2.6, r * 0.9)
			((fx["tongue"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.9 * k)
			var side := Vector3(-aim.y, aim.x, 0.0).rotated(Vector3(0, 0, 1), sin(seed * 7.0) * 0.35)
			_span_quad(fx["cross"], muzzle + aim * r * 0.3 - side * r * 1.1, muzzle + aim * r * 0.3 + side * r * 1.1, r * 0.5)
			((fx["cross"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.7 * k)
		# ładowanie
		var charging := int(p.get("w_state")) == int(wv.Controller.State.CHARGE) and not dead
		(fx["charge"] as Node3D).visible = charging
		if charging:
			var ch := clampf(float(p.get("w_charge")), 0.0, 1.0)
			var tc: Color = d.tracer_color
			(fx["charge"] as Node3D).position = muzzle
			(fx["charge"] as Node3D).scale = Vector3.ONE * (3.0 + 9.0 * ch) * PX * (1.0 + 0.12 * sin(_life * 40.0) * ch)
			((fx["charge"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(lerpf(tc.r, 1.0, ch * 0.6), lerpf(tc.g, 1.0, ch * 0.6), lerpf(tc.b, 1.0, ch * 0.6), 0.4 + 0.6 * ch)
		# promień
		var beaming := bool(p.get("w_firing")) and int(d.kind) == int(wv.WeaponDef.Kind.BEAM) and not dead
		for k in ["beam_a", "beam_b", "beam_hit"]:
			(fx[k] as Node3D).visible = beaming
		if beaming:
			var bc: Color = d.tracer_color
			var end2: Vector2 = wv.get("_beam_end")
			var end3 := Level3D.px_to_m((wv as Node2D).to_global(end2)) + Vector3(0.0, 0.0, muzzle.z)
			var fl := randf_range(0.85, 1.0)
			_span_quad(fx["beam_a"], muzzle, end3, 9.0 * PX)
			((fx["beam_a"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(bc.r, bc.g, bc.b, 0.55 * fl)
			_span_quad(fx["beam_b"], muzzle, end3, 2.6 * PX)
			((fx["beam_b"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.95 * fl)
			(fx["beam_hit"] as Node3D).position = end3
			(fx["beam_hit"] as Node3D).scale = Vector3.ONE * 8.0 * PX * fl
			((fx["beam_hit"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(bc.r, bc.g, bc.b, 0.9)
		# płomień miotacza
		var flame3 := fx["flame"] as CPUParticles3D
		var burning: bool = wv.get("flame_on") == true and not dead
		flame3.emitting = burning
		if burning:
			flame3.position = muzzle
			flame3.direction = aim
			flame3.spread = float(wv.get("flame_spread"))
			flame3.initial_velocity_min = 80.0 * PX
			flame3.initial_velocity_max = float(wv.get("flame_vmax")) * PX
			flame3.lifetime = 0.5

## Wołane z `Vfx.streak`: smuga pocisku / szyny jako dwa addytywne pasy (poświata i rdzeń), gasnące przez `life` s.
func mirror_streak(a: Vector2, b: Vector2, color: Color, width: float, life: float) -> void:
	var a3 := Level3D.px_to_m(a) + Vector3(0.0, 0.0, 0.3)
	var b3 := Level3D.px_to_m(b) + Vector3(0.0, 0.0, 0.3)
	var halo := _glow_quad(Color(color.r, color.g, color.b, 0.6))
	var core := _glow_quad(Color(1, 1, 1, 0.95))
	_world.add_child(halo)
	_world.add_child(core)
	_span_quad(halo, a3, b3, width * 3.4 * PX)
	_span_quad(core, a3, b3, maxf(width * 0.9, 1.0) * PX)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(halo.material_override, "albedo_color:a", 0.0, life)
	tw.tween_property(core.material_override, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(halo.queue_free)
	tw.tween_callback(core.queue_free)

## Szerokość smugi szybkiej kuli [m]: (poświata, rdzeń) — kula i śrucina.
const TRACE_W := Vector2(0.22, 0.055)
const TRACE_W_PELLET := Vector2(0.13, 0.034)
static var _tracer_tex: Texture2D

## Tekstura smugi: wzdłuż (u) od przezroczystego ogona do jasnej głowy z zaokrąglonym czołem, w poprzek (v) miękki profil.
static func _tracer_texture() -> Texture2D:
	if _tracer_tex == null:
		var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
		for x in 64:
			var u := (float(x) + 0.5) / 64.0
			var along := pow(u, 1.6) * (1.0 - smoothstep(0.9, 1.0, u) * 0.85)
			for y in 16:
				var v := ((float(y) + 0.5) / 16.0 - 0.5) / 0.5
				img.set_pixel(x, y, Color(1, 1, 1, along * exp(-v * v * 3.2)))
		_tracer_tex = ImageTexture.create_from_image(img)
	return _tracer_tex

## Pas smugi (addytywny, jak `_glow_quad`, ale z teksturą ogon → głowa; `_span_quad` kładzie oś U wzdłuż lotu).
func _trace_quad(col: Color) -> MeshInstance3D:
	var mi := _glow_quad(col)
	(mi.material_override as StandardMaterial3D).albedo_texture = _tracer_texture()
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Wołane z `Vfx.trace`: ostatni odcinek lotu szybkiej kuli (trafienie, ściana, koniec zasięgu) dogasa przez `life` s zamiast zniknąć w klatce.
func mirror_trace(a: Vector2, b: Vector2, color: Color, pellet: bool, life: float) -> void:
	var w: Vector2 = TRACE_W_PELLET if pellet else TRACE_W
	var halo := _trace_quad(Color(color.r, color.g, color.b, 0.5 if pellet else 0.8))
	var core := _trace_quad(Color(1.0, 0.97, 0.85, 0.85 if pellet else 1.0))
	_world.add_child(halo)
	_world.add_child(core)
	var a3 := Level3D.px_to_m(a) + Vector3(0.0, 0.0, 0.3)
	var b3 := Level3D.px_to_m(b) + Vector3(0.0, 0.0, 0.3)
	_span_quad(halo, a3, b3, w.x)
	_span_quad(core, a3, b3, w.y)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(halo.material_override, "albedo_color:a", 0.0, life)
	tw.tween_property(core.material_override, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(halo.queue_free)
	tw.tween_callback(core.queue_free)

# ---------------------------------------------------------------- ślady po kulach i osmalenia (od 1.7.312)

const MAX_HOLES := 160                      ## najstarsze ślady po kulach znikają ponad ten limit
const MAX_SCORCH := 24
const HOLE_M := 0.09                        ## średnica śladu po kuli [m]
const MARK_Z := 0.3                         ## głębokość płaszczyzny lotu kul w scenie (jak smugi)
var _holes: Array = []
var _scorches: Array = []
static var _hole_tex: Texture2D
static var _scorch_tex: Texture2D

## Tekstura śladu po kuli: ciemny otwór, poszarpany jaśniejszy pierścień odprysku, miękki brzeg.
static func _make_mark_tex(scorch: bool) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 87 if scorch else 7
	var bumps: Array = []
	for i in 16:
		bumps.append(rng.randf_range(0.82, 1.18))
	for y in n:
		for x in n:
			var v := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5) * 2.0
			var r := v.length()
			var a := fposmod(v.angle() / TAU, 1.0) * 16.0
			var j := lerpf(bumps[int(a) % 16], bumps[(int(a) + 1) % 16], a - floorf(a))
			var rr := r / j
			var c: Color
			if scorch:
				var k := clampf(1.0 - rr, 0.0, 1.0)
				c = Color(0.02, 0.018, 0.015, clampf(pow(k, 0.45) * 1.15, 0.0, 0.95) * (0.8 + 0.2 * rng.randf()))     # sadza: gęsta w środku, postrzępiony brzeg
			elif rr < 0.28:
				c = Color(0.02, 0.02, 0.02, 1.0)
			elif rr < 0.62:
				c = Color(0.55, 0.52, 0.48, (1.0 - (rr - 0.28) / 0.34) * 0.55)
			else:
				c = Color(0.1, 0.09, 0.08, clampf((1.0 - rr) / 0.38, 0.0, 1.0) * 0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

## Decal 3D w punkcie `pos` (px) na powierzchni o normalnej `normal` (2D): rzut wzdłuż −normalnej, tylko na geometrię świata.
func _mark(pos: Vector2, normal: Vector2, size_m: float, tex: Texture2D, depth: float) -> Decal:
	var dcl := Decal.new()
	dcl.texture_albedo = tex
	dcl.size = Vector3(size_m, depth, size_m)
	dcl.cull_mask = LAYER_WORLD
	dcl.upper_fade = 0.0
	dcl.lower_fade = 0.0
	var up := Vector3(normal.x, -normal.y, 0.0).normalized()
	var side := up.cross(Vector3(0, 0, 1)).normalized()
	dcl.basis = Basis(side, up, side.cross(up)).orthonormalized().rotated(up, randf() * TAU)
	dcl.position = Level3D.px_to_m(pos) + Vector3(0.0, 0.0, MARK_Z)
	_world.add_child(dcl)
	return dcl

## Wołane z `Vfx.impact`: ślad po kuli w murze, gruncie, blasze (ciecze bez śladu — Vfx tego pilnuje).
func mark_hit(pos: Vector2, normal: Vector2, _surface: String) -> void:
	if _hole_tex == null:
		_hole_tex = _make_mark_tex(false)
	_holes.append(_mark(pos, normal, HOLE_M * randf_range(0.8, 1.2), _hole_tex, 0.12))
	while _holes.size() > MAX_HOLES:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

## Wołane z `Vfx.explosion`: osmalenie gruntu pod wybuchem, średnica wg zasięgu fali (`radius_px`).
func mark_scorch(pos: Vector2, radius_px: float) -> void:
	if _scorch_tex == null:
		_scorch_tex = _make_mark_tex(true)
	var d := _mark(pos, Vector2.UP, clampf(radius_px * PX * 0.5, 0.6, 2.5), _scorch_tex, 0.5)        # WRATH-4 (48 px): ok. 2 m
	_scorches.append(d)
	while _scorches.size() > MAX_SCORCH:
		var old = _scorches.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

## Wołane z `Vfx.casing`: łuska jako mosiężny (śrutowa: czerwony) walec 3D podążający za ciałem fizycznym 2D; rysunek 2D jest chowany.
## Wymiary naturalne względem broni (ta ma od 1.7.213 naturalną skalę): łuska karabinowa ok. 42 × 13 mm, śrutowa kal. 12 ok. 72 × 21 mm.
## Ciało fizyczne jest większe od bryłki, więc ta leży niżej o różnicę — inaczej łuska wisiałaby nad ziemią.
func mirror_casing(body: RigidBody2D, big: bool) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0105 if big else 0.0065
	cm.bottom_radius = cm.top_radius
	cm.height = 0.072 if big else 0.042
	mi.set_meta("drop", (1.0 if big else 0.5) * PX - cm.top_radius)
	cm.radial_segments = 8
	cm.rings = 0
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.12, 0.1) if big else Color(0.8, 0.6, 0.25)
	m.metallic = 0.2 if big else 0.85
	m.roughness = 0.6 if big else 0.32
	mi.material_override = m
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	body.modulate = Color(1, 1, 1, 0)
	if _casings.has(body.get_instance_id()) and is_instance_valid(_casings[body.get_instance_id()][1]):
		(_casings[body.get_instance_id()][1] as Node).queue_free()       # ogólna bryłka z `mirror_debris`
	_casings[body.get_instance_id()] = [body, mi, randf_range(-0.5, 0.5)]

func _sync_casings() -> void:
	for id in _casings.keys():
		var cs: Array = _casings[id]
		if not is_instance_valid(cs[0]) or (cs[0] as Node).is_queued_for_deletion():
			if is_instance_valid(cs[1]):
				(cs[1] as Node).queue_free()
			_casings.erase(id)
			continue
		var b := cs[0] as RigidBody2D
		var mi := cs[1] as Node3D
		mi.position = Level3D.px_to_m(b.global_position) + Vector3(0.0, -float(mi.get_meta("drop", 0.0)), 0.35 + float(cs[2]) * 0.3)
		mi.rotation = Vector3(float(cs[2]), 0.0, -b.global_rotation + (float(cs[3]) if cs.size() > 3 else PI * 0.5))       # łuska: walec wzdłuż osi łuski 2D; szczątek: płasko

# ---------------------------------------------------------------- ogień, wybuchy, dym

## Pas ognia o szerokości `width` [m]: języki płomieni z całej długości, iskry i żar przy ziemi (plamy ognia miotacza, płonące ciała).
func _make_fire_line(width: float, height: float, col := Color(1.0, 0.5, 0.15)) -> Node3D:
	var root := Node3D.new()
	var hot := col.lerp(Color(1.0, 0.95, 0.7), 0.7)
	var flame := CPUParticles3D.new()
	flame.name = "Flame"
	flame.amount = int(clampf(width * 20.0, 12.0, 80.0))
	flame.lifetime = 0.7
	flame.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(height * 0.42, height * 0.42)
	q.material = _fire_mat()
	flame.mesh = q
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flame.emission_box_extents = Vector3(width * 0.5, 0.02, 0.18)
	flame.direction = Vector3.UP
	flame.spread = 14.0
	flame.gravity = Vector3(0.0, height * 3.4, 0.0)
	flame.initial_velocity_min = height * 0.9
	flame.initial_velocity_max = height * 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.2, 1.0))
	sc.add_point(Vector2(1.0, 0.1))
	flame.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(hot.r, hot.g, hot.b, 0.0))
	ramp.add_point(0.08, Color(hot.r, hot.g, hot.b, 0.36))
	ramp.add_point(0.35, Color(col.r, col.g, col.b, 0.36))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.1, 0.03, 0.0))
	flame.color_ramp = ramp
	flame.layers = LAYER_WORLD
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = int(clampf(width * 8.0, 5.0, 24.0))
	sparks.lifetime = 1.2
	sparks.local_coords = false
	var sq := QuadMesh.new()
	sq.size = Vector2(0.045, 0.045)
	sq.material = _fire_mat()
	sparks.mesh = sq
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(width * 0.5, 0.05, 0.18)
	sparks.direction = Vector3.UP
	sparks.spread = 28.0
	sparks.gravity = Vector3(0.0, 0.6, 0.0)
	sparks.initial_velocity_min = height * 1.5
	sparks.initial_velocity_max = height * 3.2
	var sr := Gradient.new()
	sr.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
	sr.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	sparks.color_ramp = sr
	sparks.layers = LAYER_WORLD
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sparks)
	return root

func _stop_fire(root: Node3D, after := 1.4) -> void:
	for ch in root.get_children():
		if ch is CPUParticles3D:
			(ch as CPUParticles3D).emitting = false
		else:
			(ch as Node3D).visible = false
	get_tree().create_timer(after).timeout.connect(root.queue_free)

## Plamy ognia miotacza, płonące ciała i chmury dymu w scenie 3D (rysunek 2D chowany przez `self_modulate`).
func _sync_burning() -> void:
	for n in get_tree().get_nodes_in_group("fire_patches"):
		if _burn.has(n.get_instance_id()) or not (n is Node2D) or n.is_queued_for_deletion():
			continue
		var f := _make_fire_line(float(n.HALF_W) * 2.0 * PX, 0.9)
		_world.add_child(f)
		(n as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		_burn[n.get_instance_id()] = [n, f, "patch", 0.0]
	for n in get_tree().get_nodes_in_group("smoke_clouds"):
		if _burn.has(n.get_instance_id()) or not (n is Node2D) or n.is_queued_for_deletion():
			continue
		var root := Node3D.new()
		_world.add_child(root)
		var fv := FogVolume.new()                               # prawdziwy dym: bryła mgły oświetlana latarką i ogniem (jakość MEDIUM / HIGH)
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var fm := FogMaterial.new()
		fm.density = 2.2
		fm.albedo = Color(0.42, 0.44, 0.47)
		fm.edge_fade = 0.5
		fv.material = fm
		root.add_child(fv)
		var puffs := CPUParticles3D.new()                       # kłęby: widoczne także bez mgły wolumetrycznej
		puffs.amount = 22
		puffs.lifetime = 3.2
		puffs.local_coords = false
		var pq := QuadMesh.new()
		pq.size = Vector2(1.6, 1.6)
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		pm.billboard_keep_scale = true
		pm.vertex_color_use_as_albedo = true
		pm.albedo_texture = n.puff_texture()
		pq.material = pm
		puffs.mesh = pq
		puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		puffs.gravity = Vector3(0.0, 0.12, 0.0)
		puffs.initial_velocity_min = 0.05
		puffs.initial_velocity_max = 0.25
		puffs.spread = 180.0
		puffs.angle_min = 0.0
		puffs.angle_max = 360.0
		var pr := Gradient.new()
		pr.set_color(0, Color(0.16, 0.17, 0.19, 0.0))
		pr.add_point(0.25, Color(0.20, 0.21, 0.24, 0.34))
		pr.set_color(pr.get_point_count() - 1, Color(0.26, 0.27, 0.3, 0.0))
		puffs.color_ramp = pr
		puffs.layers = LAYER_ACTORS
		puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(puffs)
		(n as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		_burn[n.get_instance_id()] = [n, root, "smoke", 0.0]
	for id in _burn.keys():
		var br: Array = _burn[id]
		var src_v = br[0]
		var node := br[1] as Node3D
		var kind := String(br[2])
		var gone: bool = not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion()
		if kind == "host" and not gone and _life > float(br[3]):
			gone = true
		if kind == "host" and not gone and (src_v.get("alive") == false or not (src_v as CanvasItem).is_visible_in_tree()):
			gone = true
		if gone:
			if is_instance_valid(node):
				if kind == "smoke":
					node.queue_free()
				else:
					_stop_fire(node)
			_burn.erase(id)
			continue
		var src := src_v as Node2D
		if kind == "patch":
			node.position = Level3D.px_to_m(src.global_position) + Vector3(0.0, 0.02, 0.25)
			var fade := clampf(float(src.get("life")) / 0.8, 0.0, 1.0)
			node.scale = Vector3(1.0, lerpf(0.3, 1.0, fade), 1.0)
		elif kind == "host":
			node.position = Level3D.px_to_m(src.global_position + Vector2(0.0, -4.0)) + Vector3(0.0, 0.0, 0.35)
		else:
			var r := maxf(float(src.get("radius")), 1.0) * PX
			var fade2 := clampf(float(src.get("life")) / 2.0, 0.0, 1.0)
			node.position = Level3D.px_to_m(src.global_position) + Vector3(0.0, 0.0, 0.2)
			var fv2 := node.get_child(0) as FogVolume
			fv2.size = Vector3(r * 2.0, r * 1.7, 3.0)
			(fv2.material as FogMaterial).density = 2.2 * fade2
			var pf := node.get_child(1) as CPUParticles3D
			pf.emission_sphere_radius = r * 0.7
			pf.scale_amount_min = r * 0.5
			pf.scale_amount_max = r * 0.9
			pf.emitting = fade2 > 0.35

## Wołane z `Vfx.burning`: płomienie na ciele (wróg, beczka) przez `seconds` s.
func mirror_burning(host: Node2D, seconds: float) -> void:
	var id := host.get_instance_id()
	if _burn.has(id):
		_burn[id][3] = _life + seconds
		return
	var f := _make_fire_line(0.6, 0.75)
	_world.add_child(f)
	_burn[id] = [host, f, "host", _life + seconds]

## Wołane z `Vfx.shock`: fala uderzeniowa jako rozszerzający się pierścień zwrócony do kamery.
func mirror_shock(pos: Vector2, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 6
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.55, 0.7)
	ring.material_override = m
	ring.layers = LAYER_ACTORS
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Level3D.px_to_m(pos) + Vector3(0.0, 0.0, 0.3)
	ring.rotation.x = PI * 0.5
	var r0 := radius * PX * 0.25
	var r1 := radius * PX * 1.1
	ring.scale = Vector3(r0, r0, r0)
	_world.add_child(ring)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(r1, r1, r1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(ring.queue_free)

## Wołane z `Vfx.explosion`: kula ognia (błysk rosnący i gasnący), języki ognia rozrzucone wybuchem i unoszący się kłąb dymu.
func mirror_explosion(pos: Vector2, radius: float) -> void:
	var at := Level3D.px_to_m(pos) + Vector3(0.0, 0.0, 0.3)
	var r := radius * PX
	var ball := _glow_quad(Color(1.0, 0.8, 0.5, 0.55))
	(ball.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ball.position = at
	ball.scale = Vector3.ONE * r * 0.5
	_world.add_child(ball)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * r * 1.5, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball.material_override, "albedo_color", Color(1.0, 0.4, 0.1, 0.0), 0.3)
	tw.chain().tween_callback(ball.queue_free)
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.amount = int(clampf(r * 9.0, 14.0, 50.0))
	fire.lifetime = 0.55
	var q := QuadMesh.new()
	q.size = Vector2(r * 0.4, r * 0.4)
	q.material = _fire_mat()
	fire.mesh = q
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = r * 0.2
	fire.spread = 180.0
	fire.initial_velocity_min = r * 0.8
	fire.initial_velocity_max = r * 3.2
	fire.damping_min = 3.0
	fire.damping_max = 6.0
	fire.gravity = Vector3(0.0, 1.5, 0.0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	fire.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.65, 0.3))
	g.add_point(0.35, Color(1.0, 0.45, 0.1, 0.24))
	g.set_color(g.get_point_count() - 1, Color(0.25, 0.08, 0.04, 0.0))
	fire.color_ramp = g
	fire.layers = LAYER_WORLD
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.position = at
	_world.add_child(fire)
	fire.emitting = true
	get_tree().create_timer(1.4).timeout.connect(fire.queue_free)

## Wołane z `Vfx.debris`: odłamek / szczątek jako nieregularna bryłka 3D w kolorze 2D, podążająca za ciałem fizycznym.
func mirror_debris(body: RigidBody2D, size: Vector2, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 6
	sm.rings = 3
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b).darkened(0.45)
	m.roughness = 0.32                                         # mokre
	m.metallic_specular = 0.7
	mi.material_override = m
	mi.scale = Vector3(maxf(size.x, 1.0) * randf_range(0.5, 0.8), maxf(size.y, 1.0) * randf_range(0.3, 0.5), maxf(size.y, 1.0) * randf_range(0.45, 0.8)) * PX
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	body.modulate = Color(1, 1, 1, 0)
	_casings[body.get_instance_id()] = [body, mi, randf_range(-0.5, 0.5), 0.0]

const GIB_MODELS := [["gib_meat_b", "gib_meat_c"], ["gib_bone_a", "gib_bone_b"], ["gib_gut_a"]]      # rodzaj z `Vfx._gibs_hd`: 0 mięso, 1 kość, 2 wnętrzności

## Wołane z `Vfx._gibs_hd`: szczątek jako model 3D (art/items3d/gib_*.glb, generowane lokalnie — `tools/comfy_gen.py`), podążający za
## ciałem fizycznym; zastępuje ogólną bryłkę z `mirror_debris`. `sz` — rozmiar szczątka w pikselach świata.
func mirror_gib(body: RigidBody2D, kind: int, sz: float) -> void:
	var names: Array = GIB_MODELS[clampi(kind, 0, GIB_MODELS.size() - 1)]
	var mm := Level3D.model_mesh(String(names[randi() % names.size()]))
	if mm.is_empty():
		return                                                # brak modelu: zostaje bryłka
	var gname := String((mm[0] as Mesh).resource_path)
	if not _item_tuned.has(gname):                             # jednorazowo: mapy metalu i normalnych z generatora dawały połysk „zmiętej folii”
		_item_tuned[gname] = true
		for si in (mm[0] as Mesh).get_surface_count():
			var gm := (mm[0] as Mesh).surface_get_material(si) as BaseMaterial3D
			if gm != null:
				gm.metallic = 0.0
				gm.metallic_texture = null
				gm.roughness_texture = null
				gm.roughness = 0.82                               # matowe: w snopie latarki (bardzo jasny reflektor) gładsza powierzchnia skrzyła się jak folia
				gm.metallic_specular = 0.12
				gm.normal_scale = 0.3
				gm.albedo_color = Color(0.62, 0.55, 0.55)
	var pivot := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mm[0]
	var xf: Transform3D = mm[1]
	var box: AABB = xf * (mm[0] as Mesh).get_aabb()
	mi.transform = Transform3D(xf.basis, xf.origin - box.get_center())       # obrót wokół środka bryły
	mi.layers = LAYER_ACTORS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	var k := sz * PX * (1.25 if kind == 1 else 0.95) / maxf(box.get_longest_axis_size(), 0.001)
	pivot.scale = Vector3(k, k, k)
	_world.add_child(pivot)
	body.modulate = Color(1, 1, 1, 0)
	var id := body.get_instance_id()
	if _casings.has(id) and is_instance_valid(_casings[id][1]):
		(_casings[id][1] as Node).queue_free()
	_casings[id] = [body, pivot, randf_range(-0.6, 0.6), randf() * TAU]

# ---------------------------------------------------------------- plwocina, kwas i efekty Żyły

const MAW_Z := 1.25                      ## głębia żaru paszczy Żyły: tuż przed pyskiem modelu
const WAVE_Z := 0.9                      ## pół szerokości fali i pasma zapowiedzi w głąb sceny [m]

## Materiał addytywny dla siatek rysowanych co klatkę (łuki, pasma): kolor i przezroczystość z wierzchołków.
func _add_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m

func _imm(parent: Node3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = mat
	mi.layers = LAYER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Plwocina Żyły (`boss.gd: SpitGlob`, grupa „spit_globs") i kwas Pijawki (`acid_spit.gd`, grupa „acid"): świecąca kula 3D ze smugą kropel
## i własnym zielonym światłem; rysunek 2D jest chowany. Lot liczy nadal węzeł 2D.
func _sync_globs() -> void:
	for g in ["spit_globs", "acid"]:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node2D) or n.is_queued_for_deletion() or _globs.has(n.get_instance_id()):
				continue
			var root := Node3D.new()
			root.name = "Glob"
			_sphere(root, 3.4 * PX, Vector3.ZERO, Color(0.45, 0.95, 0.25))
			_sphere(root, 1.5 * PX, Vector3(-1.0 * PX, 1.0 * PX, 2.6 * PX), Color(0.85, 1.0, 0.6))
			var drips := CPUParticles3D.new()
			drips.name = "Drips"
			drips.local_coords = false
			drips.amount = 18
			drips.lifetime = 0.4
			var q := QuadMesh.new()
			q.size = Vector2(0.13, 0.13)
			var qm := StandardMaterial3D.new()
			qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			qm.billboard_keep_scale = true
			qm.vertex_color_use_as_albedo = true
			qm.albedo_texture = _soft()
			q.material = qm
			drips.mesh = q
			drips.spread = 180.0
			drips.initial_velocity_min = 0.1
			drips.initial_velocity_max = 0.5
			drips.gravity = Vector3(0.0, -5.0, 0.0)
			var sc := Curve.new()
			sc.add_point(Vector2(0.0, 1.0))
			sc.add_point(Vector2(1.0, 0.2))
			drips.scale_amount_curve = sc
			var gr := Gradient.new()
			gr.set_color(0, Color(0.5, 0.95, 0.3, 0.8))
			gr.set_color(1, Color(0.3, 0.7, 0.2, 0.0))
			drips.color_ramp = gr
			drips.layers = LAYER_ACTORS
			drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(drips)
			var gl := OmniLight3D.new()
			gl.light_color = Color(0.55, 1.0, 0.35)
			gl.light_energy = 1.4
			gl.omni_range = 2.6
			gl.light_volumetric_fog_energy = 0.6
			gl.layers = LAYER_WORLD | LAYER_ACTORS
			root.add_child(gl)
			_world.add_child(root)
			(n as CanvasItem).self_modulate = Color(1, 1, 1, 0)
			_globs[n.get_instance_id()] = [n, root]
	for id in _globs.keys():
		var src = _globs[id][0]
		var g3: Node3D = _globs[id][1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(g3):
				g3.queue_free()
			_globs.erase(id)
			continue
		g3.position = Level3D.px_to_m((src as Node2D).global_position) + Vector3(0.0, 0.0, 0.3)

## Głaz Wołka (`boulder.gd`, grupa „boulders"): kamień z modelu `rock_b` (skan Poly Haven) o średnicy ok. 16 px, obracający się w locie. Lot liczy węzeł 2D.
func _sync_boulders() -> void:
	for n in get_tree().get_nodes_in_group("boulders"):
		if not (n is Node2D) or n.is_queued_for_deletion() or _boulders.has(n.get_instance_id()):
			continue
		var root := Node3D.new()
		root.name = "Boulder"
		var mdl := _item_model("rock_b")
		if mdl != null:
			var big := 0.001
			for mi in mdl.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).mesh != null:
					big = maxf(big, (mi as MeshInstance3D).mesh.get_aabb().size.length())
			var k := 16.0 * PX / big
			mdl.scale = Vector3(k, k, k)
			root.add_child(mdl)
		else:
			_sphere(root, 7.0 * PX, Vector3.ZERO, Color(0.45, 0.42, 0.38))
		_world.add_child(root)
		(n as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		_boulders[n.get_instance_id()] = [n, root]
	for id in _boulders.keys():
		var src = _boulders[id][0]
		var b3: Node3D = _boulders[id][1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(b3):
				b3.queue_free()
			_boulders.erase(id)
			continue
		b3.position = Level3D.px_to_m((src as Node2D).global_position) + Vector3(0.0, 0.0, 0.3)
		b3.rotation.z -= 0.25 * (1.0 if (src as Node2D).get("vel").x >= 0.0 else -1.0) * 0.5
		b3.rotation.x += 0.1

## Efekty Żyły w scenie 3D (stan z `boss.gd`):
##  - żar paszczy (słaby punkt): poświata i światło przed pyskiem — tli się, gdy zamknięta; płonie, gdy otwarta; zielona przy pluciu; biała, gdy oślepiona;
##  - zapowiedź ciosu macką: czerwony łuk zasięgu;
##  - zapowiedź zamachu: drżące pasmo na wodzie na całym zasięgu fali, najsilniejsze przy Żyle;
##  - fala: dwa grzbiety wody biegnące od Żyły — bryły o stromym czole i łagodnym ogonie, z pianą na grzbiecie.
func _sync_boss_fx() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if not (n is Node2D) or n.is_queued_for_deletion() or _bossfx.has(n.get_instance_id()) or not n.has_method("_tick_wave_spray"):
			continue
		var root := Node3D.new()
		root.name = "BossFx"
		_world.add_child(root)
		var glow := _glow_quad(Color(1, 1, 1, 0))
		glow.name = "Maw"
		glow.layers = LAYER_WORLD
		root.add_child(glow)
		var ml := OmniLight3D.new()
		ml.name = "MawLight"
		ml.omni_range = 5.0
		ml.light_volumetric_fog_energy = 0.8
		ml.layers = LAYER_WORLD | LAYER_ACTORS
		root.add_child(ml)
		_imm(root, _add_mat()).name = "Arc"
		var bm := _add_mat()
		bm.no_depth_test = true                                 # zapowiedź ma być czytelna na każdym podłożu (śnieg, lód, woda mają różną wysokość)
		_imm(root, bm).name = "Band"
		var wm := StandardMaterial3D.new()                     # woda fali: półprzezroczysta, gładka, z lekką własną jasnością (czytelna w mroku)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.vertex_color_use_as_albedo = true
		wm.roughness = 0.12
		wm.emission_enabled = true
		wm.emission = Color(0.10, 0.20, 0.26)
		_imm(root, wm).name = "Wave"
		_bossfx[n.get_instance_id()] = [n, root]
	var t := Time.get_ticks_msec() / 1000.0
	for id in _bossfx.keys():
		var b = _bossfx[id][0]
		var root: Node3D = _bossfx[id][1]
		if not is_instance_valid(b) or (b as Node).is_queued_for_deletion():
			if is_instance_valid(root):
				root.queue_free()
			_bossfx.erase(id)
			continue
		var alive: bool = b.call("is_alive") and (b as Node2D).is_visible_in_tree()
		root.visible = alive
		if not alive:
			continue
		var base := Level3D.px_to_m((b as Node2D).global_position)
		root.position = base
		var awake: bool = b.call("is_threat")
		var pulse := 0.5 + 0.5 * sin(t * (6.0 if b.enraged else (3.0 if awake else 1.5)))
		# żar paszczy
		var maw := Color(1.0, 0.35, 0.2, 0.18)
		var r := 3.0
		if b.spitting:
			maw = Color(0.55, 1.0, 0.3, 0.6 + 0.4 * pulse)
			r = 6.5
		elif b.stunned:
			maw = Color(1.0, 1.0, 0.9, 0.5 + 0.5 * absf(sin(t * 18.0)))
			r = 9.0
		elif b.maw_open:
			maw = Color(1.0, 0.6, 0.25, 0.75 + 0.25 * pulse)
			r = 8.5
		var mp: Vector2 = b.call("_maw_point")
		var mpos := Vector3(mp.x * PX, -mp.y * PX, MAW_Z)
		var glow := root.get_node("Maw") as MeshInstance3D
		glow.position = mpos
		glow.scale = Vector3.ONE * (r * 3.6 * PX)
		(glow.material_override as StandardMaterial3D).albedo_color = maw
		var ml := root.get_node("MawLight") as OmniLight3D
		ml.position = mpos + Vector3(0.0, 0.0, 0.35)
		ml.light_color = Color(maw.r, maw.g, maw.b)
		ml.light_energy = 4.0 * maw.a * r / 9.0
		# łuk zasięgu macki
		var arc := (root.get_node("Arc") as MeshInstance3D).mesh as ImmediateMesh
		arc.clear_surfaces()
		if b.winding:
			var rad: float = float(b.LASH_RANGE_X) * PX
			var ac := Color(1.0, 0.15, 0.1, 0.4 + 0.5 * pulse)
			arc.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in 33:
				var a := PI * (0.05 + 0.9 * float(i) / 32.0)
				var d := Vector3(cos(a), sin(a), 0.0)
				arc.surface_set_color(ac)
				arc.surface_add_vertex(Vector3(0.0, 10.0 * PX, 0.3) + d * (rad - 0.05))
				arc.surface_set_color(ac)
				arc.surface_add_vertex(Vector3(0.0, 10.0 * PX, 0.3) + d * (rad + 0.05))
			arc.surface_end()
		# zapowiedź zamachu: drżące pasmo na wodzie
		var band := (root.get_node("Band") as MeshInstance3D).mesh as ImmediateMesh
		band.clear_surfaces()
		var range_m: float = float(b.SWEEP_RANGE) * PX
		if int(b.atk) == 3:                                    # Atk.SWEEP
			for row in 2:
				var z0 := -WAVE_Z + WAVE_Z * float(row)
				band.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				for i in 65:
					var x := -range_m + 2.0 * range_m * float(i) / 64.0
					var near := 1.0 - absf(x) / range_m
					for k in 2:
						var z := z0 + WAVE_Z * float(k)
						var edge := 1.0 - absf(z) / WAVE_Z         # jaśniej pośrodku pasma, gaśnie ku brzegom
						var rip := 0.5 + 0.5 * sin(t * 14.0 + x * 1.35 + z * 3.0)      # biegnące zmarszczki: jasne grzbiety, ciemne doliny
						var y := 0.30 + (0.7 + 1.9 * near) * rip * PX            # nad pokrywą śniegu i lodu (do ok. 0,25 m nad kaflem)
						band.surface_set_color(Color(0.60, 0.90, 1.0, (0.35 + 0.55 * pulse) * (0.25 + 0.75 * near) * edge * (0.12 + 0.88 * rip * rip * rip)))
						band.surface_add_vertex(Vector3(x, y, z))
				band.surface_end()
		# fala: dwa grzbiety
		var wave := (root.get_node("Wave") as MeshInstance3D).mesh as ImmediateMesh
		wave.clear_surfaces()
		var ws: int = int(b._wave_start_ms)
		if ws >= 0:
			var wr := 24.0 + float(Time.get_ticks_msec() - ws) / 1000.0 * float(b.SWEEP_SPEED)
			if wr <= float(b.SWEEP_RANGE):
				var body_c := Color(0.42, 0.72, 0.88, 0.72)
				var foam_c := Color(0.95, 1.0, 1.0, 0.95)
				for sd in [-1.0, 1.0]:
					var prof: Array = []                          # [x, wysokość] w metrach; u < 0 przed czołem, u > 0 za nim
					for i in 27:
						var u := -9.0 + 51.0 * float(i) / 26.0
						var hgt := 11.0 * exp(-pow(u / (4.5 if u < 0.0 else 15.0), 2.0))
						prof.append(Vector2(sd * (wr - u) * PX, hgt * PX))
					for pass_i in 3:                              # 0: grzbiet (góra), 1: ściana od kamery, 2: ściana od tyłu
						wave.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
						for i in prof.size():
							var pt: Vector2 = prof[i]
							var col := body_c.lerp(foam_c, clampf(pt.y / (11.0 * PX), 0.0, 1.0) * (1.0 if i < 13 else 0.35))
							if pass_i == 0:
								wave.surface_set_normal(Vector3(0, 1, 0))
								wave.surface_set_color(col)
								wave.surface_add_vertex(Vector3(pt.x, pt.y, -WAVE_Z))
								wave.surface_set_normal(Vector3(0, 1, 0))
								wave.surface_set_color(col)
								wave.surface_add_vertex(Vector3(pt.x, pt.y, WAVE_Z))
							else:
								var zz := WAVE_Z if pass_i == 1 else -WAVE_Z
								wave.surface_set_normal(Vector3(0, 0, signf(zz)))
								wave.surface_set_color(body_c)
								wave.surface_add_vertex(Vector3(pt.x, 0.0, zz))
								wave.surface_set_normal(Vector3(0, 0, signf(zz)))
								wave.surface_set_color(col)
								wave.surface_add_vertex(Vector3(pt.x, pt.y, zz))
						wave.surface_end()

# ---------------------------------------------------------------- Pijawka: kręgi, cień, woda przypływu; lampy

const POOL_Y := 0.12                     ## wysokość kręgów i cienia nad dnem basenu: tuż nad taflą [m]
const TIDE_Z0 := -1.6                    ## woda przypływu: od ściany w głębi…
const TIDE_Z1 := 0.95                    ## …do krawędzi przed graczami [m]

## Okrąg leżący na wodzie (pierścień w płaszczyźnie XZ, spłaszczony w głąb) dopisany do siatki `im`.
func _water_ring(im: ImmediateMesh, c: Vector3, r: float, w: float, col: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 33:
		var a := TAU * float(i) / 32.0
		var d := Vector3(cos(a), 0.0, sin(a) * 0.55)
		im.surface_set_color(col)
		im.surface_add_vertex(c + d * (r - w))
		im.surface_set_color(col)
		im.surface_add_vertex(c + d * (r + w))
	im.surface_end()

## Efekty Pijawki w scenie 3D (stan z `leech.gd: fx_state`):
##  - kręgi na wodzie nad zanurzoną Pijawką — jedyna wskazówka w ciemności; szybsze i mocniejsze tuż przed zasadzką (także w drugim punkcie, faza 3);
##  - cień pod wodą: ciemna podłużna plama z dwojgiem bladych oczu, widoczna tylko tam, gdzie pada światło;
##  - woda przypływu (fazy 2–3): bryła wody nad basenem i brzegami, rosnąca do `SURGE_H`, z falującą powierzchnią i jasną krawędzią piany.
##    Leży na warstwie graczy, więc zakrywa postaci stojące w wodzie.
func _sync_leech_fx() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if not (n is Node2D) or n.is_queued_for_deletion() or _leechfx.has(n.get_instance_id()) or not n.has_method("fx_state"):
			continue
		var root := Node3D.new()
		root.name = "LeechFx"
		_world.add_child(root)
		_imm(root, _add_mat()).name = "Rings"
		var sm := StandardMaterial3D.new()                     # cień: czarna miękka plama — na ciemnej wodzie niewidoczna, w świetle wyraźna
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.albedo_texture = _soft()
		sm.albedo_color = Color(0.01, 0.03, 0.03, 0.0)
		for part in [["Shadow", Vector2(54.0, 15.0), -6.0], ["Head", Vector2(22.0, 12.0), 15.0]]:
			var sh := MeshInstance3D.new()
			sh.name = part[0]
			var pl := PlaneMesh.new()
			pl.size = (part[1] as Vector2) * PX
			sh.mesh = pl
			sh.material_override = sm
			sh.position = Vector3(float(part[2]) * PX, POOL_Y - 0.03, 0.2)
			sh.layers = LAYER_WORLD
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(sh)
		var em := StandardMaterial3D.new()                     # oczy: blade, bez własnego światła — błyszczą dopiero w latarce albo flarze
		em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		em.albedo_color = Color(0.8, 0.95, 0.9, 0.0)
		em.roughness = 0.15
		for ex in [16.0, 20.0]:
			var eye := MeshInstance3D.new()
			eye.name = "Eye%d" % int(ex)
			var sp := SphereMesh.new()
			sp.radius = 1.1 * PX
			sp.height = 2.2 * PX
			sp.radial_segments = 10
			sp.rings = 5
			eye.mesh = sp
			eye.material_override = em
			eye.position = Vector3(ex * PX, POOL_Y, 0.2 + (0.12 if ex < 18.0 else -0.12))
			eye.layers = LAYER_WORLD
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(eye)
		var tm := StandardMaterial3D.new()                     # woda przypływu: widoczna także w mroku (jak w 2D), kolor z wierzchołków
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		tm.vertex_color_use_as_albedo = true
		var tide := MeshInstance3D.new()
		tide.name = "Tide"
		tide.mesh = ImmediateMesh.new()
		tide.material_override = tm
		tide.layers = LAYER_WORLD
		tide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(tide)                                 # w świecie, nie przy Pijawce: woda stoi w miejscu
		var veil := tide.duplicate() as MeshInstance3D         # cienka zasłona wody przed graczami (warstwa postaci): stojący w wodzie są nią przykryci
		veil.name = "TideVeil"
		veil.mesh = ImmediateMesh.new()
		veil.layers = LAYER_ACTORS
		_world.add_child(veil)
		_leechfx[n.get_instance_id()] = [n, root, tide, veil]
	var t := Time.get_ticks_msec() / 1000.0
	for id in _leechfx.keys():
		var b = _leechfx[id][0]
		var root: Node3D = _leechfx[id][1]
		var tide_mi = _leechfx[id][2]
		if not is_instance_valid(b) or (b as Node).is_queued_for_deletion():
			if is_instance_valid(root):
				root.queue_free()
			for k in [2, 3]:
				if is_instance_valid(_leechfx[id][k]):
					(_leechfx[id][k] as Node).queue_free()
			_leechfx.erase(id)
			continue
		var fs: Array = b.call("fx_state")
		var base := Level3D.px_to_m((b as Node2D).global_position)
		root.position = base
		root.visible = (b as Node2D).is_visible_in_tree()
		var rings := (root.get_node("Rings") as MeshInstance3D).mesh as ImmediateMesh
		rings.clear_surfaces()
		var strength := float(fs[0])
		var centers: Array = [Vector3(0.0, POOL_Y, 0.2)]
		if bool(fs[3]):
			if float(b.second_x) >= 0.0:
				centers.append(Vector3((float(b.second_x) - (b as Node2D).global_position.x) * PX, POOL_Y, 0.2))
			var pr := (5.0 + 3.0 * sin(t * 18.0)) * PX          # zapowiedź: pulsujący krąg w miejscu wynurzenia
			_water_ring(rings, centers[0], pr * 0.5, pr * 0.5, Color(0.5, 0.65, 0.62, 0.25))
		for cpos in centers:
			for i in 3:
				var ph := fposmod(float(b._ripple_t) * float(fs[1]) * 0.9 + float(i) * 0.33, 1.0)
				_water_ring(rings, cpos, (6.0 + ph * 26.0) * PX, 0.035, Color(0.55, 0.75, 0.72, (1.0 - ph) * 0.55 * strength))
				_water_ring(rings, cpos, (6.0 + ph * 26.0) * PX * 0.8, 0.025, Color(0.4, 0.6, 0.58, (1.0 - ph) * 0.3 * strength))
		var sa := float(fs[2])
		for nm in ["Shadow", "Head"]:
			(root.get_node(nm) as MeshInstance3D).visible = sa > 0.0
		((root.get_node("Shadow") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.9 * sa
		for nm in ["Eye16", "Eye20"]:
			(root.get_node(nm) as MeshInstance3D).visible = sa > 0.0
		((root.get_node("Eye16") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = sa
		# woda przypływu
		var tide := (tide_mi as MeshInstance3D).mesh as ImmediateMesh
		tide.clear_surfaces()
		var veil := (_leechfx[id][3] as MeshInstance3D).mesh as ImmediateMesh
		veil.clear_surfaces()
		var lvl: float = b.call("surge_level")
		if String(b.surge_state) != "idle" and lvl > 0.01:
			var h: float = lvl * float(b.SURGE_H)
			var x0: float = float(b.pool_x0) - float(b.SURGE_PAD)
			var x1: float = float(b.pool_x1) + float(b.SURGE_PAD)
			var y0 := -float(b.surf_y) * PX
			var warn: bool = String(b.surge_state) == "warn"
			var top_c := Color(0.20, 0.50, 0.58, 0.12 if warn else 0.30)
			var bot_c := Color(0.07, 0.28, 0.36, 0.07 if warn else 0.20)
			var foam_c := Color(0.75, 0.96, 1.0, 0.25 if warn else 0.6)
			var prof: Array = []
			var x := x0
			while x <= x1 + 0.1:
				var edge := clampf(minf(x - x0, x1 - x) / 40.0, 0.0, 1.0)
				var wv := sin(x * 0.07 + t * 3.2) * 1.6 + sin(x * 0.13 - t * 2.1) * 1.0
				prof.append(Vector2(x * PX, y0 + maxf(h * edge - wv, 0.5) * PX))
				x += 16.0
			for pass_i in 3:                                     # 0: tafla, 1: ściana od kamery (jaśniej u góry), 2: pas piany na krawędzi
				tide.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				for pt in prof:
					var q: Vector2 = pt
					if pass_i == 0:
						tide.surface_set_color(Color(top_c.r, top_c.g, top_c.b, top_c.a * 0.55))
						tide.surface_add_vertex(Vector3(q.x, q.y, TIDE_Z0))
						tide.surface_set_color(top_c)
						tide.surface_add_vertex(Vector3(q.x, q.y, TIDE_Z1))
					elif pass_i == 1:
						tide.surface_set_color(bot_c)
						tide.surface_add_vertex(Vector3(q.x, y0, TIDE_Z1))
						tide.surface_set_color(top_c)
						tide.surface_add_vertex(Vector3(q.x, q.y, TIDE_Z1))
					else:
						tide.surface_set_color(foam_c)
						tide.surface_add_vertex(Vector3(q.x, q.y - 0.035, TIDE_Z1 + 0.01))
						tide.surface_set_color(foam_c)
						tide.surface_add_vertex(Vector3(q.x, q.y + 0.02, TIDE_Z1 + 0.01))
				tide.surface_end()
			veil.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for pt in prof:
				var q2: Vector2 = pt
				veil.surface_set_color(Color(bot_c.r, bot_c.g, bot_c.b, 0.06))
				veil.surface_add_vertex(Vector3(q2.x, y0, TIDE_Z1))
				veil.surface_set_color(Color(top_c.r, top_c.g, top_c.b, 0.09))
				veil.surface_add_vertex(Vector3(q2.x, q2.y, TIDE_Z1))
			veil.surface_end()

## Lampy na mapach (`lamp.gd`): model stawia `_sync_items`, światło — `_scan_lights` (smugę w powietrzu daje mgła wolumetryczna).
## Tu dochodzi poświata żarówki w scenie.
func _sync_lamps() -> void:
	for n in get_tree().get_nodes_in_group("lamps"):
		if not (n is Node2D) or n.is_queued_for_deletion() or _lampfx.has(n.get_instance_id()):
			continue
		var g := _glow_quad(Color(1.0, 0.8, 0.5, 0.0))
		g.name = "LampGlow"
		g.layers = LAYER_WORLD
		_world.add_child(g)
		_lampfx[n.get_instance_id()] = [n, g]
	for id in _lampfx.keys():
		var src = _lampfx[id][0]
		var g: MeshInstance3D = _lampfx[id][1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(g):
				g.queue_free()
			_lampfx.erase(id)
			continue
		var z := 0.0
		for ch in (src as Node).get_children():                # głębia modelu lampy (ta sama, w której stawia go _sync_items)
			if ch is ItemsHd.ItemMark and _items.has(ch.get_instance_id()):
				z = float(_items[ch.get_instance_id()][3])
		var tt := float(src.get("_t"))
		var f := 0.8 + 0.2 * sin(tt * 9.0) * sin(tt * 3.7)
		g.visible = (src as Node2D).is_visible_in_tree()
		g.position = Level3D.px_to_m((src as Node2D).global_position + Vector2(0.0, 11.0)) + Vector3(0.0, 0.0, z + 0.12)
		g.scale = Vector3.ONE * (0.75 + 0.1 * f)
		(g.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.82, 0.55, 0.55 * f)

# ---------------------------------------------------------------- lampki, diody, oczy w mroku, tablica wyników

const FP_EYE_M := 1.5                    ## oględziny: wysokość oczu gracza nad stopami [m]
const FP_Z := 0.75                       ## …i głębia kamery (tuż przed płaszczyzną gry, twarzą do ściany)
const FP_FOV := 62.0                     ## kąt widzenia z oczu gracza [°]
const DREAD_Z := -1.3                    ## oczy w mroku: w głębi sceny, za płaszczyzną gry

## Chowa rysunek 2D węzła (tylko jego własny `_draw`, dzieci zostają) i zapamiętuje go do przywrócenia.
func _hide2d(n) -> void:
	if n != null and is_instance_valid(n) and (n as CanvasItem).self_modulate.a > 0.0:
		(n as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		_hid2d.append(n)

## Przód (największe Z) modelu 3D postawionego przez `_sync_items` dla sprite'a `hd_name` będącego dzieckiem `owner`; NAN, gdy modelu jeszcze nie ma.
func _model_front(owner: Node, hd_name: String) -> float:
	for ch in owner.get_children():
		if not (ch is ItemsHd.ItemMark) or String(ch.get_meta("hd_name", "")) != hd_name or not _items.has(ch.get_instance_id()):
			continue
		var root := _items[ch.get_instance_id()][1] as Node3D
		var zmax := -INF
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			zmax = maxf(zmax, ab.end.z)
		if zmax > -INF:
			return zmax
	return NAN

## Świecący punkt (miękki krążek zwrócony do kamery) dopisany do siatki punktów.
func _dot(im: ImmediateMesh, c: Vector3, r: float, col: Color) -> void:
	for k in [0, 1, 2, 2, 1, 3]:
		var u := float(k % 2)
		var v := float(k / 2)
		im.surface_set_uv(Vector2(u, v))
		im.surface_set_color(col)
		im.surface_add_vertex(c + Vector3((u * 2.0 - 1.0) * r, (v * 2.0 - 1.0) * r, 0.0))

## Drobne elementy świata rysowane dotąd na płaskiej nakładce — teraz w scenie 3D (stan czytany z ich skryptów, rysunek 2D chowany):
##  - lampka generatora (czerwona / bursztynowa przy rozruchu / zielona, gdy pracuje) i spaliny z tłumika,
##  - latarnia drezyny, diody min i ładunków, oczy w mroku (`dread.gd`) — świecące punkty,
##  - tablica wyników: kreda rysowana przez `results_wall.gd` do tekstury i położona na powierzchni tablicy (bierze światło lamp).
func _sync_world_fx(delta: float) -> void:
	if _dots_mi == null:
		var dm := _add_mat()
		dm.albedo_texture = _soft()
		_dots_mi = _imm(_world, dm)
		_dots_mi.name = "Dots"
	var im := _dots_mi.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_dot(im, Vector3(0.0, -1000.0, 0.0), 0.001, Color(0, 0, 0, 0))      # siatka nie może być pusta
	# --- generatory
	for g in get_tree().get_nodes_in_group("generators"):
		if not (g is Node2D) or g.get("_hd") == null:
			continue
		var id: int = g.get_instance_id()
		if not _worldfx.has(id):
			var sm := CPUParticles3D.new()                     # spaliny z tłumika pracującego generatora
			sm.name = "GenSmoke"
			sm.emitting = false
			sm.amount = 12
			sm.lifetime = 1.5
			sm.local_coords = false
			var q := QuadMesh.new()
			q.size = Vector2(0.5, 0.5)
			var qm := StandardMaterial3D.new()
			qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			qm.billboard_keep_scale = true
			qm.vertex_color_use_as_albedo = true
			qm.albedo_texture = _soft()
			qm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			q.material = qm
			sm.mesh = q
			sm.direction = Vector3(0.15, 1.0, 0.0)
			sm.spread = 12.0
			sm.initial_velocity_min = 0.8
			sm.initial_velocity_max = 1.4
			sm.gravity = Vector3(0.1, 0.3, 0.0)
			var sc := Curve.new()
			sc.add_point(Vector2(0.0, 0.35))
			sc.add_point(Vector2(1.0, 1.6))
			sm.scale_amount_curve = sc
			var gr := Gradient.new()
			gr.set_color(0, Color(0.55, 0.58, 0.58, 0.0))
			gr.add_point(0.15, Color(0.55, 0.58, 0.58, 0.32))
			gr.set_color(gr.get_point_count() - 1, Color(0.5, 0.52, 0.52, 0.0))
			sm.color_ramp = gr
			sm.layers = LAYER_WORLD
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_world.add_child(sm)
			_worldfx[id] = {"src": g, "nodes": [sm], "z": NAN}
		var gf: Dictionary = _worldfx[id]
		if is_nan(float(gf["z"])):
			gf["z"] = _model_front(g, "generator")
		var gz := 0.4 if is_nan(float(gf["z"])) else float(gf["z"]) + 0.03
		var gt := float(g.get("_t"))
		var prog := float(g.get("progress"))
		var run: bool = g.get("running") == true
		var blink := 0.5 + 0.5 * sin(gt * (14.0 if prog > 0.0 and not run else 3.0))
		var gcol := Color(0.35, 1.0, 0.45) if run else (Color(1.0, 0.7, 0.2, 0.5 + 0.5 * blink) if prog > 0.0 else Color(0.95, 0.22, 0.18, 0.55 + 0.45 * blink))
		var hs := float(g.HD_SCALE)
		var gpos := Level3D.px_to_m((g as Node2D).global_position + Vector2(-4.0, -11.4) * hs)
		if (g as Node2D).is_visible_in_tree():
			_dot(im, gpos + Vector3(0.0, 0.0, gz), 3.2 * PX, Color(gcol.r, gcol.g, gcol.b, gcol.a * 0.35))
			_dot(im, gpos + Vector3(0.0, 0.0, gz + 0.01), 1.1 * PX, gcol)
		var gsm := gf["nodes"][0] as CPUParticles3D
		gsm.emitting = run and (g as Node2D).is_visible_in_tree()
		gsm.position = Level3D.px_to_m((g as Node2D).global_position + Vector2(10.0, -26.5) * hs) + Vector3(0.0, 0.0, gz - 0.25)
	# --- drezyna: latarnia
	for hc in get_tree().get_nodes_in_group("handcar"):
		if not (hc is Node2D) or hc.get("_hd") != true:
			continue
		if not (hc as Node2D).is_visible_in_tree():
			continue
		var on: bool = hc.get("enabled") == true
		var hcol := Color(1.0, 0.85, 0.5) if on else Color(0.5, 0.15, 0.12)
		var hpos := Level3D.px_to_m((hc as Node2D).global_position + Vector2(-float(hc.HALF_W) + 3.0, -17.7)) + Vector3(0.0, -Level3D.TRENCH_D, 0.45)
		_dot(im, hpos, (5.5 if on else 2.4) * PX, Color(hcol.r, hcol.g, hcol.b, 0.4 if on else 0.25))
		_dot(im, hpos + Vector3(0.0, 0.0, 0.01), 1.3 * PX, hcol)
	# --- miny i ładunki: dioda
	for pl in get_tree().get_nodes_in_group("placed"):
		if pl.get("_hd") == null or not (pl is Node2D):
			continue
		if not (pl as Node2D).is_visible_in_tree():
			continue
		var data: Dictionary = pl.get("_data")
		var pc: Color = data["color"]
		var pt := float(pl.get("_t"))
		var lit: bool
		var lp: Vector2
		if String(pl.get("kind")) == "mine":
			lit = pl.call("is_armed") or fmod(pt * 6.0, 1.0) < 0.5
			lp = Vector2(-5.4 * (-1.0 if (pl.get("dir") as Vector2).x < 0.0 else 1.0) * 0.8, -5.1 * 0.8)
		else:
			lit = fmod(pt * (2.0 + 10.0 * (pt / float(data["fuse"]))), 1.0) < 0.5
			lp = Vector2(0.6, -4.5)
		if lit:
			var ppos := Level3D.px_to_m((pl as Node2D).global_position + lp) + Vector3(0.0, 0.0, 0.55)
			_dot(im, ppos, 1.9 * PX, Color(pc.r, pc.g, pc.b, 0.45))
			_dot(im, ppos + Vector3(0.0, 0.0, 0.01), 0.7 * PX, Color(1.0, 0.85, 0.7, 0.95))
	# --- oczy w mroku
	var dread := get_tree().root.find_child("Dread", true, false)
	var eyes = dread.get("_eyes") if dread != null else null
	if eyes != null and is_instance_valid(eyes):
		if (eyes as Node2D).visible and float(dread.get("_eyes_life")) > 0.0:
			var el := float(dread.get("_eyes_life"))
			var ea := minf(float(dread.get("_eyes_age")) / 0.6, 1.0) * 0.55
			if el < 0.5 and int(el * 14.0) % 2 == 0:
				ea = 0.0
			var epos := Level3D.px_to_m((eyes as Node2D).global_position) + Vector3(0.0, 0.0, DREAD_Z)
			for ex in [-3.0, 3.0]:
				_dot(im, epos + Vector3(ex * PX, 0.0, 0.0), 2.6 * PX, Color(1.0, 0.92, 0.6, ea * 0.5))
				_dot(im, epos + Vector3(ex * PX, 0.0, 0.01), 1.2 * PX, Color(1.0, 0.92, 0.6, ea))
	im.surface_end()
	# --- tablica wyników: kreda z `results_wall.gd` w teksturze na powierzchni tablicy
	_surf_t -= delta
	var refresh := _surf_t <= 0.0
	if refresh:
		_surf_t = 0.4
	for rw in get_tree().get_nodes_in_group("results_wall"):
		var ov = rw.get("_ov")
		if not (rw is Node2D) or ov == null or _geo_key == "":
			continue
		_hide2d(ov)
		var id: int = rw.get_instance_id()
		if _worldfx.has(id) and not is_instance_valid(_worldfx[id]["nodes"][1]):
			for wn in _worldfx[id]["nodes"]:
				if is_instance_valid(wn):
					(wn as Node).queue_free()
			_worldfx.erase(id)
		if not _worldfx.has(id):
			var rect := Rect2(-56.0, -64.0, 112.0, 58.0)       # pole tablicy w px świata (jak w `_draw_content`)
			var k := 8.0
			var vp := SubViewport.new()
			vp.name = "ResultsChalk"
			vp.size = Vector2i(int(rect.size.x * k), int(rect.size.y * k))
			vp.transparent_bg = true
			vp.disable_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			if "oversampling_override" in vp:
				vp.set("oversampling_override", k)             # ostre litery przy powiększeniu
			var ci := Node2D.new()
			ci.name = "Chalk"
			ci.position = -rect.position * k
			ci.scale = Vector2(k, k)
			ci.draw.connect(func() -> void:
				if is_instance_valid(rw):
					rw.call("_draw_content", ci))
			vp.add_child(ci)
			add_child(vp)
			var board := MeshInstance3D.new()
			board.name = "ResultsText"
			var bq := QuadMesh.new()
			bq.size = rect.size * PX
			board.mesh = bq
			var bmat := StandardMaterial3D.new()
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bmat.albedo_texture = vp.get_texture()
			bmat.roughness = 1.0
			bmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			bmat.emission_enabled = true                       # kreda lekko czytelna także poza światłem lampy
			bmat.emission_texture = vp.get_texture()
			bmat.emission_energy_multiplier = 0.05
			board.material_override = bmat
			board.layers = LAYER_WORLD
			board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_geo.add_child(board)
			_worldfx[id] = {"src": rw, "nodes": [vp, board], "z": NAN, "rect": rect}
		var wf: Dictionary = _worldfx[id]
		if is_nan(float(wf["z"])):
			wf["z"] = _model_front(rw, "results_board")
		var bd := wf["nodes"][1] as MeshInstance3D
		bd.visible = not is_nan(float(wf["z"]))
		if bd.visible:
			var rc: Rect2 = wf["rect"]
			bd.position = Level3D.px_to_m((rw as Node2D).global_position + rc.get_center())
			bd.position.z = float(wf["z"]) + 0.012
		if refresh:
			var vp2 := wf["nodes"][0] as SubViewport
			(vp2.get_child(0) as Node2D).queue_redraw()
			vp2.render_target_update_mode = SubViewport.UPDATE_ONCE

# ---------------------------------------------------------------- gniazda, pierścień alarmu, pył w powietrzu

## Żar unoszący się nad gniazdem (widać je z daleka w mroku): iskry 3D zamiast cząsteczek 2D z `nest.gd` (te są chowane).
func _sync_nests() -> void:
	for n in get_tree().get_nodes_in_group("nests"):
		if not (n is Node2D) or n.is_queued_for_deletion() or _nestfx.has(n.get_instance_id()):
			continue
		var p := CPUParticles3D.new()
		p.name = "NestEmbers"
		p.amount = 20
		p.lifetime = 1.8
		p.local_coords = false
		var q := QuadMesh.new()
		q.size = Vector2(0.11, 0.11)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft()
		q.material = m
		p.mesh = q
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(12.0 * PX, 3.0 * PX, 0.35)
		p.direction = Vector3.UP
		p.spread = 25.0
		p.initial_velocity_min = 6.0 * PX
		p.initial_velocity_max = 16.0 * PX
		p.gravity = Vector3(0.0, 4.0 * PX, 0.0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.5
		var gr := Gradient.new()
		gr.set_color(0, Color(1.0, 0.6, 0.22, 0.0))
		gr.add_point(0.15, Color(1.0, 0.55, 0.2, 0.9))
		gr.set_color(gr.get_point_count() - 1, Color(0.9, 0.25, 0.08, 0.0))
		p.color_ramp = gr
		p.layers = LAYER_WORLD
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(p)
		_nestfx[n.get_instance_id()] = [n, p]
	for id in _nestfx.keys():
		var src = _nestfx[id][0]
		var p: CPUParticles3D = _nestfx[id][1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(p):
				p.queue_free()
			_nestfx.erase(id)
			continue
		p.emitting = (src as Node2D).is_visible_in_tree() and (src.get("alive") == null or src.get("alive") == true)
		p.position = Level3D.px_to_m((src as Node2D).global_position + Vector2(0.0, -16.0)) + Vector3(0.0, 0.0, 0.3)

## Pierścień alarmu wroga (`enemy.gd: _ring` — rozchodzi się od stwora, gdy podnosi alarm): okrąg w płaszczyźnie gry wokół jego tułowia.
func _sync_enemy_rings() -> void:
	if _ring_mi == null:
		_ring_mi = _imm(_world, _add_mat())
		_ring_mi.name = "EnemyRings"
	var im := _ring_mi.mesh as ImmediateMesh
	im.clear_surfaces()
	for n in get_tree().get_nodes_in_group("enemies"):
		var rv = n.get("_ring")
		if rv == null or not (n is Node2D):
			continue
		if float(rv) <= 0.0 or not (n as Node2D).is_visible_in_tree():
			continue
		var k := 1.0 - float(rv) / 0.7
		var size: Vector2 = n.get("_def")["size"]
		var c := Level3D.px_to_m((n as Node2D).global_position + Vector2(0.0, -size.y * 0.7)) + Vector3(0.0, 0.0, 0.35)
		var r := (8.0 + k * float((n.get("_def") as Dictionary).get("ring_r", 70.0))) * PX
		var col := Color(1.0, 0.55, 0.35, (1.0 - k) * 0.8)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in 49:
			var a := TAU * float(i) / 48.0
			var d := Vector3(cos(a), sin(a), 0.0)
			im.surface_set_color(col)
			im.surface_add_vertex(c + d * (r - 0.05))
			im.surface_set_color(col)
			im.surface_add_vertex(c + d * (r + 0.05))
		im.surface_end()
	# pole ochronne Podsłuchacza w trakcie krzyku (`view_info()["shield"]`): półprzezroczysta tarcza wokół tułowia z jaśniejszym brzegiem, lekko pulsuje
	for n in get_tree().get_nodes_in_group("enemies"):
		if not (n is Node2D) or not n.has_method("view_info") or not (n as Node2D).is_visible_in_tree():
			continue
		var info: Dictionary = n.view_info()
		var dfn = n.get("_def")
		if dfn == null:
			continue                                               # Stalker, Żyła, Pijawka i gniazda mają view_info, ale nie dane rodzaju zwykłego wroga
		var size: Vector2 = (dfn as Dictionary)["size"]
		if bool(info.get("shield", false)):
			var c := Level3D.px_to_m((n as Node2D).global_position + Vector2(0.0, -size.y * 0.55)) + Vector3(0.0, 0.0, 0.3)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			var r := (size.y * 0.9 + pulse * 2.0) * PX
			var fill := Color(0.55, 0.8, 1.0, 0.10 + 0.07 * pulse)
			var edge := Color(0.7, 0.9, 1.0, 0.55 + 0.3 * pulse)
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in 49:
				var a := TAU * float(i) / 48.0
				var d := Vector3(cos(a), sin(a), 0.0)
				im.surface_set_color(fill)
				im.surface_add_vertex(c)
				im.surface_set_color(fill)
				im.surface_add_vertex(c + d * r)
			im.surface_end()
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in 49:
				var a := TAU * float(i) / 48.0
				var d := Vector3(cos(a), sin(a), 0.0)
				im.surface_set_color(edge)
				im.surface_add_vertex(c + d * (r - 0.04))
				im.surface_set_color(edge)
				im.surface_add_vertex(c + d * (r + 0.04))
			im.surface_end()
		# zapowiedź fali krzyku Kapłana (`view_info()["tele"]` = promień w px): pulsujący pierścień na całym zasięgu fali — gracz widzi, skąd się cofnąć
		var tele := float(info.get("tele", 0.0))
		if tele > 0.0:
			var tc := Level3D.px_to_m((n as Node2D).global_position + Vector2(0.0, -size.y * 0.5)) + Vector3(0.0, 0.0, 0.35)
			var tp := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
			var tr := tele * PX
			var tfill := Color(1.0, 0.75, 0.3, 0.025 + 0.02 * tp)
			var tedge := Color(1.0, 0.8, 0.35, 0.55 + 0.35 * tp)
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in 49:
				var ta := TAU * float(i) / 48.0
				var td := Vector3(cos(ta), sin(ta), 0.0)
				im.surface_set_color(tfill)
				im.surface_add_vertex(tc)
				im.surface_set_color(tfill)
				im.surface_add_vertex(tc + td * tr)
			im.surface_end()
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in 49:
				var ta2 := TAU * float(i) / 48.0
				var td2 := Vector3(cos(ta2), sin(ta2), 0.0)
				im.surface_set_color(tedge)
				im.surface_add_vertex(tc + td2 * (tr - 0.05))
				im.surface_set_color(tedge)
				im.surface_add_vertex(tc + td2 * (tr + 0.05))
			im.surface_end()
		# wiązki leczenia Kapłana (`view_info()["beams"]` = punkty leczonych): zielone pasma od jego tułowia do każdego z Trzosków
		var beams: PackedVector2Array = info.get("beams", PackedVector2Array())
		if not beams.is_empty():
			var from3 := Level3D.px_to_m((n as Node2D).global_position + Vector2(0.0, -size.y * 0.7)) + Vector3(0.0, 0.0, 0.35)
			for bp in beams:
				var to3 := Level3D.px_to_m(bp) + Vector3(0.0, 0.0, 0.35)
				var dir3 := (to3 - from3)
				var nrm := Vector3(-dir3.y, dir3.x, 0.0).normalized() * 0.05
				var bc := Color(0.45, 1.0, 0.55, 0.6)
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				for t in [0.0, 1.0]:
					var pt: Vector3 = from3.lerp(to3, t)
					im.surface_set_color(bc)
					im.surface_add_vertex(pt - nrm)
					im.surface_set_color(bc)
					im.surface_add_vertex(pt + nrm)
				im.surface_end()

## Pył w powietrzu wokół kadru: drobiny 3D w całej głębi sceny, widoczne tylko w świetle — snop latarki „ma objętość".
## Mgłę przy ziemi daje mgła wolumetryczna.
func _sync_ambient() -> void:
	if _motes == null:
		_motes = CPUParticles3D.new()
		_motes.name = "DustMotes"
		_motes.amount = 160
		_motes.lifetime = 9.0
		_motes.preprocess = 9.0
		_motes.local_coords = false
		var q := QuadMesh.new()
		q.size = Vector2(0.04, 0.04)
		var sh := Shader.new()
		sh.code = DUST_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", _soft())
		mat.set_shader_parameter("glow", 0.0)
		q.material = mat
		_motes.mesh = q
		_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_motes.emission_box_extents = Vector3(230.0 * PX, 140.0 * PX, 1.5)
		_motes.direction = Vector3(1.0, 0.2, 0.0)
		_motes.spread = 180.0
		_motes.initial_velocity_min = 2.0 * PX
		_motes.initial_velocity_max = 7.0 * PX
		_motes.gravity = Vector3(0.6 * PX, -1.2 * PX, 0.0)
		_motes.scale_amount_min = 0.6
		_motes.scale_amount_max = 1.3
		var gr := Gradient.new()
		gr.set_color(0, Color(0.8, 0.78, 0.7, 0.0))
		gr.add_point(0.15, Color(0.8, 0.78, 0.7, 0.7))
		gr.add_point(0.85, Color(0.8, 0.78, 0.7, 0.7))
		gr.set_color(gr.get_point_count() - 1, Color(0.8, 0.78, 0.7, 0.0))
		_motes.color_ramp = gr
		_motes.layers = LAYER_WORLD
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(_motes)
	var cam := _cam_a.global_position
	_motes.emitting = Settings.quality_idx >= 1 and Settings.fx_mult() > 0.0
	_motes.position = Vector3(cam.x, cam.y - EYE_UP_M + 1.0, -0.3)

# ---------------------------------------------------------------- pył finału kopalni

const WS_LAMP_PX := 56.0                 ## wysokość lampy warsztatu nad podłogą [px świata]
const WS_LAMP_Z := -0.85                 ## głębia lampy warsztatu: nad ławą pod ścianą z narzędziami
## Pył jako drobiny w powietrzu: zawsze przodem do kamery, a światło bierze niezależnie od kierunku (jak zawiesina) — rozbłyska w snopie latarki
## i przy flarach, a poza światłem zostaje ledwie widoczny (`glow`).
const DUST_SHADER := "shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
uniform sampler2D tex : source_color;
uniform float glow = 0.012;
void vertex() {
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * texture(tex, UV).a;
	EMISSION = COLOR.rgb * glow;
}
void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * 0.9;
}
"
const DUST_COLS := 13                    ## pół szerokości pasa stropu wokół kamery, z którego sypie się pył [kafle]
const DUST_ROWS := 8                     ## pół wysokości tego pasa [kafle]

## Finał kopalni (`mission.finale`: trzeci nieśmiertelnik, zawał rampy, wyjście szybem): pył sypie się ze stropów wokół kamery.
## Źródłem jest spód litych kafli nad wolną przestrzenią (z mapy), więc pył leci tylko pod ziemią — na powierzchni, pod gołym niebem, go nie ma.
## Dwie warstwy: drobny pył z całego stropu i gęstsze strużki z kilku pęknięć (stałych dla miejsca). Cząsteczki są oświetlane — widać je w latarce i flarach.
func _sync_mine_dust() -> void:
	var m := get_tree().get_first_node_in_group("mission")
	var on: bool = m != null and m.get("finale") == true and Settings.quality_idx >= 1 and Settings.fx_mult() > 0.0 and not _rows.is_empty()
	if _mine_dust.is_empty():
		if not on:
			return
		var sh := Shader.new()
		sh.code = DUST_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", _soft())
		for i in 2:
			var p := CPUParticles3D.new()
			p.name = "MineDust" if i == 0 else "MineDustStreams"
			p.emitting = false
			p.local_coords = false
			p.amount = 520 if i == 0 else 150
			p.lifetime = 1.7 if i == 0 else 1.5                 # krótko: pył rozwiewa się w połowie wysokości chodnika, nie przelatuje przez podłogi
			var q := QuadMesh.new()
			q.size = Vector2(0.06, 0.06) if i == 0 else Vector2(0.42, 0.42)
			q.material = mat
			p.mesh = q
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
			p.direction = Vector3.DOWN
			p.spread = 12.0 if i == 0 else 4.0
			p.initial_velocity_min = 0.25 if i == 0 else 0.7
			p.initial_velocity_max = 0.9 if i == 0 else 1.5
			p.gravity = Vector3(0.0, -1.3 if i == 0 else -2.4, 0.0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.5
			var gr := Gradient.new()
			gr.set_color(0, Color(0.7, 0.68, 0.6, 0.0))
			gr.add_point(0.12, Color(0.7, 0.68, 0.6, 0.8 if i == 0 else 0.22))
			gr.set_color(gr.get_point_count() - 1, Color(0.6, 0.58, 0.52, 0.0))
			p.color_ramp = gr
			p.layers = LAYER_WORLD
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_world.add_child(p)
			_mine_dust.append(p)
	var cam := _cam_a.global_position
	var key := Vector2i(int(floor(cam.x / Level3D.T / 4.0)), int(floor(-cam.y / Level3D.T / 4.0)))
	if on and key != _mine_dust_key:
		_mine_dust_key = key
		var cc := int(floor(cam.x / Level3D.T))
		var cr := int(floor(-(cam.y - EYE_UP_M) / Level3D.T))
		var fine := PackedVector3Array()
		var streams := PackedVector3Array()
		for r in range(maxi(1, cr - DUST_ROWS), mini(_rows.size(), cr + DUST_ROWS)):
			for c in range(cc - DUST_COLS, cc + DUST_COLS):
				if c < 0 or c >= (_rows[r] as String).length():
					continue
				if Level3D.is_solid_ch(Level3D._ch(_rows, c, r)) or not Level3D.is_solid_ch(Level3D._ch(_rows, c, r - 1)):
					continue
				var h := hash(Vector2i(c, r))                   # stałe dla kafla: pęknięcia nie skaczą, gdy kamera się przesuwa
				var x := (float(c) + 0.5) * Level3D.T
				var y := -float(r) * Level3D.T - 0.02
				for j in 2:
					fine.append(Vector3(x + (float((h >> (j * 5)) & 31) / 31.0 - 0.5) * Level3D.T, y, -1.5 + 1.9 * float((h >> (10 + j * 6)) & 63) / 63.0))
				if h % 5 == 0:
					streams.append(Vector3(x, y, -1.2 + 1.4 * float((h >> 8) & 63) / 63.0))
		(_mine_dust[0] as CPUParticles3D).emission_points = fine
		(_mine_dust[1] as CPUParticles3D).emission_points = streams
	for i in _mine_dust.size():
		var dp := _mine_dust[i] as CPUParticles3D
		dp.emitting = on and dp.emission_points.size() > 0

# ---------------------------------------------------------------- pogoda

## Deszcz i plusk przycinane do dachów: każda kolumna mapy ma wysokość pierwszej litej bryły od góry (`roof`, tekstura 1×kolumny, metry).
## Kropla poniżej tej wysokości jest odrzucana — pod stropem, w budynku i w jaskini nie pada, a na otwartym terenie krople kończą się na gruncie.
## Za bryłą poziomu (las w głębi, `z_back`) dachów nie ma: tam krople lecą do `floor_y`. //BILLBOARD → wariant dla plusku (środek cząsteczki).
const RAIN_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D roof : filter_nearest, repeat_disable;
uniform float cols = 1.0;
uniform float tile = 1.0;
uniform float z_back = -2.7;
uniform float floor_y = -1000.0;
uniform float splash_band = 0.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	//BILLBOARD
}
void fragment() {
	float c = wp.x / tile;
	float lim = floor_y;
	if (wp.z > z_back && c >= 0.0 && c < cols) {
		lim = texture(roof, vec2((floor(c) + 0.5) / cols, 0.5)).r;
		if (splash_band > 0.0 && wp.y > lim + splash_band) {
			discard;
		}
	}
	if (wp.y < lim) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"
const RAIN_BILLBOARD := "wp = MODEL_MATRIX[3].xyz;
	mat4 bw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));"

## Wysokość dachu / gruntu dla każdej kolumny mapy [m] jako tekstura dla `RAIN_SHADER`.
func _roof_texture() -> ImageTexture:
	var cols := 1
	for r in _rows:
		cols = maxi(cols, (r as String).length())
	var img := Image.create(cols, 1, false, Image.FORMAT_RF)
	for c in cols:
		var y := -10000.0
		for r in _rows.size():
			if Level3D.is_solid_ch(Level3D._ch(_rows, c, r)):
				y = -float(r) * Level3D.T
				break
		img.set_pixel(c, 0, Color(y, 0.0, 0.0))
	return ImageTexture.create_from_image(img)

const RAIN_3D := {"rain": [12.0, 700, 10.5], "storm": [26.0, 1500, 13.0]}      # kąt od pionu [°], liczba kropel, prędkość [m/s]
const HAZE_K := {"clear": 0.12, "rain": 0.8, "storm": 0.8, "fog": 1.0}          # zamglenie powietrza wg pogody (mnożnik gęstości bazowej)
const GROUND_FOG_K := {"clear": 0.0, "rain": 0.5, "storm": 0.4, "fog": 1.6}    # wstęgi mgły przy ziemi wg pogody
const MOON_K := {"clear": 1.35, "rain": 0.75, "storm": 0.55, "fog": 1.0}       # jasność księżyca wg pogody
# niebo (`Level3D.SKY_SHADER`) wg pogody; przy słabej pogodzie (k → 0) wartości idą do domyślnych z shadera
const SKY_COVER := {"clear": 0.22, "rain": 0.85, "storm": 0.95, "fog": 0.7}      # zachmurzenie 0..1
const SKY_WIND := {"clear": 0.006, "rain": 0.02, "storm": 0.05, "fog": 0.003}    # dryf chmur [jedn. szumu/s]
const SKY_STARS := {"clear": 1.0, "rain": 0.0, "storm": 0.0, "fog": 0.1}         # gwiazdy w prześwitach
const SKY_MOON := {"clear": 1.0, "rain": 0.08, "storm": 0.0, "fog": 0.22}         # tarcza księżyca (za chmurami deszczu i w mgle blednie)
const WIND_K := {"clear": 0.3, "rain": 0.85, "storm": 1.9, "fog": 0.12}             # wiatr w koronach i runie (`Level3D.set_wind`); bez pogody 0,5
const BACKDROP_VIS := {"clear": 1.0, "rain": 0.55, "storm": 0.45, "fog": 0.25}     # lampki masztu i okno wieży (`backdrop3d.gd`) za deszczem i mgłą
const CANOPY_HAZE_K := {"clear": 1.15, "rain": 0.7, "storm": 0.6, "fog": 0.35}   # zamglenie koron (`Level3D.build_canopy_haze`); w mgle warstwy daje mgła głębi

## Pogoda w scenie 3D (stan z `weather_fx.gd`: siła `_k`, otwartość nieba `_sky`, rodzaj `_id`, błysk `_flash`; dźwięk zostaje tam):
##  - deszcz: smugi kropel w całej głębi sceny (od planu przed graczami po las), pochylone wiatrem, z podmuchami burzy, plus plusk na gruncie;
##  - mgła: gęstsza bryła mgły wolumetrycznej z własną bladą poświatą (światła latarki i flar rysują w niej snopy) i bliższa mgła głębi;
##  - burza: błyskawica to chwilowo jasny księżyc, niebo i światło otoczenia — cienie drzew i postaci na ułamek sekundy.
func _sync_weather(delta: float) -> void:
	var wx := get_tree().root.find_child("WeatherFx", true, false)
	if wx == null:
		return
	var id := String(wx.get("_id"))
	var k := float(wx.get("_k"))
	var sky := float(wx.get("_sky"))
	var mode: int = Settings.weather_fx_effective()
	if _rain == null:
		_rain = CPUParticles3D.new()
		_rain.name = "Rain"
		_rain.local_coords = false
		_rain.emitting = false
		var q := QuadMesh.new()
		q.size = Vector2(0.014, 0.55)
		var rsh := Shader.new()
		rsh.code = RAIN_SHADER
		var m := ShaderMaterial.new()
		m.shader = rsh
		q.material = m
		_rain.mesh = q
		_rain.particle_flag_align_y = true                      # smuga wzdłuż toru lotu
		_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_rain.spread = 2.5
		_rain.gravity = Vector3.ZERO
		_rain.layers = LAYER_WORLD
		_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(_rain)
		_rain_splash = CPUParticles3D.new()
		_rain_splash.name = "RainSplash"
		_rain_splash.local_coords = false
		_rain_splash.emitting = false
		_rain_splash.amount = 90
		_rain_splash.lifetime = 0.28
		var sq := QuadMesh.new()
		sq.size = Vector2(0.035, 0.035)
		var ssh := Shader.new()
		ssh.code = RAIN_SHADER.replace("//BILLBOARD", RAIN_BILLBOARD)
		var smt := ShaderMaterial.new()
		smt.shader = ssh
		smt.set_shader_parameter("splash_band", 0.5)          # plusk tylko tuż nad gruntem swojej kolumny
		sq.material = smt
		_rain_splash.mesh = sq
		_rain_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_rain_splash.direction = Vector3.UP
		_rain_splash.spread = 55.0
		_rain_splash.initial_velocity_min = 0.6
		_rain_splash.initial_velocity_max = 1.7
		_rain_splash.gravity = Vector3(0.0, -9.0, 0.0)
		_rain_splash.layers = LAYER_WORLD
		_rain_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(_rain_splash)
	var flash := float(wx.call("_flash", mode)) * k if id == "storm" else 0.0
	# deszcz
	var raining := RAIN_3D.has(id)
	# obraz deszczu nie zależy już od tego, czy sam gracz stoi pod dachem (to steruje tylko dźwiękiem): pada wszędzie pod gołym niebem,
	# a dachy przycina shader; pod ziemią (poniżej poziomu podziemi) emitery stoją
	var lp0 = wx.call("_local_player")
	var above: bool = lp0 != null and (lp0 as Node2D).global_position.y < float(_level.get("underground_y"))
	_rain_open = move_toward(_rain_open, 1.0 if above else 0.0, get_process_delta_time() * 1.5)
	var strength := k * _rain_open if raining else 0.0
	if raining and _roof_key != _geo_key and not _rows.is_empty():
		_roof_key = _geo_key
		var rt := _roof_texture()
		for pm in [_rain.mesh.surface_get_material(0), _rain_splash.mesh.surface_get_material(0)]:
			(pm as ShaderMaterial).set_shader_parameter("roof", rt)
			(pm as ShaderMaterial).set_shader_parameter("cols", float(rt.get_width()))
			(pm as ShaderMaterial).set_shader_parameter("tile", Level3D.T)
			(pm as ShaderMaterial).set_shader_parameter("z_back", -(Level3D.DEPTH_BACK + 0.3))
			(pm as ShaderMaterial).set_shader_parameter("floor_y", -float(_level.get("underground_y")) * PX)
	_rain.emitting = strength > 0.02
	_rain_splash.emitting = strength > 0.02
	if raining:
		var cfg: Array = RAIN_3D[id]
		var want := maxi(60, int(float(cfg[1]) * (0.6 if mode == Settings.WEATHER_FX_REDUCED else 1.0) * (0.5 if Settings.quality_idx == 0 else 1.0)))
		if _rain.amount != want:
			_rain.amount = want
		var gust := 1.0 + (0.5 * sin(_life * 0.7) * sin(_life * 0.31) if id == "storm" else 0.0)
		var a := deg_to_rad(float(cfg[0]) * gust)
		var dir := Vector3(-sin(a), -cos(a), 0.0)             # wiatr z prawej: krople lecą w lewo w dół
		var cam := _cam_a.global_position
		var half_h := tan(deg_to_rad(FOV * 0.5)) * cam.z * 1.8      # zapas na głębię (dalsze plany widać szerzej)
		var half_w := half_h * 1.9
		var speed := float(cfg[2])
		_rain.direction = dir
		_rain.initial_velocity_min = speed * 0.85
		_rain.initial_velocity_max = speed * 1.15
		_rain.lifetime = (half_h * 2.0 + 2.0) / speed
		_rain.emission_box_extents = Vector3(half_w + half_h * tan(a), 0.4, 8.0)
		_rain.position = Vector3(cam.x + half_h * tan(a), cam.y - EYE_UP_M + half_h + 1.0, -7.1)       # z od −15 do +0,9: krople przed frontem gruntu nie spadają „pod ziemię”
		_rain.color = Color(0.55, 0.62, 0.74, (0.16 + 0.5 * flash) * clampf(strength, 0.0, 1.0))
		var lp = wx.call("_local_player")
		if lp != null:
			_rain_splash.position = Level3D.px_to_m((lp as Node2D).global_position) + Vector3(0.0, 0.03, -1.0)
			_rain_splash.emission_box_extents = Vector3(half_w, 0.01, 1.8)
			_rain_splash.color = Color(0.6, 0.68, 0.8, 0.3 * clampf(strength, 0.0, 1.0))
	# mgła i księżyc
	var fogk := k * (0.45 + 0.55 * sky) if id == "fog" else (k * 0.25 * sky if raining else 0.0)
	var fv := _geo.get_node_or_null("FogVolume") as FogVolume
	if fv != null:
		var fm := fv.material as FogMaterial
		if not fv.has_meta("base_density"):
			fv.set_meta("base_density", fm.density)
		# zamglenie bazowe (snopy świateł w powietrzu) zależy od pogody: w noc pogodną powietrze jest czyste, w deszczu lekko zamglone
		var haze := lerpf(1.0, float(HAZE_K.get(id, 1.0)), k)
		fm.density = float(fv.get_meta("base_density")) * (haze + 9.0 * fogk)
		for gf in _geo.get_children():                             # wstęgi mgły przy ziemi (`Level3D.build_ground_fog`)
			if String(gf.name).begins_with("GroundFog") and gf is MeshInstance3D:
				var gm := (gf as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					if not gf.has_meta("base_density"):
						gf.set_meta("base_density", gm.get_shader_parameter("density"))
					gm.set_shader_parameter("density", float(gf.get_meta("base_density")) * lerpf(1.0, float(GROUND_FOG_K.get(id, 1.0)), k))
		fm.emission = Color(0.092, 0.115, 0.140) * (1.1 * fogk)       # blada własna poświata mgły — czytelna także tam, gdzie nic nie świeci
	var ff := _geo.get_node_or_null("ForestFloor") as MeshInstance3D       # dno lasu (`Level3D.build_forest_floor`) tonie w mgle głębi tylko w mgle
	if ff != null and ff.material_override is BaseMaterial3D:
		var fog_on := id == "fog" and k > 0.5
		if (ff.material_override as BaseMaterial3D).disable_fog == fog_on:
			(ff.material_override as BaseMaterial3D).disable_fog = not fog_on
			Backdrop3D.set_fog(fog_on)                             # punkty orientacyjne tła toną w mgle razem z dnem lasu
	var env := _cam_a.environment
	if env != null:
		if not env.has_meta("base_amb"):
			env.set_meta("base_amb", env.ambient_light_energy)
			env.set_meta("base_fog", env.fog_light_color)
		var deep = _level.get("depth_mult")                          # głębiej = ciemniej (dread.gd): pod ziemią światło otoczenia słabnie
		env.ambient_light_energy = float(env.get_meta("base_amb")) * (float(deep) if deep != null else 1.0) + 0.3 * flash
		env.fog_light_color = (env.get_meta("base_fog") as Color) * (1.0 + 1.6 * fogk + 3.0 * flash)       # w błysku las zostaje sylwetką na jasnym niebie (nie tonie w bieli)
		if id == "fog":
			env.fog_depth_begin -= 1.5 * k                        # mgła głębi podchodzi pod sam plan gry (początek ustawia co klatkę _sync_camera)
		# w mgle bryła mgły zasłania też niebo widoczne między pniami poniżej linii lasu (bór jest prześwitujący), inaczej zostaje tam czarne
		env.volumetric_fog_sky_affect = k if id == "fog" else 0.0
		if env.sky != null and env.sky.sky_material is ShaderMaterial:
			var skm := env.sky.sky_material as ShaderMaterial
			skm.set_shader_parameter("glow", Vector3(0.016, 0.024, 0.044) * (1.0 + 14.0 * flash) * float(MOON_K.get(id, 1.0)))
			_sky_drift.x -= lerpf(0.008, float(SKY_WIND.get(id, 0.008)), k) * delta      # wiatr z prawej (jak deszcz): chmury płyną w lewo
			skm.set_shader_parameter("drift", _sky_drift)
			skm.set_shader_parameter("cover", lerpf(0.6, float(SKY_COVER.get(id, 0.6)), k))
			skm.set_shader_parameter("stars", lerpf(0.3, float(SKY_STARS.get(id, 0.3)), k))
			skm.set_shader_parameter("moon_vis", lerpf(0.85, float(SKY_MOON.get(id, 0.85)), k))
			skm.set_shader_parameter("flash", flash)
	var haze_k := lerpf(1.0, float(CANOPY_HAZE_K.get(id, 1.0)), k)
	for ch in _geo.get_children():                                 # zamglenie koron (`Level3D.build_canopy_haze`)
		if String(ch.name).begins_with("CanopyHaze") and ch is MeshInstance3D:
			((ch as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("strength", haze_k)
	var gusty := 0.5 * sin(_life * 0.7) * sin(_life * 0.31) if id == "storm" else 0.0     # te same podmuchy co pochylenie deszczu
	Level3D.set_wind(lerpf(0.5, float(WIND_K.get(id, 0.5)), k) * (1.0 + gusty), (0.55 + 0.3 * gusty) * k if id == "storm" else 0.0)
	var bvis := lerpf(1.0, float(BACKDROP_VIS.get(id, 1.0)), k)
	for ch in _geo.get_children():                                 # lampki punktów orientacyjnych tła (`backdrop3d.gd`)
		if String(ch.name).begins_with("BackdropLamp") and ch is MeshInstance3D:
			((ch as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("vis", bvis)
	var rim := _geo.get_node_or_null("MoonRim") as DirectionalLight3D
	if rim != null:
		rim.light_energy = Level3D.MOON_RIM * lerpf(1.0, float(MOON_K.get(id, 1.0)), k) + 1.2 * flash
	var moon := _geo.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		if not moon.has_meta("base_e"):
			moon.set_meta("base_e", moon.light_energy)
		moon.light_energy = float(moon.get_meta("base_e")) * lerpf(1.0, float(MOON_K.get(id, 1.0)), k) + 0.7 * flash       # błysk: krótkie cienie drzew i postaci, ale nie dzień
		moon.light_color = Color(0.62, 0.72, 0.95).lerp(Color(0.9, 0.93, 1.0), clampf(flash, 0.0, 1.0))

# ---------------------------------------------------------------- krew

const BLOOD_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform float seed = 0.0;
uniform float wet = 1.0;             // 1 = świeża (lśni), 0 = zaschnięta (matowa, ciemniejsza)
uniform float fade = 1.0;
//COMMON
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// nieregularny brzeg z językami: kałuża rozlewa się nierówno
	float edge = 0.70 + 0.26 * (fbm(vec2(ang * 1.6 + seed * 3.0, seed)) - 0.5) * 2.0 + 0.12 * (vn(vec2(cos(ang), sin(ang)) * 5.0 + seed) - 0.5);
	float a = 1.0 - smoothstep(edge - 0.10, edge, r);
	if (a < 0.02) { discard; }
	float thick = smoothstep(edge, edge * 0.35, r);                 // środek głębszy i ciemniejszy
	ALBEDO = mix(vec3(0.11, 0.006, 0.008), vec3(0.035, 0.002, 0.004), thick) * mix(0.55, 1.0, wet);
	ROUGHNESS = mix(0.8, 0.16, wet);
	SPECULAR = mix(0.2, 0.6, wet);
	ALPHA = a * mix(0.90, 0.98, thick) * fade;
}
"""
const BLOOD_MAX := 110                      ## limit kałuż i smug ciągnięcia (najstarsze znikają)
const BLOOD_MERGE_M := 0.45                 ## bliższe plamy zlewają się w jedną, większą kałużę
const BLOOD_MAX_R := 0.75                   ## największy promień kałuży [m]

## Wołane z `Vfx.splat` (szczątki, śmierć wroga) i `BloodDecals.add` (kapanie rannych): krew zbiera się w lśniące kałuże na gruncie.
## Plama blisko istniejącej ją powiększa (kałuża rośnie), nowa rozlewa się przez ok. 1,5 s; z czasem krew zasycha (matowieje) i znika.
func mirror_blood(pos: Vector2, radius: float) -> void:
	var at := Level3D.px_to_m(pos)
	var want := clampf(radius * PX * 1.7, 0.10, BLOOD_MAX_R)
	for b in _blood:
		var mi_v = b[0]
		if is_instance_valid(mi_v) and absf((mi_v as Node3D).position.x - at.x) < BLOOD_MERGE_M and absf((mi_v as Node3D).position.y - at.y) < 0.25:
			b[1] = minf(sqrt(float(b[1]) * float(b[1]) + want * want * 0.6), BLOOD_MAX_R)      # sumowanie powierzchni
			b[3] = 0.0                                                                         # znów świeża
			return
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	if _blood_shader == null:
		_blood_shader = Shader.new()
		_blood_shader.code = BLOOD_SHADER.replace("//COMMON", Level3D.PROP_COMMON)
	sm.shader = _blood_shader
	sm.set_shader_parameter("seed", randf() * 40.0)
	mi.material_override = sm
	mi.layers = LAYER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x, at.y + 0.015 + 0.0004 * float(_blood.size()), randf_range(-0.35, 0.55))
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(0.03, 1.0, 0.03)
	_geo.add_child(mi)                                         # znika z geometrią mapy
	_blood.append([mi, want, 0.03, 0.0])
	if _blood.size() > BLOOD_MAX:
		var old: Array = _blood.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()

## Smuga krwi za porwanym graczem (Żerca, ENEMY_PLAN.md F4d, wariant C): co `DRAG_STEP` px drogi ciągniętego ciała rozciągnięta plama wzdłuż
## przesunięcia — ślad prowadzi do legowiska. Czyta replikowane `taken`, więc smugę widzi każdy peer; zasycha i znika jak zwykła krew.
const DRAG_STEP := 16.0                     ## px świata między smugami (ok. 1 m)
var _drag_last := {}                        ## id gracza → pozycja ostatniej smugi

func _sync_drag_trails() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var id := p.get_instance_id()
		if not bool(p.get("taken")):
			_drag_last.erase(id)
			continue
		var pos: Vector2 = (p as Node2D).global_position
		if not _drag_last.has(id):
			_drag_last[id] = pos
			continue
		var last: Vector2 = _drag_last[id]
		if pos.distance_to(last) >= DRAG_STEP:
			_drag_smear(last, pos)
			_drag_last[id] = pos

## Rozciągnięta plama między `a` i `b` (px świata) — ten sam shader co kałuże, wydłużona w osi ciągnięcia.
func _drag_smear(a: Vector2, b: Vector2) -> void:
	var at := Level3D.px_to_m((a + b) * 0.5)
	var length := a.distance_to(b) * PX * 1.7                    # brzeg plamy jest postrzępiony (shader) — zakładka, żeby ślad był ciągły
	var r := 0.12
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	if _blood_shader == null:
		_blood_shader = Shader.new()
		_blood_shader.code = BLOOD_SHADER.replace("//COMMON", Level3D.PROP_COMMON)
	sm.shader = _blood_shader
	sm.set_shader_parameter("seed", randf() * 40.0)
	mi.material_override = sm
	mi.layers = LAYER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x, at.y + 0.015 + 0.0004 * float(_blood.size()), randf_range(0.05, 0.2))
	mi.rotation.z = atan2(b.y - a.y, b.x - a.x) * -1.0 if absf(b.x - a.x) > 0.001 else 0.0     # zbocze: smuga leży wzdłuż drogi
	mi.scale = Vector3(length * 0.5, 1.0, 0.30)                    # od razu pełna: ciało przesuwa się, krew się nie rozlewa
	_geo.add_child(mi)
	_blood.append([mi, r, r, 0.0, Vector2(length * 0.5 / r, 0.30 / (r * 0.8))])     # ok. 0,6 m w głąb: kamera patrzy prawie z boku, wąska smuga byłaby kreską
	if _blood.size() > BLOOD_MAX:
		var old: Array = _blood.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()

func _sync_blood(delta: float) -> void:
	var i := 0
	while i < _blood.size():
		var b: Array = _blood[i]
		if not is_instance_valid(b[0]):
			_blood.remove_at(i)
			continue
		var mi := b[0] as MeshInstance3D
		b[2] = move_toward(float(b[2]), float(b[1]), delta * maxf(0.06, (float(b[1]) - float(b[2])) * 1.4))      # rozlewanie: szybko, potem coraz wolniej
		b[3] = float(b[3]) + delta
		var st: Vector2 = b[4] if b.size() > 4 else Vector2.ONE           # smuga ciągnięcia: rozciągnięta w osi x
		mi.scale = Vector3(float(b[2]) * st.x, 1.0, float(b[2]) * 0.8 * st.y)
		var sm := mi.material_override as ShaderMaterial
		sm.set_shader_parameter("wet", (1.0 - smoothstep(25.0, 70.0, float(b[3]))) * (0.3 if b.size() > 4 else 1.0))   # smuga: rozmazana, mniej lśni
		var fade := 1.0 - smoothstep(110.0, 130.0, float(b[3]))
		sm.set_shader_parameter("fade", fade)
		if fade <= 0.0:
			mi.queue_free()
			_blood.remove_at(i)
			continue
		i += 1

# ---------------------------------------------------------------- tor drezyny

const RAIL_H := 0.5 * PX                    ## wysokość szyny [m] — koło drezyny (oś 2,5 px nad torem) stoi na jej główce
const RAIL_Z := [0.98, 0.38]                ## szyna bliższa kamerze (pod kołami) i dalsza — obie w korycie przed peronem
const TRACK_ZC := 0.68                      ## oś toru: tu stoi korpus drezyny i pasażerowie
const WHEEL_D := 4.0                        ## średnica koła drezyny w widoku 3D [px świata] (sprite 2D: 6,8 px — sięgał poniżej posadzki)

## Trasa drezyny [x0, x1, y] w pikselach świata (od stacji do końca toru przy wyjściu, w dowolnym kierunku) albo pusta tablica.
## Liczona raz na mapę — potem drezyna jeździ, a tor i koryto zostają.
func _rail_span() -> Array:
	var mid := String(_level.get("map_id"))
	if _span_map == mid:
		return _span
	var hc := get_tree().get_first_node_in_group("handcar") as Node2D
	if hc == null:
		return []
	var exits = _level.get("exits")
	var xa := hc.global_position.x
	var xb := xa
	if exits != null and not (exits as Array).is_empty():
		xb = ((exits as Array)[0] as Vector2).x + 70.0
	_span = [minf(xa, xb) - 60.0, maxf(xa, xb) + 60.0, hc.global_position.y]
	_span_map = mid
	return _span

## Tor pod drezyną: dwie szyny i podkłady od stacji startowej do końca trasy (wyjście poziomu). Budowany raz na geometrię mapy.
func _build_rails() -> void:
	var span := _rail_span()
	if span.is_empty() or _geo.has_node("Rails"):
		return
	var x0: float = span[0]
	var x1: float = span[1]
	var root := Node3D.new()
	root.name = "Rails"
	_geo.add_child(root)
	var base := Level3D.px_to_m(Vector2(x0, float(span[2]))) - Vector3(0.0, Level3D.TRENCH_D, 0.0)      # dno koryta
	var len_m := (x1 - x0) * PX
	var steel := Level3D.make_pbr("metal", 0.6, Color(0.3, 0.3, 0.32), 0.45, 1.0, 1.0)
	for z in RAIL_Z:
		for part in [[0.045, RAIL_H * 0.75, RAIL_H * 0.625], [0.085, RAIL_H * 0.25, RAIL_H * 0.125]]:      # główka + stopka
			var rb := BoxMesh.new()
			rb.size = Vector3(len_m, float(part[1]), float(part[0]))
			var ri := MeshInstance3D.new()
			ri.mesh = rb
			ri.material_override = steel
			ri.position = base + Vector3(len_m * 0.5, float(part[2]) if part[0] == 0.045 else float(part[2]), float(z))
			ri.layers = LAYER_WORLD
			root.add_child(ri)
	var tie := BoxMesh.new()
	tie.size = Vector3(0.2, 0.03, absf(RAIL_Z[0] - RAIL_Z[1]) + 0.22)
	var n := int(len_m / 0.62)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tie
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, sin(float(i) * 12.9898) * 0.04), base + Vector3(0.3 + float(i) * 0.62, 0.012, (RAIL_Z[0] + RAIL_Z[1]) * 0.5)))
	var ti := MultiMeshInstance3D.new()
	ti.multimesh = mm
	ti.material_override = Level3D.make_pbr("post", 1.2, Color(0.2, 0.15, 0.1), 1.0, 1.0, 1.0, false, "organic")
	ti.layers = LAYER_WORLD
	root.add_child(ti)

# ---------------------------------------------------------------- przedmioty HD (meble, skrytki, pickupy, generator, drezyna)

const ITEM_TONE := 0.7                      ## przyciemnienie albedo kart: przedmiot z własnym światłem (skrytka, pickup) stoi tuż przy nim
const ITEM3D_DIR := "res://art/items3d/"
## Skala modeli przedmiotów względem wymiarów z potoku sprite'ów (1 jednostka = 1 px świata): meble i sprzęt kryjówki stały w skali
## „komiksowej" (stół 1,55 m, szafka 2,54 m, radiostacja jak lodówka), a znajdźki były 2–8 razy większe od prawdziwych (granat 0,6 m) —
## przy postaci 1,8 m i broni w naturalnej skali. Meble → wymiary naturalne, znajdźki → ok. 1,5–2× naturalnych (zostają czytelne: poświata,
## znacznik rodzaju). Tylko obraz: przedmioty stoją za płaszczyzną gry albo nie mają kolizji. Skrzynie i beczki (prop.gd) mają ciała 2D, na
## których się staje — ich skala zostaje. Sprawdza tools/test_proportions.gd.
const ITEM_SCALE := {
	"table": 0.78, "chair": 0.73, "stool": 0.76, "cot": 0.76, "workshop": 0.9, "locker": 0.73, "shelf": 0.8, "radio_set": 0.5, "lamp": 0.5,
	"frag": 0.37, "smoke": 0.5, "phos": 0.35, "flare": 0.6, "mine": 0.6, "ammo": 0.7, "medkit": 0.6, "charge": 0.65, "defib": 0.6,
	"scanner": 0.45, "tag": 0.6, "padlock": 0.4,
}
const ITEM_BACK := ["shelf", "table", "chair", "locker", "cot", "stool", "board", "results_board", "workshop", "tools_wall", "rack"]

## Każdy sprite z `ItemsHd.make` (grupa „items_hd”) dostaje w scenie 3D kartę z tym samym albedo i mapą normalnych: oświetlają ją światła 3D,
## rzuca cień na ścianę za sobą, łapie SSAO i mgłę — zamiast płaskiego rysunku 2D z osobnym oświetleniem nałożonego na obraz 3D.
## Meble stoją w głębi (przy ścianie tła), reszta tuż za płaszczyzną gry. Sprite 2D zostaje (logika, światła 2D), tylko jest przezroczysty.
func _sync_items() -> void:
	for n in get_tree().get_nodes_in_group("items_hd"):
		var sp := n as ItemsHd.ItemMark
		if sp == null or sp.is_queued_for_deletion() or _items.has(sp.get_instance_id()):
			continue
		var par := sp.get_parent()
		if par != null and par.is_in_group("props"):
			continue                                  # skrzynie i beczki mają własne bryły (_sync_props)
		_make_item(sp)
	for id in _items.keys():
		var it: Array = _items[id]
		var src_v = it[0]
		var mi: Node3D = it[1]
		if not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion():
			if is_instance_valid(mi):
				mi.queue_free()
			_items.erase(id)
			_cache_piles.erase(id)
			continue
		var sp := src_v as ItemsHd.ItemMark
		mi.visible = sp.is_visible_in_tree()
		if not mi.visible:
			continue
		if _cache_piles.has(id):                               # sterta skrzyni z mapy idzie za bronią drużyny (zmiana broni, śmierć, dołączenie)
			var keys := _team_primaries()
			if keys != _cache_piles[id]:
				_cache_piles[id] = keys
				_build_cache_pile(mi, keys, float(sp.get_meta("hd_dark", 0.0)) * 0.35)
		var xf := sp.global_transform
		var sc := xf.get_scale()
		if bool(it[5]):                                        # model 3D: początek w stopach sprite'a, jednostka modelu = piksel świata
			var k := absf(sc.x) * ItemsHd.ppw(String(sp.get_meta("hd_name", ""))) * PX * float(ITEM_SCALE.get(String(sp.get_meta("hd_name", "")), 1.0))
			var fl := -1.0 if (sp.flip_h != (xf.determinant() < 0.0)) else 1.0
			# stopy modelu = dolna krawędź bryły w ramce sprite'a (dla sprite'ów obracanych wokół środka — koła, dźwignia — to nie jest początek węzła)
			var nm3 := String(sp.get_meta("hd_name", ""))
			var feet := xf.origin if (it.size() > 6 and bool(it[6])) else xf * (sp.offset + Vector2(0.0, ItemsHd.frame_px(nm3).y * 0.5 - ItemsHd.PAD))
			(it[1] as Node3D).position = Level3D.px_to_m(feet) + Vector3(0.0, 0.0, float(it[3]))
			if nm3.begins_with("handcar"):                         # drezyna stoi w korycie: pokład równo z peronem
				(it[1] as Node3D).position.y -= Level3D.TRENCH_D
			(it[1] as Node3D).rotation = Vector3(0.0, 0.0, -xf.get_rotation())
			(it[1] as Node3D).scale = Vector3(k * fl, k, k * (0.7 if nm3 == "handcar" else 1.0))      # korpus drezyny węższy — mieści się w korycie
			if nm3 == "rack":                                      # stojak: mniejszy niż sprite 2D, zawieszony na ścianie, plecami do muru
				(it[1] as Node3D).scale = Vector3(k * fl, k, k) * RACK_SCALE
				(it[1] as Node3D).position = Level3D.px_to_m(feet) + Vector3(0.0, RACK_UP_PX * PX, RACK_Z)
			continue
		var ts := ItemsHd.frame_px(String(sp.hd_name))
		var centre := xf * sp.offset
		mi.position = Level3D.px_to_m(centre) + Vector3(0.0, 0.0, float(it[3]))
		mi.rotation = Vector3(0.0, 0.0, -xf.get_rotation())
		var flip := -1.0 if (sp.flip_h != (xf.determinant() < 0.0)) else 1.0
		mi.scale = Vector3(ts.x * absf(sc.x) * PX * flip, ts.y * absf(sc.y) * PX, 1.0)
		var m := it[2] as StandardMaterial3D
		var md := sp.modulate
		var up := sp.get_parent()
		while up is CanvasItem and up != _level:               # mnożniki koloru rodziców (błysk trafienia, zanikanie)
			md *= (up as CanvasItem).modulate
			up = up.get_parent()
		m.albedo_color = Color(md.r * ITEM_TONE, md.g * ITEM_TONE, md.b * ITEM_TONE, md.a)

## Model 3D przedmiotu (art/items3d/<nazwa>.glb z `tools/prep_items3d.py`) albo null, gdy go nie ma; sceny są trzymane w pamięci podręcznej.
func _item_scene(name: String) -> PackedScene:
	if not _item_scenes.has(name):
		var path := ITEM3D_DIR + name + ".glb"
		_item_scenes[name] = load(path) as PackedScene if (ResourceLoader.exists(path) and not "--noitems3d" in OS.get_cmdline_user_args()) else null
	return _item_scenes[name]

## Egzemplarz modelu przedmiotu na warstwie świata; `glow` > 0 dodaje słabą emisję z koloru (przedmioty widoczne w ciemności).
func _item_model(name: String, glow := 0.0) -> Node3D:
	var ps := _item_scene(name)
	if ps == null:
		return null
	var root := ps.instantiate() as Node3D
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = LAYER_WORLD
		if mi.mesh != null and not _item_tuned.has(name):         # jednorazowo na model: słabszy połysk — w bliskim świetle latarki mapa chropowatości
			for s in mi.mesh.get_surface_count():                  # z generatora dawała „pogniecione” odbłyski na drewnie i płótnie
				var sm := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if sm != null:
					sm.metallic_specular = 0.12
					sm.metallic = minf(sm.metallic, 0.6)
		if glow > 0.0 and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var bm := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if bm == null or bm.emission_enabled:
					continue
				var dm := bm.duplicate() as BaseMaterial3D
				dm.emission_enabled = true
				dm.emission_texture = dm.albedo_texture
				dm.emission_energy_multiplier = glow
				mi.set_surface_override_material(s, dm)
	_item_tuned[name] = true
	return root

## Wygląd naboi broni: [rodzaj, liczba sztuk rozsypanych przy skrzynce]. Rodzaje rysuje `_ammo_round`.
const AMMO_LOOK := {
	"m83": ["rifle", 3], "p64": ["pistol", 3], "spread12": ["shell", 3], "srut8": ["shell_g", 3], "lr7": ["cell", 2], "hkm9": ["fuel", 1],
	"gniew4": ["grenade40", 2], "sokol6": ["rocket", 2], "widmo1": ["slug", 2], "ciegno6": ["bolt", 2],
}
## Promień leżącego naboju (jednostki modelu): oś na tej wysokości nad ziemią.
const AMMO_LIE_R := {"rifle": 0.45, "pistol": 0.45, "shell": 0.72, "shell_g": 0.72, "cell": 1.04, "grenade40": 1.1, "rocket": 0.8, "slug": 0.36}
const AMMO_LOOSE_K := 1.35                  ## skala rozsypanych naboi względem skrzynki (większe niż w naturze — czytelne w kamerze gry)

## Skrzynka amunicji bez tabliczki: przed nią leży kilka naboi broni, do której jest (łuski karabinowe, śrut, ogniwa lasera, kanister,
## granaty 40 mm, rakietki, pręty railguna, bełty) — rodzaj amunicji widać po nich, jak na stercie skrzyni z mapy.
func _add_kind_tag(sp: ItemsHd.ItemMark, model: Node3D) -> void:
	var owner_n := sp.get_parent().get_parent() if sp.get_parent() != null else null
	if owner_n == null or owner_n.get("kind") == null or String(owner_n.get("kind")) != "ammo":
		return
	var front := -INF
	var span := Vector2(INF, -INF)                             # zakres x bryły: środek modelu z generatora nie zawsze leży w x = 0
	for mn in model.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = _local_xf(mn as MeshInstance3D, model) * (mn as MeshInstance3D).get_aabb()
		front = maxf(front, ab.end.z)
		span = Vector2(minf(span.x, ab.position.x), maxf(span.y, ab.end.x))
	if front == -INF:
		return
	_loose_rounds(model, String(Weapons.def(int(owner_n.get("arg"))).key), Vector3((span.x + span.y) * 0.5, 0.0, front + 1.4),
			span.y - span.x, int(owner_n.get_instance_id()))

## Naboje broni `key` rozsypane na ziemi wokół `at` (w poprzek ok. `width`): leżą osią w bok, każdy pod innym kątem; kanister stoi.
## `k` — jednostka modelu ammo.glb w jednostkach rodzica (na stercie skrzyni z mapy rodzic ma inną skalę niż skrzynka).
func _loose_rounds(parent: Node3D, key: String, at: Vector3, width: float, seed_v: int, k := 1.0) -> void:
	var sk := AMMO_LOOSE_K * k
	var look: Array = AMMO_LOOK.get(key, ["rifle", 3])
	var kind := String(look[0])
	var n := int(look[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in n:
		var r := Node3D.new()
		r.name = "LooseRound"
		parent.add_child(r)
		_ammo_round(r, kind)
		var x := at.x + (float(i) - float(n - 1) * 0.5) * width * 0.32 + rng.randf_range(-0.8, 0.8) * k
		var z := at.z + rng.randf_range(-0.6, 0.6) * k
		r.scale = Vector3.ONE * sk
		if kind == "fuel":                                     # kanister stoi obok skrzynki
			r.position = Vector3(x, 0.0, z)
			r.rotation.y = rng.randf_range(-0.5, 0.5)
		elif kind == "bolt":                                   # bełt leży już poziomo (oś x)
			r.position = Vector3(x, 0.45 * sk, z)
			r.rotation.y = rng.randf_range(-0.6, 0.6)
		else:                                                  # nabój stoi w osi y: obrót o 90° wokół z kładzie go na boku
			r.position = Vector3(x, float(AMMO_LIE_R.get(kind, 0.5)) * sk, z)
			r.rotation = Vector3(0.0, rng.randf_range(-1.2, 1.2), -PI * 0.5)

# ---------------------------------------------------------------- skrzynia z mapy jako sterta zawartości

const CACHE_PILE_MAX := 3                   ## najwięcej skrzynek amunicji na stercie (po jednej na broń)

## Bronie główne, które skrzynia z mapy uzupełni (jak `pickup._try_cache`: żywi gracze ludzie), klucze posortowane, najwyżej CACHE_PILE_MAX.
func _team_primaries() -> Array:
	var keys: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if bool(p.get("is_bot")) or bool(p.get("dead")) or not p.has_method("kit_primaries"):
			continue
		for w in p.kit_primaries():
			if int(w) >= 0:
				var k := String(Weapons.def(int(w)).key)
				if not keys.has(k):
					keys.append(k)
	keys.sort()
	return keys.slice(0, CACHE_PILE_MAX)

## Skrzynia z mapy (pickup „cache”) rysowana jako sterta tego, co daje: skrzynka amunicji na każdą broń główną drużyny (druga na pierwszej,
## trzecia obok), przed nimi rozsypane naboje tych broni, flara oparta o stos. Jednostka modelu = piksel świata w skali skrzyni z mapy.
func _build_cache_pile(root: Node3D, keys: Array, glow: float) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	var kc := ItemsHd.ppw("cache") * float(ITEM_SCALE.get("cache", 1.0))
	var ka := ItemsHd.ppw("ammo") * float(ITEM_SCALE["ammo"]) / kc        # skrzynka i flara w tej samej skali co na ziemi osobno
	var kf := ItemsHd.ppw("flare") * float(ITEM_SCALE["flare"]) / kc
	var crates: Array = keys.duplicate() if not keys.is_empty() else [""]
	var size := Vector3(10.4, 8.6, 9.0)                        # bryła ammo.glb (tools/prep_items3d.py: szerokość 10,4 × wysokość 8,6)
	var w := size.x * ka
	var spots := [Vector3(-w * 0.28, 0.0, 0.0), Vector3(w * 0.12, size.y * ka * 0.97, 0.4), Vector3(w * 0.78, 0.0, -1.2)]
	var tilt := [0.06, -0.2, 0.14]
	var right := -INF
	for i in crates.size():
		var m := _item_model("ammo", glow)
		if m == null:
			continue
		m.name = "PileCrate%d" % i
		m.scale = Vector3.ONE * ka * (0.94 if i == 1 else 1.0)
		m.position = spots[i]
		m.rotation.y = tilt[i]
		root.add_child(m)
		right = maxf(right, (spots[i] as Vector3).x + w * 0.5)
	var left := (spots[0] as Vector3).x - w * 0.5
	var lane := (right - left) / float(crates.size())          # naboje każdej broni na osobnym odcinku przed stertą, żeby się nie mieszały
	for i in crates.size():
		if String(crates[i]) != "":
			_loose_rounds(root, String(crates[i]), Vector3(left + lane * (float(i) + 0.5), 0.0, (size.z * 0.5 + 1.8 + 0.5 * float(i)) * ka),
					lane * 0.9, i * 7919 + 13, ka)
	var fl := _item_model("flare", glow)
	if fl != null:                                              # flara oparta o stos z prawej, leży ukośnie
		fl.name = "PileFlare"
		fl.scale = Vector3.ONE * kf * 0.75                       # flara w pełnej skali przytłaczała skrzynki
		fl.position = Vector3(right + 15.8 * kf * 0.2, 0.0, 1.8)
		fl.rotation = Vector3(0.0, -0.35, 1.18)
		root.add_child(fl)

## Jeden nabój danego rodzaju, stojący pionowo (dno w y = 0); bełt leży poziomo.
func _ammo_round(r: Node3D, look: String) -> void:
	var brass := _ammo_mat(Color(0.78, 0.6, 0.3), 0.35, 0.4)
	match look:
		"rifle", "pistol":
			var h := 3.0 if look == "rifle" else 1.6
			_ammo_cyl(r, 0.45, 0.45, h, 0.0, brass)                                     # łuska
			_ammo_cyl(r, 0.42, 0.08, 1.2 if look == "rifle" else 0.7, h, _ammo_mat(Color(0.7, 0.38, 0.2), 0.35, 0.4))      # pocisk
		"shell", "shell_g":
			_ammo_cyl(r, 0.72, 0.72, 0.7, 0.0, brass)                                   # mosiężna stopka
			_ammo_cyl(r, 0.7, 0.7, 2.2, 0.7, _ammo_mat(Color(0.6, 0.1, 0.08) if look == "shell" else Color(0.18, 0.4, 0.2), 0.55))
		"cell":
			_ammo_cyl(r, 1.0, 1.0, 3.6, 0.0, _ammo_mat(Color(0.16, 0.17, 0.18), 0.5, 0.3))
			_ammo_cyl(r, 0.5, 0.5, 0.35, 3.6, _ammo_mat(Color(0.6, 0.62, 0.65), 0.4, 0.4))      # styk
			var gm := _ammo_mat(Color(0.4, 0.85, 1.0), 0.4)
			gm.emission_enabled = true
			gm.emission = Color(0.4, 0.85, 1.0)
			gm.emission_energy_multiplier = 1.2
			_ammo_cyl(r, 1.04, 1.04, 0.5, 2.4, gm)                                       # świecący pasek naładowania
		"fuel":
			var red := _ammo_mat(Color(0.55, 0.1, 0.07), 0.5)
			_ammo_box(r, Vector3(3.4, 4.2, 1.4), Vector3(0.0, 2.1, 0.0), red)            # kanister
			_ammo_box(r, Vector3(1.6, 0.5, 0.6), Vector3(-0.6, 4.45, 0.0), red)          # rączka
			_ammo_cyl(r, 0.35, 0.35, 0.6, 4.2, _ammo_mat(Color(0.2, 0.2, 0.2), 0.5)).position.x = 1.1      # korek
		"grenade40":
			_ammo_cyl(r, 1.1, 1.1, 1.3, 0.0, brass)                                       # krótka łuska
			_ammo_cyl(r, 1.05, 0.55, 1.5, 1.3, _ammo_mat(Color(0.33, 0.36, 0.2), 0.6))   # oliwkowa głowica
			_ammo_cyl(r, 1.06, 1.06, 0.2, 1.6, _ammo_mat(Color(0.75, 0.62, 0.15), 0.5))  # żółty pasek (odłamkowy)
		"rocket":
			var ol := _ammo_mat(Color(0.3, 0.33, 0.2), 0.6)
			_ammo_cyl(r, 0.5, 0.5, 3.4, 0.6, ol)                                         # korpus
			_ammo_cyl(r, 0.5, 0.05, 1.1, 4.0, _ammo_mat(Color(0.6, 0.12, 0.08), 0.5))   # czerwony czubek
			_ammo_box(r, Vector3(1.6, 0.9, 0.12), Vector3(0.0, 0.45, 0.0), ol)           # stateczniki
		"slug":
			_ammo_cyl(r, 0.32, 0.32, 4.6, 0.0, _ammo_mat(Color(0.58, 0.6, 0.64), 0.35, 0.4))
			var sm := _ammo_mat(Color(0.55, 0.85, 1.0), 0.4)
			sm.emission_enabled = true
			sm.emission = Color(0.55, 0.85, 1.0)
			sm.emission_energy_multiplier = 1.0
			_ammo_cyl(r, 0.36, 0.36, 0.3, 3.4, sm)
			_ammo_cyl(r, 0.36, 0.36, 0.3, 1.0, sm)
		"bolt":                                                                          # bełt harpunu: leży poziomo, grot w prawo
			r.position = Vector3(0.0, float(r.get_index()) * 0.9, 0.0)        # bełty jeden nad drugim
			var shaft := _ammo_cyl(r, 0.16, 0.16, 6.4, -3.2, _ammo_mat(Color(0.22, 0.2, 0.18), 0.6))
			shaft.rotation.z = -PI * 0.5
			shaft.position = Vector3.ZERO
			var tip := _ammo_cyl(r, 0.42, 0.02, 1.2, 0.0, _ammo_mat(Color(0.62, 0.64, 0.66), 0.35, 0.4))
			tip.rotation.z = -PI * 0.5
			tip.position = Vector3(3.8, 0.0, 0.0)
			_ammo_box(r, Vector3(1.2, 0.8, 0.08), Vector3(-2.7, 0.0, 0.0), _ammo_mat(Color(0.6, 0.15, 0.1), 0.7))    # lotka

func _ammo_mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal                                         # bez pełnego metalu: w ciemności bez odbić byłby czarny
	return m

## Walec (albo stożek ścięty) o dnie w y = `y0`.
func _ammo_cyl(parent: Node3D, r_bot: float, r_top: float, h: float, y0: float, m: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bot
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(0.0, y0 + h * 0.5, 0.0)
	mi.layers = LAYER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _ammo_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.layers = LAYER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _make_item(sp: ItemsHd.ItemMark) -> void:
	var name := String(sp.get_meta("hd_name", ""))
	var alb: Texture2D = ItemsHd.albedo(name) if _item_scene(name) == null else null      # karta zastępcza tylko dla przedmiotu bez modelu
	var model: Node3D = null
	if name == "cache" and _item_scene("ammo") != null:        # skrzynia z mapy: sterta jej zawartości (amunicja broni drużyny + flara)
		model = Node3D.new()
		model.name = "CachePile"
		var keys := _team_primaries()
		_build_cache_pile(model, keys, float(sp.get_meta("hd_dark", 0.0)) * 0.35)
		_cache_piles[sp.get_instance_id()] = keys
	else:
		model = _item_model(name, float(sp.get_meta("hd_dark", 0.0)) * 0.35)
	if model != null:                                          # prawdziwa bryła zamiast karty
		_world.add_child(model)
		_add_kind_tag(sp, model)
		if name == "stake":                                    # kołek strefy wyjścia: świecąca głowica w kolorze flary (zamiast nakładki 2D)
			var tip := MeshInstance3D.new()
			var ts := SphereMesh.new()
			ts.radius = 0.55
			ts.height = 1.1
			tip.mesh = ts
			var tm := StandardMaterial3D.new()
			tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var fc := Color(0.55, 0.92, 1.0) if Settings.colorblind_idx != 0 else Color(0.4, 1.0, 0.5)
			tm.albedo_color = Color(fc.r * 1.8, fc.g * 1.8, fc.b * 1.8)
			tip.material_override = tm
			tip.position = Vector3(0.0, 8.4, 0.0)
			tip.layers = LAYER_WORLD
			tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			model.add_child(tip)
		var hid: Array = [sp]
		sp.self_modulate = Color(1, 1, 1, 0)
		var emits := false
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mm := (n as MeshInstance3D).mesh
			if mm != null and mm.get_surface_count() > 0 and mm.surface_get_material(0) is BaseMaterial3D and (mm.surface_get_material(0) as BaseMaterial3D).emission_enabled:
				emits = true
		for c in sp.get_children():
			# kopia „widoczna w ciemności” oraz nakładka diod / ekranu ze sprite'a: model ma własną emisję w swoich miejscach
			if c is Sprite2D:                                  # żadnych nakładek 2D na modelu (świecenie daje emisja modelu)
				(c as Sprite2D).visible = false
				hid.append(c)
		if name == "handcar":                                  # belka podwozia rysowana w 2D przed graczami zasłaniałaby koła 3D
			var apron := sp.get_parent().get_node_or_null("Apron") as CanvasItem
			if apron != null:
				apron.visible = false
				hid.append(apron)
		var zoff := -1.45 if ITEM_BACK.has(name) else (TRACK_ZC if name.begins_with("handcar") else -0.2)
		if name == "rack":                                     # drewno z generatora jest jaskrawopomarańczowe w ciepłym świetle lamp — tonujemy
			_tint_model(model, Color(0.56, 0.5, 0.46))
		if sp.offset == Vector2.ZERO:
			# sprite obracany wokół środka (koło, dźwignia drezyny): model wisi na przegubie w swoim środku, żeby obrót szedł wokół osi
			var box := AABB()
			var first := true
			for n in model.find_children("*", "MeshInstance3D", true, false):
				var bb := _local_xf(n as Node3D, model) * (n as MeshInstance3D).get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			var k0 := WHEEL_D / maxf(box.size.y, 0.001) if name == "handcar_wheel" else 1.0
			_world.remove_child(model)
			var pivot := Node3D.new()
			_world.add_child(pivot)
			pivot.add_child(model)
			model.scale = Vector3(k0, k0, k0)
			model.position = Vector3(-box.get_center().x * k0, -box.get_center().y * k0, 0.0)
			_items[sp.get_instance_id()] = [sp, pivot, null, RAIL_Z[0] if name == "handcar_wheel" else zoff, hid, true, true]
			return
		_items[sp.get_instance_id()] = [sp, model, null, zoff, hid, true, false]
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = alb
	var ct := ItemsHd.texture(name)
	if ct != null and ct.normal_texture != null:
		m.normal_enabled = true
		m.normal_texture = ct.normal_texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.82
	m.metallic_specular = 0.3
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var dark := float(sp.get_meta("hd_dark", 0.0))
	if dark > 0.0:                                             # przedmioty, które w 2D prześwitują w ciemności (granat, mina, flara) — słaba emisja
		m.emission_enabled = true
		m.emission_texture = alb
		m.emission_energy_multiplier = dark * 0.35
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.layers = LAYER_WORLD
	_world.add_child(mi)
	var hidden: Array = [sp]
	sp.self_modulate = Color(1, 1, 1, 0)
	for c in sp.get_children():
		if c is Sprite2D and (c as Sprite2D).texture == alb:      # kopia „widoczna w ciemności” (dark_vis) — zastępuje ją emisja karty
			(c as Sprite2D).visible = false
			hidden.append(c)
	_items[sp.get_instance_id()] = [sp, mi, m, -1.25 if ITEM_BACK.has(name) else -0.12, hidden, false]

# ---------------------------------------------------------------- obiekty fizyczne (skrzynie, beczki)

## Skrzynie i beczki (`prop.gd`, grupa „props”) jako bryły 3D: rzucają cień, łapią światło flary i latarki, obracają się jak ciało 2D.
## Wersja 2D zostaje (fizyka, trafienia), tylko jest przezroczysta.
func _sync_props() -> void:
	for n in get_tree().get_nodes_in_group("props"):
		if n is Node2D and not n.is_queued_for_deletion() and not _props.has(n.get_instance_id()):
			var kind := String(n.get("kind"))
			var px: Node3D = _item_model(kind)                 # bryła z potoku przedmiotów (ta sama co sprite 2D); bez pliku — bryła zastępcza
			if px != null:
				px.scale = Vector3(PX, PX, PX)
			else:
				px = _make_barrel() if kind == "barrel" else _make_crate()
			_world.add_child(px)
			(n as CanvasItem).modulate = Color(1, 1, 1, 0)
			_props[n.get_instance_id()] = [n, px]
	for id in _props.keys():
		var pr: Array = _props[id]
		var src = pr[0]
		var px: Node3D = pr[1]
		if not is_instance_valid(src) or (src as Node).is_queued_for_deletion():
			if is_instance_valid(px):
				px.queue_free()
			_props.erase(id)
			continue
		var s2 := src as Node2D
		px.visible = s2.visible
		px.position = Level3D.px_to_m(s2.global_position) + Vector3(0.0, 0.0, PROP_Z)      # na drodze gracza: przeszkoda, przez którą się skacze i na której się stoi
		px.rotation = Vector3(0.0, 0.0, -s2.global_rotation)

## Materiał PBR świata dla ruchomej bryły: kopia z triplanarem w przestrzeni obiektu (światowy „pływałby” po przesuwanej skrzyni).
func _prop_mat(name: String, per_m: float, tint := Color.WHITE) -> StandardMaterial3D:
	var m := Level3D.make_pbr(name, per_m, Color(0.4, 0.33, 0.26)).duplicate() as StandardMaterial3D
	m.uv1_world_triplanar = false
	m.albedo_color = m.albedo_color * tint
	return m

func _prop_part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	mi.layers = LAYER_WORLD
	parent.add_child(mi)
	return mi

## Skrzynia 14×14 px (stopy w początku układu, jak kształt kolizji): deski + rama z kantówek i dwie poprzeczki na froncie.
func _make_crate() -> Node3D:
	var root := Node3D.new()
	var s := 14.0 * PX
	var d := 0.95
	var planks := _prop_mat("plank", 0.9, Color(0.78, 0.66, 0.5))
	var frame := _prop_mat("post", 1.4, Color(0.55, 0.46, 0.36))
	var body := BoxMesh.new()
	body.size = Vector3(s * 0.94, s * 0.94, d * 0.94)
	_prop_part(root, body, Vector3(0.0, s * 0.5, 0.0), planks)
	var t := s * 0.11
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := BoxMesh.new()
			post.size = Vector3(t, s, t)
			_prop_part(root, post, Vector3(sx * (s - t) * 0.5, s * 0.5, sz * (d - t) * 0.5), frame)
	for sy in [0.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rail := BoxMesh.new()
			rail.size = Vector3(s - t * 2.0, t, t)
			_prop_part(root, rail, Vector3(0.0, t * 0.5 + sy * (s - t), sz * (d - t) * 0.5), frame)
		for sx in [-1.0, 1.0]:
			var side := BoxMesh.new()
			side.size = Vector3(t, t, d - t * 2.0)
			_prop_part(root, side, Vector3(sx * (s - t) * 0.5, t * 0.5 + sy * (s - t), 0.0), frame)
	var brace := BoxMesh.new()
	brace.size = Vector3(s * 1.22, t * 0.8, t * 0.5)
	var b := _prop_part(root, brace, Vector3(0.0, s * 0.5, d * 0.5 - t * 0.2), frame)
	b.rotation.z = PI * 0.25
	return root

## Beczka 10×15 px: stalowy płaszcz w wyblakłej czerwieni, trzy obręcze, wieko z kołnierzem.
func _make_barrel() -> Node3D:
	var root := Node3D.new()
	var r := 5.0 * PX
	var h := 15.0 * PX
	var shell := _prop_mat("metal", 1.2, Color(0.62, 0.16, 0.12))
	shell.metallic = 0.35
	var steel := _prop_mat("metal", 1.2, Color(0.42, 0.40, 0.38))
	var body := CylinderMesh.new()
	body.top_radius = r * 0.96
	body.bottom_radius = r * 0.96
	body.height = h
	body.radial_segments = 20
	_prop_part(root, body, Vector3(0.0, h * 0.5, 0.0), shell)
	for f in [0.04, 0.36, 0.66, 0.96]:
		var hoop := CylinderMesh.new()
		hoop.top_radius = r * 1.03
		hoop.bottom_radius = r * 1.03
		hoop.height = h * 0.045
		hoop.radial_segments = 20
		_prop_part(root, hoop, Vector3(0.0, h * f, 0.0), steel)
	return root

# ---------------------------------------------------------------- światła

func _scan_lights() -> void:
	var found: Array = []
	for gl in get_tree().get_nodes_in_group("game_lights"):
		if is_instance_valid(gl) and not (gl as Node).is_queued_for_deletion():
			found.append(gl)
	var cam_x := _cam_a.global_position.x / PX
	found.sort_custom(func(a, b): return absf(a.global_position.x - cam_x) < absf(b.global_position.x - cam_x))
	var keep := {}
	var n := 0
	for l in found:
		if n >= MAX_LIGHTS:
			break
		var li := l as Lights.GameLight
		if not li.enabled or li.energy <= 0.02 or not li.is_visible_in_tree():
			continue
		# aura gracza (ciepła poświata 6 m): w 3D słabsza niż zwykłe światło omni i bez cieni — ta sama plama widoczności wokół gracza co w 2D
		if li.get_parent() != null and li.get_parent().get("static_display") == true and _item_scene("lamp") != null:
			continue                                      # broń na stojaku: oświetla ją lampa nad stojakiem, nie kolorowa poświata pickupu
		var is_aura: bool = li.get_parent() is CharacterBody2D and not li.is_cone and (li.get_parent() as Node).is_in_group("players")
		var id := li.get_instance_id()
		keep[id] = true
		n += 1
		if not _lights.has(id):
			var is_cone := li.is_cone
			var l3: Light3D
			if is_cone:
				var sp := SpotLight3D.new()
				sp.light_volumetric_fog_energy = 6.0               # snop latarki widoczny we mgle
				sp.spot_angle = 24.0
				sp.spot_attenuation = 0.55
				l3 = sp
			else:
				l3 = OmniLight3D.new()
				l3.light_volumetric_fog_energy = 0.12 if is_aura else 0.7
			l3.light_color = li.color
			l3.layers = LAYER_WORLD | LAYER_ACTORS
			var l3a: Light3D = null
			if is_cone:
				l3.shadow_enabled = n <= SHADOW_LIGHTS            # reflektor oświetla i teren, i graczy
			else:
				# światło omni jest rozdzielone na dwie warstwy: świat (z cieniami dla kilku najbliższych) i gracze (bez cieni, osobne światło) —
				# cień światła omni w tej samej warstwie co modele graczy gubił je w warstwie z maską kamery (Compatibility)
				l3.light_cull_mask = LAYER_WORLD
				l3.shadow_enabled = n <= SHADOW_LIGHTS and not is_aura
				l3a = OmniLight3D.new()
				l3a.light_color = li.color
				l3a.light_cull_mask = LAYER_ACTORS
				l3a.shadow_enabled = false
				l3a.light_volumetric_fog_energy = 0.0
				l3a.layers = LAYER_WORLD | LAYER_ACTORS
				_world.add_child(l3a)
			_world.add_child(l3)
			_lights[id] = [li, l3, l3a, is_aura]
	for id in _lights.keys():
		if not keep.has(id):
			var pair: Array = _lights[id]
			for k in [1, 2]:
				if pair[k] != null and is_instance_valid(pair[k]):
					(pair[k] as Node).queue_free()
			_lights.erase(id)

func _sync_lights() -> void:
	for id in _lights.keys():
		var pair: Array = _lights[id]
		var li_v = pair[0]
		var l3: Light3D = pair[1]
		var l3a = pair[2]
		if not is_instance_valid(li_v) or not (li_v as Lights.GameLight).enabled:
			if is_instance_valid(l3):
				l3.visible = false
			if l3a != null and is_instance_valid(l3a):
				(l3a as Light3D).visible = false
			continue
		var li: Lights.GameLight = li_v
		l3.visible = true
		var rng_px := li.range_px
		var gp := li.global_position
		l3.light_color = li.color
		if l3a != null and is_instance_valid(l3a):
			var la := l3a as OmniLight3D
			la.visible = true
			la.light_color = li.color
			la.position = Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 1.0)
			la.light_energy = li.energy * (AURA_ACTOR if pair[3] else 4.0)
			la.omni_range = clampf(rng_px * PX, 3.0, 24.0)
		if l3 is SpotLight3D:
			var a := li.global_rotation
			var d := Vector3(cos(a), -sin(a), 0.0)
			# światło 2D latarki wisi 9 px nad stopami (środek sprite'a) — na modelu 1,8 m to wysokość kolan. W 3D latarka jest na broni:
			# snop wychodzi z wylotu lufy modelu (punkt `muzzle` z pliku broni, w świecie 3D). Bez modelu broni — z wysokości barku.
			var owner_p := li.get_parent() as Node2D
			var src := Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 0.6)
			if owner_p != null and owner_p.is_in_group("players"):
				var up_px := FLASH_UP_PX * (0.62 if bool(owner_p.get("crouching")) else 1.0)
				src = Level3D.px_to_m(owner_p.global_position + Vector2(0.0, -up_px)) + d * 0.35 + Vector3(0.0, 0.0, 0.3)
				var rig = _rigs.get(owner_p)
				var c3 = owner_p.get("c3d")
				if rig != null and c3 != null and is_instance_valid(c3) and rig["gun"] != null and is_instance_valid(rig["gun"]) and (rig["gun"] as Node3D).visible:
					src = (rig["gun"] as Node3D).global_transform * (c3._gun_info["muzzle"] as Vector3) + d * 0.05 + Vector3(0.0, 0.0, 0.5)      # lekko ku kamerze: snop oświetla też fronty przeszkód na drodze
			l3.position = src
			l3.basis = Basis.looking_at(d + Vector3(0.0, 0.0, -0.04), Vector3.UP)
			l3.light_energy = li.energy * 13.0
			(l3 as SpotLight3D).spot_range = clampf(rng_px * PX * 1.35, 8.0, 30.0)
		else:
			l3.position = Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 1.0)
			l3.light_energy = li.energy * (AURA_WORLD if pair[3] else 4.0)
			# aura gracza: mała plama pod nogami (AURA_RANGE_M), żeby nie potknąć się o własne stopy — drogę i wrogów pokazuje latarka
			(l3 as OmniLight3D).omni_range = AURA_RANGE_M if pair[3] else clampf(rng_px * PX, 3.0, 24.0)
