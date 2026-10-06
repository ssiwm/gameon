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
##   B  Żyła — matka gniazd (boss misji)
##   k  skrzynia (fizyczna)   o  beczka (fizyczna, wybucha)
##   g  broń na ziemi         a  skrzynka z amunicją
##   m  błoto (bagno: wolno, grząsko)   O  plama oleju (ślizg)   i  lód   s  śnieg  — kafle-podłoża z własną fizyką
##   L  Ślepiec (nie widzi, słyszy)   P  Podsłuchacz (stoi, krzyczy i ściąga hordę)
##   Y  Mimik (udaje kolegę z drużyny)
##   J  Skoczek (wisi pod sufitem i spada)   Z  Ćma (światłolubna, wisi pod sufitem)
##
## Układ (192 × 44 kafli): las + posterunek → arena z kładkami → Skład (hala z antresolą,
## dach, schody z rusztowań) → tartak z bossem; pod całą mapą biegną podziemia
## (sale i niskie tunele) połączone trzema szybami ze schodami z kładek.

const TILE := 16
## Warstwy fizyki: bryły na 1 (jak dawny World), kładki na 16 — pociski
## (maska 7) i promienie okluzji/linii strzału (maska 1) przez nie przechodzą.
const LAYER_SOLID := 1
## Od tej wysokości (px) postać jest w podziemiach: dno szybu i sale pod ziemią (mapa: rzędy ≥ 31).
const UNDERGROUND_Y := 31 * TILE
const LAYER_PLATFORM := 16

