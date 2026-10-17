extends Node
## Dyrektor grozy (1.7.5) — serwerowy „reżyser tempa": mierzy napięcie drużyny i decyduje, KIEDY dać wytchnienie,
## a kiedy docisnąć. Cel (GDD §8/§13): rytm napięcie → szczyt → oddech, zamiast równego tła zagrożenia.
##
## Napięcie (`tension` 0..1) = max(stres, Uwaga·0,7). Stres rośnie od obrażeń (każdy utracony HP) i od walki w pobliżu,
## a opada, gdy jest cicho. Dyrektor:
##   • po szczycie stresu (> PEAK_STRESS) włącza OKNO ODDECHU (RELAX_TIME) — żadnych nowych wędrowców;
##   • gdy od ostatniego starcia minęło ≥ BREATH_MIN, stres jest niski, a „na mapie" są mniej niż MAX_GROUPS grup wędrowców —
##     po losowym czasie wypuszcza z ciemności (poza kadrem i bez linii wzroku) małą grupę wędrowców, która rusza
##     na ostatnią pozycję drużyny; to utrzymuje presję tam, gdzie gracze „wyczyścili" mapę;
##   • tylko w fazie OBJECTIVE (boss i ekstrakcja mają własny rytm);
##   • wysyła napięcie klientom — dread.gd skaluje nim straszaki (fałszywe odgłosy, migotanie).
## Częstość skaluje Difficulty „dread" (łatwo ×0,6, trudno ×1,5). Wszystko serwerowe; klienci tylko czytają `tension`.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const PEAK_STRESS := 0.75
const RELAX_TIME := 45.0
const BREATH_MIN := 35.0              ## s bez starcia, zanim wolno dosypać wędrowców
const SPAWN_MIN := 55.0
const SPAWN_MAX := 90.0
const ENCOUNTER_R := 520.0            ## aktywny wróg w tym promieniu od gracza = „starcie"
const SPAWN_DIST_MIN := 380.0         ## poza kadrem (widok ≈ ±200 px) z zapasem
const SPAWN_DIST_MAX := 640.0
const STRESS_PER_HP := 0.22
const STRESS_DECAY := 0.035           ## /s w ciszy
const DESPAWN_DIST := 760.0           ## uśpiony wędrowiec tak daleko od drużyny znika (żeby się nie kumulowali)

var tension := 0.0                    ## 0..1, na kliencie ustawiane z serwera
var stress := 0.0

var _prev_hp := -1
var _since_enc := 0.0
var _relax_t := 0.0
var _spawn_t := 60.0
var _sync_t := 0.0
var _serial := 0
var _roamers: Array[String] = []
var _groups: Array = []                ## grupy wędrowców: tablice nazw (patrz `live_groups`)
var _idle: Dictionary = {}            ## nazwa wędrowca → s uśpienia poza polem widzenia (patrz `_cleanup`)
var _run_t := 0.0                     ## s w fazie OBJECTIVE poza kryjówką — „czas od startu" dla składu grup (F3.10); nie liczy kryjówki ani bossa

func _process(delta: float) -> void:
	if not NoiseMgr.is_server():
		return
	var humans := _humans()
	if humans.is_empty():
		return
	_update_stress(delta, humans)
	tension = clampf(maxf(stress, NoiseMgr.level / NoiseMgr.MAX_LEVEL * 0.7), 0.0, 1.0)
	_sync_t -= delta
	if _sync_t <= 0.0 and NoiseMgr.has_network():
		_sync_t = 1.0
		_tension_rpc.rpc(tension)
	_cleanup(humans, delta)
	if not _can_spawn_now():
		return
	_run_t += delta
	_relax_t = maxf(0.0, _relax_t - delta)
	if _relax_t > 0.0 or _since_enc < BREATH_MIN or stress > 0.3 or live_groups() >= MAX_GROUPS:
		return
	_spawn_t -= delta * Difficulty.m("dread")
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(SPAWN_MIN, SPAWN_MAX)
		_spawn_group(humans)

@rpc("authority", "call_remote", "unreliable")
func _tension_rpc(t: float) -> void:
	tension = t

