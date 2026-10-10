extends Node2D
## Postać 3D renderowana w czasie rzeczywistym do tekstury (`--char3d`, patrz CHAR3D_SPIKE.md).
##
## Model z rigiem Mixamo (art/char3d/<płeć>_<strój>.glb, tools/prep_char3d.py) żyje w małym SubViewport z kamerą
## ortogonalną patrzącą z boku; wynik wyświetla zwykły Sprite2D (obrys robi shader, oświetlenie 2D robi gra).
## Pozy to czysty kod: nogi i ręce rozwiązuje dwukostkowe IK, więc broń (art/char3d/gun_<klucz>.glb, chwyty w .json)
## leży w dłoniach przy KAŻDYM kącie celowania, animacji, broni i wyglądzie. Przeładowanie, dobycie i cios to ruch broni
## (ten sam co w weapon_view) plus lewa dłoń sięgająca do magazynka. Czyta tylko stan zreplikowany w graczu — nic tu
## nie rozstrzyga gameplayu, więc każdy peer widzi to samo.
##
## Układ: model patrzy w +X, kamera stoi na +Z (bliższa jest prawa strona postaci), stopy w y = 0.
## Odbicie (patrzenie w lewo) to flip_h na sprite'ie — jak w arkuszach 2D.

const CHAR_H_M := 1.8                       ## wysokość postaci odniesienia (m)
const CHAR_H_WP := 22.0                     ## ... w pikselach świata
const WP_PER_M := CHAR_H_WP / CHAR_H_M
## Jakość renderu (pokrętła kosztu na słabszym GPU): pikseli renderu na piksel świata (4 = jak arkusze HD postaci) i MSAA.
## Niska jakość: --char3d-lq (SS 2, bez MSAA) — ok. 3× mniej pikseli do wyrenderowania.
static var ss := 4
static var msaa := true
## Mapa normalnych (drugi przebieg renderu): światła 2D (latarka, flara) dają relief jak na sprite'ach HD. Kosztuje drugi render siatki; wyłączane w niskiej jakości.
static var normals := true
const FRAME_WP := Vector2(44.0, 44.0)       ## ramka w pikselach świata (zapas na broń podniesioną i wyciągniętą)
const CAM_Y := 1.25                         ## wysokość środka ramki (m)
const PRE := "mixamorig_"
const DIR := "res://art/char3d/"
const DEFAULT_CHAR := "male_scav"
const DEFAULT_GUN := "m83"

