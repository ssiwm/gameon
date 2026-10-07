#!/usr/bin/env python3
"""Generator pixel-artu Dead Air '87 (wariant A, 1.5).

    python3 tools/bake_sprites.py          # wszystko → prototype/art/

Rysuje sprite'y w kodzie (prostokąty, linie, elipsy z paletą) i zapisuje:
    art/sprites/<nazwa>.png        arkusz: wiersz = animacja, kolumny = klatki
    art/sprites/<nazwa>_glow.png   warstwa świecąca (oczy, żyłki) — te same klatki
    art/tiles.png                  atlas kafli 8×4 (rząd 0/2 wierzch, 1/3 wypełnienie)
    art/props.png                  dekoracje 16×16 w jednym rzędzie
    art/sprites.json               manifest: rozmiar klatki, animacje, fps, pętla

Pod artystę (wariant C): podmień PNG zachowując układ z manifestu — gra
nie wymaga zmian w kodzie. Bez zależności (PNG pisany przez zlib).
"""
import json
import math
import os
import random
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gun_art  # noqa: E402  (siatki pixel-artu 12 broni)
try:  # postacie 1.7: rigi + render 4× (numpy + Pillow); bez nich zostaje stary rysunek z prostokątów
    import char_art  # noqa: E402
    import char_boss  # noqa: E402
    import char_leech  # noqa: E402
    import gun_icons_hd  # noqa: E402
    import char_monsters_hd as hd  # noqa: E402
    import char_monsters  # noqa: E402
    import char_player  # noqa: E402
    HAVE_CHARS = True
except ImportError:
    HAVE_CHARS = False

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
SPR = os.path.join(ART, "sprites")

