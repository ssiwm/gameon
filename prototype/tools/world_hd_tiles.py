"""Teren HD (etap 2): glina z kamykami i darń z trawą jako atlas albedo + mapa normalnych, 16 px na piksel świata.

Uruchomienie (numpy + Pillow + scipy): python prototype/tools/world_hd_tiles.py
Wynik: art/world/terrain_hd.png i terrain_hd_n.png (1024×576):
    wiersz 0 (y 0..256)   : wypełnienie gliną — pas 4 kafli (1024×256), okresowy w poziomie i w pionie, więc sąsiednie kafle (kolumna % 4) składają się bez szwów
    wiersz 1 (y 256..576) : kafel wierzchni 1024×320 — nad komórką 64 px (4 piksele świata) przewisu trawy, pod nią ta sama glina co w wierszu 0
Albedo bez oświetlenia (światło dają lampy gry przez mapę normalnych: R = prawo, G = góra, B = ku widzowi).
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

ALBEDO_GAIN = 1.7            # gra jest bardzo ciemna — albedo terenu jest jaśniejsze niż „realistyczne"
S = 256                      # kafel
W = 4 * S                    # pas 4 kafli
OVER = 64                    # przewis trawy ponad komórką
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "world")
rng = np.random.default_rng(1987)


def smooth(t):
    return t * t * (3 - 2 * t)


def noise(h, w, py, px, r=rng):
    """Okresowy szum wartościowy: siatka py×px, próbkowana gładko do h×w (zawija się w obu osiach)."""
    g = r.random((py, px))
    ys = np.linspace(0, py, h, endpoint=False)
    xs = np.linspace(0, px, w, endpoint=False)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = smooth(ys - y0)[:, None], smooth(xs - x0)[None, :]
    y1, x1 = (y0 + 1) % py, (x0 + 1) % px
    a = g[y0][:, x0] * (1 - fx) + g[y0][:, x1] * fx
    b = g[y1][:, x0] * (1 - fx) + g[y1][:, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(h, w, py, px, octaves=5, r=rng):
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * noise(h, w, py * 2 ** o, px * 2 ** o, r)
        tot += amp
        amp *= 0.5
    return out / tot


def ramp(t, stops):
    """t∈[0,1] → RGB wg listy (pozycja, kolor)."""
    pos = [p for p, _ in stops]
    cols = np.array([c for _, c in stops], float)
    out = np.zeros(t.shape + (3,))
    for k in range(3):
        out[..., k] = np.interp(t, pos, cols[:, k])
    return out


def stamp_wrap(canvas, patch, cy, cx):
    """Dodaje `patch` (maska/wysokość) wyśrodkowany w (cy, cx) z zawijaniem w obu osiach."""
    ph, pw = patch.shape
    H, Wd = canvas.shape
    ys = (np.arange(ph) + cy - ph // 2) % H
    xs = (np.arange(pw) + cx - pw // 2) % Wd
    canvas[np.ix_(ys, xs)] = np.maximum(canvas[np.ix_(ys, xs)], patch)


def soil():
    """Glina 1024×256: albedo (RGB 0..1) i wysokość (px)."""
    h = np.zeros((S, W))
    n_big = fbm(S, W, 2, 8, 4)
    n_mid = fbm(S, W, 4, 16, 4)
    n_fine = fbm(S, W, 32, 128, 2)
    t = np.clip(0.25 + 0.55 * n_big + 0.35 * (n_mid - 0.5) + 0.15 * (n_fine - 0.5), 0, 1)
    alb = ramp(t, [(0.0, (0.085, 0.060, 0.042)), (0.35, (0.155, 0.108, 0.072)), (0.7, (0.235, 0.166, 0.108)), (1.0, (0.30, 0.22, 0.14))]) / 1.0
    # zielonkawe plamy mchu
    moss = np.clip((fbm(S, W, 2, 8, 3) - 0.62) * 5, 0, 1)[..., None]
    alb = alb * (1 - 0.55 * moss) + moss * 0.55 * np.array([0.10, 0.14, 0.06])
    # drobne ziarno
    grain = (n_fine - 0.5)[..., None]
    alb = alb * (1 + 0.35 * grain)
    h += 5.0 * (fbm(S, W, 3, 12, 4) - 0.5) + 1.2 * (n_fine - 0.5)
    # kamyki i bryłki
    peb = np.zeros((S, W))
    pal = np.zeros((S, W, 3))
    for _ in range(30):
        r = rng.choice([rng.uniform(3, 7), rng.uniform(4, 9), rng.uniform(8, 16)])
        ry = r * rng.uniform(0.65, 1.0)
        cy, cx = int(rng.integers(0, S)), int(rng.integers(0, W))
        yy, xx = np.mgrid[-int(ry * 1.6):int(ry * 1.6) + 1, -int(r * 1.6):int(r * 1.6) + 1]
        d2 = (yy / ry) ** 2 + (xx / r) ** 2
        dome = np.sqrt(np.clip(1 - d2, 0, 1))
        ring = np.clip(1 - np.abs(np.sqrt(d2) - 1.15) / 0.5, 0, 1)            # cień kontaktowy wokół kamyka
        stamp_wrap(peb, dome * r * 0.55, cy, cx)
        sh = np.clip(1 - np.abs(np.sqrt(d2) - 1.0) / 0.35, 0, 1) * 0
        tint = rng.uniform(0.6, 1.25)
        base = np.array([0.19, 0.17, 0.15]) * tint
        patch = np.zeros(d2.shape + (3,))
        patch[...] = base * (0.55 + 0.7 * dome[..., None])
        mask = (d2 < 1.0)
        ph, pw = d2.shape
        ys = (np.arange(ph) + cy - ph // 2) % S
        xs = (np.arange(pw) + cx - pw // 2) % W
        sub = alb[np.ix_(ys, xs)]
        sub = np.where(mask[..., None], patch, sub * (1 - 0.4 * ring[..., None] * (~mask)[..., None]))
        alb[np.ix_(ys, xs)] = sub
    h += peb
    # kawałki korzeni — ciemne, wypukłe linie
    root = np.zeros((S, W))
    for _ in range(7):
        x0, y0 = rng.uniform(0, W), rng.uniform(0, S)
        ang, wid = rng.uniform(0, np.pi), rng.uniform(3, 6)
        pts = []
        for k in range(30):
            ang += rng.normal(0, 0.18)
            x0 += np.cos(ang) * 8
            y0 += np.sin(ang) * 8
            pts.append((x0, y0))
        im = Image.new("L", (W, S), 0)
        dr = ImageDraw.Draw(im)
        for ox in (-W, 0, W):
            for oy in (-S, 0, S):
                dr.line([(x + ox, y + oy) for x, y in pts], fill=255, width=int(wid))
        root = np.maximum(root, np.asarray(im, float) / 255.0)
    root = gaussian_filter(root, 1.2, mode="wrap")
    h += root * 3.5
    alb = alb * (1 - 0.45 * root[..., None]) + 0.45 * root[..., None] * np.array([0.06, 0.04, 0.03])
    # AO z wysokości (wgłębienia ciemniejsze)
    cav = np.clip(gaussian_filter(h, 6, mode="wrap") - h, 0, 6) / 6.0
    alb = alb * (1 - 0.5 * cav[..., None])
    return np.clip(alb * ALBEDO_GAIN, 0, 1), h


def normal_from_height(h, wrap_x=True, k=1.0):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 if wrap_x else np.gradient(h, axis=1)
    gr = np.gradient(h, axis=0)                              # po wierszach (w dół)
    n = np.stack([-gx * k, gr * k, np.ones_like(h)], -1)     # R = prawo, G = góra (= +∂h/∂wiersz), B = ku widzowi
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def blades(alb_top, h_top, alpha_top):
    """Rysuje źdźbła trawy (i darń) na kaflu wierzchnim 1024×320: baza darni ok. wiersza OVER+8, źdźbła sięgają ku górze do przewisu."""
    SS = 4
    Wd, Hd = W * SS, (OVER + S) * SS
    col = Image.new("RGBA", (Wd, Hd), (0, 0, 0, 0))
    hei = Image.new("L", (Wd, Hd), 0)
    dc, dh = ImageDraw.Draw(col), ImageDraw.Draw(hei)
    base_y = (OVER + 14) * SS
    # darń: falująca krawędź
    edge = (OVER + 6 + 10 * (fbm(1, W, 1, 16, 3)[0] - 0.5)) * SS
    for _ in range(430):
        bx = rng.uniform(0, W) * SS
        by = base_y + rng.uniform(-12, 6) * SS
        ln = rng.uniform(26, 66) * (1.0 if rng.random() < 0.75 else 1.5) * SS
        wd = rng.uniform(3.5, 7.5) * SS
        bend = rng.normal(0, 14) * SS
        tone = rng.uniform(0, 1)
        n_seg = 8
        left, right = [], []
        for s_ in range(n_seg + 1):
            t = s_ / n_seg
            x = bx + bend * t * t
            y = by - ln * t
            w_ = wd * (1 - t) ** 0.9 * 0.5
            left.append((x - w_, y))
            right.append((x + w_, y))
        poly = left + right[::-1]
        gcol = ramp(np.array(tone), [(0.0, (0.085, 0.16, 0.06)), (0.5, (0.17, 0.27, 0.085)), (1.0, (0.30, 0.38, 0.12))])
        dark = tuple(int(255 * v) for v in np.clip(gcol * 0.8, 0, 1))
        lite = tuple(int(255 * v) for v in np.clip(gcol * 1.5, 0, 1))
        for ox in (-Wd, 0, Wd):
            pl = [(x + ox, y) for x, y in poly]
            dc.polygon(pl, fill=lite + (255,))
            # ciemniejsza prawa połowa i ciemna nasada — daje objętość bez światła
            half = [(x + ox, y) for x, y in right] + [(x + ox + 0, y) for x, y in right][::-1]
            dc.polygon([(x + ox, y) for x, y in right[: n_seg // 2 + 1]] + [(x + ox - 0.4 * wd * 0.5, y) for x, y in left[: n_seg // 2 + 1]][::-1], fill=dark + (255,))
            dh.polygon(pl, fill=int(110 + 120 * rng.random()))
    col = col.resize((W, OVER + S), Image.LANCZOS)
    hei = hei.resize((W, OVER + S), Image.LANCZOS)
    c = np.asarray(col, float) / 255.0
    hh = np.asarray(hei, float) / 255.0 * 9.0          # wysokość źdźbeł w px
    a = c[..., 3]
    rows = np.arange(OVER + S)[:, None]
    # warstwa darni (pod źdźbłami): ziemia → mech
    turf_t = np.clip((rows - (edge[0] if False else (OVER + 4))) / 26.0, 0, 1)
    turf_mask = (rows >= (OVER + 6 + 10 * (fbm(1, W, 1, 16, 3)[0] - 0.5))[None, :]).astype(float)
    tn = fbm(S + OVER, W, 4, 32, 3)
    turf = ramp(np.clip(0.2 + 0.7 * tn, 0, 1), [(0.0, (0.08, 0.14, 0.05)), (1.0, (0.20, 0.26, 0.09))])
    blend = np.clip((rows - (OVER + 6)) / 40.0, 0, 1)[..., None]
    base_alb = alb_top * blend + turf * (1 - blend)
    base_alb = np.where(turf_mask[..., None] > 0, base_alb, 0)
    base_a = turf_mask
    out_rgb = base_alb * (1 - a[..., None]) + c[..., :3] * a[..., None]
    out_a = np.maximum(base_a, a)
    out_h = np.where(a > 0.05, hh, h_top * 1.0)
    out_h = np.where(turf_mask > 0, np.maximum(out_h, h_top), out_h)
    return out_rgb, out_a, out_h


def main():
    os.makedirs(OUT, exist_ok=True)
    alb, h = soil()
    # kafel wierzchni: nad gliną dochodzi przewis
    alb_top = np.concatenate([np.zeros((OVER, W, 3)), alb], 0)
    h_top = np.concatenate([np.zeros((OVER, W)), h], 0)
    t_rgb, t_a, t_h = blades(alb_top, h_top, None)
    t_h = gaussian_filter(t_h, 0.8, mode="wrap")
    # atlas: wiersz 0 = glina (alfa 1), wiersz 1 = wierzch
    atlas = np.zeros((S + OVER + S, W, 4))
    atlas[:S, :, :3] = alb
    atlas[:S, :, 3] = 1.0
    atlas[S:, :, :3] = t_rgb
    atlas[S:, :, 3] = t_a
    nrm = np.zeros((S + OVER + S, W, 4))
    nrm[:S, :, :3] = normal_from_height(gaussian_filter(h, 0.6, mode="wrap"), True, 0.55)
    nrm[:S, :, 3] = 1.0
    nrm[S:, :, :3] = normal_from_height(t_h, True, 0.55)
    nrm[S:, :, 3] = t_a
    nrm[..., :3] = np.where(nrm[..., 3:4] > 0.02, nrm[..., :3], np.array([0.5, 0.5, 1.0]))
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "terrain_hd.png"))
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "terrain_hd_n.png"))
    print("OK", OUT, atlas.shape)


if __name__ == "__main__":
    main()
