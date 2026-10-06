"""Potwory: Trzosek (16×16), Wołek (30×30), Stalker (20×40) — rigi jak w char_player.py.

Wszystkie patrzą w prawo (gra odbija sprite poziomo). Oczy i żyłki idą do warstwy `glow`
(unshaded — świecą w ciemności), a ciało jest cieniowane i widoczne tylko w świetle.
"""
import math
from char_art import Hi, Frame, ramp, mix, fk, up

EYE = (255, 158, 56)
EYE_HOT = (255, 64, 38)
EYE_SLEEP = (153, 90, 38)


def _finish(hi, outline_k=0.34):
    fr = Frame.from_hi(hi)
    fr.despeckle()
    fr.outline(outline_k)
    return fr


def _glow_px(glow, fr, pts, col, a=255):
    for (x, y) in pts:
        x, y = int(round(x)), int(round(y))
        glow.put(x, y, (*col, a))


# ================================================================ TRZOSEK

TRZOSEK_ANIMS = [("idle", 4, 3, True), ("run", 6, 12, True), ("windup", 1, 1, False), ("sleep", 4, 1.5, True)]
T_GROUND = 15.7


def trzosek(an, i):
    hi = Hi(16, 16)
    hide = hi.material(ramp((150, 52, 58), cool=(0.22, 0.08, 0.2)))
    hide_d = hi.material(ramp((104, 36, 46), cool=(0.2, 0.08, 0.22)))
    bone = hi.material(ramp((214, 200, 168), cool=(0.3, 0.2, 0.3)), bands=(0.0, 0.3, 0.6, 0.88))
    flesh = hi.material(ramp((196, 96, 96), cool=(0.3, 0.1, 0.2)))
    sleep = an == "sleep"
    t = i / {"idle": 4, "run": 6, "sleep": 4}.get(an, 1) * math.tau
    breath = 0.35 * math.sin(t) if an in ("idle", "sleep") else 0.0
    if an == "run":
        bob = -0.9 * abs(math.sin(t)) + 0.4
        pitch = 0.10 * math.sin(2 * t)
    else:
        bob = 0.0
        pitch = 0.0
    low = 3.0 if sleep else (0.0 if an != "windup" else 1.2)
    by = 8.3 + low + bob - breath
    # --- ogon
    hi.capsule((2.4, by + 0.4), (0.6, by + 2.6 + (0.6 * math.sin(t) if an == "idle" else 0)), 1.0, 0.45, hide_d)
    # --- tylne nogi (daleka za ciałem)
    def leg(sx, sy, a1, a2, hind, dark):
        k = fk((sx, sy), a1, 2.9)
        p = fk(k, a1 - a2 if hind else a1 - a2 * 0.5, 3.1)
        m = hide_d if dark else hide
        hi.capsule((sx, sy), k, 1.25, 0.95, m)
        hi.capsule(k, p, 0.95, 0.7, m)
        hi.ellipse((p[0] + 0.5, min(p[1] + 0.2, T_GROUND - 0.6)), 1.2, 0.7, m)
        return p
    if not sleep:
        if an == "run":
            ph = [t, t + math.pi, t + math.pi * 0.6, t + math.pi * 1.6]
            a = [46 * math.sin(p) for p in ph]
            fl = [18 + 38 * max(0, math.cos(p)) for p in ph]
        elif an == "windup":
            a = [8, -6, -12, 10]
            fl = [10, 10, 24, 24]
        else:
            a = [6, -4, -10, 8]
            fl = [8, 8, 22, 22]
        for k, (sx, sy) in enumerate(((9.6, by + 1.7), (8.9, by + 1.9), (4.4, by + 1.5), (3.6, by + 1.7))):
            hind = k >= 2
            if an == "run":
                leg(sx, sy, a[k], fl[k], hind, dark=(k % 2 == 1))
            elif an != "windup" or k >= 2:
                leg(sx, sy, a[k], fl[k], hind, dark=(k % 2 == 1))
        if an == "windup":      # przednia łapa uniesiona do ciosu
            e = fk((10.4, by + 1.2), 100, 2.8)
            p = fk(e, 160, 2.6)
            hi.capsule((10.4, by + 1.2), e, 1.4, 1.1, hide)
            hi.capsule(e, p, 1.1, 0.7, hide)
            for d in (-0.8, 0.0, 0.8):
                hi.capsule(p, (p[0] + 0.8, p[1] + d * 0.9 - 0.6), 0.4, 0.2, bone)
    else:
        hi.ellipse((11.0, 14.3), 3.2, 1.1, hide_d)               # podkulone łapy
    # --- tułów z garbem
    hi.ellipse((6.8, by), 4.9, 3.0, hide, rot=pitch)
    hi.ellipse((5.4, by - 1.0), 3.2, 2.7, hide, rot=pitch)
    hi.ellipse((7.2, by + 1.5), 4.2, 1.3, hide_d)                 # brzuch w cieniu
    # --- kolce grzbietu
    for k, x in enumerate((3.2, 5.4, 7.6)):
        top = by - 1.0 - 2.7 + 0.5 * k
        hi.poly([(x - 0.8, top + 1.9), (x + 0.1, top - 0.6), (x + 0.9, top + 2.0)], bone, normal=(0.25, -0.5, 0.8))
    # --- głowa
    jaw_open = 1.5 if an == "windup" else (0.0 if sleep else 0.25 * (1 + math.sin(t)) if an == "idle" else 0.4)
    hx, hy = (11.8, by + (1.5 if sleep else -0.6))
    if sleep:
        hx, hy = 11.2, by + 1.0
    hi.capsule((9.4, hy - 0.2), (hx + 2.4, hy + 0.7), 2.0, 1.15, hide)
    hi.capsule((10.2, hy + 0.9), (hx + 2.2, hy + 1.5 + jaw_open), 0.85, 0.5, hide_d)
    if not sleep:
        # kły
        for dx in (0.0, 1.2):
            hi.poly([(hx + 1.2 + dx, hy + 1.1), (hx + 1.75 + dx, hy + 1.1), (hx + 1.5 + dx, hy + 2.2 + jaw_open * 0.4)], bone)
    fr = _finish(hi)
    glow = Frame(16, 16)
    col = EYE_HOT if an == "windup" else (EYE_SLEEP if sleep else EYE)
    ex, ey = hx + 0.3, hy - 0.8
    if sleep:
        _glow_px(glow, fr, [(ex + 0.8, ey + 0.4)], col, 150)
    else:
        _glow_px(glow, fr, [(ex, ey), (ex + 1.4, ey + 0.2)], col)
        fr.put(int(round(ex + 0.6)), int(round(ey + 0.1)), (40, 12, 16, 255)) if False else None
        if an == "windup":
            _glow_px(glow, fr, [(ex + 1.4, ey + 3.0)], (255, 120, 80), 190)   # żar w paszczy
    return fr, glow


