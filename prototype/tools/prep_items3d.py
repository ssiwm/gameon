"""Modele 3D przedmiotów i rekwizytów dla widoku 3D gry (`view3d.gd`): prawdziwe bryły zamiast kart ze sprite'em.

Uruchomienie (z korzenia repo, Blender w PATH):
    python prototype/tools/prep_items3d.py [--only=shelf,stash,rock] [--tex=1024]
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/prep_items3d.py -- [--only=...] [--tex=1024]

Dwa źródła:
  * proceduralne bryły z `concept/items_proc_bake.py` (te same, z których powstają sprite'y HD): siatki są łączone, rozwijane (Smart UV),
    a materiały węzłowe wypalane w Cycles do tekstur — kolor, mapa normalnych w przestrzeni stycznej, ORM (okluzja, chropowatość, metal), emisja;
  * modele z Tripo (`art_src/world/tripo/*.glb`: warsztat, złom, kłody, płot, skrzynia, beczka, szafka, stół, prycza, generator,
    skrytka, stojak, krzesło, worek, apteczka, amunicja, torba, flary, granaty, stołek, kości): obrót czołem do kamery gry, uproszczenie siatki,
    zmniejszenie tekstur;
  * skany z Poly Haven (CC0, `art_src/world/polyhaven/*.glb` z `tools/polyhaven_fetch.py`): kamienie, pnie, radiostacja, regał i dekoracje map.
Wynik: prototype/art/items3d/<nazwa>.glb. Jednostka modelu = 1 piksel świata gry, początek układu w stopach (środek szerokości, z = 0),
front bryły w stronę −Y Blendera (= +Z w Godocie, ku kamerze gry) — dokładnie tak, jak sprite z `ItemsHd.make` leży względem swojego węzła.
"""
import math
import os
import subprocess
import tempfile
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "prototype", "art", "items3d")
TRIPO = os.path.join(ROOT, "art_src", "world", "tripo")

