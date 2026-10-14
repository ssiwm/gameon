"""Generator realistycznych postaci gracza z MPFB2 (MakeHuman dla Blendera) — `art/char3d/mpfb/<płeć>_<strój>.glb` (CHARACTER_PLAN.md).

Uruchomienie (z korzenia repo; Blender z dodatkiem MPFB2 i paczkami zasobów CC0 — patrz niżej):
    blender -b -P prototype/tools/char_mpfb.py -- male_scav [female_medic ...] | --all  [--shot=PLIK.png]

Ciało, ubrania, skóry i włosy pochodzą z paczek MakeHuman (CC0): makehuman_system_assets, skins01–02, shirts01, pants01, shoes01,
hats01–02, gloves01, masks01, equipment01 (static.makehumancommunity.org/assets/assetpacks/), wczytanych do MPFB
(„apply assets” → „library settings” → „load pack from zip”). Wynik generatora też jest CC0. Uwaga: bez `--factory-startup`,
bo dodatek MPFB musi być włączony.

Szkielet „mixamo” z MPFB ma nazwy kości jak dotychczasowe modele Tripo (`mixamorig:*`), a do tego po trzy kości na palec —
`char3d.gd`, `char_clips.gd` i klipy z `prep_anim3d.py` działają bez zmian. Model stoi jak modele Tripo: przód +X, góra +Z,
stopy na z = 0, wzrost ciała (bez czapki / hełmu) wg `height` w tabeli.

Co robi: składa postać z tabeli OUTFITS (fenotyp, skóra, włosy, ubrania), przebarwia tekstury ubrań (np. dżinsy → bojówki khaki),
zapieka kształt ciała (cele MPFB to klucze kształtu) i ukrywa ciało pod ubraniami (maski MPFB), upraszcza ciało do budżetu trójkątów,
zmniejsza tekstury do --tex px i eksportuje GLB.
"""
import colorsys
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from bl_ext.user_default.mpfb.services import HumanService

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "art", "char3d", "mpfb")
GEAR_SRC = os.path.join(os.path.dirname(os.path.dirname(HERE)), "art_src", "gear")   # modele ekwipunku (FLUX + TRELLIS 2, SOURCE.md)

# gotowe modele ekwipunku: plik w art_src/gear, kość, rozmiar (m: „height” — wysokość albo „length” — najdłuższy wymiar w poziomie),
# obrót wokół pionu (°: przód modelu → od pleców; śpiwór w poprzek pleców), budżet trójkątów
GEAR_MODELS = {
    "backpack": {"file": "backpack.glb", "bone": "Spine2", "height": 0.58, "yaw": -90.0, "tris": 4000},
    "bedroll": {"file": "bedroll.glb", "bone": "Spine2", "length": 0.56, "diameter": 0.2, "yaw": 0.0, "axis": "Y", "tris": 6000},
    "airtank": {"file": "airtank.glb", "bone": "Spine2", "height": 0.60, "yaw": -90.0, "tris": 5000},     # aparat oddechowy: butle ~60 cm
    "medbag": {"file": "medbag.glb", "bone": "Spine2", "height": 0.42, "yaw": -90.0, "tris": 4000},      # plecak medyczny
    "pouch": {"file": "pouch.glb", "bone": "Hips", "height": 0.12, "depth": 0.065, "yaw": 0.0, "tris": 1500},      # ładownica na pas
    "canteen": {"file": "canteen.glb", "bone": "Hips", "height": 0.20, "depth": 0.085, "yaw": -90.0, "tris": 1500},  # manierka w pokrowcu   # oś walca w poprzek pleców
}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return next((a.split("=", 1)[1] for a in argv if a.startswith("--%s=" % name)), default)


TEX = int(arg("tex", "1024"))                 # ciało, włosy, oczy
CLOTH_TEX = int(arg("cloth-tex", "1024"))     # ubrania i ekwipunek w GLB (w kamerze gry postać ma ok. 145 px)
BAKE_TEX = int(arg("bake-tex", "2048"))       # rozdzielczość wypieku cieni (potem zmniejszana do CLOTH_TEX)
BODY_TRIS = int(arg("body-tris", "7000"))     # budżet trójkątów: ciało i każda część ubrania (cała postać ok. 25–30 tys.)
PART_TRIS = int(arg("part-tris", "3500"))     # domyślny budżet części; wpis stroju może mieć własny ("tris")
SAMPLES = int(arg("samples", "32"))           # próbki Cycles przy wypiekaniu cieni kontaktowych
SEWN = "--sewn" in argv                       # próba: ubrania szyte symulacją (tools/cloth_jacket.py, art_src/clothes) zamiast z paczek MPFB
if arg("out"):
    OUT = os.path.join(os.path.dirname(HERE), "art", "char3d", arg("out"))     # inny zestaw modeli (Char3D.charset), np. do porównań
CLOTH_SRC = os.path.join(os.path.dirname(os.path.dirname(HERE)), "art_src", "clothes")
UPPER = ("Spine", "Neck", "Shoulder", "Arm", "Hand")   # kości górnej połowy (kurtka); Hips i nogi to spodnie

# przebarwienie tekstury: piksele o odcieniu w [od, do] (stopnie) i nasyceniu w [od, do] dostają nowy odcień, nasycenie i jasność
# (mnożnik); reguły idą po kolei, piksel zmieniony przez wcześniejszą regułę już nie łapie się na następne
# „camo”: na zmienione piksele idzie wzór kamuflażu (plamy w przestrzeni UV, cienie i fałdy tkaniny zostają)
DENIM_TO_KHAKI = {"hue": (180, 260), "s": (0.12, 1.0), "to_hue": 38, "sat": 0.38, "val": 1.15}
GREY_TO_OLIVE = {"hue": (0, 360), "s": (0.0, 0.3), "to_hue": 68, "sat": 0.32, "val": 1.0}
RED_TO_RUST = {"hue": (300, 360), "s": (0.25, 1.0), "to_hue": 8, "sat": 0.7, "val": 0.75}
DENIM_TO_CAMO = dict(DENIM_TO_KHAKI, camo="woodland", seed=3)
ALL = {"hue": (0, 360), "s": (0.0, 1.0), "to_hue": 0, "sat": 0.0, "val": 1.0}
ALL_TO_CAMO = dict(ALL, camo="woodland", seed=5)
ALL_TO_HAZMAT = dict(ALL, camo="hazmat", all_px=True)
ALL_TO_NAVY = dict(ALL, camo="navy", all_px=True)          # cały mundur w granacie (pasy odblaskowe dawały białe łaty)
GREY_TO_CAMO = dict(GREY_TO_OLIVE, camo="woodland", seed=7)

# kamuflaż leśny lat 80.: tło i plamy — brąz, ciemna zieleń, czerń (próg pola szumu), wielkość plam (komórki szumu na atlas);
# wzór bez plam = jednolity kolor tkaniny z zachowaniem fałd („clip”: zakres jasności względem mediany — mniejszy gasi logo i napisy)
CAMO = {
    "hazmat": {"base": (0.80, 0.62, 0.07), "cells": 1, "spots": [], "clip": (0.5, 1.3)},
    "navy": {"base": (0.10, 0.14, 0.25), "cells": 1, "spots": [], "clip": (0.7, 1.2)},
    "woodland": {"base": (0.36, 0.34, 0.22), "cells": 42,
                 "spots": [((0.27, 0.19, 0.11), 0.60), ((0.15, 0.19, 0.10), 0.58), ((0.06, 0.06, 0.05), 0.71)]},
}

