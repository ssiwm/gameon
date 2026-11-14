extends Node2D
## Strefa wydobycia (DESTRUCTION_PLAN.md D5): prostokąt gruntu z danych mapy (`DIG_ZONES`), rozkopywany kilofem, bronią białą i wybuchem
## w drobnej siatce 4 × 4 komórki na kafel (komórka 4 px = 0,33 m). Gęstość 0–255 leży w narożnikach komórek; kontur z marching squares
## daje naraz kolizję (odcinki `ConcavePolygonShape2D` na `StaticBody2D` warstwy świata — co widać, w to się uderza; puste kieszenie
## i wyspy działają same, bo to tylko odcinki) i siatkę 3D (`chunk_mesh`, rysuje ją view3d.gd: `_sync_dig_zones`).
##
## Narożniki: pierścień tuż za strefą (stały, z kafli mapy: bryła 255, powietrze 0) + narożniki strefy. Narożnik na brzegu strefy, przy którym
## leży powietrze mapy, ma gęstość dokładnie ISO — kontur wypada wtedy równo z krawędzią kafla, więc wierzch strefy jest na tej samej wysokości
## co sąsiednie kafle (bez progu 2 px pod stopami; spike S2).
##
## Materiał (dig_materials.gd) leży w każdym narożniku: materiał strefy + wtrącenia z szumu o ziarnie strefy (głazy w ziemi, żyła w skale) —
## każdy peer liczy go sam z danych mapy. Twardość ogranicza gęstość zabraną jednym ciosem, a narzędzie decyduje, co w ogóle bierze.
##
## Sieć: serwer rozstrzyga cios (`melee_dig`, `blast_dig`) i rozsyła operację (środek, połówki boków, zaokrąglenie, narzędzie) do wszystkich
## peerów; każdy stosuje ją sam — wynik jest ten sam, a wiadomość ma kilkanaście bajtów zamiast listy komórek. Dołączający dostaje całą
## gęstość strefy (skompresowaną, `send_state_to`); wipe i punkt kontrolny bossa przywracają stan (`reset_to`, level.gd `reset_breakables`).
## Kafel strefy, w którym nie została już skała, przestaje być bryłą dla nawigacji i siatki dźwięku (`on_tiles` → level.gd `_dig_tiles_changed`).
##
## Znajdźki (część 2 D5): miejsca z ziarna strefy (`_plan_finds`, ten sam wynik u każdego peera), w głębi skały — nie na wierzchu i nie
## przy powietrzu mapy. Stan znajdźki wynika z gęstości wokół niej (`_find_state`): zakopana → odkopana do połowy (powietrze blisko: błysk
## w latarce, widok 3D) → odkopana (wypada jako przedmiot: rozstrzyga serwer w `apply_dig`, zawartość dobiera dopiero wtedy). Cios tuż
## przy zakopanej znajdźce dzwoni w metal (`melee_dig` → "metal"), skaner „Sowa” pokazuje zakopane w zasięgu (`buried_finds`).
##
## Osypywanie i wyspy (D5, po części 2): serwer co SIM_DT liczy krok — luźny materiał (żwir, dig_materials.gd `loose`) bez podparcia spada
## i zsuwa się po skosie do kąta 45° (reguła piasku, tylko w aktywnych kolumnach), a bryła odcięta od skały mapy (wyspa — zalewanie od
## narożników pierścienia, które są pełną skałą mapy) spada w całości, aż na czymś oprze się. Wynik idzie do wszystkich jako delta narożników
## (gęstość i materiał, `_cells_rpc`) — materiał się przesuwa, więc stan dla dołączających niesie i gęstość, i materiał. Gracz zasypany
## osypiskiem wychodzi na wierzch usypiska z krótkim ogłuszeniem (przygniecenie, nie śmierć), wróg — na wierzch (serwer).

