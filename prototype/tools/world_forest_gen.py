"""Tekstury drzew tła widoku 3D (`Level3D.build_forest`): świerki i martwe pnie jako karty z kanałem alfa.

Wynik: prototype/art/world3d/forest/spruce_{a,b,c}.png, snag_{a,b}.png (512×1024 RGBA, pień u dołu na środku) oraz runo:
grass_{a,b}.png i fern_a.png (256×256, kępa od dolnej krawędzi) dla `Level3D.build_undergrowth`.
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


def grass(seed, dry=0.3, size=256):
    """Kępa trawy: wachlarz wygiętych źdźbeł z podstawy na środku dołu; część sucha (żółtawa)."""
    rng = random.Random(seed)
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    green_d, green_l, straw = (28, 44, 24), (74, 104, 52), (128, 112, 66)
    for _ in range(46):
        x0 = S * 0.5 + rng.gauss(0, S * 0.13)
        lean = rng.gauss(0, 0.45)
        ln = S * rng.uniform(0.35, 0.95)
        wid = rng.uniform(2.2, 4.5) * SS
        col = _mix(green_d, green_l, rng.random())
        if rng.random() < dry:
            col = _mix(col, straw, rng.uniform(0.5, 1.0))
        pts_l, pts_r = [], []
        n = 9
        for i in range(n + 1):
            t = i / n
            x = x0 + lean * ln * 0.55 * t * t
            y = S - 2 * SS - ln * t * (1.0 - 0.18 * abs(lean) * t)
            w = wid * (1.0 - t) ** 0.7
            pts_l.append((x - w, y))
            pts_r.append((x + w, y))
        d.polygon(pts_l + pts_r[::-1], fill=col + (255,))
        d.line(pts_l, fill=_mix(col, (0, 0, 0), 0.35) + (255,), width=SS)
    return im.resize((size, size), Image.LANCZOS)


def fern(seed, size=256):
    """Paproć: kilka łukowatych liści z listkami po obu stronach osi."""
    rng = random.Random(seed)
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col_d, col_l = (20, 46, 26), (58, 98, 50)
    for k in range(9):
        ang = math.radians(-90 + (k - 4) * 19 + rng.uniform(-6, 6))
        ln = S * rng.uniform(0.55, 0.92)
        px, py = S * 0.5, S * 0.62
        n = 22
        for i in range(1, n + 1):
            t = i / n
            a = ang + (k - 4) * 0.16 * t * t
            x = S * 0.5 + math.cos(a) * ln * t
            y = S * 0.62 + math.sin(a) * ln * t + ln * 0.22 * t * t
            d.line([px, py, x, y], fill=col_d + (255,), width=max(1, int(2 * SS * (1 - t)) + 1))
            leaf = ln * 0.16 * math.sin(min(1.0, t * 1.25) * math.pi) + 2 * SS
            nx, ny = -(y - py), (x - px)
            nl = math.hypot(nx, ny) or 1.0
            nx, ny = nx / nl, ny / nl
            c = _mix(col_d, col_l, rng.random() * (0.4 + 0.6 * t))
            for sgn in (-1, 1):
                d.polygon([(px, py), (x, y), (x + nx * leaf * sgn + (x - px) * 0.6, y + ny * leaf * sgn + (y - py) * 0.6)], fill=c + (255,))
            px, py = x, y
    return im.resize((size, size), Image.LANCZOS)


def _needles(d, rng, x, y, ang, ln, col_d, col_l, n=7, spread=1.1):
    """Pęczek igieł wokół punktu gałązki: cienkie kreski pod kątem do osi (ang), po obu stronach."""
    for _ in range(n):
        a = ang + rng.choice((-1, 1)) * rng.uniform(0.35, spread)
        l = ln * rng.uniform(0.6, 1.0)
        c = _mix(col_d, col_l, rng.random() ** 1.6)
        d.line([x, y, x + math.cos(a) * l, y + math.sin(a) * l], fill=c + (255,), width=max(1, SS))


def _twig(d, rng, x0, y0, ang, length, depth, col_d, col_l, wood, sag=0.0):
    """Gałązka z igłami i rozgałęzieniami (rekurencyjnie); `sag` dogina ją w dół (+y) wraz z długością."""
    steps = max(4, int(length / (5 * SS)))
    x, y = x0, y0
    for i in range(steps):
        t = i / steps
        a = ang + sag * t + rng.uniform(-0.06, 0.06)
        nx, ny = x + math.cos(a) * length / steps, y + math.sin(a) * length / steps
        d.line([x, y, nx, ny], fill=wood + (255,), width=max(1, int((1.0 - t) * (2 + depth) * SS)))
        _needles(d, rng, nx, ny, a, (5.5 + 1.5 * depth) * SS, col_d, col_l, 6 + 2 * depth)
        if depth > 0 and i > 0 and rng.random() < 0.62:
            _twig(d, rng, nx, ny, a + rng.choice((-1, 1)) * rng.uniform(0.45, 0.85), length * (1.0 - t) * rng.uniform(0.35, 0.6), depth - 1, col_d, col_l, wood, sag * 0.5)
        x, y = nx, ny


def bough(seed, side_view, w=512, h=256):
    """Gałąź świerka z igliwiem dla modelu 3D drzewa (`tools/prep_items3d.py: build_spruce`). Nasada na lewej krawędzi.
    side_view: profil z boku — gałąź opada, gałązki zwisają pod nią (nasada u góry po lewej); inaczej widok z góry — wachlarz (nasada w połowie wysokości)."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col_d, col_l, wood = (10, 24, 20), (44, 74, 54), (30, 22, 16)
    W, Hh = w * SS, h * SS
    if side_view:
        x, y = 0.0, Hh * 0.16
        steps = 26
        for i in range(steps):
            t = i / steps
            a = 0.10 + 0.42 * t
            nx, ny = x + math.cos(a) * W * 0.95 / steps, y + math.sin(a) * W * 0.95 / steps
            d.line([x, y, nx, ny], fill=wood + (255,), width=max(1, int((1.0 - t) * 5 * SS) + SS))
            _needles(d, rng, nx, ny, a, 8 * SS, col_d, col_l, 10)
            if True:                                           # zwisające gałązki
                _twig(d, rng, nx, ny, a + rng.uniform(0.9, 1.4), Hh * rng.uniform(0.25, 0.55) * (1.0 - 0.5 * t), 1, col_d, col_l, wood, 0.25)
            if i % 5 == 2:
                _twig(d, rng, nx, ny, a - rng.uniform(0.3, 0.6), Hh * 0.16, 0, col_d, col_l, wood)
            x, y = nx, ny
    else:
        _twig(d, rng, 0.0, Hh * 0.5, 0.0, W * 0.97, 2, col_d, col_l, wood)
        for sgn in (-1, 1):                                    # dwa boczne konary od nasady — pełny wachlarz
            _twig(d, rng, W * 0.06, Hh * 0.5, sgn * 0.33, W * 0.72, 2, col_d, col_l, wood)
    return im.resize((w, h), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "spruce_a": spruce(11, 1.0, 0.16),
        "spruce_b": spruce(23, 0.78, 0.30),
        "spruce_c": spruce(37, 0.92, 0.08),
        "snag_a": snag(5),
        "snag_b": snag(9),
        "grass_a": grass(3, 0.25),
        "grass_b": grass(8, 0.6),
        "fern_a": fern(4),
        "bough_side": bough(21, True),
        "bough_top": bough(22, False),
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
