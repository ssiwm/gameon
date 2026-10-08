"""Tło parallax HD (etap 3): niebo z księżycem i gwiazdami, trzy linie świerków (daleka, średnia, bliska) i mgła — 2048×960 px (2× gęstość względem 1024×480 w grze).

Uruchomienie (numpy + Pillow + scipy): python prototype/tools/world_hd_backdrop.py
Wynik: art/backdrop/hd/{sky,ridge_far,ridge_mid,ridge_near,fog}.png. Paleta i jasność są takie same jak w backdrop.gd (gra jest celowo bardzo ciemna: niebo ~0,01,
sylwetki ledwo odcięte od horyzontu); zmienia się jakość, nie nastrój. Drzewa to prawdziwe świerki z pniem i piętrami opadających gałęzi; linie zawijają się w poziomie (okres 2048 px).
Gradienty ciemnych kolorów mają dithering (inaczej 8 bitów daje widoczne pasy).
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

W, H = 2048, 960                     # 2× względem gry (1024×480)
SS = 2                               # supersampling sylwetek
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "backdrop", "hd")
rng = np.random.default_rng(87)


def noise(h, w, py, px):
    g = rng.random((py + 1, px + 1))
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    ys, xs = np.linspace(0, py, h, endpoint=False), np.linspace(0, px, w, endpoint=False)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0] * (1 - fx) + g[y0][:, x0 + 1] * fx
    b = g[y0 + 1][:, x0] * (1 - fx) + g[y0 + 1][:, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(h, w, py, px, o=4):
    out, amp, tot = np.zeros((h, w)), 1.0, 0.0
    for k in range(o):
        out += amp * noise(h, w, py * 2 ** k, px * 2 ** k)
        tot += amp
        amp *= 0.5
    return out / tot


def save_rgb(path, arr):
    """Float 0..1 → PNG 8 bit z ditheringiem (szum trójkątny ±1 LSB)."""
    d = (rng.random(arr.shape) + rng.random(arr.shape)) - 1.0
    q = np.clip(arr * 255.0 + d, 0, 255)
    Image.fromarray(np.round(q).astype(np.uint8)).save(path)


def sky():
    top, hor = np.array([0.006, 0.008, 0.016]), np.array([0.075, 0.080, 0.110])
    y = np.arange(H)[:, None] / (H * 0.85)
    t = np.clip(y, 0, 1) ** 2
    img = top[None, None, :] * (1 - t[..., None]) + hor[None, None, :] * t[..., None]
    img = np.repeat(img, W, axis=1)
    # delikatne smugi chmur (bardzo niski kontrast), okresowe w poziomie
    cl = fbm(H, W, 3, 8, 5)
    band = np.exp(-((np.arange(H)[:, None] - H * 0.42) / (H * 0.25)) ** 2)
    img += (np.clip(cl - 0.5, 0, 1) * band * 0.035)[..., None] * np.array([0.8, 0.85, 1.0])
    # gwiazdy: różna jasność i wielkość, najjaśniejsze z miękką poświatą
    stars = np.zeros((H, W))
    for _ in range(190):
        sx, sy = int(rng.integers(0, W)), int(rng.integers(0, int(H * 0.58)))
        b = rng.uniform(0.08, 0.34) * (1.0 if rng.random() < 0.94 else 1.25)
        r = 1.2 if b < 0.2 else 1.7
        y0, y1, x0, x1 = max(0, sy - 6), min(H, sy + 7), max(0, sx - 6), min(W, sx + 7)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        stars[y0:y1, x0:x1] += b * np.exp(-((yy - sy) ** 2 + (xx - sx) ** 2) / (2 * (r * 0.55) ** 2))
    img += stars[..., None] * np.array([0.95, 0.98, 1.05])
    # księżyc (wspólna pozycja z backdrop.gd: (720, 70) w 1024×480 → (1440, 140)); tarcza z kraterami i poświata
    mc = np.array([1440.0, 140.0])
    yy, xx = np.mgrid[0:340, 1200:1680]
    d = np.sqrt((yy - mc[1]) ** 2 + (xx - mc[0]) ** 2)
    crater = fbm(340, 480, 5, 7, 5)
    disc = np.clip((30.0 - d) / 1.8, 0, 1)
    shade = (0.50 + 0.18 * (crater - 0.5)) * disc
    glow = np.clip(1 - (d - 30.0) / 112.0, 0, 1) ** 2.2 * 0.07 * (d >= 30.0)
    patch = img[0:340, 1200:1680]
    patch += glow[..., None] * np.array([1.0, 1.0, 1.1])
    patch = patch * (1 - disc[..., None]) + shade[..., None] * np.array([0.95, 1.0, 1.02])
    img[0:340, 1200:1680] = patch
    save_rgb(os.path.join(OUT, "sky.png"), np.clip(img, 0, 1))


def pine(draw, x, base_y, h, col, rimcol, lean):
    """Jeden świerk: pień + piętra opadających, postrzępionych gałęzi (współrzędne w pikselach supersamplingu)."""
    tw = max(2.0, h * 0.035)
    draw.rectangle([x - tw, base_y - h * 0.22, x + tw, base_y + 4], fill=col)
    tiers = int(rng.integers(8, 13))
    for k in range(tiers):
        t = k / (tiers - 1)
        y = base_y - h * (0.16 + 0.80 * t)
        wd = h * (0.34 * (1 - t) ** 0.85 + 0.035)
        th = h * (0.20 + 0.04 * (1 - t))
        pts = [(x + lean * t * h, y - th * 0.9)]
        n = int(rng.integers(5, 8))
        for i in range(n + 1):
            f = i / n
            px = x + lean * t * h * (1 - 0.3 * f) - wd + 2 * wd * f
            py = y + th * 0.10 * rng.uniform(-1, 1) + (th * 0.28 if i % 2 else 0.0)
            pts.append((px, py))
        draw.polygon(pts, fill=col)
        # jaśniejsza lewa krawędź (księżyc z lewej-góry)
        draw.line([pts[0], pts[1]], fill=rimcol, width=max(1, int(h * 0.006)))


def b8(c):
    return tuple(int(round(v * 255)) for v in c) + (255,)


def ridge(name, seed_off, base_frac, spacing, h_rng, col, rim, haze, ground=None):
    ground = b8(ground) if ground is not None else b8(col)       # wypełnienie pod linią drzew ciemniejsze niż korony — luki między pniami nie świecą
    col, rim = b8(col), b8(rim)
    big = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(big)
    base = int(H * base_frac) * SS
    r = np.random.default_rng(87 + seed_off)
    # podnóże: falująca masa
    xs = np.arange(W * SS)
    hill = base - 6 * SS * np.sin(xs * 0.003 / SS * 2 + seed_off) - 4 * SS * np.sin(xs * 0.008 / SS * 2 + 1.3 * seed_off)
    dr.polygon([(0, H * SS)] + [(int(x), int(hill[x])) for x in range(0, W * SS, 4)] + [(W * SS - 1, H * SS)], fill=ground)
    x = float(r.integers(0, spacing))
    while x < W * SS:
        h = r.uniform(*h_rng) * SS
        lean = r.uniform(-0.02, 0.02)
        for ox in (-W * SS, 0, W * SS):                                      # zawijanie w poziomie
            if -h < x + ox < W * SS + h:
                # lokalny RNG drzewa używa globalnego `rng` w pine(); ziarno ustala kolejność
                pine(dr, x + ox, hill[int(np.clip(x, 0, W * SS - 1))] + 3 * SS, h, col, rim, lean)
        x += spacing * SS * r.uniform(0.6, 1.5)
    img = big.resize((W, H), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) / 255.0
    # mgła u podstawy: sylwetka rozjaśnia się ku dołowi (daleki plan bardziej)
    rows = np.arange(H)[:, None]
    fogk = np.clip((rows - H * (base_frac - 0.05)) / (H * 0.10), 0, 1) * haze
    rgb = a[..., :3] * (1 - fogk[..., None]) + fogk[..., None] * np.array([0.09, 0.10, 0.13]) * a[..., 3:4]
    out = np.concatenate([rgb, a[..., 3:4]], axis=2)
    d = (rng.random(out[..., :3].shape) + rng.random(out[..., :3].shape)) - 1.0
    q = np.clip(out[..., :3] * 255.0 + d, 0, 255)
    res = np.concatenate([np.round(q), np.round(out[..., 3:4] * 255.0)], axis=2).astype(np.uint8)
    Image.fromarray(res, "RGBA").save(os.path.join(OUT, name + ".png"))


def fog():
    n = fbm(H, W, 3, 8, 4)
    n2 = fbm(H, W, 6, 16, 3)
    y0, y1 = int(H * 0.62), int(H * 0.92)
    a = np.zeros((H, W))
    rows = np.arange(y0, y1)[:, None]
    band = np.sin(np.pi * (rows - y0) / (y1 - y0))
    a[y0:y1] = band * (0.6 * n[y0:y1] ** 2 + 0.4 * n2[y0:y1] ** 2) * 0.10
    a = gaussian_filter(a, 2.0, mode="wrap")
    rgb = np.ones((H, W, 3)) * np.array([0.55, 0.62, 0.70])
    d = (rng.random(a.shape) + rng.random(a.shape)) - 1.0
    al = np.clip(a * 255.0 + d, 0, 255)                                      # dithering kanału alfa — bez niego niskie wartości dają kontury
    rgb8 = np.round(rgb * 255).astype(np.uint8)
    Image.fromarray(np.concatenate([rgb8, np.round(al)[..., None].astype(np.uint8)], axis=2), "RGBA").save(os.path.join(OUT, "fog.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    sky()
    ridge("ridge_far", 1, 0.66, 14, (38, 72), (0.050, 0.058, 0.080), (0.056, 0.065, 0.089), 0.0, ground=(0.026, 0.031, 0.043))
    ridge("ridge_mid", 2, 0.72, 22, (58, 105), (0.034, 0.040, 0.057), (0.039, 0.046, 0.064), 0.0, ground=(0.022, 0.026, 0.037))
    ridge("ridge_near", 3, 0.76, 34, (80, 150), (0.020, 0.024, 0.034), (0.024, 0.029, 0.040), 0.0)
    fog()
    print("OK", OUT)


if __name__ == "__main__":
    main()
