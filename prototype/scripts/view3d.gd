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
## podglądu — poza liczy dalej `Char3D.update()`); wrogowie, bossowie i gniazda jako `AnimatedSprite3D` z arkuszy HD; wszystkie `PointLight2D` świata
## jako światła 3D (do kilkunastu najbliższych). Pozostałe warstwy dynamiczne 2D (pociski, cząsteczki, rekwizyty, pickupy, HUD) zostają bez zmian.
## Kamera 3D jest dopasowana do Camera2D: płaszczyzna z = 0 pokrywa się z kadrem 2D (zoom, wstrząsy, „Camera zoom”).

const Level3D := preload("res://scripts/level3d.gd")
const Lights := preload("res://scripts/lights.gd")

const PX := Level3D.PX
const FOV := 40.0
const MAX_LIGHTS := 14
const SHADOW_LIGHTS := 5
const MIRROR_GROUPS := ["enemies", "boss", "nests", "roamers"]
const HIDE_NAMES := ["Back", "Solid", "Deco", "TerrainHD", "TerrainHDBack", "Backdrop"]
const LAYER_WORLD := 1                     ## warstwa wizualna terenu, lasu, wrogów
const LAYER_ACTORS := 2                    ## warstwa wizualna graczy (modele 3D)
const ACTOR_AMBIENT := 0.55                ## światło otoczenia dla modeli graczy (tylko warstwa 2)
const ACTOR_LIGHT := 1.0                   ## mnożnik świateł pomocniczych graczy (kontra, wypełnienie, obrys)
const Z_BG := -60
const Z_FG := 1

var _level: Node2D
var _players: Node2D
var _vp_bg: SubViewport
var _vp_fg: SubViewport
var _world: Node3D
var _geo: Node3D
var _geo_key := ""
var _geo_t := 0.0
var _cam_a: Camera3D
var _cam_b: Camera3D
var _spr_bg: Sprite2D
var _spr_fg: Sprite2D
var _rigs := {}                          ## Node gracza → {actor, model, gun, root}
var _mirrors := {}                       ## id źródłowego AnimatedSprite2D → [źródło, AnimatedSprite3D]
var _lights := {}                        ## id PointLight2D → [PointLight2D, Light3D]
var _frames_cache := {}
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
	# światło tylko dla graczy (warstwa 2): miękka kontra, wypełnienie i obrys jak w podglądzie postaci — sylwetka czytelna także w ciemności
	for spec in [[Vector3(-0.35, -0.6, -0.7), Color(0.9, 0.88, 0.8), 1.3], [Vector3(0.2, -0.3, 0.9), Color(0.7, 0.8, 1.0), 1.0], [Vector3(0.7, -0.2, -0.4), Color(0.6, 0.7, 1.0), 0.5]]:
		var dl := DirectionalLight3D.new()
		dl.basis = Basis.looking_at(spec[0], Vector3.UP)
		dl.light_color = spec[1]
		dl.light_energy = float(spec[2]) * ACTOR_LIGHT
		dl.light_cull_mask = LAYER_ACTORS
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
	_spr_fg.z_index = Z_FG
	_spr_fg.texture = _vp_fg.get_texture()
	_spr_fg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_spr_fg.material = Lights.unshaded()                      # bez mnożenia przez CanvasModulate „ciemności” 2D (3D ma własne światło)
	add_child(_spr_fg)

# ---------------------------------------------------------------- cykl życia

func release() -> void:
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
	_sync_camera()
	_hide_static()
	_geo_t -= delta
	if _geo_t <= 0.0:
		_geo_t = 0.25
		_sync_geometry()
	_sync_rigs()
	_sync_sprites()
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
	var xf := Transform3D(Basis.IDENTITY, Vector3(ctr.x * PX, -ctr.y * PX, dist))
	_cam_a.global_transform = xf
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
	var key := "%s:%d" % [String(_level.get("map_id")), str(rows).hash()]
	if key == _geo_key:
		return
	_geo_key = key
	for ch in _geo.get_children():
		ch.queue_free()
	var amb: Color = _level.get("ambient") if _level.get("ambient") != null else Color(0.0245, 0.0266, 0.0406)
	var hub := String(_level.get("objective")) == "hub"
	Level3D.build_environment(_geo, amb, not hub)
	var we := _geo.get_node("Env") as WorldEnvironment
	var env_a := we.environment
	we.queue_free()                                       # środowisko przypisujemy kamerom (osobno dla tła i graczy)
	_cam_a.environment = env_a
	var env_b := env_a.duplicate() as Environment         # warstwa graczy: bez nieba i glow (przezroczyste tło), to samo światło otoczenia i mgła
	env_b.background_mode = Environment.BG_CLEAR_COLOR
	env_b.sky = null
	env_b.glow_enabled = false
	# jasność postaci: osobne, łagodne światło otoczenia i słabsza mgła tylko dla warstwy graczy (modele leżą w płaszczyźnie gry, kilkanaście metrów od kamery)
	env_b.ambient_light_color = Color(0.55, 0.60, 0.78)
	env_b.ambient_light_energy = ACTOR_AMBIENT
	env_b.fog_density = env_a.fog_density * 0.35
	_cam_b.environment = env_b
	Level3D.build_level(_geo, rows)
	if not hub:
		Level3D.build_forest(_geo, rows)

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
		actor.position = Level3D.px_to_m(p.global_position)
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

func _release_rig(p: Node) -> void:
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
			if n is Node2D and not n.is_queued_for_deletion():
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
		if li.get_parent() is CharacterBody2D and li.texture != Lights.cone() and (li.get_parent() as Node).is_in_group("players"):
			continue                                      # aura gracza: światło 2D pod sprite'a; w 3D przepalałaby model
		var id := li.get_instance_id()
		keep[id] = true
		n += 1
		if not _lights.has(id):
			var is_cone := li.texture == Lights.cone()
			var l3: Light3D
			if is_cone:
				var sp := SpotLight3D.new()
				sp.spot_angle = 26.0
				sp.spot_attenuation = 0.7
				l3 = sp
			else:
				l3 = OmniLight3D.new()
			l3.light_color = li.color
			l3.shadow_enabled = is_cone and n <= SHADOW_LIGHTS      # cienie tylko dla reflektorów: cienie świateł omni gubiły modele graczy w warstwie z maską kamery (Compatibility)
			_world.add_child(l3)
			_lights[id] = [li, l3]
	for id in _lights.keys():
		if not keep.has(id):
			var pair: Array = _lights[id]
			if is_instance_valid(pair[1]):
				(pair[1] as Node).queue_free()
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
		if not is_instance_valid(li_v) or not (li_v as PointLight2D).enabled:
			if is_instance_valid(l3):
				l3.visible = false
			continue
		var li: PointLight2D = li_v
		l3.visible = true
		var rng_px := float(li.texture.get_width()) * absf(li.texture_scale) * 0.5
		var gp := li.global_position
		l3.light_color = li.color
		if l3 is SpotLight3D:
			var a := li.global_rotation
			var d := Vector3(cos(a), -sin(a), 0.0)
			l3.position = Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 0.6)
			l3.basis = Basis.looking_at(d + Vector3(0.0, 0.0, -0.04), Vector3.UP)
			l3.light_energy = li.energy * 8.0
			(l3 as SpotLight3D).spot_range = clampf(rng_px * PX, 6.0, 26.0)
		else:
			l3.position = Level3D.px_to_m(gp) + Vector3(0.0, 0.0, 1.0)
			l3.light_energy = li.energy * 4.0
			(l3 as OmniLight3D).omni_range = clampf(rng_px * PX, 3.0, 24.0)
