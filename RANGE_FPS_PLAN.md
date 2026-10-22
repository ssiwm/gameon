# Plan: strzelnica FPS 3D w kryjówce

Status: **etap 0 (szpic `--range3d`) zrobiony — 1.7.335**; wyniki i decyzje w §7. Ręce FPP (0b) — §8. **Etap 1 zrobiony (1.7.338–1.7.339):** drzwi, parkowanie,
wynik na serwerze, tablica drużyny, opcje widoku z oczu, akcje „range”, dźwięk blach 3D i przejście kamery — §9. Zastępuje strzelnicę boczną z PR #413
(wstrzymany, nie scalać). Przyjęte decyzje z §6: #413 wstrzymany, stanowiska na linii ognia, amunicja ćwiczebna, każdy gracz osobno.

## 0. Dlaczego obecna forma nie ma sensu

Strzelnica z #413 to pięć blach w płaszczyźnie gry 2D (`range_course.gd`, `range_target.gd`, `RANGE` w `z1_hub.gd`). Strzela się w bok,
po płaskiej linii, na 5–18 m. Nie widać więc tego, co etapy 3–5 `GUNSMITH_PLAN.md` zmieniły w strzelaniu:
- **podrzutu**: lufa idzie w górę o kilka stopni, a w widoku bocznym to tylko przesunięcie celownika;
- **rozrzutu i grupy**: nie ma tarczy, na której zostają przestrzeliny;
- **gorącej lufy**: rozrzut ×(1 + 0,4·t²) jest niewidoczny bez grupy;
- **oparcia, wprawy i części**: nie ma czego zmierzyć.

Strzelnica miała służyć do ogrania tych liczb przed playtestem. Do tego potrzebny jest widok z oczu: celownik mechaniczny, podrzut jako
uniesienie kamery, przestrzeliny na papierze i blachy na różnych odległościach.

## 1. Co jest w kodzie i da się użyć

| Element | Stan | Użycie w FPS |
|---|---|---|
| `weapon_controller.gd` (1503 wiersze) | Cała obsługa broni: magazynki, przeładowania (krótkie i taktyczne), zacięcia, stan, gorąca lufa, podrzut (`climb` w °), rozrzut (`spread_extra`, `bloom`), wprawa, tryby ognia, dźwięki strzału. Wejście z `Input` w `tick_local`. Wyjście strzału w `_fire_shot` → pocisk 2D (`player.aim_dir`, `muzzle_pos`). | **Bez zmian w zachowaniu.** Jeden nowy hak: `fire_sink: Callable` — gdy ustawiony, `_fire_shot` oddaje strzał (broń, ziarno, rozrzut, `climb`) zamiast tworzyć pocisk 2D. Wtedy strzelnica liczy dokładnie te same liczby co misja, a HUD naboi i zacięć działa sam. |
| `WeaponDef` | Rozrzut i podrzut w stopniach, `cooldown`, `pellets`, `speed`, `pen`, `arm_dist`, `speed_start`/`accel_time` | Stopnie przechodzą 1:1 na stożek 3D. |
| `gun_model.gd` + `art/char3d/gun_*.glb` (12 broni) | Model z częściami w gniazdach i nacięciami, punkty `grip`/`fore`/`muzzle` w `.json` | Model broni w rękach (viewmodel). W `gun_proc.py` są już podzespoły `sight_front`/`sight_base`/`sight_leaf`/`sight_tube` — trzeba tylko eksportować punkty `sight` do `.json` (celowanie przez przyrządy). |
| `char3d.gd` | Poza IK: obie dłonie na broni, celowanie kątem w płaszczyźnie postaci | Ręce w FPP: model postaci obrócony o odchylenie kamery, kąt celowania = pochylenie, głowa ukryta. **Do sprawdzenia w szpicu** (poza powstała pod widok z boku). |
| `view3d.gd` — oględziny broni (`_fp`, `FP_EYE_M`, `FP_FOV`) | Kamera już umie dojechać do oczu gracza i wrócić; gaszą się etykiety nad postaciami | Wzór przejścia do strzelnicy i z powrotem. |
| `range_course.gd` | Stoper, reset, porzucony przebieg, rekord drużyny (`Settings.range_best`, host), toast | Logika ćwiczenia „5 blach na czas” przechodzi prawie bez zmian. |
| `view3d._sync_range` | Słupek, blacha na zawiasie, lampy, tabliczka | Model blachy i animacja upadku do sceny 3D strzelnicy. |
| `MINING_PLAN.md` §2A0, Etap 0 | Plan kamery FPP, parkowania gracza w hubie, opcji FOV / czułości / osi Y, akcji w kontekście | Te same klocki. Strzelnicę warto zbudować tak, żeby kopalnia ich użyła (`fp_mode.gd`). |

**Czego nie ma:** fizyki 3D w symulacji (zasada CLAUDE.md), dźwięku pozycyjnego 3D (`audio_director.gd` ma tylko `AudioStreamPlayer2D`),
punktów przyrządów celowniczych w `.json` broni, akcji „celuj przez przyrządy” (PPM) ani ruchu przód/tył (W/S służą do celowania i schodzenia).

## 2. Założenia

1. **Osobne pomieszczenie 3D za tylną ścianą magazynu.** W kryjówce zostają stalowe drzwi z napisem STRZELNICA i tablica wyników.
   [E] przy drzwiach przenosi kamerę do oczu (wzór oględzin) i obraca ją w głąb: tunel 30 m w osi −z, poza płaszczyzną gry. Z widoku
   bocznego tunelu nie widać, bo zasłania go tylna ściana.
