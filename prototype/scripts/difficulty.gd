extends Node
## Poziom trudności (autoload). Domyślnie NORMAL = dotychczasowa gra (wszystkie mnożniki 1,0).
## Wybiera host (lobby albo --difficulty=easy|normal|hard); main.gd rozsyła wybór
## do klientów. Mnożniki czytają systemy symulowane na serwerze (wrogowie, Stalker,
## Żyła, hałas) oraz gracz (czas wykrwawiania i podnoszenia).

signal changed(level: int)

enum Level { EASY, NORMAL, HARD }

const NAMES := ["EASY", "NORMAL", "HARD"]

## Wiersze w kolejności enum Level. Opis kluczy:
##   enemy_hp / enemy_speed   Trzosek i Wołek
##   enemy_windup / enemy_cd  zapowiedź i przerwa między atakami (mniej = groźniej)
##   enemy_hear               zasięg słyszenia i budzenia wrogów
##   enemy_damage             obrażenia wrogów (zaokrąglane, min. 1)
##   stalker_speed / stalker_windup / stalker_cd   jak wyżej, dla Stalkera
##   boss_hp / boss_cd        HP Żyły oraz mnożnik jej przerw i zapowiedzi
##   noise                    mnożnik dodatniego hałasu (łatwiej / trudniej się zdradzić)
##   drops                    mnożnik szansy na apteczkę i amunicję z wrogów
##   bleed / revive           czas wykrwawiania i podnoszenia kolegi
const TABLE := [
	{
		"enemy_hp": 0.7, "enemy_speed": 0.85, "enemy_windup": 1.3, "enemy_cd": 1.3, "enemy_hear": 0.8,
		"enemy_damage": 0.5, "stalker_speed": 0.85, "stalker_windup": 1.3, "stalker_cd": 1.3,
		"boss_hp": 0.7, "boss_cd": 1.3, "noise": 0.75, "drops": 1.5, "bleed": 1.5, "revive": 0.75,
	},
	{
		"enemy_hp": 1.0, "enemy_speed": 1.0, "enemy_windup": 1.0, "enemy_cd": 1.0, "enemy_hear": 1.0,
		"enemy_damage": 1.0, "stalker_speed": 1.0, "stalker_windup": 1.0, "stalker_cd": 1.0,
		"boss_hp": 1.0, "boss_cd": 1.0, "noise": 1.0, "drops": 1.0, "bleed": 1.0, "revive": 1.0,
	},
	{
		# Stalker 1,05 × 88 = 92 px/s — nadal wolniejszy od gracza (95), jak każe GDD §8.5
		"enemy_hp": 1.35, "enemy_speed": 1.15, "enemy_windup": 0.8, "enemy_cd": 0.8, "enemy_hear": 1.25,
		"enemy_damage": 1.0, "stalker_speed": 1.05, "stalker_windup": 0.85, "stalker_cd": 0.8,
		"boss_hp": 1.4, "boss_cd": 0.8, "noise": 1.25, "drops": 0.7, "bleed": 0.7, "revive": 1.25,
	},
]

var level: int = Level.NORMAL

func set_level(new_level: int) -> void:
	new_level = clampi(new_level, 0, TABLE.size() - 1)
	if new_level == level:
		return
	level = new_level
	changed.emit(level)

## Mnożnik o danym kluczu dla aktualnego poziomu.
func m(key: String) -> float:
	return float(TABLE[level][key])

func level_name() -> String:
	return NAMES[level]

## "easy" / "Hard" / "2" → indeks poziomu; -1 gdy nie rozpoznano.
func parse(text: String) -> int:
	var t := text.strip_edges().to_upper()
	if NAMES.has(t):
		return NAMES.find(t)
	return -1
