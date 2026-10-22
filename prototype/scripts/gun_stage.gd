extends Control
## Ława rusznikarska w 3D (GUNSMITH_PLAN.md etap 2c, od 1.7.323): broń z częściami gracza w małej scenie 3D warsztatu — ciepła lampa nad ławą,
## chłodna kontra, broń leży bokiem i lekko się kołysze; przeciągnięcie myszą obraca ją. Część pod kursorem panelu (albo element fabryczny jej
## gniazda) świeci i jest wysunięta ze swojego gniazda w stronę, w którą się ją zdejmuje (magazynek w dół, tłumik do przodu, kolba do tyłu) —
## jak broń rozłożona na stole. Model składa gun_model.gd (te same części, które widać w dłoniach postaci).

const Weapons := preload("res://scripts/weapons.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Parts := preload("res://scripts/parts.gd")
const Char3D := preload("res://scripts/char3d.gd")

const MAX_PX := Vector2i(1600, 640)           ## górna granica rozdzielczości sceny (renderujemy w pikselach ekranu prostokąta, nie w 640×360 interfejsu)
const CAM_DIST := 4.6
const CAM_FOV := 30.0                         ## poziomy kąt kamery (KEEP_WIDTH) — szerokość kadru nie zależy od wysokości panelu
const FILL_W := 0.92                          ## jaką część szerokości / wysokości kadru zajmuje broń ze wszystkimi swoimi częściami (i zapasem na wysunięcie)
const FILL_H := 0.86
const PULL_M := 0.04                          ## o ile metrów (w skali broni) część pod kursorem wysuwa się z gniazda
const LAMP := Color(1.0, 0.88, 0.74)
## poświata części pod kursorem: krawędzie (fresnel) świecą mocniej niż lico — tekstura części zostaje czytelna
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec3 glow_color : source_color = vec3(1.0, 0.68, 0.3);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = glow_color * strength * (0.12 + 0.9 * rim);
}
"""
## Brud i nagar (WORKSHOP_PLAN.md W2, od 1.7.350): nakładka mnożąca kolor w plamach z szumu w układzie modelu; `amount` = 1 − stan broni.
const DIRT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back;
uniform float amount = 0.0;
varying vec3 p;
void vertex() {
	p = VERTEX;
}
float h(vec3 q) {
	return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
float n3(vec3 q) {
	vec3 i = floor(q);
	vec3 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h(i), h(i + vec3(1, 0, 0)), f.x), mix(h(i + vec3(0, 1, 0)), h(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(h(i + vec3(0, 0, 1)), h(i + vec3(1, 0, 1)), f.x), mix(h(i + vec3(0, 1, 1)), h(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}
void fragment() {
	float g = n3(p * 38.0) * 0.6 + n3(p * 140.0) * 0.4;
	float d = smoothstep(0.62 - 0.4 * amount, 0.9, g) * clamp(amount * 1.4, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0), vec3(0.42, 0.37, 0.3), d);
}
"""
const STRIP_M := 0.13                         ## o ile metrów (w skali broni) rozjeżdżają się podzespoły rozłożonej broni (czyszczenie)

## kierunek zdejmowania części z gniazda (układ broni: x wzdłuż lufy, y w górę)
const PULL_DIR := {
	"feed": Vector3(0.0, -1.0, 0.0), "barrel": Vector3(1.0, 0.0, 0.0), "muzzle": Vector3(1.0, 0.0, 0.0), "action": Vector3(0.0, 1.0, 0.0),
	"stock": Vector3(-1.0, 0.0, 0.0), "optic": Vector3(0.0, 1.0, 0.0), "edge": Vector3(0.0, 1.0, 0.0), "head": Vector3(0.0, 1.0, 0.0),
	"special": Vector3(0.0, -1.0, 0.0),
}

