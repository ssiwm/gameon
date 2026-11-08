extends RefCounted
## Kryjówka między misjami kampanii (GDD §10.3): bez wrogów (NoiseMgr.safe_zone), ciepłe światło lamp. 72 × 36 kafli, trzy poziomy co 8 kafli
## (7 kafli światła + 1 kafel stropu), projekt „Stacja Dead Air” (bunkier pod nieczynną stacją radiową).
## ŚRODEK (wiersz podłogi 22), od lewej w kolejności „co robi drużyna po powrocie”: śluza (dwa punkty startu S) → ściana wyników (v) → stół konserwacji (j: [E] czyszczenie i części eksploatacyjne) → warsztat
## (h: [E] panel broni, części i zaopatrzenia za złom) → świetlica (meble z hub_decor.gd, szafki osobiste p: [E] perki i wygląd) → zbrojownia (a, dwie gabloty g po cztery bronie: SPREAD-12, PELLET-8,
## LR-7, HKM-9, WRATH-4, SPECTER-1, FALCON-6, SINEW-6, a) → tablica z odprawą następnej misji (n). Nad tablicą, na GÓRZE (wiersz 14), radiostacja
## z prognozą pogody (R, weather.gd) i pracownią elektroniki i próbek (c: [E] badania części broni specjalnych); pod zbrojownią i warsztatem na DOLE (wiersz 30) maszynownia z tokarką i szlifierką (d: [E] części ze schematów, ostrzenie broni białej) i magazyn ze skrytkami (H) i prasą elaboracyjną (x: [E] zamówienia amunicji specjalnej) i stołem pirotechnicznym (z: [E] granaty, miny, ładunki, 40 mm, zapalniki), a za magazynem
## drzwi strzelnicy FPP z tablicą rekordów (RANGE_DOOR).
## Poziomy łączą dwa szyby (SHAFTS: kraty „=” w podłogach i podesty co 2 kafle, prawy–lewy–prawy jak szyb serwisowy w 1.1); w dół zeskakuje się przez kratę (S+SPACE).
## Ekwipunek i amunicja przechodzą z poprzedniej misji i do następnej (main._restart_mission z carry); wyjście na misję po gotowości wszystkich ([Enter]).
## Każdy poziom ma jeden wiersz znaczników i jeden wiersz lamp — po zmianie uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_hub"
const TITLE := "SAFE ROOM"
const OBJECTIVE := "hub"
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99               ## poza mapą: bez „głębi" (ambient, straszaki)
## Broń w gablotach („g": CABINET_SLOTS sztuk na gablotę, od lewej gabloty i od górnego rzędu): drużyna wymienia ekwipunek przed misją.
const WEAPONS := [Weapons.SPREAD12, Weapons.SRUT8, Weapons.LR7, Weapons.HKM9, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6]
const ACCENTS := []
## Szyby między poziomami: [pierwsza, ostatnia] kolumna mapy. Meble z hub_decor.gd ich nie zastawiają.
const SHAFTS := [[26, 31], [56, 61]]
## Strefa startu przed drzwiami wyjścia: [pierwsza kolumna, ostatnia kolumna, wiersz podłogi]. Kto w niej stoi, jest gotowy (main.gd: _hub_zone_ids).
const LAUNCH_ZONE := [63, 70, 22]
## Rekwizyty bez znaczników (hub_prop.gd, bryły buduje view3d.gd): [rodzaj, kolumna mapy, wiersz podłogi, parametry]. Maszynownia i magazyn na dole (wiersz 30),
## okno z prognozą pogody w radiostacji na górze (wiersz 14; parametr = szerokość w kaflach), rury: parametr = ostatnia kolumna.
const HUB_PROPS := [
	["pipes", 5, 30, [26]], ["generator", 14, 30, []], ["compressor", 21, 30, []], ["barrel", 24, 30, []],
	["crate", 35, 30, []], ["crate", 36, 30, []], ["scrap_pile", 39, 30, []], ["mil_crate", 45, 30, []], ["barrel", 48, 30, []],
	["d7", 66, 30, []], ["window", 68, 14, [3]],
]
## Drzwi strzelnicy FPP (RANGE_FPS_PLAN.md, range_door.gd): [kolumna, wiersz podłogi] w tylnej ścianie magazynu na dole, tablica rekordów
## drużyny na ścianie obok (view3d.gd). [E] przy drzwiach przenosi gracza do tunelu strzelnicy.
const RANGE_DOOR := [54, 30]
## Wnęki w tylnej ścianie (`niches3d.gd`, `DEPTH_PLAN.md` N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Wnęki na podłodze tylko na dole: na górze i w środku tylną ścianę zajmują meble z hub_decor.gd, tablice, gabloty i szyby.
## Rodzaje ścienne (N4) wiszą nad meblami: okna sterowni na górze, kratki w świetlicy i w magazynie — w przęsłach między żebrami
## stropu (`Level3D.interior_ribs`), bo żebro przy otworze znika (`_rib_in_niche`).
## Maszynownia: korytarz techniczny między generatorem a sprężarką (rury biegną nad otworem); magazyn: krata obok drzwi strzelnicy.
const NICHES := [
	{"kind": "corridor", "c0": 16, "c1": 18, "r0": 27, "r1": 29, "lit": "cage"},
	{"kind": "grate", "c0": 49, "c1": 51, "r0": 27, "r1": 29, "lit": "bulb"},
	{"kind": "window", "c0": 38, "c1": 41, "r0": 10, "r1": 11, "lit": "tube"},     # N4: okna sterowni nadajnika wysoko na górze, w przęsłach
	{"kind": "window", "c0": 46, "c1": 49, "r0": 10, "r1": 11, "lit": "bulb"},     #     między żebrami stropu 36–43–52 (z dala od pracowni i radiostacji)
	{"kind": "vent", "c0": 41, "c1": 41, "r0": 16, "r1": 16, "lit": "lamp"},       # N4: kratka wentylacji wysoko w świetlicy (między żebrami 35 i 44)
	{"kind": "vent", "c0": 42, "c1": 42, "r0": 24, "r1": 24, "lit": "lamp"},       # N4: kratka pod stropem magazynu na dole
]
## Pierwszy plan z przekrojem (`front3d.gd`, `FOREGROUND_PLAN.md` F3): rury, kable i lampy na przewodzie 3,5–5 m przed płaszczyzną gry
## na trzech piętrach; strop i podłoga z betonu wysunięte do `Level3D.SHELL_Z`, rury omijają otwory schodów i żebra stropu
## (`Front3D.blocked_x`). Piętra mieszczą się razem w kadrze, więc na całą kryjówkę wypada kilka dużych elementów (`Front3D.layout`).
const FRONT := [
	{"set": "bunker", "c0": 20, "c1": 71, "r0": 6, "r1": 14, "shell": true},       # sterownia nadajnika (góra)
	{"set": "bunker", "c0": 0, "c1": 71, "r0": 14, "r1": 22, "shell": true},       # świetlica i warsztat (środek)
	{"set": "bunker", "c0": 3, "c1": 68, "r0": 22, "r1": 30, "shell": true},       # maszynownia i magazyn (dół)
]
const FRONT_SKIP := []                     ## [c0, c1] bez pierwszego planu
## Radio: kolejne linie pokazuje HUD w pierwszych sekundach pobytu.
const RADIO := ["...the transmitter is still humming. Whatever listens out there heard it too.", "Restock. Swap guns at the armory. Check the board for the next job."]
const RACKS := true                       ## broń z „g" stoi w miejscu (ekspozycja)
const CABINET_SLOTS := 4                  ## każde „g" to gablota na tyle broni (cabinet.gd), zamiast stojaka na jedną
const AMBIENT := Color(0.15, 0.108, 0.075, 1.0)     ## cieplejsza i jaśniejsza ciemność: tu jest bezpiecznie
const BRIEF := ""