2. **Symulacja strzelnicy jest analityczna, bez fizyki 3D.** Tunel to prostopadłościan, a cele to proste kształty: blacha (koło na
   płaszczyźnie), papier (prostokąt) i podłoga. Promień kuli przecina się z nimi wzorem. Dzięki temu test headless liczy to samo co gra,
   bez `view3d` i bez fizyki. To jest **jawny, wąski wyjątek** od „symulacja zostaje 2D” — wpis do CLAUDE.md jak w planie kopalni.
3. **Gracz stoi na linii ognia.** A/D przechodzą między trzema stanowiskami, [Shift] to przyklęk (oparcie o ławę stanowiska),
   mysz to rozglądanie, LPM strzał, PPM celowanie przez przyrządy, [E] lub [Esc] wyjście. Bez chodzenia po tunelu i bez kolizji 3D.
4. **Broń zachowuje się dokładnie jak na misji**, bo strzela ten sam `weapon_controller` (hak `fire_sink`). Podrzut `wc.climb` unosi
   kamerę, a gracz ściąga go myszą. Rozrzut to stożek wokół osi lufy. Przy ustawieniu CLASSIC zostaje sam rozrzut (porównanie A/B).
5. **Każdy gracz strzela u siebie (lokalnie).** W hubie jego postać stoi zaparkowana przy drzwiach z podpisem „na strzelnicy”. Wynik
   ćwiczenia idzie do serwera RPC. Serwer sprawdza wiarygodność (czas nie krótszy niż liczba strzałów × `cooldown`), trzyma tablicę
   rekordów drużyny i rozsyła ją wszystkim.
6. **Amunicja ćwiczebna (propozycja):** przeładowanie nie pobiera naboi z zapasu, broń się nie zużywa i nie daje wprawy ani zabójstw.
   Zacięcia losują się według bieżącego stanu broni. Typ naboju [Z] można wybrać za darmo, żeby porównać US, BZ i brenekę.

## 3. Zawartość strzelnicy

| Ćwiczenie | Co mierzy | Wynik na tablicy |
|---|---|---|
| **Blachy na czas** — 5 blach na 7 / 12 / 18 / 25 m | szybkość przenoszenia ognia, podrzut, przeładowanie | czas (rekord drużyny i osobisty) |
| **Grupa** — 5 strzałów do tarczy papierowej 25 m z wybranej postawy | rozrzut, gorącą lufę, oparcie, części | średnica grupy w cm i MOA; przestrzeliny zostają na papierze do zmiany tarczy |
| **Przeładowanie** — 2 strzały, przeładowanie, 2 strzały (2 blachy) | oba przeładowania, wprawę | czas |
| **Seria** (później) — 10 strzałów ogniem ciągłym do papieru | podrzut serii i ściąganie myszą | rozciągnięcie pionowe grupy |
| **Ruchomy cel** (później) — wózek na linie | wyprzedzenie, prędkość kuli | trafienia / próby |

Papier przestrzeliwuje się na wylot, a blacha zatrzymuje kulę. Strzelby dają na papierze wzór śrutu, który przyda się do strojenia
`pellets` i `spread`.

## 4. Etapy

| Etap | Zakres | Pliki | Bramka |
|---|---|---|---|
| **0 — szpic za flagą `--range3d`** | Scena tunelu (tylko obraz i oświetlenie), kamera FPP, M-83 przez `fire_sink`, 3 blachy liczone analitycznie, podrzut jako uniesienie kamery. Próba rąk z `char3d` obróconego w osi y; jeśli wygląda źle — sam model broni z prostymi rękawicami. | nowe `scripts/range3d/range_sim.gd`, `range_view.gd`, `fp_mode.gd`; `weapon_controller.gd` (hak), `view3d.gd` (przełączenie kamery) | zrzuty i ocena użytkownika: czy ręce i broń wyglądają dobrze, 60 FPS, podrzut czuć |
| **1 — MVP** | Drzwi i tablica w hubie zamiast blach 2D, parkowanie gracza (`player.in_range`: bez ruchu i celowania 2D, `wc.tick_local` dalej działa), wejście i wyjście z przejściem kamery, wszystkie bronie kulowe i strzelby, ćwiczenie „blachy na czas” (logika z `range_course.gd`), amunicja ćwiczebna, wynik do serwera i tablica drużyny, opcje FOV i czułości, akcje w kontekście `range` w `actions.gd`, dźwięk blach przez rzut na pozycję 2D przy graczu. Test `--rangetest` (wejście, strzały `sim_fire`, trafienia, stoper, rekord, zapas niezmieniony po wyjściu, odrzucenie niewiarygodnego wyniku na serwerze). | j.w. + `player.gd`, `z1_hub.gd`, `level.gd`, `settings.gd`, `actions.gd`, `ui.csv`, `CLAUDE.md` (wyjątek), README / GDD / CHANGELOG | testy zielone; ogranie z użytkownikiem |
| **2 — pomiar** | Celowanie przez przyrządy (punkty `sight` z `gun_proc.py` → `.json`, przebudowa GLB), tarcza papierowa z przestrzelinami i miarą grupy, oparcie przy ławie, ćwiczenie „przeładowanie”, rekordy osobiste per broń. | `tools/gun_proc.py`, `art/char3d/gun_*.json`, `range_sim.gd`, `range_view.gd` | da się porównać grupę REALISTIC i CLASSIC, zimną i gorącą lufę, z oparciem i bez |
| **3 — reszta broni i co-op** | WRATH-4 (tor łukowy, odległość uzbrojenia), Gyrojet (przyspieszanie), LR-7 / SPECTER-1 / HKM-9 (promień, szyna, płomień — uproszczone cele) — **zrobione w 1.7.341 (§10)**; seria, ruchomy cel, widok innych graczy na sąsiednich stanowiskach (synchronizacja pozy). | j.w. | bronie specjalne zrobione, reszta po playteście |

