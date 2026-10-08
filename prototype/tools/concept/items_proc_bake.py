"""Przedmioty HD budowane proceduralnie w Blenderze (granaty, apteczka, skrzynie, beczka, stojak, narzędzia…) i renderowane do sprite'ów: albedo, normalne świata, emisja.

Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/items_proc_bake.py -- OUT_DIR [nazwa ...]
Jednostka modelu = 1 piksel świata gry (gracz ma ~22 jednostki wysokości); kamera ortograficzna z −Y, stopy na z = 0, ramka dopasowana do bryły.
Wynik w OUT_DIR: <nazwa>.png (albedo), <nazwa>_nw.png (normalne świata, Raw), <nazwa>_em.png (emisja: diody, ekrany), <nazwa>_ao.png (okluzja otoczenia), items.json (rozmiary).
Potem: python prototype/tools/pack_items_hd.py OUT_DIR   (obrys, mapy normalnych w przestrzeni ekranu, art/items/).
Materiały: węzły proceduralne (szum, drewno, metal z rdzą, płótno) — pasy renderu podmieniają wyjście na Emission (albedo / normalna z węzła Bump / kolor emisji).
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ONLY = set(argv[1:])
PAD = 6
os.makedirs(OUT, exist_ok=True)


def srgb(r, g, b):
    f = lambda c: ((c / 255.0 + 0.055) / 1.055) ** 2.4 if c / 255.0 > 0.04045 else c / 255.0 / 12.92
    return (f(r), f(g), f(b), 1.0)


# ---------------------------------------------------------------- materiały

def mat(name, col, kind="solid", rough=0.55, metal=0.0, grime=0.25, bump=0.3, scale=1.2, emit=None, col2=None, rust=0.0):
    """Materiał proceduralny. kind: solid | metal | wood | cloth. col, col2 — kolory sRGB (0–255); emit — kolor świecenia (0–255) albo None."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = nt.nodes
    L = nt.links
    base = srgb(*col)
    dark = srgb(*(col2 or tuple(int(c * 0.55) for c in col)))
    coord = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    L.new(coord.outputs["Object"], mp.inputs["Vector"])
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    noise = N.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.5
    noise.inputs["Detail"].default_value = 6.0
    L.new(mp.outputs["Vector"], noise.inputs["Vector"])
    fine = N.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 14.0
    fine.inputs["Detail"].default_value = 4.0
    L.new(mp.outputs["Vector"], fine.inputs["Vector"])
    height = noise.outputs["Fac"]
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[1].position = 0.85
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = base
    mix.inputs[7].default_value = dark
    if kind == "wood":
        # słoje: pasy wzdłuż X (deski poziome), zaburzone szumem
        mp2 = N.new("ShaderNodeMapping")
        L.new(coord.outputs["Object"], mp2.inputs["Vector"])
        mp2.inputs["Scale"].default_value = (0.35, 7.0, 7.0)
        wave = N.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "Y"
        wave.inputs["Scale"].default_value = 1.0
        wave.inputs["Distortion"].default_value = 5.0
        wave.inputs["Detail"].default_value = 3.0
        L.new(mp2.outputs["Vector"], wave.inputs["Vector"])
        mulf = N.new("ShaderNodeMath")
        mulf.operation = "MULTIPLY"
        mulf.inputs[1].default_value = 0.65
        L.new(wave.outputs["Fac"], mulf.inputs[0])
        addn = N.new("ShaderNodeMath")
        addn.operation = "ADD"
        L.new(mulf.outputs["Value"], addn.inputs[0])
        L.new(noise.outputs["Fac"], addn.inputs[1])
        L.new(addn.outputs["Value"], ramp.inputs["Fac"])
        height = wave.outputs["Fac"]
        ramp.color_ramp.elements[0].position = 0.55
        ramp.color_ramp.elements[1].position = 1.05
    elif kind == "cloth":
        wa = N.new("ShaderNodeTexWave")
        wa.wave_type = "BANDS"
        wa.bands_direction = "X"
        wa.inputs["Scale"].default_value = 40.0
        wb = N.new("ShaderNodeTexWave")
        wb.wave_type = "BANDS"
        wb.bands_direction = "Z"
        wb.inputs["Scale"].default_value = 40.0
        L.new(mp.outputs["Vector"], wa.inputs["Vector"])
        L.new(mp.outputs["Vector"], wb.inputs["Vector"])
        mm = N.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        L.new(wa.outputs["Fac"], mm.inputs[0])
        L.new(wb.outputs["Fac"], mm.inputs[1])
        ad = N.new("ShaderNodeMath")
        ad.operation = "ADD"
        ad.inputs[1].default_value = 0.0
        L.new(mm.outputs["Value"], ad.inputs[0])
        ad2 = N.new("ShaderNodeMath")
        ad2.operation = "ADD"
        L.new(ad.outputs["Value"], ad2.inputs[0])
        L.new(noise.outputs["Fac"], ad2.inputs[1])
        L.new(ad2.outputs["Value"], ramp.inputs["Fac"])
        height = mm.outputs["Value"]
        ramp.color_ramp.elements[0].position = 0.4
        ramp.color_ramp.elements[1].position = 1.1
    else:
        gm = N.new("ShaderNodeMath")
        gm.operation = "MULTIPLY"
        gm.inputs[1].default_value = 1.0
        L.new(noise.outputs["Fac"], gm.inputs[0])
        L.new(gm.outputs["Value"], ramp.inputs["Fac"])
    L.new(ramp.outputs["Color"], mix.inputs[0])
    mix.inputs[0].default_value = 0.0
    alb_src = mix.outputs[2]
    L.new(ramp.outputs["Color"], mix.inputs[0])
    # siła brudu: mnożymy współczynnik przez `grime` przez węzeł Math
    gr = N.new("ShaderNodeMath")
    gr.operation = "MULTIPLY"
    gr.inputs[1].default_value = grime * (1.8 if kind in ("wood", "cloth") else 1.0)
    L.new(ramp.outputs["Color"], gr.inputs[0])
    L.new(gr.outputs["Value"], mix.inputs[0])
    final = alb_src
    if rust > 0.0:
        rn = N.new("ShaderNodeTexNoise")
        rn.inputs["Scale"].default_value = 1.7
        rn.inputs["Detail"].default_value = 8.0
        L.new(mp.outputs["Vector"], rn.inputs["Vector"])
        rr = N.new("ShaderNodeMapRange")
        rr.inputs["From Min"].default_value = 0.66 - rust * 0.2
        rr.inputs["From Max"].default_value = 0.76 - rust * 0.2
        L.new(rn.outputs["Fac"], rr.inputs["Value"])
        rmix = N.new("ShaderNodeMix")
        rmix.data_type = "RGBA"
        L.new(rr.outputs["Result"], rmix.inputs[0])
        L.new(final, rmix.inputs[6])
        rmix.inputs[7].default_value = srgb(122, 62, 30)
        final = rmix.outputs[2]
    # kropki drobnych rys / faktury
    sp = N.new("ShaderNodeMath")
    sp.operation = "MULTIPLY"
    sp.inputs[1].default_value = 0.22
    L.new(fine.outputs["Fac"], sp.inputs[0])
    bsum = N.new("ShaderNodeMath")
    bsum.operation = "ADD"
    L.new(height, bsum.inputs[0])
    L.new(sp.outputs["Value"], bsum.inputs[1])
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.35
    L.new(bsum.outputs["Value"], bp.inputs["Height"])
    # węzeł końcowy: Emission podmieniany przy każdym przebiegu
    pas = N.new("ShaderNodeEmission")
    out = N.new("ShaderNodeOutputMaterial")
    L.new(pas.outputs["Emission"], out.inputs["Surface"])
    nv = N.new("ShaderNodeVectorMath")
    nv.operation = "MULTIPLY_ADD"
    nv.inputs[1].default_value = (0.5, 0.5, 0.5)
    nv.inputs[2].default_value = (0.5, 0.5, 0.5)
    L.new(bp.outputs["Normal"], nv.inputs[0])
    ev = N.new("ShaderNodeRGB")
    ev.outputs[0].default_value = srgb(*emit) if emit else (0, 0, 0, 1)
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 1.6
    m["pass_nodes"] = {"alb": final.node.name + "|" + final.name, "nrm": nv.name, "emi": ev.name, "pas": pas.name, "ao": ao.name}
    # pas domyślny: albedo
    set_pass(m, "alb")
    return m


