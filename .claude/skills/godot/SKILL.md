---
name: godot
description: Aktualna wiedza o Godot 4.7 (GDScript, 2D, fizyka, multiplayer, UI, audio, eksport, testy headless) i konwencje projektu Dead Air '87. Użyj przy pisaniu lub zmianie skryptów .gd, scen .tscn, project.godot, przy debugowaniu, testach headless i eksporcie gry.
---

# Godot 4.7 — wiedza do tworzenia gry

Projekt: `prototype/` (Godot **4.7.2**, GL Compatibility, GDScript, 2D, 640×360 → okno 1280×720, `canvas_items` + `keep`). Binarka: `godot` w PATH. Zawsze `--path prototype` (albo cd do `prototype/`).

## Zasady pracy (kolejność ma znaczenie)

1. **Nie zgaduj API.** Gdy nie jesteś pewien sygnatury/klasy, sprawdź: Użyj docs.godotengine.org/en/4.7/classes/class_<nazwa>.html (WebFetch) albo `grep` po repo, jak to już zrobiono.
2. **Po każdej zmianie skryptu uruchom headless** i szukaj `SCRIPT ERROR` / `Parse Error`:
   ```bash
   godot --headless --path prototype --quit-after 2 2>&1 | grep -a -E "ERROR|Parse|WARNING" | head
   ```
   Po dodaniu nowych plików/`class_name`/zasobów najpierw import: `godot --headless --path prototype --import`.
3. **Nowy `.gd` → powstaje `.gd.uid`** (od 4.4). Commituj oba pliki. Przy przenoszeniu/usuwaniu skryptu usuń też `.uid`. `.godot/` jest w `.gitignore`.
4. Edytuj `.tscn`/`project.godot` ręcznie tylko ostrożnie (format tekstowy, `config_version=5`); preferuj budowanie węzłów w kodzie — tak robi ten projekt (większość sceny składana w `main.gd`/`level.gd`).
5. Testuj przez flagi CLI gry (patrz niżej), nie przez edytor GUI.

## GDScript 2 — idiomy i pułapki

- **Typuj**: `var x: int = 0`, `var v := Vector2.ZERO`, `func f(a: float) -> void`, `Array[Node2D]`, `Dictionary[String, int]` (typowane słowniki od 4.4). `:=` wnioskuje typ; nie działa, gdy prawa strona to `Variant` (np. z `Dictionary[...]` nietypowanego, `get_node`, wynik `call`) — wtedy `var x: T = ...` albo `as T`.
- Stałe: `const Foo := preload("res://scripts/foo.gd")` (konwencja repo zamiast globalnych `class_name`). Kolejność w pliku: `extends`, komentarz `##`, `const`, `signal`, `@export`, `var`, `@onready`, funkcje.
- `@export`, `@export_range(0, 1, 0.01)`, `@export_group`, `@onready var n := $Path`. `@tool` tylko gdy naprawdę trzeba.
- Sygnały: `signal hit(dmg: int)`, `hit.emit(3)`, `obj.hit.connect(_on_hit)`, `CONNECT_ONE_SHOT`. Lambdy działają: `btn.pressed.connect(func(): ...)`. Odłączaj/`is_connected` przy ponownym podpinaniu.
- `await get_tree().create_timer(0.5).timeout`; `await signal`. Uwaga: po `await` węzeł mógł zostać zwolniony → `if not is_inside_tree(): return` / `is_instance_valid(n)`.
- `StringName`: `&"nazwa"`; `NodePath`: `^"Path"`. Przy porównaniach akcji używaj `StringName`.
- `match` wspiera wzorce tablic/słowników. `assert()` działa tylko w debug. `push_error` / `push_warning` zamiast `print` dla problemów.
- **Zmiany 4.7 (GDScript):** ustawianie elementu spakowanej tablicy (`PackedVector2Array[i] = ...`) **nie woła już settera całej właściwości**; metody dziedziczące typ zwracany **muszą mieć jawny `return`**. Zmiany 4.6: `AnimationPlayer.current_animation/assigned_animation/autoplay` są `StringName`; `FileAccess.get_as_text()` bez `skip_cr`; `Object.is_class()` bierze `StringName`.
- Wydajność: w gorących pętlach unikaj alokacji (`Vector2(...)` w tysiącach iteracji jest OK, ale nie twórz `Array`/`Dictionary`/`Callable` co klatkę), cache'uj `get_node`, używaj `PackedXArray`, `distance_squared_to` zamiast `distance_to`.
- Fizyka w `_physics_process(delta)`, wizualia/UI w `_process`. Nigdy nie mnóż ruchu `CharacterBody2D` przez `delta` przy `velocity` + `move_and_slide()` (slide sam to robi).
- Stałej liczby klatek nie zakładaj — wszystko przez `delta`.

## 2D: węzły i fizyka

