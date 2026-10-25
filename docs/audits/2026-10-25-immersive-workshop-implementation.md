# Immersyjny warsztat broni — wdrożenie 1.7.369

Data: 25.10.2026. Repozytorium: `C:\deadair87\gameon`, gałąź `fix/weapon-workshop-flow`, HEAD `657b8fb` plus bieżące zmiany robocze. Implementacja została wykonana po weryfikacji planu. Godot 4.7.2, natywny Windows, RTX 3080, renderer aktualnego projektu: **Forward+**.

## Wynik i zakres

**Zaimplementowane w kodzie gry:** nowa ława ARMS dla wszystkich 12 broni, duży rzeczywisty model na macie 3D, taca aktywnej części, numerowane gniazda powiązane z geometrią, wybór przez powierzchnię modelu, stojak noszonej broni / pełna zbrojownia, papierowa karta konfiguracji, jawne oględziny i podgląd, korzyści / kompromisy, pełne parametry, lokalna prezentacja zatwierdzonego montażu i dostępność bez myszy.

**Zaimplementowane wcześniej i wykorzystane:** części i ich modele, ceny i wspólne odblokowania Scrap, osobisty montaż Profile, presety, aktualna amunicja, rozliczanie magazynka i wymagania stanowisk. Nowy panel jest warstwą prezentacji. Nie powstał drugi kalkulator statystyk ani nowy system ekonomii.

**Niezweryfikowane ręcznie:** czas odnalezienia pierwszej wymiany przez nowego gracza (cel planu: poniżej 10 s), wygoda fizycznego pada, komfort dłuższej sesji, wydajność na słabszym sprzęcie, WAN / Steam. Testy wejścia używają zarejestrowanych akcji klawiatury, przycisków pada i osi; nie zastępują oceny ergonomii.

## Pliki i konkretne mechanizmy

| Pliki | Wdrożenie |
|---|---|
| [gunsmith_panel.gd](/C:/deadair87/gameon/prototype/scripts/gunsmith_panel.gd:175) i `.gd.uid` | Nowy panel otrzymuje dane od WorkshopUI i emituje wybory. `present`, `_present_rack`, `_present_slots`, `_present_parts`, `_present_summary`. Papierowa karta, limit czterech głównych zmian, pełne szczegóły i przewijanie. |
| [gun_stage.gd](/C:/deadair87/gameon/prototype/scripts/gun_stage.gd:278) | Tryb ławy, proceduralny stół / mata / narzędzia i fizyczna taca. `slot_at`, `slot_screen_position`, `animate_mount`, `cancel_mount`, `stable_bounds`, `_fit_viewport`. Dotychczasowy kompaktowy tryb pozostaje domyślny. |
| [workshop_ui.gd](/C:/deadair87/gameon/prototype/scripts/workshop_ui.gd:1733) | Kompozycja ARMS, neutralny wybór, pełna konfiguracja i aktualna amunicja, kontekst żądania, reakcja na wynik, zachowanie przy zamknięciu / zmianie wyboru / utracie połączenia. `_present_committed`, `_present_bench`, `_comparison_rows`. |
| [actions.gd](/C:/deadair87/gameon/prototype/scripts/actions.gd:78) | Akcje oględzin, pełnej karty i przewijania. Podpowiedzi pobierają nazwy z rejestru; nie są niezależnymi deklaracjami sterowania. |
| [workshop_test.gd](/C:/deadair87/gameon/prototype/scripts/workshop_test.gd:311) | Regresje danych, operacji i rzeczywistych węzłów panelu, przycisków, geometrii, obrotu, wszystkich konfiguracji i spóźnionych odpowiedzi. |
| [weapon_test.gd](/C:/deadair87/gameon/prototype/scripts/weapon_test.gd) | Test klienta kupuje część przez nowy panel i wymaga oczekiwania przed odpowiedzią. Host sprawdza także zachowanie własnego montażu. |
| [workbench_qa.gd](/C:/deadair87/gameon/prototype/tools/workbench_qa.gd) i `.gd.uid` | Render rzeczywistej kryjówki, PNG + JSON, kontrola granic panelu, warianty języka / skali / części / montażu oraz pomiar prezentacji. Profile i Scrap mają wyłączony zapis. |
| `prototype/translations/ui.csv`, `ui.pl.translation` | Nowe teksty EN / PL oraz import tłumaczenia. Dotychczasowe wiersze CSV zachowane. |
| `prototype/project.godot`, `CHANGELOG.md`, `prototype/README.md`, `prototype/WEAPONS.md` | Wersja 1.7.369, dokumentacja sterowania, prezentacji i QA. Pozostała konfiguracja projektu zachowana. |

