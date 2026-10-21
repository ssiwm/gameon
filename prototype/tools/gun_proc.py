"""Broń 3D budowana skryptem zamiast generatora AI: bryły z fazami (proste lufy, ostre krawędzie) + materiały proceduralne wypieczone do PBR.
Bronie (klucze jak w weapon_def): m83, spread12, p64, srut8, lr7, hkm9, gniew4, sokol6, widmo1, ciegno6, maczeta, kilof.

Uruchomienie (z korzenia repo):
    blender -b --factory-startup -P prototype/tools/gun_proc.py -- p64 prototype/art/char3d/gun_p64.glb [--length=M] [--tex=2048] [--samples=48] [--dust=1] [--nobake]
    --length = długość broni w metrach; domyślnie naturalna względem postaci 1,8 m (np. p64 = P-83 0,19, spread12 1,0); --nobake = sama siatka z szarym
    materiałem (szybki podgląd brył). Wszystkie naraz: tools/gun_proc_all.sh.
Model powstaje w milimetrach (lufa w +X, góra w +Z, lewa strona broni w +Y), na końcu jest skalowany do --length i przesuwany tak, by początek układu
wypadł w nadgarstku dłoni tylnej — jak w prep_gun3d.py (char3d.gd ustawia dłoń wzdłuż osi „góra" broni, sięga od nadgarstka ok. 0,2 m).
Obok GLB powstaje <nazwa>.json: {"hands", "length", "rear", "fore", "muzzle", "grip", "hold"[, "hold_v"]}; `rear` / `fore` to nadgarstki pod chwytem
i łożem (stary układ dłoni), `grip` = środek chwytu, który obejmuje dłoń tylna, `hold` = punkt na spodzie łoża, pod który podchodzi dłoń przednia
(`hold_v` = chwyt przedni pionowy, obejmowany z boku). --json-only przelicza sam plik .json (bez wypieku i bez zapisu GLB).
Podzespoły i części (od 1.7.320, GUNSMITH_PLAN.md etap 2b): bryły zbudowane w `with comp("mag"):` (magazynek, kolba, przód z lufą, urządzenie
wylotowe…) trafiają do osobnych węzłów GLB `gun_<klucz>__<podzespół>` — ten sam wypiek i materiał, ale gra może je ukryć, gdy część je zastępuje.
    blender -b --factory-startup -P prototype/tools/gun_proc.py -- m83 prototype/art/char3d/gunpart_m83_pbs1.glb --part=m83_pbs1 [--tex=1024]
buduje część (PART_BUILDERS) w układzie broni (mocowanie „frame”) albo względem wylotu (mocowanie „muzzle”: tłumik, płomieniotłumik — siedzą na
końcu takiej lufy, jaka jest założona). Obok GLB powstaje .json {"mount", "hides", "muzzle" (nowy wylot lufy), "muzzle_add" (o ile część
wydłuża broń za wylotem, m)}; skala i początek układu są te same co broni bazowej. Wszystkie części: tools/gun_parts_all.sh.
Tekstury (kolor, normalne, ORM) wypieka Cycles z węzłów: przetarcia oksydy na wypukłych krawędziach (AO „do środka"), brud we wnękach (AO), rysy,
słoje drewna, rowki, kratka i grawerowane napisy jako wypukłości w mapie normalnych; broń energetyczna dostaje też mapę emisji (ogniwa, cewki,
płomyk). Siatka zostaje lekka — detal siedzi w teksturach. Stal jest malowana pod pełną metaliczność (kolor bazowy = barwa odbicia): w grze odbija
„niebo odbić" warstwy graczy i sondę przy stojakach. Części niemetalowe mają wypieczone cieniowanie pomocnicze (jaśniejsze płaszczyzny górne,
rozjaśnione krawędzie, przyciemnione wnęki), a wszystko — kurz, plamy i zacieki.
"""
import json
import math
import sys
from contextlib import contextmanager

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
KEY, DST = argv[0], argv[1]


def _opt(name, default, cast):
    return cast(next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default))


LENGTH = _opt("length", 0.0, float)          # 0 = długość domyślna danej broni
TEX = _opt("tex", 2048, int)
SAMPLES = _opt("samples", 48, int)
NOBAKE = "--nobake" in argv
JSON_ONLY = "--json-only" in argv
PART = _opt("part", "", str)                 # id części (parts.gd) — budujemy ją zamiast broni
DUST = _opt("dust", 1.0, float)              # siła kurzu i brudu (0 = broń prosto z magazynu)

OBJS = []          # części modelu (po zbudowaniu łączone w jedną siatkę)
CUTTERS = []       # bryły pomocnicze do wycięć (usuwane)
MATS = {}          # nazwa materiału → gniazda i węzły przebiegów wypieku
GLOW = []          # niepuste, gdy któryś materiał świeci (wtedy wypiekana jest mapa emisji)
WEAR_MM = [1.6]    # zasięg przetarcia krawędzi stali w mm (mała broń ustawia mniejszy)
COMP = ["body"]    # bieżący podzespół (with comp(...)) — bryły dostają go jako atrybut ścian i trafiają do osobnego węzła GLB
COMP_NAMES = ["body"]


@contextmanager
def comp(name):
    """Bryły zbudowane w tym bloku należą do podzespołu `name` (osobny węzeł GLB, gra może go ukryć albo przesunąć)."""
    if name not in COMP_NAMES:
        COMP_NAMES.append(name)
    COMP.append(name)
    try:
        yield
    finally:
        COMP.pop()


# ---------------------------------------------------------------- krzywe i obrysy (płaszczyzna XZ)

def fillet(pts, seg_deg=15.0):
    """Wielokąt [(x, z, r)] → [(x, z)] z narożami zaokrąglonymi promieniem r (0 albo brak = ostre)."""
    out = []
    n = len(pts)
    for i in range(n):
        p = Vector(pts[i][:2])
        r = pts[i][2] if len(pts[i]) > 2 else 0.0
        u = Vector(pts[i - 1][:2]) - p
        v = Vector(pts[(i + 1) % n][:2]) - p
        lu, lv = u.length, v.length
        if r <= 0.0 or lu < 1e-6 or lv < 1e-6:
            out.append((p.x, p.y))
            continue
        u /= lu
        v /= lv
        ang = math.acos(max(-1.0, min(1.0, u.dot(v))))
        if ang > math.pi - 1e-3:
            out.append((p.x, p.y))
            continue
        t = min(r / math.tan(ang / 2.0), 0.48 * lu, 0.48 * lv)
        r2 = t * math.tan(ang / 2.0)
        c = p + (u + v).normalized() * (r2 / math.sin(ang / 2.0))
        s, e = p + u * t, p + v * t
        a0 = math.atan2(s.y - c.y, s.x - c.x)
        d = math.atan2(e.y - c.y, e.x - c.x) - a0
        while d > math.pi:
            d -= 2.0 * math.pi
        while d < -math.pi:
            d += 2.0 * math.pi
        k = max(1, math.ceil(abs(d) / math.radians(seg_deg)))
        for j in range(k + 1):
            a = a0 + d * j / k
            out.append((c.x + r2 * math.cos(a), c.y + r2 * math.sin(a)))
    return out