const Mats := preload("res://scripts/dig_materials.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Throwables := preload("res://scripts/throwables.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const Vfx := preload("res://scripts/vfx.gd")

const TILE := 16.0
const CELL := 4.0                     ## px komórki
const PER_TILE := 4                   ## komórek na bok kafla
const ISO := 128                      ## próg bryły (gęstość >= ISO = skała)
const CHUNK := 16                     ## komórek na bok fragmentu kolizji i siatki
const LAYER_WORLD := 1
const SOFT := 4.0                     ## px: pasmo gęstości wokół brzegu wyrwy (= komórka, więc interpolacja konturu trafia dokładnie w kształt)
## Wyrwy ciosu: prostokąty liczone od postaci (nie od punktu trafienia) i wyrównane do siatki komórek — brzegi leżą na liniach siatki,
## więc kontur ma ostre rogi bez faz, a dno tunelu nie wędruje w górę ani w dół od ciosu do ciosu. Kształt idzie za kierunkiem ciosu, tak
## żeby po wykopie dało się w nim stanąć (postać 10 × 22 px, skok ok. 42 px):
const CUT_H := 28.0                   ## px: wysokość przejścia w bok (wzrost postaci + 6 px na podskok)
const SIDE_FRONT := 19.0              ## px: czoło wyrwy w bok przed środkiem postaci (5 px pół szerokości + 14 px postępu na cios)
const SIDE_BACK := 8.0                ## px: tył wyrwy za środkiem postaci — podnosi strop nad nią (stopień w górę da się wtedy wskoczyć)
const DOWN_W := 20.0                  ## px: szerokość szybu (szerszy od postaci, żeby nie zaklinowała się rogami)
const DOWN_D := 12.0                  ## px: głębokość szybu na cios
const UP_D := 12.0                    ## px: wnęka nad głową na cios
const DIAG_DROP := 8.0                ## px: stopień przy ciosie po skosie (w dół — zejście, w górę — próg do wskoczenia)
const N_DIG := 1.5                    ## hałas ciosu kilofem w grunt (jak w ścianę, breakable.gd); materiał mnoży (dig_materials.gd `noise`)
const BLADE_NOISE := 0.5              ## broń biała w ziemi: wolniej, ale ciszej
const BLAST_DIG := 0.5                ## promień wyrwy po wybuchu = połowa promienia fali
# znajdźki (część 2): liczby do strojenia po playteście; pule z odnowieniem po 3 misjach — część 3
const FIND_EVERY := 16                ## kafli skały strefy na jedną znajdźkę
const FIND_MAX := 6
const FIND_SPACING := 3               ## kafle: najmniejszy odstęp znajdziek (Czebyszew)
const FIND_KINDS := [["scrap", 40], ["ammo", 20], ["supply", 15], ["battery", 15], ["part", 10]]   ## rodzaj → waga losowania
const FIND_NEAR := 3                  ## narożniki (12 px): powietrze tak blisko = odkopana do połowy (błysk w latarce)
const FIND_OUT := 5                   ## z 3 × 3 narożników wokół znajdźki tyle powietrzem = odkopana, wypada
const FIND_CLINK := 6.0               ## px: zakopana znajdźka tak blisko wyrwy ciosu = cios dzwoni w metal
const FIND_BLAST_PUSH := 10.0         ## px: wybuch odrzuca odkopaną znajdźkę od środka
const FIND_SCRAP := Vector2i(1, 3)    ## złom ze znajdźki (min, max)
enum Find { BURIED, NEAR, OUT }
# osypywanie i wyspy (serwer); liczby do strojenia po playteście
const SIM_DT := 0.05                  ## s: krok symulacji (20 Hz)
const GRAIN_FALL := 2                 ## narożników na krok w dół dla luźnego materiału (2 × 4 px × 20 Hz = 160 px/s)
const ISLAND_VMAX := 4                ## narożników na krok dla spadającej wyspy (przyspiesza od 1)
const CRUSH_STUN := 0.6               ## s ogłuszenia gracza zasypanego osypiskiem albo wyspą
const CRUSH_MIN := 8.0                ## px: wyciągnięcie o więcej = zasypanie (ogłusza); mniej — osypisko tylko podniosło stopy
const N_POUR := 0.4                   ## hałas osypującego się żwiru (najwyżej co POUR_EVERY s)
const POUR_EVERY := 0.5
const N_ISLAND := 2.0                 ## hałas upadku wyspy (× rozmiar: 0,5–2)

var c0 := 0                           ## kafel lewego górnego rogu strefy
var r0 := 0
var tiles := Vector2i.ZERO            ## rozmiar strefy w kaflach
var mat_key := "dirt"                 ## materiał strefy (wtrącenia z szumu)
var seed_v := 0                       ## ziarno strefy (wtrącenia; w PR 2 — znajdźki)
var map_key := ""                     ## mapa, na której stoi strefa (RPC ze starej mapy po zmianie są pomijane)
var on_tiles: Callable                ## (Rect2i kafli mapy) — zmienił się stan „kafel wolny” (level.gd `_dig_tiles_changed`)
var nx := 0                           ## komórek strefy w poziomie
var ny := 0
var _w := 0                           ## narożników w wierszu (nx + 3: pierścień + strefa + pierścień)
var _h := 0
var _d := PackedByteArray()           ## gęstość narożników
var _d0 := PackedByteArray()          ## gęstość z danych mapy (reset)
var _m := PackedByteArray()           ## materiał narożników (dig_materials.gd ORDER)
var _fixed := PackedByteArray()       ## 1 = narożnik pierścienia (nie zmienia się)
var _open := PackedByteArray()        ## 1 = kafel strefy bez skały (dla nawigacji przechodni)
var _rock0 := PackedByteArray()       ## 1 = kafel strefy był skałą w danych mapy
var _ccx := 0                         ## fragmentów w poziomie
var _ccy := 0
var _shapes: Array[ConcavePolygonShape2D] = []
var chunk_ver := PackedInt32Array()   ## wersja fragmentu (widok 3D przebudowuje siatkę po zmianie)
var digs := 0                         ## operacji kopania od wczytania / resetu (test, pomiar, stan dla dołączających)
var rebuild_usec := 0                 ## czas ostatniej przebudowy fragmentów (kontur + kolizja) w mikrosekundach
var find_round := 0                   ## numer odnowienia puli (Scrap.dig_round): nowe ziarno = nowe miejsca
var pool_key := ""                    ## klucz puli znajdziek w Scrap („mapa/DigZoneN”, część 3)
var _solid_at: Callable               ## kafle mapy poza strefą (z setup) — nowe rozmieszczenie po odnowieniu puli
## Znajdźki: {"i", "j" (narożnik), "pos" (px świata), "kind" (FIND_KINDS albo „small” — miejsce wykopane w puli: drobnica), "kind0" (rodzaj
## z ziarna), "state" (Find)}; kolejność z ziarna — indeks = id znajdźki (też w puli).
var finds: Array[Dictionary] = []
var finds_out := 0                    ## serwer: ile znajdziek wypadło od wczytania / resetu (test, dziennik)
var _m0 := PackedByteArray()          ## materiał z danych mapy (reset; materiał osypiska się przesuwa)
var _in_isl := PackedByteArray()      ## 1 = narożnik spadającej wyspy (osypywanie go nie rusza)
var _islands: Array[Dictionary] = []  ## spadające wyspy: {"cells": PackedInt32Array, "v": narożników na krok, "drop": narożników łącznie}
var _cols := Vector2i(-1, -1)         ## aktywne kolumny osypywania [od, do] (narożniki; -1 — spokój)
var _check_islands := false           ## po operacji kopania: sprawdzić spójność w następnym kroku
var _sim_t := 0.0
var _parity := 0                      ## kolejność zsuwania w lewo / w prawo (symetria usypiska)
var _pour_t := 0.0                    ## s do następnego hałasu osypywania
var _pour_fx_t := 0.0                 ## u każdego peera: s do następnego dźwięku osypywania
var sim_steps := 0                    ## kroków z ruchem od wczytania (test, pomiar)
var sim_usec := 0                     ## czas ostatniego kroku z ruchem (µs)
var islands_fallen := 0               ## serwer: wysp, które spadły od wczytania / resetu
var fx_hits := 0                      ## u każdego peera: efektów ciosu od wczytania (test)
var fx_last := {}                     ## ostatni efekt ciosu {"mat", "tool", "metal", "by"} (test)

## Ustawia strefę z wpisu `DIG_ZONES` ([c0, r0, c1, r1, materiał, ziarno, udział wtrąceń?], kafle włącznie). `solid_at(c, r) -> bool` — czy
## kafel mapy (poza strefą) jest bryłą; `zone_solid(c, r) -> bool` — czy kafel strefy był skałą w danych mapy (przed wycięciem).
func setup(def: Array, solid_at: Callable, zone_solid: Callable) -> void:
	add_to_group("dig_zones")
	c0 = int(def[0])
	r0 = int(def[1])
	tiles = Vector2i(int(def[2]) - c0 + 1, int(def[3]) - r0 + 1)
	mat_key = String(def[4]) if def.size() > 4 else "dirt"
	if not Mats.MATS.has(mat_key):
		push_warning("dig_zone: nieznany materiał %s — ziemia" % mat_key)
		mat_key = "dirt"
	seed_v = int(def[5]) if def.size() > 5 else 0
	var mix: float = float(def[6]) if def.size() > 6 else float(Mats.MATS[mat_key]["mix"])
	nx = tiles.x * PER_TILE
	ny = tiles.y * PER_TILE
	_w = nx + 3
	_h = ny + 3
	position = Vector2(c0 * TILE, r0 * TILE)
	_d.resize(_w * _h)
	_fixed.resize(_w * _h)
	_m.resize(_w * _h)
	var base := Mats.code(mat_key)
	var inc_key := String(Mats.MATS[mat_key]["inclusion"])
	var inc := Mats.code(inc_key) if inc_key != "" else base
	var noise := FastNoiseLite.new()                          # wtrącenia: plamy szumu o ziarnie strefy (ten sam wynik u każdego peera)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_v
	noise.frequency = 0.09
	var thr := 1.0 - 1.6 * clampf(mix, 0.0, 0.6)
	for j in _h:
		for i in _w:
			var k := j * _w + i
			_m[k] = inc if mix > 0.0 and noise.get_noise_2d(float(i), float(j)) > thr else base
			var p := _corner_px(i, j)                         # względem strefy
			if i == 0 or j == 0 or i == _w - 1 or j == _h - 1:
				# narożnik pierścienia na krawędzi kafla (bryła z jednej strony, powietrze z drugiej) = ISO: kontur równo z krawędzią,
				# bez progu 2 px na szwie strefa / mapa
				var n_solid := 0
				for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					var q: Vector2 = p + o
					if solid_at.call(floori(q.x / TILE) + c0, floori(q.y / TILE) + r0):
						n_solid += 1
				_d[k] = 255 if n_solid == 4 else (0 if n_solid == 0 else ISO)
				_fixed[k] = 1
				continue
			# narożnik strefy: cztery kafle wokół punktu; powietrze mapy obok = kontur dokładnie na krawędzi (ISO)
			var air_out := false
			var solid_in := false
			for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var q: Vector2 = p + o
				var t := Vector2i(floori(q.x / TILE), floori(q.y / TILE))
				var inside := t.x >= 0 and t.y >= 0 and t.x < tiles.x and t.y < tiles.y
				if inside:
					solid_in = solid_in or bool(zone_solid.call(t.x + c0, t.y + r0))
				elif not bool(solid_at.call(t.x + c0, t.y + r0)):
					air_out = true
			_d[k] = (ISO if air_out else 255) if solid_in else 0
	_d0 = _d.duplicate()
	_m0 = _m.duplicate()
	_in_isl.resize(_w * _h)
	_open.resize(tiles.x * tiles.y)
	_rock0.resize(tiles.x * tiles.y)
	for ty in tiles.y:
		for tx in tiles.x:
			_open[ty * tiles.x + tx] = 1 if _tile_clear(tx, ty) else 0
			_rock0[ty * tiles.x + tx] = 1 if bool(zone_solid.call(tx + c0, ty + r0)) else 0
	_solid_at = solid_at
	pool_key = "%s/%s" % [map_key, name]
	find_round = Scrap.dig_round(pool_key)
	_plan_finds(solid_at)
	_apply_pool()
	Scrap.changed.connect(_apply_pool)                         # pula z zapisu hosta albo z sync (klient), odnowienie po misji
	_ccx = ceili(float(nx + 2) / CHUNK)
	_ccy = ceili(float(ny + 2) / CHUNK)
	chunk_ver.resize(_ccx * _ccy)
	for ci in _ccx * _ccy:
		var body := StaticBody2D.new()
		body.name = "Chunk%d" % ci
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var sh := ConcavePolygonShape2D.new()
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		_shapes.append(sh)
		chunk_ver[ci] = 0
		_rebuild(ci)

## Narożnik (i, j) w pikselach względem strefy (i = 1, j = 1 to lewy górny róg strefy).
func _corner_px(i: int, j: int) -> Vector2:
	return Vector2(float(i - 1) * CELL, float(j - 1) * CELL)

## Prostokąt strefy w pikselach świata.
func rect_px() -> Rect2:
	return Rect2(global_position, Vector2(nx, ny) * CELL)

## Prostokąt strefy w kaflach mapy.
func rect_tiles() -> Rect2i:
	return Rect2i(c0, r0, tiles.x, tiles.y)

## Czy punkt świata leży w skale strefy (gęstość narożników komórki, interpolowana dwuliniowo).
func solid_at_px(gp: Vector2) -> bool:
	var p := (gp - global_position) / CELL + Vector2(1, 1)
	var i := floori(p.x)
	var j := floori(p.y)
	if i < 0 or j < 0 or i >= _w - 1 or j >= _h - 1:
		return false
	var fx := p.x - i
	var fy := p.y - j
	var a := float(_d[j * _w + i])
	var b := float(_d[j * _w + i + 1])
	var c := float(_d[(j + 1) * _w + i + 1])
	var e := float(_d[(j + 1) * _w + i])
	return lerpf(lerpf(a, b, fx), lerpf(e, c, fx), fy) >= ISO

## Materiał (klucz z dig_materials.gd) najbliższego narożnika punktu świata; poza strefą — materiał strefy.
func material_at_px(gp: Vector2) -> String:
	var p := (gp - global_position) / CELL + Vector2(1, 1)
	var i := clampi(roundi(p.x), 0, _w - 1)
	var j := clampi(roundi(p.y), 0, _h - 1)
	return Mats.key_of(_m[j * _w + i])

## Ułamek skały w strefie (0–1) — pomiar postępu kopania.
func solid_fraction() -> float:
	var n := 0
	var s := 0
	for j in range(1, _h - 1):
		for i in range(1, _w - 1):
			n += 1
			if _d[j * _w + i] >= ISO:
				s += 1
	return float(s) / float(maxi(n, 1))

## Czy kafel strefy (tx, ty — względem strefy) jest już wolny: żaden z 3 × 3 narożników we wnętrzu kafla nie jest skałą.
## Kafel z niedokończonym wykopem zostaje bryłą — bot i wrogowie nie wchodzą w niedokończone tunele.
func _tile_clear(tx: int, ty: int) -> bool:
	for j in range(ty * PER_TILE + 2, ty * PER_TILE + PER_TILE + 1):
		for i in range(tx * PER_TILE + 2, tx * PER_TILE + PER_TILE + 1):
			if _d[j * _w + i] >= ISO:
				return false
	return true

## Czy kafel mapy (c, r) w strefie jest już wolny (level.gd: `_dig_cells`).
func tile_open(c: int, r: int) -> bool:
	var tx := c - c0
	var ty := r - r0
	if tx < 0 or ty < 0 or tx >= tiles.x or ty >= tiles.y:
		return false
	return _open[ty * tiles.x + tx] == 1

## Czy kafel mapy (c, r) w strefie był skałą w danych mapy (reset zasypuje tylko takie).
func solid_in_data(c: int, r: int) -> bool:
	var tx := c - c0
	var ty := r - r0
	if tx < 0 or ty < 0 or tx >= tiles.x or ty >= tiles.y:
		return false
	return _rock0[ty * tiles.x + tx] == 1

# ---------------------------------------------------------------- kopanie (serwer rozstrzyga, wszyscy stosują)

## Serwer: cios z `origin` (stopy − 9 px, jak w weapon_controller.gd) w kierunku `dir` narzędziem `tool` (dig_materials.gd Tool). Kopie, gdy
## w prostokącie wyrwy jest skała, którą to narzędzie bierze, i rozsyła efekt ciosu (`_hit_rpc`; `by` — player_id bijącego, jego kamera
## drga). Zwraca {"at": punkt na pył i dźwięk, "mat": materiał, "metal": cios przy zakopanej znajdźce} albo pusty słownik.
func melee_dig(space: PhysicsDirectSpaceState2D, origin: Vector2, dir: Vector2, reach: float, tool: int, by := -1) -> Dictionary:
	var r := cut_rect(origin, dir)
	var mat := _rock_in(r, tool)
	if mat < 0:
		return {}
	var at := _face_point(r, origin, dir, reach)
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, origin + dir * reach, LAYER_WORLD))
	if not hit.is_empty() and hit["collider"] is Node and (hit["collider"] as Node).get_parent() == self:
		at = hit["position"]
	var key := Mats.key_of(mat)
	NoiseMgr.add_noise(N_DIG * float(Mats.MATS[key]["noise"]) * (BLADE_NOISE if tool == Mats.Tool.BLADE else 1.0), at, "dig")
	var metal := find_near_rect(r.grow(FIND_CLINK)) >= 0          # przed cięciem: znajdźka, która tym ciosem wypadnie, też dzwoni
	_send(r.get_center(), r.size * 0.5, 0.0, tool)
	var top := Vector2(clampf(at.x - signf(dir.x) * 3.0, r.position.x + 2.0, r.end.x - 2.0), r.position.y + 2.0)   # urobek z górnej krawędzi wyrwy, przy czole
	if NoiseMgr.has_network():
		_hit_rpc.rpc(map_key, at, -dir, mat, tool, metal, top, by)
	else:
		_hit_rpc(map_key, at, -dir, mat, tool, metal, top, by)
	return {"at": at, "mat": key, "metal": metal}

