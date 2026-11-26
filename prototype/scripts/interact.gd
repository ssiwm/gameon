extends RefCounted
## Wybór celu [E] (pad: [B]) dla lokalnego gracza — jeden na klatkę fizyki (INTERACT_PLAN.md I1).
##
## Obiekty, które reagują na interakcję, są w grupie `interactables` i mają `interact_offer(me) -> Dictionary` (pusty słownik — teraz
## nic nie oferują). Lokalny gracz sam oferuje podnoszenie kolegi (player.gd). `update()` zbiera oferty i wybiera jedną: najpierw
## możliwe (`ok`), potem najwyższy priorytet, przy remisie mniejsza odległość, a gdy różnica odległości jest mniejsza niż FACING_TIE_PX —
## obiekt po stronie, w którą patrzy postać. Cel trzymany [E] (rodzaj HOLD) zostaje celem do puszczenia klawisza, póki jego oferta
## jest możliwa. Oferta niemożliwa (brak desek, zablokowana broń w podpowiedzi) wygrywa tylko wtedy, gdy nie ma żadnej możliwej —
## pasek akcji i znacznik 3D pokazują wtedy powód, ale [E] nic nie robi.
##
## Z wyniku czytają: obiekty (`pressed` / `held` — „czy [E] dotyczy właśnie mnie”), pasek akcji HUD (hud.gd) i znacznik celu w widoku 3D
## (interact_mark3d.gd). Serwer dalej sam sprawdza zasięg, życie i blokady — arbiter rozstrzyga tylko, czego chce lokalny gracz.
##
## Oferta (`offer()`): {"kind": Kind, "prio": int, "ok": bool, "muted": bool, "dist": float, "dx": float, "box": Rect2, "prog": float}
##   dist  odległość do gracza w px (remisy), dx — przesunięcie obiektu względem gracza w poziomie (strona przy remisie)
##   box   prostokąt obiektu w px świata (znacznik 3D); pusty — bez znacznika
##   prog  postęp przytrzymania 0..1 (−1 — brak paska)

enum Kind { PRESS, HOLD }

const GROUP := "interactables"
const FACING_TIE_PX := 4.0           ## przy różnicy odległości mniejszej niż tyle wygrywa obiekt po stronie spojrzenia

## Priorytety ofert (INTERACT_PLAN.md, tabela priorytetów). Jedno miejsce — dokumenty (CONTROLS.md) opisują tę tabelę.
const P_REVIVE := 100                ## podnoszenie kolegi, Mimik jako powalony kolega
const P_PUMP := 90                   ## pompowanie drezyny
const P_WEAPON := 80                 ## broń na ziemi, na stojaku, gablota
const P_TAPE := 70                   ## taśma odsłonięta w ścianie (K4b)
const P_PROP := 65                   ## stempel pod stropem (P2d)
const P_WORK := 60                   ## sejf, generator, barykada
const P_SEARCH := 50                 ## zwłoki
const P_STATION := 40                ## stanowiska kryjówki
const P_EXIT := 30                   ## tablica odprawy, drzwi strzelnicy

static var _frame := -1
static var _me: Node2D = null
static var _target: Node = null
static var _offer := {}
static var _locked: Node = null
## Testy: wymuszony stan klawisza (−1 — czytaj Input; 0/1 — puszczony / trzymany). Nie dotyczy `pressed` (just_pressed z Input).
static var sim_held := -1

## Oferta obiektu `node` dla gracza `me` (pomocnik do `interact_offer`).
static func offer(node: Node2D, me: Node2D, kind: int, prio: int, ok := true, box := Rect2(), prog := -1.0, dist := -1.0) -> Dictionary:
	var dx := node.global_position.x - me.global_position.x
	return {"kind": kind, "prio": prio, "ok": ok, "muted": not ok, "dist": absf(dx) if dist < 0.0 else dist, "dx": dx, "box": box, "prog": prog}

## Lokalny człowiek (właściciel postaci, nie bot) albo null.
static func local_player(tree: SceneTree) -> Node2D:
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and not p.is_queued_for_deletion():
			return p
	return null

