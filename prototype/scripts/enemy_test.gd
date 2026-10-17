extends Node
## Test headless AI zwykłych wrogów i hałasu (ENEMY_PLAN.md F0): każda poprawka z fazy 0 ma tu asercję.
##
##   godot --headless --path . -- --host --enemytest --autoquit=40
##
## Mapa 1.3 (jak testy Stalkera). Testy fizyczne stawiają własną geometrię (podłoga i ściana jako `StaticBody2D` na warstwie 1) daleko poza mapą,
## żeby nic ze świata gry ich nie zakłócało. Wynik: linie [ENEMY-TEST] i kod wyjścia (0 = OK) — nadaje się do CI.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Enemy := preload("res://scripts/enemy.gd")
const Bruiser := preload("res://scripts/enemy_bruiser.gd")
const Blind := preload("res://scripts/enemy_blind.gd")
const FAR_X := 30000.0                ## px: obszar testów fizycznych poza mapą

var main: Node2D
var level: Node2D
var player: CharacterBody2D
var failed := 0
var total := 0

func check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if not ok:
		failed += 1
	print("[ENEMY-TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(1.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	check("mapa ma gracza", player != null)
	if player == null:
		_finish()
		return
	Director.set_process(false)
	_test_noise_validation()
	_test_noise_same_frame()
	_test_sound_budget()
	_test_scaled_damage()
	await _test_forced_hit()
	await _test_run_clear()
	await _test_wall_between()
	await _test_summoned()
	await _test_view_contract()
	await _test_facing()
	_test_defs()
	await _test_boss_base()
	await _test_ai_states()
	await _test_alert()
	await _test_target_hysteresis()
	await _test_target_weights()
	await _test_hear_error()
	await _test_pack_shout()
	await _test_windup_interrupt()
	await _test_director()
	await _test_pincer()
	await _test_director_composition()
	await _test_behaviors()
	await _test_elite_foundation()
	await _test_priest()
	await _test_butcher()
	await _test_devourer()
	await _test_wolek_throw_vertical()
	await _test_slepiec_mechanics()
	await _test_slepiec_listen()
	await _test_slepiec_step()
	await _test_slepiec_shaft()
	await _test_return_home_stuck()
	await _test_listener()
	await _test_wolek_boulder()
	_finish()

# ---------------------------------------------------------------- Podsłuchacz: pole ochronne, fala alarmu, limit krzyków (ENEMY_PLAN.md F3.8)

## Krzyk Podsłuchacza: pole ochronne (−90%) przez `shield.time` od krzyku, zapowiedź nadal do zabicia, fala przywołania (dalsi budzą się później), kolejne krzyki sięgają bliżej,
## po `scream.max` milknie, a kierunek patrzenia i flaga `alert`/`shield` idą z serwera do widoku. (Dwa Podsłuchacze na mapie 1.2 stoją 416 px od siebie — dalej niż słuch 238 px,
## więc krzyk jednego nie uruchamia drugiego; test pilnuje tej odległości.)
func _test_listener() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["podsluchacz"]
	check("Podsłuchacz/dane: pole ochronne pochłania 90%, krzyk ma zasięg, limit i falę", is_equal_approx(float(cfg["shield"]["reduce"]), 0.9) and float(cfg["shield"]["time"]) > 1.0 and int(cfg["scream"]["max"]) == 3 and float(cfg["scream"]["wave"]) > 0.0)
	var y := -12500.0
	var strip := _floor(FAR_X + 26000.0, FAR_X + 26900.0, y)
	var x0 := FAR_X + 26400.0
	var l := _spawn("podsluchacz", Vector2(x0, y))
	var near := _spawn("trzosek", Vector2(x0 + 60.0, y))               # śpi, 60 px (słyszana odległość ×3 = 180)
	var far := _spawn("trzosek", Vector2(x0 - 120.0, y))               # śpi, 120 px (360)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("Podsłuchacz/słuch: krzyk (hałas 14) nie sięga drugiego Podsłuchacza z mapy 1.2 (416 px > słuch)", l._noise_reach(14.0, 1.4) < 416.0, "%.0f px" % l._noise_reach(14.0, 1.4))

	# zapowiedź: tylko usłyszał (bez celu) → dłuższa o `blind`; z celem → zwykła
	l.set_physics_process(false)
	l._target = null
	l._beh.begin_scream()
	var blind_w: float = l._windup
	l._windup = 0.0
	l.winding = false
	l._target = player
	l._beh.begin_scream()
	var seen_w: float = l._windup
	check("Podsłuchacz/zapowiedź: bez celu dłuższa o `blind` (×1,3) niż z celem", seen_w > 0.1 and absf(blind_w / seen_w - 1.3) < 0.01, "%.2f / %.2f" % [blind_w, seen_w])
	check("Podsłuchacz/pole: przed krzykiem nie ma pola ochronnego", l._beh.shield_t == 0.0 and not bool(l.view_info()["shield"]))
	l._set_ai_state(l._derive_ai_state())
	check("Podsłuchacz/widok: zapowiedź → stan windup i oczy (`alert`)", l.ai_name() == "windup" and bool(l.view_info()["alert"]), l.ai_name())
	var hp0: float = l.hp
	l.take_hit({"amount": 10.0, "dir": Vector2.RIGHT, "pos": l.global_position, "shooter": int(player.player_id), "type": "bullet"})
	check("Podsłuchacz/pole: w zapowiedzi trafienie zadaje pełne obrażenia (da się zabić)", absf((hp0 - l.hp) - 10.0) < 0.01, "%.1f" % (hp0 - l.hp))
	l.hp = l.get("_max_hp")
	l._windup = 0.0
	l.winding = false
	l._target = null

	# krzyk: pole, fala, zasięg
	l._beh.scream_cd = 0.0
	l._beh.scream()
	check("Podsłuchacz/krzyk: uruchamia pole ochronne i liczy krzyk", l._beh.shield_t > 1.0 and l._beh.screams == 1 and l._beh.alerted, "%.2f / %d" % [l._beh.shield_t, l._beh.screams])
	l._set_ai_state(l._derive_ai_state())
	check("Podsłuchacz/widok: w polu stan scream, `shield` i `alert` w view_info, boty nie strzelają", l.ai_name() == "scream" and bool(l.view_info()["shield"]) and bool(l.view_info()["alert"]) and not l.is_threat())
	check("Podsłuchacz/fala: tuż po krzyku nikt jeszcze nie reaguje (głos ma czas dojść)", not near.active and not far.active)
	hp0 = l.hp
	var info := {"amount": 10.0, "dir": Vector2.RIGHT, "pos": l.global_position, "shooter": int(player.player_id), "type": "bullet"}
	var res: Dictionary = l.take_hit(info.duplicate())
	check("Podsłuchacz/pole: trafienie 10 → 1 HP (−90%) i szary hitmarker (mat 1)", absf((hp0 - l.hp) - 1.0) < 0.01 and int(res["mat"]) == 1, "%.2f mat=%s" % [hp0 - l.hp, res.get("mat")])
	hp0 = l.hp
	l.take_bullet(l.global_position, 10.0)
	check("Podsłuchacz/pole: pocisk bota (take_bullet) też −90%", absf((hp0 - l.hp) - 1.0) < 0.01, "%.2f" % (hp0 - l.hp))
	await get_tree().create_timer(0.35).timeout
	check("Podsłuchacz/fala: bliższy wrogi budzi się pierwszy (po ≈ 0,2–0,4 s), dalszy jeszcze nie musiał", near.active and near._has_lead, "near=%s far=%s" % [near.active, far.active])
	await get_tree().create_timer(0.9).timeout
	check("Podsłuchacz/fala: po chwili cała okolica w zasięgu jest obudzona i idzie na krzyk", far.active and far._has_lead)
	l.set_physics_process(true)
	await get_tree().create_timer(1.6).timeout
	check("Podsłuchacz/pole: po `shield.time` (1,4 s) pole znika — stan listen, boty znów strzelają", l._beh.shield_t == 0.0 and l.ai_name() == "listen" and l.is_threat(), "%.2f %s" % [l._beh.shield_t, l.ai_name()])
	l.set_physics_process(false)
	l._beh.shield_t = 0.0
	l._set_ai_state(l._derive_ai_state())
	hp0 = l.hp
	l.take_hit(info.duplicate())
	check("Podsłuchacz/pole: bez pola trafienie 10 → 10 HP", absf((hp0 - l.hp) - 10.0) < 0.01 and l.is_threat(), "%.2f" % (hp0 - l.hp))

	# kolejny krzyk: zasięg ×0,6 (420 → 252), więc dalszy (360) już nie słyszy
	var far2 := _spawn("trzosek", Vector2(x0 - 120.0, y - 0.5))
	var near2 := _spawn("trzosek", Vector2(x0 + 60.0, y - 0.5))
	await get_tree().physics_frame
	l.hp = l.get("_max_hp")
	l._beh.scream_cd = 0.0
	l._beh.scream()
	await get_tree().create_timer(1.0).timeout
	check("Podsłuchacz/zasięg: drugi krzyk sięga 60% promienia — bliski budzi się, dalszy (360 > 252) nie", near2.active and not far2.active and l._beh.screams == 2, "near=%s far=%s n=%d" % [near2.active, far2.active, l._beh.screams])

	# limit krzyków
	l._beh.screams = 3
	l._beh.scream_cd = 0.0
	l._beh.shield_t = 0.0
	l._windup = 0.0
	l._beh.begin_scream()
	check("Podsłuchacz/limit: po 3 krzykach milknie (zapowiedź się nie zaczyna)", l._windup == 0.0 and not l.winding)
	l._beh.calm_t = 20.0
	l._target = null
	l.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("Podsłuchacz/limit: po 12 s spokoju licznik się zeruje", l._beh.screams == 0, str(l._beh.screams))

	# kierunek patrzenia: serwer liczy go z celu / śladu, nie z lokalnego gracza
	l.set_physics_process(false)
	l._target = null
	l._has_lead = true
	l._last_known = l.global_position + Vector2(80.0, 0.0)
	l._update_facing()
	var f_lead: float = l._facing
	l._last_known = l.global_position + Vector2(-80.0, 0.0)
	l._update_facing()
	var f_lead2: float = l._facing
	l._target = player
	l._update_facing()
	check("Podsłuchacz/patrzenie: ślad po prawej → +1, po lewej → −1, cel (gracz daleko po lewej) ma pierwszeństwo przed śladem", f_lead > 0.0 and f_lead2 < 0.0 and l._facing < 0.0, "%.0f / %.0f / %.0f" % [f_lead, f_lead2, l._facing])
	var client := _spawn("podsluchacz", Vector2(x0 + 300.0, y))
	client.set_physics_process(false)
	client._sync(client.global_position, client.hp, true, true, false, 0, Enemy.Ai.SCREAM, -1.0)
	check("Podsłuchacz/klient: stan scream z `_sync` → `shield` w widoku, kierunek z serwera", bool(client.view_info()["shield"]) and client._net_face < 0.0)

	# zabity w zapowiedzi nie krzyczy (kontra: zdążyć przed krzykiem)
	var dl := _spawn("podsluchacz", Vector2(x0 + 500.0, y))
	var sleeper := _spawn("trzosek", Vector2(x0 + 560.0, y))
	await get_tree().physics_frame
	dl._windup = 0.3
	dl.winding = true
	dl.take_hit({"amount": 500.0, "dir": Vector2.RIGHT, "pos": dl.global_position, "shooter": int(player.player_id), "type": "bullet"})
	await get_tree().create_timer(1.0).timeout
	check("Podsłuchacz/zapowiedź: zabity przed krzykiem nie krzyczy (nic się nie budzi, brak pola)", not dl.alive and dl._beh.screams == 0 and not sleeper.active and dl._beh.shield_t == 0.0, "żywy=%s krzyki=%d budzi=%s" % [dl.alive, dl._beh.screams, sleeper.active])
	dl.queue_free()
	sleeper.queue_free()
	for n in [l, near, far, near2, far2, client, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Głaz Wołka (ENEMY_PLAN.md F3.9)

## Wołek bez skrzyni w pobliżu rzuca głazem (0,5 HP = ukryte „stłuczenie” gracza, dwa głazy = serce), z przerwą zależną od trudności; skrzynia obok ma pierwszeństwo.
func _test_wolek_boulder() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["wolek"]["boulder"]
	check("głaz/dane: 0,5 HP, trzy przerwy malejące z trudnością (łatwy > normalny > trudny)", is_equal_approx(float(cfg["dmg"]), 0.5) and cfg["cd"].size() == 3 and float(cfg["cd"][0]) > float(cfg["cd"][1]) and float(cfg["cd"][1]) > float(cfg["cd"][2]))
	check("głaz/trudność: przerwa z tabeli dla EASY / NORMAL / HARD, poza zakresem przycięta",
		Bruiser.boulder_cooldown(cfg, Difficulty.Level.EASY) == float(cfg["cd"][0]) and Bruiser.boulder_cooldown(cfg, Difficulty.Level.NORMAL) == float(cfg["cd"][1]) and Bruiser.boulder_cooldown(cfg, Difficulty.Level.HARD) == float(cfg["cd"][2]) and Bruiser.boulder_cooldown(cfg, 9) == float(cfg["cd"][2]))
	var y := -13500.0
	var strip := _floor(FAR_X + 27000.0, FAR_X + 27600.0, y)
	var x0 := FAR_X + 27100.0
	var w := _spawn("wolek", Vector2(x0, y))
	w.set_physics_process(false)
	var dummy := Node2D.new()
	level.add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	w._beh.charge_cd = 99.0
	w._beh.throw_cd = 0.0
	w._beh.boulder_cd = 0.0
	dummy.global_position = Vector2(x0 + 120.0, y)
	check("głaz/wybór: brak skrzyni w pobliżu → zapowiedź rzutu głazem (nie skrzynią)", w._beh.tick_phase(0.016, dummy) and w._sp == 3 and w._beh.sp_boulder and w._beh.sp_crate == null, "sp=%d boulder=%s" % [w._sp, w._beh.sp_boulder])
	check("głaz/zapowiedź: krótsza niż rzut skrzynią (0,6 s × trudność)", w._beh.sp_t < Bruiser.THROW_WINDUP * Difficulty.m("enemy_windup") and w._beh.sp_t > 0.3, "%.2f" % w._beh.sp_t)
	w._sp = 0
	w._beh.sp_boulder = false
	w.winding = false
	w._beh.boulder_cd = 3.0
	check("głaz/cooldown: w czasie przerwy nie rzuca", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	w._beh.boulder_cd = 0.0
	dummy.global_position = Vector2(x0 + 300.0, y)
	check("głaz/zasięg: cel dalej niż 220 px → bez rzutu", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	dummy.global_position = Vector2(x0 + 120.0, y)
	var crate := _crate_at(Vector2(x0 + 10.0, y - 7.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("głaz/pierwszeństwo: skrzynia obok → rzut skrzynią, nie głazem", w._beh.tick_phase(0.016, dummy) and w._sp == 3 and not w._beh.sp_boulder and w._beh.sp_crate != null, "boulder=%s" % w._beh.sp_boulder)
	w._sp = 0
	w._beh.sp_crate = null
	w.winding = false
	w._beh.throw_cd = 5.0
	check("głaz/pierwszeństwo: skrzynia obok, ale na cooldownie → nie zastępuje jej głazem", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	crate.queue_free()
	await get_tree().physics_frame
	w._beh.throw_cd = 0.0
	var wall := _block(Vector2(x0 + 60.0, y - 30.0), Vector2(6.0, 120.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("głaz/ściana: mur na linii rzutu → bez rzutu", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	wall.queue_free()
	await get_tree().physics_frame

	# rzut: pocisk powstaje, przerwa wg trudności
	var prev: int = Difficulty.level
	var n0 := get_tree().get_nodes_in_group("boulders").size()
	var ok := true
	var detail := ""
	for lvl in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		Difficulty.set_level(lvl)
		w._sp = 3
		w._beh.sp_boulder = true
		w._beh.sp_dir = 1.0
		w._beh.sp_t = 0.0
		w._beh.boulder_cd = 0.0
		w._beh.tick_phase(0.016, dummy)
		ok = ok and w._sp == 0 and not w._beh.sp_boulder and is_equal_approx(w._beh.boulder_cd, float(cfg["cd"][int(lvl)]))
		detail += "%d: %.1f  " % [int(lvl), w._beh.boulder_cd]
	Difficulty.set_level(prev)
	check("głaz/rzut: pocisk powstaje, a przerwa po rzucie to 8 / 5 / 3,2 s dla łatwego / normalnego / trudnego", ok and get_tree().get_nodes_in_group("boulders").size() == n0 + 3, detail)
	for b in get_tree().get_nodes_in_group("boulders"):
		b.queue_free()
	await get_tree().physics_frame

	# trafienie: 0,5 HP → stłuczenie; drugie → realne serce; leczenie zeruje
	var hp_keep: int = player.hp
	player.hp = 3
	player.chip = 0.0
	player._invuln = 0.0
	player.deliver_chip(0.5, player.global_position + Vector2(40.0, 0.0), "boulder")
	check("głaz/gracz: pierwsze trafienie nie zabiera serca, tylko 0,5 stłuczenia i daje krótką niewrażliwość", player.hp == 3 and is_equal_approx(player.chip, 0.5) and player._invuln > 0.0 and player._invuln < 0.5, "hp=%d chip=%.1f inv=%.2f" % [player.hp, player.chip, player._invuln])
	player.deliver_chip(0.5, player.global_position + Vector2(40.0, 0.0), "boulder")
	check("głaz/gracz: w niewrażliwości kolejne trafienie jest ignorowane", player.hp == 3 and is_equal_approx(player.chip, 0.5))
	player._invuln = 0.0
	player.deliver_chip(0.5, player.global_position + Vector2(40.0, 0.0), "boulder")
	check("głaz/gracz: drugie trafienie = 1 realny HP, stłuczenie zerowe", player.hp == 2 and player.chip == 0.0, "hp=%d chip=%.1f" % [player.hp, player.chip])
	player._invuln = 0.0
	player.deliver_chip(0.5, player.global_position + Vector2(40.0, 0.0), "boulder")
	player.apply_heal(1)
	check("głaz/gracz: leczenie zeruje stłuczenie", player.hp == 3 and player.chip == 0.0, "hp=%d chip=%.1f" % [player.hp, player.chip])
	player._invuln = 0.0

	# lot głazu: trafia gracza (chip), ściana go zatrzymuje
	var BoulderScript := load("res://scripts/boulder.gd")
	var b = BoulderScript.new()
	level.add_child(b)
	b.global_position = player.global_position + Vector2(0.0, -10.0)
	b.vel = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("głaz/lot: głaz w punkcie trafienia gracza zadaje 0,5 i znika", is_equal_approx(player.chip, 0.5) and not is_instance_valid(b), "chip=%.1f" % player.chip)
	player.chip = 0.0
	player._invuln = 0.0
	var wall2 := _block(Vector2(x0 + 400.0, y - 30.0), Vector2(6.0, 120.0))
	var b2 = BoulderScript.new()
	level.add_child(b2)
	b2.global_position = Vector2(x0 + 340.0, y - 30.0)
	b2.vel = Vector2(400.0, 0.0)
	await get_tree().create_timer(0.35).timeout
	check("głaz/lot: ściana zatrzymuje głaz (znika bez obrażeń)", not is_instance_valid(b2) or b2.is_queued_for_deletion(), "")
	player.hp = hp_keep
	player.chip = 0.0
	for n in [w, dummy, wall2, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Dyrektor: skład grup wg czasu i napięcia (ENEMY_PLAN.md F3.10)

## Okna czasu i napięcia w tabelach zestawów, tabele map, skala `dread`, licznik czasu fazy celu.
func _test_director_composition() -> void:
	var D := Director
	var W := D.window_factor
	check("skład/okno: początek 180 s z narastaniem 60 s — 0 w 180, 0,5 w 210, 1 w 240", W.call(180.0, [180.0, INF], 60.0) == 0.0 and absf(W.call(210.0, [180.0, INF], 60.0) - 0.5) < 0.001 and W.call(240.0, [180.0, INF], 60.0) == 1.0)
	check("skład/okno: początek 0 = od zawsze, koniec spada liniowo po `fade` (1 do końca, 0,5 w połowie, 0 po)", W.call(0.0, [0.0, 100.0], 50.0) == 1.0 and W.call(100.0, [0.0, 100.0], 50.0) == 1.0 and absf(W.call(125.0, [0.0, 100.0], 50.0) - 0.5) < 0.001 and W.call(150.0, [0.0, 100.0], 50.0) == 0.0)
	var e := [10.0, ["a"], {"time": [180.0, INF], "tension": [0.2, INF]}]
	check("skład/waga: czas i napięcie mnożą się (za wcześnie = 0, za cicho = 0, oba spełnione = pełna waga, bez kontekstu = sama waga)",
		D.entry_weight(e, {"time": 100.0, "tension": 0.5}) == 0.0 and D.entry_weight(e, {"time": 400.0, "tension": 0.05}) == 0.0 and D.entry_weight(e, {"time": 400.0, "tension": 0.5}) == 10.0 and D.entry_weight(e, {}) == 10.0 and D.entry_weight([7.0, ["a"]], {"time": 1.0}) == 7.0)
	var early := {"time": 0.0, "tension": 0.0}
	var late := {"time": 800.0, "tension": 0.6}
	var odds_early: Array = D.group_odds(D.GROUPS, early)
	var odds_late: Array = D.group_odds(D.GROUPS, late)
	var sum_late := 0.0
	for o in odds_late:
		sum_late += float(o)
	check("skład/domyślna: na starcie i w ciszy tylko pary Trzosków (100%)", float(odds_early[0]) == 100.0 and D.pick_group(D.GROUPS, 0.0, early) == ["trzosek", "trzosek"] and D.pick_group(D.GROUPS, 0.999, early) == ["trzosek", "trzosek"], str(odds_early))
	check("skład/domyślna: po 13 min przy hałasie wszystkie zestawy możliwe (też Wołek i 2 Ślepce), szanse sumują się do 100%", absf(sum_late - 100.0) < 0.5 and D.pick_group(D.GROUPS, 0.999, late) == ["zerca"] and not odds_late.has(0.0), str(odds_late))
	var quiet_late: Array = D.group_odds(D.GROUPS, {"time": 800.0, "tension": 0.0})
	check("skład/napięcie: w ciszy (napięcie 0) nawet po 13 min tylko Trzoski — Ślepce i Wołek wymagają hałasu (wagi 0)", float(quiet_late[3]) == 0.0 and float(quiet_late[4]) == 0.0 and float(quiet_late[5]) == 0.0 and float(quiet_late[2]) == 0.0, str(quiet_late))
	var mid := {"time": 300.0, "tension": 0.3}
	var m1: Array = D.group_odds(D.GROUPS_BY_MAP["z1_m1"], mid)
	var m2: Array = D.group_odds(D.GROUPS_BY_MAP["z1_m2"], mid)
	var m2_ślepiec := 0.0
	for i in D.GROUPS_BY_MAP["z1_m2"].size():
		if "slepiec" in D.GROUPS_BY_MAP["z1_m2"][i][1]:
			m2_ślepiec += float(m2[i])
	var m1_ślepiec := false
	for g in D.GROUPS_BY_MAP["z1_m1"]:
		m1_ślepiec = m1_ślepiec or ("slepiec" in g[1])
	check("skład/mapy: 1.1 nie ma Ślepców, 1.2 (głośna) ma ich wyraźnie (> 20% po 5 min przy hałasie)", not m1_ślepiec and m2_ślepiec > 20.0, "m2 ślepiec %.1f%%" % m2_ślepiec)
	check("skład/mapy: 1.1 po 5 min bez Wołka (wchodzi po 8 min)", float(m1[3]) == 0.0 and float(D.group_odds(D.GROUPS_BY_MAP["z1_m1"], {"time": 700.0, "tension": 0.3})[3]) > 0.0, str(m1))

	# każda tabela: w całej siatce czas × napięcie jest z czego losować, a na starcie tylko pierwszy zestaw (podstawa)
	var Defs := load("res://scripts/enemy_defs.gd")
	var tables: Dictionary = {"domyślna": D.GROUPS}
	for m in D.GROUPS_BY_MAP:
		tables[m] = D.GROUPS_BY_MAP[m]
	var empty_at := []
	var not_mobile := []
	var early_extra := []
	for name in tables:
		var t: Array = tables[name]
		for ti in range(0, 1201, 30):
			for te in 15:
				if D.group_odds(t, {"time": float(ti), "tension": 0.05 * float(te)}).max() <= 0.0:
					empty_at.append("%s %d/%d" % [name, ti, te])
		var o0: Array = D.group_odds(t, early)
		for i in range(1, o0.size()):
			if float(o0[i]) > 0.0:
				early_extra.append("%s #%d" % [name, i])
		for g in t:
			for k in g[1]:
				var d: Dictionary = Defs.DEFS[String(k)]
				if float(d["speed"]) <= 0.0 or d.get("hang", false) or d.get("moth", false) or d.get("behavior", "") == "mimic" or d.get("fly", false):
					not_mobile.append(String(k))
	check("skład/tabele: w całej siatce czas × napięcie każda tabela ma z czego losować", empty_at.is_empty(), str(empty_at.slice(0, 5)))
	check("skład/tabele: na starcie (czas 0, cisza) wszystkie tabele dają tylko pierwszy zestaw", early_extra.is_empty(), str(early_extra))
	check("skład/tabele: wędrować mogą tylko ruchome rodzaje (bez wiszących, stojących, latających i Mimika)", not_mobile.is_empty(), str(not_mobile))

	# czas × dread; licznik czasu fazy celu
	var keep_t: float = D._run_t
	var keep_tension: float = D.tension
	var keep_level: int = Difficulty.level
	D._run_t = 300.0
	D.tension = 0.4
	Difficulty.set_level(Difficulty.Level.EASY)
	var c_easy: Dictionary = D.build_ctx()
	Difficulty.set_level(Difficulty.Level.HARD)
	var c_hard: Dictionary = D.build_ctx()
	Difficulty.set_level(keep_level)
	check("skład/trudność: czas składu = czas fazy × dread (łatwy 180 s, trudny 450 s), napięcie i spokój z Dyrektora",
		absf(float(c_easy["time"]) - 300.0 * 0.6) < 0.01 and absf(float(c_hard["time"]) - 300.0 * 1.5) < 0.01 and is_equal_approx(float(c_hard["tension"]), 0.4) and c_hard.has("quiet"), "%.0f / %.0f" % [c_easy["time"], c_hard["time"]])
	D._run_t = 123.0
	D.reset()
	check("skład/czas: reset (nowa misja, wipe) zeruje licznik czasu fazy celu", D._run_t == 0.0)

	# integracja: `_spawn_group` losuje z kontekstem, loguje skład i stawia wędrowców (na realnej mapie, przy graczu)
	var spawned_before: int = D._roamers.size()
	D._run_t = 700.0
	D.tension = 0.5
	var keep_pos: Vector2 = player.global_position
	var nav_ids: Array = level.nav.get_point_ids()
	player.global_position = level.nav.get_point_position(nav_ids[nav_ids.size() / 2]) + Vector2(0.0, -4.0)
	D._spawn_group([player])
	await get_tree().physics_frame
	check("skład/spawn: `_spawn_group` z kontekstem stawia grupę wędrowców (na punkcie siatki 380–640 px od gracza)", D._roamers.size() > spawned_before, str(D._roamers.size() - spawned_before))
	player.global_position = keep_pos
	for n in D._roamers.duplicate():
		D._despawn(n)
	D._roamers.clear()
	D._groups.clear()
	D._run_t = keep_t
	D.tension = keep_tension
	D._run_t = keep_t
	D.tension = keep_tension
	await get_tree().physics_frame

# ---------------------------------------------------------------- podział enemy.gd na zachowania rodzajów (ENEMY_PLAN.md F2c / F3.1c)

## Każdy rodzaj z `behavior` w danych ma klasę zachowania, nieznane / puste zachowanie daje bezpieczną bazę, a rdzeń (`enemy.gd`) nie rozgałęzia się już po nazwie rodzaju.
func _test_behaviors() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var Base := load("res://scripts/enemy_behavior.gd")
	var bad := []
	var kinds_with := {}
	for k in Defs.DEFS:
		var b := String(Defs.DEFS[k].get("behavior", ""))
		if b != "":
			kinds_with[k] = b
			if not Base.BEHAVIORS.has(b) or not ResourceLoader.exists(String(Base.BEHAVIORS[b])):
				bad.append("%s→%s" % [k, b])
	check("zachowania: każdy `behavior` z enemy_defs.gd ma klasę (BEHAVIORS)", bad.is_empty(), str(bad))
	check("zachowania: rodzaje z własną mechaniką mają zachowanie (10 rodzajów)", kinds_with.size() == 10 and kinds_with.get("podsluchacz") == "listener" and kinds_with.get("wolek") == "bruiser" and kinds_with.get("slepiec") == "blind" and kinds_with.get("trzosek") == "pack", str(kinds_with))
	var unknown = Base.create("nie_ma_takiego", null)
	var empty = Base.create("", null)
	check("zachowania: pusta i nieznana nazwa → baza z domyślnymi hakami (bez błędu)", unknown != null and empty != null and unknown.damage_mult() == 1.0 and unknown.threat_ok() and not unknown.tick_special(0.1) and unknown.derive_pre() == -1 and empty.returns_home() and not empty.holds_still())
	var made := true
	for b in Base.BEHAVIORS:
		var inst = Base.create(String(b), null)
		made = made and inst != null and inst.get_script().resource_path == String(Base.BEHAVIORS[b])
	check("zachowania: fabryka tworzy każdą zarejestrowaną klasę", made)
	var src := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var branches := 0
	for pat in ['kind == "', 'kind != "']:
		var from := 0
		while true:
			var i := src.find(pat, from)
			if i < 0:
				break
			branches += 1
			from = i + 1
	check("zachowania: rdzeń enemy.gd nie rozgałęzia się po nazwie rodzaju (żadnego `kind == \"…\"`)", branches == 0, "%d wystąpień" % branches)
	var w := _spawn("wolek", Vector2(FAR_X + 28000.0, -14000.0))
	var t := _spawn("trzosek", Vector2(FAR_X + 28100.0, -14000.0))
	w.set_physics_process(false)
	t.set_physics_process(false)
	check("zachowania: węzeł wroga tworzy zachowanie wg danych (Wołek: bruiser, Trzosek: pack)", w._beh.get_script().resource_path.ends_with("enemy_bruiser.gd") and t._beh.get_script().resource_path.ends_with("enemy_pack.gd"))
	w.queue_free()
	t.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- F4a: fundament elit (flaga elite, klucz downs, ogłuszenie gracza)

## Ogłuszenie gracza (Kapłan): trwa zadany czas, blokuje kolejne ogłuszenie na STUN_IMMUNITY s po nim, nie działa na leżącego; Dyrektor liczy elity i okna `downs`.
func _test_elite_foundation() -> void:
	var keep_hp: int = player.hp
	player.dead = false
	player.stun_t = 0.0
	player._stun_immune = 0.0
	player.apply_stun(0.8)
	check("stun gracza: ogłuszenie 0,8 s ustawia stan i niewrażliwość na kolejne (0,8 + 3 s)", player.is_stunned() and is_equal_approx(player.stun_t, 0.8) and is_equal_approx(player._stun_immune, 0.8 + player.STUN_IMMUNITY), "%.2f / %.2f" % [player.stun_t, player._stun_immune])
	player.stun_t = 0.0
	player.apply_stun(2.0)
	check("stun gracza: w czasie niewrażliwości kolejny stun jest ignorowany", not player.is_stunned())
	player._stun_immune = 0.0
	player.dead = true
	player.apply_stun(1.0)
	check("stun gracza: leżącego nie ogłusza", not player.is_stunned())
	player.dead = false
	player._stun_immune = 0.0
	player.apply_stun(0.0)
	check("stun gracza: zerowy czas nic nie robi", not player.is_stunned())
	player.stun_t = 0.0
	player._stun_immune = 0.0
	player.hp = keep_hp

	var D := Director
	var Defs := load("res://scripts/enemy_defs.gd")
	var consistent := true
	for k in Defs.elite_kinds():
		consistent = consistent and Defs.is_elite(String(k))
	check("elity: `elite_kinds` zwraca tylko rodzaje z flagą, zwykłe rodzaje nie są elitami", consistent and not Defs.is_elite("trzosek") and not Defs.is_elite("wolek") and not Defs.is_elite("nie_ma"))
	var with_elite := [10.0, ["wolek", "trzosek"]]
	var without := [10.0, ["trzosek", "trzosek"]]
	var full := {"elites": 1, "elite_kinds": ["wolek"]}
	var free := {"elites": 0, "elite_kinds": ["wolek"]}
	check("elity: przy zajętym limicie zestawy z elitą odpadają (waga 0), zwykłe zostają", D.entry_weight(with_elite, full) == 0.0 and D.entry_weight(without, full) == 10.0 and D.entry_weight(with_elite, free) == 10.0 and D.MAX_ELITES == 1)
	var after_down := [10.0, ["trzosek"], {"downs": [1, INF]}]
	var early_only := [10.0, ["trzosek"], {"downs": [0, 1]}]
	check("elity: okno `downs` — zestaw dopiero po pierwszym upadku, a okno [0,1] wyłącza się od drugiego",
		D.entry_weight(after_down, {"downs": 0}) == 0.0 and D.entry_weight(after_down, {"downs": 1}) == 10.0 and D.entry_weight(after_down, {"downs": 4}) == 10.0 and D.entry_weight(early_only, {"downs": 1}) == 10.0 and D.entry_weight(early_only, {"downs": 2}) == 0.0)
	var ctx: Dictionary = D.build_ctx()
	check("elity: kontekst Dyrektora ma upadki, liczbę żywych elit i rodzaje elit", ctx.has("downs") and ctx.has("elites") and ctx.has("elite_kinds") and int(ctx["elites"]) == D.count_elites() and int(ctx["elites"]) == 0, str(ctx))
	var gt := ctx.duplicate()
	gt["time"] = 900.0
	gt["tension"] = 0.5
	check("elity: istniejące tabele bez elit działają jak dotąd przy pełnym kontekście", float(D.group_odds(D.GROUPS, gt)[0]) > 0.0 and absf(float(D.group_odds(D.GROUPS, gt).reduce(func(a, b): return a + b)) - 100.0) < 0.5)
	await get_tree().physics_frame

# ---------------------------------------------------------------- F4b: Kapłan (elita wsparcia: krzyk ze stunem, leczenie Trzosków)

func _test_priest() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["kaplan"]
	check("Kapłan/dane: 250 HP, elita, zachowanie priest, fala 6 m (96 px), stun 0,8 s, brak ciosu w zwarciu (damage 0)",
		float(cfg["hp"]) == 250.0 and bool(cfg["elite"]) and cfg["behavior"] == "priest" and is_equal_approx(float(cfg["priest"]["radius"]), 96.0) and is_equal_approx(float(cfg["priest"]["stun"]), 0.8) and int(cfg["damage"]) == 0 and Defs.elite_kinds().has("kaplan"))
	var y := -15000.0
	var strip := _floor(FAR_X + 29000.0, FAR_X + 29600.0, y)
	var x0 := FAR_X + 29300.0
	var k := _spawn("kaplan", Vector2(x0, y))
	k.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	k.active = true
	var keep_pos: Vector2 = player.global_position
	var keep_dead: bool = player.dead
	player.dead = false
	player.stun_t = 0.0
	player._stun_immune = 0.0
	k._beh.scream_cd = 0.0
	k._beh.heal_t = 99.0
	player.global_position = Vector2(x0 + 104.0, y)                          # w polu zapowiedzi (110 px), ale poza falą (96 px)
	check("Kapłan/zapowiedź: gracz bliżej niż 110 px → zapowiedź krzyku (stan special, oczy, pierścień o promieniu fali)",
		not k._beh.tick_phase(0.016, player) and k._sp == 1 and k.winding and is_equal_approx(float(k.view_info()["tele"]), 96.0) and bool(k.view_info()["alert"]), "sp=%d tele=%s" % [k._sp, str(k.view_info()["tele"])])
	check("Kapłan/zapowiedź: w trakcie stoi w miejscu, tick przejmuje ruch (true)", k._beh.tick_phase(0.016, player))
	k._beh.tele_t = 0.0
	k._beh.tick_phase(0.016, player)
	check("Kapłan/krzyk: gracz poza falą (104 px > 96 px) nie jest ogłuszony, krzyk kończy zapowiedź i wchodzi w przerwę 8 s",
		not player.is_stunned() and k._sp == 0 and not k.winding and k._beh.scream_cd > 7.0 and float(k.view_info()["tele"]) == 0.0, "stun=%s sp=%d cd=%.1f" % [player.is_stunned(), k._sp, k._beh.scream_cd])
	k._beh.scream_cd = 0.0
	player.global_position = Vector2(x0 + 60.0, y)
	k._beh.tick_phase(0.016, player)
	k._beh.tele_t = 0.0
	k._beh.tick_phase(0.016, player)
	check("Kapłan/krzyk: gracz w fali (60 px) dostaje stun 0,8 s", player.is_stunned() and is_equal_approx(player.stun_t, 0.8), "%.2f" % player.stun_t)
	player.stun_t = 0.0
	player._stun_immune = 0.0
	k._beh.scream_cd = 5.0
	player.global_position = Vector2(x0 + 40.0, y)
	check("Kapłan/przerwa: w czasie przerwy krzyku nie zaczyna zapowiedzi", not k._beh.tick_phase(0.016, player) and k._sp == 0)
	check("Kapłan/zwarcie: nie bije (może_atakować = false, brak zapowiedzi ciosu przy graczu w zasięgu ręki)", not k._beh.may_attack() and (func():
		k._cd = 0.0
		k._try_begin_attack(player)
		return k._windup == 0.0 and not k.winding).call())
	# dystans: za blisko → cofa się, w pasie stoi, dalej zostawia pościg
	k.velocity = Vector2.ZERO
	var near_hold: bool = k._beh.chase_hold(player, Vector2(60.0, 0.0), 42.0)
	var back_v: float = k.velocity.x
	k.velocity = Vector2(5.0, 0.0)
	var mid_hold: bool = k._beh.chase_hold(player, Vector2(150.0, 0.0), 42.0)
	var mid_v: float = k.velocity.x
	var far_hold: bool = k._beh.chase_hold(player, Vector2(260.0, 0.0), 42.0)
	check("Kapłan/dystans: gracz 60 px → cofa się (w lewo), 150 px → stoi, 260 px → pościg rdzenia", near_hold and back_v < 0.0 and mid_hold and mid_v == 0.0 and not far_hold, "%s %.0f / %s %.0f / %s" % [near_hold, back_v, mid_hold, mid_v, far_hold])

	# leczenie Trzosków: tylko ranni, tylko Trzoski (pack), tylko w zasięgu, nie ponad maks.
	player.global_position = Vector2(x0 + 400.0, y)
	var hurt := _spawn("trzosek", Vector2(x0 - 60.0, y))
	var whole := _spawn("trzosek", Vector2(x0 - 40.0, y))
	var far_t := _spawn("trzosek", Vector2(x0 - 300.0, y))
	var blind := _spawn("slepiec", Vector2(x0 + 50.0, y))
	for t in [hurt, whole, far_t, blind]:
		t.set_physics_process(false)
		t.active = true
	await get_tree().physics_frame
	hurt.hp = 10.0
	far_t.hp = 10.0
	blind.hp = 20.0
	k._beh.heal_t = 0.0
	k._beh._tick_heal(0.016)
	var max_hp: float = hurt._max_hp
	check("Kapłan/leczenie: ranny Trzosek w zasięgu +10% maks. HP, cały bez zmian, daleki i Ślepiec nie leczeni",
		absf(hurt.hp - (10.0 + max_hp * 0.10)) < 0.01 and whole.hp == whole._max_hp and far_t.hp == 10.0 and blind.hp == 20.0, "hurt=%.2f/%.1f far=%.1f" % [hurt.hp, max_hp, far_t.hp])
	check("Kapłan/leczenie: wiązka do leczonego widoczna w view_info (beams, 0,6 s)", (k.view_info()["beams"] as PackedVector2Array).size() == 1 and k._heal_fx_t > 0.5)
	hurt.hp = hurt._max_hp - 0.5
	k._beh.heal_t = 0.0
	k._beh._tick_heal(0.016)
	check("Kapłan/leczenie: nie przekracza maksymalnego HP", hurt.hp == hurt._max_hp, "%.2f" % hurt.hp)
	k._sp = 1
	k._beh.heal_t = 0.0
	hurt.hp = 5.0
	k._beh.tick_phase(0.016, player)
	check("Kapłan/leczenie: w zapowiedzi krzyku nie leczy", hurt.hp == 5.0)
	k._sp = 0
	k.winding = false

	# śmierć: Trzoski w pobliżu tracą morale, leczenie ustaje
	var fear0: float = whole._beh.fear
	k._beh.on_death()
	check("Kapłan/śmierć: Trzosek w pobliżu traci morale (+0,34), daleki nie", is_equal_approx(whole._beh.fear - fear0, 0.34) and far_t._beh.fear == 0.0, "%.2f / %.2f" % [whole._beh.fear, far_t._beh.fear])

	# Dyrektor: elita w zestawie, limit jednej elity
	var D := Director
	check("Kapłan/Dyrektor: żywa elita liczy się do limitu — zestaw z Kapłanem odpada, bez żywej elity wraca",
		(func():
			var ctx: Dictionary = D.build_ctx()
			ctx["time"] = 900.0
			ctx["tension"] = 0.5
			var entry: Array = []
			for g in D.GROUPS:
				if "kaplan" in g[1]:
					entry = g
			var w_with: float = D.entry_weight(entry, ctx)
			return not entry.is_empty() and D.count_elites() == 1 and w_with == 0.0 and D.entry_weight(entry, {"time": 900.0, "tension": 0.5, "elites": 0, "elite_kinds": ["kaplan"]}) > 0.0).call())
	check("Kapłan/mapa: litera A w mapach stawia Kapłana (znacznik i odprawa)", level.THREAT_CHARS.get("A") == "kaplan")
	player.global_position = keep_pos
	player.dead = keep_dead
	player.stun_t = 0.0
	player._stun_immune = 0.0
	for n in [k, hurt, whole, far_t, blind, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- F4c: Rzeźnik (miniboss: sparametryzowany Wołek, szarża przez barykady)

func _test_butcher() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["rzeznik"]
	check("Rzeźnik/dane: 600 HP, elita, pancerz 4, szarża 1,0 s zapowiedzi / 1,4 s / ×3,2 / przerwa 9 s, bez rzutów, łamie barykady, odporny na ogłuszenie",
		float(cfg["hp"]) == 600.0 and bool(cfg["elite"]) and float(cfg["armor"]) == 4.0 and cfg["behavior"] == "bruiser" and not bool(cfg["throws"]) and bool(cfg["breaks_barricades"]) and bool(cfg["stun_resist"])
		and is_equal_approx(float(cfg["charge"]["windup"]), 1.0) and is_equal_approx(float(cfg["charge"]["time"]), 1.4) and is_equal_approx(float(cfg["charge"]["mult"]), 3.2) and is_equal_approx(float(cfg["charge"]["cd"]), 9.0) and Defs.elite_kinds().has("rzeznik"))
	var y := -16000.0
	var strip := _floor(FAR_X + 30000.0, FAR_X + 30900.0, y)
	var x0 := FAR_X + 30100.0
	var r := _spawn("rzeznik", Vector2(x0, y))
	r.set_physics_process(false)
	var dummy := Node2D.new()
	level.add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	r.active = true
	r._beh.charge_cd = 0.0
	r._beh.throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 200.0, y)
	check("Rzeźnik/szarża: cel 200 px na tym samym poziomie → zapowiedź 1,0 s (stan special, winding)", r._beh.tick_phase(0.016, dummy) and r._sp == 1 and r.winding and is_equal_approx(r._beh.sp_t, 1.0 * Difficulty.m("enemy_windup")), "sp=%d t=%.2f" % [r._sp, r._beh.sp_t])
	r._beh.sp_t = 0.0
	r._beh.tick_phase(0.016, dummy)
	var speed_expect: float = 60.0 * Difficulty.m("enemy_speed") * 3.2
	check("Rzeźnik/szarża: po zapowiedzi pędzi 1,4 s z prędkością ×3,2 (dane `charge`, nie stałe Wołka)", r._sp == 2 and is_equal_approx(r._beh.sp_t, 1.4) and absf(r.velocity.x - 0.0) >= 0.0, "t=%.2f" % r._beh.sp_t)
	r._beh.tick_phase(0.016, dummy)
	check("Rzeźnik/szarża: prędkość w szarży = prędkość × mnożnik trudności × 3,2", absf(r.velocity.x - speed_expect) < 0.01, "%.1f vs %.1f" % [r.velocity.x, speed_expect])
	r._beh.sp_t = 0.0
	r._beh.tick_phase(0.016, dummy)
	check("Rzeźnik/szarża: po niej przerwa 9 s (× trudność)", r._sp == 0 and is_equal_approx(r._beh.charge_cd, 9.0 * Difficulty.m("enemy_cd")), "%.2f" % r._beh.charge_cd)
	# bez rzutów: skrzynia obok i cel w zasięgu rzutu, szarża zablokowana cooldownem
	var crate := _crate_at(Vector2(x0 + 10.0, y - 7.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	r._beh.charge_cd = 99.0
	r._beh.boulder_cd = 0.0
	dummy.global_position = Vector2(x0 + 140.0, y)
	check("Rzeźnik/bez rzutów: skrzynia obok i cel w zasięgu rzutu — nie rzuca ani skrzynią, ani głazem", not r._beh.tick_phase(0.016, dummy) and r._sp == 0)
	crate.queue_free()
	# odporność na ogłuszenie i odrzut
	r.velocity = Vector2.ZERO
	r._windup = 0.5
	r._windup_target = dummy
	r.winding = true
	r.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": r.global_position, "shooter": int(player.player_id), "type": "bullet", "stun": 1.0, "knock": 200.0})
	check("Rzeźnik/odporność: mocne ogłuszenie nie przerywa zapowiedzi i nie chwieje (stagger 0), odrzut ≤ 5% (≤ 10 px/s przy 200)", r._windup == 0.5 and r._stagger == 0.0 and absf(r.velocity.x) <= 10.0, "windup=%.2f stagger=%.2f vx=%.1f" % [r._windup, r._stagger, r.velocity.x])
	r._windup = 0.0
	r.winding = false
	r._windup_target = null

	# barykada: szarża przebija zamurowane przejście, Wołek o nie się rozbija
	var wall = level.BRICK_WALL.new()
	wall.name = "TestWallR"
	wall.rows = 3
	wall.position = Vector2(x0 + 400.0, y)
	level.add_child(wall)
	var br := _spawn("rzeznik", Vector2(x0 + 330.0, y))
	br.active = true
	br._sp = 2
	br._beh.sp_dir = 1.0
	br._beh.sp_t = 1.2
	br._beh.charge_hit = true
	var wall2 = level.BRICK_WALL.new()
	wall2.name = "TestWallW"
	wall2.rows = 3
	wall2.position = Vector2(x0 + 800.0, y)
	level.add_child(wall2)
	var wk := _spawn("wolek", Vector2(x0 + 730.0, y))
	wk.active = true
	wk._sp = 2
	wk._beh.sp_dir = 1.0
	wk._beh.sp_t = 1.2
	wk._beh.charge_hit = true
	await get_tree().create_timer(1.0).timeout
	check("Rzeźnik/barykada: szarża rozbija zamurowane przejście i nie ogłusza się o nie", (not is_instance_valid(wall) or wall.hp <= 0.0) and br._sp != 4, "hp=%s sp=%d" % [str(wall.hp) if is_instance_valid(wall) else "rozbita", br._sp])
	check("Rzeźnik/barykada: zwykły Wołek o taką samą ścianę się rozbija (ogłuszony, ściana cała)", is_instance_valid(wall2) and wall2.hp == wall2.WALL_HP and wk._sp == 4, "hp=%s sp=%d" % [str(wall2.hp) if is_instance_valid(wall2) else "?", wk._sp])
	check("Rzeźnik/mapa: litera U w mapach stawia Rzeźnika, Dyrektor ma Rzeźnika w tabelach", level.THREAT_CHARS.get("U") == "rzeznik" and (func():
		for g in Director.GROUPS:
			if g[1] == ["rzeznik"]:
				return true
		return false).call())
	for n in [r, br, wk, dummy, wall, wall2, strip]:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- F4d: Żerca (zamaskowany porywacz leżących graczy)

func _test_devourer() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["zerca"]
	check("Żerca/dane: 300 HP, elita, zachowanie devourer, 20 s do „zjedzenia”, węch 520 px, niesie ×0,6",
		float(cfg["hp"]) == 300.0 and bool(cfg["elite"]) and cfg["behavior"] == "devourer" and is_equal_approx(float(cfg["devour"]["time"]), 20.0) and is_equal_approx(float(cfg["devour"]["sense"]), 520.0) and is_equal_approx(float(cfg["devour"]["carry_speed"]), 0.6) and Defs.elite_kinds().has("zerca"))
	var y := -17000.0
	var strip := _floor(FAR_X + 31000.0, FAR_X + 31900.0, y)
	var x0 := FAR_X + 31200.0
	var keep_pos: Vector2 = player.global_position
	var keep_dead: bool = player.dead
	var keep_hp: int = player.hp
	var keep_spawn: Vector2 = player._spawn_point
	player._spawn_point = Vector2(x0 - 600.0, y)

	# stan „zabrany” w graczu: wykrwawianie stoi, pozycja narzucona, nie da się go podnieść
	player.dead = true
	player.taken = false
	player.bleed_left = 6.0
	player.global_position = Vector2(x0 + 100.0, y)
	player.apply_take(true, Vector2(x0 + 140.0, y - 4.0), 20.0)
	player._down_physics(2.0)
	check("zabrany: pozycja narzucona przez Żercę, wykrwawianie wstrzymane (6 s → 6 s), czas do kary widoczny",
		player.taken and is_equal_approx(player.taken_t, 20.0) and is_equal_approx(player.bleed_left, 6.0) and player.global_position.distance_to(Vector2(x0 + 140.0, y - 4.0)) < 1.0, "bleed=%.1f pos=%s" % [player.bleed_left, str(player.global_position)])
	player.request_revive()
	check("zabrany: nie da się go podnieść, dopóki Żerca żyje", player.dead and player.taken)
	player.apply_take(false, player.global_position)
	check("zabrany: puszczony (Żerca zabity) znów leży i ma co najmniej 3 s do wykrwawienia, można go podnieść", not player.taken and player.dead and player.bleed_left >= player.TAKEN_MIN_BLEED - 0.001, "bleed=%.1f" % player.bleed_left)
	player.bleed_left = 1.0
	player.apply_take(true, Vector2(x0, y - 4.0), 20.0)
	player.apply_devour()
	check("kara po 20 s: gracz wraca na start misji (pozycja startu, żyje z 1 HP), nie jest już zabrany", not player.dead and not player.taken and player.hp == 1 and player.global_position.distance_to(player._spawn_point) < 1.0, "dead=%s hp=%d" % [player.dead, player.hp])
	player.apply_devour()
	check("kara: bez porwania `apply_devour` nic nie robi", not player.taken and not player.dead)

	# zamaskowany Żerca: niewidoczny, nietrafialny, nie reaguje na żywych
	var z := _spawn("zerca", Vector2(x0 + 110.0, y))
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	z.set_physics_process(false)
	player.dead = false
	player.global_position = Vector2(x0 + 100.0, y)
	var hs = z.get_meta("hurt_shape") if z.has_meta("hurt_shape") else null
	check("Żerca/maska: na starcie zamaskowany — niewidoczny, strefa trafień wyłączona, boty go nie widzą, nie bije, view_info.hidden",
		z._sp == 2 and z._beh.is_hidden() and not z.visible and hs != null and bool(hs.disabled) and not z.is_threat() and not z._beh.may_attack() and bool(z.view_info()["hidden"]), "sp=%d vis=%s hurt_off=%s" % [z._sp, z.visible, str(hs.disabled) if hs != null else "?"])
	z.active = true
	var vx_before: float = z.velocity.x
	check("Żerca/maska: żywy gracz tuż obok nic nie zmienia — przejmuje tik, nie ma celu ani śladu, stoi", z._beh.tick_special(0.016) and z._target == null and not z._has_lead and z._sp == 2 and absf(z.velocity.x - vx_before) < 1.0)

	# wyczuwa leżącego, skrada się, porwanie = ujawnienie
	player.dead = true
	player.taken = false
	player.bleed_left = 8.0
	player.global_position = Vector2(x0 + 60.0, y)
	z._beh.scan_t = 0.0
	var handled: bool = z._beh.tick_special(0.016)
	check("Żerca/węch: leżący gracz w pobliżu (po trasie < 520 px, w świecie testu tłumienie ×3) → skrada się (ślad na ofiarę), nadal ukryty", handled and z._beh.prey == null and z._sp == 2 and z._has_lead and z._last_known.distance_to(player.global_position) < 2.0, "lead=%s sp=%d" % [str(z._last_known), z._sp])
	z.global_position = Vector2(x0 + 50.0, y)
	z._beh.scan_t = 0.0
	z._beh.tick_special(0.016)
	await get_tree().process_frame
	await get_tree().process_frame
	check("Żerca/porwanie: przy ofierze (< 14 px) porywa ją i **ujawnia się** — widoczny, trafialny, stan special, ofiara zabrana z czasem 20 s",
		z._beh.prey == player and player.taken and z._sp == 1 and not z._beh.is_hidden() and z.visible and not bool(hs.disabled) and player.taken_t > 19.0 and bool(z.view_info()["carrying"]) and not bool(z.view_info()["hidden"]) and z.is_threat(), "taken=%s sp=%d vis=%s" % [player.taken, z._sp, z.visible])
	var bleed_before: float = player.bleed_left
	z._home = Vector2(x0 + 400.0, y)
	z._beh.tick_phase(1.0, null)
	check("Żerca/niesie: ciągnie ofiarę ku domowi, wykrwawianie stoi, czas do kary maleje (20 → 19 s)", z._beh.prey == player and absf(player.bleed_left - bleed_before) < 0.01 and absf(player.taken_t - 19.0) < 0.2 and z.velocity.x > 0.0, "t=%.1f vx=%.0f" % [player.taken_t, z.velocity.x])
	z._beh.tick_phase(30.0, null)
	await get_tree().process_frame
	await get_tree().process_frame
	check("Żerca/kara: po 20 s ofiara wraca na start (żyje, nie zabrana), a Żerca po posiłku znów się chowa", z._beh.prey == null and not player.taken and not player.dead and player.hp == 1 and z._sp == 2 and not z.visible, "dead=%s sp=%d vis=%s" % [player.dead, z._sp, z.visible])
	# ratunek: zabity Żerca puszcza ofiarę
	player.dead = true
	player.bleed_left = 8.0
	player.global_position = Vector2(x0 + 50.0, y)
	z.global_position = Vector2(x0 + 50.0, y)
	z._beh.cand = null
	z._beh.scan_t = 0.0
	z._beh.tick_special(0.016)
	var was_taken: bool = player.taken
	z._beh.on_death()
	check("Żerca/ratunek: zabity w trakcie porwania puszcza ofiarę (leży, ≥ 3 s do wykrwawienia)", was_taken and not player.taken and player.dead and player.bleed_left >= 3.0 - 0.001 and z._beh.prey == null, "was=%s taken=%s" % [was_taken, player.taken])
	# trafiony w ukryciu (wybuch) — ujawnia się
	z._beh._hide()
	z._beh.on_hit(false)
	check("Żerca/maska: trafiony w ukryciu (np. wybuch) ujawnia się", z._sp == 0 and not z._beh.is_hidden())
	# żywy człowiek na nogach nie jest ofiarą
	player.dead = false
	z._beh.cand = null
	z._beh.scan_t = 0.0
	check("Żerca/węch: gracz na nogach nie jest ofiarą (ujawniony Żerca nie przejmuje ruchu)", not z._beh.tick_phase(0.016, null))

	# Dyrektor: dopiero po pierwszym upadku
	var entry: Array = []
	for g in Director.GROUPS:
		if g[1] == ["zerca"]:
			entry = g
	check("Żerca/Dyrektor: zestaw z Żercą dopiero po pierwszym upadku (downs ≥ 1) i po 6 min; marker V w mapach",
		not entry.is_empty() and Director.entry_weight(entry, {"time": 900.0, "downs": 0}) == 0.0 and Director.entry_weight(entry, {"time": 900.0, "downs": 1}) > 0.0 and Director.entry_weight(entry, {"time": 100.0, "downs": 3}) == 0.0 and level.THREAT_CHARS.get("V") == "zerca")

	player.dead = keep_dead
	player.taken = false
	player.taken_t = 0.0
	player.hp = keep_hp
	player._spawn_point = keep_spawn
	player.global_position = keep_pos
	for n in [z, strip]:
		n.queue_free()
	await get_tree().physics_frame

func _finish() -> void:
	print("[ENEMY-TEST] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	get_tree().quit(1 if failed > 0 else 0)

# ---------------------------------------------------------------- hałas

## Zgłoszenie klienta (RPC `_report`) jest walidowane: ujemne, NaN i gigantyczne wartości nie mogą zmienić Uwagi.
func _test_noise_validation() -> void:
	check("hałas od klienta: ujemna wartość odrzucona", NoiseMgr.sane_amount(-100.0) == 0.0)
	check("hałas od klienta: NaN odrzucony", NoiseMgr.sane_amount(NAN) == 0.0)
	check("hałas od klienta: nieskończoność odrzucona", NoiseMgr.sane_amount(INF) == 0.0)
	check("hałas od klienta: gigantyczna wartość przycięta", NoiseMgr.sane_amount(1.0e9) == NoiseMgr.MAX_REPORT)
	check("hałas od klienta: zwykły strzał bez zmian", is_equal_approx(NoiseMgr.sane_amount(2.5), 2.5))
	var p := NoiseMgr.sane_pos(Vector2(1.0e9, -1.0e9))
	check("hałas od klienta: pozycja przycięta do mapy", absf(p.x) < 1.0e6 and absf(p.y) < 1.0e6, str(p))
	check("hałas od klienta: pozycja NaN zastąpiona", NoiseMgr.sane_pos(Vector2(NAN, 0.0)).is_finite())

## W jednej klatce fizyki zostaje najgłośniejsze zdarzenie — cichy krok po strzale nie przesłania strzału.
func _test_noise_same_frame() -> void:
	NoiseMgr.safe_zone = false
	NoiseMgr.last_noise_amount = 0.0
	var shot := Vector2(111.0, 22.0)
	var step := Vector2(333.0, 44.0)
	var serial0: int = NoiseMgr.noise_serial
	NoiseMgr.add_noise(2.0, shot, "test")
	NoiseMgr.add_noise(0.25, step, "test")
	check("ten sam tik: strzał nie jest nadpisany krokiem", NoiseMgr.last_noise_pos == shot and is_equal_approx(NoiseMgr.last_noise_amount, 2.0),
		"pozycja %s, głośność %.2f" % [NoiseMgr.last_noise_pos, NoiseMgr.last_noise_amount])
	check("ten sam tik: serial rośnie tylko za zapisane zdarzenie", NoiseMgr.noise_serial == serial0 + 1)
	NoiseMgr.add_noise(5.0, step, "test")
	check("ten sam tik: głośniejsze zdarzenie nadpisuje", NoiseMgr.last_noise_pos == step and is_equal_approx(NoiseMgr.last_noise_amount, 5.0))
	NoiseMgr.level = 0.0
	NoiseMgr.stalker_awake = false

## Budżet A* słuchania hałasu: SOUND_BUDGET trasy na klatkę fizyki, nadmiar czeka.
func _test_sound_budget() -> void:
	var granted := 0
	for i in Enemy.SOUND_BUDGET + 4:
		if Enemy._sound_slot():
			granted += 1
	check("budżet słuchania: dokładnie SOUND_BUDGET w jednej klatce", granted == Enemy.SOUND_BUDGET, "%d z %d" % [granted, Enemy.SOUND_BUDGET])

# ---------------------------------------------------------------- walka

## Ataki specjalne (lądowanie skoczka, szarża Wołka, ćma) skalują się trudnością jak zwykły cios.
func _test_scaled_damage() -> void:
	var e := _spawn("trzosek", Vector2(FAR_X, -4000.0))
	var prev: int = Difficulty.level
	Difficulty.set_level(Difficulty.Level.NORMAL)
	var normal: int = e._scaled_damage(2)
	Difficulty.set_level(Difficulty.Level.EASY)
	var easy: int = e._scaled_damage(2)
	var easy_min: int = e._scaled_damage(1)
	Difficulty.set_level(prev)
	check("obrażenia specjalne: normalny poziom bez zmian", normal == 2, str(normal))
	check("obrażenia specjalne: łatwy poziom mniejszy", easy < normal, str(easy))
	check("obrażenia specjalne: minimum 1", easy_min >= 1)
	e.queue_free()

## `deliver_hit(force)` omija niewrażliwość po trafieniu (kara za nieudane QTE Pijawki), zwykłe trafienie jej nie omija.
func _test_forced_hit() -> void:
	player.hp = 5
	player._invuln = 0.5
	player.deliver_hit(1, player.global_position + Vector2(10, 0), "test")
	check("niewrażliwość: zwykłe trafienie jest ignorowane", player.hp == 5, "hp %d" % player.hp)
	player.deliver_hit(1, player.global_position + Vector2(10, 0), "test", true)
	check("niewrażliwość: wymuszone trafienie przechodzi", player.hp == 4, "hp %d" % player.hp)
	player._invuln = 0.0
	player.hp = 5
	await get_tree().physics_frame

# ---------------------------------------------------------------- fizyka (własna geometria)

## Podłoga: prostokąt z górną krawędzią na `y`, od `x0` do `x1`, warstwa 1 (to, co widzą promienie wrogów).
func _floor(x0: float, x1: float, y: float) -> StaticBody2D:
	return _block(Vector2((x0 + x1) * 0.5, y + 4.0), Vector2(x1 - x0, 8.0))

func _block(center: Vector2, size: Vector2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	b.global_position = center
	level.add_child(b)
	return b

func _spawn(kind: String, pos: Vector2) -> CharacterBody2D:
	var e := ENEMY_SCENE.instantiate() as CharacterBody2D
	e.kind = kind
	level.add_child(e)
	e.global_position = pos
	e._home = pos                                          # `_ready` zapamiętał pozycję sprzed przestawienia — dom to miejsce testu, nie początek układu
	e._remote_pos = pos
	e._phys_x = pos.x
	e._last_x = pos.x
	return e

## Wołek rozpędza się tylko tam, gdzie ma podłogę pod całym rozbiegiem (i ścianę sprawdzoną na pełnym dystansie).
func _test_run_clear() -> void:
	var y := -3000.0
	var full := _floor(FAR_X, FAR_X + 400.0, y)
	var cut := _floor(FAR_X + 1000.0, FAR_X + 1120.0, y)         # podłoga kończy się 120 px od startu — dalej przepaść
	var wall := _block(Vector2(FAR_X + 2250.0, y - 30.0), Vector2(4.0, 60.0))
	var strip := _floor(FAR_X + 2000.0, FAR_X + 2400.0, y)
	var w1 := _spawn("wolek", Vector2(FAR_X + 40.0, y))
	var w2 := _spawn("wolek", Vector2(FAR_X + 1040.0, y))
	var w3 := _spawn("wolek", Vector2(FAR_X + 2040.0, y))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("rozbieg Wołka: ciągła podłoga — wolno", w1._beh._run_clear(1.0, 200.0))
	check("rozbieg Wołka: przepaść na trasie — nie rozpędza się", not w2._beh._run_clear(1.0, 200.0))
	check("rozbieg Wołka: ściana dalej niż 200 px — też blokuje (pełny dystans)", not w3._beh._run_clear(1.0, 260.0))
	check("rozbieg Wołka: ściana poza dystansem — nie blokuje", w3._beh._run_clear(1.0, 150.0))
	for n in [w1, w2, w3, full, cut, wall, strip]:
		n.queue_free()

## Cios wręcz nie przechodzi przez ścianę, ale poziomy promień nie blokuje celu stojącego na stopniu.
func _test_wall_between() -> void:
	var y := -3500.0
	var strip := _floor(FAR_X, FAR_X + 300.0, y)
	var wall := _block(Vector2(FAR_X + 80.0, y - 30.0), Vector2(4.0, 60.0))
	var e := _spawn("trzosek", Vector2(FAR_X + 40.0, y))
	var behind := Node2D.new()
	var before := Node2D.new()
	var above := Node2D.new()
	level.add_child(behind)
	level.add_child(before)
	level.add_child(above)
	behind.global_position = Vector2(FAR_X + 120.0, y)
	before.global_position = Vector2(FAR_X + 60.0, y)
	above.global_position = Vector2(FAR_X + 120.0, y - 20.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("cios wręcz: ściana między wrogiem a celem blokuje", e._wall_between(behind))
	check("cios wręcz: cel przed ścianą nie jest zasłonięty", not e._wall_between(before))
	check("cios wręcz: cel na innym poziomie nie jest sprawdzany promieniem", not e._wall_between(above))
	for n in [e, behind, before, above, strip, wall]:
		n.queue_free()

# ---------------------------------------------------------------- przywołani

func _kill_xp(summoned: bool) -> int:
	var e := _spawn("trzosek", Vector2(FAR_X + 5000.0, -2000.0))
	e.summoned = summoned
	var xp0: int = Profile.xp
	e.take_hit({"amount": 9999.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	var gained: int = Profile.xp - xp0
	e.queue_free()
	return gained

## Potomstwo bossów nie daje XP (zwykły Trzosek tak) — a boss oznacza przywołanych flagą, nie nazwą.
func _test_summoned() -> void:
	var normal := _kill_xp(false)
	var summoned := _kill_xp(true)
	check("XP: zwykły Trzosek daje XP", normal > 0, "+%d" % normal)
	check("XP: przywołany nie daje XP", summoned == 0, "+%d" % summoned)
	var boss := get_tree().get_first_node_in_group("boss")
	check("mapa ma bossa z potomstwem", boss != null and boss.has_method("_spawn_brood"))
	if boss != null and boss.has_method("_spawn_brood"):
		boss._spawn_brood("BroodTest", Vector2(FAR_X + 6000.0, -2000.0))
		var kid := level.get_node_or_null("BroodTest")
		check("potomstwo Żyły jest oznaczone jako przywołane", kid != null and bool(kid.summoned))
		if kid != null:
			kid.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- kontrakt widoku (ENEMY_PLAN.md F1)

const VIEW_KEYS := ["kind", "alive", "winding", "sp", "flash"]

## Każdy wróg, który ma model 3D (Stalker, Żyła, gniazda, zwykli), podaje `view_info()` z kompletem kluczy — view3d.gd czyta tylko to.
## Stan specjalny Wołka (`sp`) przechodzi przez `_sync` do klienta, a błysk trafienia to jawna flaga, nie kolor sprite'a.
func _test_view_contract() -> void:
	var Enemy3D := load("res://scripts/enemy3d.gd")
	var seen := 0
	var bad := []
	for g in ["enemies", "boss", "nests"]:
		for n in get_tree().get_nodes_in_group(g):
			var k = n.get("kind")
			if n.has_method("view_info"):
				var info: Dictionary = n.view_info()
				seen += 1
				for key in VIEW_KEYS:
					if not info.has(key):
						bad.append("%s bez klucza %s" % [n.name, key])
				if not Enemy3D.has_model(String(info.get("kind", ""))):
					bad.append("%s: rodzaj %s bez modelu" % [n.name, info.get("kind")])
			elif k != null and Enemy3D.has_model(String(k)):
				bad.append("%s (%s) ma model 3D, ale nie ma view_info" % [n.name, k])
	check("kontrakt widoku: wszyscy wrogowie z modelem mają komplet kluczy (%d węzłów)" % seen, seen > 0 and bad.is_empty(), ", ".join(bad))
	var kinds := {}
	for g in ["enemies", "boss", "nests"]:
		for n in get_tree().get_nodes_in_group(g):
			if n.has_method("view_info"):
				kinds[String(n.view_info()["kind"])] = true
	check("kontrakt widoku: mapa 1.3 pokrywa Stalkera, Żyłę i gniazdo", kinds.has("stalker") and kinds.has("vein") and kinds.has("nest"), str(kinds.keys()))

	var server := _spawn("wolek", Vector2(FAR_X + 7000.0, -2000.0))
	var client := _spawn("wolek", Vector2(FAR_X + 7100.0, -2000.0))
	server._sp = 2                                         # szarża
	server._flash = 0.1
	var info_s: Dictionary = server.view_info()
	check("kontrakt widoku: serwer podaje sp i błysk", int(info_s["sp"]) == 2 and bool(info_s["flash"]) and info_s["kind"] == "wolek")
	# klient dostaje to, co serwer wysyła w `_sync` (kolejność argumentów jak w `_send_state`)
	client._sync(server.global_position, server.hp, true, true, false, server._sp)
	check("kontrakt widoku: klient widzi stan specjalny Wołka z `_sync`", int(client.view_info()["sp"]) == 2, str(client.view_info()))
	client._sync(server.global_position, server.hp, true, true, false)
	check("kontrakt widoku: koniec szarży zeruje sp u klienta", int(client.view_info()["sp"]) == 0)
	server._flash = 0.0
	check("kontrakt widoku: błysk gaśnie razem z `_flash`", not bool(server.view_info()["flash"]))
	server.queue_free()
	client.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- kierunek patrzenia (ENEMY_PLAN.md F1b)

## `_facing` (cios w plecy) liczy symulacja z ruchu — bez warstwy animacji: wróg bez `_spr` i bez `_process` nadal wie, w którą stronę patrzy.
func _test_facing() -> void:
	var e := _spawn("trzosek", Vector2(FAR_X + 8000.0, -2000.0))
	e._spr.clear()                                        # żadnego zegara animacji
	e.set_process(false)                                  # i żadnego `_update_sprite`
	await get_tree().physics_frame
	e.global_position.x += 12.0
	await get_tree().physics_frame
	check("kierunek patrzenia: ruch w prawo → patrzy w prawo (bez warstwy animacji)", e._facing > 0.0, str(e._facing))
	e.global_position.x -= 12.0
	await get_tree().physics_frame
	check("kierunek patrzenia: ruch w lewo → patrzy w lewo", e._facing < 0.0, str(e._facing))
	# cios w plecy: atakujący stoi za wrogiem (cios leci w tę samą stronę, w którą wróg patrzy)
	check("cios w plecy: z tyłu (kierunek zgodny ze zwrotem)", e._is_behind(Vector2.LEFT))
	check("cios w plecy: z przodu (kierunek przeciwny do zwrotu)", not e._is_behind(Vector2.RIGHT))
	e.active = true                                       # aktywny: bez „śpi” maczeta bije tylko od tyłu
	var front: Dictionary = e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "melee", "backstab": true})
	check("maczeta: cios z przodu aktywnego wroga nie zabija", e.alive and not bool(front.get("killed", false)))
	var back: Dictionary = e.take_hit({"amount": 1.0, "dir": Vector2.LEFT, "pos": e.global_position, "shooter": int(player.player_id), "type": "melee", "backstab": true})
	check("maczeta: cios w plecy aktywnego wroga zabija", bool(back.get("killed", false)) and not e.alive)
	e.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- dane rodzajów (ENEMY_PLAN.md F2)

const STAT_KEYS := ["hp", "speed", "damage", "windup", "reach", "cooldown", "leap", "hear", "wake_near", "sight", "color", "size", "knock", "knock_mult", "head"]
## Wartości sprzed przeniesienia do `enemy_defs.gd` (SUPPLY_DROP, AMMO_DROP, HEALTH_DROP, KILL_XP, Scrap.DROP, VOICES): przeniesienie nie zmienia balansu.
const GOLDEN := {
	"trzosek": {"xp": 2, "scrap": 2, "supply": 0.0, "ammo": 0.22, "health": 0.0, "voice": ["trzosek_attack", 3, -6.0, 1.0]},
	"cma": {"xp": 3, "scrap": 4, "supply": 0.0, "ammo": 0.0, "health": 0.0, "voice": []},
	"skoczek": {"xp": 5, "scrap": 5, "supply": 0.08, "ammo": 0.25, "health": 0.0, "voice": ["trzosek_attack", 3, -5.0, 0.8]},
	"mimik": {"xp": 10, "scrap": 10, "supply": 0.4, "ammo": 0.3, "health": 0.0, "voice": ["slepiec_attack", 2, -4.0, 1.2]},
	"slepiec": {"xp": 6, "scrap": 5, "supply": 0.1, "ammo": 0.3, "health": 0.0, "voice": ["slepiec_attack", 2, -4.0, 1.0]},
	"podsluchacz": {"xp": 4, "scrap": 4, "supply": 0.15, "ammo": 0.15, "health": 0.0, "voice": []},
	"wolek": {"xp": 12, "scrap": 6, "supply": 0.35, "ammo": 0.6, "health": 0.75, "voice": ["wolek_attack", 2, -3.0, 1.0]},
	"kaplan": {"xp": 25, "scrap": 15, "supply": 0.5, "ammo": 0.5, "health": 1.0, "voice": ["slepiec_attack", 2, -3.0, 0.8]},
	"rzeznik": {"xp": 40, "scrap": 25, "supply": 0.6, "ammo": 0.7, "health": 1.0, "voice": ["wolek_attack", 2, -1.0, 0.75]},
	"zerca": {"xp": 30, "scrap": 20, "supply": 0.3, "ammo": 0.3, "health": 0.5, "voice": ["trzosek_attack", 3, -4.0, 0.7]},
}

## Jedno źródło danych rodzaju: komplet pól, wartości jak przed przeniesieniem, głosy istnieją w manifeście dźwięku, każdy rodzaj ma model 3D.
func _test_defs() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var Manifest := load("res://scripts/audio_manifest.gd")
	var Enemy3D := load("res://scripts/enemy3d.gd")
	var problems := []
	for k in Defs.DEFS:
		var d: Dictionary = Defs.DEFS[k]
		for key in STAT_KEYS:
			if not d.has(key):
				problems.append("%s bez pola %s" % [k, key])
		if not Enemy3D.SPEC.has(k):
			problems.append("%s bez wpisu SPEC (model 3D)" % k)
		if not GOLDEN.has(k):
			problems.append("%s: brak wzorca w teście" % k)
		for ev in ["attack", "alert", "death"]:
			var v: Array = Defs.voice(k, ev)
			if v.is_empty():
				continue
			for i in range(1, int(v[1]) + 1):
				if not Manifest.PATHS.has("%s_%d" % [v[0], i]):
					problems.append("%s/%s: brak dźwięku %s_%d" % [k, ev, v[0], i])
	check("dane rodzajów: komplet pól, model 3D i dźwięki głosów (%d rodzajów)" % Defs.DEFS.size(), problems.is_empty(), ", ".join(problems))
	var diffs := []
	for k in GOLDEN:
		var g: Dictionary = GOLDEN[k]
		for key in ["xp", "scrap", "supply", "ammo", "health"]:
			if not is_equal_approx(Defs.value(k, key), float(g[key])):
				diffs.append("%s.%s = %s (było %s)" % [k, key, Defs.value(k, key), g[key]])
		if g["voice"] != Defs.voice(k, "attack"):
			diffs.append("%s.voice attack = %s (było %s)" % [k, Defs.voice(k, "attack"), g["voice"]])
	check("dane rodzajów: drop, XP, złom i głos bez zmian względem starych tabel", diffs.is_empty(), ", ".join(diffs))
	check("dane rodzajów: nieznany rodzaj nic nie daje", Defs.xp("nie_ma") == 0 and Defs.value("nie_ma", "ammo") == 0.0 and Defs.voice("nie_ma", "death").is_empty())
	check("dane rodzajów: Enemy.KINDS to ta sama tabela (kodeks, HUD, testy)", Enemy.KINDS == Defs.DEFS)
	check("dane rodzajów: Podsłuchacz krzyczy tylko przy śmierci, Ćma milczy", Defs.voice("podsluchacz", "attack").is_empty() and not Defs.voice("podsluchacz", "death").is_empty() and Defs.voice("cma", "death").is_empty())

# ---------------------------------------------------------------- bossowie: wspólna podstawa (ENEMY_PLAN.md F2b)

## Żyła i Pijawka dziedziczą `boss_base.gd`: ten sam stan, HP skalowane tym samym wzorem, przywołani Trzoski tą samą drogą.
func _test_boss_base() -> void:
	var Base := load("res://scripts/boss_base.gd")
	var Leech := load("res://scripts/leech.gd")
	var boss := get_tree().get_first_node_in_group("boss")
	check("boss: Żyła dziedziczy boss_base.gd", boss != null and boss.get_script().get_base_script() == Base)
	check("boss: Pijawka dziedziczy boss_base.gd", Leech.get_base_script() == Base)
	var m: float = Difficulty.m("boss_hp")
	check("boss: HP skalowane liczbą ludzi (1 → baza, 3 → baza + 2 dodatki)",
		is_equal_approx(Base.scaled_hp(750.0, 250.0, 1), 750.0 * m) and is_equal_approx(Base.scaled_hp(750.0, 250.0, 3), 1250.0 * m) and is_equal_approx(Base.scaled_hp(750.0, 250.0, 0), 750.0 * m))
	check("boss: Pijawka 5000 + 1500 za każdego dodatkowego człowieka", is_equal_approx(Leech.hp_for(1), 5000.0 * m) and is_equal_approx(Leech.hp_for(3), 8000.0 * m))
	check("boss: śpiąca Żyła ma pełne HP z `_init` (750)", is_equal_approx(boss.hp, 750.0) and is_equal_approx(boss.max_hp, 750.0) and boss.state == Base.State.DORMANT)

	# potomstwo Żyły: lista żywych tylko na serwerze, sprzątanie po prefiksie
	boss._spawn_brood("BroodT9", Vector2(FAR_X + 9000.0, -2000.0))
	var kid := level.get_node_or_null("BroodT9")
	check("boss: potomstwo Żyły jest przywołane, wie gdzie są gracze i trafia na listę serwera", kid != null and bool(kid.summoned) and bool(kid.omniscient) and boss._brood.has(kid))
	boss._clear_brood()
	await get_tree().physics_frame
	check("boss: `_clear_brood` usuwa potomstwo i czyści listę", level.get_node_or_null("BroodT9") == null and boss._brood.is_empty())

	# Pijawka stworzona w teście (mapa 1.3 jej nie ma): ta sama droga przywoływania, zabicie i sprzątanie po prefiksie LeechSpawn
	var lc: Node = Leech.new()
	level.add_child(lc)
	lc.global_position = Vector2(FAR_X + 10000.0, -2000.0)
	check("boss: Pijawka ma pełne HP z `_init` (5000)", is_equal_approx(lc.hp, 5000.0) and lc.state == Base.State.DORMANT)
	lc._spawn_minion("LeechSpawnT9", Vector2(FAR_X + 10100.0, -2000.0))
	var mn := level.get_node_or_null("LeechSpawnT9")
	check("boss: Trzosek Pijawki jest przywołany i na liście serwera", mn != null and bool(mn.summoned) and lc._minions.has(mn))
	lc._kill_summoned(lc._minions)
	check("boss: `_kill_summoned` zabija przywołanych", mn != null and not mn.alive)
	lc._clear_minions()
	await get_tree().physics_frame
	check("boss: `_clear_minions` usuwa Trzoski Pijawki", level.get_node_or_null("LeechSpawnT9") == null and lc._minions.is_empty())
	lc.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- stan AI (ENEMY_PLAN.md F3)

var _ai_log: Array = []                       ## kolejne stany AI obserwowanego wroga (sygnał ai_changed)

func _on_ai_changed(_from: int, to: int) -> void:
	_ai_log.append(to)

func _ai_state_name(e: Node, kind_wanted: String) -> bool:
	return e.ai_name() == kind_wanted

## Jawny stan AI: odpowiada temu, co wróg faktycznie robi. Scenariusz na własnej podłodze: sen → ślad → śledztwo → szukanie → powrót → sen;
## potem gracz w zasięgu wzroku → pościg → zapowiedź ciosu; panika; martwy; klient dostaje stan z `_sync`.
func _test_ai_states() -> void:
	var y := -4500.0
	var strip := _floor(FAR_X + 11000.0, FAR_X + 11600.0, y)
	var e := _spawn("trzosek", Vector2(FAR_X + 11100.0, y))
	e.ai_changed.connect(_on_ai_changed)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("stan AI: śpiący wróg → sleep", e.ai_name() == "sleep", e.ai_name())
	e._lead_at(e.global_position + Vector2(40.0, 0.0))          # ślad tuż obok: dojdzie prosto, bez nawigacji po mapie gry
	e.active = true
	var t := 0.0
	while t < 2.0 and e.ai_name() != "investigate":
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("stan AI: aktywny ze śladem i bez celu → investigate", _ai_log.has(Enemy.Ai.INVESTIGATE), str(_ai_log))
	t = 0.0
	while t < 3.0 and not _ai_log.has(Enemy.Ai.SEARCH):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("stan AI: po dojściu na ślad → search (rozgląda się)", _ai_log.has(Enemy.Ai.SEARCH), str(_ai_log))
	t = 0.0
	while t < 9.0 and e.ai_name() != "sleep":
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("stan AI: po poszukiwaniach → return → znów sleep", _ai_log.has(Enemy.Ai.RETURN) and e.ai_name() == "sleep", str(_ai_log))

	# pościg i zapowiedź ciosu: prawdziwy gracz stawiany obok wroga na podłodze testowej
	var hp0: int = player.hp
	player.hp = 5
	player.global_position = Vector2(FAR_X + 11200.0, y - 2.0)
	player.velocity = Vector2.ZERO
	_ai_log.clear()
	e.active = true
	t = 0.0
	while t < 4.0 and not (_ai_log.has(Enemy.Ai.CHASE) and _ai_log.has(Enemy.Ai.WINDUP)):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("stan AI: gracz w zasięgu wzroku → chase, a w zasięgu ciosu → windup", _ai_log.has(Enemy.Ai.CHASE) and _ai_log.has(Enemy.Ai.WINDUP), str(_ai_log))
	player.global_position = Vector2(-4000.0, -4000.0)             # gracz wraca poza scenę (jak w testach Stalkera)
	player.hp = hp0
	e._panic = 1.0
	e._windup = 0.0
	e._target = null
	await get_tree().physics_frame
	check("stan AI: panika → panic", e.ai_name() == "panic", e.ai_name())
	var client := _spawn("trzosek", Vector2(FAR_X + 11300.0, y))
	client._sync(e.global_position, e.hp, true, true, false, 0, Enemy.Ai.CHASE)
	check("stan AI: klient odtwarza stan z `_sync` i podaje go w view_info", client.view_info()["ai"] == Enemy.Ai.CHASE and client.ai_name() == "chase")
	client._sync(e.global_position, e.hp, true, true, false)
	check("stan AI: `_sync` bez pola stanu (starszy nadawca) go nie zmienia", client.ai_name() == "chase")
	e.take_hit({"amount": 9999.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": 0, "type": "bullet"})
	check("stan AI: martwy → dead", e.ai_name() == "dead" and not e.alive)

	# rodzaje o własnej pętli: ćma, podsłuchacz, skoczek wiszący
	var moth := _spawn("cma", Vector2(FAR_X + 11400.0, y - 20.0))
	var listener := _spawn("podsluchacz", Vector2(FAR_X + 11450.0, y))
	var hanger := _spawn("skoczek", Vector2(FAR_X + 11500.0, y - 30.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("stan AI: nieobudzona ćma i wiszący skoczek → hang, podsłuchacz → listen", moth.ai_name() == "hang" and hanger.ai_name() == "hang" and listener.ai_name() == "listen",
		"%s / %s / %s" % [moth.ai_name(), hanger.ai_name(), listener.ai_name()])
	moth.active = true
	await get_tree().physics_frame
	check("stan AI: obudzona ćma → fly", moth.ai_name() == "fly")
	for n in [e, client, moth, listener, hanger, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- reakcja „zauważył” (ENEMY_PLAN.md F3.1b)

## Trzosek obudzony hałasem staje na ~0,4 s i patrzy na źródło, zanim ruszy; czas skaluje trudność, przywołani i trafieni nie stoją, reakcja ma cooldown.
func _test_alert() -> void:
	var y := -5000.0
	var strip := _floor(FAR_X + 12000.0, FAR_X + 12600.0, y)
	var Defs := load("res://scripts/enemy_defs.gd")
	check("alert: Trzosek ma pole `alert` ≈ 0,4 s, reszta rodzajów bez reakcji", is_equal_approx(Defs.value("trzosek", "alert"), 0.4) and Defs.value("wolek", "alert") == 0.0 and Defs.value("slepiec", "alert") == 0.0)
	var e := _spawn("trzosek", Vector2(FAR_X + 12100.0, y))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var x0: float = e.global_position.x
	e._lead_at(e.global_position + Vector2(-60.0, 0.0))        # źródło po lewej, blisko (bez nawigacji po mapie gry)
	e.wake()
	await get_tree().physics_frame
	check("alert: obudzony Trzosek od razu w stanie alert", e.ai_name() == "alert" and e._alert > 0.25 and bool(e.view_info()["alert"]), "%s, %.2f s" % [e.ai_name(), e._alert])
	check("alert: odwrócony ku źródłu hałasu", e._facing < 0.0, str(e._facing))
	await get_tree().create_timer(0.2).timeout
	check("alert: w trakcie reakcji stoi w miejscu", e.ai_name() == "alert" and absf(e.global_position.x - x0) < 2.0, "%s, Δx %.1f" % [e.ai_name(), e.global_position.x - x0])
	await get_tree().create_timer(0.6).timeout
	check("alert: po reakcji rusza (śledztwo ku źródłu)", e.ai_name() != "alert" and e.global_position.x < x0 - 2.0, "%s, Δx %.1f" % [e.ai_name(), e.global_position.x - x0])

	# czas reakcji: trudność skaluje jak zapowiedź ciosu, rozrzut ±15%
	var prev: int = Difficulty.level
	var times := {}
	for lvl in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		Difficulty.set_level(lvl)
		var sum := 0.0
		for i in 30:                                                   # rozrzut ±15% — uśredniamy, żeby poziomy trudności nie zachodziły na siebie losowo
			e._alert = 0.0
			e._alert_cd = 0.0
			e._begin_alert()
			sum += e._alert
		times[lvl] = sum / 30.0
	Difficulty.set_level(prev)
	check("alert: łatwy dłuższy niż normalny, normalny dłuższy niż trudny", times[Difficulty.Level.EASY] > times[Difficulty.Level.NORMAL] and times[Difficulty.Level.NORMAL] > times[Difficulty.Level.HARD], str(times))
	check("alert: normalny w granicach 0,4 s ±15%", times[Difficulty.Level.NORMAL] >= 0.34 and times[Difficulty.Level.NORMAL] <= 0.46)

	# cooldown, przywołany, inny rodzaj
	e._alert = 0.0
	e._alert_cd = 3.0
	e._begin_alert()
	check("alert: w czasie cooldownu nie powtarza reakcji", e._alert == 0.0)
	e._alert_cd = 0.0
	e.summoned = true
	e._begin_alert()
	check("alert: przywołany przez bossa nie staje", e._alert == 0.0)
	var w := _spawn("wolek", Vector2(FAR_X + 12300.0, y))
	w._begin_alert()
	check("alert: rodzaj bez pola `alert` (Wołek) nie staje", w._alert == 0.0)

	# trafienie przerywa reakcję i budzenie od trafienia jej nie daje
	e.summoned = false
	e._alert = 0.0
	e._alert_cd = 0.0
	e._begin_alert()
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	check("alert: trafienie przerywa reakcję", e._alert == 0.0 and e._alert_cd > 0.0)
	var sleeper := _spawn("trzosek", Vector2(FAR_X + 12450.0, y))
	await get_tree().physics_frame
	sleeper.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": sleeper.global_position, "shooter": int(player.player_id), "type": "bullet"})
	check("alert: śpiący trafiony budzi się od razu do walki, bez reakcji", sleeper.active and sleeper._alert == 0.0, "aktywny=%s alert=%.2f" % [sleeper.active, sleeper._alert])

	# klient: stan i kierunek odwrotu z `_sync`
	var client := _spawn("trzosek", Vector2(FAR_X + 12550.0, y))
	client._sync(client.global_position, client.hp, true, true, false, 0, Enemy.Ai.ALERT, -1.0)
	check("alert: klient odtwarza stan i kierunek z `_sync`", bool(client.view_info()["alert"]) and client._net_face == -1.0)
	for n in [e, w, sleeper, client, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- wybór celu (ENEMY_PLAN.md F3.5)

## Histereza celu: wróg trzyma dotychczasowy cel, dopóki inny gracz nie jest wyraźnie bliżej (< 70% odległości); utrata wzroku zmienia cel od razu.
## Dwóch graczy: człowiek i bot z sesji testowej, zamrożeni na własnej podłodze; wróg zamrożony, `_perceive` wołany ręcznie.
func _test_target_hysteresis() -> void:
	check("cel: reguła przełączenia — 69% punktów przełącza, 71% nie", Enemy._prefer_new_target(100.0, 69.0) and not Enemy._prefer_new_target(100.0, 71.0))
	var bot: Node = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			bot = p
	if bot == null:
		check("cel: sesja testowa ma drugiego gracza (bota)", false)
		return
	var y := -5500.0
	var strip := _floor(FAR_X + 13000.0, FAR_X + 13800.0, y)
	var x0 := FAR_X + 13400.0
	var e := _spawn("trzosek", Vector2(x0, y))
	e.set_physics_process(false)
	var frozen := []
	for p in [player, bot]:
		p.set_physics_process(false)
		p.velocity = Vector2.ZERO
		frozen.append(p)
	# punkty celu = odległość × waga; bot waży 1,3 (człowiek 1,0); odizolowany (nikt w 150 px) ×0,9 obaj
	player.global_position = Vector2(x0 + 100.0, y)
	bot.global_position = Vector2(x0 - 95.0, y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: człowiek 100 px wygrywa z botem 95 px (bot nie jest wabikiem)", e._target == player, str(e._target))
	bot.global_position = Vector2(x0 - 65.0, y)                       # bot 65 px: punkty 76 vs człowiek 90 → 84% — za mało, żeby przełączyć
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: bliższy bot, ale niewyraźnie lepszy, nie przejmuje celu (histereza)", e._target == player, str(e._target))
	bot.global_position = Vector2(x0 - 40.0, y)                       # bot 40 px: 52 vs 100 (nie odizolowani, bo 140 px od siebie) → 52% — wyraźnie lepszy
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: wyraźnie lepszy cel (bot 40 px) przejmuje cel", e._target == bot, str(e._target))
	player.global_position = Vector2(x0 + 30.0, y)                    # człowiek 30 px: 30 vs bot 52 → 58%
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: człowiek tuż obok (58% punktów bota) przejmuje cel z powrotem", e._target == player, str(e._target))
	bot.global_position = Vector2(x0 - 20.0, y)                       # bot 20 px: 26 vs człowiek 30 → 87% — brak migania
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: powrót nie następuje przy 87% punktów (brak migania)", e._target == player, str(e._target))
	player.global_position = Vector2(x0 + 600.0, y)                   # dotychczasowy cel poza zasięgiem wzroku — zmiana od razu, bez histerezy
	e._perceive_t = 0.0
	e._perceive(0.2)
	check("cel: dotychczasowy cel poza wzrokiem → przejmuje widoczny", e._target == bot, str(e._target))
	for p in frozen:
		p.set_physics_process(true)
	player.global_position = Vector2(-4000.0, -4000.0)
	bot.global_position = Vector2(-4100.0, -4000.0)
	e.queue_free()
	strip.queue_free()
	await get_tree().physics_frame

## Wagi celu: człowiek bije bota, latarka i ogień przyciągają (latarka nie ślepca), ranny i odizolowany są łatwiejszym łupem; minimalna zapowiedź ciosu.
func _test_target_weights() -> void:
	var bot: Node = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			bot = p
	if bot == null:
		check("waga celu: sesja testowa ma drugiego gracza (bota)", false)
		return
	var e := _spawn("trzosek", Vector2(FAR_X + 19000.0, -9000.0))
	var s := _spawn("slepiec", Vector2(FAR_X + 19100.0, -9000.0))
	e.set_physics_process(false)
	s.set_physics_process(false)
	player.global_position = Vector2(FAR_X + 19500.0, -9000.0)
	bot.global_position = Vector2(FAR_X + 19000.0, -8000.0)             # daleko od człowieka: obaj odizolowani
	var wounded0: int = player.hp
	player.hp = 3
	player.flashlight = false
	player.w_firing = false
	var base: float = e._target_weight(player)
	check("waga celu: odizolowany człowiek ×0,9, bot ×1,3 × 0,9", is_equal_approx(base, Enemy.TARGET_ISOLATED_W) and is_equal_approx(e._target_weight(bot), Enemy.TARGET_BOT_W * Enemy.TARGET_ISOLATED_W),
		"%.3f / %.3f" % [base, e._target_weight(bot)])
	player.flashlight = true
	check("waga celu: latarka obniża wagę (wróg ją woli), ślepiec jej nie widzi", is_equal_approx(e._target_weight(player), base * Enemy.TARGET_LIGHT_W) and is_equal_approx(s._target_weight(player), base))
	player.flashlight = false
	player.w_firing = true
	check("waga celu: strzelający jest chętniej wybierany", is_equal_approx(e._target_weight(player), base * Enemy.TARGET_FIRING_W))
	player.w_firing = false
	player.hp = 1
	check("waga celu: ranny (1 serce) jest chętniej wybierany", is_equal_approx(e._target_weight(player), base * Enemy.TARGET_WOUNDED_W))
	player.hp = 3
	bot.global_position = Vector2(FAR_X + 19520.0, -9000.0)           # bot tuż obok człowieka: nikt nie jest odizolowany
	check("waga celu: razem z drużyną (nie odizolowany) bez bonusu", is_equal_approx(e._target_weight(player), 1.0) and is_equal_approx(e._target_weight(bot), Enemy.TARGET_BOT_W))
	player.hp = wounded0
	player.global_position = Vector2(-4000.0, -4000.0)
	bot.global_position = Vector2(-4100.0, -4000.0)

	# minimalna zapowiedź ciosu po trudności
	check("zapowiedź: Trzosek 0,28 s — normalny bez zmian, łatwy dłuższy, trudny nie krócej niż MIN_WINDUP",
		is_equal_approx(Enemy.windup_time(0.28, 1.0), 0.28) and Enemy.windup_time(0.28, 1.3) > 0.28 and is_equal_approx(Enemy.windup_time(0.28, 0.8), Enemy.MIN_WINDUP),
		"%.3f / %.3f / %.3f" % [Enemy.windup_time(0.28, 1.0), Enemy.windup_time(0.28, 1.3), Enemy.windup_time(0.28, 0.8)])
	check("zapowiedź: dłuższa zapowiedź (Wołek 0,6 s) nie jest skracana do minimum", is_equal_approx(Enemy.windup_time(0.6, 0.8), 0.48))
	e.queue_free()
	s.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------- lokalizacja hałasu z błędem (ENEMY_PLAN.md F3.2)

## Wróg słyszy hałas z błędem poziomym: z bliska prawie dokładnie, na granicy zasięgu do `hear_error` px (cichy 1,5× bardziej); ślepiec dokładniej, wołek gorzej.
func _test_hear_error() -> void:
	var off := Enemy.heard_offset
	check("błąd słuchu: tuż przy źródle zero", off.call(64.0, 0.0, 200.0, 3.0, 1.0) == 0.0)
	check("błąd słuchu: na granicy zasięgu głośny = pełny błąd, w obie strony", is_equal_approx(off.call(64.0, 200.0, 200.0, 3.0, 1.0), 64.0) and is_equal_approx(off.call(64.0, 200.0, 200.0, 3.0, -1.0), -64.0))
	check("błąd słuchu: pół zasięgu = pół błędu", is_equal_approx(off.call(64.0, 100.0, 200.0, 3.0, 1.0), 32.0))
	check("błąd słuchu: cichy (0,5) myli się 1,5× bardziej niż głośny", is_equal_approx(off.call(64.0, 200.0, 200.0, 0.5, 1.0), 96.0))
	check("błąd słuchu: za zasięgiem nie rośnie ponad pełny błąd", is_equal_approx(off.call(64.0, 900.0, 200.0, 3.0, 1.0), 64.0))
	var Defs := load("res://scripts/enemy_defs.gd")
	check("błąd słuchu: ślepiec dokładniejszy, wołek mniej dokładny niż domyślny",
		Defs.value("slepiec", "hear_error") < Enemy.HEAR_ERROR and Defs.value("wolek", "hear_error") > Enemy.HEAR_ERROR and Defs.value("trzosek", "hear_error") == 0.0)

	var e := _spawn("trzosek", Vector2(FAR_X + 14000.0, -6000.0))
	e.set_physics_process(false)
	var src := Vector2(FAR_X + 14100.0, -6000.0)
	var lo := 0.0
	var hi := 0.0
	var same_y := true
	for i in 300:
		var p: Vector2 = e._heard_pos(src, 150.0, 200.0, 3.0)
		lo = minf(lo, p.x - src.x)
		hi = maxf(hi, p.x - src.x)
		same_y = same_y and p.y == src.y
	var bound := Enemy.HEAR_ERROR * 0.75
	check("błąd słuchu: 300 losowań w granicach ±48 px, obie strony, bez błędu w pionie", lo >= -bound - 0.01 and hi <= bound + 0.01 and lo < -bound * 0.5 and hi > bound * 0.5 and same_y, "%.1f … %.1f" % [lo, hi])
	e.queue_free()

	# wiring na prawdziwej mapie: wróg śpi w punkcie grafu nawigacji, hałas w drugim punkcie obok — ślad jest w pobliżu źródła, nie dokładnie w nim
	var nav = level.get("nav")
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	var found := false
	if nav != null:
		for ida in nav.get_point_ids():
			var a: Vector2 = nav.get_point_position(ida)
			for idb in nav.get_point_ids():
				var b: Vector2 = nav.get_point_position(idb)
				if absf(b.y - a.y) < 1.0 and absf(b.x - a.x) > 100.0 and absf(b.x - a.x) < 140.0:
					pa = a
					pb = b
					found = true
					break
			if found:
				break
	check("błąd słuchu: mapa 1.3 ma dwa sąsiednie punkty nawigacji do testu", found)
	if found:
		var sleeper := _spawn("trzosek", level.to_global(pa))
		sleeper.set_physics_process(false)
		NoiseMgr.last_noise_pos = level.to_global(pb)
		NoiseMgr.last_noise_amount = 3.0
		NoiseMgr.noise_serial += 1
		sleeper._check_wake()
		var dx: float = sleeper._last_known.x - NoiseMgr.last_noise_pos.x
		check("błąd słuchu: śpiący budzi się od hałasu, ślad w granicach błędu i na tej samej wysokości",
			sleeper.active and absf(dx) <= Enemy.HEAR_ERROR + 0.5 and is_equal_approx(sleeper._last_known.y, NoiseMgr.last_noise_pos.y),
			"aktywny=%s, Δx=%.1f, y %.1f vs %.1f" % [sleeper.active, dx, sleeper._last_known.y, NoiseMgr.last_noise_pos.y])
		sleeper.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- wiedza grupy (ENEMY_PLAN.md F3.4a)

func _idle_ally(e: Node) -> void:
	e.set_physics_process(false)
	e.active = true
	e._ai = Enemy.Ai.RETURN                   # aktywny, nic niewidzący, wraca do domu
	e._has_lead = false
	e._target = null
	e._alert = 0.0
	e._alert_cd = 0.0

## Trzosek, który zauważył gracza, daje znać kolegom z watahy w zasięgu: aktywni i nic niewidzący dostają ślad i reakcję „zauważył"; śpiący, inny rodzaj,
## inne piętro, za daleko, mający już cel i przywołani — nie.
func _test_pack_shout() -> void:
	var y := -7000.0
	var strip := _floor(FAR_X + 15000.0, FAR_X + 15900.0, y)
	var x0 := FAR_X + 15400.0
	var a := _spawn("trzosek", Vector2(x0, y))
	var b := _spawn("trzosek", Vector2(x0 - 150.0, y))
	var c := _spawn("trzosek", Vector2(x0 - 100.0, y))                  # śpi
	var d := _spawn("slepiec", Vector2(x0 - 120.0, y))                  # inny rodzaj
	var up := _spawn("trzosek", Vector2(x0 - 100.0, y - 100.0))         # inne piętro
	var far := _spawn("trzosek", Vector2(x0 + 400.0, y))                # za daleko
	var busy := _spawn("trzosek", Vector2(x0 - 60.0, y))                # ma już cel
	var minion := _spawn("trzosek", Vector2(x0 - 80.0, y))              # przywołany
	for e in [a, b, d, up, far, busy, minion]:
		_idle_ally(e)
	c.set_physics_process(false)
	busy._target = player
	minion.summoned = true
	var spot := Vector2(x0 + 200.0, y)
	a._beh.shout_sighting(spot)
	check("wataha: kolega w zasięgu dostaje ślad w miejscu gracza i reakcję „zauważył”", b._has_lead and b._last_known.is_equal_approx(spot) and b.ai_name() == "alert", "lead=%s ai=%s" % [b._has_lead, b.ai_name()])
	check("wataha: śpiący kolega nie dostaje śladu (budzi go wake())", not c._has_lead and not c.active)
	check("wataha: inny rodzaj, inne piętro i za daleko nie słyszą", not d._has_lead and not up._has_lead and not far._has_lead)
	check("wataha: kolega, który ma już cel, i przywołany bossa nie zmieniają śladu", not busy._has_lead and not minion._has_lead)
	check("wataha: krzykacz ma cooldown", a._beh.share_cd > 2.5, str(a._beh.share_cd))
	b._has_lead = false
	b._ai = Enemy.Ai.RETURN
	b._alert = 0.0
	a._beh.shout_sighting(spot)
	check("wataha: w czasie cooldownu drugi krzyk nic nie robi", not b._has_lead)

	# ścieżka percepcji: krzykacz widzi gracza po raz pierwszy → kolega poza zasięgiem wzroku (400 px od gracza) dostaje ślad
	a._beh.share_cd = 0.0
	a._ai = Enemy.Ai.RETURN
	a._target = null
	b._has_lead = false
	b._ai = Enemy.Ai.RETURN
	b._alert = 0.0
	b._alert_cd = 0.0
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(x0 + 150.0, y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	a._perceive_t = 0.0
	a._perceive(0.2)
	check("wataha: pierwszy kontakt wzrokowy w `_perceive` daje znać koledze, który gracza nie widzi", a._target == player and b._has_lead and absf(b._last_known.x - player.global_position.x) < 2.0,
		"cel=%s lead=%s" % [a._target, b._has_lead])
	player.set_physics_process(true)
	player.global_position = Vector2(-4000.0, -4000.0)
	for n in [a, b, c, d, up, far, busy, minion, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- uczciwe zapowiedzi (ENEMY_PLAN.md F3.6)

func _hit_info(e: Node, stun: float) -> Dictionary:
	return {"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet", "stun": stun}

## Mocne ogłuszenie (≥ 0,4 s) przerywa zwykły cios w trakcie zapowiedzi i daje wrogowi przerwę; słabe trafienie, zapowiedzi specjalne Wołka,
## krzyk Podsłuchacza i przemiana Mimika (bez celu ciosu) nie są przerywane.
func _test_windup_interrupt() -> void:
	var y := -7500.0
	var strip := _floor(FAR_X + 16000.0, FAR_X + 16600.0, y)
	var e := _spawn("trzosek", Vector2(FAR_X + 16100.0, y))
	e.set_physics_process(false)
	e._windup = 0.3
	e._windup_target = player
	e.winding = true
	e.take_hit(_hit_info(e, 0.1))
	check("zapowiedź: słabe trafienie jej nie przerywa", e._windup > 0.0 and e.winding and e._windup_target == player)
	e.take_hit(_hit_info(e, 0.5))
	check("zapowiedź: ogłuszenie 0,5 s przerywa cios (bez zapowiedzi, bez celu)", e._windup == 0.0 and not e.winding and e._windup_target == null)
	check("zapowiedź: po przerwaniu przerwa przed kolejnym ciosem", e._cd >= 0.5, str(e._cd))
	var w := _spawn("wolek", Vector2(FAR_X + 16200.0, y))
	w.set_physics_process(false)
	w._windup = 0.3
	w._windup_target = player
	w.winding = true
	w._sp = 1                                              # zapowiedź szarży
	w.take_hit(_hit_info(w, 0.8))
	check("zapowiedź: szarża Wołka (stan specjalny) nie jest przerywana", w._windup > 0.0 and w.winding)
	var l := _spawn("podsluchacz", Vector2(FAR_X + 16300.0, y))
	l.set_physics_process(false)
	l._windup = 0.5
	l._windup_target = player
	l.winding = true
	l.take_hit(_hit_info(l, 0.8))
	check("zapowiedź: krzyk Podsłuchacza nie jest przerywany ogłuszeniem", l._windup > 0.0)
	var m := _spawn("mimik", Vector2(FAR_X + 16400.0, y))
	m.set_physics_process(false)
	m._windup = 0.35
	m._windup_target = null
	m.winding = true
	m._interrupt_windup()
	check("zapowiedź: przemiana Mimika (bez celu ciosu) nie jest przerywana", m._windup > 0.0 and m.winding)
	for n in [e, w, l, m, strip]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Dyrektor: grupy wędrowców (ENEMY_PLAN.md F3.7)

## Tabela zestawów, limit grup, sprzątanie uśpionych poza polem widzenia. Dyrektor stoi (`set_process(false)`), metody woła test.
func _test_director() -> void:
	var D := Director
	var table: Array = D.GROUPS
	var legacy := [[60.0, ["trzosek", "trzosek"]], [25.0, ["trzosek", "trzosek", "trzosek"]], [15.0, ["slepiec"]]]        # stary format wpisów (bez okien) działa jak dotąd
	check("dyrektor: tabela bez okien jak dotąd — 0,59 → 2 Trzoski, 0,61 → 3, 0,86 → Ślepiec",
		D.pick_group(legacy, 0.0) == ["trzosek", "trzosek"] and D.pick_group(legacy, 0.59) == ["trzosek", "trzosek"] and D.pick_group(legacy, 0.61).size() == 3
		and D.pick_group(legacy, 0.84).size() == 3 and D.pick_group(legacy, 0.86) == ["slepiec"] and D.pick_group(legacy, 0.999) == ["slepiec"])
	check("dyrektor: wagi względne (nie muszą dawać 100)", D.pick_group([[1.0, ["a"]], [3.0, ["b"]]], 0.1) == ["a"] and D.pick_group([[1.0, ["a"]], [3.0, ["b"]]], 0.3) == ["b"])
	var copy: Array = D.pick_group(table, 0.0)
	copy.append("x")
	check("dyrektor: zwrócony zestaw to kopia (tabela się nie psuje)", D.pick_group(table, 0.0).size() == 2)
	check("dyrektor: mapa bez własnej tabeli dostaje domyślną, mapa z własną — swoją", D.groups_for("nieznana") == D.GROUPS and D.groups_for("z1_m3") == D.GROUPS_BY_MAP["z1_m3"])
	var Defs := load("res://scripts/enemy_defs.gd")
	var bad := []
	var tables: Array = [D.GROUPS]
	for m in D.GROUPS_BY_MAP:
		tables.append(D.GROUPS_BY_MAP[m])
	for t in tables:
		for g in t:
			for k in g[1]:
				if not Defs.has(String(k)):
					bad.append(String(k))
	check("dyrektor: każdy rodzaj w tabelach zestawów istnieje w enemy_defs.gd", bad.is_empty(), str(bad))

	# limit grup: liczą się grupy z żywym członkiem na liście
	var r0 := D._roamers.duplicate()
	var g0 := D._groups.duplicate()
	D._roamers.assign(["R1", "R2", "R3"])
	D._groups.assign([["R1", "R2"], ["R3"]])
	check("dyrektor: dwie grupy z żywymi członkami → live_groups = 2 (= MAX_GROUPS, nowej nie wolno)", D.live_groups() == 2 and D.live_groups() >= D.MAX_GROUPS)
	D._roamers.erase("R3")
	check("dyrektor: grupa bez żywych znika z liczenia → 1 (nowa wolno)", D.live_groups() == 1 and D._groups.size() == 1)
	D._roamers.clear()
	check("dyrektor: bez wędrowców → 0 grup", D.live_groups() == 0 and D._groups.is_empty())
	D._roamers.assign(r0)
	D._groups.assign(g0)

	# sprzątanie uśpionych: po ROAMER_IDLE_DESPAWN s poza polem widzenia znikają; blisko, w linii wzroku i aktywni zostają
	var y := -8000.0
	var strip := _floor(FAR_X + 17000.0, FAR_X + 18200.0, y)
	var wall := _block(Vector2(FAR_X + 17500.0, y - 30.0), Vector2(4.0, 60.0))
	var left := FAR_X + 17100.0
	var hidden := _spawn("trzosek", Vector2(left, y))            # za ścianą, 500 px od gracza
	var close := _spawn("trzosek", Vector2(FAR_X + 17900.0, y))  # 100 px od gracza
	var seen := _spawn("trzosek", Vector2(FAR_X + 18150.0, y))   # 350 px? bliżej niż SPAWN_DIST_MIN — blisko
	var awake := _spawn("trzosek", Vector2(left + 20.0, y))      # aktywny — nie znika
	for e in [hidden, close, seen, awake]:
		e.set_physics_process(false)
		e.add_to_group("roamers")
		e.active = false
	awake.active = true
	hidden.name = "RoamerT1"
	close.name = "RoamerT2"
	seen.name = "RoamerT3"
	awake.name = "RoamerT4"
	D._roamers.assign(["RoamerT1", "RoamerT2", "RoamerT3", "RoamerT4"])
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(FAR_X + 17800.0, y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	D._cleanup([player], 20.0)
	check("dyrektor: przed ROAMER_IDLE_DESPAWN nikt nie znika", D._roamers.size() == 4, str(D._roamers))
	D._cleanup([player], 30.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("dyrektor: uśpiony za ścianą (> 380 px, bez linii wzroku) po 50 s znika", level.get_node_or_null("RoamerT1") == null and not D._roamers.has("RoamerT1"))
	check("dyrektor: uśpiony blisko gracza, uśpiony w zasięgu i aktywny zostają",
		level.get_node_or_null("RoamerT2") != null and level.get_node_or_null("RoamerT3") != null and level.get_node_or_null("RoamerT4") != null and D._roamers.size() == 3, str(D._roamers))
	D._roamers.assign(r0)
	D._groups.assign(g0)
	D._idle.clear()
	player.set_physics_process(true)
	player.global_position = Vector2(-4000.0, -4000.0)
	for n in [close, seen, awake, strip, wall]:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Dyrektor: kleszcze (ENEMY_PLAN.md F3.4)

## Nowa grupa wędrowców wychodzi z przeciwnej strony niż poprzednia (drużyna atakowana z dwóch stron bez przenikania wrogów przez gracza);
## gdy po tamtej stronie nie ma miejsca, po PINCER_TRIES próbach wolno z dowolnej.
func _test_pincer() -> void:
	var D := Director
	check("kleszcze: bez poprzedniej grupy (avoid 0) wolno z każdej strony", D.pincer_side_ok(0.0, 300.0, 0) and D.pincer_side_ok(0.0, -300.0, 0))
	check("kleszcze: poprzednia grupa z prawej (+1) → wolno tylko z lewej", D.pincer_side_ok(1.0, -300.0, 0) and not D.pincer_side_ok(1.0, 300.0, 0))
	check("kleszcze: poprzednia grupa z lewej (−1) → wolno tylko z prawej", D.pincer_side_ok(-1.0, 300.0, 0) and not D.pincer_side_ok(-1.0, -300.0, 0))
	check("kleszcze: po PINCER_TRIES próbach wolno z tej samej strony (brak miejsca po drugiej)", D.pincer_side_ok(1.0, 300.0, D.PINCER_TRIES) and not D.pincer_side_ok(1.0, 300.0, D.PINCER_TRIES - 1))

	var y := -9500.0
	var near := Vector2(FAR_X + 20000.0, y)
	var r0 := D._roamers.duplicate()
	var a := _spawn("trzosek", near + Vector2(400.0, 0.0))             # poprzednia grupa: 400 px na prawo
	var b := _spawn("trzosek", near + Vector2(500.0, 0.0))
	var far := _spawn("trzosek", near + Vector2(-2000.0, 0.0))         # daleko po lewej: poza PINCER_R, nie liczy się
	var dead := _spawn("trzosek", near + Vector2(-300.0, 0.0))         # martwy: nie liczy się
	for e in [a, b, far, dead]:
		e.set_physics_process(false)
	a.name = "RoamerP1"
	b.name = "RoamerP2"
	far.name = "RoamerP3"
	dead.name = "RoamerP4"
	dead.alive = false
	D._roamers.assign(["RoamerP1", "RoamerP2", "RoamerP3", "RoamerP4"])
	check("kleszcze: żywi wędrowcy z prawej w PINCER_R → strona +1 (daleki i martwy się nie liczą)", D._roamer_side(level, near) == 1.0, str(D._roamer_side(level, near)))
	a.global_position = near + Vector2(10.0, 0.0)                      # tuż pod graczem: |średnia| < PINCER_MIN_DX
	b.global_position = near + Vector2(-20.0, 0.0)
	check("kleszcze: wędrowcy tuż pod graczem nie wyznaczają strony", D._roamer_side(level, near) == 0.0)
	D._roamers.clear()
	check("kleszcze: bez wędrowców strona 0", D._roamer_side(level, near) == 0.0)
	D._roamers.assign(r0)
	for n in [a, b, far, dead]:
		n.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Wołek: rzut w górę i w dół; Ślepiec: przeszukiwanie i rzut na dźwięk

const PROP_SCRIPT := preload("res://scripts/prop.gd")

func _crate_at(pos: Vector2) -> RigidBody2D:
	var pr: RigidBody2D = PROP_SCRIPT.new()
	pr.kind = "crate"
	level.add_child(pr)
	pr.global_position = pos
	pr.freeze = true                                       # skrzynia stoi w miejscu (bez fizyki), test sprawdza tylko decyzję Wołka
	return pr

## Wołek z skrzynią przy sobie zaczyna rzut także wobec gracza na półce nad nim i w dole pod nim (do THROW_DY_MAX), a poza zakresem albo za ścianą nie.
func _test_wolek_throw_vertical() -> void:
	var y := -10000.0
	var strip := _floor(FAR_X + 21000.0, FAR_X + 21208.0, y)                   # półka Wołka kończy się 8 px przed nim (krawędź), żeby rzut w dół nie przechodził przez podłogę
	var strip2 := _floor(FAR_X + 21260.0, FAR_X + 21500.0, y + 100.0)         # niższy poziom po drugiej stronie krawędzi
	var x0 := FAR_X + 21200.0
	var w := _spawn("wolek", Vector2(x0, y))
	w.set_physics_process(false)
	var crate := _crate_at(Vector2(x0 + 10.0, y - 7.0))
	var dummy := Node2D.new()                              # cel: wystarczy pozycja (`_bruiser_tick` czyta tylko `global_position`)
	level.add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	w._beh.throw_cd = 0.0
	w._beh.charge_cd = 99.0                                    # bez szarży — sprawdzamy sam rzut
	dummy.global_position = Vector2(x0 + 120.0, y - 100.0)  # półka 100 px nad nim, 120 px w bok
	check("Wołek: gracz na półce 100 px nad nim → zaczyna rzut skrzynią", w._beh.tick_phase(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._beh.throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 120.0, y + 100.0)  # 100 px niżej (po drugiej stronie podłogi pomiarowej — tylko pozycja, bez fizyki)
	check("Wołek: gracz 100 px niżej (na niższym poziomie za krawędzią) → też rzut", w._beh.tick_phase(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._beh.throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 20.0, y - 90.0)    # prawie nad nim (ax < 60) na półce
	check("Wołek: gracz prawie nad nim (ax < 60) na półce → rzut", w._beh.tick_phase(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._beh.throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 120.0, y - 300.0)  # za wysoko (> THROW_DY_MAX)
	check("Wołek: za wysoko (300 px) → bez rzutu", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	w._beh.throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 400.0, y - 60.0)   # za daleko w poziomie
	check("Wołek: za daleko w poziomie → bez rzutu", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	w._beh.throw_cd = 5.0
	dummy.global_position = Vector2(x0 + 120.0, y - 100.0)
	check("Wołek: w czasie cooldownu rzutu nie zaczyna", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	w._beh.throw_cd = 0.0
	var wall := _block(Vector2(x0 + 60.0, y - 80.0), Vector2(6.0, 120.0))     # ściana na linii rzutu
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("Wołek: ściana na linii rzutu → bez rzutu", not w._beh.tick_phase(0.016, dummy) and w._sp == 0)
	for n in [w, crate, dummy, wall, strip, strip2]:
		n.queue_free()
	await get_tree().physics_frame

## Ślepiec: po dojściu na ślad przeszukuje okolicę zamiast stać, a głośny dźwięk blisko uruchamia zapowiedź i rzut w jego stronę.
func _test_slepiec_mechanics() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["slepiec"]["lunge"]
	check("Ślepiec: rzut na dźwięk — głośny i blisko tak, cichy albo za daleko (> 300 px) nie, rodzaj bez pola `lunge` nie",
		Blind.lunge_triggers(cfg, 3.0, 100.0) and not Blind.lunge_triggers(cfg, 0.6, 100.0) and Blind.lunge_triggers(cfg, 3.0, 250.0) and not Blind.lunge_triggers(cfg, 3.0, 400.0) and not Blind.lunge_triggers({}, 9.0, 10.0))
	var y := -10500.0
	var strip := _floor(FAR_X + 22000.0, FAR_X + 23000.0, y)
	var x0 := FAR_X + 22500.0
	var e := _spawn("slepiec", Vector2(x0, y))
	await get_tree().physics_frame
	await get_tree().physics_frame

	# przeszukiwanie: aktywny ze śladem 5 px obok chodzi po okolicy (± sweep), zamiast stać, i po `search` s rezygnuje
	e.active = true
	e._lead_at(e.global_position + Vector2(5.0, 0.0))
	var lo := x0
	var hi := x0
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		lo = minf(lo, e.global_position.x)
		hi = maxf(hi, e.global_position.x)
	var amp: float = Defs.DEFS["slepiec"]["sweep"]
	check("Ślepiec: przeszukuje okolicę śladu (w 3 s przeszedł ponad 40 px, nie dalej niż ±sweep od śladu)", hi - lo > 40.0 and lo >= x0 + 5.0 - amp - 12.0 and hi <= x0 + 5.0 + amp + 12.0, "%.0f … %.0f (ślad %.0f, ±%.0f)" % [lo, hi, x0 + 5.0, amp])
	check("Ślepiec: w trakcie szukania stan search", e.ai_name() == "search", e.ai_name())
	t = 0.0
	while t < 5.0 and e._has_lead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("Ślepiec: po czasie szukania (6 s, dłuższym niż domyślne 3,5 s) rezygnuje ze śladu", not e._has_lead, "has_lead=%s po łącznie ≈ %.1f s" % [e._has_lead, 3.0 + t])

	# rzut na głośny dźwięk 100 px na prawo (bez nawigacji po mapie: wołamy wprost `_maybe_lunge`)
	e._beh.lunge_cd = 0.0
	e._target = null
	e.global_position.x = x0
	var src := Vector2(x0 + 100.0, y)
	e._lead_at(src)
	e._beh.maybe_lunge(src, 100.0, 3.0)
	check("Ślepiec: głośny dźwięk 100 px obok → zapowiedź (alert) i oczy w widoku", e.ai_name() == "alert" and bool(e.view_info()["alert"]) and e._beh.lunge_wind > 0.0, "%s / %.2f" % [e.ai_name(), e._beh.lunge_wind])
	var x_wind: float = e.global_position.x
	await get_tree().create_timer(0.15).timeout
	check("Ślepiec: w zapowiedzi stoi w miejscu", absf(e.global_position.x - x_wind) < 2.0 and e.ai_name() == "alert")
	t = 0.0
	while t < 1.2 and e._beh.lunge_t <= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var x_start: float = e.global_position.x
	check("Ślepiec: po zapowiedzi pędzi (stan lunge)", e.ai_name() == "lunge" and e._beh.lunge_t > 0.0, e.ai_name())
	await get_tree().create_timer(0.3).timeout
	var v: float = (e.global_position.x - x_start) / 0.3
	check("Ślepiec: w rzucie jest szybszy niż w chodzie (> 1,5 × 70 px/s)", v > 105.0, "%.0f px/s" % v)
	t = 0.0
	while t < 2.0 and e._beh.lunge_t > 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("Ślepiec: rzut kończy się za źródłem dźwięku i wraca do normalnego stanu", e._beh.lunge_t <= 0.0 and e.global_position.x >= x0 + 90.0 and e.ai_name() != "lunge", "x=%.0f, %s" % [e.global_position.x, e.ai_name()])
	e._beh.maybe_lunge(src, 100.0, 3.0)
	check("Ślepiec: cooldown rzutu (6 s) blokuje kolejny", e._beh.lunge_wind == 0.0 and e._beh.lunge_cd > 4.0, str(e._beh.lunge_cd))
	e._beh.lunge_cd = 0.0
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	e._beh.maybe_lunge(src, 100.0, 3.0)
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	check("Ślepiec: trafiony w zapowiedzi rzutu nie stoi (zapowiedź przerwana)", e._beh.lunge_wind == 0.0)
	for n in [e, strip]:
		n.queue_free()
	await get_tree().physics_frame

## Rzut Ślepca na dźwięk przez prawdziwe `_listen()` (nie tylko `_maybe_lunge`) na realnych punktach nawigacji mapy 1.3: rozgrzana M-83 (≥ 1,0) uruchamia zapowiedź,
## zimna lufa (0,6) i cichy krok tylko prowadzą do źródła. (Playtest pokazał, że próg 2,0 nie reagował na domyślną M-83 — stąd test na kanale słuchu.)
func _test_slepiec_listen() -> void:
	var nav = level.get("nav")
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	var found := false
	if nav != null:
		for ida in nav.get_point_ids():
			var a: Vector2 = nav.get_point_position(ida)
			for idb in nav.get_point_ids():
				var b: Vector2 = nav.get_point_position(idb)
				if absf(b.y - a.y) < 1.0 and absf(b.x - a.x) > 80.0 and absf(b.x - a.x) < 110.0:
					pa = a
					pb = b
					found = true
					break
			if found:
				break
	check("Ślepiec/słuch: mapa 1.3 ma dwa sąsiednie punkty nawigacji do testu", found)
	if not found:
		return
	var thresholds := [[0.6, false], [1.2, true], [3.5, true]]       # zimna M-83, rozgrzana M-83, strzelba
	for th in thresholds:
		var e := _spawn("slepiec", level.to_global(pa))
		e.set_physics_process(false)
		e.active = true
		NoiseMgr.last_noise_pos = level.to_global(pb)
		NoiseMgr.last_noise_amount = float(th[0])
		NoiseMgr.noise_serial += 1
		e._listen()
		check("Ślepiec/słuch: strzał o głośności %.1f %s rzut (przez `_listen`)" % [th[0], "uruchamia" if th[1] else "nie uruchamia"],
			(e._beh.lunge_wind > 0.0) == bool(th[1]) and e._has_lead, "wind=%.2f lead=%s ai=%s" % [e._beh.lunge_wind, e._has_lead, e.ai_name()])
		e.queue_free()
	await get_tree().physics_frame

# ---------------------------------------------------------------- Ślepiec uwięziony za krawędzią/stopniem (playtest: „stoi na krawędzi bez ruchu")

## Na prawdziwej mapie 1.3 pierwszy Ślepiec (kol. 51, rząd 26) stoi na wyspie: po lewej szyb, po prawej metalowy blok jeden kafel wysoki (kol. 55). Wróg, który nie skacze,
## dotąd nie pokonywał nawet takiego stopnia, więc idąc na ślad za blokiem stał w miejscu. Teraz stopień o 1 kafel pokonuje małym przeskokiem.
func _test_slepiec_step() -> void:
	var e := level.get_node_or_null("Slepiec1") as CharacterBody2D
	check("stopień: mapa 1.3 ma Ślepca na wyspie (Slepiec1)", e != null and String(e.kind) == "slepiec")
	if e == null:
		return
	var t := float(level.TILE)
	var start := Vector2(51.0 * t + t * 0.5, 27.0 * t)
	e.global_position = start
	e.velocity = Vector2.ZERO
	e._home = start
	e.active = true
	e._lead_at(Vector2(60.0 * t + t * 0.5, 27.0 * t))                  # 5 kafli za blokiem na kol. 55
	var tt := 0.0
	while tt < 6.0 and e.global_position.x < 57.0 * t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	check("stopień: Ślepiec wchodzi na metalowy blok o 1 kafel i idzie dalej za ślad (nie stoi pod nim)", e.global_position.x > 56.0 * t, "x = %.0f kafli %.1f po %.1f s, blocked=%s" % [e.global_position.x, e.global_position.x / t, tt, e._blocked])

## Na mapie 1.3 szyb po lewej stronie wyspy Ślepca: wróg słyszący strzał z drugiej strony szybu dochodzi do krawędzi, ale stawał na niej w miejscu (krawędź zejścia FALL
## kończyła marsz 3 px od środka węzła, czyli dokładnie na krawędzi). Teraz schodzi w szyb i idzie dalej ścieżką.
func _test_slepiec_shaft() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["slepiec"]
	check("Ślepiec: 100 HP, 2 obrażenia, skacze (nie jest ‚lalką do bicia’)", float(cfg["hp"]) >= 100.0 and int(cfg["damage"]) == 2 and bool(cfg["leap"]))
	var e := level.get_node_or_null("Slepiec1") as CharacterBody2D
	if e == null:
		check("szyb: mapa 1.3 ma Ślepca na wyspie (Slepiec1)", false)
		return
	var t := float(level.TILE)
	e.global_position = Vector2(51.0 * t + 8.0, 27.0 * t - 1.0)
	e.velocity = Vector2.ZERO
	e._home = e.global_position
	e.active = false
	await get_tree().physics_frame
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": 0, "type": "bullet"})
	e._lead_at(Vector2(30.0 * t, 40.0 * t - 8.0))                            # ślad na dnie szybu, po drugiej stronie
	var tt := 0.0
	var y_max := 0.0
	var x_min := e.global_position.x
	while tt < 8.0 and y_max < 33.0 * t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		y_max = maxf(y_max, e.global_position.y)
		x_min = minf(x_min, e.global_position.x)
	check("szyb: Ślepiec słyszący strzał z tamtej strony szybu schodzi w szyb, zamiast stać na krawędzi", y_max >= 33.0 * t, "najniżej y = %.1f kafla, x_min = %.1f, po %.1f s" % [y_max / t, x_min / t, tt])
	e.active = false
	e.global_position = Vector2(51.0 * t + 8.0, 27.0 * t - 1.0)
	e.velocity = Vector2.ZERO
	await get_tree().physics_frame

## Dom, do którego nie da się dojść (wysoki mur), nie trzyma wroga obudzonego w nieskończoność: po RETURN_STUCK_TIME s bez ruchu dom przenosi się na miejsce postoju i wróg zasypia.
func _test_return_home_stuck() -> void:
	var y := -11500.0
	var strip := _floor(FAR_X + 24000.0, FAR_X + 24400.0, y)
	var x0 := FAR_X + 24100.0
	var wall := _block(Vector2(x0 + 22.0, y - 40.0), Vector2(6.0, 80.0))       # mur 5 kafli wysoki między wrogiem a domem
	var e := _spawn("slepiec", Vector2(x0, y))
	e._home = Vector2(x0 + 40.0, y)                                         # dom za murem, w zasięgu prostego marszu (|dx| < 48 → bez nawigacji po mapie gry)
	await get_tree().physics_frame
	await get_tree().physics_frame
	e.active = true
	e._has_lead = false
	e._target = null
	var t := 0.0
	while t < 10.0 and e.active:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("powrót do domu: dom za wysokim murem przenosi się na miejsce postoju, a wróg zasypia (nie stoi obudzony w nieskończoność)",
		not e.active and absf(e._home.x - x0) < 16.0, "aktywny=%s, dom Δx=%.0f po %.1f s" % [e.active, e._home.x - x0, t])
	for n in [e, wall, strip]:
		n.queue_free()
	await get_tree().physics_frame
