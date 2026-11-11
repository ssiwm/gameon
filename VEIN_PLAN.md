# Żyła w centrum — walka z ruchem bossa (plan)

Status: **plan z 2026-11-11 (main 1.7.550, 6e0789bf; uwzględnia otwarty PR #658 1.7.551)**. **E1 wdrożony w 1.7.552** (hala, brama, kamera,
punkt kontrolny, Stalker do F3; kadr kamery obniżony o 32 px względem §6.2, bo dolny pasek HUD-u zasłaniał podłogę). **E2 wdrożony w 1.7.553** (cykl z §7, trzy gardziele F1, wybór gardzieli, „ból”, cios wynurzenia, pęknięcia i zanurzanie w 3D, sieć, bot) — **bez** obrotu do celu, garbu jako bryły 3D i trafienia 20% w oświetlony garb (przejście pokazuje ślad wody; zostają na E3–E4).
Decyzje D1–D5 (§19) **przyjęte 2026-11-11 według zaleceń**: hala zamknięta bramą z korzeni, stały kadr areny, Stalker od F3,
faza sufitowa ze strąceniem światłem, ogień w E5 po playteście 3. Kolejność: najpierw scalić #658, potem etapy E0–E7 (§18),
playtest po E1, E2 i E4.

## 1. Skąd to

Żyła stoi nieruchomo przy wschodniej ścianie mapy (x 2936, 136 px od krawędzi), a kamera gracza jedzie za nim bez wyprzedzenia
(kadr 320×180 px na domyślnym NORMAL). Walkę widać więc głównie przez prawą krawędź ekranu. Dane z dzienników sesji
(29 prób walki, 1.7.211–1.7.465, wszystkie solo — człowiek z botem albo sam):

| Fakt | Liczba |
|---|---|
| Paszcza w kadrze gracza (kamera na graczu, granice mapy) | **NORMAL 1,7%** czasu walki, WIDE 18%, CLOSE 1% |
| Choć kawałek ciała w kadrze | NORMAL 19%, WIDE 35% |
| Gracz na zachodnich rusztowaniach, 170–380 px od Żyły | 88% czasu |
| Poza zasięgiem plucia (300 px) — Żyła nie atakuje, paszcza zamknięta, 5% obrażeń | 45% czasu |
| W zasięgu macki | 0% |
| Upadki od Żyły / od Stalkera | 34 (co najmniej 31 od plucia) / 18 |
| Latarka włączona w 128 px od paszczy (warunek oślepienia) | 0%; Q w walce: 0 użyć |
| Start walki i każdy restart od punktu kontrolnego | platforma gniazda N4, **192 px nad Żyłą** — strzały „z góry” = 5%, gracz celem plucia |
| Restart od punktu kontrolnego | wskrzesza wszystkich wrogów mapy, w tym Wołka 144 px od Żyły (1.7.430: wipe od głazu i beczki przy 525/525 HP) |
| Uwaga w walce | mediana 24 → 93 po 30–40 s, potem 95–98; Stalker budzi się 8–30 s po starcie (18 z 19) |
| Okno paszczy (symulacja stałych z `boss.gd`, NORMAL) | 24% na rusztowaniu, 30% w furii, 0% poza zasięgiem; EASY 18% — mniej okien |
| Wynik | 10 zabić na 28 prób; EASY 7/12, NORMAL 3/16, **NORMAL od 1.7.341: 0/7** |

Wniosek: walka jest dziś pojedynkiem „unik plucia z rusztowania do celu poza ekranem”. Z czterech narzędzi z projektu (okno paszczy,
latarka, Q, kładki) działa jedno. Gracze ruszają się często (mediana co 3 s), ale ruch nie zmienia sytuacji, bo bezpieczne miejsce
jest stałe.

## 2. Stan obecny (z kodu)

