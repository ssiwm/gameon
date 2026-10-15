extends RefCounted
## Kryjówka między misjami kampanii (GDD §10.3): bez wrogów (NoiseMgr.safe_zone), ciepłe światło lamp. 128 × 44 kafli.
## Układ w strefach od lewej, w kolejności „co robi drużyna po powrocie": wejście (dwa punkty startu) → ściana wyników (v) →
## radiostacja (R: prognoza pogody na następną misję, weather.gd) → warsztat (h: [E] panel zakupów i ulepszeń za złom) → zbrojownia (osiem stojaków g od startowych po zablokowane: SPREAD-12,
## PELLET-8, LR-7, HKM-9, WRATH-4, SPECTER-1, FALCON-6, SINEW-6; skrzynki z amunicją a na obu końcach) → tablica z odprawą następnej misji (n).
## Strzelnicy już nie ma (usunięta w 1.7.196). Bez rekwizytów-skrzyń — pusta podłoga to droga. Ekwipunek i amunicja przechodzą
## z poprzedniej misji i do następnej (main._restart_mission z carry); wyjście na misję po gotowości wszystkich ([Enter]).
## Mapa ma jeden wiersz znaczników i jeden wiersz lamp — po zmianie uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_hub"
const TITLE := "SAFE ROOM"
const OBJECTIVE := "hub"
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99               ## poza mapą: bez „głębi" (ambient, straszaki)
## Broń w gablotach („g": CABINET_SLOTS sztuk na gablotę, od lewej gabloty i od górnego rzędu): drużyna wymienia ekwipunek przed misją.
const WEAPONS := [Weapons.SPREAD12, Weapons.SRUT8, Weapons.LR7, Weapons.HKM9, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6]
## Akcenty dekoracji 3D [stopy, indeks z view3d.DECO_MODELS] za płaszczyzną gry: koksownik przy wejściu, skrzynie wojskowe między zbrojownią a tablicą.
const ACCENTS := [[Vector2(168, 640), 11], [Vector2(968, 640), 12], [Vector2(1208, 640), 12], [Vector2(1144, 640), 17], [Vector2(1176, 640), 20], [Vector2(1192, 640), 20], [Vector2(1448, 640), 19], [Vector2(1688, 640), 18], [Vector2(1720, 640), 20], [Vector2(1848, 640), 17], [Vector2(1880, 640), 20]]
## Radio: kolejne linie pokazuje HUD w pierwszych sekundach pobytu.
const RADIO := ["...the transmitter is still humming. Whatever listens out there heard it too.", "Restock. Swap guns at the armory. Check the board for the next job."]
const RACKS := true                       ## broń z „g" stoi w miejscu (ekspozycja)
const CABINET_SLOTS := 4                  ## każde „g" to gablota na tyle broni (cabinet.gd), zamiast stojaka na jedną
const AMBIENT := Color(0.15, 0.108, 0.075, 1.0)     ## cieplejsza i jaśniejsza ciemność: tu jest bezpiecznie
const BRIEF := ""

const MAP := [
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#######",
	"########CbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbbbblbbbbbbbbblbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbSbSbbbbbvbbbbbRbbbbhbbbbbbbbbbbabbbgbgbbbabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbnbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#######",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
]
