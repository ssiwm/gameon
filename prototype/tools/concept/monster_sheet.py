"""Arkusz podglądowy wrogów HD (idle, bieg/chód, zamach, sen) z art/sprites/<rodzaj>_hd.png. Uruchomienie (Pillow): python prototype/tools/concept/monster_sheet.py OUT.png"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "art")
FB = "/usr/share/fonts/noto/NotoSans-Bold.ttf"
man = json.load(open(os.path.join(ART, "sprites.json")))["sheets"]
kinds = [k for k in ("wolek", "trzosek", "slepiec", "skoczek", "podsluchacz", "stalker", "mimik", "cma", "nest", "vein", "leech") if k + "_hd" in man]
img = Image.new("RGB", (2300, 4200), (22, 24, 32))
d = ImageDraw.Draw(img)
d.text((40, 20), "Enemies HD (Tripo -> sprite pipeline, 8 px per world px, albedo + normal map + glow)", font=ImageFont.truetype(FB, 26), fill=(240, 170, 60))
y = 80
for k in kinds:
    info = man[k + "_hd"]
    fw, fh = info["frame"]
    sheet = Image.open(os.path.join(ART, "sprites", k + "_hd.png")).convert("RGBA")
    s = 0.8 if fw > 300 else 1.1
    d.text((40, y), k.upper(), font=ImageFont.truetype(FB, 20), fill=(225, 228, 236))
    x = 40
    for an, a in info["anims"].items():
        for i in range(a["frames"]):
            fr = sheet.crop((i * fw, a["row"] * fh, (i + 1) * fw, (a["row"] + 1) * fh)).resize((int(fw * s), int(fh * s)), Image.LANCZOS)
            bg = Image.new("RGBA", fr.size, (40, 44, 58, 255))
            bg.alpha_composite(fr)
            if x + fr.width > 2260:
                break
            img.paste(bg.convert("RGB"), (x, y + 30))
            x += fr.width + 6
        d.text((x - 60, y + 6), an, font=ImageFont.truetype(FB, 14), fill=(150, 158, 176))
        x += 14
    y += int(fh * s) + 80
img.crop((0, 0, 2300, y)).save(sys.argv[1])
print("OK", sys.argv[1])
