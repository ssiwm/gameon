extends Node
## Regresje warsztatu na rzeczywistym graczu i stanowiskach: --host --workshoptest.
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Controller := preload("res://scripts/weapon_controller.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Char3D := preload("res://scripts/char3d.gd")
const SupplyArtRef := preload("res://scripts/station_supply_art.gd")
const ServiceArtRef := preload("res://scripts/station_service_art.gd")
const Perks := preload("res://scripts/perks.gd")
var total := 0
var failed := 0
var main: Node
var player: Node2D
var wc: Node

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[WORKSHOP-TEST] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame

func station(group: String) -> void:
	var node := get_tree().get_first_node_in_group(group)
	assert(node != null)
	player.global_position = node.global_position + Vector2(0, -2)
	player.velocity = Vector2.ZERO

func run(m: Node) -> void:
	main = m
	await get_tree().create_timer(1.5).timeout
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			player = p
		elif p.is_bot:
			p.queue_free()
	check("prawdziwa kryjówka i człowiek", player != null and main.level.map_id == "z1_hub")
	if player == null:
		Audio.quit_game(1)
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED
	wc = player.weapons
	Profile.reset_for_test()
	Scrap.load_progress()
	Scrap.bank = 4000
	Scrap.samples = 20
	Settings.reliability_idx = 1
	await _authorization()
	await _magazines()
	await _delivery_wipe()
	await _migration()
	await _jobs_deliveries()
	await _ui()
	await _service_card()
	await _immersive()
	await _progression()
	await _strip_frame()
	await _layout()                                  # na końcu: przegląda wszystkie stanowiska i kafle, zmienia wybory w panelu
	print("[WORKSHOP-TEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	Audio.quit_game(1 if failed else 0)

func _authorization() -> void:
	var peer: int = player.player_id
	main._set_map("z1_m3")
	await frames(3)
	var bank: int = Scrap.bank
	Scrap.request_buy(Weapons.LR7)
	Scrap.request_part("m83_rpk40")
	Scrap.request_buy_supply("mine")
	Scrap.request_research("lr7_lens")
	Scrap.request_machining("lr7_lens")
	Scrap.request_order("ammo_slug")
	Scrap.request_service(Weapons.M83, "barrel")
	Scrap.request_fuse("frag", 0)
	check("wszystkie operacje poza hubem odrzucone", Scrap.bank == bank and Scrap.parts.is_empty() and Scrap.unlocked.is_empty() and Scrap.research.is_empty() and Scrap.orders.is_empty() and Scrap.fuses.is_empty())
	main._set_map("z1_hub")
	await frames(3)
	station("press_bench")
	Scrap.request_part("m83_rpk40")
	check("niewłaściwe stanowisko nie obciąża banku", Scrap.bank == bank and not Scrap.has_part("m83_rpk40"))
	station("workshop")
	var bench := get_tree().get_first_node_in_group("workshop")
	bench.local_in_range = false
	check("serwer używa pozycji nadawcy, nie flagi lokalnego UI", Scrap.station_reason(peer, "workshop") == "ok")
	check("obcy nadawca odrzucony", Scrap.station_reason(987654321, "workshop") == "station")
	player.dead = true
	check("martwy nadawca odrzucony", Scrap.station_reason(peer, "workshop") == "station")
	player.dead = false
	Scrap.request_buy(Weapons.LR7)
	check("zakup broni przy ławie", Scrap.is_unlocked(Weapons.LR7) and Scrap.bank == bank - Scrap.price_of(Weapons.LR7))
	Scrap.request_part("m83_rpk40")
	var after: int = Scrap.bank
	Scrap.request_part("m83_rpk40")
	check("zakup części i ponowienie bez podwójnej opłaty", Scrap.has_part("m83_rpk40") and Scrap.bank == after and Profile.fitted("m83", "feed") == "m83_rpk40")
	station("pyro_bench")
	Scrap.request_fuse("frag", 0)
	Scrap.request_buy_supply("mine")
	check("piro: zakup i wspólny zapalnik", Scrap.fuse_index("frag") == 0 and Arsenal.get_throwable("mine") > 0)
	station("service_bench")
	Profile.worn = {"m83": {"barrel": 80.0}}
	Scrap.request_service(Weapons.M83, "barrel")
	after = Scrap.bank
	Scrap.request_service(Weapons.M83, "barrel")
	await get_tree().create_timer(0.4).timeout
	Scrap.request_service(Weapons.M83, "barrel")
	check("wymiana raz na pobyt w kryjówce, także opóźnione ponowienie", Scrap.bank == after and Profile.part_wear("m83", "barrel") == 0.0)
	# próg wymiany (Profile.SERVICE_DUE): sprężyny zużyte w 0,7 % — odmowa bez złomu; od progu — wymiana
	var why := [""]
	var on_result := func(_w: int, _p: String, _ok: bool, r: String) -> void: why[0] = r
	Scrap.service_result.connect(on_result)
	Profile.worn = {"m83": {"springs": 0.7}}
	after = Scrap.bank
	Scrap.request_service(Weapons.M83, "springs")
	check("sprężyny 0,7 %%: wymiana odrzucona przed serwerem (%s), złom i zużycie bez zmian" % why[0],
		why[0] == "early" and Scrap.bank == after and is_equal_approx(Profile.part_wear("m83", "springs"), 0.7))
	Profile.worn = {"m83": {"springs": Profile.SERVICE_DUE + 5.0}}
	Scrap.request_service(Weapons.M83, "springs")
	check("sprężyny od progu %d%%: wymiana za %d złomu" % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["springs"])],
		why[0] == "ok" and Scrap.bank == after - int(Scrap.SERVICE_COST["springs"]) and Profile.part_wear("m83", "springs") == 0.0)
	Scrap.service_result.disconnect(on_result)
	station("press_bench")
	Arsenal.stock["ammo_slug"] = 0
	Scrap.request_order("ammo_slug")
	after = Scrap.bank
	Scrap.request_order("ammo_slug")
	check("powtórzone szybkie zamówienie nie płaci dwa razy", Scrap.bank == after and Scrap.orders == ["ammo_slug"])
	Scrap.orders.clear()

