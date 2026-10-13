"""Przygotowuje klipy animacji postaci 3D (szkielet Mixamo z Tripo) dla gry: `art/char3d/anim/<nazwa>.glb` — sam szkielet i klip, bez modelu.
Klipy odtwarza `scripts/char_clips.gd` (AnimationTree) na szkielecie dowolnego wyglądu; ręce z bronią i stopy dalej prowadzi IK z `char3d.gd`.

Uruchomienie (z korzenia repo, Blender w PATH):
    blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=PLIK.glb --list
        wypisuje klipy i kości pliku źródłowego oraz dopasowanie kości do naszego szkieletu
    blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=PLIK.glb --map=Jog_Fwd_Loop:run,Idle_Loop:idle [--keep-travel] [--step-sync]
        przenosi wskazane klipy (nazwa w pliku:nazwa w grze) na nasz szkielet. Plik może mieć inny układ kości (UE, humanoid Unity / Godot, Mixamo),
        inną skalę, inny kierunek „przodu" i inną pozę spoczynkową. Domyślnie klip gra w miejscu; --keep-travel zostawia przemieszczanie się postaci;
        --step-sync (pętle kroku: bieg, chód) zaczyna klip od lądowania prawej stopy, żeby zgadzał się z fazą kroku gry

Źródło klipów gry: `art_src/animations/ual1/` (Quaternius, Universal Animation Library, CC0 — patrz SOURCE.md w tym katalogu), np.
    blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=art_src/animations/ual1/AnimationLibrary_Godot_Standard.glb --map=Sprint_Loop:run --step-sync

Przeniesienie liczy się w przestrzeni świata: nasza kość dostaje ten sam obrót względem pozy spoczynkowej co kość źródłowa, po wyrównaniu
kierunków kości w spoczynku (poza T źródła kontra nasza poza A) — kończyny wskazują więc tam, gdzie w źródle, niezależnie od osi lokalnych kości.
Skrypt wypisuje największy błąd kierunku kości (°): kontrola, czy dopasowanie kości jest poprawne.

Klip trzyma własną pozę spoczynkową szkieletu, więc gra przelicza go na każdy wygląd (obroty względem spoczynku, biodra skalowane wysokością).
Układ naszego modelu w Blenderze: przód +X, góra +Z, prawa strona postaci −Y; szkielet docelowy to `art/char3d/male_scav.glb`.
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

argv = sys.argv[sys.argv.index("--") + 1:]


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


def update():
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- narzędzia kostne (w przestrzeni szkieletu)

def head(pb):
    return pb.matrix.translation.copy()


def set_basis(pb, rot3):
    """Orientacja kości w przestrzeni szkieletu; głowa kości zostaje w miejscu."""
    m = rot3.to_4x4()
    m.translation = pb.matrix.translation
    pb.matrix = m
    update()


def move(pb, v):
    m = pb.matrix.copy()
    m.translation = m.translation + v
    pb.matrix = m
    update()


# ---------------------------------------------------------------- eksport: szkielet + klip + trójkąt (żeby Godot zaimportował Skeleton3D)

def use_action(arm, action):
    """Ustawia czynną akcję szkieletu (None = żadna); ścieżki NLA z importu są wyciszane, żeby nie mieszały się z akcją."""
    ad = arm.animation_data or arm.animation_data_create()
    for tr in ad.nla_tracks:
        tr.mute = True
    ad.action = action
    if action is not None and hasattr(ad, "action_slot") and len(getattr(action, "slots", [])) > 0 and ad.action_slot is None:
        ad.action_slot = action.slots[0]


def export(arm, action, name):
    action.name = name
    use_action(arm, action)
    ob = bpy.data.objects.get("clip_anchor")
    if ob is None:
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
    for o in bpy.data.objects:                                  # eksport tylko szkieletu z klipem i trójkąta (model i szkielet źródła zostają w scenie)
        o.select_set(o in (arm, ob))
    bpy.context.view_layer.objects.active = arm
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_animations=True, export_animation_mode="ACTIVE_ACTIONS",
                              export_force_sampling=True, export_optimize_animation_size=False, export_materials="NONE", export_apply=False)
    print("OK %s  %.2f s  %d kB" % (dst, (action.frame_range[1] - action.frame_range[0]) / FPS, os.path.getsize(dst) // 1024))


def load_rig():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=RIG)
    return next(o for o in bpy.data.objects if o not in before and o.type == "ARMATURE")


# ---------------------------------------------------------------- przeniesienie klipu z innego szkieletu (przestrzeń świata)

# Nasza kość (bez przedrostka) → nazwy tej kości w innych układach (porównanie bez wielkości liter, przedrostków i znaków innych niż litery / cyfry).
ALIASES = {
    "Hips": ["hips", "pelvis", "hip"],
    "Spine": ["spine", "spine01", "spine1", "spine001"],
    "Spine1": ["spine1", "chest", "spine02", "spine2", "spine002"],
    "Spine2": ["spine2", "upperchest", "spine03", "spine3", "spine003", "chest"],
    "Neck": ["neck", "neck01"],
    "Head": ["head"],
    "LeftShoulder": ["leftshoulder", "claviclel", "shoulderl", "lshoulder", "lclavicle"],
    "LeftArm": ["leftarm", "leftupperarm", "upperarml", "lupperarm", "arml"],
    "LeftForeArm": ["leftforearm", "leftlowerarm", "lowerarml", "forearml", "llowerarm", "lforearm"],
    "LeftHand": ["lefthand", "handl", "lhand"],
    "LeftUpLeg": ["leftupleg", "leftupperleg", "thighl", "uplegl", "upperlegl", "lthigh", "lupperleg"],
    "LeftLeg": ["leftleg", "leftlowerleg", "calfl", "shinl", "lowerlegl", "legl", "lcalf", "llowerleg"],
    "LeftFoot": ["leftfoot", "footl", "lfoot"],
    "LeftToeBase": ["lefttoebase", "lefttoes", "balll", "toel", "toesl", "ltoes", "lefttoe"],
}


def _right(alias):
    if "left" in alias:
        return alias.replace("left", "right")
    if alias.endswith("l"):
        return alias[:-1] + "r"
    return "r" + alias[1:] if alias.startswith("l") else alias


for _k in [k for k in ALIASES if k.startswith("Left")]:
    ALIASES["Right" + _k[4:]] = [_right(a) for a in ALIASES[_k]]
# kość, na którą wskazuje dana kość: kierunek kości w spoczynku służy do wyrównania póz spoczynkowych (T źródła kontra nasze A)
CHILD = {"Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
         "LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
         "RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
         "LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
         "RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase"}


def norm(name):
    n = name.lower()
    for pre in ("mixamorig:", "mixamorig_", "mixamorig", "def-", "def_", "bip001", "bip01"):
        if n.startswith(pre):
            n = n[len(pre):]
    return "".join(ch for ch in n if ch.isalnum())


def bone_map(src_arm):
    """Nasza kość → kość źródła (None, gdy brak). Każda kość źródła najwyżej raz; kolejność aliasów = pierwszeństwo."""
    have = {}
    for b in src_arm.data.bones:
        have.setdefault(norm(b.name), b.name)
    out, used = {}, set()
    for ours, names in ALIASES.items():
        out[ours] = next((have[a] for a in names if a in have and have[a] not in used), None)
        if out[ours]:
            used.add(out[ours])
    return out


def retarget(src_arm, tgt_arm, action, keep_travel, step_sync):
    """Przenosi `action` ze szkieletu źródła na nasz; zwraca nową akcję na `tgt_arm`."""
    Z = Vector((0, 0, 1))
    sc = bpy.context.scene
    bm = {n: sn for n, sn in bone_map(src_arm).items() if sn}
    tp = {b.name[len(PRE):]: b for b in tgt_arm.pose.bones if b.name.startswith(PRE)}
    use_action(tgt_arm, None)
    use_action(src_arm, None)
    for arm in (src_arm, tgt_arm):
        for b in arm.pose.bones:
            b.rotation_mode = "QUATERNION"
            b.matrix_basis = Matrix.Identity(4)
    update()
    sw = src_arm.matrix_world.copy()
    tw = tgt_arm.matrix_world.copy()

    def s_pose():
        return {n: (sw @ src_arm.pose.bones[sn].matrix) for n, sn in bm.items()}

    s_rest = s_pose()
    t_rest = {n: (tw @ b.matrix) for n, b in tp.items()}

    # wyrównanie źródła do naszego układu: obrót wokół pionu (przód wynika z osi bioder) i skala (wysokość bioder nad najniższą kością)
    def forward(rest):
        left = rest["LeftUpLeg"].translation - rest["RightUpLeg"].translation
        return Vector((left.x, left.y, 0.0)).cross(Z).normalized()

    fs, ft = forward(s_rest), forward(t_rest)
    yaw = math.atan2(ft.y, ft.x) - math.atan2(fs.y, fs.x)
    A = Matrix.Rotation(yaw, 3, Z)
    floor_s = min(m.translation.z for m in s_rest.values())
    floor_t = min(m.translation.z for m in t_rest.values())
    k = (t_rest["Hips"].translation.z - floor_t) / max(s_rest["Hips"].translation.z - floor_s, 1e-6)
    print("ALIGN obrót %.1f°, skala %.4f" % (math.degrees(yaw), k))

    def rot_of(m):
        return A @ m.to_quaternion().to_matrix()

    def direction(pose, n, aligned):
        c = CHILD.get(n)
        if c is None or c not in pose or n not in pose:
            return None
        d = pose[c].translation - pose[n].translation
        if d.length < 1e-6:
            return None
        return ((A @ d) if aligned else d).normalized()

    # poprawka kierunku kości w spoczynku: nasz spoczynek → kierunek tej kości w spoczynku źródła
    fix = {}
    for n in tp:
        ds, dt = direction(s_rest, n, True), direction(t_rest, n, False)
        fix[n] = dt.rotation_difference(ds).to_matrix() if (ds is not None and dt is not None) else Matrix.Identity(3)
    s_rest_r = {n: rot_of(m) for n, m in s_rest.items()}
    f0, f1 = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
    use_action(src_arm, action)

    def hips_at(f):
        sc.frame_set(f)
        update()
        return A @ (sw @ src_arm.pose.bones[bm["Hips"]].matrix).translation

    # przemieszczenie bioder w klipie: położenie początkowe w poziomie i (bez --keep-travel) liniowy dryf zdejmujemy — klip gra w miejscu
    h0, h1 = hips_at(f0), hips_at(f1)
    hr = A @ s_rest["Hips"].translation
    travel = Vector((h1.x - h0.x, h1.y - h0.y, 0.0))
    print("TRAVEL %.2f m w klipie%s" % (travel.length * k, "" if keep_travel else " — zdjęte (klip w miejscu)"))
    # --step-sync (pętle kroku): klip zaczyna się w klatce, w której prawa stopa jest najdalej z przodu (ląduje) — tak jak faza kroku w grze
    shift = 0
    if step_sync and f1 > f0:
        best = -1e9
        for f in range(f0, f1):
            sc.frame_set(f)
            update()
            p = s_pose()
            lead = (A @ (p["RightFoot"].translation - p["Hips"].translation)).dot(ft)
            if lead > best:
                best, shift = lead, f - f0
        print("STEP prawa stopa ląduje w klatce %d z %d — klip przesunięty" % (shift, f1 - f0))
    prev, worst = {}, (0.0, "")
    for j in range(f1 - f0 + 1):
        f = f0 + (j + shift) % max(f1 - f0, 1) if shift else f0 + j
        sc.frame_set(f)
        for b in tgt_arm.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        update()
        s_now = s_pose()
        for n, b in tp.items():                                  # pose.bones idą od korzenia w dół hierarchii
            if n not in s_now:
                continue
            if n == "Hips":
                off = A @ s_now[n].translation - hr - Vector((h0.x - hr.x, h0.y - hr.y, 0.0))
                if not keep_travel:
                    off -= travel * ((f - f0) / max(f1 - f0, 1))
                elif shift:
                    sys.exit("--step-sync działa tylko dla klipów w miejscu (bez --keep-travel)")
                move(b, off * k)
            set_basis(b, rot_of(s_now[n]) @ s_rest_r[n].inverted() @ fix[n] @ t_rest[n].to_3x3())
        for n, b in tp.items():
            c = CHILD.get(n)
            if n in s_now and c in s_now and c in tp:
                ds = (A @ (s_now[c].translation - s_now[n].translation)).normalized()
                dt = (head(tp[c]) - head(b)).normalized()
                err = math.degrees(ds.angle(dt))
                if err >= worst[0]:
                    worst = (err, n)
            q = b.rotation_quaternion.copy()
            if n in prev and prev[n].dot(q) < 0.0:
                q.negate()
                b.rotation_quaternion = q
            prev[n] = q
            b.keyframe_insert("rotation_quaternion", frame=j)
        tp["Hips"].keyframe_insert("location", frame=j)
    print("CHECK największy błąd kierunku kości: %.2f° (%s)" % worst)
    return tgt_arm.animation_data.action


bpy.ops.wm.read_factory_settings(use_empty=True)
src = arg("from")
if src:
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, src) if not os.path.isabs(src) else src)
    src_arm = max((o for o in bpy.data.objects if o.type == "ARMATURE"), key=lambda o: len(o.data.bones))
    by_name = {a.name: a for a in bpy.data.actions}
    if not by_name:
        sys.exit("Brak animacji w pliku " + src)
    FPS = int(round(bpy.context.scene.render.fps))
    bm = bone_map(src_arm)
    if "--list" in argv:
        for n in sorted(by_name):
            print("CLIP %-40s %4d klatek" % (n, by_name[n].frame_range[1] - by_name[n].frame_range[0]))
        print("BONES", ", ".join(b.name for b in src_arm.data.bones))
        for n, sn in bm.items():
            print("MAP %-14s <- %s" % (n, sn))
        sys.exit(0)
    need = [n for n in ("Hips", "Spine", "Head", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot") if not bm.get(n)]
    if need:
        sys.exit("Brak dopasowania kości: %s (dopisz nazwy do ALIASES; --list pokazuje kości pliku)" % ", ".join(need))
    pairs = [x.split(":") for x in arg("map", "").split(",") if ":" in x]
    if not pairs:
        sys.exit("Podaj --map=NazwaWPliku:nazwa_w_grze[,…] (klipy pokazuje --list)")
    missing = [p[0] for p in pairs if p[0] not in by_name]
    if missing:
        sys.exit("Nie ma klipów: %s" % ", ".join(missing))
    tgt = load_rig()
    for s_name, g_name in pairs:
        export(tgt, retarget(src_arm, tgt, by_name[s_name], "--keep-travel" in argv, "--step-sync" in argv), g_name)
else:
    sys.exit(__doc__)
