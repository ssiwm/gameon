# Plan: światło w głębi i wnęki w ścianach wnętrz

Status: **N0–N3 w `main` (do 1.7.512, 19 wnęk na pięciu mapach); N4 — pilot okien i kratek w `main` (1.7.513), bramka przyjęta
2026-11-07: okna i kratki idą na inne mapy; scalone bryły i 1.2 w 1.7.514, 1.3 w 1.7.516, 1.1 w 1.7.517, kryjówka w 1.7.518 — N4 zamknięte.** Etap po analizie głębi świata
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

### Wyniki N3 na 1.1 (2026-11-07, `feat/niches-z1m1`, 1.7.509)

- Tylna ściana galerii kopalni 1.1 to ten sam mur co w budynkach, więc pasuje cały katalog. Trzy wnęki: `corridor` 268–270
  (wiersze 31–33, górna galeria, 22 kolumny od gniazda ćm), `shelf` 246–248 (wiersze 41–42, dolna galeria, 5 kolumn od lampy misji `I` —
  regał widać w jej świetle, bo bryła wnęki leży też na warstwie świata), `drift` 285–287 (wiersze 40–42, d 8 m, 14 kolumn od gniazda,
  dwie kolumny przed przegrodą z desek `%`, z dala od strefy wydobycia 296–305). Powierzchnia 1.1 nie ma tła `b` — tam wnęk nie ma.
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`): podłoga przed korytarzem 0,0002 → 0,0002, przed sztolnią 0,0005 → 0,0005,
  przed regałem 0,0216 → 0,0202 (głębia zamiast oświetlonej ściany); otwór korytarza 0,0003 → 0,0112 (próg 0,02), sztolni 0,0001 → 0,0013,
  regału 0,0143 → 0,0122 (wnęka ciemniejsza od ściany przy lampie). Przy graczu ±3% — wrogowie poruszają się tuż obok w obu wariantach.
  GPU w kadrze korytarza 7,01 / 7,24 ms z wnękami, 7,16 / 7,04 ms bez (szum); render_cpu +0,07–0,12 ms; wywołania rysowania 241 → 332.
- Zrzuty: `shots_depth/n3_z1m1/`.

### Wyniki N3 na 1.3 (2026-11-07, `feat/niches-z1m3`, 1.7.510)

- Pięć wnęk: `doorway` 19–21 (wiersze 23–25, zaplecze posterunku przy starcie), `grate` 134–136 (wiersze 23–25, parter Składu),
  a w niskim tunelu podziemi (wiersze 37–39, podłoga w wierszu 40) `drift` 51–53 (d 8 m, 14 kolumn od Ślepca), `shelf` 100–102
  (wiersze 38–39, u dołu środkowego szybu) i `corridor` 160–162 (tuż za trzecim szybem, ponad 17 kolumn od gniazd ćm).
  Oświetlone wnęki w tunelu stoją ponad 100 kolumn od siebie, strefa wydobycia (kolumny 1–5) daleko.
- Antresola Składu (wiersz 22) to kładka `=`, a walidacja wymaga litej podłogi pod otworem — na antresoli wnęki nie ma.
  Z tego samego powodu odpadają górne poziomy sal podziemi (kładki), a dno trzech z czterech sal leży bliżej niż 10 kolumn od gniazd ćm
  albo Ślepców.
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`): podłoga przed wnęką bez zmian przy wszystkich pięciu (0,0018–0,0073);
  otwór zaplecza 0,0002 → 0,0056, kraty 0,0005 → 0,0037, sztolni 0,0001 → 0,0024, regału 0,0006 → 0,0008, korytarza 0,0002 → 0,0096
  (próg 0,02). Przy graczu ±1%, poza kratą (−6%): w tym kadrze Rzeźnik i Trzosek stoją na graczu i ruszają się między przebiegami.
  GPU w kadrze korytarza 6,57 / 6,87 ms z wnękami, 6,55 / 6,91 ms bez (szum); render_cpu +0,07–0,09 ms; wywołania rysowania 228 → 320.
- Zrzuty: `shots_depth/n3_z1m3/`.

### Wyniki N3 na B1 (2026-11-07, `feat/niches-z1b1`, 1.7.511)

