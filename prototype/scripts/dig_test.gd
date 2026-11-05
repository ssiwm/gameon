extends "res://scripts/stalker_test.gd"
## Strefy wydobycia (DESTRUCTION_PLAN.md D5) na mapie testowej t_dig: ruch i kopanie (pomiary ze spike'u S2), materiały i narzędzia, hałas,
## nawigacja i siatka dźwięku po wykopie, wybuch, stan strefy (migawka, wipe), czas przebudowy.
##
##   godot --headless --path . -- --host --nobot --mission=t_dig --digtest --autoquit=120
##   w oknie: + --digshots=KATALOG (zrzuty PNG w kluczowych chwilach; najpierw override.cfg z osobnym katalogiem zapisu)
##
## DigZone1: ziemia bez wtrąceń, kafle 2–11 × 10–17 (wierzch równo z podłogą hali); DigZone2: skała z żyłą, kafle 30–37 × 10–15.
## 1. wierzch strefy równo z sąsiednimi kaflami, przejście przez szew strefa / mapa bez zatrzymania i podskoku;
## 2. dół: ciosy kilofem w dół do głębokości 2 kafli, ile ciosów i czy da się wyskoczyć; zakopanie i wyjście stopniami po skosie;
## 3. tunel w bok z dna dołu: ciosy + marsz, czy postać się mieści, czy tunel schodzi w dół, postęp na cios; schody po skosie;
## 4. nawigacja i siatka dźwięku: wykopany kafel przestaje być bryłą;
## 5. materiały i narzędzia: skała 3 ciosy, żyła 4, maczeta nie bierze skały (kilof wybiera się sam), ziemię maczetą 2 ciosy i ciszej;
## 6. wybuch (combat.gd `explode`) wycina koło w skale;
## 7. stan: migawka z punktu kontrolnego i wipe przywracają strefę (gęstość, kafle, nawigacja), gracz w zasypanym wykopie wychodzi na wierzch;
## 8. czasy przebudowy fragmentu (kontur + kolizja) i siatki 3D.
## Wynik: linie [DIG-TEST] (PASS / FAIL / INFO) i kod wyjścia.

const Weapons := preload("res://scripts/weapons.gd")
const Level3D := preload("res://scripts/level3d.gd")

const DigMats := preload("res://scripts/dig_materials.gd")
const Combat := preload("res://scripts/combat.gd")

var zone: Node2D
var rock: Node2D
var pick := -1
var blade := -1
var _noise: Array = []                    ## [ilość, pozycja] hałasu „dig” z NoiseMgr.noise_added

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[DIG-TEST] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[DIG-TEST] INFO  %s" % label)

