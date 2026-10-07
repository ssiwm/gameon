extends RefCounted
## Definicja broni (dane, nie logika) — jedno źródło prawdy dla kontrolera,
## pocisków, HUD-u, audio i testów. Instancje buduje weapons.gd z tabel.
##
## Jednostki: czas w sekundach, odległość w pikselach (1 m = 16 px, lights.gd),
## prędkość w px/s, kąty w stopniach, obrażenia w HP wroga (Trzosek 30, Wołek 140).

enum Kind {
	BULLET,     ## pocisk (jeden lub śrut) — lot z przeciąganiem promienia, przebicie, spadek obrażeń
	BEAM,       ## ciągły promień (hitscan, tyknięcia)
	RAIL,       ## ładowany strzał natychmiastowy, przebija wszystko
	FLAME,      ## ciągły stożek ognia (tyknięcia + podpalenie)
	LAUNCHER,   ## pocisk po łuku z wybuchem obszarowym
	MELEE,      ## cios w łuku
}

enum Slot { PRIMARY, SIDEARM, MELEE }

# --- tożsamość
var id := 0
var key := ""                 ## klucz techniczny (audio, sprite, logi)
var name := ""
var slot := Slot.PRIMARY
var kind := Kind.BULLET

# --- rytm ognia
var auto := false             ## przytrzymanie = ogień ciągły
var cooldown := 0.12          ## s między strzałami / tyknięciami
var draw_time := 0.3          ## s dobycia (po zmianie broni)
var charge_time := 0.0        ## s ładowania (RAIL); puszczenie przed końcem anuluje
# --- tryb serii (klawisz B; tylko broń z burst_size > 0): jedno naciśnięcie = seria, cichsza i celniejsza niż ogień ciągły
var burst_size := 0           ## strzałów w serii (0 = broń bez trybu serii)
var burst_gap := 0.07         ## s między strzałami serii
var burst_rest := 0.28        ## s przerwy po serii
var burst_quiet := 0.8        ## mnożnik hałasu strzału w serii
var burst_heat := 0.6         ## mnożnik rozgrzewania lufy w serii
var burst_bloom := 0.5        ## mnożnik narastania rozrzutu w serii

# --- obrażenia
var damage := 8.0             ## na pocisk / tyknięcie
var pellets := 1
var crit_mult := 1.0          ## mnożnik za trafienie w głowę (górna część sylwetki)
var knock := 0.0              ## odrzut wroga (px/s) na trafienie, mnożony przez knock_mult wroga
var stun := 0.0               ## ogłuszenie wroga (s)
var ignite := 0.0             ## podpalenie (s); wróg płonie i panikuje
var pierce := 0               ## ile DODATKOWYCH wrogów przebija
var wall_pierce := 0.0        ## ile px ściany przebija (RAIL, ulepszenie)
var cluster := 0              ## LAUNCHER (ulepszenie): ile bomb kasetowych rozsypuje się po wybuchu
var execute_frac := 0.0       ## MELEE (ulepszenie): cios dobija wroga poniżej tego ułamka maks. HP

# --- celność
var spread_deg := 0.0         ## rozstaw śrutu (±, rozłożony równo)
var jitter_deg := 1.0         ## losowy rozrzut bazowy (±)
var bloom_per_shot := 0.0     ## o tyle stopni rośnie rozrzut na strzał…
var bloom_max := 0.0          ## …do tego maksimum…
var bloom_decay := 8.0        ## …i wraca z taką prędkością (°/s)
var crouch_accuracy := 0.6    ## mnożnik rozrzutu przy kucaniu

# --- pocisk
var speed := 320.0
var range_px := 224.0         ## maks. zasięg lotu
var falloff_start := 0.0      ## px, od których spada obrażenie…
var falloff_min := 1.0        ## …do tego mnożnika na końcu zasięgu
var gravity := 0.0            ## px/s² (granat)
var homing := 0.0             ## rad/s skrętu w stronę celu (0 = bez naprowadzania)
var homing_cone := 55.0       ## ° od celowania, w których szukamy celu
var homing_range := 200.0
var blast_radius := 0.0       ## px; >0 = wybuch przy trafieniu / po zapalniku
var blast_damage := 0.0       ## obrażenia w środku (spadek do 50% na brzegu)
var fuse := 0.0               ## s do samodetonacji (0 = tylko kontakt)
var sticks := false           ## wbija się (bełt) i zostawia się do podniesienia
var reach := 0.0              ## MELEE: zasięg w px
var arc_deg := 0.0            ## MELEE: połowa łuku

