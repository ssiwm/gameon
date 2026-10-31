# Dead Air '87

Co-op horror run-and-gun (retro Contra), Godot **4.7.2**, GDScript, symulacja 2D z obrazem wyłącznie w 3D (`view3d.gd`; widoku 2D i grafiki klasycznej już nie ma — tylko tryb headless nic nie rysuje); renderer Forward+ (Vulkan / D3D12; `--rendering-driver opengl3` wymusza tryb zgodności, np. pod xvfb). Cały projekt w `prototype/` (`godot --path prototype`). Opis gry: `GDD.md`, historia zmian: `CHANGELOG.md`, opis prototypu i flag CLI: `prototype/README.md`.

## Zasady

- **Tylko 3D.** Wszystko, co widać w świecie gry, robimy w 3D: modele, światła, cząsteczki, ogień, dym, krew, pociski, efekty. Nie dodawaj nowych elementów rysowanych w 2D (`_draw`, `Sprite2D`, `CPUParticles2D`, `PointLight2D`) nałożonych na scenę 3D; istniejące zastępuj odpowiednikami 3D, gdy ich dotykasz. Wyjątek: interfejs (HUD, menu, celownik, etykiety i paski nad postaciami). Symulacja (fizyka, AI, sieć) zostaje 2D.
  Jedyny wyjątek od symulacji 2D: strzelnica FPP (`scripts/range3d/`, `RANGE_FPS_PLAN.md`) — tunel i cele liczone analitycznie (promień kontra
  proste bryły), bez fizyki 3D; broń strzela tym samym `weapon_controller.gd` co na misji (`range_sink`).
