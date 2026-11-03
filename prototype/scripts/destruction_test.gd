extends "res://scripts/stalker_test.gd"
## Test headless zniszczalnych elementów (DESTRUCTION_PLAN.md D0):
##
##   godot --headless --path . -- --host --mission=z1_m2 --destructiontest --autoquit=40
##
## 1. Maska uszkodzeń (`damage_mask.gd`): wysokość odcisku wg stopnia, brzeg, łączenie przez max, kolejność plam bez znaczenia.
## 2. Plamy trafień (`breakable.gd`): serwer liczy plamę (punkt w obrębie elementu, promień wg rodzaju trafienia, stopień wg siły),
##    trafienia z jednej klatki idą jedną paczką, kolejne w oknie SPLAT_GAP czekają; trafienie, które nie rani, nie zostawia plamy.
## 3. Dołączający: stan z `_splat_sync` daje te same plamy i tę samą maskę co u serwera; limit MAX_SPLATS.
## 4. Rozbicie: element znika, zapis w `_opened_walls`, odroczona paczka nie sypie błędów.
## 5. Stan zniszczeń (level.gd): reset po rozbiciu (ściana, kafle, nawigacja, plamy), migawka z przebudzenia bossa (plamy i rozbite),
##    ta sama klatka co rozbicie, restart misji (main._restart_mission) odbudowuje ścianę.
## 6. Rozpad na bryły: zestaw pre-fraktury cegły (`tools/fracture_gen.py`) — bryły wypełniają kostkę, mają przekrój; plan brył z ziarna
##    taki sam u każdego peera; rozbicie wypuszcza bryły i drobne odłamki.
## 7. Rzut mapy w HUD (`hud_minimap.gd`): rozbita i odbudowana ściana przemalowuje tylko swoje kafle — obraz taki sam jak pełna budowa.
## 8. Skrzynia `k` (prop.gd, D1): pęka od piątego pocisku pistoletu, płomień jej nie rani, drzazgi z pre-fraktury desek (wydłużone,
##    ze świeżym przełomem; plan z ziarna),
##    hałas, łup (złom 1–2 w ok. 60% skrzyń, bateria rzadko, nic w Nocnym Dyżurze), wybuch beczki rozbija bliską skrzynię, dalszą nie,
##    reset po wipe'ie; beczka zostawia wrak (osiada na podłożu, dołączający dostaje punkt od serwera, reset).
## 9. Lampy misji `I` (lamp.gd, D1): na mapie zapalone, gracz w ich świetle widoczny dla Stalkera (`Lights.lamp_lit_player`), ćma krąży
##    przy zapalonej; promień kuli trafia klosz i leci dalej, trafienie tłucze lampę (światło, hałas, szkło), stłuczona chowa gracza i nie
##    wabi ćmy, wybuch też tłucze, reset zapala, dołączający dostaje stłuczoną bez efektów.
## Mapa 1.2 (ma zamurowane przejście), reszta świata wyciszona jak w stalker_test.gd. Wynik: linie [DESTRUCTION-TEST] i kod wyjścia.