## Każdy peer: efekt ciosu w strefę wg materiału (dig_materials.gd: snd, chip, dust, clods, sparks). Do 1.7.557 kopanie szło przez
## Arsenal.broadcast_hit z `Mat.WORLD` (Vfx.hit tego nie zna — cisza, nic) albo `Mat.DUST` (pyłek Ćmy). Teraz trzy warstwy, bo to one mówią,
## że coś odpadło: uderzenie (dźwięk + okruchy i grudki od ściany, w skale czasem iskra stali o kamień), obłoczek pyłu, który wisi w świetle
## latarki, i drobny urobek sypiący się ze stropu wyrwy (`top`). Broń biała w ziemi — mniej i ciszej. Zakopana znajdźka: dodatkowo metal
## (iskry i brzęk) — podpowiedź bez skanera. Kamera drga tylko u bijącego (`by`); kilof w skale dostaje krótki hitstop (Feel: bez niego
## na hoście z klientami). Cząsteczki są cieniowane (poza iskrami): nocą widać je tylko w snopie latarki albo przy lampie, jak prawdziwy kurz.
@rpc("authority", "call_local", "unreliable")
func _hit_rpc(key: String, at: Vector2, out: Vector2, mat: int, tool: int, metal: bool, top: Vector2, by: int) -> void:
	if key != map_key:
		return
	fx_hits += 1
	fx_last = {"mat": Mats.key_of(mat), "tool": tool, "metal": metal, "by": by}
	var lvl := get_parent()
	if lvl == null or not lvl.is_inside_tree():
		return
	var m: Dictionary = Mats.MATS[Mats.key_of(mat)]
	var pick := tool != Mats.Tool.BLADE
	var k := 1.0 if pick else 0.55
	var hard := String(m["hit"]) == "world"
	var chip: Color = m["chip"]
	var snd: Array = m["snd"]
	out = out.normalized() if out.length() > 0.1 else Vector2.UP
	# uderzenie: okruchy (skała — ostre i szybkie) albo grudki (ziemia, żwir — cięższe, wolniejsze)
	Vfx.chips(lvl, at, out, chip, maxi(2, roundi(float(m["clods"]) * k)), "chip", 135.0 if hard else 90.0, Vector2(0.7, 1.5) if hard else Vector2(0.9, 2.0))
	# pył: kilka dużych, rzadkich i powolnych plam zamiast obłoczka trafienia kuli (Vfx.puff) — ten przy postaci, w snopie latarki i aurze,
	# dawał wyraźne jasne krążki zamiast mgiełki (zrzut 2026-11-14)
	Vfx.burst(lvl, at + out * 3.0, m["dust"], 3, 2.0, 10.0 * k, out, 90.0, -6.0, 1.8, Vector2(7.0, 11.0) * k, false, true,
		{"fade": true, "explosiveness": 0.9})
	# urobek ze stropu: drobne bryłki spadają same z siebie (bez prędkości początkowej). Bryłki, nie plamki-billboardy: te w świetle
	# aury postaci świeciły jak świetliki (zrzut 2026-11-14)
	Vfx.burst(lvl, top, chip, roundi(5.0 * k), 0.0, 14.0, Vector2.DOWN, 70.0, 520.0, 0.7, Vector2(0.35, 0.75), false, false, {"mesh": "chip"})
	if pick and randf() < float(m["sparks"]):
		Vfx.burst(lvl, at, Color(1.0, 0.82, 0.45), randi_range(2, 4), 60.0, 170.0, out, 45.0, 380.0, 0.16, Vector2(0.5, 0.9), true)
	Audio.play_variant_at(String(snd[0]), 3, at, Audio.BUS_WORLD, float(snd[1]) - (3.0 if not pick else 0.0), float(snd[2]) * (1.12 if not pick else 1.0))
	if metal:
		# drobne i szybkie iskry, nie Vfx.sparks (kula w blachę): tamte przy postaci wyglądały jak świecące kulki (zrzut 2026-11-14)
		Vfx.burst(lvl, at, Color(1.0, 0.86, 0.5), 5, 80.0, 210.0, out, 50.0, 420.0, 0.14, Vector2(0.35, 0.6), true)
		Audio.play_variant_at("impact_hard", 3, at, Audio.BUS_WORLD, -11.0, 1.25)
		Audio.play_variant_at("ricochet", 2, at, Audio.BUS_WORLD, -18.0, 1.1, 0.12)
	if by >= 0 and by == NoiseMgr.local_id():
		Feel.kick(out * (2.6 if hard else 1.4) * k)                 # narzędzie odbija od ściany w stronę bijącego
		Feel.shake((1.4 if hard else 0.7) * k)
		if pick and hard:
			Feel.hitstop(0.035)

