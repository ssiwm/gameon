extends RefCounted
## Geometria 3D z mapy ASCII poziomu (używają: widok 3D w grze `view3d.gd` i spike `spike3d/mission3d.gd`). Statyczne funkcje: dostają
## tablicę wierszy mapy i węzeł-rodzic, tworzą `MultiMeshInstance3D`-y (odsłonięte kafle, trawa, ściany tła, pnie, kładki) i las w głębi
## oraz środowisko. Układ: x w prawo, y w górę (mapa ma y w dół), z = 0 płaszczyzna gry, kamera patrzy w −Z.
## Skala: 1 px świata = PX m (postać 22 px = 1,8 m), kafel 16 px = T m.

const PX := 1.8 / 22.0
const TILE := 16.0
const T := TILE * PX
const DEPTH_FRONT := 1.1                   ## m: wysunięcie bryły przed płaszczyznę gry
const POST_Z := -1.6                       ## m: słupy i pnie (`w`) bez styku z pomostem stoją w głębi, za drogą postaci i drezyny, tuż przed ścianą tła
const POST_K := 0.036                      ## skala przekroju modelu słupa `post` (100 jednostek wysokości; promień ok. 0,43 m)
const DECK_H := {"-": 0.176, "=": 0.24}       ## grubość pokładu kładki w kaflach (deski: 17,6 jednostki modelu na odcinek 1 kafla, krata: 8 na 3 kafle)
## Pnie z mapy (`post_runs`: „tree") jako martwe drzewa z modeli lasu: [model, mnożnik przekroju]. Pień z Tripo i szkielet świerka mają gałęzie
## krótkie i gęste (nie przypominają kładek, po których się chodzi); martwa sosna z długimi konarami i niski kikut brzozy tu nie pasują.
const TRUNK_MODELS := [["tree_snag", 0.42], ["tree_snag_spruce", 0.48]]
const TRUNK_Z := -1.9                      ## m: pień w głębi, za drogą postaci; gałęzie zgniecione w osi z (`TRUNK_DEPTH`), żeby nie wychodziły przed bryłę
const TRUNK_DEPTH := 0.55                  ## przekrój w głąb względem szerokości (gałęzie rosną głównie w bok)
const TRUNK_OVER := [1.6, 3.4]             ## m: o tyle złamany wierzchołek wystaje ponad ostatni kafel pnia
const POST_BITE := 0.02                    ## m: o tyle słup przy pomoście wchodzi w tylną krawędź pomostu (styk bez szczeliny)
const DEPTH_BACK := 2.4                    ## m: w głąb
const LAYER_FOREST := 32                   ## warstwa wizualna lasu i jego dna (oprócz warstwy świata): tylko ją oświetla `MoonRim`
const MOON_RIM := 0.35                     ## energia poświaty księżyca na lesie (`MoonRim`) w noc bez pogody; `view3d._sync_weather` mnoży ją wg pogody

static func is_solid_ch(ch: String) -> bool:
	return ch == "#" or ch == "C" or ch == "M" or ch == "m" or ch == "O" or ch == "~"

static func is_platform_ch(ch: String) -> bool:
	return ch == "-" or ch == "="

## Dach szopy: samotna warstwa betonu `C` z niebem nad sobą (kolumna bez bryły, kładki i słupa aż do góry mapy) i pustką pod spodem. W 3D to dach
## z blachy na wiązarach (`_build_roofs`); stropy międzypiętrowe mają nad sobą wnętrze, a podłogi i skały sąsiadują z bryłą, więc zostają betonowe.
## Skrzynie `M` stojące na dachu go nie przerywają (wcześniej pod każdą skrzynią zostawał kafel betonu wśród blachy).
static func is_roof_cell(rows: Array, c: int, r: int) -> bool:
	if _ch(rows, c, r) != "C" or is_solid_ch(_ch(rows, c, r + 1)):
		return false
	var top := r - 1
	while _ch(rows, c, top) == "M" and top > 0:
		top -= 1
	if top < r - 1 and _ch(rows, c, top) != ".":
		return false                                            # skrzynie tylko na otwartym dachu (pod nimi nie ma piętra ani stropu)
	for k in range(top, -1, -1):
		var n := _ch(rows, c, k)
		if is_solid_ch(n) or is_platform_ch(n) or n == "w":
			return false
	return true

## Środek kafla (c, r) w metrach świata.
static func cell_pos(c: float, r: float) -> Vector3:
	return Vector3((c + 0.5) * T, -(r + 0.5) * T, 0.0)

static func px_to_m(p: Vector2) -> Vector3:
	return Vector3(p.x * PX, -p.y * PX, 0.0)

static func _ch(rows: Array, c: int, r: int) -> String:
	if r < 0 or r >= rows.size():
		return "#"
	var row: String = rows[r]
	if c < 0 or c >= row.length():
		return "#"
	return row[c]

static func make_mat(col: Color, rough := 0.95, noise_freq := 0.06, bump := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = noise_freq
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = bump
	return m

const PBR_DIR := "res://art/world3d/"
static var _pbr_cache := {}

## Materiał PBR ze skanu / generatora (`tools/world_pbr_import.py`, `world_pbr_gen.py`): albedo + normalne + ORM (R = AO, G = roughness, B = metallic),
## rzutowanie triplanarne w jednostkach świata (`per_m` = powtórzeń na metr). Brak plików → szum proceduralny (`make_mat`) z kolorem awaryjnym.
static func make_pbr(name: String, per_m: float, fallback: Color, rough := 0.95, normal_scale := 1.0, metal_mul := 1.0, alpha := false, grime := "") -> StandardMaterial3D:
	var key := "%s:%.3f:%s:%s" % [name, per_m, str(alpha), grime]
	if _pbr_cache.has(key):
		return _pbr_cache[key]
	var path := PBR_DIR + name + "_albedo.png"
	if not ResourceLoader.exists(path) or "--noworldpbr" in OS.get_cmdline_user_args():     # dev: --noworldpbr = stary szum proceduralny (porównanie)
		return make_mat(fallback, rough)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path) as Texture2D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(per_m, per_m, per_m)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var np := PBR_DIR + name + "_normal.png"
	if ResourceLoader.exists(np):
		m.normal_enabled = true
		m.normal_texture = load(np) as Texture2D
		m.normal_scale = normal_scale
	var op := PBR_DIR + name + "_orm.png"
	if ResourceLoader.exists(op):
		var orm := load(op) as Texture2D
		m.ao_enabled = true
		m.ao_texture = orm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = metal_mul
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if grime != "" and not alpha and ResourceLoader.exists(PBR_DIR + "grime_%s.png" % grime) and not "--nograime" in OS.get_cmdline_user_args():
		# warstwa brudu jako osobny przebieg (`next_pass`): wielkoskalowa (kafel ok. 14 m), więc plamy, zacieki i przebarwienia nie powtarzają się
		# razem z kaflem materiału (warstwa „detail” StandardMaterial3D w triplanarze używa siatki UV materiału bazowego)
		var g := StandardMaterial3D.new()
		g.albedo_texture = load(PBR_DIR + "grime_%s.png" % grime) as Texture2D
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.95
		g.uv1_triplanar = true
		g.uv1_world_triplanar = true
		g.uv1_scale = Vector3(0.07, 0.07, 0.07)
		g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.next_pass = g
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pbr_cache[key] = m
	return m

## Siatka modelu z art/items3d/<nazwa>.glb (`tools/prep_items3d.py`) i jej przekształcenie w scenie modelu: [Mesh, Transform3D] albo [] bez pliku.
## Drzewa, kłoda i słup mają 100 jednostek wysokości / długości — skalę nadaje wywołujący.
const MODEL_DIR := "res://art/items3d/"
static var _model_cache := {}
static func model_mesh(name: String) -> Array:
	if _model_cache.has(name):
		return _model_cache[name]
	var out: Array = []
	var path := MODEL_DIR + name + ".glb"
	if ResourceLoader.exists(path) and not "--nomodels3d" in OS.get_cmdline_user_args():
		var inst := (load(path) as PackedScene).instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var n := found[0] as Node3D
			var xf := n.transform
			var up := n.get_parent()
			while up != null and up is Node3D:
				xf = (up as Node3D).transform * xf
				up = up.get_parent()
			out = [(found[0] as MeshInstance3D).mesh, xf]
			var msh := (found[0] as MeshInstance3D).mesh
			for si in msh.get_surface_count():                    # karty igliwia / liści: wycinanie alfą (cienie i głębia działają), widoczne z obu stron
				var bm := msh.surface_get_material(si) as BaseMaterial3D
				if bm != null and name.begins_with("tree_"):
					bm.vertex_color_use_as_albedo = true              # odcień egzemplarza lasu (kolor `MultiMesh`, `_forest_chunks`)
				if bm != null and bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					bm.alpha_scissor_threshold = 0.4
					bm.cull_mode = BaseMaterial3D.CULL_DISABLED
					bm.metallic_specular = 0.0
					bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					_soft_cutout(bm, name.begins_with("tree_"))
					if name.begins_with("tree_") and bm.albedo_texture != null:       # igliwie drzew: ten sam wygląd + wiatr (`WIND_SHADER`)
						var wm := _wind_mat(bm.albedo_texture, bm.albedo_color, 100.0, 1.0, 0.4)
						msh.surface_set_material(si, wm)
						_wind_models.append(wm)
		inst.free()
	_model_cache[name] = out
	return out

## `MultiMesh` z modelu `name`; przekształcenia egzemplarzy są w jednostkach modelu (mnożone przez przekształcenie siatki w jej scenie).
static func _multimodel(parent: Node3D, name: String, xforms: Array, shadows := true) -> bool:
	var mm := model_mesh(name)
	if mm.is_empty():
		return false
	var out: Array = []
	for x in xforms:
		out.append((x as Transform3D) * (mm[1] as Transform3D))
	_multimesh(parent, mm[0], out, null, shadows)
	return true

static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Bryły, trawa, ściany tła, pnie i kładki z mapy (`rows`: tablica Stringów). Zwraca słownik pozycji znaczników do świateł / rekwizytów:
## {"F": [Vector3…], "E": […], "l": […], "k": […]} (środek kafla, y = podłoga komórki).
## `trench` = {"row", "c0", "c1"}: torowisko drezyny — kafle podłogi w tym pasie mają z przodu (z od TRENCH_Z0 do krawędzi bryły) obniżone koryto
## o głębokości TRENCH_D, otwarte ku kamerze; z tyłu zostaje peron na pełnej wysokości, po którym chodzą postacie.
const TRENCH_D := 5.35 * PX                ## m: góra pokładu drezyny wypada równo z peronem
const TRENCH_Z0 := 0.22                    ## m: krawędź peronu (tuż przed płaszczyzną gry)
## Czy za komórką ze znacznikiem, kładką albo słupem ma stać ściana tła: znaki mapy inne niż `b` zajmują komórkę ściany (wróg, przedmiot, kładka,
## słup w hali), a w 3D zostawiały w murze prostokątne dziury. Ściana jest, gdy w wierszu — idąc przez takie same komórki — po lewej albo po prawej
## trafiamy na `b`, albo `b` jest bezpośrednio nad lub pod komórką.
static func _wall_behind(rows: Array, c: int, r: int) -> bool:
	var ch := _ch(rows, c, r)
	if ch == "." or ch == "b" or ch == "" or is_solid_ch(ch):
		return false
	if _ch(rows, c, r - 1) == "b" or _ch(rows, c, r + 1) == "b":
		return true
	for dir in [-1, 1]:
		var k: int = c + dir
		var steps := 0
		while steps < 24:
			var n := _ch(rows, k, r)
			if n == "b":
				return true
			if n == "." or n == "" or is_solid_ch(n):
				break
			k += dir
			steps += 1
	return false

## Znacznik mapy (wróg, przedmiot, start…): komórka bez własnej geometrii — nie bryła, kładka, tło ani powietrze.
static func _is_marker(ch: String) -> bool:
	return not (ch == "" or ch == "." or ch == "b" or ch == "w" or ch == "i" or ch == "s" or is_solid_ch(ch) or is_platform_ch(ch))

## Czy komórka należy do słupa w widoku 3D. Poza kaflami `w` także:
##  - znacznik z `w` nad albo pod sobą (ta sama reguła co `level.gd: _marker_back_char` w 2D) — wróg u podstawy słupa nie skraca go o kafel,
##    więc słup nie wisi nad ziemią;
##  - kafel kładki z `w` pod sobą — słup przechodzi przez pomost (bez dziury o wysokości kafla pod deskami) albo kończy się równo z jego pokładem.
static func is_post_cell(rows: Array, c: int, r: int) -> bool:
	var ch := _ch(rows, c, r)
	if ch == "w":
		return true
	if _is_marker(ch):
		return _ch(rows, c, r - 1) == "w" or _ch(rows, c, r + 1) == "w"
	if is_platform_ch(ch):
		return _ch(rows, c, r + 1) == "w" or (_is_marker(_ch(rows, c, r + 1)) and _ch(rows, c, r + 2) == "w")
	return false

## Rola ciągu słupa w konstrukcji, którą rysuje `Backdrop3D.build_frames` zamiast modelu słupa:
##  - "mast": maszt — dwie sąsiednie kolumny `w` od samej góry mapy (maszt z generatorem w 1.2) → kratownica stalowa z lampami przeszkodowymi;
##  - "tower": noga wieży — nad ciągiem leży blacha/skrzynia `M` (podłoga albo dach strażnicy w 1.1) → drewniane nogi z przodu i z tyłu ze stężeniami;
##  - "" — zwykły słup (`build_level`).
static func frame_role(rows: Array, run: Dictionary) -> String:
	var c: int = run["c"]
	var r0: int = run["r0"]
	var r1: int = run["r1"]
	if r0 == 0 and r1 - r0 >= 12 and (_ch(rows, c - 1, 1) == "w" or _ch(rows, c + 1, 1) == "w"):
		return "mast"
	if _ch(rows, c, r0 - 1) == "M":
		return "tower"
	return ""

## Promień słupa (m) z modelu `post` w skali POST_K; bez modelu — walec zastępczy.
static func post_radius() -> float:
	var mm := model_mesh("post")
	if mm.is_empty():
		return 0.5
	var bb: AABB = (mm[1] as Transform3D) * (mm[0] as Mesh).get_aabb()
	return maxf(bb.size.x, bb.size.z) * 0.5 * POST_K

## Pół głębokości pokładu kładki (m): deski `-` mają głębokość kafla, krata `=` ramę ok. 0,27 kafla na trzy kafle długości (`build_level`).
static func deck_half(ch: String) -> float:
	var per := 1.0 if ch == "-" else 3.0
	var mm := model_mesh("walkway_plank" if ch == "-" else "walkway_grate")
	if mm.is_empty():
		return 0.65
	var bb: AABB = (mm[1] as Transform3D) * (mm[0] as Mesh).get_aabb()
	return maxf(-bb.position.z, bb.end.z) * per * T / 100.0

## Pionowe ciągi słupów: [{"c", "r0", "r1" (wyłącznie), "z" — oś słupa w głąb, "deck" — znak kładki, której dotyka, albo "", "tree" — pień drzewa}].
## Pień (`tree`): ciąg z gołym niebem nad sobą, którego nie dotyka żadna kładka — w 2D to były drzewa; w 3D stoi tu martwe drzewo (`TRUNK_MODELS`).
## Podpora dachu (`roof`): ciąg tuż pod dachem z blachy — rysuje go `_build_roofs` razem z resztą konstrukcji szopy.
## Słup dotyka kładki, gdy przez nią przechodzi, kończy się na jej pokładzie, stoi na niej albo kładka dochodzi do niego z boku.
## Taki słup stoi tuż za tylną krawędzią pokładu (`deck_half` + promień − POST_BITE), więc pomost na nim leży; nadal za płaszczyzną gry
## i za postaciami. Pozostałe (stemple pod stropem, pnie) zostają w głębi na POST_Z.
static func post_runs(rows: Array, radius := -1.0) -> Array:
	var r_post := post_radius() if radius < 0.0 else radius
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var out: Array = []
	for c in cols:
		var r := 0
		while r < nrows:
			if _ch(rows, c, r) != "w" and not (is_post_cell(rows, c, r) and _ch(rows, c, r + 1) == "w"):
				r += 1                                  # ciąg zaczyna się od `w` albo od kafla, który wchodzi w słup od góry (kładka, znacznik)
				continue
			var r1 := r
			while r1 < nrows and is_post_cell(rows, c, r1):
				r1 += 1
			var deck := ""
			for k in range(r, r1 + 1):                  # kładki w ciągu, pod jego dolnym końcem i obok
				for cc in [c - 1, c, c + 1]:
					var n := _ch(rows, cc, k)
					if is_platform_ch(n) and (cc == c or k < r1):
						if deck == "" or deck_half(n) > deck_half(deck):
							deck = n
			var z := POST_Z if deck == "" else -(deck_half(deck) + r_post - POST_BITE)
			var tree := deck == "" and _ch(rows, c, r - 1) == "."       # pień z 2D: nad nim tylko niebo i nic się o niego nie opiera
			var roof := is_roof_cell(rows, c, r - 1)                    # podpora dachu szopy: belka jak reszta konstrukcji dachu (`_build_roofs`)
			out.append({"c": c, "r0": r, "r1": r1, "z": z, "deck": deck, "tree": tree, "roof": roof})
			r = r1
	return out

## Przekrój wnętrza bryły od frontu (z = DEPTH_FRONT): poziome ciągi niewidocznych z boku kafli jako jeden czworokąt na ciąg; materiał jak bryła
## (projekcja w świecie — tekstura przechodzi bez szwu przez front sąsiednich brył). Nocą czarny jak dotąd, ale światła mają na czym się położyć.
static func _build_caps(parent: Node3D, cells: Array, mat: Material) -> void:
	if cells.is_empty():
		return
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var i := 0
	while i < cells.size():
		var a: Vector2i = cells[i]
		var j := i
		while j + 1 < cells.size() and (cells[j + 1] as Vector2i).y == a.y and (cells[j + 1] as Vector2i).x == (cells[j] as Vector2i).x + 1:
			j += 1
		var x0 := float(a.x) * T
		var x1 := float((cells[j] as Vector2i).x + 1) * T
		var y0 := -float(a.y + 1) * T
		var y1 := -float(a.y) * T
		v.append_array(PackedVector3Array([Vector3(x0, y0, DEPTH_FRONT), Vector3(x1, y1, DEPTH_FRONT), Vector3(x1, y0, DEPTH_FRONT),
				Vector3(x0, y0, DEPTH_FRONT), Vector3(x0, y1, DEPTH_FRONT), Vector3(x1, y1, DEPTH_FRONT)]))
		for k in 6:
			n.append(Vector3.BACK)
		i = j + 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Caps"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

const ROOF_SHEET := 0.05                   ## m: grubość arkusza blachy (góra arkusza = góra kafla, po której się chodzi)
const ROOF_EAVE := 0.35                    ## m: okap ku kamerze przed przednią krawędzią bryły; z boków (wolne końce szopy) — tyle samo
const ROOF_PURLIN_Z := [-2.05, -0.65, 0.8] ## m: płatwie pod blachą wzdłuż dachu
const ROOF_TRUSS := 2                      ## co tyle kafli wiązar (pas dolny w poprzek dachu + słupki pod płatwiami)
const ROOF_SPAN := 5                       ## szopa: najwyżej tyle kafli między podporami
const ROOF_POST := 0.26                    ## m: przekrój drewnianego słupa szopy
const ROOF_KNEE := 0.75                    ## m: zastrzał szopy — od słupa tyle w dół i tyle w bok pod pas dolny wiązara
const ROOF_POST_FRONT := 0.82              ## m: przednie słupy szopy pod płatwią przy okapie (za krawędzią bryły)

## Dachy z blachy (`is_roof_cell`): poziome ciągi kafli dachu [{"r", "c0", "c1" (włącznie), "steel" — oparty o ściany `C` (wiązary stalowe; inaczej
## drewniana szopa), "posts" — kolumny podpór szopy: słupy mapy pod dachem i dodane co najwyżej ROOF_SPAN kafli, gdzie pod dachem do gruntu jest pusto}].
static func roof_runs(rows: Array) -> Array:
	var out: Array = []
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	for r in nrows:
		var c := 0
		while c < cols:
			if not is_roof_cell(rows, c, r):
				c += 1
				continue
			var c1 := c
			while c1 + 1 < cols and is_roof_cell(rows, c1 + 1, r):
				c1 += 1
			var steel := _ch(rows, c - 1, r) == "C" or _ch(rows, c1 + 1, r) == "C"
			var posts: Array = []
			if not steel:
				var last := c - ROOF_SPAN                       # pierwsza podpora najpóźniej przy lewym końcu
				for k in range(c, c1 + 1):
					var mapped := _ch(rows, k, r + 1) == "w"
					var due := k - last >= ROOF_SPAN or k == c1
					if mapped or (due and roof_ground(rows, k, r) > 0):
						posts.append(k)
						last = k
			out.append({"r": r, "c0": c, "c1": c1, "steel": steel, "posts": posts})
			c = c1 + 1
	return out

## Dach i podłoga strażnicy: ciągi skrzyń `M` tuż nad nogami wieży (`frame_role` "tower") — [{"r", "c0", "c1" (włącznie), "roof": nad nimi niebo
## (dach z blachy), inaczej podłoga piętra (deski)}]. W 3D były to rdzawe pudła kafla (dach 14 × 1,3 m); teraz rysuje je `_build_roofs`.
static func tower_slabs(rows: Array) -> Array:
	var out: Array = []
	var seen := {}
	for run in post_runs(rows):
		if frame_role(rows, run) != "tower":
			continue
		var r: int = int(run["r0"]) - 1
		var c: int = run["c"]
		var a := c                                              # ciąg w tym wierszu: skrzynie i właz (kładka) między nimi
		while _ch(rows, a - 1, r) == "M" or is_platform_ch(_ch(rows, a - 1, r)):
			a -= 1
		var z := c
		while _ch(rows, z + 1, r) == "M" or is_platform_ch(_ch(rows, z + 1, r)):
			z += 1
		var k := a
		while k <= z:                                           # osobne ciągi samych `M` (właz zostaje kładką)
			if _ch(rows, k, r) != "M":
				k += 1
				continue
			var k1 := k
			while k1 + 1 <= z and _ch(rows, k1 + 1, r) == "M":
				k1 += 1
			var key := Vector2i(k, r)
			if not seen.has(key):
				seen[key] = true
				var sky := true
				for q in range(k, k1 + 1):
					if _ch(rows, q, r - 1) != ".":
						sky = false
				out.append({"r": r, "c0": k, "c1": k1, "roof": sky})
			k = k1 + 1
	return out

