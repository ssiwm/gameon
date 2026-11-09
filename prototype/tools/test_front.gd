extends SceneTree
## Test pierwszego planu przed płaszczyzną gry (`scripts/front3d.gd`, `FOREGROUND_PLAN.md`) na wszystkich mapach z scripts/maps:
## (1) dane `FRONT` / `FRONT_SKIP`: znany zestaw, kolumny i wiersze w mapie, c0 < c1, r0 < r1,
## (2) rozmieszczenie: z w Z_RANGE, element w zakresie wpisu z zapasem, duże elementy co najmniej BIG_SPACING.x od siebie także
##     między wpisami, których pasy mieszczą się razem w kadrze (najwyżej jeden duży element w kadrze NORMAL; piętra z przekrojem
##     rozdzielone płytą liczą się osobno — `Front3D.apart`), mały element
##     co najmniej SMALL_MIN od dużego, `FRONT_SKIP` pusty, na LOW bez małych, ten sam układ przy każdym wywołaniu,
## (3) bryły: tylko warstwa `LAYER_FRONT` (rozłączna z warstwami świata, lasu, dna lasu i wnęk), bez cienia, bez kolizji,
##     części rur z `pipe_parts.glb` (odcinek, zawór, trójnik, cienka rura) i tekstury zestawu, każda powierzchnia z materiałem
##     pierwszego planu (półprzezroczysty, z wygaszaniem), pas przycięcia w parametrze instancji; OFF chowa całość,
## (4) przekrój budynku (F2b): kafle strefy tylko w stropie i podłodze z fundamentem (nigdy ściany w pasie gry ani strefy wydobycia),
##     element na płycie (nie w cieczy), kołnierz przed przodem przekroju, ≥ 1 m od belki pod stropem; plama okluzji i płytka;
##     nad torowiskiem drezyny element stoi na podsypce (płyta na wysokości dna koryta), pod dachem z blachy wisi pod płatwią,
##     wyciek oleju w hali 1.2 (`Level3D.oil_spills`): plama w zasięgu płyty, przewrócona beczka na płycie przed niecką i niżej niż linia
##     podłogi w rzucie, stojące za płaszczyzną gry poza niecką, element nie stoi w plamie,
## (5) las (zestaw „forest”, F3): pnie sosny, brzozy i martwy, zwisające gałęzie, paprocie i trawa; pas otwarty w pionie (przycięcie tylko
##     w poziomie, z zapasem OPEN_PAD), pień od podłoża (nasada pod nim, `ywin` na podłożu) nad górny brzeg kadru NORMAL, kępa na podłożu
##     bliżej kamery (CLUMP_Z) z wierzchem w rzucie pod linią podłogi, kontra księżyca tylko na materiałach lasu (rury i ściany przekroju
##     bez niej), karty z alfą i dwustronne, `set_moon` zmienia tylko las; podłoże przed płaszczyzną gry: płyta w warstwie świata z materiałem
##     bryły gruntu, nie wyżej niż grunt kolumny przy bryle, w rzucie zawsze pod linią podłogi (trzy kamery, gracz wyżej i niżej), płasko
##     pod elementami, runo w rzucie najwyżej przy stopach, na mapach nie wyżej niż wierzch gruntu żadnej kolumny pasa i bez wejścia
##     w przekrój obok,
## (6) wygaszanie: `Front3D.fade` (ta sama funkcja co w shaderze) daje MIN_A na sylwetce, pełne krycie od FADE_M, rośnie z odległością,
##     waga 0 nie wygasza wcale.
## godot --headless --path prototype -s tools/test_front.gd       → ma wypisać PASS
const Level3D := preload("res://scripts/level3d.gd")
const Niches3D := preload("res://scripts/niches3d.gd")
const Front3D := preload("res://scripts/front3d.gd")
const LAYER_WORLD := 1                    ## view3d.gd LAYER_WORLD
const LAYER_ACTORS := 2                   ## view3d.gd LAYER_ACTORS
const FRAME_H_NORMAL := Front3D.FRAME_H_NORMAL
var _frames := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL  " + msg)
		_fail += 1

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var dir := DirAccess.open("res://scripts/maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	var total := 0
	for f in names:
		var consts := (load("res://scripts/maps/" + f) as GDScript).get_script_constant_map()
		var front: Array = consts.get("FRONT", [])
		if front.is_empty():
			continue
		total += front.size()
		_check_map(f.get_basename(), consts.get("MAP", []), front, consts.get("FRONT_SKIP", []))
		_check_shell(f.get_basename(), consts.get("MAP", []), front, consts.get("FRONT_SKIP", []), consts.get("DIG_ZONES", []))
	_check(total > 0, "żadna mapa nie ma pierwszego planu (pilot na z1_m2)")
	_check_skip()
	_check_layers()
	_check_trench()
	_check_roof()
	_check_oil()
	_check_forest()
	_check_fade()
	print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
	quit(0 if _fail == 0 else 1)
	return true


func _check_map(map_id: String, rows: Array, front: Array, skip: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	for e: Dictionary in front:
		var tag := "%s %s" % [map_id, e]
		_check(Front3D.SETS.has(String(e.get("set", ""))), tag + ": nieznany zestaw")
		_check(int(e["c0"]) >= 0 and int(e["c1"]) < cols and int(e["c0"]) < int(e["c1"]), tag + ": kolumny poza mapą albo c0 ≥ c1")
		_check(int(e["r0"]) >= 0 and int(e["r1"]) < nrows and int(e["r0"]) < int(e["r1"]), tag + ": wiersze poza mapą albo r0 ≥ r1")
	for s in skip:
		_check(s is Array and (s as Array).size() == 2 and int(s[0]) <= int(s[1]), "%s FRONT_SKIP %s: oczekiwane [c0, c1]" % [map_id, s])
	var bl := Front3D.blocked_x(front, rows)                 # przekrój (F2b): bez kałuż na płycie i belek pod stropem
	var items := Front3D.layout(front, skip, false, bl)
	_check_map_ground(map_id, rows, front, items)
	_check(not items.is_empty(), map_id + ": wpisy FRONT bez żadnego elementu")
	_check(str(items) == str(Front3D.layout(front, skip, false, bl)), map_id + ": układ różni się między wywołaniami (ziarno)")
	for it: Dictionary in items:
		var clip: Vector4 = it["clip"]
		var x: float = it["x"]
		var z: float = it["z"]
		_check(z >= Front3D.Z_RANGE.x and z <= Front3D.Z_RANGE.y, "%s %s x %.1f: z %.2f poza Z_RANGE" % [map_id, it["kind"], x, z])
		_check(x >= clip.x + Front3D.MARGIN - 0.01 and x <= clip.y - Front3D.MARGIN + 0.01, "%s %s x %.1f: poza zakresem wpisu" % [map_id, it["kind"], x])
		_check(bool(it["big"]) == (String(it["kind"]) in Front3D.BIG_KINDS), "%s %s: zła klasa dużego elementu" % [map_id, it["kind"]])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var ca: Vector4 = a["clip"]
			var cb: Vector4 = b["clip"]
			if Front3D.apart(ca, bool(a["shell"]), cb, bool(b["shell"])):        # pasy dalej niż kadr albo piętra rozdzielone płytą przekroju
				continue
			var dx := absf(float(a["x"]) - float(b["x"]))
			if bool(a["big"]) and bool(b["big"]):
				_check(dx >= Front3D.BIG_SPACING.x - 0.01, "%s: dwa duże elementy %.1f m od siebie (x %.1f i %.1f), dwa w jednym kadrze" % [map_id, dx, a["x"], b["x"]])
			elif bool(a["big"]) != bool(b["big"]):
				_check(dx >= Front3D.SMALL_MIN - 0.01, "%s: mały element %.1f m od dużego (x %.1f i %.1f)" % [map_id, dx, a["x"], b["x"]])
	for it: Dictionary in Front3D.layout(front, skip, true, bl):
		_check(bool(it["big"]), "%s: na LOW został mały element %s x %.1f" % [map_id, it["kind"], it["x"]])


## Przekrój budynku (F2b, `Level3D.set_shells`): kafle strefy to lite kafle stropu (r0) i podłogi z fundamentem (od r1 w dół), nigdy
## ściany w pasie gry (wysunięte zasłaniałyby wrogów w rzucie) ani strefy wydobycia; element pierwszego planu stoi na płycie z betonu
## lub gruntu (nie w cieczy), z kołnierzem przed przodem przekroju, co najmniej 1 m od belek pod stropem (belka w warstwie świata)
## i nie przed stanowiskiem w pasie wpisu (`Front3D.STATION_CH` ± `STATION_PAD`; wygaszanie obejmuje tylko postacie).
func _check_shell(map_id: String, rows: Array, front: Array, skip: Array, digs: Array) -> void:
	Level3D.set_shells(front, rows, digs)
	var shelled := front.filter(func(e: Dictionary) -> bool: return bool(e.get("shell", false)))
	_check(shelled.is_empty() or not Level3D.shell_cells.is_empty(), map_id + ": wpis z przekrojem bez kafli przekroju")
	for k: Vector2i in Level3D.shell_cells:
		var ch := String(rows[k.y]).substr(k.x, 1)
		_check(ch in Level3D.SHELL_CH, "%s %s: kafel przekroju '%s' nie jest litym kaflem" % [map_id, k, ch])
		for e: Dictionary in shelled:
			if k.x >= int(e["c0"]) and k.x <= int(e["c1"]):
				_check(k.y <= int(e["r0"]) or k.y >= int(e["r1"]), "%s %s: kafel przekroju w pasie gry (ściana wysunięta ku kamerze)" % [map_id, k])
		for z in digs:
			_check(not (k.x >= int(z[0]) and k.x <= int(z[2]) and k.y >= int(z[1]) and k.y <= int(z[3])), "%s %s: przekrój w strefie wydobycia" % [map_id, k])
	var ribs: Array = Level3D.interior_ribs(rows).map(func(rb: Dictionary) -> float: return (float(int(rb["c"])) + 0.5) * Level3D.T)
	for it: Dictionary in Front3D.layout(front, skip, false, Front3D.blocked_x(front, rows)):
		if not bool(it["shell"]):
			continue
		var x: float = it["x"]
		var c := int(floor(x / Level3D.T))
		var r1 := roundi(-(it["clip"] as Vector4).z / Level3D.T)
		var below := String(rows[r1]).substr(c, 1)
		_check(Level3D.in_shell(c, r1) and not below in "O~m", "%s %s x %.1f: nie stoi na płycie przekroju ('%s')" % [map_id, it["kind"], x, below])
		_check(float(it["z"]) + 0.45 < Level3D.SHELL_Z, "%s %s x %.1f: kołnierz wystaje przed przekrój" % [map_id, it["kind"], x])
		if bool(it["big"]):
			for rx: float in ribs:
				_check(absf(rx - x) >= 1.0, "%s %s x %.1f: %.2f m od belki pod stropem (x %.1f)" % [map_id, it["kind"], x, absf(rx - x), rx])
		# stanowisko w pasie wpisu (kryjówka): element nie stoi przed nim, wygaszanie obejmuje tylko postacie
		for r in range(roundi(-(it["clip"] as Vector4).w / Level3D.T) + 1, r1):
			for cc in String(rows[r]).length():
				if String(rows[r]).substr(cc, 1) in Front3D.STATION_CH:
					var sx0 := float(cc) * Level3D.T - Front3D.STATION_PAD
					var sx1 := float(cc + 1) * Level3D.T + Front3D.STATION_PAD
					var clip: Vector4 = it["clip"]
					if sx1 > clip.x and sx0 < clip.y:
						_check(x < sx0 or x > sx1, "%s %s x %.1f: przed stanowiskiem '%s' (%d, %d)" % [map_id, it["kind"], x, String(rows[r]).substr(cc, 1), cc, r])
	_check_walls(map_id, rows, digs)
	Level3D.set_shells([], rows)


## Ściany przekroju (`Level3D.shell_walls`): lite ściany w pasie wpisu i nadproża między przekrojami o różnym stropie, wysunięte do
## przodu przekroju na osobnej warstwie `Front3D.LAYER_WALL` (z wygaszaniem, bez światła obrysu postaci). Tylko kafle ścian (`WALL_CH`),
## nigdy kafle płyt (`shell_cells`) ani strefa wydobycia; `occ` tnie część za płytą stropu i podłogi.
func _check_walls(map_id: String, rows: Array, digs: Array) -> void:
	for k: Vector2i in Level3D.shell_walls:
		var ch := String(rows[k.y]).substr(k.x, 1)
		_check(ch in Level3D.WALL_CH, "%s %s: ściana przekroju na kaflu '%s'" % [map_id, k, ch])
		_check(not Level3D.shell_cells.has(k), "%s %s: ściana przekroju na kaflu płyty" % [map_id, k])
		for z in digs:
			_check(not (k.x >= int(z[0]) and k.x <= int(z[2]) and k.y >= int(z[1]) and k.y <= int(z[3])), "%s %s: ściana przekroju w strefie wydobycia" % [map_id, k])
		# tylko kolumna lita na całą wysokość pasa: przy oknie, drzwiach albo przejściu ściana zostaje w płaszczyźnie gry
		for e: Dictionary in Level3D.shell_bands:
			if k.x >= int(e["c0"]) and k.x <= int(e["c1"]) and k.y > int(e["r0"]) and k.y < int(e["r1"]):
				for r in range(int(e["r0"]) + 1, int(e["r1"])):
					var cr := String(rows[r]).substr(k.x, 1)
					var dug := false
					for z in digs:
						dug = dug or (k.x >= int(z[0]) and k.x <= int(z[2]) and r >= int(z[1]) and r <= int(z[3]))
					_check(cr in Level3D.WALL_CH or dug, "%s %s: ściana przekroju w kolumnie z otworem ('%s' w wierszu %d)" % [map_id, k, cr, r])
		var w: Array = Level3D.shell_walls[k]
		_check(String(w[0]) in Front3D.WALL_TEX, "%s %s: ściana bez tekstury ('%s')" % [map_id, k, w[0]])
		var occ: Vector4 = w[1]
		_check(occ.x > occ.y, "%s %s: pusty pas okluzji ściany" % [map_id, k])
	for z in digs:
		var zf := Level3D.zone_front_z(int(z[0]), int(z[1]), int(z[2]), int(z[3]))
		_check(is_equal_approx(zf, Level3D.DEPTH_FRONT) or is_equal_approx(zf, Level3D.SHELL_Z), "%s: przód strefy wydobycia %.2f" % [map_id, zf])
	if map_id in ["z1_m3", "z1_hub"]:
		_check(not Level3D.shell_walls.is_empty(), map_id + ": brak ścian przekroju")
		var root := Node3D.new()
		get_root().add_child(root)
		var n := Front3D.build_walls(root)
		_check(n > 0, map_id + ": build_walls nic nie zbudował")
		for c in root.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := c as MultiMeshInstance3D
			_check(mmi.layers == Front3D.LAYER_WALL and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: ściana %s ze złą warstwą albo z cieniem" % [map_id, mmi.name])
		root.free()
	if map_id == "z1_m3":
		# 1.3: nadproże nad niskim tunelem obok sali (skała między stropem tunelu a stropem sali) to płyta świata, nie ściana pierwszego planu
		_check(Level3D.shell_cells.has(Vector2i(91, 32)) and not Level3D.shell_walls.has(Vector2i(91, 32)), "1.3: nadproże nad tunelem 91–108 nie jest płytą przekroju")
		# 1.3: strefa kopania przy zachodniej hali stoi w jednej płaszczyźnie z podłogą przekroju
		_check(is_equal_approx(Level3D.zone_front_z(1, 31, 5, 39), Level3D.SHELL_Z), "1.3: strefa wydobycia przy hali nie wysunięta do przekroju")
		var muds := Level3D.mud_spills(rows)
		_check(muds.size() >= 2, "1.3: %d plam błota (start i hala)" % muds.size())
		for sp: Dictionary in muds:
			_check(int(sp["mode"]) == 1 and (sp["blobs"] as Array).size() == Level3D.OIL_BLOBS, "błoto: tryb albo liczba metakul (tablica w shaderze)")
			var zr: Vector2 = sp["zr"]
			_check(zr.y <= Level3D.SHELL_Z and zr.x >= -Level3D.DEPTH_BACK, "błoto: plama poza płytą (z %.2f–%.2f)" % [zr.x, zr.y])


## FRONT_SKIP: zakres bez pierwszego planu nie dostaje żadnego elementu (z zapasem MARGIN).
func _check_skip() -> void:
	var front := [{"set": "station", "c0": 0, "c1": 199, "r0": 0, "r1": 8}]
	var skip := [[60, 120]]
	var all := Front3D.layout(front, [])
	var left := Front3D.layout(front, skip)
	_check(left.size() < all.size(), "FRONT_SKIP nic nie zabrał")
	for it: Dictionary in left:
		var x: float = it["x"]
		_check(x < 60.0 * Level3D.T - Front3D.MARGIN or x > 121.0 * Level3D.T + Front3D.MARGIN, "FRONT_SKIP: element %s x %.1f w zakresie pominiętym" % [it["kind"], x])


func _check_layers() -> void:
	var lf := Front3D.LAYER_FRONT
	for other in [LAYER_WORLD, LAYER_ACTORS, Level3D.LAYER_FOREST, Level3D.LAYER_FAR, Niches3D.LAYER_NICHE]:
		_check(lf & int(other) == 0, "LAYER_FRONT nachodzi na warstwę %d" % other)
	for other in [LAYER_WORLD, LAYER_ACTORS, Level3D.LAYER_FOREST, Level3D.LAYER_FAR, Niches3D.LAYER_NICHE, lf]:
		_check(Front3D.LAYER_WALL & int(other) == 0, "LAYER_WALL nachodzi na warstwę %d" % other)
	var root := Node3D.new()
	get_root().add_child(root)
	var front := [{"set": "station", "c0": 0, "c1": 120, "r0": 2, "r1": 10, "shell": true}, {"set": "tunnel", "c0": 0, "c1": 120, "r0": 30, "r1": 37}]
	var n := Front3D.build(root, front, [], false)
	var fr := root.get_node_or_null("Front")
	_check(fr != null and n > 0, "build nie zbudował węzła Front")
	if fr == null:
		return
	var kinds := {}
	var shell_parts := {}
	for c in fr.get_children():
		_check(c is MeshInstance3D, "Front: dziecko %s nie jest MeshInstance3D" % c.name)
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		kinds[String(mi.name).get_slice("_", 0)] = true
		_check(mi.layers == lf, "%s: warstwy %d zamiast LAYER_FRONT" % [mi.name, mi.layers])
		_check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: rzuca cień" % mi.name)
		for ch in mi.get_children():
			# dzieci: światło żarówki lampy (tylko na pierwszy plan), a przy przekroju (F2b) plama okluzji na płycie (warstwa świata,
			# leży pod graczami) i płytka pod stropem (LAYER_FRONT); nic z kolizją ani cieniem
			if ch is OmniLight3D:
				_check((ch as OmniLight3D).light_cull_mask == lf and not (ch as OmniLight3D).shadow_enabled, "%s: światło %s nie tylko na LAYER_FRONT albo z cieniem" % [mi.name, ch.name])
			elif ch is MeshInstance3D and (ch.name == "Contact" or ch.name == "Plate"):
				var cm := ch as MeshInstance3D
				_check(cm.layers == (LAYER_WORLD if ch.name == "Contact" else lf) and cm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s ze złą warstwą albo z cieniem" % [mi.name, ch.name])
				shell_parts[ch.name] = true
			else:
				_check(false, "%s: nieoczekiwane dziecko %s (kolizja?)" % [mi.name, ch.name])
		_check(mi.mesh != null and mi.mesh.get_surface_count() > 0, "%s: pusta siatka" % mi.name)
		if mi.mesh != null:
			for si in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(si) as ShaderMaterial
				_check(mat != null and "blend_mix" in mat.shader.code and "ALPHA = a" in mat.shader.code, "%s: powierzchnia %d bez materiału pierwszego planu (wygaszanie)" % [mi.name, si])
		var clip: Variant = mi.get_instance_shader_parameter("clip")
		_check(clip is Vector4 and (clip as Vector4).y > (clip as Vector4).x and (clip as Vector4).w > (clip as Vector4).z, "%s: brak pasa przycięcia" % mi.name)
	for k in ["pipe", "pipes2", "cables", "chain", "lamp"]:
		_check(kinds.has(k), "rodzaj %s nie powstał na długim zakresie" % k)
	_check(shell_parts.has("Contact") and shell_parts.has("Plate"), "wpis z przekrojem: duży element bez plamy okluzji albo płytki pod stropem")
	Front3D.apply_settings(2, false)
	_check(not (fr as Node3D).visible, "OFF nie chowa pierwszego planu")
	Front3D.apply_settings(0, false)
	_check((fr as Node3D).visible, "ON nie pokazuje pierwszego planu")
	_check(Front3D.build(root, [], [], false) == 0, "pusty FRONT coś zbudował")
	root.queue_free()


## Parametr materiału albo `def`, gdy nieustawiony (domyślna wartość z shadera); bool jako 0/1.
func _par(m: ShaderMaterial, name: String, def: float) -> float:
	var v: Variant = m.get_shader_parameter(name)
	if v == null:
		return def
	return (1.0 if v else 0.0) if v is bool else float(v)


## Las (F3): rodzaje, otwarty pas, wysokość pnia względem kadru, kontra księżyca tylko na lesie, karty z alfą.
func _check_forest() -> void:
	var st: Dictionary = Front3D.SETS.get("forest", {})
	_check(bool(st.get("open", false)), "zestaw forest bez otwartego pasa")
	var root := Node3D.new()
	get_root().add_child(root)
	var e := {"set": "forest", "c0": 0, "c1": 400, "r0": 0, "r1": 26}
	var y_floor := -26.0 * Level3D.T
	var n := Front3D.build(root, [e, {"set": "tunnel", "c0": 0, "c1": 400, "r0": 40, "r1": 47}], [], false)
	var fr := root.get_node_or_null("Front")
	_check(fr != null and n > 0, "las: build nic nie zbudował")
	if fr == null:
		return
	var kinds := {}
	var clip0 := Front3D.clip_of(e)
	for c in fr.get_children():
		var mi := c as MeshInstance3D
		var kind := String(mi.name).get_slice("_", 0)
		if not kind in ["pine", "birch", "snag", "bough", "ferns", "grass"]:
			for si in mi.mesh.get_surface_count():                # rury w tunelu: bez kontry księżyca
				var pm := mi.get_surface_override_material(si) as ShaderMaterial
				_check(_par(pm, "rim_k", 0.0) == 0.0 and _par(pm, "trans_k", 0.0) == 0.0, "%s: kontra księżyca pod ziemią" % mi.name)
			continue
		kinds[kind] = true
		_check(mi.layers == Front3D.LAYER_FRONT and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: warstwa albo cień" % mi.name)
		var clip: Vector4 = mi.get_instance_shader_parameter("clip")
		_check(clip.z < -1e5 and clip.w > 1e5, "%s: las przycięty w pionie" % mi.name)
		_check(is_equal_approx(clip.x, clip0.x - Front3D.OPEN_PAD) and is_equal_approx(clip.y, clip0.y + Front3D.OPEN_PAD), "%s: przycięcie w poziomie bez zapasu OPEN_PAD" % mi.name)
		var bb := mi.mesh.get_aabb()
		var yg := Front3D.ground_y(mi.position.x, mi.position.z)
		var yw: Variant = mi.get_instance_shader_parameter("ywin")
		if kind != "bough":
			_check(yw is Vector2 and absf((yw as Vector2).x - yg) < 0.001 and absf(yg - y_floor) < 0.001, "%s: nasada nie kończy się na podłożu (ywin %s, podłoże %.3f)" % [mi.name, yw, yg - y_floor])
			for dx in [-1.0, 0.0, 1.0]:                          # płasko pod elementem (nierówność podłoża nie wchodzi nad nasadę)
				_check(absf(Front3D.ground_y(mi.position.x + dx, mi.position.z) - yg) < 0.001, "%s: podłoże pod elementem nierówne" % mi.name)
		if kind in ["pine", "birch", "snag"]:
			# nasada (szyja, korzenie) schodzi pod podłoże, koniec nad górnym brzegiem kadru NORMAL (ok. 8 m nad podłogą przy z = 3,5–5 m)
			_check(bb.position.y < yg - 0.2 and bb.position.y > yg - 1.0 and bb.end.y > y_floor + FRAME_H_NORMAL * 0.75, "%s: pień nie stoi na podłożu albo nie sięga nad kadr (%.1f..%.1f wzgl. podłoża)" % [mi.name, bb.position.y - yg, bb.end.y - yg])
		elif kind == "bough":
			_check(bb.end.y > y_floor + FRAME_H_NORMAL * 0.5 and bb.position.y > y_floor + 3.0, "%s: gałąź nie wisi przy górnym brzegu" % mi.name)
		else:
			var z := mi.position.z
			_check(z >= Front3D.CLUMP_Z.x and z <= Front3D.CLUMP_Z.y, "%s: kępa w z %.2f poza CLUMP_Z" % [mi.name, z])
			_check(bb.end.y > yg + 0.4 and bb.end.y < yg + Front3D.CLUMP_H.y, "%s: kępa %.2f m nad podłożem" % [mi.name, bb.end.y - yg])
			_check(_proj(bb.end.y, z, y_floor + 5.3, 20.2) < y_floor, "%s: wierzch kępy w rzucie nad linią podłogi" % mi.name)
		var rims := 0
		var bases := 0
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si) as ShaderMaterial
			var card := _par(m, "cutout", 0.0) > 0.0
			var mk := ""
			for k2: String in Front3D.materials():
				if Front3D.materials()[k2] == m:
					mk = k2
			if card:
				_check(_par(m, "trans_k", 0.0) > 0.0 and "cull_disabled" in m.shader.code, "%s: karta bez prześwitu albo jednostronna" % mi.name)
			elif mk.ends_with(":base"):
				bases += 1
				_check(_par(m, "rim_k", 0.0) == 0.0, "%s: nasada pnia z kontrą księżyca" % mi.name)
			else:
				rims += 1
				_check(_par(m, "rim_k", 0.0) > 0.0, "%s: kora bez kontry księżyca" % mi.name)
		if kind in ["pine", "birch", "snag"]:
			_check(rims == 1 and bases == 1, "%s: pień bez osobnej kory nasady (kora %d, nasada %d)" % [mi.name, rims, bases])
	for k in ["pine", "birch", "snag", "bough", "ferns", "grass"]:
		_check(kinds.has(k), "las: rodzaj %s nie powstał na długim zakresie" % k)
	Front3D.set_moon(0.25)
	for c in fr.get_children():
		var mi := c as MeshInstance3D
		var m := mi.get_surface_override_material(0) as ShaderMaterial
		var forest := String(mi.name).get_slice("_", 0) in ["pine", "birch", "snag", "bough", "ferns", "grass"]
		_check(is_equal_approx(_par(m, "moon", 1.0), 0.25 if forest else 1.0), "%s: set_moon nie działa tylko na las" % mi.name)
	Front3D.set_moon(1.0)
	_check_ground(root, y_floor)
	Front3D.build(root, [], [], false)
	root.queue_free()


## y punktu (y, z) w rzucie na płaszczyznę gry z kamery na wysokości `cy`, `d` m przed nią.
func _proj(y: float, z: float, cy: float, d: float) -> float:
	return cy + (y - cy) * d / (d - z)


## Podłoże lasu z `_check_forest` (płaski grunt w wierszu 26): płyta w warstwie świata z materiałem bryły `#`, przy bryle na wierzchu
## gruntu, w rzucie pod linią podłogi z każdej kamery (WIDE / NORMAL / CLOSE; kamera nisko, jak gracz przy podłodze, i wysoko), runo
## w rzucie najwyżej przy stopach; tunel (wpis bez „open”) bez podłoża.
func _check_ground(root: Node3D, y_floor: float) -> void:
	var g := root.get_node_or_null("FrontGround") as MeshInstance3D
	_check(g != null, "las: brak podłoża FrontGround")
	if g == null:
		return
	_check(g.layers == LAYER_WORLD and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "podłoże: warstwa albo cień")
	_check(g.material_override == Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic"), "podłoże: inny materiał niż bryła gruntu")
	var bb := g.mesh.get_aabb()
	_check(bb.end.z >= float(Front3D.GROUND_Z[Front3D.GROUND_Z.size() - 1]) - 0.01 and bb.position.z < Level3D.DEPTH_FRONT, "podłoże: nie sięga od bryły do %.0f m (%.2f..%.2f)" % [Front3D.GROUND_Z[Front3D.GROUND_Z.size() - 1], bb.position.z, bb.end.z])
	var verts: PackedVector3Array = g.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bad := 0
	for v in verts:
		if v.z <= Level3D.DEPTH_FRONT and v.y > y_floor - 0.01:
			continue                                        # pierwszy rząd pod wierzchem bryły
		if v.z <= 1.6 and v.y > y_floor + 0.001:
			bad += 1
		for d: float in [16.85, 20.2, 25.3]:
			for cy: float in [y_floor + 2.0, y_floor + 5.3, y_floor + 9.0]:
				if _proj(v.y, v.z, cy, d) > y_floor + 0.001:
					bad += 1
	_check(bad == 0, "podłoże: %d punktów nad gruntem przy bryle albo w rzucie nad linią podłogi" % bad)
	var cards := 0
	for c in root.get_children():
		var mm := c as MultiMeshInstance3D
		if mm != null and String(mm.name).begins_with("FrontGround_"):
			cards += mm.multimesh.instance_count
	_check(cards > 100 and cards == Front3D.cover_tops.size(), "podłoże: %d kart runa (zapis wierzchołków: %d)" % [cards, Front3D.cover_tops.size()])
	for t: Vector2 in Front3D.cover_tops:
		if _proj(t.x, t.y, y_floor + 5.3, 20.2) > y_floor + 0.35:
			bad += 1
	_check(bad == 0, "podłoże: %d kart runa w rzucie wyżej niż stopy" % bad)
	var r2 := Node3D.new()
	get_root().add_child(r2)
	Front3D.build(r2, [{"set": "tunnel", "c0": 0, "c1": 120, "r0": 2, "r1": 10, "shell": true}], [], false)
	_check(r2.get_node_or_null("FrontGround") == null, "tunel: podłoże bez wpisu otwartego")
	r2.queue_free()


## Podłoże na mapie: przy bryle (z = DEPTH_FRONT) nie wyżej niż wierzch gruntu kolumny i obu sąsiednich w pasie wpisu otwartego
## (pierwszy lity kafel pod stropem pasa) — rzut przesunięty w poziomie nie wejdzie nad niższy grunt; nie wchodzi w przekrój obok.
func _check_map_ground(map_id: String, rows: Array, front: Array, items: Array) -> void:
	Front3D.prepare_ground(front, rows, items)
	var T := Level3D.T
	var cols: int = (rows[0] as String).length()
	for e: Dictionary in front:
		if not bool((Front3D.SETS[e["set"]] as Dictionary).get("open", false)):
			continue
		for c in range(int(e["c0"]), int(e["c1"]) + 1):
			var y := Front3D.ground_y((float(c) + 0.5) * T, Level3D.DEPTH_FRONT)
			for cc in [c - 1, c, c + 1]:
				var r := int(e["r0"]) + 1
				while r < rows.size() and not Level3D.is_solid_ch(Level3D._ch(rows, clampi(cc, 0, cols - 1), r)):
					r += 1
				_check(y <= -float(r) * T + 0.001, "%s kolumna %d: podłoże %.2f m nad gruntem kolumny %d" % [map_id, c, y + float(r) * T, cc])
		for o: Dictionary in front:
			if bool(o.get("shell", false)) and absi(int(o["r1"]) - int(e["r1"])) <= 4:
				for x in [float(o["c0"]) * T + 0.3, float(int(o["c1"]) + 1) * T - 0.3]:
					_check(Front3D.ground_y(x, 3.0) == -INF, "%s: podłoże lasu wchodzi w przekrój %s (x %.1f)" % [map_id, o["set"], x])
	Front3D.prepare_ground([], rows, [])


## Torowisko drezyny w strefie przekroju (`Level3D.in_trench`): płyta leży na wysokości dna koryta (pełna płyta zasłoniłaby szyny i koła),
## więc element nad torowiskiem stoi na podsypce — dolna granica `ywin` o `TRENCH_D` niżej niż obok torowiska.
func _check_trench() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var T := Level3D.T
	Level3D.rail_trench = {"row": 10, "c0": 0, "c1": 60}
	Front3D.build(root, [{"set": "tunnel", "c0": 0, "c1": 120, "r0": 2, "r1": 10, "shell": true}], [], false)
	Level3D.rail_trench = {}
	var fr := root.get_node_or_null("Front")
	var seen := [0, 0]
	if fr != null:
		for c in fr.get_children():
			var mi := c as MeshInstance3D
			var yw: Variant = mi.get_instance_shader_parameter("ywin")
			if not (yw is Vector2):
				continue
			var inside := int(floorf(mi.position.x / T)) <= 60
			var want := -10.0 * T - (Level3D.TRENCH_D if inside else 0.0)
			_check(absf((yw as Vector2).x - want) < 0.001, "%s x %.1f: podstawa %.3f m zamiast %.3f (%s torowiska)" % [mi.name, mi.position.x, (yw as Vector2).x, want, "nad dnem" if inside else "obok"])
			seen[0 if inside else 1] += 1
	_check(seen[0] > 0 and seen[1] > 0, "torowisko: brak elementów nad torowiskiem albo obok (%d / %d)" % seen)
	root.queue_free()

## Dach z blachy w strefie przekroju (hala stacji 1.2, `Level3D.roof_purlins`): pod dachem nie ma stropu, więc element wisi pod płatwią —
## stoi na jej głębokości i kończy się na jej spodzie (górna granica `ywin`), a nie płytką w powietrzu pod wiązarami.
func _check_roof() -> void:
	var consts: Dictionary = (load("res://scripts/maps/z1_m2.gd") as Script).get_script_constant_map()
	var rows: Array = consts["MAP"]
	var front: Array = (consts["FRONT"] as Array).filter(func(e: Dictionary) -> bool: return String(e["set"]) == "station")
	_check(not front.is_empty(), "z1_m2: brak wpisu hali stacji")
	if front.is_empty():
		return
	var e: Dictionary = front[0]
	Level3D.set_shells(front, rows)
	var root := Node3D.new()
	get_root().add_child(root)
	Front3D.build(root, front, [], false, rows)
	var fr := root.get_node_or_null("Front")
	var n := 0
	if fr != null:
		for c in fr.get_children():
			var mi := c as MeshInstance3D
			var rp := Level3D.roof_purlins(rows, int(floorf(mi.position.x / Level3D.T)), int(e["r0"]))
			var yw: Variant = mi.get_instance_shader_parameter("ywin")
			if rp.is_empty() or not (yw is Vector2):
				continue
			n += 1
			_check(absf((yw as Vector2).y - float(rp[0])) < 0.001, "%s: góra %.3f m zamiast spodu płatwi %.3f" % [mi.name, (yw as Vector2).y, float(rp[0])])
			_check((rp[1] as Array).any(func(pz: float) -> bool: return absf(pz - mi.position.z) < 0.001), "%s: z %.2f nie pod płatwią" % [mi.name, mi.position.z])
			_check(mi.position.z + 0.45 < Level3D.SHELL_Z, "%s: kołnierz przed przekrojem (z %.2f)" % [mi.name, mi.position.z])
	_check(n > 0, "hala stacji: żaden element nie wisi pod dachem")
	# zasłanianie płytą (shader `occ`): każdy element z przekrojem i jego płytka znają spód stropu / dachu i przód płyty
	if fr != null:
		for c in fr.get_children():
			var mi := c as MeshInstance3D
			var oc: Variant = mi.get_instance_shader_parameter("occ")
			var yw: Variant = mi.get_instance_shader_parameter("ywin")
			_check(oc is Vector4 and yw is Vector2 and absf((oc as Vector4).x - (yw as Vector2).y - 0.02) < 0.001 and (oc as Vector4).z >= Level3D.SHELL_Z, "%s: brak zasłaniania stropem / dachem (occ)" % mi.name)
			var pl := mi.get_node_or_null("Plate") as MeshInstance3D
			if pl != null:
				_check(pl.get_instance_shader_parameter("occ") == oc, "%s: płytka bez zasłaniania (occ)" % mi.name)
	# otwór w stropie (kratka szybu nad tunelem, kolumny 273–276): element nie stoi pod nim
	var tun: Array = (consts["FRONT"] as Array).filter(func(t: Dictionary) -> bool: return String(t["set"]) == "tunnel")
	for it: Dictionary in Front3D.layout(tun, [], false, Front3D.blocked_x(tun, rows)):
		var cx := int(floorf(float(it["x"]) / Level3D.T))
		_check(String(rows[int(tun[0]["r0"])]).substr(cx, 1) in Level3D.SHELL_CH, "tunel: %s x %.1f pod otworem w stropie" % [it["kind"], float(it["x"])])
	Level3D.set_shells([], rows)
	root.queue_free()

## Wyciek oleju (`Level3D.oil_spills`) w hali stacji 1.2: dane plamy i beczek oraz rura poza plamą.
func _check_oil() -> void:
	var consts: Dictionary = (load("res://scripts/maps/z1_m2.gd") as Script).get_script_constant_map()
	var rows: Array = consts["MAP"]
	var front: Array = (consts["FRONT"] as Array).filter(func(e: Dictionary) -> bool: return String(e["set"]) == "station")
	Level3D.set_shells(front, rows)
	var spills := Level3D.oil_spills(rows)
	_check(spills.size() == 1, "hala 1.2: %d wycieków oleju zamiast 1" % spills.size())
	for sp: Dictionary in spills:
		var pit: Vector3 = sp["pit"]
		var zr: Vector2 = sp["zr"]
		_check((sp["blobs"] as Array).size() == Level3D.OIL_BLOBS, "wyciek: liczba metakul różna od OIL_BLOBS (tablica w shaderze)")
		_check(zr.y <= Level3D.SHELL_Z and zr.x >= -Level3D.DEPTH_BACK, "wyciek: plama poza płytą (z %.2f–%.2f)" % [zr.x, zr.y])
		var lying := 0
		for b: Dictionary in sp["barrels"]:
			var p: Vector3 = b["pos"]
			var c := (b["basis"] as Basis) * Vector3.UP * Level3D.OIL_BARREL_H * 0.5 + p     # środek beczki
			var outside := c.x + Level3D.OIL_BARREL_R < pit.x or c.x - Level3D.OIL_BARREL_R > pit.y
			if bool(b["lying"]):
				lying += 1
				_check(c.z > Level3D.DEPTH_FRONT + Level3D.OIL_BARREL_R and c.z + Level3D.OIL_BARREL_R < Level3D.SHELL_Z, "wyciek: przewrócona beczka poza płytą przekroju (z %.2f)" % c.z)
				_check(outside, "wyciek: przewrócona beczka nad niecką")
				# rzut wierzchu beczki na płaszczyznę gry przy kamerze NORMAL (oko EYE_UP nad środkiem kadru, kadr nad podłogą): pod linią podłogi
				var dist := 20.2
				var eye_up := FRAME_H_NORMAL * 0.5 + 2.2
				var top := 2.0 * Level3D.OIL_BARREL_R
				_check(eye_up + (top - eye_up) * dist / (dist - (c.z + Level3D.OIL_BARREL_R)) < 0.05, "wyciek: przewrócona beczka wchodzi w pas gry")
			else:
				_check(c.z + Level3D.OIL_BARREL_R < 0.0 and c.z - Level3D.OIL_BARREL_R > -Level3D.DEPTH_BACK + 0.3, "wyciek: stojąca beczka nie za płaszczyzną gry (z %.2f)" % c.z)
				_check(outside, "wyciek: stojąca beczka nad niecką")
		_check(lying == 1, "wyciek: %d przewróconych beczek zamiast 1" % lying)
		for it: Dictionary in Front3D.layout(front, [], false, Front3D.blocked_x(front, rows)):
			var x := float(it["x"])
			_check(x < (sp["xr"] as Vector2).x or x > (sp["xr"] as Vector2).y, "hala: %s x %.1f stoi w plamie oleju" % [it["kind"], x])
	Level3D.set_shells([], rows)

func _check_fade() -> void:
	_check(is_equal_approx(Front3D.fade(0.0), Front3D.MIN_A), "fade na sylwetce ≠ MIN_A")
	_check(is_equal_approx(Front3D.fade(Front3D.FADE_M), 1.0), "fade na brzegu FADE_M ≠ 1")
	_check(is_equal_approx(Front3D.fade(0.0, 0.0), 1.0), "waga 0 wygasza")
	_check(Front3D.MIN_A >= 0.2 and Front3D.MIN_A <= 0.45, "MIN_A poza 0,2–0,45 (rura ma być widoczna jako przyciemniona, postać za nią czytelna)")
	var prev := -1.0
	for i in 40:
		var a := Front3D.fade(float(i) * 0.02)
		_check(a >= prev - 0.0001, "fade maleje z odległością (d %.2f)" % (float(i) * 0.02))
		prev = a
	var p := Front3D.parts()
	for k in ["seg", "thin", "valve", "tee"]:
		_check(p.has(k), "brak części %s w %s" % [k, Front3D.PARTS_GLB])
	for key: String in ["g1", "g2", "lamp"]:
		var m := Front3D.materials()[key] as ShaderMaterial
		_check(m.get_shader_parameter("albedo_tex") != null and m.get_shader_parameter("normal_tex") != null, "materiał %s bez tekstur" % key)
