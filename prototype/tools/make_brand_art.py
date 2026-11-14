"""Ikona gry i ekran uruchamiania (boot splash) — generator.

    python tools/make_brand_art.py [--preview ARKUSZ.png]

Zapisuje do art/brand/:
  icon.png         512 px, ikona okna i projektu (application/config/icon)
  icon.ico         16–256 px, ikona pliku .exe i paska zadań Windows (application/config/windows_native_icon)
  boot_splash.png  1920×1080, obraz ekranu uruchamiania (application/boot_splash/image)

Styl jak menu główne i strona da87.eu: znak „DEAD AIR '87” krojem Big Shoulders Stencil (waga 800),
kość + krew na ziemi (#050605), ciepła poświata lampy. Pod znakiem „martwa linia” sygnału radiowego
z jednym drgnięciem — dead air = cisza w eterze.
Małe rozmiary ikony (16–48 px) rysowane osobno: same „87”, bez napisu i ramki, żeby nie robiła się z nich plama.
"""

from __future__ import annotations

import io
import math
import random
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "brand"
FONT = ROOT / "art" / "fonts" / "BigShouldersStencilDisplay-VF.ttf"
MONO = ROOT / "art" / "fonts" / "IBMPlexMono-Medium.ttf"
WEIGHT = 800

# Paleta z scripts/ui_theme.gd.
GROUND = (5, 6, 5)          ## GROUND — tło ekranu uruchamiania (musi się zgadzać z boot_splash/bg_color)
DECK = (11, 12, 11)         ## DECK_BG
LINE2 = (61, 58, 48)        ## LINE2
WARM = (232, 226, 196)      ## WARM — kość jasna
DANGER = (229, 72, 58)      ## DANGER — krew
ACCENT = (217, 146, 46)     ## ACCENT — lampa
MUTED = (141, 138, 124)     ## MUTED


