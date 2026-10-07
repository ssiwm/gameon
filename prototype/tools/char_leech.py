"""Pijawka — boss misji B1 (96×80 świata = 192×160 pikseli arkusza), ten sam silnik co potwory i Żyła (char_art.py: render 4×, rampy, obrys).

Wynurzona Pijawka: wysoki, segmentowy tułów wyrastający z wody (pierścienie ciemnozielonej skóry z jaśniejszym brzuchem, śluz) i głowa
minogi — okrągła przyssawka z kręgami zębów zwrócona w PRAWO (gra odbija sprite w stronę celu). Pod wodą Pijawka nie ma sprite'a:
cień, kręgi i zapowiedź rysuje leech.gd proceduralnie (światło ujawnia go dynamicznie), a ten arkusz służy tylko wynurzeniu.

Animacje: rise (wynurzenie, 4 klatki), idle (kołysanie, 6), grab (głowa nisko, paszcza szeroko, 3), dead (zwisa, 1).
Układ jak u potworów: wiersz = animacja, ciało cieniowane + warstwa `glow` (unshaded: oczy, żar w gardle).
Linia wody: wiersz GROUND_Y arkusza = y 0 w świecie (sprite przesuwany o SPRITE_DROP w leech.gd).
"""
import math
import random
from char_art import Frame, ramp, mix
from char_monsters import _finish
from char_monsters_hd import Sc

FW, FH = 96, 80                    # rozmiar klatki w świecie (px)
DENSITY = 2                        # pikseli arkusza na piksel świata (gra rysuje arkusz w skali 1/DENSITY)
FWD, FHD = FW * DENSITY, FH * DENSITY
GROUND_Y = 74                      # wiersz arkusza odpowiadający y = 0 w świecie (poziom wody)
LEECH_ANIMS = [("rise", 4, 14, False), ("idle", 6, 6, True), ("grab", 3, 7, True), ("dead", 1, 1, False)]

EYE = (232, 244, 160)
THROAT = (255, 96, 84)


def _spine(an, i, n):
    """Punkty kręgosłupa od wody (0) do szyi (głowa osobno) oraz kąt głowy i otwarcie paszczy."""
    t = i / max(1, n) * math.tau
    height = 55.0
    sway = 2.6 * math.sin(t)
    lean = 0.0
    open_amt = 0.45 + 0.25 * math.sin(t * 2.0)
    head_down = 0.0
    if an == "rise":
        height = (20.0, 35.0, 48.0, 55.0)[i]
        sway = (0.0, 1.2, 2.0, 1.4)[i]
        open_amt = (0.0, 0.15, 0.5, 0.7)[i]
    elif an == "grab":
        height = 44.0 + 1.5 * math.sin(t)
        lean = 9.0
        sway = 1.5 * math.sin(t * 1.5)
        open_amt = 1.0
        head_down = 0.5 + 0.08 * math.sin(t)
    elif an == "dead":
        height = 33.0
        lean = 14.0
        sway = 0.0
        open_amt = 0.05
        head_down = 1.2
    pts = []
    k = 8
    for s in range(k):
        f = s / (k - 1)
        # tułów wygina się: dół prosto, góra odchylona o `lean` i kołysana
        x = 46.0 + sway * (f ** 1.4) + lean * (f ** 2.0) + 3.2 * math.sin(f * math.pi * 1.6)
        y = GROUND_Y - height * f
        pts.append((x, y))
    return pts, open_amt, head_down


