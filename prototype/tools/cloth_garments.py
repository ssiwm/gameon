"""Ubrania szyte symulacją tkaniny na ciele MPFB — `art_src/clothes/<strój>_<ubranie>.glb` (CHARACTER_PLAN.md).

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2, jak `char_mpfb.py`):
    blender -b -P prototype/tools/cloth_garments.py -- male_scav [male_medic male_hazmat | --all] [--stage=shell|sim|all] [--tex=2048]

Zamiast gotowych ubrań z paczek MakeHuman, dla każdego stroju z tabeli WARDROBE (od warstwy spodniej do wierzchniej):
1. Ciało z tabeli OUTFITS w `char_mpfb.py` (ten sam fenotyp, A-poza MPFB, przód −Y, góra +Z, przed skalowaniem do wzrostu) i buty /
   rękawice z jego paczek MPFB — tylko jako przeszkody dla tkaniny.
2. Bryła ubrania: ciało poszerzone o luz (rękawy, nogawki) + wypukła powłoka tułowia w plastrach — tkanina mostkuje wklęsłości
   (talia, rowek kręgosłupa, krocze) jak prawdziwy wykrój; remesh wokselowy, przycięcie (dekolt, dół, mankiety, pas, nogawki).
3. Symulacja tkaniny: grawitacja, kolizja z ciałem, butami i uszytymi już warstwami; przypięty dekolt albo pas, ściągacze
   (talia, mankiety, nogawki wpuszczone w buty).
4. Detale tylko w wersji szczegółowej (kieszenie z patkami, listwy, napy, pagony, szlufki, nakolanniki, stójka, podwinięcia),
   wypiekane w mapę normalnych i okluzję na lekką wersję do gry; UV jak wykrój (elementy wg wag kości ciała), kolor z przeszyciami.
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
TEX = int(arg("tex", "2048"))

ARMS = {"LeftArm", "LeftForeArm", "RightArm", "RightForeArm"}
COLLIDE = ("boots", "shoes", "gloves")      # części paczek MPFB, o które opiera się tkanina (nogawki na butach, mankiety na rękawicach)


def P(o, n):
    return o.matrix_world @ o.pose.bones["mixamorig:" + n].head


def _is_arm(bone):
    return ("Arm" in bone or "Hand" in bone) and "Shoulder" not in bone


def _is_leg(bone):
    return any(k in bone for k in ("UpLeg", "Leg", "Foot", "Toe"))


# ------------------------------------------------------------------------------------------------ ciało i bryła

def make_body(spec):
    """Ciało MPFB (klucze kształtu zapieczone, bryły pomocnicze usunięte) + buty i rękawice stroju jako przeszkody.
    Zwraca (rig, ciało, dominująca kość wierzchołka, przeszkody)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    ph = info["phenotype"]
    ph.update(spec["phenotype"])
    ph["gender"] = 1.0 if spec["sex"] == "male" else 0.0
    ph["race"] = dict(spec["race"])
    info["rig"] = "mixamo"
    info["clothes"] = ["%s/%s.mhclo" % (c, c) for c in spec["clothes"] if any(k in c for k in COLLIDE)]
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
        if m.name.startswith("Delete."):              # ciało pod butami / rękawicami zostaje: remesh bryły potrzebuje zamkniętej siatki
            body.modifiers.remove(m)
        else:                                          # bryły pomocnicze MPFB (rajstopy, spódnica itp.) usunięte
            bpy.ops.object.modifier_apply(modifier=m.name)
    names = {g.index: g.name.replace("mixamorig:", "") for g in body.vertex_groups if g.name.startswith("mixamorig:")}
    dom = []
    for v in body.data.vertices:
        best = max(((g.weight, names[g.group]) for g in v.groups if g.group in names), default=(0, ""))
        dom.append(best[1])
    obst = []
    for o in [o for o in rig.children if o.type == "MESH" and o != body]:
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.name = o.name.split(".", 1)[-1]
        obst.append(o)
    bpy.context.view_layer.update()
    return rig, body, dom, obst


def landmarks(rig, body, obst):
    """Punkty kroju: krocze, kości (biodra, talia, klatka, kolana, kostki), górna krawędź cholewki buta po każdej stronie."""
    co = np.array([tuple(v.co) for v in body.data.vertices])
    L = {"crotch": co[(np.abs(co[:, 0]) < 0.01) & (co[:, 2] > 0.3 * co[:, 2].max())][:, 2].min(),
         "hips": P(rig, "Hips").z, "waist": P(rig, "Spine").z, "chest": P(rig, "Spine2").z, "arm": P(rig, "LeftArm").z,
         "head": P(rig, "Head").z}
    for s, sx in (("L", 1), ("R", -1)):
        side = "Left" if sx > 0 else "Right"
        L["knee_" + s] = P(rig, side + "Leg")
        L["ankle_" + s] = P(rig, side + "Foot")
        top = L["ankle_" + s].z
        for o in obst:
            if "boots" in o.name or "shoes" in o.name:
                vz = [v.co.z for v in o.data.vertices if v.co.x * sx > 0]
                if vz:
                    top = max(top, max(vz))
        L["boot_" + s] = top
    print("LANDMARKS crotch %.3f hips %.3f waist %.3f knee %.3f ankle %.3f boot %.3f / %.3f" % (
        L["crotch"], L["hips"], L["waist"], L["knee_L"].z, L["ankle_L"].z, L["boot_L"], L["boot_R"]))
    return L


def fit_look(look, L):
    """Wymiary kroju względem ciała: dół kurtki od krocza, pas spodni od bioder, koniec nogawek od cholewki albo kostki."""
    out = dict(look)
    k = look["kind"]
    if k == "jacket":
        out["hem_z"] = L["crotch"] + look["hem_dz"]
        out["loft_bot"] = out["hem_z"] - 0.05
    else:
        out["hem_z"] = -1.0
        out["loft_bot"] = L["crotch"] + 0.02
    out["waist_z"] = L["waist"] + look.get("waist_dz", 0.0)
    out["loft_top"] = L["arm"] + look["loft_dz"] if k != "trousers" else L["hips"] + look["top_dz"] + 0.04
    out["top_z"] = L["hips"] + look.get("top_dz", 0.0)               # górna krawędź spodni
    for s in ("L", "R"):
        if look.get("leg_end") == "boot":                              # wpuszczone w buty: koniec tuż nad cholewką
            out["leg_" + s] = L["boot_" + s] + look["leg_dz"]
        else:                                                          # na buty: do kostki
            out["leg_" + s] = L["ankle_" + s].z + look.get("leg_dz", 0.0)
    return out


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


