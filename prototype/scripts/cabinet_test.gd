extends Node
## Regresje prawdziwych gablot: --host --cabinettest; dwa procesy ENet: --cabinetnet.
const Weapons := preload("res://scripts/weapons.gd")
const Inspector := preload("res://scripts/weapon_inspect.gd")
const Codex := preload("res://scripts/codex.gd")
const Pickup := preload("res://scripts/pickup.gd")
var total := 0
var failed := 0
var main: Node
var level: Node
var player: Node2D
var wc: Node
var _drive_input := false
var _stage := ""
var _net_done := false

func check(label: String, ok: bool) -> void:
	total += 1
	failed += 0 if ok else 1
	print("[CABINET-TEST] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame

func wait(s := 0.4) -> void:
	await get_tree().create_timer(s).timeout

func _physics_process(_delta: float) -> void:
	if _drive_input:
		wc._tick_inspect()

func pulse(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames()

func item(w: int, cabinet := true) -> Node2D:
	for n in get_tree().get_nodes_in_group("pickups"):
		if n.get("kind") == "weapon" and int(n.arg) == w and n.has_meta("cabinet") == cabinet and not n.is_queued_for_deletion():
			return n
	return null

func loose(w: int) -> Array:
	return get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool:
		return n.get("kind") == "weapon" and int(n.arg) == w and not n.has_meta("cabinet") and not n.is_queued_for_deletion())

func run(m: Node, network := false) -> void:
	main = m
	level = m.level
	Profile.persist = false
	Scrap.persist = false
	await wait(1.5)
	if network:
		if NoiseMgr.is_server():
			await _net_host()
		else:
			await _net_client()
	else:
		await _unit()
	print("[CABINET-TEST] ==== %d/%d OK, błędów: %d ====" % [total - failed, total, failed])
	Audio.quit_game(1 if failed else 0)

func _unit() -> void:
	player = main.get_node("Players/1")
	wc = player.weapons
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			p.queue_free()
	Profile.reset_for_test()
	Scrap.load_progress()
	_drive_input = true
	var cabinets := get_tree().get_nodes_in_group("cabinets")
	check("dwie rzeczywiste gabloty po cztery rzędy", level.map_id == "z1_hub" and cabinets.size() == 2 and level.cabinet_rows(0).size() == 4 and level.cabinet_rows(1).size() == 4)
	for cabinet in cabinets:
		for side in [-20, 20]:
			player.global_position = cabinet.global_position + Vector2(side, -2)
			wc.inspect_item = null
			await pulse("inspect_weapon")
			check("H otwiera gablotę %d z boku %d" % [cabinet.index, side], wc.inspect_item != null)
			for row in 4:
				wc.select_cabinet_slot(row)
				await frames()
				check("gablota %d bok %d rząd %d pozostaje w zasięgu" % [cabinet.index, side, row], wc.inspect_item != null and int(wc.inspect_item.get_meta("slot")) == row)
	# 1.7.431: [E] (pad [B]) przy zamkniętej gablocie ją otwiera, niczego nie biorąc; start zawsze na pierwszej broni do wzięcia, z każdego miejsca
	var starts: Array = []
	var kit0: Array = wc.loadout.duplicate()
	for side in [-20, -6, 6, 20]:
		player.global_position = (cabinets[0] as Node2D).global_position + Vector2(side, -2)
		wc.inspect_item = null
		await pulse("interact")
		starts.append(String(wc.inspect_item.name) if wc.inspect_item != null else "")
	check("E przy gablocie otwiera ją, nic nie bierze, start zawsze ten sam (%s)" % str(starts),
		not starts.has("") and starts.count(starts[0]) == starts.size() and wc.loadout == kit0 and not level.is_locked_item(wc.inspect_item))
	# Esc / Start (akcja pause) zamyka oględziny i nie otwiera menu pauzy
	var pm: Node = main.get_node("UI/PauseMenu")
	player.process_mode = Node.PROCESS_MODE_INHERIT
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames()
	var esc_up := InputEventAction.new()
	esc_up.action = "pause"
	Input.parse_input_event(esc_up)
	await frames()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	check("Esc / Start zamyka oględziny gabloty bez menu pauzy", wc.inspect_item == null and not bool(pm.get("_open")))
	var cab: Node2D = cabinets[0]
	player.global_position = cab.global_position + Vector2(-20, -2)
	wc.inspect_item = item(Weapons.SPREAD12)
	await pulse("menu_down")
	check("akcja pada przechodzi do następnego rzędu", int(wc.inspect_item.get_meta("slot")) == 1)
	await pulse("menu_up")
	check("akcja pada wraca do poprzedniego rzędu", int(wc.inspect_item.get_meta("slot")) == 0)
	await pulse("menu_slot_2")
	check("wybór slotu 2 nie zmienia broni w ręku", wc.inspect_slot == 1 and wc.slot == 0)
	await pulse("menu_slot_1")
	check("wybór slotu 1", wc.inspect_slot == 0)
	var locked: Node2D = item(Weapons.SRUT8)
	wc.inspect_item = locked
	await pulse("interact")
	check("odmowa blokady zachowuje otwartą inspekcję", wc.inspect_item == locked and not locked.is_queued_for_deletion())
	player.hp -= 1
	await frames()
	check("trafienie zamyka inspekcję", wc.inspect_item == null)
	player.hp += 1
	wc.inspect_item = locked
	player.global_position.x += 100
	await frames()
	check("odejście zamyka inspekcję", wc.inspect_item == null)
	var locked_name: String = locked.name
	var kit: Array = wc.loadout.duplicate()
	level.request_weapon_pickup(locked_name, 1)
	await frames()
	check("serwer odrzuca zablokowaną broń", is_instance_valid(locked) and wc.loadout == kit)
	Scrap.unlocked[Weapons.SRUT8] = true
	level.request_weapon_pickup(locked_name, 1)
	await frames()
	check("serwer odrzuca odległe podniesienie", is_instance_valid(locked) and wc.loadout == kit)
	player.global_position = cab.global_position + Vector2(-20, -2)
	player.dead = true
	level.request_weapon_pickup(locked_name, 1)
	player.dead = false
	player.in_range = true
	level.request_weapon_pickup(locked_name, 1)
	player.in_range = false
	level.request_weapon_pickup(locked_name, 2)
	level.request_weapon_pickup(locked_name, -2)
	level.request_weapon_pickup("../Players/1", 0)
	await frames()
	check("martwy gracz, strzelnica i nieprawidłowe argumenty nie pobierają broni", is_instance_valid(locked) and wc.loadout == kit)
	var inspector := Inspector.new()
	add_child(inspector)
	inspector.size = Vector2(640, 360)
	wc.loaded[Weapons.M83] = 1
	wc.inspect_item = locked
	wc.inspect_slot = 0
	inspector.show_weapon(Weapons.SRUT8, "srut8", Weapons.M83, "", "", true, wc, locked)
	check("porównanie uwzględnia specjalny nabój", inspector._comparison_def.damage == wc.def_of(Weapons.M83).damage and inspector._comparison_def.ammo == 1)
	# wiersze (1.7.431): zablokowana z warunkiem (cena), wybrana z wyraźnym znacznikiem i własnym tłem
	var row_txt: Array = inspector._rows.get_children().map(func(b: Node) -> String: return String((b as Button).text))
	var sel_rows: Array = inspector._rows.get_children().filter(func(b: Node) -> bool: return (b as Button).has_theme_stylebox_override("normal"))
	check("wiersze: zablokowana z ceną, jeden wybrany z tłem (%s)" % str(row_txt),
		row_txt.any(func(t: String) -> bool: return t.contains("Locked ·") and t.contains("scrap")) and sel_rows.size() == 1 and String((sel_rows[0] as Button).text).begins_with("▶"))
	var expected: String = Codex._weapon_stats(wc.def_of(Weapons.M83))[0][1]
	check("kolumna obrażeń pokazuje rzeczywistą wartość", inspector._grid.get_child(5).text == expected)
	wc.loaded[Weapons.M83] = 0
	inspector.show_weapon(Weapons.SRUT8, "srut8", Weapons.M83, "", "", true, wc, locked)
	check("zmiana amunicji odświeża porównanie bez zmiany rzędu", inspector._grid.get_child(5).text == Codex._weapon_stats(wc.def_of(Weapons.M83))[0][1])
	Scrap.parts["m83_rpk40"] = true
	Profile.set_fit("m83", "feed", "m83_rpk40")
	inspector.show_weapon(Weapons.SRUT8, "srut8", Weapons.M83, "", "", true, wc, locked)
	check("zmiana części odświeża konfigurację porównywanej broni", inspector._comparison_def.fit == wc.fit_of(Weapons.M83) and inspector._comparison_def.mag == wc.def_of(Weapons.M83).mag)
	inspector._slot_buttons.get_child(1).pressed.emit()
	check("przycisk myszy wybiera slot 2", wc.inspect_slot == 1)
	inspector._rows.get_child(0).pressed.emit()
	check("przycisk myszy wybiera rząd", int(wc.inspect_item.get_meta("slot")) == 0)
	wc.inspect_item = locked
	wc.mags[Weapons.SPREAD12] = 7
	wc.loaded[Weapons.SPREAD12] = 1
	Arsenal.set_reserve(Weapons.SPREAD12, 0, 1)
	Arsenal.set_reserve(Weapons.SPREAD12, 0, 0)
	Arsenal.set_reserve(Weapons.SRUT8, 0)
	var allotment: int = locked.rounds
	await pulse("interact")
	check("rząd przy skraju gabloty zastępuje wyłącznie slot 2", wc.loadout[0] == Weapons.M83 and wc.loadout[1] == Weapons.SRUT8 and wc.slot == 0)
	check("pobranie przydziela rzeczywiste naboje przedmiotu", Arsenal.get_reserve(Weapons.SRUT8) == allotment)
	check("magazynek starej broni wraca jako specjalna amunicja", Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7 and Arsenal.get_reserve(Weapons.SPREAD12, 0) == allotment)
	check("serwer odkłada jedną broń bez przydziału nabojów", loose(Weapons.SPREAD12).size() == 1 and item(Weapons.SPREAD12, false).rounds == 0)
	check("wspólny rząd pamięta odbiorcę", level._cabinet_issued.get(locked_name, "") == "P1" and cab.issued.get(1, "") == "P1")
	level.request_weapon_pickup(locked_name, 1)
	await frames()
	check("duplikat nie zwiększa zapasu ani liczby porzuconych broni", Arsenal.get_reserve(Weapons.SRUT8) == allotment and loose(Weapons.SPREAD12).size() == 1)
	var dropped: Node2D = item(Weapons.SPREAD12, false)
	player.global_position = dropped.global_position + Vector2(0, -2)
	wc.inspect_item = dropped
	inspector._take.pressed.emit()
	await frames()
	check("przycisk pobrania zwraca porzuconą broń bez świeżych nabojów", wc.loadout[1] == Weapons.SPREAD12 and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7 and Arsenal.get_reserve(Weapons.SPREAD12, 0) == allotment)
	for i in 3:
		var w := Weapons.SRUT8 if i % 2 == 0 else Weapons.SPREAD12
		dropped = item(w, false)
		player.global_position = dropped.global_position + Vector2(0, -2)
		level.request_weapon_pickup(dropped.name, 1)
		await frames()
	check("wielokrotna zamiana nie tworzy amunicji", Arsenal.get_reserve(Weapons.SRUT8) == allotment and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7 and Arsenal.get_reserve(Weapons.SPREAD12, 0) == allotment)
	level._drop_rpc(Weapons.LR7, player.global_position)
	await frames()
	check("fałszywe żądanie porzucenia niczego nie tworzy", loose(Weapons.LR7).is_empty())
	# Symulacja odtworzenia mapy klienta po późniejszym dołączeniu.
	var snapshot: Dictionary = level._cabinet_issued.duplicate()
	level.clear_pickups()
	await frames()
	check("restart przywraca wszystkie egzemplarze i czyści etykiety", level._cabinet_issued.is_empty() and cab.issued.is_empty() and item(Weapons.SRUT8) != null)
	level._cabinet_state_rpc(snapshot)
	await frames()
	check("snapshot usuwa pobrany egzemplarz u dołączającego", item(Weapons.SRUT8) == null and cab.issued.get(1, "") == "P1")
	_drive_input = false
	inspector.queue_free()
	main._restart_mission(false)
	await frames(6)
	check("wipe resetuje zestaw i wydane egzemplarze", wc.kit() == Vector3i(Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_MELEE) and level._cabinet_issued.is_empty())
	level.load_map("z1_m2")
	level.load_map("z1_hub")
	await frames()
	check("powrót do kryjówki przywraca rzędy", item(Weapons.SRUT8) != null and level._cabinet_issued.is_empty())
	await _hook_and_switch()

## 1.7.432: broń z gabloty wraca na hak przy zamianie w gablocie, startowa ląduje obok gablot (poza ich [E]), [A] / [D] zmienia gablotę,
## a karta broni i cel misji znikają w oględzinach gabloty.
func _hook_and_switch() -> void:
	_drive_input = true
	var cabinets: Array = get_tree().get_nodes_in_group("cabinets")
	cabinets.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get("index")) < int(b.get("index")))
	var cab0: Node2D = cabinets[0]
	var cab1: Node2D = cabinets[1]
	Scrap.unlocked[Weapons.SRUT8] = true
	Scrap.unlocked[Weapons.LR7] = true
	player.global_position = cab0.global_position + Vector2(-6, -2)
	wc.inspect_item = item(Weapons.SRUT8)
	wc.inspect_slot = 0
	await pulse("interact")
	var start_drop: Array = loose(Weapons.M83)
	var far := not start_drop.is_empty()
	for c in cabinets:
		for n in start_drop:
			far = far and (n as Node2D).global_position.distance_to((c as Node2D).global_position) > Pickup.WEAPON_R
	check("broń startowa oddana przy gablocie leży obok gablot, poza ich zasięgiem (%s)" % str(start_drop.map(func(n: Node) -> Vector2: return (n as Node2D).global_position)),
		wc.loadout[0] == Weapons.SRUT8 and start_drop.size() == 1 and far and level.weapon_item_near(player.global_position + Vector2(0, -8)) != start_drop[0])
	wc.inspect_item = item(Weapons.LR7)
	wc.inspect_slot = 0
	await pulse("interact")
	var back: Node2D = item(Weapons.SRUT8)
	check("broń z gabloty wraca na swój hak przy zamianie (bez przydziału nabojów), rząd znów wolny",
		wc.loadout[0] == Weapons.LR7 and back != null and int(back.rounds) == 0 and loose(Weapons.SRUT8).is_empty()
		and not level._cabinet_issued.has(String(back.name)) and level._cabinet_issued.size() == 1)
	wc.inspect_item = back
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(4)
	var hud: Node = main.get_node("UI").find_child("HUD", false, false)
	var hidden: bool = hud != null and not bool(hud._gear_card.visible) and not bool(hud._obj_card.visible)
	await pulse("move_right")
	var switched: bool = wc.inspect_item != null and int(wc.inspect_item.get_meta("cabinet")) == int(cab1.get("index")) and is_equal_approx(player.global_position.x, cab1.global_position.x)
	await pulse("move_left")
	var back_left: bool = wc.inspect_item != null and int(wc.inspect_item.get_meta("cabinet")) == int(cab0.get("index"))
	player.process_mode = Node.PROCESS_MODE_DISABLED
	check("oględziny gabloty chowają kartę broni i cel misji (HUD %s)" % str(hud != null), hidden)
	check("[D] przechodzi do sąsiedniej gabloty, [A] wraca", switched and back_left)
	wc.inspect_item = null
	_drive_input = false