## Wiersz gruntu pod dachem w kolumnie `c` (pierwszy lity kafel pod `r`), gdy po drodze nie ma bryły ani kładki; −1, gdy kolumna nie nadaje się na słup.
static func roof_ground(rows: Array, c: int, r: int) -> int:
	for k in range(r + 1, rows.size()):
		var n := _ch(rows, c, k)
		if is_solid_ch(n):
			return k if k > r + 1 else -1
		if is_platform_ch(n) or n == "b":
			return -1
	return -1

## Pudło od rogu a do rogu b (przekształcenie pudła 1×1×1).
static func _span_box(a: Vector3, b2: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled((b2 - a).abs()), (a + b2) * 0.5)

## Belka od punktu a do b (przekrój `w` × `w`), jako przekształcenie pudła 1×1×1.
static func _strut(a: Vector3, b2: Vector3, w: float) -> Transform3D:
	var d := b2 - a
	var up := d.normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var zx := side.cross(up).normalized()
	var xx := up.cross(zx).normalized()
	return Transform3D(Basis(xx * w, up * d.length(), zx * w), (a + b2) * 0.5)

## Dach z blachy zamiast pudła kafla grubości 1,3 m: arkusz z okapem i blendą na górze kafla, pod nim płatwie, co ROOF_TRUSS kafli wiązar
## (pas dolny na dolnej krawędzi kafla — Skoczek dalej wisi „pod sufitem", słupki pod płatwiami). W budynkach ze ścianami `C` konstrukcja
## stalowa, a tylna ściana sięga pod blachę (bez niej przez wiązary prześwitywał las); w szopie drewniana, z podporami z tyłu (POST_Z) i z przodu
## (ROOF_POST_FRONT) i zastrzałami pod wiązarem. Tylko widok — kolizja to nadal pełny kafel.
static func _build_roofs(parent: Node3D, rows: Array, sheet_mat: Material, steel_mat: Material, wood_mat: Material, wall_mat: Material) -> void:
	var sheets: Array = []
	var boards: Array = []
	var walls: Array = []
	var frame := {true: [], false: []}
	var runs: Array = roof_runs(rows)
	for s in tower_slabs(rows):                                 # dach i podłoga strażnicy: ta sama konstrukcja, drewniana, podłoga z desek
		runs.append({"r": s["r"], "c0": s["c0"], "c1": s["c1"], "steel": false, "posts": [], "boards": not bool(s["roof"])})
	for run in runs:
		var r: int = run["r"]
		var c0: int = run["c0"]
		var c1: int = run["c1"]
		var steel: bool = run["steel"]
		var y_top := -float(r) * T
		var y_bot := -float(r + 1) * T
		var lo := _ch(rows, c0 - 1, r)
		var hi := _ch(rows, c1 + 1, r)
		var x0 := float(c0) * T - (0.0 if is_solid_ch(lo) or is_platform_ch(lo) else ROOF_EAVE)
		var x1 := float(c1 + 1) * T + (0.0 if is_solid_ch(hi) or is_platform_ch(hi) else ROOF_EAVE)
		var z0 := -DEPTH_BACK
		var z1 := DEPTH_FRONT + ROOF_EAVE
		var is_boards := bool(run.get("boards", false))
		var top_list: Array = boards if is_boards else sheets
		top_list.append(_span_box(Vector3(x0, y_top - ROOF_SHEET * (2.4 if is_boards else 1.0), z0), Vector3(x1, y_top, z1)))
		top_list.append(_span_box(Vector3(x0, y_top - 0.24, z1 - 0.04), Vector3(x1, y_top - ROOF_SHEET, z1)))     # blenda okapu od strony kamery
		var bar := 0.16 if steel else 0.18
		var under := y_top - ROOF_SHEET
		var fr: Array = frame[steel]
		for pz in ROOF_PURLIN_Z:
			fr.append(_span_box(Vector3(x0 + 0.05, under - bar, float(pz) - bar * 0.5), Vector3(x1 - 0.05, under, float(pz) + bar * 0.5)))
		var trusses: Array = []
		for k in range(c0, c1 + 1, ROOF_TRUSS):
			trusses.append(float(k) * T + 0.15)
		trusses.append(float(c1 + 1) * T - 0.15)
		for tx in trusses:
			fr.append(_span_box(Vector3(tx - bar * 0.5, y_bot, z0 + 0.05), Vector3(tx + bar * 0.5, y_bot + bar * 1.4, DEPTH_FRONT)))   # pas dolny
			for pz in ROOF_PURLIN_Z:
				fr.append(_span_box(Vector3(tx - bar * 0.4, y_bot + bar, float(pz) - bar * 0.4), Vector3(tx + bar * 0.4, under - bar, float(pz) + bar * 0.4)))
		if steel:
			for k in range(c0, c1 + 1):                         # tylna ściana budynku pod samą blachę
				if _ch(rows, k, r + 1) == "b":
					walls.append(_span_box(Vector3(float(k) * T, y_bot, -DEPTH_BACK), Vector3(float(k + 1) * T, under, -DEPTH_BACK + 0.3)))
		for k in run["posts"]:
			var g := roof_ground(rows, int(k), r)
			if g < 0:
				continue
			var px := (float(k) + 0.5) * T
			for pz in [POST_Z, ROOF_POST_FRONT]:
				fr.append(_span_box(Vector3(px - ROOF_POST * 0.5, -float(g) * T - 0.1, float(pz) - ROOF_POST * 0.5), Vector3(px + ROOF_POST * 0.5, y_bot, float(pz) + ROOF_POST * 0.5)))
				for dx in [-1.0, 1.0]:                          # zastrzały w stronę dachu (nie poza jego koniec)
					var ex: float = px + float(dx) * ROOF_KNEE
					if ex > x0 + 0.1 and ex < x1 - 0.1:
						fr.append(_strut(Vector3(px, y_bot - ROOF_KNEE, float(pz)), Vector3(ex, y_bot + bar * 0.7, float(pz)), ROOF_POST * 0.55))
	var box := BoxMesh.new()
	_multimesh(parent, box, walls, wall_mat, false)
	_multimesh(parent, box, sheets, sheet_mat)
	_multimesh(parent, box, boards, wood_mat)
	_multimesh(parent, box, frame[true], steel_mat)
	_multimesh(parent, box, frame[false], wood_mat)

## Stopy ścian: ściana `C` (co najmniej dwa kafle w pionie), która kończy się nad otwartym parterem (wejście do chaty radiowej, pompowni, Składu),
## wisiała w powietrzu. Od jej dołu do gruntu stoi filar z betonu w głębi (od tyłu bryły do WALL_FOOT_Z, za drogą postaci) — wejście zostaje otwarte.
## [{"c", "r" — pierwszy wiersz pod ścianą, "g" — wiersz gruntu}].
const WALL_FOOT_Z := -0.9
const WALL_FOOT_W := 0.6
static func wall_feet(rows: Array) -> Array:
	var out: Array = []
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	for c in cols:
		for r in range(1, nrows - 1):
			if _ch(rows, c, r) != "C" or _ch(rows, c, r - 1) != "C" or is_solid_ch(_ch(rows, c, r + 1)) or is_roof_cell(rows, c, r):
				continue
			if _ch(rows, c - 1, r) == "C" and _ch(rows, c + 1, r) == "C":
				continue                                            # strop (poziomy pas betonu), nie ściana
			var g := r + 1
			var open_air := true                                    # pod ścianą zewnętrzne powietrze; nad przejściem we wnętrzu (tło `b`, zamurowanie `q`) beton to nadproże
			while g < nrows and not is_solid_ch(_ch(rows, c, g)) and g - r <= 8:
				var n := _ch(rows, c, g)
				if not (n == "." or _is_marker(n)) or n == "q":
					open_air = false
				g += 1
			if open_air and g < nrows and is_solid_ch(_ch(rows, c, g)) and g - r <= 8:
				out.append({"c": c, "r": r + 1, "g": g})
	return out

static func _build_wall_feet(parent: Node3D, rows: Array, mat: Material) -> void:
	var xf: Array = []
	for f in wall_feet(rows):
		var x := (float(f["c"]) + 0.5) * T
		var top := -float(f["r"]) * T
		var bot := -float(f["g"]) * T
		var d := WALL_FOOT_Z + DEPTH_BACK
		xf.append(Transform3D(Basis().scaled(Vector3(WALL_FOOT_W, top - bot, d)), Vector3(x, (top + bot) * 0.5, -DEPTH_BACK + d * 0.5)))
	_multimesh(parent, BoxMesh.new(), xf, mat)

## Martwe drzewo w miejscu pnia z mapy (kolumna `c`, kafle r0..r1−1): podstawa na dole ciągu, złamany wierzchołek TRUNK_OVER ponad jego górą.
## Odmiana, obrót i odcień z ziarna kolumny (każdy peer widzi to samo). false — brak modeli (zostaje słup).
static func _trunk_add(trunks: Dictionary, c: int, r0: int, r1: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c * 7919 + r0)
	var pick: Array = TRUNK_MODELS[rng.randi() % TRUNK_MODELS.size()]
	var tk: String = pick[0]
	if model_mesh(tk).is_empty():
		tk = "tree_snag"
		pick = TRUNK_MODELS[0]
		if model_mesh(tk).is_empty():
			return false
	var h := float(r1 - r0) * T + rng.randf_range(TRUNK_OVER[0], TRUNK_OVER[1])
	var sw := h / 100.0 * float(pick[1]) * rng.randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sw, h / 100.0, sw))
	basis = Basis().scaled(Vector3(1.0, 1.0, TRUNK_DEPTH)) * basis
	var foot := cell_pos(c, r1 - 1) + Vector3(0.0, -T * 0.5 - 0.15, TRUNK_Z)        # 0,15 m w ziemi: korzenie nie wiszą nad krawędzią kafla
	var v := rng.randf_range(0.85, 1.05)
	if not trunks.has(tk):
		trunks[tk] = []
	(trunks[tk] as Array).append([Transform3D(basis, foot), Color(v, v * 0.98, v * 0.95)])
	return true

