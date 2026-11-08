# Plan: pierwszy plan przed płaszczyzną gry

Status: **plan z 2026-11-07; F0 zrobione 2026-11-08 (wariant A); F1 + F2 (pilot: hala stacji i tunel 1.2) w 1.7.519; po pierwszej
ocenie w grze poprawki rur w 1.7.520 (rury z Poly Haven, półprzezroczyste wygaszanie, lampy w tunelu) — czeka na bramkę F2 (wyniki
niżej). Po drugiej uwadze („nie ma tam świata”) F2b: przekrój budynku przesunięty do warstwy pierwszego planu — mechanizm w 1.7.521 (hala i tunel 1.2), luki pilota (drezyna, górny pomost, wstrząs) sprawdzone i poprawione w tym samym PR — czeka na ocenę w grze.** Punkt 2 raportu o głębi świata
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

### Poprawki po pierwszej ocenie F2 (2026-11-08, 1.7.520)

Uwaga użytkownika po grze na 1.7.519: „rury wyglądają źle, zanikają, mają niską jakość”. Przyczyny (zrzuty z wygaszaniem i bez,
zbliżenie 4K — `shots_front/f3/cmp.jpg`):

- **Zanikanie:** wygaszanie w kołach 2,7–3 m wokół gracza, celownika i każdego wroga. Rura nad wrogiem urywała się metr nad podłogą,
  a celownik w ruchu wycinał dziury tam, gdzie gracz celował. Dithering zostawiał 15% pikseli, a na ciemnym tle tego nie widać —
  rura wyglądała na uciętą, nie na przezroczystą, a w ruchu wzór migotał.
- **Niska jakość:** materiał bez oświetlenia sceny i prawie czarny (płaski pas bez bryły i odblasku), proste walce z 12–14 ścianek,
  obejmy z prostopadłościanów. To najbliższy obiekt w kadrze (ok. 60 px szerokości w 4K), więc braki widać najbardziej.
- **Tunel:** ciemny pion na ciemnym tle prawie niewidoczny.

Zmiany (decyzja użytkownika: kroki 1 i 2 naraz):

- **Wygaszanie:** celownik niczego nie wygasza. Wygaszany jest prostokąt sylwetki (gracz 1,1 × 1,9 m; wróg — prostokąt trafień z `_def`
  z zapasem 0,15 m) z miękkim brzegiem 0,6 m, tylko dla wrogów w kadrze. Zamiast ditheringu prawdziwa półprzezroczystość (krycie 0,3,
  przebieg przezroczysty z zapisem głębi). Waga każdej sylwetki narasta i gaśnie przez 0,25 s, a zniknięty wróg gaśnie w miejscu —
  rura nie mruga. Zasada 1 (dithering bez mieszania) przestaje obowiązywać: elementów jest kilka i są wąskie, więc nadrysowanie jest znikome.
- **Rury z modeli:** części zestawu Poly Haven `modular_industrial_pipes_01` (CC0) — odcinek z kołnierzami na śruby, cienka rura,
  zawór z czerwonym kołem i manometrem (ku kamerze), trójnik — wycięte skryptem Blendera `tools/front_parts.py` do
  `art/world3d/front/pipe_parts.glb` (sama geometria; tekstury kolor / ARM / normalne te same co dekoracji `pipes`). Rura to stos odcinków
  w skali ×2 (kołnierz 0,42 m) z zaworem nad głowami i czasem trójnikiem nisko; para rur to cienka rura ×1,5 i odcinki ×1,2 z obejmami
  z malowanej stali. Kable (10 ścianek, opaski) i łańcuch (gęstsze ogniwa) zostają proceduralne, w ciemnym metalu.
- **Światło:** materiał PBR oświetlany sceną. Latarka (reflektor bez maski) świeci na pierwszy plan od zawsze; kontra postaci
  (trzy światła kierunkowe) i lampy dla warstwy graczy dostały `LAYER_FRONT` w masce. Otoczenie środowiska graczy jest jaśniejsze niż
  świata, więc shader zostawia z niego 35% (`ambient_k` przez AO). Zasada 5 (światła gry nie oświetlają pierwszego planu) przestaje
  obowiązywać — dopiero odblask latarki i lamp sprzedaje rurę jako bryłę blisko kamery.
