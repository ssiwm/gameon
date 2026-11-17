"""Tło zastępcze ekranu startowego + kafelek mgły dla `menu_stage.gd`.

Ekrany startowe pokazują żywą scenę 3D (`scripts/menu_forest.gd`: nocny las z mgłą, ścieżka do radiostacji). Tło zastępcze to
pierwsza klatka tej sceny — stoi, zanim scena się zbuduje (przenikanie musi być niewidoczne, więc bez gradacji), i na stałe
w trybie zgodności (OpenGL bez mgły wolumetrycznej) oraz headless.

Źródło: `art_src/menu/forest_radio.png` (LFS), render 2560×1440 ze stojącym czasem (`START_T` sceny):
  godot --path prototype --script tools/menu_forest_shot.gd -- --out=<repo>/art_src/menu/forest_radio.png --size=2560x1440 --wait=90
(okno — wcześniej `override.cfg` z katalogiem QA). Po każdej zmianie kadru, świateł albo mgły w `menu_forest.gd` wyrenderuj źródło
od nowa i uruchom ten skrypt. Poprzedni key art z misji 1.1 (`keyart_z1_m1_c125.png`) zostaje w `art_src/menu/` na materiały prasowe.

Wynik (nie edytować ręcznie):
  art/menu/backdrop.jpg — kadr 2560×1440 (źródło bez zmian, JPEG);
  art/menu/fog.png      — biały kafelek 1024×256 z alfą (miękki pas mgły), powtarzalny w poziomie; dryfuje nad tłem zastępczym.

Użycie (z prototype/): python tools/menu_backdrop.py  → potem godot --headless --path . --import
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "..", "art_src", "menu", "forest_radio.png")
OUT = os.path.join(ROOT, "art", "menu")
W, H = 2560, 1440
SEED = 87


def fog_tile(w: int = 1024, h: int = 256) -> Image.Image:
    """Pas mgły: szum wartości z dwóch oktaw zawinięty w poziomie (kafelek bez szwu) × miękki profil pionowy."""
    rng = np.random.default_rng(SEED)
    acc = np.zeros((h, w), np.float32)
    for cells, amp in ((8, 0.7), (24, 0.3)):
        g = rng.random((max(2, cells * h // w), cells)).astype(np.float32)
        g = np.concatenate([g, g, g], axis=1)                            # trzy kopie → środkowa po skalowaniu nie ma szwu
        big = Image.fromarray((g * 255).astype(np.uint8)).resize((w * 3, h), Image.BICUBIC)
        acc += amp * np.asarray(big).astype(np.float32)[:, w:2 * w] / 255
    y = np.linspace(-1, 1, h, dtype=np.float32)[:, None]
    alpha = np.clip(acc * 1.3 - 0.25, 0, 1) * np.exp(-(y / 0.55) ** 2)
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    src = Image.open(SRC).convert("RGB")
    if src.size != (W, H):
        src = src.resize((W, H), Image.LANCZOS)
    src.save(os.path.join(OUT, "backdrop.jpg"), quality=92, optimize=True)
    fog_tile().save(os.path.join(OUT, "fog.png"), optimize=True)
    print("menu_backdrop:", os.path.join(OUT, "backdrop.jpg"), os.path.join(OUT, "fog.png"))


if __name__ == "__main__":
    main()
