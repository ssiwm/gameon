# BARRIER_FIX_PLAN — przegrody do poprawy po playteście 1.1

Stan wyjścia: main 1.7.492 + PR #595 (build 1.7.493+b594644), 2026-11-04. Kontynuacja `DESTRUCTION_PLAN.md` (D0–D3 wdrożone).
Źródło: pierwszy ludzki przebieg 1.1 z niszczeniem (dziennik `2026-11-04_12-10-30.jsonl`, solo, NORMAL, bez bota) i uwagi autora.

**Stan (2026-11-04):** B0 scalone (#597, 1.7.494). B1 (kilof u każdego) scalone (#598, 1.7.495) — bez rozgarniania gruzu (czeka na mapę z zawałem, decyzja 5). B2 (kratka, deski i mur w poprzek korytarza) w 1.7.496 — bez gruzu (decyzja 5). W trakcie B0 zapadła decyzja 5 — **zawał zdjęty z 1.1, 1.2 i 1.3**;
mechanika zostaje na przyszłe mapy w podziemiach z niskimi przejściami i jest testowana na mapie testowej `t_mine`.
Punkty planu o gruzie i stemplach na mapach kampanii (B1 rozgarnianie, B2 gruz, B4 zawał) czekają przez to na pierwszą taką mapę.

## Werdykt

Przegrody mają dziś postać „zamka bez klucza”: mapa stawia przeszkodę, a gracz zwykle nie ma czym jej otworzyć, nie wie czym,
a za przeszkodą nie ma niczego, dla czego warto by kombinować. Do tego źle brzmią i (kratka) źle wyglądają. Same poprawki dźwięku
i modeli tego nie naprawią — trzeba najpierw ustalić **zasadę klucza** i **po co przegroda stoi**, a dopiero potem dopieszczać.

## Co pokazał playtest (fakty z dziennika i kodu)

| # | Objaw (autor) | Przyczyna w grze | Gdzie |
|---|---|---|---|
| 1 | Kraty nie da się przejść: brak narzędzi i ładunków | Kratka `+` (kol. 247) puszcza tylko `pick` i `blast`. Gracz miał maczetę (zestaw `(0, 1, 10)`): kilof i maczeta dzielą **jeden** slot broni białej, a kilof wybiera się w kryjówce. Granat: 90 obrażeń w środku, 45 na brzegu, kratka ma 90 HP — trzeba trafić idealnie albo rzucić dwa; na starcie jest 1 granat (`issue 1`), a gracz zużył 2 na wrogów, zanim doszedł do kratki. Ładunek burzący: tylko z zakupu (250, `issue 0`) | `breakable.gd` `MATERIALS.grate`, `throwables.gd`, `weapons.gd` (KILOF) |
| 2 | Nie wiadomo, co czym | Zły cios odbija się bez obrażeń i bez komunikatu. Podpowiedź „pickaxe” pokazuje się **tylko temu, kto już ma kilof** — gracz z maczetą nigdy się nie dowie, że kilof istnieje | `hints.gd:121`, `breakable.take_hit` (`hit: false`) |
| 3 | Kratka źle wygląda | Pełna wysokość korytarza od podłogi do sufitu, pionowe pręty — wygląda jak drzwi celi, nie jak kratka wentylacji; brak ramy, śrub, rdzy i stanów uszkodzenia (cała → rozbita) | `view3d._grate_bars`, `_barrier_mat("grate")` |
| 4 | Deski i skrzynie: zły dźwięk | Deski i stempel używają `amb_creak` (zapętlone skrzypienie z ambientu) jako dźwięku ciosu **i** rozbicia; skrzynia — `door` + `amb_creak`. To tymczasowe próbki z D1, nigdy nie przeszły odsłuchu A/B | `MATERIALS.planks.hit_snd/break_snd`, `prop.gd _shatter_fx` |
| 5 | Mur z cegieł bez narzędzi nie do przejścia | Na 1.1 **nie ma** muru `q` — to gruz zawału (`^`, kol. 296): o 472 s granat rzucony na wroga złamał stempel obok (`support` by `blast`), strefa się zawaliła. Gruz ma 200 HP i tylko `pick` / `blast` / `charge`, a w 3D składa się z brył pre-fraktury **cegły** — wygląda jak mur. Gracz nie chciał zawału, nie wiedział, że go wywołał, i został z przeszkodą nie do ruszenia | `level.cave_in`, `MATERIALS.rubble`, `view3d._rubble_heap` |
| 6 | Przegrody bez sensu | Za kratką 1.1: bateria i amunicja; za deskami: przedmiot i Skoczek; otwór `:` — zabijanie deskami bez powodu, bo 1.1 nie ma celu „przetrzymaj”. Nagroda za hałas i czas jest drobna, a w dzienniku jedyne użycie barykady to cztery próby „przybij → przetnij” przy Planks1 (wytrzymały 1,8–6,9 s), czyli zabawa mechaniką, nie taktyka | mapy 1.1 (`z1_m1.gd`), `DESTRUCTION_PLAN.md` D2/D2b |

## Zasady (nowe, obowiązują wszystkie przegrody)

1. **Klucz w zasięgu.** Każda przegroda da się otworzyć tym, co gracz **na pewno ma**, albo tym, co leży **w zasięgu wzroku od niej**.
   Szybsze, głośniejsze narzędzie to przywilej, nie warunek (Zelda: bomby rosną przy pękniętych ścianach; Metroid: zamek pokazuje,
   jakiego klucza chce).
2. **Przegroda mówi, czego chce.** Wygląd zdradza materiał (rdza i śruby, deski na gwoździach, gruz z belką), a pierwsza próba złym
   narzędziem daje krótki komunikat nad przegrodą: „Kratka — podważ łomem [E] albo wysadź”. Raz na przegrodę, potem tylko dźwięk.
3. **Za przegrodą jest powód.** Albo skrót, który realnie skraca trasę (ewakuacja, ucieczka przed Stalkerem), albo skrytka-cel poboczny
   z nagrodą większą niż koszt hałasu, albo kryjówka przed falą. Drobnica (1 bateria) nie usprawiedliwia przegrody.
4. **Zawał nie zaskakuje gracza.** Zawał zamyka drogę wrogom, nie graczowi bez szans. Stempel ostrzega (trzask, sypiący się pył),
   zanim strop spadnie, a gruz da się przejść / odkopać bez specjalnego narzędzia — wolno i głośno.
5. **Brzmi i wygląda jak materiał** — warstwy dźwięku z biblioteki Sonniss po odsłuchu A/B (jak w `AUDIO_PLAN.md`), stany uszkodzeń
   widoczne w modelu.

## Etapy

### B0 — szybkie poprawki bez zmiany projektu (1 PR)

- **Przegrody bez celu zdjęte z map** (decyzja 3): otwór `:` na 1.1 (kol. 270) i kratka 1.1 (kol. 247, kanał z baterią i amunicją —
  rzeczy zostają, kanał otwarty albo zamurowany). Z 1.2 i 1.3 w B0 zeszły tylko strefy zawału (decyzja 5); przegląd pozostałych
  przegród 1.2 i 1.3 (`q`, `%`, `+`, `:`) tą samą miarą przechodzi do B4.
  `--maptest` i `--destructiontest` (sekcje 11–13 używają przegród z 1.2 i próbnych w tunelu — sprawdzić, czy nie zależą od 1.1).
- **Komunikat przy złym narzędziu** (zasada 2): pierwszy cios, który się odbił, pokazuje nad przegrodą nazwę materiału i czym ją
  ruszyć (arbiter komunikatów, `Actions.fmt`, tłumaczenia w `ui.csv`).
- **Granat a kratka:** jeden granat w promieniu rozbija kratkę (mnożnik `blast` w materiale albo HP kratki ≤ 45); gruz pada od dwóch.
- **Stempel nie od przypadkowego wybuchu:** odłamki granatu rzuconego na wroga nie łamią stempla, chyba że wybuch jest bliżej niż
  ok. 1 m od belki (dziś wystarcza cały promień 4 m).
- **Gruz nie wygląda jak cegła:** bryły pre-fraktury skały (nowy zestaw w `tools/fracture_gen.py`), ziemia, złamana belka w kupie.
  *Wykonanie w #597:* zarwany fragment stropu z symulacji brył sztywnych (`tools/rubble_pile_gen.py`, zestaw „beton” albo „kopalnia”
  wg stropu nad strefą), rysy na ścianie, podciąg stempla nad strefą spada z płytą; po odkopaniu płyta leży na płasko.
