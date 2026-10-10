"""Przygotowuje postać 3D (rig Mixamo z Tripo) do renderu w czasie rzeczywistym w grze (spike 3D).

Uruchomienie (z korzenia repo):
    blender -b --factory-startup -P prototype/tools/prep_char3d.py -- art_src/characters/tripo/male_scav_01_rig.glb prototype/art/char3d/male_scav.glb [--faces=12000] [--tex=2048]
Co robi: usuwa śmieciową ikosferę, upraszcza siatkę (Decimate, wagi kości zostają), zmniejsza mapę koloru, normalnych i ORM
(roughness / AO z Tripo) do --tex px i eksportuje GLB. Detal ma znaczenie: przy zoomie kamery 2,0–2,4 postać ma 130–160 px
na 1080p (265–316 px na 4K), więc normalne i AO (kieszenie, pasy, szwy) zostają; metaliczność gra zeruje po wczytaniu.
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
FACES = int(next((a.split("=")[1] for a in argv if a.startswith("--faces=")), 12000))
TEX = int(next((a.split("=")[1] for a in argv if a.startswith("--tex=")), 2048))

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

# materiał: kolor + normalne + ORM zostają (połączenia z Tripo), wszystkie obrazy sprowadzone do --tex px
mat = body.data.materials[0]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Metallic"].default_value = 0.0
for i in list(bpy.data.images):
    if i.size[0] > TEX or i.size[1] > TEX:
        i.scale(TEX, TEX)
    print("IMG", i.name, tuple(i.size))

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90,
                          export_animations=False, export_apply=False)
print("OK", dst)
