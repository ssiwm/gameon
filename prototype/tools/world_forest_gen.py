"""Tekstury drzew tła widoku 3D (`Level3D.build_forest`): świerki i martwe pnie jako karty z kanałem alfa.

Wynik: prototype/art/world3d/forest/spruce_{a,b,c}.png, snag_{a,b}.png (512×1024 RGBA, pień u dołu na środku) oraz runo:
grass_{a,b}.png i fern_a.png (256×256, kępa od dolnej krawędzi) dla `Level3D.build_undergrowth`, roots_{a,b}.png (korzenie pod krawędzią bryły, `build_front_edge`).
Kształt: pień + piętra opadających, postrzępionych gałęzi rysowanych igła po igle; jaśniejsze grzbiety gałęzi dają bryłę w świetle flary.

    python prototype/tools/world_forest_gen.py
"""
import math
import os
import random
import sys

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


def roots(seed, size=256):
    """Korzenie na przekroju gruntu: kilka grubszych, falujących korzeni z cienkimi odrostami i grudami ziemi u nasady. Rysowane jak kępa
    trawy (nasada przy dolnej krawędzi); gra wiesza je odwrócone pod krawędzią bryły (`Level3D.build_front_edge`)."""
    rng = random.Random(seed)
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col_d, col_l, soil = (40, 30, 22), (92, 74, 56), (34, 27, 21)

    def root(x0, y0, ang, ln, wid, depth):
        pts_l, pts_r = [], []
        x, y, a = x0, y0, ang
        n = 14
        for i in range(n + 1):
            t = i / n
            w = wid * (1.0 - t) ** 0.8 + 0.6 * SS
            pts_l.append((x - w, y))
            pts_r.append((x + w, y))
            if depth > 0 and 0.2 < t < 0.85 and rng.random() < 0.22:
                root(x, y, a + rng.choice((-1, 1)) * rng.uniform(0.5, 1.1), ln * rng.uniform(0.25, 0.45), w * 0.55, depth - 1)
            a += rng.gauss(0, 0.16)
            x += math.cos(a) * ln / n
            y += math.sin(a) * ln / n
        col = _mix(col_d, col_l, rng.uniform(0.0, 0.5))
        d.polygon(pts_l + pts_r[::-1], fill=col + (255,))
        d.line(pts_r, fill=_mix(col, col_l, 0.6) + (255,), width=SS)

    for _ in range(rng.randint(4, 6)):
        root(S * 0.5 + rng.gauss(0, S * 0.16), S - 2 * SS, math.radians(-90 + rng.gauss(0, 18)), S * rng.uniform(0.45, 0.95), rng.uniform(4.0, 8.0) * SS, 2)
    for _ in range(18):                                        # grudy ziemi przy nasadzie
        cx, cy, r = S * 0.5 + rng.gauss(0, S * 0.2), S - rng.uniform(2, 26) * SS, rng.uniform(5, 14) * SS
        d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=_mix(soil, col_d, rng.random()) + (255,))
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