Szacunek: etap 0 to jedna sesja, etap 1 to 2–3 PR-y, etap 2 to 1–2 PR-y.

## 5. Ryzyka

- **Ręce w FPP.** Poza `char3d` powstała pod widok z boku i z bliska może wyglądać źle. Dlatego szpic idzie pierwszy, a zapasem jest sam
  model broni.
- **Przyrządy celownicze.** Modele z `gun_proc.py` nie były robione pod oko z 5 cm. Szczerbina i muszka mogą nie leżeć w jednej linii z
  osią lufy. Trzeba je wyrównać skryptem albo przesunąć oś strzału do linii przyrządów.
- **Dźwięk** jest pozycyjny tylko w 2D. Na strzelnicy własny strzał jest niepozycyjny, a blachy dostają rzut odległości na pozycję 2D.
  Pełny dźwięk 3D to osobna praca, wspólna z kopalnią.
- **`view3d.gd` ma 5318 wierszy.** Strzelnica ma żyć we własnych plikach, a w `view3d` zostaje tylko przełączenie kamery i ukrycie
  świata huba.
- **Kontrast wobec zasady 2D.** Wyjątek ma być wąski (analityka, bez fizyki 3D), żeby nie otwierał drogi do „3D wszędzie”.

## 6. Decyzje do podjęcia

1. **Co z #413:** nie scalać i przerobić gałąź na etap 1 (proponuję) czy scalić teraz i zastąpić później?
2. **Ruch:** stanowiska na linii ognia (proponuję) czy swobodne chodzenie po tunelu (kolizje 3D, więcej pracy)?
3. **Koszt strzelania:** amunicja ćwiczebna bez zużycia i wprawy (proponuję) czy pełny realizm (zapas, zużycie)?
4. **Co-op w etapie 1:** każdy osobno (proponuję) czy wspólny tunel od razu?

## 7. Wyniki etapu 0 (2026-10-20, 1.7.335)

Uruchomienie: `godot --path prototype -- --host --range3d` (gra startuje w kryjówce, gracz od razu na strzelnicy; [E] wraca do kryjówki).
Test: `godot --headless --path prototype -- --host --rangetest --autoquit=60` (20/20). Zrzuty: `concepts/range3d_hip.jpg`, `concepts/range3d_ads.jpg`, `concepts/range3d_pistol.jpg`.

| Element | Wynik |
|---|---|
| Hak `range_sink` w `weapon_controller.gd` | Działa. Strzał idzie przez te same liczniki co na misji (magazynek, zacięcia, gorąca lufa, podrzut, tryb ognia); zmiana w kontrolerze to ~30 wierszy. Testy broni (`test_weapons.sh`) przechodzą. |
| Podrzut | Uniesienie kamery czuć: seria 5 strzałów z M-83 bez ściągania myszą idzie ok. 1,3 m w górę na 30 m (`wc.climb` do ~2,4°). Strzał bierze podrzut sprzed siebie (jak `player._local_brain` w 2D) — pierwsza wersja liczyła go podwójnie i chybiała. |
| Rozrzut | Stożek 3D o kącie `jitter_deg` z gry. **Wniosek do strojenia:** M-83 ma 0,8° (≈ 28 MOA) — na 7–13 m każda kula trafia blachę ⌀ 30 cm, na 16 m już 2 strzały, na 20 m 4 (test). To dużo jak na karabin z pierwszego strzału; w grze 2D nie było tego widać. P-83 ma 0,35°, czyli celniej niż M-83. Do decyzji przy etapie 2 (grupa na papierze pokaże to w cm). |
| Przyrządy | Linia celownicza liczona z najwyższego punktu modelu broni (wierzch muszki i szczerbinki) — obraz poprawny dla M-83 (pokrywa zamka, szczerbinka i muszka w osi). Kolba widoczna w dole kadru. Dokładne punkty `sight` z `gun_proc.py` zostają w etapie 2. |
| Ręce | **Model postaci gracza** (`fp_arms.gd`): osobna instancja `char3d.gd` (ten sam wygląd i strój co w grze) bez podglądu 2D, siatki postaci i ubrania przycięte do trójkątów z wagą ≥ 0,5 na kościach rąk (tułów i głowa weszłyby w kamerę), IK z `char3d` (`_arm_ik`, `_hand_target`, `_left_hold`, `_set_hand`, palce). Model wisi na broni, nie na oczach: zagłębienie prawego barku na stopce kolby, tułów obrócony o 32° (inaczej lewa ręka nie sięgała łoża); pistolet — postawa równoramienna, barki 15 cm pod linią wzroku, ręce na ok. 55 cm. Przeładowanie prowadzi lewą dłoń torem z `char3d._left_path`. Do poprawy: dłonie gołe (taki strój postaci), przy biodrze lewa dłoń częściowo za bronią, cięcie rękawa przy barku widać przy skrajnym obrocie w lewo. Walce i kapsuły zostały jako zapas, gdy model postaci się nie wczyta. |
| Świat | Zamiast tunelu za tylną ścianą magazynu (§2.1) strzelnica ma **własny świat 3D** w SubViewport — prościej i bez wpływu na oświetlenie kryjówki; widok kryjówki jest wtedy schowany i nie renderuje się. Wejście przez drzwi z przejściem kamery zostaje w etapie 1. |
| Rozdzielczość | Pierwsza wersja renderowała tunel w 640×360 (rozmiar płótna interfejsu, `SubViewportContainer.stretch`) i rozciągała do okna. Teraz SubViewport ma rozmiar okna × skala „Effects quality” (jak `view3d`). |
| Wydajność | 60 FPS przy vsync, 4K, RTX 3080 (`--print-fps`, seria ognia, z rękami); 6 lamp, 3 z cieniami. |
| Dźwięk | Strzał i przeładowanie z gry; blacha dzwoni niepozycyjnie z głośnością od odległości. |
| Czego nie ma | wejścia z kryjówki, zapisu rekordu, sieci (wynik tylko lokalnie), broni ciągłych i WRATH-4 (strzelają, ale bez obrazu w tunelu), łusek i dymu w 3D, opcji FOV i czułości, pada poza rozglądaniem. |

