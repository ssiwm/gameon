extends Node2D
## Poziom misji „Gniazdo" na TileMapLayer (GDD §16.0 pkt 1, 1.3.5).
##
## Mapa jest siatką ASCII (MAP), żeby dało się ją czytać i edytować bez
## edytora. TileSet i tekstury kafli budujemy w kodzie — każdy peer składa
## identyczny poziom, a znaczniki w siatce rozstawiają postacie pod stałymi
## nazwami (Trzosek1…, Nest1…), więc ścieżki RPC zgadzają się na wszystkich.
##
## Dlaczego wielopoziomowa: na jednej płaszczyźnie drużyna stała w kolejce
## i strzelała sobie w plecy. Platformy jednokierunkowe (wskakujesz od spodu,
## zeskakujesz dół+skok) i ciągłe kładki rozkładają drużynę w pionie.
##
## Legenda:
##   #  ziemia (bryła)        C  beton (bryła)        M  blacha/skrzynia (bryła)
##   ~  woda (podłoga-bryła)  =  kładka metalowa (jednokierunkowa)
##   -  rusztowanie drewniane (jednokierunkowe)
##   b  tło: beton (wnętrze)  w  tło: drewno (pnie, belki)
##   S  start  E  wyjście  T  Trzosek  W  Wołek  N  gniazdo  X  dom Stalkera

const TILE := 16
## Warstwy fizyki: bryły na 1 (jak dawny World), kładki na 16 — pociski
## (maska 7) i promienie okluzji/linii strzału (maska 1) przez nie przechodzą.
const LAYER_SOLID := 1
const LAYER_PLATFORM := 16

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const NEST_SCENE := preload("res://scenes/nest.tscn")
const STALKER_SCENE := preload("res://scenes/stalker.tscn")

const MAP := [
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##............................................................................................................................##",
	"##........................................................................................................................N...##",
	"##.............................................................................................w.........w.........w---------.##",
	"##.............................................................................................w.........w........Tw..........##",
	"##.............................................................................................w.........w......---------.....##",
	"##.......w...w.................................................................................w.........w..T......w..........##",
	"##.......w...w.................................................................................w........-------....w..........##",
	"##.......w...w................................................N................................w.........w.........w..........##",
	"##.......w...w............................................=========............................w-------..w.........w..........##",
	"##.......w...w....CCCCCCCCCCCCCCCCCCC.............................T............................w.........w.........w..........##",
	"##.......w...w.---bbbbbbbbbbbbbbbbbbC...........=========.....===========...=========..........w......-------......w..........##",
	"##.......w...w....bbbbbbbbbbbbbbbbbbC..........................................................w.........w.........w..........##",
	"##.......w..---...bbbbbbbbbbbbbbbbbb........=========...===========...===========.............-------....w.........w..........##",
	"##.ES..S.w...w....bbbbbbbbTbTbTbbNbb..................M.....W.........X...M.......T.T..........w.........w....W....w........E.##",
	"########################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"########################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"########################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"########################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
]

## znak -> [kolumna atlasu, powierzchnia kroków, rodzaj]
## rodzaj: 0 bryła, 1 kładka jednokierunkowa, 2 tło bez kolizji
const KINDS := {
	"#": [0, "dirt", 0],
	"C": [1, "concrete", 0],
	"M": [2, "metal", 0],
	"~": [3, "water", 0],
	"=": [4, "metal", 1],
	"-": [5, "dirt", 1],
	"b": [6, "", 2],
	"w": [7, "", 2],
}
const ATLAS_COLS := 8

var bounds := Rect2()
var spawns: Array[Vector2] = []
var exits: Array[Vector2] = []
var stalker_home := Vector2.ZERO

var _solid: TileMapLayer
var _back: TileMapLayer

func _ready() -> void:
	add_to_group("level")
	var ts := _build_tileset()
	_back = TileMapLayer.new()
	_back.name = "Back"
	_back.tile_set = ts
	add_child(_back)
	_solid = TileMapLayer.new()
	_solid.name = "Solid"
	_solid.tile_set = ts
	add_child(_solid)
	_build_map()
	_spawn_entities()

# ---------------------------------------------------------------- mapa

func _ch(c: int, r: int) -> String:
	if r < 0 or r >= MAP.size():
		return "."
	var row: String = MAP[r]
	if c < 0 or c >= row.length():
		return "."
	return row[c]