def _seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def make_shell(rig, body, dom, look, name, obst=()):
    """Bryła ubrania: ciało poszerzone o luz + wypukła powłoka tułowia, remesh wokselowy, przycięcie wg rodzaju ubrania."""
    kind = look["kind"]
    upper, lower = kind != "trousers", kind != "jacket"
    co = np.array([tuple(v.co) for v in body.data.vertices])
    nr = np.array([tuple(v.normal) for v in body.data.vertices])
    dom = np.array(dom)
    disp = np.full(len(co), look["ease_body"])
    for side in ("Left", "Right"):
        a, w = np.array(P(rig, side + "Arm")), np.array(P(rig, side + "Hand"))
        t = np.clip(((co - a) @ (w - a)) / ((w - a) @ (w - a)), 0, 1)
        arm = np.isin(dom, [side + "Arm", side + "ForeArm", side + "Shoulder"])
        if upper:
            disp = np.where(arm, look["ease_sleeve"][0] * (1 - t) + look["ease_sleeve"][1] * t, disp)
        if lower:                                                      # nogawka: luz przy biodrze, kolanie, kostce
            h, k, f = (np.array(P(rig, side + n)) for n in ("UpLeg", "Leg", "Foot"))
            leg = np.array([_is_leg(b) and side in b for b in dom])
            t = np.clip(((co - h) @ (f - h)) / ((f - h) @ (f - h)), 0, 1)
            e0, e1, e2 = look["ease_leg"]
            ease = np.where(t < 0.5, e0 + (e1 - e0) * t / 0.5, e1 + (e2 - e1) * (t - 0.5) / 0.5)
            disp = np.where(leg, ease, disp)
    if lower:                                          # przy butach luz od cholewki, nie od nogi (bryła nie może zaczynać się w bucie)
        from mathutils.bvhtree import BVHTree
        dg = bpy.context.evaluated_depsgraph_get()
        boots = [BVHTree.FromObject(o, dg) for o in obst if "boots" in o.name or "shoes" in o.name]
        top = max((max(v.co.z for v in o.data.vertices) for o in obst if "boots" in o.name or "shoes" in o.name), default=-1.0)
        for i in np.nonzero((co[:, 2] < top + 0.02) & np.array([_is_leg(b) for b in dom]))[0]:
            o = Vector(co[i]) + Vector(nr[i]) * 0.15                     # z zewnątrz do nogi: pierwsze trafienie to wierzch cholewki
            for bv in boots:
                hit = bv.ray_cast(o, -Vector(nr[i]), 0.15)[0]
                if hit is not None:
                    disp[i] = max(disp[i], (hit - Vector(co[i])).length + look["ease_leg"][2] * 0.6)
    fat = co + nr * disp[:, None]

    # powłoka tułowia w plastrach: otoczka wypukła punktów tułowia i ud (bez rąk), luz na zewnątrz, wygładzona w pionie
    hand = np.char.find(dom.astype(str), "Hand") >= 0
    z0, z1 = look["loft_bot"], look["loft_top"]
    pick = ~np.isin(dom, list(ARMS)) & ~hand & (co[:, 2] > z0 - 0.06)
    zs = np.linspace(z0, z1, 36)
    na = 72
    angs = np.linspace(0, 2 * math.pi, na, endpoint=False)
    rings, cents = [], []
    for z in zs:
        sl = co[pick & (np.abs(co[:, 2] - z) < 0.02)][:, :2]
        c = sl.mean(0)
        h = _hull(np.round(sl, 5))
        rings.append([_ray_hull(h, c, a) for a in angs])
        cents.append(c)
    rings, cents = np.array(rings), np.array(cents)
    kk = np.array([1, 2, 3, 2, 1], float)
    kk /= kk.sum()
    pad = np.pad(rings, ((2, 2), (0, 0)), mode="edge")
    rings = sum(kk[i] * pad[i:i + len(zs)] for i in range(5))
    cpad = np.pad(cents, ((2, 2), (0, 0)), mode="edge")
    cents = sum(kk[i] * cpad[i:i + len(zs)] for i in range(5))
    wz = min(max(look["waist_z"], z0 + 0.01), z1 - 0.01)               # talia w zakresie powłoki (spodnie kończą się pod nią)
    ease = np.interp(zs, [z0, wz, z1], look["ease_torso"])
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
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = VOXEL
    rm.adaptivity = 0.0
    C._only(ob)
    bpy.ops.object.modifier_apply(modifier=rm.name)

    # przycięcie
    neck, head = np.array(P(rig, "Neck")), np.array(P(rig, "Head"))
    wr = {s: (np.array(P(rig, s + "Hand")), np.array(P(rig, s + "Hand")) - np.array(P(rig, s + "ForeArm"))) for s in ("Left", "Right")}
    arm_seg = {s: (np.array(P(rig, s + "Arm")), wr[s][0] + 0.2 * wr[s][1] / np.linalg.norm(wr[s][1])) for s in wr}
    vco = np.array([tuple(v.co) for v in me.vertices])
    kill = (vco[:, 2] > head[2]) | (vco[:, 2] < look["hem_z"])
    if upper:
        dxy = np.hypot(vco[:, 0] - neck[0], vco[:, 1] - neck[1])
        front = np.clip((neck[1] - vco[:, 1]) / 0.08, 0, 1)
        kill |= (dxy < look["neck_r"]) & (vco[:, 2] > neck[2] + look["neck_dz"] - look["neck_drop"] * front)
        for s, (w, d) in wr.items():
            near = np.linalg.norm(vco - w, axis=1) < 0.25                # płaszczyzna mankietu tylko przy dłoni (nie tnie nogawek)
            kill |= ((vco - w) @ (d / np.linalg.norm(d)) > look["cuff_over"]) & near
    else:
        kill |= vco[:, 2] > look["top_z"]
        for a, b in arm_seg.values():                                  # ręce zwisające poniżej pasa
            kill |= _seg_dist(vco, a, b) < 0.10
    if lower:
        kill |= (vco[:, 0] >= 0) & (vco[:, 2] < look["leg_L"])
        kill |= (vco[:, 0] < 0) & (vco[:, 2] < look["leg_R"])
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(kill)[0]], context="VERTS")
    seen, parts = set(), []                                            # tylko największy spójny kawałek
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
    print("SHELL", name, "verts", len(me.vertices), "faces", len(me.polygons), "pieces dropped", len(parts) - 1,
          "z %.3f..%.3f" % (min(v.co.z for v in me.vertices), max(v.co.z for v in me.vertices)), "legs to %.3f" % look.get("leg_L", -1))
    return ob


