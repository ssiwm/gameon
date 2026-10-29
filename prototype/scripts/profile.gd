extends Node
## Autoload „Profile”: lokalny profil gracza (GDD §10.1 „Wroga wiedza”, §10.2 perki). Każdy człowiek ma własny — XP, poziom i założone perki
## żyją na JEGO komputerze (`profile.cfg` aktywnej postaci, characters.gd), nie w zapisie hosta (złom i ulepszenia są wspólne, perk jest osobisty).
##
## XP (liczone na serwerze, wysyłane do właściciela profilu): zabójstwa (pole `xp` w enemy_defs.gd, ostatni trafiający), ukończenie misji (+bonusy: cel
## poboczny, bez upadków, boss, pierwsze ukończenie danej misji), podniesienie kolegi. Nocny Dyżur: połowa. Poziom: próg kolejnego rośnie
## o 150, 250, 350… (L2 = 150 XP, L3 = 400, L4 = 750, L5 = 1200). Sloty perków: 1 od poziomu 2, 2 od poziomu 4. Perki: perks.gd (hooki — faza B3).

const Perks := preload("res://scripts/perks.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Look := preload("res://scripts/look.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const SessionLog := preload("res://scripts/session_log.gd")

signal xp_gained(amount: int, reason: String)
signal leveled_up(level: int)
signal changed
signal discovered(id: String)                 ## nowy wpis bestiariusza (bestiary_watch.gd pokazuje komunikat)

const SAVE_FILE := "profile.cfg"             ## w folderze aktywnej postaci (Characters.file, PROFILES_PLAN.md E1; do 1.7.425 user://profile.cfg)
const STEP_BASE := 50                 ## próg poziomu n+1 minus n = STEP_BASE + STEP_PER_LEVEL × n
const STEP_PER_LEVEL := 100
const SLOT_LEVELS := [2, 4]           ## poziom odblokowujący 1. i 2. slot perka
const MAX_SLOTS := 2

const EnemyDefs := preload("res://scripts/enemy_defs.gd")        ## XP za zabójstwo wg rodzaju wroga: pole `xp` w enemy_defs.gd
const XP_MISSION := 100
const XP_SIDE := 50
const XP_NO_DOWNS := 25
const XP_BOSS := 300
const XP_FIRST_CLEAR := 100
const XP_REVIVE := 15

var xp := 0
var completed: Dictionary = {}                ## id misji → true (pierwsze ukończenie daje bonus)
var look := 0                                 ## wygląd (Look.code): płeć × strój; kosmetyka, odblokowywana poziomem
var equipped: Array = ["", ""]                ## id perków w slotach 0–1 ("" = pusty)
var fits: Dictionary = {}                     ## klucz broni → {gniazdo: id części | "" (fabryczny)}; brak wpisu = pierwsza odblokowana część (parts.gd)
var presets: Dictionary = {}                  ## klucz broni → [PRESETS × {gniazdo: id części | ""}] — zapisane zestawy części (WORKSHOP_PLAN.md U6, od 1.7.349); {} = pusty
const PRESETS := 3                            ## tyle zestawów na broń
var cond: Dictionary = {}                     ## klucz broni → stan techniczny 0..100 % (GUNSMITH_PLAN §6, od 1.7.328); brak wpisu = 100
var edge: Dictionary = {}                     ## klucz broni białej → stan ostrza 0..100 % (WORKSHOP_PLAN.md W6b, od 1.7.358); brak wpisu = 100
## Ostrze broni białej (szlifierka przy tokarce): każdy zamach tępi o EDGE_WEAR % (× ustawienie niezawodności), tępe ostrze rani słabiej —
## obrażenia × (EDGE_MIN + (1 − EDGE_MIN) × ostrze). Ostrzenie bez złomu: EDGE_STEP s za każde rozpoczęte 10 %.
const EDGE_WEAR := 1.0
const EDGE_MIN := 0.7
const EDGE_STEP := 1.0
var worn: Dictionary = {}                     ## klucz broni → {część eksploatacyjna: zużycie 0..100 %} (WORKSHOP_PLAN.md W2, od 1.7.350); brak wpisu = nowa
## Części eksploatacyjne broni palnej (stół konserwacji): lufa — zużyta rozrzuca (weapon_controller.BARREL_SPREAD), sprężyny (powrotna, iglicy) —
## zużyte nie dają się doczyścić: czyszczenie przywraca stan najwyżej do clean_cap. Wymiana za złom (Scrap.SERVICE_COST).
const WEAR_PARTS := ["barrel", "springs"]
const SPRINGS_CAP := 0.5                      ## górna granica stanu po czyszczeniu = 100 − 0,5 × zużycie sprężyn (60 % zużycia → 70 %, próg zacięć)
## Wymiana części eksploatacyjnej dopiero od SERVICE_DUE % zużycia (od 1.7.412): niżej skutek jest pomijalny (lufa 40 % = rozrzut +10 %,
## sprężyny 40 % = czyszczenie do 80 %), a gra pozwalała zapłacić 40 złomu za lufę zużytą w 0,7 %. Od SERVICE_URGENT % — pilna.
const SERVICE_DUE := 40.0
const SERVICE_URGENT := 70.0
var mastery: Dictionary = {}                  ## klucz broni → punkty wprawy (GUNSMITH_PLAN §7.3, od 1.7.330): trafienia i zabójstwa tym graczem z tej broni
var history: Dictionary = {}                  ## klucz broni → {"k": zabójstwa, "e": elity, "b": bossowie} (GUNSMITH_PLAN §7.4, od 1.7.331)
var seen: Dictionary = {}                     ## znaczniki „nowe” (od 1.7.409): "perk:<id>" / "part:<id>" / "beast:<id>" → gracz już to obejrzał
var _seen_baseline := true                    ## profil bez listy obejrzanych: pierwsze zapytanie uznaje wszystko, co już jest, za obejrzane
var bestiary: Dictionary = {}                 ## id wpisu bestiariusza → zabójstwa tego gracza; wpis jest = gracz spotkał tego wroga (od 1.7.407)
var range_best: Dictionary = {}               ## strzelnica FPP, rekordy osobiste: "<ćwiczenie>:<klucz broni>" → wynik (czas w s; papier — grupa w MOA), mniej = lepiej
const NOTCH_MAX := 12                         ## tyle nacięć najwyżej mieści się na kolbie
## Bestiariusz (od 1.7.407): wpisy znane od początku (Stalker poluje w każdej misji, gniazda są celem) i specjalne wpisy spoza enemy_defs.gd.
const BESTIARY_ALWAYS := ["stalker", "nest"]
const BESTIARY_EXTRA := ["stalker", "nest", "vein", "leech"]
## Progi stopni wprawy 0..5 (punkty: trafienie 1, krytyk 2, zabójstwo 5 — weapon_controller.gd). Pierwszy stopień po jednej misji, piąty po kilkunastu.
const MASTERY_XP := [0, 60, 200, 450, 850, 1500]
var _cond_dirty := false
var _cond_save_t := 0.0
const COND_SAVE_EVERY := 30.0                 ## s — stan zmienia się co strzał, więc zapis najwyżej co tyle (i przy wyjściu z gry)
const CLEAN_STEP := 1.5                       ## s czyszczenia przy ławie za każde rozpoczęte 10 % zużycia (od 1.7.347 zamiast złomu: koszt to czas w kryjówce)
var last_mission_xp := 0                      ## XP z ostatniej misji (karta wyniku)
var last_mission_rows: Array = []             ## [[etykieta, XP], …] z ostatniej misji
var run_xp := 0                               ## XP spoza wyniku (zabójstwa, podniesienia) od ostatniego wyniku misji — także z prób zakończonych wipe'em
var last_run_xp := 0                          ## run_xp zamknięte przy ostatnim wyniku: karta wyniku pokazuje last_mission_xp + last_run_xp (P1.2)
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie ruszają prawdziwego profilu

func _ready() -> void:
	if persist:
		load_from(save_path())

# ---------------------------------------------------------------- poziomy

## Łączne XP potrzebne do osiągnięcia poziomu `n` (L1 = 0).
static func xp_for_level(n: int) -> int:
	var total := 0
	for k in range(1, n):
		total += STEP_BASE + STEP_PER_LEVEL * k
	return total

static func level_of(total_xp: int) -> int:
	var n := 1
	while total_xp >= xp_for_level(n + 1):
		n += 1
	return n

func level() -> int:
	return level_of(xp)

## Ile XP w bieżącym poziomie i ile do następnego: [mam, potrzeba].
func level_progress() -> Array:
	var n := level()
	return [xp - xp_for_level(n), xp_for_level(n + 1) - xp_for_level(n)]

func slots() -> int:
	var n := 0
	for lv in SLOT_LEVELS:
		if level() >= int(lv):
			n += 1
	return n

# ---------------------------------------------------------------- XP

func add_xp(amount: int, reason := "") -> void:
	if amount <= 0:
		return
	var before := level()
	xp += amount
	if reason != "Mission":
		run_xp += amount
	xp_gained.emit(amount, reason)
	var after := level()
	for lv in range(before + 1, after + 1):
		leveled_up.emit(lv)
	changed.emit()
	save()

## Wynik misji (u właściciela profilu): XP za ukończenie + bonusy; pierwsze ukończenie danej misji daje dodatkowe XP. Nocny Dyżur: połowa.
func apply_mission_result(map_id: String, side_ok: bool, no_downs: bool, boss: bool, night := false) -> int:
	var rows: Array = [["Mission cleared", XP_MISSION]]
	if side_ok:
		rows.append(["Side objective", XP_SIDE])
	if no_downs:
		rows.append(["No downs", XP_NO_DOWNS])
	if boss:
		rows.append(["Boss", XP_BOSS])
	if not night and not completed.has(map_id):
		rows.append(["First clear", XP_FIRST_CLEAR])
	var total := 0
	for r in rows:
		total += int(r[1])
	if night:
		total = int(round(float(total) * 0.5))
	if not night:
		completed[map_id] = true
	last_mission_xp = total
	last_mission_rows = rows
	last_run_xp = run_xp
	run_xp = 0
	add_xp(total, "Mission")
	_report_mission_xp(total, rows)
	return total

## Raport XP z misji do dziennika sesji hosta (PROGRESSION_PLAN.md P0.1): host zapisuje od razu, klient wysyła go hostowi.
func _report_mission_xp(total: int, rows: Array) -> void:
	var labels: Array = []
	for r in rows:
		labels.append(String(r[0]))
	if not NoiseMgr.has_network() or NoiseMgr.is_server():
		_log_mission_xp(NoiseMgr.local_id(), total, labels, xp)
	else:
		_xp_report.rpc_id(1, total, labels, xp)

@rpc("any_peer", "call_remote", "reliable")
func _xp_report(total: int, labels: Array, now_xp: int) -> void:
	if NoiseMgr.is_server():
		_log_mission_xp(multiplayer.get_remote_sender_id(), total, labels, now_xp)

## Serwer: wiersz `xp` w dzienniku sesji. Dane pochodzą od właściciela profilu — tylko statystyka, gra niczego z nich nie liczy.
func _log_mission_xp(pid: int, total: int, labels: Array, now_xp: int) -> void:
	var p := _human_by_id(pid)
	if p == null:
		return
	var rows: Array = []
	for l in labels.slice(0, 8):
		rows.append(String(l).left(32))
	SessionLog.note("xp", {"who": int(p.display_id), "mission": clampi(total, 0, 10000), "rows": rows, "xp": maxi(0, now_xp), "level": level_of(maxi(0, now_xp))})

# ---------------------------------------------------------------- przyznawanie (serwer → właściciel)

func _human_by_id(player_id: int) -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.player_id) == player_id and not p.is_bot:
			return p
	return null

