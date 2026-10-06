"""The Vein / Żyła — boss (128×80 świata = 256×160 pikseli arkusza), ten sam silnik co potwory (char_art.py: render 4×, rampy, obrys).

Bryła: ciemnoczerwona masa mięsa z pancernym grzbietem (5 płyt kostnych z kolcami), sześć macek-odnóży
(gniazda to jej kończyny), korona wąsów, rząd oczu i paszcza na dole — zamknięta = dwie płyty ze szwem,
otwarta = ciemna jama z kręgiem zębów (słaby punkt; jej żar dorysowuje nakładka w boss.gd).

Układ jak u potworów: wiersz = animacja, ciało cieniowane + warstwa `glow` (unshaded: oczy, żar).
Rejon gry: wiersz GROUND_Y arkusza = y 0 w świecie, środek paszczy = (MAW_X, MAW_Y) → świat (0, MAW_Y − GROUND_Y).
"""
import math
import random
from char_art import Hi, Frame, ramp, mix
from char_monsters import _finish
from char_monsters_hd import Sc

FW, FH = 128, 80                   # rozmiar w świecie (px)
DENSITY = 2                        # pikseli arkusza na piksel świata (gra rysuje arkusz w skali 1/DENSITY)
FWD, FHD = FW * DENSITY, FH * DENSITY
GROUND_Y = 74                      # wiersz arkusza odpowiadający y = 0 w świecie (korzenie leżą tuż pod)
MAW_X, MAW_Y = 64, 60              # środek paszczy w arkuszu
BOSS_ANIMS = [("dormant", 4, 1.5, True), ("idle", 6, 5, True), ("open", 4, 6, True),
              ("windup", 3, 6, True), ("spit", 3, 9, True)]

# żyły na korpusie (współrzędne arkusza) — nakładka w boss.gd rysuje ten sam przebieg jako żar
VEINS = [
    [(58, 56), (53, 50), (47, 48), (42, 43)],
    [(64, 54), (66, 47), (63, 41), (66, 35)],
    [(70, 56), (76, 52), (82, 50), (87, 44)],
]

EYE = (255, 150, 54)
EYE_DORM = (140, 70, 40)
THROAT_EMBER = (255, 110, 50)
SPORE = (150, 255, 80)


def _tentacle(hi, mat, mat_d, bone, origin, a0, curl, segs, seg_len, r0, r1, t, phase, amp, side):
    """Macka: łańcuch kapsuł; kąt w stopniach ekranu (0 = w prawo, 90 = w dół), side = −1 odbija w lewo."""
    x, y = origin
    a = a0
    pts = [(x, y)]
    for s in range(segs):
        wave = amp * math.sin(t + phase + s * 0.9) * (0.4 + s * 0.35)
        ang = math.radians(a + wave)
        ln = seg_len * 0.94 * (1.0 - 0.07 * s)
        x += side * math.cos(ang) * ln
        y += math.sin(ang) * ln
        pts.append((x, y))
        a += curl
    for s in range(segs):
        ra = r0 + (r1 - r0) * s / segs
        rb = r0 + (r1 - r0) * (s + 1) / segs
        hi.capsule(pts[s], pts[s + 1], ra, rb, mat if s % 2 == 0 else mat_d)
    # stawy z kolcami kostnymi od spodu i zakończenie zgrubieniem
    for s in (2,):
        px, py = pts[s]
        hi.poly([(px - 1.0, py + 0.2), (px + 0.1, py + 3.6), (px + 1.1, py + 0.3)], bone, normal=(0.1, 0.3, 0.9))
    tip = pts[-1]
    hi.ellipse(tip, r1 + 0.8, r1 + 0.8, mat)
    return pts