- **Zawał zdjęty z 1.1–1.3** (decyzja 5): plansze „przed → zawał → odkopanie” pokazały, że w halach 4–5 rzędów i pod lekkim dachem
  zawał się nie broni (płyta ~6,8 m przy ~3,5 m głębokości tunelu, strefa na 1.2 przed ślepym zaułkiem). Mapa testowa `t_mine`
  (poza kampanią) trzyma testy: `--destructiontest` sekcja 14, `--maptest`, `test_net_session.sh` (`--cavenet`).

### B1 — zasada klucza: kilof w osobnym slocie (decyzja 1, 1–2 PR)

*Wykonanie (1.7.495):* `Slot.TOOL` i `Weapons.TOOL`; cios (V / PPM / pad X) sam bierze kilof przy murze, kratce, gruzie i stemplu,
jeśli w zasięgu nie ma wroga (`melee_for_target`), klawisz C (układ „nowoczesny” 4) — kilof zawsze; bez osobnego wyciągania i powrotu
— cios kilofem jest szybką akcją jak cios maczetą. Kilof zostaje w liście warsztatu (części i ostrzenie), ale nie jest wyborem broni białej.
Kilof na plecach: przypięty na zewnątrz plecaka (pod plecakiem znikał). Bot, HUD, podpowiedź, kodeks i migracja zapisu jak niżej.


