# Ubrania szyte symulacją tkaniny

Pliki generuje `prototype/tools/cloth_garments.py` (Blender + MPFB2, bez sieci i usług płatnych); wynik w całości nasz.
Na postacie zakłada je `prototype/tools/char_mpfb.py --sewn` (domyślnie wyłączone — modele w `art/char3d/mpfb/` mają ubrania z paczek MPFB).
Każde ubranie jest ułożone symulacją tkaniny na ciele MPFB danego stroju (A-poza, przestrzeń MPFB przed skalowaniem do wzrostu), z kolizją
z butami i rękawicami stroju oraz z warstwą spodnią. Detale (kieszenie, patki, napy, listwy, szlufki, nakolanniki, podwinięcia) wypieczone
w mapę normalnych i okluzję; UV jak wykrój, przeszycia w kolorze.

| Plik | Postać | Co to | Trójkąty |
|---|---|---|---|
| `male_scav_m65.glb` | `male_scav` | kurtka polowa M65 w kamuflażu leśnym: stójka, cztery kieszenie z patkami, listwa z napami, pagony, ściągacz w talii | ok. 6,4 tys. |
| `male_scav_bdu.glb` | `male_scav` | spodnie polowe BDU w kamuflażu leśnym: pas ze szlufkami, rozporek, kieszenie boczne miechowe i tylne z patkami, nakolanniki, nogawki na cholewkach | 4 tys. |
| `male_medic_emt_jacket.glb` | `male_medic` | kurtka ratownika w granacie: niska stójka, kieszenie piersiowe, listwa z napami, pagony | ok. 5,8 tys. |
| `male_medic_emt_trousers.glb` | `male_medic` | spodnie ratownika w granacie: kieszenie boczne i tylne, nogawki na butach | 4 tys. |
| `male_hazmat_coverall.glb` | `male_hazmat` | kombinezon ochronny, gumowany, żółty: zamek z listwą do krocza, kieszenie piersiowe, pas, nakolanniki, szwy podklejone taśmą | ok. 7,1 tys. |

Odtworzenie: `blender -b -P prototype/tools/cloth_garments.py -- --all` (ok. 3–4 min na strój; podglądy w `build/cloth/`).
