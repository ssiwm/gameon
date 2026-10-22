# Modele 3D przedmiotów i dekoracji — źródła skanów

Większość modeli w tym katalogu powstaje z Tripo albo z brył proceduralnych (`tools/prep_items3d.py`). Część to skany z
[Poly Haven](https://polyhaven.com) — licencja **CC0 1.0** (domena publiczna; bez obowiązku podania autora, podajemy z uprzejmości).
Źródła pobiera `tools/polyhaven_fetch.py` do `art_src/world/polyhaven/`, a `tools/prep_items3d.py` upraszcza siatki i ustawia skalę.

| Model w grze | Asset Poly Haven | Gdzie |
|---|---|---|
| rock, rock_b, rock_c | rock_moss_set_01 (kamienie 1, 4, 5) | kamienie w lesie (dekoracja 3) |
| tree_log | dead_tree_trunk | powalone pnie w lesie |
| radio_set | metal_office_desk + vintage_radio_transceiver | radiostacja w kryjówce |
| shelf | steel_frame_shelves_01 | regały w kryjówce |
| fire_pit | stone_fire_pit | wygasłe ognisko patrolu (1.1) |
| stump | tree_stump_01 | pniaki (las, 1.1, 1.2) |
| trunk_big | dead_tree_trunk_02 | duży powalony pień (1.1) |
| barrel_stove | barrel_stove | koksowniki (1.2, 1.3, kryjówka) |
| mil_crate | wooden_military_crate | skrzynie wojskowe (1.1, kryjówka) |
| tyre | old_tyre | opona w bagnie (1.2) |
| barrier | concrete_road_barrier_02 | zapora przy posterunku (1.3) |
| shelf_n | steel_frame_shelves_01 | regały w Składzie i Pompowni, naturalna skala (1.2, 1.3) |
| shelf_b | steel_frame_shelves_02 | wąski regał (1.2, 1.3) |
| pipes | modular_industrial_pipes_01 | panel rur przy ścianie (1.2, 1.3) |
| compressor | old_military_compressor | kompresor w Pompowni (1.2) |
| cart | industrial_storage_cart | wózek w Składzie (1.3) |
| barrel_n | barrel_03 | beczki we wnętrzach (1.2, 1.3) |
| jerrycan | metal_jerrycan | kanistry (1.1, 1.2, 1.3, B1, kryjówka) |
| gas_mask | old_gas_mask | maska wisząca na ścianie (1.2, 1.3, B1, kryjówka) |
| lathe_cart | tool_cart + bench_vice_01 | wózek-stół z imadłem przy tokarce (kryjówka) |
| drill_chest | metal_tool_chest + old_drill_press | skrzynia narzędziowa z wiertarką stołową przy tokarce (kryjówka) |
| stool_metal | metal_stool_02 | taboret przy prasie elaboracyjnej, stole pirotechnicznym i w pracowni (kryjówka) |
| pyro_ext | korean_fire_extinguisher_01 | gaśnica przy stole pirotechnicznym (kryjówka) |

## Modele z Meshy (image-to-3D)

Maszyny, których nie ma w bibliotekach CC0: obraz wejściowy z FLUX.1 schnell (lokalnie, `tools/comfy_gen.py image --flux`), model z Meshy
(`tools/meshy_prop.py`, płatne kredyty konta autora gry — wyniki planu płatnego należą do autora). Źródła, obrazy wejściowe i parametry zadań
w `art_src/world/meshy/`; `tools/prep_items3d.py` upraszcza siatki i ustawia naturalną skalę.

| Model w grze | Źródło | Gdzie |
|---|---|---|
| lathe | `art_src/world/meshy/lathe.glb` (tokarka w stylu TUR-50) | tokarka i szlifierka (kryjówka) |
| bench_grinder | `art_src/world/meshy/bench_grinder.glb` (szlifierka stołowa na kolumnie) | tokarka i szlifierka (kryjówka) |
| reload_bench | `art_src/world/meshy/reload_bench.glb` (stół elaboracyjny z prasą jednostopniową) | prasa elaboracyjna (kryjówka) |
| ammo_shelf | `art_src/world/meshy/ammo_shelf.glb` (stalowy regał z puszkami i skrzynkami amunicji) | prasa elaboracyjna (kryjówka) |
| pyro_bench | `art_src/world/meshy/pyro_bench.glb` (stół pirotechniczny z osłoną, lontem i tackami granatów) | stół pirotechniczny (kryjówka) |
| expl_locker | `art_src/world/meshy/expl_locker.glb` (czerwona szafa na materiały wybuchowe) | stół pirotechniczny (kryjówka) |
| lab_desk | `art_src/world/meshy/lab_desk.glb` (biurko z oscyloskopem, miernikami, rozebranym radiem i mikroskopem) | pracownia (kryjówka) |
| specimen_case | `art_src/world/meshy/specimen_case.glb` (gablota z preparatami w formalinie; po retopologii Meshy) | pracownia (kryjówka) |
