extends Node2D
## Zniszczalny element mapy (DESTRUCTION_PLAN.md D0, D2): jedna klasa z materiałem z tabeli `MATERIALS`. Na mapach są trzy przegrody, każda
## wypełnia wąskie przejście od podłogi do sufitu i zasłania skrót albo skrytkę:
##  - zamurowanie (znacznik „q”, `brick`): kilof (WeaponDef.breaks_walls), wybuch (WRATH-4) albo szarża Rzeźnika — ~3 uderzenia kilofem;
##  - deski / barykada („%”, `planks`): także maczeta (cicho, kilka ciosów) i śrut (szybko, głośno); Trzoski drapią ją pazurami, Wołek
##    wali pięściami, a Wołek i Rzeźnik łamią ją szarżą;
##  - zardzewiała kratka wentylacji („+”, `grate`): tylko kilof i wybuch, szarża się od niej odbija. Ciało kratki leży na warstwie ramy
##    (128, jak okno) — zatrzymuje tylko ruch; kule, wzrok, światło i dźwięk przez nią przechodzą.
## Reszta trafień odbija się bez obrażeń. Zamurowanie i deski są bryłą (ciało na warstwie świata), więc blokują wszystkich i pociski.
## Dziury (materiał z polem `holes`, dziś deski): trafienie co najmniej stopnia 1 (śrut, maczeta, pięść Wołka) przebija deskę — na wysokości
## dziury wzrok, światło, kule i dźwięk przechodzą (`hole_at`, `sight.gd`), ruch i nawigacja dalej nie.
## Deski da się przybijać z powrotem (D2b, `barricade_spot.gd`, level.gd `nail_board`): wytrzymałość dzieli się na deski (level.gd `BOARDS`),
## pusty otwór „:” to ta sama przegroda w stanie rozbitym na starcie; widok 3D pokazuje tyle desek, ile wytrzymałości (`boards`).
## Dla nawigacji każda przegroda liczy się jako kafel (level.gd `_wall_cells`), dzięki czemu boty i wrogowie nie planują drogi przez
## nią ani do skrytki za nią.
## Obrażenia liczy serwer; rozbicie idzie do wszystkich peerów przez level.gd (`break_wall`).
##
## Stopy w (0, 0) = dół elementu, środek kafla w poziomie; `rows` = wysokość w kaflach (level.gd liczy do sufitu).

const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Mat := preload("res://scripts/arsenal.gd").Mat

const TILE := 16.0

