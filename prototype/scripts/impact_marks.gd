extends RefCounted
## Ślady trafień w świecie 3D (IMPACT_MARKS_PLAN.md E1–E2): wybór tekstury, rozmiar, wydłużenie przy kącie padania, scalanie bliskich
## śladów i punkty osmalenia wybuchu. Same funkcje bez stanu sceny — dekale stawia `view3d.gd` (`mark_hit`, `mark_scorch`), a test
## headless (`tools/test_impact_marks.gd`) sprawdza decyzje bez widoku 3D.
##
## Tekstury: `tools/gen_impact_marks.py` → `art/world3d/marks/<nazwa>_{albedo,normal,orm[,emission]}.png`. Alfa albedo maskuje też
## normalną i ORM (tak działa `Decal`). Brak pliku (np. przed generacją) → `textures` zwraca pusty słownik, a widok 3D bierze dawną
## teksturę liczoną w GDScript.

const DIR := "res://art/world3d/marks/"
const HOLE_VARIANTS := 3
const GRAZE_VARIANTS := 2
const CLUSTER_VARIANTS := 2
const SCORCH_VARIANTS := 2
const POCK_VARIANTS := 3
const HOLE_KINDS := ["concrete", "rock", "dirt", "wood", "metal", "ice"]
const GRAZE_KINDS := ["concrete", "rock", "metal"]
const CLUSTER_KINDS := ["concrete", "rock", "dirt", "wood", "metal"]
const SCORCH_KINDS := ["concrete", "rock", "dirt", "metal", "wood"]

const HOLE_M := 0.12                        ## średnica śladu kuli 7,62 prostopadle [m] (ok. 1,5 × prawdziwego odprysku — decyzja 2 — podniesione
                                           ## z 0,09 po zrzutach: z kamery gry 9 cm to 5 px na 1080p, ślad ginął w teksturze betonu)
const KIND_SIZE := {"dirt": 1.4, "metal": 0.7, "wood": 0.9, "ice": 1.1, "rock": 1.05}   ## mnożnik średnicy wg rodzaju
const CALIBER_SIZE := {"918": 0.8, "762": 1.0, "12g": 1.3}   ## mnożnik średnicy wg kalibru (12g bez śrucin = Brenneke)
const PELLET_SIZE := 0.45                   ## śrucina: drobna dziurka
const GRAZE_SIN := 0.34                     ## sin 20°: płycej → rysa zamiast dziury (beton, skała, blacha)
const STRETCH_MAX := 2.6                    ## najdłuższy owal przy płaskim trafieniu
const MERGE_R := 0.4                        ## nowy ślad bliżej niż tyle × średnicy od starego tego samego rodzaju → powiększa stary
const MERGE_GROW := 1.12                    ## powiększenie starego śladu na każde scalenie
const MERGE_MAX := 1.6                      ## najwięcej × średnicy pierwotnej
const CLUSTER_M := 0.34                     ## średnica dekala gniazda śrutu [m]
const CLUSTER_AT := 3                       ## od tylu śrucin z jednego strzału w jednym kaflu — gniazdo zamiast pojedynczych dziurek
## Limit śladów po kulach wg jakości (LOW / MEDIUM / HIGH). Ślad to dwa dekale (na powierzchni trafienia i na czole bryły, `FRONT_*`),
## więc HIGH to do 320 dekali — pomiar E0: 309 dekali w kadrze +0,22 ms GPU, klaster ma 512 elementów razem ze światłami.
const LIMITS := [64, 112, 160]
const SCORCH_LIMITS := [12, 20, 32]         ## limit osmaleń wg jakości
## Ślad na czole bryły (ściana zwrócona do kamery): kula leci w płaszczyźnie gry i trafia boki kafli, które kamera widzi krawędzią —
## dekal na boku i na wierzchu podłogi jest z kamery prawie niewidoczny (zrzuty E1 2026-11-22). Drugi dekal rzutowany z przodu (−Z)
## na czoło bryły przy krawędzi trafienia daje odprysk, który widać.
const FRONT_SCALE := 1.5                    ## × średnica śladu
const FRONT_IN := 0.3                       ## środek odprysku przesunięty w głąb bryły o tyle × średnicy (od krawędzi)
const FRONT_TILES := ["#", "C", "M", "i", "s"]   ## kafle z czołem bryły (kładki `-` / `=` bez)

static var _cache := {}                     ## nazwa → {albedo, normal, orm, emission} (pusty, gdy brak plików)