# ------------------------------------------------------------------------------------------------ brzegi i symulacja

def _group(ob, name, weights):
    g = ob.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        if w > 0:
            g.add([i], float(w), "REPLACE")
    return g


def _anchors(rig, look):
    """Punkty, wg których nazywamy brzegi: najbliższa pętla brzegu dostaje nazwę punktu."""
    out = {}
    if look["kind"] != "trousers":
        out.update(neck=P(rig, "Neck"), cuff_L=P(rig, "LeftHand"), cuff_R=P(rig, "RightHand"))
    if look["kind"] == "jacket":
        out["hem"] = Vector((0, 0, look["hem_z"]))
    else:
        out.update(leg_L=P(rig, "LeftFoot"), leg_R=P(rig, "RightFoot"))
    if look["kind"] == "trousers":
        out["waist"] = Vector((0, 0, look["top_z"]))
    return out


def _rims(ob, rig, look):
    """Brzegi ubrania jako uporządkowane pętle wierzchołków nazwane wg `_anchors` (dekolt, mankiety, dół, pas, nogawki)."""
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
    anchors = _anchors(rig, look)
    loops = sorted(loops, key=len, reverse=True)[:len(anchors)]
    pairs = sorted(((np.linalg.norm(co[lp].mean(0) - np.array(a)), k, i) for k, a in anchors.items() for i, lp in enumerate(loops)))
    out, used = {}, set()
    for _, k, i in pairs:
        if k not in out and i not in used:
            out[k] = loops[i]
            used.add(i)
    return out


def _dist_to_rim(co, rim_co):
    return np.array([np.min(np.linalg.norm(rim_co - p, axis=1)) for p in co])


