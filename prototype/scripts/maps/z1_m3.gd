extends RefCounted
## Misja 1.3 „Gniazdo" (GDD §9, Strefa I): zniszcz gniazda → matka (Żyła) → ekstrakcja.
## Dane mapy dla level.gd; legenda znaczników w level.gd. Rozmiar 192 × 44 kafli.
##
## Układ: las + posterunek → arena z kładkami → Skład (hala z antresolą, dach, schody z rusztowań) →
## hala Żyły z przedsionkiem (od 1.7.552, `VEIN_ARENA`); pod całą mapą biegną podziemia (sale i niskie tunele) połączone trzema szybami.
## Ewakuacja: zachodni skraj (jedyne „E" od 1.7.551 — wschodnie, przy tartaku, nigdy nie było wybierane,
## bo ekstrakcja bierze wyjście najdalsze od drużyny, a ta stoi wtedy przy bossie).
## Cel poboczny (od 1.7.551): dwie skrytki „H" poza główną trasą (szyb 1 w dół, szyb 3 w górę) —
## antresola Składu i ślepa wschodnia sala podziemi pod tartakiem. Wyjście z szybu 3: sucha półka
## (kol. 158–159) zamiast wody, Podsłuchacz cofnięty do wschodniego końca Składu (kol. 140).

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_m3"
const TITLE := "1.3  THE NEST"
const RADIO := []
const RACKS := false                      ## true: każde „g" dostaje stojak (zbrojownia)
const AMBIENT := Color(0, 0, 0, 0)         ## kolor ciemności mapy; alfa 0 = domyślny z lights.gd
const BRIEF := "Destroy every nest, kill The Vein when she wakes, then get the whole squad to the green flare. Side goal: two hidden stashes off the main route."
const ENEMY_HP := 1.0                     ## mnożnik HP wrogów tej mapy
const OBJECTIVE := "nests"                ## nests = gniazda + boss; generators = generatory radiostacji
const UNDERGROUND_ROW := 31               ## od tego rzędu postać jest w podziemiach (ambient, straszaki)
## Broń na ziemi („g") w kolejności od lewej (rosnąca moc).
const WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6, Weapons.HKM9, Weapons.GNIEW4]
## Skrzynia mocy (FUN_PLAN.md P1.3) w składzie saperów nad tunelem za drzwiami zbrojonymi (DESTRUCTION_CONTENT_PLAN.md W2b): SPECTER-1 przed Żyłą.
const POWER_CRATES := [[164, 34, Weapons.WIDMO1, 10]]
## Łup składu saperów (kolumna drzwi → [kolumna, rząd podłogi, rodzaj, …]): złom, granat odłamkowy i część broni wypadająca przy wysadzeniu.
const VAULT_LOOT := {170: [[167, 34, "scrap", 60], [168, 34, "supply", "frag"], [161, 34, "part"]]}
const VAULT_SIGN := {170: "SAPPERS"}
## Zwłoki (MIMIC_PLAN.md M3–M4, corpse.gd): [kolumna, rząd, ułożenie, strój, flagi] — górnicy (`miner`) w osadzie i w chodnikach,
## jeden z patrolu przy wejściu. Przeszukanie trzymanym [E] daje drobny łup (D3).
const CORPSES := [[11, 25, "side", "patrol", {}], [86, 25, "back", "miner", {}], [137, 17, "curl", "miner", {"flip": true, "mimic": true}],
	[52, 39, "back", "miner", {"flip": true, "mimic": true}], [132, 39, "side", "miner", {}], [161, 39, "curl", "miner", {"mimic": true}]]
## Ile gniazd `mimic` z CORPSES zajmuje Mimik-zwłoki (MIMIC_PLAN.md M5, D4): 1, nie 2 — przy 6 ciałach na mapie 2 łamałyby D2 (≥ 4 prawdziwe na jednego).
const MIMIC_CORPSES := 1
## Ręczne akcenty dekoracji: [pozycja stóp, indeks z art/props.png] — kłody w tartaku, regały i beczki w Składzie.
## (8+) Poly Haven: koksownik wartowników przed posterunkiem. Start w lesie bez płotu i zapory (porządek po playteście F3).
const ACCENTS := [[Vector2(1432, 416), 7], [Vector2(248, 416), 11], [Vector2(1864, 416), 15], [Vector2(1928, 416), 20], [Vector2(1960, 416), 16], [Vector2(2024, 416), 19], [Vector2(2072, 416), 15], [Vector2(2120, 416), 20], [Vector2(2184, 416), 16], [Vector2(2216, 416), 15], [Vector2(1880, 353), 15], [Vector2(2008, 353), 20], [Vector2(2056, 353), 16], [Vector2(2136, 353), 15], [Vector2(2200, 353), 20], [Vector2(2088, 416), 21], [Vector2(1896, 405), 22]]

