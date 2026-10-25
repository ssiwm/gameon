# Zamykanie gry — przyczyny komunikatów o wyciekach i poprawka 1.7.370

Data: 25.10.2026. Projekt: Dead Air ’87, `C:/deadair87/gameon`, Godot 4.7.2, natywny Windows. Zmiany lokalne, bez commita i pushu.

## Wynik

Potwierdzono i naprawiono dwie niezależne przyczyny: osierocony pomocniczy Node2D grozy w headless oraz zbyt późne zakończenie odtwarzania audio. W końcowych 13 przebiegach nie występują komunikaty o pozostawionych RID, instancjach ObjectDB ani zasobach audio. Wcześniejsze określenie całości jako „kosmetyki” było zbyt mocne: jeden węzeł rzeczywiście nie miał właściciela.

Pewność diagnozy: **wysoka dla odtworzonych przypadków**. Wyniki nie dowodzą rosnącego zużycia pamięci podczas całej sesji ani poprawności każdego sterownika audio. Komunikat przy wyjściu oznacza, że obiekt nadal istniał w chwili kontroli sprzątania; system operacyjny odzyskuje pamięć zakończonego procesu.

## 1. CanvasItem / Node2D: osierocone oczy grozy

Przed poprawką `dread.gd` inicjalizował `_eyes := Node2D.new()` przy tworzeniu instancji. `_ready()` w headless kończył się przed `add_child(_eyes)`. Węzeł pozostawał poza drzewem, a zwolnienie skryptu nie zwalnia zwykłego Node przechowywanego w polu.

Oddzielny eksperyment odtworzył dokładnie ten sam identyfikator:

```text
[PROBE] dread eyes=<Node2D#94187292441>
[PROBE] orphan id=94187292441 class=Node2D
Leaked instance: Node2D:94187292441
WARNING: 1 RID of type "CanvasItem" was leaked.
WARNING: 1 ObjectDB instance was leaked at exit.
```

Źródło: `C:/deadair87/reports/shutdown-leaks-2026-10-25/probe-dread.log`. Pierwotne pełne testy warsztatu i broni również pokazywały po jednym Node2D i CanvasItem. To pomocniczy węzeł grozy, a nie element nowego stanowiska broni.

**Kod wdrożony:** [dread.gd](../../prototype/scripts/dread.gd), `_eyes` i `_ready()` (linie 27–40). Pole jest początkowo puste; węzeł powstaje dopiero po sprawdzeniu headless i od razu trafia pod rodzica. Test sprawdza także utworzenie i zwolnienie instancji bez wejścia do drzewa.

## 2. ObjectDB / Ogg / WAV: odtwarzanie zwalniane po końcu drzewa

Oddzielny eksperyment z aktywnym ambientem, muzyką i kliknięciem UI zakończony zwykłym `SceneTree.quit()` pozostawił **22 obiekty ObjectDB i 11 zasobów**. Log identyfikuje `AudioStreamOggVorbis`, `OggPacketSequence`, ich odtwarzanie oraz `AudioStreamWAV` / `AudioStreamPlaybackWAV`. Są to referencje związane z odtwarzaniem audio, nie brakujące pliki graficzne.

Źródło: `probe-none.log` w katalogu raportu. Dotychczasowe `_exit_tree()` zatrzymywało graczy i czyściło referencje, ale następowało to podczas niszczenia drzewa. Po przeniesieniu samego zatrzymania wcześniej test z ponownym uruchomieniem audio nadal pozostawiał **36 obiektów / 13 zasobów** (`shutdown-after.log`, wynik etapu pośredniego).

Samo czekanie na SceneTreeTimer także nie było wystarczające w przyspieszonym headless. Timer skonfigurowany na 300 ms zakończył się po **3,376 ms zegara monotonicznego** (`cabinet-trace.log`). Przebiegi gablot z takim timerem zachowały pełne 50/50 asercji funkcjonalnych, a mimo to pozostawiały zasoby. Wynik PASS testu rozgrywki nie gwarantuje czystego zamknięcia.

**Kod wdrożony:** [audio_director.gd](../../prototype/scripts/audio_director.gd), `quit_game()` (linia 223), `_shutdown()` (248), callback okna (208), blokady pętli (610 / 634) i `set_enabled()` (1157).