**Decyzja 2026-11-04: kilof w osobnym slocie narzędzia** obok broni białej — każdy gracz (i bot) ma go zawsze, więc kratka, mur `q`
i deski mają klucz u każdego. Wybór maczeta / kilof w warsztacie znika; slot broni białej to maczeta (i przyszłe bronie białe).

- `weapons.gd`: nowy `Slot.TOOL` (albo pole `tool_id` w `weapon_controller.gd` obok `melee_id`), kilof poza `Slot.MELEE`; masa kilofa
  w zestawie (dziś 2,6 kg) — sprawdzić wpływ na limit masy i szybkość (`fits`, `mass` w `mission_start.equipment`).
- Wyciąganie: osobna akcja w rejestrze `actions.gd` (klawisz i przycisk pada do ustalenia; teksty przez `Actions.key`), czas wyciągnięcia
  jak dziś (`draw_time` 0,3 s), po ciosie powrót do poprzedniej broni po chwili bezczynności. Kilof nadal walczy (55 obrażeń, ogłuszenie),
  ale wolniej niż maczeta.
- Kontekst: przy przegrodzie, której nie bierze broń w ręku, cios broni białej automatycznie używa kilofa (opcjonalnie — do sprawdzenia
  w playteście, czy to nie myli).
- Warsztat (`workshop_ui.gd` `LIST`): kilof znika z listy broni białej (albo zostaje jako pozycja „narzędzie” bez wyboru); migracja zapisów
  z kilofem w slocie broni białej → maczeta + kilof w slocie narzędzia.
- Bot (`player.gd _bot_chop_wall`): rąbie kilofem zawsze, nie tylko gdy ma go w ręku. Wrogowie bez zmian.
- Widok 3D (`char3d.gd`): kilof na plecach / przy pasie, gdy nie w ręku; chwyt i zamach jak dziś (`chop`).
- HUD: ikona narzędzia w pasku broni; podpowiedź „pickaxe” dla każdego przy pierwszej przegrodzie (zastępuje podpowiedź z B0).
- Sieć: `melee_id` i nowy slot replikowane jak dziś; walidacja serwera ciosu kilofem bez zmian (`breaks_walls`).
- Testy: `--destructiontest` (bot i gracz z maczetą otwierają kratkę), `test_weapons.sh`, `--workshoptest` (lista i migracja), `--bottest`.

Odrzucone na rzecz D: wspólna akcja [E] na każdą przegrodę (A), łom w zestawie (B), klucz leżący przy przegrodzie (C — może wrócić
dla ładunków burzących, gdy mapa ma mur, którego kilof nie bierze).

**Gruz po zawale (decyzja 2): rozgarnianie [E]** — wyjątek od D, bo zawał ma zatrzymać wrogów, a nie zamknąć drogę drużynie.
*Odłożone (decyzja 5):* mapy kampanii nie mają dziś stref zawału — rozgarnianie wchodzi razem z pierwszą mapą z niskim przejściem.
Miejsce przy strefie `^` jak `barricade_spot.gd`: trzymanie [E] 10–12 s (kilofem 3–4 ciosy dalej szybciej), hałas porcjami, przerwane
przez puszczenie; wrogowie przez gruz nie przechodzą (Stalker — jak przy barykadzie, rozbija powoli). Serwer rozstrzyga, postęp
w stanie zniszczeń (wipe, punkt kontrolny, dołączający).

### B2 — wygląd kratki i stanów (1 PR)

- Kratka wentylacji w **otworze kanału** (niski otwór 1–2 kafle przy podłodze albo w ścianie szybu, nie cała wysokość korytarza):
  stalowa rama na śrubach, płaskownik w kratkę albo żaluzja, rdza i zacieki (ambientCG Rust / Metal, CC0), ciemny kanał za nią.