- Hala B1 ma tło `b` od stropu do podłogi, ale lita podłoga jest tylko na brzegach — basen (kolumny 28–110) to woda `~`, a kładki
  nad nim to `=` i `-`. Do tego fala przypływu Pijawki zalewa basen ± `SURGE_PAD` (56 px, 3,5 kafla), więc wnęki stoją poza
  kolumnami ok. 24–114. Trzy wnęki (wiersze 28–30, podłoga w wierszu 31): `doorway` 10–12 na zachodnim brzegu między miejscami
  startu (pierwszy kadr misji), `grate` 116–118 i `shelf` 132–134 (wiersze 29–30) na wschodnim brzegu przy ewakuacji.
  Ślepców i gniazd ćm na B1 nie ma.
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`). Przy zapleczu i regale kamera opiera się o brzeg mapy i gracz nie stoi
  w środku kadru, więc strefy wzięte z obrysu różnicy obu zrzutów. Otwór zaplecza 0,0000 → 0,0137, kraty 0,0001 → 0,0052,
  regału 0,0036 → 0,0038 (próg 0,02); podłoga przed kratą 0,0030 → 0,0030, przed regałem 0,0052 → 0,0052, pod zapleczem
  0,0009 → 0,0012 (próg otworu z podłogą wnęki w pasie pomiaru). Przy graczu w kadrze kraty 0,0576 → 0,0577.
  GPU w kadrze startu 7,21 / 8,00 ms z wnękami, 8,05 / 8,04 ms bez (szum); render_cpu +0,15 ms; wywołania rysowania 263 → 325.
- Zrzuty: `shots_depth/n3_z1b1/`.

### Wyniki N3 w kryjówce (2026-11-07, `feat/niches-hub`, 1.7.512)

- Kryjówka ma tło `b` na wszystkich trzech poziomach, ale górny i środkowy zajmują meble z `hub_decor.gd` (grupy co ok. 6 kafli
  w odstępach między znacznikami stanowisk), tablice wyników i odprawy, gabloty, okno radiostacji i szyby z kratami `=` — tam wnęki
  nie ma. Dolny poziom nie ma losowych mebli (tylko rekwizyty `HUB_PROPS`), więc dwie wnęki stoją na dole (wiersze 27–29, podłoga
  w wierszu 30): `corridor` 16–18 w maszynowni między generatorem a sprężarką (rury z `HUB_PROPS` biegną nad otworem) i `grate` 49–51
  w magazynie obok drzwi strzelnicy (54) — 34 kolumny od siebie, nigdy w jednym kadrze.
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`): krata — otwór 0,0004 → 0,0054, podłoga 0,0060 → 0,0060, gracz 0,1260 → 0,1265.
  Korytarz — podłoga przed nim 0,0530 → 0,0581 (+10%), gracz 0,1938 → 0,2101 (+8%): w ciepło oświetlonej kryjówce oświetlony korytarz
  odbija się w SSIL na podłodze i dokłada poświaty (por. decyzja 4); ciemnej sylwetki nie ma, bo ściana wokół otworu jest jasna.
  GPU w kadrze maszynowni 9,92 / 9,96 ms z wnękami, 9,89 / 9,89 ms bez (+0,05 ms, szum); render_cpu +0,17 ms; wywołania rysowania
  300 → 444 — więcej niż na misjach, bo lampy kryjówki rzucają cień i bryła wnęki (warstwa świata) trafia też do przebiegów cienia.
- Etap N3 zamknięty: 19 wnęk na pięciu mapach (1.1: 3, 1.2: 6, 1.3: 5, B1: 3, kryjówka: 2).
- Zrzuty: `shots_depth/n3_hub/`.

### N4 — światło w głębi poza wnękami

Zaczęte 2026-11-07 po N3. Wnęki z N1–N3 stoją na podłodze, więc zostawiają puste wysokie ściany (hala B1 ma mur od wiersza 12
do 30, szyby i niskie tunele 1.3 — ściany przy stropie). N4 dokłada **rodzaje ścienne** w tym samym `niches3d.gd` (ta sama warstwa
`LAYER_NICHE`, te same zasady 1–7, ten sam test):