def push_out(ob, rig, obst, margin=0.012):
    """Tkanina nie może zaczynać symulacji w bucie (kolizja wypchnęłaby nogawkę w górę): przy cholewce wierzchołki odsunięte
    promieniście od osi nogi na zewnętrzną powierzchnię buta + `margin` (promień z zewnątrz do osi: pierwsze trafienie = wierzch)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    boots = [o for o in obst if "boots" in o.name or "shoes" in o.name]
    if not boots:
        return
    bvs = [BVHTree.FromObject(o, dg) for o in boots]
    top = max(max(v.co.z for v in o.data.vertices) for o in boots) + 0.03
    legs = {s: (P(rig, s + "Leg"), P(rig, s + "Foot")) for s in ("Left", "Right")}
    n = 0
    for v in ob.data.vertices:
        if v.co.z > top:
            continue
        k, f = legs["Left" if v.co.x > 0 else "Right"]
        t = min(max((v.co.z - f.z) / max(k.z - f.z, 1e-6), 0.0), 1.0)
        ax = f.lerp(k, t)
        ax.z = v.co.z
        d = v.co - ax
        d.z = 0.0
        if d.length < 1e-6:
            continue
        d.normalize()
        r_boot = 0.0
        for bv in bvs:
            hit = bv.ray_cast(ax + d * 0.3, -d, 0.3)[0]
            if hit is not None:
                r_boot = max(r_boot, (hit - ax).length)
        if r_boot and (v.co - ax).length < r_boot + margin:
            v.co = ax + d * (r_boot + margin)
            n += 1
    print("PUSH", ob.name, n, "verts")


def simulate(rig, ob, colliders, look, obst=()):
    """Symulacja tkaniny: grawitacja i kolizja z ciałem, butami i warstwami spodnimi; przypięty dekolt albo pas, ściągacze."""
    C._only(ob)
    sm = ob.modifiers.new("smooth", "SMOOTH")         # schodki wokseli
    sm.factor = 0.6
    sm.iterations = 6
    bpy.ops.object.modifier_apply(modifier=sm.name)
    push_out(ob, rig, obst)
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    rims = _rims(ob, rig, look)
    pin_rim, pin_d = ("waist", 0.02) if look["kind"] == "trousers" else ("neck", 0.012)
    _group(ob, "pin", (_dist_to_rim(co, co[rims[pin_rim]]) < pin_d).astype(float))
    shrink = np.zeros(len(co))
    if look.get("waist_shrink"):
        shrink = np.maximum(shrink, np.clip(1 - np.abs(co[:, 2] - look["waist_z"]) / look["waist_band"], 0, 1) * look["waist_shrink"])
    for key, band, amount in (("cuff_L", "cuff_band", "cuff_shrink"), ("cuff_R", "cuff_band", "cuff_shrink"),
                              ("leg_L", "leg_band", "leg_shrink"), ("leg_R", "leg_band", "leg_shrink")):
        if key in rims and look.get(amount):
            d = _dist_to_rim(co, co[rims[key]])
            shrink = np.maximum(shrink, np.clip(1 - d / look[band], 0, 1) * look[amount])
    smax = max(shrink.max(), 1e-6)
    _group(ob, "shrink", shrink / smax)
    cols = []
    for c in colliders:
        m = c.modifiers.new("collision", "COLLISION")
        c.collision.thickness_outer = 0.005
        c.collision.cloth_friction = 8.0
        cols.append((c, m))
    cl = ob.modifiers.new("cloth", "CLOTH")
    st = cl.settings
    st.quality = 8
    st.mass = 0.35
    st.tension_stiffness = st.compression_stiffness = 150.0     # płótno bawełniane prawie się nie rozciąga
    st.shear_stiffness = 60.0
    st.bending_stiffness = look.get("bending", 8.0)
    st.vertex_group_mass = "pin"
    st.air_damping = 2.0
    st.shrink_min = 0.0                               # waga 0: bez skurczu, waga 1: shrink_max
    st.shrink_max = float(smax) if shrink.max() > 0 else 0.0
    st.vertex_group_shrink = "shrink"
    cs = cl.collision_settings
    cs.collision_quality = 4
    cs.distance_min = 0.004
    cs.use_self_collision = False
    sc = bpy.context.scene
    frames = look.get("frames", 60)
    sc.frame_start, sc.frame_end = 1, frames
    cl.point_cache.frame_start, cl.point_cache.frame_end = 1, frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    bpy.ops.object.modifier_apply(modifier=cl.name)
    for c, m in cols:
        c.modifiers.remove(m)
    sc.frame_set(1)
    ob.data.shade_smooth()
    print("SIM done", ob.name, len(ob.data.vertices), "verts, z %.3f..%.3f" % (min(v.co.z for v in ob.data.vertices), max(v.co.z for v in ob.data.vertices)))


def smooth_rims(ob, rig, look, iters=20):
    """Brzegi po cięciu wokselami są poszarpane: wygładzenie wzdłuż każdej pętli brzegu, pierwszy pierścień sąsiadów idzie za nią."""
    me = ob.data
    co = np.array([tuple(v.co) for v in me.vertices])
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    for key, lp in _rims(ob, rig, look).items():
        lp = np.array(lp)
        orig = co[lp].copy()
        for _ in range(iters):
            q = co[lp]
            co[lp] = 0.5 * q + 0.25 * (np.roll(q, 1, 0) + np.roll(q, -1, 0))
        if key in ("hem", "waist"):                    # dół kurtki i pas spodni równo: wysokość wygładzona mocniej
            z = co[lp, 2]
            for _ in range(40):
                z = 0.5 * z + 0.25 * (np.roll(z, 1) + np.roll(z, -1))
            co[lp, 2] = z
        delta = co[lp] - orig
        rim = set(lp.tolist())
        for i, d in zip(lp, delta):
            for e in bm.verts[int(i)].link_edges:
                j = e.other_vert(bm.verts[int(i)]).index
                if j not in rim:
                    co[j] += 0.5 * d
    bm.free()
    for v, c in zip(me.vertices, co):
        v.co = Vector(c)


# ------------------------------------------------------------------------------------------------ detale

def _new_obj(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
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


def _patch(bvh, name, centre, u, v, size, axis, lift, thick, res=(10, 10), point=0.0, reach=4.0):
    """Łata przylegająca do ubrania: siatka w płaszczyźnie (u, v) wokół `centre`, rzutowana wzdłuż `axis` na powierzchnię i odsunięta
    o `lift` wzdłuż normalnej, potem pogrubiona o `thick`. `point`: dolna krawędź w lekki szpic (patka kieszeni)."""
    u, v, axis = Vector(u).normalized(), Vector(v).normalized(), Vector(axis).normalized()
    nx, ny = res
    verts, miss = [], set()
    for j in range(ny + 1):
        for i in range(nx + 1):
            a, b = i / nx - 0.5, j / ny - 0.5
            if j == 0 and point:
                b -= point * (1 - 2 * abs(a)) / size[1]
            p = Vector(centre) + u * (a * size[0]) + v * (b * size[1])
            hit, nrm, _, _ = bvh.ray_cast(p - axis * 0.4, axis, reach)
            if hit is None:                                # poza ubraniem: ten wierzchołek i jego ściany odpadają
                miss.add(len(verts))
                hit, nrm = p, -axis
            if nrm.dot(axis) > 0:
                nrm = -nrm
            verts.append(hit + nrm * lift)
    faces = [(j * (nx + 1) + i, j * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i)
             for j in range(ny) for i in range(nx)]
    faces = [f for f in faces if not miss.intersection(f)]
    if miss:
        print("PATCH trimmed", name, len(miss), "of", len(verts))
    if not faces:
        return None
    ob = _new_obj(name, verts, faces)
    bm = bmesh.new()                                       # wierzchołki bez ścian (chybione) usunięte
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[x for x in bm.verts if not x.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
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


def pocket(bvh, name, centre, u, v, axis, w, h, flap_h, lift=0.002, depth=0.003, snap=True, reach=4.0):
    """Kieszeń naszywana z patką i napą; `depth` > 3 mm = kieszeń miechowa (wypchana)."""
    c, v_ = Vector(centre), Vector(v).normalized()
    out = [_patch(bvh, name, c, u, v, (w, h), axis, lift, depth, reach=reach)]
    if out[0] is None:
        return []
    if flap_h:
        fc = c + v_ * (h / 2 + 0.006 - flap_h / 2)
        out.append(_patch(bvh, name + "_flap", fc, u, v, (w + 0.012, flap_h), axis, lift + depth + 0.002, 0.003, point=0.009, reach=reach))
        if snap:
            out.append(_snap(bvh, name + "_snap", fc - v_ * (flap_h / 2 - 0.014), axis, lift=lift + depth + 0.005))
    return out


def make_band(ob, rim, height, out, thick, name, flip=False):
    """Podwinięcie / mankiet / pasek: pas tkaniny wzdłuż brzegu (od brzegu w głąb ubrania po powierzchni), lekko odsunięty, pogrubiony."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    nr = np.array([tuple(v.normal) for v in ob.data.vertices])
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    rs = set(rim)
    inward = []
    for i in rim:                                  # kierunek od brzegu w głąb tkaniny: średnia do sąsiadów spoza brzegu
        v = bm.verts[i]
        ns = [e.other_vert(v).co for e in v.link_edges if e.other_vert(v).index not in rs]
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
        for j, i in enumerate(rim):
            verts.append(co[i] - inward[j] * 0.002 + inward[j] * height * t + nr[i] * out)
    n = len(rim)
    faces = [(k * n + j, k * n + (j + 1) % n, (k + 1) * n + (j + 1) % n, (k + 1) * n + j) for k in range(rows) for j in range(n)]
    band = _new_obj(name, verts, faces)
    p0 = band.data.polygons[0]
    if p0.normal.dot(Vector(nr[rim[0]])) < 0:
        band.data.flip_normals()
    return _solidify(band, thick, 1.0)