## Nowa misja / wipe: wędrowcy znikają, liczniki od zera.
func reset() -> void:
	if not NoiseMgr.is_server():
		return
	for n in _roamers.duplicate():
		_despawn(n)
	_roamers.clear()
	_groups.clear()
	_idle.clear()
	stress = 0.0
	tension = 0.0
	_prev_hp = -1
	_since_enc = 0.0
	_relax_t = 0.0
	_run_t = 0.0
	_spawn_t = randf_range(SPAWN_MIN, SPAWN_MAX)

# ---------------------------------------------------------------- model napięcia

func _humans() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead:
			out.append(p)
	return out

func _update_stress(delta: float, humans: Array) -> void:
	var hp := 0
	for p in humans:
		hp += p.hp
	if _prev_hp >= 0 and hp < _prev_hp:
		stress += STRESS_PER_HP * float(_prev_hp - hp)
	_prev_hp = hp
	var fighting := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("is_threat") or not e.is_threat():
			continue
		if e.is_in_group("props") or e.is_in_group("nests"):
			continue
		for p in humans:
			if p.global_position.distance_to(e.global_position) < ENCOUNTER_R:
				fighting += 1
				break
	if fighting > 0:
		_since_enc = 0.0
		stress += 0.02 * float(mini(fighting, 6)) * delta
	else:
		_since_enc += delta
		stress -= STRESS_DECAY * delta
	stress = clampf(stress, 0.0, 1.0)
	if stress >= PEAK_STRESS and _relax_t <= 0.0:
		_relax_t = RELAX_TIME
		print("[DIRECTOR] szczyt stresu %.2f -> okno oddechu %.0f s" % [stress, RELAX_TIME])

func _can_spawn_now() -> bool:
	var main := get_tree().current_scene
	var mission = main.get("mission") if main != null else null
	# 0 = OBJECTIVE (mission.gd Phase) — boss i ekstrakcja mają własny rytm
	return mission != null and int(mission.phase) == 0 and not NoiseMgr.safe_zone       # kryjówka (safe_zone) jest wolna od wrogów

# ---------------------------------------------------------------- wędrowcy

func _spawn_group(humans: Array) -> void:
	if NoiseMgr.safe_zone:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or lvl.get("nav") == null:
		return
	var anchor: Node2D = humans[randi() % humans.size()]
	var pos := _pick_spot(lvl, anchor.global_position, humans)
	if pos == Vector2.ZERO:
		return
	var map_id := String(lvl.get("map_id"))
	var ctx := build_ctx()
	var table := groups_for(map_id)
	var kinds: Array = pick_group(table, randf(), ctx)
	var odds := group_odds(table, ctx)
	print("[DIRECTOR] skład: czas %.0f s, napięcie %.2f, szanse %s" % [float(ctx["time"]), float(ctx["tension"]), str(odds)])
	SessionLog.event("director_spawn", {"map": map_id, "time": snappedf(float(ctx["time"]), 1.0), "tension": snappedf(float(ctx["tension"]), 0.01), "quiet": snappedf(float(ctx["quiet"]), 1.0), "kinds": kinds, "odds": odds})
	# dokąd ruszają: jeśli niedawno (≤ HOT_SPOT_AGE) gdzieś w pobliżu gracza strzelano, do tego „gorącego miejsca"; inaczej na pozycję gracza
	var hot: Variant = NoiseMgr.hot_spot_near(anchor.global_position, HOT_SPOT_R, HOT_SPOT_AGE)
	var hunt_at: Vector2 = hot if hot != null else anchor.global_position
	print("[DIRECTOR] wędrowcy %s przy %s ku %s (stres %.2f, od starcia %.0f s)" % [str(kinds), str(pos.round()), str(hunt_at.round()), stress, _since_enc])
	var group: Array = []
	for i in kinds.size():
		_serial += 1
		var n := "Roamer%d" % _serial
		group.append(n)
		var at := pos + Vector2(float(i) * 14.0, 0.0)
		if NoiseMgr.has_network():
			_spawn_roamer.rpc(n, kinds[i], at, hunt_at)
		else:
			_spawn_roamer(n, kinds[i], at, hunt_at)
	_groups.append(group)

