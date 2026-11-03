# DESTRUCTION_PLAN — niszczenie otoczenia

Stan wyjścia: main 1.7.477 (2026-11-02). Plan v4 (weryfikacja silnika pomiarami, research gier gatunku, wrażenie i dźwięk,
spike'i przed D0), nic nie wdrożone.

## Cel

Otoczenie reaguje na walkę i można je świadomie niszczyć — ale tylko tam, gdzie mapa na to pozwala. W grze o hałasie, ciemności i ucieczce
niszczenie ma być **decyzją taktyczną** (otworzyć skrót, zawalić przejście za sobą, zgasić światło, zrobić wabik), a nie chaosem, który psuje
trasy i softlockuje misje.

Zasady:

1. **Niszczalne jest to, co mapa oznaczy.** Grunt `#`, beton `C`, blacha `M` i skała poza strefami zostają nietykalne. Kopać można tylko
   w strefach wydobycia (D5); kopalnia FPP to osobny plan (`MINING_PLAN.md`). Zawsze istnieje **bezpieczna droga** do celu bez niszczenia
   (zasada Spelunky — zniszczenie daje skróty i sekrety, nigdy nie jest warunkiem przejścia).
2. **Rozstrzyga serwer**, klienci dostają zdarzenie (RPC reliable), dołączający — listę już zniszczonych rzeczy, restart misji / wipe /
   punkt kontrolny bossa — stan z danych.
3. **Symulacja 2D, obraz 3D** (CLAUDE.md). Odłamki to istniejące `Vfx.debris` (fizyka 2D na kolizji mapy, bryła 3D w obrazie), bez fizyki 3D
   i bez synchronizacji — każdy peer liczy je sam z ziarna z RPC.
4. **Zniszczenie = hałas.** Każde rozbicie ma swoją wartość w `NoiseMgr` — to główny koszt i główna nagroda mechaniki.
5. **Bez przycięć.** Zniszczenie nie może przebudowywać całego świata 3D ani całego grafu nawigacji.
6. **Zniszczenie zmienia informację, nie tylko drogę.** Dziura w desce przepuszcza wzrok, światło i dźwięk — w obie strony (wnioski
   z Rainbow Six Siege i Darkwood, niżej).

## Co już jest

| Element | Gdzie | Stan |
|---|---|---|
| Zamurowane przejście `q` | `brick_wall.gd`, `level.gd` (`_wall_cells`, `break_wall`, `send_walls_to`) | kilof (`breaks_walls`) i wybuch; HP 120; hałas 1,5 / 6; gruz `view3d._spawn_rubble`; tylko **1 sztuka** w mapach (1.2) |
| Rzeźnik przebija barykady | `enemy_bruiser.gd:237` | działa na grupę `breakables` |
| Beczka `o` wybucha, skrzynia `k` | `prop.gd` | beczka: HP 30, AoE 64 px, łańcuch beczek; skrzynia nie pęka, tylko lata |
| Wybuch z linią wzroku | `combat.gd explode / blast_reaches` | rani też `breakables` |
| Zawał 1.1 | `level.gd collapse`, `view3d._geo_alt` | jedno, z góry policzone „po zawale” (geometria 3D i nawigacja przy wczytaniu) |
| Ślady kul i osmalenia | `mark_hit` / `mark_scorch` (#391) | dekale, bez stanu |
| Cele „zniszcz” | gniazda, Żyła, totemy (GDD) | osobne obiekty-wrogowie |

## Ograniczenia techniczne (zmierzone)

- **Widok 3D:** `view3d._sync_geometry` liczy klucz z hasha **całej** mapy (`_map`). Każda zmiana kafla = budowa całego świata od zera (las,
  ciecze, mgła, dekale — sekundy). Zawał 1.1 obchodzi to geometrią policzoną przy wczytaniu, ale to działa tylko dla **jednego** znanego stanu.
  Przy *n* niezależnych zniszczeniach to 2ⁿ stanów — odpada.
- **Nawigacja:** `level._refresh_region` buduje **cały** graf A* od nowa. Pomiar (headless, ten komputer): 1.1 — 85 ms, 1.2 — 122 ms,
  1.3 — 107 ms, B1 — 35 ms. **Dziś rozbicie ściany `q` na 1.2 przycina grę o ok. 0,12 s.**
- **Dźwięk:** `sound_grid.refresh(region)` już działa lokalnie — w porządku.
- **Kolizja:** `TileMapLayer.set_cell` jest tani — w porządku.
- **Wydajność:** walka ok. 38 kl./s na RTX 3080 w 4K (`gameon-perf`), więc budżet na odłamki i światła jest ciasny.

Wniosek: **zniszczalne rzeczy nie mogą być kaflami wypiekanymi w świat 3D.** Tak jak ściana `q` — osobny węzeł 2D (kolizja + HP) i osobna siatka
3D, a mapa kafli tylko rezerwuje komórki dla nawigacji (`_wall_cells`).

## Technologie (przegląd v2, poprawki v4)

Pierwsza wersja planu miała trzy słabe miejsca: osobny model na każdy stan uszkodzenia, odłamki liczone „łukiem” obok istniejącego systemu
i nowe węzły cząsteczek przy każdym trafieniu. Wybór poniżej — najlepsza jakość przy najmniejszym koszcie w naszej architekturze
(symulacja 2D, obraz 3D, Forward+, walka ok. 38 kl./s w 4K):

| Obszar | Wybór | Dlaczego nie inaczej |
|---|---|---|
| Stopnie uszkodzeń | **Jedna siatka na materiał + shader z maską uszkodzeń.** Maska to mała tekstura na obiekt (`ImageTexture` 64 × 64, kanał R), do której serwerowe zdarzenie trafienia „wypala” miękką plamę (`Image.blend_rect` / zapis pikseli + `ImageTexture.update`): z progu wycina dziurę `alpha scissor`, poniżej progu dokłada pęknięcia w normalnych i ciemniejsze drewno. Liczba trafień bez limitu, dziury tam, gdzie naprawdę padła kula. `alpha scissor` działa też w przebiegu cieni, a reflektor latarki rzuca cienie (`view3d.gd`, limit `SHADOW_LIGHTS`), więc **snop przebija przez dziury** i rzuca plamy światła na grunt za obiektem (S1: widać już 6 dziur po kulach). Po zapisie do maski obiekt trzeba **oznaczyć jako zmieniony**, inaczej Godot nie przerysuje cienia nieruchomego światła (S1). Zapis stemplem (`Image.blend_rect`), jedno `update` na obiekt na klatkę. **We mgle** dziury dają miękką poświatę snopu za obiektem (wyraźną od ok. 25 cm), bez ostrych smug — pod warunkiem poprawki mgły z #578 (bez niej poświata nie bierze cienia przeszkód; S1). Maska widać wprost tylko na obiektach równoległych do ekranu; poprzeczne (barykady, drzwi) kamera widzi z boku — tam uszkodzenie pokazują światło za nimi, odłamki i rozpad na bryły. | 3 modele na stan: 3× więcej zasobów, skok wyglądu. **`instance uniform` odpada** — dokumentacja 4.7: per-instancja tylko typy skalarne i wektorowe, bez tablic i tekstur (max 16). Zwykła tablica `uniform vec4 hits[16]` działa, ale wymaga osobnego materiału na obiekt i ogranicza liczbę trafień — tekstura maski jest równie tania i bez limitu. Materiał na obiekt rozbija grupowanie wywołań rysowania, ale przy kilkudziesięciu obiektach na mapie to pomijalne. Shader trzeba **rozgrzać pod planszą wczytywania** (jak `spawn_burst` przy budowie mapy), inaczej pierwsze trafienie zatnie klatkę. |
| Rozpad | **Pre-fraktura** w Blenderze headless: własny skrypt Voronoi (bmesh, cięcie płaszczyznami), 6–14 brył na obiekt, wnętrze z osobnym materiałem przekroju (drzazgi, cegła w środku). | Fraktura w locie (koszt CPU, brzydkie przekroje); dodatek Cell Fracture — zależność od rozszerzenia Blendera |
| Odłamki | **Istniejące `Vfx.debris`** (RigidBody2D na kolizji kafli + bryła 3D z `mirror_debris`) — odbijają się i zatrzymują na prawdziwej mapie, bez sieci. Nowe: kształt bryły z pre-fraktury zamiast kulki, a **uśpiony odłamek przechodzi do `MultiMeshInstance3D`** (ciało 2D usuwane) — setki leżących kawałków w jednym wywołaniu rysowania. Ziarno losowania w RPC, więc u wszystkich wyglądają tak samo. | Analityczne łuki (pierwsza wersja planu): brak odbić i turlania; fizyka 3D: łamie zasadę symulacji 2D i wymaga kolizji 3D świata, której nie ma |
| Cząsteczki | **Pula** emiterów (`spawn_burst` dziś tworzy nowy `CPUParticles3D` przy każdym trafieniu); pył opadający — `GPUParticles3D` z kolizją **`GPUParticlesCollisionBox3D` postawionym na podłodze z mapy** pod miejscem wybuchu (wysokość podłogi znamy z kafli); chmury pyłu — istniejąca mgła wolumetryczna (`FogVolume`) na kilka sekund. | Nowy węzeł na każde trafienie: alokacje i zacięcia. **`GPUParticlesCollisionHeightField3D` odpada** — dokumentacja 4.7: mapa wysokości nie zna nawisów („indoors or caves”), więc w podziemiach złapałaby strop zamiast podłogi; do tego kolizja działa tylko z `GPUParticles3D`, nie z `CPUParticles3D`. |
| Dekale | Istniejące `Decal` (`mark_hit`/`mark_scorch`, z limitem); odmiany wg materiału. | — (już dobre) |
| Nawigacja | `Nav.rebuild_region` (lokalnie, < 2 ms). | Pełna budowa 35–122 ms |
| Świat 3D | Zniszczalne = osobne węzły poza wypiekanym światem; modele i bryły pre-fraktury ładowane przy wczytaniu mapy (pod planszą), w grze tylko pokazywane. | Przebudowa całego świata (sekundy); `WorkerThreadPool` w grze — niepotrzebny (pomiary niżej), a w tym projekcie wątki już raz okazały się wolniejsze (pozy postaci, 2026-11-02) |
| Sieć | Zdarzenie (nazwa, stopień, ziarno, punkt trafienia) reliable; odłamki i cząsteczki deterministyczne z ziarna. | Synchronizacja odłamków — zbędny ruch |

Godot 4.7 ma Jolt jako fizykę 3D, ale dla nas to zła droga: świat 3D nie ma kolizji (jest obrazem symulacji 2D) i musielibyśmy go budować
podwójnie. Odłamki na fizyce 2D dają ten sam efekt w płaszczyźnie gry.

### Zweryfikowane pomiarem (Godot 4.7.2 headless, ten komputer, 2026-11-02)

| Co | Wynik | Wniosek dla planu |
|---|---|---|
| Pełna budowa grafu A* (`Nav.build`) | 1.1 — 85 ms, 1.2 — 122 ms, 1.3 — 107 ms, B1 — 35 ms | lokalna przebudowa konieczna (D0) |
| `BitMap.opaque_to_polygons` (wbudowane marching squares + RDP) | 64 × 64 z zamkniętą komorą: **jeden wielokąt, komora zgubiona** | nie nadaje się do stref D5 (gubi puste kieszenie i wyspy) |
| Własne marching squares w GDScript, fragment 16 × 16 komórek, losowa gęstość (najgorszy przypadek) | **0,18 ms**, 277 odcinków | przebudowa na głównym wątku, bez wątków; limit 4 fragmenty na klatkę |
| Podmiana `ConcavePolygonShape2D.segments` | 0,08 ms | kolizja stref co cios bez przycięcia |

Dokumentacja 4.7 (`ConcavePolygonShape2D`): kształt z odcinków jest przeznaczony do geometrii poziomu na `StaticBody2D`, jest pusty w środku,
a małe, szybkie ciała mogą przez niego przelecieć. Gracz i wrogowie (CharacterBody2D) są w porządku; odłamki i łuski w strefach dostają
ciągłe wykrywanie kolizji (`continuous_cd`). Kule liczą się promieniami, więc ich to nie dotyczy.

## Research — gry gatunku i ich rozwiązania

Źródła to głównie wywiady, analizy i opisy prasowe (lista na końcu); szczegóły implementacji większości gier nie są publiczne, więc
bierzemy z nich **zasady projektowe**, a technologię dobieramy pod nasz silnik.

| Gra | Co robi | Co bierzemy |
|---|---|---|
| **Broforce** (co-op run-and-gun, najbliższy krewny gatunkowo) | Prawie cały teren z klocków do zniszczenia; zasada z zapowiedzi: po czym da się chodzić, to da się zniszczyć; teren jako narzędzie (przekopać się obok wroga). | **Nie** całe mapy — u nas horror i skradanie, a chaos Broforce zabija napięcie. Bierzemy „przekopać się obok wroga” jako rolę stref D5 i desek D2. |
| **Spelunky 2** | Zawsze istnieje bezpieczna droga do wyjścia; bomby otwierają skróty i dostęp do przedmiotów odciętych przez generator; druga warstwa z ukrytymi skarbami. | Zasada bezpiecznej drogi (`--maptest` przy wszystkim całym); znajdźki **odcięte** za cienką ścianą / w strefie zamiast leżących na widoku. |
| **SteamWorld Dig** | Kafle wielkości postaci; „utknięcie” jako zagadka było rdzeniem napięcia — ale testerzy kopali prosto w dół i nie eksplorowali; ratunkiem okazał się skok od ściany, bo „utknięcie” przestało być zero-jedynkowe. | **Strefy D5 nie mogą więzić.** Reguły anty-pułapki (D5) i test, że z każdego miejsca wykopu da się wyjść. Znajdźki rozmieszczone **w bok**, nie pod wejściem, żeby kopanie prosto w dół nie było najlepszą strategią. |
| **Rainbow Six Siege** (Realblast) | Zniszczenie oparte na materiałach, które reagują spójnie na bodźce; wybuchy otwierają drogi **i dają informację** (dziury do podglądania). | Tabela materiałów (już w D0); **dziury jako informacja** — wzrok, światło i dźwięk przez dziury (D2). |
| **Darkwood** (horror, barykady) | Gracz barykaduje okna i drzwi; wrogów ciągną barykady i hałas, rozbijają je; światło przecieka przez szpary i zdradza kryjówkę; ogień i pułapki działają przez barykadę. | **Barykadowanie przez graczy** (nowe D2b) — w misjach „przetrzymaj” (GDD: typ celu, 2.3 Dzwon — obrona 3 fal); światło latarki przez dziury budzi wrogów. |
| **Noita** | Symulacja piksel po pikselu w kawałkach z „brudnymi prostokątami” (liczy się tylko to, co się zmienia); wątki szachownicą. | Osypywanie żwiru w D5: tylko aktywne komórki w brudnych prostokątach, krok 15–20 Hz; w naszej skali (do kilku tysięcy komórek) bez wątków. |
| **Teardown** | Woksele bez wytrzymałości konstrukcji: budynki potrafią wisieć na jednym wokselu (krytykowane w recenzjach), stabilność dopiero jako prototyp. | Wiszące kawałki psują wiarygodność — w D5 **wyspy bez połączenia z brzegiem strefy spadają** (sprawdzenie spójności zalewaniem, tanie przy kilku tysiącach komórek); w D3 zawał zaprojektowany z góry, bez ogólnej symulacji naprężeń. |
| **The Finals** | Zniszczenie tylko na serwerze, klienci nie liczą fizyki, czekają na potwierdzenie serwera — wszyscy widzą to samo. | Zgodne z naszym D0. Dla wyczucia: **natychmiastowa** odpowiedź lokalna (iskra, pył, dźwięk ciosu), zmiana stanu dopiero z serwera. |
| **Deep Rock Galactic** (co-op, kopanie) | Cel projektowy ok. 50/50 eksploracja / walka, kopanie jako część eksploracji; klaustrofobiczne tunele. | Kopanie w D5 trwa tyle (20–40 s na znajdźkę), żeby w co-op opłacał się podział: jeden kopie, drugi pilnuje (bot też pilnuje kopiącego). |
| **Vlambeer** (Nuclear Throne, „The Art of Screenshake”) | Zamrożenie ok. 10–20 ms przy trafieniu, wstrząs, trwałość — ślady walki zostają w świecie. | Sekcja „Wrażenie i dźwięk” niżej; gruz leży do końca misji. |

## Wrażenie i dźwięk (nowe w v4)

Satysfakcja z niszczenia to w połowie dźwięk i odpowiedź pod ręką, a v3 prawie tego nie opisywał.

- **Trzy takty każdego zniszczenia:** zapowiedź (pęknięcia z maski, trzask przy ostatnim stopniu — gracz wie, że „jeszcze jeden cios”),
  uderzenie (iskra / drzazgi / pył, wstrząs, krótki `Feel.hitstop` 15–20 ms tylko u tego, kto zadał cios — dziś hitstop jest przy zabójstwach,
  z przerwą 250 ms), skutek (odłamki spadają i **zostają**, pył osiada, dźwięk „dogasa”).
- **Dźwięk warstwowy na materiał:** uderzenie (rodzaj materiału) + pękanie (przy zmianie stopnia) + rozpad (przy zniszczeniu) + ogon
  gruzu (długość i gęstość od liczby odłamków) + osiadanie (pojedyncze stuknięcia, gdy odłamki zasypiają). Losowe warianty i wysokość,
  odległość i zasłanianie przez istniejącą `sound_grid`. Źródło: lokalna biblioteka Sonniss GDC (`C:\deadair87\audio_lib`, indeks ok.
  7 tys. nagrań: drewno ok. 150, kamień/skała ok. 120, kopanie ok. 80, szkło ok. 70, skrzypienie ok. 55, gruz ok. 50). Zgodnie z `AUDIO_PLAN.md`
  nagrania tylko lokalnie w `audio_licensed/` (repo publiczne) i **odsłuch A/B przed każdą podmianą**.
- **Wibracja pada:** dziś gra nie używa jej nigdzie (`Input.start_joy_vibration` — brak w kodzie). Krótki impuls przy ciosie kilofem
  i rozbiciu, mocniejszy przy wybuchu; ustawienie jak `shake_mult` (FULL / HALF / OFF).
- **Odkrycie znajdźki:** błysk w latarce przy odkopaniu do połowy, osobny dźwięk „metal pod kilofem”, krótki akcent przy wydobyciu
  (jak przy łupie z sejfu), wpis do raportu po akcji.
- **Hałas widać:** cios kilofem i rozbicie podbijają istniejący wskaźnik hałasu w HUD (`vu_meter.gd`) — gracz uczy się ceny niszczenia.

## Spike'i przed D0 (nowe w v4)

Dwie rzeczy są ryzykowne i tanio je sprawdzić, zanim powstanie kod produkcyjny:

- **S1 — dziury i snop latarki** (zrobiony 2026-11-02, wynik niżej): jedna deska z shaderem maski, kilka trafień, latarka za deską, zrzuty w nocy i w mgle
  (`--weaponshots`-podobny kadr). Odpowiada: czy smugi przez dziury są widoczne przy obecnej mgle, ile kosztuje cień przez `alpha scissor`.
- **S2 — ruch po wykopie** (zrobiony 2026-11-02, wynik niżej): jedna strefa 12 × 6 kafli na mapie testowej, kolizja z odcinków, gracz biega, skacze i kopie kilofem.
  Odpowiada: czy `CharacterBody2D` dobrze chodzi po krzywych skosach z marching squares (wygładzanie, `floor_snap_length`, maks. kąt podłogi),
  czy kopanie „czuje się” dobrze (ile ciosów, wielkość wyrwy), czy łatwo się zakopać.

Wynik obu idzie do planu przed D0 (liczby, ewentualna zmiana podejścia).

### Wynik S1 (2026-11-02, gałąź robocza `spike/dig-zone`, test `--holetest`)

Deska 6 cm × 2,2 m × 3,5 m (cała głębokość drogi) 2,5 m przed graczem na starcie 1.1, poprzecznie do drogi; shader z maską `R8` 128 × 80
(`ALPHA` z maski, `ALPHA_SCISSOR_THRESHOLD = 0,5`, ciemniejsze drewno wokół dziur); latarka gracza (reflektor z cieniem) w osi deski.
Kolejno: 6 dziur po kulach (9 cm), 12 po śrucie (5 cm), wyrwa 26 cm, kontrolna wyrwa 1,6 m. Jasność liczona z obrazu (grunt 0,3–14 m za deską,
powietrze 1–2,5 m nad nim) plus różnica zrzutów; okno 4K, RTX 3080; pogodna noc i MGŁA (`--shotweather`). Zrzuty: `--holeshots=KATALOG`.

**Odpowiedzi**

- **`alpha scissor` działa w przebiegu cieni** (shader własny i `StandardMaterial3D`): cała deska zabiera 34–51% światła z gruntu za nią,
  deska z wyciętą maską, przezroczysty `StandardMaterial3D` i deska bez rzucania cienia dają to samo (85–97% jasności bez deski — reszta to sama
  deska w kadrze).
- **Pogodna noc — dziury widać po świetle, nie po desce.** Już 6 dziur po kulach rzuca wyraźną plamę światła na grunt 4–8 m za deską (różnica
  zrzutów; snop idzie poziomo, więc plama z każdej dziury rośnie z odległością jak z otworkowej kamery). Wyrwa 26 cm: plama większa (+2 pkt
  średniej jasności gruntu), wyrwa 1,6 m: 92% jasności bez deski. To jest dobry sygnał „tu coś przestrzeliłem” bez żadnych cząsteczek.
- **Pułapka silnika: cień nie odświeża się po zmianie tekstury maski.** Godot przerysowuje mapę cieni reflektora tylko, gdy coś w jego zasięgu
  się ruszy lub zmieni materiał; `ImageTexture.update()` tego nie robi. Zmierzone: wyrwa 1,6 m przy nieruchomej latarce — cień bez zmian (47%),
  po przesunięciu deski o 0,1 mm i z powrotem — 88%. Latarka gracza zwykle się rusza (celowanie, kołysanie), więc zwykle się odświeży, ale
  lampy stałe i latarka nieruchomego gracza nie. **D0: po aktualizacji maski oznaczyć obiekt jako zmieniony** (przesunięcie o ułamek mm
  i powrót w następnej klatce sprawdzone; tańszy sposób przez `RenderingServer` — do sprawdzenia przy D0).
- **MGŁA bez poprawki — smug nie ma:** poświata snopu w mgle wolumetrycznej nie brała cienia przeszkody (jasność powietrza za deską taka sama
  bez deski, z deską, ze ścianą 1 m i po wyłączeniu cienia reflektora), choć grunt za deską był zacieniony. Przyczyna ustalona w osobnej sesji
  (PR ssiwm/gameon#578): mgła Godota układa komórki z założeniem symetrycznej bryły kamery, a kamera świata ma przesunięty obiektyw, więc
  światło i cień we mgle wypadały 2–4 m wyżej, niż widać. To błąd obecnej gry (snop we mgle świeci przez ściany i teren).
- **MGŁA z poprawką #578 (zmiany nałożone tymczasowo na gałąź roboczą) — dziury dają poświatę za deską:** cała deska gasi poświatę za sobą;
  6 dziur po kulach daje słabą poświatę za deską, śrut podobnie, **wyrwa 26 cm — wyraźny, miękki ciąg snopu za deską** (powietrze za nią
  0,24 → 0,34, bez deski 0,51), wyrwa 1,6 m — jak bez deski. **Ostrych pojedynczych smug nie ma:** komórka mgły to ok. 0,4 m na płaszczyźnie gry
  (siatka 96 × 96 × 96), więc snop przez dziurę rozmywa się w miękką plamę. Do D0 to wystarcza jako sygnał „tu przebiło”; ostre smugi
  wymagałyby gęstszej siatki mgły (koszt) albo osobnych brył smug (dodatkowe siatki) — nie w D0.
- **Błąd w #578 znaleziony przy S1 i już poprawiony:** gdy mapa startowała od razu w gęstej mgle, w trybie domyślnym (`fog_sym = 1`) pas nad kadrem
  był ustawiony, a mgła nie brała cienia, dopóki obraz świata nie przebudował się ponownie (powietrze za deską 101% jasności bez deski;
  po przełączeniu trybu 34%). Poprawka w #578 (commit c71cd48: atlas cieni powstaje przed mgłą); sprawdzone testem S1 bez przełączania
  trybu — od startu powietrze za deską 52% jasności bez deski.
- **Wysokość przeszkody kontra stożek snopu:** latarka świeci z wysokości 1,4–1,9 m (zależnie od pozy z bronią), stożek ma ±24°, więc nad
  przeszkodą 2,2 m odległą o 1,5 m przechodzi górna część snopu i świeci we mgle za nią. Deska w teście ma 3 m. Dla D0: barykada niższa niż
  ok. 2,5 m tylko częściowo gasi snop — przebicia widać najlepiej w pełnych ścianach i drzwiach.
- **Deska poprzeczna do drogi jest widziana z boku** (kamera z przodu, na osi z): w pogodną noc prawie jej nie widać, we mgle widać ciemną
  sylwetkę słupka; dziur w niej samej nie widać. Wniosek dla D0: zniszczalne obiekty **poprzeczne** (barykady, drzwi, deski w przejściu)
  informują o uszkodzeniu światłem za nimi, odłamkami, dźwiękiem i zmianą sylwetki (rozpad na bryły), a **maska z dziurami pracuje na
  obiektach równoległych do ekranu** (skrzynie, zabite deskami okna i ściany w tle, płoty wzdłuż drogi), gdzie widać ją wprost.
- **Koszt:** maska z `alpha scissor` kontra zwykły materiał **+0,001 / +0,007 / −0,032 ms GPU** (trzy przebiegi po 180 klatek, w szumie),
  sama deska +0,09 / −0,02 / +0,04 ms przy klatce 8,3 ms, z aktywnym cieniem latarki. Zapis dziury do maski w GDScript (`set_pixel` w pętli
  + `update` 128 × 80) **0,1–1,3 ms na dziurę** — w D0 gotowy stempel `Image.blend_rect` i jedno `update` na obiekt na klatkę (seria z karabinu
  to kilka trafień na klatkę).
- **Czego S1 nie sprawdził:** pęknięcia w normalnych, krawędź drzazg, odłamki, deska pod kątem do kamery, wiele obiektów z maską naraz,
  koszt przerysowania cienia przy serii (każde trafienie = nowa mapa cieni latarki; latarka w ruchu i tak ją przerysowuje co klatkę).

**Zmiany w planie po S1:** wiersz „Stopnie uszkodzeń” (poświata przez dziury we mgle zależy od #578 i jest miękka, odświeżenie cienia po zmianie
maski, stempel zamiast pętli, gdzie maska ma sens); poprawka mgły w osobnym PR ssiwm/gameon#578 (błąd obecnej gry, poza tym planem) —
D0 zakłada ją scaloną (z poprawką startu we mgle z c71cd48).

### Wynik S2 (2026-11-02, gałąź robocza `spike/dig-zone`, test `--digtest` 14/14)

Strefa 10 × 8 kafli w gruncie pod startem 1.1 (`--digzone=z1_m1:2,23,11,30`), siatka 4 × 4 na kafel, kolizja z odcinków
(`ConcavePolygonShape2D` na fragment 16 × 16 komórek), kilof przez `weapon_controller._server_melee`, siatka 3D w `view3d._sync_dig_zones`.
Zrzuty z okna: `--digshots=KATALOG`.

**Odpowiedzi**

- **Czy `CharacterBody2D` chodzi po konturze z marching squares — tak, po trzech poprawkach** (bez nich nie):
  1. Narożniki pierścienia (kafle mapy tuż za strefą) leżące na krawędzi kafla dostają gęstość **ISO**, nie 255 / 0. Inaczej na szwie
     strefa / mapa wychodzi skos 2 px z jednej strony i pionowy próg 2 px z drugiej — prostokąt postaci na nim staje (zmierzone: marsz
     w lewo zatrzymany na x 201). Po poprawce rozrzut wysokości stóp na szwie 0,00 px w obie strony.
  2. **Wyrwa kilofa nie jest kołem wokół punktu trafienia**, tylko prostokątem liczonym od postaci i wyrównanym do siatki komórek
     (gęstość = odległość od brzegu kształtu w paśmie ±4 px, łączona przez `min`, czyli dokładna suma brył). Koło o promieniu 13 px dawało
     tunel niższy od postaci (efektywnie ok. 9 px po progu ISO): 13 z 14 ciosów w bok bez postępu. Zaokrąglone rogi na siatce 4 px dawały
     fazę na całą komórkę, po której dno tunelu wędrowało w górę (2,7 px na 5 kafli). Prostokąty na siatce: dno płaskie (0,0 px na całej
     długości).
  3. **Klin:** prostokąt postaci (10 × 22 px) w szczelinie „V” o ścianach stromszych niż 45° wisi rogami na dwóch ścianach — nie jest
     „na ziemi”, spada z prędkością 620 px/s w miejscu i nie może skoczyć (zmierzone w szybie 16 px z fazami: zaklinowany na stałe).
     Szyb poszerzony do 20 px (płaskie dno szersze od postaci) i bezpiecznik w `player.gd`: wiszenie w „V” (dwie kolizje z normalnymi
     w przeciwne strony, obie w górę, pozycja stoi) odnawia coyote, więc da się wyskoczyć. Pierwsza wersja bezpiecznika (każde zatrzymanie
     przy dwóch kolizjach) wyłączała grawitację przy ścianie w szczycie skoku i przyklejała postać — zawężona.
- **Marching squares nie da ostrych rogów obu rodzajów naraz**, gdy narożnik leży dokładnie na progu. Wybór: wklęsłe rogi wyrwy (dno przy
  ścianie) ostre, wypukła krawędź przy wierzchu strefy dostaje skos 45° na komórkę (4 px). Skos działa jak małe podciągnięcie (wyjście
  z dołu sięga 48 px zamiast 44) i wizualnie fazuje krawędź — zostaje.
- **Wrażenie kopania (liczby):** szyb w dół 12 px na cios (2 kafle = 3 ciosy, ok. 2,7 s przy cooldownie kilofa 0,9 s), tunel w bok
  **0,99 kafla na cios** (wysokość 28 px = wzrost + 6, czoło 19 px przed środkiem postaci, tył 8 px za nim), schody w dół 8 px na cios,
  stopień w górę 8 px. Kształt idzie za kierunkiem ciosu (8 kierunków `aim_dir`), więc nie trzeba celować w piksel — jak „smart cursor”
  z Terrarii. Kopanie w samej ziemi jest **szybkie**: znajdźka 4–6 kafli w głąb to 4–6 s, a plan zakłada 20–40 s w co-op, więc twardość
  materiału musi dzielić cios (skała: siła 85–128 zamiast 255, 2–3 ciosy na wyrwę; żyła 3–4). Wartości do strojenia w grze.
- **Czy łatwo się zakopać — tak, ale nie na stałe:** skok sięga ok. 44 px; z dołu 48 px wychodzi się dzięki skosowi krawędzi, z 60 px już nie.
  **Ratunek bez pomocy działa:** cios po skosie w górę wycina stopień 8 px i podnosi strop nad postacią (tył wyrwy 8 px za nią — bez tego
  nad stopniem zostawało 4 px luzu i nie dało się wskoczyć); z 60 px wyjście w 4 ciosach. Prawdziwa pułapka powstaje tylko tam, gdzie
  ściany dołu są niekopalne (brzeg strefy, kafle mapy) — stąd poprawiona reguła anty-pułapki w D5.
- **Koszt:** przebudowa konturu i kolizji po ciosie 0,4–1,2 ms (1–4 fragmenty, GDScript), siatka 3D **1,0–1,4 ms na fragment** po
  optymalizacji (było 4,4 ms: wywołanie `Callable` na wierzchołek, tablice w pętli, dwa trójkąty na każdą pełną komórkę; teraz pełne komórki
  scalone w pasy w wierszu). Cios dotyka zwykle 1–2 fragmentów, więc 1–3 ms w klatce ciosu na głównym wątku — do przyjęcia przy cooldownie
  0,9 s; limit „4 fragmenty na klatkę” z D0 zostaje (wybuch).
- **Obraz:** zrzuty z okna złapały błąd, którego test headless nie widzi — przód strefy był wycinany jako tył (Godot: przód zgodnie z ruchem
  wskazówek, odbicie osi y przy przejściu ekran → 3D kolejności nie odwraca). Po poprawce przód ma teksturę jak teren mapy obok, tunel
  widać jako wnękę z dnem i ścianami w świetle latarki. Wnętrze wykopu w nocy jest bardzo ciemne (dobrze dla horroru); pył, grudki i dekal
  świeżego wykopu z D5 — nadal do zrobienia.
- **Sieć:** operacja kopania to prostokąt (środek, połówki boków, zaokrąglenie, siła) — kilkanaście bajtów RPC, każdy peer liczy sam,
  wynik identyczny. Delta komórek potrzebna tylko dla dołączającego (stan strefy), zgodnie z D0.
- **Czego S2 nie sprawdził:** ręczne wrażenie z pada i myszy (test steruje wejściem z kodu), osypywanie żwiru, wyspy, znajdźki, klient
  w sieci, wybuch (`blast_dig` jest, niepodpięty do `Combat.explode`), aktualizacja nawigacji i siatki dźwięku po wykopie.

**Zmiany w planie po S2:** tabela technologii D5 (kształt wyrwy, gęstość jako przycięta odległość, narożniki pierścienia, koszt siatki 3D,
klin), reguła anty-pułapki (3 kafle i niekopalne ściany zamiast 2 kafli), bezpiecznik klina w `player.gd` jako część D5, twardość materiału
jako dzielnik ciosu.

## Etapy

### D0 — fundament (bez nowej zawartości)

- **`breakable.gd`** zamiast `brick_wall.gd`: jedna klasa z **materiałem** (`brick`, `planks`, `sheet`, `grate`, `glass`, `support`) i tabelą
  w stylu `surfaces.gd`: HP, co niszczy (kilof / maczeta / kule / śrut / wybuch / szarża), hałas uderzenia i rozbicia, dźwięki, kolor gruzu,
  czy blokuje kule, czy blokuje widok i światło. Ściana `q` = materiał `brick` (zachowanie bez zmian, testy Rzeźnika i kilofa zielone).
  **Zrobione w 1.7.480:** `breakable.gd` (`MATERIALS`, `hit_kind`: pick / blade / bullet / pellet / blast / charge), szarża Rzeźnika
  jako osobny rodzaj trafienia `charge`; poza `brick` wartości wstępne. Przepuszczanie kul i światła (kratka, rozbite szkło) — razem
  z pierwszym takim elementem na mapie (D1).
- **Uszkodzenia**: serwer wysyła zdarzenie trafienia (punkt, promień plamy, stopień 0–2), a nie HP — każdy peer wypala tę samą plamę
  w masce, więc dziury wyglądają u wszystkich tak samo; dołączający dostaje listę plam obiektu. Trafienia w ułamku sekundy łączone
  w jedno RPC (seria z M-83 to nie 10 wiadomości).
  **Zrobione w 1.7.481:** `breakable.gd` — plama (u, v, promień wg rodzaju trafienia `SPLAT_R`, stopień wg siły: < 10% / < 34% / więcej),
  paczka pod koniec klatki pierwszego trafienia, kolejne co `SPLAT_GAP` 0,1 s (`_splat_rpc`, reliable), dołączający przez `send_walls_to`
  (`_splat_sync`, do `MAX_SPLATS` 64); `damage_mask.gd` — maska R8 2,5 cm/teksel, odcisk przez max (kolejność bez znaczenia), nakładka
  `material_overlay` z mnożeniem obrazu (`blend_mul`, bez cieniowania: tekstura zostaje, brzeg jaśniejszy, środek ciemny, szarpany szumem).
  Cegła ma tylko przyciemnienie — przelotowe dziury (alpha scissor + poruszenie modelu dla cienia, S1) z deskami w D1. `--destructiontest`
  w CI; zrzuty `--shotbreak=2` w `C:\deadair87\shots_damage`.
- **Lokalna przebudowa nawigacji**: `Nav.rebuild_region(rect)` — usuwa węzły i krawędzie w prostokącie powiększonym o zasięg skoku
  (`GAP_SIDE` = 4 w bok, `JUMP_UP` = 2 w górę, spadki w kolumnach do podłogi) i dokłada je od nowa. Cel: < 2 ms. Test: graf po lokalnej
  przebudowie identyczny z pełną budową (porównanie punktów i krawędzi) dla każdej ściany i każdej mapy. **Naprawia też dzisiejsze przycięcie
  przy `q`.** **Zrobione w 1.7.479:** pas nad prostokątem przelicza tylko zejścia i zeskoki, kafle w kopii `PackedByteArray` zamiast wywołań
  `Callable`; `--maptest` (80 losowych zmian 1–4 × 1–5 kafli na mapę + każda ściana) — 0 różnic, średnio 0,4–1,5 ms, najdłużej 1,3–4,9 ms (z innym testem w tle).
- **Stan zniszczeń w jednym miejscu** (`level.gd`): lista zniszczonych z nazwami, synchronizacja dołączających (uogólnione `send_walls_to`),
  reset przy wipe, nowej misji i **punkcie kontrolnym bossa** (stan z chwili przebudzenia — jak łup od 1.7.424).
  **Zrobione w 1.7.482:** `level.gd` — `breakables_state()` (rozbite z `_opened_walls` + plamy i ułamek HP stojących), migawka
  `save_breakables_checkpoint()` przy przebudzeniu bossa (`mission._save_checkpoint`), `reset_breakables(stan)` na serwerze → jedno RPC
  do wszystkich: rozbite, których nie ma w stanie, wracają (kafle bryły, nawigacja lokalnie, gracze wypchnięci jak przy zamknięciu
  przejścia), brakujące rozbicia dochodzą bez gruzu i hałasu, stojące dostają plamy i HP ze stanu. Wipe (`_restart_mission`) — stan
  pusty, wipe w walce z bossem (`_restart_from_checkpoint`) — migawka. `breakable.damage_epoch` mówi widokowi 3D, że maskę trzeba
  odcisnąć od zera. Nowa misja i tak ładuje mapę od nowa.
- **Widok 3D**: każdy materiał ma jeden model z shaderem maski uszkodzeń i zestaw brył z pre-fraktury (skrypt Blendera w `tools/`,
  w stylu generatorów — bmesh, cięcie płaszczyznami Voronoi, osobny materiał przekroju; Blender 5.2 headless). Źródła: tekstury desek,
  cegły, rdzy i skały z ambientCG / Poly Haven (CC0, już używane w `art/world3d/`), proste bryły (deska, kratka, lampa) z generatora
  w Blenderze; złożone modele z Poly Haven, w razie potrzeby lokalny TRELLIS 2 (obraz → model z PBR, potrzebuje obrazu wejściowego —
  nie mamy lokalnie tekst → obraz) albo Meshy (ok. 30–40 kredytów za rekwizyt). Każdy nowy GLB przez `tex_vram.py`. Odłamki przez `Vfx.debris`, potem leżą jako gruz
  w `MultiMesh` do końca misji (limit globalny, najstarsze znikają). Szczegóły w „Technologie”.
  **Zrobione w 1.7.483:** `tools/fracture_gen.py` (Blender 5.2 headless, bmesh: `bisect_plane` + zaślepienie, materiały `outer` / `inner`)
  → `art/items3d/fracture_brick.glb`, 12 wypukłych brył wypełniających kostkę 1 m (objętość 1,000 m³). `breakable.chunk_plan(ziarno)` —
  `chunks` brył (cegła 9) rozłożonych po ścianie siatką z odchyleniem, z ziarna `map_id` + nazwa, więc u wszystkich te same bez RPC;
  `crumble` puszcza je przez `Vfx.debris` (fizyka 2D), widok 3D (`mirror_chunk`) rysuje bryłę z teksturą triplanarną w przestrzeni bryły
  i świeżym przełomem w przekroju; po wylądowaniu (albo po 4 s) bryła przechodzi do `MultiMeshInstance3D` na kształt (`RUBBLE_CAP` 32,
  najstarsze znikają), ciało 2D znika. Gruz żyje z geometrią mapy, odbudowa ściany (wipe, punkt kontrolny) go sprząta. Bryły wczytywane
  przy budowie ściany (pod planszą). Zestawy dla desek, blachy, kratki i szkła — z elementami D1/D2. Zrzuty: `C:\deadair87\shots_fracture`.
  **Zrobione w 1.7.484 (rozgrzanie):** przy budowie ściany pod planszą `view3d._warm_destruction` stawia przed kamerą na kilka klatek
  bryłę, `MultiMesh` gruzu i model `rubble` (raz na mapę i materiał), a rzut mapy w HUD-zie przemalowuje po rozbiciu / odbudowie tylko
  zmienione kafle (`hud_minimap._repaint_walls`). Pomiar `--hitchtest --hitchwall` (okno, 1.2): pierwsze rozbicie 104–150 → 30–45 ms,
  odbudowa 67–90 → ok. 30 ms. Sam `crumble` to 2,5–4,4 ms CPU, lokalna nawigacja 1,3–2 ms. **Pula cząsteczek jeszcze nie:** przy
  rozbiciu nie wyszła w pomiarze jako koszt (kilka emiterów na zdarzenie) — wraca z D1, gdy skrzynie, szkło i lampy dołożą emiterów.
- `--maptest`: osiągalność celów **przy wszystkim całym i wszystkim zniszczonym** (rozszerzenie `open_all_walls_for_test`).
  **Zrobione (PR bez numeru wersji, same testy):** na mapach ze zniszczalnymi elementami najpierw wszystko całe — starty, wyjścia,
  generatory, nieśmiertelniki, gniazda, drezyna, stanowiska i dom Stalkera osiągalne bez rozbijania (przejście to skrót albo skrytka,
  nie warunek), wydruk tego, co leży za ścianą (1.2: trzy przedmioty), potem wszystko rozbite (`open_walls_checked`) — każdy punkt
  mapy osiągalny, także dla dźwięku. Nieużywane `open_all_walls_for_test` usunięte.
- Nowy `--destructiontest` w CI: obrażenia wg materiału, hałas, stopnie, sieć (dołączający widzi zniszczenia), reset, punkt kontrolny,
  czas lokalnej nawigacji.
  **Sieć zrobiona (ten sam PR co `--maptest`):** `tools/test_net_session.sh`, sekcja „zniszczenia” (`--destructionnet=N`): host rani
  ścianę 1.2, rozbija ją po zapisaniu migawki, wraca do migawki i robi wipe; klient obecny od początku i klient dołączający po ciosach
  mają po każdym kroku ten sam stan co host (rozbite, HP, plamy z sumą kontrolną). Czas lokalnej nawigacji sprawdza `--maptest`.

### D1 — rekwizyty, które pękają (najmniejsze ryzyko, od razu widać)

- **Skrzynia `k`** pęka po N trafieniach / wybuchu / szarży (dziś tylko lata): drzazgi, hałas; wypada drobny łup (złom 1–2,
  rzadko bateria; decyzja 3) — zgodnie z progresją z `PROGRESSION_PLAN.md`, do strojenia.
  **Zrobione w 1.7.485:** `prop.gd` — skrzynia ma 40 HP (`CRATE_HP`): pistolet 5 kul, maczeta 2 ciosy, kilof / granat / szarża Wołka
  i Rzeźnika od razu; płomień tylko popycha; wybuch beczki rozbija skrzynię bliżej niż 0,6 promienia, dalszą odrzuca. `shatter` (serwer):
  hałas 4, łup — złom 1–2 z szansą 0,6 i bateria 0,05 (× „drops” trudności; w Nocnym Dyżurze nic), zdarzenie `crate` w dzienniku sesji
  (do strojenia z playtestów), drzazgi u wszystkich (`_shatter_fx`): 6 kawałków deski z nowego zestawu `fracture_planks.glb`
  (`tools/fracture_gen.py`, tryb `cuts`: listwa 1 × 0,11 × 0,03 m, 3 cięcia pochylone o 25–50° — Voronoi na długiej listwie dawał
  prostopadłe, krępe kawałki) z planu z ziarna, lecące od uderzenia, potem gruz w `MultiMesh`; 8 wiórów i kurz. Widok 3D: drewno
  skrzyni na zewnątrz, jasny przełom; rozgrzanie desek przy pierwszej skrzyni pod planszą; drzazgi znikają, gdy skrzynia wraca (wipe) — także te jeszcze w ruchu, przed przejściem do gruzu (dotyczy też brył cegły przy odbudowie ściany).
  Dołączający dostaje rozbite skrzynie i — przy okazji — wybuchłe beczki (`send_state_to`; beczki dotąd stały u niego całe).
  Dźwięk: na razie `door` + `amb_creak` — porządne nagranie pękającego drewna do odsłuchu A/B. Zrzuty: `C:\deadair87\shots_crate`.
- **Beczka `o`**: zostaje wrak z osmaleniem zamiast znikania.
  **Zrobione w 1.7.486:** `prop.gd` — po wybuchu `wreck` (beczka osiada na podłożu pod sobą, `_floor_below`; dołączający dostaje punkt
  z `_gone_rpc`), `view3d._set_wreck` — model przysiadły (×1,12 / 0,68), przekrzywiony, nakładka sadzy (`_wreck_mat`, mnożenie),
  plama osmalenia 1,7 m i gasnący żar 9 s; reset przywraca całą beczkę. Dev `--shotbarrel[=2]`.
- **Lampy na misjach do zestrzelenia** (nowy znacznik): gaśnie światło, sypie szkło, krótki dźwięk. W grze o ciemności to realna
  decyzja: ciemniej = trudniej widzieć, ale też trudniej być widzianym (Stalker, Ćmy lecą do światła). Dziś lampy `l` są tylko w kryjówce.
  **Zrobione w 1.7.487:** znacznik `I` (`level.gd`, `MissionLamp1…`), `lamp.gd` z `shootable` — klosz `LampBody` (warstwa 32, grupa
  `shootables`: `projectile.gd` i `Combat.trace` go trafiają i lecą dalej, `Combat.explode` tłucze w promieniu), `shatter` (serwer: hałas 3,
  zdarzenie `lamp`) → `_break_rpc` (światło, 10 odłamków szkła, iskry, `glass_break`); `Lights.lamp_lit_player` — gracz do 8 m od zapalonej
  żarówki widoczny dla Stalkera z 12 m (oba odcinki bez ściany, `stalker.gd` obok latarki i broni świetlnej); ćmy krążą przy zapalonej jak
  przy płomieniu, ale na odległość konkurują z latarką (`enemy_moth.gd: nearest_light`). Reset w `level._reset_breakables_rpc`
  (wipe i punkt kontrolny), dołączający — `send_state_to`. Mapy: 1.1 — 2 lampy, 1.2 — 3 (1.3 bez zmian). Dev `--shotlamp[=2]`,
  zrzuty `C:\deadair87\shots_lamp`.
- **Szkło / okna** w budynkach (1.2 chata radiowa, 1.3 Skład): pęka od kuli, przepuszcza potem kule i dźwięk głośniej.

### D2 — przejścia do otwierania (rdzeń mechaniki)

Nowe znaczniki map (litery do wybrania z wolnych):

- **Deski / barykada** (`planks`): maczeta (GDD §6 już obiecuje „niszczy cienkie drzwi”), kilof, śrut, wybuch, Rzeźnik. Cicho kilofem
  i maczetą (kilka ciosów), głośno strzelbą (szybko).
- **Zardzewiała kratka wentylacji / blacha** (`grate`, `sheet`): tylko kilof i wybuch; skrót do skrytki albo boczna droga ucieczki.
- **Zamurowanie `q`** zostaje jako najtwardszy wariant.
- Wrogowie: Rzeźnik przebija wszystko poza kratką; Wołek łamie deski szarżą; Trzoski drapią barykadę (wolno, słychać) — gracz może się
  zabarykadować na chwilę, nie na zawsze.
- Bot: zna kilof i maczetę na przejściach na trasie dowódcy (dziś podpowiedź `pickaxe` w `hints.gd` jest tylko dla gracza).
- **Projekt map**: na każdej misji 1–3 takie miejsca, zawsze **opcjonalne** (skrót, skrytka, druga droga), nigdy jedyna droga do celu bez
  narzędzia, które gracz na pewno ma.
- **Dziury jako informacja** (Siege, Darkwood): serwer trzyma listę dziur każdej przegrody (środek i promień z maski). Linia wzroku wrogów
  (`clear_line`), snop latarki budzący wrogów i kule przechodzą przez przegrodę, jeśli promień trafia w dziurę; dźwięk przez przegrodę
  z dziurami słabiej tłumiony (`sound_grid`). Skutek: przestrzelona deska to wizjer do podglądania — ale też szpara, przez którą wróg widzi
  światło latarki.

### D2b — barykadowanie (nowe w v4, po D2)

- Gracz przybija deski w oznaczonych otworach (okno, wyrwa, przejście), przytrzymując `[E]` (ok. 2 s na deskę, 3 deski na otwór, młotek
  stuka = hałas). Koszt: złom albo deski z rozbitych skrzyń (łączy D1 z D2).
- Wrogowie słyszą stukanie i lubią barykady (jak w Darkwood): Trzoski drapią, Wołek i Rzeźnik rozbijają, Ćmy przelatują przez dziury.
  Barykada kupuje czas, nie bezpieczeństwo.
- Miejsce w grze: cele „przetrzymaj” (GDD §3, misja 2.3 Dzwon — obrona 3 fal) i ucieczka przed Stalkerem (zabarykadować przejście za
  sobą, żeby zyskać sekundy). W co-op: jeden przybija, drugi osłania.
- Technicznie to ta sama klasa `breakable` z materiałem `planks` w stanie „pusty otwór” — przybicie deski cofa stopień, a nie tworzy
  nowy obiekt; sieć i reset jak w D0.

### D3 — zawalanie za sobą (ryzyko / nagroda)

- **Podpory** (`support`): stempel w tunelu albo słup kładki do zestrzelenia / wysadzenia. Po zniszczeniu zapada się **z góry
  zaprojektowany** fragment: kładka spada albo strop sypie się i zamyka przejście (zgniata wrogów pod spodem, hałas jak wybuch).
- Technicznie: fragment, który się zawala, to od początku osobny węzeł (jak `breakable`), a nie kafle mapy — inaczej wraca problem 2ⁿ stanów
  geometrii 3D. Kafle mapy pod nim tylko rezerwują komórki dla nawigacji, jak `_wall_cells`.
- Zawał 1.1 zostaje na obecnym mechanizmie (decyzja 5: działa i jest pod `--finaletest`); przeniesienie dopiero, gdy podpory się sprawdzą.
- Dyrektor (`director.gd`) traktuje zawalone przejście jak zamkniętą drogę przy wypuszczaniu grup.

### D4 — kosmetyka walki (bez wpływu na rozgrywkę)

- Odpryski i kurz wg materiału przy trafieniu w świat (rozszerzenie `mark_hit`: beton — pył i odłamki, drewno — drzazgi, blacha — iskry,
  ziemia — grudki).
- Po wybuchu: sypiący się pył ze stropu w podziemiach, chwianie lamp kryjówki (tylko 3D, bez stanu).
- Ślady trwałe w obiektach do zniszczenia daje już maska uszkodzeń z D0 (dziury z prześwitem); tu tylko dekale na niezniszczalnym świecie.

### D5 — strefy wydobycia z wokseli (znajdźki i ukryte przedmioty)

Na misjach oznaczone fragmenty skały / ziemi, które można rozkopywać kilofem w drobnej siatce i znaleźć w nich zakopane rzeczy. To
**nie jest** kopalnia FPP z `MINING_PLAN.md` (osobny świat 3D pod kryjówką, PR #360) — strefy żyją w zwykłej symulacji 2D misji, więc
nie łamią zasady „symulacja 2D” i działają w co-op od razu.

**Rozgrywka**

- Strefa = prostokąt w danych mapy (`DIG_ZONES`: kolumny, rzędy, materiał, ziarno). Na mapie 1–3 strefy, zawsze **z boku drogi** (ściana
  korytarza, osuwisko, zasypana piwnica, nasyp przy torach) — nigdy na trasie do celu.
- **Kopanie = hałas.** Każdy cios kilofem to hałas jak w `brick_wall.gd` (1,5), więc kopanie w trakcie misji to ryzyko: Ślepcy słyszą,
  dyrektor może wypuścić grupę. Maczetą wolno i ciszej (tylko ziemia), wybuch szybko i bardzo głośno (rozrzuca też część znajdziek).
- Materiały: ziemia (każde narzędzie), żwir (osypuje się, gdy podkopać), skała (tylko kilof, wolniej), żyła rudy / złomu (więcej łupu).
- **Znajdźki**: złom, części broni (jak w `GUNSMITH_PLAN.md` 5c), baterie 4,5 V, amunicja, notatki i przedmioty fabularne (lore Strefy),
  rzadko skrzynka z czymś cennym. Rozmieszczenie deterministyczne z ziarna strefy i numeru odnowienia, rozstrzyga serwer.
- **Limit (decyzja 2026-11-02):** każda strefa ma **pulę cennych znajdziek** (złom, części, baterie, skrzynka). Wykopana znajdźka znika
  z puli na stałe — stan pul trzyma host w zapisie postaci (`progress.cfg`, jak bank złomu). Pula odnawia się po **3 udanych misjach**
  na innych mapach (nowe ziarno = nowe miejsca). Pusta strefa daje tylko drobnicę (amunicja, pojedynczy złom), więc kopanie zawsze coś
  znaczy, ale nie da się go farmić. Wykopane rzeczy idą do łupu misji (`Scrap.loot`), więc przepadają przy wipe; notatki fabularne raz
  na zawsze (kodeks). Nocny Dyżur bez złomu, jak wszędzie. Wielkość puli i próg odnowienia do strojenia po playteście
  (`session_progress.py`, `PROGRESSION_PLAN.md`).
- **Szukanie**: skaner „Sowa” (`scanner_view.gd`) pokazuje też zakopane metalowe przedmioty w zasięgu; bez skanera — błysk przedmiotu
  w latarce, gdy odkopie się go do połowy, i inny dźwięk ciosu w metal.
- Zawalanie: podkopany żwir i ziemia bez podparcia opadają (prosta reguła komórkowa jak piasek, tylko w obrębie strefy) — można zasypać
  przejście albo wroga, ale też siebie (krótkie przygniecenie, nie śmierć). Liczone tylko w „brudnych prostokątach” (komórki ruszone
  w ostatnich sekundach), krok 15–20 Hz, na serwerze; wynik idzie jak zwykła delta komórek (Noita). **Wyspy skały bez połączenia z brzegiem
  strefy spadają** jako jeden odłamek (sprawdzenie spójności zalewaniem po każdym ciosie, który coś odciął) — nic nie wisi w powietrzu
  (lekcja z Teardown).
- **Anty-pułapka** (lekcja z SteamWorld Dig, liczby z S2): z dołu do 48 px (3 kafle) wychodzi się skokiem, z głębszego — stopniami
  wyciętymi po skosie w górę (4 ciosy z 60 px). Dlatego strefa nie schodzi niżej niż **3 kafle pod najniższe wejście tam, gdzie jej
  ściany są niekopalne** (brzeg strefy przy kaflach mapy, materiał, którego nie bierze żadne narzędzie); przy kopalnych ścianach głębokość
  jest wolna. Cios po skosie zostawia stopień 8 px, a nie pionową ścianę; bezpiecznik klina w `player.gd` (wiszenie w „V” = ziemia do skoku);
  `--digtest` sprawdza na losowych wykopach, że z każdej komórki, w której gracz może stać, istnieje droga na zewnątrz. Znajdźki leżą **w bok i w głąb ściany**, nie pod wejściem — kopanie
  prosto w dół nie ma być najlepszą strategią.
- **Rytm co-op** (lekcja z Deep Rock Galactic): wydobycie cennej znajdźki trwa ok. 20–40 s kopania w hałasie — dość, żeby opłacało się,
  by jeden kopał, a drugi pilnował; bot pilnuje kopiącego człowieka (nie kopie sam).
- **Odpowiedź natychmiast, stan z serwera** (lekcja z The Finals): cios od razu daje u kopiącego iskry, pył, dźwięk i wibrację; komórki znikają,
  gdy przyjdzie delta z serwera (u hosta w tej samej klatce, u klienta po czasie odpowiedzi — ok. 1–3 klatki w LAN).

**Technologie**

| Element | Wybór | Uwagi |
|---|---|---|
| Dane | Siatka **4 × 4 komórki na kafel** (komórka 4 px = 0,33 m; decyzja 2026-11-02), gęstość 0–255 w `PackedByteArray` jako **przycięta odległość od brzegu** (±4 px, brzeg = ISO − 1, łączenie wyrw przez `min`), osobna tablica materiałów. Narożniki pierścienia (kafle mapy tuż za strefą) na krawędzi kafla = ISO — szew strefa / mapa bez progu (S2). | Strefa 20 × 10 kafli = 3200 komórek — znikome dane |
| Wyrwa | **Prostokąt od postaci, wyrównany do siatki**, kształt z kierunku ciosu: w bok przejście 28 px wysokości (czoło 19 px przed, tył 8 px za środkiem postaci), w dół szyb 20 × 12 px, w górę wnęka 12 px, po skosie stopień 8 px. Cios kopie, gdy we wnętrzu prostokąta jest skała; twardość materiału ogranicza gęstość zabraną na cios (2–3 ciosy na wyrwę w skale). Wybuch: koło (S2). | Koło wokół punktu trafienia (pierwsza wersja S2) — tunel niższy od postaci, dno wędruje, kliny |
| Siatka 3D | **Marching squares** po gęstości → kontur → bryła wyciągnięta w głąb do `DEPTH_BACK`, przód z przemieszczeniem szumem, krawędzie fazowane; fragmenty 16 × 16 komórek, przebudowa tylko dotkniętego fragmentu **na głównym wątku** (kontur 0,18 ms w najgorszym przypadku, siatka 3D w GDScript 1,0–1,4 ms na fragment po scaleniu pełnych komórek w pasy — S2; limit 4 na klatkę, reszta w następnej). Materiał PBR **triplanarny** (te same skany co ściany mapy, bez szwów na krzywych), okluzja z głębokości wykopu w kolorach wierzchołków (tanie „wnętrze jaskini”), tylna ściana wykopu. | `godot_voxel` (Zylann) — moduł C++ zależny od wersji silnika i robiony pod 3D, a nam wystarcza siatka 2D z głębią; własny greedy meshing z `MINING_PLAN.md` — sześciany, kanciaste, nie pasują do gładkiego terenu mapy |
| Kolizja | Te same odcinki z marching squares → **`ConcavePolygonShape2D` na `StaticBody2D`**, jeden na fragment (co widać, w to się uderza; gładkie skosy, puste kieszenie i wyspy działają same, bo to tylko odcinki; podmiana 0,08 ms). Odłamki i łuski w strefie z `continuous_cd`. Postać (prostokąt 10 × 22) zawisa w szczelinach „V” stromszych niż 45° — bezpiecznik klina w `player.gd` (S2). | Drobne kafle 4 px w `TileMapLayer` — postać „tnie” na schodkach; `CollisionPolygon2D` (tryb SOLIDS) i `BitMap.opaque_to_polygons` — nie obsługują dziur w wielokącie (sprawdzone pomiarem) |
| Świat 3D mapy | Komórki strefy są pomijane przy wypiekaniu (`Level3D.build_level`), bryłę strefy rysuje jej własny węzeł — bez przebudowy świata. | — |
| Nawigacja | Kafel strefy przechodni, gdy w środku nie ma już gęstości ponad próg; zmiana kafla → `Nav.rebuild_region` z D0. | Bot i wrogowie nie wchodzą w niedokończone tunele |
| Dźwięk | `sound_grid.refresh(region)` po zmianie kafla (już jest). | Odkopany tunel przewodzi hałas |
| Sieć | Klient wysyła cios (pozycja, narzędzie), serwer sprawdza zasięg i rozstrzyga; RPC: chunk + zmienione komórki (delta), dołączający dostaje deltę strefy, reset przy wipe / punkcie kontrolnym. | Ten sam wzorzec co zniszczenia z D0 |
| Efekty | Grudki i kamyki przez `Vfx.debris` (kolor z materiału komórki), pył z puli z D0, dekal świeżego wykopu. | — |

**Zależności:** D0 (lokalna nawigacja, stan zniszczeń, reset, sieć). Niezależne od D1–D4. Testy: `--digtest` (cios → komórki, hałas,
materiały i narzędzia, osypywanie, znajdźki deterministyczne, sieć z dołączającym, reset, czas przebudowy chunka), `--maptest` (strefy
nie leżą na trasie do celu).

**Relacja z `MINING_PLAN.md` (decyzja 2026-11-02): strefy zapowiadają kopalnię FPP.**

- **Przed kopalnią:** strefy uczą kopania (kilof, hałas, materiały, osypywanie, szukanie skanerem) i opowiadają o niej: notatki górników,
  zasypane wejścia sztolni, stare tory i lampy karbidowe w strefach, ślady Pasożytów Głębinowych. Na mapie, gdzie strefa jest najgłębiej,
  jedna z nich kończy się zawaloną kratą szybu — miejsce, przez które później schodzi się do kopalni (albo jego odpowiednik w kryjówce).
- **Wspólny język:** te same nazwy i kolory materiałów co w kopalni (ziemia, żwir, skała, żyła), te same dźwięki ciosów i osypywania,
  ta sama zasada „kopanie = hałas” (w kopalni przez osobną Uwagę z §3.0). Tabela materiałów jako jeden plik danych, z którego potem
  czyta też `voxel_mine.gd` (siatki są różne: tu 2D z głębią, tam woksele 3D 1 m — wspólne są dane, nie mesher).
- **Kiedy kopalnia wejdzie:** samorodki T1 / T2 z §5C nie leżą już na mapach, tylko są w pulach stref (te same ilości na mapę); do tego
  czasu w pulach ich nie ma, bo nie byłoby ich na co wydać.
- Do zrobienia przy scalaniu: poprawić §5C w `MINING_PLAN.md` (PR #360) — samorodki ze stref D5 zamiast leżących.

## Kolejność i rozmiar

| Etap | PR-y | Ryzyko | Zależność |
|---|---|---|---|
| S1, S2 (spike'i) | 0 (gałęzie robocze, wynik do planu) | — (po to są) | — |
| D0 | 2–3 (nawigacja lokalna osobno — sama w sobie jest poprawką) | średnie (sieć, reset, punkt kontrolny) | — |
| D1 | 1–2 | niskie | D0 |
| D2 | 2 (mechanika + mapy) | średnie (projekt map, bot) | D0 |
| D2b | 1 | średnie (strojenie wrogów przy barykadach) | D2 |
| D3 | 1–2 | wysokie (geometria, nawigacja, dyrektor) | D0, D2 |
| D4 | 1 | niskie, ale budżet GPU | niezależny |
| D5 | 3 (dane + siatka + kolizja; znajdźki i skaner; mapy i ekonomia) | średnie (wyczucie ruchu po krzywym terenie, ekonomia) | D0 |

Pierwszy krok, który warto zrobić od razu niezależnie od reszty: **lokalna przebudowa nawigacji** — usuwa dzisiejsze ok. 0,12 s przycięcia
przy rozbiciu ściany na 1.2.

## Pomiar po wdrożeniu

- Dziennik sesji (`session_log`): zdarzenie `break` (materiał, czym, kto, hałas) → ile przejść otwierają gracze, czym, czy to ściąga wrogów.
- `--hitchtest` / `[PERF]`: rozbicie w walce bez klatki > 33 ms.
- Dziennik sesji: `dig` (strefa, czas kopania, znajdźki, czy ściągnęło wrogów), `barricade` (przybite, rozbite przez kogo, ile sekund
  wytrzymało) → czy gracze w ogóle kopią i barykadują, czy to się opłaca, czy nie utykają (czas w strefie bez ruchu na zewnątrz).
- Playtest z pytaniem wprost: „czy rozbijanie / kopanie było przyjemne?” — wrażenie sprawdza się u ludzi, nie w testach.

## Źródła researchu (2026-11-02)

- Spelunky 2: [Digital Trends](https://uat4.www.digitaltrends.com/gaming/everything-to-know-about-spelunky-2),
  [GamesRadar](https://www.gamesradar.com/spelunky-retrospective), [PlayStation Blog](https://blog.playstation.com/archive/2018/08/29/first-look-at-spelunky-2-gameplay-plus-new-derek-yu-interview)
- SteamWorld Dig: [Game Developer — Game Design Deep Dive](https://www.gamedeveloper.com/design/game-design-deep-dive-the-digging-mechanic-in-i-steamworld-dig-i-)
- Rainbow Six Siege: [GDC Vault — The Art of Destruction](https://gdcvault.com/play/1023003/The-Art-of-Destruction-in),
  [Ubisoft — wywiad z J. L'Heureux](https://news.ubisoft.com/en-us/article/4GHX2yepSaKkflLjLAlpwO/the-art-of-destruction-in-rainbow-six-siege-an-interview-with-julien-lheureux),
  [Ubisoft dev blog](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1QkezaGoRkDWqcQ6duGvtk/dev-blog-explosions-shrapnel-in-y5s1)
- Darkwood: [Steam — dyskusje graczy](https://steamcommunity.com/app/274520/discussions/0/1751274167969701321) (źródło słabe — opinie graczy)
- Noita: [GDC Vault — Exploring the Tech and Design of Noita](https://gdcvault.com/play/1025695/Exp), [80.lv](https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation/)
- Teardown: [PC Gamer — recenzja](https://www.pcgamer.com/teardown-review/), [80.lv](https://80.lv/articles/this-real-time-voxel-building-demolition-is-so-satisfying/)
- The Finals: [PC Gamer](https://pcgamer.com/i-almost-dont-believe-the-destructibility-in-this-fps-is-real), [The Finals Wiki — Meet the Makers](https://www.thefinals.wiki/wiki/Meet_The_Makers%CB%90_Movement)
- Deep Rock Galactic: [Unreal Engine — wywiad](https://www.unrealengine.com/developer-interviews/guns-gold-and-glory-in-the-caverns-of-deep-rock-galactic),
  [GameTyrant — wywiad](https://gametyrant.com/news/deep-rock-galactic-interview-a-balanced-co-op-challenge-game)
- Broforce: [Cubed3 — hands-on](https://www.cubed3.com/preview/524/1/broforce-hands-on-pc.html), [RGCD — zapowiedź](https://www.rgcd.co.uk/2012/09/broforce-preview-pc.html?hl=en)
- Vlambeer: [Game Developer — rady J. W. Nijmana](https://gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games), [Unwinnable — Luftrausers](https://unwinnable.com/2014/06/16/notes-on-luftrausers/)
- Godot 4.7: [Shading language — instance uniforms](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html),
  [BitMap](https://docs.godotengine.org/en/4.7/classes/class_bitmap.html), [ConcavePolygonShape2D](https://docs.godotengine.org/en/4.7/classes/class_concavepolygonshape2d.html),
  [GPUParticlesCollisionHeightField3D](https://docs.godotengine.org/en/4.7/classes/class_gpuparticlescollisionheightfield3d.html)

## Decyzje

Wszystkie decyzje z v4 rozstrzygnięte 2026-11-02 (po spike'ach S1 i S2):

1. **Zakres:** zniszczalne są **tylko oznaczone elementy** (osobne znaczniki map); zwykłe kafle, w tym kładki `-`, zostają niezniszczalne.
2. **Kolejność:** **D0 + D1** (rekwizyty: skrzynie, beczki, lampy, szkło), potem D2. Skrzynie stoją przodem do kamery, więc maska dziur
   jest na nich widoczna wprost (S1).
3. **Łup ze skrzyń:** **tak, drobny** — złom 1–2, rzadko bateria; liczby do strojenia zgodnie z `PROGRESSION_PLAN.md`.
4. **Lampy na misjach:** **tak**, nowy znacznik do zestrzelenia (D1).
5. **Zawał 1.1:** **zostaje jak jest**; D3 robi nowe podpory obok, przeniesienie zawału 1.1 dopiero, gdy mechanizm się sprawdzi.
6. **Barykadowanie (D2b):** **wchodzi**, po D2; koszt: deski z rozbitych skrzyń, a gdy ich brak — złom.
7. **Spike'i S1 i S2:** zrobione (wyniki wyżej); poprawka mgły, od której zależy poświata przez dziury, scalona w #578 (1.7.478).

Wcześniej rozstrzygnięte 2026-11-02:

- Strefy wydobycia (D5): znajdźki **z limitem** (pula na strefę, odnowienie po 3 udanych misjach — liczby do strojenia); strefy
  **zapowiadają kopalnię FPP**.
- Rozdzielczość wokseli: **4 × 4 na kafel** (0,33 m).
