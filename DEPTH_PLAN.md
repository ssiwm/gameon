# Plan: światło w głębi i wnęki w ścianach wnętrz

Status: **plan z 2026-11-06, decyzje 1–3 podjęte tego samego dnia, N0 zrobione; w grze nic nie wdrożone.** Etap po analizie głębi świata
(`C:\deadair87\reports\world-depth-recommendations-2026-11-04.md`, punkty 1 i 3 tego raportu robione razem).
Stan odniesienia: `main` 1.7.506 (b7c11e3).

## Werdykt

Wnętrza (hala stacji i tunel drezyny na 1.2, podziemia 1.1, cała 1.3, B1, kryjówka) mają za płaszczyzną gry jedną płaską ścianę
2,4 m w głąb (`Level3D.DEPTH_BACK`, płyty 0,3 m z `build_level` → `walls`). Nic jej nie oświetla poza światłami przy graczach,
więc na zrzutach (`C:\deadair87\shots_cave\cave_z1_m2_0.png`, `cave_z1_m1_1.png`) tło wnętrza jest jednolicie czarne:
oko nie ma czym odczytać odległości. Sama głębsza geometria nic nie da, bo w ciemności jej nie widać. Potrzebne jest
**światło za płaszczyzną gry, które nie zmienia ciemności przy postaciach** (GDD §8.3).

Zapas jest: release 1.7.505 na 1.2 (4K, HIGH, RTX 3080) to 60 kl./s przy GPU 8,8 ms z 16,7 ms (pomiar 2026-11-06).

## Zasady (obowiązują każdą wnękę)

1. **Światło wnęki oświetla tylko wnękę.** Bryła wnęki leży na warstwie świata i nowej warstwie `LAYER_NICHE` (128).
   Światło wnęki ma `light_cull_mask = LAYER_NICHE`, a jego zasięg kończy się najpóźniej na płaszczyźnie tylnej ściany
   (z ≤ −DEPTH_BACK; w N1 `LIGHT_EDGE = 0`, bo maska i tak odcina wszystko poza bryłą wnęki). Ten sam wzór działa już w lesie: `MoonRim` świeci tylko na `LAYER_FOREST`.
   Wrogowie, gracze, podłoga i ściana przy płaszczyźnie gry nie dostają z wnęki ani odrobiny światła.
2. **Bez wpływu na symulację.** Wnęka to czysta oprawa: nie ma kolizji, nie zmienia wzroku wrogów, nie jest `GameLight`,
   nie budzi ćm i nie liczy się do Uwagi. Mapa ASCII i nawigacja się nie zmieniają.
3. **Mgła wolumetryczna ignoruje `light_cull_mask`.** Światło wnęki ma `light_volumetric_fog_energy = 0` albo zasięg,
   który nie dosięga płaszczyzny gry. Smugę w samej wnęce można dać lokalnym `FogVolume` tylko w jej wnętrzu.
4. **Sylwetki to decyzja, nie przypadek.** Wróg przed oświetloną wnęką rysuje się ciemną sylwetką. Jasność wnętrza wnęki
   ma górny próg (luminancja ekranu do ustalenia w N0), żeby sylwetka była słaba. Wnęk nie stawia się tam, gdzie mapa
   celowo chowa wroga (zasadzki Ślepca, gniazda ćm).
5. **Nie zderzać się z resztą tylnej ściany.** W komórkach wnęki nie ma płyt `walls`, pilastrów `_build_ribs`, stóp
   `_build_wall_feet`, dekali tła ani słupów (`POST_Z`, `TRUNK_Z`). Wnęka nie leży za oknem `|`, lampą `I`, stemplem `!`,
   strefą zawału `^` ani strefą wydobycia — to sprawdza test.
6. **Taniej niż 0,5 ms GPU na kadr** przy HIGH 4K, z 1–2 wnękami w kadrze. LOW: bez świateł, sama emisja żarówek.
7. Tylko 3D (CLAUDE.md): modele, światła i mgła w scenie, nic rysowanego w 2D.

Lekcja z przeszłości: plan pierwszy z `ATMOSPHERE_PLAN.md` F4 wycofano, bo dawał prostokątne ciemne bryły przy brzegach kadru.
Wnęka ma więc nieregularny brzeg (futryna, wykruszony tynk, rury wchodzące w otwór), a nie gołe prostokątne cięcie.

## Etapy

