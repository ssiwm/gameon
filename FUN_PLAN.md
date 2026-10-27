# FUN_PLAN — więcej emocji z rdzenia gry

Analiza 2026-10-27 na 1.7.399–1.7.400: GDD, kod (`noise_manager.gd`, `director.gd`, `stalker.gd`, `hints.gd`, `mission.gd`) i 129 misji
(> 60 s) z dzienników sesji z października (`user://sessions/*.jsonl`). Zastrzeżenie: to sesje autora z botem — §23.3 GDD nie ma jeszcze
wpisów z zewnętrznych playtestów, więc liczby wskazują problemy, a nie zastępują playtestu.

Zakres zgodny z GDD §16.0a: zmiany dotykają rdzenia (Uwaga, Stalker, co-op, rytm sesji), nie dodają stanowisk, walut ani warstw warsztatu.
Mapa 1.3 zostaje nietknięta (`MAPS_PLAN.md`).

## 1. Co mówią dane

| # | Obserwacja | Liczby |
|---|---|---|
| D1 | Uwaga to przełącznik, nie krzywa | 52 % czasu misji < 40, tylko **10 %** w paśmie 40–59 („COŚ SŁUCHA”), 28 % ≥ 80; mediana szczytu każdej mapy = 100; próg 60 w medianie po 65 s |
| D2 | Część hałasu nie zależy od gracza | ok. 30 % sumy Uwagi to źródła bez znacznika (`world`: wrogowie, gniazda, generator, boss) |
| D3 | Stalker nie zabija, więc nie straszy | 1257 zamachów, 206 trafień, ale tylko **10 z ok. 350** upadków ludzi; zabijają Trzoski (86), Skoczki (31), Wołki (25); obudzony 121×, uśpiony 59× |
| D4 | Pudło Stalkera nagradza go szybszym ciosem | `MISS_COOLDOWN` 0,8 s < `ATTACK_COOLDOWN` 1,5 s — po uniku kolejny zamach przychodzi szybciej niż po trafieniu, więc pudła sypią się seriami bez żadnego efektu |
| D5 | Filar 2 (Q) prawie nie istnieje | **8 użyć na 129 misji**; GDD §8.4 obiecuje „drużyna zyskuje 20 s”, ale w kodzie następny strzał kolegi od razu zawraca Stalkera |
| D6 | Gra się jedną bronią | M-83: 81 % zabójstw, 51 tys. strzałów; GNIEW-4: 242 zabójstwa z 297 strzałów — najskuteczniejsza i prawie nieużywana; kucanie 12,5 % próbek |
| D7 | Krzywa trudności to ściana | 1.1 NORMAL 37/42 sukcesów; 1.3 NORMAL **2/24**, połowa wipe'ów w fazie BOSS (cała misja od nowa); B1 0/11 (przed 1.7.398) |
| D8 | Brak nagród w trakcie i rytmu sesji | żadnych wyróżnień ani wyzwań w kodzie; mediana **1 misja na sesję**, kryjówka mediana 254 s; perki 0 założonych przy L7 |

## 2. P0 — wdrożone w 1.7.401 (`feat/fun-p0`)

### P0.1 Ucieczka o włos (D3, D4)
- Zamach Stalkera, który chybi człowieka będącego tuż obok (≤ `CLOSE_CALL_R` od zasięgu ciosu), to **ucieczka o włos**: u tego gracza
  zwężenie kadru (winieta, aberracja), przytłumienie świata i muzyki, impuls i krótki komunikat „CLOSE CALL”. Najwyżej raz na `CLOSE_CALL_GAP` s
  na gracza — seria pudeł to jedna ucieczka.
- Serwer liczy ucieczki w `mission.player_stats[id].escapes` (karta wyniku, dziennik `stalker` z `what: "close_call"`).
- `MISS_COOLDOWN` = `ATTACK_COOLDOWN` (1,5 s): unik nie daje Stalkerowi szybszego ciosu niż trafienie. Mniej zamachów, każdy coś znaczy.

### P0.2 Widoczne Q (D5)
- Udane Przesterowanie (nie „zwietrzałe”) **przytrzymuje** Stalkera na wabiku przez `LURE_LOCK` s: nowy hałas go nie zawraca (GDD §7.3:
  „wabik odciąga go na 20–30 s”). Przerywa to tylko snop latarki na nim (wyjątek z §7.3) albo kolejne Q.
- Wszyscy widzą skutek: w HUD „HE TAKES THE BAIT” z odliczaniem zamiast „He hears you…”, warkot Stalkera z jego miejsca (zawraca).
- Podpowiedź w chwili, gdy ma sens: Stalker poluje tuż przy koledze, a ja mam ładunek → „He's on P2 — {overcharge} lures him off”.
- Serwer liczy udane wabiki w `player_stats[id].lures`.

