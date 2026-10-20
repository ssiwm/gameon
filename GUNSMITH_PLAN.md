# Rusznikarnia — plan rozbudowy broni i ulepszeń

Stan wyjściowy: `main` cc178a6 (1.7.313). Dokument to **propozycja**; wdrożone są **etap 0** (1.7.316, `prototype/WEAPONS.md` §14) i główna część **etapu 1** (1.7.317, §15).
Zasada nadrzędna: broń zachowuje się jak prawdziwa, ale tempo gry zostaje jak w Contrze (misja 8–15 min, filar 7 „czucie przed zawartością”).

---

## 1. Co jest teraz

### 1.1 Mocne strony (zostają)

- **Jedno źródło prawdy.** `WeaponDef` (~60 pól) + tabele w `weapons.gd`; ulepszenia to modyfikatory pól (`upgrades.gd`), więc kontroler, HUD i pociski czytają ulepszoną broń bez zmian. Na tym da się zbudować cały nowy system.
- **Hałas jako waluta** (rozgrzanie lufy → koszt strzału, tryb serii, błysk lufy budzący ćmy). To najlepsza mechanika broni w grze i nowy system ma ją wzmacniać.
- **Serwer rozstrzyga**, seed rozrzutu, wspólny zapas autorytatywny na serwerze, testy `--weapontest`.
- Realizm już poprawiony w 1.7.310–1.7.313: szybkie kule ze smugami, łuski z okna wyrzutowego, P-83 z magazynkiem 8, SPREAD-12 z bębnem, bełt z prawdziwym g, broń nie przesuwa strzelca.
- Oględziny broni w 3D ([F]), gabloty, modele budowane skryptem (`gun_proc.py`) — gotowe miejsce na widoczne części.

### 1.2 Słabości systemu ulepszeń

| # | Problem | Gdzie | Skutek dla gry |
|---|---|---|---|
| U1 | **Liniowe 3 poziomy**, stała kolejność, każdy kupuje to samo | `upgrades.gd` `TIERS` | Brak decyzji i tożsamości broni; po 3/3 broń jest „skończona” |
| U2 | **Każde ulepszenie to czysty zysk** (zero kosztów) | całe `TIERS` | Zakup to formalność, nie wybór |
| U3 | **Niezgodne z realiami**: „Tuned action +15% obrażeń” (M-83), „Match barrel +20% obrażeń” (P-83), „Hair trigger +15% obrażeń” (PELLET-8) | [upgrades.gd:22](prototype/scripts/upgrades.gd:22), [:27](prototype/scripts/upgrades.gd:27), [:37](prototype/scripts/upgrades.gd:37) | Lufa daje celność, spust — szybkość reakcji; obrażenia daje amunicja |
| U4 | **Amunicja udaje ulepszenie**: podpalające śruciny, ogłuszające pociski, pocisk przebijający ścianę, kasetowe granaty to typy naboi, a są „poziomem 3” na zawsze | `TIERS` spread12/srut8/widmo1/gniew4 | Nie da się wybrać amunicji pod misję |
| U5 | **Ulepszenia niewidoczne** — tłumik nie pojawia się na lufie, bęben RPK na broni | `char3d.gd`, `gun_proc.py` | Zero imersji z zakupu |
| U6 | **Poziomy wspólne dla drużyny** (`Weapons.levels` = `Scrap.levels`) | [weapons.gd:207](prototype/scripts/weapons.gd:207) | Dwóch graczy z M-83 ma identyczną broń; brak „mojej” broni |
| U7 | Ulepszenia tylko z warsztatu, za złom | `scrap.gd` | Misja nie daje znalezisk związanych z bronią — mniej emocji z łupu |
| U8 | Skończona pula zakupów (36) | — | Złom szybko traci sens (brak ujścia długoterminowego) |

### 1.3 Słabości samej broni (realizm i imersja)