def font(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([WEIGHT])
    return f


def glow(size: tuple[int, int], center: tuple[float, float], radius: tuple[float, float],
         color: tuple[int, int, int], strength: float) -> Image.Image:
    """Miękka eliptyczna poświata (RGBA), zanika do zera przed brzegiem promienia."""
    w, h = size
    # Liczymy w małej rozdzielczości i skalujemy — gładko i szybko.
    s = 4
    sw, sh = max(1, w // s), max(1, h // s)
    a = Image.new("L", (sw, sh))
    px = a.load()
    cx, cy = center[0] / s, center[1] / s
    rx, ry = radius[0] / s, radius[1] / s
    for y in range(sh):
        for x in range(sw):
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            v = max(0.0, 1.0 - d)
            px[x, y] = int(255 * strength * v * v * (3 - 2 * v))
    a = a.resize((w, h), Image.BICUBIC)
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(a)
    return layer


def wordmark(height: int) -> Image.Image:
    """„DEAD AIR '87” — kość + krew, przycięte do konturu liter (RGBA)."""
    f = font(height)
    main, year = "DEAD AIR", " '87"
    w_main = f.getlength(main)
    asc, desc = f.getmetrics()
    img = Image.new("RGBA", (int(w_main + f.getlength(year)) + 20, asc + desc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((0, 0), main, font=f, fill=WARM)
    d.text((w_main, 0), year, font=f, fill=DANGER)
    return img.crop(img.getbbox())


def text_mask(text: str, height_px: int) -> Image.Image:
    """Maska L tekstu dociętego do konturu; height_px = wysokość cyfr po przycięciu (w przybliżeniu)."""
    f = font(int(height_px * 1.45))
    asc, desc = f.getmetrics()
    m = Image.new("L", (int(f.getlength(text)) + 40, asc + desc), 0)
    ImageDraw.Draw(m).text((20, 0), text, font=f, fill=255)
    m = m.crop(m.getbbox())
    scale = height_px / m.height
    return m.resize((max(1, round(m.width * scale)), height_px), Image.LANCZOS)


def grain(size: tuple[int, int], amount: int, seed: int) -> Image.Image:
    """Ziarno filmu jako warstwa L wokół 128."""
    rnd = random.Random(seed)
    w, h = size
    data = bytes(128 + rnd.randint(-amount, amount) for _ in range(w * h))
    return Image.frombytes("L", size, data)


# ---------------------------------------------------------------- ikona


def icon_large(px: int) -> Image.Image:
    """Ikona od 64 px w górę: płytka z ramką, „87” krwią, napis DEAD AIR kością, poświata lampy od dołu."""
    S = 4  # nadpróbkowanie dla gładkich krawędzi
    n = px * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    r = round(n * 0.16)
    m = round(n * 0.03)
    tile = Image.new("RGBA", (n, n), DECK + (255,))
    tile.alpha_composite(glow((n, n), (n * 0.5, n * 1.02), (n * 0.85, n * 0.7), ACCENT, 0.42))
    tile.alpha_composite(glow((n, n), (n * 0.5, n * 0.95), (n * 0.45, n * 0.35), (255, 196, 110), 0.18))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((m, m, n - 1 - m, n - 1 - m), r, fill=255)
    img.paste(tile, (0, 0), mask)
    d = ImageDraw.Draw(img)
    edge = max(S, round(n * 0.012))
    d.rounded_rectangle((m, m, n - 1 - m, n - 1 - m), r, outline=LINE2 + (255,), width=edge)

    # „87” — główny znak.
    h87 = round(n * 0.50)
    m87 = text_mask("87", h87)
    if m87.width > n * 0.70:
        m87 = m87.resize((round(n * 0.70), round(h87 * n * 0.70 / m87.width)), Image.LANCZOS)
    x = (n - m87.width) // 2
    y = round(n * 0.40)
    red = Image.new("RGBA", m87.size, DANGER + (255,))
    # Cień pod cyframi, żeby odcinały się od poświaty.
    sh = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", m87.size, (0, 0, 0, 200)), (x, y + round(n * 0.012)), m87)
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(n * 0.012)))
    img.paste(red, (x, y), m87)

    # „DEAD AIR” nad cyframi — szerokość jak „87”.
    hd = round(n * 0.155)
    md = text_mask("DEAD AIR", hd)
    wd = min(round(n * 0.70), md.width)
    md = md.resize((wd, round(hd * wd / md.width)), Image.LANCZOS)
    xd = (n - md.width) // 2
    yd = round(n * 0.40 - n * 0.06 - md.height)
    img.paste(Image.new("RGBA", md.size, WARM + (255,)), (xd, yd), md)

    return img.resize((px, px), Image.LANCZOS)


def icon_small(px: int) -> Image.Image:
    """Ikona 16–48 px: ciemna płytka i same „87”, wyrównane do pikseli."""
    S = 8
    n = px * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    r = round(n * 0.14)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, n - 1, n - 1), r, fill=DECK + (255,))
    m87 = text_mask("87", round(n * 0.70))
    if m87.width > n * 0.86:
        m87 = m87.resize((round(n * 0.86), round(m87.height * n * 0.86 / m87.width)), Image.LANCZOS)
    x = (n - m87.width) // 2
    y = (n - m87.height) // 2
    img.paste(Image.new("RGBA", m87.size, DANGER + (255,)), (x, y), m87)
    return img.resize((px, px), Image.LANCZOS)


def icon_image(px: int) -> Image.Image:
    return icon_small(px) if px <= 48 else icon_large(px)


def write_ico(path: Path, sizes: list[int]) -> None:
    """ICO z osobno narysowanym obrazem PNG na każdy rozmiar (Windows Vista+ czyta PNG w ICO)."""
    blobs = []
    for s in sizes:
        b = io.BytesIO()
        icon_image(s).save(b, "PNG", optimize=True)
        blobs.append(b.getvalue())
    head = struct.pack("<HHH", 0, 1, len(sizes))
    off = 6 + 16 * len(sizes)
    entries = b""
    for s, blob in zip(sizes, blobs):
        dim = 0 if s >= 256 else s
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), off)
        off += len(blob)
    path.write_bytes(head + entries + b"".join(blobs))


# ---------------------------------------------------------------- ekran uruchamiania


