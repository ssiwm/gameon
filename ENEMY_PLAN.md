# Plan: porządki w logice wrogów pod widok 3D i mądrzejsza AI

Status: **plan z 2026-10-16; F0 zrobiona (1.7.234), F1a zrobiona (1.7.235), F1b zrobiona (1.7.236), F2a zrobiona (1.7.237), F2b zrobiona (1.7.238), F3.1a zrobiona (1.7.239), F3.1b zrobiona (1.7.240), F3.3 odrzucone po pomiarze, F3.5a zrobiona (1.7.241), F3.2 zrobiona (1.7.242), F3.4a zrobiona (1.7.243), F3.6a zrobiona (1.7.244), F3.7 zrobiona (1.7.245), F3.5b i F3.6b zrobione (1.7.246), F3.4b odrzucone, F3.4c zrobiona (1.7.247, gałąź `feat/director-pincer`), zostają F2c, F3.1c, F4.** Oparty na przeglądzie kodu (`enemy.gd`, `enemy3d.gd`, `boss.gd`, `leech.gd`,
`stalker.gd`, `nest.gd`, `director.gd`, `nav.gd`, `noise_manager.gd`, `view3d.gd`) i na `MISSION_3D_SPIKE.md` — nie na próbnej implementacji,
więc rozmiary faz są szacunkowe, a uwagi o błędach pochodzą z lektury kodu, nie z gry.

Cel: (1) odciąć widok 3D wrogów od ukrytych sprite'ów 2D, (2) uporządkować kod wrogów tak, żeby nowy rodzaj nie wymagał dotykania ośmiu miejsc,
(3) poprawić czytelność i „inteligencję” wroga w sposób zgodny z filarami GDD: hałas to waluta (2), groza przez dźwięk i światło (4),
współpraca drużyny (3).

## 1. Decyzja: symulacja zostaje 2D

Nie przepisujemy symulacji na 3D. `CLAUDE.md` („symulacja zostaje 2D”) i `MISSION_3D_SPIKE.md` §5 mówią to samo: 3D jest **widokiem**.
Mapy ASCII, nawigacja A* po kaflach, hitboxy, kompensacja opóźnienia, boty i sieć są 2D, a oś Z nie daje graczowi nic w grze typu Contra.
Przebudowujemy `enemy.gd` i okolice, nie wymiar.

## 2. Stan obecny (z kodu)

- **Widok 3D czytał stan wroga okrężnie** (patrz korekta w F1): z węzła `Body` (zegar animacji) nazwę animacji, klatkę i flip, a rodzaj ze ścieżki
  skryptu, błysk trafienia z **koloru** (`modulate.r > 1.9`) i `_sp` z prywatnego pola — naprawione w F1a.
- **`_sp` (szarża / rzut / oszołomienie Wołka) nie było w `_sync`** — klient nie widział tych póz (naprawione w F1a).
- **`_facing` żyje w `_update_sprite()`**, a od niego zależy backstab (`take_hit` → `_is_behind`). Usunięcie sprite'ów 2D bez wcześniejszego
  przeniesienia go zepsułoby maczetę.
- **Rodzaj wroga jest rozsypany po tabelach:** `KINDS`, `SUPPLY_DROP`, `AMMO_DROP`, `HEALTH_DROP`, `VOICES` (`enemy.gd`), `SPEC` / `DEFORM`
  (`enemy3d.gd`), `KILL_XP` (`profile.gd`), `Scrap.DROP`, manifest sprite'ów; `hurt_h` trzeba ręcznie synchronizować z `fit`.
- **`enemy.gd` ma 1500 linii** `if kind == …` i `_def.get("flaga")`; `boss.gd` i `leech.gd` dublują `_humans()`, skalowanie HP, miniony, fazy, zdarzenia.
- **Hałas to jedno ostatnie zdarzenie** (`last_noise_pos`, `noise_serial`): w jednej klatce drugie nadpisuje pierwsze.
- **AI:** cel = najbliższy widoczny gracz sprawdzany co 0,12 s; poza watahą trzosków brak współpracy; brak czytelnej reakcji „zauważył cię”.
- **Testy:** `--maptest`, `--stalkertest`, `test_sound_grid.gd` — żadnego testu AI zwykłych wrogów.

## 3. Zasady wspólne

1. **Serwer rozstrzyga.** Nowa logika wrogów jest serwerowa; klient dostaje stan, nie liczy go.
2. **Jeden PR = jedna zmiana gry**, z podbiciem `config/version` i wierszem w `CHANGELOG.md` (tytuł = tytuł PR-a). Serię prowadzoną tym planem
   można opisać jednym wspólnym wierszem, jak `AUDIO_PLAN.md`.
