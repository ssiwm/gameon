"""Importuje GLB z Tripo do Blendera, wypisuje szkielet/siatkę/tekstury i renderuje podgląd (bok, przód, 3/4).
Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/tripo_inspect.py -- PLIK.glb OUT_PREFIX
"""
import math
import sys

import bpy
from mathutils import Vector

glb, prefix = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
print("INFO meshes", [(m.name, len(m.data.vertices), len(m.data.polygons), [g.name for g in m.vertex_groups][:3]) for m in meshes])
print("INFO armatures", [(a.name, len(a.data.bones)) for a in arms])
if arms:
    print("INFO bones", [b.name for b in arms[0].data.bones])
print("INFO images", [(i.name, i.size[0], i.size[1]) for i in bpy.data.images])
print("INFO materials", [m.name for m in bpy.data.materials])
lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
for m in meshes:
    for c in m.bound_box:
        w = m.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))); hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
print("INFO bbox", tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi))
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.54, 0.64, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
sc.world = w
for name, rot, en in (("key", (math.radians(52), 0, math.radians(-35)), 3.5), ("rim", (math.radians(62), 0, math.radians(150)), 2.2)):
    L = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN")); L.data.energy = en; L.rotation_euler = rot; sc.collection.objects.link(L)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
H = hi.z - lo.z
cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
cam.data.ortho_scale = H * 1.15
sc.render.resolution_x, sc.render.resolution_y = 560, 800
views = {"side": ((-9, cy, lo.z + H / 2), (90, 0, -90)), "front": ((cx, -9, lo.z + H / 2), (90, 0, 0)), "back": ((cx, 9, lo.z + H / 2), (90, 0, 180)), "left": ((9, cy, lo.z + H / 2), (90, 0, 90))}
for n, (loc, rot) in views.items():
    cam.location = loc
    cam.rotation_euler = tuple(math.radians(r) for r in rot)
    sc.render.filepath = f"{prefix}_{n}.png"
    bpy.ops.render.render(write_still=True)
print("DONE-INSPECT")
