extends Node
## Skaner „Sowa” (A2): co pokazuje lokalnemu graczowi — wrogów w promieniu skanera (także za ścianami) i zakopane znajdźki stref
## wydobycia (D5). Sam nic nie rysuje: obraz robi widok 3D (view3d.gd `_sync_scanner`, pulse3d.gd) — fala sonaru po ścianach,
## podłodze i stropie, modele wrogów prześwietlone przez ściany, romby 3D znajdziek. Zasięg i czas bierze z throwables.gd;
## stan (`scan_left`) trzyma player.gd. Do 1.7.565 nakładka 2D (okręgi, prostokąty, romby).

const Throwables := preload("res://scripts/throwables.gd")

## Okres fali sonaru [s] (fala biegnie od gracza do brzegu zasięgu, potem następna).
const PULSE_PERIOD := 1.0 / 0.9
## Wysokość środka skanera nad stopami gracza [px] (pierś, tam trzyma urządzenie).
const CENTER_UP := 9.0

var player: Node2D
var _t := 0.0

func _process(delta: float) -> void:
	if active():
		_t += delta

func active() -> bool:
	return player != null and is_instance_valid(player) and float(player.scan_left) > 0.0

## Środek skanera w px świata.
func center() -> Vector2:
	return player.global_position + Vector2(0, -CENTER_UP)

## Zasięg [px].
func range_px() -> float:
	return float(Throwables.KINDS["scanner"]["range"])

## Faza fali 0..1 (0 — przy graczu, 1 — na brzegu zasięgu).
func pulse() -> float:
	return fmod(_t / PULSE_PERIOD, 1.0)

## Wygaszanie w ostatnich 1,5 s działania.
func fade() -> float:
	return clampf(float(player.scan_left) / 1.5, 0.0, 1.0)

## Wrogowie widoczni na skanerze: [{node, hot (zagrożenie), scouted (uśpiony Stalker z perkiem „Scout”), size [px]}].
func enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not active():
		return out
	var c := center()
	var r := range_px()
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n) or n.is_in_group("props") or n.is_in_group("breakables"):
			continue
		var scouted := false             # „Scout": Stalker widoczny na skanerze także uśpiony, ale tylko z bliska
		if not n.visible:
			scouted = n.has_method("is_stalker") and player.has_perk("scout") and n.global_position.distance_to(c) <= player.perk_param("scout", "scan_stalker_range", 0.0)
			if not scouted:
				continue
		if n.get("alive") == false:
			continue
		if n.global_position.distance_to(c) > r:
			continue
		var hot: bool = n.has_method("is_threat") and bool(n.call("is_threat"))
		var sz: Vector2 = n.get("_def")["size"] if n.get("_def") is Dictionary and (n.get("_def") as Dictionary).has("size") else Vector2(10, 14)
		out.append({"node": n, "hot": hot, "scouted": scouted, "size": sz})
	return out

## Zakopane znajdźki w zasięgu (dig_zone.gd, D5): [{pos [px], small (drobnica z puli — mniejszy, bledszy romb)}].
func finds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not active():
		return out
	for z in get_tree().get_nodes_in_group("dig_zones"):
		for f in z.buried_finds(center(), range_px()):
			out.append({"pos": f["pos"], "small": String(f["kind"]) == "small"})
	return out