### P0.3 Punkt kontrolny przed bossem (D7)
- Misja z gniazdami i bossem (1.3): wejście w fazę BOSS zapisuje punkt kontrolny (pozycje ludzi i botów). Wipe w fazie BOSS wraca do
  **początku walki z Żyłą**, a nie na start mapy: gniazda zostają zniszczone, Żyła i reszta wrogów wracają do stanu startowego, Uwaga,
  ekwipunek i łup jak po zwykłym wipe'ie (łup próby przepada — GDD §4), licznik prób +1. Żyła budzi się po `CHECKPOINT_GRACE` s.
- Wykrwawienie w fazie BOSS też odradza w punkcie kontrolnym (kara dystansem zostaje, ale nie 5 minut marszu).
- Mapa bez zmian; B1 (cała misja to boss) nie potrzebuje punktu kontrolnego.

### P0.4 Następna misja z karty wyniku (D8)
- Na karcie wyniku kampanii host ma dwie drogi: [restart] — kryjówka (jak dotąd), [interact] — **od razu następna misja** z zachowanym
  ekwipunkiem i nową prognozą pogody. Nocny Dyżur bez zmian.

### P0.5 Wyróżnienia na karcie wyniku (D8)
- Z `player_stats` (serwer, replikowane do wszystkich) karta liczy wyróżnienia: **GHOST** (najmniej własnego hałasu — strzały, bieg,
  przeładowania; w pojedynkę: Stalker ani razu się nie obudził), **MEDIC** (najwięcej podniesień kolegów), **BAIT** (najwięcej udanych wabików),
  **CLOSE SHAVE** (najwięcej ucieczek o włos), **BUTCHER** (najwięcej zabójstw). Bez progu nie ma wyróżnienia (np. MEDIC wymaga ≥ 1).
- Liczy to statyczna `Mission.awards()` — ta sama na każdym peerze, test `--funtest`.
- Przybliżenia (do sprawdzenia w playteście): podniesienie rozstrzyga właściciel podnoszącego, więc MEDIC dostaje najbliższy stojący człowiek
  w 48 px od wstającego (przy „Drugiej szansie” albo podniesieniu przez bota obok może trafić do kogoś obok); hałas GHOST przypisuje serwer
  najbliższej postaci w 24 px od zdarzenia (gracz zgłasza je z własnej pozycji, hałas bota nie idzie na niczyje konto).

## 3. P1 — wdrożone w 1.7.402 (`feat/fun-p1`)

Na prośbę użytkownika wdrożone przed playtestem P0 — liczby (budżet 6 / 2 na s, 15 s → 70, oddech 8 s × 0,5) są punktem wyjścia do strojenia.

| # | Zmiana | Problem |
|---|---|---|
| P1.1 | ✅ Hałas wrogów (`enemy`) z budżetem Uwagi (6, odnowa 2/s); `alarm` i skryptowe skoki bez limitu; źródła świata z własnymi znacznikami w dzienniku | D1, D2 |
| P1.2 | ✅ 15 s na 100 → spadek do 70 i 8 s oddechu (hałas × 0,5), HUD „THE NOISE FADES”, zdarzenie `peak` | D1 |
| P1.3 | ✅ Skrzynie mocy (decyzja: broń tymczasowa poza slotami): 1.1 WRATH-4 × 8, 1.2 FALCON-6 × 60; bez przeładowania i zacięć, zmiana broni zablokowana, po ostatnim naboju wraca broń ze slotu; serwer liczy przydział i odrzuca strzał z broni spoza zestawu | D6 |
| P1.4 | ✅ Pancerz zbija strzał śrutem raz, nie każdą śrucinę (SPREAD-12 w Wołka ok. 32 zamiast 20; GNIEW-4 jako wybuch pancerza i tak nie zna); cios przechodzi przez pole Podsłuchacza | D6 |

## 4. P2 — wdrożone w 1.7.403 (`feat/fun-p2`)

Na prośbę użytkownika przed playtestami — wartości (próg 60, +30 złomu, sejf 3 s / 3 na s / +12 / 40 złomu) do strojenia.

| # | Zmiana | Problem |
|---|---|---|
| P2.1 | ✅ Cichy cel w 1.1–1.3: Uwaga < 60 przez cały cel główny → +30 złomu (podwaja premię za ukończenie), toast „SILENT RUN LOST”, wiersz na karcie wyniku; cel poboczny 1.2 (< 40) zostaje | D1 |
| P2.2 | ✅ Sejfy (`strongbox.gd`, `STRONGBOXES`): trzymany [E] 3 s, 3 Uwagi/s i łoskot +12, 40 złomu (2× skrytka); 1.1 przy strażnicy, 1.2 obok Podsłuchacza | D1, D5 |

## 5. Pomiar po P0

`mission_end.players[id]` ma `escapes`, `lures` i `noise`; zdarzenia `stalker` z `close_call` i `overcharge` z `locked`; `mission_start.checkpoint`.
Do porównania przed/po: użycia Q na misję, ucieczki o włos na minutę z obudzonym Stalkerem, sukcesy 1.3 NORMAL, misje na sesję.
