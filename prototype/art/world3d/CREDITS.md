# Materiały świata 3D — źródła i licencje

Zestaw hybrydowy (`tools/world_pbr_import.py`): skany CC0 po gradingu do stylu gry (przyciemnienie, wyciszenie nasycenia, chłodny odcień,
zmniejszenie do 512²) oraz materiały proceduralne z `tools/world_pbr_gen.py`. Dekale (grafiti, uszkodzenia) i warstwy brudu powstają w
`tools/world_decals_gen.py`.

Skany pochodzą z [ambientCG](https://ambientcg.com) — licencja **CC0 1.0** (domena publiczna; bez obowiązku podania autora, podajemy z uprzejmości):

| Materiał w grze | Asset ambientCG |
|---|---|
| concrete | Poly Haven `dirty_concrete` (od 1.7.232; poprzednio ambientCG Concrete034) |
| metal | MetalPlates013 |
| grate | MetalWalkway013 |
| plank | Planks037A |
| post | Wood096 |
| wall | Bricks097 |

Proceduralne: terrain, mud, oil, water. Dekale i grime: wyłącznie generatory w repo.

Z [Poly Haven](https://polyhaven.com) (CC0): `roof` — blacha falista z tekstury `rusty_corrugated_iron` (Charlotte Baglioni), mapy kolor / normalne / ARM
1K po gradingu jak reszta; `world_pbr_import.py --only=roof` pobiera je do `art_src/world_pbr_cc0/polyhaven/`. Panoramy HDRI w `hdri/` (`kloppenheim_07`,
`debris_basement_corridor`) — niewidoczne dla gracza „niebo odbić” na stali broni; przycięte i znormalizowane przez `tools/polyhaven_fetch.py --hdri`.

Budynek 3D (`building3d.gd`, od 1.7.527) — Poly Haven (CC0), 1K po gradingu przyciemnionym do tonu betonu gry: `bld_wall` (ściany, słupy, pilastry)
`concrete_layers_02`, `bld_slab` (stropodach, belki, żebra) `concrete`, `bld_cut` (płaszczyzna przekroju) `granular_concrete`, `bld_plinth` (cokół)
`concrete_wall_007`; `world_pbr_import.py --only=bld_wall,bld_slab,bld_cut,bld_plinth`.

Pierwszy plan (`front/pipe_parts.glb`, od 1.7.519): części rur z modelu Poly Haven `modular_industrial_pipes_01` (CC0) — sama geometria wycięta przez `tools/front_parts.py`; tekstury te same co dekoracji `pipes` w `art/items3d/`.


Sosna pierwszego planu (`art/items3d/ph_pine_a`–`c`, od 1.7.543): model Poly Haven `pine_tree_01` (CC0) — pień, konary i tekstury kory ze skanu, igliwie zamienione na karty z atlasem wyrenderowanym z geometrii igieł skanu (`tools/pine_cards.py`). Źródło (ok. 1 GB) nie jest w repo: `python prototype/tools/polyhaven_fetch.py --res=2k pine_tree_01`.

Las w głębi (od 1.7.543): sosny `tree_pine_a`–`c` i świerki `tree_spruce_a`–`c` (`art/items3d/`) to lekkie wersje tych samych skanów Poly Haven `pine_tree_01` i `fir_tree_01` (CC0; `pine_cards.py --lite`, pośrednie `art_src/world/polyhaven/*__X_lite.glb` tylko lokalnie, jak źródła), a karty dalekiego pasa `art/world3d/forest/pine_a`, `pine_b`, `spruce_a`–`c` to boczne rendery pełnych skanów (`pine_cards.py --far`). Podrost `tree_spruce_young_a`–`c`: skan Poly Haven `fir_sapling_medium` (CC0) tą samą drogą. Źródła `fir_tree_01` (ok. 570 MB) i `fir_sapling_medium` (ok. 90 MB, `--res=2k`) też tylko lokalnie.

## Porównania z Poly Haven (2026-10-15, `tools/world_pbr_compare.py`)

Obecna tekstura kontra trzej kandydaci po tym samym gradingu, potem zrzuty w grze przed i po. Wynik:

| Materiał | Decyzja | Uzasadnienie |
|---|---|---|
| concrete | **podmieniony** na `dirty_concrete` (1.7.232) | plamy brudu i okruchy zamiast smug; skupiska okruchów powtarzają się co 3 m |
| metal | zostaje MetalPlates013 | rdzawe kandydaty mają beżowo-różowy odcień i lustrzane powtórzenia, `metal_plate` to blacha ryflowana (kafel 0,5 m) |
| terrain | zostaje materiał proceduralny | kandydaci (`forrest_ground_01`, `leaves_forest_ground`, `brown_mud_leaves_01`) są rozmyci albo wyglądają jak żwir |
| wall (cegła) | zostaje Bricks097 | `dark_brick_wall`, `red_brick_03`, `worn_brick_wall` są bardziej jednolite od obecnej ściany z łatami tynku |
| plank, post, grate | bez porównania | to tylko zapas, gdy brak modelu kładki lub słupa |

Modele: las ze skanów z samą decymacją (`fir_tree_01` 7,8 mln trójkątów — od 1.7.543 użyty po zamianie igieł na karty, patrz wyżej; `fir_sapling` i `pine_sapling_small` po uproszczeniu do 9 tys. to wiotkie szkielety) i lampy (modele Poly Haven nie mają emisji, a lampy map są spięte z `lamp.gd`, `_sync_lamps` i `_scan_lights`) odrzucone — zostają świerki z kart i lampa z Tripo.