func _build_map() -> void:
	var rows := MAP.size()
	var cols: int = (MAP[0] as String).length()
	bounds = Rect2(0, 0, cols * TILE, rows * TILE)
	for r in rows:
		for c in cols:
			var ch := _ch(c, r)
			if not KINDS.has(ch):
				# znacznik albo pusto — tło dziedziczymy z lewego sąsiada, żeby
				# postać w posterunku nie zostawiała dziury w ścianie
				var left := _ch(c - 1, r)
				if ch != "." and KINDS.has(left) and KINDS[left][2] == 2:
					_back.set_cell(Vector2i(c, r), 0, Vector2i(KINDS[left][0], 1))
				continue
			var k: Array = KINDS[ch]
			# wariant „wierzch" (rząd 0 atlasu), gdy nad kaflem nie ma bryły
			var top := not _is_solid(c, r - 1)
			var layer := _back if k[2] == 2 else _solid
			# bryły: alternatywa kafla z okluderem cofniętym na odsłoniętych bokach
			var alt := _exposure(c, r) if k[2] == 0 else 0
			layer.set_cell(Vector2i(c, r), 0, Vector2i(k[0], 0 if top else 1), alt)

func _is_solid(c: int, r: int) -> bool:
	# poza mapą = bryła (krawędzie mapy nie świecą)
	if r < 0 or r >= MAP.size() or c < 0 or c >= (MAP[0] as String).length():
		return true
	var ch := _ch(c, r)
	return KINDS.has(ch) and KINDS[ch][2] == 0

## Maska odsłoniętych boków: 1 góra, 2 prawo, 4 dół, 8 lewo.
func _exposure(c: int, r: int) -> int:
	var m := 0
	if not _is_solid(c, r - 1): m |= 1
	if not _is_solid(c + 1, r): m |= 2
	if not _is_solid(c, r + 1): m |= 4
	if not _is_solid(c - 1, r): m |= 8
	return m

## Znaczniki → postacie. Nazwy numerowane od lewej do prawej, identycznie
## na każdym peerze.
func _spawn_entities() -> void:
	var found := {"T": [], "W": [], "N": []}
	for r in MAP.size():
		var row: String = MAP[r]
		for c in row.length():
			var ch := row[c]
			# punkt na podłodze: środek kafla w poziomie, dół kafla w pionie
			var p := Vector2(c * TILE + TILE * 0.5, (r + 1) * TILE)
			match ch:
				"S": spawns.append(p)
				"E": exits.append(p)
				"X": stalker_home = p
				"T", "W", "N": found[ch].append(p)
	for k in found:
		found[k].sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for i in found["T"].size():
		_add_enemy("Trzosek%d" % (i + 1), "trzosek", found["T"][i])
	for i in found["W"].size():
		_add_enemy("Wolek%d" % (i + 1), "wolek", found["W"][i])
	for i in found["N"].size():
		var n := NEST_SCENE.instantiate()
		n.name = "Nest%d" % (i + 1)
		n.position = found["N"][i]
		add_child(n)
	var s := STALKER_SCENE.instantiate()
	s.name = "Stalker"
	s.position = stalker_home
	add_child(s)

func _add_enemy(n: String, kind: String, p: Vector2) -> void:
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = kind
	e.position = p
	add_child(e)

## Punkt startowy dla slotu gracza (1..4); kolejne sloty lekko przesunięte.
func spawn_for(slot: int) -> Vector2:
	if spawns.is_empty():
		return Vector2(64, 400)
	var base: Vector2 = spawns[(slot - 1) % spawns.size()]
	return base + Vector2(((slot - 1) / spawns.size()) * 14.0, 0)

## Czy pod stopami jest kładka jednokierunkowa (zeskok dół+skok).
func is_platform_at(pos: Vector2) -> bool:
	var cell := _solid.local_to_map(_solid.to_local(pos + Vector2(0, 3)))
	var ac := _solid.get_cell_atlas_coords(cell)
	return ac.x == KINDS["="][0] or ac.x == KINDS["-"][0]

## Powierzchnia pod stopami (dźwięk kroków). Pusto = kroki „dirt".
func surface_at(pos: Vector2) -> String:
	var cell := _solid.local_to_map(_solid.to_local(pos + Vector2(0, 3)))
	var td := _solid.get_cell_tile_data(cell)
	if td == null:
		return "dirt"
	var s: String = td.get_custom_data("surface")
	return s if s != "" else "dirt"

