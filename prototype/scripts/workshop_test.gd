extends Node
## Regresje warsztatu na rzeczywistym graczu i stanowiskach: --host --workshoptest.
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Controller := preload("res://scripts/weapon_controller.gd")
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
		get_tree().quit(1)
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
	print("[WORKSHOP-TEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	get_tree().quit(1 if failed else 0)

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
	check("podgląd części pokazuje zmiany zamiast niezmienionych statystyk", labels.has("Magazine") and not labels.has("Damage"))
	check("odblokowane części odróżnione od zamontowanych", ui._d_tag.text.contains("UNLOCKED") and ui._d_tag.text.contains("FITTED"))
	check("długi panel mieści się w przewijanym korpusie", ui._arms_body.get_parent() is ScrollContainer)
	check("główna akcja pozostaje poza przewijaną treścią", ui._action.get_parent() == ui._arms_body.get_parent().get_parent() and ui._action.visible)
	ui.close()
	station("press_bench")
	ui.open("press")
	ui._sup_sel = ui._supply_kinds().find("ammo_slug")
	ui._refresh()
	check("prasa pokazuje odbiór już opłaconej dostawy", ui._s_action.text == tr("Collect ready delivery · %d rounds") % 5)
	ui.close()