| # | Problem | Gdzie | Jak jest naprawdę |
|---|---|---|---|
| B1 | Amunicja **na broń**, nie na kaliber; jeden rodzaj naboju | `Arsenal`, `reserve_*` | SPREAD-12 i PELLET-8 to ten sam nabój 12/70; AKM ma PS, US (poddźwiękowy), T-45 (smugowy), BZ (przeciwpancerno-zapalający) |
| B2 | Przeładowanie **dopełnia** magazynek nabojami z zapasu | [weapon_controller.gd:809](prototype/scripts/weapon_controller.gd:809) | Wymienia się magazynek; resztki zostają w starym. Brak naboju w komorze (30+1) |
| B3 | Odrzut = losowy stożek (bloom) + szarpnięcie kamery | [weapon_controller.gd:153](prototype/scripts/weapon_controller.gd:153) | Lufa podrzuca się przewidywalnie w górę i losowo w bok; kucanie i oparcie o przeszkodę wyraźnie pomagają |
| B4 | Rozgrzanie lufy wpływa tylko na hałas | `_heat` | Gorąca lufa: falowanie powietrza (miraż), dym z lufy, gorszy rozrzut, przy tłumiku — głośniej |
| B5 | Brak stanu technicznego i zacięć | — | Brud, błoto, woda, przegrzanie → niewypał, niedosłanie, zacięcie łuski. Dla horroru: najlepsze 2 sekundy napięcia |
| B6 | P-83 leci 1500 px/s ≈ 440 m/s | [weapons.gd:78](prototype/scripts/weapons.gd:78) | 9×18 mm ma ok. 315 m/s — **poddźwiękowy** (ok. 1070 px/s w skali gry). Ma to sens dla tłumika |
| B7 | WRATH-4 wybucha od razu po wylocie | [weapons.gd:129](prototype/scripts/weapons.gd:129) | Granat 40 mm uzbraja się dopiero po 14–27 m lotu (VOG-25: 10–40 m) — strzał z bliska to tępe uderzenie |
| B8 | FALCON-6 (Gyrojet) leci stałą prędkością | [weapons.gd:142](prototype/scripts/weapons.gd:142) | Gyrojet wychodzi z lufy powoli i przyspiesza przez kilkanaście metrów — z bliska jest słaby |
| B9 | HKM-9 pali równo przez 8 s | [weapons.gd:116](prototype/scripts/weapons.gd:116) | Miotacze (ROKS-3, LPO-50) strzelają porcjami po 1–3 s, ciśnienie spada, zasięg maleje |
| B10 | Przebijanie liczy cele, nie materiał | `Combat.trace` | 7,62×39 przechodzi przez deskę, skrzynię i chudego Trzoska; nie przez beton |
| B11 | Strzał w locie (skok) celny jak na ziemi | `spread_extra` | Strzał w powietrzu jest wyraźnie mniej celny |
| B12 | HUD zawsze podaje dokładny stan naboi | `hud.gd` | Żołnierz zna stan magazynka w przybliżeniu — opcjonalnie dla „Weterana” |

Przelicznik używany niżej: prędkość w grze ≈ prędkość prawdziwa × 3,4 px/s na m/s (M-83: 715 m/s → 2400 px/s). Prędkość dźwięku 343 m/s → **ok. 1165 px/s** — próg „poddźwiękowy” w skali gry.

---

## 2. Propozycja w skrócie

Pięć warstw, każda osobno do wdrożenia i wyłączenia:

1. **Amunicja według kalibru** — typy naboi wybierane pod misję (zamiast „poziomu 3”).
2. **Części w gniazdach** — zamiast 3 liniowych poziomów: lufa, wylot, mechanizm, zasilanie, kolba, celownik, oświetlenie. Każda część ma zysk **i koszt**, i **widać ją na modelu**.
3. **Obsługa broni** — odrzut z przewidywalnym podrzutem, oparcie broni, nabój w komorze, dwa rodzaje przeładowania, gorąca lufa.
4. **Stan techniczny i zacięcia** — rzadkie, uczciwe, z szybkim „przeładuj, by usunąć”; czyszczenie w kryjówce.
5. **Wprawa i historia broni** — broń gracza nabiera charakteru: nacięcia na kolbie, ślady użycia, drobne bonusy z doświadczenia.

Do tego: **strzelnica w kryjówce** (sprawdzanie zestawów) i **elaboracja** (własna amunicja specjalna za złom) jako trwałe ujście złomu.

---

## 3. Amunicja według kalibru

### 3.1 Kalibry

| Kaliber | Bronie | Zapas drużyny |
|---|---|---|
| 7,62×39 | M-83 (AKM) | wspólny jak dziś |
| 9×18 | P-83 | ∞ dla nabojów zwykłych (ratunek zostaje) |
| 12/70 | SPREAD-12, PELLET-8 | **wspólny dla obu strzelb** — nowa decyzja w drużynie |
| 40 mm | WRATH-4 | wspólny |
| ogniwo NiCd | LR-7, SPECTER-1 | wspólny — laser i działo cewkowe walczą o te same baterie |
| mieszanka zapalająca | HKM-9 | wspólny |
| rakieta 13 mm | FALCON-6 | wspólny |
| bełt | SINEW-6 | do odzysku jak dziś |

