"""Składa sprite'y przedmiotów HD z renderów tools/concept/items_proc_bake.py (albedo, normalne świata, emisja, AO) do art/items/:
  <nazwa>.png        albedo × okluzja + ciemny obrys 2 px,
  <nazwa>_n.png      mapa normalnych w przestrzeni ekranu (kamera z −Y: (Nx, Nz, −Ny)),
  <nazwa>_glow.png   warstwa świecąca (diody, ekrany, żarówki; tylko gdy model coś emituje),
  items.json         ramka, px na piksel świata i punkt „stóp" (środek dołu bryły) każdego przedmiotu.
Uruchomienie (Pillow + numpy): python prototype/tools/pack_items_hd.py KATALOG_RENDERÓW [nazwa ...]
Przedmioty z Tripo (warsztat, złom) renderuje prop_tripo_bake.py i dołącza do items.json przez --extra=nazwa:prefix:ppw[:KAMERA] (KAMERA = −Y domyślnie | +X | −X | +Y; nazwa pliku wynikowego = ostatni człon prefiksu, więc prefiks musi się nazywać tak jak przedmiot).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "items")
OUTLINE = (20, 14, 24)
AO_STRENGTH = 0.8


def pack(src, name, ppw, has_ao=True, cam="-Y"):
    color = Image.open(f"{src}/{name}.png").convert("RGBA")
    nw = Image.open(f"{src}/{name}_nw.png").convert("RGBA")
    solid = color.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    rgb = np.asarray(color.convert("RGB")).astype(np.float32) / 255.0
    ao_path = f"{src}/{name}_ao.png"
    if has_ao and os.path.exists(ao_path):
        ao = np.asarray(Image.open(ao_path).convert("RGB")).astype(np.float32)[..., :1] / 255.0
        rgb = rgb * (1.0 - AO_STRENGTH * (1.0 - ao))
    ring = solid.filter(ImageFilter.MaxFilter(5))
    alb = Image.fromarray((np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB")
    alb.putalpha(solid)
    out = Image.new("RGBA", color.size, OUTLINE + (0,))
    out.putalpha(ring)
    out.alpha_composite(alb)
    n = np.asarray(nw.convert("RGB")).astype(np.float32) / 255.0 * 2.0 - 1.0
    maps = {"-Y": (n[..., 0], n[..., 2], -n[..., 1]), "+Y": (-n[..., 0], n[..., 2], n[..., 1]),
            "+X": (n[..., 1], n[..., 2], n[..., 0]), "-X": (-n[..., 1], n[..., 2], -n[..., 0])}
    scr = np.stack(maps[cam], -1)
    scr /= np.maximum(np.linalg.norm(scr, axis=-1, keepdims=True), 1e-4)
    nrgb = ((scr * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)
    nrgb = np.where((np.asarray(solid) > 0)[..., None], nrgb, np.array([128, 128, 255], np.uint8))
    nimg = Image.fromarray(nrgb, "RGB")
    nimg.putalpha(ring)
    os.makedirs(ART, exist_ok=True)
    out.save(f"{ART}/{name}.png")
    nimg.save(f"{ART}/{name}_n.png")
    glow = False
    em_path = f"{src}/{name}_em.png"
    if os.path.exists(em_path):
        em = np.asarray(Image.open(em_path).convert("RGB")).astype(np.float32) / 255.0
        mx = em.max(-1)
        m = np.where(np.asarray(solid) > 0, np.clip(mx * 3.0, 0, 1), 0.0)
        if m.max() > 0.05:
            col = em / np.maximum(mx[..., None], 1e-4)
            g = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
            g.putalpha(Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.8)))
            g.save(f"{ART}/{name}_glow.png")
            glow = True
    return glow


def main():
    src = sys.argv[1]
    names = [a for a in sys.argv[2:] if not a.startswith("--")]
    man = json.load(open(f"{src}/items.json"))
    dest = f"{ART}/items.json"
    cur = json.load(open(dest)) if os.path.exists(dest) else {}
    for name, info in man.items():
        if names and name not in names:
            continue
        info["glow"] = pack(src, name, info["ppw"])
        cur[name] = info
        print("OK", name, info["w"], info["h"], "glow" if info["glow"] else "")
    for a in sys.argv[2:]:
        if a.startswith("--extra="):
            parts = a.split("=", 1)[1].split(":")
            name, prefix, ppw = parts[:3]
            cam = parts[3] if len(parts) > 3 else "-Y"
            img = Image.open(prefix + ".png")
            pack(os.path.dirname(prefix), os.path.basename(prefix), float(ppw), has_ao=False, cam=cam)
            cur[name] = {"w": img.width, "h": img.height, "ppw": float(ppw), "glow": False}
    json.dump(cur, open(dest, "w"), indent=1, sort_keys=True)


main()
