# SHOOT_DESTRUCTION_PLAN — ostrzał niszczy drewniane przeszkody

Stan wyjścia: main 1.7.554 (761ec1d9, 2026-11-13). Kontynuacja `DESTRUCTION_PLAN.md` (D0–D5) i `BARRIER_FIX_PLAN.md` (B0–B3).
Prośba autora: „strzały z broni powinny niszczyć drewniane przeszkody i ściany”. Ten plik to analiza i plan — **nic nie jest wdrożone**.

**Stan (2026-11-13):** decyzje 1–7 przyjęte zgodnie z zaleceniami (sekcja „Decyzje”). Następny krok: S0.

Skala: kafel 16 px ≈ 1,31 m, więc 1 px ≈ 8 cm.

## Werdykt

Fundament jest gotowy: przegrody z HP i materiałem, maska uszkodzeń, dziury na wylot, lokalna nawigacja, stan zniszczeń z resetem
i dołączającymi, test sieci. Brakuje trzech rzeczy:

1. **Reguły.** Deski świadomie nie przyjmują pojedynczej kuli (`breaks` bez `bullet`). Kula się odbija, a gracz dostaje komunikat
   „Deski: nie kulami”.
2. **Modelu obrażeń od kul.** Dziś liczy się tylko „przyjmuje / nie przyjmuje”. Gdyby po prostu dopisać `bullet`, M-83 rozbiłby deski
   po 8 trafieniach. Każda kula dodawałaby też 1,2 Uwagi i wybijała dziurę o promieniu ok. 18 cm. Po jednej serii deska byłaby sitem
   dla wzroku wrogów, a Uwaga skoczyłaby jak po granacie.
3. **Zgodności obrazu z symulacją.** Widok 3D już dziś zrzuca deski wraz z utratą HP. W 2D (wzrok, kule, dźwięk) przegroda zostaje
   jednak pełna aż do rozbicia. Przy ostrzale ta różnica będzie widoczna od razu: przez dziurę widać ciemność za deskami, a kula
   się w niej zatrzymuje.

Plan: kule ranią **drewno** (deski `%`, barykady `:`) według kalibru i przebicia, zostawiają małe przestrzeliny i przechodzą przez deski
słabsze. Deski odpadają **pasami** — w obrazie i w symulacji tak samo. Przejście otwiera się, jak dziś, po rozbiciu całości. Cegła `q`
od kul tylko się wyszczerbia (decyzja 2). Kafle mapy dalej są nietykalne.

## Co dziś robi broń z przeszkodami (ustalone w kodzie)

### Mechanizm

- **Kula / śrut** (`projectile.gd:260-272`): w przegrodę (`Sight.barrier_of`) na wysokości dziury (`hole_at`) kula leci dalej. W innym
  miejscu serwer zadaje przegrodzie trafienie `bullet` i **pocisk zawsze kończy lot**, bez przebicia, nawet BZ (`pen` 2,4). Przebicie
  (`_pass_through`, `pen_cost`, `projectile.gd:282-294`) działa tylko na ciała i rekwizyty: skrzynia 0,6, beczka 1,5, ciało 1,0.
- **Rodzaj trafienia** (`breakable.gd:93-106`): `bullet` / `pellet` liczy się z `Weapons.def(w).pellets`, czyli z **bazowej** broni,
  bez naboju. **Błąd:** kartacz 40 mm (10 śrucin, `ammo.gd:71`) liczy się jako `bullet` i odbija od desek. Brenneke (1 pocisk) liczy się
  jako `pellet`, bo bazowy SPREAD-12 ma 5 śrucin. `info["pellets"]` z `Combat.make_info` (`combat.gd:34-43`) ma już poprawną wartość.
- **Materiały** (`breakable.gd:43-65`): deski 60 HP przyjmują `pick blade pellet blast charge claw`, bez `bullet`. Cegła 120 HP przyjmuje
  `pick blast charge`. Kratka ma ciało na warstwie 128, której kule w ogóle nie widzą (`projectile.gd:23` `MASK_AUTH` = 1|2|4|32).
  Stempel przyjmuje `bullet`, ale jest tylko na mapie testowej `t_mine`. Odbite trafienie nie robi plamy, a człowiek dostaje raz na
  przegrodę komunikat o złym narzędziu (`_tell_bounce`, `breakable.gd:177-199`).