`Audio.quit_game(exit_code)`:

1. Przyjmuje pierwsze żądanie i zachowuje jego kod wyjścia; kolejne wywołania nie rozpoczynają następnej procedury.
2. Zatrzymuje audio, usuwa strumienie z odtwarzaczy, zwalnia pętle i czyści cache.
3. Blokuje ponowne włączenie audio oraz zamraża symulację.
4. Daje mikserowi co najmniej **100 ms rzeczywistego czasu**, mierzonego przez `Time.get_ticks_usec()`, przy nadal działających klatkach silnika. FPS podczas kończenia jest ograniczany do 60; ustawienie nie jest zapisywane w preferencjach.
5. Wywołuje zakończenie drzewa z pierwotnym kodem.

`_exit_tree()` pozostaje zabezpieczeniem. `shutdown()` jest idempotentne i nadaje się do zatrzymania audio przed restartem; ponowne użycie wymaga `Audio.set_enabled(true)`. Pętle oraz krótkie dźwięki respektują wyłączenie audio.

## Zakres zmienionego kodu

| Pliki | Zmiana |
|---|---|
| `prototype/scripts/dread.gd` | Leniwe tworzenie pomocniczego węzła z prawidłowym rodzicem. |
| `prototype/scripts/audio_director.gd` | Wspólna procedura wyjścia, callback `close_requested`, rzeczywisty czas sprzątania i blokada nowych głosów. |
| `main.gd`, `main_menu.gd`, `pause_menu.gd` | Dotychczasowe wywołania zakończenia kierowane przez `Audio.quit_game()`. Zachowane istniejące potwierdzenie przycisku Quit. |
| `workshop_test.gd`, `weapon_test.gd`, `cabinet_test.gd`, `enemy_test.gd`, `stalker_test.gd`, `range3d/range_test.gd`, `spike3d/mission3d.gd` | Przekierowanie zakończenia sceny, w tym błędów i testów hosta / klienta. |
| `prototype/tools/workbench_qa.gd` | Ten sam cykl dla rzeczywistego stanowiska oraz wcześniejszych zakończeń z błędem. |
| `prototype/tools/test_shutdown.gd` i `.uid` | Nowa regresja własności węzłów i aktywnego audio. |
| `.github/workflows/tests.yml` | Krok wymagający pełnego podsumowania testu i logu bez błędów / ostrzeżeń. Zdalnego CI jeszcze nie uruchomiono. |
| `prototype/project.godot`, `CHANGELOG.md`, `prototype/README.md`, `prototype/AUDIO.md` | Wersja 1.7.370 i dokumentacja cyklu życia. |
| Poprzedni raport warsztatu | Dopisane rozstrzygnięcie historycznych ostrzeżeń. |

Weryfikator porównał kopie sprzed tego zadania: pozostałe śledzone zmiany zachowane, przekierowania Quit są mechaniczne, wcześniejsza treść dokumentacji zachowana. Istniejące nieśledzone ścieżki nadal obecne. Testy rozgrywki używały izolowanych nazw aplikacji i katalogów userdata. Nie zmieniano ustawień renderera w projekcie ani konfiguracji systemu.

## Końcowa weryfikacja

Poniższe logi pochodzą z końcowej poprawki opartej na zegarze monotonicznym. Kody procesów odczytano z natywnych procesów Godot. Wszystkie przebiegi zakończyły się bez komunikatów o wyciekach i bez błędów skryptów.

