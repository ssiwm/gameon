# Wejścia do stref wydobycia — plan poprawek

Zgłoszenie z gry (2026-11-16, 1.2 „Radio Silence”, koniec korytarza ze skrzynią FALCON-6): „część tuneli, gdzie możemy kopać,
ma błędnie ustawione assety”. Analiza na main f748c92f (1.7.588), zrzuty w `C:\deadair87\shots_digassets` (`a_149.png`, `z1.png`,
`m1.png`, `m3c.png`). Dotyczy wszystkich trzech stref z danych map (`DIG_ZONES`):

| Mapa | Strefa (kolumny × wiersze) | Materiał | Wejście |
|------|----------------------------|----------|---------|
| 1.1 | 192–201 × 36–44 | skała (wtrącenia 0,3) | od wschodu, kol. 202, podłoga w. 43 |
| 1.2 | 133–142 × 36–39 | żwir | od wschodu, kol. 143, podłoga w. 40 (korytarz z ceglaną obudową) |
| 1.3 | 1–5 × 31–39 | ziemia | od wschodu, kol. 6, podłoga w. 40 |

## Co widać i skąd to jest

Ustalone ukrywaniem węzłów na zrzucie i sondą brył w punkcie (kol. 143, w. 38):

1. **Jasny „panel” na końcu korytarza to czoło strefy** — ściana pierścienia z `dig_zone.gd chunk_mesh` (pętla „komórki
   pierścienia przy powietrzu mapy”, dodana po uwadze z gry 2026-11-08, żeby przez bok strefy nie było widać tła). Wygląda jak
   deska albo drzwi, bo:
   - jest **idealnie płaska na całą głębokość bryły** (z od +1,1 do −2,4 m): `_jag` daje `fade = 0` w odległości < 0,5 komórki od
     brzegu strefy, a ta ściana leży dokładnie na brzegu — nierówności P1 jej nie dotyczą;
   - ma **teksturę gruntu mapy** (`terrain`, skan ziemi rzutowany triplanarnie na pionową płaszczyznę — z bliska jak słoma),
     bo `_mat_weights` daje alfę 0 wszystkiemu, co nie jest wykopane; materiału strefy (żwir, skała, ziemia) nie widać, dopóki
     się nie kopnie;
   - stoi **prostopadle do snopu latarki** gracza, który celuje w lewo — dostaje pełne światło, gdy reszta tunelu łapie je pod
     kątem, więc świeci jak jednolita pomarańczowa tablica;
   - na 1.2 ceglana obudowa korytarza urywa się na tej płaszczyźnie bez żadnego zakończenia (bez odrzwi, bez osypiska u stopy).
2. **Kilof znaku wisi przy ścianie, zamiast w niej tkwić** (`view3d._build_dig_sign`): środek modelu 0,55 m od ściany, obrót 0,45 rad,
   więc głowica tylko dotyka czoła, a trzonek sterczy w powietrzu na wysokości piersi. Na tle płaskiego, jasnego panelu wygląda jak
   narysowany.
3. **Okruchy znaku** (`rubble`, `rock_b`, `rock_c`) są ciemne i małe — przy panelu ginęły; w obecnym kadrze nic nie wnoszą.
4. **1.3: rura pierwszego planu (`FRONT`) stoi dokładnie przed wejściem do strefy** i zasłania kilof i czoło.
5. **1.1:** to samo czoło (wąski jasny pas z kilofem) — mniej rażące, bo kamera patrzy na nie bardziej z boku.

Nie są błędem (sprawdzone):
- **Ukośna granica na skale nad korytarzem** to górna krawędź stożka latarki na przodzie skały (przedłużona trafia w lufę gracza).
- **Ceglane okruchy na podłodze** (zrzut z gry) to rozbite zamurowane przejście `q` (kol. 150) — zamierzone.
- **Złote kupki** to złom ze skrytek `u` (kol. 145, 148), **żółte puszki** to amunicja `a` (kol. 147).
- **Ciemny klin nad panelem** to spód stropu korytarza w perspektywie (widoczny tylko na tle jasnego panelu).

## Etapy

### E1 — czoło strefy jak zasyp, nie tablica (`dig_zone.gd`)

**Zrobione w 1.7.589** (`feat/dig-face-e1`). Co wyszło inaczej niż w szkicu niżej:
- Garby tylko na czole od strony powietrza mapy (`_ring_out`, w poziomie, ±0,75 komórki od brzegu), do `RING_JAG` 0,4 m,
  narastające w głąb (`RING_PLANE` 0,25–0,75 m od płaszczyzny gry) — przód **i płaszczyzna gry** zostają na brzegu, bo postać
  stoi przy ścianie na z = 0; gęstsze plastry `RING_U`. Ruch w pionie tylko szumem w z, bez przesuwania krawędzi.
