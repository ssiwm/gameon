extends Node
## Test headless AI zwykłych wrogów i hałasu (ENEMY_PLAN.md F0): każda poprawka z fazy 0 ma tu asercję.
##
##   godot --headless --path . -- --host --enemytest --autoquit=40
##
## Mapa 1.3 (jak testy Stalkera). Testy fizyczne stawiają własną geometrię (podłoga i ściana jako `StaticBody2D` na warstwie 1) daleko poza mapą,
## żeby nic ze świata gry ich nie zakłócało. Wynik: linie [ENEMY-TEST] i kod wyjścia (0 = OK) — nadaje się do CI.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Enemy := preload("res://scripts/enemy.gd")
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
	await _test_wolek_throw_vertical()
	await _test_slepiec_mechanics()
	await _test_slepiec_listen()
	await _test_slepiec_step()
	await _test_return_home_stuck()
	_finish()

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
	check("rozbieg Wołka: ciągła podłoga — wolno", w1._run_clear(1.0, 200.0))
	check("rozbieg Wołka: przepaść na trasie — nie rozpędza się", not w2._run_clear(1.0, 200.0))
	check("rozbieg Wołka: ściana dalej niż 200 px — też blokuje (pełny dystans)", not w3._run_clear(1.0, 260.0))
	check("rozbieg Wołka: ściana poza dystansem — nie blokuje", w3._run_clear(1.0, 150.0))
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
		e._alert = 0.0
		e._alert_cd = 0.0
		e._begin_alert()
		times[lvl] = e._alert
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
	a._shout_sighting(spot)
	check("wataha: kolega w zasięgu dostaje ślad w miejscu gracza i reakcję „zauważył”", b._has_lead and b._last_known.is_equal_approx(spot) and b.ai_name() == "alert", "lead=%s ai=%s" % [b._has_lead, b.ai_name()])
	check("wataha: śpiący kolega nie dostaje śladu (budzi go wake())", not c._has_lead and not c.active)
	check("wataha: inny rodzaj, inne piętro i za daleko nie słyszą", not d._has_lead and not up._has_lead and not far._has_lead)
	check("wataha: kolega, który ma już cel, i przywołany bossa nie zmieniają śladu", not busy._has_lead and not minion._has_lead)
	check("wataha: krzykacz ma cooldown", a._share_cd > 2.5, str(a._share_cd))
	b._has_lead = false
	b._ai = Enemy.Ai.RETURN
	b._alert = 0.0
	a._shout_sighting(spot)
	check("wataha: w czasie cooldownu drugi krzyk nic nie robi", not b._has_lead)

	# ścieżka percepcji: krzykacz widzi gracza po raz pierwszy → kolega poza zasięgiem wzroku (400 px od gracza) dostaje ślad
	a._share_cd = 0.0
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
	check("dyrektor: domyślna tabela jak dotąd — 0,59 → 2 Trzoski, 0,61 → 3, 0,86 → Ślepiec",
		D.pick_group(table, 0.0) == ["trzosek", "trzosek"] and D.pick_group(table, 0.59) == ["trzosek", "trzosek"] and D.pick_group(table, 0.61).size() == 3
		and D.pick_group(table, 0.84).size() == 3 and D.pick_group(table, 0.86) == ["slepiec"] and D.pick_group(table, 0.999) == ["slepiec"])
	check("dyrektor: wagi względne (nie muszą dawać 100)", D.pick_group([[1.0, ["a"]], [3.0, ["b"]]], 0.1) == ["a"] and D.pick_group([[1.0, ["a"]], [3.0, ["b"]]], 0.3) == ["b"])
	var copy: Array = D.pick_group(table, 0.0)
	copy.append("x")
	check("dyrektor: zwrócony zestaw to kopia (tabela się nie psuje)", D.pick_group(table, 0.0).size() == 2)
	check("dyrektor: mapa bez własnej tabeli dostaje domyślną", D.groups_for("z1_m3") == D.GROUPS)
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
	w._throw_cd = 0.0
	w._charge_cd = 99.0                                    # bez szarży — sprawdzamy sam rzut
	dummy.global_position = Vector2(x0 + 120.0, y - 100.0)  # półka 100 px nad nim, 120 px w bok
	check("Wołek: gracz na półce 100 px nad nim → zaczyna rzut skrzynią", w._bruiser_tick(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 120.0, y + 100.0)  # 100 px niżej (po drugiej stronie podłogi pomiarowej — tylko pozycja, bez fizyki)
	check("Wołek: gracz 100 px niżej (na niższym poziomie za krawędzią) → też rzut", w._bruiser_tick(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 20.0, y - 90.0)    # prawie nad nim (ax < 60) na półce
	check("Wołek: gracz prawie nad nim (ax < 60) na półce → rzut", w._bruiser_tick(0.016, dummy) and w._sp == 3, "sp=%d" % w._sp)
	w._sp = 0
	w.winding = false
	w._throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 120.0, y - 300.0)  # za wysoko (> THROW_DY_MAX)
	check("Wołek: za wysoko (300 px) → bez rzutu", not w._bruiser_tick(0.016, dummy) and w._sp == 0)
	w._throw_cd = 0.0
	dummy.global_position = Vector2(x0 + 400.0, y - 60.0)   # za daleko w poziomie
	check("Wołek: za daleko w poziomie → bez rzutu", not w._bruiser_tick(0.016, dummy) and w._sp == 0)
	w._throw_cd = 5.0
	dummy.global_position = Vector2(x0 + 120.0, y - 100.0)
	check("Wołek: w czasie cooldownu rzutu nie zaczyna", not w._bruiser_tick(0.016, dummy) and w._sp == 0)
	w._throw_cd = 0.0
	var wall := _block(Vector2(x0 + 60.0, y - 80.0), Vector2(6.0, 120.0))     # ściana na linii rzutu
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("Wołek: ściana na linii rzutu → bez rzutu", not w._bruiser_tick(0.016, dummy) and w._sp == 0)
	for n in [w, crate, dummy, wall, strip, strip2]:
		n.queue_free()
	await get_tree().physics_frame

## Ślepiec: po dojściu na ślad przeszukuje okolicę zamiast stać, a głośny dźwięk blisko uruchamia zapowiedź i rzut w jego stronę.
func _test_slepiec_mechanics() -> void:
	var Defs := load("res://scripts/enemy_defs.gd")
	var cfg: Dictionary = Defs.DEFS["slepiec"]["lunge"]
	check("Ślepiec: rzut na dźwięk — głośny i blisko tak, cichy albo daleko nie, rodzaj bez pola `lunge` nie",
		Enemy.lunge_triggers(cfg, 3.0, 100.0) and not Enemy.lunge_triggers(cfg, 0.6, 100.0) and not Enemy.lunge_triggers(cfg, 3.0, 200.0) and not Enemy.lunge_triggers({}, 9.0, 10.0))
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
	e._lunge_cd = 0.0
	e._target = null
	e.global_position.x = x0
	var src := Vector2(x0 + 100.0, y)
	e._lead_at(src)
	e._maybe_lunge(src, 100.0, 3.0)
	check("Ślepiec: głośny dźwięk 100 px obok → zapowiedź (alert) i oczy w widoku", e.ai_name() == "alert" and bool(e.view_info()["alert"]) and e._lunge_wind > 0.0, "%s / %.2f" % [e.ai_name(), e._lunge_wind])
	var x_wind: float = e.global_position.x
	await get_tree().create_timer(0.15).timeout
	check("Ślepiec: w zapowiedzi stoi w miejscu", absf(e.global_position.x - x_wind) < 2.0 and e.ai_name() == "alert")
	t = 0.0
	while t < 1.2 and e._lunge_t <= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var x_start: float = e.global_position.x
	check("Ślepiec: po zapowiedzi pędzi (stan lunge)", e.ai_name() == "lunge" and e._lunge_t > 0.0, e.ai_name())
	await get_tree().create_timer(0.3).timeout
	var v: float = (e.global_position.x - x_start) / 0.3
	check("Ślepiec: w rzucie jest szybszy niż w chodzie (> 1,5 × 70 px/s)", v > 105.0, "%.0f px/s" % v)
	t = 0.0
	while t < 2.0 and e._lunge_t > 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("Ślepiec: rzut kończy się za źródłem dźwięku i wraca do normalnego stanu", e._lunge_t <= 0.0 and e.global_position.x >= x0 + 90.0 and e.ai_name() != "lunge", "x=%.0f, %s" % [e.global_position.x, e.ai_name()])
	e._maybe_lunge(src, 100.0, 3.0)
	check("Ślepiec: cooldown rzutu (6 s) blokuje kolejny", e._lunge_wind == 0.0 and e._lunge_cd > 4.0, str(e._lunge_cd))
	e._lunge_cd = 0.0
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	e._maybe_lunge(src, 100.0, 3.0)
	e.take_hit({"amount": 1.0, "dir": Vector2.RIGHT, "pos": e.global_position, "shooter": int(player.player_id), "type": "bullet"})
	check("Ślepiec: trafiony w zapowiedzi rzutu nie stoi (zapowiedź przerwana)", e._lunge_wind == 0.0)
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
			(e._lunge_wind > 0.0) == bool(th[1]) and e._has_lead, "wind=%.2f lead=%s ai=%s" % [e._lunge_wind, e._has_lead, e.ai_name()])
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