def bark(kind, seed, w=256, h=512):
    """Kora do pni modeli 3D (`prep_items3d.py: build_pine / build_birch`): u = obwód (powtarzalna w poziomie), v = wysokość (dół obrazu = nasada).
    pine: dół szarobrązowe, głęboko spękane płyty, ku górze cienka, łuszcząca się rudopomarańczowa kora (sosna zwyczajna);
    birch: biała kora z czarnymi poziomymi przetchlinkami i ciemnymi łatami, u nasady czarna, spękana."""
    rng = random.Random(seed)
    Wd, Hd = w * SS, h * SS
    im = Image.new("RGB", (Wd, Hd), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for y in range(0, Hd, SS):                                 # tło: przejście koloru wzdłuż pnia
        t = 1.0 - y / Hd                                       # 0 = nasada, 1 = wierzchołek
        if kind == "pine":
            c = _mix((62, 52, 44), (138, 80, 50), min(1.0, max(0.0, (t - 0.42) / 0.4)))
        else:
            c = _mix((34, 32, 30), (206, 204, 196), min(1.0, max(0.0, (t - 0.04) / 0.14)))
        d.rectangle([0, y, Wd, y + SS], fill=c)
    if kind == "pine":
        for _ in range(900):                                   # płyty kory: ciemne bruzdy pionowe, gęstsze u dołu
            t = rng.random() ** 1.6
            y = Hd * (1.0 - t)
            x = rng.uniform(0, Wd)
            ln = rng.uniform(10, 40) * SS * (1.4 - t)
            dark = _mix((26, 20, 16), (90, 46, 26), t)
            d.line([x, y, x + rng.uniform(-3, 3) * SS, y - ln], fill=dark, width=max(SS, int((1.6 - t) * 3 * SS)))
        for _ in range(500):                                   # łuszczące się płatki w górnej części
            t = rng.uniform(0.45, 1.0)
            y = Hd * (1.0 - t)
            x = rng.uniform(0, Wd)
            r = rng.uniform(2, 7) * SS
            d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=_mix((150, 94, 60), (108, 58, 36), rng.random()))
    else:
        for _ in range(420):                                   # przetchlinki: krótkie czarne kreski w poprzek pnia
            t = rng.uniform(0.1, 1.0)
            y = Hd * (1.0 - t)
            x = rng.uniform(0, Wd)
            ln = rng.uniform(6, 30) * SS
            d.line([x, y, x + ln, y + rng.uniform(-1, 1) * SS], fill=(28, 26, 24), width=max(SS, int(rng.uniform(1, 2.6) * SS)))
        for _ in range(26):                                    # ciemne łaty
            t = rng.uniform(0.12, 0.95)
            y = Hd * (1.0 - t)
            x = rng.uniform(0, Wd)
            r = rng.uniform(8, 26) * SS
            d.polygon([(x + math.cos(a) * r * rng.uniform(0.5, 1.0), y + math.sin(a) * r * 0.45 * rng.uniform(0.5, 1.0)) for a in [i * 0.7 for i in range(9)]], fill=(40, 38, 34))
        for _ in range(300):                                   # czarna, spękana nasada
            t = rng.random() * 0.12
            y = Hd * (1.0 - t)
            x = rng.uniform(0, Wd)
            d.line([x, y, x + rng.uniform(-2, 2) * SS, y - rng.uniform(8, 30) * SS], fill=(14, 13, 12), width=2 * SS)
    out = im.resize((w, h), Image.LANCZOS).convert("RGBA")
    return out


def pine_tuft(seed, size=256):
    """Kępa igliwia sosny do korony modelu 3D: zbite pęczki długich igieł promieniście z kilku gałązek, gęstsze w środku."""
    rng = random.Random(seed)
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col_d, col_l, wood = (14, 30, 24), (58, 88, 60), (40, 26, 18)
    cx, cy = S * 0.5, S * 0.55
    for _ in range(9):                                         # gałązki od środka
        a = rng.uniform(0, math.tau)
        ln = S * rng.uniform(0.18, 0.42)
        ex, ey = cx + math.cos(a) * ln, cy + math.sin(a) * ln * 0.7
        d.line([cx, cy, ex, ey], fill=wood + (255,), width=2 * SS)
        for k in range(10):
            t = (k + 1) / 10
            x, y = cx + (ex - cx) * t, cy + (ey - cy) * t
            _needles(d, rng, x, y, a, S * rng.uniform(0.06, 0.11), col_d, col_l, 9, 1.4)
    for _ in range(140):                                       # gęsty środek
        a = rng.uniform(0, math.tau)
        r = S * 0.2 * rng.random() ** 0.7
        _needles(d, rng, cx + math.cos(a) * r, cy + math.sin(a) * r * 0.7, rng.uniform(0, math.tau), S * 0.07, col_d, col_l, 5, 3.0)
    return im.resize((size, size), Image.LANCZOS)