const Lights := preload("res://scripts/lights.gd")
const Nav := preload("res://scripts/nav.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ART_TILES := "res://art/tiles.png"     ## 8×4: rzędy 0/2 wierzch, 1/3 wypełnienie
const ART_PROPS := "res://art/props.png"
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const NEST_SCENE := preload("res://scenes/nest.tscn")
const STALKER_SCENE := preload("res://scenes/stalker.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")
const PROP := preload("res://scripts/prop.gd")
const PICKUP := preload("res://scripts/pickup.gd")
const Weapons := preload("res://scripts/weapons.gd")
const FLARE := preload("res://scripts/flare.gd")

const MAP := [
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##........................................................................................................................................................................................N...##",
	"##.............................................................................................................................................................w.........w.........w---------.##",
	"##.............................................................................................................................................................w.........w........Tw..........##",
	"##.............................................................................................................................................................w.........w......---------.....##",
	"##.......w...w...........................................................................................................P..MM..T..M...........................w.........wk.T......w..........##",
	"##.......w...w..................................................................................................CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC................w........-------....w..........##",
	"##.......w...w..................................................................................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC................w...g.....w.........w..........##",
	"##.......w...w............................................=========.........................................----CbbbbbbbbbbbbbbbbbJbbbbbbbbbbbC----............w-------..w.........w..........##",
	"##.......w...w....CCCCCCCCCCCCCCCCCCC.............................T...k.........................................CbbbbbbbbbbgbbbbbbbbbbbTbbbbbbC................w.........w.........w..........##",
	"##.......w...w.---bbbbbbbbbbbbbbbbbbC...........=========.....===========...=========....................----....bb=========================bb....----.........w......-------......w..........##",
	"##.......w...w....bbbbbbbbbbbbbbbbbbC............................................................................bbbbbbbbbbbbbbbbbbbbbbbbbbbbb.................w.........w.........w..........##",
	"##.......w..---...bbbbbbbbbbbbbbbbbb........=========...===========...===========......................----......====bbbbbbbbbbbbbbbbbbbbb====......----......-------....w.........w..........##",
	"##.ES..S.w.g.w.kk.bbbbbbobTbTbTbbNbb........a.....L...M..ok.W.a.......X...M.......TaT..................k....kko..bYbbbTbbTbbbbbabbbkbWbbbbbbbb....oP..k........w..a......w.o..W.a.kw...B....E.##",
	"#############mmmmmm###################bbbbbbCCCCCCCCCCOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~C======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC======~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################====bb################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bb====################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbb====CCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbb====CCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbZbbbbbbbbgbbbbbbZbbbb#######bbbbbb################CCCbbbZbZbbbbbbbNbbbbbbbbbbbZbbCCCCbbbbbbCCCCCCCCbbbZbbbbbbbbbbbbbNbbbbbbbbbbbbbZbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbb=========bbbbbbb#######====bb################CCCbbbbbbbbb=========bbbbbbbbbbCCCC====bbCCCCCCCCbbbbbbbbb=================bbbbbbbbbCCCCCCCC====bbCCCCCCCCCCCCCbbbbbbbbb======bCCC##",
	"######bbbbbbbPbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbbbbbbbbbbbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbb=======bbbbbbbbbbbbb=======bbbbbbbbbbbbbb====bbbbbbbbbbbbbbbbb=======bbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbJbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCC##",
	"######bb===bbbbbbMMbbbbbbbbb===bbbbbbb====bbbbbbbbJbbbbbbbbbbbbbb===bbbbbbbMMbbbbbbbb===bbbbbbb====bbbbbJbbbbbb===bbbbbbbbbbMMbbbbbbbbbbbbb===bbbbbbbbbb====bbbbbbbbbbbbbbbbb===MMbbbbbbbbbCCC##",
	"######bbbbbbbbbbbMMTbbbbbbbabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbabbbTbLbbbbMMbbbbbbbWbkbbbbbYbbbbbbbbbbbbbbbbbabbbbbTbbbbbbbMMbbLbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbabbbMMbbbbTbbbbCCC##",
	"####################mmmmmm##################################CCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
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
	# powierzchnie o własnej fizyce i brzmieniu (surfaces.gd): bagno, plama oleju; lód i śnieg to zapas pod biom zimowy
	"m": [8, "mud", 0],
	"O": [9, "oil", 0],
	"i": [10, "ice", 0],
	"s": [11, "snow", 0],
}
const ATLAS_COLS := 12

var bounds := Rect2()
var spawns: Array[Vector2] = []
var exits: Array[Vector2] = []
var stalker_home := Vector2.ZERO
var boss_home := Vector2.ZERO
## Graf A* platformówki (nav.gd) — bot i Stalker.
var nav: AStar2D

var _solid: TileMapLayer
var _back: TileMapLayer
var _decals: Node2D
var _deco: Node2D
var _props_tex: Texture2D
var _deco_list: Array = []             ## [pozycja stóp, indeks dekoracji, flip]
var _rows := 2                         ## wierszy w atlasie (2 = kod, 4 = art/tiles.png)
var _decal_list: Array = []            ## [pos, radius, seed]

func _ready() -> void:
	add_to_group("level")
	# poziom ciemności w jednym miejscu (lights.gd)
	var dark := get_parent().get_node_or_null("Darkness") as CanvasModulate
	if dark != null:
		dark.color = Lights.AMBIENT
	RenderingServer.set_default_clear_color(Lights.SKY)
	add_child(preload("res://scripts/backdrop.gd").new())
	var ts := _build_tileset()
	_back = TileMapLayer.new()
	_back.name = "Back"
	_back.tile_set = ts
	add_child(_back)
	_solid = TileMapLayer.new()
	_solid.name = "Solid"
	_solid.tile_set = ts
	add_child(_solid)
	for l in [_back, _solid]:
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# dekoracje (trawa, kamienie, trzciny…) — nad kaflami, cieniowane
	_deco = Node2D.new()
	_deco.name = "Deco"
	_deco.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_deco.draw.connect(_draw_deco)
	add_child(_deco)
	# plamy krwi — nad kaflami, pod postaciami; cieniowane (widać je w świetle)
	_decals = Node2D.new()
	_decals.name = "Decals"
	_decals.draw.connect(_draw_decals)
	add_child(_decals)
	_build_map()
	nav = Nav.new()
	nav.build((MAP[0] as String).length(), MAP.size(), _is_solid, _is_platform_cell)
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
					_back.set_cell(Vector2i(c, r), 0, Vector2i(KINDS[left][0], _row(c, r, false)))
				continue
			var k: Array = KINDS[ch]
			# wariant „wierzch" (rząd 0 atlasu), gdy nad kaflem nie ma bryły
			var top := not _is_solid(c, r - 1)
			var layer := _back if k[2] == 2 else _solid
			# bryły: alternatywa kafla z okluderem cofniętym na odsłoniętych bokach
			var alt := _exposure(c, r) if k[2] == 0 else 0
			layer.set_cell(Vector2i(c, r), 0, Vector2i(k[0], _row(c, r, top)), alt)
	_place_deco()

## Rząd atlasu: wierzch/wypełnienie + wariant (deterministyczny z pozycji).
func _row(c: int, r: int, top: bool) -> int:
	var base := 0 if top else 1
	if _rows < 4:
		return base
	return base + (2 if (c * 7 + r * 13) % 3 == 0 else 0)

## Dekoracje z art/props.png na wierzchach brył — deterministycznie z pozycji.
## Indeksy jak w bake_sprites.PROPS: grass_a, grass_b, fern, rock, bones, reeds, fence, logs.
func _place_deco() -> void:
	_props_tex = Sprites.texture(ART_PROPS)
	if _props_tex == null:
		return
	for r in MAP.size():
		var row: String = MAP[r]
		for c in row.length():
			var ch := row[c]
			if not KINDS.has(ch) or KINDS[ch][2] != 0 or _is_solid(c, r - 1):
				continue
			if _ch(c, r - 1) != ".":
				continue                     # znacznik / tło nad kaflem
			var h := (c * 73856093) ^ (r * 19349663)
			var roll := absi(h) % 100
			var feet := Vector2(c * TILE + TILE * 0.5, r * TILE)
			var pick := -1
			match ch:
				"#":
					if roll < 55:
						pick = [0, 1, 0, 1, 2, 3, 0, 4][absi(h >> 3) % 8]
				"C":
					if roll < 12:
						pick = [4, 3][absi(h >> 3) % 2]
				"~":
					if roll < 30:
						pick = 5
				"m":
					if roll < 40:
						pick = 5
			if pick >= 0:
				_deco_list.append([feet, pick, (h >> 5) & 1 == 1])
	# akcenty ręczne: płot przy starcie, kłody w tartaku
	for p in [[Vector2(9 * TILE + 8, 26 * TILE), 6], [Vector2(11 * TILE + 8, 26 * TILE), 6], [Vector2(89 * TILE + 8, 26 * TILE), 7], [Vector2(182 * TILE - 40, 26 * TILE), 7]]:
		_deco_list.append([p[0], p[1], false])
	_deco.queue_redraw()

func _draw_deco() -> void:
	if _props_tex == null:
		return
	for d in _deco_list:
		var feet: Vector2 = d[0]
		var src := Rect2(int(d[1]) * 16, 0, 16, 16)
		var dst := Rect2(feet.x - 8, feet.y - 16, 16, 16)
		if d[2]:
			dst = Rect2(feet.x + 8, feet.y - 16, -16, 16)
		_deco.draw_texture_rect_region(_props_tex, dst, src)

func _is_solid(c: int, r: int) -> bool:
	# poza mapą = bryła (krawędzie mapy nie świecą)
	if r < 0 or r >= MAP.size() or c < 0 or c >= (MAP[0] as String).length():
		return true
	var ch := _ch(c, r)
	return KINDS.has(ch) and KINDS[ch][2] == 0

func _is_platform_cell(c: int, r: int) -> bool:
	var ch := _ch(c, r)
	return KINDS.has(ch) and KINDS[ch][2] == 1

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
	var found := {"T": [], "W": [], "L": [], "P": [], "Y": [], "J": [], "Z": [], "N": [], "k": [], "o": [], "a": [], "g": []}
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
				"B": boss_home = p
				"T", "W", "L", "P", "Y", "J", "Z", "N", "k", "o", "a", "g": found[ch].append(p)
	for k in found:
		found[k].sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for i in found["T"].size():
		_add_enemy("Trzosek%d" % (i + 1), "trzosek", found["T"][i])
	for i in found["W"].size():
		_add_enemy("Wolek%d" % (i + 1), "wolek", found["W"][i])
	for i in found["L"].size():
		_add_enemy("Slepiec%d" % (i + 1), "slepiec", found["L"][i])
	for i in found["P"].size():
		_add_enemy("Podsluchacz%d" % (i + 1), "podsluchacz", found["P"][i])
	for i in found["Y"].size():
		_add_enemy("Mimik%d" % (i + 1), "mimik", found["Y"][i])
	for i in found["J"].size():
		_add_enemy("Skoczek%d" % (i + 1), "skoczek", _hang_pos(found["J"][i], 14.0))
	for i in found["Z"].size():
		_add_enemy("Cma%d" % (i + 1), "cma", _hang_pos(found["Z"][i], 8.0))
	for i in found["N"].size():
		var n := NEST_SCENE.instantiate()
		n.name = "Nest%d" % (i + 1)
		n.position = found["N"][i]
		add_child(n)
	for k in [["k", "Crate", "crate"], ["o", "Barrel", "barrel"]]:
		for i in found[k[0]].size():
			var pr: RigidBody2D = PROP.new()
			pr.name = "%s%d" % [k[1], i + 1]
			pr.kind = k[2]
			# 1 px nad podłogą: start dokładnie na krawędzi kładki jednokierunkowej
			# fizyka uznawała za „w środku" i skrzynia przelatywała piętro niżej
			pr.position = found[k[0]][i] + Vector2(0, -1)
			add_child(pr)
	_map_items = {"a": found["a"], "g": found["g"]}
	_spawn_map_items()
	var s := STALKER_SCENE.instantiate()
	s.name = "Stalker"
	s.position = stalker_home
	add_child(s)
	if boss_home != Vector2.ZERO:
		var b := BOSS_SCENE.instantiate()
		b.name = "Boss"
		b.position = boss_home
		add_child(b)

## Punkt zawieszenia pod sufitem nad znacznikiem: pierwsza bryła w górę (kolumna znacznika), a wróg
## wisi tuż pod nią (stopy = dół sprite'a). Bez sufitu zostaje na podłodze.
func _hang_pos(p: Vector2, body_h: float) -> Vector2:
	var c := int(p.x / TILE)
	var r := int(p.y / TILE) - 1
	for rr in range(r, -1, -1):
		if _is_solid(c, rr):
			return Vector2(p.x, (rr + 1) * TILE + body_h)
	return p

func _add_enemy(n: String, kind: String, p: Vector2) -> void:
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = kind
	e.position = p
	add_child(e)

# ---------------------------------------------------------------- przedmioty z mapy

## Broń leżąca na mapie w kolejności od lewej (rosnąca moc) — jest jej mało i leży w
## miejscach, do których trzeba się dostać: las przy starcie, półka w podziemnej sali,
## antresola hali w Składzie, rusztowanie tartaku. „g” = broń, „a” = skrzynka z amunicją
## dla wszystkich noszonych broni głównych (zapas jest wspólny).
const MAP_WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6, Weapons.HKM9, Weapons.GNIEW4]

