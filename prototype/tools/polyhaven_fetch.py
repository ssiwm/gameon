"""Pobiera modele z Poly Haven (CC0, api.polyhaven.com) jako źródła dla `prep_items3d.py`: art_src/world/polyhaven/<id>.glb.

Uruchomienie (z korzenia repo, Blender w PATH):
    python prototype/tools/polyhaven_fetch.py [--res=1k] [--split] id1 id2 ...
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/polyhaven_fetch.py -- [--res=1k] [--split] id1 ...

Model przychodzi jako glTF z osobnymi teksturami (kolor, normalne, ARM); Blender składa go w jeden plik GLB z teksturami w środku.
`--split` rozdziela zestawy (np. `rock_moss_set_01`) na osobne pliki `<id>__<nazwa obiektu>.glb` — jeden kamień na plik.
Siatka zostaje pełna; upraszcza ją dopiero `prep_items3d.py` (do budżetu trójkątów z tabeli TRIPO_MODELS).

`--hdri id1 id2 ...` pobiera zamiast modeli panoramy HDRI (1K) do prototype/art/world3d/hdri/<id>.hdr — „niebo odbić" warstwy graczy w `view3d.gd`
(nocny krajobraz w misjach, wnętrze w kryjówce). Panorama jest przycinana (latarnie i księżyc do HDRI_CLIP, inaczej na stali broni wychodzą
błyski) i normalizowana do średniej luminancji 1 (po sferze), więc o jasności decyduje w grze samo `ACTOR_REFLECT` — jak przy niebie proceduralnym.
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "art_src", "world", "polyhaven")
UA = {"User-Agent": "dead-air-87-asset-fetch/1.0"}

if "bpy" not in sys.modules:
    try:
        import bpy  # noqa: F401
    except ImportError:
        r = subprocess.run(["blender", "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--"] + sys.argv[1:])
        sys.exit(r.returncode)

import bpy  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RES = "1k"
SPLIT = False
HDRI = False
IDS = []
HDRI_CLIP = 8.0                                                  # przycięcie względem surowej panoramy (księżyc ma ok. 7000)
for a in argv:
    if a.startswith("--res="):
        RES = a[6:]
    elif a == "--split":
        SPLIT = True
    elif a == "--hdri":
        HDRI = True
    else:
        IDS.append(a)


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def download_gltf(aid, tmp):
    files = json.loads(get("https://api.polyhaven.com/files/" + aid))
    entry = files["gltf"][RES]["gltf"]
    main = os.path.join(tmp, os.path.basename(entry["url"]))
    with open(main, "wb") as f:
        f.write(get(entry["url"]))
    for rel, inc in entry.get("include", {}).items():         # .bin i tekstury, ścieżki względne jak w pliku .gltf
        path = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(get(inc["url"]))
    return main


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90, export_animations=False)
    print("SAVED", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "kB")


def fetch(aid):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory() as tmp:
        bpy.ops.import_scene.gltf(filepath=download_gltf(aid, tmp))
        for img in bpy.data.images:                              # tekstury do GLB, zanim katalog tymczasowy zniknie
            img.pack()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        print("  ", o.name, len(o.data.polygons), "ścian")
    os.makedirs(OUT, exist_ok=True)
    if SPLIT:
        for o in meshes:
            part = o.name.lower().replace(" ", "_").removeprefix(aid).strip("_") or "0"     # rock_moss_set_01_rock01 → rock01
            export([o], os.path.join(OUT, "%s__%s.glb" % (aid, part)))
    else:
        export(meshes, os.path.join(OUT, aid + ".glb"))


def fetch_hdri(aid):
    import math
    import numpy as np
    url = json.loads(get("https://api.polyhaven.com/files/" + aid))["hdri"]["1k"]["hdr"]["url"]
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, aid + ".hdr")
        with open(raw, "wb") as f:
            f.write(get(url))
        im = bpy.data.images.load(raw)
        w, h = im.size
        a = np.array(im.pixels[:], np.float32).reshape(h, w, 4)
        a[..., :3] = np.minimum(a[..., :3], HDRI_CLIP)
        y = a[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        wt = np.cos((np.arange(h) + 0.5) / h * math.pi - math.pi / 2)[:, None] * np.ones((1, w))
        mean = float((y * wt).sum() / wt.sum())
        a[..., :3] /= mean
        im.pixels.foreach_set(a.ravel())
        out = os.path.join(ROOT, "prototype", "art", "world3d", "hdri")
        os.makedirs(out, exist_ok=True)
        path = os.path.join(out, aid + ".hdr")
        sc = bpy.context.scene
        sc.render.image_settings.file_format = "HDR"
        sc.render.image_settings.color_depth = "32"
        im.save_render(path, scene=sc)
        print("SAVED", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "kB (średnia przed normalizacją %.3f)" % mean)


for aid in IDS:
    fetch_hdri(aid) if HDRI else fetch(aid)
print("DONE-POLYHAVEN")
