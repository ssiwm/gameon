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
const UiTheme := preload("res://scripts/ui_theme.gd")

const PX := Level3D.PX
const FOV := 40.0
const MAX_LIGHTS := 14
const SHADOW_LIGHTS := 5
const MIRROR_GROUPS := ["enemies", "boss", "nests", "roamers"]
const HIDE_NAMES := ["Back", "Solid", "Deco", "Decals", "TerrainHD", "TerrainHDBack", "Backdrop"]
const LAYER_WORLD := 1                     ## warstwa wizualna terenu, lasu, wrogów
const LAYER_ACTORS := 2                    ## warstwa wizualna graczy (modele 3D)
const ACTOR_AMBIENT := 0.09                ## światło otoczenia dla modeli graczy (tylko warstwa 2)
const ACTOR_LIGHT := 1.0                   ## mnożnik świateł pomocniczych graczy (kontra, wypełnienie, obrys)
const AURA_RANGE_M := 2.6                   ## zasięg aury gracza na terenie w widoku 3D [m] (w 2D: 6 m)
const PROP_Z := 0.0                         ## oś skrzyń i beczek: płaszczyzna gry (postacie stoją na nich i przez nie skaczą)
const FLASH_UP_PX := 15.5                   ## wysokość źródła latarki nad stopami gracza w widoku 3D [px świata] (bark / broń)
const AURA_WORLD := 1.0                    ## mnożnik energii aury gracza dla terenu (zwykłe światło omni: 4)
const AURA_ACTOR := 0.55                    ## mnożnik energii aury gracza dla modeli graczy
const FOG_BEGIN_M := 2.0                    ## mgła głębi: początek za płaszczyzną gry [m]
const FOG_END_M := 62.0                     ## mgła głębi: pełna gęstość [m za płaszczyzną gry]
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
var _rows: Array = []                    ## wiersze bieżącej mapy (rozbryzgi od kroków: rodzaj cieczy pod stopami)
var _splash := {}                        ## id węzła (gracz / wróg) → CPUParticles3D rozbryzgu
var _geo_t := 0.0
var _cam_a: Camera3D
var _cam_b: Camera3D
var _spr_bg: Sprite2D
var _spr_fg: Sprite2D
var _rigs := {}                          ## Node gracza → {actor, model, gun, root}
var _mirrors := {}                       ## id źródłowego AnimatedSprite2D → [źródło, AnimatedSprite3D]
var _enemies := {}                       ## id węzła wroga 2D → [węzeł, Enemy3D] (modele 3D wrogów; null w drugim polu = brak modelu)
var _estate := {}                        ## id węzła wroga 2D → stan do wykrywania zdarzeń (żyje, błysk trafienia, zapowiedź ataku)
var _lights := {}                        ## id PointLight2D → [PointLight2D, Light3D]
var _frames_cache := {}
var _proj := {}                          ## id pocisku 2D → [Node2D, Node3D proxy]
var _props := {}                         ## id obiektu fizycznego 2D (prop.gd) → [Node2D, Node3D bryła]
var _guns := {}                          ## id pickupu z bronią → [pickup, Node3D przegub modelu, sprite 2D, z]
var _beam_masks := {}                    ## id światła 2D latarki → [światło, maska obiektów, cienie] do przywrócenia przy wyłączeniu widoku
var _casings := {}                       ## id ciała łuski 2D → [RigidBody2D, MeshInstance3D, losowe odchylenie]
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
var _scan_t := 0.0
var _hidden: Array = []                  ## ukryte statyczne węzły 2D (przywracane przy wyłączeniu)
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
	_cam_a.cull_mask = LAYER_WORLD
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
			if _drawn[id][0].get("hide_stuck") != null:
				_drawn[id][0].set("hide_stuck", false)
	_drawn.clear()
	for id in _fires.keys():
		if is_instance_valid(_fires[id][0]):
			_fires[id][0].set("fx3d", false)
	_fires.clear()
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
	for id in _beam_masks.keys():
		var bm: Array = _beam_masks[id]
		if is_instance_valid(bm[0]):
			(bm[0] as PointLight2D).range_item_cull_mask = int(bm[1])
			(bm[0] as PointLight2D).shadow_enabled = bool(bm[2])
	_beam_masks.clear()
	for id in _guns.keys():
		var gv: Array = _guns[id]
		if is_instance_valid(gv[0]) and gv[0].get("_hd") != null and is_instance_valid(gv[0].get("_hd")):
			for c in (gv[0].get("_hd") as Node).get_children():
				if c is Sprite2D or c is ColorRect:
					(c as CanvasItem).self_modulate = Color.WHITE
			var ov = gv[0].get("_hd_over")
			if ov != null and is_instance_valid(ov):
				(ov as CanvasItem).visible = true
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
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for p in _rigs.keys():
		_release_rig(p)
	_rigs.clear()
	for id in _mirrors.keys():
		_unmirror(id)
	_mirrors.clear()
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
	_hide_static()
	_geo_t -= delta
	if _geo_t <= 0.0:
		_geo_t = 0.25
		_sync_geometry()
	_sync_rigs()
	_sync_enemies(delta)
	_sync_sprites()
	_sync_projectiles()
	_sync_props()
	_sync_items()
	_build_rails()
	_sync_drawn()
	_sync_guns()
	_sync_fires()
	_sync_weapon_fx()
	_sync_casings()
	_sync_burning()
	_sync_blood(delta)
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

