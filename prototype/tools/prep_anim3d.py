"""Przygotowuje klipy animacji postaci 3D (szkielet Mixamo z Tripo) dla gry: `art/char3d/anim/<nazwa>.glb` — sam szkielet i klip, bez modelu.
Klipy odtwarza `scripts/char_clips.gd` (AnimationTree) na szkielecie dowolnego wyglądu; ręce z bronią i stopy dalej prowadzi IK z `char3d.gd`.

Uruchomienie (z korzenia repo, Blender w PATH):
    blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=art_src/characters/tripo/male_scav_01_run.glb --name=run
        klip z pliku (np. wynik `tripo_gen.py retarget RIG_TASK_ID preset:biped:run --in-place`); --clip=N wybiera animację, gdy plik ma ich kilka
    blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --standin=run
        klip zastępczy: bieg ułożony kluczami w tym skrypcie na modelu `art/char3d/male_scav.glb` (do czasu, aż będzie klip z nagrania ruchu)

Klip trzyma własną pozę spoczynkową szkieletu, więc gra przelicza go na każdy wygląd (obroty względem spoczynku, biodra skalowane wysokością).
Układ modelu w Blenderze: przód +X, góra +Z, prawa strona postaci −Y. Cykl biegu: prawa stopa ląduje w klatce 0, lewa w połowie.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "prototype", "art", "char3d", "anim")
RIG = os.path.join(ROOT, "prototype", "art", "char3d", "male_scav.glb")
PRE = "mixamorig:"
FPS = 30
FRAMES = 24                                   # próbek na cykl (klatka FRAMES = klatka 0, pętla)

argv = sys.argv[sys.argv.index("--") + 1:]


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


def update():
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- narzędzia kostne (jak w char3d.gd, w przestrzeni szkieletu)

def head(pb):
    return pb.matrix.translation.copy()


def set_basis(pb, rot3):
    """Orientacja kości w przestrzeni szkieletu; głowa kości zostaje w miejscu."""
    m = rot3.to_4x4()
    m.translation = pb.matrix.translation
    pb.matrix = m
    update()


def rot(pb, axis, deg):
    """Obrót kości (z poddrzewem) wokół jej głowy o kąt wokół osi szkieletu."""
    set_basis(pb, Matrix.Rotation(math.radians(deg), 3, axis) @ pb.matrix.to_3x3())


def move(pb, v):
    m = pb.matrix.copy()
    m.translation = m.translation + v
    pb.matrix = m
    update()


def point(pb, child, target):
    """Kość kieruje się na punkt (jej dziecko leży na osi kości)."""
    a = (head(child) - head(pb)).normalized()
    b = (target - head(pb)).normalized()
    if a.dot(b) > 0.99999:
        return
    set_basis(pb, a.rotation_difference(b).to_matrix() @ pb.matrix.to_3x3())


def two_bone(a, m, e, target, pole):
    """Dwukostkowe IK: staw środkowy wygina się w stronę `pole`."""
    la = (head(m) - head(a)).length
    lb = (head(e) - head(m)).length
    s = head(a)
    d = target - s
    dist = min(max(d.length, abs(la - lb) + 0.001), (la + lb) * 0.999)
    dn = d.normalized()
    x = (la * la - lb * lb + dist * dist) / (2.0 * dist)
    h = math.sqrt(max(la * la - x * x, 0.0))
    pv = pole - dn * pole.dot(dn)
    pv = pv.normalized() if pv.length > 0.0001 else Vector((0.0, 0.0, 1.0))
    point(a, m, s + dn * x + pv * h)
    point(m, e, s + dn * dist)


def keys(table, u):
    """Wartość z tabeli [(u, v…), …] na okręgu 0..1 — wygładzona interpolacja między kluczami."""
    n = len(table)
    for i in range(n):
        a = table[i]
        b = table[(i + 1) % n]
        ua, ub = a[0], b[0] if i + 1 < n else b[0] + 1.0
        if ua <= u <= ub:
            t = (u - ua) / max(ub - ua, 1e-6)
            return [a[k] + (b[k] - a[k]) * t for k in range(1, len(a))]
    return list(table[0][1:])


def smooth_table(table, n=96, passes=2):
    """Zagęszcza tabelę kluczy i wygładza ją na okręgu (bez kantów prędkości w kluczach)."""
    dense = [keys(table, i / n) for i in range(n)]
    for _ in range(passes):
        dense = [[(dense[(i - 1) % n][k] + 2.0 * dense[i][k] + dense[(i + 1) % n][k]) / 4.0 for k in range(len(dense[0]))] for i in range(n)]
    return [(i / n, *dense[i]) for i in range(n)]


# ---------------------------------------------------------------- klip zastępczy: bieg

# Tor kostki jednej nogi w cyklu (u = 0: lądowanie): [u, x w przód (ułamek długości nogi), uniesienie (ułamek), pochylenie stopy (°, + = palce w dół)]
FOOT = [
    (0.00, 0.36, 0.00, -8.0),
    (0.06, 0.27, 0.00, 0.0),
    (0.20, -0.03, 0.00, 0.0),
    (0.32, -0.34, 0.04, 22.0),
    (0.40, -0.52, 0.13, 50.0),
    (0.50, -0.68, 0.40, 76.0),
    (0.62, -0.46, 0.58, 70.0),
    (0.74, -0.02, 0.48, 35.0),
    (0.86, 0.38, 0.31, 6.0),
    (0.95, 0.46, 0.10, -12.0),
]


def standin_run(arm):
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    pb = {b.name[len(PRE):]: b for b in arm.pose.bones if b.name.startswith(PRE)}
    for b in arm.pose.bones:
        b.rotation_mode = "QUATERNION"
    update()
    rest = {n: b.matrix.copy() for n, b in pb.items()}
    leg = {}
    for side in ("Left", "Right"):
        leg[side] = (rest[side + "Leg"].translation - rest[side + "UpLeg"].translation).length + (rest[side + "Foot"].translation - rest[side + "Leg"].translation).length
    foot = smooth_table(FOOT)
    prev = {}
    for f in range(FRAMES + 1):
        c = (f % FRAMES) / FRAMES
        for b in arm.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        update()
        w = math.tau * c
        # miednica: najniżej w połowie podporu, najwyżej w locie; skręt za nogą wykroczną, opadanie po stronie nogi w wymachu
        bob = 0.026 * math.cos(2.0 * math.tau * (c - 0.45))
        move(pb["Hips"], Vector((0.012 * math.cos(2.0 * w), -0.012 * math.sin(w), -0.035 + bob)))
        rot(pb["Hips"], Y, 9.0 + 1.5 * math.cos(2.0 * math.tau * (c - 0.05)))
        rot(pb["Hips"], Z, 6.0 * math.cos(w))
        rot(pb["Hips"], X, -4.0 * math.sin(w))
        # tułów: pochylenie w przód, barki przeciwnie do miednicy, głowa patrzy przed siebie
        rot(pb["Spine"], Y, 3.0)
        rot(pb["Spine"], X, 2.0 * math.sin(w))
        rot(pb["Spine1"], Z, -5.0 * math.cos(w))
        rot(pb["Spine2"], Z, -5.0 * math.cos(w))
        rot(pb["Spine2"], Y, 2.0)
        rot(pb["Neck"], Y, -4.0)
        rot(pb["Neck"], Z, 2.0 * math.cos(w))
        rot(pb["Head"], Y, -6.0 - 1.5 * math.cos(2.0 * math.tau * (c - 0.05)))
        rot(pb["Head"], Z, 2.0 * math.cos(w))
        rot(pb["Head"], X, 2.0 * math.sin(w))
        # ręce (w grze i tak prowadzi je IK): przy tułowiu, łokcie zgięte, wymach przeciwnie do nóg
        for side, sg in (("Left", 1.0), ("Right", -1.0)):
            swing = -sg * 32.0 * math.cos(w) - 6.0
            rot(pb[side + "Arm"], X, -35.0 * sg)
            rot(pb[side + "Arm"], Y, swing)
            rot(pb[side + "ForeArm"], Y, -80.0 + 0.35 * swing)
        # nogi: IK na tor kostki, stopa wg toru
        for side, off in (("Right", 0.0), ("Left", 0.5)):
            x, lift, pitch = keys(foot, (c + off) % 1.0)
            L = leg[side]
            hip = rest[side + "UpLeg"].translation
            rf = rest[side + "Foot"].translation
            target = Vector((rest["Hips"].translation.x + x * L, hip.y + 0.45 * (rf.y - hip.y), rf.z + lift * L))
            two_bone(pb[side + "UpLeg"], pb[side + "Leg"], pb[side + "Foot"], target, X)
            set_basis(pb[side + "Foot"], Matrix.Rotation(math.radians(pitch), 3, Y) @ rest[side + "Foot"].to_3x3())
            rot(pb[side + "ToeBase"], Y, -0.6 * max(pitch, 0.0))                 # palce zostają na ziemi przy odbiciu
        for n, b in pb.items():
            q = b.rotation_quaternion.copy()
            if n in prev and prev[n].dot(q) < 0.0:
                q.negate()                                                         # ciągłość kwaternionów między klatkami
                b.rotation_quaternion = q
            prev[n] = q
            b.keyframe_insert("rotation_quaternion", frame=f)
        pb["Hips"].keyframe_insert("location", frame=f)
    arm.animation_data.action.name = "run"
    return arm.animation_data.action


# ---------------------------------------------------------------- eksport: szkielet + klip + trójkąt (żeby Godot zaimportował Skeleton3D)

def export(arm, action, name):
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a != action:
            bpy.data.actions.remove(a)
    action.name = name
    arm.animation_data.action = action
    me = bpy.data.meshes.new("clip_anchor")
    me.from_pydata([(0.0, 0.0, 0.0), (0.001, 0.0, 0.0), (0.0, 0.0, 0.001)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("clip_anchor", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = arm
    for b in arm.data.bones:
        ob.vertex_groups.new(name=b.name)
    ob.vertex_groups[next(b.name for b in arm.data.bones if b.name.endswith("Hips"))].add([0, 1, 2], 1.0, "REPLACE")
    ob.modifiers.new("arm", "ARMATURE").object = arm
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = int(action.frame_range[0])
    sc.frame_end = int(action.frame_range[1])
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_optimize_animation_size=False, export_materials="NONE", export_apply=False)
    print("OK %s  %.2f s  %d kB" % (dst, (action.frame_range[1] - action.frame_range[0]) / FPS, os.path.getsize(dst) // 1024))


bpy.ops.wm.read_factory_settings(use_empty=True)
src = arg("from")
standin = arg("standin")
if standin == "run":
    bpy.ops.import_scene.gltf(filepath=RIG)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    bpy.context.scene.render.fps = FPS
    export(arm, standin_run(arm), "run")
elif src:
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, src) if not os.path.isabs(src) else src)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    acts = sorted(bpy.data.actions, key=lambda a: a.name)
    if not acts:
        sys.exit("Brak animacji w pliku " + src)
    for i, a in enumerate(acts):
        print("CLIP %d %s  klatki %d–%d" % (i, a.name, a.frame_range[0], a.frame_range[1]))
    FPS = int(round(bpy.context.scene.render.fps))
    export(arm, acts[int(arg("clip", "0"))], arg("name", "run"))
else:
    sys.exit(__doc__)
