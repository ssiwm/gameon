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
## 10. Okna `|` (window_glass.gd, D1): na mapie całe; rama zatrzymuje ruch, nie wzrok; dla nawigacji bryła; cała szyba tłumi dźwięk
##    (okluzja i siatka dźwięku); promień kuli tłucze szybę i leci dalej, stłuczona przepuszcza dźwięk, rama dalej trzyma; wybuch i cios
##    też tłuką; reset wstawia szybę; dołączający dostaje stłuczoną bez efektów.
## 11. Przegrody D2 (breakable.gd): kratka `+` na 1.2 — rama zatrzymuje ruch i nawigację, wzrok, kule i dźwięk przechodzą; kula i maczeta jej nie
##    ranią, kilof rozbija; deski `%` — kula nie, maczeta, śrut i pazury tak, wzrok zasłaniają; Trzosek, którego ślad jest za deskami, dobija się
##    do nich z swojej strony; szarża Wołka łamie deski, Rzeźnika — nie kratkę (rozbieg przez deski tak, przez kratkę nie); bot rąbie deski
##    razem z dowódcą, a kratki (maczeta) nie rusza.
## 12. Dziury w deskach (D2). 13. Barykadowanie pustego otworu `:` (D2b).
## 14. Zawał (D3, support_beam.gd, level.gd `cave_in`): stempel `!` na 1.2 trzyma strefę gruzu `^` obok; kula, śrut, wybuch i kilof go ranią,
##    maczeta nie; po złamaniu strefa zapada się po CAVE_DELAY s (nawigacja zamknięta, hałas), zwykły wróg ginie, Stalker i gracz lądują
##    obok; gruz odkopuje kilof, kula nie; wipe w czasie trzeszczenia odwołuje zawał; wipe, punkt kontrolny bossa i wstrząs finału.
## 15. Dziennik sesji (DESTRUCTION_PLAN.md „Pomiar po wdrożeniu”): po sekcjach 1–14 w pliku są wiersze `break` (materiał, czym, kto,
##    rodzaj wroga, czas barykady), `crate`, `lamp` i `window` (czym), `barricade`, `support`, `cave`.
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
const WindowGlass := preload("res://scripts/window_glass.gd")
const WeaponController := preload("res://scripts/weapon_controller.gd")
const Sight := preload("res://scripts/sight.gd")
const Projectile := preload("res://scripts/projectile.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const LOG_DIR := "user://test_destruction_sessions"

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
	SessionLog.enabled = true                      # dziennik w headless: osobny katalog testu, kasowany na końcu (sekcja 15)
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "destruction"})
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
	await _windows()
	await _barriers()
	await _holes()
	await _barricade()
	await _cave()
	_session_log()
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
	return ok and _brick_cells() > 0

## Kafle zamurowania BrickWall1 w `_wall_cells` (na 1.2 jest tam też kratka Grate1).
func _brick_cells() -> int:
	return level._wall_cells.values().count("BrickWall1")

func _state() -> void:
	var pick: RefCounted = Weapons.def(Weapons.KILOF)
	var w := _real()
	check("stan: ściana 1.2 stoi na starcie (%d kafli bryły)" % _brick_cells(), w != null and _cells_solid())
	if w == null:
		return
	level.break_wall("BrickWall1")
	await _frames(0.1)
	check("stan: po rozbiciu kafle wolne, ściana w `_opened_walls`", _real() == null and _brick_cells() == 0 and level._opened_walls.has("BrickWall1"))
	level.reset_breakables()
	await _frames(0.1)
	w = _real()
	check("reset: ściana znów stoi (%.0f HP), kafle bryłą, lista rozbitych tylko z pustym otworem i strefą zawału, nawigacja = pełna budowa (%s)" % [float(w.hp) if w else 0.0, level.nav_diff_vs_full()],
		w != null and float(w.hp) == 120.0 and _cells_solid() and _only_start_open(level._opened_walls) and level.nav_diff_vs_full() == "")
	# punkt kontrolny z ranną ścianą
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	await _frames(0.15)
	level.save_breakables_checkpoint()
	var cp: Dictionary = level.breakables_checkpoint()
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	_hit(w, Weapons.KILOF, pick.damage, "melee", w.call("body_center"))
	await _frames(0.15)
	check("migawka: ranna ściana zapisana (plam %d), potem rozbita" % (cp["damage"].get("BrickWall1", [PackedFloat32Array()])[0] as PackedFloat32Array).size(),
		(cp["damage"].get("BrickWall1", [PackedFloat32Array()])[0] as PackedFloat32Array).size() == 4 and _real() == null and _only_start_open(cp["opened"]))
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
		back and _real() == null and level._opened_walls.has("BrickWall1") and _brick_cells() == 0 and level.nav_diff_vs_full() == "")
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
	check("wipe (main._restart_mission): rozbita ściana znów stoi, kafle bryłą, pusty otwór i strefa zawału wolne", _real() != null and _cells_solid() and _only_start_open(level._opened_walls))

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
	var old := _debris_ids()
	var res := Combat.apply(lamp.get_node("Bulb"), Combat.make_info(Weapons.KILOF, 8.0, bulb, Vector2.UP, 1, "bullet"))
	await _frames(0.1)
	var shards := Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not _debris_ids_has(old, x)).size()
	check("kula tłucze lampę: gaśnie (%s), hałas przy żarówce (ostatni hałas %s), %d odłamków szkła, pocisk leci dalej (pass)" % [lamp._light.enabled, NoiseMgr.last_noise_pos, shards],
		not lamp.lit and not lamp._light.enabled and NoiseMgr.last_noise_pos.distance_to(bulb) < 1.0 and shards == lamp.SHARDS and bool(res.get("hit")) and bool(res.get("pass")))
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

# ---------------------------------------------------------------- 10. okna (D1)

func _fresh_debris(old: Dictionary) -> int:
	return Vfx._debris.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not _debris_ids_has(old, x)).size()

