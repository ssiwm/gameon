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
## Mapa jest generowana programem pomocniczym — po zmianach uruchom `--maptest`.

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
## Broń na ziemi („g") od lewej: strzelba na dziedzińcu, kusza (cicha — pasuje do celu pobocznego) na antresoli chaty. Kilof przy wieży zniknął w 1.7.495
## (B1: ma go każdy) — zamurowane przejście „q" w lewej ścianie podziemnej hali (skrytka ze złomem i amunicją; wejście 3 kafle, wiersze 37-39) bierze każdy.
const WEAPONS := [Weapons.SRUT8, Weapons.CIEGNO6]
## Skrzynie mocy (FUN_PLAN.md P1.3): [kolumna, rząd, broń, naboje] — FALCON-6 w podziemnym korytarzu (obok skrzynki amunicji).
const POWER_CRATES := [[149, 39, Weapons.SOKOL6, 60]]
## Sejfy (FUN_PLAN.md P2.2): [kolumna, rząd, złom] — wyważanie trzymanym [E] jest głośne; tuż obok Podsłuchacza przy generatorze.
## Kolumna 103, nie 100: w kolumnie 100 stoi słup budynku stacji, który w widoku 3D zasłaniał skrzynię (skrytka „u” jest w kolumnie 101).
const STRONGBOXES := [[103, 25, 40]]
## (8+) Poly Haven: koksownik przy kłodach za chatą radiową, opona w bagnie, pniak za bagnem.
const ACCENTS := [[Vector2(152, 416), 6], [Vector2(184, 416), 6], [Vector2(648, 416), 7], [Vector2(2000, 416), 7], [Vector2(3500, 416), 7], [Vector2(696, 416), 11], [Vector2(808, 416), 13], [Vector2(968, 416), 9], [Vector2(3592, 416), 17], [Vector2(3624, 416), 15], [Vector2(3704, 416), 18], [Vector2(3752, 416), 17], [Vector2(3816, 416), 20], [Vector2(3864, 416), 19], [Vector2(3928, 416), 17], [Vector2(3624, 353), 17], [Vector2(3656, 353), 15], [Vector2(3704, 353), 20], [Vector2(3816, 353), 17], [Vector2(3848, 353), 18], [Vector2(3928, 353), 15], [Vector2(3896, 416), 21], [Vector2(3832, 405), 22]]

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
]
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
	"##...S..S.w...w.....########......g.kkw.a...T.T.T.T..kwow.W........bbbbbbbbbLbbbbbbLbbbbbbbbkbGbbPab.u..w...T..Tw.T...J..ok.Z...J...w.........Y...W.w...............w..........w..w................k.....................bbbbbbbobbbUbbbbobbTbbbTbb:kb................T...Twa.T.........W.P...##",
	"##################################################################CCCCCCCCCCCCCCCCCCOOOOCCCCCCCCCCCCC#####mmmmmmmmmmmmm#######~~~~~~~~~~~~~#############bbbbbb#################################################bbbbbb###CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC#########################bbbbbb##########",
	"##############################################################################################################################~~~~~~~~~~~~~#############bbbbbbbbbbbbb##########################################bbbbbb###########################################################bbbbbb##########",
	"########################################################################################################################################################======bbbbbbb##########################################======###########################################################======##########",
	"########################################################################################################################################################bbbbbb%bbubab##########################################bbbbbb###########################################################bbbbbb##########",
	"######################################################################################################################################################CCbb====CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCC#########################################################bb====##########",
	"######################################################################################################################################################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbIbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"######################################################################################################################################################Cb====bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb====bC#########################################################====bb##########",
	"######################################################################################################################################################CbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"######################################################################################################################################################Cbbb====bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb====bbbC#########################################################bb====##########",
	"######################################################################################################################################################CbbbbbbbbbbbbbbbbbbbPbbbbbbbbbbbbbbbbbbbbbbbbbPbbbbbbbbbbbbbbbbbC#########################################################bbbbbb##########",
	"######################################################################################################################################################Cb====bbbbbb===============bbbbbbbbbbbbb===============bbbb====bCCCCCCCC##################################################====bb##########",
	"###############################################################################################################################################bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbCbbbbbbC##################################################bbbbbb##########",
	"###############################################################################################################################################bbbbbbbbbbb====bbbbbb====bbbbbbbbbbbbbbbbbbbb====bbbbbbbbbbbbbbb====bbbbbbbbbbC##################################################bb====##########",
	"###############################################################################################################################################bbubaubqbybbbbbabbbbubbTbbTbbbLbbbbbbGbbkkbWbbbbbbbbTbbbbabbXbbubbbbbbb+babuybC##################################################bbbbbb##########",
	"######################################################################################################################################################CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC##################################################====bb##########",
	"############################################################bbbbbbbbbbbbbbbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbbbbbb#######################################################bbbbbb##########",
	"############################################################bbbbbbbbbbbbbbbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbbbbbb#######################################################bb====##########",
	"############################################################bbbbbbbbbbbbbbbbbbb###################################################bbbbbbbbbbbbbbbbbbbbb#################################################bbbbbbbbbbbbbbbbb#######################################################bbbbbb##########",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbbbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbbbbbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCbbbbbbbbbbbbbbbbbCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC====bbCCCC######",
	"########CbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwb====bbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbb==w======bwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbb==w=======wbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########Cbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbb====bbbbbC######",
	"########CbbbbbbbbbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbwbbbbbbbbC######",
	"########CbbbbbEbbbbbbbbbwbbbbbabwbPbbubbwbbbbbbbwbTbTbTbwbbbbbbbZbbbbbJbwbbbLbbbwbbbbbWbwbbbbbbbwbbbTbTbwbbbbbbbwbbbbubbPbabbybbwbbbbbbbJbbbZbbbJbbbbbbbwbbbbbbbwbbbbbTbTbTbbbbbwbbbbbbbwbWbbbbbwbbbbbbbwbbbbbbbJbbbbbZbwbbbbbbbwbTbTbbbwbbbbbbbwbbbLbbbwbbbbbbbwbbbbbabwbDbbubbwb====bbbC######",
	"########CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC######",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
	"################################################################################################################################################################################################################################################################################################",
]
