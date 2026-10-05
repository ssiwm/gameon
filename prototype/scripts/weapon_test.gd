extends Node
## Testy headless systemu broni (--weapontest, --weaptestnet + --weaptestclient).
##
##   godot --headless --path . -- --host --weapontest --autoquit=120
##   godot --headless --path . -- --host --weaptestnet --autoquit=60 &   # host
##   godot --headless --path . -- --join=127.0.0.1 --weaptestclient --autoquit=40
##
## Test jednostkowy bierze prawdziwego gracza i prawdziwe pociski w prawdziwym poziomie,
## ale wrogów zastępuje nieruchomymi manekinami (nic nie ucieka ani nie gryzie), a świat
## reszty gry (Stalker, boss, gniazda) wyłącza. Wynik: linie [WTEST] PASS/FAIL i kod wyjścia
## (0 = wszystko OK, 1 = były błędy) — nadaje się do CI.

const Weapons := preload("res://scripts/weapons.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Combat := preload("res://scripts/combat.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Controller := preload("res://scripts/weapon_controller.gd")

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var wc: Node
var failed := 0
var total := 0
var _dummy_serial := 0

# ---------------------------------------------------------------- narzędzia

func check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if not ok:
		failed += 1
	print("[WTEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  — " + detail) if detail != "" else ""])

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _setup(m: Node2D) -> void:
	main = m
	level = m.level
	for c in m._players.get_children():
		if not c.is_bot and c.is_multiplayer_authority():
			player = c
	# bot i reszta świata poza testem
	for c in m._players.get_children():
		if c.is_bot:
			c.queue_free()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.set("collision_layer", 0)
		e.visible = false
	await frames(3)
	wc = player.weapons
	player.global_position = level.spawn_for(1)
	player.velocity = Vector2.ZERO
	player.aim_dir = Vector2.RIGHT
	NoiseMgr.calm()
	await frames(5)

## Nieruchomy manekin: prawdziwy wróg bez własnej fizyki i AI, ogromny HP (pomiar obrażeń).
func dummy(x_off: float, hp := 100000.0, kind := "trzosek", y_off := 0.0) -> Node:
	_dummy_serial += 1
	var n := "TDummy%d" % _dummy_serial
	level._add_enemy(n, kind, player.global_position + Vector2(x_off, y_off))
	var e: Node = level.get_node(n)
	await frames(2)
	e.set_physics_process(false)
	e.hp = hp
	e._max_hp = maxf(hp, 1.0)
	e.velocity = Vector2.ZERO
	return e

func dealt(e: Node) -> float:
	return e._max_hp - e.hp

func free_dummies() -> void:
	for e in level.get_children():
		if e.name.begins_with("TDummy"):
			e.queue_free()
	for p in get_tree().get_nodes_in_group("pickups"):
		if not p.name.begins_with("Map"):
			p.queue_free()
	for b in get_tree().current_scene.get_children():
		if b is Projectile:
			b.queue_free()

## Przygotowuje zestaw: broń w slocie 0, pełny magazynek, zimne lufy, gotowość.
func equip(w: int, full_reserve := true) -> WeaponDef:
	var d := Weapons.def(w)
	if d.slot == Weapons.Slot.MELEE:
		wc.melee_id = w
		return d
	wc.loadout[0] = w
	wc.slot = 0
	wc.mags[w] = d.mag
	wc._heat.clear()
	wc.bloom = 0.0
	wc.cd = 0.0
	wc.state = Controller.State.READY
	wc.firing = false
	wc.charge = 0.0
	if full_reserve:
		Arsenal.reserve_changed.emit()
		Arsenal.reserve[w] = d.reserve_max if not d.infinite else 0
	player.aim_dir = Vector2.RIGHT
	return d

func shoot(w: int, shots: int, gap := 0.15) -> void:
	var d := equip(w)
	for i in shots:
		wc.cd = 0.0
		wc._fire_shot(d)
		await wait(gap)

# ---------------------------------------------------------------- scenariusze

