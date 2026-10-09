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
const Upgrades := preload("res://scripts/upgrades.gd")
const Lights := preload("res://scripts/lights.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Perks := preload("res://scripts/perks.gd")
const Sprites := preload("res://scripts/sprites.gd")
const NightShiftMode := preload("res://scripts/night_shift.gd")
const SmokeCloud := preload("res://scripts/smoke_cloud.gd")
const BrickWall := preload("res://scripts/brick_wall.gd")
const WALL_HP_REF := 120.0
const Enemy := preload("res://scripts/enemy.gd")
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
	wc._heat.clear()
	wc.bloom = 0.0
	wc.cd = 0.0
	wc.state = Controller.State.READY
	wc.firing = false
	wc._burst_left = 0
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
	await _t_phase1()
	await _t_upgrades()
	await _t_phase3()
	await _t_phase4()
	await _t_throwables()
	await _t_profile()
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
	await _t_lag()
	await _t_bot()
	print("[WTEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _t_data() -> void:
	var errs := Weapons.validate()
	check("tabele broni spójne (validate)", errs.is_empty(), "; ".join(errs))
	var uerrs := Upgrades.validate(Weapons.defs())
	check("tabela ulepszeń spójna: 12 broni × 3 poziomy, pola istnieją (%d wpisów)" % Upgrades.TIERS.size(), uerrs.is_empty() and Upgrades.TIERS.size() == Weapons.COUNT, "; ".join(uerrs))
	check("ceny ulepszeń skalowane klasą broni (M-83 60/120/220, P-64 T3 %d, SPECTER-1 T3 %d)" % [Upgrades.cost("p64", 3), Upgrades.cost("widmo1", 3)],
		Upgrades.cost("m83", 1) == 60 and Upgrades.cost("m83", 2) == 120 and Upgrades.cost("m83", 3) == 220 and Upgrades.cost("p64", 3) < 220 and Upgrades.cost("widmo1", 3) > 220)
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
	check("pancerz Wołka: śrucina PELLET-8 (10) traci 3, nie więcej", absf(dealt(w) - b0 - 7.0) < 0.01)
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
	var lit_beam: Dictionary = moth._nearest_light(300.0)
	player.weapon = Weapons.M83
	var lit_gun: Dictionary = moth._nearest_light(300.0)
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
	var plain: int = Upgrades.cost("m83", 2)
	var smithed: int = Scrap.tier_cost("m83", 2)
	check("Kowal: M-83 T2 %d → %d scrap (−20%%, zaokrąglone do 5), bez perka %d" % [plain, smithed, Scrap.tier_cost("m83", 2, 99)],
		smithed == Upgrades.cost("m83", 2, 0.8) and smithed < plain and Scrap.tier_cost("m83", 2, 99) == plain)
	var bf_before: float = player._revive_time()
	player.perks = Perks.to_indexes(["blood_flow", "veteran"])
	check("Krwiobieg: podnoszenie %.1f s zamiast %.1f s" % [player._revive_time(), bf_before], is_equal_approx(player._revive_time(), 2.5 * Difficulty.m("revive")) and player._revive_time() < bf_before)
	check("Weteran: serca %d (stos %d) zamiast %d (%d)" % [player.max_hp(), player.stack_hp(), player.MAX_HP, player.STACK_HP], player.max_hp() == player.MAX_HP + 1 and player.stack_hp() == player.STACK_HP + 1)
	player.perks = Perks.to_indexes(["quiet_steps", "wide_arm"])
	check("Ciche kroki ×%.2f, Szerokie ramię ×%.1f, bez perka ×1" % [player.perk_param("quiet_steps", "run_noise_mult", 1.0), player.perk_param("wide_arm", "throw_mult", 1.0)],
		is_equal_approx(player.perk_param("quiet_steps", "run_noise_mult", 1.0), 0.5) and is_equal_approx(player.perk_param("wide_arm", "throw_mult", 1.0), 1.3) and is_equal_approx(player.perk_param("scout", "scan_stalker_range", 0.0), 0.0))
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
	_t_actions()
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
	check("ściąga: ruch „WASD / Arrows”, ogień „J / LMB”, przedmiot „L-Alt / X”, broń „1 2 3 / Wheel” (%s | %s | %s | %s)" % [rows.get("Move & aim"), rows.get("Fire — makes NOISE"), rows.get("Use item / switch item"), rows.get("Switch weapon")],
		rows.get("Move & aim") == "WASD / Arrows" and rows.get("Fire — makes NOISE") == "J / LMB" 		and rows.get("Use item / switch item") == ("L-Cmd / X" if OS.get_name() == "macOS" else "L-Alt / X") and rows.get("Switch weapon") == "1 2 3 / Wheel")
	var ev_a := InputEventKey.new()
	ev_a.physical_keycode = KEY_A
	var ev_e := InputEventKey.new()
	ev_e.physical_keycode = KEY_E
	var ev_pad := InputEventJoypadButton.new()
	ev_pad.button_index = JOY_BUTTON_A
	check("akcje menu (warsztat): A → lewo, E → wróć, przycisk A pada → zatwierdź, nie są wycinane przy menu (%s / %s)" % [Actions.text("menu_accept", true), Actions.text("menu_accept", true, true)],
		InputMap.event_is_action(ev_a, "menu_left") and InputMap.event_is_action(ev_e, "menu_back") and InputMap.event_is_action(ev_pad, "menu_accept") 		and not blockable.has("menu_accept") and Actions.text("menu_accept", true) == "Enter" and Actions.text("menu_accept", true, true) == "A")
	check("podpowiedzi: {interact} → E, {restart} → ENTER, {move} → WASD (%s %s %s)" % [Actions.key("interact"), Actions.key("restart"), Actions.fmt("{move}")],
		Actions.key("interact") == "E" and Actions.key("restart") == "ENTER" and Actions.fmt("{move}") == "WASD" and not Actions.fmt("{overcharge}{throw_next}").contains("{"))

## Faza A2: dym, mina, ładunek wyburzeniowy, apteczka, defibrylator, skaner.
func _t_gear() -> void:
	var data_ok := Throwables.ORDER.size() == 8 and Throwables.ORDER.all(func(k: String) -> bool: return Throwables.KINDS.has(k) and ["throw", "place", "use"].has(Throwables.mode_of(k)))
	check("tabela przedmiotów: 8 rodzajów (3 rzucane, 2 stawiane, 3 narzędzia)", data_ok)
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
	var saved_bank := Scrap.bank
	var res: Array = []
	var cb := func(kind: String, ok: bool, reason: String) -> void: res.append([kind, reason])
	Scrap.supply_result.connect(cb)
	Arsenal.reset_throwables()
	Scrap.bank = 50
	Scrap.request_buy_supply("mine")                       # za mało
	Scrap.bank = 500
	Scrap.request_buy_supply("mine")                       # ok
	Scrap.request_buy_supply("defib")                      # nie na sprzedaż
	for i in 4:
		Scrap.request_buy_supply("frag")                   # 1 w zestawie + 3 kupione = sufit 4, czwarty „full”
	Scrap.supply_result.disconnect(cb)
	var reasons := res.map(func(r: Array) -> String: return String(r[1]))
	var spent := 500 - Scrap.bank
	check("zakup zaopatrzenia: %s, portfel −%d, zapas mina %d frag %d" % [str(reasons), spent, Arsenal.get_throwable("mine"), Arsenal.get_throwable("frag")],
		reasons == ["poor", "ok", "invalid", "ok", "ok", "ok", "full"] and spent == Throwables.price_of("mine") + 3 * Throwables.price_of("frag") and Arsenal.get_throwable("mine") == 1 and Arsenal.get_throwable("frag") == 4)
	Scrap.bank = saved_bank
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
	level.spawn_item("supply", Throwables.ORDER.find("scanner"), player.global_position + Vector2(0, -4))
	await wait(1.4)
	check("skrzynka zaopatrzenia: podniesiona, +1 skaner (zapas %d)" % Arsenal.get_throwable("scanner"), Arsenal.get_throwable("scanner") == 1)
	Arsenal.stock["scanner"] = int(Throwables.KINDS["scanner"]["max"])
	level.spawn_item("supply", Throwables.ORDER.find("scanner"), player.global_position + Vector2(0, -4))
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
	# --- linka SINEW-6 (poziom 3): trafiony wróg leci ku strzelcowi, bez ulepszenia odlatuje
	var saved: Dictionary = Weapons.levels.duplicate()
	var plain_t := await dummy(80.0)
	var info0 := Combat.make_info(Weapons.CIEGNO6, 45.0, plain_t.global_position, Vector2.RIGHT, 1, "bullet")
	Combat.apply(plain_t, info0)
	var plain_v: float = plain_t.velocity.x
	Weapons.levels[Weapons.CIEGNO6] = 3
	var teth := await dummy(120.0)
	var tank := await dummy(160.0, 100000.0, "wolek")
	var info1 := Combat.make_info(Weapons.CIEGNO6, 45.0, teth.global_position, Vector2.RIGHT, 1, "bullet")
	Combat.apply(teth, info1)
	var info2 := Combat.make_info(Weapons.CIEGNO6, 45.0, tank.global_position, Vector2.RIGHT, 1, "bullet")
	Combat.apply(tank, info2)
	check("linka SINEW-6 (T3): trafiony Trzosek leci ku strzelcowi (%.0f px/s), bez ulepszenia odlatuje (%.0f)" % [teth.velocity.x, plain_v], teth.velocity.x < -150.0 and plain_v > 0.0)
	check("linka: Wołek (knock_mult 0,2) szarpnięty słabiej (%.0f px/s)" % tank.velocity.x, tank.velocity.x < 0.0 and absf(tank.velocity.x) < absf(teth.velocity.x) * 0.5)
	Weapons.levels.clear()
	for k in saved:
		Weapons.levels[k] = saved[k]
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
	# --- ćma: ogień spala, błysk z lufy budzi
	var moth := await dummy(120.0, 100000.0, "cma")
	Lights.flashes.clear()
	player.flashlight = false
	player.w_firing = false
	var quiet: bool = moth._nearest_light(420.0).is_empty()
	level.spawn_fire_patch(moth.global_position + Vector2(40, 0), Weapons.HKM9, 1)
	await frames(2)
	var by_fire: Dictionary = moth._nearest_light(420.0)
	check("ćma leci na ogień na podłodze (jak na flarę)", quiet and not by_fire.is_empty() and by_fire["kind"] == "flare")
	free_dummies()
	await frames(2)
	moth = await dummy(120.0, 100000.0, "cma")
	var e0 := equip(Weapons.M83)
	wc.cd = 0.0
	wc._server_fire(wc.muzzle_pos(Vector2.RIGHT, e0), Vector2.RIGHT, e0.id, 1, 0.0, 1, true)
	var after_m83: bool = moth._nearest_light(420.0).is_empty()
	var sp := equip(Weapons.SPREAD12)
	wc.cd = 0.0
	wc._server_fire(wc.muzzle_pos(Vector2.RIGHT, sp), Vector2.RIGHT, sp.id, 1, 0.0, 1, true)
	var after_spread: Dictionary = moth._nearest_light(420.0)
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

## Faza 2 przeglądu broni: ulepszenia poziomu 3 zmieniają zachowanie broni (kasetowe, salwa, podpalenie, dobicie, przebicie ścian).
func _t_upgrades() -> void:
	var saved: Dictionary = Weapons.levels.duplicate()
	for w in [Weapons.GNIEW4, Weapons.SOKOL6, Weapons.WIDMO1, Weapons.CIEGNO6, Weapons.MACZETA, Weapons.KILOF, Weapons.SPREAD12, Weapons.SRUT8]:
		Weapons.levels[w] = 3
	var g := Weapons.def(Weapons.GNIEW4)
	check("WRATH-4 T3: bomby kasetowe (%d), wybuch %.0f / promień %.0f px" % [g.cluster, g.blast_damage, g.blast_radius], g.cluster == 2 and absf(g.blast_damage - 100.0) < 0.01 and absf(g.blast_radius - 54.0) < 0.5)
	# bomby kasetowe naprawdę ranią cele po bokach punktu wybuchu
	var left := await dummy(76.0)
	var right := await dummy(124.0)
	var rk := Projectile.new()
	rk.launch(Weapons.GNIEW4, player.global_position + Vector2(10, -4), Vector2.RIGHT, 1, true)
	get_tree().current_scene.add_child(rk)
	rk.set_physics_process(false)                       # sam rakieta stoi w miejscu — sprawdzamy tylko bomby kasetowe
	rk._scatter_cluster(player.global_position + Vector2(100.0, 0.0))
	await wait(0.5)
	check("WRATH-4 T3: obie bomby kasetowe trafiają cele po bokach", dealt(left) > 5.0 and dealt(right) > 5.0, "lewy %.1f prawy %.1f" % [dealt(left), dealt(right)])
	if is_instance_valid(rk):
		rk.queue_free()
	free_dummies()
	await frames(2)
	var f := Weapons.def(Weapons.SOKOL6)
	check("FALCON-6 T3: salwa 3 rakiet za 2 naboje (pellets %d, koszt %d, magazynek %d)" % [f.pellets, f.ammo_per_shot, f.mag], f.pellets == 3 and f.ammo_per_shot == 2 and f.mag == 60 and f.mag >= f.ammo_per_shot)
	check("SPECTER-1 T3: przebija jedną warstwę ściany, ładuje się szybciej (%.2f s)" % Weapons.def(Weapons.WIDMO1).charge_time, Weapons.def(Weapons.WIDMO1).wall_pierce >= 24.0 and Weapons.def(Weapons.WIDMO1).charge_time < Weapons.base_def(Weapons.WIDMO1).charge_time * 0.75)
	var sn := Weapons.def(Weapons.CIEGNO6)
	check("SINEW-6 T3: bełt przebija 1 cel, magazynek 2", sn.pierce == 1 and sn.mag == 2 and sn.damage > Weapons.base_def(Weapons.CIEGNO6).damage)
	var sp := Weapons.def(Weapons.SPREAD12)
	check("SPREAD-12 T3: pociski podpalają (%.1f s)" % sp.ignite, sp.ignite >= 2.0)
	var pe := Weapons.def(Weapons.SRUT8)
	check("PELLET-8 T3: ogłuszenie do 1,5 s (%.2f)" % pe.stun, absf(pe.stun - 1.5) < 0.01)
	var ki := Weapons.def(Weapons.KILOF)
	check("KILOF T3: szerszy łuk i dłuższe ogłuszenie (%.0f°, %.1f s)" % [ki.arc_deg, ki.stun], ki.arc_deg > Weapons.base_def(Weapons.KILOF).arc_deg * 1.5 and ki.stun >= 2.0)
	# salwa FALCON-6 T3 w kontrolerze: jeden strzał = 3 rakiety i −2 naboje
	var fd := equip(Weapons.SOKOL6)
	var mag_f: int = wc.mag_of(fd.id)
	var proj_before := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	wc.cd = 0.0
	wc._fire_shot(fd)
	await frames(2)
	var proj_after := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	check("FALCON-6 T3: jeden strzał = 3 rakiety (%d → %d) i −2 naboje (%d → %d)" % [proj_before, proj_after, mag_f, wc.mag_of(fd.id)], proj_after - proj_before == 3 and mag_f - wc.mag_of(fd.id) == 2)
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
	var rail_d := Weapons.def(Weapons.WIDMO1)
	var pierced := Combat.trace(space, org, Vector2.RIGHT, 300.0, 99, rail_d.wall_pierce, [player.get_rid()])
	check("SPECTER-1 T3: szyna bez przebicia staje na murze, z ulepszeniem trafia cel za ścianą", bool(plain["wall"]) and (plain["hits"] as Array).is_empty() and (pierced["hits"] as Array).size() == 1,
		"bez: ściana %s trafień %d, z: trafień %d" % [str(plain["wall"]), (plain["hits"] as Array).size(), (pierced["hits"] as Array).size()])
	wall.queue_free()
	free_dummies()
	await frames(2)
	# maczeta T3: dobija wroga poniżej 35% HP, wyżej zadaje zwykłe obrażenia
	var mz := Weapons.def(Weapons.MACZETA)
	check("MACZETA T3: dobicie poniżej %.0f%% HP, zasięg %.0f px" % [mz.execute_frac * 100.0, mz.reach], absf(mz.execute_frac - 0.35) < 0.001 and mz.reach > Weapons.base_def(Weapons.MACZETA).reach)
	var hi := await dummy(40.0, 100.0)
	hi.hp = 50.0
	var r_hi := Combat.apply(hi, Combat.make_info(Weapons.MACZETA, mz.damage, hi.global_position, Vector2.RIGHT, 1, "melee"))
	var lo := await dummy(60.0, 100.0)
	lo.hp = 30.0
	var r_lo := Combat.apply(lo, Combat.make_info(Weapons.MACZETA, mz.damage, lo.global_position, Vector2.RIGHT, 1, "melee"))
	check("MACZETA T3: wróg na 50% HP dostaje zwykły cios, na 30% ginie od razu", not bool(r_hi["killed"]) and bool(r_lo["killed"]), "50%%: %s, 30%%: %s" % [str(r_hi["killed"]), str(r_lo["killed"])])
	free_dummies()
	await frames(2)
	Weapons.levels.clear()
	for k in saved:
		Weapons.levels[k] = saved[k]

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
	check("LR-7: promień przebija 2 cele (pierce 1), trzeci nietknięty", hit_count == 2 and dealt(targets[2]) == 0.0, "trafionych %d" % hit_count)
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
	# perki klienta (B4): para indeksów dociera do hosta, a serwer liczy z niej serca i cenę Kowala dla tego peera
	var pw := 0.0
	while cp.perks == Vector2i(-1, -1) and pw < 6.0:
		await wait(0.2)
		pw += 0.2
	check("sieć: host widzi perki klienta (%s)" % str(Perks.ids_of(cp.perks)), Perks.ids_of(cp.perks) == ["veteran", "smith"])
	check("sieć: serce Weterana klienta liczy serwer (max %d), a cena Kowala dla peera klienta %d zamiast %d" % [cp.max_hp(), Scrap.tier_cost("m83", 2, cid), Upgrades.cost("m83", 2)],
		cp.max_hp() == cp.MAX_HP + 1 and Scrap.tier_cost("m83", 2, cid) == Upgrades.cost("m83", 2, 0.8) and Scrap.tier_cost("m83", 2) == Upgrades.cost("m83", 2))
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
	Profile.add_xp(1800, "test")                  # L6: oba sloty i Weteran
	Profile.equip(0, "veteran")
	Profile.equip(1, "smith")
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
