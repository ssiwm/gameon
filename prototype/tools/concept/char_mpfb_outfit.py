"""Stylizacja postaci MakeHuman (MPFB2) i pierwszy strój w klimacie gry: „Scavenger '87” (obie płcie).

Co robi:
  1. Buduje ciało z MPFB (płeć, suwaki), dokłada oczy, brwi, rzęsy, zęby i fryzurę.
  2. Stylizuje proporcje jedną funkcją pozycji `warp()` stosowaną do WSZYSTKICH siatek naraz (ciało, oczy, włosy…), więc części
     zostają do siebie dopasowane: krótsze nogi, większa głowa, grubszy tułów i kończyny, dłuższe stopy.
  3. Dodaje rig `game_engine` (waga ciała zostaje aktualna).
  4. Ubrania powstają Z CIAŁA: kopia siatki ograniczona do regionu (dominująca kość w wagach), przesunięta wzdłuż normalnych i pogrubiona —
     dziedziczy wagi ciała, więc rusza się razem z rigiem. Dodatki sztywne (plecak, kieszenie, czapka, respirator, latarka, radio) są
     skinowane do jednej kości. Materiały proceduralne (płótno, skóra, guma, brud od dołu).
  5. Renderuje poza „A” i swobodną poze (EEVEE, przezroczyste tło z cieniem) oraz eksportuje GLB.

Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/char_mpfb_outfit.py -- OUT_DIR           # arkusz poglądowy
             blender -b --factory-startup -P prototype/tools/concept/char_mpfb_outfit.py -- OUT_DIR --bake    # klatki animacji do gry (pack_chars3d.py składa arkusze)
Wymaga wtyczki MPFB i pakietów zasobów (patrz char_mpfb_test.py). Wynik: OUT_DIR/{male,female}_{A,relaxed,front,three}.png + .glb.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/mpfb_outfit"
os.makedirs(OUT, exist_ok=True)

bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService          # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService    # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService        # noqa: E402

DATA = LocationService.get_user_data()

# ---------------------------------------------------------------- parametry stylizacji (ułamki wzrostu H)

LEG_K = 0.88          # nogi krótsze
HEAD_S = 1.36         # głowa większa
BODY_W = 1.10         # szerokość tułowia/kończyn (x)
BODY_D = 1.14         # głębokość (y)
FOOT_L = 1.18         # długość stopy


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


class Warp:
    """Stylizacja proporcji jako funkcja pozycji (taka sama dla wszystkich części postaci)."""

    def __init__(self, height, yc):
        self.H = height
        self.zh = 0.50 * height          # biodra: nad nimi nic nie skracamy
        self.zn = 0.835 * height         # podstawa szyi
        self.yc = yc                     # oś głębokości postaci (środek ciała)
        self.z2n = self.zh * LEG_K + (self.zn - self.zh)

    def __call__(self, p):
        x, y, z = p
        z2 = z * LEG_K if z < self.zh else self.zh * LEG_K + (z - self.zh)
        w = smooth(self.zn - 0.03 * self.H, self.zn + 0.05 * self.H, z)       # udział „głowy”
        s = 1.0 + (HEAD_S - 1.0) * w
        body = 1.0 - w
        x2 = x * (1.0 + (BODY_W - 1.0) * body)
        y2 = self.yc + (y - self.yc) * (1.0 + (BODY_D - 1.0) * body)
        if z < 0.06 * self.H and y < self.yc:                                  # stopy: dłuższe do przodu (−Y)
            f = smooth(0.0, 0.06 * self.H, 0.06 * self.H - z)
            y2 = self.yc + (y2 - self.yc) * (1.0 + (FOOT_L - 1.0) * f)
        return Vector((x2 * s, self.yc + (y2 - self.yc) * s, self.z2n + (z2 - self.z2n) * s))


def warp_object(o, fn):
    mw, mi = o.matrix_world, o.matrix_world.inverted()
    for v in o.data.vertices:
        v.co = mi @ fn(mw @ v.co)
    o.data.update()


# ---------------------------------------------------------------- materiały

_mat_cache = {}


def mat(name, color, rough=0.8, metal=0.0, grain=0.0, scale=70.0, dirt=0.0, coord="UV", tint2=None, bump=0.35):
    """Proceduralny materiał: kolor + niska częstotliwość (wyblaknięcie) + ziarno (bump) + brud rosnący ku dołowi."""
    key = (name, tuple(color), rough, metal, grain, scale, dirt, coord, tint2, bump)
    if key in _mat_cache:
        return _mat_cache[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    tc = N.new("ShaderNodeTexCoord")
    src = tc.outputs["UV"] if coord == "UV" else tc.outputs["Object"]
    base = N.new("ShaderNodeRGB")
    base.outputs[0].default_value = (*color, 1)
    col = base.outputs[0]
    if tint2 is not None or dirt > 0:
        low = N.new("ShaderNodeTexNoise")
        low.inputs["Scale"].default_value = 5.0 if coord != "UV" else 6.0
        low.inputs["Detail"].default_value = 4.0
        L.new(src, low.inputs["Vector"])
        mix = N.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (*color, 1)
        mix.inputs["B"].default_value = (*(tint2 or tuple(c * 0.7 for c in color)), 1)
        L.new(low.outputs["Fac"], mix.inputs["Factor"])
        col = mix.outputs["Result"]
    if dirt > 0:
        sep = N.new("ShaderNodeSeparateXYZ")
        wp = N.new("ShaderNodeNewGeometry")
        L.new(wp.outputs["Position"], sep.inputs["Vector"])
        ramp = N.new("ShaderNodeMapRange")
        ramp.inputs["From Min"].default_value = 0.0
        ramp.inputs["From Max"].default_value = 0.9
        ramp.inputs["To Min"].default_value = dirt
        ramp.inputs["To Max"].default_value = 0.0
        L.new(sep.outputs["Z"], ramp.inputs["Value"])
        noise = N.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 18.0
        noise.inputs["Detail"].default_value = 6.0
        L.new(src, noise.inputs["Vector"])
        mul = N.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        L.new(ramp.outputs["Result"], mul.inputs[0])
        L.new(noise.outputs["Fac"], mul.inputs[1])
        mul2 = N.new("ShaderNodeMath")
        mul2.operation = "MULTIPLY"
        mul2.inputs[1].default_value = 2.2
        L.new(mul.outputs["Value"], mul2.inputs[0])
        dmix = N.new("ShaderNodeMix")
        dmix.data_type = "RGBA"
        dmix.inputs["B"].default_value = (0.05, 0.04, 0.035, 1)
        L.new(col, dmix.inputs["A"])
        L.new(mul2.outputs["Value"], dmix.inputs["Factor"])
        col = dmix.outputs["Result"]
    L.new(col, bsdf.inputs["Base Color"])
    if grain > 0:
        g = N.new("ShaderNodeTexNoise")
        g.inputs["Scale"].default_value = scale
        g.inputs["Detail"].default_value = 10.0
        g.inputs["Roughness"].default_value = 0.65
        L.new(src, g.inputs["Vector"])
        bm = N.new("ShaderNodeBump")
        bm.inputs["Strength"].default_value = bump
        bm.inputs["Distance"].default_value = grain
        L.new(g.outputs["Fac"], bm.inputs["Height"])
        L.new(bm.outputs["Normal"], bsdf.inputs["Normal"])
    _mat_cache[key] = m
    return m


# ---------------------------------------------------------------- budowa ciała

def asset(kind, name):
    base = os.path.join(DATA, kind, name)
    for root, _, files in os.walk(base):
        for f in files:
            if f.endswith(".mhmat" if kind == "skins" else ".mhclo"):
                return os.path.join(root, f)
    raise FileNotFoundError(base)


def build_body(gender, skin, hair, brows, height, weight, muscle, cup=0.5):
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=1.0 if gender == "male" else 0.0, height=height, weight=weight, muscle=muscle, age=0.5, cupsize=cup)
    macro["race"] = {"asian": 0.1, "caucasian": 0.8, "african": 0.1}
    b = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
    HumanService.set_character_skin(asset("skins", skin), b, skin_type="MAKESKIN")
    parts = []
    for atype, kind, name in (("Eyes", "eyes", "low-poly"), ("Eyebrows", "eyebrows", brows), ("Eyelashes", "eyelashes", "eyelashes01"),
                              ("Teeth", "teeth", "teeth_base"), ("Hair", "hair", hair)):
        parts.append(HumanService.add_mhclo_asset(asset(kind, name), b, asset_type=atype, material_type="MAKESKIN"))
    return b


def bake_shapekeys(b):
    with bpy.context.temp_override(object=b, active_object=b, selected_objects=[b]):
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)


BONE_SETS = {
    "jacket": {"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"},
    "pants": {"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"},
    "boots": {"foot_l", "foot_r", "ball_l", "ball_r"},
    "gloves": {"hand_l", "hand_r"} | {f"{f}_0{i}_{s}" for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3) for s in ("l", "r")},
    "scarf": {"neck_01"},
    "belt": {"spine_01", "pelvis"},
}


def region_shell(body, arm, name, bones, offset, material, thick=0.006, zmin=None, zmax=None, extra=None):
    """Kopia ciała ograniczona do regionu (dominująca kość ∈ bones i z ∈ [zmin, zmax]), odsunięta o `offset` wzdłuż normalnych."""
    o = body.copy()
    o.data = body.data.copy()
    o.name = name
    bpy.context.scene.collection.objects.link(o)
    for m in list(o.modifiers):
        if m.type == "MASK":
            o.modifiers.remove(m)
    names = {i: g.name for i, g in enumerate(o.vertex_groups)}
    bm = bmesh.new()
    bm.from_mesh(o.data)
    dl = bm.verts.layers.deform.active
    bodyi = [i for i, n in names.items() if n == "body"][0]
    bad = []
    offs = {}
    lay = bm.verts.layers.float.new("off")
    for v in bm.verts:
        w = v[dl]
        best, bw = None, 0.0
        for gi, wt in w.items():
            n = names[gi]
            if n in arm.data.bones and wt > bw:
                best, bw = n, wt
        ok = bodyi in w and best in bones
        if ok and zmin is not None and v.co.z < zmin:
            ok = False
        if ok and zmax is not None and v.co.z > zmax:
            ok = False
        if ok and extra is not None and not extra(v.co):
            ok = False
        if not ok:
            bad.append(v)
        elif isinstance(offset, dict):
            num = den = 0.0
            for gi, wt in w.items():
                n = names[gi]
                if n in offset:
                    num += wt * offset[n]
                    den += wt
            v[lay] = num / den if den > 0 else offset["_"]
    bmesh.ops.delete(bm, geom=bad, context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * (v[lay] if isinstance(offset, dict) else offset)
    bm.verts.layers.float.remove(lay)
    bm.to_mesh(o.data)
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = True
    o.data.materials.clear()
    o.data.materials.append(material)
    if thick > 0:
        s = o.modifiers.new("solid", "SOLIDIFY")
        s.thickness = thick
        s.offset = 1.0
    return o


def rigid(name, mesh_fn, bone, arm, material, loc=None):
    """Sztywny dodatek: geometria budowana w pozycji spoczynkowej, skinowana w 100% do jednej kości."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    mesh_fn(bm)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if loc is not None:
        o.location = loc
    me.materials.append(material)
    o.parent = arm
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    bpy.context.view_layer.update()
    # wierzchołki w układzie świata → odjąć location, bo obiekt ma loc (armature ma identyczność)
    return o