- `window` — wysokie okno do oświetlonego pokoju za ścianą: rama ze szczeblami co ≤ 0,9 m i ślemieniem, szyby tylko w części pól
  (reszta wybita), parapet; pokój szerszy od okna o 0,9 m z każdej strony, podłoga 1 m pod parapetem, strop 0,7 m nad nadprożem
  (boki i strop chowają się za murem tła); szafa sterownicza z lampkami (świecą też na LOW), szafka, rura; lampa `tube` (zimna)
  albo `bulb` (ciepła) w 3/4 głębokości pokoju, tuż pod nadprożem.
- `vent` — kratka wentylacyjna w jednym kaflu: mur wokół kratki 0,9 × 0,62 m, rama, ukośne żaluzje, blaszany kanał w głąb,
  wentylator (łopatki rysują się na tle lampy) i lampa `lamp` na końcu kanału.
- Walidacja: pod otworem ściennym leży mur tła `b` (nie podłoga ani kładka), wokół okna i nad nim też `b` (pokój jest większy od otworu;
  od 1.7.516 także lity kafel — beton, skała — bo jego bryła sięga do ściany tła i tak samo zasłania pokój; powietrze, kładka i ciecz
  odpadają), kratka może mieć 1 × 1 kafel, okno najmniej 2 × 2.
- „Poświata z głębi tunelu na końcu kadru” z pierwotnego szkicu jest już w N3: `corridor` i `drift` mają światło tylko w głębi.

### Wyniki pilota N4 (2026-11-07, `feat/depth-n4`, 1.7.513)

- Pilot: dwa okna dyspozytorni pomp wysoko nad basenem B1 — `window` 50–53 (`tube`) i 78–81 (`bulb`), wiersze 24–25, nad lukami
  między wysokimi kładkami (głowy graczy na kładkach nie wchodzą w okno) — i `vent` w kolumnie 150, wiersz 36, pod stropem niskiego
  tunelu 1.3 przed trzecim szybem (11 kolumn od gniazda ćm). Okna widać z niskich kładek i z brzegu, kratkę z tunelu.
- **Lekcja:** pierwsza wersja lampy okna wisiała w połowie głębokości pod stropem pokoju — zasięg (do ściany tła) kończył się
  dokładnie na tylnej ścianie, więc była czarna, a lampę zasłaniało nadproże (oko kamery jest niżej niż wysokie okno). Lampa stoi
  teraz w 3/4 głębokości (zasięg 3 m, tylna ściana metr od lampy), 0,55 m pod górną krawędzią otworu.
- Pomiar (debug, 4K HIGH, z wnękami i z `--noniches`): okno ze świetlówką 0,0000 → 0,0142, z żarówką 0,0000 → 0,0131 luminancji
  liniowej (próg 0,02; energię zbito z 2,0 do 1,2 i 0,9, bo przy 2,0 wychodziło 0,030 i 0,040), gracz na kładce 0,0522 → 0,0534
  i 0,0581 → 0,0584; kratka — otwór 0,0031 → 0,0041, podłoga tunelu bez zmian. **Poprawka (1.7.514):** 0,0041 to średnia
  strefy pomiaru znacznie większej od kratki; w samym otworze kratki (ok. 115 × 80 px w 4K, obrys różnicy zrzutów) wychodzi
  0,0000 → 0,085. Kratka czyta się więc jak mała lampa pod stropem — próg 0,02 pilnuje sylwetek przed otworami na wysokości
  postaci, a kratka wisi 3–4 kafle nad podłogą tunelu, poza głowami.
- Wydajność w kadrze pierwszego okna (cztery rundy): GPU 7,42 / 7,18 / 7,15 / 7,12 ms z oknem, 7,12 / 6,81 / 7,05 / 6,69 ms bez —
  średnio +0,30 ms (zasada 6: < 0,5 ms); render_cpu +0,12 ms; wywołania rysowania 182 → 276. Okno kosztuje więcej niż wnęka
  na podłodze (szyby przezroczyste, ok. 40 brył ramy, lampek i pokoju). Jeśli N4 pójdzie na inne mapy: szczeble i lampki
  w `MultiMesh`, szyby w jednej siatce.