- **Tunel:** zestaw `tunnel` ma lampy na przewodzie (klosz `lamp` z emisją żarówki, 0,75 m, 1,6–2,4 m pod linią stropu pasa) z własnym
  światłem omni tylko na `LAYER_FRONT` (klosz od środka, przewód, sąsiednia rura) — ciemność przy graczach się nie zmienia (GDD §8.3).
- **Rozmycie (F4) sprawdzone i odrzucone:** `CameraAttributesPractical.dof_blur_near_*` na kamerze graczy nie rozmywa niczego — także
  przy odległości 40 m, przy której rozmyta powinna być cała postać. Natywne rozmycie Godota nie działa w warstwie graczy
  (przezroczyste tło SubViewportu); zostałby własny przebieg rozmycia, a rury z modeli wyglądają dobrze ostre. Kod próby usunięty.
- **Wydajność** (GPU, 4K HIGH, debug, trzy rundy naprzemiennie, mediana): hala stacji bez 7,39 ms / z 7,59 ms (+0,20), tunel 6,47 /
  6,64 ms (+0,17) — w budżecie 0,4 ms.
- **Obraz:** w hali para rur z kołnierzami i zaworem odcina się od muru, ma połysk od lampy i latarki; przechodzący za nią wróg jest
  widoczny przez przyciemnioną rurę. W tunelu rury łapią kontrę i latarkę (kołnierze i koło zaworu czytelne), lampy na przewodach świecą.
- Zrzuty, nagrania i pomiary: `shots_front/f3/` — `sheet.jpg` (stare / nowe / próba rozmycia), `z_hall.png` (zbliżenie), `parts_sheet.jpg`
  (części zestawu), `cmp_hall.mp4` i `cmp_tun.mp4` (z | bez, 22 s biegu), `hall_strip.jpg` i `tun_strip.jpg` (klatki co 2,5 s), `perf_*.txt`,
  skrypty `f3full.sh`, `f3.sh`.
- **Nie sprawdzone:** drezyna, co-op, WIDE i CLOSE, wstrząs kamery.

### F2b — przekrój budynku: świat sięga do pierwszego planu (plan 2026-11-08, przed F3)

Druga uwaga użytkownika po 1.7.520: „rury są teraz na pierwszym planie, ale nie mamy tam świata, dlatego wyglądają nienaturalnie”.

**Przyczyna.** Świat kończy się przekrojem na z = `DEPTH_FRONT` = 1,1 m. Rura stoi na z = 3,5–5 m, więc między nią a światem
jest 2,4–3,9 m pustki. Shader ucina rurę w rzucie na linii podłogi, dlatego na nieruchomym kadrze wygląda, jakby na niej stała.
Fizycznie wisi jednak w powietrzu, a w ruchu to widać: paralaksa rury (×1,25) i podłogi (×1,0) się różni i podstawa
ślizga się po podłodze jak naklejka. Tego oko nie wybacza.

Rachunek dla NORMAL. Oko stoi `EYE_UP_M` = 2,2 m nad środkiem kadru, a środek kadru leży mniej więcej na stopach gracza.
- **Podłoga:** dziś jej wierzch widać tylko jako pasek 0,13 m (z od 0 do 1,1). Niżej, do dolnej krawędzi kadru, jest przekrój bryły
  na z = 1,1, czyli prawie połowa dolnej części kadru.
- **Strop:** hala ma go 8,3 m nad okiem, tunel 5,7 m, a górna krawędź kadru wypada 5,2 m nad okiem. Gdy gracz stoi na podłodze,
  stropu nie widać w ogóle.
- **Wniosek:** problem leży prawie wyłącznie u dołu rury, przy styku z podłogą. Strop wchodzi w kadr tylko z górnych pomostów hali.

