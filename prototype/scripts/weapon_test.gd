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
const Parts := preload("res://scripts/parts.gd")
const Ammo := preload("res://scripts/ammo.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Lights := preload("res://scripts/lights.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Perks := preload("res://scripts/perks.gd")
const Sprites := preload("res://scripts/sprites.gd")
const NightShiftMode := preload("res://scripts/night_shift.gd")
const SmokeCloud := preload("res://scripts/smoke_cloud.gd")
const BrickWall := preload("res://scripts/brick_wall.gd")
const FirePatch := preload("res://scripts/fire_patch.gd")
const WALL_HP_REF := 120.0
const Enemy := preload("res://scripts/enemy.gd")
const Controller := preload("res://scripts/weapon_controller.gd")
const Motion := preload("res://scripts/weapon_motion.gd")

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var wc: Node
var failed := 0
var total := 0
var _dummy_serial := 0
var _net_shop_finished := false

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
	var at: Vector2 = player.global_position + Vector2(x_off, y_off)
	level._add_enemy(n, kind, at)
	var e: Node = level.get_node(n)
	await frames(2)
	e.set_physics_process(false)
	# przez te dwie klatki żywy stwór zdążył ruszyć (krok w bok, a skaczący — odbić się od podłogi); zamrożony w powietrzu wychodził z linii
	# promienia i test przebicia LR-7 losowo liczył nie te cele. Manekin wraca dokładnie na swoje miejsce.
	e.global_position = at
	e.set("_last_x", at.x)                 # zwrot stwora liczy się z przesunięcia — sam powrót na miejsce nie może go odwrócić
	e.hp = hp
	e._max_hp = maxf(hp, 1.0)
	e.velocity = Vector2.ZERO
	return e

func dealt(e: Node) -> float:
	return e._max_hp - e.hp

func free_dummies() -> void:
	Lights.flashes.clear()
	for fp in get_tree().get_nodes_in_group("fire_patches"):
		fp.queue_free()
	for gr in get_tree().get_nodes_in_group("grenades"):
		gr.queue_free()
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
	wc.loaded.erase(w)                     # nabój zwykły w magazynku (ammo.gd)
	wc.want_ammo.erase(w)
	wc._heat.clear()
	wc.bloom = 0.0
	wc.cd = 0.0
	wc.state = Controller.State.READY
	wc.firing = false
	wc._burst_left = 0
	wc.charge = 0.0
	if full_reserve:
		Arsenal.reserve_changed.emit()
		Arsenal.set_reserve(w, Arsenal.pool_max(w) if not d.infinite else 0)
	player.aim_dir = Vector2.RIGHT
	return d

## Kod `build` broni z listą części (parts.gd) i typem naboju — dla Projectile.launch, Combat.make_info, Weapons.def_build.
func bld(w: int, ids: Array, ammo := 0) -> int:
	return Weapons.build_of(ammo, Parts.encode_ids(String(Weapons.def(w).key), ids))

## Definicja broni z listą części (bez montażu u gracza).
func pdef(w: int, ids: Array) -> WeaponDef:
	return Weapons.def_build(w, bld(w, ids))

## Montaż części w broni testowego gracza tą samą drogą co w grze: drużyna je ma (Scrap.parts), gracz wybiera (Profile.set_fit),
## a player.fits odświeża się z profilu (to też trafia do sieci).
func fit_player(w: int, ids: Array) -> void:
	var key := String(Weapons.def(w).key)
	for id in ids:
		Scrap.parts[String(id)] = true
		Profile.set_fit(key, String(Parts.get_part(String(id))["slot"]), String(id))
	player._sync_perks()
	await frames(1)

func clear_fits() -> void:
	Scrap.parts.clear()
	Profile.fits = {}
	player._sync_perks()
	await frames(1)

func shoot(w: int, shots: int, gap := 0.15) -> void:
	var d := equip(w)
	for i in shots:
		wc.cd = 0.0
		wc._fire_shot(d)
		await wait(gap)

## Dodatnie testy zakupów używają prawdziwej kryjówki i stanowisk; nie obchodzą walidatora serwera.
func _station_begin(group: String) -> Dictionary:
	var saved := {"map": level.map_id, "pos": player.global_position, "process": player.process_mode}
	if level.map_id != "z1_hub":
		main._set_map("z1_hub")
		await frames(3)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_station_move(group)
	return saved

func _station_move(group: String) -> void:
	var station := get_tree().get_first_node_in_group(group)
	assert(station != null)
	player.global_position = station.global_position + Vector2(0, -2)
	player.velocity = Vector2.ZERO

func _station_end(saved: Dictionary) -> void:
	if level.map_id != String(saved["map"]):
		main._set_map(String(saved["map"]))
		await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.set("collision_layer", 0)
		e.visible = false
	player.global_position = saved["pos"]
	player.velocity = Vector2.ZERO
	player.process_mode = int(saved["process"])
	NoiseMgr.calm()

# ---------------------------------------------------------------- scenariusze

func run_unit(m: Node2D) -> void:
	await wait(1.5)
	await _setup(m)
	_t_data()
	await _t_bullets()
	await _t_falloff_crit()
	await _t_phase1()
	await _t_upgrades()
	await _t_phase3()
	await _t_phase4()
	await _t_liquid_fire()
	await _t_throwables()
	await _t_profile()
	await _t_sweep()
	await _t_pierce_beam_rail()
	await _t_flame()
	await _t_launcher()
	await _t_blast_walls()
	await _t_beam_origin()
	_t_crosshair_spread()
	await _t_mouse_aim()
	await _t_fast_bullets()
	await _t_weapon_realism()
	await _t_weapon_realism2()
	await _t_realia_e0()
	await _t_ammo_calibers()
	await _t_ammo_40mm()
	await _t_parts()
	await _t_parts_alt()
	await _t_mass()
	await _t_research()
	await _t_handling_climb()
	await _t_hot_barrel()
	await _t_two_reloads()
	await _t_condition_jams()
	await _t_condition_4b()
	await _t_maintenance()
	await _t_mastery()
	await _t_history()
	await _t_part_finds()
	await _t_penetration()
	await _t_homing()
	await _t_bolt()
	await _t_melee()
	await _t_ammo_reload()
	await _t_heat_noise()
	await _t_pickups()
	await _t_lag()
	await _t_bot()
	print("[WTEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	Audio.quit_game(1 if failed > 0 else 0)

func _t_data() -> void:
	var errs := Weapons.validate()
	check("tabele broni spójne (validate)", errs.is_empty(), "; ".join(errs))
	var perrs := Parts.validate(Weapons.defs())
	check("katalog części spójny: %d broni, każda część ma koszt (minus), żadna nie jest zdominowana, pola istnieją" % Parts.PARTS.size(), perrs.is_empty() and Parts.PARTS.size() == Weapons.COUNT, "; ".join(perrs))
	# dawny tłumik płomienia przy PBS-1 (sprzed 1.7.454 bez masy i dobycia): większy błysk i mocniejsze kopnięcie — zdominowany
	var m83 := Weapons.def(Weapons.M83)
	var old_hider := {"mods": [["flash_size", "mul", 0.35], ["cam_kick", "mul", 1.15]]}
	var can := {"mods": [["flash_size", "mul", 0.3], ["n_max", "mul", 0.7]]}
	var slam := {"mods": [["auto", "set", 0.0], ["flash_size", "mul", 0.3]]}
	check("dominacja w gnieździe: wykryta (%s), odwrotnie nie (%s), pole bez kierunku nie dominuje (%s)" % [str(Parts.dominated_by(old_hider, can, m83)),
		str(Parts.dominated_by(can, old_hider, m83)), str(Parts.dominated_by(old_hider, slam, m83))],
		Parts.dominated_by(old_hider, can, m83) and not Parts.dominated_by(can, old_hider, m83) and not Parts.dominated_by(old_hider, slam, m83))
	var hider := Parts.get_part("m83_hider")
	var pbs := Parts.get_part("m83_pbs1")
	check("tłumik płomienia M-83: najmniejszy błysk, bez brudzenia (błysk %.2f < %.2f, zużycie ×%.1f przy PBS-1)" % [Parts._value_with(hider, "flash_size", m83) / m83.flash_size,
		Parts._value_with(pbs, "flash_size", m83) / m83.flash_size, Parts._value_with(pbs, "wear", m83) / m83.wear],
		Parts._value_with(hider, "flash_size", m83) < Parts._value_with(pbs, "flash_size", m83) and Parts._value_with(pbs, "wear", m83) > m83.wear
		and is_equal_approx(Parts._value_with(hider, "wear", m83), m83.wear))
	check("ceny części jak dawnych poziomów (M-83 60/120/220, tłumik P-83 %d, szyny SPECTER-1 %d)" % [Parts.cost("p64_supp"), Parts.cost("w1_rails")],
		Parts.cost("m83_rpk40") == 60 and Parts.cost("m83_rpkbar") == 120 and Parts.cost("m83_pbs1") == 220 and Parts.cost("p64_supp") < 220 and Parts.cost("w1_rails") > 220)
	print("[WTEST] %-9s %5s %6s %5s %7s %9s %9s %8s" % ["broń", "rpm", "dps", "mag", "reload", "szum/s@12s", "TTK trz.", "TTK wołek"])
	for d in Weapons.defs():
		var sim := Weapons.simulate_heat(d.id, 12.0)
		var dps: float = d.dps() if d.kind != WeaponDef.Kind.LAUNCHER else maxf(d.damage, d.blast_damage) / d.cooldown
		if d.kind == WeaponDef.Kind.RAIL:
			dps = d.damage / (d.cooldown + d.charge_time)
		var noise_s: float = float(sim["noise_per_s"]) if d.kind != WeaponDef.Kind.RAIL else d.noise(0.0) / d.cooldown
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
	# 22 px: cały wachlarz mieści się w sylwetce manekina (z 30 px górne śruciny losowo przechodziły nad nim i wynik 91–112 / 140
	# leżał na progu — test padał zależnie od rozrzutu)
	var s := await dummy(22.0)
	await shoot(Weapons.SPREAD12, 4, 0.5)
	await wait(0.4)
	var sg := dealt(s)
	check("SPREAD-12: 4 strzały z 22 px = 5×7×4", sg >= 0.9 * 140.0 and sg <= 140.1, "%.1f / 140" % sg)
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
	check("trafienie w głowę Wołka: krytyk ×2 (P-64), potem pancerz −3 (20 → 17)", bool(res["crit"]) and absf(dealt(e) - 17.0) < 0.01, "dealt %.1f" % dealt(e))
	var info2 := Combat.make_info(Weapons.P64, 10.0, Vector2(e.global_position.x - 4.0, e.global_position.y - 4.0), Vector2.RIGHT, 1, "bullet")
	var before := dealt(e)
	Combat.apply(e, info2)
	check("trafienie w tułów: bez krytyka (10 − pancerz 3 = 7)", absf(dealt(e) - before - 7.0) < 0.01)
	free_dummies()
	await frames(2)
	# strzał z wysokości barku w niskiego Trzoska nie jest „headshotem”
	var t := await dummy(60.0)
	await shoot(Weapons.P64, 3, 0.3)
	await wait(0.4)
	check("Trzosek nie ma słabego punktu (3× P-64 = 33, nie 66)", absf(dealt(t) - 33.0) < 0.5, "%.1f" % dealt(t))
	free_dummies()
	await frames(2)

## Zmiany z fazy 1 przeglądu broni: pancerz Wołka, strefy głowy, ćmy a wiązka, naprowadzanie FALCON-6, źródła broni, widełki hałasu.
func _t_phase1() -> void:
	var w := await dummy(60.0, 100000.0, "wolek")
	var r1 := Combat.apply(w, Combat.make_info(Weapons.M83, 8.0, w.global_position + Vector2(-4, -6), Vector2.RIGHT, 1, "bullet"))
	check("pancerz Wołka: kula 8 → 5, znacznik ARMOR (mat 1)", absf(dealt(w) - 5.0) < 0.01 and int(r1["mat"]) == 1, "dealt %.2f mat %d" % [dealt(w), int(r1["mat"])])
	var b0 := dealt(w)
	Combat.apply(w, Combat.make_info(Weapons.SRUT8, 10.0, w.global_position + Vector2(-4, -6), Vector2.RIGHT, 1, "bullet"))
	check("pancerz Wołka: śrucina PELLET-8 (10) traci 3/8 — pancerz zbija cały strzał raz, nie każdą śrucinę (FUN_PLAN.md P1.4)", absf(dealt(w) - b0 - (10.0 - 3.0 / 8.0)) < 0.01)
	var b1 := dealt(w)
	Combat.apply(w, Combat.make_info(Weapons.HKM9, 3.0, w.global_position + Vector2(-4, -6), Vector2.RIGHT, 1, "fire"))
	check("pancerz nie działa na ogień (3 → 3)", absf(dealt(w) - b1 - 3.0) < 0.01)
	var b2 := dealt(w)
	Combat.apply(w, Combat.make_info(Weapons.WIDMO1, 150.0, w.global_position + Vector2(-4, -6), Vector2.RIGHT, 1, "rail"))
	check("pancerz nie działa na szynę (150 → 150)", absf(dealt(w) - b2 - 150.0) < 0.01)
	free_dummies()
	await frames(2)
	var heads_ok := true
	for k in ["wolek", "slepiec", "podsluchacz", "mimik"]:
		var kd: Dictionary = Enemy.KINDS[k]
		var line: float = (kd["size"] as Vector2).y * (1.0 - float(kd["head"]))
		heads_ok = heads_ok and float(kd["head"]) > 0.0 and line > 9.5        # strzał z wysokości piersi (−9 px) nie jest headshotem
	check("strefy głowy: Wołek, Ślepiec, Podsłuchacz i Mimik (linia głowy wyżej niż pierś strzelca)", heads_ok)
	var ps := Weapons.def(Weapons.SRUT8)
	check("PELLET-8: 8 × 10 = 80 na strzał z bliska, ogłuszenie ≥ 0,5 s", absf(ps.damage * ps.pellets - 80.0) < 0.01 and ps.stun >= 0.5)
	check("FALCON-6: 10 obrażeń na rakietę", Weapons.def(Weapons.SOKOL6).damage >= 10.0)
	# naprowadzanie woli cele trudne do trafienia: bliższy Trzosek kontra dalszy Skoczek
	var near := await dummy(50.0, 100000.0, "trzosek")
	var far := await dummy(110.0, 100000.0, "skoczek")
	near.active = true
	far.active = true
	var rk := Projectile.new()
	rk.launch(Weapons.SOKOL6, player.global_position + Vector2(10, -6), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(rk)
	check("FALCON-6: naprowadzanie wybiera Skoczka zamiast bliższego Trzoska", rk._target == far, "cel %s" % str(rk._target))
	rk.queue_free()
	free_dummies()
	await frames(2)
	# ćma budzi się od wiązki LR-7, ale nie od zwykłego strzału
	var moth := await dummy(60.0, 100000.0, "cma")
	player.flashlight = false
	player.w_firing = true
	player.weapon = Weapons.LR7
	var lit_beam: Dictionary = moth._beh.nearest_light(300.0)
	player.weapon = Weapons.M83
	var lit_gun: Dictionary = moth._beh.nearest_light(300.0)
	player.w_firing = false
	check("ćma leci na wiązkę LR-7, a nie na strzał z M-83", not lit_beam.is_empty() and lit_gun.is_empty())
	free_dummies()
	await frames(2)
	# źródła broni: SPECTER-1 i WRATH-4 do kupienia, SPECTER-1 po pokonaniu Pijawki
	var gated_before := Scrap.is_gated(Weapons.WIDMO1) and not Scrap.is_unlocked(Weapons.WIDMO1)
	var had_trophy := Scrap.trophies.has("z1_b1")
	Scrap.trophies["z1_b1"] = true
	var gated_after := not Scrap.is_gated(Weapons.WIDMO1) and not Scrap.is_unlocked(Weapons.WIDMO1) and Scrap.price_of(Weapons.WIDMO1) > 0
	if not had_trophy:
		Scrap.trophies.erase("z1_b1")
	check("SPECTER-1: trofeum po Pijawce (przed: zablokowana; po: do kupienia za %d)" % Scrap.price_of(Weapons.WIDMO1), gated_before and gated_after)
	check("WRATH-4: do kupienia w warsztacie (%d)" % Scrap.price_of(Weapons.GNIEW4), Scrap.price_of(Weapons.GNIEW4) > 0 and not Scrap.is_gated(Weapons.GNIEW4))
	# widełki: hałas na jednostkę obrażeń broni palnych (poza wybuchowymi) ≤ 0,25 — pilnuje, żeby żadna broń nie była głośna za mało dla swojego DPS
	var worst := ""
	var worst_r := 0.0
	for d in Weapons.defs():
		if d.slot == Weapons.Slot.MELEE or d.kind == WeaponDef.Kind.LAUNCHER or d.kind == WeaponDef.Kind.RAIL:
			continue
		var sim := Weapons.simulate_heat(d.id, 12.0)
		var ns: float = float(sim["noise_per_s"])
		var ratio := ns / maxf(d.dps(), 0.1)
		if ratio > worst_r:
			worst_r = ratio
			worst = d.name
	check("hałas / DPS ≤ 0,25 dla broni palnych (najgorsza: %s %.2f)" % [worst, worst_r], worst_r <= 0.25)
	# LR-7 po osłabieniu: DPS ≤ 65, zasięg ≤ 12 m, hałas na DPS nie mniejszy niż ~0,05 (wcześniej 0,026) i rozgrzewa się w serii
	var lr := Weapons.def(Weapons.LR7)
	var lr_sim := Weapons.simulate_heat(lr.id, 12.0)
	var lr_ratio: float = float(lr_sim["noise_per_s"]) / lr.dps()
	check("LR-7: DPS %.0f (≤ 65), zasięg %.0f m (≤ 12), hałas/DPS %.3f (≥ 0,05), magazynek %d" % [lr.dps(), lr.range_px / 16.0, lr_ratio, lr.mag], lr.dps() <= 65.0 and lr.range_px <= 192.0 and lr_ratio >= 0.05 and lr.mag <= 70)
	var beam_t := await dummy(40.0, 100000.0, "trzosek", 0.0)
	var beam_far := await dummy(150.0, 100000.0, "trzosek", 0.0)
	equip(Weapons.LR7)
	wc.sim_fire = true
	await wait(0.9)
	wc.sim_fire = false
	var near_d := dealt(beam_t)
	var far_d := dealt(beam_far)
	check("LR-7: wiązka słabnie z dystansem (blisko %.0f, 150 px %.0f) i grzeje się (heat %.2f)" % [near_d, far_d, wc.heat_of(Weapons.LR7)], near_d > 0.0 and far_d > 0.0 and far_d < near_d * 0.85 and wc.heat_of(Weapons.LR7) > 0.1)
	free_dummies()
	await frames(2)

## Faza B1: profil gracza — krzywa poziomów, sloty, XP za zabójstwa / misję / podniesienie, perki, zapis.
func _t_profile() -> void:
	Profile.reset_for_test()
	check("krzywa XP: progi L1–L5 = %s" % str([Profile.xp_for_level(1), Profile.xp_for_level(2), Profile.xp_for_level(3), Profile.xp_for_level(4), Profile.xp_for_level(5)]),
		Profile.xp_for_level(1) == 0 and Profile.xp_for_level(2) == 150 and Profile.xp_for_level(3) == 400 and Profile.xp_for_level(4) == 750 and Profile.xp_for_level(5) == 1200)
	check("poziom z XP: 0→L1, 149→L1, 150→L2, 749→L3, 750→L4", Profile.level_of(0) == 1 and Profile.level_of(149) == 1 and Profile.level_of(150) == 2 and Profile.level_of(749) == 3 and Profile.level_of(750) == 4)
	var lv_seen: Array = []
	var cb_lv := func(l: int) -> void: lv_seen.append(l)
	Profile.leveled_up.connect(cb_lv)
	Profile.add_xp(140, "test")
	var slots_l1: int = Profile.slots()
	Profile.add_xp(15, "test")                                    # 155 → L2
	var slots_l2: int = Profile.slots()
	Profile.add_xp(600, "test")                                   # 755 → L4 (przeskok o dwa poziomy: sygnały L3 i L4)
	check("awans: sloty L1/L2/L4 = %d/%d/%d, sygnały poziomów %s, XP %d" % [slots_l1, slots_l2, Profile.slots(), str(lv_seen), Profile.xp], slots_l1 == 0 and slots_l2 == 1 and Profile.slots() == 2 and lv_seen == [2, 3, 4])
	Profile.leveled_up.disconnect(cb_lv)
	# perki: katalog, odblokowanie poziomem, sloty
	var perk_errs: Array = []
	var seen := {}
	for id in Perks.ORDER:
		if seen.has(id) or not Perks.PERKS.has(id) or String(Perks.PERKS[id]["desc"]) == "" or Perks.unlock_level(String(id)) < 2:
			perk_errs.append(String(id))
		seen[id] = true
	check("katalog perków: 8 unikalnych, z opisem i progiem poziomu (%d), brak błędów" % Perks.ORDER.size(), Perks.ORDER.size() == Perks.PERKS.size() and Perks.ORDER.size() == 8 and perk_errs.is_empty(), str(perk_errs))
	Profile.reset_for_test()
	Profile.add_xp(150, "test")                                   # L2: 1 slot, perki z progiem 2
	var e_ok: bool = Profile.equip(0, "smith")
	var e_slot2: bool = Profile.equip(1, "quiet_steps")           # drugi slot dopiero od L4
	var e_locked: bool = Profile.equip(0, "scout")                # perk L4 przy L2
	var held: bool = Profile.has_perk("smith")
	Profile.add_xp(600, "test")                                   # L4
	var e_dup: bool = Profile.equip(1, "smith")                   # ten sam perk w drugim slocie przenosi go
	check("zakładanie perków: L2 smith=%s, drugi slot zablokowany=%s, perk L4 zablokowany=%s; po L4 przeniesienie smith → slot 2 (%s)" % [str(e_ok), str(not e_slot2), str(not e_locked), str(Profile.equipped)],
		e_ok and not e_slot2 and not e_locked and held and e_dup and Profile.equipped[0] == "" and Profile.equipped[1] == "smith")
	# skutki perków (B3): replikowane indeksy, Kowal w cenniku, Krwiobieg, Weteran, Druga szansa, parametry pozostałych
	Profile.reset_for_test()
	Profile.add_xp(750, "test")                                   # L4: dwa sloty
	Profile.equip(0, "smith")
	Profile.equip(1, "second_chance")
	player._sync_perks()
	var rep_ok: bool = player.has_perk("smith") and player.has_perk("second_chance") and not player.has_perk("veteran") and Perks.ids_of(player.perks) == ["smith", "second_chance"]
	check("perki: gracz publikuje założone perki (indeksy %s → %s)" % [str(player.perks), str(Perks.ids_of(player.perks))], rep_ok)
	var plain: int = Parts.cost("m83_rpkbar")
	var smithed: int = Scrap.part_cost("m83_rpkbar")
	check("Kowal: lufa RPK %d → %d scrap (−20%%, zaokrąglone do 5), bez perka %d" % [plain, smithed, Scrap.part_cost("m83_rpkbar", 99)],
		smithed == Parts.cost("m83_rpkbar", 0.8) and smithed < plain and Scrap.part_cost("m83_rpkbar", 99) == plain)
	# od 1.7.455 Kowal obniża też złom za badanie i tokarkę; próbek nie
	var rc_s: Vector2i = Scrap.research_cost("lr7_lens")
	var rc_p: Vector2i = Scrap.research_cost("lr7_lens", 99)
	check("Kowal: badanie soczewki %d → %d złomu (próbki %d = %d), tokarka %d → %d" % [rc_p.y, rc_s.y, rc_p.x, rc_s.x, Scrap.machine_price("lr7_lens", 99), Scrap.machine_price("lr7_lens")],
		rc_s.y < rc_p.y and rc_s.x == rc_p.x and Scrap.machine_price("lr7_lens") < Scrap.machine_price("lr7_lens", 99))
	var bf_before: float = player._revive_time()
	player.perks = Perks.to_indexes(["blood_flow", "veteran"])
	check("Krwiobieg: podnoszenie %.1f s zamiast %.1f s" % [player._revive_time(), bf_before], is_equal_approx(player._revive_time(), 2.5 * Difficulty.m("revive")) and player._revive_time() < bf_before)
	check("Weteran: serca %d (stos %d) zamiast %d (%d)" % [player.max_hp(), player.stack_hp(), player.MAX_HP, player.STACK_HP], player.max_hp() == player.MAX_HP + 1 and player.stack_hp() == player.STACK_HP + 1)
	player.perks = Perks.to_indexes(["quiet_steps", "wide_arm"])
	check("Ciche kroki ×%.2f, Szerokie ramię ×%.1f, bez perka ×1" % [player.perk_param("quiet_steps", "run_noise_mult", 1.0), player.perk_param("wide_arm", "throw_mult", 1.0)],
		is_equal_approx(player.perk_param("quiet_steps", "run_noise_mult", 1.0), 0.5) and is_equal_approx(player.perk_param("wide_arm", "throw_mult", 1.0), 1.3) and is_equal_approx(player.perk_param("scout", "scan_stalker_range", 0.0), 0.0))
	# krok biegu wobec progu słuchu Ślepca: bez perka słyszy (krok na progu), z „Cichymi krokami” już nie — opis perka to obiecuje
	var step := NoiseMgr.N_RUN_PER_SEC * 0.5
	var keen_min := float(Enemy.KINDS["slepiec"]["min_noise"])
	check("Ciche kroki: krok %.3f poniżej progu słuchu Ślepca %.2f, zwykły krok %.3f na progu" % [step * Perks.param("quiet_steps", "run_noise_mult", 1.0), keen_min, step],
		step >= keen_min and step * Perks.param("quiet_steps", "run_noise_mult", 1.0) < keen_min)
	player.perks = Perks.to_indexes(["cold_blood", "scout"])
	check("Zimna krew: limit krzyku %.0f, Zwiadowca: Stalker na skanerze do %.0f px" % [player.perk_param("cold_blood", "scream_cap", 99.0), player.perk_param("scout", "scan_stalker_range", 0.0)],
		is_equal_approx(player.perk_param("cold_blood", "scream_cap", 99.0), 10.0) and is_equal_approx(player.perk_param("scout", "scan_stalker_range", 0.0), 160.0))
	player.perks = Perks.to_indexes(["second_chance", ""])
	player._second_used = false
	player._go_down()
	player._down_physics(3.0)
	var still_down: bool = player.dead
	player._down_physics(6.0)                                     # łącznie 9 s > 8 s
	var up_hp: int = player.hp
	var got_up: bool = not player.dead
	player._go_down()
	player._down_physics(9.0)
	var second_time_down: bool = player.dead                      # tylko raz na misję
	player.dead = false
	player.hp = player.MAX_HP
	player.bleed_left = 0.0
	player._second_used = false
	player.perks = Vector2i(-1, -1)
	Profile.reset_for_test()
	check("Druga szansa: po 3 s leży (%s), po 9 s wstaje na %d sercu (%s), drugi raz w misji już nie (%s)" % [str(still_down), up_hp, str(got_up), str(second_time_down)], still_down and got_up and up_hp == 1 and second_time_down)
	# wygląd gracza (Look): kody, nazwy arkuszy, odblokowania poziomem, zapis w profilu
	var Look := preload("res://scripts/look.gd")
	Profile.reset_for_test()
	var look_codes_ok := true
	for g in Look.GENDERS.size():
		for o in Look.OUTFITS.size():
			var c: int = Look.code(g, o)
			look_codes_ok = look_codes_ok and Look.is_valid(c) and Look.gender_of(c) == g and Look.outfit_of(c) == o and Sprites.has(Look.sheet(c))
	check("wygląd: 6 kombinacji płeć × strój ma poprawny kod i istniejący arkusz HD (%s, %s)" % [Look.sheet(Look.code(0, 0)), Look.sheet(Look.code(1, 2))],
		look_codes_ok and Look.sheet(Look.code(0, 0)) == "playerhd3h_male" and Look.sheet(Look.code(1, 2)) == "playerhd3h_female_medic" and not Look.is_valid(17) and not Look.is_valid(-1))
	var l1: bool = Profile.set_look(Look.code(0, 1))                  # Hazmat: poziom 3, a mamy 1
	Profile.add_xp(400, "test")                                       # L3
	var l3: bool = Profile.set_look(Look.code(1, 1))
	var l5: bool = Profile.set_look(Look.code(1, 2))                  # Medic: poziom 5
	Profile.save_to("user://look_test.cfg")
	var saved_look: int = Profile.look
	Profile.reset_for_test()
	Profile.load_from("user://look_test.cfg")
	var restored: int = Profile.look
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://look_test.cfg"))
	check("wygląd: Hazmat zablokowany na L1 (%s), po L3 odblokowany (%s), Medic wciąż zablokowany (%s), zapis/odczyt profilu zachowuje wygląd (%d → %d)" % [str(not l1), str(l3), str(not l5), saved_look, restored],
		not l1 and l3 and not l5 and saved_look == Look.code(1, 1) and restored == Look.code(1, 1))
	Profile.reset_for_test()
	# XP za misję: bonusy i pierwsze ukończenie, Nocny Dyżur połowa
	Profile.reset_for_test()
	var first: int = Profile.apply_mission_result("z1_test", true, true, false)
	var second: int = Profile.apply_mission_result("z1_test", false, false, false)
	var boss: int = Profile.apply_mission_result("z1_boss", false, true, true)
	var was_night: bool = NightShiftMode.active
	NightShiftMode.active = true
	var night: int = Profile.apply_mission_result("z1_test", true, true, false, true)
	NightShiftMode.active = was_night
	check("XP za misję: pierwsza z bonusami %d (=275), powtórka bez bonusów %d (=100), boss %d (=100+25+300+100), Nocny Dyżur %d (=eksp. 175/2)" % [first, second, boss, night],
		first == 275 and second == 100 and boss == 525 and night == 88)
	# XP za zabójstwo: zabójca dostaje XP rodzaju wroga, bot i nieznany strzelec nie
	Profile.reset_for_test()
	var wolek := await dummy(60.0, 20.0, "wolek")
	Combat.apply(wolek, Combat.make_info(Weapons.M83, 50.0, wolek.global_position + Vector2(-4, -6), Vector2.RIGHT, int(player.player_id), "bullet"))
	var xp_wolek: int = Profile.xp
	var tr := await dummy(80.0, 5.0, "trzosek")
	Combat.apply(tr, Combat.make_info(Weapons.M83, 50.0, tr.global_position, Vector2.RIGHT, 9999, "bullet"))      # strzelec spoza gry
	var xp_unknown: int = Profile.xp
	var tr2 := await dummy(100.0, 5.0, "trzosek")
	tr2.name = "LeechSpawn99"
	Combat.apply(tr2, Combat.make_info(Weapons.M83, 50.0, tr2.global_position, Vector2.RIGHT, int(player.player_id), "bullet"))   # Trzoski bossa bez XP
	var xp_minion: int = Profile.xp
	check("XP za zabójstwo: Wołek +%d (=12), nieznany strzelec +0 (%d), Trzosek Pijawki +0 (%d)" % [xp_wolek, xp_unknown - xp_wolek, xp_minion - xp_unknown], xp_wolek == 12 and xp_unknown == xp_wolek and xp_minion == xp_unknown)
	free_dummies()
	await frames(2)
	# zapis i odczyt
	Profile.reset_for_test()
	Profile.add_xp(800, "test")
	Profile.apply_mission_result("z1_m2", false, false, false)
	Profile.equip(0, "wide_arm")
	var path := "user://profile_test.cfg"
	Profile.save_to(path)
	var xp0: int = Profile.xp
	Profile.reset_for_test()
	Profile.load_from(path)
	check("zapis profilu: XP %d (=%d), ukończone misje %s, założone %s" % [Profile.xp, xp0, str(Profile.completed.keys()), str(Profile.equipped)], Profile.xp == xp0 and Profile.completed.has("z1_m2") and Profile.equipped[0] == "wide_arm")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.reset_for_test()

## Faza A1 ekwipunku: granaty (odłamkowy, fosforowy) — zapas drużyny, rzut, zapalnik, wybuch, pole ognia, ściany.
func give_gear(frag := 2, phos := 1, smoke := 1, mine := 1, charge := 1, medkit := 1, defib := 1, scanner := 2) -> void:
	var vals := {"frag": frag, "phos": phos, "smoke": smoke, "mine": mine, "charge": charge, "medkit": medkit, "defib": defib, "scanner": scanner}
	for k in vals:
		Arsenal.stock[k] = vals[k]
	Arsenal._push_stock()

func _t_throwables() -> void:
	Arsenal.reset_throwables()
	check("zestaw wydawany za darmo: frag %d, apteczka %d, defibrylator %d, reszta 0" % [Arsenal.get_throwable("frag"), Arsenal.get_throwable("medkit"), Arsenal.get_throwable("defib")],
		Arsenal.get_throwable("frag") == 1 and Arsenal.get_throwable("medkit") == 1 and Arsenal.get_throwable("defib") == 1 and Arsenal.get_throwable("phos") == 0 and Arsenal.get_throwable("scanner") == 0)
	give_gear()
	check("granaty: zapas (frag %d, phos %d), maks. %d / %d" % [Arsenal.get_throwable("frag"), Arsenal.get_throwable("phos"), Throwables.KINDS["frag"]["max"], Throwables.KINDS["phos"]["max"]],
		Arsenal.get_throwable("frag") == 2 and Arsenal.get_throwable("phos") == 1)
	# --- odłamkowy
	var tgt := await dummy(70.0)
	var wall: Node2D = BrickWall.new()
	wall.name = "TWallG"
	wall.rows = 2
	wall.global_position = player.global_position + Vector2(118.0, 0.0)
	level.add_child(wall)
	await frames(2)
	NoiseMgr.level = 0.0
	Arsenal.request_throw("frag", player.global_position + Vector2(70.0, -30.0), Vector2.ZERO)
	await frames(2)
	var live := get_tree().get_nodes_in_group("grenades").size()
	check("granat odłamkowy: rzut zdejmuje sztukę (zostało %d) i tworzy granat (%d)" % [Arsenal.get_throwable("frag"), live], Arsenal.get_throwable("frag") == 1 and live == 1)
	await wait(1.2)
	check("granat: przed zapalnikiem nic nie boli (obrażenia %.0f)" % dealt(tgt), dealt(tgt) == 0.0)
	await wait(1.2)
	var frag_dealt := dealt(tgt)
	check("granat odłamkowy: wybuch po zapalniku rani cel w promieniu 4 m (%.0f, spodziewane 45–90), granat znika, hałas %.0f" % [frag_dealt, NoiseMgr.level],
		frag_dealt >= 45.0 and frag_dealt <= 90.5 and get_tree().get_nodes_in_group("grenades").is_empty() and NoiseMgr.level >= 10.0)
	check("granat odłamkowy uszkadza też zamurowane przejście (HP %.0f / 120)" % wall.hp, wall.hp < 120.0)
	wall.queue_free()
	level._opened_walls.erase("TWallG")
	free_dummies()
	await frames(2)
	# --- fosforowy
	var burner := await dummy(60.0)
	Arsenal.request_throw("phos", player.global_position + Vector2(60.0, -30.0), Vector2.ZERO)
	await wait(2.0)
	var patches := get_tree().get_nodes_in_group("fire_patches")
	var long_lived := patches.filter(func(p: Node) -> bool: return p.life > 12.0).size()
	check("granat fosforowy: pole ognia z %d plam trwających ~15 s (żyje %d), cel w ogniu płonie (%.1f)" % [patches.size(), long_lived, dealt(burner)], patches.size() == 3 and long_lived == 3 and burner._burn > 0.0 and dealt(burner) > 0.0)
	check("granat fosforowy: zapas %d" % Arsenal.get_throwable("phos"), Arsenal.get_throwable("phos") == 0)
	free_dummies()
	await frames(2)
	# --- brak zapasu, sufit, reset
	Arsenal.request_throw("phos", player.global_position + Vector2(60.0, -30.0), Vector2.ZERO)
	await frames(2)
	check("rzut bez zapasu nic nie robi", get_tree().get_nodes_in_group("grenades").is_empty() and Arsenal.get_throwable("phos") == 0)
	var added: int = Arsenal.add_throwable("frag", 10)
	check("zapas ma sufit (dodano %d, jest %d / %d)" % [added, Arsenal.get_throwable("frag"), Throwables.KINDS["frag"]["max"]], Arsenal.get_throwable("frag") == Throwables.KINDS["frag"]["max"])
	Arsenal.throw_sel = 0
	give_gear()
	Arsenal.cycle_throwable()
	var sel2: String = Arsenal.selected_throwable()
	Arsenal.stock["smoke"] = 0
	Arsenal.cycle_throwable()
	var sel3: String = Arsenal.selected_throwable()
	Arsenal.throw_sel = 0
	check("X przełącza rodzaj (%s → %s → %s, puste pomijane)" % ["frag", sel2, sel3], sel2 == "phos" and sel3 == "mine")
	Arsenal.reset_throwables()
	check("reset przywraca zestaw wydawany (frag %d, phos %d)" % [Arsenal.get_throwable("frag"), Arsenal.get_throwable("phos")], Arsenal.get_throwable("frag") == 1 and Arsenal.get_throwable("phos") == 0 and Arsenal.get_throwable("medkit") == 1)
	_t_item_key()
	await _t_alt_release()
	_t_actions()
	await _t_pad_aim()
	_t_rebind()
	await _t_display_settings()
	_t_captions()
	_t_locale()
	await _t_chat()
	give_gear()
	await _t_gear()
	await _t_economy()

## Klawisz użycia przedmiotu: lewy Alt tak, prawy Alt nie (input_setup.gd).
func _t_item_key() -> void:
	var left := InputEventKey.new()
	left.physical_keycode = KEY_ALT
	left.location = KEY_LOCATION_LEFT
	var right := InputEventKey.new()
	right.physical_keycode = KEY_ALT
	right.location = KEY_LOCATION_RIGHT
	var left_ok: bool = InputMap.event_is_action(left, "throw")
	var right_bad: bool = InputMap.event_is_action(right, "throw")
	var t_bad: bool = false
	var tk := InputEventKey.new()
	tk.physical_keycode = KEY_T
	t_bad = InputMap.event_is_action(tk, "throw")
	check("klawisz użycia przedmiotu: lewy Alt tak (%s), prawy Alt nie (%s), T nie (%s)" % [str(left_ok), str(right_bad), str(t_bad)], left_ok and not right_bad and not t_bad)

## Rzut przy puszczeniu lewego Alta (opinia testera 2026-10-29: Alt+Tab rzucał granat pod nogi): samo wciśnięcie nie rzuca,
## puszczenie rzuca, a inny klawisz w trakcie trzymania (Tab) rozbraja rzut.
func _t_alt_release() -> void:
	give_gear(0, 0, 3)
	Arsenal.throw_sel = Throwables.ORDER.find("smoke")
	Input.action_press("throw")
	await frames(3)
	var on_press: int = Arsenal.get_throwable("smoke")
	Input.action_release("throw")
	await frames(3)
	var on_release: int = Arsenal.get_throwable("smoke")
	Input.action_press("throw")
	await frames(2)
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await frames(2)
	var tab_up := tab.duplicate() as InputEventKey
	tab_up.pressed = false
	Input.parse_input_event(tab_up)
	Input.action_release("throw")
	await frames(3)
	var after_tab: int = Arsenal.get_throwable("smoke")
	check("lewy Alt: wciśnięcie nie rzuca (%d), puszczenie rzuca (%d), Alt+Tab nie rzuca (%d)" % [on_press, on_release, after_tab],
		on_press == 3 and on_release == 2 and after_tab == 2)
	free_dummies()
	give_gear()

## Rejestr akcji (actions.gd): każda akcja jest w InputMap, menu wycina wszystko poza oznaczonymi, a ściąga i podpowiedzi
## pokazują klawisze z wiązań (domyślnie te same napisy co dawniej wpisane ręcznie).
func _t_actions() -> void:
	const Actions := preload("res://scripts/actions.gd")
	var all_registered := true
	for id in Actions.ids():
		all_registered = all_registered and InputMap.has_action(id) and not InputMap.action_get_events(id).is_empty()
	check("rejestr akcji: wszystkie %d akcje są w InputMap z wiązaniami" % Actions.ids().size(), all_registered)
	var blockable: Array = Actions.blockable()
	check("menu wycina akcje gry, ale nie pause / F2 / F11 (%d z %d)" % [blockable.size(), Actions.ids().size()],
		not blockable.has("pause") and not blockable.has("fullscreen") and not blockable.has("steam_invite") and blockable.has("fire") and blockable.has("weapon_next"))
	var sheet: Array = Actions.sheet()
	var rows := {}
	for r in sheet:
		rows[String(r[1])] = String(r[0])
	check("ściąga: ruch „WASD / Arrows”, ogień „J / LMB”, przedmiot „L-Alt / X”, broń „1 2 3 / Wheel ↓” (%s | %s | %s | %s)" % [rows.get("Move & aim"), rows.get("Fire — makes NOISE"), rows.get("Use item / switch item"), rows.get("Switch weapon")],
		rows.get("Move & aim") == "WASD / Arrows" and rows.get("Fire — makes NOISE") == "J / LMB" 		and rows.get("Use item / switch item") == ("L-Cmd / X" if OS.get_name() == "macOS" else "L-Alt / X") and rows.get("Switch weapon") == "1 2 3 / Wheel ↓")
	var ev_a := InputEventKey.new()
	ev_a.physical_keycode = KEY_A
	var ev_e := InputEventKey.new()
	ev_e.physical_keycode = KEY_E
	var ev_pad := InputEventJoypadButton.new()
	ev_pad.button_index = JOY_BUTTON_A
	check("akcje menu (warsztat): A → lewo, E → wróć, przycisk A pada → zatwierdź, nie są wycinane przy menu (%s / %s)" % [Actions.text("menu_accept", true), Actions.text("menu_accept", true, Actions.DEV_PAD)],
		InputMap.event_is_action(ev_a, "menu_left") and InputMap.event_is_action(ev_e, "menu_back") and InputMap.event_is_action(ev_pad, "menu_accept") 		and not blockable.has("menu_accept") and Actions.text("menu_accept", true) == "Enter" and Actions.text("menu_accept", true, Actions.DEV_PAD) == "A")
	check("podpowiedzi: {interact} → E, {restart} → ENTER, {move} → WASD (%s %s %s)" % [Actions.key("interact"), Actions.key("restart"), Actions.fmt("{move}")],
		Actions.key("interact") == "E" and Actions.key("restart") == "ENTER" and Actions.fmt("{move}") == "WASD" and not Actions.fmt("{overcharge}{throw_next}").contains("{"))

## Pad: drążki i spust to wiązania akcji, a prawa gałka daje swobodne (nie 8-kierunkowe) celowanie; podpowiedzi przełączają się na pad.
func _t_pad_aim() -> void:
	const Actions := preload("res://scripts/actions.gd")
	var stick_l := InputEventJoypadMotion.new()
	stick_l.axis = JOY_AXIS_LEFT_X
	stick_l.axis_value = -1.0
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_RIGHT
	trig.axis_value = 1.0
	var bt_a := InputEventJoypadButton.new()
	bt_a.button_index = JOY_BUTTON_A
	check("pad: lewy drążek ← = ruch w lewo, RT = ogień, A = skok",
		InputMap.event_is_action(stick_l, "move_left") and InputMap.event_is_action(trig, "fire") and InputMap.event_is_action(bt_a, "jump"))
	var before: Vector2 = player.aim_dir
	Input.action_press("aim_up", 1.0)
	Input.action_press("aim_right", 0.6)
	await wait(0.3)
	var d: Vector2 = player.aim_dir
	Input.action_release("aim_up")
	Input.action_release("aim_right")
	player.aim_dir = before                                      # test nie zostawia celu przechylonego dla kolejnych
	check("pad: prawa gałka celuje swobodnie, nie po 8 kierunkach (%s)" % str(d.snapped(Vector2(0.01, 0.01))),
		absf(d.length() - 1.0) < 0.05 and absf(d.x - 0.51) < 0.08 and absf(d.y + 0.86) < 0.08)
	Actions.pad_mode = true
	var pad_rows := {}
	for r in Actions.sheet():
		pad_rows[String(r[1])] = String(r[0])
	var pad_fire: String = Actions.key("fire")
	var pad_move: String = Actions.fmt("{move}")
	Actions.pad_mode = false
	check("pad: tryb pada pokazuje przyciski w ściądze i podpowiedziach (%s | %s | %s | %s)" % [pad_rows.get("Move & aim"), pad_rows.get("Jump (hold = higher)"), pad_fire, pad_move],
		pad_rows.get("Move & aim") == "L-Stick / R-Stick" and pad_rows.get("Jump (hold = higher)") == "A" and pad_fire == "RT" and pad_move == "L-STICK")

## Przypisywanie klawiszy (actions.gd): podmiana, zamiana przy konflikcie, zapis / odczyt, reset, zmiana przy otwartym menu.
func _t_rebind() -> void:
	const Actions := preload("res://scripts/actions.gd")
	var k_h := InputEventKey.new()
	k_h.physical_keycode = KEY_H
	var k_f := InputEventKey.new()
	k_f.physical_keycode = KEY_F
	var k_e := InputEventKey.new()
	k_e.physical_keycode = KEY_E
	var k_r := InputEventKey.new()
	k_r.physical_keycode = KEY_R
	var r1: Dictionary = Actions.set_binding("flare", Actions.DEV_KEY, k_h, false)
	check("przypisywanie: flara na H — H działa, F już nie",
		bool(r1["ok"]) and InputMap.event_is_action(k_h, "flare") and not InputMap.event_is_action(k_f, "flare") and Actions.key("flare") == "H")
	var r2: Dictionary = Actions.set_binding("reload", Actions.DEV_KEY, k_e, false)
	check("przypisywanie: konflikt = zamiana (przeładowanie dostaje E, interakcja R; zamieniono z %s)" % String(r2["swapped"]),
		String(r2["swapped"]) == "interact" and InputMap.event_is_action(k_e, "reload") and InputMap.event_is_action(k_r, "interact") \
		and not InputMap.event_is_action(k_e, "interact") and not InputMap.event_is_action(k_r, "reload"))
	var cf := ConfigFile.new()
	Actions.save_to(cf)
	var saved: PackedStringArray = cf.get_section_keys("keys")
	Actions.reset_defaults(false)
	var back_ok: bool = InputMap.event_is_action(k_f, "flare") and InputMap.event_is_action(k_e, "interact") and InputMap.event_is_action(k_r, "reload") and Actions.is_default("flare")
	Actions.load_from(cf)
	var reload_ok: bool = InputMap.event_is_action(k_h, "flare") and InputMap.event_is_action(k_e, "reload") and InputMap.event_is_action(k_r, "interact")
	check("zapis: tylko zmienione akcje (%s), reset przywraca domyślne, wczytanie odtwarza przypisania" % ", ".join(saved),
		saved.size() == 4 and saved.has("inspect_weapon") and back_ok and reload_ok
		and InputMap.event_is_action(k_f, "inspect_weapon"))
	Actions.reset_defaults(false)
	var k_k := InputEventKey.new()
	k_k.physical_keycode = KEY_K
	Settings.block_game_input(true)
	var during_blocked: bool = not InputMap.event_is_action(k_f, "flare")        # menu wycięło akcje gry
	Actions.set_binding("fire", Actions.DEV_KEY, k_k, false)
	var leaked: bool = InputMap.event_is_action(k_k, "fire")                     # w trakcie menu zmiana siedzi w schowku
	Settings.block_game_input(false)
	check("przypisywanie przy otwartym menu: zmiana wraca do InputMap po jego zamknięciu (w menu wycięta %s, po zamknięciu działa %s)" % [str(not leaked), str(InputMap.event_is_action(k_k, "fire"))],
		during_blocked and not leaked and InputMap.event_is_action(k_k, "fire"))
	Actions.reset_defaults(false)
	var bad := InputEventKey.new()
	check("przypisywanie: puste zdarzenie jest odrzucane", not bool(Actions.set_binding("jump", Actions.DEV_KEY, bad, false)["ok"]))

## Ustawienia obrazu i dostępności: jakość efektów, „Reduce Effects", skradanie przełączane. Zmieniamy pola wprost (bez zapisu pliku).
func _t_display_settings() -> void:
	var q0: int = Settings.quality_idx
	var r0: bool = Settings.reduce_fx
	var w0: int = Settings.weather_fx_idx
	var t0: bool = Settings.crouch_toggle
	Settings.quality_idx = 0
	Settings.reduce_fx = false
	Settings.weather_fx_idx = Settings.WEATHER_FX_FULL
	var low_ok: bool = is_equal_approx(Settings.vfx_mult(), 0.4) and is_equal_approx(Settings.post_mult(), 0.0) and Settings.weather_fx_effective() == Settings.WEATHER_FX_REDUCED
	Settings.quality_idx = 2
	var high_ok: bool = is_equal_approx(Settings.vfx_mult(), 1.0) and is_equal_approx(Settings.post_mult(), 1.0) and Settings.weather_fx_effective() == Settings.WEATHER_FX_FULL
	Settings.reduce_fx = true
	var shake_idx0: int = Settings.shake_idx
	Settings.shake_idx = 0
	var calm_ok: bool = is_zero_approx(Settings.shake_mult()) and is_zero_approx(Settings.post_mult()) and Settings.weather_fx_effective() == Settings.WEATHER_FX_REDUCED
	Settings.shake_idx = shake_idx0
	check("jakość i „Reduce Effects”: LOW tnie cząsteczki i ziarno (%s), HIGH daje pełne (%s), Reduce wyłącza wstrząs, ziarno i błysk (%s)" % [str(low_ok), str(high_ok), str(calm_ok)],
		low_ok and high_ok and calm_ok)
	# skradanie: trzymanie (domyślnie) i przełączanie
	Settings.reduce_fx = false
	Settings.crouch_toggle = true
	player.global_position = player.global_position
	await wait(0.3)
	Input.action_press("crouch")
	await wait(0.15)
	Input.action_release("crouch")
	await wait(0.15)
	var latched: bool = player.crouching
	Input.action_press("crouch")
	await wait(0.15)
	Input.action_release("crouch")
	await wait(0.15)
	var released: bool = not player.crouching
	check("skradanie przełączane: jedno naciśnięcie włącza (%s), drugie wyłącza (%s)" % [str(latched), str(released)], latched and released)
	Settings.crouch_toggle = false
	Settings.quality_idx = q0
	Settings.reduce_fx = r0
	Settings.weather_fx_idx = w0
	Settings.crouch_toggle = t0

## Napisy dla dźwięków (captions.gd): kierunek do źródła, odległość, pomijanie szumu (priorytet 0), odświeżanie i wygasanie.
func _t_captions() -> void:
	const Captions := preload("res://scripts/captions.gd")
	var c := Captions.new()
	c.push("[Gunfire]", Vector2(200, 0), 1, Vector2(0, 0))
	c.push("[Footsteps]", Vector2(0, 0), 0, Vector2(0, 0))                 # priorytet 0 — pomijany
	c.push("[Explosion]", Vector2(-600, 0), 3, Vector2(0, 0))
	var l: Array = c.lines()
	var dir_ok: bool = l.size() == 2 and String(l[0]["text"]) == "→  [Gunfire]" and String(l[1]["text"]) == "←  [Explosion]  (far)"
	c.push("[Gunfire]", Vector2(10, 0), 1, Vector2(0, 0))                  # to samo źródło bliżej: odświeża linię, bez strzałki
	var refreshed: bool = c.lines().size() == 2 and String(c.lines()[0]["text"]) == "[Gunfire]"
	for i in 6:
		c.push("[Door %d]" % i, Vector2.ZERO, 1, Vector2.ZERO)
	var capped: bool = c.lines().size() == Captions.MAX_LINES
	c.tick(Captions.LIFE_S + 0.1)
	var expired: bool = c.lines().is_empty()
	check("napisy dźwięków: kierunek i „far” (%s), odświeżenie (%s), limit %d linii (%s), wygasanie (%s)" % [str(dir_ok), str(refreshed), Captions.MAX_LINES, str(capped), str(expired)],
		dir_ok and refreshed and capped and expired)

## Lokalizacja (translations/ui.csv): klucz = angielski tekst, polski po zmianie locale; formatowane teksty przez tr().
func _t_locale() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	var pl_ok: bool = tr("RESUME") == "WZNÓW" and tr("Master volume") == "Głośność ogólna" and tr("[Gunfire]") == "[Strzały]" 		and tr("MODE: < %s >") % tr("CAMPAIGN") == "TRYB: < KAMPANIA >"
	var fmt_ok: bool = (tr("%d / %d ready") % [1, 2]) == "1 / 2 gotowych"
	TranslationServer.set_locale("en")
	var en_ok: bool = tr("RESUME") == "RESUME"
	TranslationServer.set_locale(prev)
	check("lokalizacja: PL (%s, %s), EN zostaje źródłem (%s)" % [str(pl_ok), str(fmt_ok), str(en_ok)], pl_ok and fmt_ok and en_ok)

## Czat drużyny (chat.gd): sanityzacja, nadawca, limit tempa po stronie serwera; Mono audio wyłącza panoramę pozycyjną.
func _t_chat() -> void:
	const ChatScript := preload("res://scripts/chat.gd")
	var clean: bool = ChatScript.sanitize("  hello
 world  ") == "hello world" and ChatScript.sanitize("x".repeat(500)).length() == ChatScript.MAX_LEN 		and ChatScript.sanitize("") == ""
	var chat: Node = get_tree().current_scene.get_node("Chat")
	var got: Array = []
	var cb := func(who: String, text: String) -> void: got.append([who, text])
	chat.line_added.connect(cb)
	chat.send("hello squad")
	chat.send("spam")                                   # w oknie limitu tempa — serwer odrzuca
	await wait(1.2)                                      # > MIN_GAP_MS z zapasem: serwer liczy odstęp od przyjęcia pierwszej linii, które na wolnym CI bywa spóźnione
	chat.send("again")
	var waited := 0                                     # linia wraca przez RPC serwera: na wolnym CI potrzeba więcej niż 2 klatek
	while got.size() < 2 and waited < 120:
		await frames(1)
		waited += 1
	chat.line_added.disconnect(cb)
	var flow: bool = got.size() == 2 and String(got[0][0]) == "P1" and String(got[0][1]) == "hello squad" and String(got[1][1]) == "again"
	check("czat: sanityzacja (%s), nadawca i limit tempa (%d linie: %s)" % [str(clean), got.size(), str(got)], clean and flow)
	for q in Audio._pos_pool:
		q.panning_strength = 1.0
	Settings.mono_audio = true
	Audio.play_at("m83_shot_1", player.global_position + Vector2(100, 0), Audio.BUS_WORLD)
	var mono_ok: bool = not Audio._enabled                # bez urządzenia audio (headless) play_at nic nie robi — nie ma co sprawdzać
	for q in Audio._pos_pool:
		if is_zero_approx(q.panning_strength):
			mono_ok = true
	Settings.mono_audio = false
	check("mono audio: dźwięk pozycyjny bez panoramy (panning_strength 0)", mono_ok)

## Faza A2: dym, mina, ładunek wyburzeniowy, apteczka, defibrylator, skaner.
func _t_gear() -> void:
	var data_ok := Throwables.ORDER.size() == 9 and Throwables.ORDER.all(func(k: String) -> bool: return Throwables.KINDS.has(k) and ["throw", "place", "use"].has(Throwables.mode_of(k)))
	check("tabela przedmiotów: 9 rodzajów (3 rzucane, 2 stawiane, 4 narzędzia — od 1.7.329 zestaw do czyszczenia)", data_ok)
	# --- dym
	var watcher := await dummy(130.0)
	var a: Vector2 = watcher.global_position + Vector2(0, -8)
	var b: Vector2 = player.global_position + Vector2(0, -8)
	var clear_before: bool = watcher._clear_line(player)
	Arsenal.request_throw("smoke", player.global_position + Vector2(60.0, -30.0), Vector2.ZERO)
	await wait(2.4)
	var clouds := get_tree().get_nodes_in_group("smoke_clouds")
	var cloud: Node2D = clouds[0] if clouds.size() > 0 else null
	var blocked: bool = SmokeCloud.blocks(get_tree(), a, b)
	var clear_after: bool = watcher._clear_line(player)
	var outside: bool = SmokeCloud.blocks(get_tree(), a + Vector2(0, -200), b + Vector2(0, -200))
	check("granat dymny: chmura %d (promień %.0f px) zasłania wroga przed celem (widział %s → %s), obok nie" % [clouds.size(), cloud.radius if cloud != null else 0.0, str(clear_before), str(clear_after)],
		cloud != null and cloud.radius > 40.0 and clear_before and blocked and not clear_after and not outside)
	free_dummies()
	await frames(2)
	# --- mina kierunkowa
	var sleeper := await dummy(52.0)
	var behind := await dummy(-52.0)
	sleeper.active = false
	var hp0: int = player.hp
	Arsenal.request_throw("mine", player.global_position + Vector2(0, -6.0), Vector2.RIGHT)
	await frames(2)
	var mines := get_tree().get_nodes_in_group("placed")
	check("mina: postawiona pod nogami (zapas %d), jeszcze nieuzbrojona" % Arsenal.get_throwable("mine"), mines.size() == 1 and Arsenal.get_throwable("mine") == 0 and not mines[0].is_armed())
	await wait(1.6)
	check("mina: śpiący wróg w stożku jej nie odpala (mina stoi, obrażenia %.0f)" % dealt(sleeper), mines.size() == 1 and is_instance_valid(mines[0]) and dealt(sleeper) == 0.0)
	sleeper.active = true
	await wait(0.6)
	check("mina: przebudzony wróg w stożku odpala ją — %.0f obrażeń, za miną %.0f, gracz cały (HP %d → %d)" % [dealt(sleeper), dealt(behind), hp0, player.hp],
		dealt(sleeper) >= 100.0 and dealt(behind) == 0.0 and player.hp == hp0 and get_tree().get_nodes_in_group("placed").is_empty())
	free_dummies()
	await frames(2)
	# --- ładunek wyburzeniowy
	var cwall: Node2D = BrickWall.new()
	cwall.name = "TWallC"
	cwall.rows = 2
	cwall.global_position = player.global_position + Vector2(112.0, 0.0)
	level.add_child(cwall)
	var victim := await dummy(100.0)
	await frames(2)
	NoiseMgr.level = 0.0
	Arsenal.request_throw("charge", player.global_position + Vector2(78.0, -6.0), Vector2.RIGHT)
	await wait(3.2)
	check("ładunek: przed zapalnikiem nic się nie dzieje (obrażenia %.0f, ściana %.0f HP)" % [dealt(victim), cwall.hp], dealt(victim) == 0.0 and cwall.hp > 119.0)
	await wait(1.4)
	check("ładunek: wybuch po 4 s — wróg %.0f obrażeń, zamurowane przejście rozbite, hałas %.0f" % [dealt(victim), NoiseMgr.level],
		dealt(victim) >= 60.0 and level._opened_walls.has("TWallC") and NoiseMgr.level >= 15.0)
	level._opened_walls.erase("TWallC")
	free_dummies()
	await frames(2)
	# --- apteczka, defibrylator (na graczu i bocie)
	give_gear()
	player.hp = 3
	Arsenal.request_use("medkit", int(player.player_id))
	var full_hp_ok: bool = player.hp == 3 and Arsenal.get_throwable("medkit") == 1
	player.hp = 1
	Arsenal.request_use("medkit", int(player.player_id))
	check("apteczka: pełne HP nie zużywa sztuki; ranny dostaje +1 serce (HP %d, zostało %d)" % [player.hp, Arsenal.get_throwable("medkit")], full_hp_ok and player.hp == 2 and Arsenal.get_throwable("medkit") == 0)
	give_gear()
	player.hp = 1
	Arsenal.throw_sel = Throwables.ORDER.find("medkit")
	Input.action_press("throw")
	await wait(2.0)
	var mid_prog: float = player.gear_progress
	var mid_busy: bool = player.gear_text.begins_with("Healing")
	await wait(3.6)
	Input.action_release("throw")
	await frames(3)
	check("apteczka: trzymanie T leczy się po 5 s (postęp w połowie %.2f, HP %d, zostało %d)" % [mid_prog, player.hp, Arsenal.get_throwable("medkit")], mid_prog > 0.25 and mid_prog < 0.6 and mid_busy and player.hp == 2 and Arsenal.get_throwable("medkit") == 0)
	player.hp = 3
	give_gear()
	main._spawn_bot()
	await wait(1.0)
	var bot: Node2D = null
	for c in main._players.get_children():
		if c.is_bot and not c.is_queued_for_deletion():
			bot = c
	if bot == null:
		check("defibrylator: bot do testu", false)
	else:
		bot.set_physics_process(false)
		bot.global_position = player.global_position + Vector2(120.0, 0.0)
		bot._go_down()
		await frames(2)
		check("defibrylator: leżący bot w zasięgu 10 m i w linii wzroku jest celem", player._defib_target() == bot)
		Arsenal.request_use("defib", int(bot.player_id))
		await frames(3)
		check("defibrylator: podnosi leżącego z 7 m (martwy %s, HP %d), zużywa sztukę (%d)" % [str(bot.dead), bot.hp, Arsenal.get_throwable("defib")], not bot.dead and bot.hp > 0 and Arsenal.get_throwable("defib") == 0)
		bot.hp = 1
		give_gear()
		bot.global_position = player.global_position + Vector2(20.0, 0.0)
		Arsenal.request_use("medkit", int(bot.player_id))
		check("apteczka: leczy też kolegę obok (bot HP %d)" % bot.hp, bot.hp == 2)
		bot.queue_free()
	# --- skaner
	give_gear()
	Arsenal.throw_sel = Throwables.ORDER.find("scanner")
	var scan_n0 := Arsenal.get_throwable("scanner")
	NoiseMgr.level = 0.0
	player._start_scan()
	await wait(2.2)
	check("skaner: aktywny (zostało %.1f s), zapas %d → %d, hałas ostatni %.1f, nakładka istnieje" % [player.scan_left, scan_n0, Arsenal.get_throwable("scanner"), NoiseMgr.last_noise_amount],
		player.scan_left > 6.0 and player.scan_left < 9.0 and Arsenal.get_throwable("scanner") == scan_n0 - 1 and NoiseMgr.last_noise_amount >= 0.99 and player._scan_view != null)
	player.scan_left = 0.0
	Arsenal.throw_sel = 0
	Arsenal.reset_throwables()

## Faza A3: ekonomia zaopatrzenia — zakup, sufit, zapas między misjami, wipe, zapis, skrzynki i bot.
func _t_economy() -> void:
	# tabela cen
	var bad: Array = []
	for k in Throwables.ORDER:
		var d: Dictionary = Throwables.KINDS[k]
		var pr: int = Throwables.price_of(k)
		if int(d["issue"]) > int(d["max"]):
			bad.append("%s: issue > max" % k)
		if pr != 0 and (pr < 50 or pr > 300):
			bad.append("%s: cena %d poza 50–300" % [k, pr])
		if pr == 0 and int(d["issue"]) == 0:
			bad.append("%s: nie da się go zdobyć (cena 0 i brak zestawu)" % k)
	check("ekonomia: ceny 50–300, każdy przedmiot da się zdobyć (kupić albo dostać)", bad.is_empty(), "; ".join(bad))
	check("ekonomia: ładunek droższy od miny, mina od granatu odłamkowego (%d > %d > %d)" % [Throwables.price_of("charge"), Throwables.price_of("mine"), Throwables.price_of("frag")],
		Throwables.price_of("charge") > Throwables.price_of("mine") and Throwables.price_of("mine") > Throwables.price_of("frag"))
	# zakup
	var station_state := await _station_begin("pyro_bench")
	var saved_bank := Scrap.bank
	var res: Array = []
	var cb := func(kind: String, ok: bool, reason: String) -> void: res.append([kind, reason])
	Scrap.supply_result.connect(cb)
	Arsenal.reset_throwables()
	Scrap.bank = 50
	Scrap.request_buy_supply("mine")                       # za mało
	Scrap.bank = 500
	Scrap.request_buy_supply("mine")                       # ok
	_station_move("workshop")
	Scrap.request_buy_supply("defib")                      # nie na sprzedaż
	_station_move("pyro_bench")
	for i in 4:
		var purchase_start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - purchase_start < 450:
			await frames(1) # limiter używa czasu rzeczywistego, timer gry może nadrobić długą klatkę
		Scrap.request_buy_supply("frag")                   # 1 w zestawie + 3 kupione = sufit 4, czwarty „full”
	Scrap.supply_result.disconnect(cb)
	var reasons := res.map(func(r: Array) -> String: return String(r[1]))
	var spent := 500 - Scrap.bank
	check("zakup zaopatrzenia: %s, portfel −%d, zapas mina %d frag %d" % [str(reasons), spent, Arsenal.get_throwable("mine"), Arsenal.get_throwable("frag")],
		reasons == ["poor", "ok", "invalid", "ok", "ok", "ok", "full"] and spent == Throwables.price_of("mine") + 3 * Throwables.price_of("frag") and Arsenal.get_throwable("mine") == 1 and Arsenal.get_throwable("frag") == 4)
	Scrap.bank = saved_bank
	await _station_end(station_state)
	# zapas przechodzi do następnej misji, wipe wraca do stanu z początku misji
	give_gear(3, 0, 2, 1, 0, 0, 0, 0)
	Arsenal.begin_mission(true)
	var carried: bool = Arsenal.get_throwable("frag") == 3 and Arsenal.get_throwable("smoke") == 2 and Arsenal.get_throwable("medkit") == 1 and Arsenal.get_throwable("defib") == 1
	Arsenal.stock["frag"] = 0
	Arsenal.stock["smoke"] = 0
	Arsenal.begin_mission(false)
	check("zapas: nowa misja zachowuje (3 frag, 2 dym) i dopełnia zestaw (apteczka, defib); wipe wraca do stanu sprzed misji (frag %d, dym %d)" % [Arsenal.get_throwable("frag"), Arsenal.get_throwable("smoke")],
		carried and Arsenal.get_throwable("frag") == 3 and Arsenal.get_throwable("smoke") == 2)
	Arsenal.load_gear({"frag": 99, "mine": 2, "bogus": 5})
	check("wczytanie zapisu: tylko znane rodzaje i w granicach maksimum (frag %d ≤ %d, mina %d)" % [Arsenal.get_throwable("frag"), Throwables.KINDS["frag"]["max"], Arsenal.get_throwable("mine")],
		Arsenal.get_throwable("frag") == int(Throwables.KINDS["frag"]["max"]) and Arsenal.get_throwable("mine") == 2 and not Arsenal.stock.has("bogus"))
	# skrzynka zaopatrzenia z wroga: podnoszona, gdy zapas nie jest pełny
	give_gear(0, 0, 0, 0, 0, 0, 0, 0)
	_drop_still("supply", Throwables.ORDER.find("scanner"), player.global_position + Vector2(0, -4))
	await wait(1.4)
	check("skrzynka zaopatrzenia: podniesiona, +1 skaner (zapas %d)" % Arsenal.get_throwable("scanner"), Arsenal.get_throwable("scanner") == 1)
	Arsenal.stock["scanner"] = int(Throwables.KINDS["scanner"]["max"])
	_drop_still("supply", Throwables.ORDER.find("scanner"), player.global_position + Vector2(0, -4))     # pod nogami: zostaje przez pełny zapas, nie przez znos
	await wait(1.4)
	var left := get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.kind == "supply").size()
	check("skrzynka zaopatrzenia: przy pełnym zapasie zostaje na ziemi (%d)" % left, left == 1 and Arsenal.get_throwable("scanner") == int(Throwables.KINDS["scanner"]["max"]))
	for n in get_tree().get_nodes_in_group("pickups"):
		if n.kind == "supply":
			n.queue_free()
	# bot używa zapasu: defibrylator na leżącym człowieku, apteczka na rannym
	give_gear(0, 0, 0, 0, 0, 2, 1, 0)
	main._spawn_bot()
	await wait(1.0)
	var bot2: Node2D = null
	for c in main._players.get_children():
		if c.is_bot and not c.is_queued_for_deletion():
			bot2 = c
	if bot2 == null:
		check("bot z zapasem: bot do testu", false)
	else:
		bot2.set_physics_process(false)
		player.hp = 1
		bot2.global_position = player.global_position + Vector2(24.0, 0.0)
		var busy := false
		for i in 330:
			busy = bot2._bot_gear(1.0 / 60.0, null) or busy
			await get_tree().physics_frame
		check("bot leczy rannego człowieka apteczką po ~5 s (HP %d, zostało %d, był zajęty %s)" % [player.hp, Arsenal.get_throwable("medkit"), str(busy)], player.hp == 2 and Arsenal.get_throwable("medkit") == 1 and busy)
		player.hp = 3
		bot2.queue_free()
## Dodatki po fazie 3: linka SINEW-6, zamurowane przejście i kilof, ogień jako mur dla tchórzliwych wrogów.
func _t_phase4() -> void:
	# --- linka SINEW-6 (część „Barbed tether”): trafiony wróg leci ku strzelcowi, bez niej odlatuje
	var plain_t := await dummy(80.0)
	var info0 := Combat.make_info(Weapons.CIEGNO6, 45.0, plain_t.global_position, Vector2.RIGHT, 1, "bullet")
	Combat.apply(plain_t, info0)
	var plain_v: float = plain_t.velocity.x
	var tb := bld(Weapons.CIEGNO6, ["c6_tether"])
	var teth := await dummy(120.0)
	var tank := await dummy(160.0, 100000.0, "wolek")
	var info1 := Combat.make_info(Weapons.CIEGNO6, 45.0, teth.global_position, Vector2.RIGHT, 1, "bullet", tb)
	Combat.apply(teth, info1)
	var info2 := Combat.make_info(Weapons.CIEGNO6, 45.0, tank.global_position, Vector2.RIGHT, 1, "bullet", tb)
	Combat.apply(tank, info2)
	check("linka SINEW-6 (T3): trafiony Trzosek leci ku strzelcowi (%.0f px/s), bez ulepszenia odlatuje (%.0f)" % [teth.velocity.x, plain_v], teth.velocity.x < -150.0 and plain_v > 0.0)
	check("linka: Wołek (knock_mult 0,2) szarpnięty słabiej (%.0f px/s)" % tank.velocity.x, tank.velocity.x < 0.0 and absf(tank.velocity.x) < absf(teth.velocity.x) * 0.5)
	free_dummies()
	await frames(2)
	# --- zamurowane przejście
	var wall: Node2D = BrickWall.new()
	wall.name = "TWall1"
	wall.rows = 2
	wall.global_position = player.global_position + Vector2(30.0, 0.0)
	level.add_child(wall)
	await frames(2)
	var space := player.get_world_2d().direct_space_state
	var org := player.global_position + Vector2(0, -9)
	var in_reach: Array = Combat.in_cone(get_tree(), space, org, Vector2.RIGHT, Weapons.def(Weapons.KILOF).reach, 50.0)
	check("zamurowane przejście: kilof je widzi w zasięgu ciosu", in_reach.has(wall))
	var hp0: float = wall.hp
	Combat.apply(wall, Combat.make_info(Weapons.M83, 8.0, wall.global_position, Vector2.RIGHT, 1, "bullet"))
	Combat.apply(wall, Combat.make_info(Weapons.MACZETA, 30.0, wall.global_position, Vector2.RIGHT, 1, "melee"))
	check("ściana: kula i maczeta nie robią jej nic", wall.hp == hp0)
	var pick := Weapons.def(Weapons.KILOF)
	var swings := 0
	while is_instance_valid(wall) and not wall.is_queued_for_deletion() and swings < 6:
		Combat.apply(wall, Combat.make_info(Weapons.KILOF, pick.damage, wall.global_position, Vector2.RIGHT, 1, "melee"))
		swings += 1
		await frames(2)
	await frames(3)
	check("ściana: kilof rozbija ją w %d uderzeniach (120 HP / %.0f)" % [swings, pick.damage], swings == 3 and (not is_instance_valid(wall) or wall.is_queued_for_deletion()))
	check("rozbicie zapisane (dla dołączających): %s" % str(level._opened_walls), level._opened_walls.has("TWall1"))
	level._opened_walls.erase("TWall1")
	var w2: Node2D = BrickWall.new()
	w2.name = "TWall2"
	w2.rows = 2
	w2.global_position = player.global_position + Vector2(60.0, 0.0)
	level.add_child(w2)
	await frames(2)
	var gd := Weapons.def(Weapons.GNIEW4)
	Combat.explode(get_tree(), w2.global_position + Vector2(0, -10), gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	var after_one: float = w2.hp
	Combat.explode(get_tree(), w2.global_position + Vector2(0, -10), gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	await frames(3)
	check("ściana: dwa wybuchy WRATH-4 ją rozwalają (po pierwszym %.0f HP)" % after_one, after_one < WALL_HP_REF and (not is_instance_valid(w2) or w2.is_queued_for_deletion()))
	level._opened_walls.erase("TWall2")
	free_dummies()
	await frames(2)
	# --- ogień jako mur: tchórzliwi wrogowie (Trzosek, Ślepiec, Skoczek) stają przed płomieniami, Wołek i gracz nie
	var shy_ok := true
	for k in ["trzosek", "slepiec", "skoczek"]:
		var dm := await dummy(200.0, 100000.0, k)
		shy_ok = shy_ok and dm.get_collision_mask_value(7)
	var tank2 := await dummy(220.0, 100000.0, "wolek")
	check("mur ognia: maska FIRE_BIT tylko u Trzoska, Ślepca i Skoczka (nie u Wołka %s ani gracza %s)" % [str(tank2.get_collision_mask_value(7)), str(player.get_collision_mask_value(7))], shy_ok and not tank2.get_collision_mask_value(7) and not player.get_collision_mask_value(7))
	free_dummies()
	await frames(2)
	var runner := await dummy(110.0)
	level.spawn_fire_patch(player.global_position + Vector2(70.0, 0.0), Weapons.HKM9, 1)
	await frames(3)
	var hit_shy: KinematicCollision2D = runner.move_and_collide(Vector2(-60.0, 0.0))
	var shy_x: float = runner.global_position.x - player.global_position.x
	runner.queue_free()
	await frames(2)
	var fighter := await dummy(110.0, 100000.0, "wolek")
	var hit_tank: KinematicCollision2D = fighter.move_and_collide(Vector2(-60.0, 0.0))
	var tank_x: float = fighter.global_position.x - player.global_position.x
	check("mur ognia: Trzosek zatrzymany przed płomieniami (x +%.0f, ogień do +84), Wołek przechodzi (x +%.0f)" % [shy_x, tank_x], hit_shy != null and shy_x > 84.0 and hit_tank == null and tank_x < 70.0)
	for bw in get_tree().get_nodes_in_group("breakables"):
		bw.queue_free()
	free_dummies()
	await frames(2)

## Ogień a podłoże (level.spawn_fire_patch): woda gasi, błoto skraca żar, olej się zapala i ogień biegnie po plamie.
## Kafle podłogi przed graczem są na czas testu podmieniane na olej / wodę / błoto (`level._solid`), potem przywracane.
func _t_liquid_fire() -> void:
	var layer: TileMapLayer = level._solid
	var feet := layer.local_to_map(layer.to_local(player.global_position + Vector2(0.0, 3.0)))
	var saved := {}
	var put := func(c0: int, n: int, ch: String) -> void:
		for i in n:
			var cell := feet + Vector2i(c0 + i, 0)
			if not saved.has(cell):
				saved[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
			var ac: Vector2i = saved[cell][1]
			layer.set_cell(cell, maxi(int(saved[cell][0]), 0), Vector2i(level.KINDS[ch][0], maxi(ac.y, 0)), maxi(int(saved[cell][2]), 0))
	var cell_pos := func(dc: int) -> Vector2:
		var c := feet + Vector2i(dc, 0)
		return layer.to_global(layer.map_to_local(c)) + Vector2(0.0, -8.0 - 1.0)
	var patches := func() -> Array:
		return get_tree().get_nodes_in_group("fire_patches").filter(func(p: Node) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())
	var clear_fire := func() -> void:
		for p in get_tree().get_nodes_in_group("fire_patches"):
			p.queue_free()
	clear_fire.call()
	await frames(2)
	put.call(6, 6, "O")
	put.call(14, 2, "~")
	put.call(18, 2, "m")
	await frames(2)
	check("ogień: kafle testowe czytane jako olej / woda / błoto", level.surface_at(cell_pos.call(7)) == "oil" and level.surface_at(cell_pos.call(14)) == "water" and level.surface_at(cell_pos.call(18)) == "mud",
		"%s %s %s" % [level.surface_at(cell_pos.call(7)), level.surface_at(cell_pos.call(14)), level.surface_at(cell_pos.call(18))])
	# woda: brak żaru
	level.spawn_fire_patch(cell_pos.call(14), Weapons.HKM9, 1)
	await frames(3)
	check("ogień: na wodzie gaśnie (bez żaru)", patches.call().is_empty(), str(patches.call().size()))
	# błoto: żar krótszy niż na ziemi
	level.spawn_fire_patch(cell_pos.call(18), Weapons.HKM9, 1)
	await frames(3)
	var mud_life := float(patches.call()[0].life) if not patches.call().is_empty() else -1.0
	check("ogień: w błocie żar krótszy (%.1f s < %.1f s)" % [mud_life, FirePatch.FIRE_LIFE], mud_life > 0.0 and mud_life < FirePatch.FIRE_LIFE * 0.6)
	clear_fire.call()
	await frames(2)
	# olej: zapłon na skraju plamy przechodzi na całą plamę (6 kafli ≈ 96 px), pali się dłużej i daje jednorazowy hałas
	NoiseMgr.last_noise_amount = 0.0
	level.spawn_fire_patch(cell_pos.call(6), Weapons.HKM9, 1)
	var ign_noise := NoiseMgr.last_noise_amount
	await wait(1.6)
	var ps: Array = patches.call()
	var max_x := -INF
	var min_life := INF
	for p in ps:
		max_x = maxf(max_x, (p as Node2D).global_position.x)
		min_life = minf(min_life, float(p.life))
	var reach: float = max_x - cell_pos.call(6).x
	check("ogień: olej zapala się na całej plamie (%d ognisk, zasięg %.0f px z ~88)" % [ps.size(), reach], ps.size() >= 4 and reach >= 70.0)
	check("ogień: nie wychodzi poza olej (ostatnie ognisko przed kaflem +12)", max_x < cell_pos.call(12).x - 4.0, "%.0f vs %.0f" % [max_x, cell_pos.call(12).x])
	check("ogień: olej pali się dłużej (najkrótszy żar %.1f s > %.1f s)" % [min_life, FirePatch.FIRE_LIFE], min_life > FirePatch.FIRE_LIFE)
	check("ogień: zapłon oleju słychać (hałas %.1f)" % ign_noise, ign_noise >= 2.5)
	clear_fire.call()
	for cell in saved:
		layer.set_cell(cell, int(saved[cell][0]), saved[cell][1], int(saved[cell][2]))
	await frames(2)

## Faza 3 przeglądu broni: tryb serii M-83, ogień na podłodze HKM-9, błysk lufy i światło broni jako sygnał.
func _t_phase3() -> void:
	# --- tryb serii
	var d := equip(Weapons.M83)
	wc.burst_on.clear()
	wc._buf_t = 0.0
	NoiseMgr.last_noise_amount = 0.0
	wc.cd = 0.0
	wc._fire_shot(d)
	var auto_noise: float = NoiseMgr.last_noise_amount
	var auto_heat: float = wc.heat_of(d.id)
	wc.toggle_fire_mode()
	check("B przełącza M-83 na serię (burst_on), P-64 nie ma trybu serii", bool(wc.burst_on.get(d.id, false)) and Weapons.def(Weapons.P64).burst_size == 0)
	d = equip(Weapons.M83)
	wc._burst_left = 0
	wc.cd = 0.0
	await frames(1)                                       # inny tik fizyki niż pierwszy strzał: w jednym tiku hałas zapisuje się tylko, gdy jest głośniejszy (noise_manager.gd: _apply)
	wc._fire_shot(d)
	var burst_noise: float = NoiseMgr.last_noise_amount
	var burst_heat: float = wc.heat_of(d.id)
	check("seria: strzał o %.0f%% cichszy (%.2f vs %.2f) i lufa grzeje się o %.0f%% wolniej" % [100.0 * (1.0 - burst_noise / maxf(auto_noise, 0.001)), burst_noise, auto_noise, 100.0 * (1.0 - burst_heat / maxf(auto_heat, 0.001))],
		absf(burst_noise - auto_noise * d.burst_quiet) < 0.02 and absf(burst_heat - auto_heat * d.burst_heat) < 0.005)
	d = equip(Weapons.M83)
	wc.burst_on[d.id] = true
	var m0: int = wc.mag_of(d.id)
	wc.sim_press = true                                   # jedno naciśnięcie spustu
	await wait(0.9)
	check("seria: jedno naciśnięcie = dokładnie %d strzały i przerwa (magazynek %d → %d)" % [d.burst_size, m0, wc.mag_of(d.id)], m0 - wc.mag_of(d.id) == d.burst_size)
	wc.sim_fire = true
	await wait(0.9)
	wc.sim_fire = false
	var held_shots: int = m0 - d.burst_size - wc.mag_of(d.id)
	check("seria: przytrzymany spust daje serię co %.2f s (strzałów w 0,9 s: %d), wolniej niż ogień ciągły" % [d.burst_gap * (d.burst_size - 1) + d.burst_rest, held_shots], held_shots >= 6 and held_shots <= 9)
	wc.burst_on[d.id] = false
	d = equip(Weapons.M83)
	m0 = wc.mag_of(d.id)
	wc.sim_fire = true
	await wait(0.9)
	wc.sim_fire = false
	var auto_shots: int = m0 - wc.mag_of(d.id)
	check("ogień ciągły bez zmian (strzałów w 0,9 s: %d > seria %d)" % [auto_shots, held_shots], auto_shots >= 8 and auto_shots > held_shots)
	wc.burst_on.clear()
	# --- ogień na podłodze
	var tgt := await dummy(60.0, 100000.0, "trzosek")
	var patch_pos: Vector2 = tgt.global_position
	level.spawn_fire_patch(patch_pos, Weapons.HKM9, 1)
	level.spawn_fire_patch(patch_pos + Vector2(6, 0), Weapons.HKM9, 1)
	await wait(0.7)
	var patches := get_tree().get_nodes_in_group("fire_patches")
	check("ogień na podłodze: dwa blisko siebie scalają się w jeden (%d), cel w ogniu płonie i traci HP (%.1f)" % [patches.size(), dealt(tgt)], patches.size() == 1 and dealt(tgt) > 0.4 and tgt._burn > 0.0)
	var fp: Node = patches[0]
	fp.life = 0.2
	await wait(0.5)
	check("ogień na podłodze wygasa", not is_instance_valid(fp) or fp.is_queued_for_deletion())
	free_dummies()
	await frames(2)
	var far := await dummy(220.0, 100000.0, "trzosek")
	level.spawn_fire_patch(player.global_position + Vector2(60, 0), Weapons.HKM9, 1)
	await wait(0.6)
	check("ogień nie rani celu poza plamą", dealt(far) == 0.0)
	free_dummies()
	await frames(2)
	# płomień HKM-9 zostawia ogień przed graczem
	equip(Weapons.HKM9)
	player.aim_dir = Vector2.RIGHT
	wc.sim_fire = true
	await wait(1.3)
	wc.sim_fire = false
	var dropped := get_tree().get_nodes_in_group("fire_patches").size()
	check("HKM-9: ciągły płomień zostawia ogień na podłodze (plam: %d)" % dropped, dropped >= 1)
	free_dummies()
	await frames(2)
	# --- ćma: ogień wabi (od 1.7.444 nie spala), błysk z lufy budzi
	var moth := await dummy(120.0, 100000.0, "cma")
	Lights.flashes.clear()
	player.flashlight = false
	player.w_firing = false
	var quiet: bool = moth._beh.nearest_light(420.0).is_empty()
	level.spawn_fire_patch(moth.global_position + Vector2(40, 0), Weapons.HKM9, 1)
	await frames(2)
	var by_fire: Dictionary = moth._beh.nearest_light(420.0)
	check("ćma leci na ogień na podłodze (jak na flarę)", quiet and not by_fire.is_empty() and by_fire["kind"] == "flare")
	free_dummies()
	await frames(2)
	moth = await dummy(120.0, 100000.0, "cma")
	var e0 := equip(Weapons.M83)
	wc.cd = 0.0
	wc._server_fire(wc.muzzle_pos(Vector2.RIGHT, e0), Vector2.RIGHT, e0.id, 1, 0.0, 1, true)
	var after_m83: bool = moth._beh.nearest_light(420.0).is_empty()
	var sp := equip(Weapons.SPREAD12)
	wc.cd = 0.0
	wc._server_fire(wc.muzzle_pos(Vector2.RIGHT, sp), Vector2.RIGHT, sp.id, 1, 0.0, 1, true)
	var after_spread: Dictionary = moth._beh.nearest_light(420.0)
	check("błysk z lufy: M-83 (%.1f) nie budzi ćmy, SPREAD-12 (%.1f ≥ %.1f) tak" % [e0.flash_light, sp.flash_light, Lights.FLASH_MIN], after_m83 and not after_spread.is_empty() and after_spread["kind"] == "player")
	free_dummies()
	await frames(2)
	# --- Stalker widzi światło broni cichej (wiązka, płomień), nie zwykły strzał
	var space := player.get_world_2d().direct_space_state
	var probe: Vector2 = player.global_position + Vector2(80, -20)
	player.w_firing = true
	player.weapon = Weapons.LR7
	var seen_beam := Lights.light_weapon_on(probe, get_tree(), space)
	player.weapon = Weapons.HKM9
	var seen_flame := Lights.light_weapon_on(probe, get_tree(), space)
	player.weapon = Weapons.M83
	var seen_gun := Lights.light_weapon_on(probe, get_tree(), space)
	player.w_firing = false
	check("światło broni: wiązka LR-7 i płomień HKM-9 są widoczne dla Stalkera, strzał z M-83 nie", seen_beam == player and seen_flame == player and seen_gun == null)

## Części zmieniające zachowanie broni (dawne poziomy 3: kasetowe, salwa, dobicie, przebicie ścian) — od 1.7.319 części w gniazdach.
func _t_upgrades() -> void:
	var g := pdef(Weapons.GNIEW4, ["g4_cluster"])
	var gh := pdef(Weapons.GNIEW4, ["g4_heavy"])
	check("WRATH-4: głowice kasetowe (%d bomby, wybuch %.0f) albo ciężka (wybuch %.0f / promień %.0f px, uzbrojenie %.0f) — jedno gniazdo" % [g.cluster, g.blast_damage, gh.blast_damage, gh.blast_radius, gh.arm_dist],
		g.cluster == 2 and g.blast_damage < 80.0 and absf(gh.blast_damage - 100.0) < 0.01 and absf(gh.blast_radius - 53.76) < 0.5 and gh.cluster == 0 and gh.arm_dist > g.arm_dist
		and Parts.get_part("g4_heavy")["slot"] == Parts.get_part("g4_cluster")["slot"])
	# bomby kasetowe naprawdę ranią cele po bokach punktu wybuchu
	var left := await dummy(76.0)
	var right := await dummy(124.0)
	var rk := Projectile.new()
	rk.launch(Weapons.GNIEW4, player.global_position + Vector2(10, -4), Vector2.RIGHT, 1, true, 0.0, bld(Weapons.GNIEW4, ["g4_cluster"]))
	get_tree().current_scene.add_child(rk)
	rk.set_physics_process(false)                       # sam rakieta stoi w miejscu — sprawdzamy tylko bomby kasetowe
	rk._scatter_cluster(player.global_position + Vector2(100.0, 0.0))
	await wait(0.5)
	check("WRATH-4 T3: obie bomby kasetowe trafiają cele po bokach", dealt(left) > 5.0 and dealt(right) > 5.0, "lewy %.1f prawy %.1f" % [dealt(left), dealt(right)])
	if is_instance_valid(rk):
		rk.queue_free()
	free_dummies()
	await frames(2)
	var f := pdef(Weapons.SOKOL6, ["f6_belt", "f6_salvo"])
	check("FALCON-6 salwa: 3 rakiety za 2 naboje (pellets %d, koszt %d, magazynek %d)" % [f.pellets, f.ammo_per_shot, f.mag], f.pellets == 3 and f.ammo_per_shot == 2 and f.mag == 60 and f.mag >= f.ammo_per_shot)
	var wd := pdef(Weapons.WIDMO1, ["w1_fast", "w1_rails"])
	check("SPECTER-1: szyny przebijają jedną warstwę ściany, szybki kondensator ładuje szybciej (%.2f s)" % wd.charge_time, wd.wall_pierce >= 24.0 and wd.charge_time < Weapons.base_def(Weapons.WIDMO1).charge_time * 0.75)
	var sn := pdef(Weapons.CIEGNO6, ["c6_twin", "c6_tether"])
	check("SINEW-6: bełt z linką przebija 1 cel, dwa bełty w magazynku", sn.pierce == 1 and sn.mag == 2 and sn.damage > Weapons.base_def(Weapons.CIEGNO6).damage)
	var sp := pdef(Weapons.SPREAD12, ["sp12_ported"])
	check("SPREAD-12: lufa z portami — mniejsze szarpnięcie, trochę głośniej (kamera %.2f, hałas %.2f)" % [sp.cam_kick, sp.n_max],
		sp.cam_kick < Weapons.base_def(Weapons.SPREAD12).cam_kick * 0.7 and sp.n_max > Weapons.base_def(Weapons.SPREAD12).n_max and sp.ignite == 0.0)
	var pe := pdef(Weapons.SRUT8, ["s8_carrier"])
	check("PELLET-8: ładownica — szybsze ładowanie łusek (%.2f s), bez ogłuszenia (%.2f)" % [pe.reload_time, pe.stun],
		pe.reload_time < Weapons.base_def(Weapons.SRUT8).reload_time and absf(pe.stun - Weapons.base_def(Weapons.SRUT8).stun) < 0.01)
	var ki := pdef(Weapons.KILOF, ["kf_seismic"])
	check("KILOF: głowa sejsmiczna — szerszy łuk i dłuższe ogłuszenie (%.0f°, %.1f s), wolniejszy zamach" % [ki.arc_deg, ki.stun],
		ki.arc_deg > Weapons.base_def(Weapons.KILOF).arc_deg * 1.5 and ki.stun >= 2.0 and ki.cooldown > Weapons.base_def(Weapons.KILOF).cooldown)
	# salwa FALCON-6 w kontrolerze (części zamontowane przez gracza): jeden strzał = 3 rakiety i −2 naboje
	await fit_player(Weapons.SOKOL6, ["f6_belt", "f6_salvo"])
	equip(Weapons.SOKOL6)
	var fd: WeaponDef = wc.cur()
	var mag_f: int = wc.mag_of(fd.id)
	var proj_before := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	wc.cd = 0.0
	wc._fire_shot(fd)
	await frames(2)
	var proj_after := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	check("FALCON-6 salwa z broni gracza: jeden strzał = 3 rakiety (%d → %d) i −2 naboje (%d → %d)" % [proj_before, proj_after, mag_f, wc.mag_of(fd.id)], proj_after - proj_before == 3 and mag_f - wc.mag_of(fd.id) == 2)
	await clear_fits()
	free_dummies()
	await frames(2)
	# SPECTER-1 T3 przez prawdziwą ścianę (10 px): bez ulepszenia stop na murze, z ulepszeniem trafia cel za nim
	var wall := StaticBody2D.new()
	var ws := CollisionShape2D.new()
	var wr := RectangleShape2D.new()
	wr.size = Vector2(10, 60)
	ws.shape = wr
	wall.add_child(ws)
	wall.collision_layer = Combat.LAYER_WORLD
	wall.global_position = player.global_position + Vector2(80, -10)
	get_tree().current_scene.add_child(wall)
	var behind := await dummy(120.0)
	await frames(2)
	var space := player.get_world_2d().direct_space_state
	var org := player.global_position + Vector2(0, -9)
	var plain := Combat.trace(space, org, Vector2.RIGHT, 300.0, 99, 0.0, [player.get_rid()])
	var rail_d := pdef(Weapons.WIDMO1, ["w1_rails"])
	var pierced := Combat.trace(space, org, Vector2.RIGHT, 300.0, 99, rail_d.wall_pierce, [player.get_rid()])
	check("SPECTER-1: szyna bez przebicia staje na murze, z hartowanymi szynami trafia cel za ścianą", bool(plain["wall"]) and (plain["hits"] as Array).is_empty() and (pierced["hits"] as Array).size() == 1,
		"bez: ściana %s trafień %d, z: trafień %d" % [str(plain["wall"]), (plain["hits"] as Array).size(), (pierced["hits"] as Array).size()])
	wall.queue_free()
	free_dummies()
	await frames(2)
	# maczeta (długi chwyt + kat): dobija wroga poniżej 35% HP, wyżej zadaje zwykłe obrażenia
	var mb := bld(Weapons.MACZETA, ["mc_long", "mc_exec"])
	var mz := Weapons.def_build(Weapons.MACZETA, mb)
	check("MACZETA: dobicie poniżej %.0f%% HP, zasięg %.0f px" % [mz.execute_frac * 100.0, mz.reach], absf(mz.execute_frac - 0.35) < 0.001 and mz.reach > Weapons.base_def(Weapons.MACZETA).reach)
	var hi := await dummy(40.0, 100.0)
	hi.hp = 50.0
	var r_hi := Combat.apply(hi, Combat.make_info(Weapons.MACZETA, mz.damage, hi.global_position, Vector2.RIGHT, 1, "melee", mb))
	var lo := await dummy(60.0, 100.0)
	lo.hp = 30.0
	var r_lo := Combat.apply(lo, Combat.make_info(Weapons.MACZETA, mz.damage, lo.global_position, Vector2.RIGHT, 1, "melee", mb))
	check("MACZETA: wróg na 50% HP dostaje zwykły cios, na 30% ginie od razu", not bool(r_hi["killed"]) and bool(r_lo["killed"]), "50%%: %s, 30%%: %s" % [str(r_hi["killed"]), str(r_lo["killed"])])
	free_dummies()
	await frames(2)

## Prostokątna ściana testowa na warstwie świata (Combat.LAYER_WORLD) o środku `at` i rozmiarze `size` (px).
func test_wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = "TestWall%d" % randi()
	b.collision_layer = Combat.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	b.global_position = at
	level.add_child(b)
	return b

## Wybuch nie rani przez ścianę (combat.gd `blast_reaches`): wróg i gracz za murem są cali, wróg za niską przeszkodą
## (wystaje głową) obrywa, a ten sam wybuch bez muru rani obu.
func _t_blast_walls() -> void:
	await _settle_player()
	var gd := Weapons.def(Weapons.GNIEW4)
	var open := await dummy(90.0)
	var hidden := await dummy(150.0)
	var c: Vector2 = Combat.center_of(open)
	var at := Vector2(player.global_position.x + 120.0, c.y)
	var wall := test_wall(at + Vector2(14.0, 0.0), Vector2(4.0, 120.0))
	await frames(2)
	Combat.explode(get_tree(), at, gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	check("wybuch: wróg w otwartym polu obrywa (%.0f)" % dealt(open), dealt(open) > 0.0)
	check("wybuch: wróg za ścianą w tej samej odległości nietknięty (%.0f)" % dealt(hidden), dealt(hidden) == 0.0)
	wall.queue_free()
	# niska przeszkoda: zasłania środek sylwetki, ale nie głowę
	var feet_y: float = hidden.global_position.y
	var low := test_wall(Vector2(at.x + 14.0, feet_y - (feet_y - c.y) * 0.55), Vector2(4.0, (feet_y - c.y) * 1.1))
	await frames(2)
	hidden.hp = hidden._max_hp
	Combat.explode(get_tree(), at, gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	check("wybuch: wróg za niską przeszkodą (głowa wystaje) obrywa (%.0f)" % dealt(hidden), dealt(hidden) > 0.0)
	low.queue_free()
	await frames(2)
	hidden.hp = hidden._max_hp
	Combat.explode(get_tree(), at, gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	check("wybuch: bez ściany ten sam wróg obrywa (%.0f)" % dealt(hidden), dealt(hidden) > 0.0)
	free_dummies()
	# gracz: 1 HP od wybuchu drużyny — za ścianą nic
	var hp0: int = player.hp
	var pb: Vector2 = player.global_position + Vector2(30.0, -10.0)
	var pw := test_wall(player.global_position + Vector2(15.0, -10.0), Vector2(4.0, 60.0))
	await frames(2)
	player._invuln = 0.0
	Combat.explode(get_tree(), pb, gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	await frames(2)
	var behind: int = hp0 - int(player.hp)
	pw.queue_free()
	await frames(2)
	player._invuln = 0.0
	Combat.explode(get_tree(), pb, gd.blast_radius, gd.blast_damage, 1, Weapons.GNIEW4, true)
	await frames(2)
	var exposed: int = hp0 - int(player.hp)
	check("wybuch: gracz za ścianą cały (−%d), bez ściany −1 HP (−%d)" % [behind, exposed], behind == 0 and exposed == 1)
	player.hp = hp0
	player._invuln = 0.0
	await frames(2)

## LR-7: wiązka rani od wylotu lufy (jak kule), a jej obraz kończy się tam, gdzie obrażenia. Niska przeszkoda zasłania tułów
## (stara linia obrażeń, 9 px nad stopami), ale nie lufę (12 px) — wiązka przechodzi nad nią i rani wroga za nią.
func _t_beam_origin() -> void:
	await _settle_player()
	var d := equip(Weapons.LR7)
	var muzzle: Vector2 = wc.muzzle_pos(Vector2.RIGHT, d)
	var body_y: float = player.global_position.y - 9.0
	var top: float = (muzzle.y + body_y) * 0.5
	var feet: float = player.global_position.y
	var low := test_wall(Vector2(player.global_position.x + 26.0, (top + feet) * 0.5), Vector2(4.0, feet - top))
	var t := await dummy(70.0)
	await frames(2)
	wc.sim_fire = true
	await wait(0.4)
	var tr: Dictionary = wc.beam_trace(d, player.aim_dir)
	var view_end: Vector2 = player.global_position + player.view._beam_end
	wc.sim_fire = false
	await wait(0.15)
	check("LR-7: wylot (y %.1f) nad przeszkodą zasłaniającą tułów (y %.1f, szczyt %.1f)" % [muzzle.y, body_y, top], muzzle.y < top and top < body_y)
	check("LR-7: wiązka z lufy przechodzi nad niską przeszkodą i rani wroga za nią (%.0f)" % dealt(t), dealt(t) > 0.0)
	check("LR-7: obraz wiązki kończy się w punkcie obrażeń (%s vs %s)" % [str(view_end.round()), str((tr["end"] as Vector2).round())],
		view_end.distance_to(tr["end"]) < 1.5)
	low.queue_free()
	free_dummies()
	await frames(2)

## Celownik: promień ramion to prawdziwy stożek rozrzutu w odległości kursora (WeaponDef.cone_radius), zgodny z `pellet_dirs`.
func _t_crosshair_spread() -> void:
	const View := preload("res://scripts/weapon_view.gd")
	var m := Weapons.def(Weapons.M83)
	var r75 := View.spread_radius(m, 4.0, 75.0)
	var r150 := View.spread_radius(m, 4.0, 150.0)
	check("celownik: M-83, rozrzut 4,8°, kursor 150 px → promień %.1f px (tan · odległość)" % r150, absf(r150 - 150.0 * tan(deg_to_rad(4.8))) < 0.05)
	check("celownik: promień rośnie z odległością kursora (75 px %.1f, 150 px %.1f)" % [r75, r150], absf(r150 - 2.0 * r75) < 0.05)
	var far := View.spread_radius(m, 4.0, 1000.0)
	check("celownik: dalej niż zasięg lotu (%.0f px) promień już nie rośnie (%.1f)" % [m.range_px, far], absf(far - View.spread_radius(m, 4.0, m.range_px)) < 0.01)
	var s := Weapons.def(Weapons.SPREAD12)
	check("celownik: śrut obejmuje rozstaw śrucin (%.1f° = %.1f° + %.1f°)" % [s.cone_half_deg(0.0), s.spread_deg, s.jitter_deg], absf(s.cone_half_deg(0.0) - (s.spread_deg + s.jitter_deg)) < 0.001)
	var b := Weapons.def(Weapons.LR7)
	check("celownik: wiązka bez rozrzutu — najmniejsze kółko (%.1f)" % View.spread_radius(b, 2.0, 150.0), is_equal_approx(View.spread_radius(b, 2.0, 150.0), 3.0 * View.CROSS_SCALE))
	# stożek celownika obejmuje każdy prawdziwy kierunek strzału (i nie jest od niego dużo szerszy)
	var ok := true
	var worst := ""
	for d in [m, s, Weapons.def(Weapons.P64), Weapons.def(Weapons.SRUT8)]:
		var cone: float = d.cone_half_deg(2.0)
		var widest := 0.0
		for seed in 300:
			for v in Weapons.pellet_dirs(d, Vector2.RIGHT, seed, 2.0):
				widest = maxf(widest, absf(rad_to_deg(Vector2.RIGHT.angle_to(v))))
		if widest > cone + 0.001 or widest < cone * 0.9:
			ok = false
			worst += " %s: najszerszy %.2f° vs stożek %.2f°" % [d.key, widest, cone]
	check("celownik: stożek = rzeczywisty rozrzut pellet_dirs (4 bronie, 300 strzałów)", ok, worst)

## Mysz: w trybie myszy kierunek idzie na kursor co klatkę (także gdy mysz stoi, a postać się rusza) i WASD go nie nadpisuje;
## spust z klawiatury oddaje celowanie klawiaturze (8 kierunków).
func _t_mouse_aim() -> void:
	var P: GDScript = player.get_script()
	var up_right := Vector2(1, -1).normalized()
	var r: Array = P.pick_aim(Vector2.LEFT, Vector2.ZERO, Vector2.RIGHT, true, Vector2(50, -50))
	check("mysz: idąc w prawo (WASD) dalej celujesz w kursor (%s)" % str((r[0] as Vector2).snapped(Vector2(0.01, 0.01))), (r[0] as Vector2).distance_to(up_right) < 0.001 and bool(r[1]))
	r = P.pick_aim(Vector2.LEFT, Vector2.ZERO, Vector2(1, -1), false, Vector2.ZERO)
	check("klawiatura: 8 kierunków jak dotąd (%s)" % str((r[0] as Vector2).snapped(Vector2(0.01, 0.01))), (r[0] as Vector2).distance_to(up_right) < 0.001 and not bool(r[1]))
	r = P.pick_aim(Vector2.LEFT, Vector2(0.0, -0.7), Vector2.RIGHT, true, Vector2(50, -50))
	check("pad: prawa gałka wygrywa z myszą", (r[0] as Vector2).distance_to(Vector2.UP) < 0.001 and not bool(r[1]))
	r = P.pick_aim(Vector2.LEFT, Vector2.ZERO, Vector2.ZERO, true, Vector2(2, 1))
	check("mysz: kursor na dłoni nie szarpie kierunku", (r[0] as Vector2) == Vector2.LEFT)
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(5, 0)
	var jitter := InputEventMouseMotion.new()
	jitter.relative = Vector2(1, 0)
	var fire_key := InputEventKey.new()
	fire_key.keycode = KEY_J
	fire_key.physical_keycode = KEY_J
	fire_key.pressed = true
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	check("tryb: ruch myszy i jej przycisk włączają tryb myszy, drżenie nie",
		P.aim_mode_after(false, mm) and P.aim_mode_after(false, lmb) and not P.aim_mode_after(false, jitter))
	check("tryb: spust z klawiatury (%s) i pad oddają celowanie klawiaturze / padowi" % OS.get_keycode_string(KEY_J),
		InputMap.event_is_action(fire_key, "fire") and not P.aim_mode_after(true, fire_key) and not P.aim_mode_after(true, pad))
	# w grze: tryb myszy + wciśnięte „w prawo” — kierunek na kursor, przeliczany co klatkę
	await _settle_player()
	var before: Vector2 = player.aim_dir
	player.mouse_aim = true
	Input.action_press("move_right")
	await frames(3)
	var want: Vector2 = (player.get_global_mouse_position() - player._aim_origin()).normalized()
	var got: Vector2 = player.aim_dir
	Input.action_release("move_right")
	check("mysz w grze: WASD nie nadpisuje celowania (aim %s, na kursor %s)" % [str(got.snapped(Vector2(0.01, 0.01))), str(want.snapped(Vector2(0.01, 0.01)))],
		got.distance_to(want) < 0.02 and player.aim_by_mouse and got.distance_to(Vector2.RIGHT) > 0.1)
	player.aim_dir = -want                                       # mysz stoi (zero ruchu): stary kod zostawiał kierunek, jaki był
	await frames(2)
	want = (player.get_global_mouse_position() - player._aim_origin()).normalized()
	check("mysz w grze: kierunek wraca na kursor co klatkę, także gdy mysz stoi", player.aim_dir.distance_to(want) < 0.03,
		"aim %s, na kursor %s" % [str(player.aim_dir.snapped(Vector2(0.01, 0.01))), str(want.snapped(Vector2(0.01, 0.01)))])
	player.mouse_aim = false
	Input.action_press("move_right")
	await frames(2)
	Input.action_release("move_right")
	check("klawiatura w grze: bez trybu myszy „w prawo” celuje w prawo", player.aim_dir.distance_to(Vector2.RIGHT) < 0.001 and not player.aim_by_mouse)
	player.aim_dir = before
	await _settle_player()

## Szybkie kule (1.7.311): broń palna przelatuje zasięg w ułamku sekundy i w locie jest smugą, która nie sięga za lufę;
## rakieta, bełt i granat zostają wolnymi pociskami z własnymi bryłami.
func _t_fast_bullets() -> void:
	var slow := 0.0
	for id in [Weapons.M83, Weapons.P64, Weapons.SPREAD12, Weapons.SRUT8]:
		var d := Weapons.def(id)
		slow = maxf(slow, d.range_px / d.speed)
		var p := Projectile.new()
		p.launch(id, Vector2(100, 100), Vector2.RIGHT, 1, false)
		var near: float = p.tracer_len_at(Vector2(110, 100))
		var far: float = p.tracer_len_at(Vector2(300, 100))
		check("%s: szybka kula ze smugą (%.0f px/s), smuga z bliska kończy się na lufie (%.0f px), dalej %.0f px" % [d.name, d.speed, near, far],
			p.is_fast() and absf(near - 10.0) < 0.01 and absf(far - d.speed * Projectile.TRACER_SEC) < 0.01)
		p.free()
	check("broń palna: cały zasięg w < 0,2 s (najwolniej %.3f s — poddźwiękowy P-83)" % slow, slow < 0.2)
	for id in [Weapons.SOKOL6, Weapons.CIEGNO6, Weapons.GNIEW4]:
		var p := Projectile.new()
		p.launch(id, Vector2.ZERO, Vector2.RIGHT, 1, false)
		check("%s: wolny pocisk z własną bryłą, bez smugi kuli" % Weapons.def(id).name, not p.is_fast())
		p.free()
	# z bliska kula dolatuje do celu w pierwszej klatce lotu — trafienie i tak zostaje policzone
	await _settle_player()
	var e := await dummy(24.0)
	await shoot(Weapons.M83, 3, 0.15)
	await wait(0.2)
	check("M-83 z 24 px: 3 kule trafiają, mimo że lecą 40 px/klatkę (%.0f)" % dealt(e), dealt(e) >= 3.0 * 8.0 - 0.1)
	free_dummies()
	await frames(2)

## Realia lotu i broni (1.7.312): granat WRATH-4 spada jak granat ręczny, śrut bez równego wachlarza, łuska z okna wyrzutowego,
## świst cudzej kuli koło ucha.
func _t_weapon_realism() -> void:
	const Grenade := preload("res://scripts/grenade.gd")
	var g := Weapons.def(Weapons.GNIEW4)
	check("WRATH-4: grawitacja jak granat ręczny i flara (%.0f = %.0f), kształt łuku v²/g jak dawniej (%.0f ≈ 261)" % [g.gravity, Grenade.GRAVITY, g.speed * g.speed / g.gravity],
		is_equal_approx(g.gravity, Grenade.GRAVITY) and absf(g.speed * g.speed / g.gravity - 261.3) < 3.0)
	# śrut: każda śrucina we własnym wycinku stożka, w losowym miejscu
	var s := Weapons.def(Weapons.SPREAD12)
	var w := 2.0 * s.spread_deg / float(s.pellets)
	var in_sector := true
	var first: Array = []
	for seed in 300:
		var dirs := Weapons.pellet_dirs(s, Vector2.RIGHT, seed, 0.0)
		for i in dirs.size():
			var off := rad_to_deg(Vector2.RIGHT.angle_to(dirs[i]))
			var lo := -s.spread_deg + w * i - s.jitter_deg - 0.001
			var hi := -s.spread_deg + w * (i + 1) + s.jitter_deg + 0.001
			in_sector = in_sector and off >= lo and off <= hi
		first.append(rad_to_deg(Vector2.RIGHT.angle_to(dirs[0])))
	var mean := 0.0
	for o in first:
		mean += float(o) / first.size()
	var dev := 0.0
	for o in first:
		dev += pow(float(o) - mean, 2.0) / first.size()
	check("SPREAD-12: śruciny we własnych wycinkach stożka, rozrzucone losowo (odchylenie skrajnej %.2f°, wycinek %.1f°)" % [sqrt(dev), w],
		in_sector and sqrt(dev) > w * 0.2)
	# łuska: okno wyrzutowe na osi broni między chwytem a wylotem
	for id in [Weapons.M83, Weapons.P64, Weapons.SRUT8]:
		var d := Weapons.def(id)
		var ht: Array = wc._hand_tip(Vector2.RIGHT, d)
		var ej: Vector2 = wc.eject_pos(Vector2.RIGHT, d)
		var want: Vector2 = (ht[0] as Vector2).lerp(ht[1], d.eject_frac)
		check("%s: łuska z okna wyrzutowego (%.1f px za wylotem, ułamek %.2f od chwytu)" % [d.name, ej.distance_to(ht[1]), d.eject_frac],
			ej.distance_to(want) < 0.01 and ej.distance_to(ht[1]) < (ht[0] as Vector2).distance_to(ht[1]))
	# świst: kula bota przelatuje nad głową gracza — świst; ta sama kula gracza — nie
	await _settle_player()
	var heard := []
	for shooter in [99, player.player_id]:
		var n0 := Projectile.whizz_count
		var p := Projectile.new()
		p.launch(Weapons.M83, player.global_position + Vector2(60.0, -16.0), Vector2.LEFT, shooter, false)          # z prawej, w mur przy starcie za graczem
		get_tree().current_scene.add_child(p)
		await frames(4)
		heard.append(Projectile.whizz_count > n0)
		if is_instance_valid(p):
			p.queue_free()
	check("świst: cudza kula nad głową świszczy (%s), własna nie (%s)" % [str(heard[0]), str(heard[1])], heard[0] and not heard[1])
	await frames(2)

## Realia broni (1.7.313): P-83 z magazynkiem 8, SPREAD-12 jako półautomat z bębnem (bez pompki w pozie), opadający bełt SINEW-6 krótszy od karabinu,
## żadna broń nie przesuwa strzelca.
func _t_weapon_realism2() -> void:
	const Char3D := preload("res://scripts/char3d.gd")
	var pd := Weapons.def(Weapons.P64)
	check("sidearm to P-83 z magazynkiem 8 (%s, %d)" % [pd.name, pd.mag], pd.name == "P-83" and pd.mag == 8 and pd.key == "p64")
	var sd := Weapons.def(Weapons.SPREAD12)
	var pose: Dictionary = Char3D.WEAPON_POSE["spread12"]
	check("SPREAD-12: półautomat z bębnem 25, bez cyklu pompki w pozie postaci (%d, cykl „%s”)" % [sd.mag, str(pose.get("cycle", ""))],
		sd.mag == 25 and sd.sfx_cycle == "" and not pose.has("cycle") and not sd.reload_per_round)
	var bd := Weapons.def(Weapons.CIEGNO6)
	var md := Weapons.def(Weapons.M83)
	check("SINEW-6: bełt opada z prawdziwym g (%.0f px/s² ≈ %.1f m/s²), zasięg krótszy niż M-83 (%.0f < %.0f)" % [bd.gravity, bd.gravity * 0.082, bd.range_px, md.range_px],
		absf(bd.gravity * 0.082 - 9.81) < 0.3 and bd.range_px < md.range_px)
	var kicks: Array = []
	for d in Weapons.defs():
		if d.kick > 0.0:
			kicks.append(d.key)
	check("żadna broń nie przesuwa strzelca (kick > 0: %s)" % str(kicks), kicks.is_empty())
	# bełt w locie: opada, nie świeci jak granat
	await _settle_player()
	var b := Projectile.new()
	b.launch(Weapons.CIEGNO6, player.global_position + Vector2(-20.0, -60.0), Vector2.RIGHT, 99, false)
	get_tree().current_scene.add_child(b)
	var y0: float = b.global_position.y
	await frames(12)
	var dropped := is_instance_valid(b) and b.global_position.y > y0 + 1.0
	var lit := is_instance_valid(b) and b._light != null
	check("SINEW-6: bełt w locie opada (%s) i nie ma światła granatu (%s)" % [str(dropped), str(lit)], dropped and not lit)
	if is_instance_valid(b):
		b.queue_free()
	await frames(2)

## Realia, etap 0 (1.7.316, GUNSMITH_PLAN.md): ulepszenia lufy i spustu bez „+obrażeń”, P-83 poddźwiękowy, nabój w komorze, granat WRATH-4
## z odległością uzbrojenia, rakieta FALCON-6 rozpędzająca się jak Gyrojet, strzał w locie mniej celny.
func _t_realia_e0() -> void:
	# ulepszenia: lufa, dławik, spust i pompka nie dodają obrażeń (obrażenia daje amunicja)
	var bad: Array = []
	for k in Parts.PARTS:
		for t in Parts.PARTS[k]:
			var nm := String(t["name"]).to_lower()
			if nm.contains("barrel") or nm.contains("choke") or nm.contains("trigger") or nm.contains("pump") or nm.contains("action"):
				for m in t["mods"]:
					if String(m[0]) == "damage":
						bad.append("%s/%s" % [k, t["name"]])
	check("ulepszenia lufy / dławika / spustu nie zmieniają obrażeń (%s)" % str(bad), bad.is_empty())
	var m2 := pdef(Weapons.M83, ["m83_rpk40", "m83_rpkbar"])
	var m0 := Weapons.base_def(Weapons.M83)
	check("M-83 T2 lufa RPK: ciaśniej (%.2f < %.2f), obrażenia bez zmian, magazynek RPK 40" % [m2.jitter_deg, m0.jitter_deg],
		m2.jitter_deg < m0.jitter_deg and is_equal_approx(m2.damage, m0.damage) and m2.mag == 40)
	# P-83: 9×18 mm jest poddźwiękowy, kule karabinu i strzelb — naddźwiękowe
	var pd := Weapons.def(Weapons.P64)
	check("P-83 poddźwiękowy (%.0f < %.0f px/s), M-83 i śrut naddźwiękowe" % [pd.speed, Weapons.SOUND_PX],
		pd.speed < Weapons.SOUND_PX and Weapons.def(Weapons.M83).speed > Weapons.SOUND_PX and Weapons.def(Weapons.SRUT8).speed > Weapons.SOUND_PX)
	# nabój w komorze: broń z zamkiem zamkniętym mieści mag + 1 tylko przy przeładowaniu z nabojem w komorze
	check("nabój w komorze: M-83 30+1, P-83 8+1, pusta broń bez, LR-7 i WRATH-4 bez komory",
		m0.capacity(true) == 31 and m0.capacity(false) == 30 and pd.capacity(true) == 9 and Weapons.def(Weapons.LR7).capacity(true) == Weapons.def(Weapons.LR7).mag
		and Weapons.def(Weapons.GNIEW4).capacity(true) == Weapons.def(Weapons.GNIEW4).mag)
	var p := equip(Weapons.P64, false)
	wc.loadout[2] = Weapons.P64
	wc.slot = 2
	wc.mags[p.id] = 3
	wc.state = Controller.State.READY
	wc.try_reload()
	await wait(p.reload_time + 0.4)
	var tac: int = wc.mag_of(p.id)
	wc.mags[p.id] = 0
	wc.try_reload()
	await wait(p.full_reload_time() + 0.4)
	check("P-83: przeładowanie taktyczne 8+1 (%d), z pustej 8 (%d)" % [tac, wc.mag_of(p.id)], tac == 9 and wc.mag_of(p.id) == 8)
	wc.mags[p.id] = 9
	check("pełna broń z nabojem w komorze nie przeładowuje się", not wc.try_reload())
	wc.slot = 0
	# WRATH-4: trafienie przed uzbrojeniem zapalnika = tępe uderzenie, bez wybuchu i bez hałasu detonacji
	await _settle_player()
	var g := Weapons.def(Weapons.GNIEW4)
	var close := await dummy(30.0)
	var side := await dummy(60.0)
	NoiseMgr.calm()
	var duds0 := Projectile.dud_count
	var gr := Projectile.new()
	gr.launch(Weapons.GNIEW4, player.global_position + Vector2(8, -6), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(gr)
	await wait(0.4)
	check("WRATH-4 z 30 px: bez wybuchu (uderzenie %.0f ≤ %.0f, sąsiad %.0f, Uwaga %.1f, nieuzbrojone +%d)" % [dealt(close), g.damage, dealt(side), NoiseMgr.level, Projectile.dud_count - duds0],
		dealt(close) > 0.0 and dealt(close) <= g.damage + 0.1 and dealt(side) == 0.0 and NoiseMgr.level < 5.0 and Projectile.dud_count == duds0 + 1)
	free_dummies()
	await frames(2)
	# granat w ziemię pod nogami też nie wybucha (strzelec cały)
	NoiseMgr.calm()
	duds0 = Projectile.dud_count
	var hp0: int = player.hp
	gr = Projectile.new()
	gr.launch(Weapons.GNIEW4, player.global_position + Vector2(8, -6), Vector2.from_angle(deg_to_rad(70.0)), 1, true)
	get_tree().current_scene.add_child(gr)
	await wait(0.5)
	check("WRATH-4 pod nogi: nieuzbrojony, strzelec bez obrażeń (%d → %d)" % [hp0, player.hp], Projectile.dud_count == duds0 + 1 and player.hp == hp0 and NoiseMgr.level < 5.0)
	await frames(2)
	# FALCON-6 (Gyrojet): z lufy wolno, rozpędza się; z bliska słaby
	var f := Weapons.def(Weapons.SOKOL6)
	check("FALCON-6: start %.0f px/s, po rozpędzeniu %.0f; obrażenia przy wylocie ×%.2f" % [f.speed_at(0.0), f.speed_at(f.accel_time), f.boost_damage(f.speed_start)],
		f.speed_at(0.0) < f.speed * 0.3 and is_equal_approx(f.speed_at(1.0), f.speed) and f.boost_damage(f.speed_start) < 0.5 and is_equal_approx(f.boost_damage(f.speed), 1.0))
	var near := await dummy(16.0)
	var rk := Projectile.new()
	rk.launch(Weapons.SOKOL6, player.global_position + Vector2(8, -6), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(rk)
	await wait(0.4)
	var near_dmg := dealt(near)
	free_dummies()
	await frames(2)
	var far := await dummy(150.0)
	rk = Projectile.new()
	rk.launch(Weapons.SOKOL6, player.global_position + Vector2(8, -6), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(rk)
	await wait(0.9)
	check("FALCON-6: z bliska słabo (%.1f), z daleka pełne obrażenia (%.1f)" % [near_dmg, dealt(far)], near_dmg > 0.0 and near_dmg < f.damage * 0.6 and dealt(far) >= f.damage * 0.95)
	free_dummies()
	await frames(2)
	# strzał w locie: większy rozrzut niż z ziemi
	var md := equip(Weapons.M83)
	await _settle_player()
	var ground: float = wc.spread_extra(md)
	player.global_position += Vector2(0.0, -60.0)
	player.velocity = Vector2.ZERO
	await frames(3)
	var in_air: bool = not player.is_on_floor()
	var air: float = wc.spread_extra(md)
	check("strzał w locie: rozrzut +%.1f° (ziemia %.2f, w powietrzu %.2f)" % [md.air_spread, ground, air], in_air and air >= ground + md.air_spread - 0.01)
	await _settle_player()

## Obsługa broni, etap 3a (1.7.324, GUNSMITH_PLAN.md §5.1–5.2): przy myszy strzał unosi lufę (podrzut) zamiast poszerzać stożek, lufa wraca;
## kucanie i oparcie zmniejszają podrzut; oparcie = krawędź przeszkody tuż pod linią lufy (ściana przed lufą to nie oparcie). Ustawienie CLASSIC
## przywraca sam rozrzut serii. Wszystko synchronicznie: klatka gracza (_local_brain) ustawia tryb celowania od nowa.
func _t_handling_climb() -> void:
	var real0: bool = Settings.realistic_handling
	Settings.realistic_handling = true
	var md := equip(Weapons.M83)
	await _settle_player()
	wc.cool()
	wc.braced = false
	player.aim_by_mouse = true
	var dirs_up: bool = (wc.apply_climb(Vector2.RIGHT) == Vector2.RIGHT)
	wc.climb = 3.0
	var r_up: Vector2 = wc.apply_climb(Vector2.RIGHT)
	var l_up: Vector2 = wc.apply_climb(Vector2.LEFT)
	dirs_up = dirs_up and r_up.y < -0.04 and r_up.x > 0.0 and l_up.y < -0.04 and l_up.x < 0.0
	check("podrzut: lufa idzie w górę ekranu w obie strony (prawo %s, lewo %s)" % [str(r_up.snapped(Vector2(0.001, 0.001))), str(l_up.snapped(Vector2(0.001, 0.001)))], dirs_up)
	wc.cool()
	player.crouching = false
	var per := md.bloom_per_shot * Controller.CLIMB_K
	wc._fire_shot(md)
	var c1: float = wc.climb
	check("podrzut (mysz): strzał unosi lufę o ok. %.2f° (%.2f°), rozrzut serii nie rośnie (%.2f)" % [per, c1, wc.bloom],
		c1 >= per * 0.74 and c1 <= per * 1.26 and wc.bloom == 0.0)
	for i in 40:
		wc._fire_shot(md)
	check("podrzut: najwyżej %.1f° (%.2f°)" % [md.bloom_max * Controller.CLIMB_MAX_K, wc.climb], absf(wc.climb - md.bloom_max * Controller.CLIMB_MAX_K) < 0.001)
	var before: float = wc.climb
	wc._tick_common(0.5)
	check("podrzut: lufa wraca %.1f°/s (%.2f → %.2f po 0,5 s)" % [md.bloom_decay * Controller.CLIMB_RECOVER_K, before, wc.climb],
		absf(before - wc.climb - md.bloom_decay * Controller.CLIMB_RECOVER_K * 0.5) < 0.01)
	wc.cool()
	player.crouching = true
	wc._fire_shot(md)
	var cc: float = wc.climb
	player.crouching = false
	check("podrzut: kucanie ×%.1f (%.2f°)" % [Controller.CLIMB_CROUCH, cc], cc <= per * Controller.CLIMB_CROUCH * 1.26 and cc >= per * Controller.CLIMB_CROUCH * 0.74)
	# klawiatura / pad: podrzut zostaje rozrzutem serii (nie da się go ściągać)
	wc.cool()
	player.aim_by_mouse = false
	wc._fire_shot(md)
	check("klawiatura: zamiast podrzutu rozrzut serii (%.2f°, podrzut %.2f°)" % [wc.bloom, wc.climb], wc.climb == 0.0 and absf(wc.bloom - md.bloom_per_shot) < 0.001)
	# CLASSIC: także z myszą sam rozrzut, bez oparcia
	Settings.realistic_handling = false
	wc.cool()
	player.aim_by_mouse = true
	wc._fire_shot(md)
	check("ustawienie CLASSIC: z myszą dawny rozrzut serii (%.2f°, podrzut %.2f°)" % [wc.bloom, wc.climb], wc.climb == 0.0 and wc.bloom > 0.0)
	Settings.realistic_handling = true
	wc.cool()
	await _settle_player()
	# oparcie: krawędź bryły tuż pod linią lufy przed chwytem
	var ht: Array = wc._hand_tip(Vector2.RIGHT, md)
	var hand: Vector2 = ht[0]
	var line_y: float = hand.lerp(ht[1], 0.75).y          # wysokość łoża nad krawędzią
	var line_top: float = minf(hand.y, (ht[1] as Vector2).y)
	var line_bot: float = maxf(hand.y, (ht[1] as Vector2).y)
	var ledge := StaticBody2D.new()
	ledge.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	cs.shape = rs
	ledge.add_child(cs)
	get_tree().current_scene.add_child(ledge)
	var place := func(top: float) -> void:
		var x0 := hand.x + 2.0
		var bottom := player.global_position.y - 0.5
		rs.size = Vector2(18.0, bottom - top)
		ledge.global_position = Vector2(x0 + 9.0, (top + bottom) * 0.5)
	wc.bloom = 2.0
	wc.braced = false
	var spread_free: float = wc.spread_extra(md)
	place.call(line_y + 2.5)
	await frames(2)
	var on_ledge: bool = wc.check_brace(md)
	place.call(line_top - 4.0)
	await frames(2)
	var wall: bool = wc.check_brace(md)
	place.call(line_bot + 9.0)
	await frames(2)
	var low: bool = wc.check_brace(md)
	Settings.realistic_handling = false
	place.call(line_y + 2.5)
	await frames(2)
	var classic: bool = wc.check_brace(md)
	Settings.realistic_handling = true
	check("oparcie: krawędź 2,5 px pod łożem podpiera broń (%s); nie przy ścianie zasłaniającej lufę (%s), nie przy niskiej przeszkodzie (%s), nie w CLASSIC (%s)" % [str(on_ledge), str(wall), str(low), str(classic)],
		on_ledge and not wall and not low and not classic)
	wc.bloom = 2.0
	wc.braced = true
	var spread_braced: float = wc.spread_extra(md)
	check("oparcie: rozrzut ×%.1f (%.2f → %.2f)" % [Controller.BRACE_SPREAD, spread_free, spread_braced], absf(spread_braced - spread_free * Controller.BRACE_SPREAD) < 0.001)
	player.aim_by_mouse = true
	wc._fire_shot(md)
	var cb: float = wc.climb
	check("oparcie: podrzut ×%.1f (%.2f°)" % [Controller.BRACE_CLIMB, cb], cb <= per * Controller.BRACE_CLIMB * 1.26 and cb >= per * Controller.BRACE_CLIMB * 0.74)
	wc.braced = false
	wc.cool()
	ledge.queue_free()
	await frames(2)
	# prawdziwa skrzynia (14 px): na stojąco broń leży na niej, kucając — skrzynia zasłania lufę. Chwyt i wylot z postaci 3D (w grze zawsze jest;
	# bez niej — headless — zostaje przybliżenie 2D z ręką na 12 px, niższe niż skrzynia)
	var c3_own := false
	if player.c3d == null:
		var c3: Node2D = (load("res://scripts/char3d.gd") as GDScript).new()
		player.add_child(c3)
		if c3.setup("male_scav"):
			player.c3d = c3
			c3_own = true
		else:
			c3.queue_free()
	var crate: RigidBody2D = (load("res://scripts/prop.gd") as GDScript).new()
	crate.kind = "crate"
	crate.position = player.global_position + Vector2(12.5, -1.0)
	get_tree().current_scene.add_child(crate)
	await wait(0.4)
	var crate_stand: bool = wc.check_brace(md)
	player.crouching = true
	var crate_crouch: bool = wc.check_brace(md)
	player.crouching = false
	check("oparcie: na stojąco o skrzynię tak (%s), kucając nie — skrzynia zasłania lufę (%s)" % [str(crate_stand), str(crate_crouch)], crate_stand and not crate_crouch)
	crate.queue_free()
	if c3_own:
		player.c3d.queue_free()
		player.c3d = null
	await frames(2)
	check("oparcie: nie na otwartej podłodze (%s)" % str(wc.check_brace(md)), not wc.check_brace(md))
	wc.braced = false
	wc.cool()
	player.aim_by_mouse = false
	Settings.realistic_handling = real0
	equip(Weapons.M83)
	await _settle_player()

## Gorąca lufa, etap 3b (1.7.325, GUNSMITH_PLAN.md §5.5): temperatura lufy rośnie z każdym strzałem (M-83: dwa magazynki ciągłym ogniem)
## i stygnie w 45 s; gorąca lufa rozrzuca (×(1 + 0,4·t²)), gorący tłumik głośnieje (×(1 + 0,5·t)); lufa RPK grzeje się wolniej, krótka szybciej;
## temperatura trzymanej broni idzie do gracza (`w_hot`, replikowane — dym i falowanie w view3d). CLASSIC: bez wpływu na rozrzut i hałas.
func _t_hot_barrel() -> void:
	var real0: bool = Settings.realistic_handling
	Settings.realistic_handling = true
	var md := equip(Weapons.M83)
	await _settle_player()
	wc.cool()
	wc.braced = false
	player.aim_by_mouse = false
	var shots_full := int(ceil(1.0 / md.barrel_heat))
	for i in shots_full:
		wc._fire_shot(md)
		wc.mags[md.id] = md.mag
	var full: float = wc.barrel_of(md.id)
	wc._sync_player()
	check("gorąca lufa: M-83 po %d strzałach ma pełną temperaturę (%.2f), gracz ją niesie (w_hot %.2f)" % [shots_full, full, player.w_hot],
		absf(full - 1.0) < 0.001 and absf(player.w_hot - full) < 0.001)
	wc._tick_common(9.0)
	check("gorąca lufa: stygnie %.3f/s (po 9 s %.2f)" % [Controller.BARREL_COOL, wc.barrel_of(md.id)], absf(wc.barrel_of(md.id) - (1.0 - 9.0 * Controller.BARREL_COOL)) < 0.001)
	wc.cool()
	wc.bloom = 1.0
	var cold: float = wc.spread_extra(md)
	wc._barrel[md.id] = 1.0
	wc.bloom = 1.0
	var hot: float = wc.spread_extra(md)
	var want := (md.jitter_deg + cold) * Controller.HOT_SPREAD
	Settings.realistic_handling = false
	var hot_classic: float = wc.spread_extra(md)
	Settings.realistic_handling = true
	check("gorąca lufa: rozrzut +%.2f° przy pełnej temperaturze (%.2f → %.2f), w CLASSIC bez zmian (%.2f)" % [want, cold, hot, hot_classic],
		absf(hot - cold - want) < 0.001 and absf(hot_classic - cold) < 0.001)
	wc._barrel[md.id] = 0.5
	var half: float = wc.spread_extra(md)
	check("gorąca lufa: rośnie z kwadratem temperatury — przy 0,5 tylko ćwierć (%.2f°)" % (half - cold), absf(half - cold - want * 0.25) < 0.001)
	# tłumik: rozgrzana puszka głośnieje; bez tłumika hałas nie zależy od temperatury lufy
	var sup := Weapons.def_build(Weapons.M83, Weapons.build_of(0, Parts.encode_ids("m83", ["m83_pbs1"])))
	wc._barrel[Weapons.M83] = 1.0
	check("gorąca lufa: tłumik ×%.1f przy pełnej temperaturze (%.2f), goła lufa ×%.1f" % [1.0 + Controller.HOT_CAN, wc.hot_can_mult(sup), wc.hot_can_mult(md)],
		absf(wc.hot_can_mult(sup) - (1.0 + Controller.HOT_CAN)) < 0.001 and wc.hot_can_mult(md) == 1.0)
	# części: cięższa lufa RPK grzeje się wolniej, skrócona — szybciej
	var rpk := Weapons.def_build(Weapons.M83, Weapons.build_of(0, Parts.encode_ids("m83", ["m83_rpkbar"])))
	var short := Weapons.def_build(Weapons.M83, Weapons.build_of(0, Parts.encode_ids("m83", ["m83_short"])))
	check("gorąca lufa: lufa RPK grzeje się wolniej (%.4f), krótka szybciej (%.4f) niż fabryczna (%.4f)" % [rpk.barrel_heat, short.barrel_heat, md.barrel_heat],
		rpk.barrel_heat < md.barrel_heat and short.barrel_heat > md.barrel_heat)
	var no_barrel: Array = []
	for w in [Weapons.LR7, Weapons.HKM9, Weapons.WIDMO1, Weapons.MACZETA]:
		if Weapons.def(w).barrel_heat != 0.0:
			no_barrel.append(String(Weapons.def(w).key))
	check("gorąca lufa: wiązka, płomień, szyna i broń biała się nie grzeją (%s)" % str(no_barrel), no_barrel.is_empty())
	wc.cool()
	Settings.realistic_handling = real0
	equip(Weapons.M83)
	await _settle_player()

## Magazynki „mag” leżące na mapie.
func _mags_on_map() -> Array:
	return get_tree().get_nodes_in_group("pickups").filter(func(it: Node) -> bool: return it.get("kind") == "mag" and not it.is_queued_for_deletion())

## Dwa przeładowania, etap 3c (1.7.326, GUNSMITH_PLAN.md §5.3): krótkie [R] — szybkie, magazynek leci na ziemię z resztkami (w broni zostaje nabój
## w komorze), resztki wracają do zapasu dopiero, gdy ktoś kucnie nad magazynkiem; przytrzymane [R] — taktyczne, +0,4 s, resztki zostają. Pusty
## magazynek też spada (nic do podniesienia, znika po 30 s); CLASSIC — dawne dopełnianie; na mapie najwyżej MAG_MAX magazynków.
func _t_two_reloads() -> void:
	var real0: bool = Settings.realistic_handling
	Settings.realistic_handling = true
	for m in _mags_on_map():
		m.queue_free()
	var d := equip(Weapons.M83)
	await _settle_player()
	Arsenal.set_reserve(d.id, 100)
	wc.sim_reload_hold = false
	for i in 6:
		wc.cd = 0.0
		wc._fire_shot(d)
	var left: int = wc.mag_of(d.id) - 1                         # bez naboju w komorze
	wc.try_reload()
	await wait(d.reload_time + 0.5)
	var mags: Array = _mags_on_map()
	var mg: Node2D = mags[0] if mags.size() == 1 else null
	check("szybkie przeładowanie: magazynek z %d nabojami na ziemi (%s), w broni 1 + 30 (%d), zapas −30 (%d)" % [left, str(mg.rounds) if mg != null else "brak", wc.mag_of(d.id), Arsenal.get_reserve(d.id)],
		mg != null and mg.rounds == left and (mg.arg & 255) == Weapons.M83 and wc.mag_of(d.id) == 31 and Arsenal.get_reserve(d.id) == 70 and not wc.tactical)
	# podniesienie: stojąc nad magazynkiem nic się nie dzieje, kucnięcie zwraca resztki do zapasu
	await wait(0.6)
	if mg != null and is_instance_valid(mg):
		player.global_position = mg.global_position
		player.velocity = Vector2.ZERO
	await frames(8)
	var standing_ok: bool = mg != null and is_instance_valid(mg) and not mg.is_queued_for_deletion() and Arsenal.get_reserve(d.id) == 70
	Input.action_press("crouch")
	await frames(8)
	Input.action_release("crouch")
	await frames(2)
	check("magazynek: stojąc nie podnosisz (%s), kucając — resztki wracają do zapasu (zapas %d)" % [str(standing_ok), Arsenal.get_reserve(d.id)],
		standing_ok and Arsenal.get_reserve(d.id) == 70 + left and _mags_on_map().is_empty())
	await _settle_player()
	# taktyczne: przytrzymane [R] — resztki zostają, przeładowanie dłuższe o TAC_EXTRA, nic nie spada
	wc.sim_reload_hold = true
	for i in 6:
		wc.cd = 0.0
		wc._fire_shot(d)
	var r0: int = Arsenal.get_reserve(d.id)
	wc.try_reload()
	await wait(d.reload_time + 0.1)
	var still: bool = wc.state == Controller.State.RELOAD
	await wait(Controller.TAC_EXTRA + 0.3)
	check("taktyczne przeładowanie: dłuższe o %.1f s (%s), resztki zostają (31, zapas −6: %d), nic nie spada (%d)" % [Controller.TAC_EXTRA, str(still), r0 - Arsenal.get_reserve(d.id), _mags_on_map().size()],
		still and wc.tactical and wc.mag_of(d.id) == 31 and Arsenal.get_reserve(d.id) == r0 - 6 and _mags_on_map().is_empty())
	wc.sim_reload_hold = false
	# pusty magazynek: przeładowanie z pustą bronią — magazynek spada pusty, bez poświaty i do podniesienia nie ma nic
	for i in 31:
		wc.cd = 0.0
		wc._fire_shot(d)
	wc.try_reload()
	await wait(d.full_reload_time() + 0.4)
	mags = _mags_on_map()
	check("pusty magazynek też spada (%d, naboi %s), bez poświaty" % [mags.size(), str(mags[0].rounds) if mags.size() > 0 else "-"],
		mags.size() == 1 and mags[0].rounds == 0 and mags[0].get("_glow") == null and wc.mag_of(d.id) == 30)
	for m in mags:
		m.queue_free()
	# CLASSIC: dawne dopełnianie magazynka, nic nie spada
	Settings.realistic_handling = false
	for i in 6:
		wc.cd = 0.0
		wc._fire_shot(d)
	var rc: int = Arsenal.get_reserve(d.id)
	var need: int = d.capacity(true) - wc.mag_of(d.id)
	wc.try_reload()
	await wait(d.reload_time + 0.4)
	check("CLASSIC: dopełnienie bez upuszczania (zapas −%d: %d, magazynków %d)" % [need, rc - Arsenal.get_reserve(d.id), _mags_on_map().size()],
		Arsenal.get_reserve(d.id) == rc - need and _mags_on_map().is_empty())
	Settings.realistic_handling = true
	# limit magazynków na mapie
	for i in Controller.MAG_MAX + 4:
		wc._spawn_mag(Weapons.M83, 0, 0)
	await frames(2)
	check("na mapie najwyżej %d magazynków (%d)" % [Controller.MAG_MAX, _mags_on_map().size()], _mags_on_map().size() == Controller.MAG_MAX)
	for m in _mags_on_map():
		m.queue_free()
	Settings.realistic_handling = real0
	equip(Weapons.M83)
	await _settle_player()

## Kula z broni `w` (typ naboju `t`) wystrzelona z serwera w prawo z wysokości dłoni gracza.
func _shoot_line(w: int, t := 0, from_off := Vector2(6.0, -12.0), dir := Vector2.RIGHT) -> Node:
	var pr := Projectile.new()
	pr.launch(w, player.global_position + from_off, dir, 1, true, 0.0, Weapons.build_of(t, 0))
	get_tree().current_scene.add_child(pr)
	return pr

## Przebijalność i rykoszet, etap 3d (1.7.327, GUNSMITH_PLAN.md §5.7): energia przebicia kuli (WeaponDef.pen) maleje na każdej przeszkodzie
## (ciało 1, skrzynia 0,6, beczka 1,5), obrażenia za przeszkodą — z resztą energii. 9×18 zostaje w pierwszym celu, PS przechodzi przez jedno ciało
## albo skrzynię, BZ przez dwa ciała albo beczkę, breneka przez jedno ciało, śrut nie przebija. Kula od metalu pod kątem < 20° odbija się raz.
func _t_penetration() -> void:
	free_dummies()
	await _settle_player()
	var ps := Weapons.def(Weapons.M83)
	# rząd trzech manekinów: ile trafiła kula i ile zadała za pierwszym
	var row := func(w: int, t: int) -> Array:
		var a: Node = await dummy(40.0)
		var b: Node = await dummy(70.0)
		var c: Node = await dummy(100.0)
		_shoot_line(w, t)
		await wait(0.3)
		var out := [dealt(a), dealt(b), dealt(c)]
		free_dummies()
		await frames(2)
		return out
	var r_ps: Array = await row.call(Weapons.M83, 0)
	check("PS: przez jedno ciało, drugi cel słabiej (%.1f → %.1f), trzeci nietknięty (%.1f)" % [r_ps[0], r_ps[1], r_ps[2]],
		r_ps[0] > 0.0 and r_ps[1] > 0.0 and r_ps[1] < r_ps[0] * 0.3 and r_ps[2] == 0.0)
	var r_bz: Array = await row.call(Weapons.M83, 2)
	check("BZ: przez dwa ciała (%.1f, %.1f, %.1f)" % [r_bz[0], r_bz[1], r_bz[2]], r_bz[0] > 0.0 and r_bz[1] > r_bz[2] and r_bz[2] > 0.0)
	var r_pm: Array = await row.call(Weapons.P64, 0)
	check("9×18: zostaje w pierwszym celu (%.1f, %.1f)" % [r_pm[0], r_pm[1]], r_pm[0] > 0.0 and r_pm[1] == 0.0)
	var r_slug: Array = await row.call(Weapons.SRUT8, 1)
	check("breneka: przez jedno ciało (%.1f, %.1f, %.1f)" % [r_slug[0], r_slug[1], r_slug[2]], r_slug[0] > 0.0 and r_slug[1] > 0.0 and r_slug[2] == 0.0)
	# skrzynia i beczka przed celem
	var cover := func(w: int, t: int, kind: String) -> float:
		var pr: RigidBody2D = (load("res://scripts/prop.gd") as GDScript).new()
		pr.kind = kind
		pr.position = player.global_position + Vector2(30.0, -1.0)
		pr.freeze = true
		get_tree().current_scene.add_child(pr)
		var tgt: Node = await dummy(70.0)
		await frames(3)
		_shoot_line(w, t)
		await wait(0.3)
		var got := dealt(tgt)
		pr.queue_free()
		free_dummies()
		await frames(2)
		return got
	var crate_ps: float = await cover.call(Weapons.M83, 0, "crate")
	var crate_pm: float = await cover.call(Weapons.P64, 0, "crate")
	var barrel_ps: float = await cover.call(Weapons.M83, 0, "barrel")
	var barrel_bz: float = await cover.call(Weapons.M83, 2, "barrel")
	check("skrzynia: PS przechodzi (cel za nią %.1f, ok. połowa), 9×18 nie (%.1f)" % [crate_ps, crate_pm],
		crate_ps > ps.damage * 0.3 and crate_ps < ps.damage * 0.7 and crate_pm == 0.0)
	check("beczka: PS zostaje (%.1f), BZ przechodzi (%.1f)" % [barrel_ps, barrel_bz], barrel_ps == 0.0 and barrel_bz > 0.0)
	# rykoszet: kafel blachy w powietrzu przed graczem; kula pod ostrym kątem w jego wierzch odbija się w górę, pod stromym — nie
	var cell: Vector2i = level._solid.local_to_map(level._solid.to_local(player.global_position + Vector2(64.0, -72.0)))
	var free_cell: bool = level._solid.get_cell_source_id(cell) == -1 and level._solid.get_cell_source_id(cell + Vector2i(0, -1)) == -1
	level._solid.set_cell(cell, 0, Vector2i(2, 0))
	await frames(3)
	var top: Vector2 = level._solid.to_global(level._solid.map_to_local(cell)) + Vector2(0.0, -8.0)
	var shoot_at := func(deg: float) -> Node:
		var d := Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))
		var from := top - d * 40.0
		var pr := Projectile.new()
		pr.launch(Weapons.M83, from, d, 1, true, 0.0, 0)
		get_tree().current_scene.add_child(pr)
		return pr
	var rc0: int = Projectile.ricochet_count
	var graze: Node = shoot_at.call(10.0)
	await frames(3)
	var bounced: bool = Projectile.ricochet_count == rc0 + 1 and is_instance_valid(graze) and (graze.direction as Vector2).y < 0.0
	var rc1: int = Projectile.ricochet_count
	shoot_at.call(55.0)
	await frames(3)
	var steep_none: bool = Projectile.ricochet_count == rc1
	level._solid.set_cell(cell, 0, Vector2i(1, 0))          # beton
	await frames(3)
	var rc2: int = Projectile.ricochet_count
	shoot_at.call(10.0)
	await frames(3)
	var concrete_none: bool = Projectile.ricochet_count == rc2
	level._solid.erase_cell(cell)
	await frames(2)
	check("rykoszet: od blachy pod 10° kula odbija się w górę (%s), pod 55° nie (%s), od betonu nie (%s) [kafel wolny: %s]" % [str(bounced), str(steep_none), str(concrete_none), str(free_cell)],
		free_cell and bounced and steep_none and concrete_none)
	free_dummies()
	await _settle_player()

## Stan techniczny i zacięcia, etap 4a (1.7.328, GUNSMITH_PLAN.md §6): zużycie na strzał (×wear broni, ×3 przy gorącej lufie, ×1,5 z tłumikiem,
## ×ustawienie), szansa zacięcia od 70 % stanu w dół, bezpieczne pierwsze strzały magazynka i przerwa między zacięciami; zacięcie łuski,
## niewypał (P-83: drugie pociągnięcie spustu) i podwójne podanie usuwa [R]; czyszczenie przy ławie (od 1.7.347 czas zamiast złomu).
func _t_condition_jams() -> void:
	var rel0: int = Settings.reliability_idx
	var cond0: Dictionary = Profile.cond.duplicate()
	Settings.reliability_idx = 1
	Profile.cond = {}
	var md := equip(Weapons.M83)
	await _settle_player()
	wc.cool()
	for i in 10:
		wc.cd = 0.0
		wc._fire_shot(md)
	var c10: float = Profile.condition("m83")
	check("zużycie: 10 strzałów z M-83 = −%.2f %% (%.2f)" % [10.0 * Controller.WEAR_SHOT * md.wear, c10], absf(100.0 - c10 - 10.0 * Controller.WEAR_SHOT * md.wear) < 0.001)
	wc._barrel[md.id] = 1.0
	var sup := Weapons.def_build(Weapons.M83, bld(Weapons.M83, ["m83_pbs1"], 0))
	var before: float = Profile.condition("m83")
	wc._fire_shot(sup)
	var hot_sup: float = before - Profile.condition("m83")
	check("zużycie: gorąca lufa ×%.0f i tłumik ×%.1f z części (%.4f %% na strzał)" % [Controller.WEAR_HOT, sup.wear / md.wear, hot_sup],
		sup.wear > md.wear and absf(hot_sup - Controller.WEAR_SHOT * sup.wear * Controller.WEAR_HOT) < 0.0001)
	Settings.reliability_idx = 0
	before = Profile.condition("m83")
	wc._fire_shot(md)
	check("niezawodność OFF: bez zużycia i zacięć (%.3f, szansa %.4f)" % [before - Profile.condition("m83"), wc.jam_chance(md)], Profile.condition("m83") == before and wc.jam_chance(md) == 0.0)
	Settings.reliability_idx = 1
	wc.cool()
	# szansa zacięcia ze stanu
	var ch := func(c: float) -> float:
		Profile.cond["m83"] = c
		return wc.jam_chance(md)
	var c100: float = ch.call(100.0)
	var c70: float = ch.call(70.0)
	var c30: float = ch.call(30.0)
	var c0: float = ch.call(0.0)
	Settings.reliability_idx = 2
	var vet30: float = ch.call(30.0)
	Settings.reliability_idx = 1
	check("szansa zacięcia: 100 %% i 70 %% — 0, 30 %% — 1/%.0f, 0 %% — 1/%.0f, WETERAN ×2 (1/%.0f); LR-7 się nie zacina" % [1.0 / c30, 1.0 / c0, 1.0 / vet30],
		c100 == 0.0 and c70 == 0.0 and absf(c30 - 1.0 / 150.0) < 0.00001 and c0 > c30 and absf(vet30 - 2.0 * c30) < 0.00001 and wc.jam_chance(Weapons.def(Weapons.LR7)) == 0.0)
	wc._shots_mag[md.id] = 0
	var safe_first: bool = wc._roll_jam(md) == ""
	wc._shots_mag[md.id] = 10
	wc._last_jam_ms = Time.get_ticks_msec()
	var safe_gap: bool = wc._roll_jam(md) == ""
	wc._last_jam_ms = -100000
	check("zacięcie nigdy w pierwszych %d strzałach magazynka (%s) ani dwa razy w 10 s (%s)" % [Controller.JAM_SAFE_SHOTS, str(safe_first), str(safe_gap)], safe_first and safe_gap)
	Profile.cond = {}
	# zacięcie łuski: strzał wychodzi, następny — klik; [R] przeładowuje rączką (0,6 s), naboje bez straty
	wc.mags[md.id] = 20
	wc.sim_jam = "stovepipe"
	wc.cd = 0.0
	wc._handle_shot(md, true)
	var after_jam: int = wc.mag_of(md.id)
	wc.cd = 0.0
	wc._dry_latch = false
	wc._handle_shot(md, true)
	var clicked: bool = wc.mag_of(md.id) == after_jam and wc.jammed(md.id) == "stovepipe"
	wc._dry_latch = false
	var started: bool = wc.try_reload()
	var clearing: bool = wc.state == Controller.State.RELOAD and wc.clearing
	wc._tick_reload(Controller.CLEAR_TIME + 0.05)
	check("zacięcie łuski: strzał wyszedł (%d), potem klik (%s), [R] — przeładowanie rączką (%s), po %.1f s gotowa, bez straty naboju (%d)" % [after_jam, str(clicked), str(started and clearing), Controller.CLEAR_TIME, wc.mag_of(md.id)],
		after_jam == 19 and clicked and started and clearing and wc.state == Controller.State.READY and wc.jammed(md.id) == "" and wc.mag_of(md.id) == 19)
	# niewypał: strzału nie ma, [R] wyrzuca nabój
	wc.sim_jam = "misfire"
	wc.cd = 0.0
	wc._handle_shot(md, true)
	var mis_mag: int = wc.mag_of(md.id)
	wc._dry_latch = false
	wc.try_reload()
	wc._tick_reload(Controller.CLEAR_TIME + 0.05)
	check("niewypał: bez strzału (%d), [R] wyrzuca nabój (%d)" % [mis_mag, wc.mag_of(md.id)], mis_mag == 19 and wc.mag_of(md.id) == 18 and wc.jammed(md.id) == "")
	# podwójne podanie: dłuższe usuwanie, jeden nabój stracony
	wc.sim_jam = "double"
	wc.cd = 0.0
	wc._handle_shot(md, true)
	wc._dry_latch = false
	wc.try_reload()
	wc._tick_reload(Controller.CLEAR_TIME + 0.05)
	var still: bool = wc.state == Controller.State.RELOAD
	wc._tick_reload(Controller.DOUBLE_FEED_EXTRA)
	check("podwójne podanie: usuwanie %.1f s (po %.1f s jeszcze trwa: %s), jeden nabój stracony (%d)" % [Controller.CLEAR_TIME + Controller.DOUBLE_FEED_EXTRA, Controller.CLEAR_TIME, str(still), wc.mag_of(md.id)],
		still and wc.state == Controller.State.READY and wc.mag_of(md.id) == 16 and wc.jammed(md.id) == "")
	# P-83: niewypał usuwa drugie pociągnięcie spustu (podwójne działanie)
	var pd := equip(Weapons.P64)
	await frames(2)
	wc.sim_jam = "misfire"
	wc.cd = 0.0
	wc._buf_t = 0.1
	wc._handle_shot(pd, false)
	var p_mag: int = wc.mag_of(pd.id)
	wc._dry_latch = false
	wc._buf_t = 0.1
	wc.cd = 0.0
	wc._handle_shot(pd, false)
	check("P-83: niewypał (%d), drugie pociągnięcie strzela (%d), bez [R]" % [p_mag, wc.mag_of(pd.id)], p_mag == pd.mag and wc.mag_of(pd.id) == pd.mag - 1 and wc.jammed(pd.id) == "")
	# czyszczenie przy ławie (1.7.347): bez złomu, Profile.CLEAN_STEP s za każde rozpoczęte 10 % zużycia; przerwane trzeba zacząć od nowa.
	# Bez czekania na klatki — gracz testu nie stoi przy ławie, więc panel sam by się zamknął; klatkę czyszczenia wołamy ręcznie.
	var bank0: int = Scrap.bank
	var worn_j: Dictionary = Profile.worn.duplicate(true)
	Profile.worn = {}                                             # same czyszczenie: nowe sprężyny (strzały wyżej trochę je zmęczyły — W2)
	Profile.cond["m83"] = 55.0
	var ctime: float = Profile.clean_time("m83")
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	var clean_ok := false
	var clean_info := "brak panelu"
	if wui != null:
		wui.open()
		wui._start_clean(Weapons.M83)
		wui.tick_clean(ctime * 0.5)
		var half: float = Profile.condition("m83")
		wui._stop_clean()                                     # przerwane (np. odejście od ławy) — stan bez zmian
		wui.tick_clean(ctime)
		var stopped: float = Profile.condition("m83")
		wui._start_clean(Weapons.M83)
		wui.tick_clean(ctime * 0.6)
		wui.tick_clean(ctime * 0.6)
		clean_info = "w połowie %.0f, po przerwaniu %.0f, na końcu %.0f, bank %d → %d" % [half, stopped, Profile.condition("m83"), bank0, Scrap.bank]
		clean_ok = half == 55.0 and stopped == 55.0 and Profile.condition("m83") == 100.0 and Scrap.bank == bank0 and wui._clean_w == -1
		wui.close()
	check("czyszczenie: stan 55 %% trwa %.1f s, bez złomu (%s)" % [ctime, clean_info],
		is_equal_approx(ctime, 5.0 * Profile.CLEAN_STEP) and clean_ok and Profile.clean_time("m83") == 0.0)
	Profile.worn = worn_j
	Profile.cond = cond0
	Settings.reliability_idx = rel0
	equip(Weapons.M83)
	await _settle_player()

## Stół konserwacji (WORKSHOP_PLAN.md W2, 1.7.350): lufa i sprężyny zużywają się strzałem (gorąca lufa ×3), zużyta lufa rozrzuca, zmęczone
## sprężyny ograniczają czyszczenie (i zestaw do czyszczenia), wymiana za złom drużyny przez serwer, panel w trybie „service".
func _t_maintenance() -> void:
	var rel0: int = Settings.reliability_idx
	var cond0: Dictionary = Profile.cond.duplicate()
	var worn0: Dictionary = Profile.worn.duplicate(true)
	var bank0: int = Scrap.bank
	Settings.reliability_idx = 1
	Profile.cond = {}
	Profile.worn = {}
	var md := equip(Weapons.M83)
	await _settle_player()
	wc.cool()
	for i in 10:
		wc.cd = 0.0
		wc._fire_shot(md)
	var bw: float = Profile.part_wear("m83", "barrel")
	var sw: float = Profile.part_wear("m83", "springs")
	check("konserwacja: 10 strzałów z M-83 — lufa %.3f %%, sprężyny %.3f %%" % [bw, sw],
		absf(bw - 10.0 * Controller.WEAR_BARREL * md.wear) < 0.0001 and absf(sw - 10.0 * Controller.WEAR_SPRINGS * md.wear) < 0.0001)
	wc._barrel[md.id] = 1.0
	wc._fire_shot(md)
	var hot_b: float = Profile.part_wear("m83", "barrel") - bw
	check("konserwacja: gorąca lufa zużywa lufę ×%.0f (%.4f %% na strzał)" % [Controller.WEAR_HOT, hot_b], absf(hot_b - Controller.WEAR_BARREL * md.wear * Controller.WEAR_HOT) < 0.0001)
	wc._barrel[md.id] = 0.0
	wc.bloom = 0.0
	Profile.worn = {}
	var e0: float = wc.spread_extra(md)
	Profile.worn = {"m83": {"barrel": 100.0}}
	var e1: float = wc.spread_extra(md)
	check("konserwacja: lufa zużyta w 100 %% rozrzuca o %.2f° więcej (stożek ×%.1f)" % [e1 - e0, 1.0 + Controller.BARREL_SPREAD],
		absf((e1 - e0) - (md.jitter_deg + e0) * Controller.BARREL_SPREAD) < 0.0001)
	# zmęczone sprężyny: czyszczenie najwyżej do 100 − 0,5 × zużycie, zestaw do czyszczenia też
	Profile.worn = {"m83": {"springs": 60.0}}
	Profile.cond["m83"] = 40.0
	var cap: float = Profile.clean_cap("m83")
	var ct: float = Profile.clean_time("m83")
	Profile.clean("m83")
	var after_clean: float = Profile.condition("m83")
	Profile.cond["m83"] = 65.0
	Profile.restore("m83", 40.0)
	check("konserwacja: sprężyny zużyte w 60 %% — czyszczenie do %.0f %% (%.1f s, po nim %.0f), zestaw w misji też najwyżej do %.0f" % [cap, ct, after_clean, Profile.condition("m83")],
		cap == 70.0 and is_equal_approx(ct, 3.0 * Profile.CLEAN_STEP) and after_clean == 70.0 and Profile.condition("m83") == 70.0)
	# wymiana za złom drużyny (serwer)
	var station_state := await _station_begin("service_bench")
	var res: Array = []
	var cb := func(w: int, part: String, ok: bool, reason: String) -> void: res.append(reason)
	Scrap.service_result.connect(cb)
	Profile.worn = {"m83": {"springs": 60.0, "barrel": 50.0}}          # od progu wymiany (Profile.SERVICE_DUE) — niżej prośba nie wychodzi z klienta
	Scrap.bank = 30
	Scrap.request_service(Weapons.M83, "springs")
	Scrap.request_service(Weapons.M83, "barrel")                 # 40 złomu, w banku 10 — za mało
	Scrap.request_service(Weapons.LR7, "barrel")                  # broń bez naboi — nie ma lufy do wymiany
	Scrap.request_service(Weapons.M83, "trigger")                 # nie ma takiej części
	await frames(2)
	Scrap.service_result.disconnect(cb)
	check("konserwacja: wymiana sprężyn za %d złomu (ok), lufa za mało złomu, LR-7 i nieznana część odrzucone: %s; bank %d, sprężyny %.0f %%, czyszczenie znowu do %.0f %%" % [
		int(Scrap.SERVICE_COST["springs"]), str(res), Scrap.bank, Profile.part_wear("m83", "springs"), Profile.clean_cap("m83")],
		res == ["ok", "poor", "invalid", "invalid"] and Scrap.bank == 30 - int(Scrap.SERVICE_COST["springs"]) and Profile.part_wear("m83", "springs") == 0.0 and Profile.clean_cap("m83") == 100.0)
	# panel: stół konserwacji ma tylko czyszczenie, lufę i sprężyny (broń energetyczna — samo czyszczenie), ława już nie czyści
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	var ui_ok := false
	var ui_info := "brak panelu"
	if wui != null:
		var had_lr := Scrap.is_unlocked(Weapons.LR7)
		Scrap.unlocked[Weapons.LR7] = true
		wui.open("service")
		var svc: Array = wui._options(Weapons.M83).map(func(o: Dictionary) -> String: return String(o["id"]))
		var svc_lr: Array = wui._options(Weapons.LR7).map(func(o: Dictionary) -> String: return String(o["id"]))
		var tabs_vis: int = wui._page_btns.filter(func(b: Button) -> bool: return b.visible).size()
		var title: String = wui._title.text
		wui.close()
		wui.open("bench")
		var bench_svc: int = wui._options(Weapons.M83).filter(func(o: Dictionary) -> bool: return String(o["slot"]) == "service").size()
		wui.close()
		if not had_lr:
			Scrap.unlocked.erase(Weapons.LR7)
		ui_info = "M-83 %s, LR-7 %s, zakładek %d, tytuł %s, ława %d wierszy serwisu" % [str(svc), str(svc_lr), tabs_vis, title, bench_svc]
		ui_ok = svc == ["clean", "barrel", "springs"] and svc_lr == ["clean"] and tabs_vis == 0 and title == tr("MAINTENANCE") and bench_svc == 0
	check("konserwacja: panel stołu (%s)" % ui_info, ui_ok)
	Scrap.bank = bank0
	Profile.cond = cond0
	Profile.worn = worn0
	Settings.reliability_idx = rel0
	await _station_end(station_state)
	equip(Weapons.M83)
	await _settle_player()

## Stan techniczny, etap 4b (1.7.329, GUNSMITH_PLAN.md §6.1–6.3): zestaw do czyszczenia w misji (+40 %, usuwa zacięcie, zapas zdejmuje serwer),
## zużycie od wody i błota (raz na WADE_GAP s na rodzaj, cały zestaw) i od upadku (broń w rękach), awarie broni eksperymentalnej:
## przegrzanie ogniwa LR-7 (wiązka gaśnie na 1 s) i przebicie kondensatora SPECTER-1 (ładowanie od nowa) — mijają same, [R] ich nie usuwa.
func _t_condition_4b() -> void:
	var rel0: int = Settings.reliability_idx
	var cond0: Dictionary = Profile.cond.duplicate()
	Settings.reliability_idx = 1
	Profile.cond = {}
	var md := equip(Weapons.M83)
	await _settle_player()
	# zestaw do czyszczenia
	Profile.cond["m83"] = 30.0
	wc.jams[md.id] = "stovepipe"
	var kit0: int = Arsenal.get_throwable("cleankit")
	Arsenal.stock["cleankit"] = 1
	var started: bool = player._tick_cleankit(1.0, true)
	player._tick_cleankit(float(Throwables.KINDS["cleankit"]["time"]), true)
	await frames(2)
	check("zestaw do czyszczenia: trzymanie %d s (blokuje ręce: %s) — stan 30 → %.0f %%, zacięcie usunięte (%s), zapas −1 (%d)" % [int(Throwables.KINDS["cleankit"]["time"]), str(started), Profile.condition("m83"), str(wc.jammed(md.id) == ""), Arsenal.get_throwable("cleankit")],
		started and absf(Profile.condition("m83") - 70.0) < 0.001 and wc.jammed(md.id) == "" and Arsenal.get_throwable("cleankit") == 0)
	Arsenal.stock["cleankit"] = kit0
	# woda, błoto, upadek
	Profile.cond = {}
	wc._wade_t.clear()
	var side_key := String(Weapons.def(int(wc.loadout[1])).key)
	wc.wade("water")
	var w1: float = Profile.condition("m83")
	var s1: float = Profile.condition(side_key)
	wc.wade("water")
	var w2: float = Profile.condition("m83")
	wc.wade("mud")
	var w3: float = Profile.condition("m83")
	check("brodzenie: woda −%.0f %% całej broni (M-83 %.0f, %s %.0f), drugi raz zaraz potem nic (%.0f), błoto −%.0f %% (%.0f)" % [Controller.WEAR_WATER, w1, side_key, s1, w2, Controller.WEAR_MUD, w3],
		w1 == 100.0 - Controller.WEAR_WATER and s1 == w1 and w2 == w1 and w3 == w1 - Controller.WEAR_MUD)
	wc.wear_carried(Controller.WEAR_DOWN, true)
	check("upadek: broń w rękach −%.0f %% (%.0f), reszta bez zmian (%.0f)" % [Controller.WEAR_DOWN, Profile.condition("m83"), Profile.condition(side_key)],
		Profile.condition("m83") == w3 - Controller.WEAR_DOWN and Profile.condition(side_key) == s1 - Controller.WEAR_MUD)
	Profile.cond = {}
	# LR-7: przegrzanie ogniwa
	var ld := equip(Weapons.LR7)
	await frames(2)
	Profile.cond["lr7"] = 20.0
	var lr_chance: float = wc.fault_chance(ld)
	wc.sim_fault = "overheat"
	wc.cd = 0.0
	wc._handle_continuous(ld, true)
	var hot: bool = wc.jammed(ld.id) == "overheat" and not wc.firing
	wc.cd = 0.0
	wc._handle_continuous(ld, true)
	var still_off: bool = not wc.firing
	var r_refused: bool = not wc.try_reload()
	wc._tick_common(Controller.OVERHEAT_PAUSE + 0.05)
	check("LR-7: zużyte ogniwo się przegrzewa (szansa %.4f/tik), wiązka gaśnie (%s, %s), [R] nic (%s), po %.0f s znowu działa (%s)" % [lr_chance * Controller.FAULT_TICK, str(hot), str(still_off), str(r_refused), Controller.OVERHEAT_PAUSE, str(wc.jammed(ld.id) == "")],
		lr_chance > 0.0 and hot and still_off and r_refused and wc.jammed(ld.id) == "" and wc.fault_chance(md) == 0.0)
	# SPECTER-1: przebicie kondensatora
	var sd := equip(Weapons.WIDMO1)
	await frames(2)
	var shots0: int = wc.srv_shots
	wc.sim_fault = "arc"
	wc.cd = 0.0
	wc.state = Controller.State.CHARGE
	wc.charge = 1.0
	wc._handle_rail(sd, false, 0.016)
	await frames(2)
	check("SPECTER-1: przebity kondensator — bez strzału (%d), ładunek 0 (%.1f), komunikat (%s)" % [wc.srv_shots - shots0, wc.charge, wc.jammed(sd.id)],
		wc.srv_shots == shots0 and wc.charge == 0.0 and wc.state == Controller.State.READY and wc.jammed(sd.id) == "arc")
	wc._tick_common(Controller.ARC_SHOW + 0.05)
	wc.jams.clear()
	Profile.cond = cond0
	Settings.reliability_idx = rel0
	equip(Weapons.M83)
	await _settle_player()

## Wprawa, etap 5a (1.7.330, GUNSMITH_PLAN.md §7.3): punkty za trafienia (1), krytyki (2) i zabójstwa (5) z danej broni — tylko żywe cele,
## nie skrzynie; 5 stopni (progi Profile.MASTERY_XP); każdy stopień −2 % przeładowania, dobycia i podrzutu, −4 % usuwania zacięcia.
func _t_mastery() -> void:
	var ms0: Dictionary = Profile.mastery.duplicate()
	Profile.mastery = {}
	var md := equip(Weapons.M83)
	await _settle_player()
	var lv_a: int = Profile.add_mastery("m83", int(Profile.MASTERY_XP[1]) - 1)
	var lv_b: int = Profile.add_mastery("m83", 1)
	check("wprawa: progi (%d pkt — stopień %d, +1 — awans na %d)" % [int(Profile.MASTERY_XP[1]) - 1, lv_a, lv_b], lv_a == -1 and lv_b == 1 and Profile.mastery_level("m83") == 1)
	Profile.mastery = {}
	# punkty z prawdziwego strzału: zabójstwo manekina z M-83, trafienie skrzyni nic nie daje
	var dm: Node = await dummy(60.0, 1.0)
	_shoot_line(Weapons.M83)
	await wait(0.3)
	var after_kill: int = Profile.mastery_points("m83")
	free_dummies()
	await frames(2)
	var cr: RigidBody2D = (load("res://scripts/prop.gd") as GDScript).new()
	cr.kind = "crate"
	cr.position = player.global_position + Vector2(40.0, -1.0)
	cr.freeze = true
	get_tree().current_scene.add_child(cr)
	await frames(3)
	_shoot_line(Weapons.P64)
	await wait(0.3)
	var after_crate: int = Profile.mastery_points("p64")
	cr.queue_free()
	await frames(2)
	check("wprawa: zabójstwo z M-83 = %d pkt (%d), trafienie skrzyni z P-83 — nic (%d)" % [int(Controller.MASTERY_PTS[Arsenal.Confirm.KILL]), after_kill, after_crate],
		after_kill == int(Controller.MASTERY_PTS[Arsenal.Confirm.KILL]) and after_crate == 0)
	# efekty piątego stopnia
	Profile.mastery["m83"] = int(Profile.MASTERY_XP[5])
	var mm: float = wc.mastery_mult(md.id)
	wc.mags[md.id] = 10
	Arsenal.set_reserve(md.id, 100)
	wc.sim_reload_hold = true
	wc.try_reload()
	var rl: float = wc._rl_total
	wc._cancel_reload()
	wc.sim_reload_hold = false
	wc.cool()
	player.aim_by_mouse = false
	wc._fire_shot(md)
	var bl: float = wc.bloom
	wc.cool()
	wc.jams[md.id] = "stovepipe"
	wc.try_reload()
	var cl: float = wc._rl_total
	wc._finish_reload()
	wc.jams.clear()
	check("wprawa V: przeładowanie ×%.2f (%.2f s), narastanie rozrzutu ×%.2f (%.2f°), usuwanie zacięcia ×%.2f (%.2f s)" % [mm, rl, mm, bl, 1.0 - 5.0 * Controller.MASTERY_CLEAR_STEP, cl],
		absf(mm - 0.9) < 0.0001 and absf(rl - md.reload_time * 0.9) < 0.001 and absf(bl - md.bloom_per_shot * 0.9) < 0.001 and absf(cl - Controller.CLEAR_TIME * 0.8) < 0.001)
	wc.select_slot(1)
	await frames(1)
	var d2: RefCounted = wc.cur()
	var draw_other: float = wc.state_t
	wc.select_slot(0)
	await frames(1)
	var draw_m83: float = wc.state_t
	check("wprawa V: dobycie M-83 ×0,9 (%.3f s z %.3f), inna broń bez zmian (%.3f s z %.3f)" % [draw_m83, md.draw_time, draw_other, d2.draw_time],
		draw_m83 <= md.draw_time * 0.9 + 0.001 and draw_m83 > md.draw_time * 0.9 - 0.04 and draw_other > d2.draw_time - 0.04)
	Profile.mastery = ms0
	equip(Weapons.M83)
	await _settle_player()

## Historia broni, etap 5b (1.7.331, GUNSMITH_PLAN.md §7.4): zabójstwa z danej broni w profilu, za elitę i bossa nacięcie na kolbie (serwer
## dokleja rangę zabitego do potwierdzenia trafienia); nacięcia siedzą na powierzchni modelu po obu bokach, liczbę trzymanej broni niesie gracz.
func _t_history() -> void:
	var hi0: Dictionary = Profile.history.duplicate(true)
	Profile.history = {}
	var md := equip(Weapons.M83)
	await _settle_player()
	Arsenal.weapon_hit.emit(Arsenal.Confirm.HIT, Weapons.M83, 0)
	Arsenal.weapon_hit.emit(Arsenal.Confirm.KILL, Weapons.M83, 0)
	Arsenal.weapon_hit.emit(Arsenal.Confirm.KILL, Weapons.M83, 1)
	Arsenal.weapon_hit.emit(Arsenal.Confirm.KILL, Weapons.M83, 2)
	check("historia: 3 zabójstwa (%d), nacięcia za elitę i bossa (%d, głębokie %d), trafienie się nie liczy" % [Profile.kills("m83"), Profile.notches("m83"), Profile.boss_notches("m83")],
		Profile.kills("m83") == 3 and Profile.notches("m83") == 2 and Profile.boss_notches("m83") == 1)
	# prawdziwe zabójstwo elity z M-83: serwer dokleja rangę
	Profile.history = {}
	var elite_kind := String(EnemyDefs.elite_kinds()[0])
	var el: Node = await dummy(60.0, 1.0, elite_kind)
	_shoot_line(Weapons.M83)
	await wait(0.3)
	var elite_notch: int = Profile.notches("m83")
	free_dummies()
	await frames(2)
	check("historia: zabicie elity (%s) z M-83 — nacięcie (%d), zabójstwo (%d)" % [elite_kind, elite_notch, Profile.kills("m83")], elite_notch == 1 and Profile.kills("m83") == 1)
	# model: rysy po obu bokach, głęboka wyższa; gracz niesie liczbę nacięć trzymanej broni
	var gm := GunModel.build("m83", [], Char3D.gun_info("m83")["muzzle"], 5, 1)
	var marks: Array = gm.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).mesh is BoxMesh)
	var tall: float = (marks[0] as Node3D).scale.y if marks.size() > 0 else 0.0
	var short: float = (marks[1] as Node3D).scale.y if marks.size() > 1 else 0.0
	gm.free()
	Profile.history = {"m83": {"k": 10, "e": 3, "b": 1}}
	wc._sync_player()
	check("historia: model ma %d rys (5 × 2 boki), głęboka wyższa (%.3f > %.3f); gracz niesie nacięcia (%d)" % [marks.size(), tall, short, player.notches],
		marks.size() == 10 and tall > short and player.notches == 4 + 16 * 1)
	Profile.history = hi0
	await _settle_player()

## Części jako znaleziska, etap 5c (1.7.333, GUNSMITH_PLAN.md §7.1): skrytka zawiera część, elita czasem ją zostawia na ziemi; znaleziona część
## czeka w Scrap.found do ekstrakcji (bank_loot) i dopiero wtedy jest odblokowana dla drużyny; wipe (reset_loot) ją zabiera.
func _t_part_finds() -> void:
	var parts0: Dictionary = Scrap.parts.duplicate()
	var found0: Dictionary = Scrap.found.duplicate()
	var loot0: int = Scrap.loot
	var bank0: int = Scrap.bank
	Scrap.parts = {}
	Scrap.found = {}
	await _settle_player()
	var pid: String = Scrap.pick_find()
	var pw := Weapons.index_of(String(Parts.get_part(pid).get("weapon", ""))) if pid != "" else -1
	check("znaleziska: losowa część z modelem dla broni drużyny (%s)" % pid, pid != "" and GunModel.has_model(pid) and pw >= 0 and Scrap.is_unlocked(pw))
	Scrap.find_part(pid)
	var waiting: bool = Scrap.found.has(pid) and not Scrap.has_part(pid)
	var again: bool = Scrap.find_part(pid)
	Scrap.reset_loot()
	var wiped: bool = Scrap.found.is_empty()
	Scrap.find_part(pid)
	Scrap.bank_loot(0)
	check("znaleziska: część czeka do ekstrakcji (%s), drugi raz nie (%s), wipe ją zabiera (%s), ekstrakcja odblokowuje (%s)" % [str(waiting), str(not again), str(wiped), str(Scrap.has_part(pid))],
		waiting and not again and wiped and Scrap.has_part(pid) and Scrap.found.is_empty())
	Scrap.parts = {}
	# znaleziona część broni specjalnej: po ekstrakcji schemat dla tokarki, nie gotowa część (od 1.7.454)
	var lab_id := "lr7_lens"
	var schem0: Dictionary = Scrap.schematics.duplicate()
	var unl0: Dictionary = Scrap.unlocked.duplicate()
	Scrap.unlocked[Weapons.LR7] = true
	Scrap.find_part(lab_id)
	Scrap.bank_loot(0)
	check("znaleziska: część pracowni po ekstrakcji to schemat (%s), nie część (%s)" % [str(Scrap.schematics.has(lab_id)), str(Scrap.has_part(lab_id))],
		Scrap.schematics.has(lab_id) and not Scrap.has_part(lab_id) and Scrap.found.is_empty())
	Scrap.schematics = schem0
	Scrap.unlocked = unl0
	Scrap.parts = {}
	# skrytka: złom zawsze, część tylko z szansą STASH_PART_CHANCE (wymuszony wynik losowania)
	Scrap.stash_part_roll = 0.99
	var no_part := Scrap.pick_stash_find()
	Scrap.stash_part_roll = 0.0
	_drop_still("stash", 0, player.global_position + Vector2(0.0, -4.0), Scrap.STASH_VALUE)
	var waited := 0.0
	while Scrap.found.is_empty() and waited < 4.0:             # czeka na podniesienie, nie stały czas
		await wait(0.1)
		waited += 0.1
	Scrap.stash_part_roll = -1.0
	check("znaleziska: skrytka daje część z szansą %.0f %% — los poniżej (%s), powyżej nic (%s)" % [Scrap.STASH_PART_CHANCE * 100.0, str(Scrap.found.keys()), no_part],
		Scrap.found.size() == 1 and no_part == "" and Scrap.STASH_PART_CHANCE < 1.0)
	Scrap.found = {}
	# część na ziemi (łup elity): podchodzisz — znaleziona
	var drop_id := "m83_pbs1"
	_drop_still("part", Scrap.part_index(drop_id), player.global_position + Vector2(0.0, -4.0))
	await wait(0.6)
	var left: Array = get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return n.get("kind") == "part" and not n.is_queued_for_deletion())
	check("znaleziska: część zostawiona przez elitę — podniesiona (%s), znajdźka znika (%d)" % [str(Scrap.found.has(drop_id)), left.size()], Scrap.found.has(drop_id) and left.is_empty())
	Scrap.parts = parts0
	Scrap.found = found0
	Scrap.loot = loot0
	Scrap.bank = bank0
	free_dummies()
	await _settle_player()

## Amunicja według kalibru (1.7.317, GUNSMITH_PLAN.md etap 1): wspólna pula 12/70, typy naboi (US, BZ, breneka, zapalające, gumowe),
## wymiana typu klawiszem Z przy przeładowaniu, przebicie pancerza, sklep pudełek, amunicja specjalna przeżywa reset misji.
func _t_ammo_calibers() -> void:
	var errs := Ammo.validate(Weapons.defs(), Throwables.KINDS)
	check("kalibry i typy naboi spójne (%s)" % "; ".join(errs), errs.is_empty())
	var amm_in_x := false
	for k in Throwables.ORDER:
		amm_in_x = amm_in_x or Throwables.is_ammo(String(k))
	check("amunicja nie trafia do wyboru przedmiotu [X]", not amm_in_x and Throwables.SHOP_ORDER.size() == Throwables.ORDER.size() + Throwables.AMMO_ORDER.size())
	Arsenal.reset_mission()
	await frames(2)
	# wspólna pula 12/70
	Arsenal.set_reserve(Weapons.SPREAD12, 30)
	check("12/70: SPREAD-12 i PELLET-8 dzielą zapas (%d = %d), M-83 ma własny" % [Arsenal.get_reserve(Weapons.SRUT8), Arsenal.get_reserve(Weapons.SPREAD12)],
		Arsenal.get_reserve(Weapons.SRUT8) == 30 and Arsenal.pool(Weapons.SRUT8) == Arsenal.pool(Weapons.SPREAD12) and Arsenal.pool(Weapons.M83) != Arsenal.pool(Weapons.SRUT8)
		and Arsenal.pool_max(Weapons.SRUT8) == maxi(Weapons.def(Weapons.SPREAD12).reserve_max, Weapons.def(Weapons.SRUT8).reserve_max))
	# definicje z amunicją
	var ps := Weapons.def_ammo(Weapons.M83, 0)
	var us := Weapons.def_ammo(Weapons.M83, 1)
	var bz := Weapons.def_ammo(Weapons.M83, 2)
	var ps_s := Weapons.def_build(Weapons.M83, bld(Weapons.M83, ["m83_pbs1"], 0))
	var us_s := Weapons.def_build(Weapons.M83, bld(Weapons.M83, ["m83_pbs1"], 1))
	check("7.62 US: poddźwiękowy (%.0f px/s), słabszy (%.1f < %.1f), sam trochę ciszej (%.2f < %.2f)" % [us.speed, us.damage, ps.damage, us.n_max, ps.n_max],
		us.speed < Ammo.SOUND_PX and us.damage < ps.damage and us.n_max < ps.n_max and us.ammo == 1)
	check("7.62 US z tłumikiem: hałas %.2f wobec PS z tłumikiem %.2f (≤ 60%%)" % [us_s.n_max, ps_s.n_max], us_s.suppressor > 0.0 and us_s.n_max <= ps_s.n_max * 0.6)
	check("7.62 BZ: przebija 70%% pancerza, dwa razy więcej energii przebicia (%.1f wobec %.1f), podpala" % [bz.pen, ps.pen], absf(bz.armor_pen - 0.7) < 0.01 and absf(bz.pen - ps.pen * 2.0) < 0.001 and bz.ignite > 0.0)
	var buck := Weapons.def_ammo(Weapons.SRUT8, 0)
	var slug := Weapons.def_ammo(Weapons.SRUT8, 1)
	var rub := Weapons.def_ammo(Weapons.SRUT8, 3)
	check("breneka: 1 pocisk %.0f (≈ 85%% snopa %.0f), bez rozrzutu, zasięg ×2 (%.0f)" % [slug.damage, buck.damage * buck.pellets, slug.range_px],
		slug.pellets == 1 and absf(slug.damage - buck.damage * buck.pellets * 0.85) < 0.01 and slug.spread_deg == 0.0 and absf(slug.range_px - buck.range_px * 2.0) < 0.01)
	check("gumowe: ogłuszają (%.1f s), ranią ćwierć (%.1f), bez krytyka" % [rub.stun, rub.damage], rub.stun >= buck.stun + 1.0 and rub.damage < buck.damage * 0.3 and rub.crit_mult == 1.0)
	check("nieznany typ kalibru = nabój zwykły", Weapons.def_ammo(Weapons.M83, 9) == Weapons.def(Weapons.M83) and Weapons.def_ammo(Weapons.HKM9, 1) == Weapons.def(Weapons.HKM9))
	# BZ przez pancerz Wołka: PS traci 3 na trafienie, BZ tylko 0,9
	await _settle_player()
	var wolek := await dummy(60.0, 100000.0, "wolek")
	var k0 := Projectile.new()
	k0.launch(Weapons.M83, player.global_position + Vector2(8, -6), Vector2.RIGHT, 1, true, 0.0, 0)
	get_tree().current_scene.add_child(k0)
	await wait(0.2)
	var d_ps := dealt(wolek)
	var k2 := Projectile.new()
	k2.launch(Weapons.M83, player.global_position + Vector2(8, -6), Vector2.RIGHT, 1, true, 0.0, 2)
	get_tree().current_scene.add_child(k2)
	await wait(0.2)
	var d_bz := dealt(wolek) - d_ps
	check("pancerz Wołka: PS %.1f, BZ %.1f (BZ traci tylko 30%% pancerza)" % [d_ps, d_bz], d_ps > 0.0 and d_bz > d_ps + 1.5)
	free_dummies()
	await frames(2)
	# wymiana typu klawiszem Z: stary magazynek (z komorą) wraca do zapasu, ładujemy 30 US
	var d := equip(Weapons.M83, false)
	wc.mags[d.id] = 31
	Arsenal.set_reserve(d.id, 100)
	Arsenal.set_reserve(d.id, 50, 1)
	Arsenal.set_reserve(d.id, 0, 2)
	wc.cycle_ammo()
	check("Z: wybór US uruchamia przeładowanie", wc.next_ammo_of(d.id) == 1 and wc.state == Controller.State.RELOAD and wc.mag_of(d.id) == 0)
	await wait(d.full_reload_time() + 0.4)
	check("wymiana na US: 30 US w magazynku (%d, typ %d), zapas US 50 → %d, PS wrócił (100 → %d)" % [wc.mag_of(d.id), wc.ammo_of(d.id), Arsenal.get_reserve(d.id, 1), Arsenal.get_reserve(d.id)],
		wc.mag_of(d.id) == 30 and wc.ammo_of(d.id) == 1 and Arsenal.get_reserve(d.id, 1) == 20 and Arsenal.get_reserve(d.id) == 131 and wc.cur().ammo == 1)
	var before := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	wc.cd = 0.0
	wc._fire_shot(wc.cur())
	var shots := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and n.ammo == 1)
	check("strzał nabojem US: pocisk niesie typ i prędkość poddźwiękową", shots.size() > 0 and shots.size() > before - 1 and float(shots[0]._def.speed) < Ammo.SOUND_PX)
	wc.cycle_ammo()                       # BZ pusty → pomijany, wraca PS
	check("Z pomija pusty typ (BZ 0) i wraca do PS", wc.next_ammo_of(d.id) == 0)
	await wait(d.full_reload_time() + 0.4)
	wc.state = Controller.State.READY
	# prasa elaboracyjna (1.7.354): breneka się zamawia (taniej), partia przychodzi po udanej misji — ława amunicji już nie sprzedaje; amunicja
	# specjalna przeżywa reset misji
	var bank0: int = Scrap.bank
	var loot0: int = Scrap.loot
	var orders0: Array = Scrap.orders.duplicate()
	var station_state := await _station_begin("press_bench")
	Scrap.bank = 1000
	Scrap.loot = 0
	Scrap.orders.clear()
	Arsenal.set_reserve(Weapons.SRUT8, 0, 1)
	var ores: Array = []
	var ocb := func(k: String, ok: bool, reason: String) -> void: ores.append(reason)
	Scrap.order_result.connect(ocb)
	Scrap.request_buy_supply("ammo_slug")                          # ława: odmowa (invalid), złom bez zmian
	Scrap.request_order("ammo_slug")
	await frames(2)
	var waiting := Arsenal.get_reserve(Weapons.SRUT8, 1)
	var bank_after := Scrap.bank
	Scrap.bank_loot(0)                                             # udana misja: partia z prasy trafia do zapasu
	await frames(2)
	var bought := Arsenal.get_reserve(Weapons.SRUT8, 1)
	Arsenal.reset_mission()
	await frames(2)
	check("prasa: breneka zamówiona za %d (sklep %d), przed misją w zapasie %d, po udanej misji %d (PELLET-8 i SPREAD-12: %d), kolejka pusta, po resecie zostaje (%d)" % [
		Scrap.press_price("ammo_slug"), Throwables.price_of("ammo_slug"), waiting, bought, Arsenal.get_reserve(Weapons.SPREAD12, 1), Arsenal.get_reserve(Weapons.SRUT8, 1)],
		ores == ["ok"] and waiting == 0 and bank_after == 1000 - Scrap.press_price("ammo_slug") and Scrap.press_price("ammo_slug") < Throwables.price_of("ammo_slug")
		and bought == Throwables.box_of("ammo_slug") and Arsenal.get_reserve(Weapons.SPREAD12, 1) == bought and Arsenal.get_reserve(Weapons.SRUT8, 1) == bought and Scrap.orders.is_empty())
	ores.clear()
	for i in Scrap.PRESS_SLOTS:
		await wait(0.36)
		Scrap.request_order("ammo_slug")                          # 10 + 3 × 10 = 40 = max
	Scrap.request_order("ammo_mag12")                              # prasa pełna
	await frames(2)
	check("prasa: %d partie naraz, kolejna odrzucona (%s)" % [Scrap.PRESS_SLOTS, str(ores)], ores == ["ok", "ok", "ok", "busy"] and Scrap.orders.size() == Scrap.PRESS_SLOTS)
	Scrap.orders.clear()
	ores.clear()
	Arsenal.set_reserve(Weapons.SRUT8, 0, 1)
	Arsenal.stock["ammo_slug"] = 40
	Scrap.request_order("ammo_slug")                               # zapas pełny — nie ma gdzie przyjąć partii
	await frames(2)
	Scrap.order_result.disconnect(ocb)
	check("prasa: przy pełnym zapasie zamówienie odrzucone (%s)" % str(ores), ores == ["full"])
	Arsenal.stock["ammo_slug"] = Throwables.box_of("ammo_slug")
	# ładunki gorące z prasy: mocniej, broń zużywa się dwa razy szybciej
	var m0d := Weapons.def_build(Weapons.M83, Weapons.build_of(0, 0))
	var mhot := Weapons.def_build(Weapons.M83, Weapons.build_of(Ammo.from_kind("ammo_hot762")["t"], 0))
	var s0d := Weapons.def_build(Weapons.SRUT8, Weapons.build_of(0, 0))
	var smag := Weapons.def_build(Weapons.SRUT8, Weapons.build_of(Ammo.from_kind("ammo_mag12")["t"], 0))
	check("prasa: 7.62 HOT obrażenia ×%.2f, zużycie ×%.1f; 12/70 MAG obrażenia ×%.2f, zużycie ×%.1f" % [mhot.damage / m0d.damage, mhot.wear / m0d.wear, smag.damage / s0d.damage, smag.wear / s0d.wear],
		is_equal_approx(mhot.damage, m0d.damage * 1.12) and is_equal_approx(mhot.wear, m0d.wear * 2.0) and is_equal_approx(smag.damage, s0d.damage * 1.15) and is_equal_approx(smag.wear, s0d.wear * 2.0))
	# panel prasy: same kafle amunicji specjalnej, przycisk „zamów partię” z ceną prasy, zapas w pudełkach; ława — same przedmioty
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	var ui_ok := false
	var ui_info := "brak panelu"
	if wui != null:
		wui.open("press")
		var kinds: Array = wui._supply_kinds()
		wui._sup_sel = kinds.find("ammo_slug")
		wui._refresh()
		var tile = wui._sup_tiles[wui._sup_sel]
		var vis_n: int = wui._sup_tiles.filter(func(t: Control) -> bool: return t.visible).size()
		var press_page: int = wui._page
		ui_info = "%d widocznych kafli, przycisk '%s', pasek %d/%d" % [vis_n, wui._s_action.text, tile.bar.have, tile.bar.maxn]
		var forty: int = Throwables.AMMO_ORDER.filter(func(k: String) -> bool: return String(Ammo.from_kind(k).get("cal", "")) == "40mm").size()
		ui_ok = vis_n == Throwables.AMMO_ORDER.size() - forty and press_page == 1 and wui._s_action.text.contains(str(Scrap.press_price("ammo_slug"))) and tile.bar.have == 1 and tile.bar.maxn == 4
		wui.close()
		# stół pirotechniczny (1.7.355): granaty, miny, ładunki i 40 mm; ława — same narzędzia
		wui.open("pyro")
		var pyro_kinds: Array = wui._sup_list().map(func(i: int) -> String: return String(wui._supply_kinds()[i]))
		wui.close()
		wui.open("bench")
		wui._set_page(1)
		wui._refresh()
		var bench_kinds: Array = wui._sup_list().map(func(i: int) -> String: return String(wui._supply_kinds()[i]))
		var bench_vis: Array = wui._sup_tiles.filter(func(t: Control) -> bool: return t.visible)
		ui_info += ", pirotechnika %s, ława %s" % [str(pyro_kinds), str(bench_kinds)]
		ui_ok = ui_ok and pyro_kinds.has("frag") and pyro_kinds.has("mine") and pyro_kinds.has("charge") and pyro_kinds.has("ammo_40buck") and not pyro_kinds.has("ammo_slug")
		ui_ok = ui_ok and bench_vis.size() == bench_kinds.size() and bench_kinds.all(func(k: String) -> bool: return String(Throwables.KINDS[k]["mode"]) == "use")
		ui_ok = ui_ok and bench_kinds.has("medkit") and bench_kinds.has(String(wui._supply_kinds()[wui._sup_sel]))
		# zakładka ARMS: kliknięcie wiersza części (sygnał pressed) przebudowuje listę, w tym kliknięty wiersz — bez zwalniania go w trakcie sygnału
		wui._set_page(0)
		wui._sel = 0
		wui._refresh()
		var rows: Array = wui._d_tiers.get_children().filter(func(n: Node) -> bool: return n is Button)
		var clicked := false
		if rows.size() > 2:
			(rows[2] as Button).pressed.emit()
			clicked = wui._opt == 2 and is_instance_valid(rows[2]) and wui._d_tiers.get_children().filter(func(n: Node) -> bool: return n is Button).size() == rows.size()
		check("warsztat ARMS: kliknięcie wiersza części wybiera ją i przebudowuje listę (kursor %d, wierszy %d)" % [wui._opt, rows.size()], clicked)
		# ława 3D (1.7.323): broń z częścią spod kursora, ta część świeci i wysuwa się z gniazda; na elemencie fabrycznym świecą fabryczne podzespoły.
		# Bez czekania na klatki — gracz testu nie stoi przy ławie, więc panel sam by się zamknął; klatkę ławy wołamy ręcznie.
		var ops: Array = wui._options(Weapons.M83)
		var st = wui._d_stage
		wui._opt = ops.find({"slot": "muzzle", "id": "m83_pbs1"})
		wui._refresh()
		st._process(0.5)
		var hl_names: Array = st._hl.map(func(h: Dictionary) -> String: return String((h["node"] as Node).name))
		var pulled: bool = not st._hl.is_empty() and ((st._hl[0]["node"] as Node3D).position - (st._hl[0]["base"] as Vector3)).x > 0.01
		check("ława 3D: M-83 z tłumikiem spod kursora, tłumik świeci i wysuwa się do przodu (%s)" % str(hl_names),
			st._model != null and hl_names.size() == 1 and String(hl_names[0]).begins_with("gunpart_m83_pbs1") and pulled)
		wui._opt = ops.find({"slot": "muzzle", "id": ""})
		wui._refresh()
		hl_names = st._hl.map(func(h: Dictionary) -> String: return String((h["node"] as Node).name))
		var no_part: bool = st._model.find_children("gunpart_*", "", false, false).filter(func(n: Node) -> bool: return String(n.name).contains("pbs1")).is_empty()
		check("ława 3D: fabryczny wylot spod kursora — świeci podzespół __muzzle, tłumika nie ma (%s)" % str(hl_names),
			hl_names.size() > 0 and hl_names.all(func(n: String) -> bool: return n.ends_with("__muzzle")) and no_part)
		wui.close()
	check("prasa, pirotechnika i ława: każde stanowisko ma swoje zaopatrzenie (%s)" % ui_info, ui_ok)
	# zapalniki (stół pirotechniczny): ustawienie drużyny, granat i ładunek biorą wybraną długość
	var fuses0: Dictionary = Scrap.fuses.duplicate()
	_station_move("pyro_bench")
	Scrap.request_fuse("frag", 0)
	Scrap.request_fuse("charge", 2)
	Scrap.request_fuse("smoke", 1)                                  # dymny nie ma wyboru — bez zmian
	Scrap.request_fuse("frag", 9)                                   # poza listą — odrzucone
	var gl := get_tree().get_first_node_in_group("level")
	var g_fuse := -1.0
	if gl != null:
		gl.spawn_grenade("frag", player.global_position + Vector2(0, -40), Vector2.ZERO, player.player_id)
		await frames(2)
		for g in gl.get_children():
			if g.get_script() != null and String(g.get_script().resource_path).ends_with("/grenade.gd") and String(g.kind) == "frag":
				g_fuse = float(g._data["fuse"])
				g.queue_free()
	check("zapalniki: odłamkowy %.1f s (granat w świecie %.1f s), ładunek %.1f s, dymny bez wyboru %.1f s, wybór drużyny %s" % [Scrap.fuse_of("frag"), g_fuse, Scrap.fuse_of("charge"), Scrap.fuse_of("smoke"), str(Scrap.fuses)],
		Scrap.fuse_of("frag") == 1.0 and is_equal_approx(g_fuse, 1.0) and Scrap.fuse_of("charge") == 15.0 and is_equal_approx(Scrap.fuse_of("smoke"), float(Throwables.KINDS["smoke"]["fuse"]))
		and not Scrap.fuses.has("smoke"))
	Scrap.request_fuse("frag", Throwables.fuse_default("frag"))
	check("zapalniki: powrót do fabrycznego zdejmuje wpis (%s)" % str(Scrap.fuses), not Scrap.fuses.has("frag") and Scrap.fuse_of("frag") == float(Throwables.KINDS["frag"]["fuse"]))
	Scrap.fuses = fuses0
	Scrap.bank = bank0
	Scrap.loot = loot0
	Scrap.orders = orders0
	for k in Throwables.AMMO_ORDER:
		Arsenal.stock[k] = 0
	equip(Weapons.M83)

## Naboje 40 mm (1.7.318): kartacz działa z bliska bez uzbrajania, oświetlający wyrzuca flarę na spadochronie, dymny stawia chmurę;
	await _station_end(station_state)


## elita upuszcza pudełko amunicji specjalnej do noszonej broni, a zrzut zaopatrzenia z amunicją dokłada całe pudełko.
func _t_ammo_40mm() -> void:
	var he := Weapons.def_ammo(Weapons.GNIEW4, 0)
	var bk := Weapons.def_ammo(Weapons.GNIEW4, 1)
	var il := Weapons.def_ammo(Weapons.GNIEW4, 2)
	var sm := Weapons.def_ammo(Weapons.GNIEW4, 3)
	check("40 mm: HE z wybuchem, kartacz %d śrucin bez wybuchu, oświetlający i dymny z ładunkiem (%s, %s)" % [bk.pellets, il.payload, sm.payload],
		he.blast_radius > 0.0 and bk.blast_radius == 0.0 and bk.pellets == 10 and bk.gravity == 0.0 and il.payload == "illum" and sm.payload == "smoke"
		and il.blast_radius == 0.0 and String(he.payload) == "")
	await _settle_player()
	# kartacz z 30 px: rani bez uzbrajania, bez wybuchu i bez hałasu detonacji
	var close := await dummy(30.0)
	NoiseMgr.calm()
	var duds0 := Projectile.dud_count
	var p0 := player.global_position + Vector2(8, -6)
	for dd in Weapons.pellet_dirs(bk, Vector2.RIGHT, 7, 0.0):
		var pb := Projectile.new()
		pb.launch(Weapons.GNIEW4, p0, dd, 1, true, 0.0, 1)
		get_tree().current_scene.add_child(pb)
	await wait(0.3)
	check("kartacz z 30 px: %.0f obrażeń, bez wybuchu (Uwaga %.1f) i bez „nieuzbrojonego”" % [dealt(close), NoiseMgr.level],
		dealt(close) >= 40.0 and NoiseMgr.level < 5.0 and Projectile.dud_count == duds0)
	free_dummies()
	await frames(2)
	# oświetlający stromo w górę: w szczycie toru flara na spadochronie, która opada powoli
	var fl0 := get_tree().get_nodes_in_group("flares").size()
	var pi := Projectile.new()
	pi.launch(Weapons.GNIEW4, p0, Vector2.from_angle(deg_to_rad(-80.0)), 1, true, 0.0, 2)
	get_tree().current_scene.add_child(pi)
	await wait(0.9)
	var chutes: Array = get_tree().get_nodes_in_group("flares").filter(func(f: Node) -> bool: return bool(f.get("chute")))
	var ok_ill := chutes.size() > 0 and get_tree().get_nodes_in_group("flares").size() > fl0
	var fall := 0.0
	var high := false
	if ok_ill:
		var f: Node2D = chutes[0]
		high = f.global_position.y < p0.y - 60.0
		var y0 := f.global_position.y
		await wait(1.0)
		fall = f.global_position.y - y0 if is_instance_valid(f) else 999.0
	check("oświetlający: flara na spadochronie w szczycie toru (wysoko: %s), opada %.0f px/s (≤ 30)" % [str(high), fall],
		ok_ill and high and fall > 0.0 and fall <= 30.0)
	for f in get_tree().get_nodes_in_group("flares"):
		if bool(f.get("chute")):
			f.queue_free()
	# dymny pod nogi: chmura dymu, bez wybuchu
	var sm0 := get_tree().get_nodes_in_group("smoke_clouds").size()
	NoiseMgr.calm()
	var ps := Projectile.new()
	ps.launch(Weapons.GNIEW4, p0, Vector2.from_angle(deg_to_rad(60.0)), 1, true, 0.0, 3)
	get_tree().current_scene.add_child(ps)
	await wait(0.5)
	check("dymny: chmura dymu w miejscu upadku (%d → %d), bez wybuchu (Uwaga %.1f)" % [sm0, get_tree().get_nodes_in_group("smoke_clouds").size(), NoiseMgr.level],
		get_tree().get_nodes_in_group("smoke_clouds").size() > sm0 and NoiseMgr.level < 5.0)
	for c in get_tree().get_nodes_in_group("smoke_clouds"):
		c.queue_free()
	await frames(2)
	# łup z elit: pudełko amunicji specjalnej do broni, którą ktoś nosi (M-83 → US albo BZ)
	equip(Weapons.M83)
	for k in Throwables.AMMO_ORDER:
		Arsenal.stock[k] = 0
	var picks := {}
	for i in 40:
		picks[Arsenal.pick_special_drop()] = true
	var only762 := true
	for k in picks:
		only762 = only762 and String(k) in ["ammo_us", "ammo_bz", "ammo_slug", "ammo_inc", "ammo_rub", "ammo_40buck", "ammo_40illum", "ammo_40smoke"]
	var carried := []
	for w in player.kit_primaries():
		carried.append(String(Weapons.def(w).caliber))
	var cal_ok := true
	for k in picks:
		cal_ok = cal_ok and carried.has(String(Ammo.from_kind(String(k)).get("cal", "?")))
	check("łup z elit: tylko amunicja specjalna do noszonych kalibrów (%s; noszone %s)" % [str(picks.keys()), str(carried)], only762 and cal_ok and picks.has("ammo_us"))
	var idx := Throwables.SHOP_ORDER.find("ammo_us")
	level.spawn_item("supply", idx, player.global_position + Vector2(0, -8))
	await wait(0.9)
	await _step_on_item("supply", idx)
	await wait(0.5)
	check("zrzut z amunicją US: +%d naboi (pudełko)" % Arsenal.get_throwable("ammo_us"), Arsenal.get_throwable("ammo_us") == Throwables.box_of("ammo_us"))
	for k in Throwables.AMMO_ORDER:
		Arsenal.stock[k] = 0
	free_dummies()
	await frames(2)

## Pracownia (WORKSHOP_PLAN.md W6a, 1.7.357): próbki do łupu misji (wipe zabiera, ekstrakcja do banku), części broni specjalnych tylko z badań
## (ława odmawia), badanie za próbki i złom, jedno na misję, gotowe po udanej misji; panel pracowni.
func _t_research() -> void:
	var station_state := await _station_begin("workshop")
	var bank0: int = Scrap.bank
	var loot0: int = Scrap.loot
	var smp0: int = Scrap.samples
	var res0: Array = Scrap.research.duplicate()
	var unl0: Dictionary = Scrap.unlocked.duplicate()
	var parts0: Dictionary = Scrap.parts.duplicate()
	Scrap.bank = 1000
	Scrap.loot = 0
	Scrap.samples = 0
	Scrap.samples_loot = 0
	Scrap.research.clear()
	Scrap.unlocked[Weapons.LR7] = true
	Scrap.unlocked.erase(Weapons.HKM9)
	for id in Parts.all_ids():
		if String(id).begins_with("lr7_"):
			Scrap.parts.erase(id)
	var pres: Array = []
	var pcb := func(id: String, ok: bool, reason: String) -> void: pres.append(reason)
	Scrap.part_result.connect(pcb)
	Scrap.request_part("lr7_cell")                                 # ława: część broni specjalnej — tylko z pracowni
	Scrap.part_result.disconnect(pcb)
	Scrap.add_samples(1)
	var in_loot: int = Scrap.samples_loot
	Scrap.reset_loot()                                             # wipe: próbki z misji przepadają
	var after_wipe: int = Scrap.samples_loot
	Scrap.add_samples(3)
	Scrap.bank_loot(0)
	await frames(2)
	check("pracownia: ława odmawia części LR-7 (%s); próbka w łupie %d, po wipe %d, po udanej misji w banku %d" % [str(pres), in_loot, after_wipe, Scrap.samples],
		pres == ["lab"] and in_loot == 1 and after_wipe == 0 and Scrap.samples == 3 and Scrap.samples_loot == 0)
	var rres: Array = []
	var rcb := func(id: String, ok: bool, reason: String) -> void: rres.append(reason)
	Scrap.research_result.connect(rcb)
	var lc: Vector2i = Scrap.research_cost("lr7_lens")
	var bank1: int = Scrap.bank
	_station_move("lab_bench")
	Scrap.request_research("lr7_lens")
	Scrap.request_research("lr7_cell")                             # miejsce jest (LAB_SLOTS 2), ale próbki poszły na soczewkę
	Scrap.request_research("m83_pbs1")                             # nie broń specjalna
	Scrap.request_research("hkm_tank")                             # broń niekupiona
	var queued: bool = Scrap.research.has("lr7_lens") and not Scrap.has_part("lr7_lens")
	Scrap.bank_loot(0)
	await frames(2)
	Scrap.request_research("lr7_coil")                             # próbek już nie ma
	Scrap.research_result.disconnect(rcb)
	check("pracownia: badanie soczewki LR-7 za %d próbki i %d złomu (%s), czeka do misji (%s), po udanej misji schemat (%s), część jeszcze nie (%s); bank %d → %d, próbki %d" % [
		lc.x, lc.y, str(rres), str(queued), str(Scrap.schematics.has("lr7_lens")), str(Scrap.has_part("lr7_lens")), bank1, Scrap.bank, Scrap.samples],
		rres == ["ok", "samples", "invalid", "locked", "samples"] and queued and Scrap.schematics.has("lr7_lens") and not Scrap.has_part("lr7_lens") and Scrap.research.is_empty()
		and Scrap.samples == 3 - lc.x and Scrap.bank == bank1 - lc.y and lc.x == 3)
	# zajęta pracownia: LAB_SLOTS badań naraz (do 1.7.454 jedno)
	var busy_res: Array = []
	var bcb := func(id: String, ok: bool, reason: String) -> void: busy_res.append(reason)
	Scrap.research_result.connect(bcb)
	var smp_busy: int = Scrap.samples
	Scrap.samples = 10
	Scrap.research = ["lr7_coil", "lr7_cell"]
	_station_move("lab_bench")
	Scrap.request_research("lr7_diffuser")
	Scrap.research_result.disconnect(bcb)
	check("pracownia: %d badania naraz, trzecie czeka (%s)" % [Scrap.LAB_SLOTS, str(busy_res)], Scrap.LAB_SLOTS == 2 and busy_res == ["busy"])
	Scrap.research = []
	Scrap.samples = smp_busy
	# tokarka (W6b, 1.7.358): schemat → część po udanej misji; bez schematu odmowa, LATHE_SLOTS zleceń naraz (od 1.7.455 dwa)
	var mres: Array = []
	var mcb := func(id: String, ok: bool, reason: String) -> void: mres.append(reason)
	Scrap.machining_result.connect(mcb)
	Scrap.schematics["lr7_cell"] = true
	var bank2: int = Scrap.bank
	_station_move("lathe_bench")
	Scrap.request_machining("lr7_coil")                            # brak schematu
	Scrap.request_machining("lr7_lens")
	Scrap.request_machining("lr7_cell")                            # drugie miejsce na tokarce
	Scrap.schematics["lr7_coil"] = true
	Scrap.request_machining("lr7_coil")                            # tokarka zajęta
	var on_lathe: bool = Scrap.lathe == ["lr7_lens", "lr7_cell"] and not Scrap.has_part("lr7_lens")
	var paid_lathe: int = Scrap.machine_price("lr7_lens") + Scrap.machine_price("lr7_cell")
	Scrap.bank_loot(0)
	await frames(2)
	Scrap.request_machining("lr7_lens")                            # już zrobiona
	Scrap.machining_result.disconnect(mcb)
	check("tokarka: soczewka ze schematu za %d złomu (%s), na tokarce do misji (%s), po misji odblokowana i schemat zużyty (%s, %s)" % [
		Scrap.machine_price("lr7_lens"), str(mres), str(on_lathe), str(Scrap.has_part("lr7_lens")), str(not Scrap.schematics.has("lr7_lens"))],
		mres == ["noschem", "ok", "ok", "busy", "owned"] and on_lathe and Scrap.has_part("lr7_lens") and Scrap.has_part("lr7_cell") and not Scrap.schematics.has("lr7_lens")
		and Scrap.lathe.is_empty() and Scrap.bank == bank2 - paid_lathe and Scrap.schematics.has("lr7_coil") and Scrap.job_paid.is_empty())
	Scrap.parts.erase("lr7_cell")
	Scrap.schematics.clear()
	# panel pracowni: same części broni specjalnej, M-83 bez badań
	var wui := get_tree().get_first_node_in_group("workshop_ui")
	var ui_ok := false
	var ui_info := "brak panelu"
	if wui != null:
		wui.open("lab")
		var lr: Array = wui._options(Weapons.LR7).map(func(o: Dictionary) -> String: return String(o["id"]))
		var m83: Array = wui._options(Weapons.M83)
		var title: String = wui._title.text
		wui.close()
		ui_info = "LR-7 %s, M-83 %d, tytuł %s" % [str(lr), m83.size(), title]
		ui_ok = lr.size() == Parts.of("lr7").size() and not lr.has("") and m83.is_empty() and title == tr("LAB")
	check("pracownia: panel (%s)" % ui_info, ui_ok)
	Scrap.bank = bank0
	Scrap.loot = loot0
	Scrap.samples = smp0
	Scrap.samples_loot = 0
	Scrap.research = res0
	Scrap.unlocked = unl0
	Scrap.parts = parts0
	# ostrze broni białej (szlifierka, W6b): zamach tępi, tępe rani słabiej (serwer), ostrzenie za czas bez złomu, panel tokarki
	var edge0: Dictionary = Profile.edge.duplicate()
	var rel0: int = Settings.reliability_idx
	Settings.reliability_idx = 1
	Profile.edge = {}
	wc.melee_id = Weapons.MACZETA
	wc._melee_resolve()
	var after_swing: float = Profile.edge_of("maczeta")
	Profile.edge["maczeta"] = 0.0
	var st: float = Profile.sharpen_time("maczeta")
	var lt_ok := false
	var lt_info := "brak panelu"
	if wui != null:
		wui.open("lathe")
		var lm: Array = wui._options(Weapons.MACZETA).map(func(o: Dictionary) -> String: return String(o["id"]))
		var ll: Array = wui._options(Weapons.LR7).map(func(o: Dictionary) -> String: return String(o["id"]))
		wui._start_clean(Weapons.MACZETA)
		wui.tick_clean(st + 0.1)
		lt_info = "maczeta %s, LR-7 %d części, ostrze po szlifierce %.0f %%" % [str(lm), ll.size(), Profile.edge_of("maczeta")]
		lt_ok = lm == ["sharpen"] and ll.size() == Parts.of("lr7").size() and Profile.edge_of("maczeta") == 100.0
		wui.close()
	check("ostrze: zamach −%.1f %% (%.1f), tępa maczeta rani ×%.2f, ostrzenie %.0f s (%s)" % [Profile.EDGE_WEAR, after_swing, Profile.edge_mult(0.0), st, lt_info],
		is_equal_approx(after_swing, 100.0 - Profile.EDGE_WEAR) and is_equal_approx(Profile.edge_mult(0.0), Profile.EDGE_MIN) and Profile.edge_mult(100.0) == 1.0
		and is_equal_approx(st, 10.0 * Profile.EDGE_STEP) and lt_ok)
	Profile.edge = edge0
	Settings.reliability_idx = rel0

## Masa ekwipunku (WORKSHOP_PLAN.md W5, 1.7.356): masa broni z częściami, zestaw startowy = punkt odniesienia (mnożniki 1), ciężki zestaw biegnie
	await _station_end(station_state)


## głośniej i wolniej, części zmieniają masę, obsługa klasyczna i boty bez zmian.
func _t_mass() -> void:
	var real0: bool = Settings.realistic_handling
	var lo0: Array = wc.loadout.duplicate()
	var mel0: int = wc.melee_id
	Settings.realistic_handling = true
	await clear_fits()
	wc.loadout.assign([Weapons.M83, Weapons.SPREAD12, Weapons.P64])
	wc.melee_id = Weapons.MACZETA
	var ref: float = Controller.mass_ref()
	var start_ok: bool = is_equal_approx(wc.kit_mass(), ref) and is_equal_approx(wc.mass_noise_mult(), 1.0) and is_equal_approx(wc.mass_speed_mult(), 1.0)
	check("masa: zestaw startowy %.2f kg = punkt odniesienia (hałas biegu ×%.2f, tempo ×%.2f)" % [wc.kit_mass(), wc.mass_noise_mult(), wc.mass_speed_mult()], start_ok and ref > 8.0 and ref < 12.0)
	await fit_player(Weapons.M83, ["m83_drum75"])
	var with_drum: float = wc.kit_mass()
	check("masa: bęben RPK dokłada %.2f kg do ekwipunku (masa M-83 %.2f kg)" % [with_drum - ref, wc.def_of(Weapons.M83).mass], is_equal_approx(with_drum - ref, 1.6))
	await clear_fits()
	wc.loadout.assign([Weapons.HKM9, Weapons.LR7, Weapons.P64])
	var heavy: float = wc.kit_mass()
	var hn: float = wc.mass_noise_mult()
	var hs: float = wc.mass_speed_mult()
	check("masa: HKM-9 + LR-7 = %.1f kg — bieg głośniej ×%.2f i wolniej ×%.2f" % [heavy, hn, hs],
		is_equal_approx(hn, clampf(1.0 + Controller.MASS_NOISE * (heavy - ref), 0.8, 1.5)) and hn > 1.2 and hs < 0.95 and hs >= Controller.MASS_SPEED_RANGE.x)
	Settings.realistic_handling = false
	check("masa: obsługa klasyczna — bez wpływu (×%.2f, ×%.2f)" % [wc.mass_noise_mult(), wc.mass_speed_mult()], wc.mass_noise_mult() == 1.0 and wc.mass_speed_mult() == 1.0)
	Settings.realistic_handling = real0
	wc.loadout.assign(lo0)
	wc.melee_id = mel0
	equip(Weapons.M83)
	await _settle_player()

## Alternatywy w gniazdach (WORKSHOP_PLAN.md W3, 1.7.351): serwer liczy ogień ciągły i ciosy z częściami gracza odblokowanymi przez drużynę
## (wcześniej ogień ciągły brał fabryczną broń), nowe części P-83, LR-7 i HKM-9 zmieniają zachowanie, dysza żelowa zostawia dłuższy ogień.
func _t_parts_alt() -> void:
	await clear_fits()
	var h0 := Weapons.base_def(Weapons.HKM9)
	await fit_player(Weapons.HKM9, ["hkm_mix", "hkm_gel"])
	var sd: WeaponDef = wc.server_def(Weapons.HKM9)
	check("serwer: HKM-9 z częściami gracza — obrażenia ×%.2f (gorąca mieszanka), ogień na podłodze %.1f s co %.2f s, zasięg ×%.2f (dysza żelowa)" % [
		sd.damage / h0.damage, sd.patch_life, sd.patch_every, sd.range_px / h0.range_px],
		is_equal_approx(sd.damage, h0.damage * 1.25) and is_equal_approx(sd.patch_life, h0.patch_life * 2.5) and is_equal_approx(sd.patch_every, h0.patch_every * 0.5)
		and is_equal_approx(sd.range_px, h0.range_px * 0.75))
	Scrap.parts.erase("hkm_mix")                                       # gracz ma ją w montażu, ale drużyna jej nie ma (np. inny host)
	var sd2: WeaponDef = wc.server_def(Weapons.HKM9)
	check("serwer: część, której drużyna nie ma, nie działa (obrażenia %.1f = fabryczne %.1f)" % [sd2.damage, h0.damage], is_equal_approx(sd2.damage, h0.damage) and is_equal_approx(sd2.patch_life, h0.patch_life * 2.5))
	# dysza żelowa: ogień na podłodze z płomienia pali się dłużej
	var lvl := get_tree().get_first_node_in_group("level")
	var patch_ok := false
	var patch_info := "brak poziomu"
	if lvl != null:
		for fp in get_tree().get_nodes_in_group("fire_patches"):
			fp.queue_free()
		await frames(1)
		var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
		wc._drop_fire_patch(sd2, space, player.global_position + Vector2(0, -10), Vector2(1, 0))
		await frames(2)
		var patches: Array = get_tree().get_nodes_in_group("fire_patches").filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
		patch_info = "%d ognia, życie %s" % [patches.size(), str(patches.map(func(p: Node) -> float: return float(p.life)))]
		patch_ok = patches.size() == 1 and absf(float(patches[0].life) - h0.patch_life * 2.5) < 0.5          # życie może już odliczać
		for fp in patches:
			fp.queue_free()
	check("dysza żelowa: ogień na podłodze pali się %.0f s (%s)" % [h0.patch_life * 2.5, patch_info], patch_ok)
	# LR-7: rozpraszacz — więcej przebić, krótsza i słabsza wiązka; P-83: długa lufa i kabura-kolba w nowym gnieździe
	var l0 := Weapons.base_def(Weapons.LR7)
	var ld := pdef(Weapons.LR7, ["lr7_diffuser"])
	var p0 := Weapons.base_def(Weapons.P64)
	var ps := pdef(Weapons.P64, ["p64_stock", "p64_long"])
	check("LR-7 rozpraszacz: przebija %d (było %d), zasięg ×%.1f; P-83 kabura-kolba i długa lufa: gniazda %s, podrzut ×%.2f, dobycie +%.2f s, spadek obrażeń od %.0f px" % [
		ld.pierce, l0.pierce, ld.range_px / l0.range_px, str(Parts.slots_of("p64")), ps.bloom_per_shot / p0.bloom_per_shot, ps.draw_time - p0.draw_time, ps.falloff_start],
		ld.pierce == l0.pierce + 2 and is_equal_approx(ld.range_px, l0.range_px * 0.6) and Parts.slots_of("p64") == ["feed", "barrel", "muzzle", "stock"]
		and is_equal_approx(ps.bloom_per_shot, p0.bloom_per_shot * 0.55) and is_equal_approx(ps.draw_time - p0.draw_time, 0.5) and ps.falloff_start == p0.falloff_start + 40.0)
	# wybór w gnieździe: wylot LR-7 i HKM-9 ma teraz dwie części, lufa P-83 — dwie
	check("wybór w gniazdach: LR-7 wylot %d, HKM-9 wylot %d, P-83 lufa %d części" % [Parts.in_slot("lr7", "muzzle").size(), Parts.in_slot("hkm9", "muzzle").size(), Parts.in_slot("p64", "barrel").size()],
		Parts.in_slot("lr7", "muzzle").size() == 2 and Parts.in_slot("hkm9", "muzzle").size() == 2 and Parts.in_slot("p64", "barrel").size() == 2)
	# część 2 (1.7.352): slam-fire robi z PELLET-8 broń automatyczną (pole bool przez "set"), nowe gniazda lufy PELLET-8 i WRATH-4, obcięta lufa SPREAD-12
	var s0 := Weapons.base_def(Weapons.SRUT8)
	var ss := pdef(Weapons.SRUT8, ["s8_slam", "s8_long"])
	var sw0 := Weapons.base_def(Weapons.SPREAD12)
	var sw := pdef(Weapons.SPREAD12, ["sp12_sawn"])
	var g0 := Weapons.base_def(Weapons.GNIEW4)
	var gs := pdef(Weapons.GNIEW4, ["g4_short"])
	var r0 := Weapons.base_def(Weapons.WIDMO1)
	var ro := pdef(Weapons.WIDMO1, ["w1_over"])
	check("część 2: PELLET-8 slam-fire auto %s (fabryczny %s), rytm ×%.2f, gniazda %s; SPREAD-12 obcięta lufa stożek ×%.2f; WRATH-4 krótka rura dobycie ×%.2f, gniazda %s; SPECTER-1 przeładowanie ×%.2f obrażeń" % [
		str(ss.auto), str(s0.auto), ss.cooldown / s0.cooldown, str(Parts.slots_of("srut8")), sw.spread_deg / sw0.spread_deg, gs.draw_time / g0.draw_time, str(Parts.slots_of("gniew4")), ro.damage / r0.damage],
		ss.auto and not s0.auto and is_equal_approx(ss.cooldown, s0.cooldown * 0.7) and ss.spread_deg < s0.spread_deg and Parts.slots_of("srut8") == ["feed", "barrel", "action", "stock"]
		and is_equal_approx(sw.spread_deg, sw0.spread_deg * 1.35) and is_equal_approx(gs.draw_time, g0.draw_time * 0.7) and Parts.slots_of("gniew4") == ["feed", "barrel", "special"]
		and is_equal_approx(ro.damage, r0.damage * 1.3) and ro.charge_time > r0.charge_time and not Weapons.base_def(Weapons.SRUT8).auto)
	await clear_fits()

## Części broni (1.7.319, GUNSMITH_PLAN.md etap 2a): kod `fit` w obie strony, montaż gracza (wybór, samomontaż, element fabryczny),
## broń gracza w kontrolerze i w sieci (player.fits), serwer odrzuca części, których drużyna nie ma, migracja starych poziomów ulepszeń.
func _t_parts() -> void:
	await clear_fits()
	var key := "m83"
	var code := Parts.encode_ids(key, ["m83_drum75", "m83_short", "m83_pbs1", "m83_akms"])
	var back := Parts.decode(key, code)
	check("kod części: w obie strony (%s)" % str(back), back.size() == 4 and back.has("m83_drum75") and back.has("m83_short") and back.has("m83_pbs1") and back.has("m83_akms"))
	check("kod części: dwie części w jednym gnieździe — zostaje jedna (ostatnia)", Parts.decode(key, Parts.encode_ids(key, ["m83_rpk40", "m83_drum75"])) == ["m83_drum75"])
	var owned := {"m83_pbs1": true}
	check("serwer: części, których drużyna nie ma, wypadają z kodu (%s)" % str(Parts.decode(key, Parts.sanitize(key, code, owned))), Parts.decode(key, Parts.sanitize(key, code, owned)) == ["m83_pbs1"])
	check("każda broń mieści się w kodzie (≤ %d gniazd po 2 bity, ≤ %d części w gnieździe)" % [8, Parts.MAX_PER_SLOT],
		Parts.PARTS.keys().all(func(k: String) -> bool: return Parts.slots_of(k).size() <= 8))
	# montaż: samomontaż pierwszej odblokowanej części, wybór gracza, element fabryczny
	Scrap.parts["m83_rpk40"] = true
	Scrap.parts["m83_drum75"] = true
	check("nowe odblokowanie nie montuje się bez wyboru gracza", Profile.fitted(key, "feed") == "")
	Profile.set_fit(key, "feed", "m83_drum75")
	check("wybór gracza: bęben 75 (%s)" % Profile.fitted(key, "feed"), Profile.fitted(key, "feed") == "m83_drum75")
	Profile.set_fit(key, "feed", "")
	check("element fabryczny wybrany świadomie wygrywa z samomontażem", Profile.fitted(key, "feed") == "")
	Scrap.parts.erase("m83_drum75")
	Profile.set_fit(key, "feed", "m83_drum75")
	check("część, której drużyna nie ma, nie montuje się (%s)" % Profile.fitted(key, "feed"), Profile.fitted(key, "feed") == "")
	await clear_fits()
	# broń gracza: kontroler buduje definicję z player.fits, magazynek po przeładowaniu ma pojemność z części
	await fit_player(Weapons.M83, ["m83_drum75", "m83_pbs1"])
	var d := equip(Weapons.M83, false)
	check("player.fits niesie montaż (kod %d) i kontroler go używa (magazynek %d, tłumik %s)" % [player.fits[Weapons.M83], wc.cur().mag, str(wc.cur().suppressor > 0.0)],
		player.fits[Weapons.M83] == Profile.fit_code(Weapons.M83) and wc.cur().mag == 75 and wc.cur().suppressor > 0.0 and wc.cur().build == Weapons.build_of(0, Profile.fit_code(Weapons.M83)))
	Arsenal.set_reserve(d.id, 200)
	wc.mags[d.id] = 0
	wc.try_reload()
	await wait(wc.cur().full_reload_time() + 0.4)
	check("przeładowanie bębna: 75 naboi (%d), serwer przyjął prośbę większą niż fabryczny magazynek" % wc.mag_of(d.id), wc.mag_of(d.id) == 75)
	var before: int = NoiseMgr.level
	wc.cd = 0.0
	wc._fire_shot(wc.cur())
	var shots := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and n.weapon == Weapons.M83)
	check("strzał niesie części gracza: pocisk z kodem build (%d)" % (shots.back().build if not shots.is_empty() else -1),
		not shots.is_empty() and Weapons.fit_of_build(int(shots.back().build)) == Profile.fit_code(Weapons.M83))
	await clear_fits()
	equip(Weapons.M83)
	check("bez części broń gracza jest fabryczna (magazynek %d)" % wc.cur().mag, wc.cur().mag == Weapons.def(Weapons.M83).mag and player.fits[Weapons.M83] == 0)
	# migracja zapisu sprzed 1.7.319: poziom 2 M-83 = magazynek RPK i lufa RPK, samomontaż daje tę samą broń co dawniej
	Scrap.migrate_levels({Weapons.M83: 2, Weapons.P64: 3})
	Profile.migrate_fits()
	var mig := Weapons.def_build(Weapons.M83, Weapons.build_of(0, Profile.fit_code(Weapons.M83)))
	check("migracja poziomów: M-83 poz. 2 → RPK 40 + lufa RPK (magazynek %d), P-83 poz. 3 → 3 części (%d)" % [mig.mag, Scrap.parts_owned(Weapons.P64)],
		Scrap.has_part("m83_rpk40") and Scrap.has_part("m83_rpkbar") and not Scrap.has_part("m83_pbs1") and mig.mag == 40 and Scrap.parts_owned(Weapons.P64) == 3)
	await clear_fits()
	equip(Weapons.M83)
	# model 3D z częściami (1.7.320, gun_model.gd): zastąpione podzespoły znikają, tłumik siedzi na końcu założonej lufy
	const Char3D := preload("res://scripts/char3d.gd")
	var with_model := ["m83_rpk40", "m83_drum75", "m83_rpkbar", "m83_short", "m83_pbs1", "m83_hider", "m83_akms", "p64_supp", "sp12_drum30", "sp12_box8", "sp12_ported",
		"s8_tube", "s8_carrier", "lr7_cell", "lr7_lens", "hkm_tank", "hkm_nozzle", "g4_loader", "f6_belt", "f6_seeker", "w1_cap", "w1_fast", "c6_twin", "c6_bands",
		"c6_tether", "mc_long", "mc_exec", "kf_heavy", "kf_seismic",
		"p64_ext", "p64_long", "p64_stock", "s8_pump", "s8_long", "lr7_diffuser", "hkm_gel", "w1_rails", "mc_short"]          # od 1.7.456
	# każdy podzespół, który część zastępuje, istnieje w modelu broni bazowej (inaczej część nałożyłaby się na fabryczny element)
	var bad_hides: Array = []
	for pid in with_model:
		var wkey := String(Parts.get_part(pid)["weapon"])
		var base_n := GunModel.build(wkey, [], Vector3.ZERO)
		var comps: Array = base_n.find_children("*__*", "MeshInstance3D", true, false).map(func(n: Node) -> String: return String(n.name).get_slice("__", 1))
		for h in GunModel.part_info(pid).get("hides", []):
			if not comps.has(String(h)):
				bad_hides.append("%s→%s" % [pid, h])
		base_n.free()
	check("części zastępują istniejące podzespoły broni bazowej (%s)" % str(bad_hides), bad_hides.is_empty())
	var missing: Array = with_model.filter(func(id: String) -> bool: return not GunModel.has_model(id))
	check("modele części: %d części ma GLB i opis mocowania (brak: %s)" % [with_model.size(), str(missing)], missing.is_empty())
	var bm: Vector3 = Char3D.gun_info("m83")["muzzle"]
	var ids := ["m83_drum75", "m83_rpkbar", "m83_pbs1", "m83_akms"]
	var gm := GunModel.build("m83", ids, bm)
	var names: Array = gm.find_children("*", "MeshInstance3D", true, false).map(func(n: Node) -> String: return String(n.name))
	var gone := not names.any(func(n: String) -> bool: return n.ends_with("__mag") or n.ends_with("__front") or n.ends_with("__muzzle") or n.ends_with("__stock"))
	var pbs: Node3D = null
	for n in gm.get_children():
		if String(n.name).begins_with("gunpart_m83_pbs1"):
			pbs = n
	var at_barrel := pbs != null and pbs.position.is_equal_approx(GunModel.barrel_muzzle(bm, ids)) and GunModel.barrel_muzzle(bm, ids).x > bm.x + 0.05
	check("model M-83 z bębnem, lufą RPK, PBS-1 i kolbą AKMS: fabryczne podzespoły zniknęły (%s), PBS-1 na końcu lufy RPK (%s), wylot pocisku %.2f m dalej" % [str(gone), str(at_barrel), GunModel.muzzle(bm, ids).x - bm.x],
		gone and at_barrel and GunModel.muzzle(bm, ids).x > GunModel.barrel_muzzle(bm, ids).x)
	var plain := GunModel.build("m83", [], bm)
	var pn: Array = plain.find_children("*__*", "MeshInstance3D", true, false).map(func(n: Node) -> String: return String(n.name).get_slice("__", 1))
	check("model fabryczny M-83 ma podzespoły do podmiany (%s)" % str(pn), pn.has("mag") and pn.has("front") and pn.has("muzzle") and pn.has("stock"))
	gm.free()
	plain.free()

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

## Czeka, aż gracz stoi (na podłodze, bez prędkości i odrzutu) — poprzednie testy (broń z odrzutem) mogą go jeszcze przesuwać,
## a testy liczone względem pozycji gracza (manekiny co 40 px) są wtedy zależne od tempa klatek maszyny.
func _settle_player() -> void:
	for i in 120:
		if player.is_on_floor() and player.velocity.length() < 2.0 and absf(float(player.get("_kick"))) < 1.0:
			break
		await frames(1)
	player.velocity = Vector2.ZERO
	player.aim_dir = Vector2.RIGHT
	await frames(2)

func _t_pierce_beam_rail() -> void:
	await _settle_player()
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
	var detail: Array = []
	for t in targets:
		detail.append("x%.0f:%.0f" % [t.global_position.x, dealt(t)])
	check("LR-7: promień przebija 2 cele (pierce 1), trzeci nietknięty", hit_count == 2 and dealt(targets[2]) == 0.0,
		"trafionych %d; gracz x=%.0f aim=%s; cele (x:obrażenia) %s" % [hit_count, player.global_position.x, str(player.aim_dir.snapped(Vector2(0.01, 0.01))), ", ".join(detail)])
	check("LR-7: bateria spada o tyknięcia", wc.mag_of(d.id) < mag0 and mag0 - wc.mag_of(d.id) <= 8, "zużyto %d" % (mag0 - wc.mag_of(d.id)))
	check("LR-7: zimna wiązka cicha (szum/tyk ≤ 0,3), rozgrzana głośniejsza (%.2f → %.2f)" % [d.noise(0.0), d.n_max], d.noise(0.0) <= 0.3 and d.n_max >= 0.7)
	for t in targets:
		t.hp = t._max_hp
	# szyna: ładowanie 1,2 s, puszczenie = strzał, przebija wszystkich
	var r := equip(Weapons.WIDMO1)
	wc.sim_fire = true
	await wait(0.5)
	check("SPECTER-1: w trakcie ładowania stan CHARGE", wc.state == Controller.State.CHARGE, "stan %d ładunek %.2f" % [wc.state, wc.charge])
	await wait(1.0)
	wc.sim_fire = false
	await wait(0.4)
	var all_hit := true
	for t in targets:
		all_hit = all_hit and absf(dealt(t) - 150.0) < 0.01
	check("SPECTER-1: naładowany strzał przebija wszystkich za 150", all_hit, "%s" % str(targets.map(func(t): return snappedf(dealt(t), 0.1))))
	check("SPECTER-1: magazynek −1", wc.mag_of(r.id) == r.mag - 1)
	check("SPECTER-1: najgłośniejsza broń (≥ 14 Uwagi)", NoiseMgr.last_noise_amount >= 14.0 or NoiseMgr.level >= 14.0, "ostatni %.1f" % NoiseMgr.last_noise_amount)
	# przedwczesne puszczenie anuluje bez kosztu
	equip(Weapons.WIDMO1)
	for t in targets:
		t.hp = t._max_hp
	wc.sim_fire = true
	await wait(0.4)
	wc.sim_fire = false
	await wait(0.2)
	check("SPECTER-1: puszczenie przed końcem ładowania anuluje (0 obrażeń, 0 kosztu)", dealt(targets[0]) == 0.0 and wc.mag_of(Weapons.WIDMO1) == r.mag)
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
	check("WRATH-4: trafienie bezpośrednie + wybuch (≥ 80)", dealt(a) >= 80.0, "%.1f" % dealt(a))
	check("WRATH-4: wybuch rani sąsiada w promieniu 3 m", dealt(b) >= 30.0, "%.1f" % dealt(b))
	check("WRATH-4: poza promieniem nietknięty", dealt(c) == 0.0)
	check("WRATH-4: wybuch to hałas (≥ 15 Uwagi)", NoiseMgr.level >= 15.0, "uwaga %.1f" % NoiseMgr.level)
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
	check("FALCON-6: rakiety naprowadzają się na cel poza osią", dealt(e) >= 7.0, "%.1f" % dealt(e))
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
	# częściowe: bierze tylko brakujące (przytrzymane [R] — przeładowanie taktyczne, od 1.7.326 krótkie [R] upuszcza magazynek z resztkami)
	wc.sim_reload_hold = true
	for i in 5:
		wc.cd = 0.0
		wc._fire_shot(d)
	var r1 := Arsenal.get_reserve(d.id)
	wc.try_reload()
	await wait(d.reload_time + Controller.TAC_EXTRA + 0.4)
	check("przeładowanie częściowe: brakujące 5 + nabój w komorze (31, zapas −6)", wc.mag_of(d.id) == 31 and Arsenal.get_reserve(d.id) == r1 - 6, "mag %d zapas %d→%d" % [wc.mag_of(d.id), r1, Arsenal.get_reserve(d.id)])
	# brak zapasu
	Arsenal.set_reserve(d.id, 0)
	for i in 3:
		wc.cd = 0.0
		wc._fire_shot(d)
	var started: bool = wc.try_reload()
	check("brak zapasu: przeładowanie się nie zaczyna", not started and wc.state == Controller.State.READY)
	# anulowanie zmianą broni nie kosztuje naboi (magazynek: 31 = 30 + nabój w komorze, minus 3 strzały = 28)
	Arsenal.set_reserve(d.id, 100)
	wc.try_reload()
	await wait(0.4)
	wc.select_slot(2)
	await wait(0.2)
	check("zmiana broni w trakcie przeładowania anuluje je bez kosztu", Arsenal.get_reserve(d.id) == 100 and wc.mag_of(d.id) == 28, "zapas %d mag %d" % [Arsenal.get_reserve(d.id), wc.mag_of(d.id)])
	wc.sim_reload_hold = false
	wc.select_slot(0)
	await wait(0.6)
	# strzelba: nabój po naboju, przerywane strzałem
	var s := equip(Weapons.SRUT8, false)
	wc.mags[s.id] = 2
	Arsenal.set_reserve(s.id, 24)
	wc.try_reload()
	await wait(s.reload_time * 3.0 + 0.3)
	check("PELLET-8: ładowanie po 1 naboju (2→5 po ~3 krokach)", wc.mag_of(s.id) >= 4 and wc.mag_of(s.id) <= 6, "mag %d" % wc.mag_of(s.id))
	var mag_before: int = wc.mag_of(s.id)
	wc.sim_press = true
	await frames(3)
	check("PELLET-8: strzał przerywa ładowanie", wc.state != Controller.State.RELOAD and wc.mag_of(s.id) <= mag_before, "stan %d mag %d→%d" % [wc.state, mag_before, wc.mag_of(s.id)])
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
## Znajdźka pod nogami gracza bez losowego podskoku: znos w bok (±40 px/s przez ok. 0,5 s, losowany z nazwy węzła, czyli z licznika
## wcześniejszych przedmiotów) sięga 20 px, a promień podniesienia to 18 px — test, który czeka na samo podniesienie, padał losowo.
func _drop_still(kind: String, arg: int, pos: Vector2, rounds := 0) -> void:
	level.spawn_item(kind, arg, pos, rounds)
	var item := level.get_node_or_null("Item%d" % level._pickup_serial)
	if item != null:
		item._vel = Vector2.ZERO

func _step_on_item(kind: String, arg: int) -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.kind == kind and p.arg == arg and not p.is_queued_for_deletion():
			player.global_position = p.global_position
	await frames(2)

## Kompensacja opóźnienia (lag_comp.gd): historia pozycji, odcinek vs prostokąt, trafienie w przeszłość.
func _t_lag() -> void:
	print("--- kompensacja opóźnienia")
	var e: Node = await dummy(100.0)
	var t0 := LagComp.now()
	var x1: float = e.global_position.x
	var y1: float = e.global_position.y
	e._hist.clear()
	e._hist.append(Vector3(t0 - 0.2, x1 - 20.0, y1))
	e._hist.append(Vector3(t0, x1, y1))
	var old_rect: Rect2 = e.lag_rect(t0 - 0.2)
	check("lag_rect: 0,2 s temu wróg stał 20 px bliżej", absf(old_rect.get_center().x - (x1 - 20.0)) < 1.5, str(old_rect))
	var mid: Rect2 = e.lag_rect(t0 - 0.1)
	check("lag_rect: w połowie interpolacja (−10 px)", absf(mid.get_center().x - (x1 - 10.0)) < 1.5, str(mid))
	var from := Vector2(x1 - 60.0, y1 - 7.0)
	var stop := from + Vector2(40.0, 0.0)        # kończy się w x1−20: dotyka dawnej pozycji, nie obecnej (lewa krawędź x1−6)
	check("odcinek nie trafia w obecną pozycję", LagComp.enemy_hit(from, stop, t0, []).is_empty())
	var past := LagComp.enemy_hit(from, stop, t0 - 0.2, [])
	check("ten sam odcinek trafia wroga sprzed 0,2 s", not past.is_empty() and past["node"] == e, str(past))
	check("seg_rect: poza prostokątem", LagComp.seg_rect(Vector2(0, 0), Vector2(5, 0), Rect2(10, -2, 4, 4)).is_empty())
	check("seg_rect: punkt wejścia", absf(float(LagComp.seg_rect(Vector2(0, 0), Vector2(20, 0), Rect2(10, -2, 4, 4)).get("pos", Vector2.ZERO).x) - 10.0) < 0.01)
	check("rewind_for: host i nieznany peer = 0", LagComp.rewind_for(1) == 0.0 and LagComp.rewind_for(99) == 0.0)
	e.queue_free()

func _t_pickups() -> void:
	Arsenal.reset_mission()
	await frames(2)
	free_dummies()
	var d := equip(Weapons.M83, false)
	Arsenal.set_reserve(d.id, 50)
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
	Arsenal.set_reserve(Weapons.SRUT8, 0)
	level.spawn_item("weapon", Weapons.SRUT8, player.global_position + Vector2(0, -2))
	await wait(0.9)
	await _step_on_item("weapon", Weapons.SRUT8)
	await wait(0.2)
	check("broń na ziemi jest w zasięgu E", wc.nearby_weapon_item() != null)
	# [H] przy broni = oględziny (nie rzuca flary i nic nie bierze), drugie [H] zamyka; [E] bierze broń
	var flares0: int = NoiseMgr.flares
	Input.action_press("inspect_weapon")
	await wait(0.12)
	Input.action_release("inspect_weapon")
	await wait(0.12)
	check("H przy broni otwiera oględziny: bez flary i bez zamiany", wc.inspect_item != null and NoiseMgr.flares == flares0 and wc.loadout[0] == old)
	Input.action_press("inspect_weapon")
	await wait(0.12)
	Input.action_release("inspect_weapon")
	await wait(0.12)
	check("drugie H zamyka oględziny", wc.inspect_item == null and wc.loadout[0] == old)
	Input.action_press("interact")
	await wait(0.12)
	Input.action_release("interact")
	await wait(0.6)
	check("podniesienie: PELLET-8 w slocie, stara broń porzucona", wc.loadout[0] == Weapons.SRUT8 and wc.loadout.count(old) == 0)
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
	# 6. SPECTER-1: ładowanie, potem strzał
	d = equip(Weapons.WIDMO1)
	wc.sim_fire = true
	await wait(1.0)
	await _snap(out_dir, "06_widmo_charge", 0)
	await wait(0.5)
	wc.sim_fire = false
	await _snap(out_dir, "07_widmo_shot", 2)
	await wait(0.8)
	# 7. WRATH-4: wybuch
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
	await wait(1.5)
	# 11. ślady po kulach w gruncie i osmalenie po granacie (1.7.312)
	free_dummies()
	d = equip(Weapons.M83)
	for i in 8:
		player.aim_dir = Vector2.from_angle(deg_to_rad(52.0 + 3.0 * i))          # suchy grunt tuż przed postacią (dalej w prawo leży bagno — w cieczy śladów nie ma)
		wc.cd = 0.0
		wc._fire_shot(d)
		await wait(0.12)
	d = equip(Weapons.GNIEW4)
	player.aim_dir = Vector2.from_angle(deg_to_rad(-6.0))          # granat musi przelecieć odległość uzbrojenia (od 1.7.316), zanim spadnie na grunt
	wc._fire_shot(d)
	await wait(1.6)
	player.aim_dir = Vector2.RIGHT
	await _snap(out_dir, "13_marks", 2)
	print("[WTEST] zrzuty zapisane w %s" % out_dir)
	Audio.quit_game(0)

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
		Audio.quit_game(1)
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
	# części (1.7.319): drużyna ma tłumik PBS-1 — klient nic nie wybiera, więc gniazdo wylotu montuje go samo, a jego player.fits dociera do hosta
	Scrap.bank = 1000
	Scrap.parts["m83_pbs1"] = true
	Scrap._push()
	var pbs_code := Parts.encode_ids("m83", ["m83_pbs1"])
	await wait(0.5)
	var e := await dummy(80.0)
	print("[WTEST] host: manekin %s przed klientem (%s)" % [e.name, str(cp.global_position.round())])
	# perki klienta (B4): para indeksów dociera do hosta, a serwer liczy z niej serca i cenę Kowala dla tego peera
	var pw := 0.0
	while cp.perks == Vector2i(-1, -1) and pw < 6.0:
		await wait(0.2)
		pw += 0.2
	check("sieć: host widzi perki klienta (%s)" % str(Perks.ids_of(cp.perks)), Perks.ids_of(cp.perks) == ["veteran", "smith"])
	check("sieć: host widzi XP profilu klienta do dziennika sesji (%d, poziom %d)" % [cp.prof_xp, Profile.level_of(cp.prof_xp)], cp.prof_xp >= 1800 and Profile.level_of(cp.prof_xp) == 6)
	check("sieć: serce Weterana klienta liczy serwer (max %d), a cena Kowala dla peera klienta %d zamiast %d" % [cp.max_hp(), Scrap.part_cost("m83_rpkbar", cid), Parts.cost("m83_rpkbar")],
		cp.max_hp() == cp.MAX_HP + 1 and Scrap.part_cost("m83_rpkbar", cid) == Parts.cost("m83_rpkbar", 0.8) and Scrap.part_cost("m83_rpkbar") == Parts.cost("m83_rpkbar"))
	# czat: host zbiera linie rozesłane przez serwer (klient wysyła jedną wiadomość i serię 10 „flood")
	var chat_lines: Array = []
	var chat_node: Node = m.get_node("Chat")
	chat_node.line_added.connect(func(who: String, text: String) -> void: chat_lines.append([who, text]))
	# podglądamy serwerowy licznik przyjętych strzałów i obrażenia, dopóki klient jest połączony
	var legit_dmg := -1.0
	var accepted := 0
	var seen_fits := PackedInt32Array()
	var seen_build := -1
	var t := 0.0
	while t < 14.0 and is_instance_valid(cp):
		await wait(0.1)
		t += 0.1
		if not is_instance_valid(cp):
			break
		accepted = maxi(accepted, int(cp.weapons.srv_shots))
		seen_fits = cp.fits.duplicate()                  # klient zaraz się rozłączy — zapamiętaj montaż i ostatni strzał
		seen_build = int(cp.weapons.srv_last_build)
		if legit_dmg < 0.0 and cp.weapons.srv_shots >= 10:
			await wait(0.5)                      # niech ostatnia kula doleci
			legit_dmg = dealt(e)
			if is_instance_valid(cp):
				accepted = maxi(accepted, int(cp.weapons.srv_shots))
		if accepted >= 10 and t > 9.0:
			break
	await wait(0.8)
	check("zdalny strzelec: 10 legalnych strzałów M-83 klienta zadaje obrażenia na serwerze", legit_dmg >= 0.6 * 80.0 and legit_dmg <= 80.1, "%.1f / 80" % legit_dmg)
	check("limiter tempa: 20 sfałszowanych żądań naraz przyjęte ≤ 4× (zapas 2,5 + lag), ale coś przyjęte (RPC dochodzi)", accepted <= 10 + 4 and accepted > 10, "przyjęto łącznie %d (10 legalnych + ≤4)" % accepted)
	check("serwer odrzucił większość ataku (≥ 14 z 20)", accepted <= 10 + 6, "przyjęto %d" % accepted)
	var fits_ok: bool = seen_fits.size() > Weapons.M83 and int(seen_fits[Weapons.M83]) == pbs_code
	var last_fit := Weapons.fit_of_build(seen_build) if seen_build >= 0 else -1
	check("sieć: host widzi montaż klienta (fits %s), a serwer liczy strzał z jego częściami i wycina te, których drużyna nie ma (fit %d = %d)" % [str(seen_fits), last_fit, pbs_code],
		fits_ok and last_fit == pbs_code)
	var hi := chat_lines.filter(func(l: Array) -> bool: return String(l[1]) == "hi from client")
	var flood := chat_lines.filter(func(l: Array) -> bool: return String(l[1]).begins_with("flood"))
	check("czat sieciowy: wiadomość klienta dociera z etykietą nadawcy (%s), seria 10 „flood” przepuszczona ≤ 2× (%d)" % [str(hi), flood.size()],
		hi.size() == 1 and String(hi[0][0]).begins_with("P") and String(hi[0][0]) != "P?" and flood.size() <= 2)
	check("sieć: zakupy klienta poza kryjówką nie obciążają banku ani kolejek", Scrap.bank == 1000 and not Scrap.has_part("m83_rpk40") and Scrap.orders.is_empty())
	# Snapshot akcji dociera przed trafieniem, a przeładowanie rośnie do końca bez sinusoidy.
	_net_motion_phase.rpc_id(cid)
	var motion := Motion.new()
	var first_melee := 1.0
	var reload_samples := 0
	var previous_phase := -1.0
	var previous_id := -1
	var backwards := false
	for i in 210:
		await wait(1.0 / 60.0)
		motion.sample(cp.w_action, cp.w_action_clock, 1.0 / 60.0)
		if motion.action.y == Motion.MELEE and motion.phase >= 0.0:
			first_melee = minf(first_melee, motion.phase)
		if motion.action.y == Motion.RELOAD and motion.phase >= 0.0:
			reload_samples += 1
			if motion.action.x == previous_id and motion.phase < previous_phase:
				backwards = true
			previous_phase = motion.phase
			previous_id = motion.action.x
	check("sieć: zamach kilofa dociera przed trafieniem 45%", first_melee < 0.25, "pierwsza faza %.3f" % first_melee)
	check("sieć: przeładowanie ma rosnącą fazę i rzeczywisty czas", reload_samples > 30 and not backwards)
	# broń mocy (FUN_PLAN.md P1.3): serwer przydziela 2 naboje FALCON-6 spoza zestawu — przyjmuje dokładnie tyle, a sfałszowane strzały
	# po wyczerpaniu przydziału odrzuca; koniec broni mocy u klienta zeruje licznik serwera
	var shots0 := int(cp.weapons.srv_shots)
	check("sieć: serwer przyznaje klientowi broń mocy", cp.weapons.server_grant_power(Weapons.SOKOL6, 2))
	_net_power_phase.rpc_id(cid)
	var pwait := 0.0
	while pwait < 9.0 and is_instance_valid(cp) and not _net_power_done:
		await wait(0.2)
		pwait += 0.2
	await wait(0.5)
	check("sieć: broń mocy klienta — przyjęte dokładnie 2 strzały z przydziału, sfałszowane odrzucone (%d)" % (int(cp.weapons.srv_shots) - shots0),
		int(cp.weapons.srv_shots) - shots0 == 2)
	check("sieć: koniec broni mocy u klienta zeruje licznik serwera", cp.weapons._srv_power_w == -1 and cp.weapons._srv_power_left == 0)
	# Rzeczywisty zdalny człowiek, przy każdym właściwym stanowisku; lokalny host stoi poza ławą.
	main._set_map("z1_hub")
	await frames(3)
	for actor in main._players.get_children():
		if not actor.is_bot and actor.is_multiplayer_authority():
			actor.global_position = level.spawn_for(1)
	Scrap.unlocked[Weapons.LR7] = true
	Scrap.samples = 10
	Scrap.deliveries["ammo_slug"] = 5
	Arsenal.stock["ammo_slug"] = 0
	Scrap._push()
	var cost := Scrap.part_cost("m83_rpk40", cid) + Scrap.press_price("ammo_slug") + int(Scrap.SERVICE_COST["barrel"]) + Scrap.research_cost("lr7_lens", cid).y          # cena klienta: host może mieć Kowala
	var host_fit := Profile.fit_code(Weapons.M83)
	_net_shop_phase.rpc_id(cid)
	var shop_wait := 0.0
	while not _net_shop_finished and shop_wait < 20.0:
		await wait(0.2)
		shop_wait += 0.2
	check("sieć: zdalny gracz kupuje i bada przy właściwych stanowiskach", _net_shop_finished and Scrap.has_part("m83_rpk40") and Scrap.research == ["lr7_lens"] and Scrap.orders == ["ammo_slug"] and Scrap.bank == 1000 - cost)
	check("sieć: zdalny odbiór dostawy i jego duplikat zachowują naboje", Arsenal.get_throwable("ammo_slug") == 5 and not Scrap.deliveries.has("ammo_slug") and Scrap.fuse_index("frag") == 0)
	check("sieć: zakup w panelu klienta nie zmienia osobistego montażu hosta", Profile.fit_code(Weapons.M83) == host_fit)
	print("[WTEST] ==== sieć: %d/%d OK ====" % [total - failed, total])
	await wait(0.5)                    # klient kończy po potwierdzeniu; nie odpinamy mu peera podczas rysowania HUD/audio
	Audio.quit_game(1 if failed > 0 else 0)

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
		Audio.quit_game(1)
		return
	Profile.fits = {}
	Profile.add_xp(1800, "test")                  # L6: oba sloty i Weteran
	Profile.equip(0, "veteran")
	Profile.equip(1, "smith")
	# manekin lokalnie na kliencie (RPC stanu wroga z serwera potrzebuje węzła o tej samej ścieżce)
	main.level._add_enemy("TDummy1", "trzosek", me.global_position + Vector2(80.0, 0.0))
	await wait(4.0)
	player = me
	wc = me.weapons
	me.aim_dir = Vector2.RIGHT
	var chat_client: Node = main.get_node("Chat")
	chat_client.send("hi from client")
	await wait(0.8)
	for i in 10:
		chat_client.send("flood %d" % i)                     # klient nie ogranicza — tempo pilnuje serwer
	check("sieć: odblokowanie drużyny nie zmienia montażu klienta", wc.fit_of(Weapons.M83) == 0)
	Profile.set_fit("m83", "muzzle", "m83_pbs1")
	Scrap.request_part("m83_rpk40")                  # próba zakupu poza kryjówką: serwer musi odrzucić
	Scrap.request_order("ammo_slug")
	Profile.worn = {"m83": {"barrel": 80.0}}          # ponad progiem wymiany — prośba dociera do serwera, który ją odrzuca poza kryjówką
	Scrap.request_service(Weapons.M83, "barrel")
	var d: WeaponDef = wc.cur()                   # tłumik zamontowany świadomie przez klienta
	var predicted_before := get_tree().current_scene.get_child_count()
	for i in 10:
		wc.cd = 0.0
		wc._fire_shot(d)
		await wait(0.15)
	print("[WTEST] klient: wystrzelił 10×, magazynek %d" % wc.mag_of(d.id))
	await wait(1.0)
	# atak: 20 żądań naraz z prawidłowym wylotem i sfałszowanym bębnem 75, którego drużyna nie ma (serwer go wytnie)
	var muzzle: Vector2 = wc.muzzle_pos(Vector2.RIGHT, d)
	var forged := Weapons.build_of(0, Parts.encode_ids("m83", ["m83_drum75", "m83_pbs1"]))
	for i in 20:
		wc._fire_request.rpc_id(1, muzzle, Vector2.RIGHT, Weapons.M83, randi(), 0.0, forged)
	await wait(2.0)
	var shop_wait := 0.0
	while not _net_shop_finished and shop_wait < 30.0:
		await wait(0.2)
		shop_wait += 0.2
	check("sieć: klient zakończył operacje warsztatu", _net_shop_finished)
	print("[WTEST] klient: koniec")
	Audio.quit_game(1 if failed else 0)

var _net_power_done := false

## Klient: czeka na broń mocy, oddaje 2 strzały z przydziału, po jej końcu próbuje 3 sfałszowanych strzałów tą bronią.
@rpc("authority", "call_remote", "reliable")
func _net_power_phase() -> void:
	var w8 := 0.0
	while not wc.power_active() and w8 < 4.0:
		await wait(0.1)
		w8 += 0.1
	check("sieć: klient dostał broń mocy poza slotami", wc.power_active() and wc.cur().id == Weapons.SOKOL6 and wc.mag_of(Weapons.SOKOL6) == 2)
	await wait(0.4)
	for i in 2:
		wc.cd = 0.0
		wc.state = wc.State.READY
		wc._fire_shot(wc.cur())
		await wait(0.4)
	var e8 := 0.0
	while wc.power_active() and e8 < 3.0:
		await wait(0.1)
		e8 += 0.1
	check("sieć: po przydziale klient wraca do broni ze slotu", not wc.power_active())
	await wait(0.5)
	var muzzle: Vector2 = wc.muzzle_pos(Vector2.RIGHT, Weapons.def(Weapons.SOKOL6))
	for i in 3:
		wc._fire_request.rpc_id(1, muzzle, Vector2.RIGHT, Weapons.SOKOL6, randi(), 0.0, 0)
		await wait(0.5)
	_net_power_report.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _net_power_report() -> void:
	_net_power_done = true

## Prawdziwy klient publikuje zamach i przeładowanie; host obserwuje normalną replikację.
@rpc("authority", "call_remote", "reliable")
func _net_motion_phase() -> void:
	wc.melee_id = Weapons.KILOF
	wc.try_melee()
	await wait(1.0)
	wc.practice = true
	wc.mags[wc.cur().id] = 1
	wc.try_reload()
	await wait(2.3)
	wc._cancel_actions()
	wc.practice = false

## Host zleca dodatkową fazę istniejącego testu sieci; wszystkie zakupy nadal idą normalnymi RPC Scrap.
@rpc("authority", "call_remote", "reliable")
func _net_shop_phase() -> void:
	var map_wait := 0.0
	while main.level.map_id != "z1_hub" and map_wait < 10.0:
		await wait(0.2)
		map_wait += 0.2
	if main.level.map_id != "z1_hub":
		return
	player.set_physics_process(false)
	_station_move("workshop")
	await wait(0.4)                              # replikacja pozycji do hosta
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	ui.open("bench")
	ui._select(0)
	ui._pick_opt(ui._options(Weapons.M83).find({"slot": "feed", "id": "m83_rpk40"}))
	var fit_before := Profile.fit_code(Weapons.M83)
	ui._act()
	ui._act()                                  # UI blokuje duplikat przed odpowiedzią z prawdziwego hosta
	check("sieć: klient czeka na wynik zakupu bez przedwczesnego montażu", not ui._pending_part.is_empty() and Profile.fit_code(Weapons.M83) == fit_before)
	await wait(0.4)
	check("sieć: odpowiedź hosta zatwierdza montaż i uruchamia efekt klienta", ui._pending_part.is_empty() and Profile.fitted("m83", "feed") == "m83_rpk40" and ui._d_stage._mount_time >= 0)
	ui.close()
	Scrap.request_part("m83_rpk40")              # powtórzenie normalnego RPC nadal nie pobiera drugiej opłaty
	_station_move("press_bench")
	await wait(0.4)
	check("sieć: klient otrzymał snapshot gotowej dostawy", int(Scrap.deliveries.get("ammo_slug", 0)) == 5)
	Scrap.request_order("ammo_slug")
	Scrap.request_claim("ammo_slug")
	Scrap.request_claim("ammo_slug")
	await wait(0.4)
	_station_move("service_bench")
	await wait(0.4)
	Profile.worn = {"m83": {"barrel": 80.0}}
	Scrap.request_service(Weapons.M83, "barrel")
	Scrap.request_service(Weapons.M83, "barrel")
	await wait(0.4)
	_station_move("pyro_bench")
	await wait(0.4)
	Scrap.request_fuse("frag", 0)
	_station_move("lab_bench")
	await wait(0.4)
	Scrap.request_research("lr7_lens")
	await wait(0.4)
	check("sieć: tylko kupujący montuje część i dostaje wymianę lufy", Profile.fitted("m83", "feed") == "m83_rpk40" and Profile.part_wear("m83", "barrel") == 0.0)
	player.set_physics_process(true)
	_net_shop_ack.rpc_id(1)
	_net_shop_finished = true

@rpc("any_peer", "call_remote", "reliable")
func _net_shop_ack() -> void:
	if NoiseMgr.is_server() and multiplayer.get_peers().has(multiplayer.get_remote_sender_id()):
		_net_shop_finished = true
