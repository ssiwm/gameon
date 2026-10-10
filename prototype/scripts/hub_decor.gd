extends Node2D
## Meble w tle kryjówki (ATMOSPHERE_PLAN.md, F7): regały, stoły z krzesłami i stołkiem, szafki, prycze — sprite'y HD z potoku przedmiotów
## (art/items/, tools/concept/items_proc_bake.py) rozmieszczone w odstępach między znacznikami funkcji (stojaki, warsztat,
## tablica, radio, strzelnica; przy tablicach szerszy margines, w zbrojowni zostają same stojaki). Kosmetyka: bez kolizji i interakcji; reagują na światła 2D (mapa normalnych). Tylko przy grafice HD przedmiotów.

const ItemsHd := preload("res://scripts/items_hd.gd")

const MARKER_MARGIN := 1.0            ## domyślny odstęp meblowej grupy od znacznika funkcji (kafle)
const MIN_FREE := 3.0                 ## najmniejsza wolna szerokość, w której coś stawiamy (kafle)
const CLUSTER_SPAN := 6.0             ## jedna grupa na tyle kafli wolnej szerokości (szerszy odstęp dostaje kilka)
## Układy grup (powtarzane cyklicznie, dobierane do dostępnej szerokości): [połowa szerokości w kaflach,
## [[nazwa, przesunięcie w kaflach od środka grupy, odbicie poziome], …]]
const LAYOUTS := [
	[1.0, [["shelf", 0.0, false]]],
	[2.1, [["table", 0.0, false], ["chair", 1.8, true]]],
	[0.9, [["locker", -0.5, false], ["locker", 0.5, false]]],
	[2.0, [["cot", 0.0, false], ["stool", 1.7, true]]],
	[1.8, [["shelf", 0.6, true], ["chair", -1.4, false]]],
	[1.6, [["table", 0.0, true], ["stool", -1.5, false]]],
]

## `occupied_cols` — kolumny znaczników funkcji, `margins` — kolumna → odstęp (kafle) dla szerokich obiektów (tablice),
## `quiet_cols` — znaczniki, między którymi nie stawiamy mebli (stojaki), `x0`/`x1` — pierwsza i ostatnia kolumna podłogi.
func setup(occupied_cols: Array, margins: Dictionary, quiet_cols: Array, x0: int, x1: int, floor_y: float, tile: float) -> void:
	z_index = 0
	if not ItemsHd.enabled():
		return
	var marks: Array = [x0 - 1, x1 + 1]
	for c in occupied_cols:
		if int(c) >= x0 and int(c) <= x1 and not marks.has(int(c)):
			marks.append(int(c))
	marks.sort()
	var layout_i := 0
	for i in range(marks.size() - 1):
		var a: int = marks[i]
		var b: int = marks[i + 1]
		if quiet_cols.has(a) and quiet_cols.has(b):
			continue
		var ma := float(margins.get(a, MARKER_MARGIN)) if i > 0 else 0.0
		var mb := float(margins.get(b, MARKER_MARGIN)) if i < marks.size() - 2 else 0.0
		var free := float(b - a) - ma - mb
		if free < MIN_FREE:
			continue
		var n := maxi(1, int(round(free / CLUSTER_SPAN)))
		var half := free / float(n) * 0.5
		for k in n:
			var centre := float(a) + ma + free * (float(k) + 0.5) / float(n)
			for t in LAYOUTS.size():
				var lay: Array = LAYOUTS[(layout_i + t) % LAYOUTS.size()]
				if float(lay[0]) <= half + 0.01:
					_place(lay[1], centre, floor_y, tile)
					layout_i += t + 1
					break

func _place(items: Array, centre_col: float, floor_y: float, tile: float) -> void:
	for it in items:
		var name: String = it[0]
		if not ItemsHd.has(name):
			continue
		var holder := Node2D.new()
		holder.position = Vector2((centre_col + float(it[1])) * tile + tile * 0.5, floor_y)
		add_child(holder)
		var sp := ItemsHd.make(name, holder, 1.0)
		if bool(it[2]):
			holder.scale.x = -1.0
		sp.modulate = Color(0.78, 0.78, 0.78)       # tło sceny: odrobinę przyciemnione względem elementów funkcjonalnych
