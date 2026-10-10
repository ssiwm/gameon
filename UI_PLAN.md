# Plan: interfejs użytkownika na poziomie pełnoprawnej gry

Status: **plan zaimplementowany; jedna pozycja odrzucona, dwie niezrobione (szczegóły niżej)** (stan z 2026-10-10, PR #121–#134). Gotowe: rejestr akcji (`actions.gd`), pad w grze
i w menu, przypisywanie klawiszy, menu główne osobno od lobby, ustawienia i wyjście przed grą, potwierdzenie wyjścia, suwaki, LEAVE SESSION,
ustawienia obrazu bez restartu, „Reduce effects”, filtr widzenia barw, napisy dźwięków, paleta, **dołączone czcionki** (Big Shoulders,
IBM Plex ×3 — OFL; Special Elite — Apache-2.0, nie OFL jak zakładał plan), VU-metr hałasu, poziomy HUD, jeden komunikat naraz, ściemnienie
pod modalami, tabela graczy i animowany pasek XP na karcie wyniku, podpowiedź w kryjówce, dźwięk najechania i krótkie przejścia,
lokalizacja EN/PL **razem z kodeksem, ulepszeniami, perkami i przedmiotami**. **Zrezygnowano:** jedna siatka ikon (dwukolorowe linie wektorowe) — po obejrzeniu wizualizacji decyzja z 2026-10-10: zostają obecne miniatury. **Dopasowanie wizualne do makiet (PR #138–#140):** menu pauzy (`pause_menu.gd`), menu główne z lasem i panelem Squad link (`main_menu.gd`, `menu_scene.gd`), lobby (`lobby.gd`) i karty HUD-u (miernik hałasu, cel, pasek broni) w stylu „deck” — wspólne widgety w `ui_widgets.gd`, stałe kolorów i `display_font()` w `ui_theme.gd`. **Rozmiar HUD (2026-10-10):** mnożniki SMALL / NORMAL / LARGE to 0,72 / 0,85 / 1,0 (dawniej 0,85 / 1,0 / 1,25 — nowy NORMAL to dawny SMALL); menu pauzy i lobby skalują się względem NORMAL (`Settings.ui_rel()`), menu główne nie zależy od rozmiaru HUD-u. **Dołożone po wdrożeniu:** czat tekstowy drużyny (T) i mono audio. **Nie zrobione:** lobby z listą graczy przed połączeniem (lobby działa przed siecią — listę i gotowość pokazuje kryjówka), kształty zamiast samych kolorów (GDD §14; etykiety tekstowe i filtr widzenia barw pokrywają większość przypadków).

Źródła: przegląd kodu UI (`lobby.gd`, `pause_menu.gd`, `settings.gd`, `input_setup.gd`, `ui_theme.gd`, `hud.gd`, `workshop_ui.gd`, `horror_fx.gd`) i zrzutów ekranu (lobby, HUD w misji 1.3, menu pauzy, kryjówka, warsztat, karta wyniku); makieta kierunku wizualnego (patrz „Makieta”).

**Czego nie sprawdzono:** zakładek kodeksu, perków i sterowania w grze, rozdzielczości innych niż 4K/1080p na moim komputerze, układu na prawdziwym 1280×720 (w zrzucie lobby lista sterowania była ucięta u dołu; komentarz w `lobby.gd` mówi, że to naprawiono, ale bez renderu nie potwierdzono), kontrastów i wyglądu efektów (obliczenia, nie pomiar). Weryfikacja z kodem nie uruchamiała gry.

## 1. Co jest dobre

- **Spójny styl:** ciemne tło z bursztynowym akcentem, czytelne ikony, bez nadmiaru ozdób. Wygląd jest zdefiniowany w jednym miejscu (`ui_theme.gd`), więc zmiana motywu to edycja tokenów, a nie przebudowa ekranów.
- **Warsztat** jest najbliżej poziomu komercyjnego: statystyki broni, ulepszenia z cenami, stany „BOSS REWARD” i „LATER ZONE”, podpowiedź klawiszy.
- **Pomysł z materiałami:** deska z mosiężną krawędzią (HUD, menu), papier z tuszem (tablice w kryjówce), niebieski szkic techniczny (warsztat). Każdy ekran wygląda jak przedmiot ze świata gry.
- **Podpowiedzi i kontekst:** podpowiedzi dla nowych graczy, pasek sterowania na dole, informacje o hałasie w HUD.

## 2. Czego brakuje (funkcje)

| Obszar | Stan w kodzie lub na zrzutach | Propozycja |
|---|---|---|
| **Gamepad** | Brak jakiegokolwiek wiązania pada w `input_setup.gd`. Same klawisze, celowanie myszą. **[kod]** Kierunek celowania = kierunek ruchu (`player.gd` `_local_brain`: 8 kierunków z klawiszy ruchu, swobodnie tylko mysz), więc druga gałka wymaga nowych akcji `aim_*` i osobnej gałęzi. Domyślne `ui_*` Godota mają już D-pad i A (w `project.godot` nie ma sekcji `[input]`); blokerem nawigacji jest `FOCUS_NONE` na zakładkach pauzy, w codeksie i w całym warsztacie. **Warsztat czyta surowe klawisze** (`workshop_ui.gd` `_input`: WASD, strzałki, Enter, Space, Esc, E, Backspace, Tab, 1/2), nie InputMap. | Pełna obsługa pada: celowanie drugą gałką, nawigacja po menu, podpowiedzi przycisków zależne od urządzenia. Wymóg Steam Decka i dużej części graczy co-op. Warsztat przenieść na akcje / `ui_*`; nowe akcje dopisać do `Settings.GAME_ACTIONS`, inaczej pad będzie strzelał przez menu pauzy. |
| **Zmiana klawiszy** | Brak. Ekran sterowania to statyczna ściąga, Alt przypisany na sztywno. **[kod]** Nazwy klawiszy są zaszyte w kilku miejscach: `Lobby.CONTROLS`, osobny napis w `hud.gd` (`_build_controls`), `"[ENTER] Continue"` w karcie wyniku, ok. 24 miejsc „[E]/Hold E…” w podpowiedziach, misjach i HUD. Surowe klawisze poza InputMap: F2 (`main.gd`), F11 (`settings.gd`), O (`hud.gd`). `Settings.block_game_input` chowa zdarzenia akcji na czas menu i je przywraca, więc zmiana klawisza wewnątrz menu pauzy zostałaby cofnięta (trzeba edytować `_stash`). | Ekran z przypisywaniem klawiszy i wykrywaniem konfliktów. Ściąga w lobby i HUD generowana z aktualnych przypisań. **Najpierw rejestr akcji** (id, etykieta, klawisze i pad domyślne, grupa), z którego korzystają `input_setup`, `GAME_ACTIONS`, ściągi i podpowiedzi (krok 0 w §4). |
| **Ustawienia grafiki** | Tylko pełny ekran, „Graphics HD/Classic” (restart), „Characters 3D”. Brak rozdzielczości, vsync, limitu fps, presetów jakości. | Rozdzielczość, vsync, limit fps, preset niska/średnia/wysoka (kompresja, MSAA, pogoda, cząsteczki). Zmiany bez restartu. |
| **Dostępność** | Rozmiar HUD w 3 krokach, drżenie ekranu (FULL / HALF / OFF), efekty pogody (FULL / REDUCED / OFF). Brak napisów dla dźwięków, trybu dla daltonistów, przełączania zamiast trzymania, redukcji migotania. **[kod]** `horror_fx.gd` (winieta, ziarno, aberracja rosnące z Uwagą, czerwone rogi pulsujące w rytmie tętna przy 1 HP) nie ma ustawienia gracza, tylko flagę dev `--nofx`. | Napisy dla kluczowych dźwięków (gra o hałasie), tryb dla daltonistów, trzymanie lub przełączanie, opcja „Reduce Effects”. **[kod]** Jeden przełącznik musi obejmować: wstrząsy, efekty pogody, `horror_fx` (ziarno, aberracja, puls HP), migotanie tytułu w lobby i nowe efekty HUD. |
| **Lokalizacja** | Teksty zaszyte w kodzie po angielsku, brak `tr()`. Dane i komentarze po polsku. | Tabela tłumaczeń. To najtańszy moment, bo każda nowa funkcja zwiększa dług. |
| **Menu główne** | Lobby jest jednocześnie menu głównym: host, join, Steam, trudność, mikrofon i lista sterowania na jednym ekranie. | Osobne menu główne (Graj, Ustawienia, Wyjście), a lobby jako osobny ekran z listą graczy, gotowością i czatem. |
| **Menu pauzy** | „QUIT GAME” zamyka grę natychmiast (`get_tree().quit()`), bez potwierdzenia. Głośności to przyciski − i +, bez suwaków. Brak „wróć do menu”. **[kod]** Esc w lobby nic nie robi (`pause_menu.gd` `_input`: `not _lobby_visible()`), więc przed hostem nie ma ani ustawień, ani wyjścia inną drogą niż zamknięcie okna. Klient wraca do lobby przy rozłączeniu (`main.gd`), ale host nie ma ścieżki „zakończ sesję”. | Potwierdzenie wyjścia, suwaki, „wróć do lobby” (dla hosta wymaga zamknięcia sesji w `main.gd`), kopiowanie ID lobby Steam, menu ustawień dostępne także z lobby. |
| **Hierarchia w HUD** | Wszystko widoczne naraz. Komunikaty „SOMETHING IS LISTENING…” i „1.3 THE NEST” nakładają się na środku z niskim kontrastem. **[kod]** Ostrzeżenie `_warn` jest już ustawiane pod kartą celu (`hud.gd` `_drive_mission`), więc nakładanie dotyczy raczej `_note`, `_hint` i `_prompt`; do potwierdzenia zrzutem. `show_note` ma jeden slot i nadpisuje (np. level-up zastępuje wcześniejszy komunikat). | Kolejka komunikatów z priorytetami (jeden na raz). Wyraźniejszy kontrast małego tekstu. HUD, który się wycisza w spokoju. |
| **Karta wyniku** | Modal na nieprzyciemnionym HUD-zie, wyniki tylko zbiorcze. | Tabela per gracz (zabójstwa, obrażenia, podniesienia, upadki), nagrody i postęp XP z animacją, przejście do kryjówki. |
| **Ekrany nad HUD-em** | Warsztat i karta wyniku rysują się przezroczyście nad HUD-em, w warsztacie przebija panel odprawy. | Przyciemnić lub ukryć HUD pod modalami, ujednolicić kolejność warstw. |
| **Pierwsze uruchomienie** | Są podpowiedzi, brak krótkiego samouczka. Misja 1.1 uczy ruchu, nie interfejsu. | Krótka, pomijalna sekwencja: ruch, hałas, latarka, kryjówka i warsztat. |
| **Dźwięk i animacja UI** | **[kod]** Dźwięki są: `ui_click`, `ui_confirm`, `ui_deny`, `warn_pulse` (szyna UI), użyte w lobby, pauzie, warsztacie i HUD. Brak dźwięku najechania. W UI nie ma żadnych tweenów, przejścia są natychmiastowe (poza zanikaniem alfa komunikatów i podpowiedzi). | Krótkie przejścia, dźwięk najechania, wyraźny stan fokusu. |

## 3. Design wizualny

### Problemy

| # | Problem | Efekt |
|---|---|---|
| 1 | **Brak własnej czcionki ciała.** Cały tekst to domyślna czcionka Godota. Pikselowa Silkscreen jest tylko dla nagłówków w trybie klasycznym. | Wygląda jak prototyp. Brak charakteru typografii. |
| 2 | **Hierarchia tylko kolorem i obrysem 3 px.** Teksty 9–11 px na płótnie 640×360. **[kod]** W praktyce jeszcze mniej: 89 wywołań `label()` / `heading()` z rozmiarem 5–9 w 5 plikach (HUD 44), a HUD i menu pauzy są dodatkowo skalowane ×0,7. Przy rozciągnięciu ×2 na 720p rozmiar 9 to ok. 12,6 px, rozmiar 7 ok. 9,8 px. Cel 14 / 12 px oznacza podniesienie większości tekstów o 30–40% i przeliczenie kart o stałych szerokościach (`SQUAD_W`, `OBJ_W`, `CARD_W`, `PAGE_H`). | Drugorzędne teksty małe i mało kontrastowe. Obrys na małym tekście robi szum. |
| 3 | **Menu pauzy źle wykorzystuje materiał:** szeroki, pusty panel z sześcioma równymi zakładkami i tytułem „PAUSED”, zakładki bywają w połowie puste. **[kod]** Sam materiał jest już rodziny HUD-u (karta używa `UiTheme.panel_box()`); problemem jest układ, nie kolor. | Warsztat (teal) i menu (brąz) to dwa różne światy w jednym przepływie. |
| 4 | **Mieszane style ikon:** perki kolorowe, bronie szare, w warsztacie jeszcze inne, w klasycznym trybie piksele obok wektorów. | Brak jednej siatki i jednego języka ikon. |
| 5 | **Brak tożsamości wizualnej gry:** tytuł to zwykły pogrubiony krój, lobby ma płaskie ciemne tło, brak logo i grafiki promocyjnej. | Motyw radia, hałasu i nasłuchu nie jest wykorzystany. |
| 6 | **HUD ma równą wagę wszystkich elementów.** Siedem paneli o tym samym kolorze tła. | Gracz nie wie, na co patrzeć najpierw. |
| 7 | **Modale na pełnym HUD-zie** (wynik, warsztat). | Ekran zagracony zamiast skupionego. |

### Kierunek: horror, UI jest częścią świata i psuje się wraz z hałasem

Pierwotny kierunek „sprzęt radiowy z 1987 roku” został przesunięty w stronę horroru, a z makiety usunięto efekt VHS (pasmo śledzenia, linie skanowania, rozdwojenie kolorów).

1. **Paleta:** prawie wszystko to kość słoniowa na niemal czarnym tle. Krew jest racjonowana (niebezpieczeństwo, aktywny punkt menu, tytuł). Przygasająca lampa to jedyne ciepłe światło (bezpieczne miejsca, nagrody).

   | Rola | Kolor | Kontrast na panelu |
   |---|---|---|
   | Tło | `#050605` | – |
   | Panel (deck) | `#0B0C0B` | – |
   | Kość (tekst) | `#D9D4C3` | 13,2:1 |
   | Przygaszony | `#8D8A7C` | 5,7:1 |
   | Krew (niebezpieczeństwo) | `#E5483A` | 4,9:1 |
   | Lampa | `#D9922E` | 7,6:1 |
   | Mgła (spokój) | `#6FA39B` | 6,9:1 |
   | Mech (OK) | `#8AA879` | 7,5:1 |

   Współczynniki to obliczenia, nie pomiar narzędziem. Kolor nigdy nie niesie znaczenia sam: CRITICAL, HUNTED i znaczniki ◆ mają też etykietę lub kształt.
2. **Typografia, cztery role:** Big Shoulders Stencil Display (tytuły, menu, przyciski), IBM Plex Mono (liczby i etykiety przyrządów), Special Elite (jedyny „szept” maszynowy: alerty, podpowiedzi, ostatnia audycja), IBM Plex Sans Condensed (opisy i ustawienia). Minimum 14 px tekst i 12 px etykiety na 720p, panele zamiast obrysu pod tekstem. Wszystkie kroje na licencji OFL.
3. **Wskaźnik hałasu jako znak firmowy:** analogowy VU-metr ze strefami CALM / UNEASY / HUNTED zamiast paska. **[kod]** Etykiety i kolory stanów już są w HUD (`_drive_noise`). Progi to `UNEASY_THRESHOLD` 40, `AWAKE_THRESHOLD` 60 i `SLEEP_THRESHOLD` 30 (histereza), a Nocny Dyżur je zmienia (`NightShift.awake_threshold` / `sleep_threshold`), więc strefy VU-metru czytamy z `NoiseMgr`, nie z wartości na sztywno.
4. **Interfejs psuje się wraz z hałasem** (progi poniżej to szkic z makiety; w kodzie patrz punkt 3):
   - 0–29%: czysty obraz, lekkie ziarno, panele T2 i T3 wygaszone.
   - 30–59%: ziarno rośnie, winieta się zaciska.
   - 60–100%: czerwona winieta, drżący wskaźnik, pulsująca etykieta HUNTED, EKG przy krytycznym zdrowiu.

   **[kod]** Warstwa świata już to robi: `horror_fx.gd` (shader pod HUD-em) zwiększa winietę, ziarno i aberrację wraz z Uwagą, a przy niskim HP desaturuje i pulsuje czerwonymi rogami w rytmie tętna. Nowa jest tylko degradacja samego HUD-u (drżenie wskaźnika, wygaszanie T2 / T3); decyzja w §5: rozszerzyć istniejący shader czy dodać osobny efekt UI.
5. **Zasady grozy:** (01) szeptać, nie krzyczeć: jeden alert naraz, bez wykrzykników i stingerów na UI; (02) pusty ekran jest straszniejszy: w spokoju tylko zdrowie, amunicja i wskaźnik; (03) obecność na krawędziach (oczy w lesie, sylwetka we mgle), nigdy jump scare w UI; (04) migotanie jest racjonowane: tylko lampa, tytuł i HUNTED, nigdy tekst ciała; (05) czytelność przede wszystkim: 4,5:1 i opcja „Reduce Effects” usuwająca ziarno, migotanie, drżenie ekranu i wskaźnika.
6. **Trzy poziomy HUD:** T1 krytyczne (zdrowie, amunicja, wskaźnik hałasu) zawsze 100%; T2 kontekstowe (cel, sloty, wyposażenie) wygaszane do ok. 55% po 4 s spokoju; T3 tło (podpowiedzi, zegar, XP).
7. **Materiały:** menu pauzy należy do rodziny HUD-u (deska; **[kod]** już tak jest); papier zostaje przy tablicach w kryjówce, szkic tylko w warsztacie.
8. **Ruch:** panel 160 ms (wejście z 8 px), przełączenie zakładki 140 ms, liczniki 400 ms, wszystko 0 ms przy „Reduce Effects”.
9. **Jedna siatka ikon:** dwukolorowe linie wektorowe, wspólne dla perków, przedmiotów i interfejsu.

### Makieta

Płótno z czterema planszami (menu główne interaktywne, HUD z suwakiem hałasu, menu pauzy, system designu): https://claude.ai/artifact/QENgbvLR3gFQvNRNiFSTSR. Strona jest prywatna (widoczna tylko dla właściciela). Makieta nie była renderowana ani oglądana po ostatnich zmianach, więc efekty (ziarno, migotanie) mogą wyglądać inaczej niż zamierzono. Opcja „Reduce Effects” jest w makiecie tylko opisana jako zasada.

## 4. Proponowana kolejność

0. **Rejestr akcji (nowy, wynik weryfikacji z kodem):** jedno źródło prawdy o akcjach (id, etykieta, klawisze i pad domyślne, grupa). Zasila `input_setup.gd`, `Settings.GAME_ACTIONS`, `Lobby.CONTROLS`, napis sterowania w HUD i teksty podpowiedzi; warsztat przechodzi z surowych klawiszy na akcje / `ui_*`. Bez tego pad, przypisywanie klawiszy i ściągi generowane z przypisań rozjeżdżają się w kilku miejscach naraz.
1. **Fundamenty funkcjonalne:** obsługa pada i nawigacja fokusem (zdjąć `FOCUS_NONE`, druga gałka jako `aim_*`), przypisywanie klawiszy (z poprawką `block_game_input`), menu główne osobno od lobby, ustawienia i wyjście dostępne także z lobby, „wróć do lobby” dla hosta, potwierdzenie wyjścia.
2. **Fundament wizualny:** czcionki i tokeny kolorów w `ui_theme.gd`, wspólne komponenty (przyciski, zakładki, suwaki, przełączniki, fokus), menu pauzy w rodzinie HUD-u.
3. **Ustawienia:** grafika bez restartu (rozdzielczość, vsync, fps, presety) i dostępność (napisy, daltoniści, „Reduce Effects”).
4. **Znaki firmowe:** wskaźnik hałasu (VU-metr), logo i tło menu głównego, degradacja HUD wraz z hałasem.
5. **Przepływ gry:** kolejka komunikatów, trzy poziomy HUD, karta wyniku z tabelą per gracz, przyciemnianie HUD pod modalami, krótki samouczek.
6. **Dług, który rośnie:** lokalizacja (tabela tłumaczeń), dźwięki i animacje UI, jedna siatka ikon.

Pierwszy punkt to największy zakres: pad i fokus dotykają każdego ekranu, a zmiana klawiszy wymaga przebudowy `input_setup.gd`. Każdy punkt jako osobny PR z testem (`--maptest` i testy broni nie obejmują UI, więc dla UI przydadzą się zrzuty kontrolne `tools/shot_*.gd`) i wpisem w GDD.

## 5. Decyzje do podjęcia

- Czy pad ma być w pierwszej kolejności (wymóg Steam Decka), czy menu główne i przypisywanie klawiszy?
- Intensywność efektów horroru (ziarno, migotanie): domyślnie włączone z opcją „Reduce Effects”, czy łagodniej?
- Krój „szeptu” (Special Elite): zostaje czy zamiana na inny.
- Czy usunąć też ziarno filmowe, jeśli przeszkadza (poza VHS, który już usunięto).
- **[kod]** Degradacja HUD wraz z hałasem: rozszerzyć shader `horror_fx.gd` (jedno miejsce, jeden przełącznik „Reduce Effects”), czy osobny efekt na warstwie UI.
- **[kod]** Czy „Reduce Effects” ma zastąpić dotychczasowe trzy osobne ustawienia (wstrząsy, pogoda, `horror_fx`), czy je zostawić i dodać jako nadrzędny przełącznik.

## 6. Weryfikacja z kodem (2026-10-09)

Plan porównano z kodem (bez uruchamiania gry). Skrót wyników; szczegóły są w tabelach powyżej, oznaczone **[kod]**.

| Twierdzenie planu | Wynik | Dowód |
|---|---|---|
| Brak pada | potwierdzone | `input_setup.gd`: tylko `KEY_*` i mysz |
| Brak zmiany klawiszy | potwierdzone, zakres większy | surowe klawisze w `workshop_ui.gd`, F2, F11, O; kolizja z `Settings.block_game_input` |
| Ustawienia grafiki: tylko pełny ekran i restart | potwierdzone | `pause_menu.gd` `_build_settings` |
| Brak lokalizacji | potwierdzone | 0 użyć `tr()`, brak plików tłumaczeń |
| Quit bez potwierdzenia, − / + zamiast suwaków | potwierdzone | `pause_menu.gd` |
| Karta wyniku zbiorcza, bez ściemnienia | potwierdzone | `hud.gd` `_build_result`, brak statystyk per gracz |
| Brak kolejki komunikatów | potwierdzone | osobne sloty `_warn` / `_note` / `_hint`, `show_note` nadpisuje |
| Menu pauzy zrywa z materiałami | **nieścisłe** | karta używa `panel_box()` (ta sama deska co HUD); problem to układ |
| Dźwięki UI „nie sprawdzano” | **uzupełnione** | `ui_click` / `ui_confirm` / `ui_deny` / `warn_pulse` istnieją; brak hovera i tweenów |
| Nakładanie ostrzeżenia na kartę celu | **do potwierdzenia** | `_warn` jest ustawiane pod kartą celu |
| Strefy hałasu 0–29 / 30–59 / 60–100 | **niezgodne** | 40 / 60, sleep 30; progi zmienne w Nocnym Dyżurze |
| Ziarno / winieta z hałasem jako nowość | **już jest w świecie** | `horror_fx.gd`; nowa jest tylko degradacja HUD-u |
| „Reduce Effects” jako jedna opcja | **zakres większy** | `horror_fx` ma tylko flagę `--nofx`, plus puls HP i migotanie tytułu |
| Esc / ustawienia w lobby | **luka planu** | Esc w lobby nic nie robi; host nie ma „zakończ sesję” |

Skala zmian (grep, orientacyjnie): 89 wywołań tekstu o rozmiarze ≤ 9 w 5 plikach; 202 literały `Color(` w 9 plikach UI, z czego 32 w `ui_theme.gd`, więc migracja palety dotknie ok. 170 miejsc poza motywem.