- **TileMapLayer** (stary `TileMap` jest deprecated od 4.3): jeden węzeł = jedna warstwa; `set_cell(coords, source_id, atlas_coords, alt)`, `erase_cell`, `get_cell_source_id`, `local_to_map`/`map_to_local`. Fizyka kafla z TileSet physics layer; **kładki jednokierunkowe** = polygon z `one_way_collision` (w 4.7 `body_set_shape_as_one_way_collision` ma opcjonalny `direction`).
- `CharacterBody2D`: ustaw `velocity`, wołaj `move_and_slide()`, potem `is_on_floor()`, `get_slide_collision()`. `floor_snap_length`, `up_direction`, `motion_mode` (GROUNDED/FLOATING). Rozmiary kolizji dobieraj pod siatkę kafli — rozmiar kafla jest w `level.gd`.
- Warstwy/maski kolizji: bity, `collision_layer` = „czym jestem", `collision_mask` = „co wykrywam". Ustawiaj `set_collision_layer_value(n, true)`. `Area2D` → `body_entered/area_entered`; zmiana monitoringu w callbacku fizyki → `set_deferred("monitoring", ...)`, `call_deferred`.
- Zapytania: `PhysicsDirectSpaceState2D.intersect_ray(PhysicsRayQueryParameters2D.create(a, b, mask))`, `intersect_shape`. `RayCast2D` wymaga `force_raycast_update()` jeśli ustawiasz w tej samej klatce.
- `AudioStreamPlayer` od 4.7: domyślny `area_mask` = 0 (nadpisania szyny przez `Area2D` mogą przestać działać — ustaw jawnie).
- Rysowanie: `_draw()` + `queue_redraw()`; w 4.7 linie `draw_*` nie mają już „feather" antyaliasingu (cieńsze). `Light2D`/`PointLight2D` + `LightOccluder2D` działają w Compatibility; `CanvasModulate` do przyciemniania. `texture_filter = NEAREST` dla pixel-artu (projekt: ustawienie w project.godot lub per węzeł).
- Glow `WorldEnvironment`: od 4.6 domyślnie tryb **Screen**, intensywność 0.3 → jaśniej niż dawniej; w Compatibility glow też działa, sprawdź wygląd.
- Pixel-perfect: `snap_2d_transforms_to_pixel`/`snap_2d_vertices_to_pixel` w project settings; kamera: `position_smoothing_enabled`, `limit_*`, losowy shake przez `offset`.

## Multiplayer (ENet + Steam w tym projekcie)

- Wysoki poziom: `multiplayer.multiplayer_peer = ENetMultiplayerPeer`, `create_server(port, max)` / `create_client(ip, port)`; `multiplayer.is_server()`, `get_unique_id()`, sygnały `peer_connected/peer_disconnected/connected_to_server/connection_failed/server_disconnected`. Port gry **8910**.
- `@rpc("any_peer"|"authority", "call_local"|"call_remote", "reliable"|"unreliable"|"unreliable_ordered", channel)`. Wołanie: `foo.rpc()`, `foo.rpc_id(peer)`. **Sygnatury RPC i ścieżki węzłów muszą być identyczne u wszystkich peerów**; po stronie serwera waliduj `multiplayer.get_remote_sender_id()`.
- `MultiplayerSpawner` (spawn_function / `spawn_path`, lista scen) + `MultiplayerSynchronizer` (`ReplicationConfig`: tryby ALWAYS/ON_CHANGE/NEVER, `replication_interval`). Autorytet: `set_multiplayer_authority(id)`; node z synchronizerem u gracza = autorytet klienta, reszta świata = serwer.
- Wzorzec projektu: **serwer rozstrzyga pociski i obrażenia**, klient robi predykcję i tylko rysuje; kompensacja opóźnienia w `lag_comp.gd`. Nie dodawaj logiki gameplayowej po stronie klienta bez walidacji serwera.
- **GodotSteam 4.23** (GDExtension w `addons/godotsteam/`, już zawiera `SteamMultiplayerPeer`) — nie dodawaj drugiego addonu steam-multiplayer-peer. Kod: `steam_net.gd`.
- Headless host+klient lokalnie do testów: dwa procesy `godot --headless --path . -- --host ...` i `-- --join=127.0.0.1 ...`.

## UI

- `Control` + kontenery (`VBoxContainer`, `HBoxContainer`, `GridContainer`, `MarginContainer`, `PanelContainer`), `anchors_preset`, `size_flags_*`, `custom_minimum_size`. Motyw w kodzie: `ui_theme.gd`. `Theme` przez `add_theme_*_override`.
- Fokus: `grab_focus()`; w 4.6 ma opcjonalny parametr — nie zakładaj starej sygnatury w nadpisaniach. `LineEdit.edit()` ma `hide_focus`.
- Pauza: `get_tree().paused = true`; węzły UI menu pauzy: `process_mode = PROCESS_MODE_WHEN_PAUSED`/`ALWAYS`. W co-opie świat idzie dalej (projekt nie pauzuje w sieci).
- Skalowanie: stałe `UI_SCALE`/`CROSS_SCALE` w kodzie; kontrolki rysowane w przestrzeni viewportu 640×360 (nie okna).
- `RichTextLabel.add_image` w 4.7: szerokość/wysokość `float`, `width_unit`/`height_unit` (`ImageUnit`) zamiast `*_in_percent`.

