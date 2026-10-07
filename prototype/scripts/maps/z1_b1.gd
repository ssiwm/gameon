extends RefCounted
## Misja B1 „Pijawka" (GDD §9, Strefa I — boss): zalana hala z płytkim basenem na całej długości; w wodzie żyje Pijawka (leech.gd).
## Dane mapy dla level.gd; legenda znaczników w level.gd (K = Pijawka, f = skrzynka z flarami). 140 × 44 kafli.
##
## Układ (od zachodu): suchy brzeg ze startem → basen (kolumny POOL, kafle „~") z trzema kładkami nad wodą (rząd 27, metal) i kładkami
## pośrednimi (rząd 29, jednokierunkowe) → suchy brzeg ze strefą ewakuacji. Gracze w wodzie są w zasięgu Pijawki; na kładkach nie.
## Skrzynki z flarami na brzegach i na kładkach B i C. Mapa jest generowana programem pomocniczym — po zmianach uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_b1"
const TITLE := "B1  THE LEECH"
const OBJECTIVE := "boss"
const RADIO := ["...the water moves on its own. Don't wade in the dark.", "Flares show its shadow. Shoot it when it shows."]
const RACKS := false
const AMBIENT := Color(0, 0, 0, 0)
const BRIEF := "Something lives in the flooded hall. Light reveals its shadow under the water — then shoot it. Stay on the catwalks, or keep moving."
const ENEMY_HP := 1.0
const UNDERGROUND_ROW := 99
const WEAPONS := []
const ACCENTS := []
const POOL := [28, 110]                    ## kolumny basenu (od, do włącznie): zakres ruchu Pijawki

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
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbubbbbbbbbbbbbbbbbbbbbbubbbfbbbbbbbbbbbbbbbbbbbbbbbbbfbbubbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbb=================bbbbbbbbb===================bbbbbbbbb=================bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbbbbbbbbbbbbbbbbbbbb-----bbbbbbbbbbbbbbbbbbb-------bbbbbbbbbbbbbbbbbbbbb-------bbbbbbbbbbbbbbbbbbb-----------bbbbbbbbbbbbbbbbbbbbbbbb##",
	"##bbbbSbbSbbbbfbbbabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbKbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbfbabbbEbbbbbbbbbbb##",
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
