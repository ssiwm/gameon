"""Materiały świata HD (etap 3): beton, metal, woda, kratownica, deski, ściana tła, słup, błoto i olej — albedo + mapa normalnych, 16 px na piksel świata.

Uruchomienie (numpy + Pillow + scipy): python prototype/tools/world_hd_materials.py
Wynik: art/world/mat_<nazwa>.png i mat_<nazwa>_n.png (1024×576), układ jak terrain_hd (patrz world_hd_tiles.py):
    y 0..256   : wypełnienie — pas 4 kafli, okresowy w poziomie i w pionie
    y 256..576 : kafel wierzchni (64 px przewisu + 256 px kafla), gdy nad kaflem nie ma bryły
Platformy (kratownica, deski) zajmują tylko górne 64 px kafla (4 piksele świata); reszta kafla jest przezroczysta.
Albedo bez oświetlenia (światło dają lampy gry przez mapę normalnych: R = prawo, G = góra, B = ku widzowi).
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

from world_hd_tiles import ALBEDO_GAIN, OVER, S, W, fbm, noise, normal_from_height, ramp, rng, soil

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "world")
H0 = S + OVER + S


def stripes_x(h, w, py, px):
    """Szum rozciągnięty w poziomie (słoje, szczotkowanie)."""
    return fbm(h, w, py, px, 4)


def disc(canvas, cy, cx, r, val, soft=1.5):
    yy, xx = np.mgrid[0:canvas.shape[0], 0:canvas.shape[1]]
    d = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    m = np.clip((r - d) / soft, 0, 1)
    canvas[:] = canvas * (1 - m) + val * m


def seams(h, w, step_x, step_y, width, depth):
    """Rowki w siatce (okresowe)."""
    yy, xx = np.mgrid[0:h, 0:w]
    gx = np.minimum(xx % step_x, step_x - (xx % step_x))
    gy = np.minimum(yy % step_y, step_y - (yy % step_y))
    g = np.minimum(gx, gy).astype(float)
    return -depth * np.clip(1 - g / width, 0, 1) ** 0.6


def cracks(h, w, n, depth, wid=(2, 4)):
    im = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(im)
    for _ in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(0, np.pi)
        pts = []
        for _k in range(rng.integers(10, 26)):
            ang += rng.normal(0, 0.45)
            x += np.cos(ang) * 9
            y += np.sin(ang) * 9
            pts.append((x, y))
        for ox in (-w, 0, w):
            for oy in (-h, 0, h):
                dr.line([(a + ox, b + oy) for a, b in pts], fill=255, width=int(rng.uniform(*wid)))
    return gaussian_filter(np.asarray(im, float) / 255.0, 1.0, mode="wrap") * depth


def pack(name, fill_rgb, fill_h, top_rgb=None, top_h=None, top_a=None, fill_a=None, nk=0.55):
    """Zapisuje atlas (wiersz 0 = wypełnienie, wiersz 1 = wierzch z przewisem) + mapę normalnych."""
    atlas = np.zeros((H0, W, 4))
    nrm = np.zeros((H0, W, 4))
    fa = np.ones((S, W)) if fill_a is None else fill_a
    atlas[:S, :, :3] = np.clip(fill_rgb * ALBEDO_GAIN, 0, 1)
    atlas[:S, :, 3] = fa
    nrm[:S, :, :3] = normal_from_height(gaussian_filter(fill_h, 0.6, mode="wrap"), True, nk)
    nrm[:S, :, 3] = fa
    if top_rgb is None:
        top_rgb, top_h, top_a = fill_rgb, fill_h, fa
        pad = np.zeros((OVER, W))
        top_rgb = np.concatenate([np.zeros((OVER, W, 3)), top_rgb], 0)
        top_h = np.concatenate([pad, top_h], 0)
        top_a = np.concatenate([pad, top_a], 0)
    atlas[S:, :, :3] = np.clip(top_rgb * (ALBEDO_GAIN if top_rgb.max() <= 1.0 and top_rgb is not fill_rgb else 1.0), 0, 1)
    atlas[S:, :, 3] = top_a
    nrm[S:, :, :3] = normal_from_height(gaussian_filter(top_h, 0.6, mode="wrap"), True, nk)
    nrm[S:, :, 3] = top_a
    nrm[..., :3] = np.where(nrm[..., 3:4] > 0.02, nrm[..., :3], np.array([0.5, 0.5, 1.0]))
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"mat_{name}.png"))
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"mat_{name}_n.png"))
    print("OK", name)


def with_top_edge(rgb, hgt, edge_px=18, lift=0.22, chip=True):
    """Kafel wierzchni: nad kaflem 64 px przezroczystego przewisu, na górnej krawędzi rozjaśniony fazowany pas."""
    top_rgb = np.concatenate([np.zeros((OVER, W, 3)), rgb.copy()], 0)
    top_h = np.concatenate([np.zeros((OVER, W)), hgt.copy()], 0)
    a = np.concatenate([np.zeros((OVER, W)), np.ones((S, W))], 0)
    n = fbm(S + OVER, W, 2, 64, 3)
    edge = OVER + edge_px * (0.6 + 0.8 * n[0:1, :])                         # nierówna krawędź
    rows = np.arange(S + OVER)[:, None]
    if chip:
        a = np.where(rows < OVER + 3 + 5 * (n - 0.5) * 2, 0.0, a)
    k = np.clip((edge - rows) / edge_px, 0, 1)[..., None]
    top_rgb = np.clip(top_rgb * (1 + lift * k * 2.2), 0, 1)
    top_h = top_h + 4.0 * k[..., 0]
    return top_rgb, top_h, a


def concrete():
    n_big, n_fine = fbm(S, W, 3, 12, 4), fbm(S, W, 48, 192, 2)
    t = np.clip(0.35 + 0.5 * n_big + 0.2 * (n_fine - 0.5), 0, 1)
    rgb = ramp(t, [(0, (0.15, 0.155, 0.16)), (0.5, (0.22, 0.225, 0.23)), (1, (0.31, 0.315, 0.32))])
    h = 3.0 * (fbm(S, W, 4, 16, 4) - 0.5) + 1.2 * (n_fine - 0.5)
    h += seams(S, W, 256, 256, 7, 9)
    cr = cracks(S, W, 6, 5.0)
    h -= cr
    rgb *= (1 - 0.55 * np.clip(cr / 5.0, 0, 1))[..., None]
    # zacieki (ciemne, pionowe) i plamy rdzy
    st = np.clip(fbm(S, W, 2, 80, 3) - 0.6, 0, 1) * 3.0
    rgb *= (1 - 0.22 * st)[..., None]
    rust = np.clip(fbm(S, W, 3, 14, 3) - 0.66, 0, 1) * 4.0
    rgb = rgb * (1 - 0.6 * rust[..., None]) + 0.6 * rust[..., None] * np.array([0.30, 0.15, 0.08])
    # ciemna fuga przy rowkach
    g = np.clip(-seams(S, W, 256, 256, 7, 1.0), 0, 1)
    rgb *= (1 - 0.6 * g)[..., None]
    for cx in (22, 234):                                                    # śruby w rogach płyty
        for cy in (22, 234):
            for k in range(0, W, 256):
                hh = h.copy()
                disc(hh, cy, cx + k, 9, h.max() + 3.0)
                h = hh
                dd = np.zeros((S, W))
                disc(dd, cy, cx + k, 9, 1.0)
                rgb = rgb * (1 - 0.35 * dd[..., None]) + 0.35 * dd[..., None] * np.array([0.35, 0.34, 0.33])
    top_rgb, top_h, top_a = with_top_edge(rgb, h, 16, 0.30)
    pack("concrete", rgb, h, top_rgb, top_h, top_a)


def metal():
    streak = fbm(S, W, 2, 128, 4)
    t = np.clip(0.4 + 0.6 * streak, 0, 1)
    rgb = ramp(t, [(0, (0.13, 0.14, 0.15)), (0.6, (0.21, 0.22, 0.24)), (1, (0.29, 0.30, 0.32))])
    h = 1.5 * (fbm(S, W, 2, 256, 3) - 0.5)
    h += seams(S, W, 256, 256, 8, 7)
    yy, xx = np.mgrid[0:S, 0:W]
    inset = np.minimum(np.minimum(xx % 256, 255 - xx % 256), np.minimum(yy % 256, 255 - yy % 256))
    bevel = np.clip((inset - 8) / 14.0, 0, 1)
    h += (1 - bevel) * -3.0
    rgb *= (0.78 + 0.22 * bevel)[..., None]
    for cx in (32, 224):
        for cy in (32, 224):
            for k in range(0, W, 256):
                disc(h, cy, cx + k, 12, h.max() + 4.0)
                dd = np.zeros((S, W))
                disc(dd, cy, cx + k, 12, 1.0)
                rgb = rgb * (1 - 0.5 * dd[..., None]) + 0.5 * dd[..., None] * np.array([0.5, 0.5, 0.52])
    # zadrapania i rdza w narożnikach
    sc = np.clip(fbm(S, W, 40, 160, 2) - 0.62, 0, 1) * 3.0
    rgb = rgb * (1 - 0.3 * sc[..., None]) + 0.3 * sc[..., None] * 0.55
    rust = np.clip(fbm(S, W, 3, 12, 3) - 0.68, 0, 1) * 4.0
    rgb = rgb * (1 - 0.55 * rust[..., None]) + 0.55 * rust[..., None] * np.array([0.34, 0.16, 0.07])
    top_rgb, top_h, top_a = with_top_edge(rgb, h, 12, 0.35, chip=False)
    pack("metal", rgb, h, top_rgb, top_h, top_a)


def water():
    base = ramp(np.clip(0.2 + 0.6 * fbm(S, W, 3, 12, 3), 0, 1), [(0, (0.025, 0.07, 0.10)), (1, (0.06, 0.16, 0.22))])
    rid = 1 - np.abs(2 * fbm(S, W, 4, 16, 4) - 1)
    caus = np.clip((rid - 0.86) * 8, 0, 1)
    rgb = base + caus[..., None] * np.array([0.03, 0.08, 0.10])
    h = 6.0 * (fbm(S, W, 3, 12, 3) - 0.5) + 3.0 * caus
    # powierzchnia: jasny pas z falowaną krawędzią
    top_rgb = np.concatenate([np.zeros((OVER, W, 3)), rgb.copy()], 0)
    top_h = np.concatenate([np.zeros((OVER, W)), h], 0)
    wav = 6 * (fbm(1, W, 1, 24, 3)[0] - 0.5)
    rows = np.arange(S + OVER)[:, None]
    surf = OVER + 4 + wav[None, :]
    a = (rows >= surf).astype(float)
    k = np.clip(1 - (rows - surf) / 34.0, 0, 1)[..., None] * (rows >= surf)[..., None]
    top_rgb = np.where(a[..., None] > 0, top_rgb + k * np.array([0.14, 0.30, 0.34]), 0)
    top_h = top_h + 4 * k[..., 0]
    pack("water", rgb, h, top_rgb, top_h, a, nk=0.35)


def grate():
    A = np.zeros((S, W))
    rgb = np.zeros((S, W, 3))
    h = np.zeros((S, W))
    body = np.zeros((S, W))
    yy, xx = np.mgrid[0:S, 0:W]
    slab = ((yy >= 6) & (yy < 62)).astype(float)
    body = slab
    t = np.clip(0.4 + 0.5 * fbm(S, W, 2, 128, 3), 0, 1)
    metal_c = ramp(t, [(0, (0.15, 0.16, 0.18)), (1, (0.30, 0.32, 0.35))])
    rgb = metal_c
    top_hi = np.clip(1 - (yy - 6) / 12.0, 0, 1)
    rgb = rgb * (1 + 0.7 * top_hi[..., None])
    bot_sh = np.clip((yy - 46) / 16.0, 0, 1)
    rgb = rgb * (1 - 0.45 * bot_sh[..., None])
    slot = ((yy >= 24) & (yy < 42) & ((xx % 64) >= 14) & ((xx % 64) < 50)).astype(float)
    slot = gaussian_filter(slot, 1.2)
    rgb = rgb * (1 - 0.85 * slot[..., None])
    h = -4.0 * slot + 2.0 * top_hi
    for k in range(0, W, 256):
        for cx in (10, 246):
            disc(h, 34, cx + k, 5, h.max() + 3.0)
    rust = np.clip(fbm(S, W, 2, 24, 3) - 0.68, 0, 1) * 4.0
    rgb = rgb * (1 - 0.5 * rust[..., None]) + 0.5 * rust[..., None] * np.array([0.30, 0.14, 0.06])
    a = gaussian_filter(body, 0.8)
    fill_rgb = rgb
    pack("grate", fill_rgb, h, fill_a=a, nk=0.7)


def plank():
    yy, xx = np.mgrid[0:S, 0:W]
    slab = gaussian_filter(((yy >= 4) & (yy < 62)).astype(float), 0.8)
    gr = fbm(S, W, 2, 96, 5)
    t = np.clip(0.3 + 0.7 * gr, 0, 1)
    rgb = ramp(t, [(0, (0.20, 0.12, 0.06)), (0.5, (0.34, 0.21, 0.11)), (1, (0.46, 0.30, 0.16))])
    seam = np.clip(1 - np.minimum(xx % 256, 256 - xx % 256) / 5.0, 0, 1)
    rgb *= (1 - 0.6 * seam)[..., None]
    top_hi = np.clip(1 - (yy - 4) / 10.0, 0, 1)
    rgb *= (1 + 0.5 * top_hi)[..., None]
    rgb *= (1 - 0.35 * np.clip((yy - 48) / 14.0, 0, 1))[..., None]
    h = 3.0 * (gr - 0.5) - 3.0 * seam + 2.0 * top_hi
    for k in range(0, W, 256):
        for cx in (14, 242):
            disc(h, 24, cx + k, 4, h.max() + 3.0)
            dd = np.zeros((S, W))
            disc(dd, 24, cx + k, 4, 1.0)
            rgb = rgb * (1 - 0.6 * dd[..., None]) + 0.6 * dd[..., None] * 0.18
    pack("plank", rgb, h, fill_a=slab, nk=0.8)


def wall():
    """Ściana tła: ciemna cegła w wiązaniu, 4 wiersze na kafel (cegła 128×64 px = 8×4 px świata)."""
    yy, xx = np.mgrid[0:S, 0:W]
    row = yy // 64
    off = np.where(row % 2 == 0, 0, 64)
    bx = (xx + off) % 128
    by = yy % 64
    gx = np.minimum(bx, 128 - bx)
    gy = np.minimum(by, 64 - by)
    g = np.minimum(gx, gy).astype(float)
    mortar = np.clip(1 - g / 5.0, 0, 1)
    brick_id = ((xx + off) // 128 + row * 7) % 5
    tone = 0.75 + 0.1 * brick_id + 0.25 * (fbm(S, W, 3, 12, 3) - 0.5)
    base = np.array([0.065, 0.060, 0.062])
    rgb = base[None, None, :] * tone[..., None]
    rgb = rgb * (1 - 0.6 * mortar[..., None]) + 0.6 * mortar[..., None] * np.array([0.03, 0.03, 0.035])
    grain = fbm(S, W, 48, 192, 2) - 0.5
    rgb *= (1 + 0.35 * grain)[..., None]
    moss = np.clip(fbm(S, W, 2, 8, 3) - 0.64, 0, 1) * 4.0
    rgb = rgb * (1 - 0.5 * moss[..., None]) + 0.5 * moss[..., None] * np.array([0.04, 0.07, 0.04])
    h = -4.0 * mortar + 2.5 * grain + 1.5 * (brick_id / 4.0)
    pack("wall", rgb, h, nk=0.9)


def post():
    """Słup tła: pionowa belka na środku kafla (x 64..192) na ciemnym tle."""
    yy, xx = np.mgrid[0:S, 0:W]
    bg = np.array([0.045, 0.05, 0.065])
    rgb = np.ones((S, W, 3)) * bg
    cx = (xx % 256 - 128).astype(float)
    inb = gaussian_filter((np.abs(cx) < 66).astype(float), 1.0)
    gr = fbm(S, W, 64, 3, 5)
    t = np.clip(0.25 + 0.75 * gr, 0, 1)
    wood = ramp(t, [(0, (0.10, 0.06, 0.03)), (0.5, (0.18, 0.11, 0.06)), (1, (0.27, 0.17, 0.09))])
    round_sh = np.clip(1 - (np.abs(cx) / 66.0) ** 2, 0, 1) ** 0.5
    wood *= (0.55 + 0.6 * round_sh)[..., None]
    rgb = bg * (1 - inb[..., None]) + wood * inb[..., None]
    h = inb * (10 * round_sh + 3 * (gr - 0.5))
    pack("post", rgb, h, nk=0.8)


def mud():
    alb, h = soil()                                                         # ta sama struktura co glina, inna paleta
    tint = np.array([0.62, 0.74, 0.50])
    alb = np.clip(alb * tint / ALBEDO_GAIN, 0, 1)                      # soil() ma już wzmocnienie albedo — pack() doda je ponownie
    wet = np.clip(fbm(S, W, 3, 12, 3) - 0.5, 0, 1)[..., None]
    alb = alb * (1 - 0.3 * wet) + 0.3 * wet * np.array([0.10, 0.15, 0.08])
    top_rgb, top_h, top_a = with_top_edge(alb, h, 22, 0.1)
    top_rgb = np.where(top_a[..., None] > 0, top_rgb, 0)
    pack("mud", alb, h, top_rgb, top_h, top_a)


def oil():
    n = fbm(S, W, 4, 16, 4)
    base = np.ones((S, W, 3)) * np.array([0.025, 0.025, 0.03])
    hue = np.stack([0.5 + 0.5 * np.sin(n * 18.0), 0.5 + 0.5 * np.sin(n * 18.0 + 2.1), 0.5 + 0.5 * np.sin(n * 18.0 + 4.2)], -1)
    sheen = np.clip(fbm(S, W, 2, 8, 3) - 0.45, 0, 1)[..., None]
    rgb = base + 0.22 * hue * sheen
    h = 2.5 * (fbm(S, W, 3, 12, 3) - 0.5)
    top_rgb, top_h, top_a = with_top_edge(rgb, h, 14, 1.6, chip=False)
    pack("oil", rgb, h, top_rgb, top_h, top_a, nk=0.3)


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in (concrete, metal, water, grate, plank, wall, post, mud, oil):
        fn()


if __name__ == "__main__":
    main()