- **Wiązka LR-7 i szyna SPECTER-1** (`combat.gd:115-188`, `weapon_controller.gd:1280`, `:1335`): przegroda to dla `trace` ściana. Celem jest
  tylko grupa `enemies`, więc deski nie obrywają. Szyna z ulepszeniem `wall_pierce` (`parts.gd:162`) **przechodzi przez deski bez
  obrażeń** (`_wall_depth`).
- **Płomień HKM-9** (`in_cone`, `combat.gd:232`): przegroda jest w stożku, ale `fire` daje pusty `hit_kind`, więc drewno się nie pali.
- **Wybuch** (`combat.gd:299-303`): przegroda w promieniu dostaje **pełne** `damage`, bez spadku do brzegu. Kratka padnie od 1 wybuchu,
  gruz od 2 (`blasts`).
- **Hałas** (`breakable.gd:163`, `noise_manager.gd:311-334`): `n_hit` jest doliczane **przy każdym trafieniu**, a Uwaga się sumuje.
  Jeden strzał PELLET-8 w deski (8 śrucin × 1,2) to 9,6 Uwagi plus 4,5–6 za strzał, czyli prawie granat (`N_GRENADE` 15).
- **Dziury** (`breakable.gd:216-227`, `:278-296`): stopień plamy liczy się z udziału w HP (< 10% / < 34% / więcej). Dziura powstaje od
  stopnia 1, a jej promień to `SPLAT_R` × 1,5. Kula: 1,5 px → 2,25 px ≈ 18 cm. Śrucina: 1,8 px ≈ 15 cm. Pamięć to `MAX_SPLATS` 64
  i `MAX_HOLES` 32 (`:73-74`). **Pułapka na przyszłość:** dołączający i reset odtwarzają dziury tylko z 64 ostatnich plam
  (`send_state_to` `:349`, `reset_damage` `:326`). Przy ostrzale (kilkadziesiąt plam) stare dziury u dołączającego znikną, a u hosta zostaną.
- **Obraz 3D** (`view3d.gd:3086`, `_sync_barricade` `:4263`): każda przegroda `planks` pokazuje tyle desek, ile ma HP
  (`boards(3)`), w kolejności z hasha nazwy. Symulacja 2D tych luk nie zna.
- **Nawigacja po rozbiciu** (`level.gd:1494-1528`): `break_wall` → `_open_wall` → `_refresh_region` (lokalnie ok. 1–2 ms, D0). Kafle
  przegrody to `_wall_cells`.

### Wyniki dla desek (60 HP)

| Broń / nabój | Dziś (strzałów do rozbicia) | Uwagi |
|---|---|---|
| P-83 (9×18) | ∞ — odbija się | komunikat „nie kulami” |
| M-83 PS / US / BZ / HOT | ∞ — odbija się | BZ też, choć przebija beczkę |
| SPREAD-12 śrut | 2 z bliska (≤ 3,3 m), ok. 5 z daleka | `pellet`, 5 × 7 |
| SPREAD-12 Brenneke | 3 | liczy się jako `pellet` (błąd rodzaju, wynik przypadkiem rozsądny) |
| PELLET-8 | 1 z bliska (≤ 1,6 m), 3 z daleka | 8 × 10 |
| WRATH-4 kartacz 40 mm | ∞ — odbija się | **błąd** rodzaju trafienia |
| WRATH-4 HE, granat | 1 | pełne obrażenia w promieniu |
| SINEW-6 bełt, FALCON-6 | ∞ | `bullet` |
| SPECTER-1 szyna, LR-7 wiązka | ∞ | ściana dla `trace`, szyna z ulepszeniem przelatuje |
| HKM-9 | ∞ | nie pali drewna |
| maczeta / kilof | 2 / 2 | |

### Pozostałe drewniane i „ściany”

- **Skrzynie `k`** (`prop.gd:29`, `:203-224`): **już pękają od każdej kuli** (40 HP: pistolet 4 trafienia, M-83 5). 7,62 przechodzi
  przez skrzynię (`PEN_CRATE` 0,6). Bez zmian.