- Zrzuty: `shots_depth/n4/`.
- **Bramka N4 (przyjęta 2026-11-07):** okna i kratki idą na inne mapy (hala stacji 1.2, Skład 1.3, szyby 1.1 i 1.3, kryjówka),
  po jednym PR na mapę; najpierw scalenie brył, żeby koszt okna nie rósł z liczbą okien.

### Wyniki N4 na 1.2 i scalenie brył (2026-11-07, `feat/n4-merge-z1m2`, 1.7.514)

- **Scalenie:** `Niches3D._merge_boxes` po zbudowaniu wnęki łączy wszystkie bryły `BoxMesh` z tym samym materiałem w jedną siatkę
  (`SurfaceTool.append_from` z transformacją względem korzenia wnęki); walce, szyby z przezroczystością i lampy zostają osobno,
  lampki szafy sterowniczej biorą trzy wspólne materiały zamiast siedmiu. Materiały PBR są triplanarne w przestrzeni świata, więc
  obraz się nie zmienia (zrzuty kontrolne B1, 1.3, 1.2 i kryjówki: średnia różnica 0,01–0,8 / 255 — deszcz i cząsteczki).
  Okno na B1: wywołania rysowania 276 → 195 (bez wnęk 183), GPU 7,32 / 7,33 ms z oknem i 7,37 / 7,30 ms bez — w szumie
  (wcześniej +0,30 ms). Kryjówka w kadrze maszynowni: 444 → 334 (bez wnęk 300). MultiMesh niepotrzebny.
- **1.2:** trzy okna i dwie kratki —
  `window` 93–96 w. 20–21 (`tube`, zaplecze nad drzwiami hali stacji, obok pilota N2 `doorway` 88–91; 10 kolumn od Ślepca),
  `window` 190–193 w. 32–33 (`tube`, sterownia nad prawą kładką podziemnej hali, z kładki przerwa 2 kafle),
  `window` 223–226 w. 18–19 (`bulb`, piętro pompowni, przerwa 2 kafle nad podłogą piętra),
  `vent` 124 i 228 w. 46 (`lamp`, pod stropem tunelu drezyny w środku przęseł między słupami `w` co 8 kolumn, 15–16 kolumn od `Z`).
  Kandydaci: `shots_depth/window_spots.py` i nowy `shots_depth/vent_spots.py` (kafel `b` z pierścieniem `b`, 1–2 wiersze pod
  stropem, z dala od L/Z i od stojących wnęk).
- Pomiar (debug, 4K HIGH, obrys różnicy zrzutów w stałym prostokącie wokół otworu — `lumbox.py`, bo deszcz i przestawione napisy
  na ścianie psują obrys z całego kadru): okna 0,0069 → 0,0175 (hala stacji), 0,0056 → 0,0168 (podziemna hala), 0,0003 → 0,0143
  (pompownia); pas pod oknem bez zmian (±0,001). Kratki 0,0000 → 0,081 i 0,086 — jak kratka pilota na 1.3.
- Wydajność (dwie i cztery rundy): kadr hali stacji (okno + drzwi) GPU 7,59 / 7,71 ms z wnękami, 7,58 / 7,54 ms bez — +0,09 ms,
  wywołania 320 → 348; kadr pompowni 8,35 / 8,65 / 8,02 / 8,25 ms z wnękami, 8,12 / 8,19 / 8,28 / 8,25 ms bez — +0,11 ms,
  439 → 459.
- Uwaga: napisy na ścianie tła (`Level3D.build_decals`) losują miejsca z pominięciem otworów wnęk, więc z wnękami i z `--noniches`
  stoją gdzie indziej (np. SILENCE nad oknem pompowni) — to nie błąd, ale psuje obrys różnicy z całego kadru.
- `tools/test_niches.gd`: korytarze sąsiednich wnęk z zapasem `TREE_MARGIN` nachodzą na siebie (okno 93–96 i drzwi 88–91), więc
  liczenie drzew w korytarzach liczy teraz każde drzewo raz.
- Zrzuty: `shots_depth/n4_z1m2/` (`m2_sheet.jpg`, `m2_zoom.jpg`, kontrolne po scaleniu w `scalenie/`).

### Wyniki N4 na 1.3 (2026-11-07, `feat/n4-z1m3`, 1.7.516)

