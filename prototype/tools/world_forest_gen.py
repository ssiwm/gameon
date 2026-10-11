"""Tekstury drzew tła widoku 3D (`Level3D.build_forest`): świerki i martwe pnie jako karty z kanałem alfa.

Wynik: prototype/art/world3d/forest/spruce_{a,b,c}.png, snag_{a,b}.png (512×1024 RGBA, pień u dołu na środku).
Kształt: pień + piętra opadających, postrzępionych gałęzi rysowanych igła po igle; jaśniejsze grzbiety gałęzi dają bryłę w świetle flary.

    python prototype/tools/world_forest_gen.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 512, 1024
SS = 2                                    # nadpróbkowanie krawędzi
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "world3d", "forest")


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _trunk(d, rng, cx, base_y, top_y, r_base, r_top, col_dark, col_light, bend):
    """Pień jako pasy poziome (zwężenie, lekkie wygięcie, jaśniejszy lewy bok)."""
    n = 220
    for i in range(n):
        t = i / (n - 1)
        y = base_y + (top_y - base_y) * t
        r = r_base + (r_top - r_base) * t ** 0.8
        x = cx + bend * math.sin(t * math.pi) * W * SS * 0.03
        d.rectangle([x - r, y - 3 * SS, x + r, y + 3 * SS], fill=col_dark + (255,))
        d.rectangle([x - r, y - 3 * SS, x - r * 0.35, y + 3 * SS], fill=_mix(col_dark, col_light, 0.5) + (255,))
    for _ in range(140):                  # spękania kory
        t = rng.random()
        y = base_y + (top_y - base_y) * t
        r = r_base + (r_top - r_base) * t ** 0.8
        x = cx + rng.uniform(-r, r) * 0.9
        d.line([x, y, x + rng.uniform(-2, 2) * SS, y - rng.uniform(10, 34) * SS], fill=_mix(col_dark, (0, 0, 0), 0.5) + (255,), width=SS)


def _bough(d, rng, x0, y0, length, droop, side, col_a, col_b):
    """Jedna gałąź: oś opadająca łukiem, wzdłuż niej kępki igieł zwisające w dół."""
    steps = max(6, int(length / (7 * SS)))
    px, py = x0, y0
    for i in range(steps + 1):
        t = i / steps
        x = x0 + side * length * t
        y = y0 + droop * (t ** 1.6) - length * 0.10 * math.sin(t * math.pi)
        d.line([px, py, x, y], fill=_mix(col_a, (20, 14, 10), 0.6) + (255,), width=max(1, int((1.0 - t) * 3 * SS)))
        tuft = (1.0 - 0.55 * t) * length * 0.36 + 8 * SS
        for _ in range(5):
            a = math.radians(rng.uniform(60, 120)) + side * 0.35
            ln = tuft * rng.uniform(0.5, 1.0)
            ex = x + math.cos(a) * ln * 0.5 * side + rng.uniform(-3, 3) * SS
            ey = y + math.sin(a) * ln
            c = _mix(col_a, col_b, rng.random() ** 2 * (0.25 + 0.75 * (1.0 - t)))
            d.polygon([(x - 3 * SS, y), (x + 3 * SS, y), (ex, ey)], fill=c + (255,))
        # jaśniejszy grzbiet (światło z góry)
        d.line([px, py - SS, x, y - SS], fill=_mix(col_a, col_b, 0.9) + (255,), width=SS)
        px, py = x, y


def spruce(seed, fullness=1.0, bare_low=0.18):
    rng = random.Random(seed)
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = W * SS * 0.5
    base_y = H * SS - 4 * SS
    top_y = H * SS * 0.03
    bark_d, bark_l = (26, 20, 16), (58, 48, 40)
    need_d = (12, 26, 22)
    need_l = (46, 78, 58)
    _trunk(d, rng, cx, base_y, top_y + 40 * SS, 15 * SS, 2 * SS, bark_d, bark_l, rng.uniform(-1, 1))
    tiers = rng.randint(26, 32)
    for k in range(tiers):                # od dołu do góry: dolne gałęzie rysowane pierwsze, wyższe je przykrywają
        t = k / (tiers - 1)
        y = base_y - (base_y - top_y) * (bare_low + (1.0 - bare_low) * t)
        half = W * SS * 0.46 * ((1.0 - t) ** 0.8) * fullness + 10 * SS
        for side in (-1, 1):
            for _ in range(2 if t < 0.85 else 1):
                ln = half * rng.uniform(0.62, 1.0)
                if rng.random() < 0.08 and t < 0.6:
                    continue              # przerwa po złamanej gałęzi
                _bough(d, rng, cx, y + rng.uniform(-10, 10) * SS, ln, ln * rng.uniform(0.30, 0.55), side, need_d, need_l)
        # środek korony zasłania pień
        for _ in range(10):
            ang = rng.uniform(0, math.tau)
            rr = half * 0.25 * rng.random()
            x = cx + math.cos(ang) * rr
            yy = y + math.sin(ang) * rr * 0.5
            d.polygon([(x - 5 * SS, yy), (x + 5 * SS, yy), (x + rng.uniform(-6, 6) * SS, yy + rng.uniform(14, 40) * SS)],
                      fill=_mix(need_d, need_l, rng.random() * 0.4) + (255,))
    # czubek
    d.polygon([(cx - 5 * SS, top_y + 60 * SS), (cx + 5 * SS, top_y + 60 * SS), (cx + rng.uniform(-3, 3) * SS, top_y)], fill=need_d + (255,))
    return im.resize((W, H), Image.LANCZOS)


def snag(seed):
    """Martwy pień: złamany wierzchołek, kilka nagich konarów."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = W * SS * 0.5
    base_y = H * SS - 4 * SS
    top_y = H * SS * rng.uniform(0.12, 0.3)
    bark_d, bark_l = (24, 20, 18), (70, 64, 58)
    _trunk(d, rng, cx, base_y, top_y, 17 * SS, 7 * SS, bark_d, bark_l, rng.uniform(-1.5, 1.5))
    # poszarpany przełom
    for _ in range(7):
        x = cx + rng.uniform(-7, 7) * SS
        d.polygon([(x - 3 * SS, top_y + 6 * SS), (x + 3 * SS, top_y + 6 * SS), (x + rng.uniform(-3, 3) * SS, top_y - rng.uniform(10, 46) * SS)], fill=bark_d + (255,))
    for _ in range(rng.randint(6, 10)):
        t = rng.uniform(0.25, 0.92)
        y = base_y + (top_y - base_y) * t
        side = rng.choice((-1, 1))
        ln = rng.uniform(40, 170) * SS * (1.1 - t * 0.5)
        px, py = cx, y
        segs = 6
        for i in range(1, segs + 1):
            f = i / segs
            x = cx + side * ln * f
            yy = y - ln * 0.25 * f + ln * 0.18 * f * f + rng.uniform(-5, 5) * SS
            d.line([px, py, x, yy], fill=bark_d + (255,), width=max(1, int((1.0 - f) * 6 * SS) + SS))
            if rng.random() < 0.5:
                d.line([x, yy, x + side * rng.uniform(8, 26) * SS, yy + rng.uniform(-30, 20) * SS], fill=bark_d + (255,), width=SS)
            px, py = x, yy
    return im.resize((W, H), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "spruce_a": spruce(11, 1.0, 0.16),
        "spruce_b": spruce(23, 0.78, 0.30),
        "spruce_c": spruce(37, 0.92, 0.08),
        "snag_a": snag(5),
        "snag_b": snag(9),
    }
    for name, im in jobs.items():
        # lekkie zmiękczenie koloru bez rozmywania alfy (krawędź zostaje ostra dla alpha scissor)
        rgb = im.convert("RGB").filter(ImageFilter.GaussianBlur(0.6))
        out = Image.merge("RGBA", (*rgb.split(), im.split()[3]))
        path = os.path.join(OUT, name + ".png")
        out.save(path)
        print("saved", os.path.normpath(path))


if __name__ == "__main__":
    main()
