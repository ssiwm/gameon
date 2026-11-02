extends AStar2D
## Nawigacja platformówki na siatce mapy (GDD §16.0 pkt 5) — dla bota i Stalkera.
##
## Węzeł = kafel, na którym da się STAĆ: sam kafel i ten nad nim są wolne
## (postać ma 17 px), a pod spodem jest podłoga — bryła albo kładka.
## Pozycja węzła = punkt na podłodze (środek kafla w poziomie, dół kafla).
##
## Krawędzie (jednokierunkowe, z typem):
##   WALK  sąsiedni kafel na tym samym poziomie
##   JUMP  do 2 kafli w górę (skok 42 px) lub przez przepaść; przez kładki
##         można przelecieć od spodu, przez bryły nie
##   FALL  zejście z krawędzi — spada się do pierwszej podłogi w kolumnie obok
##   DROP  zeskok przez kładkę (dół + skok) do pierwszej podłogi pod nią
##
## Koszt: odległość × mnożnik typu — skoki i zeskoki są „droższe" od chodzenia,
## więc A* wybiera je tylko wtedy, gdy się opłaca.

enum Edge { WALK, JUMP, FALL, DROP }

const TILE := 16
const COST := {Edge.WALK: 1.0, Edge.JUMP: 1.6, Edge.FALL: 1.2, Edge.DROP: 1.3}
const JUMP_UP := 2          ## kafle w górę (skok sięga 42 px = 2,6 kafla)
const UP_SIDE := 2          ## kafle w bok przy skoku w górę
const JUMP_SIDE := 3        ## kafle w bok przy skoku na tym samym poziomie
const GAP_SIDE := 4         ## kafle w bok przy skoku w dół przez przepaść

var cols := 0
var rows := 0
var _edge := {}             ## (from << 20) | to  ->  Edge

var _solid: Callable        ## (c, r) -> bool
var _platform: Callable     ## (c, r) -> bool
var _cell := PackedByteArray()   ## kopia `_solid` / `_platform` na kafel (bit 1 — bryła, bit 2 — kładka): sprawdzenia w pętlach bez wywołań `Callable`

func build(c: int, r: int, is_solid: Callable, is_platform: Callable) -> void:
	cols = c
	rows = r
	_solid = is_solid
	_platform = is_platform
	clear()
	_edge.clear()
	_cell.resize(cols * rows)
	_cache_cells(Rect2i(0, 0, cols, rows))
	for rr in rows:
		for cc in cols:
			if standable(cc, rr):
				add_point(_id(cc, rr), cell_floor(Vector2i(cc, rr)))
	for rr in rows:
		for cc in cols:
			if not has_point(_id(cc, rr)):
				continue
			_link_walk(cc, rr)
			_link_fall(cc, rr)
			_link_drop(cc, rr)
			_link_jumps(cc, rr)

## Margines lokalnej przebudowy wokół zmienionych kafli: kolumny — najdalszy skok w bok (GAP_SIDE) + 1, wiersze — skok w górę
## z zapasem na szczyt toru (`_jump_clear` sprawdza 2 kafle nad niższym z punktów) i podłogę / głowę celu.
const REBUILD_MARGIN := Vector2i(GAP_SIDE + 1, JUMP_UP + 3)

