"""Modele 3D do HUD-u, których brakuje w grze: latarka (L), wabik (Q, megafon / nadajnik hałasu) i zestaw czyszczący (Alt).

    blender -b --factory-startup -P prototype/tools/make_hud_models.py            # zapis do prototype/art/items3d
    blender -b --factory-startup -P prototype/tools/make_hud_models.py -- --out=<katalog> [--only=lure|flashlight|cleankit]
Potem ikony: godot --path prototype --rendering-driver opengl3 --script tools/bake_hud_icons.gd

Jednostka = metr, oś długa modelu wzdłuż +X (jak bronie: lufa w prawo), wylot / głowica w stronę +X.
Materiały to czyste PBR (Principled: kolor, metaliczność, chropowatość, emisja), więc eksport GLB wystarcza,
bez wypalania tekstur. Ikony renderuje ten sam skrypt Godota co dla pozostałych modeli (spójne światło).
"""
import math
import os
import sys

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "items3d")
for a in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
    if a.startswith("--out="):
        OUT = a[6:]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metal=0.0, rough=0.5, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def finish(obj, material, bevel=0.0015, smooth=True):
    obj.data.materials.append(material)
    if bevel > 0:
        md = obj.modifiers.new("bevel", "BEVEL")
        md.width = bevel
        md.segments = 3
        md.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if smooth:
        bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def cyl(name, r, length, x, material, axis="X", bevel=0.0015, segs=48, r2=None):
    """Walec (albo ścięty stożek, gdy r2) o osi wzdłuż X, środek w x."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=length)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=segs, radius1=r, radius2=r2, depth=length)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler[1] = math.radians(90)          # oś Z → X
    o.location = (x, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(o, material, bevel)


def box(name, size, loc, material, bevel=0.002, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.location = loc
    o.rotation_euler = [math.radians(v) for v in rot]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(o, material, bevel)


def torus(name, major, minor, x, material, segs=48):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segs, minor_segments=14)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler[1] = math.radians(90)
    o.location = (x, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(o, material, 0.0)


def export(filename):
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("OK", path)


# ---------------------------------------------------------------- latarka (L)
def flashlight():
    reset()
    paint = mat("fl_paint", (0.15, 0.18, 0.10), 0.35, 0.62)       # oliwkowy lakier na metalu
    steel = mat("fl_steel", (0.42, 0.43, 0.41), 0.85, 0.48)
    dark = mat("fl_dark", (0.05, 0.05, 0.05), 0.1, 0.75)
    rubber = mat("fl_rubber", (0.09, 0.09, 0.085), 0.0, 0.9)
    orange = mat("fl_orange", (0.78, 0.33, 0.06), 0.0, 0.55)
    lens = mat("fl_lens", (0.80, 0.66, 0.38), 0.0, 0.2, emit=(1.0, 0.72, 0.32), emit_strength=0.9)

    cyl("body", 0.0215, 0.150, 0.0, paint)
    for i in range(10):                                           # radełkowany uchwyt przy tylnej części
        cyl("grip%d" % i, 0.0228, 0.0065, -0.062 + i * 0.0105, rubber, bevel=0.0008, segs=36)
    cyl("tail", 0.0235, 0.016, -0.0835, dark)
    torus("lanyard", 0.0075, 0.0017, -0.0975, steel, segs=24).location.z = 0.0                # ucho smyczy
    cyl("neck", 0.0245, 0.012, 0.081, steel)
    cyl("head", 0.0245, 0.050, 0.112, paint, r2=0.0385)
    cyl("bezel", 0.0395, 0.009, 0.1395, steel, bevel=0.0012)
    cyl("reflector", 0.0345, 0.006, 0.1405, dark, bevel=0.0004)
    cyl("lens", 0.0305, 0.002, 0.1445, lens, bevel=0.0)
    box("switch_base", (0.026, 0.015, 0.008), (0.032, 0.0, 0.0245), dark, 0.0015)
    box("switch", (0.014, 0.008, 0.007), (0.032, 0.0, 0.0295), orange, 0.0015)
    export("flashlight.glb")


# ---------------------------------------------------------------- wabik (Q): megafon / nadajnik hałasu
def lure():
    reset()
    shell = mat("lu_shell", (0.17, 0.21, 0.11), 0.3, 0.65)         # oliwkowy lakier
    red = mat("lu_red", (0.48, 0.06, 0.04), 0.15, 0.55)
    steel = mat("lu_steel", (0.42, 0.43, 0.41), 0.85, 0.5)
    dark = mat("lu_dark", (0.05, 0.05, 0.05), 0.1, 0.7)
    rubber = mat("lu_rubber", (0.1, 0.1, 0.095), 0.0, 0.9)
    cream = mat("lu_cream", (0.62, 0.58, 0.45), 0.0, 0.75)

    # czasza: stożek pusty w środku (grubość 3 mm)
    bpy.ops.mesh.primitive_cone_add(vertices=64, radius1=0.04, radius2=0.115, depth=0.19, end_fill_type="NOTHING")
    bell = bpy.context.active_object
    bell.name = "bell"
    bell.rotation_euler[1] = math.radians(90)
    bell.location = (0.14, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    sd = bell.modifiers.new("solid", "SOLIDIFY")
    sd.thickness = 0.003
    sd.offset = -1.0
    finish(bell, shell, 0.0)
    torus("rim", 0.1165, 0.0045, 0.2345, red)                     # czerwona obręcz na brzegu
    cyl("band", 0.0735, 0.014, 0.165, cream, bevel=0.001, r2=0.0765)                # jasny pas na czaszy
    cyl("driver", 0.058, 0.060, 0.012, dark, r2=0.045)             # obudowa głośnika za czaszą
    cyl("throat", 0.036, 0.022, 0.055, steel, r2=0.040)
    cyl("mouth", 0.032, 0.040, -0.022, rubber, r2=0.052)           # ustnik z gumowym kołnierzem
    # chwyt pistoletowy i spust
    box("grip", (0.034, 0.042, 0.115), (0.03, 0.0, -0.075), rubber, 0.006, rot=(0, 10, 0))
    box("guard", (0.052, 0.006, 0.012), (0.045, 0.0, -0.021), dark, 0.002)
    box("trigger", (0.012, 0.008, 0.026), (0.05, 0.0, -0.036), red, 0.002, rot=(0, -12, 0))
    box("cap", (0.040, 0.046, 0.012), (0.0275, 0.0, -0.134), steel, 0.003)
    export("lure.glb")


# ---------------------------------------------------------------- zestaw czyszczący (Alt): płócienne etui z przyborami

def cleankit():
    reset()
    canvas = mat("ck_canvas", (0.23, 0.27, 0.12), rough=0.96)
    trim = mat("ck_binding", (0.10, 0.13, 0.065), rough=0.9)
    stitch = mat("ck_stitch", (0.49, 0.44, 0.28), rough=0.9)
    steel = mat("ck_steel", (0.50, 0.53, 0.54), metal=0.85, rough=0.35)
    brass = mat("ck_brass", (0.56, 0.31, 0.075), metal=0.75, rough=0.58)
    rubber = mat("ck_rubber", (0.045, 0.05, 0.04), rough=0.85)
    bottle = mat("ck_oil", (0.16, 0.22, 0.12), metal=0.25, rough=0.55)
    cream = mat("ck_label", (0.69, 0.63, 0.44), rough=0.86)
    # Przód etui w -Y Blendera (+Z Godota); wycior i szczotka wystają z kieszeni.
    box("canvas_pouch", (0.27, 0.052, 0.14), (0, 0, 0.085), canvas, 0.012)
    box("open_flap", (0.27, 0.014, 0.075), (0, 0.024, 0.182), canvas, 0.010, rot=(10, 0, 0))
    box("pocket_binding", (0.255, 0.009, 0.012), (0, -0.029, 0.151), trim, 0.003)
    for x in (-0.13, 0.13):
        box("side_binding", (0.009, 0.01, 0.12), (x, -0.026, 0.082), trim, 0.002)
    for x in (-0.065, 0.016, 0.095):
        box("pocket_seam", (0.0025, 0.004, 0.102), (x, -0.029, 0.079), stitch, 0.0005)
    # Oliwiarka z wąską szyjką i czytelną etykietą — żadnych symboli apteczki.
    box("oil_bottle", (0.048, 0.035, 0.065), (-0.097, -0.017, 0.172), bottle, 0.006)
    cap = cyl("oil_cap", 0.013, 0.012, 0, rubber, segs=20)
    cap.rotation_euler[1] = math.radians(-90)
    cap.location = (-0.097, -0.017, 0.211)
    box("oil_label", (0.036, 0.002, 0.024), (-0.097, -0.036, 0.172), cream, 0.001)
    box("label_stripe", (0.026, 0.002, 0.003), (-0.097, -0.0375, 0.173), trim, 0.0004)
    # Dwa segmenty wyciora i szczotka mosiężna.
    for i, x in enumerate((-0.043, -0.020, 0.049)):
        rod = cyl("cleaning_rod_%d" % i, 0.003, 0.178 if i < 2 else 0.146, 0, steel, segs=12, bevel=0.0005)
        rod.rotation_euler[1] = math.radians(-90)
        rod.location = (x, -0.006, 0.153)
    box("rod_t_handle", (0.043, 0.012, 0.012), (-0.043, -0.006, 0.242), rubber, 0.003)
    tip = cyl("threaded_tip", 0.004, 0.012, 0, brass, segs=12, bevel=0.0005)
    tip.rotation_euler[1] = math.radians(-90)
    tip.location = (-0.020, -0.006, 0.244)
    for i in range(12):
        ring = cyl("brush_bristles_%02d" % i, 0.012 if i in range(1, 11) else 0.008, 0.002, 0, brass, segs=16, bevel=0.0003)
        ring.rotation_euler[1] = math.radians(-90)
        ring.location = (0.049, -0.006, 0.219 + i * 0.0025)
    # Szmatki w osobnej kieszeni; pasek etui i metalowe napy.
    for i in range(3):
        box("cotton_patch_%d" % i, (0.038, 0.007, 0.040), (0.109, -0.004 - i * 0.005, 0.155 + i * 0.003), cream, 0.002, rot=(0, 0, i * 4))
    box("closure_strap", (0.017, 0.008, 0.103), (0.007, -0.030, 0.067), trim, 0.002)
    for x in (-0.116, 0.116):
        snap = cyl("snap", 0.004, 0.0025, 0, brass, segs=16, bevel=0.0005)
        snap.rotation_euler[2] = math.radians(90)
        snap.location = (x, -0.032, 0.141)
    export("cleankit.glb")


if "--only=flashlight" in sys.argv:
    flashlight()
elif "--only=cleankit" in sys.argv:
    cleankit()
elif "--only=lure" in sys.argv:
    lure()
else:
    flashlight()
    lure()
    cleankit()
