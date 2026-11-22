extends "res://scripts/stalker_test.gd"
## Kosmetyka walki (DESTRUCTION_PLAN.md D4) i pula obłoczków cząsteczek w widoku 3D (view3d.gd `spawn_burst`, `ceiling_dust`, `kick_lamps`).
##
##   godot --path . -- --host --nobot --mission=z1_m2 --fxtest [--fxshots=KATALOG --view3dlit] --autoquit=60
##   (tylko w oknie — w trybie headless nie ma widoku 3D; najpierw override.cfg z osobnym katalogiem zapisu)
##
## 1. Pula: seria 600 trafień w beton, ziemię, drewno i blachę nie tworzy więcej emiterów niż BURST_POOL, a po przerwie kolejna seria
##    nie tworzy żadnego nowego; pierwsza seria na mapie bez kompilacji potoków GPU zatrzymujących klatkę (rozgrzanie z mapą);
##    koszt wywołania z puli i nowego emitera tylko jako informacja (mediana).
## 2. Odpryski: trafienie w beton, ziemię i drewno puszcza bryłki / drzazgi (siatka bryły, koziołkowanie) i zanikający pył; blacha — iskry.
## 3. Ślady po kulach: każda z czterech powierzchni ma własną teksturę, ziemia większą, blacha mniejszą.
## 4. Pył ze stropu: wybuch pod stropem sypie pył i kamyki z pasa stropu (z opóźnieniem), pod gołym niebem nic.
## 5. Lampy: wybuch obok lampy misji ją rozbuja (model, poświata i światło 3D wychylone od strony wybuchu), daleki nie; po kilku sekundach
##    lampa wraca do spoczynku. Światło 2D (Stalker, ćmy) zostaje na miejscu.
## 6. Cykl życia śladów (IMPACT_MARKS_PLAN.md E0): trafienie w przegrodę bez dekala (maska uszkodzeń), ślad na skale strefy wydobycia znika
##    z wykopaną komórką, punkt kontrolny bossa zostawia ślady, wipe je zdejmuje, zmiana mapy też. Pomiar (informacja): elementy klastrowane
##    w kadrze (światła + dekale) i czas GPU świata przy 0 / 160 / 300 / 500 śladach w kadrze; zrzuty `e0_marks_*` i wróg na osmaleniu.
## 7. Ślady E1–E3: tekstury generatora z normalną i ORM, rysa przy płaskim trafieniu, owal przy 45°, seria w jeden punkt powiększa stary
##    ślad, śrut w jeden kafel daje gniazdo, osmalenie wybuchu na podłodze i ścianie, żar gaśnie, dziobaki odłamków, ładunek bez nich,
##    sadza pod plamą ognia (jedna na miejsce); zrzuty `e1_*`, `e2_*` (najlepiej z `--view3dlit`).
## Wynik: linie [FX-TEST] i kod wyjścia.

