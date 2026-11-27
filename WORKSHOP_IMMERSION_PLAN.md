# Warsztat w świecie — plan refaktoryzacji stanowisk Kryjówki na immersyjne

**Stan (2026-11-27):** R0 wdrożone w 1.7.700, domknięte w 1.7.703 (R0b: `workshop_ui.gd` 998 linii, `view.hint(pad)`), R1 w 1.7.701, R5 w 1.7.702 (`hub_station_end`: `time`, `first_act`). Dalej: playtest i decyzje o R2–R4. Podstawa: main 1.7.698 (`4be53cc8`). Kontynuuje `WORKSHOP_PLAN.md` (decyzja 5
„kamera na blat” — przyjęta 2026-10-22, nigdy nie zrobiona w kamerze świata) i `STATION_CARDS_PLAN.md` (E0–E5 — karty już
w nocnej palecie, tylko prezentacja). Zmienia się **prezentacja i struktura kodu**; `Scrap.*`, `Profile.*`, ceny, serwer i dane zostają
(GDD §16.0a: bez nowych stanowisk, walut i warstw zużycia do Gate 0).

## 1. Diagnoza — dlaczego dziś to nie jest immersyjne

| # | Fakt z kodu | Gdzie | Skutek |
|---|---|---|---|
| 1 | Otwarcie dowolnego stanowiska kładzie pełnoekranową zasłonę `Color(…, 0.65)` i kartę ×1,0–1,4 na środku | `workshop_ui.gd` `_ready` (`_shade`), `_process` (`card_scale`) | Kryjówka znika; to „ekran sklepu”, nie miejsce |
| 2 | Kamera świata się nie rusza — gracz stoi w kadrze przekroju obu pokładów | `view3d.gd` `_sync_camera` (brak gałęzi stanowiska) | Decyzja 5 z `WORKSHOP_PLAN.md` niewykonana |
| 3 | Broń na ławie żyje w osobnym świecie (`SubViewport.own_world_3d = true`) z proceduralnym stołem i własnym światłem | `gun_stage.gd:129–134` | Model ławy w Kryjówce (`gunsmith_bench.glb`) i broń na macie to dwie różne ławy |
| 4 | Postać przy stanowisku nic nie robi; stan „pracuje przy ławie” nie istnieje i nie jest replikowany | `player.gd`, `char3d.gd` (brak) | W co-opie kolega widzi stojący manekin |
| 5 | Dźwięki stanowisk idą przez `Audio.play(…, BUS_UI)` (19 wywołań w panelu i widokach) | `workshop_ui.gd` `STATION_SOUNDS`, `_success_fx` | Prasa „klika” w głowie gracza, nie w piwnicy; drużyna nic nie słyszy |
| 6 | Zdarzenia Kryjówki (pukanie do D-7) symulowane na karcie: czerwony pas na krawędzi ekranu, drganie papierów | `workshop_ui.gd` `_hub_events`, `_on_knock` | Zastępnik świata, który zasłoniliśmy w pkt 1 |
| 7 | Stan stanowisk (zamówione partie, badanie, tokarka) widać tylko w karcie | `Scrap.orders`, `Scrap.lab_*`, `Scrap.lathe_*` | Kryjówka nie opowiada, co drużyna ma w toku |

Dług w kodzie, który blokuje powyższe:

