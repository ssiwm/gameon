# Audyt ulepszania broni i stanowisk — Dead Air ’87

Data: 2026-10-24. Repozytorium: `ssiwm/gameon`. Wersja gry: 1.7.366.
Zakres: części, montaż, zestawy, waluty, stanowiska, wpływ konfiguracji na broń, sieć i istniejące testy.
Raport wyjściowy sprzed wdrożenia. Aktualne zmiany i walidację opisuje [raport wdrożenia](2026-10-24-weapon-upgrades-implementation.md).

## Wniosek

System jest zaimplementowany i ma szerokie pokrycie istniejącymi testami. Ulepszanie polega na wyborze części w gniazdach, a nie na trzech kolejnych poziomach mocy. Najbliższe usprawnienia powinny zapewnić spójność stanu magazynków, walidację operacji na serwerze oraz czytelny wybór i porównanie konfiguracji.

Dwa problemy wymagają poprawki przed szerszym testowaniem kooperacji: operacje warsztatu nie sprawdzają miejsca gracza na serwerze, a montaż mniejszego magazynka nie przelicza już załadowanych nabojów. To ustalenia z analizy kodu; obecny zestaw testów nie dowodzi poprawności tych przypadków.

Pewność: wysoka dla struktury kodu i zachowania istniejących testów; średnia dla przewidywanego wpływu UX; niska dla balansu i zachowań graczy z zewnątrz.

## 1. Co jest zaimplementowane

### Katalog i sposób konfiguracji