MALE = {"age": 0.6, "muscle": 0.65, "weight": 0.55, "proportions": 0.9, "height": 0.6}
FEMALE = {"age": 0.55, "muscle": 0.55, "weight": 0.5, "proportions": 0.9, "height": 0.5}
WHITE_RACE = {"asian": 0.1, "caucasian": 0.8, "african": 0.1}

OUTFITS = {
    "male_scav": {
        "sex": "male", "height": 1.80, "phenotype": MALE, "race": WHITE_RACE,
        "skin": "middleage_caucasian_male", "hair": "short02", "eyebrows": "eyebrow001",
        "clothes": {
            "male_casualsuit05": {"recolor": [DENIM_TO_CAMO, RED_TO_RUST, GREY_TO_CAMO]},     # kurtka polowa i spodnie w kamuflażu
            "mindfront_tactical_vest_male": {},                       # kamizelka taktyczna (CC-BY, Mindfront)
            "mindfront_shoes_biker_boots_male": {},                   # kozaki (CC-BY, Mindfront)
            "mindfront_helmet_kz45": {"tris": 1800},                  # hełm (CC-BY, Mindfront)
            "toigo_gloves_short": {"tint": (0.30, 0.20, 0.13)},      # rękawice skórzane
            "gredal_gas_mask": {"relocate": "left_hip", "tris": 1800},   # maska przeciwgazowa przy biodrze (CC-BY, Mathias_Gredal)
        },
        "gear": ["backpack_model", "belt_pouches", "neckerchief"],
        # --sewn: kurtka M65 z symulacji tkaniny w miejsce góry kompletu casualsuit05 (spodnie zostają)
        "sewn": {"m65": {"file": "male_scav_m65.glb", "replaces": "male_casualsuit05", "tris": 6500}},
    },
    "female_scav": {
        "sex": "female", "height": 1.70, "phenotype": FEMALE, "race": WHITE_RACE,
        "skin": "young_caucasian_female", "hair": "ponytail01", "eyebrows": "eyebrow002",
        "clothes": {
            "elvs_emt_uniform_jacket_female": {"recolor": [ALL_TO_CAMO]},   # kurtka (CC-BY, Elvaerwyn) w kamuflażu
            "elvs_emt_uniform_pants_female": {"recolor": [ALL_TO_CAMO]},
            "mindfront_tactical_vest_female": {},
            "mindfront_shoes_biker_boots_female": {},
            "mindfront_helmet_kz45": {"tris": 1800},
            "toigo_gloves_short": {"tint": (0.30, 0.20, 0.13)},
            "gredal_gas_mask": {"relocate": "left_hip", "tris": 1800},
        },
        "gear": ["backpack_model", "belt_pouches", "neckerchief"],
    },
    "male_hazmat": {
        "sex": "male", "height": 1.80, "phenotype": MALE, "race": WHITE_RACE,
        "skin": "young_caucasian_male", "hair": "", "eyebrows": "",
        "clothes": {
            "elvs_male_coveralls_1": {"recolor": [ALL_TO_HAZMAT]},  # kombinezon (CC-BY, Elvaerwyn) jako gumowany, żółty
            "culturalibre_hero-heroine_hood_1": {"tint": (0.80, 0.62, 0.07)},   # kaptur
            "gredal_gas_mask": {"tris": 1800},                        # maska na twarzy
            "toigo_gloves_short": {"tint": (0.10, 0.10, 0.09)},      # gumowe rękawice (długie przebijały przez rękawy)
            "toigo_ankle_boots_male": {"tint": (0.09, 0.09, 0.08)},   # gumowe buty (wysokie przebijały przez nogawki)
        },
        "gear": ["air_tank", "belt_pouches", "tape"],
    },
    "female_hazmat": {
        "sex": "female", "height": 1.70, "phenotype": FEMALE, "race": WHITE_RACE,
        "skin": "young_caucasian_female", "hair": "", "eyebrows": "",
        "clothes": {
            "elvs_racing_fire_suit_female1": {"recolor": [ALL_TO_HAZMAT]},   # kombinezon (CC-BY, Elvaerwyn)
            "culturalibre_hero-heroine_hood_1": {"tint": (0.80, 0.62, 0.07)},
            "gredal_gas_mask": {"tris": 1800},
            "toigo_gloves_short": {"tint": (0.10, 0.10, 0.09)},
            "toigo_ankle_boots_female": {"tint": (0.09, 0.09, 0.08)},
        },
        "gear": ["air_tank", "belt_pouches", "tape"],
    },
    "male_medic": {
        "sex": "male", "height": 1.80, "phenotype": MALE, "race": {"asian": 0.05, "caucasian": 0.15, "african": 0.8},
        "skin": "middleage_african_male", "hair": "short01", "eyebrows": "eyebrow001",
        "clothes": {
            "elvs_emt_uniform_jacket_male": {"recolor": [ALL_TO_NAVY]},   # mundur ratownika (CC-BY, Elvaerwyn) w granacie
            "elvs_emt_uniform_pants_male": {"recolor": [ALL_TO_NAVY]},
            "jaldmic_m1951_72": {"tint": (0.82, 0.82, 0.78), "tris": 1800},   # biały hełm (CC-BY, jaldmic)
            "punkduck_stethoscope": {"tris": 600},                    # stetoskop (CC-BY, punkduck)
            "toigo_ankle_boots_male": {"tint": (0.12, 0.09, 0.07)},
        },
        "gear": ["medkit_pack", "helmet_cross", "belt_pouches"],
    },
    "female_medic": {
        "sex": "female", "height": 1.70, "phenotype": FEMALE, "race": {"asian": 0.6, "caucasian": 0.35, "african": 0.05},
        "skin": "young_asian_female", "hair": "ponytail01", "eyebrows": "eyebrow002",
        "clothes": {
            "elvs_emt_uniform_jacket_female": {"recolor": [ALL_TO_NAVY]},
            "elvs_emt_uniform_pants_female": {"recolor": [ALL_TO_NAVY]},
            "jaldmic_m1951_72": {"tint": (0.82, 0.82, 0.78), "tris": 1800},
            "punkduck_stethoscope": {"tris": 600},
            "toigo_ankle_boots_female": {"tint": (0.12, 0.09, 0.07)},
        },
        "gear": ["medkit_pack", "helmet_cross", "belt_pouches"],
    },
}

# ------------------------------------------------------------------------------------------------ narzędzia