3. **Najpierw test, potem zmiana.** Każdy błąd z F0 dostaje asercję w `tools/test_enemy_ai.gd`.
4. **Wartości balansu się nie zmieniają** (px/s, HP, czasy zapowiedzi), dopóki faza tego wprost nie mówi.
5. **Komentarze po polsku, identyfikatory po angielsku**, doc-komentarze `##` (jak reszta projektu).

## 4. Fazy

### F0 — poprawki (bez zmiany architektury) — zrobione w 1.7.234

| # | Zmiana | Plik |
|---|---|---|
| 0.1 | `NoiseMgr._report`: odrzucane ujemne, NaN i zbyt duże wartości (`sane_amount`, limit `MAX_REPORT` 30); pozycja przycinana do mapy (`sane_pos`); `_flare_request` sprawdza pozycję i prędkość | `noise_manager.gd` |
| 0.2 | Potomstwo bossów nie daje XP ani dropów: flaga `summoned` (zostaje też stary wyjątek po nazwie `LeechSpawn`) | `enemy.gd`, `boss.gd`, `leech.gd` |
| 0.3 | Pijawka: kara za nieudany chwyt omija niewrażliwość (`deliver_hit(…, force)`); ofiara wybierana po HP sprzed ugryzienia, nie po `p.hp` zdalnego gracza | `leech.gd`, `player.gd` |
| 0.4 | W jednej klatce fizyki zostaje **najgłośniejsze** zdarzenie hałasu (zamiast bufora kilku — wystarcza, bo problemem był tylko krok po strzale w tym samym tiku) | `noise_manager.gd` |
| 0.5 | Obrażenia ataków specjalnych (lądowanie skoczka, szarża Wołka, ugryzienie ćmy) przez `_scaled_damage` → `Difficulty.m("enemy_damage")` | `enemy.gd` |
| 0.6 | Wołek: szarża tylko, gdy cały rozbieg (do 280 px) jest bez ściany i ma podłogę pod każdym kaflem | `enemy.gd` |
| 0.7 | Cios wręcz nie przechodzi przez ścianę (`_wall_between`, poziomy promień; przy różnicy poziomów nie sprawdzany, żeby nie blokować celu na stopniu) | `enemy.gd` |
| 0.8 | Wydajność: budżet A* na słuchanie hałasu (`SOUND_BUDGET` 6 na klatkę, nadmiar czeka do następnej); latarka na śpiącym sprawdzana co ~0,12 s z losowym przesunięciem | `enemy.gd` |
| 0.9 | Sprzątanie: `Boss._brood` rośnie tylko na serwerze; `_stun_cd` zerowany przy `awaken()`. **Nie ruszono** `_listen` w Stalkerze: zmienna jest martwa, ale `stalker_test.gd` ją ustawia — usunąć razem z testem w F3 | `boss.gd` |
| 0.10 | `scripts/enemy_test.gd` (`--enemytest`, 28 asercji) + krok w CI | `enemy_test.gd`, `main.gd`, `tests.yml` |

Nie sprawdzone grą (tylko testy headless): wygląd i odczucie szarży Wołka oraz reakcji wrogów na budżet słuchania — do playtestu.

### F1 — kontrakt widoku (porządki pod 3D)

**Korekta diagnozy z §2 (2026-10-16, przy wdrażaniu):** węzeł `Body` wrogów to **bezteksturowy zegar animacji** (`Sprites.attach` → `pose_frames`,
„niczego nie rysuje”), a nie sprite 2D z grafiką; PNG arkuszy wrogów nie są ładowane. Zegar (nazwa animacji, klatka, tempo, pętla z manifestu)
jest sensowny i zostaje — Pijawka i Żyła opierają na nim jednorazowe animacje i klatki startowe. Realne problemy były dwa: stan przekazywany
okrężnie (rodzaj ze ścieżki skryptu, błysk trafienia z koloru `modulate`, `_sp` z prywatnego pola) i `_sp` Wołka nieobecny u klientów.

- **F1a — zrobione w 1.7.235:** `view_info()` na wrogu, Stalkerze, Żyle, Pijawce i gnieździe (kind, alive, winding, sp, flash); `view3d.gd: _sync_enemies`
  czyta tylko to; `_sp` replikowany w `enemy.gd: _sync`; test kontraktu w `--enemytest`. Zrzuty z gry przed i po zmianie (Wołek, Żyła, Pijawka) identyczne.
- **F1b — zrobione w 1.7.236:** `_facing` (cios w plecy, ucieczka w panice) liczy serwer z faktycznego ruchu w `enemy.gd: _update_facing`; zwrot
  modelu to osobne `_view_facing` na każdym peerze (`_update_sprite`). Podsłuchacz nadal „patrzy na lokalnego gracza” (jak dotąd) — w F3 powinien na swój
  cel. `view_info` bez `facing` — klient go nie potrzebuje.
