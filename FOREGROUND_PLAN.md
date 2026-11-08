# Plan: pierwszy plan przed płaszczyzną gry

Status: **plan z 2026-11-07; F0 zrobione 2026-11-08 (wariant A); F1 + F2 (pilot: hala stacji i tunel 1.2) w 1.7.519 — czeka
na bramkę F2 (wyniki niżej).** Punkt 2 raportu o głębi świata
(`C:\deadair87\reports\world-depth-recommendations-2026-11-04.md`); punkty 1 i 3 (wnętrza) zamknął `DEPTH_PLAN.md` (1.7.507–1.7.518).
Stan odniesienia: `main` 1.7.518 (473eee6).

## Werdykt

Przed płaszczyzną gry (z > `Level3D.DEPTH_FRONT` = 1,1 m) stoją dziś tylko trawa i korzenie na krawędzi bryły gruntu
(`Level3D.build_front_edge`, najdalej 0,5 m przed przekrojem) i deszcz. Wszystko inne leży za płaszczyzną, więc w ruchu cały obraz
przesuwa się prawie jak jedna płaska warstwa. Pierwszy plan daje najwięcej paralaksy na metr. Przy kamerze NORMAL oko stoi 20,2 m
od płaszczyzny gry, a kadr ma 14,7 m wysokości. Względem płaszczyzny gry przesuwają się:

| Co | z [m] | Przesuw |
|---|---|---|
| tylna ściana wnętrza | −2,4 | ×0,89 |
| korytarz we wnęce | −8 | ×0,72 |
| **pierwszy plan** | **+3 / +4 / +5** | **×1,17 / ×1,25 / ×1,33** (kadr 12,5 / 11,8 / 11,0 m) |

Trzy rzeczy, przez które to nie jest „dorzucić pnie przed kamerę”:

1. **Kanapka warstw.** Obraz graczy (`VpActors`, `Z_FG` = 1) leży na obrazie świata (`VpWorld`, `Z_BG` = −60) bez testu głębi.
   Pień postawiony w warstwie świata wypadnie *pod* graczami, ale *nad* wrogami (wrogowie są w warstwie świata).
2. **Lekcja z `ATMOSPHERE_PLAN.md` F4.** Plan pierwszy z ciemnych sylwetek mebli (jeszcze w 2D) wycofano po uwagach z gry, bo
   przy brzegach kadru zostawały prostokątne, ciemne bryły. Tym razem kształty są nieregularne (igliwie, kable, gałęzie), a decyzję
   podejmujemy po obejrzeniu w ruchu, nie na zrzutach.
3. **Czytelność.** Kamera trzyma drużynę w środku kadru, a pierwszy plan przesuwa się szybciej od niej, więc prędzej czy później
   przejdzie przez środek. Nie wystarczy stawiać go przy brzegach kadru — trzeba go wygaszać tam, gdzie toczy się gra.

## Zasady (obowiązują każdy element)

1. **Nie zasłania rozgrywki.** Shader wygasza element w kole wokół każdej postaci gracza, celownika lokalnego gracza i wrogów
   w kadrze (do 16 punktów w przestrzeni ekranu, `uniform vec4[16]`), do krycia ≤ 0,15. Poza tym krycie ≤ 0,9. Wygaszanie
   jest ditheringiem w przebiegu nieprzezroczystym (alpha scissor + szum), a nie przezroczystością z mieszaniem — bez nadrysowania
   w 4K i bez sortowania.
2. **Bez wpływu na symulację.** Bez kolizji, wzroku wrogów, hałasu, nawigacji i wpływu na celowanie (celownik liczy Camera2D).
   Mapa ASCII się nie zmienia.
3. **Warstwa graczy, nie świata.** Element leży na nowej warstwie `LAYER_FRONT` (256), którą widzi tylko kamera graczy (`_cam_b`).
   W `VpActors` ma test głębi z graczami (gracz przy z ≈ 0 jest zawsze za nim) i razem z graczami ląduje nad światem i wrogami.
   Trzeci SubViewport nad graczami odpadł w F0 (+0,4–0,7 ms za ten sam obraz).
