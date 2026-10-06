extends Node
## Autoload „Scrap": złom — waluta drużyny (GDD §10.1). Portfel jest WSPÓLNY, autorytet ma serwer, klienci dostają stan przez sync.
##
## Dwa stany: `loot` to złom zebrany w TEJ misji (jeszcze nie bezpieczny) i `bank` — portfel, z którego płaci się w warsztacie.
## Udana ekstrakcja przenosi loot do banku (`bank_loot`); wipe albo restart misji kasuje loot (GDD §4: „tracicie łup misji") —
## bank zostaje. Bank zapisuje się u hosta w user://progress.cfg i wraca przy starcie hostowania. Nocny Dyżur nie daje złomu.
##
## Źródła: wrogowie (enemy.gd, szansa), skrytki na mapie (znacznik „u", pickup „scrap"), bonus za misję (mission.gd).

signal changed

const NightShift := preload("res://scripts/night_shift.gd")

const SAVE_PATH := "user://progress.cfg"

## Stałe balansu w jednym miejscu — do strojenia po playtestach.
const DROP_CHANCE := 0.35
const DROP := {"trzosek": 2, "wolek": 6, "slepiec": 5, "podsluchacz": 4, "mimik": 10, "skoczek": 5, "cma": 4}
const CACHE_VALUE := 6               ## skrytka z mapy
const BOSS_VALUE := 30
const BONUS_CLEAR := 30               ## za ukończenie misji
const BONUS_SIDE := 15                ## za cel poboczny
const BONUS_NO_DOWNS := 10            ## za misję bez upadków

var bank := 0
var loot := 0
var last_gain := 0                    ## ile trafiło do banku po ostatniej misji (karta wyniku, ściana wyników)
var persist := DisplayServer.get_name() != "headless"      ## testy headless nie czytają ani nie nadpisują prawdziwego zapisu

func _ready() -> void:
	load_progress()
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if NoiseMgr.is_server():
			_sync.rpc_id(id, bank, loot, last_gain))

## Złom nie obowiązuje w Nocnym Dyżurze (osobna seria z własnymi zasadami).
func enabled() -> bool:
	return not NightShift.active

# ---------------------------------------------------------------- serwer

## Zebrany złom wpada do łupu misji.
func add_loot(n: int) -> void:
	if not NoiseMgr.is_server() or n <= 0 or not enabled():
		return
	loot += n
	_push()

## Ekstrakcja udana: łup + bonusy do banku, zapis na dysk. Zwraca ile weszło.
func bank_loot(bonus: int) -> int:
	if not NoiseMgr.is_server() or not enabled():
		return 0
	var gain := loot + maxi(0, bonus)
	bank += gain
	last_gain = gain
	loot = 0
	save_progress()
	_push()
	return gain

## Wipe / restart: łup przepada, bank zostaje.
func reset_loot() -> void:
	if not NoiseMgr.is_server():
		return
	if loot != 0:
		loot = 0
		_push()

## Wydatek z banku (warsztat, faza B). false = za mało.
func spend(n: int) -> bool:
	if not NoiseMgr.is_server() or n < 0 or bank < n:
		return false
	bank -= n
	save_progress()
	_push()
	return true

func _push() -> void:
	changed.emit()
	if NoiseMgr.has_network() and NoiseMgr.is_server():
		_sync.rpc(bank, loot, last_gain)

@rpc("authority", "call_remote", "reliable")
func _sync(b: int, l: int, g: int) -> void:
	bank = b
	loot = l
	last_gain = g
	changed.emit()

# ---------------------------------------------------------------- zapis (host)

func load_progress() -> void:
	var cfg := ConfigFile.new()
	bank = int(cfg.get_value("scrap", "bank", 0)) if persist and cfg.load(SAVE_PATH) == OK else 0
	loot = 0
	last_gain = 0
	changed.emit()

func save_progress() -> void:
	if not persist or not NoiseMgr.is_server():
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("scrap", "bank", bank)
	cfg.save(SAVE_PATH)