- Równa jasność czoła nie brała się z `tint → deep`, tylko z nalotu brudu mapy (`next_pass` gruntu, alfa 0,5, równy oliwkowy
  kolor) i poświaty snopu we mgle. Strefy mają teraz własny przebieg brudu (`dig_ground.gd GRIME_SHADER`, znika przy alfie
  materiału strefy), a czoło ciemnieje w zagłębieniach (`RING_DIM`, `RING_SHADE` × `_ring_lump`).
- Część E3 zrobiona przy okazji: kilof i okruchy znaku odsunięte o garb czoła w swoim punkcie (`face_bulge`) — inaczej garb
  chował kilof na 1.3. Zostaje w E3: wbicie ostrza wg AABB modelu i okruchy w materiale strefy.
- `--shothide` opisane w README; test `tools/test_dig_face.gd` (CI). Siatka fragmentu w `--digtest` 1,3–4,2 ms — rozrzut ten sam
  na main, próg 4 ms jest na granicy szumu.
- Zostaje: drobny żwir z odległości kamery wygląda jak piasek — osypisko z E2 powinno dać mu skalę.

Szkic:

- Nierówności na ścianie pierścienia: osobna gałąź w `_jag` dla wierzchołków na brzegu strefy, z wyjątkiem plastra przy
  przodzie (u = 0, styk z przodem mapy `Caps` musi zostać szczelny) i styku z podłogą i stropem korytarza (bez ruchu w pionie
  przy tych krawędziach). Przesunięcie **tylko w stronę powietrza** (wzdłuż normalnej ściany, wartości ≥ 0) — wybrzuszenie do
  korytarza nigdy nie otworzy szczeliny na tło za strefą. Amplituda jak `JAG_DEEP` × ok. 0,6, ten sam szum (garby co ok. 0,6 m).
- Materiał strefy na odsłoniętym czole: wierzchołki ściany pierścienia, która styka się z powietrzem mapy pod ziemią, dostają
  wagę materiału strefy (alfa 1 i UV2 jak przy wykopie), przód (z = front) zostaje gruntem mapy. Na 1.2 czoło wygląda wtedy jak
  zasyp żwiru — od razu widać, że tu da się kopać; na 1.1 skała z wtrąceniami, na 1.3 ziemia. Wierzch strefy pod niebem bez zmian
  (tam szew z dnem lasu, dlatego dawniej alfa 0).
- Sprawdzić, czy przyciemnianie w głąb (`tint → deep` w `_walls`) dochodzi do shadera — na zrzucie czoło jest równo jasne.
- Przy okazji: fragmenty strefy dostają nazwy `DigChunk0…N` (`add_child` z czytelną nazwą) — teraz drugi i dalsze dostają
  `@MeshInstance3D@…`, co myli przy szukaniu w drzewie.

### E2 — przejście obudowy w zasyp (`view3d.gd`, znak strefy)

**Zrobione w 1.7.590** (`feat/dig-e2-talus`, na E1). Geometria w `scripts/dig_entrance3d.gd` (statycznie, ze strefy i mapy — test bez sceny):
- Osypisko to siatka stoku w materiale strefy (`_dig_mat`, alfa 1) plus bryłki `fracture_rock` w MultiMesh (`_dig_spoil_mat`), nie
  sam `dig_spoil`: urobek z kopania żyje tylko w prostokącie strefy (`_settle_spoil` zabrałby bryłki z korytarza), a same bryłki nie
  dawały stoku. Wysokość wg materiału (`TALUS_H`: żwir 0,5 m, ziemia 0,34, skała 0,26), stok 36°, ścieżka przy z = 0 przydeptana
  (12 %), przed płaszczyzną gry × 0,55, przy przodzie zero. Wierzch zaczyna się w czole (najgłębszy garb na wysokości osypiska).
- Odrzwia tylko przy obudowie (`Level3D.back_wall_at` kafla korytarza przy czole): stojak przy tylnej ścianie, stropnica pod stropem
  korytarza do z = +0,6, klin. **Bez przedniego stojaka** — przód obudowy jest w przekroju, a słup przy z ≈ 1 stałby przed postacią
  przy czole (ta sama zasada co stemple wykopu). Na 1.1 i 1.3 bez ramy.
- Kupka `rubble` znaku zastąpiona osypiskiem; zostały dwa odłamki `rock_b`/`rock_c` (E3).
- Zrzuty: na 1.2 rama domyka cegłę, stożek żwiru u stopy; na 1.1 i 1.3 osypisko niskie, kilka brył (ciemne poza snopem).

Szkic:

