extends RefCounted
## Misja 1.1 „Zaginiony Patrol" (GDD §9, Strefa I): znajdź 6 nieśmiertelników zaginionego patrolu → szybem z kopalni i z powrotem przez obudzony las do wyjścia przy starcie.
## Misja wprowadzająca: ruch i strzał, cisza (kucanie), latarka. Dane mapy dla level.gd; legenda znaczników w level.gd. 262 × 48 kafli (od 1.7.536 kopalnia leży pod strażnicą, MAPS_PLAN.md §1.6 L1; od 1.7.280 bez 8 pustych rzędów nieba: zostaje 10 nad najwyższą skałą — zapas kamery przy najmniejszym zoomie).
##
## Cel poboczny: dwie ukryte skrytki (znacznik H): A — półka nad polaną (schodki z podestów co 2 kafle), B — wnęka w stropie jaskini nad półką z Wołkiem.
## Wyjście `E` przy starcie jest od 1.7.283 jedynym wyjściem (MAPS_PLAN.md §1.4 W1; wcześniej „e” przy szybie): po finale drużyna wychodzi szybem
## przy wylocie jaskini i wraca na zachód przez jaskinię, obóz i polanę, a las budzą FINALE_SPAWNS i przechodzący Stalker (także w EXTRACT).
## Bród (od 1.7.284, MAPS_PLAN.md §1.4 W3; kol. 18–37, bez przesuwania mapy): płycizna (woda: wolniej, bieg chlapie i jest głośniejszy), dalej błoto
## (tłumi kroki, grzęźniesz); nad błotem skarpa 4 kafle wyżej, na niej śpi Wołek (na kucaka przejdziesz, wyprostowany go budzisz), obok złom; porada „ford”.
## Układ (od zachodu): start → bród → polana z ogniskiem (nieśmiertelnik 1, cztery Trzoski: strzelasz i słyszysz hałas) →
## obóz patrolu (kol. 77–140, MAPS_PLAN.md M1a; nieśmiertelnik 2): pod zerwanym mostem w niecce śpi wataha (5 Trzosków, przewodnik pod dziurą).
## Most stoi 5 kafli (80 px) nad nimi: na kucaka przejdziesz (budzi 45 px), wyprostowany budzisz (90 px). Dziury (8 kafli) nie da się przeskoczyć —
## cicha droga to konary nad mostem (9 kafli nad watahą) i zeskok na wschodni most z dala od śpiących; głośna — zeskok do niecki i walka,
## z niecki na mosty prowadzą drabinki z podestów. Złom na konarze, amunicja na płaskowyżu za obozem →
## jaskinia pod skalnym sufitem (nieśmiertelnik 3; Trzoski i Wołek śpią na półkach 4 kafle nad ścieżką: chód upright budzi ich
## w promieniu 90 px, kucanie tylko 45 — trzeba się skradać; na środkowej półce, kol. 170, Kapłan, pierwsza elita gry: leczy Trzoski, ogłusza krzykiem, wzywa kolejne.
## Od 1.7.467 tutaj, a nie w obozie: w obozie budził się w 46–57. s pierwszej misji, ELITE_PLACEMENT_PLAN.md) →
## strażnica przed rampą kopalni (kol. 197–240, MAPS_PLAN.md §1.4 W2; nieśmiertelnik 4): wieża z zygzakiem podestów co 2 kafle i włazem w piętrze,
## pod dachem 3 Ćmy i Skoczek, nieśmiertelnik na wschodnim końcu górnego piętra. Lekcja flary: ćmy lecą do każdego światła (latarka, błysk
## strzału), flara rzucona w bok je odciąga, zabija je tylko cios wręcz; skrzynka z flarami przy podejściu, porada „moths” w HINT_ZONES; zejście zeskokiem ze wschodniej krawędzi →
## kopalnia pod strażnicą (od 1.7.536, MAPS_PLAN.md §1.6 L1: blok kopalni odbity lustrzanie, kolumna = 497 − dawna): wejście nawrotem — pomost z desek
## nad wykopem (kol. 244–249) albo zeskok za nim, potem pochylnią pod pomostem na zachód; sala pod wieżą (nieśmiertelnik 5, Wołek i Trzoski
## w ciemności: latarka pomaga, ale budzi; pod sufitem Skoczki i Ćmy; M1c: drugi Wołek tuż pod rampą i Skoczek nad wejściem do sali). Pod salą druga kondygnacja — dolna galeria (szyb serwisowy z podestami, Trzoski na dojściu z szybu do nieśmiertelnika 6, Ćmy i Skoczki; w zachodnim ślepym końcu tylko złom — wrogowie stamtąd przeszli na trasę w M1c). Ostatni nieśmiertelnik zawala rampę — wyjście to szyb na zachodnim końcu sali, pod włazem z desek przy wylocie jaskini (kol. 193–197).
## Sztolnia odwadniająca (od 1.7.537, MAPS_PLAN.md §1.6 L2; wiersze 31–33, podłoga 34): druga droga powrotu z zachodniej ściany sali — pusty otwór `:`
## w kol. 189 (zabity deskami za sobą zatrzymuje pościg, Stalker musi go rozbić; porada „adit”), zalany odcinek z gniazdem ciem (kol. 150–175),
## wnęka z baterią i amunicją (137–141), komora pod niecką obozu (100–125, wiersze 27–33; skrzynia, złom) i lej z podestami co 2 kafle
## do włazu z desek w dnie niecki (kol. 111–114) — wychodzi się pod śpiącą watahą. Od 1.7.538 (L3) sztolnia biegnie dalej na zachód: stary chodnik,
## mijanka ze Skoczkiem, skrzynią i złomem (kol. 76–84, wiersze 29–33, boczny chodnik z lampą), deski `%` w kol. 50 (skrót przez deski na drodze
## ewakuacji, BARRIER_FIX_PLAN B4: rozbić kosztuje hałas) i szyb z podestami do włazu z desek między błotem brodu a polaną (kol. 40–43). Faza B: samouczek ciszy i latarki. Mapa jest generowana programem pomocniczym —
## po zmianach uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_m1"
const TITLE := "1.1  MISSING PATROL"
const OBJECTIVE := "tags"
const RADIO := ["Patrol Seven, do you read? ...we went into the trees. Something is listening.", "Find our tags. Shoot only when you must — noise carries. Crouch and the dark can’t hear you."]
const RACKS := false                      ## true: każde „g" dostaje stojak (zbrojownia)
const AMBIENT := Color(0, 0, 0, 0)         ## kolor ciemności mapy; alfa 0 = domyślny z lights.gd
const BRIEF := "Find the six dog tags of the missing patrol and get out through the mine. Side goal: two hidden stashes off the main route."
const ENEMY_HP := 1.0                     ## mnożnik HP wrogów tej mapy
const UNDERGROUND_ROW := 25
const WEAPONS := []
## Skrzynie mocy (FUN_PLAN.md P1.3): [kolumna, rząd, broń, naboje] — WRATH-4 przed zejściem do kopalni (obok skrzynki amunicji).
const POWER_CRATES := [[231, 22, Weapons.GNIEW4, 8]]
## Sejfy (FUN_PLAN.md P2.2): [kolumna, rząd, złom] — wyważanie trzymanym [E] jest głośne; przy strażnicy, pod ćmami.
const STRONGBOXES := [[206, 22, 40]]
## Akcenty dekoracji 3D [stopy, indeks z view3d.DECO_MODELS]: porzucony obóz patrolu — skrzynia, pniak, wygasłe ognisko przy Trzoskach, powalony pień; w obozie (M1a) ognisko w niecce, pień przed zboczem, skrzynia na płaskowyżu.
const ACCENTS := [[Vector2(392, 368), 12], [Vector2(536, 368), 9], [Vector2(936, 368), 8], [Vector2(2312, 368), 10], [Vector2(424, 368), 21], [Vector2(968, 368), 21], [Vector2(1800, 368), 8], [Vector2(1304, 368), 10], [Vector2(2040, 288), 12]]
## Szósty nieśmiertelnik leży na wschodnim końcu dolnej galerii (za dwoma Trzoskami, obok skrzynki i skrytki) — powód, żeby zejść szybem serwisowym.
## Finał (mission._start_finale): po ostatnim nieśmiertelniku rampa do sali zawala się (obszary [c0, r0, c1, r1]); drogą na zewnątrz jest szyb
## wentylacyjny na zachodnim końcu sali (wspinaczka po podestach, Ćmy i Skoczki pod sufitem sali; na górze właz z desek równo z gruntem —
## od dołu skok przez deski, z góry zeskok, po wierzchu zwykła ścieżka), a wyjściem — „E” przy starcie.
## Przechodzący Stalker (MAPS_PLAN.md M1b, stalker.gd): mapa nie ma znacznika X — Stalker czeka poza mapą („home" = kafel nad nią)
## i wychodzi za plecami drużyny, gdy w fazie celu Uwaga przekroczy `noise`; poluje `time` s, wycofuje się do `leave` s i znika;
## następne przejście po `cooldown` s i dopiero po spadku Uwagi poniżej progu.
## Od 1.7.281: nie wychodzi przed pierwszym nieśmiertelnikiem (`after_goal`), a na HARD dopiero od Uwagi 95 (`noise_hard`, hałas rośnie tam o 25% szybciej).
const STALKER_PASS := {"noise": 80.0, "noise_hard": 95.0, "after_goal": 1, "extract": 1, "time": 28.0, "leave": 8.0, "cooldown": 90.0, "home": [3, 3]}
## Strefy podpowiedzi [c0, r0, c1, r1] (kafle, włącznie; stopy stojącego są na górnej krawędzi rzędu podłogi, więc strefa sięga rzędu 23): „camp" na podejściu do obozu, póki wataha śpi; „moths" pod strażnicą, póki ćmy wiszą pod dachem; „adit" przy otworze sztolni, póki nie jest zabity deskami (hints.gd).
const HINT_ZONES := {"ford": [14, 0, 37, 23], "camp": [80, 0, 97, 23], "moths": [203, 0, 223, 23], "adit": [184, 29, 196, 34]}
## Obudzony las (MAPS_PLAN.md §1.4 W1, od 1.7.283): finał wypuszcza na drogę powrotną śpiące grupy [rodzaj, kolumna, wiersz podłogi] —
## dwa Trzoski w jaskini (pierwszy kontakt po wyjściu szybem), Wołek między jaskinią a obozem, trzy Trzoski na zachodnim skraju polany tuż przed wyjściem,
## dwa w komorze sztolni pod obozem (od 1.7.537: kto wraca pod ziemią, też ma kontakt) i dwa w starym chodniku za mijanką (od 1.7.538).
const FINALE_SPAWNS := [["trzosek", 176, 22], ["trzosek", 180, 22], ["wolek", 145, 22], ["trzosek", 30, 22], ["trzosek", 33, 22], ["trzosek", 36, 22], ["trzosek", 104, 33], ["trzosek", 120, 33], ["trzosek", 66, 33], ["trzosek", 70, 33]]
const COLLAPSE := [[232, 25, 239, 33]]

