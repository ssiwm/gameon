extends SceneTree
## Wybór celu [E] (INTERACT_PLAN.md I0–I4, interact.gd): reguły wyboru (możliwe przed niemożliwymi, priorytet, odległość, strona spojrzenia
## przy remisie, blokada trzymanego celu), prawdziwe obiekty obok siebie (sejf i zwłoki — jedno [E] to jedna akcja, broń wygrywa z sejfem
## i stanowiskiem, martwy gracz bez celu), odstępy zasięgów stanowisk w kryjówce (z1_hub), oględziny przytrzymaniem na padzie
## (Actions.inspect_by_hold), ramka znacznika z rzutu bryły modelu (interact_mark3d.project_box; gablota zostaje przy ramce szafy), podpowiedź od
## obiektu (interact_hint) i wiersze
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
	var hb: Dictionary = box.interact_hint(me)
	var hc: Dictionary = body.interact_hint(me)
	box.progress = 0.4
	var hb2: Dictionary = box.interact_hint(me)
	box.progress = 0.0
	_check("podpowiedź podaje cel (I2): sejf „%s”, w trakcie „%s” (postęp %.1f), zwłoki „%s”" % [hb.get("text"), hb2.get("text"), float(hb2.get("prog", -1.0)), hc.get("text")],
		String(hb.get("text", "")).contains("strongbox") and float(hb.get("prog", -1.0)) < 0.0 and is_equal_approx(float(hb2.get("prog", -1.0)), 0.4)
		and String(hb2.get("text", "")) != String(hb.get("text", "")) and String(hc.get("text", "")).contains("body") and hb.get("col") is Color)
	var no_hint: Array = []
	for sp in ["generator.gd", "strongbox.gd", "corpse.gd", "barricade_spot.gd", "workshop.gd", "lathe_bench.gd", "lab_bench.gd", "pyro_bench.gd",
			"press_bench.gd", "service_bench.gd", "locker_station.gd", "board.gd", "range3d/range_door.gd", "pickup.gd"]:
		var gs: GDScript = load("res://scripts/" + sp)
		if not gs.get_script_method_list().any(func(md: Dictionary) -> bool: return String(md["name"]) == "interact_hint"):
			no_hint.append(sp)
	_check("każdy obiekt z podpowiedzią w pasku akcji ma interact_hint %s" % str(no_hint), no_hint.is_empty())
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
	var A2: GDScript = load("res://scripts/actions.gd")
	_check("oferta broni dla znacznika: [H] przy przypisanych oględzinach (alt), pad Classic — przytrzymanie [B] (alt_hold), gablota bez przytrzymania",
		String(og.get("alt", "?")) == ("inspect_weapon" if A2.bound("inspect_weapon") else "")
		and bool(og.get("alt_hold", true)) == (String(og["alt"]) == "" and A2.inspect_by_hold())
		and (oc2.is_empty() or not bool(oc2.get("alt_hold", true)) or not cab_gun.has_meta("cabinet")))
	cab_gun.set_meta("cabinet", 0)
	var oc3: Dictionary = cab_gun.interact_offer(me2)
	_check("gablota: sam klawisz [E] bez [H] (oba otwierają ten sam panel), bez przytrzymania [B]",
		not oc3.is_empty() and String(oc3.get("alt", "?")) == "" and not bool(oc3.get("alt_hold", true)))
	cab_gun.free()
	me2.free()

	# ---------------------------------------------------------------- klawisz w świecie (INTERACT_KEY_PLAN.md K3, interact_mark3d.gd)
	_mark_checks(M)

	# ---------------------------------------------------------------- tłumaczenia nowych podpowiedzi
	var csv := FileAccess.get_file_as_string("res://translations/ui.csv")
	var need := ["[%s]  Take %s  (drops %s)   ·   Hold [%s]  Inspect", "[%s]  Take ammo for %s   ·   Hold [%s]  Inspect",
		"LOCKED  ·  %s   ·   Hold [%s]  Inspect", "[%s]  Take %s  (drops %s)", "[%s]  Take ammo for %s", "Healing %s…", "Interaction highlight"]
	var missing: Array = need.filter(func(k: String) -> bool: return not csv.contains("\n\"%s\"," % k))
	_check("wiersze ui.csv dla nowych podpowiedzi %s" % str(missing), missing.is_empty())

	print("[INTERACT] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

## Znacznik celu: położenie, stany, para [E] + [H], przytrzymanie [B] na padzie, wybuch, warstwy (INTERACT_KEY_PLAN.md K3).
func _mark_checks(M: GDScript) -> void:
	var dt := 1.0 / 60.0
	var station_box := Rect2(Vector2(78.0, 174.0), Vector2(44.0, 26.0))               # strefa stanowiska: 44 × 26 px nad podłogą y = 200
	var props_fit := Rect2(Vector2(90.0, 150.0), Vector2(60.0, 40.0))                 # rzut mebli (z tablicą na ścianie, w głębi)
	var a: Vector2 = M.anchor_px({"box": station_box}, props_fit)
	var gun_box := Rect2(Vector2(291.0, 193.0), Vector2(18.0, 4.0))
	var ag: Vector2 = M.anchor_px({"box": gun_box}, Rect2())
	var top_gap: float = M.KEY_PX * 0.5 + M.TOP_GAP_PX
	_check("położenie: oś z rzutu mebli %.1f, wysokość z wierzchu strefy (najwyżej %.0f px nad podłogą) %.1f; broń na ziemi nad bronią; anchor oferty" % [a.x, M.SURFACE_PX, a.y],
		is_equal_approx(a.x, props_fit.get_center().x) and is_equal_approx(a.y, 200.0 - M.SURFACE_PX - top_gap)
		and is_equal_approx(ag.x, 300.0) and is_equal_approx(ag.y, 193.0 - top_gap)
		and M.anchor_px({"box": station_box, "anchor": Vector2(5.0, 6.0)}, props_fit) == Vector2(5.0, 6.0))
	_check("przytrzymanie [B] na padzie: drut dopiero od %.2f (0,1 z 0,4 s), pełny przy 1" % M.LOOK_RING_FROM,
		M.look_ring(-1.0) < 0.0 and M.look_ring(0.2) < 0.0 and is_equal_approx(M.look_ring(M.LOOK_RING_FROM), 0.0)
		and is_equal_approx(M.look_ring(1.0), 1.0) and is_equal_approx(M.look_ring(0.625), 0.5))

	var mk: MeshInstance3D = M.new()
	_root.add_child(mk)
	var obj := Node2D.new()
	_root.add_child(obj)
	var base := {"box": station_box, "kind": 0, "muted": false, "prog": -1.0}
	var run := func(n: int, off: Dictionary, pressed := false, pressed_alt := false, look := -1.0) -> void:
		for i in n:
			mk.tick(dt, obj, off, true, false, props_fit, pressed and i == 0, pressed_alt and i == 0, look)
	run.call(30, base)
	var pos0: Vector3 = mk.position
	run.call(5, base)
	_check("klawisz pojawia się po %.2f s, stan „ok”, pozycja stała między klatkami (%s)" % [M.DWELL_S, mk.position],
		mk.visible and String(mk.state) == "ok" and mk.position.is_equal_approx(pos0) and not bool(mk.pair))
	run.call(1, base.merged({"muted": true}, true), true)
	var k0 = mk.keys[0]
	_check("oferta niemożliwa: stan „muted”, [E] daje zakłócenie zamiast wciśnięcia",
		String(mk.state) == "muted" and float(k0.glitch) > 0.0 and float(k0.press) <= 0.0)
	run.call(30, base)
	run.call(1, base, true)
	_check("naciśnięcie przy możliwej: wciśnięcie bez zakłócenia", float(k0.press) > 0.0 and float(k0.glitch) <= 0.0)
	run.call(60, base)
	run.call(3, base.merged({"kind": 1, "prog": 0.0}, true))
	_check("oferta przytrzymania z postępem 0 (zwłoki, sejf przed [E]): stan „ok”, bez drutu",
		String(mk.state) == "ok" and not (k0.ring as Node3D).visible)
	var hold := base.merged({"kind": 1, "prog": 0.5}, true)
	run.call(3, hold)
	_check("przytrzymanie: stan „hold”, drut widoczny", String(mk.state) == "hold" and (k0.ring as Node3D).visible)
	run.call(1, base.merged({"kind": 1, "prog": -1.0}, true))
	var no_burst: bool = float(mk._burst) < 0.0
	run.call(1, base.merged({"kind": 1, "prog": 0.95}, true))
	run.call(1, base.merged({"kind": 1, "prog": -1.0}, true))
	_check("wybuch tylko po pełnym przytrzymaniu (puszczenie w połowie — bez wybuchu)", no_burst and float(mk._burst) >= 0.0)
	run.call(80, base)

	var gun := {"box": gun_box, "kind": 0, "muted": false, "prog": -1.0, "alt": "inspect_weapon", "alt_hold": false}
	run.call(3, gun)
	var k1 = mk.keys[1]
	_check("broń z przypisanymi oględzinami: para [E] + [H], [H] z wiązania „%s”" % (k1.letter as Label3D).text,
		bool(mk.pair) and (k1.root as Node3D).visible and String(k1.action) == "inspect_weapon"
		and (k0.root as Node3D).position.x < 0.0 and (k1.root as Node3D).position.x > 0.0)
	run.call(1, gun, false, true)
	_check("[H] wciśnięte: wciśnięcie [H], [E] bez zmian", float(k1.press) > 0.0 and float(k0.press) <= 0.0)
	run.call(30, gun)
	run.call(1, gun.merged({"muted": true}, true), true)
	_check("broń zablokowana: [E] szary z zakłóceniem, [H] aktywny",
		String(k0.state) == "muted" and float(k0.glitch) > 0.0 and String(k1.state) == "ok")
	run.call(30, gun)

	var pad := gun.merged({"alt": "", "alt_hold": true}, true)
	run.call(3, pad)
	_check("pad Classic: jeden klawisz [B] (bez pary)", not bool(mk.pair) and not (k1.root as Node3D).visible)
	run.call(1, pad, true, false, 0.1)
	var pressed_early: bool = float(k0.press) > 0.0
	run.call(2, pad, false, false, 0.15)
	var ring_early: bool = (k0.ring as Node3D).visible
	run.call(1, pad, false, false, -1.0)
	_check("pad Classic: [B] wciśnięte nie błyska od razu, krótkie stuknięcie bez drutu, puszczenie = wzięcie (wciśnięcie)",
		not pressed_early and not ring_early and float(k0.press) > 0.0)
	run.call(30, pad)
	run.call(1, pad, false, false, 0.7)
	var ring_hold: bool = (k0.ring as Node3D).visible
	run.call(1, pad, false, false, 0.99)
	mk._burst = -1.0
	run.call(1, pad, false, false, -1.0)
	_check("pad Classic: przytrzymanie — drut, otwarcie oględzin — wybuch", ring_hold and float(mk._burst) >= 0.0)

	mk.set_view_layers(1)
	var layers_ok := mk.layers == 1
	for n in mk.find_children("*", "", true, false):
		if n is VisualInstance3D and (n as VisualInstance3D).layers != 1:
			layers_ok = false
	_check("warstwy: cały znacznik w obrazie świata (pod postacią gracza)", layers_ok)
	mk.free()
	obj.free()