## Materiały. Pola:
##   hp       wytrzymałość                          breaks  rodzaje trafień, które niszczą (`hit_kind`); reszta odbija się bez obrażeń
##   n_hit    hałas jednego uderzenia                n_break hałas rozbicia
##   hit_snd  [próbka, warianty, dB, wysokość]       break_snd  to samo przy rozbiciu
##   debris   kolor odłamków                         chips   ile odłamków przy rozbiciu
##   dust     kurz przy uderzeniu / przy rozbiciu    mat     znacznik trafienia (Arsenal.Mat)
##   chip     [świeży przełom, głąb wyrwy] — mnożniki barwy plam w masce uszkodzeń widoku 3D (`damage_mask.gd`, ~1 = bez zmian)
##   layer    warstwa ciała (domyślnie 1 — bryła świata; kratka 128 — tylko ruch, jak rama okna)
##   holes    mnożnik promienia plamy dla dziury na wylot (brak pola — materiał bez dziur)
##   surface  powierzchnia trafienia kulą (Vfx.impact: odpryski i dźwięk)
## Na mapach są `brick`, `planks` i `grate`; `sheet`, `glass` i `support` to wartości wstępne pod kolejne etapy.
const MATERIALS := {
	"brick": {"hp": 120.0, "breaks": ["pick", "blast", "charge"], "n_hit": 1.5, "n_break": 6.0, "surface": "concrete",
		"hit_snd": ["amb_thud", 2, -4.0, 1.4], "break_snd": ["amb_thud", 2, 0.0, 0.7],
		"debris": Color(0.5, 0.3, 0.24), "chips": 10, "chunks": 9, "dust": [1.0, 2.5], "mat": Mat.WORLD, "chip": [Color(1.6, 1.3, 1.15), Color(0.3, 0.22, 0.2)]},
	"planks": {"hp": 60.0, "breaks": ["pick", "blade", "pellet", "blast", "charge", "claw"], "n_hit": 1.2, "n_break": 4.0, "holes": 1.5, "surface": "wood",
		"hit_snd": ["amb_creak", 3, -6.0, 1.2], "break_snd": ["amb_creak", 3, 0.0, 0.8],
		"debris": Color(0.42, 0.3, 0.18), "chips": 8, "chunks": 6, "dust": [0.5, 1.5], "mat": Mat.WOOD, "chip": [Color(1.6, 1.45, 1.2), Color(0.3, 0.22, 0.16)]},
	"sheet": {"hp": 150.0, "breaks": ["pick", "blast", "charge"], "n_hit": 2.5, "n_break": 6.0,
		"hit_snd": ["impact_hard", 3, -3.0, 0.9], "break_snd": ["impact_hard", 3, 2.0, 0.6],
		"debris": Color(0.38, 0.27, 0.2), "chips": 5, "dust": [0.3, 1.0], "mat": Mat.METAL, "chip": [Color(1.7, 1.65, 1.6), Color(0.3, 0.25, 0.22)]},
	"grate": {"hp": 90.0, "breaks": ["pick", "blast"], "n_hit": 2.0, "n_break": 5.0, "layer": 128,
		"hit_snd": ["impact_hard", 3, -4.0, 1.1], "break_snd": ["impact_hard", 3, 0.0, 0.7],
		"debris": Color(0.36, 0.25, 0.18), "chips": 6, "dust": [0.3, 1.0], "mat": Mat.METAL, "chip": [Color(1.7, 1.65, 1.6), Color(0.3, 0.25, 0.22)]},
	"glass": {"hp": 5.0, "breaks": ["pick", "blade", "bullet", "pellet", "blast", "charge"], "n_hit": 1.0, "n_break": 3.0,
		"hit_snd": ["glass_break", 2, -8.0, 1.3], "break_snd": ["glass_break", 2, 0.0, 1.0],
		"debris": Color(0.6, 0.7, 0.72), "chips": 12, "dust": [0.0, 0.3], "mat": Mat.WORLD, "chip": [Color(1.8, 1.85, 1.9), Color(0.45, 0.5, 0.52)]},
	"support": {"hp": 80.0, "breaks": ["pick", "bullet", "pellet", "blast", "charge"], "n_hit": 1.2, "n_break": 5.0,
		"hit_snd": ["amb_creak", 3, -6.0, 1.0], "break_snd": ["amb_creak", 3, 2.0, 0.6],
		"debris": Color(0.4, 0.29, 0.17), "chips": 8, "dust": [0.5, 2.0], "mat": Mat.WOOD, "chip": [Color(1.6, 1.45, 1.2), Color(0.3, 0.22, 0.16)]},
}

## Promień plamy w masce uszkodzeń wg rodzaju trafienia (px świata; 16 px = kafel).
const SPLAT_R := {"pick": 4.0, "blade": 3.0, "bullet": 1.5, "pellet": 1.2, "blast": 6.0, "charge": 8.0, "claw": 2.5}
const SPLAT_GAP := 0.1           ## s: trafienia w tym oknie idą jedną paczką (seria z M-83 to nie 10 wiadomości)
const MAX_SPLATS := 64           ## pamiętanych plam (dla dołączających); starsze wypadają z listy, w masce zostają
const MAX_HOLES := 32            ## pamiętanych dziur; starsze wypadają (deska z tyloma dziurami i tak zaraz pęknie)

var mat_id := "brick"            ## klucz w MATERIALS (`material` zajmuje CanvasItem)
var rows := 3
var hp := -1.0                   ## < 0 przed `_ready`: pełne `hp` materiału
var splats := PackedFloat32Array()   ## plamy u tego peera: po 4 liczby (u, v w ułamkach `hit_rect`, v = 0 u góry; promień px; stopień 0–2)
var splat_total := 0             ## ile plam przyszło łącznie (widok 3D odciska tylko nowe)
var holes := PackedFloat32Array()    ## dziury na wylot u tego peera: po 3 liczby (u, v jak w `splats`, promień px) — z plam, więc wszędzie te same
var hole_total := 0              ## ile dziur powstało łącznie (widok 3D odciska tylko nowe)
var damage_epoch := 0            ## rośnie przy `reset_damage` — widok 3D czyści wtedy maskę i odciska plamy od nowa
var batches_sent := 0            ## serwer: wysłane paczki plam (test)
var _pending := PackedFloat32Array()
var _flush_queued := false
var _last_flush_ms := -100000
var _flash := 0.0
var _seed := 0

