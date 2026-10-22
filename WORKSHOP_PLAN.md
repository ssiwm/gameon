# Warsztat Stacji Dead Air — plan rozbudowy

**Stan (2026-10-22):** przegląd broni, ulepszeń i warsztatu na main 1.7.345 (raport: artefakt „Warsztat Stacji Dead Air”).
Użytkownik przyjął rekomendacje z §6 i kazał zacząć od etapów W0 i W1. Kontynuacja `GUNSMITH_PLAN.md` (etapy 0–5 w main).

## 1. Wnioski z przeglądu

| Ustalenie | Dane |
|---|---|
| Jedna broń wystarcza na wszystko | Dziennik 112 misji (`user://sessions`, głównie sesje deweloperskie): M-83 = 71 % obrażeń i 78 % zabójstw, średnio 364 strzały na misję; HKM-9, FALCON-6, SPECTER-1, SINEW-6 w żadnej misji |
| Wybór części jest pozorny | W 8 z 12 broni każde gniazdo ma jedną część do wyboru (`parts.gd`); prawdziwy wybór tylko M-83, SPREAD-12 (zasilanie), WRATH-4 (głowica), kilof (obuch) |
| Koszty części symboliczne | Np. +2 naboje P-83 za +0,03 s dobycia; każda część liczy koszt w innym polu, nic się nie sumuje |
| Stan techniczny prawie nie występuje | Przed 1.7.347: M-83 −0,014 % na strzał ≈ 5 % na misję, zacięcia od 70 % → pierwsze po ~6 misjach; czyszczenie ≤ 10 złomu |
| Jeden panel na wszystko | Ława: ARMS, SUPPLIES, PERKS, LOOK (`workshop_ui.gd`); górny poziom kryjówki ma tylko radiostację |
| Części nie da się wypróbować | Strzelnica FPP (z szafą od 1.7.346) zna tylko zamontowane, odblokowane części |

### 1.1 Ekonomia — szacunek z map

Złom z trupa wypada z szansą `Scrap.DROP_CHANCE` 0,35 (wartość: pole `scrap` w `enemy_defs.gd`), skrytka „u” 6, skrytka „H” 20, premia za misję
30 + 15 (cel poboczny) + 10 (bez upadków). Wrogowie ze znaczników mapy (bez dyrektora i finałów):

| Misja | Wrogów | Oczekiwany złom z trupów | Złom leżący na mapie | Premia | Razem, wszystko zebrane |
|---|---|---|---|---|---|
| 1.1 | 34 | ~41 | 82 | 30–55 | ~150–180 |
| 1.2 | 57 | ~74 | 48 | 30–55 | ~150–180 |
| 1.3 | 39 | ~53 | 48 | 30–55 | ~130–155 |
| Boss | 0 | 30 (boss) | 18 | 30–55 | ~80–100 |

Katalog: 41 części = 6030 złomu (średnio 147), bronie 1300. Przy realnym zbieraniu (~100 złomu na udaną misję) to **1–1,5 misji na część** —
cel z §6 („jedna część co 1–2 misje”) obecne ceny już spełniają. W W0 ceny zostają; od 1.7.347 dziennik sesji zapisuje złom (`scrap` w
`mission_end`: ile wypadło, ile zebrane, premia) i dopiero pomiar z playtestu zdecyduje o zmianie cen.

## 2. Usprawnienia systemu

- **U1 masa jako wspólny koszt** — masa broni i części: dobycie, obrót celownika, hałas biegu; za przełącznikiem REALISTIC / CLASSIC (W5).
- **U2 alternatywy w gniazdach** zmieniające zachowanie (kabura-kolba P-83, bełt-wabik SINEW-6, rozpraszacz LR-7, dysza żelowa HKM-9) (W3).
- **U3 ekonomia** — cel: jedna część co 1–2 udane misje; zob. §1.1 (W0: pomiar).
- **U4 zużycie, które da się poczuć** — zużycie ×3, czyszczenie przy ławie za czas zamiast złomu (W0 ✅ 1.7.347).
- **U5 próba części na strzelnicy** — każda część gry do przymierzenia w szafie strzelnicy, bez zakupu (W0b ✅ 1.7.348).
- **U6 zestawy** — 3 zapisane konfiguracje na broń w profilu gracza (`Profile.presets`); Enter montuje, [R] zapisuje bieżący montaż (W1 ✅ 1.7.349). Nazwa to lista części — wpisywanie własnej nazwy i zestawy w szafie strzelnicy zostają na później.

