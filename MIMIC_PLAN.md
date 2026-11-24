# Mimik — plan

Status: **plan z 2026-11-23 (main 1.7.666, c20b205a).** Decyzje D1–D6 (§6) przyjęte 2026-11-24 — wszystkie warianty zalecane.
**M0–M2 wdrożone w 1.7.667** (odstępstwa: przebrany stojący nie oddycha tylko w ciemności — w snopie latarki oddycha głęboko, jako
sygnał obok połysku oczu; solo bez innych postaci i bez bota etykieta to kryptonim spoza drużyny z `FALLBACK_NAMES`). Kolejność wg rekomendacji z analizy: najpierw M0–M2
(pomiar i przebranie, które trzyma się na ekranie), potem rdzeń M3–M6 (zwłoki w świecie i Mimik udający zwłoki — główna zmiana
rozgrywki, działa w solo), dalej M7 (przemiana i ruch) i M8 (echo krzyku). M9 (powalony kolega) czeka na sesje co-op.
Uwaga użytkownika (2026-11-23), wpisana w §4 i etapy M3–M5: **żeby leżący Mimik nie wzbudzał podejrzeń, w świecie muszą zostawać
zwłoki** — dziś nie ma ich wcale, więc jedyne zwłoki w grze od razu byłyby Mimikiem.

## 1. Skąd to

Użytkownik poprosił o analizę Mimika (postać, mechanika, animacje) i propozycje usprawnień. Analiza: kod (`enemy_mimic.gd`,
`enemy_defs.gd`, `enemy.gd`, SPEC `mimik` w `enemy3d.gd`, `enemy_motion.gd`, `world_bars.gd`), dzienniki sesji gracza (81 plików,
misje 1.2 i 1.3 od 1.7.211 do 1.7.663) i zrzuty `--shotmon=b --shotlive [--shotsleep]` (izolowany profil QA).

## 2. Stan obecny

### 2.1 Mechanika (z kodu)

- **Dane** (`enemy_defs.gd`): 70 HP, prędkość 95 px/s (= gracz, `player.gd SPEED`), cios 2, zapowiedź 0,4 s, `wake_near` 46 px (2,9 m;
  kucający 1,4 m), `hear` 0 (hałas go nie budzi), `sight` 220 px. 10 XP, 10 złomu.
- **Przebranie** (`enemy_mimic.gd`): nieobudzony stoi w animacji `idle` (nie śpi), nie przygasa, `asleep_lod() = false`.
  Etykieta nad głową (`disguise_label`): w co-op kryptonim innego człowieka z drużyny, sam albo z botem — „P2”–„P4”
  (numer z `instance_id`). `world_bars.gd` rysuje ją kolorem `MIMIC_COL` (szarozielony, alfa 0,45), bez serduszek.
- **Wabienie** (`tick_asleep`): co 6–10 s, gdy najbliższy gracz jest 70–340 px (4,4–21 m) od niego, `_mimic_call` gra próbkę
  `player_hurt` (stęknięcie bólu) w jego miejscu. Nic poza dźwiękiem.
- **Demaskacja** = zwykłe `wake()`: podejście na `wake_near`, **snop latarki** (`Lights.flashlight_on`: 8 m, ±24°), trafienie,
  **krzyk gracza G** (`hear_scream`, 25 m), alarm Podsłuchacza. `on_wake`: hałas 6 („enemy”), krzyk `_scream_fx` o wysokości 0,85,
  zapowiedź 0,35 s bez celu (nieprzerywalna), potem zwykły pościg. Budzi też wrogów w `SIBLING_WAKE_RADIUS` (140 px).
- **Bot** pomija nieobudzonych (`is_threat`), więc nie demaskuje Mimika strzałem.
- **GDD §7.1** obiecuje kontrę „Sprawdź pingiem/kodem drużyny” i udawanie „radia kolegi” — w kodzie nie ma ani pingu, ani radia.
- Rozmieszczenie: 1 na 1.2 (bagno, rozstaj), 2 na 1.3.

### 2.2 Widok 3D i animacje (z kodu i zrzutów)