- **Okna `|`, lampy `I`**: kula tłucze szybę i klosz i leci dalej (D1). Bez zmian.
- **Kładki `-`** (`level.gd:112-125`): kafel jednokierunkowy na warstwie 16, przez który kule przelatują. Kafle wypiekane w 3D niszczyć
  nie wolno (`DESTRUCTION_PLAN.md`, ograniczenia). Spadająca kładka to osobny punkt D3 (słup jako stempel).
- **Ściany budynków i szop**: kolizja to kafle `C` / `M` / `#`. Drewno szop i strażnicy 1.1 to tylko obraz (`building3d.gd:7`,
  `level3d.gd` dachy i nogi). Chata radiowa 1.2 ma ściany `C`. **Drewnianych ścian jako kolizji nie ma** — jedyne drewniane „ściany”
  to przegrody `%` i barykady `:`.
- **Mapy kampanii** (liczone z `MAP` w `scripts/maps/`): 1.1 — deski kol. 50 r. 33 i kol. 208 r. 42, otwór `:` kol. 189; 1.2 — deski
  kol. 66 i 158, cegła `q` kol. 150, kratka kol. 214, otwór `:` kol. 243; 1.3 — deski kol. 31, kratka kol. 37, otwór `:` kol. 46. B1 bez
  przegród. Razem **5 desek, 3 otwory na barykady, 1 cegła**.

## Zasady (przyjęte 2026-11-13)

1. **Kula dziurawi, śrut i wybuch rozbijają.** Pojedyncza kula robi przestrzelinę i odłupuje drewno. Otwarcie przejścia samą bronią
   palną kosztuje pół magazynka M-83 i daje dużo hałasu. Śrut i wybuch zostają szybkie. Kilof dalej jest najcichszym kluczem.
2. **Obraz = symulacja.** Co widać jako szparę, przez to widać, świeci i strzela. Czego nie widać, to blokuje.
3. **Zniszczenie nadal tylko tam, gdzie mapa oznaczy.** Kafle mapy, kładki i ściany budynków są nietykalne. Bezpieczna droga bez
   niszczenia zostaje (`--maptest`).
4. **Serwer rozstrzyga, peery liczą to samo z tych samych danych.** Dziury i pasy są stanem przegrody: w resecie, w punkcie
   kontrolnym i u dołączającego.

## Etapy

### S0 — porządki i pomiar (bez zmiany zasad gry, 1 PR)

- `breakable.hit_kind`: liczba śrucin z `info["pellets"]` (naprawa kartacza 40 mm i Brenneke) i nowy rodzaj `slug` (Brenneke, `ammo.gd:51-53`),
  żeby dało się go stroić osobno. Rodzaje `rail` i `beam` dostają własny `hit_kind`, na razie bez wpisu w `breaks`.
- Hałas przegrody **na paczkę** (`_flush`, co `SPLAT_GAP`), a nie na trafienie: `n_hit` raz na paczkę, z mnożnikiem wg rodzaju
  (`n_kind`, np. kula w drewno 0,3, śrut 1,0, cios 1,0). Strzał PELLET-8 w deski: z ok. 9,6 do 1,2 Uwagi za uderzenie plus wystrzał.
- `--maptest`: miara **skrótu**. Dla każdej przegrody i otworu długość trasy start → cele → wyjście przy całej i przy rozbitej
  (`_nav_len` jak w szacunku trasy, `main.gd:4590-4600`). Wydruk w `[MAPTEST]`, bez progu.
- `--destructiontest` sekcja 16 „ostrzał”: **prawdziwe pociski** (`Projectile` przez `_sweep`, nie samo `Combat.apply`) każdej broni
  i naboju w deski, cegłę, kratkę i skrzynię. Wydruk tabeli „strzałów do rozbicia / Uwaga / dziur”, a sprawdzenia tylko dla tego,
  co S0 zmienia (kartacz rani deski, hałas raz na paczkę).
- **Ukończone, gdy:** tabela z testu zgadza się z „Dziś” powyżej poza kartaczem i hałasem; `--maptest` wypisuje skróty na 1.1–1.3;
  regresje zielone (`--destructiontest`, `test_weapons.sh`, `--maptest`, `test_net_session.sh` sekcja zniszczeń).

### S1 — kule ranią drewno i przechodzą przez nie (1 PR, rdzeń)