const Breakable := preload("res://scripts/breakable.gd")
const DamageMask := preload("res://scripts/damage_mask.gd")
const Level3D := preload("res://scripts/level3d.gd")
const Combat := preload("res://scripts/combat.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")
const MiniMap := preload("res://scripts/hud_minimap.gd")
const Prop := preload("res://scripts/prop.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Lights := preload("res://scripts/lights.gd")

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[DESTRUCTION-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[DESTRUCTION-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[DESTRUCTION-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	stalker = level.get_node_or_null("Stalker")
	check("mapa ma gracza", player != null)
	if player == null:
		_finish()
		return
	_isolate()
	if stalker != null:
		stalker.queue_free()
	var real := level.get_node_or_null("BrickWall1")
	check("zamurowane przejście na mapie 1.2: materiał %s, %.0f HP" % [str(real.get("mat_id")) if real else "-", float(real.get("hp")) if real else 0.0],
		real != null and String(real.mat_id) == "brick" and float(real.hp) == 120.0)
	_mask()
	await _splats()
	await _break()
	await _state()
	await _fracture()
	await _minimap()
	await _crates()
	await _lamps()
	_finish()

# ---------------------------------------------------------------- 1. maska

func _mask() -> void:
	var w_m := Level3D.T
	var h_m := Level3D.T * 3.0
	var img := DamageMask.create(w_m, h_m)
	check("maska: %d × %d tekseli dla %.2f × %.2f m (2,5 cm na teksel), pusta" % [img.get_width(), img.get_height(), w_m, h_m],
		img.get_width() == ceili(w_m / DamageMask.TEXEL_M) and img.get_height() == ceili(h_m / DamageMask.TEXEL_M) and img.get_pixel(5, 5).r == 0.0)
	var peaks: Array = []
	for deg in 3:
		var one := DamageMask.create(w_m, h_m)
		DamageMask.stamp(one, 0.5, 0.5, 0.15, deg, w_m, h_m)
		peaks.append(snappedf(_max_r(one), 0.01))
	check("maska: szczyt odcisku wg stopnia 0 / 1 / 2 = %s (odprysk, wyszczerbienie, wyrwa)" % str(peaks),
		absf(peaks[0] - 0.55) < 0.03 and absf(peaks[1] - 0.8) < 0.03 and absf(peaks[2] - 1.0) < 0.03)
	DamageMask.stamp(img, 0.5, 0.5, 0.1, 2, w_m, h_m)
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var edge_r := 0.1 / DamageMask.TEXEL_M
	check("maska: środek plamy 1,0 (%.2f), za promieniem 0 (%.2f)" % [img.get_pixel(cx, cy).r, img.get_pixel(cx, mini(img.get_height() - 1, cy + ceili(edge_r) + 2)).r],
		img.get_pixel(cx, cy).r > 0.95 and img.get_pixel(cx, mini(img.get_height() - 1, cy + ceili(edge_r) + 2)).r == 0.0)
	DamageMask.stamp(img, 0.5, 0.5, 0.1, 0, w_m, h_m)
	check("maska: słabsza plama na wyrwie jej nie spłyca (max)", img.get_pixel(cx, cy).r > 0.95)
	var a := DamageMask.create(w_m, h_m)
	var b := DamageMask.create(w_m, h_m)
	var seq := [[0.3, 0.2, 0.08, 1], [0.6, 0.25, 0.12, 2], [0.45, 0.7, 0.05, 0]]
	for s in seq:
		DamageMask.stamp(a, s[0], s[1], s[2], s[3], w_m, h_m)
	seq.reverse()
	for s in seq:
		DamageMask.stamp(b, s[0], s[1], s[2], s[3], w_m, h_m)
	check("maska: kolejność plam nie zmienia wyniku", a.get_data() == b.get_data())

func _max_r(img: Image) -> float:
	var best := 0.0
	for j in img.get_height():
		for i in img.get_width():
			best = maxf(best, img.get_pixel(i, j).r)
	return best

# ---------------------------------------------------------------- 2–3. plamy i dołączający

func _wall(wname: String, dx: float, mat := "brick") -> Node2D:
	var w: Node2D = Breakable.new()
	w.name = wname
	w.mat_id = mat
	w.rows = 3
	w.global_position = player.global_position + Vector2(dx, 0.0)
	level.add_child(w)
	return w

func _hit(w: Node2D, wid: int, amount: float, type: String, pos: Vector2) -> Dictionary:
	return Combat.apply(w, Combat.make_info(wid, amount, pos, Vector2.RIGHT, 1, type))

func _splats() -> void:
	var w := _wall("DWall1", 40.0)
	await _frames(0.1)
	var pick: RefCounted = Weapons.def(Weapons.KILOF)
	var c: Vector2 = w.call("body_center")
	_hit(w, Weapons.KILOF, pick.damage, "melee", c)
	_hit(w, Weapons.KILOF, pick.damage, "melee", c)
	check("paczka: przed końcem klatki nic nie wyszło (paczek %d, plam %d)" % [w.batches_sent, w.splat_total], w.batches_sent == 0 and w.splat_total == 0)
	await get_tree().process_frame
	await get_tree().process_frame
	check("paczka: dwa ciosy kilofem z jednej klatki = 1 paczka, 2 plamy (paczek %d, plam %d)" % [w.batches_sent, w.splat_total],
		w.batches_sent == 1 and w.splat_total == 2 and w.splats.size() == 8)
	var in_rect := true
	for k in w.splats.size() / 4:
		in_rect = in_rect and w.splats[k * 4] >= 0.0 and w.splats[k * 4] <= 1.0 and w.splats[k * 4 + 1] >= 0.0 and w.splats[k * 4 + 1] <= 1.0
	check("plamy kilofa: w obrębie ściany, promień %.0f px, stopień %d (cios %.0f z %.0f HP — wyrwa), rozrzut (%s)" % [w.splats[2], int(w.splats[3]), pick.damage, w.max_hp(), str(w.splats)],
		in_rect and is_equal_approx(w.splats[2], Breakable.SPLAT_R["pick"]) and int(w.splats[3]) == 2 and int(w.splats[7]) == 2
		and Vector2(w.splats[0], w.splats[1]) != Vector2(w.splats[4], w.splats[5]))
	var hp_after: float = w.hp
	check("wytrzymałość: %.0f HP po dwóch ciosach" % hp_after, absf(hp_after - (w.max_hp() - 2.0 * pick.damage)) < 0.01)
	# wybuch tuż obok ściany: punkt przycięty do jej brzegu, słabe trafienie = odprysk; w oknie SPLAT_GAP czeka
	var rc: Rect2 = w.call("hit_rect")
	w.set("_last_flush_ms", Time.get_ticks_msec())       # jak tuż po paczce (czas klatek headless bywa różny)
	_hit(w, Weapons.GNIEW4, 5.0, "blast", Vector2(rc.end.x + 30.0, rc.position.y + 10.0))
	await get_tree().process_frame
	var waited: bool = w.batches_sent == 1
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("paczka: trafienie w oknie %.1f s czeka (po klatce paczek 1: %s), potem druga paczka (%d)" % [Breakable.SPLAT_GAP, str(waited), w.batches_sent],
		waited and w.batches_sent == 2 and w.splat_total == 3)
	check("plama wybuchu: przy prawym brzegu (u %.2f), odprysk (stopień %d), promień %.0f px" % [w.splats[8], int(w.splats[11]), w.splats[10]],
		is_equal_approx(w.splats[8], 1.0) and int(w.splats[11]) == 0 and is_equal_approx(w.splats[10], Breakable.SPLAT_R["blast"]))
	var r_bullet := _hit(w, Weapons.M83, 8.0, "bullet", c)
	_hit(w, Weapons.MACZETA, 30.0, "melee", c)
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("kula i maczeta w cegłę: bez obrażeń i bez plamy (plam %d, paczek %d)" % [w.splat_total, w.batches_sent],
		not bool(r_bullet.get("hit", true)) and w.splat_total == 3 and w.batches_sent == 2)
	var dl := _wall("DWall2", 80.0, "planks")
	await _frames(0.1)
	_hit(dl, Weapons.SPREAD12, 4.0, "bullet", dl.call("body_center"))
	await _frames(0.1)
	check("deski: śrut zostawia plamę śrutu (promień %.1f px, stopień %d)" % [dl.splats[2] if dl.splats.size() > 2 else -1.0, int(dl.splats[3]) if dl.splats.size() > 3 else -1],
		dl.splats.size() == 4 and is_equal_approx(dl.splats[2], Breakable.SPLAT_R["pellet"]) and int(dl.splats[3]) == 0)
	dl.queue_free()
	# dołączający: ten sam stan, ta sama maska
	var j := _wall("DWall3", 120.0)
	await _frames(0.1)
	j._splat_sync(w.splats, w.hp / w.max_hp())
	check("dołączający: te same plamy (%d) i ta sama wytrzymałość (%.0f / %.0f HP)" % [j.splat_total, j.hp, w.hp],
		j.splats == w.splats and j.splat_total == 3 and absf(j.hp - w.hp) < 0.01)
	var ma := _mask_of(w)
	var mb := _mask_of(j)
	check("dołączający: maska identyczna z maską serwera", ma.get_data() == mb.get_data() and _max_r(ma) > 0.9)
	var many := PackedFloat32Array()
	for k in Breakable.MAX_SPLATS + 6:
		many.append_array([0.5, float(k) / 100.0, 2.0, 0.0])
	j._add_splats(many, 0.5)
	check("limit: pamiętane %d ostatnich plam z %d (najstarsze wypadają z listy)" % [j.splats.size() / 4, j.splat_total],
		j.splats.size() == Breakable.MAX_SPLATS * 4 and j.splat_total == 3 + Breakable.MAX_SPLATS + 6 and is_equal_approx(j.splats[j.splats.size() - 3], float(Breakable.MAX_SPLATS + 5) / 100.0))
	j.queue_free()
	w.queue_free()
	await _frames(0.1)

## Maska z plam elementu tak, jak odciska ją widok 3D.
func _mask_of(w: Node2D) -> Image:
	var w_m := Level3D.T
	var h_m := Level3D.T * float(w.rows)
	var img := DamageMask.create(w_m, h_m)
	for k in w.splats.size() / 4:
		DamageMask.stamp(img, w.splats[k * 4], w.splats[k * 4 + 1], w.splats[k * 4 + 2] * Level3D.PX, int(w.splats[k * 4 + 3]), w_m, h_m)
	return img

# ---------------------------------------------------------------- 4. rozbicie

func _break() -> void:
	var w := _wall("DWall4", 40.0)
	await _frames(0.1)
	var pick: RefCounted = Weapons.def(Weapons.KILOF)
	var c: Vector2 = w.call("body_center")
	var swings := 0
	while is_instance_valid(w) and not w.is_queued_for_deletion() and swings < 6:
		_hit(w, Weapons.KILOF, pick.damage, "melee", c)
		swings += 1
	await _frames(Breakable.SPLAT_GAP + 0.1)
	check("rozbicie: %d ciosy, ściana znika, zapis w `_opened_walls`, odroczona paczka bez błędów" % swings,
		swings == 3 and not is_instance_valid(w) and level._opened_walls.has("DWall4"))
	level._opened_walls.erase("DWall4")

# ---------------------------------------------------------------- 5. stan zniszczeń

func _real() -> Node2D:
	var w := level.get_node_or_null("BrickWall1") as Node2D
	return w if w != null and not w.is_queued_for_deletion() else null

func _cells_solid() -> bool:
	var ok := true
	for cell in level._wall_cells.keys():
		ok = ok and level._is_solid(cell.x, cell.y)
	return ok and not level._wall_cells.is_empty()

func _state() -> void:
	var pick: RefCounted = Weapons.def(Weapons.KILOF)
	var w := _real()
	check("stan: ściana 1.2 stoi na starcie (%d kafli bryły)" % level._wall_cells.size(), w != null and _cells_solid())
	if w == null:
		return
	level.break_wall("BrickWall1")
	await _frames(0.1)
	check("stan: po rozbiciu kafle wolne, ściana w `_opened_walls`", _real() == null and level._wall_cells.is_empty() and level._opened_walls.has("BrickWall1"))
	level.reset_breakables()
	await _frames(0.1)
	w = _real()
	check("reset: ściana znów stoi (%.0f HP), kafle bryłą, lista rozbitych pusta, nawigacja = pełna budowa (%s)" % [float(w.hp) if w else 0.0, level.nav_diff_vs_full()],
		w != null and float(w.hp) == 120.0 and _cells_solid() and level._opened_walls.is_empty() and level.nav_diff_vs_full() == "")
	# punkt kontrolny z ranną ścianą
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	await _frames(0.15)
	level.save_breakables_checkpoint()
	var cp: Dictionary = level.breakables_checkpoint()
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	await _frames(0.15)
	check("migawka: ranna ściana zapisana (plam %d), potem rozbita" % (cp["damage"].get("BrickWall1", [PackedFloat32Array()])[0] as PackedFloat32Array).size(),
		(cp["damage"].get("BrickWall1", [PackedFloat32Array()])[0] as PackedFloat32Array).size() == 4 and _real() == null and (cp["opened"] as PackedStringArray).is_empty())
	level.reset_breakables(cp)
	await _frames(0.1)
	w = _real()
	check("punkt kontrolny: ściana wraca ranna jak przy przebudzeniu (%.0f HP, plam %d)" % [float(w.hp) if w else 0.0, int(w.splat_total) if w else -1],
		w != null and absf(float(w.hp) - (120.0 - pick.damage)) < 0.01 and int(w.splat_total) == 1 and (w.splats as PackedFloat32Array) == (cp["damage"]["BrickWall1"][0] as PackedFloat32Array)
		and _cells_solid() and level.nav_diff_vs_full() == "")
	level.reset_breakables()
	await _frames(0.05)
	w = _real()
	check("reset czysty: bez plam (%d) i pełne HP (%.0f), epoka rośnie (maska widoku 3D od zera)" % [int(w.splat_total), float(w.hp)],
		int(w.splat_total) == 0 and (w.splats as PackedFloat32Array).is_empty() and float(w.hp) == 120.0 and int(w.damage_epoch) > 0)
	# punkt kontrolny z rozbitą ścianą
	level.break_wall("BrickWall1")
	await _frames(0.1)
	level.save_breakables_checkpoint()
	level.reset_breakables()
	await _frames(0.1)
	var back := _real() != null
	level.reset_breakables(level.breakables_checkpoint())
	await _frames(0.1)
	check("punkt kontrolny: rozbita przy przebudzeniu zostaje rozbita (po czystym resecie stała: %s), nawigacja = pełna budowa" % str(back),
		back and _real() == null and level._opened_walls.has("BrickWall1") and level._wall_cells.is_empty() and level.nav_diff_vs_full() == "")
	# rozbicie i odbudowa w jednej klatce: nowa ściana dostaje własną nazwę
	level.reset_breakables()
	await _frames(0.1)
	level.break_wall("BrickWall1")
	level.reset_breakables()
	await _frames(0.1)
	check("ta sama klatka: rozbita i odbudowana ściana ma nazwę BrickWall1 (dzieci: %s)" % str(level.get_children().filter(func(c: Node) -> bool: return String(c.name).contains("BrickWall")).map(func(c: Node) -> String: return String(c.name))),
		_real() != null and _cells_solid())
	# restart misji (wipe): rozbita ściana wraca
	level.break_wall("BrickWall1")
	await _frames(0.1)
	main._restart_mission(false)
	await _frames(0.5)
	check("wipe (main._restart_mission): rozbita ściana znów stoi, kafle bryłą", _real() != null and _cells_solid() and level._opened_walls.is_empty())

# ---------------------------------------------------------------- 6. rozpad na bryły

func _fracture() -> void:
	var path := Level3D.MODEL_DIR + "fracture_brick.glb"
	var meshes: Array = []
	var inner := 0
	var inside := true
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("chunk_*", "MeshInstance3D", true, false):
			var msh := (n as MeshInstance3D).mesh
			meshes.append(msh)
			var box: AABB = (n as Node3D).transform * msh.get_aabb()
			inside = inside and AABB(Vector3(-0.501, -0.501, -0.501), Vector3(1.002, 1.002, 1.002)).encloses(box)
			for si in msh.get_surface_count():
				var m := msh.surface_get_material(si)
				if m != null and String(m.resource_name) == "inner":
					inner += 1
					break
		inst.free()
	check("pre-fraktura cegły: %d brył (plan 6–14), każda z przekrojem (%d), wszystkie w kostce 1 m (%s)" % [meshes.size(), inner, str(inside)],
		meshes.size() >= 6 and meshes.size() <= 14 and inner == meshes.size() and inside)
	var w := _wall("DWall5", 40.0)
	await _frames(0.1)
	var a: Array = w.chunk_plan(123)
	var rc: Rect2 = w.hit_rect()
	var in_rect := true
	for ch in a:
		in_rect = in_rect and rc.grow(1.0).has_point(ch[0])
	check("plan brył: %d brył cegły w obrysie ściany, to samo ziarno = ten sam plan (każdy peer), inne ziarno = inny" % a.size(),
		a.size() == int(Breakable.MATERIALS["brick"]["chunks"]) and in_rect and str(a) == str(w.chunk_plan(123)) and str(a) != str(w.chunk_plan(124)))
	var before := Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x)).size()
	var pick: RefCounted = Weapons.def(Weapons.KILOF)
	for i in 3:
		_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	await _frames(0.15)
	var after := Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x)).size()
	var want := int(Breakable.MATERIALS["brick"]["chunks"]) + int(Breakable.MATERIALS["brick"]["chips"])
	check("rozbicie: %d nowych odłamków (bryły + drobne, %d oczekiwanych, limit %d)" % [after - before, want, Vfx.MAX_DEBRIS],
		after - before == mini(want, Vfx.MAX_DEBRIS - before))
	level._opened_walls.erase("DWall5")

