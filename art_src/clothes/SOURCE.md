# Ubrania szyte symulacją tkaniny — próba

Pliki generuje `prototype/tools/cloth_jacket.py` (Blender + MPFB2, bez sieci i usług płatnych); wynik w całości nasz.
Na postać zakłada je `prototype/tools/char_mpfb.py --sewn` (domyślnie wyłączone — modele w `art/char3d/mpfb/` mają ubrania z paczek MPFB).

| Plik | Postać | Co to |
|---|---|---|
| `male_scav_m65.glb` | `male_scav` | kurtka polowa M65 w kamuflażu leśnym: ułożona symulacją tkaniny na ciele MPFB (A-poza, przestrzeń MPFB przed skalowaniem do wzrostu), ok. 6,4 tys. trójkątów; kieszenie z patkami, listwa z napami, pagony, podwinięcie i mankiety wypieczone w mapę normalnych i okluzję; UV jak wykrój (rękawy, przody, tył, stójka) |

Odtworzenie: `blender -b -P prototype/tools/cloth_jacket.py -- male_scav` (ok. 1,5 min; podglądy w `build/cloth/`).