## Zestawy wędrowców (F3.7, F3.10): [waga względna, rodzaje] albo [waga, rodzaje, okna]. `okna` (opcjonalne) to słownik `{"time": [od, do], "tension": [od, do], "fade": s}`:
## zestaw jest dostępny tylko wtedy, gdy czas od startu (s; × `dread`, więc łatwy eskaluje wolniej) i napięcie mieszczą się w oknach. Waga rośnie liniowo od 0 na początku
## okna do pełnej po `T_FADE` s (czas) albo `TENSION_FADE` (napięcie) i spada tak samo po końcu okna — patrz `entry_weight`; `INF` = bez końca; `fade` w oknach nadpisuje czas.
## Uwaga: w chwili spawnu stres ≤ 0,3, więc napięcie to w praktyce Uwaga × 0,7 (0…0,7): okna napięcia ustawiamy w tym zakresie.
## Tylko ruchome rodzaje (Trzosek, Ślepiec, Wołek) — Skoczek wisi, Podsłuchacz stoi, Ćma lata, Mimik udaje kolegę. Mapa może mieć własną tabelę w GROUPS_BY_MAP.
const T_FADE := 60.0                         ## s narastania wagi zestawu po początku okna czasu
const TENSION_FADE := 0.1                    ## napięcia, na których narasta waga po początku okna napięcia
const GROUPS := [
	[60.0, ["trzosek", "trzosek"]],
	[25.0, ["trzosek", "trzosek", "trzosek"], {"time": [180.0, INF]}],
	[20.0, ["trzosek", "trzosek", "trzosek", "trzosek"], {"time": [480.0, INF], "tension": [0.15, INF]}],
	[15.0, ["slepiec"], {"time": [90.0, INF], "tension": [0.1, INF]}],
	[12.0, ["slepiec", "slepiec"], {"time": [360.0, INF], "tension": [0.2, INF]}],
	[12.0, ["wolek", "trzosek"], {"time": [360.0, INF], "tension": [0.1, INF]}],
	[10.0, ["wolek", "trzosek", "trzosek"], {"time": [600.0, INF], "tension": [0.2, INF]}],
	[8.0, ["kaplan", "trzosek", "trzosek"], {"time": [540.0, INF], "tension": [0.1, INF]}],                     # elita: Kapłan leczy Trzoski (max jedna elita naraz)
	[6.0, ["rzeznik"], {"time": [720.0, INF], "tension": [0.1, INF]}],                                           # elita: Rzeźnik solo, ciężka szarża (max jedna elita naraz)
	[6.0, ["zerca"], {"time": [360.0, INF], "downs": [1, INF]}],                                                 # elita: Żerca wyczuwa krew — dopiero po pierwszym upadku w misji
]
const GROUPS_BY_MAP := {
	# 1.1 Missing Patrol (samouczek: 12 T, 3 W, bez Ślepców — pierwszy raz w 1.2): same Trzoski, Wołek dopiero po 8 min
	"z1_m1": [
		[60.0, ["trzosek", "trzosek"]],
		[25.0, ["trzosek", "trzosek", "trzosek"], {"time": [150.0, INF]}],
		[15.0, ["trzosek", "trzosek", "trzosek", "trzosek"], {"time": [420.0, INF]}],
		[10.0, ["wolek", "trzosek"], {"time": [480.0, INF]}],
	],
	# 1.2 Radio Silence (generatory — głośna misja, 5 L, 8 P): Ślepce odpowiadają na hałas, Wołek od 6 min
	"z1_m2": [
		[45.0, ["trzosek", "trzosek"]],
		[20.0, ["trzosek", "trzosek", "trzosek"], {"time": [180.0, INF]}],
		[22.0, ["slepiec"], {"time": [60.0, INF], "tension": [0.1, INF]}],
		[16.0, ["slepiec", "slepiec"], {"time": [360.0, INF], "tension": [0.2, INF]}],
		[12.0, ["wolek", "trzosek"], {"time": [360.0, INF], "tension": [0.1, INF]}],
		[10.0, ["wolek", "trzosek", "trzosek"], {"time": [600.0, INF], "tension": [0.2, INF]}],
		[8.0, ["kaplan", "trzosek", "trzosek"], {"time": [540.0, INF], "tension": [0.1, INF]}],
		[6.0, ["rzeznik"], {"time": [780.0, INF], "tension": [0.15, INF]}],
		[7.0, ["zerca"], {"time": [360.0, INF], "downs": [1, INF]}],
	],
	# 1.3 The Nest (las i tunele, 16 T, 4 W, 3 L): przewaga Trzosków i Wołka, mało Ślepców
	"z1_m3": [
		[55.0, ["trzosek", "trzosek"]],
		[30.0, ["trzosek", "trzosek", "trzosek"], {"time": [150.0, INF]}],
		[15.0, ["trzosek", "trzosek", "trzosek", "trzosek"], {"time": [420.0, INF], "tension": [0.15, INF]}],
		[8.0, ["slepiec"], {"time": [120.0, INF], "tension": [0.15, INF]}],
		[18.0, ["wolek", "trzosek"], {"time": [300.0, INF]}],
		[10.0, ["wolek", "trzosek", "trzosek"], {"time": [540.0, INF], "tension": [0.15, INF]}],
		[10.0, ["kaplan", "trzosek", "trzosek"], {"time": [480.0, INF], "tension": [0.1, INF]}],
		[8.0, ["rzeznik"], {"time": [660.0, INF], "tension": [0.1, INF]}],
		[7.0, ["zerca"], {"time": [360.0, INF], "downs": [1, INF]}],
	],
}                                            ## id mapy → tabela jak GROUPS (brak wpisu = GROUPS)
const MAX_ELITES := 1                        ## najwyżej tyle żywych elit naraz (F4): zestawy z elitą odpadają z losowania, gdy limit zajęty
const MAX_GROUPS := 2                        ## tyle grup wędrowców naraz (nowa dopiero, gdy któraś zginie albo zniknie)
const HOT_SPOT_R := 600.0                    ## „gorące miejsce" (niedawna strzelanina) w tym promieniu od gracza wyznacza cel wędrowców
const HOT_SPOT_AGE := 90.0                   ## s: starsze strzelaniny się nie liczą
const ROAMER_IDLE_DESPAWN := 45.0            ## s uśpienia poza polem widzenia, po których wędrowiec znika (żeby uśpiona grupa nie blokowała następnych)
const PICK_TRIES := 80                       ## prób losowania punktu spawnu (kleszcze: pierwsze PINCER_TRIES tylko z przeciwnej strony)
const PINCER_TRIES := 50
const PINCER_R := 900.0                      ## px: wędrowcy dalej od gracza nie liczą się do „strony" kleszczy
const PINCER_MIN_DX := 40.0                  ## px: średnia pozycja bliżej gracza niż to = brak wyraźnej strony

