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
const HIDE_NAMES := ["Back", "Solid", "Deco", "TerrainHD", "TerrainHDBack", "Backdrop"]
const LAYER_WORLD := 1                     ## warstwa wizualna terenu, lasu, wrogów
const LAYER_ACTORS := 2                    ## warstwa wizualna graczy (modele 3D)
const ACTOR_AMBIENT := 0.16                ## światło otoczenia dla modeli graczy (tylko warstwa 2)
const ACTOR_LIGHT := 1.0                   ## mnożnik świateł pomocniczych graczy (kontra, wypełnienie, obrys)
const FLASH_UP_PX := 15.5                   ## wysokość źródła latarki nad stopami gracza w widoku 3D [px świata] (bark / broń)
const AURA_WORLD := 3.2                    ## mnożnik energii aury gracza dla terenu (zwykłe światło omni: 4)
const AURA_ACTOR := 0.8                    ## mnożnik energii aury gracza dla modeli graczy
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
	_drawn.clear()
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
		_drawn[n.get_instance_id()] = [n, mi]
	for id in _drawn.keys():
		var pr: Array = _drawn[id]
		if not is_instance_valid(pr[0]) or (pr[0] as Node).is_queued_for_deletion():
			if is_instance_valid(pr[1]):
				(pr[1] as Node).queue_free()
			_drawn.erase(id)
		elif is_instance_valid(pr[1]):
			(pr[1] as Node3D).visible = (pr[0] as CanvasItem).is_visible_in_tree()

# ---------------------------------------------------------------- broń na ziemi i na stojakach

const GUN_DIR := "res://art/char3d/"

const RACK_SCALE := 0.66                    ## stojak w 3D względem sprite'a 2D (48 × 36 px to prawie 4 m szerokości)
const RACK_UP_PX := 9.0                     ## dół stojaka nad podłogą [px świata]
const RACK_Z := -1.80                       ## oś stojaka: plecy deski przy ścianie tła
const RACK_SHELF_PX := 5.3                  ## góra półki w jednostkach modelu stojaka
const RACK_GUN_SCALE := 1.3                 ## broń na stojaku względem sprite'a 2D
const RACK_GUN_Z := -1.70                   ## broń leży na półce, tuż przed deską
const RACK_PLATE_Z := -1.50                 ## front półki: tabliczka z ceną

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
		px.position = Level3D.px_to_m(s2.global_position) + Vector3(0.0, 0.0, -0.7)      # front bryły za płaszczyzną gry: latarka (z = +0,6) nie świeci po nim pod kątem ślizgowym
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
		var is_aura: bool = li.get_parent() is CharacterBody2D and li.texture != Lights.cone() and (li.get_parent() as Node).is_in_group("players")
		var id := li.get_instance_id()
		keep[id] = true
		n += 1
		if not _lights.has(id):
			var is_cone := li.texture == Lights.cone()
			var l3: Light3D
			if is_cone:
				var sp := SpotLight3D.new()
				sp.light_volumetric_fog_energy = 6.0               # snop latarki widoczny we mgle
				sp.spot_angle = 26.0
				sp.spot_attenuation = 0.7
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
					src = (rig["gun"] as Node3D).global_transform * (c3._gun_info["muzzle"] as Vector3) + d * 0.05
			l3.position = src
			l3.basis = Basis.looking_at(d + Vector3(0.0, 0.0, -0.04), Vector3.UP)
			l3.light_energy = li.energy * 8.0
			(l3 as SpotLight3D).spot_range = clampf(rng_px * PX, 6.0, 26.0)
		else:
			l3.position = Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 1.0)
			l3.light_energy = li.energy * (AURA_WORLD if pair[3] else 4.0)
			(l3 as OmniLight3D).omni_range = clampf(rng_px * PX, 3.0, 24.0)
