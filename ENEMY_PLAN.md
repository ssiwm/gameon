# Plan: porządki w logice wrogów pod widok 3D i mądrzejsza AI

Status: **plan z 2026-10-16; F0 zrobiona (1.7.234), F1a zrobiona (1.7.235, gałąź `feat/enemy-view-contract`), zostają F1b–F4.** Oparty na przeglądzie kodu (`enemy.gd`, `enemy3d.gd`, `boss.gd`, `leech.gd`,
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
- **F1b — do zrobienia:** `_facing` (backstab, ucieczka w panice) przenieść z `_update_sprite` do symulacji serwera, żeby nie zależało od warstwy
  prezentacji; `view_info` rozszerzyć o `facing`, gdy klient ma go potrzebować.
- **F1c — opcjonalnie, dopiero gdy będzie powód:** zastąpić zegar `AnimatedSprite2D` własnym (`EnemyView`). Wymaga przepisania logiki jednorazowych
  animacji Pijawki (`_set_anim`, `_anim_start`) i koloru-kanału tintu (uśpiony ×0,8, przezroczystość Stalkera) — ryzyko większe niż zysk, dopóki
  nic nowego tego nie wymaga.

### F2 — dane i moduły, ok. tygodnia

- `EnemyDef` (Resource) per rodzaj: statystyki, zmysły, dropy, głosy, XP, model 3D; `hurt_h` wyliczane z modelu.
- `BossBase`: wspólne `_humans()`, `hp_for`, fazy, miniony przez RPC, zdarzenia, `reset`.
- Podział `enemy.gd` na zmysły, mózg (maszyna stanów) i zachowania (wataha, szarża, zasadzka, nasłuch, ćma, mimik).

### F3 — inteligencja, 2–3 tygodnie etapami (kolejność wg wpływu na rozgrywkę)

1. Jawna maszyna stanów z czytelnym „zauważył”: sen → alarm (0,3–0,8 s, odwrócenie, rozżarzone oczy) → pościg / śledztwo → atak → odpoczynek → szukanie → powrót.
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
