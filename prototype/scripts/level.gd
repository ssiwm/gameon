extends Node2D
## Poziom misji na TileMapLayer (GDD §16.0 pkt 1, 1.3.5). Mapy leżą w scripts/maps/ (jedna na misję),
## a load_map(id) przebudowuje poziom — na każdym peerze identycznie (host rozsyła id, main.gd).
##
## Mapa jest siatką ASCII (MAP w pliku mapy), żeby dało się ją czytać i edytować bez
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
##   S  start  E  wyjście  T  Trzosek  W  Wołek  N  gniazdo  X  dom Stalkera  G  generator radiostacji
##   D  drezyna (stacja startowa; tor kończy się przy wyjściu E)
##   n  tablica z odprawą (kryjówka)   l  lampa pod sufitem (kryjówka)   — przy RACKS=true każde „g" dostaje stojak
##   B  Żyła — matka gniazd (boss misji)
##   k  skrzynia (fizyczna)   o  beczka (fizyczna, wybucha)
##   g  broń na ziemi         a  skrzynka z amunicją
##   m  błoto (bagno: wolno, grząsko)   O  plama oleju (ślizg)   i  lód   s  śnieg  — kafle-podłoża z własną fizyką
##   L  Ślepiec (nie widzi, słyszy)   P  Podsłuchacz (stoi, krzyczy i ściąga hordę)
##   Y  Mimik (udaje kolegę z drużyny)
##   J  Skoczek (wisi pod sufitem i spada)   Z  Ćma (światłolubna, wisi pod sufitem)
##

const TILE := 16
## Warstwy fizyki: bryły na 1 (jak dawny World), kładki na 16 — pociski
## (maska 7) i promienie okluzji/linii strzału (maska 1) przez nie przechodzą.
const LAYER_SOLID := 1
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
const FIRE_PATCH := preload("res://scripts/fire_patch.gd")
const BRICK_WALL := preload("res://scripts/brick_wall.gd")
const GRENADE := preload("res://scripts/grenade.gd")
const ACID := preload("res://scripts/acid_spit.gd")
const PLACED := preload("res://scripts/placed.gd")
const SMOKE_CLOUD := preload("res://scripts/smoke_cloud.gd")
const FLARE := preload("res://scripts/flare.gd")
const GENERATOR := preload("res://scripts/generator.gd")
const HANDCAR := preload("res://scripts/handcar.gd")
const RACK := preload("res://scripts/rack.gd")
const LAMP := preload("res://scripts/lamp.gd")
const BOARD := preload("res://scripts/board.gd")
const RADIO_SET := preload("res://scripts/radio_set.gd")
const RESULTS_WALL := preload("res://scripts/results_wall.gd")
const RANGE_LINE := preload("res://scripts/range_line.gd")
const WORKSHOP := preload("res://scripts/workshop.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const GibArt := preload("res://scripts/gib_art.gd")
const LEECH := preload("res://scripts/leech.gd")
const RANGE_TARGET := preload("res://scripts/range_target.gd")
const DEPTH_LAYERS := preload("res://scripts/depth_layers.gd")

## Mapy misji (scripts/maps/): każda niesie MAP, ID, TITLE, OBJECTIVE, UNDERGROUND_ROW, WEAPONS, ACCENTS.
const MAPS := {
	"z1_m1": preload("res://scripts/maps/z1_m1.gd"),
	"z1_m2": preload("res://scripts/maps/z1_m2.gd"),
	"z1_m3": preload("res://scripts/maps/z1_m3.gd"),
	"z1_b1": preload("res://scripts/maps/z1_b1.gd"),
	"z1_hub": preload("res://scripts/maps/z1_hub.gd"),     # kryjówka między misjami (nie należy do CAMPAIGN)
}
## Kolejność kampanii Strefy I: 1.1 → 1.2 → 1.3 → boss B1 (Pijawka); po bossie kampania wraca przez kryjówkę do 1.1.
const CAMPAIGN := ["z1_m1", "z1_m2", "z1_m3", "z1_b1"]
## Mapy losowane w Nocnym Dyżurze: bez 1.1 (samouczek bez bossa i Stalkera zaniżałby trudność serii) i bez areny B1 (osobna walka z bossem).
const SHIFT_POOL := ["z1_m2", "z1_m3"]

signal map_changed(id: String)

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

var map_id := ""
var title := ""
var objective := "nests"
var radio: Array = []             ## linie radia z danych mapy (kryjówka)
var ambient := Color(0.0245, 0.0266, 0.0406)   ## kolor ciemności (CanvasModulate): domyślny z lights.gd albo z AMBIENT mapy
var _racks := false
var _dark_node: CanvasModulate
var hp_mult := 1.0               ## mnożnik HP wrogów tej mapy (ENEMY_HP w danych mapy)
## Pogoda (weather_fx.gd): tint i błysk ciemności nałożone na `ambient` (CanvasModulate „Darkness").
const WEATHER_FLASH := Color(0.34, 0.38, 0.52)           ## kolor ciemności w szczycie błysku (zimne światło burzy)
var weather_tint := Color.WHITE
var weather_flash := 0.0
var depth_mult := 1.0                                    ## mnożnik ambientu od głębi podziemi (dread.gd)
var underground_y := 0.0         ## od tej wysokości (px) postać jest w podziemiach
var bounds := Rect2()
var spawns: Array[Vector2] = []
var exits: Array[Vector2] = []
var stalker_home := Vector2.ZERO
var boss_home := Vector2.ZERO
## Graf A* platformówki (nav.gd) — bot i Stalker.
var nav: AStar2D
## Zawał (misja 1.1, finał): obszary [c0, r0, c1, r1] (kafle, włącznie), które po zdarzeniu zamieniają się w skałę.
## Dane z mapy (const COLLAPSE); drugie wyjście po zawale to znacznik „e" (exits_alt).
var collapse_rects: Array = []
var exits_alt: Array[Vector2] = []
var _orig_map: Array = []
var _blocks: Array = []          ## już zastosowane obszary (do synchronizacji dołączających i resetu)
var _wall_cells: Dictionary = {}  ## Vector2i → nazwa ściany: kafle zajęte przez zamurowane przejścia (marker „q")
var _opened_walls: Array = []    ## nazwy już rozbitych ścian (synchronizacja dołączających)

var _solid: TileMapLayer
var _back: TileMapLayer
var _decals: Node2D
var _deco: Node2D
var _terrain_hd: Node2D                 ## dev (--newworld): teren HD rysowany nad kaflami
var _terrain_tex: CanvasTexture
var _terrain_list: Array = []           ## [kolumna, wiersz, wierzch(1)/wypełnienie(0), materiał] — kafle solid/platformy (nad _solid)
var _terrain_back_list: Array = []      ## to samo dla kafli tła (b, w) — rysowane nad _back, pod postaciami
var _terrain_back: Node2D
var _mat_tex: Dictionary = {}           ## materiał → CanvasTexture (albedo + normalne)
var _prop_hd: Dictionary = {}           ## dev: indeks dekoracji (props.png) → [CanvasTexture, rozmiar w pikselach świata] — rekwizyty HD z Tripo
var _props_tex: Texture2D
var _deco_list: Array = []             ## [pozycja stóp, indeks dekoracji, flip]
var _rows := 2                         ## wierszy w atlasie (2 = kod, 4 = art/tiles.png)
var _decal_list: Array = []            ## [pos, radius, seed]
var _map: Array = []                   ## MAP bieżącej misji
var _weapons: Array = []               ## broń z „g” (po kolei od lewej)
var _accents: Array = []
var _ts: TileSet
var _stable: Array = []                ## węzły stałe (tło, warstwy) — reszta to encje misji

func _ready() -> void:
	Sprites.apply_hd_defaults()
	add_to_group("level")
	# poziom ciemności w jednym miejscu (lights.gd)
	_dark_node = get_parent().get_node_or_null("Darkness") as CanvasModulate
	if _dark_node != null:
		_dark_node.color = Lights.AMBIENT
	RenderingServer.set_default_clear_color(Lights.SKY)
	var bd := preload("res://scripts/backdrop.gd").new()
	add_child(bd)
	_ts = _build_tileset()
	_back = TileMapLayer.new()
	_back.name = "Back"
	_back.tile_set = _ts
	add_child(_back)
	_solid = TileMapLayer.new()
	_solid.name = "Solid"
	_solid.tile_set = _ts
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
	if Sprites.newitem:
		_decals.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_decals)
	_stable = [bd, _back, _solid, _deco, _decals]
	_load(CAMPAIGN[0])

