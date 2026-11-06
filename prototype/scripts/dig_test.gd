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
## 8. czasy przebudowy fragmentu (kontur + kolizja) i siatki 3D;
## 9. znajdźki (część 2): liczba i miejsca z ziarna (w głębi skały, odstęp), determinizm, skaner, odkopanie do połowy i błysk w latarce,
##    dźwięk ciosu w metal, przedmiot wypada i spada, wybuch odrzuca przedmiot, Nocny Dyżur, dziennik `dig_find`, wipe zakopuje;
## 10. osypywanie i wyspy (DigZone3 — żwir): dół osypuje się do stożka, masa zachowana, ziemia stoi, zasypany gracz wychodzi na wierzch
##    z ogłuszeniem, odcięty blok skały spada w całości i ląduje, stan dla dołączającego z materiałem, wipe i powrót do stanu.
## 11. pule znajdziek (część 3): cenna znajdźka czeka w łupie puli, wipe ją oddaje, udana misja zabiera ją z puli (potem drobnica),
##    odnowienie po 3 udanych misjach na innych mapach (nowe miejsca), Nocny Dyżur nie rusza puli, zapis w progress.cfg.
## Wynik: linie [DIG-TEST] (PASS / FAIL / INFO) i kod wyjścia.

const Weapons := preload("res://scripts/weapons.gd")
const Level3D := preload("res://scripts/level3d.gd")

