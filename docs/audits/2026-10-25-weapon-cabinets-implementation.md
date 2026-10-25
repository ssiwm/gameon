# Weryfikacja implementacji gablot — 1.7.379

Data: 2026-10-25. Projekt: Dead Air ’87, Godot 4.7.2, symulacja 2D i obraz 3D. Weryfikacja kodu, rzeczywistej sceny kryjówki, dwóch procesów ENet oraz obrazu Forward+ / Vulkan na RTX 3080. **Pewność: wysoka w sprawdzonym zakresie lokalnym i ENet localhost.**

## Wynik

Cztery usterki z audytu zostały poprawione: podniesienie porzuconej broni nie daje kolejnego przydziału nabojów; klient nie tworzy broni przez deklarowane porzucenie; wszystkie rzędy gabloty mają wspólny zasięg; porównanie używa rzeczywistej amunicji i części. Dodano jawny wybór zastępowanego slotu, przyciski myszy, akcje pada, stan wydania wspólnego egzemplarza i snapshot dołączających. Odmowa blokady zachowuje inspekcję.

Końcowe logi sprawdzonych zestawów nie zawierają `SCRIPT ERROR`, `Parse Error` ani nieudanych asercji. `git diff --check` i kontrola składni nowego skryptu Bash zakończyły się poprawnie. Testy dodano do konfiguracji CI. Wyniki poniżej pochodzą z lokalnej walidacji; zdalny CI jest osobną weryfikacją PR.

## Zmiany potwierdzone w kodzie

