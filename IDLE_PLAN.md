# Wrogowie w spoczynku — plan

Status: **plan z 2026-11-15 (main 1.7.583, c233cc54).** Decyzje D1–D4 (§6) przyjęte 2026-11-15 — wszystkie warianty zalecane.
**I0 + I1 w 1.7.584** (`scripts/idle_life.gd`, SPEC `idle` w `enemy3d.gd`, test `tools/test_idle_life.gd`): przed zmianą dwa Ślepce w filmie
oddychały z korelacją 0,98, po zmianie −0,34; koszt pozy ok. +0,01 ms na śpiącego wroga w kadrze. A5 (głowa za hałasem) to etap I4.
**I2 w 1.7.585** (`enemy3d.gd: _sleep_pose`, SPEC `sleep_pose`, drzemka Trzoska w `_build_sit(low)`, stykówka `tools/shot_sleep3d.gd`):
Ślepiec i Rzeźnik kucają, Wołek zwija się na pięściach, Kapłan klęczy na obu kolanach, dwa na trzy Trzoski drzemią z łbem przy łapach;
śpiący sięga najwyżej 0,4–0,6 wysokości strefy trafień, kości mieszczą się w szerokości hitboxa, wstaje w ok. 0,25 s.
Odstępstwa od §5 B: pozy z kodu (IK z miar szkieletu), nie klipy UAL — klipy ludzkie nie pasują do proporcji potworów (§8), a poza z kodu
trzyma hitbox i podłogę; Podsłuchacz i Stalker stoją jak dotąd (twarz do ściany kłóci się z `_facing`, §4.2); Mimik stoi, bo zamaskowany
udaje żywego kolegę (GDD §7.1, `enemy_mimic.gd` zamienia mu sen na czuwanie — siedzący „gracz” by się zdradził); Rzeźnik bez rąbania
(ręce nad barkami = zapowiedź ciosu, §4.3; rąbanie przy zwłokach to scenka C3 w I5). Wariant przy ścianie nie wszedł — zostaje na I5 razem
ze scenkami (potrzebuje danych mapy w widoku).
Warstwy A i B zmieniają tylko obraz i dźwięk, więc nie czekają na playtest (GDD §16.0a). Warstwa C (przechadzki) zmienia symulację,
więc wchodzi dopiero po playteście.

## 1. Skąd to

Użytkownik zgłosił, że wrogowie, którzy czekają na gracza, stoją nienaturalnie bez ruchu. Poprosił o analizę i bardziej immersyjne
rozwiązanie podpatrzone w popularnych grach.

## 2. Stan obecny (z kodu)

- **Kto stoi:** prawie zawsze wróg **nieobudzony** (`active = false` → `Ai.SLEEP`, animacja `sleep`; `enemy.gd: _update_sprite`).
  Śpiący stanowią większość wrogów na mapie (na z1_m2 większość ze 100). Rzadziej obudzony bez celu: `RETURN` stoi w domu
  `HOME_SLEEP_TIME` = 1,2 s i znów zasypia; Podsłuchacz stoi z założenia (GDD §8, „stoi”).
- **Poza snu dwunożnych** (Ślepiec, Podsłuchacz, Stalker, Wołek, Kapłan, Rzeźnik; `enemy3d.gd: _biped_params("sleep")`): jedna stała poza —
  tułów pochylony o `sleep_lean` (14–27°), ręce opuszczone, kolana proste. Ruch to jedna sinusoida o okresie 2,4 s: ±2° pochylenia
  i 1 cm w pionie. Stykówka `tools/shot_enemy_clip3d.gd --anim=sleep` (4 klatki co ~0,6 s) — klatki praktycznie identyczne.
- **Synchronizacja:** zegar pozy `_t` zaczyna od 0 dla każdego wroga (`enemy3d.gd`, `var _t := 0.0`), a wszyscy powstają przy wczytaniu
  mapy — grupa oddycha w tej samej fazie, jak manekiny.
