"""Ręce do widoku z oczu (strzelnica FPP, RANGE_FPS_PLAN.md) — `art/char3d/fp/fp_arms_<strój>.glb`.

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2, jak `char_mpfb.py`; najpierw rękawy z `cloth_garments.py --fp`):
    blender -b -P prototype/tools/cloth_garments.py -- male_scav --only=m65 --fp
    blender -b -P prototype/tools/fp_arms.py -- male_scav [--tex=2048] [--samples=64]      # + build/fp/fp_arms_scav.blend dla fp_grip.py

Ciało z tabeli OUTFITS w `char_mpfb.py` (ten sam fenotyp, szkielet „mixamo” z palcami), ale bez upraszczania — z bliska widać każdy
staw palca. Z ciała powstają:
- rękawice taktyczne (jak w viewmodelach CS): ściany dłoni i palców (wagi kości dłoni) i mankiet do 7,5 cm nad nadgarstkiem,
  odsunięte od skóry, zaokrąglone podziałem i pogrubione; panele z pozy spoczynkowej (grzbiet z cordury, wnętrze z zamszu, mankiet
  z neoprenu, szwy na granicach) — materiał proceduralny wypiekany w Cycles do tekstur; twarde nakładki z gumy (zaokrąglone
  klocki) nad kostkami i na pierwszych członach palców, przypięte do kości dłoni i palców;
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
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

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
# rękawice taktyczne (jak w viewmodelach CS): grzbiet z cordury, wnętrze z syntetycznego zamszu, mankiet z neoprenu, twarde nakładki
GLOVE_FABRIC = (0.030, 0.032, 0.027)    # cordura grzbietu (grafit z zielenią)
GLOVE_PALM = (0.052, 0.047, 0.039)      # zamsz wnętrza dłoni i opuszek
GLOVE_NEOPRENE = (0.026, 0.026, 0.026)  # mankiet
GLOVE_STITCH = (0.020, 0.020, 0.018)    # szwy na granicy paneli
PAD_RUBBER = (0.020, 0.020, 0.021)      # nakładki na kostkach i palcach (guma / TPU)
KNUCKLE_PAD = (0.016, 0.019, 0.0045)    # m — nakładka nad stawem śródręczno-paliczkowym: długość (wzdłuż dłoni), szerokość, grubość
FINGER_PAD = (0.017, 0.0135, 0.003)     # m — poduszka na pierwszym członie palca: długość, szerokość, grubość
PAD_GAP = 0.0008                        # m — nakładka nad tkaniną


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


def _hand_rest(rig):
    """Układ każdej dłoni w pozie spoczynkowej: nadgarstek, f (ku palcom), a (linia kostek, mały → wskazujący), b (grzbiet), oś
    przedramienia (ku dłoni), linia stawów śródręczno-paliczkowych i pierwsze człony palców (nasada → staw międzypaliczkowy)."""
    out = {}
    for side in ("Left", "Right"):
        w, m = _bone_head(rig, side + "Hand"), _bone_head(rig, side + "HandMiddle1")
        f = (m - w).normalized()
        a = _bone_head(rig, side + "HandIndex1") - _bone_head(rig, side + "HandPinky1")
        a = (a - f * a.dot(f)).normalized()
        b = (f.cross(a) if side == "Right" else a.cross(f)).normalized()
        fa = (w - _bone_head(rig, side + "ForeArm")).normalized()
        segs = [(_bone_head(rig, side + "Hand%s1" % fg), _bone_head(rig, side + "Hand%s2" % fg)) for fg in ("Index", "Middle", "Ring", "Pinky")]
        out[side] = {"w": w, "f": f, "a": a, "b": b, "fa": fa, "mcp": (segs[0][0], segs[3][0]), "segs": segs}
    return out


def _seg_dist(p, p0, p1):
    """Odległość punktu od odcinka i parametr rzutu 0..1."""
    d = p1 - p0
    t = max(0.0, min(1.0, (p - p0).dot(d) / d.length_squared))
    return (p - (p0 + d * t)).length, t


def _vert_side(w):
    """Strona ręki wierzchołka z wag kości (MPFB: grupy „mixamorig:Left…” / „…Right…”)."""
    l = sum(x for n, x in w.items() if n.startswith(PRE + "Left"))
    r = sum(x for n, x in w.items() if n.startswith(PRE + "Right"))
    return "Left" if l >= r else "Right"


def glove_zones(g, rig):
    """Atrybut „zone” rękawicy (R — grzbiet 0..1, B — mankiet 0..1) z pozy spoczynkowej: grzbiet po normalnej względem grzbietu dłoni
    (dla kciuka grzbiet obrócony ku stronie promieniowej — paznokieć kciuka patrzy w bok), mankiet powyżej nadgarstka."""
    H = _hand_rest(rig)
    W = _weights(g)
    mw = g.matrix_world
    nm = mw.to_3x3()
    col = g.data.color_attributes.new("zone", "FLOAT_COLOR", "POINT")
    vals = []
    for v, w in zip(g.data.vertices, W):
        h = H[_vert_side(w)]
        p, n = mw @ v.co, (nm @ v.normal).normalized()
        thumb = sum(x for k, x in w.items() if "Thumb" in k) > 0.4
        bd = (h["b"] + h["a"] * 0.9).normalized() if thumb else h["b"]
        d = n.dot(bd)
        back = min(max((d + 0.15) / 0.3, 0.0), 1.0)
        su = (p - h["w"]).dot(h["fa"])                                # < 0 — w stronę łokcia
        cuff = min(max((-su - 0.012) / 0.008, 0.0), 1.0)
        vals += [back, 0.0, cuff, 1.0]
    col.data.foreach_set("color", vals)


def tactical_material(name):
    """Rękawica taktyczna: grzbiet z cordury (splot), wnętrze z zamszu (drobny meszek), mankiet z neoprenu w prążki, szwy na granicy
    grzbietu i wnętrza, drobne plamy. Panele z atrybutu „zone” (glove_zones). Bez jaśniejszych przetarć na wypukłościach — na ciemnej
    cordurze wyglądały jak dziury na kostkach."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    L = nt.links.new
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    L(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    zone = nt.nodes.new("ShaderNodeAttribute")
    zone.attribute_name = "zone"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    L(zone.outputs["Color"], sep.inputs["Color"])
    back, cuff = sep.outputs["Red"], sep.outputs["Blue"]

    def math_node(op, a, b=None, clamp=False):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    def wave(scale, axis):
        n = nt.nodes.new("ShaderNodeTexWave")
        n.wave_type = "BANDS"
        n.bands_direction = axis
        n.inputs["Scale"].default_value = scale
        n.inputs["Distortion"].default_value = 0.6
        L(tc.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    def noise(scale, detail=3.0):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        L(tc.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    def mix(fac, a, b):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        L(fac, n.inputs["Factor"])
        for sock, x in ((n.inputs["A"], a), (n.inputs["B"], b)):
            if isinstance(x, (int, float)):
                sock.default_value = x
            else:
                L(x, sock)
        return n.outputs["Result"]

    def mixc(fac, a, b, blend="MIX"):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        L(fac, n.inputs["Factor"])
        for sock, x in ((n.inputs["A"], a), (n.inputs["B"], b)):
            if isinstance(x, tuple):
                sock.default_value = x + (1.0,)
            else:
                L(x, sock)
        return n.outputs["Result"]

    weave = math_node("MULTIPLY", wave(520.0, "X"), wave(520.0, "Y"))      # splot cordury (ok. 2 mm)
    suede = noise(900.0, 4.0)                                             # meszek zamszu
    ribs = wave(140.0, "Z")                                               # prążki neoprenu
    seam = math_node("SUBTRACT", 1.0, math_node("MULTIPLY", math_node("ABSOLUTE", math_node("SUBTRACT", back, 0.5)), 9.0), True)
    h = mix(back, math_node("MULTIPLY", suede, 0.6), weave)
    h = mix(cuff, h, ribs)
    h = math_node("SUBTRACT", h, math_node("MULTIPLY", seam, 1.2))       # rowek szwu
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.0004
    L(h, bump.inputs["Height"])
    L(bump.outputs["Normal"], bsdf.inputs["Normal"])
    c = mixc(back, GLOVE_PALM, GLOVE_FABRIC)
    c = mixc(cuff, c, GLOVE_NEOPRENE)
    c = mixc(math_node("MULTIPLY", seam, 0.8), c, GLOVE_STITCH)
    tint = nt.nodes.new("ShaderNodeMix")                                  # drobne plamy (kurz, olej)
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 0.25
    L(c, tint.inputs["A"])
    mot = nt.nodes.new("ShaderNodeTexNoise")
    mot.inputs["Scale"].default_value = 35.0
    L(tc.outputs["Object"], mot.inputs["Vector"])
    L(mot.outputs["Color"], tint.inputs["B"])
    L(tint.outputs["Result"], bsdf.inputs["Base Color"])
    r = mix(back, 0.74, 0.9)
    r = mix(cuff, r, 0.82)
    L(r, bsdf.inputs["Roughness"])
    return m


def pad_material(name):
    """Guma / TPU nakładek: ciemna, półmatowa, drobne ziarno formy."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = PAD_RUBBER + (1.0,)
    bsdf.inputs["Roughness"].default_value = 0.58
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 700.0
    nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    bump.inputs["Distance"].default_value = 0.0002
    nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def _rounded_box(name, center, axes, size, bevel=None):
    """Nakładka formowana: klocek `size` (długość, szerokość, grubość) mocno zaokrąglony w rzucie (krawędzie pionowe — prawie owal)
    i łagodnie na obwodzie górnej i dolnej ściany; osie `axes` (3 wektory: długość, szerokość, grubość), środek `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    vert = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().z) > 0.9]
    bmesh.ops.bevel(bm, geom=vert, offset=min(size[0], size[1]) * 0.42, segments=6, affect="EDGES", profile=0.5)
    rim = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6 and abs(abs(e.verts[0].co.z) - size[2] * 0.5) < 1e-6]
    bmesh.ops.bevel(bm, geom=rim, offset=size[2] * 0.42, segments=3, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = Matrix((axes[0], axes[1], axes[2])).transposed().to_4x4()
    m.translation = center
    me.transform(m)
    for poly in me.polygons:
        poly.use_smooth = True
    return ob


def make_pads(rig, gloves):
    """Twarde nakładki rękawic taktycznych (guma / TPU): zaokrąglone klocki nad stawami śródręczno-paliczkowymi (przypięte do kości
    dłoni) i poduszki na pierwszych członach palców (przypięte do członu) — bez kciuka. Każda leży tuż nad grzbietem rękawicy (promień
    z punktu stawu wzdłuż grzbietu do powierzchni rękawicy w pozie spoczynkowej). Wcięcie z siatki rękawicy dawało postrzępione brzegi."""
    H = _hand_rest(rig)
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(gloves, dg)
    inv = gloves.matrix_world.inverted()

    def surface(p, d):
        hit = bvh.ray_cast(inv @ p, (inv.to_3x3() @ d).normalized(), 0.06)
        return gloves.matrix_world @ hit[0] if hit[0] is not None else p + d * 0.012

    parts = []
    for side, h in H.items():
        for (p0, p1), fg in zip(h["segs"], ("Index", "Middle", "Ring", "Pinky")):
            d = (p1 - p0).normalized()
            bf = (h["b"] - d * h["b"].dot(d)).normalized()
            for name, at, size, ax_f, bone in (
                    ("knuckle", p0, KNUCKLE_PAD, (h["f"] - h["b"] * h["f"].dot(h["b"])).normalized(), side + "Hand"),
                    ("finger", p0.lerp(p1, 0.55), FINGER_PAD, d, side + "Hand%s1" % fg)):
                up = h["b"] if name == "knuckle" else bf
                sd = up.cross(ax_f).normalized()
                c = surface(at, up) + up * (PAD_GAP + size[2] * 0.5)
                ob = _rounded_box("pad_%s_%s_%s" % (side, fg, name), c, (ax_f, sd, up), size)
                vg = ob.vertex_groups.new(name=PRE + bone)
                vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
                parts.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    pads = bpy.context.active_object
    pads.name = "glove_pads"
    pads.parent = rig
    pads.matrix_parent_inverse = rig.matrix_world.inverted()
    am = pads.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    print("PADS", len(pads.data.polygons), "faces")
    return pads


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

    def mat(name, rgb, rough, metal=0.0, emit=None, emit_strength=0.6):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = rgb + (1.0,)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if emit:
            b.inputs["Emission Color"].default_value = emit + (1.0,)
            b.inputs["Emission Strength"].default_value = emit_strength
        return m
    strap.data.materials.append(mat("watch_strap", (0.10, 0.11, 0.07), 0.9))
    case.data.materials.append(mat("watch_case", (0.55, 0.55, 0.52), 0.35, 1.0))
    glass.data.materials.append(mat("watch_face", (0.02, 0.025, 0.02), 0.08, 0.0, (0.25, 0.55, 0.3), 0.05))   # ciemna tarcza, ślad fosforu
    # (przy 0,6 cała tarcza świeciła jak zielony krążek tuż przy kamerze)
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
    glove_zones(gloves, rig)
    pads = make_pads(rig, gloves)
    C._cycles(SAMPLES)
    gloves.data.materials.clear()
    gloves.data.materials.append(tactical_material("glove_tactical"))
    bake_object(gloves, TEX, "glove")
    pads.data.materials.clear()
    pads.data.materials.append(pad_material("glove_pad_rubber"))
    bake_object(pads, 1024, "glovepad")
    watch = make_watch(rig, gloves)
    bpy.data.objects.remove(body)
    for o in [o for o in rig.children if o.type == "MESH" and o.name not in ("gloves", "glove_pads", "sleeves", "watch")]:
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
