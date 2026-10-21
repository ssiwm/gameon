# Plan: strzelnica FPS 3D w kryjówce

Status: **etap 0 (szpic `--range3d`) zrobiony — 1.7.335, gałąź `feat/range-fps`**; wyniki i decyzje w §7. Zastępuje strzelnicę boczną z PR #413
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
| **3 — reszta broni i co-op** | WRATH-4 (tor łukowy, odległość uzbrojenia), Gyrojet (przyspieszanie), LR-7 / SPECTER-1 / HKM-9 (promień, szyna, płomień — uproszczone cele), seria, ruchomy cel, widok innych graczy na sąsiednich stanowiskach (synchronizacja pozy). | j.w. | po playteście |

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
| Światło | AgX (ekspozycja 1,3), lampy ok. 3800 K (×0,8), lampa nad dłońmi przeniesiona za plecy, wypełnienie 0,8 tylko dla warstwy rąk; pomiar: albedo rękawic 0,026, rękawów 0,04 (liniowo) — przepalenie dawało światło, nie tekstury | zrobione |
| Rękaw | `cloth_garments.py --fp` → `art_src/clothes/male_scav_m65_fp.glb` (same rękawy + karczek, własne UV 2K; prawy = odbicie lewego, bo w symulacji prawy mankiet podjeżdża) | zrobione |
| Chwyt | `tools/fp_grip.py`: układy dłoni, IK z biegunem łokcia, podział skrętu, osadzenie dłoni (wnętrze dłoni dosuwane do broni), palce do kontaktu (BVH, do 125°), klip `grip_m83` + `gunref_m83` | obie dłonie na broni: palce prawej na chwycie, lewa obejmuje łoże (luz 0–0,5 mm) |
| Przeładowanie | `reload_m83` (1,35 s, 11 klatek) i `reload_empty_m83` (1,8 s, 15 klatek): lewa dłoń sięga, chwyta, wyważa, wyciąga, ładownica, powrót, zahaczenie, zatrzaśnięcie; broń ma w każdej klatce pozę (`GUN_POSES`: przechył ~10°, podbicie, szarpnięcie suwadła), prawa ręka za nią przez IK; palce: kontakt z magazynkiem albo ułożenia (`FINGER_SETS`: dłoń otwarta, hak na suwadle, puszczenie); w grze ręce kotwiczone pozą chwytu (`fp_rig.anchor`) | zrobione |
| Mechanika broni | `gun_proc.py`: podzespoły `bolt` (suwadło widoczne w oknie + rączka) i `trigger` (język spustu) M-83; `fp_rig.gd`: cykl suwadła po strzale (8 cm, 25 ms w tył, 35 ms w przód), suwadło za rączką w klipie (`bolt` w .json: chwyt / odciągnięcie / puszczenie), spust 12° wokół nasady. Kurek AKM jest wewnątrz komory — z zewnątrz go nie widać, więc go nie animujemy | zrobione |
| Dźwięki przeładowania | `bake_weapons.py`: osobne `mech_*` (zatrzask, magazynek wysuwany i wsuwany, suwadło w tył i w przód, chwyt łoża) + `foley_gear`; `fp_grip.py SOUNDS` przypina je do klatek, range_view.gd gra je, gdy postęp przeładowania mija klatkę; `weapon_controller._reload_sfx` milczy, gdy klip ma własne dźwięki | zrobione |
| Łuski i dym | `range_fx.gd`: łuski z okna wyrzutowego (rotacja, odbicia od ławy, podłogi, ścian i przegród, stuk `shell`, do 60 na ziemi), dym z wylotu, smużki z gorącej lufy (`barrel_of` > 0,45); punkty startu z kamery rąk przeliczane na kamerę tunelu (stosunek tangensów kątów widzenia) | zrobione |
| W grze | `fp_rig.gd` (broń dzieckiem dłoni), `range_view.gd`: osobna kamera rąk 58°, kołysanie, oddech, odrzut na sprężynie, broń 4K | zrobione, 60 FPS |

Do poziomu AAA brakuje jeszcze: chwytów, przeładowań i mechaniki dla pozostałych broni; łusek wyrzucanych z faktycznego okna każdej broni (dziś jedno przybliżenie od chwytu).
