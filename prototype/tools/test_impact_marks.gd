extends SceneTree
## Test śladów trafień (IMPACT_MARKS_PLAN.md, scripts/impact_marks.gd): rodzaj śladu z wyglądu kafla (skała tuneli, kładka z desek,
## kratownica), rozmiar wg kalibru i rodzaju, wydłużenie i rysa wg kąta padania, wariant i obrót z punktu, scalanie bliskich śladów,
## limity wg jakości, komplet tekstur z generatora (albedo, normalna, ORM; osmalenie z emisją), osmalenie wybuchu na gruncie, ścianie
## i stropie (jedno na płaszczyznę, nic za ścianą, nic w powietrzu daleko od wszystkiego) i dziobaki odłamków poza pierścieniem.
##   godot --headless --path prototype -s tools/test_impact_marks.gd     → ostatni wiersz: [IMPACT-MARKS] PASS / FAIL

const IM := preload("res://scripts/impact_marks.gd")
const PX := 1.8 / 22.0

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[IMPACT-MARKS] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _box(parent: Node, rect: Rect2) -> void:
	var b := StaticBody2D.new()
	b.collision_layer = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rect.size
	cs.shape = sh
	b.add_child(cs)
	b.position = rect.get_center()
	parent.add_child(b)


func _run() -> void:
	# rodzaj śladu z wyglądu kafla
	_check("bryła # pod ziemią → skała", IM.kind_for("#", "dirt", true) == "rock")
	_check("bryła # na powierzchni → ziemia", IM.kind_for("#", "dirt", false) == "dirt")
	_check("kładka - (deski) → drewno, choć kroki dirt", IM.kind_for("-", "dirt", false) == "wood")
	_check("kratownica = → blacha", IM.kind_for("=", "metal", true) == "metal")
	_check("beton C → beton", IM.kind_for("C", "concrete", true) == "concrete")
	_check("lód i śnieg", IM.kind_for("i", "ice", false) == "ice" and IM.kind_for("s", "snow", false) == "dirt")
	_check("przegroda bez kafla: powierzchnia drewna → drewno", IM.kind_for("", "wood", false) == "wood")
	_check("nieznane → beton", IM.kind_for("", "", false) == "concrete")
	# rozmiar
	_check("pistolet mniejszy od karabinu, Brenneke większa", IM.caliber_scale("918", 1) < IM.caliber_scale("762", 1)
		and IM.caliber_scale("12g", 1) > IM.caliber_scale("762", 1))
	_check("śrucina drobna", IM.caliber_scale("12g", 8) < 0.6)
	_check("ziemia większy ślad, blacha mniejszy", IM.hole_size("dirt", 1.0) > IM.hole_size("concrete", 1.0)
		and IM.hole_size("metal", 1.0) < IM.hole_size("concrete", 1.0))
	_check("ślad 7,62 w beton 11–13 cm (czytelny z kamery gry, decyzja 2)", absf(IM.hole_size("concrete", 1.0) - 0.12) < 0.011)
	# kąt padania
	var perp: Array = IM.incidence(Vector2.DOWN, Vector2.UP, "concrete")
	_check("prostopadle: bez wydłużenia, bez rysy", is_equal_approx(float(perp[0]), 1.0) and not bool(perp[1]))
	var deg45: Array = IM.incidence(Vector2(1, 1).normalized(), Vector2.UP, "concrete")
	_check("45°: owal ok. 1,41 ×, bez rysy (%.2f)" % float(deg45[0]), absf(float(deg45[0]) - 1.414) < 0.02 and not bool(deg45[1]))
	var flat: Array = IM.incidence(Vector2(1, 0.15).normalized(), Vector2.UP, "metal")
	_check("ok. 9° w blachę: rysa, wydłużenie do limitu", bool(flat[1]) and is_equal_approx(float(flat[0]), IM.STRETCH_MAX))
	_check("płasko w ziemię: bez rysy (ziemia połyka kulę)", not bool(IM.incidence(Vector2(1, 0.15).normalized(), Vector2.UP, "dirt")[1]))
	_check("bez kierunku: prostopadle", is_equal_approx(float(IM.incidence(Vector2.ZERO, Vector2.UP, "rock")[0]), 1.0))
	# wariant i obrót
	_check("wariant z punktu powtarzalny", IM.variant(Vector2(100.25, 40.5), 3) == IM.variant(Vector2(100.25, 40.5), 3))
	var vs := {}
	for i in 40:
		vs[IM.variant(Vector2(17.0 * i, 3.0 * i), 3)] = true
	_check("warianty się zmieniają (%d z 3)" % vs.size(), vs.size() == 3)
	_check("obrót w [0, 2π)", IM.spin(Vector2(5, 7)) >= 0.0 and IM.spin(Vector2(5, 7)) < TAU)
	# scalanie
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(30, 0)])
	var kinds := PackedStringArray(["concrete", "dirt", "concrete"])
	var size_px := IM.hole_size("concrete", 1.0) / PX
	_check("bliski ślad tego samego rodzaju — scalenie", IM.merge_index(pts, kinds, Vector2(0.3, 0.2), "concrete", size_px) == 0)
	_check("bliski innego rodzaju — nowy ślad", IM.merge_index(pts, kinds, Vector2(10.2, 0), "concrete", size_px) == -1)
	_check("daleki — nowy ślad", IM.merge_index(pts, kinds, Vector2(5, 0), "concrete", size_px) == -1)
	# limity
	_check("limity rosną z jakością", IM.limit(0) < IM.limit(1) and IM.limit(1) < IM.limit(2) and IM.limit(2) == 160)
	_check("limit osmaleń", IM.scorch_limit(0) < IM.scorch_limit(2))
	# tekstury
	var missing := PackedStringArray()
	for n in IM.all_names():
		var t: Dictionary = IM.textures(n)
		if not (t.has("albedo") and t.has("normal") and t.has("orm")):
			missing.append(n)
		elif n.begins_with("scorch_") and not t.has("emission"):
			missing.append(n + " (emisja)")
	_check("tekstury wszystkich %d śladów (albedo, normalna, ORM)%s" % [IM.all_names().size(), "" if missing.is_empty() else ": brak " + ", ".join(missing)],
		missing.is_empty())
	_check("nazwa rysy dla ziemi spada na beton (brak tekstury rysy w ziemi)", IM.hole_name("dirt", true, false, 0) == "graze_concrete_0")
	_check("nazwa gniazda śrutu w lodzie spada na beton", IM.hole_name("ice", false, true, 1) == "cluster_concrete_1")
	# osmalenie wybuchu: pokój 10 × 5 kafli (podłoga, strop, ściany), za prawą ścianą drugi pokój
	var room := Node2D.new()
	root.add_child(room)
	_box(room, Rect2(0, 80, 320, 16))          # podłoga y = 80
	_box(room, Rect2(0, 0, 320, 16))           # strop  y = 16
	_box(room, Rect2(0, 16, 16, 64))           # lewa ściana x = 16
	_box(room, Rect2(160, 16, 16, 64))         # prawa ściana x = 160 (za nią druga połowa)
	await physics_frame
	await physics_frame
	var space := room.get_world_2d().direct_space_state
	var floor_only: Array = IM.blast_marks(space, Vector2(100, 76), 48.0, 12, PX)
	_check("wybuch na podłodze: osmalenie na podłodze (%d)" % floor_only.size(), floor_only.size() >= 1
		and (floor_only[0]["normal"] as Vector2).dot(Vector2.UP) > 0.9)
	var nf := 0
	for g in floor_only:
		if (g["normal"] as Vector2).dot(Vector2.UP) > 0.9:
			nf += 1
	_check("jedno osmalenie na płaszczyznę podłogi (%d)" % nf, nf == 1)
	var wall: Array = IM.blast_marks(space, Vector2(150, 50), 48.0, 12, PX)
	var nw := 0
	var behind := false
	for g in wall:
		if (g["normal"] as Vector2).dot(Vector2.LEFT) > 0.9:
			nw += 1
		if (g["pos"] as Vector2).x > 176.0:
			behind = true
	_check("wybuch w powietrzu przy ścianie: osmalenie na ścianie (%d)" % nw, nw == 1)
	_check("nic za ścianą", not behind)
	var ceil: Array = IM.blast_marks(space, Vector2(80, 22), 48.0, 12, PX)
	var nc := 0
	for g in ceil:
		if (g["normal"] as Vector2).dot(Vector2.DOWN) > 0.9:
			nc += 1
	_check("wybuch pod stropem: osmalenie na stropie (%d)" % nc, nc == 1)
	_check("wybuch daleko od wszystkiego: brak osmalenia", IM.blast_marks(space, Vector2(100, 400), 48.0, 12, PX).is_empty())
	var near: Dictionary = floor_only[0]
	var far: Array = IM.blast_marks(space, Vector2(100, 50), 48.0, 12, PX)
	var far_floor := 0.0
	for g in far:
		if (g["normal"] as Vector2).dot(Vector2.UP) > 0.9:
			far_floor = float(g["size_m"])
	_check("dalej od podłogi — mniejsze osmalenie (%.2f m → %.2f m)" % [float(near["size_m"]), far_floor], far_floor > 0.0 and far_floor < float(near["size_m"]))
	_check("osmalenie granatu ok. 2–3 m (%.2f m)" % float(near["size_m"]), float(near["size_m"]) >= 1.6 and float(near["size_m"]) <= IM.SCORCH_MAX_M)
	var pk: Array = IM.pock_marks(space, Vector2(100, 70), 48.0)
	var pk_ok := pk.size() >= 2
	for p in pk:
		if (p["pos"] as Vector2).distance_to(Vector2(100, 70)) < 24.0:
			pk_ok = false
	_check("dziobaki odłamków poza pierścieniem (%d)" % pk.size(), pk_ok)
	_check("dziobaki powtarzalne z punktu", IM.pock_marks(space, Vector2(100, 70), 48.0).size() == pk.size())
	room.queue_free()
	print("[IMPACT-MARKS] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)