# ================================================================ WOŁEK

WOLEK_ANIMS = [("idle", 4, 2, True), ("walk", 6, 7, True), ("windup", 1, 1, False), ("sleep", 4, 1.2, True)]


def wolek(an, i):
    W = H = 30
    hi = Hi(W, H)
    hide = hi.material(ramp((128, 96, 112), cool=(0.18, 0.12, 0.3)))
    hide_l = hi.material(ramp((150, 112, 124), cool=(0.18, 0.12, 0.3)))          # bliższa ręka — jaśniejsza, czytelna na tułowiu
    hide_d = hi.material(ramp((70, 52, 68), cool=(0.14, 0.1, 0.3)))              # dalsze kończyny
    horn = hi.material(ramp((226, 212, 172), cool=(0.3, 0.2, 0.3)), bands=(0.0, 0.3, 0.6, 0.88))
    scar = hi.material(ramp((168, 70, 80), cool=(0.3, 0.1, 0.2)))
    sleep = an == "sleep"
    t = i / {"idle": 4, "walk": 6, "sleep": 4}.get(an, 1) * math.tau
    breath = 0.5 * math.sin(t) if an in ("idle", "sleep") else 0.0
    ground = 29.6
    lean = 14.0
    if sleep:
        lean = 58.0
    elif an == "windup":
        lean = -2.0
    # --- nogi: grube, krótkie; spód stopy dotyka ziemi
    def legpts(k, hip):
        if sleep:
            kn = (hip[0] + 3.4, ground - 3.6)
            ft = (kn[0] + 2.6, ground - 1.3)
            return kn, ft
        a, fl = 0.0, 10.0
        if an == "walk":
            ph = t + (0 if k == 0 else math.pi)
            a = 24 * math.sin(ph)
            fl = 10 + 34 * max(0, math.cos(ph))
        kn = fk(hip, a, 4.8)
        ft = fk(kn, a - fl, 4.4)
        return kn, ft
    hx = 12.5
    hy = 19.4
    if not sleep:
        low = max(legpts(k, (hx + (2.6 if k == 0 else -2.6), hy + 1.2))[1][1] for k in (0, 1)) + 1.2
        hy += ground - low
    else:
        hy = 24.2
    hy -= breath
    sh = up((hx, hy), lean, 7.6)
    tc = up((hx, hy), lean, 4.1)

    def leg(k):
        hip = (hx + (2.6 if k == 0 else -2.6), hy + 1.2)
        kn, ft = legpts(k, hip)
        m = hide if k == 0 else hide_d
        hi.capsule(hip, kn, 3.1, 2.5, m)
        hi.capsule(kn, ft, 2.5, 2.1, m)
        hi.capsule((ft[0] - 1.4, ft[1] + 0.2), (ft[0] + 2.8, ft[1] + 0.6), 1.7, 1.4, m)
        for d in (0.0, 1.5):                                      # pazury
            hi.poly([(ft[0] + 3.0 + d * 0.2, ft[1] - 0.2 + d * 0.3), (ft[0] + 4.4 + d * 0.2, ft[1] + 0.9), (ft[0] + 3.0 + d * 0.2, ft[1] + 1.2)], horn)

    def arm(k, shoulder):
        near = k == 0
        if an == "windup":
            el = (shoulder[0] + (3.8 if near else 1.2), shoulder[1] - 5.2)
            fi = (el[0] + (2.4 if near else 0.8), el[1] - 4.4)
        elif sleep:
            el = (shoulder[0] + 2.4, shoulder[1] + 4.4)
            fi = (el[0] + 3.2, el[1] + 2.4)
        else:
            sw = 0.0
            if an == "walk":
                sw = 14 * math.sin(t + (math.pi if near else 0))
            el = fk(shoulder, 10 + sw, 5.4)
            fi = fk(el, 4 + sw * 1.3, 5.0)
        m = hide_l if near else hide_d
        hi.capsule(shoulder, el, 3.2, 2.7, m)
        hi.capsule(el, fi, 2.7, 2.5, m)
        hi.ellipse((fi[0] + 0.2, fi[1] + 0.9), 3.2, 3.0, m)       # maczuga pięści
        hi.poly([(el[0] - 0.4, el[1] - 2.8), (el[0] + 0.6, el[1] - 5.0), (el[0] + 1.5, el[1] - 2.6)], horn)   # kolec łokcia
        hi.capsule((fi[0] - 1.2, fi[1] + 0.2), (fi[0] + 1.0, fi[1] + 1.8), 0.4, 0.4, scar)

    leg(1)
    arm(1, (sh[0] - 1.6, sh[1] + 1.2))
    # --- tułów: klatka + garb + brzuch
    hi.ellipse(tc, 7.6, 7.0, hide, rot=math.radians(lean * 0.5))
    hi.ellipse((hx + 0.4, hy + 0.9), 6.0, 4.2, hide_d)
    hi.ellipse((tc[0] - 2.2, tc[1] - 3.0), 5.2, 4.0, hide)
    for dx in (-1.6, -0.2, 1.2):
        hi.capsule((tc[0] + dx, tc[1] + 0.8), (tc[0] + dx + 1.2, tc[1] + 3.6), 0.45, 0.4, scar)
    for k2, (dx, dy) in enumerate(((-3.6, -5.6), (-1.6, -6.6), (0.6, -6.9))):          # kolce na grzbiecie
        px, py = sh[0] + dx - 1.2, sh[1] + dy + 1.4
        hi.poly([(px - 1.0, py + 2.2), (px + 0.1, py - 1.6), (px + 1.0, py + 2.4)], horn, normal=(0.2, -0.6, 0.75))
    leg(0)
    # --- głowa: mała, nisko, wysunięta do przodu
    hc = (sh[0] + 4.6, sh[1] + (1.4 if not sleep else 0.6))
    hi.ellipse(hc, 3.8, 3.3, hide_l)
    hi.capsule((hc[0] + 0.8, hc[1] + 1.4), (hc[0] + 3.8, hc[1] + 2.2), 1.5, 1.1, hide)
    hi.capsule((hc[0] - 1.6, hc[1] - 2.2), (hc[0] - 4.2, hc[1] - 5.4), 1.1, 0.35, horn)
    hi.capsule((hc[0] + 1.8, hc[1] - 2.5), (hc[0] + 3.4, hc[1] - 5.8), 1.1, 0.35, horn)
    arm(0, (sh[0] + 0.8, sh[1] + 1.6))
    fr = _finish(hi)
    glow = Frame(W, H)
    col = EYE_HOT if an == "windup" else (EYE_SLEEP if sleep else EYE)
    ex, ey = hc[0] + 1.8, hc[1] - 0.6
    if sleep:
        _glow_px(glow, fr, [(ex, ey)], col, 140)
    else:
        _glow_px(glow, fr, [(ex, ey), (ex + 1.5, ey + 0.2)], col)
    return fr, glow