# ---------------------------------------------------------------- TileSet

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, LAYER_SOLID)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, LAYER_PLATFORM)
	ts.set_physics_layer_collision_mask(1, 0)
	ts.add_occlusion_layer()
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "surface")
	ts.set_custom_data_layer_type(0, TYPE_STRING)

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(_build_atlas())
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)

	var h := TILE * 0.5
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var plank := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 4), Vector2(-h, -h + 4)])
	for ch in KINDS:
		var k: Array = KINDS[ch]
		for variant in 2:
			var coords := Vector2i(k[0], variant)
			if src.has_tile(coords):
				continue
			src.create_tile(coords)
			var td := src.get_tile_data(coords, 0)
			td.set_custom_data("surface", k[1])
			match k[2]:
				0:
					# Okluder obejmujący cały kafel zacieniał sam kafel — podłoga
					# była czarna nawet w snopie latarki. Alternatywy 0..15 mają
					# okluder cofnięty o OCC_INSET na odsłoniętych bokach: wierzch
					# i lica łapią światło, a wnętrze bryły nadal rzuca cień.
					_solid_tile(td, k[1], 0, full)
					for mask in range(1, 16):
						var alt := src.create_alternative_tile(coords)
						_solid_tile(src.get_tile_data(coords, alt), k[1], mask, full)
				1:
					td.add_collision_polygon(1)
					td.set_collision_polygon_points(1, 0, plank)
					td.set_collision_polygon_one_way(1, 0, true)
	return ts

const OCC_INSET := 4.0

func _solid_tile(td: TileData, surface: String, mask: int, full: PackedVector2Array) -> void:
	var h := TILE * 0.5
	td.set_custom_data("surface", surface)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, full)
	var x0 := -h + (OCC_INSET if mask & 8 else 0.0)
	var x1 := h - (OCC_INSET if mask & 2 else 0.0)
	var y0 := -h + (OCC_INSET if mask & 1 else 0.0)
	var y1 := h - (OCC_INSET if mask & 4 else 0.0)
	var occ := OccluderPolygon2D.new()
	occ.polygon = PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	td.add_occluder_polygon(0)
	td.set_occluder_polygon(0, 0, occ)

## Atlas 8×2 kafli: rząd 0 = wierzch (trawa, krawędź), rząd 1 = wypełnienie.
## Proste piksele z deterministycznym szumem — placeholder do czasu grafiki.
func _build_atlas() -> Image:
	var img := Image.create(TILE * ATLAS_COLS, TILE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7A11
	for col in ATLAS_COLS:
		for row in 2:
			var top := row == 0
			for y in TILE:
				for x in TILE:
					var c := _texel(col, top, x, y, rng)
					if c.a > 0.0:
						img.set_pixel(col * TILE + x, row * TILE + y, c)
	return img

func _texel(col: int, top: bool, x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var n := rng.randf_range(-0.035, 0.035)
	match col:
		0:  # ziemia, z wierzchu trawa
			if top and y < 3:
				return Color(0.17 + n, 0.29 + n, 0.13 + n)
			return Color(0.23 + n, 0.16 + n, 0.11 + n)
		1:  # beton
			if top and y == 0:
				return Color(0.42, 0.43, 0.45)
			var seam := 0.05 if (x == 0 or y == 15) else 0.0
			return Color(0.30 + n - seam, 0.31 + n - seam, 0.33 + n - seam)
		2:  # blacha / skrzynia
			var edge := x == 0 or x == 15 or y == 0 or y == 15
			var rivet := (x == 2 or x == 13) and (y == 2 or y == 13)
			if rivet:
				return Color(0.55, 0.57, 0.6)
			return Color(0.26, 0.30, 0.34) if edge else Color(0.32 + n, 0.36 + n, 0.40 + n)
		3:  # woda (płycizna na podłożu)
			if top and y < 2:
				return Color(0.30, 0.52, 0.62, 1.0)
			return Color(0.09 + n, 0.19 + n, 0.27 + n)
		4:  # kładka metalowa — tylko górne 4 px
			if y >= 4:
				return Color(0, 0, 0, 0)
			if y == 0:
				return Color(0.58, 0.60, 0.63)
			return Color(0.40 + n, 0.42 + n, 0.45 + n)
		5:  # rusztowanie drewniane — deska 4 px + cień
			if y >= 4:
				return Color(0, 0, 0, 0)
			return Color(0.45 + n, 0.31 + n, 0.17 + n) if x % 8 != 0 else Color(0.30, 0.20, 0.11)
		6:  # tło: beton wnętrza
			return Color(0.12 + n * 0.5, 0.12 + n * 0.5, 0.14 + n * 0.5)
		7:  # tło: pień / belka (środkowe 8 px)
			if x < 4 or x > 11:
				return Color(0, 0, 0, 0)
			return Color(0.19 + n, 0.13 + n, 0.08 + n)
	return Color(1, 0, 1)