## Przebudowa grafu po zmianie kafli w `rect` (rozbita ściana, zniszczalny obiekt) — wynik taki sam jak pełne `build`, ale liczony
## tylko tam, gdzie zmiana może coś ruszyć. Węzły powstają / znikają w kolumnach `rect` o wiersz nad i pod nim (`standable` patrzy na
## kafel, głowę i podłogę). Krawędzie wychodzące liczymy od nowa z każdego węzła, którego krawędź może dotknąć zmienionego kafla albo
## węzła: w prostokącie powiększonym o REBUILD_MARGIN (chodzenie, skoki) i w pasie kolumn `rect` ± 1 nad nim do samej góry
## (zejście z krawędzi i zeskok przez kładkę spadają w kolumnie dowolnie nisko). Każde źródło krawędzi do węzła w `rect` leży w tym zbiorze,
## więc znikający węzeł nie zostawia wpisów w `_edge`, a nowy dostaje wszystkie krawędzie wchodzące. Pas nad prostokątem leży ponad zasięgiem
## chodzenia i skoków (cel skoku najwyżej 2 kafle niżej), więc tam liczymy od nowa tylko zejścia i zeskoki.
func rebuild_region(rect: Rect2i) -> void:
	if cols == 0 or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var box := rect.grow_individual(REBUILD_MARGIN.x, REBUILD_MARGIN.y, REBUILD_MARGIN.x, REBUILD_MARGIN.y)
	var band := Rect2i(rect.position.x - 1, 0, rect.size.x + 2, rect.end.y + 1)
	var all := Rect2i(0, 0, cols, rows)
	_cache_cells(rect.intersection(all))
	box = box.intersection(all)
	band = band.intersection(all)
	var src: Array[int] = []
	for rr in range(box.position.y, box.end.y):
		for cc in range(box.position.x, box.end.x):
			src.append(_id(cc, rr))
	var fall_src: Array[int] = []
	for rr in range(band.position.y, band.end.y):
		for cc in range(band.position.x, band.end.x):
			if not box.has_point(Vector2i(cc, rr)) and has_point(_id(cc, rr)):
				fall_src.append(_id(cc, rr))
	# 1. stare krawędzie wychodzące ze źródeł
	for id in src:
		if not has_point(id):
			continue
		for nb in get_point_connections(id):
			_edge.erase((id << 20) | nb)
			disconnect_points(id, nb, false)
	for id in fall_src:
		for nb in get_point_connections(id):
			var key := (id << 20) | nb
			if _edge.get(key, Edge.WALK) == Edge.FALL or _edge.get(key, Edge.WALK) == Edge.DROP:
				_edge.erase(key)
				disconnect_points(id, nb, false)
	# 2. węzły, które mogły się pojawić albo zniknąć
	var exist := Rect2i(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y + 2).intersection(all)
	for rr in range(exist.position.y, exist.end.y):
		for cc in range(exist.position.x, exist.end.x):
			var id := _id(cc, rr)
			var ok := standable(cc, rr)
			if ok and not has_point(id):
				add_point(id, cell_floor(Vector2i(cc, rr)))
			elif not ok and has_point(id):
				remove_point(id)
	# 3. krawędzie od nowa, w tej samej kolejności co w `build` (przy dwóch drogach do tego samego węzła zostaje tańsza)
	for id in src:
		if not has_point(id):
			continue
		var cc := id % cols
		var rr := id / cols
		_link_walk(cc, rr)
		_link_fall(cc, rr)
		_link_drop(cc, rr)
		_link_jumps(cc, rr)
	for id in fall_src:
		_link_fall(id % cols, id / cols)
		_link_drop(id % cols, id / cols)

func _cache_cells(rc: Rect2i) -> void:
	for rr in range(rc.position.y, rc.end.y):
		for cc in range(rc.position.x, rc.end.x):
			_cell[rr * cols + cc] = (1 if _solid.call(cc, rr) else 0) | (2 if _platform.call(cc, rr) else 0)

func _id(c: int, r: int) -> int:
	return r * cols + c

func cell_of_id(id: int) -> Vector2i:
	return Vector2i(id % cols, id / cols)

func _in(c: int, r: int) -> bool:
	return c >= 0 and c < cols and r >= 0 and r < rows

func _free(c: int, r: int) -> bool:
	return c >= 0 and c < cols and r >= 0 and r < rows and _cell[r * cols + c] & 1 == 0

func _floor_at(c: int, r: int) -> bool:
	return _cell[(r + 1) * cols + c] != 0

func standable(c: int, r: int) -> bool:
	return _free(c, r) and _free(c, r - 1) and r + 1 < rows and _floor_at(c, r)

## Punkt na podłodze danego kafla (stopy postaci).
func cell_floor(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)

func _connect(a: Vector2i, b: Vector2i, kind: int) -> void:
	var ia := _id(a.x, a.y)
	var ib := _id(b.x, b.y)
	if ia == ib or not has_point(ib):
		return
	var key := (ia << 20) | ib
	# ten sam odcinek dwoma sposobami — zostaje tańszy typ
	if _edge.has(key) and COST[_edge[key]] <= COST[kind]:
		return
	_edge[key] = kind
	connect_points(ia, ib, false)

func edge_kind(from_id: int, to_id: int) -> int:
	return _edge.get((from_id << 20) | to_id, Edge.WALK)

var _no_jump := false       ## bieżące wyszukiwanie dla kogoś, kto nie skacze: skoki są bardzo drogie (trasa na piechotę, jeśli istnieje)
const NO_JUMP_PENALTY := 60.0

func _compute_cost(from_id: int, to_id: int) -> float:
	var k := edge_kind(from_id, to_id)
	var c: float = get_point_position(from_id).distance_to(get_point_position(to_id)) * float(COST[k])
	return c * NO_JUMP_PENALTY if (_no_jump and k == Edge.JUMP) else c

func _estimate_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id))

func _link_walk(c: int, r: int) -> void:
	for dc in [-1, 1]:
		if standable(c + dc, r):
			_connect(Vector2i(c, r), Vector2i(c + dc, r), Edge.WALK)