- Komentarze i teksty projektowe po polsku; identyfikatory po angielsku; doc-komentarze `##`.
- Wiedza o Godocie 4.7 i konwencje kodu: skill `godot`. Blender (headless, sprite'y): skill `blender`.
- Hook `.claude/hooks/gd-check.sh` po edycji `.gd` uruchamia projekt headless i ostrzega o błędach skryptów — traktuj ostrzeżenie poważnie.
- Nowe albo przebudowane modele GLB (`art/*3d/`): po imporcie headless uruchom `python tools/tex_vram.py` i zaimportuj jeszcze raz — import bez edytora
  zostawia wyciągnięte tekstury bez kompresji VRAM (ok. 4× więcej pamięci wideo); CI sprawdza to przez `tex_vram.py --check`.
- Nowy `.gd` tworzy `.gd.uid` — commituj oba. `.godot/` i `build/` są w `.gitignore`.
- Grafikę i audio generują skrypty Pythona w `prototype/tools/` — edytuj generatory, nie wynikowe pliki.
- Gameplay w sieci rozstrzyga serwer (pociski, obrażenia); klient robi predykcję i rysuje. Nie dodawaj logiki bez walidacji serwera.
- Zmieniasz mechanikę → zaktualizuj `README.md` / `GDD.md` / `WEAPONS.md`, jeśli ją opisują. PR, który zmienia grę, podbija `config/version`
  w `prototype/project.godot` i dopisuje wiersz do `CHANGELOG.md` (tytuł = tytuł PR-a).
- Klawisze i przyciski pada żyją w rejestrze `prototype/scripts/actions.gd`: nową akcję dopisz tam, a nazwę klawisza w tekstach podawaj
  przez `Actions.key("id")` / `{id}` w `Actions.fmt(...)`, nie literałem. Tekst UI po angielsku + wiersz w `prototype/translations/ui.csv`
  (kolumna `pl`); sformatowane teksty przez `tr()`.

## Testy (headless)

```bash
godot --headless --path prototype --import                      # po zmianach zasobów
godot --headless --path prototype -- --maptest --autoquit=4     # mapy (~6 s), ma wypisać PASS
godot --headless --path prototype -- --host --stalkertest --autoquit=70   # Stalker: ostrzał, teren, po ciosie, unik bota przed zamachem (~50 s), ma wypisać PASS
godot --headless --path prototype -- --host --funtest --autoquit=100     # FUN_PLAN.md P0–P2: ucieczka o włos, wabik, wyróżnienia, limit hałasu wrogów, oddech, śrut na pancerz, skrzynia mocy, cichy cel, sejf, punkt kontrolny bossa (z łupem i baterią), obrażenia Żyły (wybuch, śrut), następna misja bez kryjówki (~45 s), ma wypisać PASS
godot --headless --path prototype -- --host --mission=z1_m1 --batterytest --autoquit=40   # baterie 4,5 V (BATTERY_PLAN.md B0–B2): znaczniki `y`, kto bierze i ile, bot ustępuje człowiekowi, sejf, zrzuty, pusta latarka, dziennik sesji (`bat`, battery, battery_empty), przygasanie snopu, karta LATARKA, podpowiedź, licznik do raportu (~10 s), ma wypisać PASS
godot --headless --path prototype -- --host --mission=z1_m1 --resulttest --autoquit=60   # raport po akcji (RESULTS_PLAN.md): model i warianty misji, rozbicie złomu i XP, awanse, drużyna i gotowość, rekordy mapy, sekwencja i pominięcie, „Reduce Effects”, spóźnione XP, mieszczenie (EN/PL, skale UI, 1–4 graczy), blokada wejścia, następna misja (~15 s), ma wypisać PASS
godot --headless --path prototype -- --host --bottest --autoquit=40      # bot za plecami dowódcy (marsz w obie strony, krótki i długi obrót), linia ognia, skradanie, podnoszenie dopiero po wylądowaniu, zejście ze znacznika plucia Żyły (~20 s), ma wypisać PASS
godot --headless --path prototype -- --host --mission=z1_b1 --leechtest --autoquit=120   # boss B1: obrażenia, zasadzka, QTE, odpoczynek od brzegu, fazy, poziomy trudności, stan bossa w dzienniku, śmierć → ekstrakcja → sukces (~40 s), ma wypisać PASS (0 błędów)
godot --headless --path prototype -- --host --nobot --mission=z1_m2 --nobottest --autoquit=60   # bez AI towarzysza: brak bota, drezyna solo, kroki na jadącej drezynie, brak bicia serca przy Uwadze, upadek → wykrwawienie, drugi → wipe (~20 s), ma wypisać PASS
godot --headless --path prototype -- --host --nobot --mission=z1_hub --nobottest --autoquit=30  # bez AI towarzysza w kryjówce: przełącznik hosta dodaje i usuwa bota, ma wypisać PASS
godot --headless --path prototype -- --host --enemytest --autoquit=150    # wrogowie i hałas (walidacja, zasięgi, zachowania rodzajów, elity, ~50 s lokalnie, ~2 min w CI), ma wypisać PASS
godot --headless --path prototype -s tools/test_sound_grid.gd   # droga dźwięku po mapie, ma wypisać PASS
godot --headless --path prototype -s tools/test_audio_loops.gd  # pętle dźwięku na całej długości, ma wypisać PASS
godot --headless --path prototype -s tools/test_aim_points.gd   # wylot pocisku: niezależny od animacji i zgodny z lufą modelu, ma wypisać PASS
godot --headless --path prototype -s tools/test_proportions.gd  # hitboxy kontra modele, meble i znajdźki w naturalnej skali, anatomia postaci, ma wypisać PASS
godot --headless --path prototype -s tools/test_structures.gd   # słupy widoku 3D: ciągłość przez kładki i znaczniki, podstawa, styk z pokładem, ma wypisać PASS
godot --headless --path prototype -s tools/test_characters.gd   # postacie: magazyn user://characters, migracja starego zapisu, kryptonimy, limit, czas gry, nowa kampania, reset, usuwanie, COFNIJ, limit kopii (osobny katalog, zapis gracza nietknięty), ma wypisać PASS
godot --headless --path prototype -s tools/test_messages.gd     # arbiter komunikatów (priorytet, duplikaty, czas życia, toasty, dziennik), ma wypisać PASS
godot --headless --path prototype -s tools/test_note_contrast.gd # kontrast i jasność papieru notatek (ciemna paleta po zmroku), ma wypisać PASS
godot --headless --path prototype -- --uifittest                # menu pauzy (ustawienia, kodeks, sterowanie) i ekran OPERATORZY (karty, okno kryptonimu, walidacja, przełączenie postaci, okna resetu i usuwania, przytrzymanie myszą i [Enter], COFNIJ) mieszczą się po angielsku i po polsku; menu główne (tekst w kartach, ekran, strefy, ≥ 12 px, ≤ 70 słów w spoczynku w 4 rozdzielczościach, siatka fokusu, akcje, DOŁĄCZ bez Steama, szuflada, „Reduce effects”, podpowiedzi pada) mieści się po angielsku i po polsku, zmiana języka przebudowuje menu, ma wypisać PASS
godot --headless --path prototype -- --host --rangetest --autoquit=60   # strzelnica FPP: drzwi, opcje widoku z oczu, akcje „range”, blachy, bronie specjalne, papier, wózek, co-op, przyrządy z modelu, ćwiczenie z przeładowaniem, rekordy osobiste, porównanie grup, szafa z bronią, podrzut, amunicja ćwiczebna, oparcie, tablica drużyny (serwer), wyjście (~30 s), ma wypisać PASS
prototype/tools/test_weapons.sh                                 # bronie + sieć (~3 min)
prototype/tools/test_cabinets.sh                                # gabloty: otwieranie [E] / [H], Esc, rzędy, blokady, zamiana, sieć (~1 min)
prototype/tools/test_net_session.sh                             # sesja sieciowa: inna wersja, utrata hosta, czterech ludzi P1–P4, wyjście z sesji w kryjówce bez błędów peera, kryptonimy (powtórka „(2)”, czyszczenie), host bez bota, raport po akcji (gotowość klienta, poziomy, złom) (~1 min)
```

CI (`.github/workflows/tests.yml`) odpala te testy na każdym PR.

## Git

Praca na gałęziach, PR do `main` (bez bezpośrednich commitów na `main`).