- Model gracza `art/char3d/mpfb/male_scav.glb` (SPEC `mimik`), chód `walk_clip: human`, obrót jak gracz (`turn`), bez nasłuchu (`no_heed`).
- **Puste ręce** — gracze zawsze trzymają broń, więc to najmocniejszy sygnał przebrania, choć nie ma go w GDD.
- **Oczy**: dwie kulki r = 1,2 cm, `SHADING_MODE_UNSHADED`, żółte — świecą stale, także w przebraniu i w pełnym świetle.
- **Oddech**: SPEC `idle` nie ma `breath`, więc działa domyślny okres 2,4 s (`idle_life.gd DEFAULT`), a GDD wymienia „brak oddechu”
  jako sygnał. Tik `twitch` to tik potwora.
- **Po demaskacji nic się nie zmienia w wyglądzie**: ten sam model, ludzki chód, te same proporcje. Na zrzucie po demaskacji Mimik
  idzie do gracza jak żołnierz z małymi żółtymi oczami.
- Klip `reveal_grab` (`enemy_motion.gd`) to każdy cios, nie tylko pierwszy z przebrania.
- Pułapka narzędzia: bez `--shotlive` fizyka wroga jest zamrożona i Mimik stoi w pozie lotu (przykurczony) — fałszywy obraz.

### 2.3 Dane z dzienników sesji

| Miara | Wartość |
|---|---|
| Misje 1.2 z licznikiem rodzajów (`players.kinds`) | Mimik zabity w 28 z ok. 30 |
| Misje 1.3 z licznikiem | 2 Mimiki zabite w 3 z 4 |
| Powalenia przez Mimika (`down.source = "mimik"`) | **1** na ok. 50 misji 1.2 i 1.3 (1.7.469) |
| Kto zabija | zawsze człowiek (P1) |

Brak zdarzenia demaskacji w dzienniku — nie wiadomo, co go odsłania i z jakiej odległości.

### 2.4 Problemy

| # | Problem | Skutek |
|---|---|---|
| P1 | Latarka (8 m) demaskuje, zanim wabienie (4,4–21 m) doprowadzi gracza na 2,9 m | Pułapka nigdy się nie zamyka; Mimik biegnie z 8 m z prędkością gracza prosto pod lufę |
| P2 | Wołanie to stęknięcie z miejsca Mimika | Ostrzega, zamiast wabić: gracz wie, gdzie i czego się spodziewać |
| P3 | Krzyk G budzi go jak każdego wroga | Jeden krzyk czyści wszystkie przebrania w 25 m |
| P4 | W solo nie ma kogo udawać („P4” bez drużyny) | Główna forma gry (0 sesji co-op w dziennikach) nie ma pułapki wcale |
| P5 | Puste ręce, szara etykieta, stale świecące oczy | Przebranie widać z drugiego końca ekranu |
| P6 | Demaskacja bez zmiany wyglądu i ruchu | Brak momentu grozy; „potwór” wygląda jak żołnierz |
| P7 | Brak kontry z GDD (ping, kod) | Gracz nie ma narzędzia „sprawdzam”, tylko latarkę, która od razu rozstrzyga |
| P8 | Brak zwłok w świecie (ciała wrogów znikają po 0,8 s: `CORPSE_HOLD` + `CORPSE_SINK`) | Przebranie za zwłoki (M5) byłoby jedynymi zwłokami w grze — od razu podejrzane |

## 3. Zasady kierunku

1. **Pułapka zamyka się w chwili zobowiązania gracza** (przeszukuje, podnosi, stoi tuż obok), a nie na dystansie strzału.
2. **Sygnały uczciwe i do nauczenia**: każdy wariant przebrania ma 2–3 stałe sygnały widoczne dla uważnego gracza; żaden nie jest
   widoczny z drugiego końca ekranu.
3. **Solo pierwsze**: rdzeń działa bez drugiego człowieka; warianty co-op są dodatkiem.
4. **Przebranie potrzebuje tła**: Mimik udaje coś, co w świecie występuje często i bez niego (zwłoki — §4; ludzie — tylko w co-op).
5. Symulacja 2D na serwerze, obraz tylko 3D (CLAUDE.md); bez nowych walut i stanowisk (GDD §16.0a) — łup ze zwłok to istniejące
   złom, amunicja, baterie.

