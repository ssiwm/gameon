extends RefCounted
## Kryjówka między misjami kampanii (GDD §10.3, etap 1): bez wrogów (NoiseMgr.safe_zone), ciepłe światło lamp, zbrojownia
## z sześcioma stojakami (SPREAD-12, PELLET-8, LR-7, HKM-9, FALCON-6, SINEW-6 — wymiana broni z podglądem statystyk),
## skrzynki z amunicją i tablica z odprawą następnej misji (podejdź — HUD pokaże cel i zagrożenia). Ekwipunek i amunicja
## przechodzą z poprzedniej misji i do następnej (main._restart_mission z carry). Host rusza dalej [Enter]. 84 × 44 kafli.

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
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#######",
	"########CbbbbblbbbbbbbbbbbbbbblbbbbbbbbbbbbbbblbbbbbbbbbbbbbbblbbbbbbbbblbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#######",
	"########CbbbSbbSbbkkbakbbbbbgbbbbbgbbbbbgbbbbbgbbbbbgbbbbbgbbbbbababbbbnbkbbC#######",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#######",
	"####################################################################################",
	"####################################################################################",
	"####################################################################################",
]
