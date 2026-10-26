# Progresja gracza — analiza i plan ulepszenia

**Stan:** analiza na `main` 7f7ad66 (1.7.390), 2026-10-26. Wdrożenie: **P0 → 1.7.391** (gałąź `feat/progression-measure`),
**P1 → 1.7.392** (gałąź `feat/campaign-continue`) — patrz §7. P2 i P3 czekają na warunki z §5. Kontynuacja `GUNSMITH_PLAN.md`
i `WORKSHOP_PLAN.md`; zasady zakresu z `GDD.md` §16.0a obowiązują w całości (patrz §5).

Źródła: `profile.gd`, `perks.gd`, `look.gd`, `scrap.gd`, `parts.gd`, `throwables.gd`, `arsenal.gd`, `mission.gd`, `night_shift.gd`,
`enemy_defs.gd`, `main.gd`, `run_log.gd`, `session_log.gd`; dzienniki `user://sessions/*.jsonl` (bez `_perf_test`), bieżące
`profile.cfg` i `progress.cfg` hosta (tylko odczyt).

## 1. Mapa systemów progresji

### 1.1 Co jest czyje

| System | Gdzie żyje | Właściciel | Zapis |
|---|---|---|---|
| XP, poziom, perki, wygląd | `Profile` | każdy gracz osobno | `user://profile.cfg` |
| Ukończone misje (`completed`) | `Profile` | gracz | profil — **używane tylko do bonusu „First clear”** |
| Wprawa (`mastery`), historia broni, rekordy strzelnicy | `Profile` | gracz | profil |
| Montaż części, zestawy, stan / zużycie / ostrze | `Profile` | gracz | profil |
| Złom (bank), kupione bronie, odblokowane części, trofea | `Scrap` | drużyna = **host** | `user://progress.cfg` hosta |
| Próbki, badania, schematy, tokarka, prasa, zapalniki | `Scrap` | host | `progress.cfg` |
| Zapas zaopatrzenia (granaty, apteczki, amunicja specjalna) | `Arsenal.stock` | host | `progress.cfg` |
| Ściana wyników (`RunLog`) | statyczny stan | każdy peer | **brak — znika z końcem sesji** |
| Rekord Nocnego Dyżuru | `Settings` | lokalnie | `settings.cfg` |

### 1.2 Trzy pętle

**Krótka (w misji, sekundy–minuty)** — toasty XP za zabójstwo (2–40 XP wg rodzaju), złom z trupów (35 % szansy, 2–25) i skrytek (6 / 20),
znalezione części (skrytka misji, 30 % z elity) i próbki (elita 1, boss 2) czekające do ekstrakcji, awanse wprawy broni (−2 % przeładowania,
dobycia i podrzutu na stopień). Wipe zabiera łup, części i próbki z tej próby.

**Średnia (kryjówka między misjami, 1–2 misje)** — premia za misję (złom 30 + 15 cel poboczny + 10 bez upadków; XP 100 + 50 + 25, boss +300,
pierwsze ukończenie +100), zakup części na ławie, zaopatrzenie, zlecenia gotowe „po następnej misji” (prasa, pracownia, tokarka), wymiana
lufy / sprężyn, nowy perk lub strój po awansie.

**Długa (wiele sesji)** — poziom profilu do L6, katalog broni i części drużyny, trofeum za bossa (SPECTER-1), wprawa 5 we wszystkich broniach,
nacięcia na kolbie, rekordy strzelnicy, rekord Nocnego Dyżuru. **Kampania nie ma stanu „gdzie jesteśmy”** (§2.1).

```
misja ──► XP (profil gracza) ──► poziom ──► perki L2/L4/L6, stroje L3/L5, palety L2–L5   [koniec na L6]
  │
  ├─► złom (bank hosta) ──► bronie 150–300 ──► części 50–375 ──► zaopatrzenie / prasa / serwis (ujście ciągłe)
  │                                    └─► broń specjalna ──► próbki + ½ ceny (pracownia) ──► ¼ ceny (tokarka)
  ├─► części-znaleziska, próbki (do banku po ekstrakcji)
  ├─► wprawa i historia broni (profil) ──► −10 % obsługi na stopniu 5
  └─► completed / trofeum ──► bonus First clear, SPECTER-1 w warsztacie
```

