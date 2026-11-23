# DESTRUCTION_CONTENT_PLAN — drzwi budynków i treść niszczenia na mapach

Stan wyjścia planu: main 1.7.655 (203ed634, 2026-11-22). Kontynuacja `DESTRUCTION_PLAN.md` (D0–D5, w main do 1.7.506),
`SHOOT_DESTRUCTION_PLAN.md` (S0–S3, do 1.7.557) i `IMPACT_MARKS_PLAN.md` (1.7.655).

**Stan (2026-11-22):** decyzje 1–10 przyjęte zgodnie z zaleceniami (sekcja „Decyzje”). Spike W0 zrobiony: ościeżnica wystająca poza obrys
ściany + animowany „duch” narzędzia przy drzwiach (maczeta, kilof, ładunek; ikona HUD odrzucona przez autora), znika po wyważeniu. Sekcja „Obraz (3D)”.

**Stan (2026-11-23):** W1 zrobiony w 1.7.656 (gałąź `feat/doors-w1`): materiały `door_wood` / `door_metal` / `door_steel`, stała `DOORS`,
rejestracja w `level.gd`, posterunek 1.3 (dwoje metalowych, wschodnie wyważone na starcie), komunikaty i pasek akcji, Stalker, Wołek,
Rzeźnik i bot, `--maptest`, `--destructiontest` sekcja 21, widok 3D (ościeżnica, skrzydło zamknięte i leżące, duch 10 m / 3 pętle,
rozpływa się przy wyważeniu bez przebudowy świata). Sieć bez osobnego `door=` w `_destruction_sig`: drzwi to zwykłe przegrody
(`opened` w sygnaturze, ta sama ścieżka RPC co deski i kratka). Z listy „Do poprawy w W1” przechodzą do W2, bo w W1 na mapach są tylko
metalowe drzwi: wygląd drewna i pasy skrzydła drewnianego w 3D, furtka w bramie, widoczność maczety i ładunku ducha, strona drzwi.

**Stan (2026-11-23, W2):** W2 zrobiony w 1.7.657 (gałąź `feat/doors-w2`). `DOORS` w każdym wejściu budynku 3D na 1.2 i 1.3 (decyzje 2–3):
1.2 — hala stacji brama drewniana, pompownia brama metalowa, wschodnie wyważone; 1.3 — Skład brama drewniana, wschodnia wyważona, hala Żyły
metalowa brama w otworze bramy z korzeni (punkt kontrolny bossa pamięta wyważoną). **Decyzja 4 zmieniona (autor 2026-11-23):** bramy na całą
wysokość otworu, bez furtki — pomiar w W2: Rzeźnik ma 36 px, otwór 2 rzędów 32 px (Kapłan 32 px na styk), więc furtka zamknęłaby go w pompowni
i odcięła elitę dyrektora. Obraz: brama metalowa na całą wysokość, wyważona wisi krzywo na szynie obok otworu (poza pasem gry); drewniana
dwuskrzydłowa z listwami i zastrzałami, pasy skrzydła = pasy przegrody (odpadają z drzazgą), wyważona — resztki przy zawiasach i deski na ziemi.
Z listy „Do poprawy w W1”: drewno w teksturze `post` (słoje pionowe; `plank` dawała cegłę), duch maczety z ostrzem ×1,8, ładunek ducha
na słupku bez pasów (pasy tylko na nadprożu od W1), strona drzwi bez zmian — wszystkie zamknięte drzwi są od zachodu i drużyna podchodzi do nich
z zewnątrz. `--maptest`: wejście bez wpisu w `DOORS` na mapie kampanii to błąd. Zrzuty: `C:\deadair87\shots_doors\w2`.
Do W2b (decyzja 5): drzwi zbrojone do małych pomieszczeń pobocznych z łupem, po jednym na 1.2 i 1.3 — wymagają nowych budynków 3D na mapach.
Następny krok: W2b albo W3 (dźwięk i wyważenie).

