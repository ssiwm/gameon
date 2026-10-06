extends RefCounted
## Nocny Dyżur (GDD §11): seria MISSIONS misji pod rząd na tej samej mapie. Każda następna jest twardsza
## (HP wrogów rośnie o HP_STEP na misję) i dostaje losowe modyfikatory (§11 „Modyfikatory"). Wipe kończy serię.
##
## Stan jest statyczny, bo czytają go systemy symulowane na serwerze (hałas, amunicja, Stalker, wrogowie) i HUD
## na każdym peerze. Serwer ustawia go w mission.gd, klienci dostają go przez mission._sync.

const MISSIONS := 5
const HP_STEP := 0.12                 ## +12% HP wrogów i bossa za każdą misję po pierwszej
## Liczba modyfikatorów na misję (indeks = numer misji − 1).
const MODS_PER_MISSION := [0, 1, 1, 2, 2]
const MODS := {
	"overload": {"name": "OVERLOAD", "text": "Attention starts at 50"},
	"famine": {"name": "AMMO FAMINE", "text": "Half the ammo, in crates and from enemies"},
	"leak": {"name": "LEAK", "text": "The stalker wakes at 45 and sleeps at 15"},
	"thin": {"name": "THIN WALLS", "text": "Every noise is 50% louder"},
}

## Wybór hosta w lobby (albo --nightshift); steruje startem sesji.
static var selected := false
static var active := false
static var stage := 1
static var mods: Array = []           ## identyfikatory modyfikatorów bieżącej misji

static func has_mod(id: String) -> bool:
	return active and mods.has(id)

## Losuje modyfikatory dla misji o numerze `n` (1-based). Bez powtórek w obrębie misji.
static func roll(n: int) -> Array:
	var pool: Array = MODS.keys()
	pool.shuffle()
	var count: int = MODS_PER_MISSION[clampi(n - 1, 0, MODS_PER_MISSION.size() - 1)]
	return pool.slice(0, count)

static func reset_state() -> void:
	active = false
	stage = 1
	mods = []

# ---------------------------------------------------------------- mnożniki (czytane przez systemy gry)

static func hp_mult() -> float:
	return 1.0 + HP_STEP * float(stage - 1) if active else 1.0

static func noise_mult() -> float:
	return 1.5 if has_mod("thin") else 1.0

static func ammo_mult() -> float:
	return 0.5 if has_mod("famine") else 1.0

static func start_noise(base: float) -> float:
	return maxf(base, 50.0) if has_mod("overload") else base

## Progi Stalkera/Uwagi (domyślnie 60 / 30; LEAK obniża je do 45 / 15).
static func awake_threshold(base: float) -> float:
	return 45.0 if has_mod("leak") else base

static func sleep_threshold(base: float) -> float:
	return 15.0 if has_mod("leak") else base

# ---------------------------------------------------------------- teksty

static func mod_names() -> String:
	var out: Array = []
	for id in mods:
		out.append(MODS[id]["name"])
	return " · ".join(out)

static func title() -> String:
	return "NIGHT SHIFT  %d / %d" % [stage, MISSIONS]