def birch_leaves(seed, size=256):
    """Zwisające gałązki brzozy z drobnymi liśćmi (nasada u góry, w środku) do korony modelu 3D."""
    rng = random.Random(seed)
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    leaf_d, leaf_l, wood = (18, 28, 16), (50, 64, 32), (40, 34, 30)
    for _ in range(16):
        x0 = S * 0.5 + rng.gauss(0, S * 0.16)
        a = math.radians(90 + rng.gauss(0, 12))
        ln = S * rng.uniform(0.45, 0.95)
        x, y = x0, 2 * SS
        steps = 16
        for i in range(steps):
            t = i / steps
            nx, ny = x + math.cos(a) * ln / steps, y + math.sin(a) * ln / steps
            d.line([x, y, nx, ny], fill=wood + (255,), width=SS)
            for _ in range(3):                                 # listki: małe romby
                lx, ly = nx + rng.uniform(-8, 8) * SS, ny + rng.uniform(-4, 6) * SS
                r = rng.uniform(3, 5.5) * SS
                c = _mix(leaf_d, leaf_l, rng.random() ** 1.5)
                d.polygon([(lx, ly - r * 0.6), (lx + r * 0.55, ly), (lx, ly + r), (lx - r * 0.55, ly)], fill=c + (255,))
            a += rng.uniform(-0.05, 0.08)
            x, y = nx, ny
    return im.resize((size, size), Image.LANCZOS)