func _windows() -> void:
	var wins := get_tree().get_nodes_in_group("windows")
	var win: Node2D = level.get_node_or_null("Window1")
	check("okna na 1.2: %d (znacznik |, chata radiowa), całe, 2 kafle" % wins.size(),
		wins.size() == 2 and win != null and wins.all(func(w: Node) -> bool: return w.intact) and int(win.rows) == 2)
	if win == null:
		return
	var space := level.get_world_2d().direct_space_state
	var cell := Vector2i(int(win.global_position.x / 16.0), int(win.global_position.y / 16.0) - 1)
	var mid: Vector2 = win.body_center()
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = mid
	pq.collision_mask = 177                                    # maska graczy, bota i wrogów
	var blocks := func() -> bool: return space.intersect_point(pq).any(func(h: Dictionary) -> bool: return (h["collider"] as Node).name == "Frame")
	check("rama zatrzymuje ruch (maska postaci), dla nawigacji to bryła", blocks.call() and level._is_solid(cell.x, cell.y))
	var a := mid + Vector2(-40.0, 0.0)
	var b := mid + Vector2(40.0, 0.0)
	check("wzrok i światło przez okno przechodzą (linia bez ściany)", Combat.clear_line(space, a, b))
	var occl := func() -> bool: return not space.intersect_ray(PhysicsRayQueryParameters2D.create(a, b, 1 | 256)).is_empty()
	check("cała szyba tłumi dźwięk: okluzja i siatka dźwięku", occl.call() and level._is_sound_solid(cell.x, cell.y) and not level.sound_grid._open(cell))
	var tr := Combat.trace(space, a, Vector2.RIGHT, 80.0, 0)
	var hit_pane := (tr["hits"] as Array).any(func(h: Dictionary) -> bool: return h["collider"] == win.get_node("Pane"))
	check("promień: trafia szybę i leci dalej (koniec za oknem)", hit_pane and float((tr["end"] as Vector2).x) > mid.x + 20.0)
	var old := _debris_ids()
	var res := Combat.apply(win.get_node("Pane"), Combat.make_info(Weapons.KILOF, 8.0, mid, Vector2.RIGHT, 1, "bullet"))
	await _frames(0.1)
	var shards := _fresh_debris(old)
	check("kula tłucze szybę: %d odłamków, hałas w oknie (ostatni hałas %s), pocisk leci dalej" % [shards, NoiseMgr.last_noise_pos],
		not win.intact and shards == WindowGlass.SHARDS and NoiseMgr.last_noise_pos.distance_to(mid) < 1.0 and bool(res.get("hit")) and bool(res.get("pass")))
	check("stłuczona: dźwięk przechodzi (okluzja, siatka), rama dalej trzyma, nawigacja bez zmian",
		not occl.call() and not level._is_sound_solid(cell.x, cell.y) and level.sound_grid._open(cell) and blocks.call() and level._is_solid(cell.x, cell.y))
	check("stłuczona: kolejna kula bez trafienia", not bool(Combat.apply(win.get_node("Pane"), Combat.make_info(Weapons.KILOF, 8.0, mid, Vector2.RIGHT, 1, "bullet")).get("hit", false)))
	level.reset_breakables()
	await _frames(0.05)
	check("reset (wipe / punkt kontrolny): szyby znów całe, dźwięk znów tłumiony",
		wins.all(func(w: Node) -> bool: return w.intact) and occl.call() and not level.sound_grid._open(cell))
	Combat.explode(get_tree(), mid + Vector2(-30.0, 6.0), 48.0, 30.0, 1, Weapons.KILOF, true)
	await _frames(0.05)
	check("wybuch obok tłucze szybę", not win.intact)
	level.reset_breakables()
	await _frames(0.05)
	var cone := Combat.in_cone(get_tree(), space, mid + Vector2(-14.0, 0.0), Vector2.RIGHT, 24.0, 40.0)
	check("cios: szyba w zasięgu ciosu (in_cone)", cone.has(win))
	level.reset_breakables()
	old = _debris_ids()
	win._break_rpc(0.0)
	await _frames(0.05)
	check("dołączający (send_state_to → _break_rpc bez efektów): stłuczona, bez odłamków", not win.intact and _fresh_debris(old) == 0)
	level.reset_breakables()

# ---------------------------------------------------------------- 11. przegrody D2: kratka i deski

const BASE_C := 94                  ## kolumna środka próbnych desek w tunelu ucieczki 1.2 (płaska podłoga w rzędzie 50, sufit nad rzędem 45)
const BASE_FEET := 51 * 16.0