| Obszar | Fakt | Gdzie |
|---|---|---|
| Boss | `CharacterBody2D` bez ruchu; jedna strefa trafień 70×66; stan w `_sync` (bez pozycji) | `boss.gd`, `boss_base.gd` |
| Okno | paszcza otwarta `MAW_WINDOW` 1 s po każdym ataku; zamknięta 5%, wybuch 35%, śrucina ×0,6; „z góry” = heurystyka kierunku | `boss.gd: take_hit` |
| Ataki | macka (|dx| ≤ 64), fala po podłodze (≤ 170 px), plucie (≤ 300 px, w najwyżej stojącego) | `_tick_attacks` |
| Latarka | oślepia w zapowiedzi, gdy snop (8 m = 128 px, ±24°) trafia paszczę; 2 s, przerwa 10 s | `lights.gd: flashlight_on` |
| Q | 5 s plucia w miejsce Przesterowania (do 520 px) | `_diverted` |
| Kamera | `Camera2D` gracza, offset (0, −35), zoom 1,6 / 2,0 / 2,4 (baza 640×360), granice = mapa; pas `cam_lock` tylko w kryjówce | `player.gd`, `section_camera.gd` |
| Punkt kontrolny | pozycje graczy w chwili zniszczenia ostatniego gniazda; restart: `reset_enemy()` u każdego wroga | `mission._save_checkpoint`, `main._restart_from_checkpoint` |
| Model 3D | jeden statyczny GLB (`art/enemy3d/vein.glb`) z deformacją w shaderze (szczęka, skala); bez szkieletu i macek | `enemy3d.gd` SPEC „vein” |
| Wzorce do użycia | Pijawka: ruch pod powierzchnią, zapowiedź, wynurzenie, chwyt z progiem obrażeń drużyny (`GRAB_FRAC`), kwas w grupie „acid” | `leech.gd`, `acid_spit.gd` |
| Skok gracza | 42 px (v 275, g 900) — pomosty co 2 kafle; bieg 95 px/s; Stalker 88 px/s (wspina się 60) | `player.gd`, `stalker.gd` |

## 3. Wzorce z branży — co bierzemy, co odrzucamy

| Zasada | Przykład | U nas |
|---|---|---|
| Boss zawsze w kadrze: zamknięta arena na jeden ekran | Contra, Metal Slug, Cuphead | hala tartaku 25×14 kafli, kamera areny (§6.2) |
| Zamknięcie areny i szybki, powtarzalny restart tuż przed nią | Hollow Knight (bramy areny), Elden Ring (Stakes of Marika) | brama z korzeni, stały punkt kontrolny w przedsionku (§6.3) |
| Zapowiedź → akcja → odpoczynek; okno kary związane z atakiem bossa | zasada animacji anticipation–action–recovery; Hollow Knight, Dark Souls | rytm zostaje, ale okna rosną z ruchem i fazą (§7, §10) |
| Brak stałego bezpiecznego miejsca: ataki pokrywają każdy dystans i wysokość, boss się przemieszcza | Hollow Knight (Dung Defender zakopuje się i wyskakuje), Monster Hunter (potwór zmienia miejsce) | gardziele: Żyła znika w splocie i wynurza się gdzie indziej (§7) |
| Każda faza zmienia arenę i dokłada jeden nowy czasownik, nie tylko tempo | Hades (Hydra dokłada głowy), Cuphead (zmiana formy bossa) | F1 podłoga, F2 ściany i korzenie, F3 sufit (§10) |
| Okno wywołane przez gracza właściwym narzędziem | Monster Hunter (flash pod strąca latającego potwora), Sekiro (złamanie postawy) | latarka lub flara strąca Żyłę z sufitu, worek zarodników przerywa plucie (§9, §11) |
| Wyraźne słabe punkty zamiast ukrytych reguł kierunku | Contra (rdzeń bossa), Monster Hunter (części do rozbicia) | osobne strefy trafień: paszcza, worek, korpus (§9) |
| Ratunek kolegi jako mechanika drużyny | Left 4 Dead (Smoker, Hunter — przypięty sam się nie uwolni) | chwyt macki z progiem obrażeń drużyny (§10, wzór Pijawki) |
| Narastająca presja z czytelnym zegarem w świecie gry | „enrage timer” w rajdach MMO | krzyk F3 wypuszcza Stalkera — wyścig z jego dojściem (§12) |
| Spójny język zapowiedzi: kształt, ruch i dźwięk, nie sam kolor | standard dostępności | tabela w §15 |
| Pomiar, potem strojenie | telemetria i mapy cieplne w playtestach | wpisy `vein` w dzienniku, raport, KPI (§4, §17) |

Odrzucamy: losowość bez wzorca (gracz musi móc się nauczyć — losujemy tylko spośród 2 dopuszczalnych gardzieli i ataków), fazy „tylko
szybciej”, kary bez okna (każdy nowy atak otwiera paszczę), obrażenia od samego dotyku ciała (zbyt nieczytelne w 2,5D).

## 4. Cel i miary sukcesu

Fantazja: **matka gniazd budzi się w swojej hali — jest wszędzie w ścianach tartaku, a drużyna musi nadążać za nią z bronią i światłem.**