def vein(an, i):
    D = DENSITY
    hi = Sc(FWD, FHD, float(D))
    dorm = an == "dormant"
    base = (100, 42, 48) if dorm else (136, 40, 44)
    flesh = hi.material(ramp(base, cool=(0.22, 0.08, 0.20)))
    flesh_l = hi.material(ramp(tuple(min(255, int(c * 1.22)) for c in base), cool=(0.22, 0.08, 0.20)))
    flesh_d = hi.material(ramp(tuple(int(c * 0.58) for c in base), cool=(0.18, 0.06, 0.18)))
    plate = hi.material(ramp((150, 136, 118), cool=(0.22, 0.16, 0.34)), bands=(-0.05, 0.25, 0.55, 0.85))
    plate_d = hi.material(ramp((98, 88, 82), cool=(0.18, 0.14, 0.32)), bands=(-0.05, 0.25, 0.55, 0.85))
    bone = hi.material(ramp((232, 218, 178), cool=(0.3, 0.2, 0.3)), bands=(0.0, 0.3, 0.6, 0.88))
    throat = hi.material(ramp((46, 10, 22), cool=(0.1, 0.05, 0.2)), bands=(0.2, 0.5, 0.8, 0.95))
    plate_m = hi.material(ramp((124, 108, 94), cool=(0.22, 0.16, 0.30)), bands=(-0.05, 0.25, 0.55, 0.85))
    pust = hi.material(ramp((196, 96, 76), cool=(0.3, 0.1, 0.2)))

    n = {"dormant": 4, "idle": 6, "open": 4, "windup": 3, "spit": 3}[an]
    t = i / n * math.tau
    breath = 0.5 + 0.5 * math.sin(t)
    b = 1.0 + 0.03 * math.sin(t)
    sag = 0.0
    bx, by = 64.0, 52.0
    rx, ry = 35.0 * b, 25.0 * b
    open_amt = 0.0
    if dorm:
        sag, b = 3.0, 0.96
        by += sag
        rx, ry = 34.0, 21.0 + 0.8 * math.sin(t)
    elif an == "open":
        open_amt = 0.85 + 0.15 * math.sin(t)
    elif an == "windup":
        by -= 2.0
        ry += 1.5
    elif an == "spit":
        rx, ry = 36.0 + 1.5 * math.sin(t * 2), 27.0 + 1.5 * math.sin(t * 2)
        by -= 2.0
        open_amt = 1.0

    # --- korzenie przy ziemi: masa rozlewa się na boki
    for k, (cx, w, h) in enumerate(((22, 22, 5.0), (44, 24, 6.0), (84, 24, 6.0), (106, 22, 5.0))):
        hi.ellipse((cx, GROUND_Y - 3.2 + (0.4 if k % 2 else 0)), w * 0.5, h * 0.5 + 1.2, flesh_d)
    hi.ellipse((bx, 66.0), 38.0, 10.0, flesh_d)

    # --- macki (rysowane przed korpusem: wyrastają z boków)
    amp = 3.0 if not dorm else 0.6
    for side in (-1, 1):
        ox = bx + side * (rx - 4)
        phase = 0.0 if side == 1 else 1.7
        if dorm:
            defs = [((ox, by + 6), 60, 8, 4, 10, 5.0, 1.4), ((ox, by + 12), 80, 6, 4, 9, 4.6, 1.3)]
        elif an == "windup":
            defs = [((ox, by - 4), -95, 22, 4, 9, 5.4, 1.4), ((ox, by + 4), -45, 16, 4, 9, 5.0, 1.3),
                    ((ox, by + 12), -4, 12, 4, 8, 4.4, 1.2)]
        elif an == "spit":
            defs = [((ox, by - 2), -62, 26, 4, 8, 5.2, 1.4), ((ox, by + 8), -12, 20, 4, 8, 4.8, 1.3),
                    ((ox, by + 14), 20, 12, 3, 8, 4.2, 1.2)]
        else:
            defs = [((ox, by - 4), -64, 19, 4, 9, 5.4, 1.4), ((ox, by + 4), -26, 15, 4, 9, 5.0, 1.3),
                    ((ox, by + 12), 6, 12, 4, 8, 4.4, 1.2)]
        for k, (org, a0, curl, segs, ln, r0, r1) in enumerate(defs):
            _tentacle(hi, flesh_d if k != 1 else flesh, flesh_d, bone, org, a0, curl, segs, ln, r0, r1, t, phase + k * 1.1, amp, side)

    # --- korpus: bryła + boczne guzy + górne wypukłości
    hi.ellipse((bx, by), rx, ry, flesh)
    hi.ellipse((bx - 24, by + 2), 13.0 * b, 14.0 * b, flesh_d)
    hi.ellipse((bx + 24, by + 2), 13.0 * b, 14.0 * b, flesh_d)
    hi.ellipse((bx - 13, by - 14), 11.0, 8.5, flesh_l)
    hi.ellipse((bx + 14, by - 15), 10.0, 8.0, flesh_l)
    hi.ellipse((bx, by + 10), 26.0, 11.0, flesh)
    # fałdy mięsa na brzuchu
    for dx in (-17, -9, 9, 17):
        hi.capsule((bx + dx, by + 1), (bx + dx * 1.15, by + 12), 0.9, 0.6, flesh_d)

    # --- pory i guzki skóry: stały rozkład (te same w każdej klatce), widoczne dzięki 2× gęstości
    rnd = random.Random(11)
    for _ in range(54):
        px_ = bx + rnd.uniform(-0.88, 0.88) * rx
        py_ = by + rnd.uniform(-0.8, 0.9) * ry
        if ((px_ - bx) / rx) ** 2 + ((py_ - by) / ry) ** 2 > 0.8 or abs(px_ - MAW_X) < 17 and abs(py_ - (by + 10)) < 11:
            continue
        hi.ellipse((px_, py_), 0.55, 0.42, flesh_d)
        hi.ellipse((px_ - 0.2, py_ - 0.2), 0.22, 0.16, flesh_l)

    # --- wypukłe żyły (cięciwy mięsa); nakładka dorysowuje w nich żar
    for vi, v in enumerate(VEINS):
        vv = [(x, y + sag) for x, y in v]
        for k in range(len(vv) - 1):
            r_a, r_b = 1.5 - 0.25 * k, 1.5 - 0.25 * (k + 1)
            hi.capsule(vv[k], vv[k + 1], r_a, max(r_b, 0.5), flesh_l if vi != 1 else flesh_l, bias=0.15)

    # --- pancerny grzbiet: pięć nachodzących płyt, kolce na trzech
    for k in range(5):
        a = math.radians(205 + k * 32.5)
        px = bx + math.cos(a) * (rx + 0.5)
        py = by + math.sin(a) * (ry + 0.5) + (1.0 if dorm else 0.0)
        rot = a + math.pi / 2
        big = 1.0 + (0.16 if k == 2 else (-0.1 if k in (0, 4) else 0.0))
        hi.ellipse((px, py), 9.2 * big, 4.6 * big, plate, rot=rot)
        hi.ellipse((px - math.cos(a) * 1.0, py - math.sin(a) * 1.0), 6.0, 2.6, plate, rot=rot, bias=0.18)
        hi.ellipse((px + math.cos(a) * 1.9, py + math.sin(a) * 1.9), 7.4, 1.8, plate_d, rot=rot)
        tx_, ty_ = -math.sin(a), math.cos(a)
        for off in (-0.9, 0.0, 0.9):                                          # żebra płyty (drobny detal gęstszej siatki)
            c0 = (px - tx_ * 6.4 + math.cos(a) * off, py - ty_ * 6.4 + math.sin(a) * off)
            c1 = (px + tx_ * 6.4 + math.cos(a) * off, py + ty_ * 6.4 + math.sin(a) * off)
            hi.capsule(c0, c1, 0.22, 0.22, plate_d)
        if k in (0, 2, 4):
            nx, ny = math.cos(a), math.sin(a)
            tx, ty = -ny, nx
            ln = 9.0 if k == 2 else 7.0
            hi.poly([(px + nx * 3 - tx * 2.2, py + ny * 3 - ty * 2.2), (px + nx * (3 + ln), py + ny * (3 + ln)),
                     (px + nx * 3 + tx * 2.2, py + ny * 3 + ty * 2.2)], bone, normal=(nx * 0.5, ny * 0.5 - 0.1, 0.7))

    # --- wąsy korony: dwa cienkie czułki z bulwą (nie w uśpieniu)
    if not dorm:
        for side in (-1, 1):
            lift = 6.0 if an == "windup" else 0.0
            _tentacle(hi, flesh_l, flesh, bone, (bx + side * 8, by - 22), -80 + (4 if side > 0 else -4) * 0, 16,
                      4, 6.5, 1.8, 0.8, t, 0.6 if side > 0 else 2.2, 3.5, side)

    # --- paszcza
    mx, my = MAW_X, MAW_Y - (2 if an in ("windup", "spit") else 0) + (sag if dorm else 0)
    hi.ellipse((mx, my), 18.5, 12.0, flesh_d)                                   # obrzeże
    if open_amt <= 0.0:
        hi.ellipse((mx, my), 14.5, 9.4, plate_d)
        hi.poly([(mx - 0.8, my - 9.0), (mx - 14.0, my - 3.0), (mx - 13.0, my + 5.0), (mx - 6.0, my + 9.0), (mx - 0.8, my + 8.0)], plate_m)   # płyty ze szwem
        hi.poly([(mx + 0.8, my - 9.0), (mx + 14.0, my - 3.0), (mx + 13.0, my + 5.0), (mx + 6.0, my + 9.0), (mx + 0.8, my + 8.0)], plate_m)
        hi.ellipse((mx - 7.0, my - 3.0), 4.0, 2.4, plate_m, bias=0.2)               # połyski
        hi.ellipse((mx + 7.0, my - 3.0), 4.0, 2.4, plate_m, bias=0.2)
        for ang in (-50, -20, 20, 50):                                           # żebra płyt
            ra = math.radians(ang)
            for side in (-1, 1):
                hi.capsule((mx + side * 2.4, my + 6.0 * math.sin(ra) * 0.5), (mx + side * (7.0 + 4.0 * math.cos(ra)), my + 7.0 * math.sin(ra)), 0.35, 0.35, plate_d)
        hi.capsule((mx, my - 9.0), (mx, my + 9.0), 0.6, 0.6, throat)
        for dx, dy in ((-3.0, 0.0), (3.0, 0.0), (0.0, 0.0)):                     # kły w szwie
            hi.poly([(mx + dx - 1.0, my - 1.0), (mx + dx, my + 2.8), (mx + dx + 1.0, my - 1.0)], bone)
        for dy in (-4.0, 0.0, 4.0):                                              # nity
            hi.ellipse((mx - 9.5, my + dy), 0.8, 0.8, bone)
            hi.ellipse((mx + 9.5, my + dy), 0.8, 0.8, bone)
    else:
        orx, ory = 6.0 + 9.5 * open_amt, 4.0 + 6.8 * open_amt
        hi.ellipse((mx, my), orx + 2.4, ory + 2.0, plate_d)                      # odchylone płyty szczęk
        hi.ellipse((mx - orx - 2.0, my), 4.6, 7.8, plate, rot=0.35)
        hi.ellipse((mx + orx + 2.0, my), 4.6, 7.8, plate, rot=-0.35)
        hi.ellipse((mx, my - ory - 1.6), 9.0, 3.6, plate)
        hi.ellipse((mx, my + ory + 1.6), 9.0, 3.4, plate_d)
        hi.ellipse((mx, my), orx, ory, throat)                                   # jama
        teeth = 12
        for k in range(teeth):
            a = math.tau * (k + 0.5) / teeth
            ex, ey = mx + math.cos(a) * orx, my + math.sin(a) * ory
            ix, iy = mx + math.cos(a) * (orx - 3.4), my + math.sin(a) * (ory - 2.6)
            nx, ny = -math.sin(a), math.cos(a)
            hi.poly([(ex + nx * 1.1, ey + ny * 0.9), (ix, iy), (ex - nx * 1.1, ey - ny * 0.9)], bone, normal=(0.0, 0.2, 0.9))
        if an == "spit":                                                          # nabrzmiały worek zarodników w gardle
            hi.ellipse((mx, my - 1.0), orx * 0.55, ory * 0.6, pust)

    fr = _finish(hi)
    fr.outline(0.3)                                       # 2 px arkusza = 1 px świata, jak u reszty sprite'ów
    glow = Frame(FWD, FHD)

    def gput(frame, x, y, col, w=1):
        """Punkt świecący (współrzędne świata): w×1 px świata = w·D × D pikseli arkusza; wyśrodkowany na (x, y)."""
        x0, y0 = int(round(x * D)), int(round(y * D))
        for yy in range(D):
            for xx in range(w * D):
                frame.put(x0 + xx, y0 + yy, col)
    # --- oczy: rząd szczelin na górnej partii (zamknięte w uśpieniu)
    ecol = EYE_DORM if dorm else EYE
    ea = 110 if dorm else 255
    eyes = [(bx - 13, by - 9), (bx - 5, by - 12), (bx + 5, by - 12), (bx + 13, by - 9)]
    if an == "windup":
        ecol = (255, 70, 40)
    elif an == "spit":
        ecol = (190, 255, 90)
    for ex, ey in eyes:
        gput(glow, ex, ey, (*ecol, ea), 1 if dorm else 2)
    # ozdobne guzki-lampiony wzdłuż boków: słabe tlenie
    for px, py in ((bx - 31, by + 4), (bx - 27, by + 12), (bx + 31, by + 4), (bx + 27, by + 12), (bx - 8, by + 17), (bx + 8, by + 17)):
        for yy in range(D):
            for xx in range(D):
                fr.only_opaque_put(int(round(px * D)) + xx, int(round(py * D)) + yy, (*mix(base, (255, 150, 90), 0.6), 255))
        gput(glow, px, py, (*THROAT_EMBER, 90 if dorm else 150))
    # żar w głębi gardła (dynamiczny blask dodaje nakładka)
    if open_amt > 0.0:
        col = SPORE if an == "spit" else THROAT_EMBER
        for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
            gput(glow, mx + dx, my + dy, (*col, 200))
    return fr, glow