static func groups_for(map_id: String) -> Array:
	return GROUPS_BY_MAP.get(map_id, GROUPS)

## Kontekst losowania składu grupy (F3.10, F4): czas od startu w fazie celu × `dread`, napięcie Dyrektora, spokój od ostatniego starcia, liczba upadków w misji
## (`downs`: Żerca dopiero po pierwszym) oraz żywe elity (`elites`, limit MAX_ELITES) i rodzaje elit z danych (`elite_kinds`).
func build_ctx() -> Dictionary:
	var main := get_tree().current_scene
	var mission = main.get("mission") if main != null else null
	return {"time": _run_t * Difficulty.m("dread"), "tension": tension, "quiet": _since_enc, "downs": int(mission.downs) if mission != null else 0,
		"elites": count_elites(), "elite_kinds": EnemyDefs.elite_kinds()}

## Ilu żywych wrogów jest elitami (pole `elite` w danych rodzaju).
func count_elites() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.get("alive") == true and EnemyDefs.is_elite(str(e.get("kind"))):
			n += 1
	return n

## Czynnik okna `[od, do]` dla wartości `x`: 0 przed początkiem, rośnie liniowo do 1 w `fade` jednostek od początku, a po końcu spada tak samo do 0 (`do` = INF → bez końca).
## Początek ≤ 0 oznacza „od zawsze".
static func window_factor(x: float, win: Array, fade: float) -> float:
	var lo := float(win[0])
	var hi := float(win[1])
	var f_in := 1.0 if lo <= 0.0 else clampf((x - lo) / maxf(fade, 0.0001), 0.0, 1.0)
	var f_out := 1.0 if is_inf(hi) else clampf((hi + fade - x) / maxf(fade, 0.0001), 0.0, 1.0)
	return minf(f_in, f_out)

