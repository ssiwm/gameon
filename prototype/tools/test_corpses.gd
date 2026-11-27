extends SceneTree
## Zwłoki w świecie (MIMIC_PLAN.md M3, corpse.gd + corpse3d.gd):
## - dane CORPSES map kampanii 1.1–1.3: pola, ułożenie i strój ze znanych, ciało na podłodze (3 kafle podłogi, powietrze nad nimi),
##   nie w kolumnie drzwi ±2, nie w strefie wydobycia, nie na sejfie; na 1.1 ciało przy każdym nieśmiertelniku (F) i najwyżej 2 bez,
##   na 1.2 i 1.3 po 5–7 ciał; gniazda Mimika-zwłok (`mimic`, M5): na 1.1 brak, na 1.2 i 1.3 ≥ 3, ≥ 4 prawdziwe na jednego, z dala od `Y`;
## - modele: każdy strój × ułożenie × strona leży na gruncie (najniższy punkt skóry FLOOR_GAP nad y = 0), nie dłuższy niż
##   2,6 m (ręce za głową), biodra niżej niż 0,37 m (szyty kombinezon hazmatu ma luz), a uniesiona ręka czy kolano poniżej 0,9 m; sprzęt na plecach (`GEAR`) nie podpiera ciała; przeszukane odsuwa prawą dłoń (> 0,2 m), ziarno różnicuje dwa ciała w tym samym ułożeniu;
## - Mimik-zwłoki (M5): ta sama poza co prawdziwe ciało w tym miejscu; w ciemności bez oczu i oddechu, w snopie połysk oczu przy głowie
##   od razu, oddech dopiero po ~1 s (klatka piersiowa się rusza), po zgaszeniu znów nieruchomy; prawdziwe zwłoki bez oczu i bez `_process`.
## - opadanie pod ciężarem (`_drape`): w każdym stroju, ułożeniu, stronie i po przeszukaniu głowa, dłonie, przedramiona, golenie, stopy
##   i tułów dotykają gruntu (najniższy punkt skóry ≤ DRAPE_MAX; przedramię i dłoń mogą leżeć na brzuchu — DRAPE_ARM_MAX) — ciało nie wisi
##   na ręce ani nie ma kończyn w powietrzu;
## - echo krzyku (M8, `mimic_echo`): klatka i głowa drgają kilka razy (zmiana kierunku), potem ciało wraca dokładnie do pozy zwłok.
## - powalony kolega (M9, poza „downed”): każdy model gracza leży na gruncie w pozie upadku, z oczami Mimika; brak pliku → mundur patrolu.
## - wstawanie Mimika-zwłok (M7, `rise`): zaczyna z pozy zwłok, wstaje płynnie (bez skoków wysokości), kończy stojąc przodem do stóp
##   (+x węzła), w miejscu stóp, ze świecącymi oczami, dłuższymi przedramionami i nakładką przemiany; `end_rise` znów kładzie ciało.
##   godot --headless --path prototype -s tools/test_corpses.gd
const Corpse3D := preload("res://scripts/corpse3d.gd")
const MAPS := ["z1_m1", "z1_m2", "z1_m3"]
const FLOOR := "#CM-="
const AIR := ".bwF"

