extends RefCounted
## Dane rodzajów zwykłych wrogów w jednym miejscu (ENEMY_PLAN.md F2): statystyki i zmysły, szansa na dropy, XP, złom, głos.
## Dotąd rozsiane po `enemy.gd` (KINDS, SUPPLY_DROP, AMMO_DROP, HEALTH_DROP, VOICES), `profile.gd` (KILL_XP) i `scrap.gd` (DROP) — nowy rodzaj
## dopisuje się tu, a nie w pięciu plikach. Model 3D rodzaju opisuje `enemy3d.gd: SPEC` (osobno: to dane prezentacji).
##
## Pola poza statystykami (opcjonalne, brak = 0):
##   xp      XP za zabójstwo (profile.gd: server_award_kill)
##   scrap   złom z trupa (scrap.gd), z szansą Scrap.DROP_CHANCE
##   supply  szansa na skrzynkę zaopatrzenia (throwables.gd)
##   ammo    szansa na skrzynkę z amunicją do broni, którą ktoś nosi
##   health  szansa na apteczkę (1.5) — tylko mocniejsi wrogowie
##   sweep   amplituda [px] przeszukiwania okolicy śladu po dojściu na miejsce hałasu (Ślepiec); search — czas szukania [s], domyślnie SEARCH_TIME
##   lunge   rzut na głośny dźwięk (Ślepiec): {noise, range, wind, mult, time, cd} — patrz enemy.gd: _maybe_lunge; brak = bez rzutu
##   hear_error  błąd lokalizacji hałasu [px] na granicy zasięgu słyszenia (F3.2; domyślnie enemy.gd HEAR_ERROR = 64): ślepiec słyszy dokładniej, wołek gorzej
##   alert   s reakcji „zauważył cię" (F3.1b): wróg staje, odwraca się i rozżarza oczy, zanim ruszy do ataku; 0 / brak = bez reakcji
##   voice   zdarzenie → [rodzina, liczba wariantów, głośność dB, wysokość]; „attack" gra przy zapowiedzi ciosu, „alert" przy reakcji „zauważył", „death" przy śmierci;
##           rodzaj bez wpisu milczy (Ćma). Skoczek mówi głosem Trzoska (niżej), zdemaskowany Mimik głosem Ślepca (wyżej).

