"""Bloki `M` (FOREGROUND_PLAN F3, 1.7.526): betonowe bloki prefabrykowane z czopami („lego”) i obudowa transformatora — modele z wypiekiem PBR.

Uruchomienie: blender -b --factory-startup -P prototype/tools/mblock_bake.py -- [--only=mblock_a0,mblock_c] [--tex=1024] [--samples=N]
Wynik: prototype/art/items3d/mblock_a0.glb, mblock_a1.glb (pełny blok, dwa warianty wyszczerbień i plam), mblock_ah.glb (pół bloku),
mblock_c.glb (obudowa transformatora na blok 2×2 kafle w podziemnych halach). Jednostka = 1 piksel świata gry (kafel = 16), stopy w z = 0,
środek szerokości w x = 0, czoło ku −Y (jak `prep_items3d.py`).

Bloki betonowe: bryła wysokiej rozdzielczości (zaokrąglone krawędzie, czopy z siatki wokselowej, wyszczerbienia krawędzi i pory z szumu
przesuwającego wierzchołki do środka) → uproszczona siatka gry; normalne, okluzja, kolor i chropowatość wypalane z bryły wysokiej na niską
(selected to active). Obudowa: części z fazowaniem, wypiek na siebie. Materiały: tekstury CC0 z Poly Haven rzutowane pudełkowo
(`art_src/world/polyhaven/tex/`: concrete_wall_006, green_metal_rust, rusty_metal_02 — kolor, chropowatość, wysokość jako bump) + maski:
odpryski (świeży, jaśniejszy beton), zużycie krawędzi (węzeł Bevel), brud w zagłębieniach (AO), błoto przy ziemi, zacieki wody i rdzy.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_src", "world", "polyhaven", "tex")
OUT = os.path.join(ROOT, "prototype", "art", "items3d")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
ONLY = set(OPT["only"].split(",")) if "only" in OPT else set()
TEX = int(OPT.get("tex", "1024"))
SAMPLES = int(OPT.get("samples", "0"))

# wymiary bloku (px): długość 2u, głębokość u, korpus HB + czopy STUD_H = u (u = pół kafla, 0,65 m — proporcje bloków 1,6 × 0,8 × 0,8 m)
U = 8.0
HB = 7.3
STUD_H = U - HB
STUD_R = 1.55


def srgb(r, g, b):
    f = lambda c: ((c / 255.0 + 0.055) / 1.055) ** 2.4 if c / 255.0 > 0.04045 else c / 255.0 / 12.92
    return (f(r), f(g), f(b), 1.0)


# ------------------------------------------------------------------ węzły

class G:
    """Mały pomocnik do budowy drzew węzłów materiału."""

    def __init__(self, m):
        self.nt = m.node_tree
        self.N = self.nt.nodes
        self.L = self.nt.links

    def n(self, kind, **props):
        nd = self.N.new(kind)
        for k, v in props.items():
            setattr(nd, k, v)
        return nd

    def link(self, a, b):
        self.L.new(a, b)

    def val(self, sock, v):
        if hasattr(sock, "default_value"):
            sock.default_value = v

    def math(self, op, a, b=None, clamp=False):
        nd = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                nd.inputs[i].default_value = x
            else:
                self.link(x, nd.inputs[i])
        return nd.outputs[0]

    def mix(self, fac, a, b, blend="MIX"):
        nd = self.n("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_result=True)
        for idx, x in ((0, fac), (6, a), (7, b)):
            if isinstance(x, (int, float)):
                nd.inputs[idx].default_value = x
            elif isinstance(x, tuple):
                nd.inputs[idx].default_value = x
            else:
                self.link(x, nd.inputs[idx])
        return nd.outputs[2]

    def mixf(self, fac, a, b):
        nd = self.n("ShaderNodeMix", data_type="FLOAT", clamp_factor=True)
        for idx, x in ((0, fac), (2, a), (3, b)):
            if isinstance(x, (int, float)):
                nd.inputs[idx].default_value = x
            else:
                self.link(x, nd.inputs[idx])
        return nd.outputs[0]

    def mrange(self, v, a, b, c=0.0, d=1.0):
        nd = self.n("ShaderNodeMapRange", clamp=True)
        self.link(v, nd.inputs["Value"])
        nd.inputs["From Min"].default_value = a
        nd.inputs["From Max"].default_value = b
        nd.inputs["To Min"].default_value = c
        nd.inputs["To Max"].default_value = d
        return nd.outputs["Result"]

    def coord(self, scale=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0)):
        tc = self.n("ShaderNodeTexCoord")
        mp = self.n("ShaderNodeMapping")
        self.link(tc.outputs["Object"], mp.inputs["Vector"])
        mp.inputs["Scale"].default_value = scale
        mp.inputs["Location"].default_value = loc
        mp.inputs["Rotation"].default_value = rot
        return mp.outputs["Vector"]

    def img(self, path, vec, color=True, blend=0.3):
        im = bpy.data.images.load(path, check_existing=True)
        if not color:
            im.colorspace_settings.name = "Non-Color"
        t = self.n("ShaderNodeTexImage", projection="BOX", projection_blend=blend, interpolation="Cubic")
        t.image = im
        self.link(vec, t.inputs["Vector"])
        return t

    def noise(self, vec, scale, detail=6.0, rough=0.55, dist=0.0):
        nd = self.n("ShaderNodeTexNoise")
        self.link(vec, nd.inputs["Vector"])
        nd.inputs["Scale"].default_value = scale
        nd.inputs["Detail"].default_value = detail
        nd.inputs["Roughness"].default_value = rough
        nd.inputs["Distortion"].default_value = dist
        return nd.outputs["Fac"]

    def geo(self):
        return self.n("ShaderNodeNewGeometry")

    def edge(self, radius):
        """Maska wypukłych krawędzi: różnica normalnej zaokrąglonej (węzeł Bevel) i prawdziwej."""
        bv = self.n("ShaderNodeBevel", samples=8)
        bv.inputs["Radius"].default_value = radius
        g = self.geo()
        dp = self.n("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        self.link(bv.outputs["Normal"], dp.inputs[0])
        self.link(g.outputs["Normal"], dp.inputs[1])
        return self.math("SUBTRACT", 1.0, dp.outputs["Value"])

    def ao(self, dist, inside=False):
        nd = self.n("ShaderNodeAmbientOcclusion", samples=16, only_local=True, inside=inside)
        nd.inputs["Distance"].default_value = dist
        return nd.outputs["AO"]

    def zpos(self):
        tc = self.n("ShaderNodeTexCoord")
        sx = self.n("ShaderNodeSeparateXYZ")
        self.link(tc.outputs["Object"], sx.inputs["Vector"])
        return sx

    def nz(self):
        g = self.geo()
        sx = self.n("ShaderNodeSeparateXYZ")
        self.link(g.outputs["Normal"], sx.inputs["Vector"])
        return sx.outputs["Z"]

    def bump(self, h, strength, dist, normal=None):
        bp = self.n("ShaderNodeBump")
        bp.inputs["Strength"].default_value = strength
        bp.inputs["Distance"].default_value = dist
        self.link(h, bp.inputs["Height"])
        if normal is not None:
            self.link(normal, bp.inputs["Normal"])
        return bp.outputs["Normal"]


def finish_mat(m, g, alb, rough, metal, nrm):
    """Wyjścia przebiegów: albedo / chropowatość / metal jako Emission, normalne przez Principled. `m["pass"]` przełącza `set_pass`."""
    bsdf = g.n("ShaderNodeBsdfPrincipled")
    g.link(alb, bsdf.inputs["Base Color"])
    for sock, v in ((bsdf.inputs["Roughness"], rough), (bsdf.inputs["Metallic"], metal)):
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            g.link(v, sock)
    if nrm is not None:
        g.link(nrm, bsdf.inputs["Normal"])
    em = g.n("ShaderNodeEmission")
    out = g.n("ShaderNodeOutputMaterial")
    mats_sockets[m.name] = {"alb": alb, "rough": rough, "metal": metal, "nodes": (bsdf.name, em.name, out.name)}
    g.link(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


mats_sockets = {}


def set_pass(m, which):
    nt = m.node_tree
    bsdf_n, em_n, out_n = mats_sockets[m.name]["nodes"]
    bsdf, em, out = nt.nodes[bsdf_n], nt.nodes[em_n], nt.nodes[out_n]
    for l in list(nt.links):
        if l.to_node in (em, out):
            nt.links.remove(l)
    if which == "nrm":
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        return
    src = mats_sockets[m.name][which]
    if isinstance(src, (int, float)):
        em.inputs["Color"].default_value = (src, src, src, 1.0)
    else:
        nt.links.new(src, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])


def tex(name, kind):
    return os.path.join(SRC, name, "%s_%s_2k.jpg" % (name, kind))


# ------------------------------------------------------------------ materiały

def mat_concrete(name, tint=(1.0, 1.0, 1.0), seed=0.0, wear_attr=True, tex_px=32.0):
    """Beton prefabrykatów. `wear_attr`: maski z atrybutu `wear` siatki wysokiej (R odprysk, G krawędź, B plama rdzy); inaczej krawędź z węzła Bevel."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    k = 1.0 / tex_px
    vec = g.coord((k, k, k), (seed * 0.37, seed * 0.61, seed * 0.13))
    diff = g.img(tex("concrete_wall_006", "diff"), vec)
    rgh = g.img(tex("concrete_wall_006", "rough"), vec, color=False)
    hgt = g.img(tex("concrete_wall_006", "disp"), vec, color=False)
    obj = g.coord()
    # kolor bazowy: skan przyciemniony ku szaremu (skan jest brązowawy) i zabarwiony wariantem
    hsv = g.n("ShaderNodeHueSaturation")
    hsv.inputs["Saturation"].default_value = 0.55
    hsv.inputs["Value"].default_value = 1.18
    g.link(diff.outputs["Color"], hsv.inputs["Color"])
    base = g.mix(1.0, hsv.outputs["Color"], (tint[0], tint[1], tint[2], 1.0), "MULTIPLY")
    # duże plamy odcienia (nierówne wiązanie betonu)
    blot = g.noise(obj, 0.09 + seed * 0.003, 4.0, 0.6)
    base = g.mix(g.mrange(blot, 0.38, 0.72, 0.0, 0.35), base, srgb(96, 92, 84), "MULTIPLY")
    if wear_attr:
        at = g.n("ShaderNodeAttribute", attribute_name="wear")
        sep = g.n("ShaderNodeSeparateColor")
        g.link(at.outputs["Color"], sep.inputs["Color"])
        chip, edg, rst = sep.outputs["Red"], sep.outputs["Green"], sep.outputs["Blue"]
    else:
        chip = g.mrange(g.math("MULTIPLY", g.edge(0.35), g.noise(obj, 0.6, 5.0)), 0.05, 0.12)
        edg = g.mrange(g.edge(0.25), 0.02, 0.15)
        rst = None
    # odpryski: świeży beton — jaśniejszy, z kruszywem
    fresh = g.mix(g.mrange(g.noise(obj, 3.2, 3.0), 0.45, 0.6), srgb(150, 144, 132), srgb(112, 106, 96))
    col = g.mix(g.mrange(chip, 0.05, 0.35), base, fresh)
    # przetarte krawędzie jaśniejsze
    col = g.mix(g.math("MULTIPLY", edg, 0.12), col, srgb(160, 154, 142))
    # brud w zagłębieniach i pod czopami
    occ = g.ao(2.2)
    col = g.mix(g.mrange(occ, 0.95, 0.45, 0.0, 0.75), col, srgb(46, 42, 36), "MULTIPLY")
    # zacieki wody: szum rozciągnięty w pionie, tylko na ścianach bocznych, mocniej u góry
    sx = g.zpos()
    streak_v = g.coord((0.55, 0.55, 0.045), (seed * 1.7, seed * 0.9, 0.0))
    st = g.noise(streak_v, 1.0, 5.0, 0.6)
    side = g.math("SUBTRACT", 1.0, g.math("ABSOLUTE", g.nz()))
    st_m = g.math("MULTIPLY", g.mrange(st, 0.52, 0.68), side)
    st_m = g.math("MULTIPLY", st_m, g.mrange(sx.outputs["Z"], 0.0, HB, 0.35, 1.0))
    col = g.mix(g.math("MULTIPLY", st_m, 0.55), col, srgb(70, 66, 60), "MULTIPLY")
    # błoto przy ziemi (rozbryzgi do ~1/4 wysokości)
    mud_n = g.noise(obj, 0.8, 6.0, 0.65)
    mud = g.mrange(g.math("ADD", g.mrange(sx.outputs["Z"], 2.4, 0.0), g.math("MULTIPLY", mud_n, 0.55)), 0.6, 1.0)
    col = g.mix(g.math("MULTIPLY", mud, 0.85), col, srgb(74, 62, 46))
    # kurz i liszaj na górze
    top = g.mrange(g.nz(), 0.6, 0.95)
    lich = g.math("MULTIPLY", top, g.mrange(g.noise(obj, 0.55, 6.0, 0.7), 0.55, 0.7))
    col = g.mix(g.math("MULTIPLY", lich, 0.5), col, srgb(78, 82, 62))
    if rst is not None:
        rust_c = g.mix(g.noise(obj, 2.0, 4.0), srgb(120, 58, 26), srgb(78, 38, 18))
        col = g.mix(g.math("MULTIPLY", g.mrange(rst, 0.0, 1.0), g.mrange(g.noise(obj, 1.3, 5.0), 0.3, 0.6, 0.5, 1.0)), col, rust_c)
    rough = g.math("ADD", g.math("MULTIPLY", rgh.outputs["Color"], 0.35), 0.62)
    rough = g.mixf(g.mrange(chip, 0.05, 0.3), rough, 0.97)
    rough = g.mixf(g.math("MULTIPLY", st_m, 0.6), rough, 0.68)
    # wysokość: skan + drobne pory
    fine = g.noise(obj, 6.5, 2.0)
    h = g.math("ADD", hgt.outputs["Color"], g.math("MULTIPLY", fine, 0.25))
    nrm = g.bump(h, 0.4, 0.22)
    return finish_mat(m, g, col, rough, 0.0, nrm)