def make_collar(ob, rim, rig, look):
    """Stójka: pas tkaniny z krawędzi dekoltu w górę (lekko na zewnątrz), pogrubiony; osobny materiał (po złączeniu indeks 1)."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    neck = np.array(P(rig, "Neck"))
    rows = 4
    verts = []
    for k in range(rows + 1):
        t = k / rows
        for i in rim:
            p = co[i]
            out = np.array([p[0] - neck[0], p[1] - neck[1], 0.0])
            out /= np.linalg.norm(out) + 1e-9
            verts.append(p + np.array([0, 0, look["collar_h"] * t]) + out * (look["collar_flare"] * t - 0.002))
    n = len(rim)
    faces = [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for k in range(rows) for i in range(n)]
    col = _new_obj("collar", verts, faces)
    col.data.materials.append(_mat("collar_tmp", (0.3, 0.3, 0.2)))
    p0 = col.data.polygons[0]
    if p0.normal.dot(Vector((p0.center.x - neck[0], p0.center.y - neck[1], 0))) < 0:
        col.data.flip_normals()
    return _solidify(col, look["collar_thick"], 1.0)


def ring_band(bvh, name, z, h, centre, lift, thick, n=72):
    """Pas wokół ubrania na wysokości `z` (np. pas kombinezonu): punkty rzutowane z zewnątrz do osi."""
    verts = []
    rows = 2
    for k in range(rows + 1):
        zz = z - h / 2 + h * k / rows
        for i in range(n):
            a = 2 * math.pi * i / n
            d = Vector((math.cos(a), math.sin(a), 0))
            o = Vector((centre[0], centre[1], zz)) + d * 0.8
            hit, nrm, _, _ = bvh.ray_cast(o, -d, 1.0)
            if hit is None:
                hit, nrm, _, _ = bvh.find_nearest(o - d * 0.6)
            if nrm.dot(d) < 0:
                nrm = -nrm
            verts.append(hit + nrm * lift)
    faces = [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for k in range(rows) for i in range(n)]
    ob = _new_obj(name, verts, faces)
    p0 = ob.data.polygons[0]
    if p0.normal.dot(Vector((p0.center.x - centre[0], p0.center.y - centre[1], 0))) < 0:
        ob.data.flip_normals()
    return _solidify(ob, thick, 1.0)


FWD, BACK = (0, 1, 0), (0, -1, 0)          # kierunki rzutu: na przód (przód ciała to −Y) i na plecy
X, Z = (1, 0, 0), (0, 0, 1)


def _leg_y(body, dom, side, z):
    """Środek nogi (y) na wysokości z — do kieszeni bocznych."""
    co = np.array([tuple(v.co) for v in body.data.vertices])
    m = np.array([_is_leg(b) and side in b for b in dom]) & (np.abs(co[:, 2] - z) < 0.02)
    return float(co[m][:, 1].mean()) if m.any() else 0.0


def details_jacket(bvh, rig, ob, look, L, rims, body, dom):
    """Kurtka: kieszenie piersiowe (i dolne) z patkami, listwa z napami, pagony, patki mankietów."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    neck_front = co[rims["neck"]][:, 2].min()
    hem = look["hem_z"]
    det = []
    chest_z = L["chest"] + look["chest_dz"]
    for sx in (-1, 1):
        cx, cw, chh = look["chest_pocket"]
        det += pocket(bvh, "pocket_c%d" % sx, (sx * cx, -0.5, chest_z), X, Z, FWD, cw, chh, 0.062)
        if look.get("hip_pocket"):
            hx, hw, hh = look["hip_pocket"]
            det += pocket(bvh, "pocket_h%d" % sx, (sx * hx, -0.5, hem + look["hip_dz"]), X, Z, FWD, hw, hh, 0.072, 0.003, 0.004)
        side = "Left" if sx > 0 else "Right"
        a, n = P(rig, side + "Arm"), P(rig, "Neck")
        if look.get("epaulet"):                                        # pagon: od szwu stójki do stawu barkowego, rzut z góry
            x0, x1 = n.x + sx * (look["neck_r"] + 0.012), a.x + sx * 0.012
            det.append(_patch(bvh, "epaulet%d" % sx, ((x0 + x1) / 2, a.y, 2.5), X, (0, 1, 0), (abs(x1 - x0), look["epaulet"]),
                              (0, 0, -1), 0.003, 0.003, res=(10, 3)))
            det.append(_snap(bvh, "snap_e%d" % sx, (x0 + sx * 0.02, a.y, 2.5), (0, 0, -1), r=0.007, lift=0.006))
        w, fa = P(rig, side + "Hand"), P(rig, side + "ForeArm")       # patka mankietu (rzep) na wierzchu przedramienia
        d = (w - fa).normalized()
        up = (Vector(Z) - d * d.z).normalized()
        det.append(_patch(bvh, "cufftab%d" % sx, w - d * 0.05 + up * 0.3, up.cross(d), d, (0.03, 0.07), -up, 0.004, 0.003, res=(4, 6)))
    top = neck_front - 0.004                                           # listwa zapięcia (kryje zamek) z napami
    det.append(_patch(bvh, "placket", (look["placket_x"], -0.5, (hem + top) / 2), X, Z, (look["placket_w"], top - hem), FWD, 0.004, 0.003,
                      res=(4, 40)))
    for k in range(5):
        det.append(_snap(bvh, "snap_p%d" % k, (look["placket_x"], -0.5, hem + 0.06 + (top - hem - 0.10) * k / 4), FWD, lift=0.007))
    det += [make_band(ob, rims["hem"], look["hem_band"], 0.002, 0.003, "hem_band")]
    det += [make_band(ob, rims[k], look["cuff_h"], 0.002, 0.003, k + "_band") for k in ("cuff_L", "cuff_R")]
    return det