func _barriers() -> void:
	var space := level.get_world_2d().direct_space_state
	var gr: Node2D = level.get_node_or_null("Grate1")
	check("kratka na 1.2: Grate1 (znacznik +, wnęka przy legowisku Stalkera), %s, %d kafle" % [str(gr.get("mat_id")) if gr else "-", int(gr.get("rows")) if gr else 0],
		gr != null and String(gr.mat_id) == "grate" and int(gr.rows) == 3)
	if gr == null:
		return
	var cell := Vector2i(int(gr.global_position.x / 16.0), int(gr.global_position.y / 16.0) - 1)
	var mid: Vector2 = gr.call("body_center")
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = mid
	pq.collision_mask = 177
	var blocks := func() -> bool: return space.intersect_point(pq).any(func(h: Dictionary) -> bool: return (h["collider"] as Node).get_parent() == gr)
	check("kratka: zatrzymuje ruch (maska postaci), dla nawigacji bryła", blocks.call() and level._is_solid(cell.x, cell.y))
	var a := mid + Vector2(-40.0, 0.0)
	var b := mid + Vector2(40.0, 0.0)
	var tr := Combat.trace(space, a, Vector2.RIGHT, 80.0, 0)
	check("kratka: wzrok, kule i dźwięk przechodzą (linia, promień, okluzja, siatka dźwięku)",
		Combat.clear_line(space, a, b) and float((tr["end"] as Vector2).x) > mid.x + 20.0
		and space.intersect_ray(PhysicsRayQueryParameters2D.create(a, b, 1 | 256)).is_empty() and not level._is_sound_solid(cell.x, cell.y) and level.sound_grid._open(cell))
	var h0 := float(gr.hp)
	var rb := _hit(gr, Weapons.P64, 20.0, "bullet", mid)
	var rm := _hit(gr, Weapons.MACZETA, Weapons.def(Weapons.MACZETA).damage, "melee", mid)
	check("kratka: kula i maczeta odbijają się bez obrażeń", not bool(rb.get("hit")) and not bool(rm.get("hit")) and float(gr.hp) == h0)
	var swings := 0
	while is_instance_valid(gr) and not gr.is_queued_for_deletion() and swings < 5:
		_hit(gr, Weapons.KILOF, Weapons.def(Weapons.KILOF).damage, "melee", mid)
		swings += 1
	await _frames(0.15)
	check("kratka: kilof rozbija (%d ciosy), przejście otwarte dla nawigacji" % swings,
		swings == 2 and level._opened_walls.has("Grate1") and not level._is_solid(cell.x, cell.y))
	level.reset_breakables()
	await _frames(0.1)
	gr = level.get_node_or_null("Grate1")
	check("kratka: reset wstawia ją z powrotem", gr != null and level._is_solid(cell.x, cell.y))

	# deski: próbne w tunelu (od podłogi do sufitu, 6 kafli); wrogowie mapy z tunelu (para Trzosków) i skrzynie z wcześniejszych prób
	# (fizyczne, spychały Trzoska) nie mieszają się do prób
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != stalker:
			e.queue_free()
	for n in level.get_children():
		if n is RigidBody2D:
			n.queue_free()
	var base := Vector2(BASE_C * 16.0 + 8.0, BASE_FEET)
	_place_player(base + Vector2(-70.0, 0.0))
	var pl := _barrier("DPlanks1", base)
	await _frames(0.1)
	var pm: Vector2 = pl.call("body_center")
	check("deski: zasłaniają wzrok i zatrzymują kule (bryła świata)", not Combat.clear_line(space, pm + Vector2(-30.0, 0.0), pm + Vector2(30.0, 0.0)))
	check("deski: kula pistoletu ich nie rani", not bool(_hit(pl, Weapons.P64, 20.0, "bullet", pm).get("hit")))
	check("deski: śrut rani", bool(_hit(pl, Weapons.SRUT8, 10.0, "bullet", pm).get("hit")) and float(pl.hp) < 60.0)
	check("deski: pazury (claw) ranią", bool(Combat.apply(pl, {"type": "claw", "amount": 4.0, "pos": pm, "dir": Vector2.RIGHT}).get("hit")))
	pl.queue_free()
	pl = _barrier("DPlanks2", base)
	swings = 0
	while is_instance_valid(pl) and not pl.is_queued_for_deletion() and swings < 5:
		_hit(pl, Weapons.MACZETA, Weapons.def(Weapons.MACZETA).damage, "melee", pm)
		swings += 1
	check("deski: maczeta rozbija (%d ciosy, cicho jak cios)" % swings, swings == 2)
	await _frames(0.15)

	# Trzosek za deskami dobija się do gracza
	pl = _barrier("DPlanks3", base)
	await _frames(0.1)
	var tz := _enemy("trzosek", base + Vector2(44.0, 0.0))
	await _frames(0.2)
	tz.wake()
	tz._lead_at(player.global_position)
	var hp0 := float(pl.hp)
	await _frames(4.0)
	check("Trzosek: ślad za deskami → podchodzi i drapie (HP %.0f → %.0f), zostaje po swojej stronie (x %+.0f)" % [hp0, float(pl.hp) if is_instance_valid(pl) else 0.0, tz.global_position.x - base.x],
		is_instance_valid(pl) and float(pl.hp) <= hp0 - 8.0 and tz.global_position.x > base.x + 8.0 and tz.global_position.x < base.x + 30.0)
	tz.queue_free()
	pl.queue_free()
	await _frames(0.1)

	# szarże: Wołek łamie deski, Rzeźnik odbija się od kratki
	pl = _barrier("DPlanks4", base)
	await _frames(0.1)
	var wk := _enemy("wolek", base + Vector2(150.0, 0.0))
	await _frames(0.3)
	var rz := _enemy("rzeznik", base + Vector2(150.0, -200000.0))
	gr = level.get_node_or_null("Grate1")
	check("szarża: Wołek łamie deski, kratki nie; Rzeźnik zamurowanie i deski, kratki nie",
		wk._beh.charge_through(pl) and not wk._beh.charge_through(gr) and not wk._beh.charge_through(level.get_node_or_null("BrickWall1"))
		and rz._beh.charge_through(pl) and rz._beh.charge_through(level.get_node_or_null("BrickWall1")) and not rz._beh.charge_through(gr))
	rz.queue_free()
	check("szarża: rozbieg Wołka przez deski wolny", wk._beh._run_clear(-1.0, 140.0))
	wk.wake()
	wk._sp = 2
	wk._beh.sp_dir = -1.0
	wk._beh.sp_t = 3.0
	wk.winding = false
	await _frames(1.5)
	check("szarża Wołka łamie deski (Wołek x %+.0f)" % (wk.global_position.x - base.x), not is_instance_valid(pl) or pl.is_queued_for_deletion() or level._opened_walls.has("DPlanks4"))
	wk.queue_free()
	if is_instance_valid(pl):
		pl.queue_free()
	await _frames(0.1)

	# bot rąbie deski razem z dowódcą
	var bot: CharacterBody2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			bot = p
	check("bot w drużynie do testu rąbania", bot != null)
	if bot == null:
		return
	pl = _barrier("DPlanks5", base)
	await _frames(0.1)
	_place_player(base + Vector2(-14.0, 0.0))
	bot.global_position = base + Vector2(-40.0, 0.0)
	bot.velocity = Vector2.ZERO
	player.w_state = WeaponController.State.MELEE
	var chop: Variant = bot._bot_chop_wall(player)
	player.w_state = WeaponController.State.READY
	var idle: Variant = bot._bot_chop_wall(player)
	check("bot: przegroda do rąbania, gdy dowódca rąbie (%s), bez ciosu dowódcy — nic" % str(chop.name if chop else null), chop == pl and idle == null)
	pl.queue_free()
	var g2 := _barrier("DGrate1", base, "grate")
	await _frames(0.1)
	player.w_state = WeaponController.State.MELEE
	var chop_g: Variant = bot._bot_chop_wall(player)
	player.w_state = WeaponController.State.READY
	check("bot: kratki maczetą nie rąbie", Weapons.def(bot.weapons.melee_id).breaks_walls or chop_g == null)
	g2.queue_free()
	pl = _barrier("DPlanks6", base)
	await _frames(0.1)
	bot.set_physics_process(true)
	bot.set_process(true)
	var bot_swung := [false]
	var hp_b := float(pl.hp)
	await _frames(3.0, func(_t: float, _dt: float) -> void:
		_place_player(base + Vector2(-14.0, 0.0))
		player.aim_dir = Vector2.RIGHT
		if player.weapons.state != WeaponController.State.MELEE:
			player.weapons.try_melee()
		if bot.weapons.state == WeaponController.State.MELEE:
			bot_swung[0] = true)
	check("bot: dowódca rąbie deski → bot podchodzi i rąbie razem z nim", bot_swung[0])
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = Vector2(-4000, -4000)
	if is_instance_valid(pl):
		pl.queue_free()
	info("deski po rąbaniu dowódcy z botem: HP %.0f → %.0f" % [hp_b, float(pl.hp) if is_instance_valid(pl) else 0.0])

