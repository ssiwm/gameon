extends RefCounted
## Misja 1.2 „Przerwa w Nadawaniu" (GDD §9, Strefa I): uruchom 4 generatory radiostacji rozrzucone po całej mapie →
## nadajnik rozbrzmiewa na cały las (skok Uwagi, Stalker idzie na źródło) → ekstrakcja z powrotem na początek.
## Cel poboczny: Uwaga poniżej 40 do ostatniego generatora. Dane mapy dla level.gd; legenda znaczników w level.gd.
## Rozmiar 288 × 56 kafli (v2: dłuższa i trudniejsza niż pierwsza wersja 168 × 44; v3: głęboki tunel drezyny; 4 dolne wiersze to litej skały — zapas dla kamery, żeby drezyna nie chowała się pod HUD).
##
## Układ (od zachodu): skraj lasu ze startem → dziedziniec z watahą i Wołkiem → chata radiowa (generator 1, dwa Ślepce,
## antresola z kuszą, rusztowanie na dach) → bagno z szopą (Skoczki, Ćma, Mimik na rozstaju) → wieża widokowa nad
## podziemną halą (generator 2, Wołek, Ślepiec, dom Stalkera, dwa szyby) → pompownia o dwóch kondygnacjach
## (generator 3 na piętrze, Rzeźnik i dwie beczki na parterze — ELITE_PLACEMENT_PLAN.md E2) → maszt z pomostem (generator 4). Po nadawaniu: szyb przy maszcie →
## głęboki tunel (wiersze 44-51) → DREZYNA (znacznik D) jedzie torem na zachód do wyjścia E (pompuj [E] na pokładzie).
## Układ „Drabina” (MAPS_PLAN.md §4, D1 od 1.7.543): cicha droga pod dziedzińcem — właz z desek `-` przed watahą (kol. 39–42), niski przepust
## (wiersze 28–29, 64 px pod watahą: tylko na kucaka, bo `wake_near` liczy odległość przez ziemię; porada „culvert”) i studnia stacji z podestami
## (kol. 60–65) wychodząca włazem przy drzwiach hali. Z dna studni deski `%` (66, 38) na podest nad komorą tunelu (kol. 67–70) i stopnie do toru.
## Po nadawaniu podest zasypuje się (`COLLAPSE`, mission._start_broadcast_collapse): do wyjścia prowadzi już tylko tor, drezyna zostaje finałem.
## D2 (od 1.7.544): w podłodze magazynu hali za kratką `+` metalowy właz `=` (kol. 215–216, w. 40) i stopnie (w. 42–49) do toru przy kol. 206 — nie zasypuje się.
## Mapa jest generowana programem pomocniczym (zejścia: `tools/m2_ladder.py`) — po zmianach uruchom `--maptest`.

const Weapons := preload("res://scripts/weapons.gd")

