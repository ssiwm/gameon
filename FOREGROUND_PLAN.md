# Plan: pierwszy plan przed płaszczyzną gry

Status: **plan z 2026-11-07, nic nie wdrożone.** Punkt 2 raportu o głębi świata
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
   Trzeci SubViewport nad graczami to wariant zapasowy — F0 mierzy oba.
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

### F2 — pilot: las na powierzchni 1.2

- Pnie sosen i świerków (proste, ciemne, ucięte brzegiem kadru) i zwisające gałęzie z igliwiem przy górnej krawędzi, z modeli lasu
  (`prep_items3d.py: build_pine`, `world_forest_gen.py`) — w pierwszym planie bez szczegółu kory, sylwetka wystarcza.
- A/B: zrzuty, nagranie w ruchu (bieg w obie strony, walka z kilkoma wrogami, co-op na dwóch klientach), pomiar GPU, pokrycie kadru.
- **Bramka F2:** użytkownik ogląda nagranie i gra (nie tylko zrzuty — lekcja F4) i decyduje: dalej, poprawki albo wycofanie.

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
| F0 | zrzuty, nagranie, pomiar, spike A / B | 0,5–1 d | bez wersji (wyniki w tym pliku) |
| F1 | `front3d.gd`, shader, dane, ustawienie, test | 1–1,5 d | PR, podbicie wersji |
| F2 | pilot: las na powierzchni 1.2 + A/B + bramka | 0,5–1 d | ten sam PR albo następny |
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

## Do decyzji (przed F1)

1. **Pilot:** las na powierzchni 1.2 (polecam: najwięcej ruchu w poziomie, prosty zestaw) czy kryjówka (bez walki, łatwa ocena).
2. **Wygaszanie przy postaciach** (polecam: element może przejść przez środek kadru) czy zakaz stawiania w pasie gry
   (tylko górny i dolny brzeg kadru, prościej, ale słabsza paralaksa).
3. **Ustawienie „Foreground”** ON / REDUCED / OFF, domyślnie ON (polecam) czy domyślnie REDUCED.
4. **Rozmycie (F4):** decyzja po bramce F2.
