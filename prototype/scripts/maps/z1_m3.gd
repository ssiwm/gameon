extends RefCounted
## Misja 1.3 „Gniazdo" (GDD §9, Strefa I): zniszcz gniazda → matka (Żyła) → ekstrakcja.
## Dane mapy dla level.gd; legenda znaczników w level.gd. Rozmiar 192 × 44 kafli.
##
## Układ: las + posterunek → arena z kładkami → Skład (hala z antresolą, dach, schody z rusztowań) →
## tartak z bossem; pod całą mapą biegną podziemia (sale i niskie tunele) połączone trzema szybami.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_m3"
const TITLE := "1.3  THE NEST"
const ENEMY_HP := 1.0                     ## mnożnik HP wrogów tej mapy
const OBJECTIVE := "nests"                ## nests = gniazda + boss; generators = generatory radiostacji
const UNDERGROUND_ROW := 31               ## od tego rzędu postać jest w podziemiach (ambient, straszaki)
## Broń na ziemi („g") w kolejności od lewej (rosnąca moc).
const WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6, Weapons.HKM9, Weapons.GNIEW4]
## Ręczne akcenty dekoracji: [pozycja stóp, indeks z art/props.png] — płot przy starcie, kłody w tartaku.
const ACCENTS := [[Vector2(152, 416), 6], [Vector2(184, 416), 6], [Vector2(1432, 416), 7], [Vector2(2872, 416), 7]]

const MAP := [
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##............................................................................................................................................................................................##",
	"##........................................................................................................................................................................................N...##",
	"##.............................................................................................................................................................w.........w.........w---------.##",
	"##.............................................................................................................................................................w.........w........Tw..........##",
	"##.............................................................................................................................................................w.........w......---------.....##",
	"##.......w...w...........................................................................................................P..MM..T..M...........................w.........wk.T......w..........##",
	"##.......w...w..................................................................................................CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC................w........-------....w..........##",
	"##.......w...w..................................................................................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC................w...g.....w.........w..........##",
	"##.......w...w............................................=========.........................................----CbbbbbbbbbbbbbbbbbJbbbbbbbbbbbC----............w-------..w.........w..........##",
	"##.......w...w....CCCCCCCCCCCCCCCCCCC.............................T...k.........................................CbbbbbbbbbbgbbbbbbbbbbbTbbbbbbC................w.........w.........w..........##",
	"##.......w...w.---bbbbbbbbbbbbbbbbbbC...........=========.....===========...=========....................----....bb=========================bb....----.........w......-------......w..........##",
	"##.......w...w....bbbbbbbbbbbbbbbbbbC............................................................................bbbbbbbbbbbbbbbbbbbbbbbbbbbbb.................w.........w.........w..........##",
	"##.......w..---...bbbbbbbbbbbbbbbbbb........=========...===========...===========......................----......====bbbbbbbbbbbbbbbbbbbbb====......----......-------....w.........w..........##",
	"##.ES..S.w.g.w.kk.bbbbbbobTbTbTbbNbb........a.....L...M..ok.W.a.......X...M.......TaT..................k....kko..bYbbbTbbTbbbbbabbbkbWbbbbbbbb....oP..k........w..a......w.o..W.a.kw...B....E.##",
	"#############mmmmmm###################bbbbbbCCCCCCCCCCOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~C======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC======~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################====bb################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bb====################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbb====CCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbb====CCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbZbbbbbbbbgbbbbbbZbbbb#######bbbbbb################CCCbbbZbZbbbbbbbNbbbbbbbbbbbZbbCCCCbbbbbbCCCCCCCCbbbZbbbbbbbbbbbbbNbbbbbbbbbbbbbZbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbb=========bbbbbbb#######====bb################CCCbbbbbbbbb=========bbbbbbbbbbCCCC====bbCCCCCCCCbbbbbbbbb=================bbbbbbbbbCCCCCCCC====bbCCCCCCCCCCCCCbbbbbbbbb======bCCC##",
	"######bbbbbbbPbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbbbbbbbbbbbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbb=======bbbbbbbbbbbbb=======bbbbbbbbbbbbbb====bbbbbbbbbbbbbbbbb=======bbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbJbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCC##",
	"######bb===bbbbbbMMbbbbbbbbb===bbbbbbb====bbbbbbbbJbbbbbbbbbbbbbb===bbbbbbbMMbbbbbbbb===bbbbbbb====bbbbbJbbbbbb===bbbbbbbbbbMMbbbbbbbbbbbbb===bbbbbbbbbb====bbbbbbbbbbbbbbbbb===MMbbbbbbbbbCCC##",
	"######bbbbbbbbbbbMMTbbbbbbbabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbabbbTbLbbbbMMbbbbbbbWbkbbbbbYbbbbbbbbbbbbbbbbbabbbbbTbbbbbbbMMbbLbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbabbbMMbbbbTbbbbCCC##",
	"####################mmmmmm##################################CCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
]