| # | Fakt | Gdzie |
|---|---|---|
| K1 | 7 prawie identycznych skryptów stanowisk (68–81 linii): ten sam `_physics_process`, `interact_offer`, `interact_hint`, różnią się `REACH`, `MODELS`, trybem i tekstem | `workshop.gd`, `service_bench.gd`, `press_bench.gd`, `pyro_bench.gd`, `lab_bench.gd`, `lathe_bench.gd`, `locker_station.gd` |
| K2 | `workshop_ui.gd` — 2784 linie, 138 pól stanu, tryb jako napis i rozgałęzienia `if _mode == …` (np. `_controls_hint` — 9 gałęzi); ława (ARMS) nadal w środku, choć 4 widoki są już w `stations/` | `workshop_ui.gd`, `MODE_PAGES`, `MODE_GROUP` |
| K3 | Kamera świata ma dwa osobne, skopiowane mechanizmy najazdu: oględziny / gablota (`_fp`) i strzelnica (`_rp`); raport po akcji trzeci, w `player.gd` | `view3d.gd:760–797`, `player.gd` `_result_camera` |
| K4 | Panel sam sprawdza zasięg co klatkę przez grupę z `MODE_GROUP` i zamyka się po odejściu — logika stanowiska w UI | `workshop_ui.gd` `_process` |

## 2. Cel i zasady

**Cel:** podejście do stanowiska i [E] to *zbliżenie na ten stół w tym bunkrze* — kamera dojeżdża do blatu, światło robocze się
zapala, postać pochyla się nad ławą, dźwięki dochodzą z miejsca pracy, a karta to kartka leżąca obok, nie okno na pół ekranu.
Drużyna widzi i słyszy, kto przy czym pracuje. Wyjście [Esc] odjeżdża do kadru gry.

Zasady:
1. **Tylko prezentacja + replikacja stanu „przy stanowisku”.** Żadnej nowej ekonomii, czasu, kosztu. Serwer rozstrzyga jak dziś.
2. **Tylko 3D w świecie** (`CLAUDE.md`): lampa robocza, iskry, postać — 3D. Karta, metryka, taśma z klawiszami — UI (wyjątek zasady).
3. **Czytelność przed klimatem:** tekst ≥ 12 px przy 720p (`UI_PLAN.md`), kontrast notatek (`test_note_contrast.gd`), pad i klawiatura
   bez myszy jak dziś (`Actions`), skale UI i EN/PL (`--uifittest`).
4. **„Reduce effects”** = cięcie zamiast najazdu, bez kołysania, bez migotania lampy.
5. **Nic nie wolniej:** najazd ≤ 0,45 s i przerywalny — [Esc] w trakcie najazdu wraca od razu; pierwsza akcja przy ławie
   (cel `WORKSHOP_PLAN.md`: < 10 s dla nowego gracza) nie może się wydłużyć.
6. **Testy headless zostają zielone** na każdym etapie: `--workshoptest`, `tools/workbench_qa.gd`, `test_interact.gd`, `test_hub_camera.gd`,
   `--uifittest`, `test_weapons.sh`, `test_cabinets.sh`.

## 3. Architektura docelowa

```
Station (Node2D, scripts/station.gd)              ← 7 stanowisk dziedziczy, każde ~15 linii danych
  ├─ mode, reach, models, plate, hint()            (dziś skopiowane w 7 plikach)
  ├─ shot: {eye_dx, eye_h, z, look_dy, fov}       ← NOWE: kadr kamery na blat (dane, nie kod)
  ├─ work_spot: Vector2 (gdzie stoi postać)        ← NOWE
  └─ work_light: [x, y, z, kolor]                  ← NOWE: lampa robocza (zapala się przy użyciu)

StationPanel (workshop_ui.gd, ~900 linii)          ← stan sesji panelu: open/close, _session, _pending_*, portfel, taśma
  └─ views: {mode → StationView}                   ← jeden interfejs: build / refresh / act / input / hint / shot_anchor
       bench_view.gd (NOWY — ARMS z workshop_ui)   supply_view · service_view · lab_view · locker_view (są)

view3d.gd: CameraFocus                             ← NOWE: jedna lista „ujęć” z wagą (oględziny, gablota, strzelnica, stanowisko)
  focus_shot() → {eye, target, fov, weight}         zamiast trzech kopii lerp w _sync_camera

player.gd: station: String (replikowany)          ← NOWE: "", "bench", "press"… — pose, lampa i dźwięk u wszystkich
```

