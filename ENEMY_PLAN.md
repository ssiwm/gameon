# Plan: porządki w logice wrogów pod widok 3D i mądrzejsza AI

Status: **plan z 2026-10-16; F0 zrobiona (1.7.234), F1a zrobiona (1.7.235), F1b zrobiona (1.7.236), F2a zrobiona (1.7.237), F2b zrobiona (1.7.238), F3.1a zrobiona (1.7.239, gałąź `feat/enemy-ai-states`), zostają F2c, F3.1b–F3.7, F4.** Oparty na przeglądzie kodu (`enemy.gd`, `enemy3d.gd`, `boss.gd`, `leech.gd`,
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
   - **F3.1b — do zrobienia (zmienia grę, wymaga playtestu):** stan `alert` — gdy wróg po raz pierwszy zauważa gracza albo budzi się od hałasu, staje na 0,3–0,8 s
     (odwraca się, oczy rozżarzone, dźwięk), zanim ruszy; potem dopiero chase. Zacząć od jednego rodzaju (Trzosek), parametr w `enemy_defs.gd` (`alert`).
   - **F3.1c — po F3.1b:** przestawić gałęzie `_tick_server` tak, żeby decyzje wynikały ze stanu (`match _ai`), razem z podziałem `enemy.gd` (F2c).
2. Lokalizacja hałasu z niedokładnością (im dalej i ciszej, tym większy błąd); ślepiec „sprawdza okolicę”.
3. Odległość dźwięku jednym przebiegiem od źródła hałasu (zamiast A* na każdego wroga); wspólne z `sound_grid.gd`.
4. Współdzielona wiedza grupy z opóźnieniem; role w watasze; flankowanie trasą alternatywną po nawigacji.
5. Wybór celu z pamięcią i histerezą (świecący, hałasujący, odizolowany, ranny; bot nie jest wabikiem).
6. Ujednolicone, uczciwe zapowiedzi ataków (minimalny czas, przerwanie, brak darmowych trafień).
7. Dyrektor: kompozycja wędrowców z tabeli per misja, limit grup zamiast sztuk, uwzględnianie gorących miejsc.

### F4 — nowa zawartość

Kapłan, Rzeźnik, Żerca (GDD §7.2) dopiero po F2 — inaczej każdy dopisałby kolejne `if kind`.

## 5. Ryzyka

- F1 dotyka sieci (`_sync`) — trzeba przetestować hosta i klienta (`tools/test_weapons.sh` ma tryb sieciowy).
- F3 zmienia odczucie gry — wymaga playtestu; każdy punkt osobnym PR-em, żeby dało się cofnąć.
- Wartości z F0.4 (bufor hałasu) zmieniają, które strzały budzą wrogów — sprawdzić `--stalkertest` i `test_weapons.sh`.