## Rodzaj trafienia z `info` (Combat.make_info) dla pola `breaks`: pick (kilof), blade (inna broń biała), bullet, pellet (śrut), blast, charge
## (szarża wroga, np. Rzeźnik), claw (pazury i pięści wroga przy barykadzie — `enemy.gd`). Promień, płomień i inne — pusty tekst, nic nie niszczą.
static func hit_kind(info: Dictionary) -> String:
	var w := int(info.get("w", -1))
	match String(info.get("type", "")):
		"melee":
			return "pick" if Weapons.is_valid(w) and Weapons.def(w).breaks_walls else "blade"
		"bullet":
			return "pellet" if Weapons.is_valid(w) and Weapons.def(w).pellets > 1 else "bullet"
		"blast":
			return "blast"
		"charge":
			return "charge"
		"claw":
			return "claw"
	return ""

## Wpis materiału (nieznana nazwa → `brick`).
func mat_def() -> Dictionary:
	return MATERIALS.get(mat_id, MATERIALS["brick"])

func max_hp() -> float:
	return float(mat_def()["hp"])

func _ready() -> void:
	add_to_group("breakables")
	z_index = 1
	_seed = absi(String(name).hash())
	if hp < 0.0:
		hp = max_hp()
	var body := StaticBody2D.new()
	body.collision_layer = int(mat_def().get("layer", 1))
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(TILE, TILE * float(rows))
	cs.shape = rs
	cs.position = Vector2(0, -TILE * float(rows) * 0.5)
	body.add_child(cs)
	add_child(body)

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

## Prostokąt elementu we współrzędnych świata (trafianie, wybuch, podpowiedź).
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-TILE * 0.5, -TILE * float(rows)), Vector2(TILE, TILE * float(rows)))

func body_center() -> Vector2:
	return hit_rect().get_center()

func is_threat() -> bool:
	return false

func hit_radius() -> float:
	return TILE * 0.8

## Serwer: trafienie z listy `breaks` materiału rani, reszta tylko odbija się z brzękiem (hit = false — bez znacznika trafienia).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or hp <= 0.0:
		return {}
	var m := mat_def()
	var kind := hit_kind(info)
	if not (m["breaks"] as Array).has(kind):
		return {"hit": false, "dealt": 0.0, "killed": false, "mat": 0}
	hp -= float(info["amount"])
	NoiseMgr.add_noise(float(m["n_hit"]), global_position, "wall")
	var broken := hp <= 0.0
	_pending.append_array(_splat_for(info, kind))
	_queue_flush()
	if broken:
		NoiseMgr.add_noise(float(m["n_break"]), global_position, "wall")
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.break_wall(String(name))
	return {"hit": true, "dealt": float(info["amount"]), "killed": broken, "mat": int(m["mat"])}

## Serwer: plama trafienia. Punkt z `info.pos` (wybuch: najbliższy punkt elementu) w obrębie elementu; cios i szarża bez dokładnego punktu
## dostają rozrzut, żeby kolejne nie lądowały w tym samym miejscu (losuje tylko serwer — peery dostają gotowe liczby). Stopień z siły
## trafienia względem wytrzymałości: < 10% odprysk, < 34% wyszczerbienie, więcej — wyrwa.
func _splat_for(info: Dictionary, kind: String) -> PackedFloat32Array:
	var rc := hit_rect()
	var p: Vector2 = info.get("pos", rc.get_center())
	if kind in ["pick", "blade", "charge", "claw"]:
		p += Vector2(randf_range(-4.0, 4.0), randf_range(-rc.size.y * 0.3, rc.size.y * 0.3))
	p = p.clamp(rc.position, rc.end)
	var share := float(info["amount"]) / max_hp()
	var deg := 0 if share < 0.1 else (1 if share < 0.34 else 2)
	return PackedFloat32Array([(p.x - rc.position.x) / rc.size.x, (p.y - rc.position.y) / rc.size.y, float(SPLAT_R.get(kind, 3.0)), float(deg)])