func _net_host() -> void:
	player = main.get_node("Players/1")
	player.set_physics_process(false)
	# Izolujemy bilans broni od skrzynek amunicji zbieranych automatycznie w zbrojowni.
	for pickup in get_tree().get_nodes_in_group("pickups"):
		if pickup.kind != "weapon":
			pickup.set_physics_process(false)
	Scrap.unlocked[Weapons.SRUT8] = true
	var first: Node2D = item(Weapons.SPREAD12)
	player.global_position = first.global_position
	level.request_weapon_pickup(first.name)
	Arsenal.set_reserve(Weapons.SPREAD12, 0, 0)
	Arsenal.set_reserve(Weapons.SPREAD12, 0, 1)
	Arsenal.set_reserve(Weapons.SRUT8, 0, 0)
	Scrap.cleared = {"z1_m1": true}                 # postęp kampanii drużyny (PROGRESSION_PLAN.md P1.1): klient dostaje go w sync
	main.after_hub = "z1_m2"
	print("[CABINET-TEST] HOST READY — pobrana broń przed dołączeniem")
	var elapsed := 0.0
	while multiplayer.get_peers().is_empty() and elapsed < 20:
		await wait(0.2)
		elapsed += 0.2
	check("klient ENet dołączył", not multiplayer.get_peers().is_empty())
	if multiplayer.get_peers().is_empty():
		return
	var peer: int = multiplayer.get_peers()[0]
	Scrap._push()
	elapsed = 0.0
	while not _net_done and elapsed < 30:
		await wait(0.2)
		elapsed += 0.2
	check("klient zakończył rzeczywiste żądania RPC", _net_done)
	var remote := main.get_node("Players").get_node_or_null(str(peer)) as Node2D
	check("autoryzowany zestaw po ponownej zamianie", remote != null and level.server_weapon_kit(remote).y == Weapons.SRUT8)
	check("żadne żądanie nie utworzyło porzuconej LR-7", loose(Weapons.LR7).is_empty() and not Scrap.is_unlocked(Weapons.LR7))
	check("specjalne naboje wróciły dokładnie raz", Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7 and Arsenal.get_reserve(Weapons.SPREAD12, 0) == Weapons.def(Weapons.SRUT8).pickup_rounds)
	check("wydanie rzędu widoczne na hoście", remote != null and level._cabinet_issued.get("MapGun1", "") == "P%d" % remote.display_id and item(Weapons.SRUT8) == null)
	check("kolejna zamiana odłożyła jedną pustą broń", loose(Weapons.SPREAD12).size() == 1 and item(Weapons.SPREAD12, false).rounds == 0)
	main._restart_mission(true, "", true)
	await wait(0.7)
	check("carry zachowuje autoryzowany zestaw zdalnego gracza", level.server_weapon_kit(remote).y == Weapons.SRUT8 and remote.kit.y == Weapons.SRUT8)
	remote.deliver_hit(999, remote.global_position, "test", true)
	await wait(0.3)
	check("przygotowanie porwania: klient został powalony", remote.dead)
	remote.deliver_take(true, remote.global_position, 1.0)
	await wait(0.3)
	check("przygotowanie porwania: klient został porwany", remote.taken)
	remote.deliver_devour()
	await wait(0.7)
	check("kara porwania resetuje rejestr i zestaw klienta", level.server_weapon_kit(remote).y == Weapons.START_PRIMARY_B and remote.kit.y == Weapons.START_PRIMARY_B)
	level._weapon_kits[peer] = Vector3i(Weapons.M83, Weapons.SRUT8, Weapons.START_MELEE)
	main._restart_mission(false)
	await wait(0.4)
	check("wipe resetuje także rejestr zdalnego gracza", level.server_weapon_kit(remote).y == Weapons.START_PRIMARY_B)
	_finish_net.rpc_id(peer)
	await wait(1.0)

