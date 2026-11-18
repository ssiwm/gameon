"""Obrazki pamiątek w kwaterach kryjówki (DIG_LOOT_PLAN.md K4, zestawy taśm): komplet dwóch taśm mapy wiesza na ścianie kwater
oprawioną pamiątkę z tej mapy (view3d.gd `_build_memento`). Rysowane proceduralnie (PIL), bez cudzych zdjęć:

  memento_patrol.png   — 1.1: sepiowe zdjęcie grupowe patrolu 2187 na skraju lasu (sylwetki, prześwietlone niebo, ząbkowany brzeg)
  memento_station.png  — 1.2: odręczna mapa radiostacji na papierze w kratkę: maszt, hala, linia geofonów B, czerwone kółko pod masztem
  memento_sklad.png    — 1.3: plan Składu na kalce (niebieskie linie): regały, antresola zakreślona ołówkiem, krzyżyk przy skrytce

Napisy w obrazkach to same numery i skróty (2187, 86, B, H) — nic do tłumaczenia. Ziarno stałe, więc wynik jest powtarzalny.
Użycie (z prototype/): python tools/gen_mementos.py  → potem godot --headless --path . --import i python tools/tex_vram.py (mipmapy, VRAM)
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "art", "world3d"))
W, H = 384, 288


def noise(img, amount, seed):
    rnd = random.Random(seed)
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            n = rnd.randint(-amount, amount)
            r, g, b = px[x, y][:3]
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))


def vignette(img, strength):
    px = img.load()
    cx, cy = img.width / 2, img.height / 2
    for y in range(img.height):
        for x in range(img.width):
            d = math.hypot((x - cx) / cx, (y - cy) / cy) / math.sqrt(2)
            k = 1.0 - strength * d * d
            r, g, b = px[x, y][:3]
            px[x, y] = (int(r * k), int(g * k), int(b * k))


def stains(img, seed, count, col):
    rnd = random.Random(seed)
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for _ in range(count):
        x, y = rnd.randint(0, img.width), rnd.randint(0, img.height)
        r = rnd.randint(10, 40)
        d.ellipse([x - r, y - r * 0.8, x + r, y + r * 0.8], fill=col + (rnd.randint(14, 34),))
    ov = ov.filter(ImageFilter.GaussianBlur(6))
    img.paste(ov, (0, 0), ov)


def patrol():
    """Zdjęcie grupowe: pięciu w płaszczach i hełmach przed ścianą lasu, jeden z radiostacją na plecach."""
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):                                              # niebo prześwietlone u góry, ziemia ciemniejsza
        t = y / H
        c = int(215 - 120 * t)
        d.line([(0, y), (W, y)], fill=(c, int(c * 0.86), int(c * 0.66)))
    rnd = random.Random(87)
    for i in range(46):                                             # świerki w tle
        x = rnd.randint(-10, W + 10)
        h = rnd.randint(70, 150)
        base = 168 + rnd.randint(-6, 6)
        tone = rnd.randint(70, 105)
        d.polygon([(x, base - h), (x - h * 0.22, base), (x + h * 0.22, base)], fill=(tone, int(tone * 0.84), int(tone * 0.62)))
    d.rectangle([0, 166, W, H], fill=(92, 78, 58))
    for i in range(40):                                             # trawa
        x = rnd.randint(0, W)
        d.line([(x, 168 + rnd.randint(0, 12)), (x + rnd.randint(-3, 3), 160)], fill=(70, 60, 44), width=1)
    figs = [(62, 0.92), (124, 1.0, "radio"), (192, 1.04), (258, 0.98), (322, 0.9)]
    for f in figs:
        cx, s = f[0], f[1]
        top = int(262 - 172 * s)                                     # czubek hełmu; stopy na 262
        coat = (38, 33, 27)
        if len(f) > 2:
            d.rectangle([cx + 10 * s, top + 30 * s, cx + 26 * s, top + 74 * s], fill=(56, 54, 44))   # radiostacja na plecach
            d.line([(cx + 22 * s, top + 30 * s), (cx + 34 * s, top - 34 * s)], fill=(40, 36, 30), width=2)  # antena
        d.ellipse([cx - 8 * s, top + 8 * s, cx + 8 * s, top + 26 * s], fill=(128, 106, 82))          # twarz
        d.chord([cx - 11 * s, top, cx + 11 * s, top + 20 * s], 180, 360, fill=(46, 42, 34))           # hełm
        d.rectangle([cx - 12 * s, top + 9 * s, cx + 12 * s, top + 12 * s], fill=(46, 42, 34))
        d.polygon([(cx - 18 * s, top + 30 * s), (cx + 18 * s, top + 30 * s), (cx + 15 * s, top + 118 * s),
                   (cx - 15 * s, top + 118 * s)], fill=coat)                                            # płaszcz, ramiona
        d.ellipse([cx - 19 * s, top + 27 * s, cx + 19 * s, top + 38 * s], fill=coat)
        for lx in (-7, 4):                                                                              # nogi w butach
            d.rectangle([cx + lx * s, top + 116 * s, cx + (lx + 7) * s, top + 172 * s], fill=(30, 27, 22))
        d.line([(cx - 16 * s, top + 34 * s), (cx + 14 * s, top + 92 * s)], fill=(70, 60, 46), width=2)  # pas broni
        d.line([(cx + 14 * s, top + 40 * s), (cx + 18 * s, top + 104 * s)], fill=(24, 22, 18), width=3)  # lufa zza ramienia
    img = img.filter(ImageFilter.GaussianBlur(1.3))                 # stary obiektyw
    noise(img, 14, 1)
    stains(img, 4, 6, (60, 40, 20))
    vignette(img, 0.75)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(236, 226, 204), width=10)   # biały brzeg odbitki
    for x in range(0, W, 8):                                         # ząbkowany brzeg
        d.polygon([(x, 0), (x + 4, 4), (x + 8, 0)], fill=(30, 26, 20))
        d.polygon([(x, H - 1), (x + 4, H - 5), (x + 8, H - 1)], fill=(30, 26, 20))
    d.text((W - 92, H - 26), "2187  IX.87", fill=(90, 70, 50))
    img.save(os.path.join(OUT, "memento_patrol.png"))


def station():
    """Odręczna mapa okolic radiostacji: kratka, droga, hala, maszt z odciągami, kropki geofonów linii B, czerwone kółko."""
    img = Image.new("RGB", (W, H), (218, 210, 186))
    d = ImageDraw.Draw(img)
    for x in range(0, W, 16):
        d.line([(x, 0), (x, H)], fill=(186, 196, 200), width=1)
    for y in range(0, H, 16):
        d.line([(0, y), (W, y)], fill=(186, 196, 200), width=1)
    ink = (40, 44, 70)
    rnd = random.Random(14)

    def wobbly(pts, width=2, col=ink):
        out = [(x + rnd.uniform(-1.2, 1.2), y + rnd.uniform(-1.2, 1.2)) for x, y in pts]
        d.line(out, fill=col, width=width)

    wobbly([(0, 220), (80, 206), (160, 214), (250, 190), (384, 200)], 3)                   # droga
    wobbly([(0, 230), (80, 216), (160, 224), (250, 200), (384, 210)], 1)
    for k in range(9):                                                                      # las kółeczkami
        x, y = 30 + k * 40 + rnd.randint(-8, 8), 40 + rnd.randint(-10, 20)
        d.ellipse([x - 9, y - 9, x + 9, y + 9], outline=(60, 90, 60), width=2)
    d.rectangle([70, 120, 150, 170], outline=ink, width=2)                                  # hala stacji
    d.line([(70, 120), (150, 170)], fill=ink, width=1)
    d.line([(150, 120), (70, 170)], fill=ink, width=1)
    mx, my = 262, 130                                                                       # maszt z odciągami
    d.line([(mx, my - 50), (mx, my + 20)], fill=ink, width=3)
    for dx in (-40, 40):
        wobbly([(mx, my - 40), (mx + dx, my + 22)], 1)
    d.polygon([(mx - 6, my - 50), (mx + 6, my - 50), (mx, my - 62)], outline=ink)
    for k in range(10):                                                                     # linia geofonów B
        x = 40 + k * 32
        y = 248 - int(18 * math.sin(k * 0.6))
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=ink)
    d.text((14, 252), "B", fill=ink)
    d.text((70, 104), "86", fill=ink)
    red = (170, 30, 26)
    for w in range(3):                                                                      # czerwone kółko pod masztem, kilka pociągnięć
        r = 30 + w * 2
        d.ellipse([mx - r - 4, my + 2 - r * 0.6, mx + r + 4, my + 26 + r * 0.6], outline=red, width=2)
    d.line([(mx + 36, my + 40), (mx + 70, my + 70)], fill=red, width=2)
    d.text((mx + 50, my + 72), "?!", fill=red)
    noise(img, 8, 2)
    stains(img, 5, 8, (120, 90, 40))
    vignette(img, 0.45)
    d = ImageDraw.Draw(img)
    for x0, y0 in ((0, 0), (W - 28, 0)):                                                    # taśma klejąca w rogach
        d.rectangle([x0, y0, x0 + 28, y0 + 12], fill=(200, 190, 150))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(os.path.join(OUT, "memento_station.png"))


def sklad():
    """Plan Składu na kalce: obrys hali, rzędy regałów, schody, antresola zakreślona ołówkiem, krzyżyk przy skrytce."""
    img = Image.new("RGB", (W, H), (196, 204, 206))
    d = ImageDraw.Draw(img)
    blue = (40, 70, 130)
    for x in range(0, W, 24):
        d.line([(x, 0), (x, H)], fill=(178, 188, 194), width=1)
    d.rectangle([24, 30, W - 24, H - 40], outline=blue, width=3)                             # obrys hali
    d.rectangle([24, 30, W - 24, 40], fill=blue)
    for k in range(6):                                                                       # regały
        x = 60 + k * 44
        d.rectangle([x, 70, x + 16, 200], outline=blue, width=2)
        for y in range(80, 200, 20):
            d.line([(x, y), (x + 16, y)], fill=blue, width=1)
    for k in range(8):                                                                       # schody na antresolę
        d.line([(W - 80 + k * 6, 210), (W - 80 + k * 6, 240)], fill=blue, width=1)
    d.rectangle([W - 120, 52, W - 32, 110], outline=blue, width=2)                           # antresola
    d.line([(W - 120, 52), (W - 32, 110)], fill=blue, width=1)
    lead = (60, 56, 52)
    rnd = random.Random(3)
    pts = []
    for k in range(40):                                                                      # ołówkiem zakreślona antresola
        a = k / 39 * math.tau * 1.15
        pts.append((W - 76 + 56 * math.cos(a) + rnd.uniform(-2, 2), 81 + 40 * math.sin(a) + rnd.uniform(-2, 2)))
    d.line(pts, fill=lead, width=2)
    cx, cy = W - 56, 92
    d.line([(cx - 8, cy - 8), (cx + 8, cy + 8)], fill=(150, 30, 26), width=3)               # krzyżyk przy skrytce
    d.line([(cx - 8, cy + 8), (cx + 8, cy - 8)], fill=(150, 30, 26), width=3)
    d.text((cx + 12, cy - 4), "H", fill=(150, 30, 26))
    d.text((30, H - 32), "No 3", fill=blue)
    noise(img, 6, 3)
    stains(img, 6, 5, (90, 80, 60))
    vignette(img, 0.4)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    img.save(os.path.join(OUT, "memento_sklad.png"))


if __name__ == "__main__":
    patrol()
    station()
    sklad()
    print("ok:", OUT)