**Stan (2026-11-23, W3):** W3 zrobiony w 1.7.658 (gałąź `feat/doors-w3`, stos na W2). Przyczyna i strona rozbicia idą do wszystkich peerów (`level.break_wall(nazwa, how, dir)`, `break_how`; dołączający i migawka bossa też), a widok 3D buduje wg nich wyważone skrzydło: metalowe drzwi podważone kilofem — otwarte na tylnym zawiasie z wyrwanym górnym (przodem do kamery, za pasem gry); wybite szarżą — płasko po stronie upadku; wysadzone i zawsze zbrojone — dalej, skręcone, osmalone (`*_burnt`, ten sam shader); brama kilofem wisi na szynie, wysadzona leży; drewno wysadzone — osmalone deski dalej. Kierunek z wektora ciosu / wybuchu / szarży zamiast ziarna. Dźwięk: `door_metal_hit` (Sound Spark „Metal Sheets Sledgehammer Hit 02” + RZ Post „Creepy Door, Metal Door Medium Impact 01”) i `door_metal_break` (Kopeikin „dry rusty metal impact with collapse 08” + Mechanical Wave „Drop Fall Metal Rattle Scrap Debris 06”), synteza w repo; **odsłuch A/B 2026-11-23: autor wybrał wersję z nagrań dla obu rodzin** (`C:\deadair87\odsluch\drzwi_w3.html`, `audio_ab.py --licensed --only door_metal`), pliki w lokalnym `prototype/audio_licensed/sfx/world/door_metal_*` (poza repo). Przycięcie: wspólny shader ducha narzędzia (każde drzwi kompilowały własny — 232 ms po odbudowie drzwi na 1.2), rozgrzewany pod planszą z osmalonymi materiałami; `--hitchtest --hitchdoor`. Wgniecenia od kul w metalu bez obrazu (kula w metal daje iskrę i ślad trafienia jak dotąd). Zrzuty: `C:\deadair87\shots_doors\w3`.

**Stan (2026-11-23, W4):** W4 zrobiony w 1.7.659 (gałąź `feat/doors-w4`). Wyważone drzwi każdego materiału (także wyważone na starcie, decyzja 2)
to miejsce barykady jak pusty otwór `:` (`barricade_spot.gd` przy każdych drzwiach): w otworze staje przegroda `planks` z pasami (deska na kafel,
brama 4, drzwi 2), `level.door_planks` pamięta, że to barykada, a nie drzwi — rozbita nie zmienia przyczyny wyważenia (`break_how`, obraz skrzydła),
wipe stawia z powrotem drzwi, punkt kontrolny bossa — barykadę (`breakables_state.door_planks`), dołączający dostaje wyważenie z przyczyną i potem
barykadę. Obraz: `Building3D.door_boards` — po dwie deski na pas w poprzek otworu przed licem, między słupkami ościeżnicy, krzywo; pas znika z drzazgą
jak pas drewnianej bramy. Tym samym hala stacji i pompownia 1.2 (generatory) mają miejsce barykady w obu wejściach. Przegląd barykad na trasie
(`_shortcut_report`): `%` i `:` na 1.1–1.3 to skrytki albo ślepe zaułki (objazd „brak”, trasa misji bez zmian) — bez zmian w mapach, pomiar w sesjach
(`barricade` w dzienniku ma nazwę przegrody, `Door*` = barykada w drzwiach). Zrzuty: `C:\deadair87\shots_doors\w4`.
Następny krok: W5 (zawał 1.1) albo W2b (zbrojone drzwi do nowych pomieszczeń z łupem).

