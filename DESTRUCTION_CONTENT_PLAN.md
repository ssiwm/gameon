# DESTRUCTION_CONTENT_PLAN — drzwi budynków i treść niszczenia na mapach

Stan wyjścia planu: main 1.7.655 (203ed634, 2026-11-22). Kontynuacja `DESTRUCTION_PLAN.md` (D0–D5, w main do 1.7.506),
`SHOOT_DESTRUCTION_PLAN.md` (S0–S3, do 1.7.557) i `IMPACT_MARKS_PLAN.md` (1.7.655).

**Stan (2026-11-22):** decyzje 1–10 przyjęte zgodnie z zaleceniami (sekcja „Decyzje”). W trakcie: spike W0 (obraz drzwi).

## Skąd ten plan

Analiza 2026-11-22 („zweryfikuj możliwość dodania destrukcji środowiska”): niszczenie otoczenia już jest i jest używane. Brakuje go
tam, gdzie gracz spędza dużo czasu, czyli w budynkach. Część przygotowanych mechanik nie trafiła też na mapy. Autor przyjął
rekomendacje z analizy i dodał wymaganie: **drzwi we wszystkich budynkach**, które trzeba wyważyć maczetą (drewniane), kilofem
(metalowe) albo wysadzić (zbrojone).

### Co jest dziś

| Element | Mapy kampanii |
|---|---|
| Mur `q`, deski `%`, kratka `+`, pusty otwór `:` (barykada) | 1.1: deski 2, otwór 1; 1.2: mur 1, deski 2, kratka 1, otwór 1; 1.3: deski 1, kratka 1, otwór 1 |
| Lampy misji `I`, okna `|` | 1.1: lampy 3; 1.2: lampy 4, okna 4; 1.3: okna 4 |
| Skrzynie `k`, beczki `o` | 1.1: 4 / 0; 1.2: 9 / 4; 1.3: 10 / 4 |
| Strefy kopania (`DIG_ZONES`) | po 2 na 1.1, 1.2, 1.3 |
| Stemple `!` i zawał `^` | tylko mapa testowa `t_mine` (zdjęte z kampanii w 1.7.494, B0) |
| Materiał `sheet` (blacha) | zdefiniowany w `breakable.gd`, na mapach 0 |
| B1, kryjówka | nic zniszczalnego |

### Dane z dziennika sesji (`tools/session_progress.py --since 2026-11-03`, 27 prób od 1.7.485)

To w większości sesje autora, więc to sygnały, nie statystyka.

- W 96% prób coś zostało zniszczone. Rozbitych przegród na próbę (mediana): 1,5–2.
- Przegrody wg narzędzia: deski — maczeta 30, kilof 1, **kula 1**; mur — kilof 10; kratka — kilof 9. Strzelanie w drewno (S1–S3)
  praktycznie nie występuje.
- **Barykady:** 4 przybite deski, wszystkie na `Planks1` (1.2) w jednej próbie. Za każdym razem ten sam gracz rozbijał je potem
  maczetą po 1,8–6,9 s. Barykada stała na przejściu, którym drużyna sama musiała wrócić, więc nikt się nią nie bronił. To właśnie
  dawało medianę „wytrzymała 5,5 s”.
- Okna: 0 rozbitych (1.3 ma tylko 2 próby). Lampy: 10, wszystkie kulą.
- Pobudki Stalkera i elit do 20 s po zniszczeniu: 12 z 214 (6%), więc koszt hałasu jest dziś niski.
- Kopanie: wejście do strefy w 70–78% prób, 40 znajdziek, ruda 0 złomu (osobny `DIG_LOOT_PLAN.md`).

### Ograniczenie techniczne (sprawdzone w kodzie)