## Serwer: paczka wychodzi pod koniec klatki pierwszego trafienia (od razu słychać i widać), kolejne w oknie SPLAT_GAP czekają na następną.
func _queue_flush() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	var wait := SPLAT_GAP - float(Time.get_ticks_msec() - _last_flush_ms) / 1000.0
	if wait <= 0.0:
		_flush.call_deferred()
	else:
		get_tree().create_timer(wait).timeout.connect(_flush)

func _flush() -> void:
	_flush_queued = false
	if _pending.is_empty() or is_queued_for_deletion():
		return
	var data := _pending
	_pending = PackedFloat32Array()
	_last_flush_ms = Time.get_ticks_msec()
	batches_sent += 1
	var frac := clampf(hp / max_hp(), 0.0, 1.0)
	if NoiseMgr.has_network():
		_splat_rpc.rpc(data, frac)
	else:
		_splat_rpc(data, frac)

## U wszystkich peerów: plamy z paczki, stan wytrzymałości, jeden dźwięk i kurz na paczkę.
@rpc("authority", "call_local", "reliable")
func _splat_rpc(data: PackedFloat32Array, frac: float) -> void:
	var n := _add_splats(data, frac)
	if n == 0:
		return
	var m := mat_def()
	_flash = 0.12
	var rc := hit_rect()
	var at := Vector2.ZERO
	for i in n:
		at += rc.position + Vector2(data[i * 4] * rc.size.x, data[i * 4 + 1] * rc.size.y)
	var lvl := get_tree().get_first_node_in_group("level")
	var dust: float = (m["dust"] as Array)[0]
	if dust > 0.0:
		Vfx.dust(lvl if lvl != null else self, at / float(n), dust)
	_play(m["hit_snd"])
	queue_redraw()

## Dołączający: wszystkie zapamiętane plamy naraz, bez dźwięku i kurzu (level.gd `send_walls_to`).
@rpc("authority", "call_remote", "reliable")
func _splat_sync(data: PackedFloat32Array, frac: float) -> void:
	_add_splats(data, frac)

func _add_splats(data: PackedFloat32Array, frac: float) -> int:
	hp = max_hp() * clampf(frac, 0.0, 1.0)
	var n := data.size() / 4
	splats.append_array(data.slice(0, n * 4))
	if splats.size() > MAX_SPLATS * 4:
		splats = splats.slice(splats.size() - MAX_SPLATS * 4)
	splat_total += n
	var k := float(mat_def().get("holes", 0.0))
	var made := 0
	for i in n:
		if k > 0.0 and data[i * 4 + 3] >= 1.0:
			holes.append_array(PackedFloat32Array([data[i * 4], data[i * 4 + 1], data[i * 4 + 2] * k]))
			made += 1
	if made > 0:
		if holes.size() > MAX_HOLES * 3:
			holes = holes.slice(holes.size() - MAX_HOLES * 3)
		hole_total += made
		_holes_changed()
	return n

## Dziura na wylot na wysokości `y` (świat): promień poziomy na tej wysokości przechodzi przez przegrodę (`sight.gd`). Przegroda jest wąska
## (1 kafel), więc liczy się tylko wysokość — szerokość dziury na froncie to obraz w widoku 3D.
func hole_at(y: float) -> bool:
	if holes.is_empty():
		return false
	var rc := hit_rect()
	for i in holes.size() / 3:
		if absf(y - (rc.position.y + holes[i * 3 + 1] * rc.size.y)) <= holes[i * 3 + 2]:
			return true
	return false

## Czy któraś dziura sięga w pas wysokości od `y0` do `y1` (świat) — kafel siatki dźwięku przez nią otwarty (level.gd `_is_sound_solid`).
func hole_in(y0: float, y1: float) -> bool:
	var rc := hit_rect()
	for i in holes.size() / 3:
		var hy := rc.position.y + holes[i * 3 + 1] * rc.size.y
		if hy + holes[i * 3 + 2] > y0 and hy - holes[i * 3 + 2] < y1:
			return true
	return false

## Nowe dziury albo ich brak po resecie: siatka dźwięku w kaflach przegrody od nowa.
func _holes_changed() -> void:
	var lvl := get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	if lvl != null:
		lvl.call("window_changed", self)