const DigMats := preload("res://scripts/dig_materials.gd")
const Combat := preload("res://scripts/combat.gd")
const DigZone := preload("res://scripts/dig_zone.gd")
const Lights := preload("res://scripts/lights.gd")
const Throwables := preload("res://scripts/throwables.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const LOG_DIR := "user://test_dig_sessions"

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
	check("kafle stref są na starcie bryłą dla nawigacji (%d kafli: 80 + 48 + 48)" % dig0, dig0 == 176 and level._is_solid(5, 12) and level._is_solid(33, 12))
	await _surface()
	await _pit()
	await _tunnel()
	_nav_check(dig0)
	await _materials()
	await _blast()
	await _state(dig0)
	await _finds()
	await _gravel()
	await _pools()
	_timings()
	_finish()

func _on_noise(amount: float, pos: Vector2, tag: String) -> void:
	if tag == "dig":
		_noise.append([amount, pos])

## Zrzut okna do `--digshots=KATALOG` (w oknie; headless nic nie robi).
func _shot(name: String, each := Callable()) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--digshots="):
			dir = a.substr("--digshots=".length())
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(0.6, each)
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
	var raw: PackedByteArray = st.decompress(zone._w * zone._h * 2, FileAccess.COMPRESSION_ZSTD)
	info("stan strefy dla dołączającego: %d B (surowo %d B)" % [st.size(), raw.size()])
	check("stan strefy: kompresja bez strat i mały (< 1 kB po jednym ciosie)", raw == zone._d + zone._m and st.size() < 1024)
	level.reset_breakables()
	await _frames(0.1)

# ---------------------------------------------------------------- 9. znajdźki (część 2)

## Przedmioty leżące na mapie (pickup.gd, węzły „Item%d” poziomu).
func _items() -> Array:
	var out: Array = []
	for n in level.get_children():
		if String(n.name).begins_with("Item") and not n.is_queued_for_deletion():
			out.append(n)
	return out

## Miejsca i rodzaje znajdziek strefy jako tekst (determinizm).
func _find_sig(z: Node2D) -> String:
	var s := ""
	for f in z.finds:
		s += "%d,%d,%s;" % [int(f["i"]), int(f["j"]), String(f["kind"])]
	return s

func _finds() -> void:
	SessionLog.enabled = true                      # dziennik w headless: osobny katalog testu, kasowany na końcu sekcji
	SessionLog.dir = LOG_DIR
	SessionLog.mission_start({"map": level.map_id, "test": "dig"})
	var fz: Array = zone.finds
	var fr: Array = rock.finds
	var desc := ""
	for f in fz:
		desc += "%s (%.0f, %.0f)  " % [f["kind"], (f["pos"] as Vector2).x, (f["pos"] as Vector2).y]
	info("znajdźki DigZone1: %d — %s; DigZone2: %d" % [fz.size(), desc, fr.size()])
	var all_buried := (fz + fr).all(func(f: Dictionary) -> bool: return int(f["state"]) == DigZone.Find.BURIED)
	check("znajdźki z danych mapy: ziemia 80 kafli → 5, skała 48 → 3, po wipe wszystkie zakopane", fz.size() == 5 and fr.size() == 3 and all_buried)
	# rozmieszczenie: w głębi skały — nie w wierzchnim rzędzie, bez powietrza w sąsiednich kaflach, odstęp ≥ 3 kafli
	var placed := true
	for z: Node2D in [zone, rock]:
		var tl: Array[Vector2i] = []
		for f in z.finds:
			var t := Vector2i(floori(((f["pos"] as Vector2).x - 0.01) / 16.0), floori(((f["pos"] as Vector2).y - 0.01) / 16.0))
			placed = placed and t.y > z.r0 and z.solid_in_data(t.x, t.y)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var q := t + Vector2i(ox, oy)
					placed = placed and (z.solid_in_data(q.x, q.y) or (not z.rect_tiles().has_point(q) and level._is_solid(q.x, q.y)))
			for o in tl:
				placed = placed and maxi(absi(o.x - t.x), absi(o.y - t.y)) >= 3
			tl.append(t)
	check("znajdźki w głębi skały: nie w wierzchu strefy, bez powietrza obok, odstęp ≥ 3 kafli", placed)
	# determinizm: to samo ziarno → te same miejsca i rodzaje, inne ziarno → inne
	var sig0 := _find_sig(zone)
	var solid := func(c: int, r: int) -> bool: return level._is_solid(c, r)
	zone._plan_finds(solid)
	var same := _find_sig(zone) == sig0
	zone.seed_v += 1
	zone._plan_finds(solid)
	var other := _find_sig(zone) != sig0
	zone.seed_v -= 1
	zone._plan_finds(solid)
	check("znajdźki z ziarna strefy: to samo ziarno — te same miejsca, inne — inne", same and other and _find_sig(zone) == sig0)
	# skaner „Sowa”: zakopane w zasięgu, poza zasięgiem nic
	# znajdźka do prób: szyb obok niej (od strony środka strefy) nie przechodzi przez żadną inną
	var cx: float = zone.rect_px().get_center().x
	var f: Dictionary = {}
	for c: Dictionary in zone.finds:
		var cp: Vector2 = c["pos"]
		var csx: float = cp.x + (16.0 if cp.x < cx else -16.0)
		var clear := true
		for o: Dictionary in zone.finds:
			var op: Vector2 = o["pos"]
			if o != c and absf(op.x - csx) < 22.0 and op.y < cp.y + 14.0:
				clear = false
		if clear:
			f = c
			break
	check("jest znajdźka, przy której da się wykopać szyb bez ruszania innych", not f.is_empty())
	if f.is_empty():
		return
	var fp: Vector2 = f["pos"]
	var sr: float = float(Throwables.KINDS["scanner"]["range"])
	check("skaner widzi zakopaną znajdźkę w zasięgu, poza zasięgiem nie", zone.buried_finds(fp + Vector2(0, -sr + 8.0), sr).has(f)
		and not zone.buried_finds(fp + Vector2(0, -sr - 8.0), sr).has(f))
	# cios w wierzch strefy daleko od znajdziek nie dzwoni
	var space := zone.get_world_2d().direct_space_state
	var dx := 1.0 if fp.x < cx else -1.0
	var far_x: float = zone.rect_px().end.x - 12.0 if dx > 0.0 else zone.rect_px().position.x + 12.0
	var plain: Dictionary = zone.melee_dig(space, Vector2(far_x, TOP - 9.0), Vector2.DOWN, 24.0, DigMats.Tool.PICK)
	# szyb z wierzchu tuż obok znajdźki (ściana 10 px od niej): odkopana do połowy — skaner nadal ją widzi, nic nie wypada
	var items0 := _items().size()
	var sx := fp.x + dx * 16.0
	var bottom := fp.y + 6.0
	zone._send(Vector2(sx, (TOP - 4.0 + bottom) * 0.5), Vector2(6.0, (bottom - TOP + 4.0) * 0.5), 0.0, DigMats.Tool.PICK)
	await _frames(0.05)
	var face: Vector2 = zone.find_face(f)
	info("szyb obok znajdźki %s: stan %d, ściana przy (%.0f, %.0f)" % [f["kind"], int(f["state"]), face.x, face.y])
	check("szyb obok: znajdźka odkopana do połowy, skaner ją widzi, nic nie wypadło", int(f["state"]) == DigZone.Find.NEAR
		and face != Vector2.INF and zone.buried_finds(fp, 4.0).has(f) and _items().size() == items0 and zone.finds_out == 0)
	# błysk w latarce: latarka z szybu na ścianę przy znajdźce — błyska; odwrócona — nie (ta sama droga co view3d.gd `_sync_dig_glints`);
	# gracz w szybie 40 px nad ścianą (snop sięga 8 m = 128 px), bez klatki fizyki — nie zdąży spaść
	var pp0: Vector2 = player.global_position
	_place_player(Vector2(sx, face.y - 31.0))
	var fl0: bool = player.flashlight
	player.flashlight = true
	var from: Vector2 = player.global_position + Vector2(0, -9)
	player.aim_dir = (face - from).normalized()
	var lit := Lights.flashlight_on(face, get_tree(), space) == player
	player.aim_dir = -player.aim_dir
	var dark := Lights.flashlight_on(face, get_tree(), space) == null
	player.flashlight = fl0
	# zrzut w oknie: gracz na dnie szybu świeci w ścianę przy znajdźce (błysk), skaner pokazuje pozostałe zakopane
	if DisplayServer.get_name() != "headless":
		_place_player(Vector2(sx, bottom))
		player.flashlight = true
		if player._scan_view == null:
			player._scan_view = (load("res://scripts/scanner_view.gd") as GDScript).new()
			player._scan_view.player = player
			player.add_child(player._scan_view)
		player.scan_left = 4.0
		var ma0: bool = player.mouse_aim
		player.mouse_aim = false                 # kursor myszy w oknie nadpisałby kierunek snopu
		var aim := func(_t: float, _dt: float) -> void: player.aim_dir = (face - player.global_position - Vector2(0, -9)).normalized()
		await _frames(0.4, aim)
		await _shot("d5_9_glint", aim)
		player.flashlight = fl0
		player.mouse_aim = ma0
	_place_player(pp0)
	check("błysk: latarka skierowana w ścianę przy znajdźce ją oświetla, odwrócona nie", lit and dark)
	# cios z dna szybu w bok, w znajdźkę: dzwoni w metal, aż znajdźka wypada jako przedmiot (podskakuje — pozycja w poziomie)
	var origin := Vector2(sx, bottom - 9.0)
	var clinks := 0
	var swings := 0
	while swings < 6 and zone.finds_out == 0:
		var dug: Dictionary = zone.melee_dig(space, origin, Vector2(-dx, 0.0), 24.0, DigMats.Tool.PICK)
		swings += 1
		if bool(dug.get("metal", false)):
			clinks += 1
		await _frames(0.05)
	var items: Array = _items()
	var item: Node2D = items.back() if items.size() > items0 else null
	var ik := String(item.kind) if item != null else "—"
	info("cios w bok: %d ciosów, %d w metal, cios w wierzch daleko: metal %s; wypadło %s (znajdźka %s) przy (%.0f, %.0f)" % [swings, clinks,
		str(plain.get("metal", "—")), ik, f["kind"], item.global_position.x if item else 0.0, item.global_position.y if item else 0.0])
	check("cios przy zakopanej znajdźce dzwoni w metal, w wierzch daleko od znajdziek nie", clinks >= 1 and not plain.is_empty() and not bool(plain["metal"]))
	var kind_ok := ik == String(f["kind"]) or (ik == "scrap" and ["ammo", "part"].has(String(f["kind"])))
	check("odkopana znajdźka wypada jako przedmiot jej rodzaju (amunicja i część — albo złom, gdy nie ma czego)", item != null and zone.finds_out == 1
		and int(f["state"]) == DigZone.Find.OUT and kind_ok and absf(item.global_position.x - fp.x) < 8.0 and not zone.buried_finds(fp, 4.0).has(f))
	await _frames(1.0)
	if item != null and is_instance_valid(item):
		var ip: Vector2 = item.global_position
		check("przedmiot ze znajdźki spada na dno wykopu (nie w skale, nie w powietrzu)", not zone.solid_at_px(ip + Vector2(0, -2)) and zone.solid_at_px(ip + Vector2(0, 3)))
	# wybuch w skale: odkopuje znajdźkę i odrzuca przedmiot od środka
	var g: Dictionary = rock.finds[0]
	var gp: Vector2 = g["pos"]
	var bc := gp + Vector2(12.0, -6.0)
	var items1 := _items().size()
	Combat.explode(get_tree(), bc, 48.0, 50.0, player.player_id, pick)
	var items2: Array = _items()
	var bi: Node2D = items2.back() if items2.size() > items1 else null
	var push := (bi.global_position - gp).dot((gp - bc).normalized()) if bi != null else 0.0
	info("wybuch obok znajdźki %s w skale: wypadło %s, odrzut od środka %.1f px" % [g["kind"], String(bi.kind) if bi else "nic", push])
	check("wybuch odkopuje znajdźkę i odrzuca przedmiot od środka", int(g["state"]) == DigZone.Find.OUT and bi != null and push > 5.0)
	# Nocny Dyżur: tylko amunicja (albo nic); poza nim złom nigdy nie jest pusty
	var ns0: bool = NightShift.active
	NightShift.active = true
	var night: Array = [zone._resolve_find("scrap"), zone._resolve_find("battery"), zone._resolve_find("part")]
	NightShift.active = ns0
	check("Nocny Dyżur: znajdźka daje tylko amunicję albo nic", night.all(func(r: Array) -> bool: return r.is_empty() or String(r[0]) == "ammo"))
	check("znajdźki poza Nocnym Dyżurem: złom 1–3, bateria, zaopatrzenie", zone._resolve_find("scrap")[0] == "scrap" and zone._resolve_find("battery")[0] == "battery"
		and zone._resolve_find("supply")[0] == "supply" and int(zone._resolve_find("scrap")[2]) >= 1)
	# dziennik sesji
	var rows: Array = []
	if SessionLog.path != "" and FileAccess.file_exists(SessionLog.path):
		for line in FileAccess.get_file_as_string(SessionLog.path).split("\n", false):
			var v: Variant = JSON.parse_string(line)
			if v is Dictionary and (v as Dictionary).get("ev") == "mission_start":
				rows.clear()                       # w oknie dziennik jest włączony od startu — liczą się wiersze od startu tej sekcji
			elif v is Dictionary and (v as Dictionary).get("ev") == "dig_find":
				rows.append(v)
	check("dziennik: `dig_find` ze strefą, rodzajem, przedmiotem i narzędziem (%d)" % rows.size(), rows.size() == 2
		and rows.all(func(r: Dictionary) -> bool: return r.has("zone") and r.has("kind") and r.has("item") and r.has("pos"))
		and rows[0]["by"] == "pick" and rows[1]["by"] == "blast")
	SessionLog.reset_for_test()
	SessionLog.enabled = false
	var d := DirAccess.open(LOG_DIR)
	if d != null:
		for fn in d.get_files():
			d.remove(fn)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_DIR))
	# wipe: znajdźki znów zakopane, licznik od zera; przedmioty sprząta poziom
	level.reset_breakables()
	level.clear_pickups()
	await _frames(0.1)
	check("wipe: znajdźki znów zakopane w tych samych miejscach, licznik od zera", _find_sig(zone) == sig0 and zone.finds_out == 0
		and (zone.finds + rock.finds).all(func(q: Dictionary) -> bool: return int(q["state"]) == DigZone.Find.BURIED))

