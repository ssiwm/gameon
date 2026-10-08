"""Składa arkusz koncepcyjny postaci (poza, płeć × strój, obrót, podgląd „w grze”) z renderów char3d_concept.py.

Uruchomienie (Pillow, np. z venv): python prototype/tools/concept/char3d_sheet.py RENDER_DIR OUT.png
Podgląd „w grze” pokazuje docelowy tor: render 3D → zrzut do klatki 32×48 z ograniczoną paletą i obrysem → powiększenie ×6,
obok obecnego sprite'a (art/sprites/player_1.png, klatka idle 0) dla porównania skali i czytelności.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/char3d"
OUT = sys.argv[2] if len(sys.argv) > 2 else "concepts/characters_3d_v0.png"
ART = os.path.join(os.path.dirname(__file__), "..", "..", "art", "sprites")
FONT_B = "/usr/share/fonts/noto/NotoSans-Bold.ttf"
FONT_R = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
PIX = os.path.join(os.path.dirname(__file__), "..", "..", "art", "fonts", "Silkscreen-Regular.ttf")

BG_TOP, BG_BOT = (34, 38, 50), (14, 15, 22)
ACCENT = (240, 170, 60)
MUTED = (150, 158, 176)


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        px.line([(0, y), (w, y)], fill=tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3)))
    return img.convert("RGBA")


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def trim(im, pad=0):
    box = im.getbbox()
    return im.crop(box) if box else im


def card(im, w, h, label, sub=""):
    """Karta z postacią na gradiencie i podpisem."""
    c = gradient(w, h)
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, w - 1, h - 1], outline=(60, 66, 84))
    fig = im.resize((int(im.width * (h - 110) / im.height), h - 110), Image.LANCZOS)
    # cień pod stopami
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([w // 2 - 120, h - 118, w // 2 + 120, h - 98], fill=(0, 0, 0, 90))
    c.alpha_composite(sh)
    c.alpha_composite(fig, ((w - fig.width) // 2, 14))
    d.text((18, h - 78), label, font=font(FONT_B, 24), fill=ACCENT)
    if sub:
        d.text((18, h - 44), sub, font=font(FONT_R, 17), fill=MUTED)
    return c


def to_pixel(im, w=32, h=48, colors=22):
    """Render 3D → klatka gry: przycięcie, skalowanie do wysokości h-2, paleta, 1 px obrys."""
    im = trim(im)
    th = h - 4
    tw = max(1, round(im.width * th / im.height))
    # pracujemy w 4× i dopiero potem redukujemy, żeby krawędzie były czyste
    big = im.resize((tw * 4, th * 4), Image.LANCZOS).resize((tw, th), Image.BOX)
    a = big.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = big.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    sp = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sp.paste(rgb, (0, 0), a)
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ox = max(0, (w - tw) // 2 - 1)
    frame.alpha_composite(sp, (ox, h - th - 1))
    # obrys 1 px
    px = frame.load()
    src = frame.copy().load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        px[x, y] = (18, 14, 22, 255)
                        break
    return frame


def main():
    W, H = 2400, 1540
    sheet = gradient(W, H)
    d = ImageDraw.Draw(sheet)
    d.text((60, 36), "DEAD AIR '87", font=font(PIX, 44), fill=ACCENT)
    d.text((60, 96), "Character redesign — 2.5D concept v0 (pre-rendered 3D, toon + outline)", font=font(FONT_B, 28), fill=(225, 228, 236))
    d.text((60, 140), "Procedural placeholder model (primitives) — proportions, silhouettes, outfits and render style only. Not final art.", font=font(FONT_R, 20), fill=MUTED)

    cw, ch = 372, 640
    names = [("male", "scavenger", "SCAVENGER"), ("male", "hazmat", "HAZMAT TECH"), ("male", "medic", "FIELD MEDIC"),
             ("female", "scavenger", "SCAVENGER"), ("female", "hazmat", "HAZMAT TECH"), ("female", "medic", "FIELD MEDIC")]
    x0, y0 = 60, 200
    d.text((x0, y0 - 4), "MALE", font=font(PIX, 22), fill=ACCENT)
    d.text((x0 + 3 * (cw + 12) + 20, y0 - 4), "FEMALE", font=font(PIX, 22), fill=ACCENT)
    for i, (g, o, lab) in enumerate(names):
        col = i + (0 if i < 3 else 0)
        x = x0 + col * (cw + 12) + (20 if i >= 3 else 0)
        sheet.alpha_composite(card(trim(load(f"{g}_{o}")), cw, ch, lab, "gender: " + g + "  ·  skin tone: " + ("light" if g == "male" else "tan")), (x, y0 + 30))

    # obrót
    y1 = y0 + 30 + ch + 40
    d.text((x0, y1 - 4), "TURNAROUND  (female · medic)", font=font(PIX, 22), fill=ACCENT)
    tw_, th_ = 270, 470
    for i, n in enumerate(("front", "three", "side", "back")):
        sheet.alpha_composite(card(trim(load("turn_" + n)), tw_, th_, n.upper().replace("THREE", "3/4"), ""), (x0 + i * (tw_ + 10), y1 + 30))

    # podgląd w grze
    px0 = x0 + 4 * (tw_ + 10) + 40
    d.text((px0, y1 - 4), "IN-GAME PREVIEW  (frame 32×48, ×6)", font=font(PIX, 22), fill=ACCENT)
    cur = Image.open(os.path.join(ART, "player_1.png")).convert("RGBA").crop((0, 0, 32, 48))
    previews = [("CURRENT\n2D pixel rig", cur), ("3D to pixel\nmale scavenger", to_pixel(load("male_scavenger"))),
                ("3D to pixel\nfemale hazmat", to_pixel(load("female_hazmat"))), ("3D to pixel\nfemale medic", to_pixel(load("female_medic")))]
    bw, bh = 196, 470
    for i, (lab, fr) in enumerate(previews):
        c = gradient(bw, bh)
        big = fr.resize((32 * 6, 48 * 6), Image.NEAREST)
        c.alpha_composite(big, (2, 30))
        cd = ImageDraw.Draw(c)
        cd.rectangle([0, 0, bw - 1, bh - 1], outline=(60, 66, 84))
        cd.text((12, bh - 62), lab, font=font(FONT_B, 17), fill=ACCENT if i else (225, 228, 236), spacing=4)
        sheet.alpha_composite(c, (px0 + i * (bw + 8), y1 + 30))
    d.text((px0, y1 + 30 + bh + 14), "Same 32x48 frame as today. Rifle is baked in here for the preview only -\nin the game the weapon stays a separate, aimed layer (pivot 9,12).\nMore readable gear, hair and outfit silhouettes at the same pixel size.",
           font=font(FONT_R, 17), fill=MUTED, spacing=4)

    os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
    sheet.convert("RGB").save(OUT)
    print("OK", OUT, sheet.size)


main()