def mat_rebar(name):
    """Pręt uchwytu: stal pokryta rdzą."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    vec = g.coord((0.25, 0.25, 0.25))
    diff = g.img(tex("rusty_metal_02", "diff"), vec)
    rgh = g.img(tex("rusty_metal_02", "rough"), vec, color=False)
    obj = g.coord()
    deep = g.mrange(g.noise(obj, 2.5, 5.0), 0.35, 0.7)
    col = g.mix(deep, srgb(96, 50, 26), diff.outputs["Color"], "MULTIPLY")
    col = g.mix(0.5, col, srgb(86, 44, 22))
    rough = g.math("ADD", g.math("MULTIPLY", rgh.outputs["Color"], 0.3), 0.6)
    metal = g.mrange(g.noise(obj, 3.0, 4.0), 0.55, 0.7, 0.15, 0.6)
    nrm = g.bump(g.noise(obj, 9.0, 5.0), 0.5, 0.1)
    return finish_mat(m, g, col, rough, metal, nrm)


def mat_paint(name, color, rust=0.5, tex_px=40.0, seed=0.0):
    """Malowana blacha obudowy: skan zielonej farby z rdzą, odcień `color`, odpryski na krawędziach (rdza, stal), zacieki rdzy, błoto."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    k = 1.0 / tex_px
    vec = g.coord((k, k, k), (seed, seed * 0.5, 0.0))
    diff = g.img(tex("green_metal_rust", "diff"), vec)
    rgh = g.img(tex("green_metal_rust", "rough"), vec, color=False)
    hgt = g.img(tex("green_metal_rust", "disp"), vec, color=False)
    rvec = g.coord((0.06, 0.06, 0.06), (seed * 2.0, 0.0, 0.0))
    rdiff = g.img(tex("rusty_metal_02", "diff"), rvec)
    obj = g.coord()
    # odcień: skan zielony → farba w kolorze `color` z zachowaniem plam i przebarwień skanu
    bw = g.n("ShaderNodeRGBToBW")
    g.link(diff.outputs["Color"], bw.inputs["Color"])
    lum = g.mrange(bw.outputs["Val"], 0.02, 0.14, 0.55, 1.25)
    cc = g.n("ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        g.link(lum, cc.inputs[ch])
    paint = g.mix(1.0, srgb(*color), cc.outputs["Color"], "MULTIPLY")
    paint = g.mix(0.35, paint, diff.outputs["Color"], "OVERLAY")
    sx = g.zpos()
    # odpryski farby na krawędziach i plamach
    edg = g.mrange(g.edge(0.3), 0.01, 0.12)
    chipn = g.noise(obj, 0.9, 7.0, 0.7)
    chip = g.mrange(g.math("ADD", g.math("MULTIPLY", edg, 0.9), chipn), 1.02 - rust * 0.12, 1.12 - rust * 0.12)
    under = g.mix(g.mrange(g.noise(obj, 4.0, 3.0), 0.45, 0.6), rdiff.outputs["Color"], srgb(110, 104, 96))
    col = g.mix(chip, paint, under)
    # cienka obwódka jaśniejszej farby wokół odprysku
    rim = g.math("SUBTRACT", g.mrange(g.math("ADD", g.math("MULTIPLY", edg, 0.9), chipn), 0.97 - rust * 0.12, 1.02 - rust * 0.12), chip)
    col = g.mix(g.math("MULTIPLY", rim, 0.4), col, srgb(150, 150, 130))
    # brud w zagłębieniach
    occ = g.ao(2.5)
    col = g.mix(g.mrange(occ, 0.95, 0.4, 0.0, 0.7), col, srgb(38, 34, 28), "MULTIPLY")
    # zacieki rdzy spływające w dół
    streak_v = g.coord((0.7, 0.7, 0.05), (seed * 3.1, seed * 1.3, 0.0))
    st = g.noise(streak_v, 1.0, 6.0, 0.62)
    side = g.math("SUBTRACT", 1.0, g.math("ABSOLUTE", g.nz()))
    st_m = g.math("MULTIPLY", g.mrange(st, 0.56 - rust * 0.05, 0.7), side)
    col = g.mix(g.math("MULTIPLY", st_m, 0.85), col, srgb(98, 48, 22))
    # błoto przy ziemi
    mud = g.mrange(g.math("ADD", g.mrange(sx.outputs["Z"], 7.0, 2.0), g.math("MULTIPLY", g.noise(obj, 0.7, 6.0, 0.65), 0.5)), 0.55, 1.0)
    col = g.mix(g.math("MULTIPLY", mud, 0.8), col, srgb(66, 56, 42))
    # kurz na powierzchniach poziomych
    top = g.mrange(g.nz(), 0.6, 0.95)
    col = g.mix(g.math("MULTIPLY", top, g.mrange(g.noise(obj, 0.4, 5.0), 0.4, 0.7, 0.25, 0.6)), col, srgb(92, 86, 74))
    rough = g.math("ADD", g.math("MULTIPLY", rgh.outputs["Color"], 0.35), 0.42)
    rough = g.mixf(chip, rough, 0.82)
    rough = g.mixf(g.math("MULTIPLY", mud, 0.8), rough, 0.92)
    metal = g.math("MULTIPLY", chip, g.mrange(g.noise(obj, 4.0, 3.0), 0.45, 0.6, 0.0, 0.7))
    h = g.math("ADD", hgt.outputs["Color"], g.math("MULTIPLY", chip, -0.4))
    nrm = g.bump(h, 0.45, 0.12)
    return finish_mat(m, g, col, rough, metal, nrm)


def mat_flat(name, color, rough=0.6, metal=0.0, grime=0.5, edge_col=None):
    """Prosty materiał (guma, mosiądz, farba tabliczki) z brudem w zagłębieniach i przetarciem krawędzi."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    g = G(m)
    obj = g.coord()
    col = g.mix(g.mrange(g.noise(obj, 1.5, 6.0), 0.3, 0.8, 0.0, 0.25), srgb(*color), srgb(40, 36, 30), "MULTIPLY")
    if edge_col is not None:
        col = g.mix(g.math("MULTIPLY", g.mrange(g.edge(0.15), 0.01, 0.1), 0.8), col, srgb(*edge_col))
    col = g.mix(g.mrange(g.ao(1.5), 0.95, 0.4, 0.0, grime), col, srgb(40, 36, 30), "MULTIPLY")
    rough_s = g.mrange(g.noise(obj, 3.0, 4.0), 0.3, 0.7, rough - 0.1, rough + 0.1)
    nrm = g.bump(g.noise(obj, 8.0, 4.0), 0.15, 0.1)
    return finish_mat(m, g, col, rough_s, metal, nrm)


# ------------------------------------------------------------------ bryły

def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)
    mats_sockets.clear()


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mk(name, bm, m=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if m is not None:
        me.materials.append(m)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(ob.matrix_world)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    ob.matrix_world = Matrix.Identity(4)
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def box(c, s, m, bevel=0.2, seg=2, rot=None):
    """Prostopadłościan o środku `c` i rozmiarze `s`, z fazowaniem krawędzi."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
    ob = mk("box", bm, m)
    if bevel > 0:
        bv = ob.modifiers.new("bv", "BEVEL")
        bv.width = bevel
        bv.segments = seg
        bv.limit_method = "ANGLE"
    if rot is not None:
        ob.rotation_euler = rot
    ob.location = c
    return apply_mods(ob)


def cyl(c, r, h, m, axis="Z", seg=24, bevel=0.06, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    ob = mk("cyl", bm, m)
    if bevel > 0:
        bv = ob.modifiers.new("bv", "BEVEL")
        bv.width = bevel
        bv.segments = 2
        bv.limit_method = "ANGLE"
    ob.rotation_euler = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    ob.location = c
    return apply_mods(ob)


def tube(points, r, m, res=4, closed_caps=True):
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("NURBS" if len(points) > 2 else "POLY")
    sp.points.add(len(points) - 1)
    for p, cpt in zip(points, sp.points):
        cpt.co = (p[0], p[1], p[2], 1.0)
    if len(points) > 2:
        sp.order_u = 3
        sp.use_endpoint_u = True
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.resolution_u = 10
    cu.use_fill_caps = closed_caps
    if m is not None:
        cu.materials.append(m)
    ob = link(bpy.data.objects.new("tube", cu))
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.curves.remove(cu)
    return link(bpy.data.objects.new("tube_m", me))


def torus_arc(c, R, r, m, a0, a1, plane="XZ", seg=24, rseg=10):
    """Łuk torusa (pręt uchwytu) od kąta a0 do a1 w płaszczyźnie `plane`."""
    bm = bmesh.new()
    rings = []
    for i in range(seg + 1):
        a = a0 + (a1 - a0) * i / seg
        ring = []
        for j in range(rseg):
            b = 2 * math.pi * j / rseg
            rr = R + r * math.cos(b)
            p = (rr * math.cos(a), r * math.sin(b), rr * math.sin(a))
            if plane == "XZ":
                p = (p[0], p[1], p[2])
            else:
                p = (p[1], p[0], p[2])
            ring.append(bm.verts.new((c[0] + p[0], c[1] + p[1], c[2] + p[2])))
        rings.append(ring)
    for i in range(seg):
        for j in range(rseg):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % rseg], rings[i + 1][(j + 1) % rseg], rings[i + 1][j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = mk("arc", bm, m)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def prism_xz(pts, y0, y1, m):
    """Wielokąt (x, z) wyciągnięty od y0 do y1 (tabliczki, piorun)."""
    bm = bmesh.new()
    a = [bm.verts.new((p[0], y0, p[1])) for p in pts]
    b = [bm.verts.new((p[0], y1, p[1])) for p in pts]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    n = len(pts)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return mk("prism", bm, m)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def text_mesh(s, c, size, m, depth=0.04):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth
    ob = link(bpy.data.objects.new("txt", cu))
    ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.location = c
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    me.transform(ob.matrix_world)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.curves.remove(cu)
    o = link(bpy.data.objects.new("txt_m", me))
    me.materials.clear()
    me.materials.append(m)
    return o


# ------------------------------------------------------------------ blok betonowy

def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _rank(a):
    """Wartości → kwantyle 0…1 (szum Perlina ma wąski, zmienny zakres; progi liczymy na rozkładzie równomiernym)."""
    a = np.asarray(a)
    r = np.empty(len(a))
    r[np.argsort(a)] = np.linspace(0.0, 1.0, len(a))
    return r


def _remesh(objs, voxel):
    ob = join(objs, "rm")
    rm = ob.modifiers.new("rm", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    apply_mods(ob)
    return ob


def _chips(bm, L, seed, studs, loop):
    """Przesunięcia wierzchołków do środka: (duże ubytki, wszystko) + atrybut zużycia (R odprysk, G krawędź, B plama rdzy).
    Szum liczony z położenia, więc dwie różne siatki wokselowe tej samej bryły dostają te same ubytki."""
    bm.normal_update()
    bm.verts.ensure_lookup_table()
    rnd = random.Random(seed)
    off = Vector((rnd.uniform(0, 500), rnd.uniform(0, 500), rnd.uniform(0, 500)))
    hx, hy = L / 2, U / 2

    def nz(v, k, o):                                         # Perlin ~ ±0,35 → ok. 0…1 (stały przelicznik: te same progi na obu siatkach)
        return 0.5 + 1.45 * noise.noise(v * k + o)
    erng = random.Random(seed * 7 + 3)
    dens = {}
    for k in [(sx, sy, 0) for sx in (-1, 1) for sy in (-1, 1)] + [(sx, 0, sz) for sx in (-1, 1) for sz in (-1, 1)] + [(0, sy, sz) for sy in (-1, 1) for sz in (-1, 1)]:
        dens[k] = erng.choice((0.1, 0.3, 0.5, 0.75, 1.0))
    out = []
    for v in bm.verts:
        p = v.co
        e_m = big = d = rust = 0.0
        if p.z < HB + 0.02:
            ex, ey = hx - abs(p.x), hy - abs(p.y)
            ez = min(p.z, HB - p.z)
            de = {"x": ex, "y": ey, "z": ez}
            ax = sorted(de, key=de.get)
            ed = de[ax[1]]
            corner = 1.0 - smoothstep(0.5, 2.6, de[ax[2]])
            sgn = {"x": 1 if p.x > 0 else -1, "y": 1 if p.y > 0 else -1, "z": 1 if p.z > HB / 2 else -1}
            key = tuple(sgn[c] if c in (ax[0], ax[1]) else 0 for c in ("x", "y", "z"))
            dn = dens.get(key, 0.5)
            stud_zone = p.z > HB - 0.6 and any(math.hypot(p.x - s, p.y) < STUD_R + 0.45 for s in studs)
            e_m = 1.0 - smoothstep(0.1, 0.9, ed)
            reach = 1.2 + corner * 1.4
            emask = 1.0 - smoothstep(0.25 * reach, reach, ed)
            t = nz(p, 0.5, off) + emask * (0.55 * dn + 0.25 * corner) - 1.05 - (1.0 - emask) * 0.6
            big = smoothstep(0.0, 0.06, t) * (0.4 + 0.35 * nz(p, 1.6, off * 1.3) + 0.3 * corner)
            nick = smoothstep(0.0, 0.05, nz(p, 2.0, off * 0.7) + 0.15 - 1.08) * 0.16 * (1.0 - smoothstep(0.2, 0.6, ed))
            pore = smoothstep(0.0, 0.04, nz(p, 5.5, off * 0.3) - 1.2) * 0.06 * (1.0 - e_m)
            d = max(big, nick, pore)
            if stud_zone:
                big = 0.0
                d = min(d, pore)
            if loop:
                rust = max(0.0, 1.0 - math.hypot(p.x, p.y) / 2.4) if p.z > HB - 0.25 else 0.0
        out.append((big, d, (min(d / 0.3, 1.0), e_m, rust)))
    return out


def concrete_block(L, seed, studs, loop):
    """Bryła wysoka (korpus + czopy z jednej siatki wokselowej, wszystkie ubytki, atrybut `wear`) i siatka gry (korpus z dużymi ubytkami,
    uproszczony; czopy jako osobne niskie walce wpuszczone w korpus)."""
    hi_parts = [box((0, 0, HB / 2), (L, U, HB), None, bevel=0.2, seg=2)]
    for sx in studs:
        hi_parts.append(cyl((sx, 0, HB + STUD_H / 2 - 0.05), STUD_R, STUD_H + 0.1, None, seg=48, bevel=0.14, r2=STUD_R - 0.1))
    high = _remesh(hi_parts, 0.085)
    bm = bmesh.new()
    bm.from_mesh(high.data)
    ch = _chips(bm, L, seed, studs, loop)
    for v, c in zip(bm.verts, ch):
        v.co -= v.normal * c[1]
    lay = bm.loops.layers.color.new("wear")
    for f in bm.faces:
        for lp in f.loops:
            w = ch[lp.vert.index][2]
            lp[lay] = (w[0], w[1], w[2], 1.0)
    bm.to_mesh(high.data)
    bm.free()
    print("chips: %.1f%% verts, max %.2f px" % (100.0 * sum(1 for c in ch if c[1] > 0.05) / max(1, len(ch)), max(c[1] for c in ch)))
    low = _remesh([box((0, 0, HB / 2), (L, U, HB), None, bevel=0.2, seg=2)], 0.11)
    bm = bmesh.new()
    bm.from_mesh(low.data)
    ch = _chips(bm, L, seed, studs, False)
    for v, c in zip(bm.verts, ch):
        v.co -= v.normal * c[0]
    bm.to_mesh(low.data)
    bm.free()
    dec = low.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = 1800.0 / max(1, len(low.data.polygons))
    apply_mods(low)
    for ob in (high, low):
        for p in ob.data.polygons:
            p.use_smooth = True
    return high, low


def box_uv(ob, L, H, D, extra):
    """Rozwinięcie siatki gry bloku: każda ściana rzutowana na najbliższy bok prostopadłościanu (L × D × H), boki w atlasie bez nakładania;
    `extra` — obiekty (czopy, uchwyt) rozwijane osobno i wpasowane w wolne pole atlasu. Jednolita gęstość tekseli."""
    hx, hy = L / 2, D / 2
    gap = 0.35
    # kolumna A (szer. L): czoło, tył, góra, spód (spłaszczony); kolumna B (szer. D): lewy bok, prawy bok, pole na czopy i uchwyt
    colA = [("front", L, H), ("back", L, H), ("top", L, D), ("bottom", L, D * 0.25)]
    colB = [("left", D, H), ("right", D, H), ("extra", D, D)]
    rects = {}
    y = gap
    for n, w, h in colA:
        rects[n] = (gap, y, w, h)
        y += h + gap
    hA = y
    y = gap
    for n, w, h in colB:
        rects[n] = (L + 2 * gap, y, w, h)
        y += h + gap
    span = max(L + D + 3 * gap, hA, y)
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for f in me.polygons:
        c = f.center
        dist = {"front": hy + c.y, "back": hy - c.y, "left": hx + c.x, "right": hx - c.x, "top": H - c.z, "bottom": c.z}
        # ścianka ubytku: rozstrzyga też kierunek normalnej (ścianka ubytku na czole nie trafia na górę)
        nn = f.normal
        pref = {"front": -nn.y, "back": nn.y, "left": -nn.x, "right": nn.x, "top": nn.z, "bottom": -nn.z}
        side = min(dist, key=lambda k: dist[k] - 0.6 * pref[k])
        rx, ry, rw, rh = rects[side]
        for li in f.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            u, w = {"front": (v.x + hx, v.z), "back": (hx - v.x, v.z), "left": (hy - v.y, v.z), "right": (v.y + hy, v.z),
                    "top": (v.x + hx, v.y + hy), "bottom": (v.x + hx, (hy - v.y) * 0.25)}[side]
            u = min(max(u, 0.0), rw)
            w = min(max(w, 0.0), rh)
            uvl.data[li].uv = ((rx + u) / span, (ry + w) / span)
    # czopy i uchwyt: Smart UV każdego osobno, potem skala do pola `extra`
    rx, ry, rw, rh = rects["extra"]
    for e in extra:
        unwrap(e, 66.0, 0.02)
    if extra:
        n = len(extra)
        cols = math.ceil(math.sqrt(n))
        cw = rw / cols
        for i, e in enumerate(extra):
            ox, oy = rx + (i % cols) * cw, ry + (i // cols) * cw
            for d in e.data.uv_layers[0].data:
                d.uv = ((ox + d.uv[0] * (cw - gap)) / span, (oy + d.uv[1] * (cw - gap)) / span)


def rebar_loop(m, R=1.05, r=0.2, seg=20, rseg=10):
    return torus_arc((0, 0, HB - 0.3), R, r, m, 0.0, math.pi, "XZ", seg=seg, rseg=rseg)


def bake_setup(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    if OPT.get("gpu", "1") == "1":                           # wypiek na karcie (OPTIX/CUDA), gdy jest; inaczej procesor
        try:
            cp = bpy.context.preferences.addons["cycles"].preferences
            for kind in ("OPTIX", "CUDA"):
                cp.compute_device_type = kind
                cp.get_devices()
                devs = [d for d in cp.devices if d.type == kind]
                if devs:
                    for d in cp.devices:
                        d.use = d.type == kind
                    sc.cycles.device = "GPU"
                    break
        except Exception as e:                               # noqa: BLE001
            print("GPU niedostępne:", e)
    sc.cycles.samples = samples
    sc.render.bake.margin = 8
    return sc


def new_img(name, size, colorspace="sRGB", fill=(0, 0, 0, 1)):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    img.generated_color = fill
    return img


def target(low, img):
    for m in low.data.materials:
        nt = m.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        for n in nt.nodes:
            n.select = False
        node.select = True
        nt.nodes.active = node


def bake(low, high, img, kind, samples):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    target(low, img)
    bpy.ops.object.select_all(action="DESELECT")
    s2a = high is not None and high is not low
    if s2a:
        high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type=kind, use_selected_to_active=s2a, cage_extrusion=0.3 if s2a else 0.0, max_ray_distance=0.9 if s2a else 0.0,
                        margin=8, use_clear=True)


def bake_all(name, low, high, srcmats, size):
    """Przebiegi: albedo, chropowatość, metal (EMIT z materiałów źródłowych), normalne, AO. Wynik: materiał końcowy na `low`, eksport GLB."""
    t_alb = new_img(name + "_alb", size)
    t_r = new_img(name + "_r", size, "Non-Color")
    t_m = new_img(name + "_m", size, "Non-Color")
    t_n = new_img(name + "_n", size, "Non-Color", (0.5, 0.5, 1, 1))
    t_ao = new_img(name + "_ao", size, "Non-Color", (1, 1, 1, 1))
    if high is not low:                                       # siatka niska potrzebuje własnego materiału-celu
        tm = bpy.data.materials.new(name + "_tgt")
        tm.use_nodes = True
        low.data.materials.clear()
        low.data.materials.append(tm)
    s = SAMPLES or 1
    for which, img in (("alb", t_alb), ("rough", t_r), ("metal", t_m)):
        for m in srcmats:
            set_pass(m, which)
        bake(low, high, img, "EMIT", max(s, 4))
    for m in srcmats:
        set_pass(m, "nrm")
    bake(low, high, t_n, "NORMAL", max(s, 4))
    bake(low, high, t_ao, "AO", max(SAMPLES, 48))
    n = size * size
    a_alb = np.array(t_alb.pixels[:]).reshape(n, 4)
    occ = np.clip(np.array(t_ao.pixels[:]).reshape(n, 4)[:, 0], 0, 1)
    a_alb[:, :3] *= (0.6 + 0.4 * occ)[:, None]
    t_alb.pixels[:] = a_alb.reshape(-1).tolist()
    orm = new_img(name + "_orm", size, "Non-Color")
    a = np.ones((n, 4))
    a[:, 0] = occ
    a[:, 1] = np.array(t_r.pixels[:]).reshape(n, 4)[:, 0]
    a[:, 2] = np.array(t_m.pixels[:]).reshape(n, 4)[:, 0]
    orm.pixels[:] = a.reshape(-1).tolist()
    fm = bpy.data.materials.new(name)
    fm.use_nodes = True
    nt = fm.node_tree
    bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")

    def timg(img):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        return t
    nt.links.new(timg(t_alb).outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(timg(orm).outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(timg(t_n).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    low.data.materials.clear()
    low.data.materials.append(fm)
    for p in low.data.polygons:
        p.material_index = 0
    # podgląd tekstur obok modelu (kontrola wypieku)
    dbg = os.path.join(os.environ.get("MBLOCK_DEBUG", ""), "")
    if os.environ.get("MBLOCK_DEBUG"):
        for img in (t_alb, orm, t_n):
            img.filepath_raw = os.path.join(dbg, img.name + ".png")
            img.file_format = "PNG"
            img.save()
    export(low, name)


def export(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90, export_animations=False)
    print("SAVED", name, os.path.getsize(path) // 1024, "kB", len(obj.data.polygons), "faces")


def unwrap(ob, angle=60.0, margin=0.008):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def build_block(name, L, seed, tint, studs, loop):
    clear_scene()
    bake_setup(4)
    cm = mat_concrete(name + "_conc", tint, seed)
    high, low = concrete_block(L, seed, studs, loop)
    high.data.materials.append(cm)
    srcmats = [cm]
    parts_hi = [high]
    extra = [cyl((sx, 0, HB + STUD_H / 2 - 0.12), STUD_R - 0.02, STUD_H + 0.22, None, seg=20, bevel=0.0, r2=STUD_R - 0.12) for sx in studs]
    if loop:
        rb = mat_rebar(name + "_rebar")
        srcmats.append(rb)
        parts_hi.append(rebar_loop(rb))
        extra.append(rebar_loop(None, seg=12, rseg=6))
    high = join(parts_hi, "high")
    box_uv(low, L, HB, U, extra)
    low = join([low] + extra, name)
    low.data.set_sharp_from_angle(angle=math.radians(50))
    for p in low.data.polygons:
        p.use_smooth = True
    for a in list(low.data.color_attributes):
        low.data.color_attributes.remove(a)
    bake_all(name, low, high, srcmats, TEX)


# ------------------------------------------------------------------ obudowa transformatora

def build_transformer(name):
    """Obudowa transformatora na blok 2×2 kafle (32 × 32 px, głębokość ~29 px), płaska góra do chodzenia, czoło ku −Y."""
    clear_scene()
    bake_setup(4)
    conc = mat_concrete(name + "_conc", (0.95, 0.95, 0.93), 3.0, wear_attr=False)
    paint = mat_paint(name + "_paint", (74, 88, 58), rust=0.8, seed=1.0)
    paint_d = mat_paint(name + "_paint_d", (34, 40, 30), rust=0.3, seed=2.0)
    steel = mat_paint(name + "_steel", (120, 118, 112), rust=0.9, tex_px=20.0, seed=5.0)
    yellow = mat_flat(name + "_yel", (206, 166, 40), 0.55, 0.0, 0.6, edge_col=(120, 70, 30))
    black = mat_flat(name + "_blk", (22, 22, 24), 0.6, 0.0, 0.3)
    white = mat_flat(name + "_wht", (200, 198, 186), 0.7, 0.0, 0.5)
    alu = mat_flat(name + "_alu", (176, 178, 176), 0.4, 0.8, 0.6)
    brass = mat_flat(name + "_brass", (170, 120, 60), 0.45, 0.85, 0.6)
    rubber = mat_flat(name + "_rub", (30, 30, 32), 0.75, 0.0, 0.3)
    mats = [conc, paint, paint_d, steel, yellow, black, white, alu, brass, rubber]
    P = []
    FY = -14.3                                         # płaszczyzna czoła (cokół, żebra)
    TY = -11.5                                         # czoło zbiornika
    # cokół betonowy
    P.append(box((0, 0, 1.1), (32.0, 28.8, 2.2), conc, bevel=0.35, seg=3))
    # zbiornik + pokrywa z okapem
    P.append(box((0, 0.75, 15.8), (29.2, 24.5, 27.2), paint, bevel=0.3, seg=2))
    P.append(box((0, 0.5, 30.65), (31.4, 27.6, 2.7), paint, bevel=0.4, seg=3))
    P.append(box((0, 0.5, 29.15), (31.0, 27.2, 0.5), paint_d, bevel=0.1, seg=1))      # listwa pod okapem
    # śruby pokrywy na czole i bokach
    for i in range(9):
        x = -14.0 + 28.0 * i / 8
        if abs(x) < 6.0:                               # miejsce na napis
            continue
        P.append(cyl((x, -13.25, 30.6), 0.32, 0.35, steel, axis="Y", seg=6, bevel=0.04))
    for sxn in (-1, 1):
        for i in range(7):
            y = -11.0 + 23.0 * i / 6
            P.append(cyl((sxn * 15.72, y, 30.6), 0.32, 0.35, steel, axis="X", seg=6, bevel=0.04))
    # uchwyty transportowe na bokach pokrywy
    for sxn in (-1, 1):
        for y in (-8.0, 9.0):
            P.append(box((sxn * 15.85, y, 28.2), (0.45, 2.2, 2.4), paint, bevel=0.12, seg=1))
            P.append(torus_arc((sxn * 15.85, y, 27.6), 0.6, 0.18, steel, 0, 2 * math.pi, "YZ", seg=16, rseg=8))
    # --- lewa część czoła: drzwi szafki
    dx0, dx1, dz0, dz1 = -13.6, -1.2, 4.0, 27.4
    dcx, dcz = (dx0 + dx1) / 2, (dz0 + dz1) / 2
    P.append(box((dcx, TY - 0.22, dcz), (dx1 - dx0, 0.45, dz1 - dz0), paint, bevel=0.18, seg=2))
    # przetłoczenia drzwi (ramka)
    for z in (dz0 + 0.9, dz1 - 0.9):
        P.append(box((dcx, TY - 0.5, z), (dx1 - dx0 - 1.4, 0.18, 0.45), paint, bevel=0.06, seg=1))
    for x in (dx0 + 0.9, dx1 - 0.9):
        P.append(box((x, TY - 0.5, dcz), (0.45, 0.18, dz1 - dz0 - 1.4), paint, bevel=0.06, seg=1))
    # żaluzje wentylacyjne: górne i dolne
    for (z0, z1) in ((21.2, 25.6), (5.6, 9.2)):
        n = int((z1 - z0) / 0.75)
        P.append(box((dcx, TY - 0.47, (z0 + z1) / 2), (dx1 - dx0 - 3.2, 0.06, z1 - z0 + 0.3), paint_d, bevel=0.0))
        for i in range(n):
            z = z0 + 0.38 + i * (z1 - z0 - 0.5) / max(1, n - 1)
            P.append(box((dcx, TY - 0.72, z), (dx1 - dx0 - 3.4, 0.16, 0.95), paint, bevel=0.05, seg=1, rot=(math.radians(-38), 0, 0)))
        P.append(box((dcx, TY - 0.62, z1 + 0.35), (dx1 - dx0 - 3.0, 0.35, 0.3), paint, bevel=0.06, seg=1))
        P.append(box((dcx, TY - 0.62, z0 - 0.35), (dx1 - dx0 - 3.0, 0.35, 0.3), paint, bevel=0.06, seg=1))
    # zawiasy
    for z in (6.3, 15.7, 25.1):
        P.append(cyl((dx0 - 0.15, TY - 0.45, z), 0.36, 1.8, steel, seg=12, bevel=0.05))
        P.append(box((dx0 + 0.55, TY - 0.5, z), (1.4, 0.16, 1.1), steel, bevel=0.04, seg=1))
    # klamka z kłódką
    P.append(cyl((dx1 - 1.7, TY - 0.6, 15.6), 0.55, 0.5, steel, axis="Y", seg=16, bevel=0.06))
    P.append(box((dx1 - 1.7, TY - 0.92, 14.2), (0.55, 0.32, 3.2), steel, bevel=0.1, seg=2))
    P.append(box((dx1 - 1.7, TY - 0.7, 12.3), (1.1, 0.25, 0.6), steel, bevel=0.05, seg=1))
    P.append(box((dx1 - 1.7, TY - 1.15, 11.4), (0.95, 0.5, 1.1), brass, bevel=0.12, seg=2))
    P.append(torus_arc((dx1 - 1.7, TY - 1.15, 11.9), 0.36, 0.1, steel, 0.0, math.pi, "XZ", seg=10, rseg=6))
    # tabliczka ostrzegawcza: żółty trójkąt z czarną obwódką i błyskawicą
    sx_, sz_ = dcx, 16.6
    tri = lambda s, dz=0.0: [(sx_ - s, sz_ - s * 0.58 + dz), (sx_ + s, sz_ - s * 0.58 + dz), (sx_, sz_ + s * 1.15 + dz)]
    P.append(prism_xz(tri(2.6), TY - 0.62, TY - 0.45, black))
    P.append(prism_xz(tri(2.15), TY - 0.68, TY - 0.6, yellow))
    bolt = [(-0.35, 1.6), (0.45, 1.6), (0.05, 0.25), (0.7, 0.25), (-0.5, -1.25), (-0.1, -0.1), (-0.7, -0.1)]
    P.append(prism_xz([(sx_ + x * 0.95, sz_ + 0.15 + z * 0.95) for x, z in bolt], TY - 0.72, TY - 0.66, black))
    # tabliczka znamionowa z nitami
    P.append(box((dcx, TY - 0.55, 11.6), (4.4, 0.12, 2.3), alu, bevel=0.06, seg=1))
    for x in (-1.9, 1.9):
        for z in (-0.85, 0.85):
            P.append(cyl((dcx + x, TY - 0.62, 11.6 + z), 0.13, 0.1, steel, axis="Y", seg=8, bevel=0.02))
    for i, z in enumerate((12.15, 11.6, 11.05)):
        P.append(box((dcx - 0.4 + (0.3 if i == 2 else 0.0), TY - 0.62, z), (3.0 - i * 0.7, 0.03, 0.18), black, bevel=0.0))
    # --- prawa część czoła: radiator (żebra między kolektorami)
    rx0, rx1, rz0, rz1 = 0.6, 13.8, 4.3, 26.9
    nf = 11
    for i in range(nf):
        x = rx0 + 0.3 + i * (rx1 - rx0 - 0.6) / (nf - 1)
        P.append(box((x, (TY + FY) / 2 - 0.1, (rz0 + rz1) / 2), (0.34, TY - FY - 0.2, rz1 - rz0 - 1.4), paint, bevel=0.12, seg=2))
    for z in (rz0 + 0.3, rz1 - 0.3):
        P.append(cyl(((rx0 + rx1) / 2, TY - 1.35, z), 0.62, rx1 - rx0 + 0.6, paint, axis="X", seg=20, bevel=0.08))
        for x in (rx0 + 0.6, rx1 - 0.6):
            P.append(cyl((x, TY - 0.6, z), 0.5, 1.5, paint, axis="Y", seg=16, bevel=0.06))
    # spust oleju pod radiatorem
    P.append(cyl((rx1 - 1.2, TY - 1.35, rz0 - 0.9), 0.3, 1.1, brass, axis="Z", seg=12, bevel=0.04))
    # napis na czole pokrywy
    P.append(text_mesh("T-2   15 kV", (0.0, -13.32, 30.65), 1.45, white, 0.03))
    # --- boki: przepust kablowy, rura osłonowa, uziemienie
    pipe = [(14.4, 2.0, 22.0), (15.1, 2.0, 22.0), (15.15, 2.0, 20.8), (15.15, 2.0, 3.6), (15.15, 2.0, 2.2)]
    P.append(tube(pipe, 0.52, steel, res=4))
    for z in (8.0, 16.0):
        P.append(box((14.95, 2.0, z), (0.9, 1.4, 0.45), steel, bevel=0.06, seg=1))
    P.append(box((-15.0, -6.0, 18.5), (0.9, 2.6, 3.0), paint_d, bevel=0.15, seg=2))
    cable = [(-15.4, -6.0, 17.3), (-15.6, -6.0, 15.5), (-15.65, -5.5, 9.0), (-15.5, -4.6, 3.6), (-15.3, -4.0, 2.25)]
    P.append(tube(cable, 0.42, rubber, res=4))
    P.append(box((-14.0, FY + 1.2, 3.5), (0.9, 0.12, 2.6), brass, bevel=0.03, seg=1))
    P.append(cyl((-14.0, FY + 1.1, 4.4), 0.22, 0.25, steel, axis="Y", seg=6, bevel=0.02))
    for o in P:
        for p in o.data.polygons:
            p.use_smooth = True
    obj = join(P, name)
    # ostre krawędzie: normalne z kąta, potem rozwinięcie
    obj.data.set_sharp_from_angle(angle=math.radians(45))
    vs = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    print("transformer bounds", lo, hi, len(obj.data.polygons), "faces")
    unwrap(obj, 55.0, 0.004)
    bake_all(name, obj, obj, mats, TEX * 2)


# ------------------------------------------------------------------ główna pętla

def want(n):
    return not ONLY or n in ONLY


def main():
    os.makedirs(OUT, exist_ok=True)
    if want("mblock_a0"):
        build_block("mblock_a0", 2 * U, 11, (1.0, 0.99, 0.96), (-U / 2, U / 2), True)
    if want("mblock_a1"):
        build_block("mblock_a1", 2 * U, 29, (0.93, 0.94, 0.94), (-U / 2, U / 2), True)
    if want("mblock_ah"):
        build_block("mblock_ah", U, 47, (0.97, 0.96, 0.93), (0.0,), False)
    if want("mblock_c"):
        build_transformer("mblock_c")


main()
