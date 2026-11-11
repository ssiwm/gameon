"""Drzewa ze skanów Poly Haven (`pine_tree_01`, `fir_tree_01`; CC0) w budżecie gry: pień i konary uproszczone, igliwie zamienione na karty.

Uruchomienie (z korzenia repo, Blender w PATH):
    python prototype/tools/polyhaven_fetch.py --res=2k pine_tree_01 fir_tree_01   # źródła ~1 GB i ~0,5 GB w art_src/world/polyhaven/ (tylko lokalnie)
    python prototype/tools/pine_cards.py                                    # sosna pierwszego planu: pine_tree_01__a/b/c.glb
    python prototype/tools/pine_cards.py --lite --tint=0.42,0.55,0.62 --far=pine_a,pine_b         # sosny lasu w głębi + karty dalekiego pasa
    python prototype/tools/pine_cards.py --src=fir_tree_01 --lite --tint=0.33,0.4,0.5 --far=spruce_a,spruce_b,spruce_c   # świerki lasu
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/pine_cards.py -- [opcje]

Skan ma trzy drzewa (a, b, c) i igły jako prawdziwą geometrię (4–7 mln trójkątów na drzewo, materiał `twig` bez alfy) — zwykłe upraszczanie
zlepia je w grudy. Dlatego igliwie dzielimy na sześciany CELL m; w każdym gęstym sześcianie stoją trzy karty na krzyż w osiach głównych
chmury igieł (PCA), z teksturą wyrenderowaną z tej samej geometrii: SAMPLES wycinków korony, każdy z trzech stron (atlas 3 × 3, kolor
bez światła z alfą). Pień, konary i suche gałęzie zostają ze skanu, uproszczone do WOOD_FACES.
Wynik: art_src/world/polyhaven/<źródło>__a.glb, __b, __c (pierwszy plan, kilkadziesiąt tysięcy trójkątów) albo z `--lite` <źródło>__a_lite.glb …
(las w głębi: większe sześciany, atlas 1024, kilka tysięcy trójkątów) — dalej jak każdy skan: `prep_items3d.py` (`ph_pine_*`, `tree_pine_*`,
`tree_spruce_*`) skaluje go do wysokości 100 jednostek i zapisuje w prototype/art/items3d/.
`--far=nazwa,…`: karta dalekiego pasa lasu z każdego drzewa po kolei (pełna geometria skanu z boku, 512 × 1024 z alfą, nasada na dolnym brzegu,
pień w środku) do prototype/art/world3d/forest/<nazwa>.png — te same drzewa co modele bliżej, zamiast kart malowanych w `world_forest_gen.py`.
"""
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PH = os.path.join(ROOT, "art_src", "world", "polyhaven")
FAR_DIR = os.path.join(ROOT, "prototype", "art", "world3d", "forest")
FOLIAGE = ("twig", "needle", "leaf", "leaves", "foliage")   # materiał igliwia w skanie (reszta to drewno)

if "bpy" not in sys.modules:
    try:
        import bpy  # noqa: F401
    except ImportError:
        r = subprocess.run(["blender", "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--"] + sys.argv[1:])
        sys.exit(r.returncode)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

CELL = 0.35            # m: bok sześcianu igliwia na jedną kępę kart
CARD_K = 1.4           # bok karty względem CELL (karty sąsiadów zachodzą na siebie — bez prześwitów siatki)
SPARSE_Q = 35          # percentyl gęstości: rzadsze sześciany odpadają (pojedyncze igły, prześwity między piętrami konarów zostają puste)
SAMPLES = 3            # wycinki korony do atlasu
TILE = 680             # px: bok kafla atlasu (3 × 680 = 2040, atlas 2048)
ATLAS = 2048
WOOD_FACES = 30000     # trójkąty pnia, konarów i suchych gałęzi na drzewo
EDGE_FADE = 0.3        # część promienia kafla, w której alfa gaśnie ku okręgowi
ALPHA_GAIN = 2.2       # wzmocnienie alfy cienkich igieł (po zmniejszeniu tekstury inaczej znikają pod progiem wycinania)
DROP_DEAD = False      # pomiń suche gałęzie skanu (materiał `*dead*`)
TRUNK_FACES = 0        # > 0: pień (materiał `*trunk*`) upraszczany osobno do tylu trójkątów — konary skanu to setki osobnych rurek, których
                       # decymacja nie zwinie, więc przy wspólnym celu zjadała pień (las w głębi bez pnia poniżej korony)
