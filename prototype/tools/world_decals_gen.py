"""Generator śladów zniszczeń świata 3D: grafiti, pęknięcia, ślady po kulach, sadza, zacieki, odpryski, wilgoć + mapy „brudu” (warstwa detalu materiałów).

Uruchomienie (numpy + scipy + Pillow): python prototype/tools/world_decals_gen.py [--out=prototype/art/world3d]
Wynik:
  decals/<nazwa>.png      — sprite RGBA 512 px po dłuższym boku (alfa = krycie, kolor = farba / brud); rozmieszcza je `Level3D.build_decals`
  grime_<rodzaj>.png     — okresowa (kafelkowana) tekstura RGBA warstwy brudu (RGB = kolor, A = krycie); `Level3D.make_pbr` kładzie ją jako
      osobny przebieg (`next_pass`) w wielkiej skali świata (kafel ok. 14 m), więc plamy nie powtarzają się razem z kaflem materiału;
      rodzaje: stone (zacieki, sadza, wilgoć), rust (rdza, olej), organic (próchnica, pleśń, ciemne plamy)
Rozmiary sprite'ów w kaflach (szer. × wys.) zapisuje `Level3D.DECALS`; trzymaj je w zgodzie z proporcjami poniżej.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_pbr_gen as G  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT_STENCIL = os.path.join(ROOT, "prototype", "art", "fonts", "BigShouldersStencilDisplay-VF.ttf")
FONT_HAND = os.path.join(ROOT, "prototype", "art", "fonts", "SpecialElite-Regular.ttf")

PAINT = {
    "red": (0.40, 0.045, 0.035),
    "white": (0.62, 0.62, 0.58),
    "yellow": (0.56, 0.44, 0.07),
    "black": (0.025, 0.025, 0.028),
    "blood": (0.20, 0.012, 0.012),
    "blue": (0.06, 0.12, 0.30),
}


def rng_for(name):
    return np.random.default_rng(abs(hash(name)) % (2 ** 32) if False else sum(ord(c) * (i + 1) * 131 for i, c in enumerate(name)))


def noise_rect(w, h, f, octaves, seed):
    """Okresowy fbm o wymiarach w × h (wycinek kwadratu)."""
    n = max(w, h)
    return G.fbm(n, f, f, octaves, seed)[:h, :w]


def spray_alpha(mask, name, drips=True, wear=0.55):
    """Maska liter 0..1 → alfa „z puszki”: miękkie brzegi, mgiełka, zacieki, odpryski i wyblakłe place."""
    h, w = mask.shape
    r = rng_for(name)
    core = gaussian_filter(mask, 1.3)
    fuzz = gaussian_filter(mask, 7.0)
    speck = (r.random((h, w)) < fuzz * 0.55).astype(np.float32) * 0.5
    a = np.clip(core * 1.25 + speck * (1.0 - core), 0, 1)
    if drips:
        ink = mask > 0.5
        for _ in range(int(w / 26)):
            x = int(r.integers(8, w - 8))
            ys = np.where(ink[:, x])[0]
            if len(ys) == 0 or r.random() < 0.45:
                continue
            y0 = int(ys.max())
            ln = int(r.integers(18, int(h * 0.42)))
            wd = int(r.integers(2, 4))
            for k in range(ln):
                y = y0 + k
                if y >= h:
                    break
                fade = 1.0 - k / ln
                a[y, max(0, x - wd // 2): x + wd // 2 + 1] = np.maximum(a[y, max(0, x - wd // 2): x + wd // 2 + 1], 0.9 * fade ** 0.7)
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    yy, xx = y0 + ln + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and dx * dx + dy * dy <= 6:
                        a[yy, xx] = max(a[yy, xx], 0.8)
    worn = G.smoothstep(0.40, 0.62, noise_rect(w, h, 5, 4, 700 + len(name))) * 0.55 + 0.45
    chip = G.smoothstep(0.64, 0.74, noise_rect(w, h, 30, 3, 800 + len(name)))
    a = a * (1.0 - wear * (1.0 - worn)) * (1.0 - 0.9 * chip * wear)
    return np.clip(a, 0, 1)


def paint_img(alpha, color, name, var=0.25):
    h, w = alpha.shape
    n = noise_rect(w, h, 14, 3, 900 + len(name))
    base = np.array(color, np.float32)
    rgb = base[None, None, :] * (1.0 + (n[..., None] - 0.5) * var * 2.0)
    out = np.dstack([np.clip(rgb, 0, 1) ** (1 / 2.2), alpha])      # sRGB
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def text_mask(text, font_path, size, canvas=(1024, 512), angle=0.0, pad=0.08, weight=None, stroke=0):
    w, h = canvas
    f = ImageFont.truetype(font_path, size)
    if weight is not None:
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
    im = Image.new("L", (w * 2, h * 2), 0)
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    tx = (w * 2 - (bb[2] - bb[0])) // 2 - bb[0]
    ty = (h * 2 - (bb[3] - bb[1])) // 2 - bb[1]
    d.text((tx, ty), text, font=f, fill=255, stroke_width=stroke)
    im = im.rotate(angle, resample=Image.BICUBIC)
    im = im.crop((w // 2, h // 2, w // 2 + w, h // 2 + h))
    return np.asarray(im, np.float32) / 255.0


def save(img, out, name):
    os.makedirs(os.path.join(out, "decals"), exist_ok=True)
    img.save(os.path.join(out, "decals", name + ".png"))


# ---------------------------------------------------------------- grafiti

def g_text(out, name, text, color, font="stencil", size=190, angle=0.0, stroke=0, canvas=(1024, 512), drips=True):
    f = FONT_STENCIL if font == "stencil" else FONT_HAND
    m = text_mask(text, f, size, canvas, angle, weight="ExtraBold" if font == "stencil" else None, stroke=stroke)
    a = spray_alpha(m, name, drips=drips)
    save(paint_img(a, PAINT[color], name), out, name)


def g_symbol_eye(out, name="g_eye", color="red"):
    w, h = 1024, 512
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    # oko: dwa łuki i źrenica, promienie
    cx, cy = w // 2, h // 2
    d.arc((cx - 260, cy - 150, cx + 260, cy + 150), 200, 340, fill=255, width=22)
    d.arc((cx - 260, cy - 150, cx + 260, cy + 150), 20, 160, fill=255, width=22)
    d.ellipse((cx - 70, cy - 70, cx + 70, cy + 70), outline=255, width=24)
    d.ellipse((cx - 28, cy - 28, cx + 28, cy + 28), fill=255)
    for k in range(-3, 4):
        ang = math.radians(270 + k * 18)
        d.line((cx + math.cos(ang) * 190, cy + math.sin(ang) * 190, cx + math.cos(ang) * 235, cy + math.sin(ang) * 235), fill=255, width=14)
    a = spray_alpha(np.asarray(im, np.float32) / 255.0, name)
    save(paint_img(a, PAINT[color], name), out, name)


def g_symbol_tally(out, name="g_tally", color="white"):
    w, h = 1024, 512
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    r = rng_for(name)
    for grp in range(3):
        x0 = 130 + grp * 280
        for k in range(4):
            x = x0 + k * 46
            d.line((x + r.integers(-4, 5), 110 + r.integers(-8, 9), x + r.integers(-6, 7), 400 + r.integers(-8, 9)), fill=255, width=17)
        d.line((x0 - 28, 330, x0 + 4 * 46, 170), fill=255, width=17)
    a = spray_alpha(np.asarray(im, np.float32) / 255.0, name, wear=0.7)
    save(paint_img(a, PAINT[color], name), out, name)


def g_symbol_arrow(out, name="g_arrow", color="yellow"):
    w, h = 1024, 512
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    d.line((140, 256, 800, 256), fill=255, width=36)
    d.polygon([(760, 130), (930, 256), (760, 382)], fill=255)
    a = spray_alpha(np.asarray(im, np.float32) / 255.0, name)
    save(paint_img(a, PAINT[color], name), out, name)


def g_symbol_xcircle(out, name="g_xcircle", color="red"):
    w, h = 1024, 512
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    cx, cy, r = w // 2, h // 2, 200
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=30)
    d.line((cx - r * 0.7, cy - r * 0.7, cx + r * 0.7, cy + r * 0.7), fill=255, width=34)
    d.line((cx - r * 0.7, cy + r * 0.7, cx + r * 0.7, cy - r * 0.7), fill=255, width=34)
    a = spray_alpha(np.asarray(im, np.float32) / 255.0, name)
    save(paint_img(a, PAINT[color], name), out, name)


def g_handprint(out, name="g_hand", color="blood"):
    """Odcisk dłoni z krwi: dłoń, cztery palce rozchylone wachlarzem i kciuk, rozmazany u nasady; zacieki z krawędzi."""
    w, h = 512, 512
    S = 2
    im = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(im)
    cx, cy = 250 * S, 300 * S
    d.rounded_rectangle((cx - 78 * S, cy - 30 * S, cx + 78 * S, cy + 130 * S), radius=44 * S, fill=255)
    for off, ln, ang in ((-54, 205, -9), (-19, 245, -2), (17, 235, 4), (52, 190, 12)):
        x0 = cx + off * S
        y0 = cy - 20 * S
        a = math.radians(ang)
        x1 = x0 + math.sin(a) * ln * S
        y1 = y0 - math.cos(a) * ln * S
        wd = 38 * S
        d.line((x0, y0, x1, y1), fill=255, width=wd)
        d.ellipse((x1 - wd / 2, y1 - wd / 2, x1 + wd / 2, y1 + wd / 2), fill=255)
    # kciuk z lewej strony
    tx0, ty0 = cx - 66 * S, cy + 60 * S
    a = math.radians(-62)
    tx1, ty1 = tx0 + math.sin(a) * 135 * S, ty0 - math.cos(a) * 135 * S
    d.line((tx0, ty0, tx1, ty1), fill=255, width=44 * S)
    d.ellipse((tx1 - 22 * S, ty1 - 22 * S, tx1 + 22 * S, ty1 + 22 * S), fill=255)
    # nadgarstek
    d.rounded_rectangle((cx - 50 * S, cy + 110 * S, cx + 46 * S, cy + 215 * S), radius=20 * S, fill=255)
    im = im.resize((w, h), Image.LANCZOS)
    m = gaussian_filter(np.asarray(im, np.float32) / 255.0, 1.6)
    smear = G.smoothstep(0.30, 0.70, noise_rect(w, h, 9, 4, 91))
    a = np.clip(m * (0.50 + 0.65 * smear), 0, 1)
    r = rng_for(name)
    for _ in range(11):
        x = int(r.integers(cx // S - 70, cx // S + 70))
        y0 = int(r.integers(cy // S + 90, cy // S + 150))
        ln = int(r.integers(30, 170))
        for k in range(ln):
            if y0 + k < h:
                a[y0 + k, x - 1:x + 2] = np.maximum(a[y0 + k, x - 1:x + 2], 0.85 * (1 - k / ln) ** 0.6)
    save(paint_img(a, PAINT[color], name, var=0.15), out, name)


# ---------------------------------------------------------------- uszkodzenia

def d_soot(out, name="d_soot"):
    w, h = 512, 512
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * 0.5, h * 0.78
    dx = (xx - cx) / (w * 0.42)
    dy = (cy - yy) / (h * 0.85)                                   # sadza unosi się w górę
    plume = 1.0 - np.sqrt(dx ** 2 * (1.0 + 1.5 * np.clip(dy, 0, 1)) + (np.clip(dy, 0, 1.4) * 0.9) ** 2 + np.clip(-dy, 0, 1) ** 2 * 6.0)
    n = noise_rect(w, h, 7, 6, 31)
    a = np.clip(G.smoothstep(0.0, 0.55, plume + (n - 0.5) * 0.9), 0, 1) ** 0.9
    streak = G.smoothstep(0.5, 0.8, noise_rect(w, h, 40, 2, 33) * 0.5 + np.broadcast_to(G.vnoise(w, 40, 1, 35)[0][None, :w], (h, w)) * 0.5)
    a = np.clip(a * (0.65 + 0.5 * streak), 0, 1) * 0.82
    save(paint_img(a, (0.012, 0.012, 0.014), name, var=0.1), out, name)


def d_waterstain(out, name="d_water"):
    w, h = 512, 512
    cols = G.vnoise(w, 36, 1, 41)[0][:w]
    cols = np.broadcast_to(cols[None, :], (h, w))
    cols2 = np.broadcast_to(G.vnoise(w, 11, 1, 43)[0][:w][None, :], (h, w))
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / h
    streak = G.smoothstep(0.35, 0.7, cols * 0.55 + cols2 * 0.45 + (noise_rect(w, h, 6, 4, 45) - 0.5) * 0.6)
    top_fade = G.smoothstep(0.0, 0.18, yy)
    tail = 1.0 - G.smoothstep(0.35, 1.0, yy + (noise_rect(w, h, 8, 3, 47) - 0.5) * 0.4 + (1.0 - cols) * 0.3)
    a = streak * top_fade * tail
    tide = (1.0 - np.abs(G.smoothstep(0.55, 0.62, yy + (noise_rect(w, h, 7, 3, 49) - 0.5) * 0.3) - 0.5) * 2.0) * 0.0
    salt = G.smoothstep(0.58, 0.62, yy + (noise_rect(w, h, 7, 3, 49) - 0.5) * 0.25) * (1 - G.smoothstep(0.62, 0.70, yy + (noise_rect(w, h, 7, 3, 49) - 0.5) * 0.25))
    dark = np.clip(a * 0.7 + 0.0, 0, 1)
    salt_a = np.clip(salt * streak * 0.55, 0, 1)
    img_d = paint_img(dark, (0.035, 0.032, 0.028), name, var=0.2)
    img_s = paint_img(salt_a, (0.62, 0.60, 0.54), name, var=0.1)
    img_d.alpha_composite(img_s)
    save(img_d, out, name)


def _branch(d, x, y, ang, ln, width, depth, r, scale=1.0):
    pts = [(x, y)]
    for _ in range(int(ln / 14)):
        ang += r.normal(0, 0.28)
        x += math.cos(ang) * 14
        y += math.sin(ang) * 14
        pts.append((x, y))
    d.line(pts, fill=255, width=max(1, int(width)), joint="curve")
    if depth > 0:
        for i in range(2, len(pts) - 2, 3):
            if r.random() < 0.55:
                bx, by = pts[i]
                _branch(d, bx, by, ang + r.choice([-1, 1]) * r.uniform(0.5, 1.2), ln * 0.55, width * 0.6, depth - 1, r, scale)


def d_crack(out, name="d_crack", seed=1):
    w, h = 512, 512
    S = 2
    im = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(im)
    r = np.random.default_rng(1000 + seed)
    _branch(d, w * S * r.uniform(0.35, 0.65), 0.04 * h * S, math.pi / 2 + r.normal(0, 0.25), h * S * 0.9, 7, 2, r)
    im = im.resize((w, h), Image.LANCZOS)
    m = np.asarray(im, np.float32) / 255.0
    core = gaussian_filter(m, 0.7)
    edge = np.roll(gaussian_filter(m, 1.6), 3, axis=1) * (1 - core)
    a_dark = np.clip(core * 1.6, 0, 1)
    img = paint_img(a_dark, (0.012, 0.012, 0.012), name, var=0.1)
    img.alpha_composite(paint_img(np.clip(edge * 0.6, 0, 1), (0.50, 0.48, 0.45), name, var=0.1))
    save(img, out, name)


def d_bullets(out, name="d_bullets"):
    w, h = 512, 512
    r = np.random.default_rng(77)
    im = Image.new("L", (w, h), 0)
    chip = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    dc = ImageDraw.Draw(chip)
    cx, cy = w // 2, h // 2
    for k in range(int(r.integers(6, 10))):
        x = cx + r.normal(0, 85)
        y = cy + r.normal(0, 70)
        rad = r.uniform(7, 13)
        d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=255)
        for _ in range(int(r.integers(4, 8))):
            ang = r.uniform(0, 6.283)
            ln = r.uniform(rad * 1.2, rad * 3.4)
            dc.line((x, y, x + math.cos(ang) * ln, y + math.sin(ang) * ln), fill=255, width=2)
        dc.ellipse((x - rad * 1.8, y - rad * 1.8, x + rad * 1.8, y + rad * 1.8), outline=255, width=3)
    m = gaussian_filter(np.asarray(im, np.float32) / 255.0, 1.2)
    c = gaussian_filter(np.asarray(chip, np.float32) / 255.0, 1.0)
    img = paint_img(np.clip(c * 0.55, 0, 1), (0.42, 0.40, 0.37), name, var=0.2)
    img.alpha_composite(paint_img(np.clip(m * 1.4, 0, 1), (0.01, 0.01, 0.01), name, var=0.05))
    save(img, out, name)


def d_plaster(out, name="d_plaster"):
    w, h = 512, 512
    n = noise_rect(w, h, 5, 5, 61)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - w / 2) / (w * 0.42)) ** 2 + ((yy - h / 2) / (h * 0.40)) ** 2)
    shape = G.smoothstep(1.0, 0.82, d + (n - 0.5) * 1.1)
    rim = G.smoothstep(0.0, 0.5, shape) * (1 - G.smoothstep(0.5, 1.0, shape))
    inner = G.smoothstep(0.55, 0.95, shape)
    rough = noise_rect(w, h, 40, 3, 63)
    sub = np.dstack([np.full((h, w), 0.075, np.float32) * (0.7 + 0.6 * rough),
                     np.full((h, w), 0.068, np.float32) * (0.7 + 0.6 * rough),
                     np.full((h, w), 0.060, np.float32) * (0.7 + 0.6 * rough)])
    brick = G.smoothstep(0.55, 0.7, noise_rect(w, h, 9, 3, 65))[..., None] * np.array([0.05, 0.02, 0.015], np.float32)
    sub = sub + brick * inner[..., None]
    out_img = paint_img(np.clip(inner * 0.95, 0, 1), (0.1, 0.09, 0.08), name)
    arr = np.asarray(out_img, np.float32) / 255.0
    arr[..., :3] = np.clip(sub, 0, 1) ** (1 / 2.2)
    arr[..., 3] = np.clip(inner * 0.95, 0, 1)
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    img.alpha_composite(paint_img(np.clip(rim * 0.6, 0, 1), (0.52, 0.50, 0.46), name, var=0.1))
    save(img, out, name)


def d_rustbleed(out, name="d_rustbleed"):
    w, h = 512, 512
    r = np.random.default_rng(88)
    a = np.zeros((h, w), np.float32)
    ox = w // 2
    for k in range(26):
        x = int(ox + r.normal(0, 50))
        wd = int(r.integers(2, 9))
        ln = int(r.integers(80, 470))
        y0 = int(r.integers(10, 80))
        for y in range(y0, min(h, y0 + ln)):
            f = 1 - (y - y0) / ln
            xx = x + int(2 * math.sin(y * 0.05 + k))
            a[y, max(0, xx - wd // 2): xx + wd // 2 + 1] = np.maximum(a[y, max(0, xx - wd // 2): xx + wd // 2 + 1], 0.8 * f ** 0.8)
    a = gaussian_filter(a, 1.2)
    a = a * (0.6 + 0.6 * G.smoothstep(0.35, 0.7, noise_rect(w, h, 14, 3, 71)))
    save(paint_img(np.clip(a, 0, 1), (0.30, 0.115, 0.04), name, var=0.35), out, name)


def d_damp(out, name="d_damp"):
    w, h = 512, 512
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / h
    n = noise_rect(w, h, 4, 6, 81)
    a = G.smoothstep(0.42, 0.68, n + (yy - 0.5) * 0.35) * 0.8
    spots = G.smoothstep(0.80, 0.90, noise_rect(w, h, 36, 2, 83)) * G.smoothstep(0.3, 0.6, n)
    img = paint_img(np.clip(a, 0, 1), (0.018, 0.035, 0.022), name, var=0.35)
    img.alpha_composite(paint_img(np.clip(spots * 0.85, 0, 1), (0.01, 0.02, 0.012), name, var=0.1))
    save(img, out, name)


# ---------------------------------------------------------------- warstwa detalu (okresowa)

def grime_maps(out, kind, n=512):
    """Okresowa maska brudu + kolor warstwy detalu materiału (stone: zacieki i sadza; rust: rdza; organic: ciemne plamy i pleśń)."""
    seed = {"stone": 1100, "rust": 1200, "organic": 1300}[kind]
    yy = np.mgrid[0:n, 0:n][0].astype(np.float32) / n
    base = G.fbm(n, 3, 3, 6, seed)
    big = G.smoothstep(0.42, 0.66, base)
    mid = G.smoothstep(0.50, 0.70, G.fbm(n, 9, 9, 5, seed + 3))
    cols = np.broadcast_to(G.vnoise(n, 28, 1, seed + 5)[0][None, :], (n, n))
    run = G.smoothstep(0.55, 0.85, cols * 0.6 + G.fbm(n, 5, 5, 3, seed + 7) * 0.5)
    if kind == "stone":
        mask = np.clip(big * 0.9 + run * G.smoothstep(0.0, 0.3, yy) * 0.55 + mid * 0.25, 0, 1)
        dark = np.dstack([np.full((n, n), 0.020, np.float32), np.full((n, n), 0.020, np.float32), np.full((n, n), 0.022, np.float32)])
        damp = np.dstack([np.full((n, n), 0.020, np.float32), np.full((n, n), 0.030, np.float32), np.full((n, n), 0.025, np.float32)])
        salt = np.dstack([np.full((n, n), 0.34, np.float32), np.full((n, n), 0.33, np.float32), np.full((n, n), 0.31, np.float32)])
        pick = G.smoothstep(0.55, 0.7, G.fbm(n, 4, 4, 4, seed + 9))[..., None]
        sp = G.smoothstep(0.7, 0.85, G.fbm(n, 6, 6, 4, seed + 11))[..., None]
        col = dark * (1 - pick) + damp * pick
        col = col * (1 - sp * 0.5) + salt * sp * 0.5
    elif kind == "rust":
        mask = np.clip(big * 0.85 + run * 0.35 + mid * 0.3, 0, 1)
        r1 = np.dstack([np.full((n, n), 0.20, np.float32), np.full((n, n), 0.075, np.float32), np.full((n, n), 0.03, np.float32)])
        r2 = np.dstack([np.full((n, n), 0.09, np.float32), np.full((n, n), 0.035, np.float32), np.full((n, n), 0.02, np.float32)])
        pick = G.smoothstep(0.45, 0.65, G.fbm(n, 6, 6, 4, seed + 9))[..., None]
        col = r1 * (1 - pick) + r2 * pick
    else:
        mask = np.clip(big * 0.9 + mid * 0.3, 0, 1)
        d1 = np.dstack([np.full((n, n), 0.018, np.float32), np.full((n, n), 0.016, np.float32), np.full((n, n), 0.012, np.float32)])
        d2 = np.dstack([np.full((n, n), 0.025, np.float32), np.full((n, n), 0.04, np.float32), np.full((n, n), 0.018, np.float32)])
        pick = G.smoothstep(0.5, 0.7, G.fbm(n, 5, 5, 4, seed + 9))[..., None]
        col = d1 * (1 - pick) + d2 * pick
    col = np.clip(col, 0, 1) ** (1 / 2.2)
    rgba = np.dstack([col, np.clip(mask * 0.85, 0, 1)])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, f"grime_{kind}.png"))


def main():
    a = sys.argv[1:]
    out = next((x.split("=")[1] for x in a if x.startswith("--out=")), os.path.join(ROOT, "prototype", "art", "world3d"))
    os.makedirs(out, exist_ok=True)
    # grafiti (rozmiar docelowy w kaflach: patrz Level3D.DECALS)
    g_text(out, "g_dont_listen", "DON'T LISTEN", "red", size=200, angle=-4)
    g_text(out, "g_they_hear", "THEY HEAR", "white", size=225, angle=3)
    g_text(out, "g_silence", "SILENCE", "yellow", size=235, angle=-2)
    g_text(out, "g_no_exit", "NO WAY OUT", "red", size=185, angle=2)
    g_text(out, "g_patrol7", "PATROL 7", "black", size=235, angle=-3)
    g_text(out, "g_help", "HELP US", "white", font="hand", size=205, angle=-5)
    g_text(out, "g_run", "RUN", "red", font="hand", size=330, angle=4)
    g_text(out, "g_47", "'87", "yellow", size=420, angle=-6)
    g_symbol_eye(out)
    g_symbol_tally(out)
    g_symbol_arrow(out)
    g_symbol_xcircle(out)
    g_handprint(out)
    # uszkodzenia
    d_soot(out)
    d_waterstain(out)
    d_crack(out, "d_crack_a", 1)
    d_crack(out, "d_crack_b", 2)
    d_bullets(out)
    d_plaster(out)
    d_rustbleed(out)
    d_damp(out)
    for k in ("stone", "rust", "organic"):
        grime_maps(out, k)
    print("OK", len(os.listdir(os.path.join(out, "decals"))), "dekali")


if __name__ == "__main__":
    main()