## Statyczne warstwy 2D (kafle, tło, teren HD) są zastąpione geometrią 3D — chowamy je co klatkę (węzły HD powstają leniwie).
func _hide_static() -> void:
	for c in _level.get_children():
		var scr: Script = c.get_script()
		var is_backdrop: bool = scr != null and String(scr.resource_path).ends_with("backdrop.gd")     # tło parallax: węzeł bez nazwy
		if c is TileMapLayer or is_backdrop or HIDE_NAMES.has(String(c.name)):
			if c.visible:
				c.visible = false
				if not _hidden.has(c):
					_hidden.append(c)

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
	var amb: Color = _level.get("ambient") if _level.get("ambient") != null else Color(0.0245, 0.0266, 0.0406)
	var hub := String(_level.get("objective")) == "hub"
	Level3D.build_environment(_geo, amb, not hub, Settings.quality_idx)
	var we := _geo.get_node("Env") as WorldEnvironment
	var env_a := we.environment
	we.queue_free()                                       # środowisko przypisujemy kamerom (osobno dla tła i graczy)
	_cam_a.environment = env_a
	var env_b := env_a.duplicate() as Environment         # warstwa graczy: bez nieba i glow (przezroczyste tło), to samo światło otoczenia i mgła
	env_b.background_mode = Environment.BG_CLEAR_COLOR
	env_b.sky = null
	env_b.glow_enabled = false
	env_b.ssao_enabled = false
	env_b.ssil_enabled = false
	env_b.volumetric_fog_enabled = false
	# jasność postaci: osobne, łagodne światło otoczenia i słabsza mgła tylko dla warstwy graczy (modele leżą w płaszczyźnie gry, kilkanaście metrów od kamery)
	env_b.ambient_light_color = Color(0.50, 0.56, 0.70)
	env_b.ambient_light_energy = ACTOR_AMBIENT
	env_b.fog_enabled = false
	_cam_b.environment = env_b
	var span := _rail_span()
	var trench := {}
	if not span.is_empty():
		trench = {"row": int(float(span[2]) / 16.0), "c0": int(float(span[0]) / 16.0), "c1": int(float(span[1]) / 16.0)}
	Level3D.build_level(_geo, rows, trench)
	Level3D.build_liquids(_geo, rows)
	Level3D.build_liquid_props(_geo, rows)
	_rows = rows
	Level3D.build_decals(_geo, rows)
	Level3D.build_undergrowth(_geo, rows)
	_build_deco()
	Level3D.build_fog_volumes(_geo, rows, 0.02 if hub else 0.035)
	if not hub:
		Level3D.build_forest(_geo, rows)
		Level3D.build_ground_fog(_geo, rows)

# ---------------------------------------------------------------- gracze (modele 3D)

func _sync_rigs() -> void:
	var alive := {}
	for p in _players.get_children():
		if p.is_queued_for_deletion():
			continue
		alive[p] = true
		var c3 = p.get("c3d")
		if c3 == null or not is_instance_valid(c3) or not c3.ready_ok:
			_mirror_node(p, 0.1)                     # klasyczne sprite'y gracza (bez modelu 3D) jako billboardy
			continue
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
		actor.position = Level3D.px_to_m(p.global_position) + Vector3(0.0, -float(c3.sink_m), float(rig["lift"]))
		_splash_update(actor, p.global_position, absf(float(p.get("velocity").x)) if p.get("velocity") != null else 0.0, LAYER_ACTORS)
		actor.scale = Vector3(c3.px_flip, 1.0, 1.0)
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
		if is_instance_valid(p) and p.get("view") != null and is_instance_valid(p.get("view")):
			p.get("view").set("fx3d", false)
			var f2 = p.get("view").get("_flame")
			if f2 != null and is_instance_valid(f2):
				(f2 as CanvasItem).visible = true
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

