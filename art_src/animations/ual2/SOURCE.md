# Universal Animation Library 2 (Standard) — Quaternius

- Autor: Quaternius (https://quaternius.com, podgląd klipów: https://quaternius.com/animviewer.html)
- Licencja: CC0 1.0 (domena publiczna) — `License.txt` z paczki
- Pobrano 2026-10-13 z https://opengameart.org/content/universal-animation-library-2 (`universal_animation_library_2standard.zip`, 10,3 MB)
- W repo jest tylko wersja glTF z katalogu `Unreal-Godot/` paczki: `UAL2_Standard.glb` (43 klipy, szkielet w układzie Unreal: `pelvis`, `spine_01`…).
  Paczka zawiera też te same klipy w FBX dla Unity oraz manekin kobiety — pominięte.

Gra używa stąd klipów zombie (`Zombie_Walk_Fwd_Loop`, `Zombie_Scratch`) dla wrogów dwunożnych. Klipy przenosi na szkielet gry
`prototype/tools/prep_anim3d.py` (`--list` pokazuje nazwy klipów), wynik trafia do `prototype/art/char3d/anim/`.