### N0 — punkt wyjścia (pomiar i zrzuty, bez zmian w grze)

- Zrzuty hali stacji 1.2 i tunelu drezyny w 5 kolumnach, noc bez pogody, burza i mgła, WIDE / NORMAL / CLOSE.
  Przez `--host --nohud --mission=z1_m2 --shotat=KOL --shot=…`, profil QA (`override.cfg`).
- `--perf=15 --perfreport` w tych samych miejscach na eksporcie release.
- Luminancja ekranu przy graczu i 6–9 m od niego (jak przy strojeniu ciemności, GDD §8.3). Te liczby nie mogą się zmienić po N2.
- Wybór kolumn pilota na zrzucie (propozycja niżej).

**Wyniki N0 (2026-11-06, `main` b7c11e3, ze źródeł w oknie, 4K HIGH, gracz w kolumnie 89 na parterze hali).**
Zrzuty, arkusz i strefy pomiaru: `C:\deadair87\shots_depth\n0\` (`n0_sheet.jpg`, `n0_strefy.png`); seria `shots_depth\series.sh`,
pomiar `shots_depth\lum.py` (`--shotat=89 --shotrow=23`, ok. 192 px na kafel).

- Hala nie jest cała czarna: lampa `I` (kolumna 82) oświetla ceglaną ścianę do ok. kolumny 89. Dalej w prawo, za skrzynią
  i generatorem, ściana jest czysto czarna (luminancja 0,0000). Wnęka 88–91 stoi na granicy: z lewej słabe światło lampy, z prawej czerń.
- Pogoda prawie nie zmienia wnętrza (deszcz pada tylko pod niebem). WIDE pokazuje więcej ściany, CLOSE mniej, układ ten sam.
- Luminancja liniowa (średnia w strefie):

| wariant | przy graczu | 6–9 m w lewo | podłoga przed wnęką | ściana w miejscu wnęki | ściana na prawo od wnęki |
|---|---|---|---|---|---|
| noc bez pogody | 0,0107 | 0,0060 | 0,0293 | 0,0040 | 0,0000 |
| burza | 0,0102 | 0,0049 | 0,0279 | 0,0036 | 0,0000 |
| mgła | 0,0103 | 0,0050 | 0,0276 | 0,0038 | 0,0000 |
| deszcz | 0,0104 | 0,0060 | 0,0285 | 0,0038 | 0,0000 |
| MEDIUM | 0,0102 | 0,0057 | 0,0283 | 0,0038 | 0,0000 |
| LOW | 0,0092 | 0,0047 | 0,0265 | 0,0034 | 0,0000 |

  Po N2 strefy „przy graczu”, „6–9 m” i „podłoga przed wnęką” mogą zmienić się najwyżej o ±2%.
- **Próg sylwetek (decyzja 2):** średnia luminancja otworu wnęki najwyżej ok. 0,02, czyli tyle, ile ma dziś podłoga przy graczu
  (0,029 na samym przodzie podłogi). Wróg na takim tle jest ciemniejszy od tła, ale tło nie jest jaśniejsze od miejsca, gdzie stoi gracz.
  Do potwierdzenia na zrzucie z Trzoskiem przed wnęką.
- Wydajność (ze źródeł, debug): 60 kl./s, GPU 7,95 ms (p95 9,65), view3d 4,72 ms, `_process` 7,84 ms. Budżet pilota: GPU ≤ 8,45 ms
  w tym samym pomiarze (`--shotat=89 --perfrow=23 --perf=15 --perfreport`).

### N1 — mechanizm wnęki (`scripts/niches3d.gd`)

- Dane w pliku mapy, obok `BACKDROP`: `const NICHES := [{"kind": "doorway", "c0": 88, "c1": 91, "r0": 23, "r1": 25, "d": 8.0, "lit": "bulb"}]`.
  Ręczne wpisy, nie generator: pilot potrzebuje kontroli kadru.
- `Level3D.build_level` pomija płyty `walls` w prostokącie wnęki. `niches3d.gd` buduje otwór z futryną, podłogę, strop, boki
  i tylną ścianę wnęki z materiałów ściany i betonu, z cieniowaniem w głąb (jak `shade` w lesie).
- Światło: `OmniLight3D` (albo `SpotLight3D` z żarówki w dół) na `LAYER_NICHE`, zasięg w obrębie wnęki, plus żarówka
  z emisją (`unshaded`, jak lampki `backdrop3d.gd`). Cień światła wnęki tylko na HIGH i tylko, jeśli pomiar w N2 go uzasadni.
- Kamera świata nie potrzebuje `LAYER_NICHE` w `cull_mask`: bryła wnęki leży też na warstwie świata (1), więc ją widzi i oświetlają ją światła mapy.
- Test `tools/test_niches.gd` (headless, dopisany do CLAUDE.md i CI; w planie `--nichetest`): wnęka nie zachodzi na zasady z punktu 5, światło nie sięga z > −DEPTH_BACK,
  maska światła to tylko `LAYER_NICHE`, płyty ściany w otworze usunięte, a poza nim nietknięte. `--maptest` bez zmian (PASS).

### N2 — pilot: jedna wnęka w hali stacji 1.2

- **Miejsce: kolumny 88–91, wiersze 23–25** (podłoga w wierszu 25; przesunięte z 85–88 po zrzutach N0). To parter hali pod kratą `=`
  z wiersza 22, między kałużą oleju (kolumny 84–87) a skrzynią `k` (kolumna 92), na granicy światła lampy `I` (kolumna 82). Gracz widzi halę w pierwszej minucie misji,
  a zrzuty N0 pokazują tu prawie czarną ścianę. Otwór ma 5,2 × 3,9 m. Malowana strzałka na ścianie (kolumny 89–90) przenosi się obok otworu.
- **Treść:** korytarz zaplecza 8 m w głąb z dwiema żarówkami (na 3 i 7 m), drzwi uchylone na końcu, rura i kable
  wzdłuż stropu. Daleka żarówka słabsza i chłodniejsza, bliska cieplejsza: dwa punkty światła dają oku skalę odległości.
- **A/B:** te same kadry co w N0 (noc, burza, mgła; WIDE / NORMAL / CLOSE; HIGH / MEDIUM / LOW), krótkie nagranie przejścia
  przez halę (`trailer/capture.sh`), `--perfreport` na release, luminancja przy graczach, Trzosek ustawiony przed wnęką
  (sylwetka). Użytkownik ogląda pilota w grze ze skrótu „Dead Air 87 (release)”.
- **Kryteria przyjęcia:** wnęka czytelnie „idzie w głąb” w ruchu kamery; luminancja przy graczach bez zmian (±2%);
  GPU ≤ +0,5 ms; brak migotania, szwów i prostokątnych krawędzi; sylwetka wroga zauważalna dopiero z bliska.
- **Bramka:** decyzja użytkownika po obejrzeniu. Bez niej nie ma N3.

### Wyniki N1–N2 (2026-11-07, `feat/depth-niches`, 1.7.507)

Wnęka: korytarz 8 m, ościeża z wyszczerbioną krawędzią i nadproże z betonu, rura i korytko pod stropem, beczka i skrzynia,
uchylone drzwi w ścianie końcowej, dwie żarówki (bliska ciepła na 3 m, 1,8; daleka chłodna na 7 m, 1,0; zasięg 3 m).
Bańki wiszą 1 m pod nadprożem, bo w kadrze kamery nadproże zasłaniało bliską żarówkę. Luminancja liniowa (te same kadry co N0, 4K):

| Kadr | przy graczu N0 → N2 | 6–9 m | podłoga przed wnęką | otwór wnęki |
|------|------|------|------|------|
| noc bez pogody | 0,0649 → 0,0672 (+3,5%) | 0,0060 → 0,0061 | 0,0293 → 0,0294 | 0,0040 → 0,0090 |
| burza | 0,0637 → 0,0657 (+3,1%) | 0,0049 → 0,0054 | 0,0279 → 0,0279 | 0,0036 → 0,0091 |
| mgła | 0,0646 → 0,0655 (+1,4%) | 0,0050 → 0,0053 | 0,0276 → 0,0276 | 0,0038 → 0,0056 |
| deszcz | 0,0642 → 0,0665 (+3,6%) | 0,0060 → 0,0057 | 0,0285 → 0,0286 | 0,0038 → 0,0092 |
| MEDIUM | 0,0617 → 0,0625 (+1,3%) | 0,0057 → 0,0055 | 0,0283 → 0,0284 | 0,0038 → 0,0081 |
| LOW (same bańki) | 0,0540 → 0,0542 (+0,4%) | 0,0047 → 0,0050 | 0,0265 → 0,0265 | 0,0034 → 0,0041 |

- **Światło nie wychodzi z wnęki:** podłoga przed wnęką bez zmian w każdym kadrze; 6–9 m w szumie (burza i mgła mają losowe błyski).
- **Przy graczu +3–3,6% (kryterium ±2% przekroczone) to bloom, nie światło.** Z `--nofx` ta sama strefa zmienia się o +0,4%.
  Bloom `horror_fx` rozmywa ekran (mipy) i odcina próg 0,16, więc jaśniejsze tło obok żółtego kombinezonu podbija poświatę na postaci.
  Ciemność przy graczu (GDD §8.3) się nie zmienia, zmienia się aureola. Słabsza bańka (`BULB_GLOW`) tego nie zbiła.
- **Próg sylwetek:** otwór 0,009 — poniżej progu 0,02 i poniżej ściany przy lampie `I` (0,0129). Trzosek w kolumnie 89 przed wnęką
  (zrzut z tymczasową flagą, niecommitowaną) nie robi się ciemną sylwetką: jest nawet nieco jaśniejszy od tła (0,0023 przy tle 0,0003–0,0009;
  bez wnęki 0,0012 przy 0,0001–0,0002), bo za nogami wroga dolna część otworu zostaje ciemna. Sylwetki są słabe, jak w decyzji 2.
- **Wydajność (debug, 4K HIGH, dwa przebiegi A/B):** GPU 7,73 → 7,83 ms i 7,86 → 7,99 ms (+0,10 / +0,13 ms; p95 +0,2 / +0,9 ms),
  render_cpu +0,05–0,09 ms, draw calls 319 → 378. **Release** (eksport z gałęzi, A/B flagą `--noniches`, 3 + 3 przebiegi na zmianę):
  z wnęką 7,10 / 7,44 / 7,91 ms (śr. 7,48), bez 7,00 / 7,76 / 7,89 ms (śr. 7,55) — różnica w szumie, 60 kl./s we wszystkich. W budżecie (+0,5 ms).
- **Nagranie przejścia przez halę** (Movie Maker, 1920×1080, `--shotrun` od kolumny 74, z wnęką i bez): w ruchu kamery wnęka czyta się
  jako oświetlony korytarz w głąb, bez migotania i szwów.
- **Cień (decyzja 3):** w korytarzu nie ma ruchomych brył, a rekwizyty stoją blisko ścian, więc brak cienia nie razi na zrzutach.
  Rekomendacja: zostać bez cienia.
- Zrzuty, arkusze i nagranie: `C:\deadair87\shots_depth\n2\` (`n2_porownanie.jpg`, `n2_sylwetka.jpg`, `n2_przejscie_hali.mp4`).

### N3 — katalog wnęk i rozmieszczenie (po bramce)

Rodzaje: `doorway` (zaplecze z żarówką), `corridor` (korytarz 10–15 m z lampami co 4 m, najmocniejszy efekt),
`grate` (pomieszczenie za kratą, cienie prętów), `shelf` (płytka wnęka 1–1,5 m z regałem, bez światła),
`drift` (boczna sztolnia w tunelu z daleką lampą górniczą).
Rozmieszczenie: 1.2 hala i tunel (np. między słupami `w` w kolumnach 187–193), podziemia 1.1, 1.3, B1, kryjówka.
Najwyżej 1–2 oświetlone wnęki w jednym kadrze i odstęp ok. 30 m, żeby nie powstał rytm „co kafel to wnęka”.
Każda mapa: zrzuty, `--perfreport`, luminancja, `--nichetest`.

### Wyniki N3 na 1.2 (2026-11-07, `feat/niches-catalog`, 1.7.508)

- Katalog w `niches3d.gd` (`KINDS`): `doorway` (d 8 m, „bulb”), `corridor` (12 m, „cage”: lampy w koszach co 4 m na zmianę po bokach,
  boczne przejście w połowie, zamknięte drzwi na końcu), `grate` (4,5 m, „bulb”: pręty co 0,14 m w jednym `MultiMesh`, szafka, regał,
  kanister, zimna świetlówka na 70% głębokości), `shelf` (1,2 m, bez światła: regały pod ścianą końcową, kanister, opona),
  `drift` (10 m, „mine”: odrzwia co 2 m, skalne ściany i strop z odcinków o losowym wcięciu, tory na podkładach w `MultiMesh`,
  lampa górnicza 1,6 m przed czołem). Walidacja sprawdza rodzaj, dozwolone światło i najmniejszą głębokość rodzaju.
- Rozmieszczenie na 1.2 (6 wnęk): zaplecze w hali stacji (88–91, pilot), w tunelu drezyny (wiersze 48–50) sztolnie 107–109 i 195–197,
  korytarz 155–157 i regał 259–261, w dolnej hali krata 211–213 (wiersze 37–39). Odstęp ≥ 40 kolumn między oświetlonymi wnękami,
  ≥ 10 kolumn od Ślepców `L` i gniazd ćm `Z` (zasada 4). Uwaga: pilot w hali stoi 6–7 kolumn od dwóch Ślepców — zostawiony, bo przyjęty w bramce N2.
- **Lekcja kadru:** kamera patrzy z oka nad środkiem kadru, więc we wnęce widać więcej podłogi niż stropu. Lampy zawieszone pod stropem
  chowają się za nadprożem (korytarz) albo za stropnicami bliższych odrzwi (sztolnia) — wszystkie wiszą ok. 1 m pod stropem
  (w sztolni na 60% wysokości odrzwi, na długim haku).
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`): podłoga przed korytarzem 0,0021 → 0,0021, przed sztolnią 0,0017 → 0,0018;
  przy graczu w kadrze korytarza 0,0648 → 0,0649; otwór korytarza 0,0003 → 0,0097 (próg 0,02), otwór sztolni 0,0003 → 0,0016
  (świeci tylko jej koniec). GPU w kadrze korytarza 6,67 / 7,33 ms z wnękami i 6,77 / 7,68 ms bez (szum), render_cpu +0,06–0,13 ms,
  wywołania rysowania 199 → 295.