## Miejsce uderzenia na pył i dźwięk: pierwszy punkt skały na linii ciosu (czoło wyrwy), a gdy linia idzie powietrzem (cios po skosie, wnęka
## nad głową) — środek skały w prostokącie wyrwy `r`. Środek samego prostokąta leży w postaci (wyrwa w bok sięga 8 px za nią), więc
## okruchy i pył wychodziły z jej nóg (zrzut 2026-11-14).
func _face_point(r: Rect2, origin: Vector2, dir: Vector2, reach: float) -> Vector2:
	var t := 0.0
	while t <= reach + CELL:
		var p := origin + dir * t
		if solid_at_px(p):
			return p - dir * 1.0
		t += 2.0
	var sum := Vector2.ZERO
	var n := 0
	var a := (r.position - global_position) / CELL + Vector2(1, 1)
	var b := (r.end - global_position) / CELL + Vector2(1, 1)
	for j in range(maxi(1, roundi(a.y)), mini(_h - 2, roundi(b.y)) + 1):
		for i in range(maxi(1, roundi(a.x)), mini(_w - 2, roundi(b.x)) + 1):
			if _d[j * _w + i] >= ISO and _fixed[j * _w + i] == 0:
				sum += global_position + _corner_px(i, j)
				n += 1
	return sum / float(n) if n > 0 else r.get_center()

## Czy w zasięgu ciosu z `origin` w kierunku `dir` jest skała strefy (dowolne narzędzie) i której nie bierze broń biała — wybór kilofa
## (weapon_controller.gd `melee_for_target`). Zwraca [jest skała, broń biała jej nie bierze].
func cut_needs(origin: Vector2, dir: Vector2) -> Array:
	var r := cut_rect(origin, dir)
	var any := _rock_in(r, Mats.Tool.PICK) >= 0
	return [any, any and _rock_in(r, Mats.Tool.BLADE) < 0]

## Prostokąt wyrwy ciosu (px świata) z miejsca postaci (`origin` = stopy − 9) w kierunku `dir`, wyrównany do siatki komórek strefy.
func cut_rect(origin: Vector2, dir: Vector2) -> Rect2:
	var feet := _snap(origin.y + 9.0, global_position.y)
	var r: Rect2
	if absf(dir.x) < 0.38:                                    # pionowo: szyb pod stopami albo wnęka nad głową, w osi postaci
		# linia do usunięcia (grunt pod stopami, strop) leży we wnętrzu prostokąta (+ 1 komórka) — _rock_in patrzy tylko na wnętrze
		if dir.y > 0.0:
			r = Rect2(origin.x - DOWN_W * 0.5, feet - CELL, DOWN_W, DOWN_D + CELL)
		else:
			r = Rect2(origin.x - DOWN_W * 0.5, feet - CUT_H - UP_D, DOWN_W, UP_D + CELL)
	else:                                                     # w bok i po skosie: przejście na wzrost postaci, po skosie o stopień niżej/wyżej
		var bottom := feet
		if absf(dir.y) >= 0.38:
			bottom += DIAG_DROP * signf(dir.y)
		var xa := origin.x - signf(dir.x) * SIDE_BACK
		var xb := origin.x + signf(dir.x) * SIDE_FRONT
		r = Rect2(minf(xa, xb), bottom - CUT_H, absf(xb - xa), CUT_H)
	var x0 := _snap(r.position.x, global_position.x)
	var x1 := _snap(r.end.x, global_position.x)
	var y0 := _snap(r.position.y, global_position.y)
	var y1 := _snap(r.end.y, global_position.y)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

## Najbliższa linia siatki komórek (`o` — początek strefy na tej osi).
func _snap(v: float, o: float) -> float:
	return o + roundf((v - o) / CELL) * CELL

## Materiał skały we wnętrzu prostokąta (px świata, wyrównany do siatki; narożniki na brzegu nie zmieniają kształtu), którą bierze `tool`;
## -1 — nic do kopania. Przy kilku materiałach — najtwardszy (dźwięk i efekt ciosu).
func _rock_in(r: Rect2, tool: int) -> int:
	var a := (r.position - global_position) / CELL + Vector2(1, 1)
	var b := (r.end - global_position) / CELL + Vector2(1, 1)
	var best := -1
	var best_p := 256
	for j in range(maxi(1, roundi(a.y) + 1), mini(_h - 2, roundi(b.y) - 1) + 1):
		for i in range(maxi(1, roundi(a.x) + 1), mini(_w - 2, roundi(b.x) - 1) + 1):
			var k := j * _w + i
			if _fixed[k] == 0 and _d[k] >= ISO:
				var pw := Mats.power(_m[k], tool)
				if pw > 0 and pw < best_p:
					best_p = pw
					best = _m[k]
	return best

## Serwer: wybuch w zasięgu strefy (combat.gd `explode`) — okrągła wyrwa o połowie promienia fali, bierze każdy materiał.
func blast_dig(pos: Vector2, radius: float) -> bool:
	var rr := radius * BLAST_DIG
	if not rect_px().grow(rr + SOFT).has_point(pos):
		return false
	_send(pos, Vector2.ZERO, rr, Mats.Tool.BLAST)
	return true

func _send(pos: Vector2, half: Vector2, round_r: float, tool: int) -> void:
	if NoiseMgr.has_network():
		_dig_rpc.rpc(map_key, pos, half, round_r, tool)
	else:
		_dig_rpc(map_key, pos, half, round_r, tool)

@rpc("authority", "call_local", "reliable")
func _dig_rpc(key: String, pos: Vector2, half: Vector2, round_r: float, tool: int) -> void:
	if key != map_key:
		return
	apply_dig(pos, half, round_r, tool)

## Każdy peer: wycina zaokrąglony prostokąt (środek `pos` w świecie, połowy boków `half`, zaokrąglenie `round_r`; `half` = 0 → koło) i przebudowuje
## dotknięte fragmenty. Gęstość narożnika = odległość od brzegu kształtu przeskalowana na 0–255 w paśmie ±SOFT (brzeg = ISO − 1), łączona przez
## min — wyrwy sumują się dokładnie, a kontur z marching squares leży na brzegu kształtu. Narzędzie `tool` i materiał narożnika ograniczają,
## ile gęstości zabiera jedno uderzenie (dig_materials.gd `power`; 0 — narzędzie tego materiału nie bierze).
func apply_dig(pos: Vector2, half: Vector2, round_r: float, tool: int) -> void:
	digs += 1
	var lp := pos - global_position                            # px względem strefy
	var ext := half + Vector2.ONE * (round_r + SOFT)
	var i0 := maxi(1, floori((lp.x - ext.x) / CELL) + 1)
	var i1 := mini(_w - 2, ceili((lp.x + ext.x) / CELL) + 1)
	var j0 := maxi(1, floori((lp.y - ext.y) / CELL) + 1)
	var j1 := mini(_h - 2, ceili((lp.y + ext.y) / CELL) + 1)
	var touched := {}
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * _w + i
			if _fixed[k] == 1 or _d[k] == 0:
				continue
			var power := Mats.power(_m[k], tool)
			if power <= 0:
				continue
			var p := _corner_px(i, j) - lp
			var qv := Vector2(absf(p.x) - half.x, absf(p.y) - half.y)
			var sdf := Vector2(maxf(qv.x, 0.0), maxf(qv.y, 0.0)).length() + minf(maxf(qv.x, qv.y), 0.0) - round_r
			if sdf >= SOFT:
				continue
			# brzeg kształtu (sdf = 0) = ISO − 1 (już powietrze): wklęsłe rogi wyrwy (dno przy ścianie) wychodzą ostre, dno tunelu płaskie.
			# Cena: wypukła krawędź wyrwy przy wierzchu strefy (ISO) dostaje skos 45° na komórkę (4 px) — działa jak małe podciągnięcie.
			# Marching squares nie da ostrych rogów obu rodzajów naraz, gdy narożnik leży dokładnie na progu.
			var target := clampi(ISO - 1 + roundi(sdf / SOFT * 127.0), 0, 255)
			var nd := maxi(mini(int(_d[k]), target), int(_d[k]) - power)
			if nd == int(_d[k]):
				continue
			_d[k] = nd
			_touch(touched, i, j)
	var t0 := Time.get_ticks_usec()
	for ci in touched:
		_rebuild(int(ci))
	rebuild_usec = Time.get_ticks_usec() - t0
	if not touched.is_empty():
		_update_finds(Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1).grow(FIND_NEAR), pos, tool)
		_update_tiles(_tile_rect(i0, i1, j0, j1))
		if NoiseMgr.is_server():
			_wake(i0 - 1, i1 + 1)
			_check_islands = true

## Narożnik (i, j) należy do czterech komórek — ich fragmenty do przebudowy.
func _touch(touched: Dictionary, i: int, j: int) -> void:
	for oy: int in [-1, 0]:
		for ox: int in [-1, 0]:
			var ci := i + ox
			var cj := j + oy
			if ci >= 0 and cj >= 0 and ci < _w - 1 and cj < _h - 1:
				touched[(cj / CHUNK) * _ccx + (ci / CHUNK)] = true

## Kafle strefy (względem strefy) wokół prostokąta narożników [i0, i1] × [j0, j1].
func _tile_rect(i0: int, i1: int, j0: int, j1: int) -> Rect2i:
	return Rect2i(floori(float(i0 - 1) / PER_TILE) - 1, floori(float(j0 - 1) / PER_TILE) - 1, (i1 - i0) / PER_TILE + 3, (j1 - j0) / PER_TILE + 3)