`view3d._sync_geometry` (`view3d.gd:932`) liczy klucz z hasha wierszy `_map`. Każda zmiana kafla usuwa wszystkie dzieci `_geo` i buduje
świat od nowa. Zniszczalne może więc być tylko to, co jest osobnym węzłem (`breakable.gd`, jak przegrody) albo strefą kopania. Drzwi
muszą być przegrodą, nie kaflem. Nawigacja ma lokalną przebudowę (`Nav.rebuild_region`, #580), więc wyważenie drzwi nie przycina gry.

## Zasady

1. **Bezpieczna droga bez materiałów wybuchowych.** Cele misji, wyjścia i stanowiska muszą być osiągalne przy wszystkich drzwiach
   zbrojonych zamkniętych. Wystarczą narzędzia, które każdy ma od 1.7.495: maczeta i kilof. Granat odłamkowy to 1 sztuka na drużynę
   na misję (`throwables.gd` `issue`), a ładunek burzący kosztuje 250 złomu i nie jest wydawany. Sprawdza to `--maptest`.
2. **Drzwi to przegroda** (`breakable.gd`): HP, materiał, pasy, maska uszkodzeń, stan, reset, punkt kontrolny i dołączający idą
   istniejącymi ścieżkami. Bez nowych RPC, poza tym, czego wymaga obraz.
3. **Drzwi zmieniają informację.** Zamknięte blokują wzrok, światło i tłumią dźwięk jak cała szyba (`_is_sound_solid`). Dziury
   i pasy drewnianych przepuszczają je jak w deskach (S1–S2).
4. **Wyważenie kosztuje czas i hałas.** Materiał widać z daleka: model, kolor i komunikat o złym narzędziu, raz na przegrodę.
5. **Wszystko wg istniejących wzorców:** maczeta i kilof wg `weapon_controller.melee_for_target`, komunikat wg `TOOL_LABELS`,
   wybuch wg `blasts`.

## Inwentarz budynków (main 1.7.655)

Budynki 3D to wpisy `FRONT` z kluczem `build`. Otwory liczy `Level3D._plan_building` w kolumnach `c0` i `c1`: do 2 wierszy to
„door”, wyżej „gate”, okno `|` to „window”.

| Mapa | Budynek (`build`) | Wejście zach. | Wejście wsch. | Co w środku | Na trasie |
|---|---|---|---|---|---|
| 1.2 | hala stacji / chata radiowa (`hall`, kol. 66–100) | kol. 66, w. 22–25 — brama 4 rz. | kol. 100, w. 22–25 — brama 4 rz. | generator 1, antresola z kuszą, okna `|` 19–20 | tak |
| 1.2 | pompownia (`hall`, kol. 216–246, piętro 22) | kol. 216, w. 22–25 — brama 4 rz. | kol. 246, w. 22–25 — brama 4 rz. | generator 3 na piętrze, Rzeźnik, beczki, otwór `:` kol. 243 | tak |
| 1.3 | posterunek (`bunker`, kol. 18–36) | kol. 18, w. 24–25 — drzwi 2 rz. | kol. 36, w. 24–25 — drzwi 2 rz. | skrzynie, beczka | tak |
| 1.3 | Skład (`hall`, kol. 112–142) | kol. 112, w. 22–25 — brama 4 rz. | kol. 142, w. 22–25 — brama 4 rz. | antresola ze skrytką `H`, magazyn za kratą, okna `|` | tak |
| 1.3 | hala Żyły (`shed`, kol. 164–190) | kol. 164, w. 23–25 — brama 3 rz. | — (skała) | arena bossa, `VEIN_ARENA`, brama z korzeni | tak (boss) |

Poza zakresem:
- **1.1** — bez budynków (las i kopalnia).
- **B1** — hala Pijawki w skale, ściany szczytowe bez otworów; `doorway` (kol. 10–12) to wnęka-dekoracja.
- **Kryjówka** — bezpieczna strefa; drzwi D-7 zostają wątkiem fabularnym.
- Szopa na bagnie (1.2, kol. 112–132) — wiata bez ścian.
- `doorway` w 1.2 (kol. 88–91) — wnęka w tylnej ścianie, bez przejścia.

Razem 9 wejść w 5 budynkach: 2 drzwi, 7 bram. Każde wejście jest dziś na trasie głównej.

## Drzwi — projekt

### Materiały

Trzy nowe wpisy w `breakable.MATERIALS`. Metalowe drzwi to w praktyce `sheet` (blacha), więc ten materiał wreszcie trafia na mapy.
Liczby są do strojenia. Maczeta: 30 obrażeń co 0,42 s; kilof: 55 co 0,9 s (`weapons.gd`).

| Materiał | HP | Czym (`breaks`) | Wyważenie | Hałas (`n_hit` / `n_break`) | Kule (`shot`) |
|---|---|---|---|---|---|
| `door_wood` — drewniane | 90, pasy (`bands`, pas na kafel) | maczeta, kilof, kule, śrut, Brenneke, szyna, wybuch, ładunek, pazury | maczeta 3–4 ciosy ≈ 1,5 s; kilof 2 ≈ 1,8 s | 1,2 / 4 (jak deski) | jak deski (S1): pistolet ok. 30, M-83 ok. 18 trafień; dziury `holes` |
| `door_metal` — metalowe (z `sheet`) | 220 | kilof, wybuch (`blasts` 1), ładunek, szarża | kilof 4 ciosy ≈ 3,6 s; 1 granat | 3,0 / 6 (głośno — każdy cios słychać daleko) | 0 — tylko wgniecenia, kula się odbija |
| `door_steel` — zbrojone | 400 | wybuch (`blasts` 2), ładunek | 2 granaty albo 1 ładunek | — / 8 | 0 |

- Złe narzędzie daje komunikat raz na przegrodę, tylko dla człowieka (wzór B0): „Metal door — use a pickaxe or explosives”,
  „Reinforced door — explosives only”. Etykiety w `ui.csv`.
- Pasek akcji: „Wyważ” z nazwą klawisza narzędzia (`Actions.key("tool")`), jak podpowiedź „Kop” przy strefach.
- Kilof w zbrojone: odbija się z iskrą i hałasem `n_hit` 2,0. Hałas bez skutku to kara za próbę.

### Dane mapy

Stała `DOORS` w danych mapy, kluczem jest kolumna wejścia budynku:

```gdscript
const DOORS := {66: {"mat": "wood"}, 100: {"mat": "metal"}, 216: {"mat": "metal", "start": "broken"}}
```

- `level.gd` rejestruje drzwi jak przegrody z `WALL_MARKS`: komórki od podłogi w górę do pierwszej bryły, nazwy `Door1…`.
  Do tego `start: "broken"` jak `WALL_START_OPEN` — wyważone skrzydło leży, otwór da się zabić deskami (D2b).
- `--maptest`:
  - każde wejście „door” i „gate” każdego budynku 3D na mapie misji ma wpis w `DOORS`. Tak jest spełnione „wszystkie budynki”:
    nowy budynek bez drzwi nie przejdzie testu;
  - przy zamkniętych zbrojonych i wyważonych drewnianych i metalowych cele, wyjścia i stanowiska są osiągalne (zasada 1);
  - wydruk skrótów (`_shortcut_report`) obejmuje drzwi.

### Bramy 4 rzędy (7 z 9 wejść)

Brama ma dziś 4 rzędy (ok. 5,2 m). Wyważona przegroda na całą wysokość dawałaby otwór, w którym obraz bramy dalej stoi.
**Zalecenie (decyzja 4): furtka.** Przejście ma 2 rzędy, a górne rzędy otworu zamyka stała brama:
- w symulacji kafle bryły (nowy znak wypełnienia bramy albo `C` w kolumnie wejścia);
- w obrazie brama przesuwna z furtką, którą `building3d.gd` już rysuje (`gate`: skrzydło z blachy i furtka 0,85 × 1,95 m).

Do sprawdzenia w W2: wysocy wrogowie (Rzeźnik, Wołek, Stalker) przechodzą przez otwór 2 rzędów. Przy bramach 4-rzędowych nikt tego
nie mierzył. Sprawdzi to `--maptest` (nawigacja rodzaju ciała) i `--enemytest`.

### Wrogowie, bot, dyrektor

| Kto | Drewniane | Metalowe | Zbrojone |
|---|---|---|---|
| Trzosek (`claw_barricade`) | drapie (4) | nie | nie |
| Wołek, Rzeźnik (`charge_through`, szarża) | łamie | Rzeźnik łamie, Wołek odbija się | nie |
| Stalker (`_smash_tick`) | rozbija | rozbija wolniej (×2 czasu) | nie (zbrojone są tylko poza trasą) |
| Bot (`_bot_chop_wall`) | maczetą | kilofem | nie — bot nie zużywa materiałów wybuchowych |
| Dyrektor (`_pick_spot`) | — | — | — |

Dyrektor już dziś wymaga ścieżki nawigacji do graczy, więc grupy nie wyjdą z zamkniętego budynku. Wrogowie w środku zostają
w środku do wyważenia. Słyszą wyważanie przez drzwi (tłumienie jak szyba), więc za drzwiami czeka komitet powitalny. To jest
napięcie, o które chodzi.

### Obraz (3D)

- **Zamknięte:** skrzydło w ościeżnicy w pasie gry, materiał wg rodzaju:
  - drewniane — deski z poprzeczkami (tekstura desek przegród);
  - metalowe — blacha z przetłoczeniami (dzisiejszy `leaf`);
  - zbrojone — gruba stal z nitami i ryglem.
- **Wyważone:**
  - drewniane — pasy odpadają (`_sync_barricade` z `band_mask`), drzazgi z `fracture_planks.glb`;
  - metalowe — skrzydło wisi na jednym zawiasie albo leży, wgniecenia w masce uszkodzeń;
  - zbrojone — skrzydło wyrwane i odrzucone od ładunku (kierunek z ziarna, bez fizyki 3D), osmalenie (`impact_marks`).
- **Ryzyko widoczności (spike W0).** Ściana szczytowa stoi prostopadle do ekranu. Skrzydło w otworze kamera widzi ukosem albo
  krawędzią, tak jak ślady po kulach w `IMPACT_MARKS_PLAN.md` (tam rozwiązaniem był „odprysk na czole bryły”). Do tego
  `Level3D.shell_entry` pomija wysuniętą ścianę wejścia przy przegrodach (`ENTRY_KEEP` `"+%:q"`), żeby było je widać. Drzwi we
  wszystkich wejściach zdjęłyby wysuniętą ścianę ze wszystkich budynków. Budynek przestałby być zamkniętą bryłą, czyli wróciłaby uwaga
  z gry z 2026-11-09. Spike sprawdza dwa warianty:
  - A — skrzydło w pasie gry, wysunięta ściana zostaje, drzwi powtórzone na jej boku (`shell_facades`);
  - B — wyjątek z `ENTRY_KEEP` jak dziś.

  Kryterium: z kamery gry widać, które drzwi są zamknięte, z jakiego materiału i czy są wyważone. Zrzuty z nocy z latarką.

### Dźwięk

Drewno z odsłuchu B3 (`wood_hit`, `wood_break`). Nowe nagrania z biblioteki Sonniss (`audio_lib`): kilof w blachę drzwi, wyrwanie
zawiasu, upadek skrzydła i wybuch drzwi. Odsłuch A/B jak w B3. Wybrane pliki idą przez generator i manifest, bez ręcznych kopii.

## Pozostałe punkty z analizy

### Barykady przy drzwiach (S4 w części barykad)

Dane pokazują, że barykady stoją na przejściach, którymi drużyna sama wraca. Wyważone drzwi budynków z generatorami (1.2:
hala stacji, pompownia) to naturalne miejsca obrony. Uruchomienie generatora robi hałas, a drużyna może się zabarykadować na czas
rozruchu. Plan:
- wyważone drzwi są miejscem barykady (jak rozbite `%`);
- barykady na przejściach, które drużyna musi pokonać dwa razy, do przeglądu. `_shortcut_report` i trasa misji pokażą, które to są;
- **bez zmian w balansie kul w drewno**, dopóki drzwi nie dadzą więcej okazji (drewniane drzwi z dystansu: amunicja i hałas
  zamiast podejścia). Pomiar po W3.

### Zawał w galerii 1.1 (powrót D3 na kampanię)

B0 (1.7.494) zdjął stemple z kampanii, bo hale miały 4–5 rzędów. Warunek powrotu: niskie przejście 2–3 rzędy pod skałą. Galeria
kopalni 1.1 (wiersze 31–33) go spełnia.
- 1 stempel + strefa w miejscu, gdzie zawał za sobą odcina pościg i nie odcina celu. Miejsce wybrane skanem nawigacji, nie
  przybliżeniem (pułapka z D3).
- Modele zawału 2–3 rzędy z `tools/rubble_pile_gen.py` (dziś są tylko 4–5).
- `--maptest` (`cave_checked`), `--finaletest` (zawał finału 1.1 otwiera wszystkie strefy).

### B1 — osłony na arenie Pijawki

Dziś na B1 nic się nie niszczy. Pomysł: osłony (deski, blacha), które boss rozbija, więc kryjówki znikają z czasem walki. Najpierw
trzeba sprawdzić ataki Pijawki (`--leechtest`: zasadzka, plucie, QTE), czy osłona w ogóle coś zmienia. Wtedy osobny mini-plan
w tym pliku. Zalecam po drzwiach.

### Spadająca kładka (zaległe z D3)

Zestrzelony albo wyłamany słup i kładka spada. Kładki `-` są kaflami, więc spadająca musi być osobnym węzłem z kaflami
zarezerwowanymi dla nawigacji (jak `_wall_cells`). Ryzyko jest najwyższe z tej listy: geometria, nawigacja, dyrektor. Na koniec
i tylko jeśli drzwi i zawał się sprawdzą.

## Etapy

| Etap | PR | Zawartość | Ryzyko |
|---|---|---|---|
| **W0** spike obrazu drzwi | 0 (gałąź robocza, wynik do planu) | warianty A/B, zrzuty posterunku 1.3 (drzwi 2 rz.) i hali stacji 1.2 (brama z furtką), noc + latarka, `--shotwall=Door1` | średnie (czytelność) |
| **W1** mechanika + posterunek 1.3 | 1 | materiały `door_*`, `DOORS`, rejestracja w `level.gd`, komunikaty, pasek akcji, wrogowie i bot, `--destructiontest` sekcja drzwi, `--maptest`, sieć (`door=` w `_destruction_sig`), dziennik `break` z `door_*`, 3D wg wyniku W0 | średnie |
| **W2** wszystkie budynki | 1 | furtki w bramach (decyzja 4), `DOORS` na 1.2 i 1.3, hala Żyły z punktem kontrolnym bossa, sprawdzenie wysokich wrogów, `--veintest`, `--funtest` | średnie (projekt map) |
| **W3** dźwięk i wyważenie | 1 | nagrania A/B, skrzydło na zawiasie / wyrwane / osmalone, rozgrzanie (`_warm_destruction("door_*")`) bez przycięcia (`--hitchtest`) | niskie |
| **W4** barykady przy drzwiach | 1 | miejsca barykad przy budynkach z generatorami, przegląd barykad na trasie | niskie |
| **W5** zawał 1.1 | 1 | stempel i strefa w galerii, modele 2–3 rz. | średnie |
| **W6** B1 osłony | 0–1 | najpierw sprawdzenie mechaniki bossa, potem decyzja | średnie |
| **W7** spadająca kładka | 1–2 | osobny węzeł, nawigacja, dyrektor | wysokie |

Każdy PR zmieniający grę podbija `config/version` i dopisuje wiersz do `CHANGELOG.md`. README i GDD tylko tam, gdzie opisują
przegrody i budynki.

## Testy

- `--destructiontest`, nowa sekcja drzwi:
  - maczeta wyważa drewniane, odbija się od metalowych z jednym komunikatem;
  - kilof wyważa metalowe, w zbrojone daje iskrę i hałas;
  - 1 granat metalowe, 2 granaty albo 1 ładunek zbrojone;
  - kule — dziury w drewnianych, wgniecenia w metalowych;
  - wzrok, światło i dźwięk przez zamknięte, przez pasy i dziury;
  - Trzosek drapie tylko drewno, Rzeźnik łamie metal, Stalker przez metal wolniej, bot maczetą i kilofem, bot nie rzuca;
  - reset przy wipe, punkt kontrolny bossa, dołączający, `start: broken`, barykada w wyważonych.
- `--maptest`: drzwi przy każdym wejściu budynku, osiągalność bez materiałów wybuchowych, skróty.
- `test_net_session.sh`: host wyważa drzwi drewniane i metalowe, klient i dołączający widzą to samo (`door=`).
- `--fxtest` / zrzuty W0: czytelność stanów z kamery gry.
- Regresje jak w S0–S3: `--enemytest`, `--stalkertest`, `--bottest`, `--nobottest`, `--funtest`, `--veintest`, `--finaletest`, `--gentest`.

## Pomiar

`session_progress.py`, sekcja „Niszczenie”, wiersz drzwi:
- wyważenia wg materiału i narzędzia;
- czas od pierwszego ciosu do przejścia;
- Uwaga po wyważeniu, pobudki Stalkera i elit do 20 s;
- ile drzwi drużyna wysadza i czym;
- czy gracze omijają budynki;
- barykady przy drzwiach: przybite, wytrzymały, kto rozbił.

Sygnały:
- mediana wyważenia > 8 s (żmudne);
- ponad połowa wyważeń budzi Stalkera (za drogie);
- nikt nie otwiera zbrojonych (nagroda za mała);
- barykady dalej rozbija sam gracz.

## Ryzyka

| Ryzyko | Skutek | Środek |
|---|---|---|
| Drzwi zbrojone na jedynej drodze | utknięcie bez granatu | zasada 1, `--maptest`, zbrojone tylko poza trasą (decyzja 5) |
| Zbyt wiele wyważeń na trasie (do 9) | żmudna misja | decyzja 2: na trasie jedne zamknięte drzwi na budynek |
| Skrzydło nieczytelne z kamery | gracz nie wie, czym wyważać | spike W0 przed W1, materiał w modelu i kolorze, komunikat |
| Wysunięta ściana wejścia znika | budynki znów jak zlepek brył | wariant A w W0 |
| Wysocy wrogowie nie mieszczą się w furtce | Rzeźnik / Stalker utyka | W2: test nawigacji wg rodzaju ciała, w razie czego brama na całą wysokość z obrazem bramy wyrwanej |
| Arena Żyły zamknięta przy restarcie | gracz musi ponownie wyważać | stan drzwi w punkcie kontrolnym bossa (już jest dla przegród) |
| Metal głośny przy kilofie | Stalker zawsze przy drzwiach | pomiar, strojenie `n_hit` |

## Decyzje

Wszystkie przyjęte 2026-11-22 zgodnie z zaleceniami (warianty odrzucone).

1. **Zakres:** wszystkie budynki 3D na misjach — 1.2: hala stacji, pompownia; 1.3: posterunek, Skład, hala Żyły (9 wejść).
   Kryjówka, B1 (bez otworów) i 1.1 (bez budynków) poza zakresem. *Zalecam:* tak. Wariant: drewniane tamy wentylacyjne w kopalni 1.1
   (nie budynek, ale drzwi pod ziemią) — w osobnym planie.
2. **Ile zamkniętych na starcie?** Drzwi ma każde wejście. *Zalecam:* na trasie głównej po jednych zamkniętych drzwiach na budynek,
   drugie wyważone (`start: broken`, leżące skrzydło jako ślad poprzedniego patrolu, miejsce na barykadę). Wychodzi 5 wyważeń na dwie
   mapy zamiast 9. Wariant: wszystkie zamknięte.
3. **Materiały wg budynku.** *Zalecam:*
   - hala stacji 1.2 (cegła): zachód drewniane, wschód wyważone;
   - pompownia 1.2: zachód metalowe, wschód wyważone;
   - posterunek 1.3 (bunkier): zachód metalowe, wschód wyważone;
   - Skład 1.3: zachód drewniane, wschód wyważone;
   - hala Żyły 1.3: metalowa brama z furtką.

   Przy wariancie z decyzji 2 „wszystkie zamknięte” wschodnie wejścia jako metalowe.
4. **Bramy 4 rzędy:** *Zalecam:* furtka 2 rzędy, górna część bramy stała (obraz bramy z furtką). Wariant: cała brama jako przegroda
   na 4 rzędy.
5. **Drzwi zbrojone:** na trasie byłyby pułapką (granat 1 na misję). *Zalecam:* tylko do nowych, małych pomieszczeń pobocznych
   z łupem (sejf, skrzynia mocy, taśma) — po jednym na 1.2 i 1.3, miejsca wybrane w W2 skanem nawigacji. Wysadzenie to decyzja:
   granat albo ładunek za łup i hałas. Wariant: zbrojone także na trasie, z objazdem (dach, szyb).
6. **Kule w drzwi:** *Zalecam:* drewniane jak deski (S1), metalowe tylko wgniecenia, zbrojone nic.
7. **Wrogowie:** *Zalecam* tabelę wyżej: Trzosek tylko drewno, Rzeźnik drewno i metal, Wołek drewno, Stalker drewno i metal
   (wolniej), zbrojonych nikt.
8. **Bot:** *Zalecam:* maczetą i kilofem tak, materiałami wybuchowymi nie (jak S3: bot nie strzela w przegrody).
9. **Barykady:** *Zalecam:* wyważone drzwi budynków z generatorami jako miejsca barykad (W4); balans kul w drewno bez zmian do
   pomiaru po W3.
10. **Reszta z analizy:** *Zalecam* kolejność W5 zawał 1.1 → W6 B1 (po sprawdzeniu bossa) → W7 spadająca kładka (opcjonalnie).