var _map_items := {}

## Każdy peer tworzy te same przedmioty o tych samych nazwach (mapa jest statyczna), więc
## podniesienie rozstrzygane przez serwer znika wszędzie. Wołane też po restarcie misji.
func _spawn_map_items() -> void:
	var guns: Array = _map_items.get("g", [])
	for i in guns.size():
		_add_map_item("MapGun%d" % i, "weapon", MAP_WEAPONS[i % MAP_WEAPONS.size()], guns[i])
	var caches: Array = _map_items.get("a", [])
	for i in caches.size():
		_add_map_item("MapCache%d" % i, "cache", 0, caches[i])

func _add_map_item(n: String, kind: String, arg: int, pos: Vector2) -> void:
	if has_node(n):
		return
	var it: Node2D = PICKUP.new()
	it.name = n
	it.kind = kind
	it.arg = arg
	it.position = pos + Vector2(0, -2)
	add_child(it)

# ---------------------------------------------------------------- flary

var _flare_serial := 0

## Serwer: flara rzucona przez gracza (NoiseMgr.request_flare) — powstaje u wszystkich peerów.
func spawn_flare(pos: Vector2, vel: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	_flare_serial += 1
	var n := "Flare%d" % _flare_serial
	if NoiseMgr.has_network():
		_spawn_flare_rpc.rpc(n, pos, vel)
	else:
		_spawn_flare_rpc(n, pos, vel)

@rpc("authority", "call_local", "reliable")
func _spawn_flare_rpc(n: String, pos: Vector2, vel: Vector2) -> void:
	if has_node(n):
		return
	var f: Node2D = FLARE.new()
	f.name = n
	f.position = pos
	f.vel = vel
	add_child(f)

# ---------------------------------------------------------------- apteczki

var _pickup_serial := 0

## Serwer: apteczka wypada w punkcie (Wołek, Żyła). Stała nazwa na każdym peerze.
func spawn_health(pos: Vector2) -> void:
	spawn_item("health", 0, pos)

## Serwer: przedmiot na ziemi — "health", "ammo" (arg = broń, rounds = naboje)
## albo "weapon" (arg = broń). Nazwa węzła jest stała na każdym peerze.
func spawn_item(kind: String, arg: int, pos: Vector2, rounds := 0) -> void:
	if not NoiseMgr.is_server():
		return
	_pickup_serial += 1
	var n := "Item%d" % _pickup_serial
	if NoiseMgr.has_network():
		_spawn_item_rpc.rpc(n, kind, arg, rounds, pos)
	else:
		_spawn_item_rpc(n, kind, arg, rounds, pos)

@rpc("authority", "call_local", "reliable")
func _spawn_item_rpc(n: String, kind: String, arg: int, rounds: int, pos: Vector2) -> void:
	if has_node(n):
		return
	var h: Node2D = PICKUP.new()
	h.name = n
	h.kind = kind
	h.arg = arg
	h.rounds = rounds
	h.position = pos
	add_child(h)

## Serwer: przedmiot podniesiony — znika u wszystkich.
func take_item(n: String) -> void:
	if NoiseMgr.has_network():
		_take_item_rpc.rpc(n)
	else:
		_take_item_rpc(n)

@rpc("authority", "call_local", "reliable")
func _take_item_rpc(n: String) -> void:
	var h := get_node_or_null(n)
	if h == null:
		return
	var snd := "revive" if h.kind == "health" else ("weapon_pickup" if h.kind == "weapon" else "ammo_pickup")
	Audio.play_at(snd, h.global_position, Audio.BUS_WORLD, -8.0, 1.4 if h.kind == "health" else 1.0)
	h.queue_free()

## Serwer: restart misji czyści przedmioty.
func clear_pickups() -> void:
	if not NoiseMgr.is_server():
		return
	if NoiseMgr.has_network():
		_clear_pickups_rpc.rpc()
	else:
		_clear_pickups_rpc()

@rpc("authority", "call_local", "reliable")
func _clear_pickups_rpc() -> void:
	for f in get_tree().get_nodes_in_group("flares"):
		f.queue_free()
	for h in get_tree().get_nodes_in_group("pickups"):
		h.queue_free()
		# nazwa zwalnia się dopiero po klatce — przedmioty z mapy wracają odroczone
		h.name = "Old_%s" % h.name
	_spawn_map_items.call_deferred()

## Najbliższa broń na ziemi w zasięgu „E” (HUD podpowiada, kontroler podnosi).
func weapon_item_near(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for h in get_tree().get_nodes_in_group("pickups"):
		if h.kind != "weapon" or h.is_queued_for_deletion():
			continue
		var d: float = h.global_position.distance_to(pos)
		if d <= h.WEAPON_R and d < best_d:
			best_d = d
			best = h
	return best

## Gracz (właściciel) prosi o podniesienie broni z ziemi. Serwer sprawdza odległość,
## dolicza do zapasu naboje „z łupu”, usuwa przedmiot i odsyła przyznanie.
func request_weapon_pickup(item_name: String) -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		_weapon_pickup_rpc.rpc_id(1, item_name)
	else:
		_weapon_pickup_server(item_name, NoiseMgr.local_id())

@rpc("any_peer", "call_remote", "reliable")
func _weapon_pickup_rpc(item_name: String) -> void:
	if NoiseMgr.is_server():
		_weapon_pickup_server(item_name, multiplayer.get_remote_sender_id())

func _weapon_pickup_server(item_name: String, peer_id: int) -> void:
	var it := get_node_or_null(item_name)
	if it == null or it.kind != "weapon" or it.is_queued_for_deletion():
		return
	var pl: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == peer_id and not p.is_bot:
			pl = p
	if pl == null or pl.dead or not it.in_reach(pl):
		return
	var w: int = it.arg
	Arsenal.add_reserve(w, int(Weapons.def(w).pickup_rounds))
	take_item(item_name)
	if not NoiseMgr.has_network() or peer_id == NoiseMgr.local_id():
		pl.weapons.grant_weapon(w)
	else:
		pl.weapons.grant_weapon.rpc_id(peer_id, w)

## Gracz porzuca zastąpioną broń (leży pod stopami) — przez serwer, żeby miała stałą nazwę.
func request_drop(w: int, pos: Vector2) -> void:
	if NoiseMgr.has_network() and not NoiseMgr.is_server():
		_drop_rpc.rpc_id(1, w, pos)
	else:
		spawn_item("weapon", w, pos)

@rpc("any_peer", "call_remote", "reliable")
func _drop_rpc(w: int, pos: Vector2) -> void:
	if NoiseMgr.is_server() and Weapons.is_valid(w):
		spawn_item("weapon", w, pos)

## Plama krwi na powierzchni (vfx.splat). Lokalna, kosmetyczna.
func add_decal(pos: Vector2, radius: float) -> void:
	_decal_list.append([pos, radius, randi()])
	if _decal_list.size() > 260:
		_decal_list.pop_front()
	_decals.queue_redraw()

func _draw_decals() -> void:
	var rng := RandomNumberGenerator.new()
	for d in _decal_list:
		rng.seed = d[2]
		var p: Vector2 = d[0]
		var r: float = d[1]
		# płaska plama na podłodze: kilka spłaszczonych kropel
		for i in 5:
			var off := Vector2(rng.randf_range(-r, r), rng.randf_range(-0.6, 0.4))
			var rr := rng.randf_range(0.35, 0.8) * r
			var c := Color(0.32, 0.02, 0.04, rng.randf_range(0.55, 0.85))
			_decals.draw_set_transform(p + off, 0.0, Vector2(1.0, 0.32))
			_decals.draw_circle(Vector2.ZERO, rr, c)
	_decals.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Punkt startowy dla slotu gracza (1..4); kolejne sloty lekko przesunięte.
func spawn_for(slot: int) -> Vector2:
	if spawns.is_empty():
		return Vector2(64, 400)
	var base: Vector2 = spawns[(slot - 1) % spawns.size()]
	return base + Vector2(((slot - 1) / spawns.size()) * 14.0, 0)

func is_underground(pos: Vector2) -> bool:
	return pos.y > UNDERGROUND_Y

## Czy pod stopami jest kładka jednokierunkowa (zeskok dół+skok).
func is_platform_at(pos: Vector2) -> bool:
	var cell := _solid.local_to_map(_solid.to_local(pos + Vector2(0, 3)))
	var ac := _solid.get_cell_atlas_coords(cell)
	return ac.x == KINDS["="][0] or ac.x == KINDS["-"][0]

## Powierzchnia kafla, w który uderzył pocisk (punkt trafienia przesunięty w głąb ściany).
func surface_at_hit(pos: Vector2, normal: Vector2) -> String:
	var cell := _solid.local_to_map(_solid.to_local(pos - normal * 2.0))
	var td := _solid.get_cell_tile_data(cell)
	if td == null:
		return "dirt"
	var s: String = td.get_custom_data("surface")
	return s if s != "" else "dirt"

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
	# atlas z art/tiles.png (bake_sprites.py / artysta), inaczej generowany w kodzie
	var art := Sprites.texture(ART_TILES)
	_rows = 4 if art != null else 2
	src.texture = art if art != null else ImageTexture.create_from_image(_build_atlas())
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)

	var h := TILE * 0.5
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var plank := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 4), Vector2(-h, -h + 4)])
	for ch in KINDS:
		var k: Array = KINDS[ch]
		for variant in _rows:
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
		8:  # błoto
			return Color(0.22 + n, 0.25 + n, 0.12 + n) if top and y < 3 else Color(0.14 + n, 0.11 + n, 0.07 + n)
		9:  # olej
			return Color(0.06 + n, 0.06 + n, 0.09 + n) if top and y < 3 else Color(0.14 + n, 0.14 + n, 0.16 + n)
		10:  # lód
			return Color(0.72 + n, 0.88 + n, 0.95) if top and y < 3 else Color(0.38 + n, 0.55 + n, 0.70)
		11:  # śnieg
			return Color(0.92, 0.95, 1.0) if top and y < 3 else Color(0.62 + n, 0.70 + n, 0.82)
		7:  # tło: pień / belka (środkowe 8 px)
			if x < 4 or x > 11:
				return Color(0, 0, 0, 0)
			return Color(0.19 + n, 0.13 + n, 0.08 + n)
	return Color(1, 0, 1)