## 4. Zwłoki w świecie (uwaga użytkownika)

Dziś w grze nie ma ani jednych zwłok. Mimik leżący jako jedyne ciało na mapie zdradziłby się sam. Dlatego zwłoki wchodzą jako
**osobna warstwa świata przed Mimikiem** (M3–M4) i dopiero potem Mimik zaczyna je udawać (M5).

- **Kto**: Patrol Siedem z 1.1 „Zaginiony Patrol” (`RADIO` w `z1_m1.gd`: „Patrol Seven, do you read?”) — żołnierze patrolu
  rozproszeni po Strefie I; na 1.2 także obsługa radiostacji, na 1.3 górnicy. Fabuła jest już w grze, zwłoki ją tylko pokazują.
- **Ile**: co najmniej **4 prawdziwe zwłoki na każdego Mimika-zwłoki na mapie** (D2), w sumie ok. 5–7 na mapę. Na 1.1 zwłoki
  bez Mimika — tam gracz uczy się, że zwłoki = drobny łup i informacja (nauka przed 1.2).
- **1.1**: nieśmiertelniki leżą przy zwłokach patrolu (zamiast samych na ziemi) — cel misji prowadzi gracza do ciał od pierwszej
  misji, więc podchodzenie do zwłok staje się nawykiem.
- **Wygląd**: modele MPFB z `art/char3d/mpfb/` w innym stroju niż operatorzy (mundur patrolu, kombinezon technika, strój górnika),
  bez postaci od zera. Pozy: na plecach, na boku, na twarzy, siedzący oparty o drzewo albo ścianę. Pod każdym prawdziwym ciałem plama
  krwi albo ziemi (dekal), część przysypana igliwiem. Bez dosłownej makabry.
- **Pozy wypiekane raz** (szkielet ustawiony przy budowie, potem bez przeliczania co klatkę), więc koszt zbliżony do rekwizytu.
  Mimik-zwłoki używa **tych samych póz, modeli, materiału i cienia** — różnią się tylko sygnały z §5.3.
- **Przeszukanie** [E] (trzymanie ok. 1,2 s, jak wyjmowanie taśmy K4b): drobny łup z istniejących (złom 3–6, naboje, bateria 4,5 V,
  czasem notatka z radia) albo nic (D3). Przeszukane ciało zmienia pozę o szczegół (otwarty plecak, odwrócona kieszeń) i nie daje
  więcej. Stan na serwerze, w migawce dla dołączającego; po wipe'ie zostaje przeszukane (jak skrytki, FUN_PLAN).
- **Bot nie przeszukuje** (jak z taśmami) — zwłoki to decyzja człowieka.
- **Nie zatrzymujemy ciał wrogów** — nie pomagają przebraniu (inna sylwetka), a kosztują. Ewentualnie w I5 (`IDLE_PLAN.md` C3:
  „Rzeźnik przy zwłokach”) — scenka może korzystać z tych samych modeli zwłok.

## 5. Etapy

### M0 — pomiar (dziennik)

- Zdarzenie `mimic_reveal` w dzienniku sesji: `cause` (`light`, `near`, `hit`, `scream`, `alarm`, `search`), `dist` (px do najbliższego
  człowieka), `calls` (ile wołań przed demaskacją), `disguise` (`stand` / `corpse`), czas od startu misji.
- `mimic_grab` (od M6): kto, czy uwolniony, czym, ile obrażeń.
- `corpse_search` (od M4): mapa, id zwłok, łup, czas trzymania.
- Test: `--enemytest` — każda przyczyna demaskacji zapisuje jedno zdarzenie z poprawną przyczyną.

### M1 — przebranie stojące, które trzyma się na ekranie (tylko obraz)

- **Broń w rękach**: model broni naśladowanego kolegi (w solo M-83), trzymanej nisko, lufą w dół; Mimik nigdy nie celuje
  (sygnał: „kolega” nie unosi broni, gdy wszyscy wokół strzelają).
