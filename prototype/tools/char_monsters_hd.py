"""Potwory w wyższej jakości (1.7.16): większe klatki (≈1,5×), więcej brył i detali niż w char_monsters.py,
ten sam silnik (char_art: render 4×, rampy, obrys) i te same nazwy animacji — wymiana arkuszy nie wymaga zmian w grze
poza rozmiarem klatki. Wszystkie patrzą w prawo, stopy przy dolnej krawędzi; oczy i żar → warstwa `glow`.
"""
import math
import random
from char_art import Hi, Frame, ramp, mix, fk, up
from char_monsters import _finish, _glow_px, _flip_v, EYE, EYE_HOT, EYE_SLEEP, monster_frames

BONE_BANDS = (0.0, 0.3, 0.6, 0.88)
DENSITY = 2                        # pikseli arkusza na piksel świata; gra rysuje te arkusze w skali 1/DENSITY (manifest „scale")
D = DENSITY


class Sc(Hi):
    """Hi z przeskalowaniem geometrii (projektujemy w wygodnych liczbach, a rysujemy mniejsze): punkt p → p·sc + (ox, oy)."""

    def __init__(self, w, h, sc=1.0, ox=0.0, oy=0.0):
        super().__init__(w, h)
        self.sc, self.ox, self.oy = sc, ox, oy

    def _t(self, p):
        return (p[0] * self.sc + self.ox, p[1] * self.sc + self.oy)

    def capsule(self, a, b, ra, rb, m, **kw):
        super().capsule(self._t(a), self._t(b), ra * self.sc, rb * self.sc, m, **kw)

    def ellipse(self, c, rx, ry, m, rot=0.0, **kw):
        super().ellipse(self._t(c), rx * self.sc, ry * self.sc, m, rot=rot, **kw)

    def rbox(self, c, w, h, m, rot=0.0, curve=0.7, **kw):
        super().rbox(self._t(c), w * self.sc, h * self.sc, m, rot=rot, curve=curve, **kw)

    def poly(self, pts, m, normal=(0.0, -0.25, 0.97), **kw):
        super().poly([self._t(p) for p in pts], m, normal=normal, **kw)

def _sc(w, h, sc=1.0, ox=0.0, oy=0.0):
    """Rysownik klatki o rozmiarze świata (w, h), gęstość D: współrzędne projektu zostają w pikselach świata."""
    return Sc(w * D, h * D, sc * D, ox * D, oy * D)


def _finish2(hi, k=0.34):
    """Obrys 2 px arkusza = 1 px świata (jak u reszty sprite'ów przy gęstości 1×)."""
    fr = _finish(hi, k)
    fr.outline(k)
    return fr


def _blk(glow, x, y, col, a=255, w=1):
    """Świecący punkt w×1 pikseli ŚWIATA (w·D × D pikseli arkusza), lewy górny róg w (x, y) arkusza."""
    x0, y0 = int(round(x)), int(round(y))
    for yy in range(D):
        for xx in range(w * D):
            glow.put(x0 + xx, y0 + yy, (*col, a))


def _eye(glow, hi, p, offs, col, a=255):
    """Punkty świecące: p = punkt w układzie projektu, offs = przesunięcia w pikselach ŚWIATA."""
    ax, ay = hi._t(p)
    for dx, dy in offs:
        _blk(glow, ax + dx * D, ay + dy * D, col, a)


def _speckle(hi, mat_d, mat_l, c, rx, ry, n, seed, r=0.5):
    """Drobne pory / guzki w elipsie: wzór stały (seed), więc taki sam w każdej klatce; widoczny dopiero przy gęstszej siatce."""
    rnd = random.Random(seed)
    for _ in range(n):
        a = rnd.uniform(0, math.tau)
        d_ = math.sqrt(rnd.uniform(0.0, 1.0))
        x, y = c[0] + math.cos(a) * rx * d_, c[1] + math.sin(a) * ry * d_
        hi.ellipse((x, y), r, r * 0.78, mat_d)
        hi.ellipse((x - r * 0.35, y - r * 0.35), r * 0.4, r * 0.3, mat_l)


# ================================================================ TRZOSEK (wataha, szybki)

TRZOSEK_HD = (24, 22)
TRZOSEK_ANIMS = [("idle", 4, 3, True), ("run", 6, 12, True), ("windup", 1, 1, False), ("sleep", 4, 1.5, True)]