# ---------------------------------------------------------------- PNG / płótno

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[(0, 0, 0, 0)] * w for _ in range(h)]

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            if len(c) == 3:
                c = (*c, 255)
            self.px[y][x] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return (0, 0, 0, 0)

    def rect(self, x, y, w, h, c):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.put(xx, yy, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.put(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, c):
        for yy in range(int(cy - ry - 1), int(cy + ry + 2)):
            for xx in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((xx + 0.5 - cx) / max(rx, 0.1)) ** 2 + ((yy + 0.5 - cy) / max(ry, 0.1)) ** 2 <= 1.0:
                    self.put(xx, yy, c)

    def outline(self, c, src=None):
        """Obrys 1 px wokół nieprzezroczystych pikseli (czytelność sylwetki)."""
        src = src or self
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if src.get(x, y)[3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        if src.get(x + dx, y + dy)[3] > 0:
                            add.append((x, y))
                            break
        for x, y in add:
            self.put(x, y, c)

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c[3] > 0:
                    self.put(ox + x, oy + y, c)

    def save(self, path):
        raw = b"".join(b"\x00" + bytes([v for p in row for v in p]) for row in self.px)
        def chunk(t, d):
            return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(png)


def rgb(r, g, b, a=1.0):
    return (int(r * 255), int(g * 255), int(b * 255), int(a * 255))


def shade(c, k):
    return (max(0, min(255, int(c[0] * k))), max(0, min(255, int(c[1] * k))), max(0, min(255, int(c[2] * k))), c[3])


OUTLINE = rgb(0.05, 0.045, 0.06)

# ---------------------------------------------------------------- arkusze

MANIFEST = {"sheets": {}}


def sheet(name, fw, fh, anims, draw, glow=None):
    """anims: [(nazwa, klatek, fps, pętla)], draw(c, anim, i) rysuje klatkę."""
    cols = max(a[1] for a in anims)
    body = Canvas(fw * cols, fh * len(anims))
    light = Canvas(fw * cols, fh * len(anims))
    for row, (an, n, fps, loop) in enumerate(anims):
        for i in range(n):
            f = Canvas(fw, fh)
            g = Canvas(fw, fh)
            draw(f, g, an, i)
            o = Canvas(fw, fh)
            o.blit(f, 0, 0)
            o.outline(OUTLINE, f)
            body.blit(o, i * fw, row * fh)
            light.blit(g, i * fw, row * fh)
    body.save(os.path.join(SPR, name + ".png"))
    has_glow = any(p[3] for r in light.px for p in r)
    if has_glow:
        light.save(os.path.join(SPR, name + "_glow.png"))
    MANIFEST["sheets"][name] = {
        "frame": [fw, fh],
        "glow": has_glow,
        "anims": {a[0]: {"row": r, "frames": a[1], "fps": a[2], "loop": a[3]} for r, a in enumerate(anims)},
    }

def char_sheet(name, fw, fh, anims, body, glow):
    """Arkusz z gotowych klatek (char_art.Frame): ciało + opcjonalny glow, wpis do manifestu."""
    cols = max(a[1] for a in anims)
    char_art.write_png(char_art.sheet_rows(body, fw, fh, cols), os.path.join(SPR, name + ".png"))
    has_glow = any(p is not None for row in glow for fr in row for r in fr.px for p in r)
    if has_glow:
        char_art.write_png(char_art.sheet_rows(glow, fw, fh, cols), os.path.join(SPR, name + "_glow.png"))
    MANIFEST["sheets"][name] = {
        "frame": [fw, fh],
        "glow": has_glow,
        "anims": {a[0]: {"row": r, "frames": a[1], "fps": a[2], "loop": a[3]} for r, a in enumerate(anims)},
    }


def bake_chars_hd(only=None):
    """only: zbiór nazw arkuszy do przepieczenia (reszta zostaje nietknięta); None = wszystkie."""
    for name, col in PLAYER_VARIANTS.items():
        if only:
            break
        body, glow = char_player.frames_for(tuple(int(v * 255) for v in col), bot=(name == "bot"))
        char_sheet(name, char_player.FWD, char_player.FHD, char_player.PLAYER_ANIMS, body, glow)
        MANIFEST["sheets"][name]["scale"] = 1.0 / char_player.DENSITY      # 2× gęstość pikseli: gra rysuje arkusz w skali 0,5
    for name, fn, anims, fw, fh in (
        # potwory w wyższej jakości (1.7.16) i 2× gęstości pikseli (1.7.20), tools/char_monsters_hd.py; arkusz ma 2× więcej
        # pikseli, gra rysuje go w skali 0,5 (manifest „scale"). Mimik ma gęstość i sylwetkę gracza (musi go udawać).
        ("trzosek", hd.trzosek, hd.TRZOSEK_ANIMS) + tuple(v * hd.DENSITY for v in hd.TRZOSEK_HD),
        ("wolek", hd.wolek, hd.WOLEK_ANIMS) + tuple(v * hd.DENSITY for v in hd.WOLEK_HD),
        ("stalker", hd.stalker, hd.STALKER_ANIMS) + tuple(v * hd.DENSITY for v in hd.STALKER_HD),
        ("slepiec", hd.slepiec, hd.SLEPIEC_ANIMS) + tuple(v * hd.DENSITY for v in hd.SLEPIEC_HD),
        ("podsluchacz", hd.podsluchacz, hd.PODSLUCHACZ_ANIMS) + tuple(v * hd.DENSITY for v in hd.PODSLUCHACZ_HD),
        ("mimik", char_monsters.mimik, char_monsters.MIMIK_ANIMS, char_player.FWD, char_player.FHD),
        ("cma", hd.cma, hd.CMA_ANIMS) + tuple(v * hd.DENSITY for v in hd.CMA_HD),
        ("skoczek", hd.skoczek, hd.SKOCZEK_ANIMS) + tuple(v * hd.DENSITY for v in hd.SKOCZEK_HD),
        ("nest", hd.nest, hd.NEST_ANIMS) + tuple(v * hd.DENSITY for v in hd.NEST_HD),
        ("vein", char_boss.vein, char_boss.BOSS_ANIMS, char_boss.FWD, char_boss.FHD),
        ("leech", char_leech.leech, char_leech.LEECH_ANIMS, char_leech.FWD, char_leech.FHD),
    ):
        if only and name not in only:
            continue
        body, glow = char_monsters.monster_frames(fn, anims)
        char_sheet(name, fw, fh, anims, body, glow)
        if name == "vein":
            MANIFEST["sheets"][name]["scale"] = 1.0 / char_boss.DENSITY       # gra rysuje arkusz bossa w tej skali
        elif name == "leech":
            MANIFEST["sheets"][name]["scale"] = 1.0 / char_leech.DENSITY      # jw. (Pijawka)
        elif name == "mimik":
            MANIFEST["sheets"][name]["scale"] = 1.0 / char_player.DENSITY     # Mimik ma sylwetkę gracza — ta sama gęstość
        else:
            MANIFEST["sheets"][name]["scale"] = 1.0 / hd.DENSITY

# ---------------------------------------------------------------- gracz

PLAYER_VARIANTS = {
    "player_1": (0.91, 0.62, 0.22),
    "player_2": (0.25, 0.72, 0.85),
    "player_3": (0.86, 0.28, 0.36),
    "player_4": (0.45, 0.80, 0.30),
    "bot": (0.58, 0.60, 0.66),
}
PLAYER_ANIMS = [("idle", 4, 4, True), ("run", 6, 12, True), ("jump", 1, 1, False), ("fall", 1, 1, False),
                ("crouch", 1, 1, False), ("crouch_walk", 4, 8, True), ("down", 1, 1, False)]


def draw_player(col):
    jacket = rgb(*col)
    jacket_d = shade(jacket, 0.72)
    skin = rgb(0.86, 0.68, 0.54)
    skin_d = shade(skin, 0.8)
    pants = rgb(0.30, 0.32, 0.38)
    pants_d = shade(pants, 0.75)
    boots = rgb(0.10, 0.09, 0.10)
    cap = shade(jacket, 0.5)
    pack = rgb(0.30, 0.27, 0.20)
    belt = rgb(0.16, 0.13, 0.10)

    def legs(c, y_hip, front, back, crouch=False):
        # front/back: przesunięcie stopy w x; kolano zgięte w biegu. Nogi po
        # 2 px (1 px + obrys dawało „trzy paski" zamiast dwóch nóg).
        for lx, dxf, col_l in ((6, back, pants_d), (9, front, pants)):
            fx = lx + dxf
            for w in (0, 1):
                if crouch:
                    c.line(lx + w, y_hip, lx + 2 + w, y_hip + 3, col_l)
                    c.line(lx + 2 + w, y_hip + 3, fx + w, 22, col_l)
                else:
                    knee = (lx + fx) / 2 + (1 if dxf > 0 else -1 if dxf < 0 else 0)
                    c.line(lx + w, y_hip, knee + w, y_hip + 3, col_l)
                    c.line(knee + w, y_hip + 3, fx + w, 22, col_l)
            c.rect(fx - 1, 22, 4, 2, boots)

    def body(c, g, y0, lean=0):
        # plecak, tułów, pas, głowa z czapką
        c.rect(3 + lean, y0 + 6, 3, 6, pack)
        c.rect(5 + lean, y0 + 5, 7, 8, jacket)
        c.rect(5 + lean, y0 + 10, 7, 3, jacket_d)
        c.rect(5 + lean, y0 + 12, 7, 1, belt)
        c.rect(6 + lean, y0, 6, 6, skin)
        c.rect(6 + lean, y0 + 4, 6, 1, skin_d)
        c.rect(6 + lean, y0 - 1, 6, 2, cap)
        c.rect(11 + lean, y0 + 1, 2, 1, cap)          # daszek
        c.put(10 + lean, y0 + 2, OUTLINE)              # oko

    def draw(c, g, an, i):
        if an == "idle":
            bob = 1 if i in (1, 2) else 0
            legs(c, 14, 0, 0)
            body(c, g, 3 + bob)
        elif an == "run":
            ph = i / 6.0 * math.tau
            f = round(3 * math.sin(ph))
            bob = 1 if i % 3 == 1 else 0
            legs(c, 14 + bob, f, -f)
            body(c, g, 3 + bob, 1)
        elif an == "jump":
            legs(c, 14, 2, -2)
            c.rect(9, 19, 2, 2, pants)                 # podkurczona noga
            body(c, g, 2)
        elif an == "fall":
            legs(c, 14, 2, 0)
            body(c, g, 3)
        elif an == "crouch":
            legs(c, 17, 1, -1, True)
            body(c, g, 9, 1)
        elif an == "crouch_walk":
            f = [2, 0, -2, 0][i]
            legs(c, 17, f, -f, True)
            body(c, g, 9, 1)
        elif an == "down":
            # leży na boku
            c.rect(2, 19, 11, 3, jacket)
            c.rect(2, 21, 11, 1, jacket_d)
            c.rect(12, 19, 4, 3, skin)
            c.rect(12, 18, 4, 1, cap)
            c.rect(0, 20, 3, 2, pants)
            c.put(1, 22, rgb(0.45, 0.04, 0.06))
            c.rect(4, 22, 6, 1, rgb(0.38, 0.03, 0.05))
    return draw


def bake_players():
    for name, col in PLAYER_VARIANTS.items():
        sheet(name, 16, 24, PLAYER_ANIMS, draw_player(col))

# ---------------------------------------------------------------- broń

GUN_FRAME = (gun_art.W, gun_art.H)   # klatka broni; dłoń (pivot obrotu) w (4, 4), lufa w stronę +x
GUN_NAMES = ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6", "maczeta", "kilof"]


def bake_guns_hd():
    """Wysoka jakość (1.7.17): jeden projekt, dwa arkusze — `guns` 36×14 (świat; dłoń w HAND, wylot = HAND.x + gun_len)
    i `gun_icons` 64×24 (HUD, kodeks). Rysunki: tools/gun_icons_hd.py."""
    # spójność z grą: gun_len w weapons.gd musi równać się odległości dłoń → wylot z rysunku
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "weapons.gd"), encoding="utf-8").read()
    for n in gun_icons_hd.NAMES:
        m = re.search(r'"key": "%s".*?"gun_len": ([0-9.]+)' % n, src, re.S)
        assert m and abs(float(m.group(1)) - gun_icons_hd.gun_len(n)) < 0.01, \
            "%s: gun_len w weapons.gd (%s) != %s z tools/gun_icons_hd.py" % (n, m.group(1) if m else "?", gun_icons_hd.gun_len(n))
    anims = [(n, 1, 1, False) for n in gun_icons_hd.NAMES]
    for name, world, fw, fh in (("guns", True, gun_icons_hd.WFW, gun_icons_hd.WFH), ("gun_icons", False, gun_icons_hd.FW, gun_icons_hd.FH)):
        body, glow = [], []
        for n in gun_icons_hd.NAMES:
            b, g = gun_icons_hd.gun(n, world)
            body.append([b])
            glow.append([g])
        char_sheet(name, fw, fh, anims, body, glow)
        if world:
            MANIFEST["sheets"][name]["scale"] = 1.0 / gun_icons_hd.WORLD_DENSITY     # gra rysuje arkusz broni w tej skali


