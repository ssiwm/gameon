"""Przenosi klipy czworonoga (wilk Quaterniusa, CC0) na szkielet Trzoska z Tripo i zapisuje GLB z klipami.

Uruchomienie (z korzenia repo, Blender w PATH): python prototype/tools/retarget_quad.py
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/retarget_quad.py -- TRIPO.glb WILK.glb WYNIK.glb
Wynik (`art_src/enemies/tripo/trzosek_01_clips.glb`) jest źródłem dla `prep_enemy3d.py` (decymacja, tekstury → `art/enemy3d/trzosek.glb`).

Jak przenosi (oba szkielety w świecie Blendera: Z w górę; wilk patrzy w −Y, Trzosek w +Y, stąd obrót C = 180° wokół Z):
  - tułów, szyja, głowa, uszy, łopatki i ogon: zmiana obrotu kości wilka względem jego spoczynku (w świecie) nakładana na spoczynek
    odpowiadającej kości Trzoska — kilka kości Trzoska może iść za jedną kością wilka;
  - korzeń: przesunięcie bioder wilka w skali wysokości nóg;
  - łapy: punkt podparcia łapy wilka względem jej obręczy (bark / biodro), zmiana od spoczynku przeskalowana długością nogi Trzoska,
    a potem dwukostkowe IK (Limb_0, Limb_1) jak w `enemy3d.gd: _quad_support`; śródręcze / śródstopie (Limb_2) obraca się jak podudzie wilka.
Klipy dostają nazwy gry (CLIPS); wypiekane klatka po klatce w 24 kl./s (tempo źródła), klucze lokalne kości jak w zwykłym klipie glTF.
"""
import glob
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC_TRIPO = os.path.join(ROOT, "art_src", "enemies", "tripo", "trzosek_01_anims.glb")
SRC_WOLF = os.path.join(ROOT, "art_src", "animations", "quaternius_wolf", "Wolf.glb")
DST = os.path.join(ROOT, "art_src", "enemies", "tripo", "trzosek_01_clips.glb")

## nazwa w grze → klip wilka
CLIPS = {
    "gallop": "Gallop", "walk": "Walk", "idle": "Idle", "idle_low": "Idle_2_HeadLow", "attack": "Attack", "death": "Death",
    "hit_l": "Idle_HitReact_Left", "hit_r": "Idle_HitReact_Right", "jump": "Gallop_Jump", "land": "Jump_ToIdle",
}

## kość Trzoska → kość wilka, której zmianę obrotu przejmuje
ROT_MAP = {
    "tripo::Root": "Back", "tripo::Spine_0": "Torso", "tripo::Spine_1": "Torso2", "tripo::Spine_2": "Torso3", "tripo::Spine_3": "Torso3",
    "tripo::Spine_4": "Neck2", "tripo::Head_0": "Neck3", "tripo::Head_1": "Head", "tripo::Head_2": "Head",
    "bone_10": "Ear1.R", "bone_11": "Ear1.L",
    "bone_13": "FrontShoulder.R", "bone_22": "FrontShoulder.L",
    "bone_31": "Tail1", "bone_32": "Tail2", "bone_33": "Tail3", "tripo::Tail_0": "Tail4", "tripo::Tail_1": "Tail5",
    "tripo::Tail_2": "Tail6", "tripo::Tail_3": "Tail7",
}

## noga Trzoska (przedrostek łańcucha Limb_0..4) → [obręcz wilka (staw), kość udowa / ramienna, podudzie, punkt łapy (głowa kości)]
## Trzosek: „Right” leży na +X, wilk: „.L” na +X przed obrotem C — po obrocie lewa wilka trafia na −X, czyli na „Left” Trzoska.
LEGS = {
    "tripo::0_Right": ["FrontUpperLeg.R", "FrontUpperLeg.R", "FrontLowerLeg.R", "FF.R"],
    "tripo::0_Left": ["FrontUpperLeg.L", "FrontUpperLeg.L", "FrontLowerLeg.L", "FF.L"],
    "tripo::1_Right": ["BackLeg.R", "BackUpperLeg.R", "BackLowerLeg.R", "FFB.R"],
    "tripo::1_Left": ["BackLeg.L", "BackUpperLeg.L", "BackLowerLeg.L", "FFB.L"],
}
GROUND_MIN = 0.02                    ## m: najniżej położony punkt łapy Trzoska (poniżej tylko przy przewróconym ciele)