**Bramka etapu 0** (ocena użytkownika): czy widok z oczu i broń wyglądają dobrze, czy podrzut i przyrządy dają sensowne strzelanie. Jeśli tak — etap 1 zaczyna się od rąk FPP.

## 8. Etap 0b — ręce FPP klasy AAA (2026-10-21, 1.7.336, gałąź `feat/range-fps-arms`)

Decyzje użytkownika: rękawice skórzane + rękaw M65, MPFB + nasz pipeline (bez Meshy), najpierw M-83 w pełnej jakości.

| Element | Jak | Stan |
|---|---|---|
| Ręce | `tools/fp_arms.py` → `art/char3d/fp/fp_arms_scav.glb` (66 tys. trójkątów: rękawice 49 tys., rękawy z karczkiem 15 tys., zegarek) | zrobione; skóra rękawic z wyraźnym ziarnem i zmarszczkami (wypukłości ×2–3 po pierwszej próbie) |
| Rękawice taktyczne bez palców (poprawki 2026-10-21) | oliwkowe, wg zdjęć referencyjnych: palce ucięte w poprzek członu bliższego z obszyciem otworu (`_finger_cuts`, `_cut_finger`), dalej skóra ciała MPFB z paznokciami (`make_finger_skin`, kolor wypieczony na własne UV, `SKIN_TONE`); formowana skorupa z czterema garbami na kostkach i owalne nakładki na pierwszych członach palców dopasowane do grzbietu rękawicy (`_molded`, wagi z rękawicy przez Data Transfer); pasek na rzep z patką (wolna krawędź, stopień grubości) i szwem w krzyż (`make_strap`); materiał z atrybutów `zone` / `kf` / `sc` (zamszowa obwódka skorupy z dwoma szwami, elastyczny grzbiet w prążki, obszycia) wypiekany do 4K; zegarek wyżej, nad paskiem. Meshy niewykorzystane: rękawica musi zginać się z każdym stawem palca (siatka z ciała ze szkieletem), model z Meshy byłby sztywny; kciuk: obrót kości śródręcza ograniczony do ~40° (`thumb_range`) — przy 64–96° siatka nadymała się w bulwę na grzbiecie dłoni | zrobione |
| Światło | AgX (ekspozycja 1,3), lampy ok. 3800 K (×0,8), lampa nad dłońmi przeniesiona za plecy, wypełnienie 0,8 tylko dla warstwy rąk; pomiar: albedo rękawic 0,026, rękawów 0,04 (liniowo) — przepalenie dawało światło, nie tekstury | zrobione |
| Rękaw (poprawki 2026-10-21) | rękawica z płaszczyzny cięcia (pełna dłoń, równy mankiet), kurtka z lewej połowy (`mirror_half`), karczek z płaszczyzny, `smooth_cuffs`, grubość tkaniny 1,8 mm, `unwrap_fp` (cięcie po wewnętrznej stronie ręki, MINIMUM_STRETCH, gęstość 0,83–0,85 na całej długości), kamuflaż z szumu 3D (`_bake_positions`, `_noise3`) | zrobione |
| Rękaw | `cloth_garments.py --fp` → `art_src/clothes/male_scav_m65_fp.glb` (same rękawy + karczek, własne UV 2K; prawy = odbicie lewego, bo w symulacji prawy mankiet podjeżdża) | zrobione |
| Chwyt | `tools/fp_grip.py`: układy dłoni, IK z biegunem łokcia, podział skrętu, osadzenie dłoni (wnętrze dłoni dosuwane do broni), palce do kontaktu (BVH, do 125°), klip `grip_m83` + `gunref_m83` | obie dłonie na broni: palce prawej na chwycie, lewa obejmuje łoże (luz 0–0,5 mm) |
| Chwyt jak w viewmodelach FPS (poprawki 2026-10-21) | łokcie w dół, broń cofnięta i uniesiona względem barków (`sink`) — przedramiona wchodzą w kadr od dołu, bark poza kadrem; `orient_hand`: przegląd przetoczenia i odchylenia dłoni oraz bieguna łokcia, wybór z najmniejszym zgięciem nadgarstka po IK (było ~100° zgięcia i odchylenia lewego — „złamany”; jest ok. −35° wyprostu i 20° odchylenia łokciowego, prawy ~0°) i z przedramieniem ukośnie w kadrze; prawa dłoń linią kostek na przedniej krawędzi chwytu (`mcp`), wskazujący dobierany do języka spustu (`aim_index`), pozostałe palce przeglądem póz (`wrap_finger`: największe zgięcie bez wchodzenia w broń, przylega całą długością, palce razem); skóra rękawicy bez grud (zmarszczki ~6 mm, 0,5 mm głębokości); kciuk prawej dłoni z własnym solverem (`aim_thumb`: nasada w dwóch stopniach swobody, przeglądem — leży wzdłuż lewego boku broni na styku chwytu i komory, przylega bez wchodzenia w broń; owijany jak palce chował się w chwycie); lewa dłoń też z punktu kostek (`mcp` przy prawej dolnej krawędzi łoża) i z przetoczeniem ograniczonym do ±20° od „wnętrzem do góry” — przy ±60° przegląd kładł ją nachwytem na łoże od lewej; dłoń na przodzie łoża, broń niżej i dalej od barków (`sink` 0,03 / 0,05) — przedramię łagodniej, nadgarstek ~30° zamiast ~50° (wyprost w jednym stawie wyglądał jak złamanie), bark poza kadrem; lewy kciuk z `aim_thumb` (w przód wzdłuż lewej dolnej krawędzi łoża: kierunek `thumb_dir`, przyleganie `thumb_hug`, koniuszek nie wyżej niż `thumb_top`; owijany jak palce zwijał się w hak pod łożem, bez kierunku sterczał w górę przy muszce); dłoń 8 cm za przednią krawędzią łoża (`mcp` x 0,28 — przy muszce palce i kciuk wchodziły w obraz przyrządów, a kciuk nie mieścił się na łożu i chował pod spód), kciuk płasko na lewej ściance (`thumb_bottom`, `thumb_band`, szerszy przegląd nasady `thumb_range`), koniuszki palców nie wyżej niż górna osłona (`tip_top`); `--quick=1` — sama poza i zbliżenia (bez kurtki) | zrobione |
| Lewa dłoń: dwie pozy (poprawki 2026-10-21) | od biodra jak w viewmodelach CS: wnętrze dłoni na lewej ściance łoża, palce w górę i przez wierzch osłony rury gazowej, kciuk pod łożem w przód — z kamery widać grzbiet dłoni, przedramię od dołu bez skrętu nadgarstka (podparcie od spodu pokazywało z góry otwartą dłoń z kciukiem w górę); przy celowaniu klip `grip_ads_m83` (podparcie od spodu, kciuk płasko na lewej ściance) — palce na wierzchu osłony zasłaniałyby muszkę; `fp_rig.animate(..., ads)` miesza obroty kości lewej ręki wg `ads_t` w pierwszych 30% wejścia w przyrządy (`ADS_SWITCH`; pozy pośrednie odrywały dłoń od łoża), prawa ręka i broń (kotwica kadru) bez zmian; palce mogą lekko przeprostować staw u nasady (mały palec kładzie się na ściance zamiast wchodzić w łoże); ciemna tarcza zegarka (świecąca cała wyglądała jak zielony krążek); dev `--rangeads=T` — stały postęp przyrządów do zrzutów przejścia | zrobione |
| Przeładowanie | `reload_m83` (1,35 s, 11 klatek) i `reload_empty_m83` (1,8 s, 15 klatek): lewa dłoń sięga, chwyta, wyważa, wyciąga, ładownica, powrót, zahaczenie, zatrzaśnięcie; broń ma w każdej klatce pozę (`GUN_POSES`: przechył ~10°, podbicie, szarpnięcie suwadła), prawa ręka za nią przez IK; palce: kontakt z magazynkiem albo ułożenia (`FINGER_SETS`: dłoń otwarta, hak na suwadle, puszczenie); w grze ręce kotwiczone pozą chwytu (`fp_rig.anchor`) | zrobione |
| Mechanika broni | `gun_proc.py`: podzespoły `bolt` (suwadło widoczne w oknie + rączka) i `trigger` (język spustu) M-83; `fp_rig.gd`: cykl suwadła po strzale (8 cm, 25 ms w tył, 35 ms w przód), suwadło za rączką w klipie (`bolt` w .json: chwyt / odciągnięcie / puszczenie), spust 12° wokół nasady. Kurek AKM jest wewnątrz komory — z zewnątrz go nie widać, więc go nie animujemy | zrobione |
| Dźwięki przeładowania | `bake_weapons.py`: osobne `mech_*` (zatrzask, magazynek wysuwany i wsuwany, suwadło w tył i w przód, chwyt łoża) + `foley_gear`; `fp_grip.py SOUNDS` przypina je do klatek, range_view.gd gra je, gdy postęp przeładowania mija klatkę; `weapon_controller._reload_sfx` milczy, gdy klip ma własne dźwięki | zrobione |
| Łuski i dym | `range_fx.gd`: łuski z okna wyrzutowego (rotacja, odbicia od ławy, podłogi, ścian i przegród, stuk `shell`, do 60 na ziemi), dym z wylotu, smużki z gorącej lufy (`barrel_of` > 0,45); punkty startu z kamery rąk przeliczane na kamerę tunelu (stosunek tangensów kątów widzenia) | zrobione |
| W grze | `fp_rig.gd` (broń dzieckiem dłoni), `range_view.gd`: osobna kamera rąk 58°, kołysanie, oddech, odrzut na sprężynie, broń 4K | zrobione, 60 FPS |
| P-83 (1.7.340, gałąź `feat/fp-arms-p83`) | `gun_proc.py`: zamek z przyrządami (`bolt`), język spustu (`trigger`) i magazynek ze stopką i korpusem w chwycie (`mag`) jako osobne podzespoły; w `gun_p64.json` `trigger`, `trigger_pad`, `slide` (55 mm). `fp_grip.py` ma tryb pistoletu: postawa równoramienna (`pistol`), lewa dłoń na broni i siatce prawej (`wrap_right`, `right_hand_bvh`), przeładowanie z zatrzaskiem w stopce i zamek nachwytem (`_pistol_targets`), pozy broni z przesunięciem w bok (`GUN_POSES`, piąta liczba); w grze `fp_rig.eye_in_gun` (odległość szczerbinki od oka z ułożonej postawy). **Ręce P-83 odrzucone przez użytkownika jako zbyt słabej jakości** — zasób rąk ma tylko chwyt M-83 (eksport `scav m83`), a na strzelnicy ręce są wyłączone dla wszystkich broni, także M-83 (`range_view.ARMS_RIG = false`; zamek i spust ruszają się bez rąk — `fp_rig.bind_parts`). Wniosek: przegląd póz kostnych i IK w Blenderze nie daje jakości animacji dłoni — potrzebne lepsze narzędzia (np. nagrane / ręcznie animowane klipy rąk), zanim powstaną chwyty kolejnych broni | odłożone |

