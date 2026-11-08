"""Części rur pierwszego planu (`scripts/front3d.gd`, `FOREGROUND_PLAN.md`) z zestawu Poly Haven `modular_industrial_pipes_01` (CC0).

Uruchomienie (z korzenia repo, Blender w PATH):
    python prototype/tools/front_parts.py
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/front_parts.py

Źródło: art_src/world/polyhaven/modular_industrial_pipes_01.glb (`tools/polyhaven_fetch.py`). Wynik: prototype/art/world3d/front/pipe_parts.glb —
sama geometria z UV, bez materiałów i tekstur. Tekstury (kolor, ARM, normalne) bierze shader `front3d.gd` z plików, które ten sam zestaw
ma już w `art/items3d/pipes_*` (dekoracja `pipes` z `prep_items3d.py`), więc nie ma drugiej kopii.

Każda część jest osobnym obiektem `<nazwa>__g1` albo `<nazwa>__g2` (grupa tekstur zestawu), z początkiem układu w środku dolnego kołnierza,
osią rury pionowo (Y w Godocie) i frontem (koło zaworu, odgałęzienie) w stronę −Y Blendera (= +Z w Godocie, ku kamerze gry).
Rozmiar jak w źródle (rura z kołnierzem 0,21 m) — skalę dobiera `front3d.gd`.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_src", "world", "polyhaven", "modular_industrial_pipes_01.glb")
OUT = os.path.join(ROOT, "prototype", "art", "world3d", "front", "pipe_parts.glb")

if "bpy" not in sys.modules:
    try:
        import bpy  # noqa: F401
    except ImportError:
        r = subprocess.run(["blender", "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--"] + sys.argv[1:])
        sys.exit(r.returncode)

import bpy  # noqa: E402
import mathutils  # noqa: E402

# część → (obiekt w zestawie, grupa tekstur, obrót wokół pionu w stopniach: odgałęzienie / koło zaworu ku kamerze)
PARTS = {
    "seg": ("pipe01", 1, 0.0),      # prosty odcinek 0,86 m z kołnierzami na obu końcach
    "thin": ("pipe02", 1, 0.0),     # cienka rura 1,95 m
    "offset": ("pipe03", 1, 0.0),   # odsadzka w kształcie S
    "tee": ("pipe06", 2, 0.0),      # trójnik z odgałęzieniem w bok
    "cross": ("pipe07", 2, 0.0),    # czwórnik
    "valve": ("pipe08", 2, 0.0),    # zawór z czerwonym kołem i manometrem
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = {o.name.replace("modular_industrial_pipes_01_", ""): o for o in bpy.context.scene.objects if o.type == "MESH"}
keep = []
for name, (obj_name, group, rot) in PARTS.items():
    o = src[obj_name]
    me = o.data.copy()
    me.transform(o.matrix_world)
    if rot != 0.0:
        me.transform(mathutils.Matrix.Rotation(rot * 3.14159265 / 180.0, 4, "Z"))
    # początek układu: środek dolnego kołnierza (oś rury = środek przekroju na dole bryły)
    zs = [v.co.z for v in me.vertices]
    z0 = min(zs)
    bottom = [v.co for v in me.vertices if v.co.z < z0 + 0.03]
    cx = (min(c.x for c in bottom) + max(c.x for c in bottom)) * 0.5
    cy = (min(c.y for c in bottom) + max(c.y for c in bottom)) * 0.5
    me.transform(mathutils.Matrix.Translation((-cx, -cy, -z0)))
    me.materials.clear()
    ob = bpy.data.objects.new("%s__g%d" % (name, group), me)
    bpy.context.scene.collection.objects.link(ob)
    keep.append(ob)
    d = ob.dimensions
    print("[FRONT] %-7s z %s: %d trójkątów, %.2f × %.2f × %.2f m" % (name, obj_name, sum(len(p.vertices) - 2 for p in me.polygons), d.x, d.y, d.z))

for o in list(bpy.context.scene.objects):
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_materials="NONE", export_yup=True, export_apply=True, export_tangents=True)
print("[FRONT] zapisano", OUT)