func _magazines() -> void:
	wc.loadout.assign([Weapons.SPREAD12, Weapons.M83, Weapons.P64])
	wc.slot = 0
	wc.melee_id = Weapons.MACZETA
	Scrap.parts["sp12_box8"] = true
	Scrap.parts["sp12_drum30"] = true
	Profile.set_fit("spread12", "feed", "sp12_drum30")
	wc.reset()
	wc.loadout.assign([Weapons.SPREAD12, Weapons.M83, Weapons.P64])
	wc.slot = 0
	var large: int = wc.cur().mag
	wc.mags[Weapons.SPREAD12] = 25
	Arsenal.set_reserve(Weapons.SPREAD12, 5, 1)
	wc.loaded[Weapons.SPREAD12] = 1
	Profile.set_fit("spread12", "feed", "sp12_box8")
	var small: int = wc.cur().capacity(true)
	check("duży → mały zachowuje naboje i typ amunicji", wc.mag_of(Weapons.SPREAD12) == small and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 5 + 25 - small and wc.ammo_of(Weapons.SPREAD12) == 1)
	Profile.save_preset("spread12", 0)
	Profile.set_fit("spread12", "feed", "sp12_drum30")
	check("mały → duży nie tworzy nabojów", wc.cur().mag == large and wc.mag_of(Weapons.SPREAD12) == small)
	wc.mags[Weapons.SPREAD12] = 25
	Arsenal.set_reserve(Weapons.SPREAD12, 0, 1)
	Profile.load_preset("spread12", 0)
	check("zestaw przechodzi tą samą ścieżką ograniczenia magazynka", wc.mag_of(Weapons.SPREAD12) == small and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 25 - small)
	Profile.set_fit("spread12", "feed", "sp12_drum30")
	wc.mags[Weapons.SPREAD12] = 20
	wc.state = Controller.State.RELOAD
	wc._rl_cap = large
	wc._rl_pending = 2
	Profile.set_fit("spread12", "feed", "sp12_box8")
	check("zmiana podczas przeładowania rozlicza już przyznane naboje", wc.state == Controller.State.READY and wc._rl_pending == 0 and wc.mag_of(Weapons.SPREAD12) == small and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 25 - small + 22 - small)
	var reserve: int = Arsenal.get_reserve(Weapons.SPREAD12, 1)
	wc._on_rounds_granted(Weapons.SPREAD12, 4)
	check("spóźniona odpowiedź po zmianie części zwraca nadmiar", wc.mag_of(Weapons.SPREAD12) == small and Arsenal.get_reserve(Weapons.SPREAD12, 1) == reserve + 4)
	wc.mags[Weapons.SPREAD12] = 0
	wc.state = Controller.State.RELOAD
	wc._rl_cap = small
	Arsenal.set_reserve(Weapons.SPREAD12, 5, 1)
	wc._on_rounds_granted(Weapons.SPREAD12, 20)
	check("spóźniona odpowiedź podczas nowego przeładowania zachowuje nadmiar", wc.mag_of(Weapons.SPREAD12) == small and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 5 + 20 - small)
	Profile.set_fit("spread12", "feed", "sp12_drum30")
	wc.mags[Weapons.SPREAD12] = 25
	Arsenal.stock["ammo_slug"] = int(Throwables.KINDS["ammo_slug"]["max"])
	Profile.set_fit("spread12", "feed", "sp12_box8")
	check("specjalne naboje zwrócone przy pełnym zapasie czekają w dostawie", int(Scrap.deliveries.get("ammo_slug", 0)) == 25 - small)
	Scrap.deliveries.clear()
	Scrap.parts["m83_drum75"] = true
	Profile.set_fit("m83", "feed", "m83_drum75")
	wc.loaded.erase(Weapons.M83)
	wc.mags[Weapons.M83] = 76
	Arsenal.set_reserve(Weapons.M83, Arsenal.pool_max(Weapons.M83))
	Profile.set_fit("m83", "feed", "")
	check("komora +1 i pełny zapas nie kasują zwrotu", wc.mag_of(Weapons.M83) == 31 and Arsenal.get_reserve(Weapons.M83) == Arsenal.pool_max(Weapons.M83) + 45)
	check("zwrot z pełnej puli jest dostępny do następnego przeładowania", Arsenal.take_rounds(Weapons.M83, 45) == 45 and Arsenal.get_reserve(Weapons.M83) == Arsenal.pool_max(Weapons.M83))

