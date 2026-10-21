"""Chwyty broni dla rąk FPP (strzelnica, RANGE_FPS_PLAN.md) — klipy `grip_<broń>` w `art/char3d/fp/fp_arms_<strój>.glb`.

Uruchomienie (z korzenia repo; najpierw `fp_arms.py`, który zapisuje `build/fp/fp_arms_<strój>.blend`):
    blender -b -P prototype/tools/fp_grip.py -- scav m83 [p64 ...] [--shots=build/fp]

Dla każdej broni z tabeli GRIPS:
1. Broń (`art/char3d/gun_<klucz>.glb`) w postawie strzeleckiej: stopka kolby w zagłębieniu prawego barku, lufa obrócona o `yaw`
   względem tułowia (tułów bokiem do celu) — pistolet: przed twarzą na wyciągniętych rękach.
2. Dłonie z układów zmierzonych na szkielecie (kierunek palców, linia kostek, grzbiet): prawa na chwycie (kostki wzdłuż chwytu,
   grzbiet na zewnątrz), lewa pod łożem (wnętrzem do góry). Ramiona IK z biegunem łokcia, obojczyki lekko w przód.
3. Palce zginane człon po członie, aż kapsuła członu dotknie siatki broni (BVH) — palce leżą na chwycie, łożu i spuście, nie w nich.
4. Poza zapisana jako klip `grip_<klucz>` (jedna klatka) i pusty węzeł `gunref_<klucz>` przypięty do kości prawej dłoni: w grze broń
   stoi tam, gdzie ten węzeł (BoneAttachment3D), więc broń i dłonie zgadzają się co do milimetra.
Podglądy (Eevee): `<shots>/grip_<klucz>_eye.png` (z oka nad przyrządami) i `_side.png`.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(os.path.dirname(HERE), "art", "char3d")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


WORK = arg("work", os.path.join(REPO, "build", "fp"))
SHOTS = arg("shots", WORK)
PRE = "mixamorig:"
FINGERS = ("Index", "Middle", "Ring", "Pinky")
SEG_R = (0.0105, 0.0095, 0.0085)        # m — promień kapsuły członu palca w rękawicy (nasada, środek, opuszka)
THUMB_R = (0.0125, 0.011, 0.0095)
STEP = math.radians(2.0)
CURL_MAX = math.radians(125.0)
PALM_R = 0.019                         # m — pół grubości dłoni w rękawicy (od osi kości do wnętrza dłoni)

# Chwyty: yaw — obrót broni względem tułowia (°, + = w lewo), right / left — dłoń: punkt broni (układ Blendera broni: x lufa, y lewo,
# z góra), „up” — kierunek linii kostek (od małego do wskazującego), „back” — strona grzbietu dłoni, `off` — środek dłoni od punktu
# (wzdłuż −back: wnętrze dłoni dotyka broni), `push` — przesunięcie punktu. Pierwszy człon wskazującego może zostać prosty (`index`).
GRIPS = {
    "m83": {
        "yaw": 35.0, "butt_dz": 0.02, "clav": (6.0, 12.0),
        "right": {"at": "grip", "push": (-0.03, -0.004, 0.0), "up": (0.34, 0.0, 0.94), "back": (-0.25, -0.97, 0.0), "off": 0.022},
        "left": {"at": "hold", "push": (0.0, 0.042, -0.03), "up": (1.0, 0.0, 0.0), "back": (0.0, 0.25, -0.97), "off": 0.012},
    },
}


# Przeładowania: klipy (nazwa, czas w s jak WeaponDef.reload_time [+ reload_empty_extra]) i klatki kluczowe lewej dłoni (ułamek klipu, poza).
# Pozy: grip — jak w chwycie, grab — dłoń na magazynku (w gnieździe), rock — magazynek wyważony w przód i w dół, pouch — przy ładownicy
# pod kadrem, handle / pulled — dłoń na suwadle i suwadło odciągnięte. Magazynek jedzie z dłonią od pierwszego `grab` do ostatniego
# (`mag_out` / `mag_in` w .json; w grze przypina go range_view.gd), więc ten sam magazynek wychodzi i wraca.
RELOADS = {
    "m83": {"handle": (0.17, -0.032, 0.118), "clips": [
        # (ułamek klipu, poza lewej dłoni, poza broni)
        ("reload", 1.35, [(0.0, "grip", "rest"), (0.08, "reach", "tilt"), (0.16, "grab", "show"), (0.24, "rock", "show"),
                          (0.32, "out", "show"), (0.44, "pouch", "show"), (0.56, "back", "show"), (0.66, "hook", "show"),
                          (0.74, "seat", "slap"), (0.82, "leave", "tilt"), (1.0, "grip", "rest")]),
        ("reload_empty", 1.8, [(0.0, "grip", "rest"), (0.06, "reach", "tilt"), (0.12, "grab", "show"), (0.18, "rock", "show"),
                               (0.24, "out", "show"), (0.33, "pouch", "show"), (0.42, "back", "show"), (0.50, "hook", "show"),
                               (0.56, "seat", "slap"), (0.63, "hreach", "lcant"), (0.70, "handle", "lcant"), (0.76, "pulled", "jerk"),
                               (0.80, "release", "slam"), (0.88, "leave", "tilt"), (1.0, "grip", "rest")]),
    ]},
}
# Pozy broni w klipie (względem chwytu prawej dłoni): przechył (°, + = górą w prawo — gniazdo magazynka do lewej dłoni), uniesienie
# lufy (°), podniesienie (m), cofnięcie (m). Prawa ręka idzie za bronią przez IK.
GUN_POSES = {
    "rest": (0.0, 0.0, 0.0, 0.0),
    "tilt": (5.0, 1.0, 0.0, -0.01),
    "show": (10.0, 2.0, 0.0, -0.035),
    "slap": (8.0, 1.0, 0.009, -0.035),      # zatrzaśnięcie: broń podbita od dołu
    "lcant": (-8.0, 1.5, 0.0, -0.01),     # suwadło po prawej: broń przechylona w lewo, rączka na widoku
    "jerk": (-9.0, 1.0, 0.0, 0.004),    # odciągnięcie suwadła szarpie broń w tył
    "slam": (-6.0, 2.5, 0.006, -0.014),  # zamek wraca: broń podbija w górę i w przód
}
# Ułożenia palców bez kontaktu (zgięcie członów 1–3 w °; kciuk osobno): rozwarta dłoń w drodze, hak na rączce suwadła, puszczenie.
FINGER_SETS = {
    "open": ((22.0, 28.0, 18.0), (8.0, 10.0, 8.0)),
    "hook": ((58.0, 78.0, 52.0), (12.0, 22.0, 14.0)),
    "release": ((18.0, 22.0, 14.0), (6.0, 8.0, 6.0)),
}
FPS = 30


def P(rig, n):
    return rig.matrix_world @ rig.pose.bones[PRE + n].head


def T(rig, n):
    return rig.matrix_world @ rig.pose.bones[PRE + n].tail


def update():
    bpy.context.view_layer.update()


def hand_frame(rig, side):
    """Układ dłoni w bieżącej pozie: f — kierunek palców (nadgarstek → nasada środkowego), a — linia kostek (mały → wskazujący),
    b — grzbiet dłoni; pc — środek dłoni (połowa drogi do kostek)."""
    w = P(rig, side + "Hand")
    m = P(rig, side + "HandMiddle1")
    a = (P(rig, side + "HandIndex1") - P(rig, side + "HandPinky1")).normalized()
    f = (m - w).normalized()
    a = (a - f * a.dot(f)).normalized()
    b = f.cross(a) if side == "Right" else a.cross(f)
    return f, a, b.normalized(), w + (m - w) * 0.5


def frame_matrix(f, a, b):
    return Matrix((f, a, b)).transposed()          # kolumny f, a, b


def place_hand(rig, side, gun_m, info, conf, seat=Vector()):
    """Cel nadgarstka i obrót dłoni: linia kostek wzdłuż `up`, grzbiet ku `back` (w układzie broni), wnętrze dłoni na punkcie broni."""
    gr = gun_m.to_3x3().normalized()
    up = (gr @ Vector(conf["up"])).normalized()
    back = (gr @ Vector(conf["back"])).normalized()
    back = (back - up * back.dot(up)).normalized()
    if side == "Right":
        ft = up.cross(back)                         # b = f × a  →  f = a × b
    else:
        ft = back.cross(up)                         # b = a × f  →  f = b × a
    f, a, b, pc = hand_frame(rig, side)
    R = frame_matrix(ft, up, back) @ frame_matrix(f, a, b).inverted()
    w = P(rig, side + "Hand")
    target_pc = gun_m @ (Vector(info[conf["at"]]) + Vector(conf["push"])) + back * conf["off"] + seat
    wrist = target_pc - R @ (pc - w)
    hw = (rig.matrix_world @ rig.pose.bones[PRE + side + "Hand"].matrix).to_3x3().normalized()
    return wrist, (R @ hw).normalized()        # docelowy obrót kości dłoni w świecie


def solve_arm(rig, side, wrist, hand_rot, pole):
    """IK ramienia (przedramię do nadgarstka, biegun łokcia), potem obrót dłoni — ograniczenia zapieczone w pozę."""
    pb_f = rig.pose.bones[PRE + side + "ForeArm"]
    pb_h = rig.pose.bones[PRE + side + "Hand"]
    tgt = bpy.data.objects.new("ik_" + side, None)
    bpy.context.scene.collection.objects.link(tgt)
    tgt.location = wrist
    pol = bpy.data.objects.new("pole_" + side, None)
    bpy.context.scene.collection.objects.link(pol)
    pol.location = pole
    ik = pb_f.constraints.new("IK")
    ik.target = tgt
    ik.pole_target = pol
    ik.pole_angle = math.radians(-90.0)
    ik.chain_count = 2
    ik.use_tail = True
    update()
    rot = bpy.data.objects.new("rot_" + side, None)
    bpy.context.scene.collection.objects.link(rot)
    rot.matrix_world = hand_rot.to_4x4()
    cr = pb_h.constraints.new("COPY_ROTATION")
    cr.target = rot
    update()
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.visual_transform_apply()
    bpy.ops.object.mode_set(mode="OBJECT")
    pb_f.constraints.remove(ik)
    pb_h.constraints.remove(cr)
    for o in (tgt, pol, rot):
        bpy.data.objects.remove(o)
    update()
    share_twist(rig, side, hand_rot)
    err = (P(rig, side + "Hand") - wrist).length
    print("IK %s wrist error %.1f mm" % (side, err * 1000.0))


def share_twist(rig, side, hand_rot, share=0.6):
    """Skręt nadgarstka dzielony z przedramieniem (szkielet nie ma kości skrętu): cały obrót dłoni wokół osi przedramienia w jednym
    stawie zwija skórę rękawicy jak papierek od cukierka. Przedramię bierze `share` skrętu, dłoń wraca do zadanego obrotu."""
    pb_f = rig.pose.bones[PRE + side + "ForeArm"]
    pb_h = rig.pose.bones[PRE + side + "Hand"]
    rest_rel = pb_f.bone.matrix_local.to_3x3().inverted() @ pb_h.bone.matrix_local.to_3x3()
    fw = (rig.matrix_world @ pb_f.matrix).to_3x3().normalized()
    follow = fw @ rest_rel
    axis = (T(rig, side + "ForeArm") - P(rig, side + "ForeArm")).normalized()
    q = (hand_rot @ follow.inverted()).to_quaternion()
    tw = 2.0 * math.atan2(Vector((q.x, q.y, q.z)).dot(axis), q.w)
    tw = (tw + math.pi) % (2.0 * math.pi) - math.pi
    rotate_world(rig, PRE + side + "ForeArm", axis, tw * share)
    update()
    head = rig.matrix_world.inverted() @ P(rig, side + "Hand")
    pb_h.matrix = Matrix.Translation(head) @ (rig.matrix_world.inverted().to_3x3() @ hand_rot).to_4x4()
    update()
    print("TWIST %s %.0f deg (forearm %.0f)" % (side, math.degrees(tw), math.degrees(tw * share)))


def palm_gap(rig, side, bvh):
    """Luz (m) między wnętrzem dłoni a bronią: próbki wzdłuż osi dłoni (nadgarstek → nasada środkowego), promień PALM_R."""
    w, m = P(rig, side + "Hand"), P(rig, side + "HandMiddle1")
    best = 1.0
    for k in range(4):
        hit = bvh.find_nearest(w.lerp(m, 0.35 + 0.2 * k))
        if hit[0] is not None:
            best = min(best, hit[3] - PALM_R)
    return best


def seat_hand(rig, side, G, info, c, bvh, pole):
    """Osadzenie dłoni: cel przesuwany wzdłuż grzbietu dłoni, aż wnętrze dłoni dotknie broni (bez wchodzenia w nią), IK po każdym kroku."""
    seat = Vector()
    for it in range(8):
        wrist, R = place_hand(rig, side, G, info, c, seat)
        solve_arm(rig, side, wrist, R, pole)
        gap = palm_gap(rig, side, bvh)
        if abs(gap) < 0.0015:
            break
        seat -= hand_frame(rig, side)[2] * gap * 0.9
    print("SEAT %s palm gap %.1f mm (shift %.1f mm)" % (side, gap * 1000.0, seat.length * 1000.0))


def rotate_world(rig, name, axis_w, ang):
    """Obrót kości o kąt wokół osi świata (przez jej własny układ)."""
    pb = rig.pose.bones[name]
    m = (rig.matrix_world @ pb.matrix).to_3x3().normalized()
    al = (m.inverted() @ axis_w).normalized()
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(al, ang)


def _touch(rig, bones, radii, bvh):
    """Najmniejszy luz (m) między kapsułami członów a bronią (< 0 — człon w broni)."""
    best = 1.0
    for n, r in zip(bones, radii):
        h, t = P(rig, n), T(rig, n)
        for k in range(5):
            p = h.lerp(t, k / 4.0)
            hit = bvh.find_nearest(p)
            if hit[0] is not None:
                best = min(best, hit[3] - r)
    return best


def curl_finger(rig, side, finger, bvh, back):
    """Zgina palec do kontaktu: najpierw wszystkie człony razem (1 : 1 : 0,7), potem coraz dalsze osobno — każdy, aż dotknie broni."""
    names = [side + "Hand" + finger + str(i) for i in (1, 2, 3)]
    radii = THUMB_R if finger == "Thumb" else SEG_R
    weights = (1.0, 1.0, 0.7)
    if _touch(rig, names, radii, bvh) < -0.001:               # człon zaczyna w broni (kciuk po drugiej stronie chwytu): najpierw rozgięcie
        ang = 0.0
        while _touch(rig, names, radii, bvh) < 0.0 and ang < math.radians(25.0):     # dalej kciuk sterczałby w kadr
            for i in range(3):
                d = (T(rig, names[i]) - P(rig, names[i])).normalized()
                rotate_world(rig, PRE + names[i], back.cross(d).normalized(), -STEP * weights[i])
            update()
            ang += STEP
        print("UNCURL %s %s %.0f deg" % (side, finger, math.degrees(ang)))
        return
    for start in range(3):
        ang = 0.0
        while ang < CURL_MAX:
            if _touch(rig, names[start:], radii[start:], bvh) < 0.0005:
                break
            for i in range(start, 3):
                d = (T(rig, names[i]) - P(rig, names[i])).normalized()
                ax = back.cross(d)
                if finger == "Thumb":
                    ax = (back.cross(d) + d.cross(back.cross(d)) * 0.0).normalized()
                rotate_world(rig, PRE + names[i], ax.normalized(), STEP * (weights[i] if start == 0 else (1.0 if i == start else 0.0)))
            update()
            ang += STEP
        # cofnij o pół kroku, jeśli człon wszedł w broń
        if _touch(rig, names[start:], radii[start:], bvh) < -0.0015:
            for i in range(start, 3):
                d = (T(rig, names[i]) - P(rig, names[i])).normalized()
                rotate_world(rig, PRE + names[i], back.cross(d).normalized(), -STEP * 0.5)
            update()
    print("CURL %s %s gap %.1f mm" % (side, finger, _touch(rig, names, radii, bvh) * 1000.0))


def _pose_get(rig):
    return {pb.name: pb.rotation_quaternion.copy() for pb in rig.pose.bones}


def _pose_set(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = pose[pb.name]
        pb.location = Vector()
    update()


def gun_pose(G, info, name):
    """Broń w pozie klipu: obroty wokół punktu chwytu (prawa dłoń), potem podniesienie i cofnięcie w układzie broni."""
    roll, pitch, lift, back = GUN_POSES[name]
    piv = Vector(info["grip"])
    M = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(-pitch), 4, "Y") @ Matrix.Rotation(math.radians(roll), 4, "X") @ Matrix.Translation(-piv)
    return G @ Matrix.Translation(Vector((-back, 0.0, lift))) @ M


def curl_fixed(rig, side, finger, back, angles):
    """Palec zgięty o stałe kąty członów (°) wokół osi zgięcia (grzbiet dłoni × kierunek członu)."""
    for i, deg in enumerate(angles):
        n = side + "Hand" + finger + str(i + 1)
        if PRE + n not in rig.pose.bones:
            continue
        d = (T(rig, n) - P(rig, n)).normalized()
        rotate_world(rig, PRE + n, back.cross(d).normalized(), math.radians(deg))
        update()


def _hand_bones(rig, side):
    return [pb.name for pb in rig.pose.bones if pb.name.startswith(PRE + side + "Hand") and pb.name != PRE + side + "Hand"]


def author_reloads(rig, key, G, info, conf, meshes, root):
    """Klipy przeładowania: klatki kluczowe obu rąk. Broń ma w każdej klatce własną pozę (GUN_POSES) — prawa ręka idzie za nią przez IK
    z osadzeniem dłoni i palcami jak w chwycie; lewa dłoń po swoich pozach (IK + podział skrętu), palce na magazynku do kontaktu albo
    w ułożeniach FINGER_SETS. Magazynek jedzie z lewą dłonią od pierwszego `grab` do `seat` (`mag_out` / `mag_in` w .json)."""
    spec = RELOADS[key]
    grip_pose = _pose_get(rig)
    rig.animation_data.action = None                                # bez klipu: render nie nadpisuje układanej pozy
    mag = next((o for o in meshes if o.name.endswith("__mag")), None)
    Gi = G.inverted()
    if mag is not None:
        pts = [Gi @ (mag.matrix_world @ Vector(c)) for c in mag.bound_box]
    else:
        pts = [Vector((0.03, -0.015, -0.12)), Vector((0.11, 0.015, 0.02))]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    grab_p = Vector(((lo.x + hi.x) * 0.5, hi.y, lo.z + (hi.z - lo.z) * 0.45))
    hp = Vector(spec["handle"])
    right_fingers = {n: grip_pose[n] for n in _hand_bones(rig, "Right")}
    hand_grip = rig.matrix_world @ rig.pose.bones[PRE + "RightHand"].matrix
    hold = Vector(info["hold"]) + Vector(conf["left"]["push"])
    up_mag = (0.2, 0.0, 0.98)
    bk_mag = (0.0, 1.0, 0.0)
    # lewa dłoń: punkt w układzie broni, linia kostek, grzbiet, odstęp, palce ("mag" — do kontaktu z magazynkiem, "held" — jak przy
    # chwycie magazynka, albo nazwa z FINGER_SETS)
    targets = {
        "reach": (hold.lerp(grab_p, 0.5) + Vector((0.0, 0.03, -0.03)), (0.6, 0.0, 0.8), (0.0, 0.8, -0.6), 0.02, "open"),
        "grab": (grab_p, up_mag, bk_mag, 0.012, "mag"),
        "rock": (grab_p + Vector((0.03, 0.005, -0.05)), (0.45, 0.0, 0.89), bk_mag, 0.012, "held"),
        "out": (grab_p + Vector((0.02, 0.05, -0.16)), (0.3, 0.2, 0.93), (-0.1, 0.99, 0.0), 0.012, "held"),
        "pouch": (grab_p + Vector((-0.08, 0.22, -0.42)), (0.1, 0.25, 0.96), (-0.3, 0.95, 0.0), 0.012, "held"),
        "back": (grab_p + Vector((0.03, 0.04, -0.14)), (0.35, 0.15, 0.92), (-0.05, 0.99, 0.0), 0.012, "held"),
        "hook": (grab_p + Vector((0.022, 0.0, -0.028)), (0.42, 0.0, 0.91), bk_mag, 0.012, "held"),
        "seat": (grab_p, up_mag, bk_mag, 0.012, "held"),
        "leave": (hold.lerp(grab_p, 0.35) + Vector((0.0, 0.02, -0.035)), (0.8, 0.0, 0.6), (0.0, 0.6, -0.8), 0.02, "open"),
        # suwadło od dołu: dłoń pod komorą wnętrzem do góry, palce hakiem na rączce z prawej (z góry przedramię zasłaniało cały kadr)
        "hreach": (hp + Vector((0.05, 0.0, -0.07)), (1.0, 0.0, 0.0), (0.0, 0.3, -0.95), 0.02, "open"),
        "handle": (hp + Vector((0.0, -0.012, -0.045)), (1.0, 0.0, 0.0), (0.0, 0.3, -0.95), 0.010, "hook"),
        "pulled": (hp + Vector((-0.11, -0.012, -0.045)), (1.0, 0.0, 0.0), (0.0, 0.3, -0.95), 0.010, "hook"),
        "release": (hp + Vector((-0.09, 0.01, -0.09)), (1.0, 0.0, 0.0), (0.0, 0.4, -0.92), 0.02, "release"),
    }
    poses = {}
    held_fingers = None
    order = []
    for _c, _s, keys in spec["clips"]:
        for _t, h, g in keys:
            if (h, g) not in order:
                order.append((h, g))
    order.sort(key=lambda hg: 0 if hg[0] == "grab" else 1)           # najpierw chwyt magazynka (palce „held” biorą się z niego)
    for hname, gname in order:
        Gk = gun_pose(G, info, gname)
        root.matrix_world = Gk
        update()
        bvh = gun_bvh(meshes)
        mag_bvh = gun_bvh([mag]) if mag is not None else bvh
        _pose_set(rig, grip_pose)
        if gname != "rest":                                          # prawa ręka za bronią: dłoń osadzona na chwycie, palce jak w chwycie
            seat_hand(rig, "Right", Gk, info, conf["right"], bvh, P(rig, "RightArm") + Vector((-0.1, -0.9, 0.5)))
            for n, q in right_fingers.items():
                rig.pose.bones[n].rotation_quaternion = q
            update()
            hk = rig.matrix_world @ rig.pose.bones[PRE + "RightHand"].matrix
            implied = hk @ hand_grip.inverted() @ G
            d = implied.inverted() @ Gk
            print("RHCHK %s/%s rot %.1f deg pos %.1f mm" % (hname, gname, math.degrees(d.to_quaternion().angle), d.translation.length * 1000))
        if hname == "grip":
            if gname != "rest":
                seat_hand(rig, "Left", Gk, info, conf["left"], bvh, P(rig, "LeftArm") + Vector((0.2, 0.9, 0.4)))
                for n in _hand_bones(rig, "Left"):
                    rig.pose.bones[n].rotation_quaternion = grip_pose[n]
                update()
            poses[(hname, gname)] = _pose_get(rig)
            continue
        p, up, back, off, fingers = targets[hname]
        for n in _hand_bones(rig, "Left"):                           # palce lewej dłoni od spoczynku (rozwarta dłoń)
            rig.pose.bones[n].rotation_quaternion = Quaternion()
        update()
        c = {"at": "p", "push": (0.0, 0.0, 0.0), "up": up, "back": back, "off": off}
        wrist, hrot = place_hand(rig, "Left", Gk, {"p": tuple(p)}, c)
        solve_arm(rig, "Left", wrist, hrot, P(rig, "LeftArm") + Vector((0.2, 0.9, 0.4)))
        bk = hand_frame(rig, "Left")[2]
        if fingers == "mag":
            for fg in FINGERS + ("Thumb",):
                curl_finger(rig, "Left", fg, mag_bvh, bk)
            held_fingers = {n: rig.pose.bones[n].rotation_quaternion.copy() for n in _hand_bones(rig, "Left")}
        elif fingers == "held" and held_fingers is not None:
            for n, q in held_fingers.items():
                rig.pose.bones[n].rotation_quaternion = q
            update()
        elif fingers in FINGER_SETS:
            fa, ta = FINGER_SETS[fingers]
            for fg in FINGERS:
                curl_fixed(rig, "Left", fg, bk, fa)
            curl_fixed(rig, "Left", "Thumb", bk, ta)
        poses[(hname, gname)] = _pose_get(rig)
        print("RELOAD %s %s/%s" % (key, hname, gname))
    # podglądy wybranych klatek (z lewej strony, nad bronią)
    for hname, gname in (("grab", "show"), ("out", "show"), ("hook", "show"), ("handle", "lcant"), ("pulled", "jerk")):
        if (hname, gname) in poses:
            Gk = gun_pose(G, info, gname)
            root.matrix_world = Gk
            _pose_set(rig, poses[(hname, gname)])
            mid = Gk @ Vector((0.1, 0.0, 0.0))
            render(os.path.join(SHOTS, "reload_%s_%s.png" % (key, hname)), look(mid + Vector((0.25, 0.85, 0.1)), mid), 32.0)
    root.matrix_world = G
    update()
    meta = {}
    for clip, secs, keys in spec["clips"]:
        act = bpy.data.actions.new("%s_%s" % (clip, key))
        rig.animation_data.action = act
        last = max(1, round(secs * FPS))
        for t, hname, gname in keys:
            _pose_set(rig, poses[(hname, gname)])
            fr = 1 + round(t * last)
            for pb in rig.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=fr)
                pb.keyframe_insert("location", frame=fr)
        for fc in getattr(act, "fcurves", []):                       # łagodne wejścia i wyjścia z klatek (bez szarpnięć interpolacji)
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.handle_left_type = "AUTO_CLAMPED"
                kp.handle_right_type = "AUTO_CLAMPED"
        grabs = [t for t, h, _g in keys if h == "grab"]
        seats = [t for t, h, _g in keys if h == "seat"]
        meta[clip] = {"secs": secs, "mag_out": grabs[0], "mag_in": seats[-1]}
        print("CLIP", act.name, last + 1, "frames", meta[clip])
    _pose_set(rig, grip_pose)
    return meta


def gun_object(key):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ART, "gun_%s.glb" % key))
    new = set(bpy.data.objects) - before
    root = bpy.data.objects.new("gun_" + key, None)
    bpy.context.scene.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    return root, [o for o in new if o.type == "MESH"]


def gun_bvh(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        off = len(verts)
        verts += [o.matrix_world @ v.co for v in me.vertices]
        polys += [[off + i for i in p.vertices] for p in me.polygons]
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def render(path, cam_m, lens=24.0):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    cam = bpy.data.objects.get("shotcam") or bpy.data.objects.new("shotcam", bpy.data.cameras.new("shotcam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.matrix_world = cam_m
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("SHOT", path)


def lights():
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.05, 0.055, 1.0)
    bpy.context.scene.world = w
    for loc, e in (((0.6, -0.4, 2.6), 120.0), ((-0.4, 0.8, 1.9), 35.0)):
        L = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "AREA"))
        L.data.energy = e
        L.data.size = 0.8
        L.location = loc
        L.rotation_euler = (Vector((0.4, 0.0, 1.35)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(L)


def look(eye, at, roll_up=Vector((0, 0, 1))):
    q = (at - eye).to_track_quat("-Z", "Y")
    return Matrix.Translation(eye) @ q.to_matrix().to_4x4()


def build(outfit, keys):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, "fp_arms_%s.blend" % outfit))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    reload_meta = {}
    lights()
    os.makedirs(SHOTS, exist_ok=True)
    for key in keys:
        conf = GRIPS[key]
        info = json.load(open(os.path.join(ART, "gun_%s.json" % key)))
        root, meshes = gun_object(key)
        update()
        lo = min((o.matrix_world @ Vector(c)).x for o in meshes for c in o.bound_box)
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        update()
        # obojczyki w przód (prawy mniej: kolba w barku), potem broń: stopka kolby w zagłębieniu prawego barku
        for side, deg in zip(("Right", "Left"), conf["clav"]):
            rotate_world(rig, PRE + side + "Shoulder", Vector((0, 0, 1)) * (-1.0 if side == "Left" else 1.0), math.radians(deg))
        update()
        pocket = P(rig, "RightArm") + Vector((0.03, 0.06, -0.05))
        butt = Vector((lo + 0.03, 0.0, info["grip"][2] + conf["butt_dz"]))
        G = Matrix.Translation(pocket) @ Matrix.Rotation(math.radians(conf["yaw"]), 4, "Z") @ Matrix.Translation(-butt)
        root.matrix_world = G
        update()
        bvh = gun_bvh(meshes)
        for side, pole in (("Right", Vector((-0.1, -0.9, 0.5))), ("Left", Vector((0.2, 0.9, 0.4)))):
            c = conf[side.lower()]
            seat_hand(rig, side, G, info, c, bvh, P(rig, side + "Arm") + pole)
            f2, a2, b2, pc2 = hand_frame(rig, side)
            gr = G.to_3x3().normalized()
            want_pc = G @ (Vector(info[c["at"]]) + Vector(c["push"]))
            print("HAND %s f %s a %s b %s | want up %s back %s | palm-point %.1f mm" % (side, tuple(round(x, 2) for x in f2), tuple(round(x, 2) for x in a2),
                  tuple(round(x, 2) for x in b2), tuple(round(x, 2) for x in (gr @ Vector(c["up"])).normalized()), tuple(round(x, 2) for x in (gr @ Vector(c["back"])).normalized()),
                  (pc2 - want_pc).length * 1000))
            back = hand_frame(rig, side)[2]
            for fg in FINGERS + ("Thumb",):
                curl_finger(rig, side, fg, bvh, back)
        # klip pozy i punkt odniesienia broni na kości prawej dłoni
        act = bpy.data.actions.new("grip_" + key)
        rig.animation_data_create()
        rig.animation_data.action = act
        for pb in rig.pose.bones:
            for fr in (1, 2):
                pb.keyframe_insert("rotation_quaternion", frame=fr)
                pb.keyframe_insert("location", frame=fr)
        ref = bpy.data.objects.new("gunref_" + key, None)
        bpy.context.scene.collection.objects.link(ref)
        ref.parent = rig
        ref.parent_type = "BONE"
        ref.parent_bone = PRE + "RightHand"
        update()
        ref.matrix_world = G
        update()
        rig.animation_data.action = act
        update()
        eye = G @ Vector((info["grip"][0] - 0.27, 0.0, 0.215))
        render(os.path.join(SHOTS, "grip_%s_eye.png" % key), look(eye, G @ Vector((1.5, 0.0, 0.17))), 20.0)
        mid = G @ Vector((0.1, 0.0, 0.08))
        render(os.path.join(SHOTS, "grip_%s_side.png" % key), look(mid + Vector((0.05, -0.75, 0.15)), mid), 35.0)
        render(os.path.join(SHOTS, "grip_%s_left.png" % key), look(mid + Vector((0.15, 0.7, -0.05)), mid), 35.0)
        body_c = P(rig, "Spine2")
        render(os.path.join(SHOTS, "grip_%s_wide.png" % key), look(body_c + Vector((0.9, -1.4, 0.35)), body_c + Vector((0.35, 0.0, -0.1))), 30.0)
        render(os.path.join(SHOTS, "grip_%s_top.png" % key), look(body_c + Vector((0.35, -0.05, 1.6)), body_c + Vector((0.35, 0.0, -0.1))), 30.0)
        if key in RELOADS:
            reload_meta[key] = author_reloads(rig, key, G, info, conf, meshes, root)
            rig.animation_data.action = act
            update()
        root.hide_render = True
        root.hide_viewport = True
        for o in meshes:
            o.hide_render = True
            o.hide_viewport = True
    # eksport: ręce, szkielet, klipy chwytów, punkty odniesienia broni (bez modeli broni)
    for o in list(bpy.data.objects):
        if o.name.startswith("gun_") or (o.type == "MESH" and o.parent is not None and o.parent.name.startswith("gun_")) or o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent != rig:
            bpy.data.objects.remove(o)
    dst = os.path.join(ART, "fp", "fp_arms_%s.glb" % outfit)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="WEBP", export_image_quality=90,
                              export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_apply=False, export_morph=False)
    print("OK", dst)
    with open(os.path.splitext(dst)[0] + ".json", "w") as f:        # momenty przeładowań dla range_view.gd
        json.dump(reload_meta, f, indent=1)


names = [a for a in argv if not a.startswith("--")]
if names:
    build(names[0], names[1:] or list(GRIPS))