- **F1c — opcjonalnie, dopiero gdy będzie powód:** zastąpić zegar `AnimatedSprite2D` własnym (`EnemyView`). Wymaga przepisania logiki jednorazowych
  animacji Pijawki (`_set_anim`, `_anim_start`) i koloru-kanału tintu (uśpiony ×0,8, przezroczystość Stalkera) — ryzyko większe niż zysk, dopóki
  nic nowego tego nie wymaga.

### F2 — dane i moduły, ok. tygodnia

- **F2a — zrobione w 1.7.237:** `enemy_defs.gd` — jedno źródło danych rodzaju (statystyki, zmysły, `xp`, `scrap`, `supply`, `ammo`, `health`, `voice`).
  Zamiast zasobów `.tres` zwykły `const` w skrypcie, jak `weapons.gd` i `throwables.gd` (bez dodatkowych plików do ładowania i commitowania).
  `Enemy.KINDS` zostaje jako alias (kodeks, HUD, testy bez zmian); `SUPPLY_DROP`, `AMMO_DROP`, `HEALTH_DROP`, `VOICES`, `KILL_XP`, `Scrap.DROP` usunięte.
  Test w `--enemytest`: komplet pól, wzorzec wartości sprzed przeniesienia, dźwięki głosów w manifeście, model 3D (`SPEC`) dla każdego rodzaju.
  **Zostaje:** `hurt_h` nadal ręcznie zsynchronizowane z `fit` w `enemy3d.gd: SPEC` (pilnuje tego `test_proportions.gd`); `SPEC` zostaje osobno jako dane prezentacji.
- **F2b — zrobione w 1.7.238:** `boss_base.gd` (`extends CharacterBody2D`): `State`, `state`/`hp`/`max_hp`/`phase`, `is_threat`/`is_alive`, `_humans`, `scaled_hp`,
  `_shake_near`, `_summon` / `_clear_summoned` / `_kill_summoned` (przywołani Trzoski), `_drop_boss_loot`. `boss.gd` i `leech.gd` dziedziczą po nim
  (`extends "res://scripts/boss_base.gd"`; bez `class_name`, jak reszta projektu); `hp`/`max_hp` startują z `_init` (BASE_HP) w podklasach.
  **Zostaje własne:** ataki, okna obrażeń, progi faz, `_sync`/`_event`, `reset_enemy` — różnią się za bardzo, żeby wspólna wersja była czytelniejsza
  (zdarzenia i replikacja mają inne pola); do wspólnej wersji wrócić dopiero przy trzecim bossie.
- **F2c — do zrobienia:** podział `enemy.gd` na zmysły, mózg (maszyna stanów) i zachowania (wataha, szarża, zasadzka, nasłuch, ćma, mimik) — najlepiej razem
  z F3, żeby nie przenosić kodu dwa razy.

### F3 — inteligencja, 2–3 tygodnie etapami (kolejność wg wpływu na rozgrywkę)

1. Jawna maszyna stanów z czytelnym „zauważył”: sen → alarm (0,3–0,8 s, odwrócenie, rozżarzone oczy) → pościg / śledztwo → atak → odpoczynek → szukanie → powrót.
   - **F3.1a — zrobione w 1.7.239:** jawny stan `Ai` (sleep, hang, listen, fly, investigate, search, chase, windup, retreat, panic, special, return, dead)
     liczony raz na tik z flag (`_derive_ai_state`), replikowany w `_sync`, w `view_info()["ai"]`, sygnał `ai_changed`. **Bez zmiany zachowania** — to obserwacja;
     decyzje wciąż podejmują gałęzie `_tick_server`. Test przejść w `--enemytest`.
   - **F3.1b — zrobione w 1.7.240 (zmienia grę, wymaga playtestu):** stan `Ai.ALERT`. Trzosek (`alert` 0,4 s w `enemy_defs.gd`) po obudzeniu hałasem albo po nowym
     kontakcie wzrokowym (z `investigate` / `search` / `return`) staje, odwraca się ku źródłu, ma rozżarzone oczy (`enemy3d.gd: pose(..., alert)`) i cichy warkot
     (głos `alert`), potem rusza. Czas × `enemy_windup` trudności, ±15%; `ALERT_COOLDOWN` 5 s; trafienie przerywa i ustawia cooldown; przywołani i rodzaje bez pola — bez
     reakcji. Kierunek odwrotu idzie w `_sync` (`new_face`). **Do sprawdzenia grą:** czy 0,4 s czyta się jako „zauważył”, a nie lag; czy warkot nie zlewa się z krzykiem
     zapowiedzi; czy ślepiec / skoczek / mimik też powinni mieć reakcję (pole `alert` per rodzaj); czy wataha rusza jednocześnie (rozrzut ±15%).
   - **F3.1c — po F3.1b:** przestawić gałęzie `_tick_server` tak, żeby decyzje wynikały ze stanu (`match _ai`), razem z podziałem `enemy.gd` (F2c).