func _finish() -> void:
	print("[DIG-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	zone = level.get_node_or_null("DigZone1")
	rock = level.get_node_or_null("DigZone2")
	check("mapa t_dig ma gracza i dwie strefy wydobycia (%s)" % level.map_id, player != null and zone != null and rock != null and level.map_id == "t_dig")
	if player == null or zone == null or rock == null:
		_finish()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	Director.set_process(false)
	pick = Weapons.index_of("kilof")
	blade = Weapons.index_of("maczeta")
	NoiseMgr.noise_added.connect(_on_noise)
	var dig0: int = (level._dig_cells as Dictionary).size()
	check("kafle stref są na starcie bryłą dla nawigacji (%d kafli: 80 + 48)" % dig0, dig0 == 128 and level._is_solid(5, 12) and level._is_solid(33, 12))
	await _surface()
	await _pit()
	await _tunnel()
	_nav_check(dig0)
	await _materials()
	await _blast()
	await _state(dig0)
	_timings()
	_finish()

func _on_noise(amount: float, pos: Vector2, tag: String) -> void:
	if tag == "dig":
		_noise.append([amount, pos])

## Zrzut okna do `--digshots=KATALOG` (w oknie; headless nic nie robi).
func _shot(name: String) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--digshots="):
			dir = a.substr("--digshots=".length())
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(0.6)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	info("zrzut %s" % dir.path_join(name + ".png"))

func _release_all() -> void:
	for a in ["move_left", "move_right", "jump", "crouch"]:
		Input.action_release(a)

## Cios kilofem z miejsca gracza w kierunku `dir` (ta sama droga co cios z wejścia: `_server_melee` → `DigZone.melee_dig`).
func _swing(dir: Vector2, w := -1, z: Node2D = null) -> bool:
	if z == null:
		z = zone
	var before: int = z.digs
	player.weapons._server_melee(player.global_position + Vector2(0, -9), dir.normalized(), pick if w < 0 else w, player.player_id)
	await _frames(0.05)
	if z.digs == before:                    # diagnostyka: w co trafił promień ciosu
		var o: Vector2 = player.global_position + Vector2(0, -9)
		var q := PhysicsRayQueryParameters2D.create(o, o + dir.normalized() * 24.0, 1)
		var hit := player.get_world_2d().direct_space_state.intersect_ray(q)
		info("  pudło: stopy (%.1f, %.1f) kierunek %s → %s" % [player.global_position.x, player.global_position.y, dir,
			"nic w zasięgu" if hit.is_empty() else "%s przy %s" % [(hit["collider"] as Node).get_path(), hit["position"]]])
	return z.digs > before

# ---------------------------------------------------------------- 1. wierzch strefy

const TOP := 10.0 * 16.0                  ## wierzch stref i podłoga hali (y stóp)

var _flag := false                        ## wyniki z lambd: lambda GDScript kopiuje zmienne lokalne, pola obiektu nie
var _cnt := 0
var _ys: Array[Vector2] = []

## Marsz w stronę `action` przez `secs` s; zbiera (x, y) stóp co klatkę fizyki do `_ys`.
func _walk(action: String, secs: float) -> void:
	_ys.clear()
	Input.action_press(action)
	await _frames(secs, func(_t: float, _dt: float) -> void: _ys.append(player.global_position))
	_release_all()

func _y_spread() -> Vector3:              ## (min y, max y, x przy min y)
	var lo := Vector2(0, INF)
	var hi := -INF
	for p in _ys:
		if p.y < lo.y:
			lo = p
		hi = maxf(hi, p.y)
	return Vector3(lo.y, hi, lo.x)

func _surface() -> void:
	_place_player(Vector2(3.5 * 16.0, TOP - 2.0))
	await _frames(0.4)
	check("gracz stoi na wierzchu strefy (stopy y=%.2f, oczekiwane %.0f)" % [player.global_position.y, TOP],
		player.is_on_floor() and absf(player.global_position.y - TOP) < 0.6)
	var x0: float = player.global_position.x
	await _walk("move_right", 2.0)          # przez strefę i szew z mapą (kolumna 12, x = 192), przed DigZone2 od kolumny 30
	var dx: float = player.global_position.x - x0
	var sp := _y_spread()
	info("marsz w prawo: %.0f px w 2 s, y od %.2f (przy x %.0f) do %.2f" % [dx, sp.x, sp.z, sp.y])
	check("przejście przez szew strefa → mapa bez zatrzymania (> 150 px w 2 s)", dx > 150.0)
	check("bez podskoku na szwie (rozrzut y < 1 px)", sp.y - sp.x < 1.0)
	x0 = player.global_position.x
	await _walk("move_left", 2.0)
	sp = _y_spread()
	info("marsz w lewo: z x %.0f do %.0f, y od %.2f (przy x %.0f) do %.2f" % [x0, player.global_position.x, sp.x, sp.z, sp.y])
	await _shot("s2_1_surface")
	check("powrót w lewo przez szew (> 150 px w 2 s albo do ściany hali)", x0 - player.global_position.x > 150.0 or player.global_position.x < 1.0 * 16.0 + 8.0)
	check("bez podskoku w lewo (rozrzut y < 1 px)", sp.y - sp.x < 1.0)

# ---------------------------------------------------------------- 2. dół

func _dump_segments(r: Rect2) -> void:
	var pp: Vector2 = player.global_position
	for sh in zone._shapes:
		var sg: PackedVector2Array = sh.segments
		for k in range(0, sg.size(), 2):
			var a: Vector2 = sg[k] + zone.global_position
			var b: Vector2 = sg[k + 1] + zone.global_position
			if r.has_point((a + b) * 0.5):
				info("    odcinek %s → %s (względem stóp %s)" % [a, b, (a + b) * 0.5 - pp])

## Kopie w dół do głębokości `depth` px pod wierzchem; zwraca liczbę ciosów.
func _dig_down(depth: float) -> int:
	var hits := 0
	while hits < 30 and player.global_position.y - TOP < depth - 0.5:
		if not await _swing(Vector2.DOWN):
			info("cios w dół #%d nie trafił w strefę (stopy %.1f)" % [hits + 1, player.global_position.y])
			break
		hits += 1
		await _frames(0.85)
	return hits

## Skok z przytrzymaniem w stronę `action`; czy stopy wróciły na wierzch.
func _jump_out(action: String) -> bool:
	_flag = false
	_ys.clear()
	var y_start: float = player.global_position.y
	var on_floor: bool = player.is_on_floor()
	Input.action_press("jump")
	Input.action_press(action)
	await _frames(1.2, func(_t: float, _dt: float) -> void:
		_ys.append(player.global_position)
		if player.global_position.y <= TOP + 0.6 and player.is_on_floor():
			_flag = true)
	_release_all()
	await _frames(0.3)
	var sp0 := _y_spread()
	info("  skok: start (%.1f, %.1f), szczyt y %.1f przy x %.1f, koniec (%.1f, %.1f), klatek %d" % [_ys[0].x if _ys.size() > 0 else 0.0, y_start, sp0.x, sp0.z, player.global_position.x, player.global_position.y, _ys.size()])
	if not _flag:
		var sp := _y_spread()
		info("  wyskok nieudany: start y %.1f (na ziemi: %s), szczyt y %.1f przy x %.1f, koniec (%.1f, %.1f); dead %s stun %.2f grabbed %s v %s fizyka %s" %
			[y_start, on_floor, sp.x, sp.z, player.global_position.x, player.global_position.y, player.dead, player.stun_t, player.grabbed,
			player.velocity, player.is_physics_processing()])
		var pp: Vector2 = player.global_position
		for sh in zone._shapes:
			var sg: PackedVector2Array = sh.segments
			for k in range(0, sg.size(), 2):
				var a: Vector2 = sg[k] + zone.global_position
				var b: Vector2 = sg[k + 1] + zone.global_position
				if Rect2(pp - Vector2(14, 30), Vector2(28, 40)).has_point((a + b) * 0.5):
					info("    odcinek %s → %s" % [a - pp, b - pp])
	return _flag

func _pit() -> void:
	_place_player(Vector2(6.5 * 16.0, TOP - 2.0))
	await _frames(0.3)
	var x0: float = player.global_position.x
	var hits := await _dig_down(32.0)
	var depth: float = player.global_position.y - TOP
	info("dół na 2 kafle: %d ciosów w dół (%.1f px, %.1f px na cios, ok. %.1f s przy cooldownie 0,9 s), x %.1f → %.1f" %
		[hits, depth, depth / maxf(hits, 1), hits * 0.9, x0, player.global_position.x])
	check("dół na 2 kafle w 2–5 ciosach", depth >= 31.5 and hits >= 2 and hits <= 5)
	await _shot("s2_2_pit")
	check("z dołu na 2 kafle da się wyskoczyć (skok + bok)", await _jump_out("move_right"))
	# głębiej niż skok (ok. 44 px) + skos krawędzi (4 px): czy da się zakopać i czy stopnie po skosie w górę wyprowadzają
	_place_player(Vector2(x0, TOP + depth - 2.0))
	await _frames(0.4)
	var hits3 := await _dig_down(52.0)
	var d3: float = player.global_position.y - TOP
	var bottom: Vector2 = player.global_position
	var out3 := await _jump_out("move_right")
	if not out3:
		out3 = await _jump_out("move_left")
	info("dół głębszy niż skok: +%d ciosów, głębokość %.1f px; wyskok bez kopania: %s" % [hits3, d3, "TAK" if out3 else "NIE"])
	check("z dołu na 52+ px nie da się wyskoczyć bez kopania (zakopanie możliwe → reguła D5 potrzebna)", not out3)
	# ratunek: cios po skosie w górę (stopień) + skok w bok, aż stopy na wierzchu
	_place_player(bottom + Vector2(0, -2))
	await _frames(0.4)
	var tries := 0
	var out := false
	while tries < 8 and not out:
		await _swing(Vector2(1, -1))
		tries += 1
		out = await _jump_out("move_right")
	info("wyjście z dołu stopniami po skosie w górę: %s po %d ciosach, stopy (%.0f, %.1f)" %
		["TAK" if out else "NIE", tries, player.global_position.x, player.global_position.y])
	check("z dołu na 52+ px wychodzi się stopniami po skosie (≤ 6 ciosów)", out and tries <= 6)
	_place_player(Vector2(bottom.x + 20.0, TOP - 2.0))
	await _shot("s2_3_steps")
	set_meta("pit_bottom", bottom)

# ---------------------------------------------------------------- 3. tunel w bok i schody w dół

## Cios w kierunku `dir` i marsz w stronę `action` na 0,85 s, `n` razy. Zwraca (postęp x, zmiana y, ciosy bez postępu, klatki z sufitem).
func _bore(dir: Vector2, action: String, n: int, x_stop: float) -> Vector4:
	var x0: float = player.global_position.x
	var y0: float = player.global_position.y
	var stuck := 0
	_cnt = 0
	for h in n:
		if player.global_position.x >= x_stop:
			break
		await _swing(dir)
		var xa: float = player.global_position.x
		Input.action_press(action)
		await _frames(0.85, func(_t: float, _dt: float) -> void:
			if player.is_on_ceiling():
				_cnt += 1)
		_release_all()
		if absf(player.global_position.x - xa) < 1.0:
			stuck += 1
	return Vector4(player.global_position.x - x0, player.global_position.y - y0, stuck, _cnt)

func _tunnel() -> void:
	# pod schodami z punktu 2: z dna dołu na 3 kafle jeszcze 2 kafle w dół, potem w bok
	var pit: Vector2 = get_meta("pit_bottom", Vector2(6.5 * 16.0, TOP + 48.0))
	_place_player(pit + Vector2(0, -2))
	await _frames(0.4)
	await _dig_down(pit.y - TOP + 24.0)
	var start: Vector2 = player.global_position
	var d0: int = zone.digs
	var r := await _bore(Vector2.RIGHT, "move_right", 8, 11.0 * 16.0 - 8.0)
	var hits: int = zone.digs - d0
	info("tunel w bok: %d ciosów, postęp %.0f px (%.1f px = %.2f kafla na cios), zmiana dna %+.1f px, ciosy bez postępu %d, klatki z sufitem %d" %
		[hits, r.x, r.x / maxf(hits, 1), r.x / maxf(hits, 1) / 16.0, r.y, r.z, r.w])
	check("tunel w bok: postać się mieści i idzie naprzód (> 8 px na cios)", r.x / maxf(hits, 1) > 8.0)
	check("dno tunelu nie schodzi (|zmiana| ≤ 1 px)", absf(r.y) <= 1.0)
	var prof := []                            # profil dna: promień w dół co 4 px od wejścia tunelu
	var space := player.get_world_2d().direct_space_state
	var x := start.x
	while x <= player.global_position.x + 0.1:
		var q := PhysicsRayQueryParameters2D.create(Vector2(x, start.y - 14.0), Vector2(x, start.y + 20.0), 1)
		var h := space.intersect_ray(q)
		prof.append("%.0f:%s" % [x, "—" if h.is_empty() else "%.1f" % (h["position"].y - start.y)])
		x += 4.0
	info("  dno tunelu względem wejścia (x:dy): %s" % " ".join(prof))
	await _shot("s2_4_tunnel")
	# schody w dół po skosie: od lewej krawędzi strefy w głąb
	_place_player(Vector2(2.5 * 16.0, TOP - 2.0))
	await _frames(0.4)
	d0 = zone.digs
	r = await _bore(Vector2(1, 1), "move_right", 3, 4.5 * 16.0)
	hits = zone.digs - d0
	info("schody po skosie w dół: %d ciosów, %.0f px w bok, %+.1f px w dół (%.1f px w dół na cios), ciosy bez postępu %d" %
		[hits, r.x, r.y, r.y / maxf(hits, 1), r.z])
	check("schody po skosie schodzą (≥ 6 px w dół na cios) i idą naprzód", r.y / maxf(hits, 1) >= 6.0 and r.x > 20.0)
	info("skała w strefie: %.0f%% (operacji kopania: %d)" % [zone.solid_fraction() * 100.0, zone.digs])

# ---------------------------------------------------------------- 4. nawigacja i dźwięk

func _nav_check(dig0: int) -> void:
	var open: Array = []
	for k in zone.tiles.x * zone.tiles.y:
		var c: int = zone.c0 + k % zone.tiles.x
		var r: int = zone.r0 + k / zone.tiles.x
		if zone.tile_open(c, r):
			open.append(Vector2i(c, r))
	var left: int = (level._dig_cells as Dictionary).size()
	info("po dole, schodach i tunelu: kafli wolnych w strefie %d, kafli skały w `_dig_cells` %d z %d" % [open.size(), left, dig0])
	var ok := not open.is_empty() and left == dig0 - open.size()
	for cell in open:
		ok = ok and not level._is_solid(cell.x, cell.y) and level.nav._free(cell.x, cell.y) and level.sound_grid._open(cell)
	check("wykopane kafle wolne dla nawigacji i siatki dźwięku, reszta strefy nadal bryłą", ok and level._is_solid(10, 17))

# ---------------------------------------------------------------- 5. materiały i narzędzia

## Ile ciosów w dół (bronią `w`) do wyczyszczenia wyrwy pod stopami w `x` na wierzchu strefy `z`; [ciosy, najtwardszy materiał w wyrwie].
func _hits_down(z: Node2D, x: float, w: int) -> Array:
	_place_player(Vector2(x, TOP - 2.0))
	await _frames(0.3)
	var o: Vector2 = player.global_position + Vector2(0, -9)
	var r: Rect2 = z.cut_rect(o, Vector2.DOWN)
	var tool: int = DigMats.Tool.PICK if Weapons.def(w).breaks_walls else DigMats.Tool.BLADE
	var mat: int = z._rock_in(r, DigMats.Tool.PICK)
	var hits := 0
	while hits < 8 and z._rock_in(r, tool) >= 0:
		_place_player(Vector2(x, TOP - 0.5))
		player.weapons._server_melee(o, Vector2.DOWN, w, player.player_id)
		hits += 1
		await _frames(0.05)
	return [hits, DigMats.key_of(mat) if mat >= 0 else "—"]

func _materials() -> void:
	# skała: w DigZone2 szukamy miejsca z samą skałą i miejsca z żyłą (wtrącenia z ziarna strefy)
	var rock_x := INF
	var vein_x := INF
	var rr: Rect2 = rock.rect_px()
	var x := rr.position.x + 12.0
	while x < rr.end.x - 12.0:
		var m: int = rock._rock_in(rock.cut_rect(Vector2(x, TOP - 9.0), Vector2.DOWN), DigMats.Tool.PICK)
		if m == DigMats.code("rock") and rock_x == INF:
			rock_x = x
		elif m == DigMats.code("vein") and vein_x == INF and (rock_x == INF or absf(x - rock_x) > 24.0):
			vein_x = x
		x += 4.0
	info("DigZone2: sama skała pod x %.0f, żyła pod x %.0f" % [rock_x, vein_x])
	check("strefa skały ma i skałę, i żyłę z ziarna", rock_x != INF and vein_x != INF)
	# maczeta na skale: nic, a wybór narzędzia daje kilof
	var wc: Node = player.weapons
	var melee0: int = wc.melee_id
	wc.melee_id = blade
	if rock_x != INF:
		_place_player(Vector2(rock_x, TOP - 2.0))
		await _frames(0.3)
		player.aim_dir = Vector2.DOWN
		var auto_rock: int = wc.melee_for_target()
		var d0: int = rock.digs
		wc._server_melee(player.global_position + Vector2(0, -9), Vector2.DOWN, blade, player.player_id)
		await _frames(0.05)
		check("maczeta nie bierze skały, a cios w skałę bierze kilof (%s)" % Weapons.def(auto_rock).key, rock.digs == d0 and auto_rock == Weapons.TOOL)
		var hr: Array = await _hits_down(rock, rock_x, pick)
		info("skała: %d ciosów kilofem na wyrwę (%s)" % [hr[0], hr[1]])
		check("skała: 3 ciosy kilofem na wyrwę", int(hr[0]) == 3 and String(hr[1]) == "rock")
	if vein_x != INF:
		var hv: Array = await _hits_down(rock, vein_x, pick)
		info("żyła: %d ciosów kilofem na wyrwę (%s)" % [hv[0], hv[1]])
		check("żyła: 4 ciosy kilofem na wyrwę", int(hv[0]) == 4 and String(hv[1]) == "vein")
	# ziemia: maczetą 2 ciosy, ciszej niż kilof; wybór narzędzia zostaje przy maczecie
	_place_player(Vector2(9.5 * 16.0, TOP - 2.0))
	await _frames(0.3)
	player.aim_dir = Vector2.DOWN
	var auto_dirt: int = wc.melee_for_target()
	_noise.clear()
	var hb: Array = await _hits_down(zone, 9.5 * 16.0, blade)
	var n_blade: float = float(_noise[0][0]) if not _noise.is_empty() else 0.0
	_noise.clear()
	var hp: Array = await _hits_down(zone, 8.0 * 16.0 + 2.0, pick)
	var n_pick: float = float(_noise[0][0]) if not _noise.is_empty() else 0.0
	info("ziemia: maczetą %d ciosów (hałas %.2f), kilofem %d (hałas %.2f), wybór narzędzia w ziemi: %s" % [hb[0], n_blade, hp[0], n_pick, Weapons.def(auto_dirt).key])
	check("ziemia: maczetą 2 ciosy, kilofem 1", int(hb[0]) == 2 and int(hp[0]) == 1)
	check("cios maczetą w ziemię jest o połowę cichszy od kilofa (> 0)", n_blade > 0.0 and absf(n_blade - n_pick * 0.5) < 0.05)
	check("w ziemi wybór narzędzia zostawia maczetę", auto_dirt == blade)
	wc.melee_id = melee0

# ---------------------------------------------------------------- 6. wybuch

func _blast() -> void:
	var c := Vector2(35.0 * 16.0, 13.0 * 16.0)
	_place_player(Vector2(31.5 * 16.0, TOP - 2.0))         # przy strefie skały (zrzut: wtrącenia żyły, wykopy, wyrwa po wybuchu)
	await _frames(0.4)
	var f0: float = rock.solid_fraction()
	var d0: int = rock.digs
	var z1: int = zone.digs
	Combat.explode(get_tree(), c, 48.0, 50.0, player.player_id, pick)
	await _frames(0.1)
	var f1: float = rock.solid_fraction()
	info("wybuch r 48 px w skale: skała strefy %.1f%% → %.1f%%, środek %s" % [f0 * 100.0, f1 * 100.0, "pusty" if not rock.solid_at_px(c) else "skała"])
	check("wybuch wycina koło w skale (środek pusty, skały mniej, druga strefa nietknięta)", rock.digs == d0 + 1 and not rock.solid_at_px(c) and f1 < f0 - 0.01 and zone.digs == z1)
	await _shot("d5_6_blast")

# ---------------------------------------------------------------- 7. stan: migawka i wipe

func _state(dig0: int) -> void:
	var cp_dig: int = (level._dig_cells as Dictionary).size()
	level.save_breakables_checkpoint()
	var cp: Dictionary = level.breakables_checkpoint()
	var cp1: PackedByteArray = zone.state()
	check("migawka zawiera obie ruszone strefy", (cp.get("dig", {}) as Dictionary).has("DigZone1") and (cp.get("dig", {}) as Dictionary).has("DigZone2"))
	# kopanie po migawce, potem powrót do niej (punkt kontrolny bossa)
	_place_player(Vector2(10.5 * 16.0, TOP - 2.0))
	await _frames(0.3)
	await _dig_down(30.0)
	var moved: bool = zone.state() != cp1
	level.reset_breakables(cp)
	await _frames(0.1)
	check("punkt kontrolny: strefa wraca do migawki (gęstość i kafle)", moved and zone.state() == cp1 and (level._dig_cells as Dictionary).size() == cp_dig)
	# wipe: dane mapy; gracz w wykopie wychodzi na wierzch
	var fp := Vector2(6.5 * 16.0, TOP + 40.0)
	var was_air: bool = not zone.solid_at_px(fp + Vector2(0, -10))
	_place_player(fp)
	level.reset_breakables()
	await _frames(0.3)
	var full: bool = zone.state().is_empty() and rock.state().is_empty() and is_equal_approx(zone.solid_fraction(), 1.0)
	info("wipe: skała strefy %.0f%%, kafli skały %d z %d, gracz (%.0f, %.1f)" % [zone.solid_fraction() * 100.0, (level._dig_cells as Dictionary).size(), dig0, player.global_position.x, player.global_position.y])
	check("wipe: strefy jak w danych mapy, kafle znów bryłą dla nawigacji", full and (level._dig_cells as Dictionary).size() == dig0 and not level.nav._free(6, 12))
	check("wipe: gracz z zasypanego wykopu stoi na wierzchu (nie w skale)", was_air and not zone.solid_at_px(player.global_position + Vector2(0, -10)) and player.global_position.y <= TOP + 0.5)
	# stan dla dołączającego: kompresja i powrót bez strat
	_place_player(Vector2(6.5 * 16.0, TOP - 2.0))
	await _frames(0.3)
	await _swing(Vector2.DOWN)
	var st: PackedByteArray = zone.state()
	var raw: PackedByteArray = st.decompress(zone._w * zone._h, FileAccess.COMPRESSION_ZSTD)
	info("stan strefy dla dołączającego: %d B (surowo %d B)" % [st.size(), raw.size()])
	check("stan strefy: kompresja bez strat i mały (< 1 kB po jednym ciosie)", raw == zone._d and st.size() < 1024)
	level.reset_breakables()
	await _frames(0.1)

# ---------------------------------------------------------------- 8. czasy

func _timings() -> void:
	info("ostatnia przebudowa fragmentów po ciosie (kontur + kolizja): %.3f ms" % (zone.rebuild_usec / 1000.0))
	var t0 := Time.get_ticks_usec()
	for ci in zone.chunk_count():
		zone.chunk_mesh(ci, Level3D.PX, Level3D.DEPTH_FRONT, -Level3D.DEPTH_BACK)
	var all_ms := (Time.get_ticks_usec() - t0) / 1000.0
	info("siatka 3D wszystkich %d fragmentów: %.2f ms (%.2f ms na fragment)" % [zone.chunk_count(), all_ms, all_ms / zone.chunk_count()])
	check("siatka 3D fragmentu < 4 ms", all_ms / zone.chunk_count() < 4.0)
