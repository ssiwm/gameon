# Plan: atmosfera „2.5D” bez przepisywania gry (ścieżka pośrednia)

Status: **plan z 2026-10-10; F0–F3 i F5 wdrożone, F4 wycofana** (F4, plan pierwszy z sylwetkami mebli, dawał widoczne artefakty — prostokątne, ciemne bryły przy krawędziach kadru — i został usunięty po uwagach z gry; głębia wróci jako rozmycie tła / mgła warstwowa, jeśli Bramka B tego zażąda; F5: gradacja per mapa w `horror_fx.gd` — presety `GRADES`: kryjówka cieplejsza i kontrastowa, gniazda nasycone, Pijawka zimna). F0–F3: (smugi światła w kryjówce, bloom z mip ekranu w `horror_fx.gd`, okludery postaci + miękki cień kontaktowy zależny od lampy, wszystko pod „Effects quality”). **Pomiar** (`tools/bench_fx.gd`, kryjówka, okno 4K, RTX 3080, czas klatki CPU+GPU z odczytem): HIGH ≈ +1,2 ms, MEDIUM ≈ +0,7 ms względem LOW — przy 1080p ok. ¼ tego, więc budżet +1,5 ms jest zachowany z dużym zapasem; słabsze GPU nie mierzone. Cel: zbliżyć obraz (najpierw kryjówki) do klimatu referencji — ciemne wnętrze, widoczne smugi światła
w mgle i pyle, gorące źródła światła z poświatą, postacie lekko oświetlone i rzucające cienie, miękka głębia, ciężki grading — **metodami 2D**,
w obecnej architekturze (Godot 4.7, `gl_compatibility`, światła 2D, HD sprite'y i postacie 3D renderowane do tekstur). Po bramce A (zob. niżej)
zapada decyzja: dociągamy 2D, czy robimy mały eksperyment 3D na jednej misji.

Referencja: zrzut z filmu o grach 2.5D (kryjówka z kowbojem i lampami sufitowymi), trzymany lokalnie, **poza repo** (prawa autorskie); porównania
robimy obok własnych zrzutów z `tools/shot_*.gd`.

## 1. Co składa się na efekt referencji

| # | Element | Opis |
|---|---|---|
| E1 | Smugi światła | stożki od lamp widoczne w powietrzu, z szumem i drobinami kurzu |
| E2 | Poświata źródeł | gorące lampy i reflektor „zalewają” kadr (bloom/halo) |
| E3 | Postacie w scenie | rim po stronie światła, miękkie cienie na podłodze, brak „naklejenia” na tle |
| E4 | Głębia | rozmyte plany pierwszy i tylny, sylwetki mebli, lekki parallax |
| E5 | Grading | ciepły bursztyn kontra chłodna czerń, winieta, spójna paleta lokacji |
| E6 | Podłoga | miękkie odbicia i kałuże światła na deskach |
| E7 | Scenografia | geometria 3D wnętrza (stoły, krzesła, regały) z wypieczonym AO |

## 2. Stan obecny (z kodu)

- **Lampy:** `lamp.gd` — `PointLight2D` (`Lights.radial()`, promień 9 m, energia 0,85, bez cieni), migotanie, kółka poświaty w nakładce „unshaded”.
- **Światła i stożek:** `lights.gd` — `make_light(tex, meters, color, energy, shadows)`, tekstura stożka (`Lights.cone()`) używana dla latarki.
- **Obraz:** `horror_fx.gd` — jeden przebieg na ekranie (gradacja zimne cienie / ciepłe światła, winieta, aberracja, rogi przy niskim HP); `weather_fx.gd` —
  deszcz, mgła, błyskawice; `player.gd` — pyłki i mgła przy kamerze; `backdrop.gd` — tło parallax (lasy HD).
- **Postacie 3D:** `char3d.gd` — rim light, cienie własne, mapa normalnych dla świateł 2D; sprite'y wrogów HD z normalnymi (8 px/j.).
- **Czego brak:** smug i pyłków w stożku, bloomu o większym promieniu, cieni postaci od lamp (nie ma `LightOccluder2D`), planów pierwszego planu, LUT per lokacja.
- **Sprawdzone:** `WorldEnvironment` z glow w `gl_compatibility` daje halo, ale o małym promieniu (kilkanaście px na 4K) — do mocniejszego efektu własny przebieg.

## 3. Fazy (każda osobny PR, zrzuty A/B przed/po, bez zmian w sieci i rozgrywce)

| Faza | Zakres | Pliki / hooki | Kryterium akceptacji | Szac. |
|---|---|---|---|---|
| **F0 Baseline** | Zrzuty kryjówki (`--mission=z1_hub`, zoom 2,0, 1080p i 4K, poziomy jakości LOW / MEDIUM / HIGH); pomiar fps i czasu klatki (`perf_bench.sh`); budżet: **+1,5 ms / klatka przy 1080p na HIGH** | `tools/perf_bench.sh`, nowa flaga zrzutu | punkt odniesienia w `concepts/` i `perf_*.txt` | 0,5 d |
| **F1 Smugi światła (E1)** | Nowy `light_shaft.gd`: stożek z shaderem (przewijany szum, miękkie krawędzie, intensywność związana z migotaniem lampy); długość ograniczona raycastem do podłogi; drobiny kurzu tylko wewnątrz smugi; lampy w kryjówce dostają smugę | `lamp.gd`, `lights.gd`, `light_shaft.gd` (nowy) | smugi widoczne, gracz i wróg czytelni w smudze; 0 migotania krawędzi; LOW bez smug | 1–2 d |
| **F2 Bloom / halo (E2)** | Przebieg w `horror_fx.gd`: próg jasności → downsample → blur → dodanie (pod HUD-em, więc UI zostaje ostre); alternatywnie / dodatkowo `WorldEnvironment` glow; halo sprite'ów lamp spięte z energią | `horror_fx.gd`, `lamp.gd` | źródła „świecą”, ciemne partie bez przepaleń, HUD ostry; koszt ≤ 0,6 ms na 1080p | 1 d |
| **F3 Cienie postaci od lamp (E3)** | `LightOccluder2D` z uproszczonej sylwetki gracza i bota (z kości / kapsuły), cienie włączone dla lamp kryjówki, miękki filtr; zastępuje usunięty „klocek” pod stopami | `player.gd`, `lamp.gd`, `lights.gd` | cień postaci pada na podłogę i ścianę zgodnie z lampą; bez „pływania”; koszt ≤ 0,5 ms | 1 d |
| **BRAMKA A** | Porównanie zrzutów A/B ze zrzutem referencyjnym wg checklisty (poniżej) i wyniki pomiarów; decyzja: dalej F4–F7, stop, albo spike 3D | — | patrz §5 | 0,5 d |
| **F4 Głębia (E4)** | Warstwy pierwszego planu (ciemne sylwetki mebli, rozmyte shaderem) i rozmycie tła; skala parallax; opcjonalny lekki DoF | `backdrop.gd`, nowy `depth_layers.gd` | głębia bez zasłaniania celu; LOW bez rozmycia | 1–1,5 d |
| **F5 Grading per lokacja (E5)** | LUT (tabela barw) per mapa / kryjówka w `horror_fx.gd`: ciepły bursztyn w kryjówce, stalowy w tunelach, zimny teal w lesie | `horror_fx.gd`, `level.gd` (preset mapy) | spójna paleta każdej lokacji; kontrast zgodny z paletą UI | 0,5 d |
| **F6 Podłoga (E6, opcja)** | Odbicie lustrzane świata w pasie pod podłogą dla materiałów polerowanych / mokrych, szum falowania | shader w `level.gd` | tylko wybrane materiały; koszt ≤ 0,3 ms | 1 d |
| **F7 Scenografia (E7, opcja)** | Prerender elementów kryjówki (stół, krzesła, regały) w Blenderze: sprite + mapa normalnych + wypieczone AO, relit światłami 2D | `art_src/`, `tools/`, `items_hd.gd` | meble z wypieczonym światłem zgodne ze scenami; budżet assetów ≤ 15 MB | 3–5 d |
| **BRAMKA B** | Po F5 (lub F7): decyzja „zostajemy w 2D” albo eksperyment 3D jednej misji (osobny plan, 3 dni, bez ruszania gry) | — | — | 0,5 d |

Razem: **F0–F3 ≈ 4–5 dni** (największe podobieństwo przy najmniejszym ryzyku), **F4–F5 ≈ 2 dni**, F6–F7 opcjonalnie ok. 1 + 3–5 dni.

## 4. Integracja z ustawieniami i jakością

| Element | LOW | MEDIUM | HIGH |
|---|---|---|---|
| Smugi światła | wyłączone | statyczne | animowane + pyłki |
| Bloom / halo | wyłączone | jeden poziom blur | pełny |
| Cienie postaci | wyłączone | 1 lampa | wszystkie lampy w kadrze |
| Głębia (rozmycie) | wyłączona | planu pierwszego | + tło |
| Odbicia podłogi | wyłączone | wyłączone | włączone |

- Wspólne: „Effects quality” (`Settings.quality_idx`) wybiera poziom; **„Reduce effects”** zatrzymuje ruch (smugi statyczne, bez migotania) i wyłącza pyłki; każdy efekt ma też osobny przełącznik w kodzie (do testów i `--nofx`).
- **Czytelność ponad klimat:** smugi i mgła nie mogą ukrywać wrogów; poza kryjówką domyślnie wyłączone, włączane per mapa (`LevelDef`).

## 5. Bramka A — checklista porównania (0–2 pkt każda, próg ≥ 10 / 14)

1. Widoczne stożki światła z szumem / kurzem.
2. Źródła światła mają poświatę, bez przepalenia ciemnych partii.
3. Postać rzuca czytelny cień na podłogę i ścianę.
4. Rim po stronie światła widoczny przy dwóch różnych lampach.
5. Kontrast ciepłe światło / chłodna ciemność.
6. Winieta i krawędzie kadru podobne w nastroju.
7. Czytelność gry (gracz, wróg, HUD) bez strat.

Wynik + pomiar: koszt GPU, fps na RTX i (jeśli dostępny) na integrowanej karcie, VRAM, rozmiar repo.

## 6. Ryzyka

- **Koszt GPU na słabszych kartach:** przebiegi pełnoekranowe (bloom, rozmycie) są najdroższe — stąd budżet i poziomy jakości; pomiar na słabszym sprzęcie przed F4.
- **Czytelność:** smugi i mgła w grze akcji nie mogą zasłaniać wrogów (zasada „słyszysz, nigdy nie widzisz” nie zwalnia z czytelności).
- **Cienie 2D:** liczba świateł z cieniami rośnie koszt kwadratowo z liczbą okluderów; limit na kadr (≤ 3 lampy z cieniami).
- **Granica podejścia:** brak realnej perspektywy i odbić w skali referencji; stąd bramki — jeśli wynik < 10 / 14, rozważamy eksperyment 3D.
- **Zgodność wstecz:** wszystko w poziomach jakości i pod „Reduce effects”; tryb CLASSIC (pixel art) bez zmian.

## 7. Testy i dokumentacja

- `--maptest`, `tools/test_weapons.sh` (jednostkowe + sieć), `shot_flow.gd` — bez regresji.
- Nowe flagi zrzutów: `--shotlight` / `--quality` w `shot_hud.gd` i `shot_game.gd`; zrzut kryjówki w stałych ustawieniach.
- GDD (wpis wersji) i README (opis ustawień) po każdej fazie; ten plik aktualizowany statusem.

## 8. Decyzje do podjęcia

1. **Zakres startowy:** F0–F3 (rekomendacja) czy od razu F0–F5.
2. **Gdzie smugi:** tylko kryjówka (rekomendacja) czy też wybrane mapy (tunele, stacja).
3. **Budżet GPU:** +1,5 ms na 1080p / HIGH (rekomendacja) czy inny.
4. **F7:** prerender mebli (assety) — tak / nie / po bramce A.
5. **Referencja:** czy używamy tylko jednego zrzutu, czy zbieramy 3–4 kadry jako wzorzec nastroju (też poza repo).