## Czysty wybór (test): `cands` — [{"node": Node, "offer": Dictionary}], `facing` — znak kierunku spojrzenia (−1 / +1), `locked` — cel
## trzymanego [E]. Zwraca indeks w `cands` albo −1.
static func choose(cands: Array, facing: float, locked: Node) -> int:
	if locked != null:
		for i in cands.size():
			if cands[i]["node"] == locked and bool(cands[i]["offer"]["ok"]):
				return i
	var best := -1
	for pass_ok in [true, false]:
		for i in cands.size():
			var o: Dictionary = cands[i]["offer"]
			if bool(o["ok"]) != pass_ok:
				continue
			if best < 0 or _better(o, cands[best]["offer"], facing):
				best = i
		if best >= 0:
			return best
	return -1

static func _better(a: Dictionary, b: Dictionary, facing: float) -> bool:
	if int(a["prio"]) != int(b["prio"]):
		return int(a["prio"]) > int(b["prio"])
	var da := float(a["dist"])
	var db := float(b["dist"])
	if absf(da - db) < FACING_TIE_PX:
		var fa := signf(float(a["dx"])) == signf(facing)
		var fb := signf(float(b["dx"])) == signf(facing)
		if fa != fb:
			return fa
	return da < db

static func _is_held() -> bool:
	if sim_held >= 0:
		return sim_held == 1
	return Input.is_action_pressed("interact")

## Zbiera oferty i wybiera cel — raz na klatkę fizyki (kolejne wywołania w tej samej klatce zwracają wynik z pamięci).
static func update(tree: SceneTree, force := false) -> void:
	var f := Engine.get_physics_frames()
	if f == _frame and not force:
		return
	_frame = f
	_target = null
	_offer = {}
	_me = local_player(tree)
	var held := _is_held()
	if not held:
		_locked = null
	if _me == null or bool(_me.get("dead")):
		_locked = null
		return
	var cands: Array = []
	if _me.has_method("interact_offer"):
		var own: Dictionary = _me.interact_offer(_me)
		if not own.is_empty():
			cands.append({"node": _me, "offer": own})
	for n in tree.get_nodes_in_group(GROUP):
		if n == _me or n.is_queued_for_deletion() or not n.has_method("interact_offer"):
			continue
		var o: Dictionary = n.interact_offer(_me)
		if not o.is_empty():
			cands.append({"node": n, "offer": o})
	var aim = _me.get("aim_dir")
	var facing := signf((aim as Vector2).x) if aim is Vector2 and absf((aim as Vector2).x) > 0.01 else 1.0
	var i := choose(cands, facing, _locked if is_instance_valid(_locked) else null)
	if i < 0:
		_locked = null
		return
	_target = cands[i]["node"]
	_offer = cands[i]["offer"]
	if held and bool(_offer["ok"]) and int(_offer["kind"]) == Kind.HOLD:
		_locked = _target
	elif _locked != _target:
		_locked = null

## Cel [E] lokalnego gracza w tej klatce albo null.
static func target(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	update(from.get_tree())
	return _target if is_instance_valid(_target) else null

## Oferta celu (kopia) albo {}.
static func current(from: Node) -> Dictionary:
	return _offer.duplicate() if target(from) != null else {}

## Czy `n` jest celem, a jego oferta możliwa.
static func is_target(n: Node) -> bool:
	return n != null and target(n) == n

## [E] wciśnięte w tej klatce i dotyczy `n` (oferta możliwa).
static func pressed(n: Node) -> bool:
	return is_target(n) and bool(_offer.get("ok", false)) and Input.is_action_just_pressed("interact")

## [E] trzymane i dotyczy `n` (oferta możliwa; cel trzymany nie zmienia się do puszczenia).
static func held(n: Node) -> bool:
	return is_target(n) and bool(_offer.get("ok", false)) and _is_held()

## Testy i zmiana mapy: zapomina cel i blokadę.
static func reset() -> void:
	_frame = -1
	_me = null
	_target = null
	_offer = {}
	_locked = null
	sim_held = -1
