# Plan: komunikaty w grze — jeden system zamiast kilkunastu osobnych

Status: **wdrożone w czterech PR-ach, czekają na przegląd** (stan z 2026-10-17): etap 1 — #337 (arbiter `Msg`, tokeny, test), etap 2 — #338 (notatki w trzech materiałach, ciemna paleta, pasek akcji, 1.7.269), etap 3 — #339 (alerty, toasty, karta tytułowa, 1.7.270), etap 4 — #340 (dziennik na klawiszu **N** zamiast J, bo J to strzał, porady na kanale TIP, 1.7.271). Materiał „kartka odręczna” jest gotowy w komponencie, ale nie ma jeszcze odbiorcy (ostrzeżenia i porady idą dziś ciemnymi kartami); papier w 3D (2b) zrobiony w #341 razem ze zmniejszeniem wszystkich komunikatów o 20% (1.7.272). Dokument poniżej zachowuje pierwotny plan. Powstał z audytu `hud.gd`, `hints.gd`, `mission.gd`, `main.gd` i zrzutów z gry
(kryjówka przy tablicy, start misji, odliczanie wyjścia, prognoza). Makiety przed i po (kadry z gry z nałożoną propozycją) oraz trzy warianty stylu notatek
były oglądane i zaakceptowane co do kierunku; styl notatek wymaga jeszcze potwierdzenia poziomu przyciemnienia w grze (patrz „Decyzje”).

Dotyczy komunikatów, czyli tego, co się zdarza: karty przy obiektach, ostrzeżenia, podpowiedzi, noty, baner startu, toasty. Karty stanu (hałas, drużyna,
ekwipunek, zegar) zostają, jak są.

## 1. Co jest dziś

Dwanaście rodzajów komunikatów, każdy powstał osobno:

| # | Rodzaj | Kod | Miejsce i czas życia |
|---|---|---|---|
| 1 | Karta celu | `hud.gd` `_build_objective_card` | góra, środek; stała w misji; podpowiedź pod tytułem 7 px |
| 2 | Odprawa (karta papierowa) | `hud.gd` `_drive_cards`, `_fill_brief` | nad tablicą w kryjówce, gdy gracz jest w zasięgu (56 px) |
| 3 | Prognoza (karta papierowa) | `hud.gd` `_drive_radio` | nad radiostacją, w zasięgu |
| 4 | Pasek kontekstowy | `hud.gd` `_drive_prompt` (ok. 130 linii `elif`) | dół, środek (76% wysokości); tekst i pasek postępu |
| 5 | Baner startu misji | `hud.gd` `_center`, `_center_sub` | środek ekranu na wysokości głów; tytuł, cel, linie radia, pogoda |
| 6 | Odliczanie w kryjówce | `mission.gd` `objective_hint`, `hud.gd` `_hub_count` | tekst w karcie celu plus duża cyfra |
| 7 | Ostrzeżenie o hałasie | `hud.gd` `_drive_warning` | środek, 25% wysokości |
| 8 | Nota (jedna linia) | `hud.gd` `show_note` | 3 do 5 s, jeden slot (awans, „They know this trick”) |
| 9 | Podpowiedzi TIP | `hints.gd` (16 wpisów) | nad paskiem kontekstowym, 7 s, każda tylko raz |
| 10 | Feed XP, napisy dźwięków, czat | `hud.gd` | trzy osobne listy z własnym wygaszaniem |
| 11 | Toast sieciowy | `main.gd` `_toast` | osobny mechanizm poza HUD-em |
| 12 | Etykiety w świecie | `player.gd`, `view3d.gd` `_add_kind_tag` | „P1 / BOT” nad postaciami, znaczniki przedmiotów |

## 2. Co jest nie tak

- **Ta sama informacja kilka razy.** Cel misji jest w karcie celu i w banerze startu; pogoda w wierszu karty hałasu, w banerze i w karcie prognozy; gotowość w kryjówce
  w karcie celu, w kwadracikach, w dużej cyfrze i w pasach na podłodze.
- **Priorytet siedzi w warunkach, nie w danych.** `_drive_prompt` to łańcuch `elif`; `_drive_hint` sprawdza `_warn.text` i `_note_t`, baner sprawdza `_inspect`,
  odprawę i radio. Każdy komunikat zna część pozostałych, więc kolizje wychodzą dopiero na ekranie (duża cyfra odliczania nachodziła na kartę odprawy).
- **Dwa języki wizualne i chaos typograficzny.** Karty ciemne i papierowe (papierowe tylko dwie); rozmiary tekstu 7, 8, 9, 10, 14, 16, 21, 24 i 56 w jednym HUD-zie;
  klawisze raz jako ramki, raz jako tekst w nawiasach.
