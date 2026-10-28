extends Control
## Scena broni 3D: zwarty podgląd stanowisk albo pełna ława z matą, tacą, projekcją gniazd i montażem po zatwierdzeniu.
## Te same modele i części co w dłoniach postaci (GunModel). Podświetlenie nie przebudowuje broni.
## Efekt montażu pokazuje migawkę sprzed zmiany, odkłada część na tacę i osadza nową; nie zmienia stanu gry.

const Weapons := preload("res://scripts/weapons.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Parts := preload("res://scripts/parts.gd")
const Char3D := preload("res://scripts/char3d.gd")

signal mount_finished
signal slot_clicked(slot: String)
var bench_mode := false
var reduced_motion := false
static var _bounds_cache: Dictionary = {}

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
## Fabryczne podzespoły typowe dla gniazda, gdy żadna jego część nie ma `hides` (P-83: magazynek, PELLET-8: czółenko). Pomijane, jeśli
## podzespół należy już do innego gniazda tej broni (kilof: głowica to gniazdo „head”, nie „edge”).
const SLOT_COMPS := {
	"feed": ["mag", "tube", "tank"], "barrel": ["front", "barrel"], "muzzle": ["muzzle"], "action": ["bolt", "pump"],
	"stock": ["stock", "grip", "saddle"], "optic": ["optic"], "edge": ["blade"], "head": ["head"],
}
## Gniazdo bez żadnego podzespołu (mechanizm, lufa w osłonie): punkt na długości broni, 0 = tył, 1 = wylot. Lufa i wylot leżą na osi
## przewodu, reszta w środku przekroju bryły w tym miejscu — nie w środku obrysu, który u SPREAD-12 wypada w bębnie.
const SLOT_ALONG := {
	"stock": 0.1, "feed": 0.38, "action": 0.55, "special": 0.65, "optic": 0.5, "barrel": 0.78, "edge": 0.92, "head": 0.92, "muzzle": 1.0,
}

var _vp: SubViewport
var _camera: Camera3D
var _table: Node3D
var _tray_model: Node3D
var _tray_sig := ""
var _tray_box := AABB()
var _model_sig := ""
var _weapon := -1
var _ids: Array = []
var _focus_slot := ""
var _dragging := false
var _drag_distance := 0.0
var _outgoing: Node3D
var _mount_nodes: Array = []
var _mount_time := -1.0
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
var _anchors := {}                            ## gniazdo bez podzespołu → punkt w układzie modelu (dla bieżącego modelu)
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
var _strip_box := AABB()                      ## obrys bieżącego modelu rozłożonego do końca (układ modelu); pusty — brak podzespołów
var _strip_k := 1.0                           ## kadr rozłożonej broni: skala i środek; między nim a kadrem złożonej przechodzimy płynnie z _strip
var _strip_c := Vector3.ZERO

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
	env.ambient_light_energy = 0.22 if bench_mode else 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	_camera = cam
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = CAM_FOV
	cam.position = Vector3(0.0, 0.0, CAM_DIST)
	if bench_mode:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.0 * CAM_DIST * tan(deg_to_rad(CAM_FOV * 0.5))
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
	if bench_mode:
		_build_bench()

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
	_weapon = w
	_ids = ids.duplicate()
	var model_sig := "%s|%s|%d|%d" % [key, ",".join(ids), nt, deep]
	if model_sig != _model_sig:
		cancel_mount()
		_model_sig = model_sig
		if is_instance_valid(_model):
			_pivot.remove_child(_model)
			_model.queue_free()
		_model = null
		if key == "" or not ResourceLoader.exists(GunModel.DIR + "gun_%s.glb" % key):
			_hl.clear()
			return
		var bm: Vector3 = Char3D.gun_info(key)["muzzle"]
		_model = GunModel.build(key, ids, bm, nt, deep)
		_anchors.clear()
		_pivot.add_child(_model)
		_collect_comps()
		_place()
	# Zmiana podświetlenia nie przebudowuje modelu ani nie zostawia wysuniętego podzespołu.
	for c in _comps:
		(c["node"] as Node3D).position = c["base"]
		c["hl"] = false
	_hl.clear()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _dirt
	# podświetlenie: węzeł części albo fabryczne podzespoły, które części tego gniazda zastępują
	var targets: Array = _slot_targets(_model, key, hl_part, hl_slot)
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
	_focus_slot = hl_slot if bench_mode else ""
	_show_tray(hl_part, hl_slot)
	_pull = 0.0
	if not same_gun:
		_yaw = 0.0
		_pitch = 0.0
		_idle = 9.0
		_camera.position = Vector3(0, 0, CAM_DIST)

## Gniazda z istniejących części i metadanych hides, także gdy zamontowana część ukryła fabryczny mesh.
func _slot_targets(root: Node3D, key: String, id: String, slot: String) -> Array:
	var targets: Array = []
	if id != "" and GunModel.has_model(id):
		for child in root.get_children():
			if String(child.name).begins_with("gunpart_" + id):
				targets.append(child)
	elif slot != "":
		var names := {}
		for part in Parts.in_slot(key, slot):
			for hidden in GunModel.part_info(String(part["id"])).get("hides", []):
				names[String(hidden)] = true
		for mesh in root.find_children("*__*", "MeshInstance3D", true, false):
			if names.has(String(mesh.name).get_slice("__", 1)):
				targets.append(mesh)
		if names.is_empty():
			var claimed := {}
			for part in Parts.of(key):
				for hidden in GunModel.part_info(String(part["id"])).get("hides", []):
					claimed[String(hidden)] = true
			var typical := {}
			for comp in SLOT_COMPS.get(slot, []):
				if not claimed.has(comp):
					typical[comp] = true
			for mesh in root.find_children("*__*", "MeshInstance3D", true, false):
				if typical.has(String(mesh.name).get_slice("__", 1)):
					targets.append(mesh)
	return targets

## Punkt gniazda bez podzespołu w układzie modelu: przekrój bryły w miejscu z SLOT_ALONG (lufa i wylot na osi przewodu).
func _slot_anchor(slot: String) -> Vector3:
	if _anchors.has(slot):
		return _anchors[slot]
	var points := PackedVector3Array()
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := GunModel._xf_in(mi, _model)
		for v in mi.mesh.get_faces():
			points.append(xf * v)
	if points.is_empty():
		return _fit_c
	var lo := points[0]
	var hi := points[0]
	for v in points:
		lo = lo.min(v)
		hi = hi.max(v)
	var muzzle := GunModel.barrel_muzzle(Char3D.gun_info(String(Weapons.def(_weapon).key))["muzzle"], _ids)
	var fwd := 1.0 if muzzle.x >= (lo.x + hi.x) * 0.5 else -1.0
	var rear := lo.x if fwd > 0.0 else hi.x
	var length := maxf(absf(muzzle.x - rear), 0.001)
	var x := rear + fwd * float(SLOT_ALONG.get(slot, 0.5)) * length
	var anchor := Vector3(x, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
	if slot == "barrel" or slot == "muzzle":
		anchor = Vector3(x, muzzle.y, muzzle.z)
	else:
		for half in [0.04 * length, 0.1 * length]:
			var sum := Vector3.ZERO
			var top := -INF
			var count := 0
			for v in points:
				if absf(v.x - x) <= half:
					sum += v
					top = maxf(top, v.y)
					count += 1
			if count > 0:
				anchor = sum / float(count)
				if slot == "optic":
					anchor.y = top
				break
	_anchors[slot] = anchor
	return anchor

func _slot_id(ids: Array, slot: String) -> String:
	for id in ids:
		if String(Parts.get_part(String(id)).get("slot", "")) == slot:
			return String(id)
	return ""

func slot_screen_position(slot: String) -> Vector2:
	if not is_instance_valid(_model) or _weapon < 0:
		return Vector2(INF, INF)
	var key := String(Weapons.def(_weapon).key)
	var nodes := _slot_targets(_model, key, _slot_id(_ids, slot), slot)
	var center := Vector3.ZERO
	var count := 0
	for node in nodes:
		for mesh in ([node] if node is MeshInstance3D else []) + node.find_children("*", "MeshInstance3D", true, false):
			center += (mesh as Node3D).global_transform * (mesh as MeshInstance3D).get_aabb().get_center()
			count += 1
	if count == 0:
		# Wewnętrzny mechanizm albo lufa w osłonie: punkt na bryle w miejscu tego gniazda, bez fikcyjnego zewnętrznego modelu.
		center = _model.global_transform * _slot_anchor(slot)
	else:
		center /= float(count)
	return _camera.unproject_position(center) * size / Vector2(_vp.size)

## Wybór powierzchni podzespołu po projekcji jego mesh, bez dodatkowych kolizji w symulacji gry.
func slot_at(point: Vector2) -> String:
	if not bench_mode or not is_instance_valid(_model):
		return ""
	var key := String(Weapons.def(_weapon).key)
	var selected := ""
	var distance := INF
	for slot in Parts.slots_of(key):
		var targets := _slot_targets(_model, key, _slot_id(_ids, String(slot)), String(slot))
		var center := slot_screen_position(String(slot))
		var hit := targets.is_empty() and point.distance_to(center) < 12.0
		for target in targets:
			for mesh in ([target] if target is MeshInstance3D else []) + target.find_children("*", "MeshInstance3D", true, false):
				var box: AABB = (mesh as MeshInstance3D).get_aabb()
				var rect := Rect2()
				for i in 8:
					var world: Vector3 = (mesh as Node3D).global_transform * box.get_endpoint(i)
					var pixel := _camera.unproject_position(world) * size / Vector2(_vp.size)
					rect = Rect2(pixel, Vector2.ZERO) if i == 0 else rect.expand(pixel)
				hit = hit or rect.grow(3.0).has_point(point)
		var dist := point.distance_squared_to(center)
		if hit and dist < distance:
			distance = dist
			selected = String(slot)
	return selected

func set_rendering(on: bool) -> void:
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if on else SubViewport.UPDATE_DISABLED

func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	if on:
		cancel_mount()
		_yaw = 0
		_pitch = 0
		_camera.position = Vector3(0, 0, CAM_DIST)

## Wyłącznie efekt po zatwierdzonym montażu. Nigdy nie zapisuje profilu ani nie obciąża banku.
func animate_mount(w: int, before: Array, after: Array) -> void:
	cancel_mount()
	if reduced_motion or not is_visible_in_tree() or w != _weapon or not is_instance_valid(_model):
		return
	var key := String(Weapons.def(w).key)
	_outgoing = GunModel.build(key, before, Char3D.gun_info(key)["muzzle"])
	_outgoing.scale = _model.scale
	_outgoing.position = _model.position
	_pivot.add_child(_outgoing)
	var old_targets: Array = []
	for slot in Parts.slots_of(key):
		var old_id := _slot_id(before, String(slot))
		var new_id := _slot_id(after, String(slot))
		if old_id == new_id:
			continue
		for node in _slot_targets(_outgoing, key, old_id, String(slot)):
			old_targets.append(node)
			var center := Vector3.ZERO
			var count := 0
			for mesh in ([node] if node is MeshInstance3D else []) + node.find_children("*", "MeshInstance3D", true, false):
				center += (mesh as Node3D).global_transform * (mesh as MeshInstance3D).get_aabb().get_center()
				count += 1
			center /= float(maxi(1, count))
			_mount_nodes.append({"node": node, "base": node.position, "scale": node.scale,
				"center": node.global_transform.affine_inverse() * center, "dir": PULL_DIR.get(slot, Vector3.UP), "old": true})
		for node in _slot_targets(_model, key, new_id, String(slot)):
			_mount_nodes.append({"node": node, "base": node.position, "dir": PULL_DIR.get(slot, Vector3.UP), "old": false})
	for mesh in _outgoing.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = old_targets.any(func(target: Node) -> bool: return target == mesh or target.is_ancestor_of(mesh))
	_mount_time = 0.0
	if DisplayServer.get_name() != "headless":
		Audio.play("mech_mag_out_1" if _slot_id(before, "feed") != _slot_id(after, "feed") else "mech_regrip_1", Audio.BUS_UI, -13.0)

func cancel_mount() -> void:
	for item in _mount_nodes:
		if not bool(item["old"]) and is_instance_valid(item["node"]):
			(item["node"] as Node3D).position = item["base"]
	_mount_nodes.clear()
	if is_instance_valid(_outgoing):
		_outgoing.get_parent().remove_child(_outgoing)
		_outgoing.queue_free()
	_outgoing = null
	_mount_time = -1.0

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
	# Obrys rozłożonej broni: podzespoły na chwilę w końcowym położeniu (zagnieżdżone sumują przesunięcia jak w _process).
	for c in _comps:
		(c["node"] as Node3D).position = (c["base"] as Vector3) + (c["dir"] as Vector3) * STRIP_M
	_strip_box = model_bounds(_model)
	for c in _comps:
		(c["node"] as Node3D).position = c["base"]

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
		var box: AABB = stable_bounds(key).grow(0.08 if bench_mode else PULL_M)
		var vis_w := 2.0 * CAM_DIST * tan(deg_to_rad(CAM_FOV * 0.5))
		var vis_h := vis_w / aspect
		_fit_k = minf(FILL_W * vis_w / maxf(box.size.x, 0.001), FILL_H * vis_h / maxf(box.size.y, 0.001))
		_fit_c = box.get_center()
	_strip_k = _fit_k
	_strip_c = _fit_c
	if not bench_mode and _strip_box.has_volume():
		var sbox := _strip_box.grow(PULL_M)
		_strip_c = sbox.get_center()
		_strip_k = _sway_fit(sbox, aspect, _fit_k)
	_apply_fit()
	if bench_mode and is_instance_valid(_table):
		var vis_w := 2.0 * CAM_DIST * tan(deg_to_rad(CAM_FOV * 0.5))
		_table.scale.y = (vis_w / aspect) / 1.55
		_fit_tray()

## Skala modelu wg postępu rozłożenia: kadr złożonej broni (stały dla broni) przechodzi w kadr rozłożonej (bieżące części), który
## nigdy nie przybliża — rozłożona broń najwyżej się oddala, żeby żaden podzespół nie wyszedł poza okno.
func _apply_fit() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var s := ease(_strip, -1.8)
	var k := lerpf(_fit_k, _strip_k, s)
	_model.scale = Vector3.ONE * k
	_model.position = -(_fit_c * _fit_k).lerp(_strip_c * _strip_k, s)

## Kąty (odchylenie, pochylenie) rozłożonej broni, w których ma się mieścić w kadrze: bez dotyku leży bokiem (kołysanie wygasa z rozłożeniem).
const STRIP_POSES := [Vector2(0.0, 0.0)]

## Największa skala ≤ `k_max`, przy której obrys `box` (układ modelu, środek w osi obrotu) mieści się w FILL_W × FILL_H kadru
## kamery perspektywicznej w każdym z kątów STRIP_POSES (bliższy koniec obróconej broni wychodzi na ekranie dalej).
func _sway_fit(box: AABB, aspect: float, k_max: float) -> float:
	var half_w := tan(deg_to_rad(CAM_FOV * 0.5))
	var c := box.get_center()
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(box.get_endpoint(i) - c)
	var fits := func(k: float) -> bool:
		for a in STRIP_POSES:
			var basis := Basis.from_euler(Vector3((a as Vector2).y, (a as Vector2).x, 0.0))
			for p in corners:
				var q: Vector3 = basis * (p * k)
				var depth := CAM_DIST - q.z
				if depth <= 0.01:
					return false
				if absf(q.x) / (depth * half_w) > FILL_W or absf(q.y) * aspect / (depth * half_w) > FILL_H:
					return false
		return true
	if fits.call(k_max):
		return k_max
	var lo := 0.0
	var hi := k_max
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if fits.call(mid):
			lo = mid
		else:
			hi = mid
	return lo

## Części na ramie mają niezależne obwiednie; wylot zależy też od wybranej lufy. Badamy wszystkie takie pary.
static func stable_bounds(key: String) -> AABB:
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var sets: Array = [[]]
	for part in Parts.of(key):
		if GunModel.has_model(String(part["id"])):
			sets.append([String(part["id"])])
	for barrel in Parts.in_slot(key, "barrel"):
		for muzzle in Parts.in_slot(key, "muzzle"):
			sets.append([String(barrel["id"]), String(muzzle["id"])])
	var box := AABB()
	var first := true
	for ids in sets:
		var probe := GunModel.build(key, ids, Char3D.gun_info(key)["muzzle"])
		var bound := model_bounds(probe)
		box = bound if first else box.merge(bound)
		first = false
		probe.free()
	_bounds_cache[key] = box
	return box

static func model_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var transform: Transform3D = mesh.transform
		var up: Node = mesh.get_parent()
		while up != root and up is Node3D:
			transform = (up as Node3D).transform * transform
			up = up.get_parent()
		var bound: AABB = transform * (mesh as MeshInstance3D).get_aabb()
		box = bound if first else box.merge(bound)
		first = false
	return box

func _bench_material(color: Color, grain := false) -> Material:
	if not grain:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.88
		return material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 base : source_color;
void fragment() {
	float grain = sin(UV.x * 290.0 + sin(UV.y * 29.0) * 3.0);
	float fleck = fract(sin(dot(floor(UV * 430.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = base.rgb * (0.85 + grain * 0.07 + fleck * 0.15);
	ROUGHNESS = 0.9;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base", color)
	return material

func _bench_box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _bench_metal(color: Color, roughness: float) -> Material:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.75
	material.roughness = roughness
	return material

## Walec leżący na macie (oś wzdłuż x, obrócony o `angle_deg` w płaszczyźnie maty); `upright` — stojący (łeb śruby).
func _bench_rod(parent: Node3D, length: float, radius: float, at: Vector3, angle_deg: float, material: Material, upright := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.height = length
	rod.top_radius = radius
	rod.bottom_radius = radius
	rod.radial_segments = 16
	mesh.mesh = rod
	mesh.material_override = material
	mesh.position = at
	mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0) if upright else Vector3(0.0, 0.0, PI * 0.5 + deg_to_rad(angle_deg))
	parent.add_child(mesh)
	return mesh

func _build_bench() -> void:
	_table = Node3D.new()
	_vp.add_child(_table)
	var wood := _bench_material(Color("57402d"), true)
	var mat := _bench_material(Color("344838"), true)
	var brass := _bench_material(Color("96784a"))
	_bench_box(_table, Vector3(2.9, 1.55, 0.09), Vector3(0, 0, -0.52), wood)
	_bench_box(_table, Vector3(2.33, 1.24, 0.014), Vector3(-0.05, 0.03, -0.465), mat)
	var grid := _bench_material(Color("52604c"))
	for i in 19:
		_bench_box(_table, Vector3(0.0015, 1.19, 0.002), Vector3(-1.1 + i * 0.12, 0.03, -0.455), grid)
	for i in 10:
		_bench_box(_table, Vector3(2.28, 0.0015, 0.002), Vector3(-0.05, -0.51 + i * 0.12, -0.455), grid)
	# Płytka taca, śrubokręt i stalowy wybijak: prawdziwe bryły 3D, jedna scena i bez nowych tekstur. Taca ma gumowe dno i wyższy,
	# jaśniejszy metalowy rant ze śrubami w rogach — płaska szara płyta wyglądała jak pusty prostokąt interfejsu.
	var rubber := _bench_material(Color("33362e"), true)
	var rim := _bench_metal(Color("8b918a"), 0.35)
	_bench_box(_table, Vector3(0.49, 0.30, 0.02), Vector3(0.81, -0.47, -0.435), _bench_metal(Color("454a44"), 0.55))
	_bench_box(_table, Vector3(0.45, 0.26, 0.006), Vector3(0.81, -0.47, -0.423), rubber)
	for side in [-1.0, 1.0]:
		_bench_box(_table, Vector3(0.49, 0.02, 0.04), Vector3(0.81, -0.47 + side * 0.14, -0.41), rim)
		_bench_box(_table, Vector3(0.02, 0.3, 0.04), Vector3(0.81 + side * 0.235, -0.47, -0.41), rim)
		for end in [-1.0, 1.0]:
			_bench_rod(_table, 0.008, 0.009, Vector3(0.81 + end * 0.235, -0.47 + side * 0.14, -0.386), 0.0, brass, true)
	# Drobiazgi w rogach tacy (śrubki, kołek, łuska): bez wysuniętej części ciemne gumowe dno czytało się jak pusta ramka interfejsu.
	var steel := _bench_metal(Color("b7bab2"), 0.3)
	_bench_rod(_table, 0.055, 0.008, Vector3(0.63, -0.56, -0.411), 28.0, steel)
	_bench_rod(_table, 0.045, 0.008, Vector3(0.675, -0.575, -0.411), -12.0, steel)
	_bench_rod(_table, 0.07, 0.006, Vector3(0.975, -0.385, -0.412), 64.0, steel)
	_bench_rod(_table, 0.06, 0.012, Vector3(0.965, -0.555, -0.408), -35.0, brass)
	# Narzędzia: walce z cieniowaniem i lekko skośnie — płaskie prostokąty w rzędzie czytały się jak paski postępu.
	var handle := _bench_material(Color("7a3424"))
	_bench_rod(_table, 0.2, 0.022, Vector3(-0.9, 0.6, -0.42), 7.0, handle)
	_bench_rod(_table, 0.2, 0.0065, Vector3(-0.7, 0.625, -0.43), 7.0, _bench_metal(Color("a9aea6"), 0.3))
	_bench_rod(_table, 0.3, 0.008, Vector3(-0.84, 0.52, -0.432), -4.0, brass)
	_lamp.shadow_enabled = true
	_lamp.position = Vector3(0.2, 0.65, 3.5)
	_lamp.look_at(Vector3.ZERO)

func _show_tray(id: String, slot: String) -> void:
	if not bench_mode:
		return
	var sig := "%s|%s|%d" % [id, slot, _weapon]
	if sig == _tray_sig:
		return
	_tray_sig = sig
	if is_instance_valid(_tray_model):
		_table.remove_child(_tray_model)
		_tray_model.queue_free()
	_tray_model = null
	if id == "" or not GunModel.has_model(id):
		return
	_tray_model = (load(GunModel.DIR + "gunpart_%s.glb" % id) as PackedScene).instantiate()
	_tray_box = model_bounds(_tray_model)
	_table.add_child(_tray_model)
	_fit_tray()

## Stół jest skalowany tylko w pionie (wysokość kadru), więc część na tacy dostaje odwrotną skalę y — inaczej bęben wychodził owalny.
func _fit_tray() -> void:
	if not is_instance_valid(_tray_model):
		return
	var squash := maxf(_table.scale.y, 0.001)
	var scale_k := minf(0.37 / maxf(_tray_box.size.x, 0.001), 0.20 * squash / maxf(_tray_box.size.y, 0.001))
	_tray_model.scale = Vector3(scale_k, scale_k / squash, scale_k)
	_tray_model.position = Vector3(0.81, -0.47, -0.32) - _tray_box.get_center() * _tray_model.scale

## Scena renderuje się w pikselach ekranu prostokąta (interfejs 640×360 jest skalowany do okna) — inaczej broń byłaby rozmyta.
func _fit_viewport() -> void:
	var px := size * get_global_transform_with_canvas().get_scale() * get_viewport().get_final_transform().get_scale()
	var k := minf(1.0, minf(float(MAX_PX.x) / maxf(1, px.x), float(MAX_PX.y) / maxf(1, px.y)))
	var want := Vector2i(maxi(int(px.x * k), 64), maxi(int(px.y * k), 32))
	if want != _vp.size:
		_vp.size = want
		_place()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_dragging = true
			_drag_distance = 0.0
		else:
			if _dragging and _drag_distance < 3.0:
				var slot := slot_at((event as InputEventMouseButton).position)
				if slot != "":
					slot_clicked.emit(slot)
			_dragging = false
		accept_event()
	if event is InputEventMouseMotion and _dragging and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var rel := (event as InputEventMouseMotion).relative
		_drag_distance += rel.length()
		if _drag_distance < 3.0:
			return
		_yaw = clampf(_yaw + rel.x * 0.01, -0.65, 0.65) if bench_mode else _yaw + rel.x * 0.01
		_pitch = clampf(_pitch + rel.y * 0.008, -0.45 if bench_mode else -1.0, 0.45 if bench_mode else 1.0)
		_idle = 0.0
		accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_fit_viewport()
	_t += delta
	_idle += delta
	if _idle > 2.0 and not reduced_motion:
		# nikt nie obraca: broń wraca bokiem do lampy i lekko się kołysze (bok czyta się najlepiej — widać, co jest w gnieździe);
		# rozłożona leży nieruchomo bokiem jak podzespoły na stole — kołysanie długich końców zabierałoby kadrowi miejsce
		var sway := 0.0 if bench_mode or reduced_motion else 1.0 - ease(_strip, -1.8)
		_yaw = lerpf(_yaw, sway * 0.28 * sin(_t * 0.45), minf(1.0, delta * 1.5))
		_pitch = lerpf(_pitch, sway * (0.12 + 0.05 * sin(_t * 0.6)), minf(1.0, delta * 1.5))
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	if bench_mode and is_instance_valid(_model):
		var frame: AABB = stable_bounds(String(Weapons.def(_weapon).key)).grow(0.14 if _mount_time >= 0 else PULL_M)
		var half := frame.size * 0.5 * _fit_k
		var z_radius := absf(_pivot.basis.x.z) * half.x + absf(_pivot.basis.y.z) * half.y + absf(_pivot.basis.z.z) * half.z
		# Podczas oglądania unosimy broń ponad matę; obrót nie wciska końców lufy i kolby w blat.
		_pivot.position.z = maxf(0.0, z_radius - 0.35)
	if bench_mode and not reduced_motion:
		var target := Vector3(0, 0, CAM_DIST)
		if _focus_slot != "" and is_instance_valid(_model):
			var anchor := slot_screen_position(_focus_slot)
			var world := _camera.project_position(anchor * Vector2(_vp.size) / size.max(Vector2.ONE), CAM_DIST)
			target.x = clampf(world.x * 0.12, -0.08, 0.08)
			target.y = clampf(world.y * 0.12, -0.05, 0.05)
		_camera.position = _camera.position.lerp(target, minf(1.0, delta * 4.0))
	# część pod kursorem wysuwa się z gniazda i pulsuje
	_pull = move_toward(_pull, 1.0, delta * 3.0)
	var off := Vector3.ZERO if reduced_motion else _hl_dir * PULL_M * ease(_pull, 0.4) * (1.0 if bench_mode else (0.85 + 0.15 * sin(_t * 3.0)))
	for h in _hl:
		var n: Node3D = h["node"]
		if is_instance_valid(n):
			n.position = (h["base"] as Vector3) + off
	# rozłożona broń (czyszczenie): podzespoły odjeżdżają od środka; podświetlony dostaje to samo przesunięcie do swojego wysunięcia
	_strip = move_toward(_strip, _strip_target, delta * 1.6)
	if not bench_mode:
		_apply_fit()
	var k := STRIP_M * ease(_strip, -1.8)
	for c in _comps:
		var cn: Node3D = c["node"]
		if not is_instance_valid(cn):
			continue
		var so: Vector3 = (c["dir"] as Vector3) * k
		cn.position = (cn.position + so) if bool(c["hl"]) else ((c["base"] as Vector3) + so)
	if _mount_time >= 0.0:
		_mount_time += delta
		var phase := clampf(_mount_time / 0.8, 0.0, 1.0)
		for item in _mount_nodes:
			if not is_instance_valid(item["node"]):
				continue
			var node: Node3D = item["node"]
			if bool(item["old"]) and bench_mode:
				var transfer := smoothstep(0.25, 0.7, phase)
				node.scale = (item["scale"] as Vector3).lerp((item["scale"] as Vector3) * 0.45, transfer)
				var tray := (node.get_parent() as Node3D).to_local(_table.to_global(Vector3(0.69, -0.47, -0.32)))
				var target := tray - node.basis * (item["center"] as Vector3)
				var removed: Vector3 = item["base"] + item["dir"] * smoothstep(0.0, 0.3, phase) * 0.14
				node.position = removed.lerp(target, transfer)
			else:
				var amount := smoothstep(0.0, 0.55, phase) if bool(item["old"]) else 1.0 - smoothstep(0.55, 1.0, phase)
				node.position = (item["base"] as Vector3) + (item["dir"] as Vector3) * amount * 0.14
		if phase >= 1.0:
			cancel_mount()
			if DisplayServer.get_name() != "headless":
				Audio.play("mech_mag_in_1", Audio.BUS_UI, -12.0)
			mount_finished.emit()
	_glow.set_shader_parameter("strength", 0.65 if bench_mode or reduced_motion else 0.6 + 0.4 * sin(_t * 4.0))
	_view.modulate = Color(0.42, 0.46, 0.52) if _locked else Color.WHITE
	_lamp.light_energy = 1.3 if _locked and bench_mode else (2.5 if _locked or bench_mode else 5.0)
	_rim.light_color = Color(0.9, 0.12, 0.08) if _locked else Color(0.45, 0.6, 0.9)
	_rim.light_energy = 1.6 if _locked else 1.0