**Stan (2026-11-23, W5):** W5 zrobiony w 1.7.660 (gałąź `feat/cave-w5`, stos na W4). „Galeria 1.1, wiersze 31–33” z analizy to sztolnia odwadniająca
(druga droga powrotu po finale). Miejsce ze skanu nawigacji: niski chodnik pod skałą między wnęką z baterią (kol. 137–141) a zalanym odcinkiem
z gniazdem ciem (150–175) — stempel `!` w kol. 144, strefa `^` w kol. 146 (3 rzędy, strop `#`). Drużyna idąca sztolnią na zachód łamie stempel
za sobą (kula przelatuje i łamie, śrut, kilof, wybuch) i zasypuje chodnik między sobą a pościgiem z sali: objazd 2900 px górą (`--maptest`,
`_cave_report`: na mapach kampanii objazd ≥ 800 px, inaczej zawał nic nie odcina), cele i wyjścia osiągalne przy zawalonej strefie
(`cave_checked`). Wnęka z baterią zostaje po stronie drużyny. Wstrząs finału rozsypuje gruz (jak od D3), więc stempel złamany przed finałem już
nie pomoże w ucieczce — `--finaletest` (zawał przed finałem, gruz rozsypany, restart stawia stempel). Modele zawału 3 rzędów:
`rubble_pile_{mine,concrete}_r3_{0,1}.glb` (`tools/rubble_pile_gen.py`, `ROWS = (3, 4, 5)`; do W5 3-rzędowe przejście dostawało ściśnięty
model 4 rzędów). Test B0 „kampania bez `^`” zastąpiony: strefy kampanii tylko ≤ 3 rzędy pod `#`, stempli tyle co stref. Zrzuty:
`C:\deadair87\shots_doors\w5` (`w5_prop`, `w5_cave`, `w5_dug`).
Do decyzji: porada przy stemplu (jak „adit” przy otworze) — dziś gracz musi sam zauważyć belkę. Następny krok: W2b albo W6 (osłony na B1).

**Stan (2026-11-23, W2b):** W2b zrobiony w 1.7.661 (gałąź `feat/doors-w2b`, stos na W5), plan przyjęty zgodnie z zaleceniami (sekcja „Drzwi
zbrojone do pomieszczeń z łupem”). Spike W2b-0 potwierdził oba miejsca; zmiany wobec szkicu: bunkier 1.2 w kol. 280–285 (nie 278 — drzwi
otwierałyby się nad szybem 272–277), kafle otworu drzwi `.` zamiast `b` (znaczniki beczki i Wołka przed drzwiami ciągnęłyby ścianę tła pod
gołe niebo, `test_structures.gd`), las 1.2 kończy się w kol. 279 (`test_front.gd`: podłoże lasu w przekroju bunkra). Skład 1.3: kol. 159–170,
strop w. 31, wnętrze 32–34, drzwi kol. 170 w. 33–34, półka `=` w. 35 kol. 171–174, beczka na półce. Wybuch beczki rani przegrody z polem
`barrel` w materiale (dziś tylko `door_steel`) jak jeden wybuch: sama beczka — 200 / 400, beczka + granat wyważają. Łup (`VAULT_LOOT`): złom 60 i granat
leżą od początku (widać je w przekroju razem z poświatą skrzyni mocy), część broni losuje serwer przy wysadzeniu (`level._vault_breach`, raz na
próbę, bez brakujących — 20 złomu). Czerwona lampa nad ościeżnicą (światło 1,7 m, bez cienia — większy zasięg przenikał przez ścianę), napis
„SIGNALS” / „SAPPERS” (`VAULT_SIGN`, PL: ŁĄCZNOŚĆ / SAPERZY) na tylnej ścianie, porada „vault” raz na 1.2. Dziennik `break` ma `src: barrel`.
`--maptest` (`_vault_report`): łup za zamkniętymi drzwiami nieosiągalny, po wysadzeniu osiągalny. Zrzuty: `C:\deadair87\shots_doors\w2b`
(`b0_*` spike, `b1_*` z lampą, napisem i łupem). Następny krok: W6 (osłony na B1, najpierw sprawdzenie bossa).

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

### Obraz (3D) — wynik spike'u W0 (2026-11-22)

**Co wyszło na zrzutach** (`C:\deadair87\shots_doors`, gałąź robocza `spike/doors-w0`):