## 4. Etapy (jeden PR na etap)

### R0 — refaktor bez zmiany zachowania (przed playtestem, tani)

1. `scripts/station.gd` (+ `.gd.uid`): wspólna klasa stanowiska. `workshop.gd` i 6 pozostałych zostają jako cienkie podklasy z danymi
   (`MODE`, `REACH`, `MODELS`, `MODEL_CHECK`, `hint_text()`); grupy (`workshop`, `press_bench`…) bez zmian, bo czytają je testy i `main.gd`.
   Uśpienie stanowiska (plandeka, `Scrap.lab_open` / `lathe_open`) przechodzi do bazy jako `is_awake()`.
2. Zasięg i zamknięcie po odejściu: stanowisko emituje `left_range`, panel przestaje szukać go przez `MODE_GROUP` co klatkę (K4).
3. `scripts/stations/bench_view.gd`: ARMS (ława z `GunsmithPanel`, `_present_bench`, `_comparison_rows`, `_part_delta`, presety)
   wyjęte z `workshop_ui.gd` tak, jak w 1.7.420 wyjęto 4 widoki. `_controls_hint` → `view.hint(pad)` w każdym widoku.
4. `view3d.gd`: `_fp` i `_rp` jako dwa źródła jednej funkcji `_focus_shot()` (K3), wynik identyczny.

**Akceptacja:** zrzuty wszystkich 7 stanowisk przed / po identyczne poza animacjami (jak w 1.7.420), wszystkie testy z §2.6 PASS,
`workshop_ui.gd` < 1000 linii, skrypty stanowisk < 30 linii.

### R1 — kamera na blat (największy efekt, przed playtestem)

1. Dane `shot` w każdym stanowisku: oko na wysokości ok. 1,55 m, 1,6–2,2 m przed płaszczyzną gry, lekko z góry na blat;
   ławka szafek i tokarka z boku. Źródło ujęć: `--shotorbit` do strojenia, potem stałe w danych.
2. `CameraFocus` dostaje źródło „stanowisko”: waga rośnie przez 0,45 s (smoothstep, jak `_fp`), [Esc] w trakcie — odwrót od bieżącej wagi.
   Etykiety i paski 2D gasną jak w oględzinach (`label_fade`). Kamera areny Żyły i raport po akcji mają pierwszeństwo (nie dotyczy Kryjówki,
   ale reguła w jednym miejscu).
3. Zasłona `_shade` 0,65 → winieta na krawędziach (jak `Scrim` raportu, `RESULTS_PLAN.md` S3) ok. 0,25; środek ekranu — stół.
4. Karta przesuwa się z środka na bok przeciwny do stołu (`view.shot_anchor()` — lewa / prawa), skala jak dziś; stół w kadrze nie jest
   zasłonięty przez kartę w 16:9, 21:9 i 16:10.
5. Lampa robocza stanowiska (`SpotLight3D`, bez cienia — budżet cieni lamp `shadow_casts.gd`) zapala się z najazdem.

**Testy:** rozszerzenie `test_hub_camera.gd` → `[STATION-SHOT]`: dla każdego stanowiska bryła modeli (`interact_mark3d.project_box`)
w bryle widzenia i poza prostokątem karty, w trzech proporcjach i trzech zoomach; gracz nie zasłania blatu; żaden element `Front3D` przed
blatem (`STATION_CH` już trzyma ±1 m — sprawdzić, czy wystarcza przy bliskim oku). `--workshoptest`: „Reduce effects” = cięcie;
[Esc] w trakcie najazdu zamyka. Pomiar: `--perfreport` przy otwartej ławie, 3 przebiegi (raport 1.7.385 miał jeden — §Wydajność).

### R2 — postać i dźwięk w świecie (po playteście)