func _is_local(player_id: int) -> bool:
	return not NoiseMgr.has_network() or player_id == NoiseMgr.local_id()

## Serwer: zabójstwo wroga `kind` przez gracza `shooter_id` (boty i przypadkowe zgony nie dają XP).
func server_award_kill(shooter_id: int, kind: String) -> void:
	if not NoiseMgr.is_server() or EnemyDefs.xp(kind) <= 0 or _human_by_id(shooter_id) == null:
		return
	var ms: Variant = get_tree().current_scene.get("mission") if get_tree().current_scene != null else null
	if ms != null and ms.has_method("note_kill"):
		ms.note_kill(shooter_id)                                   # statystyka do ekranu wyniku (liczba zabójstw per gracz)
	var amount := EnemyDefs.xp(kind)
	if NightShift.active:
		amount = maxi(1, amount / 2)
	SessionLog.note_kill(shooter_id, kind, amount)                 # dziennik sesji: zabójstwa wg rodzaju i XP (PROGRESSION_PLAN.md P0.3)
	if _is_local(shooter_id):
		add_xp(amount, "Kill")
		note_beast_kill(kind)
	else:
		_recv_xp.rpc_id(shooter_id, amount, "Kill")
		_recv_beast_kill.rpc_id(shooter_id, kind)