static func build_level(parent: Node3D, rows: Array, trench := {}) -> Dictionary:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var box := BoxMesh.new()
	box.size = Vector3(T, T, DEPTH_FRONT + DEPTH_BACK)
	var groups := {"#": [], "C": [], "M": [], "m": [], "O": [], "~": []}
	var caps := {"#": [], "C": [], "M": [], "m": [], "O": [], "~": []}
	var walls: Array = []
	var planks: Array = []
	var grates: Array = []
	var marks := {"F": [], "E": [], "l": [], "k": []}
	var slabs := {}
	for s in tower_slabs(rows):
		for k in range(int(s["c0"]), int(s["c1"]) + 1):
			slabs[Vector2i(k, int(s["r"]))] = true
	var zc := (DEPTH_FRONT - DEPTH_BACK) * 0.5
	for r in nrows:
		for c in cols:
			var ch := _ch(rows, c, r)
			if ch == "C" and is_roof_cell(rows, c, r):
				continue                                            # dach z blachy na wiązarach zamiast pudła kafla (`_build_roofs`); znak mapy i kolizja bez zmian
			if ch == "M" and slabs.has(Vector2i(c, r)):
				continue                                            # dach / podłoga strażnicy: `_build_roofs` (kolizja kafla bez zmian)
			if groups.has(ch):
				# bryły tylko dla odsłoniętych kafli (sąsiad z powietrzem lub tłem); wnętrza skał zamyka od frontu płaski przekrój (`caps`),
				# bez niego pod skorupą gruntu widać było pustkę zamiast ziemi (flara czy wybuch nie miały czego oświetlić)
				if is_solid_ch(_ch(rows, c - 1, r)) and is_solid_ch(_ch(rows, c + 1, r)) and is_solid_ch(_ch(rows, c, r - 1)) and is_solid_ch(_ch(rows, c, r + 1)):
					caps[ch].append(Vector2i(c, r))
					continue
				var p := cell_pos(c, r)
				if (ch == "O" or ch == "~" or ch == "m") and _liquid_surface_col(rows, c, r, ch) and not "--noliquids" in OS.get_cmdline_user_args():
					continue                                    # ciecz / błoto: siatkę niecki i taflę rysuje `build_liquids`
				if not trench.is_empty() and r == int(trench["row"]) and c >= int(trench["c0"]) and c <= int(trench["c1"]):
					var full := DEPTH_FRONT + DEPTH_BACK
					var back_d := TRENCH_Z0 + DEPTH_BACK
					var bed_d := DEPTH_FRONT - TRENCH_Z0
					groups[ch].append(Transform3D(Basis().scaled(Vector3(1.0, 1.0, back_d / full)), p + Vector3(0.0, 0.0, TRENCH_Z0 - back_d * 0.5)))
					groups[ch].append(Transform3D(Basis().scaled(Vector3(1.0, (T - TRENCH_D) / T, bed_d / full)), p + Vector3(0.0, -TRENCH_D * 0.5, TRENCH_Z0 + bed_d * 0.5)))
					continue
				groups[ch].append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.0, zc)))
			if ch == "b" or _wall_behind(rows, c, r):
				walls.append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, 0.0, -DEPTH_BACK + 0.15)))
			if ch == "b":
				pass
			elif is_platform_ch(ch):
				(grates if ch == "=" else planks).append(Transform3D(Basis.IDENTITY, cell_pos(c, r) + Vector3(0.0, T * 0.5 - 0.1, 0.0)))
			elif ch == "F" or ch == "l" or ch == "k":
				marks[ch].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
			elif ch == "E" or ch == "e":
				marks["E"].append(cell_pos(c, r) + Vector3(0.0, -T * 0.5, 0.0))
	var mats := {
		"#": make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic"),
		"C": make_pbr("concrete", 0.33, Color(0.30, 0.31, 0.33), 0.9, 1.0, 1.0, false, "stone"),
		"roof": make_pbr("roof", 0.25, Color(0.30, 0.22, 0.20), 0.8, 1.0, 1.0, false, "rust"),
		"M": make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
		"m": make_pbr("mud", 0.30, Color(0.18, 0.2, 0.1), 1.0, 1.0, 1.0, false, "organic"),
	}
	# ciecze (olej, woda): kafle są tylko „dnem” (grunt mokry), ciecz to osobna taflą + przekrojem — patrz `build_liquids`
	var wet := make_pbr("terrain", 0.30, Color(0.12, 0.10, 0.08), 1.0, 1.0, 1.0, false, "organic")
	for k in ["O", "~", "m"]:
		mats[k] = wet                                           # kafle poniżej powierzchni cieczy: mokry grunt (nad nimi leży bryła)
	for k in groups:
		_multimesh(parent, box, groups[k], mats[k])
		_build_caps(parent, caps[k], mats[k])
	var wbox := BoxMesh.new()
	wbox.size = Vector3(T, T, 0.3)
	_multimesh(parent, wbox, walls, make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone"), false)
	var pc := CylinderMesh.new()
	pc.top_radius = 0.5                                     # równy promień: słup z kafli ma gładki zarys, a nie „stos kubków”
	pc.bottom_radius = 0.5
	pc.height = T
	pc.radial_segments = 10
	# słupy: pionowe ciągi (`post_runs`: `w` razem ze znacznikiem u podstawy i kładką, przez którą przechodzą) jako belki z modelu (odcinki do
	# 4 kafli, okucia na końcach kryją łączenia); bez modelu — walce z kafli. Słup przy kładce stoi tuż za jej pokładem.
	var beams: Array = []
	var posts: Array = []
	var ledgers: Array = []
	var trunks := {}                                       # model → [[Transform3D, Color], …]
	for run in post_runs(rows):
		var c: int = run["c"]
		var r0: int = run["r0"]
		var r1: int = run["r1"]
		var z: float = run["z"]
		if bool(run["tree"]) and _trunk_add(trunks, c, r0, r1):
			continue
		if bool(run["roof"]):
			continue
		var framed := frame_role(rows, run) != ""                 # maszt i nogi strażnicy: `Backdrop3D.build_frames` (belki pod kładkami zostają)
		var n := int(ceil(float(r1 - r0) / 4.0))
		var seg := float(r1 - r0) * T / float(n)
		for i in (0 if framed else n):
			var bottom := cell_pos(c, r1 - 1) + Vector3(0.0, -T * 0.5 + seg * float(i), z)
			beams.append(Transform3D(Basis().scaled(Vector3(POST_K, seg / 100.0, POST_K)), bottom))
		for k in range(r0, r1):
			if not framed:
				posts.append(Transform3D(Basis.IDENTITY, cell_pos(c, k) + Vector3(0.0, 0.0, z)))
			for dir in [-1, 1]:
				# kładka dochodzi do słupa z boku: belka pod jej końcem, od osi słupa pod pokład (za płaszczyzną gry)
				var dk := _ch(rows, c + dir, k)
				if not is_platform_ch(dk) or is_post_cell(rows, c + dir, k) or is_platform_ch(_ch(rows, c, k)):     # przez kładkę słup przechodzi sam
					continue
				var dh := deck_half(dk)
				var under: float = -float(k) * T - float(DECK_H[dk]) * T + 0.01
				var z0 := -dh + 0.12
				var len_x := T * 0.5 + 0.45
				var xc := cell_pos(c, k).x + float(dir) * len_x * 0.5
				ledgers.append(Transform3D(Basis().scaled(Vector3(len_x, 0.16, absf(z - z0))), Vector3(xc, under - 0.08, (z + z0) * 0.5)))
	for tk in trunks:
		var tm := model_mesh(tk)
		_forest_chunks(parent, tm[0], null, trunks[tk], true, tm[1])
	if not _multimodel(parent, "post", beams):
		_multimesh(parent, pc, posts, make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic"))
	var lm := make_pbr("post", 0.9, Color(0.20, 0.14, 0.09), 1.0, 1.0, 1.0, false, "organic").duplicate() as StandardMaterial3D
	lm.albedo_color = Color(0.45, 0.40, 0.36)                  # belki pod kładkami ciemne jak model słupa (tekstura „post" jest jaśniejsza od modelu z Tripo)
	_multimesh(parent, BoxMesh.new(), ledgers, lm)
	_build_roofs(parent, rows, mats["roof"], make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"),
			make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"), make_pbr("wall", 0.7, Color(0.20, 0.20, 0.22), 0.95, 1.0, 1.0, false, "stone"))
	_build_wall_feet(parent, rows, mats["C"])
	var plb := BoxMesh.new()
	plb.size = Vector3(T, 0.22, 1.3)
	# kładki z modeli: poziome ciągi kafli dzielone na równe odcinki (deski: 1 kafel, krata: ok. 3 kafle), co drugi obrócony o 180° dla odmiany;
	# góra pokładu na wysokości góry dawnej płyty (kolizja bez zmian). Bez modelu — płyty z teksturą.
	var decks := {"-": [], "=": []}
	for r in nrows:
		var c := 0
		while c < cols:
			var ch := _ch(rows, c, r)
			if not decks.has(ch):
				c += 1
				continue
			var c1 := c
			while c1 < cols and _ch(rows, c1, r) == ch:
				c1 += 1
			var per := 1.0 if ch == "-" else 3.0
			var n := maxi(1, int(round(float(c1 - c) / per)))
			var seg := float(c1 - c) * T / float(n)
			var hgt: float = DECK_H[ch] * T
			for i in n:
				var x := float(c) * T + seg * (float(i) + 0.5)
				var b := Basis(Vector3.UP, PI if (i + c + r) % 2 == 1 else 0.0).scaled(Vector3(seg / 100.0, per * T / 100.0, per * T / 100.0))
				(decks[ch] as Array).append(Transform3D(b, Vector3(x, -float(r) * T + 0.01 - hgt, 0.0)))
			c = c1
	if not _multimodel(parent, "walkway_plank", decks["-"]):
		_multimesh(parent, plb, planks, make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"))
	if not _multimodel(parent, "walkway_grate", decks["="]):
		_multimesh(parent, plb, grates, make_pbr("grate", 0.5, Color(0.28, 0.30, 0.34), 0.5, 1.0, 0.7, true))
	_build_deck_supports(parent, rows, make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic"),
			make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust"))
	return marks

const DECK_LEG_EVERY := 4                  ## kafli: najwyżej tyle między nogami pomostu
const DECK_LEG_REACH := 9                  ## kafli: najdalej tyle w dół do gruntu / pomostu (noga) albo w górę do stropu (wieszak)
const DECK_LEG_W := {"-": 0.16, "=": 0.12} ## m: przekrój nogi (drewno pod deskami, stal pod kratą)
const DECK_ROD_W := 0.04                   ## m: pręt wieszaka

## Pomost bez żadnej podpory: oba końce w powietrzu, bez ściany (`b`, bryła) obok, nad ani pod nim i bez słupa `w` przy nim.
static func deck_is_free(rows: Array, ch: String, r: int, c0: int, c1: int) -> bool:
	for e in [_ch(rows, c0 - 1, r), _ch(rows, c1 + 1, r)]:
		if is_solid_ch(e) or e == "b" or e == "w":
			return false
	for k in range(c0 - 1, c1 + 2):
		if _ch(rows, k, r - 1) == "w" or _ch(rows, k, r + 1) == "w":
			return false
		if k >= c0 and k <= c1 and (_ch(rows, k, r - 1) == "b" or _ch(rows, k, r + 1) == "b"):
			return false
	return true

## Podpory pomostów, które wisiały w powietrzu (schodki z pomostów, podesty w kopalni i w lesie): [{"r", "c0", "c1" (włącznie), "ch", "legs":
## [{"c", "x" (m), "kind": "stilt" — noga do gruntu / pomostu niżej w wierszu "to", "hang" — pręt do stropu w wierszu "to", "" — brak oparcia}]}].
## Nogi na końcach (0,3 m od krawędzi) i co najwyżej DECK_LEG_EVERY kafli; najpierw szukamy oparcia w dół, dopiero potem stropu nad pomostem.
static func deck_supports(rows: Array) -> Array:
	var out: Array = []
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	for r in nrows:
		var c := 0
		while c < cols:
			var ch := _ch(rows, c, r)
			if not is_platform_ch(ch):
				c += 1
				continue
			var c1 := c
			while c1 + 1 < cols and _ch(rows, c1 + 1, r) == ch:
				c1 += 1
			if deck_is_free(rows, ch, r, c, c1):
				var cols_at: Array = [c]
				var span := c1 - c
				var nseg := int(ceil(float(span) / float(DECK_LEG_EVERY)))
				for i in range(1, nseg):
					cols_at.append(c + int(round(float(span) * float(i) / float(nseg))))
				if c1 != c:
					cols_at.append(c1)
				var legs: Array = []
				for k in cols_at:
					var x := (float(k) + 0.5) * T
					if k == c and c1 != c:
						x = float(c) * T + 0.3
					elif k == c1 and c1 != c:
						x = float(c1 + 1) * T - 0.3
					var leg := {"c": k, "x": x, "kind": "", "to": -1}
					var g := r + 1
					while g < nrows and g - r <= DECK_LEG_REACH and not is_solid_ch(_ch(rows, k, g)) and not is_platform_ch(_ch(rows, k, g)):
						g += 1
					if g < nrows and g - r <= DECK_LEG_REACH:
						leg["kind"] = "stilt"
						leg["to"] = g
					else:
						var q := r - 1
						while q >= 0 and r - q <= DECK_LEG_REACH and not is_solid_ch(_ch(rows, k, q)):
							q -= 1
						if q >= 0 and r - q <= DECK_LEG_REACH:
							leg["kind"] = "hang"
							leg["to"] = q
					legs.append(leg)
				out.append({"r": r, "c0": c, "c1": c1, "ch": ch, "legs": legs})
			c = c1 + 1
	return out

## Nogi i wieszaki pomostów z `deck_supports` (wcześniej pomosty wisiały w powietrzu). Noga stoi tuż za tylną krawędzią pokładu (jak słup przy kładce),
## pod pokładem wspornik w poprzek do przedniej krawędzi, a przy dłuższej nodze zastrzał pod pokład. Drewno pod deskami `-`, stal pod kratą `=`.
## Tylko widok — kolizja kładki bez zmian.
static func _build_deck_supports(parent: Node3D, rows: Array, wood: Material, steel: Material) -> void:
	var parts := {"-": [], "=": []}
	for d in deck_supports(rows):
		var ch: String = d["ch"]
		var r: int = d["r"]
		var dh := deck_half(ch)
		var w: float = DECK_LEG_W[ch]
		var z := -(dh + w * 0.5) + POST_BITE
		var under: float = -float(r) * T - float(DECK_H[ch]) * T + 0.01
		var x_lo := float(int(d["c0"])) * T
		var x_hi := float(int(d["c1"]) + 1) * T
		var list: Array = parts[ch]
		for leg in d["legs"]:
			var x: float = leg["x"]
			var kind: String = leg["kind"]
			if kind == "":
				continue
			list.append(_span_box(Vector3(x - w * 0.5, under - w, z - w * 0.5), Vector3(x + w * 0.5, under, dh - 0.05)))        # wspornik pod pokładem
			if kind == "stilt":
				var to: int = leg["to"]
				var foot := -float(to) * T - (0.1 if is_solid_ch(_ch(rows, int(leg["c"]), to)) else 0.0)
				list.append(_span_box(Vector3(x - w * 0.5, foot, z - w * 0.5), Vector3(x + w * 0.5, under, z + w * 0.5)))
				if under - foot > 1.2:
					var dir := 1.0 if x < (x_lo + x_hi) * 0.5 else -1.0           # zastrzał w stronę środka pomostu
					list.append(_strut(Vector3(x, under - 0.6, z), Vector3(x + dir * 0.6, under - w * 0.5, z), w * 0.7))
			else:
				var top := -float(int(leg["to"]) + 1) * T
				list.append(_span_box(Vector3(x - DECK_ROD_W * 0.5, under - w, z - DECK_ROD_W * 0.5), Vector3(x + DECK_ROD_W * 0.5, top, z + DECK_ROD_W * 0.5)))
	var box := BoxMesh.new()
	_multimesh(parent, box, parts["-"], wood)
	_multimesh(parent, box, parts["="], steel)

## Ciecze i błoto jako zagłębienia o profilu przekroju, a nie prostokątne kafle o innym kolorze. Dla ciągu kafli powstaje:
##  - bryła gruntu pod nieckę (siatka z profilem: łagodnie opadające brzegi, nierówne dno), jej front z kamery widać jako przekrój;
##  - przekrój cieczy z boku (jak w akwarium): gradient głębi, kaustyki, linia tafli (`LIQUID_FRONT`);
##  - tafla (`LIQUID_TOP`): siatka z falami i przemieszczeniem wierzchołków, piana tam, gdzie ciecz jest płytka, tęczowa błona oleju, bryłki błota;
##  - grube zacieki po froncie sąsiedniego gruntu przy obu brzegach (`LIQUID_DRIP`) z kroplą na końcu i mokrym zaciemnieniem.
## Profil (głębokość pod krawędzią gruntu co ok. 0,12 m) trafia do shaderów jako tekstura `prof` (RH), więc tafla i przekrój używają tego samego kształtu.
const LIQUID_SINK := 0.04                  ## m: tafla oleju / wody leży tyle poniżej krawędzi gruntu (niecka pełna po brzegi; postacie w niej brodzą — `WADE`)
const LIQUID_SINK_MUD := 0.05              ## m: powierzchnia błota
## Brodzenie (tylko widok): o tyle pod taflę schodzą stopy postaci i wrogów stojących w cieczy — błoto do kostek, olej, woda do kolan.
## Fizyka zostaje na krawędzi kafla; model opuszcza widok (`wade_at`), a przy brzegu stopy idą po dnie niecki, więc wchodzi się stopniowo.
const WADE := [0.12, 0.34, 0.42]
const LIQUID_COMMON := """
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + vec2(17.1, 9.7); a *= 0.5; }
	return s;
}
"""
## Profil niecki i wysokość powierzchni (fale wody, grudy błota) — wspólne dla tafli i górnej krawędzi przekroju, żeby się schodziły.
const LIQUID_SURF := """
uniform sampler2D prof : filter_linear, repeat_disable;
uniform float x0 = 0.0;                // początek ciągu (m, świat)
uniform float run_w = 2.6;             // szerokość ciągu (m)
uniform float sink = 0.04;
uniform float z_back = -2.4;           // tył bryły (m) — tylny brzeg niecki: `shore_z` / `shore_k` (te same wzory w GDScript)
uniform float shore_back = 0.55;
uniform float shore_bank = 0.65;
float depth_at(float x) {
	return texture(prof, vec2(clamp((x - x0) / run_w, 0.0, 1.0), 0.5)).r;
}
float shore_k(vec2 w) {
	float zs = z_back + shore_back + 0.25 * sin(w.x * 0.9 + seed) + 0.12 * sin(w.x * 2.3 + seed * 1.7);
	return smoothstep(zs, zs + shore_bank, w.y);
}
float depth_xz(vec2 w) {
	return depth_at(w.x) * shore_k(w);
}
float surf_h(vec2 w, float wd) {
	float bank = smoothstep(0.0, 0.40, wd);
	if (kind == 0) {
		float rut = 0.5 + 0.5 * sin(w.x * 4.4 + fbm(w * 1.1 + seed) * 7.0);
		float lump = fbm(w * 2.3 + seed);
		float grit = vn(w * 7.5 + seed) - 0.5;                        // drobna nierówność: odciski, grudki
		return bank * (0.080 * lump + 0.050 * rut * smoothstep(0.35, 0.75, vn(w * vec2(0.5, 1.4) + seed)) + 0.030 * grit - 0.015);
	}
	float wave = 0.0;
	if (kind == 2) {
		wave = (sin(w.x * 2.3 + TIME * 0.9 + seed) * 0.5 + sin(w.x * 5.1 - TIME * 1.3 + w.y * 1.7) * 0.25) * 0.010 + (vn(w * 5.0 + vec2(TIME * 0.3, 0.0)) - 0.5) * 0.010;
	} else {
		wave = (vn(w * 3.0 + vec2(TIME * 0.05, 0.0)) - 0.5) * 0.005;
	}
	return wave * bank;
}
"""
## Tafla bez własnego światła (ciemność to mechanika, GDD §8.3): nocą widać ją tylko w świetle sceny — latarka, flara, ogień dają połysk.
const LIQUID_TOP := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform int kind = 0;                  // 0 błoto, 1 olej, 2 woda
uniform float seed = 0.0;
uniform vec4 prints[48];               // błoto: kroki przechodzących (view3d._sync_mud_prints) — x, z, czas powstania, kierunek ±1; „teraz” w print_now
uniform float print_now = 0.0;
varying vec2 v_w;
//COMMON
//SURF
// Rozdeptany pas błota wzdłuż drogi przechodzących: x = rozmiękłe, mokre błoto, y = wypchnięta obwódka; znika po 35–60 s.
// Pojedynczy odcisk stopy (~0,1 m w głąb) z bocznej kamery zajmuje ok. 1 px wysokości — widać dopiero pas szerokości ~0,5 m.
vec2 mud_print(vec2 p) {
	float inside = 0.0;
	float rim = 0.0;
	for (int i = 0; i < 48; i++) {
		vec4 pr = prints[i];
		float age = print_now - pr.z;
		if (pr.z <= 0.0 || age < 0.0 || age > 60.0) { continue; }
		vec2 d = p - pr.xy;
		d.x *= pr.w;
		float fade = 1.0 - smoothstep(35.0, 60.0, age);
		float brk = 0.82 + 0.36 * vn(p * 9.0 + pr.xy);                      // poszarpany brzeg zamiast gładkiej elipsy
		float e = length(vec2(d.x / 0.34, d.y / 0.24)) / brk;
		inside = max(inside, (1.0 - smoothstep(0.65, 1.0, e)) * fade);
		rim = max(rim, smoothstep(0.85, 1.0, e) * (1.0 - smoothstep(1.0, 1.3, e)) * fade);
	}
	return vec2(inside, rim);
}
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_w = wp.xz;
	v_w.x = wp.x;
	float vwd = depth_xz(wp.xz) - sink;
	VERTEX.y += surf_h(vec2(wp.x, wp.z), max(vwd, 0.0));
}
void fragment() {
	vec2 p = vec2(v_w.x, v_w.y);
	float wd_f = depth_xz(p) - sink;                                       // per piksel: linia tylnego brzegu bez schodków siatki
	if (wd_f < -0.01) { discard; }
	float wd = max(wd_f, 0.0);
	float e0 = 0.035;
	float h0 = surf_h(p, wd);
	float hx = surf_h(p + vec2(e0, 0.0), wd);
	float hz = surf_h(p + vec2(0.0, e0), wd);
	float k = (kind == 0) ? 1.2 : 2.2;
	vec3 n = normalize(vec3((h0 - hx) / e0 * k, 1.0, (h0 - hz) / e0 * k));
	vec2 q = p * ((kind == 0) ? 14.0 : 9.0);
	vec2 flow = (kind == 2) ? vec2(TIME * 0.35, TIME * 0.12) : ((kind == 1) ? vec2(TIME * 0.03, 0.0) : vec2(0.0));
	float r1 = vn(q + flow) - 0.5;
	float r2 = vn(q * 1.9 - flow * 1.3 + 7.0) - 0.5;
	float amp = (kind == 0) ? 0.22 : ((kind == 1) ? 0.05 : 0.16);
	n = normalize(n + vec3(r1, 0.0, r2) * amp);
	if (kind == 0) {                                                       // błoto: drobne grudki i odciski w normalnych
		n = normalize(n + vec3(vn(p * 38.0) - 0.5, 0.0, vn(p * 41.0 + 3.0) - 0.5) * 0.45);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float edge = 1.0 - smoothstep(0.0, 0.35, wd);                          // przy brzegu ciecz jest płytka: piana, grubsza błona, widać dno
	if (kind == 0) {
		// mokre, ciemne błoto: placki rozmokłe (gładsze, ale matowe — bez lustrzanych białych plam), skorupa tylko przy brzegu i stonowana
		float wetn = smoothstep(0.52, 0.70, fbm(p * 1.7 + seed * 2.0));
		vec3 dry = mix(vec3(0.036, 0.027, 0.019), vec3(0.060, 0.045, 0.031), fbm(p * 3.2));
		vec3 mud = mix(dry, vec3(0.020, 0.015, 0.011), wetn * 0.85) * (0.80 + 0.35 * vn(p * 22.0));
		float crust = smoothstep(0.60, 0.85, fbm(p * 5.0 + seed)) * edge;
		vec2 fp = mud_print(p);
		ALBEDO = mix(mud, vec3(0.072, 0.055, 0.039), crust * 0.5 * (1.0 - fp.x)) * (1.0 - 0.45 * fp.x) * (1.0 + 0.25 * fp.y);
		ROUGHNESS = mix(mix(0.86, 0.48, wetn), 0.14, fp.x);                   // woda wyciśnięta w rozdeptanym pasie: błyszczy w świetle latarki
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, fp.x * 0.8));
		SPECULAR = 0.32;
		ALPHA = smoothstep(-0.01, 0.06, wd_f);
	} else if (kind == 1) {
		float film = fbm(p * 1.4 + seed);
		float ph = film * 11.0 + TIME * 0.04;
		vec3 irid = vec3(0.5 + 0.5 * sin(ph), 0.5 + 0.5 * sin(ph + 2.1), 0.5 + 0.5 * sin(ph + 4.2));
		ALBEDO = vec3(0.010, 0.010, 0.013) + irid * 0.050 * (0.35 + edge * 1.2);
		ROUGHNESS = 0.045;
		SPECULAR = 1.0;
		ALPHA = 0.97 * smoothstep(-0.01, 0.05, wd_f);
	} else {
		// mętna woda torfowa (herbaciano-oliwkowa), przy brzegu przejaśnia ją dno, piana brudna; połysk daje tylko światło sceny
		float foam = edge * smoothstep(0.42, 0.66, fbm(p * 7.0 + vec2(TIME * 0.18, 0.0)));
		float depthc = smoothstep(0.05, 0.6, wd);
		vec3 wat = mix(vec3(0.105, 0.090, 0.056), vec3(0.042, 0.038, 0.025), depthc) + vec3(0.10, 0.088, 0.060) * foam;
		ALBEDO = wat;
		ROUGHNESS = mix(0.16, 0.6, foam);
		SPECULAR = 0.6;
		ALPHA = clamp(0.92 + foam * 0.08, 0.0, 1.0) * smoothstep(-0.01, 0.05, wd_f);
	}
}
"""
const LIQUID_FRONT := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform int kind = 2;                  // 0 błoto, 1 olej, 2 woda
uniform float y_s = 0.0;               // poziom tafli (m, świat)
uniform float seed = 0.0;
varying vec3 v_w;
//COMMON
//SURF
void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (abs(v_w.y - y_s) < 0.002) {                            // górna krawędź przekroju idzie za falą / grudami tafli (bez prostej „deski”)
		float h = surf_h(v_w.xz, max(depth_at(v_w.x) - sink, 0.0));
		VERTEX.y += h;
		v_w.y += h;
	}
}
void fragment() {
	float d = max(y_s - v_w.y, 0.0);                          // głębokość pod taflą (m)
	float line = 1.0 - smoothstep(0.0, 0.03, d);               // linia tafli
	if (kind == 2) {
		// mętna woda torfowa: szybko gęstnieje w głąb, zawiesina zamiast kaustyk (te wymagałyby słońca)
		float t = 1.0 - exp(-d * 2.6);
		float silt = fbm(vec2(v_w.x * 3.1 + seed, v_w.y * 4.0 - TIME * 0.02));
		ALBEDO = mix(vec3(0.052, 0.044, 0.026), vec3(0.010, 0.009, 0.006), t) * (0.75 + 0.5 * silt) + vec3(0.060, 0.055, 0.040) * line;
		ALPHA = mix(0.80, 0.97, t);
		ROUGHNESS = 0.12;
	} else if (kind == 1) {
		float t = 1.0 - exp(-d * 1.1);
		float sheen = smoothstep(0.30, 0.70, fbm(vec2(v_w.x * 1.6 + TIME * 0.03, v_w.y * 2.2)));
		ALBEDO = mix(vec3(0.030, 0.030, 0.038), vec3(0.008, 0.008, 0.012), t) + vec3(0.05, 0.04, 0.08) * sheen * 0.6 * (1.0 - t * 0.5) + vec3(0.10, 0.11, 0.14) * line;
		ALPHA = 0.96;
		ROUGHNESS = 0.07;
	} else {
		// błoto: mokre i ciemne, płytka przeschnięta warstwa u góry (stonowana), żyłki i grudki w przekroju
		float t = 1.0 - exp(-d * 1.1);
		float crust = 1.0 - smoothstep(0.0, 0.10, d + (fbm(vec2(v_w.x * 5.0, 0.7)) - 0.5) * 0.1);
		float vein = smoothstep(0.55, 0.75, fbm(vec2(v_w.x * 3.0 + seed, v_w.y * 6.0)));
		float grit = vn(vec2(v_w.x * 24.0, v_w.y * 24.0) + seed);
		float mott = fbm(vec2(v_w.x * 7.0 + seed, v_w.y * 12.0));                // smugi rozmokłego i gęstszego błota
		vec3 wetc = mix(vec3(0.040, 0.030, 0.021), vec3(0.016, 0.012, 0.009), t);
		ALBEDO = mix(wetc, vec3(0.068, 0.052, 0.037), crust * 0.6) * (0.8 + 0.3 * vein) * (0.85 + 0.3 * grit) * (0.6 + 0.7 * mott);
		// dół warstwy przechodzi w ziemię pod niecką (bez ostrej krawędzi „deski”)
		float above_bed = v_w.y - (y_s + sink - depth_at(v_w.x));
		ALPHA = smoothstep(0.0, 0.14, above_bed + (vn(vec2(v_w.x * 9.0, seed)) - 0.5) * 0.06);
		ROUGHNESS = mix(0.36, 0.78, crust) + 0.2 * (1.0 - mott);
	}
	SPECULAR = 0.6;
}
"""
const LIQUID_DRIP := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform int kind = 0;                  // 0 błoto, 1 olej, 2 woda (mokry ślad)
uniform float seed = 0.0;
uniform float side = 1.0;              // +1: quad rośnie w prawo od brzegu, −1: w lewo
uniform vec2 qsize = vec2(1.3, 1.7);   // wymiar quada (m); lewy górny róg przy brzegu niecki
varying vec2 v_l;
//COMMON
void vertex() {
	v_l = UV;
}
void fragment() {
	// współrzędne w metrach od narożnika przy brzegu: x w głąb gruntu, y w dół
	float mx = abs(v_l.x - ((side > 0.0) ? 0.0 : 1.0)) * qsize.x;
	float my = v_l.y * qsize.y;
	// mokre zaciemnienie przy brzegu: nieregularny kształt, wyższe przy samej niecce
	float stain_h = 0.55 + 0.4 * fbm(vec2(mx * 3.0 + seed, 2.0));
	float stain = (1.0 - smoothstep(0.0, qsize.x * 0.9, mx + (fbm(vec2(my * 2.2, seed)) - 0.5) * 0.35)) * (1.0 - smoothstep(0.0, stain_h * 1.1, my));
	// grube zacieki: pasy po ~0,3 m, część wyłączona; szerokość 0,13–0,27 m, zbieżne, zakończone kroplą
	float cell = floor(mx / 0.30 + seed);
	float lane = fract(mx / 0.30 + seed);
	float h = h21(vec2(cell, seed + 1.0));
	float h2 = h21(vec2(cell * 1.7, seed + 4.0));
	float len = (0.20 + 0.95 * pow(h, 1.4)) * step(0.22, h2) * (1.0 - 0.45 * smoothstep(0.0, qsize.x, mx));   // dłuższe przy samym brzegu
	float cx = 0.5 + (h2 - 0.5) * 0.30 + 0.07 * sin(my * 7.0 + h * 6.0) + 0.04 * (vn(vec2(my * 5.0, cell)) - 0.5);
	float wid = (0.36 + 0.24 * h) * (1.0 - 0.50 * smoothstep(0.0, max(len, 0.01), my)) * (0.85 + 0.30 * vn(vec2(my * 9.0 + cell, 2.0)));
	float inlane = 1.0 - smoothstep(wid * 0.5, wid * 0.5 + 0.10, abs(lane - cx));
	float along = 1.0 - smoothstep(len - 0.10, len, my);
	float bulb = 1.0 - smoothstep(0.0, 0.13, length(vec2((lane - cx) * 0.30, my - len + 0.07)));
	float drip = max(inlane * along, bulb * step(0.14, len));
	float a = max(drip, stain * 0.55);
	vec3 base;
	float rough_v;
	if (kind == 0) { base = vec3(0.050, 0.035, 0.024); rough_v = 0.22; }
	else if (kind == 1) { base = vec3(0.016, 0.016, 0.020); rough_v = 0.05; }
	else { base = vec3(0.034, 0.029, 0.019); rough_v = 0.1; }
	ALBEDO = base * (0.8 + 0.4 * vn(vec2(mx * 28.0, my * 11.0)));
	ALPHA = clamp(a, 0.0, 1.0) * ((kind == 2) ? 0.7 : 1.0);
	ROUGHNESS = rough_v;
	SPECULAR = 0.9;
	ALBEDO += vec3(0.04) * bulb * ((kind == 0) ? 0.5 : 1.0);
}
"""
const DECAL_DIR := "res://art/world3d/decals/"
## Dekale (sprite'y z `tools/world_decals_gen.py`): [szerokość, wysokość w kaflach, powierzchnie (b tło, C beton, M metal), waga, odbicie dozwolone].
## Duży wariant (×1) wymaga wolnego prostokąta kafli tej samej powierzchni; gdy go nie ma, próbujemy połowy rozmiaru.
const DECALS := {
	"g_dont_listen": [4, 2, "bC", 1.0, false], "g_they_hear": [4, 2, "bC", 1.0, false], "g_silence": [4, 2, "bC", 0.8, false],
	"g_no_exit": [4, 2, "bC", 0.9, false], "g_patrol7": [4, 2, "bC", 0.9, false], "g_help": [4, 2, "b", 0.8, false],
	"g_run": [4, 2, "bCM", 0.8, false], "g_47": [4, 2, "bCM", 0.5, false], "g_eye": [4, 2, "bC", 0.9, true],
	"g_tally": [4, 2, "bCM", 0.7, true], "g_arrow": [4, 2, "bCM", 0.7, true], "g_xcircle": [4, 2, "bCM", 0.7, true],
	"g_hand": [3, 3, "bC", 0.6, true],
	"d_soot": [4, 4, "bC", 1.1, true], "d_water": [3, 3, "bCM", 1.4, true], "d_crack_a": [3, 3, "bC", 1.2, true],
	"d_crack_b": [3, 3, "bC", 1.2, true], "d_bullets": [3, 3, "bCM", 1.2, true], "d_plaster": [3, 3, "bC", 1.0, true],
	"d_rustbleed": [3, 3, "bM", 1.2, true], "d_damp": [4, 4, "bC", 1.1, true],
}

## Ślady zniszczeń na ścianach: grafiti, pęknięcia, ślady po kulach, sadza, zacieki, odpryski. Rozmieszczenie deterministyczne (ziarno z mapy), więc
## każdy peer widzi to samo; tylko widok. `--nodecals` wyłącza.
static func build_decals(parent: Node3D, rows: Array) -> void:
	if "--nodecals" in OS.get_cmdline_user_args():
		return
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var surf := {}                                              # (c, r) → powierzchnia: "b" (ściana tła), "C" / "M" (odsłonięty kafel)
	for r in nrows:
		for c in cols:
			var ch := _ch(rows, c, r)
			if ch == "b":
				surf[Vector2i(c, r)] = "b"
			elif (ch == "C" and not is_roof_cell(rows, c, r)) or ch == "M":       # na blasze dachu (cienki arkusz na wiązarach) dekal by wisiał
				if not (is_solid_ch(_ch(rows, c - 1, r)) and is_solid_ch(_ch(rows, c + 1, r)) and is_solid_ch(_ch(rows, c, r - 1)) and is_solid_ch(_ch(rows, c, r + 1))):
					surf[Vector2i(c, r)] = ch
	if surf.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rows))
	var names: Array = DECALS.keys()
	var used := {}
	var inst := {}
	var budget := 160
	var anchors: Array = surf.keys()
	for k in anchors:
		if budget <= 0:
			break
		if rng.randf() > 0.07 or used.has(k):
			continue
		var kind: String = surf[k]
		var cand: Array = []
		var tot := 0.0
		for nm in names:
			if (DECALS[nm][2] as String).contains(kind):
				cand.append(nm)
				tot += float(DECALS[nm][3])
		if cand.is_empty():
			continue
		var pick := rng.randf() * tot
		var name: String = cand[0]
		for nm in cand:
			pick -= float(DECALS[nm][3])
			if pick <= 0.0:
				name = nm
				break
		var d: Array = DECALS[name]
		for sc in [1.0, 0.5]:
			var wt := maxi(1, int(round(float(d[0]) * sc)))
			var ht := maxi(1, int(round(float(d[1]) * sc)))
			if not _decal_fits(k, wt, ht, kind, surf, used):
				continue
			for dy in ht:
				for dx in wt:
					used[Vector2i(k.x + dx, k.y + dy)] = true
			var z := (DEPTH_FRONT + 0.012) if kind != "b" else (-DEPTH_BACK + 0.3 + 0.012)
			var ctr := cell_pos(float(k.x), float(k.y)) + Vector3(float(wt - 1) * T * 0.5, -float(ht - 1) * T * 0.5, 0.0)
			ctr.z = z
			var sx := T * float(wt) * (-1.0 if (bool(d[4]) and rng.randf() < 0.5) else 1.0)
			var rot := rng.randf_range(-0.05, 0.05) if bool(d[4]) else 0.0
			var bas := Basis(Vector3.BACK, rot) * Basis.from_scale(Vector3(sx, T * float(ht), 1.0))
			if not inst.has(name):
				inst[name] = []
			inst[name].append(Transform3D(bas, ctr))
			budget -= 1
			break
	for name in inst:
		var path := DECAL_DIR + String(name) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path) as Texture2D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.95
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.render_priority = 1
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var arr: Array = inst[name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = q
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Decals_" + String(name)
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

static func _decal_fits(k: Vector2i, wt: int, ht: int, kind: String, surf: Dictionary, used: Dictionary) -> bool:
	for dy in ht:
		for dx in wt:
			var p := Vector2i(k.x + dx, k.y + dy)
			if used.has(p) or not surf.has(p) or String(surf[p]) != kind:
				return false
	return true

## Czy komórka (c, r) cieczy / błota jest pod powierzchnią ciągu, który rysuje `build_liquids` (nad kolumną aż do pierwszej innej komórki nie ma bryły).
static func _liquid_surface_col(rows: Array, c: int, r: int, ch: String) -> bool:
	var rr := r
	while _ch(rows, c, rr - 1) == ch:
		rr -= 1
	return not is_solid_ch(_ch(rows, c, rr - 1))

## Szum wartościowy 1D dla profilu (deterministyczny z ziarna).
static func _vn1(x: float, seed: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	var a := fposmod(sin((i + seed * 12.9898) * 78.233) * 43758.5453, 1.0)
	var b := fposmod(sin((i + 1.0 + seed * 12.9898) * 78.233) * 43758.5453, 1.0)
	return lerpf(a, b, f)

## Profil niecki (głębokość pod krawędzią gruntu, m) w `ns + 1` próbkach: łagodnie opadające brzegi o szerokości `bank` m, nierówne dno, zmienna głębokość.
## `cap` — maks. głębokość per próbka (grubość stosu kafli pod kolumną), żeby niecka nie przebiła gruntu.
static func _liquid_profile(w: float, ns: int, d0: float, bank: float, seed: float, cap: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ns + 1)
	for i in ns + 1:
		var x := w * float(i) / float(ns)
		var e := minf(x, w - x)
		var shape := smoothstep(0.0, bank, e)
		shape = pow(shape, 0.85)
		var wob := 0.80 + 0.40 * _vn1(x * 0.62, seed) + 0.10 * (_vn1(x * 2.7, seed + 3.0) - 0.5)
		out[i] = minf(d0 * shape * wob, cap[i])
	return out

## Tylny brzeg niecki: zamiast prostej krawędzi na tyle bryły ciecz kończy się falistą linią `shore_z` (średnio SHORE_BACK m przed tyłem bryły),
## za którą dno podnosi się skarpą szerokości SHORE_BANK do poziomu gruntu. Te same wzory liczą shadery (`LIQUID_SURF`: shore_k, depth_xz).
const SHORE_BACK := 0.55
const SHORE_BANK := 0.65

## z (m) linii tylnego brzegu ciągu nad pozycją x. `back`: odległość brzegu od tyłu bryły (ciąg ze strumieniem: ujemna — brzegu nie ma).
static func shore_z(x: float, seed: float, back := SHORE_BACK) -> float:
	return -DEPTH_BACK + back + 0.25 * sin(x * 0.9 + seed) + 0.12 * sin(x * 2.3 + seed * 1.7)

## 0 na linii brzegu i dalej w głąb, 1 za skarpą (pełna głębokość profilu).
static func shore_k(x: float, z: float, seed: float, back := SHORE_BACK) -> float:
	var zs := shore_z(x, seed, back)
	return smoothstep(zs, zs + SHORE_BANK, z)

## Odległość tylnego brzegu dla ciągu [x0, x0 + w]: SHORE_BACK albo — gdy ciąg zasila strumień z lasu (`streams`) — brzeg daleko za bryłą,
## więc woda sięga tyłu bryły i łączy się z korytem (`build_streams`).
static func run_shore_back(x0: float, w: float) -> float:
	for st in streams:
		if float(st["x"]) > x0 and float(st["x"]) < x0 + w:
			return -10.0
	return SHORE_BACK

# ---------------------------------------------------------------- strumień z lasu (kosmetyka)

## Strumienie z danych mapy (`level.streams`, STREAMS: [kolumna od, kolumna do] ciągu wody): {x — środek przy bryle, hw — pół szerokości przy bryle,
## ph — faza meandrów}. Ustawia widok przed budową (`set_streams`); czytają je niecka (brak tylnego brzegu), koryto, las (omija koryto) i trzcina.
static var streams: Array = []
const STREAM_LEN := 30.0                   ## m w głąb od tyłu bryły; dalej koryto znika w ciemności (dno lasu też ciemnieje w głąb)
const STREAM_HW_FAR := 1.6                 ## m: pół szerokości koryta w lesie (przy bryle — szerokość ciągu wody)

static func set_streams(list: Array) -> void:
	streams = []
	for e in list:
		var c0 := int(e[0])
		var c1 := int(e[1])
		streams.append({"x": float(c0 + c1 + 1) * 0.5 * T, "hw": float(c1 - c0 + 1) * T * 0.5, "ph": float(c0) * 0.37})

## Środek koryta (x, m) na głębokości `d` (m w głąb od płaszczyzny gry, ≥ DEPTH_BACK): przy bryle prosto, dalej meandruje.
static func stream_x(st: Dictionary, d: float) -> float:
	var e := maxf(d - DEPTH_BACK, 0.0)
	var ph: float = st["ph"]
	return float(st["x"]) + 2.4 * sin(e * 0.11 + ph) * smoothstep(0.0, 10.0, e) + 1.1 * sin(e * 0.29 + ph * 2.1) * smoothstep(0.0, 6.0, e)

## Pół szerokości koryta (m) na głębokości `d`: od szerokości brodu do STREAM_HW_FAR w ~12 m.
static func stream_hw(st: Dictionary, d: float) -> float:
	var e := maxf(d - DEPTH_BACK, 0.0)
	return lerpf(float(st["hw"]), STREAM_HW_FAR, smoothstep(0.0, 12.0, e)) * (0.9 + 0.2 * sin(d * 0.4 + float(st["ph"])))

## x przesunięty poza koryto (na bliższy brzeg, `margin` m od wody), gdy punkt (x, głębokość d) leży w korycie; inaczej bez zmian.
static func out_of_stream(x: float, d: float, margin: float) -> float:
	if streams.is_empty() or d > DEPTH_BACK + STREAM_LEN + 2.0 or d < DEPTH_BACK - 0.5:
		return x
	for st in streams:
		var cx := stream_x(st, d)
		var lim := stream_hw(st, d) + margin
		if absf(x - cx) < lim:
			return cx + (lim if x >= cx else -lim)
	return x

## Nurt: mętna woda torfowa jak w niecce (bez własnego światła, GDD §8.3), wzór i pasma piany płyną ku kamerze; po bokach mokry brzeg,
## który przechodzi w dno lasu. Ciemnieje w głąb jak dno lasu (kolor wierzchołków), a za ~20 m gaśnie. Mgłę przyjmuje (bez niej w snopie latarki,
## gdzie mgła wolumetryczna rozjaśnia wszystko wokół, koryto było czarną plamą).
const STREAM_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform float bank = 0.22;             // część szerokości z każdej strony: mokry brzeg zamiast wody
uniform float flow = 0.55;             // m/s: nurt ku kamerze
uniform float fade0 = 18.0;
uniform float fade1 = 30.0;
varying float v_shade;
//COMMON
void vertex() {
	v_shade = COLOR.r;
}
void fragment() {
	float u = UV.x;                       // 0..1 w poprzek (z brzegami)
	float v = UV.y;                       // m wzdłuż koryta od tyłu bryły
	float edge = min(u, 1.0 - u);
	float wob = (vn(vec2(v * 0.7, 2.0)) - 0.5) * 0.06;                   // łagodnie falisty brzeg (wcześniej poszarpany szumem w poprzek)
	float water = smoothstep(bank - 0.03, bank + 0.03, edge + wob);
	vec2 q = vec2(u * 7.0, v * 1.7 + TIME * flow * 1.7);
	float r1 = vn(q) - 0.5;
	float r2 = vn(q * 1.9 + 7.0) - 0.5;
	vec3 n = normalize(vec3(r1 * 0.30 * water, 1.0, r2 * 0.30 * water));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float streak = smoothstep(0.60, 0.80, fbm(vec2(u * 9.0, v * 0.6 + TIME * flow * 0.6))) * smoothstep(0.30, 0.45, edge);
	// ta sama woda torfowa co płycizna niecki (LIQUID_TOP przy brzegu) i mokry brzeg jaśniejszy od nurtu — w latarce koryto nie jest czarną plamą
	vec3 wat = mix(vec3(0.105, 0.090, 0.056), vec3(0.070, 0.062, 0.040), smoothstep(0.30, 0.50, edge)) + vec3(0.10, 0.088, 0.060) * streak * 0.6;
	vec3 mud = vec3(0.062, 0.050, 0.036) * (0.8 + 0.4 * vn(vec2(u * 24.0, v * 7.0)));
	ALBEDO = mix(mud, wat, water) * v_shade;
	ROUGHNESS = mix(0.55, mix(0.18, 0.5, streak), water);
	SPECULAR = 0.6;
	ALPHA = smoothstep(0.0, 0.12, edge + wob * 0.5) * (1.0 - smoothstep(fade0, fade1, v + DEPTH_BACK_C));
}
"""

## Koryto strumieni: wstęga na dnie lasu od tyłu bryły w głąb (woda + mokre brzegi), kamienie w nurcie, trzcina wzdłuż brzegów.
static func build_streams(parent: Node3D, rows: Array) -> void:
	if streams.is_empty():
		return
	var ft := forest_terrain(rows)
	if ft.is_empty():
		return
	var sh := Shader.new()
	sh.code = STREAM_SHADER.replace("//COMMON", LIQUID_COMMON).replace("DEPTH_BACK_C", str(DEPTH_BACK))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57E4
	var rocks: Array = []
	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	var rc := PackedColorArray()
	var ri := PackedInt32Array()
	for si in streams.size():
		var st: Dictionary = streams[si]
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var across := 9
		var d := DEPTH_BACK - 0.02
		var rowc := 0
		while d <= DEPTH_BACK + STREAM_LEN:
			var cx := stream_x(st, d)
			var hw := stream_hw(st, d) / (1.0 - 2.0 * 0.22)              # wstęga szersza o mokre brzegi (`bank` w shaderze)
			var e := d - DEPTH_BACK
			var shade := lerpf(1.0, 0.3, smoothstep(DEPTH_BACK, 40.0, d))
			for k in across:
				var u := float(k) / float(across - 1)
				var x := cx + (u * 2.0 - 1.0) * hw
				var y := forest_ground_y(ft, x, maxf(d, DEPTH_BACK)) + 0.05 - 0.07 * (1.0 - smoothstep(0.0, 2.5, e))     # przy bryle równo z taflą niecki
				verts.append(Vector3(x, y, -d))
				nrms.append(Vector3.UP)
				uvs.append(Vector2(u, e))
				cols.append(Color(shade, shade, shade))
			rowc += 1
			d += 0.5 + e * 0.04
		for j in rowc - 1:
			for k in across - 1:
				var a := j * across + k                                   # a, b: bliżej kamery; c, d: dalej
				var b := a + 1
				var c := a + across
				var dd := c + 1
				idx.append_array(PackedInt32Array([a, c, b, c, dd, b]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = nrms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := ShaderMaterial.new()
		m.shader = sh
		var mi := MeshInstance3D.new()
		mi.name = "Stream_%d" % si
		mi.mesh = am
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | LAYER_FOREST
		parent.add_child(mi)
		# kamienie w nurcie i przy brzegach (rzadziej dalej)
		var rd := DEPTH_BACK + 0.8
		while rd < DEPTH_BACK + STREAM_LEN * 0.8:
			var side := rng.randf_range(-1.0, 1.0)
			var rx := stream_x(st, rd) + side * stream_hw(st, rd) * 0.95
			var size := rng.randf_range(0.30, 0.75) * (1.2 if absf(side) > 0.7 else 1.0)
			rocks.append([Vector3(rx, forest_ground_y(ft, rx, rd) - 0.06, -rd), size, rng.randf() * TAU])
			rd += rng.randf_range(0.9, 2.2) + (rd - DEPTH_BACK) * 0.08
		# trzcina i turzyca wzdłuż obu brzegów (bliżej gęściej)
		var bd := DEPTH_BACK + 0.4
		while bd < DEPTH_BACK + 20.0:
			for sd in [-1.0, 1.0]:
				if rng.randf() < 0.25:
					continue
				var bx: float = stream_x(st, bd) + sd * (stream_hw(st, bd) + rng.randf_range(-0.15, 0.45))
				var by := forest_ground_y(ft, bx, bd)
				for b in rng.randi_range(6, 12):
					var base := Vector3(bx + rng.randf_range(-0.3, 0.3), by - 0.02, -bd + rng.randf_range(-0.3, 0.3))
					var hh := rng.randf_range(0.7, 1.7)
					var lean := Vector3(rng.randf_range(-0.25, 0.25) * hh, 0.0, rng.randf_range(-0.10, 0.10) * hh)
					_blade(rv, rn, rc, ri, base, hh, rng.randf_range(0.022, 0.036), rng.randf() * TAU, lean,
						Color(0.050, 0.095, 0.045), Color(0.150, 0.165, 0.080), rng.randf() < 0.18)
			bd += rng.randf_range(0.8, 1.5) + (bd - DEPTH_BACK) * 0.05
	var rock := model_mesh("rock")
	if not rock.is_empty() and not rocks.is_empty():
		var local: Transform3D = rock[1]
		var ab := local * (rock[0] as Mesh).get_aabb()
		var big := maxf(maxf(ab.size.x, ab.size.z), 0.001)
		var list: Array = []
		for r in rocks:
			var k := float(r[1]) / big
			var b := Basis(Vector3.UP, float(r[2])).scaled(Vector3(k, k * 0.7, k))
			list.append([Transform3D(b, r[0]), Color(0.8, 0.8, 0.78)])
		var first := parent.get_child_count()
		_forest_chunks(parent, rock[0], null, list, false, local)
		for i in range(first, parent.get_child_count()):
			var vi := parent.get_child(i) as VisualInstance3D
			if vi != null:
				vi.layers = 1 | LAYER_FOREST
	if rv.size() > 0:
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = rv
		arr2[Mesh.ARRAY_NORMAL] = rn
		arr2[Mesh.ARRAY_COLOR] = rc
		arr2[Mesh.ARRAY_INDEX] = ri
		var am2 := ArrayMesh.new()
		am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		var rsh := Shader.new()
		rsh.code = REED_SHADER
		var rm := ShaderMaterial.new()
		rm.shader = rsh
		var reeds := MeshInstance3D.new()
		reeds.name = "StreamReeds"
		reeds.mesh = am2
		reeds.material_override = rm
		reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		reeds.layers = 1 | LAYER_FOREST
		parent.add_child(reeds)

## Tafle i bryły błota, oleju i wody (patrz opis przy `LIQUID_SINK`). Ciąg = kolejne kafle tego samego rodzaju w wierszu, nad którymi nie ma bryły.
static func build_liquids(parent: Node3D, rows: Array) -> void:
	if "--noliquids" in OS.get_cmdline_user_args():
		return
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var kinds := {"m": 0, "O": 1, "~": 2}
	var top_sh := Shader.new()
	top_sh.code = LIQUID_TOP.replace("//COMMON", LIQUID_COMMON).replace("//SURF", LIQUID_SURF)
	var front_sh := Shader.new()
	front_sh.code = LIQUID_FRONT.replace("//COMMON", LIQUID_COMMON).replace("//SURF", LIQUID_SURF)
	var drip_sh := Shader.new()
	drip_sh.code = LIQUID_DRIP.replace("//COMMON", LIQUID_COMMON)
	var wet := make_pbr("terrain", 0.30, Color(0.12, 0.10, 0.08), 1.0, 1.0, 1.0, false, "organic")
	var zf := DEPTH_FRONT
	var zb := -DEPTH_BACK
	for r in nrows:
		var c := 0
		while c < cols:
			var ch := _ch(rows, c, r)
			if not kinds.has(ch) or is_solid_ch(_ch(rows, c, r - 1)):
				c += 1
				continue
			var c1 := c
			while c1 < cols and _ch(rows, c1, r) == ch and not is_solid_ch(_ch(rows, c1, r - 1)):
				c1 += 1
			var kd: int = kinds[ch]
			var n := c1 - c
			var x0 := float(c) * T
			var w := float(n) * T
			var y_top := -float(r) * T                         # krawędź gruntu
			var seed := float((c * 31 + r * 17) % 97)
			var sink := LIQUID_SINK_MUD if kd == 0 else LIQUID_SINK
			var y_s := y_top - sink                            # poziom tafli
			# grubość stosu pod każdą kolumną ciągu
			var stack: Array = []
			for cc in range(c, c1):
				var dpt := 1
				while _ch(rows, cc, r + dpt) == ch:
					dpt += 1
				stack.append(dpt)
			var per_tile := 10
			var ns := n * per_tile
			var cap := PackedFloat32Array()
			cap.resize(ns + 1)
			for i in ns + 1:
				var col := mini(i / per_tile, n - 1)
				cap[i] = float(stack[col]) * T * 0.85
			var d0 := clampf(0.50 + 0.065 * w, 0.70, 1.20) if kd > 0 else clampf(0.26 + 0.030 * w, 0.34, 0.60)
			var bank := 0.75 if kd > 0 else 0.55
			var prof := _liquid_profile(w, ns, d0, bank, seed, cap)

			# --- bryła gruntu pod nieckę: front (przekrój), dno niecki (powierzchnia profilu) i boki ciągu
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var idx := PackedInt32Array()
			for i in ns + 1:
				var x := x0 + w * float(i) / float(ns)
				var col := mini(i / per_tile, n - 1)
				var yb := y_top - float(stack[col]) * T
				var yt := y_top - prof[i]
				# front (z = +DEPTH_FRONT): dwa wierzchołki na próbkę
				verts.append(Vector3(x, yt, zf))
				verts.append(Vector3(x, yb, zf))
				norms.append(Vector3.BACK)
				norms.append(Vector3.BACK)
			for i in ns:
				var a := i * 2
				idx.append_array(PackedInt32Array([a, a + 2, a + 3, a, a + 3, a + 1]))      # w Godocie front = zgodnie z ruchem wskazówek
			# dno: siatka x × z — w głąb profil wypłyca się skarpą tylnego brzegu (`shore_k`), gęściej przy samej skarpie
			var zrows: Array = []
			var zz := zb
			while zz < zb + SHORE_BACK + 0.37 + SHORE_BANK:
				zrows.append(zz)
				zz += 0.12
			zrows.append(zf)
			var nz := zrows.size()
			var dx := w / float(ns)
			var sback := run_shore_back(x0, w)
			var bed_h := func(i: int, z: float) -> float:
				var xi := clampi(i, 0, ns)
				return y_top - prof[xi] * shore_k(x0 + dx * float(xi), z, seed, sback)
			var base := verts.size()
			for i in ns + 1:
				var x := x0 + dx * float(i)
				for j in nz:
					var z: float = zrows[j]
					var dz := 0.06
					var hx := (float(bed_h.call(i + 1, z)) - float(bed_h.call(i - 1, z))) / (dx * float(mini(i + 1, ns) - maxi(i - 1, 0)))
					var hz := (float(bed_h.call(i, z + dz)) - float(bed_h.call(i, z - dz))) / (2.0 * dz)
					verts.append(Vector3(x, bed_h.call(i, z), z))
					norms.append(Vector3(-hx, 1.0, -hz).normalized())   # powierzchnia opada ku środkowi niecki i od tylnego brzegu
			for i in ns:
				for j in nz - 1:
					var g0 := base + i * nz + j                         # (x_i, z_j) — z_j bliżej tyłu niż z_(j+1)
					var g1 := base + (i + 1) * nz + j
					idx.append_array(PackedInt32Array([g0, g1, g1 + 1, g0, g1 + 1, g0 + 1]))
			# boki ciągu (widoczne, gdy obok jest powietrze): pionowe ściany od profilu w dół na pełną głębokość
			for sidec in [0, 1]:
				var xi := 0 if sidec == 0 else ns
				var x := x0 if sidec == 0 else x0 + w
				var yt := y_top - prof[xi]
				var yb := y_top - float(stack[0 if sidec == 0 else n - 1]) * T
				var nsd := Vector3(-1.0 if sidec == 0 else 1.0, 0.0, 0.0)
				var b0 := verts.size()
				verts.append_array(PackedVector3Array([Vector3(x, yt, zf), Vector3(x, yb, zf), Vector3(x, yb, zb), Vector3(x, yt, zb)]))
				norms.append_array(PackedVector3Array([nsd, nsd, nsd, nsd]))
				if sidec == 0:
					idx.append_array(PackedInt32Array([b0 + 3, b0, b0 + 1, b0 + 3, b0 + 1, b0 + 2]))
				else:
					idx.append_array(PackedInt32Array([b0, b0 + 3, b0 + 2, b0, b0 + 2, b0 + 1]))
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var shell := MeshInstance3D.new()
			shell.name = "LiquidBed_%s_%d_%d" % [ch, c, r]
			shell.mesh = am
			shell.material_override = wet
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			parent.add_child(shell)

			# --- tekstura profilu dla shaderów
			var pimg := Image.create(ns + 1, 1, false, Image.FORMAT_RH)
			for i in ns + 1:
				pimg.set_pixel(i, 0, Color(prof[i], 0.0, 0.0))
			var ptex := ImageTexture.create_from_image(pimg)

			# --- przekrój cieczy z boku (front, tuż przed frontem gruntu): między taflą a profilem
			var fv := PackedVector3Array()
			var fi := PackedInt32Array()
			for i in ns + 1:
				var x := x0 + w * float(i) / float(ns)
				var yb2 := minf(y_top - prof[i], y_s)
				fv.append(Vector3(x, y_s, zf + 0.012))
				fv.append(Vector3(x, yb2, zf + 0.012))
			for i in ns:
				var a := i * 2
				fi.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))
			var fa := []
			fa.resize(Mesh.ARRAY_MAX)
			fa[Mesh.ARRAY_VERTEX] = fv
			fa[Mesh.ARRAY_INDEX] = fi
			var fm := ArrayMesh.new()
			fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fa)
			var fmat := ShaderMaterial.new()
			fmat.shader = front_sh
			fmat.set_shader_parameter("kind", kd)
			fmat.set_shader_parameter("y_s", y_s)
			fmat.set_shader_parameter("seed", seed)
			fmat.set_shader_parameter("prof", ptex)
			fmat.set_shader_parameter("x0", x0)
			fmat.set_shader_parameter("run_w", w)
			fmat.set_shader_parameter("sink", sink)
			for sp in [["z_back", zb], ["shore_back", sback], ["shore_bank", SHORE_BANK]]:
				fmat.set_shader_parameter(sp[0], sp[1])
			var fmi := MeshInstance3D.new()
			fmi.name = "LiquidFront_%s_%d_%d" % [ch, c, r]
			fmi.mesh = fm
			fmi.material_override = fmat
			fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(fmi)

			# --- tafla (siatka z falami i przemieszczeniem)
			var pm := PlaneMesh.new()
			pm.size = Vector2(w, zf - zb)
			pm.subdivide_width = maxi(8, int(w * 10.0))
			pm.subdivide_depth = 20
			var sm := ShaderMaterial.new()
			sm.shader = top_sh
			sm.set_shader_parameter("kind", kd)
			sm.set_shader_parameter("prof", ptex)
			sm.set_shader_parameter("x0", x0)
			sm.set_shader_parameter("run_w", w)
			sm.set_shader_parameter("sink", sink)
			for sp in [["z_back", zb], ["shore_back", sback], ["shore_bank", SHORE_BANK]]:
				sm.set_shader_parameter(sp[0], sp[1])
			sm.set_shader_parameter("seed", seed)
			var tmi := MeshInstance3D.new()
			tmi.name = "LiquidTop_%s_%d_%d" % [ch, c, r]
			tmi.mesh = pm
			tmi.material_override = sm
			tmi.position = Vector3(x0 + w * 0.5, y_s, (zf + zb) * 0.5)
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(tmi)

			# --- zacieki po froncie sąsiedniego gruntu przy obu brzegach (grube, z kroplą), tylko gdzie sąsiad jest bryłą
			for sd in [-1.0, 1.0]:
				var nc := (c - 1) if sd < 0.0 else c1
				if not is_solid_ch(_ch(rows, nc, r)):
					continue
				var qsz := Vector2(1.3, 1.7)
				var qm := QuadMesh.new()
				qm.size = qsz
				var dm := ShaderMaterial.new()
				dm.shader = drip_sh
				dm.set_shader_parameter("kind", kd)
				dm.set_shader_parameter("seed", seed + (3.0 if sd < 0.0 else 8.0))
				dm.set_shader_parameter("side", -sd)
				dm.set_shader_parameter("qsize", qsz)
				var di := MeshInstance3D.new()
				di.name = "LiquidDrip_%s_%d_%d_%d" % [ch, c, r, int(sd)]
				di.mesh = qm
				di.material_override = dm
				var ex := x0 if sd < 0.0 else x0 + w                  # brzeg niecki
				di.position = Vector3(ex + sd * qsz.x * 0.5, y_top - qsz.y * 0.5 + 0.03, zf + 0.016)
				di.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(di)
			c = c1

## Rekwizyty cieczy (po `build_liquids`): kałuże odbijające światło, rozchlapane krople, trzcina i patyki przy brzegu, bąble gazu w oleju i błocie.
## Wszystko deterministyczne z ziarna mapy; `--noliquidprops` wyłącza. Dynamiczne rozbryzgi od kroków: `view3d.gd` (`_splash_update`).
const PROP_COMMON := """
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vn(p); p = p * 2.03 + vec2(17.1, 9.7); a *= 0.5; }
	return s;
}
"""
## Kałuża: nieregularny owal z niskim roughness — światła sceny (flary, latarka, lampy) dają w niej prawdziwe błyski; bez własnej poświaty (GDD §8.3).
const PUDDLE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
varying vec2 v_uv;
varying float v_seed;
//COMMON
void vertex() {
	v_uv = UV;
	v_seed = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 p = (v_uv - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float edge = 0.78 + 0.20 * (fbm(vec2(ang * 1.3 + v_seed * 3.0, v_seed)) - 0.5) * 2.0 + 0.10 * (vn(vec2(cos(ang), sin(ang)) * 4.0 + v_seed) - 0.5);
	float a = 1.0 - smoothstep(edge - 0.16, edge, r);
	if (a < 0.01) { discard; }
	float t = TIME * 0.4;
	vec2 q = p * 3.5 + vec2(v_seed);
	vec3 n = normalize(vec3((vn(q + vec2(t, 0.0)) - 0.5) * 0.10, 1.0, (vn(q * 1.7 - vec2(0.0, t)) - 0.5) * 0.10));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = vec3(0.013, 0.012, 0.010);
	ROUGHNESS = 0.035;
	SPECULAR = 1.0;
	ALPHA = a * 0.90;
}
"""
## Rozchlapane krople: kropki o zmiennej wielkości, gęstsze przy brzegu (uv.x = 0 przy brzegu), z wydłużeniem w dół na froncie.
const SPLAT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform int kind = 0;                  // 0 błoto, 1 olej, 2 woda
uniform float seed = 0.0;
uniform float side = 1.0;
uniform float vert = 1.0;              // 1: front (krople ściekają w dół), 0: wierzch (okrągłe)
uniform vec2 qsize = vec2(1.5, 1.2);
varying vec2 v_l;
//COMMON
void vertex() { v_l = UV; }
void fragment() {
	float mx = abs(v_l.x - ((side > 0.0) ? 0.0 : 1.0)) * qsize.x;
	float my = v_l.y * qsize.y;
	float dens = exp(-mx * 1.7);
	float cell = 0.085;
	vec2 g = vec2(mx, my) / cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = h21(id + vec2(seed, seed * 1.3));
	float h2 = h21(id * 1.7 + vec2(seed + 5.0, 2.0));
	float on = step(1.0 - 0.55 * dens - 0.04, h);                                   // gęstość maleje od brzegu
	vec2 jit = vec2(h2 - 0.5, fract(h * 7.0) - 0.5) * 0.45;
	float rad = (0.10 + 0.22 * h2) * (0.5 + 0.9 * dens);
	vec2 d = f - jit;
	d.y /= mix(1.0, 1.9, vert * h2);                                                // krople wydłużone w dół
	float dot_ = 1.0 - smoothstep(rad * 0.6, rad, length(d));
	float a = dot_ * on;
	if (a < 0.02) { discard; }
	vec3 base = (kind == 0) ? vec3(0.040, 0.029, 0.020) : ((kind == 1) ? vec3(0.014, 0.014, 0.018) : vec3(0.034, 0.029, 0.019));
	ALBEDO = base;
	ALPHA = a * ((kind == 2) ? 0.65 : 0.95);
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
"""
## Trzcina, patyki: cienkie wstęgi i pryzmy z kolorem wierzchołkowym; alfa koloru = waga kołysania (u podstawy 0, na końcu 1).
const REED_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform float sway = 0.045;
uniform vec4 pushers[8];               // przechodzący (view3d._sync_reeds): x, y stóp, z, siła 0..1 — kępy rozchylają się na boki i lekko kładą
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = COLOR.a;
	VERTEX.x += (sin(TIME * 1.25 + wp.x * 2.3 + wp.z * 1.7) * 0.7 + sin(TIME * 2.9 + wp.x * 5.0) * 0.3) * sway * k * k;
	for (int i = 0; i < 8; i++) {
		vec4 pu = pushers[i];
		if (pu.w <= 0.0) { continue; }
		float dxp = wp.x - pu.x;
		float dzp = wp.z - pu.z;
		float f = exp(-dxp * dxp / 0.09) * (1.0 - smoothstep(0.30, 0.75, abs(dzp))) * step(pu.y - 0.4, wp.y) * step(wp.y, pu.y + 2.4);
		float s = pu.w * f * k * k;
		VERTEX.x += sign(dxp) * 0.32 * s;
		VERTEX.z += sign(dzp) * 0.10 * s;
		VERTEX.y -= 0.14 * s;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
}
"""

## Ciągi cieczy / błota w mapie (jak w `build_liquids`): [{ch, kd, c, c1, r, x0, w, y_top, seed, stack}].
static func _liquid_runs(rows: Array) -> Array:
	var out: Array = []
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var kinds := {"m": 0, "O": 1, "~": 2}
	for r in nrows:
		var c := 0
		while c < cols:
			var ch := _ch(rows, c, r)
			if not kinds.has(ch) or is_solid_ch(_ch(rows, c, r - 1)):
				c += 1
				continue
			var c1 := c
			while c1 < cols and _ch(rows, c1, r) == ch and not is_solid_ch(_ch(rows, c1, r - 1)):
				c1 += 1
			var stack: Array = []
			for cc in range(c, c1):
				var dpt := 1
				while _ch(rows, cc, r + dpt) == ch:
					dpt += 1
				stack.append(dpt)
			out.append({"ch": ch, "kd": kinds[ch], "c": c, "c1": c1, "r": r, "x0": float(c) * T, "w": float(c1 - c) * T,
				"y_top": -float(r) * T, "seed": float((c * 31 + r * 17) % 97), "stack": stack})
			c = c1
	return out

## Profil niecki ciągu (jak w `build_liquids`): `[próbki co 0,131 m od początku ciągu]`.
static func _run_profile(run: Dictionary) -> PackedFloat32Array:
	var n: int = int(run["c1"]) - int(run["c"])
	var w: float = run["w"]
	var kd: int = run["kd"]
	var per_tile := 10
	var ns := n * per_tile
	var cap := PackedFloat32Array()
	cap.resize(ns + 1)
	for i in ns + 1:
		cap[i] = float((run["stack"] as Array)[mini(i / per_tile, n - 1)]) * T * 0.85
	var d0 := clampf(0.50 + 0.065 * w, 0.70, 1.20) if kd > 0 else clampf(0.26 + 0.030 * w, 0.34, 0.60)
	var bank := 0.75 if kd > 0 else 0.55
	return _liquid_profile(w, ns, d0, bank, float(run["seed"]), cap)

## Mapa brodzenia: wiersz kafli → ciągi cieczy w nim [{x0, w, kd, prof}] (patrz `WADE`, `wade_at`).
static func wade_map(rows: Array) -> Dictionary:
	var out := {}
	for run in _liquid_runs(rows):
		var r: int = run["r"]
		if not out.has(r):
			out[r] = []
		(out[r] as Array).append({"x0": run["x0"], "w": run["w"], "kd": run["kd"], "prof": _run_profile(run)})
	return out

## O ile opuścić model (m), którego stopy stoją w `feet_px` (px świata): stopy schodzą po dnie niecki, najwyżej `WADE` pod taflę; 0 poza cieczą.
static func wade_at(wmap: Dictionary, feet_px: Vector2) -> float:
	var r := int(floor((feet_px.y + 1.0) / TILE))
	if not wmap.has(r):
		return 0.0
	var xm := feet_px.x * PX
	for run in wmap[r]:
		var x0: float = run["x0"]
		var w: float = run["w"]
		if xm < x0 or xm > x0 + w:
			continue
		var prof: PackedFloat32Array = run["prof"]
		var ns := prof.size() - 1
		var f := clampf((xm - x0) / w, 0.0, 1.0) * float(ns)
		var i := mini(int(f), ns - 1)
		var depth := lerpf(prof[i], prof[i + 1], f - float(i))
		var kd: int = run["kd"]
		return minf(depth, (LIQUID_SINK_MUD if kd == 0 else LIQUID_SINK) + float(WADE[kd]))
	return 0.0

## Zasłona brodzenia dla warstwy graczy (rysowanej osobną kamerą na wierzchu świata, więc tafla ich nie zakrywa): pudło z wierzchem na poziomie
## tafli i frontem przekroju. Mnoży (blend_mul) tylko piksele, na których już jest postać: z bufora głębi odtwarza punkt modelu za zasłoną
## i im głębiej pod taflą, tym mniej go widać (mętna woda, nieprzejrzyste błoto i olej). Puste piksele warstwy (alfa 0) zostają puste.
const WADE_VEIL_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float y_s = 0.0;               // poziom tafli (m, świat)
uniform vec3 tint = vec3(0.6, 0.55, 0.4);
uniform float keep = 0.3;              // ile widać tuż pod taflą
uniform float fade = 6.0;              // zanik widoczności w głąb (1/m)
void fragment() {
	float z = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(v.xyz / v.w, 1.0)).xyz;
	float under = y_s - wp.y;
	float vis = mix(1.0, keep * exp(-max(under, 0.0) * fade), smoothstep(-0.005, 0.03, under));
	ALBEDO = mix(tint, vec3(1.0), vis);
	ALPHA = vis;
}
"""
static func build_wade_veils(parent: Node3D, rows: Array, layer: int) -> void:
	if "--noliquids" in OS.get_cmdline_user_args():
		return
	var sh := Shader.new()
	sh.code = WADE_VEIL_SHADER
	var zf := DEPTH_FRONT + 0.02
	var zb := -0.9                                             # za modelami graczy (płaszczyzna gry z = 0, drezyna wysuwa ich ku kamerze)
	# [odcień, widoczność tuż pod taflą, zanik] wg rodzaju: błoto, olej, woda
	var look := [[Color(0.35, 0.27, 0.20), 0.10, 14.0], [Color(0.25, 0.25, 0.28), 0.12, 12.0], [Color(0.62, 0.56, 0.40), 0.40, 5.5]]
	for run in _liquid_runs(rows):
		var kd: int = run["kd"]
		var y_s: float = float(run["y_top"]) - (LIQUID_SINK_MUD if kd == 0 else LIQUID_SINK)
		var prof := _run_profile(run)
		var deep := 0.0
		for d in prof:
			deep = maxf(deep, d)
		var x0: float = run["x0"]
		var w: float = run["w"]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("y_s", y_s)
		var lk: Array = look[kd]
		var tc: Color = lk[0]
		m.set_shader_parameter("tint", Vector3(tc.r, tc.g, tc.b))
		m.set_shader_parameter("keep", float(lk[1]))
		m.set_shader_parameter("fade", float(lk[2]))
		var top := MeshInstance3D.new()
		top.name = "WadeVeilTop_%d_%d" % [int(run["c"]), int(run["r"])]
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, zf - zb)
		top.mesh = pm
		top.position = Vector3(x0 + w * 0.5, y_s, (zf + zb) * 0.5)
		var front := MeshInstance3D.new()
		front.name = "WadeVeilFront_%d_%d" % [int(run["c"]), int(run["r"])]
		var qm := QuadMesh.new()
		var hgt := deep - (float(run["y_top"]) - y_s) + 0.1        # od tafli do najgłębszego miejsca niecki
		qm.size = Vector2(w, hgt)
		front.mesh = qm
		front.position = Vector3(x0 + w * 0.5, y_s - hgt * 0.5, zf)
		for mi in [top, front]:
			(mi as MeshInstance3D).material_override = m
			(mi as MeshInstance3D).layers = layer
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)

static func _blade(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array, base: Vector3, h: float, wid: float,
		yaw: float, lean: Vector3, c_base: Color, c_tip: Color, cattail: bool) -> void:
	var right := Vector3(cos(yaw), 0.0, sin(yaw))
	var face := Vector3(-sin(yaw), 0.0, cos(yaw))
	var ts: Array = [0.0, 0.3, 0.6, 0.82, 1.0]
	var ws: Array = [1.0, 0.85, 0.62, 0.38, 0.0]
	if cattail:
		# pałka: brązowy kłos ~0,15–0,25 m i ok. 2–3 cm grubości, nad nim cienki szpic (wcześniej czarna łopata szeroka na ~20 cm)
		ts = [0.0, 0.3, 0.6, 0.77, 0.79, 0.84, 0.89, 0.91, 1.0]
		ws = [0.9, 0.70, 0.50, 0.32, 0.85, 0.95, 0.85, 0.12, 0.0]
	var b0 := v.size()
	for i in ts.size():
		var t: float = ts[i]
		var p := base + Vector3(0.0, h * t, 0.0) + lean * (t * t)
		var wv := wid * float(ws[i])
		var is_head := cattail and t >= 0.78 and t <= 0.90
		var c := c_base.lerp(c_tip, t)
		if is_head:
			c = Color(0.092, 0.055, 0.030).lerp(Color(0.060, 0.036, 0.020), absf(t - 0.84) * 12.0)
		c.a = t
		v.append(p - right * wv)
		v.append(p + right * wv)
		nrm.append(face)
		nrm.append(face)
		col.append(c)
		col.append(c)
	for i in ts.size() - 1:
		var a := b0 + i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))