- **Kierunek i głowa:** kierunek ciała zamrożony (ostatni ruch albo kierunek z serwera), głowa sztywno w osi tułowia. Brak dźwięku snu.
- **Trzosek:** sen i czekanie to ta sama poza siadu (`_build_sit`), różni je tylko przygaszenie oczu.
- **Przygaszenie:** śpiący ma `modulate` 0,8 (`enemy.gd`), w 3D ciemniejszy materiał.
- **Nieużyte klipy CC0, które już mamy** (`art_src/animations/`):
  - UAL2: `Zombie_Idle_Loop`, `TreeChopping_Loop`, `Idle_No_Loop`, `Consume`;
  - UAL1: `Crouch_Idle_Loop`, `Sitting_Idle_Loop`, `Sitting_Enter` / `Sitting_Exit`, `Fixing_Kneeling` (użyty przy reanimacji graczy),
    `Spell_Simple_Idle_Loop`;
  - wilk Quaterniusa: `Idle_2`, `Idle_2_HeadLow`, `Eating`;
  - wstawanie `LayToIdle` (UAL2, użyty po reanimacji graczy).

### 2.1 Problemy

| # | Problem | Skutek |
|---|---|---|
| P1 | Jedna poza + jedna sinusoida | Wróg wygląda jak manekin, nie jak istota, która śpi albo czeka |
| P2 | Wspólna faza oddechu | Grupa kołysze się równo — od razu widać, że to animacja |
| P3 | Sen = stanie | Gracz nie odróżnia sylwetką śpiącego od czuwającego; to ważne, bo maczeta zabija śpiącego od razu (GDD §8) |
| P4 | Cisza śpiących | Latarka budzi, więc w ciemności śpiącego nie da się namierzyć niczym poza wzrokiem |
| P5 | Brak reakcji na bodźce poniżej progu | Gracz nie dostaje sygnału „prawie mnie usłyszał” — skradanie jest zero-jedynkowe |
| P6 | Brak scenek | Śpiący nic nie mówią o świecie (co tu robili, co jedzą, czego pilnują) |

## 3. Inspiracje

| Gra | Mechanika | U nas |
|---|---|---|
| The Last of Us (I i II) | Zarażeni nigdy nie stoją nieruchomo: tiki głowy, kołysanie w kątach, szloch; klikanie klikaczy niesie ich stan | Tiki według rodzaju (A4), dźwięk snu (C1) |
| Left 4 Dead | Zarażeni w spoczynku siedzą, opierają się o ściany, wymiotują; Witch siedzi i płacze — „nie przeszkadzaj” słychać z daleka | Pozy przy ścianie (B), dźwięk jako ostrzeżenie (C1) |
| Days Gone, Dying Light 2 | Śpiący leżą w gniazdach albo stoją zahibernowani; sylwetka snu inna niż czuwania, przebudzenie to efektowne wstanie | Poza snu według rodzaju i wstawanie (B) |
| Resident Evil 4 | Ganados pracują (rąbią, noszą), dopóki cię nie zobaczą; czynność przypisana do miejsca | Rzeźnik przy zwłokach, Kapłan na modlitwie (B), scenki ze znaczników (C3) |
| Hunt: Showdown, S.T.A.L.K.E.R., Metro | Żerowanie na zwłokach; stado odpoczywa, jeden czuwa | Wataha: leżą, jeden węszy, jeden żre (B) |
| Hollow Knight | Część wrogów chodzi w kółko na krótkim odcinku | Krótkie przechadzki (C2) |
| Hitman, Skin Deep, FFXV | Zadania w spoczynku, „interesujące miejsca” / smart objects; w spoczynku wzrok bardziej wyrozumiały | Scenki ze znaczników (C3); głowa nasłuchuje bez zmiany reguł (A5) |
| Technika z dużych produkcji (np. Idle Weaver) | Spoczynek z warstw: oddech, przenoszenie ciężaru, obrót głowy ku bodźcowi, losowe tiki; każdy osobnik ma własny rytm | Warstwa A |

Źródła: wykład Naughty Dog o zachowaniach w spoczynku w TLOU Part II (GDC 2021), wpis „Skin Deep: Enemy Brains” (Blendo Games, 2025),
smart objects w FFXV (Game Developer), Idle Weaver (forum Unreal Engine), „The deceptively complex art of just standing around” (GamesRadar).
Pozostałe przykłady z własnej znajomości gier.