# ---------------------------------------------------------------- 7. rzut mapy w HUD

func _minimap() -> void:
	var mm: Node = MiniMap.new()
	add_child(mm)
	mm._lvl = level
	mm._build(true)
	var ok := true
	var steps := 0
	for st in ["break", "reset"]:
		if st == "break":
			level.break_wall("BrickWall1")
		else:
			level.reset_breakables()
		await _frames(0.1)
		mm._repaint_walls(level._wall_cells)
		var part: Image = (mm._base as Image).duplicate()
		mm._build(false)
		ok = ok and part.get_data() == (mm._base as Image).get_data()
		steps += 1
	check("rzut mapy: po rozbiciu i odbudowie przemalowane kafle ściany = pełna budowa obrazu (%d kroki)" % steps, ok and steps == 2)
	mm.queue_free()

# ---------------------------------------------------------------- 8. skrzynia (D1)

var _crate_n := 0

func _crate(at: Vector2, kind := "crate") -> RigidBody2D:
	_crate_n += 1
	var pr: RigidBody2D = Prop.new()
	pr.kind = kind
	pr.name = "TCrate%d" % _crate_n
	level.add_child(pr)
	pr.global_position = at
	pr.freeze = true                                       # bez fizyki: liczą się obrażenia, łup i efekty
	return pr