func _delivery_wipe() -> void:
	Scrap.deliveries = {"ammo_slug": 3}
	Arsenal.stock["ammo_slug"] = int(Throwables.KINDS["ammo_slug"]["max"])
	main._set_map("z1_m3")
	await frames(3)
	Arsenal.begin_mission(true)
	Arsenal.deposit(Weapons.SPREAD12, 8, 1)
	check("zwrot przy pełnym zapasie w misji jest tymczasowo dostępny", int(Scrap.deliveries.get("ammo_slug", 0)) == 11)
	Scrap.persist = true
	var path := "user://workshop_checkpoint_test.cfg"
	Scrap.save_progress(path)
	Scrap.persist = false
	var cfg := ConfigFile.new()
	cfg.load(path)
	check("zapis w trakcie misji nie utrwala tymczasowego zwrotu", int((cfg.get_value("workshop", "deliveries", {}) as Dictionary).get("ammo_slug", 0)) == 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Arsenal.begin_mission(false)
	check("wipe cofa zwrot i zachowuje wcześniej opłaconą dostawę", int(Scrap.deliveries.get("ammo_slug", 0)) == 3 and Arsenal.get_throwable("ammo_slug") == int(Throwables.KINDS["ammo_slug"]["max"]))
	main._set_map("z1_hub")
	await frames(3)
	Scrap.deliveries.clear()
	Arsenal.begin_mission(true)

func _migration() -> void:
	Profile.fits = {"m83": {"muzzle": ""}}
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "fits", Profile.fits)
	var path := "user://workshop_profile_test.cfg"
	cfg.save(path)
	Profile.load_from(path)
	check("stary zapis utrwala dotychczasowy automatyczny montaż", Profile.fitted("m83", "feed") == "m83_rpk40" and Profile.fitted("m83", "muzzle") == "")
	Scrap.parts["m83_pbs1"] = true
	Profile.load_from(path)
	check("migracja nie powtarza się po nowym odblokowaniu", Profile.fitted("m83", "muzzle") == "")
	var missing := "user://workshop_missing_profile_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(missing))
	Profile.fits = {}
	Scrap.legacy_fits = true
	Profile.load_from(missing)
	check("starszy postęp bez osobnego profilu zachowuje montaż", Profile.fitted("m83", "feed") == "m83_rpk40" and FileAccess.file_exists(missing))
	Scrap.legacy_fits = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(missing))
	Profile.fits = {}
	Scrap.changed.emit()
	check("nowy profil i współdzielone odblokowanie pozostają przy fabrycznej broni", Profile.fit_code(Weapons.M83) == 0 and wc.fit_of(Weapons.M83) == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _jobs_deliveries() -> void:
	station("lab_bench")
	Scrap.parts.erase("lr7_lens")
	Scrap.request_research("lr7_lens")
	check("badanie startuje przy pracowni", Scrap.research == ["lr7_lens"])
	check("część w badaniu nie trafia do puli znalezisk", not Scrap.find_part("lr7_lens"))
	check("pula losowania wyklucza aktywne badanie", not Scrap.find_candidates().has("lr7_lens"))
	Scrap.bank_loot(0)
	check("badanie kończy się schematem", Scrap.schematics.has("lr7_lens") and not Scrap.has_part("lr7_lens"))
	station("lathe_bench")
	Scrap.request_machining("lr7_lens")
	check("tokarka startuje ze schematu", Scrap.lathe == ["lr7_lens"])
	Scrap.bank_loot(0)
	check("tokarka daje część i usuwa schemat", Scrap.has_part("lr7_lens") and not Scrap.schematics.has("lr7_lens") and Scrap.lathe.is_empty())
	# Niespójny starszy zapis: znaleziono część już opłaconą w pracowni.
	var cost: Vector2i = Scrap.research_cost("lr7_cell")
	Scrap.research = ["lr7_cell"]
	Scrap.found["lr7_cell"] = true
	var bank: int = Scrap.bank
	var samples: int = Scrap.samples
	Scrap.bank_loot(0)
	check("odzysk znalezionej części anuluje zbędne badanie i zwraca koszt", Scrap.has_part("lr7_cell") and not Scrap.schematics.has("lr7_cell") and Scrap.research.is_empty() and Scrap.bank == bank + cost.y and Scrap.samples == samples + cost.x)
	var maxn := int(Throwables.KINDS["ammo_slug"]["max"])
	Arsenal.stock["ammo_slug"] = maxn - 3
	Scrap.orders = ["ammo_slug"]
	Scrap.bank_loot(0)
	var rest := Throwables.box_of("ammo_slug") - 3
	check("częściowa dostawa zachowuje każdy opłacony nabój", Arsenal.get_throwable("ammo_slug") == maxn and int(Scrap.deliveries.get("ammo_slug", 0)) == rest and Scrap.orders.is_empty())
	station("pyro_bench")
	Arsenal.stock["ammo_slug"] -= 2
	Scrap.request_claim("ammo_slug")
	check("odbiór przy niewłaściwym stanowisku odrzucony", int(Scrap.deliveries.get("ammo_slug", 0)) == rest)
	station("press_bench")
	Scrap.request_claim("ammo_slug")
	check("częściowy odbiór pozostawia resztę", Arsenal.get_throwable("ammo_slug") == maxn and int(Scrap.deliveries.get("ammo_slug", 0)) == rest - 2)
	Arsenal.stock["ammo_slug"] -= rest - 2
	Scrap.request_claim("ammo_slug")
	Scrap.request_claim("ammo_slug")
	check("pełny odbiór i duplikat nie tworzą nabojów", Arsenal.get_throwable("ammo_slug") == maxn and not Scrap.deliveries.has("ammo_slug"))
	Scrap.deliveries["ammo_slug"] = 5
	Scrap.persist = true
	var path := "user://workshop_progress_test.cfg"
	Scrap.save_progress(path)
	Scrap.deliveries.clear()
	Scrap.load_progress(path)
	Scrap.persist = false
	check("oczekująca dostawa przechodzi zapis i odczyt", int(Scrap.deliveries.get("ammo_slug", 0)) == 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var stock: Dictionary = Arsenal.stock.duplicate()
	Scrap._sync(Scrap.bank, Scrap.loot, Scrap.last_gain, Scrap.unlocked.keys(), Scrap.parts.keys(), Scrap.trophies.keys(), [], [], {}, Scrap.samples, 0, [], Scrap.schematics.keys(), [], {"ammo_slug": 5})
	check("snapshot dla ponownie dołączającego zawiera dostawy", int(Scrap.deliveries.get("ammo_slug", 0)) == 5 and Arsenal.stock == stock)

func _ui() -> void:
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	station("lab_bench")
	ui.open("lab")
	check("pracownia wybiera obsługiwaną broń", ui._sel > 0 and int(ui.LIST[ui._sel]) == Weapons.LR7)
	check("pracownia ukrywa broń bez operacji", ui._tiles.filter(func(t: Control) -> bool: return t.visible).size() == Scrap.LAB_WEAPONS.size() and not ui._tiles[0].visible)
	ui._select(ui.LIST.find(Weapons.GNIEW4))
	ui.close()
	ui.open("lab")
	check("wybór zapamiętany osobno dla stanowiska", int(ui.LIST[ui._sel]) == Weapons.GNIEW4)
	ui.close()
	Scrap.schematics["lr7_coil"] = true
	station("lathe_bench")
	ui.open("lathe")
	check("tokarka wybiera broń z gotowym schematem", int(ui.LIST[ui._sel]) == Weapons.LR7)
	check("podsumowanie pokazuje schemat i miejsce odbioru dostawy", ui._queue_summary().contains(tr("RELOADING PRESS")) and ui._queue_summary().contains(tr("Schematic: %s — take to the lathe") % tr(String(Parts.get_part("lr7_coil")["name"]))))
	ui.close()
	station("workshop")
	ui.open("bench")
	ui._select(ui.LIST.find(Weapons.SPREAD12))
	wc.loaded[Weapons.SPREAD12] = 1
	ui._refresh()
	check("porównanie używa amunicji z magazynka", ui._d_tag.text.contains(Ammo.name_of("12g", 1)))
	var labels: Array = ui._d_stats.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(c: Label) -> String: return c.text)
	var metrics: Array = ui._comparison_rows(wc.def_of(Weapons.SPREAD12)).map(func(row: Array) -> String: return String(row[0]))
	check("porównanie zawiera dobycie, celność, przebicie, grzanie i masę zestawu", metrics.has(tr("Draw")) and metrics.has(tr("Spread")) and metrics.has(tr("Penetration")) and metrics.has(tr("Heating")) and labels.has(tr("Kit mass")))
	check("otwarcie ławy pokazuje aktualny montaż i pełne statystyki", ui._opt == -1 and labels.has(tr("Damage")) and not ui._workbench._payload["preview"])
	ui._pick_opt(ui._options(Weapons.SPREAD12).find({"slot": "feed", "id": "sp12_drum30"}))
	labels = ui._d_stats.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(c: Label) -> String: return c.text)
	check("jawny podgląd pokazuje zmiany zamiast niezmienionych statystyk", labels.has(tr("Magazine")) and not labels.has(tr("Damage")) and ui._workbench._payload["preview"])
	check("odblokowane części odróżnione od zamontowanych", ui._d_tag.text.contains(tr("  ·  UNLOCKED %d / %d") % [Scrap.parts_owned(Weapons.SPREAD12), Parts.of("spread12").size()]) and ui._d_tag.text.contains(tr("  ·  FITTED %d") % Parts.decode("spread12", Profile.fit_code(Weapons.SPREAD12)).size()))
	check("długi panel mieści się w przewijanym korpusie", ui._arms_body.get_parent() is ScrollContainer)
	check("główna akcja pozostaje poza przewijaną treścią", ui._action.get_parent() == ui._arms_body.get_parent().get_parent() and ui._action.visible)
	ui.close()
	station("press_bench")
	ui.open("press")
	ui._sup_sel = ui._supply_kinds().find("ammo_slug")
	ui._refresh()
	check("prasa pokazuje odbiór już opłaconej dostawy", ui._s_action.text == tr("Collect ready delivery · %d rounds") % 5)
	ui.close()
	# rendery modeli 3D zamiast ikon (STATION_CARDS_PLAN.md E0): każdy rodzaj z modelem ma wypalony render, 40 mm zostaje przy ikonie (D3a)
	var ItemIcon := preload("res://scripts/item_icon.gd")
	var no_render: Array = []
	for k in Throwables.SHOP_ORDER:
		if ItemIcon.render_model(String(k)) != "" and ItemIcon.render_of(String(k)) == null:
			no_render.append(k)
	check("rendery przedmiotów: każdy rodzaj z modelem ma render %s" % str(no_render), no_render.is_empty())
	check("rendery przedmiotów: 40 mm bez modelu zostaje przy ikonie", ItemIcon.render_model("ammo_40buck") == "" and ItemIcon.render_model("frag") == "frag")
	station("pyro_bench")
	ui.open("pyro")
	var frag_tile: Control = ui._sup_tiles[ui._supply_kinds().find("frag")]
	check("kafel pirotechniki rysuje render modelu", ItemIcon.render_of(String(frag_tile.icon_node.kind)) != null and frag_tile.visible)
	# korpus kart (STATION_CARDS_PLAN.md E1): tabliczka, światło jako kursor, VU w skali HUD, stany dźwigni akcji
	check("tabliczka stanowiska: numer i radziecki numer inwentarzowy", ui._plate.code.text == "04" and ui._plate.sub.text.contains("86/0104") and ui._title.text == tr("PYROTECHNICS"))
	check("światło jako kursor: wybrany kafel w snopie lampy, reszta przygaszona", frag_tile.lit and frag_tile.icon_node.self_modulate == Color.WHITE
		and ui._sup_tiles.filter(func(t: Control) -> bool: return t.visible and t != frag_tile).all(func(t: Control) -> bool: return not t.lit and t.icon_node.self_modulate != Color.WHITE))
	check("VU granatu: +15 od ciszy, 3 naraz do niepokoju", ui._s_vu.visible and is_equal_approx(ui._s_vu_meter.value, NoiseMgr.N_GRENADE / 100.0) and ui._s_vu_text.text.contains(tr("%d at once = unease") % 3))
	var bank0 := Scrap.bank
	Scrap.bank = 0
	ui._refresh()
	check("dźwignia akcji bez złomu: stan „brak złomu”", String(ui._s_action.get_meta("dressed", "")) == "broke")
	Scrap.bank = 100000
	ui._refresh()
	check("dźwignia akcji ze złomem: stan „gotowe” (lampa)", String(ui._s_action.get_meta("dressed", "")) == "ready")
	Scrap.bank = bank0
	ui.close()
	var StationNoise := preload("res://scripts/station_noise.gd")
	check("StationNoise: progi skali = progi NoiseMgr (jak w HUD)", StationNoise.ticks().map(func(r: Array) -> float: return float(r[0])) == [NoiseMgr.SLEEP_THRESHOLD / 100.0, NoiseMgr.UNEASY_THRESHOLD / 100.0, NoiseMgr.AWAKE_THRESHOLD / 100.0])
	check("StationNoise: granat = N_GRENADE, mina i ładunek z danych przedmiotu", StationNoise.item_noise("frag") == NoiseMgr.N_GRENADE and StationNoise.item_noise("mine") == float(Throwables.KINDS["mine"]["noise"])
		and StationNoise.item_noise("scanner") == 0.0 and StationNoise.count_to(NoiseMgr.N_GRENADE, NoiseMgr.UNEASY_THRESHOLD) == 3)
	var m83 := Weapons.def_build(Weapons.M83, Weapons.build_of(0, 0))
	var m83_us := Weapons.def_build(Weapons.M83, Weapons.build_of(Ammo.from_kind("ammo_us")["t"], 0))
	var lv := StationNoise.mag_level(m83)
	var lv_us := StationNoise.mag_level(m83_us)
	# bez wygaszania magazynek dałby sumę hałasu strzałów; wygaszanie NoiseMgr.DECAY_LOUD przez czas magazynka musi ją obniżyć dokładnie o tyle
	var raw := 0.0
	var heat := 0.0
	for i in int(m83.mag):
		raw += m83.noise(heat)
		heat = minf(1.0, maxf(0.0, heat + m83.heat_gain - m83.heat_decay * m83.cooldown))
	check("StationNoise: magazynek M-83 %.1f (suma strzałów %.1f − wygaszanie %.1f/s), z US %.1f" % [lv, raw, NoiseMgr.DECAY_LOUD, lv_us],
		lv > 20.0 and lv < 45.0 and absf(lv - (raw - NoiseMgr.DECAY_LOUD * m83.cooldown * float(int(m83.mag) - 1))) < 2.5 and lv_us < lv)
	station("press_bench")
	ui.open("press")
	ui._sup_sel = ui._supply_kinds().find("ammo_us")
	ui._refresh()
	check("VU prasy: nabój poddźwiękowy ciszej niż zwykły (cień = zwykły)", ui._s_vu_meter.visible and ui._s_vu_meter.ghost > ui._s_vu_meter.value and ui._s_vu_meter.value > 0.0)
	ui._sup_sel = ui._supply_kinds().find("ammo_slug")
	ui._refresh()
	check("VU prasy: nabój bez zmiany hałasu — sam napis, bez miernika", ui._s_vu.visible and not ui._s_vu_meter.visible and ui._s_vu_text.text == tr("Shot noise unchanged."))
	check("taśma sterowania: klawisze w ramkach z rejestru akcji", ui._hint.text.contains("[bgcolor=") and ui._hint.text.contains(ui._menu_key("menu_back", false)))
	# prasa (STATION_CARDS_PLAN.md E2, ST-03): regał z półką na kaliber, etykieta partii z ząbkiem pod wybranym pudełkiem, matryce po prawej
	await frames(3)
	var press_tiles: Array = ui._sup_list().map(func(i: int) -> Control: return ui._sup_tiles[i])
	check("prasa: pudełka stoją na regale, półka na kaliber", ui._shelves.visible and ui._shelves.get_child_count() == 2
		and press_tiles.all(func(c: Control) -> bool: return ui._shelves.is_ancestor_of(c)) and not ui._sup_grid.visible and not ui._crate.visible)
	check("prasa: etykieta partii pod regałem, ząbek pod wybranym pudełkiem", ui._lid.get_parent() == ui._sup_left and ui._notch.target == ui._sup_tiles[ui._sup_sel] and ui._s_side.visible)
	check("prasa: matryce = miejsca na partie (%d), zajęte jak zamówienia" % Scrap.PRESS_SLOTS, ui._dies.visible and ui._dies_list.get_child_count() == Scrap.PRESS_SLOTS + 1 and not ui._s_queue.visible)
	var us: int = ui._supply_kinds().find("ammo_us")
	var hot: int = ui._supply_kinds().find("ammo_hot762")
	var slug: int = ui._supply_kinds().find("ammo_slug")
	check("prasa: strzałka w dół z 7.62 US na półkę 12/70 pod spodem", ui._spatial_step(ui._sup_tiles, ui._sup_list(), us, ui.COLS) == slug)
	check("prasa: strzałka w prawo z końca półki przechodzi na następną", ui._spatial_step(ui._sup_tiles, ui._sup_list(), hot, 1) == slug)
	ui.close()
	# stół pirotechniczny (E2, ST-04): skrzynia z przegrodami 4 × 2, karta w wieku, pokrętło zapalnika, lont, schemat działania w skali
	station("pyro_bench")
	ui.open("pyro")
	ui._sup_sel = ui._supply_kinds().find("frag")
	ui._refresh()
	await frames(3)
	var pyro_tiles: Array = ui._sup_list().map(func(i: int) -> Control: return ui._sup_tiles[i])
	check("pirotechnika: przedmioty w przegrodach skrzyni (4 w rzędzie), karta w wieku", ui._crate.visible and ui._crate_grid.columns == 4
		and pyro_tiles.all(func(c: Control) -> bool: return ui._crate_grid.is_ancestor_of(c)) and ui._lid.get_parent() != ui._sup_left and not ui._s_icon.visible)
	var dials: Array = ui._s_fuse.find_children("*", "Control", true, false).filter(func(c: Node) -> bool: return c.get_script() == SupplyArtRef.FuseDial)
	check("pirotechnika: pokrętło zapalnika na pozycji drużyny, lont o długości czasu", dials.size() == 1 and int(dials[0].index) == Scrap.fuse_index("frag")
		and ui._s_fuse.find_children("*", "Control", true, false).any(func(c: Node) -> bool: return c.get_script() == SupplyArtRef.FuseCord and is_equal_approx(float(c.seconds), Scrap.fuse_of("frag"))))
	check("pirotechnika: schemat wybuchu w skali z kolegą w zasięgu", ui._s_blast.visible and ui._s_blast.kind == "frag" and String(ui._s_blast.lines[1]) == tr("squad mate: hurt"))
	var charge: int = ui._supply_kinds().find("charge")
	check("pirotechnika: strzałka w dół z granatu na przegrodę pod nim", ui._spatial_step(ui._sup_tiles, ui._sup_list(), ui._sup_sel, ui.COLS) == charge)
	ui._sup_sel = ui._supply_kinds().find("ammo_40buck")
	ui._refresh()
	check("pirotechnika: 40 mm bez schematu wybuchu (inny ładunek)", not ui._s_blast.visible)
	ui.close()

