"""Generator tileowalnych materiałów PBR świata (teren, beton, metal, kratka, deski, słup, ściana, błoto, olej, woda).

Uruchomienie (numpy + scipy + Pillow):
    python prototype/tools/world_pbr_gen.py [--res=1024] [--out=art_src/world_pbr] [--only=concrete,wall] [--preview]
Dla każdego materiału powstaje: <nazwa>_albedo.png (RGB; kratka: RGBA z maską otworów), <nazwa>_normal.png (OpenGL, Y+ w górę),
<nazwa>_orm.png (R = AO, G = roughness, B = metallic, jak w glTF) i <nazwa>_height.png. Wszystko okresowe — kafelkuje się bez szwów
(szumy z zawinięciem, Voronoi z zawijaniem komórek, wypaczanie z trybem „grid-wrap”).
--preview zapisuje podgląd oświetlonego materiału (1 kafel + kafelkowanie 2×2) do <out>/preview/.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

# ---------------------------------------------------------------- narzędzia


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(img, s):
    return gaussian_filter(img, s, mode="wrap")


def vnoise(n, fx, fy, seed):
    """Okresowy szum wartościowy: fx × fy komórek na kafel."""
    g = np.random.default_rng(seed).random((fy, fx)).astype(np.float32)
    xs = np.arange(n) * fx / n
    ys = np.arange(n) * fy / n
    xi, yi = np.floor(xs).astype(int), np.floor(ys).astype(int)
    xf, yf = (xs - xi).astype(np.float32), (ys - yi).astype(np.float32)
    ux = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    uy = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
    x0, x1, y0, y1 = xi % fx, (xi + 1) % fx, yi % fy, (yi + 1) % fy
    v00, v01 = g[y0][:, x0], g[y0][:, x1]
    v10, v11 = g[y1][:, x0], g[y1][:, x1]
    a = v00 + (v01 - v00) * ux[None, :]
    b = v10 + (v11 - v10) * ux[None, :]
    return a + (b - a) * uy[:, None]


def fbm(n, fx, fy, octaves, seed, gain=0.5):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * vnoise(n, fx * 2 ** o, fy * 2 ** o, seed + o * 31)
        tot += amp
        amp *= gain
    return out / tot


def ridged(n, fx, fy, octaves, seed):
    return 1.0 - np.abs(2.0 * fbm(n, fx, fy, octaves, seed) - 1.0)


def voronoi(n, cells, seed, jitter=1.0):
    """Okresowe Voronoi: zwraca F1, F2 (w jednostkach komórki) i losowy identyfikator najbliższej komórki 0..1."""
    r = np.random.default_rng(seed)
    jx = (0.5 + (r.random((cells, cells)) - 0.5) * jitter).astype(np.float32)
    jy = (0.5 + (r.random((cells, cells)) - 0.5) * jitter).astype(np.float32)
    hid = r.random((cells, cells)).astype(np.float32)
    p = (np.arange(n) + 0.5) * cells / n
    cx = np.floor(p).astype(int)[None, :]
    cy = np.floor(p).astype(int)[:, None]
    px = p[None, :]
    py = p[:, None]
    f1 = np.full((n, n), 9.0, np.float32)
    f2 = np.full((n, n), 9.0, np.float32)
    cid = np.zeros((n, n), np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ci = cx + dx
            cj = cy + dy
            qx = ci + jx[cj % cells, ci % cells]
            qy = cj + jy[cj % cells, ci % cells]
            d = np.sqrt((px - qx) ** 2 + (py - qy) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, hid[cj % cells, ci % cells], cid)
            f1 = np.where(closer, d, f1)
    return f1, f2, cid


def warp(img, wx, wy, amt):
    n = img.shape[0]
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    return map_coordinates(img, [yy + wy * amt * n, xx + wx * amt * n], order=1, mode="grid-wrap")


def normal_from_height(h, strength):
    n = h.shape[0]
    s = strength * n / 1024.0
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny = -dx * s * 64.0, dy * s * 64.0
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5


def ao_from_height(h, radii=(2, 6, 18), k=6.0):
    ao = np.zeros_like(h)
    for r in radii:
        ao += np.clip((blur(h, r) - h) * k * (1.0 + r * 0.04), 0.0, 1.0)
    return np.clip(1.0 - ao / len(radii), 0.0, 1.0)


def curvature(h, s=3.0):
    return h - blur(h, s)


def ramp(t, stops):
    pos = [p for p, _ in stops]
    cols = np.array([c for _, c in stops], np.float32)
    t = np.clip(t, 0.0, 1.0)
    return np.dstack([np.interp(t, pos, cols[:, i]) for i in range(3)]).astype(np.float32)


def mix(a, b, m):
    return a + (b - a) * (m[..., None] if a.ndim == 3 and m.ndim == 2 else m)


def hashf(a, seed=0):
    x = np.sin(a * 127.1 + seed * 311.7) * 43758.5453
    return x - np.floor(x)


def grid_mask(n, nx, ny, w, wy=None):
    """Okresowe linie siatki (szczeliny płyt): zwraca 1 na liniach, 0 pomiędzy, miękka krawędź."""
    wy = w if wy is None else wy
    u = (np.arange(n) / n * nx) % 1.0
    v = (np.arange(n) / n * ny) % 1.0
    du = np.minimum(u, 1.0 - u)
    dv = np.minimum(v, 1.0 - v)
    mu = 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.02, du)
    mv = 1.0 - smoothstep(wy * 0.5, wy * 0.5 + 0.02, dv)
    return np.maximum(mu[None, :], mv[:, None]), du, dv


# ---------------------------------------------------------------- materiały (przebieg 2)
# Każdy zwraca słownik: albedo (n,n,3 0..1 sRGB), height (0..1), roughness, metallic, ao, ns [, alpha]


def stripes(n, a, b, f, seed):
    """Okresowy szum 1D wzdłuż kierunku (a, b) o całkowitych współczynnikach: pasma/włókna pod dowolnym kątem."""
    g = np.random.default_rng(seed).random(f).astype(np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    t = (a * xx + b * yy) % 1.0 * f
    i = np.floor(t).astype(int)
    fr = (t - i).astype(np.float32)
    u = fr * fr * (3 - 2 * fr)
    return g[i % f] * (1 - u) + g[(i + 1) % f] * u


def dome(f1, radius, power=0.6):
    return np.clip(1.0 - f1 / radius, 0.0, 1.0) ** power


def needles(n, seed, f=128, thick=0.84):
    """Igliwie / źdźbła: cienkie kreski pod kilkoma kątami, przerywane maską szumu. Zwraca (maska 0..1, losowy ton 0..1)."""
    dirs = [(1, 1), (1, -1), (2, 1), (1, 2), (2, -1), (1, -2), (3, 1), (1, 3), (3, -1), (1, -3), (3, 2), (2, 3)]
    mask = np.zeros((n, n), np.float32)
    tone = np.zeros((n, n), np.float32)
    for k, (a, b) in enumerate(dirs):
        s = stripes(n, a, b, f + 8 * k, seed + k * 7)
        gate = smoothstep(0.50, 0.58, vnoise(n, 22 + k, 22 + k, seed + 100 + k))
        line = smoothstep(thick, thick + 0.07, s) * gate
        tone = np.where(line > mask, vnoise(n, 7, 7, seed + 200 + k), tone)
        mask = np.maximum(mask, line)
    return mask, tone


def mat_terrain(n):
    base = 0.6 * fbm(n, 5, 5, 6, 601) + 0.4 * fbm(n, 70, 70, 3, 603)
    nm, nt = needles(n, 610)
    nm2, nt2 = needles(n, 640, f=96, thick=0.8)
    nd = np.maximum(nm, nm2 * 0.9)
    ndt = np.where(nm >= nm2 * 0.9, nt, nt2)
    # kamienie: rzadkie, duże, kopułki z kontaktowym AO; żwir: drobniejszy, ciemny
    rf1, _, rid = voronoi(n, 9, 605)
    rf1 = rf1 + (fbm(n, 14, 14, 4, 606) - 0.5) * 0.22
    rocks = dome(rf1, 0.34, 0.55) * (rid > 0.84)
    gf1, _, gid = voronoi(n, 54, 607)
    gravel = dome(gf1, 0.34, 0.6) * (gid > 0.62)
    moss_m = smoothstep(0.50, 0.70, fbm(n, 4, 4, 5, 615))
    moss_t = fbm(n, 110, 110, 3, 617)
    twig = smoothstep(0.90, 0.96, stripes(n, 2, 1, 40, 650)) * smoothstep(0.5, 0.6, vnoise(n, 5, 5, 651))
    h = 0.35 + 0.22 * base + 0.10 * nd + 0.34 * rocks + 0.10 * gravel + 0.06 * moss_m * moss_t + 0.10 * twig
    cav = ao_from_height(h, (2, 6, 20), 6.0)
    humus = ramp(0.55 * base + 0.45 * fbm(n, 40, 40, 3, 621), [(0.0, (0.035, 0.026, 0.020)), (0.5, (0.085, 0.060, 0.042)), (1.0, (0.16, 0.115, 0.080))])
    nee = ramp(ndt, [(0.0, (0.17, 0.095, 0.045)), (0.5, (0.30, 0.17, 0.075)), (1.0, (0.36, 0.26, 0.13))])
    rock = ramp(rid, [(0.84, (0.13, 0.13, 0.14)), (1.0, (0.28, 0.26, 0.24))]) * (0.7 + 0.6 * fbm(n, 50, 50, 4, 623))[..., None]
    rock = mix(rock, ramp(moss_t, [(0.0, (0.04, 0.08, 0.03)), (1.0, (0.11, 0.19, 0.07))]), smoothstep(0.5, 0.75, fbm(n, 18, 18, 4, 629)) * 0.8)
    grav = ramp(gid, [(0.62, (0.15, 0.13, 0.11)), (1.0, (0.30, 0.27, 0.23))])
    mossc = ramp(moss_t, [(0.0, (0.035, 0.075, 0.030)), (1.0, (0.12, 0.22, 0.075))])
    alb = mix(humus, nee, np.clip(nd * 0.85, 0, 1))
    alb = mix(alb, np.full_like(alb, 0.05), twig * 0.9)
    alb = mix(alb, mossc, moss_m * 0.8 * (1 - nd * 0.5))
    alb = mix(alb, grav, np.clip(gravel * 1.5, 0, 1))
    alb = mix(alb, rock, np.clip(rocks * 3.0, 0, 1))
    macro = 0.82 + 0.36 * fbm(n, 3, 3, 3, 625)
    alb = alb * macro[..., None] * (0.35 + 0.65 * cav[..., None])
    rough = np.clip(0.93 - 0.18 * rocks - 0.08 * gravel + 0.05 * (fbm(n, 40, 40, 3, 627) - 0.5) - 0.05 * moss_m, 0.5, 1.0)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=2.8)


def mat_concrete(n):
    h = 0.50 * fbm(n, 3, 3, 6, 11) + 0.25 * fbm(n, 14, 14, 5, 21) + 0.25 * fbm(n, 70, 70, 3, 31)
    seam, du, dv = grid_mask(n, 2, 2, 0.010)
    d = np.minimum(du[None, :], dv[:, None])
    bevel = 1.0 - smoothstep(0.0, 0.012, d)
    h = h * 0.40 - seam * 0.22 - bevel * 0.06
    # chip na krawędzi płyt
    chip = smoothstep(0.62, 0.74, fbm(n, 24, 24, 4, 33)) * (1.0 - smoothstep(0.0, 0.05, d))
    h -= chip * 0.18
    ties = np.zeros((n, n), np.float32)
    streak = np.zeros((n, n), np.float32)
    ys = np.arange(n)[:, None] / n
    xs = np.arange(n)[None, :] / n
    for cx in (0.25, 0.75):
        for cy in (0.25, 0.75):
            for ox in (-0.11, 0.11):
                for oy in (-0.11, 0.11):
                    x0, y0 = cx + ox, cy + oy
                    dx = (xs - x0 + 0.5) % 1.0 - 0.5
                    dy = (ys - y0 + 0.5) % 1.0 - 0.5
                    ties = np.maximum(ties, 1.0 - smoothstep(0.011, 0.016, np.sqrt(dx * dx + dy * dy)))
                    below = np.clip(dy, 0, 1)
                    wob = 0.004 * np.sin(below * 90.0 + x0 * 40.0)
                    streak = np.maximum(streak, np.exp(-((dx + wob) / (0.006 + 0.012 * below)) ** 2) * np.exp(-below * 5.5) * (dy > 0))
    h -= ties * 0.20
    wx = fbm(n, 3, 3, 3, 41) - 0.5
    wy = fbm(n, 3, 3, 3, 43) - 0.5
    f1, f2, _ = voronoi(n, 4, 7)
    edge = warp(np.clip(f2 - f1, 0, 1), wx, wy, 0.07)
    gate = smoothstep(0.50, 0.66, fbm(n, 3, 3, 3, 51))
    crack_core = (1.0 - smoothstep(0.006, 0.02, edge)) * gate
    crack_wide = (1.0 - smoothstep(0.012, 0.07, edge)) * gate
    h -= crack_core * 0.30 + crack_wide * 0.08
    pf1, _, pid = voronoi(n, 80, 13)
    pits = dome(pf1, 0.16, 0.8) * (pid > 0.85)
    h -= pits * 0.18
    gf1, _, gid = voronoi(n, 150, 17)
    spec = dome(gf1, 0.22, 0.9) * (gid > 0.55)
    stain = smoothstep(0.35, 0.8, fbm(n, 9, 2, 4, 61))
    cav = ao_from_height(h, (1, 4, 12), 7.0)
    macro = 0.80 + 0.40 * fbm(n, 2, 2, 4, 71)
    tone = 0.45 * fbm(n, 22, 22, 4, 73) + 0.55 * np.clip(0.5 + (h - 0.2) * 0.8, 0, 1)
    alb = ramp(tone, [(0.0, (0.17, 0.17, 0.175)), (0.5, (0.36, 0.355, 0.345)), (1.0, (0.55, 0.545, 0.53))])
    alb = alb * macro[..., None]
    alb = alb * np.array([1.0, 0.99, 0.96], np.float32)
    alb = alb * (1.0 - 0.35 * stain)[..., None]
    alb = mix(alb, alb * 0.5, spec * (gid > 0.8) * 0.8)
    alb = mix(alb, np.minimum(alb * 1.5, 0.8), spec * (gid <= 0.8) * 0.5)
    rust = np.array([0.33, 0.17, 0.09], np.float32)
    alb = mix(alb, rust, np.clip(streak * 0.7 + ties * 0.4, 0, 1))
    alb = alb * (0.45 + 0.55 * cav[..., None])
    alb = mix(alb, np.array([0.045, 0.043, 0.042], np.float32), np.clip(crack_core * 0.9 + pits * 0.7, 0, 1))
    rough = np.clip(0.78 + 0.14 * fbm(n, 12, 12, 3, 81) - 0.12 * stain - 0.1 * spec, 0.5, 0.98)
    return dict(albedo=alb, height=np.clip(h * 1.7 + 0.4, 0, 1), roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=2.4)


def mat_wall(n):
    rows, cols = 8, 4
    yy = np.arange(n)[:, None] / n * rows
    xx = np.arange(n)[None, :] / n * cols
    row = np.floor(yy).astype(int)
    xs = xx + (row % 2) * 0.5
    col = np.floor(xs).astype(int)
    u = xs - np.floor(xs)
    v = yy - np.floor(yy)
    bid = hashf(row * 17.0 + (col % cols) * 3.1 + 0.7)
    bid2 = hashf(row * 5.3 + (col % cols) * 9.7 + 2.1)
    d = np.minimum(np.minimum(u, 1 - u) * 0.5, np.minimum(v, 1 - v))          # cegła 2:1
    mortar_w = 0.045
    bevel = smoothstep(mortar_w, mortar_w + 0.05, d)
    chips = smoothstep(0.58, 0.72, fbm(n, 36, 36, 4, 5))
    edge_chip = chips * (1.0 - smoothstep(0.0, 0.18, d))
    brick = np.clip(bevel - edge_chip * 0.6, 0, 1)
    surf = 0.5 * fbm(n, 22, 22, 5, 9) + 0.5 * fbm(n, 90, 90, 4, 19)
    pitch = (bid2 - 0.5) * 0.10
    h = brick * (0.60 + 0.30 * surf + pitch) + (1 - brick) * (0.18 + 0.14 * fbm(n, 130, 130, 3, 29))
    base = ramp(bid * 0.6 + fbm(n, 8, 8, 3, 15) * 0.4, [(0.0, (0.30, 0.100, 0.075)), (0.35, (0.43, 0.17, 0.11)), (0.7, (0.38, 0.19, 0.14)), (1.0, (0.22, 0.10, 0.09))])
    burnt = smoothstep(0.82, 0.95, bid2)
    base = mix(base, np.array([0.12, 0.07, 0.07], np.float32), burnt * 0.7)
    base *= (0.75 + 0.5 * surf)[..., None]
    mortar = ramp(0.6 * fbm(n, 70, 70, 4, 25) + 0.4 * fbm(n, 6, 6, 3, 26), [(0.0, (0.30, 0.285, 0.26)), (1.0, (0.47, 0.455, 0.42))])
    alb = mix(mortar, base, brick)
    streak = smoothstep(0.35, 0.80, fbm(n, 14, 1, 4, 33)) * 0.5 + smoothstep(0.5, 0.9, fbm(n, 5, 3, 4, 35)) * 0.5
    alb = alb * (1.0 - 0.45 * streak)[..., None]
    sal = smoothstep(0.64, 0.82, fbm(n, 7, 7, 3, 47))
    alb = mix(alb, np.array([0.62, 0.60, 0.56], np.float32), sal * 0.22 * (0.5 + 0.5 * (1 - brick)))
    cav = ao_from_height(h, (1, 3, 10), 7.0)
    alb = alb * (0.45 + 0.55 * cav[..., None])
    rough = np.clip(0.86 + 0.10 * surf - 0.12 * streak, 0.55, 1.0)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=3.2)


def mat_metal(n):
    seam, du, dv = grid_mask(n, 2, 2, 0.014)
    d = np.minimum(du[None, :], dv[:, None])
    plate = smoothstep(0.0, 0.035, d)
    h = 0.55 + 0.16 * plate
    ys = np.arange(n)[:, None] / n
    xs = np.arange(n)[None, :] / n
    riv = np.zeros((n, n), np.float32)
    rivstreak = np.zeros((n, n), np.float32)
    for gx in range(2):
        for gy in range(2):
            for k in range(6):
                t = (k + 0.5) / 6.0 * 0.5
                for (px, py) in ((gx * 0.5 + t, gy * 0.5 + 0.03), (gx * 0.5 + t, gy * 0.5 + 0.47), (gx * 0.5 + 0.03, gy * 0.5 + t), (gx * 0.5 + 0.47, gy * 0.5 + t)):
                    dx = (xs - px + 0.5) % 1.0 - 0.5
                    dy = (ys - py + 0.5) % 1.0 - 0.5
                    r = np.sqrt(dx * dx + dy * dy)
                    riv = np.maximum(riv, (1.0 - smoothstep(0.0, 0.0105, r)) ** 0.5)
                    below = np.clip(dy, 0, 1)
                    wob = 0.003 * np.sin(below * 70.0 + px * 50.0)
                    rivstreak = np.maximum(rivstreak, np.exp(-((dx + wob) / (0.004 + 0.008 * below)) ** 2) * np.exp(-below * 6.0) * (dy > 0.0))
    h += riv * 0.20
    scr = np.zeros((n, n), np.float32)
    for k, (a, b) in enumerate([(1, 0), (0, 1), (1, 1), (1, -1), (3, 1), (1, 3)]):
        s = stripes(n, a, b, 200 + 31 * k, 900 + k)
        scr = np.maximum(scr, smoothstep(0.93, 0.98, s) * smoothstep(0.35, 0.6, vnoise(n, 4 + k, 4 + k, 910 + k)))
    brush = vnoise(n, 3, 260, 5) * 0.6 + vnoise(n, 9, 520, 6) * 0.4
    dent = fbm(n, 4, 4, 5, 15)
    h += (dent - 0.5) * 0.10 - scr * 0.02
    cav = ao_from_height(h, (1, 4, 12), 8.0)
    curv = curvature(h, 1.8)
    edge = smoothstep(0.003, 0.02, curv) * 1.3 + (1 - plate) * 0.4
    chip_n = smoothstep(0.60, 0.72, fbm(n, 12, 12, 6, 25))
    chip_n2 = smoothstep(0.66, 0.78, fbm(n, 40, 40, 4, 27))
    wear = np.clip(edge * (0.4 + chip_n2) + chip_n * 0.9 + riv * 0.6, 0, 1)
    wear_hard = smoothstep(0.45, 0.55, wear)
    rust_n = smoothstep(0.50, 0.70, fbm(n, 5, 5, 6, 35))
    rust = np.clip(rust_n * (0.35 + (1 - cav) * 2.0) + rivstreak * 0.9 + wear_hard * 0.35 * smoothstep(0.45, 0.7, fbm(n, 28, 28, 4, 37)), 0, 1)
    rust = smoothstep(0.30, 0.65, rust)
    paint = ramp(fbm(n, 4, 4, 4, 45), [(0.0, (0.085, 0.105, 0.085)), (1.0, (0.17, 0.20, 0.15))])
    paint = paint * (0.92 + 0.16 * fbm(n, 90, 90, 3, 47))[..., None]
    paint = mix(paint, paint * 1.6, scr * 0.5)
    steel = np.dstack([0.50 + 0.30 * brush] * 3) * np.array([1.0, 1.0, 1.02], np.float32)
    rustc = ramp(fbm(n, 26, 26, 5, 55), [(0.0, (0.17, 0.060, 0.025)), (0.55, (0.36, 0.15, 0.06)), (1.0, (0.55, 0.30, 0.11))])
    alb = mix(paint, steel, wear_hard * (1 - rust) * 0.95)
    alb = mix(alb, rustc, rust * 0.9)
    alb = alb * (0.5 + 0.5 * cav[..., None])
    metallic = np.clip(wear_hard * (1 - rust) * 0.95 + rust * 0.1, 0, 1)
    rough = np.clip(0.50 - 0.15 * metallic + rust * 0.40 + (brush - 0.5) * 0.08 * wear_hard + scr * -0.15, 0.2, 0.95)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=metallic, ao=cav, ns=3.0)


def mat_grate(n):
    # kratka spawana: pręty nośne (wysokie, płaskie) i poprzeczki (okrągłe, rzadziej) — otwory to szczeliny
    nb, nc = 12, 6
    u = (np.arange(n) / n * nb) % 1.0
    vv = (np.arange(n) / n * nc) % 1.0
    bar_w, rod_w = 0.30, 0.20
    bear = 1.0 - smoothstep(bar_w * 0.5, bar_w * 0.5 + 0.04, np.minimum(u, 1 - u))          # pręty pionowe
    rod = 1.0 - smoothstep(rod_w * 0.5, rod_w * 0.5 + 0.05, np.minimum(vv, 1 - vv))          # poprzeczki poziome
    bearm = np.broadcast_to(bear[None, :], (n, n))
    rodm = np.broadcast_to(rod[:, None], (n, n))
    rod_prof = np.sqrt(np.clip(rodm, 0, 1))
    h = np.maximum(bearm * 0.95, rod_prof * 0.70)
    mask = np.maximum(bearm, rodm)
    alpha = smoothstep(0.12, 0.45, mask)
    weld = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    for iy in range(nc):
        for ix in range(nb):
            cx, cy = (ix + 0.5) / nb, (iy + 0.5) / nc
            weld = np.maximum(weld, np.exp(-(((xx - cx) * nb) ** 2 + ((yy - cy) * nc) ** 2) * 18.0))
    h += weld * 0.04 * mask
    sf1, _, sid = voronoi(n, 22, 7)
    spangle = 0.75 + 0.5 * sid                         # cynkowa „rozeta” — komórki o różnym odbiciu
    cav = ao_from_height(h, (2, 6, 16), 5.0)
    rust = smoothstep(0.50, 0.78, fbm(n, 7, 7, 5, 7)) * np.clip(0.45 + (1 - cav) * 1.2, 0, 1) + weld * 0.35
    rust = np.clip(rust, 0, 1)
    zinc = np.dstack([0.34 * spangle] * 3) * np.array([1.0, 1.0, 1.03], np.float32)
    zinc = zinc * (0.85 + 0.3 * fbm(n, 40, 40, 3, 9))[..., None]
    rustc = ramp(fbm(n, 24, 24, 3, 11), [(0.0, (0.19, 0.08, 0.04)), (1.0, (0.42, 0.20, 0.08))])
    dirt = smoothstep(0.55, 0.85, fbm(n, 5, 5, 4, 13))
    alb = mix(zinc, rustc, rust * 0.75)
    alb = alb * (1.0 - 0.45 * dirt)[..., None]
    alb = alb * (0.45 + 0.55 * cav[..., None])
    alb = alb * np.clip(mask * 1.2, 0, 1)[..., None]
    metallic = np.clip((1 - rust) * 0.9, 0, 1) * alpha
    rough = np.clip(0.38 + rust * 0.45 + dirt * 0.2, 0.2, 0.95)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=metallic, alpha=alpha, ao=cav, ns=2.8)


def _grain(n, vertical, seed, fine=160, wave=0.35):
    """Pole drewna: słoje (łagodnie wypaczone, nie „smużone”), włókna, pory. Zwraca (słoje, włókna, pory)."""
    a = fbm(n, 2, 2, 4, seed) - 0.5
    b = fbm(n, 5, 5, 3, seed + 1) - 0.5
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    across = xx if vertical else yy
    along = yy if vertical else xx
    phase = across * 7.0 + a * wave * 2.2 + b * 0.18 * np.sin(along * 6.2832 * 2)
    rings = 0.5 + 0.5 * np.sin(phase * 6.2832)
    rings = rings ** 1.4
    ax, ay = (fine, 3) if vertical else (3, fine)
    fibers = vnoise(n, ax, ay, seed + 2) * 0.6 + vnoise(n, ax * 2 if vertical else 5, 5 if vertical else ay * 2, seed + 3) * 0.4
    pores = smoothstep(0.78, 0.9, vnoise(n, (fine // 2) if vertical else 12, 12 if vertical else (fine // 2), seed + 4))
    return rings, fibers, pores


def mat_plank(n):
    planks = 6
    yy = np.arange(n)[:, None] / n * planks
    row = np.floor(yy).astype(int)
    v = yy - np.floor(yy)
    grain = np.zeros((n, n), np.float32)
    fiber = np.zeros((n, n), np.float32)
    pores = np.zeros((n, n), np.float32)
    for r in range(planks):
        rings, fibers, pr = _grain(n, False, 100 + r * 13)
        sh = int(hashf(r + 1.0) * n)
        sel = row == r
        grain = np.where(sel, np.roll(rings, sh, axis=1), grain)
        fiber = np.where(sel, np.roll(fibers, sh, axis=1), fiber)
        pores = np.where(sel, np.roll(pr, sh, axis=1), pores)
    xs = np.broadcast_to((np.arange(n) / n)[None, :], (n, n))
    gap = 1.0 - smoothstep(0.02, 0.06, np.minimum(v, 1 - v))
    joint = hashf(np.arange(planks) * 3.7 + 1.0)
    end = np.zeros((n, n), np.float32)
    for r in range(planks):
        dd = np.abs(((xs - joint[r] + 0.5) % 1.0) - 0.5)
        end = np.where(row == r, 1.0 - smoothstep(0.002, 0.010, dd), end)
    knots = np.zeros((n, n), np.float32)
    rng = np.random.default_rng(5)
    for _ in range(7):
        cx, cy = rng.random(), rng.random()
        rr = 0.010 + rng.random() * 0.012
        dx = (np.arange(n)[None, :] / n - cx + 0.5) % 1.0 - 0.5
        dy = (np.arange(n)[:, None] / n - cy + 0.5) % 1.0 - 0.5
        dd = np.sqrt((dx * 0.6) ** 2 + dy * dy)
        knots = np.maximum(knots, np.exp(-(dd / rr) ** 2))
    nails = np.zeros((n, n), np.float32)
    nailstreak = np.zeros((n, n), np.float32)
    for r in range(planks):
        for k in (-1, 1):
            cx = (joint[r] + k * 0.028) % 1.0
            cy = (r + 0.5) / planks
            dx = (np.arange(n)[None, :] / n - cx + 0.5) % 1.0 - 0.5
            dy = (np.arange(n)[:, None] / n - cy + 0.5) % 1.0 - 0.5
            nails = np.maximum(nails, 1.0 - smoothstep(0.0035, 0.0065, np.sqrt(dx * dx + dy * dy)))
            below = np.clip(dy, 0, 1)
            nailstreak = np.maximum(nailstreak, np.exp(-(dx / (0.004 + 0.01 * below)) ** 2) * np.exp(-below * 14) * (dy > 0))
    bow = 0.10 * (1.0 - (2 * v - 1) ** 2)
    cracks = smoothstep(0.80, 0.93, vnoise(n, 4, 70, 71) * 0.5 + fbm(n, 8, 110, 3, 72) * 0.5) * (1 - gap) * smoothstep(0.4, 0.6, fbm(n, 3, 3, 3, 73))
    h = 0.55 + bow + 0.10 * grain + 0.07 * fiber - 0.05 * pores - 0.40 * gap - 0.25 * end + 0.10 * knots + 0.09 * nails - 0.18 * cracks
    cav = ao_from_height(h, (1, 3, 9), 7.0)
    tone = np.clip(0.55 * grain + 0.35 * fiber + 0.2 * fbm(n, 3, 3, 3, 81) - 0.25 * knots, 0, 1)
    wood = ramp(tone, [(0.0, (0.14, 0.085, 0.050)), (0.5, (0.30, 0.19, 0.11)), (1.0, (0.46, 0.33, 0.20))])
    bt = np.zeros((n, n), np.float32)
    for r in range(planks):
        bt = np.where(row == r, (hashf(r * 2.3 + 0.4) - 0.5), bt)
    wood = wood * (1.0 + 0.35 * bt)[..., None]
    weather = smoothstep(0.30, 0.78, fbm(n, 4, 4, 4, 91)) * (0.6 + 0.4 * vnoise(n, 3, 90, 92))
    gray = ramp(0.6 * fiber + 0.4 * fbm(n, 6, 80, 3, 93), [(0.0, (0.17, 0.165, 0.15)), (1.0, (0.40, 0.385, 0.35))])
    alb = mix(wood, gray, weather * 0.6)
    alb = alb * (0.8 + 0.4 * (1 - pores * 0.5))[..., None]
    alb = alb * (0.4 + 0.6 * cav[..., None])
    alb = mix(alb, np.full_like(alb, 0.025), np.clip(gap * 0.9 + end * 0.8 + cracks * 0.7, 0, 1))
    alb = mix(alb, np.array([0.28, 0.12, 0.05], np.float32), nailstreak * 0.55)
    alb = mix(alb, np.array([0.11, 0.10, 0.10], np.float32), nails * 0.9)
    rough = np.clip(0.80 + 0.12 * fiber + 0.06 * weather - 0.05 * pores, 0.55, 1.0)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=nails * 0.8, ao=cav, ns=2.4)


def mat_post(n):
    rings, fibers, pores = _grain(n, True, 200, fine=140, wave=0.6)
    deep = smoothstep(0.80, 0.93, ridged(n, 5, 1, 4, 207) * 0.75 + fibers * 0.2) * smoothstep(0.35, 0.60, fbm(n, 2, 3, 3, 211))
    deep = blur(deep, 1.2)
    small = smoothstep(0.84, 0.94, vnoise(n, 24, 3, 213)) * smoothstep(0.4, 0.6, fbm(n, 3, 5, 3, 214))
    knot = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    for (cx, cy, rr) in ((0.30, 0.62, 0.05), (0.72, 0.22, 0.035)):
        dx = (xx - cx + 0.5) % 1.0 - 0.5
        dy = (yy - cy + 0.5) % 1.0 - 0.5
        dd = np.sqrt(dx * dx + (dy * 0.6) ** 2)
        knot = np.maximum(knot, np.exp(-(dd / rr) ** 2))
    h = 0.55 + 0.10 * rings + 0.07 * fibers - 0.05 * pores - 0.45 * deep - 0.12 * small + 0.12 * knot
    cav = ao_from_height(h, (1, 3, 10), 7.0)
    tone = np.clip(0.45 * rings + 0.35 * fibers + 0.25 * fbm(n, 4, 4, 3, 215) - 0.2 * knot, 0, 1)
    wood = ramp(tone, [(0.0, (0.11, 0.075, 0.048)), (0.5, (0.25, 0.17, 0.105)), (1.0, (0.41, 0.31, 0.21))])
    gray = ramp(0.5 * fibers + 0.5 * fbm(n, 24, 5, 3, 217), [(0.0, (0.16, 0.15, 0.14)), (1.0, (0.37, 0.35, 0.32))])
    weather = smoothstep(0.25, 0.7, fbm(n, 3, 3, 4, 219))
    alb = mix(wood, gray, weather * 0.7)
    moss = smoothstep(0.60, 0.82, fbm(n, 4, 4, 4, 221)) * (1 - deep) * (0.5 + 0.5 * yy)
    alb = mix(alb, np.array([0.09, 0.15, 0.06], np.float32), moss * 0.4)
    alb = alb * (0.4 + 0.6 * cav[..., None])
    alb = mix(alb, np.full_like(alb, 0.022), np.clip(deep * 0.95 + small * 0.6, 0, 1))
    rough = np.clip(0.84 + 0.10 * fibers - 0.04 * pores, 0.55, 1.0)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=2.6)


def mat_mud(n):
    base = fbm(n, 3, 3, 5, 301)
    undul = fbm(n, 9, 9, 5, 303)
    rut = smoothstep(0.55, 0.75, vnoise(n, 2, 7, 321) * 0.6 + fbm(n, 3, 10, 3, 322) * 0.4)         # koleiny
    dry = smoothstep(0.50, 0.72, fbm(n, 3, 3, 3, 307)) * (1 - rut)
    f1, f2, cid = voronoi(n, 6, 305)
    edge = warp(np.clip(f2 - f1, 0, 1), fbm(n, 4, 4, 3, 309) - 0.5, fbm(n, 4, 4, 3, 311) - 0.5, 0.05)
    crack_core = (1.0 - smoothstep(0.012, 0.035, edge)) * dry
    crack_soft = (1.0 - smoothstep(0.02, 0.11, edge)) * dry
    curl = dome(f1, 0.55, 1.6) * dry                    # podwinięte brzegi spękanych płatów
    pools = smoothstep(0.56, 0.66, fbm(n, 4, 4, 5, 313)) * (1 - dry) * 1.0
    pf1, _, pid = voronoi(n, 70, 315)
    pebbles = dome(pf1, 0.26, 0.7) * (pid > 0.86)
    h = 0.50 + 0.18 * base + 0.10 * undul - 0.22 * crack_core - 0.06 * crack_soft + 0.08 * curl + 0.10 * pebbles - 0.18 * rut
    h = np.where(pools > 0.5, 0.34 + 0.006 * undul, h)
    cav = ao_from_height(h, (2, 6, 18), 5.0)
    mud = ramp(0.6 * base + 0.4 * undul, [(0.0, (0.060, 0.042, 0.028)), (0.5, (0.13, 0.092, 0.058)), (1.0, (0.23, 0.17, 0.105))])
    dryc = ramp(fbm(n, 16, 16, 4, 317), [(0.0, (0.24, 0.185, 0.12)), (1.0, (0.40, 0.33, 0.23))])
    alb = mix(mud, dryc, dry * 0.75)
    alb = mix(alb, np.array([0.035, 0.026, 0.019], np.float32), np.clip(pools * 0.8 + crack_core * 0.8 + rut * 0.3, 0, 1))
    pebc = ramp(pid, [(0.86, (0.10, 0.09, 0.08)), (1.0, (0.19, 0.17, 0.15))])
    alb = mix(alb, pebc, np.clip(pebbles * 2.0, 0, 1))
    alb = alb * (0.5 + 0.5 * cav[..., None])
    wet = np.clip(1.0 - dry * 0.9 + rut * 0.5, 0, 1)
    rough = np.clip(0.75 - 0.35 * wet + 0.12 * (fbm(n, 34, 34, 3, 319) - 0.5) - 0.65 * pools, 0.03, 0.98)
    rough = np.maximum(rough, np.clip(pebbles * 2.0, 0, 1) * 0.9)
    return dict(albedo=alb, height=np.clip(h, 0, 1), roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=2.4)


def mat_oil(n):
    wx = fbm(n, 3, 3, 3, 401) - 0.5
    wy = fbm(n, 3, 3, 3, 402) - 0.5
    flow = warp(fbm(n, 4, 4, 5, 403), wx, wy, 0.18)
    gx = np.roll(flow, -1, 1) - np.roll(flow, 1, 1)
    gy = np.roll(flow, -1, 0) - np.roll(flow, 1, 0)
    grad = np.clip(np.sqrt(gx * gx + gy * gy) * 60.0, 0, 1)                # cienka warstwa tęczuje przy krawędziach nacieków
    ripples = fbm(n, 24, 24, 4, 405) * 0.6 + fbm(n, 80, 80, 3, 406) * 0.4
    h = 0.5 + 0.05 * (ripples - 0.5) + 0.06 * (flow - 0.5)
    ph = flow * 14.0
    irid = np.dstack([0.5 + 0.5 * np.sin(ph), 0.5 + 0.5 * np.sin(ph + 2.1), 0.5 + 0.5 * np.sin(ph + 4.2)]).astype(np.float32)
    alb = np.dstack([np.full((n, n), 0.016, np.float32)] * 3)
    alb = alb + irid * (0.045 * grad)[..., None]
    clump = smoothstep(0.62, 0.78, fbm(n, 6, 6, 4, 409))
    alb = mix(alb, np.full_like(alb, 0.006), clump * 0.85)
    cav = np.clip(0.92 + 0.08 * ripples, 0, 1)
    rough = np.clip(0.06 + 0.10 * clump + 0.04 * (ripples - 0.5) + 0.04 * grad, 0.03, 0.4)
    return dict(albedo=alb, height=h, roughness=rough, metallic=np.zeros((n, n), np.float32), ao=cav, ns=1.1)


def mat_water(n):
    # fale: kilka kierunkowych sinusoid + szum, okresowe (całkowite liczby fal na kafel)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    h = np.zeros((n, n), np.float32)
    rng = np.random.default_rng(501)
    for i in range(7):
        kx, ky = rng.integers(-5, 6), rng.integers(-5, 6)
        if kx == 0 and ky == 0:
            kx = 3
        h += np.sin((kx * xx + ky * yy) * 2 * np.pi + rng.random() * 6.28) * (0.5 / (1 + 0.25 * (abs(kx) + abs(ky))))
    h += (fbm(n, 12, 12, 5, 503) - 0.5) * 0.6
    h = (h - h.min()) / (h.max() - h.min())
    foam = smoothstep(0.80, 0.97, h) * smoothstep(0.45, 0.7, fbm(n, 18, 18, 4, 507))
    deep = ramp(h, [(0.0, (0.008, 0.045, 0.060)), (0.6, (0.025, 0.12, 0.15)), (1.0, (0.07, 0.22, 0.25))])
    alb = mix(deep, np.full_like(deep, 0.75), foam * 0.6)
    rough = np.clip(0.04 + foam * 0.6, 0.02, 0.9)
    return dict(albedo=alb, height=h, roughness=rough, metallic=np.zeros((n, n), np.float32), ao=np.ones((n, n), np.float32), ns=1.6)


MATERIALS = {
    "terrain": mat_terrain, "concrete": mat_concrete, "metal": mat_metal, "grate": mat_grate, "plank": mat_plank,
    "post": mat_post, "wall": mat_wall, "mud": mat_mud, "oil": mat_oil, "water": mat_water,
}

# ---------------------------------------------------------------- zapis i podgląd


def to8(a):
    return (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def save_set(name, m, out):
    n = m["height"].shape[0]
    alb = np.clip(m["albedo"], 0, 1)
    if "alpha" in m:
        img = np.dstack([alb, m["alpha"][..., None]])
        Image.fromarray(to8(img)).save(os.path.join(out, name + "_albedo.png"))
    else:
        Image.fromarray(to8(alb)).save(os.path.join(out, name + "_albedo.png"))
    nrm = normal_from_height(m["height"], m["ns"])
    Image.fromarray(to8(nrm)).save(os.path.join(out, name + "_normal.png"))
    ao = m.get("ao", np.ones((n, n), np.float32))
    orm = np.dstack([ao, m["roughness"], m["metallic"]])
    Image.fromarray(to8(orm)).save(os.path.join(out, name + "_orm.png"))
    Image.fromarray(to8(m["height"])).save(os.path.join(out, name + "_height.png"))
    return nrm, orm


def lit(alb, nrm, orm, light=(0.55, 0.65, 0.52)):
    """Podgląd: oświetlenie kierunkowe + otoczenie z AO + wspólne odbicie (gradient nieba) dla metali."""
    L = np.array(light, np.float32)
    L /= np.linalg.norm(L)
    V = np.array([0.0, 0.0, 1.0], np.float32)
    H = L + V
    H /= np.linalg.norm(H)
    n = nrm * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-5)
    ao, rough, metal = orm[..., 0], orm[..., 1], orm[..., 2]
    ndl = np.clip((n * L).sum(-1), 0, 1)
    ndh = np.clip((n * H).sum(-1), 0, 1)
    shin = np.clip(2.0 / np.maximum(rough ** 2, 1e-3) - 2.0, 2.0, 600.0)
    spec = (shin + 8.0) / 8.0 * ndh ** shin * ndl * 0.25 * (1.0 - rough * 0.6)
    f0 = 0.04 * (1 - metal)[..., None] + alb * metal[..., None]
    diffuse = alb * (1 - metal)[..., None]
    sky = 0.35 + 0.65 * (n[..., 1] * 0.5 + 0.5)
    env = f0 * (sky * (1.0 - rough) * 0.9)[..., None]
    col = diffuse * (ndl[..., None] * 1.6 + 0.30 * ao[..., None]) + f0 * spec[..., None] * 1.0 + env * ao[..., None]
    col = col / (1.0 + col * 0.35)                       # miękkie ściskanie świateł
    return np.clip(col, 0, 1) ** (1 / 2.2)


def preview(name, alb, nrm, orm, out, alpha=None):
    n = alb.shape[0]
    one = lit(alb, nrm, orm)
    if alpha is not None:
        one = one * alpha[..., None] + 0.08 * (1 - alpha[..., None])
    tile = np.tile(one, (2, 2, 1))
    size = 512
    a = Image.fromarray(to8(one)).resize((size, size), Image.LANCZOS)
    b = Image.fromarray(to8(tile)).resize((size, size), Image.LANCZOS)
    c = Image.new("RGB", (size * 2 + 6, size), (20, 20, 20))
    c.paste(a, (0, 0))
    c.paste(b, (size + 6, 0))
    c.save(os.path.join(out, "preview", name + "_preview.png"))


def main():
    a = sys.argv[1:]
    res = int(next((x.split("=")[1] for x in a if x.startswith("--res=")), 1024))
    out = next((x.split("=")[1] for x in a if x.startswith("--out=")), "art_src/world_pbr")
    only = next((x.split("=")[1].split(",") for x in a if x.startswith("--only=")), list(MATERIALS))
    os.makedirs(os.path.join(out, "preview"), exist_ok=True)
    for name in only:
        m = MATERIALS[name](res)
        nrm, orm = save_set(name, m, out)
        if "--preview" in a:
            preview(name, np.clip(m["albedo"], 0, 1), nrm, orm, out, m.get("alpha"))
        print("OK", name)


if __name__ == "__main__":
    main()