## Zejście z krawędzi: kolumna obok jest wolna, ale bez podłogi — spadamy.
func _link_fall(c: int, r: int) -> void:
	for dc in [-1, 1]:
		var cc: int = c + dc
		if not (_free(cc, r) and _free(cc, r - 1)) or standable(cc, r):
			continue
		var rr := r + 1
		while rr < rows and _free(cc, rr):
			if standable(cc, rr):
				_connect(Vector2i(c, r), Vector2i(cc, rr), Edge.FALL)
				break
			rr += 1

## Zeskok przez kładkę pod stopami.
func _link_drop(c: int, r: int) -> void:
	if _cell[(r + 1) * cols + c] & 2 == 0:
		return
	var rr := r + 2
	while rr < rows and _free(c, rr):
		if standable(c, rr):
			_connect(Vector2i(c, r), Vector2i(c, rr), Edge.DROP)
			return
		rr += 1

## Skoki: w górę (do JUMP_UP kafli, także pionowo przez kładkę), w bok na tym
## samym poziomie przez przepaść i w dół przez przepaść. Tor sprawdzamy
## zgrubnie: wolna przestrzeń nad startem na wysokość skoku i wolny „korytarz"
## na wysokości lądowania nad pośrednimi kolumnami. Bryły blokują, kładki nie.
func _link_jumps(c: int, r: int) -> void:
	for dr in range(-JUMP_UP, 3):
		# zasięg w bok zależy od czasu lotu: w górę ~0,45 s (≈43 px przy 95 px/s),
		# na tym samym poziomie ~0,6 s, w dół dłużej
		var side := GAP_SIDE if dr > 0 else (JUMP_SIDE if dr == 0 else UP_SIDE)
		for dc in range(-side, side + 1):
			if dr == 0 and absi(dc) <= 1:
				continue          # sąsiad = chodzenie
			if dc == 0 and dr >= 0:
				continue
			var tc: int = c + dc
			var tr: int = r + dr
			if not standable(tc, tr):
				continue
			if not _jump_clear(c, r, tc, tr):
				continue
			_connect(Vector2i(c, r), Vector2i(tc, tr), Edge.JUMP)

func _jump_clear(c: int, r: int, tc: int, tr: int) -> bool:
	# wysokość szczytu: 1 kafel nad wyższym z punktów (start / cel)
	var peak := mini(r, tr) - 2
	# pion nad startem do szczytu
	for rr in range(peak, r):
		if not _free(c, rr):
			return false
	# korytarz nad trasą (kolumny pośrednie i cel) na wysokości szczytu..lądowania
	var step := 1 if tc > c else -1
	var cc := c
	while cc != tc:
		cc += step
		for rr in range(peak, tr + 1 if cc == tc else mini(r, tr)):
			if not _free(cc, rr):
				return false
	return true

## Najbliższy węzeł dla pozycji (stopy) — najpierw kafel stóp, potem w dół
## (postać w powietrzu spadnie) i na boki.
func nearest_id(pos: Vector2) -> int:
	var c := int(floor(pos.x / TILE))
	var r := int(floor((pos.y - 1.0) / TILE))
	for dr in range(0, 8):
		for dc in [0, -1, 1, -2, 2]:
			if _in(c + dc, r + dr) and has_point(_id(c + dc, r + dr)):
				return _id(c + dc, r + dr)
	for dr in range(1, 3):
		for dc in [0, -1, 1]:
			if _in(c + dc, r - dr) and has_point(_id(c + dc, r - dr)):
				return _id(c + dc, r - dr)
	return get_closest_point(pos)

## Liczniki do pomiarów (main.gd `_perf_run`): ile razy i jak długo liczono A* od ostatniego zerowania.
static var stat_calls := 0
static var stat_usec := 0

## Ścieżka jako lista kroków {pos, kind, id}; pierwszy krok = start.
func find_path(from: Vector2, to: Vector2, can_jump := true) -> Array:
	var t0 := Time.get_ticks_usec()
	_no_jump = not can_jump
	var res := _find_path(from, to)
	_no_jump = false
	stat_calls += 1
	stat_usec += Time.get_ticks_usec() - t0
	return res

func _find_path(from: Vector2, to: Vector2) -> Array:
	var a := nearest_id(from)
	var b := nearest_id(to)
	if a < 0 or b < 0:
		return []
	var ids := get_id_path(a, b)
	var out := []
	for i in ids.size():
		var kind := Edge.WALK if i == 0 else edge_kind(ids[i - 1], ids[i])
		out.append({"pos": get_point_position(ids[i]), "kind": kind, "id": ids[i]})
	return out
