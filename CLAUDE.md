# Dead Air '87

Co-op horror run-and-gun (retro Contra), Godot **4.7.2**, GDScript, symulacja 2D z obrazem wyłącznie w 3D (`view3d.gd`; widoku 2D i grafiki klasycznej już nie ma — tylko tryb headless nic nie rysuje); renderer Forward+ (Vulkan / D3D12; `--rendering-driver opengl3` wymusza tryb zgodności, np. pod xvfb). Cały projekt w `prototype/` (`godot --path prototype`). Opis gry: `GDD.md`, historia zmian: `CHANGELOG.md`, opis prototypu i flag CLI: `prototype/README.md`.

## Zasady

- **Tylko 3D.** Wszystko, co widać w świecie gry, robimy w 3D: modele, światła, cząsteczki, ogień, dym, krew, pociski, efekty. Nie dodawaj nowych elementów rysowanych w 2D (`_draw`, `Sprite2D`, `CPUParticles2D`, `PointLight2D`) nałożonych na scenę 3D; istniejące zastępuj odpowiednikami 3D, gdy ich dotykasz. Wyjątek: interfejs (HUD, menu, celownik, etykiety i paski nad postaciami). Symulacja (fizyka, AI, sieć) zostaje 2D.
- Komentarze i teksty projektowe po polsku; identyfikatory po angielsku; doc-komentarze `##`.
- Wiedza o Godocie 4.7 i konwencje kodu: skill `godot`. Blender (headless, sprite'y): skill `blender`.
- Hook `.claude/hooks/gd-check.sh` po edycji `.gd` uruchamia projekt headless i ostrzega o błędach skryptów — traktuj ostrzeżenie poważnie.
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
godot --headless --path prototype -- --host --stalkertest --autoquit=70   # Stalker: ostrzał, teren, po ciosie (~45 s), ma wypisać PASS
godot --headless --path prototype -- --host --enemytest --autoquit=40     # wrogowie i hałas (walidacja, zasięgi, XP przywołanych, ~10 s), ma wypisać PASS
godot --headless --path prototype -s tools/test_sound_grid.gd   # droga dźwięku po mapie, ma wypisać PASS
godot --headless --path prototype -s tools/test_audio_loops.gd  # pętle dźwięku na całej długości, ma wypisać PASS
godot --headless --path prototype -s tools/test_aim_points.gd   # wylot pocisku: niezależny od animacji i zgodny z lufą modelu, ma wypisać PASS
godot --headless --path prototype -s tools/test_proportions.gd  # hitboxy kontra modele, meble i znajdźki w naturalnej skali, anatomia postaci, ma wypisać PASS
prototype/tools/test_weapons.sh                                 # bronie + sieć (~3 min)
```

CI (`.github/workflows/tests.yml`) odpala te testy na każdym PR.

## Git

Praca na gałęziach, PR do `main` (bez bezpośrednich commitów na `main`).