static func _stick(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array, p0: Vector3, p1: Vector3, rad: float, c: Color) -> void:
	var d := (p1 - p0)
	if d.length() < 0.01:
		return
	var u := d.normalized()
	var a := u.cross(Vector3.UP)
	if a.length() < 0.1:
		a = u.cross(Vector3.RIGHT)
	a = a.normalized()
	var b := u.cross(a).normalized()
	var b0 := v.size()
	for k in 4:
		var ang := float(k) * PI * 0.5
		var off := (a * cos(ang) + b * sin(ang)) * rad
		var nn := (a * cos(ang) + b * sin(ang)).normalized()
		var cc := c
		cc.a = 0.0
		v.append(p0 + off)
		v.append(p1 + off * 0.65)
		nrm.append(nn)
		nrm.append(nn)
		col.append(cc)
		col.append(cc)
	for k in 4:
		var k2 := (k + 1) % 4
		var a0 := b0 + k * 2
		var a1 := b0 + k2 * 2
		idx.append_array(PackedInt32Array([a0, a1, a1 + 1, a0, a1 + 1, a0 + 1]))

## Środki kęp trzciny (m, świat; y = podstawa) z ostatniego `build_liquid_props` — widok ugina je przy przechodzących i odtwarza szelest (`view3d._reeds_update`).
static var reed_spots := PackedVector3Array()

