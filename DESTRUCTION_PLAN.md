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
| Stopnie uszkodzeń | **Jedna siatka na materiał + shader z maską uszkodzeń.** Maska to mała tekstura na obiekt (`ImageTexture` 64 × 64, kanał R), do której serwerowe zdarzenie trafienia „wypala” miękką plamę (`Image.blend_rect` / zapis pikseli + `ImageTexture.update`): z progu wycina dziurę `alpha scissor`, poniżej progu dokłada pęknięcia w normalnych i ciemniejsze drewno. Liczba trafień bez limitu, dziury tam, gdzie naprawdę padła kula. `alpha scissor` działa też w przebiegu cieni, a reflektor latarki rzuca cienie (`view3d.gd`, limit `SHADOW_LIGHTS`), więc **snop przebija przez dziury** i w mgle wolumetrycznej widać smugi (do sprawdzenia w spike'u S1 — mgła ma dziś 128 × 128 × 54, cienkie smugi mogą się nie rozdzielić). | 3 modele na stan: 3× więcej zasobów, skok wyglądu. **`instance uniform` odpada** — dokumentacja 4.7: per-instancja tylko typy skalarne i wektorowe, bez tablic i tekstur (max 16). Zwykła tablica `uniform vec4 hits[16]` działa, ale wymaga osobnego materiału na obiekt i ogranicza liczbę trafień — tekstura maski jest równie tania i bez limitu. Materiał na obiekt rozbija grupowanie wywołań rysowania, ale przy kilkudziesięciu obiektach na mapie to pomijalne. Shader trzeba **rozgrzać pod planszą wczytywania** (jak `spawn_burst` przy budowie mapy), inaczej pierwsze trafienie zatnie klatkę. |
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

- **S1 — dziury i snop latarki** (1–2 dni): jedna deska z shaderem maski, kilka trafień, latarka za deską, zrzuty w nocy i w mgle
  (`--weaponshots`-podobny kadr). Odpowiada: czy smugi przez dziury są widoczne przy obecnej mgle, ile kosztuje cień przez `alpha scissor`.
- **S2 — ruch po wykopie** (1–2 dni): jedna strefa 12 × 6 kafli na mapie testowej, kolizja z odcinków, gracz biega, skacze i kopie kilofem.
  Odpowiada: czy `CharacterBody2D` dobrze chodzi po krzywych skosach z marching squares (wygładzanie, `floor_snap_length`, maks. kąt podłogi),
  czy kopanie „czuje się” dobrze (ile ciosów, wielkość wyrwy), czy łatwo się zakopać.

Wynik obu idzie do planu przed D0 (liczby, ewentualna zmiana podejścia).

## Etapy

### D0 — fundament (bez nowej zawartości)

- **`breakable.gd`** zamiast `brick_wall.gd`: jedna klasa z **materiałem** (`brick`, `planks`, `sheet`, `grate`, `glass`, `support`) i tabelą
  w stylu `surfaces.gd`: HP, co niszczy (kilof / maczeta / kule / śrut / wybuch / szarża), hałas uderzenia i rozbicia, dźwięki, kolor gruzu,
  czy blokuje kule, czy blokuje widok i światło. Ściana `q` = materiał `brick` (zachowanie bez zmian, testy Rzeźnika i kilofa zielone).
- **Uszkodzenia**: serwer wysyła zdarzenie trafienia (punkt, promień plamy, stopień 0–2), a nie HP — każdy peer wypala tę samą plamę
  w masce, więc dziury wyglądają u wszystkich tak samo; dołączający dostaje listę plam obiektu. Trafienia w ułamku sekundy łączone
  w jedno RPC (seria z M-83 to nie 10 wiadomości).
- **Lokalna przebudowa nawigacji**: `Nav.rebuild_region(rect)` — usuwa węzły i krawędzie w prostokącie powiększonym o zasięg skoku
  (`GAP_SIDE` = 4 w bok, `JUMP_UP` = 2 w górę, spadki w kolumnach do podłogi) i dokłada je od nowa. Cel: < 2 ms. Test: graf po lokalnej
  przebudowie identyczny z pełną budową (porównanie punktów i krawędzi) dla każdej ściany i każdej mapy. **Naprawia też dzisiejsze przycięcie
  przy `q`.**
- **Stan zniszczeń w jednym miejscu** (`level.gd`): lista zniszczonych z nazwami, synchronizacja dołączających (uogólnione `send_walls_to`),
  reset przy wipe, nowej misji i **punkcie kontrolnym bossa** (stan z chwili przebudzenia — jak łup od 1.7.424).
- **Widok 3D**: każdy materiał ma jeden model z shaderem maski uszkodzeń i zestaw brył z pre-fraktury (skrypt Blendera w `tools/`,
  w stylu generatorów — bmesh, cięcie płaszczyznami Voronoi, osobny materiał przekroju; Blender 5.2 headless). Źródła: tekstury desek,
  cegły, rdzy i skały z ambientCG / Poly Haven (CC0, już używane w `art/world3d/`), proste bryły (deska, kratka, lampa) z generatora
  w Blenderze; złożone modele z Poly Haven, w razie potrzeby lokalny TRELLIS 2 (obraz → model z PBR, potrzebuje obrazu wejściowego —
  nie mamy lokalnie tekst → obraz) albo Meshy (ok. 30–40 kredytów za rekwizyt). Każdy nowy GLB przez `tex_vram.py`. Odłamki przez `Vfx.debris`, potem leżą jako gruz
  w `MultiMesh` do końca misji (limit globalny, najstarsze znikają). Szczegóły w „Technologie”.
- `--maptest`: osiągalność celów **przy wszystkim całym i wszystkim zniszczonym** (rozszerzenie `open_all_walls_for_test`).
- Nowy `--destructiontest` w CI: obrażenia wg materiału, hałas, stopnie, sieć (dołączający widzi zniszczenia), reset, punkt kontrolny,
  czas lokalnej nawigacji.

### D1 — rekwizyty, które pękają (najmniejsze ryzyko, od razu widać)

- **Skrzynia `k`** pęka po N trafieniach / wybuchu / szarży (dziś tylko lata): drzazgi, hałas; opcjonalnie wypada drobny łup (złom 1–2,
  rzadko bateria) — zgodnie z progresją z `PROGRESSION_PLAN.md`, do strojenia.
- **Beczka `o`**: zostaje wrak z osmaleniem zamiast znikania.
- **Lampy na misjach do zestrzelenia** (nowy znacznik): gaśnie światło, sypie szkło, krótki dźwięk. W grze o ciemności to realna
  decyzja: ciemniej = trudniej widzieć, ale też trudniej być widzianym (Stalker, Ćmy lecą do światła). Dziś lampy `l` są tylko w kryjówce.
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
- Uogólnienie zawału 1.1 na ten mechanizm (opcjonalnie, jeśli zysk wart ryzyka — zawał 1.1 działa i jest pod `--finaletest`).
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
- **Anty-pułapka** (lekcja z SteamWorld Dig): strefa nie schodzi niżej niż 2 kafle pod najniższe miejsce, z którego da się do niej wejść
  (skok sięga 2,6 kafla); cios kilofem w dół-skos zostawia stopień, a nie pionową ścianę; `--digtest` sprawdza na losowych wykopach, że
  z każdej komórki, w której gracz może stać, istnieje droga na zewnątrz. Znajdźki leżą **w bok i w głąb ściany**, nie pod wejściem — kopanie
  prosto w dół nie ma być najlepszą strategią.
- **Rytm co-op** (lekcja z Deep Rock Galactic): wydobycie cennej znajdźki trwa ok. 20–40 s kopania w hałasie — dość, żeby opłacało się,
  by jeden kopał, a drugi pilnował; bot pilnuje kopiącego człowieka (nie kopie sam).
- **Odpowiedź natychmiast, stan z serwera** (lekcja z The Finals): cios od razu daje u kopiącego iskry, pył, dźwięk i wibrację; komórki znikają,
  gdy przyjdzie delta z serwera (u hosta w tej samej klatce, u klienta po czasie odpowiedzi — ok. 1–3 klatki w LAN).

**Technologie**

| Element | Wybór | Uwagi |
|---|---|---|
| Dane | Siatka **4 × 4 komórki na kafel** (komórka 4 px = 0,33 m; decyzja 2026-11-02), gęstość 0–255 w `PackedByteArray` (gładkie krawędzie, wytrzymałość materiału), osobna tablica materiałów. | Strefa 20 × 10 kafli = 3200 komórek — znikome dane |
| Siatka 3D | **Marching squares** po gęstości → kontur → bryła wyciągnięta w głąb do `DEPTH_BACK`, przód z przemieszczeniem szumem, krawędzie fazowane; fragmenty 16 × 16 komórek, przebudowa tylko dotkniętego fragmentu **na głównym wątku** (zmierzone 0,18 ms w najgorszym przypadku; limit 4 na klatkę, reszta w następnej). Materiał PBR **triplanarny** (te same skany co ściany mapy, bez szwów na krzywych), okluzja z głębokości wykopu w kolorach wierzchołków (tanie „wnętrze jaskini”), tylna ściana wykopu. | `godot_voxel` (Zylann) — moduł C++ zależny od wersji silnika i robiony pod 3D, a nam wystarcza siatka 2D z głębią; własny greedy meshing z `MINING_PLAN.md` — sześciany, kanciaste, nie pasują do gładkiego terenu mapy |
| Kolizja | Te same odcinki z marching squares → **`ConcavePolygonShape2D` na `StaticBody2D`**, jeden na fragment (co widać, w to się uderza; gładkie skosy, puste kieszenie i wyspy działają same, bo to tylko odcinki; podmiana 0,08 ms). Odłamki i łuski w strefie z `continuous_cd`. | Drobne kafle 4 px w `TileMapLayer` — postać „tnie” na schodkach; `CollisionPolygon2D` (tryb SOLIDS) i `BitMap.opaque_to_polygons` — nie obsługują dziur w wielokącie (sprawdzone pomiarem) |
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

## Decyzje do podjęcia

1. **Zakres:** tylko oznaczone elementy (rekomendacja) czy także szerzej (np. każda kładka z desek `-` łamliwa)?
2. **Kolejność:** zacząć od D0 + D1 (szybki efekt) czy od D0 + D2 (rdzeń mechaniki)?
3. **Łup ze skrzyń:** tak / nie (wpływ na ekonomię złomu).
4. **Lampy na misjach:** dodać jako nowy element map (D1) czy zostawić ciemność bez źródeł do gaszenia?
5. **Zawał 1.1:** przenieść na nowy mechanizm (D3) czy zostawić jak jest?
6. **Barykadowanie (D2b):** wchodzi do planu? Koszt w złomie czy tylko deski z rozbitych skrzyń?
7. **Spike'i S1 i S2 przed D0:** zgoda na 2–4 dni sprawdzenia ryzyk, zanim powstanie kod produkcyjny?

Rozstrzygnięte 2026-11-02:

- Strefy wydobycia (D5): znajdźki **z limitem** (pula na strefę, odnowienie po 3 udanych misjach — liczby do strojenia); strefy
  **zapowiadają kopalnię FPP**.
- Rozdzielczość wokseli: **4 × 4 na kafel** (0,33 m).