## Przelicza „kafel wolny” w prostokącie kafli strefy `rt` i zgłasza zmienione kafle poziomowi (nawigacja, siatka dźwięku, rzut mapy).
func _update_tiles(rt: Rect2i) -> void:
	var changed := Rect2i()
	var any := false
	for ty in range(maxi(0, rt.position.y), mini(tiles.y, rt.end.y)):
		for tx in range(maxi(0, rt.position.x), mini(tiles.x, rt.end.x)):
			var o := 1 if _tile_clear(tx, ty) else 0
			if o == _open[ty * tiles.x + tx]:
				continue
			_open[ty * tiles.x + tx] = o
			var cr := Rect2i(tx + c0, ty + r0, 1, 1)
			changed = cr if not any else changed.merge(cr)
			any = true
	if any and on_tiles.is_valid():
		on_tiles.call(changed)

# ---------------------------------------------------------------- stan: dołączający, wipe, punkt kontrolny

## Gęstość i materiał strefy (skompresowane, jedno za drugim) — puste, gdy strefa jest jak w danych mapy. Materiał, bo osypisko go przesuwa.
func state() -> PackedByteArray:
	if _d == _d0 and _m == _m0:
		return PackedByteArray()
	return (_d + _m).compress(FileAccess.COMPRESSION_ZSTD)

## Serwer: dołączający gracz dostaje stan strefy (jeśli ktoś już kopał).
func send_state_to(peer_id: int) -> void:
	var s := state()
	if not s.is_empty():
		_state_rpc.rpc_id(peer_id, map_key, s)

## Serwer: strefa wraca do stanu `s` (`state()`; pusty — dane mapy) u wszystkich peerów. Wipe i nowa misja — pusty, punkt kontrolny bossa —
## stan z przebudzenia (level.gd `reset_breakables`).
func reset_to(s: PackedByteArray) -> void:
	if NoiseMgr.has_network():
		_state_rpc.rpc(map_key, s)
	else:
		_state_rpc(map_key, s)

@rpc("authority", "call_local", "reliable")
func _state_rpc(key: String, s: PackedByteArray) -> void:
	if key != map_key:
		return
	var dm := (_d0 + _m0) if s.is_empty() else s.decompress(_w * _h * 2, FileAccess.COMPRESSION_ZSTD)
	if dm.size() != _w * _h * 2:
		push_warning("dig_zone: zły rozmiar stanu %s (%d zamiast %d)" % [name, dm.size(), _w * _h * 2])
		return
	_islands.clear()                                             # symulacja od nowa: nic nie spada, nic się nie osypuje
	_in_isl.fill(0)
	_cols = Vector2i(-1, -1)
	_check_islands = false
	if s.is_empty():
		islands_fallen = 0
	var d := dm.slice(0, _w * _h)
	var m := dm.slice(_w * _h)
	if d == _d and m == _m:
		return
	_d = d
	_m = m
	digs = 0 if s.is_empty() else maxi(digs, 1)
	for ci in _ccx * _ccy:
		_rebuild(ci)
	for f in finds:                                              # bez wypadania: przedmioty z wykopanych znajdziek sprząta level.gd (wipe, punkt kontrolny)
		f["state"] = _find_state(f)
	if s.is_empty():
		finds_out = 0
	_update_tiles(Rect2i(0, 0, tiles.x, tiles.y))
	_unstick_players()

## Po zasypaniu wykopu (reset) albo osypisku: gracz tego peera, który stoi w skale, wychodzi w górę na pierwsze wolne miejsce nad sobą
## (najdalej na wierzch strefy) — jak `_push_players_out` przy odbudowanej ścianie (level.gd). Ruch postaci należy do właściciela, więc każdy
## peer przesuwa tylko swoje. `stun` — ogłuszenie (przygniecenie przez osypisko lub wyspę; reset bez niego).
func _unstick_players(stun := 0.0) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion() or not p.is_multiplayer_authority():
			continue
		if _push_up(p) > CRUSH_MIN and stun > 0.0:              # przysypane stopy tylko podnoszą; ogłusza dopiero zasypanie
			p.stun_t = maxf(float(p.stun_t), stun)

## Serwer: wróg w skale strefy (osypisko, wyspa) wychodzi na wierzch jak gracz.
func _unstick_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and not e.is_queued_for_deletion() and not e.is_in_group("props") and not e.is_in_group("breakables") and e.get("alive") != false:
			_push_up(e)

## Postać `n` (stopy w `global_position`) w skale strefy → w górę o 4 px do pierwszego miejsca, gdzie stopy i głowa są w powietrzu
## (najdalej nad wierzch strefy). Zwraca, o ile px (0 — nie była w skale).
func _push_up(n: Node2D) -> float:
	var rc := rect_px()
	var gp: Vector2 = n.global_position
	if gp.x < rc.position.x or gp.x > rc.end.x or gp.y < rc.position.y - 1.0 or gp.y > rc.end.y + 24.0:
		return 0.0
	if not (solid_at_px(gp + Vector2(0, -10)) or solid_at_px(gp + Vector2(0, -2))):
		return 0.0
	var y := gp.y
	while y > rc.position.y - 0.5:
		y -= CELL
		if not solid_at_px(Vector2(gp.x, y - 2.0)) and not solid_at_px(Vector2(gp.x, y - 12.0)) and not solid_at_px(Vector2(gp.x, y - 20.0)):
			break
	n.global_position = Vector2(gp.x, maxf(y, rc.position.y - 0.5))
	if "velocity" in n:
		n.velocity = Vector2.ZERO
	return gp.y - n.global_position.y

# ---------------------------------------------------------------- osypywanie i wyspy (serwer liczy, wszyscy stosują deltę)

## Serwer: kolumny narożników [a, b] do sprawdzenia w następnych krokach osypywania.
func _wake(a: int, b: int) -> void:
	a = maxi(a, 1)
	b = mini(b, _w - 2)
	_cols = Vector2i(a, b) if _cols.x < 0 else Vector2i(mini(_cols.x, a), maxi(_cols.y, b))

## Czy strefa jest w spoczynku (nic się nie osypuje, nic nie spada) — test i pomiar.
func is_settled() -> bool:
	return _cols.x < 0 and _islands.is_empty() and not _check_islands

func _physics_process(delta: float) -> void:
	_pour_fx_t = maxf(0.0, _pour_fx_t - delta)
	if not NoiseMgr.is_server():
		return
	_pour_t = maxf(0.0, _pour_t - delta)
	if is_settled():
		_sim_t = 0.0
		return
	_sim_t += delta
	while _sim_t >= SIM_DT:
		_sim_t -= SIM_DT
		_step()

## Serwer: jeden krok — wykrycie nowych wysp, ruch wysp, osypywanie luźnego materiału; zmiany idą do wszystkich jedną deltą.
func _step() -> void:
	var t0 := Time.get_ticks_usec()
	var changed := {}
	var fx := PackedVector3Array()                               # (x, y, siła): siła 0 — osypywanie, > 0 — upadek wyspy
	if _check_islands:
		_check_islands = false
		_detect_islands()
	for isl in _islands.duplicate():
		if _move_island(isl, changed):
			_islands.erase(isl)
			_land(isl, fx)
	if _cols.x >= 0:
		var pour := _settle(changed)
		if pour != Vector2.INF and _pour_t <= 0.0:
			_pour_t = POUR_EVERY
			NoiseMgr.add_noise(N_POUR, pour, "dig")
			fx.append(Vector3(pour.x, pour.y, 0.0))
	if changed.is_empty():
		return
	sim_steps += 1
	sim_usec = Time.get_ticks_usec() - t0
	var idx := PackedInt32Array(changed.keys())
	var d := PackedByteArray()
	var m := PackedByteArray()
	for k in idx:
		d.append(_d[k])
		m.append(_m[k])
	if NoiseMgr.has_network():
		_cells_rpc.rpc(map_key, idx, d, m, fx)
	else:
		_cells_rpc(map_key, idx, d, m, fx)

## Czy narożnik `k` jest wolny dla spadającego materiału (w strefie, powietrze, nie spadająca wyspa).
func _free(k: int) -> bool:
	return k >= 0 and k < _w * _h and _fixed[k] == 0 and _d[k] < ISO and _in_isl[k] == 0

## Przeniesienie narożnika skały `a` → `b` (gęstość i materiał); `a` zostaje powietrzem.
func _move(a: int, b: int, changed: Dictionary) -> void:
	_d[b] = _d[a]
	_m[b] = _m[a]
	_d[a] = 0
	changed[a] = true
	changed[b] = true