func _bullet(c: Node2D, amount: float, type := "bullet") -> void:
	Combat.apply(c, Combat.make_info(Weapons.KILOF, amount, c.global_position + Vector2(-6, -7), Vector2.RIGHT, 1, type))

func _items_since(serial: int) -> Array:
	var out: Array = []
	for i in range(serial + 1, int(level._pickup_serial) + 1):
		var it := level.get_node_or_null("Item%d" % i)
		if it != null and not it.is_queued_for_deletion():
			out.append(it)
	return out

func _crates() -> void:
	var pieces := 0
	var cut := 0
	var path := Level3D.MODEL_DIR + "fracture_planks.glb"
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		for nd in inst.find_children("chunk_*", "MeshInstance3D", true, false):
			var msh := (nd as MeshInstance3D).mesh
			var aabb := msh.get_aabb()
			pieces += 1
			for si in msh.get_surface_count():
				var m := msh.surface_get_material(si)
				if m != null and String(m.resource_name) == "inner" and aabb.size.x > 2.0 * maxf(aabb.size.y, aabb.size.z):
					cut += 1
					break
		inst.free()
	check("pre-fraktura desek: %d drzazg, wydłużone (dłuższe niż 2× szerokość) i z przełomem: %d" % [pieces, cut], pieces >= 3 and cut == pieces)
	var base := player.global_position + Vector2(0, -3000)        # z dala od gracza i ścian (wybuch beczki rani w promieniu)
	var c := _crate(base)
	await _frames(0.05)
	check("skrzynia: %.0f HP (pistolet 8 → pięć trafień)" % float(c.hp), float(c.hp) == Prop.CRATE_HP)
	for i in 4:
		_bullet(c, 8.0)
	_bullet(c, 20.0, "fire")
	check("skrzynia: cztery pociski i płomień — stoi (%.0f HP)" % float(c.hp), not c.exploded and float(c.hp) == Prop.CRATE_HP - 32.0)
	var a: Array = c.chunk_plan(77, 1.0)
	check("drzazgi: plan %d brył z ziarna (ten sam u każdego peera), lecą od uderzenia" % a.size(),
		a.size() == Prop.CRATE_CHUNKS and str(a) == str(c.chunk_plan(77, 1.0)) and str(a) != str(c.chunk_plan(78, 1.0))
		and float(a.reduce(func(acc: float, ch: Array) -> float: return acc + (ch[1] as Vector2).x, 0.0)) > 0.0)
	var noise0 := float(NoiseMgr.level)
	var old := {}
	for d in Vfx._debris:
		if is_instance_valid(d):
			old[(d as Object).get_instance_id()] = true
	var serial := int(level._pickup_serial)
	_bullet(c, 8.0)
	await _frames(0.1)
	var fresh := Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not old.has((x as Object).get_instance_id())).size()
	check("skrzynia: piąty pocisk — pęka (znika, bez kolizji), %d nowych odłamków (drzazgi + wióry), hałas %.1f → %.1f" % [fresh, noise0, float(NoiseMgr.level)],
		c.exploded and not c.visible and c.collision_layer == 0 and fresh == Prop.CRATE_CHUNKS + Prop.CRATE_CHIPS and float(NoiseMgr.level) > noise0)
	for it in _items_since(serial):
		it.queue_free()
	c.reset_enemy()
	await _frames(0.1)
	check("skrzynia po wipe'ie: wraca cała (%.0f HP, widoczna, kolizja)" % float(c.hp),
		not c.exploded and c.visible and c.collision_layer == Prop.LAYER and float(c.hp) == Prop.CRATE_HP)
	c.queue_free()
	# łup: 40 skrzyń z ustalonym ziarnem losowania
	seed(87)
	var n := 40
	var scrap := 0
	var scrap_bad := 0
	var batteries := 0
	serial = int(level._pickup_serial)
	for i in n:
		var ci := _crate(base + Vector2(200.0 + 120.0 * i, 0.0))
		ci.shatter()
	await _frames(0.1)
	for it in _items_since(serial):
		if String(it.kind) == "scrap":
			scrap += 1
			scrap_bad += 0 if int(it.rounds) >= 1 and int(it.rounds) <= 2 else 1
		elif String(it.kind) == "battery":
			batteries += 1
		it.queue_free()
	var p_scrap := minf(1.0, Prop.CRATE_SCRAP * Difficulty.m("drops"))
	if Scrap.enabled():
		check("łup: złom z %d / %d skrzyń (szansa %.2f), po 1–2 sztuki; bateria z %d" % [scrap, n, p_scrap, batteries],
			absf(float(scrap) / n - p_scrap) < 0.2 and scrap_bad == 0 and batteries <= n / 5)
	else:
		info("łup: złom wyłączony w tym trybie (Scrap.enabled = false) — baterii %d / %d" % [batteries, n])
	NightShift.active = true
	serial = int(level._pickup_serial)
	for i in 10:
		_crate(base + Vector2(200.0 + 120.0 * i, 200.0)).shatter()
	await _frames(0.1)
	NightShift.active = false
	check("łup: Nocny Dyżur — nic ze skrzyń (%d przedmiotów)" % _items_since(serial).size(), _items_since(serial).is_empty())
	# wybuch beczki
	var bp := base + Vector2(-600.0, 0.0)
	var barrel := _crate(bp, "barrel")
	var near := _crate(bp + Vector2(20.0, 0.0))
	var far := _crate(bp + Vector2(-52.0, 0.0))
	await _frames(0.05)
	var at0 := barrel.global_position
	barrel.explode()
	await _frames(0.1)
	check("wybuch beczki: skrzynia 20 px obok pęka, 52 px dalej tylko odlatuje", near.exploded and not far.exploded)
	await _frames(0.05)
	check("wrak beczki: zostaje (wreck), bez kolizji, w powietrzu bez podłoża na miejscu wybuchu (%s → %s)" % [at0, barrel.global_position],
		barrel.exploded and barrel.wreck and barrel.collision_layer == 0 and barrel.global_position.distance_to(at0) < 1.0)
	barrel.reset_enemy()
	await _frames(0.1)
	check("wrak beczki po wipe'ie: cała beczka wraca (bez wraku, widoczna, kolizja)",
		not barrel.exploded and not barrel.wreck and barrel.visible and barrel.collision_layer == Prop.LAYER)
	for x in [barrel, near, far]:
		x.queue_free()
	# wrak na podłożu: beczka 40 px nad graczem (bez wybuchu — `_gone` jak u dołączającego bez punktu); gracz nie jest w masce podłoża
	var top := player.global_position + Vector2(0.0, -40.0)
	var floor_hit := level.get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(top, top + Vector2(0.0, 320.0), 1 | 16))
	var wb := _crate(top, "barrel")
	await _frames(0.05)
	wb._gone()
	await _frames(0.1)
	var want: Vector2 = floor_hit.get("position", top)
	check("wrak beczki: osiada na podłożu pod sobą (%.0f → %.0f, podłoże %.0f)" % [top.y, wb.global_position.y, want.y],
		wb.wreck and not floor_hit.is_empty() and wb.global_position.distance_to(want) < 1.0 and is_zero_approx(wb.rotation))
	wb._gone_rpc(top + Vector2(0.0, 7.0))
	await _frames(0.1)
	check("wrak beczki u dołączającego: w punkcie od serwera (send_state_to → _gone_rpc)",
		wb.wreck and wb.global_position.distance_to(top + Vector2(0.0, 7.0)) < 1.0)
	wb.queue_free()