| Przebieg | Wynik funkcjonalny | Kod | Czas zamykania | Log |
|---|---|---:|---:|---|
| Warsztat, headless / Dummy | 85/85 | 0 | 107,241 ms | `workshop-after.log` |
| Bronie, headless / Dummy | 379/379 | 0 | 103,890 ms | `weapons-after.log` |
| ENet, host | 12/12 | 0 | 112,717 ms | `net-host-after.log` |
| ENet, klient | 6 PASS i ukończenie operacji warsztatu | 0 | 109,417 ms | `net-client-after.log` |
| Strzelnica | 79/79 | 0 | 112,419 ms | `range-after.log` |
| Gabloty, dwa przebiegi | 50/50 w każdym | 0 / 0 | 104,608 / 104,698 ms | `cabinet-clock-1.log`, `cabinet-clock-2.log` |
| Regresja zamykania, zwykłe wyjście | 10/10 | 0 | 105,388 ms | `shutdown-normal-after.log` |
| Regresja, sygnał zamknięcia okna | 10/10 | 0 | 106,575 ms | `shutdown-window-after.log` |
| Regresja, zachowanie kodu 7 | 10/10 | 7 | 106,213 ms | `shutdown-code7-after.log` |
| Regresja, pauza i time_scale=0 | 10/10 | 7 | 106,212 ms | `shutdown-paused-after.log` |
| Natywne okno, D3D12 Forward+ / WASAPI, sygnał zamknięcia | 10/10 | 0 | 103,988 ms | `shutdown-native-d3d12.log` |
| Rzeczywisty warsztat, montaż, PL, D3D12 Forward+ / WASAPI | `layout_ok=true`, PNG 1280×720 | 0 | 103,280 ms | `workbench-after.log`, `shutdown-workbench.json` |

Test zamknięcia okna emituje `close_requested` i sprawdza podłączony callback; nie automatyzuje fizycznego naciśnięcia Alt+F4. Audio w regresji jest faktycznie uruchamiane, zatrzymywane i ponownie uruchamiane. Sprawdzane są puste pętle i cache, zatrzymanie odtwarzaczy, brak ich strumieni oraz brak nowych osieroconych węzłów. Import projektu i `git diff --check` zakończone kodem 0.

Artefakty: [final-validation.json](C:/deadair87/reports/shutdown-leaks-2026-10-25/final-validation.json), [verify_final.py](C:/deadair87/reports/shutdown-leaks-2026-10-25/verify_final.py). Katalog zawiera także logi wcześniejszych, nieudanych wariantów; nie są one końcowym wynikiem. Weryfikator wybiera jawnie 13 końcowych przebiegów.

## Osobne komunikaty i ograniczenia

Natywny test rzeczywistej kryjówki na D3D12 zgłasza konwersję tekstur **RGB8 do RGBA8** w `char3d.gd:633`. To ostrzeżenie zgodności formatu z urządzeniem, nie komunikat o wycieku. Nie zmieniano kodu wyglądu postaci w tym zadaniu.

Wcześniejszy natywny przebieg Vulkan zgłosił brak pliku warstwy Epic Online Services:
`C:/Program Files (x86)/Epic Games/Epic Online Services/managedArtifacts/98bc04bc842e4906993fd6d6644ffb8d/EOSOverlayVkLayer-Win64.json`.
Plik faktycznie nie istnieje. Jest to osobny problem konfiguracji lokalnej warstwy Vulkan. Końcowe testy natywne używały opcji CLI `--rendering-driver d3d12 --rendering-method forward_plus`, zachowując WASAPI i renderer Forward+. Nie edytowano instalacji ani rejestru systemowego.

100 ms jest zweryfikowanym czasem opróżnienia w tych konfiguracjach, nie potwierdzeniem zakończenia miksu przez API ani gwarancją dla wszystkich urządzeń. Bezpośredni `SceneTree.quit()` w zewnętrznym narzędziu, wymuszone zatrzymanie procesu lub silnikowe `--quit-after` mogą pominąć wspólną procedurę. Narzędzia grające audio powinny kończyć przez `root.get_node("Audio").quit_game(code)`. Zdalny Linux CI i pozostałe sterowniki nie były uruchamiane w tym zadaniu.

Następny krok: uruchomić dodany krok CI po publikacji zmian oraz sprawdzić zwykłe zamknięcie w docelowym buildzie. Lokalna poprawka i opisane testy są ukończone.

## Integracja z aktualnym main

Przed publikacją PR połączono zmiany z `main` w wersji 1.7.384; wspólny numer publikacji to **1.7.385**. Numery 1.7.369 / 1.7.370 w historycznych logach i zrzutach identyfikują wcześniejsze lokalne przebiegi. Zachowano aktualne sterowanie (`inspect_weapon`, domyślnie H), kalibrację jasności i nowsze modele. Test `tools/test_input_bindings.gd` z main również uruchamia audio; jego zakończenie skierowano przez `Audio.quit_game()`. Powtórzony test: **100/100**, kod 0, bez pozostawionych zasobów. Kolejne wyniki integracji są w [raporcie PR](2026-10-25-pr-integration.md).