Do poziomu AAA brakuje jeszcze: chwytów, przeładowań i mechaniki dla pozostałych broni (najpierw lepsze narzędzia animacji rąk — zob. wiersz P-83); łusek wyrzucanych z faktycznego okna każdej broni (dziś jedno przybliżenie od chwytu).
Do tego czasu broń bez klipu `grip_<broń>` jest w kadrze sama (1.7.337, `range_view.ARMS_FALLBACK = false`): ręce z modelu postaci (`fp_arms.gd`)
rozjeżdżały się — SPREAD-12 miał rękaw przez pół kadru, P-83 nie miał rąk. Na strzelnicy HUD chowa kartę celu i opis kryjówki, baner, podpowiedzi
akcji kryjówki i karty tablicy i radia (`hud._in_range`).

## 9. Etap 1 — MVP, część pierwsza (2026-10-21, 1.7.338, gałąź `feat/range-mvp`)

| Element | Jak | Stan |
|---|---|---|
| Drzwi w kryjówce | `RANGE_DOOR := [54, 30]` w `z1_hub.gd` (dolny poziom, za magazynem) → `level.gd` stawia `range3d/range_door.gd` (`RangeDoor`, grupa `range_door`); [E] przy drzwiach (`local_in_range`, podpowiedź w HUD z rekordem drużyny) wchodzi do tunelu; obraz w `view3d._sync_range_doors`: stalowe skrzydło z wizjerem i pochwytem, lampa w koszu, napis RANGE, czerwona lampa „w użyciu” (ktoś ma `in_range`) | zrobione |
| Parkowanie | `player.in_range` (replikowane w MultiplayerSynchronizer): postać stoi przy drzwiach (`_range_brain` — bez ruchu), plakietka „P2 · RANGE”; `fp_mode` ustawia i gasi flagę także w `_exit_tree`, zamyka obraz tunelu, gdy drzwi znikną z mapą; to samo naciśnięcie [E] przy wejściu nie wychodzi (`_enter_frame`) | zrobione |
| Wynik na serwerze | `range_sim.run_shots` / `run_w` → `fp_mode._on_finished` → `range_door.submit` → RPC `_submit_rpc` (host: wprost `_accept`). Serwer przyjmuje tylko od gracza z `in_range`, z bronią w ręku (`player.weapon`), i wiarygodny wynik (`plausible`: co najmniej 5 strzałów, strzelba 3, czas ≥ (n−1) × `cooldown` × 0,75) | zrobione |
| Tablica drużyny | `range_door.board` — 5 najlepszych, jeden wiersz na gracza i broń; trzyma ją host (`Settings.range_board`, zapis w ustawieniach, nie w headless), rozsyła `_board_rpc` z toastem wyniku; dołączający prosi `_request_rpc`. W kryjówce czarna płyta w ramie obok drzwi (czcionka o stałej szerokości), w tunelu wiersz „squad”. Dev `--shotrangeboard` | zrobione |
| Test | `--rangetest` 33/33: [E] przy drzwiach, parkowanie, tablica po przebiegu, `plausible`, odrzucenia (spoza strzelnicy, za szybko, inna broń), brak dubli wiersza | zrobione |

