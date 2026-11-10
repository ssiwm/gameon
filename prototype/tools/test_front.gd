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
## (5) las (zestaw „forest”, F3): pnie sosny (martwe pnie i brzozy usunięte w 1.7.543), krzewy, paprocie i trawa; pas otwarty w pionie (przycięcie tylko
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
const Building3D := preload("res://scripts/building3d.gd")
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
		_check_sky_edges(f.get_basename(), consts.get("MAP", []))
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
			if Front3D.over_ground(ca, bool((Front3D.SETS[a["set"]] as Dictionary).get("open", false)), cb, bool((Front3D.SETS[b["set"]] as Dictionary).get("open", false))):
				continue                                                          # las nad tunelem: pod ziemią gaśnie
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
		var entry := false                                   # kolumna wejścia budynku: cała wysokość pasa, także przed otworem
		for e: Dictionary in Level3D.shell_bands:
			entry = entry or (k.y > int(e["r0"]) and k.y < int(e["r1"]) and Level3D.shell_entry(e, k.x, rows))
		_check(entry or ch in Level3D.WALL_CH, "%s %s: ściana przekroju na kaflu '%s'" % [map_id, k, ch])
		_check(not Level3D.shell_cells.has(k), "%s %s: ściana przekroju na kaflu płyty" % [map_id, k])
		for z in digs:
			_check(not (k.x >= int(z[0]) and k.x <= int(z[2]) and k.y >= int(z[1]) and k.y <= int(z[3])), "%s %s: ściana przekroju w strefie wydobycia" % [map_id, k])
		# tylko kolumna lita na całą wysokość pasa: przy oknie, drzwiach albo przejściu ściana zostaje w płaszczyźnie gry
		for e: Dictionary in Level3D.shell_bands:
			if k.x >= int(e["c0"]) and k.x <= int(e["c1"]) and k.y > int(e["r0"]) and k.y < int(e["r1"]) and not entry:
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
	if map_id == "z1_m3":                          # kryjówka to budynki 3D (bez ścian przekroju z kafli)
		_check(not Level3D.shell_walls.is_empty(), map_id + ": brak ścian przekroju")
		var root := Node3D.new()
		get_root().add_child(root)
		var n := Front3D.build_walls(root)
		_check(n > 0, map_id + ": build_walls nic nie zbudował")
		for c in root.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := c as MultiMeshInstance3D
			_check(mmi.layers == Front3D.LAYER_WALL and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: ściana %s ze złą warstwą albo z cieniem" % [map_id, mmi.name])
		var nb := 0
		for k: Vector2i in Level3D.shell_walls:
			nb += int(not Level3D.shell_entry_cells.has(k))
		_check(n <= nb, "%s: ściana wejścia budynku w warstwie pierwszego planu (ma być w świecie z fasadą)" % map_id)
		root.free()
	if map_id == "z1_m2":
		# hala stacji 1.2 to budynek 3D (szkielet z cegłą): bramy na parterze i okna piętra po obu stronach, bez fasad wejść z kafli
		_check(Level3D.shell_facades.is_empty(), "1.2: fasada z kafli przy budynku 3D (%s)" % [Level3D.shell_facades])
		_check_building(rows, "1.2 hala stacji", 66, 100, 18, 26, ["-1:gate", "1:gate", "-1:window", "1:window"])
	if map_id == "z1_m3":
		_check(not Level3D.shell_walls.has(Vector2i(37, 29)), "1.3: ściana wejścia zasłania kratkę piwniczki")
		_check(Level3D.shell_facades.is_empty(), "1.3: fasada z kafli przy budynku 3D (%s)" % [Level3D.shell_facades])
		# posterunek: drzwi po obu stronach; Skład: bramy na parterze i okna piętra po obu stronach
		_check_building(rows, "1.3 posterunek", 18, 36, 21, 26, ["-1:door", "1:door"])
		_check_building(rows, "1.3 Skład", 112, 142, 18, 26, ["-1:gate", "1:gate", "-1:window", "1:window"])
	if map_id == "z1_hub":
		_check_vault(rows)
		_check_hub_furniture(rows)
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
		# bagno startu (14–16, wiersz 26) pod gołym niebem: plama wychodzi na podłoże lasu, a podłoże pod nią jest płaskie i bez runa
		var start: Array = muds.filter(func(sp: Dictionary) -> bool: return absf(float(sp["x0"]) - 14.0 * Level3D.T) < 0.5)
		_check(start.size() == 1 and bool(start[0].get("open", false)) and (start[0]["zr"] as Vector2).y > Level3D.DEPTH_FRONT + 2.0, "1.3: bagno startu nie wychodzi na podłoże lasu")


## FRONT_SKIP: zakres bez pierwszego planu nie dostaje żadnego elementu (z zapasem MARGIN).
## Krawędzie mapy w widoku 3D (`Level3D.sky_edges`): nad gruntem sąsiedniej kolumny dwie skrajne kolumny to powietrze (bez słupa ziemi
## do nieba), od gruntu w dół bez zmian; poza krawędziami wiersze identyczne.
func _check_sky_edges(map_id: String, rows: Array) -> void:
	var out := Level3D.sky_edges(rows)
	var cols: int = (rows[0] as String).length()
	_check(out.size() == rows.size(), "%s: sky_edges zmienia liczbę wierszy" % map_id)
	for side in [[0, 1, 2], [cols - 1, cols - 2, cols - 3]]:
		var top := 0
		while top < rows.size() and not Level3D.is_solid_ch(Level3D._ch(rows, side[2], top)):
			top += 1
		for r in rows.size():
			for c in [side[0], side[1]]:
				var want := "." if r < top and Level3D._ch(rows, c, r) == "#" else Level3D._ch(rows, c, r)
				_check(Level3D._ch(out, c, r) == want, "%s: krawędź kol. %d wiersz %d w widoku 3D: %s" % [map_id, c, r, Level3D._ch(out, c, r)])
	for r in rows.size():
		_check((out[r] as String).substr(2, cols - 4) == (rows[r] as String).substr(2, cols - 4), "%s: sky_edges zmienia wiersz %d poza krawędzią" % [map_id, r])

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
		if not kind in ["pine", "shrub", "ferns", "grass"]:
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
		_check(yw is Vector2 and absf((yw as Vector2).x - yg) < 0.001 and absf(yg - y_floor) < 0.001, "%s: nasada nie kończy się na podłożu (ywin %s, podłoże %.3f)" % [mi.name, yw, yg - y_floor])
		for dx in [-1.0, 0.0, 1.0]:                          # płasko pod elementem (nierówność podłoża nie wchodzi nad nasadę)
			_check(absf(Front3D.ground_y(mi.position.x + dx, mi.position.z) - yg) < 0.001, "%s: podłoże pod elementem nierówne" % mi.name)
		if kind == "pine":
			# nasada (szyja, korzenie) schodzi pod podłoże, koniec nad górnym brzegiem kadru NORMAL (ok. 8 m nad podłogą przy z = 3,5–5 m)
			_check(bb.position.y < yg - 0.2 and bb.position.y > yg - 1.0 and bb.end.y > y_floor + FRAME_H_NORMAL * 0.75, "%s: pień nie stoi na podłożu albo nie sięga nad kadr (%.1f..%.1f wzgl. podłoża)" % [mi.name, bb.position.y - yg, bb.end.y - yg])
		elif kind == "shrub":
			# krzew ze skanu stoi na podłożu (dawniej gałąź `bough` wisiała nad kadrem bez pnia — uwaga z gry 2026-11-09)
			_check(bb.position.y < yg and bb.end.y > yg + 0.7 and bb.end.y < yg + Front3D.SHRUB_H.y * 1.1, "%s: krzew nie stoi na podłożu (%.1f..%.1f wzgl. podłoża)" % [mi.name, bb.position.y - yg, bb.end.y - yg])
		else:
			var z := mi.position.z
			_check(z >= Front3D.CLUMP_Z.x and z <= Front3D.CLUMP_Z.y, "%s: kępa w z %.2f poza CLUMP_Z" % [mi.name, z])
			_check(bb.end.y > yg + 0.4 and bb.end.y < yg + Front3D.CLUMP_H.y, "%s: kępa %.2f m nad podłożem" % [mi.name, bb.end.y - yg])
			_check(_proj(bb.end.y, z, y_floor + 5.3, 20.2) < y_floor, "%s: wierzch kępy w rzucie nad linią podłogi" % mi.name)
		var rims := 0
		var bases := 0
		var cards := 0
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si) as ShaderMaterial
			var card := _par(m, "cutout", 0.0) > 0.0
			var mk := ""
			for k2: String in Front3D.materials():
				if Front3D.materials()[k2] == m:
					mk = k2
			if card:
				cards += 1
				_check(_par(m, "trans_k", 0.0) > 0.0 and "cull_disabled" in m.shader.code, "%s: karta bez prześwitu albo jednostronna" % mi.name)
			elif mk.ends_with(":base"):
				bases += 1
				_check(_par(m, "rim_k", 0.0) == 0.0, "%s: nasada pnia z kontrą księżyca" % mi.name)
			else:
				rims += 1
				_check(_par(m, "rim_k", 0.0) > 0.0, "%s: kora bez kontry księżyca" % mi.name)
		if kind == "pine" and Level3D.model_mesh(String(Front3D.PINE_MODELS[0])).is_empty():
			_check(rims == 1 and bases == 1, "%s: pień bez osobnej kory nasady (kora %d, nasada %d)" % [mi.name, rims, bases])
		elif kind == "pine":
			# sosna ze skanu (1.7.543): kora pnia i konarów z kontrą, igliwie na kartach z wycinaniem i prześwitem
			_check(rims >= 1 and cards >= 1, "%s: sosna ze skanu bez kory albo igliwia (kora %d, karty %d)" % [mi.name, rims, cards])
	_check(kinds.has("pine"), "las: pień sosny nie powstał na długim zakresie")
	# martwe pnie usunięte w 1.7.543 (gołe, jasne „badyle” między koronami): zestaw lasu nie może ich już stawiać
	_check(Front3D.SETS["forest"]["big"] == ["pine"], "las: duże elementy inne niż sosna (%s)" % str(Front3D.SETS["forest"]["big"]))
	# kępy paproci i pokrzyw w warstwie świata (runo z modeli, oświetlone sceną), nie w pierwszym planie; paproć przy każdym pniu
	var ck := {}
	for cl: Array in Front3D._clumps:
		ck[cl[2]] = int(ck.get(cl[2], 0)) + 1
	for k in ["shrub", "ferns", "grass", "base"]:
		_check(ck.has(k), "las: kępa %s nie powstała w warstwie świata (%s)" % [k, ck])
	for k in ["shrub", "ferns", "grass"]:
		_check(not kinds.has(k), "las: kępa %s w warstwie pierwszego planu (oświetlają ją tylko kontry postaci)" % k)
	Front3D.set_moon(0.25)
	for c in fr.get_children():
		var mi := c as MeshInstance3D
		var m := mi.get_surface_override_material(0) as ShaderMaterial
		var forest := String(mi.name).get_slice("_", 0) in ["pine", "shrub", "ferns", "grass"]
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
	var plates: Array = root.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("FrontGround_plate_"))
	_check(plates.size() > 10, "las: brak płyty podłoża w kawałkach (FrontGround_plate_*: %d)" % plates.size())
	if plates.is_empty():
		return
	var g := plates[0] as MeshInstance3D
	var bb := AABB()
	var verts := PackedVector3Array()
	for p: MeshInstance3D in plates:
		_check(p.layers == LAYER_WORLD and p.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "podłoże: warstwa albo cień")
		_check(p.material_override == Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic"), "podłoże: inny materiał niż bryła gruntu")
		bb = p.mesh.get_aabb() if bb.size == Vector3.ZERO else bb.merge(p.mesh.get_aabb())
		verts.append_array(p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	_check(bb.end.z >= float(Front3D.GROUND_Z[Front3D.GROUND_Z.size() - 1]) - 0.01 and bb.position.z < Level3D.DEPTH_FRONT, "podłoże: nie sięga od bryły do %.0f m (%.2f..%.2f)" % [Front3D.GROUND_Z[Front3D.GROUND_Z.size() - 1], bb.position.z, bb.end.z])
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
	var tufts := 0
	for c in root.get_children():
		var mm := c as MultiMeshInstance3D
		if mm != null and String(mm.name).begins_with("FrontGround_tufts_"):
			tufts += mm.multimesh.instance_count
			_check(mm.material_override is ShaderMaterial and (mm.material_override as ShaderMaterial).shader.code == Front3D.GRASS_SHADER, "trawa: kępki bez shadera wiatru")
		elif mm != null and String(mm.name).begins_with("FrontGround_") and not String(mm.name).begins_with("FrontGround_bank_"):   # brzeg bagna osobno
			cards += mm.multimesh.instance_count
	_check(cards > 100 and cards == Front3D.cover_tops.size(), "podłoże: %d kart runa (zapis wierzchołków: %d)" % [cards, Front3D.cover_tops.size()])
	for t: Vector2 in Front3D.cover_tops:
		if _proj(t.x, t.y, y_floor + 5.3, 20.2) > y_floor + 0.35:
			bad += 1
	_check(bad == 0, "podłoże: %d kart runa w rzucie wyżej niż stopy" % bad)
	# ruchoma trawa: kępki w kawałkach mapy, czubki w rzucie pod stopami (jak runo), wiatr z pogody
	_check(tufts > 1000 and tufts == Front3D.tuft_tops.size(), "trawa: %d kępek (zapis czubków: %d)" % [tufts, Front3D.tuft_tops.size()])
	for t: Vector2 in Front3D.tuft_tops:
		if _proj(t.x, t.y, y_floor + 5.3, 20.2) > y_floor + 0.35:
			bad += 1
	_check(bad == 0, "trawa: %d kępek w rzucie wyżej niż stopy" % bad)
	var wind0 := Level3D._wind
	Level3D.set_wind(1.7, 0.4)
	_check(is_equal_approx(float(Front3D._grass_mat.get_shader_parameter("amp")), 1.7), "trawa: set_wind nie dochodzi do kępek")
	Level3D.set_wind(wind0.x, wind0.y)
	# kamera pod powierzchnią (`SURF_FADE`; gracz na podłożu: kamera ok. 5,3 m nad nim) bez wierszy mapy: gaśnie cały pas — płyta i runo
	# (węzły i maska kolumn), pnie przez maskę `gmask`; mapa z zawałem (1.1) buduje świat dwa razy (`GeometryAfterCollapse`): gasną obie kopie
	var fm := Front3D._moon_mats[0] as ShaderMaterial
	_check(fm.get_shader_parameter("gmask") == Front3D.gmask_tex(), "las: pnie bez maski kolumn podłoża")
	var r3 := Node3D.new()
	r3.name = "GeometryAfterCollapse"
	get_root().add_child(r3)
	Front3D.build(r3, [{"set": "forest", "c0": 0, "c1": 400, "r0": 0, "r1": 26}], [], false)
	Front3D.set_camera_y(y_floor + 1.0, NAN, 20.2, 1.0)
	var shown := 0
	for c in root.get_children() + r3.get_children():
		if String(c.name).begins_with("FrontGround") and (c as Node3D).visible and not c.has_meta("gmask"):
			shown += 1
	r3.queue_free()
	var mask0 := Front3D._gmask_img.get_pixel(200 + Front3D.GMASK_PAD, 0).r
	_check(shown == 0 and mask0 == 0.0, "kamera pod powierzchnią: %d węzłów podłoża widocznych, maska kolumn %.2f" % [shown, mask0])
	Front3D.set_camera_y(y_floor + 5.3, NAN, 20.2, 1.0)
	var mask1 := Front3D._gmask_img.get_pixel(200 + Front3D.GMASK_PAD, 0).r
	_check(g.visible and g.transparency == 0.0 and mask1 == 1.0, "kamera nad powierzchnią: las albo podłoże wygaszone")
	_check_local_fade()
	var r2 := Node3D.new()
	get_root().add_child(r2)
	Front3D.build(r2, [{"set": "tunnel", "c0": 0, "c1": 120, "r0": 2, "r1": 10, "shell": true}], [], false)
	_check(r2.get_node_or_null("FrontGround") == null, "tunel: podłoże bez wpisu otwartego")
	r2.queue_free()


## Wygaszanie miejscowe (uwaga z gry 2026-11-09: grunt po prawej znikał po zejściu do piwniczki): grunt w wierszu 26, piwniczka pod nim
## (kolumny 40–44, wiersze 27–29, strop lity), gracz na jej dnie. Kawałki płyty nad piwniczką gasną, płyta nad litym gruntem z prawej
## i z lewej zostaje; nad powierzchnią wszystko widać; gracz głęboko (kamera pod wierzchem) — gaśnie płyta w kadrze.
## Budynek 3D (`building3d.gd`, pilot: posterunek 1.3): kafle dachu i ścian szczytowych bez pudła, płyty przekroju i ściany wejścia;
## drzwi po obu stronach; płyta 0,25 m na górze kafla dachu, ściany 0,4 m, słupy poza pasem gry, przekrój na SHELL_Z dla każdej
## skrzynki dochodzącej do płaszczyzny przekroju, nic przed SHELL_Z.
func _check_building(rows: Array, name: String, c0: int, c1: int, r0: int, r1: int, want: Array) -> void:
	var b: Dictionary = {}
	for x: Dictionary in Level3D.buildings:
		if int(x["c0"]) == c0 and int(x["r0"]) == r0:
			b = x
	_check(not b.is_empty(), "%s: brak budynku 3D (są: %s)" % [name, Level3D.buildings])
	if b.is_empty():
		return
	var doors := {}
	for o: Dictionary in b["open"]:
		doors["%d:%s" % [int(o["side"]), String(o["kind"])]] = true
	for w: String in want:
		_check(doors.has(w), "%s: brak otworu %s (są: %s)" % [name, w, doors.keys()])
	var cm := (c0 + c1) / 2
	var ks: Array = [Vector2i(c0, r0), Vector2i(cm, r0)]
	for r in range(r0 + 1, r1):                              # mur ścian szczytowych (bez otworów i okien)
		for c in [c0, c1]:
			if Level3D._ch(rows, c, r) in Level3D.WALL_CH:
				ks.append(Vector2i(c, r))
	_check(ks.size() > 3, "%s: ściany szczytowe bez muru w mapie" % name)
	for k: Vector2i in ks:
		_check(Level3D.bld_cells.has(k), "%s %s: kafel budynku 3D z pudłem kafla" % [name, k])
		_check(not Level3D.shell_cells.has(k) and not Level3D.shell_walls.has(k) and not Level3D.shell_entry_cells.has(k), "%s %s: kafel budynku 3D w przekroju z kafli" % [name, k])
	for run in Level3D.roof_runs(rows):
		_check(not (int(run["r"]) == r0 and int(run["c0"]) <= c1 and int(run["c1"]) >= c0), "%s: dach z blachy na budynku 3D" % name)
	_check(Level3D.shell_cells.has(Vector2i(cm, r1)), "%s: podłoga budynku bez płyty przekroju" % name)
	var p := Building3D.parts(b, rows)
	var T := Level3D.T
	var zc := Level3D.SHELL_Z
	var yr := -float(r0) * T
	var slab := false
	var cuts: Array = p["cut"]
	for key: String in p:
		for xf: Transform3D in p[key]:
			var sz := xf.basis.get_scale()
			var zmax := xf.origin.z + sz.z * 0.5
			_check(zmax <= zc + Building3D.CUT + 0.001, "%s: element budynku '%s' przed przekrojem (z %.2f)" % [name, key, zmax])
			if key == "cut":
				continue
			slab = slab or (is_equal_approx(xf.origin.y + sz.y * 0.5, yr) and absf(sz.y - Building3D.SLAB) < 0.001 and sz.x > 20.0)
			if zmax >= zc - 0.001:                           # dochodzi do płaszczyzny przekroju: nakładka o tym samym obrysie
				var hit := false
				for c: Transform3D in cuts:
					hit = hit or (c.origin - Vector3(xf.origin.x, xf.origin.y, c.origin.z)).length() < 0.001
				_check(hit, "%s: '%s' w %s bez materiału przekroju" % [name, key, xf.origin])
			# słupy (wysokie, wąskie skrzynki muru) nie stoją w pasie gry
			if key == "col" and sz.y > 4.0 and sz.x <= Building3D.COL + 0.001 and sz.z <= Building3D.COL + 0.001:
				_check(xf.origin.z - sz.z * 0.5 >= Level3D.DEPTH_FRONT or xf.origin.z + sz.z * 0.5 <= -1.0, "%s: słup w pasie gry (z %.2f)" % [name, xf.origin.z])
	_check(slab, "%s: brak płyty stropodachu 0,25 m na górze kafla dachu" % name)
	var walls := 0
	for xf: Transform3D in p["wall"]:
		var sz := xf.basis.get_scale()
		walls += int(absf(sz.x - Building3D.WALL) < 0.001 and sz.y > 1.0)
	_check(walls >= 4, "%s: za mało odcinków ścian szczytowych 0,4 m (%d)" % [name, walls])
	_check(not (p["cut"] as Array).is_empty(), "%s: brak przekroju budynku" % name)

## Kryjówka: trzy kondygnacje bunkra w skale (`"vault"`, `buried`) jedna nad drugą. Bez ścian przekroju i fasad z kafli; płyta stropu tylko nad
## murem wiersza dachu (otwory szybów `=` wolne), nic poza ścianami szczytowymi (okap, cokół, pilastry weszłyby w skałę), słupy poza otworami
## w stropie i podłodze, wszystko za płaszczyzną przekroju i z jej materiałem, żeber `interior_ribs` w budynku nie ma.
## Meble kryjówki stawiane ręcznie (HUB_LAYOUT_PLAN.md E5, HUB_PROPS): rodzaje z hub_prop.gd FURNITURE, w kwaterach dwie prycze piętrowe
## (cztery miejsca), piecyk i stół, nic w pionie poza włazem i kanałem kablowym; właz na parterze w kolumnach pionu, kanał od włazu do
## radiostacji (R); meble nie wchodzą na znaczniki stanowisk; wnęki w danych.
func _check_hub_furniture(rows: Array) -> void:
	var consts: Dictionary = (load("res://scripts/maps/z1_hub.gd") as Script).get_script_constant_map()
	var src := FileAccess.get_file_as_string("res://scripts/hub_prop.gd")    # hub_prop.gd używa autoloadu Audio — stałą czytamy z tekstu
	var rx := RegEx.create_from_string(r"const FURNITURE := (\[[^\]]*\])")
	var mt := rx.search(src)
	var furniture: Array = str_to_var(mt.get_string(1)) if mt != null else []
	_check(furniture.has("bunk") and furniture.has("stove"), "kryjówka: hub_prop.gd FURNITURE bez pryczy i piecyka (%s)" % [furniture])
	var shaft := [21, 26]
	var bunks := 0
	var quarters := {}
	var hatch := -1
	var cables: Array = []
	var radio := String(rows[9 - 1]).find("R")
	for hp: Array in consts.get("HUB_PROPS", []):
		var kind := String(hp[0])
		var c := int(hp[1])
		var fr := int(hp[2])
		if furniture.has(kind):
			_check(c < shaft[0] or c > shaft[1], "kryjówka: mebel %s w pionie (kolumna %d)" % [kind, c])
			var mark := String(rows[fr - 1]).substr(c, 1)
			_check(mark == "b" or (mark == "v" and kind == "table"), "kryjówka: mebel %s na znaczniku '%s' (%d, %d)" % [kind, mark, c, fr - 1])     # stół stoi pod wiszącą tablicą wyników
			_check(not Level3D.is_solid_ch(mark), "kryjówka: mebel %s w ścianie (%d, %d)" % [kind, c, fr - 1])
			if fr == 14 and c <= 9:
				quarters[kind] = int(quarters.get(kind, 0)) + 1
				bunks += int(kind == "bunk")
		elif kind == "hatch":
			hatch = c
			_check(fr == 9 and c >= shaft[0] and c <= shaft[1], "kryjówka: właz poza stropem pionu (%d, %d)" % [c, fr])
		elif kind == "cables":
			cables = [c, int((hp[3] as Array)[0]), fr]
	_check(bunks * 2 >= 4, "kwatery: %d prycz piętrowych — mniej miejsc niż graczy" % bunks)
	_check(quarters.has("stove") and quarters.has("table"), "kwatery bez piecyka albo stołu (%s)" % [quarters])
	_check(hatch >= 0, "kryjówka: brak włazu w stropie pionu")
	_check(cables.size() == 3 and int(cables[0]) == hatch and absi(int(cables[1]) - radio) <= 1 and int(cables[2]) == 9,
		"kryjówka: kanał kablowy nie biegnie od włazu (%d) do radiostacji (%d): %s" % [hatch, radio, cables])
	_check(not (consts.get("NICHES", []) as Array).is_empty(), "kryjówka: brak wnęk")

func _check_vault(rows: Array) -> void:
	var T := Level3D.T
	var zc := Level3D.SHELL_Z
	_check(Level3D.buildings.size() == 2, "kryjówka: %d budynków 3D zamiast 2 (parter i piwnica)" % Level3D.buildings.size())
	_check(Level3D.shell_walls.is_empty() and Level3D.shell_facades.is_empty(), "kryjówka: ściany albo fasady przekroju z kafli przy budynkach 3D")
	_check(Level3D.interior_ribs(rows).is_empty(), "kryjówka: żebra z kafli w budynku 3D (%s)" % [Level3D.interior_ribs(rows)])
	for b: Dictionary in Level3D.buildings:
		var tag := "kryjówka %d–%d r%d" % [int(b["c0"]), int(b["c1"]), int(b["r0"])]
		_check(String(b["kind"]) == "vault" and (b["open"] as Array).is_empty(), "%s: typ %s, otwory %s" % [tag, b["kind"], b["open"]])
		var x0 := float(int(b["c0"])) * T
		var x1 := float(int(b["c1"]) + 1) * T
		var p := Building3D.parts(b, rows)
		var slabs := 0
		for key: String in p:
			for xf: Transform3D in p[key]:
				var sz := xf.basis.get_scale()
				var xa := xf.origin.x - sz.x * 0.5
				var xb := xf.origin.x + sz.x * 0.5
				_check(xa >= x0 - 0.001 and xb <= x1 + 0.001, "%s: '%s' poza ścianami (x %.2f–%.2f)" % [tag, key, xa, xb])
				_check(xf.origin.z + sz.z * 0.5 <= zc + Building3D.CUT + 0.001, "%s: '%s' przed przekrojem" % [tag, key])
				if key in ["slab", "beam", "col"]:
					for c in range(int(floorf((xa + 0.001) / T)), int(ceilf((xb - 0.001) / T))):
						var top := not Level3D._ch(rows, c, int(b["r0"])) in Level3D.WALL_CH and xf.origin.y > -float(int(b["r0"]) + 1) * T
						_check(not top, "%s: '%s' nad otworem stropu w kolumnie %d" % [tag, key, c])
						if key == "col" and sz.y > 4.0:
							_check(Level3D._ch(rows, c, int(b["r1"])) in Level3D.WALL_CH, "%s: słup nad otworem podłogi w kolumnie %d" % [tag, c])
				slabs += int(key == "slab")
		var shafts := false
		for c in range(int(b["c0"]), int(b["c1"]) + 1):
			shafts = shafts or not Level3D._ch(rows, c, int(b["r0"])) in Level3D.WALL_CH
		_check(slabs >= (2 if shafts else 1), "%s: płyta stropu (%d kawałków, szyby: %s)" % [tag, slabs, shafts])
		_check(not (p["cut"] as Array).is_empty() and not (p["col"] as Array).is_empty(), "%s: brak przekroju albo słupów" % tag)
		# słupy tylko na granicach pomieszczeń z klucza "bays" (HUB_LAYOUT_PLAN.md), nie co Building3D.BAY
		var bays: Array = b.get("bays", [])
		_check(not bays.is_empty(), "%s: brak klucza bays" % tag)
		for xf: Transform3D in p["col"]:
			var on_bay := false
			for bc in bays:
				on_bay = on_bay or absf(xf.origin.x - float(int(bc)) * T) < 0.01
			_check(on_bay, "%s: słup x %.2f poza granicą pomieszczenia %s" % [tag, xf.origin.x, bays])

func _check_local_fade() -> void:
	var T := Level3D.T
	var rows: Array = []
	for r in 40:
		var line := ""
		for c in 120:
			var open := r < 26 or (r >= 27 and r <= 29 and c >= 40 and c <= 44)
			line += "." if open else "#"
		rows.append(line)
	var root := Node3D.new()
	get_root().add_child(root)
	Front3D.build(root, [{"set": "forest", "c0": 2, "c1": 110, "r0": 0, "r1": 26}], [], false, rows)
	var vis_at := func(c: int) -> float:
		return Front3D._gvis[c + Front3D.GMASK_PAD]
	var cx := 42.5 * T
	Front3D.set_camera_y(-26.0 * T + 5.3, cx, 20.2, 1.0)        # gracz na powierzchni
	_check(vis_at.call(42) == 1.0 and vis_at.call(60) == 1.0, "miejscowe: nad powierzchnią płyta zgaszona")
	Front3D.set_camera_y(-30.0 * T + 5.3, cx, 20.2, 1.0)        # gracz na dnie piwniczki (kamera ok. 0,06 m nad wierzchem)
	_check(vis_at.call(42) == 0.0 and vis_at.call(60) == 1.0, "miejscowe: kamera na wysokości gruntu — płyta nad piwniczką widoczna albo nad litym gruntem zgaszona")
	Front3D.set_camera_y(-26.0 * T - 1.0, cx, 20.2, 1.0)        # kamera metr pod wierzchem: płytę widać od spodu — gaśnie cała
	_check(vis_at.call(42) == 0.0 and vis_at.call(60) == 0.0 and vis_at.call(20) == 0.0, "miejscowe: kamera pod wierzchem — płyta widoczna od spodu")
	Front3D.set_camera_y(-28.0 * T + 5.3, cx, 20.2, 1.0)        # gracz dwa kafle pod powierzchnią
	var hid := 0
	for c in range(30, 60):
		if vis_at.call(c) < 0.5:
			hid += 1
	_check(vis_at.call(42) == 0.0 and vis_at.call(40) == 0.0 and vis_at.call(44) == 0.0, "miejscowe: płyta nad piwniczką nie gaśnie (%.2f %.2f %.2f)" % [vis_at.call(40), vis_at.call(42), vis_at.call(44)])
	_check(vis_at.call(52) == 1.0 and vis_at.call(58) == 1.0 and vis_at.call(30) == 1.0, "miejscowe: płyta nad litym gruntem gaśnie (%.2f %.2f %.2f)" % [vis_at.call(30), vis_at.call(52), vis_at.call(58)])
	_check(hid <= 10, "miejscowe: zgaszonych %d kolumn przy piwniczce o szerokości 5" % hid)
	var plate := root.get_node("FrontGround_plate_%d" % 56) as MeshInstance3D
	var over := root.get_node("FrontGround_plate_%d" % 42) as MeshInstance3D
	_check(plate.visible and plate.transparency == 0.0 and not over.visible, "miejscowe: węzły płyty nie idą za maską kolumn")
	Front3D.build(root, [], [], false)
	root.queue_free()


## Podłoże na mapie: przy bryle (z = DEPTH_FRONT) w całej kolumnie nie wyżej niż wierzch jej gruntu w pasie wpisu otwartego (pierwszy lity
## kafel pod stropem pasa) i równo z gruntem od r1 w dół (najwyżej 8 wierszy) — dołek przed szybem ma pionowe ściany równo z bokami bryły,
## bez opadania nad sąsiednią kolumną; nie wchodzi w przekrój obok.
func _check_map_ground(map_id: String, rows: Array, front: Array, items: Array) -> void:
	Front3D.prepare_ground(front, rows, items)
	var T := Level3D.T
	var cols: int = (rows[0] as String).length()
	for e: Dictionary in front:
		if not bool((Front3D.SETS[e["set"]] as Dictionary).get("open", false)):
			continue
		for c in range(int(e["c0"]), int(e["c1"]) + 1):
			var cc := clampi(c, 0, cols - 1)
			var top := int(e["r0"]) + 1
			while top < rows.size() and not Level3D.is_solid_ch(Level3D._ch(rows, cc, top)) \
					and not (top >= int(e["r1"]) and Front3D.ground_stop(Level3D._ch(rows, cc, top))):   # właz z desek w wierszu gruntu = podłoga
				top += 1
			top = mini(top, int(e["r1"]) + 8)
			var r := int(e["r1"])
			while r < mini(int(e["r1"]) + 8, rows.size() - 1) and not Front3D.ground_stop(Level3D._ch(rows, cc, r)):
				r += 1                                       # szyb głębszy niż r1 + 8: dołek kończy się na tej głębokości (kamera jest już pod powierzchnią, `SURF_FADE`)
			for fx in [0.02, 0.5, 0.98]:
				var y := Front3D.ground_y((float(c) + fx) * T, Level3D.DEPTH_FRONT)
				if y > -INF:
					_check(y <= -float(top) * T + 0.001, "%s kolumna %d: podłoże %.2f m nad gruntem kolumny" % [map_id, c, y + float(top) * T])
					_check(absf(y + float(r) * T) < 0.001, "%s kolumna %d: podłoże %.2f m od gruntu kolumny od r1" % [map_id, c, y + float(r) * T])
					if Level3D._ch(rows, cc, int(e["r1"])) == "-":   # właz z desek: płyta na powierzchni, nie w sztolni pod nim (1.1, 2026-11-10)
						_check(absf(y + float(int(e["r1"])) * T) < 0.001, "%s kolumna %d: podłoże zjeżdża pod właz z desek (%.2f m)" % [map_id, c, y])
		for o: Dictionary in front:
			if bool(o.get("shell", false)) and absi(int(o["r1"]) - int(e["r1"])) <= 4:
				for x in [float(o["c0"]) * T + 0.3, float(int(o["c1"]) + 1) * T - 0.3]:
					_check(Front3D.ground_y(x, 3.0) == -INF, "%s: podłoże lasu wchodzi w przekrój %s (x %.1f)" % [map_id, o["set"], x])
					# budynek na powierzchni: przed płytą podłogi przekroju grunt biegnie dalej (od SHELL_Z), na wysokości podłogi
					# (przy brzegu może opadać jak podłoże przy szybie obok — na środku budynku leży na wysokości podłogi)
					if absi(int(o["r1"]) - int(e["r1"])) <= 1:
						var yb := Front3D.ground_y(x, Level3D.SHELL_Z)
						var ym := Front3D.ground_y((float(o["c0"]) + float(o["c1"]) + 1.0) * 0.5 * T, Level3D.SHELL_Z + 0.5)
						_check(yb > -INF and yb <= -float(o["r1"]) * T + 0.01 and absf(ym + float(o["r1"]) * T) < 0.01,
								"%s: brak gruntu przed przekrojem %s (x %.1f, y %.2f, środek %.2f)" % [map_id, o["set"], x, yb, ym])
	# pnie i kępy: tylko na równym podłożu (nie na zboczu dołka przed szybem i rampą) i poza pominięciami wpisu (jaskinia, wieża, budynek)
	Level3D.set_shells(front, rows)
	var root := Node3D.new()
	get_root().add_child(root)
	Front3D.build(root, front, [], false, rows)
	var fr := root.get_node_or_null("Front")
	var n := 0
	if fr != null:
		for c in fr.get_children():
			var mi := c as MeshInstance3D
			var yw: Variant = mi.get_instance_shader_parameter("ywin") if mi != null else null
			if not (yw is Vector2) or (yw as Vector2).y < 1e5 or (yw as Vector2).x < -1e5:
				continue                                         # nie stoi na podłożu lasu (gałąź, rury)
			n += 1
			var x := mi.position.x
			_check(Front3D.level_at(x), "%s %s: stoi na nierównym podłożu (x %.1f)" % [map_id, mi.name, x])
			for e: Dictionary in front:
				for sk: Array in (e.get("skip", []) as Array):
					_check(x < float(sk[0]) * T or x > float(int(sk[1]) + 1) * T, "%s %s: pień w pominięciu %s (x %.1f)" % [map_id, mi.name, sk, x])
	if front.any(func(e: Dictionary) -> bool: return bool((Front3D.SETS[e["set"]] as Dictionary).get("open", false))):
		_check(n > 0, "%s: las bez elementów na podłożu" % map_id)
	# podłoga tuneli i sal pod ziemią przed płytą przekroju: od SHELL_Z, płaska, nie wyżej niż najwyższa podłoga przekroju
	var tun: Array = front.filter(func(e: Dictionary) -> bool: return bool(e.get("shell", false)) and String(e["set"]) != "bunker")
	if not tun.is_empty():
		var ytop := -INF
		for e: Dictionary in tun:
			ytop = maxf(ytop, -float(e["r1"]) * T)
		var floors: Array = root.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("FrontFloor"))
		_check(not floors.is_empty(), "%s: brak podłogi tunelu przed przekrojem" % map_id)
		for c: Node in floors:
			var bb := ((c as MeshInstance3D).mesh as ArrayMesh).get_aabb()
			_check(bb.position.z >= Level3D.SHELL_Z - 0.05 and bb.end.z >= float(Front3D.GROUND_Z[Front3D.GROUND_Z.size() - 1]) - 0.01 and bb.end.y <= ytop + 0.01,
					"%s: podłoga tunelu z %.2f..%.2f, wierzch %.2f (podłoga %.2f)" % [map_id, bb.position.z, bb.end.z, bb.end.y, ytop])
	root.queue_free()
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

## Hala stacji 1.2 jako budynek 3D (`building3d.gd`, od 1.7.529; wcześniej dach z blachy na płatwiach): nad pasem nie ma dachu z blachy
## (`Level3D.roof_purlins` puste), a element pierwszego planu dochodzi do spodu płyty stropu (`Building3D.SLAB` pod górą kafla dachu), nie do
## spodu żeber — między żebrami nad elementem prześwitywała ściana (piwnica kryjówki, uwaga z gry 2026-11-10).
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
			var yw: Variant = mi.get_instance_shader_parameter("ywin")
			if not (yw is Vector2):
				continue
			n += 1
			_check(Level3D.roof_purlins(rows, int(floorf(mi.position.x / Level3D.T)), int(e["r0"])).is_empty(), "%s: dach z blachy nad budynkiem 3D" % mi.name)
			var yc := -float(int(e["r0"])) * Level3D.T - float((load("res://scripts/building3d.gd") as Script).get_script_constant_map()["SLAB"])
			_check(absf((yw as Vector2).y - yc) < 0.001, "%s: góra %.3f m zamiast spodu stropu %.3f" % [mi.name, (yw as Vector2).y, yc])
	_check(n > 0, "hala stacji: brak elementów pierwszego planu z przekrojem")
	# zasłanianie płytą (shader `occ`): każdy element z przekrojem i jego płytka znają spód stropu / dachu i przód płyty
	if fr != null:
		for c in fr.get_children():
			var mi := c as MeshInstance3D
			var oc: Variant = mi.get_instance_shader_parameter("occ")
			var yw: Variant = mi.get_instance_shader_parameter("ywin")
			_check(oc is Vector4 and yw is Vector2 and absf((oc as Vector4).x - (yw as Vector2).y - 0.02) < 0.001 and (oc as Vector4).z >= Level3D.SHELL_Z - 0.001, "%s: brak zasłaniania stropem / dachem (occ %s, ywin %s)" % [mi.name, oc, yw])
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