### 3.2 Typy naboi (zgodne z realiami 1987)

Typ wybiera się w ekwipunku przed misją i klawiszem **T** w misji (zmiana obowiązuje od **następnego** magazynka — realistycznie i bez nowego RPC na strzał). Naboje zwykłe są w zapasie; specjalne trzeba znaleźć albo elaborować (§7).

| Kaliber | Typ | Zmiana względem zwykłego | Koszt / ograniczenie |
|---|---|---|---|
| 7,62×39 | **PS** (zwykły) | — | — |
| | **US** poddźwiękowy | prędkość ×0,42 (≈1000 px/s), obrażenia ×0,75, spadek obrażeń od połowy zasięgu; **bez trzasku naddźwiękowego**: hałas ×0,85, a z tłumikiem ×0,3 | Wolniejsza kula — trudniej trafić skoczka; mniejszy odrzut kamery |
| | **T-45** smugowy | jasna smuga przez cały lot, łatwiej korygować ogień | Smuga widoczna dla wrogów: przyciąga ćmy jak błysk lufy; w ciemności zdradza strzelca |
| | **BZ** przeciwpancerno-zapalający | pancerz Wołka/Rzeźnika ignorowany w 70%, przebija deskę i skrzynię, krótkie podpalenie | Rzadki (skrzynki, elity); głośniejszy trafienie w metal |
| 9×18 | zwykły | już poddźwiękowy po poprawce B6 | — |
| 12/70 | **loftki** (zwykły) | jak dziś | — |
| | **Breneka** (pocisk jednolity) | 1 pocisk, obrażenia ×4 śruciny, rozrzut ≈ 0, zasięg ×2, przebija deskę | Bez rozrzutu — trzeba trafić; silny odrzut kamery |
| | **zapalające** | dzisiejsze „Incendiary shells” (podpalenie 2 s) | Słabsze śruciny (×0,7); zapala olej i siano na mapie |
| | **gumowe** (jak „Wołna-R” z KS-23) | dzisiejsze „Concussion shells”: ogłuszenie, odrzut, mało obrażeń | Nie zabija Trzoska jednym strzałem |
| | **strzałki** | przebija 1 cel, mniejszy rozrzut | Mniej obrażeń w ciało |
| 40 mm | **odłamkowy** (zwykły) | z odległością uzbrojenia (§5.4) | — |
| | **kartaczowy** | stożek śrucin z bliska — działa poniżej odległości uzbrojenia | Bez wybuchu, nie niszczy gniazd |
| | **oświetlający** | flara na spadochronie: światło 20 m przez 40 s | Hałas wystrzału; Ślepce ignorują, ćmy lecą |
| | **dymny** | chmura jak granat dymny | — |
| | **kasetowy** | dzisiejsze „Cluster warheads” | Rzadki |
| NiCd | zwykłe / **zimne** | — | Mróz (pogoda z radiostacji) obniża pojemność o 20–30% — bateria z kieszeni przy ciele działa lepiej (opcjonalnie) |
| SPECTER-1 | **rdzeń wolframowy** | dzisiejsze przebicie ściany | Rzadki |

Zasada: wszystko, co dziś jest „poziomem 3 zmieniającym zachowanie” na podstawie amunicji, staje się typem naboju. Gracz wybiera pod misję, a nie kupuje raz na zawsze.

---

## 4. Części w gniazdach (zamiast liniowych poziomów)

### 4.1 Gniazda

| Gniazdo | Co zmienia | Przykład kosztu |
|---|---|---|
| **Lufa** | celność, prędkość, długość | dłuższa = celniej i szybciej, ale dłuższe dobycie i broń „zahacza” o ścianę (`muzzle_pos`) |
| **Wylot** | hałas, błysk, podrzut | tłumik: cicho, ale +długość, +masa, gorąca puszka głośnieje, więcej brudu w mechanizmie |
| **Mechanizm** (spust, sprężyna, zamek) | tempo, niezawodność, czas reakcji | mocniejsza sprężyna = pewniejsze działanie w błocie, ale wolniejsze tempo |
| **Zasilanie** | pojemność, czas przeładowania | bęben 75 = długo strzelasz, ale +masa i +1,2 s przeładowania |
| **Kolba / chwyt** | podrzut, dobycie, rozrzut w ruchu | kolba składana = szybkie dobycie, większy podrzut |
| **Celownik** | rozrzut z dystansu, czytelność w ciemności | noktowizor NSPU: widzisz w mroku, ale żarzy się na zielono i jest ciężki |
| **Oświetlenie** | latarka na taśmie | widzisz cel, ale to światło: GDD §8.3 — ściąga wzrok |