# ---------------------------------------------------------------- 10. osypywanie żwiru i spadające wyspy

## Narożników skały strefy (bez pierścienia) — masa materiału.
func _solid_count(z: Node2D) -> int:
	var n := 0
	for k in (z._d as PackedByteArray).size():
		if z._fixed[k] == 0 and z._d[k] >= DigZone.ISO:
			n += 1
	return n

## Czy luźny materiał strefy leży stabilnie: żaden narożnik nie ma wolnego miejsca pod sobą ani skosu do zsunięcia.
func _stable(z: Node2D) -> bool:
	var w: int = z._w
	for k in (z._d as PackedByteArray).size():
		if z._fixed[k] == 1 or z._d[k] < DigZone.ISO or not DigMats.loose(z._m[k]):
			continue
		if z._free(k + w) or (z._free(k - 1) and z._free(k + w - 1)) or (z._free(k + 1) and z._free(k + w + 1)):
			return false
	return true

## Pierwszy y skały pod `x` od wierzchu strefy w dół (px świata), INF — nic.
func _surface_y(z: Node2D, x: float) -> float:
	var y: float = z.rect_px().position.y - 4.0
	while y < z.rect_px().end.y:
		if z.solid_at_px(Vector2(x, y)):
			return y
		y += 1.0
	return INF

