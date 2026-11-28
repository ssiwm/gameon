extends RefCounted
## Kryjówka pokazuje stan stanowisk bez otwierania kart (WORKSHOP_IMMERSION_PLAN.md R4). Tylko odczyt istniejących danych — `Scrap`
## (drużyna, zapis u hosta, replikowany) i `Profile` (lokalny gracz); nic tu nie zmienia gry. Rzeczy stoją na meblach stanowiska
## (`station_props`, view3d.gd `_sync_station_props`) w miejscach zmierzonych na modelach (wierzch blatu, półka, uchwyt tokarki):
## - prasa: pudełka zamówionych partii na blacie (`Scrap.orders`), partie gotowe do odbioru na dolnej półce (`Scrap.deliveries`);
## - tokarka: przedmiot w uchwycie kręci się, gdy jest zlecenie (`Scrap.lathe`);
## - pracownia: słoje z próbkami wg banku (`Scrap.samples`), geoda na blacie (`Scrap.geodes`);
## - ława: nowa, nieobejrzana część drużyny — broń gracza z jego montażem stoi w imadle, a część leży obok (`Profile.is_new("part:…")`);
## - szafka: kartka na drzwiach, gdy gracz ma odblokowany, nieobejrzany perk albo wolny slot i perk do założenia.
##   (Plan mówił o uchylonych drzwiach, ale model `locker_row` ma drzwi w jednej bryle, a środkowa szafka jest otwarta na stałe.)
## Stan liczony co klatkę jako krótki podpis; przy zmianie rzeczy budują się od nowa (rzadko — zakup, misja, odbiór).