Na broń 3–5 gniazd z 2–3 częściami w każdym (w tym część fabryczna). Zasada projektowa sprawdzana testem: **każda część ma co najmniej jeden modyfikator na minus** (poza fabryczną).

### 4.2 Przykład: M-83 (AKM)

| Gniazdo | Fabryczna | Opcja A | Opcja B |
|---|---|---|---|
| Wylot | kompensator AKM (skośny — ściąga podrzut w bok) | **PBS-1** (prawdziwy tłumik AKM do naboju US): hałas ×0,6 (z US ×0,3), błysk ×0,1 / +0,2 s dobycia, broń dłuższa o 0,2 m, puszka się grzeje | **płomieniotłumik**: błysk ×0,3 (nie budzi ciem) / podrzut +10% |
| Zasilanie | magazynek 30 | **magazynek RPK 40**: +10 / +0,15 s przeładowania | **bęben RPK 75**: +45 / +1,2 s przeładowania, +0,1 s dobycia, wolniejszy bieg o 5% |
| Lufa | 415 mm | **lufa RPK 590 mm**: rozrzut ×0,75, prędkość +8% / dobycie +0,15 s, dłuższa broń | **skrócona (AKS-74U-styl)**: dobycie ×0,7, w ruchu celniej / rozrzut ×1,3, zasięg ×0,8, głośniej |
| Kolba | drewniana | **składana AKMS**: dobycie ×0,8 / podrzut +20% | — |
| Celownik | szczerbinka | **1P29 (kolimator, druga połowa lat 80.)**: rozrzut na dystansie ×0,85 / +masa | **NSPU**: widok w ciemności w stożku przed lufą / zielona poświata zdradza, +masa |

Trzy przykładowe zestawy, które wychodzą same z siebie:
- **Zwiadowca**: PBS-1 + US + kolba składana → prawie bezgłośny, słabszy, do skradania.
- **Szturm**: bęben 75 + kompensator + PS → długi ogień, wolne przeładowanie, głośno.
- **Nocny strzelec**: lufa RPK + NSPU + T-45 → celny w mroku, ale świeci.

### 4.3 Pozostałe bronie (szkic)

| Broń | Najciekawsze części (zysk / koszt) |
|---|---|
| P-83 | gwintowana lufa + tłumik (z 9×18 naprawdę cicho, bo nabój poddźwiękowy) / dłuższy, zahacza; magazynek 12 / wystaje, wolniej z kabury |
| SPREAD-12 | **czok** (zmienia skupienie loftek; dziś „+15% obrażeń” → teraz tylko skupienie) / gorzej z bliska; magazynek 8 zamiast bębna / szybkie przeładowanie, mało naboi |
| PELLET-8 | **przedłużony magazynek rurowy** +2 / dłuższa i cięższa; kolba z gumą / mniejsze szarpnięcie, wolniejsze dobycie; **wyważanie drzwi** jako cecha amunicji, nie ulepszenia |
| LR-7 | soczewka skupiająca (+przebicie) / wiązka nagrzewa się szybciej; chłodnica / +masa, bzyczy |
| HKM-9 | dysza długa (+zasięg) / szerszy rozrzut ognia przy spadku ciśnienia; 3 naboje ciśnieniowe zamiast 2 / +masa |
| WRATH-4 | lufa krótka / gorzej celny łuk; bęben 6 → pojedynczy (lekki, szybki) |
| FALCON-6 | czujnik (dzisiejsze naprowadzanie) / +koszt; prowadnica długa (szybciej osiąga prędkość) / dłuższa |
| SPECTER-1 | kondensatory szybkie (−ładowanie) / grzeją cewki — 3. strzał pod rząd wolniej; cewki chłodzone / +masa |
| SINEW-6 | **gumy podwójne** (prędkość, zasięg) / dłuższe naciąganie; **linka** (dzisiejszy „Barbed tether”) / bełt na lince wolniej wraca; groty z zadziorami |
| Maczeta, kilof | ostrzenie (jak dziś) / tępieje z użyciem; ciężki obuch / wolniejszy zamach |

### 4.4 Widoczne na modelu