- Stany z maski i HP: cała → wgięta (pręty wygięte w stronę ciosu) → jedna strona wyrwana, wisi na zawiasie → leży na podłodze.
  Przy kolejnych ciosach kilofa śruby wypadają po kolei (widać postęp bez paska).
- Deski: gwoździe i poprzeczka widoczne, odrywana deska odchodzi od jednej strony (nie znika).
- Gruz: zasada 4 — skała, ziemia i złamana belka, szczelina u góry kupy; przy rozgarnianiu [E] kupa maleje etapami (razem z rozgarnianiem,
  po decyzji 5). Modele `rubble_pile_*` są dziś dla stref 4 i 5 rzędów — dla niskich przejść wygenerować 2–3 rzędy.
- Zrzuty przed / po (`--shotwall=Grate1 --view3dlit`) w `C:\deadair87\shots_barrier_v2`.

*Wykonanie (1.7.496):* po pierwszej wersji (deski i krata na przednim licu bryły) autor zwrócił uwagę, że przegroda narysowana na przekroju
jest ścianą wzdłuż drogi i niczego nie zamyka, a bryła nie sięga do przodu sąsiednich kafli. Zaakceptowana wersja v3: deski i kratka w poprzek
korytarza, od ściany tła (−2,4 m) do przodu brył (+1,1 m) i od podłogi do stropu, mur `q` do przodu brył. Niski otwór na 1.2 i 1.3 — nadproże `C`
nad kratką. Kratka: rama, skrzydło na zawiasach przy ścianie tła, rygle z przodu; stany z HP — cała → wgięta (> 55%) → skrzydło odgięte ku stronie
ciosów → rama zostaje, skrzydło na podłodze; śruby wypadają po kolei. Deski: trzy słupki, gwoździe, zastrzały w `%`, lico od strony gracza w `:`;
połowa odłupanych desek wisi na przednim słupku, po rozbiciu zostają słupki i wiszące deski; dziury z D2 na licach desek. Rdza z materiału `metal`
z brudem `rust` (bez nowych tekstur ambientCG). Gruz bez zmian (decyzja 5). Dev: `--shotpick=N`, `--shotorbit=YAW,PITCH`. Kolizja bez zmian
(cały kafel), więc gracz staje ok. 0,6 m przed deskami.

### B3 — dźwięk (1 PR, odsłuch A/B przed podmianą)

Warstwy na materiał (uderzenie, pęknięcie przy zmianie stopnia, rozpad, ogon gruzu), losowe warianty i wysokość. Kandydaci z
`C:\deadair87\audio_lib` (Sonniss GDC; nagrania tylko lokalnie w `audio_licensed/`):

| Materiał | Dziś | Kandydaci |
|---|---|---|
| Deski, skrzynia | `amb_creak`, `door` | Double Trouble Audio — „Wood Impacts and Debris” (ciosy, pękanie), „Tools and Wood” (Small Wood Pile, Smash), BROKEN — WOOD Break Small |
| Kratka | `impact_hard` | Metal_Jolt_Rattle_Scrape, LOCK_Metal_shake_rattle (podważanie), metalowe uderzenia z rdzą (Kopeikin „dry hard metal impact with rust debris”) |
| Gruz | `amb_thud` | Kopeikin Rocks — rock impact medium, rock tumble down debris, soil and dirt debris heavy |
| Stempel | `amb_creak` | pękające drewno (Double Trouble), trzask + sypiący się pył z gruzu |
| Młotek (D2b) | `amb_thud` | wbijanie gwoździ (do znalezienia w indeksie; „nails_on_*” to paznokcie, nie gwoździe) |

Odsłuch: 3–4 kandydatów na rodzinę w katalogu `C:\deadair87\odsluch\barriers`, wybór autora, potem podmiana w `audio_manifest.gd`.