# ---------------------------------------------------------------- 9. lampy misji (D1)

func _debris_ids() -> Dictionary:
	var ids := {}
	for d in Vfx._debris:
		if is_instance_valid(d):
			ids[(d as Object).get_instance_id()] = true
	return ids

func _lamps() -> void:
	var lamps := get_tree().get_nodes_in_group("mission_lamps")
	var lamp: Node2D = level.get_node_or_null("MissionLamp2")
	check("lampy misji na 1.2: %d (znacznik I), zapalone, klosz w warstwie obiektów" % lamps.size(),
		lamps.size() == 3 and lamp != null and lamps.all(func(l: Node) -> bool: return l.lit and l._light.enabled)
		and lamp.get_node_or_null("Bulb") != null and int(lamp.get_node("Bulb").collision_layer) == 32)
	if lamp == null:
		return
	var space := level.get_world_2d().direct_space_state
	var bulb: Vector2 = lamp.bulb_pos()
	var fl := space.intersect_ray(PhysicsRayQueryParameters2D.create(bulb, bulb + Vector2(0.0, 400.0), 1 | 16))
	var feet: Vector2 = fl.get("position", bulb + Vector2(0.0, 48.0))
	player.flashlight = false
	player.global_position = feet + Vector2(0.0, -1.0)
	player.velocity = Vector2.ZERO
	await _frames(0.05)
	var c := player.global_position + Vector2(0.0, -9.0)
	var eye := c + Vector2(-112.0, -11.0)
	if not Combat.clear_line(space, eye, c):
		eye = c + Vector2(112.0, -11.0)
	var seen := Lights.lamp_lit_player(eye, get_tree(), space)
	check("Stalker widzi gracza pod zapaloną lampą (%.1f m od żarówki, oko 7 m obok)" % (c.distance_to(bulb) / Lights.PX_PER_M), seen == player)
	var far := Lights.lamp_lit_player(c + Vector2(0.0, -9.0) + Vector2(Lights.LAMP_STALKER_M * Lights.PX_PER_M + 40.0, 0.0), get_tree(), space)
	check("…ale nie spoza zasięgu Stalkera", far == null)
	level._add_enemy("TMoth", "cma", bulb + Vector2(-60.0, 4.0))
	var moth: Node2D = level.get_node_or_null("TMoth")
	await _frames(0.05)
	var lt: Dictionary = moth._beh.nearest_light(400.0) if moth != null else {}
	check("ćma: zapalona lampa to światło do krążenia (jak płomień)", lt.get("node") == lamp and String(lt.get("kind", "")) == "flare")
	var tr := Combat.trace(space, bulb + Vector2(0.0, 30.0), Vector2.UP, 200.0, 0)
	var hit_bulb := (tr["hits"] as Array).any(func(h: Dictionary) -> bool: return h["collider"] == lamp.get_node("Bulb"))
	check("promień: trafia klosz i leci dalej aż do sufitu (przebicie 0, ściana: %s)" % tr["wall"], hit_bulb and bool(tr["wall"]) and float((tr["end"] as Vector2).y) < bulb.y)
	var noise0 := float(NoiseMgr.level)
	var old := _debris_ids()
	var res := Combat.apply(lamp.get_node("Bulb"), Combat.make_info(Weapons.KILOF, 8.0, bulb, Vector2.UP, 1, "bullet"))
	await _frames(0.1)
	var shards := Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not _debris_ids_has(old, x)).size()
	check("kula tłucze lampę: gaśnie (%s), hałas %.1f → %.1f, %d odłamków szkła, pocisk leci dalej (pass)" % [lamp._light.enabled, noise0, float(NoiseMgr.level), shards],
		not lamp.lit and not lamp._light.enabled and float(NoiseMgr.level) > noise0 and shards == lamp.SHARDS and bool(res.get("hit")) and bool(res.get("pass")))
	check("stłuczona: kolejna kula przelatuje bez trafienia", not bool(Combat.apply(lamp.get_node("Bulb"), Combat.make_info(Weapons.KILOF, 8.0, bulb, Vector2.UP, 1, "bullet")).get("hit", false)))
	check("stłuczona: Stalker nie widzi gracza pod nią", Lights.lamp_lit_player(eye, get_tree(), space) == null)
	lt = moth._beh.nearest_light(400.0) if moth != null else {}
	check("stłuczona: ćma jej nie widzi", lt.get("node") != lamp)
	level.reset_breakables()
	await _frames(0.05)
	check("reset (wipe / punkt kontrolny): wszystkie lampy znów świecą", lamps.all(func(l: Node) -> bool: return l.lit and l._light.enabled))
	Combat.explode(get_tree(), bulb + Vector2(20.0, 10.0), 48.0, 30.0, 1, Weapons.KILOF, true)
	await _frames(0.05)
	check("wybuch obok tłucze lampę", not lamp.lit)
	level.reset_breakables()
	await _frames(0.05)
	old = _debris_ids()
	lamp._break_rpc(false)
	await _frames(0.05)
	check("dołączający (send_state_to → _break_rpc bez efektów): stłuczona, bez odłamków",
		not lamp.lit and not lamp._light.enabled and Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not _debris_ids_has(old, x)).is_empty())
	level.reset_breakables()
	if moth != null:
		moth.queue_free()

func _debris_ids_has(ids: Dictionary, x: Variant) -> bool:
	return ids.has((x as Object).get_instance_id())