## Tło 3D (`backdrop3d.gd`, kosmetyka): ta sama linia energetyczna co w 1.2 i daleki maszt radiostacji za lasem.
const BACKDROP := [{"kind": "power", "c0": -20, "c1": 215, "z": -82.0}, {"kind": "mast", "col": 30, "z": -170.0, "h": 110.0}]
## Strefy wydobycia (DESTRUCTION_PLAN.md D5 część 3, od 1.7.505; DIG_LOOT_PLAN.md K5 od 1.7.604): głęboka — ziemia za wyłomem we
## wschodniej ścianie ślepej sali podziemi pod tartakiem (ze skrytką, z dala od trasy); krótka — dół zachodniej ściany pierwszej
## podziemnej sali przy starcie (jedna znajdźka, bez budzenia wrogów; bez lampy, bo ćma pod stropem leciałaby do niej).
const DIG_ZONES := [[187, 31, 190, 39, "dirt", 1301, 0.2, {"tape": "m3_dig"}], [2, 36, 5, 39, "dirt", 1302, 0.0, {"wake": false}]]
## Wnęki w tylnej ścianie wnętrz (`niches3d.gd`, `DEPTH_PLAN.md` N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Posterunek: zaplecze z żarówką. Skład: magazyn za kratą na parterze (antresola to kładka `=`, nie podłoga — tam wnęk nie ma).
## Podziemia (niski tunel między salami): sztolnia, regał u dołu środkowego szybu i korytarz techniczny,
## co najmniej 10 kolumn od Ślepców i gniazd ćm i z dala od strefy wydobycia.
## Pomosty pod gołym niebem z historii miejsca (`step3d.gd`, STEPS_PLAN.md S2): plac — ciepłociąg na wspornikach Γ z kładką z desek
## (każdy pomost to pętla kompensacyjna nad drogą, magistrala za placem); przy budynkach — narośl Żyły wylewająca się z okien piętra.
const STEPS := [
	{"kind": "heat", "decks": [[24, 44], [22, 48], [20, 58], [24, 56], [22, 62], [24, 70], [22, 76]]},
	{"kind": "vein", "decks": [[20, 108], [22, 105], [24, 103]]},
	{"kind": "vein", "decks": [[20, 143], [22, 146], [24, 148]]},
]

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
	{"set": "station", "c0": 18, "c1": 36, "r0": 21, "r1": 26, "shell": true, "build": "bunker"},     # posterunek (budynek 3D, `building3d.gd`)
	{"set": "station", "c0": 159, "c1": 170, "r0": 31, "r1": 35, "shell": true, "build": "bunker"},  # skład saperów nad tunelem: drzwi zbrojone, łup (W2b)
	{"set": "station", "c0": 32, "c1": 37, "r0": 26, "r1": 30, "shell": true, "wall": "bunker"},     # piwniczka pod posterunkiem (kratka do szybu); ściana tylna, podłoga i ściana zachodnia z betonu jak posterunek
	{"set": "station", "c0": 112, "c1": 142, "r0": 18, "r1": 26, "shell": true, "build": "hall"},   # Skład (antresola, niecka oleju; budynek 3D: szkielet z cegłą)
	{"set": "tunnel", "c0": 0, "c1": 30, "r0": 30, "r1": 40, "shell": true},       # zachodnia sala podziemi (gniazda) ze ścianą do kopania
	{"set": "tunnel", "c0": 31, "c1": 62, "r0": 35, "r1": 40, "shell": true},      # niski tunel z pierwszym szybem
	{"set": "tunnel", "c0": 63, "c1": 90, "r0": 30, "r1": 40, "shell": true},      # środkowa sala
	{"set": "tunnel", "c0": 91, "c1": 108, "r0": 35, "r1": 40, "shell": true},     # tunel ze środkowym szybem
	{"set": "tunnel", "c0": 109, "c1": 143, "r0": 30, "r1": 40, "shell": true},    # wschodnia sala (niecka oleju)
	{"set": "tunnel", "c0": 144, "c1": 170, "r0": 35, "r1": 40, "shell": true},    # tunel z trzecim szybem
	{"set": "tunnel", "c0": 171, "c1": 191, "r0": 30, "r1": 40, "shell": true},    # ślepa wschodnia sala pod tartakiem z końcową ścianą (skrytka — cel poboczny)
	# las z podłożem (F3) na powierzchni poza przekrojami posterunku i Składu: skraj lasu przy starcie, arena z kładkami, tartak nad stawem
	{"set": "forest", "c0": 2, "c1": 17, "r0": 0, "r1": 26},
	{"set": "forest", "c0": 38, "c1": 111, "r0": 0, "r1": 26, "skip": [[46, 86], [101, 111]]},   # STEPS_PLAN.md S2: bez pni przed pomostami placu i przy budynku (dół korony 6,5–8 m, pomosty do 7,9 m nad placem)
	{"set": "forest", "c0": 143, "c1": 163, "r0": 0, "r1": 26, "skip": [[143, 154]]},
	# hala Żyły (VEIN_PLAN.md §6.1): przekrój, bez lasu przed areną; budynek 3D z blachy na stalowym szkielecie (`building3d.gd` "shed"),
	# ściana wschodnia na skraju mapy (kol. 190), ściana tylna na całej wysokości (wnętrze bez tła `b`), słupy przy ścianie tylnej w osiach
	# słupów `w` hali, bez słupów w płaszczyźnie przekroju (arena bossa — nic nie zasłania kadru)
	{"set": "station", "c0": 164, "c1": 190, "r0": 11, "r1": 26, "shell": true, "build": "shed", "bays": [173.5, 181.5], "cut_cols": false, "closed": true},
]
## Drzwi budynków 3D (DESTRUCTION_CONTENT_PLAN.md W1–W2, decyzje 2–4): kolumna wejścia → materiał; `"start": "broken"` — wyważone na starcie
## (skrzydło leży, ślad poprzedniego patrolu). Na trasie po jednych zamkniętych na budynek, od zachodu (stąd drużyna podchodzi).
## Posterunek: zachód metalowe (kilof), wschód wyważone. Skład: brama drewniana (maczeta), wschodnia wyważona. Hala Żyły: metalowa brama
## w otworze bramy z korzeni (`VEIN_ARENA.gate`); wyważona zostaje wyważona po restarcie walki (punkt kontrolny bossa).
## Bramy na całą wysokość otworu, bez furtki: Rzeźnik (36 px) nie mieści się w otworze 2 rzędów (32 px), W2.
const DOORS := {
	18: {"mat": "metal"}, 36: {"mat": "metal", "start": "broken"},
	112: {"mat": "wood"}, 142: {"mat": "wood", "start": "broken"},
	164: {"mat": "metal"}, 170: {"mat": "steel"},
}
const FRONT_SKIP := []