- **Różne czasy życia i brak powrotu.** Tip 7 s, nota 3 do 5 s, baner kilka sekund; przegapiony komunikat znika, tip jest „spalony” po jednym pokazaniu.
- **Luki w tłumaczeniu.** W `hud.gd` ok. 21 z 47 literałów komunikatów nie ma wiersza w `translations/ui.csv` (np. „WEATHER FORECAST”, „Side goal — hidden”,
  „Extraction failed — …”), komunikaty bossów i ewakuacji („GRABBED —”, „THE TIDE IS RISING —”, „EVACUATING…”) są poza tabelą. To szacunek skryptem po
  literałach, do potwierdzenia przy wdrożeniu.
- **Dostępność.** Znaczenie głównie kolorem, małe napisy (7 px), brak wspólnej opcji „mniej komunikatów”, napisy dźwięków żyją osobno.

## 3. Model docelowy: sześć kanałów

Każdy komunikat to dane (`id`, kanał, priorytet, czas życia, klucz tłumaczenia z parametrami, klawisze, postęp), a nie węzeł tekstowy. O widoczności decyduje jeden
arbiter; każdy kanał ma jedno, stałe miejsce i jeden styl.

| Kanał | Co trafia | Zasady | Zastępuje |
|---|---|---|---|
| **A · Notatka** | informacja związana z miejscem: odprawa, prognoza, cena, plakietki, oględziny | papier z pinezką i ogonkiem, kotwica nad obiektem, jedna naraz (bliższa na wierzch), stopka z klawiszami, rozmiary S, M, L | 2, 3, część paska i oględzin |
| **B · Alert** | zagrożenie i stan drużyny: hałas, SQUAD DOWN, chwyt Pijawki, przypływ, odliczanie wyjścia | pod kartą celu, duży krój i ikona, jeden naraz wg wagi, trwa tak długo jak powód, ten sam komunikat aktualizowany w miejscu (3, 2, 1) | 6, 7, część paska |
| **C · Toasty** | zdarzenia: XP, awans, perk, złom, zmiana pogody, dołączenie gracza, błędy sieci | stos do trzech pod kartą RUN, 3 do 5 s, łączenie duplikatów (+XP sumuje się), wspólne dla HUD-u i sieci | 8, 10 (XP), 11 |
| **D · Karta tytułowa** | start misji: tytuł, linie radia, krótka reguła, pogoda jako jedna linia | dolna trzecia po lewej nad kartą drużyny, 6 s, nigdy w środku akcji; cel tylko w karcie celu | 5 |
| **E · Porada** | wskazówki dla nowych graczy | tylko w spokojnych chwilach, nad kartą drużyny, każda trafia do dziennika | 9 |
| **F · Pasek akcji** | co mogę zrobić teraz: [E], [F], przytrzymaj, postęp | rejestr dostawców zamiast łańcucha `elif`, priorytety w danych, klawisze jako klawisze (`actions.gd`), akcja główna i drugorzędna | 4 |

Zasady arbitra: jeden komunikat naraz na kanał, wywłaszczenie wagą, deduplikacja po `id`, aktualizacja w miejscu, cooldown dla powtarzalnych. Wszystkie teksty
przez klucze w `ui.csv` (`tr()` i `Actions.fmt`); komunikaty trafiają też do dziennika [J] (ostatnie 30 plus spis odkrytych porad).

## 4. Styl notatek (kanał A)

Notatka ma wyglądać jak znaleziony przedmiot z 1987 roku w świecie, który oświetlają tylko lampy i latarka: niedoskonała, ludzka, trochę niepokojąca, ale zawsze
czytelna. Materiał zależy od źródła informacji:

| Materiał | Rodzaj informacji | Gdzie |
|---|---|---|
| Akta sztabu (maszynopis, teczka, pieczątka, zdjęcie ze spinaczem) | oficjalne, wymagające lektury: odprawa, bestiariusz, opis broni | tablica odpraw, oględziny broni, dziennik |
| Wydruk z radia (perforacja, krój matrycowy) | dane z zewnątrz: prognoza, zmiana pogody, status misji, ewakuacja | radiostacja, toasty „RADIO”, karta tytułowa |
| Kartka odręczna (zeszyt, marker, taśma, ptaszki graczy) | ostrzeżenia, porady, ślady poprzednich oddziałów; krótkie | porady TIP, plakietka D-7, napisy na ścianach, wpisy „od kolegi” |
| Metka kartonowa i etykieta Dymo | przedmioty: cena, odblokowanie, ulepszenie | stojaki, gabloty, ława warsztatu |

**Ciemna paleta (zasada, bo gra toczy się w nocy):**