func _sync_sprites() -> void:
	for g in MIRROR_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node2D and not n.is_queued_for_deletion() and not (_enemies.has(n.get_instance_id()) and _enemies[n.get_instance_id()][1] != null):
				_mirror_node(n, 0.25)
	for id in _mirrors.keys():
		var pair: Array = _mirrors[id]
		var src_v = pair[0]
		var dst: AnimatedSprite3D = pair[1]
		if not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion():
			if is_instance_valid(dst):
				dst.queue_free()
			_mirrors.erase(id)
			continue
		var src: AnimatedSprite2D = src_v
		var show: bool = src.is_visible_in_tree()
		dst.visible = show
		if not show:
			continue
		if dst.animation != src.animation and src.sprite_frames != null and src.sprite_frames.has_animation(src.animation):
			dst.animation = src.animation
		dst.frame = src.frame
		dst.flip_h = src.flip_h
		dst.flip_v = src.flip_v
		dst.offset = Vector2(src.offset.x, -src.offset.y)
		dst.modulate = src.modulate
		var z: float = float(src.get_meta("v3d_z", 0.25))
		dst.position = Level3D.px_to_m(src.global_position) + Vector3(0.0, 0.0, z)
		dst.rotation = Vector3(0.0, 0.0, -src.global_rotation)

## Rodzaj wroga, jeśli ma model 3D (`enemy3d.gd`), inaczej "".
func _enemy_kind(n: Node) -> String:
	var k = n.get("kind")
	if k == null:
		var scr: Script = n.get_script()
		var path := String(scr.resource_path) if scr != null else ""
		for pair in [["stalker.gd", "stalker"], ["boss.gd", "vein"], ["leech.gd", "leech"], ["nest.gd", "nest"]]:
			if path.ends_with(pair[0]):
				k = pair[1]
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
				_enemies[id] = [n, null]                  # bez modelu: zostają billboardy
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
		var alive_v = src.get("alive")
		var alive: bool = true if alive_v == null else bool(alive_v)
		if alive_v == null and String(e.get("kind")) == "vein":                 # boss nie ma `alive`: martwy = stan DEAD (2)
			var stv = src.get("state")
			if stv != null and int(stv) == 2:
				alive = false
		var wind_v = src.get("winding")
		var winding: bool = false if wind_v == null else bool(wind_v)
		if bool(st["alive"]) and not alive:
			e.call("die")
		elif not bool(st["alive"]) and alive:
			e.call("revive")
		var dying: bool = not alive and not bool(e.get("finished"))
		var flash: bool = body != null and body.modulate.r > 1.9 and body.modulate.g > 1.9
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
		e.position = pos + Vector3(0.0, 0.0, 0.3)
		var sp_v2 = float(st.get("vx", 0.0))
		if not ["cma", "nest", "vein", "leech"].has(String(e.get("kind"))):
			_splash_update(e, src.global_position, sp_v2, LAYER_WORLD)
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
		var sp_v = src.get("_sp")                          # stan specjalny wroga (Wołek: szarża, oszołomienie)
		e.call("pose", delta, anim, body.flip_h, md, float(body.frame) + body.frame_progress, nfr, lp, float(st["vy"]), 0 if sp_v == null else int(sp_v))

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

## Rozbryzg od kroków w błocie / oleju / wodzie: strumień kropel z poziomu stóp (węzeł `host` to model postaci lub wroga).
func _splash_update(host: Node3D, feet_px: Vector2, speed_px: float, layer: int) -> void:
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
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
		m.albedo_color = [Color(0.20, 0.14, 0.09, 0.9), Color(0.09, 0.09, 0.12, 0.95), Color(0.35, 0.55, 0.60, 0.85)][kind]
	sp.emitting = speed_px > 22.0

func _set_layer(root: Node, layer: int) -> void:
	for mi in root.find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = layer