- `gun_proc.py` buduje części jako osobne bryły z gniazdami (puste węzły `socket_muzzle`, `socket_mag`, `socket_optic`, `socket_stock`, `socket_light`) w GLB broni; części mają własne GLB (`art/char3d/parts/`).
- `char3d.gd` i oględziny ([F]) przypinają części do gniazd. Długość broni (`gun_len`) liczona z zestawu — wylot pocisku dalej z pozy nominalnej (`Char3D.aim_points`), więc animacja nic nie psuje.
- Tłumik zmienia też dźwięk strzału (nowe klucze audio: `m83_shot_supp`, `p64_shot_supp`) i błysk.

### 4.5 Kto ma jaką broń

- **Odblokowane części** (schematy) są **wspólne dla drużyny** — jak dziś złom i bronie.
- **Konfiguracja broni jest osobna dla każdego gracza** (zapis w profilu klienta). Dwóch graczy z M-83 może mieć różne bronie.
- Sieć: gracz replikuje zestaw jako krótką tablicę liczb (`PackedByteArray`: broń → indeksy części + typ naboju). Serwer sprawdza, czy części są odblokowane, i buduje definicję u siebie; obrażenia dalej liczy serwer.
- Bot: zestaw fabryczny (bez zmian w botach).

---

## 5. Obsługa broni

### 5.1 Odrzut: przewidywalny podrzut zamiast samego bloomu

- Każdy strzał podnosi **punkt celowania** o `climb` (°) i przesuwa w bok losowo o `drift` (°); punkt wraca z prędkością `recover` °/s.
- Mysz: gracz może ściągać broń w dół (prawdziwa kontrola odrzutu). Klawiatura/pad z 8 kierunkami nie może kompensować — dla nich podrzut działa jak dziś bloom (rozrzut w stożku), żeby nikt nie był karany za sterowanie.
- Mniejszy podrzut: **kucanie** (×0,6), **oparcie** (§5.2), seria 3 (jak dziś), kompensator.
- Celownik HUD pokazuje podrzut (kółko unosi się i wraca) — gracz widzi przyczynę i skutek.

### 5.2 Oparcie broni

Kucanie przy krawędzi skrzyni, parapetu, murku (przeszkoda w zasięgu 0,5 m przed lufą, na wysokości broni) = **oparcie**: podrzut ×0,4, rozrzut ×0,6. Ikonka w celowniku. Daje sens osłonom w strzelaninie 2D bez nowego klawisza.

### 5.3 Magazynek i komora

- **Nabój w komorze**: broń z zamkiem zamkniętym ma `mag + 1` po przeładowaniu taktycznym (AKM 30+1, P-83 8+1). Pusty = dłużej (już jest `reload_empty_extra` — AKM nie zatrzymuje zamka, trzeba przeładować rączką).
- **Dwa rodzaje przeładowania**:
  - **[R] krótko — szybkie**: magazynek leci na ziemię (model 3D, dźwięk upadku = mały hałas), resztki naboi wracają do zapasu dopiero po podniesieniu.
  - **[R] przytrzymane — taktyczne**: +0,4 s, resztki zostają.
- Zatrzymanie zamka P-83 po ostatnim naboju (widać na modelu), szybsze przeładowanie bez repetowania.

### 5.4 Fizyka pocisków specjalnych

| Broń | Zmiana | Skutek w grze |
|---|---|---|
| **P-83** | 1500 → 1070 px/s (9×18 ≈ 315 m/s) | uczciwie poddźwiękowy, tłumik ma sens |
| **WRATH-4** | **odległość uzbrojenia** ok. 5 m projektowych (80 px): bliżej granat odbija się i nie wybucha (tępe uderzenie, ogłuszenie). Samolikwidacja jak dziś (`fuse`) | koniec samobójczych wybuchów pod nogami; kartacz na bliski dystans |
| **FALCON-6** | start 60 px/s, przyspieszenie do 420 px/s w 0,3 s; obrażenia rosną z prędkością | słaby z bliska, groźny z daleka — prawdziwa cecha Gyrojetu |
| **HKM-9** | **ciśnienie**: ciągły ogień obniża ciśnienie → zasięg płomienia spada do 50%; puszczenie spustu na 0,5 s odbudowuje; nabój ciśnieniowy (3 na zbiornik) przywraca całość | strzela się porcjami jak prawdziwym miotaczem |
| **SPECTER-1** | trzymanie naładowanego strzału zjada baterię (upływ kondensatora); 3. strzał pod rząd — gorące cewki, ładowanie +40% | decyzja „strzel teraz albo stracisz” |
| **SINEW-6** | bełt trafiający beton może się wygiąć (25%) — nie do odzysku | odzysk bełtów wymaga wyboru celu |
| Kule | bez spadku (realnie <10 cm na 30 m) — **zostaje 0** | nie udajemy balistyki, której nie widać |

