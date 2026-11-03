extends Node2D
## Zniszczalny element mapy (DESTRUCTION_PLAN.md D0): jedna klasa z materiałem z tabeli `MATERIALS`. Dziś jedyny na mapach to zamurowane
## przejście (marker „q”, materiał `brick`): cegły wypełniają wąskie przejście od podłogi do sufitu i zasłaniają skrytkę; rozbija je kilof
## (WeaponDef.breaks_walls), wybuch (WRATH-4) albo szarża Rzeźnika — ~3 uderzenia kilofem. Kule i maczeta odbijają się.
## Element jest bryłą (ciało na warstwie świata), więc blokuje wszystkich i pociski; dla nawigacji liczy się jako kafel
## (level.gd `_wall_cells`), dzięki czemu boty i wrogowie nie planują drogi przez niego ani do skrytki za nim.
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
## Na mapach jest dziś tylko `brick`; reszta to wartości wstępne pod D1 (deski, blacha, kratka, szkło, podpory) — strojenie, a także
## przepuszczanie kul i światła przez kratkę i rozbite szkło, przyjdą razem z pierwszym takim elementem na mapie.
const MATERIALS := {
	"brick": {"hp": 120.0, "breaks": ["pick", "blast", "charge"], "n_hit": 1.5, "n_break": 6.0,
		"hit_snd": ["amb_thud", 2, -4.0, 1.4], "break_snd": ["amb_thud", 2, 0.0, 0.7],
		"debris": Color(0.5, 0.3, 0.24), "chips": 10, "dust": [1.0, 2.5], "mat": Mat.WORLD, "chip": [Color(1.6, 1.3, 1.15), Color(0.3, 0.22, 0.2)]},
	"planks": {"hp": 60.0, "breaks": ["pick", "blade", "pellet", "blast", "charge"], "n_hit": 1.2, "n_break": 4.0,
		"hit_snd": ["amb_creak", 3, -6.0, 1.2], "break_snd": ["amb_creak", 3, 0.0, 0.8],
		"debris": Color(0.42, 0.3, 0.18), "chips": 8, "dust": [0.5, 1.5], "mat": Mat.WOOD, "chip": [Color(1.6, 1.45, 1.2), Color(0.3, 0.22, 0.16)]},
	"sheet": {"hp": 150.0, "breaks": ["pick", "blast", "charge"], "n_hit": 2.5, "n_break": 6.0,
		"hit_snd": ["impact_hard", 3, -3.0, 0.9], "break_snd": ["impact_hard", 3, 2.0, 0.6],
		"debris": Color(0.38, 0.27, 0.2), "chips": 5, "dust": [0.3, 1.0], "mat": Mat.METAL, "chip": [Color(1.7, 1.65, 1.6), Color(0.3, 0.25, 0.22)]},
	"grate": {"hp": 90.0, "breaks": ["pick", "blast"], "n_hit": 2.0, "n_break": 5.0,
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
const SPLAT_R := {"pick": 4.0, "blade": 3.0, "bullet": 1.5, "pellet": 1.2, "blast": 6.0, "charge": 8.0}
const SPLAT_GAP := 0.1           ## s: trafienia w tym oknie idą jedną paczką (seria z M-83 to nie 10 wiadomości)
const MAX_SPLATS := 64           ## pamiętanych plam (dla dołączających); starsze wypadają z listy, w masce zostają

var mat_id := "brick"            ## klucz w MATERIALS (`material` zajmuje CanvasItem)
var rows := 3
var hp := -1.0                   ## < 0 przed `_ready`: pełne `hp` materiału
var splats := PackedFloat32Array()   ## plamy u tego peera: po 4 liczby (u, v w ułamkach `hit_rect`, v = 0 u góry; promień px; stopień 0–2)
var splat_total := 0             ## ile plam przyszło łącznie (widok 3D odciska tylko nowe)
var batches_sent := 0            ## serwer: wysłane paczki plam (test)
var _pending := PackedFloat32Array()
var _flush_queued := false
var _last_flush_ms := -100000
var _flash := 0.0
var _seed := 0

## Rodzaj trafienia z `info` (Combat.make_info) dla pola `breaks`: pick (kilof), blade (inna broń biała), bullet, pellet (śrut), blast, charge
## (szarża wroga, np. Rzeźnik). Promień, płomień i inne — pusty tekst, nic nie niszczą.
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
	body.collision_layer = 1
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
	if kind in ["pick", "blade", "charge"]:
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
	return n

## Serwer: stan dla dołączającego (pusty, gdy element nietknięty).
func send_state_to(peer_id: int) -> void:
	if not splats.is_empty():
		_splat_sync.rpc_id(peer_id, splats, clampf(hp / max_hp(), 0.0, 1.0))

## Rozbicie (u wszystkich peerów, z level.gd): odłamki i kurz, potem element znika.
func crumble() -> void:
	var m := mat_def()
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	var rc := hit_rect()
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
