"""Generator śladów trafień w świecie 3D (IMPACT_MARKS_PLAN.md E1–E2): dekale po kulach, rysy rykoszetów, gniazda śrutu i osmalenia wybuchów.

Uruchomienie (numpy + scipy + Pillow): python prototype/tools/gen_impact_marks.py [--out=prototype/art/world3d/marks] [--preview]
Wynik (dla każdego śladu trzy pliki PNG):
  <nazwa>_albedo.png  — RGBA: kolor i krycie (alfa maskuje też normalną i ORM dekala — tak działa `Decal` w Godocie)
  <nazwa>_normal.png  — normalna z mapy wysokości (konwencja OpenGL, Y w górę)
  <nazwa>_orm.png     — R okluzja, G chropowatość, B metaliczność
Nazwy:
  hole_<rodzaj>_<w>     — kula prostopadle: concrete, rock, dirt, wood, metal, ice (w = 0..HOLE_VARIANTS-1)
  graze_<rodzaj>_<w>    — rysa rykoszetu / kula pod ostrym kątem, wydłużona wzdłuż osi U (x): concrete, rock, metal
  cluster_<rodzaj>_<w>  — gniazdo śrutu (kilka dziurek): concrete, rock, dirt, wood, metal
  scorch_<rodzaj>_<w>   — osmalenie wybuchu z dziobakami odłamków: concrete, rock, dirt, metal, wood (E2)
  pock_<w>              — pojedynczy dziobak odłamka na ścianie poza pierścieniem (E2)
Ślad leży w środku obrazu, poza kołem o promieniu 1 (w jednostkach obrazu) alfa = 0 — dekal można obracać.
Wszystko deterministyczne (ziarno z nazwy): ponowne uruchomienie daje te same pliki.
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_pbr_gen as G  # noqa: E402

HOLE_RES = 128
SCORCH_RES = 256
HOLE_VARIANTS = 3
GRAZE_VARIANTS = 2
CLUSTER_VARIANTS = 2
SCORCH_VARIANTS = 2
POCK_VARIANTS = 3

HOLE_KINDS = ["concrete", "rock", "dirt", "wood", "metal", "ice"]
GRAZE_KINDS = ["concrete", "rock", "metal"]
CLUSTER_KINDS = ["concrete", "rock", "dirt", "wood", "metal"]
SCORCH_KINDS = ["concrete", "rock", "dirt", "metal", "wood"]

## barwy materiałów (liniowo 0..1, zapis jak w reszcie generatorów)
DUST = {"concrete": (0.56, 0.54, 0.50), "rock": (0.46, 0.43, 0.39), "ice": (0.84, 0.88, 0.92)}
CORE = (0.025, 0.022, 0.02)


def seed_of(name):
    return sum(ord(c) * (i + 1) * 131 for i, c in enumerate(name)) % (2 ** 31)


def blur(a, s):
    return gaussian_filter(a, s, mode="nearest")


def grid(n):
    c = (np.arange(n, dtype=np.float32) + 0.5) / n * 2.0 - 1.0
    x, y = np.meshgrid(c, c)
    return x, y


def lobes(ang, k, lo, hi, rng):
    """Poszarpany brzeg: mnożnik promienia zależny od kąta (k płatów, interpolacja kosinusowa, okresowo)."""
    b = rng.uniform(lo, hi, k).astype(np.float32)
    t = (ang / (2 * math.pi)) % 1.0 * k
    i0 = np.floor(t).astype(int) % k
    i1 = (i0 + 1) % k
    f = t - np.floor(t)
    f = (1 - np.cos(f * math.pi)) * 0.5
    return b[i0] * (1 - f) + b[i1] * f


def noise(n, f, seed, octaves=3):
    return G.fbm(n, f, f, octaves, seed)


def fade_edge(r, inner=0.86):
    """Alfa schodzi do zera przed brzegiem obrazu (dekal obracany — rogi muszą być puste)."""
    return np.clip((1.0 - r) / (1.0 - inner), 0.0, 1.0)


def pack(alb, alpha, h, rough, metal, ao=None, ns=1.0):
    n = h.shape[0]
    if ao is None:
        ao = np.clip(1.0 - np.clip(blur(h, n / 32) - h, 0, 1) * 3.0, 0.0, 1.0)
    return {"albedo": alb, "alpha": alpha, "height": h, "ns": ns, "roughness": rough, "metallic": metal, "ao": ao}


# ---------------------------------------------------------------- kula prostopadle

def hole(kind, v):
    n = HOLE_RES
    rng = np.random.default_rng(seed_of("hole_%s_%d" % (kind, v)))
    x, y = grid(n)
    r0 = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    s = seed_of(kind) + v * 101
    nz = noise(n, 6, s)
    nz2 = noise(n, 16, s + 7)
    alb = np.zeros((n, n, 3), np.float32)
    alpha = np.zeros((n, n), np.float32)
    h = np.zeros((n, n), np.float32)
    rough = np.full((n, n), 0.92, np.float32)
    metal = np.zeros((n, n), np.float32)
    if kind in ("concrete", "rock", "ice"):
        r = r0 / lobes(ang, 14, 0.78, 1.15, rng)
        core = 0.27 + 0.04 * rng.random()                                        # duży ciemny wylot: z kamery gry ślad ma kilka pikseli
        spall = 0.6 + 0.08 * rng.random()
        hole_m = G.smoothstep(core + 0.04, core - 0.02, r)                       # wylot w głąb
        sp = G.smoothstep(spall + 0.05, spall - 0.08, r) * (0.75 + 0.5 * nz)     # odprysk: płytka niecka z grudami
        h = 0.55 - 0.32 * sp - 0.45 * hole_m + 0.06 * (nz2 - 0.5) * sp
        dust = np.array(DUST[kind], np.float32)
        ring = sp * (1.0 - hole_m)
        alb = dust[None, None, :] * (0.85 + 0.3 * nz2[..., None])
        alb = alb * (0.35 + 0.65 * G.smoothstep(core, spall, r))[..., None]       # cień niecki gęstnieje ku wylotowi (czytelność z daleka)
        alb = alb * (1.0 - hole_m[..., None]) + np.array(CORE, np.float32) * hole_m[..., None]
        powder = G.smoothstep(1.0, spall, r) * (1.0 - sp) * (0.25 + 0.2 * nz)    # jasny pył wokół, słabo kryjący
        alpha = np.maximum(np.maximum(hole_m, ring * (0.75 + 0.25 * nz2)), powder)
        if kind == "ice":                                                        # lód: gwiazda pęknięć z jasnym środkiem
            cr = np.zeros((n, n), np.float32)
            for k in range(7):
                a = rng.uniform(0, 2 * math.pi)
                d = np.abs(np.sin(ang - a)) * r0 * n
                cr = np.maximum(cr, np.clip(1.2 - d, 0, 1) * (np.cos(ang - a) > 0) * G.smoothstep(0.95, 0.3, r0))
            alpha = np.maximum(alpha, cr * 0.8)
            alb = alb * (1 - cr[..., None] * 0.3) + cr[..., None] * 0.95 * 0.3
            h = h - cr * 0.08
            rough = 0.25 + 0.6 * sp
        else:
            rough = 0.95 - 0.1 * hole_m
    elif kind == "dirt":
        r = r0 / lobes(ang, 10, 0.85, 1.12, rng)
        pit = G.smoothstep(0.42, 0.1, r)
        lip = G.smoothstep(0.35, 0.55, r) * G.smoothstep(0.95, 0.6, r) * (0.6 + 0.6 * nz)   # wał wyrzuconej ziemi
        h = 0.5 - 0.4 * pit + 0.18 * lip
        wet = np.array((0.07, 0.05, 0.035), np.float32)
        soil = np.array((0.24, 0.18, 0.12), np.float32)
        alb = soil[None, None, :] * (0.8 + 0.4 * nz2[..., None])
        alb = alb * (1 - pit[..., None]) + wet * pit[..., None]
        clods = (nz2 > 0.62) * G.smoothstep(1.0, 0.5, r) * (1 - pit)              # grudki
        alpha = np.clip(np.maximum(pit, lip * 0.75) + clods * 0.6, 0, 1) * G.smoothstep(1.0, 0.75, r)
        rough = np.full((n, n), 0.97, np.float32) - 0.25 * pit                    # wilgotny środek błyszczy słabo
    elif kind == "wood":
        r = r0 / lobes(ang, 24, 0.7, 1.3, rng)
        core = 0.28 + 0.05 * rng.random()
        hole_m = G.smoothstep(core + 0.04, core - 0.03, r)
        spl = np.zeros((n, n), np.float32)
        for k in range(6):                                                       # drzazgi promieniście, dłuższe wzdłuż słojów (oś X)
            a = rng.uniform(0, 2 * math.pi)
            ln = rng.uniform(0.35, 0.65) * (1.0 + 0.4 * abs(math.cos(a)))
            d = np.abs(np.sin(ang - a)) * r0
            w = 0.03 + 0.025 * rng.random()
            spl = np.maximum(spl, np.clip(1 - d / w, 0, 1) * (np.cos(ang - a) > 0) * G.smoothstep(ln, core, r0))
        brk = G.smoothstep(0.62, 0.3, r)                                         # jasny przełom wokół dziury
        light = np.array((0.52, 0.40, 0.27), np.float32)
        alb = light[None, None, :] * (0.85 + 0.3 * nz2[..., None])
        alb = alb * (1 - hole_m[..., None]) + np.array(CORE, np.float32) * hole_m[..., None]
        alpha = np.maximum(hole_m, np.maximum(brk * 0.7, spl * 0.6)) * fade_edge(r0)
        h = 0.5 - 0.45 * hole_m + 0.14 * spl - 0.08 * brk * (1 - hole_m)
        rough = np.full((n, n), 0.9, np.float32)
    elif kind == "metal":
        r = r0 / lobes(ang, 16, 0.88, 1.12, rng)
        core = 0.2 + 0.04 * rng.random()
        dent = G.smoothstep(0.55, 0.05, r)                                       # gładka wgniecina
        hole_m = G.smoothstep(core + 0.03, core - 0.02, r)
        bare = G.smoothstep(0.4, 0.24, r) * (1 - hole_m)                        # goły metal (zdarta farba)
        rust = G.smoothstep(0.85, 0.45, r) * (1 - bare) * (1 - hole_m) * (0.6 + 0.5 * nz)
        steel = np.array((0.62, 0.61, 0.59), np.float32)
        rc = np.array((0.30, 0.15, 0.07), np.float32)
        alb = steel[None, None, :] * bare[..., None] + rc * rust[..., None] + np.array(CORE, np.float32) * hole_m[..., None]
        tot = np.maximum(bare + rust + hole_m, 1e-4)
        alb = alb / tot[..., None]
        alpha = np.clip(hole_m + bare * 0.95 + rust * 0.5, 0, 1)
        h = 0.6 - 0.3 * dent - 0.3 * hole_m + 0.05 * G.smoothstep(0.5, 0.62, r) * G.smoothstep(0.8, 0.62, r)   # wywinięty brzeg
        rough = 0.35 + 0.6 * (1 - bare)
        metal = bare * 0.95
    alpha = np.clip(alpha, 0, 1) * fade_edge(r0)
    return pack(alb, alpha, h, rough, metal, ns=3.0)


# ---------------------------------------------------------------- rysa rykoszetu (wydłużona wzdłuż X)

def graze(kind, v):
    n = HOLE_RES
    rng = np.random.default_rng(seed_of("graze_%s_%d" % (kind, v)))
    x, y = grid(n)
    s = seed_of(kind) + v * 211
    nz = noise(n, 10, s)
    L = 0.8 + 0.12 * rng.random()                                              # połowa długości
    t = np.clip((x + L) / (2 * L), 0, 1)                                       # 0 wlot → 1 wylot
    wid = 0.07 + 0.16 * np.clip(np.sin(t * math.pi), 0, 1) ** 0.7 * (0.6 + 0.4 * t)   # najszersza za środkiem
    d = np.abs(y + 0.03 * (nz - 0.5)) / np.maximum(wid, 1e-3)
    inside = (np.abs(x) < L).astype(np.float32)
    gouge = G.smoothstep(1.0, 0.55, d) * inside
    rim = G.smoothstep(1.6, 1.0, d) * (1 - gouge) * inside
    r0 = np.sqrt(x * x + y * y)
    h = 0.55 - 0.35 * gouge * (0.4 + 0.6 * t) + 0.05 * rim
    metal = np.zeros((n, n), np.float32)
    if kind == "metal":
        steel = np.array((0.78, 0.77, 0.74), np.float32)
        alb = np.broadcast_to(steel, (n, n, 3)).astype(np.float32) * (0.9 + 0.2 * nz[..., None])
        alpha = gouge * 0.95 + rim * 0.25
        metal = gouge * 0.95
        rough = 0.3 + 0.6 * (1 - gouge)
    else:
        dust = np.array(DUST[kind], np.float32)
        alb = dust[None, None, :] * (0.9 + 0.25 * nz[..., None])
        alb = alb * (1 - 0.6 * gouge[..., None] * (1 - t[..., None]))         # wlot ciemniejszy
        alpha = gouge * 0.9 + rim * 0.35
        rough = np.full((n, n), 0.95, np.float32)
    alpha = np.clip(alpha, 0, 1) * fade_edge(r0, 0.9)
    return pack(alb, alpha, h, rough, metal, ns=2.5)


# ---------------------------------------------------------------- gniazdo śrutu

def cluster(kind, v):
    n = HOLE_RES
    rng = np.random.default_rng(seed_of("cluster_%s_%d" % (kind, v)))
    x, y = grid(n)
    r0 = np.sqrt(x * x + y * y)
    s = seed_of(kind) + v * 307
    nz = noise(n, 14, s)
    alb = np.zeros((n, n, 3), np.float32)
    alpha = np.zeros((n, n), np.float32)
    h = np.full((n, n), 0.55, np.float32)
    metal = np.zeros((n, n), np.float32)
    rough = np.full((n, n), 0.93, np.float32)
    base = {"concrete": DUST["concrete"], "rock": DUST["rock"], "dirt": (0.08, 0.06, 0.04), "wood": (0.66, 0.5, 0.32),
            "metal": (0.76, 0.75, 0.72)}[kind]
    col = np.array(base, np.float32)
    k = 7 + v * 2
    pts = []
    while len(pts) < k:
        p = rng.normal(0, 0.33, 2)
        if np.hypot(*p) < 0.72:
            pts.append(p)
    for p in pts:
        rr = np.hypot(x - p[0], y - p[1])
        sz = rng.uniform(0.07, 0.11)
        core = G.smoothstep(sz * 0.55, sz * 0.3, rr)
        ring = G.smoothstep(sz * 1.5, sz * 0.6, rr) * (1 - core)
        alpha = np.maximum(alpha, np.maximum(core, ring * (0.55 + 0.4 * nz)))
        h = h - 0.4 * core - 0.08 * ring
        alb = alb + (col[None, None, :] * ring[..., None] + np.array(CORE, np.float32) * core[..., None]) * (1 - np.clip(alpha - core - ring, 0, 1))[..., None]
        if kind == "metal":
            metal = np.maximum(metal, ring * 0.9)
            rough = np.minimum(rough, 0.95 - 0.6 * ring)
    covered = np.maximum(alpha, 1e-3)
    alb = np.clip(alb / np.maximum(alb.max(axis=2, keepdims=True) / np.maximum(col.max(), 0.1), 1.0), 0, 1)
    dust = G.smoothstep(0.95, 0.3, r0) * (0.15 + 0.15 * nz) * (kind != "dirt")    # pył całego gniazda
    alpha = np.clip(np.maximum(alpha, dust), 0, 1) * fade_edge(r0)
    alb = np.where(alpha[..., None] > covered[..., None] - 1e-4, alb, col[None, None, :])
    alb = np.where((alb.sum(axis=2) < 1e-3)[..., None], col[None, None, :], alb)
    return pack(alb, alpha, h, rough, metal, ns=2.5)


# ---------------------------------------------------------------- osmalenie wybuchu (E2)

def scorch(kind, v):
    n = SCORCH_RES
    rng = np.random.default_rng(seed_of("scorch_%s_%d" % (kind, v)))
    x, y = grid(n)
    r0 = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    s = seed_of(kind) + v * 401
    nz = noise(n, 5, s, 4)
    nz2 = noise(n, 18, s + 3)
    r = r0 / lobes(ang, 22, 0.72, 1.12, rng)
    # promienie sadzy: wybuch rozchlapuje się w smugi
    streak = G.fbm(n, 40, 1, 2, s + 11)[0]                                     # profil kątowy z jednej linii szumu
    idx = ((ang / (2 * math.pi)) % 1.0 * (n - 1)).astype(int)
    rays = streak[idx]
    soot_r = 0.62 + 0.3 * rays
    soot = G.smoothstep(soot_r, soot_r * 0.25, r) * (0.75 + 0.35 * nz)
    core = G.smoothstep(0.32, 0.1, r)
    pocks = np.zeros((n, n), np.float32)
    for k in range(70 + 20 * v):                                               # dziobaki odłamków w pierścieniu
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.18, 0.92) ** 0.8
        px, py = math.cos(a) * d, math.sin(a) * d
        rr = np.hypot(x - px, y - py)
        sz = rng.uniform(0.008, 0.022)
        pocks = np.maximum(pocks, G.smoothstep(sz, sz * 0.4, rr))
    h = np.full((n, n), 0.55, np.float32)
    metal = np.zeros((n, n), np.float32)
    rough = np.full((n, n), 0.96, np.float32)
    soot_c = np.array((0.018, 0.016, 0.014), np.float32)
    if kind == "dirt":                                                         # krater: misa, wał, wyrzucona ziemia
        bowl = G.smoothstep(0.55, 0.0, r)
        lip = G.smoothstep(0.42, 0.62, r) * G.smoothstep(0.95, 0.65, r) * (0.6 + 0.6 * nz2)
        h = 0.6 - 0.45 * bowl ** 0.8 + 0.2 * lip
        soil = np.array((0.2, 0.15, 0.1), np.float32)
        thrown = (nz2 > 0.58) * G.smoothstep(1.0, 0.55, r) * (1 - bowl)
        alb = soil[None, None, :] * (0.8 + 0.4 * nz2[..., None])
        sootm = np.clip(soot * 0.85 + core * 0.3, 0, 1)
        alb = alb * (1 - sootm[..., None]) + soot_c * sootm[..., None]
        alpha = np.clip(np.maximum(np.maximum(bowl * 0.95, lip * 0.8), np.maximum(sootm, thrown * 0.7)), 0, 1)
    else:
        spall = G.smoothstep(0.3, 0.05, r) * (0.7 + 0.5 * nz2) if kind in ("concrete", "rock") else np.zeros((n, n), np.float32)
        dent = G.smoothstep(0.5, 0.0, r) if kind == "metal" else np.zeros((n, n), np.float32)
        h = 0.55 - 0.25 * spall - 0.2 * dent - 0.25 * pocks
        sootm = np.clip(soot + core * 0.2, 0, 1)
        if kind == "wood":
            char = G.smoothstep(0.55, 0.15, r) * (0.7 + 0.5 * nz2)                 # zwęglenie: łuski spękane w poprzek słojów
            cracks = (np.abs(np.sin(x * 38 + nz * 6)) < 0.18) * char
            h = h - 0.12 * cracks
            sootm = np.clip(sootm + char * 0.3, 0, 1)
        dust = np.array(DUST.get(kind, (0.4, 0.38, 0.35)), np.float32)
        if kind == "metal":
            dust = np.array((0.6, 0.58, 0.55), np.float32)
        alb = soot_c * (1 - spall[..., None]) + dust * 0.75 * spall[..., None]
        pk = pocks * (1 - core)
        alb = alb * (1 - pk[..., None]) + (dust * 0.85) * pk[..., None]       # świeże dziobaki jaśniejsze od sadzy
        alpha = np.clip(np.maximum(sootm * 0.92, np.maximum(spall, pk * 0.9)), 0, 1)
        if kind == "metal":
            metal = pk * 0.9
            rough = rough - 0.5 * pk
    alpha = alpha * fade_edge(r0, 0.8)
    em = np.clip(core * (0.6 + 0.8 * nz2) - 0.25, 0, 1) * (kind != "metal" or True)   # żarzące się żyłki w środku (emisja, E2)
    m = pack(alb, alpha, h, rough, metal, ns=2.0)
    m["emission"] = em
    return m


def pock(v):
    n = 64
    rng = np.random.default_rng(seed_of("pock_%d" % v))
    x, y = grid(n)
    r0 = np.sqrt(x * x + y * y)
    alpha = np.zeros((n, n), np.float32)
    h = np.full((n, n), 0.55, np.float32)
    for k in range(3 + v):
        p = rng.normal(0, 0.35, 2)
        rr = np.hypot(x - p[0], y - p[1])
        sz = rng.uniform(0.12, 0.2)
        c = G.smoothstep(sz, sz * 0.35, rr)
        alpha = np.maximum(alpha, c)
        h = h - 0.35 * c
    alb = np.broadcast_to(np.array((0.1, 0.09, 0.085), np.float32), (n, n, 3)).copy()
    alpha = alpha * fade_edge(r0, 0.8)
    return pack(alb, alpha, h, np.full((n, n), 0.95, np.float32), np.zeros((n, n), np.float32), ns=2.0)


# ---------------------------------------------------------------- zapis

def to8(a):
    return (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def save(name, m, out):
    alb = np.clip(m["albedo"], 0, 1)
    Image.fromarray(to8(np.dstack([alb, m["alpha"][..., None]]))).save(os.path.join(out, name + "_albedo.png"))
    nrm = G.normal_from_height(m["height"], m["ns"])
    Image.fromarray(to8(nrm)).save(os.path.join(out, name + "_normal.png"))
    orm = np.dstack([m["ao"], m["roughness"], m["metallic"]])
    Image.fromarray(to8(orm)).save(os.path.join(out, name + "_orm.png"))
    if "emission" in m:
        e = m["emission"][..., None] * np.array((1.0, 0.42, 0.12), np.float32)
        Image.fromarray(to8(e)).save(os.path.join(out, name + "_emission.png"))
    return alb, nrm


def preview(items, out, cell=128):
    """Stykówka: każdy ślad na szarym tle, oświetlony z lewej góry (normalna), do akceptacji."""
    cols = 8
    rows = (len(items) + cols - 1) // cols
    sheet = np.full((rows * cell, cols * cell, 3), 0.42, np.float32)
    L = np.array((-0.5, 0.6, 0.62), np.float32)
    L /= np.linalg.norm(L)
    for i, (name, m) in enumerate(items):
        alb = np.clip(m["albedo"], 0, 1)
        nrm = G.normal_from_height(m["height"], m["ns"]) * 2 - 1
        sh = np.clip((nrm * L).sum(axis=2), 0, 1)[..., None] * 0.9 + 0.25
        bg = np.full_like(alb, 0.42) * (np.clip((np.array((0, 0, 1.0)) * L).sum(), 0, 1) * 0.9 + 0.25)
        a = m["alpha"][..., None]
        col = bg * (1 - a) + alb * sh * a
        col = col * (1 - a) + col * a                                          # normalna działa też pod pełnym kryciem
        img = Image.fromarray(to8(col)).resize((cell, cell), Image.LANCZOS)
        r, c = divmod(i, cols)
        sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = np.asarray(img, np.float32) / 255.0
    Image.fromarray(to8(sheet)).save(os.path.join(out, "_preview.png"))


def all_marks():
    items = []
    for k in HOLE_KINDS:
        for v in range(HOLE_VARIANTS):
            items.append(("hole_%s_%d" % (k, v), lambda k=k, v=v: hole(k, v)))
    for k in GRAZE_KINDS:
        for v in range(GRAZE_VARIANTS):
            items.append(("graze_%s_%d" % (k, v), lambda k=k, v=v: graze(k, v)))
    for k in CLUSTER_KINDS:
        for v in range(CLUSTER_VARIANTS):
            items.append(("cluster_%s_%d" % (k, v), lambda k=k, v=v: cluster(k, v)))
    for k in SCORCH_KINDS:
        for v in range(SCORCH_VARIANTS):
            items.append(("scorch_%s_%d" % (k, v), lambda k=k, v=v: scorch(k, v)))
    for v in range(POCK_VARIANTS):
        items.append(("pock_%d" % v, lambda v=v: pock(v)))
    return items


def main():
    a = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    out = next((x.split("=", 1)[1] for x in a if x.startswith("--out=")), os.path.join(here, "..", "art", "world3d", "marks"))
    only = next((x.split("=", 1)[1].split(",") for x in a if x.startswith("--only=")), None)
    os.makedirs(out, exist_ok=True)
    done = []
    for name, fn in all_marks():
        if only and not any(name.startswith(o) for o in only):
            continue
        m = fn()
        save(name, m, out)
        done.append((name, m))
    if "--preview" in a:
        prev = next((x.split("=", 1)[1] for x in a if x.startswith("--preview=")), None) or out
        os.makedirs(prev, exist_ok=True)
        preview(done, prev)
    print("OK %d śladów -> %s" % (len(done), os.path.abspath(out)))


if __name__ == "__main__":
    main()