1. `player.station` (napis, replikowany w istniejącej synchronizacji stanu gracza; ustawia go właściciel, serwer tylko przekazuje — to
   prezentacja, nie gameplay). Gracz staje na `work_spot`, odwraca się do stołu; `Char3D` — poza „pochylony nad blatem” z istniejącego
   `lean` / `kneel` (szafka: stoi przodem, pracownia: pochylony nad słojami). Kolega widzi pracującego i lampę.
2. Dźwięki stanowisk: `Audio.play_at(key, station_pos, BUS_WORLD)` zamiast `BUS_UI` dla dźwięków przedmiotów (montaż, prasa, szlifierka,
   wieko skrzyni); kliknięcia nawigacji zostają w `BUS_UI`. Zdarzenie „operacja się udała” jako RPC prezentacyjne — reszta drużyny słyszy
   prasę w piwnicy.
3. Pukanie do D-7 z widocznym światem: czerwony pas pod drzwiami widać w kadrze, jeśli D-7 jest w ujęciu; nakładka na karcie zostaje
   tylko jako napis z kierunkiem (dostępność) — drganie papierów zostaje.

**Testy:** `test_net_session.sh` — klient widzi `station` hosta i odwrotnie, rozłączenie czyści stan; `--workshoptest` — pozycja i
kierunek postaci, `play_at` z pozycją stanowiska.

### R3 — ława w świecie zamiast osobnego świata (spike za flagą, decyzja po pomiarze)

`GunStage` dziś rysuje broń w `own_world_3d`. Wariant: broń na prawdziwym blacie `gunsmith_bench.glb` w świecie Kryjówki, kadr z R1,
światło robocze z R1. Do sprawdzenia w spike'u `--benchworld`:
- wybór gniazda i kotwice etykiet (`slot_at`, `slot_screen_position`) przez kamerę świata zamiast kamery SubViewportu;
- czytelność części w nocnym oświetleniu (lampa robocza vs. dzisiejsze studyjne światło sceny);
- koszt: dziś +0,19 ms GPU za podgląd; w świecie — cienie i mgła Kryjówki;
- oględziny (obrót broni) — w świecie broń unosi się nad matę jak dziś.

Jeśli spike przegrywa na czytelności albo koszcie, zostaje SubViewport, a ujęcie R1 i tak pokazuje prawdziwą ławę dookoła karty.

### R4 — Kryjówka pokazuje stan bez otwierania kart (po playteście)

Tylko odczyt istniejących danych:
- prasa: pudełka zamówionych partii na matrycy (`Scrap.orders`), po misji — gotowe na półce do odbioru;
- tokarka: wrzeciono się kręci i przedmiot w uchwycie, gdy jest zlecenie (`Scrap` machining); pracownia — słoje pełne wg próbek w banku
  (dziś tylko na karcie, `LabArt.Jars`);
- ława: zamontowana konfiguracja broni gracza leży w imadle (`Profile` montaż);
- szafka: drzwi uchylone, gdy właściciel ma niewydany poziom perków.

**Testy:** `--workshoptest` — stan modeli zgodny ze `Scrap` po zamówieniu, misji i odbiorze; `test_front.gd` — nic nie wchodzi w pas gry.

### R5 — pomiar

Dziennik sesji: przy zamknięciu panelu wiersz `hub_station_end` z czasem w stanowisku i do pierwszej akcji (`time`, `first_act`; wdrożone w 1.7.702, raport `session_progress.py` → `hub_moves.station_time`).
Porównanie przed / po R1 na playteście (§23.3). Bez tego nie wiadomo, czy zbliżenie pomaga, czy spowalnia.

## 5. Kolejność i koszt