## Przebudowuje poziom na mapę `id` (wołane na każdym peerze z tym samym id). Encje starej mapy znikają od razu
## (remove_child), żeby nowe mogły dostać te same nazwy — ścieżki RPC muszą się zgadzać na wszystkich peerach.
func load_map(id: String) -> void:
	if id == map_id or not MAPS.has(id):
		return
	for c in get_children():
		if not _stable.has(c):
			remove_child(c)
			c.queue_free()
	_back.clear()
	_solid.clear()
	_deco_list.clear()
	_terrain_list.clear()
	_decal_list.clear()
	spawns.clear()
	exits.clear()
	exits_alt.clear()
	stalker_home = Vector2.ZERO
	boss_home = Vector2.ZERO
	_load(id)
	map_changed.emit(id)

func _load(id: String) -> void:
	var m = MAPS[id]
	map_id = id
	title = m.TITLE
	objective = m.OBJECTIVE
	hp_mult = float(m.ENEMY_HP)
	radio = m.RADIO
	_racks = m.RACKS
	ambient = m.AMBIENT if m.AMBIENT.a > 0.0 else Lights.AMBIENT      # alfa 0 = domyślna ciemność gry
	_apply_darkness()
	NoiseMgr.safe_zone = objective == "hub"
	underground_y = float(m.UNDERGROUND_ROW * TILE)
	_orig_map = m.MAP
	_map = (m.MAP as Array).duplicate()          # kopia: zawał (collapse) zmienia wiersze w trakcie misji
	collapse_rects = ((m as GDScript).get_script_constant_map().get("COLLAPSE", []) as Array).duplicate()
	_blocks.clear()
	_wall_cells.clear()
	_opened_walls.clear()
	_weapons = m.WEAPONS
	_accents = m.ACCENTS
	_map_items = {}
	_build_map()
	_register_walls()
	nav = Nav.new()
	nav.build((_map[0] as String).length(), _map.size(), _is_solid, _is_platform_cell)
	_spawn_entities()
	_deco.queue_redraw()
	_decals.queue_redraw()


# ---------------------------------------------------------------- mapa

func _ch(c: int, r: int) -> String:
	if r < 0 or r >= _map.size():
		return "."
	var row: String = _map[r]
	if c < 0 or c >= row.length():
		return "."
	return row[c]

func _build_map() -> void:
	var rows := _map.size()
	var cols: int = (_map[0] as String).length()
	bounds = Rect2(0, 0, cols * TILE, rows * TILE)
	for r in rows:
		for c in cols:
			_place_cell(c, r)
	_place_deco()
	_build_terrain_hd()

## Kolor ciemności = ambient mapy × tint pogody, przy błysku ciągnięty ku jasnemu kolorowi burzy.
func _apply_darkness() -> void:
	if _dark_node == null:
		return
	var c := Color(ambient.r * weather_tint.r * depth_mult, ambient.g * weather_tint.g * depth_mult, ambient.b * weather_tint.b * depth_mult, 1.0)
	_dark_node.color = c.lerp(WEATHER_FLASH, clampf(weather_flash, 0.0, 1.0))

## Tło parallax (backdrop.gd) wzmacnia / przyciemnia niebo i grzbiety wg pogody.
func set_backdrop_weather(id: String, k: float) -> void:
	for c in get_children():
		if c.has_method("set_weather"):
			c.set_weather(id, k)
			return

func apply_depth_darkness(m: float) -> void:
	if is_equal_approx(m, depth_mult):
		return
	depth_mult = m
	_apply_darkness()

func apply_weather_darkness(tint: Color, flash: float) -> void:
	if tint == weather_tint and is_equal_approx(flash, weather_flash):
		return
	weather_tint = tint
	weather_flash = flash
	_apply_darkness()

## Czy w punkcie `p` (świat) jest otwarte niebo: nad ziemią i bez bryły (dachu, skały) aż do górnej krawędzi mapy.
func sky_open_at(p: Vector2) -> bool:
	if p.y >= underground_y:
		return false
	var c := int(floor(p.x / TILE))
	for r in range(int(floor((p.y - 1.0) / TILE)), -1, -1):
		if _is_solid(c, r):
			return false
	return true