def details_trousers(bvh, rig, ob, look, L, rims, body, dom):
    """Spodnie: pasek ze szlufkami, rozporek, kieszenie boczne miechowe i tylne z patkami, nakolanniki, podwinięcia nogawek."""
    det = [make_band(ob, rims["waist"], look["waistband"], 0.002, 0.004, "waistband")]
    top = look["top_z"]
    cx, cy = 0.0, float(np.array([tuple(v.co) for v in ob.data.vertices])[rims["waist"]][:, 1].mean())
    for i, a in enumerate((-150, -75, -28, 28, 75, 150)):                   # szlufki: kąt od przodu
        ar = math.radians(a)
        d = Vector((math.sin(ar), -math.cos(ar), 0))
        c = Vector((cx, cy, top - look["waistband"] / 2)) + d * 0.6
        det.append(_patch(bvh, "loop%d" % i, c, Vector((math.cos(ar), math.sin(ar), 0)), Z, (0.012, look["waistband"] + 0.008), -d,
                          0.006, 0.003, res=(2, 4)))
    det.append(_patch(bvh, "fly", (0.012, -0.5, top - look["waistband"] - 0.085), X, Z, (0.032, 0.17), FWD, 0.003, 0.003, res=(3, 12)))
    for sx, s in ((1, "L"), (-1, "R")):
        side = "Left" if sx > 0 else "Right"
        kz = L["knee_" + s].z
        if look.get("cargo"):                                          # kieszeń boczna na udzie, rzut z boku
            w, h = look["cargo"]
            z = (L["crotch"] + kz) / 2 + 0.02
            y = _leg_y(body, dom, side, z)
            det += pocket(bvh, "cargo_" + s, (sx * 0.7, y, z), (0, -1, 0), Z, (-sx, 0, 0), w, h, 0.07, 0.003, 0.009,
                          reach=0.4 + 0.7 - 0.12)               # promień kończy się przed drugą nogą
        if look.get("back_pocket"):                                    # tylne kieszenie, rzut od pleców
            w, h = look["back_pocket"]
            det += pocket(bvh, "back_" + s, (sx * 0.09, 0.6, L["hips"] - 0.03), (-1, 0, 0), Z, BACK, w, h, 0.055)
        if look.get("knee_patch"):                                     # wzmocnienie kolana
            w, h = look["knee_patch"]
            k = L["knee_" + s]
            det.append(_patch(bvh, "knee_" + s, (k.x, -0.6, k.z + 0.01), X, Z, (w, h), FWD, 0.003, 0.002, res=(8, 10)))
        det.append(make_band(ob, rims["leg_" + s], look["leg_hem"], 0.002, 0.003, "leg_band_" + s))
    return det


def details_coverall(bvh, rig, ob, look, L, rims, body, dom):
    """Kombinezon: zamek z listwą od szyi do krocza, kieszenie piersiowe, pas, nakolanniki, mankiety i podwinięcia nogawek."""
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    neck_front = co[rims["neck"]][:, 2].min()
    det = []
    bot = L["crotch"] + 0.05
    top = neck_front - 0.004
    det.append(_patch(bvh, "placket", (look["placket_x"], -0.5, (bot + top) / 2), X, Z, (look["placket_w"], top - bot), FWD, 0.004, 0.003,
                      res=(4, 50)))
    cx, cw, chh = look["chest_pocket"]
    for sx in (-1, 1):
        det += pocket(bvh, "pocket_c%d" % sx, (sx * cx, -0.5, L["chest"] + look["chest_dz"]), X, Z, FWD, cw, chh, 0.05, snap=False)
    if look.get("belt_h"):
        c = co[(np.abs(co[:, 2] - look["waist_z"]) < 0.02)][:, :2].mean(0)
        det.append(ring_band(bvh, "belt", look["waist_z"], look["belt_h"], c, 0.003, 0.004))
    for s in ("L", "R"):
        k = L["knee_" + s]
        w, h = look["knee_patch"]
        det.append(_patch(bvh, "knee_" + s, (k.x, -0.6, k.z + 0.01), X, Z, (w, h), FWD, 0.003, 0.005, res=(8, 10)))
        det.append(make_band(ob, rims["leg_" + s], look["leg_hem"], 0.002, 0.003, "leg_band_" + s))
    det += [make_band(ob, rims[k], look["cuff_h"], 0.002, 0.003, k + "_band") for k in ("cuff_L", "cuff_R")]
    return det


DETAILS = {"jacket": details_jacket, "trousers": details_trousers, "coverall": details_coverall}


# ------------------------------------------------------------------------------------------------ rozkrój i mapy

def _labels(ob, body, dom, kind, seam_z=None):
    """Element wykroju dla każdej ściany wg kości najbliższego punktu ciała (wagi MPFB wyznaczają naturalne linie szwów):
    rękawy, przody L/P i tył (kurtka), nogawki przód / tył L/P (spodnie i dół kombinezonu), stójka (materiał 1).
    Granice wygładzone głosowaniem sąsiadów, żeby szwy szły gładko."""
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
        fb = "front" if c.y < -0.01 else "back"
        s = "L" if c.x > 0 else "R"
        if _is_arm(bone) and kind != "trousers":
            lab.append("sleeve_" + ("Left" if bone.startswith("Left") else "Right"))
        elif kind == "trousers" or (kind == "coverall" and c.z < seam_z):        # kombinezon: szew poziomo pod pasem
            lab.append("leg%s_%s" % (fb, s))
        else:
            lab.append("front_" + s if fb == "front" else "back")
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


def unwrap_pieces(ob, rig, body, dom, kind, seam_z=None):
    """UV jak wykrój: szwy na granicach elementów + szew pod rękawem i z tyłu stójki; elementy ustawione nitką osnowy w pionie."""
    lab = _labels(ob, body, dom, kind, seam_z)
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
    uv = ob.data.uv_layers.active.data                 # obrót elementów: kierunek nitki (pion, oś rękawa) → +V
    for piece in set(lab):
        grain = -arms[piece.split("_")[1]][1] if piece.startswith("sleeve") else Vector((0, 0, 1))
        loops = [li for p in ob.data.polygons if lab[p.index] == piece for li in p.loop_indices]
        g = np.array([ob.data.vertices[ob.data.loops[li].vertex_index].co.dot(grain) for li in loops])
        U = np.array([tuple(uv[li].uv) for li in loops])
        (ga, gb, _), *_ = np.linalg.lstsq(np.c_[U, np.ones(len(U))], g, rcond=None)
        ang = math.atan2(ga, gb)
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
                if dash[1] and int(q.x + q.y) % (dash[0] + dash[1]) >= dash[0]:
                    continue
                for dx in range(width):
                    x, y = int(q.x) + dx, int(q.y)
                    if 0 <= x < size and 0 <= y < size:
                        px[y, x, :3] = px[y, x, :3] * 0.35 + col * 0.65
                        n += 1
    bm.free()
    return n