**Zrobione w 1.7.499 (drewno, młotek; odsłuch 2026-11-05):** strona `odsluch\barriers\index.html` (`render.py`: wersja z gry —
te same pliki, wysokość i dB z wywołań — obok kandydatów wyrównanych do jej głośności chwilowej, okno 400 ms). Wybór autora:
trafienie w drewno — David Dumais „Impact Wood 23”, rozbicie — „Designed Wood Crash And Debris 13”, młotek — The Sound Pack Tree
„Nail Hammering 03”; zawał i trzeszczenie stropu przed nim — **obecne** (bez zmian). Nowe klucze `wood_hit`, `wood_break`,
`hammer_nail` (po 3 warianty; synteza w `bake_sfx.build_world`, nagrania w `bake_hybrid.world`, głośność chwilowa obu wersji równa):
deski `%` (trafienie −8 dB, rozbicie −2 dB), kula w deskę (`Vfx.impact`, −11 dB, ×1,1), skrzynia — rozbicie (−2 dB) i upadek
(`wood_hit` ×0,8), stukanie przy barykadowaniu (0 dB co 0,4 s) i dobita deska (+3 dB, ×0,92). Skrzynia i deski grały wcześniej
**metal**: `door` to nagranie metalowych drzwi, `amb_creak` skrzypienie metalu. Napisy: „[Wood splinters]”, „[Hammering]”.
Zostają: kratka (`impact_hard`), gruz (`amb_thud`) i stempel (`amb_creak`) — nie było ich w tym odsłuchu.

### B4 — sens przegród na mapach (1–2 PR, decyzja 3)

- Przegląd każdej przegrody na 1.1, 1.2, 1.3: co daje, ile kosztuje (hałas, czas), czy klucz jest w zasięgu. Przegrody bez powodu
  usunąć albo zamienić na zwykłą ścianę.
- Nagrody: skrytka za kratką jako cel poboczny (licznik „skrytki 2/2” już jest w misjach) z częścią broni albo 2–3 bateriami; skrót
  przez deski na trasie ewakuacji 1.1 (dziennik: faza ewakuacji od 204 s, a gracz od 265 s do wyjścia z gry kręcił się przy Planks1
  i zawale — przegrody były celem samym w sobie, nie częścią drogi).
- Otwór `:` (D2b) tylko tam, gdzie zabicie go ma cel: zatrzymanie Stalkera na trasie ucieczki albo misja „przetrzymaj”; na 1.1 bez
  takiego celu — rozważyć usunięcie.
- Zawał (decyzja 5): nie na 1.1–1.3. Na nowej mapie w podziemiach — strefa w niskim przejściu (2–3 rzędy) pod skałą lub betonem, stempel
  z podciągiem tuż przed nią, w miejscu, gdzie zawalenie za sobą ratuje przed pościgiem (Stalker, fala z dyrektora), z drugą drogą dla drużyny.

### B5 — playtest i pomiar

- Ten sam przebieg 1.1 po B0–B4, dziennik `session_progress.py` (sekcja „Niszczenie” z #595): czy kratka i gruz zostają otwarte,
  ile trwało, czym, czy ktoś utknął (czas przy przegrodzie bez przejścia — nowa miara, do dopisania).
- Pytania z `CZYTAJ.txt` (7–8).

## Kolejność i rozmiar

| Etap | PR | Ryzyko | Zależy od |
|---|---|---|---|
| B0 | 1 | niskie | — |
| B1 | 1–2 | średnie (bot, sieć, czas akcji) | decyzja 1 |
| B2 | 1 | średnie (model, czytelność w ciemności) | B1 (kilof u każdego, rozgarnianie gruzu) |
| B3 | 1 | niskie | odsłuch autora |
| B4 | 1–2 | średnie (projekt map, `--maptest`) | B1, decyzja 3 |
| B5 | 0 | — | B0–B4 |

Decyzje podjęte — B0 gotowe (#597), B1 i B3 można zaczynać od razu (B3 równolegle, czeka tylko na odsłuch). B2 po B1, B4 po B1 i B2.
Rozgarnianie gruzu (B1) i wygląd gruzu (B2) czekają na pierwszą mapę ze strefą zawału (decyzja 5).

## Decyzje (2026-11-04)

1. **Klucz dla gracza bez kilofa:** kilof w osobnym slocie narzędzia (B1) — każdy ma go zawsze.
2. **Gruz po zawale:** rozgarnianie [E] przez każdego gracza (B1); bryły skały zamiast cegły (B0).
3. **Przegrody bez celu** (otwór `:` na 1.1, kratka z samą drobnicą): **usunąć na razie** — w B0 zdjęte z map, wracają w B4 z nagrodą
   albo skrótem. Przegląd 1.2 i 1.3 tą samą miarą w B0.
4. **Stempel od granatu:** tylko bliski wybuch (ok. 1 m od belki); kula, śrut, kilof i ładunek jak dziś; trzask i pył jako ostrzeżenie (B0).
5. **Zawał na mapach kampanii:** zdjęty z 1.1, 1.2 i 1.3 („nie ma najmniejszego sensu”) — mechanika zostaje na mapy w podziemiach
   z niskimi przejściami; testy na mapie testowej `t_mine` (B0, #597).