## Jeden kafel mapy do warstw (tło / bryła) — wspólne dla budowy i odświeżania po zawale.
func _place_cell(c: int, r: int) -> void:
	var ch := _ch(c, r)
	if not KINDS.has(ch):
		# znacznik albo pusto — tło dziedziczymy z lewego sąsiada, żeby
		# postać w posterunku nie zostawiała dziury w ścianie
		# (szukamy w lewo ponad sąsiednimi znacznikami — kilka znaczników obok siebie nie zostawia czarnych dziur w tle)
		var lc := c - 1
		while lc >= 0 and c - lc <= 8 and ch != "." and not KINDS.has(_ch(lc, r)) and _ch(lc, r) != ".":
			lc -= 1
		var left := _ch(lc, r) if lc >= 0 else "."
		if ch != "." and KINDS.has(left) and KINDS[left][2] == 2:
			_back.set_cell(Vector2i(c, r), 0, Vector2i(KINDS[left][0], _row(c, r, false)))
		return
	var k: Array = KINDS[ch]
	# wariant „wierzch" (rząd 0 atlasu), gdy nad kaflem nie ma bryły
	var top := not _is_solid(c, r - 1)
	var layer := _back if k[2] == 2 else _solid
	# bryły: alternatywa kafla z okluderem cofniętym na odsłoniętych bokach
	var alt := _exposure(c, r) if k[2] == 0 else 0
	layer.set_cell(Vector2i(c, r), 0, Vector2i(k[0], _row(c, r, top)), alt)

# ---------------------------------------------------------------- zawał (zmiana kafli w trakcie misji)

## Serwer: zamienia powietrze i tło w podanych obszarach w skałę u wszystkich peerów (RPC). Wołane przez mission.gd.
func collapse(rects: Array) -> void:
	if not NoiseMgr.is_server():
		return
	if NoiseMgr.has_network():
		_collapse_rpc.rpc(map_id, rects)
	else:
		_collapse_rpc(map_id, rects)

@rpc("authority", "call_local", "reliable")
func _collapse_rpc(id: String, rects: Array) -> void:
	if id != map_id:
		return
	for r in rects:
		if not _blocks.has(r):
			_blocks.append(r)
	_apply_blocks(rects)

## Dołączający gracz dostaje już zastosowane zawały (po tym, jak załadował mapę).
func send_collapse_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and NoiseMgr.has_network() and not _blocks.is_empty():
		_collapse_rpc.rpc_id(peer_id, map_id, _blocks)

func _apply_blocks(rects: Array) -> void:
	var dirty := Rect2i()
	var first := true
	for rc in rects:
		var c0 := int(rc[0])
		var r0 := int(rc[1])
		var c1 := int(rc[2])
		var r1 := int(rc[3])
		for r in range(r0, r1 + 1):
			var row: String = _map[r]
			for c in range(c0, c1 + 1):
				var ch := row[c]
				if not KINDS.has(ch) or KINDS[ch][2] != 0:         # powietrze, znaczniki, tło i kładki → skała
					row = row.substr(0, c) + "#" + row.substr(c + 1)
			_map[r] = row
		var rr := Rect2i(c0, r0, c1 - c0 + 1, r1 - r0 + 1)
		dirty = rr if first else dirty.merge(rr)
		first = false
		_push_players_out(rr)
	_refresh_region(dirty)

## Gracze (własni na tym peerze) uwięzieni w obszarze, który zaraz stanie się skałą, lądują tuż za nim — po stronie wschodniej.
func _push_players_out(rc: Rect2i) -> void:
	var area := Rect2(rc.position * TILE, rc.size * TILE)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion() or not p.is_multiplayer_authority():
			continue
		if area.grow(4.0).has_point(p.global_position + Vector2(0, -8)):
			p.global_position = Vector2(area.end.x + 10.0, p.global_position.y)
			p.velocity = Vector2.ZERO

## Odświeża kafle (z ramką 1) i graf nawigacji po zmianie `_map`.
func _refresh_region(rc: Rect2i) -> void:
	var g := rc.grow(1)
	var cols: int = (_map[0] as String).length()
	for r in range(maxi(0, g.position.y), mini(_map.size(), g.end.y)):
		for c in range(maxi(0, g.position.x), mini(cols, g.end.x)):
			_back.erase_cell(Vector2i(c, r))
			_solid.erase_cell(Vector2i(c, r))
			_place_cell(c, r)
	nav = Nav.new()
	nav.build(cols, _map.size(), _is_solid, _is_platform_cell)
	if _terrain_hd != null:
		_build_terrain_hd()                  # zawał / odbudowa: kafle HD wg aktualnej mapy

## Serwer: restart misji (wipe / nowa misja) — mapa wraca do stanu z danych.
func reset_collapse() -> void:
	if not NoiseMgr.is_server():
		return
	if NoiseMgr.has_network():
		_reset_collapse_rpc.rpc(map_id)
	else:
		_reset_collapse_rpc(map_id)

@rpc("authority", "call_local", "reliable")
func _reset_collapse_rpc(id: String) -> void:
	if id != map_id or _blocks.is_empty():
		return
	var dirty := Rect2i()
	var first := true
	for rc in _blocks:
		var rr := Rect2i(int(rc[0]), int(rc[1]), int(rc[2]) - int(rc[0]) + 1, int(rc[3]) - int(rc[1]) + 1)
		dirty = rr if first else dirty.merge(rr)
		first = false
	_blocks.clear()
	_map = _orig_map.duplicate()
	_refresh_region(dirty)

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
	for r in _map.size():
		var row: String = _map[r]
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
	# akcenty ręczne z danych mapy (płot, kłody…)
	for p in _accents:
		_deco_list.append([p[0], p[1], false])
	_deco.queue_redraw()

func _draw_deco() -> void:
	if _props_tex == null:
		return
	for d in _deco_list:
		if _terrain_hd != null and (int(d[1]) <= 2 or _prop_hd.has(int(d[1]))):
			continue                         # HD trawa i paprocie zastępuje trawa terenu, a płot/kłody/kamień — rekwizyty HD (_draw_terrain_hd)
		var feet: Vector2 = d[0]
		var src := Rect2(int(d[1]) * 16, 0, 16, 16)
		var dst := Rect2(feet.x - 8, feet.y - 16, 16, 16)
		if d[2]:
			dst = Rect2(feet.x + 8, feet.y - 16, -16, 16)
		_deco.draw_texture_rect_region(_props_tex, dst, src)