## 4. Zasady (twarde)

1. **Czytelność stanu:** śpi — niska, oparta albo zwinięta sylwetka, przygaszone oczy, dźwięk snu; czuwa — wyprostowany, głowa w ruchu,
   jasne oczy; zauważył — obecna reakcja `alert` (oczy żarzą się, obrót ku źródłu).
2. **Ciało pokazuje prawdziwy kierunek** z symulacji (`_facing`, `_is_behind` przy ciosie w plecy). Obracać wolno się tylko głowie.
3. **Tik nie wygląda jak zapowiedź ciosu:** żadna ręka powyżej barków, żadnego pulsowania oczu.
4. **Poza mieści się w hitboxie** (prostokąt z symulacji 2D) albo hitbox zmienia się na serwerze razem z nią (D1); pilnuje tego
   `tools/test_proportions.gd`.
5. **Bez sieci w warstwach A i B:** wszystko liczone w widoku z ziarna egzemplarza (nazwa węzła) i czasu gry, więc każdy klient widzi to samo.
6. **Koszt:** śpiący daleko już mają rzadszy tik wyglądu (`_asleep_far`); nowe warstwy nie mogą tego psuć. Pomiar `--perf` przed i po.

## 5. Propozycja

### Warstwa A — żywe ciało (sam widok, wszystkie rodzaje)

- **A1** Faza zegara i okres oddechu (±15%) z ziarna egzemplarza — koniec wspólnej fazy.
- **A2** Oddech w klatce i barkach (`Spine2`, ramiona), nie w całym tułowiu; wdech krótszy niż wydech.
- **A3** Przenoszenie ciężaru z nogi na nogę co 4–9 s (`sway` + odciążona noga).
- **A4** Tiki według rodzaju z losowego harmonogramu z ziarna: szarpnięcie głowy, drgnięcie palców, przechylenie, otrząśnięcie.
- **A5** Głowa podąża za hałasem poniżej progu przebudzenia (obrót do ~70°, ciało stoi) — sygnał „prawie mnie usłyszał”.
  Do sprawdzenia: czy klient zna hałasy poniżej progu (inaczej lekki znacznik w `_sync`).

### Warstwa B — sen wygląda jak sen (poza według rodzaju + wstawanie)

| Rodzaj | Sen | Źródło ruchu |
|---|---|---|
| Ślepiec | Kuca skulony, kiwa się, głowa przechylona jak przy nasłuchu | `Crouch_Idle_Loop` + warstwa A |
| Podsłuchacz | Stoi (GDD), ale twarzą do ściany, rytmiczne drgania | `Zombie_Idle_Loop` + tiki |
| Wołek | Siedzi ciężko albo podpiera się pięściami, sapie | Poza z kodu (krótkie nogi — klipy ludzkie nie pasują) |
| Rzeźnik | „Pracuje” tasakiem przy zwłokach | `TreeChopping_Loop` |
| Kapłan | Klęczy i modli się, szepcze | `Fixing_Kneeling` / `Spell_Simple_Idle_Loop` |
| Stalker | Bez zmian w B (skryptowany, budzi go Uwaga), tylko warstwa A | — |
| Trzosek | Wataha zwinięta w niskim siadzie (D1: w obecnym prostokącie); jeden siedzi i węszy, czasem jeden żre | `Idle_2_HeadLow`, `Eating`, poza zwinięta z kodu |
| Mimik | Spoczywa jak żołnierz (siedzi oparty), wzmacnia przynętę | `Sitting_Idle_Loop` |
| Skoczek, Żerca, Ćma | Bez zmian (wiszą / są ukryci) | — |

- **Wariant z otoczenia:** ściana w zasięgu kafla → oparcie; inaczej poza wolnostojąca. Wybór z ziarna, więc stały między sesjami.
- **Wstawanie** w czasie istniejącej reakcji `alert` (Trzosek 0,4 s, Kapłan 0,5 s). Rodzaje bez `alert` (Ślepiec ma zapowiedź skoku 0,3 s):
  szybkie przejście ≤ 0,25 s, żeby nie zmieniać balansu.