# modele z Tripo: nazwa → (plik, strona kamery jak w tools/build_items.sh / wypieku rekwizytów świata, szerokość w pikselach świata, trójkąty)
TRIPO_MODELS = {
    "workshop": ("workshop.glb", "+X", 30.0, 14000),
    "scrap_pile": ("scrap_pile.glb", "+X", 14.0, 6000),
    "logs": ("logs.glb", "-Y", 18.0, 6000),
    "fence": ("fence.glb", "-Y", 20.0, 6000),
    # meble i sprzęt (Tripo, 2026-10-11): szerokość i wysokość jak bryła sprite'a w art/items/items.json — model mieści się w tej ramce
    "crate": ("crate.glb", "+X", 14.0, 8000, 14.0, True),      # True: wypełnia ramkę dokładnie (kształt kolizji 14×14 — na skrzyni się stoi)
    "barrel": ("barrel.glb", "+X", 10.0, 6000, 15.0, True),
    "locker": ("locker.glb", "+X", 13.0, 6000, 31.0),
    "table": ("table.glb", "-Y", 40.0, 10000, 19.0),
    "cot": ("cot.glb", "-Y", 36.0, 8000, 13.0),
    "generator": ("generator.glb", "-Y", 35.5, 14000, 25.8),
    "cache": ("cache.glb", "+X", 19.6, 8000, 12.5),
    "rack": ("rack.glb", "+X", 48.0, 8000, 36.2),
    "chair": ("chair.glb", "+X", 9.5, 6000, 18.0),
    "stash": ("stash.glb", "+X", 10.8, 6000, 11.7),
    # pickupy i drobne rekwizyty (Tripo, druga partia)
    "medkit": ("medkit.glb", "+X", 16.7, 4000, 10.4),
    "ammo": ("ammo.glb", "+X", 10.4, 4000, 8.6),
    "supply": ("supply.glb", "+X", 16.8, 5000, 10.5),
    "flare_box": ("flare_box.glb", "+X", 14.4, 5000, 12.8),
    "frag": ("frag.glb", "+X", 5.8, 3000, 7.2),
    "phos": ("phos.glb", "+X", 5.6, 3000, 11.6),
    "smoke": ("smoke.glb", "+X", 5.6, 3000, 11.6),
    "stool": ("stool.glb", "-Y", 9.6, 5000, 10.5),
    "bones": ("bones.glb", "-Y", 17.7, 5000, 8.0),
    "flare": ("flare.glb", "-Y", 3.4, 2000, 15.8),
    # trzecia partia: tablice, lampa, sprzęt z diodami, strzelnica, drezyna (korpus + osobno koło i dźwignia)
    "handcar": ("handcar.glb", "-Y", 92.4, 12000),             # kształt dopasowuje reshape_handcar (bez kół, pokład na wysokości stóp)
    "handcar_wheel": ("handcar_wheel.glb", "+X", 6.8, 4000, 6.8, True),
    "handcar_lever": ("handcar_lever.glb", "+X", 46.0, 4000, 8.0),
    "board": ("board.glb", "+X", 60.0, 5000, 40.0),
    "results_board": ("results_board.glb", "+X", 116.0, 5000, 66.0, True, 5.0),
    "lamp": ("lamp.glb", "-Y", 9.5, 4000, 11.7),
    "mine": ("mine.glb", "+X", 15.7, 4000, 9.4),
    "charge": ("charge.glb", "+X", 13.0, 4000, 8.5),
    "defib": ("defib.glb", "+X", 17.3, 5000, 10.3),
    "scanner": ("scanner.glb", "+X", 9.6, 4000, 14.9),
    "range_target": ("range_target.glb", "+X", 16.0, 5000, 35.0),
    "range_sign": ("range_sign.glb", "+X", 34.0, 4000, 34.5),
    "tag": ("tag.glb", "+X", 6.8, 3000, 8.7),
    # czwarta partia: reszta przedmiotów + radiostacja; drzewa, kłoda i słup mają wysokość / długość 100 jednostek (skalę nadaje gra)
    "tools_wall": ("tools_wall.glb", "+X", 30.0, 9000, 26.0),
    "padlock": ("padlock.glb", "+X", 4.4, 3000, 6.2),
    "flare_stuck": ("flare_stuck.glb", "-Y", 9.1, 3000, 16.0),   # flara wyjścia wbita w ziemię
    "rubble": ("rubble.glb", "-Y", 26.0, 4000, 8.0),             # gruz po rozbitym zamurowanym przejściu
    # szczątki (lokalnie: SDXL → TRELLIS 2 przez tools/comfy_gen.py, źródła w art_src/gibs/): największy wymiar poziomy = 100 jednostek,
    # skalę nadaje gra (`view3d.gd: mirror_gib`)
    "gib_meat_b": ("../../gibs/meat_b.glb", "-Y", 100.0, 1200, 1000.0),
    "gib_meat_c": ("../../gibs/meat_c.glb", "-Y", 100.0, 1200, 1000.0),
    "gib_gut_a": ("../../gibs/gut_a.glb", "-Y", 100.0, 1500, 1000.0),
    "gib_bone_a": ("../../gibs/bone_a.glb", "-Y", 100.0, 1000, 1000.0),
    "gib_bone_b": ("../../gibs/bone_b.glb", "-Y", 100.0, 1000, 1000.0),            # kłódka zablokowanej broni na stojaku
    "stake": ("stake.glb", "+X", 4.0, 2500, 8.9),
    "tree_snag": ("tree_snag.glb", "+X", 1000.0, 2500, 100.0),
    # wersja szczegółowa dla najbliższego rzędu lasu
    "tree_snag_hi": ("tree_snag.glb", "+X", 1000.0, 7000, 100.0),
    "post": ("post.glb", "-Y", 1000.0, 1500, 100.0),
    # kładki: odcinek o długości 100 jednostek (x), góra pokładu = góra bryły; gra układa odcinki jeden za drugim (`Level3D.build_level`).
    # Deski leżą w poprzek kładki, więc łączenia odcinków wypadają w szczelinach między deskami; krata ma ramę — łączenie to styk paneli.
    "walkway_plank": ("walkway_plank.glb", "+X", 100.0, 5000, 17.6, True, 99.0),
    "walkway_grate": ("walkway_grate.glb", "-Y", 100.0, 6000, 8.0, True, 33.0),
    # Poly Haven (CC0, skany; źródła pobiera tools/polyhaven_fetch.py do art_src/world/polyhaven/). Front modeli Poly Haven leży na −Y Blendera.
    # Zamienniki modeli z Tripo — te same nazwy, ramki i skale w grze:
    "tree_log": ("../polyhaven/dead_tree_trunk.glb", "-Y", 100.0, 6000, 1000.0),
    "rock": ("../polyhaven/rock_moss_set_01__rock01.glb", "-Y", 14.0, 3000, 9.0),
    "radio_set": (["../polyhaven/metal_office_desk.glb", "../polyhaven/vintage_radio_transceiver.glb"], "-Y", 43.9, 10000),   # radio na biurku: 1,8 m w skali gry 0,5
    "shelf": ("../polyhaven/steel_frame_shelves_01.glb", "-Y", 31.8, 4400, 29.5),        # 1,93 m w skali gry 0,8 (granica 2,0 w test_proportions)
    # nowe dekoracje mapy (view3d.gd: DECO_MODELS) w naturalnej skali: szerokość w px świata = metry / 0,082
    "rock_b": ("../polyhaven/rock_moss_set_01__rock04.glb", "-Y", 14.0, 3000, 9.0),
    "rock_c": ("../polyhaven/rock_moss_set_01__rock05.glb", "-Y", 14.0, 3000, 9.0),
    "fire_pit": ("../polyhaven/stone_fire_pit.glb", "-Y", 17.7, 3900),
    "stump": ("../polyhaven/tree_stump_01.glb", "-Y", 17.4, 5000),
    "trunk_big": ("../polyhaven/dead_tree_trunk_02.glb", "-Y", 49.4, 7000),
    "barrel_stove": ("../polyhaven/barrel_stove.glb", "-Y", 7.3, 5000),
    "mil_crate": ("../polyhaven/wooden_military_crate.glb", "-Y", 15.1, 6000),
    "tyre": ("../polyhaven/old_tyre.glb", "-Y", 7.3, 2000),
    "barrier": ("../polyhaven/concrete_road_barrier_02.glb", "-Y", 19.1, 4000),
}
# modele z Tripo ze świecącymi elementami (diody, ekrany, żarówka): emisja = jasne, nasycone piksele koloru (żarówka: jasne, blade)
EMISSIVE = {"mine": "led", "charge": "led", "defib": "led", "scanner": "led", "lamp": "bulb", "stake": "led"}
# przedmioty proceduralne o większej teksturze (duże bryły blisko kamery)
BIG = {"generator", "handcar", "shelf", "locker", "table", "cot", "results_board", "board", "rack", "tools_wall"}

