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
