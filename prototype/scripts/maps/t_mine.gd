extends RefCounted
## Mapa testowa zawału (D3, nie należy do CAMPAIGN ani SHIFT_POOL): chodnik kopalni z niskim przejściem — tam, gdzie zawał ma sens
## (1.1–1.3 go nie mają, 1.7.494). Hala startu 5 rzędów (S, wyjście E, lampa) → niskie przejście 3 rzędy pod skałą ze stemplem `!`
## i strefą zawału `^` 2 kafle za nim → ślepa komora z amunicją `a` (jedyne wejście przez strefę). Wzór dla przyszłych map w podziemiach:
## strefa w przejściu najwyżej 2–3 rzędy pod skałą lub betonem, stempel ze swoim podciągiem tuż przed nią.
## Używają jej --destructiontest (zawał), --maptest i test_net_session.sh (zawał w sieci), zrzuty: --mission=t_mine --shotwall=Support1.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "t_mine"
const TITLE := "TEST  MINE GALLERY"
const OBJECTIVE := "test"                 ## bez celu misji (mission.gd liczy gniazda: 0)
const RADIO := []
const RACKS := false
const AMBIENT := Color(0, 0, 0, 0)
const BRIEF := ""
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 0
const WEAPONS := []
const ACCENTS := []

const MAP := [
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"###bbbbbbbbblbbbbbbbb###########################",
	"###bbbbbbbbbbbbbbbbbb##########bbbbblbbbb#######",
	"###bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#######",
	"###bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#######",
	"###bbEbbSbSbbbbbbbbbbbbb!b^bbbbbbbbbabbbb#######",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
]
