extends RefCounted
## Misja 1.3 „Gniazdo" (GDD §9, Strefa I): zniszcz gniazda → matka (Żyła) → ekstrakcja.
## Dane mapy dla level.gd; legenda znaczników w level.gd. Rozmiar 192 × 44 kafli.
##
## Układ: las + posterunek → arena z kładkami → Skład (hala z antresolą, dach, schody z rusztowań) →
## tartak z bossem; pod całą mapą biegną podziemia (sale i niskie tunele) połączone trzema szybami.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_m3"
const TITLE := "1.3  THE NEST"
const RADIO := []
const RACKS := false                      ## true: każde „g" dostaje stojak (zbrojownia)
const AMBIENT := Color(0, 0, 0, 0)         ## kolor ciemności mapy; alfa 0 = domyślny z lights.gd
const BRIEF := "Destroy every nest, kill The Vein when she wakes, then get the whole squad to the green flare."
const ENEMY_HP := 1.0                     ## mnożnik HP wrogów tej mapy
const OBJECTIVE := "nests"                ## nests = gniazda + boss; generators = generatory radiostacji
const UNDERGROUND_ROW := 31               ## od tego rzędu postać jest w podziemiach (ambient, straszaki)
## Broń na ziemi („g") w kolejności od lewej (rosnąca moc).
const WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6, Weapons.HKM9, Weapons.GNIEW4]
## Ręczne akcenty dekoracji: [pozycja stóp, indeks z art/props.png] — kłody w tartaku, regały i beczki w Składzie.
## (8+) Poly Haven: koksownik wartowników przed posterunkiem. Start w lesie bez płotu i zapory (porządek po playteście F3).
const ACCENTS := [[Vector2(1432, 416), 7], [Vector2(2872, 416), 7], [Vector2(584, 416), 11], [Vector2(1864, 416), 15], [Vector2(1928, 416), 20], [Vector2(1960, 416), 16], [Vector2(2024, 416), 19], [Vector2(2072, 416), 15], [Vector2(2120, 416), 20], [Vector2(2184, 416), 16], [Vector2(2216, 416), 15], [Vector2(2248, 416), 17], [Vector2(1880, 353), 15], [Vector2(1928, 353), 17], [Vector2(2008, 353), 20], [Vector2(2056, 353), 16], [Vector2(2136, 353), 15], [Vector2(2200, 353), 20], [Vector2(2088, 416), 21], [Vector2(1896, 405), 22]]

## Tło 3D (`backdrop3d.gd`, kosmetyka): ta sama linia energetyczna co w 1.2 i daleki maszt radiostacji za lasem.
const BACKDROP := [{"kind": "power", "c0": -20, "c1": 215, "z": -82.0}, {"kind": "mast", "col": 30, "z": -170.0, "h": 110.0}]
## Strefa wydobycia (DESTRUCTION_PLAN.md D5 część 3, od 1.7.505): ziemia w zachodniej ślepej ścianie pierwszej podziemnej sali —
## z boku drogi, pod lasem przy starcie.
const DIG_ZONES := [[1, 31, 5, 39, "dirt", 1301]]
## Wnęki w tylnej ścianie wnętrz (`niches3d.gd`, `DEPTH_PLAN.md` N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Posterunek: zaplecze z żarówką. Skład: magazyn za kratą na parterze (antresola to kładka `=`, nie podłoga — tam wnęk nie ma).
## Podziemia (niski tunel między salami): sztolnia, regał u dołu środkowego szybu i korytarz techniczny,
## co najmniej 10 kolumn od Ślepców i gniazd ćm i z dala od strefy wydobycia.
const NICHES := [
	{"kind": "doorway", "c0": 19, "c1": 21, "r0": 23, "r1": 25, "lit": "bulb"},
	{"kind": "grate", "c0": 134, "c1": 136, "r0": 23, "r1": 25, "lit": "bulb"},
	{"kind": "drift", "c0": 51, "c1": 53, "r0": 37, "r1": 39, "d": 8.0, "lit": "mine"},
	{"kind": "shelf", "c0": 100, "c1": 102, "r0": 38, "r1": 39, "lit": ""},
	{"kind": "corridor", "c0": 160, "c1": 162, "r0": 37, "r1": 39, "lit": "cage"},
	{"kind": "vent", "c0": 150, "c1": 150, "r0": 36, "r1": 36, "lit": "lamp"},     # N4: kratka pod stropem niskiego tunelu przed trzecim szybem
	{"kind": "window", "c0": 117, "c1": 120, "r0": 19, "r1": 20, "lit": "tube"},   # N4: okno pod stropem piętra Składu, nad antresolą
	{"kind": "window", "c0": 173, "c1": 176, "r0": 32, "r1": 33, "d": 5.0, "lit": "bulb"}, # N4: okno na górnym poziomie wschodniej sali podziemi
	{"kind": "vent", "c0": 32, "c1": 32, "r0": 22, "r1": 22, "lit": "lamp"},       # N4: kratka pod stropem posterunku
	{"kind": "vent", "c0": 36, "c1": 36, "r0": 36, "r1": 36, "lit": "lamp"},       # N4: kratka pod skalnym stropem na zachodnim końcu niskiego tunelu
]

