# Dead Air '87

Co-op horror run-and-gun (retro Contra), Godot **4.7.2**, GDScript, 2D, GL Compatibility. Cały projekt w `prototype/` (`godot --path prototype`). Opis gry: `GDD.md`, opis prototypu i flag CLI: `prototype/README.md`.

## Zasady

- Komentarze i teksty projektowe po polsku; identyfikatory po angielsku; doc-komentarze `##`.
- Wiedza o Godocie 4.7 i konwencje kodu: skill `godot`. Blender (headless, sprite'y): skill `blender`.
- Hook `.claude/hooks/gd-check.sh` po edycji `.gd` uruchamia projekt headless i ostrzega o błędach skryptów — traktuj ostrzeżenie poważnie.
- Nowy `.gd` tworzy `.gd.uid` — commituj oba. `.godot/` i `build/` są w `.gitignore`.
- Grafikę i audio generują skrypty Pythona w `prototype/tools/` — edytuj generatory, nie wynikowe pliki.
- Gameplay w sieci rozstrzyga serwer (pociski, obrażenia); klient robi predykcję i rysuje. Nie dodawaj logiki bez walidacji serwera.
- Zmieniasz mechanikę → zaktualizuj `README.md` / `GDD.md` / `WEAPONS.md`, jeśli ją opisują.

## Testy (headless)

```bash
godot --headless --path prototype --import                      # po zmianach zasobów
godot --headless --path prototype -- --maptest --autoquit=4     # mapy (~6 s), ma wypisać PASS
prototype/tools/test_weapons.sh                                 # bronie + sieć (~3 min)
```

CI (`.github/workflows/tests.yml`) odpala oba testy na każdym PR.

## Git

Praca na gałęziach, PR do `main` (bez bezpośrednich commitów na `main`).
