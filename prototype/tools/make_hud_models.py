"""Modele 3D do HUD-u, których brakuje w grze: latarka (L) i wabik (Q, megafon / nadajnik hałasu).

    blender -b --factory-startup -P prototype/tools/make_hud_models.py            # zapis do prototype/art/items3d
    blender -b --factory-startup -P prototype/tools/make_hud_models.py -- --out=<katalog> [--only=lure|flashlight]
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


if "--only=flashlight" in sys.argv:
    flashlight()
elif "--only=lure" in sys.argv:
    lure()
else:
    flashlight()
    lure()