1. Wszystkie 5 budynków to bryły `building3d.gd`. Dla nich `Level3D.set_shells` pomija wysuniętą ścianę wejścia (`level3d.gd:2580`),
   więc ryzyko z `ENTRY_KEEP` ich nie dotyczy. Warianty A/B z pierwszej wersji planu odpadają.
2. **Przegroda w otworze budynku jest z kamery niewidoczna.** Próba: deski `%` w zachodnim wejściu posterunku 1.3
   (`w0_planks_out/at`). Ściana szczytowa to bryła od z = −2,4 do 5,6 m (`building3d.gd:349`), bez wygaszania, i zasłania przód
   przegrody (z = 1,1). Postaci widać, bo rysuje je osobna kamera, drzwi już nie. Skrzydło w otworze stoi w płaszczyźnie y-z, więc
   kamera i tak widziałaby je krawędzią.
3. **Rozwiązanie (szkic autora 2026-11-22): ościeżnica wystająca poza obrys ściany + narzędzie 3D przy drzwiach.**
   - Ościeżnica wystaje 0,3 m poza oba lica ściany: słupki 0,16 m, nadproże 0,18 m, daszek. Jest w materiale drzwi:
     - drewno;
     - blacha w kolorze minii;
     - ciemna stal z pasami żółto-czarnymi na czole słupka i nadproża.
   - Czoło słupka od strony kamery niesie kolor i materiał. Widać je poza obrysem budynku z zewnątrz, a ościeżnicę wewnętrzną
     od środka hali.
   - Skrzydło siedzi na zewnętrznym końcu ościeżnicy.
   - **Narzędzie 3D przy drzwiach** (`Building3D.build_door_hints`) pokazuje w świecie, czym wyważyć drzwi. Zastąpiło ikonę HUD
     (tabliczka z `art/hud`, `door_marks.gd`), której autor nie przyjął. Narzędzie leży w płaszczyźnie kadru, w osi słupka od kamery,
     na zewnętrznym końcu ościeżnicy po stronie zewnętrznej:
     - drewno: maczeta (`gun_maczeta.glb`, skala 1,6 → ok. 0,95 m) wbita ostrzem 7 cm w ościeżnicę na 1,35 m, ostrze w dół
       jak po ciosie, rękojeść na zewnątrz;
     - metal: kilof (`gun_kilof.glb`, skala 1,3) wbity obuchem w szczelinę skrzydła na 1,15 m, trzonek w dół jak dźwignia
       (ten sam układ co znak strefy wydobycia, `DigEntrance3D.pick_parts`);
     - zbrojone: ładunek (`charge.glb`, skala znajdźki 0,65) na czole słupka na 0,95 m, czerwony lont w dół i 1,2 m po podłodze
       na zewnątrz, zapalnik na końcu.
     - **Wygląd i ruch (uwaga autora 2026-11-22: „ma animować akcję i wyglądać inaczej niż przedmiot gry, po zniszczeniu znikać”):**
       `door_hint3d.gd` — „duch” narzędzia, nie przedmiot: bez światła sceny i mgły, półprzezroczysty bursztyn z jaśniejszą
       krawędzią i liniami, bez cienia. W pętli 2,6 s pokazuje akcję: maczeta — zamach i cios w ościeżnicę z błyskiem i drżeniem;
       kilof — zamach, wbicie w szczelinę, podważenie skrzydła trzonkiem; ładunek — dosuwa się do słupka, mruga coraz szybciej,
       błysk i gaśnie. Po wyważeniu rozpływa się z błyskiem w 0,35 s (`dissolve()`); spike pokazuje to flagą `--doorbreakat=S`
       (po S s duch znika, świat przebudowany z wyważonymi drzwiami). Film: `shots_doors/mov/drzwi_podpowiedz_3d.mp4`.
   - **Wyważone:**
     - drewno — resztki desek przy zawiasach;
     - metal — skrzydło leży płasko przed drzwiami.

   Ościeżnica zostaje, więc dalej widać, że to było wejście.
