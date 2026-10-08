"""Składa sprite broni HD z renderów tools/concept/gun_tripo_bake.py: art/sprites/gunhd_<nazwa>.png (albedo + obrys 3 px) i gunhd_<nazwa>_n.png (normalne w przestrzeni ekranu).
Uruchomienie (Pillow + numpy): python prototype/tools/pack_gun_hd.py PREFIX NAZWA [--cam=+X|-X|+Y|-Y] [--out=ŚCIEŻKA_W_art/]
Mapowanie normalnych świata → ekran zależy od strony kamery: +X → (Ny, Nz, Nx), −X → (−Ny, Nz, −Nx), −Y → (Nx, Nz, −Ny), +Y → (−Nx, Nz, Ny).
Domyślnie wynik to art/sprites/gunhd_NAZWA(.png|_n.png); z --out=world/prop_fence zapisze art/world/prop_fence(.png|_n.png) (rekwizyty świata HD, tools/concept/prop_tripo_bake.py).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "sprites")
OUTLINE = (20, 14, 24)


def main():
    prefix, name = sys.argv[1:3]
    cam = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--cam=")), "+X")
    color = Image.open(prefix + ".png").convert("RGBA")
    nw = Image.open(prefix + "_nw.png").convert("RGBA")
    solid = color.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    ring = solid.filter(ImageFilter.MaxFilter(7))
    out = Image.new("RGBA", color.size, OUTLINE + (0,))
    out.putalpha(ring)
    out.alpha_composite(Image.merge("RGBA", (*color.convert("RGB").split(), solid)))
    n = np.asarray(nw.convert("RGB")).astype(np.float32) / 255.0 * 2.0 - 1.0
    maps = {"+X": (n[..., 1], n[..., 2], n[..., 0]), "-X": (-n[..., 1], n[..., 2], -n[..., 0]),
            "-Y": (n[..., 0], n[..., 2], -n[..., 1]), "+Y": (-n[..., 0], n[..., 2], n[..., 1])}
    scr = np.stack(maps[cam], -1)
    scr /= np.maximum(np.linalg.norm(scr, axis=-1, keepdims=True), 1e-4)
    rgb = ((scr * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)
    rgb = np.where((np.asarray(solid) > 0)[..., None], rgb, np.array([128, 128, 255], np.uint8))
    nimg = Image.fromarray(rgb, "RGB")
    nimg.putalpha(ring)
    dest = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--out=")), None)
    base = os.path.join(ART, "..", dest) if dest else os.path.join(ART, f"gunhd_{name}")
    out.save(base + ".png")
    nimg.save(base + "_n.png")
    print("OK", name, out.size)


main()