def recolor_image(img, rules):
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = px[:, :3]
    mx = rgb.max(1)
    mn = rgb.min(1)
    d = mx - mn + 1e-6
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    s = np.where(mx > 0, d / (mx + 1e-6), 0)
    done = mx < 0.004                                            # tło atlasu (czysta czerń) zostaje; ciemna tkanina już nie
    out = rgb.copy()
    side = int(round(math.sqrt(len(px))))
    for rule in rules:
        lo, hi = rule["hue"]
        m = (h >= lo) & (h <= hi) & (s >= rule["s"][0]) & (s <= rule["s"][1]) & ~done
        if rule.get("all_px"):                                   # cała tkanina, także czarne łaty (tło atlasu i tak nie jest widoczne)
            m = ~done | (mx < 0.004)
        if "v" in rule:
            m &= (mx >= rule["v"][0]) & (mx <= rule["v"][1])
        v = np.clip(mx * rule["val"], 0, 1)
        # HSV → RGB dla nowego odcienia (jeden odcień, więc wystarczy kolor bazowy razy jasność)
        base = np.array(colorsys.hsv_to_rgb(rule["to_hue"] / 360.0, rule["sat"], 1.0), dtype=np.float32)
        out[m] = v[m, None] * base[None, :]
        if rule.get("camo"):
            cm = CAMO[rule["camo"]]
            col = np.tile(np.array(cm["base"], dtype=np.float32)[None, :], (len(px), 1))
            for i, (c, thr) in enumerate(cm["spots"]):
                f = smooth_noise(side, side, cm["cells"], rule.get("seed", 0) * 10 + i).ravel()
                col[f > thr] = np.array(c, dtype=np.float32)
            # jasność tkaniny względem mediany: fałdy i szwy zostają, przetarcia dżinsu nie robią białych plam
            vm = float(np.median(mx[m])) if m.any() else 1.0
            lo_c, hi_c = cm.get("clip", (0.6, 1.25))
            out[m] = col[m] * np.clip(mx[m] / max(vm, 1e-3), lo_c, hi_c)[:, None]
        done |= m
        print("RECOLOR", img.name, rule["to_hue"], int(m.sum()), "px")
    px[:, :3] = out
    img.pixels[:] = px.ravel()


