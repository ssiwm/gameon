"""Wizualizacja koncepcyjna postaci 2.5D: parametryczny model 3D (płeć × strój) renderowany w Blenderze (toon + obrys).

To prototyp wizualny do planu `CHARACTERS_PLAN.md`, nie docelowy asset: model składa się z prymitywów (kapsuły, elipsoidy, pudełka),
żeby pokazać proporcje, sylwetki płci i trzy stroje oraz styl renderu (cel-shading + obrys odwróconą skorupą).

Uruchomienie (z katalogu repo):
    blender -b --factory-startup -P prototype/tools/concept/char3d_concept.py -- OUT_DIR
Wynik: OUT_DIR/{male,female}_{scavenger,hazmat,medic}.png (poza) oraz turn_{front,three,side,back}.png (obrót jednej postaci).
Arkusz składa char3d_sheet.py (Pillow).
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/char3d"

# ---------------------------------------------------------------- materiały

_mats = {}


def toon(name, rgb, emit=0.0):
    """Cel-shading: Diffuse → ShaderToRGB → rampa 3-stopniowa × kolor bazowy → Emission."""
    key = (name, tuple(rgb), emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    if emit > 0.0:
        em.inputs["Color"].default_value = (*rgb, 1.0)
        em.inputs["Strength"].default_value = emit
    else:
        dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
        dif.inputs["Color"].default_value = (1, 1, 1, 1)
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].position = 0.0
        ramp.color_ramp.elements[0].color = (0.34, 0.36, 0.56, 1)
        ramp.color_ramp.elements[1].position = 0.34
        ramp.color_ramp.elements[1].color = (0.72, 0.74, 0.84, 1)
        e3 = ramp.color_ramp.elements.new(0.70)
        e3.color = (1.0, 1.0, 1.0, 1)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs["B"].default_value = (*rgb, 1.0)
        nt.links.new(dif.outputs["BSDF"], s2r.inputs["Shader"])
        nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mul.inputs["A"])
        nt.links.new(mul.outputs["Result"], em.inputs["Color"])
        em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    _mats[key] = m
    return m


def outline_mat():
    if "outline" in _mats:
        return _mats["outline"]
    m = bpy.data.materials.new("outline")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.04, 0.03, 0.05, 1.0)
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    m.use_backface_culling = True
    _mats["outline"] = m
    return m


# ---------------------------------------------------------------- prymitywy

SC = None
ROOT = None
OUTLINE = 0.013


def _finish(name, mesh, mat, loc=(0, 0, 0), rot=None, scale=(1, 1, 1), outline=True):
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    SC.collection.objects.link(o)
    o.location = loc
    if rot is not None:
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rot
    o.scale = scale
    mesh.materials.append(mat)
    if outline:
        mesh.materials.append(outline_mat())
        sol = o.modifiers.new("ol", "SOLIDIFY")
        sol.thickness = OUTLINE / (sum(scale) / 3.0)        # grubość liczy się w jednostkach lokalnych — kompensujemy skalę obiektu
        sol.offset = 1.0
        sol.use_flip_normals = True
        sol.material_offset = 1
    o.parent = ROOT
    return o


def ellipsoid(name, c, r, mat, rot=None, seg=20, outline=True):
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=1.0)
    bm.to_mesh(m)
    bm.free()
    return _finish(name, m, mat, tuple(c), rot, tuple(r), outline)


def box(name, c, size, mat, rot=None, outline=True, bevel=0.012):
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel / max(size), segments=2, affect="EDGES")
    bm.to_mesh(m)
    bm.free()
    return _finish(name, m, mat, tuple(c), rot, tuple(size), outline)


def limb(name, p, q, r1, r2, mat, outline=True, seg=14):
    """Stożek ścięty od p do q (promień r1 przy p, r2 przy q) z półkulami na końcach nie dodajemy — łączymy elipsoidami w stawach."""
    p, q = Vector(p), Vector(q)
    d = q - p
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r2, radius2=r1, depth=d.length)
    bm.to_mesh(m)
    bm.free()
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return _finish(name, m, mat, tuple((p + q) / 2), rot, (1, 1, 1), outline)


def tube(name, pts, radii, mat, joint=True):
    """Łańcuch segmentów z kulami w stawach."""
    for i in range(len(pts) - 1):
        limb(f"{name}_{i}", pts[i], pts[i + 1], radii[i], radii[i + 1], mat)
    if joint:
        for i, p in enumerate(pts):
            ellipsoid(f"{name}_j{i}", p, (radii[i],) * 3, mat, seg=14)


def ik2(shoulder, target, a, b, pole):
    """Dwukostkowe IK: łokieć/kolano leży w płaszczyźnie (ramię→cel, pole)."""
    s, t = Vector(shoulder), Vector(target)
    d = t - s
    L = min(d.length, (a + b) * 0.999)
    dn = d.normalized()
    x = (a * a - b * b + L * L) / (2 * L)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pv = Vector(pole)
    pv = (pv - dn * pv.dot(dn)).normalized()
    return s + dn * x + pv * h


# ---------------------------------------------------------------- budowa postaci

DZ = -0.115                                              # obniżenie górnej połowy ciała (krótsze nogi, bardziej „komiksowe” proporcje)
SKIN_TONES = {"light": (0.93, 0.72, 0.60), "tan": (0.80, 0.56, 0.40), "dark": (0.45, 0.28, 0.20)}

OUTFITS = {
    "scavenger": dict(label="SCAVENGER", top=(0.36, 0.40, 0.22), top2=(0.28, 0.31, 0.17), pants=(0.50, 0.44, 0.30), boots=(0.20, 0.14, 0.11),
                      gear=(0.42, 0.30, 0.18), accent=(0.78, 0.30, 0.20), gloves=(0.25, 0.20, 0.15)),
    "hazmat": dict(label="HAZMAT TECH", top=(0.92, 0.62, 0.10), top2=(0.78, 0.50, 0.07), pants=(0.88, 0.58, 0.09), boots=(0.14, 0.14, 0.16),
                   gear=(0.30, 0.31, 0.34), accent=(0.45, 0.95, 0.90), gloves=(0.12, 0.12, 0.13)),
    "medic": dict(label="FIELD MEDIC", top=(0.80, 0.82, 0.84), top2=(0.23, 0.30, 0.45), pants=(0.20, 0.25, 0.37), boots=(0.13, 0.13, 0.15),
                  gear=(0.55, 0.58, 0.60), accent=(0.86, 0.14, 0.14), gloves=(0.80, 0.82, 0.84)),
}
METAL = (0.20, 0.21, 0.24)
HAIR_M = (0.16, 0.11, 0.08)
HAIR_F = (0.55, 0.24, 0.12)


def build(gender, outfit, skin="light"):
    """Postać zwrócona w prawo (+X), stojąca na z=0, w pozie „broń w gotowości”."""
    f = gender == "female"
    o = OUTFITS[outfit]
    sk = toon("skin", SKIN_TONES[skin])
    top, top2 = toon("top", o["top"]), toon("top2", o["top2"])
    pants, boots = toon("pants", o["pants"]), toon("boots", o["boots"])
    gear, acc = toon("gear", o["gear"]), toon("accent", o["accent"])
    gloves, metal = toon("gloves", o["gloves"]), toon("metal", METAL)
    hair = toon("hair", HAIR_F if f else HAIR_M)
    k = 0.94 if f else 1.0                                   # skala wzrostu
    sh_w = 0.165 if f else 0.20                              # połowa rozstawu barków
    hip_w = 0.115 if f else 0.095
    bulk = 1.14 if outfit == "hazmat" else 1.0

    # --- nogi
    hip_z = 0.835 * k
    thigh, shin = 0.415 * k, 0.415 * k
    for side, ty, ang, flex in ((-1, -hip_w, 13.0, 7.0), (1, hip_w, -13.0, 20.0)):
        hip = Vector((-0.01, ty, hip_z))
        a = math.radians(ang)
        knee = hip + Vector((math.sin(a) * thigh, 0, -math.cos(a) * thigh))
        b = a - math.radians(flex)
        ankle = knee + Vector((math.sin(b) * shin, 0, -math.cos(b) * shin))
        rt = (0.098 if f else 0.102) * bulk
        tube(f"leg{side}", [hip, knee, ankle], [rt, 0.078 * bulk, 0.060 * bulk], pants)
        if outfit == "hazmat":
            ellipsoid("kneepad", knee + Vector((0.05, 0, 0.0)), (0.05, 0.07, 0.06), gear)
        if outfit == "medic" and side == -1:
            box("thigh_pouch", knee + Vector((0.0, -0.075, 0.16 * k)), (0.10, 0.045, 0.14), gear, rot=Quaternion((0, 1, 0), math.radians(-ang * 0.6)))
        # but
        bz = ankle + Vector((0.07, 0, -0.065))
        box("boot", bz, (0.26, 0.12, 0.12), boots, rot=Quaternion((0, 1, 0), -b * 0.35))
        box("boot_sole", bz + Vector((0.01, 0, -0.06)), (0.28, 0.125, 0.03), metal, rot=Quaternion((0, 1, 0), -b * 0.35), outline=False)
        limb("boot_cuff", ankle + Vector((0, 0, 0.10)), ankle, 0.062 * bulk, 0.060 * bulk, boots)

    # --- tułów
    lean = math.radians(7.0)
    pelvis = Vector((-0.01, 0, hip_z + 0.03))
    ellipsoid("pelvis", pelvis, ((0.15 if f else 0.14) * bulk, (0.19 if f else 0.17) * bulk, 0.11), pants)
    chest = Vector((0.03, 0, (1.24 * k + DZ)))
    rq = Quaternion((0, 1, 0), lean)
    cw = (0.15 if f else 0.175) * bulk
    ellipsoid("torso", chest, (cw * 1.08, sh_w * 1.15 * bulk, 0.30 * k), top, rot=rq)
    waist = Vector((0.0, 0, (1.06 * k + DZ)))
    ellipsoid("waist", waist, ((0.12 if f else 0.14) * bulk, (0.135 if f else 0.16) * bulk, 0.12), top2, rot=rq)
    # pas
    ellipsoid("belt", pelvis + Vector((0.0, 0, 0.09)), (0.155 * bulk, 0.18 * bulk if not f else 0.175 * bulk, 0.035), gear, outline=False)
    shoulder_z = (1.42 * k + DZ)
    sh = {-1: Vector((0.045, -sh_w, shoulder_z)), 1: Vector((0.045, sh_w, shoulder_z))}

    # --- strój: elementy
    if outfit == "scavenger":
        ellipsoid("collar", Vector((0.05, 0, (1.52 * k + DZ))), (0.12, 0.15, 0.06), top2, rot=rq)
        ellipsoid("scarf", Vector((0.06, 0, (1.54 * k + DZ))), (0.095, 0.115, 0.05), acc)
        box("pack", Vector((-0.20, 0.0, (1.22 * k + DZ))), (0.17, 0.27, 0.36 * k), gear, rot=Quaternion((0, 1, 0), -lean))
        ellipsoid("bedroll", Vector((-0.22, 0.0, (1.48 * k + DZ))), (0.075, 0.15, 0.075), toon("roll", (0.30, 0.34, 0.40)))
        box("chest_pocket", Vector((0.17, -0.07, (1.27 * k + DZ))), (0.04, 0.10, 0.10), top2, rot=rq)
    elif outfit == "hazmat":
        ellipsoid("collar", Vector((0.04, 0, (1.52 * k + DZ))), (0.14, 0.17, 0.07), top2, rot=rq)
        limb("tank_a", Vector((-0.22, -0.07, (1.04 * k + DZ))), Vector((-0.22, -0.07, (1.46 * k + DZ))), 0.07, 0.07, gear)
        limb("tank_b", Vector((-0.22, 0.07, (1.04 * k + DZ))), Vector((-0.22, 0.07, (1.46 * k + DZ))), 0.07, 0.07, gear)
        box("strap", Vector((0.09, 0, (1.30 * k + DZ))), (0.05, 0.34, 0.05), gear, rot=Quaternion((0, 1, 0), lean + 0.5), outline=False)
        ellipsoid("patch", Vector((0.19, -0.10, (1.34 * k + DZ))), (0.02, 0.05, 0.05), acc, outline=False)
    else:   # medic
        box("vest", Vector((0.04, 0, (1.28 * k + DZ))), (0.20, 0.36, 0.34 * k), toon("vest", o["top2"]), rot=rq)
        box("cross_v", Vector((0.145, -0.115, (1.31 * k + DZ))), (0.012, 0.035, 0.11), acc, outline=False, bevel=0.002)
        box("cross_h", Vector((0.147, -0.115, (1.31 * k + DZ))), (0.012, 0.11, 0.035), acc, outline=False, bevel=0.002)
        box("bag", Vector((-0.20, 0.0, (1.20 * k + DZ))), (0.15, 0.30, 0.30 * k), gear, rot=Quaternion((0, 1, 0), -lean))
        box("bag_cross", Vector((-0.282, 0.0, (1.22 * k + DZ))), (0.01, 0.08, 0.025), acc, outline=False, bevel=0.002)
        box("bag_cross2", Vector((-0.282, 0.0, (1.22 * k + DZ))), (0.01, 0.025, 0.08), acc, outline=False, bevel=0.002)
        ellipsoid("collar", Vector((0.04, 0, (1.52 * k + DZ))), (0.11, 0.14, 0.05), top, rot=rq)

    # --- broń (szkic karabinu) i ramiona
    rz = (1.27 * k + DZ)
    box("rifle_body", Vector((0.34, -0.01, rz)), (0.56, 0.065, 0.10), metal, rot=Quaternion((0, 1, 0), -0.04))
    box("rifle_stock", Vector((0.02, -0.01, rz - 0.01)), (0.18, 0.06, 0.12), toon("stock", (0.30, 0.22, 0.15)), rot=Quaternion((0, 1, 0), -0.04))
    limb("rifle_barrel", Vector((0.60, -0.01, rz + 0.012)), Vector((0.88, -0.01, rz + 0.016)), 0.018, 0.018, metal)
    box("rifle_mag", Vector((0.33, -0.01, rz - 0.13)), (0.07, 0.05, 0.16), metal, rot=Quaternion((0, 1, 0), 0.25))
    box("rifle_sight", Vector((0.36, -0.01, rz + 0.075)), (0.16, 0.03, 0.03), metal, outline=False)
    hand_near, hand_far = Vector((0.20, -0.07, rz - 0.07)), Vector((0.53, 0.04, rz - 0.04))
    ua, fa = 0.27 * k, 0.26 * k
    for side, hand in ((-1, hand_near), (1, hand_far)):
        s = sh[side]
        elbow = ik2(s, hand, ua, fa, (-0.15, side * 0.8, -1.0))
        ra = 0.072 * bulk
        tube(f"arm{side}", [s, elbow, hand], [ra * 1.1, 0.060 * bulk, 0.050], top if outfit != "medic" else top2)
        ellipsoid(f"hand{side}", hand, (0.060, 0.052, 0.058), gloves)
    ellipsoid("shoulder_n", sh[-1], (0.075 * bulk,) * 3, top if outfit != "medic" else top2)
    ellipsoid("shoulder_f", sh[1], (0.075 * bulk,) * 3, top if outfit != "medic" else top2)

    # --- głowa
    hz = (1.66 * k + DZ)
    hc = Vector((0.075, 0, hz + 0.01))
    limb("neck", Vector((0.05, 0, (1.46 * k + DZ))), Vector((0.065, 0, hz - 0.06)), 0.055, 0.05, sk)
    ellipsoid("head", hc, (0.135, 0.125 if f else 0.13, 0.158), sk, seg=24)
    ellipsoid("jaw", hc + Vector((0.03, 0, -0.082)), (0.100, 0.100 if f else 0.108, 0.082), sk)
    ellipsoid("nose", hc + Vector((0.13, 0, -0.014)), (0.033, 0.024, 0.035), sk, outline=False)
    if outfit != "hazmat":
        ellipsoid("eye", hc + Vector((0.10, -0.088, 0.03)), (0.017, 0.012, 0.024), toon("eye", (0.05, 0.04, 0.06)), outline=False)
        ellipsoid("brow", hc + Vector((0.095, -0.094, 0.066)), (0.036, 0.009, 0.009), hair, outline=False)
        box("mouth", hc + Vector((0.12, -0.035, -0.077)), (0.014, 0.053, 0.009), toon("mouth", (0.45, 0.20, 0.20)), outline=False, bevel=0.001)
    # fryzura / nakrycie głowy
    if outfit == "scavenger":
        ellipsoid("cap", hc + Vector((-0.005, 0, 0.055)), (0.148, 0.140, 0.118), toon("cap", o["top2"]))
        box("brim", hc + Vector((0.135, 0, 0.042)), (0.13, 0.20, 0.02), toon("cap", o["top2"]), rot=Quaternion((0, 1, 0), 0.12))
        if f:   # kucyk pod czapką
            tube("pony", [hc + Vector((-0.12, 0, 0.0)), hc + Vector((-0.20, 0, -0.07)), hc + Vector((-0.23, 0, -0.17))], [0.04, 0.045, 0.03], hair)
        else:
            ellipsoid("hair_b", hc + Vector((-0.09, 0, -0.02)), (0.05, 0.10, 0.09), hair)
    elif outfit == "hazmat":
        ellipsoid("hood", hc + Vector((-0.01, 0, 0.0)), (0.170, 0.160, 0.195), top, seg=24)
        ellipsoid("visor", hc + Vector((0.065, 0, 0.018)), (0.112, 0.136, 0.088), toon("lens", o["accent"], emit=1.6), outline=True)
        limb("filter", hc + Vector((0.12, 0, -0.082)), hc + Vector((0.23, 0, -0.11)), 0.065, 0.052, gear)
        limb("canister", hc + Vector((0.07, -0.12, -0.07)), hc + Vector((0.085, -0.165, -0.115)), 0.038, 0.038, metal)
    else:
        ellipsoid("helmet", hc + Vector((0.0, 0, 0.065)), (0.160, 0.148, 0.118), toon("helmet", (0.84, 0.86, 0.88)))
        box("h_cross_v", hc + Vector((0.065, -0.119, 0.07)), (0.012, 0.012, 0.075), acc, outline=False, bevel=0.002)
        box("h_cross_h", hc + Vector((0.065, -0.119, 0.07)), (0.075, 0.012, 0.012), acc, outline=False, bevel=0.002)
        if f:
            tube("pony", [hc + Vector((-0.12, 0, -0.02)), hc + Vector((-0.19, 0, -0.08)), hc + Vector((-0.20, 0, -0.18))], [0.04, 0.045, 0.03], hair)
        else:
            ellipsoid("hair_b", hc + Vector((-0.09, 0, -0.03)), (0.05, 0.10, 0.08), hair)


# ---------------------------------------------------------------- scena i render

def new_scene():
    global SC, ROOT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    SC = bpy.context.scene
    SC.render.engine = "BLENDER_EEVEE"
    SC.render.film_transparent = True
    SC.render.image_settings.file_format = "PNG"
    SC.render.image_settings.color_mode = "RGBA"
    SC.view_settings.view_transform = "Standard"
    SC.eevee.taa_render_samples = 24
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.72, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    SC.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    SC.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.location = (0.15, -6.0, 0.98)
    cam.rotation_euler = (math.radians(90), 0, 0)
    SC.camera = cam
    for name, rot, en in (("key", (math.radians(55), math.radians(8), math.radians(-62)), 3.4), ("rim", (math.radians(60), 0, math.radians(150)), 2.0)):
        L = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        L.data.energy = en
        L.data.angle = 0.1
        L.rotation_euler = rot
        SC.collection.objects.link(L)
    ROOT = bpy.data.objects.new("root", None)
    SC.collection.objects.link(ROOT)


def render(path, w=560, h=820, yaw=0.0, scale=2.15):
    SC.render.resolution_x, SC.render.resolution_y = w, h
    SC.camera.data.ortho_scale = scale
    ROOT.rotation_euler = (0, 0, math.radians(yaw))
    SC.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDER", path)


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    for gender in ("male", "female"):
        for outfit in OUTFITS:
            new_scene()
            build(gender, outfit, skin="light" if gender == "male" else "tan")
            render(f"{OUT}/{gender}_{outfit}.png")
    # obrót: kobieta w stroju Medyk (przód, 3/4, bok, tył)
    new_scene()
    build("female", "medic", skin="tan")
    for name, yaw in (("front", -90.0), ("three", -45.0), ("side", 0.0), ("back", 90.0)):
        render(f"{OUT}/turn_{name}.png", yaw=yaw)


main()