**Rozwiązanie: przesunąć przekrój do przodu.** W strefie wpisu `FRONT` lite kafle świata (`#`, `C`, `M`, …) stropu i podłogi
z fundamentem sięgają do z = `SHELL_Z` = 5,6 m zamiast 1,1 m (ściany w pasie gry zostają na 1,1 m — wynik spike'a niżej). Przekrój staje się jedną płaszczyzną cięcia na 5,6 m. Wnętrza zostają otwarte, a kamera
zagląda do nich przez brakującą przednią ścianę, jak w domku dla lalek. Elementy pierwszego planu (z 3,5–5 m, kołnierz
z ≤ 5,42 m) stoją wtedy fizycznie na płycie podłogi i dochodzą do stropu.

- **Zostaje w warstwie świata:** podłoga, strop i przekrój leżą w `LAYER_WORLD`, z jego światłem (lampy, latarka), mgłą i cieniami.
  Nie zasłaniają gry, bo poziomy wierzch podłogi przed płaszczyzną gry rzutuje się zawsze *poniżej* linii podłogi, a spód stropu
  zawsze *powyżej* linii stropu. Pas gry jest bezpieczny geometrycznie, nie dzięki wygaszaniu.
- **Pas podłogi w kadrze** (gracz na podłodze, wierzch płyty od z 1,1 do 5,6 m):
  - WIDE: 0,53 m, 2,9% wysokości kadru;
  - NORMAL: 0,72 m, 4,9%;
  - CLOSE: 0,94 m, 7,7%.

  Niżej leży przekrój na z = 5,6 m zamiast na 1,1 m, tej samej wielkości co dziś.
- **Pas stropu** pojawia się tylko z górnych pomostów hali: około 0,6 m, 4% kadru NORMAL.
- **Rura dostaje fizyczne końce.** Podstawa (kołnierz) stoi na wierzchu płyty, a górny kołnierz dochodzi do spodu stropu.
  Przycięcie w rzucie do pasa wpisu zostaje tylko dla wpisów bez przekroju. REDUCED tnie dalej względem środka kadru.
- **Kontakt z płytą:** pod kołnierzem leży ciemna plama okluzji (kalka w warstwie świata), a w miejscu wejścia rury w strop płytka
  mocująca. Pierwszy plan nie rzuca cienia, więc plama zastępuje cień kontaktowy.
- **Hala:** płyta peronu z kątownikiem na przedniej krawędzi; materiał wierzchu ten sam co podłoga hali (beton). Belki pod stropem
  (`_build_ribs`, dziś do z 1,1) przedłużone do `SHELL_Z`, a elementy pierwszego planu trzymają się co najmniej 1 m od belek w osi x.
  Belki są w warstwie świata, więc rura za belką rysowałaby się na niej. Okap dachu hali (`roof_runs`, `ROOF_EAVE`) przesuwa się
  razem z przodem bryły.
- **Tunel:** przekrój skały na 5,6 m i podsypka z betonem na wierzchu. Strop poza kadrem nie wymaga dziś niczego.
- **Bez zmian w symulacji:** mapa ASCII, kolizje i nawigacja to nadal 2D. Głębokość brył to tylko obraz (zasada 2).

**Prostokąt strefy i jej końce.** Strefa to pas wpisu z zapasem kafli w pionie i poziomie, w danych jako opcjonalne pole
`"shell": [c0, c1, r0, r1]` we wpisie `FRONT`, domyślnie wyliczane. Przy granicy strefy przekrój ma uskok 4,5 m w głąb, który
zamyka boczna ściana przekroju (ten sam materiał co przekrój).
- **Pod ziemią** (tunel): zapas 12 kolumn i 8 wierszy wystarcza, żeby uskok nie trafiał do kadru, gdy środek kadru jest we wpisie.
- **Na powierzchni** (hala to budynek stacji na gruncie): grunt obok ma krawędź z trawą na 1,1 m (`build_front_edge`), a przed
  gruntem jest las i niebo. Polecam wysunąć tylko bryłę budynku i grunt pod nią, z boczną ścianą fundamentu z betonu. Z zewnątrz
  stacja stoi wtedy na wysuniętym cokole, który jest głębszy niż sąsiedni grunt. Do decyzji 5.

**Co jeszcze używa `DEPTH_FRONT`.** Każde z tych miejsc musi znać przód strefy albo ją omijać:
- skrzynki brył niszczalnych (`view3d.gd` ok. 2511);
- bryły stref wydobycia (`chunk_mesh`, `view3d.gd` ok. 7436);
- kalki trafień (`level3d.gd` ok. 1315, `view3d.gd` ok. 7521);
- wnęki (`niches3d.gd` ok. 131);
- przekrój (`_build_caps`).

Zasada: **strefa nie obejmuje kafli, które mogą się zmienić** (`DIG_ZONES`, okna `|`, deski `%`, kratki `+`, podpory i cała reszta
z `DESTRUCTION_PLAN.md`). Te kafle zostają na 1,1 m, a przekrój wokół nich zamyka się bocznymi ścianami. Na 1.2 strefa wydobycia
(kolumny 133–142, wiersze 36–39) leży w zapasie tunelu, więc wypada ze strefy.

**Zmiana zasad.** Zasada 4 („duży element ucięty brzegiem kadru u góry i u dołu, nie widać podstawy”) przestaje obowiązywać
w strefach z przekrojem: podstawa jest widoczna i właśnie ona sprzedaje głębię. Poza strefami (las w F3) zasada zostaje.

**Etapy F2b:**

1. **Spike** (lokalnie, bez PR; 0,5 d): tylko hala 1.2, prostokąt na sztywno, głębsze bryły i przekrój, rury z fizycznymi końcami,
   plama pod kołnierzem. Do obejrzenia:
   - zrzuty z | bez przekroju (gracz na podłodze, na górnym pomoście, przy ścianie bocznej hali od zewnątrz);
   - nagranie biegu w obie strony (`cmp_hall.mp4` jak w F2);
   - WIDE i CLOSE, pomiar GPU.

   Oczekiwany koszt: kilkaset głębszych skrzynek MultiMesh i jeden czworokąt przekroju na ciąg, około +0,05–0,1 ms.
   **Bramka:** użytkownik ogląda nagranie i decyduje, czy dalej.
2. **Mechanizm** (1 d):
   - `level3d.gd`: głębokość przodu per kafel (`front_z(c, r)`), boczne ściany uskoku, przekrój, belki, okap, kalki;
   - dane `shell` we wpisie `FRONT`;
   - `front3d.gd`: końce fizyczne, plama i płytka;
   - `test_front.gd`:
     - strefa bez kafli niszczalnych i stref wydobycia;
     - podstawa każdego elementu na wierzchu płyty i z < `SHELL_Z`;
     - element ≥ 1 m od belki;
     - rzut wierzchu płyty i spodu stropu poza pasem gry przy WIDE, NORMAL i CLOSE.
3. **Hala i tunel 1.2** (0,5 d): zrzuty, nagrania, pomiar, `--maptest` całe i rozbite, test sieci. Bramka F2 obejmuje wtedy
   rury razem z przekrojem.

**Wyniki spike'a F2b** (2026-11-08, decyzje 5–7 zgodnie z rekomendacją; kod lokalnie na `spike/front-shell` 47396c9, poza `main`):

- **Zakres:** hala stacji 1.2 (`"shell": true` we wpisie). Strop (wiersz 18) i podłoga z fundamentem (wiersze 26–34) sięgają
  do z = 5,6 m; grunt pod halą jako beton fundamentu. Rury stoją kołnierzem na płycie, przycięte fizycznie (okno y w shaderze)
  zamiast w rzucie, z plamą okluzji pod rurą i płytką pod stropem. Flagi dev: `--noshell` (A/B), `--camidx=N` (WIDE / NORMAL / CLOSE).
- **Zmiana względem planu — ściany w pasie gry zostają na 1,1 m.** Pierwsza wersja wysuwała wszystkie lite kafle w prostokącie,
  także ściany boczne hali w pasie gry. Ściana wysunięta ku kamerze rozrasta się w rzucie (×1,38 przy z = 5,6 m) i zasłoniła
  pierścień Stalkera obok siebie, czyli wrogów i znaczniki z warstwy świata. Przekrój obejmuje więc tylko wiersz stropu i podłogę
  z fundamentem. Dopiero wtedy pas gry jest bezpieczny geometrycznie, jak zakładał plan.
- **Obraz:**
  - przed graczami leży płyta peronu oświetlona latarką i lampą hali, a rura stoi na niej kołnierzem bliżej kamery niż gracz;
  - podstawa nie wisi już na linii podłogi, a na nagraniu biegu (`cmp_hall.mp4`, z | bez) przesuwa się razem z płytą;
  - przy WIDE pas płyty jest wąski, przy CLOSE wyraźny;
  - z zewnątrz (kolumny 63 i 103) budynek stoi na wysuniętym cokole, a pierścień Stalkera przy ścianie jest cały.
- **Wydajność** (GPU, 4K HIGH, debug, trzy rundy naprzemiennie): bez przekroju 7,58 / 7,84 / 7,80 ms, z przekrojem 7,38 / 7,59 /
  7,63 ms — w szumie.
- **Braki do mechanizmu:**
  - kałuża oleju (`O`, kolumny 84–87) kończy się na 1,1 m, a przed nią leży beton: ciemny prostokąt na płycie. Tafla cieczy powinna
    sięgać przodu przekroju;
  - kalki przedniej krawędzi starej bryły zostały na płycie jako przerywana linia na z = 1,1;
  - plama okluzji pod rurą jest prawie niewidoczna (jasny kołnierz robi więcej);
  - okap blachy dachu nie przesunięty — z podłogi strop jest poza kadrem;
  - nie sprawdzone: górny pomost (zrzut z `--shotrow=21` stawia gracza na podłodze), tunel, co-op, drezyna.
- Zrzuty, nagrania i pomiary: `shots_front/f2b/`:
  - `sheet.jpg` i `sheet2.jpg` (bez | z: hala, hala w lewo, WIDE, CLOSE, z zewnątrz), `cmp.jpg` (zbliżenia), `out2.jpg`;
  - `cmp_hall.mp4`, `run_hall_on/off.mp4`, `strip.jpg`;
  - `perf_*.txt`, skrypty `f2b.sh` i `f2b_run.sh`.

**Mechanizm F2b + hala i tunel 1.2** (2026-11-08, 1.7.521; po bramce spike'a — użytkownik: „kierunek jest dobry, kontynuuj”):

- **Kafle przekroju** (`Level3D.set_shells(front, rows)`, `shell_cells`, `front_z`):
  - wiersz stropu r0;
  - podłoga r1 i ciągły lity grunt pod nią w każdej kolumnie, najwyżej `SHELL_DOWN` = 8 wierszy (nie wchodzi w głąb sąsiedniego wnętrza);
  - tylko znaki `#CMmO~`, więc kafle niszczalne zostają;
  - w hali fundament z betonu, w tunelu przekrój skały.
- **Bryły:** skrzynki scalone w ciągi w wierszu (kilkadziesiąt zamiast kilku tysięcy w tunelu), bez cienia.
- **Ciecze:** niecka i tafla cieczy sięgają przodu strefy, więc kałuża oleju w hali leży na płycie aż do jej krawędzi. Przy okazji
  zniknęła przerywana linia na płycie: była krawędzią niecki na 1,1 m.
- **Dach:** blacha dachu (okap), pas dolny wiązarów i dodatkowe płatwie co 1,45 m sięgają przodu strefy. Belki pod stropem
  (`_build_ribs`) też.
- **Rozmieszczenie:** `Front3D.blocked_x` omija kałuże na płycie i belki stropu ±1 m.
  - Test z rozmieszczeniem od razu znalazł oba przypadki: rura stała w oleju (x 114) i 0,43 m od belki w tunelu (x 233).
  - Elementy z przekrojem zaczynają się kołnierzem na płycie, przycięte fizycznie (okno `ywin` w shaderze).
  - Duży element ma plamę okluzji na płycie (warstwa świata, krycie 0,75) i płytkę pod stropem.
- **Test** `test_front.gd`:
  - kafle przekroju tylko lite i tylko w stropie i podłodze, nigdy w pasie gry ani w strefie wydobycia;
  - element na płycie, nie w cieczy;
  - kołnierz przed przodem przekroju;
  - duży element ≥ 1 m od belki;
  - dzieci elementu: światło, plama, płytka.
- **Wydajność** (GPU, 4K HIGH, debug, trzy rundy naprzemiennie, po scaleniu w ciągi):

  | Kadr | bez przekroju [ms] | z przekrojem [ms] |
  |---|---|---|
  | hala | 7,96 / 7,78 / 7,88 | 8,00 / 7,91 / 7,92 |
  | tunel | 6,89 / 6,77 / 7,28 | 6,74 / 7,17 / 7,16 |

  Różnica median w hali +0,04 ms, w tunelu +0,27 ms, ale przedziały się pokrywają (średnie +0,04 ms). Przed scaleniem w ciągi
  tunel kosztował +0,31 ms. Mieści się w budżecie 0,4 ms (zasada 7).
- **Obraz:**
  - **hala:** jak w spike'u, a kałuża oleju jest ciemną taflą do przodu płyty;
  - **tunel:** płyta jest słabo widoczna (tunel jest ciemny z założenia, GDD §8.3), a rury i lampy stoją na niej i dochodzą do
    spodu stropu; ślepy koniec tunelu (kolumna 8) ma płytę z boczną ścianą skały.
- **Nie sprawdzone:** górny pomost hali (`--shotrow` nie stawia gracza na kładce), drezyna, co-op, wstrząs kamery.
- Zrzuty, nagrania i pomiary: `shots_front/f2b2/`:
  - `sheet.jpg` (bez | z: hala, olej, z zewnątrz, tunel ×3, koniec tunelu), `z_oil.jpg`, `z_left.jpg`;
  - `cmp_hall.mp4`, `cmp_tun.mp4`, `strip_tun.jpg`;
  - `perf_*.txt` (przed scaleniem), `perf2_*.txt`, skrypty `run.sh`, `perf2.sh`.

**Luki pilota sprawdzone** (2026-11-08, 1.7.521, ten sam PR #627):

- **Drezyna (błąd, poprawiony).** Tunel drezyny to cały wpis `tunnel`, a tor leży w korycie przed peronem (`Level3D.TRENCH_Z0`–
  `DEPTH_FRONT`, szyny na z 0,38 i 0,98 m, dno o `TRENCH_D` niżej). Pełna płyta przekroju od z = 1,1 m zasłaniała szyny, podkłady
  i koła — drezyna sunęła po betonie. Z rachunku: przy oku 2,2 m nad stopami i 20,2 m od płaszczyzny gry szynę na dnie koryta
  zasłoni każda pełna płyta zaczynająca się bliżej niż ok. 4,5 m, więc nie wystarczy ją cofnąć. Poprawka: w wierszu torowiska
  (`Level3D.in_trench`, pas z `_rail_span`) płyta przekroju leży na wysokości dna koryta aż do `SHELL_Z` — torowisko z podsypką
  biegnie do przodu przekroju, a element nad nim stoi kołnierzem na podsypce (dolna granica `ywin` o `TRENCH_D` niżej).
  Na nagraniu jazdy (`cmp_ride.mp4`) szyny przed drezyną widać tak samo jak bez przekroju.
- **Górny pomost hali (błąd, poprawiony).** Z kładki (wiersz 22) widać górę elementu. Hala nie ma stropu z płyty, tylko blachę
  na płatwiach i wiązarach, więc płytka pod „spodem stropu” (spód kafla dachu) wisiała w powietrzu pod wiązarami. Poprawka: pod
  dachem (`Level3D.roof_purlins`) element stoi na głębokości płatwi (z = 3,7 m — jedyna w `Z_RANGE` z kołnierzem przed przodem
  przekroju; ×1,22) i kończy się na jej spodzie, płytka to obejma pod płatwią. Płatew bliżej kamery (z 5,15) rzutuje się wyżej, więc
  rury nie przecina. Z podłogi hali dach jest poza kadrem, obraz bez zmian.
- **Wstrząs kamery:** wybuch tuż przed graczem (`Feel.shake(5)`) przesuwa kamerę o ok. 30 px w 4K, a rura na z 3,7–5 m przesuwa
  się o ok. 7 px więcej niż plan gry — na nagraniu (`cmp_boom.mp4`, `cmp_boomtun.mp4`) niezauważalne. Słabszy wstrząs dla pierwszego
  planu niepotrzebny (ryzyko z planu zamknięte). Uniform błysku nadal nie zrobiony: rura kilka metrów od wybuchu nie zmienia jasności,
  na nagraniu tego nie widać.
- **Nie sprawdzone:** co-op na dwóch klientach (punkty wygaszania), wydajność po poprawkach (ta sama liczba brył, inne wymiary).
- **Test** `test_front.gd`: element nad torowiskiem stoi na podsypce, obok torowiska na płycie; w hali 1.2 każdy element pod dachem
  ma górę na spodzie płatwi i z płatwi. `--maptest`, `test_structures.gd`, `test_niches.gd` przechodzą.
- **Flagi dev** (`main.gd`): `--shotride` (drezyna zasilona, gracz 1 pompuje), `--shotplat` (z `--shotrow`: kładka jest podłogą),
  `--shotboom=S` (wybuch bez obrażeń przed graczem co S s).
- Zrzuty i nagrania: `shots_front/f2b3/` — `z_ride.jpg` (błąd: z | bez), `z_ride_fix.jpg` (po poprawce: z | bez), `z_plat3.jpg`
  i `z_roof.jpg` (płytka w powietrzu | pod płatwią), `sheet2.jpg` (hala, drezyna, kładka po poprawkach), `cmp_ride.mp4`,
  `cmp_run_hall.mp4`, `cmp_run_plat.mp4` (pierwsze 6 s), `cmp_boom.mp4`, `cmp_boomtun.mp4`; skrypty w `f2b3_*.sh`.

**Odrzucone warianty:**
- **Same płyty podłogi i stropu bez przekroju pod nimi:** wyglądałyby jak balkony wysunięte nad cofniętą skałą, bo dolny przekrój
  zostałby na 1,1 m.
- **Nadproże (belka) z przodu nad pasem gry w warstwie świata:** rura za nim rysowałaby się na nim (kanapka warstw). Nadproże tylko
  w `LAYER_FRONT`, a i tak niewidoczne, bo strop wypada poza kadrem.
- **Przekrój na 5,6 m w całej mapie:** zmienia krawędź gruntu z trawą, las, wody i niszczenie na każdej mapie. Za duży zakres
  jak na pilota. Wrócić do tego, jeśli strefy się sprawdzą.

### F3 — katalog i mapy (po bramce)

- Las: pień sosny, pień brzozy, martwy pień, zwisająca gałąź, wysoka paproć i trawa przy dolnej krawędzi.
- Wnętrza: rura pionowa, wiązka kabli ze stropu, dźwigar stalowy, łańcuch, krata. W kryjówce i hali stacji to „ucięty przód
  budynku”, jak w grach z przekrojem.
- Zabudowania i stacja: słup energetyczny z przewodami, płot, siatka.
- Po jednym PR na mapę: 1.2, 1.1, 1.3, B1, kryjówka. Każda mapa: zrzuty, nagranie, pokrycie, GPU, `test_front.gd`.
- Wnętrza i podziemia dostają przekrój z F2b (strefa `shell` przy każdym wpisie). W katalogu dochodzą elementy, które opierają się
  o płytę: filar hali, pierścień tubingu w tunelu, pion rur z kołnierzem w podłodze.

### F4 — rozmycie bliskiego planu (sprawdzone 2026-11-08: natywne nie działa w warstwie graczy, odłożone)

- Rozmycie głębi ostrości tylko dla bliskiego planu na kamerze graczy (`CameraAttributesPractical.dof_blur_near_*`): gracze
  stoją 20,2 m od kamery i zostają ostrzy, pierwszy plan przy 15–17 m się rozmywa. Sprawdzić koszt w 4K i krawędzie
  na przezroczystym tle `VpActors`. Zamiennik: miękkie tekstury i mipmapy przesunięte w górę.

## Kolejność i rozmiar

| Etap | Co | Rozmiar | Wersja |
|---|---|---|---|
| F0 | zrzuty, nagranie, pomiar, spike A / B | 0,5–1 d | zrobione 2026-11-08, bez wersji: wariant A |
| F1 | `front3d.gd`, shader, dane, ustawienie, test | 1–1,5 d | 1.7.519 |
| F2 | pilot: hala stacji i tunel 1.2 + A/B + bramka; las 1.2 z kontrą po bramce | 0,5–1 d | 1.7.519 (ten sam PR) |
| F2b | przekrój budynku: spike w hali, mechanizm, hala i tunel 1.2 | 2 d | 1.7.521 |
| F3 | katalog i mapy | 2–3 d | po jednym PR na mapę |
| F4 | rozmycie bliskiego planu | 0,5 d | natywne DOF nie działa w `VpActors` (1.7.520); tylko własny przebieg, jeśli bramka zażąda |

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
4. **Rozmycie (F4):** sprawdzone w 1.7.520 — natywne rozmycie nie działa w warstwie graczy; własny przebieg tylko na żądanie bramki.

Przed spike'iem F2b (5–7 rozstrzygnięte 2026-11-08 zgodnie z rekomendacją):

5. **Uskok przekroju na powierzchni** (hala to budynek na gruncie):
   - polecam wysunąć tylko budynek z fundamentem (betonowy cokół, widoczna ściana boczna);
   - alternatywa: wysunąć także grunt z trawą o zapas kolumn; uskok wtedy w trawie, ale zmienia się `build_front_edge`;
   - alternatywa: bez przekroju na powierzchni, tylko pod ziemią.
6. **Głębokość przekroju:**
   - polecam `SHELL_Z` = 5,6 m przy obecnych z 3,5–5 m rur;
   - alternatywa: rury bliżej (z 2,5–3,5 m, paralaksa ×1,14–1,21) i przekrój na 4 m. Pas płyty o około 30% węższy, ale słabszy efekt.
7. **Filar hali w katalogu teraz** (w spike'u obok rur) **czy w F3:** polecam w F3 — spike ma sprawdzić samo zakotwienie.