### Warstwa C — dźwięk, przechadzki, scenki

- **C1** Dźwięk snu: sapanie, chrapanie, mamrotanie, żucie, w małym promieniu i przestrzennie, z rozjechanymi odstępami. Latarka budzi,
  więc to główny sposób, żeby namierzyć śpiącego w ciemności. Synteza czy nagrania — D3.
- **C2** Krótkie przechadzki 10–20% śpiących (1–3 m, powoli, powrót). Zmienia symulację: LOD śpiących (`_asleep_far_ok` wymaga
  zerowej prędkości), okna ciosu w plecy, ustawione trasy cichego przejścia (np. przepust pod watahą w 1.2) — wyłączone tam znacznikiem.
- **C3** Scenki ze znaczników map (zwłoki z Rzeźnikiem, padlina z watahą, ołtarz z Kapłanem) jako rekwizyt + poza.

## 6. Decyzje

| # | Pytanie | Warianty | Przyjęte 2026-11-15 |
|---|---|---|---|
| D1 | Niska sylwetka snu a hitbox | a) pozy tylko w obecnym prostokącie (kucanie, oparcie, klęczenie); b) serwer obniża hitbox śpiącego | **a)** — bez zmian na serwerze; leżenie Trzosków (b) dopiero, gdy okaże się potrzebne |
| D2 | Przechadzki w symulacji | a) tak, po playteście (C2); b) nie, tylko widok | **a)** — 10–20% śpiących, wyłączone na trasach cichego przejścia, etap I5 |
| D3 | Dźwięk snu | a) synteza w `bake_sfx.py`; b) nagrania w `audio_licensed/`; c) najpierw synteza, potem odsłuch A/B | **c)** |
| D4 | Głowa nasłuchuje (A5) | a) tak, dla wszystkich; b) tylko Ślepiec i Podsłuchacz (słuchacze) | **a)** |

Skutki dla etapów: w I2 pozy Trzosków to zwinięty siad / przysiad w obecnym prostokącie (nie leżenie płasko), poza Wołka i Kapłana
sprawdzana w `test_proportions.gd`; I3 zaczyna od syntezy, odsłuch A/B z nagraniami przed podmianą.

## 7. Etapy

| Etap | Zakres | Sprawdzenie |
|---|---|---|
| I0 | Film referencyjny „przed”: `shot_enemy_clip3d.gd --movie` dla `sleep` i `idle` wszystkich rodzajów | Klatki w `shots_idle/before` |
| I1 | Warstwa A (A1–A4) | Film „po”; test: różne fazy dla dwóch egzemplarzy, ten sam wynik z tego samego ziarna; `test_proportions.gd`; `--perf` bez regresji |
| I2 | Warstwa B: pozy snu, klipy przez `prep_anim3d.py` / `retarget_quad.py`, wariant przy ścianie, wstawanie | Stykówki według rodzaju do akceptacji przed włączeniem; `--enemytest`; zrzut kierunku ciała kontra `_facing` |
| I3 | Dźwięk snu (C1) | Odsłuch; `test_audio_loops.gd`; klucze w banku |
| I4 | Głowa nasłuchuje (A5) | Test: hałas poniżej progu obraca głowę, nie ciało, i nie budzi |
| I5 | Przechadzki i scenki (C2, C3) — po playteście | `--maptest`, `--enemytest`, trasy cichego przejścia bez zmian |

## 8. Ryzyka

- **Klipy ludzkie na potworach:** proporcje Wołka i Rzeźnika już wcześniej odrzucały klipy (krótkie nogi) — każdą pozę oceniać na stykówce.
- **Czytelność kontra immersja:** zbyt żywy śpiący może wyglądać na czuwającego — zasada 1 z §4 ma pierwszeństwo.
- **Hitbox:** zob. D1.
- **Koszt:** dodatkowe drzewa klipów u kilkudziesięciu śpiących; mierzyć na z1_m2 (najwięcej wrogów).
