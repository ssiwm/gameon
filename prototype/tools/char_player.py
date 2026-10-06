"""Gracz i bot (16×24): rig humanoida + animacje (idle, run, jump, fall, crouch, crouch_walk, down).

Klatka powstaje z pozy — patrz char_art.py. Postać patrzy w prawo; gra odbija ją poziomo.
Dłoń trzymająca broń musi wypaść w (9, 12) — tam jest oś obrotu sprite'a broni (weapon_view.gd).
"""
import math
from char_art import Hi, Frame, ramp, mix, fk, up

FW, FH = 16, 24
GROUND = 23.7

SKIN = (222, 172, 138)
PANTS = (88, 98, 122)
BOOTS = (58, 50, 54)
GEAR = (92, 80, 56)          # plecak, pasy, kieszenie
METAL = (150, 156, 168)
EYE = (34, 26, 38)

PLAYER_ANIMS = [("idle", 6, 5, True), ("run", 8, 14, True), ("jump", 1, 1, False), ("fall", 1, 1, False),
                ("crouch", 1, 1, False), ("crouch_walk", 6, 9, True), ("down", 1, 1, False)]


class Pose:
    def __init__(self, **kw):
        self.hip = (7.6, 15.0)
        self.lean = 4.0            # tułów do przodu (stopnie)
        self.head = 2.0            # dodatkowe pochylenie głowy
        self.thigh = [0.0, 0.0]    # [przednia (bliższa), tylna]; kąt od pionu, + = do przodu
        self.flex = [8.0, 8.0]     # zgięcie kolana (goleń do tyłu względem uda)
        self.foot = [0.0, 0.0]     # obrót stopy względem „płasko"
        self.arm_far = (-20.0, 20.0)   # (bark, łokieć) tylnej ręki
        self.bob = 0.0
        self.ground = True
        self.prone = False
        self.ant = 0.0             # wychylenie anteny (px)
        self.__dict__.update(kw)


def pose_for(an, i):
    p = Pose()
    if an == "idle":
        t = i / 6.0 * math.tau
        p.bob = -0.35 * math.sin(t)                      # oddech
        p.lean = 4.0 + 0.8 * math.sin(t)
        p.head = 2.0 - 0.8 * math.sin(t - 0.6)
        p.thigh = [9.0, -9.0]
        p.flex = [8.0, 8.0]
        p.arm_far = (-10.0 + 3.0 * math.sin(t), 16.0)
        p.ant = 0.35 * math.sin(t - 0.8)
    elif an == "run":
        t = i / 8.0 * math.tau
        for k, ph in enumerate((t, t + math.pi)):
            p.thigh[k] = 42.0 * math.sin(ph)
            p.flex[k] = 12.0 + 62.0 * max(0.0, math.cos(ph)) ** 1.3
            p.foot[k] = -14.0 * max(0.0, math.cos(ph)) + 8.0 * max(0.0, -math.sin(ph))
        p.lean = 14.0
        p.head = -4.0
        p.hip = (7.2, 14.6)
        p.arm_far = (-48.0 * math.sin(t), 38.0 + 22.0 * math.cos(t))
        p.bob = -0.4 * abs(math.sin(t))
        p.ant = -1.2 + 0.6 * math.sin(2 * t)
    elif an == "jump":
        p.thigh = [52.0, -14.0]
        p.flex = [78.0, 36.0]
        p.foot = [-18.0, 10.0]
        p.lean = 8.0
        p.arm_far = (-70.0, 30.0)
        p.hip = (7.6, 13.6)
        p.ground = False
        p.ant = -1.0
    elif an == "fall":
        p.thigh = [18.0, -12.0]
        p.flex = [24.0, 40.0]
        p.foot = [10.0, 20.0]
        p.lean = 2.0
        p.arm_far = (-120.0, 20.0)
        p.hip = (7.6, 14.2)
        p.ground = False
        p.ant = 1.1
    elif an in ("crouch", "crouch_walk"):
        p.hip = (7.0, 18.0)
        p.lean = 22.0
        p.head = -6.0
        p.thigh = [74.0, 48.0]
        p.flex = [118.0, 100.0]
        p.foot = [-6.0, -4.0]
        p.arm_far = (-6.0, 40.0)
        if an == "crouch_walk":
            t = i / 6.0 * math.tau
            p.thigh = [66.0 + 14.0 * math.sin(t), 52.0 - 14.0 * math.sin(t)]
            p.flex = [108.0 + 14.0 * math.cos(t), 98.0 - 14.0 * math.cos(t)]
            p.bob = 0.25 * math.sin(2 * t)
            p.ant = 0.4 * math.sin(t)
    elif an == "down":
        p.prone = True
    return p