def leech(an, i):
    D = DENSITY
    hi = Sc(FWD, FHD, float(D))
    n = {"rise": 4, "idle": 6, "grab": 3, "dead": 1}[an]
    dead = an == "dead"
    base = (52, 82, 70) if not dead else (44, 66, 58)
    skin = hi.material(ramp(base, cool=(0.10, 0.18, 0.26)))
    skin_l = hi.material(ramp(tuple(min(255, int(c * 1.28)) for c in base), cool=(0.10, 0.18, 0.26)))
    skin_d = hi.material(ramp(tuple(int(c * 0.62) for c in base), cool=(0.08, 0.14, 0.24)))
    belly = hi.material(ramp((150, 124, 100), cool=(0.20, 0.16, 0.30)))
    lip = hi.material(ramp((142, 52, 56), cool=(0.20, 0.10, 0.24)))
    bone = hi.material(ramp((232, 222, 190), cool=(0.3, 0.2, 0.3)), bands=(0.0, 0.3, 0.6, 0.88))
    throat = hi.material(ramp((46, 10, 22), cool=(0.1, 0.05, 0.2)), bands=(0.2, 0.5, 0.8, 0.95))
    foam = hi.material(ramp((196, 224, 220), cool=(0.20, 0.30, 0.40)))
    slime = hi.material(ramp((150, 196, 170), cool=(0.18, 0.30, 0.36)))

    pts, open_amt, head_down = _spine(an, i, n)
    # --- piana przy linii wody: rozchlapana woda wokół podstawy (nie w klatce „dead")
    if not dead:
        hi.ellipse((48.0, GROUND_Y + 1.0), 24.0, 3.4, foam)
        hi.ellipse((48.0, GROUND_Y + 1.0), 17.0, 2.2, skin_d)
    # --- tułów: kapsuły z pierścieniami; promień maleje ku szyi, brzuch jaśniejszy od strony głowy (prawa)
    segs = len(pts) - 1
    for s in range(segs):
        f0, f1 = s / segs, (s + 1) / segs
        r0 = 14.0 - 4.8 * f0
        r1 = 14.0 - 4.8 * f1
        hi.capsule(pts[s], pts[s + 1], r0, r1, skin if s % 2 == 0 else skin_d)
        mx = (pts[s][0] + pts[s + 1][0]) * 0.5
        my = (pts[s][1] + pts[s + 1][1]) * 0.5
        rm = (r0 + r1) * 0.5
        hi.ellipse((mx + rm * 0.38, my), rm * 0.34, rm * 0.92, belly)              # brzuch (jasny pas) z boku do przodu
        hi.capsule((mx - rm * 0.9, my - 1.0), (mx + rm * 0.9, my - 1.0), 0.35, 0.35, skin_d)   # szew pierścienia
    # grzbiet: jaśniejsze guzki wzdłuż tylnej krawędzi
    rnd = random.Random(7)
    for s in range(1, len(pts) - 1):
        px, py = pts[s]
        rr = 14.0 - 4.8 * s / segs
        hi.ellipse((px - rr * 0.78, py), 1.5, 2.6, skin_l)
    for _ in range(26):                                                              # pory i śluz
        s = rnd.randrange(0, len(pts) - 1)
        px, py = pts[s]
        rr = 14.0 - 4.8 * s / segs
        ox = rnd.uniform(-0.8, 0.6) * rr
        hi.ellipse((px + ox, py + rnd.uniform(-2.5, 2.5)), 0.5, 0.4, slime if rnd.random() < 0.35 else skin_d)
    # --- głowa: owalna, z okrągłą przyssawką po prawej (kąt pochylenia head_down radianów w dół)
    hx, hy = pts[-1]
    ang = head_down
    ca, sa = math.cos(ang), math.sin(ang)
    hc = (hx + 3.0 * ca, hy - 1.0 + 3.0 * sa)
    hi.ellipse(hc, 10.5, 9.0, skin, rot=ang * 0.6)
    hi.ellipse((hc[0] - 2.0, hc[1] - 3.2), 7.0, 3.2, skin_l, rot=ang * 0.6)
    # przyssawka: kręgi — warga, pierścień zębów, jama
    mc = (hc[0] + 7.5 * ca, hc[1] + 7.5 * sa * 0.5)
    ry = 5.6 + 5.2 * open_amt
    rx = 3.6 + 2.2 * open_amt
    hi.ellipse(mc, rx + 2.2, ry + 2.0, lip, rot=0.0)
    hi.ellipse(mc, rx + 0.4, ry + 0.2, bone if open_amt > 0.05 else lip)
    hi.ellipse(mc, rx - 0.5, ry - 0.9, throat)
    if open_amt > 0.05:
        teeth = 14
        for k in range(teeth):
            a = math.tau * (k + 0.5) / teeth
            ex, ey = mc[0] + math.cos(a) * rx, mc[1] + math.sin(a) * ry
            ix, iy = mc[0] + math.cos(a) * rx * 0.35, mc[1] + math.sin(a) * ry * 0.4
            nx, ny = -math.sin(a), math.cos(a)
            hi.poly([(ex + nx * 0.9, ey + ny * 0.9), (ix, iy), (ex - nx * 0.9, ey - ny * 0.9)], bone, normal=(0.2, 0.1, 0.95))
        # drugi, mniejszy krąg zębów w głębi
        for k in range(8):
            a = math.tau * (k + 0.2) / 8
            ex, ey = mc[0] + math.cos(a) * rx * 0.55, mc[1] + math.sin(a) * ry * 0.55
            hi.ellipse((ex, ey), 0.7, 0.7, bone)
    # kropki śluzu i skóra wokół głowy
    for k in range(3):
        hi.ellipse((hc[0] - 6.0 + k * 3.0, hc[1] + 6.2), 0.6, 0.9 + 0.3 * k, slime)

    fr = _finish(hi)
    fr.outline(0.3)
    glow = Frame(FWD, FHD)

    def gput(x, y, col, w=1):
        x0, y0 = int(round(x * D)), int(round(y * D))
        for yy in range(D):
            for xx in range(w * D):
                glow.put(x0 + xx, y0 + yy, col)
    # oczy: dwie jasne kropki na górze głowy (zgaszone w „dead")
    if not dead:
        ea = 255
        gput(hc[0] + 1.0, hc[1] - 5.0, (*EYE, ea), 2)
        gput(hc[0] - 4.0, hc[1] - 5.2, (*EYE, 210), 2)
    # żar w gardle
    if open_amt > 0.3:
        for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
            gput(mc[0] + dx, mc[1] + dy, (*THROAT, 190))
    return fr, glow