## Serwer: misja ukończona — każdy człowiek dostaje XP za wynik (bonusy liczy jego profil: pierwsze ukończenie).
func server_award_mission(map_id: String, side_ok: bool, no_downs: bool, boss: bool) -> void:
	if not NoiseMgr.is_server():
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			continue
		var pid := int(p.player_id)
		if _is_local(pid):
			apply_mission_result(map_id, side_ok, no_downs, boss, NightShift.active)
		else:
			_recv_mission.rpc_id(pid, map_id, side_ok, no_downs, boss, NightShift.active)

@rpc("authority", "call_remote", "reliable")
func _recv_xp(amount: int, reason: String) -> void:
	add_xp(amount, reason)

@rpc("authority", "call_remote", "reliable")
func _recv_beast_kill(kind: String) -> void:
	if EnemyDefs.DEFS.has(kind):
		note_beast_kill(kind)

## Bestiariusz: czy gracz zna wpis `id` (rodzaj z enemy_defs.gd albo stalker / nest / vein / leech).
func knows(id: String) -> bool:
	return bestiary.has(id) or id in BESTIARY_ALWAYS

## Pierwsze spotkanie: wpis bestiariusza się odsłania. Zapis jak stanu broni (co COND_SAVE_EVERY s).
func discover(id: String) -> void:
	if knows(id):
		return
	bestiary[id] = 0
	_cond_dirty = true
	discovered.emit(id)