- **Etykieta jak gracza**: ten sam krój i kolor co imiona graczy; w solo kryptonim innej postaci z ekranu OPERATORZY
  (`user://characters`), a bez innych postaci — imię bota. Sygnałem zostaje brak serduszek.
- **Oczy**: bez stałego świecenia; połysk jak u zwierzęcia tylko w snopie latarki albo przy flarze (emisja wg światła padającego).
- **Bez oddechu** (`idle.breath` = 0 albo osobna flaga), tiki tylko `look`; „twitch” dopiero po demaskacji.
- Test: `tools/test_idle_life.gd` (Mimik w przebraniu: zerowy oddech), zrzut przebranie / gracz obok siebie (`--shotmon=b --shotlive --shotsleep`).

### M2 — latarka nie rozstrzyga od razu (symulacja)

- Snop na przebranym Mimiku **nie demaskuje** natychmiast: Mimik odwraca twarz od światła (widok) i demaskuje się po
  ok. 1,5 s ciągłego światła na nim (licznik na serwerze, zeruje się po 0,5 s ciemności) albo przy `wake_near`.
- Wabienie zostaje dla przebrania stojącego, ale zamiast stęknięcia — wezwanie pomocy (krótka kwestia, z trzaskiem radia, kierunek
  rozmyty); w co-op głos z puli kryptonimu naśladowanego.
- Test: `--enemytest` — snop krótszy niż próg nie budzi, dłuższy budzi; `wake_near` dalej budzi od razu.

### M3 — zwłoki w świecie (obraz + dane map)

- Dane mapy `CORPSES := [[kol, wiersz, poza, strój, flagi], …]` (jak `STRONGBOXES`), scena zwłok w widoku 3D (`corpse3d.gd`),
  wypiekane pozy, dekal plamy, przysypanie.
- Rozmieszczenie: 1.1 (6 przy nieśmiertelnikach + 0–2 bez), 1.2 i 1.3 po 5–7, w tym gniazda z flagą `mimic` (D4).
- Bez kolizji i bez wpływu na nawigację; nie w pasach wejść stref wydobycia, nie na trasach cichego przejścia w miejscach, gdzie
  zasłaniałyby znaczniki.
- Test: `tools/test_corpses.gd` — dane (pola, stroje, pozy), ciało na podłodze (skóra nie pod gruntem, nie w powietrzu), w obrysie
  kafla, z dekalem, poza wejściami stref; `--maptest` bez zmian. Zrzut każdej pozy i stroju do akceptacji.

### M4 — przeszukiwanie zwłok (symulacja)

- [E] trzymane ok. 1,2 s przy ciele (akcja w `actions.gd`, podpowiedź w pasku akcji, tłumaczenia), puszczenie przerywa, hałas
  szelestu mały.
- Łup wg D3, stan „przeszukane” na serwerze (RPC, migawka dla dołączającego, wipe, punkt kontrolny bossa), poza po przeszukaniu.
- Nieśmiertelnik na 1.1 = przeszukanie zwłok patrolu (cel misji), bez zmiany liczby celów.
- Test: `--corpsetest` (albo w `--funtest`) — trzymanie, przerwanie, odległość, łup, bot nie przeszukuje, dołączający, wipe;
  `tools/test_net_session.sh` — przeszukane u klienta i dołączającego.

### M5 — Mimik udaje zwłoki (symulacja + obraz)

- Na mapach z gniazdami `mimic` serwer losuje z ziarna misji, **które** zwłoki to Mimik (D4) — gracz nie nauczy się miejsca na pamięć.
  `Y` w mapie zostaje dla przebrania stojącego (D5).
- Mimik-zwłoki: ta sama poza, model, strój, materiał i cień co prawdziwe zwłoki w tym miejscu; bez etykiety; nie woła.
- **Sygnały** (stałe, do nauczenia; kodeks po pierwszej demaskacji je opisuje):
  1. **brak plamy pod ciałem** (prawdziwe zawsze ją mają),
  2. **połysk oczu** w snopie latarki (oczy otwarte; u prawdziwych matowe),
  3. **oddech** widoczny, gdy świecisz na niego dłużej niż ok. 1 s (klatka piersiowa unosi się — „przyłapany”).