## Układ każdego stanowiska i zakładki po angielsku i po polsku (etap 4 przeglądu UI, 1.7.409): karta na ekranie, żadna widoczna kontrolka
## nie wystaje w poziomie poza przodka, który ją przycina (przewijany korpus, karta) — dla każdego kafla, bo opisy i porównania zmieniają szerokość.
func _layout() -> void:
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	var keep := TranslationServer.get_locale()
	var bad: Array = []
	for loc in ["en", "pl"]:
		TranslationServer.set_locale(loc)
		for mode in ui.MODE_PAGES:
			station(String(ui.MODE_GROUP[mode]))
			await frames()
			ui.open(String(mode))
			for page in ui.MODE_PAGES[mode]:
				if String(mode) == "bench" and int(page) == 0:
					continue                                     # ława 3D: osobna kontrola w _immersive
				ui._set_page(int(page))
				var count: int = {0: ui._tiles.size(), 1: ui._sup_tiles.size(), 2: ui._perk_tiles.size(), 3: ui._look_tiles.size()}[int(page)]
				for i in count:
					var tiles: Array = [ui._tiles, ui._sup_tiles, ui._perk_tiles, ui._look_tiles][int(page)]
					if not (tiles[i] as Control).visible:
						continue
					match int(page):
						0: ui._select(i)
						1: ui._sup_sel = i
						2: ui._perk_sel = i
						3: ui._look_sel = i
					ui._refresh()
					for f in 3:
						await get_tree().process_frame
					_layout_check(ui, "%s %s/%d #%d" % [loc, mode, page, i], bad)
			ui.close()
	TranslationServer.set_locale(keep)
	check("układ stanowisk po angielsku i po polsku: karta na ekranie, nic nie wystaje%s" % ("" if bad.is_empty() else " — " + "; ".join(bad.slice(0, 6))), bad.is_empty())

