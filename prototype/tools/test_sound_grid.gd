extends SceneTree
## Test siatki propagacji dźwięku (scripts/sound_grid.gd) na małej mapie ASCII — bez gry i bez autoloadów.
##   godot --headless --path prototype -s tools/test_sound_grid.gd     → ostatni wiersz: [SOUNDGRID] PASS / FAIL
##
## Mapa: dwa pokoje rozdzielone ścianą (kolumna 9) z jednym przejściem na dole (wiersz 4) i zamknięta komora po prawej.

const SoundGrid := preload("res://scripts/sound_grid.gd")

const MAP := [
	"########################",
	"#........#.........#...#",
	"#........#.........#...#",
	"#........#.........#...#",
	"#..................#...#",
	"########################",
]

var _fails := 0
var _map: Array = []


func _init() -> void:
	_map = MAP.duplicate()
	var g := SoundGrid.new()
	g.build((_map[0] as String).length(), _map.size(), _solid)
	var t := float(SoundGrid.TILE)

	# 1. Ten sam pokój: droga prawie prosta, róg = samo źródło (słuchacz je widzi).
	var a := g.center(Vector2i(2, 1))
	var b := g.center(Vector2i(7, 3))
	var r := g.route(a, b)
	_check("ten sam pokój: droga istnieje", not r.is_empty())
	if not r.is_empty():
		_check("ten sam pokój: długość ≈ odległość (do 10%)", absf(float(r[0]) - a.distance_to(b)) <= a.distance_to(b) * 0.10, "%.0f vs %.0f" % [r[0], a.distance_to(b)])
		_check("ten sam pokój: róg to źródło", (r[1] as Vector2).distance_to(a) < 1.0)

	# 2. Przez ścianę: droga prowadzi dołem przez przejście, a róg leży przy przejściu — poniżej i na lewo od słuchacza.
	var src := g.center(Vector2i(3, 1))
	var ear := g.center(Vector2i(15, 1))
	r = g.route(src, ear)
	_check("za ścianą: droga istnieje", not r.is_empty())
	if not r.is_empty():
		var gap := g.center(Vector2i(9, 4))
		var via := src.distance_to(gap) + gap.distance_to(ear)
		_check("za ścianą: droga dłuższa niż na wprost", float(r[0]) > src.distance_to(ear) + t)
		_check("za ścianą: długość ≈ droga przez przejście (do 12%)", absf(float(r[0]) - via) <= via * 0.12, "%.0f vs %.0f" % [r[0], via])
		var corner: Vector2 = r[1]
		_check("za ścianą: róg przy przejściu, nie za ścianą", corner.x >= 8.0 * t and corner.x <= 11.0 * t and corner.y >= 3.0 * t, str(corner / t))
		_check("za ścianą: róg poniżej słuchacza i po stronie źródła", corner.y > ear.y and corner.x < ear.x)

	# 3. Zamknięta komora: brak drogi.
	_check("zamknięta komora: brak drogi", g.route(g.center(Vector2i(21, 2)), ear).is_empty())

	# 4. Zmiana mapy: zamurowane przejście odcina drogę, otwarte ją przywraca; wersja siatki rośnie.
	var v0: int = g.version
	_put(9, 4, "#")
	g.refresh(Rect2i(9, 4, 1, 1), _solid)
	_check("zamurowane przejście: brak drogi", g.route(src, ear).is_empty())
	_put(9, 4, ".")
	g.refresh(Rect2i(9, 4, 1, 1), _solid)
	_check("otwarte przejście: droga wraca", not g.route(src, ear).is_empty())
	_check("wersja siatki rośnie po zmianie", g.version == v0 + 2)

	# 5. Punkt w bryle (trafienie w ścianę) przyciąga się do sąsiedniej wolnej komórki; punkt daleko poza mapą — brak drogi.
	_check("źródło w ścianie: droga z sąsiedniej komórki", not g.route(g.center(Vector2i(0, 2)), b).is_empty())
	_check("źródło poza mapą: brak drogi", g.route(Vector2(-500.0, -500.0), b).is_empty())

	print("[SOUNDGRID] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _solid(c: int, r: int) -> bool:
	if r < 0 or r >= _map.size() or c < 0 or c >= (_map[0] as String).length():
		return true
	return (_map[r] as String)[c] == "#"


func _put(c: int, r: int, ch: String) -> void:
	var row: String = _map[r]
	_map[r] = row.substr(0, c) + ch + row.substr(c + 1)


func _check(what: String, ok: bool, info := "") -> void:
	print("  %s %s%s" % ["ok  " if ok else "FAIL", what, ("  (%s)" % info) if info != "" else ""])
	if not ok:
		_fails += 1