- **Demaskacja**: start przeszukiwania [E] (Mimik łapie od razu albo po 0,3 s — D6), przejście tuż nad nim (≈ 0,6 m, także bot),
  trafienie, ok. 2,5 s ciągłego snopu (dłużej niż przy stojącym — leżący „wytrzymuje” światło), krzyk G wg M8.
- Zabity Mimik-zwłoki zostawia łup zwłok, które udawał (nagroda za rozpoznanie).
- Test: `--enemytest` / `--corpsetest` — losowanie gniazda z ziarna (to samo u każdego peera, inne między misjami), brak plamy,
  demaskacja przy [E], przy przejściu, przy strzale, licznik światła; prawdziwe zwłoki nigdy się nie budzą.

### M6 — chwyt z przebrania (symulacja)

- Pierwszy atak po demaskacji z bliska to **chwyt**: `player.grabbed` (jak Pijawka — przypięty, może strzelać i bić), ok. 1,5 s,
  obrażenia 1 na początku i 1 na końcu (do strojenia), potem odrzut i zwykła walka.
- Uwolnienie wcześniej: cios maczetą albo kilofem chwyconego, trafienie Mimika przez kolegę lub bota za ≥ 20 obrażeń,
  ogłuszenie (strzelba, harpun).
- Kolejne ciosy zwykłe (`reveal_grab` przemianowany na `grab_hold` dla chwytu, osobny lżejszy klip zwykłego ciosu).
- Test: `--enemytest` — chwyt tylko pierwszy, czas, uwolnienie każdą drogą, bot pomaga; `test_weapons.sh` / sieć — `grabbed` u klienta.

### M7 — przemiana i ruch po demaskacji (obraz + strojenie)

- Klip przemiany ok. 0,9 s zamiast 0,35 s: ze stania — szarpnięcie, głowa skręca się za daleko, przedramiona wydłużają się
  (skala kości ×1,3–1,5), plecak spada i zostaje na ziemi jako ślad; z leżenia — wstaje „wstecz” (łuk pleców, bez podparcia rąk).
  W tym czasie +25% przyjmowanych obrażeń (okno na kontrę).
- Chód `lope` (pochylony, długi krok, ręce nisko), zryw 1,5 s do ok. 110 px/s po przemianie, potem 95.
- Materiał po przemianie: zszarzały mundur, blada skóra z żyłami (parametr istniejącego shadera), oczy jaśniejsze i większe.
- Test: `tools/test_proportions.gd` (hitbox kontra model po wydłużeniu), stykówka klipu, `test_gait_speed.gd`.

### M8 — krzyk G to test „kto to?” (symulacja + dźwięk)

- Krzyk gracza **nie demaskuje** Mimika; Mimik odpowiada echem tego krzyku po ok. 0,5 s, odrobinę za nisko, z jego miejsca
  (stojący — głosem, leżący — drgnięcie ciała i stłumiony głos). To kontra z GDD („kod drużyny”) bez nowego systemu
  i powód, żeby używać krzyku (dziś nieużywany).
- Test: `--enemytest` — krzyk budzi innych, Mimika nie; echo raz na krzyk, z opóźnieniem i niższym głosem.

### M9 — powalony kolega (co-op, po sesjach co-op)

- W co-op Mimik może udawać **powalonego kolegę**: leży ze znacznikiem powalenia i kryptonimem naśladowanego; demaskuje się przy
  próbie podniesienia. Sygnał: prawdziwy kolega jest też w HUD drużyny (stan, strzałka przy krawędzi ekranu) — wystarczy sprawdzić.
- Wchodzi dopiero, gdy dzienniki pokażą sesje co-op (dziś 0).

## 6. Decyzje

