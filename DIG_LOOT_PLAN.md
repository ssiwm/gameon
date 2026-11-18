# DIG_LOOT_PLAN — kopanie i znajdźki: analiza i propozycja (2026-11-17)

Analiza na main `713cd173` (1.7.600, po #719). Decyzje przyjęte 2026-11-17 (§5).
**Stan wdrożenia:** K0 + K1 w 1.7.601 (PR #720), K2 w 1.7.602 (PR #721), K3 „coś drapie” w 1.7.603 (PR #722), K5a (druga, krótka strefa na każdej mapie i wejścia na rzucie mapy) w 1.7.604 (PR #723), K5b (komora z gniazdem ćm w głębokiej strefie 1.1; 1.2 i 1.3 bez komory) w 1.7.605 (PR #724), K4a (6 taśm: po jednej w głębokiej strefie i w sejfie albo skrytce każdej mapy, karta ARCHIWUM, teksty do redakcji autora) w 1.7.606 (PR #725), K4b część 1 (ostrożne wydobycie taśmy: kilof i wybuch niszczą, [E] 1,5 s wyjmuje dłońmi) w 1.7.607 (gałąź `feat/dig-loot-k4b`). Zostają z K4: geoda otwierana w pracowni, zestawy; potem K6.
Dane: dzienniki sesji `%APPDATA%/Godot/app_userdata/Dead Air '87 Prototype/sessions`, **74 próby kampanii od 1.7.505**
(od wejścia stref na mapy, 2026-11-06 → 2026-11-17). To prawie wyłącznie sesje autora (solo, RTX 3080), więc liczby pokazują,
jak gra autor, a nie nowi gracze.

---

## 1. Jak to działa dziś (krótko)

| Element | Stan w kodzie |
|---|---|
| Strefy | Po jednej na mapę (`DIG_ZONES`): 1.1 skała z żyłą 10×9 kafli, 5 znajdziek; 1.2 żwir 10×4, 2 znajdźki; 1.3 ziemia 5×9, 2 znajdźki. Zawsze w ślepym końcu, w ciemności. |
| Kopanie | Kęs na cios (`bite_rect`); krok tunelu: ziemia 3 ciosy, skała 6, żyła 9; cooldown kilofa 0,9 s; każdy cios to hałas 1,5 × materiał. |
| Znajdźki | `_plan_finds`: 1 na 16 kafli skały, max 6, „w bok i w głąb”. Wagi: złom 40 / amunicja 20 / zaopatrzenie 15 / bateria 15 / część 10. **Złom ze znajdźki: 1–3.** |
| Szukanie | Znajdźka jest niewidoczna, dopóki leży w ziemi. Wskazują ją tylko: skaner OWL (romb), dźwięk metalu przy ciosie, gdy wyrwa jest **≤ 6 px** od znajdźki, i błysk w latarce, gdy jest odkopana do połowy. |
| Pule | Cenna znajdźka znika z puli po ekstrakcji, pula odnawia się po 3 udanych misjach na innych mapach; w wykopanym miejscu zostaje drobnica. |
| Żyła | Twardsza (9 ciosów na krok zamiast 6), ale **znajdźki losują się niezależnie od materiału**, więc nie daje więcej łupu. D5 obiecywał „więcej łupu”. |
| Fabuła | Notatki górników, „skrzynka z czymś cennym” i taśmy (GDD §łup: „Taśmy — ukryte znajdźki”) **nie istnieją** w kodzie. |
| Inne znajdźki | Skrzynie (deski, ok. 1,25 złomu na skrzynię, czasem bateria), sejf 40 złomu (trzymane [E]), skrytka 20 złomu (cel poboczny, 35% na część), skrzynie mocy, zrzuty z wrogów (35%). |

## 2. Co mówią dzienniki (od 1.7.505)

| Mapa | Prób | Sukces | Gracz był przy strefie | Kopał | Wykopał | Ciosy, gdy kopał (mediana) | Co wypadło |
|---|---|---|---|---|---|---|---|
| 1.1 | 24 | 17 | 14 | 9 | 6 prób / 10 znajdziek | 30 (3–166) | złom 4, amunicja 3, bateria 2, zaopatrzenie 1 |
| 1.2 | 27 | 8 | 12 | 4 | 2 próby / 3 znajdźki | ok. 120 (79–180) | bateria 2, amunicja 1 — **obie próby bez ekstrakcji** (wipe, wyjście) |
| 1.3 | 23 | 0 | 9 | 3 | 0 | 27 (18–33) | — |

- **Kopie 1 na 5 prób (16/74).** Przy strefie stoi połowa prób, ale wielu graczy odchodzi bez jednego ciosu.
- **Całe kopanie przez 11 dni dało ok. 8 złomu**, 3 paczki amunicji, 2 baterie i 1 przedmiot zaopatrzenia, wszystko na 1.1.
  Dla porównania na tej samej mapie: łup misji (mediana) **189 złomu**, sejf **40** (otwarty w 21 z 24 prób), premia za misję 55.
- **Części broni: 0 z 13 znajdziek** (waga 10%, a `pick_find` może zwrócić pusty wynik i wtedy wypada złom).
- Koszt: 30 ciosów to ok. 30 s, 166 ciosów to ok. 2,5 min z hałasem. Na 1.2 ok. 2 minuty kopania w żwirze dawały baterię.
- Dziennik nie zapisuje wejścia do strefy ani czasu w strefie. Ciosy liczy tylko `mission_end.noise.dig.n`. Pobyt przy strefie
  policzyłem z `pos` (skrypt `agg.py` w scratchpadzie sesji).

**Diagnoza:** technicznie kopanie jest świetne (siatka, materiały, osypywanie, zawał, dźwięk, pył). Jako *rozgrywka*
ma jednak cztery dziury:

1. **Nagroda nie pasuje do wysiłku i ryzyka.** Typowa znajdźka daje mniej niż skrzynia przy drodze, a sejf daje 10–20× więcej
   za 10 s trzymania [E]. Kopanie przegrywa z każdą inną czynnością w misji.
2. **Gracz kopie na ślepo.** Nagrody nie widać przed kopaniem, a sygnał „ciepło / zimno” pojawia się dopiero 6 px od znajdźki.
   Skaner OWL (rzadki, 120 złomu) to jedyny radar.
3. **Nie ma „wow”.** Losują się te same przedmioty co ze skrzyń i wrogów. Nie ma rzadkiej rzeczy, kolekcji ani historii.
   Żyła wygląda na cenną, ale jest tylko twardsza.
4. **Strefa to ślepa uliczka bez związku z resztą misji.** Jest jedna, w głębi i w ciemności. Na 1.2 i 1.3 mieści 2 znajdźki,
   a 1.3 od 11 dni nie ma sukcesu, więc nic stamtąd nie trafia do banku.

## 3. Inspiracje (co działa w popularnych grach i co bierzemy)

| Gra | Mechanizm | Co bierzemy |
|---|---|---|
| **Deep Rock Galactic** | Minerały (złoto, nitra) **widać w ścianach**; kopanie jest częścią eksploracji (cel 50/50 eksploracja / walka); na końcu jaskini czeka „Vault” z dużym łupem. | Żyła ma być **widoczną** nagrodą: każdy kęs żyły daje bryłkę rudy. Strefa ma „komorę” na końcu. |
| **Spelunky 2** | Złoto i klejnoty błyszczą w ścianach; Udjat Eye klika coraz szybciej przy ukrytej komnacie. | Część znajdziek sygnalizuje się na ścianie przed kopaniem. Sygnał dźwiękowy narasta z odległością. |
| **Valheim** (Wishbone) | Pikanie przyspiesza w miarę zbliżania się do zakopanego skarbu lub żyły srebra; najpierw szuka się miejsca, potem kopie. | „Dzwonienie” ciosu w metal z zasięgu ok. 3 kafli, z wysokością i głośnością zależną od odległości. Minigra namierzania bez HUD. |
| **Rust** (hotspot) | Na złożu świeci punkt: trafienie w niego daje 150%, kolejne trafienia do 300%, chybienie zeruje premię. Bez światła punktu nie widać. | **Szczelina** na czole wykopu widoczna tylko w snopie latarki: cios celowany w nią bierze podwójny kęs. To umiejętność w powtarzalnej czynności i powód, żeby świecić latarką. |
| **Dome Keeper** | Kopie się między falami, a licznik zmusza do powrotu; dźwiganie surowców spowalnia; chciwość jest karana. | Kopanie pod presją: po N ciosach zza ściany „coś drapie” i wychodzi wróg. Rytm co-op: jeden kopie, drugi pilnuje. |
| **SteamWorld Dig** | Ograniczona torba wymusza powrót; drogę powrotną planuje się razem z wykopem. | Ciężkie znalezisko (opcja K5) zajmuje ręce aż do ekstrakcji. |
| **R.E.P.O. / Lethal Company** (wzorce z GDD) | Przedmiot ma wartość widoczną po zeskanowaniu; kruchy traci wartość od uderzeń; trzeba go donieść do ekstrakcji. | Skaner pokazuje **klasę** znajdźki (cenna / drobnica). Opcja: kruche znalezisko traci wartość, gdy wybuch je odrzuci. |
| **Minecraft** (archeologia) | Powolne odsłanianie pędzlem „podejrzanego” bloku; skorupy mają wzory i tworzą kolekcję. | Ostatni kęs przy znajdźce fabularnej wymaga ostrożnego, cichego wydobycia (maczetą lub dłońmi). Zestawy do zebrania. |
| **Stardew Valley** | „Robaki” na ziemi gwarantują znalezisko; geody otwiera się u kowala, a muzeum zbiera kolekcję. | Widoczny znak na ścianie gwarantuje znajdźkę. **„Geoda” z żyły otwierana w pracowni** daje moment odkrycia w kryjówce i źródło próbek. |
| **Sea of Thieves** | Mapa skarbu i „X”; z niesioną skrzynią nie można sprintować ani używać przedmiotów. | Notatka górnika może wskazywać skrytkę w strefie innej mapy (mapa skarbu). |

## 4. Propozycja — etapy

Zasady, które zostają bez zmian: symulacja 2D, rozwój tylko w 3D, strefy nigdy nie leżą na trasie do celu, anty-pułapka,
pule bez farmienia, nagrania tylko lokalnie. **Progi zawału zostają** (decyzja z 2026-11-14).

### K0 — pomiar (mały, pierwszy)
- Zdarzenia `dig_enter` / `dig_leave` (strefa, czas) oraz w `mission_end` blok `dig` dla każdej strefy: ciosy, sekundy w strefie,
  czas do pierwszej znajdźki, ile razy dzwoniło, ile hotspotów trafiono (od K2).
- Raport w `session_progress.py`: odsetek prób z kopaniem, złom na minutę kopania i na minutę misji.
- Cel do sprawdzenia po K1–K2: kopanie w ≥ 40% prób, złom na minutę kopania ≥ średni złom na minutę misji.

### K1 — wartość nagrody (same liczby i dane, największy efekt)
- **Znajdźka „zakopany pakunek”** zamiast złomu 1–3: 12–20 złomu (`FIND_SCRAP`). Cała strefa 1.1 ma być warta mniej więcej
  sejf (40) plus jedna rzadka rzecz.
- **Żyła płaci:** narożniki materiału `vein` zamienione w powietrze dają rudę: co `ORE_CORNERS` = 24 — 1 złom do łupu misji (licznik
  w strefie, bez przedmiotów na ziemi, toast z sumą). Dzięki temu twardość 9 ciosów ma sens, a nagroda jest widoczna przed kopaniem,
  jak w DRG. Bez puli (tempo niższe niż złom na minutę zwykłej gry).
- **Geoda** (wdrożone w K1): jedno miejsce na narożniku żyły w strefie z żyłą; odkopana daje próbkę do łupu misji, w puli jak inne
  cenne znajdźki. Otwieranie w pracowni jako osobny moment zostaje w K4.
- **Gwarantowana główna znajdźka:** w każdej strefie i w każdym ziarnie jedno miejsce jest „główne”: część broni z puli znalezisk,
  a gdy pula jest pusta, próbka. Reszta losuje się z wag. Na 1.2 i 1.3 (po 2 miejsca) daje to jedną pewną rzecz.
- **Próbki ze stref:** pracownia ma wąskie gardło (ok. 0,8 próbki na misję). Ruda z żyły jako źródło próbek pasuje do fabuły
  (organizm z meteorytu w skale).

### K2 — sygnały „tu coś jest” (czytelność bez HUD)
- **Ślady na ścianie:** nad znajdźką ułożoną płycej niż 2 kafle od czoła wykopu widać w świetle latarki wtrącenie (wystający róg
  skrzynki, żyłka rudy prowadząca w głąb). To rozszerzenie dzisiejszego błysku przy odkopaniu do połowy.
- **Dzwonienie z odległości:** cios w strefę w zasięgu ok. 3 kafli od zakopanej znajdźki daje dźwięk metalu, cichszy i niższy z daleka,
  głośny i wysoki tuż przy niej (Valheim, Udjat). Dziś próg to 6 px.
- **Hotspot / szczelina (Rust):** na odsłoniętym czole w snopie latarki pojawia się pęknięcie (1 narożnik na krok tunelu). Cios celowany
  w nie bierze podwójny kęs i jest cichszy o połowę; następna szczelina pojawia się obok. Bez latarki szczeliny nie widać, więc kopanie
  w ciemności jest wolniejsze. Latarka dostaje cel (dziś świeci 14–37% czasu, a bateria nigdy nie spada do zera).
- **Skaner OWL:** romb cenny (pełny, ciepły) albo drobnica (blady; to już jest) oraz głębokość („2 m”). Rozważyć OWL w zestawie startowym
  na 1.1 jako lekcję.

### K3 — ryzyko i rytm (po playteście K1–K2)
- **„Coś drapie”**: po ok. 20 ciosach w strefę zza ściany słychać drapanie. Po kolejnych ok. 10 z czoła wykopu wychodzi para Trzosków
  (na 1.3 Ślepiec). Gracz dostaje zapowiedź i może przestać. Dziś dyrektor prawie nikogo nie wypuszcza, a strefa to dobre lokalne miejsce
  na zaplanowaną walkę. Bot pilnuje kopiącego (niezrobione w D5).
- **Komora na końcu** (Vault z DRG): najgłębsze miejsce strefy 1.1 to pusta kieszeń z gniazdem ćm i główną znajdźką. Odkopanie jej
  daje „aha”, ale budzi rój.

### K4 — znajdźki fabularne i kolekcja
- **Taśmy i listy górników** (GDD je obiecuje, kod ich nie ma): 1–2 na mapę, w strefach i skrytkach. Raz zebrane zostają w kodeksie
  „Archiwum” w kryjówce (głos z taśmy, tekst). Wymaga treści od autora.
- **Ostrożne wydobycie** (Minecraft): ostatni kęs przy znajdźce fabularnej trzeba zdjąć maczetą lub dłońmi ([E] trzymane 1,5 s).
  Kilof lub wybuch ją uszkadza: taśma „zniszczona”, wraca w następnym ziarnie.
- **Geoda z żyły:** otwierana w pracowni daje próbkę, część albo kosmetyk (moment odkrycia w kryjówce, jak w Stardew).
- **Zestawy:** komplet taśm z mapy odblokowuje nagrodę (tapetę, wskazówkę do kopalni FPP z `MINING_PLAN.md`, emblemat).
- Notatka może być **mapą skarbu**: wskazuje miejsce w strefie innej mapy, które dostaje główną znajdźkę.

### K5 — rozmieszczenie stref (zmiany map)
- 2 strefy na mapę: krótka **przy** trasie (1 znajdźka, uczy, zawsze w świetle lampy) i głęboka w ślepym końcu (cenna, z komorą).
- Wejście w strefę oznaczone na minimapie po pierwszym zauważeniu kilofa-znaku.
- Opcja (do decyzji): **ciężkie znalezisko** w stylu R.E.P.O. / Sea of Thieves: skrzynka niesiona oburącz, bez broni i wolniej, do
  ekstrakcji; po upuszczeniu leży. Duży system, warto tylko jeśli K1–K4 nie wystarczą.

### K6 — znajdźki poza kopaniem (porządki)
- Skrzynie dają 1,25 złomu, a sejf 40: rozjazd jest duży. Rzadkość widoczna od razu: poświata i dźwięk zależne od klasy (zwykłe /
  rzadkie / fabularne), krótki akcent przy rzadkim.
- Taśmy (K4) także w skrytkach i sejfach, nie tylko w strefach.

## 5. Decyzje (przyjęte 2026-11-17)

1. **Wartość strefy:** sejf + 1 rzadka rzecz. Pakunek 12–20 złomu, ok. 40–60 na strefę plus gwarantowana część albo próbka.
2. **Żyła:** płaci rudą (do łupu misji) i czasem daje geodę z próbką, otwieraną w pracowni.
3. **Sygnały:** wszystkie cztery — dzwonienie z ok. 3 kafli, szczelina w latarce, ślady na ścianie, skaner z klasą i głębokością.
4. **Wrogowie budzeni kopaniem (K3):** od razu, razem z K1–K2 (nie czeka na playtest).
5. **Taśmy (K4):** Claude pisze szkic 6 tekstów (2 na mapę 1.1–1.3, PL i EN) zgodnych z GDD, autor redaguje przed scaleniem.
6. **Ciężkie znalezisko:** odłożone. Wraca, jeśli po playteście kopanie dalej będzie mało atrakcyjne.
7. **Strefy (K5):** dwie na mapę — krótka przy trasie (1 znajdźka, w świetle) i głęboka w ślepym końcu z komorą.

## 6. Kolejność i zakres

| Etap | Pliki (główne) | Test | Wielkość |
|---|---|---|---|
| K0 | `session_log.gd`, `dig_zone.gd`, `tools/session_progress.py` | `--digtest` + raport w CI | S |
| K1 | `dig_zone.gd` (`FIND_SCRAP`, główna znajdźka, licznik rudy), `scrap.gd` (próbki z rudy) | `--digtest` sekcja 11 + nowa | S–M |
| K2 | `dig_zone.gd` (dzwonienie, szczeliny), `view3d.gd` (ślady, szczeliny w snopie), `scanner_view.gd`, `weapon_controller.gd` | `--digtest`, zrzuty w oknie | M |
| K3 | `dig_zone.gd`, `director.gd`, bot | `--digtest`, `--enemytest` | M |
| K4 | nowe `tapes.gd`, kodeks, `lab_bench.gd`, treść PL/EN | nowy `--tapetest` | M–L (głównie treść) |
| K5 | dane map 1.1–1.3, `hud_minimap.gd` | `--maptest` (anty-pułapka, trasa) | M |

Kolejność po decyzjach: **PR 1 = K0 + K1**, **PR 2 = K2**, **PR 3 = K3**, **PR 4 = K5** (mapy), **PR 5 = K4** (taśmy, szkic tekstów
do redakcji), K6 na końcu. Playtest (`fun_report.py`, `session_progress.py`) po PR 3. Ciężkie znalezisko odłożone.

## Źródła inspiracji
- Deep Rock Galactic — wywiad Co-optimus (50/50 eksploracja / walka): https://www.co-optimus.com/editorial/1978/page/2/indie-ana-co-op-and-the-deep-rock-galactic-interview.html ; Vault: https://www.gamepressure.com/deep-rock-galactic/cave-structure/zad4b0
- Rust — hotspoty złóż: https://wiki.facepunch.com/rust/Ore_nodes
- Valheim — Wishbone: https://www.thegamer.com/valheim-wishbone-location-uses/
- Spelunky 2 — Udjat Eye: https://www.thegamer.com/spelunky-2-udjat-eye-find/
- Dome Keeper: https://en.wikipedia.org/wiki/Dome_Keeper ; https://www.techradar.com/au/features/dome-keepers-pacific-rim-style-monsters-test-your-self-restraint
- SteamWorld Dig — projekt kopania: https://gamedeveloper.com/design/game-design-deep-dive-the-digging-mechanic-in-i-steamworld-dig-i-
- Minecraft — skorupy: https://minecraft.wiki/w/Pottery_Shard
- Stardew Valley — artefakty: https://stardewvalleywiki.com/Artifact
- Sea of Thieves — skrzynie: https://seaofthieves.wiki.gg/wiki/Treasure_Chests
- R.E.P.O. (przewodnik społeczności, nieoficjalny): https://guide-repo-game.pages.dev/guides/repo-beginners-guide-walkthrough-tips-best-builds