4. **Kształt nieregularny.** Igliwie, liście, kable, łańcuchy i pręty z miękką krawędzią alfa. Żadnych prostych bloków ani
   gołych prostokątnych brzegów, żadnych mebli. Duży element (pień, słup) jest zawsze ucięty brzegiem kadru u góry i u dołu —
   nie widać jego podstawy ani końca.
5. **Ciemniejszy od planu gry.** Sylwetka prawie czarna, z cienką kontrą: w lesie od księżyca, we wnętrzach od poświaty otoczenia
   (oba liczone w shaderze, bez nowych świateł). Światła gry (latarka, lampy, ogień, flary) go nie oświetlają: ich `light_cull_mask`
   nie obejmuje `LAYER_FRONT`. Jedyny wyjątek to błysk wybuchu i burzy jako jeden uniform jasności. Element nie rzuca cienia.
6. **Gęstość.** Najwyżej jeden duży element naraz w kadrze NORMAL. Pokrycie liczone na zrzucie: średnio ≤ 8% kadru,
   w żadnym kadrze ≤ 15%. Bez pierwszego planu w strefach wpisanych w dane mapy (`FRONT_SKIP`): arena bossa, pościg Stalkera,
   strefa startu i wyjścia.
7. **Koszt < 0,4 ms GPU** na kadr przy HIGH 4K. LOW: połowa elementów, bez wygaszania ditheringiem (twarde koło).
8. **Ustawienie dostępności:** „Foreground” ON / REDUCED / OFF w menu pauzy (DISPLAY), domyślnie ON; REDUCED = tylko górny
   i dolny brzeg kadru. Do testów flaga `--nofront`.
9. Tylko 3D (CLAUDE.md): modele i shader w scenie, nic rysowanego w 2D.

## Etapy

### F0 — punkt wyjścia (pomiar, zrzuty i spike, bez zmian w grze)

- Zrzuty i nagranie przejścia (Movie Maker, `--shotrun`) w czterech miejscach: las na powierzchni 1.2 (start, przed stacją),
  powierzchnia 1.1, hala stacji 1.2, kryjówka. Pomiar GPU tych kadrów na HIGH 4K (`--perf=15 --perfreport`).
- Spike A: jeden pień i jedna gałąź na `LAYER_FRONT` w `VpActors`. Sprawdzić:
  - **światło:** środowisko graczy (`env_b`) ma jaśniejsze otoczenie (0,50 / 0,56 / 0,70) niż świat — shader liczy więc własne
    światło i nie bierze otoczenia ze środowiska;
  - **skalę renderu:** na LOW warstwa graczy ma 50%, na MEDIUM 75% rozdzielczości, rozciągana dwuliniowo — sprawdzić krawędzie;
  - **głębię z graczami** i drezyną (wysuwa graczy ku kamerze).
- Spike B: trzeci SubViewport `VpFront` nad graczami (przezroczysty, własna kamera z maską `LAYER_FRONT`). Porównać koszt z A —
  osobny viewport ma stały narzut przebiegu.
- Wynik: wybór A albo B, zrzuty w `shots_front/f0/` i liczby w tym pliku.

### Wyniki F0 (2026-11-08, spike lokalnie na `spike/front-f0`, poza `main`)

- **Spike:** `scripts/front3d.gd` i flaga `--frontspike=A|B` (`--frontbright` rozjaśnia elementy, żeby było je widać na zrzucie).
  Co ok. 24 m stoi jeden element, 3,5–5 m przed płaszczyzną gry: pod gołym niebem pień sosny z gałęziami, we wnętrzu rura z trzema
  kablami. Shader bez oświetlenia sceny (`unshaded`): ciemny odcień, cienka kontra, wygaszanie ditheringiem Bayera 4 × 4 wokół
  punktów rzutowanych na płaszczyznę gry (z = 0) promieniem z kamery. Przy `--shotat` pierwszy element stoi 2 m na prawo od gracza.