- Zrzuty: `shots_depth/n3/`.

### N4 — światło w głębi poza wnękami (opcjonalnie)

Tylko jeśli N3 się sprawdzi: dalekie okna i lampy za kratami w ścianach szybów, poświata z głębi tunelu na końcu kadru.
Zasada 1 obowiązuje tak samo.

## Kolejność i rozmiar

| Etap | Co | Rozmiar | Wersja |
|---|---|---|---|
| N0 | zrzuty, pomiar, wybór kolumn | 0,5 d | bez wersji (wyniki w tym pliku) |
| N1 | `niches3d.gd`, dane mapy, wycięcie ściany, `--nichetest` | 1 d | PR, podbicie wersji |
| N2 | pilot w hali 1.2 + A/B | 0,5–1 d | ten sam PR albo następny |
| N3 | katalog i mapy | 2–3 d | po jednym PR na mapę |
| N4 | światło w głębi poza wnękami | do oceny | — |

## Ryzyka

- **SSIL** we wnętrzach może przenieść odrobinę światła wnęki na podłogę przy otworze (efekt w przestrzeni ekranu nie zna maski).
  Sprawdza to pomiar luminancji w N2. Jeśli to za dużo: mniejsza energia światła wnęki, reflektor skierowany w głąb zamiast
  żarówki świecącej na wszystkie strony albo ciemniejsza podłoga przy otworze.