- Materiał dostaje pole `shot` (wpływ pocisków):
  `{"bullet": mnożnik, "slug": …, "pellet": …, "rail": …, "beam": …, "pen_ref": 1.0, "pen_cost": 0.8, "hole_r": 0.45}`.
  Obrażenia kuli = obrażenia z pocisku (spadek z dystansem, energia) × `mnożnik` × `clamp(pen / pen_ref, 0.25, 2.0)`. Przebicie
  liczy się więc tak samo jak przy ciałach: twardy rdzeń łupie mocniej niż miękka kula pistoletowa.
- **Deski** (`planks`, także barykady `:`): `bullet` 0,5, `slug` 1,0, `pellet` 1,0 (jak dziś), `rail` 1,0. Wartości startowe do strojenia:

  | Broń / nabój | Trafień do rozbicia 60 HP | Za deską (energia) |
  |---|---|---|
  | P-83 | ok. 22 (ok. 3 magazynki) | zostaje w desce |
  | M-83 PS | ok. 13 (pół magazynka) | przechodzi, ok. 33% |
  | M-83 US / HOT / BZ | ok. 28 / 10 / 7 | 0 / ok. 45% / ok. 67% |
  | Brenneke | 2 | przechodzi, ok. 38% |
  | Śrut, PELLET-8 | jak dziś | zostaje (`pen` 0,3) |
  | SINEW-6 bełt | ok. 11, wbija się w deskę | zostaje |
  | FALCON-6 | praktycznie nic (`pen` 0) | zostaje |
  | SPECTER-1 | 1 | przechodzi (jak przez cel) |

- **Przebicie przegrody** (`projectile.gd:260-272`): po trafieniu serwer i kopia kosmetyczna u klienta pytają tę samą funkcję
  `pen_cost` (przegroda z polem `pen_cost`). Jeśli energii wystarczy, kula leci dalej słabsza (`_energy`), jak przez skrzynię, i trafia
  wroga za deskami. W przeciwnym razie kończy lot jak dziś. Cegła ma `pen_cost` ∞.
- **Przestrzelina**: kula i Brenneke dają **stopień 0 w HP plamy, ale z dziurą o promieniu `hole_r`** (0,45 px ≈ 4 cm zamiast
  dzisiejszych 18 cm). Przez taką dziurę promień wzroku i kula przechodzą tylko na tej wysokości — wizjer, nie sito. Śrut z bliska,
  cios i wyrwa (stopień ≥ 1) dają dziury jak dziś.
- **Cegła `q`**: kula daje plamę stopnia 0 (wyszczerbienie w masce 3D, kurz), **bez HP** i bez komunikatu (decyzja 2). Komunikat
  „nie kulami” zostaje dla kratki (kule i tak przez nią przechodzą) i cegły tylko przy maczecie.
- **Szyna** (`weapon_controller._server_rail`): `trace` zwraca też przegrody na drodze (pole `barriers`). Serwer zadaje im `rail`,
  a promień idzie dalej przez rozbite albo z `wall_pierce`. **Wiązka i płomień**: bez zmian (decyzja 5).
- Pamięć dziur poza listą plam: `holes` w `send_state_to` i w `breakables_state` / `reset_damage`, osobno od `splats`. Dołączający
  i reset nie gubią więc dziur sprzed 64 ostatnich plam. Limit dziur podniesiony do 64, a przy przepełnieniu łączą się najbliższe
  w pionie, zamiast wypadać najstarsze.
- Dźwięk: kula w deskę to dzisiejszy `Vfx.impact` „wood” (B3) plus drzazgi po **drugiej** stronie przy przebiciu. Rozbicie jak dziś.
- **Ukończone, gdy:** sekcja 16 sprawdza tabelę (±1 trafienie), przebicie (wróg za deskami dostaje ułamek obrażeń, pistolet nie),
  cegłę (HP stałe, plamy przybywa), szynę i stare sekcje 11–13. Sprawdzenia „kula pistoletu nie rani desek”
  (`destruction_test.gd:715`) i „kula nie przebija” (`:833`) zmieniają znaczenie. `test_weapons.sh` (391 + 21 sieć) i `--maptest`
  bez zmian, a w `test_net_session.sh` klient strzela kulami w deski: host, klient i dołączający mają te same HP, dziury i rozbicie.