### 5.5 Gorąca lufa

Rozgrzanie (`_heat`) poza hałasem:
- rozrzut × (1 + 0,4 × heat²) — dopiero przy długim ogniu;
- **dym z lufy** (cząsteczki 3D) i **falowanie powietrza** nad lufą od heat > 0,6 — gracz widzi, że przesadził;
- tłumik: hałas × (1 + 0,5 × heat) — gorąca puszka głośnieje;
- przy heat 1 i ogniu ciągłym: szybciej spada stan techniczny (§6).

### 5.6 Strzał w powietrzu

Rozrzut +1,5° w locie (skok, spadanie), ×0,5 przez 0,15 s po lądowaniu. Contra zostaje (strzelasz w skoku), ale stojąc trafiasz lepiej.

### 5.7 Przebijalność materiałów

Pocisk ma **energię przebicia** (z typu naboju); materiał zabiera jej część:

| Materiał | 9×18 | 7,62 PS | 7,62 BZ | Breneka | Szyna |
|---|---|---|---|---|---|
| deska, skrzynia | nie | tak | tak | tak | tak |
| blacha | nie | nie | tak | nie | tak |
| ciało Trzoska | nie | tak (1) | tak (2) | tak (1) | wszystko |
| beton, mur | nie | nie | nie | nie | ulepszenie |

Rykoszet od metalu przy ostrym kącie (< 20°) jako prawdziwy pocisk z połową energii — z regułą GDD: kolega trafiony rykoszetem krzyczy (hałas), nie traci zdrowia.

### 5.8 Opcjonalnie: przybliżony stan naboi (tryb Weteran)

HUD zamiast `23 / 150` pokazuje „pełny / ponad połowa / mało / ostatnie” — dokładnie widać tylko po sprawdzeniu magazynka (przytrzymaj [R] przy pełnym). Ustawienie dostępności, domyślnie wyłączone.

---

## 6. Stan techniczny i zacięcia

### 6.1 Stan

Każda broń gracza ma `condition` 0–100 % (zapis w profilu). Spada od:
- strzałów (0,02 % na strzał, ×3 przy gorącej lufie),
- **brodzenia** (`water_wading` — woda do pasa: −5 %, błoto: −10 %) i upadku na ziemię (down),
- tłumika (gazy cofają się do mechanizmu),
- typu broni: AKM i P-83 tracą najwolniej, broń eksperymentalna (LR-7, SPECTER-1, FALCON-6) najszybciej.

### 6.2 Zacięcia

Szansa na strzał ≈ 0 powyżej 70 % stanu, potem rośnie do ok. 1 na 150 strzałów przy 30 %. **Nigdy** w pierwszych 3 strzałach magazynka i nigdy dwa razy w 10 s.

| Rodzaj | Jak wygląda | Usunięcie |
|---|---|---|
| niewypał | klik, brak strzału | P-83 (podwójne działanie): pociągnij jeszcze raz; reszta: [R] krótko |
| niedosłanie / zacięcie łuski | zamek nie domknięty, łuska w oknie (widać na modelu) | **[R] krótko** — przeładowanie rączką, 0,6 s, mały hałas |
| podwójne podanie | dwa naboje w komorze | pełne przeładowanie, +1 s |
| broń eksperymentalna | LR-7: przegrzanie ogniwa (pauza 1 s); SPECTER-1: przebicie kondensatora (ładowanie od nowa) | czekanie / ponowne ładowanie |

To ma dawać **dwie sekundy napięcia** w horrorze, a nie karę: zacięcie zawsze da się usunąć jednym klawiszem, a jego szansę widać (oględziny [F] i warsztat pokazują stan, HUD ostrzega „broń brudna” poniżej 40 %).

### 6.3 Konserwacja

- W kryjówce: **czyszczenie przy ławie** — tanio (5–15 złomu) albo za darmo przy kilku sekundach animacji rozkładania na ławie.
- W misji: **zestaw do czyszczenia** (przedmiot zużywalny jak apteczka): 6 s, cicho, +40 % stanu.
- Ustawienie „Niezawodność broni”: wyłączona / standard / weteran. Boty bez zacięć.