def build(col, bot, an, i):
    p = pose_for(an, i)
    hi = Hi(FW, FH)
    jacket = hi.material(ramp(col))
    jacket_d = hi.material(ramp(mix(col, (20, 20, 30), 0.45)))
    skin = hi.material(ramp(SKIN, warm=(1.0, 0.92, 0.75), cool=(0.38, 0.14, 0.10), sh=0.8))
    pants = hi.material(ramp(PANTS))
    boots = hi.material(ramp(BOOTS), bands=(-0.1, 0.35, 0.7, 0.95))
    gear = hi.material(ramp(GEAR))
    metal = hi.material(ramp(METAL, cool=(0.2, 0.2, 0.4)), bands=(0.0, 0.3, 0.6, 0.88))
    cap = hi.material(ramp(mix(col, (25, 25, 32), 0.5)), bands=(-0.5, -0.05, 0.4, 0.85))
    helm = hi.material(ramp((120, 126, 138), cool=(0.18, 0.2, 0.4)))

    if p.prone:
        return _prone(hi, p, bot, jacket, jacket_d, skin, pants, boots, gear, cap, helm, col)

    hx, hy = p.hip
    # --- uziemienie: najniższa stopa dotyka podłoża (naturalne podskoki w biegu)
    def leg_joints(k):
        hip = (hx + (0.5 if k == 0 else -0.5), hy)
        knee = fk(hip, p.thigh[k], 3.9)
        ank = fk(knee, p.thigh[k] - p.flex[k], 3.6)
        return hip, knee, ank
    if p.ground:
        low = max(leg_joints(k)[2][1] for k in (0, 1)) + 1.35
        dy = GROUND - low
    else:
        dy = 0.0
    dy += p.bob
    hy += dy
    hx_, hy_ = hx, hy

    def L(k):
        hip = (hx_ + (0.5 if k == 0 else -0.5), hy_)
        knee = fk(hip, p.thigh[k], 3.9)
        ank = fk(knee, p.thigh[k] - p.flex[k], 3.6)
        return hip, knee, ank

    sh = up((hx_, hy_), p.lean, 6.4)
    tc = up((hx_, hy_), p.lean, 3.3)
    # --- tylna ręka (za tułowiem)
    sh_far = (sh[0] - 0.6, sh[1] + 0.5)
    el_far = fk(sh_far, p.arm_far[0], 2.9)
    ha_far = fk(el_far, p.arm_far[0] + p.arm_far[1], 2.7)
    hi.capsule(sh_far, el_far, 1.35, 1.15, jacket_d)
    hi.capsule(el_far, ha_far, 1.15, 0.95, jacket_d)
    hi.ellipse(ha_far, 1.0, 1.0, skin if not bot else metal)
    # --- tylna noga
    _leg(hi, 1, L, p, pants, boots, shade_dark=True)
    # --- plecak i antena
    pk = (tc[0] - 3.3, tc[1] - 0.2)
    hi.rbox(pk, 3.2, 6.2, gear, rot=math.radians(p.lean), curve=0.8)
    ant_base = (pk[0] - 0.4, pk[1] - 3.0)
    ant_tip = (ant_base[0] + p.ant - 0.8, ant_base[1] - 3.6)
    hi.capsule(ant_base, ant_tip, 0.5, 0.4, metal)
    # --- tułów (kurtka) + pas biodrowy
    hi.rbox(tc, 6.6, 7.4, jacket, rot=math.radians(p.lean), curve=0.85)
    hi.ellipse((hx_ + 0.1, hy_ - 0.2), 3.5, 1.9, jacket_d)               # biodra / dół kurtki
    hi.rbox(up((hx_, hy_), p.lean, 1.0), 6.8, 1.25, gear, rot=math.radians(p.lean), curve=0.4)   # pas
    # --- przednia noga
    _leg(hi, 0, L, p, pants, boots, shade_dark=False)
    # --- szyja / kołnierz
    hi.ellipse((sh[0] + 0.5, sh[1] - 0.6), 2.5, 1.5, jacket_d)
    # --- głowa
    hc = up(sh, p.lean + p.head, 3.55)
    hc = (hc[0] + 0.9, hc[1])
    if bot:
        hi.ellipse(hc, 3.3, 3.4, helm)
        hi.poly([(hc[0] + 0.2, hc[1] - 0.8), (hc[0] + 3.5, hc[1] - 0.6), (hi_x(hc, 3.3), hc[1] + 1.4), (hc[0] + 0.2, hc[1] + 1.6)], metal)
    else:
        hi.ellipse(hc, 3.1, 3.3, skin)
        hi.ellipse((hc[0] - 0.5, hc[1] - 2.0), 3.5, 1.95, cap)                 # czapka (tylko czubek głowy)
        hi.poly([(hc[0] + 1.8, hc[1] - 1.9), (hc[0] + 4.3, hc[1] - 1.3), (hc[0] + 4.0, hc[1] - 0.8), (hc[0] + 1.6, hc[1] - 1.0)], cap)  # daszek
    # --- przednia ręka z bronią (dłoń w (9, 12))
    el = (sh[0] + 0.6, sh[1] + 2.6)
    ha = (9.2, 12.3)
    hi.capsule((sh[0] + 0.2, sh[1] + 0.4), el, 1.4, 1.2, jacket)
    hi.capsule(el, ha, 1.2, 1.0, jacket)
    hi.ellipse(ha, 1.05, 1.0, skin if not bot else metal)
    # --- piersiowe kieszenie / pas na ramię
    hi.rbox((tc[0] + 1.6, tc[1] + 0.9), 2.4, 2.0, gear, rot=math.radians(p.lean), curve=0.5)

    fr = Frame.from_hi(hi)
    fr.despeckle()
    fr.outline()
    glow = Frame(FW, FH)
    # --- detale na siatce gry
    ex, ey = round(hc[0] + 1.1), round(hc[1] + (0.7 if not bot else 0.4))
    if bot:
        for dx in (0, 1):
            glow.put(ex + dx, ey, (70, 240, 255, 255))
            fr.put(ex + dx, ey, (40, 150, 190, 255))
    else:
        fr.put(ex, ey, EYE + (255,))
        fr.only_opaque_put(ex - 1, ey + 2, mix(SKIN, (90, 40, 40), 0.35) + (255,))   # usta/cień pod nosem
    return fr, glow