## Strumień (kosmetyka, `Level3D.build_streams`): bród jest przejściem przez strumień, który wypływa z lasu w głębi i przecina płaszczyznę
## gry — [kolumna od, kolumna do] ciągu wody na płaszczyźnie gry; tam niecka nie ma tylnego brzegu, a las i dno lasu robią miejsce korytu.
const STREAMS := [[18, 26]]

## Tło 3D (`backdrop3d.gd`, kosmetyka): wieża przeciwpożarowa za obozem z tlącym się oknem i daleki maszt radiostacji z 1.2 nad lasem.
const BACKDROP := [{"kind": "tower", "col": 64, "lit": true}, {"kind": "mast", "col": 215}]
## Strefa wydobycia (DESTRUCTION_PLAN.md D5 część 3, od 1.7.505) [c0, r0, c1, r1, materiał, ziarno, udział wtrąceń]: skała z żyłą w zachodniej
## ślepej ścianie dolnej galerii kopalni (za przegrodą z desek i złomem) — z boku drogi, w ciemności, z dala od szybu wyjściowego.
const DIG_ZONES := [[192, 36, 201, 44, "rock", 1101, 0.3]]
## Wnęki w tylnej ścianie kopalni (`niches3d.gd`, `DEPTH_PLAN.md` N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Górna galeria: korytarz techniczny ponad 20 kolumn od gniazd ćm. Dolna galeria: regał bez światła obok lampy misji `I`
## (widać go w jej świetle) i boczna sztolnia przed przegrodą z desek, 14 kolumn od gniazda i z dala od strefy wydobycia.
## Pierwszy plan (`front3d.gd`, `FOREGROUND_PLAN.md` F3): las z podłożem na całej powierzchni (wiersz gruntu 23); bez pni przed jaskinią
## pod skalnym sufitem i przed strażnicą. Nad płytką kopalnią (rampa, sala, szyb wentylacyjny) las i podłoże gasną, kiedy kamera schodzi
## pod powierzchnię (`Front3D.SURF_FADE`).
const FRONT := [
	{"set": "forest", "c0": 2, "c1": 259, "r0": 0, "r1": 23, "skip": [[148, 191], [210, 223]]},
]
const NICHES := [
	{"kind": "corridor", "c0": 227, "c1": 229, "r0": 31, "r1": 33, "lit": "cage"},
	{"kind": "shelf", "c0": 249, "c1": 251, "r0": 41, "r1": 42, "lit": ""},
	{"kind": "drift", "c0": 210, "c1": 212, "r0": 40, "r1": 42, "d": 8.0, "lit": "mine"},
	{"kind": "vent", "c0": 239, "c1": 239, "r0": 27, "r1": 27, "lit": "lamp"},     # N4: kratka pod stropem rampy w dół do kopalni
	{"kind": "window", "c0": 204, "c1": 207, "r0": 40, "r1": 41, "lit": "bulb"},   # N4: okno dyspozytorni na ślepym zachodnim końcu dolnej galerii
	{"kind": "drift", "c0": 117, "c1": 119, "r0": 31, "r1": 33, "d": 8.0, "lit": "mine"},   # L2: boczny chodnik z lampą w komorze sztolni pod obozem
	{"kind": "drift", "c0": 80, "c1": 82, "r0": 31, "r1": 33, "d": 8.0, "lit": "mine"},     # L3: boczny chodnik z lampą w mijance
]