| # | Pytanie | Warianty | Zalecane |
|---|---|---|---|
| D1 | Kim są zwłoki | a) Patrol Siedem + obsługa radiostacji (1.2) + górnicy (1.3); b) tylko patrol | **a)** — każda mapa ma swoich, patrol spina Strefę I |
| D2 | Gęstość | a) ≥ 4 prawdziwe na Mimika-zwłoki; b) ≥ 2 | **a)** — przy 2 rzut monetą, przy 4 przeszukiwanie się opłaca, a Mimik zaskakuje |
| D3 | Łup ze zwłok | a) ok. 60% drobny łup, 40% nic; b) zawsze coś; c) nic | **a)** — opłaca się podejść, ale nie zawsze; bez nowych walut |
| D4 | Ile Mimików-zwłok | a) 1 na 1.2, 1–2 na 1.3, losowane z gniazd `mimic`; b) stała pozycja | **a)** — losowanie z ziarna misji, nie da się nauczyć na pamięć |
| D5 | Przebranie stojące | a) zostaje (`Y`), w solo z etykietą postaci z OPERATORÓW; b) tylko w co-op; c) usunąć | **a)** po M1–M2; ocenić po M0 — jeśli w solo nadal nikt się nie nabiera, przejść na b) |
| D6 | Kiedy łapie przy przeszukiwaniu | a) od razu przy starcie [E]; b) po 0,3 s | **b)** — gracz zdąży zobaczyć ruch ręki, ale nie zdąży puścić |

## 7. Cel i pomiar

- Przed: 1 powalenie na ok. 50 misji, Mimik ginie bez zagrożenia w prawie każdej misji.
- Cel po M5–M6: chwyt albo powalenie w **20–35%** spotkań z Mimikiem (`mimic_reveal` + `mimic_grab`), a nadal ginie w większości
  misji; demaskacja przez latarkę z dystansu (`cause = light`, `dist` > 100 px) w mniej niż połowie spotkań.
- Zwłoki: na 1.1 gracz przeszukuje co najmniej połowę zwłok poza nieśmiertelnikami (`corpse_search`) — inaczej przynęta nie działa
  i trzeba podnieść łup (D3).
- Ocena na dziennikach po co najmniej 10 misjach 1.2 i 5 na 1.3 od wydania M5.

## 8. Ryzyka

- **Zwłoki jako szum wizualny** — za dużo ciał spłaszcza grozę i zasłania znaczniki; trzymać się 5–7 na mapę i miejsc poza pasem walki.
- **Sygnały za słabe w 3D z kamery gry** (plama, połysk) — zrzuty akceptacyjne w snopie latarki i bez niego przed M5.
- **Niesprawiedliwy chwyt** w solo bez bota — dlatego maczeta/kilof uwalnia, a chwyt trwa krótko.
- **Koszt** — zwłoki z wypiekaną pozą i bez cienia od świateł poza wybranymi (`test_shadow_casts.gd`); pomiar FPS na 1.2.
- **Spójność z GDD §7.1** — opis Mimika i kontry do przepisania w M5 (i README / kodeks).

## 9. Pliki

- `scripts/enemy_mimic.gd` (tryby przebrania, licznik światła, echo, chwyt), `scripts/enemy_defs.gd` (dane), `scripts/enemy.gd`
  (demaskacja z przyczyną, `hear_scream` dla Mimika), `scripts/enemy3d.gd` (SPEC `mimik`: broń, oczy, oddech, przemiana, `lope`),
  `scripts/enemy_motion.gd` / `char_clips.gd` (klipy `grab_hold`, przemiana, `lope`), `scripts/world_bars.gd` (etykieta).
- Nowe: `scripts/corpse.gd` (+ `.gd.uid`) — zwłoki w symulacji (stan, przeszukanie), `scripts/corpse3d.gd` — widok,
  `tools/test_corpses.gd`; dane `CORPSES` w `scripts/maps/z1_m1.gd`, `z1_m2.gd`, `z1_m3.gd`.
- `scripts/actions.gd` (przeszukanie), `prototype/translations/ui.csv`, `scripts/session_log.gd` (zdarzenia M0),
  `scripts/codex.gd` (sygnały w kodeksie), `GDD.md` §7.1 i §9, `prototype/README.md`, `CHANGELOG.md`.
