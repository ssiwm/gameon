extends Node
## Bestiariusz z odkrywaniem (od 1.7.407): wróg, który pojawił się na ekranie lokalnego gracza, odsłania swój wpis w kodeksie
## (Profile.discover) — nowy wpis to krótki komunikat z klawiszem kodeksu. Ukryci (Żerca przed atakiem, Mimik w przebraniu) odsłaniają się
## dopiero po ujawnieniu albo zabiciu (zabójstwo też odsłania: Profile.note_beast_kill). Węzeł tworzy hud.gd.

const Codex := preload("res://scripts/codex.gd")
const Actions := preload("res://scripts/actions.gd")
const PERIOD := 0.4                   ## s między przeglądami wrogów
const MARGIN := 12.0                  ## px od krawędzi ekranu: wróg ledwo wystający zza krawędzi jeszcze nie jest „spotkany”

var _t := 0.0

func _ready() -> void:
	Profile.discovered.connect(_on_discovered)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIOD
	if not NoiseMgr.has_network() or NoiseMgr.safe_zone:
		return
	var vp := get_viewport()
	var rect := vp.get_visible_rect().grow(-MARGIN)
	var xf := vp.get_canvas_transform()
	for e in get_tree().get_nodes_in_group("enemies"):
		var id := id_of(e)
		if id == "" or Profile.knows(id) or not (e is Node2D) or hidden(e):
			continue
		if rect.has_point(xf * (e as Node2D).global_position):
			Profile.discover(id)

## Wpis bestiariusza dla węzła wroga: rodzaj (enemy.gd), stalker, nest, vein, leech albo "" (np. pomocnicy bossa bez wpisu).
static func id_of(e: Node) -> String:
	var path := String(e.get_script().resource_path) if e.get_script() != null else ""
	if path.ends_with("leech.gd"):
		return "leech"
	if e.is_in_group("boss"):
		return "vein"
	if path.ends_with("stalker.gd"):
		return "stalker"
	if path.ends_with("nest.gd"):
		return "nest"
	var k: Variant = e.get("kind")
	return String(k) if k != null and Codex.Enemy.KINDS.has(String(k)) else ""

## Wróg martwy albo jeszcze ukryty przed graczami (Żerca przed atakiem, Mimik w przebraniu).
static func hidden(e: Node) -> bool:
	if e.get("alive") == false:
		return true
	var beh: Variant = e.get("_beh")
	if beh is Object:
		if (beh as Object).has_method("is_hidden") and bool((beh as Object).call("is_hidden")):
			return true
		if (beh as Object).has_method("disguised") and bool((beh as Object).call("disguised")) and e.get("active") == false:
			return true                                   # Mimik przed demaskacją (wake) stoi jak kolega z drużyny
	return false

func _on_discovered(id: String) -> void:
	print("[BESTIARY] discovered %s" % id)
	Msg.post("bestiary.%s" % id, Msg.Ch.TOAST, tr("New bestiary entry: %s") % tr(Codex.beast_name(id)),
		{"sub": tr("%s → Bestiary") % Actions.key("pause"), "style": Msg.Style.LORE, "ttl": 4.0, "prio": 55})