| Miara (dziennik `vein`, §17) | Dziś | Cel |
|---|---|---|
| Paszcza w kadrze każdego człowieka | 1,7% (NORMAL) | ≥ 95% |
| Czas, gdy gracza nie sięga żaden atak | ~45% | < 5% |
| Największy udział jednego ataku w upadkach od Żyły | ≥ 91% (plucie) | ≤ 45% |
| Walka solo NORMAL (zabicie) | 83–174 s | 120–180 s, każda faza 40–70 s |
| Zabicie NORMAL, solo z botem | 0/7 od 1.7.341 | mediana ≤ 3 prób do pierwszego zabicia |
| Wykorzystane okna (obrażenia w ≥ 50% czasu otwartej paszczy) | nie mierzone | ≥ 60% okien |
| Oślepienie latarką lub flarą | 0 | w ≥ 50% walk |
| Q w walce | 0 | w ≥ 30% walk |
| Od wipe'a do pierwszej akcji w kolejnej próbie | ~2,5 s + zejście z N4 | ≤ 8 s |

## 5. Pętla walki w skrócie

1. **Wynurzenie** w jednej z gardzieli (zapowiedź 1,2 s: pękanie podłogi, światło spod spodu, dudnienie) — kto stoi w pękającym
   miejscu, dostaje cios i odrzut.
2. **Ryk** 0,6 s z otwartą paszczą — nagroda za dobre ustawienie przed wynurzeniem.
3. **Seria 3 ataków** (F2: 4) w stronę celu; po każdym okno paszczy.
4. **Zanurzenie** — po serii, po 12 s albo po „bólu” (≥ 12% maks. HP w 5 s); **przejście** splotem (garb sunący pod podłogą lub
   ścianą, 1,5–2,5 s oddechu dla drużyny) i znów 1.

Gracz musi się przestawić co wynurzenie (12–15 s): z miejsca wynurzenia, spod Żyły (pancerz z góry), na stronę paszczy (żeby zadawać)
albo za plecy (worek, unik macki).

## 6. Arena: hala tartaku

### 6.1 Układ (szkic; wymaga `--maptest` i przeglądu w 3D)

Obecny tartak (kol. 158–189: wieża rusztowań, gniazdo N4 na szczycie, Wołek i 2 Trzoski) zastępuje kryta hala z przedsionkiem.
Wnętrze: kol. 165–189 × rzędy 12–25 (400×224 px, środek x 2840). Szkic na mapie z #658:

```
     555555555566666666667777777777888888888899
     012345678901234567890123456789012345678901
10   ........................................##
11   ..............MMMMMMMMMMMMMMMMMMMMMMMMMM##   dach hali (sufit = gardziel F3)
12   .........w....M........w.......w........##
13   .........w....M........w.......w........##
14   .........w....M........w.......w........##
15   .........w....M........w.......w........##
16   .........w....M........w.......w........##
17   .........w....M........w.......w........##
18   .........w....M------..w.......w...-----##   wysokie półki boczne
19   .........w....M........w.......w........##   ← gardziele ścienne F2 (x 2640 i 3040, ok. y 336)
20   .........w....M........----------.......##   kładka środkowa nad G_C
21   .........w....M........w.......w........##
22   .........w....M-------.w.......w.-------##   pomosty boczne nad G_W i G_E
23   .........w.............w.......w........##   ← brama z korzeni (kol. 164, rzędy 23–25)
24   --.......w.....---.....w.......w.....---##   stopnie przy ścianach
25   k........w.ay...o......w...BN..w......o.##   G_W kol. 169 · G_C kol. 177 (B + gniazdo N) · G_E kol. 185
26   CCbbbbbbCC~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
```

- **Przedsionek** (kol. 158–163): wyjście z szybu 3 i sucha półka z #658, amunicja `a`, bateria `y`, punkt kontrolny.
- **Pomosty co 2 rzędy (32 px)** przy skoku 42 px; przerwy między poziomami 1–2 kafle. Układ symetryczny — zawsze jest druga strona.
- **Gniazdo N4 stoi na środkowej gardzieli** (`N` obok `B`): zniszczenie ostatniego gniazda tutaj to wejście bossa spod niego.
- **Beczki `o`** przy gardzielach bocznych (48 px) — pułapka na Żyłę (§11).
- **Bez zwykłych wrogów w hali.** Wołka i Trzoski z tartaku przenieść na podejście przed szybem 3 albo usunąć.
- Gardziele, prostokąt areny, brama i punkt kontrolny jako dane mapy (`VEIN_ARENA` w `z1_m3.gd`, jak `NICHES`), nie nowe litery —
  wolnych znaczników prawie nie ma.