| Etap | Kiedy | Rozmiar | Ryzyko |
|---|---|---|---|
| R0 | teraz | średni (przenosiny, ~1800 linii ruchu) | niskie — zrzuty przed / po |
| R1 | teraz, po R0 | mały–średni | kadr przy 21:9 i CLOSE; lampy i cienie |
| R5 | razem z R1 | mały | — |
| R2 | po playteście | średni (sieć, animacja) | poza „pochylony” bez nowych klipów może wyglądać sztywno |
| R3 | spike po R1 | duży | wybór gniazd i czytelność w ciemności |
| R4 | po playteście | średni | gęstość modeli w kadrze przekroju |

GDD §16.0a każe najpierw §16.1 (AI towarzysz, stabilność 4 osób, demo) — dlatego przed playtestem tylko R0 + R1 + R5: tanie,
porządkują kod i od razu zmieniają wrażenie z „sklepu” na „stół w bunkrze”.

## 6a. Jak to robią inne gry (przegląd 2026-11-26)

Źródła: prasa, wiki, analizy UX (lista w odpowiedzi w rozmowie). Fakty oznaczone *(wł.)* pochodzą z własnej wiedzy, a nie z
przeczytanego źródła — do sprawdzenia na nagraniu z gry przed powołaniem się na nie.

| Gra | Jak działa stanowisko | Wniosek dla nas |
|---|---|---|
| The Last of Us Part II | Ława w świecie: osobne animacje wzięcia, odłożenia i zamontowania części, czyszczenia i ładowania; zamontowana część zostaje na broni w przerywnikach. Plecak nie pauzuje gry (Pete Ellis: napięcie przy zasadzce przy ławie). *(wł.)* Kamera zza ramienia nad blatem, panel z boku | Potwierdza R1 (kadr na blat), R2 (postać pracuje) i `animate_mount`. Montaż „widać rękami”, nie tylko w karcie |
| Metro Exodus | Dwa poziomy: plecak (szybkie zmiany w terenie) i ława (pełna zmiana, amunicja, czyszczenie z przytrzymaniem klawisza); brud widać na broni | Czyszczenie z przytrzymaniem już mamy (E3). Brud widoczny tylko na ławie (`WORKSHOP_PLAN.md` W2) — kandydat do R4 |
| This War of Mine | Widok z boku „udający 2D”, a zbudowany w 3D — jak nasz. *(wł.)* Postać idzie do stanowiska i pracuje z animacją; mały panel wyskakuje przy obiekcie, schron zostaje w kadrze | Najbliższy odpowiednik naszego przekroju. Mocno za R1.3–R1.4 (bez zasłony, karta przy stole) i R2 |
| Lethal Company | Terminal na statku: podejście + [E], komendy w terminalu w stylu IBM 3270; zakupy przylatują rakietą po lądowaniu. *(wł.)* Kamera blokuje się na ekranie, inni widzą gracza przy terminalu, a świat działa dalej | Co-op horror: kto przy czym stoi, jest częścią gry drużynowej → R2 |
| Dead Space (remake) | UI w świecie (holo z kombinezonu), ławy jako stanowiska; mapę-hologram z oryginału w remake'u zamieniono na 2D, bo była niewygodna | Granica: diegeza tylko tam, gdzie nie psuje obsługi. Karta zostaje UI „przy stole”, nie wszystko w 3D → R3 jako spike, nie z góry |
| Escape from Tarkov | Montaż w menu: ogromna głębia, krytykowana jako przytłaczająca; pomaga natychmiastowy podgląd zmian statystyk przy przełączaniu części | Immersja nie naprawia złożoności. Zostaje limit 4 głównych zmian na karcie i podgląd przed zakupem |
| Resident Evil 4 (remake) | Walizka jako przedmiot to ikona gry; menu maszyny do pisania i kupca recenzent nazwał sterylnymi, niepasującymi do stylu | Nasze karty-przedmioty (metryka, regał, skrzynia — E1–E5) idą w dobrą stronę. Słabszym punktem jest otoczenie karty (zasłona), nie sama karta |
| Deep Rock Galactic, Helldivers 2 | Hub co-op z terminalami w sektorach; gracze są razem na pokładzie, gry w hubie (Space Ball). W Helldivers światła mostka i zbrojowni robią się czerwone przy planecie o wysokim priorytecie | Hub opowiada stan bez otwierania menu → R4 |
| Darkwood, Alien: Isolation | Praca w kryjówce pod presją nocy; *(wł.)* w Alien tworzenie przedmiotów nie zatrzymuje gry | Nasza Kryjówka to strefa bezpieczna (`NoiseMgr.safe_zone`). Pukanie do D-7 widoczne w kadrze (R2.3) to granica — prawdziwe zagrożenie w Kryjówce byłoby nowym systemem (§16.0a) |