## Waga zestawu przy danym kontekście: waga × czynnik okna czasu × czynnik okna napięcia. Wpis bez okien (albo kontekst bez danego klucza) = sama waga.
static func entry_weight(entry: Array, ctx: Dictionary) -> float:
	var w := float(entry[0])
	if ctx.is_empty():
		return w
	# elity (F4): gdy ich limit zajęty, zestawy z elitą odpadają (`elites` = żywe elity, `elite_kinds` = rodzaje elit z danych)
	if int(ctx.get("elites", 0)) >= MAX_ELITES:
		for k in entry[1]:
			if (ctx.get("elite_kinds", []) as Array).has(k):
				return 0.0
	if entry.size() < 3:
		return w
	var win := entry[2] as Dictionary
	if win.has("time") and ctx.has("time"):
		w *= window_factor(float(ctx["time"]), win["time"], float(win.get("fade", T_FADE)))
	if win.has("tension") and ctx.has("tension"):
		w *= window_factor(float(ctx["tension"]), win["tension"], float(win.get("tension_fade", TENSION_FADE)))
	if win.has("downs") and ctx.has("downs"):
		var r := win["downs"] as Array                           # okno liczby upadłych w tej misji (całkowite, włącznie na obu końcach); Żerca dopiero po pierwszym upadku
		if float(ctx["downs"]) < float(r[0]) or float(ctx["downs"]) > float(r[1]):
			return 0.0
	return w

## Szanse zestawów (procenty w kolejności wpisów) — do logu i testów.
static func group_odds(table: Array, ctx: Dictionary) -> Array:
	var ws: Array = []
	var total := 0.0
	for g in table:
		var w := entry_weight(g, ctx)
		ws.append(w)
		total += w
	var out: Array = []
	for w in ws:
		out.append(snappedf(100.0 * float(w) / total, 0.1) if total > 0.0 else 0.0)
	return out

## Wybiera zestaw z tabeli wg rzutu `roll` ∈ [0, 1) i wag (kolejność wpisów = kolejność przedziałów); z `ctx` wagi uwzględniają okna czasu i napięcia.
## Gdyby wszystkie wagi wyszły 0, bierze pierwszy wpis (podstawowy zestaw tabeli).
static func pick_group(table: Array, roll: float, ctx := {}) -> Array:
	var total := 0.0
	for g in table:
		total += entry_weight(g, ctx)
	if total <= 0.0:
		return ((table[0] as Array)[1] as Array).duplicate()
	var acc := 0.0
	var last := table[0] as Array
	for g in table:
		var w := entry_weight(g, ctx)
		if w <= 0.0:
			continue
		last = g
		acc += w / total
		if roll < acc:
			return (g[1] as Array).duplicate()
	return (last[1] as Array).duplicate()

## Ile grup wędrowców wciąż ma żywego członka na liście (martwe i zniknięte grupy są usuwane).
func live_groups() -> int:
	var live := 0
	for g in _groups.duplicate():
		var any := false
		for n in g:
			if _roamers.has(n):
				any = true
				break
		if any:
			live += 1
		else:
			_groups.erase(g)
	return live

## Punkt do postawienia wędrowców: węzeł grafu nawigacji 380–640 px od gracza, bez linii wzroku do żadnego człowieka.
func _pick_spot(lvl: Node, near: Vector2, humans: Array) -> Vector2:
	var nav: AStar2D = lvl.nav
	var ids := nav.get_point_ids()
	var space := get_tree().root.get_world_2d().direct_space_state
	var avoid := _roamer_side(lvl, near)                  # kleszcze: gdy z jednej strony już ktoś jest, nowi wychodzą z drugiej
	for _try in PICK_TRIES:
		var id: int = ids[randi() % ids.size()]
		var pt := nav.get_point_position(id)
		var d := pt.distance_to(near)
		if d < SPAWN_DIST_MIN or d > SPAWN_DIST_MAX:
			continue
		if not pincer_side_ok(avoid, pt.x - near.x, _try):
			continue
		var visible := false
		for p in humans:
			var q := PhysicsRayQueryParameters2D.create(p.global_position + Vector2(0, -9), pt + Vector2(0, -8), 1)
			if space.intersect_ray(q).is_empty() and p.global_position.distance_to(pt) < 460.0:
				visible = true
				break
		if not visible:
			return pt
	return Vector2.ZERO

