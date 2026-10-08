"""Składa arkusze wrogów HD z klatek tools/concept/monster_tripo_bake.py: art/sprites/<kind>_hd.png (albedo + obrys), _hd_n.png (normalne w przestrzeni ekranu),
_hd_glow.png (świecące oczy: nasycone żółte/pomarańczowe piksele albedo) + wpis w art/sprites.json (gęstość 8 px na piksel świata, skala 0,125).
Uruchomienie (Pillow + numpy): python prototype/tools/pack_monsters_hd.py FRAMES_DIR KIND CAM
    CAM jak w bake (−Y → normalne (Nx, Nz, −Ny); +X → (Ny, Nz, Nx)). Układ i fps animacji bierzemy ze starego arkusza KIND w manifeście.
"""
import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art")
OUTLINE = (18, 12, 20)


def glow_mask(rgb, alpha):
    """Świecące oczy: piksele o odcieniu żółto-pomarańczowym, dużej nasyceniu i jasności (bez kości/rogów, które są kremowe)."""
    r, g, b = [rgb[..., i].astype(np.float32) / 255.0 for i in range(3)]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-4), 0)
    hue = np.zeros_like(mx)
    d = np.maximum(mx - mn, 1e-4)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    return ((hue > 22) & (hue < 70) & (sat > 0.62) & (mx > 0.6) & (alpha > 0.5)).astype(np.float32)


def main():
    src, kind, cam = sys.argv[1:4]
    mpath = os.path.join(ART, "sprites.json")
    manifest = json.load(open(mpath))
    old = manifest["sheets"][kind]
    anims = old["anims"]
    first = next(iter(anims))
    probe = Image.open(os.path.join(src, f"{kind}_{first}_0.png"))
    fw, fh = probe.size
    cols = max(a["frames"] for a in anims.values())
    sheet = Image.new("RGBA", (cols * fw, len(anims) * fh), (0, 0, 0, 0))
    nsheet = Image.new("RGBA", (cols * fw, len(anims) * fh), (128, 128, 255, 0))
    gsheet = Image.new("RGBA", (cols * fw, len(anims) * fh), (0, 0, 0, 0))
    info = {}
    for row, (an, a) in enumerate(anims.items()):
        for i in range(a["frames"]):
            c = Image.open(os.path.join(src, f"{kind}_{an}_{i}.png")).convert("RGBA")
            nw = Image.open(os.path.join(src, f"{kind}_{an}_{i}_n.png")).convert("RGBA")
            solid = c.getchannel("A").point(lambda v: 255 if v > 90 else 0)
            ring = solid.filter(ImageFilter.MaxFilter(5))
            col = Image.new("RGBA", c.size, OUTLINE + (0,))
            col.putalpha(ring)
            col.alpha_composite(Image.merge("RGBA", (*c.convert("RGB").split(), solid)))
            n = np.asarray(nw.convert("RGB")).astype(np.float32) / 255.0 * 2.0 - 1.0
            maps = {"-Y": (n[..., 0], n[..., 2], -n[..., 1]), "+Y": (-n[..., 0], n[..., 2], n[..., 1]),
                    "+X": (n[..., 1], n[..., 2], n[..., 0]), "-X": (-n[..., 1], n[..., 2], -n[..., 0])}
            scr = np.stack(maps[cam], -1)
            scr /= np.maximum(np.linalg.norm(scr, axis=-1, keepdims=True), 1e-4)
            rgb = ((scr * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)
            rgb = np.where((np.asarray(solid) > 0)[..., None], rgb, np.array([128, 128, 255], np.uint8))
            nimg = Image.fromarray(rgb, "RGB")
            nimg.putalpha(ring)
            gm = glow_mask(np.asarray(c.convert("RGB")), np.asarray(solid).astype(np.float32) / 255.0)
            gimg = Image.fromarray((gm * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
            glow = Image.merge("RGBA", (*c.convert("RGB").split(), gimg))
            sheet.alpha_composite(col, (i * fw, row * fh))
            nsheet.alpha_composite(nimg, (i * fw, row * fh))
            gsheet.alpha_composite(glow, (i * fw, row * fh))
        info[an] = dict(a)
        info[an]["row"] = row
    name = kind + "_hd"
    sheet.save(os.path.join(ART, "sprites", name + ".png"))
    nsheet.save(os.path.join(ART, "sprites", name + "_n.png"))
    gsheet.save(os.path.join(ART, "sprites", name + "_glow.png"))
    manifest["sheets"][name] = {"frame": [fw, fh], "glow": True, "anims": info, "scale": 0.125, "hd": True, "normal": True}
    json.dump(manifest, open(mpath, "w"), indent=1)
    print("OK", name, sheet.size, "glow px:", int((np.asarray(gsheet)[..., 3] > 40).sum()))


main()