### 6.2 Kamera areny

Gdy faza BOSS trwa, a lokalny człowiek jest w prostokącie areny (z ramką ścian: x 2632–3048, y 184–424):

- granice `Camera2D` = prostokąt areny, zoom = min(ustawienie gracza, dopasowanie areny) → ok. **1,5 (427×240 px)** — kadr praktycznie
  stały, cała hala i Żyła (16% szerokości ekranu) zawsze widoczne;
- przejście 0,6 s przy wejściu i wyjściu; poza areną zwykła kamera;
- widok 3D już dziś podąża za `Camera2D` (`view3d.gd`), więc wystarczy zmiana granic i zoomu; sprawdzić ostrość postaci 3D
  (`Char3D.ss_for_view`) i tabliczki nad postaciami przy 1,5.

Alternatywa (D2): dynamiczne kadrowanie (środek między graczem a paszczą, zoom 1,5–2,0). Daje większe postacie, ale gorzej czytelne
ataki z drugiego końca hali.

### 6.3 Brama, start i punkt kontrolny

- Walka zaczyna się, gdy **wszystkie gniazda są zniszczone i człowiek wejdzie do hali** (albo już w niej jest, gdy pada N4).
  Ostatnie gniazdo zniszczone gdzie indziej → Żyła budzi się „na sucho” (ryk co kilkanaście sekund, korzenie drgają), czeka na wejście.
- **Brama z korzeni** zamyka otwór 4 s po wejściu pierwszego człowieka albo gdy wejdą wszyscy żywi; kto został w przedsionku,
  zostaje wciągnięty do środka (efekt korzeni). Otwiera się w F3 (wejście Stalkera, §12) i po śmierci Żyły.
  Technicznie: komórki przełączane jak przegrody (`breakable.gd`) — zmiana kolizji, nawigacji i siatki dźwięku, reset przy restarcie.
- **Punkt kontrolny = stałe miejsce w przedsionku** (dane mapy), nie pozycje graczy. Restart: pełne HP i bateria, Q naładowane,
  gniazda zniszczone, brama otwarta; kto wejdzie — start.
- **Restart nie wskrzesza zabitych wrogów**: w `_save_checkpoint` zapisać listę zabitych (jak `save_breakables_checkpoint`),
  `_restart_from_checkpoint` przywraca tylko żyjących wtedy wrogów na ich pozycje.

## 7. Żyła: stany i ruch

| Stan | Czas | Paszcza | Trafienia | Uwagi |
|---|---|---|---|---|
| UŚPIONA | — | — | rykoszet | pod gniazdem N4 |
| CZEKA | — | zamknięta | 5% | gniazda zniszczone, nikt nie wszedł |
| WYNURZENIE | 1,2 s (EASY 1,5, HARD 1,0) | — | nietrafialna | pękanie w miejscu gardzieli; kto w promieniu 40 px na podłodze — 1 HP i odrzut |
| RYK | 0,6 s | **otwarta** | pełne | po każdym wynurzeniu |
| WALKA | 3–4 ataki, do 12 s | okna po atakach | §9 | obrót do celu z zapowiedzią 0,3 s |
| ZANURZENIE | 0,7 s | zamknięta | 5% | po serii, po 12 s albo po „bólu” |
| PRZEJŚCIE | 1,5–2,5 s (160 px/s) | — | garb 20%, gdy oświetlony | garb biegnie żyłą pod podłogą / w ścianie; flara albo snop pokazuje cel |

**Wybór gardzieli** (spośród dostępnych w fazie, nigdy ta sama dwa razy z rzędu; losowanie między dwiema najwyżej ocenionymi):
+2 najbliższa graczowi, który najdłużej stoi w jednym miejscu (≥ 6 s w 48 px) — przeciw kampieniu; +1 najbliższa temu, kto zadał
najwięcej obrażeń w ostatnich 10 s; Q nadpisuje wybór (§11). Bez gracza w hali — CZEKA.

**Gardziele:** F1 — G_W (x 2712), G_C (x 2840), G_E (x 2968) na podłodze, 128 px od siebie. F2 — dodatkowo S_W i S_E w ścianach
(paszcza w poziomie do środka hali, ok. y 336). F3 — sufit nad kładką (x 2840, y 192), paszcza w dół.

## 8. Ataki

Każdy atak ma zapowiedź (×`boss_cd`), własny dźwięk i znak w 3D; po każdym paszcza otwiera się na `MAW_WINDOW`.