func _layout_check(ui: Control, what: String, bad: Array) -> void:
	var card: Control = ui._card
	var cr := card.get_global_rect()
	var screen := Rect2(Vector2.ZERO, ui.get_viewport_rect().size).grow(1.0)
	if not screen.encloses(cr):
		bad.append("%s: karta %s poza ekranem %s" % [what, cr, screen])
		return
	for n in card.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x <= 0.0 or c is ScrollBar:
			continue
		var clip := card.get_global_rect()
		var pa := c.get_parent()
		while pa != null and pa != card:
			if pa is Control and ((pa as Control).clip_contents or pa is ScrollContainer):
				clip = (pa as Control).get_global_rect()
				break
			pa = pa.get_parent()
		var r := c.get_global_rect()
		if r.end.x > clip.end.x + 1.0 or r.position.x < clip.position.x - 1.0:
			var label := (c as Label).text.left(30) if c is Label else ((c as Button).text.left(30) if c is Button else c.get_class())
			var key := "%s: %s" % [what.split(" #")[0], label]
			if not bad.has(key):
				bad.append(key)
			return

## Rzeczywista konfiguracja, operacje serwera i sceny 3D — bez osobnego kalkulatora w makiecie.
func _immersive() -> void:
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	station("workshop")
	ui.open("bench")
	# Wyższa karta zaopatrzenia nie może zostać po powrocie na ławę 3D (skala 1,4) — panel wychodził w lewo i w górę poza ekran.
	ui._set_page(1)
	for i in 3:
		await get_tree().process_frame
	ui._set_page(0)
	for i in 3:
		await get_tree().process_frame
	var shown := Rect2(ui._card.position, ui._card.size * ui._card.scale)
	check("po stronie zaopatrzenia ława mieści się na ekranie %s w %s" % [shown, ui.size], Rect2(Vector2.ZERO, ui.size).grow(1.0).encloses(shown))
	ui._select(0)
	ui._inspect()
	ui._workbench._show_all = true
	ui._workbench._present_rack()
	(ui._workbench._rack.get_child(2) as Button).pressed.emit()
	check("przycisk nowego stojaka wybiera właściwą broń", ui._sel == 2 and ui._opt == -1)
	ui._select(0)
	ui._pick_slot("feed")
	(ui._workbench._parts.get_child(1) as Button).pressed.emit()
	check("karta na nowej tacy wybiera wariant bez zatwierdzania", ui._opt == ui._options(Weapons.M83).find({"slot": "feed", "id": "m83_rpk40"}))
	ui._inspect()
	var key := "m83"
	var bank: int = Scrap.bank
	var fit: int = Profile.fit_code(Weapons.M83)
	var stock: Dictionary = Arsenal.stock.duplicate()
	var loaded: Dictionary = wc.loaded.duplicate()
	var ops: Array = ui._options(Weapons.M83)
	ui._pick_opt(ops.find({"slot": "muzzle", "id": "m83_pbs1"}))
	check("podgląd nie zmienia profilu, banku, nabojów ani zapasu", Profile.fit_code(Weapons.M83) == fit and Scrap.bank == bank and Arsenal.stock == stock and wc.loaded == loaded)
	check("podgląd zachowuje pozostałe gniazda i aktualną amunicję", ui._d_stage._ids == Parts.decode(key, Parts.encode(key, _preview_choice(key, "muzzle", "m83_pbs1"))) and ui._workbench._payload["preview"])
	ui._inspect()
	check("oględziny przywracają prawdziwą konfigurację bez zapisu", ui._d_stage._ids == Parts.decode(key, fit) and ui._opt == -1 and Profile.fit_code(Weapons.M83) == fit)
	ui._pick_opt(ops.find({"slot": "feed", "id": "m83_drum75"}))
	var changes: Array = ui._workbench._payload["rows"]
	check("korzyść magazynka i kompromis masy są podpisane z danych konfiguracji", changes.any(func(row: Array) -> bool: return row[0] == tr("Magazine") and int(row[3]) > 0) and changes.any(func(row: Array) -> bool: return row[0] == tr("Mass") and int(row[3]) < 0))
	var details_key := InputEventKey.new()
	details_key.physical_keycode = KEY_V
	details_key.pressed = true
	ui._input(details_key)
	check("klawiatura otwiera pełne parametry bez montażu", ui._workbench._show_details and Profile.fit_code(Weapons.M83) == fit and Scrap.bank == bank)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press("menu_scroll_down")
	ui._workbench._process(0.5)
	Input.action_release("menu_scroll_down")
	check("karta parametrów przewija się akcją klawiatury / osi pada", ui._workbench._summary_scroll.scroll_vertical > 0)
	var details_pad := InputEventJoypadButton.new()
	details_pad.button_index = JOY_BUTTON_BACK
	details_pad.pressed = true
	ui._input(details_pad)
	check("pad wraca do głównych zmian na karcie", not ui._workbench._show_details)
	ui._workbench._summary_scroll.scroll_vertical = 0
	ui._inspect()
	var model: Node3D = ui._d_stage._model
	ui._pick_slot("feed")
	ui._inspect()
	check("samo podświetlenie gniazda nie przebudowuje modelu", ui._d_stage._model == model)
	ui._pick_opt(ops.find({"slot": "feed", "id": ""}))
	check("fabryczny element ma osobny podgląd i nie usuwa części bez akcji", Profile.fit_code(Weapons.M83) == fit and ui._opt >= 0)
	ui._inspect()
	# Ograniczenie ruchu jest lokalną prezentacją, nie ustawieniem symulacji.
	ui._workbench.stage.set_reduced_motion(true)
	ui._pick_opt(ops.find({"slot": "muzzle", "id": "m83_pbs1"}))
	ui._d_stage._process(0.5)
	check("ograniczony ruch zostawia gniazdo na miejscu", ui._d_stage._hl.all(func(item: Dictionary) -> bool: return (item["node"] as Node3D).position.is_equal_approx(item["base"])))
	ui._workbench.stage.set_reduced_motion(false)
	ui._inspect()
	ui._d_stage.size = Vector2(300, 150)
	ui._d_stage._fit_viewport()
	ui._d_stage._process(0.1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = ui._d_stage.slot_screen_position("feed")
	ui._d_stage._gui_input(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	ui._d_stage._gui_input(release)
	check("kliknięcie powierzchni magazynka wybiera jego gniazdo", ui._bench_slot == "feed" and ui._opt >= 0)
	ui._d_stage._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ui._d_stage._gui_input(motion)
	release.position = ui._d_stage.slot_screen_position("stock")
	ui._d_stage._gui_input(release)
	check("przeciągnięcie obraca broń bez kliknięcia innego gniazda przy puszczeniu", ui._bench_slot == "feed" and ui._d_stage._yaw != 0)
	ui._d_stage._yaw = 0
	ui._d_stage._pitch = 0
	ui._inspect()
	var all_models := true
	var all_slots := true
	var all_bounds := true
	var all_effects := true
	var all_rotations := true
	var all_anchors := true
	var distinct_fail: Array = []
	var sp12_barrel := false
	var shotgun: RefCounted = Weapons.base_def(Weapons.SPREAD12)
	check("wartość obrażeń śrutu korzysta z tłumaczenia karty", ui._comparison_rows(shotgun).any(func(row: Array) -> bool: return row[0] == tr("Damage") and row[1] == tr("%d × %d pellets") % [int(shotgun.damage), shotgun.pellets]))
	var unlocked: Dictionary = Scrap.unlocked.duplicate()
	for i in ui.LIST.size():
		var w := int(ui.LIST[i])
		Scrap.unlocked[w] = true
		ui._select(i)
		ui._d_stage.size = Vector2(300, 150)
		ui._d_stage._fit_viewport()
		ui._d_stage._process(0.1)
		all_models = all_models and ui._d_stage._model != null and ui._opt == -1
		var gun_key := String(Weapons.def(w).key)
		var metrics: Array = ui._comparison_rows(Weapons.def(w)).map(func(row: Array) -> String: return String(row[0]))
		for part in Parts.of(gun_key):
			for modifier in part["mods"]:
				if ui.PART_METRICS.has(String(modifier[0])):
					all_effects = all_effects and metrics.has(tr(String(ui.PART_METRICS[String(modifier[0])][0])))
		for slot in Parts.slots_of(gun_key):
			ui._pick_slot(String(slot))
			var point: Vector2 = ui._d_stage.slot_screen_position(String(slot))
			all_slots = all_slots and ui._bench_slot == slot and point.is_finite() and Rect2(Vector2.ZERO, ui._d_stage.size).has_point(point)
		# Gniazda bez własnego podzespołu nie dzielą jednego punktu (dawniej środek obrysu: u SPREAD-12 lufa wskazywała bęben).
		var anchors := {}
		for slot in Parts.slots_of(gun_key):
			anchors[String(slot)] = ui._d_stage.slot_screen_position(String(slot))
		for a in anchors:
			for b in anchors:
				if String(a) < String(b) and (anchors[a] as Vector2).distance_to(anchors[b]) < 2.0:
					all_anchors = false
					distinct_fail.append("%s %s/%s" % [gun_key, a, b])
			if ui._d_stage.slot_at(anchors[a]) != String(a):
				all_anchors = false
				distinct_fail.append("%s klik %s→%s" % [gun_key, a, ui._d_stage.slot_at(anchors[a])])
		if gun_key == "spread12":
			var barrel: Vector2 = anchors["barrel"]
			sp12_barrel = barrel.distance_to(anchors["muzzle"]) < barrel.distance_to(anchors["feed"])
		ui._d_stage._yaw = 0.65
		ui._d_stage._pitch = 0.45
		ui._d_stage._idle = 0
		ui._d_stage._process(0.1)
		var rotated: AABB = ui._d_stage._model.global_transform * GunStage.model_bounds(ui._d_stage._model)
		all_rotations = all_rotations and rotated.position.z > -0.455
		ui._d_stage._yaw = 0
		ui._d_stage._pitch = 0
		var builds: Array = [[]]
		for slot in Parts.slots_of(gun_key):
			var expanded: Array = []
			for ids in builds:
				expanded.append(ids.duplicate())
				for part in Parts.in_slot(gun_key, String(slot)):
					if GunModel.has_model(String(part["id"])):
						expanded.append(ids + [String(part["id"])])
			builds = expanded
		var frame: AABB = GunStage.stable_bounds(gun_key).grow(0.0001)
		for ids in builds:
			var probe := GunModel.build(gun_key, ids, Char3D.gun_info(gun_key)["muzzle"])
			all_bounds = all_bounds and frame.encloses(GunStage.model_bounds(probe))
			probe.free()
	Scrap.unlocked = unlocked
	check("nowa ława pokazuje wszystkie 12 rzeczywistych modeli", all_models)
	check("wszystkie gniazda mają dostępny wybór i kotwicę w kadrze", all_slots)
	check("każde gniazdo ma własny znacznik, a klik w znacznik wybiera to gniazdo %s" % str(distinct_fail), all_anchors)
	check("znacznik lufy SPREAD-12 leży przy lufie, nie na bębnie", sp12_barrel)
	check("stały kadr obejmuje wszystkie kombinacje części z modelami", all_bounds)
	check("pełna karta obejmuje dodatkowe efekty części każdej broni", all_effects)
	check("obrót żadnej broni nie chowa jej wewnątrz blatu", all_rotations)
	ui._select(0)
	ui._inspect()
	var right := InputEventKey.new()
	right.physical_keycode = KEY_RIGHT
	right.pressed = true
	ui._input(right)
	check("strzałka wybiera gniazdo z tego samego rejestru co mysz", ui._bench_slot == "barrel")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.pressed = true
	ui._input(pad)
	check("pad wybiera wariant w aktywnym gnieździe", String(ui._options(Weapons.M83)[ui._opt]["slot"]) == "barrel" and ui._opt >= 0)
	ui._inspect()
	# Odpowiedź opóźniona: UI może zmienić zaznaczenie, profil kupującego aktualizuje Scrap.
	ui._pending_part = {"id": "m83_pbs1", "w": Weapons.M83, "fit": Profile.fit_code(Weapons.M83), "session": ui._session, "revision": ui._selection_revision}
	var fits: Dictionary = Profile.fits.duplicate(true)
	ui._pick_opt(ui._options(Weapons.M83).find({"slot": "barrel", "id": "m83_short"}))
	ui._act()
	check("oczekujące żądanie blokuje drugą operację także po zmianie kursora", Scrap.bank == bank and Profile.fits == fits)
	ui._select(ui.LIST.find(Weapons.SPREAD12))
	Scrap.parts["m83_pbs1"] = true
	Scrap._part_done("m83_pbs1", "ok")
	check("opóźniony wynik nie animuje ani nie przekłada części nowo oglądanej broni", ui._pending_part.is_empty() and ui._d_stage._weapon == Weapons.SPREAD12 and ui._d_stage._mount_time < 0 and Profile.fitted(key, "muzzle") == "m83_pbs1")
	ui._select(0)
	ui._pending_part = {"id": "m83_hider", "w": Weapons.M83, "fit": Profile.fit_code(Weapons.M83), "session": ui._session, "revision": ui._selection_revision}
	ui.close()
	ui.open("bench")
	Scrap.parts["m83_hider"] = true
	Scrap._part_done("m83_hider", "ok")
	check("zamknięcie i ponowne otwarcie nie odtwarza spóźnionej animacji", ui._pending_part.is_empty() and ui._d_stage._mount_time < 0 and Profile.fitted(key, "muzzle") == "m83_hider")
	ui._select(0)
	ui._inspect()
	Scrap.parts.erase("m83_short")
	Scrap.found.erase("m83_short")
	Scrap.bank = 0
	fit = Profile.fit_code(Weapons.M83)
	ui._pick_opt(ui._options(Weapons.M83).find({"slot": "barrel", "id": "m83_short"}))
	ui._act()
	check("odmowa serwera usuwa oczekiwanie bez montażu i animacji", ui._pending_part.is_empty() and Profile.fit_code(Weapons.M83) == fit and ui._d_stage._mount_time < 0 and ui._action.disabled)
	Scrap.bank = 4000
	bank = Scrap.bank
	ui._act()
	var after: int = Profile.fit_code(Weapons.M83)
	check("udany zakup rozlicza raz i rozpoczyna prezentację dopiero po wyniku", ui._pending_part.is_empty() and Scrap.bank == bank - Scrap.part_cost("m83_short") and after != fit and ui._d_stage._mount_time == 0)
	var paid: int = Scrap.bank
	ui._d_stage._process(0.56)
	var on_tray := false
	for item in ui._d_stage._mount_nodes:
		if bool(item["old"]):
			var center: Vector3 = (item["node"] as Node3D).to_global(item["center"])
			on_tray = on_tray or ui._d_stage._table.to_local(center).distance_to(Vector3(0.69, -0.47, -0.32)) < 0.03
	check("animacja odkłada stary podzespół na fizyczną tacę", on_tray and Profile.fit_code(Weapons.M83) == after and Scrap.bank == paid)
	ui._d_stage._process(1.0)
	check("koniec animacji nie zapisuje ani nie rozlicza operacji ponownie", Profile.fit_code(Weapons.M83) == after and Scrap.bank == paid and ui._d_stage._mount_time < 0 and ui._d_stage._outgoing == null)
	ui._pick_slot("preset")
	ui._save_current_preset()
	check("zestawy zapisują aktualny montaż, nie podgląd", Profile.is_preset_fitted(key, 0))
	ui._pick_opt(ui._options(Weapons.M83).find({"slot": "barrel", "id": ""}))
	ui._act()
	check("montaż posiadanej / fabrycznej części uruchamia tę samą prezentację", ui._d_stage._mount_time == 0 and Scrap.bank == paid and Profile.fitted(key, "barrel") == "")
	ui.close()
	check("zamknięcie przerywa efekt i wyłącza ukryte viewporty", ui._workbench.stage._outgoing == null and ui._workbench.stage._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and ui._legacy_stage._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	await frames(3) # obsługa odroczonego przewijania po wymianie i usunięciu wierszy

func _preview_choice(key: String, slot: String, id: String) -> Dictionary:
	var choice := {}
	for s in Parts.slots_of(key):
		choice[s] = id if s == slot else Profile.fitted(key, String(s))
	return choice

## PROGRESSION_PLAN.md P1: postęp kampanii drużyny i wybór misji przy tablicy odpraw (P1.1), pełne XP na karcie wyniku (P1.2), próbki bez broni
## specjalnej (P1.3). Ostatni krok: tablica stoi w strefie startu, więc gracz schodzi z niej, zanim odliczanie wyprowadzi drużynę z kryjówki.
func _progression() -> void:
	if main.level.map_id != "z1_hub":
		main._set_map("z1_hub")
		await frames(3)
	var peer := NoiseMgr.local_id()
	Scrap.cleared.clear()
	check("kampania bez postępu: start od 1.1, do wyboru tylko 1.1", main.campaign_start_map() == "z1_m1" and main.campaign_unlocked() == ["z1_m1"])
	Scrap.add_cleared("z1_m1")
	Scrap.add_cleared("z1_m2")
	check("po 1.1 i 1.2: start od 1.3, do wyboru 1.1–1.3", main.campaign_start_map() == "z1_m3" and main.campaign_unlocked() == ["z1_m1", "z1_m2", "z1_m3"])
	main.after_hub = "z1_m3"
	station("workshop")
	await frames(2)
	check("zmiana misji z dala od tablicy odrzucona", not main._brief_cycle_server(peer) and main.after_hub == "z1_m3")
	station("board")
	await frames(2)
	var first_ok: bool = main._brief_cycle_server(peer)
	var first := String(main.after_hub)
	var second_ok: bool = main._brief_cycle_server(peer)
	check("tablica odpraw: 1.3 → 1.1 → 1.2 (%s, %s)" % [first, main.after_hub], first_ok and first == "z1_m1" and second_ok and main.after_hub == "z1_m2")
	check("obcy nadawca nie zmienia misji", not main._brief_cycle_server(987654321) and main.after_hub == "z1_m2")
	main.hub_countdown = 1.0
	main._brief_cycle_server(peer)
	check("zmiana misji odnawia odliczanie wyjścia (%.1f s)" % main.hub_countdown, main.after_hub == "z1_m3" and main.hub_countdown >= main.HUB_COUNTDOWN - 0.05)
	station("workshop")
	await frames(2)
	main.hub_countdown = -1.0
	Scrap.persist = true
	var path := "user://workshop_campaign_test.cfg"
	Scrap.save_progress(path)
	Scrap.persist = false
	var cfg := ConfigFile.new()
	cfg.load(path)
	var saved: Array = Array(cfg.get_value("campaign", "cleared", []))
	check("postęp kampanii w zapisie hosta (%s)" % str(saved), saved.has("z1_m1") and saved.has("z1_m2") and saved.size() == 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Scrap.add_cleared("z1_m3")
	Scrap.add_cleared("z1_b1")
	check("po bossie: start znowu od 1.1, do wyboru cała Strefa I", main.campaign_start_map() == "z1_m1" and main.campaign_unlocked().size() == 4)
	# P1.2: karta wyniku liczy XP za zabójstwa i podniesienia razem z wynikiem misji
	Profile.reset_for_test()
	Profile.add_xp(12, "Kill")
	Profile.add_xp(Profile.XP_REVIVE, "Revive")
	var mission_xp := Profile.apply_mission_result("z1_m1", false, false, false)
	check("XP na karcie: wynik %d + zabójstwa i podniesienia %d" % [Profile.last_mission_xp, Profile.last_run_xp],
		mission_xp == Profile.XP_MISSION + Profile.XP_FIRST_CLEAR and Profile.last_run_xp == 12 + Profile.XP_REVIVE and Profile.run_xp == 0
		and Profile.xp == mission_xp + Profile.last_run_xp)
	# P1.3: próbki bez broni specjalnej mówią, czego brakuje
	var had_lab: bool = Scrap.has_lab_weapon()
	Scrap.unlocked.clear()
	check("broń specjalna do badań: po zakupie LR-7 tak (%s), bez zakupów nie (%s)" % [had_lab, Scrap.has_lab_weapon()], had_lab and not Scrap.has_lab_weapon())

## Czyszczenie przy stole konserwacji: rozłożona broń (GunStage.set_strip) mieści się w podglądzie — każda broń z modelem, fabryczna i z najdłuższą
## częścią w każdym gnieździe, w dwóch proporcjach podglądu, po wygaśnięciu kołysania (dawniej bęben M-83 wychodził dołem, tłumik bokiem).
func _strip_frame() -> void:
	var stage: Control = GunStage.new()
	get_tree().root.add_child(stage)
	var worst := ""
	var worst_px := 0.0
	var cases := 0
	for aspect_size in [Vector2(600, 225), Vector2(640, 200)]:
		stage.size = aspect_size
		for w in Weapons.COUNT:
			var key := String(Weapons.def(w).key)
			if not ResourceLoader.exists(GunModel.DIR + "gun_%s.glb" % key):
				continue
			for ids in [[], _longest_parts(key)]:
				stage.set_strip(false)
				stage.show_gun(w, ids, "", "", false)
				stage.set_strip(true)
				await get_tree().create_timer(0.9).timeout
				stage.set("_idle", 3.0)
				for a in GunStage.STRIP_POSES:
					stage.set("_yaw", (a as Vector2).x)
					stage.set("_pitch", (a as Vector2).y)
					stage._process(0.0)
					var out := _outside_px(stage)
					cases += 1
					if out > worst_px:
						worst_px = out
						worst = "%s %s %s" % [key, ",".join(ids), str(aspect_size)]
	check("rozłożona broń w kadrze czyszczenia (%d ujęć; najgorsze %.1f px poza: %s)" % [cases, worst_px, worst if worst != "" else "—"], cases > 0 and worst_px <= 1.0)
	stage.queue_free()

## Po jednej części z modelem na gniazdo — ta o najdłuższej bryle (bęben, długa lufa, tłumik): najtrudniejszy kadr.
func _longest_parts(key: String) -> Array:
	var best := {}
	for part in Parts.of(key):
		var id := String(part["id"])
		if not GunModel.has_model(id):
			continue
		var probe := GunModel.build(key, [id], Char3D.gun_info(key)["muzzle"])
		var span := GunStage.model_bounds(probe).size.length()
		probe.free()
		var slot := String(part["slot"])
		if not best.has(slot) or span > float(best[slot][1]):
			best[slot] = [id, span]
	var ids := []
	for slot in best:
		ids.append(best[slot][0])
	return ids

## Ile pikseli podglądu (najwięcej) wystaje któryś wierzchołek obrysu siatek modelu poza obraz SubViewport.
func _outside_px(stage: Control) -> float:
	var model: Node3D = stage.get("_model")
	var cam: Camera3D = stage.get("_camera")
	var vp: SubViewport = stage.get("_vp")
	if model == null or cam == null:
		return 0.0
	var size := Vector2(vp.size)
	var out := 0.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		for i in 8:
			var p := cam.unproject_position((mi as Node3D).global_transform * box.get_endpoint(i))
			out = maxf(out, maxf(maxf(-p.x, p.x - size.x), maxf(-p.y, p.y - size.y)))
	return out

## Stół konserwacji (K3, 1.7.413): zalecenie na górze karty i kursor na zalecanym wierszu, lista „do zrobienia” pod kaflami, ikonki wymian
## na kafelku, skutek wymiany na przycisku, wygaszony przycisk poniżej progu.
## Zdarzenie klawisza przypisanego do akcji menu (pierwszy klawisz z InputMap) — panel czyta tylko klawiaturę i pad, nie InputEventAction.
func _key_event(action: String, pressed: bool) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var e := (ev as InputEventKey).duplicate() as InputEventKey
			e.pressed = pressed
			return e
	return null

func _service_card() -> void:
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	station("service_bench")
	Profile.cond = {"m83": 90.0}
	Profile.worn = {"m83": {"springs": 65.0, "barrel": 10.0}}
	ui.open("service")
	ui._sel = ui.LIST.find(Weapons.M83)
	ui._opt = ui._first_part_opt()
	ui._refresh()
	var adv: Dictionary = ui._service_advice(Weapons.M83)
	var ops: Array = ui._options(Weapons.M83)
	var top: Label = ui._d_panel.get_child(0) as Label
	check("zalecenie: zmęczone sprężyny (czyszczenie do 67%%) są pilne, kursor na ich wierszu: %s" % str(adv),
		int(adv.get("level", -9)) == 2 and String(adv.get("id", "")) == "springs" and String(ops[ui._opt]["id"]) == "springs" and top != null and top.text == String(adv["text"]))
	var tile = ui._tiles[ui._sel]
	check("kafel M-83: ikonka sprężyn zapalona, lufy nie", tile.marks != null and tile.marks.visible and tile.marks.springs == 1 and tile.marks.barrel == 0)
	check("lista do zrobienia pod kaflami wymienia M-83: %s" % ui._svc_todo.text.replace("
", " / "),
		ui._svc_todo.visible and ui._svc_todo.text.contains("M-83 — " + tr("replace springs")))
	check("przycisk wymiany sprężyn podaje skutek: %s" % ui._action.text, not ui._action.disabled and ui._action.text.contains("→ 100%"))
	ui._pick_opt(ops.find({"slot": "service", "id": "barrel"}))
	check("lufa zużyta w 10%%: przycisk wygaszony z progiem: %s" % ui._action.text, ui._action.disabled and ui._action.text.contains(str(int(Profile.SERVICE_DUE))))
	# E3 (ST-02): karta znika, trzy przyrządy z manometrem, kartka do zrobienia, w lewo / w prawo = przyrząd, przytrzymanie czyszczenia
	check("konserwacja: trzy przyrządy, wybrany pod lampą, karta bez papieru", ui._gauges.size() == 3 and ui._gauges["barrel"].dial.lit
		and not ui._gauges["clean"].dial.lit and bool(ui._arms_paper.get_meta("service", false)) and not ui._d_tiers.visible)
	check("konserwacja: stan 90%% na tarczy, cień do limitu %d%%, kropka lampy na limicie" % int(Profile.clean_cap("m83")),
		is_equal_approx(ui._gauges["clean"].dial.value, 0.9) and is_equal_approx(ui._gauges["clean"].dial.mark, Profile.clean_cap("m83") / 100.0)
		and is_equal_approx(ui._gauges["springs"].dial.value, 0.65) and ui._gauges["springs"].dial.ghost == 0.0)
	check("konserwacja: lista do zrobienia na kartce odręcznej", ui._svc_note.visible and ui._svc_note is ServiceArtRef.Scrawl)
	var left_ev := _key_event("menu_left", true)
	var opt0: int = ui._opt
	ui._input(left_ev)
	check("konserwacja: strzałka w lewo przechodzi na poprzedni przyrząd", ui._opt == opt0 - 1 or ui._opt == 0)
	ui._pick_opt(ops.find({"slot": "service", "id": "clean"}))
	Profile.cond = {"m83": 50.0}
	ui._refresh()
	var acc_down := _key_event("menu_accept", true)
	var acc_up := _key_event("menu_accept", false)
	if acc_down != null:
		ui._input(acc_down)
		var started: bool = ui._clean_w == Weapons.M83 and ui._hold_clean
		ui.tick_clean(0.5)
		var moved: bool = ui._gauges["clean"].dial.value > 0.5
		ui._input(acc_up)
		check("konserwacja: przytrzymanie czyści (wskazówka idzie), puszczenie przerywa", started and moved and ui._clean_w < 0 and not ui._hold_clean and is_equal_approx(Profile.condition("m83"), 50.0))
	Profile.cond = {}
	Profile.worn = {}
	ui._refresh()
	check("broń sprawna: zalecenie bez pracy, lista pusta", int(ui._service_advice(Weapons.M83)["level"]) == -1 and ui._svc_todo.text.contains(tr("All guns in good order.")))
	ui.close()
	check("lista do zrobienia tylko na stole konserwacji", not ui._svc_todo.visible or not ui._open)
	# E3 (ST-07): szafka — drzwi, książeczka z pieczątkami poziomów, zdjęcie, naszywki ze ściegiem, zablokowany perk w folii, rzepy
	station("locker_station")
	ui.open("locker")
	ui._perk_sel = Perks.ORDER.find("quiet_steps")
	ui._refresh()
	var veteran = ui._perk_tiles[Perks.ORDER.find("veteran")]
	check("szafka: pieczątki poziomów = poziom profilu (%d), zdjęcie wyglądu" % Profile.level(), ui._book_stamps.level == Profile.level() and ui._book_photo.tex != null)
	check("szafka: naszywki ze ściegiem, zablokowany perk w folii", ui._perk_tiles.all(func(t) -> bool: return t.has_meta("stitch"))
		and bool(veteran.get_meta("stitch").foil) == not Profile.is_unlocked("veteran"))
	var prow: Array = ui._p_stats.get_children().map(func(c: Node) -> String: return (c as Label).text if c is Label else "")
	check("szafka: Ciche kroki — wiersz biegu z mnożnikiem, bez VU (bieg nie przebija wygaszania)", prow.has(tr("Running")) and prow.any(func(s: String) -> bool: return s.contains("×0")) and not ui._p_vu.visible)
	ui._perk_sel = Perks.ORDER.find("cold_blood")
	ui._refresh()
	check("szafka: Zimna krew — VU krzyku %d%% → %d%% (cień = bez perka)" % [int(NoiseMgr.N_SCREAM), int(Perks.PERKS["cold_blood"]["params"]["scream_cap"])],
		ui._p_vu.visible and is_equal_approx(ui._p_vu_meter.ghost, NoiseMgr.N_SCREAM / 100.0) and ui._p_vu_meter.value < ui._p_vu_meter.ghost)
	ui.close()