def pine_card(seed):
    """Sosna dalekiego lasu (karta): wysoki, prawie nagi pień, rudy u góry, i płaska, nieregularna korona z kęp w górnej ćwiartce."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = W * SS * (0.5 + rng.uniform(-0.04, 0.04))
    base_y = H * SS - 4 * SS
    crown_y = H * SS * rng.uniform(0.24, 0.34)
    top_y = H * SS * 0.04
    _trunk(d, rng, cx, base_y, top_y + 30 * SS, 11 * SS, 3 * SS, (40, 32, 26), (118, 72, 44), rng.uniform(-1.6, 1.6))
    for _ in range(rng.randint(3, 6)):                         # suche kikuty pod koroną
        y = rng.uniform(crown_y, base_y * 0.7)
        side = rng.choice((-1, 1))
        d.line([cx, y, cx + side * rng.uniform(12, 34) * SS, y - rng.uniform(2, 12) * SS], fill=(36, 28, 22, 255), width=2 * SS)
    need_d, need_l = (12, 26, 22), (46, 72, 52)
    clumps = []
    for _ in range(rng.randint(9, 13)):                        # konary korony i płaskie kępy wzdłuż nich (parasol, nie miotła)
        side = rng.choice((-1, 1))
        y0 = rng.uniform(crown_y + 40 * SS, top_y + 70 * SS)
        ln = rng.uniform(60, 190) * SS
        ex, ey = cx + side * ln, y0 - rng.uniform(5, 60) * SS
        d.line([cx, y0, ex, ey], fill=(54, 34, 24, 255), width=4 * SS)
        for k in range(3):
            t = 0.45 + 0.27 * k
            clumps.append((cx + (ex - cx) * t, y0 + (ey - y0) * t - 8 * SS, rng.uniform(34, 62) * SS))
    for _ in range(4):
        clumps.append((cx + rng.uniform(-40, 40) * SS, top_y + rng.uniform(40, 110) * SS, rng.uniform(50, 75) * SS))
    for (x, y, r) in clumps:
        for _ in range(int(r / SS * 5)):
            a = rng.uniform(0, math.tau)
            rr = r * rng.random() ** 0.5
            px, py = x + math.cos(a) * rr, y + math.sin(a) * rr * 0.42
            _needles(d, rng, px, py, rng.uniform(0, math.tau), rng.uniform(8, 15) * SS, need_d, need_l, 5, 3.0)
    return im.resize((W, H), Image.LANCZOS)


def birch_card(seed):
    """Brzoza dalekiego lasu (karta): smukły biały pień z czarnymi znakami, lekko pochylony, jajowata ażurowa korona z wygiętych konarów
    i zwisających gałązek z drobnymi liśćmi."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = W * SS * 0.5
    base_y = H * SS - 4 * SS
    top_y = H * SS * 0.12
    bend = rng.uniform(-1.4, 1.4)
    _trunk(d, rng, cx, base_y, top_y, 8 * SS, 2 * SS, (150, 150, 144), (214, 212, 204), bend)
    for _ in range(90):                                        # czarne znaki na korze
        t = rng.random()
        y = base_y + (top_y - base_y) * t
        x = cx + bend * math.sin(t * math.pi) * W * SS * 0.03 + rng.uniform(-6, 6) * SS * (1.0 - t)
        d.line([x - 5 * SS, y, x + 5 * SS, y], fill=(24, 22, 20, 255), width=SS)
    leaf_d, leaf_l = (16, 26, 14), (48, 62, 30)
    wood = (58, 52, 46)
    crown_lo, crown_hi = 0.36, 0.97                            # korona: jajowata, najszersza w ok. 40% swojej wysokości
    hanging = []                                               # zwisające gałązki rysowane na końcu, żeby przykryły konary
    for j in range(13):                                        # konary: łuk skośnie w górę i na boki, końce opadają
        t = crown_lo + (crown_hi - crown_lo) * (j + rng.random()) / 13
        q = (t - crown_lo) / (crown_hi - crown_lo)
        y0 = base_y + (top_y - base_y) * t
        x0 = cx + bend * math.sin(t * math.pi) * W * SS * 0.03
        side = (-1 if j % 2 == 0 else 1) if rng.random() < 0.75 else rng.choice((-1, 1))
        reach = W * SS * 0.36 * math.sin(math.pi * (0.25 + 0.75 * q)) ** 0.7 * rng.uniform(0.75, 1.05) + 20 * SS
        a0 = math.radians(rng.uniform(28, 48))                 # od pionu
        steps = 12
        x, y = x0, y0
        for i in range(steps):
            s = (i + 1) / steps
            a = a0 + s * math.radians(rng.uniform(40, 70))       # wygina się na zewnątrz i w dół
            nx = x + side * math.sin(a) * reach / steps * 1.1
            ny = y - math.cos(a) * reach / steps * 1.1
            d.line([x, y, nx, ny], fill=wood + (255,), width=max(SS, int((1.0 - s) * 3 * SS)))
            if i >= 2:
                for _ in range(3):
                    hanging.append((nx + rng.uniform(-6, 6) * SS, ny + rng.uniform(-3, 6) * SS, rng.uniform(20, 130) * SS * (1.1 - 0.5 * q) * rng.uniform(0.6, 1.2), side))
            x, y = nx, ny
    for (x, y, ln, side) in hanging:                           # zwisające gałązki z drobnymi liśćmi, gęstsze ku końcom
        n = max(5, int(ln / (5 * SS)))
        sway = rng.uniform(-0.5, 0.5) * SS + side * 0.4 * SS
        for i in range(n):
            nx, ny = x + sway + rng.uniform(-0.6, 0.6) * SS, y + ln / n
            d.line([x, y, nx, ny], fill=(46, 42, 38, 255), width=SS)
            for _ in range(2):
                r = rng.uniform(2.5, 4.5) * SS
                lx, ly = nx + rng.uniform(-5, 5) * SS, ny + rng.uniform(-2, 4) * SS
                rot = rng.uniform(0, math.pi)
                pts = [(lx + math.cos(rot + k * math.pi / 2) * r * (1.0 if k % 2 == 0 else 0.55),
                        ly + math.sin(rot + k * math.pi / 2) * r * (1.0 if k % 2 == 0 else 0.55)) for k in range(4)]
                d.polygon(pts, fill=_mix(leaf_d, leaf_l, rng.random() ** 1.8) + (255,))
            x, y = nx, ny
    return im.resize((W, H), Image.LANCZOS)


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
        "roots_a": roots(6),
        "roots_b": roots(13),
        "pine_a": pine_card(31),
        "pine_b": pine_card(47),
        "birch_a": birch_card(53),
        "pine_bark": bark("pine", 61),
        "birch_bark": bark("birch", 67),
        "pine_tuft": pine_tuft(71),
        "birch_leaves": birch_leaves(73),
        "bough_side": bough(21, True),
        "bough_top": bough(22, False),
    }
    only = next((a[7:].split(",") for a in sys.argv[1:] if a.startswith("--only=")), None)        # --only=roots_a,roots_b: tylko te pliki
    for name, im in jobs.items():
        if only and name not in only:
            continue
        # lekkie zmiękczenie koloru bez rozmywania alfy (krawędź zostaje ostra dla alpha scissor)
        rgb = im.convert("RGB").filter(ImageFilter.GaussianBlur(0.6))
        out = Image.merge("RGBA", (*rgb.split(), im.split()[3]))
        path = os.path.join(OUT, name + ".png")
        out.save(path)
        print("saved", os.path.normpath(path))


if __name__ == "__main__":
    main()
