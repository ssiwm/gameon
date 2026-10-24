# Wołek i Rzeźnik — odbiór modeli i ruchu, 1.7.378

## Zakres i przyczyny

Ocena z 2026-10-25 obejmuje te dwa modele, ich chód, szarżę, cios, przerwanie, obrót, lądowanie i śmierć. Naprawa szwów z 1.7.377 poprawiała ciągłość, lecz pozostawiała słabą topologię i zbyt uproszczony ruch. Sam pomiar liczby trójkątów nie potwierdza jakości.

Fakty z kodu i porównania renderów:

- Wołek miał 5 999 trójkątów. Postawa używała wspólnej, niskiej wysokości dłoni i dokładała pochylenie do już zgarbionej anatomii.
- Rzeźnik miał 24 990 trójkątów ciała i 5 000 tasaka. Źródło zawierało liczne nieregularne połączenia, drobiny powierzchni i otwartą dłoń przy rękojeści.
- Oba wpisy w `scripts/enemy3d.gd::SPEC` nie podłączały biblioteki chodu (`walk_clip`). Istniejące krzywe ciosu sterowały celami dłoni bez osobnego ustawienia nadgarstka i skrętu klatki piersiowej.
- Porównanie materiału, wyłączenia normalnych, wyłączenia ORM oraz samego albedo izoluje wpływ AO. Nadmierne przyciemnienie źródła dawało czarne plamy na ramionach i butach.
- Pomiar zakresu retargetowanych stóp wykazał, że przy cyklu 1 s ciało przemieszczało się około dwa razy szybciej niż wynikało z kroku. Maska żaru oczu rozpoznawała również pomarańczową skórę Rzeźnika.

## Wdrożone w kodzie

`tools/prep_enemy3d.py --only=wolek,rzeznik` korzysta z `tools/enemy_hero_mesh.py::prepare`:

1. Pełne, istniejące źródła: `art_src/enemies/tripo/wolek_01_rig.glb` i `art_src/enemies_f4/rzeznik_rig.glb`.
2. Odtworzenie powierzchni voxel remesh, łagodne wygładzenie, redukcja z budżetem LOD0 40k/50k. Usunięcie płaskich drobin i kontrola zamknięcia **rzeczywistego eksportu GLB**, po konwersji do float32.
3. Nowe UV i wypiek albedo, normalnych z geometrii oraz ORM w 2048 px. Albedo nie zawiera nowego oświetlenia; AO ma ograniczoną siłę. Skóra, rogi i tkaniny są dielektrykami, tasak zachowuje osobny materiał.
4. Wagi po powierzchni, dyfuzja na barkach/łokciach, maksymalnie cztery znormalizowane wpływy. Tasak jest sztywno związany z prawą dłonią; `_cleaver_grip` zamyka dalszą część palców w stałej pozie chwytu.
5. Import Godota generuje LOD i siatki cieni (`meshes/generate_lods`, `meshes/create_shadow_meshes`). Tekstury przechodzą kompresję VRAM przez `tools/tex_vram.py`.

`scripts/enemy3d.gd` podłącza chód zombie dla Wołka i ludzki dla Rzeźnika. Pozycja spoczynkowa dłoni pochodzi z anatomii szkieletu. `_apply_biped` rozdziela pochylenie między miednicę i kręgosłup, dodaje kontrrotację, udział obręczy barkowej oraz sterowanie nadgarstkiem. Podparcie stóp pozostaje korygowane względem terenu.

Cykl zwykłego chodu wynosi 0,5 s; częstotliwość skaluje rzeczywista prędkość. Szarża używa dłuższego kroku z referencyjnym cyklem 1 s, zasięgiem ograniczonym długością nóg i podporami pod biodrami. Prędkości i mnożniki zachowań nie uległy zmianie. `_prepare_soles` usuwa duplikaty UV z limitu próbek i dodaje najniższe punkty siatki 8×8 na pięcie i palcach tych dwóch modeli. Maska żaru jest wyłączona dla palety Rzeźnika również w aktualizacji każdej klatki.