## Znak mapy → materiał HD (art/world/mat_<nazwa>.png; „terrain" = terrain_hd.png). Kolumny atlasu kafli (KINDS) pokrywane przez HD są
## w trybie --newworld przezroczyste w oryginalnym atlasie, żeby stary pixel-art nie prześwitywał.
const MATERIALS := {"#": "terrain", "C": "concrete", "M": "metal", "~": "water", "=": "grate", "-": "plank", "b": "wall", "w": "post", "m": "mud", "O": "oil"}
## Materiały rysowane tylko w górnym pasie kafla (platformy) — jeden wariant.
const PLATFORM_MATS := ["grate", "plank"]

## Dev: HD teren z atlasu art/world/terrain_hd.png (+ _n.png): wiersz 0 = glina 1024×256, wiersz 1 = wierzch 1024×320 (z przewisem trawy 64 px).
## Pas ma okres 4 kafli (kolumna % 4), więc sąsiednie kafle łączą się bez szwów.
const TERRAIN_HD_OVER := 4.0           ## przewis trawy ponad komórką (piksele świata)

func _load_terrain_hd() -> CanvasTexture:
	if not Sprites.newworld:
		return null
	return _load_material("terrain")

## Atlas materiału (albedo + normalne, mipmapy). „terrain" to terrain_hd.png, reszta mat_<nazwa>.png.
func _load_material(mat: String) -> CanvasTexture:
	if _mat_tex.has(mat):
		return _mat_tex[mat]
	var base := "res://art/world/terrain_hd" if mat == "terrain" else "res://art/world/mat_" + mat
	var d := Sprites.texture(base + ".png")
	var ct: CanvasTexture = null
	if d != null:
		ct = CanvasTexture.new()
		ct.diffuse_texture = Sprites.hd_texture(d.get_image(), false)
		var n := Sprites.texture(base + "_n.png")
		if n != null:
			ct.normal_texture = Sprites.hd_texture(n.get_image(), true)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_tex[mat] = ct
	return ct

## Wołane z main.gd po sparsowaniu `--newworld` (poziom budowany jest wcześniej niż flagi) oraz przy każdej budowie mapy.
func enable_world_hd() -> void:
	var bd := get_node_or_null("Backdrop")
	if bd == null:
		for c in get_children():
			if c.has_method("enable_hd"):
				bd = c
	if bd != null:
		bd.enable_hd()                      # tło parallax HD (art/backdrop/hd/)
	if _terrain_hd == null:
		_terrain_tex = _load_terrain_hd()
		if _terrain_tex == null:
			return
		_terrain_hd = Node2D.new()
		_terrain_hd.name = "TerrainHD"
		_terrain_hd.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(_terrain_hd)
		move_child(_terrain_hd, _solid.get_index() + 1)               # nad kaflami, pod dekoracjami i postaciami
		_stable.append(_terrain_hd)
		_terrain_back = Node2D.new()
		_terrain_back.name = "TerrainHDBack"
		_terrain_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(_terrain_back)
		move_child(_terrain_back, _back.get_index() + 1)               # nad tłem-kaflami, pod bryłami i postaciami
		_stable.append(_terrain_back)
		_hide_pixel_tiles()
		_load_props_hd()
	_build_terrain_hd()
	_deco.queue_redraw()

## Kolumny atlasu kafli pokryte materiałami HD stają się przezroczyste (kolizje i okludery zostają w danych kafli).
func _hide_pixel_tiles() -> void:
	var src := _ts.get_source(0) as TileSetAtlasSource
	var tex: Texture2D = src.texture
	if tex == null:
		return
	var img: Image = tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for ch in MATERIALS:
		if not KINDS.has(ch) or _load_material(MATERIALS[ch]) == null:
			continue
		var col: int = KINDS[ch][0]
		for y in img.get_height():
			for x in range(col * TILE, col * TILE + TILE):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	src.texture = ImageTexture.create_from_image(img)

## Rekwizyty HD (art/world/prop_<nazwa>.png + _n.png, 16 px na piksel świata) podmieniają dekoracje z props.png: 3 kamień, 6 płot, 7 kłody.
func _load_props_hd() -> void:
	_prop_hd.clear()
	for spec in [[3, "rock", Vector2(14, 8)], [6, "fence", Vector2(20, 14)], [7, "logs", Vector2(18, 10)]]:
		var d := Sprites.texture("res://art/world/prop_%s.png" % spec[1])
		if d == null:
			continue
		var ct := CanvasTexture.new()
		ct.diffuse_texture = Sprites.hd_texture(d.get_image(), false)
		var n := Sprites.texture("res://art/world/prop_%s_n.png" % spec[1])
		if n != null:
			ct.normal_texture = Sprites.hd_texture(n.get_image(), true)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_prop_hd[int(spec[0])] = [ct, spec[2]]
	# kości i trzciny: modele z art/items/ (items_proc_bake.py), skala względem ramki modelu
	for spec in [[4, "bones", 0.7], [5, "reeds", 0.9]]:
		var ct2: CanvasTexture = ItemsHd.texture(String(spec[1]))
		if ct2 != null:
			_prop_hd[int(spec[0])] = [ct2, ItemsHd.frame_wp(String(spec[1])) * float(spec[2])]

func _build_terrain_hd() -> void:
	if _terrain_hd == null:
		return
	_terrain_list.clear()
	_terrain_back_list.clear()
	for r in _map.size():
		var row: String = _map[r]
		for c in row.length():
			var ch := row[c]
			if not KINDS.has(ch) and ch != ".":
				# znacznik (S, f, g…) — tło dziedziczy z lewego sąsiada, tak jak w _place_cell
				var lc := c - 1
				while lc >= 0 and c - lc <= 8 and not KINDS.has(_ch(lc, r)) and _ch(lc, r) != ".":
					lc -= 1
				var left := _ch(lc, r) if lc >= 0 else "."
				if KINDS.has(left) and KINDS[left][2] == 2 and MATERIALS.has(left) and _load_material(MATERIALS[left]) != null:
					_terrain_back_list.append([c, r, 0, MATERIALS[left]])
				continue
			if not MATERIALS.has(ch) or not KINDS.has(ch):
				continue
			var mat: String = MATERIALS[ch]
			if _load_material(mat) == null:
				continue
			var kind: int = KINDS[ch][2]
			var top := 0 if (kind != 0 or _is_solid(c, r - 1)) else 1
			var entry := [c, r, top, mat]
			if kind == 2:
				_terrain_back_list.append(entry)
			else:
				_terrain_list.append(entry)
	_rebuild_hd_chunks()