## Input

- Akcje i ich klawisze są w rejestrze `actions.gd` (`DEFS`), rejestruje je `input_setup.gd` (autoload); nową akcję dopisz tam, a nazwę klawisza w tekstach podawaj przez `Actions.key("id")` / `Actions.fmt("Hold [{interact}]")`, nie literałem. `Input.is_action_pressed/just_pressed`, `get_vector("left","right","up","down")`. Zdarzenia: `_unhandled_input(event)` dla gameplayu, `_input` tylko gdy musisz przechwycić; `get_viewport().set_input_as_handled()`.
- 4.7: device id myszy/klawiatury to `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD` (nie `0`).
- Mikrofon: `AudioStreamMicrophone` + `AudioEffectCapture` na szynie, `driver/enable_input=true` (jest w project.godot). Przetwarzanie lokalne, nic nie wysyłać.

## Audio

- Szyny w `default_bus_layout.tres`; `AudioServer.set_bus_volume_db`, `linear_to_db`. `AudioStreamPlayer2D` dla pozycyjnych (attenuation, `max_distance`). Muzyka stemowa: `AudioStreamSynchronized`/`AudioStreamInteractive` albo własny miks (`audio_director.gd`). Efekty szyn: `AudioEffectReverb`, `LowPassFilter`, `Capture`.
- Zob. `prototype/AUDIO.md` (manifest, generowanie przez `tools/bake_*.py`).

## Zasoby, sceny, zapis

- `preload` dla stałych ścieżek (kompilacja), `load`/`ResourceLoader.load_threaded_request` dla dużych. Instancje: `scene.instantiate()`; zwalnianie `queue_free()`; `add_child(n)` po ustawieniu właściwości, `call_deferred("add_child", n)` w callbackach fizyki.
- `user://` na zapis (`ConfigFile` → `user://settings.cfg`). Nie pisz do `res://` w eksporcie.
- 4.6+: `.tscn` zawiera unikalne ID węzłów, brak `load_steps` — diffy mogą hałasować po otwarciu w edytorze; nie „naprawiaj" ich.
- Grafika: pixel-art wypalany skryptami `tools/*.py` (Python) → `art/`. Edytuj generatory, nie wynikowe PNG, jeśli istnieje skrypt.

## Eksport i testy (komendy projektu)

```bash
godot --headless --path prototype --import                       # import po zmianach zasobów
godot --headless --path prototype --export-release "Linux"       # -> build/linux/
godot --headless --path prototype --export-release "Windows"     # -> build/windows/
prototype/tools/test_weapons.sh                                  # testy broni (~3 min)
godot --headless --path prototype -- --maptest --autoquit=4      # kształt map + osiągalność
godot --headless --path prototype -- --host --mission=z1_m2 --gentest --autoquit=35
godot --headless --path prototype -- --nightshift --host --shifttest --autoquit=8
```

- Argumenty użytkownika po `--`; `--autoquit=N` kończy po N sekundach. Kod wyjścia ≠ 0 = błąd.
- Szablony eksportu 4.7.2 muszą być zainstalowane. Presety: `export_presets.cfg`.
- `--headless` nie ma audio ani renderu; zrzuty ekranu: `tools/shot_*.gd` (wymagają okna).

## Konwencje repo

- Komentarze i teksty projektowe **po polsku**; kod/identyfikatory po angielsku; doc-komentarze `##`.
- Nowe mapy to dane (`scripts/maps/<id>.gd`, siatka ASCII) + wpis w `MAPS`/`CAMPAIGN` w `level.gd`; po zmianie uruchom `--maptest`.
- Autoloady (project.godot): `InputSetup, Settings, NoiseMgr, Audio, Feel, Arsenal, Scrap, Difficulty, Voice, LagComp, Director`. Nowy globalny stan → rozważ najpierw istniejący autoload.
- Statystyki w UI (kodeks, bronie) liczone z danych (`Enemy.KINDS`, `WeaponDef`) — nie duplikuj liczb w tekstach.
- Przy zmianie mechaniki zaktualizuj `README.md`/`GDD.md`/`WEAPONS.md`, jeśli ją opisują.

## Źródła

- [Upgrading 4.6 → 4.7](https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html)
- [Upgrading 4.5 → 4.6](https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.6.html)
- [Dokumentacja klas 4.7](https://docs.godotengine.org/en/4.7/classes/index.html)