## Czeka, aż strefa się uspokoi (najdłużej `secs`); zwraca czas w s.
func _settle_wait(z: Node2D, secs: float, each := Callable()) -> float:
	var t := 0.0
	while t < secs and not z.is_settled():
		await _frames(0.05, each)
		t += 0.05
	return t

func _gravel() -> void:
	var gz: Node2D = level.get_node_or_null("DigZone3")
	check("mapa t_dig ma strefę żwiru (DigZone3, %s)" % (gz.mat_key if gz else "—"), gz != null and gz.mat_key == "gravel")
	if gz == null:
		return
	# 1. dół w żwirze osypuje się do kąta usypiska; masa zachowana; skała i ziemia się nie osypują
	var cx := 688.0
	var n0 := _solid_count(gz)
	gz._send(Vector2(cx, TOP + 16.0), Vector2(10.0, 16.0), 0.0, DigMats.Tool.PICK)
	var n1 := _solid_count(gz)
	var depth0 := _surface_y(gz, cx)
	var s0: int = gz.sim_steps
	var secs: float = await _settle_wait(gz, 4.0)
	var n2 := _solid_count(gz)
	var depth1 := _surface_y(gz, cx)
	info("dół 20 × 32 px w żwirze: zabrano %d narożników, osypało się w %.2f s (%d kroków, ostatni %.2f ms); dno pod środkiem y %.0f → %.0f, obok (±20 px) %.0f / %.0f" % [
		n0 - n1, secs, gz.sim_steps - s0, gz.sim_usec / 1000.0, depth0, depth1, _surface_y(gz, cx - 20.0), _surface_y(gz, cx + 20.0)])
	check("dół w żwirze osypuje się i staje (w < 3 s), stok stabilny", gz.is_settled() and secs < 3.0 and _stable(gz))
	check("osypywanie nie gubi ani nie dodaje materiału (%d → %d narożników)" % [n1, n2], n2 == n1 and n1 < n0)
	check("dno dołu podsypane, brzegi obniżone (stożek zamiast pionowych ścian)", depth1 < depth0 - 3.0 and _surface_y(gz, cx - 20.0) > TOP + 1.0 and _surface_y(gz, cx + 20.0) > TOP + 1.0)
	_place_player(Vector2(cx + 40.0, TOP - 2.0))               # kamera przy usypisku
	await _shot("d5_10_gravel")
	level.reset_breakables()
	await _frames(0.1)
	var pz: int = zone.sim_steps
	_place_player(Vector2(6.5 * 16.0, TOP - 2.0))
	await _frames(0.3)
	await _swing(Vector2.DOWN)
	await _frames(0.5)
	check("ziemia się nie osypuje (krok symulacji bez ruchu)", zone.sim_steps == pz and zone.is_settled())
	level.reset_breakables()
	await _frames(0.1)
	# 2. gracz w wąskim dole w żwirze: osypisko sypie się pod stopy i podnosi go na wierzch usypiska (bez ogłuszenia — nie został zasypany)
	gz._send(Vector2(cx, TOP + 22.0), Vector2(8.0, 22.0), 0.0, DigMats.Tool.PICK)
	_place_player(Vector2(cx, TOP + 44.0))
	player.stun_t = 0.0
	var max_stun := [0.0]
	var buried := [false]
	await _settle_wait(gz, 4.0, func(_t: float, _dt: float) -> void:
		max_stun[0] = maxf(max_stun[0], float(player.stun_t))
		buried[0] = buried[0] or gz.solid_at_px(player.global_position + Vector2(0, -10)))
	await _frames(0.3)
	var pp: Vector2 = player.global_position
	info("gracz w dole 16 × 44 px: po osypaniu stopy y %.1f (dno %.0f), ogłuszenie do %.2f s, głowa w skale w trakcie: %s" % [pp.y, TOP + 44.0, max_stun[0], buried[0]])
	check("osypisko podnosi gracza z dna dołu na wierzch usypiska (nie w skale, żywy, bez ogłuszenia)", pp.y < TOP + 36.0 and not gz.solid_at_px(pp + Vector2(0, -10))
		and not gz.solid_at_px(pp + Vector2(0, -2)) and max_stun[0] == 0.0 and not player.dead)
	# gracz zasypany głęboko (np. przez spadającą wyspę): wychodzi na wierzch strefy z krótkim ogłuszeniem
	_place_player(Vector2(730.0, TOP + 30.0))
	player.stun_t = 0.0
	gz._unstick_players(DigZone.CRUSH_STUN)
	var bp: Vector2 = player.global_position
	check("zasypany 30 px w żwirze wychodzi na wierzch (y %.1f) z ogłuszeniem %.2f s" % [bp.y, float(player.stun_t)], bp.y <= TOP + 0.5
		and is_equal_approx(float(player.stun_t), DigZone.CRUSH_STUN) and not gz.solid_at_px(bp + Vector2(0, -10)))
	player.stun_t = 0.0
	_place_player(Vector2(20.0 * 16.0, TOP - 2.0))
	level.reset_breakables()
	await _frames(0.1)
	# 3. wyspa w skale: blok odcięty z czterech stron spada w całości i staje na dnie szczeliny
	var r0: int = rock.islands_fallen
	var rn0 := _solid_count(rock)
	var cuts := [[Vector2(544.0, 196.0), Vector2(14.0, 4.0)], [Vector2(544.0, 228.0), Vector2(14.0, 6.0)], [Vector2(532.0, 212.0), Vector2(4.0, 18.0)],
		[Vector2(556.0, 212.0), Vector2(4.0, 18.0)]]
	var top_solid := false
	for c in cuts.size():
		if c == 3:
			await _frames(0.3)
			top_solid = rock.solid_at_px(Vector2(544.0, 203.0)) and rock.islands_fallen == r0 and rock.is_settled()
			_noise.clear()
		rock._send(cuts[c][0], cuts[c][1], 0.0, DigMats.Tool.BLAST)
	var rn1 := _solid_count(rock)
	await _settle_wait(rock, 3.0)
	var loud := _noise.filter(func(e: Array) -> bool: return float(e[0]) > 0.3)           # mnożnik trudności zmienia głośność (EASY w oknie)
	info("wyspa w skale: przed ostatnim cięciem stoi (%s), spadło wysp %d, wierzch bloku y 203 %s, dno szczeliny y 231 %s, hałas upadku %s" % [
		top_solid, rock.islands_fallen - r0, "skała" if rock.solid_at_px(Vector2(544.0, 203.0)) else "pusto",
		"skała" if rock.solid_at_px(Vector2(544.0, 231.0)) else "pusto", str(loud.map(func(e: Array) -> String: return "%.1f" % e[0]))])
	check("blok połączony z resztą stoi; odcięty z czterech stron spada w całości", top_solid and rock.islands_fallen == r0 + 1 and rock.is_settled())
	check("wyspa ląduje na dnie szczeliny (wierzch bloku zszedł, dno zajęte), masa zachowana, upadek słychać",
		not rock.solid_at_px(Vector2(544.0, 203.0)) and rock.solid_at_px(Vector2(544.0, 231.0)) and _solid_count(rock) == rn1 and rn1 < rn0 and not loud.is_empty())
	# 4. stan dla dołączającego niesie materiał (wyspa przesunęła żyłę i skałę); migawka wraca do tego samego
	var st: PackedByteArray = rock.state()
	var raw: PackedByteArray = st.decompress(rock._w * rock._h * 2, FileAccess.COMPRESSION_ZSTD)
	var dm: PackedByteArray = rock._d + rock._m
	check("stan strefy: gęstość i materiał, bez strat (%d B)" % st.size(), raw == dm and raw.size() == rock._w * rock._h * 2)
	level.reset_breakables()
	await _frames(0.1)
	var wiped: bool = rock.state().is_empty() and rock.is_settled()
	rock.reset_to(st)
	await _frames(0.1)
	check("wipe czyści strefę, powrót do stanu przywraca gęstość i materiał", wiped and rock._d + rock._m == dm and rock.is_settled())
	level.reset_breakables()
	await _frames(0.1)