2. Lokalizacja hałasu z niedokładnością (im dalej i ciszej, tym większy błąd); ślepiec „sprawdza okolicę”.
   - **F3.2 — zrobione w 1.7.242:** `heard_offset` / `_heard_pos` w `enemy.gd`: błąd poziomy = `hear_error` (64 px domyślnie; ślepiec 36, wołek 96) × (słyszalna odległość / zasięg)
     × (1,5 dla zdarzeń cichych); stosowany przy budzeniu hałasem (`_check_wake`), śledztwie po hałasie (`_listen`) i krzyku gracza (`hear_scream`). Tylko w poziomie.
     **Zostaje:** „sprawdzanie okolicy” — dłuższe szukanie po dojściu do niedokładnego śladu (dziś standardowe `SEARCH_TIME`), do decyzji po playtestach.
3. ~~Odległość dźwięku jednym przebiegiem od źródła hałasu (zamiast A* na każdego wroga); wspólne z `sound_grid.gd`.~~ **Odrzucone po pomiarze (2026-10-16):**
   `_sound_distance` (A* po grafie `nav`) kosztuje ≈ 76 µs na wywołanie (30 wrogów naraz = 2,3 ms), a `sound_grid.route` ≈ 81 µs; budżet 6 wyszukiwań na klatkę
   z F0 ogranicza szczyt do ≈ 0,5 ms. Pole odległości z jednego przebiegu pisane w GDScript (BFS po ok. 2–8 tys. komórek) byłoby wolniejsze niż natywny A*, więc
   nic by nie dało. Wrócić do tego tylko, jeśli pomiar w grze z dziesiątkami wrogów pokaże `Nav.stat_usec` jako problem.
4. Współdzielona wiedza grupy z opóźnieniem; role w watasze; flankowanie trasą alternatywną po nawigacji.
   - **F3.4a — zrobione w 1.7.243:** `_shout_sighting` / `_hear_shout`: Trzosek, który po raz pierwszy zauważył gracza, daje znać kolegom z watahy w `SHARE_RADIUS` (220 px,
     ±`SHARE_DY` 40 px w pionie); aktywni i nic niewidzący (`investigate` / `search` / `return`) dostają ślad i `alert`. Cooldown 3 s. Opóźnienie daje sam `alert` (0,4 s ±15%).
   - ~~**F3.4b — flankowanie w walce** (wróg wstrzymany przez `_pack_hold` obchodzi gracza na stronę przeciwną do atakujących).~~ **Odrzucone po analizie (2026-10-16):**
     wrogowie i gracze nie kolidują (`enemy.tscn` warstwa 4 / maska 49, `player.tscn` warstwa 2 / maska 49), więc flanker przechodziłby przez model gracza; `MAX_ATTACKERS` 2 nie
     zmienia obrażeń, tylko stronę ataku; GDD obiecuje „atakuje po kolei"; pole z wolnymi ≥ 6 kafli po obu stronach to tylko 31% (1.3), 58% (1.1), 62% (1.2), 66% (B1) podłogi,
     a w 1.3 dodatkowo 26% to niskie tunele.
   - **F3.4c — zrobione w 1.7.247 (zamiast F3.4b):** kleszcze Dyrektora — nowa grupa wędrowców wychodzi z przeciwnej strony niż poprzednia żywa grupa (`_roamer_side`,
     `pincer_side_ok`; `PINCER_R` 900 px, `PINCER_TRIES` 50 z `PICK_TRIES` 80, potem dowolna strona). Ten sam efekt „z dwóch stron" bez przenikania.
5. Wybór celu z pamięcią i histerezą (świecący, hałasujący, odizolowany, ranny; bot nie jest wabikiem).
   - **F3.5a — zrobione w 1.7.241:** histereza — dotychczasowy, wciąż widoczny cel zostaje, dopóki inny gracz nie jest bliżej niż 70% (`TARGET_SWITCH_RATIO`).
   - **F3.5b — zrobione w 1.7.246 (wymaga playtestu w kooperacji):** punkty celu = odległość × `_target_weight`: bot ×1,3, latarka ×0,8 (nie dla ślepca), strzelanie ×0,85,
     ranny (≤ 1 serce) ×0,9, odizolowany (nikt żywy w 150 px) ×0,9; histereza liczy punkty. „Hałasujący” = strzelający (`w_firing`); bieg i krzyk jeszcze nie wchodzą w wagę.
