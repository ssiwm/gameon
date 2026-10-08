"""Bake broni z Tripo (GLB) do sprite'a HD gry: albedo (bez oświetlenia) + mapa normalnych świata, ortho z boku, lufa w prawo.

Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/gun_tripo_bake.py -- GUN.glb OUT_PREFIX CAM LENGTH_WP PIVOT_FRAC_X PIVOT_FRAC_Z
    CAM = +X albo -X (strona, z której kamera widzi lufę po prawej: +X gdy lufa jest w +Y modelu, -X gdy w −Y)
    LENGTH_WP = długość broni w pikselach świata; PIVOT_FRAC_X = położenie dłoni od tyłu broni (0..1); PIVOT_FRAC_Z = od góry broni (0..1)
Ramka 576×224 (16 px na piksel świata = 36×14 px świata, jak guns.png 72×28 @0,5); punkt obrotu (dłoń) w (104, 112) px.
Wynik: OUT_PREFIX.png (albedo), OUT_PREFIX_nw.png (normalne świata, Raw — pack_gun_hd.py przelicza na przestrzeń ekranu).
"""
import math
import sys

import bpy

glb, prefix, cam_side, length_wp, fx, fz = sys.argv[sys.argv.index("--") + 1:][:6]
length_wp, fx, fz = float(length_wp), float(fx), float(fz)
FW, FH = 576, 224
PPW = 16.0                                  # pikseli ramki na piksel świata
HAND = (104.0, 112.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
vs = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
ylo, yhi = min(v.y for v in vs), max(v.y for v in vs)
zlo, zhi = min(v.z for v in vs), max(v.z for v in vs)
L = yhi - ylo
ppm = length_wp * PPW / L                   # pikseli ramki na metr modelu
sign = 1.0 if cam_side == "+X" else -1.0    # kierunek „w prawo na ekranie” wzdłuż Y: +Y dla kamery +X, −Y dla kamery −X
rear_y = ylo if sign > 0 else yhi
pivot_y = rear_y + sign * fx * L
pivot_z = zhi - fz * (zhi - zlo)
cam_y = pivot_y + sign * (FW * 0.5 - HAND[0]) / ppm
cam_z = pivot_z + (FH * 0.5 - HAND[1]) / ppm * -1.0 if False else pivot_z
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.resolution_x, sc.render.resolution_y = FW, FH
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = FW / ppm
cam.location = (9.0 * sign, cam_y, cam_z)
cam.rotation_euler = (math.radians(90), 0, math.radians(90 * sign))


def pass_material(src, normal):
    m = src.copy()
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for l in list(nt.links):
        if l.to_node == out:
            nt.links.remove(l)
    em = nt.nodes.new("ShaderNodeEmission")
    if normal:
        nm = next((n for n in nt.nodes if n.type == "NORMAL_MAP"), None)
        ma = nt.nodes.new("ShaderNodeVectorMath")
        ma.operation = "MULTIPLY_ADD"
        ma.inputs[1].default_value = (0.5, 0.5, 0.5)
        ma.inputs[2].default_value = (0.5, 0.5, 0.5)
        if nm is not None:
            nt.links.new(nm.outputs["Normal"], ma.inputs[0])
        else:
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            nt.links.new(geo.outputs["Normal"], ma.inputs[0])
        nt.links.new(ma.outputs["Vector"], em.inputs["Color"])
    else:
        link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color"), None)
        if link is not None:
            nt.links.new(link.from_socket, em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


orig = mesh.data.materials[0]
w = bpy.data.worlds.new("w")
sc.world = w
for normal, suffix, vt in ((False, "", "Standard"), (True, "_nw", "Raw")):
    mesh.data.materials[0] = pass_material(orig, normal)
    sc.view_settings.view_transform = vt
    sc.render.filepath = f"{prefix}{suffix}.png"
    bpy.ops.render.render(write_still=True)
print("INFO L=%.3f ppm=%.1f pivot=(%.3f,%.3f) cam_y=%.3f" % (L, ppm, pivot_y, pivot_z, cam_y))
print("DONE-GUN")