# --- hałas (GDD §8.1): lerp(n_min, n_max, heat); heat rośnie o heat_gain na strzał
var n_min := 0.6
var n_max := 1.5
var heat_gain := 0.1
var heat_decay := 1.2         ## /s
var n_extra := 0.0            ## hałas stały zdarzenia (np. detonacja granatu)

# --- amunicja
var mag := 30                 ## pojemność magazynka
var reserve_start := 120      ## zapas drużyny na starcie misji
var reserve_max := 240
var ammo_per_shot := 1
var pickup_rounds := 24       ## ile daje skrzynka / znaleziona broń
var infinite := false         ## bez zapasu (sidearm) — magazynek się przeładowuje, zapas nie spada
var reload_time := 1.5
var reload_empty_extra := 0.4 ## pusty magazynek przeładowuje się dłużej (nie ma „nabitej” komory)
var reload_per_round := false ## ładowanie nabój po naboju (strzelba) — można przerwać strzałem

# --- czucie (feel)
var shake := 0.7              ## drżenie kamery
var cam_kick := 0.0           ## szarpnięcie kamery przeciwnie do lufy (px)
var kick := 0.0               ## odrzut postaci (px/s)
var recoil := 3.0             ## cofnięcie sprite'a broni (px)
var flash_size := 4.0         ## promień rozbłysku (px)
var flash_light := 1.4        ## energia światła rozbłysku
var flash_color := Color(1.0, 0.82, 0.45)
var tracer_color := Color(1.0, 0.85, 0.35)
var tracer_len := 10.0        ## długość smugi (px)
var casing := 1               ## 0 brak, 1 mała, 2 duża (łuska)
var gun_len := 12.0           ## px od dłoni do wylotu lufy
var gun_row := 0              ## wiersz w art/sprites/guns.png

# --- audio (klucze rodzin z audio_manifest.gd)
var sfx := ""
var sfx_count := 1
var sfx_vol := -7.0
var sfx_pitch := 1.0
var sfx_loop := ""            ## BEAM/FLAME: pętla (klucz) gra, dopóki trwa ogień
var reload_sfx := "reload"
var reload_sfx_count := 3
var sfx_cycle := ""           ## dźwięk po strzale (przeładowanie zamka, pompka)
var sfx_cycle_count := 0

# --- ulepszenia (GDD §6.4) — poziomy kupowane w Kryjówce; tu tylko miejsce na modyfikatory
var tier_notes := ""

## Buduje definicję ze słownika; literówka w kluczu = natychmiastowy błąd,
## nie cicho ignorowane pole (tabele mają ~40 kluczy).
static func make(wid: int, data: Dictionary) -> RefCounted:
	var d: RefCounted = (load("res://scripts/weapon_def.gd") as GDScript).new()
	d.id = wid
	for k in data:
		assert(k in d, "WeaponDef: nieznane pole '%s' (broń %s)" % [k, data.get("key", "?")])
		d.set(k, data[k])
	return d

# --- wielkości pochodne (HUD, balans, testy)

func is_continuous() -> bool:
	return kind == Kind.BEAM or kind == Kind.FLAME

func is_melee() -> bool:
	return kind == Kind.MELEE

func uses_ammo() -> bool:
	return kind != Kind.MELEE

func rpm() -> float:
	return 60.0 / cooldown

## Obrażenia na sekundę przy pełnym trafieniu (bez krytyków, bez spadku).
func dps() -> float:
	if kind == Kind.MELEE:
		return damage / cooldown
	var per_hit := damage * float(pellets)
	if kind == Kind.LAUNCHER:
		per_hit = maxf(per_hit, blast_damage)
	return per_hit / cooldown

func range_m() -> float:
	return (reach if kind == Kind.MELEE else range_px) / 16.0

## Czas jednego pełnego przeładowania pustej broni.
func full_reload_time() -> float:
	if reload_per_round:
		return reload_time * float(mag)
	return reload_time + reload_empty_extra

## Mnożnik obrażeń po przebyciu `dist` px (spadek liniowy od falloff_start do zasięgu).
func falloff(dist: float) -> float:
	if falloff_min >= 1.0 or dist <= falloff_start:
		return 1.0
	var t := clampf((dist - falloff_start) / maxf(range_px - falloff_start, 1.0), 0.0, 1.0)
	return lerpf(1.0, falloff_min, t)

## Hałas jednego strzału dla danego rozgrzania (0–1).
func noise(heat: float) -> float:
	return lerpf(n_min, n_max, clampf(heat, 0.0, 1.0)) + n_extra