def box_fn(size, bevel=0.008, offset=(0, 0, 0), rot=None):
    def f(bm):
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=bm.verts)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
        if rot is not None:
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    return f


def cyl_fn(r, depth, axis="z", offset=(0, 0, 0), seg=18):
    def f(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth)
        if axis == "y":
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=bm.verts)
        elif axis == "x":
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    return f


def sph_fn(r, scale=(1, 1, 1), offset=(0, 0, 0), seg=20, cut_below=None):
    def f(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
        bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
        if cut_below is not None:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut_below], context="VERTS")
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    return f


def surf_y(body, z, half_x=0.035):
    """Najdalej wysunięta do przodu (−Y) i do tyłu (+Y) współrzędna ciała na wysokości z przy osi — do przyklejania dodatków."""
    ys = [v.co.y for v in body.data.vertices if abs(v.co.z - z) < 0.025 and abs(v.co.x) < half_x]
    return (min(ys), max(ys)) if ys else (0.0, 0.0)


def head_pos(arm, bone):
    b = arm.data.bones[bone]
    return arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local


def outfit_scavenger(body, arm, gender):
    """Pierwszy strój: kurtka polowa, spodnie bojówki, buty, rękawice, plecak z karimatą, pas, kolanówki, czapka, szalik, respirator, radio, latarka."""
    f = gender == "female"
    olive = (0.20, 0.23, 0.12)
    khaki = (0.31, 0.25, 0.15)
    leather = (0.22, 0.14, 0.09)
    rubber = (0.07, 0.07, 0.08)
    rust = (0.55, 0.16, 0.10)
    metal = (0.16, 0.17, 0.19)
    canvas = dict(grain=0.004, scale=140.0, dirt=0.9)
    jm = mat("jacket", olive, rough=0.92, tint2=(0.13, 0.15, 0.08), **canvas)
    pm = mat("pants", khaki, rough=0.9, tint2=(0.21, 0.17, 0.10), **canvas)
    bm_ = mat("boots", leather, rough=0.55, grain=0.003, scale=60.0, dirt=0.6, tint2=(0.12, 0.08, 0.05))
    gm = mat("gloves", (0.30, 0.20, 0.12), rough=0.6, grain=0.003, scale=80.0, dirt=0.4, tint2=(0.18, 0.12, 0.08))
    sm = mat("scarf", rust, rough=0.95, tint2=(0.35, 0.10, 0.07), grain=0.003, scale=90.0, dirt=0.3)
    belt_m = mat("belt", (0.10, 0.07, 0.05), rough=0.5, grain=0.002, scale=50.0)
    trim_m = mat("trim", (0.13, 0.10, 0.06), rough=0.8, tint2=(0.08, 0.06, 0.04), grain=0.003, scale=100.0, dirt=0.7)
    pack_m = mat("pack", (0.20, 0.18, 0.10), rough=0.9, tint2=(0.13, 0.11, 0.06), coord="OBJ", dirt=0.5, grain=0.004, scale=110.0)
    roll_m = mat("roll", (0.20, 0.26, 0.30), rough=0.85, coord="OBJ", dirt=0.6, tint2=(0.13, 0.17, 0.20))
    metal_m = mat("metal", metal, rough=0.4, metal=0.85, coord="OBJ")
    rub_m = mat("rubber", rubber, rough=0.7, coord="OBJ")
    cap_m = mat("cap", (0.24, 0.27, 0.16), rough=0.9, tint2=(0.17, 0.2, 0.11), coord="OBJ", grain=0.003, scale=120.0, dirt=0.3)
    parts = []
    k = 0.9 if f else 1.0
    jacket_off = {"spine_01": 0.030 * k, "spine_02": 0.034 * k, "spine_03": 0.032 * k, "clavicle_l": 0.026, "clavicle_r": 0.026,
                  "upperarm_l": 0.024, "upperarm_r": 0.024, "lowerarm_l": 0.018, "lowerarm_r": 0.018, "_": 0.02}
    pants_off = {"pelvis": 0.030, "thigh_l": 0.024, "thigh_r": 0.024, "calf_l": 0.016, "calf_r": 0.016, "_": 0.02}
    parts.append(region_shell(body, arm, "jacket", BONE_SETS["jacket"], jacket_off, jm, thick=0.008))
    parts.append(region_shell(body, arm, "pants", BONE_SETS["pants"], pants_off, pm, thick=0.007))
    sole_m = mat("sole", (0.05, 0.05, 0.055), rough=0.8, coord="OBJ")
    for sfx in ("l", "r"):
        fh, ft = head_pos(arm, f"foot_{sfx}")
        parts.append(rigid(f"boot_{sfx}", sph_fn(1.0, (0.098, 0.185, 0.095), (0, 0, 0), seg=28), f"foot_{sfx}", arm, bm_, loc=(fh.x, fh.y - 0.075, 0.085)))
        parts.append(rigid(f"boot_ankle_{sfx}", cyl_fn(0.088, 0.20, "z", seg=28), f"foot_{sfx}", arm, bm_, loc=(fh.x, fh.y + 0.005, 0.20)))
        parts.append(rigid(f"sole_{sfx}", sph_fn(1.0, (0.104, 0.196, 0.022), (0, 0, 0), seg=28), f"foot_{sfx}", arm, sole_m, loc=(fh.x, fh.y - 0.078, 0.022)))
    parts.append(region_shell(body, arm, "boot_shaft", {"calf_l", "calf_r"}, 0.020, bm_, thick=0.008, zmax=0.30 * body.dimensions.z))
    parts.append(region_shell(body, arm, "gloves", BONE_SETS["gloves"], 0.009, gm, thick=0.004))
    parts.append(region_shell(body, arm, "scarf", BONE_SETS["scarf"], 0.032, sm, thick=0.010))
    sp3h, sp3t0 = head_pos(arm, "spine_03")
    parts.append(region_shell(body, arm, "collar", {"spine_03", "neck_01", "clavicle_l", "clavicle_r"}, 0.046, jm, thick=0.008,
                              zmin=sp3t0.z - 0.035, extra=lambda c: abs(c.x) < 0.115))
    zb = head_pos(arm, "pelvis")[0].z + 0.045
    parts.append(region_shell(body, arm, "belt", BONE_SETS["belt"], 0.044, belt_m, thick=0.008, zmin=zb - 0.04, zmax=zb + 0.04))
    # --- sztywne dodatki (pozycje z rigu)
    sp3, sp3t = head_pos(arm, "spine_03")
    sp2, _ = head_pos(arm, "spine_02")
    pel, _ = head_pos(arm, "pelvis")
    hd, hdt = head_pos(arm, "head")
    fy, by = surf_y(body, sp3.z)                              # przód (−Y) i tył (+Y) tułowia na wysokości klatki
    back_y = by + 0.03
    fy2 = surf_y(body, sp2.z)[0]
    # kurtka: zamek, kieszenie piersiowe z klapkami, epolety
    parts.append(rigid("zip", box_fn((0.012, 0.012, 0.34), 0.003), "spine_02", arm, metal_m, loc=(0, fy2 - 0.040, sp2.z + 0.02)))
    for s_ in (-1, 1):
        parts.append(rigid(f"chest_pocket{s_}", box_fn((0.085, 0.022, 0.085), 0.008), "spine_03", arm, trim_m, loc=(s_ * 0.095, fy - 0.062, sp3.z - 0.01)))
        parts.append(rigid(f"pocket_flap{s_}", box_fn((0.09, 0.018, 0.028), 0.006), "spine_03", arm, trim_m, loc=(s_ * 0.095, fy - 0.068, sp3.z + 0.035)))
        cb = "clavicle_l" if s_ < 0 else "clavicle_r"
        cl, _ = head_pos(arm, cb)
        sg = 1.0 if cl.x > 0 else -1.0
        parts.append(rigid(f"epaulet{s_}", box_fn((0.10, 0.085, 0.016), 0.005), cb, arm, trim_m, loc=(cl.x + sg * 0.12, cl.y, cl.z + 0.065)))
    # spodnie: kieszenie bojówek z klapkami
    for s_, bn in ((-1, "thigh_l"), (1, "thigh_r")):
        th, tt = head_pos(arm, bn)
        mid = (th + tt) * 0.5
        sg = 1.0 if mid.x > 0 else -1.0
        parts.append(rigid(f"cargo{s_}", box_fn((0.05, 0.11, 0.15), 0.010), bn, arm, trim_m, loc=(mid.x + sg * 0.062, mid.y + 0.012, mid.z + 0.02)))
        parts.append(rigid(f"cargo_flap{s_}", box_fn((0.054, 0.115, 0.035), 0.006), bn, arm, trim_m, loc=(mid.x + sg * 0.064, mid.y + 0.012, mid.z + 0.10)))
    # plecak: korpus + klapa + karimata + kieszenie boczne
    parts.append(rigid("pack", box_fn((0.38, 0.20, 0.46), 0.04, (0, 0, 0)), "spine_03", arm, pack_m, loc=(0, back_y + 0.095, sp3.z - 0.03)))
    parts.append(rigid("pack_flap", box_fn((0.39, 0.21, 0.13), 0.04, (0, 0, 0)), "spine_03", arm, pack_m, loc=(0, back_y + 0.105, sp3.z + 0.215)))
    parts.append(rigid("bedroll", cyl_fn(0.075, 0.46, "x", (0, 0, 0)), "spine_03", arm, roll_m, loc=(0, back_y + 0.115, sp3.z + 0.34)))
    for s in (-1, 1):
        parts.append(rigid(f"pack_pouch{s}", box_fn((0.08, 0.11, 0.18), 0.014), "spine_03", arm, pack_m, loc=(s * 0.215, back_y + 0.07, sp3.z - 0.12)))
    # pasy plecaka (taśmy na ramionach, od plecaka do pasa)
    for s in (-1, 1):
        parts.append(rigid(f"strap{s}", box_fn((0.045, 0.012, 0.36), 0.004, rot=Matrix.Rotation(math.radians(8 * s), 3, "Y")),
                           "spine_03", arm, belt_m, loc=(s * 0.095, fy - 0.040, sp3.z - 0.02)))
    # kieszenie na pasie, latarka, kabura-sakwa
    for s in (-1, 1):
        parts.append(rigid(f"pouch{s}", box_fn((0.085, 0.07, 0.10), 0.012), "pelvis", arm, pack_m, loc=(s * 0.155, pel.y - 0.03, pel.z + 0.03)))
    parts.append(rigid("flashlight", cyl_fn(0.020, 0.15, "z"), "pelvis", arm, metal_m, loc=(0.045, pel.y - 0.115, pel.z + 0.03)))
    parts.append(rigid("flashlight_head", cyl_fn(0.027, 0.04, "z"), "pelvis", arm, rub_m, loc=(0.045, pel.y - 0.115, pel.z + 0.115)))
    parts.append(rigid("buckle", box_fn((0.05, 0.012, 0.035), 0.004), "pelvis", arm, metal_m, loc=(0.0, pel.y - 0.135, pel.z + 0.045)))
    # kolanówki
    for s, bn in ((-1, "calf_l"), (1, "calf_r")):
        h, t = head_pos(arm, bn)
        parts.append(rigid(f"kneepad{s}", box_fn((0.115, 0.045, 0.14), 0.016), bn, arm, rub_m, loc=(h.x, h.y - 0.085, h.z + 0.02)))
    # radio na ramieniu (lewa strona od przodu), antena
    parts.append(rigid("radio", box_fn((0.055, 0.035, 0.09), 0.008), "spine_03", arm, metal_m, loc=(0.13, sp3.y - 0.125, sp3.z + 0.07)))
    parts.append(rigid("radio_ant", cyl_fn(0.004, 0.20, "z"), "spine_03", arm, metal_m, loc=(0.145, sp3.y - 0.125, sp3.z + 0.20)))
    # respirator zawieszony na szyi (maska + filtr)
    mask_m = mat("mask", (0.14, 0.16, 0.11), rough=0.55, coord="OBJ", grain=0.002, scale=80.0, dirt=0.4)
    parts.append(rigid("mask", sph_fn(0.085, (1.15, 0.5, 0.78), (0, 0, 0)), "spine_03", arm, mask_m, loc=(0, fy - 0.058, sp3.z + 0.10)))
    for s_ in (-1, 1):
        parts.append(rigid(f"canister{s_}", cyl_fn(0.032, 0.07, "y"), "spine_03", arm, metal_m, loc=(s_ * 0.085, fy - 0.075, sp3.z + 0.085)))
        parts.append(rigid(f"canister_cap{s_}", cyl_fn(0.034, 0.014, "y"), "spine_03", arm, rub_m, loc=(s_ * 0.085, fy - 0.118, sp3.z + 0.085)))
    parts.append(rigid("mask_cord", box_fn((0.20, 0.008, 0.008), 0.002), "spine_03", arm, rub_m, loc=(0, fy - 0.030, sp3.z + 0.19)))
    # czapka z daszkiem
    zn = head_pos(arm, "neck_01")[1].z
    hv = [v.co for o in [body] + [m for m in bpy.data.objects if m.type == "MESH" and m.name.startswith(body.name + ".")]
          for v in o.data.vertices if v.co.z > zn + 0.03]
    xm = max(abs(c.x) for c in hv)
    y0, y1, zt = min(c.y for c in hv), max(c.y for c in hv), max(c.z for c in hv)
    rx, ry, rz = xm * 1.04, (y1 - y0) * 0.5 * 1.02, 0.115
    parts.append(rigid("cap", sph_fn(1.0, (rx, ry, rz), (0, 0, 0), cut_below=0.0), "head", arm, cap_m, loc=(0, (y0 + y1) * 0.5, zt - rz * 0.78)))
    parts.append(rigid("brim", box_fn((rx * 1.7, 0.13, 0.013), 0.005, rot=Matrix.Rotation(math.radians(-10), 3, "X")), "head", arm, cap_m,
                       loc=(0, y0 - 0.055, zt - rz * 0.78 + 0.012)))
    return parts