### 1.3 Krzywa XP (`Profile.xp_for_level`: krok do L(n+1) = 50 + 100·n)

| Poziom | Łącznie XP | Krok | Co odblokowuje | Udanych misji do poziomu (szac.) |
|---|---|---|---|---|
| L2 | 150 | 150 | 1. slot perka; Ciche kroki, Krwioobieg, Szerokie ramię, Kowal; paleta DUST | 1 (w trakcie pierwszej misji) |
| L3 | 400 | 250 | strój Hazmat, paleta RUST | 1–2 |
| L4 | 750 | 350 | 2. slot; Zimna krew, Zwiadowca, Druga szansa; FROST | 2–3 |
| L5 | 1200 | 450 | strój Medic, paleta EMBER | ≈ 4 (pełna Strefa I za pierwszym razem) |
| L6 | 1750 | 550 | Weteran (+1 serce) — **ostatnie odblokowanie** | 5–7 |
| L7–L10 | 2400 / 3150 / 4000 / 4950 | 650–950 | **nic** | — |

XP na udaną misję (szacunek z reguł i dzienników; **dziennik nie zapisuje XP** — §2.6):

| Misja | Za wynik (powtórka) | Zabójstwa (mediana) → XP | Razem powtórka | Pierwsze ukończenie | Mediana czasu sukcesu | XP / min |
|---|---|---|---|---|---|---|
| 1.1 | 100 + 50 (cel pob. 77 %) + 25 (bez upadków 75 %) ≈ 157 | 20 → ~60–90 | **~230** | +100 | 4,0 min | **~57** |
| 1.2 | 100 + 50 (14 %) + 25 (36 %) ≈ 116 | 35 → ~100–140 | ~240 | +100 | 8,4 min | ~29 |
| 1.3 | 100 + 0 (0 %) + 25 (14 %) ≈ 104 | 16 → ~50–80 | ~170 | +100 | 6,4 min | ~27 |
| B1 | 100 + 300 (+25) | boss | ~400–425 | +100 | — (0 zwycięstw w dziennikach) | — |

Pierwsze przejście Strefy I (4 × First clear) daje ok. 1300–1500 XP → **L5**; L6 przychodzi 1–2 misje później. Dalej XP nie kupuje niczego.
Bieżący profil autora: 1734 XP (L5, 16 XP do L6), `equipped = ["", ""]` — **żaden perk założony mimo dwóch slotów**.

### 1.4 Ekonomia złomu

**Dochód** — dzienniki z polem `scrap` (od 1.7.347; 14 sukcesów 1.1, 2 sukcesy 1.2, NORMAL, 1 człowiek + bot):

| Misja | Łup zebrany | Premia | Do banku | Na minutę misji |
|---|---|---|---|---|
| 1.1 | 110–142 (med. 125) | 40–55 | **~165–195** | ~40 |
| 1.2 | 95–120 | 40 | ~135–160 | ~17 |
| 1.3, B1 | brak danych z pomiarem złomu | | szac. 130–155 / 80–100 (WORKSHOP_PLAN §1.1) | |