Część druga (1.7.339, gałąź `feat/range-mvp-2`):

| Element | Jak | Stan |
|---|---|---|
| Opcje widoku z oczu | Menu pauzy → FIRST PERSON (RANGE): kąt widzenia 60–100° (domyślnie 74°), czułość ×0,4–×2,5 (mysz i drążek), odwrócona oś Y (`Settings.fp_fov` / `fp_sens` / `fp_invert_y`, sekcja „fp” w ustawieniach); ręce i broń mają stały kąt kamery rąk (`VM_FOV`), łuski i dym przeliczane z bieżącego kąta tunelu | zrobione |
| Akcje w kontekście „range” | `Actions.RANGE_SHEET` (stanowisko, oparcie, przyrządy, strzał, przeładowanie, tryb ognia, typ naboju, broń, wyjście) → `range_sheet()`, `range_hud_line()` (pasek F1 na strzelnicy), `range_line()` (podpowiedź u góry, odświeżana po przypisaniu klawisza); `aim_sights` do przypisania w CONTROLS, na padzie lewy spust (krzyk na strzelnicy nie działa) | zrobione |
| Dźwięk blach | Zamiast rzutu na pozycję 2D — głosy 3D w świecie tunelu (`range_view._play3d`, słuchacz = kamera tunelu, `audio_listener_enable_3d`): `plate_ring` (4 warianty: trzask + nieharmoniczne dzwonienie stalowej tarczy, `bake_weapons.py`), `plate_fall` (stuk o ogranicznik zawiasu 0,16 s po trafieniu), trafienia w ściany i kulochwyt `impact_hard`; strzał i mechanika broni zostają przy uchu | zrobione |
| Przejście kamery | Wejście: kamera kryjówki najeżdża na drzwi na wysokości oczu (`view3d._rp`, 0,6 s, model gracza znika), ostatnie 0,25 s to czerń, z niej wyłania się tunel. Wyjście: tunel gaśnie do czerni, kryjówka wraca przy drzwiach i kamera odjeżdża (`range_view` fazy IN / TUNNEL / OUT / BACK); karty HUD kryjówki wracają dopiero po zgaśnięciu tunelu. Dev `--rangeleave=S` | zrobione |