4. Sprawdzone:
   - dzień (`--view3dlit`): trzy materiały (`w0_p_trio.jpg`);
   - noc z latarką: snop łapie czoło słupka i narzędzie (`w0_n_metal`, `w0_h_night4.jpg`);
   - narzędzie 3D: dzień (`w0_h_trio.jpg`), noc (`w0_h_night4.jpg`), brama 1.2 (`w0_hg_pair.jpg`);
   - widok od środka (`w0_in_metal`);
   - wyważone metal i drewno (`w0_br_*`);
   - brama hali stacji 1.2 z furtką (`w0_gates.jpg`).

   Koszt: ok. 20 skrzynek na drzwi w MultiMesh budynku, bez nowych świateł.

**Do poprawy w W1** (z zrzutów):
- Drewno: tekstura `plank` w rzucie triplanarnym 0,9/m na cienkich skrzynkach wygląda jak cegła. Brać materiał desek barykady
  (`view3d._prop_mat("plank")`) albo UV na element ze słojami w pionie.
- Brama: stała część nad furtką w minii dominuje kadr. Powinna zostać blachą bramy jak dziś (szyna, żebra), a kolor materiału tylko
  na ościeżnicy furtki.
- Furtka ma dziś szerokość całego otworu bramy (2,8 m). W W1 węższa (ok. 1,1 m) przy jednym słupku, reszta to stała brama.
- Wyważone drewno czyta się słabiej niż metal: dodać deski leżące na ziemi (drzazgi z `fracture_planks.glb` przy rozbiciu i tak będą).
- Narzędzie 3D (wynik zrzutów `w0_h_*`):
  - Kilof czyta się najlepiej (obuch w sylwetce).
  - Maczeta nawet w skali 1,6 to cienka kreska: ostrze ma 5 cm, szarość ginie na tle nieba i trzciny. Do sprawdzenia: jaśniejsze,
    lśniące ostrze, mocniejszy skos albo nacięcie (drzazgi) w ościeżnicy przy ostrzu.
  - Ładunek ginie na pasach żółto-czarnych; czyta się dzięki czerwonemu lontowi. Pasy przenieść na nadproże albo ładunek na skrzydło
    przy krawędzi ościeżnicy.
  - Strona drzwi: dziś zawsze zewnętrzna. W W1 strona, z której drużyna podchodzi na trasie misji (posterunek 1.3 i hala Żyły od środka?).
  - W W1 `dissolve()` z sygnału rozbicia przegrody (`breakable.gd`), bez przebudowy świata; u dołączającego do rozbitych drzwi ducha nie ma.
  - **Decyzja autora 2026-11-22:** duch tylko przy podejściu i najwyżej 3 pętle. W spike'u: lokalny gracz (bez bota hosta) bliżej
    niż 10 m od drzwi → pojawia się (0,3 s), gra 3 pętle (7,8 s) i gaśnie; znowu dopiero po odejściu dalej niż 14 m i powrocie.
    Wyważenie, gdy duch jest ukryty, nie daje błysku. Sprawdzone przebiegiem odległości (30 / 12 / 1 / 16 / 5 m) i filmem
    `shots_doors/mov/drzwi_podejscie_3petle.mp4`.

**Docelowo (W1–W3):**
- Zamknięte: skrzydło i ościeżnica jak wyżej. Stan z przegrody (`breakable.gd`) zamiast flagi.
- Wyważane:
  - drewniane — pasy odpadają (`band_mask`), drzazgi z `fracture_planks.glb`;
  - metalowe — wgniecenia, a po rozbiciu skrzydło na ziemi;
  - zbrojone — skrzydło odrzucone od ładunku (kierunek z ziarna, bez fizyki 3D), osmalenie (`impact_marks`).

### Dźwięk

Drewno z odsłuchu B3 (`wood_hit`, `wood_break`). Nowe nagrania z biblioteki Sonniss (`audio_lib`): kilof w blachę drzwi, wyrwanie
zawiasu, upadek skrzydła i wybuch drzwi. Odsłuch A/B jak w B3. Wybrane pliki idą przez generator i manifest, bez ręcznych kopii.