func run_unit(m: Node2D) -> void:
	await wait(1.5)
	await _setup(m)
	_t_data()
	await _t_bullets()
	await _t_falloff_crit()
	await _t_sweep()
	await _t_pierce_beam_rail()
	await _t_flame()
	await _t_launcher()
	await _t_homing()
	await _t_bolt()
	await _t_melee()
	await _t_ammo_reload()
	await _t_heat_noise()
	await _t_pickups()
	await _t_bot()
	print("[WTEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _t_data() -> void:
	var errs := Weapons.validate()
	check("tabele broni spójne (validate)", errs.is_empty(), "; ".join(errs))
	print("[WTEST] %-9s %5s %6s %5s %7s %9s %9s %8s" % ["broń", "rpm", "dps", "mag", "reload", "szum/s@12s", "TTK trz.", "TTK wołek"])
	for d in Weapons.defs():
		var sim := Weapons.simulate_heat(d.id, 12.0)
		var dps: float = d.dps() if d.kind != WeaponDef.Kind.LAUNCHER else maxf(d.damage, d.blast_damage) / d.cooldown
		if d.kind == WeaponDef.Kind.RAIL:
			dps = d.damage / (d.cooldown + d.charge_time)
		var noise_s: float = float(sim["noise_per_s"]) if not d.is_continuous() and d.kind != WeaponDef.Kind.RAIL else d.noise(0.0) / d.cooldown
		if d.kind == WeaponDef.Kind.RAIL:
			noise_s = d.noise(0.0) / (d.cooldown + d.charge_time)
		print("[WTEST] %-9s %5.0f %6.1f %5d %6.2fs %9.1f %8.2fs %8.2fs" % [
			d.name, d.rpm(), dps, d.mag, d.full_reload_time(), noise_s, 30.0 / maxf(dps, 0.1), 140.0 / maxf(dps, 0.1)])
	# model rozgrzania: każda broń z rozstrzałem hałasu ma go osiągnąć w serii (regresja błędu z 1.5.x)
	for id in [Weapons.M83, Weapons.SPREAD12, Weapons.P64, Weapons.SRUT8, Weapons.SOKOL6]:
		var sim := Weapons.simulate_heat(id, 12.0)
		check("rozgrzanie lufy: %s osiąga n_max" % Weapons.def(id).name, float(sim["peak_heat"]) >= 0.99, "peak %.2f" % float(sim["peak_heat"]))

func _t_bullets() -> void:
	var e := await dummy(100.0)
	await shoot(Weapons.M83, 10)
	await wait(0.5)
	var got := dealt(e)
	check("M-83: 10 strzałów z 100 px zadaje ≥ 80% obrażeń", got >= 0.8 * 80.0 and got <= 80.0 + 0.1, "%.1f / 80" % got)
	check("M-83: magazynek spadł o 10", wc.mag_of(Weapons.M83) == 20, str(wc.mag_of(Weapons.M83)))
	check("trafienie budzi manekina (hałas po strzale)", NoiseMgr.level > 0.0, "uwaga %.1f" % NoiseMgr.level)
	free_dummies()
	await frames(2)
	var s := await dummy(30.0)
	await shoot(Weapons.SPREAD12, 4, 0.5)
	await wait(0.4)
	var sg := dealt(s)
	check("SPREAD-12: 4 strzały z 30 px ≈ 5×7×4", sg >= 0.7 * 140.0 and sg <= 140.1, "%.1f / 140" % sg)
	free_dummies()
	await frames(2)

func _t_falloff_crit() -> void:
	var near := await dummy(30.0)
	await shoot(Weapons.SPREAD12, 3, 0.5)
	await wait(0.4)
	var d_near := dealt(near)
	free_dummies()
	await frames(2)
	var far := await dummy(110.0)
	await shoot(Weapons.SPREAD12, 3, 0.5)
	await wait(0.6)
	var d_far := dealt(far)
	check("spadek obrażeń śrutu z dystansem (blisko ≥ 1,8× daleko)", d_near >= 1.8 * maxf(d_far, 0.01) or d_far == 0.0, "blisko %.1f, daleko %.1f" % [d_near, d_far])
	free_dummies()
	await frames(2)
	# krytyk: trafienie w górną część sylwetki
	var e := await dummy(60.0, 100000.0, "wolek")
	var info := Combat.make_info(Weapons.P64, 10.0, Vector2(e.global_position.x - 4.0, e.head_y() - 1.0), Vector2.RIGHT, 1, "bullet")
	var res := Combat.apply(e, info)
	check("trafienie w głowę Wołka: krytyk ×2 (P-64)", bool(res["crit"]) and absf(dealt(e) - 20.0) < 0.01, "dealt %.1f" % dealt(e))
	var info2 := Combat.make_info(Weapons.P64, 10.0, Vector2(e.global_position.x - 4.0, e.global_position.y - 4.0), Vector2.RIGHT, 1, "bullet")
	var before := dealt(e)
	Combat.apply(e, info2)
	check("trafienie w tułów: bez krytyka", absf(dealt(e) - before - 10.0) < 0.01)
	free_dummies()
	await frames(2)
	# strzał z wysokości barku w niskiego Trzoska nie jest „headshotem”
	var t := await dummy(60.0)
	await shoot(Weapons.P64, 3, 0.3)
	await wait(0.4)
	check("Trzosek nie ma słabego punktu (3× P-64 = 33, nie 66)", absf(dealt(t) - 33.0) < 0.5, "%.1f" % dealt(t))
	free_dummies()
	await frames(2)

## Szybki pocisk nie może przeskoczyć wąskiego wroga (przeciąganie promienia, nie przesuwany obszar).
func _t_sweep() -> void:
	var e := await dummy(200.0)
	var d := Weapons.def(Weapons.CIEGNO6)
	var old_speed: float = d.speed
	var old_range: float = d.range_px
	d.speed = 9000.0                      # ~150 px/klatkę, wróg ma 10 px szerokości
	d.range_px = 400.0
	var p := Projectile.new()
	p.launch(Weapons.CIEGNO6, player.global_position + Vector2(10, -4), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(p)
	await wait(0.4)
	d.speed = old_speed
	d.range_px = old_range
	check("pocisk 9000 px/s nie tuneluje przez wroga 10 px", dealt(e) > 0.0, "obrażenia %.1f" % dealt(e))
	free_dummies()
	await frames(2)

func _t_pierce_beam_rail() -> void:
	var targets: Array = []
	for i in 4:
		targets.append(await dummy(40.0 + 40.0 * i, 100000.0, "trzosek", 0.0))
	var d := equip(Weapons.LR7)
	var mag0: int = wc.mag_of(d.id)
	wc.sim_fire = true
	await wait(0.55)
	wc.sim_fire = false
	await wait(0.15)
	var hit_count := 0
	for t in targets:
		if dealt(t) > 0.0:
			hit_count += 1
	check("LR-7: promień przebija 3 cele (pierce 2), czwarty nietknięty", hit_count == 3 and dealt(targets[3]) == 0.0, "trafionych %d" % hit_count)
	check("LR-7: bateria spada o tyknięcia", wc.mag_of(d.id) < mag0 and mag0 - wc.mag_of(d.id) <= 8, "zużyto %d" % (mag0 - wc.mag_of(d.id)))
	check("LR-7: ciągły ogień cichy (szum/tyk ≤ 0,2)", d.noise(0.0) <= 0.2)
	for t in targets:
		t.hp = t._max_hp
	# szyna: ładowanie 1,2 s, puszczenie = strzał, przebija wszystkich
	var r := equip(Weapons.WIDMO1)
	wc.sim_fire = true
	await wait(0.5)
	check("WIDMO-1: w trakcie ładowania stan CHARGE", wc.state == Controller.State.CHARGE, "stan %d ładunek %.2f" % [wc.state, wc.charge])
	await wait(1.0)
	wc.sim_fire = false
	await wait(0.4)
	var all_hit := true
	for t in targets:
		all_hit = all_hit and absf(dealt(t) - 150.0) < 0.01
	check("WIDMO-1: naładowany strzał przebija wszystkich za 150", all_hit, "%s" % str(targets.map(func(t): return snappedf(dealt(t), 0.1))))
	check("WIDMO-1: magazynek −1", wc.mag_of(r.id) == r.mag - 1)
	check("WIDMO-1: najgłośniejsza broń (≥ 14 Uwagi)", NoiseMgr.last_noise_amount >= 14.0 or NoiseMgr.level >= 14.0, "ostatni %.1f" % NoiseMgr.last_noise_amount)
	# przedwczesne puszczenie anuluje bez kosztu
	equip(Weapons.WIDMO1)
	for t in targets:
		t.hp = t._max_hp
	wc.sim_fire = true
	await wait(0.4)
	wc.sim_fire = false
	await wait(0.2)
	check("WIDMO-1: puszczenie przed końcem ładowania anuluje (0 obrażeń, 0 kosztu)", dealt(targets[0]) == 0.0 and wc.mag_of(Weapons.WIDMO1) == r.mag)
	free_dummies()
	await frames(2)

func _t_flame() -> void:
	var near := await dummy(40.0, 100000.0, "trzosek")
	var far := await dummy(120.0, 100000.0, "trzosek")
	var d := equip(Weapons.HKM9)
	wc.sim_fire = true
	await wait(0.8)
	wc.sim_fire = false
	await wait(0.2)
	check("HKM-9: płomień rani cel w zasięgu 4 m", dealt(near) > 10.0, "%.1f" % dealt(near))
	check("HKM-9: cel poza zasięgiem nietknięty", dealt(far) == 0.0)
	check("HKM-9: podpala i płoszy Trzoska", near._burn > 0.0 and near._panic > 0.0, "burn %.1f panic %.1f" % [near._burn, near._panic])
	check("HKM-9: paliwo spada", wc.mag_of(d.id) < d.mag)
	free_dummies()
	await frames(2)

func _t_launcher() -> void:
	var a := await dummy(120.0)
	var b := await dummy(150.0)          # 30 px od celu: w promieniu 48 px
	var c := await dummy(260.0)          # poza promieniem
	NoiseMgr.calm()
	equip(Weapons.GNIEW4)
	player.aim_dir = Vector2.from_angle(deg_to_rad(-9.0))       # łuk: celuj trochę w górę (wylot jest nad głową niskiego wroga)
	wc._fire_shot(Weapons.def(Weapons.GNIEW4))
	await wait(1.4)
	check("GNIEW-4: trafienie bezpośrednie + wybuch (≥ 80)", dealt(a) >= 80.0, "%.1f" % dealt(a))
	check("GNIEW-4: wybuch rani sąsiada w promieniu 3 m", dealt(b) >= 30.0, "%.1f" % dealt(b))
	check("GNIEW-4: poza promieniem nietknięty", dealt(c) == 0.0)
	check("GNIEW-4: wybuch to hałas (≥ 15 Uwagi)", NoiseMgr.level >= 15.0, "uwaga %.1f" % NoiseMgr.level)
	free_dummies()
	await frames(2)

func _t_homing() -> void:
	# cel pod kątem ~18° nad osią strzału: kula prosta by go ominęła
	var e := await dummy(110.0, 100000.0, "trzosek", -36.0)
	e.active = true                              # rakiety szukają tylko aktywnych zagrożeń
	equip(Weapons.SOKOL6)
	player.aim_dir = Vector2.RIGHT
	for i in 3:
		wc.cd = 0.0
		wc._fire_shot(Weapons.def(Weapons.SOKOL6))
		await wait(0.3)
	await wait(0.7)
	check("SOKÓŁ-6: rakiety naprowadzają się na cel poza osią", dealt(e) >= 7.0, "%.1f" % dealt(e))
	free_dummies()
	await frames(2)

func _t_bolt() -> void:
	var e := await dummy(120.0)
	var before := get_tree().get_nodes_in_group("pickups").size()
	equip(Weapons.CIEGNO6)
	wc._fire_shot(Weapons.def(Weapons.CIEGNO6))
	await wait(0.7)
	check("CIĘGNO-6: bełt zadaje 45", absf(dealt(e) - 45.0) < 0.5, "%.1f" % dealt(e))
	check("CIĘGNO-6: bełt do odzysku (skrzynka z 1 nabojem)", get_tree().get_nodes_in_group("pickups").size() > before)
	check("CIĘGNO-6: cichy strzał (≤ 0,1)", Weapons.def(Weapons.CIEGNO6).noise(0.0) <= 0.1)
	free_dummies()
	await frames(2)

func _t_melee() -> void:
	NoiseMgr.calm()
	var e := await dummy(14.0, 30.0, "trzosek")
	e.active = false
	var lvl_before := NoiseMgr.level
	wc.melee_id = Weapons.MACZETA
	wc.state = Controller.State.READY
	wc.cd = 0.0
	wc.try_melee()
	await wait(0.6)
	check("MACZETA: cios w śpiącego zabija natychmiast", not e.alive)
	check("MACZETA: zabójstwo ciche (0 Uwagi)", NoiseMgr.level <= lvl_before + 0.01, "uwaga %.2f→%.2f" % [lvl_before, NoiseMgr.level])
	free_dummies()
	await frames(2)
	# żywy, zwrócony twarzą do gracza — zwykłe 30
	var f := await dummy(14.0, 100000.0, "trzosek")
	f.active = true
	f._facing = -1.0                       # patrzy na gracza (celujemy w prawo)
	wc.state = Controller.State.READY
	wc.try_melee()
	await wait(0.6)
	check("MACZETA: cios z przodu w czujnego zadaje 30", absf(dealt(f) - 30.0) < 0.5, "%.1f" % dealt(f))
	free_dummies()
	await frames(2)
	var g := await dummy(14.0, 100000.0, "trzosek")
	g.active = true
	g._facing = 1.0                        # plecami do gracza
	wc.state = Controller.State.READY
	wc.try_melee()
	await wait(0.6)
	check("MACZETA: cios w plecy czujnego = zabójstwo", dealt(g) >= 100000.0 - 0.5 or not g.alive)
	free_dummies()
	await frames(2)

func _t_ammo_reload() -> void:
	Arsenal.reset_mission()
	await frames(2)
	var d := equip(Weapons.M83, false)
	var reserve0 := Arsenal.get_reserve(Weapons.M83)
	for i in 30:
		wc.cd = 0.0
		wc._fire_shot(d)
	check("magazynek M-83 pusty po 30 strzałach", wc.mag_of(d.id) == 0)
	wc.cd = 0.0
	wc.sim_fire = true                     # M-83 jest automatem — „klik” to trzymany spust
	await frames(3)
	wc.sim_fire = false
	check("pusty magazynek: kliknięcie uruchamia przeładowanie", wc.state == Controller.State.RELOAD)
	await wait(d.full_reload_time() + 0.4)
	check("przeładowanie M-83: magazynek pełny, zapas −30", wc.mag_of(d.id) == 30 and Arsenal.get_reserve(d.id) == reserve0 - 30, "mag %d zapas %d→%d" % [wc.mag_of(d.id), reserve0, Arsenal.get_reserve(d.id)])
	# częściowe: bierze tylko brakujące
	for i in 5:
		wc.cd = 0.0
		wc._fire_shot(d)
	var r1 := Arsenal.get_reserve(d.id)
	wc.try_reload()
	await wait(d.reload_time + 0.4)
	check("przeładowanie częściowe zabiera tylko brakujące 5", wc.mag_of(d.id) == 30 and Arsenal.get_reserve(d.id) == r1 - 5)
	# brak zapasu
	Arsenal.reserve[d.id] = 0
	for i in 3:
		wc.cd = 0.0
		wc._fire_shot(d)
	var started: bool = wc.try_reload()
	check("brak zapasu: przeładowanie się nie zaczyna", not started and wc.state == Controller.State.READY)
	# anulowanie zmianą broni nie kosztuje naboi
	Arsenal.reserve[d.id] = 100
	wc.try_reload()
	await wait(0.4)
	wc.select_slot(2)
	await wait(0.2)
	check("zmiana broni w trakcie przeładowania anuluje je bez kosztu", Arsenal.get_reserve(d.id) == 100 and wc.mag_of(d.id) == 27, "zapas %d mag %d" % [Arsenal.get_reserve(d.id), wc.mag_of(d.id)])
	wc.select_slot(0)
	await wait(0.6)
	# strzelba: nabój po naboju, przerywane strzałem
	var s := equip(Weapons.SRUT8, false)
	wc.mags[s.id] = 2
	Arsenal.reserve[s.id] = 24
	wc.try_reload()
	await wait(s.reload_time * 3.0 + 0.3)
	check("SRUT-8: ładowanie po 1 naboju (2→5 po ~3 krokach)", wc.mag_of(s.id) >= 4 and wc.mag_of(s.id) <= 6, "mag %d" % wc.mag_of(s.id))
	var mag_before: int = wc.mag_of(s.id)
	wc.sim_press = true
	await frames(3)
	check("SRUT-8: strzał przerywa ładowanie", wc.state != Controller.State.RELOAD and wc.mag_of(s.id) <= mag_before, "stan %d mag %d→%d" % [wc.state, mag_before, wc.mag_of(s.id)])
	await wait(s.cooldown + 0.2)
	# sidearm: nieskończony zapas
	var p := equip(Weapons.P64, false)
	wc.loadout[2] = Weapons.P64
	wc.slot = 2
	wc.mags[p.id] = 0
	wc.state = Controller.State.READY
	wc.try_reload()
	await wait(p.full_reload_time() + 0.4)
	check("P-64: przeładowanie bez zapasu (∞)", wc.mag_of(p.id) == p.mag)
	wc.slot = 0

func _t_heat_noise() -> void:
	NoiseMgr.calm()
	var d := equip(Weapons.M83)
	var first := -1.0
	var heat_peak := 0.0
	wc.sim_fire = true
	var t := 0.0
	var noises: Array = []
	while t < 2.6:
		await frames(1)
		t += 1.0 / 60.0
		heat_peak = maxf(heat_peak, wc.heat_of(d.id))
		if first < 0.0 and NoiseMgr.last_noise_amount > 0.0:
			first = NoiseMgr.last_noise_amount
		noises.append(NoiseMgr.last_noise_amount)
	wc.sim_fire = false
	var last: float = noises.back()
	check("ciągły ogień M-83 rozgrzewa lufę (heat ≥ 0,85 po 2,6 s)", heat_peak >= 0.85, "heat %.2f" % heat_peak)
	check("hałas strzału rośnie z rozgrzaniem (ostatni ≥ 1,8× pierwszy)", last >= 1.8 * first, "pierwszy %.2f ostatni %.2f" % [first, last])
	await wait(2.5)
	check("lufa stygnie po przerwie", wc.heat_of(d.id) < heat_peak * 0.5, "heat %.2f" % wc.heat_of(d.id))

## Przenosi gracza na ostatnio upuszczony przedmiot danego rodzaju (drop ma losowy znos ±20 px).
func _step_on_item(kind: String, arg: int) -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.kind == kind and p.arg == arg and not p.is_queued_for_deletion():
			player.global_position = p.global_position
	await frames(2)

func _t_pickups() -> void:
	Arsenal.reset_mission()
	await frames(2)
	free_dummies()
	var d := equip(Weapons.M83, false)
	Arsenal.reserve[d.id] = 50
	level.spawn_item("ammo", d.id, player.global_position + Vector2(0, -8), 10)
	await wait(0.9)
	await _step_on_item("ammo", d.id)       # upuszczona skrzynka ma losowy znos — wejdź na nią
	await wait(0.5)
	check("skrzynka z amunicją zasila wspólny zapas (+10)", Arsenal.get_reserve(d.id) == 60, str(Arsenal.get_reserve(d.id)))
	level.spawn_item("ammo", Weapons.HKM9, player.global_position + Vector2(0, -8), 10)
	await wait(0.9)
	await _step_on_item("ammo", Weapons.HKM9)
	await wait(0.5)
	var stuck := false
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.kind == "ammo" and p.arg == Weapons.HKM9:
			stuck = true
	check("skrzynka do broni, której nikt nie nosi, zostaje na ziemi", stuck)
	free_dummies()
	# podniesienie broni (E): wymiana głównej, stara spada na ziemię
	var old: int = wc.loadout[0]
	Arsenal.reserve[Weapons.SRUT8] = 0
	level.spawn_item("weapon", Weapons.SRUT8, player.global_position + Vector2(0, -2))
	await wait(0.9)
	await _step_on_item("weapon", Weapons.SRUT8)
	await wait(0.2)
	check("broń na ziemi jest w zasięgu E", wc.nearby_weapon_item() != null)
	wc._try_pickup()
	await wait(0.6)
	check("podniesienie: SRUT-8 w slocie, stara broń porzucona", wc.loadout[0] == Weapons.SRUT8 and wc.loadout.count(old) == 0)
	var dropped := false
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.kind == "weapon" and p.arg == old:
			dropped = true
	check("porzucona broń leży na ziemi do podniesienia", dropped)
	await wait(Weapons.def(Weapons.SRUT8).draw_time + Weapons.def(Weapons.SRUT8).reload_time * 9.0 + 1.0)
	check("nowa pusta broń ładuje się sama po dobyciu", wc.mag_of(Weapons.SRUT8) > 0, "mag %d" % wc.mag_of(Weapons.SRUT8))
	var loot: int = Arsenal.get_reserve(Weapons.SRUT8) + wc.mag_of(Weapons.SRUT8)
	check("podniesienie: naboje z łupu trafiają do zapasu (zapas + magazynek = 8)", loot == Weapons.def(Weapons.SRUT8).pickup_rounds, str(loot))
	check("kit replikowany odzwierciedla zestaw", player.kit.x == Weapons.SRUT8 and player.carries(Weapons.SRUT8))

## Bot (AI towarzysz): strzela z M-83 bez zużycia amunicji i bez psucia zapasu drużyny.
func _t_bot() -> void:
	free_dummies()
	NoiseMgr.calm()
	var reserve_before := Arsenal.get_reserve(Weapons.M83)
	main._spawn_bot()
	await wait(1.2)
	var bot: Node = null
	for c in main._players.get_children():
		if c.is_bot and not c.is_queued_for_deletion():
			bot = c
	check("bot się pojawił", bot != null)
	if bot == null:
		return
	# bot przed graczem (człowiek na linii strzału blokuje bota — to osobna, celowa zasada)
	bot.global_position = player.global_position + Vector2(40, 0)
	var e := await dummy(150.0, 100000.0, "trzosek")
	e.active = true                         # aktywny wróg = zagrożenie, do którego bot strzela
	await wait(3.5)
	check("bot strzela do aktywnego wroga w zasięgu", dealt(e) > 0.0, "%.1f" % dealt(e))
	check("bot nie zjada zapasu drużyny", Arsenal.get_reserve(Weapons.M83) == reserve_before)
	check("bot strzela M-83", bot.weapon == Weapons.M83)
	bot.queue_free()
	free_dummies()

# ---------------------------------------------------------------- zrzuty ekranu (wizualna kontrola)

## Wymaga prawdziwego renderowania (np. `xvfb-run -a godot --rendering-driver opengl3 …`):
##   xvfb-run -a godot --rendering-driver opengl3 --path . -- --host --weaponshots=/ścieżka/katalog
## Zapisuje PNG-i: rozbłysk, promień, płomień, szyna, wybuch, cios, celownik z ciepłem, HUD.
func run_shots(m: Node2D, out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await wait(2.0)
	await _setup(m)
	player.global_position = level.spawn_for(1) + Vector2(60, 0)
	await wait(0.5)
	var e1 := await dummy(120.0)
	var e2 := await dummy(170.0)
	var e3 := await dummy(220.0, 100000.0, "wolek")
	await wait(0.5)
	# 1. M-83: rozbłysk + smuga
	var d := equip(Weapons.M83)
	wc.cd = 0.0
	wc._fire_shot(d)
	await _snap(out_dir, "01_m83_flash", 2)
	# 2. M-83: ciągły ogień → łuk ciepła w celowniku
	wc.sim_fire = true
	await wait(1.7)
	await _snap(out_dir, "02_m83_heat_crosshair", 0)
	wc.sim_fire = false
	await wait(0.4)
	# 3. SPREAD-12
	d = equip(Weapons.SPREAD12)
	wc._fire_shot(d)
	await _snap(out_dir, "03_spread12_flash", 2)
	await wait(0.6)
	# 4. LR-7
	d = equip(Weapons.LR7)
	wc.sim_fire = true
	await wait(0.35)
	await _snap(out_dir, "04_lr7_beam", 0)
	wc.sim_fire = false
	await wait(0.3)
	# 5. HKM-9
	d = equip(Weapons.HKM9)
	wc.sim_fire = true
	await wait(0.6)
	await _snap(out_dir, "05_hkm9_flame", 0)
	wc.sim_fire = false
	await wait(0.4)
	# 6. WIDMO-1: ładowanie, potem strzał
	d = equip(Weapons.WIDMO1)
	wc.sim_fire = true
	await wait(1.0)
	await _snap(out_dir, "06_widmo_charge", 0)
	await wait(0.5)
	wc.sim_fire = false
	await _snap(out_dir, "07_widmo_shot", 2)
	await wait(0.8)
	# 7. GNIEW-4: wybuch
	for e in [e1, e2, e3]:
		e.hp = e._max_hp
	d = equip(Weapons.GNIEW4)
	player.aim_dir = Vector2.from_angle(deg_to_rad(-9.0))
	wc._fire_shot(d)
	await wait(0.33)
	await _snap(out_dir, "08_gniew_flight", 0)
	await wait(0.2)
	await _snap(out_dir, "09_gniew_explosion", 1)
	await wait(0.8)
	# 8. cios
	player.aim_dir = Vector2.RIGHT
	wc.melee_id = Weapons.MACZETA
	wc.state = Controller.State.READY
	wc.try_melee()
	await wait(0.18)
	await _snap(out_dir, "10_melee_swing", 0)
	await wait(0.6)
	# 9. przeładowanie
	d = equip(Weapons.M83)
	wc.mags[d.id] = 3
	wc.try_reload()
	await wait(0.5)
	await _snap(out_dir, "11_reload", 0)
	await wait(2.0)
	# 10. SOKOL
	d = equip(Weapons.SOKOL6)
	e2.active = true
	wc.sim_fire = true
	await wait(0.55)
	await _snap(out_dir, "12_sokol_rockets", 0)
	wc.sim_fire = false
	print("[WTEST] zrzuty zapisane w %s" % out_dir)
	get_tree().quit(0)

func _snap(dir: String, name: String, extra_frames: int) -> void:
	for i in extra_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])

# ---------------------------------------------------------------- sieć

## Host: czeka na klienta, stawia manekina przed jego postacią i sprawdza efekty strzałów.
func run_net_host(m: Node2D) -> void:
	main = m
	level = m.level
	var waited := 0.0
	while multiplayer.get_peers().is_empty() and waited < 20.0:
		await wait(0.25)
		waited += 0.25
	check("klient dołączył", not multiplayer.get_peers().is_empty())
	if multiplayer.get_peers().is_empty():
		get_tree().quit(1)
		return
	await wait(2.0)
	var cid: int = multiplayer.get_peers()[0]
	var cp: CharacterBody2D = m._players.get_node(str(cid))
	for c in m._players.get_children():
		if c.is_bot:
			c.queue_free()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.set("collision_layer", 0)
		e.visible = false
	player = cp
	await wait(0.5)
	var e := await dummy(80.0)
	print("[WTEST] host: manekin %s przed klientem (%s)" % [e.name, str(cp.global_position.round())])
	# podglądamy serwerowy licznik przyjętych strzałów i obrażenia, dopóki klient jest połączony
	var legit_dmg := -1.0
	var accepted := 0
	var t := 0.0
	while t < 14.0 and is_instance_valid(cp):
		await wait(0.1)
		t += 0.1
		if not is_instance_valid(cp):
			break
		accepted = maxi(accepted, int(cp.weapons.srv_shots))
		if legit_dmg < 0.0 and cp.weapons.srv_shots >= 10:
			await wait(0.5)                      # niech ostatnia kula doleci
			legit_dmg = dealt(e)
			if is_instance_valid(cp):
				accepted = maxi(accepted, int(cp.weapons.srv_shots))
		if accepted >= 10 and t > 9.0:
			break
	await wait(0.8)
	check("zdalny strzelec: 10 legalnych strzałów M-83 klienta zadaje obrażenia na serwerze", legit_dmg >= 0.6 * 80.0 and legit_dmg <= 80.1, "%.1f / 80" % legit_dmg)
	check("limiter tempa: 20 sfałszowanych żądań naraz przyjęte ≤ 4× (zapas 2,5 + lag)", accepted <= 10 + 4, "przyjęto łącznie %d (10 legalnych + ≤4)" % accepted)
	check("serwer odrzucił większość ataku (≥ 14 z 20)", accepted <= 10 + 6, "przyjęto %d" % accepted)
	print("[WTEST] ==== sieć: %d/%d OK ====" % [total - failed, total])
	get_tree().quit(1 if failed > 0 else 0)

## Klient: strzela 10 razy (legalnie, z rytmem), potem próbuje „zalać” serwer żądaniami.
func run_net_client(m: Node2D) -> void:
	main = m
	var waited := 0.0
	var me: CharacterBody2D = null
	while me == null and waited < 15.0:
		await wait(0.25)
		waited += 0.25
		for c in m._players.get_children():
			if not c.is_bot and c.is_multiplayer_authority():
				me = c
	if me == null:
		get_tree().quit(1)
		return
	# manekin lokalnie na kliencie (RPC stanu wroga z serwera potrzebuje węzła o tej samej ścieżce)
	main.level._add_enemy("TDummy1", "trzosek", me.global_position + Vector2(80.0, 0.0))
	await wait(4.0)
	player = me
	wc = me.weapons
	me.aim_dir = Vector2.RIGHT
	var d := Weapons.def(Weapons.M83)
	var predicted_before := get_tree().current_scene.get_child_count()
	for i in 10:
		wc.cd = 0.0
		wc._fire_shot(d)
		await wait(0.15)
	print("[WTEST] klient: wystrzelił 10×, magazynek %d" % wc.mag_of(d.id))
	await wait(1.0)
	# atak: 20 żądań naraz z prawidłowym wylotem
	var muzzle: Vector2 = wc.muzzle_pos(Vector2.RIGHT, d)
	for i in 20:
		wc._fire_request.rpc_id(1, muzzle, Vector2.RIGHT, Weapons.M83, randi(), 0.0)
	await wait(2.0)
	print("[WTEST] klient: koniec")
	get_tree().quit(0)