Poza etapem 1: inne bronie bez klipów rąk (§8). Rekordy trzyma host pod etykietą „P1”–„P4” (numer slotu w tej sesji, nie
profil gracza) — imiona z profilu, gdy pojawią się w grze.

## 10. Etap 3 — bronie specjalne (2026-10-22, 1.7.341, gałąź `feat/range-special`)

Skale świata gry 2D → tunel (`range_sim.gd`): długości przez `PX_PER_M` 12,3 (bełt SINEW-6, zapalnik WRATH-4 „ok. 6,5 m”), prędkości przez
`SPEED_PX` 3,4 (jak kule: dźwięk 1165 px/s ≈ 343 m/s), czas naprowadzania i rozpędu przez `TIME_K = PX_PER_M / SPEED_PX` (tor rakiety ma w tunelu
ten sam kształt co w grze), grawitacja prawdziwa (w grze przesadzona dla czytelności łuku na ekranie).

| Broń | W tunelu | Liczy | Obraz (`range_special.gd`) |
|---|---|---|---|
| WRATH-4 | granat 108 m/s z prawdziwym g (strzał w poziomie opada ok. 0,4 m na 30 m), zapalnik uzbraja się po 6,5 m lotu; uzbrojony wybucha — fala przewraca blachy w połowie promienia wybuchu (3,9 m), bliżej — niewypał (tępe uderzenie, blacha od trafienia pada) | `_launch` (tor krokami 1/240 s), trafienie w chwili uderzenia (`_pending`, `tick` → `_resolve`) | granat w locie, błysk, kula ognia, iskry, dym po błysku, okopcenie, huk 3D |
| FALCON-6 | rakieta startuje wolno i rozpędza się (`speed_at`), po chwili skręca na stojącą blachę w stożku `homing_cone` i zasięgu `homing_range` | `_launch` + `_homing_target` | żarzący się silnik ze światłem, smuga dymu |
| SPECTER-1 | szyna przebija wszystkie blachy na linii aż do bryły tunelu (po pełnym naładowaniu) | `_pierce` | jasny ślad szyny gasnący w 0,45 s, błysk na końcu |
| LR-7 | promień ciągły do 14,3 m (`range_px`), przebija jedną blachę; blacha grzeje się obrażeniami kroku ze spadkiem z odległością i pada po `PLATE_HEAT` (z bliska ok. 0,7 s) | `_beam` (każdy krok ognia przez `range_sink`) | promień od wylotu, światło i iskry na końcu, żarząca się blacha |
| HKM-9 | płomień do 5,2 m w stożku `arc_deg` — najbliższa blacha (7 m) jest poza zasięgiem; koniec płomienia zostawia ogień na podłodze (co 0,5 s, 3,5 s) | `_flame` | stożek cząstek ognia, światło, plamy ognia na podłodze z okopceniem |

Kontroler broni: ogień ciągły na strzelnicy oddaje każdy krok do tunelu (`range_sink.range_shot` w `_handle_continuous`), a serwer nie liczy
promienia i płomienia w kryjówce za gracza z `in_range` (wcześniej płomień zostawiał ogień przy zaparkowanej postaci). Tablica drużyny:
granat i szyna mogą położyć kilka blach jednym strzałem (`RangeDoor.plausible`). Dev: `--rangeweapon=KLUCZ`, `--rangefire` naciska też spust
broni półautomatycznej. Test `--rangetest` 49/49.

Ciąg dalszy (1.7.342, gałąź `feat/range-extras`):