## Przebieg operacji i zgodność z symulacją

Otwarcie ARMS i oględziny ustawiają `_opt = -1`: model pokazuje aktualny montaż. Fabryczny podzespół jest jawną opcją. Podgląd wariantu pracuje na kopii kompletnej konfiguracji, zachowuje inne gniazda i rodzaj załadowanego naboju. Karta korzysta z `Weapons.def_build`, danych części i aktualnego kontrolera gracza.

Przed `Scrap.request_part` zapisywany jest `_pending_part`: ID, broń, kod montażu sprzed żądania, sesja i rewizja wyboru. Jest to konieczne także przy bezpośredniej, synchronicznej odpowiedzi hosta. Drugie działanie jest blokowane. `Scrap._part_done` montuje zakup kupującemu przed sygnałem `part_result`; dopiero jego zgodny wynik uruchamia prezentację. Montaż posiadanej części i zestawu nadal przechodzi przez Profile.

`GunStage.animate_mount` pokazuje demontaż, odłożenie starego podzespołu na tacę i osadzenie nowego przez 0,8 s. Korzysta ze zrzutu konfiguracji sprzed operacji. Nie zapisuje profilu, nie pobiera złomu i nie przelicza nabojów na końcu. W testach headless nie uruchamia dodatkowych dźwięków montażu. W grze wykorzystuje istniejące próbki mechaniczne.

Zamknięcie panelu, zmiana broni / wariantu, ukrycie zakładki i utrata połączenia sprzątają efekt. Przyjęty zakup pozostaje zatwierdzony; spóźniony wynik nie animuje nowo oglądanej broni ani ponownie otwartej sesji. Po otwarciu odczytywany jest prawdziwy stan. Strony zaopatrzenia i pozostałe stanowiska zachowują dotychczasowe zasady.

Karta podpisuje korzyści i kompromisy także tekstem. Pełne parametry obejmują pola faktycznie modyfikowane przez części danej broni, w tym błysk, naprowadzanie, działanie pocisków i broń białą. Długości z symulacji przeliczane są przez 16 px/m; hałas pozostaje współczynnikiem. Zużycie, temperatura, wprawa i sytuacja strzału pozostają w kontrolerze. Modyfikacje bez zewnętrznego modelu mają opis działania wewnętrznego i kotwicę korpusu.

## Model, układ i sterowanie

Kotwice i wybór powierzchni pochodzą z rzeczywistych mesh, montowanych części i metadanych `hides`. Etykiety są przeliczane po obrocie i rozdzielane w dwóch pasach. Krótkie kliknięcie wybiera gniazdo; ruch ponad próg oddziela obrót od kliknięcia. Przy obrocie broń unosi się nad matę. Kadr jest wspólny dla kompatybilnych części, z uwzględnieniem par lufa + wylot. Podświetlenie gniazda nie przebudowuje modelu.

Scena pozostaje nieruchoma w oględzinach. Ograniczenie ruchu wyłącza wysuwanie części, ruch kamery i montaż; stan startowy pochodzi z ustawienia reduce_fx. Ukryte viewporty mają `UPDATE_DISABLED`. Bufor renderu dopasowuje się do faktycznych pikseli ekranu i zachowuje proporcje przy ograniczeniu rozdzielczości.