# ---------------------------------------------------------------- poza

def aim(arm, name, target):
    pb = arm.pose.bones[name]
    bpy.context.view_layer.update()
    h = pb.head.copy()
    d = (target - h).normalized()
    cur = (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(d)
    pb.matrix = Matrix.Translation(h) @ (q.to_matrix().to_4x4() @ pb.matrix.to_3x3().to_4x4())
    bpy.context.view_layer.update()


def pose_relaxed(arm):
    """Swobodna poza „gotowy”: ręce lekko ugięte do przodu (−Y), jedna noga o krok do przodu."""
    for s, sfx in ((-1, "l"), (1, "r")):
        ua, la = arm.data.bones[f"upperarm_{sfx}"], arm.data.bones[f"lowerarm_{sfx}"]
        L1 = (ua.tail_local - ua.head_local).length
        L2 = (la.tail_local - la.head_local).length
        sh = arm.pose.bones[f"upperarm_{sfx}"].head.copy()
        aim(arm, f"upperarm_{sfx}", sh + Vector((s * 0.22, -0.08, -0.97)).normalized() * L1)
        el = arm.pose.bones[f"upperarm_{sfx}"].tail.copy()
        aim(arm, f"lowerarm_{sfx}", el + Vector((s * 0.10, -0.55, -0.82)).normalized() * L2)
    for s, sfx in ((-1, "l"), (1, "r")):
        th = arm.data.bones[f"thigh_{sfx}"]
        L1 = (th.tail_local - th.head_local).length
        hip = arm.pose.bones[f"thigh_{sfx}"].head.copy()
        step = -0.20 if sfx == "l" else 0.14
        aim(arm, f"thigh_{sfx}", hip + Vector((0, step, -1.0)).normalized() * L1)
        knee = arm.pose.bones[f"thigh_{sfx}"].tail.copy()
        ca = arm.data.bones[f"calf_{sfx}"]
        L2 = (ca.tail_local - ca.head_local).length
        aim(arm, f"calf_{sfx}", knee + Vector((0, -step * 0.2 + (0.10 if sfx == "r" else 0.0), -1.0)).normalized() * L2)


# ---------------------------------------------------------------- scena i render

def setup_scene():
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
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, rot, en, col in (("key", (math.radians(52), math.radians(8), math.radians(-35)), 3.6, (1.0, 0.93, 0.82)),
                               ("rim", (math.radians(62), 0, math.radians(150)), 2.6, (0.7, 0.8, 1.0)),
                               ("fill", (math.radians(75), 0, math.radians(60)), 0.9, (0.85, 0.9, 1.0))):
        L = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        L.data.energy = en
        L.data.color = col
        L.rotation_euler = rot
        sc.collection.objects.link(L)
    return sc, cam


def shoot(sc, cam, path, view, w=620, h=900, H=1.7):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    if view == "side":              # postać zwrócona w prawo (+X na ekranie), jak w grze
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = H * 1.28
        cam.location = (-8.0, 0.0, H * 0.5)
        cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    elif view == "front":
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = H * 1.28
        cam.location = (0.0, -8.0, H * 0.5)
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:                           # 3/4 z perspektywą
        cam.data.type = "PERSP"
        cam.data.lens = 75
        cam.location = (-3.2, -5.2, H * 0.62)
        cam.rotation_euler = (math.radians(88), 0, math.radians(-31))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def make_character(cid, gender, skin, hair, brows, height, weight, muscle, cup=0.5):
    b = build_body(gender, skin, hair, brows, height, weight, muscle, cup)
    bake_shapekeys(b)
    H = b.dimensions.z
    ys = [v.co.y for v in b.data.vertices if v.co.z > 0.5 * H]
    yc = sum(ys) / len(ys)
    fn = Warp(H, yc)
    objs = [b] + [o for o in bpy.data.objects if o.type == "MESH" and o is not b and o.name.startswith(b.name)]
    for o in objs:
        warp_object(o, fn)
    arm = HumanService.add_builtin_rig(b, "game_engine")
    bpy.context.view_layer.update()
    # elementy twarzy i włosy MPFB nie dostają wag z rigu — przypinamy je w 100% do kości głowy
    for o in objs[1:]:
        vg = o.vertex_groups.new(name="head")
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    outfit_scavenger(b, arm, gender)
    return b, arm, fn


def main():
    specs = [("male", dict(gender="male", skin="young_caucasian_male", hair="short02", brows="eyebrow001", height=0.45, weight=0.58, muscle=0.62, cup=0.5)),
             ("female", dict(gender="female", skin="young_caucasian_female", hair="ponytail01", brows="eyebrow003", height=0.42, weight=0.5, muscle=0.5, cup=0.28))]
    for cid, kw in specs:
        # każda postać w osobnej, czystej scenie
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
        _mat_cache.clear()
        sc, cam = setup_scene()
        b, arm, fn = make_character(cid, **kw)
        Hn = b.dimensions.z
        print("BUILT", cid, "H=%.2f" % Hn)
        for v in ("side", "front", "three"):
            shoot(sc, cam, f"{OUT}/{cid}_A_{v}.png", v, H=Hn)
        pose_relaxed(arm)
        for v in ("side", "three"):
            shoot(sc, cam, f"{OUT}/{cid}_relaxed_{v}.png", v, H=Hn)
        # GLB (poza spoczynkowa nie jest eksportowana — rig z animacjami dochodzi w fazie potoku)
        for p in arm.pose.bones:
            p.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        for o in bpy.data.objects:
            o.select_set(o.type in ("MESH", "ARMATURE") and True)
        try:
            bpy.ops.export_scene.gltf(filepath=f"{OUT}/{cid}_scavenger.glb", export_format="GLB", use_selection=True, export_apply=True)
            print("GLB", cid, os.path.getsize(f"{OUT}/{cid}_scavenger.glb"))
        except Exception as e:
            print("GLB FAIL", repr(e)[:300])
    print("DONE")


# ---------------------------------------------------------------- animacje do gry (--bake)
# Klatka gry: 64×96 px przy skali 0,25 (świat 16×24). Stopy w dolnej krawędzi, ciało wyśrodkowane na osi postaci. Broń to osobny sprite
# obracany wokół punktu (±1, −12) px nad stopami (weapon_view.gd `_gun_pos`) — dłoń z modelu ma więc stać dokładnie tam w KAŻDEJ klatce.

PX_M = None           # metrów na piksel świata (ustawiane z wysokości męskiej postaci: 23 px)
RENDER_W, RENDER_H = 256, 384
ANIMS = [("idle", 6), ("run", 8), ("jump", 1), ("fall", 1), ("crouch", 1), ("crouch_walk", 6), ("down", 1)]


def T(v):
    return Matrix.Translation(v)


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def rot_about(arm, bone, axis, angle, pivot=None):
    pb = arm.pose.bones[bone]
    h = pb.head.copy() if pivot is None else pivot
    pb.matrix = T(h) @ Matrix.Rotation(angle, 4, axis) @ T(-h) @ pb.matrix
    bpy.context.view_layer.update()


def move_bone(arm, bone, delta):
    pb = arm.pose.bones[bone]
    pb.matrix = T(delta) @ pb.matrix
    bpy.context.view_layer.update()


def reach(arm, upper, lower, target, pole):
    """Dwukostkowe IK na kościach rigu: kończyna sięga celu (w przestrzeni rigu), łokieć/kolano w stronę `pole`."""
    bu, bl = arm.data.bones[upper], arm.data.bones[lower]
    L1, L2 = (bu.tail_local - bu.head_local).length, (bl.tail_local - bl.head_local).length
    sh = arm.pose.bones[upper].head.copy()
    mid = ik2(sh, target, L1, L2, pole)
    aim(arm, upper, mid)
    end = sh + (target - sh).normalized() * min((target - sh).length, L1 + L2 - 1e-4)
    aim(arm, lower, end)


def plant_foot(arm, side, ankle, tilt=0.0):
    """Stopa o orientacji spoczynkowej (płasko) z pochyleniem noska o `tilt` (rad; + = nosek w dół)."""
    pb = arm.pose.bones[f"foot_{side}"]
    rest = arm.data.bones[f"foot_{side}"].matrix_local.to_3x3().to_4x4()
    pb.matrix = T(ankle) @ Matrix.Rotation(-tilt, 4, "X") @ rest
    bpy.context.view_layer.update()


def pose_anim(arm, anim, i, n, env):
    """Ustawia rig na klatkę `i` z `n` animacji `anim`. env: pivot dłoni (stojąc/kucając), PX."""
    reset_pose(arm)
    PX = env["px"]
    t = i / max(n, 1)
    ph = t * math.tau
    lean, bob, drop = 4.0, 0.0, 0.0
    A, Lf = 0.0, 0.0
    feet = {"r": Vector((0, 0, 0)), "l": Vector((0, 0, 0))}      # przesunięcia kostek względem spoczynku (x,y,z)
    hand_h = 12 * PX
    if anim == "idle":
        bob = 0.006 * math.sin(ph)
        lean = 4.0 + 1.0 * math.sin(ph)
        feet = {"r": Vector((0, -0.05, 0)), "l": Vector((0, 0.05, 0))}
    elif anim == "run":
        lean = 11.0
        A, Lf = 0.26, 0.20
        bob = 0.028 * math.cos(2 * ph)
        drop = 0.03
        for side, k in (("r", 0), ("l", 1)):
            phk = ph + k * math.pi
            feet[side] = Vector((0, -(-A * math.cos(phk)), Lf * max(0.0, math.sin(phk))))
    elif anim == "jump":
        lean = 3.0
        feet = {"r": Vector((0, -0.14, 0.30)), "l": Vector((0, 0.06, 0.20))}
    elif anim == "fall":
        lean = 0.0
        feet = {"r": Vector((0, -0.06, 0.12)), "l": Vector((0, 0.08, 0.06))}
    elif anim == "crouch":
        lean = 16.0
        drop = 0.27
        hand_h = 8 * PX
        feet = {"r": Vector((0, -0.10, 0)), "l": Vector((0, 0.09, 0))}
    elif anim == "crouch_walk":
        lean = 16.0
        drop = 0.27
        hand_h = 8 * PX
        A, Lf = 0.12, 0.08
        bob = 0.010 * math.cos(2 * ph)
        for side, k in (("r", 0), ("l", 1)):
            phk = ph + k * math.pi
            feet[side] = Vector((0, -(-A * math.cos(phk)), Lf * max(0.0, math.sin(phk))))
    elif anim == "down":
        lean = -18.0
        drop = 0.52
        hand_h = 0.0
        feet = {"r": Vector((0, -0.52, 0.0)), "l": Vector((0, -0.46, 0.02))}
    # tułów: obniżenie + pochylenie (pochylamy miednicę; nogi i ręce dostają cele niżej)
    move_bone(arm, "pelvis", Vector((0, 0, -drop + bob)))
    rot_about(arm, "pelvis", "X", math.radians(lean))
    rot_about(arm, "head", "X", -math.radians(lean) * 0.7)
    # nogi
    for side in ("r", "l"):
        ankle = arm.data.bones[f"foot_{side}"].head_local.copy() + feet[side]
        reach(arm, f"thigh_{side}", f"calf_{side}", ankle, Vector((0, -1.0, 0.1)))
        plant_foot(arm, side, ankle, tilt=0.25 * max(0.0, feet[side].z / 0.2))
    # ręce: prawa (bliższa kamery, x<0) trzyma broń w punkcie obrotu, lewa — tuż za nią
    if anim != "down":
        sh_r = arm.data.bones["upperarm_r"].head_local
        sh_l = arm.data.bones["upperarm_l"].head_local
        cy = arm.data.bones["pelvis"].head_local.y
        near = Vector((sh_r.x * 0.82, cy - 1.0 * PX, hand_h))
        far = Vector((sh_l.x * 0.35, cy - 3.2 * PX, hand_h + 0.02))
        reach(arm, "upperarm_r", "lowerarm_r", near, Vector((-0.6, 0.6, -0.7)))
        reach(arm, "upperarm_l", "lowerarm_l", far, Vector((0.6, 0.6, -0.7)))
    else:
        for sfx, sx in (("r", -1), ("l", 1)):
            sh = arm.pose.bones[f"upperarm_{sfx}"].head.copy()
            aim(arm, f"upperarm_{sfx}", sh + Vector((sx * 0.25, -0.15, -0.95)).normalized() * 0.3)
            el = arm.pose.bones[f"upperarm_{sfx}"].tail.copy()
            aim(arm, f"lowerarm_{sfx}", el + Vector((sx * 0.1, -0.4, -0.9)).normalized() * 0.28)


def ik2(shoulder, target, a, b, pole):
    """Dwukostkowe IK: łokieć/kolano leży w płaszczyźnie (barek→cel, pole)."""
    s_, t_ = Vector(shoulder), Vector(target)
    d = t_ - s_
    L = max(min(d.length, (a + b) * 0.999), 1e-4)
    dn = d.normalized()
    x = (a * a - b * b + L * L) / (2 * L)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pv = Vector(pole)
    pv = (pv - dn * pv.dot(dn)).normalized()
    return s_ + dn * x + pv * h


def frame_camera(sc, cam, cam_y, px):
    sc.render.resolution_x, sc.render.resolution_y = RENDER_W, RENDER_H
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 24.0 * px                        # wysokość klatki = 24 px świata × px (m/px)
    cam.location = (-8.0, cam_y, cam.data.ortho_scale * 0.5)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))


