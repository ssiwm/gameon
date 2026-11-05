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
## Wynik: linie [FX-TEST] i kod wyjścia.

const Level3D := preload("res://scripts/level3d.gd")
const View3D := preload("res://scripts/view3d.gd")
const Vfx := preload("res://scripts/vfx.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

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
	await _pool(lamp)
	_chips()
	_decals()
	await _ceiling(lamp, roofed)
	await _lamps(lamp)
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
	check("mark_hit kładzie ślad blachy (%d → %d)" % [before, (v3d.get("_holes") as Array).size()], d != null and d.texture_albedo == texs["metal"])

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