Panel respektuje bazowe 640×360 oraz skalowanie HUD. Koszt i główne działanie pozostają poza przewijaną treścią. Kontrola natywna objęła 1280×720 i 1920×1080, EN / PL, większą skalę UI, strzelbę, maczetę, konfigurację z kilkoma częściami i montaż.

| Czynność | Klawiatura / mysz | Pad |
|---|---|---|
| Broń | W/S, strzałki góra/dół, stojak | D-pad góra/dół |
| Gniazdo | A/D, strzałki lewo/prawo, powierzchnia / numer / przycisk | D-pad lewo/prawo |
| Wariant | 1 / 2 lub karta części | X / Y |
| Zakup / montaż | Enter lub główny przycisk | A |
| Oględziny | C | R3 |
| Pełna karta | V | Back |
| Przewijanie karty | PageUp / PageDown, kółko | Oś pionowa prawego drążka |
| Wybór zapisu / zapis aktualnego zestawu | R lub przycisk | L3 |
| Zakładki / zamknięcie | Tab / Esc | RB / LB / B |

## Walidacja

| Kontrola | Wynik |
|---|---|
| Import i parser Godot | Kod wyjścia 0; brak SCRIPT ERROR / Parse Error |
| Warsztat EN | **85/85**, kod wyjścia 0 |
| Warsztat PL | **85/85**, kod wyjścia 0 |
| Pełna regresja broni | **379/379**, kod wyjścia 0 |
| Dwa procesy ENet | Host **12/12**, klient 5 kontroli PASS i poprawne zakończenie, oba kody wyjścia 0 |
| Strzelnica podczas wdrożenia | **79/79**, kod wyjścia 0 |
| Natywne rendery | PNG zapisane, granice panelu i głównej akcji wewnątrz viewportu; Forward+, bez błędów stderr w końcowych renderach |
| Diff / zachowanie wcześniejszych zmian | `git diff --check` 0; wcześniejsze patche innych plików i oryginalna treść wspólnych dokumentów / CSV zachowane |

Regresje obejmują wszystkie 12 modeli, gniazda, obwiednie każdej kombinacji modelowanych części, dodatkowe efekty na pełnej karcie, uniesienie nad blat, kliknięcia, klawiaturę / pad, ograniczony ruch, odmowę serwera, zakup, duplikaty, stare odpowiedzi, zamknięcie i presety. Poprawiono istniejący błąd odroczonego `ensure_control_visible`: funkcja wyszukuje aktualny wiersz i sprawdza jego przodka, zamiast przechowywać usuniętą kontrolkę.

Testy wykorzystują osobne aplikacje `DeadAirAudit-20261025-workshop` / `...-weapons` w `C:\deadair87\reports\weapon-workshop-verification-2026-10-25`. Zasoby są junctionami do aktualnego checkoutu, a userdata jest odrębne. Nie są to kopie starego kodu. Końcowe testy wymuszają osobno locale=0 (EN) i locale=1 (PL), bez równoległego narzędzia renderu zapisującego ustawienia tej aplikacji. Poprzednia zawartość odizolowanych ustawień jest przywracana; wejścia językowe i kody wyjścia zapisano w `locale-test-inputs.json`.

Logi i dane: [katalog wyników](/C:/deadair87/reports/weapon-workshop-implementation-2026-10-25), [walidacja JSON](/C:/deadair87/reports/weapon-workshop-implementation-2026-10-25/final-validation.json), [zachowanie checkoutu](/C:/deadair87/reports/weapon-workshop-implementation-2026-10-25/checkout-verification.json). Dane bazowe i weryfikacja planu: [poprzedni raport](/C:/deadair87/reports/weapon-workshop-verification-2026-10-25/weryfikacja-planu.md).