## Luźny materiał w aktywnych kolumnach, od dołu: spada (do GRAIN_FALL narożników), a oparty — zsuwa się po skosie, gdy obok i po skosie
## jest powietrze (kąt usypiska 45°). Zwraca środek ruchu (hałas, efekt) albo Vector2.INF; bez ruchu kolumny gasną.
func _settle(changed: Dictionary) -> Vector2:
	_parity ^= 1
	var lo := _w
	var hi := -1
	var sum := Vector2.ZERO
	var n := 0
	var dirs := PackedInt32Array([-1, 1] if _parity == 0 else [1, -1])
	for j in range(_h - 2, 0, -1):
		for ii in range(_cols.x, _cols.y + 1):
			var i := ii if _parity == 0 else _cols.y - (ii - _cols.x)
			var k := j * _w + i
			if _fixed[k] == 1 or _d[k] < ISO or _in_isl[k] == 1 or not Mats.loose(_m[k]):
				continue
			var to := -1
			if _free(k + _w):
				to = k + _w
				for _s in GRAIN_FALL - 1:
					if _free(to + _w):
						to += _w
			else:
				for dx in dirs:
					if _free(k + dx) and _free(k + _w + dx):
						to = k + _w + dx
						break
			if to < 0:
				continue
			_move(k, to, changed)
			lo = mini(lo, mini(i, to % _w))
			hi = maxi(hi, maxi(i, to % _w))
			sum += _corner_px(to % _w, to / _w)
			n += 1
	if n == 0:
		_cols = Vector2i(-1, -1)
		return Vector2.INF
	_cols = Vector2i(maxi(1, lo - 1), mini(_w - 2, hi + 1))
	return global_position + sum / float(n)

## Spójność: skała strefy połączona (po bokach narożników) z narożnikiem pierścienia, który jest pełną skałą mapy, stoi; reszta to wyspy —
## każda spada w całości. Zalewanie po całej strefie (kilka tysięcy narożników — znikomy koszt), tylko po operacji kopania.
func _detect_islands() -> void:
	var n := _w * _h
	var seen := PackedByteArray()
	seen.resize(n)
	var q := PackedInt32Array()
	for k in n:
		if _fixed[k] == 1 and _d[k] == 255:
			seen[k] = 1
			q.append(k)
	_flood(q, seen)
	for k in n:
		if seen[k] == 1 or _fixed[k] == 1 or _d[k] < ISO or _in_isl[k] == 1:
			continue
		var start := PackedInt32Array([k])
		seen[k] = 1
		var cells := _flood(start, seen)
		for c in cells:
			_in_isl[c] = 1
		_islands.append({"cells": cells, "v": 1, "drop": 0})

## Zalewanie od `q` po narożnikach skały strefy (nie pierścienia, nie spadających wysp); zwraca odwiedzone (z `q`).
func _flood(q: PackedInt32Array, seen: PackedByteArray) -> PackedInt32Array:
	var h := 0
	while h < q.size():
		var k := q[h]
		h += 1
		for nb in [k - 1, k + 1, k - _w, k + _w]:
			if nb >= 0 and nb < _w * _h and seen[nb] == 0 and _fixed[nb] == 0 and _d[nb] >= ISO and _in_isl[nb] == 0:
				seen[nb] = 1
				q.append(nb)
	return q

## Wyspa spada o `v` narożników (przyspiesza do ISLAND_VMAX), dopóki pod każdym jej narożnikiem jest powietrze albo ona sama. true — oparła się.
func _move_island(isl: Dictionary, changed: Dictionary) -> bool:
	var cells: PackedInt32Array = isl["cells"]
	var steps := int(isl["v"])
	var moved := 0
	for _s in steps:
		var own := {}
		for k in cells:
			own[k] = true
		var ok := true
		for k in cells:
			var b := k + _w
			if not own.has(b) and not _free(b):
				ok = false
				break
		if not ok:
			break
		var vd := PackedByteArray()
		var vm := PackedByteArray()
		for k in cells:
			vd.append(_d[k])
			vm.append(_m[k])
			_d[k] = 0
			_in_isl[k] = 0
			changed[k] = true
		for c in cells.size():
			var b := cells[c] + _w
			_d[b] = vd[c]
			_m[b] = vm[c]
			_in_isl[b] = 1
			changed[b] = true
			cells[c] = b
		moved += 1
	isl["cells"] = cells
	isl["drop"] = int(isl["drop"]) + moved
	if moved < steps:
		for k in cells:
			_in_isl[k] = 0
		return true
	isl["v"] = mini(steps + 1, ISLAND_VMAX)
	return false

## Serwer: wyspa oparła się — hałas, dziennik, efekt (przez deltę), a luźny materiał na niej może się dalej osypywać.
func _land(isl: Dictionary, fx: PackedVector3Array) -> void:
	var cells: PackedInt32Array = isl["cells"]
	var c := Vector2.ZERO
	var lo := _w
	var hi := -1
	for k in cells:
		c += _corner_px(k % _w, k / _w)
		lo = mini(lo, k % _w)
		hi = maxi(hi, k % _w)
	c = global_position + c / float(maxi(cells.size(), 1))
	if int(isl["drop"]) == 0:                                    # nie ruszyła się (oparta o pierścień bez skały mapy) — bez pętli sprawdzeń
		return
	islands_fallen += 1
	var size_k := clampf(float(cells.size()) / 40.0, 0.5, 2.0)
	NoiseMgr.add_noise(N_ISLAND * size_k, c, "dig")
	fx.append(Vector3(c.x, c.y, size_k))
	_wake(lo - 1, hi + 1)
	_check_islands = true                                        # oparła się o coś, co też może wisieć
	SessionLog.event("dig_fall", {"zone": String(name), "cells": cells.size(), "drop": int(isl["drop"]) * int(CELL), "pos": SessionLog.xy(c),
		"noise": roundi(NoiseMgr.level)})

## Każdy peer: delta z kroku serwera — narożniki `idx` dostają gęstość `d` i materiał `m`; przebudowa fragmentów, kafli, znajdziek (serwer
## wyrzuca odkopane osypiskiem), wyciągnięcie zasypanych postaci, efekty (`fx`: siła 0 — szmer osypiska, > 0 — upadek wyspy).
@rpc("authority", "call_local", "reliable")
func _cells_rpc(key: String, idx: PackedInt32Array, d: PackedByteArray, m: PackedByteArray, fx: PackedVector3Array) -> void:
	if key != map_key or idx.size() != d.size() or idx.size() != m.size():
		return
	var touched := {}
	var i0 := _w
	var i1 := 0
	var j0 := _h
	var j1 := 0
	for c in idx.size():
		var k := idx[c]
		if k < 0 or k >= _w * _h or _fixed[k] == 1:
			continue
		_d[k] = d[c]
		_m[k] = m[c]
		var i := k % _w
		var j := k / _w
		_touch(touched, i, j)
		i0 = mini(i0, i)
		i1 = maxi(i1, i)
		j0 = mini(j0, j)
		j1 = maxi(j1, j)
	for ci in touched:
		_rebuild(int(ci))
	if touched.is_empty():
		return
	_update_finds(Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1).grow(FIND_NEAR), Vector2.ZERO, -1)
	_update_tiles(_tile_rect(i0, i1, j0, j1))
	_unstick_players(CRUSH_STUN)
	if NoiseMgr.is_server():
		_unstick_enemies()
	var lvl := get_parent()
	for e in fx:
		var at := Vector2(e.x, e.y)
		if e.z <= 0.0:
			if _pour_fx_t <= 0.0:
				_pour_fx_t = 0.35
				Audio.play_at("collapse", at, Audio.BUS_WORLD, -16.0, 1.7)
				if lvl != null:
					Vfx.dust(lvl, at, 0.4)
		else:
			Audio.play_at("collapse", at, Audio.BUS_WORLD, -6.0 + 3.0 * e.z, 1.25)
			if lvl != null:
				Vfx.dust(lvl, at, 0.8 * e.z)
				Vfx.quake(at, 48.0 * e.z, 0.6)

# ---------------------------------------------------------------- znajdźki

## Rozmieszczenie znajdziek z ziarna strefy (i numeru odnowienia): kafle skały z danych mapy, które nie stykają się z powietrzem (także po
## skosie) i nie leżą w wierzchnim rzędzie strefy — znajdźka jest w głębi ściany, nie na wierzchu ani pod samym wejściem. Losowa kolejność
## kandydatów (Fisher-Yates z `RandomNumberGenerator` o ustalonym ziarnie), odstęp FIND_SPACING kafli, jedna na FIND_EVERY kafli skały.
func _plan_finds(solid_at: Callable) -> void:
	finds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, find_round, c0, r0, "finds"])
	var cands: Array[Vector2i] = []
	var rock_n := 0
	for ty in tiles.y:
		for tx in tiles.x:
			if _rock0[ty * tiles.x + tx] == 0:
				continue
			rock_n += 1
			if ty < 1:
				continue
			var deep := true
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var t := Vector2i(tx + ox, ty + oy)
					var inside := t.x >= 0 and t.y >= 0 and t.x < tiles.x and t.y < tiles.y
					if (inside and _rock0[t.y * tiles.x + t.x] == 0) or (not inside and not bool(solid_at.call(t.x + c0, t.y + r0))):
						deep = false
			if deep:
				cands.append(Vector2i(tx, ty))
	for k in range(cands.size() - 1, 0, -1):
		var o := rng.randi_range(0, k)
		var tmp := cands[k]
		cands[k] = cands[o]
		cands[o] = tmp
	var total := 0
	for e in FIND_KINDS:
		total += int(e[1])
	var want := mini(FIND_MAX, rock_n / FIND_EVERY)
	var taken: Array[Vector2i] = []
	for t in cands:
		if taken.size() >= want:
			break
		var ok := true
		for q in taken:
			if maxi(absi(q.x - t.x), absi(q.y - t.y)) < FIND_SPACING:
				ok = false
				break
		if not ok:
			continue
		taken.append(t)
		var i := t.x * PER_TILE + rng.randi_range(2, PER_TILE)       # narożnik we wnętrzu kafla
		var j := t.y * PER_TILE + rng.randi_range(2, PER_TILE)
		var roll := rng.randi_range(0, total - 1)
		var kind := "scrap"
		for e in FIND_KINDS:
			roll -= int(e[1])
			if roll < 0:
				kind = String(e[0])
				break
		finds.append({"i": i, "j": j, "pos": global_position + _corner_px(i, j), "kind": kind, "kind0": kind, "state": Find.BURIED})