const Level3D := preload("res://scripts/level3d.gd")
const View3D := preload("res://scripts/view3d.gd")
const Vfx := preload("res://scripts/vfx.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const ImpactMarks := preload("res://scripts/impact_marks.gd")

var v3d: Node

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[FX-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[FX-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[FX-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(2.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	v3d = m.get_node_or_null("View3D")
	if DisplayServer.get_name() == "headless" or v3d == null or player == null:
		info("test tylko w oknie (widok 3D)")
		_finish()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	Director.set_process(false)
	var lamp: Node2D = null                             # lampa pod litym stropem (nie pod dachem z blachy) w najniższym pomieszczeniu — strop w kadrze
	var roofed: Node2D = null
	var rows: Array = v3d.get("_rows")
	var best := INF
	for ml in get_tree().get_nodes_in_group("mission_lamps"):
		var c := int(floor((ml as Node2D).global_position.x / 16.0))
		var r := int(floor((ml as Node2D).global_position.y / 16.0)) - 1
		if Level3D.is_roof_cell(rows, c, r):
			roofed = ml
			continue
		var h := _floor_below((ml as Node2D).global_position).y
		if h < best:
			best = h
			lamp = ml
	check("lampa misji pod litym stropem na mapie 1.2 (%s)" % (lamp.name if lamp else "-"), lamp != null)
	if lamp == null:
		_finish()
		return
	_place_player(lamp.global_position + Vector2(-60.0, 0.0) + _floor_below(lamp.global_position))
	player.set_physics_process(false)
	await _frames(1.5)
	if OS.get_cmdline_user_args().has("--fxonly=marks"):          # same ślady (sekcje 6–7), bez puli, pyłu i lamp
		await _marks_life()
		await _marks_look(lamp)
		_finish()
		return
	await _pool(lamp)
	_chips()
	_decals()
	await _ceiling(lamp, roofed)
	await _lamps(lamp)
	await _marks_life()
	await _marks_look(lamp)
	_finish()

## Liczba kompilacji potoków GPU od startu, które zatrzymują klatkę (canvas, mesh, surface, draw). Specjalizacje (`SPECIALIZATION`) silnik
## kompiluje w tle, a do tego czasu rysuje ubershaderem — nie przycinają, więc ich nie liczymy.
func _pipelines() -> int:
	var n := 0
	for k in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW]:
		n += int(Performance.get_monitor(k))
	return n

## Odległość od `p` w dół do podłogi (px), żeby postawić gracza pod lampą.
func _floor_below(p: Vector2) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(p + Vector2(0, 2), p + Vector2(0, 600), 1 | 16)
	var hit := (level as Node2D).get_world_2d().direct_space_state.intersect_ray(q)
	return Vector2(0.0, ((hit["position"] as Vector2).y - p.y - 1.0) if not hit.is_empty() else 40.0)

# ---------------------------------------------------------------- 1. pula

const SURFACES := ["concrete", "dirt", "wood", "metal"]

var _barrage_worst := 0.0                ## najdłuższa klatka ostatniej serii [s]

func _barrage(at: Vector2, n: int, per_frame: int) -> void:
	var i := 0
	_barrage_worst = 0.0
	while i < n:
		for k in per_frame:
			var s: String = SURFACES[(i + k) % SURFACES.size()]
			Vfx.impact(level, at + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 0.0)), Vector2.UP, s, (i + k) % 7 == 0)
		i += per_frame
		await get_tree().process_frame
		_barrage_worst = maxf(_barrage_worst, get_process_delta_time())

func _pool(lamp: Node2D) -> void:
	var at := player.global_position + Vector2(30.0, -2.0)
	var new0 := View3D.stat_burst_new
	var us0 := View3D.stat_usec
	var f0 := Engine.get_process_frames()
	var pipes0 := _pipelines()
	await _barrage(at, 600, 12)
	var pipes := _pipelines() - pipes0
	var frames := maxi(1, Engine.get_process_frames() - f0)
	var made := View3D.stat_burst_new - new0
	var nodes := int(v3d.call("burst_nodes"))
	info("seria 600 trafień (12 na klatkę): nowych emiterów %d, w puli %d, widok 3D średnio %.2f ms/klatkę" % [made, nodes,
		float(View3D.stat_usec - us0) / 1000.0 / frames])
	info("pierwsza seria trafień na mapie: najdłuższa klatka %.1f ms, kompilacji potoków GPU zatrzymujących klatkę %d" % [_barrage_worst * 1000.0, pipes])
	# klatki są skwantowane do synchronizacji pionowej (16,7 / 33,3 ms) i zależą od obciążenia maszyny — pewniejsza miara to kompilacje
	# potoków: bez rozgrzania (`_warm_destruction("hitfx")`) pierwsze bryłki i pył kompilowały je w środku serii (ok. 40 ms klatki)
	check("pierwsze trafienia bez kompilacji potoków GPU (odpryski rozgrzane z mapą)", pipes == 0)
	check("pula nie rośnie ponad BURST_POOL (%d ≤ %d)" % [nodes, View3D.BURST_POOL], nodes <= View3D.BURST_POOL)
	check("seria używa emiterów z puli (ponowne użycia %d)" % View3D.stat_burst_reuse, View3D.stat_burst_reuse > 0)
	await _frames(2.5)                                  # wszystkie obłoczki gasną
	var new1 := View3D.stat_burst_new
	await _barrage(at, 40, 4)
	check("po przerwie seria 40 trafień bez nowych emiterów (%d)" % (View3D.stat_burst_new - new1), View3D.stat_burst_new == new1)
	# koszt CPU: obłoczek z puli kontra nowy emiter (dawna droga: węzeł, siatka, add_child, minutnik)
	await _frames(2.5)
	var cfg := {"color": Color(0.6, 0.6, 0.6), "amount": 6, "life": 0.3}
	var world := v3d.get("_world") as Node3D
	var pooled_t: Array = []
	var fresh_t: Array = []
	for round in 3:                                     # naprzemiennie, mediana: pojedyncze wywołanie potrafi czekać na wątek renderu
		for i in 40:
			var t1 := Time.get_ticks_usec()
			v3d.spawn_burst(at, cfg)
			pooled_t.append(Time.get_ticks_usec() - t1)
		await _frames(1.0)
		for i in 40:
			var t1 := Time.get_ticks_usec()
			var p := CPUParticles3D.new()               # dawna droga: węzeł, siatka, add_child, minutnik do zwolnienia
			p.one_shot = true
			p.amount = 6
			p.lifetime = 0.3
			var q := QuadMesh.new()
			q.size = Vector2(0.6, 0.6)
			q.material = v3d.call("_burst_material", cfg)
			p.mesh = q
			world.add_child(p)
			p.emitting = true
			get_tree().create_timer(0.9).timeout.connect(p.queue_free)
			fresh_t.append(Time.get_ticks_usec() - t1)
		await _frames(1.0)
	pooled_t.sort()
	fresh_t.sort()
	var pooled := float(pooled_t[pooled_t.size() / 2])
	var fresh := float(fresh_t[fresh_t.size() / 2])
	info("obłoczek (mediana wywołania): z puli %.0f µs, nowy emiter %.0f µs" % [pooled, fresh])
	# bez sprawdzenia: różnica na samym wywołaniu jest mała (20 kontra 25–37 µs) i w pojedynczym przebiegu potrafi się odwrócić;
	# zysk puli to brak tworzenia i zwalniania węzłów, buforów i minutników przy każdym trafieniu (sprawdzone wyżej licznikiem emiterów)
	await _frames(1.5)

# ---------------------------------------------------------------- 2. odpryski

## Emitery z obłoczkami puszczonymi po numerze `seq0` (`View3D.stat_burst_seq`).
func _since(seq0: int) -> Array:
	var out: Array = []
	for e in v3d.get("_burst_busy"):
		if is_instance_valid(e[0]) and int((e[0] as Node).get_meta("seq", 0)) > seq0:
			out.append(e[0])
	return out

func _burst_count() -> int:
	return View3D.stat_burst_seq

func _chips() -> void:
	var at := player.global_position + Vector2(30.0, -2.0)
	for s in SURFACES:
		var b0 := _burst_count()
		Vfx.impact(level, at, Vector2.UP, s, false)
		var made := _since(b0)
		var solid := 0
		var fade := 0
		for p in made:
			var pp := p as CPUParticles3D
			if pp.mesh is BoxMesh and pp.particle_flag_disable_z:
				solid += 1
			if pp.color_ramp != null:
				fade += 1
		if s == "metal":
			check("blacha: iskry bez bryłek i pyłu (%d obłoczków)" % made.size(), made.size() >= 2 and solid == 0 and fade == 0)
		else:
			check("%s: bryłki / drzazgi i zanikający pył (bryły %d, pył %d)" % [s, solid, fade], solid >= 1 and fade >= 1)
	var b1 := _burst_count()
	Vfx.impact(level, at, Vector2.UP, "wood", false)
	var wood := _since(b1)
	var splinter := false
	for p in wood:
		var bm = (p as CPUParticles3D).mesh
		if bm is BoxMesh and (bm as BoxMesh).size.x > 2.0 * (bm as BoxMesh).size.y:
			splinter = true
	check("drewno: drzazgi wydłużone", splinter)

# ---------------------------------------------------------------- 3. ślady

func _decals() -> void:
	var texs := {}
	var imgs := {}
	for s in SURFACES:
		var t: Texture2D = View3D._hole_tex_for(s)
		texs[s] = t
		imgs[s] = t.get_image().get_data()
	var distinct := true
	for i in SURFACES.size():
		for j in range(i + 1, SURFACES.size()):
			if imgs[SURFACES[i]] == imgs[SURFACES[j]]:
				distinct = false
	check("ślady po kulach: cztery różne tekstury (beton, ziemia, drewno, blacha)", distinct)
	check("nieznana powierzchnia i beton — ten sam krater", View3D._hole_tex_for("ice") == texs["concrete"])
	check("ziemia większy ślad, blacha mniejszy", float(View3D.HOLE_SIZE["dirt"]) > 1.0 and float(View3D.HOLE_SIZE["metal"]) < 1.0)
	var holes: Array = v3d.get("_holes")
	var before := holes.size()
	v3d.call("mark_hit", player.global_position + Vector2(20.0, 0.0), Vector2.UP, "metal")
	var d := (v3d.get("_holes") as Array).back() as Decal
	var tp := String(d.texture_albedo.resource_path) if d != null and d.texture_albedo != null else ""
	check("mark_hit kładzie ślad blachy (%d → %d, %s)" % [before, (v3d.get("_holes") as Array).size(), tp.get_file()],
		d != null and (tp.contains("hole_metal") or d.texture_albedo == texs["metal"]))

# ---------------------------------------------------------------- 4. pył ze stropu

func _box_bursts(seq0: int) -> Array:
	var out: Array = []
	for p in _since(seq0):
		if (p as CPUParticles3D).emission_shape == CPUParticles3D.EMISSION_SHAPE_BOX:
			out.append(p)
	return out

## Wolny kafel z podłogą pod spodem i niebem nad sobą (żaden lity kafel w CEIL_DUST_ROWS + 1 wierszach) — miejsce pod gołym niebem.
func _open_sky() -> Vector2:
	var rows: Array = v3d.get("_rows")
	for r in range(View3D.CEIL_DUST_ROWS + 2, rows.size() - 1):
		var row: String = rows[r]
		for c in range(4, row.length() - 4, 3):
			if Level3D.is_solid_ch(Level3D._ch(rows, c, r)) or not Level3D.is_solid_ch(Level3D._ch(rows, c, r + 1)):
				continue
			var open := true
			for k in range(1, r + 1):
				if Level3D.is_solid_ch(Level3D._ch(rows, c, r - k)) or Level3D.is_platform_ch(Level3D._ch(rows, c, r - k)):
					open = false
					break
			if open:
				return Vector2((c + 0.5) * 16.0, (r + 1) * 16.0 - 4.0)
	return Vector2.INF

func _ceiling(lamp: Node2D, roofed: Node2D) -> void:
	var under := lamp.global_position + Vector2(30.0, 40.0)
	var b0 := _burst_count()
	v3d.call("ceiling_dust", under, 48.0)
	check("bez opóźnienia pyłu jeszcze nie ma", _box_bursts(b0).is_empty())
	await _frames(0.6)
	var dust := _box_bursts(b0)
	var top := INF
	for p in dust:
		top = minf(top, -(p as CPUParticles3D).position.y / Level3D.PX)
	info("pod stropem: %d obłoczków z pasa stropu, najwyżej y = %.0f px (lampa %.0f px)" % [dust.size(), top, lamp.global_position.y])
	check("wybuch pod stropem sypie pył i kamyki", dust.size() >= 2)
	check("pył leci z wysokości stropu (najwyżej %.0f px nad wybuchem)" % (under.y - top), top < under.y - 8.0 and top >= lamp.global_position.y - 32.0)
	if roofed != null:                                  # dach szopy z blachy: słaby pył, bez kamyków
		var b2 := _burst_count()
		v3d.call("ceiling_dust", roofed.global_position + Vector2(30.0, 40.0), 48.0)
		await _frames(0.6)
		var rd := _box_bursts(b2)
		var chips := 0
		for p in rd:
			if (p as CPUParticles3D).mesh is BoxMesh:
				chips += 1
		check("pod dachem z blachy (%s) sam pył bez kamyków (%d obłoczków, kamyki %d)" % [roofed.name, rd.size(), chips], rd.size() >= 1 and chips == 0)
	var sky := _open_sky()
	check("na mapie jest miejsce pod gołym niebem", sky != Vector2.INF)
	if sky != Vector2.INF:
		var b1 := _burst_count()
		v3d.call("ceiling_dust", sky, 48.0)
		await _frames(0.6)
		check("pod gołym niebem (%.0f, %.0f) pyłu nie ma" % [sky.x, sky.y], _box_bursts(b1).is_empty())
	# koszt: pierwszy wybuch w sesji pod gołym niebem (bez pyłu i lamp — dawny koszt), potem wybuch pod stropem
	var first := await _worst_after_blast(sky + Vector2(0.0, -4.0)) if sky != Vector2.INF else 0.0
	var second := await _worst_after_blast(under)
	info("najdłuższa klatka w 1 s po wybuchu: pierwszy w sesji, pod gołym niebem %.1f ms; pod stropem (pył, lampa) %.1f ms" % [first * 1000.0, second * 1000.0])
	check("wybuch pod stropem bez przycięcia ponad 50 ms", second < 0.05)
	# zrzuty: gracz pod lampą w niskim pomieszczeniu
	_place_player(lamp.global_position + Vector2(-80.0, 0.0) + _floor_below(lamp.global_position + Vector2(-80.0, 0.0)))
	await _frames(6.0)
	for srf in SURFACES:                                # zrzuty: każda powierzchnia osobno (obłoczki i ślady)
		var hit_at := player.global_position + Vector2(36.0, -1.0)
		for i in 6:
			Vfx.impact(level, hit_at + Vector2(randf_range(-6.0, 6.0), 0.0), Vector2.UP, srf, false)
			await _frames(0.05)
		await _shot("hit_" + srf)
		await _frames(0.9)
		await _shot("after_" + srf)
		await _frames(1.0)
	Vfx.explosion(level, lamp.global_position + Vector2(50.0, 30.0) + Vector2(0.0, _floor_below(lamp.global_position + Vector2(50.0, 30.0)).y - 4.0), 48.0)
	await _frames(0.9)
	await _shot("ceiling_dust")

## Najdłuższa klatka (s) przez sekundę po wybuchu w `at` (sam obraz: `Vfx.explosion`).
func _worst_after_blast(at: Vector2) -> float:
	await _frames(0.5)
	Vfx.explosion(level, at, 48.0)
	var worst := 0.0
	var t := 0.0
	while t < 1.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		worst = maxf(worst, get_process_delta_time())
	await _frames(1.0)
	return worst

# ---------------------------------------------------------------- 5. lampy

func _lamp_model(lamp: Node2D) -> Node3D:
	var items: Dictionary = v3d.get("_items")
	for ch in lamp.get_children():
		if ch is ItemsHd.ItemMark and items.has(ch.get_instance_id()):
			return items[ch.get_instance_id()][1] as Node3D
	return null

func _lamp_light(lamp: Node2D) -> Node3D:
	var lights: Dictionary = v3d.get("_lights")
	var gl = lamp.get("_light")
	if gl == null or not lights.has((gl as Object).get_instance_id()):
		return null
	return lights[(gl as Object).get_instance_id()][1] as Node3D

func _lamps(lamp: Node2D) -> void:
	await _frames(9.0)                                  # spokój po zrzucie z wybuchem
	check("lampa w spoczynku przed testem (rozbujanych %d)" % int(v3d.call("swaying_lamps")), int(v3d.call("swaying_lamps")) == 0)
	var mdl := _lamp_model(lamp)
	var li := _lamp_light(lamp)
	check("lampa ma model i światło 3D", mdl != null and li != null)
	if mdl == null or li == null:
		return
	var rest_x := li.position.x
	var rest_rot := mdl.rotation.z
	var light2d := (lamp.get("_light") as Node2D).global_position
	# daleki wybuch: poza zasięgiem
	v3d.call("kick_lamps", lamp.global_position + Vector2(1200.0, 0.0), 48.0)
	check("daleki wybuch lampy nie rusza", int(v3d.call("swaying_lamps")) == 0)
	# wybuch z lewej: dół lampy odchyla się w prawo
	Vfx.explosion(level, lamp.global_position + Vector2(-70.0, 40.0), 48.0)
	var max_dx := 0.0
	var max_rot := 0.0
	var t := 0.0
	var worst := 0.0
	while t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		worst = maxf(worst, get_process_delta_time())
		max_dx = maxf(max_dx, li.position.x - rest_x)
		max_rot = maxf(max_rot, absf(mdl.rotation.z - rest_rot))
	info("najdłuższa klatka w 0,5 s po wybuchu pod stropem (pył, lampa): %.1f ms" % (worst * 1000.0))
	info("po wybuchu z lewej: światło 3D przesunięte o %.1f cm, model obrócony o %.1f°" % [max_dx * 100.0, rad_to_deg(max_rot)])
	check("lampa rozbujana od strony wybuchu (światło 3D w prawo)", max_dx > 0.01)
	check("model lampy się wychyla", max_rot > deg_to_rad(3.0))
	check("światło 2D zostaje na miejscu (Stalker, ćmy)", (lamp.get("_light") as Node2D).global_position.distance_to(light2d) < 0.01)
	await _shot("lamp_sway")
	await _frames(9.0)
	check("po kilku sekundach lampa w spoczynku (rozbujanych %d, światło %.1f cm od spoczynku)" % [int(v3d.call("swaying_lamps")),
		absf(li.position.x - rest_x) * 100.0], int(v3d.call("swaying_lamps")) == 0 and absf(li.position.x - rest_x) < 0.005)

## Zrzut do `--fxshots=KATALOG`.
func _shot(name: String) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxshots="):
			dir = a.substr("--fxshots=".length())
	if dir == "":
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	info("zrzut %s" % dir.path_join(name + ".png"))

# ---------------------------------------------------------------- 6. cykl życia śladów (IMPACT_MARKS_PLAN.md E0)

func _marks() -> Vector2i:
	return v3d.call("marks_count")

func _marks_life() -> void:
	v3d.call("clear_marks")
	# przegroda: odpryski bez dekala
	var bw: Node2D = null
	for n in get_tree().get_nodes_in_group("breakables"):
		if n is Node2D and String((n.call("mat_def") as Dictionary).get("surface", "")) != "":
			bw = n
			break
	if bw == null:
		for n in level.get_children():
			if n.has_method("mat_def") and n.has_method("hit_rect"):
				bw = n
				break
	if bw != null:
		var rc: Rect2 = bw.call("hit_rect")
		var n0 := _marks().x
		Vfx.impact(level, rc.get_center(), Vector2.LEFT, "wood", false, false)
		check("trafienie w przegrodę %s: odpryski bez dekala (%d → %d)" % [bw.name, n0, _marks().x], _marks().x == n0)
	else:
		info("brak przegrody na mapie — pominięte")
	var n1 := _marks().x
	Vfx.impact(level, player.global_position + Vector2(30.0, 0.0), Vector2.UP, "concrete")
	check("trafienie w kafel kładzie dekal (%d → %d)" % [n1, _marks().x], _marks().x == n1 + 1)
	# strefa wydobycia: ślad na skale znika z wykopaną komórką
	var zone: Node2D = null
	var rock := Vector2.INF
	for z in get_tree().get_nodes_in_group("dig_zones"):
		var r: Rect2 = z.call("rect_px")
		for yy in range(int(r.position.y) + 1, int(r.end.y) - 4, 2):
			for xx in range(int(r.position.x) + 4, int(r.end.x) - 4, 4):
				if bool(z.call("solid_at_px", Vector2(xx, yy))) and not bool(z.call("solid_at_px", Vector2(xx, yy - 6))):
					rock = Vector2(xx, yy)
					break
			if rock != Vector2.INF:
				break
		if rock != Vector2.INF:
			zone = z
			break
	if zone != null:
		v3d.call("mark_hit", rock - Vector2(0.0, 2.0), Vector2.UP, "dirt")
		var d: Decal = (v3d.get("_holes") as Array).back()
		zone.call("blast_dig", rock, 20.0)
		var t := 0.0
		while is_instance_valid(d) and not d.is_queued_for_deletion() and t < 3.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		check("ślad na skale strefy %s znika po wykopaniu (%.2f s)" % [zone.name, t], not is_instance_valid(d) or d.is_queued_for_deletion())
	else:
		info("brak strefy wydobycia ze skałą pod powietrzem — pominięte")
	# pomiar i zrzuty, potem punkt kontrolny i wipe
	await _marks_budget()
	var before := _marks()
	level.reset_breakables(level.breakables_state())
	await _frames(0.3)
	check("punkt kontrolny bossa zostawia ślady (%s → %s)" % [before, _marks()], _marks() == before and before.x > 0)
	level.reset_breakables()
	await _frames(0.3)
	check("wipe zdejmuje ślady (%s → %s)" % [before, _marks()], _marks() == Vector2i.ZERO)
	Vfx.impact(level, player.global_position + Vector2(30.0, 0.0), Vector2.UP, "concrete")
	Vfx.explosion(level, player.global_position + Vector2(40.0, -6.0), 48.0)
	var b2 := _marks()
	level.map_changed.emit(String(level.map_id))
	check("zmiana mapy zdejmuje ślady (%s → %s)" % [b2, _marks()], b2.x > 0 and _marks() == Vector2i.ZERO)

## Elementy klastrowane w kadrze kamery świata: światła punktowe i stożkowe z zasięgiem w bryle widzenia oraz dekale.
func _clustered() -> Vector2i:
	var cam: Camera3D = v3d.get("_cam_a")
	var lights := 0
	var decals := 0
	for n in (v3d.get("_world") as Node).find_children("*", "VisualInstance3D", true, false):
		if not (n as Node3D).is_visible_in_tree():
			continue
		var pos := (n as Node3D).global_position
		if n is OmniLight3D or n is SpotLight3D:
			var r := float((n as OmniLight3D).omni_range) if n is OmniLight3D else float((n as SpotLight3D).spot_range)
			var p := cam.unproject_position(pos)
			if cam.is_position_in_frustum(pos) or (p.distance_to(Vector2(cam.get_viewport().size) * 0.5) < r * 120.0 and not cam.is_position_behind(pos)):
				lights += 1
		elif n is Decal and cam.is_position_in_frustum(pos):
			decals += 1
	return Vector2i(lights, decals)

func _gpu_ms(rid: RID, seconds: float) -> float:
	var acc := 0.0
	var k := 0
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		acc += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		k += 1
	return acc / maxf(1.0, float(k))

func _marks_budget() -> void:
	var vp: SubViewport = v3d.get("_vp_bg")
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(0.5)
	var lim := int(ProjectSettings.get_setting("rendering/limits/cluster_builder/max_clustered_elements", 512))
	var base := await _gpu_ms(rid, 1.0)
	var c0 := _clustered()
	info("elementy klastrowane w kadrze bez śladów: światła %d, dekale %d (limit %d); GPU świata %.2f ms" % [c0.x, c0.y, lim, base])
	var at := player.global_position
	var placed := 0
	v3d.set("max_holes", 600)
	for target in [160, 300, 500]:
		while placed < target:
			var p := at + Vector2(randf_range(-260.0, 260.0), randf_range(-120.0, 10.0))
			var q := PhysicsRayQueryParameters2D.create(p, p + Vector2(0, 200), 1 | 16)
			var hit := (level as Node2D).get_world_2d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				v3d.call("mark_hit", hit["position"], hit["normal"], "concrete")
			placed += 1
		var saved: int = v3d.get("max_holes")
		await _frames(0.3)
		var c := _clustered()
		var g := await _gpu_ms(rid, 1.0)
		info("%d trafień (limit na czas pomiaru %d): w kadrze światła %d + dekale %d = %d z %d; GPU świata %.2f ms (+%.2f)" % [
			target, saved, c.x, c.y, c.x + c.y, lim, g, g - base])
	await _shot("e0_marks_grid")
	v3d.set("max_holes", -1)
	v3d.call("mark_hit", at, Vector2.UP, "concrete")          # przycięcie do limitu
	# bryła w warstwie świata (jak model wroga, enemy3d.gd bez własnej warstwy) na osmaleniu: czy dekal ją maluje (zrzut, błąd 3)
	var fp := at + Vector2(60.0, -10.0)
	var foot := fp + _floor_below(fp)
	v3d.call("mark_scorch", foot, 48.0)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 1.6, 0.4)
	box.mesh = bm
	box.layers = View3D.LAYER_WORLD
	(v3d.get("_world") as Node3D).add_child(box)
	box.global_position = Level3D.px_to_m(foot) + Vector3(0.0, 0.8, View3D.MARK_Z)
	await _frames(0.3)
	await _shot("e0_marks_scorch")
	box.queue_free()
	RenderingServer.viewport_set_measure_render_time(rid, false)

# ---------------------------------------------------------------- 7. ślady E1–E3 (IMPACT_MARKS_PLAN.md)

## Ściana najbliżej gracza w poziomie (promień w lewo i w prawo na wysokości piersi): [punkt, normalna] albo [].
func _wall_near(at: Vector2) -> Array:
	var space := (level as Node2D).get_world_2d().direct_space_state
	var best: Array = []
	var bd := INF
	for sx in [-1.0, 1.0]:
		var q := PhysicsRayQueryParameters2D.create(at, at + Vector2(sx * 220.0, 0.0), 1 | 16)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector2).distance_to(at) < bd and absf((hit["normal"] as Vector2).x) > 0.9 				and String(level.call("tile_char_at", hit["position"], hit["normal"])) in ["#", "C"]:     # pełna ściana, nie koniec kładki
			bd = (hit["position"] as Vector2).distance_to(at)
			best = [hit["position"], hit["normal"]]
	return best