def spline(pts, n=6):
    """Krzywa Catmulla-Roma przez punkty (x, z) albo (x, y, z); n odcinków między kolejnymi punktami."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(n):
            t = j / n
            out.append(tuple(0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t ** 3) for k in range(len(p1))))
    out.append(tuple(pts[-1]))
    return out


def strip(path, th):
    """Łamana (x, z) pogrubiona do obrysu; th = grubość stała albo funkcja położenia 0..1 wzdłuż łamanej."""
    left, right = [], []
    n = len(path)
    for i, p in enumerate(path):
        a = Vector(path[max(i - 1, 0)])
        b = Vector(path[min(i + 1, n - 1)])
        t = (b - a).normalized()
        nrm = Vector((-t.y, t.x))
        h = (th(i / (n - 1)) if callable(th) else th) * 0.5
        left.append(tuple(Vector(p) + nrm * h))
        right.append(tuple(Vector(p) - nrm * h))
    return left + right[::-1]


def hull(pts):
    """Otoczka wypukła punktów (x, z)."""
    pts = sorted(set(pts))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def circle(cx, cz, r, n=20):
    return [(cx + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def dome_sec(w, zb, zs, rt, n=12):
    """Przekrój (y, z): płaskie boki ±w od zb do zs, nad nimi wypukły grzbiet o wysokości rt (zamek pistoletu, komora zamkowa)."""
    ring = [(-w, zb), (w, zb)]
    for i in range(n + 1):
        t = math.pi * i / n
        c, sn = math.cos(t), math.sin(t)
        ring.append((w * math.copysign(abs(c) ** 0.8, c), zs + rt * sn ** 0.8))
    return ring


def oval_sec(w, zc, h, n=20, pw=0.8):
    """Przekrój (y, z) owalny (kolba): półszerokość w, środek zc, półwysokość h."""
    out = []
    for i in range(n):
        t = 2.0 * math.pi * i / n
        c, sn = math.cos(t), math.sin(t)
        out.append((w * math.copysign(abs(c) ** pw, c), zc + h * math.copysign(abs(sn) ** pw, sn)))
    return out


def curve_fn(pts, n=8):
    """Funkcja z(x) po gładkiej krzywej przez punkty (x rosnące)."""
    cv = spline(pts, n)

    def f(x):
        for (x0, z0), (x1, z1) in zip(cv, cv[1:]):
            if x <= x1:
                return z0 + (z1 - z0) * max(0.0, min(1.0, (x - x0) / max(x1 - x0, 1e-6)))
        return cv[-1][1]
    return f


# ---------------------------------------------------------------- bryły

def _mk(name, verts, faces, mat, part=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    ob["comp"] = COMP[-1]
    (OBJS if part else CUTTERS).append(ob)
    return ob


def bevel(ob, width, seg=2, angle=28.0):
    """Faza na krawędziach ostrzejszych niż `angle` + normalne ważone polem ścian (płaskie ściany zostają płaskie)."""
    if width > 0.0:
        bv = ob.modifiers.new("bv", "BEVEL")
        bv.width = width
        bv.segments = seg
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(angle)
        bv.face_strength_mode = "FSTR_ALL"                       # ściany pierwotne „mocne", ściany fazy „słabe"
    else:
        ob.data.set_sharp_from_angle(angle=math.radians(angle))  # bez fazy: krawędzie ostrzejsze niż `angle` zostają ostre
    wn = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    wn.weight = 100
    wn.use_face_influence = width > 0.0                          # normalne płaskich ścian nie uciekają ku fazie (bez smug na dużych wielokątach)
    return ob


def cut(ob, cutter):
    md = ob.modifiers.new("cut", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.object = cutter
    return ob


def prism(name, prof, y0, y1, mat, bv=0.5, seg=2, part=True):
    """Obrys (x, z) wyciągnięty wzdłuż Y."""
    n = len(prof)
    verts = [(x, y0, z) for x, z in prof] + [(x, y1, z) for x, z in prof]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    ob = _mk(name, verts, faces, mat, part)
    return bevel(ob, bv, seg) if bv is not None else ob


def loft(name, secs, mat):
    """Przekroje [(x, [(y, z), …])] o tej samej liczbie punktów połączone wzdłuż X (końce zamknięte). Bez modyfikatorów — dodaj bevel()."""
    m = len(secs[0][1])
    verts = [(x, y, z) for x, ring in secs for y, z in ring]
    faces = [list(range(m)), list(range(len(secs) * m - 1, (len(secs) - 1) * m - 1, -1))]
    for s in range(len(secs) - 1):
        faces += [(s * m + i, s * m + (i + 1) % m, (s + 1) * m + (i + 1) % m, (s + 1) * m + i) for i in range(m)]
    return _mk(name, verts, faces, mat)


def revolve(name, prof, c, mat, axis="X", seg=24, bv=0.0, bseg=1, part=True):
    """Bryła obrotowa: obrys [(położenie na osi, promień)] wokół osi X, Y albo Z przechodzącej przez c (dwie pozostałe współrzędne)."""
    verts, faces = [], []
    for u, r in prof:
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            if axis == "X":
                verts.append((u, c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
            elif axis == "Y":
                verts.append((c[0] + r * math.cos(a), u, c[1] + r * math.sin(a)))
            else:
                verts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a), u))
    for i in range(len(prof) - 1):
        faces += [(i * seg + j, i * seg + (j + 1) % seg, (i + 1) * seg + (j + 1) % seg, (i + 1) * seg + j) for j in range(seg)]
    ob = _mk(name, verts, faces, mat, part)
    return bevel(ob, bv, bseg) if bv is not None else ob


def cyl(name, x0, x1, r, c, mat, seg=20, bv=0.4, r1=None, bseg=1):
    """Walec (albo stożek ścięty r → r1) wzdłuż X o osi w (y, z) = c."""
    return revolve(name, [(x0, 0.0), (x0, r), (x1, r if r1 is None else r1), (x1, 0.0)], c, mat, seg=seg, bv=bv, bseg=bseg)


def barrel(name, x0, x1, r, bore, c, mat, bore_mat, depth=30.0, seg=20):
    """Lufa z kanałem: walec z otworem od czoła x1 (ściany kanału dostają materiał bore_mat)."""
    ob = revolve(name, [(x0, 0.0), (x0, r), (x1, r), (x1, bore), (x1 - depth, bore), (x1 - depth, 0.0)], c, mat, seg=seg, bv=0.35, bseg=1)
    if bore_mat is not None:
        ob.data.materials.append(bore_mat)
        for q in ob.data.polygons:
            if q.center.x < x1 - 0.3 and math.hypot(q.center.y - c[0], q.center.z - c[1]) < bore + 0.1:
                q.material_index = 1
    return ob


def box(name, x0, x1, z0, z1, w, mat, bv=0.8, seg=2, r=0.0, y=0.0):
    """Prostopadłościan: prostokąt w XZ o narożach r, szerokość ±w wokół y."""
    return prism(name, fillet([(x0, z0, r), (x1, z0, r), (x1, z1, r), (x0, z1, r)]), y - w, y + w, mat, bv=bv, seg=seg)


def pipe(name, path, r, mat, seg=8, smooth=4):
    """Rura / przewód / pręt wzdłuż łamanej 3D (wygładzanej krzywą, gdy smooth > 0)."""
    pts = [Vector(q) for q in (spline(path, smooth) if smooth else path)]
    verts, faces = [], []
    for i, q in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = Vector((0.0, 1.0, 0.0)) if abs(t.y) < 0.9 else Vector((0.0, 0.0, 1.0))
        n1 = t.cross(ref).normalized()
        n2 = t.cross(n1).normalized()
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            verts.append(tuple(q + (n1 * math.cos(a) + n2 * math.sin(a)) * r))
    k = len(pts)
    faces += [list(range(seg)), list(range(k * seg - 1, (k - 1) * seg - 1, -1))]
    for i in range(k - 1):
        faces += [(i * seg + j, i * seg + (j + 1) % seg, (i + 1) * seg + (j + 1) % seg, (i + 1) * seg + j) for j in range(seg)]
    return bevel(_mk(name, verts, faces, mat), 0.0)


def oval_loft(name, x0, x1, top, bot, wid, mat, n=24, bv=1.0):
    """Bryła o owalnych przekrojach (kolba, łoże, trzonek) wzdłuż linii grzbietu top(x), spodu bot(x) i półszerokości wid(x)."""
    secs = []
    for i in range(n):
        xs = x0 + (x1 - x0) * i / (n - 1)
        secs.append((xs, oval_sec(wid(xs), 0.5 * (top(xs) + bot(xs)), 0.5 * (top(xs) - bot(xs)))))
    return bevel(loft(name, secs, mat), bv, 2)


def helix(p0, p1, r, turns, n=10):
    """Punkty przewodu spiralnego od p0 do p1 (promień r zwęża się na końcach)."""
    a, b = Vector(p0), Vector(p1)
    ax = b - a
    t = ax.normalized()
    u = t.cross(Vector((0.0, 1.0, 0.0)) if abs(t.y) < 0.9 else Vector((0.0, 0.0, 1.0))).normalized()
    v = t.cross(u)
    k = int(turns * n)
    out = []
    for i in range(k + 1):
        f = i / k
        rr = r * min(1.0, f * turns, (1.0 - f) * turns)
        out.append(tuple(a + ax * f + (u * math.cos(2.0 * math.pi * turns * f) + v * math.sin(2.0 * math.pi * turns * f)) * rr))
    return out


def swivel(cx, cz, mat, r=8.0):
    """Strzemiączko pasa: otwarta pętla z drutu zawieszona w (cx, cz + r)."""
    loop = [(cx + r * math.sin(math.radians(a)), cz + r * math.cos(math.radians(a))) for a in range(20, 341, 20)]
    return prism("swivel", strip(loop, 2.6), -1.7, 1.7, mat, bv=0.5, seg=1)


def pgrip(name, xt, zt, mat, h=92.0, rake=20.0, d=36.0, w=13.0):
    """Chwyt pistoletowy pochylony w tył; (xt, zt) = przód jego górnej krawędzi (spód komory)."""
    return prism(name, fillet([(xt, zt + 6.0, 3.2), (xt - d, zt + 6.0, 3.2), (xt - d - rake, zt - h, 7.0), (xt - rake - 5.0, zt - h, 5.0),
                               (xt - 2.0, zt - 14.0, 6.0)]), -w, w, mat, bv=2.5, seg=2)


def trig(name, x0, x1, z, mat, mat_s, depth=30.0):
    """Kabłąk od x0 do x1 pod linią z i język spustu (język — osobny podzespół „trigger”: strzelnica FPP go ściąga)."""
    path = spline([(x0, z + 3.0), (x0 + 2.0, z - depth * 0.55), (x0 + 12.0, z - depth), ((x0 + x1) * 0.5, z - depth - 2.0), (x1 - 10.0, z - depth),
                   (x1, z - depth * 0.5), (x1 + 1.0, z + 3.0)], 5)
    prism(name + "_guard", strip(path, 3.6), -5.5, 5.5, mat, bv=0.9, seg=2)
    xm = x0 + (x1 - x0) * 0.6
    with comp("trigger"):
        prism(name, strip(spline([(xm, z + 2.0), (xm + 1.0, z - depth * 0.35), (xm + 4.0, z - depth * 0.62), (xm + 8.5, z - depth * 0.8)], 5),
                          lambda t: 5.0 - 2.4 * t), -3.0, 3.0, mat_s, bv=0.8, seg=2)


def pins(name, pts, w, mat, r=2.5):
    """Sworznie / nity przez całą szerokość ±w w punktach (x, z)."""
    for cx, cz in pts:
        revolve(name, [(-w - 0.4, 0.0), (-w - 0.4, r), (w + 0.4, r), (w + 0.4, 0.0)], (cx, cz), mat, axis="Y", seg=12, bv=0.25)


# ---------------------------------------------------------------- materiały proceduralne

class G:
    """Skrót do budowy węzłów: argumentem jest liczba / krotka albo gniazdo innego węzła."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        self.N = self.nt.nodes
        self.L = self.nt.links

    def put(self, inp, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.L.new(v, inp)
        else:
            inp.default_value = v

    def m(self, op, a, b=0.0, c=0.0):
        n = self.N.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b, c)):
            self.put(n.inputs[i], v)
        return n.outputs[0]

    def add(self, *v):
        out = v[0]
        for x in v[1:]:
            out = self.m("ADD", out, x)
        return out

    def mul(self, *v):
        out = v[0]
        for x in v[1:]:
            out = self.m("MULTIPLY", out, x)
        return out

    def inv(self, v):
        return self.m("SUBTRACT", 1.0, v)

    def sstep(self, v, lo, hi, t0=0.0, t1=1.0):
        n = self.N.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        for k, x in (("Value", v), ("From Min", lo), ("From Max", hi), ("To Min", t0), ("To Max", t1)):
            self.put(n.inputs[k], x)
        return n.outputs["Result"]

    def box(self, v, lo, hi, soft=0.3):
        return self.mul(self.sstep(v, lo - soft, lo + soft), self.inv(self.sstep(v, hi - soft, hi + soft)))

    def tri(self, v):
        """Fala trójkątna 0..1 o okresie 1 (0 w całkowitych, 1 w połowie)."""
        return self.m("SUBTRACT", 1.0, self.m("MULTIPLY", self.m("ABSOLUTE", self.m("SUBTRACT", self.m("FRACT", v), 0.5)), 2.0))

    def mixc(self, fac, a, b):
        n = self.N.new("ShaderNodeMix")
        n.data_type = "RGBA"
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def mixf(self, fac, a, b):
        n = self.N.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        self.put(n.inputs[0], fac)
        self.put(n.inputs[2], a)
        self.put(n.inputs[3], b)
        return n.outputs[0]

    def noise(self, vec, scale, detail=3.0, rough=0.5, dist=0.0):
        n = self.N.new("ShaderNodeTexNoise")
        self.L.new(vec, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        return n.outputs[0]

    def mapping(self, vec, scale=(1.0, 1.0, 1.0), rot=(0.0, 0.0, 0.0)):
        n = self.N.new("ShaderNodeMapping")
        self.L.new(vec, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Rotation"].default_value = rot
        return n.outputs[0]

    def scale(self, col, k):
        n = self.N.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self.L.new(col, n.inputs[0])
        self.put(n.inputs["Scale"], k)
        return n.outputs[0]

    def dist(self, x, z, cx, cz):
        return self.m("SQRT", self.add(self.m("POWER", self.m("SUBTRACT", x, cx), 2.0), self.m("POWER", self.m("SUBTRACT", z, cz), 2.0)))

    def rrect(self, x, z, x0, x1, z0, z1, r):
        """Odległość ze znakiem od prostokąta o zaokrąglonych narożach (ujemna w środku); r = połowa boku daje koło."""
        dx = self.m("SUBTRACT", self.m("ABSOLUTE", self.m("SUBTRACT", x, (x0 + x1) * 0.5)), (x1 - x0) * 0.5 - r)
        dz = self.m("SUBTRACT", self.m("ABSOLUTE", self.m("SUBTRACT", z, (z0 + z1) * 0.5)), (z1 - z0) * 0.5 - r)
        out = self.m("SQRT", self.add(self.m("POWER", self.m("MAXIMUM", dx, 0.0), 2.0), self.m("POWER", self.m("MAXIMUM", dz, 0.0), 2.0)))
        return self.m("SUBTRACT", self.add(out, self.m("MINIMUM", self.m("MAXIMUM", dx, dz), 0.0)), r)

    def xyz(self, vec):
        n = self.N.new("ShaderNodeSeparateXYZ")
        self.L.new(vec, n.inputs[0])
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def ao(self, dist, inside=False, samples=8):
        n = self.N.new("ShaderNodeAmbientOcclusion")
        n.inside = inside
        n.samples = samples
        n.inputs["Distance"].default_value = dist
        return n.outputs["AO"]


def rgb(r, g, b):
    return (r, g, b, 1.0)


def _finish_mat(m, g, color, rough, metal, height, occl, emit=None, shade=True):
    """Wspólny koniec materiału: cieniowanie pomocnicze i kurz w kolorze (shade), potem przebiegi wypieku (kolor / ORM przez Emission, normalne
    przez BSDF z węzłem Bump)."""
    N, L = g.N, g.L
    if not isinstance(color, bpy.types.NodeSocket):              # stały kolor → węzeł, żeby dało się go podpiąć do przebiegu wypieku
        cn = N.new("ShaderNodeRGB")
        cn.outputs[0].default_value = color
        color = cn.outputs[0]
    if shade:
        geo = N.new("ShaderNodeNewGeometry")
        _, _, nz = g.xyz(geo.outputs["Normal"])
        cav = g.sstep(occl, 0.25, 0.9)                                                  # 0 we wnękach, 1 na otwartej powierzchni
        edge = g.mul(g.inv(g.ao(1.2, inside=True, samples=8)), cav)                     # wypukłe krawędzie łapią światło
        up = g.sstep(nz, -0.7, 0.9)
        pos = geo.outputs["Position"]
        blot = g.noise(pos, 0.045, 5.0, 0.7)                                             # plamy smaru i wytarcia od rąk
        drip = g.sstep(g.noise(g.mapping(pos, scale=(0.5, 0.5, 0.035)), 1.0, 3.0), 0.55, 0.8)   # pionowe zacieki
        # metal odbija w grze prawdziwe otoczenie (niebo odbić warstwy graczy, sonda przy stojakach), więc dostaje tylko ślad gradientu
        k = g.add(g.mixf(metal, g.mixf(up, 0.6, 1.12), g.mixf(up, 0.9, 1.0)), g.mul(edge, g.mixf(metal, 0.6, 0.3)))
        k = g.mul(k, g.mixf(cav, 0.4, 1.0), g.add(0.78, g.mul(blot, 0.44)), g.inv(g.mul(drip, 0.22)))
        rough = g.add(rough, g.mul(g.m("SUBTRACT", blot, 0.5), 0.22), g.mul(drip, 0.12))
        dust = g.mul(g.add(g.mul(g.sstep(nz, 0.3, 0.95), 0.55), g.mul(g.inv(cav), 0.7)), g.sstep(g.noise(geo.outputs["Position"], 0.11, 4.0, 0.6), 0.35, 0.7),
                     DUST)
        color = g.mixc(g.mul(dust, 0.5), g.scale(color, k), rgb(0.16, 0.13, 0.1))
        rough = g.mixf(g.mul(dust, 0.6), rough, 0.9)
        metal = g.mul(metal, g.inv(g.mul(dust, 0.7)))
    bump = N.new("ShaderNodeBump")
    bump.inputs["Distance"].default_value = 1.0
    bump.inputs["Strength"].default_value = 1.0
    g.put(bump.inputs["Height"], height)
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    g.put(bsdf.inputs["Base Color"], color)
    g.put(bsdf.inputs["Roughness"], rough)
    g.put(bsdf.inputs["Metallic"], metal)
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    orm = N.new("ShaderNodeCombineColor")
    g.put(orm.inputs[0], occl)
    g.put(orm.inputs[1], rough)
    g.put(orm.inputs[2], metal)
    emi = N.new("ShaderNodeEmission")
    out = N.new("ShaderNodeOutputMaterial")
    tex = N.new("ShaderNodeTexImage")
    en = N.new("ShaderNodeRGB")                                  # świecenie (czarne, gdy materiał nie świeci)
    en.outputs[0].default_value = emit or (0.0, 0.0, 0.0, 1.0)
    if emit:
        GLOW.append(m.name)
    MATS[m.name] = {"mat": m, "color": color, "orm": orm.outputs[0], "emit": en.outputs[0], "emi": emi, "bsdf": bsdf, "out": out, "tex": tex}
    return m


def _grooves(g, x, z, side, grooves, col, rough, height):
    """Rowki w mapie normalnych: [(oś 'x'|'z', podziałka mm, x0, x1, z0, z1, głębokość mm, tylko boki)]. Zwraca (kolor, chropowatość, wysokość)."""
    for axis, pitch, x0, x1, z0, z1, depth, side_only in grooves:
        mask = g.mul(g.box(x, x0, x1), g.box(z, z0, z1))
        if side_only:
            mask = g.mul(mask, side)
        ridge = g.tri(g.m("DIVIDE", x if axis == "x" else z, pitch))                   # 1 na grzbiecie, 0 na dnie rowka
        dip = g.mul(g.inv(g.sstep(ridge, 0.15, 0.7)), mask)
        height = g.add(height, g.mul(dip, -depth))
        col = g.mixc(g.mul(dip, 0.6), col, rgb(0.012, 0.012, 0.012))
        rough = g.add(rough, g.mul(dip, 0.15))
    return col, rough, height


def _feats(g, x, z, side, feats, col, rough, height):
    """Detale tłoczone i wiercone na bokach, rysowane w mapie normalnych i kolorze:
    ("pocket" | "ridge", x0, x1, z0, z1, r, mm) — przetłoczenie w głąb / żebro; ("slot", x0, x1, z0, z1, r, mm) — otwór na wylot (czarny);
    ("seam", x0, x1, z0, z1, r, szer.) — szczelina wzdłuż obrysu (r = połowa boku: okrąg); ("rivet" | "hole", cx, cz, r) — łeb nitu / otwór."""
    dark = rgb(0.006, 0.006, 0.006)
    for f in feats:
        if f[0] in ("rivet", "hole"):
            _, cx, cz, r = f
            d = g.dist(x, z, cx, cz)
            inside = g.mul(g.inv(g.sstep(d, r - 0.6, r + 0.2)), side)
            ring = g.mul(g.inv(g.sstep(g.m("ABSOLUTE", g.m("SUBTRACT", d, r + 0.2)), 0.0, 0.6)), side)
            if f[0] == "rivet":
                height = g.add(height, g.mul(inside, 0.6))
                col = g.mixc(g.mul(ring, 0.6), col, dark)
            else:
                height = g.add(height, g.mul(inside, -1.2))
                col = g.mixc(inside, col, dark)
                rough = g.add(rough, g.mul(inside, 0.3))
            continue
        kind, x0, x1, z0, z1, r, amt = f
        d = g.rrect(x, z, x0, x1, z0, z1, r)
        if kind == "seam":
            line = g.mul(g.inv(g.sstep(g.m("ABSOLUTE", d), 0.0, amt)), side)
            height = g.add(height, g.mul(line, -0.35))
            col = g.mixc(g.mul(line, 0.75), col, dark)
            rough = g.add(rough, g.mul(line, 0.2))
            continue
        inside = g.mul(g.inv(g.sstep(d, -1.2, 0.0)), side)                               # 1 w środku, zbocze 1,2 mm
        rim = g.mul(g.inv(g.sstep(g.m("ABSOLUTE", g.add(d, 0.6)), 0.0, 0.9)), side)
        if kind == "slot":
            height = g.add(height, g.mul(inside, -amt))
            col = g.mixc(inside, col, dark)
            rough = g.add(rough, g.mul(inside, 0.4))
        else:
            height = g.add(height, g.mul(inside, amt if kind == "ridge" else -amt))
            col = g.mixc(g.mul(rim, 0.4), col, dark)
    return col, rough, height


def _checker(g, x, z, pitch, deg):
    """Kratka (rybka) w płaszczyźnie XZ: zwraca (ścięte szczyty 0..1, bruzdy 0..1, ostrosłup 0..1)."""
    a1, a2 = math.radians(deg + 32.0), math.radians(deg - 32.0)
    u = g.m("DIVIDE", g.add(g.mul(x, math.cos(a1)), g.mul(z, math.sin(a1))), pitch)
    v = g.m("DIVIDE", g.add(g.mul(x, math.cos(a2)), g.mul(z, math.sin(a2))), pitch)
    pyr = g.m("MINIMUM", g.tri(u), g.tri(v))                                           # 1 na szczycie, 0 w bruzdach
    return g.m("MINIMUM", g.mul(pyr, 1.7), 1.0), g.inv(g.sstep(pyr, 0.0, 0.45)), pyr


def steel(name, tone="blued", grooves=(), slot=None, wear_k=1.0, engrave=(), blue=None, muzzle=None, holes=(), eng_style=(0.2, (0.24, 0.24, 0.25), 0.55), feats=(), r0=None, stencil=()):
    """Stal: oksydowana (blued) albo jasna (bright). grooves = [(oś 'x'|'z', podziałka mm, x0, x1, z0, z1, głębokość mm, tylko boki)] — rowki w mapie
    normalnych; slot = (cx, cz, kąt°) — nacięcie łba śruby na ścianach bocznych; engrave = [(x0, x1, z0, z1)] — pola napisów na bokach: grawer tam,
    gdzie tuż pod powierzchnią leży siatka-znacznik (marker_text); blue = dwa odcienie oksydy (krotki RGB liniowe); muzzle = (x0, x1) — boki przy
    wylocie wytarte od kabury / futerału; tone "paint" = stal lakierowana (blue = odcienie lakieru, metal wychodzi tylko w odpryskach);
    holes = [(podziałka mm, promień mm, x0, x1, z0, z1)] — otwory osłony na bokach; eng_style = (głębokość mm, kolor, krycie) napisu;
    feats = tłoczenia, szczeliny, nity (patrz _feats); r0 = chropowatość wykończenia (domyślnie 0,36 oksyda / 0,55 lakier);
    stencil = napisy z stencil_text() rzutowane z boku — do powierzchni walcowych, na których siatka-znacznik się nie sprawdza."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    geo = g.N.new("ShaderNodeNewGeometry")
    P, TN = geo.outputs["Position"], geo.outputs["True Normal"]
    x, y, z = g.xyz(P)
    _, ny, _ = g.xyz(TN)
    side = g.sstep(g.m("ABSOLUTE", ny), 0.85, 0.95)
    n_big = g.noise(P, 0.035, 3.0)
    n_mid = g.noise(P, 0.2, 4.0)
    n_edge = g.noise(P, 0.55, 4.0, 0.6)
    n_fine = g.noise(P, 1.8, 3.0, 0.6)
    # rysy: krótkie kreski w trzech kierunkach (szum obrócony, potem rozciągnięty i wycięty wąskim progiem)
    scr = None
    for ang, thr, k in ((0.2, 0.745, 1.0), (-0.9, 0.75, 0.8), (1.3, 0.755, 0.6)):
        v = g.mapping(g.mapping(P, rot=(0.0, ang, 0.0)), scale=(0.1, 6.0, 6.0))
        one = g.mul(g.sstep(g.noise(v, 1.0, 2.0), thr, thr + 0.015), k)
        scr = one if scr is None else g.m("MAXIMUM", scr, one)
    occl = g.ao(7.0, samples=12)
    cavity = g.inv(g.sstep(occl, 0.35, 0.8))
    convex = g.inv(g.ao(WEAR_MM[0], inside=True, samples=12))
    edge = g.sstep(g.mul(convex, g.add(0.25, g.mul(g.sstep(n_edge, 0.3, 0.7), 2.0))), 0.3, 0.55)       # wyszczerbione przetarcie krawędzi
    # cieńsza, zszarzała oksyda: płaty na płaskich ścianach i boki przy wylocie (od kabury)
    thin = g.mul(g.sstep(n_big, 0.6, 0.78), g.sstep(n_mid, 0.4, 0.65))
    if muzzle is not None:
        thin = g.add(thin, g.mul(g.sstep(x, muzzle[0], muzzle[1]), n_mid, side, 0.9))
    thin = g.mul(thin, 0.6)
    eng = None
    if engrave:
        reg = None
        for x0, x1, z0, z1 in engrave:
            one = g.mul(g.box(x, x0, x1), g.box(z, z0, z1))
            reg = one if reg is None else g.m("MAXIMUM", reg, one)
        reg = g.mul(reg, side)
        eng = g.mul(g.sstep(g.inv(g.ao(0.3, inside=True, samples=12)), 0.3, 0.6), reg)
        edge = g.mul(edge, g.inv(reg))
    wear = g.m("MINIMUM", g.mul(edge, g.inv(cavity), wear_k), 1.0)
    rust = g.mul(g.sstep(g.noise(P, 0.45, 6.0, 0.65), 0.67, 0.73), g.add(0.2, cavity), g.inv(wear))
    if tone in ("blued", "paint"):
        c1, c2 = blue or ((0.07, 0.078, 0.1), (0.12, 0.115, 0.12))                # oksyda: granatowa czerń z brunatnym odcieniem
        base = g.mixc(n_big, rgb(*c1), rgb(*c2))
        base = g.mixc(thin, base, rgb(*(1.4 * (a + b) + 0.01 for a, b in zip(c1, c2))))
        r_base = r0 or (0.36 if tone == "blued" else 0.55)
    else:
        base = g.mixc(n_mid, rgb(0.4, 0.4, 0.41), rgb(0.6, 0.6, 0.62))
        r_base = r0 or 0.32
    bare = g.mixc(n_fine, rgb(0.48, 0.48, 0.49), rgb(0.7, 0.7, 0.72))
    if tone == "paint":                                          # odpryski: pod lakierem podkład tlenkowy, w środku goła stal
        flake = g.mul(g.sstep(g.noise(P, 0.3, 5.0, 0.6), 0.67, 0.71), g.inv(cavity), wear_k)
        chip = g.m("MINIMUM", g.add(wear, flake), 1.0)
        base = g.mixc(chip, base, rgb(0.15, 0.05, 0.03))
        wear = g.mul(g.sstep(g.mul(chip, g.add(0.45, n_fine)), 0.6, 0.85), chip)
    col = g.mixc(g.mul(wear, 0.9), base, bare)
    col = g.mixc(g.mul(scr, 0.18), col, bare)
    col = g.mixc(g.mul(rust, 0.7), col, rgb(0.13, 0.05, 0.02))
    col = g.mixc(g.mul(cavity, 0.65), col, rgb(0.018, 0.016, 0.014))
    rough = g.add(r_base, g.mul(g.m("SUBTRACT", n_mid, 0.5), 0.26), g.mul(g.m("SUBTRACT", n_fine, 0.5), 0.12), g.mul(thin, -0.06))
    rough = g.mixf(wear, rough, 0.24)
    rough = g.add(rough, g.mul(scr, 0.1), g.mul(rust, 0.4), g.mul(cavity, 0.3))
    metal = g.m("MAXIMUM", g.m("SUBTRACT", 1.0, g.add(g.mul(rust, 0.8), g.mul(cavity, 0.5))), 0.0)
    if tone == "paint":
        metal = g.m("MINIMUM", g.add(g.mul(wear, 0.95), g.mul(scr, 0.3)), 1.0)
    height = g.add(g.mul(n_fine, 0.012), g.mul(scr, -0.015), g.mul(g.sstep(g.noise(P, 3.0, 2.0), 0.72, 0.8), -0.035))
    col, rough, height = _grooves(g, x, z, side, grooves, col, rough, height)
    col, rough, height = _feats(g, x, z, side, feats, col, rough, height)
    for pitch, hr, x0, x1, z0, z1 in holes:
        u = g.m("SUBTRACT", g.m("FRACT", g.m("DIVIDE", x, pitch)), 0.5)
        v = g.m("SUBTRACT", g.m("FRACT", g.m("DIVIDE", z, pitch)), 0.5)
        d = g.mul(g.m("SQRT", g.add(g.mul(u, u), g.mul(v, v))), pitch)
        hole = g.mul(g.inv(g.sstep(d, hr - 0.5, hr + 0.5)), g.box(x, x0, x1), g.box(z, z0, z1), side)
        height = g.add(height, g.mul(hole, -1.2))
        col = g.mixc(hole, col, rgb(0.004, 0.004, 0.004))
        rough = g.add(rough, g.mul(hole, 0.4))
        metal = g.mul(metal, g.inv(hole))
    if slot is not None:
        cx, cz, deg = slot
        a = math.radians(deg)
        d = g.m("ABSOLUTE", g.add(g.mul(g.m("SUBTRACT", x, cx), -math.sin(a)), g.mul(g.m("SUBTRACT", z, cz), math.cos(a))))
        dip = g.mul(g.inv(g.sstep(d, 0.35, 0.6)), side)
        height = g.add(height, g.mul(dip, -0.6))
        col = g.mixc(g.mul(dip, 0.7), col, rgb(0.01, 0.01, 0.01))
    for img, x0, x1, z0, z1, sgn in (t for t in stencil if t is not None):
        # rzut z boku: u wzdłuż napisu (po lewej stronie broni biegnie ku tyłowi), v w górę; maska działa tylko po swojej stronie
        u = g.m("DIVIDE", g.m("SUBTRACT", x1, x) if sgn > 0.0 else g.m("SUBTRACT", x, x0), x1 - x0)
        v = g.m("DIVIDE", g.m("SUBTRACT", z, z0), z1 - z0)
        uv = g.N.new("ShaderNodeCombineXYZ")
        g.put(uv.inputs[0], u)
        g.put(uv.inputs[1], v)
        tex = g.N.new("ShaderNodeTexImage")
        tex.image = img
        tex.extension = "CLIP"
        g.L.new(uv.outputs[0], tex.inputs["Vector"])
        mask = g.mul(g.m("MULTIPLY", tex.outputs["Color"], 1.0), g.sstep(g.mul(ny, sgn), 0.55, 0.8))
        eng = mask if eng is None else g.m("MAXIMUM", eng, mask)
    if eng is not None:
        height = g.add(height, g.mul(eng, -eng_style[0]))
        col = g.mixc(g.mul(eng, eng_style[2]), col, rgb(*eng_style[1]))             # bicie przecina oksydę — jaśniejsze od tła
        rough = g.add(rough, g.mul(eng, 0.2))
        metal = g.mul(metal, g.inv(g.mul(eng, 0.5)))
    rough = g.m("MINIMUM", g.m("MAXIMUM", rough, 0.14), 0.95)
    return _finish_mat(m, g, col, rough, metal, height, occl)


def bakelite(name, checker=None, screw=None, tone=None, mottle=0.09):
    """Okładziny z bakelitu albo inne tworzywo (tone = dwa odcienie RGB, domyślnie brunatna czerń). checker = (podziałka mm, kąt osi chwytu°) — kratka na płaskich ścianach bocznych; screw = (cx, cz, r) — gładkie pole wokół śruby."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    geo = g.N.new("ShaderNodeNewGeometry")
    P, TN = geo.outputs["Position"], geo.outputs["True Normal"]
    x, y, z = g.xyz(P)
    _, ny, _ = g.xyz(TN)
    n_marble = g.noise(P, mottle, 5.0, 0.6, 2.5 if mottle < 0.2 else 0.6)
    n_fine = g.noise(P, 2.2, 3.0)
    occl = g.ao(7.0, samples=12)
    cavity = g.inv(g.sstep(occl, 0.35, 0.8))
    convex = g.inv(g.ao(1.2, inside=True, samples=12))
    wear = g.sstep(g.mul(convex, g.add(0.5, n_fine)), 0.35, 0.8)
    t1, t2 = tone or ((0.008, 0.005, 0.004), (0.032, 0.014, 0.008))                    # brunatno-czarny, marmurkowy
    col = g.mixc(g.sstep(n_marble, 0.3, 0.7), rgb(*t1), rgb(*t2))
    rough = g.add(0.42, g.mul(g.m("SUBTRACT", n_fine, 0.5), 0.16))
    height = g.mul(n_fine, 0.015)
    if checker is not None:
        pitch, deg = checker
        flat = g.sstep(g.m("ABSOLUTE", ny), 0.985, 0.995)
        if screw is not None:
            d = g.m("SQRT", g.add(g.m("POWER", g.m("SUBTRACT", x, screw[0]), 2.0), g.m("POWER", g.m("SUBTRACT", z, screw[1]), 2.0)))
            flat = g.mul(flat, g.sstep(d, screw[2], screw[2] + 0.6))
        top, groove, pyr = _checker(g, x, z, pitch, deg)
        height = g.add(height, g.mul(top, flat, 0.42))
        groove = g.mul(groove, flat)
        col = g.mixc(g.mul(groove, g.add(0.08, g.mul(n_marble, 0.2))), col, rgb(0.07, 0.058, 0.048))   # kurz w bruzdach
        col = g.mixc(g.mul(g.sstep(pyr, 0.55, 0.9), flat, 0.35), col, rgb(0.075, 0.035, 0.02))         # wytarte szczyty kratki
        rough = g.add(rough, g.mul(groove, 0.25), g.mul(g.mul(top, flat), -0.1))
    col = g.mixc(g.mul(wear, 0.45), col, rgb(*(c * 2.5 + 0.004 for c in t2)))
    rough = g.mixf(wear, rough, 0.3)
    col = g.mixc(g.mul(cavity, 0.6), col, rgb(0.008, 0.006, 0.005))
    rough = g.m("MINIMUM", g.m("MAXIMUM", g.add(rough, g.mul(cavity, 0.25)), 0.2), 0.95)
    return _finish_mat(m, g, col, rough, 0.0, height, occl)


def wood(name, grooves=(), checker=None, tone=((0.028, 0.011, 0.005), (0.125, 0.05, 0.02)), laminate=False):
    """Drewno lakierowane (orzech), słoje wzdłuż X. grooves jak w steel(); checker = (podziałka mm, kąt°, x0, x1, z0, z1) — rybka na bokach;
    laminate = klejonka (sklejka bukowa jak w kolbach AK): cienkie warstwy z ciemnymi spoinami."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    geo = g.N.new("ShaderNodeNewGeometry")
    P, TN = geo.outputs["Position"], geo.outputs["True Normal"]
    x, y, z = g.xyz(P)
    _, ny, _ = g.xyz(TN)
    side = g.sstep(g.m("ABSOLUTE", ny), 0.7, 0.9)
    n_big = g.noise(P, 0.012, 3.0)
    n_fine = g.noise(P, 1.5, 3.0)
    grain = g.noise(g.mapping(P, scale=(0.012, 0.3, 0.3)), 1.0, 5.0, 0.65, 1.2)        # włókna długie na kilkadziesiąt mm
    pores = g.sstep(g.noise(g.mapping(P, scale=(0.08, 3.0, 3.0)), 1.0, 2.0), 0.62, 0.7)  # pory: krótkie ciemne kreski
    occl = g.ao(7.0, samples=12)
    cavity = g.inv(g.sstep(occl, 0.35, 0.8))
    convex = g.inv(g.ao(1.5, inside=True, samples=12))
    wear = g.mul(g.sstep(g.mul(convex, g.add(0.4, g.mul(g.noise(P, 0.4, 4.0), 1.4))), 0.35, 0.65), g.inv(cavity))
    dent = g.sstep(g.noise(P, 0.25, 3.0), 0.73, 0.76)                                  # obicia
    col = g.mixc(g.sstep(grain, 0.3, 0.7), rgb(*tone[0]), rgb(*tone[1]))
    col = g.mixc(g.mul(g.sstep(n_big, 0.35, 0.75), 0.4), col, rgb(*(c * 0.6 for c in tone[0])))
    col = g.mixc(g.mul(pores, 0.5), col, rgb(*(c * 0.4 for c in tone[0])))
    if laminate:
        ply = g.tri(g.m("DIVIDE", g.add(z, g.mul(g.noise(P, 0.012, 2.0), 7.0)), 2.6))
        col = g.mixc(g.mul(g.inv(g.sstep(ply, 0.08, 0.28)), 0.32), col, rgb(*(c * 0.45 for c in tone[0])))
        col = g.mixc(g.mul(g.sstep(ply, 0.6, 0.95), 0.12), col, rgb(*(min(c * 1.25, 1.0) for c in tone[1])))
    rough = g.add(0.3, g.mul(g.m("SUBTRACT", n_fine, 0.5), 0.1), g.mul(pores, 0.15))
    height = g.add(g.mul(grain, 0.03), g.mul(pores, -0.04), g.mul(dent, -0.25))
    col, rough, height = _grooves(g, x, z, side, grooves, col, rough, height)
    if checker is not None:
        pitch, deg, x0, x1, z0, z1 = checker
        mask = g.mul(g.box(x, x0, x1, 3.0), g.box(z, z0, z1, 3.0), side)
        top, groove, _ = _checker(g, x, z, pitch, deg)
        height = g.add(height, g.mul(top, mask, 0.3))
        col = g.mixc(g.mul(groove, mask, 0.55), col, rgb(*(c * 0.35 for c in tone[0])))
        rough = g.add(rough, g.mul(groove, mask, 0.2))
    col = g.mixc(g.mul(wear, 0.6), col, rgb(0.3, 0.19, 0.1))                           # gołe drewno na krawędziach
    rough = g.mixf(wear, rough, 0.62)
    col = g.mixc(g.mul(dent, 0.6), col, rgb(0.03, 0.015, 0.008))
    col = g.mixc(g.mul(cavity, 0.6), col, rgb(0.012, 0.008, 0.005))
    rough = g.m("MINIMUM", g.m("MAXIMUM", g.add(rough, g.mul(dent, 0.2), g.mul(cavity, 0.25)), 0.18), 0.95)
    return _finish_mat(m, g, col, rough, 0.0, height, occl)


def plain(name, col, rough, metal, emit=None):
    """Materiał jednolity; emit = kolor świecenia (rgb) albo None."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    return _finish_mat(m, g, col, rough, metal, 0.0, g.ao(7.0, samples=8), emit)


def glow(name, col):
    """Element świecący (ogniwo, cewka, dioda): ciemna baza w odcieniu światła + emisja."""
    return plain(name, rgb(*(c * 0.3 for c in col)), 0.3, 0.0, rgb(*col))


def M(fn, *a, **k):
    """Materiał albo None przy --nobake (bryły dostają wtedy szary materiał podglądu)."""
    return None if NOBAKE else fn(*a, **k)


GREY = ((0.07, 0.073, 0.078), (0.115, 0.114, 0.11))            # stal fosforanowana (szaroczarna)
STENCIL = (0.02, (0.5, 0.48, 0.36), 0.85)                       # napis malowany od szablonu zamiast bicia
BLACK = ((0.008, 0.008, 0.009), (0.014, 0.014, 0.016))          # czarne tworzywo (odcienie blisko siebie — bez marmurka)
BRASS = ((0.32, 0.2, 0.045), (0.5, 0.33, 0.085))                # mosiądz jako „oksyda" materiału steel()
BLACKOX = ((0.075, 0.078, 0.088), (0.125, 0.122, 0.118))          # czerniona stal (AK)
PARK = ((0.08, 0.085, 0.082), (0.125, 0.127, 0.118))            # fosforanowanie: matowa szarozielona
OLIVE = ((0.045, 0.055, 0.022), (0.08, 0.09, 0.042))            # lakier khaki
NAVY = ((0.028, 0.042, 0.07), (0.048, 0.066, 0.105))            # szaroniebieska emalia aparatury
COPPER = ((0.3, 0.1, 0.04), (0.5, 0.2, 0.075))                  # miedź w emalii
LAMINATE = ((0.06, 0.02, 0.008), (0.19, 0.068, 0.022))          # klejonka pod szelakiem
TEAK = ((0.06, 0.03, 0.01), (0.2, 0.105, 0.036))
REDBAKE = ((0.05, 0.012, 0.007), (0.15, 0.036, 0.015))          # bakelit chwytu (brunatnoczerwony)
ORANGEBAKE = ((0.1, 0.026, 0.01), (0.25, 0.075, 0.02))          # bakelit AG-4 magazynków („rdzawy")
PHENOL = ((0.06, 0.026, 0.01), (0.13, 0.06, 0.022))             # tekstolit


def _text_mesh(body, size):
    """Siatka napisu wbudowaną czcionką Blendera w układzie własnym (x w prawo, y w górę, linia bazowa na y = 0)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    tmp = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(tmp)
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp, do_unlink=True)
    return me


def marker_text(body, size, x, z, y, mat):
    """Napis jako płaska siatka-znacznik tuż pod powierzchnią boku: materiał stali (engrave) znajduje ją promieniami AO i żłobi w tym miejscu grawer.
    Znaczniki znikają po wypieku. Napis jest czytelny od swojej strony: y > 0 = lewa strona broni (biegnie od x ku tyłowi), y < 0 = prawa (od x ku przodowi).
    Tylko na płaskie boki — na walcach użyj stencil_text()."""
    if mat is None:
        return None
    me = _text_mesh(body, size)
    sx = -1.0 if y > 0.0 else 1.0
    for v in me.vertices:
        v.co = Vector((x + sx * v.co.x, y, z + v.co.y))
    ob = bpy.data.objects.new("marker", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    ob["comp"] = COMP[-1]
    OBJS.append(ob)
    return ob


def stencil_text(body, size, x, z, left, ppm=10.0, pad=1.5):
    """Napis jako maska rastrowa rzutowana z boku (dla steel(stencil=[…])): działa na walcach, gdzie płaski znacznik odstaje od powierzchni.
    (x, z) = początek linii bazowej; left = lewa strona broni (napis biegnie od x ku tyłowi), inaczej prawa (od x ku przodowi).
    Zwraca (obraz, x0, x1, z0, z1, znak strony) albo None przy --nobake."""
    if NOBAKE:
        return None
    me = _text_mesh(body, size)
    me.calc_loop_triangles()
    vs = np.array([(v.co.x, v.co.y) for v in me.vertices], dtype=np.float64)
    lo = vs.min(axis=0) - pad
    hi = vs.max(axis=0) + pad
    w, h = int(math.ceil((hi[0] - lo[0]) * ppm)), int(math.ceil((hi[1] - lo[1]) * ppm))
    buf = np.zeros((h, w), dtype=np.float32)
    pts = (vs - lo) * ppm
    for t in me.loop_triangles:
        a, b, c = (pts[i] for i in t.vertices)
        x0, x1 = max(int(min(a[0], b[0], c[0])), 0), min(int(max(a[0], b[0], c[0])) + 1, w)
        y0, y1 = max(int(min(a[1], b[1], c[1])), 0), min(int(max(a[1], b[1], c[1])) + 1, h)
        if x1 <= x0 or y1 <= y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        e0 = (b[0] - a[0]) * (gy - a[1]) - (b[1] - a[1]) * (gx - a[0])
        e1 = (c[0] - b[0]) * (gy - b[1]) - (c[1] - b[1]) * (gx - b[0])
        e2 = (a[0] - c[0]) * (gy - c[1]) - (a[1] - c[1]) * (gx - c[0])
        inside = ((e0 >= 0) & (e1 >= 0) & (e2 >= 0)) | ((e0 <= 0) & (e1 <= 0) & (e2 <= 0))
        buf[y0:y1, x0:x1][inside] = 1.0
    bpy.data.meshes.remove(me)
    img = bpy.data.images.new("stencil", w, h, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.repeat(buf[:, :, None], 4, axis=2).ravel())
    img.pack()
    if left:
        return img, x - hi[0], x - lo[0], z + lo[1], z + hi[1], 1.0
    return img, x + lo[0], x + hi[0], z + lo[1], z + hi[1], -1.0


# ---------------------------------------------------------------- P-83 (klucz techniczny p64)

def build_p83():
    """P-83 Wanad w milimetrach (od 1.7.313 zamiast P-64): zamek 166 mm o płaskim grzbiecie, wysokość ok. 122 mm ze szczerbinką, magazynek na 8 naboi
    z płaską stopką; stopka magazynka na z = 0, tył zamka na x = 0. Okładziny z czarnego tworzywa z kratką, zaokrąglony kabłąk, kurek z ostrogą."""
    WEAR_MM[0] = 0.9
    if NOBAKE:
        blued = small = bright = bore = grip_m = screw_m = hammer_m = None
    else:
        blued = steel("p83_blued", blue=BLACKOX, r0=0.4, grooves=[("x", 3.0, 7.0, 36.0, 89.0, 113.0, 0.55, True)],
                      engrave=[(66.0, 128.0, 90.0, 101.0), (100.0, 160.0, 90.0, 101.0)], muzzle=(130.0, 166.0))
        small = steel("p83_small", blue=BLACKOX, r0=0.4, wear_k=0.35)
        hammer_m = steel("p83_hammer", blue=BLACKOX, grooves=[("z", 1.3, -10.0, -1.0, 96.0, 108.0, 0.25, False)])
        bright = steel("p83_bright", tone="bright")
        screw_m = steel("p83_screw", blue=BLACKOX, slot=(22.0, 40.0, 25.0), wear_k=0.35)
        bore = plain("p83_bore", rgb(0.008, 0.008, 0.008), 0.7, 1.0)
        grip_m = bakelite("p83_grip", checker=(1.3, 101.0), screw=(22.0, 40.0, 4.8), tone=BLACK)
        mark = plain("marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
        marker_text("9 mm  P-83", 6.0, 126.0, 91.5, 12.43, mark)
        marker_text("WA 03187", 6.0, 104.0, 91.5, -12.43, mark)
    # zamek: płaskie boki i spłaszczony grzbiet (wyższy i bardziej kanciasty niż w P-64), przód lekko zwężony, okno wyrzutowe po prawej (−Y)
    sec = lambda w, zb, zs, rt: dome_sec(w, zb, zs, rt)
    slide = loft("slide", [(0.0, sec(12.5, 86.0, 112.0, 4.0)), (70.0, sec(12.5, 86.0, 112.0, 4.0)), (140.0, sec(12.5, 86.0, 112.0, 4.0)),
                           (158.0, sec(11.8, 87.0, 111.0, 3.8)), (166.0, sec(10.8, 88.0, 110.0, 3.4))], blued)
    cut(slide, prism("cut_port", fillet([(70.0, 103.0, 2.0), (99.0, 103.0, 2.0), (99.0, 125.0), (70.0, 125.0)]), -20.0, 2.5, None, bv=None, part=False))
    cut(slide, revolve("cut_bore", [(150.0, 0.0), (150.0, 5.6), (172.0, 5.6), (172.0, 0.0)], (0.0, 101.0), None, seg=24, bv=None, part=False))
    bevel(slide, 0.7, 2)
    revolve("chamber", [(70.6, 0.0), (70.6, 10.2), (98.4, 10.2), (98.4, 0.0)], (0.0, 101.0), bright, seg=28, bv=0.0)
    barrel = revolve("barrel", [(158.0, 0.0), (158.0, 6.5), (166.5, 6.5), (166.5, 4.6), (152.0, 4.6), (152.0, 0.0)], (0.0, 101.0), blued, seg=24, bv=0.35, bseg=1)
    if not NOBAKE:
        barrel.data.materials.append(bore)
        for p in barrel.data.polygons:
            if p.center.x < 166.2 and math.hypot(p.center.y, p.center.z - 101.0) < 4.7:
                p.material_index = 1
    prism("extractor", fillet([(55.0, 100.4), (70.0, 100.4), (70.0, 103.0), (55.0, 103.0, 1.0)]), -13.0, -11.5, small, bv=0.25, seg=1)
    # przyrządy: muszka z przodu, szczerbinka w jaskółczym ogonie z tyłu
    prism("sight_front", fillet([(152.0, 115.0), (161.0, 115.0), (160.0, 120.5, 0.6), (155.0, 120.5, 1.2)]), -1.3, 1.3, small, bv=0.2, seg=1)
    prism("sight_base", fillet([(6.0, 114.5), (18.0, 114.5), (16.5, 118.0, 0.6), (6.0, 118.0, 0.6)]), -7.0, 7.0, small, bv=0.3, seg=1)
    for sgn in (-1.0, 1.0):
        prism("sight_post", fillet([(6.5, 117.5), (15.5, 117.5), (14.0, 121.5, 0.4), (6.5, 121.5, 0.4)]), sgn * 1.7, sgn * 6.8, small, bv=0.2, seg=1)
    # bezpiecznik z zwalniaczem kurka po lewej (+Y), jego oś widoczna po prawej
    prism("safety", hull(circle(16.0, 101.0, 4.0) + circle(29.0, 98.5, 2.4)), 12.1, 15.0, small, bv=0.45, seg=1)
    revolve("safety_axis", [(-13.0, 0.0), (-13.0, 2.8), (12.5, 2.8), (12.5, 0.0)], (16.0, 101.0), small, axis="Y", seg=16, bv=0.25)
    # szkielet: osłona pod zamkiem, zaokrąglony kabłąk, chwyt na magazynek 8-nabojowy (dłuższy niż w P-64)
    prism("frame", fillet([(-1.0, 87.0, 0.5), (134.0, 87.0), (137.5, 83.0, 2.5), (134.0, 77.0, 3.0), (112.0, 76.5), (106.0, 74.5, 2.0), (63.0, 74.5, 3.0),
                           (57.0, 69.0, 4.0), (43.0, 3.0, 2.0), (-8.0, 4.0, 3.0), (1.5, 64.0, 14.0), (-4.5, 79.0, 4.0), (-5.5, 84.5, 1.5)]),
          -11.7, 11.7, blued, bv=0.6, seg=2)
    guard = spline([(112.0, 79.0), (115.0, 66.0), (112.0, 54.0), (103.0, 46.5), (88.0, 44.5), (73.0, 46.5), (63.5, 53.0), (58.5, 62.0), (56.0, 70.0)], 6)
    prism("guard", strip(guard, 4.2), -5.6, 5.6, blued, bv=0.9, seg=2)
    prism("trigger", strip(spline([(73.0, 77.0), (74.5, 68.0), (77.0, 60.0), (81.0, 54.0)], 5), lambda t: 5.4 - 2.4 * t), -3.4, 3.4, blued, bv=0.8, seg=2)
    prism("hammer", fillet([(6.0, 87.0), (-2.5, 88.5, 2.0), (-9.0, 97.0, 3.0), (-9.5, 105.0, 3.0), (-4.0, 109.0, 2.5), (3.0, 106.0, 2.0), (6.0, 98.0)]),
          -3.9, 3.9, hammer_m, bv=0.5, seg=2)
    revolve("chamber_pin", [(-1.2, 0.0), (-1.2, 1.3), (3.0, 1.3), (3.0, 0.0)], (0.0, 110.5), bright, seg=10, bv=0.2)      # wskaźnik naboju w komorze
    for cx, cz, r in ((114.0, 81.5, 2.0), (73.0, 80.5, 1.6)):
        revolve("pin", [(-12.1, 0.0), (-12.1, r), (12.1, r), (12.1, 0.0)], (cx, cz), small, axis="Y", seg=14, bv=0.2)
    # okładzina z czarnego tworzywa (owija grzbiet), śruba, płaska stopka magazynka, zaczep magazynka w stopce chwytu
    prism("grip", fillet([(55.0, 66.0, 4.0), (41.5, 6.5, 4.0), (-9.5, 7.0, 4.5), (0.0, 63.0, 14.0), (-5.0, 77.0, 3.5), (1.5, 82.5, 3.5),
                          (30.0, 83.0, 5.0), (45.0, 78.5, 6.0)]), -14.5, 14.5, grip_m, bv=2.2, seg=3)          # promienie naroży > faza, inaczej faza się zapada
    revolve("screw", [(-15.0, 0.0), (-15.0, 3.4), (15.0, 3.4), (15.0, 0.0)], (22.0, 40.0), screw_m, axis="Y", seg=18, bv=0.3)
    prism("mag_plate", fillet([(-8.5, 0.0, 1.2), (42.0, 0.0, 1.2), (42.0, 3.8), (-8.8, 3.8, 1.0)]), -10.8, 10.8, blued, bv=0.4, seg=1)
    prism("mag_catch", fillet([(-12.0, 2.0, 1.0), (-7.0, 2.0), (-6.0, 9.5), (-11.0, 9.5, 1.5)]), -5.0, 5.0, blued, bv=0.5, seg=1)
    # nadgarstek pod chwytem: od nadgarstka do grzbietu zamka ok. 0,21 m, jak w P-64 — dłoń kończy się na wysokości zamka
    return {"rear": Vector((16.0, 0.0, -65.0)), "fore": None, "muzzle": Vector((166.5, 0.0, 101.0)), "hands": 1, "length": 0.19, "grip": Vector((19.0, 0.0, 47.0))}


# ---------------------------------------------------------------- strzelba pump-action: PELLET-8

def shell(name, c, z0, red, brass, axis="Z"):
    """Nabój śrutowy kal. 12 (mosiężne dno + czerwona łuska) o osi Z albo X; c = dwie pozostałe współrzędne, z0 = początek na osi."""
    revolve(name + "_base", [(z0, 0.0), (z0, 10.8), (z0 + 9.0, 10.8), (z0 + 9.0, 0.0)], c, brass, axis=axis, seg=12, bv=0.4)
    revolve(name, [(z0 + 9.0, 0.0), (z0 + 9.0, 10.3), (z0 + 62.0, 10.3), (z0 + 64.0, 8.0), (z0 + 64.0, 0.0)], c, red, axis=axis, seg=12, bv=0.0)


def sg_tube(mag_end, blued, small, cap_m):
    """Magazynek rurowy strzelby z nakrętką, obejmą i strzemiączkiem pasa przy nakrętce (podzespół „tube”)."""
    cyl("mag_tube", 588.0, mag_end + 2.0, 12.6, (0.0, -27.0), blued, seg=20, bv=0.0)
    revolve("mag_cap", [(mag_end, 0.0), (mag_end, 14.2), (mag_end + 23.0, 14.2), (mag_end + 27.0, 11.0), (mag_end + 27.0, 0.0)], (0.0, -27.0), cap_m,
            seg=20, bv=0.5, bseg=1)
    ring = hull(circle(0.0, 0.0, 13.4, 24) + circle(0.0, -27.0, 14.6, 24))
    bevel(loft("band", [(mag_end - 16.0, ring), (mag_end - 2.0, ring)], blued), 0.6, 1)
    loop = [(mag_end - 9.0 + 8.0 * math.sin(math.radians(a)), -50.5 + 8.0 * math.cos(math.radians(a))) for a in range(20, 341, 20)]
    prism("swivel", strip(loop, 2.6), -1.7, 1.7, small, bv=0.5, seg=1)


def _shotgun(v):
    """Strzelba pump-action kal. 12 z magazynkiem rurowym. Oś lufy na z = 0, stopka kolby na x = 0. v = parametry odmiany (patrz build_srut8)."""
    pre, tip, mag_end = v["pre"], v["muzzle"], v["mag_end"]
    blued = M(steel, pre + "_blued", blue=v["steel"], engrave=[(498.0, 584.0, -17.0, 1.0), (478.0, 552.0, -40.0, -24.0)], muzzle=(tip - 110.0, tip))
    small = M(steel, pre + "_small", blue=v["steel"], wear_k=0.35)
    cap_m = M(steel, pre + "_cap", blue=v["steel"], grooves=[("z", 2.4, mag_end - 1.0, mag_end + 21.0, -45.0, -9.0, 0.35, False)])
    bright = M(steel, pre + "_bright", tone="bright")
    bore = M(plain, pre + "_bore", rgb(0.008, 0.008, 0.008), 0.7, 1.0)
    stock_m = M(wood, pre + "_stock", checker=(3.2, 12.0, 302.0, 360.0, -64.0, -24.0), tone=v["wood"])
    fore_m = M(wood, pre + "_fore", grooves=[("x", 16.0, 654.0, 826.0, -60.0, 5.0, 1.4, False)], tone=v["wood"])
    rubber = M(plain, pre + "_rubber", rgb(0.012, 0.012, 0.012), 0.85, 0.0)
    brass = M(plain, pre + "_brass", rgb(0.55, 0.38, 0.1), 0.35, 1.0)
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text(v["text_l"], 12.0, 580.0, -13.0, 16.43, mark)
    marker_text(v["text_r"], 8.5, 482.0, -36.0, -16.43, mark)

    # komora zamkowa: zaokrąglony tył, okno wyrzutowe po prawej (−Y) z jasnym zamkiem w środku
    rc = lambda zs, rt: dome_sec(16.5, -46.0, zs, rt)
    recv = loft("receiver", [(370.0, rc(-8.0, 9.0)), (380.0, rc(-2.0, 11.0)), (395.0, rc(3.0, 12.0)), (415.0, rc(4.0, 12.0)), (500.0, rc(4.0, 12.0)),
                             (590.0, rc(4.0, 12.0))], blued)
    cut(recv, prism("cut_port", fillet([(500.0, -9.0, 3.0), (578.0, -9.0, 3.0), (578.0, 9.0, 3.0), (500.0, 9.0, 3.0)]), -30.0, -4.0, None, bv=None, part=False))
    bevel(recv, 0.9, 2)
    cyl("bolt", 499.0, 579.0, 9.5, (0.0, 0.0), bright, seg=24, bv=0.0)
    trig("trigger", 396.0, 472.0, -46.0, blued, small)
    revolve("safety", [(-9.0, 0.0), (-9.0, 3.3), (9.0, 3.3), (9.0, 0.0)], (404.0, -53.0), small, axis="Y", seg=14, bv=0.3)
    pins("pin", ((418.0, -22.0), (452.0, -30.0)), 16.5, small, 2.6)

    # lufa, magazynek rurowy z nakrętką, obejma, muszka, listwy czółenka
    barrel("barrel", 586.0, tip, 11.4, 9.25, (0.0, 0.0), blued, bore, depth=35.0, seg=24)
    with comp("tube"):
        sg_tube(mag_end, blued, small, cap_m)
    revolve("bead", [(-1.6, 0.0), (-1.6, 2.0), (1.6, 2.0), (1.6, 0.0)], (tip - 9.0, 11.6), brass, axis="Y", seg=12, bv=0.4, bseg=1)
    for sy in (-1.0, 1.0):
        prism("action_bar", [(580.0, -31.0), (650.0, -31.0), (650.0, -23.0), (580.0, -23.0)], sy * 13.4, sy * 15.2, small, bv=0.3, seg=1)

    # czółenko (drewno, rowki w mapie normalnych) i kolba: owalne przekroje wzdłuż gładkich linii grzbietu, spodu i szerokości
    revolve("forend", [(640.0, 0.0), (640.0, 18.5), (647.0, 23.0), (833.0, 23.0), (840.0, 18.5), (840.0, 0.0)], (0.0, -27.0), fore_m, seg=24, bv=1.2, bseg=2)
    top = curve_fn([(22.0, -50.0), (150.0, -39.0), (270.0, -27.0), (305.0, -23.0), (335.0, -19.0), (358.0, -9.0), (374.0, -1.0)])
    bot = curve_fn([(22.0, -178.0), (120.0, -150.0), (200.0, -122.0), (262.0, -103.0), (292.0, -90.0), (318.0, -70.0), (345.0, -53.0), (374.0, -45.0)])
    wid = curve_fn([(22.0, 21.0), (150.0, 21.5), (260.0, 20.0), (300.0, 17.5), (340.0, 15.8), (374.0, 15.4)])    # węższa od komory — bez współpłaszczyzn
    oval_loft("stock", 22.0, 374.0, top, bot, wid, stock_m)
    pad = lambda k: oval_sec(21.0 * k, 0.5 * (top(22.0) + bot(22.0)), 0.5 * (top(22.0) - bot(22.0)) * k)
    bevel(loft("pad", [(0.0, pad(0.93)), (5.0, pad(1.02)), (23.0, pad(1.02))], rubber), 1.5, 2)
    # strzemiączka pasa: pod kolbą i pod obejmą lufy
    loop = [(96.0 + 8.0 * math.sin(math.radians(a)), -167.0 + 8.0 * math.cos(math.radians(a))) for a in range(20, 341, 20)]
    prism("swivel", strip(loop, 2.6), -1.7, 1.7, small, bv=0.5, seg=1)
    if v.get("extras"):
        v["extras"](blued, small, brass, top, bot)
    # nadgarstki pod szyjką kolby i pod czółenkiem (dłonie sięgają od nich ok. 0,2 m w górę)
    return {"rear": Vector((335.0, 0.0, -120.0)), "fore": Vector((742.0, 0.0, -116.0)), "muzzle": Vector((tip, 0.0, 0.0)), "hands": 2, "length": v["length"],
            "grip": Vector((332.0, 0.0, -42.0)), "hold": Vector((742.0, 0.0, -50.0))}


def p8_saddle(n, cuff, red, brass):
    """Ładownica na lewym boku komory PELLET-8 z `n` nabojami (podzespół „saddle”)."""
    box("saddle", 428.0, 428.0 + 26.8 * n, -40.0, 4.0, 2.2, cuff, bv=0.6, seg=1, y=18.6)
    for i in range(n):
        shell("shell_l", (445.0 + i * 25.0, 30.0), -46.0, red, brass)


def build_srut8():
    """PELLET-8: ciężka strzelba — dłuższa lufa z perforowaną osłoną, magazynek na 8 nabojów, szara stal, ciemne drewno, zapas nabojów na broni."""
    def extras(blued, small, brass, top, bot):
        shield = M(steel, "p8_shield", blue=GREY, holes=[(12.0, 3.4, 650.0, 1008.0, -12.5, 12.5)])
        red = M(plain, "p8_red", rgb(0.3, 0.018, 0.014), 0.5, 0.0)
        cuff = M(bakelite, "p8_cuff", tone=BLACK)
        # osłona termiczna: półrura nad lufą, urządzenie wylotowe z pierścieniami
        cyl("shield", 644.0, 1014.0, 16.0, (0.0, 0.0), shield, seg=22, bv=0.6)
        ring_m = M(steel, "p8_brake", blue=GREY, grooves=[("x", 7.0, 1078.0, 1118.0, -20.0, 20.0, 1.0, False)])
        revolve("brake", [(1074.0, 11.0), (1074.0, 14.8), (1099.0, 14.8), (1099.0, 11.0), (1074.0, 11.0)], (0.0, 0.0), ring_m, seg=22, bv=0.8)   # tuleja: nie zasłania kanału
        # naboje: ładownica na lewym boku komory i opaska na kolbie (widoczna z prawej)
        with comp("saddle"):
            p8_saddle(5, cuff, red, brass)
        box("cuff", 158.0, 248.0, bot(203.0) - 3.0, top(203.0) + 3.0, 23.0, cuff, bv=2.0, r=8.0)
        for i in range(4):
            shell("shell_r", (-33.0, -50.0 - i * 23.0), 170.0, red, brass, axis="X")
    return _shotgun({"pre": "p8", "steel": GREY, "wood": ((0.014, 0.006, 0.004), (0.06, 0.024, 0.011)), "muzzle": 1100.0, "mag_end": 1040.0,
                     "length": 1.1, "text_l": "PELLET-8", "text_r": "HD 8 / 70", "extras": extras})


# ---------------------------------------------------------------- wspólne: komora tłoczona wzoru AK

def ak_feats(x0):
    """Tłoczenia, szczelina pokrywy i nity komory wzoru AK zaczynającej się w x0 (dla steel(feats=…))."""
    return [("pocket", x0 + 150.0, x0 + 186.0, -31.0, -15.0, 5.0, 1.0),               # przetłoczenie nad gniazdem magazynka
            ("seam", x0 + 4.0, x0 + 258.0, 0.6, 40.0, 2.0, 0.55),                       # szczelina pokrywy
            ("rivet", x0 + 12.0, -8.0, 2.6), ("rivet", x0 + 12.0, -28.0, 2.6), ("rivet", x0 + 236.0, -6.5, 2.6), ("rivet", x0 + 252.0, -6.5, 2.6),
            ("rivet", x0 + 244.0, -31.0, 2.6), ("rivet", x0 + 120.0, -33.0, 2.2), ("rivet", x0 + 196.0, -33.0, 2.2),
            ("hole", x0 + 88.0, -9.0, 1.6), ("hole", x0 + 88.0, -28.0, 1.6)]            # gniazda ustalające skrzydełko przełącznika


def ak_receiver(x0, st, small, bright):
    """Komora tłoczona wzoru AK (262 mm od x0): pokrywa, suwadło z rączką po prawej (−Y), skrzydełko przełącznika, osie, zatrzask magazynka."""
    rc = dome_sec(16.5, -38.0, 2.0, 9.0)
    bevel(loft("receiver", [(x0, rc), (x0 + 130.0, rc), (x0 + 262.0, rc)], st), 0.8, 2)
    with comp("bolt"):                                      # suwadło z rączką: osobny węzeł — strzelnica FPP przesuwa je przy strzale i odciąganiu
        box("carrier", x0 + 168.0, x0 + 248.0, -3.0, 7.0, 0.9, bright, bv=0.3, seg=1, y=-16.9)
        revolve("handle", [(-31.0, 0.0), (-31.0, 4.2), (-16.0, 4.2), (-16.0, 0.0)], (x0 + 236.0, 2.0), small, axis="Y", seg=12, bv=0.6)
    prism("selector", hull(circle(x0 + 102.0, -20.0, 6.0, 12) + circle(x0 + 200.0, -13.0, 3.5, 10)), -18.2, -16.6, small, bv=0.35, seg=1)
    prism("selector_tab", [(x0 + 196.0, -17.0), (x0 + 207.0, -17.0), (x0 + 207.0, -9.0), (x0 + 196.0, -9.0)], -21.5, -16.6, small, bv=0.3, seg=1)
    pins("pin", ((x0 + 30.0, -10.0), (x0 + 155.0, -28.0), (x0 + 172.0, -18.0)), 16.5, small, 2.2)
    prism("mag_catch", fillet([(x0 + 130.0, -38.0), (x0 + 146.0, -38.0), (x0 + 142.0, -58.0, 2.0), (x0 + 134.0, -58.0, 2.0)]), -4.0, 4.0, small, bv=0.5, seg=1)


# ---------------------------------------------------------------- M-83


M83_MATS = {}


def m83_mats():
    """Materiały M-83 (raz na przebieg) — części budują się z tych samych co broń."""
    if not M83_MATS:
        X = 300.0
        M83_MATS.update({
            "st": M(steel, "m83_steel", blue=BLACKOX, r0=0.42, engrave=[(X + 198.0, X + 258.0, -24.0, -10.0), (X + 28.0, X + 84.0, -31.0, -13.0)],
                    muzzle=(800.0, 880.0), feats=ak_feats(X), grooves=[("x", 21.0, X + 24.0, X + 150.0, 7.5, 12.0, 0.5, False)]),
            "small": M(steel, "m83_small", blue=BLACKOX, r0=0.42, wear_k=0.4),
            "bright": M(steel, "m83_bright", tone="bright"),
            "bore": M(plain, "m83_bore", rgb(0.008, 0.008, 0.008), 0.7, 1.0, None),
            "lam": M(wood, "m83_lam", laminate=True, tone=LAMINATE),
            "grip": M(bakelite, "m83_grip", checker=(2.2, 100.0), tone=REDBAKE),
            "mag": M(bakelite, "m83_mag", tone=ORANGEBAKE, mottle=0.7),
        })
    return M83_MATS


def m83_mag(mag_m, small, extra=0.0):
    """Magazynek łukowy z bakelitu ze stalową stopką; `extra` mm dłuższy (RPK 40 = +55 mm, bardziej zakrzywiony)."""
    k = extra / 55.0
    mag_path = spline([(455.0, -30.0), (460.0, -80.0), (472.0 + 2.0 * k, -128.0 - 18.0 * k), (492.0 + 14.0 * k, -172.0 - 45.0 * k)], 6)
    prism("mag", strip(mag_path, 42.0), -11.5, 11.5, mag_m, bv=1.5, seg=2)
    prism("mag_floor", strip(mag_path[-3:], 46.0), -12.5, 12.5, small, bv=0.8, seg=1)
    prism("mag_lug", strip(mag_path[:5], 44.5), -6.0, 6.0, small, bv=0.5, seg=1)


def m83_front(st, small, bright, lam, hg_end=746.0, muzzle_end=880.0, heavy=0.0, bayonet=True):
    """Przód M-83: lufa, rura gazowa, łoże i nakładka, komora gazowa, muszka, osada bagnetu, wycior. `hg_end` = koniec łoża, `muzzle_end` = wylot
    (urządzenie wylotowe 30 mm buduje m83_muzzle), `heavy` = grubsza lufa (RPK). Dla wartości domyślnych — dokładnie fabryczny AKM."""
    h, e = hg_end, muzzle_end
    cyl("barrel", 560.0, e - 30.0, 7.6 + heavy, (0.0, 0.0), st, seg=16, bv=0.0)
    cyl("gas_tube", 562.0, h - 4.0, 6.2, (0.0, 23.0), st, seg=14, bv=0.0)
    cyl("hg_upper", 606.0, h - 12.0, 13.5, (0.0, 22.0), lam, seg=16, bv=1.2)
    mid = 566.0 + (h - 10.0 - 566.0) * (84.0 / 170.0)
    prism("hg_lower", fillet([(566.0, 8.0), (h - 10.0, 8.0), (h - 10.0, -20.0, 5.0), (mid, -30.0, 30.0), (566.0, -28.0, 8.0)]), -15.5, 15.5, lam, bv=2.5, seg=2)
    box("hg_cap", h - 11.0, h, -24.0, 12.0, 16.0, st, bv=0.8, r=3.0)
    prism("gas_block", fillet([(h - 6.0, -9.0), (h + 26.0, -9.0), (h + 26.0, 10.0, 2.0), (h + 11.0, 31.0, 3.0), (h - 6.0, 31.0, 2.0)]), -9.0, 9.0, st, bv=1.0, seg=2)
    swivel(h + 10.0, -27.0, small, 7.0)
    box("fs_base", e - 82.0, e - 52.0, -9.5, 9.5, 9.5, st, bv=1.0, r=3.0)
    prism("fs_tower", [(e - 79.0, 6.0), (e - 55.0, 6.0), (e - 58.0, 30.0), (e - 76.0, 30.0)], -4.0, 4.0, st, bv=0.6, seg=1)
    for sy in (-1.0, 1.0):
        prism("fs_ear", fillet([(e - 76.0, 28.0), (e - 58.0, 28.0), (e - 60.0, 46.0, 2.0), (e - 74.0, 46.0, 2.0)]), sy * 3.0, sy * 5.6, st, bv=0.4, seg=1)
    revolve("fs_post", [(28.0, 0.0), (28.0, 1.3), (43.0, 1.3), (43.0, 0.0)], (e - 67.0, 0.0), small, axis="Z", seg=8, bv=0.0)
    if bayonet:
        box("bayonet_lug", e - 104.0, e - 86.0, -16.0, -8.0, 4.0, st, bv=0.6, seg=1)
    if e - 34.0 > h + 2.0:
        cyl("rod", h - 4.0, e - 34.0, 2.4, (0.0, -12.5), bright, seg=8, bv=0.0)


def m83_muzzle(st, bore, muzzle_end=880.0):
    """Gwint i skośny kompensator AKM (podzespół „muzzle” — gra przesuwa go na koniec założonej lufy)."""
    cyl("thread_ring", muzzle_end - 34.0, muzzle_end - 29.0, 10.4, (0.0, 0.0), st, seg=16, bv=0.4)
    barrel("muzzle", muzzle_end - 30.0, muzzle_end, 9.6, 4.2, (0.0, 0.0), st, bore, depth=24.0, seg=16)


def build_m83():
    """M-83: karabinek wzoru AKM — tłoczona komora z nitami, kolba i łoże z klejonki, bakelitowy chwyt i magazynek. Oś lufy na z = 0, wylot na x = 880 mm."""
    X = 300.0
    mm = m83_mats()
    st, small, bright, bore, lam, grip_m, mag_m = mm["st"], mm["small"], mm["bright"], mm["bore"], mm["lam"], mm["grip"], mm["mag"]
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("M-83", 9.5, X + 256.0, -22.0, 16.43, mark)
    marker_text("KR 4471", 7.5, X + 30.0, -27.0, -16.43, mark)

    ak_receiver(X, st, small, bright)
    # kolba z klejonki ze stalową stopką i strzemiączkiem (podzespół „stock” — kolba składana AKMS go zastępuje)
    with comp("stock"):
        prism("stock", fillet([(X + 2.0, 3.0, 4.0), (X + 2.0, -34.0, 4.0), (200.0, -50.0, 20.0), (14.0, -104.0, 8.0), (14.0, -22.0, 8.0)]), -14.0, 14.0, lam, bv=3.0, seg=2)
        box("butt", 0.0, 16.0, -106.0, -20.0, 14.5, small, bv=1.0, seg=1, r=3.0)
        swivel(118.0, -89.0, small)
    box("stock_tang", X - 46.0, X + 4.0, 1.0, 5.5, 8.0, st, bv=0.6, seg=1)
    pgrip("grip", X + 72.0, -38.0, grip_m)
    trig("trigger", X + 74.0, X + 132.0, -38.0, st, small)
    with comp("mag"):
        m83_mag(mag_m, small)
    # przednia wkładka z celownikiem krzywkowym (komora), przód z lufą i łożem („front”), urządzenie wylotowe („muzzle”)
    box("sight_base", 560.0, 604.0, 10.0, 34.0, 10.5, st, bv=1.0, r=3.0)
    prism("sight_leaf", [(566.0, 33.0), (622.0, 36.0), (622.0, 40.0), (566.0, 38.5)], -5.0, 5.0, small, bv=0.5, seg=1)
    box("sight_slider", 604.0, 613.0, 35.0, 42.5, 7.0, small, bv=0.6, seg=1)
    with comp("front"):
        m83_front(st, small, bright, lam)
    with comp("muzzle"):
        m83_muzzle(st, bore)
    return {"rear": Vector((350.0, 0.0, -140.0)), "fore": Vector((655.0, 0.0, -118.0)), "muzzle": Vector((880.0, 0.0, 0.0)), "hands": 2, "length": 0.88,
            "grip": Vector((342.0, 0.0, -83.0)), "hold": Vector((650.0, 0.0, -29.0))}


# ---------------------------------------------------------------- SPREAD-12


S12_MATS = {}
S12_DRUM = (500.0, -186.0, 98.0)        # środek (x, z) i promień bębna 25 — przed kabłąkiem, dłoń na chwycie go nie dotyka


def s12_mats():
    if not S12_MATS:
        X = 300.0
        BLUE = ((0.035, 0.055, 0.12), (0.065, 0.09, 0.165))
        WALNUT = ((0.028, 0.011, 0.005), (0.125, 0.05, 0.02))
        cx, cz, _r = S12_DRUM
        S12_MATS.update({
            "st": M(steel, "s12_steel", blue=BLUE, engrave=[(X + 198.0, X + 258.0, -24.0, -10.0), (X + 28.0, X + 84.0, -31.0, -13.0)], muzzle=(880.0, 960.0),
                    feats=ak_feats(X), grooves=[("x", 21.0, X + 24.0, X + 150.0, 7.5, 12.0, 0.5, False)]),
            "small": M(steel, "s12_small", blue=BLUE, wear_k=0.4),
            "bright": M(steel, "s12_bright", tone="bright"),
            "bore": M(plain, "s12_bore", rgb(0.008, 0.008, 0.008), 0.7, 1.0),
            "choke": M(steel, "s12_choke", blue=BLUE, grooves=[("x", 6.0, 912.0, 952.0, -20.0, 20.0, 0.8, False)]),
            "wood": M(wood, "s12_wood", checker=(3.0, 12.0, 160.0, 250.0, -70.0, -30.0), tone=WALNUT),
            "fore": M(wood, "s12_fore", grooves=[("x", 14.0, 612.0, 742.0, -40.0, -10.0, 1.2, False)], tone=WALNUT),
            "grip": M(bakelite, "s12_grip", checker=(2.2, 100.0), tone=BLACK),
            "drum": M(steel, "s12_drum", tone="paint", blue=((0.012, 0.012, 0.014), (0.03, 0.03, 0.034)), r0=0.6,
                      engrave=[(cx - 27.0, cx + 27.0, cz - 56.0, cz - 41.0)], eng_style=STENCIL),
            "box": M(steel, "s12_box", blue=PARK, r0=0.5, wear_k=0.6),
        })
    return S12_MATS


def s12_drum(cx, cz, R, hw, drum_m, small):
    """Bęben (oś w poprzek broni): płaszcz, dekle z żebrami, piasta i klucz naciągu sprężyny po lewej (+Y); hw = połowa szerokości."""
    revolve("drum", [(-hw, 0.0), (-hw, R - 6.0), (-hw + 2.5, R), (hw - 2.5, R), (hw, R - 6.0), (hw, 0.0)], (cx, cz), drum_m, axis="Y", seg=48, bv=0.6)
    for sy in (-1.0, 1.0):
        for rr in (R * 0.35, R * 0.63, R * 0.86):
            revolve("drum_rib", [(sy * hw, rr - 3.0), (sy * (hw + 1.6), rr - 2.0), (sy * (hw + 1.6), rr + 2.0), (sy * hw, rr + 3.0)], (cx, cz), drum_m, axis="Y",
                    seg=48, bv=0.0)
    revolve("drum_hub", [(hw - 1.0, 0.0), (hw - 1.0, 20.0), (hw + 6.0, 19.0), (hw + 8.0, 15.0), (hw + 8.0, 0.0)], (cx, cz), small, axis="Y", seg=24, bv=0.4)
    box("drum_key", cx - 26.0, cx + 26.0, cz - 5.5, cz + 5.5, 4.0, small, bv=0.8, seg=2, r=4.0, y=hw + 12.0)
    revolve("drum_hub_r", [(-hw - 8.0, 0.0), (-hw - 8.0, 15.0), (-hw - 6.0, 19.0), (-hw + 1.0, 20.0), (-hw + 1.0, 0.0)], (cx, cz), small, axis="Y", seg=24, bv=0.4)


def build_spread12():
    """SPREAD-12 (od 1.7.313): samopowtarzalna strzelba kal. 12 na komorze wzoru AK z bębnem na 25 naboi — jak radzieckie strzelby na mechanizmie
    Kałasznikowa. Niebieska oksyda (znak rozpoznawczy tej broni) i jasny orzech, bęben lakierowany na czarno z kluczem naciągu sprężyny.
    Oś lufy na z = 0, stopka kolby na x = 0, wylot z dławikiem na x = 960 mm."""
    X = 300.0
    mm = s12_mats()
    st, small, bright, bore, choke, wood_m, fore_m, grip_m, drum_m = (mm[k] for k in ("st", "small", "bright", "bore", "choke", "wood", "fore", "grip", "drum"))
    cx, cz, R = S12_DRUM
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("SPREAD-12", 9.5, X + 256.0, -22.0, 16.43, mark)
    marker_text("12 / 76", 7.5, X + 30.0, -27.0, -16.43, mark)
    with comp("mag"):
        marker_text("12x25", 11.0, cx + 23.0, cz - 54.0, 37.93, mark)            # na lewym deklu, między żebrami

    ak_receiver(X, st, small, bright)
    # kolba z orzecha ze stalową stopką, chwyt z czarnego tworzywa, kabłąk
    prism("stock", fillet([(X + 2.0, 3.0, 4.0), (X + 2.0, -36.0, 4.0), (200.0, -54.0, 20.0), (14.0, -110.0, 8.0), (14.0, -22.0, 8.0)]), -15.0, 15.0, wood_m, bv=3.0, seg=2)
    box("butt", 0.0, 16.0, -112.0, -20.0, 15.5, small, bv=1.0, seg=1, r=3.0)
    box("stock_tang", X - 46.0, X + 4.0, 1.0, 5.5, 8.0, st, bv=0.6, seg=1)
    swivel(118.0, -95.0, small)
    pgrip("grip", X + 72.0, -38.0, grip_m)
    trig("trigger", X + 74.0, X + 132.0, -38.0, st, small)
    # gniazdo i wieżyczka podająca bębna, bęben (oś w poprzek broni) — podzespół „mag” (bęben 30 i magazynek pudełkowy go zastępują)
    with comp("mag"):
        box("feed_tower", X + 150.0, X + 228.0, -104.0, -36.0, 14.5, drum_m, bv=1.2, seg=2, r=4.0)
        s12_drum(cx, cz, R, 38.0, drum_m, small)
    # przednia wkładka z celownikiem, rura gazowa, łoże z orzecha, obejma
    box("sight_base", 560.0, 604.0, 12.0, 38.0, 12.5, st, bv=1.0, r=3.0)
    prism("sight_leaf", [(566.0, 37.0), (622.0, 40.0), (622.0, 44.0), (566.0, 42.5)], -5.5, 5.5, small, bv=0.5, seg=1)
    box("sight_slider", 604.0, 613.0, 39.0, 46.5, 7.5, small, bv=0.6, seg=1)
    cyl("barrel", 560.0, 912.0, 11.4, (0.0, 0.0), st, seg=20, bv=0.0)
    cyl("gas_tube", 562.0, 762.0, 7.4, (0.0, 27.0), st, seg=16, bv=0.0)
    cyl("hg_upper", 606.0, 748.0, 15.5, (0.0, 26.0), fore_m, seg=18, bv=1.2)
    prism("hg_lower", fillet([(566.0, 10.0), (750.0, 10.0), (750.0, -24.0, 6.0), (660.0, -36.0, 34.0), (566.0, -33.0, 9.0)]), -18.5, 18.5, fore_m, bv=2.5, seg=2)
    box("hg_cap", 749.0, 760.0, -28.0, 14.0, 19.0, st, bv=0.8, r=3.0)
    # blok gazowy z regulatorem, muszka w osłonie, strzemiączko, dławik wylotowy z nacięciami
    prism("gas_block", fillet([(758.0, -12.0), (798.0, -12.0), (798.0, 13.0, 2.0), (782.0, 37.0, 3.0), (758.0, 37.0, 2.0)]), -12.0, 12.0, st, bv=1.0, seg=2)
    revolve("gas_plug", [(798.0, 0.0), (798.0, 8.5), (812.0, 8.5), (814.0, 6.0), (814.0, 0.0)], (0.0, 27.0), small, seg=16, bv=0.4)
    swivel(776.0, -31.0, small, 7.0)
    box("fs_base", 862.0, 892.0, -13.0, 13.0, 12.5, st, bv=1.0, r=3.0)
    prism("fs_tower", [(865.0, 9.0), (889.0, 9.0), (886.0, 34.0), (868.0, 34.0)], -4.0, 4.0, st, bv=0.6, seg=1)
    for sy in (-1.0, 1.0):
        prism("fs_ear", fillet([(868.0, 32.0), (886.0, 32.0), (884.0, 50.0, 2.0), (870.0, 50.0, 2.0)]), sy * 3.0, sy * 5.8, st, bv=0.4, seg=1)
    revolve("fs_post", [(32.0, 0.0), (32.0, 1.3), (47.0, 1.3), (47.0, 0.0)], (877.0, 0.0), small, axis="Z", seg=8, bv=0.0)
    with comp("muzzle"):
        barrel("choke", 910.0, 960.0, 14.6, 9.25, (0.0, 0.0), choke, bore, depth=40.0, seg=24)
    # dłoń tylna na chwycie pistoletowym, przednia pod łożem
    return {"rear": Vector((350.0, 0.0, -140.0)), "fore": Vector((665.0, 0.0, -124.0)), "muzzle": Vector((960.0, 0.0, 0.0)), "hands": 2, "length": 1.0,
            "grip": Vector((342.0, 0.0, -83.0)), "hold": Vector((660.0, 0.0, -36.0))}


# ---------------------------------------------------------------- LR-7

def lr7_pack(extra, pack, win, warn, rubber):
    """Zasobnik kondensatorów LR-7 w gnieździe magazynka (okienka naładowania, tabliczki ostrzegawcze) i przewód spiralny do głowicy; `extra` mm
    dłuższy w dół (powiększone ogniwo). Podzespół „mag”."""
    zb = -150.0 - extra
    prism("pack", fillet([(440.0, -34.0), (512.0, -34.0), (520.0 + 0.07 * extra, zb, 5.0), (446.0 + 0.05 * extra, zb, 5.0)]), -12.5, 12.5, pack, bv=1.5, seg=2)
    for sy in (-1.0, 1.0):
        box("pack_win", 500.0, 507.0, -104.0 - extra, -60.0, 0.5, win, bv=0.0, seg=1, y=sy * 12.6)
        box("pack_warn", 448.0, 510.0, -132.0 - extra, -114.0 - extra, 0.5, warn, bv=0.2, seg=1, y=sy * 12.8)
    pipe("cable", helix((518.0 + 0.07 * extra, 0.0, -122.0 - extra), (596.0, 0.0, -28.0), 7.0, 9.0 + extra / 12.0), 2.0, rubber, seg=6, smooth=0)


def build_lr7():
    """LR-7: laser impulsowy zabudowany na komorze kbk AK (jak prototypy z lat 80.): żebrowana głowica z prętem i lampą błyskową, ekspander wiązki
    z dużym obiektywem, zasobnik kondensatorów w gnieździe magazynka połączony przewodem spiralnym, celownik optyczny. Obiektyw do x = 900 mm."""
    X = 300.0
    st = M(steel, "lr7_steel", blue=PARK, r0=0.48, engrave=[(X + 198.0, X + 258.0, -24.0, -10.0), (X + 28.0, X + 84.0, -31.0, -13.0)], feats=ak_feats(X))
    small = M(steel, "lr7_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    bright = M(steel, "lr7_bright", tone="bright")
    alu = M(steel, "lr7_alu", blue=((0.05, 0.052, 0.056), (0.085, 0.087, 0.09)), r0=0.48, grooves=[("x", 8.0, 592.0, 766.0, -40.0, 50.0, 2.2, False)])
    pack = M(steel, "lr7_pack", tone="paint", blue=OLIVE, grooves=[("z", 15.0, 436.0, 524.0, -104.0, -62.0, 0.8, True)],
             feats=[("seam", 444.0, 516.0, -146.0, -42.0, 4.0, 0.5), ("rivet", 452.0, -50.0, 2.0), ("rivet", 506.0, -50.0, 2.0)])
    warn = M(steel, "lr7_warn", tone="paint", blue=((0.5, 0.34, 0.02), (0.62, 0.44, 0.04)), engrave=[(446.0, 512.0, -134.0, -112.0)],
             eng_style=(0.0, (0.01, 0.01, 0.01), 0.95), wear_k=0.6)
    lam = M(wood, "lr7_lam", laminate=True, tone=LAMINATE)
    grip_m = M(bakelite, "lr7_grip", checker=(2.2, 100.0), tone=REDBAKE)
    rubber = M(plain, "lr7_rubber", rgb(0.012, 0.012, 0.012), 0.8, 0.0)
    glass = M(plain, "lr7_glass", rgb(0.01, 0.03, 0.05), 0.08, 0.0, rgb(0.03, 0.32, 0.4))
    glass2 = M(plain, "lr7_glass2", rgb(0.012, 0.01, 0.03), 0.08, 0.0)
    win = M(glow, "lr7_win", (0.1, 0.85, 1.0))
    led = M(glow, "lr7_led", (1.0, 0.12, 0.05))
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("LR-7", 9.5, X + 256.0, -22.0, 16.43, mark)
    marker_text("OP 0077", 7.5, X + 30.0, -27.0, -16.43, mark)
    marker_text("LASER", 9.0, 508.0, -127.0, 13.23, mark)
    marker_text("LASER", 9.0, 450.0, -127.0, -13.23, mark)

    ak_receiver(X, st, small, bright)
    revolve("led", [(-17.4, 0.0), (-17.4, 2.6), (17.4, 2.6), (17.4, 0.0)], (X + 60.0, -6.0), led, axis="Y", seg=10, bv=0.0)
    # kolba składana z prętów ze stopką i poduszką policzkową, chwyt, kabłąk
    pipe("stock_top", [(X + 4.0, 0.0, -5.0), (150.0, 0.0, -8.0), (20.0, 0.0, -14.0)], 5.0, small)
    pipe("stock_bot", [(X + 4.0, 0.0, -30.0), (160.0, 0.0, -60.0), (20.0, 0.0, -96.0)], 5.0, small)
    box("butt", 0.0, 22.0, -108.0, -2.0, 13.0, rubber, bv=2.0, r=5.0)
    box("cheek", 104.0, 232.0, -15.0, 6.0, 9.5, lam, bv=2.5, r=6.0)
    pgrip("grip", X + 72.0, -38.0, grip_m)
    trig("trigger", X + 74.0, X + 132.0, -38.0, st, small)
    # zasobnik kondensatorów w gnieździe magazynka: okienko naładowania, tabliczka ostrzegawcza
    with comp("mag"):
        lr7_pack(0.0, pack, win, warn, rubber)
    # głowica: żebrowany korpus między pokrywami na wsporniku, ekspander wiązki, oprawa obiektywu ze szkłem
    box("bracket", 560.0, 602.0, -12.0, 26.0, 12.0, st, bv=1.0, r=3.0)
    cyl("head", 584.0, 772.0, 28.0, (0.0, 6.0), alu, seg=24, bv=0.0)
    cyl("cap_rear", 566.0, 588.0, 31.0, (0.0, 6.0), st, seg=24, bv=1.0)
    cyl("cap_front", 768.0, 790.0, 31.0, (0.0, 6.0), st, seg=24, bv=1.0)
    revolve("expander", [(788.0, 0.0), (788.0, 17.0), (848.0, 27.0), (848.0, 0.0)], (0.0, 6.0), small, seg=24, bv=0.0)
    with comp("muzzle"):
        barrel("objective", 846.0, 900.0, 31.0, 26.5, (0.0, 6.0), small, glass, depth=12.0, seg=24)
    prism("hg_lower", fillet([(566.0, -18.0), (742.0, -18.0), (742.0, -42.0, 6.0), (650.0, -52.0, 30.0), (566.0, -48.0, 8.0)]), -15.5, 15.5, lam, bv=2.5, seg=2)
    # celownik optyczny na wsporniku: tubus, obiektyw, muszla oczna, pokrętło nastaw
    box("mount", 404.0, 470.0, 9.0, 36.0, 7.0, st, bv=0.8, r=2.0)
    cyl("scope", 372.0, 512.0, 11.5, (0.0, 46.0), small, seg=16, bv=0.6)
    barrel("scope_obj", 504.0, 548.0, 15.0, 12.5, (0.0, 46.0), small, glass2, depth=8.0, seg=16)
    cyl("eyecup", 350.0, 376.0, 13.5, (0.0, 46.0), rubber, seg=16, bv=1.0)
    revolve("turret", [(56.0, 0.0), (56.0, 6.5), (67.0, 6.5), (67.0, 0.0)], (440.0, 0.0), small, axis="Z", seg=12, bv=0.5)
    return {"rear": Vector((350.0, 0.0, -140.0)), "fore": Vector((655.0, 0.0, -142.0)), "muzzle": Vector((900.0, 0.0, 6.0)), "hands": 2, "length": 0.9,
            "grip": Vector((342.0, 0.0, -83.0)), "hold": Vector((654.0, 0.0, -51.0))}


# ---------------------------------------------------------------- HKM-9

def hkm_front(e, st, jacket, heat, bore, small, red, brass, pilot):
    """Lufa, osłona perforowana, dysza odbarwiona żarem, naboje zapłonowe i płomyk dyżurny HKM-9; `e` = wylot dyszy (fabrycznie 1000 mm).
    Podzespół „front”."""
    d = e - 1000.0
    cyl("barrel", 478.0, 962.0 + d, 10.0, (0.0, 0.0), st, seg=16, bv=0.0)
    cyl("jacket", 824.0, 936.0 + d, 15.0, (0.0, 0.0), jacket, seg=18, bv=0.6)
    barrel("nozzle", 950.0 + d, e, 13.5, 9.0, (0.0, 0.0), heat, bore, depth=34.0, seg=18)
    box("igniter_plate", 938.0 + d, 946.0 + d, -30.0, 14.0, 20.0, small, bv=0.6, r=4.0)
    for deg in (210.0, 270.0, 330.0):
        a = math.radians(deg)
        cyl("igniter", 940.0 + d, 994.0 + d, 6.5, (19.0 * math.cos(a), 19.0 * math.sin(a)), red, seg=10, bv=0.5)
    cyl("pilot_tube", 900.0, 990.0 + d, 2.6, (0.0, 17.5), brass, seg=8, bv=0.0)
    cyl("pilot_tip", 988.0 + d, 997.0 + d, 3.4, (0.0, 17.5), pilot, seg=8, bv=0.0)


def hkm_tank(x1, r, tank_m, small, brass, dial, red, hose):
    """Zbiornik mieszanki pod lufą (wypukłe dna, obejmy z wieszakami, wlew, manometr, zawór z pokrętłem, wąż w oplocie) od x = 500 do `x1`, promień `r`
    (fabrycznie 726 i 38 mm). Podzespół „tank”."""
    zc = -54.0 - (r - 38.0)
    revolve("tank", [(500.0, 0.0), (500.0, r - 18.0), (512.0, r - 4.0), (526.0, r), (x1 - 26.0, r), (x1 - 12.0, r - 4.0), (x1, r - 18.0), (x1, 0.0)], (0.0, zc),
            tank_m, seg=24, bv=0.0)
    for cx in (540.0, x1 - 38.0):
        cyl("band", cx - 5.0, cx + 5.0, r + 1.4, (0.0, zc), small, seg=24, bv=0.5)
        box("hanger", cx - 5.0, cx + 5.0, -20.0, 6.0, 6.0, small, bv=0.5, seg=1)
    cyl("filler", 484.0, 502.0, 12.0, (0.0, zc), brass, seg=14, bv=0.8)
    box("filler_wing", 480.0, 486.0, zc - 14.0, zc + 14.0, 2.5, brass, bv=0.5, seg=1)
    revolve("gauge", [(-r - 12.0, 0.0), (-r - 12.0, 13.0), (-r + 2.0, 13.0), (-r + 2.0, 0.0)], (632.0, zc), brass, axis="Y", seg=18, bv=0.6)
    revolve("gauge_dial", [(-r - 12.6, 0.0), (-r - 12.6, 10.5), (-r - 11.8, 10.5), (-r - 11.8, 0.0)], (632.0, zc), dial, axis="Y", seg=18, bv=0.0)
    box("gauge_needle", 626.0, 633.0, zc + 7.0, zc + 8.4, 0.3, small, bv=0.0, seg=1, y=-r - 12.9)
    cyl("valve", x1 - 2.0, x1 + 26.0, 9.0, (0.0, zc), brass, seg=12, bv=0.6)
    revolve("valve_wheel", [(-26.0, 0.0), (-26.0, 4.0), (-24.0, 15.0), (-20.0, 15.0), (-18.0, 4.0), (-18.0, 0.0)], (x1 + 14.0, zc), red, axis="Y", seg=14, bv=0.6)
    pipe("hose", [(x1 + 24.0, 0.0, zc), (min(x1 + 64.0, 800.0), 0.0, zc - 3.0), (814.0, 0.0, -38.0), (806.0, 0.0, -9.0)], 5.0, hose)


def build_hkm9():
    """HKM-9: miotacz ognia w układzie karabinowym (jak radzieckie ROKS-3 i LPO-50): drewniana kolba, korpus zaworu ze spustem, zbiornik mieszanki
    z manometrem i zaworem pod lufą, perforowana osłona i trzy naboje zapłonowe przy dyszy. Dysza do x = 1000 mm."""
    st = M(steel, "hkm_steel", blue=PARK, r0=0.48, engrave=[(340.0, 400.0, -24.0, -6.0)],
           feats=[("seam", 330.0, 472.0, -30.0, 0.0, 3.0, 0.5), ("rivet", 338.0, -8.0, 2.4), ("rivet", 464.0, -8.0, 2.4), ("rivet", 464.0, -26.0, 2.4)])
    small = M(steel, "hkm_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    tank_m = M(steel, "hkm_tank", tone="paint", blue=OLIVE, eng_style=STENCIL, wear_k=1.2,
               stencil=[stencil_text("HKM-9", 16.0, 676.0, -60.0, True), stencil_text("PALNE", 16.0, 548.0, -60.0, False)])
    red = M(steel, "hkm_red", tone="paint", blue=((0.2, 0.018, 0.012), (0.32, 0.04, 0.02)), wear_k=1.3)
    jacket = M(steel, "hkm_jacket", blue=BLACKOX, r0=0.5, holes=[(11.0, 3.2, 826.0, 934.0, -11.5, 11.5)])
    heat = M(steel, "hkm_heat", blue=((0.07, 0.04, 0.1), (0.2, 0.12, 0.04)), r0=0.3, wear_k=0.5)               # stal odbarwiona żarem
    bore = M(plain, "hkm_bore", rgb(0.006, 0.006, 0.006), 0.9, 0.0)
    lam = M(wood, "hkm_lam", checker=(3.2, 12.0, 262.0, 318.0, -60.0, -24.0), tone=LAMINATE, laminate=True)
    hose = M(steel, "hkm_hose", blue=((0.02, 0.02, 0.02), (0.04, 0.04, 0.04)), r0=0.7, wear_k=0.2, grooves=[("x", 2.2, 740.0, 830.0, -80.0, 0.0, 0.5, False)])
    dial = M(plain, "hkm_dial", rgb(0.55, 0.53, 0.45), 0.25, 0.0)
    brass = M(steel, "hkm_brass", blue=BRASS, wear_k=0.5)
    pilot = M(glow, "hkm_pilot", (1.0, 0.42, 0.06))
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("HKM-9", 8.0, 342.0, -19.0, -14.93, mark)
    marker_text("1987", 8.0, 398.0, -19.0, 14.93, mark)

    # kolba z klejonki ze stopką, korpus zaworu z dźwignią spustu i kabłąkiem
    top = curve_fn([(22.0, -46.0), (150.0, -36.0), (250.0, -24.0), (290.0, -18.0), (316.0, -8.0), (330.0, -2.0)])
    bot = curve_fn([(22.0, -168.0), (120.0, -142.0), (200.0, -114.0), (250.0, -92.0), (280.0, -66.0), (306.0, -46.0), (330.0, -36.0)])
    wid = curve_fn([(22.0, 20.0), (150.0, 20.5), (250.0, 18.0), (300.0, 14.5), (330.0, 13.5)])
    oval_loft("stock", 22.0, 330.0, top, bot, wid, lam)
    pad = lambda k: oval_sec(20.0 * k, 0.5 * (top(22.0) + bot(22.0)), 0.5 * (top(22.0) - bot(22.0)) * k)
    bevel(loft("pad", [(0.0, pad(0.93)), (4.0, pad(1.02)), (23.0, pad(1.02))], small), 1.2, 2)
    rc = dome_sec(15.0, -36.0, 4.0, 9.0)
    bevel(loft("receiver", [(324.0, rc), (400.0, rc), (480.0, rc)], st), 0.8, 2)
    trig("trigger", 346.0, 420.0, -36.0, st, small)
    prism("valve_lever", fillet([(430.0, 8.0), (468.0, 8.0), (468.0, 14.0, 2.0), (400.0, 32.0, 2.0), (396.0, 26.0, 2.0)]), -4.0, 4.0, small, bv=0.6, seg=1)
    pins("pin", ((352.0, -24.0), (448.0, 2.0)), 15.0, small, 2.4)
    # lufa, osłona perforowana, dysza odbarwiona żarem, trzy naboje zapłonowe na obejmie, płomyk dyżurny
    with comp("front"):
        hkm_front(1000.0, st, jacket, heat, bore, small, red, brass, pilot)
    # zbiornik mieszanki pod lufą: wypukłe dna, obejmy z wieszakami, wlew, manometr, zawór z czerwonym pokrętłem, wąż w oplocie
    with comp("tank"):
        hkm_tank(726.0, 38.0, tank_m, small, brass, dial, red, hose)
    return {"rear": Vector((338.0, 0.0, -120.0)), "fore": Vector((618.0, 0.0, -172.0)), "muzzle": Vector((1000.0, 0.0, 0.0)), "hands": 2, "length": 1.0,
            "grip": Vector((305.0, 0.0, -34.0)), "hold": Vector((615.0, 0.0, -92.0))}


# ---------------------------------------------------------------- WRATH-4

def build_gniew4():
    """WRATH-4: rewolwerowy granatnik 40 mm w układzie Milkor MGL (1983): szkielet z bębnem pod lufą, wysuwana kolba na prętach, kolimator, chwyt
    przedni, żółty pas amunicji odłamkowej. Oś lufy na z = 0 (bęben na z = −27), wylot na x = 770 mm."""
    frame = M(steel, "wr_frame", blue=PARK, r0=0.48, wear_k=1.2)
    drum_m = M(steel, "wr_drum", tone="paint", blue=OLIVE, eng_style=STENCIL,
               stencil=[stencil_text("WRATH-4", 15.0, 432.0, -33.0, True), stencil_text("40 MM HE", 15.0, 324.0, -33.0, False)],
               feats=[("pocket", 326.0, 430.0, -55.0, -44.0, 5.0, 1.8), ("pocket", 326.0, 430.0, -10.0, 1.0, 5.0, 1.8)])
    tube = M(steel, "wr_tube", tone="paint", blue=OLIVE, muzzle=(690.0, 770.0), grooves=[("x", 9.0, 470.0, 560.0, -30.0, 30.0, 0.8, False)])
    small = M(steel, "wr_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    yellow = M(plain, "wr_yellow", rgb(0.5, 0.35, 0.025), 0.55, 0.0)
    bore = M(plain, "wr_bore", rgb(0.008, 0.008, 0.008), 0.8, 1.0)
    grip_m = M(bakelite, "wr_grip", checker=(2.2, 100.0), tone=BLACK)
    lam = M(wood, "wr_lam", laminate=True, tone=LAMINATE, grooves=[("z", 9.0, 540.0, 600.0, -124.0, -40.0, 1.0, True)])
    rubber = M(plain, "wr_rubber", rgb(0.012, 0.012, 0.012), 0.85, 0.0)
    glass = M(plain, "wr_glass", rgb(0.03, 0.008, 0.006), 0.08, 0.0)

    # szkielet: płyty przed i za bębnem, belka górna i dolna; bęben z czterema komorami
    cyl("rear_plate", 296.0, 312.0, 61.0, (0.0, -27.0), frame, seg=28, bv=1.2)
    cyl("front_plate", 444.0, 460.0, 61.0, (0.0, -27.0), frame, seg=28, bv=1.2)
    box("top_strap", 300.0, 458.0, 30.0, 40.0, 10.0, frame, bv=1.0)
    box("bot_strap", 300.0, 458.0, -92.0, -84.0, 12.0, frame, bv=1.0)
    cyl("drum", 314.0, 442.0, 55.0, (0.0, -27.0), drum_m, seg=28, bv=1.5)
    cyl("drum_knob", 460.0, 478.0, 12.0, (0.0, -27.0), small, seg=14, bv=1.0)
    # kolba wysuwana: dwa pręty, stopka gumowa, poduszka policzkowa
    for sy in (-1.0, 1.0):
        pipe("stock_rod", [(300.0, sy * 20.0, 6.0), (24.0, sy * 20.0, 6.0)], 5.5, small, smooth=0)
    box("butt", 0.0, 28.0, -74.0, 34.0, 24.0, rubber, bv=2.5, r=8.0)
    box("cheek", 120.0, 250.0, 2.0, 20.0, 22.0, lam, bv=3.0, r=7.0)
    pgrip("grip", 356.0, -92.0, grip_m)
    trig("trigger", 358.0, 418.0, -92.0, frame, small)
    # lufa z żebrowaną nasadą, żółtym pasem i opaską, chwyt przedni na obejmie
    barrel("barrel", 458.0, 770.0, 26.5, 20.3, (0.0, 0.0), tube, bore, depth=70.0, seg=24)
    cyl("muzzle_ring", 754.0, 770.5, 28.5, (0.0, 0.0), small, seg=24, bv=0.8)
    cyl("he_band", 706.0, 720.0, 26.9, (0.0, 0.0), yellow, seg=24, bv=0.0)
    cyl("fg_clamp", 556.0, 586.0, 29.0, (0.0, 0.0), small, seg=24, bv=0.8)
    prism("foregrip", fillet([(556.0, -24.0, 3.2), (586.0, -24.0, 3.2), (582.0, -128.0, 7.0), (556.0, -128.0, 7.0)]), -13.0, 13.0, lam, bv=2.5, seg=2)
    swivel(640.0, -44.0, small, 7.0)
    # kolimator na wsporniku z pokrętłem odległości, muszka
    box("sight_mount", 346.0, 410.0, 40.0, 54.0, 7.0, frame, bv=0.8, r=2.0)
    cyl("sight_tube", 326.0, 424.0, 13.5, (0.0, 66.0), small, seg=16, bv=0.8)
    barrel("sight_lens", 416.0, 432.0, 14.5, 12.0, (0.0, 66.0), small, glass, depth=5.0, seg=16)
    revolve("sight_knob", [(-22.0, 0.0), (-22.0, 7.0), (-9.0, 7.0), (-9.0, 0.0)], (378.0, 50.0), small, axis="Y", seg=12, bv=0.6)
    prism("front_sight", fillet([(738.0, 24.0), (752.0, 24.0), (749.0, 44.0, 1.5), (741.0, 44.0, 1.5)]), -2.5, 2.5, small, bv=0.5, seg=1)
    return {"rear": Vector((334.0, 0.0, -182.0)), "fore": Vector((571.0, 0.0, -176.0)), "muzzle": Vector((770.0, 0.0, 0.0)), "hands": 2, "length": 0.77,
            "grip": Vector((326.0, 0.0, -137.0)), "hold": Vector((571.0, 0.0, -80.0)), "hold_v": True}


# ---------------------------------------------------------------- FALCON-6

def fa_drum(R, hw, drum_m, small):
    """Bęben taśmy FALCON-6 z gardzielą i kluczem sprężyny; promień `R`, połowa szerokości `hw` (fabrycznie 58 i 17 mm). Podzespół „mag”."""
    cz = -54.0 - R
    prism("mag_throat", fillet([(444.0, -34.0), (502.0, -34.0), (500.0, -70.0), (450.0, -70.0)]), -11.5, 11.5, drum_m, bv=1.0, seg=1)
    revolve("drum", [(-hw, 0.0), (-hw, R - 4.0), (-hw + 3.0, R), (hw - 3.0, R), (hw, R - 4.0), (hw, 0.0)], (476.0, cz), drum_m, axis="Y", seg=28, bv=0.0)
    revolve("drum_hub", [(-hw - 4.0, 0.0), (-hw - 4.0, 9.0), (hw + 4.0, 9.0), (hw + 4.0, 0.0)], (476.0, cz), small, axis="Y", seg=14, bv=0.6)
    box("drum_key", 476.0 - 0.31 * R, 476.0 + 0.31 * R, cz - 3.0, cz + 3.0, 1.5, small, bv=0.4, seg=1, y=-hw - 5.5)


def fa_optic(r_obj, r_ir, navy, small, glass, rubber, ir):
    """Celownik noktowizyjny FALCON-6 z reflektorem podczerwieni: tubus, obiektyw o promieniu `r_obj`, muszla, baterie, reflektor o promieniu `r_ir`
    (fabrycznie 29 i 14 mm). Podzespół „optic”."""
    cyl("nsp", 392.0, 548.0, 23.0, (0.0, 58.0), navy, seg=22, bv=1.0)
    barrel("nsp_obj", 540.0, 600.0 + (r_obj - 29.0), r_obj, r_obj - 5.0, (0.0, 58.0), navy, glass, depth=16.0, seg=22)
    cyl("nsp_eye", 354.0, 394.0, 15.0, (0.0, 58.0), rubber, seg=16, bv=1.0)
    box("nsp_batt", 418.0, 500.0, 78.0, 96.0, 12.0, navy, bv=1.0, r=3.0)
    zl = 83.0 + r_ir
    barrel("ir_lamp", 500.0, 546.0 + 2.0 * (r_ir - 14.0), r_ir, r_ir - 2.5, (0.0, zl), small, ir, depth=6.0, seg=16)


def build_sokol6():
    """FALCON-6: karabinek na mikrorakiety (idea Gyrojeta) na komorze AK: prowadnica w osłonie ze szczelinami na gazy, magazynek bębnowy, kolba RPK,
    złożony dwójnóg, celownik noktowizyjny z reflektorem podczerwieni w szaroniebieskiej emalii. Wylot na x = 950 mm."""
    X = 290.0
    st = M(steel, "fa_steel", blue=PARK, r0=0.48, engrave=[(X + 198.0, X + 260.0, -24.0, -10.0), (X + 28.0, X + 84.0, -31.0, -13.0)], feats=ak_feats(X))
    small = M(steel, "fa_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    bright = M(steel, "fa_bright", tone="bright")
    shroud = M(steel, "fa_shroud", tone="paint", blue=NAVY, feats=[("slot", 592.0 + i * 46.0, 626.0 + i * 46.0, -4.6, 4.6, 4.5, 1.6) for i in range(5)])
    navy = M(steel, "fa_navy", tone="paint", blue=NAVY, wear_k=1.2)
    drum_m = M(steel, "fa_drum", blue=BLACKOX, r0=0.45, wear_k=1.2,
               feats=[("seam", 426.0, 526.0, -162.0, -62.0, 50.0, 0.7), ("seam", 452.0, 500.0, -136.0, -88.0, 24.0, 0.7)]
               + [("rivet", 476.0 + 37.0 * math.cos(math.radians(a)), -112.0 + 37.0 * math.sin(math.radians(a)), 2.2) for a in range(0, 360, 60)])
    bore = M(plain, "fa_bore", rgb(0.008, 0.008, 0.008), 0.8, 1.0)
    lam = M(wood, "fa_lam", laminate=True, tone=LAMINATE)
    grip_m = M(bakelite, "fa_grip", checker=(2.2, 100.0), tone=REDBAKE)
    rubber = M(plain, "fa_rubber", rgb(0.012, 0.012, 0.012), 0.8, 0.0)
    glass = M(plain, "fa_glass", rgb(0.012, 0.03, 0.02), 0.08, 0.0)
    ir = M(plain, "fa_ir", rgb(0.06, 0.004, 0.003), 0.1, 0.0, rgb(0.55, 0.04, 0.02))
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("FALCON-6", 8.0, X + 258.0, -22.0, 16.43, mark)
    marker_text("MR 15 MM", 7.0, X + 30.0, -27.0, -16.43, mark)

    ak_receiver(X, st, small, bright)
    # kolba RPK z „kopytem" z klejonki, chwyt, kabłąk
    prism("stock", fillet([(X + 2.0, 6.0, 4.0), (X + 2.0, -36.0, 4.0), (214.0, -46.0, 14.0), (132.0, -58.0, 30.0), (98.0, -104.0, 10.0), (14.0, -112.0, 6.0),
                           (14.0, -18.0, 8.0)]), -14.0, 14.0, lam, bv=3.0, seg=2)
    box("butt", 0.0, 16.0, -114.0, -16.0, 14.5, small, bv=1.0, seg=1, r=3.0)
    swivel(170.0, -66.0, small, 7.0)
    pgrip("grip", X + 72.0, -38.0, grip_m)
    trig("trigger", X + 74.0, X + 132.0, -38.0, st, small)
    # magazynek bębnowy z gardzielą i kluczem sprężyny
    with comp("mag"):
        fa_drum(58.0, 17.0, drum_m, small)
    # przednia wkładka z celownikiem, prowadnica w osłonie ze szczelinami, podstawa muszki, nasadka wylotowa
    box("trunnion", 550.0, 580.0, -14.0, 22.0, 12.0, st, bv=1.0, r=3.0)
    prism("sight_leaf", [(556.0, 21.0), (604.0, 24.0), (604.0, 28.0), (556.0, 26.5)], -5.0, 5.0, small, bv=0.5, seg=1)
    cyl("barrel", 552.0, 906.0, 10.5, (0.0, 0.0), st, seg=16, bv=0.0)
    cyl("shroud", 578.0, 826.0, 17.0, (0.0, 0.0), shroud, seg=20, bv=0.8)
    cyl("shroud_cap", 822.0, 834.0, 18.6, (0.0, 0.0), st, seg=20, bv=0.8)
    box("fs_base", 852.0, 874.0, -11.0, 11.0, 10.5, st, bv=1.0, r=3.0)
    prism("fs_tower", fillet([(855.0, 8.0), (871.0, 8.0), (868.0, 40.0, 1.5), (858.0, 40.0, 1.5)]), -3.0, 3.0, st, bv=0.6, seg=1)
    barrel("booster", 902.0, 950.0, 15.0, 10.6, (0.0, 0.0), small, bore, depth=36.0, seg=18)
    # dwójnóg złożony pod osłoną
    box("bipod_hub", 836.0, 850.0, -25.0, -8.0, 9.5, small, bv=0.6)
    for sy in (-1.0, 1.0):
        pipe("leg", [(843.0, sy * 7.0, -22.0), (760.0, sy * 8.0, -29.0), (640.0, sy * 8.0, -29.0)], 3.2, small, smooth=0)
        box("leg_foot", 632.0, 646.0, -34.0, -25.0, 2.5, small, bv=0.5, seg=1, y=sy * 8.0)
    box("leg_clip", 664.0, 672.0, -34.0, -18.0, 11.5, small, bv=0.4, seg=1)
    # celownik noktowizyjny: tubus, obiektyw, muszla oczna, pojemnik baterii, reflektor podczerwieni
    box("mount", 398.0, 482.0, 9.0, 37.0, 8.0, st, bv=0.8, r=2.0)
    with comp("optic"):
        fa_optic(29.0, 14.0, navy, small, glass, rubber, ir)
    return {"rear": Vector((340.0, 0.0, -140.0)), "fore": Vector((650.0, 0.0, -128.0)), "muzzle": Vector((950.0, 0.0, 0.0)), "hands": 2, "length": 0.95,
            "grip": Vector((332.0, 0.0, -83.0)), "hold": Vector((650.0, 0.0, -18.0))}


# ---------------------------------------------------------------- SPECTER-1

def sp_bank(r, zb, small, can):
    """Bateria pięciu kondensatorów SPECTER-1 w korytku z opaską: promień puszki `r`, spód na z = `zb` (fabrycznie 16,5 i −104 mm). Podzespół „mag”."""
    box("tray", 476.0, 676.0, -52.0, -40.0, r + 2.5, small, bv=1.0)
    for i in range(5):
        revolve("can", [(zb, 0.0), (zb, r), (-46.0, r), (-46.0, 0.0)], (500.0 + i * 38.0, 0.0), can, axis="Z", seg=14, bv=0.8)
    box("can_strap", 480.0, 672.0, zb + 20.0, zb + 26.0, r + 0.9, small, bv=0.4, seg=1)


def build_widmo1():
    """SPECTER-1: karabin elektromagnetyczny cewkowy — osiem uzwojeń miedzianych na rurze z tekstolitu z modułami łączników i lampkami, szyny
    zbiorcze, bateria kondensatorów elektrolitycznych pod komorą, przewody plus i minus, dźwignia ładowania. Wylot na x = 1150 mm."""
    body = M(steel, "sp_body", blue=PARK, r0=0.48,
             feats=[("seam", 308.0, 552.0, -34.0, 16.0, 4.0, 0.55), ("rivet", 316.0, -27.0, 2.6), ("rivet", 316.0, 9.0, 2.6), ("rivet", 544.0, -27.0, 2.6),
                    ("rivet", 544.0, 9.0, 2.6), ("rivet", 430.0, 9.0, 2.6)] + [("ridge", 326.0 + i * 13.0, 333.0 + i * 13.0, -24.0, 2.0, 2.5, 0.9) for i in range(5)])
    small = M(steel, "sp_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    plate = M(steel, "sp_plate", blue=BRASS, wear_k=0.4, engrave=[(440.0, 532.0, -17.0, 7.0)], eng_style=(0.25, (0.02, 0.015, 0.01), 0.9))
    copper = M(steel, "sp_copper", blue=COPPER, r0=0.35, wear_k=0.25, grooves=[("x", 1.9, 600.0, 1080.0, -40.0, 40.0, 0.45, False)])
    bus = M(steel, "sp_bus", blue=COPPER, r0=0.3, wear_k=0.6)
    phen = M(bakelite, "sp_phen", tone=PHENOL)
    poly = M(bakelite, "sp_poly", tone=BLACK)
    can = M(steel, "sp_can", tone="paint", blue=((0.012, 0.035, 0.12), (0.025, 0.06, 0.17)), wear_k=0.6, grooves=[("z", 30.0, 470.0, 690.0, -104.0, -50.0, 0.4, False)])
    bore = M(plain, "sp_bore", rgb(0.008, 0.008, 0.008), 0.8, 1.0)
    lam = M(wood, "sp_lam", laminate=True, tone=LAMINATE)
    grip_m = M(bakelite, "sp_grip", checker=(2.2, 100.0), tone=BLACK)
    rubber = M(plain, "sp_rubber", rgb(0.012, 0.012, 0.012), 0.8, 0.0)
    cab_p = M(plain, "sp_cab_p", rgb(0.22, 0.02, 0.014), 0.6, 0.0)
    red = M(plain, "sp_knob", rgb(0.3, 0.02, 0.015), 0.45, 0.0)
    lamp = M(glow, "sp_lamp", (0.12, 0.85, 1.0))
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("SPECTER-1", 9.5, 530.0, -9.0, 20.93, mark)
    marker_text("2,4 MJ  WN", 9.5, 444.0, -9.0, -20.93, mark)

    box("receiver", 300.0, 560.0, -40.0, 22.0, 20.0, body, bv=1.2, r=3.0)
    for sy in (-1.0, 1.0):
        box("plate", 442.0, 530.0, -15.0, 5.0, 0.5, plate, bv=0.2, seg=1, y=sy * 20.5)
    box("top_rail", 330.0, 540.0, 21.0, 28.0, 7.0, small, bv=0.8)
    # dźwignia ładowania po prawej (−Y) z czerwoną gałką
    prism("lever", strip([(352.0, -8.0), (372.0, 12.0), (392.0, 30.0)], 6.0), -24.0, -21.0, small, bv=0.5, seg=1)
    revolve("lever_knob", [(-32.0, 0.0), (-31.0, 4.5), (-27.0, 6.5), (-23.0, 4.5), (-22.0, 0.0)], (393.0, 31.0), red, axis="Y", seg=12, bv=0.0)
    revolve("lever_pivot", [(-25.0, 0.0), (-25.0, 6.0), (-20.0, 6.0), (-20.0, 0.0)], (352.0, -8.0), small, axis="Y", seg=12, bv=0.5)
    # kolba z prętów ze stopką i poduszką policzkową, chwyt, kabłąk
    pipe("stock_top", [(304.0, 0.0, 6.0), (150.0, 0.0, 2.0), (20.0, 0.0, -6.0)], 6.0, small)
    pipe("stock_bot", [(304.0, 0.0, -30.0), (160.0, 0.0, -62.0), (20.0, 0.0, -100.0)], 6.0, small)
    box("butt", 0.0, 22.0, -112.0, 6.0, 14.0, rubber, bv=2.0, r=5.0)
    box("cheek", 104.0, 236.0, -6.0, 16.0, 10.0, lam, bv=2.5, r=6.0)
    pgrip("grip", 384.0, -40.0, grip_m)
    trig("trigger", 386.0, 446.0, -40.0, body, small)
    # bateria kondensatorów: pięć puszek w korytku z opaską
    with comp("mag"):
        sp_bank(16.5, -104.0, small, can)
    # lufa: rura z tekstolitu, osiem uzwojeń z podkładkami, moduły łączników z lampkami, szyny zbiorcze
    box("breech", 556.0, 592.0, -26.0, 26.0, 18.0, body, bv=1.0, r=4.0)
    cyl("tube", 560.0, 1100.0, 13.0, (0.0, 0.0), phen, seg=16, bv=0.0)
    for i in range(8):
        cx = 628.0 + i * 60.0
        cyl("coil", cx - 17.0, cx + 17.0, 26.0, (0.0, 0.0), copper, seg=20, bv=0.6)
        cyl("washer", cx - 21.0, cx - 17.0, 30.0, (0.0, 0.0), small, seg=20, bv=0.4)
        cyl("washer", cx + 17.0, cx + 21.0, 30.0, (0.0, 0.0), small, seg=20, bv=0.4)
        box("module", cx - 11.0, cx + 11.0, 26.0, 40.0, 7.5, poly, bv=0.8)
        revolve("lamp", [(40.0, 0.0), (40.0, 3.4), (43.5, 3.4), (45.5, 1.6), (45.5, 0.0)], (cx + 3.0, 0.0), lamp, axis="Z", seg=8, bv=0.0)
    for sy in (-1.0, 1.0):
        box("bus_top", 584.0, 1066.0, 40.0, 42.6, 1.4, bus, bv=0.3, seg=1, y=sy * 5.6)
    box("bus_bot", 584.0, 1066.0, -33.4, -30.6, 5.0, bus, bv=0.3, seg=1)
    # tarcza wylotowa i końcówka lufy, łoże pod uzwojeniami, przewody od kondensatorów do szyn
    cyl("shield", 1090.0, 1101.0, 36.0, (0.0, 0.0), small, seg=22, bv=0.8)
    barrel("muzzle", 1098.0, 1150.0, 18.0, 9.0, (0.0, 0.0), small, bore, depth=40.0, seg=18)
    prism("forend", fillet([(692.0, -33.0), (832.0, -33.0), (828.0, -58.0, 8.0), (702.0, -62.0, 8.0)]), -15.0, 15.0, lam, bv=2.5, seg=2)
    pipe("cable_p", [(522.0, -21.0, -48.0), (552.0, -27.0, -20.0), (576.0, -16.0, 22.0), (592.0, -6.0, 41.0)], 4.2, cab_p)
    pipe("cable_n", [(560.0, 21.0, -48.0), (580.0, 25.0, -42.0), (592.0, 12.0, -33.0)], 4.2, rubber)
    return {"rear": Vector((362.0, 0.0, -142.0)), "fore": Vector((760.0, 0.0, -162.0)), "muzzle": Vector((1150.0, 0.0, 0.0)), "hands": 2, "length": 1.15,
            "grip": Vector((354.0, 0.0, -85.0)), "hold": Vector((762.0, 0.0, -61.0))}


# ---------------------------------------------------------------- SINEW-6

def build_ciegno6():
    """SINEW-6: kusza-harpun na gumowych cięgnach, zbudowana jak tekowe kusze podwodne: belka z prowadnicą, mechanizm spustowy ze stali nierdzewnej,
    dwie pary lateksowych cięgien z zaczepami, harpun z płetwami i ruchomym zadziorem, mosiężny kołowrotek z linką. Grot do x = 1110 mm."""
    inox = M(steel, "sn_inox", tone="bright", r0=0.3, wear_k=0.3, engrave=[(374.0, 452.0, -9.0, 7.0)], eng_style=(0.2, (0.03, 0.03, 0.03), 0.8),
             feats=[("hole", 950.0, 14.0, 3.2), ("hole", 950.0, -6.0, 3.2), ("rivet", 378.0, 8.0, 1.8), ("rivet", 448.0, 8.0, 1.8)])
    small = M(steel, "sn_small", blue=BLACKOX, r0=0.42, wear_k=0.4)
    stock_m = M(wood, "sn_stock", checker=(3.2, 12.0, 296.0, 352.0, -62.0, -24.0), tone=TEAK, laminate=True)
    beam_m = M(wood, "sn_beam", tone=TEAK, laminate=True)
    latex = M(plain, "sn_latex", rgb(0.3, 0.14, 0.025), 0.45, 0.0)
    rubber = M(plain, "sn_rubber", rgb(0.012, 0.012, 0.012), 0.85, 0.0)
    brass = M(steel, "sn_brass", blue=BRASS, wear_k=0.5)
    rope = M(plain, "sn_rope", rgb(0.5, 0.46, 0.36), 0.9, 0.0)
    mark = M(plain, "marker", rgb(0.0, 0.0, 0.0), 1.0, 0.0)
    marker_text("SINEW-6", 8.0, 450.0, -4.0, 16.13, mark)
    marker_text("K 0612", 8.0, 378.0, -4.0, -16.13, mark)

    # kolba z szyjką (rybka) i gumową stopką do napinania, belka z prowadnicą
    top = curve_fn([(22.0, -48.0), (150.0, -38.0), (270.0, -26.0), (320.0, -20.0), (350.0, -8.0), (368.0, 4.0)])
    bot = curve_fn([(22.0, -170.0), (120.0, -144.0), (200.0, -118.0), (262.0, -100.0), (292.0, -88.0), (318.0, -68.0), (345.0, -50.0), (368.0, -36.0)])
    wid = curve_fn([(22.0, 20.0), (150.0, 20.5), (260.0, 19.0), (300.0, 16.5), (340.0, 15.0), (368.0, 15.0)])
    oval_loft("stock", 22.0, 368.0, top, bot, wid, stock_m)
    pad = lambda k: oval_sec(20.0 * k, 0.5 * (top(22.0) + bot(22.0)), 0.5 * (top(22.0) - bot(22.0)) * k)
    bevel(loft("pad", [(0.0, pad(0.93)), (5.0, pad(1.03)), (24.0, pad(1.03))], rubber), 1.5, 2)
    oval_loft("beam", 362.0, 968.0, curve_fn([(362.0, 6.0), (968.0, 6.0)]), curve_fn([(362.0, -36.0), (520.0, -37.0), (800.0, -29.0), (968.0, -18.0)]),
              curve_fn([(362.0, 15.0), (600.0, 15.0), (968.0, 12.0)]), beam_m, n=18)
    # mechanizm spustowy, kabłąk, bezpiecznik
    box("mech", 372.0, 454.0, -10.0, 12.0, 16.2, inox, bv=0.8, r=2.5)
    trig("trigger", 388.0, 448.0, -35.0, inox, small)
    revolve("safety", [(-17.5, 0.0), (-17.5, 3.5), (17.5, 3.5), (17.5, 0.0)], (364.0, -12.0), brass, axis="Y", seg=12, bv=0.4)
    # harpun: pręt z płetwami zaczepów, ostrze i ruchomy zadzior; głowica z otworami cięgien
    cyl("shaft", 392.0, 1070.0, 3.6, (0.0, 13.0), inox, seg=10, bv=0.0)
    for cx in (470.0, 524.0):
        prism("fin", [(cx, 16.0), (cx + 11.0, 16.0), (cx + 3.5, 23.0)], -1.0, 1.0, inox, bv=0.2, seg=1)
    with comp("tip"):
        revolve("tip", [(1066.0, 0.0), (1066.0, 5.2), (1080.0, 5.2), (1110.0, 0.6), (1110.0, 0.0)], (0.0, 13.0), inox, seg=8, bv=0.0)
        prism("barb", [(1078.0, 17.5), (1044.0, 31.0), (1039.0, 28.0), (1060.0, 17.5)], -2.2, 2.2, inox, bv=0.4, seg=1)
    box("muzzle", 938.0, 972.0, -18.0, 26.0, 14.5, inox, bv=1.0, r=5.0)
    # cięgna: dwie pary gum od głowicy do zaczepów z linki na płetwach
    for sy in (-1.0, 1.0):
        pipe("band", [(954.0, sy * 16.0, 14.0), (800.0, sy * 15.0, 17.0), (640.0, sy * 11.0, 19.0), (542.0, sy * 6.0, 19.0)], 4.6, latex)
        pipe("band", [(954.0, sy * 16.0, -6.0), (790.0, sy * 16.5, 2.0), (610.0, sy * 14.0, 12.0), (488.0, sy * 6.0, 19.0)], 4.6, latex)
    for cx in (470.0, 524.0):
        pipe("wishbone", [(cx + 18.0, -6.0, 19.0), (cx + 7.0, -2.2, 21.5), (cx + 7.0, 2.2, 21.5), (cx + 18.0, 6.0, 19.0)], 1.3, rope, seg=5, smooth=0)
    # kołowrotek: mosiężne boki, linka, korbka, pokrętło hamulca; linka biegnie do suwaka na harpunie
    box("reel_arm", 748.0, 772.0, -56.0, -24.0, 5.0, inox, bv=0.8)
    revolve("reel", [(-11.0, 0.0), (-11.0, 34.0), (-8.5, 34.0), (-8.5, 20.0), (8.5, 20.0), (8.5, 34.0), (11.0, 34.0), (11.0, 0.0)], (760.0, -64.0), brass,
            axis="Y", seg=22, bv=0.4)
    revolve("line_spool", [(-8.3, 0.0), (-8.3, 28.0), (8.3, 28.0), (8.3, 0.0)], (760.0, -64.0), rope, axis="Y", seg=22, bv=0.0)
    revolve("reel_hub", [(-14.0, 0.0), (-14.0, 7.0), (14.0, 7.0), (14.0, 0.0)], (760.0, -64.0), small, axis="Y", seg=12, bv=0.5)
    revolve("crank", [(-25.0, 0.0), (-25.0, 3.6), (-11.0, 3.6), (-11.0, 0.0)], (779.0, -79.0), small, axis="Y", seg=10, bv=0.5)
    pipe("line", [(772.0, 0.0, -34.0), (900.0, 0.0, -24.0), (966.0, 0.0, -20.0), (984.0, 0.0, 0.0), (1000.0, 0.0, 9.5)], 1.0, rope, seg=5, smooth=0)
    return {"rear": Vector((338.0, 0.0, -120.0)), "fore": Vector((610.0, 0.0, -130.0)), "muzzle": Vector((1110.0, 0.0, 13.0)), "hands": 2, "length": 1.11,
            "grip": Vector((332.0, 0.0, -38.0)), "hold": Vector((610.0, 0.0, -36.0))}


# ---------------------------------------------------------------- broń biała: maczeta, kilof

def mc_blade(k, half_t, flats, grind):
    """Głownia maczety o klinowym przekroju (ciemne płazy, jasny szlif): `k` = współczynnik szerokości, `half_t` = połowa grubości grzbietu
    (fabrycznie 1 i 1,7 mm). Podzespół „blade”."""
    top = curve_fn([(148.0, 17.0), (300.0, 21.0 * k), (480.0, 25.0 * k), (560.0, 22.0 * k), (598.0, 7.0)])
    bot = curve_fn([(148.0, -17.0), (250.0, -24.0 * k), (400.0, -32.0 * k), (520.0, -33.0 * k), (575.0, -18.0 * k), (598.0, 3.0)])
    secs = []
    for i in range(22):
        xs = 150.0 + (598.0 - 150.0) * i / 21
        zt, zb = top(xs), bot(xs)
        zm = zb + 0.38 * (zt - zb)
        secs.append((xs, [(-half_t, zt), (half_t, zt), (half_t, zm), (0.08, zb), (-0.08, zb), (-half_t, zm)]))
    blade = bevel(loft("blade", secs, flats), 0.0)
    if grind is not None:
        blade.data.materials.append(grind)
        for q in blade.data.polygons:
            if -0.5 < q.normal.z < -0.02:
                q.material_index = 1


def mc_handle(ext, wd, brass):
    """Rękojeść maczety z drewnianymi okładzinami na mosiężnych nitach; `ext` mm dłuższa do tyłu (fabrycznie 0). Podzespół „grip”."""
    x0 = -ext
    oval_loft("handle", x0, 142.0, curve_fn([(x0, 19.0), (x0 + 20.0, 17.0), (70.0, 15.5), (120.0, 16.5), (142.0, 17.0)]),
              curve_fn([(x0, -26.0), (x0 + 18.0, -21.0), (70.0, -16.0), (120.0, -17.0), (142.0, -17.0)]), curve_fn([(x0, 11.5), (70.0, 10.5), (142.0, 10.5)]),
              wd, n=12)
    pins("rivet", tuple([(30.0 - ext, 0.0)] + ([(30.0 - ext * 0.5, 0.0)] if ext > 0.0 else []) + [(72.0, 0.0), (114.0, 0.5)]), 10.8, brass, 3.2)


def build_maczeta():
    """Maczeta: głownia o klinowym przekroju (ciemne płazy, jasny szlif), drewniane okładziny na mosiężnych nitach. Sztych na x = 598 mm."""
    flats = M(steel, "mc_flats", blue=((0.08, 0.08, 0.085), (0.14, 0.135, 0.128)), wear_k=0.8)
    grind = M(steel, "mc_grind", tone="bright", grooves=[("x", 7.0, 156.0, 262.0, -40.0, -6.0, 1.0, False)])
    st = M(steel, "mc_steel", blue=GREY, wear_k=0.7)
    wd = M(wood, "mc_wood", tone=((0.07, 0.04, 0.014), (0.26, 0.16, 0.06)))
    brass = M(plain, "mc_brass", rgb(0.55, 0.38, 0.1), 0.35, 1.0)
    with comp("blade"):
        mc_blade(1.0, 1.7, flats, grind)
    box("guard", 140.0, 152.0, -25.0, 25.0, 7.0, st, bv=1.0, r=3.0)
    with comp("grip"):
        mc_handle(0.0, wd, brass)
    return {"rear": Vector((72.0, 0.0, -85.0)), "fore": None, "muzzle": Vector((598.0, 0.0, 5.0)), "hands": 1, "length": 0.6, "grip": Vector((72.0, 0.0, 0.0))}


def kf_head(k, head):
    """Dwustronne ostrze kilofa z oczkiem; `k` = grubość i masywność (fabrycznie 1). Podzespół „head”."""
    prism("pick", strip(spline([(606.0, 212.0), (652.0, 136.0), (681.0, 62.0), (690.0, 0.0), (681.0, -62.0), (652.0, -136.0), (606.0, -212.0)], 5),
                        lambda t: 9.0 * k + 36.0 * k * (1.0 - abs(2.0 * t - 1.0)) ** 0.8), -13.0 * k, 13.0 * k, head, bv=2.5, seg=2)
    box("eye", 660.0 - 6.0 * (k - 1.0) * 10.0, 720.0 + 4.0 * (k - 1.0) * 10.0, -30.0 * k, 30.0 * k, 20.0 * k, head, bv=1.5, r=6.0)


def build_kilof():
    """Kilof: dwustronne ostrze na krótkim trzonku. Trzonek wzdłuż X od 0, głowica przy x = 690 mm, ostrza do z = ±212 mm."""
    head = M(steel, "kf_head", blue=((0.08, 0.08, 0.085), (0.14, 0.135, 0.128)), wear_k=1.3)
    wd = M(wood, "kf_wood", tone=((0.06, 0.032, 0.012), (0.24, 0.14, 0.055)))
    oval_loft("handle", 0.0, 702.0, curve_fn([(0.0, 24.0), (40.0, 20.0), (350.0, 18.0), (640.0, 20.0), (702.0, 21.0)]),
              curve_fn([(0.0, -24.0), (40.0, -20.0), (350.0, -18.0), (640.0, -20.0), (702.0, -21.0)]), curve_fn([(0.0, 16.0), (350.0, 14.0), (702.0, 15.0)]), wd, n=16)
    with comp("head"):
        kf_head(1.0, head)
    return {"rear": Vector((150.0, 0.0, -85.0)), "fore": None, "muzzle": Vector((606.0, 0.0, 212.0)), "hands": 1, "length": 0.72, "grip": Vector((150.0, 0.0, 0.0))}


BUILDERS = {"m83": build_m83, "spread12": build_spread12, "p64": build_p83, "srut8": build_srut8, "lr7": build_lr7, "hkm9": build_hkm9, "gniew4": build_gniew4,
            "sokol6": build_sokol6, "widmo1": build_widmo1, "ciegno6": build_ciegno6, "maczeta": build_maczeta, "kilof": build_kilof}


# ---------------------------------------------------------------- siatka końcowa, UV, wypiek, eksport


# ---------------------------------------------------------------- części broni (parts.gd, etap 2b): bryły w układzie broni w mm

def part_m83_rpk40(spec):
    mm = m83_mats()
    m83_mag(mm["mag"], mm["small"], extra=55.0)
    return {"mount": "frame", "hides": ["mag"]}


def part_m83_drum75(spec):
    """Bęben RPK na 75 naboi: szyjka w gnieździe magazynka, bęben o osi w poprzek broni przed kabłąkiem, piasta z kluczem."""
    mm = m83_mats()
    drum_m = M(steel, "m83_drum", tone="paint", blue=((0.012, 0.012, 0.014), (0.03, 0.03, 0.034)), r0=0.6)
    prism("drum_neck", fillet([(452.0, -28.0), (498.0, -28.0), (502.0, -84.0, 4.0), (452.0, -84.0, 4.0)]), -12.0, 12.0, mm["mag"], bv=1.2, seg=2)
    s12_drum(500.0, -128.0, 72.0, 34.0, drum_m, mm["small"])
    return {"mount": "frame", "hides": ["mag"]}


def part_m83_rpkbar(spec):
    mm = m83_mats()
    m83_front(mm["st"], mm["small"], mm["bright"], mm["lam"], hg_end=746.0, muzzle_end=1000.0, heavy=1.4)
    return {"mount": "frame", "hides": ["front"], "muzzle": Vector((1000.0, 0.0, 0.0))}


def part_m83_short(spec):
    mm = m83_mats()
    m83_front(mm["st"], mm["small"], mm["bright"], mm["lam"], hg_end=660.0, muzzle_end=760.0, bayonet=False)
    return {"mount": "frame", "hides": ["front"], "muzzle": Vector((760.0, 0.0, 0.0))}


def part_m83_pbs1(spec):
    """Tłumik PBS-1: gwint, dwa człony puszki (tylny grubszy z przegrodami, przedni z gumową zatyczką), kanał od czoła."""
    mm = m83_mats()
    e = 880.0
    cyl("thread_ring", e - 34.0, e - 29.0, 10.4, (0.0, 0.0), mm["st"], seg=16, bv=0.4)
    cyl("can_rear", e - 30.0, e + 92.0, 17.5, (0.0, 0.0), mm["st"], seg=24, bv=0.8)
    cyl("can_joint", e + 92.0, e + 100.0, 18.6, (0.0, 0.0), mm["small"], seg=24, bv=0.5)
    barrel("can_front", e + 100.0, e + 166.0, 16.0, 4.6, (0.0, 0.0), mm["st"], mm["bore"], depth=30.0, seg=24)
    return {"mount": "muzzle", "hides": ["muzzle"], "muzzle_add": 166.0}


def part_m83_hider(spec):
    """Płomieniotłumik szczelinowy: walec z czterema szczelinami na końcu (zamiast skośnego kompensatora)."""
    mm = m83_mats()
    e = 880.0
    cyl("thread_ring", e - 34.0, e - 29.0, 10.4, (0.0, 0.0), mm["st"], seg=16, bv=0.4)
    hid = barrel("hider", e - 30.0, e + 18.0, 10.8, 7.0, (0.0, 0.0), mm["st"], mm["bore"], depth=34.0, seg=24)
    for ang in (0.0, 90.0):
        c = prism("cut_slot", [(e - 8.0, -2.2), (e + 20.0, -2.2), (e + 20.0, 2.2), (e - 8.0, 2.2)], -16.0, 16.0, None, bv=None, part=False)
        c.rotation_euler = (math.radians(ang), 0.0, 0.0)
        cut(hid, c)
    return {"mount": "muzzle", "hides": ["muzzle"], "muzzle_add": 18.0}


def part_m83_akms(spec):
    """Kolba składana AKMS (rozłożona): dwa tłoczone ramiona od zawiasu przy komorze do stopki i stalowa stopka."""
    mm = m83_mats()
    X = 300.0
    for sy in (-1.0, 1.0):
        arm = strip(spline([(X + 4.0, -14.0), (220.0, -30.0), (110.0, -48.0), (34.0, -62.0)], 6), 13.0)
        prism("akms_arm", arm, sy * 9.5, sy * 12.5, mm["small"], bv=0.6, seg=1)
    prism("akms_plate", fillet([(16.0, -22.0, 4.0), (40.0, -30.0, 6.0), (40.0, -98.0, 6.0), (16.0, -104.0, 4.0)]), -12.5, 12.5, mm["small"], bv=1.2, seg=2)
    box("akms_butt", 6.0, 18.0, -104.0, -22.0, 13.0, mm["small"], bv=1.0, seg=1, r=3.0)
    revolve("akms_hinge", [(-14.0, 0.0), (-14.0, 6.0), (14.0, 6.0), (14.0, 0.0)], (X + 2.0, -14.0), mm["small"], axis="Y", seg=16, bv=0.4)
    return {"mount": "frame", "hides": ["stock"]}


def part_p64_supp(spec):
    """Tłumik P-83 na gwintowanej lufie: tuleja gwintu i puszka z kanałem od czoła (oś lufy na z = 101 mm)."""
    blued = M(steel, "p83supp_blued", blue=BLACKOX, r0=0.4)
    bore = M(plain, "p83supp_bore", rgb(0.008, 0.008, 0.008), 0.7, 1.0)
    cyl("thread", 160.0, 176.0, 6.3, (0.0, 101.0), blued, seg=20, bv=0.3)
    barrel("can", 174.0, 300.0, 13.5, 3.2, (0.0, 101.0), blued, bore, depth=20.0, seg=24)
    return {"mount": "muzzle", "hides": [], "muzzle_add": 133.5}


def part_sp12_drum30(spec):
    mm = s12_mats()
    X = 300.0
    box("feed_tower", X + 150.0, X + 228.0, -104.0, -36.0, 14.5, mm["drum"], bv=1.2, seg=2, r=4.0)
    s12_drum(505.0, -198.0, 110.0, 44.0, mm["drum"], mm["small"])
    return {"mount": "frame", "hides": ["mag"]}


def part_sp12_box8(spec):
    """Magazynek pudełkowy na 8 naboi kal. 12 (stal fosforanowana): prosty, lekko pochylony do przodu, stopka i zatrzask."""
    mm = s12_mats()
    X = 300.0
    prism("box_mag", fillet([(X + 152.0, -34.0), (X + 226.0, -34.0), (X + 238.0, -176.0, 6.0), (X + 162.0, -180.0, 6.0)]), -14.0, 14.0, mm["box"], bv=1.4, seg=2)
    prism("box_floor", fillet([(X + 158.0, -176.0, 2.0), (X + 242.0, -172.0, 2.0), (X + 242.0, -186.0, 3.0), (X + 158.0, -190.0, 3.0)]), -15.5, 15.5, mm["small"],
          bv=0.8, seg=1)
    for zz in (-70.0, -110.0, -150.0):
        prism("box_rib", [(X + 156.0, zz - 3.0), (X + 230.0, zz - 3.0), (X + 230.0, zz + 3.0), (X + 156.0, zz + 3.0)], -14.8, -14.0, mm["box"], bv=0.3, seg=1)
    return {"mount": "frame", "hides": ["mag"]}


def part_sp12_ported(spec):
    """Lufa z portami: dławik z rzędem owalnych portów gazowych na górze (zamiast gładkiego dławika)."""
    mm = s12_mats()
    ch = barrel("choke", 910.0, 960.0, 14.6, 9.25, (0.0, 0.0), mm["choke"], mm["bore"], depth=40.0, seg=24)
    for i in range(4):
        x = 918.0 + i * 10.0
        c = prism("cut_port", fillet([(x, -2.8, 1.2), (x + 6.0, -2.8, 1.2), (x + 6.0, 2.8, 1.2), (x, 2.8, 1.2)]), -3.0, 3.0, None, bv=None, part=False)
        c.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        c.location = (0.0, 0.0, 14.0)
        cut(ch, c)
    return {"mount": "muzzle", "hides": ["muzzle"], "muzzle_add": 0.0}


def mat(name):
    """Materiał zbudowany przez broń bazową (część w trybie --part buduje się po niej) — po nazwie; None przy --nobake."""
    return None if NOBAKE else bpy.data.materials.get(name)


def part_s8_tube(spec):
    sg_tube(1070.0, mat("p8_blued"), mat("p8_small"), M(steel, "p8_cap_ext", blue=GREY, grooves=[("z", 2.4, 1069.0, 1091.0, -45.0, -9.0, 0.35, False)]))
    return {"mount": "frame", "hides": ["tube"]}


def part_s8_carrier(spec):
    p8_saddle(6, mat("p8_cuff"), mat("p8_red"), mat("p8_brass"))
    return {"mount": "frame", "hides": ["saddle"]}


def part_lr7_cell(spec):
    lr7_pack(40.0, mat("lr7_pack"), mat("lr7_win"), mat("lr7_warn"), mat("lr7_rubber"))
    return {"mount": "frame", "hides": ["mag"]}


def part_lr7_lens(spec):
    """Soczewka skupiająca: większy obiektyw w dłuższej oprawie z osłoną przeciwsłoneczną."""
    barrel("objective", 846.0, 912.0, 33.0, 28.5, (0.0, 6.0), mat("lr7_small"), mat("lr7_glass"), depth=22.0, seg=24)
    barrel("hood", 908.0, 936.0, 35.0, 31.5, (0.0, 6.0), mat("lr7_small"), mat("lr7_small"), depth=24.0, seg=24)
    return {"mount": "muzzle", "hides": ["muzzle"], "muzzle_add": 36.0}


def part_hkm_tank(spec):
    hkm_tank(750.0, 44.0, mat("hkm_tank"), mat("hkm_small"), mat("hkm_brass"), mat("hkm_dial"), mat("hkm_red"), mat("hkm_hose"))
    return {"mount": "frame", "hides": ["tank"]}


def part_hkm_nozzle(spec):
    hkm_front(1120.0, mat("hkm_steel"), mat("hkm_jacket"), mat("hkm_heat"), mat("hkm_bore"), mat("hkm_small"), mat("hkm_red"), mat("hkm_brass"), mat("hkm_pilot"))
    return {"mount": "frame", "hides": ["front"], "muzzle": Vector((1120.0, 0.0, 0.0))}


def part_g4_loader(spec):
    """Szybkoładowacz WRATH-4: zasobnik na dwa granaty pod lufą przed bębnem, z żółtymi wierzchołkami granatów odłamkowych."""
    olive = mat("wr_tube")
    box("loader", 482.0, 548.0, -62.0, -30.0, 22.0, olive, bv=1.5, r=4.0)
    for sy in (-1.0, 1.0):
        revolve("loader_nose", [(548.0, 0.0), (548.0, 9.5), (556.0, 9.0), (562.0, 5.0), (564.0, 0.0)], (sy * 11.0, -46.0), mat("wr_yellow"), seg=16, bv=0.0)
    box("loader_clip", 486.0, 544.0, -30.0, -26.0, 8.0, mat("wr_small"), bv=0.5, seg=1)
    return {"mount": "frame", "hides": []}


def part_f6_belt(spec):
    fa_drum(70.0, 22.0, mat("fa_drum"), mat("fa_small"))
    return {"mount": "frame", "hides": ["mag"]}


def part_f6_seeker(spec):
    fa_optic(34.0, 19.0, mat("fa_navy"), mat("fa_small"), mat("fa_glass"), mat("fa_rubber"), mat("fa_ir"))
    return {"mount": "frame", "hides": ["optic"]}


def part_w1_cap(spec):
    sp_bank(19.5, -122.0, mat("sp_small"), mat("sp_can"))
    return {"mount": "frame", "hides": ["mag"]}


def part_w1_fast(spec):
    """Szybki kondensator: aluminiowe żeberka chłodzące na każdym uzwojeniu (cewki grzeją się przy szybkim ładowaniu)."""
    alu = M(steel, "sp_fins", blue=((0.05, 0.052, 0.056), (0.085, 0.087, 0.09)), r0=0.45, wear_k=0.5)
    for i in range(8):
        cx = 628.0 + i * 60.0
        for dx in (-9.0, 0.0, 9.0):
            revolve("fin", [(cx + dx - 0.9, 25.5), (cx + dx - 0.9, 32.5), (cx + dx + 0.9, 32.5), (cx + dx + 0.9, 25.5)], (0.0, 0.0), alu, seg=24, bv=0.0)
    return {"mount": "frame", "hides": []}


def part_c6_twin(spec):
    """Drugi harpun w zaczepach na lewym boku belki."""
    inox, small = mat("sn_inox"), mat("sn_small")
    cyl("spare_shaft", 430.0, 990.0, 3.6, (19.5, -14.0), inox, seg=10, bv=0.0)
    revolve("spare_tip", [(986.0, 0.0), (986.0, 5.2), (1000.0, 5.2), (1030.0, 0.6), (1030.0, 0.0)], (19.5, -14.0), inox, seg=8, bv=0.0)
    for cx in (520.0, 820.0):
        box("spare_clip", cx, cx + 14.0, -21.0, -7.0, 2.4, small, bv=0.4, seg=1, y=17.0)
    return {"mount": "frame", "hides": []}


def part_c6_bands(spec):
    """Trzecia para lateksowych cięgien nad harpunem."""
    for sy in (-1.0, 1.0):
        pipe("band3", [(954.0, sy * 14.0, 24.0), (800.0, sy * 14.5, 27.0), (650.0, sy * 11.0, 26.0), (570.0, sy * 6.0, 20.0)], 4.6, mat("sn_latex"))
    return {"mount": "frame", "hides": []}


def part_c6_tether(spec):
    """Grot z hakami: dwa ruchome zadziory (góra i dół) i obejma linki."""
    inox = mat("sn_inox")
    revolve("tip", [(1066.0, 0.0), (1066.0, 5.6), (1080.0, 5.6), (1110.0, 0.6), (1110.0, 0.0)], (0.0, 13.0), inox, seg=8, bv=0.0)
    prism("barb", [(1078.0, 17.5), (1044.0, 31.0), (1039.0, 28.0), (1060.0, 17.5)], -2.2, 2.2, inox, bv=0.4, seg=1)
    prism("barb2", [(1078.0, 8.5), (1044.0, -5.0), (1039.0, -2.0), (1060.0, 8.5)], -2.2, 2.2, inox, bv=0.4, seg=1)
    cyl("line_clamp", 1000.0, 1012.0, 5.5, (0.0, 13.0), mat("sn_brass"), seg=12, bv=0.5)
    return {"mount": "frame", "hides": ["tip"]}


def part_mc_long(spec):
    mc_handle(60.0, mat("mc_wood"), mat("mc_brass"))
    return {"mount": "frame", "hides": ["grip"]}


def part_mc_exec(spec):
    mc_blade(1.25, 2.4, mat("mc_flats"), mat("mc_grind"))
    return {"mount": "frame", "hides": ["blade"]}


def part_kf_heavy(spec):
    kf_head(1.25, mat("kf_head"))
    return {"mount": "frame", "hides": ["head"]}


def part_kf_seismic(spec):
    """Głowa sejsmiczna: z jednej strony szpic, z drugiej płaski obuch z żebrami (szerszy łuk i ogłuszenie, cięższy zamach)."""
    head = mat("kf_head")
    prism("pick", strip(spline([(606.0, 212.0), (652.0, 136.0), (681.0, 62.0), (690.0, 0.0)], 5), lambda t: 9.0 + 34.0 * t ** 0.8), -14.0, 14.0, head, bv=2.5, seg=2)
    prism("sledge", fillet([(652.0, 0.0, 6.0), (728.0, 0.0, 6.0), (734.0, -96.0, 4.0), (646.0, -96.0, 4.0)]), -24.0, 24.0, head, bv=2.5, seg=2)
    for zz in (-30.0, -54.0, -78.0):
        box("sledge_rib", 644.0, 736.0, zz - 3.0, zz + 3.0, 26.0, head, bv=0.8, seg=1)
    box("eye", 654.0, 724.0, -32.0, 32.0, 22.0, head, bv=1.5, r=6.0)
    return {"mount": "frame", "hides": ["head"]}


PART_BUILDERS = {
    "m83_rpk40": part_m83_rpk40, "m83_drum75": part_m83_drum75, "m83_rpkbar": part_m83_rpkbar, "m83_short": part_m83_short,
    "m83_pbs1": part_m83_pbs1, "m83_hider": part_m83_hider, "m83_akms": part_m83_akms,
    "p64_supp": part_p64_supp,
    "sp12_drum30": part_sp12_drum30, "sp12_box8": part_sp12_box8, "sp12_ported": part_sp12_ported,
    "s8_tube": part_s8_tube, "s8_carrier": part_s8_carrier, "lr7_cell": part_lr7_cell, "lr7_lens": part_lr7_lens,
    "hkm_tank": part_hkm_tank, "hkm_nozzle": part_hkm_nozzle, "g4_loader": part_g4_loader, "f6_belt": part_f6_belt, "f6_seeker": part_f6_seeker,
    "w1_cap": part_w1_cap, "w1_fast": part_w1_fast, "c6_twin": part_c6_twin, "c6_bands": part_c6_bands, "c6_tether": part_c6_tether,
    "mc_long": part_mc_long, "mc_exec": part_mc_exec, "kf_heavy": part_kf_heavy, "kf_seismic": part_kf_seismic,
}


def merge_parts(name=None):
    """Stosuje modyfikatory, trianguluje (z zachowaniem normalnych) i łączy części w jeden obiekt. Ściany niosą atrybut „comp” (indeks w COMP_NAMES)."""
    for ob in OBJS:
        tri = ob.modifiers.new("tri", "TRIANGULATE")
        tri.keep_custom_normals = True
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    done = []
    for ob in OBJS:
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o2 = bpy.data.objects.new(ob.name, me)
        bpy.context.scene.collection.objects.link(o2)
        at = me.attributes.new("comp", "INT", "FACE")
        at.data.foreach_set("value", [COMP_NAMES.index(ob.get("comp", "body"))] * len(me.polygons))
        done.append(o2)
    for ob in OBJS + CUTTERS:
        bpy.data.objects.remove(ob, do_unlink=True)
    for o in done:
        o.select_set(True)
    bpy.context.view_layer.objects.active = done[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name or ("gun_" + KEY)
    return ob


def split_comps(ob):
    """Po wypieku: ściany każdego podzespołu (poza „body”) do osobnego obiektu `<nazwa>__<podzespół>` — ten sam materiał i UV, osobny węzeł GLB."""
    if ob.data.attributes.get("comp") is None:
        return
    for idx, cname in enumerate(COMP_NAMES):
        vals = [0] * len(ob.data.polygons)
        ob.data.attributes["comp"].data.foreach_get("value", vals)
        if idx == 0 or idx not in vals:
            continue
        for o in bpy.context.scene.objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        at = ob.data.attributes.get("comp")
        at.data.foreach_get("value", vals)
        for p in ob.data.polygons:
            p.select = vals[p.index] == idx
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        for o in bpy.context.selected_objects:
            if o != ob:
                o.name = o.data.name = ob.name + "__" + cname
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.data.attributes.get("comp") is not None:
            o.data.attributes.remove(o.data.attributes["comp"])


def drop_markers(ob):
    """Usuwa siatki-znaczniki napisów (materiały „marker…") — potrzebne były tylko promieniom AO przy wypieku."""
    idx = [i for i, m in enumerate(ob.data.materials) if m is not None and m.name.startswith("marker")]
    if not idx:
        return
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in ob.data.polygons:
        p.select = p.material_index in idx
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")


def unwrap(ob):
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def cycles_setup():
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
    except TypeError:
        bpy.ops.preferences.addon_enable(module="cycles")
        sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.device = "CPU"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            prefs.compute_device_type = kind
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == kind]
            if devs:
                for d in prefs.devices:
                    d.use = d.type == kind
                sc.cycles.device = "GPU"
                break
    except Exception as e:                                       # brak GPU / sterownika — zostaje CPU
        print("GPU niedostępne:", e)
    print("CYCLES", sc.cycles.device, "próbek", SAMPLES)


def bake(ob):
    """Wypieka kolor, ORM (okluzja, chropowatość, metaliczność) i normalne w przestrzeni stycznej do trzech obrazów TEX×TEX."""
    cycles_setup()
    imgs = {}
    passes = [("color", "sRGB"), ("orm", "Non-Color"), ("normal", "Non-Color")] + ([("emit", "sRGB")] if GLOW else [])
    for which, cs in passes:
        img = bpy.data.images.new({"color": "BaseColor", "orm": "ORM", "normal": "Normal", "emit": "Emissive"}[which], TEX, TEX, alpha=False)
        img.colorspace_settings.name = cs
        imgs[which] = img
        for d in MATS.values():
            nt = d["mat"].node_tree
            for l in list(nt.links):
                if l.to_node in (d["emi"], d["out"]):
                    nt.links.remove(l)
            if which == "normal":
                nt.links.new(d["bsdf"].outputs[0], d["out"].inputs["Surface"])
            else:
                nt.links.new(d[which], d["emi"].inputs["Color"])
                nt.links.new(d["emi"].outputs[0], d["out"].inputs["Surface"])
            d["tex"].image = img
            for n in nt.nodes:
                n.select = False
            d["tex"].select = True
            nt.nodes.active = d["tex"]
        if which == "normal":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=8, use_clear=True)
        else:
            bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
        img.pack()
        print("BAKE", which)
    return imgs


def export_material(ob, imgs):
    """Jeden materiał z wypieczonymi teksturami w układzie, który eksporter glTF zapisuje jako kolor + ORM + normalne."""
    m = bpy.data.materials.new(ob.name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    if imgs:
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = imgs["color"]
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
        to = nt.nodes.new("ShaderNodeTexImage")
        to.image = imgs["orm"]
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(to.outputs["Color"], sep.inputs[0])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        gn = nt.nodes.new("ShaderNodeGroup")
        gn.node_tree = grp
        nt.links.new(sep.outputs[0], gn.inputs[0])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = imgs["normal"]
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
        if "emit" in imgs:
            te = nt.nodes.new("ShaderNodeTexImage")
            te.image = imgs["emit"]
            nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.0
    else:
        bsdf.inputs["Base Color"].default_value = rgb(0.35, 0.35, 0.36)
        bsdf.inputs["Roughness"].default_value = 0.5
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.material_index = 0


def main_part():
    """Część broni (PART_BUILDERS): skala i początek układu z broni bazowej, potem tylko bryły części — wypiek, eksport, .json z mocowaniem."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = BUILDERS[KEY]()
    base = merge_parts()
    xs = [v.co.x for v in base.data.vertices]
    sc = (LENGTH or spec["length"]) / (max(xs) - min(xs))
    bpy.data.objects.remove(base, do_unlink=True)
    OBJS.clear()
    CUTTERS.clear()
    del COMP_NAMES[1:]
    ps = PART_BUILDERS[PART](spec)
    ob = merge_parts("gunpart_" + PART)
    imgs = None
    if not NOBAKE:
        unwrap(ob)
        imgs = bake(ob)
        drop_markers(ob)
    print("TRIS", len(ob.data.polygons))
    export_material(ob, imgs)
    origin = spec["rear"] if ps["mount"] == "frame" else spec["muzzle"]
    ob.data.transform(Matrix.Translation(-origin))
    ob.data.transform(Matrix.Scale(sc, 4))
    ob.data.update()
    if not JSON_ONLY:
        bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=95, export_animations=False)
    info = {"weapon": KEY, "mount": ps["mount"], "hides": ps.get("hides", []), "muzzle_add": round(ps.get("muzzle_add", 0.0) * sc, 4)}
    if ps.get("muzzle") is not None:
        info["muzzle"] = [round(c, 4) for c in (ps["muzzle"] - spec["rear"]) * sc]
    with open(DST.rsplit(".", 1)[0] + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print("OK", DST, info)


def main():
    if PART:
        main_part()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = BUILDERS[KEY]()
    rear, muzzle, length = spec["rear"], spec["muzzle"], LENGTH or spec["length"]
    ob = merge_parts()
    imgs = None
    if not NOBAKE and not JSON_ONLY:
        unwrap(ob)
        imgs = bake(ob)
        drop_markers(ob)
    print("TRIS", len(ob.data.polygons))
    export_material(ob, imgs)
    xs = [v.co.x for v in ob.data.vertices]
    sc = length / (max(xs) - min(xs))
    ob.data.transform(Matrix.Translation(-rear))
    ob.data.transform(Matrix.Scale(sc, 4))
    ob.data.update()
    split_comps(ob)
    if not JSON_ONLY:
        bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=95, export_animations=False)
    rel = lambda v: [round(c, 4) for c in (v - rear) * sc]
    info = {"hands": spec["hands"], "length": length, "rear": [0.0, 0.0, 0.0], "fore": rel(spec["fore"]) if spec["fore"] is not None else [0.0, 0.0, 0.0],
            "muzzle": rel(muzzle)}
    for k in ("grip", "hold"):
        if spec.get(k) is not None:
            info[k] = rel(spec[k])
    if spec.get("hold_v"):
        info["hold_v"] = True
    with open(DST.rsplit(".", 1)[0] + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print("OK", DST, info)


main()
