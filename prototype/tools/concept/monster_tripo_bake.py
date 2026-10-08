"""Bake wrogów z Tripo do klatek HD gry (albedo bez oświetlenia + mapa normalnych świata), te same animacje co stare arkusze: idle, run/walk, windup, sleep.

Uruchomienie:
    blender -b --factory-startup -P prototype/tools/concept/monster_tripo_bake.py -- KIND GLB OUT_DIR [CAM]
    KIND = wolek | slepiec (szkielet Mixamo, własne pozy) | trzosek (animacja „preset:quadruped:walk" z Tripo + pozy pochodne)
    CAM  = -Y (domyślnie, postać patrzy w +X) | +X | -X | +Y — strona, z której kamera widzi bok potwora zwróconego w prawo
Wynik: OUT_DIR/KIND_<anim>_<i>.png i KIND_<anim>_<i>_n.png (normalne świata, Raw). Pakuje: tools/pack_monsters_hd.py.
Gęstość: 8 px na piksel świata (połowa gęstości postaci — oszczędność pamięci przy wielu typach wrogów).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

kind, glb, OUT = sys.argv[sys.argv.index("--") + 1:][:3]
CAM = (sys.argv[sys.argv.index("--") + 1:] + ["-Y"])[3] if len(sys.argv[sys.argv.index("--") + 1:]) > 3 else "-Y"
os.makedirs(OUT, exist_ok=True)
PPW = 8.0
# wymiary klatki w pikselach świata (jak w starych arkuszach: 88×88 / 2 i 48×44 / 2), wysokość lub długość potwora w pikselach świata
SPEC = {
    "wolek": {"frame": (44, 44), "fit": ("height", 32.0), "anims": [("idle", 4), ("walk", 6), ("windup", 1), ("sleep", 4)]},
    "slepiec": {"frame": (26, 32), "fit": ("height", 27.0), "anims": [("idle", 4), ("walk", 6), ("windup", 1), ("sleep", 4)]},
    "trzosek": {"frame": (24, 22), "fit": ("length", 21.0), "anims": [("idle", 4), ("run", 6), ("windup", 1), ("sleep", 4)]},
}[kind]
P = "mixamorig:"
BIPEDS = ("wolek", "slepiec")           # szkielet Mixamo + własne pozy (wolek_pose); reszta bierze animację z GLB


def upd():
    bpy.context.view_layer.update()


def T(v):
    return Matrix.Translation(v)


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


def aim(arm, name, target):
    pb = arm.pose.bones[P + name]
    upd()
    h = pb.head.copy()
    d = (target - h).normalized()
    cur = (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    pb.matrix = T(h) @ (cur.rotation_difference(d).to_matrix().to_4x4() @ pb.matrix.to_3x3().to_4x4())
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
    aim(arm, upper, ik2(sh, target, L1, L2, pole))
    aim(arm, lower, sh + (target - sh).normalized() * min((target - sh).length, L1 + L2 - 1e-4))


def plant_foot(arm, side, ankle, tilt):
    pb = arm.pose.bones[f"{P}{side}Foot"]
    rest = arm.data.bones[f"{P}{side}Foot"].matrix_local.to_3x3().to_4x4()
    pb.matrix = T(ankle) @ Matrix.Rotation(tilt, 4, "Y") @ rest
    upd()


def wolek_pose(arm, anim, i, n, x0):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    upd()
    ph = i / max(n, 1) * math.tau
    lean, bob, drop = 12.0, 0.0, 0.0
    feet = {"Right": Vector(), "Left": Vector()}
    hz = 0.42
    hands = {"Right": Vector((x0 + 0.05, -0.62, hz)), "Left": Vector((x0 + 0.05, 0.62, hz))}
    if anim == "idle":
        lean, bob = 12.0 + 1.6 * math.sin(ph), 0.012 * math.sin(ph)
        feet = {"Right": Vector((0.04, 0, 0)), "Left": Vector((-0.04, 0, 0))}
        sw = 0.06 * math.sin(ph)
        hands = {"Right": Vector((x0 + 0.05 + sw, -0.62, hz)), "Left": Vector((x0 + 0.05 - sw, 0.62, hz))}
    elif anim == "walk":
        lean, bob, drop = 14.0, 0.035 * math.cos(2 * ph), 0.03
        for side, k in (("Right", 0), ("Left", 1)):
            phk = ph + k * math.pi
            feet[side] = Vector((-0.22 * math.cos(phk), 0, 0.14 * max(0.0, math.sin(phk))))
        sw = 0.30 * math.sin(ph)
        hands = {"Right": Vector((x0 + 0.05 + sw, -0.62, hz + 0.05 * abs(sw))), "Left": Vector((x0 + 0.05 - sw, 0.62, hz + 0.05 * abs(sw)))}
    elif anim == "windup":
        lean, drop = -10.0, 0.04
        feet = {"Right": Vector((0.12, 0, 0)), "Left": Vector((-0.12, 0, 0))}
        hands = {"Right": Vector((x0 + 0.10, -0.40, 1.70)), "Left": Vector((x0 + 0.10, 0.40, 1.70))}
    elif anim == "sleep":
        lean, drop, bob = 27.0 + 2.0 * math.sin(ph), 0.06, 0.01 * math.sin(ph)
        feet = {"Right": Vector((0.05, 0, 0)), "Left": Vector((-0.05, 0, 0))}
        hands = {"Right": Vector((x0 + 0.26, -0.50, 0.40)), "Left": Vector((x0 + 0.26, 0.50, 0.40))}
    move(arm, "Hips", Vector((0, 0, -drop + bob)))
    rot_about(arm, "Hips", "Y", math.radians(lean))
    rot_about(arm, "Head", "Y", -math.radians(lean) * (0.8 if anim != "sleep" else 0.3))
    for side in ("Right", "Left"):
        ankle = arm.data.bones[f"{P}{side}Foot"].head_local.copy() + feet[side]
        reach(arm, f"{side}UpLeg", f"{side}Leg", ankle, Vector((1, 0, 0.1)))
        plant_foot(arm, side, ankle, tilt=0.2 * max(0.0, feet[side].z / 0.14))
    for side, sg in (("Right", -1), ("Left", 1)):
        reach(arm, f"{side}Arm", f"{side}ForeArm", hands[side], Vector((-0.4, sg * 0.8, -0.5)))


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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and not o.name.startswith("tripo"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    sc = bpy.context.scene
    act = bpy.data.actions[0] if bpy.data.actions else None
    if act is not None:
        arm.animation_data_create()
        arm.animation_data.action = act
        sc.frame_start, sc.frame_end = int(act.frame_range[0]), int(math.ceil(act.frame_range[1]))
    sc.frame_set(sc.frame_start)
    upd()
    vs = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    fit_kind, fit_wp = SPEC["fit"]
    ext = (hi[2] - lo[2]) if fit_kind == "height" else max(hi[0] - lo[0], hi[1] - lo[1])
    m_per_wp = ext / fit_wp
    fw, fh = SPEC["frame"]
    FW, FH = int(fw * PPW), int(fh * PPW)
    horiz = 0 if CAM in ("-Y", "+Y") else 1
    hc = (lo[horiz] + hi[horiz]) / 2
    if kind in BIPEDS:
        hc = arm.data.bones[P + "Hips"].head_local.x - 0.05
    ortho = max(fw, fh) * m_per_wp
    ppm = max(FW, FH) / ortho
    cz = lo[2] + FH * 0.5 / ppm
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x, sc.render.resolution_y = FW, FH
    sc.world = bpy.data.worlds.new("w")
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    loc, rot = {"-Y": ((hc, -9, cz), (90, 0, 0)), "+Y": ((hc, 9, cz), (90, 0, 180)), "-X": ((-9, hc, cz), (90, 0, -90)), "+X": ((9, hc, cz), (90, 0, 90))}[CAM]
    cam.location, cam.rotation_euler = loc, tuple(math.radians(a) for a in rot)
    orig = mesh.data.materials[0]
    mats = {False: pass_material(orig, False), True: pass_material(orig, True)}
    print("INFO %s ext=%.3f m_per_wp=%.4f frame=%dx%d" % (kind, ext, m_per_wp, FW, FH))

    def render(path_base):
        for normal, suffix, vt in ((False, "", "Standard"), (True, "_n", "Raw")):
            mesh.data.materials[0] = mats[normal]
            sc.view_settings.view_transform = vt
            sc.render.filepath = f"{path_base}{suffix}.png"
            bpy.ops.render.render(write_still=True)

    fr0, fr1 = (sc.frame_start, sc.frame_end)
    base_scale = arm.scale.copy()
    base_loc = arm.location.copy()
    for anim, n in SPEC["anims"]:
        for i in range(n):
            if kind in BIPEDS:
                wolek_pose(arm, anim, i, n, hc)
            else:
                arm.scale, arm.location = base_scale.copy(), base_loc.copy()
                ph = i / max(n, 1)
                if anim == "run":
                    sc.frame_set(int(round(fr0 + (fr1 - fr0) * ph)))
                elif anim == "idle":
                    sc.frame_set(fr0)
                    arm.scale = Vector((base_scale.x, base_scale.y, base_scale.z * (1.0 + 0.018 * math.sin(ph * math.tau))))
                elif anim == "windup":                     # skok: wyciągnięta faza kroku, ściśnięty przed odbiciem
                    sc.frame_set(int(round(fr0 + (fr1 - fr0) * 0.25)))
                    arm.scale = Vector((base_scale.x, base_scale.y * 1.05, base_scale.z * 0.86))
                elif anim == "sleep":                      # zwinięty: spłaszczony, powoli oddycha
                    sc.frame_set(fr0)
                    arm.scale = Vector((base_scale.x, base_scale.y * 1.0, base_scale.z * (0.60 + 0.02 * math.sin(ph * math.tau))))
                upd()
            render(f"{OUT}/{kind}_{anim}_{i}")
        print("BAKED", kind, anim, n)
    print("DONE-MONSTER")


main()