if "bpy" not in sys.modules and not any(a.endswith("blender") or a.endswith("blender.exe") for a in sys.argv[:1]):
    try:
        import bpy  # noqa: F401
    except ImportError:
        # uruchomione zwykłym Pythonem: odpal Blendera z tym samym skryptem
        os.makedirs(OUT, exist_ok=True)
        r = subprocess.run(["blender", "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--"] + sys.argv[1:])
        sys.exit(r.returncode)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set()
TEX = 1024
for a in argv:
    if a.startswith("--only="):
        ONLY = set(a[7:].split(","))
    elif a.startswith("--tex="):
        TEX = int(a[6:])
os.makedirs(OUT, exist_ok=True)


def want(name):
    return not ONLY or name in ONLY


def export_glb(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="AUTO" if name.startswith("tree_spruce") else "JPEG", export_jpeg_quality=88, export_animations=False)
    print("SAVED", name, os.path.getsize(path) // 1024, "kB", len(obj.data.polygons), "faces")


# ------------------------------------------------------------------ bryły proceduralne

def load_proc():
    """Wykonuje definicje z items_proc_bake.py (materiały, bryły, MODELS) bez jego pętli renderu."""
    src = open(os.path.join(HERE, "concept", "items_proc_bake.py"), encoding="utf-8").read()
    src = src[:src.index("# ---------------------------------------------------------------- render")]
    old = sys.argv
    sys.argv = ["x", "--", os.path.join(tempfile.gettempdir(), "items3d_tmp")]
    ns = {"__name__": "items_proc"}
    exec(compile(src, "items_proc_bake.py", "exec"), ns)
    sys.argv = old
    base_mat = ns["mat"]

    def mat(name, col, kind="solid", rough=0.55, metal=0.0, **kw):          # zapamiętujemy chropowatość i metal (węzły ich nie niosą)
        m = base_mat(name, col, kind, rough, metal, **kw)
        m["rough"] = rough
        m["metal"] = metal if kind != "metal" else max(metal, 0.85)
        m["emits"] = kw.get("emit") is not None
        return m
    ns["mat"] = mat
    return ns


def bake_image(name, colorspace="sRGB", fill=(0, 0, 0, 1), size=TEX):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    img.generated_color = fill
    return img


def bake_pass(obj, img, kind):
    """Wypala przebieg na teksturę `img`: każdy materiał dostaje aktywny węzeł obrazu jako cel."""
    for m in obj.data.materials:
        nt = m.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        for n in nt.nodes:
            n.select = False
        node.select = True
        nt.nodes.active = node
    sc = bpy.context.scene
    sc.cycles.samples = 24 if kind == "AO" else 6
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="NORMAL" if kind == "NORMAL" else "EMIT", margin=6, use_clear=True)