# ---------------------------------------------------------------- 11. pule znajdziek (część 3)

## Miejsca znajdziek strefy (bez rodzajów) — czy odnowienie puli przestawiło znajdźki.
func _pos_sig(z: Node2D) -> String:
	var s := ""
	for f in z.finds:
		s += "%d,%d;" % [int(f["i"]), int(f["j"])]
	return s

## Nowe przedmioty na ziemi od `before` (lista z _items()).
func _new_items(before: Array) -> Array:
	return _items().filter(func(n: Node) -> bool: return not before.has(n))

func _pools() -> void:
	var key: String = zone.pool_key
	Scrap.dig_pools.clear()
	Scrap.dig_since.clear()
	Scrap.dig_loot.clear()
	Scrap._push()
	level.reset_breakables()
	await _frames(0.1)
	var plain := true
	for f in zone.finds:
		plain = plain and String(f["kind"]) == String(f["kind0"])
	check("strefa zna klucz puli (%s); pula pusta — odnowienie 0, rodzaje z ziarna" % key, key == "t_dig/DigZone1" and zone.find_round == 0 and plain)
	var k := -1
	for i in zone.finds.size():
		if String(zone.finds[i]["kind0"]) != "ammo":
			k = i
			break
	check("strefa ma cenną znajdźkę do prób (indeks %d)" % k, k >= 0)
	if k < 0:
		return
	var f: Dictionary = zone.finds[k]
	var fp: Vector2 = f["pos"]
	# 1. wykopana cenna znajdźka czeka w łupie puli (jak znaleziona część); wipe ją oddaje
	zone._send(fp, Vector2(8.0, 8.0), 0.0, DigMats.Tool.PICK)
	await _frames(0.05)
	var pend := (Scrap.dig_loot.get(key, []) as Array).has(k) and int(f["state"]) == DigZone.Find.OUT
	Scrap.reset_loot()
	level.reset_breakables()
	await _frames(0.1)
	f = zone.finds[k]
	check("cenna znajdźka (%s) po wykopaniu czeka w łupie puli; wipe oddaje ją do puli — znów zakopana i cenna" % f["kind0"],
		pend and Scrap.dig_loot.is_empty() and int(f["state"]) == DigZone.Find.BURIED and String(f["kind"]) == String(f["kind0"]))
	# 2. udana misja: do puli na stałe; w następnej próbie to miejsce daje drobnicę i nic nie zabiera z puli
	zone._send(fp, Vector2(8.0, 8.0), 0.0, DigMats.Tool.PICK)
	await _frames(0.05)
	Scrap.bank_loot(0)
	await _frames(0.05)
	f = zone.finds[k]
	check("po udanej misji znajdźka trafia do puli (wykopane %s), miejsce daje drobnicę" % str(Scrap.dig_taken(key)),
		Scrap.dig_taken(key) == [k] and String(f["kind"]) == "small" and Scrap.dig_loot.is_empty() and int(Scrap.dig_since.get("t_dig", -1)) == 0)
	level.reset_breakables()
	await _frames(0.1)
	var before := _items()
	zone._send(fp, Vector2(8.0, 8.0), 0.0, DigMats.Tool.PICK)
	await _frames(0.1)
	var got := _new_items(before)
	var it: Node = got[0] if got.size() == 1 else null
	var small_ok: bool = it != null and ((String(it.kind) == "scrap" and int(it.rounds) == 1) or (String(it.kind) == "ammo" and int(it.rounds) >= 1))
	info("drobnica z wykopanego miejsca: %s" % ("%s × %d" % [it.kind, it.rounds] if it != null else "%d przedmiotów" % got.size()))
	check("następna misja: z wykopanego miejsca wypada drobnica (amunicja albo 1 złom), pula bez zmian", small_ok and Scrap.dig_loot.is_empty()
		and Scrap.dig_taken(key) == [k])
	# 3. odnowienie: 3 udane misje na innych mapach (ta sama mapa się nie liczy) → nowe ziarno, nowe miejsca, nic nie wykopane
	level.reset_breakables()
	await _frames(0.1)
	var pos0 := _pos_sig(zone)
	Scrap.dig_commit("t_dig")
	var same_map := int(Scrap.dig_since.get("t_dig", -1))
	Scrap.dig_commit("z1_m1")
	Scrap.dig_commit("z1_m2")
	var r_before := Scrap.dig_round(key)
	var renewed: Array = Scrap.dig_commit("z1_m3")
	Scrap._push()
	await _frames(0.05)
	var fresh := true
	for g in zone.finds:
		fresh = fresh and String(g["kind"]) == String(g["kind0"]) and int(g["state"]) == DigZone.Find.BURIED
	info("odnowienie: licznik po misji na tej samej mapie %d, przed trzecią odnowienie %d, odnowione %s, znajdziek %d" % [same_map, r_before, str(renewed), zone.finds.size()])
	check("pula odnawia się po 3 udanych misjach na innych mapach: nowe ziarno i miejsca, nic nie wykopane, wszystko zakopane",
		same_map == 0 and r_before == 0 and renewed == ["t_dig"] and zone.find_round == 1 and Scrap.dig_taken(key).is_empty()
		and _pos_sig(zone) != pos0 and fresh and not zone.finds.is_empty() and not Scrap.dig_since.has("t_dig"))
	# 4. Nocny Dyżur: kopanie nie rusza puli
	var ns0: bool = NightShift.active
	NightShift.active = true
	var nf: Dictionary = {}
	for g in zone.finds:
		if String(g["kind0"]) != "ammo":
			nf = g
			break
	if not nf.is_empty():
		zone._send(nf["pos"], Vector2(8.0, 8.0), 0.0, DigMats.Tool.PICK)
		await _frames(0.05)
	NightShift.active = ns0
	check("Nocny Dyżur: wykopana znajdźka nie trafia do łupu puli", not nf.is_empty() and int(nf["state"]) == DigZone.Find.OUT and Scrap.dig_loot.is_empty())
	level.reset_breakables()
	await _frames(0.1)
	# 5. zapis: pule i licznik w progress.cfg u hosta wracają przy wczytaniu (z nimi miejsca i drobnica)
	Scrap.dig_pools[key] = {"round": 2, "taken": [0, 1]}
	Scrap.dig_since["t_dig"] = 1
	var saved: Dictionary = Scrap.dig_pools.duplicate(true)
	var path := "user://dig_pool_test.cfg"
	var persist0: bool = Scrap.persist
	Scrap.persist = true
	Scrap.save_progress(path)
	Scrap.dig_pools.clear()
	Scrap.dig_since.clear()
	Scrap.load_progress(path)
	Scrap.persist = persist0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await _frames(0.05)
	var kinds_ok := true
	for i in zone.finds.size():
		var want := "small" if (i == 0 or i == 1) and String(zone.finds[i]["kind0"]) != "ammo" else String(zone.finds[i]["kind0"])
		kinds_ok = kinds_ok and String(zone.finds[i]["kind"]) == want
	check("pule i licznik odnowienia zapisują się w progress.cfg i wracają (odnowienie 2, wykopane 0 i 1 — drobnica)", Scrap.dig_pools == saved
		and int(Scrap.dig_since.get("t_dig", -1)) == 1 and zone.find_round == 2 and kinds_ok)
	Scrap.dig_pools.clear()
	Scrap.dig_since.clear()
	Scrap.dig_loot.clear()
	Scrap._push()
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
