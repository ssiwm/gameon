"""Przygotowuje postać 3D (rig Mixamo z Tripo) do renderu w czasie rzeczywistym w grze (spike 3D).

Uruchomienie (z korzenia repo):
    blender -b --factory-startup -P prototype/tools/prep_char3d.py -- art_src/characters/tripo/male_scav_01_rig.glb prototype/art/char3d/male_scav.glb [--faces=6000] [--tex=1024]
Co robi: usuwa śmieciową ikosferę, upraszcza siatkę (Decimate, wagi kości zostają), zostawia tylko mapę koloru
zmniejszoną do --tex px (normalne i ORM pomijamy — postać ma ~100 px wysokości na ekranie), eksportuje GLB (JPEG).
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
FACES = int(next((a.split("=")[1] for a in argv if a.startswith("--faces=")), 6000))
TEX = int(next((a.split("=")[1] for a in argv if a.startswith("--tex=")), 1024))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# śmieci: obiekty bez wag (ikosfera z importu)
for o in list(bpy.data.objects):
    if o.type == "MESH" and len(o.vertex_groups) == 0:
        bpy.data.objects.remove(o, do_unlink=True)

body = next(o for o in bpy.data.objects if o.type == "MESH")
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
bpy.context.view_layer.objects.active = body

# skala: modele Tripo bywają w innej jednostce — sprowadź wysokość do 1,8 m (pozy IK liczone są w metrach)
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
h = max(zs) - min(zs)
if abs(h / 1.8 - 1.0) > 0.25:
    f = 1.8 / h
    print("INFO normalize %.3f -> 1.8 (x%.2f)" % (h, f))
    arm.scale = (f, f, f)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.objects.active = body

# Decimate przed modyfikatorem Armature (najpierw geometria spoczynkowa)
mod = body.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / max(len(body.data.polygons), 1))
while body.modifiers[0] != mod:
    bpy.ops.object.modifier_move_up(modifier=mod.name)
bpy.ops.object.modifier_apply(modifier=mod.name)
print("FACES", len(body.data.polygons))

# materiał: sama mapa koloru
mat = body.data.materials[0]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
color_img = None
for n in nt.nodes:
    if n.type == "TEX_IMAGE" and n.image and n.image.name.startswith("Color"):
        color_img = n
for l in list(nt.links):
    if l.to_node == bsdf and l.to_socket.name != "Base Color":
        nt.links.remove(l)
for n in list(nt.nodes):
    if n.type in ("NORMAL_MAP", "SEPARATE_COLOR") or (n.type == "TEX_IMAGE" and n != color_img):
        nt.nodes.remove(n)
bsdf.inputs["Roughness"].default_value = 0.85
bsdf.inputs["Metallic"].default_value = 0.0
color_img.image.scale(TEX, TEX)
for i in list(bpy.data.images):
    if i != color_img.image:
        bpy.data.images.remove(i)

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88,
                          export_animations=False, export_apply=False)
print("OK", dst)