| Atak | Faza | Kogo | Zapowiedź | Zasięg / działanie | Unik | Uwagi |
|---|---|---|---|---|---|---|
| Macka | 1+ | gracz przed paszczą | 0,75 s | łuk 80 px przed Żyłą | odskok, przeskok za plecy | z gardzieli ściennej: poziomy zamach na wysokości pomostu |
| Fala | 1+ | ktoś na podłodze | 0,9 s | po całej podłodze hali w obie strony | skok, pomost | było 170 px — teraz cała hala |
| Plucie | 1+ | najwyżej stojący, ale nie ten sam 3× z rzędu | 0,8 s | łuk z celem z początku zapowiedzi, znacznik lądowania | zejść ze znacznika | **zostawia kałużę kwasu na 3 s** (promień 14 px, grupa „acid”) — odbiera miejsce na pomoście |
| Korzenie | 2+ | gracz na pomoście ≥ 3 s w 48 px albo najwyżej stojący | 1,0 s pęknięć i żaru w deskach | 3 kolce przez pomost, 1 HP | zejść z pomostu | wyrwany fragment pomostu nie trzyma 8 s (kładka bez kolizji) |
| Deszcz zarodników | 3 | gracze pod sufitem | 0,9 s | 3 plwociny: na 2 graczy i losowo w hali | znaczniki | zastępuje plucie w F3 |
| Chwyt | 3 | gracz pod Żyłą | 0,9 s | macka z sufitu chwyta na 3 s; drużyna musi zadać 6% maks. HP (macka albo paszcza), solo — cios wręcz ×2 | wyjść spod paszczy | wzór `leech.gd` (`GRAB_FRAC`, `GRAB_MELEE_MULT`); nieuwolniony = upadek |

Sprawdzian projektu (test, §18): w każdej fazie każde miejsce hali dostępne dla gracza jest w zasięgu co najmniej dwóch ataków.

## 9. Obrażenia i słabe punkty

Zamiast heurystyki „z góry” (źródło błędu WRATH-4 z 2026-10-29) — **osobne strefy trafień**:

| Strefa | Kiedy aktywna | Mnożnik |
|---|---|---|
| Paszcza (ok. 24×20 px, z przodu) | otwarta: RYK, okna po atakach, oślepienie, upadek | 1,0 (śrucina 0,6, jak dziś) |
| Paszcza zamknięta | reszta czasu | 0,05 (wybuch 0,35, jak dziś) |
| Korpus i plecy | zawsze | 0,05 |
| **Worek zarodników** (plecy, 30 HP) | tylko w zapowiedzi plucia, nabrzmiewa i świeci | trafienie do 0 HP: plucie przerwane, chmura zarodników, **paszcza otwarta 1,5 s** |
| Garb w przejściu | oświetlony flarą lub snopem | 0,2 |

Worek daje rolę temu, kto nie jest celem (w duecie: jeden ściąga plucie, drugi przebija worek zza pleców); solo — wybór między unikiem
a obejściem Żyły. Strefy jako osobne `Hurtbox` węzły-dzieci (sprawdzić, czy `hurtbox.gd` obsługuje kilka na encję; jeśli nie — rozszerzyć).

## 10. Fazy

| Faza | HP | Gardziele | Nowość | Potomstwo |
|---|---|---|---|---|
| F1 „Gardziel” | 100–66% | G_W, G_C, G_E | wynurzanie, okno ryku, worek | brak (nauka) |
| F2 „Splot” | 66–33% | + S_W, S_E | korzenie przez pomosty, seria 4 ataków, zapowiedzi ×0,85 | 1 Trzosek co 8 s, najwyżej 2 (+1 na człowieka) |
| F3 „Matka” | 33–0% | sufit | deszcz zarodników, chwyt, **strącenie światłem**, Stalker w drodze | z sufitu co 6 s, najwyżej 3 |

**Przejścia (spektakl i nagroda):**
- **66%:** ryk z falą odrzutu 80 px (zrzuca z pomostów obok), paszcza otwarta 2,5 s, żyły rozrastają się po ścianach (nowe gardziele).
- **33%:** krzyk — Uwaga 100, migotanie świateł (jak dziś), brama otwiera się, Stalker rusza (§12); Żyła wspina się na sufit
  (2 s, nietrafialna).
- **F3 — strącenie:** latarka lub flara w paszczę w zapowiedzi → Żyła spada na środek hali: **upadek 3 s**, paszcza otwarta,
  pełne obrażenia z każdej strony; potem wraca na sufit (1,5 s). To główne okno F3 i kulminacja kooperacji: jeden świeci, reszta strzela.

