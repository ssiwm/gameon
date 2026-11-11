"""Tekstury lasu widoku 3D: runo i karty pierwszego planu (PIL).

Wynik w prototype/art/world3d/forest/: grass_{a,b}.png i fern_a.png (256×256, kępa od dolnej krawędzi) dla `Level3D.build_undergrowth`,
roots_{a,b}.png (korzenie pod krawędzią bryły, `build_front_edge`), pine_bark.png (kora pnia proceduralnego pierwszego planu bez modeli) i
bough_side.png (gałąź świerka, `Front3D._bough`). Karty drzew dalekiego pasa (spruce_{a,b,c}.png, pine_{a,b}.png) od 1.7.543 renderuje
ze skanów Poly Haven `tools/pine_cards.py --far=…` — te same drzewa co modele lasu bliżej.

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
    """Gałąź świerka z igliwiem (karta pierwszego planu `Front3D._bough`). Nasada na lewej krawędzi.
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


def bark(seed, w=256, h=512):
    """Kora sosny do pnia proceduralnego pierwszego planu bez modeli (`Front3D._trunk`): u = obwód (powtarzalna w poziomie), v = wysokość (dół obrazu = nasada);
    dół szarobrązowe, głęboko spękane płyty, ku górze cienka, łuszcząca się rudopomarańczowa kora (sosna zwyczajna)."""
    rng = random.Random(seed)
    Wd, Hd = w * SS, h * SS
    im = Image.new("RGB", (Wd, Hd), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for y in range(0, Hd, SS):                                 # tło: przejście koloru wzdłuż pnia
        t = 1.0 - y / Hd                                       # 0 = nasada, 1 = wierzchołek
        c = _mix((62, 52, 44), (138, 80, 50), min(1.0, max(0.0, (t - 0.42) / 0.4)))
        d.rectangle([0, y, Wd, y + SS], fill=c)
    for _ in range(900):                                       # płyty kory: ciemne bruzdy pionowe, gęstsze u dołu
        t = rng.random() ** 1.6
        y = Hd * (1.0 - t)
        x = rng.uniform(0, Wd)
        ln = rng.uniform(10, 40) * SS * (1.4 - t)
        dark = _mix((26, 20, 16), (90, 46, 26), t)
        d.line([x, y, x + rng.uniform(-3, 3) * SS, y - ln], fill=dark, width=max(SS, int((1.6 - t) * 3 * SS)))
    for _ in range(500):                                       # łuszczące się płatki w górnej części
        t = rng.uniform(0.45, 1.0)
        y = Hd * (1.0 - t)
        x = rng.uniform(0, Wd)
        r = rng.uniform(2, 7) * SS
        d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=_mix((150, 94, 60), (108, 58, 36), rng.random()))
    out = im.resize((w, h), Image.LANCZOS).convert("RGBA")
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "grass_a": grass(3, 0.25),
        "grass_b": grass(8, 0.6),
        "fern_a": fern(4),
        "roots_a": roots(6),
        "roots_b": roots(13),
        "pine_bark": bark(61),
        "bough_side": bough(21, True),
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