## Zabójstwo wroga rodzaju `kind` przez tego gracza (serwer: server_award_kill). Zabity wróg jest też spotkany.
func note_beast_kill(kind: String) -> void:
	discover(kind)
	bestiary[kind] = int(bestiary.get(kind, 0)) + 1
	_cond_dirty = true

func beast_kills(id: String) -> int:
	return int(bestiary.get(id, 0))

## Znacznik „nowe”: rzecz jest dostępna (perk odblokowany, część drużyny, spotkany wróg), a gracz jej jeszcze nie obejrzał w panelu.
func is_new(key: String) -> bool:
	_seen_baseline_now()
	if seen.has(key):
		return false
	var id := key.get_slice(":", 1)
	match key.get_slice(":", 0):
		"perk":
			return is_unlocked(id)
		"part":
			return Scrap.has_part(id)
		"beast":
			return bestiary.has(id) and not id in BESTIARY_ALWAYS
	return false

func mark_seen(key: String) -> void:
	if not seen.has(key):
		seen[key] = true
		_cond_dirty = true

## Profil sprzed znaczników (albo nowy): wszystko, co gracz już ma, jest obejrzane — kropki dostaje dopiero to, co przybędzie.
func _seen_baseline_now() -> void:
	if not _seen_baseline:
		return
	_seen_baseline = false
	for id in Perks.ORDER:
		if is_unlocked(String(id)):
			seen["perk:" + String(id)] = true
	for pid in Scrap.parts:
		if Scrap.has_part(String(pid)):
			seen["part:" + String(pid)] = true
	for id in bestiary:
		seen["beast:" + String(id)] = true
	_cond_dirty = true

## Wszystkie wpisy bestiariusza (migracja starych profili, testy).
static func bestiary_ids() -> Array:
	var out: Array = EnemyDefs.DEFS.keys()
	for id in BESTIARY_EXTRA:
		if not out.has(id):
			out.append(id)
	return out

@rpc("authority", "call_remote", "reliable")
func _recv_mission(map_id: String, side_ok: bool, no_downs: bool, boss: bool, night: bool) -> void:
	apply_mission_result(map_id, side_ok, no_downs, boss, night)

# ---------------------------------------------------------------- perki

