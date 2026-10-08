"""Arkusz prezentacyjny stylizowanych postaci MakeHuman („Scavenger '87”, M/F) z renderów char_mpfb_outfit.py.

Uruchomienie (Pillow): python prototype/tools/concept/char_mpfb_sheet.py RENDER_DIR OUT.png
Zawiera: przód (poza A), 3/4 i bok w swobodnej pozie dla obu płci, oraz podgląd „w grze” — zrzut do klatki 64×96 (gęstość 4×)
obok obecnego gracza i Wołka w tej samej skali świata.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mpfb_outfit"
OUT = sys.argv[2] if len(sys.argv) > 2 else "concepts/makehuman_scavenger_v1.png"
ART = os.path.join(os.path.dirname(__file__), "..", "..", "art", "sprites")
FB, FR = "/usr/share/fonts/noto/NotoSans-Bold.ttf", "/usr/share/fonts/noto/NotoSans-Regular.ttf"
PIX = os.path.join(os.path.dirname(__file__), "..", "..", "art", "fonts", "Silkscreen-Regular.ttf")
TOP, BOT = (36, 40, 52), (14, 15, 22)
ACCENT, MUTED = (240, 170, 60), (150, 158, 176)


def font(p, s):
    try:
        return ImageFont.truetype(p, s)
    except OSError:
        return ImageFont.load_default()


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)))
    return img.convert("RGBA")


def load(n):
    return Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")


def trim(im):
    b = im.getbbox()
    return im.crop(b) if b else im


def card(im, w, h, label, sub=""):
    c = gradient(w, h)
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, w - 1, h - 1], outline=(60, 66, 84))
    fig = trim(im)
    sc = min((w - 40) / fig.width, (h - 110) / fig.height)
    fig = fig.resize((int(fig.width * sc), int(fig.height * sc)), Image.LANCZOS)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([w // 2 - fig.width // 2, h - 108, w // 2 + fig.width // 2, h - 88], fill=(0, 0, 0, 110))
    c.alpha_composite(sh)
    c.alpha_composite(fig, ((w - fig.width) // 2, h - 98 - fig.height))
    d.text((16, h - 70), label, font=font(FB, 22), fill=ACCENT)
    if sub:
        d.text((16, h - 38), sub, font=font(FR, 16), fill=MUTED)
    return c


def to_pixel(im, w=64, h=96, colors=32):
    im = trim(im)
    th = h - 6
    tw = max(1, round(im.width * th / im.height))
    big = im.resize((tw * 4, th * 4), Image.LANCZOS).resize((tw, th), Image.BOX)
    a = big.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = big.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    sp = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sp.paste(rgb, (0, 0), a)
    fr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fr.alpha_composite(sp, ((w - tw) // 2, h - th - 2))
    px, src = fr.load(), fr.copy().load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        px[x, y] = (18, 14, 22, 255)
                        break
    return fr


def main():
    W, H = 2400, 1380
    sheet = gradient(W, H)
    d = ImageDraw.Draw(sheet)
    d.text((60, 34), "DEAD AIR '87", font=font(PIX, 44), fill=ACCENT)
    d.text((60, 94), "Character v1 — stylized MakeHuman base + custom outfit “Scavenger '87”", font=font(FB, 28), fill=(225, 228, 236))
    d.text((60, 138), "Proportions stylized by one position-warp applied to every part (shorter legs, bigger head, chunkier body). "
           "Outfit built from the body mesh (inherits the rig weights) + rigid gear. Same script builds male and female.", font=font(FR, 19), fill=MUTED)
    cw, ch = 360, 700
    x0, y0 = 60, 190
    cols = [("A_front", "A-pose · front"), ("relaxed_three", "ready · 3/4"), ("relaxed_side", "ready · side")]
    for gi, (g, lab) in enumerate((("male", "MALE"), ("female", "FEMALE"))):
        gx = x0 + gi * (3 * (cw + 10) + 50)
        d.text((gx, y0 - 8), lab, font=font(PIX, 22), fill=ACCENT)
        for ci, (v, vl) in enumerate(cols):
            sheet.alpha_composite(card(load(f"{g}_{v}"), cw, ch, "SCAVENGER '87", f"{g} · {vl}"), (gx + ci * (cw + 10), y0 + 26))
    # podgląd w grze
    y1 = y0 + 26 + ch + 40
    d.text((x0, y1 - 8), "IN-GAME PREVIEW — same world scale (frame 64x96 @ 0.25 vs current 32x48 @ 0.5), shown x8", font=font(PIX, 20), fill=ACCENT)
    cur = Image.open(os.path.join(ART, "player_1.png")).convert("RGBA").crop((0, 0, 32, 48)).resize((128, 192), Image.NEAREST)
    wol = Image.open(os.path.join(ART, "wolek.png")).convert("RGBA").crop((0, 0, 88, 88)).resize((176, 176), Image.NEAREST)
    cards = [("CURRENT player", cur), ("WOLEK (existing)", wol)]
    for g in ("male", "female"):
        cards.append((f"NEW {g} -> 64x96", to_pixel(load(f"{g}_relaxed_side")).resize((128 * 1, 192), Image.NEAREST)))
    x = x0
    for lab, im in cards:
        bw = max(im.width, 150) + 40
        c = gradient(bw, 290)
        c.alpha_composite(im, ((bw - im.width) // 2, 290 - im.height - 52))
        cd = ImageDraw.Draw(c)
        cd.rectangle([0, 0, bw - 1, 289], outline=(60, 66, 84))
        cd.text((12, 252), lab, font=font(FB, 16), fill=(225, 228, 236) if "NEW" not in lab else ACCENT)
        sheet.alpha_composite(c, (x, y1 + 26))
        x += bw + 12
    d.text((x + 20, y1 + 40), "Known gaps in v1 (see CHARACTERS_PLAN.md):", font=font(FB, 18), fill=(225, 228, 236))
    notes = ["• clothing is plain procedural cloth (no sculpted folds / hand-painted wear)",
             "• boots, backpack and gear are simple primitives; face and hands are MakeHuman defaults",
             "• ready pose is a static aim; weapon arm layers and animations come in the pipeline phase",
             "• hair and cap clip slightly; per-region shells have visible seams at the belt line"]
    for i, t in enumerate(notes):
        d.text((x + 20, y1 + 74 + i * 28), t, font=font(FR, 17), fill=MUTED)
    os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
    sheet.convert("RGB").save(OUT)
    print("OK", OUT, sheet.size)


main()