const DEFS := {
	"trzosek": {
		"hp": 30.0, "speed": 88.0, "damage": 1, "windup": 0.28, "reach": 13.0,
		"cooldown": 0.9, "leap": true, "hear": 200.0, "wake_near": 90.0, "sight": 260.0,
		"pack": true, "fears": true, "phototaxis": true, "fire_shy": true,
		"color": Color(0.62, 0.2, 0.22), "size": Vector2(10, 14), "knock": 70.0, "knock_mult": 1.0, "head": 0.0,
		"xp": 2, "scrap": 2, "ammo": 0.22, "alert": 0.4, "voice": {"attack": ["trzosek_attack", 3, -6.0, 1.0], "alert": ["trzosek_attack", 3, -12.0, 1.35], "death": ["trzosek_death", 2, -4.0, 1.0]},
	},
	# Ćma (1.7.5): światłolubna — wisi pod sufitem, budzi ją światło (latarka, flara) i leci na nie.
	# Przy flarze spala się, przy latarce gryzie gracza: rzuć flarę daleko, żeby ją odciągnąć.
	"cma": {
		"hp": 18.0, "speed": 74.0, "damage": 1, "windup": 0.2, "reach": 10.0,
		"cooldown": 1.2, "leap": false, "hear": 0.0, "wake_near": 0.0, "sight": 0.0,
		"fly": true, "moth": true, "phototaxis": true,
		"color": Color(0.74, 0.7, 0.55), "size": Vector2(10, 8), "hurt_h": 18.0, "hurt_w": 16.0, "knock": 40.0, "knock_mult": 1.0, "head": 0.0,
		"xp": 3, "scrap": 4,
	},
	# Skoczek (GDD §7.1): wisi pod sufitem nad przejściem i spada na tego, kto pod nim przejdzie (2 obrażenia).
	"skoczek": {
		"hp": 40.0, "speed": 84.0, "damage": 1, "windup": 0.3, "reach": 13.0,
		"cooldown": 1.0, "leap": true, "hear": 230.0, "wake_near": 60.0, "sight": 280.0,
		"hang": true, "fire_shy": true,
		"color": Color(0.62, 0.6, 0.5), "size": Vector2(12, 14), "hurt_h": 17.0, "knock": 60.0, "knock_mult": 0.9, "head": 0.0,
		"xp": 5, "scrap": 5, "supply": 0.08, "ammo": 0.25, "voice": {"attack": ["trzosek_attack", 3, -5.0, 0.8], "death": ["trzosek_death", 2, -4.0, 0.8]},
	},
	# Mimik (GDD §7.1): udaje kolegę z drużyny — stoi jak człowiek i wzywa pomocy głosem gracza.
	# Zdradzają go: brak serduszek nad głową, brak kroków i oddechu, oczy świecące w ciemności,
	# dziwny numer w etykiecie. Latarka, strzał albo podejście (46 px) go demaskują.
	"mimik": {
		"hp": 70.0, "speed": 95.0, "damage": 2, "windup": 0.4, "reach": 14.0,
		"cooldown": 1.2, "leap": true, "hear": 0.0, "wake_near": 46.0, "sight": 220.0,
		"mimic": true,
		"color": Color(0.6, 0.72, 0.6), "size": Vector2(10, 16), "hurt_h": 22.0, "knock": 50.0, "knock_mult": 0.8, "head": 0.28,
		"xp": 10, "scrap": 10, "supply": 0.4, "ammo": 0.3, "voice": {"attack": ["slepiec_attack", 2, -4.0, 1.2], "death": ["slepiec_death", 2, -3.0, 1.2]},
	},
	# Ślepiec (GDD §7.1): nie widzi, tylko słyszy — idzie do źródła hałasu; kucanie i cisza go mijają.
	"slepiec": {
		"hp": 60.0, "speed": 70.0, "damage": 1, "windup": 0.35, "reach": 14.0,
		"cooldown": 1.1, "leap": false, "hear": 300.0, "wake_near": 36.0, "sight": 26.0,
		"keen": true, "min_noise": 0.25, "blind": true, "fire_shy": true,
		"color": Color(0.8, 0.78, 0.76), "size": Vector2(12, 17), "hurt_h": 27.0, "knock": 40.0, "knock_mult": 0.6, "head": 0.28,
		"xp": 6, "scrap": 5, "supply": 0.1, "ammo": 0.3, "hear_error": 36.0, "sweep": 70.0, "search": 6.0,
		"lunge": {"noise": 1.0, "range": 140.0, "wind": 0.3, "mult": 2.2, "time": 0.7, "cd": 6.0},
		"voice": {"attack": ["slepiec_attack", 2, -4.0, 1.0], "alert": ["slepiec_attack", 2, -9.0, 1.25], "death": ["slepiec_death", 2, -3.0, 1.0]},
	},
	# Podsłuchacz (GDD §7.1): stoi nieruchomo i nasłuchuje; zobaczy albo usłyszy — krzyczy i ściąga hordę.
	"podsluchacz": {
		"hp": 35.0, "speed": 0.0, "damage": 0, "windup": 0.9, "reach": 0.0,
		"cooldown": 6.0, "leap": false, "hear": 170.0, "wake_near": 0.0, "sight": 240.0,
		"color": Color(0.58, 0.5, 0.57), "size": Vector2(12, 24), "hurt_h": 34.0, "knock": 30.0, "knock_mult": 0.5, "head": 0.28,
		"xp": 4, "scrap": 4, "supply": 0.15, "ammo": 0.15, "voice": {"death": ["slepiec_death", 2, -4.0, 1.35]},
	},
	"wolek": {
		"hp": 140.0, "speed": 36.0, "damage": 2, "windup": 0.6, "reach": 20.0,
		"cooldown": 1.6, "leap": false, "hear": 150.0, "wake_near": 70.0, "sight": 200.0,
		"bruiser": true, "armor": 3.0,
		"color": Color(0.36, 0.27, 0.34), "size": Vector2(20, 26), "hurt_h": 32.0, "knock": 14.0, "knock_mult": 0.2, "head": 0.28,
		"xp": 12, "scrap": 6, "supply": 0.35, "ammo": 0.6, "health": 0.75, "hear_error": 96.0, "voice": {"attack": ["wolek_attack", 2, -3.0, 1.0], "death": ["wolek_death", 2, -2.0, 1.0]},
	},
}

## Zawartość dla rodzaju nieznanego (np. gniazdo, boss) — puste zamiast błędu.
static func has(kind: String) -> bool:
	return DEFS.has(kind)

## Szansa 0..1 (lub liczba) z pola `key` rodzaju; 0, gdy rodzaj albo pole nie istnieje.
static func value(kind: String, key: String) -> float:
	return float((DEFS.get(kind, {}) as Dictionary).get(key, 0.0))

## XP za zabójstwo rodzaju (0 = brak wpisu: nie daje XP).
static func xp(kind: String) -> int:
	return int(value(kind, "xp"))

## Głos rodzaju dla zdarzenia: [rodzina, liczba wariantów, głośność dB, wysokość] albo [] (milczy).
static func voice(kind: String, event: String) -> Array:
	var v: Dictionary = (DEFS.get(kind, {}) as Dictionary).get("voice", {})
	return v.get(event, [])
