"""Pobiera modele z Poly Haven (CC0, api.polyhaven.com) jako źródła dla `prep_items3d.py`: art_src/world/polyhaven/<id>.glb.

Uruchomienie (z korzenia repo, Blender w PATH):
    python prototype/tools/polyhaven_fetch.py [--res=1k] [--split] id1 id2 ...
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/polyhaven_fetch.py -- [--res=1k] [--split] id1 ...

Model przychodzi jako glTF z osobnymi teksturami (kolor, normalne, ARM); Blender składa go w jeden plik GLB z teksturami w środku.
`--split` rozdziela zestawy (np. `rock_moss_set_01`) na osobne pliki `<id>__<nazwa obiektu>.glb` — jeden kamień na plik.
Siatka zostaje pełna; upraszcza ją dopiero `prep_items3d.py` (do budżetu trójkątów z tabeli TRIPO_MODELS).
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
IDS = []
for a in argv:
    if a.startswith("--res="):
        RES = a[6:]
    elif a == "--split":
        SPLIT = True
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


for aid in IDS:
    fetch(aid)
print("DONE-POLYHAVEN")