## Tworzy (raz) proxy 3D dla każdego AnimatedSprite2D będącego dzieckiem węzła; oryginał robi się przezroczysty (`modulate` dalej czytamy z niego).
func _mirror_node(n: Node, z: float) -> void:
	var idx := 0
	for c in n.get_children():
		if not (c is AnimatedSprite2D):
			continue
		var s := c as AnimatedSprite2D
		var id := s.get_instance_id()
		idx += 1
		if _mirrors.has(id):
			continue
		if s.sprite_frames == null:
			continue
		if s.material != null and s.name == "Silhouette":
			s.self_modulate = Color(1, 1, 1, 0)           # słaba sylwetka addytywna nie ma odpowiednika w Sprite3D
			continue
		var d := AnimatedSprite3D.new()
		d.sprite_frames = _frames3d(s.sprite_frames)
		d.pixel_size = PX * absf(s.global_scale.x)
		d.centered = s.centered
		d.double_sided = true
		d.transparent = true
		d.shaded = s.material == null                      # materiał unshaded (warstwa świecąca) zostaje niezależny od świateł
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if s.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		d.render_priority = idx
		d.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		d.layers = LAYER_WORLD
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # billboard nie rzuca prostokątnego cienia
		s.set_meta("v3d_z", z + 0.01 * float(idx))
		s.self_modulate = Color(1, 1, 1, 0)
		_world.add_child(d)
		_mirrors[id] = [s, d]

## Arkusze HD są w 2D `CanvasTexture` (albedo + mapa normalnych dla świateł 2D), a materiały 3D traktują je jak białą teksturę — dla 3D bierzemy
## sam albedo (`diffuse_texture`) i budujemy równoległe SpriteFrames (z cache).
func _frames3d(sf: SpriteFrames) -> SpriteFrames:
	var key := sf.get_instance_id()
	if _frames_cache.has(key):
		return _frames_cache[key]
	var out := SpriteFrames.new()
	for a in out.get_animation_names():
		out.remove_animation(a)
	for an in sf.get_animation_names():
		out.add_animation(an)
		out.set_animation_loop(an, sf.get_animation_loop(an))
		out.set_animation_speed(an, sf.get_animation_speed(an))
		for i in sf.get_frame_count(an):
			out.add_frame(an, _tex3d(sf.get_frame_texture(an, i)), sf.get_frame_duration(an, i))
	_frames_cache[key] = out
	return out

func _tex3d(t: Texture2D) -> Texture2D:
	if t is CanvasTexture:
		return (t as CanvasTexture).diffuse_texture
	if t is AtlasTexture:
		var a := t as AtlasTexture
		if a.atlas is CanvasTexture:
			var n := AtlasTexture.new()
			n.atlas = (a.atlas as CanvasTexture).diffuse_texture
			n.region = a.region
			n.margin = a.margin
			n.filter_clip = a.filter_clip
			return n
	return t

func _unmirror(id: int) -> void:
	var pair: Array = _mirrors[id]
	var src = pair[0]
	if is_instance_valid(src):
		src.self_modulate = Color.WHITE
	if is_instance_valid(pair[1]):
		(pair[1] as Node).queue_free()

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
	if float(d.gravity) > 0.0:
		_sphere(root, 0.2, Vector3.ZERO, Color(0.3, 0.32, 0.2))
		_sphere(root, 0.09, Vector3(-0.12, 0.0, 0.0), Color(1.0, 0.7, 0.3))
	elif n.has_method("sticks_on_hit") and n.sticks_on_hit():
		_box(root, Vector3(maxf(tail, 0.5), 0.035, 0.035), Vector3(-maxf(tail, 0.5) * 0.5, 0.0, 0.0), Color(0.62, 0.5, 0.34))
		_box(root, Vector3(0.3, 0.06, 0.06), Vector3(0.22, 0.0, 0.0), Color(0.85, 0.85, 0.9))
	elif float(d.homing) > 0.0:
		_box(root, Vector3(tail, 0.12, 0.12), Vector3(-tail * 0.5, 0.0, 0.0), Color(col.r, col.g, col.b, 0.25))
		_box(root, Vector3(tail * 0.6, 0.06, 0.06), Vector3(-tail * 0.3, 0.0, 0.0), Color(col.r, col.g, col.b, 0.7))
		_box(root, Vector3(0.32, 0.16, 0.16), Vector3.ZERO, Color(0.9, 0.9, 0.92))
	else:
		_box(root, Vector3(maxf(tail, 0.1), 0.05, 0.05), Vector3(-tail * 0.5, 0.0, 0.0), Color(col.r, col.g, col.b, 0.22))
		_box(root, Vector3(maxf(tail * 0.5, 0.05), 0.07, 0.07), Vector3(-tail * 0.25, 0.0, 0.0), Color(col.r, col.g, col.b, 0.7))
		_box(root, Vector3(0.2, 0.06, 0.06), Vector3(0.04, 0.0, 0.0), Color(1.0, 0.97, 0.85))
	_world.add_child(root)
	n.self_modulate = Color(1, 1, 1, 0)
	_proj[n.get_instance_id()] = [n, root]

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
		px.position = Level3D.px_to_m(s2.global_position) + Vector3(0.0, 0.0, 0.3)
		px.rotation = Vector3(0.0, 0.0, -s2.global_rotation)

