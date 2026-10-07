---
name: blender
description: Praca z Blenderem 5.2 z terminala (headless, bpy) — skrypty Pythona, render sprite'ów i sprite sheetów dla Godota, eksport glTF/OBJ. Użyj, gdy trzeba wygenerować lub przetworzyć modele, animacje albo prerenderowaną grafikę do gry.
---

# Blender 5.2 (headless) pod Godota

Na tej maszynie: `blender` w `~/.local/bin`, wersja **5.2.2 LTS**. Brak serwera MCP/pluginu do Blendera — pracujemy przez skrypty `bpy` uruchamiane w tle. Projekt jest 2D pixel-art; Blender ma sens głównie do prerenderowanych sprite'ów (obrót, animacje → klatki → `art/`) albo modeli 3D.

## Uruchamianie

```bash
blender -b --factory-startup -P skrypt.py -- --arg1 x      # skrypt w tle, czyste ustawienia
blender -b plik.blend -P skrypt.py                         # na istniejącym pliku
blender -b plik.blend -o //out/frame_#### -F PNG -a        # render animacji
blender -b plik.blend -f 1 -o //out/img_ -F PNG            # jedna klatka
```

- Argumenty własne czytaj po `--`: `argv = sys.argv[sys.argv.index("--")+1:]`.
- `--factory-startup` daje powtarzalność (bez cudzych addonów i ustawień), ale domyślna scena (kostka, kamera, światło) zostaje — wyczyść ją: `bpy.ops.wm.read_factory_settings(use_empty=True)`.
- Kod wyjścia ≠ 0 i `Error:`/`Traceback` w stdout = błąd; zawsze grepuj wyjście. Zapis: `bpy.ops.wm.save_as_mainfile(filepath=...)`.
- Skrypty trzymaj w `prototype/tools/` (obok `bake_*.py`), z komentarzem po polsku i uruchomieniem w nagłówku — jak reszta generatorów. Wynik do `prototype/art/`.

## Pułapki wersji 5.x

- Silnik EEVEE ma id **`BLENDER_EEVEE`** (w 4.2–4.5 było `BLENDER_EEVEE_NEXT`). W headless bez GPU EEVEE może nie działać — sprawdź; alternatywa `CYCLES` (CPU, `scene.cycles.device = 'CPU'`, mało próbek) albo `BLENDER_WORKBENCH` do szybkich, płaskich renderów. Przy factory-startup w tej instalacji lista silników pokazała tylko EEVEE — Cycles trzeba włączyć addonem, jeśli potrzebny: `bpy.ops.preferences.addon_enable(module="cycles")`.
- Preferuj **API danych** (`bpy.data.objects.new`, `bpy.data.meshes.new`, `mesh.from_pydata`) zamiast `bpy.ops` — ops wymagają kontekstu i bywają kruche w tle. Gdy musisz użyć ops: `with bpy.context.temp_override(...)`.
- Zaznaczanie/aktywny obiekt: `obj.select_set(True)`, `bpy.context.view_layer.objects.active = obj`.
- Jednostki: Blender metry, Z w górę; Godot Y w górę (glTF eksporter konwertuje osie — zostaw domyślne `export_yup=True`).
- Nie polegaj na zapamiętanych nazwach operatorów/właściwości z 2.x/3.x — sprawdzaj `dir(...)`/`bpy.types.X.bl_rna.properties` w tym samym uruchomieniu albo docs.blender.org/api/current/.

## Render sprite'ów 2D (pixel-art)

1. Kamera ortograficzna: `cam.data.type='ORTHO'`, `ortho_scale` dobierz do obiektu; tło przezroczyste: `scene.render.film_transparent = True`.
2. Rozdzielczość = docelowy rozmiar klatki × 4 (projekt renderuje postacie w 4× i zmniejsza z cieniowaniem rampami) albo bezpośrednio docelowa; `scene.render.resolution_percentage = 100`, `image_settings.file_format='PNG'`, `color_mode='RGBA'`.
3. Klatki: pętla po `scene.frame_set(i)` + `bpy.ops.render.render(write_still=True)` z `scene.render.filepath`. Sprite sheet złóż w Pythonie (Pillow w istniejących `tools/*.py`) — spójnie z `bake_sprites.py`.
4. Redukcja palety/obrys: po renderze przepuść przez istniejące narzędzia grafiki projektu, nie powtarzaj logiki w Blenderze.
5. Skala w Godocie: tekstury `NEAREST` (filtr), bez mipmap dla pixel-artu.

## Eksport do Godota (3D)

```python
bpy.ops.export_scene.gltf(filepath="//model.glb", export_format='GLB',
                          export_apply=True, export_animations=True)
```

- glTF 2.0 (`.glb`) to preferowany format dla Godota; OBJ: `bpy.ops.wm.obj_export(filepath=...)`.
- Zastosuj modyfikatory (`export_apply=True`), skale `1.0` (Ctrl+A odpowiednik: `bpy.ops.object.transform_apply(scale=True)`), nazwy węzłów/animacji bez spacji. Animacje jako osobne akcje (`bpy.data.actions`), NLA tracks → osobne klipy w Godocie.
- Do Godota wrzucaj do `prototype/art/` (lub podkatalogu); po dodaniu: `godot --headless --path prototype --import`.

## Weryfikacja

- Po wygenerowaniu pliku sprawdź go: rozmiar (`ls -la`), wymiary PNG, a obraz obejrzyj narzędziem Read (obsługuje PNG).
- Skrypt powinien być idempotentny (czyści scenę na starcie, nadpisuje wynik).

Źródła: [Blender Python API](https://docs.blender.org/api/current/), [Command line](https://docs.blender.org/manual/en/latest/advanced/command_line/index.html), [Godot: importing 3D scenes](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/index.html).