- **Mgła głębi** (`Environment.fog`) może rozjaśnić daleką część korytarza. Jeśli tak, materiał tylnej ściany wnęki dostaje `fog_disabled`.
- **Perspektywa kamery** (oko 2,2 m nad środkiem kadru, przesunięta projekcja) odsłania strop wnęki bardziej niż podłogę.
  Strop musi mieć detal, nie pustą płytę.
- **Zniszczenia D1–D5** dokładają elementy przy ścianie (gruz, dziury w deskach). Test z N1 pilnuje, że wnęka ich nie przecina.

## Decyzje (2026-11-06)

1. Pilot w **hali stacji 1.2** (kolumny 88–91, wiersze 23–25). Tunel drezyny dopiero w N3.
2. Sylwetki wrogów na tle wnęki **słabe, z progiem jasności** wnętrza wnęki (zasada 4). Próg ustala pomiar w N0/N2.
3. Cień światła wnęki **dopiero po pomiarze w N2**; pilot startuje bez cienia.

## Decyzje (2026-11-07, bramka N2)

4. Pilot przyjęty. Poświata przy graczu (+3–3,6% przy wnęce, bloom `horror_fx`, a nie światło wnęki) zostaje jako efekt optyczny.
5. Wnęki zostają **bez cienia**.
6. Przechodzimy do N3: katalog rodzajów i rozmieszczenie, po jednym PR na mapę (pierwszy: 1.2).