## Rodzaj śladu z wyglądu kafla, nie z powierzchni kroków: bryła `#` pod ziemią to skała (w 3D skała tuneli), na powierzchni ziemia;
## kładka `-` to deski, kratownica `=` blacha. `tile` — znak kafla mapy (`level.tile_char_at`), `surface` — powierzchnia kroków.
static func kind_for(tile: String, surface: String, underground: bool) -> String:
	match tile:
		"#":
			return "rock" if underground else "dirt"
		"-":
			return "wood"
		"=", "M":
			return "metal"
		"C":
			return "concrete"
		"i":
			return "ice"
		"s":
			return "dirt"
	match surface:
		"dirt", "snow":
			return "dirt"
		"wood":
			return "wood"
		"metal":
			return "metal"
		"ice":
			return "ice"
	return "concrete"

## Mnożnik średnicy śladu z kalibru broni (WeaponDef.caliber) i liczby śrucin naboju.
static func caliber_scale(caliber: String, pellets: int) -> float:
	if pellets >= 2:
		return PELLET_SIZE
	return float(CALIBER_SIZE.get(caliber, 1.0))

## Średnica śladu kuli [m] dla rodzaju i kalibru (bez losowości).
static func hole_size(kind: String, scale: float) -> float:
	return HOLE_M * float(KIND_SIZE.get(kind, 1.0)) * scale

## Kąt padania: [rozciągnięcie wzdłuż toru (≥ 1), rysa?]. `dir` — kierunek lotu (2D), `normal` — normalna powierzchni (2D).
## Bez kierunku (wybuch, test) — prostopadle.
static func incidence(dir: Vector2, normal: Vector2, kind: String) -> Array:
	if dir.length() < 0.01 or normal.length() < 0.01:
		return [1.0, false]
	var s := absf(dir.normalized().dot(normal.normalized()))
	var graze := s < GRAZE_SIN and kind in GRAZE_KINDS
	return [clampf(1.0 / maxf(s, 0.01), 1.0, STRETCH_MAX), graze]

## Wariant tekstury z punktu (ten sam punkt → ten sam ślad u każdego przebiegu i w zrzutach).
static func variant(pos: Vector2, count: int, salt := 0) -> int:
	var h := hash(Vector3i(int(round(pos.x * 4.0)), int(round(pos.y * 4.0)), salt))
	return absi(h) % maxi(1, count)

## Obrót wokół normalnej z punktu [rad].
static func spin(pos: Vector2) -> float:
	return float(absi(hash(Vector2i(int(round(pos.x * 8.0)), int(round(pos.y * 8.0))))) % 3600) / 3600.0 * TAU

## Indeks śladu do scalenia: najbliższy w `pts` (px) tego samego rodzaju (`kinds`) bliżej niż MERGE_R × średnicy; -1 — nowy ślad.
## `size_px` — średnica nowego śladu w px świata.
static func merge_index(pts: PackedVector2Array, kinds: PackedStringArray, pos: Vector2, kind: String, size_px: float) -> int:
	var best := -1
	var bd := MERGE_R * size_px
	for i in pts.size():
		if kinds[i] != kind:
			continue
		var d := pts[i].distance_to(pos)
		if d < bd:
			bd = d
			best = i
	return best

static func limit(quality_idx: int) -> int:
	return int(LIMITS[clampi(quality_idx, 0, LIMITS.size() - 1)])

static func scorch_limit(quality_idx: int) -> int:
	return int(SCORCH_LIMITS[clampi(quality_idx, 0, SCORCH_LIMITS.size() - 1)])

## Nazwa pliku śladu kuli: dziura, rysa albo gniazdo śrutu.
static func hole_name(kind: String, graze: bool, cluster: bool, v: int) -> String:
	if cluster:
		var k := kind if kind in CLUSTER_KINDS else "concrete"
		return "cluster_%s_%d" % [k, v % CLUSTER_VARIANTS]
	if graze:
		return "graze_%s_%d" % [kind if kind in GRAZE_KINDS else "concrete", v % GRAZE_VARIANTS]
	return "hole_%s_%d" % [kind if kind in HOLE_KINDS else "concrete", v % HOLE_VARIANTS]

static func scorch_name(kind: String, v: int) -> String:
	var k := kind if kind in SCORCH_KINDS else ("dirt" if kind == "ice" else "concrete")
	return "scorch_%s_%d" % [k, v % SCORCH_VARIANTS]