- 12 broni, 51 części, 38 gniazd. 13 gniazd oferuje dwie części poza opcją fabryczną; pozostałe 25 — jedną.
- FALCON-6 i SINEW-6 mają kod i części, lecz `Scrap.LATER` blokuje dostęp w obecnej kampanii. Po ich odjęciu: 10 broni, 45 części, 32 gniazda, w tym 13 z alternatywami.
- Źródło danych: [parts.gd](../../prototype/scripts/parts.gd#L24), [weapons.gd](../../prototype/scripts/weapons.gd#L29), [scrap.gd](../../prototype/scripts/scrap.gd#L60).
- Odblokowania i bank są wspólne dla drużyny i zapisują się u hosta w `user://progress.cfg`. Montaż oraz trzy zestawy na broń są prywatne i zapisują się w `user://profile.cfg`.
- `Parts.encode/decode/apply` i `Weapons.def_build` przekładają części oraz typ naboju na parametry broni. To logika rozgrywki, nie same opisy UI.
- Serwer usuwa nieposiadane części przez `Parts.sanitize`: zarówno w żądaniu strzału, jak i w `server_def` dla ognia ciągłego i walki wręcz — [weapon_controller.gd](../../prototype/scripts/weapon_controller.gd#L243), [parts.gd](../../prototype/scripts/parts.gd#L283).
- Części wpływają m.in. na pojemność, przeładowanie, hałas, celność, podrzut, masę, grzanie, przebicie, zasięg i ogień na podłożu. Wprawa, zabrudzenie, zużycie lufy/sprężyn i ostrość broni białej tworzą dodatkowe warstwy.
- Masa całego ekwipunku zmienia bieg i jego hałas w trybie REALISTIC. CLASSIC wyłącza ten koszt; `Weapon reliability = OFF` wyłącza zużycie i zacięcia. Nie trzeba ponownie wdrażać tych rekomendacji ze starszych planów.

| Broń | Części | Gniazda | Gniazda z dwiema częściami |
|---|---:|---:|---:|
| M-83 | 7 | 4 | 3 |
| P-83, klucz techniczny `p64` | 5 | 4 | 1 |
| SPREAD-12 | 5 | 3 | 2 |
| PELLET-8 | 5 | 4 | 1 |
| LR-7 | 4 | 3 | 1 |
| HKM-9 | 4 | 3 | 1 |
| WRATH-4 | 4 | 3 | 1 |
| SPECTER-1 | 4 | 3 | 1 |
| FALCON-6, zablokowany | 3 | 3 | 0 |
| SINEW-6, zablokowany | 3 | 3 | 0 |
| Maczeta | 4 | 3 | 1 |
| Kilof | 3 | 2 | 1 |

Jedna część plus element fabryczny nadal może być sensownym wyborem. Samo liczenie alternatyw nie dowodzi, że gniazdo jest źle zbalansowane. Walidator sprawdza istnienie kosztu części, z jawnym wyjątkiem dla dławika SPREAD-12, ale nie mierzy, czy ten koszt jest odczuwalny.

### Drogi zdobywania i koszt

1. Zwykła część: zakup za złom albo znajdźka zabezpieczana dopiero przy ekstrakcji.
2. Części broni specjalnych: badanie za 1–3 próbki i około połowę katalogowej ceny w złomie → udana misja daje schemat → tokarka za około ćwierć ceny → kolejna udana misja daje część → montaż na ławie.
3. Badanie i tokarka mają po jednym wspólnym miejscu w kolejce. Dla jednej części standardowa ścieżka wymaga dwóch udanych misji od rozpoczęcia badania. Znajdźka może ją skrócić.
4. Prasa i amunicja 40 mm z pirotechniki: zamówienie partii, wspólna kolejka do trzech partii, dostawa po udanej misji. Granaty, miny i narzędzia kupuje się od ręki.
5. Koszty liczą `part_cost`, `research_cost`, `machine_price` i `press_price`; perk Smith obniża zakup zwykłych części. Nie należy traktować sumy katalogowych cen jako rzeczywistego kosztu wszystkich odblokowań.

Przykład: `lr7_lens` ma cenę katalogową 265, badanie kosztuje 3 próbki + 135 złomu, tokarka 65 złomu; razem 200 złomu, próbki i dwie udane misje.

Źródło: [scrap.gd](../../prototype/scripts/scrap.gd#L367), `bank_loot`, `pick_find`, `_research_server`, `_machining_server`, `_order_server`.

## 2. Aktualne stanowiska

Wszystkie siedem stanowisk ma znacznik w mapie, tworzenie węzła, interakcję, tryb panelu i plik głównego modelu 3D. Potwierdzono ich logikę; nie wykonano oceny wizualnej kadru, czytelności ani wygody dojścia.

Pozycje to indeksy kolumn mapy liczone od zera. „Środek/góra/dół” odnoszą się do trzech poziomów kryjówki.

| Stanowisko | Miejsce | Faktyczna funkcja | Status i źródło |
|---|---|---|---|
| Ława rusznikarska | Środek, kol. 20 | Zakup broni i zwykłych części, montaż, trzy zestawy, narzędzia | Implementacja: [workshop.gd](../../prototype/scripts/workshop.gd#L44), tryb `bench` |
| Stół konserwacji | Środek, kol. 16 | Czyszczenie za czas; wymiana lufy za 40 złomu i sprężyn za 20 | Implementacja: [service_bench.gd](../../prototype/scripts/service_bench.gd#L40), `service` |
| Szafki osobiste | Środek, kol. 37 | Perki oraz wygląd; zestawy broni pozostają na ławie/strzelnicy | Implementacja: [locker_station.gd](../../prototype/scripts/locker_station.gd), `locker` |
| Prasa elaboracyjna | Dół, kol. 33 | Zamówienia amunicji specjalnej poza 40 mm | Implementacja: [press_bench.gd](../../prototype/scripts/press_bench.gd#L40), `press` |
| Stół pirotechniczny | Dół, kol. 46 | Granaty, miny, ładunki, zamówienia 40 mm, wspólny wybór zapalników | Implementacja: [pyro_bench.gd](../../prototype/scripts/pyro_bench.gd), `pyro` |
| Pracownia elektroniki i próbek | Góra, kol. 45 | Badanie części broni specjalnych za próbki i złom; wynik to schemat | Implementacja: [lab_bench.gd](../../prototype/scripts/lab_bench.gd), `lab` |
| Tokarka i szlifierka | Dół, kol. 11 | Wytwarzanie części ze schematów oraz ostrzenie maczety/kilofa za czas | Implementacja: [lathe_bench.gd](../../prototype/scripts/lathe_bench.gd), `lathe` |
| Zbrojownia | Środek, gabloty kol. 48 i 51 | Pobieranie/wymiana odblokowanej broni; nie jest kolejnym etapem ulepszania | Implementacja: `cabinet.gd`, [z1_hub.gd](../../prototype/scripts/maps/z1_hub.gd#L22) |
| Strzelnica FPP | Dół, drzwi kol. 54 | Próba broni i niekupionych części, zestawy, tarcze/rekordy; przy wyjściu przywraca ekwipunek wejściowy | Implementacja: [fp_mode.gd](../../prototype/scripts/range3d/fp_mode.gd), `range_snapshot/range_restore` |

Mapowanie panelu: [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L259).
Tworzenie stanowisk: [level.gd](../../prototype/scripts/level.gd#L719).

### Ograniczony zakres i roadmapa

- Prasa i pirotechnika realizują zakupy/zlecenia gotowych pozycji, nie pełny crafting z prochu, łusek, spłonek i komponentów.
- Pracownia realizuje badania; opisy ładowania ogniw i chronografu z pierwotnego planu nie są potwierdzeniem takich funkcji w obecnych stanowiskach.
- Trzy zestawy już istnieją. Ich opis powstaje z listy części; edytowane przez użytkownika nazwy pozostają na później.
- Szpital, wyzwania tygodniowe i osiągnięcia są poza obecnym zakresem EA według GDD §16.0a.
- Starszy audyt w WORKSHOP_PLAN dotyczył wcześniejszego katalogu i sesji deweloperskich. Nie jest aktualnym pomiarem balansu ani reprezentatywnym badaniem użytkowników.

## 3. Problemy i rekomendacje

### P1 — montaż mniejszego magazynka nie przelicza załadowanych nabojów

Dowód: `Profile.set_fit/load_preset` aktualizują konfigurację; `Player._sync_perks` publikuje `fits`. Nie wywołują przeliczenia `WeaponController.mags`. `mag_of` odczytuje istniejącą liczbę nabojów, a normalny strzał tylko ją zmniejsza. Ograniczanie pojemności odbywa się przy przeładowaniu i osobno przy próbie części na strzelnicy.

Scenariusz do testu: SPREAD-12 z 25 nabojami → montaż `sp12_box8` → definicja ma pojemność 8, a licznik załadowanych nabojów pozostaje 25. Analogiczny przypadek występuje przy zmianie zestawu. Nie tworzy to nowych nabojów, ale pozwala zachować zaletę dużego magazynka po zamontowaniu małego.

Źródła: [profile.gd](../../prototype/scripts/profile.gd#L393), [player.gd](../../prototype/scripts/player.gd#L485), [weapon_controller.gd](../../prototype/scripts/weapon_controller.gd#L309), `_has_ammo`, `try_reload`.

Rekomendacja: jeden handler zmiany konfiguracji dla montażu i zestawów. Powinien przerwać nieaktualne przeładowanie, zachować typ naboju i stan komory, zwrócić nadmiar do właściwej puli zgodnie z autorytetem serwera i nie generować darmowej amunicji przy powiększeniu magazynka. Dodać regresje duży→mały→duży oraz zmianę podczas przeładowania.

Pewność wysoka z analizy przepływu; osobnej reprodukcji runtime tego scenariusza jeszcze nie wykonano.

### P1 — serwer nie wymaga obecności przy stanowisku

Panel zamyka się po odejściu i poza bezpieczną strefą, ale `_buy_server`, `_part_server`, `_buy_supply_server`, `_service_server`, `_research_server`, `_machining_server`, `_order_server` i `_fuse_server` nie sprawdzają fazy misji, życia gracza ani odległości nadawcy od właściwego stanowiska. Sprawdzenie `enabled()` wyłącza gospodarkę w Nocnym Dyżurze, nie stanowi ograniczenia do kryjówki.

Klient wysyłający RPC może więc uruchomić operację poza miejscem udostępnianym przez UI. Wymiana części eksploatacyjnych dodatkowo nie potwierdza na serwerze, że wymiana jest potrzebna; powtarzane żądania mogą obciążać wspólny bank.

Źródła: [scrap.gd](../../prototype/scripts/scrap.gd#L270), [scrap.gd](../../prototype/scripts/scrap.gd#L555), [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L1027).

Rekomendacja: wspólna walidacja kontekstu operacji, wykonywana przed wydaniem walut: istniejący gracz nadawcy, żywy, w kryjówce, przy stanowisku obsługującym tę akcję. Dystans liczyć dla gracza nadawcy; `local_in_range` jest lokalnym stanem UI i nie nadaje się do autoryzowania klientów na hoście. Dodać ograniczenie tempa i kontrolę powtórzeń dla operacji płatnych. Testować odmowę poza kryjówką i brak zmiany banku, pozytywny zakup przy stanowisku oraz dwa konkurujące żądania.

Pewność wysoka z kodu; nie wykonywano osobnego ataku RPC na działającą sesję.

### P2 — pracownia i tokarka otwierają się na niepasującej broni

`open()` zawsze ustawia `_sel = 0`, czyli M-83. `_options(M83)` jest puste w trybach `lab` i `lathe`, a siatka nadal pokazuje wszystkie 12 broni. Użytkownik trafia na pusty szczegół mimo dostępnych badań lub schematów.

Źródła: [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L994), [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L1150).

Rekomendacja: lista odpowiednia do stanowiska oraz pierwszy sensowny wybór: noszona broń, schemat do wykonania, aktywne zlecenie lub dostępna broń specjalna. Zapamiętać wybór osobno dla stanowiska. Zachować wspólny komponent panelu.

### P2 — porównanie konfiguracji nie pokazuje wielu głównych korzyści

Podgląd oblicza część spod kursora poprawnie, ale korzysta ze standardowej amunicji i `Codex._weapon_stats`. Tabela pokazuje obrażenia, tempo, zasięg, magazynek, przeładowanie, hałas, masę i DPS broni białej. Nie pokazuje liczbowo m.in. czasu dobycia, rozrzutu, podrzutu, przebicia i grzania. Korzyść części bywa więc widoczna tylko w opisie, podczas gdy jej koszt pojawia się w tabeli. Pasek kafla pokazuje liczbę odblokowanych części, nie jakość ani stan zamontowanego zestawu.

Źródła: [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L1628), [codex.gd](../../prototype/scripts/codex.gd#L243), [workshop_ui.gd](../../prototype/scripts/workshop_ui.gd#L1600).

Rekomendacja: krótka lista zmienionych parametrów „teraz → po montażu”, właściwa dla części i trybu obsługi. Dodatkowo koszt masy całego ekwipunku: zmiana biegu i hałasu. Jasno podpisywać „odblokowane części” oraz „zamontowany zestaw”. Przy próbie na strzelnicy umożliwić porównanie z obecnym montażem i wybranym typem naboju.

### P2 — samomontaż jest świadomym zachowaniem, ale zmienia też broń kolegów

`Profile.fitted` wybiera pierwszą odblokowaną część, jeśli gracz nie zapisał własnej decyzji w gnieździe. `Scrap.changed` aktualizuje `player.fits`. Zakup lub ukończenie badania/tokarki może więc zmienić konfigurację pozostałych graczy bez ich osobnego montażu. To zachowanie jawnie opisane i testowane, nie przypadkowy błąd.

Źródła: [profile.gd](../../prototype/scripts/profile.gd#L401), [player.gd](../../prototype/scripts/player.gd#L470), [weapon_test.gd](../../prototype/scripts/weapon_test.gd#L3054).

Rekomendacja: odblokowanie drużynowe plus świadomy montaż osobisty. Historyczne konfiguracje przenieść jednorazowo przy migracji. Jeśli samomontaż zostaje, wyraźnie komunikować każdemu graczowi zmianę i umożliwić szybki powrót. Decyzję UX sprawdzić w kooperacji.

### P2 — dopracować zbiegi znajdziek, badań i dostaw

`pick_find` pomija posiadane i już znalezione części, lecz nie pomija aktywnego badania, schematu ani zlecenia tokarki. `bank_loot` najpierw odblokowuje znaleziska, potem kończy badania; może zostać schemat części już posiadanej.

Dostawa amunicji korzysta z `Arsenal.add_throwable`, które ogranicza zapas do maksimum. `bank_loot` ignoruje zwróconą liczbę przyjętych nabojów i usuwa zlecenie. Jeśli zapas wypełni się podczas misji, opłacona dostawa może wejść tylko częściowo.

Źródła: [scrap.gd](../../prototype/scripts/scrap.gd#L163), [scrap.gd](../../prototype/scripts/scrap.gd#L101), [arsenal.gd](../../prototype/scripts/arsenal.gd#L204).

Rekomendacja: zdefiniować wynik tych przypadków i dodać regresje. Najmniejszy pierwszy krok to pomijanie części w toku przy losowaniu, usuwanie martwych schematów oraz zachowanie nieprzyjętej części dostawy do odebrania w kryjówce.

## 4. Kolejność usprawnień

1. **Spójność i ochrona gospodarki:** pojemność magazynka po montażu/zestawie, serwerowa walidacja stanowiska, ochrona przed powtórnym obciążaniem banku.
2. **Czytelność obecnych stanowisk:** właściwa lista broni i wybór początkowy, porównanie rzeczywiście zmienianych parametrów, wspólny widok „co jest gotowe / co czeka / gdzie odebrać”.
3. **Świadoma konfiguracja:** doprecyzować samomontaż i zachowanie zestawów; wykorzystać już istniejącą bezpłatną próbę części na strzelnicy.
4. **Przypadki graniczne kolejek:** znajdźka podczas badania/tokarki, pełny zapas w chwili dostawy, ponowne dołączenie i dwóch kupujących.
5. **Playtest przed balansem:** mierzyć czas przygotowania do następnej misji, wykorzystanie stanowisk, udział broni, czas do pierwszej części, korzystanie z zestawów i strzelnicy. Dopiero potem zmieniać ceny, czasy i alternatywy.

Zgodnie z [GDD §16.0a](../../GDD.md#L582), do co najmniej trzech zewnętrznych sesji priorytetem jest uproszczenie i weryfikacja istniejącego systemu. Nie rekomenduję teraz nowych stanowisk, walut ani warstw zużycia.

## 5. Weryfikacja i jej granice

Uruchomiono lokalną paczkę Windows `1.7.366+826bae4` z Godot 4.7.2, headless, przez ENet. Porównano 22 pliki źródłowe tego systemu z commitem builda: są identyczne po normalizacji CRLF. Bieżący checkout ma HEAD `52498c9`; nie jest to pełny test całego checkoutu ani jego widoku 3D.

Silnik eksportowy odmawia uruchomienia repozytorium przez `--path` (`disable_path_overrides`). Dlatego testowano gotową paczkę, a zgodność audytowanych źródeł sprawdzono osobno. Dane użytkownika były odizolowane przez środowisko procesów APPDATA/LOCALAPPDATA.

| Test | Wynik |
|---|---|
| Start hosta | Kod 0 |
| `--weapontest` | 379/379, 0 błędów, kod 0 |
| `--rangetest` | 79/79, PASS, kod 0 |
| `--weaptestnet` + `--weaptestclient` | 8/8 przypadków hosta; host i klient zakończyły się kodem 0 |

Testy potwierdzają m.in. zastosowanie części, odrzucanie nieposiadanych części na serwerze, pojemność po przeładowaniu, zestawy, konserwację, kolejki badań/tokarki i próby części na strzelnicy. Nie pokrywają wszystkich opisanych wyżej luk. Testy nie potwierdzają wygody UI, balansu, Steam P2P ani poprawnego renderowania kadru; Steam nie był połączony.

Logi: `/mnt/c/tmp/codex-gameon-upgrade-audit-_vwmy3_x/`: `unit-stdout.log`, `range-stdout.log`, `net2-host-stdout.log`, `net2-client-stdout.log` i odpowiednie stderr.

Komendy do ponownej weryfikacji repozytorium z pełnym Godotem 4.7.2:

```bash
godot --headless --path prototype -- --host --port=8950 --weapontest --autoquit=220
godot --headless --path prototype -- --host --port=8952 --rangetest --autoquit=60
bash prototype/tools/test_weapons.sh
```

Jedyny dodany plik repozytorium to ten raport. Kolejny rekomendowany krok: mały patch dla zmiany pojemności magazynka i autoryzacji operacji warsztatu, z regresjami tych konkretnych zachowań.
