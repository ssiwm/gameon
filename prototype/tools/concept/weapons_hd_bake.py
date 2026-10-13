"""Seryjny bake sprite'ów broni HD (miniatury HUD / warsztatu / kodeksu, rozmiar broni na stojaku i jako łup) z modeli gry
prototype/art/char3d/gun_<klucz>.glb (tools/gun_proc.py). Długość i punkt chwytu wyliczane ze starych sprite'ów guns.png, więc rozmiary w grze
zostają jak dotąd. Z --src=tripo bierze stare modele art_src/weapons/tripo/<klucz>_01.glb.

Uruchomienie (Pillow + numpy; Blender w PATH albo w zmiennej BLENDER):
    python prototype/tools/concept/weapons_hd_bake.py OUT_DIR [--src=tripo] [--cams=klucz:CAM,...] [--only=klucz,...] [--preview]
    CAM = +X | -X | +Y | -Y (patrz gun_tripo_bake.py); domyślnie -Y dla modeli gry (lufa w +X), +X dla Tripo.
    --preview: renderuje obie strony (+X i -X) do OUT_DIR/<klucz>_<cam>.png i kończy (wybór strony modeli Tripo).
Bez --preview: bake + pack_gun_hd.py → art/sprites/gunhd_<klucz>(.png|_n.png) i _glow.png dla broni świecących.
"""
import json
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PROTO = os.path.join(ROOT, "prototype")
GUNS = Image.open(os.path.join(PROTO, "art", "sprites", "guns.png")).convert("RGBA")
ROWS = {"m83": 0, "spread12": 1, "p64": 2, "srut8": 3, "lr7": 4, "hkm9": 5, "gniew4": 6, "sokol6": 7, "widmo1": 8, "ciegno6": 9, "maczeta": 10, "kilof": 11}
# Kilof: głowica Tripo to duży łuk w płaszczyźnie zamachu (wysokość ≈ długość), więc ta sama szerokość co stary sprite (17,5 px) wypychałaby ją poza ramkę 14 px — zmniejszamy.
OVERRIDE_W = {"kilof": 12.0}
HAND = (13, 14)                          # dłoń w klatce 72×28 guns.png (weapon_view.gd HAND)
TRIPO = "--src=tripo" in sys.argv
GLOW = {"lr7": "cyan", "widmo1": "cyan", "hkm9": "red"}      # warstwa świecenia (pack_gun_hd.py --glow)
BLENDER = os.environ.get("BLENDER", "blender")


def source(key):
    if TRIPO:
        return os.path.join(ROOT, "art_src", "weapons", "tripo", f"{key}_01.glb")
    return os.path.join(PROTO, "art", "char3d", f"gun_{key}.glb")


def geometry(key):
    r = ROWS[key]
    x0, y0, x1, y1 = GUNS.crop((0, r * 28, 72, r * 28 + 28)).getbbox()
    w = OVERRIDE_W.get(key, (x1 - x0) * 0.5)   # skala sprite'a 0,5 → piksele świata
    fx = min(max((HAND[0] - x0) / float(x1 - x0), 0.0), 1.0)
    fz = min(max((HAND[1] - y0) / float(y1 - y0), 0.0), 1.0)
    return w, fx, fz


def bake(key, cam, out_dir, tag=None):
    glb = source(key)
    w, fx, fz = geometry(key)
    prefix = os.path.join(out_dir, f"{key}{'_' + tag if tag else ''}")
    subprocess.run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "gun_tripo_bake.py"), "--", glb, prefix, cam, f"{w:.2f}", f"{fx:.3f}", f"{fz:.3f}"],
                   check=True, stdout=subprocess.DEVNULL)
    return prefix, (w, fx, fz)


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    cams = dict(p.split(":") for p in next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--cams=")), "").split(",") if p)
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), list(ROWS))
    preview = "--preview" in sys.argv
    for key in only:
        if (TRIPO and key == "m83") or not os.path.exists(source(key)):      # M-83 z Tripo miał własny bake z etapu 1
            continue
        if preview:
            for cam in ("+X", "-X"):
                bake(key, cam, out_dir, cam.replace("+", "p").replace("-", "m"))
            print("preview", key)
            continue
        cam = cams.get(key, "+X" if TRIPO else "-Y")
        prefix, g = bake(key, cam, out_dir)
        subprocess.run([sys.executable, os.path.join(PROTO, "tools", "pack_gun_hd.py"), prefix, key, f"--cam={cam}"]
                       + ([f"--glow={GLOW[key]}"] if key in GLOW else []), check=True)
        print("OK", key, cam, "w=%.1f fx=%.2f fz=%.2f" % g)


if __name__ == "__main__":
    main()