## Wołane z `Vfx.burst`: przenosi wybuch cząsteczek 2D do 3D (głębia: rozrzut także w z, cząsteczki jako billboardy); wersja 2D jest ukrywana.
func mirror_burst(fx: CPUParticles2D, pos: Vector2) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = fx.explosiveness
	p.amount = fx.amount
	p.lifetime = fx.lifetime
	p.direction = Vector3(fx.direction.x, -fx.direction.y, 0.0)
	p.spread = fx.spread
	p.initial_velocity_min = fx.initial_velocity_min * PX
	p.initial_velocity_max = fx.initial_velocity_max * PX
	p.gravity = Vector3(fx.gravity.x * PX, -fx.gravity.y * PX, 0.0)
	p.scale_amount_min = fx.scale_amount_min
	p.scale_amount_max = fx.scale_amount_max
	p.color = fx.color
	p.layers = LAYER_ACTORS
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(8.0, 8.0) * PX
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	if fx.texture != null:
		m.albedo_texture = fx.texture
	q.material = m
	p.mesh = q
	p.position = Level3D.px_to_m(pos) + Vector3(0.0, 0.0, 0.2)
	_world.add_child(p)
	p.emitting = true
	get_tree().create_timer(fx.lifetime + 0.6).timeout.connect(p.queue_free)
	fx.emitting = false
	fx.visible = false

# ---------------------------------------------------------------- dekoracje mapy (kamienie, kłody, płoty, kości)

const DECO_MODELS := {3: ["rock", 1.0], 4: ["bones", 0.7], 6: ["fence", 1.0], 7: ["logs", 1.0]}

## Dekoracje z listy poziomu (`level.gd: _deco_list` — te same miejsca co w 2D) jako modele 3D w `MultiMesh`: kamienie i kości rozrzucone w głąb
## bryły gruntu, płoty i kłody tuż za płaszczyzną gry. Trzciny (5) mają własne bryły przy cieczach (`Level3D.build_liquid_props`).
func _build_deco() -> void:
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
		var k := PX * float(DECO_MODELS[id][1]) * (0.85 + 0.4 * r2 if id == 3 else 1.0)
		var z := -0.9 if (id == 6 or id == 7) else lerpf(-1.9, -0.45, r1)
		var yaw := (PI if bool(d[2]) else 0.0) + (lerpf(-0.6, 0.6, r2) if id == 3 or id == 4 else lerpf(-0.08, 0.08, r2))
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k))
		if not groups.has(id):
			groups[id] = []
		(groups[id] as Array).append(Transform3D(b, Level3D.px_to_m(feet) + Vector3(0.0, 0.0, z)))
	for id in groups:
		var ps := _item_scene(String(DECO_MODELS[id][0]))
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
		var xfs: Array = groups[id]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, (xfs[i] as Transform3D) * base)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Deco_" + String(DECO_MODELS[id][0])
		mmi.multimesh = mm
		mmi.layers = LAYER_WORLD
		_geo.add_child(mmi)
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
		m.scale = Vector3(PX, PX, PX)
		m.position = Level3D.px_to_m((n as Node2D).global_position) + Vector3(0.0, 0.0, -1.2)
		_world.add_child(m)
		(n as CanvasItem).modulate = Color(1, 1, 1, 0)
		_drawn[n.get_instance_id()] = [n, m]
	for n in get_tree().get_nodes_in_group("exit_flares"):     # flara wyjścia: tuba wbita w ziemię jako model, płomień i iskry zostają w 2D
		if _drawn.has(n.get_instance_id()) or not (n is Node2D):
			continue
		var fm := _item_model("flare_stuck")
		if fm == null:
			continue
		fm.scale = Vector3(PX, PX, PX) * 0.85
		fm.position = Level3D.px_to_m((n as Node2D).global_position) + Vector3(0.0, -0.03, 0.05)
		_world.add_child(fm)
		n.set("hide_stuck", true)
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