def set_pass(m, which):
    nt = m.node_tree
    d = m["pass_nodes"]
    pas = nt.nodes[d["pas"]]
    for l in list(nt.links):
        if l.to_node == pas:
            nt.links.remove(l)
    if which == "alb":
        nn, sn = d["alb"].split("|")
        nt.links.new(nt.nodes[nn].outputs[sn], pas.inputs["Color"])
    elif which == "nrm":
        nt.links.new(nt.nodes[d["nrm"]].outputs["Vector"], pas.inputs["Color"])
    elif which == "ao":
        nt.links.new(nt.nodes[d["ao"]].outputs["Color"], pas.inputs["Color"])
    else:
        nt.links.new(nt.nodes[d["emi"]].outputs[0], pas.inputs["Color"])


# ---------------------------------------------------------------- bryły

OBJS = []


def _finish(ob, bevel=0.0, seg=3, smooth=True):
    for p in ob.data.polygons:
        p.use_smooth = smooth
    if bevel > 0.0:
        bv = ob.modifiers.new("bv", "BEVEL")
        bv.width = bevel
        bv.segments = seg
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(35)
        wn = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
    OBJS.append(ob)
    return ob


def _obj(name, bm, m, loc, rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = Euler(tuple(math.radians(a) for a in rot))
    if m is not None:
        ob.data.materials.append(m)
    return ob


def box(loc, size, m, bevel=0.15, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    return _finish(_obj("box", bm, m, loc, rot), bevel)


def cyl(loc, r, h, m, axis="Z", r2=None, seg=40, bevel=0.06, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    r_ = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}[axis]
    ob = _obj("cyl", bm, m, loc, tuple(a + b for a, b in zip(r_, rot)) if rot != (0, 0, 0) else r_)
    return _finish(ob, bevel)


def sph(loc, r, m, scale=(1, 1, 1), seg=40):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    ob = _obj("sph", bm, m, loc)
    ob.scale = scale
    return _finish(ob, 0.0)


def tor(loc, R, r, m, axis="Y", seg=40, rot=(0, 0, 0)):
    bm = bmesh.new()
    pts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(16):
            b = 2 * math.pi * j / 16
            pts.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
    for i in range(seg):
        for j in range(16):
            a, b = i * 16 + j, i * 16 + (j + 1) % 16
            c, d = ((i + 1) % seg) * 16 + (j + 1) % 16, ((i + 1) % seg) * 16 + j
            bm.faces.new((pts[a], pts[b], pts[c], pts[d]))
    r_ = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}[axis]
    ob = _obj("tor", bm, m, loc, tuple(a + b for a, b in zip(r_, rot)))
    return _finish(ob, 0.0)


def tube(points, r, m, caps=True, res=6):
    """Rurka (kabel, drut, uchwyt) wzdłuż łamanej/wygładzonej krzywej."""
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("NURBS" if len(points) > 3 else "POLY")
    sp.points.add(len(points) - 1)
    for p, c in zip(points, sp.points):
        c.co = (p[0], p[1], p[2], 1.0)
    if len(points) > 3:
        sp.order_u = 4
        sp.use_endpoint_u = True
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.resolution_u = 12
    cu.use_fill_caps = caps
    ob = bpy.data.objects.new("tube", cu)
    bpy.context.scene.collection.objects.link(ob)
    if m is not None:
        cu.materials.append(m)
    OBJS.append(ob)
    return ob


def prism(points, thick, loc, m, rot=(0, 0, 0), bevel=0.06):
    """Wielokąt w płaszczyźnie XZ (x, z) wyciągnięty o `thick` wzdłuż Y."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], 0.0, p[1])) for p in points]
    f = bm.faces.new(vs)
    ex = bmesh.ops.extrude_face_region(bm, geom=[f])
    vv = [e for e in ex["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, thick, 0), verts=vv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = _obj("prism", bm, m, (loc[0], loc[1] - thick / 2, loc[2]), rot)
    return _finish(ob, bevel)


def arc_panel(cx, cy, R, ang, z0, z1, thick, m, bevel=0.1):
    """Wygięta w poziomie płyta (mina kierunkowa): wycinek pierścienia o kącie ±`ang` stopni, wypukłością ku −Y."""
    bm = bmesh.new()
    n = 24
    rows = []
    for zi, z in enumerate((z0, z1)):
        ring = []
        for i in range(n + 1):
            a = math.radians(-ang + 2 * ang * i / n)
            ring.append((bm.verts.new((cx + math.sin(a) * R, cy - math.cos(a) * R + R, z)), bm.verts.new((cx + math.sin(a) * (R + thick), cy - math.cos(a) * (R + thick) + R + thick * 0, z))))
        rows.append(ring)
    # powierzchnia zewnętrzna (ku −Y): wierzchołki o promieniu R, wewnętrzna: R+thick (ku +Y)
    def quad(a, b, c, d):
        bm.faces.new((a, b, c, d))
    for i in range(n):
        quad(rows[0][i][0], rows[0][i + 1][0], rows[1][i + 1][0], rows[1][i][0])
        quad(rows[0][i][1], rows[1][i][1], rows[1][i + 1][1], rows[0][i + 1][1])
        quad(rows[0][i][0], rows[1][i][0], rows[1][i][1], rows[0][i][1]) if False else None
        quad(rows[1][i][0], rows[1][i + 1][0], rows[1][i + 1][1], rows[1][i][1])
        quad(rows[0][i][0], rows[0][i][1], rows[0][i + 1][1], rows[0][i + 1][0])
    quad(rows[0][0][0], rows[0][0][1], rows[1][0][1], rows[1][0][0])
    quad(rows[0][n][0], rows[1][n][0], rows[1][n][1], rows[0][n][1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = _obj("arc", bm, m, (0, 0, 0))
    return _finish(ob, bevel)


def clear():
    for ob in list(OBJS):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        else:
            bpy.data.curves.remove(data)
    OBJS.clear()


# ---------------------------------------------------------------- paleta

def palette():
    P = {}
    P["olive"] = mat("olive", (78, 92, 54), "metal", grime=0.35, bump=0.15, rust=0.12)
    P["olive_d"] = mat("olive_d", (52, 62, 38), "metal", grime=0.4, bump=0.15, rust=0.15)
    P["olive_l"] = mat("olive_l", (104, 118, 72), "metal", grime=0.3, bump=0.15)
    P["steel"] = mat("steel", (150, 154, 162), "metal", rough=0.35, metal=0.8, grime=0.35, bump=0.12, rust=0.05)
    P["steel_d"] = mat("steel_d", (84, 88, 98), "metal", rough=0.4, metal=0.8, grime=0.35, bump=0.12)
    P["steel_l"] = mat("steel_l", (200, 204, 210), "metal", grime=0.25, bump=0.1)
    P["black"] = mat("black", (26, 27, 31), "solid", grime=0.2, bump=0.08)
    P["rubber"] = mat("rubber", (34, 34, 36), "solid", grime=0.2, bump=0.25, scale=3.0)
    P["white"] = mat("white", (222, 222, 212), "solid", grime=0.55, bump=0.1, col2=(150, 148, 130))
    P["red"] = mat("red", (176, 40, 34), "solid", grime=0.35, bump=0.1, col2=(110, 22, 20))
    P["red_d"] = mat("red_d", (128, 30, 26), "solid", grime=0.4, bump=0.1, col2=(80, 16, 14))
    P["yellow"] = mat("yellow", (214, 176, 56), "solid", grime=0.35, bump=0.1, col2=(150, 116, 30))
    P["orange"] = mat("orange", (214, 110, 40), "solid", grime=0.3, bump=0.1)
    P["brass"] = mat("brass", (196, 150, 62), "metal", rough=0.35, metal=0.85, grime=0.35, bump=0.1)
    P["tan"] = mat("tan", (186, 170, 124), "solid", grime=0.4, bump=0.1, col2=(120, 108, 76))
    P["khaki"] = mat("khaki", (142, 128, 86), "solid", grime=0.35, bump=0.15, col2=(100, 90, 58))
    P["slate"] = mat("slate", (92, 98, 106), "metal", grime=0.35, bump=0.12)
    P["grey_l"] = mat("grey_l", (170, 175, 180), "metal", grime=0.3, bump=0.1)
    P["wood"] = mat("wood", (122, 84, 50), "wood", rough=0.8, grime=0.55, bump=0.5, col2=(70, 46, 26))
    P["wood_d"] = mat("wood_d", (78, 52, 32), "wood", rough=0.85, grime=0.5, bump=0.5, col2=(44, 28, 16))
    P["wood_l"] = mat("wood_l", (168, 128, 82), "wood", rough=0.8, grime=0.5, bump=0.45, col2=(110, 78, 46))
    P["burlap"] = mat("burlap", (138, 104, 62), "cloth", rough=0.95, grime=0.5, bump=0.9, col2=(86, 62, 34))
    P["cord"] = mat("cord", (196, 178, 128), "cloth", grime=0.4, bump=0.7, col2=(128, 110, 70))
    P["barrel"] = mat("barrel", (152, 58, 38), "metal", grime=0.5, bump=0.3, col2=(92, 34, 22), rust=0.55)
    P["rusty"] = mat("rusty", (112, 70, 44), "metal", grime=0.6, bump=0.3, col2=(70, 42, 24), rust=0.8)
    P["bone"] = mat("bone", (206, 196, 168), "solid", rough=0.8, grime=0.6, bump=0.35, col2=(124, 110, 84))
    P["bone_d"] = mat("bone_d", (150, 138, 108), "solid", rough=0.8, grime=0.6, bump=0.3, col2=(88, 78, 58))
    P["reed"] = mat("reed", (112, 134, 70), "cloth", rough=0.9, grime=0.6, bump=0.3, col2=(70, 90, 40))
    P["reed_dry"] = mat("reed_dry", (170, 150, 84), "cloth", rough=0.9, grime=0.6, bump=0.3, col2=(110, 92, 50))
    P["cattail"] = mat("cattail", (92, 58, 34), "cloth", rough=0.9, grime=0.5, bump=0.8, col2=(54, 32, 18))
    P["cork"] = mat("cork", (176, 128, 84), "solid", rough=0.95, grime=0.7, bump=0.9, scale=3.0, col2=(112, 76, 44))
    P["paper"] = mat("paper", (222, 214, 190), "solid", rough=0.9, grime=0.45, bump=0.12, col2=(176, 164, 132))
    P["ink"] = mat("ink", (52, 52, 58), "solid", grime=0.1, bump=0.05)
    P["slate"] = mat("slate_b", (28, 38, 34), "solid", rough=0.95, grime=0.9, bump=0.15, scale=0.8, col2=(66, 80, 72))
    P["felt"] = mat("felt", (70, 52, 40), "cloth", grime=0.4, bump=0.6)
    P["ply"] = mat("ply", (150, 110, 70), "wood", rough=0.85, grime=0.5, bump=0.4, col2=(96, 66, 40))
    P["sign_dk"] = mat("sign_dk", (30, 26, 22), "metal", grime=0.5, bump=0.15)
    P["sign_in"] = mat("sign_in", (30, 36, 33), "metal", grime=0.4, bump=0.1)
    P["gold"] = mat("gold", (224, 174, 54), "metal", rough=0.3, metal=1.0, grime=0.2, bump=0.05)
    P["cyan_e"] = mat("cyan_e", (40, 150, 170), "solid", grime=0.0, bump=0.0, emit=(70, 220, 240))
    P["cyan_h"] = mat("cyan_h", (190, 250, 255), "solid", grime=0.0, bump=0.0, emit=(200, 255, 255))
    P["green_e"] = mat("green_e", (40, 150, 70), "solid", grime=0.0, bump=0.0, emit=(70, 230, 110))
    P["red_e"] = mat("red_e", (230, 40, 30), "solid", grime=0.0, bump=0.0, emit=(255, 60, 40))
    P["amber_e"] = mat("amber_e", (230, 150, 40), "solid", grime=0.0, bump=0.0, emit=(255, 170, 50))
    P["bulb_e"] = mat("bulb_e", (255, 230, 170), "solid", grime=0.0, bump=0.0, emit=(255, 232, 170))
    return P


# ---------------------------------------------------------------- modele (jednostka = piksel świata, z = 0 to podłoga)

def m_frag(P):
    sph((0, 0, 2.9), 2.7, P["olive"], (1, 1, 1.12))
    # segmenty „ananasa": poziome i pionowe rowki
    for z in (1.4, 2.7, 4.0):
        tor((0, 0, z), 2.62 * math.sqrt(max(0.1, 1 - ((z - 2.9) / 3.02) ** 2)), 0.1, P["olive_d"], "Z")
    cyl((0, 0, 5.75), 0.95, 0.9, P["steel_d"])
    cyl((0, 0, 5.2), 1.05, 0.28, P["yellow"])
    cyl((0, 0, 6.45), 0.75, 0.6, P["steel"])
    pts = []
    for a in range(75, 20, -7):
        t = math.radians(a)
        pts.append((2.9 * math.cos(t), -0.15, 2.9 + 3.05 * math.sin(t)))
    tube(pts, 0.28, P["steel"])
    tube([(0.9, 0, 6.3), (1.8, 0, 6.4), (2.5, 0, 6.0)], 0.25, P["steel"])
    tor((-1.2, -0.7, 6.1), 0.8, 0.12, P["steel_l"], "Y")


def m_phos(P):
    cyl((0, 0, 4.4), 2.2, 8.8, P["grey_l"], bevel=0.12)
    cyl((0, 0, 5.4), 2.24, 1.7, P["yellow"], bevel=0.05)
    cyl((0, 0, 2.0), 2.24, 0.55, P["red"], bevel=0.04)
    cyl((0, 0, 9.4), 1.95, 1.3, P["orange"], bevel=0.14)
    cyl((0, 0, 10.4), 0.8, 0.9, P["steel_d"])
    tube([(0.7, 0, 10.9), (1.9, 0, 11.0), (2.4, 0, 9.4), (2.4, 0, 6.4)], 0.22, P["steel"])
    tor((-1.1, -0.9, 10.7), 0.75, 0.11, P["steel_l"], "Y")
    box((0, -2.2, 7.6), (1.0, 0.1, 0.6), P["black"], 0.03)
    box((0, -2.2, 7.1), (0.5, 0.1, 0.5), P["black"], 0.03)


def m_smoke(P):
    cyl((0, 0, 4.4), 2.2, 8.8, P["slate"], bevel=0.12)
    cyl((0, 0, 5.4), 2.24, 2.0, P["grey_l"], bevel=0.05)
    cyl((0, 0, 9.4), 1.95, 1.4, P["steel_d"], bevel=0.14)
    for x in (-1.0, 0.0, 1.0):
        cyl((x, -1.75 + abs(x) * 0.35, 9.5), 0.3, 0.35, P["black"], axis="Y")
    cyl((0, 0, 10.5), 0.8, 0.8, P["steel_d"])
    tube([(0.7, 0, 10.9), (1.9, 0, 11.0), (2.4, 0, 9.4), (2.4, 0, 7.0)], 0.22, P["steel"])
    tor((-1.1, -0.9, 10.7), 0.75, 0.11, P["steel_l"], "Y")
    box((0, -2.2, 2.2), (2.2, 0.1, 0.5), P["black"], 0.03)


def m_mine(P):
    arc_panel(0, 0, 16.0, 26, 1.8, 7.6, 2.0, P["olive"], 0.2)
    # górna listwa celownicza i gniazda zapalników
    box((0, 0.6, 7.9), (9.0, 1.4, 0.5), P["olive_d"], 0.12)
    cyl((-3.4, 0.8, 8.3), 0.4, 0.7, P["steel_d"])
    cyl((3.4, 0.8, 8.3), 0.4, 0.7, P["steel_d"])
    tube([(3.4, 0.8, 8.6), (5.0, 1.0, 9.3), (6.5, 0.9, 7.5)], 0.14, P["red"])
    # przód: żeberka, napis-pasek i diody (przód płyty leży na y ≈ −2)
    for x in (-5.6, -2.8, 0.0, 2.8, 5.6):
        box((x, -2.1 + abs(x) * abs(x) / 32.0, 4.7), (0.5, 0.35, 5.0), P["olive_d"], 0.08)
    box((0, -2.28, 4.7), (4.6, 0.2, 1.3), P["yellow"], 0.05)
    for x in (-1.2, -0.4, 0.4, 1.2):
        box((x, -2.4, 4.7), (0.3, 0.1, 0.8), P["black"], 0.02)
    sph((-6.8, -1.2, 6.4), 0.5, P["red_d"])             # dioda uzbrojenia świeci dynamicznie (placed.gd), tu tylko oprawa
    sph((-6.0, -1.5, 6.4), 0.35, P["steel_d"])
    # nóżki
    for sx in (-1, 1):
        tube([(sx * 5.6, 0.2, 2.5), (sx * 6.6, -0.6, 1.0), (sx * 7.4, -1.2, 0.2)], 0.2, P["steel_d"])
        tube([(sx * 5.6, 0.7, 2.5), (sx * 6.2, 1.2, 1.0), (sx * 6.9, 1.8, 0.2)], 0.2, P["steel_d"])


def m_charge(P):
    box((0, 0, 1.4), (13.0, 4.4, 2.8), P["khaki"], 0.35)
    box((0, 0, 4.1), (13.0, 4.4, 2.6), P["khaki"], 0.35)
    for x in (-5.5, -1.0, 5.0):
        box((x, 0, 2.75), (0.5, 4.6, 5.6), P["black"], 0.05)
    box((3.2, 0.2, 6.9), (5.4, 2.6, 3.0), P["black"], 0.25)
    box((3.2, -1.15, 7.0), (4.2, 0.2, 1.4), P["amber_e"], 0.05)
    sph((1.2, -1.35, 5.9), 0.38, P["red_d"])            # zapalnik miga dynamicznie (placed.gd)
    cyl((-4.2, 0.4, 5.6), 0.45, 1.8, P["steel"])
    for i, c in enumerate(("red", "yellow", "steel_l")):
        tube([(-4.2, 0.4, 5.9), (-2.5 + i * 0.4, -1.0 - i * 0.5, 7.4 + i * 0.4), (0.4, -0.8, 6.3 + i * 0.5)], 0.14, P[c])


def m_medkit(P):
    box((0, 0, 4.2), (16.0, 6.0, 8.4), P["white"], 0.5)
    box((0, -3.0, 6.1), (16.2, 0.12, 0.35), P["steel_d"], 0.05)
    box((0, -3.1, 4.2), (2.3, 0.35, 6.4), P["red"], 0.12)
    box((0, -3.1, 4.2), (6.4, 0.35, 2.3), P["red"], 0.12)
    for x in (-5.4, 5.4):
        box((x, -3.1, 6.1), (1.6, 0.6, 1.3), P["steel"], 0.12)
    for x in (-8.0, 8.0):
        box((x, 0, 4.2), (0.7, 6.4, 8.8), P["grey_l"], 0.2)
    tube([(-3.5, 0, 8.3), (-3.2, 0, 10.2), (3.2, 0, 10.2), (3.5, 0, 8.3)], 0.45, P["black"])
    box((0, -3.05, 0.9), (13.0, 0.2, 0.4), P["steel_d"], 0.06)


def m_defib(P):
    box((0, 0, 4.6), (14.0, 5.6, 9.0), P["black"], 0.55)
    box((0, -2.8, 1.0), (13.4, 0.5, 1.4), P["yellow"], 0.2)
    box((-1.2, -2.85, 5.8), (7.6, 0.3, 4.2), P["steel_d"], 0.15)
    box((-1.2, -3.05, 5.8), (6.8, 0.2, 3.5), P["cyan_e"], 0.05)
    tube([(-4.4, -3.25, 5.6), (-3.0, -3.25, 5.6), (-2.4, -3.25, 7.2), (-1.4, -3.25, 4.2), (-0.6, -3.25, 5.6), (1.6, -3.25, 5.6)], 0.17, P["cyan_h"], res=3)
    for x, c in ((4.7, "red_e"), (4.7, None)):
        pass
    sph((5.0, -3.0, 7.5), 0.55, P["red_e"])
    sph((5.0, -3.0, 5.0), 0.55, P["green_e"])
    prism([(0, 1.6), (-1.0, 0), (-0.1, 0), (-0.7, -1.6), (1.0, 0.3), (0.1, 0.3)], 0.2, (4.6, -3.0, 2.8), P["yellow"], bevel=0.03)
    tube([(-5.0, 0, 8.7), (-4.6, 0, 10.3), (4.6, 0, 10.3), (5.0, 0, 8.7)], 0.45, P["rubber"])
    for sx in (-1, 1):
        cyl((sx * 7.8, -0.2, 6.4), 1.9, 0.9, P["steel"], axis="X")
        cyl((sx * 8.4, -0.2, 6.4), 1.3, 0.5, P["red_d"], axis="X")


def m_scanner(P):
    box((0, 0, 5.0), (8.4, 3.6, 9.6), P["olive_d"], 0.6)
    cyl((0, -1.8, 6.4), 3.0, 0.7, P["steel_d"], axis="Y")
    cyl((0, -2.1, 6.4), 2.5, 0.4, P["green_e"], axis="Y", seg=48)
    for r in (0.9, 1.6, 2.2):
        tor((0, -2.35, 6.4), r, 0.07, P["green_e"] if r < 2 else P["cyan_h"], "Y")
    tube([(-2.3, -2.4, 6.4), (2.3, -2.4, 6.4)], 0.05, P["cyan_h"], res=3)
    tube([(0, -2.4, 4.1), (0, -2.4, 8.7)], 0.05, P["cyan_h"], res=3)
    sph((1.3, -2.45, 7.7), 0.32, P["green_e"])
    cyl((2.8, 0.3, 9.8 + 2.5), 0.25, 5.0, P["steel_d"])
    sph((2.8, 0.3, 14.5), 0.55, P["red"])
    sph((-2.4, -1.9, 1.7), 0.55, P["red"])
    sph((-0.9, -1.9, 1.7), 0.55, P["amber_e"])
    box((0, -1.9, 0.9), (6.0, 0.2, 0.3), P["steel"], 0.04)
    tube([(-3.9, 0, 3.0), (-5.0, 0, 6.5), (-3.9, 0, 9.0)], 0.35, P["rubber"])


def m_flare(P, stuck=False):
    cyl((0, 0, 7.0), 1.45, 14.0, P["red"], bevel=0.1)
    cyl((0, 0, 7.4), 1.5, 1.1, P["cord"], bevel=0.04)
    cyl((0, 0, 9.3), 1.5, 0.4, P["cord"], bevel=0.03)
    cyl((0, 0, 14.6), 1.55, 1.3, P["wood_d"], bevel=0.12)
    cyl((0, 0, 15.5), 0.65, 0.6, P["black"], bevel=0.05)
    cyl((0, 0, 0.35), 1.5, 0.7, P["black"], bevel=0.08)
    if stuck:
        P_ = P["steel_d"]
        for x, y, r, z in ((-3.2, 0.5, 1.3, 0.9), (3.0, -0.4, 1.6, 1.0), (-1.2, -1.6, 0.8, 0.5), (1.8, 1.2, 0.9, 0.5)):
            sph((x, y, z), r, P["slate"], (1, 1, 0.75), seg=16)


def m_flare_box(P):
    box((0, 0, 3.0), (14.0, 6.0, 6.0), P["wood"], 0.3)
    box((0, -3.02, 3.0), (14.2, 0.1, 1.2), P["red"], 0.04)
    for x in (-3.9, 0.0, 3.9):
        cyl((x, -0.3, 7.6), 1.25, 9.0, P["red"], bevel=0.08)
        cyl((x, -0.3, 8.2), 1.3, 0.9, P["cord"], bevel=0.03)
        cyl((x, -0.3, 12.3), 1.3, 0.9, P["wood_d"], bevel=0.08)
    box((0, -3.0, 6.3), (14.4, 0.4, 0.6), P["wood_d"], 0.1)


def m_supply(P):
    box((0, 0, 4.6), (14.0, 7.0, 9.2), P["olive"], 0.4)
    box((0, 0, 9.5), (14.4, 7.4, 0.9), P["olive_d"], 0.25)
    for x in (-4.6, 4.6):
        box((x, -3.5, 4.8), (0.7, 0.3, 8.4), P["olive_d"], 0.08)
    box((0, -3.55, 4.4), (5.6, 0.15, 3.8), P["tan"], 0.06)
    for x in (-5.6, 5.6):
        box((x, -3.65, 7.6), (1.4, 0.6, 1.2), P["steel"], 0.12)
    for x in (-7.2, 7.2):
        tube([(x, -1.4, 7.2), (x + (0.9 if x > 0 else -0.9), 0, 7.6), (x, 1.4, 7.2)], 0.28, P["cord"])
    for y in (-3.0, 3.0):
        for x in (-6.4, 6.4):
            sph((x, y, 8.6), 0.3, P["steel_l"], seg=12)


def m_ammo(P):
    box((0, 0, 3.0), (10.0, 4.6, 6.0), P["olive"], 0.35)
    box((0, 0, 6.25), (10.4, 5.0, 0.8), P["olive_d"], 0.2)
    box((0, -2.35, 3.2), (5.6, 0.14, 2.6), P["tan"], 0.05)
    box((0, -2.45, 5.8), (1.4, 0.45, 1.0), P["steel"], 0.1)
    tube([(-2.0, 0, 6.7), (-1.8, 0, 8.1), (1.8, 0, 8.1), (2.0, 0, 6.7)], 0.28, P["steel_d"])
    for x in (-3.9, 3.9):
        box((x, -2.35, 3.0), (0.4, 0.14, 5.4), P["olive_d"], 0.05)


def m_cache(P):
    box((0, 0, 4.8), (16.0, 8.0, 9.6), P["olive_d"], 0.5)
    box((0, 0, 9.9), (16.6, 8.6, 1.4), P["olive"], 0.4)
    for x in (-5.4, 5.4):
        box((x, -4.05, 4.8), (1.5, 0.3, 9.8), P["brass"], 0.08)
    box((0, -4.1, 6.0), (16.4, 0.3, 1.1), P["brass"], 0.08)
    box((0, -4.25, 7.0), (2.2, 0.5, 2.6), P["brass"], 0.15)
    sph((0, -4.55, 6.6), 0.5, P["black"], seg=12)
    for x in (-8.0, 8.0):
        box((x, 0, 4.8), (0.7, 8.4, 9.8), P["steel_d"], 0.15)
        tube([(x + (0.4 if x > 0 else -0.4), -1.7, 6.4), (x + (1.5 if x > 0 else -1.5), 0, 6.8), (x + (0.4 if x > 0 else -0.4), 1.7, 6.4)], 0.3, P["steel"])


def m_stash(P):
    sph((0, 0, 3.5), 1.0, P["burlap"], (5.4, 4.3, 3.6), seg=48)
    cyl((0, 0, 7.4), 2.3, 2.2, P["burlap"], r2=1.35, seg=32, bevel=0)
    tor((0, 0, 7.9), 1.5, 0.3, P["cord"], "Z")
    tor((0, 0, 7.3), 1.65, 0.22, P["cord"], "Z")
    sph((0.4, 0, 9.4), 1.0, P["burlap"], (2.5, 1.9, 1.7), seg=32)
    sph((-1.1, -0.3, 9.0), 1.0, P["burlap"], (1.4, 1.1, 1.3), seg=24)
    for x, z in ((2.8, 0.45), (3.9, 0.35)):
        cyl((x, -3.0, z), 0.95, 0.3, P["gold"], axis="Y", seg=24)
    cyl((1.2, -4.6, 0.7), 0.9, 0.3, P["gold"], axis="Y", seg=24)


def m_tag(P):
    pts = []
    for i in range(15):
        t = math.radians(200 + (140 * i / 14))
        pts.append((-3.2 * math.cos(t) * 0 + 3.4 * math.cos(math.radians(200 + 140 * i / 14)), 0.0, 6.2 + 2.2 * math.sin(math.radians(200 + 140 * i / 14)) * 0 + (3.0 * math.sin(math.radians(200 + 140 * i / 14)) + 3.0)))
    for p in pts:
        sph(p, 0.22, P["steel"], seg=10)
    for x, z, rz in ((-0.9, 2.2, 6), (1.2, 2.0, -5)):
        box((x, 0, z), (3.0, 0.4, 4.6), P["rubber"], 0.5, rot=(0, 0, rz))
        box((x, -0.1, z), (2.6, 0.4, 4.2), P["steel_l"], 0.5, rot=(0, 0, rz))
        for k in range(4):
            box((x, -0.35, z + 1.4 - k * 0.8), (1.9 - (k % 2) * 0.5, 0.12, 0.2), P["steel_d"], 0.03, rot=(0, 0, rz))
        cyl((x - 0.1 * math.sin(math.radians(rz)), 0, z + 2.2), 0.3, 0.5, P["black"], axis="Y", seg=12)


def m_crate(P):
    for x in (-6.2, 6.2):
        box((x, 0, 7.0), (1.6, 1.8, 14.0), P["wood_d"], 0.2)
    for z in (1.9, 5.5, 9.1, 12.5):
        box((0, -0.6, z), (13.4, 1.3, 3.2), P["wood"], 0.25)
    box((0, -1.3, 13.2), (14.0, 0.5, 1.6), P["wood_d"], 0.12)
    box((0, -1.3, 0.8), (14.0, 0.5, 1.6), P["wood_d"], 0.12)
    brace = math.degrees(math.atan2(14.0 - 3.2, 12.4))
    box((0, -1.2, 7.0), (1.5, 0.6, 16.4), P["wood_l"], 0.12, rot=(0, brace * 1.0, 0))
    for x in (-6.2, 6.2):
        for z in (1.2, 4.8, 8.4, 12.2):
            sph((x, -1.45, z), 0.26, P["steel_d"], seg=10)


def m_barrel(P):
    cyl((0, 0, 7.5), 4.9, 15.0, P["barrel"], bevel=0.18, seg=48)
    for z in (3.3, 7.5, 11.7):
        tor((0, 0, z), 4.9, 0.45, P["barrel"], "Z", seg=48)
    cyl((0, 0, 14.8), 5.0, 0.7, P["steel_d"], bevel=0.12, seg=48)
    cyl((0, 0, 0.35), 5.0, 0.7, P["steel_d"], bevel=0.12, seg=48)
    # znak ostrzegawczy: żółty romb z czarnym płomieniem
    prism([(0, 2.6), (2.6, 0), (0, -2.6), (-2.6, 0)], 0.15, (0, -4.9, 8.9), P["yellow"], rot=(0, 0, 0), bevel=0.04)
    prism([(0, 1.7), (1.0, 0.1), (0.35, 0.1), (0.9, -1.5), (-0.9, -0.4), (-0.3, -0.4), (-1.0, 0.7)], 0.15, (0, -5.0, 8.9), P["black"], bevel=0.02)
    cyl((-1.6, 0, 15.3), 0.55, 0.5, P["steel"], seg=16)


def m_rack(P):
    box((0, 0, 18.0), (48.0, 2.4, 36.0), P["wood_d"], 0.5)
    for i in range(4):
        box((-18.0 + i * 12.0, -1.3, 18.0), (11.4, 0.5, 33.0), P["wood"], 0.25)
    box((0, -1.9, 1.0), (48.0, 1.2, 2.2), P["wood_d"], 0.2)
    box((0, -1.9, 35.0), (48.0, 1.2, 2.2), P["wood_d"], 0.2)
    # kołyska pod broń: półka z wargami
    box((0, -2.2, 9.4), (21.0, 1.8, 1.4), P["steel"], 0.25)
    for x in (-10.0, 10.0):
        box((x, -2.2, 12.2), (1.4, 1.8, 4.2), P["steel"], 0.25)
    for x in (-8.0, 8.0):
        box((x, -2.0, 7.4), (0.8, 1.2, 2.6), P["steel_d"], 0.1)
    box((0, -1.95, 5.4), (16.0, 0.4, 3.0), P["brass"], 0.12)
    for x in (-6.5, -2.2, 2.2, 6.5):
        box((x, -2.2, 5.4), (2.6, 0.12, 0.3), P["black"], 0.03)
    for x in (-21.2, 21.2):
        for z in (4.0, 32.0):
            sph((x, -1.8, z), 0.55, P["steel_d"], seg=12)


def m_tools_wall(P):
    # młotek (całość ~14 wysoka — jak na starej ścianie warsztatu)
    cyl((-17.0, -1.0, 6.5), 0.55, 11.0, P["wood_l"], bevel=0.1, seg=16)
    box((-17.0, -1.0, 13.3), (7.0, 2.4, 3.0), P["steel"], 0.35)
    box((-17.0, -1.0, 14.9), (7.0, 2.4, 0.4), P["steel_d"], 0.1)
    # klucz z okrągłą głowicą
    tube([(-5.0, -1.0, 0.8), (-5.0, -1.0, 11.5)], 0.5, P["steel"], res=8)
    tor((-5.0, -1.0, 13.2), 1.9, 0.5, P["steel"], "Y", seg=32)
    box((-5.0, -1.0, 14.8), (1.2, 1.2, 1.4), P["black"], 0.1)
    # piła: ząbkowane ostrze + drewniana rączka
    teeth = [(0.0, 2.0), (0.0, 0.0)]
    n = 18
    for i in range(n):
        teeth.append((i * 14.0 / n + 0.4, 0.0))
        teeth.append((i * 14.0 / n + 0.8, 1.0))
        teeth.append((i * 14.0 / n + 1.0, 0.0))
    teeth += [(14.0, 0.0), (14.0, 4.6), (0.0, 4.6)]
    prism(teeth, 0.25, (6.0, -1.0, 8.0), P["steel_l"], bevel=0.04)
    box((4.6, -1.0, 10.3), (3.8, 1.2, 4.6), P["wood"], 0.4)
    # lampka robocza: ramię i klosz
    tube([(23.0, -1.0, 0.5), (23.0, -1.0, 11.0), (24.5, -1.0, 14.0)], 0.5, P["black"])
    cyl((25.6, -1.0, 15.0), 3.6, 2.8, P["yellow"], r2=1.8, seg=32, bevel=0.12, rot=(0, 28, 0))
    sph((25.6, -1.0, 13.9), 0.9, P["bulb_e"])


def m_lamp(P):
    tube([(0, 0, 14.0), (0, 0, 8.5)], 0.22, P["black"], res=6)
    cyl((0, 0, 14.2), 1.4, 0.8, P["steel_d"])
    cyl((0, 0, 6.8), 4.8, 3.4, P["olive_d"], r2=1.6, bevel=0.15, seg=40)
    sph((0, 0, 4.6), 1.5, P["bulb_e"], seg=24)
    cyl((0, 0, 7.4), 1.3, 1.0, P["steel"])
    for a in range(0, 360, 60):
        t = math.radians(a)
        tube([(math.cos(t) * 0.9, math.sin(t) * 0.9, 5.0), (math.cos(t) * 1.8, math.sin(t) * 1.8, 3.2), (math.cos(t) * 1.0, math.sin(t) * 1.0, 3.0)], 0.07, P["steel_d"], res=3)


def m_bones(P):
    # czaszka z profilu (kopuła, pysk z zębami, żuchwa, oczodół) + kręgosłup i dwa żebra ciągnące się w prawo (jak stary szkic z props.png)
    sph((-3.2, 0, 3.5), 2.5, P["bone"], (1.1, 0.9, 1.0), seg=32)
    box((-0.4, 0, 2.5), (3.6, 1.8, 1.8), P["bone"], 0.45)                   # pysk
    box((-0.9, 0, 1.0), (3.6, 1.6, 0.9), P["bone_d"], 0.3)                  # żuchwa
    for i in range(5):
        box((-2.0 + i * 0.62, -0.85, 1.65), (0.34, 0.2, 0.7), P["bone"], 0.06)
    sph((-3.4, -2.0, 3.9), 1.0, P["black"], (1, 0.35, 1.15), seg=16)        # oczodół
    sph((0.9, -1.0, 3.0), 0.35, P["black"], (1, 0.4, 1), seg=12)            # nozdrze
    for i in range(7):
        x = 2.2 + i * 1.5
        sph((x, 0, 0.8 + 0.25 * math.sin(i * 1.3)), 0.62, P["bone_d"], (1, 1.1, 0.85), seg=14)
    for x in (3.6, 6.6):
        tube([(x, 0.2, 1.0), (x + 0.5, -0.9, 2.3), (x + 1.7, -1.1, 3.2)], 0.28, P["bone"])


def m_reeds(P):
    import random
    rnd = random.Random(7)
    for i in range(9):
        x0 = -3.4 + i * 0.85 + rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(9.0, 14.5)
        lean = rnd.uniform(-2.2, 2.2)
        m = P["reed"] if i % 3 else P["reed_dry"]
        tube([(x0, 0, 0.0), (x0 + lean * 0.3, 0, h * 0.5), (x0 + lean, 0, h * 0.85), (x0 + lean * 1.5, 0, h)], 0.2, m, res=4)
        if i in (2, 6):
            cyl((x0 + lean * 1.4, 0, h * 0.86), 0.5, 2.6, P["cattail"], bevel=0.1, seg=16)


def m_board(P):
    # tablica z odprawą: korek w drewnianej ramie, przypięte kartki i czerwony sznurek (jak w kryjówce z horroru)
    box((0, 0, 3.0), (4.0, 1.4, 6.0), P["wood_d"], 0.2)
    box((0, 0, 23.0), (60.0, 1.8, 34.0), P["wood_d"], 0.5)
    box((0, -0.95, 23.0), (56.0, 0.8, 30.0), P["cork"], 0.2)
    box((0, -1.05, 38.0), (56.0, 0.7, 2.0), P["cork"], 0.1)
    papers = [(-15.5, 24.0, 13.0, 16.0, 2.0), (0.0, 25.0, 12.0, 14.0, -2.5), (15.0, 23.0, 14.0, 17.0, 3.0), (-5.0, 12.5, 18.0, 9.0, -1.5)]
    pins = []
    for i, (cx, cz, w, h, rz) in enumerate(papers):
        box((cx, -1.45 - i * 0.04, cz), (w, 0.12, h), P["paper"], 0.05, rot=(0, rz, 0))
        for k in range(3):
            lw = w - 3.0 - (k % 2) * 2.0
            box((cx - (w - 3.0 - lw) * 0.5 * 0.0, -1.58 - i * 0.04, cz + h * 0.5 - 4.0 - k * 2.6), (lw, 0.1, 0.7), P["ink"], 0.02, rot=(0, rz, 0))
        px, pz = cx, cz + h * 0.5 - 1.3
        sph((px, -1.9 - i * 0.04, pz), 0.75, P["red"], seg=20)
        sph((px - 0.25, -2.5 - i * 0.04, pz + 0.3), 0.2, P["white"], seg=8)
        pins.append((px, -1.9 - i * 0.04, pz))
    for a, b in zip(pins, pins[1:] + pins[:1]):
        tube([(a[0], a[1] - 0.2, a[2]), ((a[0] + b[0]) * 0.5, a[1] - 0.6, (a[2] + b[2]) * 0.5 - 1.2), (b[0], b[1] - 0.2, b[2])], 0.1, P["red_d"], res=3)


def m_results_board(P):
    # tablica wyników: drewniana rama, zielonkawa łupkowa płyta z rozmazami kredy, półka z kredą i gąbką
    box((0, 0, 33.0), (116.0, 2.4, 66.0), P["wood_d"], 0.7)
    box((0, -1.35, 35.0), (112.0, 0.9, 58.0), P["slate"], 0.3)
    box((0, -2.4, 4.0), (116.0, 3.4, 2.0), P["wood"], 0.4)
    box((0, -1.2, 5.6), (116.0, 1.0, 1.6), P["wood_d"], 0.2)
    for x, c in ((-6.0, "white"), (-3.0, "white"), (16.0, "yellow")):
        cyl((x, -2.4, 5.8), 0.5, 4.0 if c == "white" else 2.4, P[c], axis="X", seg=12, bevel=0.05)
    box((38.0, -2.2, 6.4), (9.0, 2.2, 2.2), P["felt"], 0.5)
    for x in (-54.0, 54.0):
        for z in (6.0, 62.0):
            sph((x, -1.4, z), 0.6, P["steel_d"], seg=12)


def m_range_target(P):
    # manekin strzelnicy: sylwetka z płyty (głowa-krążek, tułów), tarcze malowane pierścieniami, podpórki
    box((0, 0, 12.0), (14.0, 1.4, 24.0), P["ply"], 0.4)
    cyl((0, 0.2, 29.0), 6.0, 1.4, P["ply"], axis="Y", seg=40, bevel=0.2)
    box((0, 0, 24.5), (3.0, 1.2, 3.0), P["ply"], 0.2)
    for r, m, dy in ((4.6, "paper", -0.8), (3.2, "red_d", -0.9), (2.0, "paper", -1.0), (0.9, "red", -1.1)):
        cyl((0, dy - 0.3, 29.0), r, 0.12, P[m], axis="Y", seg=36, bevel=0.01)
    for r, m, dy in ((4.8, "paper", -0.75), (3.4, "red_d", -0.85), (2.1, "paper", -0.95), (0.9, "red", -1.05)):
        cyl((0, dy - 0.3, 14.0), r, 0.12, P[m], axis="Y", seg=36, bevel=0.01)
    tube([(-4.0, 1.0, 1.0), (-2.5, 3.5, 9.0)], 0.5, P["wood_d"], res=6)
    tube([(4.0, 1.0, 1.0), (2.5, 3.5, 9.0)], 0.5, P["wood_d"], res=6)
    box((0, 0.7, 1.0), (16.0, 3.0, 2.0), P["wood_d"], 0.3)


def m_range_sign(P):
    # tablica strzelnicy na słupku (napis „RANGE" rysuje gra)
    box((0, 0.3, 11.5), (2.0, 1.2, 23.0), P["wood_d"], 0.25)
    box((0, 0, 29.0), (34.0, 1.6, 11.0), P["sign_dk"], 0.4)
    box((0, -0.9, 29.0), (32.0, 0.5, 9.0), P["sign_in"], 0.2)
    for x in (-15.0, 15.0):
        for z in (25.0, 33.0):
            sph((x, -0.9, z), 0.4, P["steel_d"], seg=10)


# nazwa → (budowniczy, px na piksel świata)
MODELS = {
    "frag": (m_frag, 32), "phos": (m_phos, 32), "smoke": (m_smoke, 32), "mine": (m_mine, 32), "charge": (m_charge, 32),
    "medkit": (m_medkit, 32), "defib": (m_defib, 32), "scanner": (m_scanner, 32),
    "flare": (m_flare, 32), "flare_stuck": (lambda P: m_flare(P, True), 32), "flare_box": (m_flare_box, 32),
    "supply": (m_supply, 32), "ammo": (m_ammo, 32), "cache": (m_cache, 32), "stash": (m_stash, 32), "tag": (m_tag, 32),
    "bones": (m_bones, 32), "reeds": (m_reeds, 32), "board": (m_board, 16), "results_board": (m_results_board, 12), "range_target": (m_range_target, 24), "range_sign": (m_range_sign, 24), "crate": (m_crate, 24), "barrel": (m_barrel, 24), "rack": (m_rack, 16), "tools_wall": (m_tools_wall, 20), "lamp": (m_lamp, 24),
}

# ---------------------------------------------------------------- render

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
try:
    sc.eevee.taa_render_samples = 48
except Exception:
    pass
sc.world = bpy.data.worlds.new("w")
P = palette()
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.rotation_euler = (math.radians(90), 0, 0)
manifest = {}
if os.path.exists(os.path.join(OUT, "items.json")):
    manifest = json.load(open(os.path.join(OUT, "items.json")))

for name, (builder, ppw) in MODELS.items():
    if ONLY and name not in ONLY:
        continue
    clear()
    builder(P)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for ob in OBJS:
        eo = ob.evaluated_get(dg)
        me = eo.to_mesh()
        for v in me.vertices:
            w = eo.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
        eo.to_mesh_clear()
    wpx, hpx = (hi.x - lo.x), (hi.z - lo.z)
    FW, FH = int(math.ceil(wpx * ppw)) + 2 * PAD, int(math.ceil(hpx * ppw)) + 2 * PAD
    sc.render.resolution_x, sc.render.resolution_y = FW, FH
    cam.data.ortho_scale = max(FW, FH) / ppw
    cx, cz = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
    cam.location = (cx, -20.0, cz)
    for passname, suffix, vt in (("alb", "", "Standard"), ("nrm", "_nw", "Raw"), ("emi", "_em", "Standard"), ("ao", "_ao", "Standard")):
        for m in P.values():
            set_pass(m, passname)
        sc.view_settings.view_transform = vt
        sc.render.filepath = os.path.join(OUT, name + suffix + ".png")
        bpy.ops.render.render(write_still=True)
    # stopy: dolna krawędź bryły (z = lo.z) leży PAD px nad dołem ramki; środek poziomy ramki = cx
    manifest[name] = {"w": FW, "h": FH, "ppw": ppw, "foot": [FW / 2.0 + (0.0), FH - PAD], "bbox": [round(wpx, 2), round(hpx, 2)]}
    print("OK", name, FW, FH)
json.dump(manifest, open(os.path.join(OUT, "items.json"), "w"), indent=1)
print("DONE-ITEMS")