## Hala Żyły (`VEIN_PLAN.md` §6, od 1.7.552): dane areny bossa zamiast nowych liter mapy. Kafle włącznie.
## `rect` — wnętrze hali [c0, r0, c1, r1]; kamera areny (player.gd) i start walki liczą się od wejścia człowieka do tego prostokąta.
## `view` — kadr kamery areny w px świata [x0, y0, x1, y1]: hala ze ścianami od najwyższej kładki z zapasem na głowy po podłogę z pasem
## pod nią (pasek broni HUD zasłania dół ekranu, a dwa górne rzędy hali są puste); zoom dopasowany do kadru, najwyżej ustawienie gracza.
## `gate` — brama z korzeni [kolumna, r0, r1]: otwór w zachodniej ścianie hali, zamyka się po wejściu drużyny, otwiera w fazie 3 i po śmierci.
## `checkpoint` — stały punkt kontrolny w przedsionku [kolumna, wiersz podłogi]; kolejni gracze stają co 16 px na zachód.
## `entry` — miejsce za bramą [kolumna, wiersz podłogi]: tu bramę przechodzą wciągnięci i tu wstają wykrwawieni, gdy brama jest zamknięta.
## `anchors` — gardziele fazy 1 na podłodze (kolumny), między którymi Żyła przechodzi pod podłogą (E2).
const VEIN_ARENA := {
	"rect": [165, 12, 189, 25],
	"view": [2632, 216, 3048, 456],
	"gate": [164, 23, 25],
	"checkpoint": [162, 25],
	"entry": [167, 25],
	"anchors": [169, 177, 185],
}

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
	"##..................................................................................................................................................................MMMMMMMMMMMMMMMMMMMMMMMMMM##",
	"##.............................................................................................................................................................w....M........w.......w........##",
	"##.............................................................................................................................................................w....M........w.......w........##",
	"##.............................................................................................................................................................w....M........w.......w........##",
	"##.............................................................................................................................................................w....M........w.......w........##",
	"##.............................................................................................................................................................w....M........w.......w........##",
	"##.......................................................................................................................P..MM..T..M...........................w....M........w.......w........##",
	"##..............................................................................................................CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC................w....M------..w.......w...-----##",
	"##..............................................................................................................|bbbbbbbbbbbbbbbbbbbbbbbbbbbbb|................w....M........w.......w........##",
	"##........................................................=========.........................................----|bbbbbbbbbbbbbbbbbJbbbbbbbbbbb|----............w....M........----------.......##",
	"##................CCCCCCCCCCCCCCCCCCC.............................T...k.........................................CbbbbbbbbbbgbbbHbbbbbbbTbbbbbbC................w....M........w.......w........##",
	"##................CbbbbbbbbbbbbbbbbbC...........=========.....===========...=========....................----....bb=========================bb....----.........w....M-------.w.......w.-------##",
	"##................CbbbbbbbbbbbbbbbbbC............................................................................bbbbbbbbbbbbbbbbbbbbbbbbbbbbb.................w.............w.......w........##",
	"##................bbbbbbbbbbbbbbbbbb........=========...===========...===========......................----......====bbbbbbbbbbbbbbbbbbbbb====......----.......w.....---.....w.......w.....---##",
	"##.ESg.S..........bbbbkkobTbTbTbbNbb.u......a.....L...M..ok.W.a....u..X...M.......TaT...u..............k....kko..bYbbbTbbTbbubbabbbkbWbbbbbbPb....o...k........wgay..........w...BN..w........##",
	"##############mmm#CCCCCCCCCCCCCCCCCCCCbbbbbbCCCCCCCCCCOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"###############################CbbbbbCbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"###############################Cbbbbbb======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~C======CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC======CC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"###############################Cbybub+bbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC~~CbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##",
	"###############################CCCCCCC====bb################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCCbbbbbbbbbbbbbbbb#####",
	"######bbbbbbbbbbbbbbbbbbbbbbbbb#######bb====################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbb====CCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbb====CCbbbbbbbbbbCbbbbbbbbbbbbbbbb#####",
	"######bbbbZbbbbbbbbgbbbbbbZbbbb#######bbbbbb################CCCbbbZbZbbbbbbbNbbbbbbbbbbbZbbCCCCbbbbbbCCCCCCCCbbbZbbbbbbbbbbbbbNbbbbbbbbbbbbbZbbbCCCCCCCCbbbbbbCCbbbbbbbbbbbbbbbbbbbbbbbbHbb#####",
	"######bbbbbbbbb=========bbbbbbb#######====bb################CCCbbbbbbbbb=========bbbbbbbbbbCCCC====bbCCCCCCCCbbbbbbbbb=================bbbbbbbbbCCCCCCCC====bbCCbbbbbbbbbbbbobbbbbbb======b#####",
	"######bbbbbbbPbbbbbbbbbbbbbbbbb#######bbbbbb################CCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCbbbbbbCCCCCCCCbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCCCCCCCCbbbbbbCCCCCCCCCCCCC====bbbbbbbbbbbb#####",
	"######bbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbbbbbbbbbbbbb=======bbbbb=======bbbbbbbbbbb====bbbbbbbbbbbb=======bbbbbbbbbbbbb=======bbbbbbbbbbbbbb====bbbbbbbbbbbbbbbbb=======bbbbb#####",
	"######bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbJbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#####",
	"######bb===bbbbbbMMbbbbbbbbb===bbbbbbb====bbbbbbbbJbbbbbbbbbbbbbb===bbbbbbbMMbbbbbbbb===bbbbbbb====bbbbbJbbbbbb===bbbbbbbbbbMMbbbbbbbbbbbbb===bbbbbbbbbb====bbbbbbbbbbbbbbbbb===MMbbbbbbbbb#####",
	"######bbbbbbbbbbbMMTbbbbbbbabbb%ubbbbbbbbbbbbb:bbbbbbbbbbbbubbybabbbTbLbbbbMMbbbbbbbWbkbbbbbYbbbbbbbbbbbbubbybabbbbbTbbbbbbbMMbbLbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbubbbbabbbMMbbbbTbbbb#####",
	"####################mmmmmm##################################CCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCOOOOOOOCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
	"############################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##",
]