| Zakres | Stan i implementacja | Źródło |
|---|---|---|
| Przydział amunicji | Zaimplementowane: mapowe egzemplarze i nowy łup mają jawne `rounds`; wymieniana broń ma 0. Podniesienie odczytuje wartość przedmiotu | [level.gd](../../prototype/scripts/level.gd#L964), `_add_map_item`, `spawn_item`, `_weapon_pickup_server` |
| Wymiana na serwerze | Zaimplementowane: walidacja przedmiotu, slotu, blokady, życia i zasięgu; serwer tworzy stary egzemplarz z zatwierdzonego zestawu. `_drop_rpc` nie tworzy przedmiotów | [level.gd](../../prototype/scripts/level.gd#L1444), `_weapon_pickup_server`, `server_weapon_kit` |
| Magazynek i docelowy slot | Zaimplementowane: zwrot starego magazynka z właściwym typem naboju; klient otrzymuje slot wybrany przy pobraniu | [weapon_controller.gd](../../prototype/scripts/weapon_controller.gd#L1704), `grant_weapon` |
| Zasięg gabloty | Zaimplementowane: jeden punkt interakcji dla wszystkich rzędów, używany do wyszukiwania i kontroli zasięgu | [cabinet.gd](../../prototype/scripts/cabinet.gd#L16), `interaction_point`, [pickup.gd](../../prototype/scripts/pickup.gd#L459), `in_reach`, `level.weapon_item_near` |
| Stan wspólnego egzemplarza | Zaimplementowane w pamięci bieżącej mapy: dostępny / zablokowany / wydany, etykieta odbiorcy; dołączający nie odtwarza wydanej broni | [level.gd](../../prototype/scripts/level.gd#L1517), `_cabinet_state_rpc`, `cabinet_rows`, `send_cabinets_to`; `main._on_peer_connected` |
| Lifecycle zestawu | Zaimplementowane: rejestr zachowuje carry i resetuje spawn, wipe oraz poprawnie rozpoczętą karę porwania; rozłączenie usuwa wpis peera | [main.gd](../../prototype/scripts/main.gd#L192), `_restart_mission`, `_spawn_player`, `_on_peer_disconnected`; [player.gd](../../prototype/scripts/player.gd#L1888), `deliver_devour` |
| Obsługa inspekcji | Zaimplementowane: wybór rzędu i slotu, akcje pada, przyciski myszy, zachowanie panelu przy blokadzie | [weapon_controller.gd](../../prototype/scripts/weapon_controller.gd#L1548), `_tick_inspect`, `select_cabinet_slot`, `_try_pickup`; `weapon_inspect._select_target`, `_take_selected` |
| Porównanie i czytelność | Zaimplementowane: rzeczywisty nabój i części; nowa broń porównywana z zastępowanym slotem, znana broń z aktualnie trzymaną. Większe teksty i przewijane szczegóły, przycisk pobrania poza przewijaniem | [weapon_inspect.gd](../../prototype/scripts/weapon_inspect.gd#L191), `show_weapon`, `_fill`, `_process`; `hud._drive_cards` |
| Obraz i tłumaczenia | Zaimplementowane: słabsze dodatkowe światło gabloty, bez budowania niewidocznego drugiego modelu; polskie nowe komunikaty. Poprawiono wybór rzędu w dev `--shotinspect=N`; zachowano istniejącą ochronę przed powtórnym łączeniem sygnałów przycisków | `view3d.gd`, `weapon_inspect.gd`, `main.gd`, `translations/ui.csv`, `ui.pl.translation` |
| Dekoracje i drzwi | Dotychczasowa dekoracja 3D: dolny pistolet, magazynki i skrzynka nie są dodatkowym wyposażeniem. Animacja otwarcia pozostaje lokalna | `view3d._build_cabinet`, `_sync_cabinets` |

Gabloty nadal wydają wspólne egzemplarze. Pobranie znanej broni daje tylko amunicję i usuwa wspólny egzemplarz; liczba przyjętych nabojów zależy od pojemności puli. Ekspozycja pokazuje model fabryczny, a panel objaśnia montaż gracza po pobraniu. Stan wydania jest stanem bieżącej mapy, nie osobnym trwałym magazynem.

## Weryfikacja

Testy uruchamiano z odrębnym `APPDATA`, bez używania profilu gracza. Nowa próba sieciowa potwierdza odbiór replikowanej pozycji na hoście przed żądaniem; w scenariuszu fałszywego zestawu potwierdza także, że host rzeczywiście widzi sfałszowane dane. Bilans broni izoluje automatycznie zbierane skrzynki amunicji.

| Zestaw | Wynik | Dowód |
|---|---|---|
| Gabloty, rzeczywista kryjówka | **50/50** | `pr-cabinets/dead_air_weapon_tests/cabinet.log` |
| Gabloty ENet — host | **17/17** | `pr-cabinets/dead_air_weapon_tests/cabinet_host.log` |
| Gabloty ENet — klient | **17/17** | `pr-cabinets/dead_air_weapon_tests/cabinet_client.log` |
| Dotychczasowe bronie | **379/379** | `pr-weapons/dead_air_weapon_tests/unit.log` |
| Warsztat | **52/52** | `pr-workshop.log` |
| Strzelnica | **79/79** | `pr-range.log` |
| Dotychczasowe bronie ENet | **Host 13/13**, klient zakończył asercje bez błędów | `pr-weapons/dead_air_weapon_tests/net_host.log`, `pr-weapons/dead_air_weapon_tests/net_client.log` |
| Przejścia kampanii i zachowanie wyposażenia | **PASS, 0 błędów** | `pr-generation.log`, `--gentest` |
| Sterowanie po połączeniu z main | **100/100** | `pr-controls.log`, `tools/test_input_bindings.gd` |
| Import zasobów | **Kod 0**, wygenerowane tłumaczenie i UID testu | `pr-import.log` |
| Widok 3D | Panel mieści się na ekranie; sprawdzono wersje EN i PL, blokadę oraz sloty | [EN](images/weapon-cabinet-1.7.379-en.png), [PL](images/weapon-cabinet-1.7.379-pl.png) |

Nowe scenariusze znajdują się w [cabinet_test.gd](../../prototype/scripts/cabinet_test.gd) i [test_cabinets.sh](../../prototype/tools/test_cabinets.sh); krok dodano do [.github/workflows/tests.yml](../../.github/workflows/tests.yml). Aktualizacje dokumentacji: `README.md`, `WEAPONS.md`, `GDD.md`, `CHANGELOG.md`. Wersja gry: `prototype/project.godot`, **1.7.379**.

## Ryzyka i granice potwierdzenia

- Host i klienci wymagają tej samej wersji — RPC podniesienia/przyznania otrzymały parametr docelowego slotu.
- Serwerowy rejestr zabezpiecza zamianę. Replikowana pozycja, pełna walidacja magazynka i wyposażenia przy strzale nadal należą do dotychczasowego modelu kooperacyjnego; zmiana nie stanowi pełnego systemu przeciw oszustwom.
- Próby pada używały akcji wejścia; nie wykonano testu fizycznego kontrolera, WAN ani Steam relay. Następny krok: krótki playtest dwóch osób na tej samej wersji, z równoczesnym pobraniem i dołączeniem w trakcie sesji.
- Headless przy zamknięciu nadal zgłasza ostrzeżenia RID/ObjectDB i czasem zasoby w użyciu, obecne także w zestawach bazowych. Brak błędów GDScript nie jest potwierdzeniem braku wszystkich wycieków silnika.

Wersja 1.7.379 opiera się na aktualnym main (1.7.378). Oględziny używają osobnej akcji `inspect_weapon`, domyślnie H; F pozostaje flarą. Polecenia odtworzenia: `godot --headless --path prototype -- --host --cabinettest --autoquit=40` i `bash prototype/tools/test_cabinets.sh`. Nazwy logów w tabeli odnoszą się do lokalnej sesji walidacyjnej. Przy niepowodzeniu CI udostępnia logi w artefaktach testów broni.