static func build_liquid_props(parent: Node3D, rows: Array) -> void:
	reed_spots = PackedVector3Array()
	if "--noliquidprops" in OS.get_cmdline_user_args():
		return
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rows)) + 77
	var runs := _liquid_runs(rows)
	var zf := DEPTH_FRONT
	var zb := -DEPTH_BACK
	var puddle_shader := Shader.new()
	puddle_shader.code = PUDDLE_SHADER.replace("//COMMON", PROP_COMMON)
	var splat_shader := Shader.new()
	splat_shader.code = SPLAT_SHADER.replace("//COMMON", PROP_COMMON)
	var reed_shader := Shader.new()
	reed_shader.code = REED_SHADER

	# ---------------- kałuże: na odsłoniętym wierzchu gruntu i betonu, częściej blisko cieczy
	var near: Dictionary = {}
	for run in runs:
		for cc in range(int(run["c"]) - 7, int(run["c1"]) + 7):
			near[Vector2i(cc, int(run["r"]))] = true
	var pud: Array = []
	var pud_n := 0
	for r in nrows:
		for c in cols:
			var ch := _ch(rows, c, r)
			if (ch != "#" and ch != "C") or is_solid_ch(_ch(rows, c, r - 1)):
				continue
			var p := 0.07 + (0.28 if near.has(Vector2i(c, r)) else 0.0)
			if rng.randf() > p or pud_n >= 110:
				continue
			var wd := rng.randf_range(0.8, 2.1)
			var dp := rng.randf_range(0.5, 1.5)
			var x := (float(c) + rng.randf()) * T
			var y := -float(r) * T + (0.105 if ch == "#" else 0.012)
			var z := rng.randf_range(zb + 0.9, zf - 0.35)
			var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(wd, dp, 1.0))
			pud.append([Transform3D(b, Vector3(x, y, z)), rng.randf() * 50.0])
			pud_n += 1
	if not pud.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mm.mesh = q
		mm.instance_count = pud.size()
		for i in pud.size():
			mm.set_instance_transform(i, pud[i][0])
			mm.set_instance_custom_data(i, Color(float(pud[i][1]), 0.0, 0.0, 0.0))
		var pm := ShaderMaterial.new()
		pm.shader = puddle_shader
		var pi := MultiMeshInstance3D.new()
		pi.name = "Puddles"
		pi.multimesh = mm
		pi.material_override = pm
		pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(pi)

	if runs.is_empty():
		return
	# ---------------- trzcina i patyki (jedna siatka na całą mapę)
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for run in runs:
		var kd: int = run["kd"]
		var x0: float = run["x0"]
		var w: float = run["w"]
		var y_top: float = run["y_top"]
		var c: int = run["c"]
		var c1: int = run["c1"]
		var r: int = run["r"]
		var sink := LIQUID_SINK_MUD if kd == 0 else LIQUID_SINK
		var y_s := y_top - sink
		var prof := _run_profile(run)
		var ns := prof.size() - 1
		var greens := kd == 2
		var cb := Color(0.050, 0.095, 0.045) if greens else Color(0.085, 0.070, 0.038)
		var ct := Color(0.150, 0.165, 0.080) if greens else Color(0.185, 0.155, 0.080)
		var stick_c := Color(0.055, 0.040, 0.027)
		for sd in [-1, 1]:
			var nc := (c - 1) if sd < 0 else c1
			if not is_solid_ch(_ch(rows, nc, r)):
				continue
			var edge := x0 if sd < 0 else x0 + w
			var ground_y := y_top + (0.095 if _ch(rows, nc, r) == "#" else 0.0)
			# kępy na brzegu
			var clumps := rng.randi_range(2, 4)
			for k in clumps:
				var cx := edge + float(sd) * rng.randf_range(0.12, 1.1)
				var cz := rng.randf_range(zb + 0.9, zf - 0.25)
				var nb := rng.randi_range(5, 12)
				reed_spots.append(Vector3(cx, ground_y, cz))
				for b in nb:
					var base := Vector3(cx + rng.randf_range(-0.22, 0.22), ground_y - 0.02, cz + rng.randf_range(-0.18, 0.18))
					var hh := rng.randf_range(0.55, 1.55)
					var lean := Vector3(rng.randf_range(-0.30, 0.30) * hh, 0.0, rng.randf_range(-0.12, 0.12) * hh)
					_blade(v, nr, col, idx, base, hh, rng.randf_range(0.020, 0.036), rng.randf() * TAU, lean, cb, ct, rng.randf() < 0.32)
			# kępy w płytkiej wodzie przy brzegu (tam, gdzie głębokość < 0,35 m)
			if kd > 0:
				for k in rng.randi_range(1, 3):
					var fx := rng.randf_range(0.15, 0.9)
					var xi := int(clampf((fx if sd < 0 else (w - fx)) / w * float(ns), 0.0, float(ns)))
					if prof[xi] > 0.40:
						continue
					var bx := x0 + (float(xi) / float(ns)) * w
					var by := y_top - prof[xi] + 0.02
					var wz := rng.randf_range(maxf(zb + 1.0, shore_z(bx, float(run["seed"]), run_shore_back(x0, w)) + SHORE_BANK), zf - 0.45)
					reed_spots.append(Vector3(bx, by, wz))
					for b in rng.randi_range(4, 9):
						var base := Vector3(bx + rng.randf_range(-0.16, 0.16), by, wz + rng.randf_range(-0.25, 0.25))
						var hh := rng.randf_range(0.6, 1.4) + prof[xi]
						var lean := Vector3(rng.randf_range(-0.25, 0.25) * hh, 0.0, rng.randf_range(-0.10, 0.10) * hh)
						_blade(v, nr, col, idx, base, hh, rng.randf_range(0.020, 0.034), rng.randf() * TAU, lean, cb, ct, rng.randf() < 0.28)
			# patyki na gruncie przy brzegu: leżące i oparte
			for k in rng.randi_range(2, 5):
				var sx := edge + float(sd) * rng.randf_range(0.15, 1.6)
				var sz := rng.randf_range(zb + 0.8, zf - 0.3)
				var yaw := rng.randf() * TAU
				var ln := rng.randf_range(0.35, 1.5)
				var tilt := rng.randf_range(0.0, 0.55) if rng.randf() < 0.35 else rng.randf_range(0.0, 0.08)
				var d := Vector3(cos(yaw) * cos(tilt), sin(tilt), sin(yaw) * cos(tilt))
				var p0 := Vector3(sx, ground_y + 0.015, sz)
				_stick(v, nr, col, idx, p0, p0 + d * ln, rng.randf_range(0.012, 0.028), stick_c.lerp(Color(0.09, 0.07, 0.05), rng.randf()))
		# tylny brzeg: pas trzciny (woda) albo turzycy (błoto) wzdłuż falistej linii brzegu — tam, gdzie staw przechodzi w dno lasu
		var sback := run_shore_back(x0, w)
		if kd != 1 and sback > 0.0:
			var sx := x0 + rng.randf_range(0.1, 0.5)
			while sx < x0 + w - 0.1:
				var xi := int(clampf((sx - x0) / w * float(ns), 0.0, float(ns)))
				var zs := shore_z(sx, float(run["seed"]))
				var cz := zs + rng.randf_range(-0.20, 0.30)
				var by := y_top - prof[xi] * shore_k(sx, cz, float(run["seed"]))
				var tall := 1.0 if kd == 2 else 0.6
				reed_spots.append(Vector3(sx, by, cz))
				for b in rng.randi_range(7, 14):
					var base := Vector3(sx + rng.randf_range(-0.28, 0.28), by - 0.02, cz + rng.randf_range(-0.22, 0.22))
					var hh := rng.randf_range(0.7, 1.8) * tall
					var lean := Vector3(rng.randf_range(-0.25, 0.25) * hh, 0.0, rng.randf_range(-0.10, 0.10) * hh)
					_blade(v, nr, col, idx, base, hh, rng.randf_range(0.022, 0.038), rng.randf() * TAU, lean, cb, ct, kd == 2 and rng.randf() < 0.18)
				sx += rng.randf_range(0.45, 0.95)
		# patyki i kępy pływające / wystające z cieczy
		if kd > 0 and w >= 2.0:
			for k in rng.randi_range(1, 3):
				var fx := rng.randf_range(0.3, w - 0.3)
				var xi := int(clampf(fx / w * float(ns), 0.0, float(ns)))
				if prof[xi] - sink < 0.12:
					continue
				var yaw := rng.randf_range(-0.5, 0.5) + (PI * 0.5 if rng.randf() < 0.2 else 0.0)
				var ln := rng.randf_range(0.35, 1.0)
				var p0 := Vector3(x0 + fx, y_s + 0.012, rng.randf_range(maxf(zb + 1.0, shore_z(x0 + fx, float(run["seed"]), run_shore_back(x0, w)) + SHORE_BANK), zf - 0.5))
				var d := Vector3(cos(yaw), 0.0, sin(yaw))
				_stick(v, nr, col, idx, p0, p0 + d * ln, rng.randf_range(0.012, 0.024), stick_c)
	if v.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var rm := ShaderMaterial.new()
		rm.shader = reed_shader
		var ri := MeshInstance3D.new()
		ri.name = "ShoreReeds"
		ri.mesh = am
		ri.material_override = rm
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(ri)

	# ---------------- rozchlapane krople na froncie i wierzchu gruntu przy brzegach
	for run in runs:
		var kd: int = run["kd"]
		var x0: float = run["x0"]
		var w: float = run["w"]
		var y_top: float = run["y_top"]
		var c: int = run["c"]
		var c1: int = run["c1"]
		var r: int = run["r"]
		for sd in [-1, 1]:
			var nc := (c - 1) if sd < 0 else c1
			if not is_solid_ch(_ch(rows, nc, r)):
				continue
			var edge := x0 if sd < 0 else x0 + w
			var ground_y := y_top + (0.095 if _ch(rows, nc, r) == "#" else 0.0)
			for face in [0, 1]:
				var qsz := Vector2(1.5, 1.25) if face == 0 else Vector2(1.7, 2.6)
				var qm := QuadMesh.new()
				qm.size = qsz
				var dm := ShaderMaterial.new()
				dm.shader = splat_shader
				dm.set_shader_parameter("kind", kd)
				dm.set_shader_parameter("seed", float(run["seed"]) + float(face) * 4.0 + (2.0 if sd < 0 else 0.0))
				dm.set_shader_parameter("side", float(-sd))
				dm.set_shader_parameter("vert", 1.0 if face == 0 else 0.0)
				dm.set_shader_parameter("qsize", qsz)
				var mi := MeshInstance3D.new()
				mi.name = "LiquidSplat_%d_%d_%d_%d" % [c, r, sd, face]
				mi.mesh = qm
				mi.material_override = dm
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if face == 0:
					mi.position = Vector3(edge + float(sd) * qsz.x * 0.5, y_top - qsz.y * 0.5 - 0.1, zf + 0.02)
				else:
					mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
					mi.position = Vector3(edge + float(sd) * qsz.x * 0.5, ground_y + 0.004, (zf + zb) * 0.5 + 0.2)
				parent.add_child(mi)

	# ---------------- bąble gazu: olej (z dna niecki, w przekroju) i błoto (pęcherze na wierzchu — nie na froncie gruntu)
	# bez emisji: ciemne i błyszczące, widać je dopiero w świetle sceny (GDD §8.3)
	var bmesh := SphereMesh.new()
	bmesh.radius = 0.5
	bmesh.height = 1.0
	bmesh.radial_segments = 8
	bmesh.rings = 4
	var bmat_oil := StandardMaterial3D.new()
	bmat_oil.albedo_color = Color(0.030, 0.030, 0.036, 0.85)
	bmat_oil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat_oil.roughness = 0.05
	bmat_oil.metallic_specular = 1.0
	bmat_oil.rim_enabled = true
	bmat_oil.rim = 0.3
	var bmat_mud := StandardMaterial3D.new()
	bmat_mud.albedo_color = Color(0.030, 0.023, 0.016)
	bmat_mud.roughness = 0.22
	bmat_mud.metallic_specular = 0.6
	var bcurve := Curve.new()
	bcurve.add_point(Vector2(0.0, 0.5))
	bcurve.add_point(Vector2(0.15, 1.0))
	bcurve.add_point(Vector2(0.88, 1.0))
	bcurve.add_point(Vector2(1.0, 0.0))
	var blister := Curve.new()                                     # pęcherz błota: powoli rośnie, pęka
	blister.add_point(Vector2(0.0, 0.2))
	blister.add_point(Vector2(0.85, 1.0))
	blister.add_point(Vector2(1.0, 0.0))
	for run in runs:
		var kd: int = run["kd"]
		if kd == 2:
			continue
		var x0: float = run["x0"]
		var w: float = run["w"]
		var y_top: float = run["y_top"]
		var sink := LIQUID_SINK_MUD if kd == 0 else LIQUID_SINK
		var y_s := y_top - sink
		var prof := _run_profile(run)
		var ns := prof.size() - 1
		var emitters := clampi(int(w / 1.5), 1, 8)
		for k in emitters:
			var xi := int((float(k) + rng.randf_range(0.25, 0.75)) / float(emitters) * float(ns))
			xi = clampi(xi, 0, ns)
			var d := prof[xi] - sink
			if d < 0.18:
				continue
			var bp := CPUParticles3D.new()
			bp.name = "Bubbles_%d_%d" % [int(run["c"]), k]
			bp.mesh = bmesh
			bp.local_coords = false
			bp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			bp.direction = Vector3.UP
			bp.spread = 6.0
			bp.gravity = Vector3.ZERO
			var bx := x0 + w * float(xi) / float(ns)
			if kd == 1:
				var y_start := y_s - d * 0.85
				var speed := rng.randf_range(0.22, 0.38)
				bp.material_override = bmat_oil
				bp.amount = 7
				bp.lifetime = (y_s - y_start) / speed + 0.25
				bp.emission_box_extents = Vector3(0.12, 0.01, 0.01)
				bp.initial_velocity_min = speed * 0.85
				bp.initial_velocity_max = speed * 1.2
				bp.scale_amount_min = 0.07
				bp.scale_amount_max = 0.20
				bp.scale_amount_curve = bcurve
				bp.position = Vector3(bx, y_start, DEPTH_FRONT + 0.03)
			else:
				bp.material_override = bmat_mud
				bp.amount = 3
				bp.lifetime = 2.4
				bp.emission_box_extents = Vector3(0.35, 0.0, 0.6)
				bp.initial_velocity_min = 0.008
				bp.initial_velocity_max = 0.02
				bp.scale_amount_min = 0.05
				bp.scale_amount_max = 0.12
				bp.scale_amount_curve = blister
				bp.position = Vector3(bx, y_s + 0.02, rng.randf_range(zb + 1.4, zf - 1.0))
			bp.preprocess = bp.lifetime
			bp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(bp)