def bake_maps(low, high_objs, look, size):
    """Wypiek z wersji szczegółowej na lekką: normalne i okluzja (fałdy, kieszenie, patki, napy); kolor = wzór + przeszycia."""
    C._cycles(32)
    sc = bpy.context.scene
    nrm = bpy.data.images.new(low.name + "_normal", size, size)
    nrm.colorspace_settings.name = "Non-Color"
    ao = bpy.data.images.new(low.name + "_ao", size, size)
    ao.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new(low.name)
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
    # kolor: wzór (kamuflaż / jednolity) w przestrzeni UV — plamy tej samej wielkości na każdym elemencie — × okluzja, przeszycia
    m_per_uv = _uv_scale(low)
    cm = C.CAMO[look["camo"]]
    cells = max(2, int(round(m_per_uv / look.get("camo_blotch", 0.055))))
    col = np.tile(np.array(look.get("base", cm["base"]), np.float32), (size * size, 1))
    cover = look.get("camo_cover", (0.24, 0.30, 0.12))                  # udział plam (brąz, zieleń, czerń): progi z kwantyli, nie stałe
    for i, (c, thr) in enumerate(cm["spots"]):
        fld = C.smooth_noise(size, size, cells, look.get("camo_seed", 3) * 10 + i).ravel()
        q = np.quantile(fld, 1.0 - cover[i]) if i < len(cover) else thr
        col[fld > q] = np.array(c, np.float32)
    fiber = C.smooth_noise(size, size, cells * 12, 99).ravel()            # nierówność barwienia
    col *= (1 - look.get("mottle", 0.08) + 2 * look.get("mottle", 0.08) * fiber)[:, None]
    a = np.array(ao.pixels[:], np.float32).reshape(-1, 4)[:, 0]
    k = look.get("ao", 0.45)
    col *= (1 - k + k * np.clip(a, 0, 1) ** 1.2)[:, None]
    px = np.c_[np.clip(col, 0, 1), np.ones(size * size, np.float32)].reshape(size, size, 4)
    st = look.get("stitch", {})
    n = _stitches(low, px, size, inset_px=max(2, int(0.005 / m_per_uv * size)), color=st.get("color", (0.20, 0.19, 0.12)),
                  dash=st.get("dash", (5, 3)), width=st.get("width", 1))
    alb = bpy.data.images.new(low.name + "_albedo", size, size)
    alb.pixels[:] = px.ravel()
    print("BAKE m/uv %.2f cells %d stitches %d px" % (m_per_uv, cells, n))
    nt = _nodes(mat)                                   # kolor pod nazwą węzła jak w MPFB (char_mpfb dopieka na nim cienie) + normalne
    bsdf = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = look.get("rough", 0.85)
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.name = "diffuseTexture"
    ti.image = alb
    nt.links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nrm
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


def make_low(ob, collar, tris, name):
    """Lekka wersja do gry: kopia ułożonego ubrania uproszczona do budżetu (+ stójka)."""
    low = ob.copy()
    low.data = ob.data.copy()
    low.name = name
    bpy.context.scene.collection.objects.link(low)
    low.vertex_groups.clear()
    cur = sum(len(p.vertices) - 2 for p in low.data.polygons)
    C._only(low)
    dec = low.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, tris / cur)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    for p in low.data.polygons:
        p.material_index = 0
    if collar is not None:
        cl = collar.copy()
        cl.data = collar.data.copy()
        bpy.context.scene.collection.objects.link(cl)
        bpy.ops.object.select_all(action="DESELECT")
        cl.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low
        bpy.ops.object.join()
    low.data.shade_smooth()
    print("LOW", name, "tris", sum(len(p.vertices) - 2 for p in low.data.polygons))
    return low


# ------------------------------------------------------------------------------------------------ kroje i garderoba

STITCH_OLIVE = {"color": (0.20, 0.19, 0.12)}
STITCH_NAVY = {"color": (0.05, 0.07, 0.13)}
STITCH_NAVY_LIGHT = {"color": (0.30, 0.34, 0.45)}             # jasna nić: kieszenie i listwa czytelne na granacie
TAPE_HAZMAT = {"color": (0.55, 0.40, 0.04), "dash": (1, 0), "width": 4}     # zgrzewane szwy podklejone taśmą

# kurtka polowa M65: dół tuż pod kroczem (zakrywa siedzenie), ściągacz w talii, stójka, cztery kieszenie z patkami, pagony
M65 = {
    "kind": "jacket", "hem_dz": -0.025, "waist_dz": 0.0, "loft_dz": 0.0,          # powłoka do stawu barkowego (wyżej: kanciaste barki)
    "ease_body": 0.012, "ease_sleeve": (0.018, 0.013), "ease_torso": (0.030, 0.025, 0.012),
    "waist_band": 0.018, "waist_shrink": 0.05, "cuff_band": 0.035, "cuff_shrink": 0.30,
    "neck_r": 0.085, "neck_dz": -0.005, "neck_drop": 0.035, "cuff_over": 0.03,
    "collar_h": 0.065, "collar_flare": 0.008, "collar_thick": 0.004, "hem_band": 0.03, "cuff_h": 0.045,
    "chest_dz": 0.025, "chest_pocket": (0.115, 0.13, 0.16), "hip_dz": 0.13, "hip_pocket": (0.098, 0.125, 0.19),
    "epaulet": 0.05, "placket_x": 0.012, "placket_w": 0.036,
    "camo": "woodland", "camo_seed": 3, "stitch": STITCH_OLIVE, "low_tris": 5000,
}
# spodnie polowe BDU: pas na biodrach, nogawki wpuszczone w buty (ściągacz nad cholewką), kieszenie boczne miechowe, nakolanniki
BDU = {
    "kind": "trousers", "top_dz": 0.055, "waist_dz": 0.0,
    "ease_body": 0.012, "ease_leg": (0.028, 0.022, 0.016), "ease_torso": (0.018, 0.016, 0.014),
    "leg_end": "boot", "leg_dz": -0.015, "leg_band": 0.03, "leg_shrink": 0.0,    # nogawka kończy się tuż za krawędzią cholewki (ściągacz na bucie zsuwa się w górę, głębiej wpada do buta)
    "waistband": 0.04, "leg_hem": 0.025, "cargo": (0.17, 0.20), "back_pocket": (0.13, 0.15), "knee_patch": (0.13, 0.19),
    "camo": "woodland", "camo_seed": 5, "stitch": STITCH_OLIVE, "low_tris": 4000,
}
# mundur ratownika: kurtka do bioder (ściągacz w pasie), niska stójka, kieszenie piersiowe, pagony; spodnie z kieszeniami bocznymi na buty
NAVY = (0.13, 0.18, 0.31)                  # jaśniejszy granat niż w CAMO (detale ginęły w ciemnym)
EMT_JACKET = dict(M65, hem_dz=0.075, collar_h=0.042, hip_pocket=None, chest_pocket=(0.11, 0.12, 0.14), waist_shrink=0.0,
                  hem_band=0.045, camo="navy", base=NAVY, ao=0.6, stitch=STITCH_NAVY_LIGHT, mottle=0.06, low_tris=4500)
