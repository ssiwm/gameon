"""Seryjny bake broni HD z modeli Tripo (art_src/weapons/tripo/<klucz>_01.glb): geometria (długość, punkt chwytu) wyliczana ze starych sprite'ów guns.png, więc HD pasuje do celowania.

Uruchomienie (Pillow + numpy; Blender w PATH): python prototype/tools/concept/weapons_hd_bake.py OUT_DIR [--cams=klucz:CAM,...] [--only=klucz,...] [--preview]
    CAM = +X | -X | +Y | -Y (patrz gun_tripo_bake.py); domyślnie +X. --preview: renderuje obie strony (+X i -X) do OUT_DIR/<klucz>_<cam>.png i kończy (wybór strony).
Bez --preview: bake + pack_gun_hd.py → art/sprites/gunhd_<klucz>(.png|_n.png).
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


def geometry(key):
    r = ROWS[key]
    x0, y0, x1, y1 = GUNS.crop((0, r * 28, 72, r * 28 + 28)).getbbox()
    w = OVERRIDE_W.get(key, (x1 - x0) * 0.5)   # skala sprite'a 0,5 → piksele świata
    fx = min(max((HAND[0] - x0) / float(x1 - x0), 0.0), 1.0)
    fz = min(max((HAND[1] - y0) / float(y1 - y0), 0.0), 1.0)
    return w, fx, fz


def bake(key, cam, out_dir, tag=None):
    glb = os.path.join(ROOT, "art_src", "weapons", "tripo", f"{key}_01.glb")
    w, fx, fz = geometry(key)
    prefix = os.path.join(out_dir, f"{key}{'_' + tag if tag else ''}")
    subprocess.run(["blender", "-b", "--factory-startup", "-P", os.path.join(HERE, "gun_tripo_bake.py"), "--", glb, prefix, cam, f"{w:.2f}", f"{fx:.3f}", f"{fz:.3f}"],
                   check=True, stdout=subprocess.DEVNULL)
    return prefix, (w, fx, fz)


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    cams = dict(p.split(":") for p in next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--cams=")), "").split(",") if p)
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), list(ROWS))
    preview = "--preview" in sys.argv
    for key in only:
        if key == "m83" or not os.path.exists(os.path.join(ROOT, "art_src", "weapons", "tripo", f"{key}_01.glb")):
            continue
        if preview:
            for cam in ("+X", "-X"):
                bake(key, cam, out_dir, cam.replace("+", "p").replace("-", "m"))
            print("preview", key)
            continue
        cam = cams.get(key, "+X")
        prefix, g = bake(key, cam, out_dir)
        subprocess.run([sys.executable, os.path.join(PROTO, "tools", "pack_gun_hd.py"), prefix, key, f"--cam={cam}"], check=True)
        print("OK", key, cam, "w=%.1f fx=%.2f fz=%.2f" % g)


if __name__ == "__main__":
    main()