## Tekstury śladu `name` z `DIR` (albedo, normal, orm, emission) albo pusty słownik, gdy brak albedo.
static func textures(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out := {}
	var base := DIR + name
	if ResourceLoader.exists(base + "_albedo.png"):
		out["albedo"] = load(base + "_albedo.png")
		for ch in ["normal", "orm", "emission"]:
			if ResourceLoader.exists(base + "_" + ch + ".png"):
				out[ch] = load(base + "_" + ch + ".png")
	_cache[name] = out
	return out

## Wszystkie nazwy śladów (rozgrzanie przy budowie mapy).
static func all_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in HOLE_KINDS:
		for v in HOLE_VARIANTS:
			out.append(hole_name(k, false, false, v))
	for k in GRAZE_KINDS:
		for v in GRAZE_VARIANTS:
			out.append(hole_name(k, true, false, v))
	for k in CLUSTER_KINDS:
		for v in CLUSTER_VARIANTS:
			out.append(hole_name(k, false, true, v))
	for k in SCORCH_KINDS:
		for v in SCORCH_VARIANTS:
			out.append(scorch_name(k, v))
	for v in POCK_VARIANTS:
		out.append("pock_%d" % v)
	return out

# ---------------------------------------------------------------- wybuch (E2)

const BLAST_RAYS := [8, 10, 12]             ## promieni z punktu wybuchu wg jakości
const BLAST_REACH := 0.8                    ## zasięg promieni × promień wybuchu
const SCORCH_MIN_M := 0.5
const SCORCH_MAX_M := 3.0
const POCK_MIN := 4                         ## dziobaki odłamków poza pierścieniem (granaty i WRATH-4)
const POCK_MAX := 8
const POCK_M := 0.16                        ## średnica dekala dziobaków [m]

## Punkty osmalenia wybuchu w `pos` o promieniu `radius` (px): promienie po masce 1|16, trafienia zgrupowane po kaflu i normalnej (jedno
## osmalenie na grunt / ścianę / strop). Wynik: [{pos, normal, size_m, cell}] od najbliższego. `rays` — liczba promieni (jakość).
## `px_m` — metry na px (`Level3D.PX`).
static func blast_marks(space: PhysicsDirectSpaceState2D, pos: Vector2, radius: float, rays: int, px_m: float) -> Array:
	var groups := {}
	for i in rays:
		var a := TAU * (float(i) + 0.5) / float(rays) + PI * 0.5      # pierwszy promień prosto w dół (+y)
		var d := Vector2(cos(a), sin(a))
		var q := PhysicsRayQueryParameters2D.create(pos, pos + d * radius * BLAST_REACH, 1 | 16)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var p: Vector2 = hit["position"]
		var n: Vector2 = hit["normal"]
		var cell := Vector2i(floori((p.x - n.x * 2.0) / 16.0), floori((p.y - n.y * 2.0) / 16.0))
		var nk := Vector2i(roundi(n.x), roundi(n.y))
		var key := "%d,%d:%d,%d" % [cell.x, cell.y, nk.x, nk.y]
		var dist := p.distance_to(pos)
		if not groups.has(key) or float(groups[key]["dist"]) > dist:
			groups[key] = {"pos": p, "normal": n, "dist": dist, "cell": cell}
	var out: Array = []
	for g in groups.values():
		var k := 1.0 - clampf(float(g["dist"]) / (radius * BLAST_REACH), 0.0, 1.0) * 0.7
		g["size_m"] = clampf(radius * px_m * 0.9 * k, SCORCH_MIN_M, SCORCH_MAX_M)
		out.append(g)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	# wiele kafli tej samej płaszczyzny (np. podłoga pod wybuchem trafiona 3 promieniami) → jedno osmalenie na płaszczyznę w zasięgu,
	# w punkcie najbliższym wybuchu
	var keep: Array = []
	for g in out:
		var dup := false
		for k2 in keep:
			var kn: Vector2 = k2["normal"]
			if kn.dot(g["normal"]) > 0.9 and absf(((g["pos"] as Vector2) - (k2["pos"] as Vector2)).dot(kn)) < 3.0:   # ta sama płaszczyzna
				dup = true
				break
		if not dup:
			keep.append(g)
	return keep

## Dziobaki odłamków poza pierścieniem osmalenia: punkty na ścianach i stropie w 0,8–1,5 promienia (promienie z wybuchu, ziarno z punktu).
static func pock_marks(space: PhysicsDirectSpaceState2D, pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(pos.x), int(pos.y)))
	var want := rng.randi_range(POCK_MIN, POCK_MAX)
	for i in want * 2:
		if out.size() >= want:
			break
		var a := rng.randf() * TAU
		var d := Vector2(cos(a), sin(a))
		var q := PhysicsRayQueryParameters2D.create(pos, pos + d * radius * 1.5, 1 | 16)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dist := (hit["position"] as Vector2).distance_to(pos)
		if dist < radius * 0.5:
			continue
		out.append({"pos": hit["position"], "normal": hit["normal"], "v": i % POCK_VARIANTS})
	return out