EMT_TROUSERS = dict(BDU, leg_end="boot", leg_dz=-0.03, leg_shrink=0.0, ease_leg=(0.026, 0.022, 0.020), knee_patch=None,
                    camo="navy", base=NAVY, ao=0.6, stitch=STITCH_NAVY_LIGHT, mottle=0.06)     # nogawka oparta na cholewce
# kombinezon ochronny: jedna część od szyi do kostek, pas, nakolanniki, gumowany (gładszy), szwy podklejone taśmą
COVERALL = {
    "kind": "coverall", "waist_dz": 0.0, "loft_dz": 0.035,
    "ease_body": 0.016, "ease_sleeve": (0.030, 0.022), "ease_torso": (0.034, 0.028, 0.016), "ease_leg": (0.032, 0.028, 0.030),
    "waist_band": 0.02, "waist_shrink": 0.06, "cuff_band": 0.035, "cuff_shrink": 0.30,
    "leg_end": "ankle", "leg_dz": -0.005, "leg_band": 0.04, "leg_shrink": 0.15,
    "neck_r": 0.085, "neck_dz": -0.005, "neck_drop": 0.03, "cuff_over": 0.03,
    "cuff_h": 0.04, "leg_hem": 0.03,                                # bez stójki: kaptur kryje szyję (stójka wchodziła w pochłaniacz maski)
    "chest_dz": 0.03, "chest_pocket": (0.11, 0.12, 0.13), "placket_x": 0.0, "placket_w": 0.04, "belt_h": None,   # pas z ekwipunku
    "knee_patch": (0.13, 0.16), "bending": 10.0,
    "camo": "hazmat", "stitch": TAPE_HAZMAT, "mottle": 0.04, "rough": 0.62, "low_tris": 5000,
}

# ubrania strojów od warstwy spodniej do wierzchniej (wierzchnia ma spodnią jako przeszkodę w symulacji)
WARDROBE = {
    "male_scav": [("bdu", BDU), ("m65", M65)],
    "male_medic": [("emt_trousers", EMT_TROUSERS), ("emt_jacket", EMT_JACKET)],
    "male_hazmat": [("coverall", COVERALL)],
}


# ------------------------------------------------------------------------------------------------ podgląd

def _nodes(m):
    if m.node_tree is None:
        m.use_nodes = True
    return m.node_tree


def _mat(name, rgb, rough=0.8):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    _nodes(m)
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
    _nodes(sc.world)
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.62, 0.65, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.view_settings.view_transform = "AgX"
    hidden = {o: o.hide_render for o in sc.objects}
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
    for o, h in hidden.items():
        o.hide_render = h
    out = np.concatenate(tiles, axis=1)
    im = bpy.data.images.new("shot", out.shape[1], out.shape[0])
    im.pixels[:] = out.ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("SHOT", path)


def _hi_copy(ob):
    hi = ob.copy()
    hi.data = ob.data.copy()
    hi.name = ob.name + "_hi"
    bpy.context.scene.collection.objects.link(hi)
    C._only(hi)
    ss = hi.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    bpy.ops.object.modifier_apply(modifier=ss.name)
    return hi


def build(outfit):
    spec = C.OUTFITS[outfit]
    rig, body, dom, obst = make_body(spec)
    body.data.materials.clear()
    body.data.materials.append(_mat("skin", (0.62, 0.45, 0.36), 0.6))
    L = landmarks(rig, body, obst)
    colliders = [body] + obst
    lows = []
    for gname, base in WARDROBE[outfit]:
        look = fit_look(base, L)
        ob = make_shell(rig, body, dom, look, gname, obst)
        ob.data.materials.append(_mat("cloth", (0.29, 0.30, 0.20)))
        if STAGE == "shell":
            shot(os.path.join(WORK, "%s_%s_shell.png" % (outfit, gname)), [body, ob] + obst)
            continue
        simulate(rig, ob, colliders, look, obst)
        colliders.append(ob)                                           # warstwa wierzchnia opiera się na spodniej
        if STAGE == "sim":
            shot(os.path.join(WORK, "%s_%s_sim.png" % (outfit, gname)), [body, ob] + obst, views=("front", "q", "side", "back"))
            continue
        smooth_rims(ob, rig, look)
        rims = _rims(ob, rig, look)
        collar = make_collar(ob, rims["neck"], rig, look) if "collar_h" in look else None
        det = DETAILS[look["kind"]](bpy_bvh(ob), rig, ob, look, L, rims, body, dom)
        det = [d for d in det if d is not None]
        hi = _hi_copy(ob)
        high = [hi] + ([collar] if collar else []) + det
        shot(os.path.join(WORK, "%s_%s_hi.png" % (outfit, gname)), [body, *obst, *high], views=("front", "q", "back"))
        low = make_low(ob, collar, look["low_tris"], "%s_%s" % (outfit, gname))
        unwrap_pieces(low, rig, body, dom, look["kind"], look["waist_z"])
        ob.hide_render = True                                          # siatka symulacji pokrywa się z wersją szczegółową (okluzja w prążki)
        bake_maps(low, high, look, TEX)
        for o in high:                                                 # wersja szczegółowa tylko do wypieku
            o.hide_render = True
        ob.hide_render = True
        os.makedirs(OUT, exist_ok=True)
        dst = os.path.join(OUT, "%s_%s.glb" % (outfit, gname))
        C._only(low)
        bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_image_format="WEBP",
                                  export_image_quality=90, export_animations=False, export_apply=True)
        print("OK", dst)
        lows.append(low)
    if lows:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, outfit + "_final.blend"))
        shot(os.path.join(WORK, outfit + "_sewn.png"), [body, *obst, *lows], views=("front", "q", "side", "back"))
        shot(os.path.join(WORK, outfit + "_sewn_close.png"), [body, *obst, *lows], views=("q", "back"), size=900)


def bpy_bvh(ob):
    from mathutils.bvhtree import BVHTree
    return BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())


os.makedirs(WORK, exist_ok=True)
for n in (list(WARDROBE) if "--all" in argv else [a for a in argv if not a.startswith("--")]):
    build(n)