Ramy: Fagerholt i Lorentzon, „Beyond the HUD” (Chalmers 2009) dzielą UI na diegetyczne, przestrzenne, meta i niediegetyczne.
Peacocke i in. (2018) w badaniu na graczach: wskaźniki diegetyczne i przestrzenne lepsze dla amunicji, HUD lepszy dla zdrowia.
Wniosek: karta stanowiska ma być **przestrzenna** (przy stole, w kadrze świata), a nie w pełni diegetyczna.

**Zmiany w planie po przeglądzie:**
1. R1 bez zmian. Wzmocnienie punktów R1.3–R1.4: zasłona zamieniona na winietę i karta przy stole to wzorzec TWoM i TLOU2.
2. R2 przed R3: postać widoczna przy stanowisku w co-opie (Lethal Company, TWoM) daje więcej niż broń w świecie zamiast SubViewportu.
3. R3 tylko jako spike. Rekomendacja do decyzji 2: zostaje SubViewport, chyba że spike wyraźnie wygra czytelnością (lekcja z Dead Space).
4. Pomysł na później (po Gate 0, bo to nowy system): w Kryjówce coś, co przerywa pracę przy stole (TLOU2, Alien).

## 6. Decyzje do podjęcia (z rekomendacjami)

| # | Decyzja | Rekomendacja | Dlaczego |
|---|---|---|---|
| 1 | **Zakres przed playtestem:** R0 + R1 + R5 czy tylko R0? | **R0 + R1 + R5** | R0 sam nic nie zmienia dla gracza; R1 to najtańsza zmiana odczuwalna (kamera na blat, winieta zamiast zasłony — wzorzec This War of Mine / TLOU2), R5 daje dane z playtestu do decyzji o R2–R4. Wszystko w granicach GDD §16.0a (tylko prezentacja). |
| 2 | **Ława ARMS:** spike R3 (broń w świecie Kryjówki) czy SubViewport z ujęciem R1 dookoła? | **Zostaje SubViewport**; R3 tylko jako spike `--benchworld` po R2 | Dead Space remake cofnął się z diegezy tam, gdzie szkodziła czytelności; Tarkov pokazuje, że problemem jest złożoność, nie klimat. Spike przechodzi tylko, jeśli wyraźnie wygra czytelnością na zrzutach. |
| 3 | **Ruch przy stanowisku:** panel dalej blokuje wejście (`Settings.block_game_input`) czy ruch zamyka panel? | **Blokada zostaje** | Kryjówka to `NoiseMgr.safe_zone`, więc praca przy stole nie wymaga ucieczki w trakcie; zmiana dotyka sterowania i testów, a nie daje imersji. Do powrotu po Gate 0 razem z pomysłem „coś przerywa pracę przy stole”. |
| 4 | **Poza postaci (R2):** istniejące klipy `lean` / `kneel` czy nowy klip? | **Istniejące klipy** | Wystarczą, by inni gracze widzieli, kto przy czym stoi (Lethal Company, This War of Mine). Nowy klip z ActionForge / mocapu dopiero, gdy playtest pokaże, że poza źle się czyta. |

**Kolejność po rekomendacjach:** R0 → R1 → R5 → (playtest / Gate 0) → R2 → R4 → spike R3.