def run_in_blender():
    import bpy
    from mathutils import Matrix, Quaternion, Vector

    argv = sys.argv[sys.argv.index("--") + 1:]
    src_tripo, src_wolf, dst = argv[0], argv[1], argv[2]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 24

    bpy.ops.import_scene.gltf(filepath=src_tripo)
    tripo = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    keep = {tripo} | {o for o in bpy.data.objects if o.parent == tripo}
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    old_actions = set(bpy.data.actions)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src_wolf)
    wolf = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o not in before)
    for o in list(bpy.data.objects):
        if o not in before and o != wolf and o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    wolf_actions = {a.name: a for a in bpy.data.actions if a not in old_actions}
    # import glTF kładzie każdy klip na osobny aktywny tor NLA — bez wyciszenia tory przykrywają przypisaną akcję
    for tr in wolf.animation_data.nla_tracks:
        tr.mute = True

    C = Matrix.Rotation(math.pi, 4, "Z")
    C3 = C.to_3x3()
    tw = tripo.matrix_world.copy()
    tw_inv = tw.inverted()

    def rot3(m):
        return m.to_3x3().normalized()

    # spoczynek obu szkieletów w świecie
    t_rest = {b.name: tw @ b.matrix_local for b in tripo.data.bones}
    w_rest = {b.name: wolf.matrix_world @ b.matrix_local for b in wolf.data.bones}

    def w_head(name):                   # głowa kości wilka w świecie w bieżącej klatce
        return wolf.matrix_world @ wolf.pose.bones[name].head

    def w_rot_delta(name):              # zmiana obrotu kości wilka w świecie, w układzie Trzoska
        pb = wolf.pose.bones[name]
        cur = rot3(wolf.matrix_world @ pb.matrix)
        d = cur @ rot3(w_rest[name]).inverted()
        return C3 @ d @ C3.inverted()

    def w_point(bone, point_rest):      # punkt skóry (w spoczynku w świecie) niesiony przez kość wilka
        pb = wolf.pose.bones[bone]
        m = (wolf.matrix_world @ pb.matrix) @ w_rest[bone].inverted()
        return m @ point_rest

    def to_tripo(v):                    # wektor (różnica położeń) wilka → układ Trzoska
        return C3 @ v

    # skale: wysokość obręczy nad ziemią (Trzosek / wilk), osobno dla przodu i tyłu
    def t_head(name):
        return t_rest[name].translation

    leg_scale = {}
    for pre, (girdle, _upper, _lower, paw) in LEGS.items():
        th = t_head(pre + "_Limb_0").z - t_head(pre + "_Limb_3").z
        wh = w_rest[girdle].translation.z - w_rest[paw].translation.z
        leg_scale[pre] = th / wh
    body_scale = sum(leg_scale.values()) / len(leg_scale)
    print("SCALE", {k: round(v, 3) for k, v in leg_scale.items()}, "body", round(body_scale, 3))

    bones = list(tripo.data.bones)          # kolejność: rodzic przed dzieckiem (glTF importuje drzewo w głąb)
    order = []
    seen = set()

    def visit(b):
        if b.name in seen: return
        if b.parent: visit(b.parent)
        seen.add(b.name)
        order.append(b)
    for b in bones: visit(b)

    leg_bones = {}
    for pre in LEGS:
        leg_bones[pre] = [pre + "_Limb_%d" % i for i in range(5)]

    def frame_basis(x, pole):
        x = x.normalized()
        p = (pole - x * pole.dot(x))
        if p.length < 1e-6:
            p = Vector((0, 0, 1)) - x * x.z
        p.normalize()
        z = x.cross(p)
        return Matrix((x, p, z)).transposed()

    def aim(rest_from, rest_to, rest_pole, new_from, new_to, new_pole):
        return frame_basis(new_to - new_from, new_pole) @ frame_basis(rest_to - rest_from, rest_pole).inverted()

    def two_bone(s, w, l0, l1, pole):
        d_vec = w - s
        d = max(min(d_vec.length, l0 + l1 - 1e-4), abs(l0 - l1) + 1e-4)
        u = d_vec.normalized()
        v = pole - u * pole.dot(u)
        v = v.normalized() if v.length > 1e-6 else Vector((0, 0, 1))
        cos_a = max(-1.0, min(1.0, (l0 * l0 + d * d - l1 * l1) / (2.0 * l0 * d)))
        a = math.acos(cos_a)
        return s + (u * math.cos(a) + v * math.sin(a)) * l0, s + u * d

    tripo.animation_data_create()
    for pb in tripo.pose.bones:
        pb.rotation_mode = "QUATERNION"
    # rest offsets
    rest_rel = {}
    for b in order:
        rest_rel[b.name] = (t_rest[b.parent.name].inverted() @ t_rest[b.name]) if b.parent else t_rest[b.name].copy()

    made = []
    for clip, wname in CLIPS.items():
        act_src = wolf_actions.get(wname) or wolf_actions.get("AnimalArmature|" + wname)
        wolf.animation_data.action = act_src
        if hasattr(wolf.animation_data, "action_slot") and act_src.slots:
            wolf.animation_data.action_slot = act_src.slots[0]
        f0, f1 = int(round(act_src.frame_range[0])), int(round(act_src.frame_range[1]))
        act = bpy.data.actions.new(clip)
        act.use_fake_user = True
        tripo.animation_data.action = act
        if hasattr(tripo.animation_data, "action_slot") and not tripo.animation_data.action_slot:
            slot = act.slots.new(id_type="OBJECT", name=tripo.name) if hasattr(act, "slots") else None
            if slot: tripo.animation_data.action_slot = slot
        back_rest = w_rest["Back"].translation
        # Korzeń Trzoska ma głowę przy ziemi, a kość Back wilka siedzi na grzbiecie nad biodrami — obrót trzeba liczyć wokół
        # odpowiednika tego punktu (grzbiet nad stawami biodrowymi), inaczej przewrót przy śmierci wbija tułów w ziemię.
        hips = [t_rest["tripo::1_Right_Limb_0"].translation, t_rest["tripo::1_Left_Limb_0"].translation]
        anchor_rest = Vector(((hips[0].x + hips[1].x) * 0.5, (hips[0].y + hips[1].y) * 0.5, t_rest["tripo::Spine_0"].translation.z))
        trace = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            world = {}                  # docelowe macierze kości Trzoska w świecie
            # 1) obroty z mapy, położenia z drzewa
            for b in order:
                n = b.name
                if b.parent:
                    base = world[b.parent.name] @ rest_rel[n]
                else:
                    base = rest_rel[n].copy()
                pos = base.translation.copy()
                r = rot3(base)
                if n in ROT_MAP:
                    r = w_rot_delta(ROT_MAP[n]) @ rot3(t_rest[n])
                if b.parent is None:
                    anchor = anchor_rest + to_tripo(w_head("Back") - back_rest) * body_scale
                    pos = anchor - w_rot_delta(ROT_MAP[n]) @ (anchor_rest - t_rest[n].translation)
                m = r.to_4x4()
                m.translation = pos
                world[n] = m
            # 2) nogi: IK do punktu łapy
            for pre, (girdle, upper, lower, paw) in LEGS.items():
                ch = leg_bones[pre]
                s_pose = world[ch[0]].translation.copy()               # bark / biodro (po obrotach tułowia i łopatki)
                g_rest = w_rest[girdle].translation
                p_rest = w_rest[paw].translation
                off_rest = p_rest - g_rest
                off_now = w_point(lower, p_rest) - w_head(girdle)
                t_s0, t_e0, t_w0, t_p0 = (t_head(c) for c in ch[:4])
                target = s_pose + (t_p0 - t_s0) + to_tripo(off_now - off_rest) * leg_scale[pre]
                target.z = max(target.z, GROUND_MIN)
                r_past = w_rot_delta(lower) @ rot3(t_rest[ch[2]])
                past_vec = r_past @ rot3(t_rest[ch[2]]).inverted() @ (t_p0 - t_w0)
                w_tgt = target - past_vec
                pole_rest = t_e0 - (t_s0 + t_w0) * 0.5
                pole = w_rot_delta(upper) @ pole_rest
                l0, l1 = (t_e0 - t_s0).length, (t_w0 - t_e0).length
                e_new, w_new = two_bone(s_pose, w_tgt, l0, l1, pole)
                r0 = aim(t_s0, t_e0, pole_rest, s_pose, e_new, pole) @ rot3(t_rest[ch[0]])
                m0 = r0.to_4x4(); m0.translation = s_pose; world[ch[0]] = m0
                # środkowa kość: płaszczyzna zgięcia z tej samej tyczki
                r1 = aim(t_e0, t_w0, pole_rest, e_new, w_new, pole) @ rot3(t_rest[ch[1]])
                m1 = r1.to_4x4(); m1.translation = e_new; world[ch[1]] = m1
                m2 = r_past.to_4x4(); m2.translation = w_new; world[ch[2]] = m2
                # dalej (Limb_3, Limb_4, palce): sztywno za śródręczem
                for b in order:
                    if b.name in ch[:3]: continue
                    p = b.parent
                    inside = False
                    while p is not None:
                        if p.name == ch[2]:
                            inside = True
                            break
                        p = p.parent
                    if inside:
                        world[b.name] = world[b.parent.name] @ rest_rel[b.name]
                if f == f0 and clip == "idle":
                    trace.append((pre, round((world[ch[3]].translation - target).length, 4)))
            # 3) klucze lokalne
            for b in order:
                n = b.name
                pb = tripo.pose.bones[n]
                arm_pose = tw_inv @ world[n]
                if b.parent:
                    parent_pose = tw_inv @ world[b.parent.name]
                    rel = (tw_inv @ t_rest[b.parent.name]).inverted() @ (tw_inv @ t_rest[n])
                    basis = rel.inverted() @ parent_pose.inverted() @ arm_pose
                else:
                    basis = (tw_inv @ t_rest[n]).inverted() @ arm_pose
                loc, rot, _sc = basis.decompose()
                pb.location = loc
                pb.rotation_quaternion = rot
                pb.scale = (1.0, 1.0, 1.0)
                for path in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(path, frame=f - f0, group=n)
        if trace:
            print("PAWERR", clip, trace)
        made.append((clip, wname, f1 - f0))
        print("CLIP", clip, "<-", wname, f1 - f0 + 1, "kl.")

    # Wagi: auto-rig Tripo przypisał pazury tylnych łap po części kościom pazurów przednich (np. bone_21, bone_30) i odwrotnie —
    # gdy łapy się rozchodzą (galop, skok), pazury ciągnęły się w długie czarne kolce. Wierzchołek zostaje tylko przy kościach
    # nogi, która ma w nim największą wagę (reszta nóg odpada, wagi tułowia zostają), potem normalizacja.
    leg_of = {}
    for pre in LEGS:
        stack = [tripo.data.bones[pre + "_Limb_0"]]
        while stack:
            b = stack.pop()
            leg_of[b.name] = pre
            stack.extend(b.children)
    fixed = 0
    for body in [o for o in tripo.children if o.type == "MESH"]:
        groups = {g.index: g for g in body.vertex_groups}
        for v in body.data.vertices:
            sums = {}
            for g in v.groups:
                pre = leg_of.get(groups[g.group].name)
                if pre: sums[pre] = sums.get(pre, 0.0) + g.weight
            if len(sums) < 2: continue
            main_leg = max(sums, key=sums.get)
            drop = [g.group for g in v.groups if leg_of.get(groups[g.group].name) not in (None, main_leg)]
            for gi in drop:
                groups[gi].remove([v.index])
            total = sum(g.weight for g in v.groups)
            for g in v.groups:
                g.weight /= max(total, 1e-6)
            fixed += 1
    print("WEIGHTS", fixed, "wierzchołków z wagami dwóch nóg")

    # eksport: tylko Trzosek, każdy klip jako osobny tor NLA (nazwa toru = nazwa animacji w glTF)
    tripo.animation_data.action = None
    for tr in list(tripo.animation_data.nla_tracks):          # chód z Tripo („preset:quadruped:walk”) zastępuje chód wilka
        tripo.animation_data.nla_tracks.remove(tr)
    for clip, _w, _n in made:
        tr = tripo.animation_data.nla_tracks.new()
        tr.name = clip
        strip = tr.strips.new(clip, 0, bpy.data.actions[clip])
        strip.name = clip
    bpy.data.objects.remove(wolf, do_unlink=True)
    for a in list(bpy.data.actions):
        if a.name not in CLIPS:
            bpy.data.actions.remove(a)
    bpy.ops.object.select_all(action="DESELECT")
    tripo.select_set(True)
    for o in tripo.children: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_apply=False)
    print("OK", dst)


def main():
    exe = os.environ.get("BLENDER")
    if not exe and os.name == "nt":
        found = sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe"))
        exe = found[-1] if found else None
    exe = exe or shutil.which("blender")
    if not exe:
        raise SystemExit("Nie znaleziono Blendera (ustaw BLENDER=ścieżka)")
    subprocess.run([exe, "-b", "--factory-startup", "--python-exit-code", "1", "-P", os.path.abspath(__file__), "--",
                    SRC_TRIPO, SRC_WOLF, DST], check=True)


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        main()
    else:
        run_in_blender()