6. Ujednolicone, uczciwe zapowiedzi ataków (minimalny czas, przerwanie, brak darmowych trafień).
   - **F3.6a — zrobione w 1.7.244:** mocne ogłuszenie (`WINDUP_INTERRUPT_STUN` 0,4 s: strzelba, szyna, harpun, maczeta) przerywa zwykły cios w zapowiedzi (`_interrupt_windup`),
     przerwa 0,6 s × `enemy_cd`; poza zakresem zapowiedzi specjalne Wołka, krzyk Podsłuchacza, przemiana Mimika. Cios przez ścianę zablokowany w F0.
   - **F3.6b — zrobione w 1.7.246:** `MIN_WINDUP` 0,25 s (`windup_time`): zapowiedź zwykłego ciosu po trudności nie krótsza (Trzosek na trudnym: 0,22 → 0,25 s).
     **Zostaje:** ujednolicenie czasu zapowiedzi między rodzajami — dane po playtestach.
7. Dyrektor: kompozycja wędrowców z tabeli per misja, limit grup zamiast sztuk, uwzględnianie gorących miejsc.
   - **F3.7 — zrobione w 1.7.245:** `GROUPS` / `GROUPS_BY_MAP` / `pick_group` (zestawy jako dane, domyślnie jak dotąd), `MAX_GROUPS` 2 zamiast `MAX_ROAMERS` 3, `live_groups()`,
     sprzątanie uśpionych wędrowców po `ROAMER_IDLE_DESPAWN` 45 s poza polem widzenia (`_seen_or_close`), cel wędrowców = świeże gorące miejsce (`HOT_SPOT_R` 600 px,
     `HOT_SPOT_AGE` 90 s) albo pozycja gracza. **Zostaje:** kompozycja zależna od napięcia / czasu od starcia (więcej Ślepców przy długiej ciszy) i własne tabele
     per mapa — dane wypełnić po playtestach; test `_spawn_group` na prawdziwym grafie nawigacji (losowy punkt spawnu — niedeterministyczny w teście headless).

### Dodatek: Wołek i Ślepiec (1.7.248, na prośbę po playteście)

- **Wołek:** rzut skrzynią w górę i w dół (`THROW_DY_MAX` 160 px; cel prawie nad / pod nim też; `_throw_clear` sprawdza ścianę; dłuższy czas lotu dla rzutu pionowego).
  Szarża dalej tylko po poziomie (`|dy| ≤ 24`). Skrzynia musi leżeć w 60 px od niego (`_find_crate`) — bez skrzyni nie rzuca; do rozważenia: szukanie skrzyni w okolicy.