### Drzwi zbrojone do pomieszczeń z łupem (W2b) — plan przyjęty 2026-11-23

Decyzja 5 w szczegółach. Punkt wyjścia: drzwi zbrojone wymagają 2 wybuchów albo 1 ładunku burzącego, a drużyna ma na misję 1 granat
(ładunek 250 złomu, nie jest wydawany). Wybuch beczki `o` (`prop.gd explode`) rani wrogów, graczy i skrzynie, ale nie przegrody — bez zmian
pomieszczenie byłoby otwarte tylko u tych, którzy kupili ładunek.

**Decyzje (przyjęte zgodnie z zaleceniami):**
1. **Otwarcie — beczka przy drzwiach.** Przy każdych drzwiach zbrojonych stoi beczka; jej wybuch rani drzwi zbrojone jak jeden wybuch
   (`blasts`), tylko te (pole materiału, reszta przegród bez zmian). Wydany granat + beczka otwierają pokój bez zakupów; dalej też 2 granaty
   albo ładunek. Beczkę trzeba zestrzelić z dystansu (promień 64 px), da się ją pchać.
2. **Łup na pokój:** skrzynia mocy (1.2 WRATH-4, 8 granatów; 1.3 SPECTER-1), ok. 60 złomu, część broni (`Scrap.pick_find`, bez brakujących —
   próbka), skrzynka z granatem odłamkowym (zwrot wydanego). Taśm K4 nie ruszamy.
3. **Sygnał:** czerwona lampa nad drzwiami, napis szablonem na ścianie w 3D, duch ładunku jak od W1; porada raz, tylko na 1.2.
4. **Bot** bez zmian (decyzja 8): nie rzuca i nie strzela w beczki.

**Miejsca (kandydaci z przeglądu map, współrzędne potwierdza W2b-0):**
- 1.2 — **bunkier łączności** na powierzchni w ślepym końcu mapy za szybem do drezyny: kol. 280–285, strop w. 22, wnętrze w. 23–25, drzwi
  w ścianie zachodniej (kol. 280, w. 24–25), wschodnia przy krawędzi mapy. Przed drzwiami 2 kolumny gruntu (szyb 272–277 tuż obok —
  beczkę zestrzeli się zza szybu). Wołek i Podsłuchacz z kol. 280 / 282 przed drzwi i przy szybie: wysadzenie przy Podsłuchaczu to krzyk i horda.
- 1.3 — **skład saperów** w bloku betonu nad tunelem pod halą Żyły: kol. 159–170, strop w. 31, wnętrze w. 32–34, podłoga w. 35, drzwi
  we wschodniej ścianie (kol. 170, w. 33–34) do hali ze skrytką `H`; półka `=` w w. 35 (kol. 171–174) przy drzwiach, krok w górę z kładki
  w. 36. Wariant: blok pod posterunkiem (kol. 31–37) — wcześnie w misji, mniej wybuchów pod ręką.

**Etapy:** W2b-0 spike (kafle i wpis budynku na gałęzi, zrzuty 3D dzień / noc / od środka, skan nawigacji, ostateczne współrzędne) →
W2b-1 (1 PR): pokoje, `DOORS` steel, beczka i obrażenia od beczki dla zbrojonych, łup (`VAULT_LOOT` mapy), lampa i napis, porada,
dziennik `break` z przyczyną `barrel`, testy (`--destructiontest`: granat sam nie, granat + beczka tak, ładunek tak, beczka nie rusza muru
ani kratki, migawka i wipe; `--maptest`: cele przy zamkniętych zbrojonych, dojście do drzwi; `test_front.gd`; `test_net_session.sh`;
regresje `--enemytest`, `--veintest`, `--funtest`).

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

### B1 — osłony na arenie Pijawki (W6) — plan przyjęty 2026-11-23

