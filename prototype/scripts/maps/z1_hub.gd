extends RefCounted
## Kryjówka między misjami kampanii (GDD §10.3): bez wrogów (NoiseMgr.safe_zone), ciepłe światło lamp. 128 × 44 kafli.
## Układ w strefach od lewej, w kolejności „co robi drużyna po powrocie": wejście (dwa punkty startu) → ściana wyników (v) →
## warsztat (h: [E] panel zakupów i ulepszeń za złom) → zbrojownia (sześć stojaków g od startowych po zablokowane: SPREAD-12,
## PELLET-8, LR-7, HKM-9, FALCON-6, SINEW-6; skrzynki z amunicją a na obu końcach) → tablica z odprawą następnej misji (n) →
## strzelnica (linia r i tarcza t 10 m). Bez rekwizytów-skrzyń — pusta podłoga to droga. Ekwipunek i amunicja przechodzą
## z poprzedniej misji i do następnej (main._restart_mission z carry); wyjście na misję po gotowości wszystkich ([Enter]).
## Mapa ma jeden wiersz znaczników i jeden wiersz lamp — po zmianie uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_hub"
const TITLE := "SAFE ROOM"
const OBJECTIVE := "hub"
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99               ## poza mapą: bez „głębi" (ambient, straszaki)
## Broń na stojakach („g") od lewej: drużyna wymienia ekwipunek przed następną misją.
const WEAPONS := [Weapons.SPREAD12, Weapons.SRUT8, Weapons.LR7, Weapons.HKM9, Weapons.SOKOL6, Weapons.CIEGNO6]
const ACCENTS := []
## Radio: kolejne linie pokazuje HUD w pierwszych sekundach pobytu.
const RADIO := ["...the transmitter is still humming. Whatever listens out there heard it too.", "Restock. Swap guns at the racks. Check the board for the next job."]
const RACKS := true                       ## każde „g" dostaje stojak
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
	"########CbbbSbSbbbbbvbbbbbbbbbbhbbbbbbabbbbbbgbbbbbbgbbbbbbgbbbbbbgbbbbbbgbbbbbbgbbbbbbabbbbbbbnbbbbbbrbbbbbbbbbtbbbbbbbC#######",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#######",
	"################################################################################################################################",
	"################################################################################################################################",
	"################################################################################################################################",
]