- **Kadry** (4K, HIGH, debug): las na powierzchni 1.2 (kolumna 44, `--shotrow=20`), powierzchnia 1.1 (46, 18), hala stacji 1.2
  (89, 19), środek kryjówki (40, 15).
- **Wydajność** (GPU, trzy rundy naprzemiennie; mediana):

| Kadr | bez | A (warstwa graczy) | B (trzeci SubViewport) |
|---|---|---|---|
| las 1.2 | 9,14 ms | 9,23 ms (+0,09) | 9,56 ms (+0,42) |
| powierzchnia 1.1 | 9,83 ms | 10,11 ms (+0,28) | 10,37 ms (+0,54) |
| hala stacji 1.2 | 7,63 ms | 7,48 ms (−0,15) | 8,37 ms (+0,74) |
| kryjówka | 10,07 ms | 10,08 ms (0,00) | 10,47 ms (+0,40) |

  A kosztuje tyle co szum (średnio +0,06 ms), +1–5 wywołań rysowania. B dokłada stały narzut osobnego przebiegu (+0,4–0,7 ms),
  a obraz ma ten sam. **Wybór: wariant A** — `LAYER_FRONT` w `VpActors`; B odpada.
- **Skala renderu:** na MEDIUM (75%) i LOW (50%, dwuliniowo) krawędzie pnia są czyste, bez schodków ani obwódki na przezroczystym
  tle warstwy graczy.
- **Światło:** materiał `unshaded` nie bierze jaśniejszego otoczenia środowiska graczy (`env_b`) — własne światło w shaderze działa.
- **Najważniejsze: ciemna sylwetka znika w nocnym lesie.** Na 1.2 i 1.1 pień widać tylko na tle nieba i plam światła (ognisko,
  latarka), a gałęzi prawie wcale — tło lasu jest równie ciemne. We wnętrzach jest odwrotnie: rura z kablami na tle oświetlonego
  muru kryjówki czyta się wyraźnie, w hali stacji na tle okna i zaplecza. Paralaksa w lesie wymaga więc mocniejszej kontry
  od księżyca (kierunek `Level3D.MOON_DIR`, tylko krawędź zwrócona ku niebu) albo sylwetki odrobinę jaśniejszej od czerni
  i chłodnej — do sprawdzenia w F1. Wnętrza działają już z samą sylwetką.
- **Wygaszanie:** na zrzucie z `--frontbright` pień przechodzący przez gracza jest wokół niego przerzedzony do 15%; wzór ditheringu
  widać jako drobną siatkę. Czy migocze w ruchu, okaże się dopiero na nagraniu (F2).
- **Nie sprawdzone:** drezyna (gracze wysunięci ku kamerze), nagranie w ruchu, WIDE i CLOSE.
- Zrzuty i pomiary: `shots_front/f0/` (`f0_sheet.jpg`: bez / A / B / A rozjaśnione dla czterech kadrów; `f0_zoom.jpg`,
  `f0_lowzoom.jpg`; skrypt serii `f0.sh`).
- **Wniosek dla decyzji 1 (pilot):** w lesie pierwszy plan zadziała dopiero po dodaniu kontry. Pilot we wnętrzu (hala stacji 1.2
  albo kryjówka) pokaże efekt od razu, ale bez biegu przez długi odcinek. Rekomendacja zmienia się na: **pilot w hali stacji 1.2
  i jej tunelu** (wnętrze, walka, bieg w poziomie), las jako drugi krok F2 z kontrą księżyca.

### F1 — mechanizm (`scripts/front3d.gd`)

- Dane: rozmieszczenie proceduralne z kafli mapy (las pod gołym niebem, wnętrze pod `C`/`b`, jak `build_forest` i
  `build_front_edge`), stałe ziarno per mapa, odcinki po 96 m jak `FOREST_CHUNK` (silnik rysuje tylko te w kadrze). W danych mapy
  `FRONT_SKIP` (zakresy kolumn bez pierwszego planu) i opcjonalnie `FRONT` (ręczne wpisy w miejscach, gdzie reguła nie wystarcza).