- luminancja względna tła notatki ≤ 0,3 (obecny papier ma 0,59 do 0,81): zgaszona ochra, oliwka, szarość, bez bieli i kremu,
- tekst ≥ 4,5:1 względem tła, duże pismo (≥ 24 px) ≥ 3:1; zmierzone dla propozycji: akta 4,6, kartka 5,3, metka 5,2, czerwony nagłówek 3,3 (duże pismo),
- wydruk z radia odwrócony: ciemne tło i fosforowy zielony tekst (kontrast ok. 12:1), perforacja jaśniejsza niż tło, żeby nadal był papierem,
- światło lokalne: notatka jaśniejsza pod lampą, ciemniejsza w półmroku (w HUD z jasności otoczenia i bliskości lampy, w 3D ze świateł sceny),
- zużycie z kampanii: plamy krwi i spalenia na brzegach rosną z liczbą upadków drużyny (`RunLog`), nigdy na tekście; ptaszki graczy w kolorach slotów z `hud.gd`;
  tryb wysokiego kontrastu wyłącza tekstury i zostawia płaski papier.

Zasoby: 3 tekstury papieru (CC0), 6 dekoracji (taśma, spinacz, pinezka, plamy, spalenie, kółko po kawie) i czcionki OFL osadzone jako TTF w `art/fonts/`.
**Special Elite już jest w repo** (Apache-2.0, `SpecialElite-Regular.ttf`); do dodania VT323, Caveat i Permanent Marker. **Wymagane sprawdzenie polskich znaków** w każdej
z nich; jeśli któraś zawiedzie, zamiana na podobną z pełnym Latin-Ext.

## 5. Etapy

Każdy etap to osobny PR, grywalny sam w sobie; PR-y zmieniające grę podbijają wersję i dopisują wiersz do `CHANGELOG.md`.

1. **Fundament** (`messages.gd`, `ui_theme.gd`): struktura wiadomości i arbiter, tokeny typografii (cztery rozmiary) i stylów semantycznych (info, akcja, sukces,
   ostrzeżenie, groźba, papier), test headless arbitra (`tools/test_messages.gd`: priorytet, deduplikacja, czas życia), flaga zrzutu `--shotmsg=RODZAJ` do przeglądu
   każdego typu.
2. **Notatki, styl i pasek akcji** (`hud.gd`, `ui_theme.gd`): jeden komponent notatki S, M, L dla odprawy i prognozy, trzy materiały jako skórki karty HUD
   (`StyleBoxTexture`, nieregularny obrys, dekoracje jako dzieci karty), ciemna paleta jako stałe w `ui_theme.gd` zamiast jasnych `PAPER_*` i `INK_*`, mnożnik jasności
   z otoczenia, zużycie z `RunLog`, test `tools/test_note_contrast.gd` (kontrast WCAG każdej pary i luminancja papieru, PASS do CI). Pasek akcji z rejestrem
   dostawców zamiast łańcucha `elif`.
   - **2b (opcjonalnie):** papier w świecie 3D dla odprawy i prognozy: quad z teksturą z `SubViewport` (jak kreda na tablicy wyników), przypięty do tablicy, oświetlony
     lampami; karta HUD zostaje jako widok „czytam z bliska”.
3. **Alerty, toasty, tytuł** (`hud.gd`, `mission.gd`, `main.gd`): kanały B, C i D; ostrzeżenia hałasu, odliczanie wyjścia, stos toastów (XP, awans, pogoda, sieć),
   dolna trzecia zamiast środkowego banera; usunięcie powtórzeń (cel tylko w karcie celu, pogoda jedną linią); domknięcie tłumaczeń w `ui.csv`.
4. **Dziennik i porady** (`hints.gd`, `pause_menu.gd`): dziennik [J] z ostatnimi 30 komunikatami i spisem odkrytych porad; porady tylko w spokojnych chwilach i z wpisem
   do dziennika; nowa akcja w `actions.gd`.

Minimum, które daje połowę zysku w czytelności: etapy 1 i 2.

## 6. Ryzyka i czego nie sprawdzono

- Wygląd w samej grze (lampy, latarka, kamera) oceniono tylko na makietach z kadrami; poziom przyciemnienia trzeba zobaczyć po wdrożeniu etapu 2.
- Liczba brakujących tłumaczeń to szacunek skryptem po literałach, nie pełny audyt.
- Pokrycie polskich znaków przez czcionki odręczne niesprawdzone w grze.
- Dziennik [J] to nowy ekran i klawisz; etap 4 można pominąć bez wpływu na resztę.
- Zmiana kolejności i miejsc komunikatów zmienia zrzuty referencyjne i układ HUD-u (`_fit` w `hud.gd`); każdy etap sprawdzać zrzutami (`--shot`, flagi `--shot*`).

## 7. Decyzje

- Zakres: minimum (etapy 1 i 2) czy pełny system (etapy 1 do 4).
- Poziom przyciemnienia papieru (luminancja ≤ 0,3 to propozycja) i wydruk odwrócony czy ciemny papier z czarnym tekstem.
- Dziennik [J] jako nowa funkcja.
- Baner startu w środku zamienić na dolną trzecią (traci „kinowy” środek ekranu, przestaje zasłaniać akcję).
- Papier tylko dla informacji z miejsca (kanał A), reszta ciemnych kart; to zmiana wyglądu, nie logiki.
- Krew i zużycie z kampanii (zero wpływu na grę; do wyłączenia dla trybu łagodnego).