- U stopy czoła **osypisko** z urobku (ten sam `dig_spoil` MultiMesh co po kopaniu, tylko klient, kosmetyka): żwir — stożek ok. 0,5 m
  w stoku naturalnym, ziemia i skała — mniejsza kupka okruchów. Bez kolizji (symulacja 2D bez zmian).
- Tam, gdzie korytarz ma obudowę (`Level3D.back_wall_at` — 1.2), **odrzwia na końcu obudowy**: dwa stemple i belka z modelu stempla
  stref (`_sync_dig_props`), ustawione na granicy cegły i zasypu. Domyka obudowę i sam jest znakiem „dalej zasypane”.
- Opcjonalnie (do decyzji po zrzutach): na 1.1 i 1.3, bez obudowy, same stemple bez belki albo nic.

### E3 — znak: kilof wbity, okruchy na podłodze

**Zrobione w 1.7.591** (`feat/dig-e3-pick`). Kilof: `dig_entrance3d.gd pick_parts` bierze z modelu czubek obucha (górny koniec AABB
siatki `*head*`) i koniec trzonka, `pick_xf` obraca go w płaszczyźnie kadru — obuch (+y modelu) w czoło i lekko w dół, trzonek
`PICK_TILT` 0,6 rad od pionu w stronę korytarza — i stawia czubek `PICK_EMBED` 8 cm w garbie czoła (`face_bulge`) na 1,12 m, z = 0,72.
Inaczej niż w szkicu: obuch, nie ostrze wzdłuż trzonka — w modelu ostrze jest w poprzek trzonka, więc wbity kilof wisi trzonkiem w dół.
Odłamki `rock_b`/`rock_c` zniknęły z wejścia z boku (osobne modele w obcym materiale); zamiast nich dwie większe bryły urobku za stopą
osypiska (`TALUS_STRAY`), w materiale strefy. Wejście od góry (bez czoła) bez zmian.

Szkic:

- Położenie kilofa liczone z AABB modelu (`gun_kilof.glb` × `DIG_SIGN_PICK_K`): ostrze 6–10 cm w czole (po E1 — w nierównej
  powierzchni, więc odległość od `wall_x` + przesunięcie `_jag` w tym punkcie), głowica na wysokości 1,0–1,2 m, trzonek w dół
  i od ściany, z = 0,6–0,8 m (w snopie, przed graczem).
- `rubble`, `rock_b`, `rock_c` osadzone na podłodze (y z `floor_y`, bez lewitowania) i przesunięte bliżej czoła, w materiale strefy
  (żwir / skała / ziemia) — po E2 część tej roli przejmuje osypisko, więc może wystarczyć jeden okruch.

### E4 — pierwszy plan nie zasłania wejść (`front3d` / `level3d`)

- Reguła rozstawienia `FRONT`: żaden element pierwszego planu w kolumnach wejścia strefy ±2 (z `entrance()`), jak dziś
  `FRONT_SKIP`. Na 1.3 rura przesunie się w bok.
- Test w `tools/test_front.gd`: „pierwszy plan nie stoi przed wejściem strefy wydobycia” dla wszystkich map z `DIG_ZONES`.

### E5 — testy i zrzuty

- `--digtest` (t_dig) i nowy krok w `test_front.gd`: ściana pierścienia nie jest płaska (rozrzut położenia wierzchołków w głąb
  > 5 cm), plaster przy przodzie dokładnie na z = front (szczelność), żaden wierzchołek pierścienia nie cofa się za brzeg strefy,
  ostrze kilofa znaku za `wall_x` w skale, okruchy na podłodze (±2 cm).
- Zrzuty przed i po dla trzech map (okno, `override.cfg` z osobnym katalogiem QA, każdy przebieg osobno — równoległe przebiegi
  na jednym katalogu pokazują ekran jasności zamiast gry):
  - 1.2: `--mission=z1_m2 --nobot --shotat=149 --shotrow=39 --shottorch --shotaimleft`
  - 1.1: `--mission=z1_m1 --nobot --shotclear --shotat=204 --shotrow=42 --shottorch --shotaimleft`
  - 1.3: `--mission=z1_m3 --nobot --shotclear --shotat=9 --shotrow=39 --shottorch --shotaimleft`
- Koszt: przebudowa siatki fragmentu (dziś 1,6–2,5 ms) — zmierzyć po E1, bo pierścień dostaje więcej wierzchołków z szumem.
- Dev: flaga `--shothide=Prefiks,...` (ukrywa węzły 3D o nazwach z prefiksem przed zrzutem) — przydała się w tej analizie,
  do dopisania w README razem z E1.

Kolejność: E1 (największy efekt, sam usuwa „tablicę”) → E3 (zależy od powierzchni z E1) → E2 → E4 → E5 na bieżąco w każdym etapie.
Każdy etap osobnym PR-em z podbiciem `config/version` i wierszem w `CHANGELOG.md`.