- **Reguła okna:** piętro Składu ma 3 kafle wysokości i beton tuż nad nim, więc okno z murem `b` także nad otworem się nie mieści.
  Bryła litego kafla sięga do ściany tła (`DEPTH_FRONT + DEPTH_BACK`), więc zasłania pokój tak samo jak mur:
  `Niches3D._hides_room` przyjmuje obok okna i nad nim `b` albo lity kafel. Test na sztucznej mapie: okno pod stropem i przy
  skale przechodzi, przy otwartym powietrzu i pod kładką — nie. `window_spots.py` liczy tak samo i pomija stojące wnęki,
  `vent_spots.py` dopuszcza strop nad kratką (jak walidacja i pilot w kolumnie 150).
- **Wpisy:** `window` 117–120 w. 19–20 (`tube`, pod stropem piętra Składu, nad antresolą — głowy graczy na antresoli wchodzą
  w dolne pół metra okna), `window` 173–176 w. 32–33 (`bulb`, `d` 5 m, górny poziom wschodniej sali podziemi, 11 kolumn od
  korytarza 160–162), `vent` 32 w. 22 (pod stropem posterunku, 11 kolumn od zaplecza), `vent` 36 w. 36 (pod skalnym stropem
  na zachodnim końcu niskiego tunelu). Szyby 1.3 bez kratek: ich ściany co dwa wiersze przecinają podesty `=`, a rodzaj ścienny
  potrzebuje muru pod spodem.
- Pomiar (debug, 4K HIGH, `lumbox.py`): okno Składu 0,0000 → 0,0187, okno wschodniej sali 0,0000 → 0,0234 przy głębokości 4 m —
  ponad progiem, więc pokój pogłębiony do 5 m (lampa w 3/4 głębokości stoi dalej od otworu): 0,0172; pas pod oknami bez zmian
  (≤ 0,0014). Kratki 0,110 i 0,093 w samym otworze (jak pozostałe kratki, ok. 0,08–0,11).
- Wydajność: kadr Składu 9,20 / 8,33 / 8,57 ms z wnękami, 9,04 / 8,71 / 8,56 ms bez — w szumie, +15 wywołań rysowania.
  Kadr wschodniej sali z wnękami +0,35 ms względem `--noniches` (sześć rund), ale `--noniches` gasi też korytarz 160–162 i kratkę
  150. Samo okno (naprzemiennie bez wpisu okna i z nim, trzy rundy): 7,75 / 7,85 / 7,80 ms bez, 7,73 / 7,74 / 6,87 ms z oknem —
  w szumie, +14 wywołań. Zegar GPU w ciągu godziny pomiarów pływał o ok. 0,5 ms — porównywać tylko rundy naprzemienne.
- Zrzuty: `shots_depth/n4_z1m3/` (`m3_sheet.jpg`).

### Wyniki N4 na 1.1 (2026-11-07, `feat/n4-z1m1`, 1.7.517)

- **Miejsce:** kopalnia 1.1 jest ciasna — prawie każdy kandydat stoi bliżej niż 10 kolumn od gniazd ćm `Z` (wiszą pod stropem
  galerii) i Ślepców `L`, a w górnej galerii okno albo kratka obok korytarza 268–270 dałyby trzy świecące otwory w kadrze.
  Szyb serwisowy (276–279) jest za wąski i co dwa wiersze ma podest. Zostały dwa wpisy: `vent` 258 w. 27 (`lamp`, pod stropem
  rampy w dół do kopalni — dotąd bez żadnego światła; Skoczek `J` wisi 2 kolumny obok, nie przed kratką) i `window` 290–293
  w. 40–41 (`bulb`, okno dyspozytorni na ślepym wschodnim końcu dolnej galerii, obok sztolni 285–287, 18 kolumn od gniazda ćm;
  przerwa 1 kafel — głowa gracza wchodzi w dolną krawędź okna).