### S2 — deski odpadają pasami (1 PR)

- Przegroda z desek dzieli się na **pasy** — tyle, ile ma kafli wysokości (`rows`, 2–6). Każdy pas ma własne HP
  (`hp_bands`, suma = HP materiału). Kula, cios i drapanie ranią pas na wysokości trafienia, wybuch i szarża — wszystkie po równo.
- Pas z HP 0 to **odpadnięta deska**: otwarty dla wzroku, światła, kul i dźwięku (`hole_at` / `hole_in` zwracają prawdę w całym pasie,
  bez zmian w `sight.gd`), ale dalej zamknięty dla ruchu i nawigacji. **Przejście otwiera się dopiero przy wszystkich pasach na zero**
  (`break_wall` jak dziś; decyzja 4 — wariant z przejściem pod górną deską odłożony).
- Widok 3D (`_sync_barricade`): deski **z pasów**, a nie z ogólnego HP i kolejności z hasha. Odpada ta, którą trafiono. Barykada `:`
  (D2b, `level.nail_board`): przybicie wraca najniższy brakujący pas, bo najpierw trzeba zamknąć przejście dla Trzosków.
  `BOARDS` = 3 zastąpione liczbą pasów, a koszt (zapas desek albo 2 złomu) liczony za pas.
- Stan: `hp_bands` zamiast ułamka w `_splat_rpc` / `_splat_sync` / `breakables_state` / `_nail_rpc`. Wipe zeruje, punkt kontrolny
  przywraca, dołączający dostaje pasy.
- **Ukończone, gdy:** strzał w górny pas otwiera wzrok tylko na tej wysokości (wróg za deskami widzi latarkę na głowie, a gracz
  w kucki nie jest widoczny), zestrzelenie wszystkich pasów otwiera przejście i nawigację (graf = pełna budowa), przybicie wraca
  najniższy pas, a zrzuty 3D (`--shotwall=Planks1 --shotholes`) pokazują deski w miejscach z symulacji. `--destructiontest` (sekcje
  11–13, 16), `test_net_session.sh` (barykada zestrzelona do jednego pasa u klienta i dołączającego), `--fxtest`, `--hitchtest
  --hitchwall` (bez nowych przycięć).

### S3 — wrogowie, bot, dyrektor (1 PR)

- **Wrogowie**: wzrok przez otwarte pasy działa sam (S2). Hałas uderzeń kul przenosi ślad na barykadę (`_barricade_tick`,
  `enemy.gd:1239`), więc strzelanie przez deski ściąga Trzoski na barykadę. To zamierzone — sprawdzić, czy nie utykają.
- **Stalker** (`stalker.gd:530`, `_barricade_blocking`): bez zmian w logice, test pasów.
- **Bot** (`player.gd:1908`): **nie celuje w przegrody** (zostaje `_bot_chop_wall` kilofem). Jego kule we wroga za deskami ranią
  deski jak każde (decyzja 6). `--bottest`: bot broni barykady i nie zestrzeliwuje jej w całości przed falą (miara, bez progu do playtestu).
- **Dyrektor** (`_pick_spot`): bez zmian — wymaga drogi nav, a ta otwiera się dopiero przy rozbiciu.
- **Ukończone, gdy:** `--enemytest`, `--stalkertest`, `--bottest`, `--nobottest` zielone z override.cfg na świeżym katalogu.

### S4 — mapy i balans (1 PR, po playteście S1–S3)

- Z miary skrótu (S0): każda deska i otwór na 1.1–1.3. Deska, która **skraca drogę do celu głównego albo ewakuacji**, zostaje
  świadomym skrótem z kosztem: hałas serii i czas. Jeśli skraca za dużo (proponowany próg: ponad 40% trasy), przenieść ją albo
  zamienić na cegłę.
- Nocny Dyżur i trudności: mnożnik `bullet` dla desek bez zmian (prostota), hałas ze skalą trudności jak dziś.
- Pomiar w dzienniku sesji: `break` ma już `by` (rodzaj). Dopisać liczbę trafień wg rodzaju do rozbicia, sekcję „Niszczenie”
  w `tools/session_progress.py`: ile przegród otwarto kulami, ile Uwagi to kosztowało, ile barykad padło od kul drużyny.