def flatline(width: int, height: int, S: int) -> Image.Image:
    """Martwa linia sygnału z jednym drgnięciem (RGBA): kość przygaszona, drgnięcie krwią."""
    w, h = width * S, height * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    mid = h // 2
    lw = max(1, round(1.6 * S))
    bx = round(w * 0.62)  # drgnięcie po prawej, pod „'87”
    pts = [(bx - 7 * S, mid), (bx - 3 * S, mid - 5 * S), (bx + 1 * S, mid + 13 * S),
           (bx + 5 * S, mid - 22 * S), (bx + 9 * S, mid + 6 * S), (bx + 13 * S, mid)]
    # Linia wygasa ku brzegom — gradient alfy.
    line = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    ld.line([(0, mid), pts[0]], fill=MUTED + (255,), width=lw)
    ld.line([pts[-1], (w, mid)], fill=MUTED + (255,), width=lw)
    fade = Image.new("L", (w, 1))
    for x in range(w):
        t = x / (w - 1)
        fade.putpixel((x, 0), int(255 * min(1.0, t / 0.35, (1 - t) / 0.35) ** 1.5 * 0.55))
    line.putalpha(ImageChops.multiply(line.getchannel("A"), fade.resize((w, h))))
    img.alpha_composite(line)
    d.line(pts, fill=DANGER + (255,), width=lw, joint="curve")
    return img.resize((width, height), Image.LANCZOS)


def boot_splash(w: int = 1920, h: int = 1080) -> Image.Image:
    img = Image.new("RGBA", (w, h), GROUND + (255,))
    # Lampa nisko pod znakiem; poświata kończy się daleko przed brzegiem obrazu,
    # więc brzegi mają dokładnie kolor tła i obraz nie odcina się przy innych proporcjach ekranu.
    img.alpha_composite(glow((w, h), (w * 0.5, h * 0.60), (w * 0.42, h * 0.40), ACCENT, 0.16))
    img.alpha_composite(glow((w, h), (w * 0.5, h * 0.56), (w * 0.20, h * 0.16), (255, 196, 110), 0.07))

    wm = wordmark(round(h * 0.135))
    target_w = round(w * 0.44)
    wm = wm.resize((target_w, round(wm.height * target_w / wm.width)), Image.LANCZOS)
    x = (w - wm.width) // 2
    y = round(h * 0.5 - wm.height * 0.62)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", wm.size, (0, 0, 0, 170)), (x, y + 6), wm.getchannel("A"))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    img.alpha_composite(wm, (x, y))

    fl = flatline(target_w, 60, 4)
    img.alpha_composite(fl, (x, y + wm.height + round(h * 0.035)))

    # Ziarno tylko w środku kadru (maska poświaty), żeby brzegi zostały równym kolorem tła.
    g = grain((w // 2, h // 2), 10, 87).resize((w, h), Image.NEAREST)
    gm = glow((w, h), (w * 0.5, h * 0.5), (w * 0.48, h * 0.48), (255, 255, 255), 1.0).getchannel("A")
    base = img.convert("RGB")
    noisy = ImageChops.add(base, Image.merge("RGB", (g, g, g)), 1.0, -128)
    base = Image.composite(noisy, base, gm.point(lambda v: v * 0.35))
    return base


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon_large(512).save(OUT / "icon.png", "PNG", optimize=True)
    write_ico(OUT / "icon.ico", [16, 24, 32, 48, 64, 128, 256])
    boot_splash().save(OUT / "boot_splash.png", "PNG", optimize=True)
    # Podgląd małych rozmiarów do akceptacji (nie trafia do gry).
    args = sys.argv[1:]
    if "--preview" in args:
        sizes = [16, 24, 32, 48, 64, 128, 256]
        sheet = Image.new("RGBA", (sum(sizes) + 20 * (len(sizes) + 1), 256 + 40), (40, 40, 40, 255))
        xx = 20
        for s in sizes:
            sheet.alpha_composite(icon_image(s), (xx, 20 + 256 - s))
            xx += s + 20
        sheet.save(args[args.index("--preview") + 1])
    print("brand art:", ", ".join(p.name for p in sorted(OUT.glob("*.*")) if p.suffix != ".import"))


if __name__ == "__main__":
    main()