## U wszystkich peerów (level.gd `_reset_breakables_rpc`): uszkodzenia zastąpione stanem `data` / `frac` — wipe (czysto) albo punkt
## kontrolny bossa (plamy z przebudzenia). Czekająca paczka przepada.
func reset_damage(data: PackedFloat32Array, frac: float) -> void:
	_pending = PackedFloat32Array()
	splats = PackedFloat32Array()
	splat_total = 0
	var had_holes := not holes.is_empty()
	holes = PackedFloat32Array()
	hole_total = 0
	damage_epoch += 1
	_add_splats(data, frac)
	if had_holes and holes.is_empty():
		_holes_changed()
	queue_redraw()

## U wszystkich peerów (level.gd `_nail_rpc`): przybita deska — nowa wytrzymałość (ułamek), plamy zostają.
func set_hp_frac(frac: float) -> void:
	hp = max_hp() * clampf(frac, 0.0, 1.0)
	queue_redraw()

## Ile z `n` desek stoi (widok 3D barykady): nadłamana deska dalej wisi.
func boards(n: int) -> int:
	return clampi(ceili(hp / max_hp() * float(n) - 0.001), 0, n)

## Serwer: stan dla dołączającego (pusty, gdy element nietknięty).
func send_state_to(peer_id: int) -> void:
	if not splats.is_empty() or hp < max_hp():
		_splat_sync.rpc_id(peer_id, splats, clampf(hp / max_hp(), 0.0, 1.0))

## Rozpad na bryły (DESTRUCTION_PLAN.md D0): `chunks` brył z materiału, rozłożonych po prostokącie elementu siatką z odchyleniem, lekko
## w bok i w dół — mur osypuje się w miejscu, a nie wybucha. Z ziarna (`map_id` + nazwa), więc u wszystkich peerów te same miejsca,
## prędkości, rozmiary i kształty bez wysyłania ich w RPC. Wynik: [pozycja, prędkość, rozmiar px, kształt].
func chunk_plan(seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var rc := hit_rect()
	var n := int(mat_def().get("chunks", 0))
	var cols := maxi(1, roundi(sqrt(n * rc.size.x / maxf(rc.size.y, 1.0))))
	var rows := ceili(float(n) / cols)
	var out: Array = []
	for i in n:
		var cx := (float(i % cols) + 0.5 + rng.randf_range(-0.3, 0.3)) / cols
		var cy := (float(i / cols) + 0.5 + rng.randf_range(-0.3, 0.3)) / rows
		var pos := rc.position + rc.size * Vector2(cx, cy)
		out.append([pos, Vector2((cx - 0.5) * rng.randf_range(40.0, 90.0), rng.randf_range(-50.0, 10.0)), rng.randf_range(4.5, 7.0), rng.randi()])
	return out

## Rozbicie (u wszystkich peerów, z level.gd): bryły pre-fraktury (`chunk_plan`, widok 3D `mirror_chunk`), drobne odłamki i kurz, potem element znika.
func crumble() -> void:
	var m := mat_def()
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	var rc := hit_rect()
	for ch in chunk_plan(hash("%s:%s" % [String(lvl.get("map_id")) if lvl != null else "", String(name)])):
		var sz: float = ch[2]
		var b := Vfx.debris(parent, ch[0], ch[1], Vector2(sz, sz * 0.75), m["debris"], 0.1, 3.0)
		if b != null and Vfx.view3d != null and is_instance_valid(Vfx.view3d):
			Vfx.view3d.call("mirror_chunk", b, mat_id, sz, int(ch[3]))
	for i in int(m["chips"]):
		var p := Vector2(rc.position.x + randf() * rc.size.x, rc.position.y + randf() * rc.size.y)
		Vfx.debris(parent, p, Vector2(randf_range(-60.0, 60.0), randf_range(-90.0, -20.0)), Vector2(3, 3), m["debris"])
	var dust: float = (m["dust"] as Array)[1]
	if dust > 0.0:
		Vfx.dust(parent, rc.get_center(), dust)
	_play(m["break_snd"])
	queue_free()

func _play(snd: Array) -> void:
	Audio.play_variant_at(String(snd[0]), int(snd[1]), global_position, Audio.BUS_WORLD, float(snd[2]), float(snd[3]))