## Fragment (chunk) świata HD: węzeł rysujący swoją porcję kafli i rekwizytów. Dzięki podziałowi silnik odrzuca (culling) fragmenty poza kadrem
## zamiast rysować całą mapę jednym elementem; wpisy posortowane wg tekstury sklejają się w mało wywołań rysowania.
class HdChunk extends Node2D:
	var items: Array = []              ## [tekstura, Rect2 docelowy, Rect2 źródłowy albo null]

	func _draw() -> void:
		for it in items:
			if it[2] == null:
				draw_texture_rect(it[0], it[1], false)
			else:
				draw_texture_rect_region(it[0], it[1], it[2])

const HD_CHUNK := 16                    ## kafli na bok fragmentu (16×16 kafli = 256×256 px świata; kadr gry to ok. 400×225 px)

## Buduje fragmenty obu warstw HD (tło nad `_back`, bryły i rekwizyty nad `_solid`) z list `_terrain_list`, `_terrain_back_list` i `_deco_list`.
func _rebuild_hd_chunks() -> void:
	for node in [_terrain_hd, _terrain_back]:
		if node == null:
			continue
		for ch in node.get_children():
			node.remove_child(ch)
			ch.queue_free()
	var layers := [[_terrain_hd, _terrain_list, true], [_terrain_back, _terrain_back_list, false]]
	for layer in layers:
		var node: Node2D = layer[0]
		if node == null:
			continue
		var list: Array = (layer[1] as Array).duplicate()
		list.sort_custom(func(x, y): return String(x[3]) < String(y[3]))            # wg materiału → sklejanie wywołań rysowania
		var buckets := {}
		for t in list:
			var c: int = t[0]
			var r: int = t[1]
			var mat: String = t[3]
			var tex := _load_material(mat)
			if tex == null:
				continue
			var col := c % 4
			var dst: Rect2
			var src: Rect2
			if int(t[2]) == 1 and not PLATFORM_MATS.has(mat):
				dst = Rect2(c * TILE, r * TILE - TERRAIN_HD_OVER, TILE, TILE + TERRAIN_HD_OVER)
				src = Rect2(col * 256, 256, 256, 320)
			else:
				dst = Rect2(c * TILE, r * TILE, TILE, TILE)
				src = Rect2(col * 256, 0, 256, 256)
			var key := Vector2i(c / HD_CHUNK, r / HD_CHUNK)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([tex, dst, src])
		if bool(layer[2]):
			for d in _deco_list:                                                      # rekwizyty HD (płot, kłody, kamień) po kaflach w swoim fragmencie
				if not _prop_hd.has(int(d[1])):
					continue
				var info: Array = _prop_hd[int(d[1])]
				var sz: Vector2 = info[1]
				var feet: Vector2 = d[0]
				var pdst := Rect2(feet.x - sz.x * 0.5, feet.y - sz.y, sz.x, sz.y)
				if d[2]:
					pdst = Rect2(feet.x + sz.x * 0.5, feet.y - sz.y, -sz.x, sz.y)
				var pkey := Vector2i(int(feet.x / TILE) / HD_CHUNK, int((feet.y - 1.0) / TILE) / HD_CHUNK)
				if not buckets.has(pkey):
					buckets[pkey] = []
				buckets[pkey].append([info[0], pdst, null])
		for key in buckets:
			var chunk := HdChunk.new()
			chunk.name = "c_%d_%d" % [key.x, key.y]
			chunk.items = buckets[key]
			node.add_child(chunk)

func _is_solid(c: int, r: int) -> bool:
	# poza mapą = bryła (krawędzie mapy nie świecą)
	if r < 0 or r >= _map.size() or c < 0 or c >= (_map[0] as String).length():
		return true
	if _wall_cells.has(Vector2i(c, r)):
		return true                       # zamurowane przejście (brick_wall.gd) — dla nawigacji i krawędzi kafli to bryła
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
	_spawn_walls()
	var found := {"T": [], "W": [], "L": [], "P": [], "Y": [], "J": [], "Z": [], "N": [], "G": [], "D": [], "n": [], "R": [], "v": [], "r": [], "t": [], "u": [], "h": [], "F": [], "H": [], "K": [], "f": [], "l": [], "k": [], "o": [], "a": [], "g": [], "q": []}
	for r in _map.size():
		var row: String = _map[r]
		for c in row.length():
			var ch := row[c]
			# punkt na podłodze: środek kafla w poziomie, dół kafla w pionie
			var p := Vector2(c * TILE + TILE * 0.5, (r + 1) * TILE)
			match ch:
				"S": spawns.append(p)
				"E": exits.append(p)
				"e": exits_alt.append(p)
				"X": stalker_home = p
				"B": boss_home = p
				"T", "W", "L", "P", "Y", "J", "Z", "N", "G", "D", "n", "R", "v", "r", "t", "u", "h", "F", "H", "K", "f", "l", "k", "o", "a", "g", "q": found[ch].append(p)
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
	for i in found["G"].size():
		var g: Node2D = GENERATOR.new()
		g.name = "Generator%d" % (i + 1)
		g.position = found["G"][i]
		add_child(g)
	for i in found["D"].size():
		var car: AnimatableBody2D = HANDCAR.new()
		car.name = "Handcar" if i == 0 else "Handcar%d" % (i + 1)
		car.position = found["D"][i]
		add_child(car)
	for i in found["n"].size():
		var bd: Node2D = BOARD.new()
		bd.name = "Board%d" % (i + 1)
		bd.position = found["n"][i]
		add_child(bd)
	for i in found["R"].size():
		var rs: Node2D = RADIO_SET.new()
		rs.name = "RadioSet%d" % (i + 1)
		rs.position = found["R"][i]
		add_child(rs)
	for i in found["v"].size():
		var rw: Node2D = RESULTS_WALL.new()
		rw.name = "ResultsWall%d" % (i + 1)
		rw.position = found["v"][i]
		add_child(rw)
	for i in found["h"].size():
		var ws: Node2D = WORKSHOP.new()
		ws.name = "Workshop%d" % (i + 1)
		ws.position = found["h"][i]
		add_child(ws)
	for i in found["r"].size():
		var rl: Node2D = RANGE_LINE.new()
		rl.name = "RangeLine%d" % (i + 1)
		rl.position = found["r"][i]
		add_child(rl)
	for i in found["t"].size():
		var rt: StaticBody2D = RANGE_TARGET.new()
		rt.name = "RangeTarget%d" % (i + 1)
		rt.position = found["t"][i]
		add_child(rt)
	for i in found["l"].size():
		var lp: Node2D = LAMP.new()
		lp.name = "Lamp%d" % (i + 1)
		lp.position = _hang_pos(found["l"][i], 0.0)
		add_child(lp)
	if found["l"].size() > 0:
		# plan pierwszy kryjówki: sylwetki mebli przed kamerą (depth_layers.gd), podłoga pod pierwszą lampą
		var lc := int(float((found["l"][0] as Vector2).x) / float(TILE))
		var fr := int(float((found["l"][0] as Vector2).y) / float(TILE))
		for rr in range(fr, _map.size()):
			if _is_solid(lc, rr):
				fr = rr
				break
		var dl: Node2D = DEPTH_LAYERS.new()
		dl.name = "DepthLayers"
		add_child(dl)
		dl.setup(float((_map[0] as String).length() * TILE), float(fr * TILE))
	if _racks:
		for i in found["g"].size():
			var rk: Node2D = RACK.new()
			rk.name = "Rack%d" % (i + 1)
			rk.position = found["g"][i]
			add_child(rk)
	for k in [["k", "Crate", "crate"], ["o", "Barrel", "barrel"]]:
		for i in found[k[0]].size():
			var pr: RigidBody2D = PROP.new()
			pr.name = "%s%d" % [k[1], i + 1]
			pr.kind = k[2]
			# 1 px nad podłogą: start dokładnie na krawędzi kładki jednokierunkowej
			# fizyka uznawała za „w środku" i skrzynia przelatywała piętro niżej
			pr.position = found[k[0]][i] + Vector2(0, -1)
			add_child(pr)
	_map_items = {"a": found["a"], "g": found["g"], "u": found["u"], "F": found["F"], "H": found["H"], "f": found["f"]}
	_spawn_map_items()
	if stalker_home != Vector2.ZERO:         # kryjówka (bez znacznika X) nie ma Stalkera
		var s := STALKER_SCENE.instantiate()
		s.name = "Stalker"
		s.position = stalker_home
		add_child(s)
	for i in found["K"].size():                   # Pijawka (misja B1): basen z danych mapy (POOL = kolumny)
		var lc: CharacterBody2D = LEECH.new()
		lc.name = "Boss"
		lc.position = found["K"][i]
		var pool: Array = ((MAPS[map_id] as GDScript).get_script_constant_map().get("POOL", []) as Array)
		lc.pool_x0 = float(int(pool[0]) * TILE) if pool.size() >= 2 else lc.position.x - 200.0
		lc.pool_x1 = float((int(pool[1]) + 1) * TILE) if pool.size() >= 2 else lc.position.x + 200.0
		add_child(lc)
	if boss_home != Vector2.ZERO:
		var b := BOSS_SCENE.instantiate()
		b.name = "Boss"
		b.position = boss_home
		add_child(b)