Dziś na B1 nic się nie niszczy. Pomysł: osłony, które boss rozbija, więc kryjówki znikają z czasem walki.

**Sprawdzenie mechaniki (2026-11-23):**
- Kwas Pijawki (faza 2+, `acid_spit.gd`) leci łukiem po promieniu z maską brył (1) i znika na pierwszej bryle — przegroda go zatrzymuje.
  Przegląd 2026-11-01 (`leech.gd`): kwas to 15 z 19 upadków na B1.
- Geometria (tor ze wzoru `leech.gd _spit`: wylot 40 px nad wodą, lot `dist / 250` w 0,35–1,2 s, grawitacja 520): płyta 2 rzędów tuż przy graczu
  na wysokiej kładce (w. 27), od strony Pijawki, zatrzymuje **16 z 16** łuków z 40–340 px; 1 rząd — 13 z 16 (dalekie łuki spadają za nią);
  z kaflem odstępu — 13 z 16. Ta sama płyta zatrzymuje kule gracza strzelającego w dół do wody: za osłoną bezpiecznie, ale bez obrażeń.
- Brzeg i woda: osłona nic nie daje (zasadzka gryzie od dołu, fala przypływu zalewa niskie kładki i brzeg).
- B1 nie ma punktu kontrolnego bossa (`mission._start_boss`: `kind == "boss"`) — wipe to restart walki, osłony wracają z resetem przegród.
- `--leechtest` PASS. **Danych z gry brak:** ostatnie podejścia do B1 w dzienniku są z 13–21 października (1.7.211–1.7.340), sprzed HP 1300,
  znacznika plucia i rozróżnienia kwasu w dzienniku — `tools/leech_report.py` liczy tam 19 z 23 upadków jako `leech` i 0 jako `acid`.

**Decyzje (przyjęte zgodnie z zaleceniami):**
1. **Najpierw pomiar (W6-0):** 2–3 podejścia autora do B1 na 1.7.661 z dziennikiem; `python tools/leech_report.py --since 2026-11-23` — upadki
   wg źródła (`acid` / `leech` / przyzwane), czas, wynik, HP i faza bossa na końcu, flary. W6-1 ma sens, gdy kwas dalej jest głównym źródłem.
2. **6 płyt z blachy** (`sheet`, dziś na mapach 0) **2 rzędy** na wysokich kładkach, po dwie na kładkę. Miejsca z symulacji (gracz w każdej kolumnie
   kładki, Pijawka w każdej kolumnie basenu w zasięgu plucia 340 px; miara — ile kafli do najbliższego miejsca, w którym płyta zatrzymuje łuk):
   kładka 31–47 → kol. **37 i 46** (śr. 2,6 kafla), 57–75 → **58 i 74** (3,8), 85–110 → **86 i 99** (3,8). Jedna płyta na kładkę dawała 11–20 kafli.
3. **Płyta nie blokuje ruchu** (jak stempel: gracz przechodzi przed nią, w 3D stoi tuż za płaszczyzną gry), zatrzymuje kwas i kule. Wysokie kładki
   to droga ucieczki przed falą; pełna przegroda 2 rzędów (32 px) to granica skoku (ok. 42 px).
4. **Kwas przeżera płytę w 3 trafieniach** (maska uszkodzeń: blacha z dziurami, potem resztka) — osłony znikają w tempie plucia, od fazy 2 coraz
   szybciej. Wariant na później (po pomiarze): w fazie 3 Pijawka przepływa na stronę bez osłony, zanim plunie.
5. **Bez zmian balansu bossa** (HP, czasy) w W6-1; rytm walki: chowasz się na zapowiedź plucia (znacznik), wychodzisz strzelać w oknie wynurzenia
   po pluciu (1,1 s).