- **Ukończone, gdy:** `--maptest` bez nowych błędów, decyzje per miejsce zapisane w tym pliku, raport z ludzkiego przebiegu.

## Ryzyka

| Ryzyko | Skutek | Zabezpieczenie |
|---|---|---|
| Skróty przez deski z dystansu | trasa krótsza, mniej napięcia | S0 miara skrótu, S4 przegląd; seria kosztuje Uwagę (zasada 4 D0) |
| Własna barykada zestrzelona przez drużynę | D2b traci sens | pistolet ok. 22 trafień, M-83 ok. 13 na całość; S2 pas po pasie; pomiar S4; decyzja 6 |
| Sito z dziur → wrogowie widzą przez deski | Darkwood-owy „wizjer” robi się oknem | dziura od kuli 4 cm zamiast 18; pasy otwierają się dopiero po zerze |
| Uwaga skacze przy serii | Stalker budzi się od strzelania w deski | hałas na paczkę (S0) |
| Rozjazd kopii kosmetycznej u klienta | kula „zatrzymana” u klienta leci dalej u serwera | ta sama funkcja przebicia i ten sam stan; rozjazd tylko przez czas RPC, kosmetyczny |
| Dołączający bez starych dziur | inna widoczność u hosta i dołączającego | S1: dziury w stanie osobno od plam |
| Koszt CPU przy serii | `window_changed` → siatka dźwięku po każdej paczce z nową dziurą | odświeżenie na paczkę (już), pomiar `--hitchtest` |
| Testy zakładające „kula nie rani desek” | czerwone CI | przepisane w S1 razem ze zmianą |

## Decyzje (2026-11-13: autor przyjął wszystkie zalecenia)

1. **Co niszczy ostrzał?** *Zalecam:* drewno — deski `%` i barykady `:` (skrzynie, okna, lampy już działają). Kładki i ściany szop
   poza zakresem: to kafle albo sam obraz. Spadająca kładka zostaje w D3.
2. **Cegła `q` od kul?** *Zalecam:* tylko wyszczerbienia bez HP (cegła = kilof albo wybuch, jak zasada klucza z B1). Inne warianty:
   powoli (np. BZ i Brenneke × 0,1) albo jak deski.
3. **Tempo i przebicie** — tabela S1: M-83 ok. 13 trafień, pistolet ok. 22, Brenneke 2, śrut jak dziś, 7,62 przechodzi przez deski
   słabsza. *Zalecam* te liczby jako start, strojenie po playteście.
4. **Kiedy przejście się otwiera?** *Zalecam:* po zerze wszystkich pasów (jak dziś, prosto dla nawigacji). Wariant: przejście, gdy
   odpadną dolne pasy na wysokość postaci (więcej pracy w nawigacji i kolizji).
5. **Wiązka LR-7 i płomień HKM-9?** *Zalecam:* bez obrażeń dla przegród. Palenie drewna to osobny temat: rozprzestrzenianie ognia,
   reset, sieć. Szyna SPECTER-1 rozbija deski jednym strzałem.
6. **Kule drużyny w swoją barykadę?** *Zalecam:* tak, jak każde (czytelność, filar „decyzja i koszt”). Pomiar w S4. Wariant:
   kule z wewnętrznej strony × 0,5.
7. **Bot strzela w przegrody?** *Zalecam:* nie — bot otwiera przejścia kilofem jak dziś.

## Kolejność i rozmiar

| Etap | PR | Ryzyko | Zależy od |
|---|---|---|---|
| S0 porządki + pomiar | 1 | niskie | — |
| S1 kule w drewno, przebicie, przestrzeliny | 1 | średnie (sieć, testy) | S0, decyzje 1–3, 5 |
| S2 pasy desek | 1 | średnie (barykada D2b, widok 3D) | S1, decyzja 4 |
| S3 wrogowie, bot | 1 | niskie | S2, decyzje 6–7 |
| S4 mapy i balans | 1 | średnie (projekt map) | playtest po S3 |

S0 nie zmienia zasad gry, więc może wejść od razu. S1 i S2 można scalić w jeden PR, jeśli autor woli jedną zmianę odczuwalną w grze.