- Shader: sylwetka, kontra, miękka krawędź, wygaszanie wokół punktów z zasady 1, uniform błysku. Punkty co klatkę z `view3d.gd`:
  gracze (wszyscy, także w co-op), celownik lokalnego gracza, najbliżsi wrogowie w kadrze i znaczniki ataków (znacznik plucia Żyły).
- MultiMesh na rodzaj; LOW i REDUCED wg zasady 7 i 8; `--nofront`.
- Test `tools/test_front.gd`: warstwy i maski (kamera świata nie widzi `LAYER_FRONT`, żadne światło gry go nie oświetla), brak
  kolizji, brak cienia, `FRONT_SKIP` szanowany, gęstość (≤ 1 duży element na okno kadru NORMAL), funkcja wygaszania (krycie ≤ 0,15
  w punkcie i promieniu, liczona tą samą funkcją co w shaderze).

### F2 — pilot (po F0: hala stacji 1.2 z tunelem, potem las 1.2 z kontrą — decyzja 1)

- Pnie sosen i świerków (proste, ciemne, ucięte brzegiem kadru) i zwisające gałęzie z igliwiem przy górnej krawędzi, z modeli lasu
  (`prep_items3d.py: build_pine`, `world_forest_gen.py`) — w pierwszym planie bez szczegółu kory, sylwetka wystarcza.
- A/B: zrzuty, nagranie w ruchu (bieg w obie strony, walka z kilkoma wrogami, co-op na dwóch klientach), pomiar GPU, pokrycie kadru.
- **Bramka F2:** użytkownik ogląda nagranie i gra (nie tylko zrzuty — lekcja F4) i decyduje: dalej, poprawki albo wycofanie.

### Wyniki F1 + F2 (2026-11-08, 1.7.519)

Decyzje przed F1 (użytkownik, 2026-11-08): pilot w hali stacji 1.2 z tunelem; element może przejść przez środek kadru
(wygaszanie przy postaciach); „Foreground” domyślnie ON. Rozmycie (decyzja 4) — po bramce F2.

- **Mechanizm** (`scripts/front3d.gd`, wariant A z F0):
  - Dane: ręczne wpisy `FRONT` w mapie (`{"set", "c0", "c1", "r0", "r1"}` — zestaw i pas wejścia w kaflach) i `FRONT_SKIP`
    (zakresy kolumn bez pierwszego planu). Reguła z kafli (las, wnętrza z `C`/`b`) zostaje na F3, po bramce — pilot obejmuje
    dwa wpisy w `z1_m2.gd`: hala stacji (kolumny 66–100, wiersze 18–26) i tunel drezyny (8–282, 44–51).
  - Rozmieszczenie stałym ziarnem z wpisu: duży element (rura, para rur z obejmami) co 21–28 m, mały (wiązka kabli, łańcuch na haku)
    w połowie odstępu z prawdopodobieństwem 0,6; z 3,5–5 m przed płaszczyzną gry; 2 m zapasu od brzegów wpisu.
  - Bryły scalone z części (`SurfaceTool`), jeden `MeshInstance3D` na element zamiast MultiMesh na rodzaj: elementów jest kilka
    na wpis, a każdy ma własny pas przycięcia w parametrze instancji.
  - **Przycięcie do pasa wejścia:** shader rzutuje fragment na płaszczyznę gry promieniem z kamery i odrzuca wszystko poza pasem
    wpisu. Rura kończy się więc dokładnie na linii stropu i podłogi korytarza (w rzucie), także przy zmianie zoomu, i nie wystaje
    w niebo ani do sąsiedniej kondygnacji. Brzeg kadru tnie ją tylko wtedy, gdy pas jest wyższy od kadru.
  - Shader `unshaded`: odcień zestawu, kontra od kierunku klucza, **poświata od graczy** (strona zwrócona do graczy rozjaśnia się
    ciepło, słabnąc z odległością w skali 7 m — bez tego w tunelu elementów prawie nie widać). Światła gry go nie oświetlają (materiał
    bez oświetlenia), cienia nie rzuca.
  - Wygaszanie: ditheringiem Bayera 4 × 4 do 0,15 w kołach wokół graczy (1,8 m), celownika (1,0 m) i wrogów w kadrze (1,6 m,
    od najbliższego środka kadru), pełne krycie od promienia × 1,7; najwyżej 16 punktów. `Front3D.fade` liczy to samo co shader.
  - LOW: bez małych elementów i twarde koło zamiast ditheringu. REDUCED: bez pasa ±30% wysokości kadru wokół jego środka —
    zostają tylko końce przy górnym i dolnym brzegu. OFF chowa węzeł. `--nofront` nie buduje nic.