## 11. Światło, Q, ogień, beczki (filary 2 i 4)

- **Latarka:** oślepia jak dziś (w zapowiedzi, 2 s, przerwa 10 s), ale w hali 400 px po wynurzeniu obok gracza zasięg 128 px jest
  realny. W F3 oślepienie = strącenie. Trzoski lgną do światła (`phototaxis`) — świecenie ma cenę.
- **Flara:** zapalona flara w 48 px od paszczy w zapowiedzi oślepia (raz na flarę) — sposób na dystans; flara ujawnia też garb w przejściu.
- **Q (Przesterowanie):** w hali Żyła zanurza się i wynurza w gardzieli najbliższej punktu Q, przodem do niego, i przez 5 s atakuje
  to miejsce. Służy do ściągnięcia jej do beczki, z dala od leżącego kolegi albo spod kładki. Ładunek Q jest pełny na starcie walki
  (`objective_bonus`, jak dziś). Podpowiedź (`Hints.TIPS`) przy pierwszym przebudzeniu: „Q ściąga Żyłę”.
- **Beczki** przy G_W i G_E: wybuch, gdy Żyła wynurzona obok — 8% maks. HP, paszcza otwarta 2 s; rani też graczy w promieniu (filar 3).
  Odnawiają się przy restarcie (reset zniszczalnych).
- **Ogień (opcja, D5):** podpalona Żyła przez 4 s nie może się zanurzyć ani wypuścić korzeni (GDD §7.1: „Kontra: ogień”). Wymaga ognia
  na trasie — dziś HKM-9 leży w Składzie poza trasą; np. granaty fosforowe w przedsionku.

## 12. Stalker

- Od startu walki do F3 Stalker **nie wchodzi do hali matki**: hałas z hali nie budzi go (`stalker_hold` w czasie fazy BOSS przed F3),
  a obudzony wcześniej odchodzi (stan `leaving`). Dziś Uwaga przekracza 60 po ~20 s i Stalker jest w walce od początku — krzyk F3
  nic nie dodaje.
- **Krzyk F3 go wypuszcza:** Uwaga 100 w hali, brama otwarta, sygnał w HUD i dźwięk zbliżania (odległość). Z dzienników: od przebudzenia
  do pierwszego ciosu ~30 s — tyle trwa wyścig F3 (cel strojenia: część HP F3 do zbicia w 30–40 s).
- Q w F3 ma dwie strony: ściąga Żyłę, ale woła też Stalkera (filar 2: hałas jako decyzja).

## 13. Kooperacja, skalowanie, bot

- **Cele rotują:** żaden gracz nie jest celem 3 ataków z rzędu; plucie i korzenie w najwyżej stojącego, macka i fala w bliskich.
  Duet naturalnie dzieli się na „kogo ściga” i „kto przebija worek / świeci”.
- **Skalowanie:** HP + `HP_PER_EXTRA_HUMAN` (dziś 250, do strojenia), potomstwo +1 na człowieka, chwyt wymaga drużyny
  (próg 6% maks. HP liczony z obrażeń wszystkich).
- **Bot (filar 6):** omija pęknięcia wynurzenia i korzeni, znaczniki plucia i kałuże (rozszerzyć `_bot_dodge_acid` o nowe znaczniki),
  skacze przed falą, schodzi spod Żyły, strzela w paszczę tylko w oknie (oszczędza amunicję), przebija worek, gdy jest za plecami,
  uwalnia chwyconego. Świecenie bota: tylko w zapowiedzi i gdy dowódca świeci (nie ściągać Trzosków bez potrzeby).
- Bez bota (solo): chwyt uwalnia się ciosem wręcz ×2; pierwszy upadek = wykrwawienie i powrót w przedsionek, drugi = wipe (jak dziś).

## 14. Trudność

| Parametr | EASY | NORMAL | HARD |
|---|---|---|---|
| Zapowiedzi i przerwy (`boss_cd`) | ×1,3 | ×1,0 | ×0,8 |
| Wynurzenie (zapowiedź) | 1,5 s | 1,2 s | 1,0 s |
| `MAW_WINDOW` | **1,3 s** | 1,0 s | 0,9 s |
| Korzenie | od F2, pojedyncze | od F2 | od F2, dwa naraz |
| HP (`boss_hp`) | ×0,7 | ×1,0 | ×1,4 |

Dziś EASY ma rzadsze okna (18% wobec 24%), więc wolniejsza Żyła nie skraca walki. Dłuższe okno na EASY to naprawia.