- Pomiar (debug, 4K HIGH, `lumbox.py`): kratka 0,0000 → 0,065, okno 0,0000 → 0,0074, pas pod nimi bez zmian (≤ 0,0011).
- Wydajność: kadr rampy z wnękami 8,64 / 8,83 / 8,71 ms, z `--noniches` 8,38 / 8,62 / 8,36 ms — +0,27 ms dla kratki i korytarza
  268–270 razem, +34 wywołania rysowania. Samo okno (sześć rund naprzemiennie z wpisem i bez): 8,60 / 8,50 / 8,61 / 8,94 / 8,45 /
  8,67 ms z oknem, 8,20 / 7,16 / 8,28 / 8,42 / 8,63 / 8,61 ms bez — mediana +0,25 ms (bez odstającej rundy 7,16: +0,20 ms),
  +15 wywołań rysowania; w budżecie 0,5 ms. W kadrze dolnej galerii liczba wrogów różni się między przebiegami (7–8), co dokłada
  szumu.
- Zrzuty: `shots_depth/n4_z1m1/` (`m1_sheet.jpg`).

### Wyniki N4 w kryjówce (2026-11-07, `feat/n4-hub`, 1.7.518)

- **Miejsce:** na górze i w środku tylną ścianę zajmują meble z `hub_decor.gd`, tablice i gabloty, więc rodzaje ścienne wiszą
  nad nimi: dwa okna sterowni nadajnika na górze (`window` 38–41 w. 10–11 `tube` i 46–49 `bulb`, nad szafkami i stołem
  pracowni, z dala od radiostacji i okna pogody), kratka wysoko w świetlicy (`vent` 41 w. 16) i kratka pod stropem magazynu
  na dole (`vent` 42 w. 24). Dwa świecące otwory w kadrze góry, jeden w kadrze środka.
- **Pułapka: żebra stropu.** Długie hale kryjówki mają żebra co 8 kafli (`Level3D.interior_ribs`), a `_rib_in_niche` zdejmuje
  żebro, gdy otwór stoi ±1 kolumnę od niego. Pierwsze miejsca (okna 33–36 i 49–52, kratka 35) zabrały trzy pilastry —
  przesunięte w środek przęseł (żebra góry 36 / 43 / 52, środka 35 / 44). Kolumny żeber liczy `shots_depth/rib_cols.py MAPA.gd`.
- Pomiar (debug, 4K HIGH, `lumbox.py`): kryjówka jest jasna, więc mur wokół otworów ma już 0,03–0,08. Okno `tube` 0,042 → 0,062,
  okno `bulb` 0,033 → 0,036, kratki na poziomie muru obok (0,083 → 0,091 i 0,053 → 0,052) — żaden otwór nie odstaje od
  oświetlonej ściany, pas pod nimi bez zmian.
- Wydajność (trzy rundy naprzemiennie): kadr góry z oknami 10,06 / 10,05 / 9,57 ms, bez okien (podmiana mapy) 9,83 / 9,65 /
  10,17 ms — w szumie, +28 wywołań rysowania (201 → 229); kadr środka 10,06 / 10,13 / 10,32 ms, z `--noniches` 10,05 / 11,24 /
  9,81 ms — mediana +0,08 ms, +25 wywołań.
- Zrzuty: `shots_depth/n4_hub/` (`hub_sheet.jpg`).
- **N4 zamknięte:** 18 otworów ściennych na pięciu mapach (B1 2, 1.2 5, 1.3 5, 1.1 2, kryjówka 4 — razem z pilotem 1.3).

## Kolejność i rozmiar

| Etap | Co | Rozmiar | Wersja |
|---|---|---|---|
| N0 | zrzuty, pomiar, wybór kolumn | 0,5 d | bez wersji (wyniki w tym pliku) |
| N1 | `niches3d.gd`, dane mapy, wycięcie ściany, `--nichetest` | 1 d | PR, podbicie wersji |
| N2 | pilot w hali 1.2 + A/B | 0,5–1 d | ten sam PR albo następny |
| N3 | katalog i mapy | 2–3 d | po jednym PR na mapę |
| N4 | okna i kratki w ścianie tła (pilot: B1, 1.3; dalej 1.2, Skład 1.3, szyby, kryjówka) | 1 d pilot + po 0,5 d na mapę | 1.7.513 pilot, 1.7.514 scalenie i 1.2, 1.7.516 1.3, 1.7.517 1.1, 1.7.518 kryjówka |

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