---

## 7. Postęp, który daje frajdę

### 7.1 Skąd części

- **Zaginiony patrol** (fabuła strefy I): przy ciałach żołnierzy i w skrzynkach patrolu — PBS-1, magazynki RPK, NSPU. Znalezisko = schemat dla drużyny (odblokowanie na stałe po ekstrakcji, jak złom — wipe go zabiera).
- **Elity** (Kapłan, Rzeźnik, Żerca): rzadkie części i amunicja specjalna.
- **Warsztat**: części podstawowe za złom; lepsze wymagają schematu + złomu.
- Brak „legendarnych” losowych statystyk — każda część to konkretna, nazwana rzecz.

### 7.2 Elaboracja (ujście złomu)

Prasa przy ławie w kryjówce: złom → amunicja specjalna (Breneka, gumowe, US, BZ — każda z limitem zapasu). Realistyczne (elaboracja nabojów myśliwskich była w ZSRR powszechna) i daje stały sens zbieraniu złomu.

### 7.3 Wprawa (osobno dla gracza i broni)

Zabójstwa i trafienia z danej broni dają wprawę (5 stopni): szybsze przeładowanie (do −10 %), szybsze dobycie, lepsza kontrola podrzutu (do −10 %), szybsze usuwanie zacięć. Małe liczby — wyszkolenie, nie supermoc. Zapis w `Profile`.

### 7.4 Historia broni

- **Nacięcia na kolbie** za elity i bossów (decal na modelu), licznik zabójstw w oględzinach.
- Zużycie widać: przetarta oksyda, taśma na łożu, zadrapania rosnące z liczbą strzałów (parametr materiału w `gun_proc.py` — już ma kurz i zacieki).
- Nazwa broni nadana przez gracza (wygrawerowana w oględzinach).

### 7.5 Strzelnica w kryjówce

Kilka tarcz i manekinów w maszynowni (dolny poziom huba): sprawdzanie zestawu, podrzutu, typu naboju, odległości uzbrojenia granatu. Wyniki „czas trafienia 5 tarcz” na ścianie pamięci — mała rywalizacja w drużynie.

### 7.6 Ława rusznikarska (interfejs)

Zamiast płaskiej listy: broń rozłożona w 3D na ławie (rozszerzenie oględzin z `weapon_inspect.gd`), gniazda jako punkty na modelu, panel „teraz → po zmianie” z zyskami na zielono i kosztami na czerwono, zestawy zapisywane pod nazwą (np. „Cicho”, „Szturm”).

---

## 8. Architektura (szkic)

```
weapon_def.gd     + pola: climb, drift, recover, brace_mult, air_spread, chamber, pen_energy, arm_dist, accel,
                    pressure_*, reliability, length_m, mass_kg, caliber
ammo.gd (nowy)    kalibry i typy naboi: modyfikatory jak w upgrades.gd + flagi (subsonic, tracer, ap, incendiary…)
parts.gd (nowy)   katalog części: gniazdo, bronie, modyfikatory (zysk i koszt), siatka/socket, wymaganie odblokowania
upgrades.gd       zostaje jako warstwa zgodności → migracja: dzisiejsze poziomy mapowane na części/typy naboi
weapons.gd        def_for(id, loadout_cfg) — baza + części + amunicja, pamięć podręczna po skrócie zestawu
weapon_controller podrzut, oparcie, komora, przeładowanie szybkie/taktyczne, ciśnienie, zacięcia (seed od serwera)
arsenal.gd        zapas po kalibrze i typie; podnoszenie upuszczonego magazynka
scrap.gd          schematy (wspólne), elaboracja; poziomy `levels` → migracja
profile.gd        zestawy gracza, stan techniczny, wprawa, nacięcia
gun_proc.py       części jako osobne GLB + gniazda w GLB broni
```

Zgodność: `Weapons.def(id)` dalej zwraca definicję (dla gracza bez zestawu = fabryczna), więc HUD, pociski i boty działają od pierwszego dnia.

Sieć: zestaw (≤ 16 bajtów na broń) replikowany przy zmianie, nie na strzał. Zacięcia losowane z seedu strzału, który i tak jest wysyłany — serwer i klient wiedzą to samo.

## 9. Testy