- **Ślepiec** (był „nieruchomą lalką"): `sweep` — po dojściu na ślad przeszukuje okolicę ±70 px przez `search` 6 s; `lunge` — szarża na głośny dźwięk (≥ 1,0 — po playteście obniżone z 2,0, bo domyślna M-83 nigdy nie dochodziła do 2,0)
  w 300 px (pierwotne 140 px po playteście okazało się za mało: gracz strzela z dalej, więc szarża praktycznie się nie odpalała): zapowiedź 0,3 s (stan `alert`), potem do 1,4 s × 2,4 prędkości w stronę źródła
  (z błędem), cooldown 6 s; nowy stan `Ai.LUNGE`, głos `alert`. Po playteście też twardszy: 100 HP (było 60), 2 obrażenia (było 1), `leap: true`. Wszystko w danych (`enemy_defs.gd`), więc strojenie bez kodu.
  **Do playtestu:** czy jest groźny, ale uczciwy; czy kroki (nie ≥ 2,0) dalej go tylko prowadzą do gracza.
- **Uskoki (po playteście: Ślepiec stał na wyspie za metalowym blokiem i na krawędzi szybu):** na krawędzi zejścia (`Nav.Edge.FALL`) wróg idzie dalej, aż straci grunt (wcześniej stawał 3 px od środka węzła, czyli na samej krawędzi). Ponadto wrogowie, którzy nie skaczą, pokonują stopień o 1 kafel małym przeskokiem (`_is_step`, `STEP_HOP_V`), a gdy nie mogą dojść do domu, po `RETURN_STUCK_TIME` 4 s dom przenosi się na miejsce postoju. **Zostaje otwarte:** Trzosek/Skoczek/Mimik nie mają flagi `_blocked` i skaczą o ścianę bez limitu — do decyzji po playteście.

### F4 — nowa zawartość

Kapłan, Rzeźnik, Żerca (GDD §7.2) dopiero po F2 — inaczej każdy dopisałby kolejne `if kind`.

## 5. Ryzyka

- F1 dotyka sieci (`_sync`) — trzeba przetestować hosta i klienta (`tools/test_weapons.sh` ma tryb sieciowy).
- F3 zmienia odczucie gry — wymaga playtestu; każdy punkt osobnym PR-em, żeby dało się cofnąć.
- Wartości z F0.4 (bufor hałasu) zmieniają, które strzały budzą wrogów — sprawdzić `--stalkertest` i `test_weapons.sh`.

### F3.8 — Podsłuchacz (1.7.249, na prośbę po analizie)

Analiza kodu wykazała: zapowiedź krzyku 0,9 s nie jest przerywana ogłuszeniem (celowo), brak sygnału „zauważył" w widoku, kierunek patrzenia liczony po stronie widoku (każdy peer: na własnego gracza), krzyk precyzyjny i natychmiastowy
dla całej okolicy, powtarzany co 6 s bez limitu. Zrobione (dane w `enemy_defs.gd`: `scream`, `shield`):

- **Pole ochronne** (−90%) przez 1,4 s od krzyku (zapowiedź zostaje podatna — kontra: zabić przed krzykiem); stan `Ai.SCREAM`, `view_info["shield"]`, tarcza w `view3d.gd` (`_sync_enemy_rings`), szary hitmarker, boty nie strzelają.
- **A — testy** (`_test_listener`): zapowiedź, pole (`take_hit`, `take_bullet`), fala, zasięg 2. krzyku, limit, uspokojenie, kierunek, klient.
- **B** — flaga `alert` na czas zapowiedzi/krzyku; kierunek patrzenia z serwera (`_listener_look`: cel > ślad > najbliższy gracz) i `_net_face` u klienta.
- **C** — ślad z `hear_error` rodzaju, fala przywołania (`answer_alarm`: 900 px/s + do 0,2 s rozrzutu).
- **D** — kolejne krzyki ×0,6 zasięgu, po 3 milknie (`calm` 12 s), zapowiedź ×1,3 gdy tylko usłyszał.
- Łańcuch Podsłuchaczy: odrzucone jako problem — na mapach 1.2/1.3 stoją ≥ 416 px od siebie, a słuch to 238 px (test pilnuje).
- Otwarte: czy limit 3 krzyków i pole 1,4 s są dobrze dobrane (playtest); klucz 3D „scream" pozostaje pozą zapowiedzi (osobna poza krzyku w modelu — F4/grafika).

### F3.9 — Głaz Wołka (zrobione w 1.7.250, wariant B „stłuczenie”)

**Cel:** Wołek bez skrzyni w pobliżu nie jest bezradny na dystans: rzuca **głazem**, który jest zawsze dostępny, zabiera **0,5 HP** i leci częściej na wyższej trudności.

**Reguły**
- Wybór pocisku w `_bruiser_tick` (stan 0, ta sama geometria co rzut skrzynią: `ax < 220`, `|dy| ≤ THROW_DY_MAX`, `_throw_clear`): `_find_crate()` jest → rzut skrzynią (jak dziś, cooldown `THROW_CD`); brak skrzyni w 60 px → głaz (własny `_boulder_cd`). Skrzynia ma pierwszeństwo, więc głaz nigdy jej nie zastępuje, gdy leży obok.
- Zapowiedź krótsza niż skrzyni (0,6 s zamiast 0,8 s, skalowana `enemy_windup`), lot 0,5–0,8 s, mały promień trafienia (8 px) — da się uniknąć kucnięciem, skokiem albo zejściem z linii.
- Hałas rzutu 2,0 (cichszy niż skrzynia 4,0); wróg nie rzuca, gdy ma cel w zwarciu (`ax ≤ 60` na tym samym poziomie → zwykły cios).

**Częstotliwość zależna od trudności** (osobna tabela w `enemy_defs.gd`, nie mnożnik `enemy_cd`, żeby dało się stroić każdy poziom): `"boulder": {"dmg": 0.5, "cd": [8.0, 5.0, 3.2], "windup": 0.6, "range": 220.0, "noise": 2.0}` — kolejno EASY / NORMAL / HARD (indeks `Difficulty.level`), do strojenia po playteście.
Maksymalny DPS przy braku uników: ≈ 0,06 / 0,10 / 0,16 HP/s — znacznie mniej niż szarża (2 obrażenia) i skrzynia (1 HP co 6 s), więc głaz jest dokuczliwy, a nie śmiertelny.

**Obrażenia 0,5 HP — decyzja potrzebna:** `Player.hp` to `int` (3 serca), `apply_hit(amount: int)` odrzuca `amount ≤ 0`, HUD rysuje całe serca.
- **A. Półserca w całej grze** (hp w połówkach): czysto, ale dotyka HUD, apteczek, perków, sieci, botów, zapisu i testów — osobny, duży PR.
- **B. Licznik „stłuczenia" (zalecane):** gracz trzyma ukryte 0,5; drugi głaz zamienia je w 1 realne obrażenie. HUD pokazuje popękane serce przy 0,5. Licznik zeruje się przy leczeniu, powaleniu i respawnie. Nowa metoda `deliver_chip(0.5, from, "boulder")` obok `deliver_hit`; niewrażliwość po trafieniu krótsza (0,3 s). Jeden plik gracza + HUD + test.

**Pocisk:** nowy lekki węzeł `boulder.gd` (serwer liczy łuk balistyczny, kolizja ze ścianą promieniem na warstwie 1 i z graczami `hurt_point < 8 px`, znika po trafieniu / uderzeniu / 2 s; pozycja replikowana jak pocisk). Nie reuse `prop.gd` — skrzynia to ciało fizyczne zostające na mapie, a głazy by się kumulowały. Model 3D: istniejący `rock` z `DECO_MODELS` (`view3d.gd`) obracający się w locie, pył przy uderzeniu.
**Ryzyko widoku:** poza rzutu (`sp == 3`) zakłada, że Wołek unosi skrzynię — dla głazu trzeba sprawdzić w `enemy3d.gd`, czy poza wygląda dobrze bez rekwizytu w rękach (ewentualnie podnosi „głaz z ziemi" tym samym ruchem).

**Kroki:** (1) `boulder.gd` + dane `boulder` w `enemy_defs.gd`; (2) wybór pocisku i `_boulder_cd` w `_bruiser_tick`; (3) `deliver_chip` + HUD popękanego serca (wariant B); (4) model 3D + dźwięk (rzut, uderzenie); (5) testy: skrzynia obok → skrzynia, brak → głaz, 2 głazy = 1 HP, cd per poziom (3 wartości), ściana blokuje, replikacja; (6) GDD (wiersz Wołka), CHANGELOG 1.7.250, README.

**Wdrożenie F3.9 (1.7.250):** `boulder.gd` (+ `Level.spawn_boulder`, pocisk po łuku liczony na każdym peerze jak kwas Pijawki), dane `boulder` w `enemy_defs.gd`, wybór pocisku w `_bruiser_tick`
(`_boulder_ready`, `_throw_boulder`, `Enemy.boulder_cooldown`), `Player.chip` + `deliver_chip` / `apply_chip` (replikowane), pęknięte serce w `hud.gd` (`Pips.cracked`), model skały w `view3d.gd`
(`_sync_boulders`). Nie zrobione: pęknięcie w plakietce nad głową postaci 3D (tylko HUD drużyny); osobny dźwięk rzutu i uderzenia (użyty `impact_hard`); pozę rzutu Wołka dalej daje
animacja zapowiedzi (nie ma osobnej pozy podnoszenia głazu).

### F3.10 — Dyrektor: kompozycja wg napięcia i czasu, własne tabele map (zrobione w 1.7.251)

**Dziś:** `Director.pick_group(table, roll)` losuje zestaw tylko z wag; jedna tabela `GROUPS` (60% 2 Trzoski, 25% 3 Trzoski, 15% Ślepiec), `GROUPS_BY_MAP` jest puste. Tabela nie widzi ani czasu, ani napięcia, więc w 20. minucie przychodzi to samo co w pierwszej, a na mapie z generatorami (głośnych) tak samo jak w ciszy.
Warunki wypuszczenia grupy się nie zmieniają: faza OBJECTIVE, poza kryjówką, stres ≤ 0,3, ≥ 35 s od ostatniego starcia, < 2 grupy, interwał 55–90 s × `dread`.

**Wejścia (`ctx`, liczone w `_spawn_group`):**
- `time` — `mission.elapsed` (s od startu misji; zerowany przy restarcie) × `Difficulty.m("dread")` (łatwy ×0,6 spowalnia eskalację, trudny ×1,5 przyspiesza — bez nowych kluczy trudności);
- `tension` — `Director.tension` = max(stres, Uwaga × 0,7). **Uwaga:** w chwili spawnu stres ≤ 0,3, więc napięcie to w praktyce Uwaga × 0,7 (0…0,7). Okna napięcia w tabelach trzeba więc ustawiać w 0…0,7, nie 0…1;
- `quiet` — `_since_enc` (jak długo drużyna ma spokój), do ewentualnego strojenia.

**Format tabeli (zgodny wstecz):** wpis `[waga, [rodzaje]]` zostaje; opcjonalny 3. element to słownik okien `{"time": [od, do], "tension": [od, do], "fade": 60.0}`.
Waga efektywna = waga × czynnik okna (1 w środku, liniowo do 0 na krawędzi w `fade` s / 0,1 napięcia — skład zmienia się płynnie, nie skokiem). Czysta funkcja `Director.entry_weight(entry, ctx)`,
`pick_group(table, roll, ctx := {})` (bez `ctx` działa jak dziś, więc stare testy zostają). Gdy wszystkie wagi wyjdą 0 → ostatni wpis tabeli (bezpiecznik).
Alternatywa odrzucona: „budżet zagrożenia” (punkty za rodzaj, losowe dobieranie) — płynniejszy, ale trudny do zaprojektowania i przetestowania, a zależy nam na ręcznie ułożonych, czytelnych zestawach.

**Proponowane tabele** (wagi startowe; do strojenia po playtestach). Wędrować mogą tylko ruchome rodzaje (Trzosek, Ślepiec, Wołek); Skoczek, Podsłuchacz, Ćma i Mimik odpadają (wiszą, stoją, latają, udają).

| Zestaw | Czas | Napięcie (Uwaga) | Uzasadnienie |
|---|---|---|---|
| 2 Trzoski | zawsze, mocniej < 8 min | zawsze | podstawa, jak dziś |
| 3 Trzoski | od 3 min | zawsze | pierwszy wzrost |
| 4 Trzoski | od 8 min | ≥ 0,2 | późna presja |
| Ślepiec | od 1,5 min | ≥ 0,2 (rośnie z hałasem) | kara za hałas: słyszy, więc przychodzi, gdy głośno |
| 2 Ślepce | od 6 min | ≥ 0,4 | głośna drużyna w późnej fazie |
| Wołek + Trzosek | od 6 min | ≥ 0,15 | tank na przełamanie, nigdy w pierwszych minutach |
| Wołek + 2 Trzoski | od 10 min | ≥ 0,3 | szczyt eskalacji |

Tabele map (`GROUPS_BY_MAP`):
- **1.1 Missing Patrol** (12 T, 3 W, 0 L; samouczek): bez Ślepca (mapa go nie ma — pierwszy raz w 1.2), Wołek dopiero po 8 min.
- **1.2 Radio Silence** (generatory, głośna; 5 L, 8 P): Ślepiec i 2 Ślepce mocniej wg Uwagi — misja z założenia hałaśliwa, a Dyrektor ma na to odpowiadać.
- **1.3 The Nest** (las i tunele; 16 T, 4 W, 3 L): domyślna z naciskiem na Trzoski i Wołka, mało Ślepców.
- B1 (boss) i kryjówka: bez zmian — Dyrektor tam nie działa.

**Co nie zmienia się:** interwał, limit grup, kleszcze (F3.4c), okno oddechu, kierunek marszu na gorące miejsce.
**Logi do strojenia:** linia `[DIRECTOR]` dopisze `ctx` i prawdopodobieństwa zestawu; zdarzenie sesji (`SessionLog.event("director_spawn", …)`) z czasem, napięciem i zestawem, żeby po playteście dało się zobaczyć, co faktycznie przychodziło.

**Kroki:** (1) `entry_weight` + `pick_group(…, ctx)` + `build_ctx()` w `director.gd`, domyślna `GROUPS` z oknami; (2) tabele `GROUPS_BY_MAP` dla 1.1–1.3; (3) log i zdarzenie sesji; (4) testy: okna i krawędzie `fade`; brak `ctx` = stary wynik (0,59 / 0,61 / 0,86); czas 0 nie losuje Wołka, 12 min tak; napięcie 0 nie losuje 2 Ślepców; skala `dread` przesuwa czas; każda tabela mapy ma niezerową sumę wag w siatce (czas × napięcie) i same ruchome rodzaje; (5) GDD §7/§13 (opis Dyrektora i składu grup), CHANGELOG 1.7.251, README.
**Ryzyka:** zmienia odczucie gry (kolejność i ciężar spotkań) — wymaga playtestu, wagi to dane; `mission.elapsed` liczy też czas w kryjówce, jeśli Dyrektor tam nie spawnuje, czas „ucieka” — do sprawdzenia, czy brać własny licznik `_run_t` tylko z fazy OBJECTIVE (zalecane).

**Wdrożenie F3.10 (1.7.251):** `director.gd`: `_run_t` (własny licznik fazy celu, decyzja 2), `build_ctx()`, `window_factor` / `entry_weight` / `group_odds` / `pick_group(…, ctx)`, nowe `GROUPS` z oknami i `GROUPS_BY_MAP` dla 1.1–1.3;
Wołek wędruje od 6 min (decyzja 1). Test integracyjny stawia grupę z kontekstem na punkcie siatki mapy. Dopisek do planu: napięcie w chwili spawnu to ≤ 0,7, więc najwyższy próg okna to 0,2 (Uwaga ≈ 29%).
Nie zrobione: strojenie po playtestach (tempo 3 / 6 / 10 min), osobne tabele zależne od liczby graczy.
