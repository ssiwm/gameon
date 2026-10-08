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

func build(c: int, r: int, is_solid: Callable, is_platform: Callable) -> void:
	cols = c
	rows = r
	_solid = is_solid
	_platform = is_platform
	clear()
	_edge.clear()
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

func _id(c: int, r: int) -> int:
	return r * cols + c

func cell_of_id(id: int) -> Vector2i:
	return Vector2i(id % cols, id / cols)

func _in(c: int, r: int) -> bool:
	return c >= 0 and c < cols and r >= 0 and r < rows

func _free(c: int, r: int) -> bool:
	return c >= 0 and c < cols and r >= 0 and r < rows and not _solid.call(c, r)

func _floor_at(c: int, r: int) -> bool:
	return _solid.call(c, r + 1) or _platform.call(c, r + 1)

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
	if not _platform.call(c, r + 1):
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
