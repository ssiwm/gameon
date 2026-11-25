# Łupacz — plan zagrożenia

Status: **plan z 2026-11-25 (main 1.7.685, cd81e4ae); decyzje D1–D8 (§6) przyjęte w wariantach zalecanych.** Wdrożone: L0 (1.7.686, #816),
L1 (1.7.687, #817), L2 (1.7.688, #818), po playteście L3 (1.7.689, #820) i L4 (1.7.690). Zostaje L5 — strojenie na dziennikach.

Łupacz po #810–#814 ma skorupę, model, lampę, zanurzanie, markę lampową i własne dźwięki, ale w grze nadal jest „nieporadnym, bezbronnym
stworzeniem” (uwaga użytkownika po teście 1.7.685). Plan daje mu trzy zdolności, z których każda zamienia kopalnię w zagrożenie:
**chwyt spod ziemi** (L2), **podkop stropu** (L3) i **pancerną kulę** (L4) — na wspólnym fundamencie: tempo i zmysł drgań (L1).

## 1. Skąd to

- Analiza Łupacza 2026-11-25 (wątek „ile dźwięków przy zakończeniu misji”): punkt 1 „czuje drgania gruntu, nie słyszy powietrza” —
  niewdrożony; punkt 4 „zawał zasypuje go i ogłusza” — wdrożony inaczej (zawał zabija).
- Propozycje 1–3 z 2026-11-25: „wciąga w skałę”, „podkopuje strop”, „pancerna kula”; użytkownik wybrał wszystkie trzy.

## 2. Stan obecny

### 2.1 Mechanika (z kodu, `enemy_defs.gd`, `enemy_mole.gd`)

| Cecha | Łupacz | Dla porównania |
|---|---|---|
| Prędkość | **16 px/s** | gracz 95, kucając 45; Wołek 36; Ślepiec 70 |
| HP | 72 + 3 płyty × 60 | Wołek 140, Ślepiec 100 |
| Cios | 2 serca z 3, zapowiedź 0,79 s, zasięg 13 px, przerwa 1,55 s | — |
| Zmysły | słuch 220 px (każdy hałas), wzrok 62 px | — |
| Wynurzenie (K3, K3d) | wychodzi z kieszeni obok gracza i dopiero zaczyna gonić | nie jest atakiem |

Wniosek: cios jest groźny (2 z 3 serc), ale prawie nigdy nie trafia — gracz odchodzi od niego nawet kucając, a wynurzenie daje 1,2 s
drapania i 2 s wychodzenia z kieszeni, w których Łupacz jest celem, nie zagrożeniem.

### 2.2 Dziennik sesji 2026-11-25 19:48 (1.7.685, z1_m1, solo, NORMAL)

- 319 s: drapanie (20 ciosów), 337 s warczenie, 342 s Łupacz wychodzi.
- 359,0 s: kula rozbija płytę karku; 359,4 s `mole_under` z `why: hurt`, **HP 18/72** — w 17 s stracił 54 HP i jedną płytę.
- 360,7 s: marka lampowa nr 214 podniesiona.
- 375–438 s: gracz kopie dalej w tej samej strefie (DigZone1, 4 znajdźki, 2 stemple) — **Łupacz nie wraca**.
- Koniec misji: wśród zabitych nie ma Łupacza (`kinds`: ćma 80, trzosek 24, skoczek 7, wołek 4, kapłan 1), gracz bez obrażeń od niego.

Zanurzenie miało go wynurzyć przy graczu po 2,5 s (`_tick_under` → `_rise_target`). Dziennik nie ma zdarzeń wynurzenia, więc nie wiadomo,
czy nie wyszedł w ogóle, czy wyszedł i utknął. To pierwszy punkt L0.

### 2.3 Na czym budujemy (istnieje w kodzie)

- **Chwyt z przypięciem:** `player.grabbed` / `deliver_grab` / `apply_grab` (Pijawka, Mimik M6): przypięty strzela i bije, nie chodzi;
  Mimik puszcza po ciosie wręcz chwyconego, ogłuszeniu ≥ 0,4 s albo `GRAB_FREE_DMG` od innych. Replikowane, w `test_net_session.sh`.
- **Zanurzenie:** `SP_UNDER` / `SP_RISE`, ukrycie i nietrafialność (`is_hidden`), `DigZone.open_pocket`, `wake_spot`, drapanie `claw_scrape`.
- **Zawał stropu D5:** `dig_zone.gd` — `unstable_spans`, ostrzeżenia `warns` z czasem materiału, `_collapse` (łuk w żwir, gracz −1 serce
  i na wierzch z ogłuszeniem, wrogowie `COLLAPSE_CRUSH`), stemple `place_prop` / `_prop_at` blokują przęsło.
- **Szarża:** `enemy_bruiser.gd` (Wołek) — `_run_clear` (rozbieg bez ściany i przepaści), `charge_through` (barykady), `_crash` + `CRASH_STUN`.
- **Hałas z tagiem:** `NoiseMgr.add_noise(amount, pos, tag)` i sygnał `noise_added` (serwer). Tagi gruntu już są: `run`, `dig`, `prop`,
  `explosive`, `n_break`, `handcar`; lądowanie nie emituje nic.

## 3. Zasady kierunku

1. **Groźny z zasadzki, nie z pościgu.** Łupacz zostaje wolny na powierzchni; niebezpieczny jest pod ziemią i w chwili wyjścia. Gracz boi się
   gruntu pod nogami, a nie biegnącego kreta.
2. **Każda zdolność ma zapowiedź ≥ 0,8 s, którą da się rozpoznać uchem w ciemności** — trzy różne dźwięki: drapanie pod stopami (chwyt),
   trzeszczenie stropu (podkop), skrzypienie płyt (kula). Gracz, który słucha, zawsze ma szansę.
3. **Każda kontra pochodzi z kopalni:** kucnij i przestań kopać, postaw stempel, stań na deskach, wejdź we wnękę, kilof w odsłonięty łeb.
4. **Jedna zdolność na wynurzenie.** Nigdy dwie naraz; wybór wynika z położenia gracza (§4.0), więc da się go przewidzieć.
5. **Sieć: wszystko rozstrzyga serwer** (chwyt, zawał, trafienie kulą); klient tylko rysuje i gra dźwięk.

## 4. Etapy

### 4.0 Wybór zdolności (wspólny dla L2–L4)

| Gdzie jest cel (najsilniejsze drgania w strefie) | Łupacz pod ziemią | Łupacz na powierzchni |
|---|---|---|
| na gruncie strefy (ziemia, żwir, skała), bez stropu nad głową | **chwyt** (L2) | zwykły pościg |
| w wykopie albo chodniku pod przęsłem bez stempla (`roof_over`) | **podkop** (L3), co drugi raz chwyt | zwykły pościg |
| na deskach, pomoście, betonie, blasze | wynurza się obok (jak dziś) | — |
| na tym samym poziomie, 48–200 px, prosty rozbieg | — | **kula** (L4), gdy ≥ 2 płyty całe |

### L0 — pomiar i naprawa wynurzenia (dziennik + poprawka)

- Dziennik sesji: `mole_rise` (cel, miejsce, czas pod ziemią), `mole_emerge`, `mole_hit` (komu, ile, czym: cios / chwyt / zawał / kula),
  `mole_stuck` (≥ 3 s bez postępu po wyjściu), `mole_death` (czym, ile płyt). W `mission_end` licznik `kinds` dostaje `lupacz`.
- Odtworzenie przypadku z §2.2 w `--digtest` (`--digonly=resurface`): zanurzenie z `hurt` przy HP 25%, gracz kopie w tej samej strefie
  20 px obok → Łupacz wychodzi w ≤ 4 s i dochodzi do gracza. Naprawa przyczyny, którą pokaże test.
- **Wyjście:** każde spotkanie z Łupaczem da się odczytać z dziennika; zanurzony zawsze wraca, gdy ktoś kopie w strefie.

### L1 — tempo i zmysł drgań (symulacja)

- Prędkość 16 → **30 px/s** (nadal poniżej Wołka); w pierwszej sekundzie po wyjściu z kieszeni **zryw 70 px/s** — wyjście przestaje być
  darmowym oknem na ostrzał.
- **Zmysł drgań** zamiast zwykłego słuchu (D1):
  - Nowe `NoiseMgr.tremor(pos, strength, tag)` — serwer, **bez Uwagi** (nie zmienia innych wrogów ani muzyki). Woła je `add_noise` dla tagów
    gruntu (`run`, `dig`, `prop`, `explosive`, `n_break`, `handcar`) oraz nowe lądowanie gracza po spadku ≥ 24 px (`land`).
  - Łupacz słyszy tylko drgania (zasięg 260 px, przez skałę, bez drogi dźwięku). Strzały, krzyk, radio, przeładowanie — tylko do 40 px.
  - Wzrok 62 px zostaje, ale **gracz kucający i nieruchomy ≥ 0,5 s jest niewidoczny** poza 20 px (D2).
- Kodeks: wskazówka „Crouch and stop digging — it feels the ground, not the air.” / „Kucnij i przestań kopać — czuje grunt, nie powietrze.”
- Test `--digtest` (`--digonly=tremor`): bieg i kopanie budzą i prowadzą; strzał z 100 px nie; kucający nieruchomy znika z celu;
  lądowanie z wysoka daje drganie; tremor nie zmienia Uwagi.
- **Wyjście:** decyzja „przestań kopać i kucnij” działa i jest jedyną skuteczną ucieczką przed zanurzonym Łupaczem.

### L2 — chwyt spod ziemi (symulacja + obraz + dźwięk)

- **Kiedy:** zanurzony, po `SUB_TIME`, cel na gruncie strefy (materiał pod stopami z `material_at_px` ≠ powietrze, nie deski ani beton),
  ≥ 30 px od ostatniego chwytu. Najwyżej jeden chwyt na zanurzenie.
- **Zapowiedź 1,0 s** (EASY 1,4 / HARD 0,9 / ELITE 0,8): miejsce zablokowane w chwili zapowiedzi (stopy celu). Pęknięcia gruntu i pył pod
  butami w 3D, dźwięk `claw_scrape` przy stopach (panorama), lekkie drżenie kamery tylko u celu, napis „[Ziemia pęka pod stopami]”.
  Ucieczka: ≥ 14 px od miejsca albo skok — wtedy Łupacz wychodzi w pustą kieszeń, chwieje się 1,2 s z odsłoniętym łbem (obrażenia ×1,5).
- **Chwyt:** `deliver_grab(true)` — gracz przypięty (strzela i bije, nie chodzi), model zapada się w grunt 0 → 0,35 m przez czas chwytu.
  Obrażenia **1 serce na początku i 1 po 3 s** (× trudność); chwyt trwa najwyżej 3 s, potem puszcza i wraca pod ziemię (D3).
- **Uwolnienie:** cios wręcz chwyconego (2 ciosy maczetą albo 1 kilofem), ogłuszenie ≥ 0,4 s, 20 obrażeń od innych (kolega, bot) w łeb
  nad gruntem (strefa trafień tylko łba, płyty pod ziemią). Puszczony Łupacz wychodzi do połowy i chwieje się 1,0 s — okno na kontrę.
- **Widok:** Łupacz wynurzony do łopatek (przesunięcie modelu w dół), klip `grab` (przednie łapy obejmują nogę, ryj-gwiazda w górę),
  po puszczeniu `emerge` z połowy. Gracz: poza `grabbed` z nogą w gruncie (char3d.gd), żwir wokół kostek.
- **Dźwięk:** `mole_grab` (chrupnięcie gruntu + mokre złapanie, synteza i wersja z nagrań do odsłuchu A/B), `lupacz_squeal` przy puszczeniu.
- **Bot:** strzela w łeb jak przy chwycie Mimika; bot nie jest celem chwytu (D4).
- Testy: `--digtest` (`--digonly=grab`) — zapowiedź i ucieczka, chwyt i obrażenia, uwolnienie każdą drogą, deski chronią, raz na zanurzenie;
  `test_net_session.sh` — chwyt u klienta i dołączającego.
- **Wyjście:** stanie w miejscu albo kopanie w strefie z zanurzonym Łupaczem kosztuje serce, ale zawsze da się przed tym uciec.

### L3 — podkop stropu (symulacja + obraz + dźwięk)

- **Kiedy:** zanurzony, cel pod przęsłem w strefie (`roof_over(feet)`), przęsło ≥ 2 kafle szerokie, bez stempla. Raz na 30 s na strefę.
- **Gdzie:** przęsło nad celem albo **za nim, między nim a wejściem strefy** (odcięcie) — losowo 50/50, odcięcie tylko gdy cel ma kilof
  (każdy ma od B1) i żwir da się przekopać (D5).
- **API:** `DigZone.force_warn(feet, by)` — wpis do `warns` także dla stabilnego przęsła, czas ostrzeżenia `max(materiał, 1,5 s)`; odmowa,
  gdy przęsło ma stempel. Zawał przez istniejące `_collapse` (gruz, −1 serce, gracz na wierzch z ogłuszeniem) — bez nowych reguł obrażeń.
- **Zapowiedź:** to samo trzeszczenie i pył co ostrzeżenie D5 + drapanie w stropie (dźwięk z góry). Kontra: wybiec spod przęsła albo
  postawić stempel (2,5 s — zdąży tylko ktoś, kto już go klinuje albo ma kolegę).
- **Łupacz a zawał:** sam nie stoi pod przęsłem (jest w skale), więc go nie przygniata. Osobno, zgodnie z planem pancerza: zawał, który
  przygniata Łupacza na powierzchni, **zrywa płytę i ogłusza 2 s zamiast zabijać** (D6).
- Testy: `--digtest` (`--digonly=undermine`) — podkop nad celem i za nim, stempel blokuje, gracz wychodzi spod gruzu, odcięcie da się
  przekopać, limit 30 s; zawał na Łupaczu zrywa płytę.
- **Wyjście:** chodnik wykopany przez gracza staje się pułapką, a stemple — realną obroną.

### L4 — pancerna kula (symulacja + obraz + dźwięk)

- **Kiedy:** na powierzchni, cel na tym samym poziomie (±10 px), 48–200 px, rozbieg czysty (`_run_clear` z Wołka), ≥ 2 płyty całe
  (rozbita skorupa nie zwija się — nagroda za wcześniejsze rozbijanie). Przerwa 8 s.
- **Zapowiedź 0,6 s:** zwija się (klip `curl`), skrzypienie płyt `shell_curl`.
- **Toczenie:** 180 px/s, najwyżej 1,4 s, na wprost. W tym czasie każda kula w płytę (×0,15), brzucha nie ma. Rozbija deski i skrzynie
  (`charge_through`). Trafiony gracz: **1 serce + odrzut 140 px/s + ogłuszenie 0,5 s**. Przeskok i wnęka to unik.
- **Koniec:** ściana albo próg > 9 px → `_crash`: leży na grzbiecie **2,0 s z odsłoniętym brzuchem** (całe ciało ×1,5, płyty nie chronią).
  Przepaść → spada i kończy toczenie bez ogłuszenia.
- **Widok:** poza kuli z klipu `curl` + obrót całego modelu wokół osi poprzecznej wg przebytej drogi (bez fizyki 3D); klip `belly_up` po
  zderzeniu. Iskry z płyt o skałę co 0,15 s.
- **Dźwięk:** `shell_curl`, pętla `shell_roll_loop` (toczenie płyt po żwirze; synteza + nagranie do odsłuchu), zderzenie = `shell_crack`
  ciszej.
- Testy: `--enemytest` — warunki szarży (poziom, rozbieg, płyty), obrażenia i odrzut, deski, zderzenie i okno brzucha, przepaść; `test_net_session.sh`.
- **Wyjście:** na powierzchni Łupacz ma ruch, przed którym trzeba uskoczyć, a jego skorupa ma drugie zastosowanie.

### L5 — strojenie (po playteście)

Na dziennikach z L0: obrażenia od Łupacza na spotkanie, ile chwytów z ucieczką, ile podkopów zablokowanych stemplem, czas walki, śmierci
graczy. Cel w §7.

## 5. Kolejność i PR-y

| PR | Etap | Zależy od | Koszt |
|---|---|---|---|
| 1 | L0 pomiar + naprawa wynurzenia | — | mały |
| 2 | L1 tempo i zmysł drgań | L0 | mały |
| 3 | L2 chwyt spod ziemi | L1 | średni (klip `grab`, poza gracza, dźwięk) |
| — | **playtest** 1.1 i 1.2, decyzja o dalszych krokach | L2 | — |
| 4 | L3 podkop + zawał zrywa płytę | L1 | mały do średniego |
| 5 | L4 pancerna kula | L1 | duży (klipy `curl`, `belly_up`, toczenie, dźwięki) |
| 6 | L5 strojenie | L2–L4 | mały |

## 6. Decyzje

| | Pytanie | Zalecane | Inne |
|---|---|---|---|
| D1 | Czym słyszy | **tylko drgania gruntu** (strzał z bliska do 40 px) | drgania + zwykły słuch ze stratą zasięgu |
| D2 | Kucający nieruchomy | **niewidoczny poza 20 px** po 0,5 s | niewidoczny zawsze / tylko spowolnione wykrycie |
| D3 | Chwyt | **2 serca w 3 s, puszcza sam** | wciąga do powalenia (za ostre w solo) |
| D4 | Czy chwyta bota | **nie** (bot nie czuje strachu, nie ma kontry) | tak |
| D5 | Odcięcie drogi podkopem | **tak, 50%, tylko gdy żwir do przekopania** | tylko nad celem |
| D6 | Zawał na Łupaczu | **zrywa płytę i ogłusza 2 s** (jak plan pancerza) | zabija jak dziś |
| D7 | Kula przy rozbitej skorupie | **nie zwija się przy < 2 płytach** | zawsze |
| D8 | Kolejność | **L0 → L1 → L2 → playtest → L3 → L4** | wszystko przed playtestem |

## 7. Cel i pomiar (dziennik sesji, NORMAL, 1.1 i 1.2)

- Łupacz zadaje obrażenia w **≥ 50%** spotkań (dziś 0 z 1); średnio **1–2 serca** na spotkanie.
- **≤ 15%** spotkań kończy się powaleniem gracza przez Łupacza (zagrożenie, nie kat).
- Chwyt: **≥ 40%** zapowiedzi kończy się ucieczką (zapowiedź czytelna); jeśli < 20% — wydłużyć zapowiedź.
- Podkop: co najmniej raz na kilka spotkań gracz stawia stempel z powodu Łupacza (`dig_prop` w 10 s po ostrzeżeniu).
- Walka trwa **20–60 s** (dziś 17 s do zanurzenia z 25% HP).

## 8. Ryzyka

- **Niesprawiedliwy chwyt w solo** — łagodzą: zapowiedź 1,0 s, deski jako bezpieczna strefa, uwolnienie własnym ciosem, limit 2 serc.
- **Pułapka bez wyjścia po podkopie** — odcięcie tylko przy żwirze do przekopania; test sprawdza, że gracz wychodzi.
- **Kula utyka na rampach wykopu** — szarża tylko przy czystym rozbiegu po podłożu (`_run_clear`), koniec na progu > 9 px.
- **Zmysł drgań zbyt łatwy do ograniczenia** (kucanie = nieśmiertelność) — kucający nie kopie, a pod ziemią Łupacz czeka; L5 sprawdza czas.
- **Rig nowego modelu** ma krótkie łapy (×0,62) — klipy `grab`, `curl`, `belly_up` trzeba ocenić na zrzutach przed scaleniem.
- **Więcej odgłosów w kopalni** — nowe dźwięki podlegają limitowi hałasu wrogów jak inne odgłosy (FUN_PLAN.md) i ściszaniu pod ważnymi sygnałami.

## 9. Pliki

- `prototype/scripts/enemy_mole.gd` — L0–L4 (dziennik, zmysł, chwyt, podkop, kula).
- `prototype/scripts/enemy_defs.gd` — prędkość, zmysły, głosy.
- `prototype/scripts/noise_manager.gd` — `tremor()`, sygnał drgań bez Uwagi.
- `prototype/scripts/player.gd` — drganie przy lądowaniu, poza chwytu w gruncie (stan już replikowany: `grabbed`).
- `prototype/scripts/dig_zone.gd` — `force_warn()`, zawał na Łupaczu (D6).
- `prototype/scripts/enemy_bruiser.gd` — wydzielenie `_run_clear` / `charge_through` do wspólnego użytku (bez zmiany zachowania Wołka).
- `prototype/scripts/enemy3d.gd`, `char3d.gd` — poza chwytu, toczenie, wynurzenie do połowy, pęknięcia gruntu.
- `prototype/tools/rig_lupacz.py` — klipy `grab`, `curl`, `belly_up`.
- `prototype/tools/bake_sfx.py`, `bake_hybrid.py` — `mole_grab`, `shell_curl`, `shell_roll_loop` (synteza + nagrania do odsłuchu).
- `prototype/scripts/dig_test.gd`, `enemy_test.gd`, `tools/test_net_session.sh` — testy; `CLAUDE.md` — opisy testów.
- `GDD.md` §7.1, kodeks (EN/PL w `translations/ui.csv`), `CHANGELOG.md`.

## 10. Rekomendacje

1. **Zacząć od L0.** Dzisiejszy test pokazał, że zanurzony Łupacz może nie wrócić — każda nowa zdolność pod ziemią stoi na wynurzeniu,
   więc najpierw dziennik i naprawa.
2. **L1 + L2 to rdzeń zmiany** — po nich Łupacz jest już groźny; L3 i L4 rozbudowują, ale nie są konieczne do oceny kierunku.
   Playtest po L2, zanim powstaną kosztowne klipy kuli.
3. **Tempo tylko do 30 px/s.** Szybszy Łupacz byłby kolejnym Ślepcem; jego tożsamość to zasadzka spod ziemi.
4. **Trzy różne zapowiedzi dźwiękiem** (pod stopami, w stropie, w płytach) — w ciemności gracz ma rozpoznać zdolność uchem, zanim ją zobaczy.
5. **Kontry z kopalni, nie z menu** — deski, stemple, wnęki, kilof. Dzięki temu Łupacz uczy gracza czytać kopalnię, a nie tylko strzelać.
6. **Liczby to punkt startowy** — strojenie po L5 na dziennikach, z celem z §7.