const ID := "z1_m2"
const TITLE := "1.2  RADIO SILENCE"
const OBJECTIVE := "generators"
const RADIO := []
const RACKS := false                      ## true: każde „g" dostaje stojak (zbrojownia)
const AMBIENT := Color(0, 0, 0, 0)         ## kolor ciemności mapy; alfa 0 = domyślny z lights.gd
const BRIEF := "Start all four radio generators spread across the map, then escape through the deep tunnel on the handcar. Bonus: keep Attention under 40 until the last one."
const ENEMY_HP := 1.25                    ## mnożnik HP wrogów tej mapy (dłuższa i trudniejsza misja)
const UNDERGROUND_ROW := 30
## Porady w miejscu (hints.gd): przepust przed watahą na dziedzińcu.
const HINT_ZONES := {"culvert": [28, 0, 43, 29]}
## Zawał przy nadawaniu (MAPS_PLAN.md §4): podest między studnią stacji a tunelem drezyny — po nadawaniu do wyjścia tylko torem.
const COLLAPSE := [[67, 36, 70, 40]]
## Broń na ziemi („g") od lewej: strzelba na dziedzińcu, kusza (cicha — pasuje do celu pobocznego) na antresoli chaty. Kilof przy wieży zniknął w 1.7.495
## (B1: ma go każdy) — zamurowane przejście „q" w lewej ścianie podziemnej hali (skrytka ze złomem i amunicją; wejście 3 kafle, wiersze 37-39) bierze każdy.
const WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6]
## Skrzynie mocy (FUN_PLAN.md P1.3): [kolumna, rząd, broń, naboje] — FALCON-6 w podziemnym korytarzu (obok skrzynki amunicji).
const POWER_CRATES := [[149, 39, Weapons.SOKOL6, 60]]
## Sejfy (FUN_PLAN.md P2.2): [kolumna, rząd, złom] — wyważanie trzymanym [E] jest głośne; tuż obok Podsłuchacza przy generatorze.
## Kolumna 103, nie 100: w kolumnie 100 stoi słup budynku stacji, który w widoku 3D zasłaniał skrzynię (skrytka „u” jest w kolumnie 101).
const STRONGBOXES := [[103, 25, 40]]
## (8+) Poly Haven: koksownik przy kłodach za chatą radiową, opona w bagnie, pniak za bagnem.
const ACCENTS := [[Vector2(584, 416), 7], [Vector2(2000, 416), 7], [Vector2(3500, 416), 7], [Vector2(696, 416), 11], [Vector2(808, 416), 13], [Vector2(920, 416), 9], [Vector2(3592, 416), 17], [Vector2(3624, 416), 15], [Vector2(3704, 416), 18], [Vector2(3752, 416), 17], [Vector2(3816, 416), 20], [Vector2(3864, 416), 19], [Vector2(3928, 416), 17], [Vector2(3624, 353), 17], [Vector2(3656, 353), 15], [Vector2(3704, 353), 20], [Vector2(3816, 353), 17], [Vector2(3848, 353), 18], [Vector2(3928, 353), 15], [Vector2(3896, 416), 21], [Vector2(3832, 405), 22]]

