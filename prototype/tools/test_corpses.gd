extends SceneTree
## Zwłoki w świecie (MIMIC_PLAN.md M3, corpse.gd + corpse3d.gd):
## - dane CORPSES map kampanii 1.1–1.3: pola, ułożenie i strój ze znanych, ciało na podłodze (3 kafle podłogi, powietrze nad nimi),
##   nie w kolumnie drzwi ±2, nie w strefie wydobycia, nie na sejfie; na 1.1 ciało przy każdym nieśmiertelniku (F) i najwyżej 2 bez,
##   na 1.2 i 1.3 po 5–7 ciał;
## - modele: każdy strój × ułożenie × strona leży na gruncie (najniższy punkt skóry FLOOR_GAP nad y = 0), nie dłuższy niż
##   2,6 m (ręce za głową), biodra niżej niż 0,35 m, a uniesiona ręka czy kolano poniżej 0,9 m; sprzęt na plecach (`GEAR`) nie podpiera ciała; przeszukane odsuwa prawą dłoń (> 0,2 m), ziarno różnicuje dwa ciała w tym samym ułożeniu.
##   godot --headless --path prototype -s tools/test_corpses.gd
const Corpse3D := preload("res://scripts/corpse3d.gd")
const MAPS := ["z1_m1", "z1_m2", "z1_m3"]
const FLOOR := "#CM-="
const AIR := ".bwF"

var _fails := 0

func _ok(cond: bool, msg: String) -> void:
	print("[CORPSES] %s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		_fails += 1

func _initialize() -> void:
	for m in MAPS:
		_check_map(m)
	_go.call_deferred()

func _check_map(id: String) -> void:
	var consts: Dictionary = (load("res://scripts/maps/%s.gd" % id) as GDScript).get_script_constant_map()
	var rows: Array = consts["MAP"]
	var defs: Array = consts.get("CORPSES", [])
	var bad: Array = []
	var door_cols: Array = (consts.get("DOORS", {}) as Dictionary).keys()
	for cd in defs:
		var c := int(cd[0])
		var r := int(cd[1])
		var why := ""
		if (cd as Array).size() < 5 or not Corpse3D.POSES.has(String(cd[2])) or not Corpse3D.OUTFITS.has(String(cd[3])) or not (cd[4] is Dictionary):
			why = "pola"
		else:
			for d in [-1, 0, 1]:
				if not FLOOR.contains(String(rows[r + 1])[c + d]) or not AIR.contains(String(rows[r])[c + d]):
					why = "podłoga/powietrze"
			for dc in door_cols:
				if absi(int(dc) - c) <= 2:
					why = "drzwi %d" % int(dc)
			for z in consts.get("DIG_ZONES", []):
				if c >= int(z[0]) - 1 and c <= int(z[2]) + 1 and r >= int(z[1]) - 1 and r <= int(z[3]):
					why = "strefa wydobycia"
			for sb in consts.get("STRONGBOXES", []):
				if absi(int(sb[0]) - c) <= 1 and int(sb[1]) == r:
					why = "sejf"
		if why != "":
			bad.append("%d,%d (%s)" % [c, r, why])
	_ok(bad.is_empty(), "%s: %d zwłok na podłodze, poza drzwiami, strefami i sejfem %s" % [id, defs.size(), bad])
	if id == "z1_m1":
		var tags: Array = []
		for r in rows.size():
			for c in (rows[r] as String).length():
				if String(rows[r])[c] == "F":
					tags.append(Vector2i(c, r))
		var lonely: Array = []
		for t in tags:
			var has := defs.any(func(cd: Array) -> bool: return bool(cd[4].get("tag", false)) and int(cd[1]) == t.y and absi(int(cd[0]) - t.x) <= 1)
			if not has:
				lonely.append(t)
		var extra := defs.filter(func(cd: Array) -> bool: return not bool(cd[4].get("tag", false))).size()
		_ok(lonely.is_empty() and extra <= 2, "1.1: ciało przy każdym z %d nieśmiertelników %s, bez nieśmiertelnika %d (≤ 2)" % [tags.size(), lonely, extra])
	else:
		_ok(defs.size() >= 5 and defs.size() <= 7, "%s: 5–7 zwłok (%d)" % [id, defs.size()])

func _go() -> void:
	await process_frame
	var bad: Array = []
	var n := 0
	for out in Corpse3D.OUTFITS.keys():
		for pose in Corpse3D.POSES:
			for flip in [1.0, -1.0]:
				var c := Corpse3D.new()
				root.add_child(c)
				if not c.build(String(out), String(pose), 101, flip):
					bad.append("%s/%s bez modelu" % [out, pose])
					continue
				await process_frame
				await process_frame                              # odroczone wypieczenie w _ready
				var bb: AABB = c.skin_bounds()
				n += 1
				var low := bb.position.y
				if absf(low - Corpse3D.FLOOR_GAP) > 0.003:
					bad.append("%s/%s/%d: dół %.3f" % [out, pose, int(flip), low])
				var hips_y: float = c._node_pt(c._b["Hips"]).y
				if hips_y > 0.35:
					bad.append("%s/%s/%d: biodra %.2f" % [out, pose, int(flip), hips_y])
				if bb.end.y > 0.9:
					bad.append("%s/%s/%d: wysokość %.2f" % [out, pose, int(flip), bb.end.y])
				if bb.size.x > 2.6:
					bad.append("%s/%s/%d: długość %.2f" % [out, pose, int(flip), bb.size.x])
				c.queue_free()
	_ok(bad.is_empty() and n == Corpse3D.OUTFITS.size() * Corpse3D.POSES.size() * 2,
		"%d modeli: leżą na gruncie (%.3f m), biodra niżej niż 0,35 m, całość niżej niż 0,9 m (uniesiona ręka, kolano), krócej niż 2,6 m %s" % [n, Corpse3D.FLOOR_GAP, bad])
	# przeszukane: prawa dłoń odsunięta
	var s := Corpse3D.new()
	root.add_child(s)
	s.build("patrol", "back", 7)
	await process_frame
	await process_frame
	var hand: int = s._b["RightHand"]
	var h0: Vector3 = s._transform_under(s._sk, s) * s._gp(hand).origin
	s.set_searched(true)
	var h1: Vector3 = s._transform_under(s._sk, s) * s._gp(hand).origin
	var moved := h0.distance_to(h1)
	var low1: float = s.skin_lowest()
	_ok(moved > 0.2 and absf(low1 - Corpse3D.FLOOR_GAP) < 0.003, "przeszukane: prawa dłoń odsunięta o %.2f m, ciało dalej na gruncie (%.3f)" % [moved, low1])
	# ziarno różnicuje
	var a := Corpse3D.new()
	var b := Corpse3D.new()
	root.add_child(a)
	root.add_child(b)
	a.build("patrol", "side", 3)
	b.build("patrol", "side", 9)
	await process_frame
	await process_frame
	var head: int = a._b["Head"]
	var diff := (a._gp(head).basis.get_euler() - b._gp(head).basis.get_euler()).length()
	_ok(diff > deg_to_rad(5.0), "dwa ciała w tym samym ułożeniu różnią się głową (%.1f°)" % rad_to_deg(diff))
	print("[CORPSES] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)