## Każdy peer: pula strefy (Scrap) — nowe ziarno po odnowieniu (nowe miejsca, stan z gęstości bez wypadania) i drobnica w miejscach
## już wykopanych. Amunicja nie jest cenna, więc nie znika z puli.
func _apply_pool() -> void:
	if pool_key == "":
		return
	var r := Scrap.dig_round(pool_key)
	if r != find_round:
		find_round = r
		_plan_finds(_solid_at)
		for f in finds:
			f["state"] = _find_state(f)
	var taken := Scrap.dig_taken(pool_key)
	for k in finds.size():
		var f: Dictionary = finds[k]
		f["kind"] = "small" if taken.has(k) and String(f["kind0"]) != "ammo" else String(f["kind0"])

## Stan znajdźki z gęstości wokół niej: odkopana, gdy co najmniej FIND_OUT z 3 × 3 najbliższych narożników jest powietrzem; do połowy, gdy
## powietrze jest w promieniu FIND_NEAR narożników (ściana wykopu tuż przy niej); inaczej zakopana.
func _find_state(f: Dictionary) -> int:
	var fi: int = f["i"]
	var fj: int = f["j"]
	var air := 0
	for j in range(fj - 1, fj + 2):
		for i in range(fi - 1, fi + 2):
			if _d[j * _w + i] < ISO:
				air += 1
	if air >= FIND_OUT:
		return Find.OUT
	if air > 0:
		return Find.NEAR
	for j in range(maxi(0, fj - FIND_NEAR), mini(_h, fj + FIND_NEAR + 1)):
		for i in range(maxi(0, fi - FIND_NEAR), mini(_w, fi + FIND_NEAR + 1)):
			if _d[j * _w + i] < ISO and _fixed[j * _w + i] == 0:
				return Find.NEAR
	return Find.BURIED

## Po operacji kopania: przelicza znajdźki w prostokącie narożników `rc`; serwer wyrzuca te, które właśnie zostały odkopane.
func _update_finds(rc: Rect2i, from: Vector2, tool: int) -> void:
	for k in finds.size():
		var f: Dictionary = finds[k]
		if int(f["state"]) == Find.OUT or not rc.has_point(Vector2i(int(f["i"]), int(f["j"]))):
			continue
		f["state"] = _find_state(f)
		if int(f["state"]) == Find.OUT and NoiseMgr.is_server():
			_spawn_find(k, from, tool)

## Serwer: odkopana znajdźka wypada jako przedmiot (level.gd `spawn_item`). Zawartość dobiera się teraz: amunicja do broni, której drużynie
## brakuje (jak z wrogów), część broni z puli znalezisk (Scrap.pick_find), a gdy nie ma czego — złom. Nocny Dyżur: tylko amunicja.
## Wybuch odrzuca przedmiot od środka. Cenna znajdźka idzie do łupu puli (Scrap.dig_take), miejsce wykopane w puli daje drobnicę.
func _spawn_find(k: int, from: Vector2, tool: int) -> void:
	var f: Dictionary = finds[k]
	var kind := String(f["kind"])
	var item := _resolve_find(kind)
	var at: Vector2 = f["pos"] + Vector2(0, -2)
	if tool == Mats.Tool.BLAST and (at - from).length() > 0.5:
		at += (at - from).normalized() * FIND_BLAST_PUSH
	finds_out += 1
	if kind != "ammo" and kind != "small" and not NightShift.active:
		Scrap.dig_take(pool_key, k)                              # cenna: znika z puli po ekstrakcji
	var lvl := get_parent()
	if not item.is_empty() and lvl != null and lvl.has_method("spawn_item"):
		lvl.spawn_item(String(item[0]), int(item[1]), at, int(item[2]))
	SessionLog.event("dig_find", {"zone": String(name), "find": k, "kind": kind, "item": String(item[0]) if not item.is_empty() else "",
		"by": "fall" if tool < 0 else ["pick", "blade", "blast"][clampi(tool, 0, 2)], "pos": SessionLog.xy(at), "noise": roundi(NoiseMgr.level)})

## [rodzaj pickup.gd, arg, rounds] albo pusta tablica (nic — Nocny Dyżur bez potrzebnej amunicji).
func _resolve_find(kind: String) -> Array:
	if kind == "ammo" or NightShift.active:
		var w: int = Arsenal.pick_drop_weapon()
		if w >= 0:
			return ["ammo", w, maxi(1, int(Weapons.def(w).pickup_rounds * 0.5))]
		if NightShift.active:
			return []
	elif kind == "small":                                        # pusta pula: drobnica — trochę amunicji albo jeden złom
		var ws: int = Arsenal.pick_drop_weapon()
		if ws >= 0:
			return ["ammo", ws, maxi(1, int(Weapons.def(ws).pickup_rounds * 0.25))]
		return ["scrap", 0, 1] if Scrap.enabled() else []
	elif kind == "supply":
		return ["supply", Throwables.ORDER.find(Throwables.drop_kind()), -1]
	elif kind == "battery":
		return ["battery", 0, -1]
	elif kind == "part":
		var pid: String = Scrap.pick_find()
		if pid != "":
			return ["part", Scrap.part_index(pid), -1]
	return ["scrap", 0, randi_range(FIND_SCRAP.x, FIND_SCRAP.y)] if Scrap.enabled() else []

## Indeks zakopanej (nie odkopanej) znajdźki w prostokącie px świata albo -1 — dźwięk ciosu w metal.
func find_near_rect(r: Rect2) -> int:
	for k in finds.size():
		if int(finds[k]["state"]) != Find.OUT and r.has_point(finds[k]["pos"]):
			return k
	return -1

