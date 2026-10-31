"""Tło ekranu startowego (MAIN_MENU_PLAN.md P0): key art z klatki gry + kafelek mgły dla `menu_stage.gd`.

Źródło: `art_src/menu/keyart_z1_m1_c125.png` (LFS) — zrzut widoku 3D 3840×2160, zaakceptowany 31.10.2026:
  godot --path prototype -- --host --port=8931 --mission=z1_m1 --nohud --look=0 --shotweather=clear --shotzoom=1.6 --shotat=125 --shot=PLIK
(poza postaci zmienia się między przebiegami — nowy zrzut trzeba obejrzeć przed podmianą źródła).

Wynik (nie edytować ręcznie):
  art/menu/backdrop.jpg — kadr 2560×1440 z gradacją w palecie gry: ekspozycja, zimne cienie i ciepłe światła, poświata ogniska,
                          przyciemniona lewa strona pod listę menu, winieta, ziarno;
  art/menu/fog.png      — biały kafelek 1024×256 z alfą (miękki pas mgły), powtarzalny w poziomie.
Pozycję ogniska w kadrze (`FIRE_UV`) zna `menu_stage.gd` — przy zmianie kadru popraw ją tam.

Użycie (z prototype/): python tools/menu_backdrop.py  → potem godot --headless --path . --import
"""
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "..", "art_src", "menu", "keyart_z1_m1_c125.png")
OUT = os.path.join(ROOT, "art", "menu")
W, H = 2560, 1440
CROP = (256, 619)                 # lewy górny róg kadru w źródle 4K: żołnierz na ~65% szerokości, stopy na ~82% wysokości
SEED = 87


def grade(src: Image.Image) -> Image.Image:
    a = np.asarray(src.convert("RGB").crop((CROP[0], CROP[1], CROP[0] + W, CROP[1] + H))).astype(np.float32) / 255
    a = np.clip(a * 2.1, 0, 1) ** 0.85                                   # ekspozycja: nocny kadr gry jest ~2× za ciemny na tło
    lum = a.mean(axis=2, keepdims=True)
    cool = np.array([0.80, 0.90, 1.12], np.float32)
    warm = np.array([1.12, 0.98, 0.82], np.float32)
    t = np.clip((lum - 0.15) / 0.5, 0, 1)
    a = a * (cool * (1 - t) + warm * t)                                  # zimne cienie, ciepłe światła
    soft = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(28))
    a = a + 0.45 * np.clip(np.asarray(soft).astype(np.float32) / 255 - 0.55, 0, 1)   # poświata ogniska
    x = np.linspace(0, 1, W, dtype=np.float32)[None, :, None]
    y = np.linspace(-1, 1, H, dtype=np.float32)[:, None, None]
    a *= 0.42 + 0.58 * np.clip((x - 0.08) / 0.42, 0, 1)                  # lewa strona pod tytuł i listę menu
    a *= 1 - 0.38 * y ** 2                                               # winieta
    a += np.random.default_rng(SEED).normal(0, 0.012, (H, W, 1)).astype(np.float32)   # ziarno
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


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
    grade(Image.open(SRC)).save(os.path.join(OUT, "backdrop.jpg"), quality=90, optimize=True)
    fog_tile().save(os.path.join(OUT, "fog.png"), optimize=True)
    print("menu_backdrop:", os.path.join(OUT, "backdrop.jpg"), os.path.join(OUT, "fog.png"))


if __name__ == "__main__":
    main()
