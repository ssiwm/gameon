extends Node
## Autoload „Profile”: lokalny profil gracza (GDD §10.1 „Wroga wiedza”, §10.2 perki). Każdy człowiek ma własny — XP, poziom i założone perki
## żyją na JEGO komputerze (`user://profile.cfg`), nie w zapisie hosta (złom i ulepszenia są wspólne, perk jest osobisty).
##
## XP (liczone na serwerze, wysyłane do właściciela profilu): zabójstwa (tabela KILL_XP, ostatni trafiający), ukończenie misji (+bonusy: cel
## poboczny, bez upadków, boss, pierwsze ukończenie danej misji), podniesienie kolegi. Nocny Dyżur: połowa. Poziom: próg kolejnego rośnie
## o 150, 250, 350… (L2 = 150 XP, L3 = 400, L4 = 750, L5 = 1200). Sloty perków: 1 od poziomu 2, 2 od poziomu 4. Perki: perks.gd (hooki — faza B3).

const Perks := preload("res://scripts/perks.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Look := preload("res://scripts/look.gd")

signal xp_gained(amount: int, reason: String)
signal leveled_up(level: int)
signal changed

const SAVE_PATH := "user://profile.cfg"
const STEP_BASE := 50                 ## próg poziomu n+1 minus n = STEP_BASE + STEP_PER_LEVEL × n
const STEP_PER_LEVEL := 100
const SLOT_LEVELS := [2, 4]           ## poziom odblokowujący 1. i 2. slot perka
const MAX_SLOTS := 2

## XP za zabójstwo wg rodzaju wroga (enemy.gd KINDS).
const KILL_XP := {"trzosek": 2, "cma": 3, "podsluchacz": 4, "skoczek": 5, "slepiec": 6, "mimik": 10, "wolek": 12}
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
var last_mission_xp := 0                      ## XP z ostatniej misji (karta wyniku)
var last_mission_rows: Array = []             ## [[etykieta, XP], …] z ostatniej misji
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie ruszają prawdziwego profilu

func _ready() -> void:
	if persist:
		load_from(SAVE_PATH)

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
	add_xp(total, "Mission")
	return total

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
	if not NoiseMgr.is_server() or not KILL_XP.has(kind) or _human_by_id(shooter_id) == null:
		return
	var amount := int(KILL_XP[kind])
	if NightShift.active:
		amount = maxi(1, amount / 2)
	if _is_local(shooter_id):
		add_xp(amount, "Kill")
	else:
		_recv_xp.rpc_id(shooter_id, amount, "Kill")

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

# ---------------------------------------------------------------- zapis

func save() -> void:
	if persist:
		save_to(SAVE_PATH)

func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("profile", "completed", completed.keys())
	cfg.set_value("profile", "equipped", equipped)
	cfg.set_value("profile", "look", look)
	cfg.save(path)

func load_from(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
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
	last_mission_xp = 0
	last_mission_rows = []
