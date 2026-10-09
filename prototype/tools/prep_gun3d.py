"""Przygotowuje broń 3D (Tripo) do renderu w czasie rzeczywistym (spike 3D): lufa w +X, góra w +Z, początek układu = dłoń tylna (chwyt).

Uruchomienie (z korzenia repo):
    blender -b --factory-startup -P prototype/tools/prep_gun3d.py -- art_src/weapons/tripo/m83_01.glb prototype/art/char3d/gun_m83.glb LENGTH_M REAR_FX REAR_FZ FORE_FX FORE_FZ [--flip] [--faces=2500] [--tex=512]
    LENGTH_M = długość broni w metrach (postać ma ~1,8 m); *_FX = położenie dłoni wzdłuż lufy od tyłu (0..1); *_FZ = od góry broni (0..1).
Obok GLB powstaje <nazwa>.json: {"rear": [x,y,z], "fore": [x,y,z], "muzzle": [x,y,z]} w układzie wynikowego modelu (metry).
--flip odwraca kierunek lufy, gdyby heurystyka (tył = grubszy koniec) się pomyliła.
"""
import json
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
length_m, rfx, rfz, ffx, ffz = (float(a) for a in argv[2:7])
FLIP = "--flip" in argv
FACES = int(next((a.split("=")[1] for a in argv if a.startswith("--faces=")), 2500))
TEX = int(next((a.split("=")[1] for a in argv if a.startswith("--tex=")), 512))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
# wbij transformacje obiektu w siatkę
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

vs = [v.co.copy() for v in mesh.data.vertices]
ext = [(min(v[i] for v in vs), max(v[i] for v in vs)) for i in range(3)]
# oś długa = lufa
ax = max(range(3), key=lambda i: ext[i][1] - ext[i][0])
span = ext[ax][1] - ext[ax][0]


def end_height(lo, hi):
    sel = [v for v in vs if lo <= v[ax] <= hi]
    zs = [v.z for v in sel]
    return (max(zs) - min(zs)) if zs else 0.0


a = ext[ax][0]
h_lo = end_height(a, a + span * 0.12)
h_hi = end_height(a + span * 0.88, a + span)
barrel_positive = h_lo > h_hi              # grubszy (kolba) koniec na minusie → lufa na plusie
if FLIP:
    barrel_positive = not barrel_positive
print("AXIS", ax, "barrel_positive", barrel_positive, "heights", round(h_lo, 3), round(h_hi, 3))

# obróć tak, by lufa szła w +X (obrót wokół Z lub zamiana osi)
import math
from mathutils import Matrix, Vector

if ax == 0:
    R = Matrix.Identity(3) if barrel_positive else Matrix.Rotation(math.pi, 3, "Z")
elif ax == 1:
    R = Matrix.Rotation(-math.pi / 2, 3, "Z") if barrel_positive else Matrix.Rotation(math.pi / 2, 3, "Z")
else:
    raise SystemExit("oś Z jako długa — nieobsługiwane")
mesh.data.transform(R.to_4x4())
vs = [v.co.copy() for v in mesh.data.vertices]
ext = [(min(v[i] for v in vs), max(v[i] for v in vs)) for i in range(3)]
sc = length_m / (ext[0][1] - ext[0][0])
mesh.data.transform(Matrix.Scale(sc, 4))
ext = [(e[0] * sc, e[1] * sc) for e in ext]
L = ext[0][1] - ext[0][0]
hz = ext[2][1] - ext[2][0]
yc = (ext[1][0] + ext[1][1]) * 0.5


def pt(fx, fz):
    return Vector((ext[0][0] + fx * L, yc, ext[2][1] - fz * hz))


rear, fore = pt(rfx, rfz), pt(ffx, ffz)
mesh.data.transform(Matrix.Translation(-rear))        # początek = dłoń tylna
out = {"rear": [0.0, 0.0, 0.0], "fore": list(fore - rear), "muzzle": [ext[0][1] - rear.x, 0.0, (ext[2][1] - rear.z) - hz * 0.25]}
mesh.data.update()

mod = mesh.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / max(len(mesh.data.polygons), 1))
bpy.ops.object.modifier_apply(modifier=mod.name)
print("FACES", len(mesh.data.polygons))

mat = mesh.data.materials[0]
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
bsdf.inputs["Roughness"].default_value = 0.7
bsdf.inputs["Metallic"].default_value = 0.0
color_img.image.scale(TEX, TEX)
for i in list(bpy.data.images):
    if i != color_img.image:
        bpy.data.images.remove(i)

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90, export_animations=False)
with open(dst.rsplit(".", 1)[0] + ".json", "w") as f:
    json.dump(out, f, indent=1)
print("OK", dst, out)
