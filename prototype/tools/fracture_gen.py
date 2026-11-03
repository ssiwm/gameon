"""Pre-fraktura zniszczalnych elementów (DESTRUCTION_PLAN.md D0, „Rozpad”): bryła materiału pocięta na komórki Voronoi.

Każda komórka to część wspólna bryły z półprzestrzeniami „bliżej mojego punktu niż sąsiada” — cięcie płaszczyznami w bmesh
(`bisect_plane` + zaślepienie otworu), więc bryły są wypukłe i razem dokładnie wypełniają całość. Ściany zewnętrzne mają materiał
`outer`, przekroje — `inner` (świeży przełom). Widok 3D (`view3d.gd`, `mirror_chunk`) bierze bryły jako odłamki przy rozbiciu,
a uśpione przenosi do `MultiMesh` (gruz do końca misji); materiały podmienia na własne (tekstura triplanarna w przestrzeni bryły),
więc plik nie ma tekstur ani UV.

Wynik: prototype/art/items3d/fracture_<zestaw>.glb — obiekty chunk_00…, środek każdego w początku układu (środek bryły).

    blender -b --factory-startup -P prototype/tools/fracture_gen.py
    blender -b --factory-startup -P prototype/tools/fracture_gen.py -- brick      # jeden zestaw
"""
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "items3d")

# zestaw: wymiary bryły [m] (x, y, z w Blenderze: z w górę), liczba komórek, ziarno, spłaszczenie rozkładu punktów
SETS = {
    # cegła / mur: kostka 1 m, 12 brył (plan: 6–14); skala w grze wg wielkości odłamka
    "brick": {"size": (1.0, 1.0, 1.0), "cells": 12, "seed": 87},
}


def _clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = color
    return m


def _cell(size, pts, i):
    """Komórka `i`: prostopadłościan `size` przycięty płaszczyznami symetralnych do wszystkich innych punktów."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    for f in bm.faces:
        f.material_index = 0
    p = pts[i]
    for j, q in enumerate(pts):
        if j == i or not bm.verts:
            continue
        n = (q - p).normalized()
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(p + q) * 0.5, plane_no=n,
                                     clear_outer=True)
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if len(cut) >= 3:
            for f in bmesh.ops.holes_fill(bm, edges=cut, sides=0)["faces"]:
                f.material_index = 1
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm


def build(name, spec):
    _clear()
    rng = random.Random(spec["seed"])
    sx, sy, sz = spec["size"]
    pts = [Vector((rng.uniform(-0.5, 0.5) * sx, rng.uniform(-0.5, 0.5) * sy, rng.uniform(-0.5, 0.5) * sz)) for _ in range(spec["cells"])]
    outer = _material("outer", (0.5, 0.3, 0.24, 1.0))
    inner = _material("inner", (0.75, 0.5, 0.4, 1.0))
    made = 0
    vol = 0.0
    for i in range(len(pts)):
        bm = _cell(spec["size"], pts, i)
        if len(bm.faces) < 4:
            bm.free()
            continue
        c = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        bmesh.ops.translate(bm, vec=-c, verts=bm.verts)
        vol += bm.calc_volume()
        me = bpy.data.meshes.new("chunk_%02d" % made)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(outer)
        me.materials.append(inner)
        for poly in me.polygons:
            poly.use_smooth = False                         # ostre krawędzie przełomu
        ob = bpy.data.objects.new("chunk_%02d" % made, me)
        ob.location = c
        bpy.context.scene.collection.objects.link(ob)
        made += 1
    path = os.path.join(OUT, "fracture_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_animations=False,
                              export_materials="EXPORT", export_texcoords=False)
    print("[FRACTURE] %s: %d brył, objętość %.3f z %.3f m³ -> %s" % (name, made, vol, sx * sy * sz, path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in (argv or list(SETS)):
        build(name, SETS[name])


main()