## Tło 3D (`backdrop3d.gd`, kosmetyka): maszty stacji nad wschodnią częścią mapy i linia energetyczna, która ją zasila.
const BACKDROP := [{"kind": "power", "c0": -20, "c1": 300, "z": -78.0}, {"kind": "mast", "col": 248, "z": -100.0, "h": 85.0}, {"kind": "mast", "col": 214, "z": -150.0}]
## Wnęki ze światłem w tylnej ścianie wnętrz (`niches3d.gd`, `DEPTH_PLAN.md` N2–N3). Czysta oprawa: bez kolizji i bez światła na planie gry.
## Hala stacji: zaplecze (pilot N2) na parterze pod kratą, między kałużą oleju (kolumny 84–87) a skrzynią `k` (kolumna 92).
## Tunel drezyny (wiersze 45–50): sztolnie i korytarz techniczny między stemplami `w`, co najmniej 40 kolumn od siebie i 10 od Ślepców
## i gniazd ćm (zasada 4); regał bez światła przy końcu tunelu. Dolna hala: magazyn za kratą przy prawym końcu.
const NICHES := [
	{"kind": "doorway", "c0": 88, "c1": 91, "r0": 23, "r1": 25, "d": 8.0, "lit": "bulb"},
	{"kind": "drift", "c0": 107, "c1": 109, "r0": 48, "r1": 50, "lit": "mine"},
	{"kind": "corridor", "c0": 155, "c1": 157, "r0": 48, "r1": 50, "lit": "cage"},
	{"kind": "drift", "c0": 195, "c1": 197, "r0": 48, "r1": 50, "d": 8.0, "lit": "mine"},
	{"kind": "grate", "c0": 211, "c1": 213, "r0": 37, "r1": 39, "lit": "bulb"},
	{"kind": "shelf", "c0": 259, "c1": 261, "r0": 49, "r1": 50, "lit": ""},
	{"kind": "window", "c0": 93, "c1": 96, "r0": 20, "r1": 21, "lit": "tube"},     # N4: okno zaplecza nad drzwiami hali stacji
	{"kind": "window", "c0": 190, "c1": 193, "r0": 32, "r1": 33, "lit": "tube"},   # N4: okno sterowni nad prawą kładką podziemnej hali
	{"kind": "window", "c0": 223, "c1": 226, "r0": 18, "r1": 19, "lit": "bulb"},   # N4: okno na piętrze pompowni
	{"kind": "vent", "c0": 124, "c1": 124, "r0": 46, "r1": 46, "lit": "lamp"},     # N4: kratki pod stropem tunelu, w środku przęseł
	{"kind": "vent", "c0": 228, "c1": 228, "r0": 46, "r1": 46, "lit": "lamp"},
]
## Pierwszy plan przed płaszczyzną gry (`front3d.gd`, `FOREGROUND_PLAN.md` F2 — pilot): rury, kable i łańcuchy 3,5–5 m przed kamerą
## w hali stacji i w tunelu drezyny; pas wpisu od stropu (r0) do podłogi (r1), elementy przycięte do niego w rzucie na płaszczyznę gry.
const FRONT := [
	{"set": "station", "c0": 66, "c1": 100, "r0": 18, "r1": 26, "shell": true, "build": "hall"},     # hala stacji (budynek 3D: szkielet z cegłą)
	{"set": "tunnel", "c0": 8, "c1": 282, "r0": 44, "r1": 51, "shell": true},      # tunel drezyny
	{"set": "forest", "c0": 2, "c1": 62, "r0": 0, "r1": 26, "skip": [[38, 43], [59, 62]]},   # las od startu do hali stacji (F3, pilot lasu); bez drzew nad włazami przepustu i studni (pień widać w przekroju)
	# las za halą stacji do masztu; bez pni przed szopą na bagnie i pompownią (wnętrza bez przekroju), podłoże ciągłe (dołki przed szybami)
	{"set": "forest", "c0": 101, "c1": 285, "r0": 0, "r1": 26, "skip": [[112, 132], [216, 246]]},
]
const FRONT_SKIP := []                     ## [c0, c1] bez pierwszego planu
## Strefa wydobycia (DESTRUCTION_PLAN.md D5 część 3, od 1.7.505): zasypana piwnica ze żwirem za zamurowaną skrytką „q” na zachód od
## podziemnej hali — wchodzi się tylko przez rozbite przejście, z boku drogi do generatorów.
const DIG_ZONES := [[133, 36, 142, 39, "gravel", 1201]]