## Ile ukrytych skrytek (znaczniki „H") ma bieżąca mapa — cel poboczny misji 1.1.
func stash_total() -> int:
	return (_map_items.get("H", []) as Array).size() if Scrap.enabled() else 0

## Ile nieśmiertelników (znaczniki „F") ma bieżąca mapa — cel główny misji 1.1.
func tag_total() -> int:
	return (_map_items.get("F", []) as Array).size()

## Odprawa misji `id` z danych mapy (kryjówka, tablica): tytuł, cel, liczba wrogów każdego rodzaju policzona ze znaczników.
const THREAT_CHARS := {"T": "trzosek", "W": "wolek", "L": "slepiec", "P": "podsluchacz", "Y": "mimik", "J": "skoczek", "Z": "cma"}

func briefing(id: String) -> Dictionary:
	if not MAPS.has(id):
		return {}
	var m = MAPS[id]
	var counts := {}
	var stalker := false
	var nests := 0
	var boss := false
	var boss_name := ""
	var gens := 0
	var tags := 0
	var stashes := 0
	for row in m.MAP:
		for ch in (row as String):
			if THREAT_CHARS.has(ch):
				counts[THREAT_CHARS[ch]] = int(counts.get(THREAT_CHARS[ch], 0)) + 1
			elif ch == "X":
				stalker = true
			elif ch == "N":
				nests += 1
			elif ch == "B":
				boss = true
				boss_name = "THE VEIN"
			elif ch == "K":
				boss = true
				boss_name = "THE LEECH"
			elif ch == "G":
				gens += 1
			elif ch == "F":
				tags += 1
			elif ch == "H":
				stashes += 1
	return {"title": m.TITLE, "brief": m.BRIEF, "counts": counts, "stalker": stalker, "nests": nests, "boss": boss, "boss_name": boss_name, "generators": gens, "tags": tags, "stashes": stashes}

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
## miejscach, do których trzeba się dostać. „g” = broń (lista w danych mapy), „a” = skrzynka
## z amunicją dla wszystkich noszonych broni głównych (zapas jest wspólny).
var _map_items := {}

## Każdy peer tworzy te same przedmioty o tych samych nazwach (mapa jest statyczna), więc
## podniesienie rozstrzygane przez serwer znika wszędzie. Wołane też po restarcie misji.
func _spawn_map_items() -> void:
	var guns: Array = _map_items.get("g", [])
	for i in guns.size():
		_add_map_item("MapGun%d" % i, "weapon", _weapons[i % _weapons.size()], guns[i])
	if Scrap.enabled():
		var stash: Array = _map_items.get("H", [])
		for i in stash.size():
			_add_map_item("MapStash%d" % i, "stash", 0, stash[i], Scrap.STASH_VALUE)
	var flare_boxes: Array = _map_items.get("f", [])
	for i in flare_boxes.size():
		_add_map_item("MapFlares%d" % i, "flares", 0, flare_boxes[i], 2)
	var tags: Array = _map_items.get("F", [])
	for i in tags.size():
		_add_map_item("MapTag%d" % i, "tag", 0, tags[i])
	var caches: Array = _map_items.get("a", [])
	for i in caches.size():
		_add_map_item("MapCache%d" % i, "cache", 0, caches[i])
	if Scrap.enabled():
		var stash: Array = _map_items.get("u", [])
		for i in stash.size():
			_add_map_item("MapScrap%d" % i, "scrap", 0, stash[i], Scrap.CACHE_VALUE)

