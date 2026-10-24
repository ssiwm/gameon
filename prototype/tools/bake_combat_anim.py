"""Autorskie klipy obsługi broni na kanonicznym szkielecie MPFB, bez zmiany modeli.

blender -b --factory-startup -P prototype/tools/bake_combat_anim.py
Wynik: art/char3d/anim/combat_*.glb, combat_motion.gd oraz art_src/animations/combat.blend.
Klipy są nakładkami na lokomocję; nogi zachowują kontakt przez końcowe IK gry.
Pozy kluczowe: przygotowanie → rozpęd → kontakt (45%) → wybieg → powrót.
Zapis .blend zachowuje akcje do dalszego dostrajania przez animatora.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "prototype/art/char3d/anim"
FPS = 60

# Stopnie w układzie postaci: pochylenie bioder, skręt, kręgosłup, głowa; przesunięcie bioder w metrach.
POSES = {
    "combat_chop": [
        (0, 0, 0, 0, 0, 0, 0), (.12, -3, -5, -2, 2, -.015, .008),
        (.28, -8, -16, -7, 7, -.025, .015), (.38, -2, -5, 2, 3, .008, -.006),
        (.45, 9, 12, 6, -7, .035, -.045), (.56, 11, 15, 7, -8, .035, -.055),
        (.72, 5, 7, 3, -3, .018, -.025), (1, 0, 0, 0, 0, 0, 0),
    ],
    "combat_slash": [
        (0, 0, 0, 0, 0, 0, 0), (.22, -4, -19, -4, 4, -.020, .010),
        (.45, 7, 18, 5, -5, .030, -.025), (.60, 8, 23, 4, -5, .025, -.020),
        (.78, 3, 8, 1, -2, .008, -.010), (1, 0, 0, 0, 0, 0, 0),
    ],
    "combat_reload": [
        (0, 0, 0, 0, 0, 0, 0), (.18, 2, -4, 2, -10, 0, -.008),
        (.38, 2, -7, 3, -14, 0, -.012), (.62, 3, -3, 3, -16, .003, -.012),
        (.80, 2, 1, 1, -10, 0, -.006), (1, 0, 0, 0, 0, 0, 0),
    ],
    "combat_fire_rifle": [(0, 0, 0, 0, 0, 0, 0), (.08, -1.8, -1.2, -.8, 1.3, -.005, -.003), (.3, -.8, -.5, -.4, .6, -.002, -.001), (1, 0, 0, 0, 0, 0, 0)],
    "combat_fire_pistol": [(0, 0, 0, 0, 0, 0, 0), (.08, -1.2, -1, -1.5, 1.2, -.003, -.002), (.3, -.6, -.4, -.8, .5, -.001, -.001), (1, 0, 0, 0, 0, 0, 0)],
    "combat_fire_heavy": [(0, 0, 0, 0, 0, 0, 0), (.08, -3, -1.8, -1.4, 2, -.009, -.005), (.35, -1.2, -.8, -.7, .8, -.003, -.002), (1, 0, 0, 0, 0, 0, 0)],
}
MOTION = {
    "chop": {
        "ang": [[0, 0], [.28, -1.65], [.45, .12], [.58, .40], [.78, .24], [1, 0]],
        "rad": [[0, .30], [.28, .18], [.45, .38], [.58, .36], [1, .30]],
        "slide": [[0, .20], [.28, .28], [.45, .13], [.65, .13], [1, .20]],
    },
    "slash": {
        "ang": [[0, 0], [.22, -1.10], [.45, .18], [.60, .60], [1, 0]],
        "rad": [[0, .30], [.22, .20], [.45, .40], [.60, .36], [1, .30]],
    },
}


def bone(arm, short):
    return next(b for b in arm.pose.bones if b.name.endswith(short))


def rotate(pb, axis, degrees):
    m = pb.matrix.copy()
    rot = Matrix.Rotation(math.radians(degrees), 4, axis)
    m = rot @ m
    m.translation = pb.matrix.translation
    pb.matrix = m
    bpy.context.view_layer.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / "prototype/art/char3d/mpfb/male_scav.glb"))
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for obj in list(bpy.data.objects):
    if obj != arm:
        bpy.data.objects.remove(obj, do_unlink=True)
arm.animation_data_clear()
mesh = bpy.data.meshes.new("clip_anchor")
mesh.from_pydata([(0, 0, 0), (.001, 0, 0), (0, 0, .001)], [], [(0, 1, 2)])
anchor = bpy.data.objects.new("clip_anchor", mesh)
bpy.context.collection.objects.link(anchor)
anchor.parent = arm
for b in arm.data.bones:
    anchor.vertex_groups.new(name=b.name)
anchor.vertex_groups[bone(arm, "Hips").name].add([0, 1, 2], 1, "REPLACE")
anchor.modifiers.new("arm", "ARMATURE").object = arm
OUT.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start = 0
sc.frame_end = FPS

for name, poses in POSES.items():
    action = bpy.data.actions.new(name)
    arm.animation_data_create().action = action
    for u, lean, twist, spine, head, forward, up in poses:
        frame = round(u * FPS)
        sc.frame_set(frame)
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
            pb.rotation_mode = "QUATERNION"
        bpy.context.view_layer.update()
        hips = bone(arm, "Hips")
        m = hips.matrix.copy()
        m.translation += Vector((forward, 0, up))
        hips.matrix = m
        bpy.context.view_layer.update()
        rotate(hips, "Y", lean)
        rotate(hips, "Z", twist * .4)
        for b in ["Spine", "Spine1", "Spine2"]:
            rotate(bone(arm, b), "Y", spine / 3)
            rotate(bone(arm, b), "Z", twist * .2)
        rotate(bone(arm, "Head"), "Y", head)
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb == hips:
                pb.keyframe_insert("location", frame=frame)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for k in fc.keyframe_points:
                        k.interpolation = "BEZIER"
                        k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
    for obj in bpy.data.objects:
        obj.select_set(obj in (arm, anchor))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{name}.glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIVE_ACTIONS",
                              export_force_sampling=True, export_optimize_animation_size=False,
                              export_materials="NONE", export_apply=False)
    action.use_fake_user = True
    print(f"COMBAT OK {name}")

(OUT / "combat_motion.gd").write_text("extends RefCounted\n## Dane toru broni z tools/bake_combat_anim.py; edytuj generator.\nconst CURVES := " + json.dumps(MOTION, indent=2) + "\n", encoding="utf-8")
source = ROOT / "art_src/animations/combat.blend"
source.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(source))
print("COMBAT SOURCE", source)
