"""Ręce do widoku z oczu (strzelnica FPP, RANGE_FPS_PLAN.md) — `art/char3d/fp/fp_arms_<strój>.glb`.

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2, jak `char_mpfb.py`; najpierw rękawy z `cloth_garments.py --fp`):
    blender -b -P prototype/tools/cloth_garments.py -- male_scav --only=m65 --fp
    blender -b -P prototype/tools/fp_arms.py -- male_scav [--tex=2048] [--samples=64]      # + build/fp/fp_arms_scav.blend dla fp_grip.py

Ciało z tabeli OUTFITS w `char_mpfb.py` (ten sam fenotyp, szkielet „mixamo” z palcami), ale bez upraszczania — z bliska widać każdy
staw palca. Z ciała powstają:
- rękawice: ściany dłoni i palców (wagi kości dłoni) i mankiet do 7,5 cm nad nadgarstkiem, odsunięte od skóry o grubość skóry
  rękawicy (mankiet rozszerza się jak w rękawicy z mankietem), zaokrąglone podziałem i pogrubione; materiał proceduralny (ziarno
  skóry, zmarszczki, przetarcia na wypukłościach, szew wzdłuż palców) wypiekany w Cycles do tekstur;
- rękawy kurtki M65 z symulacji tkaniny (`art_src/clothes/<strój>_m65_fp.glb`), wagi kości z ciała;
- zegarek na lewym nadgarstku (koperta, szkło, pasek), przypięty do przedramienia.
Samo ciało nie trafia do pliku (rękawice i rękawy zakrywają je w całości). Orientacja jak `char_mpfb.py`: przód +X, góra +Z, stopy
na z = 0, wzrost wg tabeli — szkielet zgodny z modelem postaci w grze.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
_argv = sys.argv
sys.argv = [_argv[0], "--"]          # char_mpfb przy imporcie nic nie buduje
import char_mpfb as C  # noqa: E402
sys.argv = _argv
from bl_ext.user_default.mpfb.services import HumanService  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


OUT = os.path.join(os.path.dirname(HERE), "art", "char3d", "fp")
CLOTH_SRC = os.path.join(REPO, "art_src", "clothes")
TEX = int(arg("tex", "2048"))
SAMPLES = int(arg("samples", "64"))
WORK = arg("work", os.path.join(REPO, "build", "fp"))
PRE = "mixamorig:"

GLOVE_GAP = 0.0016           # m — skóra rękawicy nad skórą dłoni
GLOVE_CUFF = 0.075           # m — mankiet nad nadgarstkiem
GLOVE_FLARE = 0.0065         # m — rozszerzenie mankietu na końcu
GLOVE_THICK = 0.0012         # m — grubość skóry (widoczna na krawędzi mankietu)
SLEEVE_THICK = 0.0018        # m — grubość tkaniny rękawa
LEATHER = (0.10, 0.068, 0.046)      # skóra rękawicy (brąz wojskowy, ciemny)
LEATHER_WORN = (0.20, 0.14, 0.095)  # przetarcia na kłykciach i opuszkach


def _bone_head(rig, n):
    return rig.matrix_world @ rig.data.bones[PRE + n].head_local


def make_body(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    ph = info["phenotype"]
    ph.update(spec["phenotype"])
    ph["gender"] = 1.0 if spec["sex"] == "male" else 0.0
    ph["race"] = dict(spec["race"])
    info["rig"] = "mixamo"
    info["eyes"] = ""
    info["eyebrows"] = ""
    info["hair"] = ""
    info["clothes"] = []
    info["skin_mhmat"] = "%s/%s.mhmat" % (spec["skin"], spec["skin"])
    info["skin_material_type"] = "MAKESKIN"
    info["alternative_materials"] = {}
    st = HumanService.get_default_deserialization_settings()
    st["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, st)
    rig = body.parent
    body.name = "body"
    C._only(body)
    if body.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    return rig, body


def _weights(ob):
    """Wagi wierzchołków: lista słowników nazwa grupy → waga."""
    names = {g.index: g.name for g in ob.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups} for v in ob.data.vertices]


def make_gloves(rig, body):
    """Rękawice z ciała: dla każdej ręki cała dłoń i przedramię do GLOVE_CUFF nad nadgarstkiem, odcięte jedną płaszczyzną prostopadłą do
    przedramienia (równy, okrągły mankiet; bez progów wag — wcześniej wybór ścian po wagach dziurawił grzbiet dłoni i rwał palce).
    Ściany ręki: każda, której choć jeden wierzchołek ma wagę kości tej ręki (ramię, przedramię, dłoń, palce) — bez nóg i tułowia.
    Potem odsunięcie od skóry (mankiet rozszerza się), podział i grubość skóry."""
    parts = []
    for side in ("Left", "Right"):
        g = body.copy()
        g.data = body.data.copy()
        g.name = "glove_" + side
        bpy.context.scene.collection.objects.link(g)
        for m in list(g.modifiers):
            if m.type != "ARMATURE":
                g.modifiers.remove(m)
        W = _weights(g)
        wr = _bone_head(rig, side + "Hand")
        el = _bone_head(rig, side + "ForeArm")
        d = (wr - el).normalized()                                  # od łokcia do nadgarstka
        arm = []
        for w in W:
            a_w = sum(x for n, x in w.items() if n.startswith(PRE + side) and ("Arm" in n or "Hand" in n))
            arm.append(w.get("body", 0.0) > 0.5 and a_w > 0.05)
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not any(arm[v.index] for v in f.verts)], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        cut = wr - d * GLOVE_CUFF
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=cut, plane_no=d, clear_inner=True)     # zostaje strona dłoni
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        # luźne kawałki (resztki tułowia za płaszczyzną) precz: zostaje największa spójna część
        seen = set()
        comps = []
        for f in bm.faces:
            if f.index in seen:
                continue
            stack = [f]
            comp = []
            seen.add(f.index)
            while stack:
                x = stack.pop()
                comp.append(x)
                for e in x.edges:
                    for y in e.link_faces:
                        if y.index not in seen:
                            seen.add(y.index)
                            stack.append(y)
            comps.append(comp)
        comps.sort(key=len, reverse=True)
        bmesh.ops.delete(bm, geom=[f for c in comps[1:] for f in c], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.normal_update()
        for v in bm.verts:
            s_up = (wr - v.co).dot(d)                               # > 0: od nadgarstka w stronę łokcia
            t = min(max((s_up - 0.03) / (GLOVE_CUFF - 0.03), 0.0), 1.0) if s_up > 0 else 0.0
            v.co += v.normal * (GLOVE_GAP + GLOVE_FLARE * t * t * (3 - 2 * t))
        bm.to_mesh(g.data)
        bm.free()
        parts.append(g)
    bpy.ops.object.select_all(action="DESELECT")
    for g in parts:
        g.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "gloves"
    C._only(g)
    ss = g.modifiers.new("ss", "SUBSURF")
    ss.levels = 1
    ss.render_levels = 1
    while g.modifiers[0] != ss:
        bpy.ops.object.modifier_move_up(modifier=ss.name)
    bpy.ops.object.modifier_apply(modifier=ss.name)
    so = g.modifiers.new("so", "SOLIDIFY")
    so.thickness = GLOVE_THICK
    so.offset = -1.0
    so.use_rim = True
    while g.modifiers[0] != so:
        bpy.ops.object.modifier_move_up(modifier=so.name)
    bpy.ops.object.modifier_apply(modifier=so.name)
    for p in g.data.polygons:
        p.use_smooth = True
    print("GLOVES", len(g.data.polygons), "faces")
    return g


def leather_material(name):
    """Skóra rękawicy: ziarno, zmarszczki, przetarcia na wypukłościach (Pointiness w Cycles), połysk zależny od zużycia."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 380.0                # ziarno ok. 1–2 mm — przy teksturze 2K na dwie rękawice jeszcze czytelne z oka
    grain.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], grain.inputs["Vector"])
    crease = nt.nodes.new("ShaderNodeTexVoronoi")
    crease.feature = "DISTANCE_TO_EDGE"
    crease.inputs["Scale"].default_value = 55.0                 # zmarszczki skóry (stawy, grzbiet dłoni)
    nt.links.new(tc.outputs["Object"], crease.inputs["Vector"])
    mottle = nt.nodes.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 45.0
    mottle.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], mottle.inputs["Vector"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    wear = nt.nodes.new("ShaderNodeMapRange")                 # wypukłe (kłykcie, opuszki, krawędź mankietu) → przetarte
    wear.inputs["From Min"].default_value = 0.52
    wear.inputs["From Max"].default_value = 0.62
    nt.links.new(geo.outputs["Pointiness"], wear.inputs["Value"])
    wmix = nt.nodes.new("ShaderNodeMath")
    wmix.operation = "MULTIPLY"
    nt.links.new(wear.outputs["Result"], wmix.inputs[0])
    nt.links.new(mottle.outputs["Fac"], wmix.inputs[1])
    col = nt.nodes.new("ShaderNodeMix")
    col.data_type = "RGBA"
    col.inputs["A"].default_value = LEATHER + (1.0,)
    col.inputs["B"].default_value = LEATHER_WORN + (1.0,)
    nt.links.new(wmix.outputs["Value"], col.inputs["Factor"])
    tint = nt.nodes.new("ShaderNodeMix")                      # drobne plamy (pot, olej)
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 0.35
    nt.links.new(col.outputs["Result"], tint.inputs["A"])
    nt.links.new(mottle.outputs["Color"], tint.inputs["B"])
    nt.links.new(tint.outputs["Result"], bsdf.inputs["Base Color"])
    rough = nt.nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.70
    rough.inputs["To Max"].default_value = 0.40
    nt.links.new(wmix.outputs["Value"], rough.inputs["Value"])
    nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    b1 = nt.nodes.new("ShaderNodeBump")
    b1.inputs["Strength"].default_value = 1.0
    b1.inputs["Distance"].default_value = 0.0012
    nt.links.new(grain.outputs["Fac"], b1.inputs["Height"])
    b2 = nt.nodes.new("ShaderNodeBump")
    b2.inputs["Strength"].default_value = 1.0
    b2.inputs["Distance"].default_value = 0.003
    b2.invert = True
    nt.links.new(crease.outputs["Distance"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def bake_object(ob, size, prefix):
    """Wypiek materiału proceduralnego do tekstur (kolor, szorstkość, normalne, okluzja) i materiał z obrazów."""
    C._only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    imgs = {}
    for key, kind, nonc in (("albedo", "DIFFUSE", False), ("rough", "ROUGHNESS", True), ("normal", "NORMAL", True), ("ao", "AO", True)):
        img = bpy.data.images.new("%s_%s" % (prefix, key), size, size, alpha=False)
        if nonc:
            img.colorspace_settings.name = "Non-Color"
        C._bake_target(ob, img)
        kw = {"type": kind}
        if kind == "DIFFUSE":
            kw["pass_filter"] = {"COLOR"}
        C._bake(**kw)
        imgs[key] = img
    C._drop_target(ob)
    # okluzja wmnożona w kolor (głębokie zgięcia palców, wnętrze mankietu)
    a = np.array(imgs["albedo"].pixels[:]).reshape(-1, 4)
    o = np.array(imgs["ao"].pixels[:]).reshape(-1, 4)
    a[:, :3] *= 0.7 + 0.3 * o[:, :3]                               # łagodnie: mocna okluzja dawała ciemne plamy na grzbiecie dłoni
    imgs["albedo"].pixels.foreach_set(a.astype(np.float32).ravel())
    m = bpy.data.materials.new(prefix)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = imgs["albedo"]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    r = nt.nodes.new("ShaderNodeTexImage")
    r.image = imgs["rough"]
    nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = imgs["normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.0
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for img in imgs.values():
        img.pack()
    bpy.data.images.remove(imgs["ao"])


def make_watch(rig, gloves):
    """Zegarek na lewym nadgarstku, na mankiecie rękawicy (koperta 38 mm, szkło, pasek parciany), sztywno na przedramieniu."""
    wr = _bone_head(rig, "LeftHand")
    el = _bone_head(rig, "LeftForeArm")
    d = (wr - el).normalized()
    c = wr - d * 0.045                                       # 4,5 cm nad nadgarstkiem
    # promień nadgarstka z rękawicy (najdalszy punkt przekroju)
    rs = [((v.co - c) - d * (v.co - c).dot(d)).length for v in gloves.data.vertices if abs((v.co - c).dot(d)) < 0.006 and (v.co - c).length < 0.08]
    r = (max(rs) if rs else 0.03) + 0.0015
    up = Vector((0, 0, 1))
    back = (up - d * up.dot(d)).normalized()                 # grzbiet przedramienia w A-pozie (z góry)
    side = d.cross(back)
    bm = bmesh.new()
    n = 40
    w = 0.02
    ring = []
    for i in range(n):                                       # pasek: pierścień eliptyczny (nadgarstek jest płaski)
        a = 2 * math.pi * i / n
        p = c + (back * math.cos(a) * r * 0.92 + side * math.sin(a) * r * 1.12)
        ring.append((bm.verts.new(p - d * w / 2), bm.verts.new(p + d * w / 2)))
    for i in range(n):
        a0, b0 = ring[i]
        a1, b1 = ring[(i + 1) % n]
        bm.faces.new((a0, a1, b1, b0))
    strap = bpy.data.objects.new("watch_strap", bpy.data.meshes.new("watch_strap"))
    bm.to_mesh(strap.data)
    bm.free()
    bpy.context.scene.collection.objects.link(strap)
    so = strap.modifiers.new("so", "SOLIDIFY")
    so.thickness = 0.0022
    C._only(strap)
    bpy.ops.object.modifier_apply(modifier=so.name)
    # koperta i szkło na grzbiecie
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.019, depth=0.009, location=c + back * (r * 0.92 + 0.004))
    case = bpy.context.active_object
    case.name = "watch_case"
    case.rotation_mode = "QUATERNION"
    case.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(back)
    bv = case.modifiers.new("bv", "BEVEL")
    bv.width = 0.0015
    bv.segments = 3
    bpy.ops.object.modifier_apply(modifier=bv.name)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.0155, depth=0.002, location=c + back * (r * 0.92 + 0.0088))
    glass = bpy.context.active_object
    glass.name = "watch_glass"
    glass.rotation_mode = "QUATERNION"
    glass.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(back)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    def mat(name, rgb, rough, metal=0.0, emit=None):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = rgb + (1.0,)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if emit:
            b.inputs["Emission Color"].default_value = emit + (1.0,)
            b.inputs["Emission Strength"].default_value = 0.6
        return m
    strap.data.materials.append(mat("watch_strap", (0.10, 0.11, 0.07), 0.9))
    case.data.materials.append(mat("watch_case", (0.55, 0.55, 0.52), 0.35, 1.0))
    glass.data.materials.append(mat("watch_face", (0.02, 0.025, 0.02), 0.08, 0.0, (0.25, 0.55, 0.3)))   # tarcza z fosforem pod szkłem
    bpy.ops.object.select_all(action="DESELECT")
    for o in (strap, case, glass):
        o.select_set(True)
    bpy.context.view_layer.objects.active = case
    bpy.ops.object.join()
    watch = bpy.context.active_object
    watch.name = "watch"
    watch.parent = rig
    watch.matrix_parent_inverse = rig.matrix_world.inverted()
    vg = watch.vertex_groups.new(name=PRE + "LeftForeArm")
    vg.add(list(range(len(watch.data.vertices))), 1.0, "REPLACE")
    am = watch.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    for p in watch.data.polygons:
        p.use_smooth = True
    print("WATCH r=%.3f" % r)
    return watch


def build(outfit):
    spec = C.OUTFITS[outfit]
    rig, body = make_body(spec)
    gi = body.vertex_groups["body"].index
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    k = spec["height"] / (max(zs) - min(zs))
    floor = min(zs)
    sleeves = C.add_sewn(rig, body, spec, {"sleeves": {"file": "%s_m65_fp.glb" % outfit}})
    sl = bpy.data.objects.get("sleeves")
    if sl is not None:                                         # grubość tkaniny: z oka widać krawędź mankietu (bez niej — prześwit i „szarpana” krawędź)
        C._only(sl)
        so = sl.modifiers.new("so", "SOLIDIFY")
        so.thickness = SLEEVE_THICK
        so.offset = -1.0
        so.use_rim = True
        while sl.modifiers[0] != so:
            bpy.ops.object.modifier_move_up(modifier=so.name)
        bpy.ops.object.modifier_apply(modifier=so.name)
    gloves = make_gloves(rig, body)
    gloves.parent = rig
    C._cycles(SAMPLES)
    gloves.data.materials.clear()
    gloves.data.materials.append(leather_material("glove_leather"))
    bake_object(gloves, TEX, "glove")
    watch = make_watch(rig, gloves)
    bpy.data.objects.remove(body)
    for o in [o for o in rig.children if o.type == "MESH" and o.name not in ("gloves", "sleeves", "watch")]:
        bpy.data.objects.remove(o)
    # orientacja i skala jak char_mpfb.build (przód +X, wzrost, stopy na z = 0)
    rig.location.z -= floor
    rig.rotation_euler = (0.0, 0.0, math.radians(90.0))
    rig.scale = (k, k, k)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig] + list(rig.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    per = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in rig.children if o.type == "MESH"}
    print("TRIS", sum(per.values()), per, "BONES", len(rig.data.bones))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, "fp_arms_%s.glb" % outfit.split("_", 1)[1])
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="WEBP", export_image_quality=90,
                              export_animations=False, export_apply=False, export_morph=False)
    print("OK", dst)
    os.makedirs(WORK, exist_ok=True)                           # źródło dla fp_grip.py (chwyty i animacje broni)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "fp_arms_%s.blend" % outfit.split("_", 1)[1]))


for n in [a for a in argv if not a.startswith("--")]:
    build(n)