# ---------------------------------------------------------------- 12. dziury w deskach (D2, PR 2)

## D2, PR 2 — dziury na wylot w deskach: śrut, maczeta i kilof przebijają, kula i drapanie nie; przez dziurę widać, świeci latarka,
## leci kula i promień (cios nie sięga), słychać (siatka dźwięku i okluzja); prawdziwy śrut z broni łupie deski; reset zabiera dziury.
func _holes() -> void:
	var space := level.get_world_2d().direct_space_state
	for n in level.get_children():
		if n is RigidBody2D:
			n.queue_free()
	var base := Vector2(BASE_C * 16.0 + 8.0, BASE_FEET)
	_place_player(base + Vector2(-40.0, 0.0))
	player.aim_dir = Vector2.RIGHT
	var pl := _barrier("DHoles1", base)
	await _frames(0.1)
	var hy := base.y - 9.0                           # wysokość latarki gracza (Lights: stopy − 9 px)
	var at := Vector2(base.x, hy)
	_hit(pl, Weapons.P64, 20.0, "bullet", at)
	_hit(pl, Weapons.SRUT8, 2.0, "bullet", at)      # śrut z daleka (słaby — stopień 0): odprysk bez dziury
	_hit(pl, 0, 4.0, "claw", at)
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("dziury: kula, słaby śrut i drapanie nie przebijają (%d dziur)" % int(pl.hole_total), int(pl.hole_total) == 0 and not pl.hole_at(hy))
	_hit(pl, Weapons.SRUT8, 10.0, "bullet", at)
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("dziury: śrut przebija deskę (%d dziura, promień %.1f px), tylko na swojej wysokości" % [int(pl.hole_total), float(pl.holes[2]) if pl.holes.size() >= 3 else 0.0],
		int(pl.hole_total) == 1 and pl.hole_at(hy) and not pl.hole_at(hy - 20.0) and not pl.hole_at(hy + 6.0))
	var a := Vector2(base.x - 40.0, hy)
	var b := Vector2(base.x + 40.0, hy)
	check("dziury: wzrok przez dziurę, obok niej nie", Sight.clear(space, a, b) and not Sight.clear(space, a - Vector2(0.0, 20.0), b - Vector2(0.0, 20.0)))
	check("dziury: cios i płomień przez dziurę nie sięgają (Combat.clear_line)", not Combat.clear_line(space, a, b))
	var tr := Combat.trace(space, a, Vector2.RIGHT, 80.0, 0)
	check("dziury: promień (wiązka, szyna) leci dalej (koniec x %+.0f)" % (float((tr["end"] as Vector2).x) - base.x), float((tr["end"] as Vector2).x) > base.x + 20.0)
	var oq := PhysicsRayQueryParameters2D.create(a, b, 1 | 256)
	check("dziury: okluzja dźwięku przez dziurę słabsza (promień przechodzi)", Sight.first_hit(space, oq).is_empty())
	player.flashlight = true
	var lit: Variant = Lights.flashlight_on(b, get_tree(), space)
	var dark: Variant = Lights.flashlight_on(b - Vector2(0.0, 20.0), get_tree(), space)
	player.flashlight = false
	check("dziury: latarka świeci przez szparę (wróg za deskami ją widzi), obok niej nie", lit == player and dark == null)
	# kula przez dziurę trafia skrzynię za deskami; ta sama kula obok dziury zostaje w desce
	var cr := _crate(Vector2(base.x + 30.0, base.y))
	await _frames(0.1)
	var c0 := float(cr.hp)
	var hp0 := float(pl.hp)
	var miss := Projectile.new()
	miss.launch(Weapons.P64, Vector2(base.x - 30.0, hy - 20.0), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(miss)
	await _frames(0.3)
	var stopped := float(cr.hp) == c0 and float(pl.hp) == hp0
	var shot := Projectile.new()
	shot.launch(Weapons.P64, Vector2(base.x - 30.0, hy), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(shot)
	await _frames(0.3)
	check("dziury: kula obok dziury zostaje w desce (%s), przez dziurę trafia skrzynię za deskami (HP %.0f → %.0f)" % [str(stopped), c0, float(cr.hp) if is_instance_valid(cr) else 0.0],
		stopped and is_instance_valid(cr) and float(cr.hp) < c0)
	if is_instance_valid(cr):
		cr.queue_free()
	pl.queue_free()
	await _frames(0.1)

	# prawdziwy śrut z broni (pociski SPREAD-12: 5 × 7, deski zostają): deski tracą HP i dostają dziury; dotąd pociski w ogóle nie raniły przegród
	var p2 := _barrier("DHoles2", base)
	await _frames(0.1)
	var d := Weapons.def(Weapons.SPREAD12)
	var muzzle := Vector2(base.x - 40.0, base.y - 30.0)
	for dd in Weapons.pellet_dirs(d, Vector2.RIGHT, 7, 0.0):
		var pr := Projectile.new()
		pr.launch(Weapons.SPREAD12, muzzle, dd, 1, true)
		get_tree().current_scene.add_child(pr)
	await _frames(0.3)
	check("dziury: strzał z SPREAD-12 z bliska łupie deski (HP %.0f) i je przebija (%d dziur)" % [float(p2.hp) if is_instance_valid(p2) else 0.0, int(p2.hole_total) if is_instance_valid(p2) else 0],
		is_instance_valid(p2) and float(p2.hp) < 60.0 and int(p2.hole_total) >= 1)
	if is_instance_valid(p2):
		p2.queue_free()
	var p3 := _barrier("DHoles3", base)
	_hit(p3, Weapons.MACZETA, Weapons.def(Weapons.MACZETA).damage, "melee", Vector2(base.x, base.y - 40.0))
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("dziury: maczeta wyrąbuje dziurę (%d)" % int(p3.hole_total), int(p3.hole_total) == 1)
	p3.queue_free()
	var g := _barrier("DHoles4", base, "grate")
	_hit(g, Weapons.KILOF, 30.0, "melee", Vector2(base.x, base.y - 40.0))
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("dziury: kratka ich nie ma (i tak przepuszcza wzrok)", int(g.hole_total) == 0)
	g.queue_free()
	await _frames(0.1)

	# deski na mapie 1.2 (schowek w zachodnim szybie): dziura otwiera kafel siatki dźwięku, reset go zamyka
	var mp: Node2D = level.get_node_or_null("Planks1")
	check("deski na 1.2: Planks1 (schowek w ścianie zachodniego szybu), %d kafle" % (int(mp.get("rows")) if mp else 0), mp != null and int(mp.rows) == 3)
	if mp == null:
		return
	var col := int(mp.global_position.x / 16.0)
	var row := int(mp.global_position.y / 16.0) - 2                   # środkowy kafel przegrody
	var cell := Vector2i(col, row)
	var before: bool = level._is_sound_solid(col, row) and not level.sound_grid._open(cell)
	_hit(mp, Weapons.SRUT8, 10.0, "bullet", Vector2(mp.global_position.x, row * 16.0 + 8.0))
	await _frames(Breakable.SPLAT_GAP + 0.05)
	check("deski na 1.2: dziura otwiera tylko swój kafel siatki dźwięku (przed %s, po %s, wyżej %s)" % [str(before), str(not level._is_sound_solid(col, row)), str(level._is_sound_solid(col, row - 1))],
		before and not level._is_sound_solid(col, row) and level.sound_grid._open(cell) and level._is_sound_solid(col, row - 1))
	level.reset_breakables()
	await _frames(0.1)
	mp = level.get_node_or_null("Planks1")
	check("deski na 1.2: reset zabiera dziury i zamyka kafel dźwięku", mp != null and int(mp.hole_total) == 0 and level._is_sound_solid(col, row) and not level.sound_grid._open(cell))

## D2b — barykadowanie: pusty otwór `:` na 1.2 (dolny korytarz budynku z generatorem), deski ze skrzyń, złom z łupu bez desek, trzymanie [E]
## ~2 s na deskę (serwer: zasięg, koszt, hałas), komplet 3 desek, nadłamana deska się liczy, wróg w otworze blokuje, gracz w otworze
## wypchnięty na bliższą stronę, reset (wipe) i punkt kontrolny bossa, Stalker rozbija barykadę na jedynej drodze do hałasu.
func _barricade() -> void:
	var on := "Opening1"
	var wd: Dictionary = level.wall_def(on)
	var cell := Vector2i(243, 25)
	var spot: Node2D = level.get_node_or_null("Nail_" + on)
	check("pusty otwór na 1.2: %s (znacznik :), %d kafle, na starcie wolny (bez węzła, nawigacja przechodzi), miejsce przybijania %s" % [on, int(wd.get("rows", 0)), str(spot != null)],
		not wd.is_empty() and int(wd["rows"]) == 3 and level._opened_walls.has(on) and level.get_node_or_null(on) == null
		and not level._wall_cells.has(cell) and spot != null and level.boards_of(on) == 0)
	if wd.is_empty() or spot == null:
		return
	var feet: Vector2 = wd["pos"]
	var pid := int(String(player.name))
	level.plank_stock = 0
	Scrap.loot = 0
	check("bez desek i złomu nie da się (%s)" % level.nail_reason(on), level.nail_reason(on) == "nomat")
	var cr := _crate(feet + Vector2(60, 0))
	await _frames(0.1)
	cr.shatter()
	await _frames(0.1)
	var got := int(level.plank_stock)
	check("rozbita skrzynia: %d deski do zapasu drużyny" % got, got >= 1 and got <= 2)

	# trzymanie [E]: deska co ~2 s; pierwsza z zapasu, kolejne za złom z łupu
	level.plank_stock = 1
	Scrap.loot = 4
	_place_player(feet + Vector2(-20, 0))
	await _frames(0.2)
	var ns0 := int(NoiseMgr.noise_serial)
	spot.force_worker(pid, true)
	await _frames(1.0)
	var mid := float(spot.progress)
	var knocks := int(NoiseMgr.noise_serial) - ns0
	await _frames(1.15)
	var at: Vector2 = NoiseMgr.last_noise_pos
	check("trzymanie [E]: po 1 s połowa deski (%.2f), po ~2 s jedna deska (%d), otwór znów przegrodą dla nawigacji, deska z zapasu (zostało %d), stukanie to hałas (%d zgłoszeń w 1 s, źródło %.0f px od otworu)" % [mid, level.boards_of(on), int(level.plank_stock), knocks, at.distance_to(feet)],
		mid > 0.4 and mid < 0.6 and level.boards_of(on) == 1 and level._wall_cells.has(cell) and int(level.plank_stock) == 0 and knocks >= 3 and at.distance_to(feet) < 32.0)
	await _frames(4.3)
	var w: Node2D = level.get_node_or_null(on)
	check("trzyma dalej: komplet %d desek (%.0f HP), druga i trzecia za %d złomu każda (łup %d), więcej się nie da (%s), postęp stoi (%.2f)" % [level.boards_of(on), float(w.hp) if w else 0.0, int(level.NAIL_SCRAP), int(Scrap.loot), level.nail_reason(on), float(spot.progress)],
		level.boards_of(on) == 3 and w != null and is_equal_approx(float(w.hp), 60.0) and int(Scrap.loot) == 0 and level.nail_reason(on) == "full" and float(spot.progress) == 0.0)
	spot.force_worker(pid, false)
	await _frames(0.1)
	_place_player(feet + Vector2(-60, 0))
	level.plank_stock = 1
	_hit(w, 0, 25.0, "claw", feet + Vector2(-8.0, -24.0))
	await _frames(Breakable.SPLAT_GAP + 0.05)
	spot.force_worker(pid, true)
	await _frames(0.3)
	check("gracz za daleko (%s): serwer nie przybija (postęp %.2f, desek %d)" % [level.nail_reason(on), float(spot.progress), level.boards_of(on)], float(spot.progress) == 0.0 and level.boards_of(on) == 2)
	spot.force_worker(pid, false)
	level.plank_stock = 0
	check("nadłamana barykada: %.0f HP = %d deski, brak desek (%s)" % [float(w.hp), level.boards_of(on), level.nail_reason(on)], level.boards_of(on) == 2 and level.nail_reason(on) == "nomat")
	level.plank_stock = 1
	check("dobita deską: %s, %.0f HP, zapas %d" % [level.nail_board(on), float(w.hp), int(level.plank_stock)], is_equal_approx(float(w.hp), 60.0) and int(level.plank_stock) == 0)

	# wipe i punkt kontrolny bossa
	_hit(w, 0, 25.0, "claw", feet + Vector2(-8.0, -24.0))
	await _frames(Breakable.SPLAT_GAP + 0.05)
	level.plank_stock = 3
	var st: Dictionary = level.breakables_state()
	level.reset_breakables()
	await _frames(0.1)
	check("wipe: otwór znów wolny (nawigacja przechodzi), zapas desek przepada (%d)" % int(level.plank_stock),
		level._opened_walls.has(on) and level.get_node_or_null(on) == null and not level._wall_cells.has(cell) and int(level.plank_stock) == 0)
	level.reset_breakables(st)
	await _frames(0.1)
	w = level.get_node_or_null(on)
	check("punkt kontrolny bossa: barykada z %d deskami (%.0f HP) i zapas %d wracają" % [level.boards_of(on), float(w.hp) if w else 0.0, int(level.plank_stock)],
		level.boards_of(on) == 2 and w != null and is_equal_approx(float(w.hp), 35.0) and int(level.plank_stock) == 3 and level._wall_cells.has(cell))
	level.reset_breakables()
	await _frames(0.1)

	# wróg w otworze blokuje; gracz w otworze wypchnięty na bliższą stronę
	level.plank_stock = 2
	var tz := _enemy("trzosek", feet + Vector2(0, -1))
	var blocked := String(level.nail_reason(on))
	tz.queue_free()
	await _frames(0.1)
	check("wróg w otworze: nie da się go zabić (%s), po nim znów można (%s)" % [blocked, level.nail_reason(on)], blocked == "blocked" and level.nail_reason(on) == "ok")
	_place_player(feet + Vector2(3, 0))
	await _frames(0.05)
	var why := String(level.nail_board(on))
	check("gracz w otworze: deska przybita (%s), gracz wypchnięty na bliższą stronę (x %+.0f)" % [why, player.global_position.x - feet.x], why == "ok" and player.global_position.x > feet.x + 8.0)
	level.reset_breakables()
	await _frames(0.1)

	# Stalker: barykada na jedynej drodze do hałasu — dochodzi i rozbija ją, zamiast czekać pod nią
	level.plank_stock = 3
	for k in 3:
		level.nail_board(on)
	_place_player(feet + Vector2(400, -2000))
	var s: CharacterBody2D = level.STALKER_SCENE.instantiate()
	s.name = "TStalker"
	s.position = feet + Vector2(-160, 0)
	level.add_child(s)
	await _frames(0.1)
	var goal := feet + Vector2(120, 0)
	check("pełna barykada zamyka jedyną drogę z korytarza na wschód (%d deski, ścieżka %d punktów)" % [level.boards_of(on), (level.nav.find_path(s.global_position, goal) as Array).size()],
		level.boards_of(on) == 3 and (level.nav.find_path(s.global_position, goal) as Array).is_empty())
	s.awake = true
	s.target_pos = goal
	s._seen_serial = NoiseMgr.noise_serial
	var tb := -1.0
	var t := 0.0
	while t < 10.0 and s.global_position.x <= feet.x + 40.0:       # do 10 s: rozbicie i przejście na drugą stronę
		NoiseMgr.level = maxf(float(NoiseMgr.level), 70.0)          # poluje dalej (nie zasypia)
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		if tb < 0.0 and level._opened_walls.has(on):
			tb = t
	check("Stalker rozbija barykadę na drodze do hałasu po %.1f s (dojście + 3 ciosy — sekundy, nie azyl) i idzie dalej (x %+.0f)" % [tb, s.global_position.x - feet.x],
		tb >= 2.5 and tb <= 8.0 and s.global_position.x > feet.x + 40.0)
	s.queue_free()
	NoiseMgr.level = 0.0
	level.reset_breakables()
	await _frames(0.1)

# ---------------------------------------------------------------- 14. zawał (D3)

func _cave_path_through(a: Vector2, b: Vector2, rc: Rect2) -> bool:
	var path: Array = level.nav.find_path(a, b)
	var band := rc.grow_individual(0.0, 0.0, 0.0, 4.0)
	for i in path.size():
		var p: Vector2 = path[i]["pos"]
		if band.has_point(p):
			return true
		if i > 0:                                     # krok przez strefę (węzły grafu bywają rzadsze niż kafle)
			var q: Vector2 = path[i - 1]["pos"]
			var inside_y := p.y >= band.position.y and p.y <= band.end.y and q.y >= band.position.y and q.y <= band.end.y
			if inside_y and minf(p.x, q.x) < band.position.x and maxf(p.x, q.x) > band.end.x:
				return true
	return false

## Lista rozbitych / wolnych przegród zawiera tylko te, które są wolne od startu mapy: pusty otwór „:” i strefa zawału „^”.
func _only_start_open(arr: Variant) -> bool:
	var a := Array(arr)
	a.sort()
	return a == ["Opening1", "Rubble1"]

func _cave() -> void:
	var sb: Node2D = level.get_node_or_null("Support1")
	var sd: Dictionary = level.support_def("Support1")
	var zn := String(sd.get("wall", ""))
	var wd: Dictionary = level.wall_def(zn)
	var cells: Array = wd.get("cells", [])
	check("stempel na 1.2: Support1 trzyma %s (stempli %d), strefa na starcie wolna (bez węzła, kafle wolne)" % [zn, level.supports_total()],
		sb != null and zn == "Rubble1" and level.supports_total() == 1 and level._opened_walls.has(zn) and level.get_node_or_null(zn) == null
		and not cells.is_empty() and not level._wall_cells.has(cells[0]))
	if sb == null or wd.is_empty() or cells.is_empty():
		return
	var cell: Vector2i = cells[0]
	var rc: Rect2 = level.wall_rect(wd)
	var feet: Vector2 = wd["pos"]
	var a := feet + Vector2(-120.0, -2.0)
	var b := feet + Vector2(40.0, -2.0)                 # ślepy koniec pokoju za strefą (1.2: jedyne wejście przez strefę)
	var space := level.get_world_2d().direct_space_state
	var c: Vector2 = sb.body_center()
	_place_player(feet + Vector2(-260.0, 0.0))
	await _frames(0.1)
	check("przed zawałem droga wiedzie przez strefę", _cave_path_through(a, b, rc))

	# trafienia: maczeta odbija się, kula i śrut ranią (pocisk leci dalej), wybuch rani, cios w stożku sięga belki
	var r_blade: Dictionary = _hit(sb, Weapons.MACZETA, 30.0, "melee", c)
	var hp0 := float(sb.hp)
	var tr := Combat.trace(space, c + Vector2(-40.0, 0.0), Vector2.RIGHT, 200.0, 0)
	var beam_hit := (tr["hits"] as Array).any(func(h: Dictionary) -> bool: return h["collider"] == sb.get_node("Beam"))
	var r_bullet: Dictionary = _hit(sb.get_node("Beam"), Weapons.M83, 20.0, "bullet", c)
	var after_bullet := float(sb.hp)
	_hit(sb, Weapons.SPREAD12, 10.0, "bullet", c)
	var after_pellet := float(sb.hp)
	Combat.explode(get_tree(), c + Vector2(-20.0, 10.0), 48.0, 10.0, 1, Weapons.KILOF, true)
	var after_blast := float(sb.hp)
	var cone := Combat.in_cone(get_tree(), space, c + Vector2(-14.0, 0.0), Vector2.RIGHT, 24.0, 40.0)
	check("stempel: maczeta odbija się (zadane %.0f, HP %.0f), promień kuli trafia belkę i leci dalej (%s), kula %.0f → %.0f (pass %s), śrut → %.0f, wybuch → %.0f, cios w stożku sięga belki (%s)" % [float(r_blade.get("dealt", -1.0)), hp0, str(beam_hit), hp0, after_bullet, str(r_bullet.get("pass")), after_pellet, after_blast, str(cone.has(sb))],
		float(r_blade.get("dealt", -1.0)) == 0.0 and hp0 == 80.0 and beam_hit and after_bullet == 60.0 and bool(r_bullet.get("pass", false))
		and after_pellet == 50.0 and after_blast < after_pellet and cone.has(sb))
	await _frames(0.1)

	# złamanie kilofem; w czasie trzeszczenia do strefy wchodzą wróg, Stalker i gracz
	var ns0 := int(NoiseMgr.noise_serial)
	var picks := 0
	while sb.intact and picks < 6:
		_hit(sb, Weapons.KILOF, Weapons.def(Weapons.KILOF).damage, "melee", c)
		picks += 1
	check("kilof łamie stempel (%d ciosy): kula przez niego przelatuje, złamany u wszystkich (%s), strefa jeszcze wolna (trzeszczy)" % [picks, str(level._supports_down)],
		not sb.intact and level._supports_down.has("Support1") and level._opened_walls.has(zn) and int(sb.get_node("Beam").collision_layer) == 0)
	var tz := _enemy("trzosek", feet + Vector2(-2.0, -1.0))
	tz.set_physics_process(false)
	var st: CharacterBody2D = level.STALKER_SCENE.instantiate()
	st.name = "TCaveStalker"
	st.position = feet + Vector2(3.0, -1.0)
	level.add_child(st)
	st.set_physics_process(false)
	_place_player(feet + Vector2(-3.0, -1.0))
	await _frames(level.CAVE_DELAY * 0.5)
	var open_mid := bool(level._opened_walls.has(zn))
	await _frames(level.CAVE_DELAY * 0.5 + 0.15)
	var rw: Node2D = level.get_node_or_null(zn)
	var tz_dead: bool = not is_instance_valid(tz) or tz.is_queued_for_deletion() or tz.get("dead") == true or float(tz.get("hp")) <= 0.0
	check("po %.1f s strefa się zawala (w połowie wolna: %s): gruz %s %.0f HP, kafle i nawigacja zamknięte, hałas przy strefie (%d zgłoszeń)" % [level.CAVE_DELAY, str(open_mid), str(rw.get("mat_id")) if rw else "-", float(rw.get("hp")) if rw else 0.0, int(NoiseMgr.noise_serial) - ns0],
		open_mid and rw != null and String(rw.get("mat_id")) == "rubble" and float(rw.get("hp")) == 200.0 and level._wall_cells.has(cell)
		and not _cave_path_through(a, b, rc) and int(NoiseMgr.noise_serial) > ns0 and NoiseMgr.last_noise_pos.distance_to(rc.get_center()) < 1.0)
	check("zasypani: zwykły wróg ginie (%s), Stalker wypchnięty w prawo (x %+.0f), gracz na bliższą stronę w lewo (x %+.0f)" % [str(tz_dead), st.global_position.x - feet.x, player.global_position.x - feet.x],
		tz_dead and st.global_position.x > rc.end.x and player.global_position.x < rc.position.x)
	st.queue_free()
	if is_instance_valid(tz):
		tz.queue_free()
	if rw == null:
		level.reset_breakables()
		await _frames(0.1)
		return

	# odkopywanie: kula nie rusza gruzu, kilof tak
	_hit(rw, Weapons.M83, 20.0, "bullet", rw.call("body_center"))
	var rhp := float(rw.hp)
	var digs := 0
	while is_instance_valid(rw) and not rw.is_queued_for_deletion() and level._wall_cells.has(cell) and digs < 12:
		_hit(rw, Weapons.KILOF, Weapons.def(Weapons.KILOF).damage, "melee", rw.call("body_center"))
		digs += 1
	await _frames(0.1)
	check("gruz: kula nie rani (%.0f HP), kilof odkopuje w %d ciosów, droga znów przez strefę" % [rhp, digs],
		rhp == 200.0 and digs >= 3 and level._opened_walls.has(zn) and not level._wall_cells.has(cell) and _cave_path_through(a, b, rc))

	# wipe stawia stempel
	level.reset_breakables()
	await _frames(0.1)
	check("wipe: stempel znów cały (%.0f HP), strefa wolna" % float(sb.hp), sb.intact and float(sb.hp) == 80.0 and level._supports_down.is_empty() and level._opened_walls.has(zn))

	# wipe w czasie trzeszczenia odwołuje zawał
	_place_player(feet + Vector2(-260.0, 0.0))
	while sb.intact:
		_hit(sb, Weapons.KILOF, Weapons.def(Weapons.KILOF).damage, "melee", c)
	await _frames(level.CAVE_DELAY * 0.3)
	level.reset_breakables()
	await _frames(level.CAVE_DELAY + 0.2)
	check("wipe w czasie trzeszczenia: zawał odwołany (strefa wolna %s), stempel cały" % str(level._opened_walls.has(zn)),
		level._opened_walls.has(zn) and not level._wall_cells.has(cell) and sb.intact)

	# punkt kontrolny bossa: zawalona strefa i złamany stempel wracają
	while sb.intact:
		_hit(sb, Weapons.KILOF, Weapons.def(Weapons.KILOF).damage, "melee", c)
	await _frames(level.CAVE_DELAY + 0.2)
	var snap: Dictionary = level.breakables_state()
	level.reset_breakables()
	await _frames(0.1)
	var wiped: bool = level._opened_walls.has(zn) and sb.intact
	level.reset_breakables(snap)
	await _frames(0.1)
	check("punkt kontrolny bossa: po wipe'ie wolna (%s), z migawki znów zawalona i stempel złamany" % str(wiped),
		wiped and not level._opened_walls.has(zn) and level._wall_cells.has(cell) and not sb.intact and level._supports_down.has("Support1"))

	# wstrząs finału rozsypuje gruz wszystkich stref
	level._collapse_rpc(level.map_id, [])
	await _frames(0.1)
	check("wstrząs finału: gruz strefy rozsypany (droga powrotna wolna)", level._opened_walls.has(zn) and not level._wall_cells.has(cell))
	level.reset_breakables()
	await _frames(0.1)

## Próbna przegroda od podłogi do sufitu tunelu (6 kafli), poza `_wall_cells` — sama mechanika trafień, ruchu i wrogów.
func _barrier(wname: String, feet: Vector2, mat := "planks") -> Node2D:
	var w: Node2D = Breakable.new()
	w.name = wname
	w.mat_id = mat
	w.rows = 6
	w.global_position = feet
	level.add_child(w)
	return w

func _enemy(kind: String, pos: Vector2) -> CharacterBody2D:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as CharacterBody2D
	e.kind = kind
	level.add_child(e)
	e.global_position = pos
	e._home = pos
	e._remote_pos = pos
	e._phys_x = pos.x
	e._last_x = pos.x
	return e

# ---------------------------------------------------------------- 15. dziennik sesji

func _session_log() -> void:
	var rows: Array = []
	if SessionLog.path != "" and FileAccess.file_exists(SessionLog.path):
		for line in FileAccess.get_file_as_string(SessionLog.path).split("\n", false):
			var v: Variant = JSON.parse_string(line)
			if v is Dictionary:
				rows.append(v)
	var by_ev := {}
	for r in rows:
		var ev := String(r.get("ev", ""))
		by_ev[ev] = int(by_ev.get(ev, 0)) + 1
	info("dziennik: %s" % str(by_ev))
	var breaks := rows.filter(func(r: Dictionary) -> bool: return r.get("ev") == "break")
	var mats := {}
	for r in breaks:
		mats[String(r.get("mat", ""))] = true
	check("dziennik: `break` dla cegły, desek i kratki (%s)" % str(mats.keys()), mats.has("brick") and mats.has("planks") and mats.has("grate"))
	check("dziennik: `break` ma czym, kto, hałas i pozycję", not breaks.is_empty() and breaks.all(func(r: Dictionary) -> bool:
		return r.has("by") and r.has("shooter") and r.has("noise") and r.has("pos") and String(r["by"]) != ""))
	check("dziennik: gruz odkopany kilofem to `break` z materiałem rubble",
		breaks.any(func(r: Dictionary) -> bool: return r.get("mat") == "rubble" and r.get("by") == "pick"))
	var srcs := {}
	for r in breaks:
		if r.has("src"):
			srcs[String(r["src"])] = true
	check("dziennik: rozbicie przez wroga ma rodzaj (%s)" % str(srcs.keys()), not srcs.is_empty())
	var held := breaks.filter(func(r: Dictionary) -> bool: return r.has("held"))
	check("dziennik: rozbita przybita barykada ma `held` (%s)" % str(held.map(func(r: Dictionary) -> String: return "%s %s s" % [r.get("src", r.get("by")), r["held"]])),
		not held.is_empty() and held.all(func(r: Dictionary) -> bool: return float(r["held"]) >= 0.0))
	for ev in ["crate", "barricade", "support", "cave"]:
		check("dziennik: zdarzenie `%s`" % ev, int(by_ev.get(ev, 0)) > 0)
	for ev in ["lamp", "window"]:
		var rs := rows.filter(func(r: Dictionary) -> bool: return r.get("ev") == ev)
		check("dziennik: `%s` z rodzajem trafienia" % ev, not rs.is_empty() and rs.any(func(r: Dictionary) -> bool: return String(r.get("by", "")) != ""))
	SessionLog.reset_for_test()                      # zwalnia plik (inaczej Windows nie da go skasować)
	SessionLog.enabled = false
	var d := DirAccess.open(LOG_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_DIR))
