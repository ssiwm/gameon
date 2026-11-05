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

const Mats := preload("res://scripts/dig_materials.gd")

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
	_open.resize(tiles.x * tiles.y)
	_rock0.resize(tiles.x * tiles.y)
	for ty in tiles.y:
		for tx in tiles.x:
			_open[ty * tiles.x + tx] = 1 if _tile_clear(tx, ty) else 0
			_rock0[ty * tiles.x + tx] = 1 if bool(zone_solid.call(tx + c0, ty + r0)) else 0
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
## w prostokącie wyrwy jest skała, którą to narzędzie bierze. Zwraca {"at": punkt na pył i dźwięk, "mat": materiał} albo pusty słownik.
func melee_dig(space: PhysicsDirectSpaceState2D, origin: Vector2, dir: Vector2, reach: float, tool: int) -> Dictionary:
	var r := cut_rect(origin, dir)
	var mat := _rock_in(r, tool)
	if mat < 0:
		return {}
	var at := r.get_center()
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, origin + dir * reach, LAYER_WORLD))
	if not hit.is_empty() and hit["collider"] is Node and (hit["collider"] as Node).get_parent() == self:
		at = hit["position"]
	var key := Mats.key_of(mat)
	NoiseMgr.add_noise(N_DIG * float(Mats.MATS[key]["noise"]) * (BLADE_NOISE if tool == Mats.Tool.BLADE else 1.0), at, "dig")
	_send(r.get_center(), r.size * 0.5, 0.0, tool)
	return {"at": at, "mat": key}

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
			for oy: int in [-1, 0]:                            # narożnik należy do czterech komórek
				for ox: int in [-1, 0]:
					var ci := i + ox
					var cj := j + oy
					if ci >= 0 and cj >= 0 and ci < _w - 1 and cj < _h - 1:
						touched[(cj / CHUNK) * _ccx + (ci / CHUNK)] = true
	var t0 := Time.get_ticks_usec()
	for ci in touched:
		_rebuild(int(ci))
	rebuild_usec = Time.get_ticks_usec() - t0
	if not touched.is_empty():
		_update_tiles(Rect2i(floori(float(i0 - 1) / PER_TILE) - 1, floori(float(j0 - 1) / PER_TILE) - 1,
			(i1 - i0) / PER_TILE + 3, (j1 - j0) / PER_TILE + 3))

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

## Gęstość strefy (skompresowana) — pusta, gdy strefa jest jak w danych mapy.
func state() -> PackedByteArray:
	if _d == _d0:
		return PackedByteArray()
	return _d.compress(FileAccess.COMPRESSION_ZSTD)

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
	var d := _d0.duplicate() if s.is_empty() else s.decompress(_w * _h, FileAccess.COMPRESSION_ZSTD)
	if d.size() != _w * _h:
		push_warning("dig_zone: zły rozmiar stanu %s (%d zamiast %d)" % [name, d.size(), _w * _h])
		return
	if d == _d:
		return
	_d = d
	digs = 0 if s.is_empty() else maxi(digs, 1)
	for ci in _ccx * _ccy:
		_rebuild(ci)
	_update_tiles(Rect2i(0, 0, tiles.x, tiles.y))
	_unstick_players()

## Po zasypaniu wykopu (reset): gracz tego peera, który stoi w skale, wychodzi na wierzch strefy nad sobą — jak `_push_players_out` przy
## odbudowanej ścianie (level.gd). Ruch postaci należy do właściciela, więc każdy peer przesuwa tylko swoje.
func _unstick_players() -> void:
	var rc := rect_px()
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion() or not p.is_multiplayer_authority():
			continue
		var gp: Vector2 = p.global_position
		if gp.x < rc.position.x or gp.x > rc.end.x or not (solid_at_px(gp + Vector2(0, -10)) or solid_at_px(gp + Vector2(0, -2))):
			continue
		p.global_position = Vector2(gp.x, rc.position.y - 0.5)
		p.velocity = Vector2.ZERO

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
			for k in range(0, segs.size(), 2):
				# normalna ściany: od środka skały w komórce na zewnątrz (w płaszczyźnie xy)
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

## Prostokąt przodu skały (a, b, c, d zgodnie z ruchem wskazówek na ekranie i w 3D), normalna +z.
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, col: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		verts.append(p)
		norms.append(Vector3(0, 0, 1))
		cols.append(col)

func chunk_count() -> int:
	return _ccx * _ccy