var _fails := 0
const DRAPE_MAX := 0.05                          ## m: najniższy punkt części ciała nad gruntem (przed opadaniem dłoń 0,3 m, łokieć 0,8 m)
const DRAPE_ARM_MAX := 0.16                      ## m: przedramię i dłoń mogą leżeć na brzuchu albo biodrze (tułów ma ok. 0,2 m)

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
	# gniazda Mimika-zwłok (M5): na 1.1 żadnych; na 1.2 i 1.3 co najmniej 3 (losowanie), ≥ 4 prawdziwe na jednego Mimika (D2), z dala od
	# stojącego Mimika `Y` (≥ 8 kolumn w tym samym rzędzie — dwa przebrania obok siebie zdradzają się nawzajem)
	var nests := defs.filter(func(cd: Array) -> bool: return bool(cd[4].get("mimic", false)))
	var n_mim := int(consts.get("MIMIC_CORPSES", 1)) if not nests.is_empty() else 0
	var near_y: Array = []
	for r in rows.size():
		for c in (rows[r] as String).length():
			if String(rows[r])[c] == "Y":
				for cd in nests:
					if int(cd[1]) == r and absi(int(cd[0]) - c) < 8:
						near_y.append("%d,%d" % [int(cd[0]), int(cd[1])])
	var nest_ok: bool = nests.is_empty() if id == "z1_m1" else (nests.size() >= 3 and n_mim >= 1 and n_mim < nests.size())
	_ok(nest_ok and defs.size() - n_mim >= 4 * n_mim and near_y.is_empty(),
		"%s: gniazd `mimic` %d, Mimików-zwłok %d, prawdziwych %d (≥ 4 na jednego), przy `Y` %s" % [id, nests.size(), n_mim, defs.size() - n_mim, near_y])

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
				if hips_y > 0.37:                                   # szyty kombinezon hazmatu (luz 1,6–3,4 cm) podnosi biodra leżącego na boku o ok. 1 cm (Q4)
					bad.append("%s/%s/%d: biodra %.2f" % [out, pose, int(flip), hips_y])
				if bb.end.y > 0.9:
					bad.append("%s/%s/%d: wysokość %.2f" % [out, pose, int(flip), bb.end.y])
				if bb.size.x > 2.6:
					bad.append("%s/%s/%d: długość %.2f" % [out, pose, int(flip), bb.size.x])
				c.queue_free()
	_ok(bad.is_empty() and n == Corpse3D.OUTFITS.size() * Corpse3D.POSES.size() * 2,
		"%d modeli: leżą na gruncie (%.3f m), biodra niżej niż 0,37 m, całość niżej niż 0,9 m (uniesiona ręka, kolano), krócej niż 2,6 m %s" % [n, Corpse3D.FLOOR_GAP, bad])
	# opadanie pod ciężarem (`_drape`): żadna część nie wisi — głowa, dłonie, przedramiona, golenie, stopy i tułów dotykają gruntu
	var hang: Array = []
	var worst := 0.0
	var parts := ["Spine", "Head", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]
	for out in Corpse3D.OUTFITS.keys():
		for pose in ["back", "side", "curl"]:
			for flip in [1.0, -1.0]:
				for srch in [false, true]:
					var c := Corpse3D.new()
					root.add_child(c)
					c.build(String(out), pose, 21 + int(flip > 0.0) * 5, flip)
					if srch:
						c.set_searched(true)
					await process_frame
					for pn in parts:
						var bi: int = c._sk.find_bone(Corpse3D.PRE + pn)
						if not c._drape_parts.has(bi):
							hang.append("%s/%s: brak części %s" % [out, pose, pn])
							continue
						var lo: float = c._part_low(bi) - Corpse3D.FLOOR_GAP
						var lim := DRAPE_ARM_MAX if pn.ends_with("Hand") or pn.ends_with("ForeArm") else DRAPE_MAX
						worst = maxf(worst, lo)
						if lo > lim:
							hang.append("%s/%s/%d%s: %s %.2f m" % [out, pose, int(flip), "/p" if srch else "", pn, lo])
					c.queue_free()
	_ok(hang.is_empty(), "opadanie: w 36 ciałach (strój × ułożenie × strona × przeszukane) każda część na gruncie (najwyżej %.3f m, próg %.2f, ręka na tułowiu %.2f) %s" % [worst, DRAPE_MAX, DRAPE_ARM_MAX, hang])
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
	await _mimic_view()
	await _downed_view()
	print("[CORPSES] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

## Mimik jako powalony kolega (M9): model postaci gracza (każdy plik zestawu mpfb), poza „downed” = koniec klipu upadku bez wariantu — leży na
## gruncie jak zwłoki, nie wyżej niż ~0,9 m; strój nie wyblakły; oczy i drgnięcie jak u Mimika-zwłok; brak pliku → mundur patrolu.
func _downed_view() -> void:
	var bad: Array = []
	for g in ["male", "female"]:
		for o in ["scav", "hazmat", "medic"]:
			var path := "res://art/char3d/mpfb/%s_%s.glb" % [g, o]
			var c := Corpse3D.new()
			root.add_child(c)
			var ok: bool = c.build(path, "downed", 7, 1.0, true, false)
			await process_frame
			var bb: AABB = c.skin_bounds() if ok else AABB()
			if not ok or c.model_path != path or bb.size.y > 0.9 or absf(bb.position.y) > 0.05 or c._mimic_eyes.size() != 2:
				bad.append("%s_%s %s %.2f/%.2f" % [g, o, ok, bb.position.y, bb.size.y])
			c.queue_free()
	_ok(bad.is_empty(), "powalony kolega (M9): 6 modeli graczy leży na gruncie w pozie upadku, z oczami Mimika %s" % str(bad))
	var x := Corpse3D.new()
	root.add_child(x)
	var fb: bool = x.build("res://art/char3d/mpfb/nie_ma.glb", "downed", 7, 1.0, true, false)
	_ok(fb and x.model_path == String(Corpse3D.OUTFITS["patrol"]), "powalony kolega: brak pliku modelu → mundur patrolu (%s)" % x.model_path)
	x.queue_free()
	await process_frame

## Mimik-zwłoki w widoku (M5): poza jak prawdziwe ciało, oczy i oddech tylko w snopie.
func _mimic_view() -> void:
	var real := Corpse3D.new()
	var fake := Corpse3D.new()
	root.add_child(real)
	root.add_child(fake)
	real.build("tech", "side", 11, 1.0)
	fake.build("tech", "side", 11, 1.0, true)
	await process_frame
	await process_frame
	var head: int = fake._b["Head"]
	var same: bool = real._gp(head).origin.distance_to(fake._gp(head).origin) < 0.001
	fake.set_process(false)                                     # krok ręcznie, ze stałym czasem
	var chest: int = fake._b["Spine2"]
	var eyes_dark := false
	for _i in 10:
		fake.step_mimic(0.1)
	eyes_dark = fake._mimic_eyes.all(func(e: MeshInstance3D) -> bool: return not e.visible)
	var still := fake._sk.get_bone_pose_rotation(chest)
	fake.mimic_lit = 1.0
	for _i in 5:
		fake.step_mimic(0.1)
	var eyes_lit: bool = fake._mimic_eyes.all(func(e: MeshInstance3D) -> bool: return e.visible)
	var near_head: bool = fake._mimic_eyes.all(func(e: MeshInstance3D) -> bool: return (e.global_position - fake._model.global_transform * fake._transform_under(fake._sk, fake._model) * fake._gp(head).origin).length() < 0.25)
	var breath_early: float = fake.breath_w
	var moved := 0.0
	for _i in 40:
		fake.step_mimic(0.1)
		moved = maxf(moved, rad_to_deg(fake._sk.get_bone_pose_rotation(chest).angle_to(still)))
	var breath_late: float = fake.breath_w
	fake.mimic_lit = 0.0
	for _i in 30:
		fake.step_mimic(0.1)
	var calm: bool = fake.breath_w < 0.01 and fake._mimic_eyes.all(func(e: MeshInstance3D) -> bool: return not e.visible) 		and rad_to_deg(fake._sk.get_bone_pose_rotation(chest).angle_to(still)) < 0.5
	_ok(same and eyes_dark and eyes_lit and near_head and breath_early < 0.01 and breath_late > 0.9 and moved > 5.0 and calm
		and real._mimic_eyes.is_empty() and not real.is_processing(),
		"Mimik-zwłoki: ta sama poza %s; w ciemności bez oczu %s; w snopie oczy przy głowie %s/%s, oddech po 0,5 s %.2f, po 4,5 s %.2f (klatka %.1f°); po zgaszeniu nieruchomy %s; prawdziwe bez oczu" % [same, eyes_dark, eyes_lit, near_head, breath_early, breath_late, moved, calm])
	# echo krzyku (M8): drgnięcie, potem dokładnie poza zwłok
	var head_still := fake._sk.get_bone_pose_rotation(head)
	var jerk_max := 0.0
	var head_max := 0.0
	var flips := 0
	var last_sign := 0.0
	var w := 1.0
	while w > 0.0:
		w = maxf(0.0, w - 0.05 / 0.6)                          # enemy_mimic.gd ECHO_VIEW_S, kroki 0,05 s
		fake.mimic_echo = w
		fake.step_mimic(0.05)
		jerk_max = maxf(jerk_max, rad_to_deg(fake._sk.get_bone_pose_rotation(chest).angle_to(still)))
		head_max = maxf(head_max, rad_to_deg(fake._sk.get_bone_pose_rotation(head).angle_to(head_still)))
		var sg := signf(Corpse3D.echo_jerk(w))
		if sg != 0.0 and last_sign != 0.0 and sg != last_sign:
			flips += 1
		if sg != 0.0:
			last_sign = sg
	fake.step_mimic(0.05)
	var echo_rest: float = rad_to_deg(fake._sk.get_bone_pose_rotation(chest).angle_to(still)) + rad_to_deg(fake._sk.get_bone_pose_rotation(head).angle_to(head_still))
	_ok(jerk_max > 3.0 and head_max > 5.0 and flips >= 2 and echo_rest < 0.5,
		"Mimik-zwłoki: echo krzyku — klatka drga do %.1f°, głowa do %.1f°, %d zmian kierunku, potem poza zwłok (%.2f°)" % [jerk_max, head_max, flips, echo_rest])
	# wstawanie (M7)
	var lie_bb: AABB = fake.skin_bounds()
	var arm := func() -> float: return fake._gp(fake._b["RightForeArm"]).origin.distance_to(fake._gp(fake._b["RightHand"]).origin)
	var arm0: float = arm.call()
	fake.rise(0.0, 0.0)
	var start_bb: AABB = fake.skin_bounds()
	var hs: Array = []
	var max_jump := 0.0
	for i in 31:
		var u := float(i) / 30.0
		fake.rise(u, u * 0.75)
		var h: float = fake.skin_bounds().end.y
		if not hs.is_empty():
			max_jump = maxf(max_jump, absf(h - float(hs[-1])))
		hs.append(h)
	var up_bb: AABB = fake.skin_bounds()
	var fwd: Vector3 = fake.chest_forward()
	var eyes_on: bool = fake._mimic_eyes.all(func(e: MeshInstance3D) -> bool: return e.visible)
	var arm1: float = arm.call()
	var ov: float = float((fake._morph_mats[0] as ShaderMaterial).get_shader_parameter("amount")) if not fake._morph_mats.is_empty() else 0.0
	_ok(start_bb.size.y < lie_bb.size.y + 0.05 and up_bb.size.y > 1.4 and max_jump < 0.2 and absf(up_bb.get_center().x) < 0.45
		and fwd.x > 0.5 and eyes_on and arm1 > arm0 * 1.3 and ov > 0.8,
		"Mimik-zwłoki wstaje: z pozy zwłok (%.2f → %.2f m), płynnie (skok %.2f m), stoi %.2f m w miejscu stóp (x %.2f), przodem do stóp (%.2f), oczy %s, przedramię ×%.2f, nakładka %.2f" % [lie_bb.size.y, start_bb.size.y, max_jump, up_bb.size.y, up_bb.get_center().x, fwd.x, eyes_on, arm1 / arm0, ov])
	fake.end_rise()
	var back_bb: AABB = fake.skin_bounds()
	var ov2: float = float((fake._morph_mats[0] as ShaderMaterial).get_shader_parameter("amount")) if not fake._morph_mats.is_empty() else 0.0
	_ok(absf(back_bb.size.y - lie_bb.size.y) < 0.01 and fake.rise_u < 0.0 and is_zero_approx(ov2) and absf(arm.call() / arm0 - 1.0) < 0.01,
		"Mimik-zwłoki: `end_rise` (restart) znów leży bez przemiany (%.2f m)" % back_bb.size.y)
	real.queue_free()
	fake.queue_free()
