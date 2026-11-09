extends RefCounted
## Kryjówka „dwa pokłady” (plan układu kryjówki, etap E1: spike pod flagą `--hub2`, w grze pod id z1_hub). 53 × 20 kafli (ściany na krawędziach mapy, jak w z1_hub.gd), dwie kondygnacje
## po 4 kafle światła (5,2 m — wysokość pomieszczeń jak budynki misji) i 1 kafel stropu, jeden pion pośrodku. Kamera trzyma oba pokłady
## w kadrze (CAM_LOCK): przy zbliżeniu NORMAL kadr ma 11,25 kafla, pas stropu do podłogi piwnicy — 11.
## PARTER (wiersz podłogi 9), od lewej w kolejności „co robi drużyna po powrocie”: śluza (dwa punkty startu S, szafki osobiste p) →
## warsztat (stół konserwacji j, ława h) → pion (kol. 21–26) → drzwi strzelnicy FPP (RANGE_DOOR) → zbrojownia (a, gabloty g po cztery
## bronie, a) → radiostacja z prognozą pogody (R i okno) → odprawa (tablica n) w strefie wyjścia (LAUNCH_ZONE).
## PIWNICA (wiersz podłogi 14): kwatery (skrytka H, ściana wyników v) → pracownia elektroniki i próbek (c) z tokarką (d) pod ławą →
## pion → prasa elaboracyjna (x) i stół pirotechniczny (z) pod zbrojownią → maszynownia (generator, sprężarka, drzwi D-7, skrytka H).
## Łańcuchy stanowisk leżą w pionie: badanie (c) → wykonanie (d) → montaż (h) w jednej kolumnie pomieszczeń, amunicja i granaty pod gablotami.
## Pion: krata „=” w podłodze parteru i dwa podesty (wiersze 11 i 12); w dół zeskakuje się przez kratę (S+SPACE).
## Każdy pokład ma jeden wiersz znaczników i jeden wiersz lamp — po zmianie uruchom `--maptest` (z `--hub2` sprawdza tę mapę pod id z1_hub).

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_hub"
const TITLE := "SAFE ROOM"
const OBJECTIVE := "hub"
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99               ## poza mapą: bez „głębi" (ambient, straszaki)
## Broń w gablotach (jak w z1_hub.gd).
const WEAPONS := [Weapons.SPREAD12, Weapons.SRUT8, Weapons.LR7, Weapons.HKM9, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6]
const ACCENTS := []
## Pion między pokładami: [pierwsza, ostatnia] kolumna mapy. Meble z hub_decor.gd go nie zastawiają.
const SHAFTS := [[21, 26]]
## Strefa startu przed drzwiami wyjścia na prawym końcu parteru: [pierwsza kolumna, ostatnia kolumna, wiersz podłogi].
const LAUNCH_ZONE := [46, 51, 9]
## Kamera w pionie: [wiersz stropu parteru, wiersz podłogi piwnicy] — pas, który kamera trzyma w kadrze (player.gd `_lock_camera_band`).
const CAM_LOCK := [4, 14]
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
## Wnęki w tylnej ścianie: w spike'u bez wnęk (E5: kwatery i stałe meble).
const NICHES := []
## Pierwszy plan z przekrojem (`front3d.gd`) i bryły bunkra (`building3d.gd`, typ „vault”): dwie kondygnacje jedna nad drugą; słupy tylko
## na granicach pomieszczeń (klucz "bays": śluza | warsztat | pion | zbrojownia | radiostacja i odprawa), nie co 5 m.
const FRONT := [
	{"set": "bunker", "c0": 0, "c1": 52, "r0": 4, "r1": 9, "shell": true, "build": "vault", "bays": [10, 20, 28, 41]},       # parter
	{"set": "bunker", "c0": 0, "c1": 52, "r0": 9, "r1": 14, "shell": true, "build": "vault", "bays": [10, 20, 28, 41]},      # piwnica
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
	"CbbblbbbbbbbbblbbbbbbbbbbbbblbbbbbblbbbbbbblbbbbblbbC",
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