## 15. Widok 3D, dźwięk, czytelność

Wszystko w 3D (zasada projektu); jeden język zapowiedzi:

| Znaczenie | Obraz | Dźwięk |
|---|---|---|
| „Zaraz tu wyjdzie” | pęknięcia w podłodze/ścianie + światło od spodu, pył | dudnienie narastające 1,2 s |
| „Atakuje cię” | żar paszczy zielony (plucie), czerwony łuk (macka), pas na podłodze (fala), żar w deskach (korzenie) | osobny warkot na atak (jest dla 3 ataków) |
| „Strzelaj teraz” | paszcza otwarta, pomarańczowy żar, światło na otoczenie | krótki syk/oddech |
| „Ból” / przejście | drżenie, garb pod podłogą z falą wody | mlaśnięcie, szum w żyłach |
| „Oślepiona / strącona” | biały błysk, upadek z sufitu | ryk wysoki |

- Ruch modelu: pozycja z symulacji 2D; zanurzanie i wynurzanie przesunięciem w dół i skalą `sxz` (jak `_sink` przy śmierci).
  Gardziel ścienna i sufitowa — obrót całego modelu o 90° i 180° (bryła organiczna, bez szkieletu).
- **Nowe elementy:** żyły na ścianach i podłodze hali (dekale lub rury z ziarna, rosną w F2), garb przejścia, macka (rura po krzywej
  w `view3d`, ImmediateMesh albo model z Meshy — do wyceny), worek na plecach (osobna bryła z pulsowaniem).
- „Reduce effects”: mniej pyłu i wstrząsów, zapowiedzi bez zmian.

## 16. Sieć

Serwer rozstrzyga stan, pozycję, gardziel, cel ataku, okno, chwyt i obrażenia (jak dziś). `_sync` dostaje pozycję, gardziel, stan
ruchu i fazę; klienci interpolują garb i wynurzenie z czasu startu (jak fala: `_wave_start_ms`). Dołączający w trakcie walki dostaje
stan bossa, bramy i kałuż. Kamera areny liczy się lokalnie u każdego człowieka.

## 17. Dziennik i raport

Nowe zdarzenie `vein` (serwer): `start` (humans, bots, diff), `emerge` (anchor, reason: cycle/pain/q/idle), `attack` (kind, target,
bot), `hit` (kind, who), `window` (src: attack/roar/stun/sac/fall/barrel, s, dmg), `stun` (by: lamp/flare, who), `sac` (who),
`grab` (who, freed_by, s), `phase` (n), `stalker_release`, `stalker_arrive`, `death` (s). `mission_end.boss` dostaje czasy faz.
Raport `tools/vein_report.py` (albo sekcja w `session_progress.py`) liczy miary z §4, w tym paszczę w kadrze z próbek `pos`.

## 18. Etapy wdrożenia

Każdy etap = osobny PR z podbiciem wersji i wierszem w `CHANGELOG.md`; dokumenty (GDD §7.1 i §9, README) w etapie, który zmienia mechanikę.

- **E0 — symulacja i dziennik.** `--veinsim` (rytm, okna, czas zabicia przy zmierzonym DPS ~20 na człowieka w oknach, jak `--leechsim`),
  zdarzenia `vein` dla obecnej walki, raport. Bez zmian w grze.
- **E1 — hala, kamera, brama, punkt kontrolny (MVP 1).** Mapa (§6.1), `VEIN_ARENA`, kamera areny, brama z korzeni, start po wejściu,
  stały punkt kontrolny, restart bez wskrzeszania, wrogowie z hali przeniesieni, `stalker_hold` do F3. Żyła nadal bez ruchu, ale
  na środku hali. Testy: `--maptest` (nawigacja przy bramie otwartej i zamkniętej), nowy `--veintest` (start, brama, punkt kontrolny,
  wrogowie po restarcie, kamera w prostokącie, Stalker), `test_net_session.sh` (brama u klienta i dołączającego).
  **Playtest 1:** czy centrum ekranu i stały kadr wystarczają.
- **E2 — ruch (MVP 2).** Stany z §7, gardziele F1, wybór gardzieli, obrót, obrażenia wynurzenia, garb; 3D: zanurzanie, pęknięcia, garb;
  sieć: pozycja w `_sync`; bot omija pęknięcia. Test: cykl, wybór gardzieli przeciw kampieniu, „ból”, sieć.
  **Playtest 2:** czy ruch wymusza zmianę pozycji bez frustracji.
