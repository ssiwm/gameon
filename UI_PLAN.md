# Plan: interfejs użytkownika na poziomie pełnoprawnej gry

Status: **plan i makieta, nic jeszcze nie zaimplementowano** (stan z 2026-10-09, po PR #119).
Źródła: przegląd kodu UI (`lobby.gd`, `pause_menu.gd`, `settings.gd`, `input_setup.gd`, `ui_theme.gd`) i zrzutów ekranu (lobby, HUD w misji 1.3, menu pauzy, kryjówka, warsztat, karta wyniku); makieta kierunku wizualnego (patrz „Makieta”).

**Czego nie sprawdzono:** zakładek kodeksu, perków i sterowania w grze, rozdzielczości innych niż 4K/1080p na moim komputerze, układu na prawdziwym 1280×720 (w zrzucie lobby lista sterowania była ucięta u dołu), animacji i przejść między ekranami (zakładam, że są natychmiastowe), dźwięków interfejsu.

## 1. Co jest dobre

- **Spójny styl:** ciemne tło z bursztynowym akcentem, czytelne ikony, bez nadmiaru ozdób. Wygląd jest zdefiniowany w jednym miejscu (`ui_theme.gd`), więc zmiana motywu to edycja tokenów, a nie przebudowa ekranów.
- **Warsztat** jest najbliżej poziomu komercyjnego: statystyki broni, ulepszenia z cenami, stany „BOSS REWARD” i „LATER ZONE”, podpowiedź klawiszy.
- **Pomysł z materiałami:** deska z mosiężną krawędzią (HUD, menu), papier z tuszem (tablice w kryjówce), niebieski szkic techniczny (warsztat). Każdy ekran wygląda jak przedmiot ze świata gry.
- **Podpowiedzi i kontekst:** podpowiedzi dla nowych graczy, pasek sterowania na dole, informacje o hałasie w HUD.

## 2. Czego brakuje (funkcje)

| Obszar | Stan w kodzie lub na zrzutach | Propozycja |
|---|---|---|
| **Gamepad** | Brak jakiegokolwiek wiązania pada w `input_setup.gd`. Same klawisze, celowanie myszą. | Pełna obsługa pada: celowanie drugą gałką, nawigacja po menu, podpowiedzi przycisków zależne od urządzenia. Wymóg Steam Decka i dużej części graczy co-op. |
| **Zmiana klawiszy** | Brak. Ekran sterowania to statyczna ściąga, Alt przypisany na sztywno. | Ekran z przypisywaniem klawiszy i wykrywaniem konfliktów. Ściąga w lobby i HUD generowana z aktualnych przypisań. |
| **Ustawienia grafiki** | Tylko pełny ekran, „Graphics HD/Classic” (restart), „Characters 3D”. Brak rozdzielczości, vsync, limitu fps, presetów jakości. | Rozdzielczość, vsync, limit fps, preset niska/średnia/wysoka (kompresja, MSAA, pogoda, cząsteczki). Zmiany bez restartu. |
| **Dostępność** | Rozmiar HUD w 3 krokach, drżenie ekranu, efekty pogody. Brak napisów dla dźwięków, trybu dla daltonistów, przełączania zamiast trzymania, redukcji migotania. | Napisy dla kluczowych dźwięków (gra o hałasie), tryb dla daltonistów, trzymanie lub przełączanie, opcja „Reduce Effects”. |
| **Lokalizacja** | Teksty zaszyte w kodzie po angielsku, brak `tr()`. Dane i komentarze po polsku. | Tabela tłumaczeń. To najtańszy moment, bo każda nowa funkcja zwiększa dług. |
| **Menu główne** | Lobby jest jednocześnie menu głównym: host, join, Steam, trudność, mikrofon i lista sterowania na jednym ekranie. | Osobne menu główne (Graj, Ustawienia, Wyjście), a lobby jako osobny ekran z listą graczy, gotowością i czatem. |
| **Menu pauzy** | „QUIT GAME” zamyka grę natychmiast (`get_tree().quit()`), bez potwierdzenia. Głośności to przyciski − i +, bez suwaków. Brak „wróć do menu”. | Potwierdzenie wyjścia, suwaki, „wróć do lobby”, kopiowanie ID lobby Steam. |
| **Hierarchia w HUD** | Wszystko widoczne naraz. Komunikaty „SOMETHING IS LISTENING…” i „1.3 THE NEST” nakładają się na środku z niskim kontrastem. | Kolejka komunikatów z priorytetami (jeden na raz). Wyraźniejszy kontrast małego tekstu. HUD, który się wycisza w spokoju. |
| **Karta wyniku** | Modal na nieprzyciemnionym HUD-zie, wyniki tylko zbiorcze. | Tabela per gracz (zabójstwa, obrażenia, podniesienia, upadki), nagrody i postęp XP z animacją, przejście do kryjówki. |
| **Ekrany nad HUD-em** | Warsztat i karta wyniku rysują się przezroczyście nad HUD-em, w warsztacie przebija panel odprawy. | Przyciemnić lub ukryć HUD pod modalami, ujednolicić kolejność warstw. |
| **Pierwsze uruchomienie** | Są podpowiedzi, brak krótkiego samouczka. Misja 1.1 uczy ruchu, nie interfejsu. | Krótka, pomijalna sekwencja: ruch, hałas, latarka, kryjówka i warsztat. |
| **Dźwięk i animacja UI** | Nie sprawdzano. | Krótkie przejścia, dźwięki najechania i kliknięcia, wyraźny stan fokusu. |

## 3. Design wizualny

### Problemy

| # | Problem | Efekt |
|---|---|---|
| 1 | **Brak własnej czcionki ciała.** Cały tekst to domyślna czcionka Godota. Pikselowa Silkscreen jest tylko dla nagłówków w trybie klasycznym. | Wygląda jak prototyp. Brak charakteru typografii. |
| 2 | **Hierarchia tylko kolorem i obrysem 3 px.** Teksty 9–11 px na płótnie 640×360. | Drugorzędne teksty małe i mało kontrastowe. Obrys na małym tekście robi szum. |
| 3 | **Menu pauzy zrywa z pomysłem materiałów:** szeroki, pusty panel z sześcioma równymi zakładkami i tytułem „PAUSED”, zakładki bywają w połowie puste. | Warsztat (teal) i menu (brąz) to dwa różne światy w jednym przepływie. |
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
3. **Wskaźnik hałasu jako znak firmowy:** analogowy VU-metr ze strefami CALM / UNEASY / HUNTED zamiast paska.
4. **Interfejs psuje się wraz z hałasem:**
   - 0–29%: czysty obraz, lekkie ziarno, panele T2 i T3 wygaszone.
   - 30–59%: ziarno rośnie, winieta się zaciska.
   - 60–100%: czerwona winieta, drżący wskaźnik, pulsująca etykieta HUNTED, EKG przy krytycznym zdrowiu.
5. **Zasady grozy:** (01) szeptać, nie krzyczeć: jeden alert naraz, bez wykrzykników i stingerów na UI; (02) pusty ekran jest straszniejszy: w spokoju tylko zdrowie, amunicja i wskaźnik; (03) obecność na krawędziach (oczy w lesie, sylwetka we mgle), nigdy jump scare w UI; (04) migotanie jest racjonowane: tylko lampa, tytuł i HUNTED, nigdy tekst ciała; (05) czytelność przede wszystkim: 4,5:1 i opcja „Reduce Effects” usuwająca ziarno, migotanie, drżenie ekranu i wskaźnika.
6. **Trzy poziomy HUD:** T1 krytyczne (zdrowie, amunicja, wskaźnik hałasu) zawsze 100%; T2 kontekstowe (cel, sloty, wyposażenie) wygaszane do ok. 55% po 4 s spokoju; T3 tło (podpowiedzi, zegar, XP).
7. **Materiały:** menu pauzy należy do rodziny HUD-u (deska); papier zostaje przy tablicach w kryjówce, szkic tylko w warsztacie.
8. **Ruch:** panel 160 ms (wejście z 8 px), przełączenie zakładki 140 ms, liczniki 400 ms, wszystko 0 ms przy „Reduce Effects”.
9. **Jedna siatka ikon:** dwukolorowe linie wektorowe, wspólne dla perków, przedmiotów i interfejsu.

### Makieta

Płótno z czterema planszami (menu główne interaktywne, HUD z suwakiem hałasu, menu pauzy, system designu): https://claude.ai/artifact/QENgbvLR3gFQvNRNiFSTSR. Strona jest prywatna (widoczna tylko dla właściciela). Makieta nie była renderowana ani oglądana po ostatnich zmianach, więc efekty (ziarno, migotanie) mogą wyglądać inaczej niż zamierzono. Opcja „Reduce Effects” jest w makiecie tylko opisana jako zasada.

## 4. Proponowana kolejność

1. **Fundamenty funkcjonalne:** obsługa pada i nawigacja fokusem, przypisywanie klawiszy, menu główne osobno od lobby, potwierdzenie wyjścia.
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