func _net_client() -> void:
	var elapsed := 0.0
	while player == null and elapsed < 15:
		player = main.get_node("Players").get_node_or_null(str(NoiseMgr.local_id()))
		await wait(0.1)
		elapsed += 0.1
	check("rzeczywisty zdalny człowiek", player != null)
	if player == null:
		return
	player.set_physics_process(false)
	wc = player.weapons
	await wait(0.5)
	check("dołączenie nie odtwarza wcześniej pobranej broni", item(Weapons.SPREAD12) == null and level._cabinet_issued.get("MapGun0", "") == "P1")
	check("ENet: klient zna cel wyjścia i postęp kampanii hosta (%s, %s)" % [main.after_hub, str(Scrap.cleared.keys())], main.after_hub == "z1_m2" and Scrap.cleared.has("z1_m1"))
	var board: Node2D = get_tree().get_first_node_in_group("board")
	await _move_to(board.global_position + Vector2(0, -2), "board")
	main.request_brief_cycle()
	await wait(0.6)
	check("ENet: wybór misji przy tablicy rozstrzyga serwer (%s)" % main.after_hub, main.after_hub == "z1_m1")
	var locked: Node2D = item(Weapons.LR7)
	await _move_to(locked.global_position, "locked")
	level.request_weapon_pickup(locked.name, 1)
	level._drop_rpc.rpc_id(1, Weapons.LR7, player.global_position)
	level.request_drop(Weapons.LR7, player.global_position)
	await wait()
	check("ENet: blokada i fałszywe porzucenie LR-7 odrzucone", item(Weapons.LR7) != null and loose(Weapons.LR7).is_empty() and not wc.carries(Weapons.LR7))
	var free: Node2D = item(Weapons.SRUT8)
	var name_before: String = free.name
	await _move_to(free.global_position + Vector2(100, 0), "far")
	level.request_weapon_pickup(name_before, 1)
	await wait()
	check("ENet: odległe podniesienie odrzucone", item(Weapons.SRUT8) != null)
	# Kit jest polem synchronizowanym przez właściciela; nie wolno tworzyć z niego łupu.
	player.kit = Vector3i(Weapons.LR7, Weapons.LR7, Weapons.START_MELEE)
	var cab: Node2D = get_tree().get_nodes_in_group("cabinets")[0]
	await _move_to(cab.global_position + Vector2(-20, -2), "forged")
	level.request_weapon_pickup(name_before, 2)
	level.request_weapon_pickup("../Players/1", 1)
	await wait()
	check("ENet: błędny slot i ścieżka nie pobierają broni", item(Weapons.SRUT8) != null)
	wc.mags[Weapons.SPREAD12] = 7
	wc.loaded[Weapons.SPREAD12] = 1
	level.request_weapon_pickup(name_before, 1)
	level.request_weapon_pickup(name_before, 1)
	await wait(0.8)
	check("ENet: wybrany slot i wspólny rząd", wc.loadout[0] == Weapons.M83 and wc.loadout[1] == Weapons.SRUT8 and item(Weapons.SRUT8) == null)
	check("ENet: stare wyposażenie pochodzi z rejestru serwera", loose(Weapons.SPREAD12).size() == 1 and loose(Weapons.LR7).is_empty() and item(Weapons.SPREAD12, false).rounds == 0)
	check("ENet: duplikat zwraca specjalne naboje tylko raz", Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7)
	var old: Node2D = item(Weapons.SPREAD12, false)
	await _move_to(old.global_position + Vector2(0, -2), "return")
	level.request_weapon_pickup(old.name, 1)
	await wait(0.8)
	check("ENet: podniesienie porzuconej broni bez świeżych nabojów", wc.loadout[1] == Weapons.SPREAD12 and Arsenal.get_reserve(Weapons.SPREAD12, 1) == 7 and Arsenal.get_reserve(Weapons.SPREAD12, 0) == Weapons.def(Weapons.SRUT8).pickup_rounds)
	old = item(Weapons.SRUT8, false)
	await _move_to(old.global_position + Vector2(0, -2), "carry")
	level.request_weapon_pickup(old.name, 1)
	await wait(0.7)
	check("zdalny gracz przygotował zmieniony zestaw do carry", wc.loadout[1] == Weapons.SRUT8)
	_client_done.rpc_id(1)
	elapsed = 0.0
	while not _net_done and elapsed < 6:
		await wait(0.1)
		elapsed += 0.1
	check("host niezależnie sprawdził wynik", _net_done)
	check("cykl carry/porwanie/wipe przywrócił zestaw klienta", wc.loadout[1] == Weapons.START_PRIMARY_B)

func _move_to(pos: Vector2, stage: String) -> void:
	player.global_position = pos
	_stage = ""
	_sync_position.rpc_id(1, stage, pos)
	var elapsed := 0.0
	while _stage != stage and elapsed < 5:
		await wait(0.05)
		elapsed += 0.05
	check("potwierdzona replikacja pozycji: " + stage, _stage == stage)

@rpc("any_peer", "call_remote", "reliable")
func _sync_position(stage: String, pos: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var remote := main.get_node("Players").get_node_or_null(str(peer)) as Node2D
	var elapsed := 0.0
	while remote != null and elapsed < 4:
		if remote.global_position.distance_to(pos) < 1 and (stage != "forged" or remote.kit.x == Weapons.LR7):
			check("host widzi pozycję i replikowane dane: " + stage, true)
			_stage_ready.rpc_id(peer, stage)
			return
		await wait(0.05)
		elapsed += 0.05

@rpc("authority", "call_remote", "reliable")
func _stage_ready(stage: String) -> void:
	_stage = stage

@rpc("any_peer", "call_remote", "reliable")
func _client_done() -> void:
	if NoiseMgr.is_server():
		_net_done = true

@rpc("authority", "call_remote", "reliable")
func _finish_net() -> void:
	_net_done = true
