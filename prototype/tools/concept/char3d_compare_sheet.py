"""Arkusz porównawczy postaci 3D: model Tripo (podgląd), wszystkie animacje arkusza playerhd3_male, porównanie skali z MakeHuman v1, obecnym graczem i potworami.
Uruchomienie (Pillow): python prototype/tools/concept/char3d_compare_sheet.py PREVIEW.png OUT.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ART = os.path.join(os.path.dirname(__file__), "..", "..", "art", "sprites")
FB = "/usr/share/fonts/noto/NotoSans-Bold.ttf"
FR = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
PIX = os.path.join(os.path.dirname(__file__), "..", "..", "art", "fonts", "Silkscreen-Regular.ttf")
ACCENT, MUTED, BG = (240, 170, 60), (150, 158, 176), (22, 24, 32)


def font(p, s):
    try:
        return ImageFont.truetype(p, s)
    except OSError:
        return ImageFont.load_default()


def sheet(n):
    return Image.open(os.path.join(ART, n + ".png")).convert("RGBA")


def strip(name, row, n, up=2.5):
    s = sheet(name)
    fw, fh = 64, 96
    out = Image.new("RGBA", (int(n * fw * up), int(fh * up)), (0, 0, 0, 0))
    for i in range(n):
        f = s.crop((i * fw, row * fh, (i + 1) * fw, (row + 1) * fh)).resize((int(fw * up), int(fh * up)), Image.LANCZOS)
        out.alpha_composite(f, (int(i * fw * up), 0))
    return out


def main():
    prev, outp = sys.argv[1:3]
    W, H = 2400, 1500
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((50, 30), "DEAD AIR '87", font=font(PIX, 40), fill=ACCENT)
    d.text((50, 84), "Tripo (text-to-3D + auto-rig) rendered into the game's sprite pipeline — 64x96 @ 0.25", font=font(FB, 26), fill=(225, 228, 236))
    p = Image.open(prev).convert("RGBA")
    p = p.resize((380, 380), Image.LANCZOS)
    bg = Image.new("RGBA", (380, 380), (36, 40, 52, 255))
    bg.alpha_composite(p)
    img.paste(bg.convert("RGB"), (50, 150))
    d.text((50, 540), "Tripo preview (50 credits = $0.50)", font=font(FB, 18), fill=ACCENT)
    x = 470
    d.text((x, 150), "IDLE 6f · RUN 8f", font=font(PIX, 20), fill=ACCENT)
    idle, run = strip("playerhd3_male", 0, 6), strip("playerhd3_male", 1, 8)
    img.paste(idle, (x, 184), idle)
    img.paste(run, (x + idle.width + 30, 184), run)
    y2 = 184 + 240 + 40
    d.text((x, y2), "JUMP · FALL · CROUCH · CROUCH-WALK 6f · DOWN", font=font(PIX, 20), fill=ACCENT)
    xs = x
    for row, n in ((2, 1), (3, 1), (4, 1), (5, 6), (6, 1)):
        st = strip("playerhd3_male", row, n)
        img.paste(st, (xs, y2 + 34), st)
        xs += st.width + 14
    # skala
    y3 = 760
    d.text((50, y3), "SCALE vs WORLD — same world scale (x8)", font=font(PIX, 20), fill=ACCENT)
    items = []
    cur = sheet("player_1").crop((0, 0, 32, 48)).resize((128, 192), Image.NEAREST)               # 32x48 @0.5
    mh = sheet("playerhd_male").crop((0, 0, 64, 96)).resize((128, 192), Image.LANCZOS)            # 64x96 @0.25
    tr = sheet("playerhd3_male").crop((0, 0, 64, 96)).resize((128, 192), Image.LANCZOS)
    trz = sheet("trzosek").crop((0, 0, 48, 44)).resize((48 * 4, 44 * 4), Image.NEAREST)
    wol = sheet("wolek").crop((0, 0, 88, 88)).resize((88 * 4, 88 * 4), Image.NEAREST)
    x = 50
    for lab, im in (("CURRENT", cur), ("MakeHuman v1", mh), ("TRIPO", tr), ("TRZOSEK", trz), ("WOLEK", wol)):
        img.paste(im, (x, y3 + 40 + (352 - im.height)), im)
        d.text((x, y3 + 400), lab, font=font(FB, 18), fill=ACCENT if lab == "TRIPO" else (225, 228, 236))
        x += max(im.width, 140) + 50
    d.text((50, H - 70), "Rifle stays a separate layer (pivot 1,-12 px above feet); hand posed there in each frame. Frames are rendered at 4x and reduced; 2 px outline added.",
           font=font(FR, 17), fill=MUTED)
    img.save(outp)
    print("OK", outp, img.size)


main()