# ================================================================ STALKER

STALKER_ANIMS = [("idle", 6, 4, True), ("walk", 8, 9, True), ("windup", 1, 1, False)]


def stalker(an, i):
    W, H = 20, 40
    hi = Hi(W, H)
    cloth = hi.material(ramp((62, 54, 72), cool=(0.1, 0.1, 0.3), sh=1.2), bands=(-0.1, 0.25, 0.6, 0.9))
    cloth_d = hi.material(ramp((40, 34, 50), cool=(0.1, 0.1, 0.3)), bands=(-0.1, 0.25, 0.6, 0.9))
    skin = hi.material(ramp((128, 120, 132), warm=(0.85, 0.85, 0.95), cool=(0.15, 0.12, 0.3)), bands=(-0.1, 0.3, 0.62, 0.9))
    skin_d = hi.material(ramp((78, 72, 86), cool=(0.15, 0.12, 0.3)), bands=(-0.1, 0.3, 0.62, 0.9))
    rib = hi.material(ramp((150, 144, 150), cool=(0.2, 0.15, 0.3)), bands=(0.0, 0.3, 0.6, 0.9))
    t = i / {"idle": 6, "walk": 8}.get(an, 1) * math.tau
    ground = 39.7
    hx = 10.0
    if an == "walk":
        sway = 1.0 * math.sin(t)
        step = [(30 * math.sin(t + k * math.pi), 8 + 46 * max(0, math.cos(t + k * math.pi))) for k in (0, 1)]
    else:
        sway = 1.2 * math.sin(t)
        step = [(5, 6), (-5, 6)]
    # --- nogi: długie, wychudzone, kolano wygięte do tyłu
    def leg(k, hip):
        a, fl = step[k]
        kn = fk(hip, a, 7.4)
        ft = fk(kn, a - fl, 7.6)
        return hip, kn, ft
    legs = [leg(k, (hx + (0.7 if k == 0 else -0.7), 25.0)) for k in (0, 1)]
    low = max(l[2][1] for l in legs) + 1.0
    dy = ground - low
    if an == "windup":
        dy = 0.0
    hy = 25.0 + dy
    for k in (1, 0):
        hip, kn, ft = leg(k, (hx + (0.7 if k == 0 else -0.7), hy))
        m = cloth_d if k == 1 else cloth
        hi.capsule(hip, kn, 1.7, 1.2, m)
        hi.capsule(kn, ft, 1.2, 0.85, m)
        hi.capsule((ft[0] - 0.5, ft[1] + 0.1), (ft[0] + 2.4, ft[1] + 0.4), 0.9, 0.7, skin_d)
        if k == 1:
            _stalker_torso_back(hi, hx, hy, sway, an, t, skin_d, cloth_d)
    lean = 6.0 + sway * 2.0
    sh = up((hx, hy), lean, 12.5)
    # --- szerokie, wychudzone ramiona do kolan
    # --- tułów: wychudzony, z żebrami; płaszcz w strzępach
    hi.capsule((hx, hy - 0.5), sh, 3.0, 3.2, cloth)
    for k, yy in enumerate((3.0, 5.2, 7.4)):
        c = up((hx, hy), lean, yy + 1.0)
        hi.capsule((c[0] - 1.0, c[1]), (c[0] + 2.2, c[1] + 0.5), 0.45, 0.35, rib)
    for k in range(5):                       # strzępy płaszcza
        bx = hx - 3.2 + k * 1.7
        wob = math.sin(t * 1.0 + k * 1.3) * 0.7
        hi.capsule((bx, hy + 1.0), (bx + wob - 0.3, hy + 5.0 + (k % 2) * 1.4), 0.9, 0.35, cloth_d if k % 2 else cloth)
    # --- głowa: wydłużona
    hd = up(sh, lean * 0.5 + sway, 5.6)
    hi.capsule((sh[0] + 0.3, sh[1] - 1.0), (hd[0] + 0.4, hd[1] + 2.0), 1.2, 1.7, skin_d)           # szyja
    hi.ellipse((hd[0] + 0.7, hd[1]), 2.7, 4.8, skin)
    hi.capsule((hd[0] + 1.6, hd[1] + 2.4), (hd[0] + 2.4, hd[1] + 3.8), 0.9, 0.6, skin_d)           # zapadnięta żuchwa
    # --- ręce
    def arm(k):
        s = (sh[0] + (0.5 if k == 0 else -1.0), sh[1] + 1.0)
        if an == "windup":
            el = (s[0] + (3.0 if k == 0 else -3.2), s[1] - 5.0)
            fi = (el[0] + (3.0 if k == 0 else -3.4), el[1] - 5.0)
        else:
            sw = (4.0 * math.sin(t + (0 if k == 0 else math.pi))) * (1.0 if an == "walk" else 0.4)
            el = (s[0] + 0.6 + sw * 0.5, s[1] + 7.0)
            fi = (el[0] + 0.8 + sw * 0.6, el[1] + 8.2)
        m = skin_d if k == 1 else skin
        hi.capsule(s, el, 1.2, 0.95, m)
        hi.capsule(el, fi, 0.95, 0.75, m)
        for d in (-0.9, 0.0, 0.9):               # długie palce
            hi.capsule(fi, (fi[0] + 0.5 * d, fi[1] + 2.8), 0.4, 0.2, rib)
    arm(1)
    arm(0)
    fr = _finish(hi, 0.3)
    glow = Frame(W, H)
    hot = an == "windup"
    ec = (255, 52, 38) if hot else (255, 50, 36)
    ex, ey = hd[0] + 1.2, hd[1] - 1.4
    _glow_px(glow, fr, [(ex, ey), (ex + 1.6, ey + 0.1)], ec, 255 if hot else 215)
    return fr, glow