## Pierwszy plan przed płaszczyzną gry (`front3d.gd`, `FOREGROUND_PLAN.md` F3): wszystkie wnętrza z przekrojem (F2b). Posterunek
## i Skład — zestaw stacji (Skład z plamą oleju i beczkami przy niecce w podłodze, `Level3D.oil_spills`); piwniczka pod posterunkiem
## tylko przekrój (za wąska na element). Podziemia osobno dla sal (strop w wierszu 30) i niskich tuneli między nimi (strop w wierszu 35,
## razem z szybami — pod otworem szybu element nie staje): jeden wpis na cały poziom wysunąłby strop sal nad skałą tuneli jak balkon.
const FRONT := [
	{"set": "station", "c0": 18, "c1": 36, "r0": 21, "r1": 26, "shell": true},     # posterunek
	{"set": "station", "c0": 32, "c1": 37, "r0": 26, "r1": 30, "shell": true},     # piwniczka pod posterunkiem (kratka do szybu)
	{"set": "station", "c0": 112, "c1": 142, "r0": 18, "r1": 26, "shell": true},   # Skład (antresola, niecka oleju)
	{"set": "tunnel", "c0": 0, "c1": 30, "r0": 30, "r1": 40, "shell": true},       # zachodnia sala podziemi (gniazda) ze ścianą do kopania
	{"set": "tunnel", "c0": 31, "c1": 62, "r0": 35, "r1": 40, "shell": true},      # niski tunel z pierwszym szybem
	{"set": "tunnel", "c0": 63, "c1": 90, "r0": 30, "r1": 40, "shell": true},      # środkowa sala
	{"set": "tunnel", "c0": 91, "c1": 108, "r0": 35, "r1": 40, "shell": true},     # tunel ze środkowym szybem
	{"set": "tunnel", "c0": 109, "c1": 143, "r0": 30, "r1": 40, "shell": true},    # wschodnia sala (niecka oleju)
	{"set": "tunnel", "c0": 144, "c1": 170, "r0": 35, "r1": 40, "shell": true},    # tunel z trzecim szybem
	{"set": "tunnel", "c0": 171, "c1": 191, "r0": 30, "r1": 40, "shell": true},    # sala ewakuacji z końcową ścianą
	# las z podłożem (F3) na powierzchni poza przekrojami posterunku i Składu: skraj lasu przy starcie, arena z kładkami, tartak nad stawem
	{"set": "forest", "c0": 2, "c1": 17, "r0": 0, "r1": 26},
	{"set": "forest", "c0": 38, "c1": 111, "r0": 0, "r1": 26},
	{"set": "forest", "c0": 143, "c1": 189, "r0": 0, "r1": 26},
]
const FRONT_SKIP := []

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
	"##.......................................................................................................................P..MM..T..M...........................w.........wk.T......w..........##",
	"##..............................................................................................................CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC................w........-------....w..........##",
	"##..............................................................................................................|bbbbbbbbbbbbbbbbbbbbbbbbbbbbb|................w...g.....w.........w..........##",
	"##........................................................=========.........................................----|bbbbbbbbbbbbbbbbbJbbbbbbbbbbb|----............w-------..w.........w..........##",
	"##................CCCCCCCCCCCCCCCCCCC.............................T...k.........................................CbbbbbbbbbbgbbbbbbbbbbbTbbbbbbC................w.........w.........w..........##",
	"##................CbbbbbbbbbbbbbbbbbC...........=========.....===========...=========....................----....bb=========================bb....----.........w......-------......w..........##",
	"##................CbbbbbbbbbbbbbbbbbC............................................................................bbbbbbbbbbbbbbbbbbbbbbbbbbbbb.................w.........w.........w..........##",
	"##................bbbbbbbbbbbbbbbbbb........=========...===========...===========......................----......====bbbbbbbbbbbbbbbbbbbbb====......----......-------....w.........w..........##",
	"##.ESg.S..........bbbbkkobTbTbTbbNbb.u......a.....L...M..ok.W.a....u..X...M.......TaT...u..............k....kko..bYbbbTbbTbbubbabbbkbWbbbbbbbb....oP..k........w..a......w.o..W.aykw...B....E.##",
	"##############mmm#CCCCCCCCCCCCCCCCCCCCbbbbbbCCCCCCCCCCOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"################################bbbbbCbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"################################bbbbbb======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~C======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC======~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"################################bybub+bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbb~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"######################################====bb################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bb====################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbb====CCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbb====CCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbZbbbbbbbbgbbbbbbZbbbb#######bbbbbb################CCCbbbZbZbbbbbbbNbbbbbbbbbbbZbbCCCCbbbbbbCCCCCCCCbbbZbbbbbbbbbbbbbNbbbbbbbbbbbbbZbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbbbbbbb=========bbbbbbb#######====bb################CCCbbbbbbbbb=========bbbbbbbbbbCCCC====bbCCCCCCCCbbbbbbbbb=================bbbbbbbbbCCCCCCCC====bbCCCCCCCCCCCCCbbbbbbbbb======bCCC##",
	"######bbbbbbbPbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbbCCC##",
	"######bbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbbbbbbbbbbbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbb=======bbbbbbbbbbbbb=======bbbbbbbbbbbbbb====bbbbbbbbbbbbbbbbb=======bbbbbCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbJbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCC##",
	"######bb===bbbbbbMMbbbbbbbbb===bbbbbbb====bbbbbbbbJbbbbbbbbbbbbbb===bbbbbbbMMbbbbbbbb===bbbbbbb====bbbbbJbbbbbb===bbbbbbbbbbMMbbbbbbbbbbbbb===bbbbbbbbbb====bbbbbbbbbbbbbbbbb===MMbbbbbbbbbCCC##",
	"######bbbbbbbbbbbMMTbbbbbbbabbb%ubbbbbbbbbbbbb:bbbbbbbbbbbbubbybabbbTbLbbbbMMbbbbbbbWbkbbbbbYbbbbbbbbbbbbubbybabbbbbTbbbbbbbMMbbLbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbubbbbabbbMMbbbbTbbbbCCC##",
	"####################mmmmmm##################################CCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
]
