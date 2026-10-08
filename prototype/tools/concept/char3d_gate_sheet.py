"""Arkusz bramki P0: postacie 3D w grze (zrzuty), wszystkie animacje z arkuszy playerhd_* oraz porównanie z obecnym graczem i potworami.

Uruchomienie (Pillow): python prototype/tools/concept/char3d_gate_sheet.py SHOT_NEW1.png SHOT_NEW2.png SHOT_CLASSIC.png OUT.png
Zrzuty z gry: godot --path prototype -- --host --newchar=mix|female --shot=PLIK --shotdelay=2.0
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ART = os.path.join(os.path.dirname(__file__), "..", "..", "art", "sprites")
FB, FR = "/usr/share/fonts/noto/NotoSans-Bold.ttf", "/usr/share/fonts/noto/NotoSans-Regular.ttf"
PIX = os.path.join(os.path.dirname(__file__), "..", "..", "art", "fonts", "Silkscreen-Regular.ttf")
ACCENT, MUTED = (240, 170, 60), (150, 158, 176)
BG = (22, 24, 32)


def font(p, s):
    try:
        return ImageFont.truetype(p, s)
    except OSError:
        return ImageFont.load_default()


def sheet(name):
    return Image.open(os.path.join(ART, name + ".png")).convert("RGBA")


def strip(name, row, n, fw, fh, scale, up):
    s = sheet(name)
    out = Image.new("RGBA", (n * fw * up, fh * up), (0, 0, 0, 0))
    for i in range(n):
        out.alpha_composite(s.crop((i * fw, row * fh, (i + 1) * fw, (row + 1) * fh)).resize((fw * up, fh * up), Image.NEAREST), (i * fw * up, 0))
    return out


def main():
    s1, s2, sc, out_path = sys.argv[1:5]
    W, H = 2400, 1940
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((50, 30), "DEAD AIR '87", font=font(PIX, 40), fill=ACCENT)
    d.text((50, 84), "Gate P0 — 3D character rendered to the game's sprite pipeline (64x96 @ 0.25)", font=font(FB, 26), fill=(225, 228, 236))
    # zrzuty z gry (powiększone 4×)
    crops = [("NEW male (left) + old bot", s1, (340, 540, 740, 700)), ("NEW female + old bot", s2, (340, 540, 740, 700)), ("CURRENT player + old bot", sc, (340, 540, 740, 700))]
    x = 50
    for lab, p, box in crops:
        c = Image.open(p).convert("RGB").crop(box).resize((760, 304), Image.LANCZOS)
        img.paste(c, (x, 150))
        d.text((x, 462), lab, font=font(FB, 20), fill=ACCENT if "NEW" in lab else (225, 228, 236))
        x += 780
    # animacje
    up = 4 * 1
    y = 520
    for g in ("male", "female"):
        d.text((50, y), f"{g.upper()} — idle 6f · run 8f", font=font(PIX, 20), fill=ACCENT)
        idle = strip(f"playerhd_{g}", 0, 6, 64, 96, 0.25, 3)
        run = strip(f"playerhd_{g}", 1, 8, 64, 96, 0.25, 3)
        img.paste(idle, (50, y + 34), idle)
        img.paste(run, (50 + idle.width + 40, y + 34), run)
        y += 330
    # pozostałe stany
    d.text((50, y), "MALE — jump · fall · crouch · crouch-walk · down", font=font(PIX, 20), fill=ACCENT)
    x = 50
    for row, n in ((2, 1), (3, 1), (4, 1), (5, 3), (6, 1)):
        st = strip("playerhd_male", row, n, 64, 96, 0.25, 3)
        img.paste(st, (x, y + 34), st)
        x += st.width + 24
    # porównanie skali ze światem (ta sama skala świata: 16×24 px świata ×6)
    y += 330
    d.text((50, y), "SCALE vs WORLD — same world scale (x6)", font=font(PIX, 20), fill=ACCENT)
    cur = sheet("player_1").crop((0, 0, 32, 48)).resize((96, 144), Image.NEAREST)           # 32x48 @0.5
    new_m = sheet("playerhd_male").crop((0, 0, 64, 96)).resize((96, 144), Image.LANCZOS)    # 64x96 @0.25
    new_f = sheet("playerhd_female").crop((0, 0, 64, 96)).resize((96, 144), Image.LANCZOS)
    trz = sheet("trzosek").crop((0, 0, 48, 44)).resize((48 * 3, 44 * 3), Image.NEAREST)     # 48x44 @0.5
    wol = sheet("wolek").crop((0, 0, 88, 88)).resize((88 * 3, 88 * 3), Image.NEAREST)       # 88x88 @0.5
    x = 50
    for lab, im in (("CURRENT", cur), ("NEW male", new_m), ("NEW female", new_f), ("TRZOSEK", trz), ("WOLEK", wol)):
        img.paste(im, (x, y + 44 + (264 - im.height)), im)
        d.text((x, y + 316), lab, font=font(FB, 16), fill=ACCENT if "NEW" in lab else (225, 228, 236))
        x += max(im.width, 110) + 36
    d.text((50, H - 90), "Rifle is a separate layer in game (pivot 1,-12 px above feet) — the hand in every frame is posed to that point. Known issues: legs/boots are chunky "
           "primitives, outfit is plain cloth, hair stays rigid to the head bone, 'down' is a seated pose (the 24 px tall body does not fit lying in a 16 px frame).",
           font=font(FR, 17), fill=MUTED)
    img.save(out_path)
    print("OK", out_path, img.size)


main()