**Etapy:**
- **W6-0** (bez zmian w grze): pomiar z podejść autora (`tools/leech_report.py`), symulacja miejsc (wyżej) — **czeka na podejścia autora**.
- **W6-1** (1 PR): `COVERS` w danych B1 (kolumna, rząd, rzędy, materiał); płyta jako przegroda bez kolizji ruchu, która zatrzymuje kwas
  (`acid_spit.gd`) i kule; rodzaj trafienia `acid` rani `sheet`; obraz 3D blachy na podporach z przeżarciem, syk i plama przy trafieniu;
  reset przy wipe, dołączający, dziennik (`break` z `src: leech`); testy: `--leechtest` (płyta zatrzymuje kwas, 3 trafienia ją niszczą,
  kula gracza przez nią nie przechodzi, ruch tak, wipe przywraca), `--maptest`, `test_front.gd` (przekrój hali B1), `test_net_session.sh`;
  po wdrożeniu pomiar — odsetek upadków od kwasu i czas walki.

### Spadająca kładka (zaległe z D3)

Zestrzelony albo wyłamany słup i kładka spada. Kładki `-` są kaflami, więc spadająca musi być osobnym węzłem z kaflami
zarezerwowanymi dla nawigacji (jak `_wall_cells`). Ryzyko jest najwyższe z tej listy: geometria, nawigacja, dyrektor. Na koniec
i tylko jeśli drzwi i zawał się sprawdzą.

## Etapy

| Etap | PR | Zawartość | Ryzyko |
|---|---|---|---|
| **W0** spike obrazu drzwi — **zrobiony** | 0 (gałąź robocza `spike/doors-w0`, wynik do planu) | ościeżnica poza obrysem + narzędzie 3D (ikona HUD odrzucona); zrzuty posterunku 1.3 i bramy 1.2, dzień, noc z latarką, od środka, wyważone (`--doorproto[=wood\|metal\|steel] [--doorbroken]`) | — |
| **W1** mechanika + posterunek 1.3 | 1 | materiały `door_*`, `DOORS`, rejestracja w `level.gd`, komunikaty, pasek akcji, wrogowie i bot, `--destructiontest` sekcja drzwi, `--maptest`, sieć (`door=` w `_destruction_sig`), dziennik `break` z `door_*`, 3D wg wyniku W0 | średnie |
| **W2b** drzwi zbrojone do pomieszczeń z łupem — **zrobiony** (1.7.661) | 1 | bunkier łączności 1.2, skład saperów 1.3, beczka przy drzwiach, łup, lampa i napis | średnie |
| **W2** wszystkie budynki — **zrobiony** (1.7.657) | 1 | bramy na całą wysokość (decyzja 4 zmieniona: Rzeźnik nie mieści się w furtce), `DOORS` na 1.2 i 1.3, hala Żyły z punktem kontrolnym bossa, sprawdzenie wysokich wrogów, `--veintest`, `--funtest` | średnie (projekt map) |
| **W3** dźwięk i wyważenie — **zrobiony** (1.7.658, odsłuch A/B 2026-11-23: nagrania) | 1 | nagrania A/B, skrzydło na zawiasie / wyrwane / osmalone, rozgrzanie (`_warm_destruction("door_*")`) bez przycięcia (`--hitchtest`) | niskie |
| **W4** barykady przy drzwiach — **zrobiony** (1.7.659) | 1 | miejsca barykad przy budynkach z generatorami, przegląd barykad na trasie | niskie |
| **W5** zawał 1.1 — **zrobiony** (1.7.660) | 1 | stempel i strefa w galerii, modele 2–3 rz. | średnie |
| **W6** B1 osłony — plan przyjęty, W6-0 czeka na podejścia autora | 0–1 | pomiar z podejść (`tools/leech_report.py`), potem 6 płyt z blachy na wysokich kładkach przeciw kwasowi | średnie |
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
| Skrzydło nieczytelne z kamery | gracz nie wie, czym wyważać | W0: ościeżnica poza obrysem w materiale drzwi + narzędzie 3D przy drzwiach, komunikat |
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
   na 4 rzędy. **Zmiana 2026-11-23 (W2): cała brama** — Rzeźnik (36 px) nie mieści się w furtce 2 rzędów (32 px).
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