Z łupu ok. 40 % to złom z trupów (`dropped` 28–74 na próbę), reszta skrytki i znaleziska. Wipe: łup przepada (28 % czasu misji w dziennikach
to próby zakończone wipe'em).

**Koszty** — czego da się w EA (Strefa I) używać:

| Wydatek | Suma | Uwagi |
|---|---|---|
| Bronie z warsztatu | 900 (LR-7 150, HKM-9 200, PELLET-8 250, WRATH-4 300) + SPECTER-1 400 po bossie | FALCON-6, SINEW-6 — `LATER`, niedostępne |
| Części broni podstawowych | 3235 (M-83 780, P-83 515, SPREAD-12 520, PELLET-8 720, maczeta 380, kilof 320) | zakup od ręki; Kowal −20 % |
| Części broni specjalnych | 2870 ceny katalogowej → ~2150 złomu (½ badanie + ¼ tokarka) + **27 próbek** | jedno badanie i jedno zlecenie na misję |
| Części FALCON-6 / SINEW-6 | 1120 + 6 części | **nieosiągalne w EA** (broń `LATER`) |
| Ciągłe ujście | granat 100, apteczka 70, zestaw czyszczący 50, Sowa 120, prasa 30–90 / partia, lufa 40, sprężyny 20 | po wypełnieniu katalogu |

Katalog osiągalny w EA ≈ **6700 złomu ≈ 37–42 udane misje** (przy ~160–180 na misję). Średnia część (142) ≈ 1 udana misja — cel WORKSHOP_PLAN
„część co 1–2 misje” jest spełniony. Próbki są wąskim gardłem: ~1 na udaną 1.1 (cel poboczny), 0 na 1.3 → 27 próbek ≈ 25+ misji.

Stan hosta autora: bank 507 (230 z testów 26.10), **0 kupionych broni** (`unlocked=[]`), 12 części (1165 złomu: M-83, SPREAD-12, maczeta,
kilof), 5 próbek bez zastosowania.

### 1.5 Kampania i tryby

- `level.CAMPAIGN = [z1_m1, z1_m2, z1_m3, z1_b1]`, sukces → kryjówka → następna misja (`main._next_campaign_map`). **Każda nowa sesja startuje
  od 1.1** (`main.gd`: `level.CAMPAIGN[0]`); `Profile.completed` nie wybiera misji.
- Dzienniki: 63 pliki sesji, mediana **1 misja na sesję**; 52 sesje zaczęły się od 1.1, do 1.2 doszło 16, do bossa 6. Próby: 1.1 69 (56 sukcesów),
  1.2 21 (14), 1.3 26 (7; średnio 3,7 próby na sukces, najgorzej 16), **B1 13 (0)**.
- Nocny Dyżur: połowa XP, **zero złomu, próbek i części**, rekord tylko lokalny; **0 misji w dziennikach**.
- Kryjówka: `hub_seconds` 28–220 s (mediana ~85 s, 10 pomiarów).

## 2. Problemy

### 2.1 Kampania nie pamięta postępu (wysoki)
Sesja zawsze zaczyna od 1.1, a `completed` służy tylko bonusowi. Skutki widać w danych: 56 sukcesów 1.1 wobec 7 sukcesów 1.3 i żadnego bossa.
Tester z zewnątrz, który wraca następnego dnia, gra znowu 1.1 — nuda z powtórki zanieczyści §23.3, a trofeum, B1 i XP za bossa są dla niego
praktycznie niedostępne. GDD §10.3 przewiduje **tablicę misji**, której nie ma.

### 2.2 Nagrody nie rosną z trudnością — opłaca się farmić 1.1 (wysoki)
Premia złomu (30/15/10) i XP za wynik (100/50/25) są stałe dla każdej misji. 1.1 daje ~40 złomu i ~57 XP na minutę, 1.2 i 1.3 mniej niż
połowę, a do tego mają rzadziej zaliczany cel poboczny (14 % i 0 %) i więcej upadków. System nagradza **cofanie się** do najłatwiejszej mapy.

### 2.3 Krzywa XP urywa się na L6 (średni)
Wszystkie odblokowania kończą się po ~5–7 udanych misjach (~1 h gry), a katalog złomu starcza na ~40. Od L6 pasek XP, toasty „Kill +2”,
karta „LEVEL UP” i bonusy XP są **martwą nagrodą**. Pierwsze poziomy są gęste (L2 w pierwszej misji), środek pusty, koniec ucięty.

### 2.4 Martwe lub niedostępne nagrody (średni)
- **Próbki** zbierają się od pierwszej misji (toast „Sample taken”), ale badać można tylko części broni specjalnej, którą drużyna kupiła.
  Bez zakupu LR-7 / HKM-9 / WRATH-4 próbki nic nie dają (host autora: 5 próbek, 0 broni).
- **FALCON-6 i SINEW-6** (`LATER`) — 6 części za 1120 złomu nieosiągalnych w EA.
- **Trofeum SPECTER-1** i XP_BOSS 300 — za bossa, którego w dziennikach nikt nie pokonał (13 prób; strojenie bossa to osobny temat).
- **Nocny Dyżur** — po L6 nie daje nic trwałego poza lokalnym rekordem; w dziennikach nieużywany.
- **Ściana wyników** — `RunLog` jest statyczny, ostatnie 8 wpisów, znika po wyjściu z gry; GDD §10.3 „Ściana pamięci” sugeruje trwałość.
- **Karta wyniku** pokazuje tylko `last_mission_xp` (wynik misji), bez XP za zabójstwa — gracz nie widzi pełnego zarobku misji.

### 2.5 Co-op: postęp warsztatu należy tylko do hosta (średni, projektowy)
Złom, bronie, części, próbki i zapas są w `progress.cfg` hosta. Gracz, który zawsze dołącza, zbiera i wydaje złom kogoś innego i nie zabiera
nic do własnej gry (zostaje mu tylko profil: XP, wprawa, montaż). Część odblokowana tylko u innego hosta nie działa w jego własnej grze
(`Profile.fitted` → element fabryczny, dopóki jego drużyna jej nie odblokuje). To zgodne z GDD (§10.1 „portfel wspólny”), ale w playtestach z rotacją hosta da mylące odczucia.

### 2.6 Brak pomiaru progresji (wysoki — blokuje strojenie)
Dziennik ma złom i stan warsztatu na starcie misji, ale **nie zapisuje**: XP i poziomu graczy, założonych perków i wyglądu, zabójstw wg rodzaju
wroga, zakupów w kryjówce (co, za ile, kto), próbek zdobytych na misji poza `samples`. Wszystkie dzienniki pochodzą z sesji autora (1 człowiek
+ bot; klient nie pisze dziennika, a goście z zewnątrz hostują u siebie) — **żadnych danych z zewnętrznych playtestów** (§23.3 pusta).

### 2.7 Wprawa wzmacnia monokulturę broni (niski, do obserwacji)
Wprawa rośnie z trafień i zabójstw; M-83 autora ma 1747 pkt (stopień 5 od 1500), SPREAD-12 14, maczeta 37. Najlepiej opłaca się zostać przy
broni, która już ma bonus — w tę samą stronę co ustalenie WORKSHOP_PLAN §1 (M-83 = 78 % zabójstw).

### 2.8 Rozjazd z GDD (niski, dokumentacja)
- §16.0a i §16.2 wyłączają „Wrogą wiedzę” z EA, a XP / poziomy / perki / stroje działają od 1.7.73 i opisuje je README.
- §10.1: złom ze „sprzedaży próbek” i wydatek „perki” — nie istnieją (perki z poziomu); próbki na „odblokowanie stref” — nie istnieją.
- §9 „Nagroda strefy: sklep broni (SPREAD-12, PELLET-8), postać Igła” — SPREAD-12 jest od startu, PELLET-8 za złom, postaci brak.
- §4 „Pętla meta → trudniejsze misje” — trudność nie zależy od postępu (tylko Nocny Dyżur +12 % HP na misję).

### 2.9 ~~Ryzyko dla prawdziwego profilu~~ — wycofane
Pierwsza wersja planu twierdziła, że `--shotperks`, `--shotperkcard` i `--shotlook` nadpisują prawdziwy `profile.cfg`. To nieprawda: wszystkie
trzy działają wewnątrz `main._take_shot`, który na początku ustawia `Profile.persist = false`. Punkt P0.6 odpadł.

### 2.10 Klient nie znał następnej misji (znalezione przy wdrożeniu P1)
`main.after_hub` ustawiał tylko serwer i nigdzie go nie rozsyłał — u klienta odprawa na tablicy, tytuł „Next: …” i radiostacja pokazywały
„the next mission”. Naprawione w P1.1 (cel wyjścia w `mission._sync`).

## 3. Plan

Kolejność wynika z §16.0a: najpierw pomiar i naprawy bez nowych systemów, strojenie dopiero na danych z ≥ 3 zewnętrznych sesji, nowe cele
średnioterminowe po Gate 0 albo gdy §23.3 wskaże nudę z powtórek.

### P0 — Pomiar (teraz, bez zmian rozgrywki) — priorytet 1

| # | Zmiana | Pliki | Po co |
|---|---|---|---|
| P0.1 | `mission_end.players[id]`: `xp` (zarobek w misji: wynik + zabójstwa + podniesienia), `level` przed i po | `mission.gd`, `profile.gd`, `session_log.gd` | XP na misję i czas do poziomu z danych, nie z reguł |
| P0.2 | `mission_start.equipment[]`: `level`, `perks`, `look` | `mission.gd` | czy gracze zakładają perki (§2.4, profil autora: 0) |
| P0.3 | `mission_end.kills_by_kind` (rodzaj → liczba) | `session_log.gd`, `profile.gd` | XP i złom z zabójstw wg mapy |
| P0.4 | zdarzenie `hub_buy` przy każdym rozstrzygniętym zakupie (`kind`: weapon / part / supply / order / research / machining / service, `id`, `cost`, `ok`, `reason`, `who`) | `scrap.gd`, `session_log.gd` | struktura wydatków, odmowy „poor” = frustracja |
| P0.5 | `tools/session_progress.py`: raport z dzienników — złom i XP na sukces wg mapy, saldo banku w czasie, wydatki wg kategorii, odsetek wizyt w kryjówce z zakupem, wipe'y na sukces, mapy na sesję | `prototype/tools/` | jedno polecenie po każdym playteście |
| ~~P0.6~~ | wycofane — flagi zrzutów już nie zapisują profilu (§2.9) | — | — |
| P0.7 | Pytania do §23.3 (ankieta po sesji): „Na co wydałeś złom? Czy wiedziałeś, na co zbierasz? Czy zauważyłeś perki / próbki? Czy chciałeś zacząć od innej misji?” | `GDD.md` §23.3, `tools/testers_readme.txt` | odczucia, których dziennik nie złapie |

Gotowe, gdy: raport P0.5 działa na dziennikach autora i jednej testowej sesji co-op. Jeden PR (pomiar + narzędzie).

### P1 — Naprawy martwych nagród i zgodności (przed / w trakcie playtestów, bez nowych stanowisk i walut) — priorytet 2

| # | Zmiana | Uzasadnienie | Ryzyko |
|---|---|---|---|
| P1.1 | **Kontynuacja kampanii:** host zapisuje w `progress.cfg` najdalszą odblokowaną misję; start kampanii i „Depart” idą do pierwszej nieukończonej; tablica odpraw w kryjówce pozwala wybrać dowolną odblokowaną misję (GDD §10.3 „Tablica misji”) | §2.1 — inaczej każdy playtest powtarza 1.1 | testy kampanii w `main.gd` (kolejność 1.1 → hub → 1.2) trzeba rozszerzyć; zapis u hosta jak trofea, nie nowa waluta |
| P1.2 | Karta wyniku: wiersz „Kills” (suma XP z zabójstw w misji), razem z wynikiem | §2.4 | mała; `last_mission_rows` już istnieje |
| P1.3 | Próbki bez broni specjalnej: pracownia i toast mówią wprost „Próbki bada się dla LR-7 / HKM-9 / WRATH-4 — kup broń w warsztacie”; części broni `LATER` ukryte w pracowni i kodeksie EA | §2.4 — bez zmiany reguł, tylko czytelność | żadne dla balansu |
| P1.4 | GDD: §16.0a / §16.2 — poziom profilu (XP → perki, stroje) jest w EA, „Wroga wiedza” jako waluta fabularna zostaje na 1.0; §10.1, §9 (nagroda strefy), §4 zgodnie ze stanem | §2.8 | brak (dokumentacja) |

Gotowe, gdy: druga sesja testera zaczyna od pierwszej nieukończonej misji, wybór misji działa w co-op (serwer rozstrzyga), testy kampanii PASS.

### P2 — Strojenie na danych (po ≥ 3 zewnętrznych sesjach w §23.3) — priorytet 3

Tylko zmiany stałych w istniejących systemach, każda za liczbą z raportu P0.5.

| # | Zmiana (kierunek) | Warunek z danych |
|---|---|---|
| P2.1 | Premia za misję zależna od mapy: `BONUS_CLEAR` i `XP_MISSION` w danych mapy (np. 1.1 30 / 100, 1.2 45 / 150, 1.3 55 / 175, B1 60 / 200), tak by złom i XP **na minutę** nie spadały z kolejną misją | §2.2 potwierdzone u testerów (powtarzanie 1.1 albo wyraźnie niższy dochód / min na 1.2–1.3) |
| P2.2 | Krzywa XP: rozłożyć istniejące odblokowania do ~L8–L9 (np. Weteran L8, palety co poziom), żeby ostatnie przyszło po ~10–12 misjach zamiast 5–7; bez nowych perków | testerzy dochodzą do L6 w playteście, a potem XP przestaje ich obchodzić (P0.1, ankieta) |
| P2.3 | Ekonomia: ceny części ±, `DROP_CHANCE`, kara wipe'u (np. część łupu zostaje) — cel „część co 1–2 misje” z WORKSHOP_PLAN §5 | saldo banku rośnie bez zakupów (brak celu) albo częste „poor” (za drogo) |
| P2.4 | Nocny Dyżur: część złomu (np. 50 %) albo premia za całą serię | tryb grany, a gracze mówią, że „nic nie daje”; jeśli nie grany — zostawić |
| P2.5 | Próbki: niższe koszty badań (27 próbek na cały katalog to ~25 misji) albo pewniejsze źródło na 1.2 / 1.3, gdzie cel poboczny prawie nie wychodzi (14 % / 0 %) | gracze kupują broń specjalną, ale stoją na próbkach |

Każda zmiana: osobny PR, wpis w CHANGELOG, aktualizacja tabel w tym dokumencie i w GDD §10.

### P3 — Cele średnioterminowe (po Gate 0 albo gdy §23.3 wskaże nudę z powtórek) — priorytet 4, decyzja użytkownika

- **Trwała ściana wyników:** najlepszy czas, najmniej upadków i cel poboczny per misja w zapisie hosta (jak `range_best` w profilu).
  Uwaga: osiągnięcia na ścianie pamięci są w §16.0a poza EA — rekordy tak, odznaki nie.
- **„Następny cel” w kryjówce:** jedna linia na tablicy odpraw / ławie: najtańsza nieodblokowana część posiadanej broni i brakujący złom,
  następny poziom i co da. Bez nowego systemu — tylko podpowiedź z istniejących danych.
- **Wprawa a różnorodność broni:** jeśli P0 pokaże > 70 % zabójstw z jednej broni u testerów — rozważyć szybszy pierwszy stopień (60 → 30 pkt),
  żeby próba nowej broni szybciej się opłacała.
- **Postęp gościa w co-op (§2.5):** decyzja projektowa — zostaje „portfel hosta” (GDD) czy gość dostaje np. część złomu do własnego zapisu.
  Dotyka zasad waluty, więc tylko po danych i decyzji użytkownika.

### Poza EA (1.0, GDD §16.2)
Wroga wiedza jako waluta fabularna, Taśmy, Szpital, osiągnięcia, wyzwania tygodniowe, Koszmar Tygodnia (złom ×3), strefy II–VI.

## 4. Co mierzyć — wskaźniki i progi

| Wskaźnik | Źródło | Sygnał problemu |
|---|---|---|
| Złom do banku na sukces i na minutę, wg mapy | `mission_end.scrap`, `time` | późniejsza mapa < 70 % dochodu / min 1.1 (§2.2) |
| XP na sukces, minuty gry do L2 / L4 / L6 | P0.1 | L6 przed 60 min gry albo L2 dopiero po 2 misjach |
| Odsetek wizyt w kryjówce z zakupem; czas w kryjówce | P0.4, `hub_seconds` | < 50 % wizyt z zakupem przy banku > 150 albo `hub_seconds` > 180 s (gubią się) |
| Saldo banku w czasie | `mission_start.workshop.bank` | rośnie przez 3+ wizyty bez wydatków (brak celu) |
| Odmowy „poor” na zakup | P0.4 | > 30 % prób zakupu |
| Perki założone przy L ≥ 2 | P0.2 | < 60 % graczy z perkiem w misji po awansie |
| Próbki w banku vs badania | `workshop.samples`, `research` | próbki rosną, badań 0 (§2.4) |
| Udział broni w zabójstwach; kupione bronie | `weapons`, P0.4 | > 70 % jednej broni, 0 kupionych broni po 3 misjach |
| Misje na sesję; najdalsza mapa; wipe'y na sukces | `mission_start/end` | sesja kończy się na 1.1 albo > 3 wipe'y na sukces 1.3 |
| Nocny Dyżur: uruchomienia | `mission_start.mode` | 0 w playtestach → P2.4 bez znaczenia |

## 5. Zgodność z GDD §16.0a

| Zasada | Jak plan ją spełnia |
|---|---|
| 1. Systemy warsztatu weryfikuje playtest; nieużywane upraszczamy | P0 mierzy użycie każdego stanowiska (P0.4); P1.3 i P2 tylko upraszczają lub stroją |
| 2. Bez nowych stanowisk, walut i warstw zużycia przed 3 sesjami w §23.3 | P0–P1 nie dodają żadnego; P1.1 to zapis stanu kampanii u hosta (jak trofea), opisany już w GDD §10.3; P2 czeka na 3 sesje; P3 po Gate 0 |
| 3. Czas najpierw w braki §16.1 (AI towarzysz, sesja 4-osobowa, demo) | P0 to ~1–2 dni, P1 ~2–3 dni; P1.1 wspiera playtesty (bez niego dane z kolejnych sesji są skażone powtórką 1.1) |

## 6. Ryzyka

- **Dane autora ≠ dane graczy.** Wszystkie liczby z §1 to sesje dewelopera z botem, na buildach w toku, z ręcznymi resetami profilu i banku
  (bank 1379 → 0 w ciągu dnia, +230 z testów). Nie stroić na nich niczego poza oczywistymi błędami.
- **Mała próba.** 3 sesje zewnętrzne to za mało na ceny; P2 traktować jako kierunek, z małymi krokami i pomiarem po każdym.
- **Profil gracza a zapis hosta.** Zmiany ekonomii dotykają `progress.cfg` hostów z playtestów — migracja zapisu jak `migrate_levels`,
  nigdy kasowanie postępu testera.
- **Wybór misji a kolejność nauki.** 1.1 uczy ciszy, 1.2 Przesterowania; tablica misji musi odblokowywać po kolei (tylko ukończone + następna).
- **Testy w oknie piszą prawdziwe zapisy** (notatka 26.10: +230 złomu): każdy przebieg w oknie przy tej pracy — `override.cfg` z `custom_user_dir`.
- **Rozjazd dokumentów.** Każdy etap aktualizuje ten plik, GDD §10 / §16.0a i README „Profil, XP i perki”.

## 7. Stan wdrożenia

| Etap | Wersja / gałąź | Co weszło | Weryfikacja |
|---|---|---|---|
| P0.1–P0.5, P0.7 | 1.7.391, `feat/progression-measure` | `equipment` z `xp`, `level`, `perks`, `look` (replikowane `player.prof_xp`, tylko przy zmianie); `players[id].kinds` i `xp_kills`; wiersz `xp` po udanej misji (u klienta RPC do hosta); `hub_buy`; `tools/session_progress.py`; pytania w GDD §23.3 i `CZYTAJ.txt` | `--missiontest` i `--workshoptest` z `--sessionlog` (nowe kontrole w CI), test sieciowy broni (XP klienta widoczne na hoście), `test_weapons.sh` 379/379 + 15/15; raport na dziennikach autora zgłasza §2.1, §2.2, §2.4, §2.7 |
| P0.6 | — | wycofane (§2.9) | — |
| P1.1 | 1.7.392, `feat/campaign-continue` | `Scrap.cleared` (`[campaign]` w zapisie hosta, migracja z profilu hosta), start od misji po najdalszej ukończonej, wybór przy tablicy odpraw ([Interakcja], serwer, odnawia odliczanie), `after_hub` u klientów | `--workshoptest` 98/98, `test_cabinets.sh` (ENet: klient zna cel i postęp, wybór klienta rozstrzyga serwer) |
| P1.2 | 1.7.392 | karta wyniku: XP za wynik + zabójstwa i podniesienia od poprzedniego wyniku (`Profile.last_run_xp`) | `--workshoptest` |
| P1.3 | 1.7.392 | toast próbki i podpowiedź przy pracowni bez broni specjalnej; części FALCON-6 / SINEW-6 zostają w pracowni z napisem „Available in a later zone” (już czytelne, nie ukrywamy) | `--workshoptest` |
| P1.4 | 1.7.392 | GDD §4, §9, §10.1, §10.3, §16.0a, §16.2 | — |
| P2, P3 | — | czekają: ≥ 3 sesje zewnętrzne w §23.3 (P2), Gate 0 / decyzja użytkownika (P3) | — |

Nie sprawdzone w prawdziwej grze w oknie ani w co-op przez Steam: wygląd podpowiedzi „Change mission”, odczucie odnowionego odliczania.