const MAP := [
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"####################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
	"####################CbbblbbbbbbbbbbbbbbbblbbbbbbbbbbbbbbbbbbbbbbblbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"####################CbbbbbbbbbbbbbbbbbbbbbbbbcbbbbbbbbbbbbbbbbbbRbbbbbbC",
	"CCCCCCCCCCCCCCCCCCCCCCCCCC======CCCCCCCCCCCCCCCCCCCCCCCC======CCCCCCCCCC",
	"CbbbblbbbbbblbbbbbbblbbbbbbbbbbblbbbbblbbbbbbbbbbblbbbbbbbbbbbbbblbbbbbC",
	"Cbbbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbC",
	"CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"Cbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbC",
	"CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC",
	"Cbbbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbC",
	"CbbbSbSbbbbbvbbbjbbbhbbbbbbbbbbbbbbbbpbbbbbbbbabgbbgbbabbbbbbbbbbnbbbbbC",
	"CCCCCCCCCCCCCCCCCCCCCCCCCC======CCCCCCCCCCCCCCCCCCCCCCCC======CCCCCCCCCC",
	"###CbbbbbbbbbbblbbbbbbbbbbbbbbbbbbbbbbblbbbbbbbbbbbbbbbbbbbbbbbbbbbbC###",
	"###Cbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbC###",
	"###CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC###",
	"###Cbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbC###",
	"###CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC###",
	"###Cbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbbbbbbbbbbbbbbbbbbbbbb===bbbbbbC###",
	"###CbbHbbbbdbbbbbbbbbbbbbbbbbbbbbxbbbbbbbbHbbbzbbbbbbbbbbbbbbbbbbbbbC###",
	"###CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC###",
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"########################################################################",
	"########################################################################",
]