- **Ustawienie** „Foreground” / „Pierwszy plan” ON / REDUCED / OFF w DISPLAY menu pauzy, zapis `foreground` w `[game]`.
- **Test** `tools/test_front.gd` (w CI): dane wszystkich map, rozmieszczenie (z, zapas, odstępy dużych ≥ 21 m także między wpisami
  w jednym kadrze NORMAL, mały ≥ 6 m od dużego, LOW bez małych, determinizm), `FRONT_SKIP`, warstwy rozłączne ze światem, lasem,
  dnem lasu i wnękami, bryły (tylko `LAYER_FRONT`, bez cienia, bez kolizji, `unshaded`, pas przycięcia), ON/OFF, funkcja wygaszania.
- **Wydajność** (GPU, 4K HIGH, debug, trzy rundy naprzemiennie, mediana): hala stacji (89, 19) bez 7,90 ms / z 7,79 ms — szum;
  tunel (120, 45) 6,96 ms / 7,19 ms (+0,23 ms). +2 wywołania rysowania. Oba w budżecie 0,4 ms (zasada 7).
- **Pokrycie** (różnica zrzutów z / bez, górna granica — wlicza też ruchomy pył i cząsteczki): hala 4,8% i 0,9%, tunel 0,4% i 3,6%
  kadru — w limicie 8% (zasada 6).
- **Obraz:**
  - hala: para rur przed oświetlonym murem to wyraźna ciemna sylwetka, a przy wolnym biegu widać, że przesuwa się szybciej niż
    plan gry; rura przechodząca przez wroga przerzedza się wokół niego (na zrzucie wygląda jak ucięta nad podłogą — to wygaszanie);
  - tunel: elementy są ciemnymi, cienkimi pionami, widać je głównie przy latarce gracza, lampach i poświacie. Na tle ciemnego
    tunelu sylwetka czyta się słabo — jeśli bramka zażąda mocniejszego efektu, w tunelu lepiej sprawdzi się jaśniejszy odcień
    albo element z własnym źródłem (lampa na kablu) niż ciemny pion;
  - LOW: twarde koło przy postaciach, krawędzie bez schodków; REDUCED: rury tylko przy brzegach kadru.
- **Nie sprawdzone:** drezyna (gracze wysunięci ku kamerze), co-op na dwóch klientach, WIDE i CLOSE, wstrząs kamery przy wybuchu,
  uniform błysku (nie zrobiony — pilot nie ma wybuchów przed rurą), znaczniki ataków jako punkty wygaszania.
- Zrzuty, nagrania i pomiary: `shots_front/f2/` — `f2_sheet.jpg` (hala, hala w lewo, REDUCED, LOW, tunel, tunel LOW),
  `cmp_hall.mp4` i `cmp_tun.mp4` (z | bez, 22 s biegu z `--shotrun`), pełne `run_*_on/off.mp4`, `perf_*.txt`, skrypt `f2.sh`.

### F3 — katalog i mapy (po bramce)