`scripts/enemy_motion.gd` opisuje osobne zamachy, kontakt i odzyskanie równowagi. `_bounded_track` wypieka monotoniczny Hermite w 120 Hz, aby cele i kąty nie przestrzeliwały klatek kluczowych. **Kontakt nadal wyznacza zdarzenie serwera**; biblioteka animacji nie zadaje obrażeń ani nie zmienia zasięgów.

## Odbiór i odtwarzanie

Odbiór techniczny obejmuje faktyczną siatkę, zamknięcie ciała, wagi i ruch szwów (`test_enemy_surface.gd`), pozycję dłoni nad głową, osiągalność celów, podparcie, uniesienie i kierunek ostrza (`test_enemy_motion.gd`) oraz położenie podeszew 14 modeli (`audit_enemy_assets.gd`). Częstotliwości: 30/60/120 fps.

Wyniki aktualnego LOD0:

| Model | Trójkąty | Brzegi ciała | Krawędzie ciała >2 ścian | Rozjazd szwów w ruchu |
|---|---:|---:|---:|---:|
| Wołek | 39 882 | 0 | 0 | 0 |
| Rzeźnik | 44 872 ciało + 5 000 tasak | 0 | 0 | 0 |

- `test_enemy_motion.gd`: **55 653 sprawdzenia, 0 błędów**, w tym dopasowanie drogi do kroku, szarża, chwyt tasaka i kierunek ostrza.
- `audit_enemy_assets.gd`: **14 modeli, 0 błędów**; dopuszczalne przenikanie podeszew tych dwóch modeli zaostrzone do 3 mm.
- `--enemytest`: **284/284**. `--maptest`: **PASS, 0 błędów**. Przy zamykaniu pełnej gry testowej występują dotychczasowe ostrzeżenia o zasobach/ObjectDB; nie traktujemy tego jako bezbłędnego zamykania runtime.
- Forward+/Vulkan, RTX 3080, 1280×720, 12 ciężkich modeli: pozowanie **P50 5,747 ms / P95 7,513 ms**, odstęp klatek **P50 16,657 ms / P95 17,444 ms**, 36 wywołań rysowania, około 152,4 MiB pamięci wideo. To scena podglądu, nie pełna misja ani gwarancja minimum sprzętowego.

Odbiór wizualny: Forward+/Vulkan, to samo światło i kamera w porównaniu z 1.7.377, dodatkowo widok z przodu i kamera mapy. Powtarzalny podgląd:

Nagrania i wyniki lokalnego odbioru: `C:/deadair87/reports/enemy-quality-1.7.378/` — `comparison.mp4` (8 s, przed/po), `front.mp4`, `charge.mp4`, `game/` (światło gry), `game-lit/` (diagnostyczne), `assets.json`, `surface.json`, `benchmark.json`. Pliki podglądu są poza repozytorium; poniższy skrypt pozwala odtworzyć aktualne animacje na innej maszynie.

```sh
godot --path prototype -s tools/shot_enemy_motion.gd -- --dir=/tmp/enemy-side --kinds=wolek,rzeznik --closeup --angle=5.33
godot --path prototype -s tools/shot_enemy_motion.gd -- --dir=/tmp/enemy-front --kinds=wolek,rzeznik --closeup --angle=90
godot --headless --path prototype -s tools/test_enemy_motion.gd
godot --headless --path prototype -s tools/test_enemy_surface.gd
godot --headless --path prototype -s tools/audit_enemy_assets.gd -- --out=/tmp/enemy-assets.json
```

## Ograniczenia i poziom pewności

Zamknięcie ciała, wagi, markery kontaktu i geometria kończyn są mierzalne — wysoka pewność po testach. Naturalność i wygląd wymagają również obejrzenia sekwencji, nie pojedynczej pozy.

To istniejący styl i anatomia modeli źródłowych po przebudowie, a nie nowy projekt postaci ani ręcznie wykonana siatka quad. Ciosy są autorskimi krzywymi całego ciała z IK, chód pochodzi z istniejących klipów szkieletowych. Model Rzeźnika ma stały chwyt i nie otrzymał niezależnej animacji każdego palca. Pomiar wydajności na RTX 3080 nie zastępuje testu minimalnej specyfikacji.

Licencjonowane audio i jego wybór w runtime pozostają zachowane; ta zmiana nie dodaje nagrań ani nowych zależności.