def build_proc(ns, name, builder):
    sc = bpy.context.scene
    ns["clear"]()
    for m in list(bpy.data.materials):                       # świeża paleta dla każdego modelu: wypiek przepina węzły materiałów na stałe
        bpy.data.materials.remove(m)
    P = ns["P"] = ns["palette"]()
    builder(P)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    # wszystkie części (siatki z modyfikatorami, krzywe) → jedna siatka
    parts = []
    for ob in ns["OBJS"]:
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(ob.matrix_world)
        new = bpy.data.objects.new(ob.name + "_m", me)
        sc.collection.objects.link(new)
        parts.append(new)
    if not parts:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    ns["clear"]()
    me = obj.data
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    me.transform(Matrix.Translation((-(lo[0] + hi[0]) * 0.5, 0.0, -lo[2])))      # stopy w z = 0, środek szerokości w x = 0 (jak ramka sprite'a)
    for p in me.polygons:
        p.use_smooth = True
    # rozwinięcie UV
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.012)
    bpy.ops.object.mode_set(mode="OBJECT")
    size = TEX * 2 if name in BIG else TEX
    mats = [m for m in me.materials if m is not None]
    set_pass = ns["set_pass"]
    # kolor
    alb = bake_image(name + "_alb", size=size)
    for m in mats:
        set_pass(m, "alb")
    bake_pass(obj, alb, "EMIT")
    # okluzja
    ao = bake_image(name + "_ao", "Non-Color", (1, 1, 1, 1), size)
    for m in mats:
        set_pass(m, "ao")
    bake_pass(obj, ao, "AO")
    # chropowatość / metal jako stałe na materiał
    rm = bake_image(name + "_rm", "Non-Color", size=size)
    emit_any = False
    for m in mats:
        nt = m.node_tree
        pas = nt.nodes[m["pass_nodes"]["pas"]]
        for l in list(nt.links):
            if l.to_node == pas:
                nt.links.remove(l)
        pas.inputs["Color"].default_value = (1.0, float(m.get("rough", 0.6)), float(m.get("metal", 0.0)), 1.0)
        emit_any = emit_any or bool(m.get("emits", False))
    bake_pass(obj, rm, "EMIT")
    # emisja (diody, ekrany, żarówka)
    emi = None
    if emit_any:
        emi = bake_image(name + "_emi", size=size)
        for m in mats:
            set_pass(m, "emi")
        bake_pass(obj, emi, "EMIT")
    # normalne w przestrzeni stycznej: tymczasowy Principled z wyjściem węzła Bump
    nrm = bake_image(name + "_nrm", "Non-Color", (0.5, 0.5, 1, 1), size)
    for m in mats:
        nt = m.node_tree
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bump = next((n for n in nt.nodes if n.type == "BUMP"), None)
        if bump is not None:
            nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bake_pass(obj, nrm, "NORMAL")
    # ORM = (AO, rough, metal); okluzja także lekko w kolorze (styki części ciemniejsze)
    n = size * size
    a_ao = np.array(ao.pixels[:]).reshape(n, 4)
    a_rm = np.array(rm.pixels[:]).reshape(n, 4)
    a_alb = np.array(alb.pixels[:]).reshape(n, 4)
    occ = np.clip(a_ao[:, 0], 0.0, 1.0)
    a_alb[:, :3] *= (0.55 + 0.45 * occ)[:, None]
    alb.pixels[:] = a_alb.reshape(-1).tolist()
    orm = bake_image(name + "_orm", "Non-Color", size=size)
    a_orm = np.ones((n, 4))
    a_orm[:, 0] = occ
    a_orm[:, 1] = a_rm[:, 1]
    a_orm[:, 2] = a_rm[:, 2]
    orm.pixels[:] = a_orm.reshape(-1).tolist()
    # materiał wynikowy
    fm = bpy.data.materials.new(name)
    fm.use_nodes = True
    nt = fm.node_tree
    bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")

    def tex(img):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        return t
    nt.links.new(tex(alb).outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex(orm).outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex(nrm).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emi is not None:
        nt.links.new(tex(emi).outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    me.materials.clear()
    me.materials.append(fm)
    for p in me.polygons:
        p.material_index = 0
    export_glb(obj, name)
    bpy.data.objects.remove(obj, do_unlink=True)
    for img in (alb, ao, rm, nrm, orm) + ((emi,) if emi is not None else ()):
        bpy.data.images.remove(img)
    return True


# ------------------------------------------------------------------ modele z Tripo

def reshape_handcar(obj):
    """Korpus drezyny z Tripo → kształt, którego wymaga gra (`handcar.gd`): bez własnych kół (koła i dźwignia to osobne, animowane modele),
    pokład o grubości 3,35 px (góra pokładu = stopy graczy, 5,35 px nad torem przy korpusie 2 px nad torem), słup latarni skrócony przez
    usunięcie środkowego odcinka pręta (latarnia zostaje nieściśnięta). Liczby to ułamki wysokości modelu źródłowego (pomiar przekrojów)."""
    import bmesh
    me = obj.data
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    H = hi[2] - lo[2]
    px = 92.4 / (hi[0] - lo[0])                               # pikseli świata na jednostkę modelu (szerokość pokładu jak sprite)
    z_cut = lo[2] + 0.111 * H                                 # poniżej: koła, osie, belka ramy i wsporniki resorów (nadkola)
    z_deck = lo[2] + 0.167 * H                                # góra pokładu
    z_p0, z_p1 = lo[2] + 0.333 * H, lo[2] + 0.733 * H         # usuwany odcinek pręta latarni
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z_cut], context="VERTS")
    z_bot = lo[2] + 0.1155 * H                                # spód desek pokładu: strzępy ramy tuż pod nim spłaszczamy do tej płaszczyzny
    xc, xh = (lo[0] + hi[0]) * 0.5, (hi[0] - lo[0]) * 0.5
    top = [v.co.x for v in bm.verts if z_deck - 0.012 * H < v.co.z <= z_deck]          # zasięg desek pokładu w x
    x_a, x_b = min(top) - 0.004 * xh, max(top) + 0.004 * xh
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z_deck and not (x_a <= v.co.x <= x_b)], context="VERTS")      # zderzaki za końcami pokładu
    for v in bm.verts:
        if v.co.z < z_bot:
            v.co.z = z_bot
    z_cut = z_bot
    deck_k = 3.35 / ((z_deck - z_cut) * px)
    for v in bm.verts:
        z = v.co.z
        if z <= z_deck:
            nz = (z - z_cut) * deck_k
        else:
            zz = min(z, z_p0) + max(z - z_p1, 0.0)             # pręt między z_p0 a z_p1 zapada się do z_p0
            nz = (z_deck - z_cut) * deck_k + (zz - z_deck)
        v.co.z = nz
        v.co.y *= 0.62                                         # płytszy pokład (ok. 14 px)
    bm.to_mesh(me)
    bm.free()
    me.update()