const MAP := [
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##..................................................................................................................................................................................................................................................................##",
	"##................................................................................................................................................................................................................MMMMMMMMMMMMMM....................................##",
	"##.................................................................................................................................................................................................................w..........w.....................................##",
	"##.................................................................................................................................................................................................................w.Z.J.Z...Zw.....................................##",
	"##..................................................................................................................................................############################################...................w.........Fw.....................................##",
	"##..................................................................................................................................................###################################bbbbbbbbb...................M-------MMMM.....................................##",
	"##..................................................................................................................................................###################################bbbbbbbbb...................w..........w.....................................##",
	"##.........................................................................................................u........................................###################################bbbbbbbbb...................w---.......w.....................................##",
	"##..................................................................H..............................----..----.---...................................###################################bbbbbbbbb...................w..........w..........w....w.....................##",
	"##................................................................-----................................w.....w.....................................................................................................w....---...w..........w....w.....................##",
	"##............................................................................................----.....w.....w.--..........................................................................H.......................w..........w..........w....w.....................##",
	"##.............................................................---.....................................w.....w........F.......ya........................................................------.....................w---.......w..........w....w.....................##",
	"##................................W.u........................................................####--------....w...------------####..........................T...........T..A........W...............................w..........w..........w....w.....................##",
	"##.............................------.......................---............................######--.w..w.....w......w....w.--######.....................--------....--------....--------...........................w....---...w..........w....w.....................##",
	"##............................w......w...................................................########...w..w.....w......w....w...########..............................................................................w..........w..........w....w.....................##",
	"##..........................--w......w...................---...........................##########--.w..w.....w......w....w.--##########.........................---.........---.........---........................w---.......w..........w....w.....................##",
	"##....S..S....E...............w......wa.....kk....T....T......F...T...T..u...........############...wT.w.T..Tw......T....T...############....................................................F.........u...f.......w..........w......a...w....w.....................##",
	"##################~~~~~~~~~mmmmmmmmmmm##----###################################################################----##############################################################################-----##############################################------bbbb########",
	"##################~~~~~~~~~#############b---###################################################################b---##############################################################################bb---############################################bbbbbbbbbb##########",
	"########################################bbbb###################################################################bbbb##############################################################################bbbbb##########################################bbbbbbbbbb############",
	"########################################---b###################################################################---b##############################################################################---bb########################################bbbbbbbbbb##############",
	"########################################bbbb########################################################bbbbbbbbbbbbbbbbbbbbbbbbbb###################################################################bbbbb######################################bbbbbbbbbb################",
	"########################################b---########################################################bbbbbbbbbbbb---bbbbbbbbbbb###################################################################bb---####################################bbbbbbbJbb##################",
	"########################################bbbb################################bbbbJbbbb###############bbbbbbbbbbbbbbbbbbbbbbbbbb###################################################################bbbbbbbZbbbbbZbbbbbbJbbbIbbbJbbbbbbbbbbbbbbbbbbbb####################",
	"########################################---b################################bbbbbbbbb###############bbbbbbbbbbb---bbbbbbbbbbbb###########bbbbb########bbbbbbbbbbZbbZbbbbbbbbbbbb#################---bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb######################",
	"########################################bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb########################",
	"########################################b---bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb---bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb---bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb##########################",
	"########################################bbbbbbbubb%bbbbbbbbbbbbbbbbbbbbbbbbbbbkbbbbubbbbbbbbbbbbbbbbbbbubbbbbbbbbbbbbbbbbbkbbbbbbbbbbbbbbbybabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:bbbbbbbbbbbbubFbbbbTbbbWbbTbbbbbbbbTbbbbWbbb############################",
	"########################################################################################################################################################~~~~~~~~~~~~~~~~~~~~~~############################################bbbb########################################",
	"########################################################################################################################################################~~~~~~~~~~~~~~~~~~~~~~############################################---b########################################",
	"##########################################################################################################################################################################################################################bbbb########################################",
	"##########################################################################################################################################################################################################################b---########################################",
	"##########################################################################################################################################################################################################bbJbbb##bbbbbJbbbbbbbbbZbbbb##bbbbZb##bbbbbIbbbb############",
	"##########################################################################################################################################################################################################bbbbbbbbbbbbbbbb---bbbbbbbbbbbbbbbbbbbbbbbbbbbbb#CCCCCCC####",
	"##########################################################################################################################################################################################################bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC####",
	"##########################################################################################################################################################################################################bbbbbbbbbbbbbbbbb---bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC####",
	"##########################################################################################################################################################################################################bubbbb%bbbbbbbbbbbbbbbTbbTbbbbbbTbbbbybFbbabbubbbbabybbC####",
	"###########################################################################################################################################################################################################################################################CCCCCCC####",
	"######################################################################################################################################################################################################################################################################",
	"######################################################################################################################################################################################################################################################################",
	"######################################################################################################################################################################################################################################################################",
	"######################################################################################################################################################################################################################################################################",
]