## Wydajność i ograniczenia

Pomiar lokalny: dwa oddzielne 4-sekundowe przebiegi, 1280×720, EN, fabryczna M-83, RTX 3080 / Forward+. Poprzedni WorkshopUI ładowano ze zrzutu sprzed wdrożenia; pozostały kod i scena były wspólne. To krótka próba prezentacji, nie reprezentatywny benchmark gry.

| Metryka | Poprzedni panel | Nowa ława |
|---|---:|---:|
| Viewport broni | 257×72 | 866×387 |
| Średni GPU viewportu broni | 0,098 ms | 0,287 ms |
| Średni GPU sumy mierzonych viewportów | 5,218 ms | 5,517 ms |
| Średni CPU przygotowania / renderu | 1,325 ms | 1,401 ms |
| Całkowite draw calls w próbce | 464 | 393 |
| Średni czas klatki / p95 | 17,346 / 19,384 ms | 18,310 / 19,907 ms |
| Maksimum czasu klatki | 106,114 ms | 218,259 ms |

Większy podgląd kosztował w tej próbie około +0,189 ms GPU sceny broni. Próbki zawierają duże pojedyncze skoki czasu klatki; nie pozwalają zadeklarować stałego FPS ani braku regresji na słabszej karcie. Renderery pełnej gry inne niż obecny Forward+ wymagają osobnej weryfikacji: wymuszony Compatibility ujawnił istniejące ograniczenia efektów świata (fog / SSIL), więc nie jest potwierdzeniem obsługi pełnej gry w GL.

Przy kończeniu testów headless nadal występują komunikaty o CanvasItem / ObjectDB i zasobach. Ten rodzaj komunikatów był obecny przed wdrożeniem. W końcowych przebiegach warsztatu EN i PL: 1 CanvasItem i 1 ObjectDB; bronie oraz klient ENet: 33 ObjectDB i 16 zasobów. Liczby w kolejnych przebiegach warsztatu różniły się przy zamykaniu. Bazowy klient miał mniejszy ślad, a nowy fixture otwiera i zamyka panel. Nie traktować wszystkich stderr jako czystych ani twierdzić, że usunięto globalne wycieki. Oddzielne zwolnienie panelu po zmianach wariantów nie zgłosiło wycieku; diagnostyka verbose wskazywała także zasoby audio. Pełne ustalenie i naprawa globalnego shutdown pozostają osobnym zadaniem. Pewność wysoka dla wyników testów i obecności komunikatów, średnia dla wszystkich ich przyczyn.

Następny zalecany krok odbioru: krótki playtest nowego gracza, fizyczny pad i słabsza karta. Nie wymaga to dalszego projektowania systemu upgrade’u; sprawdza czytelność i komfort już działającej implementacji.

## Rzeczywisty render

![M-83, polski podgląd bębna, 1280×720](C:/deadair87/gameon/docs/audits/images/weapon-workbench-pl-1.7.369.png)

![Pełne parametry strzelby, PL, większe UI i podpowiedzi pada](C:/deadair87/gameon/docs/audits/images/weapon-workbench-pad-1.7.369.png)

![Zatwierdzony montaż bębna, 1920×1080](C:/deadair87/gameon/docs/audits/images/weapon-workbench-mount-1.7.369.png)

## Uzupełnienie: zamykanie gry 1.7.370

Komunikaty o pozostawionych obiektach z przebiegów 1.7.369 powyżej są historycznymi wynikami. Ustalono przyczyny i dodano poprawki: leniwe tworzenie pomocniczego węzła grozy oraz wcześniejsze zatrzymanie i opróżnienie audio przez wspólną ścieżkę wyjścia. Szczegółowa diagnoza, powtórzone testy i ograniczenia: [raport zamykania](/C:/deadair87/gameon/docs/audits/2026-10-25-shutdown-leaks.md).