var _vp: SubViewport
var _view: TextureRect
var _pivot: Node3D
var _model: Node3D
var _lamp: SpotLight3D
var _rim: OmniLight3D
var _glow: ShaderMaterial
var _sig := ""                                ## co pokazujemy (broń, części, podświetlenie, blokada) — zmiana = przebudowa
var _fit_key := ""                            ## broń i proporcje, dla których liczono kadr (kadr stały dla broni — nie skacze przy zmianie części)
var _fit_k := 1.0
var _fit_c := Vector3.ZERO
var _hl: Array = []                           ## węzły podświetlone (część albo fabryczne podzespoły gniazda)
var _hl_dir := Vector3.ZERO
var _pull := 0.0
var _locked := false
var _t := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _idle := 9.0
var _dirt: ShaderMaterial
var _dirt_amount := 0.0
var _strip_target := 0.0                     ## 1 — broń rozłożona na podzespoły (czyszczenie przy stole konserwacji)
var _strip := 0.0
var _comps: Array = []                        ## [{node, base, dir}] — podzespoły i części modelu do rozłożenia

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(320, 120)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = CAM_FOV
	cam.position = Vector3(0.0, 0.0, CAM_DIST)
	_vp.add_child(cam)
	_lamp = SpotLight3D.new()
	_lamp.light_color = LAMP
	_lamp.spot_range = 9.0
	_lamp.spot_angle = 40.0
	_lamp.position = Vector3(0.4, 2.4, 2.4)
	_vp.add_child(_lamp)
	_lamp.look_at(Vector3.ZERO)
	_rim = OmniLight3D.new()
	_rim.omni_range = 6.0
	_rim.position = Vector3(-1.6, 0.8, -1.8)
	_vp.add_child(_rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	_glow = ShaderMaterial.new()                             # nakładka na część pod kursorem (material_overlay)
	_glow.shader = sh
	var dsh := Shader.new()
	dsh.code = DIRT_SHADER
	_dirt = ShaderMaterial.new()                             # brud: nakładka na resztę broni
	_dirt.shader = dsh

## Brud na broni: 0 — czysta, 1 — zaniedbana (stan 0 %).
func set_dirt(x: float) -> void:
	_dirt_amount = clampf(x, 0.0, 1.0)
	_dirt.set_shader_parameter("amount", _dirt_amount)

## Rozłożenie broni na podzespoły (`on`) albo złożenie z powrotem — płynnie, w _process.
func set_strip(on: bool) -> void:
	_strip_target = 1.0 if on else 0.0

## Pokazuje broń `w` z częściami `ids` (Parts.decode). `hl_part` = id części do podświetlenia, `hl_slot` = gniazdo (gdy kursor stoi na elemencie
## fabrycznym — świecą fabryczne podzespoły tego gniazda). `locked` = broń niekupiona (półmrok, czerwona kontra).
func show_gun(w: int, ids: Array, hl_part: String, hl_slot: String, locked: bool) -> void:
	var key := String(Weapons.def(w).key) if Weapons.is_valid(w) else ""
	var nt := Profile.notches(key) if key != "" else 0
	var deep := Profile.boss_notches(key) if key != "" else 0
	var sig := "%s|%s|%s|%s|%s|%d|%d" % [key, ",".join(ids), hl_part, hl_slot, str(locked), nt, deep]
	if sig == _sig:
		return
	var same_gun := _sig.get_slice("|", 0) == key
	_sig = sig
	_locked = locked
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_hl.clear()
	if key == "" or not ResourceLoader.exists(GunModel.DIR + "gun_%s.glb" % key):
		return
	var bm: Vector3 = Char3D.gun_info(key)["muzzle"]
	_model = GunModel.build(key, ids, bm, nt, deep)          # nacięcia na kolbie (historia broni)
	_pivot.add_child(_model)
	_place()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _dirt
	_collect_comps()
	# podświetlenie: węzeł części albo fabryczne podzespoły, które części tego gniazda zastępują
	var targets: Array = []
	if hl_part != "" and GunModel.has_model(hl_part):
		for n in _model.get_children():
			if String(n.name).begins_with("gunpart_" + hl_part):
				targets.append(n)
	elif hl_slot != "":
		var comps := {}
		for p in Parts.in_slot(key, hl_slot):
			for h in GunModel.part_info(String(p["id"])).get("hides", []):
				comps[String(h)] = true
		for n in _model.find_children("*__*", "MeshInstance3D", true, false):
			if comps.has(String(n.name).get_slice("__", 1)):
				targets.append(n)
	for n in targets:
		_hl.append({"node": n, "base": (n as Node3D).position})
		for mi in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = _glow
	for c in _comps:
		for h in _hl:
			if h["node"] == c["node"]:
				c["hl"] = true
	var slot := hl_slot if hl_slot != "" else String(Parts.get_part(hl_part).get("slot", ""))
	_hl_dir = PULL_DIR.get(slot, Vector3.ZERO)
	_pull = 0.0
	if not same_gun:
		_yaw = 0.0
		_pitch = 0.0
		_idle = 9.0

## Podzespoły do rozłożenia: węzły „…__<podzespół>” i części; kierunek = od środka broni do środka podzespołu (głównie w górę/dół i wzdłuż lufy).
func _collect_comps() -> void:
	_comps.clear()
	var nodes: Array = _model.find_children("*__*", "MeshInstance3D", true, false)
	for n in _model.get_children():
		if String(n.name).begins_with("gunpart_"):
			nodes.append(n)
	if nodes.is_empty():
		return
	var inv := _model.global_transform.affine_inverse()
	var centers := []
	var sum := Vector3.ZERO
	for n in nodes:
		var c := Vector3.ZERO
		var cnt := 0
		for mi in ([n] if n is MeshInstance3D else []) + (n as Node).find_children("*", "MeshInstance3D", true, false):
			c += inv * ((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb().get_center())
			cnt += 1
		c = c / float(maxi(cnt, 1))
		centers.append(c)
		sum += c
	var mid := sum / float(nodes.size())
	for i in nodes.size():
		var dv: Vector3 = (centers[i] as Vector3) - mid
		dv.z = 0.0
		var dir := dv.normalized() if dv.length() > 0.001 else Vector3.UP
		_comps.append({"node": nodes[i], "base": (nodes[i] as Node3D).position, "dir": dir, "hl": false})

## Kadr broni: skala i środek z obrysu broni fabrycznej i każdej jej części z modelem (z zapasem na wysunięcie), więc żadna część — także długi
## tłumik — nie wychodzi poza ławę, a kadr nie skacze przy zmianie części. Broń leży bokiem, więc mieści się długością (x) w szerokości kadru
## i wysokością (y) w jego wysokości — pistolet jest wyższy względem długości niż karabin.
func _place() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var key := _sig.get_slice("|", 0)
	var aspect := float(_vp.size.x) / maxf(1.0, float(_vp.size.y))
	var fk := "%s|%.2f" % [key, aspect]
	if fk != _fit_key:
		_fit_key = fk
		var bm: Vector3 = Char3D.gun_info(key)["muzzle"]
		var box := AABB()
		var first := true
		var sets: Array = [[]]
		for p in Parts.of(key):
			if GunModel.has_model(String(p["id"])):
				sets.append([String(p["id"])])
		for ids in sets:
			var probe := GunModel.build(key, ids, bm)
			for mi in probe.find_children("*", "MeshInstance3D", true, false):
				var xf := (mi as Node3D).transform
				var up := mi.get_parent()
				while up != probe and up is Node3D:
					xf = (up as Node3D).transform * xf
					up = up.get_parent()
				var ab: AABB = xf * (mi as MeshInstance3D).get_aabb()
				box = ab if first else box.merge(ab)
				first = false
			probe.free()
		box = box.grow(PULL_M)
		var vis_w := 2.0 * CAM_DIST * tan(deg_to_rad(CAM_FOV * 0.5))
		var vis_h := vis_w / aspect
		_fit_k = minf(FILL_W * vis_w / maxf(box.size.x, 0.001), FILL_H * vis_h / maxf(box.size.y, 0.001))
		_fit_c = box.get_center()
	_model.scale = Vector3.ONE * _fit_k
	_model.position = -_fit_c * _fit_k

## Scena renderuje się w pikselach ekranu prostokąta (interfejs 640×360 jest skalowany do okna) — inaczej broń byłaby rozmyta.
func _fit_viewport() -> void:
	var px := size * get_global_transform_with_canvas().get_scale() * get_viewport().get_final_transform().get_scale()
	var want := Vector2i(clampi(int(px.x), 64, MAX_PX.x), clampi(int(px.y), 32, MAX_PX.y))
	if want != _vp.size:
		_vp.size = want
		_place()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		var rel := (event as InputEventMouseMotion).relative
		_yaw += rel.x * 0.01
		_pitch = clampf(_pitch + rel.y * 0.008, -1.0, 1.0)
		_idle = 0.0
		accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_fit_viewport()
	_t += delta
	_idle += delta
	if _idle > 2.0:
		# nikt nie obraca: broń wraca bokiem do lampy i lekko się kołysze (bok czyta się najlepiej — widać, co jest w gnieździe)
		_yaw = lerpf(_yaw, 0.28 * sin(_t * 0.45), minf(1.0, delta * 1.5))
		_pitch = lerpf(_pitch, 0.12 + 0.05 * sin(_t * 0.6), minf(1.0, delta * 1.5))
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	# część pod kursorem wysuwa się z gniazda i pulsuje
	_pull = move_toward(_pull, 1.0, delta * 3.0)
	var off := _hl_dir * PULL_M * ease(_pull, 0.4) * (0.85 + 0.15 * sin(_t * 3.0))
	for h in _hl:
		var n: Node3D = h["node"]
		if is_instance_valid(n):
			n.position = (h["base"] as Vector3) + off
	# rozłożona broń (czyszczenie): podzespoły odjeżdżają od środka; podświetlony dostaje to samo przesunięcie do swojego wysunięcia
	_strip = move_toward(_strip, _strip_target, delta * 1.6)
	var k := STRIP_M * ease(_strip, -1.8)
	for c in _comps:
		var cn: Node3D = c["node"]
		if not is_instance_valid(cn):
			continue
		var so: Vector3 = (c["dir"] as Vector3) * k
		cn.position = (cn.position + so) if bool(c["hl"]) else ((c["base"] as Vector3) + so)
	_glow.set_shader_parameter("strength", 0.6 + 0.4 * sin(_t * 4.0))
	_view.modulate = Color(0.42, 0.46, 0.52) if _locked else Color.WHITE
	_lamp.light_energy = 2.5 if _locked else 5.0
	_rim.light_color = Color(0.9, 0.12, 0.08) if _locked else Color(0.45, 0.6, 0.9)
	_rim.light_energy = 1.6 if _locked else 1.0