def _stalker_torso_back(hi, hx, hy, sway, an, t, skin_d, cloth_d):
    pass


# ================================================================ ŚLEPIEC

SLEPIEC_ANIMS = [("idle", 4, 3, True), ("walk", 6, 8, True), ("windup", 1, 1, False), ("sleep", 4, 1.5, True)]


def slepiec(an, i):
    """Blada, niewidząca istota: zaszyte oczy, wielkie ucho, ręce wyciągnięte przed siebie, macha głową."""
    W, H = 16, 20
    hi = Hi(W, H)
    skin = hi.material(ramp((206, 200, 196), warm=(1.0, 0.95, 0.85), cool=(0.3, 0.25, 0.4)))
    skin_d = hi.material(ramp((150, 144, 150), cool=(0.25, 0.2, 0.4)))
    rag = hi.material(ramp((92, 84, 76), cool=(0.15, 0.12, 0.3)))
    stitch = hi.material(ramp((90, 40, 44), cool=(0.2, 0.1, 0.2)))
    sleep = an == "sleep"
    t = i / {"idle": 4, "walk": 6, "sleep": 4}.get(an, 1) * math.tau
    ground = 19.7
    lean = 38.0 if not sleep else 80.0
    hip = [7.0, 12.4]
    if an == "walk":
        hip[1] += 0.3 * math.sin(2 * t)
    if sleep:
        hip = [6.0, 15.0 - 0.3 * math.sin(t)]
    sh = up(tuple(hip), lean, 5.0)
    # nogi
    for k in (1, 0):
        a, fl = (6.0, 8.0) if k == 0 else (-6.0, 8.0)
        if an == "walk":
            ph = t + (0 if k == 0 else math.pi)
            a = 30 * math.sin(ph)
            fl = 10 + 40 * max(0, math.cos(ph))
        if sleep:
            a, fl = (70.0, 110.0)
        h0 = (hip[0] + (0.4 if k == 0 else -0.4), hip[1])
        kn = fk(h0, a, 3.6)
        ft = fk(kn, a - fl, 3.6)
        m = skin if k == 0 else skin_d
        hi.capsule(h0, kn, 1.5, 1.2, m)
        hi.capsule(kn, ft, 1.2, 1.0, m)
        hi.capsule((ft[0] - 0.5, ft[1] + 0.3), (ft[0] + 1.7, ft[1] + 0.5), 0.9, 0.7, m)
    # daleka ręka, tułów w łachmanach
    sway = math.sin(t) * (10.0 if an != "walk" else 18.0)

    def arm(k):
        s0 = (sh[0] + (0.4 if k == 0 else -0.5), sh[1] + 0.8)
        if sleep:
            el = (s0[0] + 1.5, s0[1] + 2.5)
            fi = (el[0] + 1.5, el[1] + 1.5)
        elif an == "windup":
            el = (s0[0] + 2.2, s0[1] - 1.0)
            fi = (el[0] + 2.4, el[1] - 1.8)
        else:
            a1 = 70 + sway * (1 if k == 0 else -1)
            el = fk(s0, a1, 3.0)
            fi = fk(el, a1 + 12, 3.0)
        m = skin if k == 0 else skin_d
        hi.capsule(s0, el, 1.1, 0.9, m)
        hi.capsule(el, fi, 0.9, 0.7, m)
        for d in (-0.7, 0.0, 0.7):
            hi.capsule(fi, (fi[0] + 1.2, fi[1] + d * 0.8), 0.3, 0.2, m)
    arm(1)
    hi.capsule(tuple(hip), sh, 2.4, 2.6, rag)
    hi.ellipse(up(tuple(hip), lean, 2.0), 2.5, 2.0, skin_d)
    arm(0)
    # głowa przechylona, wielkie ucho nasłuchuje
    hc = up(sh, lean * 0.5 + 12.0 * math.sin(t * (1 if an != "walk" else 2)) * 0.6 + 6.0, 3.0)
    hc = (hc[0] + 1.0, hc[1] + (1.6 if sleep else 0.0))
    hi.ellipse(hc, 2.7, 3.0, skin)
    hi.ellipse((hc[0] - 0.8, hc[1] - 0.4), 1.4, 2.6, skin_d)                                  # ucho
    hi.ellipse((hc[0] - 1.1, hc[1] - 0.6), 0.9, 1.9, skin)
    hi.capsule((hc[0] + 1.2, hc[1] + 1.4), (hc[0] + 2.6, hc[1] + 1.8), 0.7, 0.5, skin_d)     # bezzębna szczęka
    fr = _finish(hi, 0.32)
    glow = Frame(W, H)
    # zaszyte oczy: dwie czerwone nitki (detal na siatce)
    ex, ey = int(round(hc[0] + 1.2)), int(round(hc[1] - 0.8))
    for dx in (0, 1):
        fr.only_opaque_put(ex + dx, ey, (120, 40, 48, 255))
    if an == "windup":
        _glow_px(glow, fr, [(hc[0] + 2.2, hc[1] + 1.8)], (255, 90, 70), 200)
    return fr, glow


