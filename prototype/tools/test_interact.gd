extends SceneTree
## Wybór celu [E] (INTERACT_PLAN.md I0–I4, interact.gd): reguły wyboru (możliwe przed niemożliwymi, priorytet, odległość, strona spojrzenia
## przy remisie, blokada trzymanego celu), prawdziwe obiekty obok siebie (sejf i zwłoki — jedno [E] to jedna akcja, broń wygrywa z sejfem
## i stanowiskiem, martwy gracz bez celu), odstępy zasięgów stanowisk w kryjówce (z1_hub), oględziny przytrzymaniem na padzie
## (Actions.inspect_by_hold), ramka znacznika z rzutu bryły modelu (interact_mark3d.project_box; gablota zostaje przy ramce szafy) i wiersze
## tłumaczeń nowych podpowiedzi.
##   godot --headless --path prototype -s tools/test_interact.gd     → ostatni wiersz: [INTERACT] PASS / FAIL

var _fails := 0
var _root: Node2D
var I: GDScript


func _check(name: String, ok: bool) -> void:
	print("[INTERACT] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


static func _o(prio: int, dist: float, dx: float, ok := true, kind := 0) -> Dictionary:
	return {"kind": kind, "prio": prio, "ok": ok, "muted": not ok, "dist": dist, "dx": dx, "box": Rect2(), "prog": -1.0}


## Atrapa lokalnego gracza: tylko to, czego potrzebują oferty (pozycja, życie, kierunek spojrzenia, bot / właściciel).
func _fake_player(x: float) -> Node2D:
	var gs := GDScript.new()
	gs.source_code = "extends Node2D\nvar dead := false\nvar is_bot := false\nvar aim_dir := Vector2.RIGHT\n"
	gs.reload()
	var p := Node2D.new()
	p.set_script(gs)
	p.name = "FakePlayer"
	p.add_to_group("players")
	p.position = Vector2(x, 100.0)
	_root.add_child(p)
	return p


func _add(script_path: String, n: String, x: float) -> Node2D:
	var s: GDScript = load(script_path)
	var node: Node2D = s.new()
	node.name = n
	node.position = Vector2(x, 100.0)
	_root.add_child(node)
	node.set_physics_process(false)            # bez własnych klatek: oferty liczy arbiter, stan ustawia test
	node.set_process(false)
	return node


func _run() -> void:
	I = load("res://scripts/interact.gd")
	_root = Node2D.new()
	root.add_child(_root)
	var nA := Node.new()
	var nB := Node.new()
	var nC := Node.new()

	# ---------------------------------------------------------------- reguły wyboru (czysta funkcja)
	var c1 := [{"node": nA, "offer": _o(I.P_STATION, 2.0, -2.0)}, {"node": nB, "offer": _o(I.P_WEAPON, 20.0, 20.0)}]
	_check("wyższy priorytet wygrywa mimo większej odległości (broń 20 px > stanowisko 2 px)", I.choose(c1, 1.0, null) == 1)
	var c2 := [{"node": nA, "offer": _o(I.P_WORK, 5.0, 5.0, false)}, {"node": nB, "offer": _o(I.P_SEARCH, 15.0, 15.0)}]
	_check("możliwa oferta wygrywa z niemożliwą o wyższym priorytecie (zwłoki zamiast barykady bez desek)", I.choose(c2, 1.0, null) == 1)
	var c3 := [{"node": nA, "offer": _o(I.P_WORK, 5.0, 5.0, false)}]
	_check("sama niemożliwa oferta jest celem do podpowiedzi", I.choose(c3, 1.0, null) == 0)
	var c4 := [{"node": nA, "offer": _o(I.P_WORK, 18.0, -18.0)}, {"node": nB, "offer": _o(I.P_WORK, 10.0, 10.0)}]
	_check("ten sam priorytet: bliższy wygrywa", I.choose(c4, -1.0, null) == 1)
	var c5 := [{"node": nA, "offer": _o(I.P_WORK, 9.0, -9.0)}, {"node": nB, "offer": _o(I.P_WORK, 11.0, 11.0)}]
	_check("remis poniżej %.0f px: obiekt po stronie spojrzenia (w prawo → prawy, w lewo → lewy)" % I.FACING_TIE_PX,
		I.choose(c5, 1.0, null) == 1 and I.choose(c5, -1.0, null) == 0)
	var c6 := [{"node": nA, "offer": _o(I.P_SEARCH, 10.0, 10.0, true, 1)}, {"node": nB, "offer": _o(I.P_REVIVE, 5.0, 5.0, true, 1)}]
	_check("trzymany cel zostaje mimo ważniejszej oferty (podnoszenie dopiero po puszczeniu)", I.choose(c6, 1.0, nA) == 0 and I.choose(c6, 1.0, null) == 1)
	var c7 := [{"node": nA, "offer": _o(I.P_WORK, 10.0, 10.0, false, 1)}, {"node": nB, "offer": _o(I.P_SEARCH, 5.0, 5.0, true, 1)}]
	_check("blokada puszcza cel, którego oferta przestała być możliwa", I.choose(c7, 1.0, nA) == 1)
	_check("blokada puszcza cel, który zniknął z ofert", I.choose([{"node": nB, "offer": _o(I.P_SEARCH, 5.0, 5.0)}], 1.0, nC) == 0)
	_check("tabela priorytetów: ratowanie > drezyna > broń > taśma > stempel > prace > zwłoki > stanowiska > wyjścia",
		I.P_REVIVE > I.P_PUMP and I.P_PUMP > I.P_WEAPON and I.P_WEAPON > I.P_TAPE and I.P_TAPE > I.P_PROP and I.P_PROP > I.P_WORK
		and I.P_WORK > I.P_SEARCH and I.P_SEARCH > I.P_STATION and I.P_STATION > I.P_EXIT)
	nA.free()
	nB.free()
	nC.free()

	# ---------------------------------------------------------------- prawdziwe obiekty obok siebie (misja, przykład z planu)
	var me := _fake_player(168.0)
	var box := _add("res://scripts/strongbox.gd", "Strongbox1", 150.0)
	var body := _add("res://scripts/corpse.gd", "Corpse1", 188.0)
	I.reset()
	I.update(self, true)
	var ob: Dictionary = box.interact_offer(me)
	var oc: Dictionary = body.interact_offer(me)
	_check("sejf i zwłoki w zasięgu oferują [E] (przytrzymanie, z prostokątem znacznika)",
		not ob.is_empty() and not oc.is_empty() and int(ob["kind"]) == I.Kind.HOLD and (ob["box"] as Rect2).size.x > 0.0)
	_check("jedno [E] to jedna akcja: celem jest sejf (P_WORK), nie zwłoki", I.target(box) == box and not I.is_target(body))
	I.sim_held = 1
	box.opened = true                                          # sejf otwarty: oferuje już tylko ciało
	I.update(self, true)
	_check("po otwarciu sejfu celem są zwłoki", I.is_target(body) and I.held(body) and not I.held(box))
	box.opened = false                                         # sejf znów dostępny (test), [E] wciąż trzymane przy zwłokach
	I.update(self, true)
	_check("trzymane [E] zostaje przy zwłokach, choć sejf ma wyższy priorytet", I.is_target(body) and I.held(body))
	I.sim_held = 0
	I.update(self, true)
	_check("po puszczeniu celem znowu jest sejf", I.is_target(box))
	var gun: Node2D = load("res://scripts/pickup.gd").new()
	gun.name = "Item1"
	gun.kind = "weapon"
	gun.arg = 1
	gun.rounds = 0
	gun.static_display = true
	gun.position = Vector2(176.0, 102.0)
	_root.add_child(gun)
	gun.set_physics_process(false)
	I.update(self, true)
	_check("broń w zasięgu wygrywa z sejfem (P_WEAPON)", I.target(gun) == gun and not bool(I.current(gun).get("muted", true)))
	me.dead = true
	I.update(self, true)
	_check("powalony gracz nie ma celu", I.target(box) == null)
	me.dead = false
	gun.free()
	box.free()
	body.free()

	# ---------------------------------------------------------------- stanowisko ustępuje broni
	var bench := _add("res://scripts/pyro_bench.gd", "PyroBench1", 160.0)
	I.update(self, true)
	_check("stanowisko w zasięgu jest celem (naciśnięcie)", I.is_target(bench) and int(I.current(bench)["kind"]) == I.Kind.PRESS)
	var gun2: Node2D = load("res://scripts/pickup.gd").new()
	gun2.name = "Item2"
	gun2.kind = "weapon"
	gun2.arg = 1
	gun2.static_display = true
	gun2.position = Vector2(170.0, 102.0)
	_root.add_child(gun2)
	gun2.set_physics_process(false)
	I.update(self, true)
	_check("broń obok stanowiska: [E] bierze broń, nie otwiera stanowiska", not I.is_target(bench) and I.target(bench) == gun2)
	gun2.free()
	bench.free()
	me.free()
	I.reset()

	# ---------------------------------------------------------------- odstępy zasięgów stanowisk w kryjówce
	var hub: GDScript = load("res://scripts/maps/z1_hub.gd")
	var rows: Array = hub.get_script_constant_map()["MAP"]
	var reach := {"p": "res://scripts/locker_station.gd", "j": "res://scripts/service_bench.gd", "h": "res://scripts/workshop.gd",
		"x": "res://scripts/press_bench.gd", "z": "res://scripts/pyro_bench.gd", "c": "res://scripts/lab_bench.gd", "d": "res://scripts/lathe_bench.gd",
		"n": "res://scripts/board.gd"}
	var bands := {}                                            # wiersz → [[x0, x1, znak]]
	for r in rows.size():
		var line := String(rows[r])
		for c in line.length():
			var ch := line[c]
			if reach.has(ch):
				var rx := float((load(reach[ch]) as GDScript).get_script_constant_map()["REACH_X"])
				var cx := c * 16.0 + 8.0
				if not bands.has(r):
					bands[r] = []
				bands[r].append([cx - rx, cx + rx, ch])
	var rd: Array = hub.get_script_constant_map()["RANGE_DOOR"]
	var rdx := float((load("res://scripts/range3d/range_door.gd") as GDScript).get_script_constant_map()["REACH_X"])
	var rdr := int(rd[1]) - 1                                  # wiersz znacznika = wiersz podłogi − 1
	if not bands.has(rdr):
		bands[rdr] = []
	bands[rdr].append([int(rd[0]) * 16.0 + 8.0 - rdx, int(rd[0]) * 16.0 + 8.0 + rdx, "range"])
	var overlaps: Array = []
	var gaps: Array = []
	for r in bands:
		var b: Array = bands[r]
		b.sort_custom(func(a: Array, q: Array) -> bool: return float(a[0]) < float(q[0]))
		for i in b.size() - 1:
			var g := float(b[i + 1][0]) - float(b[i][1])
			gaps.append("%s|%s %.0f" % [b[i][2], b[i + 1][2], g])
			if g < 0.0:
				overlaps.append("%s|%s %.0f px" % [b[i][2], b[i + 1][2], g])
	print("[INTERACT] odstępy zasięgów kryjówki: %s" % ", ".join(gaps))
	_check("kryjówka: zasięgi stanowisk się nie nakładają %s" % str(overlaps), overlaps.is_empty() and not gaps.is_empty())

	# ---------------------------------------------------------------- pad: oględziny przytrzymaniem
	var A: GDScript = load("res://scripts/actions.gd")
	A.register()
	A.pad_mode = true
	var hold_pad: bool = A.inspect_by_hold()
	var pad_inspect: bool = A.bound("inspect_weapon")
	var pad_close: String = A.fmt("[{inspect_weapon}] [{pause}]  Close")
	A.pad_mode = false
	var key_close: String = A.fmt("[{inspect_weapon}] [{pause}]  Close")
	_check("stopka oględzin bez „[—]”: pad „%s”, klawiatura „%s”" % [pad_close, key_close],
		not pad_close.contains("—") and pad_close.begins_with("[") and pad_close.ends_with("Close")
		and key_close.begins_with("[%s] [" % A.key("inspect_weapon")))
	var hold_key: bool = A.inspect_by_hold()
	_check("pad (Classic, oględziny bez przycisku): oględziny przytrzymaniem [B]; klawiatura — [H] (%s)" % A.key("inspect_weapon"),
		hold_pad and not pad_inspect and not hold_key and A.bound("inspect_weapon") and A.INSPECT_HOLD_S > 0.2 and A.INSPECT_HOLD_S < 0.8)

	# ---------------------------------------------------------------- ramka z bryły modelu (interact_mark3d.gd project_box)
	var M: GDScript = load("res://scripts/interact_mark3d.gd")
	var L3: GDScript = load("res://scripts/level3d.gd")
	var px: float = L3.PX
	var eye := Vector3(10.0 * px, -10.0 * px, 12.0)
	var flat: Rect2 = M.project_box([AABB(Vector3(0.0, -8.0 * px, 0.0), Vector3(20.0 * px, 8.0 * px, 0.0))], eye)
	var deep: Rect2 = M.project_box([AABB(Vector3(0.0, -8.0 * px, -1.0), Vector3(20.0 * px, 8.0 * px, 0.0))], eye)
	var thick: Rect2 = M.project_box([AABB(Vector3(0.0, -8.0 * px, -1.0), Vector3(20.0 * px, 8.0 * px, 1.0))], eye)
	var near := func(a: Rect2, b: Rect2) -> bool: return a.position.distance_to(b.position) < 0.01 and a.size.distance_to(b.size) < 0.01
	var ctr_d: Vector2 = deep.get_center() - flat.get_center()
	_check("rzut bryły: w płaszczyźnie gry bez zmian %s, w głębi mniejszy i bliżej osi oka %s, gruba = obrys obu %s" % [flat, deep, thick],
		near.call(flat, Rect2(0.0, 0.0, 20.0, 8.0)) and deep.size.x < 20.0 and deep.size.x > 18.0 and ctr_d.y > 0.0 and absf(ctr_d.x) < 0.01
		and near.call(thick, flat.merge(deep)) and M.project_box([], eye) == Rect2()
		and M.project_box([AABB(Vector3(0.0, 0.0, 13.0), Vector3.ONE)], eye) == Rect2())
	var cab_gun := _add("res://scripts/pickup.gd", "GunCab", 500.0)
	cab_gun.kind = "weapon"
	var me2 := _fake_player(500.0)
	var og: Dictionary = cab_gun.interact_offer(me2)
	cab_gun.set_meta("cab_x", 500.0)
	var oc2: Dictionary = cab_gun.interact_offer(me2)
	_check("broń na ziemi: ramka z modelu (fit), gablota: ramka szafy z oferty (bez fit)",
		bool(og.get("fit", false)) and (oc2.is_empty() or not bool(oc2.get("fit", true))))
	cab_gun.free()
	me2.free()

	# ---------------------------------------------------------------- tłumaczenia nowych podpowiedzi
	var csv := FileAccess.get_file_as_string("res://translations/ui.csv")
	var need := ["[%s]  Take %s  (drops %s)   ·   Hold [%s]  Inspect", "[%s]  Take ammo for %s   ·   Hold [%s]  Inspect",
		"LOCKED  ·  %s   ·   Hold [%s]  Inspect", "[%s]  Take %s  (drops %s)", "[%s]  Take ammo for %s", "Healing %s…", "Interaction highlight"]
	var missing: Array = need.filter(func(k: String) -> bool: return not csv.contains("\n\"%s\"," % k))
	_check("wiersze ui.csv dla nowych podpowiedzi %s" % str(missing), missing.is_empty())

	print("[INTERACT] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)
