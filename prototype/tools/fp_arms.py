"""Ręce do widoku z oczu (strzelnica FPP, RANGE_FPS_PLAN.md) — `art/char3d/fp/fp_arms_<strój>.glb`.

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2, jak `char_mpfb.py`; najpierw rękawy z `cloth_garments.py --fp`):
    blender -b -P prototype/tools/cloth_garments.py -- male_scav --only=m65 --fp
    blender -b -P prototype/tools/fp_arms.py -- male_scav [--tex=2048] [--samples=64]      # + build/fp/fp_arms_scav.blend dla fp_grip.py

Ciało z tabeli OUTFITS w `char_mpfb.py` (ten sam fenotyp, szkielet „mixamo” z palcami), ale bez upraszczania — z bliska widać każdy
staw palca. Z ciała powstają:
- rękawice taktyczne bez palców (oliwkowe, jak w viewmodelach CS): dłoń i mankiet do 7,5 cm nad nadgarstkiem z ciała, palce ucięte
  w poprzek członu bliższego (obszycie otworu), odsunięte od skóry, zaokrąglone podziałem i pogrubione; panele z pozy spoczynkowej
  (wnętrze z zamszu, zamszowa obwódka skorupy z dwoma szwami, elastyczny grzbiet w prążki) — materiał proceduralny wypiekany
  w Cycles do tekstur; formowana skorupa z czterema garbami na kostkach i owalne nakładki na pierwszych członach palców (dopasowane
  do rękawicy, wagi z rękawicy); pasek na rzep na nadgarstku z patką i szwem w krzyż;
- palce z rękawic: skóra ciała (kolor skóry MPFB z paznokciami wypieczony na własne UV);
- rękawy kurtki M65 z symulacji tkaniny (`art_src/clothes/<strój>_m65_fp.glb`), wagi kości z ciała;
- zegarek na lewym nadgarstku (koperta, szkło, pasek), przypięty do przedramienia.
Samo ciało nie trafia do pliku (rękawice i rękawy zakrywają je w całości). Orientacja jak `char_mpfb.py`: przód +X, góra +Z, stopy
na z = 0, wzrost wg tabeli — szkielet zgodny z modelem postaci w grze.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
_argv = sys.argv
sys.argv = [_argv[0], "--"]          # char_mpfb przy imporcie nic nie buduje
import char_mpfb as C  # noqa: E402
sys.argv = _argv
from bl_ext.user_default.mpfb.services import HumanService  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


OUT = os.path.join(os.path.dirname(HERE), "art", "char3d", "fp")
CLOTH_SRC = os.path.join(REPO, "art_src", "clothes")
TEX = int(arg("tex", "2048"))
SAMPLES = int(arg("samples", "64"))
WORK = arg("work", os.path.join(REPO, "build", "fp"))
PRE = "mixamorig:"

GLOVE_GAP = 0.0016           # m — skóra rękawicy nad skórą dłoni
GLOVE_CUFF = 0.075           # m — mankiet nad nadgarstkiem
GLOVE_FLARE = 0.0065         # m — rozszerzenie mankietu na końcu
GLOVE_THICK = 0.0012         # m — grubość skóry (widoczna na krawędzi mankietu)
SLEEVE_THICK = 0.0018        # m — grubość tkaniny rękawa
# rękawice taktyczne bez palców (oliwkowe, jak na zdjęciach referencyjnych i w viewmodelach CS): zamsz, elastyczny grzbiet w prążki,
# twarda skorupa na kostkach, gumowe nakładki na pierwszych członach palców, pasek na rzep na nadgarstku; dalej palców — skóra
OLIVE_SUEDE = (0.105, 0.112, 0.040)     # zamsz (liniowo; sRGB ok. 0,36 0,37 0,22)
OLIVE_PALM = (0.080, 0.084, 0.032)      # zamsz wnętrza dłoni (ciemniejszy, wytarty)
OLIVE_RIB = (0.050, 0.060, 0.018)       # elastyczny grzbiet w prążki
OLIVE_BIND = (0.036, 0.042, 0.014)      # obszycie otworów palców
OLIVE_STITCH = (0.042, 0.047, 0.016)    # nici szwów
SHELL_PLASTIC = (0.016, 0.018, 0.012)   # skorupa i nakładki (TPU, czarnooliwkowy)
STRAP_WEB = (0.066, 0.078, 0.027)       # taśma paska na rzep
FINGER_CUT = {"Index": 0.74, "Middle": 0.76, "Ring": 0.76, "Pinky": 0.72, "Thumb": 0.55}   # koniec rękawicy: ułamek członu bliższego
SKIN_TONE = (0.74, 0.66, 0.58)          # mnożnik koloru skóry palców (opalenizna, brud)
SKIN_UNDER = 0.005                      # m — skóra palca zaczyna się pod rękawicą (bez szczeliny przy zgięciu)
HEM = 0.0045                            # m — obszycie otworu palca
SHELL_GAP = 0.0006                      # m — skorupa / nakładka nad tkaniną
STRAP_SPAN = (0.003, 0.031)             # m — pasek na rzep: od – do (od nadgarstka w stronę łokcia)
GLOVE_TEX = int(arg("glove-tex", "4096"))

def _bone_head(rig, n):
    return rig.matrix_world @ rig.data.bones[PRE + n].head_local


def make_body(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    ph = info["phenotype"]
    ph.update(spec["phenotype"])
    ph["gender"] = 1.0 if spec["sex"] == "male" else 0.0
    ph["race"] = dict(spec["race"])
    info["rig"] = "mixamo"
    info["eyes"] = ""
    info["eyebrows"] = ""
    info["hair"] = ""
    info["clothes"] = []
    info["skin_mhmat"] = "%s/%s.mhmat" % (spec["skin"], spec["skin"])
    info["skin_material_type"] = "MAKESKIN"
    info["alternative_materials"] = {}
    st = HumanService.get_default_deserialization_settings()
    st["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, st)
    rig = body.parent
    body.name = "body"
    C._only(body)
    if body.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    return rig, body


def _weights(ob):
    """Wagi wierzchołków: lista słowników nazwa grupy → waga."""
    names = {g.index: g.name for g in ob.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups} for v in ob.data.vertices]


def _ramp(x, a, b):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _finger_cuts(rig, side):
    """Końce rękawicy na palcach ręki `side` (poza spoczynkowa): punkt i normalna płaszczyzny cięcia (w poprzek członu bliższego, normalna
    ku koniuszkowi) oraz oś palca od nasady członu bliższego do koniuszka (wybór ścian palca)."""
    out = []
    for fg, t in FINGER_CUT.items():
        b0, b1 = ("Thumb2", "Thumb3") if fg == "Thumb" else (fg + "1", fg + "2")
        p0, p1 = _bone_head(rig, side + "Hand" + b0), _bone_head(rig, side + "Hand" + b1)
        tip = rig.matrix_world @ rig.data.bones[PRE + side + "Hand" + fg + "3"].tail_local
        out.append({"finger": fg, "p": p0.lerp(p1, t), "n": (p1 - p0).normalized(), "a0": p0, "a1": tip})
    return out


def _near_finger(c, cu, r=0.0135):
    return _seg_dist(c, cu["a0"], cu["a1"])[0] < r


def _cut_finger(bm, cu, keep, shift=0.0):
    """Cięcie palca płaszczyzną `cu` (przesuniętą o `shift` ku nasadzie): tylko ściany przy osi palca. `keep` = "hand" — zostaje dłoń
    (rękawica), "finger" — zostaje koniec palca (skóra)."""
    pc = cu["p"] - cu["n"] * shift
    near = [f for f in bm.faces if _near_finger(f.calc_center_median(), cu)]
    geom = list({v for f in near for v in f.verts}) + list({e for f in near for e in f.edges}) + near
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=pc, plane_no=cu["n"])
    sign = 1.0 if keep == "hand" else -1.0
    drop = [f for f in bm.faces if (f.calc_center_median() - pc).dot(cu["n"]) * sign > 0 and _near_finger(f.calc_center_median(), cu)]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def make_gloves(rig, body):
    """Rękawice z ciała: dla każdej ręki cała dłoń i przedramię do GLOVE_CUFF nad nadgarstkiem, odcięte jedną płaszczyzną prostopadłą do
    przedramienia (równy, okrągły mankiet; bez progów wag — wcześniej wybór ścian po wagach dziurawił grzbiet dłoni i rwał palce).
    Ściany ręki: każda, której choć jeden wierzchołek ma wagę kości tej ręki (ramię, przedramię, dłoń, palce) — bez nóg i tułowia.
    Potem odsunięcie od skóry (mankiet rozszerza się), podział i grubość skóry."""
    parts = []
    for side in ("Left", "Right"):
        g = body.copy()
        g.data = body.data.copy()
        g.name = "glove_" + side
        bpy.context.scene.collection.objects.link(g)
        for m in list(g.modifiers):
            if m.type != "ARMATURE":
                g.modifiers.remove(m)
        W = _weights(g)
        wr = _bone_head(rig, side + "Hand")
        el = _bone_head(rig, side + "ForeArm")
        d = (wr - el).normalized()                                  # od łokcia do nadgarstka
        arm = []
        for w in W:
            a_w = sum(x for n, x in w.items() if n.startswith(PRE + side) and ("Arm" in n or "Hand" in n))
            arm.append(w.get("body", 0.0) > 0.5 and a_w > 0.05)
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not any(arm[v.index] for v in f.verts)], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        cut = wr - d * GLOVE_CUFF
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=cut, plane_no=d, clear_inner=True)     # zostaje strona dłoni
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        # luźne kawałki (resztki tułowia za płaszczyzną) precz: zostaje największa spójna część
        seen = set()
        comps = []
        for f in bm.faces:
            if f.index in seen:
                continue
            stack = [f]
            comp = []
            seen.add(f.index)
            while stack:
                x = stack.pop()
                comp.append(x)
                for e in x.edges:
                    for y in e.link_faces:
                        if y.index not in seen:
                            seen.add(y.index)
                            stack.append(y)
            comps.append(comp)
        comps.sort(key=len, reverse=True)
        bmesh.ops.delete(bm, geom=[f for c in comps[1:] for f in c], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        cuts = _finger_cuts(rig, side)
        for cu in cuts:                                             # bez palców: każdy palec odcięty płaszczyzną w poprzek członu bliższego
            _cut_finger(bm, cu, keep="hand")
        bm.normal_update()
        for v in bm.verts:
            s_up = (wr - v.co).dot(d)                               # > 0: od nadgarstka w stronę łokcia
            t = min(max((s_up - 0.03) / (GLOVE_CUFF - 0.03), 0.0), 1.0) if s_up > 0 else 0.0
            hem = max((_ramp((v.co - cu["p"]).dot(cu["n"]), -HEM, 0.0) for cu in cuts if _near_finger(v.co, cu)), default=0.0)
            v.co += v.normal * (GLOVE_GAP + GLOVE_FLARE * t * t * (3 - 2 * t) + 0.0006 * hem)    # obszycie otworu — zgrubienie
        bm.to_mesh(g.data)
        bm.free()
        parts.append(g)
    bpy.ops.object.select_all(action="DESELECT")
    for g in parts:
        g.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "gloves"
    C._only(g)
    ss = g.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    ss.render_levels = 1
    while g.modifiers[0] != ss:
        bpy.ops.object.modifier_move_up(modifier=ss.name)
    bpy.ops.object.modifier_apply(modifier=ss.name)
    so = g.modifiers.new("so", "SOLIDIFY")
    so.thickness = GLOVE_THICK
    so.offset = -1.0
    so.use_rim = True
    while g.modifiers[0] != so:
        bpy.ops.object.modifier_move_up(modifier=so.name)
    bpy.ops.object.modifier_apply(modifier=so.name)
    for p in g.data.polygons:
        p.use_smooth = True
    print("GLOVES", len(g.data.polygons), "faces")
    return g


def _hand_rest(rig):
    """Układ każdej dłoni w pozie spoczynkowej: nadgarstek, f (ku palcom), a (linia kostek, mały → wskazujący), b (grzbiet), oś
    przedramienia (ku dłoni), linia stawów śródręczno-paliczkowych i pierwsze człony palców (nasada → staw międzypaliczkowy)."""
    out = {}
    for side in ("Left", "Right"):
        w, m = _bone_head(rig, side + "Hand"), _bone_head(rig, side + "HandMiddle1")
        f = (m - w).normalized()
        a = _bone_head(rig, side + "HandIndex1") - _bone_head(rig, side + "HandPinky1")
        a = (a - f * a.dot(f)).normalized()
        b = (f.cross(a) if side == "Right" else a.cross(f)).normalized()
        fa = (w - _bone_head(rig, side + "ForeArm")).normalized()
        segs = [(_bone_head(rig, side + "Hand%s1" % fg), _bone_head(rig, side + "Hand%s2" % fg)) for fg in ("Index", "Middle", "Ring", "Pinky")]
        out[side] = {"w": w, "f": f, "a": a, "b": b, "fa": fa, "mcp": (segs[0][0], segs[3][0]), "segs": segs}
    return out


def _seg_dist(p, p0, p1):
    """Odległość punktu od odcinka i parametr rzutu 0..1."""
    d = p1 - p0
    t = max(0.0, min(1.0, (p - p0).dot(d) / d.length_squared))
    return (p - (p0 + d * t)).length, t


def _vert_side(w):
    """Strona ręki wierzchołka z wag kości (MPFB: grupy „mixamorig:Left…” / „…Right…”)."""
    l = sum(x for n, x in w.items() if n.startswith(PRE + "Left"))
    r = sum(x for n, x in w.items() if n.startswith(PRE + "Right"))
    return "Left" if l >= r else "Right"


def _shell_frame(H, side):
    """Skorupa na kostkach ręki `side`: środek (nad linią stawów śródręczno-paliczkowych, lekko ku nadgarstkowi), osie u (w poprzek
    kostek), v (wzdłuż dłoni), n (grzbiet) i półosie A, B (m)."""
    h = H[side]
    k0, k1 = h["mcp"]
    b = h["b"]
    f = (h["f"] - b * h["f"].dot(b)).normalized()
    a = b.cross(f).normalized()
    return {"c": (k0 + k1) * 0.5 - f * 0.005, "u": a, "v": f, "n": b, "A": (k0 - k1).length * 0.5 + 0.0105, "B": 0.0135}


def glove_zones(g, rig):
    """Atrybuty rękawicy z pozy spoczynkowej do materiału: „zone” (R — grzbiet 0..1, G — obszycie otworu palca, B — nadgarstek i dalej)
    i „kf” (x, y — położenie w układzie skorupy na kostkach podzielone przez półosie, z — odległość wzdłuż dłoni w m: prążki i szwy
    liczone w materiale, ostre niezależnie od gęstości siatki). Grzbiet po normalnej względem grzbietu dłoni (dla kciuka obrócony
    ku stronie promieniowej — paznokieć kciuka patrzy w bok)."""
    H = _hand_rest(rig)
    cuts = {sd: _finger_cuts(rig, sd) for sd in H}
    fr = {sd: _shell_frame(H, sd) for sd in H}
    W = _weights(g)
    mw = g.matrix_world
    nm = mw.to_3x3()
    zone = g.data.color_attributes.new("zone", "FLOAT_COLOR", "POINT")
    kf = g.data.color_attributes.new("kf", "FLOAT_COLOR", "POINT")
    zv, kv = [], []
    for v, w in zip(g.data.vertices, W):
        sd = _vert_side(w)
        h, sh = H[sd], fr[sd]
        p, n = mw @ v.co, (nm @ v.normal).normalized()
        thumb = sum(x for k, x in w.items() if "Thumb" in k) > 0.4
        bd = (h["b"] + h["a"] * 0.9).normalized() if thumb else h["b"]
        back = min(max((n.dot(bd) + 0.15) / 0.3, 0.0), 1.0)
        su = (p - h["w"]).dot(h["fa"])                                # < 0 — w stronę łokcia
        wrist = min(max((-su - 0.002) / 0.004, 0.0), 1.0)
        hem = max(((1.0 if (p - cu["p"]).dot(cu["n"]) > -HEM else 0.0) for cu in cuts[sd] if _near_finger(p, cu)), default=0.0)
        q = p - sh["c"]
        zv += [back, hem, wrist, 1.0]
        kv += [q.dot(sh["u"]) / sh["A"], q.dot(sh["v"]) / sh["B"], q.dot(sh["v"]), 1.0]
    zone.data.foreach_set("color", zv)
    kf.data.foreach_set("color", kv)


def _node_kit(nt):
    """Drobne pomocniki węzłów materiału: działania, mieszanie, atrybuty, szum."""
    L = nt.links.new
    tc = nt.nodes.new("ShaderNodeTexCoord")

    def plug(sock, x):
        if isinstance(x, (int, float)):
            sock.default_value = x
        elif isinstance(x, tuple):
            sock.default_value = x + (1.0,) if len(x) == 3 else x
        else:
            L(x, sock)

    def m(op, a, b=None, clamp=False):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        plug(n.inputs[0], a)
        if b is not None:
            plug(n.inputs[1], b)
        return n.outputs[0]

    def mixf(fac, a, b):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        plug(n.inputs["Factor"], fac)
        plug(n.inputs["A"], a)
        plug(n.inputs["B"], b)
        return n.outputs["Result"]

    def mixc(fac, a, b, blend="MIX"):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        plug(n.inputs["Factor"], fac)
        plug(n.inputs["A"], a)
        plug(n.inputs["B"], b)
        return n.outputs["Result"]

    def attr(name):
        n = nt.nodes.new("ShaderNodeAttribute")
        n.attribute_name = name
        sx = nt.nodes.new("ShaderNodeSeparateXYZ")
        L(n.outputs["Vector"], sx.inputs[0])
        return sx.outputs[0], sx.outputs[1], sx.outputs[2]

    def noise(scale, detail=3.0):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        L(tc.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    def ramp(x, a, b):                                       # 0 przed a, 1 za b (liniowo)
        return m("DIVIDE", m("SUBTRACT", x, a), b - a, True)

    def line(x, at, w):                                      # 1 na linii x = at, 0 dalej niż w
        return m("SUBTRACT", 1.0, m("DIVIDE", m("ABSOLUTE", m("SUBTRACT", x, at)), w), True)

    def ribs(x, period):                                     # prążki 0..1
        return m("ADD", m("MULTIPLY", m("SINE", m("MULTIPLY", x, 2.0 * math.pi / period)), 0.5), 0.5)

    def bump(h, strength, dist):
        n = nt.nodes.new("ShaderNodeBump")
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = dist
        plug(n.inputs["Height"], h)
        return n.outputs["Normal"]

    return {"L": L, "m": m, "mixf": mixf, "mixc": mixc, "attr": attr, "noise": noise, "ramp": ramp, "line": line, "ribs": ribs,
            "bump": bump, "plug": plug}


def _principled(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, nt, bsdf


def glove_material(name):
    """Rękawica bez palców: wnętrze dłoni z zamszu, na grzbiecie zamszowa obwódka skorupy (dwa szwy) i zamsz na palcach, między nią
    a nadgarstkiem elastyczna tkanina w poprzeczne prążki, obszycie otworów palców w prążki, szew grzbiet / wnętrze. Panele i szwy
    z atrybutów „zone” i „kf” (glove_zones)."""
    mat, nt, bsdf = _principled(name)
    K = _node_kit(nt)
    m, mixf, mixc, ramp, line = K["m"], K["mixf"], K["mixc"], K["ramp"], K["line"]
    back, hem, wrist = K["attr"]("zone")
    x, y, z = K["attr"]("kf")
    se = m("POWER", m("ADD", m("POWER", m("ABSOLUTE", x), 4.0), m("POWER", m("ABSOLUTE", y), 4.0)), 0.25)    # superelipsa skorupy
    ring = m("SUBTRACT", 1.0, ramp(se, 1.30, 1.36))          # zamszowa obwódka
    fingers = ramp(y, 0.95, 1.10)                            # grzbiet palców (za kostkami)
    suede_back = m("MAXIMUM", ring, fingers)
    rib_back = m("MULTIPLY", m("SUBTRACT", 1.0, suede_back), back)
    rib_any = m("MAXIMUM", m("MAXIMUM", rib_back, wrist), hem)
    th = m("ARCTAN2", y, x)
    dash = m("GREATER_THAN", m("SINE", m("MULTIPLY", th, 140.0)), -0.3)
    stitch = m("MULTIPLY", m("MAXIMUM", line(se, 1.09, 0.028), line(se, 1.33, 0.028)), m("MULTIPLY", dash, back))
    seam = m("SUBTRACT", 1.0, m("MULTIPLY", m("ABSOLUTE", m("SUBTRACT", back, 0.5)), 9.0), True)
    hemline = m("MULTIPLY", hem, m("SUBTRACT", 1.0, wrist))
    rib = K["ribs"](z, 0.0021)
    suede_n = K["noise"](1100.0, 4.0)
    c = mixc(back, OLIVE_PALM, OLIVE_SUEDE)
    c = mixc(rib_back, c, OLIVE_RIB)
    c = mixc(m("MULTIPLY", wrist, 1.0), c, OLIVE_RIB)
    c = mixc(hemline, c, OLIVE_BIND)
    c = mixc(m("MAXIMUM", stitch, m("MULTIPLY", seam, 0.8)), c, OLIVE_STITCH)
    tint = nt.nodes.new("ShaderNodeMix")                     # plamy (kurz, olej)
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 0.22
    K["L"](c, tint.inputs["A"])
    mot = nt.nodes.new("ShaderNodeTexNoise")
    mot.inputs["Scale"].default_value = 30.0
    K["L"](nt.nodes["Texture Coordinate"].outputs["Object"], mot.inputs["Vector"])
    K["L"](mot.outputs["Color"], tint.inputs["B"])
    K["L"](tint.outputs["Result"], bsdf.inputs["Base Color"])
    K["plug"](bsdf.inputs["Roughness"], mixf(rib_any, 0.93, 0.82))
    h = mixf(rib_any, m("MULTIPLY", suede_n, 0.5), rib)
    h = m("ADD", h, m("MULTIPLY", stitch, 0.7))
    h = m("SUBTRACT", h, m("MULTIPLY", seam, 0.9))
    K["L"](K["bump"](h, 0.6, 0.0004), bsdf.inputs["Normal"])
    return mat


def shell_material(name):
    """Skorupa na kostkach i nakładki palców: formowane TPU, czarnooliwkowe, półmatowe, drobne ziarno formy."""
    mat, nt, bsdf = _principled(name)
    K = _node_kit(nt)
    K["plug"](bsdf.inputs["Base Color"], SHELL_PLASTIC)
    K["plug"](bsdf.inputs["Roughness"], K["mixf"](K["noise"](90.0), 0.36, 0.5))
    K["L"](K["bump"](K["noise"](900.0, 2.0), 0.25, 0.0002), bsdf.inputs["Normal"])
    return mat


def strap_material(name):
    """Pasek na rzep: taśma nylonowa (drobne prążki wzdłuż paska), ciemniejsze lamówki na brzegach, na końcu paska (patka) prostokąt
    z krzyżem — szew mocujący. Położenie z atrybutu „sc” (u — wzdłuż obwodu od wolnej krawędzi, v — w poprzek paska, z — patka)."""
    mat, nt, bsdf = _principled(name)
    K = _node_kit(nt)
    m, ramp, line = K["m"], K["ramp"], K["line"]
    u, v, tab = K["attr"]("sc")
    half = (STRAP_SPAN[1] - STRAP_SPAN[0]) * 0.5
    edge = ramp(m("ABSOLUTE", v), half - 0.0035, half - 0.0025)
    bu0, bu1, bv = 0.004, 0.024, half - 0.0055                # prostokąt szwu na patce
    inu = m("MULTIPLY", m("GREATER_THAN", u, bu0 - 0.0004), m("LESS_THAN", u, bu1 + 0.0004))
    inv = m("LESS_THAN", m("ABSOLUTE", v), bv + 0.0004)
    w = 0.00045
    box = m("MAXIMUM", m("MAXIMUM", line(u, bu0, w), line(u, bu1, w)), line(m("ABSOLUTE", v), bv, w))
    du = m("DIVIDE", m("SUBTRACT", u, (bu0 + bu1) * 0.5), (bu1 - bu0) * 0.5)
    dv = m("DIVIDE", v, bv)
    diag = m("MAXIMUM", line(m("SUBTRACT", du, dv), 0.0, 0.05), line(m("ADD", du, dv), 0.0, 0.05))
    dash = m("GREATER_THAN", m("SINE", m("MULTIPLY", m("ADD", u, v), 2.0 * math.pi / 0.0028)), -0.4)
    stitch = m("MULTIPLY", m("MULTIPLY", m("MAXIMUM", box, diag), m("MULTIPLY", inu, inv)), m("MULTIPLY", tab, dash))
    web = K["ribs"](v, 0.0009)
    c = K["mixc"](edge, STRAP_WEB, OLIVE_BIND)
    c = K["mixc"](stitch, c, OLIVE_STITCH)
    K["L"](c, bsdf.inputs["Base Color"])
    K["plug"](bsdf.inputs["Roughness"], 0.8)
    h = m("ADD", m("MULTIPLY", web, 0.6), m("SUBTRACT", m("MULTIPLY", stitch, 0.8), m("MULTIPLY", edge, 0.3)))
    K["L"](K["bump"](h, 0.6, 0.0003), bsdf.inputs["Normal"])
    return mat


def _molded(name, bvh, center, ax_u, ax_v, nrm, A, B, n_exp, t_center, t_edge, bumps=(), rings=9, segs=72):
    """Formowana nakładka dopasowana do rękawicy: zarys superelipsy (półosie A, B, wykładnik n_exp) w płaszczyźnie (ax_u, ax_v) rzutowany
    wzdłuż `nrm` na powierzchnię rękawicy (`bvh`), spód tuż nad tkaniną, wierzch wyżej o profil kopuły (t_center → t_edge na brzegu)
    plus garby `bumps` (u, v, wysokość, σu, σv). Zamknięta bryła (wierzch, spód, ścianka brzegu)."""
    def surf(u, v):
        p = center + ax_u * u + ax_v * v
        hit = bvh.ray_cast(p + nrm * 0.04, -nrm, 0.08)
        if hit[0] is None:
            return p, nrm
        nn = hit[1].normalized()
        return hit[0], (nn if nn.dot(nrm) > 0 else -nn)

    def height(u, v, r):
        hgt = t_edge + (t_center - t_edge) * (1.0 - r ** 4)
        for bu, bv, amp, su, sv in bumps:
            hgt += amp * math.exp(-((u - bu) / su) ** 2 - ((v - bv) / sv) ** 2) * (1.0 - r ** 6)
        return hgt

    bm = bmesh.new()
    sp, sn = surf(0.0, 0.0)
    top0 = bm.verts.new(sp + sn * (SHELL_GAP + height(0.0, 0.0, 0.0)))
    bot0 = bm.verts.new(sp + sn * SHELL_GAP * 0.5)
    top, bot = [], []
    for i in range(1, rings + 1):
        r = i / rings
        tr, br = [], []
        for j in range(segs):
            th = 2.0 * math.pi * j / segs
            c, sn_ = math.cos(th), math.sin(th)
            u = A * r * math.copysign(abs(c) ** (2.0 / n_exp), c)
            v = B * r * math.copysign(abs(sn_) ** (2.0 / n_exp), sn_)
            p, n = surf(u, v)
            tr.append(bm.verts.new(p + n * (SHELL_GAP + height(u, v, r))))
            br.append(bm.verts.new(p + n * SHELL_GAP * 0.5))
        top.append(tr)
        bot.append(br)
    for j in range(segs):
        k = (j + 1) % segs
        bm.faces.new((top0, top[0][j], top[0][k]))
        bm.faces.new((bot0, bot[0][k], bot[0][j]))
        for i in range(rings - 1):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][k], top[i][k]))
            bm.faces.new((bot[i][k], bot[i + 1][k], bot[i + 1][j], bot[i][j]))
        bm.faces.new((top[-1][j], bot[-1][j], bot[-1][k], top[-1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _bind_to(ob, rig, src):
    """Wagi kości z obiektu `src` (najbliższa ściana, interpolowane) i modyfikator szkieletu — nakładka rusza się jak tkanina pod nią."""
    C._only(ob)
    dt = ob.modifiers.new("dt", "DATA_TRANSFER")
    dt.object = src
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    ob.parent = rig
    ob.matrix_parent_inverse = rig.matrix_world.inverted()
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = rig


def make_pads(rig, gloves):
    """Twarde części rękawic: skorupa na kostkach (jedna formowana płyta z czterema garbami nad stawami śródręczno-paliczkowymi) i owalne
    nakładki na pierwszych członach palców (bez kciuka) — dopasowane do grzbietu rękawicy w pozie spoczynkowej, wagi z rękawicy."""
    H = _hand_rest(rig)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = gloves.evaluated_get(dg)
    me = ev.to_mesh()
    mw = gloves.matrix_world
    bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])
    ev.to_mesh_clear()
    parts = []
    for side, h in H.items():
        sh = _shell_frame(H, side)
        bumps = []
        for p0, _ in h["segs"]:
            q = p0 - sh["c"]
            bumps.append((q.dot(sh["u"]), q.dot(sh["v"]), 0.0026, 0.0060, 0.0095))
        parts.append(_molded("shell_" + side, bvh, sh["c"], sh["u"], sh["v"], sh["n"], sh["A"], sh["B"], 4.0, 0.0030, 0.0011, bumps))
        for (p0, p1), fg in zip(h["segs"], ("Index", "Middle", "Ring", "Pinky")):
            d = (p1 - p0).normalized()
            bf = (h["b"] - d * h["b"].dot(d)).normalized()
            k = (p1 - p0).length / 0.029
            parts.append(_molded("pad_%s_%s" % (side, fg), bvh, p0.lerp(p1, 0.40), bf.cross(d).normalized(), d, bf,
                                 0.0056 * min(k, 1.1), 0.0062 * k, 2.4, 0.0022, 0.0008, rings=5, segs=32))
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    pads = bpy.context.active_object
    pads.name = "glove_pads"
    C._only(pads)
    ss = pads.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    bpy.ops.object.modifier_apply(modifier=ss.name)
    for p in pads.data.polygons:
        p.use_smooth = True
    _bind_to(pads, rig, gloves)
    print("PADS", len(pads.data.polygons), "faces")
    return pads


def make_strap(rig, body):
    """Pasek na rzep na nadgarstku: pierścień z ciała między dwiema płaszczyznami prostopadłymi do przedramienia (STRAP_SPAN), odsunięty
    nad rękawicę, z patką — koniec paska nachodzi na pasek na grzbiecie nadgarstka (wolna krawędź wzdłuż przedramienia, stopień
    grubości). Atrybut „sc” do szwu na patce."""
    H = _hand_rest(rig)
    parts = []
    frames = {}
    for side in ("Left", "Right"):
        g = body.copy()
        g.data = body.data.copy()
        g.name = "strap_" + side
        bpy.context.scene.collection.objects.link(g)
        for md in list(g.modifiers):
            if md.type != "ARMATURE":
                g.modifiers.remove(md)
        W = _weights(g)
        wr = _bone_head(rig, side + "Hand")
        d = (wr - _bone_head(rig, side + "ForeArm")).normalized()
        arm = [w.get("body", 0.0) > 0.5 and sum(x for n, x in w.items() if n.startswith(PRE + side) and ("Arm" in n or "Hand" in n)) > 0.05
               for w in W]
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not any(arm[v.index] for v in f.verts)], context="FACES")
        for off, clear in ((STRAP_SPAN[0], "outer"), (STRAP_SPAN[1], "inner")):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=wr - d * off, plane_no=d,
                                   clear_outer=clear == "outer", clear_inner=clear == "inner")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        comps, seen = [], set()
        for f in bm.faces:
            if f.index in seen:
                continue
            stack, comp = [f], []
            seen.add(f.index)
            while stack:
                x = stack.pop()
                comp.append(x)
                for e in x.edges:
                    for y in e.link_faces:
                        if y.index not in seen:
                            seen.add(y.index)
                            stack.append(y)
            comps.append(comp)
        comps.sort(key=len, reverse=True)
        bmesh.ops.delete(bm, geom=[f for c in comps[1:] for f in c], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        # wolna krawędź patki: płaszczyzna przez oś przedramienia, tylko na grzbiecie (jedno cięcie), krawędzie rozdzielone
        o = wr - d * (STRAP_SPAN[0] + STRAP_SPAN[1]) * 0.5
        e1 = (H[side]["b"] - d * H[side]["b"].dot(d)).normalized()
        e2 = d.cross(e1)
        if side == "Left":
            e2 = -e2
        phi0 = math.radians(-35.0)
        r0 = e1 * math.cos(phi0) + e2 * math.sin(phi0)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=o, plane_no=d.cross(r0))
        cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and all((v.co - o).dot(r0) > 0 for v in e.verts)]
        bmesh.ops.split_edges(bm, edges=cut_edges)
        bm.normal_update()

        def phi_of(p):
            q = p - o
            return math.atan2(q.dot(e2), q.dot(e1)) - phi0

        for v in bm.verts:
            ph = phi_of(sum((f.calc_center_median() for f in v.link_faces), Vector()) / max(len(v.link_faces), 1))
            ph = (ph + math.pi) % (2.0 * math.pi) - math.pi
            lift = 0.0017 * (1.0 - _ramp(ph, math.radians(55.0), math.radians(85.0))) if ph > 0 else 0.0
            v.co += v.normal * (GLOVE_GAP + GLOVE_THICK + 0.0008 + lift)
        bm.to_mesh(g.data)
        bm.free()
        frames[side] = (o, e1, e2, phi0, d)
        parts.append(g)
    bpy.ops.object.select_all(action="DESELECT")
    for g in parts:
        g.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    st = bpy.context.active_object
    st.name = "glove_strap"
    C._only(st)
    ss = st.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    so = st.modifiers.new("so", "SOLIDIFY")
    so.thickness = 0.0022
    so.offset = 1.0
    so.use_rim = True
    for md in (ss, so):
        while st.modifiers[0] != md:
            bpy.ops.object.modifier_move_up(modifier=md.name)
        bpy.ops.object.modifier_apply(modifier=md.name)
    for p in st.data.polygons:
        p.use_smooth = True
    # „sc”: u — łuk od wolnej krawędzi patki (m), v — w poprzek paska (m), z — patka (0/1)
    W = _weights(st)
    attr = st.data.color_attributes.new("sc", "FLOAT_COLOR", "POINT")
    vals = []
    for v, w in zip(st.data.vertices, W):
        o, e1, e2, phi0, d = frames[_vert_side(w)]
        q = st.matrix_world @ v.co - o
        ph = (math.atan2(q.dot(e2), q.dot(e1)) - phi0 + math.pi) % (2.0 * math.pi) - math.pi
        rad = (q - d * q.dot(d)).length
        vals += [ph * rad, q.dot(d), 1.0 if 0.0 < ph < math.radians(75.0) else 0.0, 1.0]
    attr.data.foreach_set("color", vals)
    print("STRAP", len(st.data.polygons), "faces")
    return st


def make_finger_skin(rig, body):
    """Palce wystające z rękawic: skóra ciała (z teksturą skóry MPFB — paznokcie, zmarszczki stawów) od SKIN_UNDER pod brzegiem rękawicy
    do koniuszków; wagi i szkielet z ciała."""
    parts = []
    for side in ("Left", "Right"):
        g = body.copy()
        g.data = body.data.copy()
        g.name = "skin_" + side
        bpy.context.scene.collection.objects.link(g)
        for md in list(g.modifiers):
            if md.type != "ARMATURE":
                g.modifiers.remove(md)
        cuts = _finger_cuts(rig, side)
        bm = bmesh.new()
        bm.from_mesh(g.data)
        keep = set()
        for cu in cuts:
            for f in bm.faces:
                c = f.calc_center_median()
                if _near_finger(c, cu) and (c - cu["p"]).dot(cu["n"]) > -SKIN_UNDER - 0.006:
                    keep.add(f)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        for cu in cuts:
            _cut_finger(bm, cu, keep="finger", shift=SKIN_UNDER)
        bm.to_mesh(g.data)
        bm.free()
        parts.append(g)
    bpy.ops.object.select_all(action="DESELECT")
    for g in parts:
        g.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    sk = bpy.context.active_object
    sk.name = "hand_skin"
    C._only(sk)
    ss = sk.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    while sk.modifiers[0] != ss:
        bpy.ops.object.modifier_move_up(modifier=ss.name)
    bpy.ops.object.modifier_apply(modifier=ss.name)
    for p in sk.data.polygons:
        p.use_smooth = True
    print("SKIN", len(sk.data.polygons), "faces")
    return sk


def bake_skin(ob, size, prefix):
    """Wypiek koloru skóry MPFB (obraz na UV ciała) na nowe UV palców + drobne pory i zmarszczki w mapie normalnych; materiał z obrazów."""
    me = ob.data
    src = me.uv_layers.active
    src_name = src.name
    mat = ob.data.materials[0].copy()
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    nt = mat.node_tree
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = src_name
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for n in nt.nodes:
        if n.type == "TEX_IMAGE":
            nt.links.new(uvn.outputs["UV"], n.inputs["Vector"])
    K = _node_kit(nt)
    h = K["m"]("ADD", K["m"]("MULTIPLY", K["noise"](2600.0, 3.0), 0.6), K["m"]("MULTIPLY", K["noise"](320.0, 2.0), 0.4))
    K["L"](K["bump"](h, 0.25, 0.0002), bsdf.inputs["Normal"])
    new = me.uv_layers.new(name="bake")
    me.uv_layers.active = new
    C._only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    imgs = {}
    for key, kind, nonc in (("albedo", "DIFFUSE", False), ("normal", "NORMAL", True)):
        img = bpy.data.images.new("%s_%s" % (prefix, key), size, size, alpha=False)
        if nonc:
            img.colorspace_settings.name = "Non-Color"
        C._bake_target(ob, img)
        kw = {"type": kind}
        if kind == "DIFFUSE":
            kw["pass_filter"] = {"COLOR"}
        C._bake(**kw)
        imgs[key] = img
    C._drop_target(ob)
    a = np.array(imgs["albedo"].pixels[:]).reshape(-1, 4)       # ciemniej i cieplej: blada skóra MPFB w ciepłym świetle strzelnicy
    a[:, :3] *= SKIN_TONE                                       # wychodziła prawie biała
    imgs["albedo"].pixels.foreach_set(a.astype(np.float32).ravel())
    me.uv_layers.remove(me.uv_layers[src_name])
    m = bpy.data.materials.new(prefix)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = imgs["albedo"]
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = imgs["normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.55
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for img in imgs.values():
        img.pack()


def bake_object(ob, size, prefix):
    """Wypiek materiału proceduralnego do tekstur (kolor, szorstkość, normalne, okluzja) i materiał z obrazów."""
    C._only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    imgs = {}
    for key, kind, nonc in (("albedo", "DIFFUSE", False), ("rough", "ROUGHNESS", True), ("normal", "NORMAL", True), ("ao", "AO", True)):
        img = bpy.data.images.new("%s_%s" % (prefix, key), size, size, alpha=False)
        if nonc:
            img.colorspace_settings.name = "Non-Color"
        C._bake_target(ob, img)
        kw = {"type": kind}
        if kind == "DIFFUSE":
            kw["pass_filter"] = {"COLOR"}
        C._bake(**kw)
        imgs[key] = img
    C._drop_target(ob)
    # okluzja wmnożona w kolor (głębokie zgięcia palców, wnętrze mankietu)
    a = np.array(imgs["albedo"].pixels[:]).reshape(-1, 4)
    o = np.array(imgs["ao"].pixels[:]).reshape(-1, 4)
    a[:, :3] *= 0.7 + 0.3 * o[:, :3]                               # łagodnie: mocna okluzja dawała ciemne plamy na grzbiecie dłoni
    imgs["albedo"].pixels.foreach_set(a.astype(np.float32).ravel())
    m = bpy.data.materials.new(prefix)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = imgs["albedo"]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    r = nt.nodes.new("ShaderNodeTexImage")
    r.image = imgs["rough"]
    nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = imgs["normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.0
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for img in imgs.values():
        img.pack()
    bpy.data.images.remove(imgs["ao"])


def make_watch(rig, gloves):
    """Zegarek na lewym nadgarstku, na mankiecie rękawicy (koperta 38 mm, szkło, pasek parciany), sztywno na przedramieniu."""
    wr = _bone_head(rig, "LeftHand")
    el = _bone_head(rig, "LeftForeArm")
    d = (wr - el).normalized()
    c = wr - d * 0.053                                       # 5,3 cm nad nadgarstkiem — nad paskiem na rzep rękawicy
    # promień nadgarstka z rękawicy (najdalszy punkt przekroju)
    rs = [((v.co - c) - d * (v.co - c).dot(d)).length for v in gloves.data.vertices if abs((v.co - c).dot(d)) < 0.006 and (v.co - c).length < 0.08]
    r = (max(rs) if rs else 0.03) + 0.0015
    up = Vector((0, 0, 1))
    back = (up - d * up.dot(d)).normalized()                 # grzbiet przedramienia w A-pozie (z góry)
    side = d.cross(back)
    bm = bmesh.new()
    n = 40
    w = 0.02
    ring = []
    for i in range(n):                                       # pasek: pierścień eliptyczny (nadgarstek jest płaski)
        a = 2 * math.pi * i / n
        p = c + (back * math.cos(a) * r * 0.92 + side * math.sin(a) * r * 1.12)
        ring.append((bm.verts.new(p - d * w / 2), bm.verts.new(p + d * w / 2)))
    for i in range(n):
        a0, b0 = ring[i]
        a1, b1 = ring[(i + 1) % n]
        bm.faces.new((a0, a1, b1, b0))
    strap = bpy.data.objects.new("watch_strap", bpy.data.meshes.new("watch_strap"))
    bm.to_mesh(strap.data)
    bm.free()
    bpy.context.scene.collection.objects.link(strap)
    so = strap.modifiers.new("so", "SOLIDIFY")
    so.thickness = 0.0022
    C._only(strap)
    bpy.ops.object.modifier_apply(modifier=so.name)
    # koperta i szkło na grzbiecie
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.019, depth=0.009, location=c + back * (r * 0.92 + 0.004))
    case = bpy.context.active_object
    case.name = "watch_case"
    case.rotation_mode = "QUATERNION"
    case.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(back)
    bv = case.modifiers.new("bv", "BEVEL")
    bv.width = 0.0015
    bv.segments = 3
    bpy.ops.object.modifier_apply(modifier=bv.name)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.0155, depth=0.002, location=c + back * (r * 0.92 + 0.0088))
    glass = bpy.context.active_object
    glass.name = "watch_glass"
    glass.rotation_mode = "QUATERNION"
    glass.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(back)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    def mat(name, rgb, rough, metal=0.0, emit=None, emit_strength=0.6):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = rgb + (1.0,)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if emit:
            b.inputs["Emission Color"].default_value = emit + (1.0,)
            b.inputs["Emission Strength"].default_value = emit_strength
        return m
    strap.data.materials.append(mat("watch_strap", (0.10, 0.11, 0.07), 0.9))
    case.data.materials.append(mat("watch_case", (0.55, 0.55, 0.52), 0.35, 1.0))
    glass.data.materials.append(mat("watch_face", (0.02, 0.025, 0.02), 0.08, 0.0, (0.25, 0.55, 0.3), 0.05))   # ciemna tarcza, ślad fosforu
    # (przy 0,6 cała tarcza świeciła jak zielony krążek tuż przy kamerze)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (strap, case, glass):
        o.select_set(True)
    bpy.context.view_layer.objects.active = case
    bpy.ops.object.join()
    watch = bpy.context.active_object
    watch.name = "watch"
    watch.parent = rig
    watch.matrix_parent_inverse = rig.matrix_world.inverted()
    vg = watch.vertex_groups.new(name=PRE + "LeftForeArm")
    vg.add(list(range(len(watch.data.vertices))), 1.0, "REPLACE")
    am = watch.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    for p in watch.data.polygons:
        p.use_smooth = True
    print("WATCH r=%.3f" % r)
    return watch


def build(outfit):
    spec = C.OUTFITS[outfit]
    rig, body = make_body(spec)
    gi = body.vertex_groups["body"].index
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    k = spec["height"] / (max(zs) - min(zs))
    floor = min(zs)
    sleeves = C.add_sewn(rig, body, spec, {"sleeves": {"file": "%s_m65_fp.glb" % outfit}})
    sl = bpy.data.objects.get("sleeves")
    if sl is not None:                                         # grubość tkaniny: z oka widać krawędź mankietu (bez niej — prześwit i „szarpana” krawędź)
        C._only(sl)
        so = sl.modifiers.new("so", "SOLIDIFY")
        so.thickness = SLEEVE_THICK
        so.offset = -1.0
        so.use_rim = True
        while sl.modifiers[0] != so:
            bpy.ops.object.modifier_move_up(modifier=so.name)
        bpy.ops.object.modifier_apply(modifier=so.name)
    gloves = make_gloves(rig, body)
    gloves.parent = rig
    glove_zones(gloves, rig)
    pads = make_pads(rig, gloves)
    strap = make_strap(rig, body)
    skin = make_finger_skin(rig, body)
    C._cycles(SAMPLES)
    gloves.data.materials.clear()
    gloves.data.materials.append(glove_material("glove_olive"))
    bake_object(gloves, GLOVE_TEX, "glove")
    pads.data.materials.clear()
    pads.data.materials.append(shell_material("glove_shell"))
    bake_object(pads, 1024, "glovepad")
    strap.data.materials.clear()
    strap.data.materials.append(strap_material("glove_strap"))
    bake_object(strap, 1024, "glovestrap")
    bake_skin(skin, 1024, "handskin")
    watch = make_watch(rig, gloves)
    bpy.data.objects.remove(body)
    for o in [o for o in rig.children if o.type == "MESH" and o.name not in ("gloves", "glove_pads", "glove_strap", "hand_skin", "sleeves", "watch")]:
        bpy.data.objects.remove(o)
    # orientacja i skala jak char_mpfb.build (przód +X, wzrost, stopy na z = 0)
    rig.location.z -= floor
    rig.rotation_euler = (0.0, 0.0, math.radians(90.0))
    rig.scale = (k, k, k)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig] + list(rig.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    per = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in rig.children if o.type == "MESH"}
    print("TRIS", sum(per.values()), per, "BONES", len(rig.data.bones))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, "fp_arms_%s.glb" % outfit.split("_", 1)[1])
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="WEBP", export_image_quality=90,
                              export_animations=False, export_apply=False, export_morph=False)
    print("OK", dst)
    os.makedirs(WORK, exist_ok=True)                           # źródło dla fp_grip.py (chwyty i animacje broni)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "fp_arms_%s.blend" % outfit.split("_", 1)[1]))


for n in [a for a in argv if not a.startswith("--")]:
    build(n)
