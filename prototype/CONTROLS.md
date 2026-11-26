# Sterowanie 1.7.374

## Wdrożone

`actions.gd` jest rejestrem akcji, mapą zdarzeń i źródłem etykiet. `bindings_policy.gd` określa,
które akcje działają jednocześnie w misji, na strzelnicy i w menu. Celowanie przez przyrządy i krzyk
mogą współdzielić LT, ponieważ działają w różnych kontekstach; przeniesienie LT do strzału przy
zamianie ADS z RT jest odrzucane, ponieważ strzał i krzyk działałyby równocześnie w misji.

- `plan_binding` / `plan_remove` przygotowują zmianę bez modyfikowania `InputMap` ani pliku ustawień.
- `apply_plan` ponownie sprawdza kompletną mapę i rewizję; zatwierdzenie nieaktualnego planu jest odrzucane.
- Klawisz ANY nakłada się na LEFT i RIGHT. Nowy prawy Alt jest zapisywany jako RIGHT, stary `left` migruje.
- Menu pokazuje wszystkie zmieniane akcje, przyjmuje klawiaturę, mysz i spusty, pozwala dodać/usunąć wiązanie.
  Przechwytywanie trwa podczas zmiany urządzenia i ignoruje ruch drążka. Esc anuluje bez zapisu.
- Esc pozostaje stały dla pauzy. Osie ruchu/celowania są stałe. Menu zachowuje nawigację także po zmianach akcji gry.
- Pusta tablica w konfiguracji oznacza świadome wyłączenie. Niepusta tablica z wadliwymi danymi pozostawia domyślne
  wiązania. Jeżeli starszy, poprawny zapis używa już H, zachowuje H, a nowa akcja oględzin pozostaje nieprzypisana.
  Pozostałe kolidujące zapisane nadpisania wracają do domyślnych, a menu informuje o naprawionych akcjach.
- Podczas nakładki zmiany trafiają do schowka `Settings._stash`; zamknięcie przywraca aktualne przypisania.
- Kafle ekwipunku, sloty broni, podpowiedzi oględzin i ściągi korzystają z aktualnych wiązań oraz urządzenia.
  Niestandardowe sloty 6/8/0 pokazują 6/8/0, strzelnica na padzie pokazuje przycisk następnej broni.
- H otwiera oględziny przy łupie/gablocie. F rzuca flarę także w pobliżu broni. Obrót oględzin korzysta z akcji
  celowania, a nie surowego odczytu kontrolera nr 0.
- Podparcie na strzelnicy ma osobne HOLD/TOGGLE, niezależne od skradania. Zmiana stanowiska/nakładka zeruje Toggle.

## Cel interakcji [E] (od 1.7.691, `INTERACT_PLAN.md`)

Jedno [E] (pad: [B]) robi jedną rzecz. `scripts/interact.gd` co klatkę wybiera cel lokalnego gracza spośród ofert obiektów: najpierw
możliwe, potem priorytet, potem odległość (przy różnicy < 4 px — strona, w którą patrzy postać). Cel trzymanego [E] nie zmienia się
do puszczenia klawisza. Pasek akcji i znacznik 3D pokazują ten sam cel.

| Priorytet | Cel |
|---|---|
| 100 | podnoszenie kolegi |
| 90 | pompowanie drezyny |
| 80 | broń na ziemi, na stojaku, gablota |
| 70 / 65 | taśma w ścianie / stempel |
| 60 | sejf, generator, barykada |
| 50 | zwłoki |
| 40 | stanowiska kryjówki |
| 30 | tablica odprawy, drzwi strzelnicy |

- Znacznik celu: zardzewiały klawisz [E] na wierzchu obiektu w świecie 3D; przy przytrzymaniu owija go drut kolczasty (postęp), szary,
  gdy akcja jest niemożliwa (brak desek, broń zablokowana). Przy broni i gablocie obok [H] (oględziny); na padzie klawisz pokazuje
  przycisk pada. Opcja „Interaction highlight” w menu pauzy; „Reduce effects” wyłącza oddech, kołysanie, iskry i zakłócenie.
- Pad bez przycisku oględzin (Classic): krótkie [B] bierze broń, przytrzymanie [B] 0,4 s otwiera oględziny. Podpowiedź pokazuje
  „Hold [B]  Inspect”, a bez żadnego przypisania pomija oględziny (bez „[—]”).

## Profile

Classic jest domyślny i zachowuje dotychczasowy układ z osobnym H. Modern jest opcjonalny:

| Akcja | Modern — klawiatura/mysz | Modern — pad (Xbox) |
|---|---|---|
| Latarka | C / L | D-pad ← |
| Przedmiot | M4 / lewy Alt (Cmd/Alt na macOS) | RB |
| Oględziny | H / M5 | Share |
| Przeładowanie | R | X |
| Cios | V / PPM | R3 |

Oba profile wymagają zatwierdzenia przed zastąpieniem własnych przypisań. Start gry nie wybiera Modern.
Nazwy PlayStation/Nintendo wynikają z nazwy kontrolera zwracanej przez Godota; przypisania logiczne pozostają te same.

## Weryfikacja i granice

`tools/test_interact.gd` sprawdza wybór celu [E], obiekty obok siebie, odstępy zasięgów kryjówki i oględziny przytrzymaniem na padzie.
`tools/test_input_bindings.gd` wykonuje regresje mapy zdarzeń, zapisów, rzeczywistego menu/HUD-u, oględzin i flary.
`tools/test_controls_render.gd` sprawdza układ polskiego panelu, widoczność przycisków, fokus i działanie przycisków
edycji; zapisuje zrzut viewportu. Oba testy blokują CI. Testy strzelnicy i broni pozostają w dotychczasowym CI.

Syntetyczne zdarzenia potwierdzają logikę i oznaczenia. Fizyczne kontrolery oraz macOS wymagają playtestu.
Starszy pad lub wirtualny Xbox może nie udostępniać Share/Create; oględziny można przypisać ręcznie.
Nie ma automatycznej naprawy przez zgadywanie zamian: niebezpieczny nowy plan jest odrzucany z nazwą konfliktu.