const OUTLINE_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.078, 0.055, 0.094, 1.0);
uniform float width = 2.0;
uniform bool flip_n = false;          // sprite odbity poziomo (flip_h): składowa X normalnych odwrócona, żeby światło padało z właściwej strony
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = 0.0;
	for (int r = 1; r <= 2; r++) {
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			a = max(a, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * (float(r) * 0.5)).a);
		}
	}
	a = smoothstep(0.1, 0.7, a);
	COLOR = vec4(mix(outline_color.rgb, c.rgb / max(c.a, 0.001), c.a), max(a, c.a));
	vec3 n = texture(NORMAL_TEXTURE, UV).rgb;
	if (flip_n) {
		n.x = 1.0 - n.x;
	}
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n, c.a);
}
"""

var _vp: SubViewport
var _vpn: SubViewport                        ## drugi przebieg: normalne widokowe (R=+X, G=+Y w górę, B=do kamery, ×0,5+0,5) tego samego świata 3D
var _camn: Camera3D
var _gun_n: Node3D
var _normal_mat: ShaderMaterial
var _cam: Camera3D
var _sprite: Sprite2D
var _notifier: VisibleOnScreenNotifier2D
var _root3d: Node3D
var _char_node: Node
var _char_name := ""
var _sk: Skeleton3D
var _gun: Node3D
var _gun_key := ""
var _hands := 2
var _gun_len := 1.2
var _gun_info := {"rear": Vector3.ZERO, "fore": Vector3(0.4, 0.03, 0.0), "muzzle": Vector3(0.9, 0.08, 0.0)}   ## w układzie Godota (x, y w górę, z do kamery)
var _b := {}                                 ## nazwa kości → indeks
var _leg_len := {}                           ## długości [udo, goleń] (m)
var _arm_len := {}                           ## długości [ramię, przedramię] (m)
var _origin_x := 0.163                       ## oś ciała (m) — biodra w pozie spoczynkowej
var _ankle_y := 0.077                        ## wysokość kostki na podłożu (m)
var _time := 0.0
var _phase := 0.0
var _on_screen := true

## Wejście od widoku broni (weapon_view.gd), ustawiane co klatkę przed update().
var gun_extra := 0.0                         ## rad — dodatkowy obrót lufy w dół (odrzut, dobycie, przeładowanie, zamach), względem kierunku patrzenia
var gun_kick_px := 0.0                       ## px — cofnięcie broni wzdłuż lufy (odrzut)
var reload_t := -1.0                         ## 0..1 trwającego przeładowania, <0 = brak (lewa dłoń sięga do magazynka)
var swing_t := -1.0                          ## 0..1 trwającego ciosu, <0 = brak
var throw_t := -1.0                          ## 0..1 trwającego rzutu (flara, granat), <0 = brak: prawa ręka zamachem nad głową, broń schowana

## Wyniki ostatniej klatki, w pikselach świata względem stóp (z uwzględnieniem odbicia) — dla efektów.
var muzzle_px := Vector2.ZERO
var px_flip := 1.0                           ## +1 postać patrzy w prawo, −1 w lewo (znak, z jakim policzono muzzle_px / grip_px)
var grip_px := Vector2.ZERO
var ready_ok := false

## Plik modelu dla kodu wyglądu: np. "male_scav", "female_hazmat" (Look.gender_id + Look.outfit_id; „scavenger” → „scav”).
static func char_name_for(gender: String, outfit: String) -> String:
	return "%s_%s" % [gender, "scav" if outfit == "scavenger" else outfit]

## Niska jakość (--char3d-lq lub słaby sprzęt): mniejsza rozdzielczość renderu, bez MSAA.
static func set_low_quality(on: bool) -> void:
	ss = 2 if on else 4
	msaa = not on
	normals = not on
	ss_auto = not on

## Czy `ss` ma nadążać za zoomem kamery i rozmiarem okna (wyłącza je tryb niskiej jakości).
static var ss_auto := true

## Ile pikseli renderu na piksel świata daje ostry obraz przy danym zoomie kamery i wysokości okna (baza 640×360).
static func ss_for_view(zoom: float, win_h: float) -> int:
	return clampi(int(ceil(zoom * win_h / 360.0)), 3, 8)

static func available() -> bool:
	return DisplayServer.get_name() != "headless" and ResourceLoader.exists(DIR + DEFAULT_CHAR + ".glb")

var _ss_now := 0

## Dopasowuje rozdzielczość renderu do widoku: zoom kamery × rozmiar okna. Woła gracz przy starcie, zmianie zoomu i rozmiaru okna.
func apply_view(zoom: float, win_h: float) -> void:
	if not ss_auto or _vp == null:
		return
	var n := ss_for_view(zoom, win_h)
	if n == _ss_now:
		return
	_ss_now = n
	ss = n                                                # nowe postacie startują od razu w dobrej jakości
	_vp.size = Vector2i(int(FRAME_WP.x) * n, int(FRAME_WP.y) * n)
	if _vpn != null:
		_vpn.size = _vp.size
	_sprite.scale = Vector2.ONE / float(n)
	(_sprite.material as ShaderMaterial).set_shader_parameter("width", 0.5 * n)

func setup(char_name := DEFAULT_CHAR, gun_key := DEFAULT_GUN) -> bool:
	_ss_now = ss
	_vp = SubViewport.new()
	_vp.name = "Vp"
	_vp.size = Vector2i(int(FRAME_WP.x) * ss, int(FRAME_WP.y) * ss)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if msaa else Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = FRAME_WP.y / WP_PER_M
	_cam.near = 0.5
	_cam.far = 20.0
	_cam.cull_mask = 1
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	_cam.environment = env
	_root3d.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.96, 0.9)
	_root3d.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.7, -0.2, -0.4), Vector3.UP)
	fill.light_energy = 0.28
	fill.light_color = Color(0.6, 0.7, 1.0)
	_root3d.add_child(fill)

	_sprite = Sprite2D.new()
	_sprite.name = "Body3D"
	if normals:
		_build_normal_pass()
		var ct := CanvasTexture.new()
		ct.diffuse_texture = _vp.get_texture()
		ct.normal_texture = _vpn.get_texture()
		_sprite.texture = ct
	else:
		_sprite.texture = _vp.get_texture()
	_sprite.scale = Vector2.ONE / float(ss)
	_sprite.position = Vector2(0.0, -CAM_Y * WP_PER_M)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("width", 0.5 * ss)           # obrys 0,5 piksela świata niezależnie od ss
	_sprite.material = mat
	add_child(_sprite)
	# poza ekranem nie renderujemy viewportu (koszt rośnie z liczbą postaci, a zdalni gracze bywają daleko)
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-FRAME_WP.x * 0.5, -CAM_Y * WP_PER_M - FRAME_WP.y * 0.5, FRAME_WP.x, FRAME_WP.y)
	_notifier.screen_entered.connect(func(): _set_on_screen(true))
	_notifier.screen_exited.connect(func(): _set_on_screen(false))
	add_child(_notifier)

	if not set_look(char_name):
		return false
	set_gun(gun_key)
	ready_ok = true
	return true

func _set_on_screen(v: bool) -> void:
	_on_screen = v
	var mode := SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = mode
	if _vpn != null:
		_vpn.render_target_update_mode = mode

## Drugi SubViewport z tym samym światem 3D i kamerą na warstwie 2: widzi tylko kopie siatek z materiałem wypisującym normalne.
## Kopie współdzielą szkielet z oryginałem, więc poza liczymy raz.
func _build_normal_pass() -> void:
	_vpn = SubViewport.new()
	_vpn.name = "VpN"
	_vpn.size = _vp.size
	_vpn.transparent_bg = true
	_vpn.msaa_3d = _vp.msaa_3d
	_vpn.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vpn)
	_vpn.world_3d = _vp.find_world_3d()
	_camn = Camera3D.new()
	_camn.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camn.keep_aspect = Camera3D.KEEP_HEIGHT
	_camn.size = _cam.size
	_camn.near = _cam.near
	_camn.far = _cam.far
	_camn.cull_mask = 2
	_vpn.add_child(_camn)
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D nm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_nm = false;
void fragment() {
	vec3 n = NORMAL;
	if (has_nm) {
		// mapa normalnych z modelu (tangent space) → normalne widokowe: relief widzą światła 2D (latarka, flara)
		vec3 t = texture(nm, UV).xyz * 2.0 - 1.0;
		n = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	}
	ALBEDO = n * 0.5 + vec3(0.5);
}
"
	_normal_mat = ShaderMaterial.new()
	_normal_mat.shader = sh

## Materiał normalnych dla siatki: wspólny, a gdy model ma mapę normalnych — kopia ze wskazaną teksturą.
func _normal_material_for(mi: MeshInstance3D) -> Material:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return _normal_mat
	var src := mi.mesh.surface_get_material(0)
	if src is BaseMaterial3D and (src as BaseMaterial3D).normal_texture != null:
		var m := _normal_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("nm", (src as BaseMaterial3D).normal_texture)
		m.set_shader_parameter("has_nm", true)
		return m
	return _normal_mat

## Materiały modelu pod światła gry: bez metaliczności (bez sondy odbić metal byłby czarny), reszta (kolor, normalne, roughness, AO) z modelu.
func _prepare_materials(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var d := m.duplicate() as StandardMaterial3D
				d.metallic = 0.0
				d.metallic_texture = null
				mi.set_surface_override_material(i, d)

## Kopie siatek sceny na warstwie 2 z materiałem normalnych. skinned: kopie dzielą szkielet z oryginałem (są jego dziećmi).
func _normal_clones(root: Node, skinned: bool) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.layers = 2
		c.material_override = _normal_material_for(mi)
		c.transform = mi.transform
		mi.add_sibling(c)
		if skinned and mi.skin != null:
			c.skin = mi.skin
			c.skeleton = c.get_path_to(mi.get_parent())


## Wymiana modelu postaci (wygląd z warsztatu, replikowany `player.look`). Zwraca false, gdy brak pliku.
func set_look(char_name: String) -> bool:
	if char_name == _char_name and _sk != null:
		return true
	var path := DIR + char_name + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var scene: Node = (load(path) as PackedScene).instantiate()
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	if sk == null:
		scene.free()
		return false
	if _char_node != null:
		_char_node.queue_free()
	_char_node = scene
	_char_name = char_name
	_sk = sk
	_prepare_materials(scene)
	_root3d.add_child(scene)
	_b.clear()
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
			"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		_b[n] = _sk.find_bone(PRE + n)
	for side in ["Left", "Right"]:
		_leg_len[side] = [_rest_dist(side + "UpLeg", side + "Leg"), _rest_dist(side + "Leg", side + "Foot")]
		_arm_len[side] = [_rest_dist(side + "Arm", side + "ForeArm"), _rest_dist(side + "ForeArm", side + "Hand")]
	_origin_x = _sk.get_bone_global_rest(_b["Hips"]).origin.x
	_ankle_y = _sk.get_bone_global_rest(_b["RightFoot"]).origin.y
	_cam.position = Vector3(_origin_x, CAM_Y, 6.0)
	if _camn != null:
		_camn.position = _cam.position
		_normal_clones(scene, true)
	return true

## Wymiana broni (klucz z weapon_def: m83, p64, maczeta…). Brak modelu → karabin M-83.
func set_gun(key: String) -> void:
	if key == _gun_key and _gun != null:
		return
	var path := DIR + "gun_%s.glb" % key
	if not ResourceLoader.exists(path):
		key = DEFAULT_GUN
		path = DIR + "gun_%s.glb" % key
		if key == _gun_key and _gun != null:
			return
	if _gun != null:
		_gun.queue_free()
	if _gun_n != null:
		_gun_n.queue_free()
		_gun_n = null
	_gun = (load(path) as PackedScene).instantiate()
	_root3d.add_child(_gun)
	if _camn != null:                                        # kopia broni na warstwie 2 (osobny egzemplarz sceny, ta sama transformacja)
		_gun_n = (load(path) as PackedScene).instantiate()
		_root3d.add_child(_gun_n)
		for mi in _gun_n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 2
			(mi as MeshInstance3D).material_override = _normal_mat
	_gun_key = key
	_load_gun_info(path.get_basename() + ".json")

func _load_gun_info(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for k in ["rear", "fore", "muzzle"]:
		var a: Array = d[k]
		_gun_info[k] = Vector3(float(a[0]), float(a[2]), -float(a[1]))      # Blender (x, y, z) → Godot (x, z, −y)
	_hands = int(d.get("hands", 2))
	_gun_len = float(d.get("length", 1.2))

func _rest_dist(a: String, b: String) -> float:
	return _sk.get_bone_global_rest(_sk.find_bone(PRE + a)).origin.distance_to(_sk.get_bone_global_rest(_sk.find_bone(PRE + b)).origin)

# ---------------------------------------------------------------- narzędzia kostne

func _gp(i: int) -> Transform3D:
	return _sk.get_bone_global_pose(i)

func _set_global_basis(i: int, gb: Basis) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_rotation(i, (pb.inverse() * gb).orthonormalized().get_rotation_quaternion())

## Przesuwa kość o wektor w przestrzeni szkieletu (świata modelu). Osie lokalne kości Mixamo są obrócone (w biodrach „góra" to lokalne Z),
## więc przesunięcie w pozie trzeba przeliczyć przez bazę rodzica — samo dodanie wektora do lokalnej pozycji ruszało biodra w bok.
func _move_global(i: int, delta: Vector3) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_position(i, _sk.get_bone_rest(i).origin + pb.inverse() * delta)

## Obraca kość (i całe jej poddrzewo) wokół jej własnego początku o kąt wokół osi świata.
func _rot_world(i: int, axis: Vector3, ang: float) -> void:
	_set_global_basis(i, Basis(axis, ang) * _gp(i).basis)

## Kość i kieruje się na punkt target (jej dziecko child leży na osi kości).
func _point_bone(i: int, child: int, target: Vector3) -> void:
	var g := _gp(i)
	var from := (_gp(child).origin - g.origin).normalized()
	var to := (target - g.origin).normalized()
	if from.dot(to) > 0.99999:
		return
	_set_global_basis(i, Basis(Quaternion(from, to)) * g.basis)

## Dwukostkowe IK: staw środkowy tak, by koniec sięgał celu; pole = kierunek wygięcia (łokieć / kolano).
func _two_bone(a: int, m: int, e: int, la: float, lb: float, target: Vector3, pole: Vector3) -> void:
	var s := _gp(a).origin
	var d := target - s
	var dist := clampf(d.length(), absf(la - lb) + 0.001, (la + lb) * 0.999)
	var dn := d.normalized()
	var x := (la * la - lb * lb + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pv := pole - dn * pole.dot(dn)
	pv = pv.normalized() if pv.length() > 0.0001 else Vector3.UP
	var mid := s + dn * x + pv * h
	_point_bone(a, m, mid)
	_point_bone(m, e, s + dn * dist)

# ---------------------------------------------------------------- klatka

## anim: idle | run | jump | fall | crouch | crouch_walk | down. aim: kierunek celowania na ekranie (y w dół).
## speed: |prędkość pozioma| w px/s (tempo kroku). armed=false chowa broń (leżenie).
func update(delta: float, anim: String, facing: float, aim: Vector2, speed := 0.0, armed := true, tint := Color.WHITE) -> void:
	if not ready_ok:
		return
	_time += delta
	_sprite.flip_h = facing < 0.0
	px_flip = -1.0 if _sprite.flip_h else 1.0
	(_sprite.material as ShaderMaterial).set_shader_parameter("flip_n", _sprite.flip_h)
	_sprite.modulate = tint
	if not _on_screen:
		return                                                    # poza ekranem nic nie rysujemy (viewport wyłączony), pozę nadrobi pierwsza klatka po wejściu
	_sk.reset_bone_poses()
	var ax := absf(aim.x)
	var theta := atan2(-aim.y, maxf(ax, 0.0001))               # kąt w górę od poziomu; ax≥0 (lustro załatwia flip_h)
	if ax < 0.05:
		theta = PI * 0.5 * signf(-aim.y)
	theta = clampf(theta, deg_to_rad(-80.0), deg_to_rad(85.0))
	_pose_body(delta, anim, speed, theta)
	var holding := armed and anim != "down" and throw_t < 0.0
	if throw_t >= 0.0 and armed and anim != "down":
		_pose_throw(theta)
	elif holding:
		_pose_arms(theta)
	else:
		_pose_arms_relaxed(true)
	if _gun != null:
		_gun.visible = holding
		if _gun_n != null:
			_gun_n.visible = holding

func _pose_body(delta: float, anim: String, speed: float, theta: float) -> void:
	var hips := _b["Hips"] as int
	var run := anim == "run" or anim == "crouch_walk"
	var crouch := anim == "crouch" or anim == "crouch_walk"
	if run:
		_phase += delta * clampf(speed / 95.0, 0.4, 1.4) * TAU * 2.0
	var lean := 4.0
	var drop := 0.0
	var bob := 0.0
	var lunge := 0.0
	if anim == "idle":
		bob = -0.006 * sin(_time * 2.4)
		lean = 4.0 + 0.8 * sin(_time * 2.4)
	elif anim == "run":
		lean = 13.0
		bob = -0.035 * absf(sin(_phase))
	elif anim == "jump":
		lean = 8.0
	elif anim == "fall":
		lean = 2.0
	elif crouch:
		lean = 6.0                                                    # przysiad: tułów prawie pionowo (nie pochylony), kolana do przodu
		drop = 0.48                                                   # głęboki przysiad: sylwetka ok. 0,65 wysokości stojącej, jak hitbox kucania (11 / 17 px)
		bob = (0.012 * sin(_phase * 2.0)) if run else 0.0
	if swing_t >= 0.0:                                            # cios: wypad do przodu w chwili cięcia
		lunge = sin(clampf(swing_t * 2.0, 0.0, 1.0) * PI) * 0.09
		lean += lunge * 60.0
	if anim == "down":
		_move_global(hips, Vector3(0.0, -0.62, 0.0))
		_rot_world(hips, Vector3.BACK, -PI * 0.5)
		return
	_move_global(hips, Vector3(lunge, -drop + bob, 0.0))                           # kucając biodra cofnięte za stopy
	_rot_world(hips, Vector3.BACK, -deg_to_rad(lean))
	# tułów zwraca się ku kamerze (broń po bliższej stronie) i pochyla się za celem
	_rot_world(_b["Spine"], Vector3.UP, deg_to_rad(-22.0))
	for n in ["Spine", "Spine1", "Spine2"]:
		_rot_world(_b[n], Vector3.BACK, theta * 0.13 + deg_to_rad(lean) * 0.12 - gun_extra * 0.06)
	_rot_world(_b["Head"], Vector3.BACK, theta * 0.2 - deg_to_rad(lean) * 0.5)
	_pose_legs(anim)

func _pose_legs(anim: String) -> void:
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Right" else -1.0
		var rest_foot := _sk.get_bone_global_rest(_b[side + "Foot"]).origin
		var off := Vector3.ZERO
		var tilt := 0.0
		var ph := _phase + (0.0 if side == "Right" else PI)
		if anim == "idle":
			off = Vector3(0.12 * sgn * 0.8, 0.0, 0.0)
		elif anim == "run":
			off = Vector3(0.34 * sin(ph), 0.17 * maxf(0.0, cos(ph)), 0.0)
			tilt = deg_to_rad(-14.0) * maxf(0.0, cos(ph))
		elif anim == "jump":
			off = Vector3(0.28 if sgn > 0 else -0.12, 0.30 if sgn > 0 else 0.16, 0.0)
			tilt = deg_to_rad(-14.0)
		elif anim == "fall":
			off = Vector3(0.10 if sgn > 0 else -0.08, 0.14 if sgn > 0 else 0.22, 0.0)
		elif anim == "crouch":
			off = Vector3(0.10 if sgn > 0 else -0.10, 0.0, 0.0)
		elif anim == "crouch_walk":
			off = Vector3(0.13 * sin(ph) + (0.06 if sgn > 0 else -0.06), 0.07 * maxf(0.0, cos(ph)), 0.0)
		var target := Vector3(_origin_x + off.x, _ankle_y + off.y, rest_foot.z)
		_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], _b[side + "Foot"], _leg_len[side][0], _leg_len[side][1], target, Vector3(1.0, 0.0, 0.0))
		# stopa płasko (z lekkim obrotem czubka)
		var rest_gb := _sk.get_bone_global_rest(_b[side + "Foot"]).basis
		_set_global_basis(_b[side + "Foot"], Basis(Vector3.BACK, tilt) * rest_gb)

## Broń wokół barku: prawa dłoń na chwycie pistoletowym; lewa na łożu (broń dwuręczna), sięga po magazynek przy przeładowaniu,
## albo zwisa (pistolet, broń biała). Gdy łoże za daleko, broń jest wsuwana ku ciału.
func _pose_arms(theta: float) -> void:
	var sr := _gp(_b["RightArm"]).origin
	var sl := _gp(_b["LeftArm"]).origin
	var aim_t := theta - gun_extra
	var dirv := Vector3(cos(aim_t), sin(aim_t), 0.0)
	var up := Vector3(-sin(aim_t), cos(aim_t), 0.0)
	var gun_b := Basis(Vector3.BACK, aim_t)
	var radial := 0.30
	var rear := Vector3.ZERO
	var fore := Vector3.ZERO
	var reach_l: float = _arm_len["Left"][0] + _arm_len["Left"][1]
	var kick_m := gun_kick_px / WP_PER_M * 0.6
	# celowanie w dół: broń wysuwa się ku kamerze, żeby nie chować się za tułowiem (z=+ to bliższa strona)
	for k in 8:
		rear = sr + Vector3(cos(theta), sin(theta), 0.0) * radial - Vector3(-sin(theta), cos(theta), 0.0) * 0.11 + Vector3(0.0, 0.0, -0.13 + 0.28 * maxf(0.0, -sin(theta)))
		rear -= dirv * kick_m
		fore = rear + gun_b * (_gun_info["fore"] as Vector3)
		if _hands == 1 or fore.distance_to(sl) <= reach_l * 0.97:
			break
		radial -= 0.035
	var gx := Transform3D(gun_b, rear)
	if _gun != null:
		_gun.transform = gx
		if _gun_n != null:
			_gun_n.transform = gx
	_two_bone(_b["RightArm"], _b["RightForeArm"], _b["RightHand"], _arm_len["Right"][0], _arm_len["Right"][1], rear, Vector3(-0.35, -1.0, 0.55))
	if _hands == 2:
		var lt := fore
		if reload_t >= 0.0:                                       # lewa dłoń zostawia łoże, sięga po magazynek i wraca
			var mag := rear + gun_b * Vector3(_gun_len * 0.1, -0.24, 0.0)
			var k := sin(clampf(reload_t, 0.0, 1.0) * PI)
			lt = fore.lerp(mag, ease(k, 0.5))
		_two_bone(_b["LeftArm"], _b["LeftForeArm"], _b["LeftHand"], _arm_len["Left"][0], _arm_len["Left"][1], lt, Vector3(-0.25, -1.0, -0.4))
		_set_global_basis(_b["LeftHand"], gx.basis)
	else:
		_pose_left_relaxed()
	_set_global_basis(_b["RightHand"], gx.basis * Basis(Vector3.FORWARD, deg_to_rad(8.0)))
	muzzle_px = _to_px(gx * (_gun_info["muzzle"] as Vector3))
	grip_px = _to_px(rear)

## Rzut: prawa ręka zamach z tyłu nad głową → wyprost w przód i w dół (zwolnienie ok. 60% czasu), lewa ręka swobodnie.
func _pose_throw(theta: float) -> void:
	var t := clampf(throw_t, 0.0, 1.0)
	var ang := lerpf(deg_to_rad(160.0), deg_to_rad(-15.0) + theta * 0.6, ease(t, 0.7))
	var sr := _gp(_b["RightArm"]).origin
	var reach: float = (_arm_len["Right"][0] + _arm_len["Right"][1]) * 0.92
	var target := sr + Vector3(cos(ang), sin(ang), 0.0) * reach + Vector3(0.0, 0.0, 0.06)
	_two_bone(_b["RightArm"], _b["RightForeArm"], _b["RightHand"], _arm_len["Right"][0], _arm_len["Right"][1], target, Vector3(-0.3, -0.6, 0.6))
	_pose_left_relaxed()
	muzzle_px = _to_px(target)
	grip_px = muzzle_px

func _pose_left_relaxed() -> void:
	var sl := _gp(_b["LeftArm"]).origin
	var reach: float = _arm_len["Left"][0] + _arm_len["Left"][1]
	_two_bone(_b["LeftArm"], _b["LeftForeArm"], _b["LeftHand"], _arm_len["Left"][0], _arm_len["Left"][1], sl + Vector3(0.12, -reach * 0.9, 0.05), Vector3(-0.3, -1.0, -0.5))

func _pose_arms_relaxed(both: bool) -> void:
	muzzle_px = Vector2(0.0, -10.0)
	grip_px = muzzle_px
	if both and not _b.is_empty():
		var sr := _gp(_b["RightArm"]).origin
		var reach: float = _arm_len["Right"][0] + _arm_len["Right"][1]
		_two_bone(_b["RightArm"], _b["RightForeArm"], _b["RightHand"], _arm_len["Right"][0], _arm_len["Right"][1], sr + Vector3(0.10, -reach * 0.9, -0.03), Vector3(-0.3, -1.0, 0.5))
		_pose_left_relaxed()

## Punkt 3D (m) → piksele świata względem stóp, z odbiciem.
func _to_px(p: Vector3) -> Vector2:
	var fl := -1.0 if _sprite.flip_h else 1.0
	return Vector2((p.x - _origin_x) * WP_PER_M * fl, -p.y * WP_PER_M)