const RACK_SCALE := 0.66                    ## stojak w 3D względem sprite'a 2D (48 × 36 px to prawie 4 m szerokości)
const RACK_UP_PX := 9.0                     ## dół stojaka nad podłogą [px świata]
const RACK_Z := -1.80                       ## oś stojaka: plecy deski przy ścianie tła
const RACK_SHELF_PX := 5.3                  ## góra półki w jednostkach modelu stojaka
const RACK_GUN_SCALE := 1.3                 ## broń na stojaku względem sprite'a 2D
const RACK_GUN_Z := -1.70                   ## broń leży na półce, tuż przed deską
const RACK_PLATE_Z := -1.50                 ## front półki: tabliczka z ceną

const RACK_LAMP_PX := 41.0                  ## spód lampy nad podłogą [px świata] (stojak kończy się ok. 31 px nad podłogą)

## Lampa wisząca nad stojakiem z bronią (kryjówka): emaliowany klosz z modelu `lamp`, przewód do stropu i ciepły reflektor w dół — stojak i broń
## oświetla widoczne źródło, a nie poświata „znikąd” (poświata pickupu na stojaku jest w 3D pomijana, zob. `_scan_lights`).
func _add_rack_lamp(rack_item: Node2D) -> void:
	var lamp := _item_model("lamp")
	if lamp == null:
		return
	var foot := rack_item.global_position
	var root := Node3D.new()
	root.name = "RackLamp"
	_geo.add_child(root)                                       # razem z geometrią mapy (znika przy zmianie mapy)
	root.position = Level3D.px_to_m(foot) + Vector3(0.0, RACK_LAMP_PX * PX, RACK_GUN_Z + 0.42)
	lamp.scale = Vector3(PX, PX, PX) * 1.25
	root.add_child(lamp)
	# przewód do stropu: pierwszy lity kafel nad lampą
	var c := int(foot.x / 16.0)
	var r := int(foot.y / 16.0) - 1
	var guard := 0
	while r > 0 and guard < 40 and not Level3D.is_solid_ch(Level3D._ch(_rows, c, r)):
		r -= 1
		guard += 1
	var top_m := -float(r + 1) * Level3D.T
	var lamp_top := root.position.y + 11.7 * PX * 1.25
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
	sp.light_energy = 7.0
	sp.spot_range = 5.5
	sp.spot_angle = 40.0
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
## (art/char3d/gun_<klucz>.glb). Łup na ziemi ma rozmiar sprite'a 2D. Na stojaku broń jest większa i leży na półce; zablokowana jest przyciemniona,
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
		var spr: Sprite2D = null
		for c in (hd as Node).get_children():
			if c is Sprite2D and spr == null:
				spr = c
			if c is Sprite2D or c is ColorRect:
				(c as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		if spr == null:
			continue
		var model := (load(path) as PackedScene).instantiate() as Node3D
		var box := AABB()
		var first := true
		for mn in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mn as MeshInstance3D
			mi.layers = LAYER_WORLD
			var bb := _local_xf(mi, model) * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					var sm := mi.mesh.surface_get_material(si) as StandardMaterial3D
					if sm != null:
						sm.metallic = 0.45
						sm.metallic_specular = 0.6
		var rect: Rect2 = n.get("_hd_gun_rect")
		var k := (rect.size.x / 16.0 * PX) / maxf(box.size.x, 0.001) * (RACK_GUN_SCALE if on_rack else 1.0)
		var pivot := Node3D.new()
		_world.add_child(pivot)
		pivot.add_child(model)
		model.scale = Vector3(k, k, k)
		model.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
		var lock: Node3D = null
		var plate: Node3D = null
		var label: Label3D = null
		if on_rack:
			model.rotation.x = deg_to_rad(-7.0)                   # oparta o deskę
			var over = n.get("_hd_over")
			if over != null and is_instance_valid(over):
				(over as CanvasItem).visible = false
			lock = _item_model("padlock")
			if lock != null:
				lock.scale = Vector3(PX, PX, PX) * 0.75
				lock.position = Vector3(0.0, box.size.y * k * 0.5 - 3.4 * PX, 0.10)
				lock.rotation.z = deg_to_rad(6.0)
				pivot.add_child(lock)
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
		if on_rack:
			_add_rack_lamp(n as Node2D)
		_guns[id] = [n, pivot, spr, RACK_GUN_Z if on_rack else -0.25, on_rack, model, lock, plate, label, -1]
	for id in _guns.keys():
		var g: Array = _guns[id]
		if not is_instance_valid(g[0]) or (g[0] as Node).is_queued_for_deletion() or not is_instance_valid(g[2]):
			if is_instance_valid(g[1]):
				(g[1] as Node).queue_free()
			_guns.erase(id)
			continue
		var sp := g[2] as Sprite2D
		var pv := g[1] as Node3D
		pv.visible = sp.is_visible_in_tree()
		if not bool(g[4]):
			pv.position = Level3D.px_to_m(sp.global_position) + Vector3(0.0, 0.0, float(g[3]))
			continue
		# stojak: broń na półce (podłoga = początek pickupu), stan blokady z warsztatu
		var floor_px := (g[0] as Node2D).global_position
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
			(g[7] as Node3D).visible = locked
			(g[8] as Label3D).text = ("%d" % price) if price > 0 else "SOON"

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
## `col` — barwa flary, `size` — szerokość płomienia [m]. Światło daje osobno światło 3D odwzorowane z `PointLight2D` flary.
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
		n.set("fx3d", true)
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
		_fires[n.get_instance_id()] = [n, f2, "exit", ring]
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
			if fr[3] != null and is_instance_valid(fr[3]):
				(fr[3] as Node).queue_free()
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
					if ch is Sprite2D and _items.has(ch.get_instance_id()) and bool(_items[ch.get_instance_id()][5]):
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
## Stan czytany z `weapon_view.gd` gracza (`_flash_t`, `w_state`, `w_firing`, `_beam_end`, `_flame`); rysunek 2D jest tam wyłączany (`fx3d`).
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
			wv.set("fx3d", true)
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
		var fl2d = wv.get("_flame")
		var flame3 := fx["flame"] as CPUParticles3D
		var burning: bool = fl2d != null and is_instance_valid(fl2d) and (fl2d as CPUParticles2D).emitting and not dead
		flame3.emitting = burning
		if fl2d != null and is_instance_valid(fl2d):
			(fl2d as CanvasItem).visible = false
		if burning:
			flame3.position = muzzle
			flame3.direction = aim
			flame3.spread = (fl2d as CPUParticles2D).spread
			flame3.initial_velocity_min = (fl2d as CPUParticles2D).initial_velocity_min * PX
			flame3.initial_velocity_max = (fl2d as CPUParticles2D).initial_velocity_max * PX
			flame3.lifetime = (fl2d as CPUParticles2D).lifetime

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

## Wołane z `Vfx.casing`: łuska jako mosiężny (śrutowa: czerwony) walec 3D podążający za ciałem fizycznym 2D; rysunek 2D jest chowany.
func mirror_casing(body: RigidBody2D, big: bool) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = (0.55 if big else 0.32) * PX
	cm.bottom_radius = cm.top_radius
	cm.height = (3.0 if big else 2.0) * PX
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
		mi.position = Level3D.px_to_m(b.global_position) + Vector3(0.0, 0.0, 0.35 + float(cs[2]) * 0.3)
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
				gm.roughness = 0.42                               # mokre, ale nie lustrzane
				gm.metallic_specular = 0.35
				gm.normal_scale = 0.45
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
const BLOOD_MAX := 70                       ## limit kałuż (najstarsze znikają)
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
		mi.scale = Vector3(float(b[2]), 1.0, float(b[2]) * 0.8)
		var sm := mi.material_override as ShaderMaterial
		sm.set_shader_parameter("wet", 1.0 - smoothstep(25.0, 70.0, float(b[3])))
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
const ITEM_BACK := ["shelf", "table", "chair", "locker", "cot", "stool", "board", "results_board", "workshop", "tools_wall", "rack", "range_sign", "range_target"]

## Każdy sprite z `ItemsHd.make` (grupa „items_hd”) dostaje w scenie 3D kartę z tym samym albedo i mapą normalnych: oświetlają ją światła 3D,
## rzuca cień na ścianę za sobą, łapie SSAO i mgłę — zamiast płaskiego rysunku 2D z osobnym oświetleniem nałożonego na obraz 3D.
## Meble stoją w głębi (przy ścianie tła), reszta tuż za płaszczyzną gry. Sprite 2D zostaje (logika, światła 2D), tylko jest przezroczysty.
func _sync_items() -> void:
	for n in get_tree().get_nodes_in_group("items_hd"):
		var sp := n as Sprite2D
		if sp == null or sp.is_queued_for_deletion() or _items.has(sp.get_instance_id()) or sp.texture == null:
			continue
		var par := sp.get_parent()
		if par != null and par.is_in_group("props"):
			continue                                  # skrzynie i beczki mają własne bryły (_sync_props)
		if sp.region_enabled:                         # wycinek sprite'a rysowany przed graczami (osłona pokładu drezyny) — sztuczka 2D, w 3D zbędna
			sp.self_modulate = Color(1, 1, 1, 0)
			_items[sp.get_instance_id()] = [sp, Node3D.new(), null, 0.0, [sp], true]
			_world.add_child(_items[sp.get_instance_id()][1])
			continue
		_make_item(sp)
	for id in _items.keys():
		var it: Array = _items[id]
		var src_v = it[0]
		var mi: Node3D = it[1]
		if not is_instance_valid(src_v) or (src_v as Node).is_queued_for_deletion():
			if is_instance_valid(mi):
				mi.queue_free()
			_items.erase(id)
			continue
		var sp := src_v as Sprite2D
		mi.visible = sp.is_visible_in_tree()
		if not mi.visible:
			continue
		var xf := sp.global_transform
		var sc := xf.get_scale()
		if bool(it[5]):                                        # model 3D: początek w stopach sprite'a, jednostka modelu = piksel świata
			var k := absf(sc.x) * ItemsHd.ppw(String(sp.get_meta("hd_name", ""))) * PX
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
		var ts := sp.texture.get_size()
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

func _make_item(sp: Sprite2D) -> void:
	var name := String(sp.get_meta("hd_name", ""))
	var ct := sp.texture as CanvasTexture
	var alb: Texture2D = ct.diffuse_texture if ct != null else sp.texture
	var model := _item_model(name, float(sp.get_meta("hd_dark", 0.0)) * 0.35)
	if model != null:                                          # prawdziwa bryła zamiast karty
		_world.add_child(model)
		var hid: Array = [sp]
		sp.self_modulate = Color(1, 1, 1, 0)
		var emits := false
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mm := (n as MeshInstance3D).mesh
			if mm != null and mm.get_surface_count() > 0 and mm.surface_get_material(0) is BaseMaterial3D and (mm.surface_get_material(0) as BaseMaterial3D).emission_enabled:
				emits = true
		for c in sp.get_children():
			# kopia „widoczna w ciemności” oraz nakładka diod / ekranu ze sprite'a: model ma własną emisję w swoich miejscach
			if c is Sprite2D and ((c as Sprite2D).texture == alb or emits):
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
	_collect_lights(_level, found)
	_collect_lights(_players, found)
	var cam_x := _cam_a.global_position.x / PX
	found.sort_custom(func(a, b): return absf(a.global_position.x - cam_x) < absf(b.global_position.x - cam_x))
	var keep := {}
	var n := 0
	for l in found:
		if n >= MAX_LIGHTS:
			break
		var li := l as PointLight2D
		if not li.enabled or li.energy <= 0.02 or li.texture == null or not li.is_visible_in_tree():
			continue
		# aura gracza (ciepła poświata 6 m): w 3D słabsza niż zwykłe światło omni i bez cieni — ta sama plama widoczności wokół gracza co w 2D
		if li.get_parent() != null and li.get_parent().get("static_display") == true and _item_scene("lamp") != null:
			continue                                      # broń na stojaku: oświetla ją lampa nad stojakiem, nie kolorowa poświata pickupu
		var is_aura: bool = li.get_parent() is CharacterBody2D and li.texture != Lights.cone() and (li.get_parent() as Node).is_in_group("players")
		var id := li.get_instance_id()
		keep[id] = true
		n += 1
		if not _lights.has(id):
			var is_cone := li.texture == Lights.cone()
			var l3: Light3D
			if is_cone:
				var sp := SpotLight3D.new()
				# latarka w widoku 3D to tylko ten reflektor: stożek 2D (inny kąt, zasięg i płaskie cienie) przestaje oświetlać warstwy 2D —
				# zostaje włączony jako źródło stanu (kierunek, energia, migotanie), ale z pustą maską obiektów
				_beam_masks[id] = [li, li.range_item_cull_mask, li.shadow_enabled]
				li.range_item_cull_mask = 0
				li.shadow_enabled = false
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

func _collect_lights(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is PointLight2D:
			out.append(c)
		if c.get_child_count() > 0 and not (c is TileMapLayer):
			_collect_lights(c, out)

func _sync_lights() -> void:
	for id in _lights.keys():
		var pair: Array = _lights[id]
		var li_v = pair[0]
		var l3: Light3D = pair[1]
		var l3a = pair[2]
		if not is_instance_valid(li_v) or not (li_v as PointLight2D).enabled:
			if is_instance_valid(l3):
				l3.visible = false
			if l3a != null and is_instance_valid(l3a):
				(l3a as Light3D).visible = false
			continue
		var li: PointLight2D = li_v
		l3.visible = true
		var rng_px := float(li.texture.get_width()) * absf(li.texture_scale) * 0.5
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
