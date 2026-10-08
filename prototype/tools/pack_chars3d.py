"""Składa arkusze postaci 3D (klatki z tools/concept/char_mpfb_outfit.py --bake) w art/sprites/playerhd_<płeć>.png + wpis w art/sprites.json.

Uruchomienie (Pillow):
    blender -b --factory-startup -P prototype/tools/concept/char_mpfb_outfit.py -- FRAMES_DIR --bake
    python prototype/tools/pack_chars3d.py FRAMES_DIR
Klatka gry: 64×96 przy skali 0,25 (świat 16×24, jak dotąd). Render 256×384 jest zmniejszany 4× z wygładzeniem, a obrys (2 px = 0,5 px świata,
jak w arkuszach 2× potworów) dokładany pod sprite'em. Układ: wiersz = animacja, kolumna = klatka (zgodnie z `Sprites`).
Opcje: --hd (klatki 256×384 + arkusz normalnych NAZWA_n.png; wymaga klatek *_n.png z char_tripo_bake.py --normals), --prefix=playerhd3_ (nazwa arkusza = prefiks + płeć), --genders=male,female (nazwy plików klatek w FRAMES_DIR).
Pełny `bake_sprites.py` zachowuje wpisy `playerhd*_` z istniejącego manifestu.
"""
import json
import os
import sys

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "art")
FW, FH = 64, 96
OUTLINE = (20, 14, 24)
ANIMS = [("idle", 6, 5, True), ("run", 8, 14, True), ("jump", 1, 1, False), ("fall", 1, 1, False),
         ("crouch", 1, 1, False), ("crouch_walk", 6, 9, True), ("down", 1, 1, False)]


def finish(img):
    """256×384 RGBA → klatka 64×96 z obrysem pod sprite'em."""
    small = img.resize((FW, FH), Image.LANCZOS)
    a = small.getchannel("A")
    solid = a.point(lambda v: 255 if v > 90 else 0)
    ring = solid.filter(ImageFilter.MaxFilter(5))                 # 2 px dookoła
    out = Image.new("RGBA", (FW, FH), OUTLINE + (0,))
    out.putalpha(ring)
    out.alpha_composite(Image.merge("RGBA", (*small.convert("RGB").split(), solid)))
    return out


def finish_hd(color, normal):
    """HD: klatka 256×384 bez zmniejszania; obrys 3 px; normalne świata → przestrzeń ekranu (R=+X, G=+Z, B=−Y)."""
    import numpy as np
    a = color.getchannel("A")
    solid = a.point(lambda v: 255 if v > 90 else 0)
    ring = solid.filter(ImageFilter.MaxFilter(7))                        # 3 px dookoła
    out = Image.new("RGBA", color.size, OUTLINE + (0,))
    out.putalpha(ring)
    out.alpha_composite(Image.merge("RGBA", (*color.convert("RGB").split(), solid)))
    e = np.asarray(normal.convert("RGB")).astype(np.float32) / 255.0
    n = e * 2.0 - 1.0
    scr = np.stack([n[..., 0], n[..., 2], -n[..., 1]], -1)
    scr /= np.maximum(np.linalg.norm(scr, axis=-1, keepdims=True), 1e-4)
    rgb = ((scr * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)
    flat = np.array([128, 128, 255], np.uint8)
    mask = np.asarray(solid) > 0
    rgb = np.where(mask[..., None], rgb, flat)                            # poza sylwetką i w obrysie: płasko
    nimg = Image.fromarray(rgb, "RGB")
    nimg.putalpha(ring)
    return out, nimg


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/bake"
    prefix = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--prefix=")), "playerhd_")
    genders = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--genders=")), ["male", "female"])
    mpath = os.path.join(ART, "sprites.json")
    with open(mpath) as f:
        manifest = json.load(f)
    hd = "--hd" in sys.argv
    for gender in genders:
        if hd:
            FW2, FH2 = 256, 384
            cols = max(n for _, n, _, _ in ANIMS)
            sheet = Image.new("RGBA", (cols * FW2, len(ANIMS) * FH2), (0, 0, 0, 0))
            nsheet = Image.new("RGBA", (cols * FW2, len(ANIMS) * FH2), (128, 128, 255, 0))
            info = {}
            for row, (anim, n, fps, loop) in enumerate(ANIMS):
                for i in range(n):
                    c = Image.open(os.path.join(src, f"{gender}_{anim}_{i}.png")).convert("RGBA")
                    nm = Image.open(os.path.join(src, f"{gender}_{anim}_{i}_n.png")).convert("RGBA")
                    fc, fn = finish_hd(c, nm)
                    sheet.alpha_composite(fc, (i * FW2, row * FH2))
                    nsheet.alpha_composite(fn, (i * FW2, row * FH2))
                info[anim] = {"row": row, "frames": n, "fps": fps, "loop": loop}
            name = f"{prefix}{gender}"
            sheet.save(os.path.join(ART, "sprites", name + ".png"))
            nsheet.save(os.path.join(ART, "sprites", name + "_n.png"))
            manifest["sheets"][name] = {"frame": [FW2, FH2], "glow": False, "anims": info, "scale": 0.0625, "hd": True, "normal": True}
            print("OK HD", name, sheet.size)
            continue
        cols = max(n for _, n, _, _ in ANIMS)
        sheet = Image.new("RGBA", (cols * FW, len(ANIMS) * FH), (0, 0, 0, 0))
        info = {}
        for row, (anim, n, fps, loop) in enumerate(ANIMS):
            for i in range(n):
                fr = finish(Image.open(os.path.join(src, f"{gender}_{anim}_{i}.png")).convert("RGBA"))
                sheet.alpha_composite(fr, (i * FW, row * FH))
            info[anim] = {"row": row, "frames": n, "fps": fps, "loop": loop}
        name = f"{prefix}{gender}"
        sheet.save(os.path.join(ART, "sprites", name + ".png"))
        manifest["sheets"][name] = {"frame": [FW, FH], "glow": False, "anims": info, "scale": 0.25}
        print("OK", name, sheet.size)
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1)
    print("NASTĘPNY KROK: godot --headless --path . --import")


if __name__ == "__main__":
    main()
