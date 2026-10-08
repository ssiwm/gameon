"""Bake animacji postaci z Tripo (GLB z rigiem Mixamo) do klatek gry — te same 7 animacji i ten sam punkt dłoni co char_mpfb_outfit.py --bake.

Uruchomienie:
    blender -b --factory-startup -P prototype/tools/concept/char_tripo_bake.py -- RIGGED.glb OUT_DIR NAZWA [--normals] [--albedo]
Wynik: OUT_DIR/NAZWA_<anim>_<i>.png (256×384) oraz, z --normals, NAZWA_<anim>_<i>_n.png — mapa normalnych ŚWIATA (n*0,5+0,5, Raw); pack_chars3d.py --hd przelicza ją na przestrzeń ekranu. Potem: python prototype/tools/pack_chars3d.py OUT_DIR --prefix=playerhd3_ --genders=NAZWA
Model Tripo patrzy w +X, kamera stoi po stronie −Y (bliższa jest prawa strona postaci), stopy w z=0. Skala: postać 22 px świata (klatka 24 px).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

glb, OUT, NAME = sys.argv[sys.argv.index("--") + 1:][:3]
NORMALS = "--normals" in sys.argv
ALBEDO = "--albedo" in sys.argv        # kolor bez oświetlenia (do dynamicznego światła 2D z mapą normalnych)
os.makedirs(OUT, exist_ok=True)
CHAR_PX = 22.0                       # wysokość postaci REF_H w pikselach świata (klatka ma 24)
REF_H = 1.8                          # wysokość odniesienia (m): wspólna skala dla wszystkich postaci, więc niższa postać wychodzi niższa
RW, RH = 256, 384
ANIMS = [("idle", 6), ("run", 8), ("jump", 1), ("fall", 1), ("crouch", 1), ("crouch_walk", 6), ("down", 1)]
P = "mixamorig:"
FWD = Vector((1, 0, 0))              # kierunek patrzenia modelu


def ik2(shoulder, target, a, b, pole):
    s_, t_ = Vector(shoulder), Vector(target)
    d = t_ - s_
    L = max(min(d.length, (a + b) * 0.999), 1e-4)
    dn = d.normalized()
    x = (a * a - b * b + L * L) / (2 * L)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pv = Vector(pole)
    pv = (pv - dn * pv.dot(dn)).normalized()
    return s_ + dn * x + pv * h


def T(v):
    return Matrix.Translation(v)


def upd():
    bpy.context.view_layer.update()


def reset(arm):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    upd()


def aim(arm, name, target):
    pb = arm.pose.bones[P + name]
    upd()
    h = pb.head.copy()
    d = (target - h).normalized()
    cur = (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(d)
    pb.matrix = T(h) @ (q.to_matrix().to_4x4() @ pb.matrix.to_3x3().to_4x4())
    upd()


def rot_about(arm, name, axis, ang):
    pb = arm.pose.bones[P + name]
    h = pb.head.copy()
    pb.matrix = T(h) @ Matrix.Rotation(ang, 4, axis) @ T(-h) @ pb.matrix
    upd()


def move(arm, name, delta):
    pb = arm.pose.bones[P + name]
    pb.matrix = T(delta) @ pb.matrix
    upd()


def reach(arm, upper, lower, target, pole):
    bu, bl = arm.data.bones[P + upper], arm.data.bones[P + lower]
    L1, L2 = (bu.tail_local - bu.head_local).length, (bl.tail_local - bl.head_local).length
    sh = arm.pose.bones[P + upper].head.copy()
    mid = ik2(sh, target, L1, L2, pole)
    aim(arm, upper, mid)
    aim(arm, lower, sh + (target - sh).normalized() * min((target - sh).length, L1 + L2 - 1e-4))


def plant_foot(arm, side, ankle, tilt):
    pb = arm.pose.bones[f"{P}{side}Foot"]
    rest = arm.data.bones[f"{P}{side}Foot"].matrix_local.to_3x3().to_4x4()
    pb.matrix = T(ankle) @ Matrix.Rotation(tilt, 4, "Y") @ rest
    upd()


def pose(arm, anim, i, n, env):
    reset(arm)
    PX = env["px"]
    x0 = env["x0"]
    ph = i / max(n, 1) * math.tau
    lean, bob, drop, A, Lf, hand_h = 4.0, 0.0, 0.0, 0.0, 0.0, 12 * PX
    feet = {"Right": Vector(), "Left": Vector()}
    if anim == "idle":
        bob, lean = 0.006 * math.sin(ph), 4.0 + math.sin(ph)
        feet = {"Right": FWD * 0.05, "Left": -FWD * 0.05}
    elif anim == "run":
        lean, A, Lf, bob, drop = 11.0, 0.26, 0.20, 0.028 * math.cos(2 * ph), 0.03
        for side, k in (("Right", 0), ("Left", 1)):
            phk = ph + k * math.pi
            feet[side] = FWD * (-A * math.cos(phk)) + Vector((0, 0, Lf * max(0.0, math.sin(phk))))
    elif anim == "jump":
        lean = 3.0
        feet = {"Right": FWD * 0.14 + Vector((0, 0, 0.30)), "Left": -FWD * 0.06 + Vector((0, 0, 0.20))}
    elif anim == "fall":
        lean = 0.0
        feet = {"Right": FWD * 0.06 + Vector((0, 0, 0.12)), "Left": -FWD * 0.08 + Vector((0, 0, 0.06))}
    elif anim in ("crouch", "crouch_walk"):
        lean, drop, hand_h = 16.0, 0.27, 8 * PX
        if anim == "crouch":
            feet = {"Right": FWD * 0.10, "Left": -FWD * 0.09}
        else:
            A, Lf, bob = 0.12, 0.08, 0.010 * math.cos(2 * ph)
            for side, k in (("Right", 0), ("Left", 1)):
                phk = ph + k * math.pi
                feet[side] = FWD * (-A * math.cos(phk)) + Vector((0, 0, Lf * max(0.0, math.sin(phk))))
    elif anim == "down":
        lean, drop, hand_h = -18.0, 0.52, 0.0
        feet = {"Right": FWD * 0.52, "Left": FWD * 0.46 + Vector((0, 0, 0.02))}
    move(arm, "Hips", Vector((0, 0, -drop + bob)))
    rot_about(arm, "Hips", "Y", math.radians(lean))
    rot_about(arm, "Head", "Y", -math.radians(lean) * 0.7)
    for side in ("Right", "Left"):
        ankle = arm.data.bones[f"{P}{side}Foot"].head_local.copy() + feet[side]
        reach(arm, f"{side}UpLeg", f"{side}Leg", ankle, FWD + Vector((0, 0, 0.1)))
        plant_foot(arm, side, ankle, tilt=0.25 * max(0.0, feet[side].z / 0.2))
    if anim != "down":
        sy = arm.data.bones[P + "RightArm"].head_local.y
        near = Vector((x0 + 1.0 * PX, sy * 1.12, hand_h))
        far = Vector((x0 + 3.2 * PX, -sy * 0.45, hand_h + 0.02))
        reach(arm, "RightArm", "RightForeArm", near, Vector((-0.6, -0.6, -0.7)))
        reach(arm, "LeftArm", "LeftForeArm", far, Vector((-0.6, 0.6, -0.7)))
    else:
        for sd, sg in (("Right", -1), ("Left", 1)):
            sh = arm.pose.bones[f"{P}{sd}Arm"].head.copy()
            aim(arm, f"{sd}Arm", sh + Vector((0.15, sg * 0.25, -0.95)).normalized() * 0.3)
            el = arm.pose.bones[f"{P}{sd}Arm"].tail.copy()
            aim(arm, f"{sd}ForeArm", el + Vector((0.4, sg * 0.1, -0.9)).normalized() * 0.28)


def make_normal_material(src):
    """Kopia materiału, która zamiast koloru emituje normalną ŚWIATA (po mapie normalnych) jako n * 0,5 + 0,5.
    Render w trybie Raw (bez gammy); pack_chars3d.py przelicza ją na przestrzeń ekranu (stała orientacja kamery: R = +X, G = +Z, B = −Y)."""
    m = src.copy()
    m.name = "normalpass"
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nm = next((n for n in nt.nodes if n.type == "NORMAL_MAP"), None)
    for l in list(nt.links):
        if l.to_node == out:
            nt.links.remove(l)
    ma = nt.nodes.new("ShaderNodeVectorMath")
    ma.operation = "MULTIPLY_ADD"
    ma.inputs[1].default_value = (0.5, 0.5, 0.5)
    ma.inputs[2].default_value = (0.5, 0.5, 0.5)
    if nm is not None:
        nt.links.new(nm.outputs["Normal"], ma.inputs[0])
    else:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        nt.links.new(geo.outputs["Normal"], ma.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ma.outputs["Vector"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def make_albedo_material(src):
    """Kopia materiału emitująca sam kolor bazowy (bez światła i cieni) — oświetlenie robi silnik gry na podstawie mapy normalnych."""
    m = src.copy()
    m.name = "albedopass"
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color"), None)
    for l in list(nt.links):
        if l.to_node == out:
            nt.links.remove(l)
    em = nt.nodes.new("ShaderNodeEmission")
    if link is not None:
        nt.links.new(link.from_socket, em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = bsdf.inputs["Base Color"].default_value
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and not o.name.startswith("tripo"):
            bpy.data.objects.remove(o)               # pomocnicza „Icosphere” z importu
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    mesh = [o for o in bpy.data.objects if o.type == "MESH"][0]
    zs = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices]
    H = max(zs) - min(zs)
    px = REF_H / CHAR_PX
    hips = arm.data.bones[P + "Hips"].head_local
    x0 = hips.x - 0.05                              # oś postaci: nieco z tyłu miednicy (plecak wystaje do tyłu)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.eevee.taa_render_samples = 48
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.46, 0.58, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sc.world = w
    for name, rot, en, col in (("key", (math.radians(52), math.radians(-8), math.radians(-25)), 3.6, (1.0, 0.93, 0.82)),
                               ("rim", (math.radians(62), 0, math.radians(165)), 2.4, (0.7, 0.8, 1.0)),
                               ("fill", (math.radians(78), 0, math.radians(-100)), 0.9, (0.85, 0.9, 1.0))):
        L = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        L.data.energy, L.data.color, L.rotation_euler = en, col, rot
        sc.collection.objects.link(L)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 24.0 * px
    cam.location = (x0, -9.0, cam.data.ortho_scale * 0.5)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.resolution_x, sc.render.resolution_y = RW, RH
    env = {"px": px, "x0": x0}
    orig_mat = mesh.data.materials[0]
    color_mat = make_albedo_material(orig_mat) if ALBEDO else orig_mat
    mesh.data.materials[0] = color_mat
    normal_mat = make_normal_material(orig_mat) if NORMALS else None
    print("INFO H=%.3f px=%.4f x0=%.3f" % (H, px, x0))
    for anim, n in ANIMS:
        for i in range(n):
            pose(arm, anim, i, n, env)
            sc.render.filepath = f"{OUT}/{NAME}_{anim}_{i}.png"
            bpy.ops.render.render(write_still=True)
            if normal_mat is not None:
                mesh.data.materials[0] = normal_mat
                sc.view_settings.view_transform = "Raw"
                sc.render.filepath = f"{OUT}/{NAME}_{anim}_{i}_n.png"
                bpy.ops.render.render(write_still=True)
                sc.view_settings.view_transform = "Standard"
                mesh.data.materials[0] = color_mat
        print("BAKED", NAME, anim, n)
    print("DONE-BAKE")


main()