def trzosek(an, i):
    W, H = TRZOSEK_HD
    hi = _sc(W, H)
    hide = hi.material(ramp((156, 54, 58), cool=(0.22, 0.08, 0.2)))
    hide_l = hi.material(ramp((184, 74, 70), cool=(0.22, 0.08, 0.2)))
    hide_d = hi.material(ramp((98, 34, 46), cool=(0.2, 0.08, 0.22)))
    bone = hi.material(ramp((220, 206, 172), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    flesh = hi.material(ramp((200, 98, 98), cool=(0.3, 0.1, 0.2)))
    spine = hi.material(ramp((176, 160, 130), cool=(0.3, 0.2, 0.3)), bands=(0.05, 0.35, 0.65, 0.9))
    maw = hi.material(ramp((70, 14, 28), cool=(0.1, 0.05, 0.2)))
    sleep, wind = an == "sleep", an == "windup"
    n = {"idle": 4, "run": 6, "sleep": 4}.get(an, 1)
    t = i / n * math.tau
    ground = H - 0.4
    breath = 0.5 * math.sin(t) if an in ("idle", "sleep") else 0.0
    bob = (-1.3 * abs(math.sin(t)) + 0.5) if an == "run" else 0.0
    pitch = 0.12 * math.sin(2 * t) if an == "run" else (0.18 if wind else 0.0)
    low = 5.0 if sleep else (2.2 if wind else 0.0)
    by = 12.2 + low + bob - breath * 0.6                     # środek tułowia
    # --- ogon: długi, bat
    tw = (1.4 * math.sin(t) if an in ("idle", "run") else 0.3)
    tip = (1.0 - tw * 0.2, by + 4.6 + tw) if not sleep else (2.2, by + 3.2)
    hi.capsule((4.0, by + 0.2), (2.4, by + 2.4 + tw * 0.4), 1.4, 0.8, hide_d)
    hi.capsule((2.4, by + 2.4 + tw * 0.4), tip, 0.8, 0.35, hide_d)

    def leg(sx, sy, a1, a2, hind, dark):
        """Noga dwuczłonowa; tylna ma wyraźne podudzie (kolano do tyłu), przednia prostsza. Stopa = trzy palce."""
        up_len, lo_len = (3.8, 4.2) if hind else (3.4, 4.0)
        k = fk((sx, sy), a1, up_len)
        p = fk(k, a1 - a2 if hind else a1 - a2 * 0.55, lo_len)
        p = (p[0], min(p[1], ground - 0.5)) if not sleep else p
        m = hide_d if dark else hide
        hi.capsule((sx, sy), k, 1.9 if hind else 1.5, 1.2, m)
        hi.capsule(k, p, 1.2, 0.8, m)
        hi.ellipse((p[0] + 0.7, min(p[1] + 0.1, ground - 0.5)), 1.7, 0.85, m)
        for d in (0.6, 1.5, 2.3):
            hi.capsule((p[0] + d, p[1] + 0.2), (p[0] + d + 0.8, min(p[1] + 0.7, ground)), 0.3, 0.15, bone)

    if not sleep:
        if an == "run":
            ph = [t, t + math.pi, t + math.pi * 0.55, t + math.pi * 1.55]
            a = [52 * math.sin(p) for p in ph]
            fl = [20 + 44 * max(0, math.cos(p)) for p in ph]
        elif wind:
            a = [10, -4, -14, 12]
            fl = [8, 8, 28, 28]
        else:
            a = [6, -5, -12, 8]
            fl = [8, 8, 26, 26]
        hips = ((14.2, by + 2.2), (13.2, by + 2.4), (6.2, by + 2.2), (5.0, by + 2.4))
        for k, (sx, sy) in enumerate(hips):
            hind = k >= 2
            if wind and k == 0:
                continue
            leg(sx, sy, a[k], fl[k], hind, dark=(k % 2 == 1))
        if wind:                                              # przednia łapa uniesiona do ciosu, pazury rozcapierzone
            e = fk((14.6, by + 1.6), 105, 3.6)
            p = fk(e, 165, 3.4)
            hi.capsule((14.6, by + 1.6), e, 1.7, 1.3, hide)
            hi.capsule(e, p, 1.3, 0.8, hide)
            for d in (-1.3, -0.4, 0.5, 1.3):
                hi.capsule(p, (p[0] + 1.3, p[1] + d * 1.1 - 0.8), 0.4, 0.18, bone)
    else:
        hi.ellipse((14.0, ground - 1.4), 4.4, 1.6, hide_d)    # podkulone łapy pod głową
        hi.ellipse((7.0, ground - 1.6), 3.8, 1.7, hide_d)
    # --- tułów: klatka piersiowa, biodro, brzuch, garb
    hi.ellipse((9.6, by + 0.3), 5.4, 2.6, hide, rot=pitch)                 # talia
    hi.ellipse((6.2, by - 1.0), 4.4, 3.6, hide_l, rot=pitch)               # udo / zad
    hi.ellipse((12.8, by - 0.5), 4.4, 3.8, hide, rot=pitch)                # klatka piersiowa / barki
    hi.ellipse((9.6, by + 2.3), 4.2, 1.3, hide_d)                          # podkasany brzuch
    for rb in range(4):                                                    # żebra rysujące się pod skórą
        x = 9.2 + rb * 1.6
        hi.capsule((x, by - 0.5), (x + 0.7, by + 2.3), 0.32, 0.26, spine)
    # --- grzbiet: rząd kolców
    for k in range(6):
        x = 5.4 + k * 1.75
        top = by - 3.6 - 0.7 * math.sin(k * 0.9 + 0.6) + (0.4 if k % 2 else 0.0)
        hi.poly([(x - 0.8, top + 1.6), (x + 0.15, top - 1.6 - (0.7 if k in (2, 3) else 0.0)), (x + 1.0, top + 1.7)], spine, normal=(0.25, -0.5, 0.8))
    # --- szyja i głowa
    jaw_open = 3.0 if wind else (0.0 if sleep else 0.5 * (1 + math.sin(t)) if an == "idle" else 0.9)
    hx, hy = (17.4, by - 1.2 + (0.4 if an == "run" else 0.0))
    if sleep:
        hx, hy = 17.0, by + 1.2
    elif wind:
        hx, hy = 18.0, by - 0.4
    hi.capsule((13.6, by - 1.0), (hx - 1.0, hy), 2.8, 2.2, hide)           # szyja
    hi.ellipse((hx, hy), 3.2, 2.7, hide_l)                                 # czaszka
    hi.capsule((hx + 1.2, hy - 0.2), (hx + 4.8, hy + 0.9), 2.0, 1.2, hide)  # pysk
    # dolna szczęka
    jy = hy + 1.9 + jaw_open
    hi.capsule((hx + 0.2, hy + 1.6), (hx + 4.6, jy), 1.0, 0.55, hide_d)
    if not sleep:
        if jaw_open > 0.6:                                                # wnętrze paszczy
            hi.ellipse((hx + 3.2, hy + 1.6 + jaw_open * 0.5), 1.9, 0.5 + jaw_open * 0.35, maw)
        for dx in (1.0, 3.2):                                             # kły górne
            hi.poly([(hx + 1.2 + dx, hy + 1.6), (hx + 1.8 + dx, hy + 1.6), (hx + 1.5 + dx, hy + 2.9 + jaw_open * 0.3)], bone)
        for dx in (2.0, 3.8):                                             # kły dolne
            hi.poly([(hx + 1.0 + dx, jy - 0.3), (hx + 1.5 + dx, jy - 0.3), (hx + 1.25 + dx, jy - 1.6)], bone)
    # ucho: poszarpane, odchylone do tyłu
    hi.poly([(hx - 1.8, hy - 2.0), (hx - 4.4, hy - 4.8), (hx - 0.8, hy - 3.0)], hide_d, normal=(-0.3, -0.5, 0.8))
    hi.poly([(hx - 0.6, hy - 2.4), (hx - 2.2, hy - 5.6), (hx + 0.6, hy - 2.6)], hide, normal=(-0.2, -0.6, 0.78))
    # blizna na boku i sierść: drobne kępki (wzór stały)
    hi.capsule((8.4, by + 0.2), (11.0, by - 1.6), 0.35, 0.3, flesh)
    _speckle(hi, hide_d, hide_l, (9.4, by), 4.6, 2.2, 13, 3, 0.4)
    fr = _finish2(hi)
    glow = Frame(W * D, H * D)
    col = EYE_HOT if wind else (EYE_SLEEP if sleep else EYE)
    p_eye = (hx + 1.6, hy - 0.9)
    if sleep:
        _eye(glow, hi, p_eye, [(0, 0.5)], col, 150)
    else:
        _eye(glow, hi, p_eye, [(0, 0), (1.0, 0.1), (2.0, 0.2)], col)
        if wind:
            _eye(glow, hi, (hx + 3.0, hy + 2.6), [(0, 0)], (255, 110, 70), 200)    # żar w paszczy
            _eye(glow, hi, (hx + 2.0, hy + 2.8), [(0, 0)], (255, 110, 70), 200)
    return fr, glow


# ================================================================ WOŁEK (bruiser)

WOLEK_HD = (44, 44)
WOLEK_ANIMS = [("idle", 4, 2, True), ("walk", 6, 7, True), ("windup", 1, 1, False), ("sleep", 4, 1.2, True)]


def wolek(an, i):
    W, H = WOLEK_HD
    hi = _sc(W, H, 0.78, 1.8, 9.6)
    hide = hi.material(ramp((134, 96, 110), cool=(0.2, 0.1, 0.28)))
    hide_l = hi.material(ramp((160, 114, 124), cool=(0.2, 0.1, 0.28)))
    hide_d = hi.material(ramp((74, 52, 68), cool=(0.15, 0.08, 0.3)))
    horn = hi.material(ramp((228, 214, 174), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    plate = hi.material(ramp((150, 138, 120), cool=(0.22, 0.16, 0.34)), bands=(-0.05, 0.25, 0.55, 0.85))
    scar = hi.material(ramp((176, 74, 84), cool=(0.3, 0.1, 0.2)))
    sleep, wind = an == "sleep", an == "windup"
    if sleep:
        hi.oy = 4.0 * D
    n = {"idle": 4, "walk": 6, "sleep": 4}.get(an, 1)
    t = i / n * math.tau
    breath = 0.7 * math.sin(t) if an in ("idle", "sleep") else 0.0
    ground = H - 0.4
    lean = 24.0
    if sleep:
        lean = 62.0
    elif wind:
        lean = -8.0
    hx = 21.0
    hy = 27.0 - breath * 0.4 if not sleep else 31.0

    def leg(k):
        near = k == 0
        hip = (hx + (3.2 if near else -3.0), hy + 2.0)
        if sleep:
            kn = (hip[0] + 8.0, ground - 6.0)
            ft = (kn[0] + 4.0, ground - 1.6)
        else:
            a = 0.0
            fl = 14.0
            if an == "walk":
                ph = t + (0 if near else math.pi)
                a = 26 * math.sin(ph)
                fl = 12 + 36 * max(0, math.cos(ph))
            kn = fk(hip, a, 7.4)
            ft = fk(kn, a - fl, 7.0)
            ft = (ft[0], min(ft[1], ground - 1.2))
        m = hide if near else hide_d
        hi.capsule(hip, kn, 5.7, 4.7, hide_d)
        hi.capsule(kn, ft, 4.7, 3.9, hide_d)
        hi.capsule(hip, kn, 5.0, 4.0, m)
        hi.capsule(kn, ft, 4.0, 3.2, m)
        hi.ellipse((ft[0] + 1.6, ft[1] + 1.0), 4.2, 2.1, m)                  # stopa
        for d in (1.2, 3.0, 4.8):
            hi.poly([(ft[0] + d, ft[1] + 1.4), (ft[0] + d + 1.6, ft[1] + 1.7), (ft[0] + d, ft[1] + 2.4)], horn)   # pazury
    # stopy dotykają ziemi: skoryguj wysokość bioder
    if not sleep:
        lows = []
        for k in (0, 1):
            pass
    sh = up((hx, hy), lean, 14.0)
    tc = up((hx, hy), lean, 7.0)

    def arm(k):
        near = k == 0
        shoulder = (sh[0] + (1.0 if near else -2.4), sh[1] + (2.6 if near else 1.6))
        if wind:
            el = (shoulder[0] + (5.0 if near else 1.0), shoulder[1] - 8.0)
            fi = (el[0] + (3.4 if near else 1.0), el[1] - 7.6)
        elif sleep:
            el = (shoulder[0] + 3.2, shoulder[1] + 7.0)
            fi = (el[0] + 5.2, el[1] + 3.4)
        else:
            sw = 0.0
            if an == "walk":
                sw = 18 * math.sin(t + (math.pi if near else 0))
            el = fk(shoulder, 14 + sw, 10.4)
            fi = fk(el, 6 + sw * 1.4, 10.0)
        m = hide_l if near else hide_d
        if near:
            hi.capsule(shoulder, el, 5.8, 5.0, hide_d)
            hi.capsule(el, fi, 5.0, 4.7, hide_d)
        hi.capsule(shoulder, el, 5.0, 4.3, m)
        hi.capsule(el, fi, 4.3, 4.0, m)
        hi.ellipse((fi[0] + 0.4, fi[1] + 1.8), 5.2, 4.8, m)                  # maczuga pięści
        for d in (-2.4, 0.0, 2.4):                                           # kolce na kostkach
            hi.poly([(fi[0] + d - 0.9, fi[1] + 4.2), (fi[0] + d + 0.1, fi[1] + 7.0), (fi[0] + d + 1.0, fi[1] + 4.2)], horn) if not wind else None
        hi.poly([(el[0] - 1.2, el[1] - 4.4), (el[0] + 0.8, el[1] - 8.0), (el[0] + 2.4, el[1] - 4.0)], horn)    # kolec łokcia
        hi.capsule((fi[0] - 1.6, fi[1] + 0.4), (fi[0] + 1.8, fi[1] + 3.2), 0.5, 0.5, scar)

    leg(1)
    arm(1)
    # --- tułów: klatka + garb + brzuch
    hi.ellipse(tc, 12.2, 10.4, hide, rot=math.radians(lean * 0.5))
    hi.ellipse((hx + 0.8, hy + 1.8), 8.6, 6.6, hide_d)                       # biodra
    hi.ellipse((tc[0] - 6.2, tc[1] - 5.0), 7.2, 5.4, hide)                   # garb
    hi.ellipse((tc[0] + 1.8, tc[1] + 4.6), 8.0, 5.4, hide_l, bias=-0.1)      # wypchnięty brzuch
    # płyty kostne na grzbiecie
    for k, (dx, dy, rr) in enumerate(((-10.0, -5.0, 3.6), (-7.4, -9.4, 4.0), (-2.6, -11.6, 3.8))):
        px, py = sh[0] + dx, sh[1] + dy + 4.2
        hi.ellipse((px, py), rr * 1.5, rr, plate, rot=math.radians(-30 + 28 * k))
        hi.poly([(px - 1.2, py - rr * 0.6), (px + 0.2, py - rr - 3.6), (px + 1.8, py - rr * 0.6)], horn, normal=(0.2, -0.6, 0.75))
    _speckle(hi, hide_d, hide_l, tc, 10.0, 8.6, 28, 5, 0.85)          # pory i guzki skóry
    # blizny: szwy na piersi i brzuchu
    for dx in (-2.6, -0.4, 1.8, 4.0):
        hi.capsule((tc[0] + dx, tc[1] + 0.4), (tc[0] + dx + 1.4, tc[1] + 5.0), 0.5, 0.45, scar)
    hi.capsule((tc[0] - 4.0, tc[1] + 2.4), (tc[0] + 5.6, tc[1] + 2.6), 0.4, 0.4, scar)
    leg(0)
    # --- głowa: mała, nisko, wysunięta; długie rogi i kły
    hc = (sh[0] + 9.6, sh[1] + (4.4 if not sleep else 2.0))
    hi.ellipse(hc, 6.2, 5.4, hide_l)
    hi.capsule((hc[0] + 1.8, hc[1] + 2.4), (hc[0] + 7.0, hc[1] + 3.8), 3.0, 2.2, hide)       # pysk
    hi.capsule((hc[0] + 2.0, hc[1] + 4.2), (hc[0] + 7.0, hc[1] + 5.0), 1.5, 1.0, hide_d)      # żuchwa
    for dx in (3.0, 6.0):                                                                      # kły wystające w górę
        hi.poly([(hc[0] + dx, hc[1] + 4.4), (hc[0] + dx + 1.2, hc[1] + 4.4), (hc[0] + dx + 0.6, hc[1] + 0.6)], horn)
    for hs, (sx, sy, ex2, ey2) in enumerate(((-3.0, -4.0, -9.0, -12.0), (2.4, -4.6, 6.0, -13.0))):   # dwa rogi
        mx, my = hc[0] + (sx + ex2) / 2 + (-2.0 if hs == 0 else 2.0), hc[1] + (sy + ey2) / 2
        hi.capsule((hc[0] + sx, hc[1] + sy), (mx, my), 2.0, 1.5, horn)
        hi.capsule((mx, my), (hc[0] + ex2, hc[1] + ey2), 1.5, 0.4, horn)
    arm(0)
    fr = _finish2(hi)
    glow = Frame(W * D, H * D)
    col = EYE_HOT if wind else (EYE_SLEEP if sleep else EYE)
    p_eye = (hc[0] + 3.6, hc[1] - 0.8)
    if sleep:
        _eye(glow, hi, p_eye, [(0, 0.6)], col, 140)
    else:
        _eye(glow, hi, p_eye, [(0, 0), (1.0, 0), (2.0, 0.2)], col)
    return fr, glow


# ================================================================ STALKER „ON" (nieśmiertelny)

STALKER_HD = (32, 60)
STALKER_ANIMS = [("idle", 6, 4, True), ("walk", 8, 9, True), ("windup", 1, 1, False)]


def stalker(an, i):
    """Wysoka, wychudzona sylwetka bez twarzy w podartym płaszczu z kapturem; ramiona do kolan, długie palce."""
    W, H = STALKER_HD
    hi = _sc(W, H, 0.96, 1.0, 2.0)
    cloth = hi.material(ramp((58, 56, 76), cool=(0.14, 0.12, 0.34)))
    cloth_l = hi.material(ramp((84, 82, 106), cool=(0.14, 0.12, 0.34)))
    cloth_d = hi.material(ramp((30, 30, 44), cool=(0.1, 0.08, 0.3)))
    skin = hi.material(ramp((150, 144, 160), cool=(0.2, 0.16, 0.36)))
    skin_d = hi.material(ramp((98, 94, 112), cool=(0.18, 0.14, 0.34)))
    void = hi.material(ramp((8, 6, 14), cool=(0.05, 0.04, 0.2)), bands=(0.3, 0.6, 0.85, 0.95))
    n = {"idle": 6, "walk": 8}.get(an, 1)
    t = i / n * math.tau
    wind = an == "windup"
    ground = H - 0.5
    sway = 0.9 * math.sin(t) if an == "idle" else 0.0
    step = math.sin(t) if an == "walk" else 0.0
    bob = -0.8 * abs(math.sin(t)) if an == "walk" else 0.0
    cx = 14.0 + sway * 0.6
    hipy = 31.0 + bob
    lean = (4.0 + 3.0 * math.sin(t)) if an == "idle" else (9.0 if an == "walk" else -6.0)
    sh = up((cx, hipy), lean, 17.0)
    head = up(sh, lean * 1.4 + 6.0, 6.2)
    # --- nogi: długie, cienkie, widoczne spod postrzępionego płaszcza
    for k in (1, 0):
        a = 22.0 * step * (1 if k == 0 else -1)
        hip = (cx + (0.8 if k == 0 else -0.8), hipy + 1.0)
        kn = fk(hip, a, 10.6)
        ft = fk(kn, a - (14 + 16 * max(0.0, -step if k == 0 else step)), 10.6)
        ft = (ft[0], min(ft[1], ground - 0.8))
        m = skin if k == 0 else skin_d
        hi.capsule(hip, kn, 1.7, 1.3, m)
        hi.capsule(kn, ft, 1.3, 0.95, m)
        hi.capsule((ft[0] - 1.0, ft[1] + 0.3), (ft[0] + 3.4, ft[1] + 0.6), 0.9, 0.6, m)   # długa stopa
    # --- płaszcz: wąski stożek postrzępiony na dole, falujący w ruchu
    sway2 = 1.4 * math.sin(t + 1.0) if an != "windup" else 0.0
    top_l = (sh[0] - 5.2, sh[1] + 1.0)
    top_r = (sh[0] + 5.2, sh[1] + 1.0)
    hem_y = ground - 12.0
    hi.poly([top_l, top_r, (cx + 6.4 + sway2, hem_y), (cx + 3.0, hem_y + 3.4), (cx + 0.6 + sway2 * 0.5, hem_y + 1.0),
             (cx - 2.2, hem_y + 4.6), (cx - 4.4 + sway2, hem_y + 0.6), (cx - 6.8, hem_y + 3.0)], cloth, normal=(0.0, -0.1, 0.99))
    hi.ellipse((sh[0] + 0.4, sh[1] + 4.4), 5.2, 6.0, cloth_l)                              # tors w świetle
    hi.ellipse((sh[0] - 3.0, sh[1] + 12.0), 3.4, 10.0, cloth_d, rot=math.radians(4))       # fałda cienia
    for fx in (-3.6, 1.0, 4.2):                                                            # postrzępione końce
        hi.capsule((cx + fx, hem_y + 2.0), (cx + fx + sway2 * 0.5, hem_y + 6.6 + 1.4 * math.sin(t + fx)), 0.9, 0.2, cloth_d)
    # --- ramiona: za długie, wiszą do kolan; w windup uniesione do przodu z rozcapierzonymi palcami
    for k in (1, 0):
        near = k == 0
        shoulder = (sh[0] + (2.0 if near else -2.4), sh[1] + 1.6)
        if wind:
            el = (shoulder[0] + (7.0 if near else 4.0), shoulder[1] + 3.0 - (2.0 if near else 0.0))
            fi = (el[0] + (7.0 if near else 5.0), el[1] - (3.0 if near else 1.0))
        else:
            sw = 12.0 * math.sin(t + (math.pi if near else 0.0)) if an == "walk" else 3.0 * math.sin(t + (1.0 if near else 0.0))
            el = fk(shoulder, 6 + sw, 10.4)
            fi = fk(el, 3 + sw * 1.2, 11.0)
        m = skin if near else skin_d
        sleeve = cloth_l if near else cloth
        hi.capsule(shoulder, el, 1.9, 1.5, sleeve)
        hi.capsule(el, fi, 1.5, 1.0, m)
        for d in range(4):                                                                  # cztery długie palce
            ang = math.radians(70 + d * 9 - (50 if wind else 0))
            hi.capsule(fi, (fi[0] + math.sin(ang) * 4.4 * (1 if wind else 0.8), fi[1] + math.cos(ang) * 4.4 * (1 if wind else 0.9)), 0.45, 0.2, m)
    # --- kaptur i głowa: czarna pustka z dwojgiem oczu
    hi.ellipse((head[0] - 0.8, head[1] + 0.6), 5.4, 6.8, cloth, rot=math.radians(lean * 0.4))
    hi.poly([(head[0] - 5.0, head[1] + 6.0), (head[0] - 0.8, head[1] - 9.6), (head[0] + 4.6, head[1] + 5.2)], cloth, normal=(-0.1, -0.3, 0.9))    # szpic kaptura
    hi.ellipse((head[0] + 1.4, head[1] + 0.8), 3.4, 4.6, void)                              # wnętrze kaptura
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    ecol = (255, 40, 30) if wind else (255, 70, 50)
    p_eye = (head[0] + 1.6, head[1] - 0.2)
    _eye(glow, hi, p_eye, [(0, 0), (1, 0), (3, 0), (4, 0)], ecol, 255)
    if wind:
        _eye(glow, hi, p_eye, [(0, 1), (1, 1), (3, 1), (4, 1)], ecol, 200)
    return fr, glow


# ================================================================ ŚLEPIEC (nie widzi — słyszy)

SLEPIEC_HD = (26, 32)
SLEPIEC_ANIMS = [("idle", 4, 3, True), ("walk", 6, 8, True), ("windup", 1, 1, False), ("sleep", 4, 1.5, True)]


def slepiec(an, i):
    """Blada, zgarbiona istota z zaszytymi oczodołami, ogromnymi nasłuchującymi uszami i zębatą szczeliną na twarzy."""
    W, H = SLEPIEC_HD
    hi = _sc(W, H, 1.0, 0.0, 0.0)
    skin = hi.material(ramp((206, 200, 196), warm=(1.0, 0.95, 0.9), cool=(0.3, 0.26, 0.42)))
    skin_d = hi.material(ramp((146, 140, 142), cool=(0.26, 0.22, 0.4)))
    skin_l = hi.material(ramp((226, 222, 216), warm=(1.0, 0.96, 0.9), cool=(0.3, 0.26, 0.42)))
    ear = hi.material(ramp((196, 150, 150), cool=(0.3, 0.16, 0.3)))
    wound = hi.material(ramp((150, 54, 66), cool=(0.3, 0.1, 0.2)))
    bone = hi.material(ramp((232, 220, 186), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    mouth = hi.material(ramp((52, 10, 22), cool=(0.1, 0.05, 0.2)), bands=(0.3, 0.6, 0.85, 0.95))
    sleep, wind = an == "sleep", an == "windup"
    n = {"idle": 4, "walk": 6, "sleep": 4}.get(an, 1)
    t = i / n * math.tau
    breath = 0.5 * math.sin(t) if an in ("idle", "sleep") else 0.0
    ground = H - 0.4
    lean = 38.0
    if sleep:
        lean = 74.0
    elif wind:
        lean = 18.0
    hx = 11.0
    hy = 21.0 + (2.0 if sleep else 0.0) - breath * 0.4

    for k in (1, 0):
        near = k == 0
        hip = (hx + (1.6 if near else -1.4), hy + 1.0)
        if sleep:
            kn = (hip[0] + 4.4, ground - 3.0)
            ft = (kn[0] + 2.4, ground - 0.8)
        else:
            a = 14.0 * math.sin(t + (0 if near else math.pi)) if an == "walk" else (6.0 if near else -4.0)
            fl = (10 + 26 * max(0.0, math.cos(t + (0 if near else math.pi)))) if an == "walk" else 12.0
            kn = fk(hip, a, 5.4)
            ft = fk(kn, a - fl, 5.2)
            ft = (ft[0], min(ft[1], ground - 0.6))
        m = skin if near else skin_d
        hi.capsule(hip, kn, 2.0, 1.5, m)
        hi.capsule(kn, ft, 1.5, 1.1, m)
        hi.capsule((ft[0] - 0.6, ft[1] + 0.2), (ft[0] + 2.8, ft[1] + 0.4), 1.0, 0.7, m)
    sh = up((hx, hy), lean, 8.6)
    tc = up((hx, hy), lean, 4.4)
    # tors: wychudzony, żebra pod skórą, kręgosłup jak sznur
    hi.ellipse(tc, 4.6, 5.6, skin, rot=math.radians(lean * 0.5))
    hi.ellipse((hx + 0.2, hy + 0.8), 3.8, 3.0, skin_d)
    for rb in range(3):
        o = (tc[0] + 0.8, tc[1] - 1.4 + rb * 1.7)
        hi.capsule(o, (o[0] + 2.4, o[1] + 0.6), 0.28, 0.22, skin_d)
    for vk in range(5):                                                # guzki kręgosłupa na plecach
        p = up((hx, hy), lean, 2.4 + vk * 1.6)
        hi.ellipse((p[0] - 2.8, p[1] - 0.2), 0.8, 0.7, bone)
    # ramiona: długie, szponiaste, jedno wyciągnięte do przodu
    for k in (1, 0):
        near = k == 0
        shoulder = (sh[0] + (0.8 if near else -1.0), sh[1] + 1.4)
        if wind:
            el = (shoulder[0] + 4.6, shoulder[1] + 1.6)
            fi = (el[0] + (5.4 if near else 4.0), el[1] + (1.0 if near else -0.4))
        elif sleep:
            el = (shoulder[0] + 2.0, shoulder[1] + 4.0)
            fi = (el[0] + 3.2, el[1] + 2.0)
        else:
            sw = 12.0 * math.sin(t + (math.pi if near else 0.0)) if an == "walk" else 4.0 * math.sin(t + (1.0 if near else 0.0))
            el = fk(shoulder, 14 + sw, 6.2)
            fi = fk(el, 18 + sw * 1.2, 6.4)
        m = skin_l if near else skin_d
        hi.capsule(shoulder, el, 1.6, 1.2, m)
        hi.capsule(el, fi, 1.2, 0.8, m)
        for d in (-0.9, 0.0, 0.9):
            hi.capsule(fi, (fi[0] + 2.2, fi[1] + 1.6 + d), 0.32, 0.14, bone)
    # głowa: wydłużona, bez oczu; usta-szczelina z igłowatymi zębami; ogromne ucho
    hc = (sh[0] + 3.2, sh[1] + (1.0 if not sleep else 0.4))
    ex1 = (hc[0] - 3.4, hc[1] - 2.2)                                                              # ucho: za głową, sterczące
    hi.ellipse(ex1, 2.0, 5.6, ear, rot=math.radians(-30))
    hi.ellipse((ex1[0] - 0.3, ex1[1] - 0.4), 1.0, 3.6, wound, rot=math.radians(-30))
    hi.ellipse(hc, 3.7, 4.2, skin_l, rot=math.radians(14))
    jaw_open = 1.6 if wind else (0.5 + 0.4 * math.sin(t) if an == "idle" else 0.3)
    hi.ellipse((hc[0] + 1.4, hc[1] + 2.2 + jaw_open * 0.4), 2.2, 0.7 + jaw_open * 0.5, mouth)
    for dx in (0.2, 1.2, 2.2):
        hi.poly([(hc[0] + dx, hc[1] + 1.8), (hc[0] + dx + 0.7, hc[1] + 1.8), (hc[0] + dx + 0.35, hc[1] + 3.0 + jaw_open * 0.3)], bone)
    hi.capsule((hc[0] - 1.0, hc[1] - 1.6), (hc[0] + 2.6, hc[1] - 1.2), 0.6, 0.5, skin_d)         # brew
    hi.capsule((hc[0] + 0.6, hc[1] - 0.8), (hc[0] + 2.6, hc[1] - 0.6), 0.28, 0.28, wound)          # zaszyte oczodoły
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    # pod skórą tli się coś w oczodołach — słaby, bladoczerwony punkt (nie widzi, ale „patrzy")
    _eye(glow, hi, (hc[0] + 1.6, hc[1] - 0.7), [(0, 0)], (255, 90, 90), 120 if sleep else 190)
    return fr, glow


# ================================================================ PODSŁUCHACZ (nieruchomy, krzyczy)

PODSLUCHACZ_HD = (26, 40)
PODSLUCHACZ_ANIMS = [("idle", 4, 3, True), ("windup", 1, 1, False), ("sleep", 2, 1.5, True)]


def podsluchacz(an, i):
    """Wysoka, cienka postać na miejscu: ogromne, wachlarzowate uszy-czasze, brak oczu, wąska szyja; w windup głowa odrzucona i krzyk."""
    W, H = PODSLUCHACZ_HD
    hi = _sc(W, H, 1.0, 0.0, 0.0)
    skin = hi.material(ramp((150, 128, 146), cool=(0.24, 0.14, 0.34)))
    skin_l = hi.material(ramp((184, 156, 172), cool=(0.24, 0.14, 0.34)))
    skin_d = hi.material(ramp((96, 80, 98), cool=(0.2, 0.1, 0.34)))
    ear_o = hi.material(ramp((214, 150, 160), cool=(0.3, 0.14, 0.3)))
    ear_i = hi.material(ramp((120, 44, 62), cool=(0.25, 0.1, 0.25)))
    bone = hi.material(ramp((226, 212, 178), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    mouth = hi.material(ramp((50, 8, 22), cool=(0.1, 0.05, 0.2)), bands=(0.3, 0.6, 0.85, 0.95))
    sleep, wind = an == "sleep", an == "windup"
    t = i / {"idle": 4, "sleep": 2}.get(an, 1) * math.tau
    ground = H - 0.4
    sway = 0.7 * math.sin(t) if an == "idle" else 0.0
    cx = 12.0
    droop = 5.0 if sleep else 0.0
    # nogi: dwie cienkie szczudła-łydki
    for k in (1, 0):
        x = cx + (1.5 if k == 0 else -1.5)
        m = skin if k == 0 else skin_d
        hi.capsule((x, ground - 14.0), (x + 0.3, ground - 0.8), 1.6, 1.0, m)
        hi.capsule((x - 0.6, ground - 0.6), (x + 2.6, ground - 0.4), 0.9, 0.7, m)
    # tułów: wąski, długi, z żebrami; wiszące ramiona
    top = (cx + sway * 0.4, 14.0 + droop)
    hi.ellipse((cx, 22.0), 3.6, 8.4, skin)
    hi.ellipse((cx + 0.4, 17.0), 3.9, 4.6, skin_l)
    for rb in range(4):
        hi.capsule((cx - 1.0, 14.8 + droop * 0.2 + rb * 1.5), (cx + 2.4, 15.2 + droop * 0.2 + rb * 1.5), 0.28, 0.22, skin_d)
    for k in (1, 0):
        sx = cx + (2.2 if k == 0 else -2.2)
        m = skin_l if k == 0 else skin_d
        el = (sx + (2.0 if k == 0 else 0.4), 22.0 + (3.0 if wind else 0.0))
        fi = (el[0] + (1.4 if not wind else 3.4), el[1] + (8.0 if not wind else -3.0))
        if wind:
            fi = (el[0] + (4.6 if k == 0 else 3.0), el[1] - 1.6)
        hi.capsule((sx, 15.6 + droop * 0.3), el, 1.3, 1.0, m)
        hi.capsule(el, fi, 1.0, 0.7, m)
        for d in (-0.6, 0.0, 0.6):
            hi.capsule(fi, (fi[0] + 1.6, fi[1] + 2.2 + d), 0.26, 0.12, bone)
    # szyja i głowa; dwa wielkie, sterczące uszy w „V" (za głową), pusta twarz i wiecznie otwarta szczelina ust
    hc = (top[0] + (2.0 if wind else 0.6), 12.4 + droop - (0.6 if wind else 0.0))
    hi.capsule((top[0], top[1] + 1.0), hc, 1.8, 1.7, skin)
    fl = 2.4 if wind else 0.0                                                     # w krzyku uszy odchylają się na boki
    hi.poly([(hc[0] - 2.8, hc[1] - 1.6), (hc[0] - 5.0 - fl, hc[1] - 12.0), (hc[0] + 0.2, hc[1] - 3.2)], ear_o, normal=(-0.3, -0.4, 0.85))
    hi.poly([(hc[0] - 2.2, hc[1] - 2.4), (hc[0] - 4.2 - fl * 0.8, hc[1] - 9.6), (hc[0] - 0.4, hc[1] - 3.2)], ear_i, normal=(-0.3, -0.4, 0.85))
    hi.poly([(hc[0] + 0.2, hc[1] - 3.0), (hc[0] + 3.4 + fl, hc[1] - 11.2), (hc[0] + 3.6, hc[1] - 1.2)], ear_o, normal=(0.2, -0.4, 0.85))
    hi.poly([(hc[0] + 0.8, hc[1] - 3.2), (hc[0] + 3.0 + fl * 0.8, hc[1] - 8.8), (hc[0] + 3.0, hc[1] - 1.8)], ear_i, normal=(0.2, -0.4, 0.85))
    hi.ellipse(hc, 4.0, 4.4, skin_l, rot=math.radians(-8 if wind else 4))
    open_m = 2.8 if wind else (1.2 + 0.5 * math.sin(t) if an == "idle" else 0.5)
    hi.ellipse((hc[0] + 1.6, hc[1] + 1.8), 2.0, 0.7 + open_m * 0.55, mouth)
    for dx in (0.2, 1.4, 2.6):
        hi.poly([(hc[0] + dx, hc[1] + 0.9), (hc[0] + dx + 0.6, hc[1] + 0.9), (hc[0] + dx + 0.3, hc[1] + 2.4)], bone)
    for e in range(2):                                                            # zmarszczki nad ustami — w miejscu oczu gładka skóra
        hi.capsule((hc[0] - 0.4 + e * 1.8, hc[1] - 1.4), (hc[0] + 0.2 + e * 1.8, hc[1] + 0.2), 0.2, 0.18, skin_d)
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    # brak oczu: tylko blady żar w gardle przy krzyku
    if wind:
        _eye(glow, hi, (hc[0] + 1.6, hc[1] + 2.2), [(0, 0)], (255, 100, 90), 210)
        _eye(glow, hi, (hc[0] + 2.6, hc[1] + 2.2), [(0, 0)], (255, 100, 90), 170)
    return fr, glow


# ================================================================ CMA (światłolubna ćma)

CMA_HD = (26, 20)
CMA_ANIMS = [("idle", 4, 14, True), ("sleep", 1, 1, False)]


def cma(an, i):
    """Duża ćma: puszyste ciało, pierzaste czułki, skrzydła z „oczami"; w locie trzepocze, śpiąc wisi złożona (odbita w pionie)."""
    W, H = CMA_HD
    hi = _sc(W, H, 1.0, 0.0, 0.0)
    wing = hi.material(ramp((206, 196, 160), warm=(1.0, 0.95, 0.8), cool=(0.3, 0.25, 0.4)))
    wing_d = hi.material(ramp((148, 136, 108), cool=(0.25, 0.2, 0.4)))
    wing_f = hi.material(ramp((110, 96, 82), cool=(0.22, 0.18, 0.38)))
    fur = hi.material(ramp((150, 128, 104), cool=(0.2, 0.16, 0.34)))
    spot = hi.material(ramp((240, 170, 90), cool=(0.3, 0.2, 0.3)))
    pupil = hi.material(ramp((50, 30, 40), cool=(0.1, 0.08, 0.2)))
    sleep = an == "sleep"
    lift = [1.0, 0.35, -0.5, 0.35][i % 4] if not sleep else -0.9
    cx, cy = 12.0, 14.6
    # dalekie skrzydło (ciemniejsze) — w górę i w tył
    hi.ellipse((cx - 2.0, cy - 1.8 - 3.4 * lift), 3.0, 5.2, wing_d, rot=math.radians(-20 - 24 * lift))
    # ciało: odwłok, tułów, głowa
    hi.ellipse((cx - 2.6, cy + 1.6), 4.2, 2.2, fur)
    hi.ellipse((cx + 1.4, cy + 0.6), 3.0, 2.8, fur)
    hi.ellipse((cx + 4.6, cy + 0.2), 2.0, 1.9, fur)
    for k in range(3):
        hi.capsule((cx - 5.0 + k * 1.6, cy + 1.0), (cx - 4.6 + k * 1.6, cy + 3.2), 0.3, 0.25, wing_f)          # pręgi odwłoka
    # czułki pierzaste
    for sgn, (dx, dy) in ((1, (3.2, -5.2)), (2, (1.8, -4.6))):
        a = (cx + 5.4, cy - 0.8)
        b = (cx + 5.4 + dx, cy - 0.8 + dy)
        hi.capsule(a, b, 0.35, 0.18, wing_f)
        for q in range(3):
            p = (a[0] + (b[0] - a[0]) * (q + 1) / 4, a[1] + (b[1] - a[1]) * (q + 1) / 4)
            hi.capsule(p, (p[0] + 1.3, p[1] - 0.2), 0.15, 0.1, wing_f)
    # nogi
    for k in range(3):
        hi.capsule((cx + 0.8 + k * 1.2, cy + 2.8), (cx + 0.2 + k * 1.4, cy + 5.2), 0.3, 0.2, wing_f)
    # bliższe skrzydło: przód wzorzysty z oczkiem
    if sleep:
        hi.ellipse((cx - 2.6, cy - 0.6), 6.4, 3.2, wing, rot=math.radians(10))
        hi.ellipse((cx - 3.0, cy - 0.8), 3.0, 1.4, wing_d, rot=math.radians(10))
        eye = (cx - 3.4, cy - 0.8)
    else:
        wc = (cx - 1.2, cy - 3.0 - 3.8 * lift)
        rot = math.radians(-14 - 26 * lift)
        hi.ellipse(wc, 3.9, 6.4, wing, rot=rot)
        hi.ellipse((wc[0] - 0.8, wc[1] + 1.6), 2.6, 3.6, wing_d, rot=rot)                                       # cień u nasady
        eye = (wc[0] - 0.4 + 2.0 * math.sin(rot), wc[1] - 1.8 - 1.2 * lift)
    hi.ellipse(eye, 1.7, 1.7, spot)
    hi.ellipse(eye, 0.8, 0.8, pupil)
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    _eye(glow, hi, (cx + 5.4, cy), [(0, 0), (1, 0)], (255, 214, 140), 170 if sleep else 255)
    _eye(glow, hi, eye, [(0, 0)], (255, 190, 100), 90)
    if sleep:
        _flip_v(fr, glow)
    return fr, glow


# ================================================================ SKOCZEK (spada z sufitu)

SKOCZEK_HD = (26, 26)
SKOCZEK_ANIMS = [("idle", 4, 3, True), ("run", 6, 12, True), ("windup", 1, 1, False), ("sleep", 1, 1, False)]


def skoczek(an, i):
    """Chudy, długonogi owadzi drapieżnik. Śpi wisząc głową w dół (odbity w pionie), spada rozkraczony z pazurami,
    po lądowaniu biega długimi susami."""
    W, H = SKOCZEK_HD
    hi = _sc(W, H, 1.0, 0.0, 0.0)
    shell = hi.material(ramp((156, 148, 118), warm=(1.0, 0.95, 0.8), cool=(0.2, 0.18, 0.35)))
    shell_l = hi.material(ramp((190, 180, 142), warm=(1.0, 0.95, 0.8), cool=(0.2, 0.18, 0.35)))
    shell_d = hi.material(ramp((92, 86, 70), cool=(0.18, 0.15, 0.35)))
    bone = hi.material(ramp((226, 216, 184), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    mouth = hi.material(ramp((60, 14, 24), cool=(0.1, 0.05, 0.2)), bands=(0.3, 0.6, 0.85, 0.95))
    t = i / {"idle": 4, "run": 6}.get(an, 1) * math.tau
    sleep, wind = an == "sleep", an == "windup"
    ground = H - 0.4
    cy = 12.0 + (0.5 * math.sin(t) if an == "idle" else (-1.4 * abs(math.sin(t)) if an == "run" else 0.0))
    if sleep:
        cy = 14.0
    if wind:
        cy = 10.0
    # nogi: dwie pary długich, stawowych odnóży; przednie zakończone pazurem
    legs = [(14.0, 1), (10.4, 1), (12.8, 0), (8.8, 0)]
    for k, (hx, near) in enumerate(legs):
        if sleep:
            a1, a2 = (-32.0 + 14 * k, 130.0)
        elif wind:
            a1, a2 = (58.0 - 26 * k, -34.0)
        elif an == "run":
            ph = t + k * math.pi * 0.5
            a1, a2 = (40 * math.sin(ph), 50 + 44 * max(0, math.cos(ph)))
        else:
            a1, a2 = ([-30.0, -10.0, 12.0, 32.0][k], 40.0)
        hip = (hx, cy + 0.8)
        kn = fk(hip, a1, 7.0)
        ft = fk(kn, a1 - a2, 7.6)
        if not sleep and not wind:
            ft = (ft[0], min(ft[1], ground))
        m = shell if near else shell_d
        hi.capsule(hip, kn, 1.3, 1.0, m)
        hi.capsule(kn, ft, 1.0, 0.55, m)
        hi.poly([(kn[0] - 0.8, kn[1] - 0.4), (kn[0] + 0.1, kn[1] - 2.0), (kn[0] + 0.9, kn[1] - 0.2)], bone)       # kolec na stawie
        hi.capsule(ft, (ft[0] + 1.4, ft[1] + 0.9), 0.4, 0.15, bone)                                              # pazur
    # tułów: odwłok (wydłużony, segmentowany), tułów, głowa z żuwaczkami
    hi.ellipse((7.6, cy + 0.4), 5.4, 2.8, shell_d)
    for seg in range(4):
        hi.capsule((4.4 + seg * 1.9, cy - 1.8), (4.8 + seg * 1.9, cy + 2.4), 0.3, 0.3, shell_l)
    hi.ellipse((12.4, cy), 4.0, 3.1, shell)
    hi.ellipse((12.0, cy - 1.0), 2.6, 1.6, shell_l)
    hi.ellipse((17.4, cy - 0.8), 3.0, 2.6, shell)
    mo = 1.2 if wind else 0.5
    for sgn in (-1, 1):
        hi.capsule((19.0, cy + 0.6), (21.6, cy + 0.6 + sgn * (0.8 + mo)), 0.6, 0.18, bone)
    hi.ellipse((20.0, cy + 1.2), 1.0, 0.5 + mo * 0.3, mouth)
    hi.capsule((17.0, cy - 2.4), (20.0, cy - 5.4), 0.3, 0.15, shell_d)                                           # czułki
    hi.capsule((16.0, cy - 2.4), (17.4, cy - 5.8), 0.3, 0.15, shell_d)
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    col = (255, 64, 38) if wind else (255, 140, 70)
    for pt in ((17.8, cy - 1.4), (19.0, cy - 1.0), (16.8, cy - 2.0)):
        _eye(glow, hi, pt, [(0, 0)], col, 140 if sleep else 255)
    if sleep:
        _flip_v(fr, glow)
    return fr, glow


# ================================================================ GNIAZDO (cel misji)

NEST_HD = (40, 34)
NEST_ANIMS = [("pulse", 3, 3, True)]


def nest(an, i):
    """Gniazdo: kępa pulsujących worków z żyłami, korzenie wrastające w ziemię, gałki zarodników."""
    W, H = NEST_HD
    hi = _sc(W, H, 1.0, 0.0, 0.0)
    flesh = hi.material(ramp((132, 40, 50), cool=(0.22, 0.08, 0.2)))
    flesh_l = hi.material(ramp((170, 62, 66), cool=(0.22, 0.08, 0.2)))
    flesh_d = hi.material(ramp((76, 22, 36), cool=(0.18, 0.06, 0.2)))
    sac = hi.material(ramp((198, 92, 70), cool=(0.3, 0.1, 0.2)), bands=(-0.1, 0.25, 0.55, 0.85))
    bone = hi.material(ramp((220, 204, 168), cool=(0.3, 0.2, 0.3)), bands=BONE_BANDS)
    p = [0.0, 1.0, 0.0][i]
    ground = H - 0.6
    # korzenie / wąsy wrastające w podłoże
    for k, (x0, x1, y1) in enumerate(((6, 1, 4), (10, 4, 2), (30, 36, 3), (34, 39, 5), (20, 18, 1))):
        hi.capsule((x0 + 5, ground - 4.0), (x1 + 2, ground - 0.4 + y1 * 0.0), 2.0, 0.7, flesh_d)
    hi.ellipse((20, ground - 3.0), 16.4, 4.2, flesh_d)
    # bryły worków
    hi.ellipse((12, ground - 10.0), 7.6, 8.0, flesh)
    hi.ellipse((28, ground - 10.0), 8.6, 8.2 + p * 0.7, flesh)
    hi.ellipse((20, ground - 15.0), 8.2, 8.8 + p * 0.9, flesh_l)
    hi.ellipse((20, ground - 7.0), 11.6, 6.4, flesh)
    # półprzezroczyste pęcherze z zarodnikami
    for (x, y, rr) in ((9.0, ground - 13.0, 2.6), (30.0, ground - 14.0, 2.9), (20.0, ground - 22.0, 3.0 + p * 0.3), (23.5, ground - 9.0, 2.2), (15.0, ground - 7.0, 2.0)):
        hi.ellipse((x, y), rr, rr, sac)
        hi.ellipse((x - rr * 0.3, y - rr * 0.3), rr * 0.4, rr * 0.35, sac, bias=0.4)
    _speckle(hi, flesh_d, flesh_l, (20, ground - 10), 14.0, 8.0, 26, 9, 0.55)       # ziarnista powierzchnia worków
    # żyły
    for (a, b) in (((20, ground - 8), (14, ground - 14)), ((20, ground - 8), (27, ground - 15)), ((20, ground - 8), (20, ground - 20)), ((20, ground - 7), (30, ground - 8))):
        hi.capsule(a, b, 0.7, 0.5, flesh_d)
    # kolce kostne u podstawy
    for x in (7, 14, 26, 33):
        hi.poly([(x - 1.0, ground - 1.0), (x + 0.1, ground - 5.0), (x + 1.1, ground - 1.0)], bone)
    fr = _finish2(hi, 0.3)
    glow = Frame(W * D, H * D)
    # żar w pęcherzach i żyłach; pulsuje
    a = 255 if p > 0.5 else 190
    for (x, y) in ((9, ground - 13), (30, ground - 14), (20, ground - 22), (23, ground - 9), (15, ground - 7)):
        _eye(glow, hi, (x, y), [(0, 0)], (255, 130, 70), a)
        _eye(glow, hi, (x + 1, y), [(0, 0)], (255, 110, 60), int(a * 0.8))
    return fr, glow