def bake_guns():
    """12 modeli w jednym arkuszu, wiersz = broń (kolejność = id w weapons.gd, `gun_row`).
    Rysunki to siatki znaków w tools/gun_art.py (rampy cieni, detale, warstwa świecąca).
    Wylot lufy = x dłoni (4) + gun_len z weapons.gd — gun_art.check() pilnuje zgodności."""
    gun_art.check()

    def draw(c, g, an, i):
        for y, row in enumerate(gun_art.ARTS[an]):
            for x, ch in enumerate(row):
                body, glow = gun_art.LEGEND[ch]
                if body is not None:
                    c.put(x, y, body)
                if glow is not None:
                    g.put(x, y, glow)

    sheet("guns", GUN_FRAME[0], GUN_FRAME[1], [(n, 1, 1, False) for n in GUN_NAMES], draw)

# ---------------------------------------------------------------- wrogowie

EYE = rgb(1.0, 0.62, 0.22)
EYE_HOT = rgb(1.0, 0.25, 0.15)


def bake_trzosek():
    hide = rgb(0.55, 0.18, 0.20)
    hide_d = shade(hide, 0.7)
    bone = rgb(0.78, 0.72, 0.60)
    def draw(c, g, an, i):
        crouch = 3 if an == "sleep" else 0
        ph = i / 4.0 * math.tau
        if an == "run":
            f = round(2.5 * math.sin(ph))
        elif an == "windup":
            f = 0
        else:
            f = 0
        breath = 1 if (an in ("idle", "sleep") and i == 1) else 0
        y = 5 + crouch - breath
        # garbaty tułów
        c.ellipse(8, y + 4, 6, 4, hide)
        c.ellipse(8, y + 6, 5, 2, hide_d)
        for k in range(3):                             # kolce grzbietu
            c.put(5 + k * 3, y, bone)
        # głowa wysunięta do przodu
        hx = 12 + (1 if an == "windup" else 0)
        c.ellipse(hx, y + 5, 3, 2.5, hide)
        c.put(hx + 3, y + 6, bone)                     # kieł
        # łapy
        if an != "sleep":
            c.line(5, y + 7, 4 - f, 15, hide_d)
            c.line(11, y + 7, 12 + f, 15, hide_d)
            c.line(8, y + 7, 8 + f // 2, 15, hide)
        else:
            c.rect(3, 14, 11, 1, hide_d)
        if an == "windup":
            c.line(13, y + 3, 15, y - 1, hide)         # uniesiona łapa
        eye = EYE_HOT if an == "windup" else EYE
        g.put(hx + 1, y + 4, eye if an != "sleep" else rgb(0.6, 0.35, 0.15, 0.6))
        g.put(hx - 1, y + 4, eye if an != "sleep" else rgb(0.6, 0.35, 0.15, 0.6))
    sheet("trzosek", 16, 16, [("idle", 2, 3, True), ("run", 4, 10, True), ("windup", 1, 1, False), ("sleep", 2, 1.5, True)], draw)


def bake_wolek():
    hide = rgb(0.40, 0.30, 0.36)
    hide_d = shade(hide, 0.7)
    horn = rgb(0.80, 0.74, 0.62)
    def draw(c, g, an, i):
        sleep = an == "sleep"
        ph = i / 4.0 * math.tau
        f = round(2 * math.sin(ph)) if an == "walk" else 0
        y = 6 + (4 if sleep else 0) + (1 if an == "idle" and i == 1 else 0)
        # masywne barki i tułów
        c.ellipse(14, y + 9, 10, 8, hide)
        c.ellipse(14, y + 13, 8, 4, hide_d)
        # mała głowa z rogami, nisko
        c.ellipse(21, y + 6, 4, 3.5, hide)
        c.line(19, y + 3, 17, y, horn)
        c.line(23, y + 3, 25, y, horn)
        # ręce-maczugi
        arm_up = an == "windup"
        if arm_up:
            c.line(22, y + 8, 26, y - 2, hide_d)
            c.ellipse(26, y - 3, 2.5, 2.5, hide_d)
        else:
            c.line(22, y + 9, 24, y + 17, hide_d)
            c.ellipse(24, y + 18, 2.5, 2.5, hide_d)
        # nogi
        if not sleep:
            c.rect(8 + f, y + 17, 4, 30 - (y + 17), hide_d)
            c.rect(16 - f, y + 17, 4, 30 - (y + 17), hide_d)
        eye = EYE_HOT if an == "windup" else EYE
        if sleep:
            eye = rgb(0.6, 0.35, 0.15, 0.6)
        g.put(22, y + 5, eye)
        g.put(24, y + 5, eye)
    sheet("wolek", 30, 30, [("idle", 2, 2, True), ("walk", 4, 6, True), ("windup", 1, 1, False), ("sleep", 2, 1.2, True)], draw)


def bake_stalker():
    cloth = rgb(0.25, 0.22, 0.28)
    cloth_d = shade(cloth, 0.7)
    skin = rgb(0.36, 0.33, 0.38)
    def draw(c, g, an, i):
        ph = i / max(1, (6 if an == "walk" else 4)) * math.tau
        sway = math.sin(ph) * (1.5 if an == "idle" else 1.0)
        f = round(2.5 * math.sin(ph)) if an == "walk" else 0
        # długie nogi
        c.line(9, 26, 8 - f, 39, cloth_d)
        c.line(11, 26, 12 + f, 39, cloth_d)
        # wychudzony tułów, płaszcz w strzępach
        c.rect(7, 10, 7, 17, cloth)
        for k in range(4):
            c.line(7 + k * 2, 26, 7 + k * 2 + (1 if (i + k) % 2 else -1), 30 + k % 2, cloth_d)
        # wydłużona głowa
        hx = 10 + round(sway)
        c.ellipse(hx, 6, 3, 5, skin)
        # ramiona do kolan, w zapowiedzi uniesione
        if an == "windup":
            c.line(13, 12, 18, 2, skin)
            c.line(7, 12, 2, 3, skin)
        else:
            c.line(13, 12, 15 + round(sway), 27, skin)
            c.line(7, 12, 5 - round(sway), 27, skin)
        e = rgb(1.0, 0.25, 0.18) if an == "windup" else rgb(1.0, 0.2, 0.15, 0.85)
        g.put(hx - 1, 5, e)
        g.put(hx + 1, 5, e)
    sheet("stalker", 20, 40, [("idle", 4, 3, True), ("walk", 6, 7, True), ("windup", 1, 1, False)], draw)


def bake_nest():
    flesh = rgb(0.38, 0.12, 0.16)
    flesh_l = shade(flesh, 1.3)
    def draw(c, g, an, i):
        p = [0, 1, 0][i]
        c.ellipse(12, 15, 10 + p * 0.5, 6, shade(flesh, 0.8))
        c.ellipse(7, 12, 5, 5, flesh)
        c.ellipse(16, 12, 6, 5 + p * 0.5, flesh)
        c.ellipse(12, 8, 4.5, 4.5 + p * 0.5, flesh_l)
        for (x, y) in ((8, 11), (15, 13), (12, 7), (18, 10)):
            g.put(x, y, rgb(1.0, 0.5, 0.25, 0.6 + 0.3 * p))
            g.put(x + 1, y, rgb(1.0, 0.45, 0.2, 0.5))
    sheet("nest", 24, 22, [("pulse", 3, 3, True)], draw)

# ---------------------------------------------------------------- obiekty fizyczne (1.5)

def bake_objects():
    wood = rgb(0.46, 0.31, 0.16)
    wood_d = shade(wood, 0.7)
    red = rgb(0.62, 0.14, 0.10)
    def draw(c, g, an, i):
        if an == "crate":
            c.rect(1, 2, 14, 14, wood)
            c.rect(1, 2, 14, 2, shade(wood, 1.15))
            c.rect(1, 14, 14, 2, wood_d)
            c.line(2, 4, 13, 13, wood_d)               # zastrzał
            c.line(2, 5, 12, 14, wood_d)
            for (x, y) in ((2, 3), (13, 3), (2, 14), (13, 14)):
                c.put(x, y, rgb(0.6, 0.6, 0.62))
        elif an == "barrel":
            c.rect(3, 1, 10, 15, red)
            c.rect(3, 1, 2, 15, shade(red, 1.25))
            c.rect(11, 1, 2, 15, shade(red, 0.7))
            for y in (3, 12):
                c.rect(3, y, 10, 1, rgb(0.25, 0.22, 0.2))
            for x in range(4, 12, 2):                  # pas ostrzegawczy
                c.rect(x, 6, 1, 3, rgb(0.95, 0.78, 0.15))
            c.rect(5, 0, 3, 1, rgb(0.35, 0.33, 0.3))
        elif an == "medkit":
            # apteczka (1.5): biała skrzynka z czerwonym krzyżem; krzyż świeci (glow)
            c.rect(3, 7, 10, 8, rgb(0.86, 0.86, 0.82))
            c.rect(3, 13, 10, 2, rgb(0.62, 0.62, 0.6))
            c.rect(6, 5, 4, 2, rgb(0.5, 0.5, 0.5))     # rączka
            c.rect(7, 8, 2, 6, rgb(0.85, 0.12, 0.12))
            c.rect(5, 10, 6, 2, rgb(0.85, 0.12, 0.12))
            g.rect(7, 8, 2, 6, rgb(0.4, 1.0, 0.5, 0.9))
            g.rect(5, 10, 6, 2, rgb(0.4, 1.0, 0.5, 0.9))
    sheet("objects", 16, 16, [("crate", 1, 1, False), ("barrel", 1, 1, False), ("medkit", 1, 1, False)], draw)

# ---------------------------------------------------------------- kafle i dekoracje

TILE = 16


def bake_tiles():
    """Atlas 12×4: kolumny jak w level.gd (# C M ~ = - b w m O i s), rzędy 0/2 wierzch, 1/3 wypełnienie."""
    c = Canvas(TILE * 12, TILE * 4)
    for col in range(12):
        for row in range(4):
            top = row in (0, 2)
            var = row // 2
            rnd = random.Random(col * 97 + row * 13 + 7)
            t = Canvas(TILE, TILE)
            draw_tile(t, col, top, var, rnd)
            c.blit(t, col * TILE, row * TILE)
    c.save(os.path.join(ART, "tiles.png"))


def noise_fill(t, base, amt, rnd):
    for y in range(TILE):
        for x in range(TILE):
            k = 1.0 + rnd.uniform(-amt, amt)
            t.put(x, y, shade(base, k))


def draw_tile(t, col, top, var, rnd):
    if col == 0:      # ziemia: grudki, kamyki, korzenie; wierzch: trawa z kępkami
        noise_fill(t, rgb(0.24, 0.17, 0.11), 0.12, rnd)
        for _ in range(4 + var * 2):
            x, y = rnd.randrange(16), rnd.randrange(4 if top else 0, 16)
            t.put(x, y, rgb(0.36, 0.30, 0.24))
        if rnd.random() < 0.5:
            x = rnd.randrange(2, 14)
            t.line(x, 8, x + rnd.choice((-3, 3)), 15, rgb(0.17, 0.11, 0.07))
        if top:
            for x in range(16):
                h = 2 + (1 if rnd.random() < 0.4 else 0)
                for y in range(h):
                    t.put(x, y, rgb(0.17, 0.30 + rnd.uniform(-0.04, 0.04), 0.13))
                if rnd.random() < 0.3:
                    t.put(x, -1 + h, rgb(0.24, 0.40, 0.18))
    elif col == 1:    # beton: płyty, spoiny, rysy, zacieki
        noise_fill(t, rgb(0.30, 0.31, 0.33), 0.05, rnd)
        t.rect(0, 15, 16, 1, rgb(0.22, 0.23, 0.25))
        t.rect(15 if var == 0 else 7, 0, 1, 16, rgb(0.24, 0.25, 0.27))
        if rnd.random() < 0.7:
            x = rnd.randrange(2, 12)
            t.line(x, rnd.randrange(0, 6), x + rnd.randrange(-2, 3), rnd.randrange(8, 15), rgb(0.21, 0.21, 0.23))
        if top:
            t.rect(0, 0, 16, 1, rgb(0.44, 0.45, 0.47))
            t.rect(rnd.randrange(0, 10), 1, 5, 2, rgb(0.24, 0.26, 0.24))   # mech/zaciek
    elif col == 2:    # blacha/skrzynia: nity, żebrowanie
        noise_fill(t, rgb(0.33, 0.37, 0.41), 0.04, rnd)
        for i in range(0, 16, 4):
            t.line(i, 15, i + 15, 0, rgb(0.38, 0.42, 0.46))
        t.rect(0, 0, 16, 1, rgb(0.48, 0.52, 0.56))
        t.rect(0, 15, 16, 1, rgb(0.20, 0.23, 0.26))
        for (x, y) in ((2, 2), (13, 2), (2, 13), (13, 13)):
            t.put(x, y, rgb(0.62, 0.64, 0.68))
            t.put(x + 1, y + 1, rgb(0.18, 0.2, 0.22))
        if var:
            t.rect(5, 6, 6, 4, rgb(0.42, 0.18, 0.12))  # ślad rdzy
    elif col == 3:    # woda: ciemne podłoże, wierzch z refleksami
        noise_fill(t, rgb(0.08, 0.17, 0.24), 0.08, rnd)
        if top:
            t.rect(0, 0, 16, 2, rgb(0.24, 0.44, 0.54))
            for _ in range(3):
                x = rnd.randrange(14)
                t.rect(x, 0, 3, 1, rgb(0.55, 0.75, 0.82))
            t.put(rnd.randrange(16), rnd.randrange(4, 12), rgb(0.16, 0.28, 0.34))
    elif col == 4:    # kładka metalowa: krata, tylko górne 4 px
        for x in range(16):
            for y in range(4):
                solid = y in (0, 3) or x % 3 == 0
                t.put(x, y, rgb(0.48, 0.50, 0.53) if y == 0 else (rgb(0.36, 0.38, 0.41) if solid else (0, 0, 0, 0)))
    elif col == 5:    # rusztowanie: deska ze słojami i gwoździami
        for x in range(16):
            for y in range(4):
                g = 0.04 * math.sin(x * 0.9 + y * 2.0 + var)
                t.put(x, y, rgb(0.45 + g, 0.31 + g, 0.17))
        t.rect(0, 3, 16, 1, rgb(0.28, 0.18, 0.09))
        t.put(2, 1, rgb(0.6, 0.6, 0.62))
        t.put(13, 1, rgb(0.6, 0.6, 0.62))
        if var:
            t.put(8, 0, (0, 0, 0, 0))                  # wyszczerbienie
    elif col == 6:    # tło: wnętrze posterunku — panele, plamy
        noise_fill(t, rgb(0.12, 0.12, 0.14), 0.06, rnd)
        t.rect(0, 7, 16, 1, rgb(0.09, 0.09, 0.11))
        t.rect(8 if var else 0, 0, 1, 7, rgb(0.09, 0.09, 0.11))
        if rnd.random() < 0.4:
            t.ellipse(rnd.randrange(3, 13), rnd.randrange(9, 14), 2, 3, rgb(0.10, 0.11, 0.10))
    elif col == 8:    # błoto z bagna: ciemna breja, wierzch oliwkowy z kałużami i bąblami
        noise_fill(t, rgb(0.14, 0.11, 0.07), 0.10, rnd)
        if top:
            t.rect(0, 0, 16, 3, rgb(0.20, 0.23, 0.11))
            for _ in range(3):
                x = rnd.randrange(1, 12)
                t.rect(x, 1, rnd.randrange(2, 5), 1, rgb(0.10, 0.12, 0.07))      # kałuża
                t.put(x + 1, 0, rgb(0.42, 0.50, 0.30))                           # połysk
            for _ in range(2):
                t.put(rnd.randrange(16), 2, rgb(0.30, 0.34, 0.18))               # bąbel
        for _ in range(3):
            t.put(rnd.randrange(16), rnd.randrange(5, 16), rgb(0.08, 0.06, 0.04))
    elif col == 9:    # plama oleju: czarna, lśniąca, z tęczowym połyskiem
        noise_fill(t, rgb(0.12, 0.12, 0.14), 0.04, rnd)
        if top:
            t.rect(0, 0, 16, 3, rgb(0.04, 0.04, 0.06))
            for x in range(16):
                if rnd.random() < 0.45:
                    t.put(x, 0, rgb(0.20, 0.14, 0.34))                           # fiolet
                if rnd.random() < 0.3:
                    t.put(x, 1, rgb(0.10, 0.26, 0.30))                           # turkus
            for _ in range(2):
                t.rect(rnd.randrange(1, 12), 0, 3, 1, rgb(0.55, 0.60, 0.70))     # odblask
    elif col == 10:   # lód: błękitny, z białymi rysami
        noise_fill(t, rgb(0.38, 0.55, 0.70), 0.06, rnd)
        for _ in range(3):
            x = rnd.randrange(2, 14)
            t.line(x, rnd.randrange(0, 6), x + rnd.randrange(-3, 4), rnd.randrange(8, 16), rgb(0.62, 0.80, 0.90))
        if top:
            t.rect(0, 0, 16, 3, rgb(0.72, 0.88, 0.95))
            for _ in range(3):
                t.put(rnd.randrange(16), 0, rgb(1.0, 1.0, 1.0))
    elif col == 11:   # śnieg: biały puch, na boku błękitne cienie
        noise_fill(t, rgb(0.62, 0.70, 0.82), 0.05, rnd)
        if top:
            t.rect(0, 0, 16, 3, rgb(0.93, 0.96, 1.0))
            for x in range(16):
                if rnd.random() < 0.35:
                    t.put(x, 3, rgb(0.86, 0.92, 1.0))
    elif col == 7:    # tło: belka / pień (środkowe 8 px), kora
        for y in range(16):
            for x in range(4, 12):
                g = 0.03 * math.sin(y * 0.8 + x * 2.5 + var * 3)
                t.put(x, y, rgb(0.19 + g, 0.13 + g, 0.08))
            if rnd.random() < 0.25:
                t.put(rnd.randrange(5, 11), y, rgb(0.12, 0.08, 0.05))


PROPS = ["grass_a", "grass_b", "fern", "rock", "bones", "reeds", "fence", "logs"]


def bake_props():
    c = Canvas(16 * len(PROPS), 16)
    for i, name in enumerate(PROPS):
        t = Canvas(16, 16)
        rnd = random.Random(i * 31 + 5)
        g = rgb(0.18, 0.32, 0.14)
        gl = rgb(0.26, 0.42, 0.18)
        if name in ("grass_a", "grass_b"):
            for k in range(6 if name == "grass_a" else 9):
                x = rnd.randrange(1, 15)
                h = rnd.randrange(3, 8)
                t.line(x, 15, x + rnd.choice((-1, 0, 1)), 15 - h, g if k % 2 else gl)
        elif name == "fern":
            t.line(8, 15, 8, 6, g)
            for y in range(7, 15, 2):
                t.line(8, y, 3 + (y - 7) // 3, y - 2, gl)
                t.line(8, y, 13 - (y - 7) // 3, y - 2, gl)
        elif name == "rock":
            t.ellipse(8, 12, 6, 4, rgb(0.30, 0.30, 0.32))
            t.ellipse(7, 11, 3, 2, rgb(0.38, 0.38, 0.40))
            t.put(10, 10, rgb(0.24, 0.32, 0.20))
        elif name == "bones":
            bone = rgb(0.80, 0.76, 0.66)
            t.line(3, 14, 12, 12, bone)
            t.ellipse(12, 11, 2.5, 2, bone)
            t.put(11, 11, OUTLINE)
            t.line(5, 15, 9, 13, shade(bone, 0.8))
        elif name == "reeds":
            for k in range(5):
                x = 3 + k * 2 + rnd.randrange(0, 2)
                t.line(x, 15, x + rnd.choice((-1, 1)), 4 + rnd.randrange(0, 4), rgb(0.30, 0.34, 0.18))
                t.rect(x - 1 + rnd.choice((0, 1)), 4 + rnd.randrange(0, 3), 2, 3, rgb(0.32, 0.22, 0.12))
        elif name == "fence":
            wood = rgb(0.34, 0.24, 0.14)
            for x in (2, 8, 13):
                t.rect(x, 5, 2, 11, wood)
            t.rect(0, 7, 16, 2, shade(wood, 1.15))
            t.rect(0, 11, 16, 1, shade(wood, 0.9))
        elif name == "logs":
            for k, (x, y) in enumerate(((5, 12), (11, 12), (8, 8))):
                t.ellipse(x, y, 3.5, 3.5, rgb(0.36, 0.25, 0.14))
                t.ellipse(x, y, 2, 2, rgb(0.62, 0.48, 0.30))
                t.put(x, y, rgb(0.45, 0.33, 0.20))
        o = Canvas(16, 16)
        o.blit(t, 0, 0)
        if name not in ("grass_a", "grass_b", "reeds"):
            o.outline(OUTLINE, t)
        c.blit(o, i * 16, 0)
    c.save(os.path.join(ART, "props.png"))
    MANIFEST["props"] = PROPS


def bake_only(names):
    """Przepieka tylko wskazane arkusze postaci (np. `--only=leech`) i dopisuje je do istniejącego sprites.json."""
    path = os.path.join(ART, "sprites.json")
    with open(path) as f:
        MANIFEST.update(json.load(f))
    bake_chars_hd(set(names))
    with open(path, "w") as f:
        json.dump(MANIFEST, f, indent=1)
    print("przepieczone: %s" % ", ".join(sorted(names)))
    print("NASTĘPNY KROK: godot --headless --path . --import")


def main():
    only = [a[7:].split(",") for a in sys.argv[1:] if a.startswith("--only=")]
    if only and HAVE_CHARS:
        return bake_only(only[0])
    if HAVE_CHARS:
        bake_chars_hd()
    else:
        print("UWAGA: brak numpy/Pillow — postacie rysowane po staremu (pip install -r tools/requirements.txt)")
        bake_players()
        bake_trzosek()
        bake_wolek()
        bake_stalker()
    if HAVE_CHARS:
        bake_guns_hd()
    else:
        bake_guns()
        bake_nest()
    bake_objects()
    bake_tiles()
    bake_props()
    with open(os.path.join(ART, "sprites.json"), "w") as f:
        json.dump(MANIFEST, f, indent=1)
    n = len(MANIFEST["sheets"])
    print("sprite'y: %d arkuszy + tiles.png + props.png → %s" % (n, ART))
    print("NASTĘPNY KROK: godot --headless --path . --import")


if __name__ == "__main__":
    main()