func is_unlocked(id: String) -> bool:
	return Perks.is_valid(id) and level() >= Perks.unlock_level(id)

func has_perk(id: String) -> bool:
	return equipped.has(id)

## Ustawia wygląd (jeśli poprawny i odblokowany). Zwraca powodzenie.
func set_look(c: int) -> bool:
	if not Look.is_unlocked(c, level()):
		return false
	if c != look:
		look = c
		changed.emit()
		save()
	return true

## Zakłada perk w slocie (0–1): wymaga odblokowanego slotu i perka; ten sam perk nie może siedzieć w dwóch slotach. Zwraca powodzenie.
func equip(slot: int, id: String) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or slot >= slots() or not is_unlocked(id):
		return false
	for i in MAX_SLOTS:
		if equipped[i] == id:
			equipped[i] = ""
	equipped[slot] = id
	changed.emit()
	save()
	return true

func unequip(slot: int) -> void:
	if slot >= 0 and slot < MAX_SLOTS:
		equipped[slot] = ""
		changed.emit()
		save()

# ---------------------------------------------------------------- stan techniczny broni

## Stan broni `key` (0..100 %).
func condition(key: String) -> float:
	return float(cond.get(key, 100.0))

## Zużycie broni `key` o `amount` punktów procentowych (strzały, gorąca lufa, tłumik).
func wear(key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	cond[key] = maxf(0.0, condition(key) - amount)
	_cond_dirty = true

## Stan ostrza broni białej `key` (0..100 %).
func edge_of(key: String) -> float:
	return float(edge.get(key, 100.0))

## Zamach bronią białą `key`: ostrze tępieje o `amount` punktów.
func wear_edge(key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	edge[key] = maxf(0.0, edge_of(key) - amount)
	_cond_dirty = true

## Mnożnik obrażeń od ostrza (1 — ostre, EDGE_MIN — całkiem tępe).
static func edge_mult(e: float) -> float:
	return EDGE_MIN + (1.0 - EDGE_MIN) * clampf(e, 0.0, 100.0) / 100.0

## Ile sekund zajmie ostrzenie `key` na szlifierce (0 — ostre).
func sharpen_time(key: String) -> float:
	var e := edge_of(key)
	return 0.0 if e >= 99.5 else EDGE_STEP * ceilf((100.0 - e) / 10.0)

## Szlifierka: ostrze jak nowe.
func sharpen(key: String) -> void:
	edge.erase(key)
	save()
	changed.emit()

## Zużycie części eksploatacyjnej `part` broni `key` (0..100 %).
func part_wear(key: String, part: String) -> float:
	return float((worn.get(key, {}) as Dictionary).get(part, 0.0))

## Zużycie części `part` broni `key` o `amount` punktów (strzał — weapon_controller._wear_shot).
func wear_part(key: String, part: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var w: Dictionary = (worn.get(key, {}) as Dictionary).duplicate()
	w[part] = minf(100.0, float(w.get(part, 0.0)) + amount)
	worn[key] = w
	_cond_dirty = true

## Czy część `part` broni `key` jest już na tyle zużyta, że stół konserwacji pozwala ją wymienić.
func service_due(key: String, part: String) -> bool:
	return part_wear(key, part) >= SERVICE_DUE

## Nowa część `part` w broni `key` (stół konserwacji, po opłaceniu złomem przez serwer).
func replace_part(key: String, part: String) -> void:
	var w: Dictionary = (worn.get(key, {}) as Dictionary).duplicate()
	w.erase(part)
	if w.is_empty():
		worn.erase(key)
	else:
		worn[key] = w
	save()
	changed.emit()

## Najwyższy stan, do którego da się doczyścić broń `key` — ogranicza go zużycie sprężyn.
func clean_cap(key: String) -> float:
	return clampf(100.0 - SPRINGS_CAP * part_wear(key, "springs"), 0.0, 100.0)

## Zestaw do czyszczenia w misji: stan broni `key` w górę o `amount` punktów (najwyżej do clean_cap).
func restore(key: String, amount: float) -> void:
	cond[key] = minf(maxf(clean_cap(key), condition(key)), condition(key) + amount)
	if cond[key] >= 100.0:
		cond.erase(key)
	_cond_dirty = true
	changed.emit()

## Punkty wprawy z bronią `key`.
func mastery_points(key: String) -> int:
	return int(mastery.get(key, 0))

## Stopień wprawy 0..5.
func mastery_level(key: String) -> int:
	var p := mastery_points(key)
	var lvl := 0
	for i in MASTERY_XP.size():
		if p >= int(MASTERY_XP[i]):
			lvl = i
	return lvl

## Dolicza punkty wprawy; zwraca nowy stopień, gdy właśnie awansował, inaczej −1. Zapis jak stanu broni (co COND_SAVE_EVERY s).
func add_mastery(key: String, n: int) -> int:
	if n <= 0:
		return -1
	var before := mastery_level(key)
	mastery[key] = mastery_points(key) + n
	_cond_dirty = true
	var after := mastery_level(key)
	return after if after > before else -1

## Zabójstwo z broni `key`; `rank` 1 — elita, 2 — boss (nacięcie na kolbie). Zwraca true, gdy przybyło nacięcie.
func add_kill(key: String, rank := 0) -> bool:
	var h: Dictionary = (history.get(key, {}) as Dictionary).duplicate()
	h["k"] = int(h.get("k", 0)) + 1
	if rank == 1:
		h["e"] = int(h.get("e", 0)) + 1
	elif rank >= 2:
		h["b"] = int(h.get("b", 0)) + 1
	history[key] = h
	_cond_dirty = true
	return rank > 0 and notches(key) <= NOTCH_MAX

func kills(key: String) -> int:
	return int((history.get(key, {}) as Dictionary).get("k", 0))

## Nacięcia na kolbie broni `key`: po jednym za elitę i bossa, najwyżej NOTCH_MAX; bossowie liczą się pierwsi (głębokie nacięcia).
func notches(key: String) -> int:
	var h: Dictionary = history.get(key, {}) as Dictionary
	return mini(NOTCH_MAX, int(h.get("e", 0)) + int(h.get("b", 0)))

func boss_notches(key: String) -> int:
	return mini(NOTCH_MAX, int((history.get(key, {}) as Dictionary).get("b", 0)))

## Rekord osobisty na strzelnicy: ćwiczenie `ex` (plates / reload / paper) z bronią `key`; `value` — czas w s albo grupa w MOA (mniej = lepiej).
## Zwraca true, gdy to nowy rekord (zapis od razu).
func range_record(ex: String, key: String, value: float) -> bool:
	var k := "%s:%s" % [ex, key]
	if range_best.has(k) and float(range_best[k]) <= value:
		return false
	range_best[k] = value
	save()
	return true

## Rekord osobisty (−1: brak).
func range_best_of(ex: String, key: String) -> float:
	return float(range_best.get("%s:%s" % [ex, key], -1.0))

## Ile sekund zajmie czyszczenie broni `key` przy ławie (0 — czysta): CLEAN_STEP za każde rozpoczęte 10 % zużycia.
func clean_time(key: String) -> float:
	var c := condition(key)
	var cap := clean_cap(key)
	return 0.0 if c >= cap - 0.5 else CLEAN_STEP * ceilf((cap - c) / 10.0)

## Czyszczenie przy stole konserwacji: stan do clean_cap (nowe sprężyny — broń jak nowa).
func clean(key: String) -> void:
	var cap := clean_cap(key)
	if cap >= 99.5:
		cond.erase(key)
	else:
		cond[key] = maxf(condition(key), cap)
	save()
	changed.emit()

func _process(delta: float) -> void:
	if not _cond_dirty:
		return
	_cond_save_t += delta
	if _cond_save_t >= COND_SAVE_EVERY:
		_cond_save_t = 0.0
		_cond_dirty = false
		save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _cond_dirty:
			_cond_dirty = false
			save()

# ---------------------------------------------------------------- zapis

func save_path() -> String:
	return Characters.file(SAVE_FILE)

func save() -> void:
	if persist:
		save_to(save_path())

## Wybór części w gnieździe broni `key` (montaż prywatny gracza). `id` = "" — element fabryczny.
func set_fit(key: String, slot: String, id: String) -> void:
	var f: Dictionary = (fits.get(key, {}) as Dictionary).duplicate()
	f[slot] = id
	fits[key] = f
	save()
	changed.emit()

## Część zamontowana w gnieździe: jawny wybór gracza; brak wyboru oznacza element fabryczny.
func fitted(key: String, slot: String) -> String:
	var f: Dictionary = fits.get(key, {}) as Dictionary
	if f.has(slot):
		var id := String(f[slot])
		return id if id == "" or Scrap.has_part(id) else ""
	return ""

## Jednorazowo utrwala automatyczny montaż ze starych zapisów. Nowe odblokowania nie zmieniają zestawu.
func migrate_fits() -> void:
	for w in Weapons.COUNT:
		var key := String(Weapons.base_def(w).key)
		var f: Dictionary = (fits.get(key, {}) as Dictionary).duplicate()
		for slot in Parts.slots_of(key):
			if f.has(slot):
				continue
			f[slot] = ""
			for p in Parts.in_slot(key, String(slot)):
				if Scrap.has_part(String(p["id"])):
					f[slot] = String(p["id"])
					break
		fits[key] = f

## Zestaw `i` broni `key` ({} — pusty): {gniazdo: id części | ""}.
func preset(key: String, i: int) -> Dictionary:
	var arr: Array = presets.get(key, []) as Array
	return (arr[i] as Dictionary) if i >= 0 and i < arr.size() and arr[i] is Dictionary else {}

## Zapisuje bieżący montaż broni `key` jako zestaw `i` (każde gniazdo, także fabryczne).
func save_preset(key: String, i: int) -> void:
	if i < 0 or i >= PRESETS:
		return
	var arr: Array = (presets.get(key, []) as Array).duplicate()
	while arr.size() < PRESETS:
		arr.append({})
	var f := {}
	for s in Parts.slots_of(key):
		f[s] = fitted(key, String(s))
	arr[i] = f
	presets[key] = arr
	save()
	changed.emit()

## Montuje zestaw `i` broni `key`. Część, której drużyna już nie ma (np. inny host), zostaje w gnieździe jak była. Zwraca liczbę pominiętych części.
func load_preset(key: String, i: int) -> int:
	var p := preset(key, i)
	if p.is_empty():
		return 0
	var f: Dictionary = (fits.get(key, {}) as Dictionary).duplicate()
	var skipped := 0
	for s in Parts.slots_of(key):
		var id := String(p.get(s, ""))
		if id == "" or Scrap.has_part(id):
			f[s] = id
		else:
			skipped += 1
	fits[key] = f
	save()
	changed.emit()
	return skipped

## Czy montaż broni `key` jest dokładnie zestawem `i`.
func is_preset_fitted(key: String, i: int) -> bool:
	var p := preset(key, i)
	if p.is_empty():
		return false
	for s in Parts.slots_of(key):
		if String(p.get(s, "")) != fitted(key, String(s)):
			return false
	return true

## Kod części (`fit`) broni `w` dla tego gracza — replikowany jako player.fits i wysyłany ze strzałem.
func fit_code(w: int) -> int:
	var key := String(Weapons.def(w).key)
	var choice := {}
	for s in Parts.slots_of(key):
		choice[s] = fitted(key, String(s))
	return Parts.encode(key, choice)

func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("profile", "completed", completed.keys())
	cfg.set_value("profile", "equipped", equipped)
	cfg.set_value("profile", "look", look)
	cfg.set_value("profile", "fits", fits)
	cfg.set_value("profile", "fits_version", 1)
	cfg.set_value("profile", "presets", presets)
	cfg.set_value("profile", "cond", cond)
	cfg.set_value("profile", "worn", worn)
	cfg.set_value("profile", "edge", edge)
	cfg.set_value("profile", "mastery", mastery)
	cfg.set_value("profile", "history", history)
	cfg.set_value("profile", "range_best", range_best)
	cfg.set_value("profile", "bestiary", bestiary)
	if not _seen_baseline:
		cfg.set_value("profile", "seen", seen.keys())
	cfg.save(path)

func load_from(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		if not FileAccess.file_exists(path) and Scrap.legacy_fits:
			migrate_fits()             # postęp sprzed wprowadzenia pliku profilu
			save_to(path)
		return
	xp = maxi(0, int(cfg.get_value("profile", "xp", 0)))
	completed.clear()
	for m in Array(cfg.get_value("profile", "completed", [])):
		completed[String(m)] = true
	var eq := Array(cfg.get_value("profile", "equipped", ["", ""]))
	equipped = ["", ""]
	for i in mini(eq.size(), MAX_SLOTS):
		var id := String(eq[i])
		if Perks.is_valid(id):
			equipped[i] = id
	fits = (cfg.get_value("profile", "fits", {}) as Dictionary).duplicate(true)
	if int(cfg.get_value("profile", "fits_version", 0)) < 1:
		migrate_fits()
		# Zapis wersji od razu: ponowny start nie powtarza migracji po nowych zakupach drużyny.
		cfg.set_value("profile", "fits", fits)
		cfg.set_value("profile", "fits_version", 1)
		cfg.save(path)
	presets = (cfg.get_value("profile", "presets", {}) as Dictionary).duplicate(true)
	edge = {}
	var ed_in := cfg.get_value("profile", "edge", {}) as Dictionary
	for k in ed_in:
		edge[String(k)] = clampf(float(ed_in[k]), 0.0, 100.0)
	worn = {}
	var wn_in := cfg.get_value("profile", "worn", {}) as Dictionary
	for k in wn_in:
		if wn_in[k] is Dictionary:
			var wd := {}
			for pt in wn_in[k]:
				if String(pt) in WEAR_PARTS:
					wd[String(pt)] = clampf(float(wn_in[k][pt]), 0.0, 100.0)
			worn[String(k)] = wd
	cond = {}
	var cd_in := cfg.get_value("profile", "cond", {}) as Dictionary
	for k in cd_in:
		cond[String(k)] = clampf(float(cd_in[k]), 0.0, 100.0)
	mastery = {}
	var ms_in := cfg.get_value("profile", "mastery", {}) as Dictionary
	for k in ms_in:
		mastery[String(k)] = maxi(0, int(ms_in[k]))
	history = {}
	var hi_in := cfg.get_value("profile", "history", {}) as Dictionary
	for k in hi_in:
		if hi_in[k] is Dictionary:
			var hd: Dictionary = hi_in[k]
			history[String(k)] = {"k": maxi(0, int(hd.get("k", 0))), "e": maxi(0, int(hd.get("e", 0))), "b": maxi(0, int(hd.get("b", 0)))}
	range_best = {}
	var rb_in := cfg.get_value("profile", "range_best", {}) as Dictionary
	for k in rb_in:
		if float(rb_in[k]) > 0.0:
			range_best[String(k)] = float(rb_in[k])
	bestiary = {}
	if cfg.has_section_key("profile", "bestiary"):
		var bs_in := cfg.get_value("profile", "bestiary", {}) as Dictionary
		for k in bs_in:
			bestiary[String(k)] = maxi(0, int(bs_in[k]))
	elif xp > 0:
		# profil sprzed bestiariusza z odkrywaniem (< 1.7.407): gracz z postępem widział już kodeks w całości — zostaje mu cały
		for id in bestiary_ids():
			bestiary[String(id)] = 0
	seen = {}
	_seen_baseline = not cfg.has_section_key("profile", "seen")
	for k in Array(cfg.get_value("profile", "seen", [])):
		seen[String(k)] = true
	look = int(cfg.get_value("profile", "look", Look.DEFAULT))
	if not Look.is_unlocked(look, level()):
		look = Look.DEFAULT
	_sanitize_equipped()
	changed.emit()

## Perk założony w slocie, którego poziom nie dosięga (zmiana tabeli / ręczna edycja pliku) wypada.
func _sanitize_equipped() -> void:
	for i in MAX_SLOTS:
		if equipped[i] != "" and (i >= slots() or not is_unlocked(String(equipped[i]))):
			equipped[i] = ""

## Testy: czysty profil.
func reset_for_test() -> void:
	look = Look.DEFAULT
	xp = 0
	completed.clear()
	equipped = ["", ""]
	fits = {}
	presets = {}
	worn = {}
	edge = {}
	cond = {}
	mastery = {}
	history = {}
	range_best = {}
	bestiary = {}
	seen = {}
	_seen_baseline = false
	_cond_dirty = false
	last_mission_xp = 0
	last_mission_rows = []
	run_xp = 0
	last_run_xp = 0