func _add_map_item(n: String, kind: String, arg: int, pos: Vector2, value := 0) -> void:
	if has_node(n):
		return
	var it: Node2D = PICKUP.new()
	it.name = n
	it.kind = kind
	it.arg = arg
	it.rounds = value
	it.position = pos + Vector2(0, -2)
	it.static_display = kind == "weapon" and _racks      # broń na stojaku stoi w miejscu
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

# ---------------------------------------------------------------- zamurowane przejścia

const WALL_MAX_ROWS := 6
var _wall_defs: Array = []       ## [{name, pos (stopy), rows, cells}] od lewej do prawej

## Znaczniki „q" → zamurowane przejścia: ściana zajmuje kafle od znacznika w górę do pierwszej bryły (maks. WALL_MAX_ROWS).
## Rejestrujemy je przed zbudowaniem grafu nawigacji — dla A* to bryła, więc nikt nie planuje drogi do skrytki za ścianą.
func _register_walls() -> void:
	_wall_defs.clear()
	var found: Array = []
	for r in _map.size():
		var row: String = _map[r]
		for c in row.length():
			if row[c] == "q":
				found.append(Vector2i(c, r))
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for i in found.size():
		var cell: Vector2i = found[i]
		var rows := 1
		while rows < WALL_MAX_ROWS and cell.y - rows >= 0 and not _is_solid(cell.x, cell.y - rows):
			rows += 1
		var cells: Array = []
		for k in rows:
			cells.append(Vector2i(cell.x, cell.y - k))
			_wall_cells[Vector2i(cell.x, cell.y - k)] = "BrickWall%d" % (i + 1)
		_wall_defs.append({"name": "BrickWall%d" % (i + 1), "pos": Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE), "rows": rows, "cells": cells})

func _spawn_walls() -> void:
	for wd in _wall_defs:
		var w: Node2D = BRICK_WALL.new()
		w.name = String(wd["name"])
		w.position = wd["pos"]
		w.rows = int(wd["rows"])
		add_child(w)

## Serwer: ściana rozbita — znika u wszystkich peerów, kafle odblokowują nawigację.
func break_wall(wall_name: String) -> void:
	if not NoiseMgr.is_server() or _opened_walls.has(wall_name):
		return
	if NoiseMgr.has_network():
		_break_wall_rpc.rpc(map_id, wall_name)
	else:
		_break_wall_rpc(map_id, wall_name)

@rpc("authority", "call_local", "reliable")
func _break_wall_rpc(id: String, wall_name: String) -> void:
	if id != map_id or _opened_walls.has(wall_name):
		return
	_open_wall(wall_name, true)

func _open_wall(wall_name: String, with_fx: bool) -> void:
	_opened_walls.append(wall_name)
	var rc := Rect2i()
	var first := true
	for cell in _wall_cells.keys():
		if String(_wall_cells[cell]) == wall_name:
			var cr := Rect2i(cell, Vector2i(1, 1))
			rc = cr if first else rc.merge(cr)
			first = false
	for cell in _wall_cells.keys():
		if String(_wall_cells[cell]) == wall_name:
			_wall_cells.erase(cell)
	var w := get_node_or_null(wall_name)
	if w != null:
		if with_fx and w.has_method("crumble"):
			w.crumble()
		else:
			w.queue_free()
	if not first:
		_refresh_region(rc)

## Dołączający gracz dostaje listę już rozbitych ścian.
func send_walls_to(peer_id: int) -> void:
	if NoiseMgr.is_server() and NoiseMgr.has_network():
		for n in _opened_walls:
			_break_wall_rpc.rpc_id(peer_id, map_id, n)

## Test map: otwiera wszystkie ściany bez efektów (maptest sprawdza osiągalność skrytek za nimi).
func open_all_walls_for_test() -> void:
	for wd in _wall_defs.duplicate():
		if not _opened_walls.has(String(wd["name"])):
			_open_wall(String(wd["name"]), false)

func walls_total() -> int:
	return _wall_defs.size()

# ---------------------------------------------------------------- ogień na podłodze

const MAX_FIRE_PATCHES := 16
const FIRE_MERGE_DIST := 18.0
var _fire_serial := 0

## Serwer: HKM-9 zostawia ogień na podłodze w `pos`. Blisko istniejącego ognia tylko go odnawia; pula jest ograniczona (najstarszy gaśnie).
func spawn_fire_patch(pos: Vector2, weapon: int, shooter: int, life := FIRE_PATCH.FIRE_LIFE) -> void:
	if not NoiseMgr.is_server():
		return
	var live: Array = get_tree().get_nodes_in_group("fire_patches").filter(func(p: Node) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())
	for p in live:
		if absf(p.global_position.x - pos.x) < FIRE_MERGE_DIST and absf(p.global_position.y - pos.y) < 10.0:
			_refresh_fire_patch(String(p.name), life)
			return
	if live.size() >= MAX_FIRE_PATCHES:
		(live[0] as Node).queue_free()
	_fire_serial += 1
	var n := "Fire%d" % _fire_serial
	if NoiseMgr.has_network():
		_spawn_fire_rpc.rpc(n, pos, weapon, shooter, life)
	else:
		_spawn_fire_rpc(n, pos, weapon, shooter, life)

func _refresh_fire_patch(n: String, life: float) -> void:
	if NoiseMgr.has_network():
		_refresh_fire_rpc.rpc(n, life)
	else:
		_refresh_fire_rpc(n, life)

@rpc("authority", "call_local", "reliable")
func _refresh_fire_rpc(n: String, life: float) -> void:
	var f := get_node_or_null(n)
	if f != null:
		f.life = maxf(f.life, life)

@rpc("authority", "call_local", "reliable")
func _spawn_fire_rpc(n: String, pos: Vector2, weapon: int, shooter: int, life: float) -> void:
	if has_node(n):
		return
	var f: Node2D = FIRE_PATCH.new()
	f.name = n
	f.position = pos
	f.weapon = weapon
	f.shooter_id = shooter
	f.life = life
	add_child(f)

# ---------------------------------------------------------------- miny, ładunki i dym (A2)

var _placed_serial := 0
var _smoke_serial := 0

## Serwer: mina / ładunek postawiony pod nogami gracza (Arsenal.request_throw dla rodzaju „place”): przyklejony do podłogi.
func spawn_placed(kind: String, pos: Vector2, dir: Vector2, shooter: int) -> void:
	if not NoiseMgr.is_server():
		return
	var space := get_world_2d().direct_space_state
	var fh := space.intersect_ray(PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, 40.0), 1 | 16))
	var at: Vector2 = (fh["position"] as Vector2) + Vector2(0, -1) if not fh.is_empty() else pos
	_placed_serial += 1
	var n := "Placed%d" % _placed_serial
	if NoiseMgr.has_network():
		_spawn_placed_rpc.rpc(n, kind, at, dir, shooter)
	else:
		_spawn_placed_rpc(n, kind, at, dir, shooter)