MIN_PART = 0.0         # m: kawałki konarów o mniejszej przekątnej odpadają (cieńsze od piksela w środkowym pasie)
# las w głębi (`--lite`): setki drzew w kadrze — mniej i większych kart (koszt to nakładanie się kart z alfą, rośnie jak objętość / CELL;
# przy 0,8 m środkowy pas 1.2 / 1.3 kosztował +1,6–1,8 ms GPU), mały atlas, pień uproszczony mocniej, bez suchych gałęzi (z tej odległości
# cieńsze od piksela — migotałyby, a ich setki rurek trzymały decymację pnia ponad celem)
LITE = {"CELL": 0.7, "CARD_K": 1.3, "SPARSE_Q": 45, "TILE": 340, "ATLAS": 1024, "WOOD_FACES": 1200, "DROP_DEAD": True,
        "TRUNK_FACES": 500, "MIN_PART": 1.2}
FAR_W, FAR_H = 512, 1024
FAR_GAIN = 1.6         # wzmocnienie alfy karty dalekiego pasa (igły w 1024 px to półprzezroczysty puch)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC_ID = next((a[6:] for a in ARGS if a.startswith("--src=")), "pine_tree_01")
FAR = next((a[6:].split(",") for a in ARGS if a.startswith("--far=")), [])
# mnożnik koloru igliwia (atlas) i całej karty dalekiej: albedo skanów (oliwkowe, ok. 76/76/51 sRGB) jest ok. 2,5× jaśniejsze i bardziej
# żółte od palety lasu gry (ciemna sinozieleń ok. 30/42/31) — bez tego korony w głębi świecą jak liściaste kępy; `fir_tree_01` jest
# jeszcze jaśniejsze od sosny (a w borze świerk to ciemniejsze piętro), stąd mocniejszy mnożnik
TINT = np.array(next((a[7:].split(",") for a in ARGS if a.startswith("--tint=")), [1, 1, 1]), np.float32)
if "--lite" in ARGS:
    globals().update(LITE)
SRC = os.path.join(PH, SRC_ID + ".glb")
OUT = os.path.join(PH, SRC_ID + "__%s" + ("_lite" if "--lite" in ARGS else "") + ".glb")