def smooth_noise(h, w, cells, seed):
    """Gładkie pole szumu 0..1 (siatka `cells` × `cells` wartości losowych, interpolacja dwuliniowa z wygładzeniem, dwie oktawy)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), dtype=np.float32)
    for k, amp in ((cells, 0.7), (cells * 3, 0.3)):
        g = rng.random((k + 1, k + 1)).astype(np.float32)
        ys = np.linspace(0, k, h, dtype=np.float32)
        xs = np.linspace(0, k, w, dtype=np.float32)
        y0 = np.minimum(ys.astype(int), k - 1)
        x0 = np.minimum(xs.astype(int), k - 1)
        ty = ys - y0
        tx = xs - x0
        ty = ty * ty * (3 - 2 * ty)
        tx = tx * tx * (3 - 2 * tx)
        a = g[y0][:, x0]
        b = g[y0][:, x0 + 1]
        c = g[y0 + 1][:, x0]
        d = g[y0 + 1][:, x0 + 1]
        top = a + (b - a) * tx[None, :]
        bot = c + (d - c) * tx[None, :]
        out += amp * (top + (bot - top) * ty[:, None])
    return out


def tint_image(img, tint):
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    lum = px[:, :3] @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    lit = lum[px[:, 3] > 0.5] if (px[:, 3] > 0.5).any() else lum
    k = np.clip(lum / max(float(np.median(lit)), 1e-3), 0.55, 1.3)
    px[:, :3] = np.clip(k[:, None] * np.array(tint, dtype=np.float32)[None, :], 0, 1)
    img.pixels[:] = px.ravel()
    print("TINT", img.name)


def ensure_material(o, key):
    """Część, której MPFB nie dał materiału (np. czapka z paczki hats01): materiał z tekstury z pliku .mhmat obok .mhclo."""
    from bl_ext.user_default.mpfb.services import LocationService
    d = os.path.join(LocationService.get_user_data(), "clothes", key)
    tex = None
    for f in os.listdir(d) if os.path.isdir(d) else []:
        if f.endswith(".mhmat"):
            for line in open(os.path.join(d, f), encoding="utf-8", errors="ignore"):
                if line.startswith("diffuseTexture "):
                    tex = os.path.join(d, line.split(None, 1)[1].strip())
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.85
    if tex and os.path.exists(tex):
        n = mat.node_tree.nodes.new("ShaderNodeTexImage")
        n.name = "diffuseTexture"
        n.image = bpy.data.images.load(tex)
        mat.node_tree.links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
    o.data.materials.clear()
    o.data.materials.append(mat)
    print("MATERIAL", key, tex)


def obj_images(o):
    out = {}
    for m in o.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    out[n.name] = n.image
    return out


# ------------------------------------------------------------------------------------------------ ekwipunek (bryły skryptem)
# Model stoi przodem do +X, góra +Z, prawa strona postaci to −Y. Każda część jest w całości przypięta do jednej kości.

COL = {
    "leather": ((0.22, 0.12, 0.06), 0.65), "canvas": ((0.50, 0.42, 0.28), 0.9), "olive": ((0.26, 0.28, 0.17), 0.85),
    "strap": ((0.16, 0.10, 0.06), 0.7), "rust": ((0.45, 0.10, 0.06), 0.9), "metal": ((0.35, 0.33, 0.30), 0.5),
    "white": ((0.80, 0.80, 0.76), 0.7), "canvas_dark": ((0.12, 0.10, 0.055), 0.9), "tape": ((0.05, 0.05, 0.05), 0.5), "red": ((0.62, 0.05, 0.04), 0.6), "steel": ((0.36, 0.39, 0.35), 0.45),
}


def _bone(rig, n):
    return rig.matrix_world @ rig.data.bones["mixamorig:" + n].head_local


def _section(pts, z, dz=0.03, y_max=None):
    """Zasięg sylwetki (ciało + ubrania) na wysokości z: (x_min, x_max, y_min, y_max)."""
    sel = [p for p in pts if abs(p.z - z) < dz and (y_max is None or abs(p.y) < y_max)]
    return (min(p.x for p in sel), max(p.x for p in sel), min(p.y for p in sel), max(p.y for p in sel))


def _part(rig, name, bm, bone, col):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.parent = rig
    vg = o.vertex_groups.new(name="mixamorig:" + bone)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    o.modifiers.new("Armature", "ARMATURE").object = rig
    mat = bpy.data.materials.get("gear_" + col)
    if mat is None:
        mat = bpy.data.materials.new("gear_" + col)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = COL[col][0] + (1.0,)
        bsdf.inputs["Roughness"].default_value = COL[col][1]
    me.materials.append(mat)
    return o


def _box(size, centre, bevel=0.015, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
    if rot is not None:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=rot)
    bmesh.ops.translate(bm, vec=Vector(centre), verts=bm.verts)
    return bm


def _cyl(r, length, centre, axis="Y", caps=True, seg=16, scale_xy=(1.0, 1.0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, segments=seg, radius1=r, radius2=r, depth=length)
    bmesh.ops.scale(bm, vec=Vector((scale_xy[0], scale_xy[1], 1.0)), verts=bm.verts)
    if axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=Vector(centre), verts=bm.verts)
    return bm


def _strap(rig, p0, p1, bone):
    v = p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(v.normalized()).to_matrix()
    _part(rig, "strap", _box((0.012, 0.045, v.length + 0.02), (p0 + p1) * 0.5, 0.004, rot), bone, "strap")


def add_gear(rig, gear):
    before = set(rig.children)
    _add_gear(rig, gear)
    # jedna siatka na cały ekwipunek (mniej wywołań rysowania); grupy wierzchołków per kość zostają
    parts = [o for o in rig.children if o not in before and o.name.split("_")[0].split(".")[0] not in GEAR_MODELS]   # gotowe modele mają własne UV i tekstury
    if len(parts) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in parts:
            o.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        parts[0].name = "gear"


def relocate(rig, o, where):
    """Część stroju zdjęta z miejsca, do którego ją uszyto, i przypięta sztywnie do kości (np. maska przeciwgazowa przy biodrze)."""
    pts = [p.matrix_world @ v.co for p in rig.children if p.type == "MESH" and p != o for v in p.data.vertices]
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    c = sum(vs, Vector()) / len(vs)
    hips = _bone(rig, "Hips")
    if where == "left_hip":
        z = hips.z - 0.06
        y_left = _section(pts, z, dz=0.02, y_max=0.19)[3]
        target = Vector((hips.x - 0.02, y_left + 0.06, z))
        rot = Matrix.Rotation(math.radians(-30), 4, "X") @ Matrix.Rotation(math.radians(90), 4, "Z")   # twarzą w bok i w dół
        bone = "Hips"
    m = Matrix.Translation(target) @ rot @ Matrix.Translation(-c)
    for v in o.data.vertices:
        v.co = o.matrix_world.inverted() @ (m @ (o.matrix_world @ v.co))
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    vg = o.vertex_groups.new(name="mixamorig:" + bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")


def _ring(rig, pts, at_bone, along_bone, weight_bone, width, col, grow=0.006):
    """Opaska wokół kończyny w punkcie kości `at_bone` (oś: kość `along_bone`), promień z otaczającej siatki ubrań."""
    a = rig.matrix_world @ rig.data.bones["mixamorig:" + along_bone].head_local
    c = rig.matrix_world @ rig.data.bones["mixamorig:" + at_bone].head_local
    ax = (c - a).normalized()
    near = [p for p in pts if abs((p - c).dot(ax)) < width and ((p - c) - ax * (p - c).dot(ax)).length < 0.14]
    if not near:
        return
    r = sorted(((p - c) - ax * (p - c).dot(ax)).length for p in near)[int(len(near) * 0.92)] + grow
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=14, radius1=r, radius2=r, depth=width)
    rot = Vector((0, 0, 1)).rotation_difference(ax).to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=rot)
    bmesh.ops.translate(bm, vec=c, verts=bm.verts)
    _part(rig, "tape", bm, weight_bone, col)


def _import_gear(rig, key, ks):
    """Model z art_src/gear: jedna siatka, uproszczona, obrócona i przeskalowana, wyśrodkowana w (0, 0, 0), przypięta do kości."""
    g = GEAR_MODELS[key]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GEAR_SRC, g["file"]))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.parent = None
    for x in new:
        if x != o:
            bpy.data.objects.remove(x, do_unlink=True)
    o.name = key
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > g["tris"]:
        dec = o.modifiers.new("dec", "DECIMATE")
        dec.ratio = g["tris"] / tris
        bpy.ops.object.modifier_apply(modifier=dec.name)
    if "axis" in g:
        # model z ujęcia 3/4 leży po skosie: główna oś bryły (PCA wierzchołków) na zadaną oś
        arr = np.array([v.co[:] for v in o.data.vertices], dtype=np.float64)
        w, vec = np.linalg.eigh(np.cov((arr - arr.mean(0)).T))
        main = Vector(vec[:, int(np.argmax(w))])
        o.data.transform(main.rotation_difference(Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[g["axis"]])).to_matrix().to_4x4())
    vs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    size = (hi.z - lo.z) if "height" in g else max(hi.x - lo.x, hi.y - lo.y)
    k = g.get("height", g.get("length")) * ks / size
    c = (lo + hi) * 0.5
    dk = 1.0
    if "depth" in g:                                             # grubość przód–tył (oś Y modelu): TRELLIS robi z płaskich rzeczy klocki
        dk = g["depth"] * ks / ((hi.y - lo.y) * k)
    o.data.transform(Matrix.Rotation(math.radians(g["yaw"]), 4, "Z") @ Matrix.Diagonal((k, k * dk, k, 1.0)) @ Matrix.Translation(-c))
    if "diameter" in g:
        # walec (śpiwór): przekrój do zadanej średnicy, długość bez zmian
        vs = [v.co for v in o.data.vertices]
        dx = max(v.x for v in vs) - min(v.x for v in vs)
        dz = max(v.z for v in vs) - min(v.z for v in vs)
        f = g["diameter"] * ks / ((dx + dz) * 0.5)
        o.data.transform(Matrix.Diagonal((f, 1.0, f, 1.0)))
    o.parent = rig
    vg = o.vertex_groups.new(name="mixamorig:" + g["bone"])
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    o.modifiers.new("Armature", "ARMATURE").object = rig
    for mt in o.data.materials:
        for n in mt.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Metallic"].default_value = 0.0
    vs = [v.co for v in o.data.vertices]
    ext = Vector([max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)])
    want = g.get("height", g.get("length")) * ks
    got = ext.z if "height" in g else max(ext.x, ext.y)
    print("GEAR MODEL %s tris %d size %.2f x %.2f x %.2f m (cel %.2f)" % (key, sum(len(p.vertices) - 2 for p in o.data.polygons),
                                                                         ext.x, ext.y, ext.z, want))
    assert abs(got / want - 1.0) < 0.1, "proporcje %s: %.2f m zamiast %.2f m" % (key, got, want)
    return o


def _has(key):
    return key in GEAR_MODELS and os.path.exists(os.path.join(GEAR_SRC, GEAR_MODELS[key]["file"]))


def gear_model(rig, pts, key, neck, sh):
    """Plecak z art_src/gear na plecach: wierzch pod karkiem, bryła przy plecach (szelki modelu mogą wejść w ciało)."""
    ks = neck.z / 1.52
    o = _import_gear(rig, key, ks)
    vs = [v.co for v in o.data.vertices]
    depth = max(v.x for v in vs) - min(v.x for v in vs)
    top = neck.z - 0.02
    zc = top - GEAR_MODELS[key]["height"] * ks * 0.5
    back = _section(pts, zc, y_max=0.12)[0]
    xs = sorted(v.x for v in vs)
    o.data.transform(Matrix.Translation((back + 0.015 - xs[int(len(xs) * 0.9)], 0.0, zc)))
    vs = [v.co for v in o.data.vertices]
    z1 = max(v.z for v in vs)
    crown = [v for v in vs if v.z > z1 - 0.08]
    o["crown"] = (sum(v.x for v in crown) / len(crown), z1)        # środek i wierzch korony plecaka (miejsce na śpiwór)
    return back - depth * 0.5, depth, top, zc


def _harness(rig, pts, xc, d, top, zc, sh):
    """Szelki: od górnej krawędzi plecaka przez barki na pierś."""
    front_top = _section(pts, sh.z - 0.06, y_max=0.12)[1]
    front_low = _section(pts, zc - 0.12, y_max=0.12)[1]
    for side in (-1, 1):
        y = side * 0.1
        a = Vector((xc + d * 0.4, y, top - 0.02))
        m = Vector(((xc + front_top) * 0.5, y, sh.z + 0.05))
        b = Vector((front_top + 0.008, y, sh.z - 0.03))
        c = Vector((front_low + 0.01, y, zc - 0.14))
        _strap(rig, a, m, "Spine2")
        _strap(rig, m, b, "Spine2")
        _strap(rig, b, c, "Spine2")


def _add_gear(rig, gear):
    pts = [o.matrix_world @ v.co for o in rig.children if o.type == "MESH" for v in o.data.vertices]
    neck = _bone(rig, "Neck")
    hips = _bone(rig, "Hips")
    sh = _bone(rig, "RightArm")
    ks = neck.z / 1.52                                           # skala ekwipunku wg wzrostu (kobieta ~0,95)
    if "medkit_pack" in gear and _has("medbag"):
        xc, d, top, zc = gear_model(rig, pts, "medbag", neck, sh)
        _harness(rig, pts, xc, d, top, zc, sh)
    elif "medkit_pack" in gear:
        # biała torba medyczna na plecach z czerwonym krzyżem, szelki jak przy plecaku
        top = neck.z - 0.08
        h, w, d = 0.34 * ks, 0.30 * ks, 0.14 * ks
        zc = top - h * 0.5
        back = _section(pts, zc, y_max=0.12)[0]
        xc = back - d * 0.5 + 0.01
        _part(rig, "medkit", _box((d, w, h), (xc, 0.0, zc), 0.03), "Spine2", "white")
        xb = xc - d * 0.5 - 0.004
        _part(rig, "medkit_cross", _box((0.01, 0.16 * ks, 0.05 * ks), (xb, 0.0, zc), 0.0), "Spine2", "red")
        _part(rig, "medkit_cross", _box((0.01, 0.05 * ks, 0.16 * ks), (xb, 0.0, zc), 0.0), "Spine2", "red")
        _part(rig, "medkit_lid", _box((d + 0.01, w + 0.01, 0.03), (xc, 0.0, top - 0.015), 0.01), "Spine2", "white")
        _part(rig, "medkit_seam", _box((d + 0.012, w + 0.012, 0.008), (xc, 0.0, top - 0.035), 0.002), "Spine2", "strap")
        _part(rig, "medkit_handle", _box((0.03, w * 0.5, 0.02), (xc, 0.0, top + 0.012), 0.008), "Spine2", "strap")
        for yy in (-w * 0.3, w * 0.3):
            _part(rig, "medkit_clasp", _box((0.012, 0.03, 0.05), (xb - 0.003, yy, top - 0.05), 0.003), "Spine2", "metal")
        _harness(rig, pts, xc, d, top, zc, sh)
    if "air_tank" in gear and _has("airtank"):
        xc, d, top, zc = gear_model(rig, pts, "airtank", neck, sh)
        _harness(rig, pts, xc, d, top, zc, sh)
    elif "air_tank" in gear:
        # dwie butle powietrza na plecach (Spine2) z zaworami i opaskami
        top = neck.z - 0.03
        r, ln = 0.075 * ks, 0.52 * ks
        zc = top - ln * 0.5
        back = _section(pts, zc, y_max=0.12)[0]
        xc = back - r - 0.01
        for yy in (-0.08 * ks, 0.08 * ks):
            _part(rig, "tank", _cyl(r, ln, (xc, yy, zc), axis="Z", seg=16), "Spine2", "steel")
            _part(rig, "tank_valve", _cyl(0.022, 0.06, (xc, yy, top + 0.03), axis="Z", seg=8), "Spine2", "metal")
            for zz in (zc + ln * 0.3, zc - ln * 0.3):
                _part(rig, "tank_band", _cyl(r + 0.004, 0.03, (xc, yy, zz), axis="Z", seg=16), "Spine2", "strap")
        _part(rig, "tank_hose", _cyl(0.012, 0.32, (xc + 0.05, 0.12 * ks, top - 0.02), axis="Y", seg=6), "Spine2", "strap")
        _part(rig, "tank_bridge", _box((0.03, 0.16 * ks + 0.04, 0.03), (xc, 0.0, top + 0.05), 0.008), "Spine2", "metal")
        _part(rig, "tank_gauge", _cyl(0.025, 0.02, (xc - 0.03, 0.0, top + 0.05), axis="Z", seg=12), "Spine2", "white")
        _part(rig, "tank_plate", _box((0.012, 0.12, 0.08), (xc - r - 0.004, 0.0, zc), 0.004), "Spine2", "white")
        _harness(rig, pts, xc, r * 2, top - 0.05, zc, sh)
    if "tape" in gear:
        # taśma na styku rękawic i rękawów oraz butów i nogawek — klasyczny kombinezon ochronny
        cl = [o.matrix_world @ v.co for o in rig.children if o.type == "MESH" and o.name not in ("body", "gear")
              for v in o.data.vertices]
        for side in ("Left", "Right"):
            _ring(rig, cl, side + "Hand", side + "ForeArm", side + "ForeArm", 0.05, "tape")
            _ring(rig, cl, side + "Foot", side + "Leg", side + "Leg", 0.06, "tape")
    if "helmet_cross" in gear:
        # biały hełm medyka: czerwony krzyż z przodu (Head)
        hm = next((o for o in rig.children if o.type == "MESH" and ("helmet" in o.name or "m1951" in o.name)), None)
        if hm is not None:
            hv = [hm.matrix_world @ v.co for v in hm.data.vertices]
            z1 = max(p.z for p in hv)
            zc = z1 - 0.06                                       # czasza hełmu (bez paska pod brodą)
            band = [p.x for p in hv if abs(p.z - zc) < 0.02 and abs(p.y) < 0.04]
            xf = max(band) if band else max(p.x for p in hv)
            _part(rig, "helmet_cross", _box((0.006, 0.07, 0.022), (xf + 0.001, 0.0, zc), 0.0), "Head", "red")
            _part(rig, "helmet_cross", _box((0.006, 0.022, 0.07), (xf + 0.001, 0.0, zc), 0.0), "Head", "red")
    if "backpack_model" in gear:
        xc, d, top, zc = gear_model(rig, pts, "backpack", neck, sh)
        _harness(rig, pts, xc, d, top, zc, sh)
        # duży śpiwór w poprzek na wierzchu plecaka (koc z modelu był za mały), dwa paski
        cx, z1 = bpy.data.objects["backpack"]["crown"]
        if os.path.exists(os.path.join(GEAR_SRC, GEAR_MODELS["bedroll"]["file"])):
            br = _import_gear(rig, "bedroll", ks)
            bv = [v.co for v in br.data.vertices]
            hz = (max(v.z for v in bv) - min(v.z for v in bv)) * 0.5
            br.data.transform(Matrix.Translation((cx, 0.0, z1 - 0.07 + hz * 0.8)))   # wciśnięty w klapę plecaka, przykrywa koc modelu
        else:
            r, ln = 0.085 * ks, 0.56 * ks
            zr = z1 - 0.035
            _part(rig, "bedroll", _cyl(r, ln, (cx, 0.0, zr), seg=20), "Spine2", "canvas")
            for yy in (-ln * 0.3, ln * 0.3):
                _part(rig, "bedroll_strap", _cyl(r + 0.005, 0.03, (cx, yy, zr), seg=20), "Spine2", "strap")
    if "backpack_bedroll" in gear:
        # plecak na łopatkach (Spine2), śpiwór zwinięty na górze, szelki przez barki na pierś
        top = neck.z - 0.07
        h, w, d = 0.42 * ks, 0.32 * ks, 0.18 * ks
        zc = top - h * 0.5
        back = _section(pts, zc, y_max=0.12)[0]
        xc = back - d * 0.5 + 0.01
        _part(rig, "backpack", _box((d, w, h), (xc, 0.0, zc), 0.035), "Spine2", "canvas_dark")
        xb = xc - d * 0.5                                       # tylna ściana plecaka
        # klapa: płat z góry na tył, do połowy wysokości
        _part(rig, "pack_lid", _box((d + 0.02, w + 0.01, 0.035), (xc - 0.005, 0.0, top + 0.005), 0.012), "Spine2", "leather")
        _part(rig, "pack_lid_back", _box((0.02, w + 0.01, h * 0.42), (xb - 0.008, 0.0, top - h * 0.21), 0.01), "Spine2", "leather")
        for yy in (-w * 0.28, w * 0.28):
            _part(rig, "pack_lid_strap", _box((0.012, 0.03, h * 0.62), (xb - 0.02, yy, top - h * 0.31), 0.003), "Spine2", "strap")
            _part(rig, "pack_buckle", _box((0.014, 0.042, 0.03), (xb - 0.026, yy, top - h * 0.58), 0.003), "Spine2", "metal")
        # kieszeń tylna z klapką
        _part(rig, "pack_pocket", _box((0.06, w * 0.62, h * 0.36), (xb - 0.03, 0.0, zc - h * 0.24), 0.02), "Spine2", "canvas_dark")
        _part(rig, "pack_pocket_flap", _box((0.068, w * 0.64, 0.05), (xb - 0.032, 0.0, zc - h * 0.08), 0.012), "Spine2", "leather")
        # kieszenie boczne i paski kompresyjne
        for side in (-1, 1):
            _part(rig, "pack_side", _box((d * 0.6, 0.05, h * 0.42), (xc - d * 0.1, side * (w * 0.5 + 0.022), zc - h * 0.12), 0.015),
                  "Spine2", "canvas_dark")
            for zz in (zc + h * 0.2, zc - h * 0.05):
                _part(rig, "pack_comp", _box((d * 0.9, 0.006, 0.025), (xc - 0.01, side * (w * 0.5 + 0.003), zz), 0.002), "Spine2", "strap")
        _part(rig, "bedroll", _cyl(0.075, 0.46, (xc + 0.01, 0.0, top + 0.06)), "Spine2", "canvas")
        for yy in (-0.13, 0.13):
            _part(rig, "bedroll_strap", _cyl(0.079, 0.025, (xc + 0.01, yy, top + 0.06)), "Spine2", "strap")
        _harness(rig, pts, xc, d, top, zc, sh)
    if "belt_pouches" in gear:
        zb = hips.z + 0.06
        x0, x1, y0, y1 = _section(pts, zb, dz=0.02, y_max=0.19)   # bez dłoni (poza A: dłonie wiszą przy biodrach)
        cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        _part(rig, "belt", _cyl(1.0, 0.045, (cx, cy, zb), axis="Z", caps=False, seg=24,
                                scale_xy=((x1 - x0) * 0.5 + 0.012, (y1 - y0) * 0.5 + 0.012)), "Hips", "strap")
        _part(rig, "buckle", _box((0.01, 0.055, 0.04), (x1 + 0.012, cy, zb), 0.004), "Hips", "metal")
        if _has("pouch") and _has("canteen"):
            # ładownice z przodu po bokach (przodem na zewnątrz), manierka z tyłu na lewym biodrze; wierzch na wysokości pasa
            for side in (-1, 1):
                o = _import_gear(rig, "pouch", ks)
                o.data.transform(Matrix.Rotation(math.radians(90.0), 4, "Z"))       # przodem do przodu postaci (+X)
                vs = [v.co for v in o.data.vertices]
                th = (max(v.x for v in vs) - min(v.x for v in vs)) * 0.5
                hz = (max(v.z for v in vs) - min(v.z for v in vs)) * 0.5
                yy = cy + side * 0.105 * ks                                          # po obu stronach klamry
                xf = _section(pts, zb - 0.03, dz=0.03, y_max=0.19)[1]
                o.data.transform(Matrix.Translation((xf + th - 0.012, yy, zb + 0.015 - hz)))
                o.name = "pouch_" + ("L" if side > 0 else "R")
            o = _import_gear(rig, "canteen", ks)
            vs = [v.co for v in o.data.vertices]
            th = (max(v.x for v in vs) - min(v.x for v in vs)) * 0.5
            hz = (max(v.z for v in vs) - min(v.z for v in vs)) * 0.5
            o.data.transform(Matrix.Translation((x0 - th + 0.015, y1 - 0.07, zb + 0.02 - hz)))
        else:
            for yy in (y0 + 0.05, y1 - 0.05):
                _part(rig, "pouch", _box((0.09, 0.055, 0.11), (cx + 0.04, yy, zb - 0.05), 0.012), "Hips", "olive")
            _part(rig, "canteen", _cyl(0.05, 0.16, (x0 - 0.02, y0 + 0.08, zb - 0.08), axis="Z"), "Hips", "olive")
    if "neckerchief" in gear:
        zn = neck.z - 0.01
        x0, x1, y0, y1 = _section(pts, zn, dz=0.02, y_max=0.12)
        cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        _part(rig, "neckerchief", _cyl(1.0, 0.06, (cx, cy, zn), axis="Z", caps=False, seg=20,
                                       scale_xy=((x1 - x0) * 0.5 + 0.008, (y1 - y0) * 0.5 + 0.008)), "Neck", "rust")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=3, radius1=0.07, radius2=0.0, depth=0.1)
        bmesh.ops.scale(bm, vec=Vector((0.25, 1.0, 1.0)), verts=bm.verts)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(180), 3, "X"))
        bmesh.ops.translate(bm, vec=Vector((x1 + 0.01, cy, zn - 0.07)), verts=bm.verts)
        _part(rig, "neckerchief_knot", bm, "Spine2", "rust")


# ------------------------------------------------------------------------------------------------ wypiekanie (Cycles)
# Ekwipunek dostaje tekstury z materiałów proceduralnych (płótno, skóra, metal), a ubrania i ekwipunek — cienie kontaktowe (AO:
# fałdy, kamizelka na kurtce, pasy na kombinezonie) i brud od dołu (błoto na nogawkach i butach). Wszystko trafia do tekstury koloru,
# więc gra nie potrzebuje nowych map ani zmian w shaderze.

GEAR_LOOK = {   # materiał ekwipunku → (skala szumu, siła zmian koloru, siła wypukłości, splot tkaniny)
    "leather": (40.0, 0.18, 0.35, False), "canvas": (60.0, 0.14, 0.25, True), "olive": (60.0, 0.14, 0.25, True),
    "strap": (90.0, 0.12, 0.2, True), "canvas_dark": (60.0, 0.16, 0.3, True), "tape": (70.0, 0.1, 0.15, False), "rust": (50.0, 0.15, 0.2, True), "metal": (25.0, 0.08, 0.1, False),
    "white": (45.0, 0.08, 0.2, True), "red": (45.0, 0.08, 0.1, False), "steel": (20.0, 0.10, 0.12, False),
}


def _cycles(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for t in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = t
            except TypeError:
                continue
            prefs.get_devices()
            if any(d.type == t for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == t
                sc.cycles.device = "GPU"
                break
    except KeyError:
        pass
    sc.cycles.samples = samples
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True


def _bake(**kw):
    try:
        bpy.ops.object.bake(**kw)
    except RuntimeError as e:
        if bpy.context.scene.cycles.device != "GPU":
            raise
        print("BAKE GPU failed, CPU:", e)
        bpy.context.scene.cycles.device = "CPU"
        bpy.ops.object.bake(**kw)


def _only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def _bake_target(o, img):
    """Węzeł obrazu `img` jako cel wypieku we wszystkich materiałach obiektu."""
    for m in o.data.materials:
        nt = m.node_tree
        n = nt.nodes.get("bake_target") or nt.nodes.new("ShaderNodeTexImage")
        n.name = "bake_target"
        n.image = img
        nt.nodes.active = n


def _drop_target(o):
    for m in o.data.materials:
        n = m.node_tree.nodes.get("bake_target")
        if n is not None:
            m.node_tree.nodes.remove(n)


def texture_gear(rig, size=1024):
    """Ekwipunek: UV, materiały proceduralne (szum koloru, splot, wypukłości) wypieczone do jednej pary map: kolor + normalne."""
    g = bpy.data.objects.get("gear")
    if g is None:
        return
    _only(g)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    for m in g.data.materials:
        key = m.name.replace("gear_", "").split(".")[0]
        sc_, var, bump, weave = GEAR_LOOK.get(key, (40.0, 0.1, 0.2, False))
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        base = tuple(bsdf.inputs["Base Color"].default_value)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = sc_ * 0.15
        noise.inputs["Detail"].default_value = 8.0
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = base
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (1 - var, 1 - var, 1 - var, 1)
        ramp.color_ramp.elements[1].color = (1 + var * 0.5, 1 + var * 0.5, 1 + var * 0.5, 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bp = nt.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = bump
        hsrc = noise.outputs["Fac"]
        if weave:
            wv = nt.nodes.new("ShaderNodeTexWave")
            wv.inputs["Scale"].default_value = sc_ * 2.5
            wv.inputs["Distortion"].default_value = 1.5
            nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
            add = nt.nodes.new("ShaderNodeMath")
            add.operation = "ADD"
            nt.links.new(noise.outputs["Fac"], add.inputs[0])
            nt.links.new(wv.outputs["Fac"], add.inputs[1])
            hsrc = add.outputs["Value"]
        nt.links.new(hsrc, bp.inputs["Height"])
        nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    alb = bpy.data.images.new("gear_albedo", size, size)
    nrm = bpy.data.images.new("gear_normal", size, size)
    nrm.colorspace_settings.name = "Non-Color"
    sc = bpy.context.scene
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    _bake_target(g, alb)
    _bake(type="DIFFUSE", pass_filter={"COLOR"})
    _bake_target(g, nrm)
    _bake(type="NORMAL")
    _drop_target(g)
    # jeden materiał z wypieczonych map
    mat = bpy.data.materials.new("gear")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.75
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.name = "diffuseTexture"
    ti.image = alb
    nt.links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nrm
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    g.data.materials.clear()
    g.data.materials.append(mat)
    print("GEAR TEX", size)


def bake_shading(rig, body, size_cap=2048):
    """Cienie kontaktowe i brud od dołu wypieczone w kolor każdej części (ubrania, buty, rękawice, hełm, maska, ekwipunek)."""
    sc = bpy.context.scene
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.cycles.ao_bounces_render = 0
    sc.world.light_settings.distance = 0.12            # AO na odległość fałdy, nie całej sylwetki
    for o in [o for o in rig.children if o.type == "MESH"]:
        if o == body or o.name in ("low-poly",) or o.name.startswith("eyebrow") or o.name.startswith("eyelash"):
            continue
        img = obj_images(o).get("diffuseTexture")
        if img is None or not o.data.uv_layers:
            continue
        w, h = min(img.size[0], size_cap), min(img.size[1], size_cap)
        if (w, h) != tuple(img.size):
            img.scale(w, h)
        ao = bpy.data.images.new("ao_" + o.name, w, h)
        ao.colorspace_settings.name = "Non-Color"
        _only(o)
        _bake_target(o, ao)
        _bake(type="AO")
        # wysokość nad ziemią na teksel: tymczasowa emisja współrzędnej z
        hz = bpy.data.images.new("hz_" + o.name, w, h, float_buffer=True)
        hz.colorspace_settings.name = "Non-Color"
        saved = [m for m in o.data.materials]
        tmp = bpy.data.materials.new("hz_tmp")
        tmp.use_nodes = True
        tnt = tmp.node_tree
        for n in list(tnt.nodes):
            if n.type == "BSDF_PRINCIPLED":
                tnt.nodes.remove(n)
        geo = tnt.nodes.new("ShaderNodeNewGeometry")
        sep = tnt.nodes.new("ShaderNodeSeparateXYZ")
        em = tnt.nodes.new("ShaderNodeEmission")
        out = next(n for n in tnt.nodes if n.type == "OUTPUT_MATERIAL")
        tnt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
        tnt.links.new(sep.outputs["Z"], em.inputs["Color"])
        tnt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        tn = tnt.nodes.new("ShaderNodeTexImage")
        tn.image = hz
        tnt.nodes.active = tn
        for i in range(len(o.data.materials)):
            o.data.materials[i] = tmp
        _bake(type="EMIT")
        for i, m in enumerate(saved):
            o.data.materials[i] = m
        _drop_target(o)
        a = np.array(ao.pixels[:], dtype=np.float32).reshape(-1, 4)[:, 0]
        z = np.array(hz.pixels[:], dtype=np.float32).reshape(-1, 4)[:, 0]
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        shade = 0.45 + 0.55 * np.clip(a, 0, 1) ** 1.3
        f = smooth_noise(h, w, 24, len(o.name)).ravel()
        dirt = np.clip((0.55 - z) / 0.5, 0, 1) * (0.35 + 0.65 * f)        # błoto: najwięcej przy stopach, plamami
        dirt = np.where(z > -5, dirt, 0)                                     # teksele bez geometrii (tło atlasu) bez zmian
        mud = np.array([0.20, 0.16, 0.11], dtype=np.float32)
        rgb = px[:, :3] * shade[:, None]
        rgb = rgb * (1 - 0.55 * dirt[:, None]) + mud[None, :] * (0.55 * dirt[:, None])
        px[:, :3] = np.clip(rgb, 0, 1)
        img.pixels[:] = px.ravel()
        print("BAKED", o.name, w, "x", h)


def add_sewn(rig, body, spec):
    """Ubrania szyte symulacją (cloth_jacket.py): import GLB, wagi kości z ciała (najbliższa ściana, interpolacja), Armature.
    Część kompletu MPFB, którą zastępują, traci górną połowę (ściany przypięte głównie do kości tułowia i rąk)."""
    masks = [m for m in body.modifiers if m.type == "MASK"]
    for m in masks:                                   # wagi z całego ciała, także spod ubrań
        m.show_viewport = False
    for key, conf in spec.get("sewn", {}).items():
        src = os.path.join(CLOTH_SRC, conf["file"])
        if not os.path.exists(src):
            print("SEWN missing", src)
            continue
        old = bpy.data.objects.get(conf.get("replaces", ""))
        if old is not None:
            names = {g.index: g.name for g in old.vertex_groups}
            bm = bmesh.new()
            bm.from_mesh(old.data)
            dl = bm.verts.layers.deform.active
            upper = set()
            for v in bm.verts:
                w = {names[g]: x for g, x in v[dl].items()} if dl else {}
                up = sum(x for n, x in w.items() if any(u in n for u in UPPER))
                if up > 0.5 * max(sum(w.values()), 1e-6):
                    upper.add(v)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if sum(v in upper for v in f.verts) * 2 > len(f.verts)], context="FACES")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            bm.to_mesh(old.data)
            bm.free()
            print("SEWN cut", old.name, "upper verts", len(upper))
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=src)
        ob = next(o for o in set(bpy.data.objects) - before if o.type == "MESH")
        for o in set(bpy.data.objects) - before - {ob}:
            bpy.data.objects.remove(o)
        ob.name = key
        ob.parent = rig
        ob.matrix_parent_inverse.identity()
        for m in ob.data.materials:                   # kolor pod nazwą węzła jak w MPFB (bake_shading dopieka na nim cienie)
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links):
                    n.name = "diffuseTexture"
        _only(ob)
        dt = ob.modifiers.new("dt", "DATA_TRANSFER")
        dt.object = body
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        dt.layers_vgroup_select_src = "ALL"
        dt.layers_vgroup_select_dst = "NAME"
        bpy.ops.object.datalayout_transfer(modifier=dt.name)
        bpy.ops.object.modifier_apply(modifier=dt.name)
        for g in [g for g in ob.vertex_groups if not g.name.startswith("mixamorig:")]:
            ob.vertex_groups.remove(g)
        am = ob.modifiers.new("Armature", "ARMATURE")
        am.object = rig
        print("SEWN", key, len(ob.data.vertices), "verts", len(ob.vertex_groups), "groups")
    for m in masks:
        m.show_viewport = True


def build(name, spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    ph = info["phenotype"]
    ph.update(spec["phenotype"])
    ph["gender"] = 1.0 if spec["sex"] == "male" else 0.0          # MPFB: 1 = mężczyzna, 0 = kobieta
    ph["race"] = dict(spec["race"])
    info["rig"] = "mixamo"
    info["eyes"] = "low-poly/low-poly.mhclo"
    info["eyebrows"] = "%s/%s.mhclo" % (spec["eyebrows"], spec["eyebrows"]) if spec.get("eyebrows") else ""
    info["hair"] = "%s/%s.mhclo" % (spec["hair"], spec["hair"]) if spec.get("hair") else ""
    info["clothes"] = ["%s/%s.mhclo" % (c, c) for c in spec["clothes"]]
    info["skin_mhmat"] = "%s/%s.mhmat" % (spec["skin"], spec["skin"])
    info["skin_material_type"] = "MAKESKIN"
    info["alternative_materials"] = {}
    st = HumanService.get_default_deserialization_settings()
    st["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, st)
    rig = body.parent
    rig.name = name
    body.name = "body"

    # przebarwienia ubrań
    for o in list(rig.children):
        if o.type != "MESH" or o == body:
            continue
        key = o.name.split(".", 1)[-1]
        o.name = key
        conf = spec["clothes"].get(key, {})
        if not any(o.data.materials):
            ensure_material(o, key)
        img = obj_images(o).get("diffuseTexture")
        if img is not None:
            if conf.get("recolor"):
                recolor_image(img, conf["recolor"])
            if "tint" in conf:
                tint_image(img, conf["tint"])
        elif "tint" in conf:                                         # część bez tekstury (np. czapka): sam kolor materiału
            for m in o.data.materials:
                for n in m.node_tree.nodes:
                    if n.type == "BSDF_PRINCIPLED":
                        for lk in list(n.inputs["Base Color"].links):
                            m.node_tree.links.remove(lk)
                        n.inputs["Base Color"].default_value = tuple(conf["tint"]) + (1.0,)

    if SEWN:
        add_sewn(rig, body, spec)

    # ciało: zapiecz klucze kształtu (cele fenotypu), zastosuj maski (pomocnicze bryły MPFB, ciało pod ubraniami), uprość
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    if body.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    # wzrost ciała mierzony przed ukryciem stóp pod butami (grupa „body” bez brył pomocniczych)
    gi = body.vertex_groups["body"].index
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    k = spec["height"] / (max(zs) - min(zs))
    floor = min(zs)
    arm_mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    body.modifiers.remove(arm_mod)
    moved = [k for k, c in spec["clothes"].items() if c.get("relocate")]
    for m in [m for m in body.modifiers if m.type == "MASK"]:
        if any(m.name == "Delete." + k for k in moved):
            body.modifiers.remove(m)
            continue
        bpy.ops.object.modifier_apply(modifier=m.name)
    am = body.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    # upraszczanie (wagi kości zostają); Decimate przesuwamy przed Armature, żeby liczył geometrię spoczynkową
    for o in [o for o in rig.children if o.type == "MESH"]:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        conf = spec["clothes"].get(o.name) or spec.get("sewn", {}).get(o.name, {})
        budget = BODY_TRIS if o == body else int(conf.get("tris", PART_TRIS))
        if tris <= budget:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        dec = o.modifiers.new("dec", "DECIMATE")
        dec.ratio = budget / tris
        while o.modifiers[0] != dec:
            bpy.ops.object.modifier_move_up(modifier=dec.name)
        bpy.ops.object.modifier_apply(modifier=dec.name)

    # orientacja (przód −Y → +X), wzrost ciała, stopy na z = 0
    rig.location.z -= floor
    rig.rotation_euler = (0.0, 0.0, math.radians(90.0))
    rig.scale = (k, k, k)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig] + list(rig.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    zs = [(o.matrix_world @ v.co).z for o in rig.children if o.type == "MESH" for v in o.data.vertices]
    print("HEIGHT body %.3f (x%.3f), all meshes %.3f..%.3f" % (spec["height"], k, min(zs), max(zs)))
    for k, c in spec["clothes"].items():
        if c.get("relocate"):
            relocate(rig, bpy.data.objects[k], c["relocate"])
    add_gear(rig, spec.get("gear", []))
    _cycles(SAMPLES)
    texture_gear(rig)
    bake_shading(rig, body, BAKE_TEX)

    # tekstury i metaliczność; w GLB tekstury idą jako WebP (z przezroczystością, kilka razy mniejsze niż PNG)
    cloth = {img.name for o in rig.children if o.type == "MESH" and o != body for img in obj_images(o).values()}
    for img in list(bpy.data.images):
        cap = CLOTH_TEX if img.name in cloth else TEX
        if img.size[0] > cap or img.size[1] > cap:
            img.scale(min(cap, img.size[0]), min(cap, img.size[1]))
    for m in bpy.data.materials:
        if m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    n.inputs["Metallic"].default_value = 0.0

    per = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in rig.children if o.type == "MESH"}
    print("TRIS", sum(per.values()), per, "BONES", len(rig.data.bones), "MESHES", [o.name for o in rig.children if o.type == "MESH"])

    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="WEBP", export_image_quality=88,
                              export_animations=False, export_apply=False, export_morph=False)
    print("OK", dst)


names = list(OUTFITS) if "--all" in argv else [a for a in argv if not a.startswith("--")]
for n in names:
    build(n, OUTFITS[n])