## Kleszcze (F3.4): po której stronie `near` (−1 / +1) są już żywi wędrowcy z poprzedniej grupy — średnia ich pozycji w PINCER_R; 0, gdy nikogo nie ma
## w pobliżu albo stoją pod graczem (|średnia| ≤ PINCER_MIN_DX). Nowa grupa dostaje wtedy spawn z przeciwnej strony, czyli drużyna jest atakowana z dwóch stron
## bez przechodzenia wrogów przez gracza (wrogowie i gracze nie kolidują, więc „obejście" w walce wyglądałoby jak przenikanie).
func _roamer_side(lvl: Node, near: Vector2) -> float:
	var sum := 0.0
	var n := 0
	for rn in _roamers:
		var e := lvl.get_node_or_null(rn) as Node2D
		if e == null or not is_instance_valid(e) or not e.alive:
			continue
		if e.global_position.distance_to(near) <= PINCER_R:
			sum += e.global_position.x - near.x
			n += 1
	if n == 0:
		return 0.0
	var mean := sum / float(n)
	return signf(mean) if absf(mean) > PINCER_MIN_DX else 0.0

## Czy punkt spawnu `dx` px od gracza (znak = strona) wolno wziąć przy próbie nr `try_i`: pierwsze PINCER_TRIES prób tylko z przeciwnej strony niż `avoid`,
## potem dowolna (gdy po tamtej stronie nie ma miejsca, np. ściana — lepiej nie z przeciwnej niż wcale).
static func pincer_side_ok(avoid: float, dx: float, try_i: int) -> bool:
	return avoid == 0.0 or try_i >= PINCER_TRIES or signf(dx) != avoid

@rpc("authority", "call_local", "reliable")
func _spawn_roamer(n: String, kind: String, pos: Vector2, hunt_at: Vector2) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or lvl.has_node(n):
		return
	var e := ENEMY_SCENE.instantiate()
	e.name = n
	e.kind = kind
	e.position = pos
	lvl.add_child(e)
	e.add_to_group("roamers")
	if NoiseMgr.is_server():
		_roamers.append(n)
		e._lead_at(hunt_at)        # rusza na ostatnią znaną pozycję drużyny
		e.wake()

@rpc("authority", "call_local", "reliable")
func _despawn_rpc(n: String) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var e := lvl.get_node_or_null(n) if lvl != null else null
	if e != null:
		e.queue_free()

func _despawn(n: String) -> void:
	if NoiseMgr.has_network():
		_despawn_rpc.rpc(n)
	else:
		_despawn_rpc(n)

## Martwi znikają z listy; uśpieni znikają ze świata, gdy są bardzo daleko od drużyny (DESPAWN_DIST) albo gdy śpią ≥ ROAMER_IDLE_DESPAWN s poza polem widzenia
## (bliżej niż SPAWN_DIST_MIN albo w linii wzroku człowieka nie znikają — gracz nie może zobaczyć, jak wróg rozpływa się w powietrzu).
func _cleanup(humans: Array, delta := 0.0) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return
	for n in _roamers.duplicate():
		var e := lvl.get_node_or_null(n)
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion() or not e.alive:
			_roamers.erase(n)
			_idle.erase(n)
			continue
		if e.active:
			_idle[n] = 0.0
			continue
		_idle[n] = float(_idle.get(n, 0.0)) + delta
		var far := true
		for p in humans:
			if p.global_position.distance_to(e.global_position) < DESPAWN_DIST:
				far = false
		if far or (float(_idle[n]) >= ROAMER_IDLE_DESPAWN and not _seen_or_close(e, humans)):
			_roamers.erase(n)
			_idle.erase(n)
			_despawn(n)

## Czy któryś człowiek jest blisko wroga (< SPAWN_DIST_MIN) albo go widzi (linia bez ściany w 460 px) — wtedy nie znika.
func _seen_or_close(e: Node2D, humans: Array) -> bool:
	var space := get_tree().root.get_world_2d().direct_space_state
	for p in humans:
		var d: float = p.global_position.distance_to(e.global_position)
		if d < SPAWN_DIST_MIN:
			return true
		if d < 460.0:
			var q := PhysicsRayQueryParameters2D.create(p.global_position + Vector2(0, -9), e.global_position + Vector2(0, -8), 1)
			if space.intersect_ray(q).is_empty():
				return true
	return false