def bake_frames(out_dir):
    global PX_M
    os.makedirs(out_dir, exist_ok=True)
    specs = [("male", dict(gender="male", skin="young_caucasian_male", hair="short02", brows="eyebrow001", height=0.45, weight=0.58, muscle=0.62, cup=0.5)),
             ("female", dict(gender="female", skin="young_caucasian_female", hair="ponytail01", brows="eyebrow003", height=0.42, weight=0.5, muscle=0.5, cup=0.28))]
    for cid, kw in specs:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
        _mat_cache.clear()
        sc, cam = setup_scene()
        b, arm, fn = make_character(cid, **kw)
        if PX_M is None:                                   # skala wspólna dla obu płci wyznaczona z męskiej postaci (23 px świata)
            PX_M = b.dimensions.z / 23.0
        cy = arm.data.bones["pelvis"].head_local.y
        frame_camera(sc, cam, cy, PX_M)
        env = {"px": PX_M}
        # ukryj siatkę pomocniczą nie jest potrzebne: maska ciała już ją ukrywa
        for anim, n in ANIMS:
            for i in range(n):
                pose_anim(arm, anim, i, n, env)
                sc.render.filepath = f"{out_dir}/{cid}_{anim}_{i}.png"
                bpy.ops.render.render(write_still=True)
            print("BAKED", cid, anim, n)
    with open(f"{out_dir}/meta.txt", "w") as f:
        f.write(f"px_m={PX_M}\nframe=64x96\n")
    print("DONE-BAKE")


if "--bake" in sys.argv:
    bake_frames(OUT)
else:
    main()