@rpc("authority", "call_local", "reliable")
func _spawn_placed_rpc(n: String, kind: String, pos: Vector2, dir: Vector2, shooter: int) -> void:
	if has_node(n):
		return
	var p: Node2D = PLACED.new()
	p.name = n
	p.kind = kind
	p.position = pos
	p.dir = dir
	p.shooter_id = shooter
	add_child(p)

## Serwer: chmura dymu w punkcie (granat dymny po zapalniku).
func spawn_smoke(pos: Vector2, life: float) -> void:
	if not NoiseMgr.is_server():
		return
	_smoke_serial += 1
	var n := "Smoke%d" % _smoke_serial
	if NoiseMgr.has_network():
		_spawn_smoke_rpc.rpc(n, pos, life)
	else:
		_spawn_smoke_rpc(n, pos, life)

@rpc("authority", "call_local", "reliable")
func _spawn_smoke_rpc(n: String, pos: Vector2, life: float) -> void:
	if has_node(n):
		return
	var s: Node2D = SMOKE_CLOUD.new()
	s.name = n
	s.position = pos
	s.life = life
	add_child(s)

var _acid_serial := 0

## Serwer: kwas Pijawki (leech.gd `_spit`) — pocisk po łuku u wszystkich peerów.
func spawn_acid(pos: Vector2, vel: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	_acid_serial += 1
	var n := "Acid%d" % _acid_serial
	if NoiseMgr.has_network():
		_spawn_acid_rpc.rpc(n, pos, vel)
	else:
		_spawn_acid_rpc(n, pos, vel)

@rpc("authority", "call_local", "reliable")
func _spawn_acid_rpc(n: String, pos: Vector2, vel: Vector2) -> void:
	if has_node(n):
		return
	var a: Node2D = ACID.new()
	a.name = n
	a.position = pos
	a.vel = vel
	add_child(a)

# ---------------------------------------------------------------- granaty (rzucane przedmioty)

var _grenade_serial := 0

## Serwer: granat rzucony przez gracza (Arsenal.request_throw) — powstaje u wszystkich peerów.
func spawn_grenade(kind: String, pos: Vector2, vel: Vector2, shooter: int) -> void:
	if not NoiseMgr.is_server():
		return
	_grenade_serial += 1
	var n := "Grenade%d" % _grenade_serial
	if NoiseMgr.has_network():
		_spawn_grenade_rpc.rpc(n, kind, pos, vel, shooter)
	else:
		_spawn_grenade_rpc(n, kind, pos, vel, shooter)

@rpc("authority", "call_local", "reliable")
func _spawn_grenade_rpc(n: String, kind: String, pos: Vector2, vel: Vector2, shooter: int) -> void:
	if has_node(n):
		return
	var g: Node2D = GRENADE.new()
	g.name = n
	g.kind = kind
	g.position = pos
	g.vel = vel
	g.shooter_id = shooter
	add_child(g)

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
	for gr in get_tree().get_nodes_in_group("grenades"):
		gr.queue_free()
	for ac in get_tree().get_nodes_in_group("acid"):
		ac.queue_free()
	for pl in get_tree().get_nodes_in_group("placed"):
		pl.queue_free()
	for sm in get_tree().get_nodes_in_group("smoke_clouds"):
		sm.queue_free()
	for fp in get_tree().get_nodes_in_group("fire_patches"):
		fp.queue_free()
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
## Broń na stojaku kryjówki, której drużyna jeszcze nie kupiła w warsztacie (scrap.gd) — nie da się jej wziąć.
func is_locked_item(it: Node2D) -> bool:
	return it != null and it.kind == "weapon" and it.static_display and not Scrap.is_unlocked(int(it.arg))

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
	if it == null or it.kind != "weapon" or it.is_queued_for_deletion() or is_locked_item(it):
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

const DROP_MAX_DIST := 64.0          ## broń porzucona przez klienta musi wylądować tuż przy jego postaci

@rpc("any_peer", "call_remote", "reliable")
func _drop_rpc(w: int, pos: Vector2) -> void:
	if not NoiseMgr.is_server() or not Weapons.is_valid(w):
		return
	var pl: Node2D = null
	var sender := multiplayer.get_remote_sender_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == sender and not p.is_bot:
			pl = p
	if pl == null or pl.dead or pos.distance_to(pl.global_position) > DROP_MAX_DIST:
		return                                                    # nie wstawimy broni w dowolne miejsce mapy (czy gracz ją miał, serwer nie wie — zostaje tylko ta luka)
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
		if Sprites.newitem:
			_draw_decal_hd(p, r, rng)
			continue
		# płaska plama na podłodze: kilka spłaszczonych kropel
		for i in 5:
			var off := Vector2(rng.randf_range(-r, r), rng.randf_range(-0.6, 0.4))
			var rr := rng.randf_range(0.35, 0.8) * r
			var c := Color(0.32, 0.02, 0.04, rng.randf_range(0.55, 0.85))
			_decals.draw_set_transform(p + off, 0.0, Vector2(1.0, 0.32))
			_decals.draw_circle(Vector2.ZERO, rr, c)
	_decals.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Plama krwi w grafice HD: jedna tekstura kałuży (GibArt.blood_pool) na plamę, rysowana przez `draw_texture_rect` — wszystkie plamy sklejają się w jedno wywołanie.
func _draw_decal_hd(p: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	var tex := GibArt.blood_pool(rng.randi() % 4)
	var w := r * 3.6
	var h := w * 20.0 / 64.0
	_decals.draw_texture_rect(tex, Rect2(p.x - w * 0.5, p.y - h * 0.62, w, h), false, Color(1, 1, 1, rng.randf_range(0.8, 1.0)))

## Punkt startowy dla slotu gracza (1..4); kolejne sloty lekko przesunięte.
func spawn_for(slot: int) -> Vector2:
	if spawns.is_empty():
		return Vector2(64, 400)
	var base: Vector2 = spawns[(slot - 1) % spawns.size()]
	return base + Vector2(((slot - 1) / spawns.size()) * 14.0, 0)

func is_underground(pos: Vector2) -> bool:
	return pos.y > underground_y

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