def mesh_arrays(obj):
    me = obj.data
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    tri_v = np.empty(nt * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", tri_v)
    tri_l = np.empty(nt * 3, np.int32)
    me.loop_triangles.foreach_get("loops", tri_l)
    tri_m = np.empty(nt, np.int32)
    me.loop_triangles.foreach_get("material_index", tri_m)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(obj.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers[0].data.foreach_get("uv", uv)
    return tri_v.reshape(-1, 3), tri_l.reshape(-1, 3), tri_m, co, uv.reshape(-1, 2)


def sub_mesh(name, tris, loops, mats_idx, co, uv, materials):
    """Nowy obiekt z wybranych trójkątów (wierzchołki przenumerowane, UV z narożników, materiały po indeksie)."""
    uniq, inv = np.unique(tris, return_inverse=True)
    faces = inv.reshape(-1, 3)
    me = bpy.data.meshes.new(name)
    me.from_pydata(co[uniq].tolist(), [], faces.tolist())
    for m in materials:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mats_idx.astype(np.int32))
    lay = me.uv_layers.new(name="UVMap")
    lay.data.foreach_set("uv", uv[loops].reshape(-1))
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def frames(pts, cell):
    """Sześciany igliwia: środek, osie PCA (e1 najdłuższa, e2, n = e1 × e2) i liczba wierzchołków."""
    key = np.floor(pts / cell).astype(np.int64)
    uk, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    k = len(uk)
    s1 = np.zeros((k, 3))
    np.add.at(s1, inv, pts)
    s2 = np.zeros((k, 3, 3))
    for a in range(3):
        for b in range(a, 3):
            col = np.zeros(k)
            np.add.at(col, inv, pts[:, a] * pts[:, b])
            s2[:, a, b] = col
            s2[:, b, a] = col
    mu = s1 / cnt[:, None]
    cov = s2 / cnt[:, None, None] - mu[:, :, None] * mu[:, None, :]
    w, v = np.linalg.eigh(cov + np.eye(3) * 1e-9)          # rosnąco: v[:, :, 2] najdłuższa
    e1 = v[:, :, 2]
    e2 = v[:, :, 1]
    n = np.cross(e1, e2)
    return mu, e1, e2, n, cnt


def render_tile(src, tris, co_t, mu, axes, half, path):
    """Wycinek igliwia (sześcian o boku 2·half w osiach `axes`) widziany z trzech stron → trzy obrazy TILE × TILE z alfą."""
    sc = bpy.context.scene
    rel = (co_t - mu) @ np.array(axes).T                    # współrzędne w osiach wycinka
    inside = np.all(np.abs(rel) <= half, axis=1)
    keep = inside[tris].all(axis=1)
    obj = sub_mesh("sample", src["tris"][keep], src["loops"][keep], np.zeros(int(keep.sum())), src["co"], src["uv"], [src["mat"]])
    for o in sc.objects:
        o.hide_render = o is not obj and o.type == "MESH"
    cam = sc.camera
    e1, e2, n = (Vector(a) for a in axes)
    outs = []
    for view, (x, y) in enumerate(((e1, e2), (e1, n), (e2, n))):
        z = x.cross(y)
        cam.matrix_world = Matrix.Translation(Vector(mu) + z * 20.0) @ Matrix((x, y, z)).transposed().to_4x4()
        cam.data.ortho_scale = 2.0 * half
        sc.render.filepath = path % view
        bpy.ops.render.render(write_still=True)
        outs.append(sc.render.filepath)
    bpy.data.objects.remove(obj)
    return outs


def build_atlas(paths, name):
    img = np.zeros((ATLAS, ATLAS, 4), np.float32)
    for i, p in enumerate(paths):
        t = bpy.data.images.load(p)
        px = np.array(t.pixels[:], np.float32).reshape(TILE, TILE, 4)
        bpy.data.images.remove(t)
        s, view = divmod(i, 3)
        img[s * TILE:(s + 1) * TILE, view * TILE:(view + 1) * TILE] = px
    # brzeg kafla: alfa gaśnie ku okręgowi wpisanemu w kafel (inaczej igły ucięte prosto po krawędzi wycinka dawały na karcie prostą linię)
    t = (np.arange(TILE) + 0.5) / TILE * 2.0 - 1.0
    r = np.sqrt(t[:, None] ** 2 + t[None, :] ** 2)          # okrąg wpisany w kafel: gęsty wycinek to kępa, nie kwadratowa płyta
    ramp = np.clip((1.0 - r) / EDGE_FADE, 0.0, 1.0)
    reps = ATLAS // TILE
    mask = np.zeros((ATLAS, ATLAS), np.float32)
    mask[: reps * TILE, : reps * TILE] = np.tile(ramp, (reps, reps))
    a = img[:, :, 3] * mask
    rgb = img[:, :, :3].copy()                                 # PNG z Blendera ma alfę prostą (kolor nieprzemnożony)
    mean = rgb[a > 0.5].mean(axis=0)
    rgb[a < 0.02] = mean                                       # tło w średnim kolorze igieł: bez ciemnej obwódki w mipmapach
    img[:, :, :3] = np.clip(rgb * TINT, 0.0, 1.0)
    img[:, :, 3] = np.clip(a * ALPHA_GAIN, 0.0, 1.0)
    out = bpy.data.images.new(name, ATLAS, ATLAS, alpha=True)
    out.pixels[:] = img.reshape(-1)
    out.pack()
    return out


def card_material(atlas, name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = atlas
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
    bs.inputs["Roughness"].default_value = 1.0
    bs.inputs["Metallic"].default_value = 0.0
    m.blend_method = "CLIP"
    m.use_backface_culling = False
    return m


def cards_mesh(name, mu, e1, e2, n, half, rng, mat):
    """Trzy karty na krzyż w każdym sześcianie; kafel atlasu = (losowy wycinek, strona zgodna z płaszczyzną karty)."""
    verts, faces, uvs = [], [], []
    tile = TILE / ATLAS
    for i in range(len(mu)):
        s = int(rng.integers(SAMPLES))
        flip = rng.random() < 0.5
        for view, (x, y) in enumerate(((e1[i], e2[i]), (e1[i], n[i]), (e2[i], n[i]))):
            b = len(verts)
            for cu, cv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                verts.append(mu[i] + (x * cu + y * cv) * half)
                u = (cu * (-1 if flip else 1) + 1) * 0.5
                uvs.append(((view + u) * tile, (s + (cv + 1) * 0.5) * tile))
            faces.append((b, b + 1, b + 2, b + 3))
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.array(verts).tolist(), [], faces)
    me.materials.append(mat)
    lay = me.uv_layers.new(name="UVMap")
    lay.data.foreach_set("uv", np.array([uvs[v] for f in faces for v in f], np.float32).reshape(-1))
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def decimate(obj, faces, min_part=0.0):
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    if min_part > 0.0:
        seen, drop = set(), []
        for f0 in bm.faces:
            if f0 in seen:
                continue
            part, st = [], [f0]
            while st:
                f = st.pop()
                if f in seen:
                    continue
                seen.add(f)
                part.append(f)
                st.extend(g for e in f.edges for g in e.link_faces)
            vs = np.array([v.co[:] for f in part for v in f.verts])
            if np.linalg.norm(vs.max(axis=0) - vs.min(axis=0)) < min_part:
                drop += part
        bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.to_mesh(me)
    bm.free()
    if len(me.polygons) > faces:
        bpy.context.view_layer.objects.active = obj
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = faces / float(len(me.polygons))
        bpy.ops.object.modifier_apply(modifier="dec")


def render_far(obj, co, path):
    """Karta dalekiego lasu: całe drzewo ze skanu z boku (rzut prostokątny), wysokość = wysokość obrazu, nasada na dolnym brzegu, pień w środku."""
    sc = bpy.context.scene
    for o in sc.objects:
        o.hide_render = o is not obj and o.type == "MESH"
    lo, hi = co.min(axis=0), co.max(axis=0)
    h = hi[2] - lo[2]
    foot = co[co[:, 2] <= lo[2] + 0.02 * h].mean(axis=0)
    cam = sc.camera
    cam.data.ortho_scale = h
    cam.matrix_world = Matrix.Translation((foot[0], lo[1] - 50.0, lo[2] + h * 0.5)) @ Matrix.Rotation(math.radians(90.0), 4, "X")
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    sc.render.resolution_x, sc.render.resolution_y = FAR_W, FAR_H
    sc.render.filepath = path + ".raw.png"
    bpy.ops.render.render(write_still=True)
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    t = bpy.data.images.load(sc.render.filepath)
    px = np.array(t.pixels[:], np.float32).reshape(FAR_H, FAR_W, 4)
    bpy.data.images.remove(t)
    a = px[:, :, 3]
    mean = px[a > 0.5, :3].mean(axis=0)
    px[a < 0.02, :3] = mean                                   # tło w średnim kolorze drzewa: bez ciemnej obwódki w mipmapach
    px[:, :, :3] = np.clip(px[:, :, :3] * TINT, 0.0, 1.0)
    px[:, :, 3] = np.clip(a * FAR_GAIN, 0.0, 1.0)
    out = bpy.data.images.new(os.path.basename(path), FAR_W, FAR_H, alpha=True)
    out.pixels[:] = px.reshape(-1)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    os.remove(sc.render.filepath)
    print("FAR", os.path.relpath(path, ROOT))


def main():
    if not os.path.exists(SRC):
        print("BRAK", SRC, "— najpierw: python prototype/tools/polyhaven_fetch.py pine_tree_01")
        sys.exit(1)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.render_aa = "32"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = sc.render.resolution_y = TILE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.clip_end = 100.0
    sc.collection.objects.link(cam)
    sc.camera = cam
    tmp = os.path.join(os.environ.get("TEMP", "/tmp"), "pine_cards")
    os.makedirs(tmp, exist_ok=True)
    trees = sorted([o for o in sc.objects if o.type == "MESH"], key=lambda o: o.name)
    for idx, obj in enumerate(trees):
        tag = "abc"[idx]
        rng = np.random.default_rng(71 + idx)
        tris, loops, tmat, co, uv = mesh_arrays(obj)
        mats = [s.material for s in obj.material_slots]
        print("TREE", tag, obj.name, "materiały:", [m.name for m in mats])
        twig_i = next(i for i, m in enumerate(mats) if any(k in m.name.lower() for k in FOLIAGE))
        wood_sel = tmat != twig_i
        if DROP_DEAD:
            wood_sel &= ~np.isin(tmat, [i for i, m in enumerate(mats) if "dead" in m.name.lower()])
        trunk_sel = np.zeros_like(wood_sel)
        if TRUNK_FACES > 0:
            trunk_sel = wood_sel & np.isin(tmat, [i for i, m in enumerate(mats) if "trunk" in m.name.lower()])
            wood_sel = wood_sel & ~trunk_sel
        wood_mats = sorted(set(tmat[wood_sel].tolist()))
        remap = np.zeros(len(mats), np.int32)
        for j, mi in enumerate(wood_mats):
            remap[mi] = j
        wood = sub_mesh("pine_" + tag, tris[wood_sel], loops[wood_sel], remap[tmat[wood_sel]], co, uv, [mats[i] for i in wood_mats])
        trunk = None
        if trunk_sel.any():
            trunk = sub_mesh("trunk_" + tag, tris[trunk_sel], loops[trunk_sel], np.zeros(int(trunk_sel.sum()), np.int32), co, uv,
                             [mats[int(tmat[trunk_sel][0])]])
        twig = tmat == twig_i
        t_tris, t_loops = tris[twig], loops[twig]
        tv = np.unique(t_tris)
        mu, e1, e2, n, cnt = frames(co[tv], CELL)
        dense = cnt >= max(8.0, np.percentile(cnt, SPARSE_Q))
        print("TREE", tag, "igły: %d trójkątów, sześcianów %d, gęstych %d" % (len(t_tris), len(cnt), int(dense.sum())))
        half = CELL * CARD_K * 0.5
        # wycinki do atlasu: sześciany w środkowej części korony (różne wysokości), każdy z trzech stron
        # (gęstość średnia, nie największa — najgęstsze wycinki to lita masa igieł bez ażurowego obrysu)
        zs = mu[:, 2]
        z_lo, z_hi = np.percentile(zs[dense], [35, 90])
        c_lo, c_hi = np.percentile(cnt[dense], [55, 80])
        cand = [i for i in np.argsort(zs) if z_lo <= zs[i] <= z_hi and c_lo <= cnt[i] <= c_hi]
        picks = [cand[int((k + 0.5) * len(cand) / SAMPLES)] for k in range(SAMPLES)]
        src = {"tris": t_tris, "loops": t_loops, "co": co, "uv": uv, "mat": mats[twig_i]}
        paths = []
        for s, i in enumerate(picks):
            paths += render_tile(src, t_tris, co, mu[i], (e1[i], e2[i], n[i]), half, os.path.join(tmp, "%s_%s_%d_%%d.png" % (SRC_ID, tag, s)))
        atlas = build_atlas(paths, "%s_%s_needles" % (SRC_ID, tag))
        atlas.filepath_raw = os.path.join(tmp, "%s_%s_needles.png" % (SRC_ID, tag))
        atlas.file_format = "PNG"
        atlas.save()
        cmat = card_material(atlas, SRC_ID + "_needles")
        cards = cards_mesh("cards_" + tag, mu[dense], e1[dense], e2[dense], n[dense], half, rng, cmat)
        decimate(wood, WOOD_FACES, MIN_PART)
        if trunk:
            decimate(trunk, TRUNK_FACES)
        for o in sc.objects:
            o.select_set(o in (wood, cards, trunk))
        bpy.context.view_layer.objects.active = wood
        bpy.ops.object.join()
        wood.hide_render = False
        lo = np.array([min(v.co[a] for v in wood.data.vertices) for a in range(3)])
        hi = np.array([max(v.co[a] for v in wood.data.vertices) for a in range(3)])
        print("TREE", tag, "trójkątów %d, wymiary %.1f × %.1f × %.1f m" % (sum(len(p.vertices) - 2 for p in wood.data.polygons), *(hi - lo)))
        for o in list(sc.objects):
            o.select_set(o is wood)
        bpy.ops.export_scene.gltf(filepath=OUT % tag, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                                  export_image_format="AUTO", export_animations=False)
        print("SAVED", os.path.relpath(OUT % tag, ROOT), os.path.getsize(OUT % tag) // 1024, "kB")
        bpy.data.objects.remove(wood)
        if idx < len(FAR):
            render_far(obj, co, os.path.join(FAR_DIR, FAR[idx] + ".png"))
        bpy.data.objects.remove(obj)


main()