## Znajdźki jeszcze w ziemi (zakopane i odkopane do połowy) w promieniu `radius` od `from` — skaner „Sowa” (scanner_view.gd).
func buried_finds(from: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in finds:
		if int(f["state"]) != Find.OUT and (f["pos"] as Vector2).distance_to(from) <= radius:
			out.append(f)
	return out

## Punkt w powietrzu przy znajdźce odkopanej do połowy (najbliższy pusty narożnik) albo Vector2.INF — tam celuje latarka, żeby błysnęła.
func find_face(f: Dictionary) -> Vector2:
	var fi: int = f["i"]
	var fj: int = f["j"]
	var best := Vector2.INF
	var bd := INF
	for j in range(maxi(0, fj - FIND_NEAR), mini(_h, fj + FIND_NEAR + 1)):
		for i in range(maxi(0, fi - FIND_NEAR), mini(_w, fi + FIND_NEAR + 1)):
			if _d[j * _w + i] < ISO:
				var dd := float(Vector2(i - fi, j - fj).length_squared())
				if dd < bd:
					bd = dd
					best = global_position + _corner_px(i, j)
	return best

## Wejście do strefy (znak w 3D, view3d.gd `_build_dig_sign`): najniższy kafel powietrza z gruntem pod spodem tuż obok skały strefy
## z danych mapy — z boku (lewa albo prawa kolumna za strefą) albo na wierzchu. Zwraca {"wall_x": krawędź skały [px], "floor_y": grunt [px],
## "dir": +1 skała w prawo, −1 w lewo, 0 skała pod stopami} albo pusty słownik. Liczone z danych mapy, więc stałe przez całą misję.
func entrance() -> Dictionary:
	var air := func(c: int, r: int) -> bool:
		if c >= c0 and r >= r0 and c < c0 + tiles.x and r < r0 + tiles.y:
			return _rock0[(r - r0) * tiles.x + (c - c0)] == 0
		return not bool(_solid_at.call(c, r))
	var ground := func(c: int, r: int) -> bool:
		return not bool(air.call(c, r))
	var best := {}
	var best_r := -1
	for side in [-1, 1]:
		var c := c0 - 1 if side < 0 else c0 + tiles.x
		var wall_c := c0 if side < 0 else c0 + tiles.x - 1
		for r in range(r0, r0 + tiles.y):
			if r > best_r and bool(air.call(c, r)) and bool(ground.call(c, r + 1)) and solid_in_data(wall_c, r):
				best_r = r
				best = {"wall_x": float(c0 if side < 0 else c0 + tiles.x) * TILE, "floor_y": float(r + 1) * TILE, "dir": -side}
	if best.is_empty():
		for c in range(c0, c0 + tiles.x):
			if bool(air.call(c, r0 - 1)) and solid_in_data(c, r0):
				return {"wall_x": (float(c) + 0.5) * TILE, "floor_y": float(r0) * TILE, "dir": 0}
	return best

# ---------------------------------------------------------------- marching squares

## Wielokąt skały w komórce (i, j) (narożniki TL, TR, BR, BL zgodnie z ruchem wskazówek na ekranie) i odcinki konturu.
## `poly` dostaje wierzchołki wielokąta (px względem strefy), `segs` — pary punktów konturu. Zwraca maskę narożników w skale (15 = pełna).
func _cell(i: int, j: int, poly: PackedVector2Array, segs: PackedVector2Array) -> int:
	var k0 := j * _w + i
	var v0 := int(_d[k0])
	var v1 := int(_d[k0 + 1])
	var v2 := int(_d[k0 + _w + 1])
	var v3 := int(_d[k0 + _w])
	var mask := int(v0 >= ISO) | (int(v1 >= ISO) << 1) | (int(v2 >= ISO) << 2) | (int(v3 >= ISO) << 3)
	if mask == 0:
		return 0
	var base := _corner_px(i, j)
	if mask == 15:                                             # pełna komórka (najczęstsza): bez konturu
		poly.append(base)
		poly.append(base + Vector2(CELL, 0))
		poly.append(base + Vector2(CELL, CELL))
		poly.append(base + Vector2(0, CELL))
		return mask
	var v := [v0, v1, v2, v3]
	var cp := [base, base + Vector2(CELL, 0), base + Vector2(CELL, CELL), base + Vector2(0, CELL)]
	var cross := []                                            # czy wierzchołek wielokąta leży na konturze
	for k in 4:
		var n := (k + 1) % 4
		var sk := (mask >> k) & 1
		if sk == 1:
			poly.append(cp[k])
			cross.append(false)
		if sk != (mask >> n) & 1:
			var t := clampf(float(ISO - int(v[k])) / float(int(v[n]) - int(v[k])), 0.0, 1.0)
			poly.append((cp[k] as Vector2).lerp(cp[n], t))
			cross.append(true)
	var m := poly.size()
	for k in m:
		if cross[k] and cross[(k + 1) % m]:
			segs.append(poly[k])
			segs.append(poly[(k + 1) % m])
	return mask

## Materiał komórki (i, j) do koloru siatki: lewy górny narożnik, a gdy jest powietrzem — pierwszy narożnik w skale.
func _cell_mat(i: int, j: int) -> int:
	var k0 := j * _w + i
	for k in [k0, k0 + 1, k0 + _w + 1, k0 + _w]:
		if _d[k] >= ISO:
			return _m[k]
	return _m[k0]

## Kontur i kolizja jednego fragmentu.
func _rebuild(ci: int) -> void:
	var segs := PackedVector2Array()
	var poly := PackedVector2Array()
	var ix := (ci % _ccx) * CHUNK
	var jy := (ci / _ccx) * CHUNK
	for j in range(jy, mini(jy + CHUNK, _h - 1)):
		for i in range(ix, mini(ix + CHUNK, _w - 1)):
			poly.clear()
			_cell(i, j, poly, segs)
	_shapes[ci].segments = segs
	chunk_ver[ci] += 1

## Siatka 3D fragmentu `ci`: przód skały (płaski przekrój na z = `front`), ściany wykopu wzdłuż konturu do z = `back`. Współrzędne w metrach
## świata (`px` — metrów na piksel, Level3D.PX; y w 3D rośnie w górę). Pełne komórki tego samego materiału w wierszu idą jednym prostokątem.
## Kolor wierzchołka: odcień materiału (dig_materials.gd `tint`), na ścianach wykopu ściemniony w głąb (tania okluzja „wnętrza jaskini”).
func chunk_mesh(ci: int, px: float, front: float, back: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var poly := PackedVector2Array()
	var segs := PackedVector2Array()
	var ix := (ci % _ccx) * CHUNK
	var jy := (ci / _ccx) * CHUNK
	var gp := global_position
	var i_end := mini(ix + CHUNK, _w - 2)                      # komórki pierścienia pomijamy: tam jest zwykła mapa
	for j in range(maxi(jy, 1), mini(jy + CHUNK, _h - 2)):
		var run := -1                                          # początek pasa pełnych komórek
		var run_mat := -1
		for i in range(maxi(ix, 1), i_end + 1):
			poly.clear()
			segs.clear()
			var mask := 0 if i == i_end else _cell(i, j, poly, segs)
			var cm := _cell_mat(i, j) if mask != 0 else -1
			if run >= 0 and (mask != 15 or cm != run_mat):       # zamknij pas pełnych komórek [run, i)
				var a := (gp + _corner_px(run, j)) * px
				var b := (gp + _corner_px(i, j + 1)) * px
				_quad(verts, norms, cols, Mats.tint(run_mat), Vector3(a.x, -a.y, front), Vector3(b.x, -a.y, front), Vector3(b.x, -b.y, front), Vector3(a.x, -b.y, front))
				run = -1
			if mask == 15:
				if run < 0:
					run = i
					run_mat = cm
				continue
			if poly.size() < 3:
				continue
			var tint := Mats.tint(cm)
			var deep := tint.darkened(0.65)
			var cen := Vector2.ZERO
			for q in poly:
				cen += q
			cen /= float(poly.size())
			var p0 := (gp + poly[0]) * px
			for k in range(1, poly.size() - 1):
				var p1 := (gp + poly[k]) * px
				var p2 := (gp + poly[k + 1]) * px
				verts.append(Vector3(p0.x, -p0.y, front))      # Godot: przód = zgodnie z ruchem wskazówek; odbicie osi y tego nie zmienia
				verts.append(Vector3(p1.x, -p1.y, front))      # (wielokąt z ekranu idzie zgodnie z ruchem wskazówek i tak zostaje w 3D)
				verts.append(Vector3(p2.x, -p2.y, front))
				for _q in 3:
					norms.append(Vector3(0, 0, 1))
					cols.append(tint)
			_walls(verts, norms, cols, segs, cen, gp, px, front, back, tint, deep)
	# komórki pierścienia przy powietrzu mapy (strefa na końcu sali, nie w litej skale): kontur leży dokładnie na brzegu strefy, w komórce
	# pierścienia, której nie wypełniamy (tam jest zwykła mapa) — bez tej ściany przez bok strefy widać tło (uwaga z gry 2026-11-08)
	for j in range(jy, mini(jy + CHUNK, _h - 1)):
		for i in range(ix, mini(ix + CHUNK, _w - 1)):
			if i != 0 and j != 0 and i != _w - 2 and j != _h - 2:
				continue
			var k0 := j * _w + i
			var air := true
			for k in [k0, k0 + 1, k0 + _w + 1, k0 + _w]:
				if _fixed[k] == 1 and _d[k] != 0:
					air = false
			if not air:
				continue
			poly.clear()
			segs.clear()
			var mask := _cell(i, j, poly, segs)
			if mask == 0 or mask == 15 or segs.is_empty():
				continue
			var cm := _cell_mat(i, j)
			var cen := Vector2.ZERO
			for q in poly:
				cen += q
			cen /= float(poly.size())
			# kontur na samym brzegu: wielokąt bez pola — środek skały leży po stronie strefy
			cen = cen.lerp(_corner_px(nx / 2 + 1, ny / 2 + 1), 0.01)
			_walls(verts, norms, cols, segs, cen, gp, px, front, back, Mats.tint(cm), Mats.tint(cm).darkened(0.65))
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Ściany konturu (odcinki `segs` komórki) od przodu do tyłu strefy; normalna od środka skały `cen` na zewnątrz (w płaszczyźnie xy).
func _walls(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, segs: PackedVector2Array, cen: Vector2, gp: Vector2, px: float, front: float, back: float, tint: Color, deep: Color) -> void:
	for k in range(0, segs.size(), 2):
		var e := segs[k + 1] - segs[k]
		var n2 := Vector2(-e.y, e.x).normalized()
		if n2.dot((segs[k] + segs[k + 1]) * 0.5 - cen) < 0.0:
			n2 = -n2
		var n3 := Vector3(n2.x, -n2.y, 0.0)
		var a2 := (gp + segs[k]) * px
		var b2 := (gp + segs[k + 1]) * px
		var af := Vector3(a2.x, -a2.y, front)
		var bf := Vector3(b2.x, -b2.y, front)
		var ab := Vector3(a2.x, -a2.y, back)
		var bb := Vector3(b2.x, -b2.y, back)
		if (bf - af).cross(bb - af).dot(n3) > 0.0:     # przód (zgodnie z ruchem wskazówek) od strony normalnej
			var t := af
			af = bf
			bf = t
			t = ab
			ab = bb
			bb = t
		verts.append(af)
		verts.append(bf)
		verts.append(bb)
		verts.append(af)
		verts.append(bb)
		verts.append(ab)
		for c in [tint, tint, deep, tint, deep, deep]:
			norms.append(n3)
			cols.append(c)

## Prostokąt przodu skały (a, b, c, d zgodnie z ruchem wskazówek na ekranie i w 3D), normalna +z.
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, col: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		verts.append(p)
		norms.append(Vector3(0, 0, 1))
		cols.append(col)

func chunk_count() -> int:
	return _ccx * _ccy
