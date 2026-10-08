"""Bake rekwizytu świata z Tripo (GLB) do sprite'a HD: albedo (bez oświetlenia) + normalne świata, ortho z wybranej strony, stopy w dolnej krawędzi ramki.

Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/prop_tripo_bake.py -- PROP.glb OUT_PREFIX CAM WIDTH_WP FRAME_W_WP FRAME_H_WP
    CAM = -Y | +Y | -X | +X (z której strony patrzymy); WIDTH_WP = szerokość obiektu w pikselach świata; ramka w pikselach świata (× PPW px; PPW = 7. argument, domyślnie 16).
Wynik: OUT_PREFIX.png i OUT_PREFIX_nw.png; potem: python prototype/tools/pack_gun_hd.py OUT_PREFIX NAZWA --cam=CAM --out=world/prop_NAZWA
"""
import math
import sys

import bpy

_a = sys.argv[sys.argv.index("--") + 1:]
glb, prefix, cam_side, width_wp, fw_wp, fh_wp = _a[:6]
width_wp, fw_wp, fh_wp = float(width_wp), float(fw_wp), float(fh_wp)
PPW = float(_a[6]) if len(_a) > 6 else 16.0      # px ramki na piksel świata (opcjonalnie; domyślnie 16)
FW, FH = int(fw_wp * PPW), int(fh_wp * PPW)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
vs = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
horiz = 0 if cam_side in ("-Y", "+Y") else 1
lo_h, hi_h = min(v[horiz] for v in vs), max(v[horiz] for v in vs)
zlo = min(v.z for v in vs)
ppm = width_wp * PPW / (hi_h - lo_h)
ch = (lo_h + hi_h) / 2
cz = zlo + (FH * 0.5) / ppm
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
cam.data.ortho_scale = max(FW, FH) / ppm
cam.location, cam.rotation_euler = {
    "-Y": ((ch, -9, cz), (90, 0, 0)), "+Y": ((ch, 9, cz), (90, 0, 180)),
    "-X": ((-9, ch, cz), (90, 0, -90)), "+X": ((9, ch, cz), (90, 0, 90))}[cam_side]
cam.rotation_euler = tuple(math.radians(a) for a in cam.rotation_euler)
sc.world = bpy.data.worlds.new("w")


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
for normal, suffix, vt in ((False, "", "Standard"), (True, "_nw", "Raw")):
    mesh.data.materials[0] = pass_material(orig, normal)
    sc.view_settings.view_transform = vt
    sc.render.filepath = f"{prefix}{suffix}.png"
    bpy.ops.render.render(write_still=True)
print("INFO bbox_h", round(hi_h - lo_h, 3), "ppm", round(ppm, 1), "frame", FW, FH)
print("DONE-PROP")