| Element | Jak | Stan |
|---|---|---|
| Papier (seria, grupa) | arkusz 45 × 60 cm na 25 m (`PAPER`, z tarczą z pierścieniami) przestrzeliwuje się na wylot — kule, śrut, szyna, bełt i pociski z lotem zostawiają przestrzeliny (`_paper_ray`); po `PAPER_GAP` 3 s bez trafienia następna kula zaczyna nową serię (czysty arkusz). `paper_group`: liczba, rozrzut (cm i MOA), rozciągnięcie w pionie — seria ogniem ciągłym ciągnie grupę w górę. Wyniki na tabliczce przy papierze i na tablicy nad linią ognia | zrobione |
| Ruchomy cel | wózek na szynie w poprzek tunelu na 22 m (`MOVER_*`, 1,6 m/s tam i z powrotem) z pomarańczową blachą; kula trafia tam, gdzie wózek jest w chwili jej przylotu (`trace` z `speed_m` / `at`, czas lotu z `SPEED_PX`), więc wolny pocisk wymaga wyprzedzenia (bełt: ok. 1,1 m). Trafienia i próby (`MOVER_NEAR` 1,2 m), blacha wstaje po 1,5 s | zrobione |
| Inni gracze na sąsiednich stanowiskach | replikowane `player.range_pose` (stanowisko, odchylenie, pochylenie z podrzutem, przyklęk) i `range_shots`; `range_others.gd` — osobny char3d (wygląd i kolory gracza, jego broń) na jego stanowisku albo najbliższym wolnym, celuje i klęka jak on, strzał: błysk, światło, dźwięk 3D. Przegrody obniżone do 1,45 m — nad nimi widać sąsiada | zrobione |
| Bełt SINEW-6 | lot z opadem w skali świata gry (400 px/s ≈ 33 m/s, 120 px/s² ≈ 9,8 m/s²): na 13 m opada ok. 0,8 m, lot 0,5 s; w locie pręt, wbija się w ściany i kulochwyt (8 ostatnich zostaje) | zrobione |

Poprawka dev: `--range3d` na kliencie (`--join`) czeka na własnego gracza — wcześniej brał gracza hosta („1”) i sterował nim (błędy NaN w pozie postaci).
Test `--rangetest` 54/54. Zostaje: ręce FPP (lepsze narzędzia, §8), etap 2 (przyrządy z `gun_proc.py`, rekordy per broń) — zrobione w §11.

## 11. Etap 2 — przyrządy, przeładowanie, rekordy osobiste (2026-10-22, 1.7.343, gałąź `feat/range-stage2`)

| Element | Jak | Stan |
|---|---|---|
| Linia przyrządów z modelu | `gun_proc.py` `sight_line()` czyta bryły przed scaleniem: przód — wierzch muszki (`fs_post` / `sight_front` / `front_sight`, w ostateczności `fs_tower`), tył — dno szczerbinki (między słupkami `sight_post` wierzch `sight_base`, na celowniku przerzutowym `sight_leaf` krawędź 1,5 mm niżej); kolimator (`sight_tube`) — oś tuby, noktowizor FALCON-6 (`nsp`, zasłania szczerbinkę) — oś od muszli ocznej do obiektywu. Zapis w `gun_<klucz>.json`: `sight_rear`, `sight_front`, `sight_optic` (`dot` / `nv`); `--json-only --nobake` odświeża same `.json` bez przebudowy GLB. Mają je M-83, SPREAD-12, P-83, FALCON-6, WRATH-4; LR-7, HKM-9, SPECTER-1, SINEW-6 i PELLET-8 nie mają przyrządów w modelu — zostaje linia nad najwyższym punktem | zrobione |
| Broń przy przyrządach | `range_view.ads_pose`: przesunięcie i pochylenie broni takie, że linia szczerbinka → muszka leży w osi kamery (punkt linii nad chwytem w tej samej odległości od oka co dotąd); obrót wchodzi razem z postępem celowania | zrobione |
| Obraz przez optykę | tuby kolimatora i noktowizora są w modelu zamknięte — z bliska zasłaniały cel. Przy postępie celowania 0,8–0,97 model broni gaśnie, a `range_optic.gd` (nakładka interfejsu z shaderem) pokazuje okrągłe pole widzenia: kolimator — czerwona kropka z poświatą, noktowizor — zielony ziarnisty obraz ze wzmocnioną jasnością, słupek i poziome kreski | zrobione |
| Ćwiczenie „przeładowanie” | [X] / D-pad ↑ (`range_exercise`, poza przebiegiem) przełącza 5 blach ↔ przeładowanie. Przeładowanie: 4 najbliższe blachy (piąta leży), magazynek trzymanej broni przed startem przycięty do `drill_load` (2 strzały; broń ciągła — 1/5 zbiornika), także po przeładowaniu przed pierwszą blachą; od pierwszej blachy zwykły magazynek. Rekord wizyty osobno dla każdego ćwiczenia | zrobione |
| Tablica drużyny | wynik z ćwiczeniem (`ex`), `plausible` dla przeładowania dolicza przeładowania (amunicja ponad tę z magazynka na starcie: magazynkami albo nabój po naboju × `reload_time` × 0,6). Do 5 wierszy na ćwiczenie; tablica przy drzwiach ma dwie części po 3 wiersze, toast podaje ćwiczenie; zapis sprzed 1.7.343 (bez `ex`) to „5 blach” | zrobione |
| Rekordy osobiste | `Profile.range_best` (`<ćwiczenie>:<klucz broni>` → wynik, mniej = lepiej): czas 5 blach i przeładowania z każdej broni, grupa 5 strzałów na papierze w MOA (`paper`). Tablica w tunelu: rekord trzymanej broni w bieżącym ćwiczeniu, najlepsza grupa przy wierszu papieru, „REKORD OSOBISTY” przy nowym | zrobione |

Dev: `--rangeex=reload` (ćwiczenie na starcie `--range3d`). Test `--rangetest` 68/68 (przyrządy w osi kamery dla 5 broni, optyka WRATH-4 /
FALCON-6, rekordy w profilu i ich zapis, ćwiczenie z przeładowaniem: blachy, przycięty magazynek, przebieg z przeładowaniem na tablicy
przeładowania, walidacja serwera, rekord grupy). Zostaje: ręce FPP (lepsze narzędzia, §8); przyrządy broni, które ich nie mają w modelu
(SINEW-6, PELLET-8) — do dodania w `gun_proc.py` przy ich przebudowie.
