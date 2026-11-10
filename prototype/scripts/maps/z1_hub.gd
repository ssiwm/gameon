extends RefCounted
## Kryjówka między misjami kampanii (GDD §10.3, `HUB_LAYOUT_PLAN.md`): bez wrogów (NoiseMgr.safe_zone), ciepłe światło lamp. Układ „dwa pokłady”
## (od 1.7.532): 53 × 20 kafli, dwie kondygnacje po 4 kafle światła (5,2 m — wysokość pomieszczeń jak budynki misji) i 1 kafel stropu, jeden pion
## pośrodku. Kamera trzyma oba pokłady w kadrze (CAM_LOCK): przy zbliżeniu NORMAL kadr ma 11,25 kafla, pas stropu do podłogi piwnicy — 11.
## PARTER (wiersz podłogi 9), od lewej w kolejności „co robi drużyna po powrocie”: śluza (dwa punkty startu S, szafki osobiste p: [E] perki
## i wygląd) → warsztat (stół konserwacji j: [E] czyszczenie i części eksploatacyjne; ława h: [E] panel broni, części i zaopatrzenia za złom)
## → pion (kol. 21–26) → drzwi strzelnicy FPP (RANGE_DOOR) → zbrojownia (a, dwie gabloty g po cztery bronie: SPREAD-12, PELLET-8, LR-7,
## HKM-9, WRATH-4, SPECTER-1, FALCON-6, SINEW-6, a) → radiostacja z prognozą pogody (R i okno, weather.gd) → odprawa następnej misji
## (tablica n) w strefie wyjścia (LAUNCH_ZONE).
## PIWNICA (wiersz podłogi 14): kwatery (skrytka H, ściana wyników v) → pracownia elektroniki i próbek (c: [E] badania części broni
## specjalnych) i tokarka ze szlifierką (d: [E] części ze schematów, ostrzenie broni białej) pod ławą → pion → prasa elaboracyjna
## (x: [E] zamówienia amunicji specjalnej) i stół pirotechniczny (z: [E] granaty, miny, ładunki, 40 mm, zapalniki) pod zbrojownią →
## maszynownia (generator, sprężarka, zamknięte drzwi D-7, skrytka H).
## Łańcuchy stanowisk leżą w pionie: badanie (c) → wykonanie (d) → montaż (h) w jednej kolumnie pomieszczeń, amunicja i granaty pod gablotami.
## Pion: krata „=” w podłodze parteru i dwa podesty (wiersze 11 i 12); w dół zeskakuje się przez kratę (S+SPACE).
## Ekwipunek i amunicja przechodzą z poprzedniej misji i do następnej (main._restart_mission z carry); wyjście na misję po gotowości wszystkich ([Enter]).
## Każdy pokład ma jeden wiersz znaczników i jeden wiersz lamp — po zmianie uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_hub"
const TITLE := "SAFE ROOM"
const OBJECTIVE := "hub"
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99               ## poza mapą: bez „głębi" (ambient, straszaki)
## Broń w gablotach („g": CABINET_SLOTS sztuk na gablotę, od lewej gabloty i od górnego rzędu): drużyna wymienia ekwipunek przed misją.
const WEAPONS := [Weapons.SPREAD12, Weapons.SRUT8, Weapons.LR7, Weapons.HKM9, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6]
const ACCENTS := []
## Pion między pokładami: [pierwsza, ostatnia] kolumna mapy. Meble z hub_decor.gd go nie zastawiają.
const SHAFTS := [[21, 26]]
## Strefa startu przed drzwiami wyjścia na prawym końcu parteru: [pierwsza kolumna, ostatnia kolumna, wiersz podłogi].
const LAUNCH_ZONE := [46, 51, 9]
## Kamera w pionie: [wiersz stropu parteru, wiersz podłogi piwnicy] — pas, który kamera trzyma w kadrze (player.gd `_lock_camera_band`).
const CAM_LOCK := [4, 14]
## Oko kamery 3D 3,4 m nad środkiem kadru zamiast 2,2 m z misji (view3d.gd `eye_up_for`): środek pasa wypada na stropie między pokładami,
## więc przy 2,2 m oko stało 1,5 m nad podłogą parteru i ta była tylko kreską; przy 3,4 m czyta się jak pokład (zrzuty E3, przy 4,6 m piwnica się spłaszcza).
const EYE_UP := 3.4
## Rekwizyty bez znaczników (hub_prop.gd): [rodzaj, kolumna mapy, wiersz podłogi, parametry]. Skrzynie prasy 32–48 px na prawo od „x”,
## skrzynia wojskowa 16 px na lewo i beczka 32 px na prawo od „z” (press_bench.gd, pyro_bench.gd); okno z prognozą przy radiostacji.
const HUB_PROPS := [
	["pipes", 10, 14, [20]], ["pipes", 41, 14, [51]],
	["crate", 32, 14, []], ["crate", 33, 14, []], ["mil_crate", 35, 14, []], ["barrel", 38, 14, []], ["scrap_pile", 40, 14, []],
	["generator", 43, 14, []], ["compressor", 46, 14, []], ["d7", 48, 14, []],
	["window", 45, 9, [3]],
]
## Drzwi strzelnicy FPP (range_door.gd): na parterze tuż za pionem, krok od ławy (próba części zaraz po montażu).
const RANGE_DOOR := [29, 9]
## Wnęki w tylnej ścianie (`niches3d.gd`): na razie bez wnęk — wrócą z ręcznie ustawionymi meblami (HUB_LAYOUT_PLAN.md E5).
const NICHES := []
## Pomieszczenia (HUB_LAYOUT_PLAN.md E4): [pierwsza kolumna, ostatnia kolumna, wiersz podłogi, barwa światła] — lampy sufitowe „l” i lampy
## stanowisk w pomieszczeniu świecą jego barwą (level.gd `room_tint`), żeby pokoje różniły się bez czytania tabliczek.
const ROOMS := [
	[1, 9, 9, Color(0.86, 0.88, 0.95)],      # śluza: chłodne, „wejście z zewnątrz”
	[10, 20, 9, Color(1.0, 0.8, 0.52)],      # warsztat: ciepłe żarówki nad ławą
	[21, 26, 9, Color(0.95, 0.9, 0.8)],      # pion
	[27, 40, 9, Color(0.9, 0.93, 1.0)],      # zbrojownia i drzwi strzelnicy: neutralne, broń w gablotach w prawdziwym kolorze
	[41, 51, 9, Color(1.0, 0.66, 0.42)],     # radiostacja i odprawa: bursztyn
	[1, 9, 14, Color(1.0, 0.7, 0.42)],       # kwatery: przygaszone, ciepłe
	[10, 20, 14, Color(0.82, 0.96, 0.9)],    # pracownia i tokarka: zimne, „laboratoryjne”
	[21, 26, 14, Color(0.95, 0.9, 0.8)],     # pion
	[27, 40, 14, Color(1.0, 0.74, 0.46)],    # prasa i pirotechnika
	[41, 51, 14, Color(1.0, 0.56, 0.38)],    # maszynownia: czerwonawe
]
## Tabliczki w świecie (view3d.gd `_build_hub_signs`): [kolumna środka, wiersz podłogi, tekst (klucz ui.csv), strzałka: "" / "down" / "up"].
## Tabliczka stanowiska stoi nad nim na ścianie tylnej; uśpione stanowisko (zużycie wyłączone, pracownia bez próbek, tokarka bez schematu) ma
## ją przygaszoną. Strzałki przy pionie: w dół na parterze, w górę w piwnicy.
const SIGNS := [
	[7, 9, "LOCKER", ""], [12, 9, "MAINTENANCE", ""], [16, 9, "WORKSHOP", ""], [35, 9, "ARMORY", ""], [43, 9, "RADIO", ""],
	[5, 14, "QUARTERS", ""], [12, 14, "LAB", ""], [17, 14, "LATHE", ""], [30, 14, "AMMO PRESS", ""], [36, 14, "PYROTECHNICS", ""],
	[46, 14, "ENGINE ROOM", ""],
	[23, 9, "BASEMENT", "down"], [25, 14, "GROUND FLOOR", "up"],
]
## Pierwszy plan z przekrojem (`front3d.gd`) i bryły bunkra (`building3d.gd`, typ „vault”): dwie kondygnacje jedna nad drugą; słupy tylko
## na granicach pomieszczeń (klucz "bays": śluza | warsztat | pion | zbrojownia | radiostacja i odprawa), nie co 5 m.
const FRONT := [
	{"set": "bunker", "c0": 0, "c1": 52, "r0": 4, "r1": 9, "shell": true, "build": "vault", "bays": [10, 20, 28, 41], "cut_cols": false},       # parter
	{"set": "bunker", "c0": 0, "c1": 52, "r0": 9, "r1": 14, "shell": true, "build": "vault", "bays": [10, 20, 28, 41], "cut_cols": false},      # piwnica
]
const FRONT_SKIP := []                     ## [c0, c1] bez pierwszego planu
## Radio: kolejne linie pokazuje HUD w pierwszych sekundach pobytu.
const RADIO := ["...the transmitter is still humming. Whatever listens out there heard it too.", "Restock. Swap guns at the armory. Check the board for the next job."]
const RACKS := true                       ## broń z „g" stoi w miejscu (ekspozycja)
const CABINET_SLOTS := 4                  ## każde „g" to gablota na tyle broni (cabinet.gd)
const AMBIENT := Color(0.15, 0.108, 0.075, 1.0)     ## cieplejsza i jaśniejsza ciemność: tu jest bezpiecznie
const BRIEF := ""

const MAP := [
	"#####################################################",
	"#####################################################",
	"#####################################################",
	"#####################################################",
	"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
	"CbbblbbbbbbbbblbbbbbbbblbbbbbbbblbbbbbbblbbbbbbblbbbC",
	"CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"CbSbSbbpbbbbjbbbhbbbbbbbbbbbbbbbabgbbgbabbRbbbbbbnbbC",
	"CCCCCCCCCCCCCCCCCCCCC======CCCCCCCCCCCCCCCCCCCCCCCCCC",
	"CbbblbbbbbbbbblbbbblbbbbbbbblbbbbbblbbbbbbblbbbbblbbC",
	"Cbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"Cbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbC",
	"CbHbbbvbbbbbcbbbbdbbbbbbbbbbbbxbbbbbzbbbbbbbbbbbbbbHC",
	"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
	"#####################################################",
	"#####################################################",
	"#####################################################",
	"#####################################################",
	"#####################################################",
]