## Wierzch gruntu w kolumnie `x` pod graczem: promień od wysokości piersi w dół (start w gruncie omijał podłogę i trafiał w tunel niżej).
func _ground(x: float) -> Vector2:
	var p := Vector2(x, player.global_position.y - 20.0)
	var q := PhysicsRayQueryParameters2D.create(p, p + Vector2(0, 200), 1 | 16)
	var hit := (level as Node2D).get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p + Vector2(0, 200)

func _last_hole() -> Decal:
	var h: Array = v3d.get("_holes")
	return h.back() as Decal if not h.is_empty() else null

func _tex_name(d: Decal) -> String:
	return String(d.texture_albedo.resource_path).get_file() if d != null and d.texture_albedo != null else ""

func _marks_look(lamp: Node2D) -> void:
	v3d.call("clear_marks")
	_place_player(lamp.global_position + Vector2(-60.0, 0.0) + _floor_below(lamp.global_position))   # sztuczna zmiana mapy (sekcja 6) wraca gracza na start
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxat="):                      # inne miejsce zrzutów śladów, np. tunel przy ścianie: --fxat=4456,815
			var xy := a.substr(7).split(",")
			_place_player(Vector2(float(xy[0]), float(xy[1])))
	await _frames(1.0)
	var chest := player.global_position + Vector2(0.0, -12.0)
	var floor_at := _ground(player.global_position.x + 24.0)
	info("ślady przy graczu %s: kafel '%s', pod ziemią %s, rodzaj %s" % [player.global_position.round(), level.tile_char_at(floor_at, Vector2.UP),
		level.is_underground(floor_at), v3d.call("_mark_kind", floor_at, Vector2.UP, "concrete")])
	# kula prostopadle w podłogę: tekstura generatora z normalną i ORM
	v3d.call("mark_hit", floor_at, Vector2.UP, "concrete", Vector2.DOWN, 1.0)
	var d := _last_hole()
	check("ślad kuli z generatora z normalną i ORM (%s)" % _tex_name(d), d != null and _tex_name(d).begins_with("hole_")
		and d.texture_normal != null and d.texture_orm != null)
	# 45°: owal
	v3d.call("mark_hit", floor_at + Vector2(30.0, 0.0), Vector2.UP, "concrete", Vector2(1, 1).normalized(), 1.0)
	d = _last_hole()
	check("kula pod 45°: owal wzdłuż toru (%.2f × %.2f m)" % [d.size.x, d.size.z], d != null and d.size.x > d.size.z * 1.3)
	# płasko w blachę: rysa
	v3d.call("mark_hit", floor_at + Vector2(60.0, 0.0), Vector2.UP, "metal", Vector2(1, 0.12).normalized(), 1.0)
	d = _last_hole()
	var fk := String(v3d.call("_mark_kind", floor_at, Vector2.UP, "metal"))
	check("płasko (ok. 7°) w podłogę (%s): %s (%s, %.2f × %.2f m)" % [fk, "rysa" if fk in ImpactMarks.GRAZE_KINDS else "długi owal", _tex_name(d),
		d.size.x if d else 0.0, d.size.z if d else 0.0], d != null and (_tex_name(d).begins_with("graze_") if fk in ImpactMarks.GRAZE_KINDS
		else d.size.x > d.size.z * 2.0))
	# seria w jeden punkt: jeden ślad, większy
	var n0: int = (v3d.get("_holes") as Array).size()
	var spot := floor_at + Vector2(-40.0, 0.0)
	v3d.call("mark_hit", spot, Vector2.UP, "concrete", Vector2.DOWN, 1.0)
	var first := _last_hole()
	var s0 := first.size.z if first != null else 0.0
	for i in 12:
		v3d.call("mark_hit", spot + Vector2(randf_range(-0.2, 0.2), 0.0), Vector2.UP, "concrete", Vector2.DOWN, 1.0)
	var n1: int = (v3d.get("_holes") as Array).size()
	check("seria 13 kul w jeden punkt: 1 ślad (%d → %d), większy (%.3f → %.3f m, ≤ ×%.1f)" % [n0, n1, s0, first.size.z if first else 0.0, ImpactMarks.MERGE_MAX],
		n1 == n0 + 1 and first != null and first.size.z > s0 * 1.2 and first.size.z <= s0 * ImpactMarks.MERGE_MAX + 0.001)
	# śrut w jeden kafel: gniazdo
	var w := _wall_near(chest)
	if not w.is_empty():
		var wp: Vector2 = w[0]
		var wn: Vector2 = w[1]
		var c0: int = (v3d.get("_holes") as Array).size()
		for i in 8:
			v3d.call("mark_hit", wp + Vector2(0.0, -2.0 + float(i % 4) * 1.5), wn, "concrete", -wn, ImpactMarks.PELLET_SIZE)
		var c1: int = (v3d.get("_holes") as Array).size()
		var cl := false
		for h in v3d.get("_holes"):
			if is_instance_valid(h) and _tex_name(h).begins_with("cluster_"):
				cl = true
		check("8 śrucin w jeden kafel ściany: gniazdo zamiast 8 dziurek (%d → %d dekali)" % [c0, c1], cl and c1 - c0 <= 2)
		var lh := _last_hole()
		var fr: Decal = lh.get_meta("front") if lh != null and lh.has_meta("front") else null
		info("ściana w %s n=%s; ślad %s, odprysk %s" % [wp, wn, lh.global_position if lh else Vector3.ZERO, fr.global_position if fr else "brak"])
		check("ślad na ścianie ma odprysk na czole bryły (rzut wzdłuż Z)", fr != null and absf(fr.global_transform.basis.y.normalized().z) > 0.99)
		await _frames(0.2)
		await _shot("e1_wall")
	else:
		info("brak ściany obok gracza — gniazdo śrutu pominięte")
	await _frames(0.3)
	await _shot("e1_floor")
	# wybuch przy ścianie: osmalenie na podłodze i ścianie, żar, dziobaki
	v3d.call("clear_marks")
	if not w.is_empty():
		var wp2: Vector2 = w[0]
		var wn2: Vector2 = w[1]
		var bp := wp2 + wn2 * 18.0
		var gy := _ground(bp.x).y
		var floor_near := gy - wp2.y < 40.0                           # podłoga pod wybuchem w zasięgu fali (na 1.2 obok gracza bywa szyb)
		if floor_near:
			bp.y = gy - 10.0
		Vfx.explosion(level, bp, 48.0, true)
		var sc: Array = v3d.get("_scorches")
		var on_floor := false
		var on_wall := false
		var glow := 0.0
		for s in sc:
			if not is_instance_valid(s):
				continue
			var up := (s as Decal).global_transform.basis.y
			if up.y > 0.9:
				on_floor = true
			if absf(up.x) > 0.9:
				on_wall = true
			glow = maxf(glow, (s as Decal).emission_energy)
		check("granat przy ścianie: osmalenie na ścianie%s (%d osmaleń)" % [" i na podłodze" if floor_near else " (podłoga poza zasięgiem)", sc.size()],
			on_wall and (on_floor or not floor_near))
		check("żar tuż po wybuchu (emisja %.2f)" % glow, glow > 1.0)
		var pocks := 0
		for h in v3d.get("_holes"):
			if is_instance_valid(h) and _tex_name(h).begins_with("pock_"):
				pocks += 1
		info("dziobaki odłamków: %d" % pocks)
		await _frames(0.6)
		await _shot("e2_blast")
		await _frames(View3D.SCORCH_GLOW_S + 0.5)
		var glow2 := 0.0
		for s in v3d.get("_scorches"):
			if is_instance_valid(s):
				glow2 = maxf(glow2, (s as Decal).emission_energy)
		check("żar gaśnie po %.1f s (%.2f)" % [View3D.SCORCH_GLOW_S, glow2], glow2 < 0.05)
		await _shot("e2_blast_cold")
		v3d.call("clear_marks")
		Vfx.explosion(level, bp, 48.0, false)
		var pk2 := 0
		for h in v3d.get("_holes"):
			if is_instance_valid(h) and _tex_name(h).begins_with("pock_"):
				pk2 += 1
		check("ładunek burzący (bez odłamków): bez dziobaków (%d)" % pk2, pk2 == 0)
	else:
		info("brak ściany obok gracza — wybuch przy ścianie pominięty")
	# wybuch daleko od wszystkiego (w powietrzu): bez osmalenia
	v3d.call("clear_marks")
	Vfx.explosion(level, Vector2(player.global_position.x, -600.0), 48.0, true)        # nad mapą (w tunelu 400 px w górę to strop)
	var air: int = (v3d.get("_scorches") as Array).size()
	check("wybuch wysoko w powietrzu: bez osmalenia (%d)" % air, air == 0)
	# sadza pod plamą ognia: jedna na miejsce
	v3d.call("clear_marks")
	v3d.call("mark_soot", floor_at + Vector2(0.0, -4.0), 28.0)
	v3d.call("mark_soot", floor_at + Vector2(3.0, -4.0), 28.0)
	var so: Array = v3d.get("_scorches")
	check("sadza pod plamą ognia, druga w tym samym miejscu nic nie dokłada (%d)" % so.size(), so.size() == 1
		and is_instance_valid(so[0]) and (so[0] as Decal).modulate.a < 0.9 and (so[0] as Decal).texture_emission == null)
	await _frames(0.3)
	await _shot("e3_soot")
	v3d.call("clear_marks")