const GunModel := preload("res://scripts/gun_model.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Parts := preload("res://scripts/parts.gd")
const Perks := preload("res://scripts/perks.gd")
const Level3D := preload("res://scripts/level3d.gd")

const PX := Level3D.PX
const ITEMS := "res://art/items3d/%s.glb"
const MAX_JARS := 6                          ## więcej próbek nie dokłada słojów (blat pracowni)
const SPIN := 1.6                            ## obr./s przedmiotu w uchwycie tokarki (wolno, żeby obrót było widać, nie migotanie)

## Miejsca na meblach w pikselach modelu (x w prawo, y w górę od podłogi, z ku kamerze), zmierzone promieniem w dół w siatkę modelu.
const PRESS_TOP := Vector3(-5.0, 12.2, 3.0)       ## reload_bench: przedni pas blatu (wolny od x −6 do 7)
const PRESS_STEP := 2.6
const PRESS_SHELF := Vector3(-5.0, 2.8, 2.6)      ## reload_bench: dolna półka, przód (słoje fabryczne stoją od x 0 w głąb)
const LATHE_AXIS := Vector3(-3.0, 15.3, 0.3)      ## lathe: oś wrzeciona przy uchwycie (wrzeciennik do x −3, łoże 13,6, konik od x 6)
const LATHE_LEN := 3.6
const LAB_TOP := Vector3(-5.6, 9.9, 3.4)          ## lab_desk: przedni pas blatu (mikroskop i papiery dalej w głębi)
const LAB_STEP := 1.6
const LAB_GEODE := Vector3(2.6, 9.9, 2.6)
const BENCH_TOP := Vector3(-1.5, 13.1, 1.6)        ## gunsmith_bench: blat (wolny przód; imadło na x −6, karabin z modelu stoi w głębi na z −4)
const BENCH_PART := Vector3(-8.0, 13.1, 3.0)
const LOCKER_NOTE := Vector3(-5.4, 13.6, 0.42)    ## locker_row: lico lewych drzwi (z ≈ 0,35) na wysokości oczu — prawe zasłania w kryjówce rura

var mode := ""
var root: Node3D                             ## korzeń wyposażenia stanowiska (view3d.gd StationProps_*), w metrach
var models: Array = []                       ## [model, przesunięcie x w px, głębia z w m] (station.gd `models`)
var sig := "?"                               ## podpis zbudowanego stanu
var holder: Node3D                           ## rzeczy stanu (przebudowywane)
var spin: Node3D                             ## tokarka: obracany przedmiot
var item_model: Callable                     ## view3d.gd `_item_model` (strojenie materiałów); pusty — zwykłe wczytanie

func _init(station_mode: String, props_root: Node3D, station_models: Array, loader := Callable()) -> void:
	mode = station_mode
	root = props_root
	models = station_models
	item_model = loader

## Podpis stanu stanowiska `m` — zmienia się dokładnie wtedy, gdy w świecie ma się coś zmienić.
static func signature(m: String) -> String:
	match m:
		"press":
			var d: Array = []
			for k in Scrap.deliveries:
				if int(Scrap.deliveries[k]) > 0:
					d.append(String(k))
			d.sort()
			return "%s/%s" % [",".join(Scrap.orders), ",".join(d)]
		"lathe":
			return "1" if not Scrap.lathe.is_empty() else ""
		"lab":
			return "%d/%d" % [mini(Scrap.samples, MAX_JARS), mini(Scrap.geodes, 1)]
		"bench":
			return bench_part()
		"locker":
			return "1" if locker_waiting() else ""
	return ""

## Nowa część drużyny, której lokalny gracz jeszcze nie obejrzał na ławie (kropka „nowe” w karcie) — "" gdy brak.
static func bench_part() -> String:
	var ids: Array = Scrap.parts.keys()
	ids.sort()
	for id in ids:
		var p := Parts.get_part(String(id))
		if not p.is_empty() and Profile.is_new("part:" + String(id)) and not Char3D.gun_info(String(p["weapon"])).is_empty():
			return String(id)
	return ""

## Na gracza czeka coś w szafce: odblokowany perk, którego nie obejrzał, albo wolny slot i perk, który da się założyć.
static func locker_waiting() -> bool:
	var free_slot := false
	for i in Profile.slots():
		if String(Profile.equipped[i]) == "":
			free_slot = true
	for id in Perks.ORDER:
		if not Profile.is_unlocked(String(id)):
			continue
		if Profile.is_new("perk:" + String(id)) or (free_slot and not Profile.has_perk(String(id))):
			return true
	return false

## Co klatkę (view3d.gd): przebudowa po zmianie podpisu, obrót przedmiotu w tokarce.
func sync(delta: float) -> void:
	if not is_instance_valid(root):
		return
	var s := signature(mode)
	if s != sig:
		sig = s
		_rebuild()
	if spin != null and is_instance_valid(spin):
		spin.rotate_x(TAU * SPIN * delta)

## Liczba rzeczy stanu (testy): węzły-dzieci `holder`.
func count() -> int:
	return holder.get_child_count() if holder != null and is_instance_valid(holder) else 0

func _rebuild() -> void:
	if holder != null and is_instance_valid(holder):
		holder.queue_free()
		root.remove_child(holder)
	spin = null
	holder = Node3D.new()
	holder.name = "State"
	root.add_child(holder)
	match mode:
		"press":
			_build_press()
		"lathe":
			_build_lathe()
		"lab":
			_build_lab()
		"bench":
			_build_bench()
		"locker":
			_build_locker()

## Punkt w metrach w układzie korzenia z punktu w pikselach modelu nr `i` (station.gd `models`).
func _at(i: int, p: Vector3) -> Vector3:
	var e: Array = models[i] if i < models.size() else [0, 0.0, 0.0]
	return Vector3((float(e[1]) + p.x) * PX, p.y * PX, float(e[2]) + p.z * PX)

func _model(name: String) -> Node3D:
	if item_model.is_valid():
		return item_model.call(name) as Node3D
	var ps := load(ITEMS % name) as PackedScene if ResourceLoader.exists(ITEMS % name) else null
	return ps.instantiate() as Node3D if ps != null else null

static func _mat(col: Color, rough := 0.7, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(col.r, col.g, col.b)
		m.emission_energy_multiplier = glow
	return m

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else holder).add_child(mi)
	return mi

# ---------------------------------------------------------------- prasa

## Pudełko z nabojami: model `ammo` zmniejszony do ~15 cm; zamówienie — z uchyloną pokrywą (w robocie), gotowe — zamknięte z banderolą.
func _box(at: Vector3, open: bool) -> void:
	var m := _model("ammo")
	if m == null:
		_mesh(_cbox(Vector3(0.16, 0.1, 0.12)), _mat(Color(0.45, 0.33, 0.2)), at + Vector3(0.0, 0.05, 0.0))
		return
	m.scale = Vector3.ONE * PX * 0.2
	m.position = at
	m.rotation.y = 0.18 if open else -0.12
	holder.add_child(m)
	if not open:
		_mesh(_cbox(Vector3(0.02, 0.012, 0.13)), _mat(Color(0.82, 0.78, 0.62), 0.9), at + Vector3(0.0, 8.7 * PX * 0.2, 0.0))

static func _cbox(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _build_press() -> void:
	for i in Scrap.orders.size():
		_box(_at(0, PRESS_TOP + Vector3(PRESS_STEP * i, 0.0, 0.0)), true)
	var n := 0
	var kinds: Array = Scrap.deliveries.keys()
	kinds.sort()
	for k in kinds:
		if int(Scrap.deliveries[k]) <= 0 or n >= 3:
			continue
		_box(_at(0, PRESS_SHELF + Vector3(2.2 * n, 0.0, 0.0)), false)
		n += 1

# ---------------------------------------------------------------- tokarka

## Przedmiot w uchwycie: stalowy wałek z kołnierzem i rowkiem (siedmiokąt — obrót widać na krawędziach), szczęki uchwytu przy wrzecienniku.
func _build_lathe() -> void:
	if Scrap.lathe.is_empty():
		return
	var axis := _at(0, LATHE_AXIS)
	spin = Node3D.new()
	spin.position = axis
	holder.add_child(spin)
	var steel := _mat(Color(0.72, 0.72, 0.7), 0.3, 0.9)
	var cut := _mat(Color(0.86, 0.84, 0.8), 0.18, 1.0)
	var len := LATHE_LEN * PX
	var r := 0.5 * PX
	var shaft := CylinderMesh.new()
	shaft.top_radius = r
	shaft.bottom_radius = r
	shaft.height = len
	shaft.radial_segments = 7
	var s := _mesh(shaft, steel, Vector3(len * 0.5, 0.0, 0.0), spin)
	s.rotation.z = PI * 0.5
	var collar := CylinderMesh.new()
	collar.top_radius = r * 1.45
	collar.bottom_radius = r * 1.45
	collar.height = 0.5 * PX
	collar.radial_segments = 7
	var c := _mesh(collar, cut, Vector3(len * 0.62, 0.0, 0.0), spin)
	c.rotation.z = PI * 0.5
	for j in 3:                                                    # szczęki uchwytu
		var jaw := _mesh(_cbox(Vector3(0.5 * PX, 0.55 * PX, 0.35 * PX)), _mat(Color(0.25, 0.25, 0.24), 0.5, 0.8),
			Vector3(0.25 * PX, 0.0, 0.0), spin)
		jaw.rotation.x = TAU * j / 3.0
		jaw.position += Vector3(0.0, cos(TAU * j / 3.0), sin(TAU * j / 3.0)) * r * 1.3
	var chips := Node3D.new()                                       # wióry na łożu pod przedmiotem (nie kręcą się)
	holder.add_child(chips)
	for j in 5:
		var w := _mesh(_cbox(Vector3(0.012, 0.004, 0.02)), cut, axis + Vector3(len * (0.25 + 0.12 * j), -1.65 * PX, 0.02 * float(j % 3 - 1)), chips)
		w.rotation.y = 0.7 * j

# ---------------------------------------------------------------- pracownia

## Słój z próbką: szklany walec, mętny płyn z lekką poświatą (widać go w półmroku kryjówki), blady kształt w środku i ciemne wieko.
func _jar(at: Vector3, seed: int) -> void:
	var h := 1.9 * PX
	var r := 0.6 * PX
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.8, 0.76, 0.42)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic_specular = 0.8
	var g := CylinderMesh.new()
	g.top_radius = r
	g.bottom_radius = r
	g.height = h
	g.radial_segments = 14
	_mesh(g, glass, at + Vector3(0.0, h * 0.5, 0.0))
	var fill := 0.62 + 0.08 * float(seed % 3)
	var lq := CylinderMesh.new()
	lq.top_radius = r * 0.9
	lq.bottom_radius = r * 0.9
	lq.height = h * fill
	lq.radial_segments = 14
	var tint := [Color(0.3, 0.32, 0.12, 0.8), Color(0.36, 0.27, 0.1, 0.8), Color(0.22, 0.3, 0.17, 0.8)][seed % 3] as Color
	var lm := _mat(tint, 0.2, 0.0, 0.05)                          # mętny płyn: półprzezroczysty, ciemny — kształt w środku prześwituje
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh(lq, lm, at + Vector3(0.0, h * fill * 0.5, 0.0))
	var blob := SphereMesh.new()
	blob.radius = r * 0.45
	blob.height = r * (1.1 + 0.15 * float(seed % 2))
	blob.radial_segments = 8
	blob.rings = 5
	_mesh(blob, _mat(Color(0.86, 0.8, 0.68), 0.6), at + Vector3(0.05 * r * float(seed % 3 - 1), h * fill * 0.45, 0.0))
	var lid := CylinderMesh.new()
	lid.top_radius = r * 1.04
	lid.bottom_radius = r * 1.04
	lid.height = 0.22 * PX
	lid.radial_segments = 14
	_mesh(lid, _mat(Color(0.18, 0.17, 0.15), 0.6, 0.5), at + Vector3(0.0, h + 0.11 * PX, 0.0))

func _build_lab() -> void:
	for i in mini(Scrap.samples, MAX_JARS):
		_jar(_at(0, LAB_TOP + Vector3(LAB_STEP * i, 0.0, 0.25 * float(i % 2))), i)
	if Scrap.geodes > 0:                                            # geoda z żyły czeka na rozbicie (DIG_LOOT_PLAN.md K4)
		var geo := SphereMesh.new()
		geo.radius = 0.85 * PX
		geo.height = 1.4 * PX
		geo.radial_segments = 7
		geo.rings = 4
		var gm := _mesh(geo, _mat(Color(0.36, 0.34, 0.32), 0.95), _at(0, LAB_GEODE) + Vector3(0.0, 0.62 * PX, 0.0))
		gm.rotation = Vector3(0.3, 0.8, 0.2)

# ---------------------------------------------------------------- ława

## Broń gracza (jego montaż) w imadle na blacie — profilem do kamery, lufą w prawo; obok nowa część (model części, jeśli ma model).
func _build_bench() -> void:
	var id := bench_part()
	if id == "":
		return
	var key := String(Parts.get_part(id)["weapon"])
	var ids: Array = []
	for slot in Parts.slots_of(key):
		var f := Profile.fitted(key, String(slot))
		if f != "":
			ids.append(f)
	var gun := GunModel.build(key, ids, Char3D.gun_info(key)["muzzle"])
	if gun == null:
		return
	var box := _bounds(gun)
	var top := _at(0, BENCH_TOP)
	gun.position = top - Vector3(box.get_center().x, box.position.y - 0.012, box.get_center().z)     # najniższy punkt (magazynek, kolba) na blacie
	holder.add_child(gun)
	_mesh(_cbox(Vector3(0.05, 0.035, 0.06)), _mat(Color(0.2, 0.2, 0.19), 0.6, 0.7), top + Vector3(0.0, 0.0175, 0.0))   # klocek imadła pod bronią
	if GunModel.has_model(id):
		var pn := GunModel.scene(GunModel.DIR + "gunpart_%s.glb" % id).instantiate() as Node3D
		var pb := _bounds(pn)
		var at := _at(0, BENCH_PART)
		pn.position = at - Vector3(pb.get_center().x, pb.position.y, pb.get_center().z)
		pn.rotation.y = 0.35
		holder.add_child(pn)
	else:                                                         # część bez modelu (mechanizm, dławik): zawiniątko w szmacie
		_mesh(_cbox(Vector3(0.12, 0.04, 0.08)), _mat(Color(0.5, 0.44, 0.34), 0.95), _at(0, BENCH_PART) + Vector3(0.0, 0.02, 0.0))

## Obrys siatek węzła w jego własnym układzie.
static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# ---------------------------------------------------------------- szafka

## Kartka przyklejona taśmą do drzwi lewej szafki — jasny papier z czerwonym wykrzyknikiem, widoczny w półmroku.
func _build_locker() -> void:
	if not locker_waiting():
		return
	var at := _at(0, LOCKER_NOTE)
	var paper := _mesh(_cbox(Vector3(1.35 * PX, 1.9 * PX, 0.004)), _mat(Color(0.9, 0.86, 0.72), 0.95, 0.0, 0.12), at)
	paper.rotation.z = -0.09
	var tape := _mesh(_cbox(Vector3(0.7 * PX, 0.22 * PX, 0.005)), _mat(Color(0.78, 0.72, 0.5, 1.0), 0.5), at + Vector3(0.0, 0.92 * PX, 0.002))
	tape.rotation.z = -0.09
	var mark := _mesh(_cbox(Vector3(0.16 * PX, 0.8 * PX, 0.002)), _mat(Color(0.72, 0.1, 0.06), 0.8), at + Vector3(0.03 * PX, 0.18 * PX, 0.003))
	mark.rotation.z = -0.09
	_mesh(_cbox(Vector3(0.16 * PX, 0.16 * PX, 0.002)), _mat(Color(0.72, 0.1, 0.06), 0.8), at + Vector3(-0.05 * PX, -0.5 * PX, 0.003))
