# 100STYLE — mocap stylów chodu (Ian Mason)

- Autor: Ian Mason, University of Edinburgh — „The 100STYLE Dataset”, https://www.ianxmason.com/100style/
- Pobrano 2026-11-27 z Zenodo (rekord 8127870), pliki BVH pojedynczych stylów wyjęte z archiwum `100STYLE.zip` (HTTP Range).
- Licencja: **CC BY 4.0** — wolno komercyjnie, wymagane podanie autora (dopisek w `prototype/art/char3d/anim/CREDITS.md`).
- Nagrania: Xsens, 60 kl./s, jeden wykonawca; szkielet `Hips`, `Chest`–`Chest4`, `Neck`, `Head`, `*Collar`, `*Shoulder` (ramię), `*Elbow`,
  `*Wrist`, `*Hip`, `*Knee`, `*Ankle`, `*Toe`. `Frame_Cuts.csv` z archiwum podaje granice ujęć (FW / FR / BW / BR / SW / SR / ID).

Surowe BVH nie są w repo (rozmiar); lokalnie leżą w `C:\deadair87\char_src\mocap\100STYLE\<Styl>\`. Wybór klipów: VOICE_MOCAP_PLAN.md B1
(strona porównania z filmami `tools/shot_mocap.gd`), w grze od 1.7.709.

| Plik gry | Źródło | Polecenie (z korzenia repo) |
|---|---|---|
| `idle_swat.glb` (stan `idle`) | `Swat/Swat_ID.bvh`, ujęcie 636–1395 | `blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=<100STYLE>/Swat/Swat_ID.bvh --range=636:1395 --loop=3.5:6.0 --yaw=-14 --name=idle_swat` |
| `crouch_run_toes.glb` (stan `crouch_walk`, od 1.7.711) | `OnToesCrouched/OnToesCrouched_FR.bvh`, ujęcie 446–4722 | `blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=<100STYLE>/OnToesCrouched/OnToesCrouched_FR.bvh --range=446:4722 --loop=0.4:1.2 --step-sync --name=crouch_run_toes` |

W 1.7.709–1.7.710 marsz w kucaniu grał `crouch_walk_toes.glb` (`OnToesCrouched_FW`, ujęcie 409–8991, `--loop=0.7:2.0`): krok ok. 0,55 m
przy 3,7 m/s gry dawał rozkrok albo ślizg — wersja biegnąca (FR) ma krok ok. 1 m, a tempo i długość kroku dobiera `char3d.gd` (`GAIT`).

Zmiany względem nagrania: wycięta jedna pętla (postój 3,5 s, krok w kucaniu 0,8 s), ruch w miejscu, obrót przodem do kierunku gry
(postój dodatkowo o 14°, żeby barki były skręcone jak w pozie celowania), przeniesienie na szkielet postaci gry; w grze marsz w kucaniu
ma biodra niżej (`drop` w `char_clips.gd`), żeby sylwetka miała wysokość hitboxa kucania.