const MAP := [
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........................................................................................................................................................................................................................................................................ww..................##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.......................................................................................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.......................................................................................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.......................................................................................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.......................................................................................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.......................................................................................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.....................................CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC...................ww............w.....##",
	"##........w...w.......................w...............w.w...............................................w.....................................w...w.w.............................w.....................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC.................G.ww............w.....##",
	"##........w...w.......................w...............w.w.........CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC...w.....................................w...w.w.............................w.....................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC...........============..........w.....##",
	"##........w...w.......................w...............w.w.........|bbbbbbbbbbbbbbbIbbbbbbbbbbbbbbbbb|...w.....................................w...w.w.......................P.....w.....................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC...................ww............w.....##",
	"##........w...w.......................w...............w.w.....----|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|...w.......CCCCCCCCCCCCCCCCCCCCC.........w...w.w.............===============.w.....................................CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC.........----......ww............w.....##",
	"##........w...w.......................w...............w.w.........CbbbbbbbbbbbbbgbbbbbbbbbbbbbbbbbbbC...w.......w...................w.........w...w.w...............w..........w..w.....................................CbbbbbbbbbbbbbbbJbbbGbybbbPbbbC...................ww............w.....##",
	"##........w...w.......................w...............w.w...----...bbb=====================bbbbbbbbb....w.......w...................w.........w...w.w...........----w..........w..w......................................bbbbbbCCCCCCCCCCCCCCCCCCCCCCC........----........ww............w.....##",
	"##........w...w.......................w...............w.w..........bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb....w.......w...................w.........w...w.w...............w..........w..w......................................bbbbbbbbbbbbbbbbbIbbbbbbbbbbb....................ww............w.....##",
	"##........w...w.......####............w...............w.w.----.....b====bbbbbbbbbbbbbbbbbbbbbbbbbbbb....w.......w...................w.........w...w.w.........----..w..........w..w......................................b----bbbbbbbbbbbbbbbbbbbbbbbb......----..........ww............w.....##",
	"##...S..S.w...w.....########.....ag.kkw.......T.TWT.Tkwow..........bbbbbbbbbLbbbbbbLbbbbbbbbkbGbbPab.u..w...T..Tw.T...J..ok.Z...J...w.........Y...W.w...............w..........w..w................k.....................bbbbbbbobbbUbbbbobbTbbbTbb:kb................T...Twa.T.........W.P...##",
	"#######################################----#################------CCCCCCCCCCCCCCCCCCOOOOCCCCCCCCCCCCC#####mmmmmmmmmmmmm#######~~~~~~~~~~~~~#############bbbbbb#################################################bbbbbb###CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#########################bbbbbb##########",
	"#######################################bbbb#################bbbbbb############################################################~~~~~~~~~~~~~#############bbbbbbbbbbbbb##########################################bbbbbb###########################################################bbbbbb##########",
	"#######################################--bbbbbbbbbbbbbbbbbbbbb====######################################################################################======bbbbbbb##########################################======###########################################################======##########",
	"#######################################bbbbbbbbbbbbbbbbbbbbbbbbbbb######################################################################################bbbbbb%bbubab##########################################bbbbbb###########################################################bbbbbb##########",
	"############################################################====bb####################################################################################CCbb====CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCC#########################################################bb====##########",
	"############################################################bbbbbb####################################################################################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbIbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"############################################################bb====####################################################################################Cb====bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb====bC#########################################################====bb##########",
	"############################################################bbbbbb####################################################################################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"############################################################====bb####################################################################################Cbbb====bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb====bbbC#########################################################bb====##########",
	"############################################################bbbbbb####################################################################################CbbbbbbbbbbbbbbbbbbbPbbbbbbbbbbbbbbbbbbbbbbbbbPbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"############################################################bb====bbbbb###############################################################################Cb====bbbbbb===============bbbbbbbbbbbbb===============bbbb====bCCCCCCCC##################################################====bb##########",
	"############################################################bbbbbbbbbbb########################################################################bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCbbbbbbC##################################################bbbbbb##########",
	"############################################################====bb%bbbb########################################################################bbbbbbbbbbb====bbbbbb====bbbbbbbbbbbbbbbbbbbb====bbbbbbbbbbbbbbb====bbbbbbbbbbC##################################################bb====##########",
	"###################################################################====########################################################################bbubaubqbybbbbbabbbbubbTbbTbbbLbbbbbbGbbkkbWbbbbbbbbTbbbbabbXbbubbbbbbb+bbauybC##################################################bbbbbb##########",
	"###################################################################bbbb###############################################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC==CCCCC##################################################====bb##########",
	"############################################################bbbbbbb====bbbbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbbbbbb#######################################################bbbbbb##########",
	"############################################################bbbbbbbbbbbbbbbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbb====#######################################################bb====##########",
	"############################################################bbbbbbbbb====bbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbbbbbb#######################################################bbbbbb##########",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbbbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbbbbbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbb====CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbb====bwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbb====wbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwb====bbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbb==w======bwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbb==w=======wbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbw====bbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbb====bbbbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbb====wbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbb===wbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########CbbbbbEbbbbbbbbbwbbbbbabwbPbbubbwbbbbbbbwbTbTbTbwbbbbbbbZbbbbbbbwbbbJbbbwbbbbbWbwbbbLbbbwbbbTbTbwbbbbbbbwbbbbubbPbabbybbwbbbbbbbJbbbZbbbJbbbbbbbwbbbbbbbwbbbbbTbTbTbbbbbwbbbbbbbwbWbbbbbwbbbbbbbwbJbbbbZwbbbbbbbwbbbbbbbwbTbTbbbwbbbbbbbwbbbLbbbwbbbbbbbwbbbbbabwbDbbubbwb====bbbC######",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC######",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
]
