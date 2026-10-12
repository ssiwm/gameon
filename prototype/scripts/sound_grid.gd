extends RefCounted
## Siatka propagacji dźwięku po mapie (AUDIO_PLAN.md, F6) — własność poziomu, tak jak graf `nav`.
##
## Dźwięk zza ściany nie dochodzi „na wprost": idzie wolnymi kaflami do najbliższego przejścia
## i dopiero stamtąd do słuchacza. `route()` zwraca długość tej drogi i punkt, z którego dźwięk
## wychodzi w pole widzenia słuchacza (ostatni róg) — AudioDirector stawia tam pozorne źródło.
##
## Komórka = kafel mapy. Bryły blokują, kładki (jednokierunkowe platformy) nie — są za cienkie,
## żeby zatrzymać dźwięk. Ruch po skosie tylko, gdy oba sąsiednie kafle są wolne (dźwięk nie
## przeciska się przez styk narożników). Wyszukiwanie robi natywny AStarGrid2D.

const TILE := 16
## Ile kafli wokół szukać wolnej komórki, gdy punkt wypada w bryle (trafienie w ścianę, kamera w murze).
const SNAP_RADIUS := 2

## Rośnie przy każdej zmianie siatki (zawał, rozbita ściana) — pamięć podręczna dróg u słuchacza ją sprawdza.
var version := 0

var _astar := AStarGrid2D.new()
var _cols := 0
var _rows := 0


## Buduje siatkę z mapy `cols` × `rows`; `is_solid.call(c, r)` mówi, czy kafel jest bryłą.
func build(cols: int, rows: int, is_solid: Callable) -> void:
	_cols = cols
	_rows = rows
	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.cell_size = Vector2(TILE, TILE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()                       # czyści stan punktów — bryły ustawiamy dopiero po tym
	refresh(Rect2i(0, 0, cols, rows), is_solid)


## Odświeża fragment siatki po zmianie mapy (prostokąt w kaflach).
func refresh(rc: Rect2i, is_solid: Callable) -> void:
	for r in range(maxi(0, rc.position.y), mini(_rows, rc.end.y)):
		for c in range(maxi(0, rc.position.x), mini(_cols, rc.end.x)):
			_astar.set_point_solid(Vector2i(c, r), bool(is_solid.call(c, r)))
	version += 1


## Komórka zawierająca punkt [px, układ poziomu].
func cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


## Środek komórki [px, układ poziomu].
func center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


## Droga dźwięku ze źródła `from` do słuchacza `to` [px, układ poziomu].
## Zwraca [długość_px: float, róg: Vector2] albo [] — gdy drogi nie ma (zamknięte pomieszczenie, punkt poza mapą).
## `róg` to najdalszy od słuchacza punkt drogi, który słuchacz jeszcze „widzi": stamtąd dźwięk do niego dociera.
func route(from: Vector2, to: Vector2) -> Array:
	var src := _free_cell(cell(from))
	var ear := _free_cell(cell(to))
	if src.x < 0 or ear.x < 0:
		return []
	var ids := _astar.get_id_path(ear, src)        # od słuchacza: rogu szukamy od jego strony
	if ids.is_empty():
		return []
	var length := 0.0
	for i in range(1, ids.size()):
		length += Vector2(ids[i] - ids[i - 1]).length()
	var corner := ear
	for i in range(1, ids.size()):
		if not _los(ear, ids[i]):
			break
		corner = ids[i]
	return [length * TILE, center(corner)]


## Czy odcinek między środkami komórek nie przecina bryły (próbkowanie co pół kafla).
func _los(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var steps := maxi(1, ceili(pa.distance_to(pb) * 2.0))
	for i in range(1, steps):
		var p := pa.lerp(pb, float(i) / float(steps))
		if _astar.is_point_solid(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true


## Komórka `c`, a gdy jest bryłą albo poza mapą — najbliższa wolna w promieniu SNAP_RADIUS; (-1, -1), gdy brak.
func _free_cell(c: Vector2i) -> Vector2i:
	if _open(c):
		return c
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
		for dx in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
			var n := c + Vector2i(dx, dy)
			var dd := float(dx * dx + dy * dy)
			if dd < best_d and _open(n):
				best = n
				best_d = dd
	return best


func _open(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cols and c.y < _rows and not _astar.is_point_solid(c)
