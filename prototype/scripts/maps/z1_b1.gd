extends RefCounted
## Misja B1 „Pijawka" (GDD §9, Strefa I — boss): zalana hala z płytkim basenem na całej długości; w wodzie żyje Pijawka (leech.gd).
## Dane mapy dla level.gd; legenda znaczników w level.gd (K = Pijawka, f = skrzynka z flarami, y = bateria, Q = ładowarka latarki). 140 × 44 kafli.
##
## Układ (od zachodu): suchy brzeg ze startem → basen (kolumny POOL, kafle „~") z trzema kładkami nad wodą (rząd 27, metal) i kładkami
## pośrednimi (rząd 29, jednokierunkowe) → suchy brzeg ze strefą ewakuacji. W zasięgu zasadzki Pijawki są gracze w wodzie, na niskich kładkach
## (rząd 29, 32 px) i na brzegu przy basenie; wysokie kładki (rząd 27, 64 px) chronią przed ugryzieniem i falą przypływu (od fazy 2 sięga tam kwas).
## 1.7.69: wschodnia wysoka kładka przedłużona do kolumny 110 (tam, gdzie kończy się basen) — droga w górę przed falą przypływu.
## Skrzynki z flarami na brzegach i na kładkach B i C. Mapa jest generowana programem pomocniczym — po zmianach uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_b1"
const TITLE := "B1  THE LEECH"
const OBJECTIVE := "boss"
const RADIO := ["...the water moves on its own. Don't wade in the dark.", "Flares show its shadow. Shoot it when it shows."]
const RACKS := false
const AMBIENT := Color(0, 0, 0, 0)
const BRIEF := "Something lives in the flooded hall. Light shows its shadow under the water, but it only takes full damage when it surfaces — bait the ambush, then hit it. Watch the tide."
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99
const WEAPONS := []
const ACCENTS := [[Vector2(72, 496), 17], [Vector2(136, 496), 15], [Vector2(200, 496), 20], [Vector2(264, 496), 12], [Vector2(344, 496), 18], [Vector2(392, 496), 20], [Vector2(1816, 496), 20], [Vector2(1864, 496), 17], [Vector2(1928, 496), 19], [Vector2(1992, 496), 15], [Vector2(2056, 496), 20], [Vector2(2104, 496), 12], [Vector2(2152, 496), 17], [Vector2(2024, 496), 21], [Vector2(296, 485), 22]]
const POOL := [28, 110]                    ## kolumny basenu (od, do włącznie): zakres ruchu Pijawki
## Wnęki w tylnej ścianie hali (`niches3d.gd`, `DEPTH_PLAN.md` N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Tylko na suchych brzegach (pod otworem musi być lita podłoga) i poza zasięgiem fali przypływu (basen ± `SURGE_PAD`):
## zachodni brzeg — zaplecze z żarówką między miejscami startu; wschodni — magazyn za kratą i regał bez światła przy ewakuacji.
## N4: dwa wysokie okna dyspozytorni pomp nad basenem (wiersze 24–25), nad lukami między wysokimi kładkami — głowy graczy na kładkach
## nie wchodzą w okno; pod oknami mur tła do kładek.
const NICHES := [
	{"kind": "window", "c0": 50, "c1": 53, "r0": 24, "r1": 25, "lit": "tube"},
	{"kind": "window", "c0": 78, "c1": 81, "r0": 24, "r1": 25, "lit": "bulb"},
	{"kind": "doorway", "c0": 10, "c1": 12, "r0": 28, "r1": 30, "lit": "bulb"},
	{"kind": "grate", "c0": 116, "c1": 118, "r0": 28, "r1": 30, "lit": "bulb"},
	{"kind": "shelf", "c0": 132, "c1": 134, "r0": 29, "r1": 30, "lit": ""},
]

const MAP := [
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"##bbbbbbbbbblbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbblbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbybubbbbbbbbbbbbbbbbbbbbbubybfbbbbbbbbbbbbbbbbbbbbbbbybfbbubbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbb=================bbbbbbbbb===================bbbbbbbbb==========================bbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbb-----bbbbbbbbbbbbbbbbbbb-------bbbbbbbbbbbbbbbbbbbbb-------bbbbbbbbbbbbbbbbbbb-----------bbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbSbbSbbbbfbbbabQbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbKbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbfbabbbEbbbbbbbbbbb##",
	"############################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#############################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
	"############################################################################################################################################",
]
