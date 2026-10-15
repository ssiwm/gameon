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

## Porównania z Poly Haven (2026-10-15, `tools/world_pbr_compare.py`)

Obecna tekstura kontra trzej kandydaci po tym samym gradingu, potem zrzuty w grze przed i po. Wynik:

| Materiał | Decyzja | Uzasadnienie |
|---|---|---|
| concrete | **podmieniony** na `dirty_concrete` (1.7.232) | plamy brudu i okruchy zamiast smug; skupiska okruchów powtarzają się co 3 m |
| metal | zostaje MetalPlates013 | rdzawe kandydaty mają beżowo-różowy odcień i lustrzane powtórzenia, `metal_plate` to blacha ryflowana (kafel 0,5 m) |
| terrain | zostaje materiał proceduralny | kandydaci (`forrest_ground_01`, `leaves_forest_ground`, `brown_mud_leaves_01`) są rozmyci albo wyglądają jak żwir |
| wall (cegła) | zostaje Bricks097 | `dark_brick_wall`, `red_brick_03`, `worn_brick_wall` są bardziej jednolite od obecnej ściany z łatami tynku |
| plank, post, grate | bez porównania | to tylko zapas, gdy brak modelu kładki lub słupa |

Modele: las ze skanów (`fir_tree_01` 7,8 mln trójkątów, `fir_sapling` i `pine_sapling_small` po uproszczeniu do 9 tys. to wiotkie szkielety) i lampy (modele Poly Haven nie mają emisji, a lampy map są spięte z `lamp.gd`, `_sync_lamps` i `_scan_lights`) odrzucone — zostają świerki z kart i lampa z Tripo.
