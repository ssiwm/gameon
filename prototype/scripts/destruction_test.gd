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
## Mapa 1.2 (ma zamurowane przejście), reszta świata wyciszona jak w stalker_test.gd. Wynik: linie [DESTRUCTION-TEST] i kod wyjścia.

const Breakable := preload("res://scripts/breakable.gd")
const DamageMask := preload("res://scripts/damage_mask.gd")
const Level3D := preload("res://scripts/level3d.gd")
const Combat := preload("res://scripts/combat.gd")
const Weapons := preload("res://scripts/weapons.gd")

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
