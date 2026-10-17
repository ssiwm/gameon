"""Szkieletuje statyczny model humanoida z TRELLIS-a (comfy_gen.py model) szkieletem Mixamo (`mixamorig:*`), tak jak modele wrogów z Tripo, żeby `enemy3d.gd` mógł nim
poruszać (IK nóg i rąk, klipy). Blender headless:

    blender -b --factory-startup -P prototype/tools/rig_trellis.py -- SRC.glb DST_rig.glb [--face=-y] [--height=1.8] [--preset=humanoid|brute|crawler] [--preview=PREFIX] [--attach=PROP.glb --attach-bone=RightHand --attach-length=0.8 --attach-handle=auto|lo|hi]

Co robi: scala siatki, obraca model przodem do +X (jak modele Tripo w grze), skaluje do `--height` m i stawia stopami na z = 0; wykrywa punkty orientacyjne ciała na przekrojach siatki
(biodra, kolana, kostki, barki, nadgarstki z skrajnych punktów rąk), buduje 23 kości Mixamo w tych punktach, liczy wagi na uproszczonej, szczelnej kopii (voxel remesh + automatyczne wagi)
i przenosi je na pełną siatkę (najbliższa powierzchnia). `--preview=PREFIX` zapisuje trzy renderowane pozy (spoczynek, krok, ręka w górze) do oceny wag.
Gra liczy pozę przez IK po długościach kości i pozycjach spoczynkowych (nie po osiach lokalnych), więc dokładne role kości nie mają znaczenia.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

BONES = [  # (nazwa, rodzic)
    ("Root", None), ("Hips", "Root"), ("LeftUpLeg", "Hips"), ("LeftLeg", "LeftUpLeg"), ("LeftFoot", "LeftLeg"), ("LeftToeBase", "LeftFoot"),
    ("RightUpLeg", "Hips"), ("RightLeg", "RightUpLeg"), ("RightFoot", "RightLeg"), ("RightToeBase", "RightFoot"),
    ("Spine", "Hips"), ("Spine1", "Spine"), ("Spine2", "Spine1"),
    ("LeftShoulder", "Spine2"), ("LeftArm", "LeftShoulder"), ("LeftForeArm", "LeftArm"), ("LeftHand", "LeftForeArm"),
    ("Neck", "Spine2"), ("Head", "Neck"),
    ("RightShoulder", "Spine2"), ("RightArm", "RightShoulder"), ("RightForeArm", "RightArm"), ("RightHand", "RightForeArm"),
]

# proporcje (ułamek wysokości H): bioder, kolana, kostki, kręgosłup, szyja; barki i nadgarstki bierzemy z siatki
PRESETS = {
    "humanoid": {"hips": 0.52, "knee": 0.27, "ankle": 0.05, "spine": [0.58, 0.66, 0.75], "shoulder": 0.80, "neck": 0.83, "head": 0.88, "hip_w": 0.055, "sh_w": 0.11},
    "brute": {"hips": 0.47, "knee": 0.25, "ankle": 0.05, "spine": [0.55, 0.64, 0.73], "shoulder": 0.78, "neck": 0.82, "head": 0.88, "hip_w": 0.08, "sh_w": 0.17},
    "crawler": {"hips": 0.50, "knee": 0.26, "ankle": 0.05, "spine": [0.56, 0.64, 0.72], "shoulder": 0.76, "neck": 0.82, "head": 0.88, "hip_w": 0.07, "sh_w": 0.13},
}


def arg(name, default=None):
    for a in sys.argv[sys.argv.index("--") + 1:]:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default


def load_and_normalize(src, face, height):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = max(meshes, key=lambda m: len(m.data.vertices))
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.parent = None
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    # przód: do +X. TRELLIS (glTF +Z do przodu) daje w Blenderze przód w −Y; `--face=-y|+y|-x|+x` mówi, gdzie model patrzy teraz
    rot = {"-y": 90.0, "+y": -90.0, "+x": 0.0, "-x": 180.0}[face]
    pts = np.array([(body.matrix_world @ v.co)[:] for v in body.data.vertices])
    pts = np.array([Matrix.Rotation(math.radians(rot), 3, "Z") @ Vector(p) for p in pts])
    zmin, zmax = pts[:, 2].min(), pts[:, 2].max()
    k = height / (zmax - zmin)
    cx = (pts[:, 0].min() + pts[:, 0].max()) / 2
    cy = (pts[:, 1].min() + pts[:, 1].max()) / 2
    new = (pts - np.array([cx, cy, zmin])) * k
    for v, p in zip(body.data.vertices, new):
        v.co = Vector(p)
    body.data.update()
    return body, new


def slice_center(pts, z0, z1, lat_sign=0, lat_min=0.0):
    """Środek (x, y) wierzchołków w pasie wysokości; lat_sign ±1 ogranicza do strony ciała (y)."""
    m = (pts[:, 2] >= z0) & (pts[:, 2] <= z1)
    if lat_sign:
        m &= (pts[:, 1] * lat_sign) >= lat_min
    if m.sum() < 4:
        return None
    return pts[m][:, 0].mean(), pts[m][:, 1].mean()


def landmarks(pts, H, P):
    L = {}
    cxm = pts[:, 0].mean()
    for side, sg in (("Left", 1), ("Right", -1)):
        hip = slice_center(pts, 0.44 * H, 0.50 * H, sg, 0.01 * H) or (cxm, sg * P["hip_w"] * H)
        knee = slice_center(pts, P["knee"] * H - 0.05 * H, P["knee"] * H + 0.05 * H, sg, 0.01 * H) or hip
        ank = slice_center(pts, 0.0, 0.09 * H, sg, 0.01 * H) or hip
        hy = max(abs(hip[1]), P["hip_w"] * H * 0.7) * sg
        L[side + "UpLeg"] = Vector((hip[0], hy, P["hips"] * H - 0.02 * H))
        L[side + "Leg"] = Vector((knee[0], max(abs(knee[1]), abs(hy) * 0.9) * sg, P["knee"] * H))
        L[side + "Foot"] = Vector((ank[0] - 0.02 * H, max(abs(ank[1]), abs(hy) * 0.8) * sg, P["ankle"] * H))
        L[side + "ToeBase"] = Vector((ank[0] + 0.09 * H, L[side + "Foot"].y, 0.02 * H))
        # ręka: nadgarstek z skrajnych bocznych punktów (dłoń) w paśmie od pasa w górę
        m = (pts[:, 2] > 0.30 * H) & (pts[:, 2] < 0.85 * H) & ((pts[:, 1] * sg) > 0)
        lat = pts[m][:, 1] * sg
        thr = lat.max() * 0.8
        hand = pts[m][lat >= thr]
        wrist = Vector(hand.mean(axis=0)) if len(hand) else Vector((cxm, sg * 0.35 * H, 0.5 * H))
        sh = Vector((cxm, sg * min(P["sh_w"] * H, abs(wrist.y) * 0.5), P["shoulder"] * H))
        L[side + "Shoulder"] = Vector((cxm, sg * 0.03 * H, P["shoulder"] * H + 0.01 * H))
        L[side + "Arm"] = sh
        L[side + "Hand"] = wrist
        L[side + "ForeArm"] = sh.lerp(wrist, 0.5) + Vector((-0.02 * H, 0.0, 0.0))
    L["Hips"] = Vector((cxm, 0.0, P["hips"] * H))
    L["Spine"] = Vector((cxm, 0.0, P["spine"][0] * H))
    L["Spine1"] = Vector((cxm, 0.0, P["spine"][1] * H))
    L["Spine2"] = Vector((cxm, 0.0, P["spine"][2] * H))
    L["Neck"] = Vector((cxm, 0.0, P["neck"] * H))
    L["Head"] = Vector((cxm + 0.01 * H, 0.0, P["head"] * H))
    L["Root"] = Vector((cxm, 0.0, 0.0))
    return L


def build_armature(L, H):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    children = {}
    for n, p in BONES:
        children.setdefault(p, []).append(n)
    ends = {"Head": Vector((0, 0, 0.1 * H)), "LeftHand": None, "RightHand": None, "LeftToeBase": Vector((0.04 * H, 0, 0)), "RightToeBase": Vector((0.04 * H, 0, 0))}
    for n, p in BONES:
        b = arm_data.edit_bones.new("mixamorig:" + n)
        b.head = L[n]
        kids = [c for c in children.get(n, []) if c not in ("LeftShoulder", "RightShoulder") or n == "Spine2"]
        if n == "Spine2":
            kids = ["Neck"]
        if n in ("Hips",):
            kids = ["Spine"]
        if n == "Root":
            kids = ["Hips"]
        if kids and kids[0] in L:
            tail = L[kids[0]]
        else:
            ext = ends.get(n)
            if n.endswith("Hand"):
                dirv = (L[n] - L[n.replace("Hand", "ForeArm")]).normalized()
                tail = L[n] + dirv * 0.08 * H
            else:
                tail = L[n] + (ext if ext is not None else Vector((0, 0, 0.05 * H)))
        if (tail - b.head).length < 0.01:
            tail = b.head + Vector((0, 0, 0.03 * H))
        b.tail = tail
    for n, p in BONES:
        if p:
            arm_data.edit_bones["mixamorig:" + n].parent = arm_data.edit_bones["mixamorig:" + p]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def skin(body, arm, H):
    # szczelna, uproszczona kopia do automatycznych wag (siatka z TRELLIS-a bywa nieszczelna / samoprzecinająca się)
    proxy = body.copy()
    proxy.data = body.data.copy()
    proxy.name = "proxy"
    bpy.context.scene.collection.objects.link(proxy)
    proxy.modifiers.clear()
    mod = proxy.modifiers.new("remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = H / 90.0
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    print("PROXY groups", len(proxy.vertex_groups), "verts", len(proxy.data.vertices))
    # przeniesienie wag na pełną siatkę
    bpy.context.view_layer.objects.active = body
    for vg in proxy.vertex_groups:
        body.vertex_groups.new(name=vg.name)
    dt = body.modifiers.new("wt", "DATA_TRANSFER")
    dt.object = proxy
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(proxy, do_unlink=True)
    body.parent = arm
    am = body.modifiers.new("Armature", "ARMATURE")
    am.object = arm
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 0.001 for g in v.groups))
    print("WEIGHTS body groups", len(body.vertex_groups), "unweighted verts", unweighted, "of", len(body.data.vertices))
    if unweighted > 0.03 * len(body.data.vertices):
        skin_by_distance(body, arm, H)
    fix_hands(body, arm, H)
    split_islands(body)


def fix_hands(body, arm, H):
    """Palce i pazury za nadgarstkiem w całości na kość dłoni. Szczelna kopia do wag (voxel H/90) gubi cienkie pazury, więc dostawały wagi
    od najbliższej powierzchni — szaty, uda, biodra — i przy uniesionej ręce zostawały na dole, rozciągnięte w długie „pręty" (Kapłan).
    Wierzchołek idzie na dłoń, gdy leży za nadgarstkiem, blisko przedłużenia kości dłoni (0,22 H) i wyraźnie bliżej niej niż kości tułowia i nóg."""
    pts = np.array([v.co[:] for v in body.data.vertices])
    mw = arm.matrix_world

    def seg_dist(a, b):
        ab = b - a
        t = np.clip(((pts - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
        return np.linalg.norm(pts - (a + t[:, None] * ab), axis=1)

    other = []
    for bn in arm.data.bones:
        if not any(k in bn.name for k in ("Arm", "Hand", "Shoulder", "Root")):
            other.append(seg_dist(np.array(mw @ bn.head_local), np.array(mw @ bn.tail_local)))
    d_other = np.min(np.array(other), axis=0)
    total = 0
    for side in ("Left", "Right"):
        hb = arm.data.bones["mixamorig:%sHand" % side]
        head = np.array(mw @ hb.head_local)
        dirv = np.array(mw @ hb.tail_local) - head
        dirv = dirv / max(np.linalg.norm(dirv), 1e-9)
        t = (pts - head) @ dirv
        d_hand = seg_dist(head - dirv * 0.02 * H, head + dirv * 0.22 * H)
        sel = np.where((t > -0.02 * H) & (d_hand < 0.10 * H) & (d_hand < 0.8 * d_other))[0]
        name = "mixamorig:%sHand" % side
        g = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
        idx = set(int(i) for i in sel)
        for vg in body.vertex_groups:
            if vg.name != name:
                vg.remove(list(idx))
        g.add(list(idx), 1.0, "REPLACE")
        total += len(idx)
    print("HANDS fixed verts", total)


def split_islands(body):
    """Siatka z TRELLIS-a to „zupa" ponad tysiąca luźnych kawałków. Kawałek z wagami zmieszanymi między ręką a tułowiem/nogą rozciąga się przy
    każdym ruchu ręki (pazur przyklejony do uda, strzęp szaty ciągnięty za dłonią). Każdy kawałek trafia więc w całości do jednej klasy — ręka lewa,
    ręka prawa albo reszta ciała — tej, która ma w nim większą sumę wag; wpływy pozostałych klas są usuwane."""
    import bmesh
    groups = {g.index: g.name for g in body.vertex_groups}

    def cls(name):
        for side in ("Left", "Right"):
            if any(name == "mixamorig:%s%s" % (side, b) for b in ("Arm", "ForeArm", "Hand")):
                return side
        return "Body"

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    seen = [False] * len(bm.verts)
    fixed = 0
    verts = body.data.vertices
    for s0 in range(len(bm.verts)):
        if seen[s0]:
            continue
        stack, comp = [s0], []
        seen[s0] = True
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in bm.verts[x].link_edges:
                o = e.other_vert(bm.verts[x]).index
                if not seen[o]:
                    seen[o] = True
                    stack.append(o)
        sums = {"Left": 0.0, "Right": 0.0, "Body": 0.0}
        for i in comp:
            for g in verts[i].groups:
                sums[cls(groups[g.group])] += g.weight
        if sum(1 for v in sums.values() if v > 0.0) < 2 or len(comp) > 0.02 * len(bm.verts):
            continue                                          # duży kawałek (np. ręka zrośnięta z tułowiem) zostaje z płynnymi wagami
        keep = max(sums, key=sums.get)
        for i in comp:
            v = verts[i]
            drop = [g.group for g in v.groups if cls(groups[g.group]) != keep]
            if not drop:
                continue
            best = max((g for g in v.groups if cls(groups[g.group]) == keep), key=lambda g: g.weight, default=None)
            for gi in drop:
                body.vertex_groups[gi].remove([i])
            if best is None:                                  # wierzchołek bez wag w wybranej klasie: dominująca kość kawałka
                tally = {}
                for j in comp:
                    for g in verts[j].groups:
                        if cls(groups[g.group]) == keep:
                            tally[g.group] = tally.get(g.group, 0.0) + g.weight
                body.vertex_groups[max(tally, key=tally.get)].add([i], 1.0, "REPLACE")
            fixed += 1
    bm.free()
    print("ISLANDS fixed verts", fixed)


def skin_by_distance(body, arm, H):
    """Zapasowe wagi, gdy automatyczne (heat) się nie udają (np. siatka z wyspami, łańcuchy): waga kości ∝ 1/(odległość do odcinka kości)⁴ dla trzech najbliższych kości."""
    for vg in list(body.vertex_groups):
        body.vertex_groups.remove(vg)
    names = []
    segs = []
    for b in arm.data.bones:
        if b.name in ("mixamorig:Root",):
            continue
        names.append(b.name)
        segs.append((np.array(arm.matrix_world @ b.head_local), np.array(arm.matrix_world @ b.tail_local)))
    mult = np.array([0.35 if ("Shoulder" in n or "ToeBase" in n) else 1.0 for n in names])
    pts = np.array([v.co[:] for v in body.data.vertices])
    D = np.empty((len(pts), len(names)))
    for j, (a, bb) in enumerate(segs):
        ab = bb - a
        t = np.clip(((pts - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
        D[:, j] = np.linalg.norm(pts - (a + t[:, None] * ab), axis=1)
    W = (1.0 / (D + 0.01 * H)) ** 4 * mult
    keep = np.argsort(-W, axis=1)[:, :3]
    groups = {n: body.vertex_groups.new(name=n) for n in names}
    for i in range(len(pts)):
        ws = W[i, keep[i]]
        ws = ws / ws.sum()
        for k, w in zip(keep[i], ws):
            if w > 0.02:
                groups[names[k]].add([i], float(w), "REPLACE")
    unweighted = sum(1 for v in body.data.vertices if not v.groups)
    print("WEIGHTS(distance) groups", len(groups), "unweighted", unweighted, "of", len(pts))


def attach_prop(body, arm, L, H, path, bone, length, forward, handle="auto"):
    """Dołącza rekwizyt (np. tasak z osobnego modelu) do kości dłoni: siatka rekwizytu dostaje wagę 1 na tej kości i zostaje scalona z ciałem (jedna siatka, wiele materiałów).
    Uchwyt = węższy koniec modelu (większy rozrzut przekroju na drugim końcu); rekwizyt celuje ostrzem pionowo w dół (lekko do przodu, +X), a cały uchwyt chowa się w pięści."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(o in new)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    prop = bpy.context.view_layer.objects.active
    prop.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o not in before and o is not prop:
            bpy.data.objects.remove(o, do_unlink=True)
    pts = np.array([v.co[:] for v in prop.data.vertices])
    c = pts.mean(axis=0)
    u, s, vt = np.linalg.svd(pts - c, full_matrices=False)
    ax = vt[0]
    proj = (pts - c) @ ax
    lo, hi = proj.min(), proj.max()
    span = hi - lo

    def spread(mask):
        q = pts[mask] - c
        q = q - np.outer(q @ ax, ax)
        return float(np.median(np.linalg.norm(q, axis=1))) if mask.sum() else 0.0

    # mediana odległości od osi na 30 % długości z każdej strony: ostrze jest szerokie na całym odcinku, a uchwyt wąski — dyndający łańcuszek
    # przy głowicy (tasak Rzeźnika) to mało wierzchołków, więc mediany nie przesuwa (średnia z samych 12 % końca myliła się właśnie przez łańcuszek)
    s_lo = spread(proj < lo + 0.30 * span)
    s_hi = spread(proj > hi - 0.30 * span)
    handle_at_lo = s_lo < s_hi                         # węższy koniec = uchwyt
    if handle in ("lo", "hi"):                         # jawne nadpisanie (`--attach-handle`), gdy heurystyka się myli
        handle_at_lo = handle == "lo"
    print("ATTACH spread lo/hi", round(s_lo, 4), round(s_hi, 4))
    d = ax if handle_at_lo else -ax                    # kierunek uchwyt → czubek ostrza
    handle_pt = c + ax * (lo if handle_at_lo else hi)
    k = length / span
    target = Vector(forward).normalized()
    rot = Vector(d).rotation_difference(target).to_matrix()
    # obrót wokół osi długości: szeroka płaszczyzna ostrza (najmniejsza oś główna = grubość) ma być zwrócona do kamery gry (±Y), nie krawędzią
    thick = rot @ Vector(vt[2])
    tp = thick - target * thick.dot(target)
    want = Vector((0.0, 1.0, 0.0))
    want = want - target * want.dot(target)
    if tp.length > 1e-6 and want.length > 1e-6:
        if tp.angle(-want) < tp.angle(want):
            want = -want
        rot = tp.rotation_difference(want).to_matrix() @ rot
    # granica uchwyt → ostrze z profilu szerokości (mediana odległości od osi w 40 przedziałach licząc od głowicy): pierwszy przedział
    # wyraźnie szerszy od samego uchwytu. W tym punkcie ostrze wychodzi spod pięści, a cały uchwyt chowa się w dłoni i przedramieniu.
    t = (pts - handle_pt) @ d / span
    q = pts - c
    q = q - np.outer(q @ ax, ax)
    dist = np.linalg.norm(q, axis=1)
    bins = [np.median(dist[(t >= i / 40) & (t < (i + 1) / 40)]) if ((t >= i / 40) & (t < (i + 1) / 40)).any() else 0.0 for i in range(40)]
    handle_w = float(np.median([b for b in bins[1:6] if b > 0])) if any(b > 0 for b in bins[1:6]) else 0.0
    junction = next((i / 40 for i in range(4, 40) if bins[i] > 2.0 * handle_w), 0.3)
    print("ATTACH junction", round(junction, 3), "handle_w", round(handle_w, 4))
    grip = Vector(handle_pt) + Vector(d) * junction * span
    wrist = L[bone]
    fist = wrist + Vector((0.02 * H, 0.0, -0.07 * H))        # dół pięści: tu ostrze wychodzi z dłoni
    for v in prop.data.vertices:
        p = rot @ ((Vector(v.co) - grip) * k)
        v.co = p + fist
    prop.data.update()
    vg = prop.vertex_groups.new(name="mixamorig:" + bone)
    vg.add(list(range(len(prop.data.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    prop.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    print("ATTACH", path, "length", round(span * k, 2), "handle_at_lo", handle_at_lo)


def render_pose(arm, body, prefix, name, H):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 900, 900
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.55, 0.57, 0.6)
    cam = sc.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = H * 1.25
    d = Vector((1.0, -1.0, 0.1)).normalized()      # widok z przodu-boku
    cam.location = Vector((0, 0, H * 0.5)) + d * H * 3
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s_%s.png" % (prefix, name)
    bpy.ops.render.render(write_still=True)


def main():
    src, dst = sys.argv[sys.argv.index("--") + 1], sys.argv[sys.argv.index("--") + 2]
    face = arg("--face", "-y")
    height = float(arg("--height", 1.8))
    P = PRESETS[arg("--preset", "humanoid")]
    prefix = arg("--preview")
    body, pts = load_and_normalize(src, face, height)
    H = float(pts[:, 2].max())
    L = landmarks(pts, H, P)
    for k in ("LeftHand", "LeftArm", "LeftUpLeg", "LeftFoot", "RightHand"):
        print("LM", k, tuple(round(c, 3) for c in L[k]))
    arm = build_armature(L, H)
    skin(body, arm, H)
    attach = arg("--attach")
    if attach:
        attach_prop(body, arm, L, H, attach, arg("--attach-bone", "RightHand"), float(arg("--attach-length", 0.8)), (0.12, 0.0, -1.0),
                    arg("--attach-handle", "auto"))
        body = bpy.context.view_layer.objects.active
    if prefix:
        render_pose(arm, body, prefix, "rest", H)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="POSE")
        pb = arm.pose.bones
        pb["mixamorig:LeftUpLeg"].rotation_mode = "XYZ"
        pb["mixamorig:LeftUpLeg"].rotation_euler = (0, math.radians(-35), 0)
        pb["mixamorig:RightArm"].rotation_mode = "XYZ"
        pb["mixamorig:RightArm"].rotation_euler = (math.radians(80), 0, 0)
        pb["mixamorig:Spine1"].rotation_mode = "XYZ"
        pb["mixamorig:Spine1"].rotation_euler = (0, math.radians(20), 0)
        bpy.context.view_layer.update()
        render_pose(arm, body, prefix, "pose", H)
        bpy.ops.object.mode_set(mode="OBJECT")
        for b in pb:
            b.rotation_euler = (0, 0, 0)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90, export_animations=False, export_apply=False)
    print("OK", dst)


main()
