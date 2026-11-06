extends RefCounted
## Mapa testowa stref wydobycia (DESTRUCTION_PLAN.md D5; nie należy do CAMPAIGN ani SHIFT_POOL): hala 5 rzędów (S, wyjście E, lampy) nad
## litym gruntem z trzema strefami — DigZone1: ziemia bez wtrąceń 10 × 8 kafli pod lewą częścią hali (wierzch równo z podłogą, tu są
## pomiary ruchu ze spike'u S2), DigZone2: skała z żyłą 8 × 6 kafli pod prawą częścią,
## DigZone3: czysty żwir 8 × 6 kafli przy prawej ścianie (osypywanie). Używają jej --digtest, --maptest i
## test_net_session.sh (kopanie w sieci, dołączający, reset).

const Weapons := preload("res://scripts/weapons.gd")

const ID := "t_dig"
const TITLE := "TEST  DIG ZONES"
const OBJECTIVE := "test"                 ## bez celu misji (mission.gd liczy gniazda: 0)
const RADIO := []
const RACKS := false
const AMBIENT := Color(0, 0, 0, 0)
const BRIEF := ""
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 0
const WEAPONS := []
const ACCENTS := []

## [c0, r0, c1, r1, materiał (dig_materials.gd), ziarno, udział wtrąceń (opcjonalnie; domyślnie z tabeli materiałów)] — kafle włącznie.
const DIG_ZONES := [
	[2, 10, 11, 17, "dirt", 7, 0.0],
	[30, 10, 37, 15, "rock", 11, 0.35],
	[39, 10, 46, 15, "gravel", 5, 0.0],
]

const MAP := [
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"#bbbbblbbbbbbbbbbbbbbbbblbbbbbbbbbbbbbbblbbbbbb#",
	"#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
	"#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
	"#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
	"#bbbbbbbbbbbbbbbbbbbEbbSbSbbbbbbbbbbbbbbbbbbbbb#",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
	"################################################",
]
