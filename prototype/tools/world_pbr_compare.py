"""Porównanie tekstur świata: obecna (prototype/art/world3d) vs kandydaci z Poly Haven po tym samym gradingu co w grze (`world_pbr_import.py`).

Uruchomienie (z korzenia repo, Python z numpy, Pillow, scipy):
    python prototype/tools/world_pbr_compare.py [--out=art_src/world_pbr_cc0/compare] [materiał ...]
bez argumentów porównuje wszystkie materiały z SETS. Dla każdego materiału powstaje arkusz tex_<materiał>.png: obecna tekstura w lewym górnym rogu,
obok kandydaci; każdy kafel pokazuje PATCH_M × PATCH_M m powierzchni w skali rzeczywistej (kafel obecnej tekstury = 1 / `per_m` z `level3d.gd`,
kandydata — wymiar zasobu z API), z oświetleniem podglądu `world_pbr_gen.lit` i średnią luminancją albedo (grading wyrównuje ją do celu).
Pobrane mapy trafiają do art_src/world_pbr_cc0/polyhaven/<id>/ (katalog ignorowany przez git).
Podgląd jest płaski (jedno światło), więc nie zastępuje zrzutów w grze: decyzję podejmuje się po zdjęciach z tych samych ujęć przed i po.
"""
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
os.chdir(ROOT)
sys.path.insert(0, HERE)
import world_pbr_gen as G  # noqa: E402
import world_pbr_import as W  # noqa: E402

CACHE = os.path.join(ROOT, "art_src", "world_pbr_cc0", "polyhaven")
UA = {"User-Agent": "dead-air-87-asset-fetch/1.0"}
PATCH_M = 3.0          # bok pokazywanego kawałka powierzchni [m]
PX = 640               # bok kafla arkusza [px]

# materiał gry → (rozmiar kafla obecnej tekstury [m] = 1 / per_m z level3d.gd, kandydaci z Poly Haven)
SETS = {
    "concrete": (1 / 0.33, ["concrete_floor_worn_001", "dirty_concrete", "concrete_wall_008"]),
    "metal": (1 / 0.40, ["metal_plate", "rusty_metal_03", "rusty_metal_05"]),
    "terrain": (1 / 0.30, ["forrest_ground_01", "leaves_forest_ground", "brown_mud_leaves_01"]),
    "wall": (1 / 0.70, ["dark_brick_wall", "red_brick_03", "worn_brick_wall"]),
}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def fetch(aid):
    """Mapy 1K (kolor, normalne GL, ARM albo roughness + AO) zasobu `aid`; zwraca katalog i rozmiar kafla w metrach."""
    d = os.path.join(CACHE, aid)
    os.makedirs(d, exist_ok=True)
    size_m = float(json.loads(get("https://api.polyhaven.com/info/" + aid))["dimensions"][0]) / 1000.0
    files = json.loads(get("https://api.polyhaven.com/files/" + aid))
    for key, tag in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm"), ("Rough", "rough"), ("AO", "ao")):
        p = os.path.join(d, tag + ".jpg")
        if key in files and not os.path.exists(p):
            with open(p, "wb") as f:
                f.write(get(files[key]["1k"]["jpg"]["url"]))
    return d, size_m


def load_candidate(name, aid):
    d, size_m = fetch(aid)
    col = Image.open(os.path.join(d, "diff.jpg")).convert("RGB")
    w, h = col.size
    alb = np.asarray(col, np.float32) / 255.0
    nrm = np.asarray(Image.open(os.path.join(d, "nor.jpg")).convert("RGB").resize((w, h)), np.float32) / 255.0
    arm = os.path.join(d, "arm.jpg")
    if os.path.exists(arm):
        orm = np.asarray(Image.open(arm).convert("RGB").resize((w, h)), np.float32) / 255.0
    else:                                       # brak ARM: roughness + AO, metaliczność 0
        rough = np.asarray(Image.open(os.path.join(d, "rough.jpg")).convert("L").resize((w, h)), np.float32) / 255.0
        ao_p = os.path.join(d, "ao.jpg")
        ao = np.asarray(Image.open(ao_p).convert("L").resize((w, h)), np.float32) / 255.0 if os.path.exists(ao_p) else np.ones((h, w), np.float32)
        orm = np.dstack([ao, rough, np.zeros((h, w), np.float32)])
    alb = W.grade(alb, W.GRADE[name])
    alb, nrm, orm = W.square(alb), W.square(nrm), W.square(orm)
    alb, nrm, orm, _ = W.finish(alb, nrm, orm, None, name)
    return alb, nrm, orm, size_m


def load_current(name):
    base = os.path.join(ROOT, "prototype", "art", "world3d", name)
    return tuple(np.asarray(Image.open(f"{base}_{k}.png").convert("RGB"), np.float32) / 255.0 for k in ("albedo", "normal", "orm"))


def srgb_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def patch(alb, nrm, orm, size_m):
    """Kawałek PATCH_M × PATCH_M m: kafel powtórzony tyle razy, ile mieści się w tej powierzchni (okresowo, więc bez szwów)."""
    lit = G.lit(alb, nrm, orm)
    h, w = lit.shape[:2]
    reps = PATCH_M / size_m
    ix = (np.arange(PX) / PX * reps * w).astype(int) % w
    iy = (np.arange(PX) / PX * reps * h).astype(int) % h
    lum = float((srgb_lin(alb) * np.array([0.2126, 0.7152, 0.0722])).sum(-1).mean())
    return Image.fromarray(G.to8(lit[iy][:, ix])), lum


def main():
    args = sys.argv[1:]
    out = next((a.split("=", 1)[1] for a in args if a.startswith("--out=")), os.path.join("art_src", "world_pbr_cc0", "compare"))
    names = [a for a in args if not a.startswith("--")] or list(SETS)
    os.makedirs(out, exist_ok=True)
    try:
        f, fb = ImageFont.truetype("arial.ttf", 20), ImageFont.truetype("arialbd.ttf", 24)
    except OSError:
        f = fb = ImageFont.load_default()
    for name in names:
        cur_size, cands = SETS[name]
        tiles = []
        im, lum = patch(*load_current(name), cur_size)
        tiles.append((im, f"OBECNY: {name}", f"luminancja {lum:.3f}, kafel {cur_size:.1f} m"))
        for aid in cands:
            a, n, o, size_m = load_candidate(name, aid)
            im, lum = patch(a, n, o, size_m)
            tiles.append((im, aid, f"luminancja {lum:.3f}, kafel {size_m:.1f} m"))
        rows = (len(tiles) + 1) // 2
        sheet = Image.new("RGB", (PX * 2 + 6, (PX + 62) * rows), (18, 18, 20))
        d = ImageDraw.Draw(sheet)
        for i, (im, t1, t2) in enumerate(tiles):
            x, y = (i % 2) * (PX + 6), (i // 2) * (PX + 62)
            sheet.paste(im, (x, y + 56))
            d.text((x + 10, y + 4), t1, font=fb, fill=(240, 200, 120))
            d.text((x + 10, y + 30), t2, font=f, fill=(200, 200, 200))
        path = os.path.join(out, f"tex_{name}.png")
        sheet.save(path)
        print("SHEET", path)


if __name__ == "__main__":
    main()