# ================================================================ PODSŁUCHACZ

PODSLUCHACZ_ANIMS = [("idle", 4, 3, True), ("windup", 1, 1, False), ("sleep", 2, 1.5, True)]


def podsluchacz(an, i):
    """Nieruchomy „słuchacz": długa szyja, wielkie lejkowate uszy, paszcza otwiera się do krzyku."""
    W, H = 16, 26
    hi = Hi(W, H)
    skin = hi.material(ramp((150, 132, 146), cool=(0.2, 0.15, 0.4)))
    skin_d = hi.material(ramp((104, 88, 104), cool=(0.18, 0.12, 0.4)))
    ear = hi.material(ramp((182, 120, 128), cool=(0.3, 0.1, 0.3)))
    rag = hi.material(ramp((70, 62, 72), cool=(0.14, 0.12, 0.3)))
    mouth = hi.material(ramp((90, 22, 34), cool=(0.2, 0.1, 0.2)))
    t = i / {"idle": 4, "sleep": 2}.get(an, 1) * math.tau
    scream = an == "windup"
    ground = 25.7
    base = (7.5, 20.0)
    # nogi: proste, cienkie
    for k, x in ((1, 6.7), (0, 8.5)):
        hi.capsule((x, 18.6), (x - 0.2 + (0.4 if k else 0), ground - 1.2), 1.1, 0.8, skin_d if k else skin)
        hi.capsule((x - 0.8, ground - 0.5), (x + 1.4, ground - 0.4), 0.9, 0.7, skin_d if k else skin)
    # tułów w łachmanach
    lean = 4.0 + (-12.0 if scream else 0.0)
    sh = up((7.5, 18.5), lean, 6.0)
    hi.capsule((7.5, 18.5), sh, 2.6, 2.2, rag)
    # ręce przy uszach (nasłuchuje) albo rozłożone w krzyku
    for k in (1, 0):
        s0 = (sh[0] + (0.4 if k == 0 else -0.4), sh[1] + 0.6)
        if scream:
            el = (s0[0] + (2.4 if k == 0 else -2.2), s0[1] + 1.6)
            fi = (el[0] + (1.6 if k == 0 else -1.6), el[1] + 3.2)
        else:
            el = (s0[0] + (1.4 if k == 0 else -1.2), s0[1] + 3.4)
            fi = (el[0] + 0.6, el[1] + 3.0)
        m = skin if k == 0 else skin_d
        hi.capsule(s0, el, 0.95, 0.8, m)
        hi.capsule(el, fi, 0.8, 0.6, m)
    # szyja i głowa
    sway = 0.7 * math.sin(t) if an != "windup" else 0.0
    neck_top = up(sh, lean * 0.6 + sway * 4, 3.4)
    hi.capsule((sh[0], sh[1] - 0.6), neck_top, 1.2, 1.0, skin)
    hc = (neck_top[0] + (-0.4 if scream else 0.8), neck_top[1] - (1.5 if not scream else 0.4))
    hi.ellipse(hc, 2.9, 2.7, skin)
    # lejkowate uszy
    for k, dx in ((1, -2.6), (0, 2.2)):
        e = (hc[0] + dx * 0.55, hc[1] - 1.8 - (0.4 if an == "idle" and (i % 2) else 0.0))
        hi.ellipse((e[0] + dx * 0.35, e[1]), 1.5, 3.0, ear if k == 0 else skin_d, rot=math.radians(18 * (1 if k == 0 else -1)))
    # paszcza: zamknięta szparka albo szeroko otwarta
    if scream:
        hi.ellipse((hc[0] + 0.9, hc[1] + 1.4), 2.1, 2.5, mouth)
    else:
        hi.capsule((hc[0] + 0.8, hc[1] + 1.4), (hc[0] + 2.4, hc[1] + 1.6), 0.5, 0.4, mouth)
    fr = _finish(hi, 0.32)
    glow = Frame(W, H)
    # oczy: dwa blade punkty (czujny), w krzyku — żar paszczy
    ex, ey = int(round(hc[0] + 1.2)), int(round(hc[1] - 0.6))
    col = (255, 214, 140)
    if scream:
        _glow_px(glow, fr, [(hc[0] + 0.6, hc[1] + 1.0), (hc[0] + 1.4, hc[1] + 1.8), (hc[0] + 0.6, hc[1] + 2.2)], (255, 80, 60), 230)
    if an != "sleep":
        _glow_px(glow, fr, [(ex, ey), (ex + 2, ey)], (255, 60, 40) if scream else col, 220)
    return fr, glow