def hi_x(hc, r):
    return hc[0] + r - 0.2


def _leg(hi, k, L, p, pants, boots, shade_dark):
    hip, knee, ank = L(k)
    hi.capsule(hip, knee, 1.75, 1.45, pants)
    hi.capsule(knee, ank, 1.45, 1.2, pants)
    ang = p.thigh[k] - p.flex[k] + p.foot[k]
    toe = (ank[0] + 2.7 * math.cos(math.radians(ang)) * 1.0 + 0.0, ank[1] + 0.9 + 0.0 * ang)
    toe = (ank[0] + 2.4, ank[1] + 0.95 - 0.9 * math.sin(math.radians(ang)) * 0.6)
    if p.foot[k] < -6.0:
        toe = (ank[0] + 2.0, ank[1] + 0.2)
    heel = (ank[0] - 0.7, ank[1] + 0.35)
    hi.capsule(heel, toe, 1.35, 1.1, boots)
    hi.capsule((ank[0] - 0.2, ank[1] - 1.2), (ank[0] + 0.3, ank[1] + 0.2), 1.3, 1.3, boots)    # cholewka


def _prone(hi, p, bot, jacket, jacket_d, skin, pants, boots, gear, cap, helm, col):
    """Leży na boku, głowa w prawo (jak w starym sprite'cie), nogi w lewo."""
    gy = 21.6
    hip = (5.6, gy)
    sh = (10.6, gy - 0.4)
    # nogi
    hi.capsule(hip, (2.0, gy + 0.5), 1.5, 1.3, pants)
    hi.capsule((1.8, gy + 0.5), (0.2, gy + 0.2), 1.3, 1.2, pants)
    hi.capsule((0.6, gy + 0.2), (-0.2, gy + 0.2), 1.3, 1.1, boots)
    hi.capsule(hip, (3.2, gy - 1.6), 1.4, 1.2, pants)
    hi.capsule((3.2, gy - 1.6), (1.0, gy - 1.4), 1.2, 1.1, pants)
    hi.ellipse((0.7, gy - 1.4), 1.4, 1.1, boots)
    # plecak za plecami (pod tułowiem)
    hi.rbox((7.0, gy + 1.0), 3.4, 2.4, gear, curve=0.8)
    hi.rbox(((hip[0] + sh[0]) / 2, gy - 0.1), 7.2, 4.6, jacket, curve=0.85, bias=0.3)
    hi.ellipse((hip[0] + 0.4, gy), 2.2, 2.3, jacket_d)
    hi.capsule((8.0, gy - 1.9), (10.2, gy + 1.0), 1.2, 1.0, jacket_d)      # ręka pod ciałem
    hi.ellipse((10.6, gy + 1.1), 1.0, 0.9, skin)
    hc = (13.0, gy - 0.5)
    if bot:
        hi.ellipse(hc, 2.9, 2.9, helm)
    else:
        hi.ellipse(hc, 2.7, 2.8, skin)
        hi.ellipse((hc[0] - 0.9, hc[1] - 0.2), 2.5, 3.0, cap)
        hi.poly([(hc[0] + 0.2, hc[1] - 2.1), (hc[0] + 2.7, hc[1] - 1.6), (hc[0] + 2.4, hc[1] - 1.1), (hc[0] + 0.2, hc[1] - 1.2)], cap)
    fr = Frame.from_hi(hi)
    fr.despeckle()
    fr.outline()
    glow = Frame(FW, FH)
    ex, ey = round(hc[0] + 1.2), round(hc[1] + 0.4)
    if bot:
        fr.put(ex, ey, (40, 150, 190, 255))
        glow.put(ex, ey, (70, 240, 255, 150))
    else:
        fr.put(ex, ey, (34, 26, 38, 255))
    # kałuża krwi pod ciałem
    blood = (120, 12, 20, 255)
    blood_d = (84, 8, 16, 255)
    for x in range(3, 13):
        fr.put(x, 23, blood_d if x % 3 else blood)
    fr.put(1, 23, blood)
    fr.put(14, 23, blood_d)
    return fr, glow


def frames_for(col, bot=False):
    """→ (ciało, glow): listy klatek na animację, w kolejności PLAYER_ANIMS."""
    body, glow = [], []
    for an, n, _fps, _loop in PLAYER_ANIMS:
        b, g = [], []
        for i in range(n):
            fr, gl = build(col, bot, an, i)
            b.append(fr)
            g.append(gl)
        body.append(b)
        glow.append(g)
    return body, glow
