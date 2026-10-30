# Wilk (Ultimate Animated Animal Pack) — Quaternius

- Autor: Quaternius (https://quaternius.com/packs/ultimateanimatedanimals.html)
- Licencja: CC0 1.0 (domena publiczna) — strona modelu: https://poly.pizza/m/P1gU3Qkr9r („Public Domain (CC0)”)
- Pobrano 2026-10-30 z https://static.poly.pizza/f1d12388-e39b-4157-b32a-646a1d089fc4.glb (964 KB) jako `Wolf.glb`
- 12 klipów: Attack, Death, Eating, Gallop, Gallop_Jump, Idle, Idle_2, Idle_2_HeadLow, Idle_HitReact_Left/Right, Jump_ToIdle, Walk
  (24 kl./s; każdy klip w pliku występuje dwa razy — z prefiksem `AnimalArmature|` i bez).

Gra nie używa modelu wilka, tylko jego ruchu: `prototype/tools/retarget_quad.py` przenosi klipy na szkielet Trzoska z Tripo
(`art_src/enemies/tripo/trzosek_01_clips.glb`), a `prep_enemy3d.py` robi z tego `prototype/art/enemy3d/trzosek.glb`.
