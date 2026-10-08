"""Test wykonalności: modularne postacie z MakeHuman (wtyczka MPFB2 w Blenderze 5.2), płeć × strój, render + eksport GLB.

Wymaga zainstalowanej wtyczki MPFB (extensions.blender.org) i pakietów zasobów MakeHuman (CC0) w katalogu danych MPFB.
Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/char_mpfb_test.py -- OUT_DIR
Wynik: OUT_DIR/mpfb_<id>_{side,front}.png, OUT_DIR/mpfb_<id>.glb (jedna postać z rigiem „game_engine”), raport w stdout.
"""
import math
import os
import sys
import time

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/mpfb"
os.makedirs(OUT, exist_ok=True)

bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.assetservice import AssetService          # noqa: E402
from bl_ext.user_default.mpfb.services.humanservice import HumanService          # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService        # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService    # noqa: E402

DATA = LocationService.get_user_data() if hasattr(LocationService, "get_user_data") else None
print("DATA", DATA)


def asset(kind, name):
    """Ścieżka do assetu .mhclo / .mhmat w katalogu danych (clothes/hair/eyes/...)."""
    base = os.path.join(DATA, kind, name)
    for root, _, files in os.walk(base):
        for f in files:
            if f.endswith(".mhclo") and kind != "skins":
                return os.path.join(root, f)
            if f.endswith(".mhmat") and kind == "skins":
                return os.path.join(root, f)
    raise FileNotFoundError(base)


def make(gender, skin, hair, brows, clothes, shoes, hat=None, height=0.5, weight=0.5, muscle=0.5, cup=0.5, rig=None):
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=1.0 if gender == "male" else 0.0, height=height, weight=weight, muscle=muscle, cupsize=cup, age=0.5)
    macro["race"] = {"asian": 0.1, "caucasian": 0.8, "african": 0.1}
    base = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
    HumanService.set_character_skin(asset("skins", skin), base, skin_type="MAKESKIN")
    items = [("Eyes", "eyes", "low-poly"), ("Eyebrows", "eyebrows", brows), ("Eyelashes", "eyelashes", "eyelashes01"),
             ("Teeth", "teeth", "teeth_base"), ("Hair", "hair", hair), ("Clothes", "clothes", clothes), ("Clothes", "clothes", shoes)]
    if hat:
        items.append(("Clothes", "clothes", hat))
    for atype, kind, name in items:
        try:
            HumanService.add_mhclo_asset(asset(kind, name), base, asset_type=atype, material_type="MAKESKIN")
        except Exception as e:                      # pragma: no cover - raport w teście
            print("ASSET FAIL", atype, name, repr(e)[:160])
    if rig:
        HumanService.add_builtin_rig(base, rig)
    return base


def children_all(o):
    out = [o]
    for c in o.children:
        out.extend(children_all(c))
    return out


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = "--transparent" in sys.argv
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.eevee.taa_render_samples = 32
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.13, 0.15, 0.2, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, rot, en in (("key", (math.radians(55), math.radians(5), math.radians(-40)), 3.5), ("fill", (math.radians(70), 0, math.radians(140)), 1.2)):
        L = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        L.data.energy = en
        L.rotation_euler = rot
        sc.collection.objects.link(L)
    return sc, cam


def shoot(sc, cam, path, side=True, w=600, h=900):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    if side:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 2.0
        cam.location = (6.0, 0.0, 0.95)
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    else:
        cam.data.type = "PERSP"
        cam.data.lens = 70
        cam.location = (-1.6, -4.2, 1.05)
        cam.rotation_euler = (math.radians(88), 0, math.radians(-21))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def hide_others(keep_objs, all_objs):
    keep = set(keep_objs)
    for o in all_objs:
        o.hide_render = o not in keep


def main():
    sc, cam = setup_scene()
    specs = [
        ("m_work", dict(gender="male", skin="young_caucasian_male", hair="short02", brows="eyebrow001", clothes="male_worksuit01", shoes="shoes02", muscle=0.6)),
        ("m_casual", dict(gender="male", skin="young_african_male", hair="short04", brows="eyebrow002", clothes="male_casualsuit03", shoes="shoes04", hat="jujube_newsboy_cap", height=0.6)),
        ("f_sport", dict(gender="female", skin="young_caucasian_female", hair="ponytail01", brows="eyebrow003", clothes="female_sportsuit01", shoes="shoes05", muscle=0.55)),
        ("f_casual", dict(gender="female", skin="young_asian_female", hair="bob02", brows="eyebrow004", clothes="female_casualsuit01", shoes="shoes03", height=0.45)),
    ]
    made = {}
    for i, (cid, kw) in enumerate(specs):
        t = time.time()
        b = make(**kw, rig=("game_engine" if cid == "f_sport" else None))
        made[cid] = b
        print("BUILT", cid, "%.1fs" % (time.time() - t), "verts", len(b.data.vertices), "children", len(b.children))
    allobjs = [o for o in bpy.data.objects if o.type in ("MESH", "ARMATURE")]
    # rozsuń postacie i renderuj pojedynczo
    for cid, b in made.items():
        grp = children_all(b)
        arm = b.parent
        if arm is not None:
            grp = children_all(arm)
        hide_others([o for o in grp], allobjs)
        shoot(sc, cam, f"{OUT}/mpfb_{cid}_side.png", side=True)
        shoot(sc, cam, f"{OUT}/mpfb_{cid}_front.png", side=False)
    # eksport GLB postaci z rigiem
    b = made["f_sport"]
    root = b.parent if b.parent is not None else b
    for o in bpy.data.objects:
        o.hide_render = False
        o.select_set(False)
    for o in children_all(root):
        o.select_set(True)
    try:
        bpy.ops.export_scene.gltf(filepath=f"{OUT}/mpfb_f_sport.glb", export_format="GLB", use_selection=True, export_apply=False)
        print("GLB", os.path.getsize(f"{OUT}/mpfb_f_sport.glb"))
    except Exception as e:
        print("GLB FAIL", repr(e)[:300])
    print("DONE")


main()
