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
		for ev in ["attack", "death"]:
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