# świerki: pień z modelu Tripo (martwy pień — kora) + gałęzie z igliwiem jako karty z teksturą (art/world3d/forest/bough_*.png z
# tools/world_forest_gen.py) rozłożone piętrami wokół pnia. Sam generator 3D robi z igliwia szerokie liście; igły muszą być teksturą.
SPRUCES = {"tree_spruce_a": (11, 1.0, 0.16), "tree_spruce_b": (23, 0.72, 0.34), "tree_spruce_c": (37, 0.9, 0.06)}      # ziarno, pełność, goły dół pnia


def build_spruce(name, seed, fullness, bare):
    import bmesh
    import random
    src = os.path.join(TRIPO, "tree_snag.glb")
    if not os.path.exists(src):
        print("SKIP", name)
        return
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    trunk = next(o for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.object.select_all(action="DESELECT")
    trunk.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = trunk.data
    me.transform(Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z"))
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    me.transform(Matrix.Translation((-(lo[0] + hi[0]) * 0.5, -(lo[1] + hi[1]) * 0.5, -lo[2])))
    kz = 100.0 / (hi[2] - lo[2])
    kxy = 9.0 / max(hi[0] - lo[0], hi[1] - lo[1])                # smukły pień (konary martwego pnia zostają jako suche gałęzie w koronie)
    me.transform(Matrix.Diagonal((kxy, kxy, kz, 1.0)))
    for v in me.vertices:                                      # zbieżność ku wierzchołkowi
        f = 1.0 - 0.8 * (v.co.z / 100.0)
        v.co.x *= f
        v.co.y *= f
    dec = trunk.modifiers.new("dec", "DECIMATE")
    dec.ratio = 1800.0 / max(len(me.polygons), 1)
    bpy.ops.object.modifier_apply(modifier="dec")
    for img in bpy.data.images:
        if img.size[0] > 512:
            img.scale(512, 512)
    for m in bpy.data.materials:
        if m.node_tree:
            bs = next((nd for nd in m.node_tree.nodes if nd.type == "BSDF_PRINCIPLED"), None)
            if bs is not None:
                bs.inputs["Metallic"].default_value = 0.0
    # materiały igliwia
    mats = []
    for key in ("bough_side", "bough_top"):
        m = bpy.data.materials.new(key)
        m.use_nodes = True
        nt = m.node_tree
        bs = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(ROOT, "prototype", "art", "world3d", "forest", key + ".png"))
        nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
        nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
        bs.inputs["Roughness"].default_value = 1.0
        m.blend_method = "CLIP"
        m.use_backface_culling = False
        me.materials.append(m)
        mats.append(len(me.materials) - 1)
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()

    def quad(p0, du, dv, mat, v0=0.0, v1=1.0):
        """Czworokąt: p0 = nasada (u = 0, v = v0), du = wektor wzdłuż gałęzi, dv = wektor wysokości / szerokości tekstury."""
        vv = [bm.verts.new(p0), bm.verts.new(p0 + du), bm.verts.new(p0 + du + dv), bm.verts.new(p0 + dv)]
        f = bm.faces.new(vv)
        f.material_index = mat
        for lp, (a, b) in zip(f.loops, ((0, v0), (1, v0), (1, v1), (0, v1))):
            lp[uv].uv = (a, b)

    from mathutils import Vector as V
    tiers = 30
    z0 = 100.0 * bare
    for k in range(tiers):
        t = k / (tiers - 1)
        z = z0 + (98.0 - z0) * t
        L = (2.0 + 16.0 * (1.0 - t) ** 0.85) * fullness + 2.0
        n = 7 if t < 0.8 else 5
        base_phi = rng.uniform(0, math.tau)
        for i in range(n):
            if rng.random() < 0.07:
                continue                                           # przerwa po złamanej gałęzi
            phi = base_phi + math.tau * i / n + rng.uniform(-0.25, 0.25)
            ln = L * rng.uniform(0.75, 1.1)
            droop = math.radians(rng.uniform(8, 22) * (1.0 - 0.6 * t))
            r = V((math.cos(phi), math.sin(phi), 0.0))
            tan = V((-r.y, r.x, 0.0))
            up = V((0, 0, 1))
            root = r * (1.2 * (1.0 - t) + 0.2) + up * (z + rng.uniform(-1.2, 1.2))
            d = (r * math.cos(droop) - up * math.sin(droop)) * ln
            # profil z boku: tekstura 2:1, nasada na 0,84 wysokości
            hq = ln * 0.5
            vdir = (up * math.cos(droop) + r * math.sin(droop)) * hq
            quad(root - vdir * 0.84, d, vdir, mats[0])
            # wachlarz z góry (lekko skręcony), szerokość = połowa długości
            wv = (tan * math.cos(0.25) + up * math.sin(0.25) * rng.choice((-1, 1))) * (ln * 0.5)
            quad(root - wv * 0.5 - up * 0.3, d, wv, mats[1])
    for i in range(5):                                         # czubek: krótkie gałązki ku górze
        phi = math.tau * i / 5
        r = V((math.cos(phi), math.sin(phi), 0.0))
        d = (r * 0.45 + V((0, 0, 1)) * 0.9) * 6.0
        quad(V((0, 0, 96.0)) - r.cross(V((0, 0, 1))) * 1.5, d, r.cross(V((0, 0, 1))) * 3.0, mats[1])
    bm.to_mesh(me)
    bm.free()
    me.update()
    export_glb(trunk, name)


def _join(meshes):
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def _bounds(obj):
    vs = np.array([v.co[:] for v in obj.data.vertices])
    return vs.min(axis=0), vs.max(axis=0)


def build_tripo(name, fname, cam, width_wp, faces, height_wp=None, stretch=False, depth_wp=None):
    # fname może być listą plików: kolejne bryły stoją na poprzedniej (np. radio na biurku), środkiem w osi X, przy tylnej krawędzi
    srcs = [os.path.join(TRIPO, f) for f in (fname if isinstance(fname, (list, tuple)) else [fname])]
    if not all(os.path.exists(s) for s in srcs):
        print("SKIP", name, "(brak", fname, ")")
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    for src in srcs:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=src)
        part = _join([o for o in bpy.data.objects if o not in before and o.type == "MESH"])
        if parts:
            lo0, hi0 = _bounds(parts[-1])
            lo, hi = _bounds(part)
            part.data.transform(Matrix.Translation(((lo0[0] + hi0[0] - lo[0] - hi[0]) * 0.5,
                                                    hi0[1] - hi[1] - 0.08 * (hi0[1] - lo0[1]), hi0[2] - lo[2])))
        parts.append(part)
    obj = _join(parts)
    # strona, z której patrzy wypiek 2D, ma trafić na −Y (ku kamerze gry)
    rot = {"-Y": 0.0, "+Y": 180.0, "+X": -90.0, "-X": 90.0}[cam]
    me = obj.data
    me.transform(Matrix.Rotation(math.radians(rot), 4, "Z"))
    if name == "handcar":
        reshape_handcar(obj)
    if name == "walkway_plank":                                  # bez nóg: zostają deski i belki nośne (kładka wisi na słupach mapy)
        import bmesh
        vz = np.array([v.co.z for v in me.vertices])
        zc = vz.min() + 0.45 * (vz.max() - vz.min())
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < zc], context="VERTS")
        bm.to_mesh(me)
        bm.free()
        me.update()
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    k = width_wp / max(hi[0] - lo[0], 1e-6)
    if height_wp is not None:                                    # mieści się w ramce: ogranicza też wysokość
        k = min(k, height_wp / max(hi[2] - lo[2], 1e-6))
    me.transform(Matrix.Translation((-(lo[0] + hi[0]) * 0.5, -(lo[1] + hi[1]) * 0.5, -lo[2])))
    if stretch and height_wp is not None:
        kx = width_wp / max(hi[0] - lo[0], 1e-6)
        kz = height_wp / max(hi[2] - lo[2], 1e-6)
        ky = min(kx, kz)
        if depth_wp is not None:                                 # płaskie bryły (tablice): ograniczona głębokość
            ky = min(ky, depth_wp / max(hi[1] - lo[1], 1e-6))
        me.transform(Matrix.Diagonal((kx, ky, kz, 1.0)))
    else:
        me.transform(Matrix.Scale(k, 4))
    if len(me.polygons) > faces:
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = faces / float(len(me.polygons))
        bpy.ops.object.modifier_apply(modifier="dec")
    for m in bpy.data.materials:                                 # mapy normalnych z Tripo są ostre — w bliskim świetle latarki dawały „pogniecioną” powierzchnię
        if m.node_tree:
            for nd in m.node_tree.nodes:
                if nd.type == "NORMAL_MAP":
                    nd.inputs["Strength"].default_value = 0.55
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX)
    if name in EMISSIVE:
        for m in bpy.data.materials:
            if not m.node_tree:
                continue
            bsdf = next((nd for nd in m.node_tree.nodes if nd.type == "BSDF_PRINCIPLED"), None)
            if bsdf is None or not bsdf.inputs["Base Color"].links:
                continue
            src_img = bsdf.inputs["Base Color"].links[0].from_node.image
            w, h = src_img.size
            px = np.array(src_img.pixels[:]).reshape(h * w, 4)
            rgb = px[:, :3]
            v = rgb.max(axis=1)
            sat = (v - rgb.min(axis=1)) / np.maximum(v, 1e-6)
            if EMISSIVE[name] == "bulb":
                mask = (v > 0.72) & (sat < 0.3)
            else:
                mask = (v > 0.55) & (sat > 0.62) & ~((rgb[:, 1] > rgb[:, 2] * 1.1) & (rgb[:, 0] > rgb[:, 2] * 1.1) & (sat < 0.8))     # bez żółci i oliwki
            out = np.zeros_like(px)
            out[:, 3] = 1.0
            out[mask, :3] = rgb[mask]
            emi = bpy.data.images.new(name + "_emi", w, h, alpha=False)
            emi.pixels[:] = out.reshape(-1).tolist()
            emi.pack()
            t = m.node_tree.nodes.new("ShaderNodeTexImage")
            t.image = emi
            m.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.0
            print("EMI", name, int(mask.sum()), "px")
    export_glb(obj, name)


def main():
    procs = None
    for name, spec in TRIPO_MODELS.items():
        if want(name):
            build_tripo(name, *spec)
    for name, spec in SPRUCES.items():
        if want(name):
            build_spruce(name, *spec)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.use_selected_to_active = False
    sc.world = bpy.data.worlds.new("w")
    procs = load_proc()
    procs["P"] = procs["palette"]()
    for name, (builder, _ppw) in procs["MODELS"].items():
        if name in TRIPO_MODELS or not want(name):
            continue
        try:
            build_proc(procs, name, builder)
        except Exception as e:                                   # jeden zepsuty model nie zatrzymuje reszty
            import traceback
            traceback.print_exc()
            print("FAIL", name, e)
    print("DONE-ITEMS3D")


main()