## Las w głębi: świerki i martwe pnie jako skrzyżowane karty z teksturą (art/world3d/forest, `tools/world_forest_gen.py`) w `MultiMesh`,
## w płaszczyznach z = −3,5 … −60 m nad kolumnami z otwartym niebem. Bliskie rzędy są rzadsze i wyższe (pnie w kadrze), dalekie gęste —
## razem z mgłą głębi i wstęgami mgły dają warstwy sylwetek zamiast pustego nieba.
const FOREST_DIR := "res://art/world3d/forest/"
const FOREST_KINDS := ["spruce_a", "spruce_b", "spruce_c", "snag_a", "snag_b", "pine_a", "pine_b", "birch_a"]
const FOREST_MODELS := ["tree_snag", "tree_snag_hi", "tree_snag_pine", "tree_snag_spruce", "tree_snag_birch", "tree_log", "tree_spruce_a", "tree_spruce_b", "tree_spruce_c", "tree_pine_a", "tree_pine_b", "tree_pine_c", "tree_birch_a", "tree_birch_b"]
## martwe drzewa (`prep_items3d.py: build_snag`) obok pnia z Tripo: wysokość względem drzewa w tym miejscu (złamana brzoza to niski kikut)
const SNAG_H := {"tree_snag": 0.8, "tree_snag_pine": 0.85, "tree_snag_spruce": 0.9, "tree_snag_birch": 0.42}
const FOREST_CHUNK := 96.0                 ## m: las dzielony na odcinki wzdłuż mapy — silnik pomija odcinki poza kadrem (wcześniej jedna siatka na całą mapę).
## Pomiar 2026-10-19 (RTX 3080, 1920×1080): czas GPU bez mierzalnej różnicy między 1 odcinkiem, 96 i 48 m (las to ok. 25 tys. prymitywów, koszt robią
## karty z alfą), a 48 m dokładało ok. 25 wywołań rysowania więcej niż 96 m.

## Profil terenu lasu: wysokość dna lasu za bryłą gruntu, wspólna dla dna (`build_forest_floor`), drzew (`build_forest`) i wstęg mgły przy ziemi
## (`build_ground_fog`). Grunt kolumny to pierwsza od góry warstwa lita, która jest prawdziwym gruntem: pomija cienkie warstwy z pustką pod spodem
## (do FOREST_THIN kafli: dachy, stropy, kładki `C`/`M`, platforma strażnicy) i nawisy z otwartym powietrzem (`.`) pod spodem; szyby i doły
## (grunt głęboko pod powierzchnią albo brak gruntu) wycina mediana z FOREST_MEDIAN kolumn w każdą stronę. Potem filtr Gaussa tym mocniejszy,
## im dalej w głąb (węzły FOREST_KNOTS): tuż za bryłą profil trzyma się jej wierzchu, a daleki las stoi prawie poziomo.
const FOREST_THIN := 2
const FOREST_MEDIAN := 16
const FOREST_KNOTS := [DEPTH_BACK, 3.6, 5.5, 8.0, 12.0, 17.0, 24.0, 34.0, 46.0, 65.0]      ## m w głąb od płaszczyzny gry
static var _ft_cache := {}

## {"mask": PackedByteArray (1 = nad kolumną jest niebo, tu rośnie las i leży mgła), "y": [PackedFloat32Array…] (y gruntu w m na kolumnę, po jednej
## tablicy na węzeł głębi)} albo {} gdy mapa nie ma otwartego gruntu (boss, kryjówka).
static func forest_terrain(rows: Array) -> Dictionary:
	var key := rows.hash()
	if _ft_cache.has(key):
		return _ft_cache[key]
	if _ft_cache.size() > 4:
		_ft_cache.clear()
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var mask := PackedByteArray()
	mask.resize(cols)
	var surf := PackedFloat32Array()                      # wiersz gruntu kolumny albo -1
	surf.resize(cols)
	for c in cols:
		var r := 0
		while r < nrows and not is_solid_ch(_ch(rows, c, r)):
			r += 1
		mask[c] = 1 if r >= 6 else 0                       # lita od góry (brzeg mapy, wnętrze skały): bez lasu
		surf[c] = -1.0
		if r < 6:
			continue
		while r < nrows:
			var e := r
			while e < nrows and is_solid_ch(_ch(rows, c, e)):
				e += 1
			if e >= nrows or (e - r > FOREST_THIN and _ch(rows, c, e) != "."):
				surf[c] = float(r)
				break
			r = e                                          # cienka warstwa albo nawis: szukaj gruntu niżej
			while r < nrows and not is_solid_ch(_ch(rows, c, r)):
				r += 1
	var base := PackedFloat32Array()
	base.resize(cols)
	var known: Array[int] = []
	for c in cols:
		var win := PackedFloat32Array()
		for k in range(maxi(0, c - FOREST_MEDIAN), mini(cols, c + FOREST_MEDIAN + 1)):
			if surf[k] >= 0.0:
				win.append(surf[k])
		if win.is_empty():
			continue
		win.sort()
		base[c] = -win[win.size() >> 1] * T
		known.append(c)
	if known.is_empty():
		_ft_cache[key] = {}
		return {}
	for c in cols:                                         # kolumny bez gruntu w całym oknie: liniowo między sąsiadami, na brzegach najbliższa wartość
		var i := known.bsearch(c)
		if i < known.size() and known[i] == c:
			continue
		if i == 0 or i >= known.size():
			base[c] = base[known[clampi(i, 0, known.size() - 1)]]
		else:
			var a := known[i - 1]
			var b := known[i]
			base[c] = lerpf(base[a], base[b], float(c - a) / float(b - a))
	var ys: Array = []
	for d in FOREST_KNOTS:
		var sig := maxf(0.3, (float(d) - 2.0) * 0.45)      # kolumny: ok. 0,3 tuż za bryłą, 3 w 9 m, 10 w 24 m, 28 w 65 m
		var rad := int(ceil(sig * 3.0))
		var wts := PackedFloat32Array()
		var wsum := 0.0
		for k in range(-rad, rad + 1):
			var w := exp(-0.5 * pow(float(k) / sig, 2.0))
			wts.append(w)
			wsum += w
		var out := PackedFloat32Array()
		out.resize(cols)
		for c in cols:
			var acc := 0.0
			for k in range(-rad, rad + 1):
				acc += wts[k + rad] * base[clampi(c + k, 0, cols - 1)]
			out[c] = acc / wsum
		ys.append(out)
	var ft := {"mask": mask, "y": ys}
	_ft_cache[key] = ft
	return ft