- `parts.validate()`: każda część wskazuje istniejące pole, pasuje do broni, **ma co najmniej jeden minus**; brak części „lepszej we wszystkim” od innej w tym samym gnieździe.
- `ammo.validate()`: poddźwiękowe < 1165 px/s, smugowe mają smugę, typy przypisane do kalibru.
- Hałas: kolejność zestawów M-83 (PBS-1 + US < PBS-1 + PS < PS) i P-83 z tłumikiem.
- WRATH-4: granat poniżej odległości uzbrojenia nie wybucha; kartacz działa z bliska.
- FALCON-6: obrażenia z 1 m < z 10 m.
- Zacięcia: brak w pierwszych 3 strzałach, deterministyczne z seedu, częstość przy stanie 30 % w widełkach.
- Sieć: klient z nieodblokowaną częścią → serwer liczy fabryczną; dwa zestawy M-83 u dwóch graczy dają różne obrażenia.
- Przebijalność: PS przez skrzynię tak, 9×18 nie; rykoszet nie rani kolegi.

## 10. Kolejność (propozycja)

| Etap | Zakres | Ryzyko dla czucia gry | Przed playtestem? |
|---|---|---|---|
| **0. Poprawki realiów** ✅ 1.7.316 | U3 (opisy i efekty bez „+obrażeń z lufy”), B6 P-83 1070 px/s, B7 uzbrojenie WRATH-4, B8 Gyrojet, B11 strzał w locie, komora +1 | małe | tak — mały PR |
| **1. Amunicja wg kalibru** ✅ 1.7.317 (część) | §3: kalibry, typy naboi, klawisz Z (T zajmuje czat), dzisiejsze „poziomy 3” → typy naboi. Wdrożone: pula 12/70, 7,62 US / BZ, 12/70 breneka / zapalające / gumowe, sklep pudełek (1.7.317); 40 mm kartacz / oświetlający / dymny i łup z elit (1.7.318). Zostało: wspólne ogniwa NiCd. Świadomie pominięte: T-45 (w grze każda kula ma smugę — konwencja z 1.7.311) i kasetowy jako nabój (zostaje ulepszeniem WRATH-4) | średnie (ekonomia amunicji) | tak, jeśli playtest ma sprawdzić stealth |
| **2. Części w gniazdach** | §4 + widoczne na modelu + konfiguracja per gracz + ława. **2a ✅ 1.7.319**: katalog części z kompromisami (`parts.gd`), zakup dla drużyny, montaż prywatny (Profile.fits → player.fits), sieć, migracja poziomów, warsztat i kodeks. **2b ✅ 1.7.320–1.7.321**: części widoczne na modelu 3D — 29 modeli dla wszystkich broni (części bez wyglądu: mechanizmy, mieszanka, głowice, dławik). **2c ✅ 1.7.323**: ława rusznikarska w 3D w zakładce ARMS warsztatu (broń z częścią spod kursora, część świeci i wysuwa się z gniazda, obrót myszą). Zostało: więcej alternatyw dla broni innych niż M-83 i SPREAD-12 | średnie (UI) | po playteście |
| **3. Obsługa** | §5.1–5.3, 5.5, 5.7: podrzut, oparcie, dwa przeładowania, gorąca lufa, przebijalność | **duże** — zmienia strzelanie; tylko z odsłuchem/ogrywaniem | po playteście, A/B |
| **4. Stan i zacięcia** | §6, z ustawieniem trudności | duże dla nastroju | po playteście, domyślnie „standard” |
| **5. Wprawa, historia, strzelnica, elaboracja** | §7 | małe | po playteście |

Każdy etap: gałąź + PR, podbicie wersji, wiersz w CHANGELOG, aktualizacja `WEAPONS.md` i GDD §6.

## 11. Decyzje do podjęcia

1. **Zestawy osobne dla gracza czy wspólne dla drużyny?** (Rekomendacja: schematy wspólne, zestaw osobny.) — **decyzja 2026-10-20: osobne dla gracza, odblokowania wspólne.**
2. **Zacięcia: tak / nie / tylko „Weteran”?** (Rekomendacja: tak, rzadkie, z ustawieniem; po playteście.)
3. **Podrzut tylko dla myszy** (klawiatura/pad zostają przy rozrzucie)? (Rekomendacja: tak.)
4. **Przybliżony stan naboi w HUD** — tylko jako opcja? (Rekomendacja: opcja, domyślnie wyłączona.)
5. **Wspólna amunicja 12/70** dla SPREAD-12 i PELLET-8? (Rekomendacja: tak — realne i tworzy decyzje w drużynie.)
6. **Od którego etapu zaczynamy?** (Rekomendacja: Etap 0, potem Etap 1.)