- Las: pień sosny, pień brzozy, martwy pień, zwisająca gałąź, wysoka paproć i trawa przy dolnej krawędzi.
- Wnętrza: rura pionowa, wiązka kabli ze stropu, dźwigar stalowy, łańcuch, krata. W kryjówce i hali stacji to „ucięty przód
  budynku”, jak w grach z przekrojem.
- Zabudowania i stacja: słup energetyczny z przewodami, płot, siatka.
- Po jednym PR na mapę: 1.2, 1.1, 1.3, B1, kryjówka. Każda mapa: zrzuty, nagranie, pokrycie, GPU, `test_front.gd`.

### F4 — rozmycie bliskiego planu (opcjonalnie, po F3)

- Rozmycie głębi ostrości tylko dla bliskiego planu na kamerze graczy (`CameraAttributesPractical.dof_blur_near_*`): gracze
  stoją 20,2 m od kamery i zostają ostrzy, pierwszy plan przy 15–17 m się rozmywa. Sprawdzić koszt w 4K i krawędzie
  na przezroczystym tle `VpActors`. Zamiennik: miękkie tekstury i mipmapy przesunięte w górę.

## Kolejność i rozmiar

| Etap | Co | Rozmiar | Wersja |
|---|---|---|---|
| F0 | zrzuty, nagranie, pomiar, spike A / B | 0,5–1 d | zrobione 2026-11-08, bez wersji: wariant A |
| F1 | `front3d.gd`, shader, dane, ustawienie, test | 1–1,5 d | 1.7.519 |
| F2 | pilot: hala stacji i tunel 1.2 + A/B + bramka; las 1.2 z kontrą po bramce | 0,5–1 d | 1.7.519 (ten sam PR) |
| F3 | katalog i mapy | 2–3 d | po jednym PR na mapę |
| F4 | rozmycie bliskiego planu | 0,5 d | po F3, jeśli bramka F2 tego zażąda |

## Ryzyka

- **Zasłonięty wróg albo pocisk.** Wygaszanie obejmuje postacie i wrogów, ale nie każdą smugę kuli i nie każdy odprysk. Dlatego
  elementy są cienkie i rzadkie (zasada 6), a REDUCED i OFF czekają w menu.
- **Wstrząsy kamery.** Duża ciemna sylwetka przesuwa się przy wstrząsie mocniej niż plan gry (×1,25). Sprawdzić na nagraniu
  wybuchu i ciosu Wołka; w razie potrzeby wstrząs dla pierwszego planu słabszy.
- **Kamery WIDE i CLOSE.** Odległość oka zmienia się z zoomem, więc zmieniają się też skala i pokrycie pierwszego planu.
  Pokrycie mierzyć we wszystkich trzech.
- **Co-op.** Gracze mogą stać daleko od siebie, a punktów wygaszania jest 16. Kolejność: gracze, celownik, wrogowie od najbliższego.
- **Światło.** Wybuch tuż przed pniem bez rozjaśnienia pnia wygląda płasko — stąd uniform błysku (zasada 5).
- **Choroba lokomocyjna i migotanie** przy szybkim biegu: przesuw ×1,17–1,33 jest umiarkowany, ale pnie co kilka metrów dałyby
  stroboskop. Stąd jeden duży element na kadr.

## Do decyzji (przed F1 — 1–3 rozstrzygnięte 2026-11-08 zgodnie z rekomendacją)

1. **Pilot:** po F0 polecam halę stacji 1.2 z tunelem (wnętrze — sylwetka czyta się od razu; walka i bieg w poziomie), las 1.2
   jako drugi krok z kontrą księżyca. Alternatywy: las od razu (więcej pracy nad światłem) albo kryjówka (bez walki).
2. **Wygaszanie przy postaciach** (polecam: element może przejść przez środek kadru) czy zakaz stawiania w pasie gry
   (tylko górny i dolny brzeg kadru, prościej, ale słabsza paralaksa).
3. **Ustawienie „Foreground”** ON / REDUCED / OFF, domyślnie ON (polecam) czy domyślnie REDUCED.
4. **Rozmycie (F4):** decyzja po bramce F2.