# ================================================================ MIMIK

MIMIK_ANIMS = [("idle", 6, 5, True), ("walk", 8, 12, True), ("windup", 1, 1, False), ("sleep", 1, 1, False)]
MIMIC_COLOR = (118, 172, 118)        # nieco przygaszona zieleń — prawie slot P4, ale „nie ta"


def mimik(an, i):
    """Udaje gracza: ta sama sylwetka i animacje co postać (char_player), plus zdradzające szczegóły —
    świecące oczy (warstwa glow, widać je w ciemności) i, po demaskacji, czerwona szczelina paszczy."""
    import char_player
    src = {"idle": ("idle", i), "walk": ("run", i), "windup": ("jump", 0), "sleep": ("idle", 0)}[an]
    fr, _ = char_player.build(MIMIC_COLOR, False, src[0], src[1])
    glow = Frame(fr.w, fr.h)
    eye = None
    for y in range(fr.h):
        for x in range(fr.w):
            px = fr.px[y][x]
            if px is not None and tuple(px[:3]) == (34, 26, 38):
                eye = (x, y)
    if eye is not None:
        ex, ey = eye
        hot = an == "windup"
        col = (255, 60, 40) if hot else (255, 120, 90)
        glow.put(ex, ey, (*col, 255 if hot else 170))
        glow.put(ex + 1, ey, (*col, 255 if hot else 110))
        if hot:
            # po demaskacji: paszcza rozcięta od ucha do ucha
            for dx in range(-1, 2):
                fr.only_opaque_put(ex + dx, ey + 2, (150, 20, 30, 255))
                glow.put(ex + dx, ey + 2, (255, 70, 50, 200))
    return fr, glow


# ================================================================ API

def monster_frames(fn, anims):
    body, glow = [], []
    for an, n, _fps, _loop in anims:
        b, g = [], []
        for i in range(n):
            fr, gl = fn(an, i)
            b.append(fr)
            g.append(gl)
        body.append(b)
        glow.append(g)
    return body, glow
