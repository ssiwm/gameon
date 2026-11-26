# Model nakładki klawisza [E] do znacznika interakcji (INTERACT_KEY_PLAN.md K1b): surowy model z Meshy (image-to-3d z klatki 1 arkusza
# inspiracji art_src/ui/interact_key_ref.png, bez litery; ok. 360 tys. trójkątów, 18 MB) → decymacja do ~TRIS trójkątów, środek bryły
# w początku układu, szerokość 1 m, lico nakładki w stronę kamery gry (+Z po eksporcie glTF), tekstura zmniejszona do TEX px.
# Literę rysuje Label3D (interact_mark3d.gd), więc model jest bez litery i działa dla każdego klawisza.
#
#   python meshy_character.py character -i <nakładka bez litery 1024 px> --name ekey_cap --pose none --no-rig --no-anim ...
#   blender -b --factory-startup -P prototype/tools/blender_key_cap.py -- --src=meshy_out/ekey_cap/<...>/ekey-cap.glb [--tris=6000] [--tex=512]
import bpy
import math
import os
import sys

import mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ""
TRIS = 6000
TEX = 512
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "art", "world3d", "interact", "key_cap.glb")
for a in argv:
	if a.startswith("--src="):
		SRC = a[len("--src="):]
	elif a.startswith("--tris="):
		TRIS = int(a[len("--tris="):])
	elif a.startswith("--tex="):
		TEX = int(a[len("--tex="):])
	elif a.startswith("--out="):
		OUT = a[len("--out="):]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
	bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
dec = ob.modifiers.new("dec", "DECIMATE")
dec.ratio = min(1.0, TRIS / max(tris, 1))
bpy.ops.object.modifier_apply(modifier="dec")
# środek bryły w początku układu, szerokość 1 m
bb = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
mn = mathutils.Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
mx = mathutils.Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
ctr = (mn + mx) * 0.5
ob.location -= ctr
bpy.ops.object.transform_apply(location=True)
s = 1.0 / max(mx.x - mn.x, mx.z - mn.z)
ob.scale = (s, s, s)
bpy.ops.object.transform_apply(scale=True)
# lico Meshy patrzy w −Y Blendera → po eksporcie glTF (+Y w górę) w +Z, czyli do kamery gry; nic nie obracamy
for mat in ob.data.materials:
	if mat is None or not mat.use_nodes:
		continue
	for n in mat.node_tree.nodes:
		if n.type == "TEX_IMAGE" and n.image is not None and max(n.image.size) > TEX:
			n.image.scale(TEX, TEX)
			n.image.pack()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_animations=False,
	export_image_format="JPEG", export_jpeg_quality=88)
tris2 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
print("[KEY-CAP] %d → %d trójkątów, zapisano %s" % (tris, tris2, OUT))