## Drzewostan w punkcie x (m) mapy: {"s": 0..1 (szum wolnozmienny, ok. 40 m na falę), "dens": mnożnik gęstości bliskiego i środkowego pasa
## (0,12 na polanie … 1,7 w gęstwinie), "open": 0..1 (jak bardzo otwarte miejsce)}. Te same polany widać we wszystkich wywołaniach.
static func forest_stand(x: float) -> Dictionary:
	var s := _vn1(x / 38.0, 3.1) * 0.65 + _vn1(x / 13.0, 7.7) * 0.35
	var k := smoothstep(0.2, 0.82, s)
	return {"s": s, "dens": lerpf(0.12, 1.7, k), "open": 1.0 - smoothstep(0.15, 0.45, s)}

## Wiek drzewostanu w punkcie x (m): mnożnik wysokości drzew 0,8 … 1,2 (płaty młodszego i starszego lasu, inny rytm niż polany).
static func forest_age(x: float) -> float:
	return lerpf(0.8, 1.2, _vn1(x / 24.0, 5.3))

## y dna lasu (m) w punkcie x (m) i głębokości `d` (m w głąb, dodatnia): interpolacja między kolumnami i węzłami głębi profilu `forest_terrain`.
static func forest_ground_y(ft: Dictionary, x: float, d: float) -> float:
	var ys: Array = ft["y"]
	var a: PackedFloat32Array = ys[0]
	var u := clampf(x / T - 0.5, 0.0, float(a.size() - 1))
	var c0 := int(u)
	var c1 := mini(c0 + 1, a.size() - 1)
	var fu := u - float(c0)
	var dd := clampf(d, float(FOREST_KNOTS[0]), float(FOREST_KNOTS[FOREST_KNOTS.size() - 1]))
	var k := 0
	while k < FOREST_KNOTS.size() - 2 and dd > float(FOREST_KNOTS[k + 1]):
		k += 1
	var fk := (dd - float(FOREST_KNOTS[k])) / (float(FOREST_KNOTS[k + 1]) - float(FOREST_KNOTS[k]))
	a = ys[k]
	var b: PackedFloat32Array = ys[k + 1]
	return lerpf(lerpf(a[c0], a[c1], fu), lerpf(b[c0], b[c1], fu), fk)

## Dno lasu za bryłą gruntu: siatka terenu od tyłu bryły (z = −DEPTH_BACK) do ostatniego węzła FOREST_KNOTS w głąb, po profilu `forest_terrain`.
## Materiał gruntu (`terrain`, ta sama projekcja triplanarna w świecie co wierzch bryły — tekstura przechodzi bez szwu) ciemnieje w głąb kolorem
## wierzchołków. Przy bryle leży tuż pod jej wierzchem. Wychodzi FOREST_FLOOR_MARGIN poza brzegi mapy:
## w perspektywie daleki pas widać szerzej niż plan gry.
const FOREST_FLOOR_MARGIN := 30.0
static func build_forest_floor(parent: Node3D, rows: Array) -> void:
	var ft := forest_terrain(rows)
	if ft.is_empty() or "--noforestfloor" in OS.get_cmdline_user_args():      # dev: bez dna lasu (porównanie)
		return
	var cols := (ft["y"][0] as PackedFloat32Array).size()
	var depths := PackedFloat32Array()                    # węzły profilu i punkty w pół drogi między nimi
	for i in FOREST_KNOTS.size():
		depths.append(float(FOREST_KNOTS[i]))
		if i + 1 < FOREST_KNOTS.size():
			depths.append((float(FOREST_KNOTS[i]) + float(FOREST_KNOTS[i + 1])) * 0.5)
	var nz := depths.size()
	var nx := int(ceil((float(cols) * T + 2.0 * FOREST_FLOOR_MARGIN) / T)) + 1
	var x0 := -FOREST_FLOOR_MARGIN
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in nz:
		for i in nx:
			hs[j * nx + i] = forest_ground_y(ft, x0 + float(i) * T, depths[j]) - (0.03 if j == 0 else 0.0)
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols_c := PackedColorArray()
	var idx := PackedInt32Array()
	for j in nz:
		var jm := maxi(j - 1, 0)
		var jp := mini(j + 1, nz - 1)
		var shade := lerpf(1.0, 0.3, smoothstep(DEPTH_BACK, 40.0, depths[j]))
		for i in nx:
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, nx - 1)
			var dydx := (hs[j * nx + ip] - hs[j * nx + im]) / (float(ip - im) * T)
			var dydz := (hs[jp * nx + i] - hs[jm * nx + i]) / (depths[jm] - depths[jp])       # z = −głębokość
			verts.append(Vector3(x0 + float(i) * T, hs[j * nx + i], -depths[j]))
			nrms.append(Vector3(-dydx, 1.0, -dydz).normalized())
			cols_c.append(Color(shade, shade, shade))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i                                # a, b: bliższy brzeg; c, d: dalszy (zgodnie z ruchem wskazówek zegara patrząc z góry)
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx.append_array(PackedInt32Array([a, c, b, c, d, b]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrms
	arr[Mesh.ARRAY_COLOR] = cols_c
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic").duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	# bez mgły głębi: w noc pogodną dno ma być czarne jak dawniej niebo między pniami (mgła barwiłaby pas za postaciami, GDD §8.3);
	# w pogodzie „mgła” `view3d._sync_weather` włącza ją z powrotem, żeby dno tonęło w mgle razem z drzewami
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.name = "ForestFloor"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
static func build_forest(parent: Node3D, rows: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1ACE
	var xf := {}
	for k in FOREST_KINDS:
		xf[k] = []
	# modele 3D w bliskim i środkowym pasie: sosny i brzozy (`prep_items3d.py: build_pine / build_birch`), świerki (pień z Tripo + gałęzie
	# z igliwiem, `build_spruce`), martwe pnie i powalone kłody; daleki pas zostaje płaskimi kartami (ginie we mgle). Bór: sosna przeważa,
	# świerk jest drugim piętrem, brzoza rośnie pojedynczo. Każde drzewo ma lekko inny odcień (kolor egzemplarza `MultiMesh`).
	var trees := {}                                       # model → [[Transform3D, Color], …]
	for tk in FOREST_MODELS:
		trees[tk] = []
	var have_models := not model_mesh("tree_snag").is_empty()
	var have_spruce := not model_mesh("tree_spruce_a").is_empty() and not model_mesh("tree_spruce_b").is_empty() and not model_mesh("tree_spruce_c").is_empty()
	var have_pine := not model_mesh("tree_pine_a").is_empty() and not model_mesh("tree_pine_b").is_empty() and not model_mesh("tree_pine_c").is_empty()
	var have_birch := not model_mesh("tree_birch_a").is_empty() and not model_mesh("tree_birch_b").is_empty()
	var ft := forest_terrain(rows)
	if ft.is_empty():
		return
	var first := parent.get_child_count()
	_wind_cards.clear()
	var mask: PackedByteArray = ft["mask"]
	for c in range(0, cols, 2):
		if mask[c] == 0:
			continue
		var r0 := 0
		while r0 < nrows and not is_solid_ch(_ch(rows, c, r0)):
			r0 += 1
		# trzy pasy głębi: bliski (pojedyncze wysokie drzewa), środkowy, daleki (gęsta ściana lasu); stoją na dnie lasu (`forest_ground_y`)
		if rng.randf() < 0.07 and r0 < nrows and _ch(rows, c, r0) == "#" and not model_mesh("tree_log").is_empty():       # powalony pień na ściółce, w głębi bryły gruntu
			var ll := rng.randf_range(2.2, 3.6)
			var lb := Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)).scaled(Vector3(ll / 100.0, ll / 100.0, ll / 100.0))
			(trees["tree_log"] as Array).append([Transform3D(lb, Vector3((float(c) + rng.randf()) * T, -float(r0) * T - 0.06, rng.randf_range(-DEPTH_BACK + 0.5, -1.2))), Color.WHITE])
		var bands := [[DEPTH_BACK + 1.2, 9.0, 0.28, 13.0, 21.0], [9.0, 24.0, 1.4, 11.0, 19.0], [24.0, 60.0, 2.6, 12.0, 24.0]]
		# drzewostan zmienia się wzdłuż mapy (`forest_stand`): polany i rzadkie miejsca z martwymi pniami, gęste kępy, starsze i młodsze płaty —
		# linia czubków dostaje rytm zamiast równego grzebienia; daleki pas zostaje ścianą lasu, tylko trochę rzednie
		var stand := forest_stand(float(c + 1) * T)
		var dens: float = stand["dens"]
		for bi in bands.size():
			var band: Array = bands[bi]
			var per := float(band[2]) * (dens if bi < 2 else lerpf(0.6, 1.3, float(stand["s"])))
			var n := int(per) + (1 if rng.randf() < fmod(per, 1.0) else 0)
			for i in n:
				var z := -rng.randf_range(float(band[0]), float(band[1]))
				var x := (float(c) + rng.randf() * 2.0) * T + rng.randf_range(-1.5, 1.5)
				var h := rng.randf_range(float(band[3]), float(band[4])) * forest_age(x)
				if bi > 0 and rng.randf() < 0.045:                       # pojedyncze stare drzewa wystają ponad las
					h *= rng.randf_range(1.25, 1.45)
				x = out_of_stream(x, -z, 1.4)                          # koryto strumienia (`build_streams`): drzewo staje na brzegu, nie w nurcie
				var y := forest_ground_y(ft, x, -z)
				var roll := rng.randf()
				var snag_p := 0.12 + 0.22 * float(stand["open"])               # na polanach i w rzadkim lesie więcej martwych pni
				var kind := "snag_a" if roll < snag_p * 0.5 else "snag_b"
				if roll >= snag_p:
					var q := (roll - snag_p) / (1.0 - snag_p)
					kind = "birch" if q < 0.14 else ("pine" if q < 0.6 else "spruce")
				if kind == "pine":
					h *= 1.12                                          # sosny wyższe, z koroną w górnej części
				elif kind == "birch":
					h *= 0.8
				var v := rng.randf_range(0.82, 1.12)
				var tint := Color(v * rng.randf_range(0.94, 1.06), v, v * rng.randf_range(0.92, 1.05))
				var w := h * 0.5 * rng.randf_range(0.85, 1.15)
				var model := ""
				if bi < 2:
					if kind == "spruce" and have_spruce:
						model = "tree_spruce_" + "abc"[rng.randi() % 3]
					elif kind == "pine" and have_pine:
						model = "tree_pine_" + "abc"[rng.randi() % 3]
					elif kind == "birch" and have_birch:
						model = "tree_birch_" + "ab"[rng.randi() % 2]
				if model != "":
					var sw := h / 100.0 * rng.randf_range(0.9, 1.15)
					var sb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sw, h / 100.0, sw))
					(trees[model] as Array).append([Transform3D(sb, Vector3(x, y - 0.3, z)), tint])
					continue
				if have_models and bi < 2 and kind.begins_with("snag"):
					# odmiany martwych drzew: pień z Tripo co trzeci raz, reszta proceduralna — sąsiednie pnie nie są już kopiami tego samego modelu
					var tk := "tree_snag"
					var sr := rng.randf()
					if sr < 0.62:
						var alt: String = ["tree_snag_pine", "tree_snag_spruce", "tree_snag_birch"][int(sr / 0.62 * 3.0) % 3]
						if not model_mesh(alt).is_empty():
							tk = alt
					var th := h * float(SNAG_H[tk])
					var tw := th / 100.0 * rng.randf_range(0.9, 1.2)
					var tb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(tw, th / 100.0, tw))
					if tk == "tree_snag" and bi == 0 and not model_mesh(tk + "_hi").is_empty():       # najbliższy rząd: wersja szczegółowa
						tk += "_hi"
					(trees[tk] as Array).append([Transform3D(tb, Vector3(x, y - 0.3, z)), tint])
					continue
				var card_kind: String = kind
				if kind == "spruce":
					card_kind = "spruce_" + "abc"[rng.randi() % 3]
				elif kind == "pine":
					card_kind = "pine_" + "ab"[rng.randi() % 2]
				elif kind == "birch":
					card_kind = "birch_a"
				var b := Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)).scaled(Vector3(w, h, w))
				(xf[card_kind] as Array).append([Transform3D(b, Vector3(x, y - 0.3, z)), tint])
	for tk in trees:
		var mdl := model_mesh(tk)
		if not mdl.is_empty():
			_forest_chunks(parent, mdl[0], null, trees[tk], tk == "tree_log", mdl[1])
	# siatka: dwie skrzyżowane karty 1×1 m (podstawa w y = 0), normalne w górę i ku kamerze — karta nie gaśnie przy bocznym świetle
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for a in [0.0, PI * 0.5]:
		var dx := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var base := v.size()
		v.append_array(PackedVector3Array([-dx, dx, dx + Vector3.UP, -dx + Vector3.UP]))
		uv.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
		for q in 4:
			nrm.append(Vector3(0.0, 0.55, 0.83))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var card := ArrayMesh.new()
	card.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	for k in FOREST_KINDS:
		if (xf[k] as Array).is_empty() or not ResourceLoader.exists(FOREST_DIR + k + ".png"):
			continue
		var m := _wind_mat(load(FOREST_DIR + k + ".png"), Color.WHITE, 1.0, 0.0, 0.5)       # karta kołysze się w całości
		_wind_cards.append(m)
		_forest_chunks(parent, card, m, xf[k], false)
	for i in range(first, parent.get_child_count()):          # las na własnej warstwie: oświetla go `MoonRim`, plan gry nie
		var vi := parent.get_child(i) as VisualInstance3D
		if vi != null:
			vi.layers = 1 | LAYER_FOREST