## 3. Stanowiska w kryjówce

Każde stanowisko: znacznik mapy kryjówki, bryła 3D, podejście + [E], kamera na blat, panel z modelem na żywo jak ława 2c (decyzja 5).
Meble `hub_decor.gd` same rozsuwają się przy nowych znacznikach. Zlecenia w czasie (decyzja 1): gotowe po następnej misji.

| # | Stanowisko | Miejsce (orientacyjnie) | Co robi | Etap |
|---|---|---|---|---|
| 1 | Ława rusznikarska | środek, kol. 20 (jest) | montaż części, zestawy, nazwa broni, oględziny; oddaje PERKS/LOOK szafkom, SUPPLIES stanowiskom 3–4 | W1 |
| 2 | Stół konserwacji | środek, kol. 16 | rozkładanie broni z podzespołów `gun_proc`, części eksploatacyjne, żywotność lufy, brud na modelu | W2 |
| 3 | Prasa elaboracyjna | dół, kol. ~34 | naboje specjalne z łupu + prochu, własne ładunki słaby / gorący, chronograf na strzelnicy | W4 |
| 4 | Stół pirotechniczny | dół, kol. ~46 | granaty, miny, ładunki, 40 mm z komponentów, warianty zapalnika | W4 |
| 5 | Pracownia elektroniki i próbek | góra, kol. ~45 | ogniwa NiCd (LR-7, SPECTER-1, FALCON-6), ładowanie między misjami, próbki z elit → schematy | W6 |
| 6 | Tokarka i szlifierka | dół, kol. ~11 | części ze schematów (broń specjalna, decyzja 2), ostrzenie broni białej | W6 |
| 7 | Szafki osobiste | środek, kol. ~37 | perki i wygląd postaci, zestawy gracza | W1 |

## 4. Etapy

| Etap | Zakres | Stan |
|---|---|---|
| W0 | Złom w dzienniku sesji, zużycie ×3, czyszczenie za czas (U3 pomiar, U4) | ✅ 1.7.347 |
| W0b | Próba części na strzelnicy (U5) | ✅ 1.7.348 |
| W1 | Szafki osobiste (7), odchudzona ława (1), zestawy (U6) | ✅ 1.7.349 — zestawy z nazwą z listy części (bez wpisywania), na razie tylko przy ławie |
| W2 | Stół konserwacji (2) | ✅ 1.7.350 — stanowisko kol. 16, lufa i sprężyny, rozłożona i brudna broń na ławie 3D; brud widać tylko na ławie (nie na broni w rękach) |
| W3 | Alternatywy w gniazdach (U2), po jednym PR na broń | część 1 ✅ 1.7.351: naprawa części ognia ciągłego i broni białej na serwerze, P-83 (długa lufa, kabura-kolba), LR-7 (rozpraszacz), HKM-9 (dysza żelowa); część 2 ✅ 1.7.352: SPREAD-12 (obcięta lufa), PELLET-8 (slam-fire, długa lufa), WRATH-4 (skrócona rura), SPECTER-1 (kondensator przeładowania), maczeta (krótki chwyt) — 13 z 32 gniazd z wyborem; zostaje bełt-wabik SINEW-6 (broń z późniejszej strefy) |
| W4 | Prasa (3) i pirotechnika (4), przejęcie SUPPLIES | |
| W5 | Masa jako koszt (U1), A/B | |
| W6 | Elektronika i próbki (5), tokarka (6) | |

## 5. Decyzje (przyjęte 2026-10-22)

1. Zlecenia w czasie: **tak**, jedna misja na zlecenie, bez zegara.
2. Schematy: części broni podstawowych do kupienia od ręki; **schematy tylko dla broni specjalnych i części z badań**.
3. Masa jako koszt: **tak, po playteście**, za przełącznikiem REALISTIC / CLASSIC.
4. Cel ekonomii: **jedna część co 1–2 udane misje** (§1.1: obecne ceny go spełniają — zmiana dopiero po pomiarze).
5. Interakcja: **kamera na blat** z panelem jak ława 2c.
6. Start: **W0 i W1**.