- **E3 — ataki i słabe punkty.** Strefy trafień (§9), worek, fala na całą halę, kałuże kwasu, rotacja celów, tabela trudności (§14),
  język zapowiedzi (§15). Aktualizacja `fun_test` (obrażenia Żyły) i `bot_test` (znaczniki).
- **E4 — fazy.** F2 (gardziele ścienne, korzenie z wyrywaniem pomostu, potomstwo), F3 (sufit, deszcz, chwyt, strącenie), przejścia;
  modele 3D (macka, worek, żyły na ścianach). **Playtest 3.**
- **E5 — narzędzia filarów.** Flara, Q w hali, beczki, podpowiedzi; opcjonalnie ogień (D5).
- **E6 — kooperacja i bot.** Skalowanie, zachowania bota z §13, dołączający w trakcie walki, testy sieci z dwoma ludźmi.
- **E7 — strojenie.** HP i czasy z `--veinsim` i dzienników do celów z §4; usunięcie martwego kodu (heurystyka „z góry”,
  `SPIT_RANGE_FAR` z #658, jeśli zbędny).

MVP do pierwszej oceny na żywo to **E1 + E2** (hala, kamera, ruch). E3–E4 dopiero po playteście 2.

## 19. Decyzje (rozstrzygnięte 2026-11-11: według zaleceń)

| # | Pytanie | Warianty | Przyjęte |
|---|---|---|---|
| D1 | Zamknąć halę? | A: brama z korzeni do F3 · B: otwarta hala | **A** — bez tego wraca kampienie poza kadrem |
| D2 | Kamera | A: stały kadr areny (zoom ~1,5) · B: dynamiczne kadrowanie gracz–paszcza | **A** (czytelność, tradycja Contry); B zostaje awaryjny, gdy playtest 1 pokaże, że postacie przy 1,5 są za małe |
| D3 | Stalker | A: dopiero od F3 (wyścig) · B: jak dziś (od hałasu) | **A** — dziś jest w walce od ~30 s i zabiera kulminację |
| D4 | Faza sufitowa F3 | A: sufit + strącenie światłem · B: F3 na podłodze (wszystkie gardziele naraz, szybciej) | **A** — model macki i pozy w E4; B tylko, jeśli wycena grafiki E4 okaże się za duża |
| D5 | Ogień | A: wejdzie w E5 (granaty fosforowe w przedsionku) · B: bez ognia | **A**, po playteście 3 |

## 20. Ryzyka

- **Zoom 1,5** zmniejsza postacie o 25% względem NORMAL — sprawdzić czytelność, tabliczki i ostrość renderu postaci 3D.
- **Model bez szkieletu:** obroty o 90° i 180° mogą wyglądać źle; macka i worek to nowa grafika (koszt w E4).
- **Nawigacja** bota i Stalkera po nowej hali i przy przełączanej bramie (`--maptest`, `nav.gd`).
- **`boss_base.gd` jest wspólny z Pijawką** — zmiany stref trafień i ruchu trzymać w `boss.gd` albo pokryć `--leechtest`.
- **Pomost bez kolizji przez 8 s** to pierwszy kawałek „spadającej kładki” z DESTRUCTION_PLAN (D3, niezrobione) — zrobić prosto
  (fragment wyłączony na czas), bez fizyki.
- **Zakres:** E4 jest duży; jeśli playtest 2 pokaże, że ruch + kamera wystarczają, F2–F3 można uprościć (D4 B).
- **Jedna misja z danymi solo:** kooperacji nikt nie grał — cele w §4 sprawdzać osobno dla solo i duetu.

## 21. Odrzucone warianty

- **Żyła goniąca po całej mapie** — dubluje rolę Stalkera, ciało 70 px nie przejdzie tuneli, kamera nie obejmie walki.
- **Większy zasięg plucia i więcej HP** (kierunek #658) — leczy objaw; boss dalej poza kadrem i bez ruchu.
- **Sama kamera z wyprzedzeniem w stronę bossa** — poprawia widoczność, ale zostawia stałą półkę poza zasięgiem i jeden atak.

## 22. Związek z PR #658

#658 (odrodzenie przy gnieździe, dalekie plucie, sucha półka, wylot szybu 3, skrytki H) zostaje: plan buduje na jego mapie (sucha półka
w przedsionku, skrytka H (184, 33) pod halą bez zmian). W hali 400 px dalekie plucie (`SPIT_RANGE_FAR`, `IDLE_FAR`) przestaje być
potrzebne — do usunięcia w E7. Odrodzenie po wykrwawieniu w trakcie walki = punkt kontrolny w przedsionku (§6.3).