## Egzemplarze lasu (`list`: [[Transform3D, Color], …]) w odcinkach FOREST_CHUNK wzdłuż osi x — każdy odcinek to osobna `MultiMesh` z własnym
## AABB, więc silnik rysuje tylko odcinki w kadrze. Kolor egzemplarza mnoży albedo (lekko różne odcienie drzew). `local`: przekształcenie siatki w scenie modelu.
static func _forest_chunks(parent: Node3D, mesh: Mesh, mat: Material, list: Array, shadows: bool, local := Transform3D.IDENTITY) -> void:
	var groups := {}
	for e in list:
		var key := int(floor((e[0] as Transform3D).origin.x / FOREST_CHUNK))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(e)
	for key in groups:
		var g: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = g.size()
		for i in g.size():
			mm.set_instance_transform(i, (g[i][0] as Transform3D) * local)
			mm.set_instance_color(i, g[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if mat != null:
			mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## Wiatr w koronach: igliwie modeli drzew (`model_mesh`, powierzchnie z alfą) i karty dalekiego lasu. Wychylenie rośnie z wysokością nad podstawą
## drzewa, a w modelach także z odległością od pnia — nasada gałęzi stoi przy nieruchomym pniu, kołyszą się końce (nic się nie odrywa); karty
## kołyszą się w całości. Każde drzewo ma własną fazę, podmuchy idą falą wzdłuż mapy. Siłę i przechył (burza) ustawia `set_wind` z pogody.
const WIND_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, alpha_to_coverage, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float unit_h = 100.0;           // wysokość drzewa w jednostkach siatki (modele: 100, karty: 1)
uniform float radial = 1.0;             // 1: modele (wychylenie rośnie od pnia), 0: karty (cała karta)
uniform float scissor = 0.4;
uniform float amp = 0.5;
uniform float lean = 0.0;
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float th = max(length(MODEL_MATRIX[1].xyz) * unit_h, 0.1);
	float hg = clamp((VERTEX.y - base.y) / th, 0.0, 1.0);
	float rr = mix(1.0, clamp(length(VERTEX.xz - base.xz) / th * 5.0, 0.0, 1.0), radial);
	float ph = base.x * 0.37 + base.z * 0.21;
	float gust = 0.5 + 0.5 * sin(TIME * 0.45 - base.x * 0.031);
	float w = (sin(TIME * 1.1 + ph) * 0.7 + sin(TIME * 2.3 + ph * 1.7) * 0.3) * (0.35 + 0.65 * gust);
	float fl = sin(TIME * 4.7 + VERTEX.x * 2.1 + VERTEX.z * 1.7 + VERTEX.y * 0.9) * 0.35 * radial;
	float d = (w + fl - lean) * amp * hg * hg * rr * th * 0.02;
	VERTEX.x += d;
	VERTEX.z += d * 0.3;
	VERTEX.y -= abs(d) * 0.15 * rr;
}
void fragment() {
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb * COLOR.rgb;                            // odcień egzemplarza (`_forest_chunks`)
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ALPHA_ANTIALIASING_EDGE = 0.3;                         // wygładzony brzeg (alpha-to-coverage przy MSAA)
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(tex, 0));
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.55, 0.62, 0.5);                     // igliwie prześwituje światłem zza drzew (`MoonRim`)
}
"""
static var _wind_sh: Shader
static var _wind_models: Array = []                ## materiały igliwia modeli (żyją w pamięci podręcznej `model_mesh`)
static var _wind_cards: Array = []                 ## materiały kart dalekiego lasu (odtwarzane z każdym `build_forest`)
static var _wind_grass: Array = []                 ## materiały runa (odtwarzane z każdym `build_undergrowth`)
static var _wind := Vector2(0.5, 0.0)              ## ostatnie (amp, lean) — nowe materiały startują z tym samym wiatrem

static func _wind_mat(tex: Texture2D, tint: Color, unit_h: float, radial: float, scissor: float) -> ShaderMaterial:
	if _wind_sh == null:
		_wind_sh = Shader.new()
		_wind_sh.code = WIND_SHADER
	var m := ShaderMaterial.new()
	m.shader = _wind_sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("unit_h", unit_h)
	m.set_shader_parameter("radial", radial)
	m.set_shader_parameter("scissor", scissor)
	m.set_shader_parameter("amp", _wind.x)
	m.set_shader_parameter("lean", _wind.y)
	return m

## Siła wiatru w koronach (`amp`: 0 cisza, ok. 0,5 lekki wiatr, 2 burza) i stały przechył w lewo (`lean`, burza) — woła `view3d._sync_weather`.
static func set_wind(amp: float, lean: float) -> void:
	if is_equal_approx(amp, _wind.x) and is_equal_approx(lean, _wind.y):
		return
	_wind = Vector2(amp, lean)
	for m in _wind_models + _wind_cards + _wind_grass:
		(m as ShaderMaterial).set_shader_parameter("amp", amp)
		(m as ShaderMaterial).set_shader_parameter("lean", lean)

## Wycinanie alfą z wygładzonym brzegiem (alpha-to-coverage przy MSAA widoków 3D): brzegi kart igliwia, pni i trawy nie migoczą
## przy przesuwanej kamerze. `backlight`: igliwie prześwituje światłem zza drzew (`MoonRim`).
static func _soft_cutout(m: BaseMaterial3D, backlight := false) -> void:
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.alpha_antialiasing_edge = 0.3
	if backlight:
		m.backlight_enabled = true
		m.backlight = Color(0.55, 0.62, 0.5)

## Runo: kępy trawy i paprocie na odsłoniętym wierzchu gruntu (`#`) — karty z teksturą (art/world3d/forest) kołysane wiatrem w shaderze.
## Gęste i wysokie w głębi bryły, niskie i rzadkie w pasie, po którym chodzą postacie (ścieżka zostaje czytelna).
const UNDERGROWTH_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled, alpha_to_coverage;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float amp = 0.5;
uniform float lean = 0.0;
void vertex() {
	float k = 1.0 - UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.1 + w.x * 0.8 + w.z * 1.9) * 0.6 + sin(TIME * 2.7 + w.x * 2.3) * 0.4;
	VERTEX.x += (sway - lean) * 0.14 * amp * k * k;
	NORMAL = normalize(vec3(0.0, 1.0, 0.45));
	COLOR = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * mix(0.6, 1.5, 1.0 - UV.y) * (0.8 + 0.5 * COLOR.r);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = 0.3;                         // wygładzony brzeg źdźbeł (alpha-to-coverage przy MSAA)
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(tex, 0));
	ROUGHNESS = 1.0;
}
"""
static func build_undergrowth(parent: Node3D, rows: Array) -> void:
	_wind_grass.clear()
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6A55
	var xf := {"grass_a": [], "grass_b": [], "fern_a": []}
	for r in nrows:
		for c in cols:
			if _ch(rows, c, r) != "#" or is_solid_ch(_ch(rows, c, r - 1)) or is_platform_ch(_ch(rows, c, r - 1)):
				continue
			var roofed := false                                        # wnętrza (ściana tła albo strop nad kaflem) zostają bez runa
			for rr in range(r - 1, -1, -1):
				var up := _ch(rows, c, rr)
				if up == "b" or is_solid_ch(up):
					roofed = true
					break
			if roofed:
				continue
			var top := cell_pos(c, r) + Vector3(0.0, T * 0.5, 0.0)
			for i in 9:
				var z := rng.randf_range(-DEPTH_BACK + 0.15, DEPTH_FRONT - 0.08)
				var lane := absf(z) < 0.45                                   # pas chodu
				if lane and rng.randf() < 0.55:
					continue
				var deep := clampf(-z / DEPTH_BACK, 0.0, 1.0)
				var fern := not lane and z < -0.7 and rng.randf() < 0.16
				var h := rng.randf_range(0.55, 0.95) if fern else (rng.randf_range(0.14, 0.26) if lane else rng.randf_range(0.26, 0.5) + 0.35 * deep)
				var wd := h * (1.5 if fern else rng.randf_range(0.9, 1.3))
				var b := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)).scaled(Vector3(wd, h, wd))
				var kind := "fern_a" if fern else ("grass_a" if rng.randf() < 0.6 else "grass_b")
				var at := top + Vector3(rng.randf_range(-0.5, 0.5) * T, -h * (0.42 if fern else 0.04), z)
				(xf[kind] as Array).append(Transform3D(b, at))
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for a in [0.0, PI * 0.5]:
		var dx := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var base := v.size()
		v.append_array(PackedVector3Array([-dx, dx, dx + Vector3.UP, -dx + Vector3.UP]))
		uv.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var card := ArrayMesh.new()
	card.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = UNDERGROWTH_SHADER
	for k in xf:
		var list: Array = xf[k]
		if list.is_empty() or not ResourceLoader.exists(FOREST_DIR + k + ".png"):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", load(FOREST_DIR + k + ".png"))
		mat.set_shader_parameter("amp", _wind.x)
		mat.set_shader_parameter("lean", _wind.y)
		_wind_grass.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = card
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 1.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Undergrowth_" + k
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## Krawędź przekroju gruntu: przód bryły był idealnie prostą linią przez cały ekran (makieta w przekroju). Na odsłoniętym wierzchu gruntu pod
## gołym niebem (te same kafle co runo): trawa przewieszona przez krawędź ku kamerze, korzenie zwisające po przekroju i rzadkie, niskie kępy tuż
## przed bryłą. Kępy przed bryłą mają najwyżej ok. 0,35 m — z wysokości kamery zasłaniają tylko stopy postaci (rozgrywka bez zmian).
## Ten sam shader co runo (`UNDERGROWTH_SHADER`: trawa kołysze się z wiatrem, `set_wind`); korzenie wiszą odwrócone i stoją nieruchomo.
static func build_front_edge(parent: Node3D, rows: Array) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xED6E
	var xf := {"grass_a": [], "grass_b": [], "roots_a": [], "roots_b": []}
	for r in nrows:
		for c in cols:
			if _ch(rows, c, r) != "#" or is_solid_ch(_ch(rows, c, r - 1)) or is_platform_ch(_ch(rows, c, r - 1)):
				continue
			var roofed := false
			for rr in range(r - 1, -1, -1):
				var up := _ch(rows, c, rr)
				if up == "b" or is_solid_ch(up):
					roofed = true
					break
			if roofed:
				continue
			var top := cell_pos(c, r) + Vector3(0.0, T * 0.5, 0.0)
			for i in 5:                                            # trawa na krawędzi: część pochylona ku kamerze, część zwisa przed przekrojem
				var hang := i < 3
				var h := rng.randf_range(0.25, 0.55) if hang else rng.randf_range(0.18, 0.35)
				var w := h * rng.randf_range(1.0, 1.4)
				var b := Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, rng.randf_range(1.9, 2.6) if hang else rng.randf_range(0.5, 1.0))
				var at := Vector3(top.x + rng.randf_range(-0.5, 0.5) * T, top.y - (0.06 if hang else 0.03), DEPTH_FRONT + (0.03 if hang else rng.randf_range(-0.12, 0.02)))
				(xf["grass_a" if rng.randf() < 0.6 else "grass_b"] as Array).append(Transform3D(b * Basis.from_scale(Vector3(w, h, w)), at))
			if rng.randf() < 0.35:                                 # niska kępa tuż przed bryłą
				var h2 := rng.randf_range(0.12, 0.32)
				var b2 := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)).scaled(Vector3(h2 * 1.3, h2, h2 * 1.3))
				(xf["grass_a"] as Array).append(Transform3D(b2, Vector3(top.x + rng.randf_range(-0.5, 0.5) * T, top.y - 0.04, DEPTH_FRONT + rng.randf_range(0.05, 0.5))))
			if rng.randf() < 0.5 and is_solid_ch(_ch(rows, c, r + 1)):      # korzenie na przekroju
				var rh := rng.randf_range(0.8, 2.2)
				var rw := rng.randf_range(1.0, 2.2)
				(xf["roots_a" if rng.randf() < 0.5 else "roots_b"] as Array).append(
					Transform3D(Basis().scaled(Vector3(rw, rh, 1.0)), Vector3(top.x + rng.randf_range(-0.4, 0.4) * T, top.y - rng.randf_range(0.02, 0.15), DEPTH_FRONT + 0.012)))
	# siatki: skrzyżowane karty trawy (podstawa w y = 0) i płaski czworokąt korzeni wiszący w dół od y = 0 (nasada z tekstury u góry)
	var gv := PackedVector3Array()
	var guv := PackedVector2Array()
	var gidx := PackedInt32Array()
	for a in [0.0, PI * 0.5]:
		var dx := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var base := gv.size()
		gv.append_array(PackedVector3Array([-dx, dx, dx + Vector3.UP, -dx + Vector3.UP]))
		guv.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
		gidx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var rv := PackedVector3Array([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, -1.0, 0.0), Vector3(-0.5, -1.0, 0.0)])
	var ruv := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var ridx := PackedInt32Array([0, 2, 1, 0, 3, 2])
	var meshes := {}
	for kind in [["grass", gv, guv, gidx], ["roots", rv, ruv, ridx]]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = kind[1]
		arr[Mesh.ARRAY_TEX_UV] = kind[2]
		arr[Mesh.ARRAY_INDEX] = kind[3]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		meshes[kind[0]] = m
	var sh := Shader.new()
	sh.code = UNDERGROWTH_SHADER
	for k in xf:
		var list: Array = xf[k]
		if list.is_empty() or not ResourceLoader.exists(FOREST_DIR + k + ".png"):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", load(FOREST_DIR + k + ".png"))
		mat.set_shader_parameter("amp", 0.0 if k.begins_with("roots") else _wind.x)          # korzenie w ziemi nie falują
		mat.set_shader_parameter("lean", _wind.y)
		if not k.begins_with("roots"):
			_wind_grass.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes["roots" if k.begins_with("roots") else "grass"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, Color(rng.randf() * 0.6, 0.0, 0.0, 1.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "FrontEdge_" + k
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
uniform vec3 tint : source_color = vec3(0.30, 0.38, 0.52);
uniform float density = 0.6;
uniform float seed = 0.0;
uniform float speed = 0.05;
varying vec3 wp;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vn(p); p = p * 2.03 + vec2(17.1, 9.7); a *= 0.5; }
	return s;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	vec2 q = vec2(wp.x * 0.11 + TIME * speed + seed * 7.0, wp.y * 0.30 + seed * 3.0);
	float n = fbm(q);
	float n2 = fbm(q * vec2(0.45, 1.2) + vec2(-TIME * speed * 0.6, 4.0));
	float cloud = smoothstep(0.28, 0.80, n * 0.6 + n2 * 0.6);
	float fall = smoothstep(1.0, 0.12, h);
	ALBEDO = tint;
	EMISSION = tint * 0.02;                // ledwie własna poświata: wstęgi leżą wzdłuż całego lasu, a tło na wysokości postaci ma zostać czarne (GDD §8.3)
	ALPHA = clamp(cloud * fall * density, 0.0, 0.85) * COLOR.a;
}
void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * (LIGHT_IS_DIRECTIONAL ? 0.12 : 0.65);       // księżyc ledwie muska mgłę, flary i latarki ją barwią
}
"""
## Mgła przy ziemi: kilka warstw wstęg za płaszczyzną gry (z = -3 … -20 m) wszędzie tam, gdzie las (kolumny z otwartym niebem), leżących na dnie
## lasu (`forest_terrain` w głębokości warstwy). Dryfujący szum fbm, gęsta przy gruncie i rzednąca do góry; oświetlana światłami 3D (flara,
## ognisko, latarka podbarwiają mgłę).
static func build_ground_fog(parent: Node3D, rows: Array) -> void:
	var ft := forest_terrain(rows)
	if ft.is_empty():
		return
	var mask: PackedByteArray = ft["mask"]
	var cols := mask.size()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	var layers := [[-3.2, 0.55, 3.4], [-6.5, 0.5, 4.2], [-12.0, 0.45, 5.4], [-20.0, 0.4, 6.8]]       # z, gęstość, wysokość
	for li in layers.size():
		var spec: Array = layers[li]
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("seed", float(li) * 1.7)
		mat.set_shader_parameter("density", float(spec[1]))
		mat.set_shader_parameter("speed", 0.035 + 0.012 * float(li))
		var hgt := float(spec[2])
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols_c := PackedColorArray()
		var idx := PackedInt32Array()
		var c := 0
		while c < cols:
			if mask[c] == 0:
				c += 1
				continue
			var c1 := c
			while c1 < cols and mask[c1] == 1:
				c1 += 1
			if c1 - c >= 2:
				var base := verts.size()
				for k in range(c, c1 + 1):
					var edge := 0.0 if (k == c or k == c1) else 1.0
					var x := float(k) * T
					var g := forest_ground_y(ft, x, -float(spec[0]))
					verts.append(Vector3(x, g - 0.4, 0.0))
					verts.append(Vector3(x, g + hgt, 0.0))
					uvs.append(Vector2(x, 0.0))
					uvs.append(Vector2(x, 1.0))
					cols_c.append(Color(1, 1, 1, edge))
					cols_c.append(Color(1, 1, 1, edge))
				for k in range(c1 - c):
					var a := base + k * 2
					idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
			c = c1
		if verts.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols_c
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "GroundFog%d" % li
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.0, float(spec[0]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## Zamglenie koron: nocą trzy pasy lasu zlewały się w jedną czarną ścianę (mgła głębi jest prawie czarna, żeby nie rozjaśniać planu gry).
## Między pasami stoją pionowe zasłony chłodnej, księżycowej poświaty (dodawane do obrazu za nimi, `blend_add`), które rosną z wysokością nad
## dnem lasu (`forest_terrain`): przy gruncie zero — tło za postaciami zostaje czarne (GDD §8.3) — a od kilku metrów w górę coraz więcej, więc każdy
## dalszy rząd koron jest odrobinę jaśniejszy od bliższego i czubki układają się w plany sylwetek. Wygasają powyżej czubków lasu (nie zmieniają nieba
## wyżej). Siłę ustawia `view3d._sync_weather` (parametr `strength`: pogoda; w mgle robotę przejmuje mgła głębi).
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(0.010, 0.014, 0.024);
uniform float strength = 1.0;
uniform float h0 = 4.0;
uniform float h1 = 18.0;
uniform float top = 30.0;
void fragment() {
	float h = UV.y;                          // m nad dnem lasu
	float a = smoothstep(h0, h1, h) * (1.0 - smoothstep(top - 8.0, top, h));
	ALBEDO = tint * a * strength * COLOR.a;
}
"""
const HAZE_TINT := Vector3(0.008, 0.011, 0.019)              ## poświata jednej zasłony przy pełnej wysokości (liniowo, przed tonemappingiem)
const HAZE_LAYERS := [[9.0, 0.7], [16.5, 0.85], [24.0, 1.0], [38.0, 1.1]]       ## [m w głąb, mnożnik] — zasłony na granicach pasów lasu i w środku dalekiego
static func build_canopy_haze(parent: Node3D, rows: Array) -> void:
	var ft := forest_terrain(rows)
	if ft.is_empty():
		return
	var cols := (ft["y"][0] as PackedFloat32Array).size()
	var sh := Shader.new()
	sh.code = HAZE_SHADER
	for li in HAZE_LAYERS.size():
		var depth := float(HAZE_LAYERS[li][0])
		var x0 := -FOREST_FLOOR_MARGIN
		var nx := int(ceil((float(cols) * T + 2.0 * FOREST_FLOOR_MARGIN) / T)) + 1
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols_c := PackedColorArray()
		var idx := PackedInt32Array()
		var top := 34.0
		for i in nx:
			var x := x0 + float(i) * T
			var g := forest_ground_y(ft, x, depth)
			var edge := clampf(minf(float(i), float(nx - 1 - i)) / 6.0, 0.0, 1.0)       # brzegi wygasają (bez ostrej krawędzi poza mapą)
			for hh in [0.0, top]:
				verts.append(Vector3(x, g + hh, -depth))
				uvs.append(Vector2(x, hh))
				cols_c.append(Color(1, 1, 1, edge))
			if i > 0:
				var a := (i - 1) * 2
				idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols_c
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tint", HAZE_TINT * float(HAZE_LAYERS[li][1]))
		mat.set_shader_parameter("top", top)
		var mi := MeshInstance3D.new()
		mi.name = "CanopyHaze%d" % li
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## Niebo nocy: czarne przy horyzoncie (na wysokości graczy tło zostaje ciemne — wróg nie rysuje się sylwetką na poświacie), wyżej pokład chmur
## podświetlony księżycem — czubki świerków odcinają się od niego postrzępioną linią. Szum gradientowy z obrotem między oktawami (bez kanciastych
## łat dawnego szumu wartości) i zawiniętą dziedziną (strzępy chmur); tarcza księżyca z poświatą w `MOON_DIR` (za lasem, skąd świeci też `MoonRim`
## na korony), gwiazdy w prześwitach. Pogodę ustawia `view3d._sync_weather`: `cover` (zachmurzenie), `drift` (przesunięcie chmur wg wiatru),
## `stars`, `moon_vis` (tarcza za chmurami deszczu / mgłą), `flash` (błysk burzy rozświetla chmury od środka).
const MOON_DIR := Vector3(0.34, 0.215, -0.915)          ## kierunek do księżyca: za lasem, po prawej, ok. 12° nad horyzontem (w kadrze nad dalekim lasem)
const SKY_SHADER := """
shader_type sky;
uniform vec3 glow : source_color = vec3(0.016, 0.024, 0.044);
uniform vec3 base : source_color = vec3(0.003, 0.004, 0.008);
uniform float lit = 0.0;
uniform vec3 moon_dir = vec3(0.34, 0.215, -0.915);
uniform float cover = 0.6;
uniform vec2 drift = vec2(0.0);
uniform float stars = 0.3;
uniform float moon_vis = 0.85;
uniform float flash = 0.0;
vec2 g2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}
float gn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(dot(g2(i), f), dot(g2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(g2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(g2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	mat2 r = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * gn(p); p = r * p * 2.03 + vec2(11.3, 5.9); a *= 0.5; }
	return s;
}
float h31(vec3 p) { p = fract(p * vec3(0.1031, 0.1030, 0.0973)); p += dot(p, p.yzx + 33.33); return fract((p.x + p.y) * p.z); }
void sky() {
	vec3 d = EYEDIR;
	float e = d.y;
	float band = smoothstep(0.04, 0.24, e) * (1.0 - 0.6 * smoothstep(0.5, 0.95, e));
	// chmury: płaszczyzna nad lasem (perspektywa zagęszcza je ku horyzontowi), dziedzina zawinięta drugim szumem
	vec2 q = d.xz / (max(e, 0.0) + 0.18) * 0.9 + drift;
	vec2 w = vec2(fbm(q * 0.7 + vec2(3.1, 7.7)), fbm(q * 0.7 + vec2(8.3, 1.9)));
	float n = fbm(q * 1.6 + w * 1.1) * 0.95 + 0.5;
	float cloud = smoothstep(1.02 - cover, 1.32 - cover, n);
	float thick = smoothstep(1.2 - cover, 1.7 - cover, n);                  // gęste rdzenie: ciemniejsze niż brzegi
	// księżyc: tarcza z ciemniejszymi morzami i poświata wokół
	vec3 m = normalize(moon_dir);
	float ang = acos(clamp(dot(d, m), -1.0, 1.0));
	float halo = exp(-ang * 10.0) * 0.5 + exp(-ang * 45.0) * 0.6 * moon_vis;
	float disc = smoothstep(0.0118, 0.0100, ang);
	vec3 mx = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
	vec2 mp = vec2(dot(d - m, mx), dot(d - m, cross(mx, m))) / 0.011;
	float maria = gn(mp * 2.3 + 4.0) * 0.6 + gn(mp * 5.1) * 0.25;
	vec3 moon_col = vec3(0.92, 0.94, 1.0) * (0.95 - 0.40 * smoothstep(0.0, 0.35, maria));
	// prześwity: czarne u dołu, granat wyżej i przy księżycu; gwiazdy (stałe na ekranie — kamera się nie obraca) migoczą
	vec3 clear_sky = base + glow * band * (0.25 + 1.6 * halo);
	vec3 sc = d * 520.0;
	vec3 cell = floor(sc);
	float hs = h31(cell);
	vec3 sp = cell + vec3(h31(cell + 7.1), h31(cell + 3.3), h31(cell + 5.9));
	float star = step(0.9965, hs) * smoothstep(0.55, 0.0, length(sc - sp)) * (0.55 + 0.45 * sin(TIME * (1.5 + 3.0 * hs) + hs * 60.0));
	clear_sky += vec3(0.75, 0.8, 1.0) * star * stars * smoothstep(0.06, 0.2, e) * (1.0 - smoothstep(0.0, 0.25, halo));
	// chmury: jaśniejsze przy tarczy i na brzegach (srebrne obwódki), gęste rdzenie ciemniejsze; błysk burzy rozświetla je od środka
	float rim = cloud * (1.0 - thick);
	vec3 cloud_col = glow * band * (0.55 + 0.6 * (1.0 - thick) + 3.2 * halo * (0.4 + rim));
	float bolt = flash * (0.5 + 0.8 * smoothstep(0.4, 0.9, fbm(q * 0.5 + vec2(17.0, 3.0)) + 0.5));
	cloud_col += vec3(0.55, 0.62, 0.85) * bolt * band * (0.4 + thick);
	vec3 c = mix(clear_sky, cloud_col, cloud);
	c += moon_col * disc * moon_vis * moon_vis * (1.0 - 0.85 * thick) * (1.0 - 0.5 * cloud);      // za mgłą i deszczem zostaje sama rozmyta poświata
	COLOR = mix(c, vec3(0.16, 0.19, 0.24), lit);
}
"""
## Mgła wolumetryczna (Forward+): jedna bryła na całą mapę od 1,5 m przed płaszczyzną gry do 11 m w głąb. Światła sceny rozpraszają się w niej —
## snop latarki, poświata flary i lampy, smugi księżyca między drzewami.
static func build_fog_volumes(parent: Node3D, rows: Array, density := 0.035) -> void:
	var nrows := rows.size()
	var cols: int = (rows[0] as String).length() if nrows > 0 else 0
	if cols == 0:
		return
	var fv := FogVolume.new()
	fv.name = "FogVolume"
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.size = Vector3(float(cols) * T + 40.0, float(nrows) * T + 30.0, 12.5)
	fv.position = Vector3(float(cols) * T * 0.5, -float(nrows) * T * 0.5, -4.75)
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = Color(0.80, 0.86, 1.0)
	fm.edge_fade = 0.3
	fv.material = fm
	parent.add_child(fv)

## Środowisko nocy (niebo, mgła głębi, glow, filmic) i księżyc z cieniami. `ambient` — kolor ciemności poziomu (jak w 2D) służy do ocieplenia
## światła otoczenia (kryjówka); `moon` = false dla wnętrz.
static func build_environment(parent: Node3D, ambient := Color(0.0245, 0.0266, 0.0406), moon := true, quality := 2) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sm.shader = ssh
	sky.sky_material = sm
	sm.set_shader_parameter("moon_dir", MOON_DIR.normalized())
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var warm := clampf((ambient.r - ambient.b) * 6.0, 0.0, 1.0)          # kryjówka: bursztynowe otoczenie
	# noc ma być czarna jak w 2D (GDD §8.3: ciemność jest mechaniką) — otoczenie tylko odcina bryły od nieba, widoczność dają światła (aura, latarka, flara, ognisko)
	env.ambient_light_color = Color(0.15, 0.18, 0.25).lerp(Color(0.42, 0.30, 0.20), warm)
	env.ambient_light_energy = 0.03 + 0.37 * warm            # prawie zero poza kryjówką: bez własnego światła nie widać terenu
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	# mgła głębi liczona od płaszczyzny gry w głąb (view3d.gd ustawia początek tuż za graczami): plan gry zostaje czysty i czarny,
	# a kolejne rzędy lasu toną w chłodnej poświacie — bliskie pnie rysują się na niej czarną sylwetką
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.020, 0.030, 0.050)
	env.fog_density = 1.0
	env.fog_depth_curve = 0.7
	env.fog_depth_begin = 20.0
	env.fog_depth_end = 80.0
	# Forward+ (w Compatibility te pola są ignorowane): zaciemnienie styków brył, odbite światło z ekranu i mgła wolumetryczna.
	# Mgła globalna ma gęstość 0 — zamglenie dają bryły `FogVolume` z `build_fog_volumes` (tylko przy płaszczyźnie gry i za nią),
	# inaczej 40 m powietrza między kamerą a graczami przygaszałoby cały kadr.
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.35
	env.ssil_enabled = quality >= 2
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2
	env.volumetric_fog_enabled = quality >= 1
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.82, 0.88, 1.0)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_detail_spread = 0.5
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.0
	if "--view3dlit" in OS.get_cmdline_user_args():                # dev: pełne, białe światło otoczenia — podgląd geometrii i materiałów bez nocy
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.55
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
		sm.set_shader_parameter("lit", 1.0)
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	parent.add_child(we)
	if moon:
		var l := DirectionalLight3D.new()
		l.name = "Moon"
		l.basis = Basis.looking_at(Vector3(0.55, -0.7, -0.45), Vector3.UP)
		l.light_color = Color(0.62, 0.72, 0.95)
		l.light_energy = 0.06                                  # księżyc tylko muska krawędzie — nie oświetla drogi
		l.shadow_enabled = true
		l.directional_shadow_max_distance = 60.0
		l.shadow_bias = 0.04
		l.light_volumetric_fog_energy = 0.3                    # smugi księżyca między pniami
		l.layers = 3                                           # widoczne dla kamery świata i kamery graczy (Forward+ odcina światła maską warstw kamery)
		parent.add_child(l)
		# poświata księżyca na lesie: ten sam kierunek co tarcza na niebie (`MOON_DIR`), zza drzew ku kamerze — prześwituje przez igliwie
		# (`backlight` kart, `model_mesh`) i obrysowuje korony na tle nieba. Maska świateł: tylko warstwa lasu (LAYER_FOREST), więc plan gry
		# i postacie zostają w ciemności (GDD §8.3); bez cieni i bez mgły wolumetrycznej (ta nie zna masek warstw)
		var rim := DirectionalLight3D.new()
		rim.name = "MoonRim"
		rim.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
		rim.light_color = Color(0.62, 0.72, 0.95)
		rim.light_energy = MOON_RIM
		rim.light_cull_mask = LAYER_FOREST
		rim.light_volumetric_fog_energy = 0.0
		rim.layers = 3
		parent.add_child(rim)
	return env
