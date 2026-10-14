"""Kurtka polowa M65 szyta symulacją tkaniny na ciele MPFB — `art_src/clothes/<strój>_m65.glb` (próba, CHARACTER_PLAN.md).

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2, jak `char_mpfb.py`):
    blender -b -P prototype/tools/cloth_jacket.py -- male_scav [--stage=shell|sim|all] [--shot=PLIK.png]

Co robi, zamiast gotowej kurtki z paczki MakeHuman:
1. Składa ciało z tabeli OUTFITS w `char_mpfb.py` (ten sam fenotyp, A-poza MPFB, przód −Y, góra +Z, przed skalowaniem do wzrostu).
2. Bryła kurtki: ciało poszerzone o luz (rękawy szerzej) + wypukła powłoka tułowia w plastrach — tkanina mostkuje wklęsłości
   (talia, rowek kręgosłupa) jak prawdziwy wykrój; połączone przez remesh wokselowy, przycięte na dekolt, dół i mankiety.
3. Symulacja tkaniny (grawitacja, kolizja z ciałem, ściągacz w pasie i przy mankietach) układa fałdy.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
_argv = sys.argv
sys.argv = [_argv[0], "--"]          # char_mpfb przy imporcie nic nie buduje (brak nazw strojów w argumentach)
import char_mpfb as C  # noqa: E402
sys.argv = _argv
from bl_ext.user_default.mpfb.services import HumanService  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


WORK = arg("work", os.path.join(REPO, "build", "cloth"))
OUT = os.path.join(REPO, "art_src", "clothes")
STAGE = arg("stage", "all")
VOXEL = float(arg("voxel", "0.011"))        # gęstość siatki symulacji (m)

TORSO = {"Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder"}
ARMS = {"LeftArm", "LeftForeArm", "RightArm", "RightForeArm"}
HANDS = {"LeftHand", "RightHand"}


def P(o, n):
    return o.matrix_world @ o.pose.bones["mixamorig:" + n].head


def make_body(spec):
    """Ciało MPFB bez ubrań: klucze kształtu zapieczone, bryły pomocnicze usunięte; zwraca (rig, ciało, dominująca kość wierzchołka)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    ph = info["phenotype"]
    ph.update(spec["phenotype"])
    ph["gender"] = 1.0 if spec["sex"] == "male" else 0.0
    ph["race"] = dict(spec["race"])
    info["rig"] = "mixamo"
    info["clothes"] = []
    info["skin_mhmat"] = "%s/%s.mhmat" % (spec["skin"], spec["skin"])
    info["skin_material_type"] = "MAKESKIN"
    info["alternative_materials"] = {}
    st = HumanService.get_default_deserialization_settings()
    st["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, st)
    rig = body.parent
    C._only(body)
    if body.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    body.modifiers.remove(next(m for m in body.modifiers if m.type == "ARMATURE"))
    for m in [m for m in body.modifiers if m.type == "MASK"]:
        bpy.ops.object.modifier_apply(modifier=m.name)
    names = {g.index: g.name.replace("mixamorig:", "") for g in body.vertex_groups if g.name.startswith("mixamorig:")}
    dom = []
    for v in body.data.vertices:
        best = max(((g.weight, names[g.group]) for g in v.groups if g.group in names), default=(0, ""))
        dom.append(best[1])
    bpy.context.view_layer.update()
    return rig, body, dom


def _hull(pts):
    """Otoczka wypukła punktów 2D (łańcuch monotoniczny), przeciwnie do wskazówek zegara."""
    pts = sorted(set(map(tuple, pts)))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def _ray_hull(hull, c, ang):
    """Odległość od środka `c` do otoczki wzdłuż kierunku `ang`."""
    d = np.array([math.cos(ang), math.sin(ang)])
    best = 0.0
    n = len(hull)
    for i in range(n):
        a = np.array(hull[i]) - c
        b = np.array(hull[(i + 1) % n]) - c
        e = b - a
        den = d[0] * (-e[1]) - d[1] * (-e[0])
        if abs(den) < 1e-12:
            continue
        t = (a[0] * (-e[1]) - a[1] * (-e[0])) / den
        s = (d[0] * a[1] - d[1] * a[0]) / den
        if t > 0 and -1e-6 <= s <= 1 + 1e-6:
            best = max(best, t)
    return best


def make_shell(rig, body, dom, look):
    """Bryła kurtki: ciało poszerzone o luz + wypukła powłoka tułowia, remesh wokselowy, przycięcie (dekolt, dół, mankiety)."""
    co = np.array([tuple(v.co) for v in body.data.vertices])
    nr = np.array([tuple(v.normal) for v in body.data.vertices])
    dom = np.array(dom)
    hem_z = look["hem_z"]
    # luz: rękawy szersze przy ramieniu, węższe przy nadgarstku; tułów dostaje luz z powłoki wypukłej
    disp = np.full(len(co), look["ease_body"])
    for side in ("Left", "Right"):
        a, w = np.array(P(rig, side + "Arm")), np.array(P(rig, side + "Hand"))
        ax = w - a
        t = np.clip(((co - a) @ ax) / (ax @ ax), 0, 1)
        arm = np.isin(dom, [side + "Arm", side + "ForeArm", side + "Shoulder"])
        disp = np.where(arm, look["ease_sleeve"][0] * (1 - t) + look["ease_sleeve"][1] * t, disp)
    fat = co + nr * disp[:, None]

    # powłoka tułowia w plastrach: otoczka wypukła punktów tułowia (bez ramion), luz na zewnątrz, wygładzona w pionie
    hand = np.char.find(dom.astype(str), "Hand") >= 0              # dłonie i palce
    torso = ~np.isin(dom, list(ARMS)) & ~hand & (co[:, 2] > hem_z - 0.06)
    z_top = look["loft_top"]
    zs = np.linspace(hem_z - 0.05, z_top, 36)
    na = 72
    angs = np.linspace(0, 2 * math.pi, na, endpoint=False)
    rings, cents = [], []
    for z in zs:
        sl = co[torso & (np.abs(co[:, 2] - z) < 0.02)][:, :2]
        c = sl.mean(0)
        h = _hull(np.round(sl, 5))
        rings.append([_ray_hull(h, c, a) for a in angs])
        cents.append(c)
    rings = np.array(rings)
    cents = np.array(cents)
    k = np.array([1, 2, 3, 2, 1], float)
    k /= k.sum()
    pad = np.pad(rings, ((2, 2), (0, 0)), mode="edge")
    rings = sum(k[i] * pad[i:i + len(zs)] for i in range(5))
    cpad = np.pad(cents, ((2, 2), (0, 0)), mode="edge")
    cents = sum(k[i] * cpad[i:i + len(zs)] for i in range(5))
    ease = np.interp(zs, [hem_z, look["waist_z"], z_top], look["ease_torso"])
    verts, faces = [], []
    for i, z in enumerate(zs):
        for j, a in enumerate(angs):
            r = rings[i, j] + ease[i]
            verts.append((cents[i, 0] + r * math.cos(a), cents[i, 1] + r * math.sin(a), z))
    for i in range(len(zs) - 1):
        for j in range(na):
            faces.append((i * na + j, i * na + (j + 1) % na, (i + 1) * na + (j + 1) % na, (i + 1) * na + j))
    b0 = len(verts)
    verts.append((cents[0, 0], cents[0, 1], zs[0]))
    t0 = len(verts)
    verts.append((cents[-1, 0], cents[-1, 1], zs[-1]))
    top = (len(zs) - 1) * na
    for j in range(na):
        faces.append((b0, (j + 1) % na, j))
        faces.append((t0, top + j, top + (j + 1) % na))
    # jedna siatka: poszerzone ciało + powłoka, remesh wokselowy łączy je w szczelną bryłę
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v, p in zip(bm.verts, fat):
        v.co = Vector(p)
    off = len(bm.verts)
    for p in verts:
        bm.verts.new(p)
    bm.verts.ensure_lookup_table()
    for f in faces:
        bm.faces.new([bm.verts[off + i] for i in f])
    me = bpy.data.meshes.new("jacket")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("jacket", me)
    bpy.context.scene.collection.objects.link(ob)
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = VOXEL
    rm.adaptivity = 0.0
    C._only(ob)
    bpy.ops.object.modifier_apply(modifier=rm.name)

    # przycięcie: dół, dekolt (z przodu niżej), mankiety kawałek za nadgarstkiem (przykrywają dłoń, potem ściągacz)
    neck = np.array(P(rig, "Neck"))
    head = np.array(P(rig, "Head"))
    wr = {s: (np.array(P(rig, s + "Hand")), np.array(P(rig, s + "Hand")) - np.array(P(rig, s + "ForeArm"))) for s in ("Left", "Right")}
    bm = bmesh.new()
    bm.from_mesh(me)
    kill = []
    for v in bm.verts:
        p = np.array(v.co)
        if p[2] < hem_z or p[2] > head[2]:
            kill.append(v)
            continue
        dxy = math.hypot(p[0] - neck[0], p[1] - neck[1])
        front = np.clip((neck[1] - p[1]) / 0.08, 0, 1)
        if dxy < look["neck_r"] and p[2] > neck[2] + look["neck_dz"] - look["neck_drop"] * front:
            kill.append(v)
            continue
        for s, (w, d) in wr.items():
            u = d / np.linalg.norm(d)
            if (p - w) @ u > look["cuff_over"]:
                kill.append(v)
                break
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    # tylko największy spójny kawałek
    seen, parts = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        stack, part = [v], []
        seen.add(v)
        while stack:
            x = stack.pop()
            part.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        parts.append(part)
    parts.sort(key=len)
    bmesh.ops.delete(bm, geom=[v for p in parts[:-1] for v in p], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    print("SHELL verts", len(me.vertices), "faces", len(me.polygons), "pieces dropped", len(parts) - 1)
    return ob


def _group(ob, name, weights):
    g = ob.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        if w > 0:
            g.add([i], float(w), "REPLACE")
    return g


def _rims(ob, rig):
    """Brzegi kurtki jako uporządkowane pętle wierzchołków: neck, cuff_L, cuff_R (najbliższe szyi / dłoni), hem (reszta)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    adj = {}
    for e in bm.edges:
        if e.is_boundary:
            i, j = e.verts[0].index, e.verts[1].index
            adj.setdefault(i, []).append(j)
            adj.setdefault(j, []).append(i)
    bm.free()
    loops, seen = [], set()
    for st in adj:
        if st in seen:
            continue
        lp, prev, cur = [st], None, st
        seen.add(st)
        while True:
            nxt = [n for n in adj[cur] if n != prev and n not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            lp.append(cur)
        loops.append(lp)
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    loops = sorted(loops, key=len, reverse=True)[:4]
    out = {}
    for key, bone in (("neck", "Neck"), ("cuff_L", "LeftHand"), ("cuff_R", "RightHand")):
        tgt = np.array(P(rig, bone))
        lp = min(loops, key=lambda lp: np.linalg.norm(co[lp].mean(0) - tgt))
        out[key] = lp
        loops.remove(lp)
    out["hem"] = loops[0]
    return out


def _dist_to_rim(ob, co, key, rig):
    rim = co[_rims(ob, rig)[key]]
    return np.array([np.min(np.linalg.norm(rim - p, axis=1)) for p in co])


def simulate(rig, body, ob, look):
    """Symulacja tkaniny: grawitacja i kolizja z ciałem; ściągacz w pasie i przy mankietach (skurcz pasa wierzchołków)."""
    C._only(ob)
    sm = ob.modifiers.new("smooth", "SMOOTH")         # schodki wokseli
    sm.factor = 0.6
    sm.iterations = 6
    bpy.ops.object.modifier_apply(modifier=sm.name)
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    waist = np.clip(1 - np.abs(co[:, 2] - look["waist_z"]) / look["waist_band"], 0, 1)
    cuff = np.zeros(len(co))
    for s in ("Left", "Right"):
        w = np.array(P(rig, s + "Hand"))
        u = w - np.array(P(rig, s + "ForeArm"))
        u /= np.linalg.norm(u)
        d = (co - w) @ u
        cuff = np.maximum(cuff, np.clip(1 - (look["cuff_over"] - d) / look["cuff_band"], 0, 1))
    _group(ob, "pin", (_dist_to_rim(ob, co, "neck", rig) < 0.012).astype(float))
    _group(ob, "shrink", np.maximum(waist * look["waist_shrink"], cuff * look["cuff_shrink"]) / max(look["waist_shrink"], look["cuff_shrink"]))
    col = body.modifiers.new("collision", "COLLISION")
    body.collision.thickness_outer = 0.005
    body.collision.cloth_friction = 8.0
    cl = ob.modifiers.new("cloth", "CLOTH")
    st = cl.settings
    st.quality = 8
    st.mass = 0.35
    st.tension_stiffness = st.compression_stiffness = 150.0     # płótno bawełniane prawie się nie rozciąga
    st.shear_stiffness = 60.0
    st.bending_stiffness = 8.0
    st.vertex_group_mass = "pin"                              # dekolt trzyma kołnierz
    st.air_damping = 2.0
    st.shrink_min = 0.0                               # waga 0: bez skurczu, waga 1: shrink_max
    st.shrink_max = max(look["waist_shrink"], look["cuff_shrink"])
    st.vertex_group_shrink = "shrink"
    cs = cl.collision_settings
    cs.collision_quality = 4
    cs.distance_min = 0.004
    cs.use_self_collision = False
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, look["frames"]
    cl.point_cache.frame_start, cl.point_cache.frame_end = 1, look["frames"]
    for f in range(1, look["frames"] + 1):
        sc.frame_set(f)
        if f % 10 == 0:
            print("SIM frame", f)
    bpy.ops.object.modifier_apply(modifier=cl.name)
    body.modifiers.remove(col)
    ob.data.shade_smooth()
    print("SIM done")


def fit_look(rig, body, look):
    """Wymiary kroju względem ciała: dół względem krocza, ściągacz na wysokości kości Spine, powłoka do stawu barkowego."""
    co = np.array([tuple(v.co) for v in body.data.vertices])
    crotch = co[(np.abs(co[:, 0]) < 0.01) & (co[:, 2] > 0.3 * co[:, 2].max())][:, 2].min()
    out = dict(look)
    out["crotch_z"] = crotch
    out["hem_z"] = crotch + look["hem_dz"]
    out["waist_z"] = P(rig, "Spine").z + look["waist_dz"]
    out["loft_top"] = P(rig, "LeftArm").z + look["loft_dz"]
    print("FIT crotch %.3f hem %.3f waist %.3f loft %.3f" % (crotch, out["hem_z"], out["waist_z"], out["loft_top"]))
    return out


# kurtka M65: dół tuż pod kroczem (zakrywa siedzenie), ściągacz w talii, stójka, cztery kieszenie z patkami, pagony
M65 = {
    "hem_dz": -0.025, "waist_dz": 0.0, "loft_dz": 0.035,
    "ease_body": 0.012, "ease_sleeve": (0.026, 0.019), "ease_torso": (0.032, 0.026, 0.014),
    "waist_band": 0.018, "waist_shrink": 0.05, "cuff_band": 0.035, "cuff_shrink": 0.30, "frames": 60,
    "neck_r": 0.085, "neck_dz": -0.005, "neck_drop": 0.035, "cuff_over": 0.03,
    "collar_h": 0.065, "hem_band": 0.03, "cuff_h": 0.045, "collar_flare": 0.008, "collar_thick": 0.004,
    "chest_dz": 0.025, "chest_pocket": (0.115, 0.13, 0.16), "hip_dz": 0.13, "hip_pocket": (0.098, 0.125, 0.19),
    "epaulet": (0.12, 0.05), "placket_x": 0.012, "placket_w": 0.036,
    "camo": "woodland", "camo_blotch": 0.07, "camo_seed": 3, "low_tris": 5000,
}


# ------------------------------------------------------------------------------------------------ detale

def _new_obj(name, verts, faces, mat_index=0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    for p in me.polygons:
        p.material_index = mat_index
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _solidify(ob, thick, offset=1.0):
    C._only(ob)
    m = ob.modifiers.new("sol", "SOLIDIFY")
    m.thickness = thick
    m.offset = offset
    m.use_even_offset = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    ob.data.shade_smooth()
    return ob


def _patch(bvh, name, centre, u, v, size, axis, lift, thick, res=(10, 10), point=0.0):
    """Łata przylegająca do kurtki: siatka w płaszczyźnie (u, v) wokół `centre`, rzutowana wzdłuż `axis` na powierzchnię i odsunięta
    o `lift` wzdłuż normalnej, potem pogrubiona o `thick`. `point`: dolna krawędź w lekki szpic (patka kieszeni)."""
    u, v, axis = Vector(u).normalized(), Vector(v).normalized(), Vector(axis).normalized()
    nx, ny = res
    verts, ok = [], True
    for j in range(ny + 1):
        for i in range(nx + 1):
            a, b = i / nx - 0.5, j / ny - 0.5
            if j == 0 and point:
                b -= point * (1 - 2 * abs(a)) / size[1]
            p = Vector(centre) + u * (a * size[0]) + v * (b * size[1])
            hit, nrm, _, _ = bvh.ray_cast(p - axis * 0.4, axis, 4.0)
            if hit is None:                                # poza kurtką: najbliższy punkt powierzchni
                ok = False
                hit, nrm, _, _ = bvh.find_nearest(p)
            if nrm.dot(axis) > 0:
                nrm = -nrm
            verts.append(hit + nrm * lift)
    faces = [(j * (nx + 1) + i, j * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i)
             for j in range(ny) for i in range(nx)]
    if not ok:
        print("PATCH miss", name)
    ob = _new_obj(name, verts, faces)
    if ob.data.polygons[0].normal.dot(axis) > 0:          # normalne na zewnątrz (od ciała)
        ob.data.flip_normals()
    return _solidify(ob, thick, 1.0)


def _snap(bvh, name, at, axis, r=0.008, h=0.004, lift=0.0):
    """Napa / guzik: niski walec na powierzchni."""
    axis = Vector(axis).normalized()
    hit, nrm, _, _ = bvh.ray_cast(Vector(at) - axis * 0.4, axis, 4.0)
    if hit is None:
        return None
    if nrm.dot(axis) > 0:
        nrm = -nrm
    t = nrm.orthogonal().normalized()
    b = nrm.cross(t)
    seg = 12
    verts = []
    for k in (0, 1):
        for i in range(seg):
            a = 2 * math.pi * i / seg
            verts.append(hit + nrm * (lift + h * k) + (t * math.cos(a) + b * math.sin(a)) * r * (1 - 0.25 * k))
    faces = [(i, (i + 1) % seg, seg + (i + 1) % seg, seg + i) for i in range(seg)] + [tuple(range(seg, 2 * seg))]
    return _new_obj(name, verts, faces)


def smooth_rims(ob, rig, iters=12):
    """Brzegi po cięciu wokselami są poszarpane: wygładzenie wzdłuż każdej pętli brzegu (jak obrzucona krawędź), sąsiedzi idą za nią."""
    me = ob.data
    co = np.array([tuple(v.co) for v in me.vertices])
    for key, lp in _rims(ob, rig).items():
        lp = np.array(lp)
        orig = co[lp].copy()
        for _ in range(iters):
            q = co[lp]
            co[lp] = 0.5 * q + 0.25 * (np.roll(q, 1, 0) + np.roll(q, -1, 0))
        if key == "hem":                           # dół równo: wysokość wygładzona mocniej
            z = co[lp, 2]
            for _ in range(40):
                z = 0.5 * z + 0.25 * (np.roll(z, 1) + np.roll(z, -1))
            co[lp, 2] = z
        delta = co[lp] - orig
        # pierwszy pierścień sąsiadów dostaje połowę przesunięcia (bez schodka przy brzegu)
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        for i, d in zip(lp, delta):
            for e in bm.verts[int(i)].link_edges:
                j = e.other_vert(bm.verts[int(i)]).index
                if j not in set(lp.tolist()):
                    co[j] += 0.5 * d
        bm.free()
    for v, c in zip(me.vertices, co):
        v.co = Vector(c)


def make_band(ob, rig, key, height, out, thick, name):
    """Podwinięcie / mankiet: pas tkaniny wzdłuż brzegu (od brzegu w górę rękawa / kurtki po powierzchni), lekko odsunięty, pogrubiony."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    nr = np.array([tuple(v.normal) for v in ob.data.vertices])
    lp = _rims(ob, rig)[key]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    rim = set(lp)
    inward = []
    for i in lp:                                   # kierunek od brzegu w głąb tkaniny: średnia do sąsiadów spoza brzegu
        v = bm.verts[i]
        ns = [e.other_vert(v).co for e in v.link_edges if e.other_vert(v).index not in rim]
        d = (sum(ns, Vector()) / len(ns) - v.co) if ns else Vector((0, 0, 1))
        inward.append(np.array(d.normalized()))
    bm.free()
    inward = np.array(inward)
    for _ in range(6):
        inward = 0.5 * inward + 0.25 * (np.roll(inward, 1, 0) + np.roll(inward, -1, 0))
    inward /= np.linalg.norm(inward, axis=1)[:, None]
    rows = 3
    verts = []
    for k in range(rows + 1):
        t = k / rows
        for j, i in enumerate(lp):
            verts.append(co[i] - inward[j] * 0.002 + inward[j] * height * t + nr[i] * out)
    n = len(lp)
    faces = [(k * n + j, k * n + (j + 1) % n, (k + 1) * n + (j + 1) % n, (k + 1) * n + j) for k in range(rows) for j in range(n)]
    band = _new_obj(name, verts, faces)
    p0 = band.data.polygons[0]
    if p0.normal.dot(Vector(nr[lp[0]])) < 0:
        band.data.flip_normals()
    return _solidify(band, thick, 1.0)


def make_collar(ob, rig, look):
    """Stójka: pas tkaniny z krawędzi dekoltu w górę (lekko na zewnątrz), pogrubiony."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    lp = _rims(ob, rig)["neck"]
    neck = np.array(P(rig, "Neck"))
    rows = 4
    verts = []
    for k in range(rows + 1):
        t = k / rows
        for i in lp:
            p = co[i]
            out = np.array([p[0] - neck[0], p[1] - neck[1], 0.0])
            out /= np.linalg.norm(out) + 1e-9
            verts.append(p + np.array([0, 0, look["collar_h"] * t]) + out * (look["collar_flare"] * t - 0.002))
    n = len(lp)
    faces = [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for k in range(rows) for i in range(n)]
    col = _new_obj("collar", verts, faces)
    col.data.materials.append(_mat("collar_tmp", (0.3, 0.3, 0.2)))     # osobny materiał: po złączeniu stójka ma indeks 1 (rozkrój)
    p0 = col.data.polygons[0]
    if p0.normal.dot(Vector((p0.center.x - neck[0], p0.center.y - neck[1], 0))) < 0:   # normalne na zewnątrz od szyi
        col.data.flip_normals()
    return _solidify(col, look["collar_thick"], 1.0)


def make_details(rig, ob, look):
    """Detale M65 do wypieku (kieszenie z patkami, listwa zapięcia z napami, pagony, patki mankietów); zwraca listę obiektów."""
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    fwd = (0, 1, 0)                               # rzut z przodu (przód ciała to −Y)
    X, Z = (1, 0, 0), (0, 0, 1)
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    neck_front = co[_rims(ob, rig)["neck"]][:, 2].min()
    hem = look["hem_z"]
    det = []
    chest_z = P(rig, "Spine2").z + look["chest_dz"]
    hip_z = hem + look["hip_dz"]
    for sx in (-1, 1):
        cx, cw, chh = look["chest_pocket"]
        det.append(_patch(bvh, "pocket_c%d" % sx, (sx * cx, -0.5, chest_z), X, Z, (cw, chh), fwd, 0.002, 0.003))
        det.append(_patch(bvh, "flap_c%d" % sx, (sx * cx, -0.5, chest_z + chh / 2 - 0.022), X, Z, (cw + 0.012, 0.062), fwd, 0.006, 0.003,
                          point=0.008))
        det.append(_snap(bvh, "snap_c%d" % sx, (sx * cx, -0.5, chest_z + chh / 2 - 0.045), fwd, lift=0.008))
        hx, hw, hh = look["hip_pocket"]
        det.append(_patch(bvh, "pocket_h%d" % sx, (sx * hx, -0.5, hip_z), X, Z, (hw, hh), fwd, 0.003, 0.004))
        det.append(_patch(bvh, "flap_h%d" % sx, (sx * hx, -0.5, hip_z + hh / 2 - 0.026), X, Z, (hw + 0.012, 0.072), fwd, 0.008, 0.003,
                          point=0.010))
        det.append(_snap(bvh, "snap_h%d" % sx, (sx * hx, -0.5, hip_z + hh / 2 - 0.054), fwd, lift=0.010))
        # pagon: od podstawy szyi do stawu barkowego, rzut z góry
        side = "Left" if sx > 0 else "Right"
        a, n = P(rig, side + "Arm"), P(rig, "Neck")
        x0, x1 = n.x + sx * (look["neck_r"] + 0.012), a.x + sx * 0.012          # od szwu stójki do stawu barkowego
        det.append(_patch(bvh, "epaulet%d" % sx, ((x0 + x1) / 2, a.y, 2.5), (1, 0, 0), (0, 1, 0), (abs(x1 - x0), look["epaulet"][1]),
                          (0, 0, -1), 0.003, 0.003, res=(10, 3)))
        det.append(_snap(bvh, "snap_e%d" % sx, (x0 + sx * 0.02, a.y, 2.5), (0, 0, -1), r=0.007, lift=0.006))
        # patka mankietu (rzep): na wierzchu przedramienia przy dłoni
        w, fa = P(rig, side + "Hand"), P(rig, side + "ForeArm")
        d = (w - fa).normalized()
        up = (Vector(Z) - d * d.z).normalized()
        det.append(_patch(bvh, "cufftab%d" % sx, w - d * 0.05 + up * 0.3, up.cross(d), d, (0.03, 0.07), -up, 0.004, 0.003, res=(4, 6)))
    # listwa zapięcia (kryje zamek) z napami, od dołu do dekoltu
    top = neck_front - 0.004
    det.append(_patch(bvh, "placket", (look["placket_x"], -0.5, (hem + top) / 2), X, Z, (look["placket_w"], top - hem), fwd, 0.004, 0.003,
                      res=(4, 40)))
    for k in range(5):
        z = hem + 0.06 + (top - hem - 0.10) * k / 4
        det.append(_snap(bvh, "snap_p%d" % k, (look["placket_x"], -0.5, z), fwd, lift=0.007))
    det = [d for d in det if d is not None]
    for d in det:
        d.data.shade_smooth()
    print("DETAILS", len(det))
    return det


# ------------------------------------------------------------------------------------------------ rozkrój i mapy

def _labels(ob, body, dom):
    """Element wykroju dla każdej ściany: rękaw L/P (najbliższy punkt ciała należy do kości ramienia — wagi MPFB wyznaczają naturalną
    linię wszycia rękawa), przód L/P, tył, stójka (materiał 1). Granice wygładzone głosowaniem sąsiadów, żeby szwy szły gładko."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(body.data.vertices))
    for v in body.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    lab = []
    for p in ob.data.polygons:
        c = p.center
        if p.material_index == 1:
            lab.append("collar")
            continue
        bone = dom[kd.find(c)[1]]
        if bone.startswith("Left") and bone != "LeftShoulder" and "UpLeg" not in bone:
            lab.append("sleeve_Left")
        elif bone.startswith("Right") and bone != "RightShoulder" and "UpLeg" not in bone:
            lab.append("sleeve_Right")
        else:
            lab.append(("front_L" if c.x > 0 else "front_R") if c.y < -0.01 else "back")
    # głosowanie: ściana przyjmuje element większości sąsiadów (przez krawędzie)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    nb = [[g.index for e in f.edges for g in e.link_faces if g.index != f.index] for f in bm.faces]
    bm.free()
    for _ in range(4):
        new = list(lab)
        for i, ns in enumerate(nb):
            if lab[i] == "collar" or not ns:
                continue
            cnt = {}
            for j in ns:
                cnt[lab[j]] = cnt.get(lab[j], 0) + 1
            best = max(cnt, key=cnt.get)
            if cnt[best] > len(ns) / 2:
                new[i] = best
        lab = new
    return lab


def unwrap_pieces(ob, rig, body, dom):
    """UV jak wykrój: szwy na granicach elementów + szew pod rękawem i z tyłu stójki; elementy ustawione nitką osnowy w pionie."""
    lab = _labels(ob, body, dom)
    arms = {s: (P(rig, s + "Arm"), (P(rig, s + "Hand") - P(rig, s + "Arm")).normalized()) for s in ("Left", "Right")}

    def phi(c, s):          # kąt wokół osi ramienia; ±pi = spód rękawa
        a, d = arms[s]
        e1 = (Vector((0, 0, 1)) - d * d.z).normalized()
        e2 = d.cross(e1)
        r = c - a
        return math.atan2(r.dot(e2), r.dot(e1))
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for e in bm.edges:
        fs = e.link_faces
        if len(fs) != 2:
            continue
        la, lb = lab[fs[0].index], lab[fs[1].index]
        if la != lb:
            e.seam = True
        elif la.startswith("sleeve"):
            s = la.split("_")[1]
            pa, pb = phi(fs[0].calc_center_median(), s), phi(fs[1].calc_center_median(), s)
            e.seam = pa * pb < 0 and abs(pa) > 1.6 and abs(pb) > 1.6
        elif la == "collar":                           # szew z tyłu i na grzbiecie (zewnętrzna / wewnętrzna strona stójki)
            ca, cb = fs[0].calc_center_median(), fs[1].calc_center_median()
            e.seam = (ca.y > 0 and cb.y > 0 and ca.x * cb.x < 0) or fs[0].normal.dot(fs[1].normal) < 0.3
    bm.to_mesh(ob.data)
    bm.free()
    C._only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    # obrót elementów: kierunek nitki (pion tułowia, oś rękawa od nadgarstka do barku) → +V
    uv = ob.data.uv_layers.active.data
    for piece in set(lab):
        grain = -arms[piece.split("_")[1]][1] if piece.startswith("sleeve") else Vector((0, 0, 1))
        loops = [li for p in ob.data.polygons if lab[p.index] == piece for li in p.loop_indices]
        g = np.array([ob.data.vertices[ob.data.loops[li].vertex_index].co.dot(grain) for li in loops])
        U = np.array([tuple(uv[li].uv) for li in loops])
        (ga, gb, _), *_ = np.linalg.lstsq(np.c_[U, np.ones(len(U))], g, rcond=None)
        ang = math.atan2(ga, gb)                       # obrót, który przenosi gradient nitki na +V
        ca, sa = math.cos(ang), math.sin(ang)
        c = U.mean(0)
        R = U - c
        U2 = np.c_[R[:, 0] * ca - R[:, 1] * sa, R[:, 0] * sa + R[:, 1] * ca] + c
        for li, q in zip(loops, U2):
            uv[li].uv = tuple(q)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=False, margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("UV pieces", sorted(set(lab)))
    return lab


def _uv_scale(ob):
    """Metry na jednostkę UV (średnio, z pól ścian)."""
    a3 = sum(p.area for p in ob.data.polygons)
    uv = ob.data.uv_layers.active.data
    a2 = 0.0
    for p in ob.data.polygons:
        q = [uv[li].uv for li in p.loop_indices]
        a2 += abs(sum(q[i].x * q[(i + 1) % len(q)].y - q[(i + 1) % len(q)].x * q[i].y for i in range(len(q)))) / 2
    return math.sqrt(a3 / max(a2, 1e-9))


def _stitches(ob, px, size, inset_px, color, dash=(5, 3), width=1):
    """Przeszycia: linie przerywane wzdłuż szwów i brzegów (granice wysp UV), odsunięte do środka elementu o `inset_px`."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uvl = bm.loops.layers.uv.active
    n = 0
    col = np.array(color, np.float32)
    for f in bm.faces:
        cf = sum((l[uvl].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
        for l in f.loops:
            e = l.edge
            if not (e.seam or e.is_boundary):
                continue
            a, b = l[uvl].uv.copy(), l.link_loop_next[uvl].uv.copy()
            t = b - a
            if t.length < 1e-6:
                continue
            nrm = Vector((-t.y, t.x)).normalized()
            if nrm.dot(cf - a) < 0:
                nrm = -nrm
            off = nrm * (inset_px / size)
            pa, pb = (a + off) * size, (b + off) * size
            steps = int((pb - pa).length) + 1
            for k in range(steps):
                q = pa + (pb - pa) * (k / steps)
                if int(q.x + q.y) % (dash[0] + dash[1]) >= dash[0]:
                    continue
                for dx in range(width):
                    x, y = int(q.x) + dx, int(q.y)
                    if 0 <= x < size and 0 <= y < size:
                        px[y, x, :3] = px[y, x, :3] * 0.35 + col * 0.65
                        n += 1
    bm.free()
    return n


def bake_maps(low, high_objs, look, size):
    """Wypiek z wersji szczegółowej na lekką: normalne i okluzja (fałdy, kieszenie, patki, napy); kolor = kamuflaż + przeszycia."""
    C._cycles(32)
    sc = bpy.context.scene
    nrm = bpy.data.images.new(low.name + "_normal", size, size)
    nrm.colorspace_settings.name = "Non-Color"
    ao = bpy.data.images.new(low.name + "_ao", size, size)
    ao.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new(low.name)
    mat.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(mat)
    for p in low.data.polygons:
        p.material_index = 0
    cloth = _mat("cloth", (0.3, 0.3, 0.2))
    for o in [low] + high_objs:
        o.hide_render = False
    for h in high_objs:
        h.data.materials.clear()
        h.data.materials.append(cloth)
    bpy.ops.object.select_all(action="DESELECT")
    for h in high_objs:
        h.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.02
    sc.render.bake.max_ray_distance = 0.05
    sc.render.bake.margin = 8
    C._bake_target(low, nrm)
    C._bake(type="NORMAL")
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.light_settings.distance = 0.04
    C._bake_target(low, ao)
    C._bake(type="AO")
    C._drop_target(low)
    sc.render.bake.use_selected_to_active = False
    # kolor: kamuflaż leśny w przestrzeni UV (plamy tej samej wielkości na każdym elemencie) × okluzja detali, przeszycia
    m_per_uv = _uv_scale(low)
    cm = C.CAMO[look["camo"]]
    cells = max(2, int(round(m_per_uv / look["camo_blotch"])))
    col = np.tile(np.array(cm["base"], np.float32), (size * size, 1))
    for i, (c, thr) in enumerate(cm["spots"]):
        fld = C.smooth_noise(size, size, cells, look["camo_seed"] * 10 + i).ravel()
        col[fld > thr] = np.array(c, np.float32)
    fiber = C.smooth_noise(size, size, cells * 12, 99).ravel()            # nierówność barwienia
    col *= (0.92 + 0.16 * fiber)[:, None]
    a = np.array(ao.pixels[:], np.float32).reshape(-1, 4)[:, 0]
    col *= (0.55 + 0.45 * np.clip(a, 0, 1) ** 1.2)[:, None]
    px = np.c_[np.clip(col, 0, 1), np.ones(size * size, np.float32)].reshape(size, size, 4)
    n = _stitches(low, px, size, inset_px=max(2, int(0.005 / m_per_uv * size)), color=(0.20, 0.19, 0.12))
    alb = bpy.data.images.new(low.name + "_albedo", size, size)
    alb.pixels[:] = px.ravel()
    print("BAKE m/uv %.2f camo cells %d stitches %d px" % (m_per_uv, cells, n))
    # materiał wynikowy: kolor (węzeł „diffuseTexture” jak w MPFB — char_mpfb dopieka na nim cienie) + mapa normalnych
    nt = mat.node_tree
    bsdf = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.85
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.name = "diffuseTexture"
    ti.image = alb
    nt.links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nrm
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return alb, nrm


def make_low(ob, collar, tris):
    """Lekka wersja do gry: kopia ułożonej kurtki uproszczona do budżetu + stójka."""
    low = ob.copy()
    low.data = ob.data.copy()
    low.name = "m65"
    bpy.context.scene.collection.objects.link(low)
    low.vertex_groups.clear()
    cur = sum(len(p.vertices) - 2 for p in low.data.polygons)
    C._only(low)
    dec = low.modifiers.new("dec", "DECIMATE")
    dec.ratio = tris / cur
    bpy.ops.object.modifier_apply(modifier=dec.name)
    for p in low.data.polygons:
        p.material_index = 0
    cl = collar.copy()
    cl.data = collar.data.copy()
    bpy.context.scene.collection.objects.link(cl)
    bpy.ops.object.select_all(action="DESELECT")
    cl.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.join()
    low.data.shade_smooth()
    print("LOW tris", sum(len(p.vertices) - 2 for p in low.data.polygons))
    return low


# ------------------------------------------------------------------------------------------------ podgląd

def _mat(name, rgb, rough=0.8):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = tuple(rgb) + (1.0,)
    b.inputs["Roughness"].default_value = rough
    return m


def shot(path, objs, views=("front", "side", "back"), size=640, zr=None):
    """Render podglądu (EEVEE): kilka widoków obok siebie w jednym PNG."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = size
    sc.render.resolution_y = int(size * 1.25)
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.62, 0.65, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.view_settings.view_transform = "AgX"
    for o in sc.objects:
        o.hide_render = o not in objs and o.type == "MESH"
    if "key" not in bpy.data.objects:
        for nm, rot, e in (("key", (50, 0, -30), 3.5), ("fill", (60, 0, 150), 1.2)):
            ld = bpy.data.lights.new(nm, "SUN")
            ld.energy = e
            lo = bpy.data.objects.new(nm, ld)
            lo.rotation_euler = [math.radians(a) for a in rot]
            sc.collection.objects.link(lo)
    cam = bpy.data.objects.get("cam")
    if cam is None:
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    zs = [(o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box]
    z0, z1 = zr or (min(zs), max(zs))
    cam.data.ortho_scale = (z1 - z0) * 1.08
    cz = (z0 + z1) / 2
    dirs = {"front": (0, -1, 0), "back": (0, 1, 0), "side": (1, 0, 0), "q": (0.7, -0.7, 0)}
    tiles = []
    for v in views:
        d = Vector(dirs[v]).normalized()
        cam.location = Vector((0, 0, cz)) + d * 5
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        tmp = os.path.join(WORK, "_tile_%s.png" % v)
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4))
        bpy.data.images.remove(img)
    out = np.concatenate(tiles, axis=1)
    im = bpy.data.images.new("shot", out.shape[1], out.shape[0])
    im.pixels[:] = out.ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("SHOT", path)


def main():
    name = next(a for a in argv if not a.startswith("--"))
    spec = C.OUTFITS[name]
    os.makedirs(WORK, exist_ok=True)
    rig, body, dom = make_body(spec)
    body.data.materials.clear()
    body.data.materials.append(_mat("skin", (0.62, 0.45, 0.36), 0.6))
    look = fit_look(rig, body, M65)
    jacket = make_shell(rig, body, dom, look)
    jacket.data.materials.append(_mat("cloth", (0.29, 0.30, 0.20)))
    if STAGE == "shell":
        shot(arg("shot", os.path.join(WORK, name + "_shell.png")), [body, jacket])
        return
    simulate(rig, body, jacket, look)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, name + "_sim.blend"))
    if STAGE == "sim":
        shot(arg("shot", os.path.join(WORK, name + "_sim.png")), [body, jacket], views=("front", "q", "side", "back"))
        return
    smooth_rims(jacket, rig)
    collar = make_collar(jacket, rig, look)
    det = make_details(rig, jacket, look)
    det += [make_band(jacket, rig, "hem", look["hem_band"], 0.002, 0.003, "hem_band")]
    det += [make_band(jacket, rig, k, look["cuff_h"], 0.002, 0.003, k + "_band") for k in ("cuff_L", "cuff_R")]
    hi = jacket.copy()
    hi.data = jacket.data.copy()
    hi.name = "jacket_hi"
    bpy.context.scene.collection.objects.link(hi)
    C._only(hi)
    ss = hi.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    bpy.ops.object.modifier_apply(modifier=ss.name)
    shot(os.path.join(WORK, name + "_hi.png"), [body, hi, collar] + det, views=("front", "q", "back"))
    low = make_low(jacket, collar, look["low_tris"])
    unwrap_pieces(low, rig, body, dom)
    bake_maps(low, [hi, collar] + det, look, int(arg("tex", "2048")))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, name + "_final.blend"))
    shot(arg("shot", os.path.join(WORK, name + "_m65.png")), [body, low], views=("front", "q", "side", "back"))
    shot(os.path.join(WORK, name + "_m65_close.png"), [body, low], views=("q", "back"), size=900, zr=(look["hem_z"] - 0.05, P(rig, "Head").z + 0.05))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + "_m65.glb")
    C._only(low)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_image_format="WEBP",
                              export_image_quality=90, export_animations=False, export_apply=True)
    print("OK", dst)


main()
