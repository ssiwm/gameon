"""Pre-fraktura zniszczalnych elementów (DESTRUCTION_PLAN.md D0, „Rozpad”): bryła materiału pocięta na komórki Voronoi
albo — deska — skośnymi cięciami w poprzek; gruz zawału (`rock`, BARRIER_FIX_PLAN.md B0) — nieregularny głaz zamiast kostki.

Każda komórka to część wspólna bryły z półprzestrzeniami „bliżej mojego punktu niż sąsiada” — cięcie płaszczyznami w bmesh
(`bisect_plane` + zaślepienie otworu), więc bryły są wypukłe i razem dokładnie wypełniają całość. Deska (`cuts`) ma kawałki między
kolejnymi płaszczyznami pochylonymi o 25–50° w płaszczyźnie deski: końce kawałków są ukośne, więc wyglądają jak drzazgi
(komórki Voronoi na długiej listwie wychodzą prostopadłe). Ściany zewnętrzne mają materiał
`outer`, przekroje — `inner` (świeży przełom). Widok 3D (`view3d.gd`, `mirror_chunk`) bierze bryły jako odłamki przy rozbiciu,
a uśpione przenosi do `MultiMesh` (gruz do końca misji); materiały podmienia na własne (tekstura triplanarna w przestrzeni bryły),
więc plik nie ma tekstur ani UV.

Wynik: prototype/art/items3d/fracture_<zestaw>.glb — obiekty chunk_00…, środek każdego w początku układu (środek bryły).

    blender -b --factory-startup -P prototype/tools/fracture_gen.py
    blender -b --factory-startup -P prototype/tools/fracture_gen.py -- brick      # jeden zestaw
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "items3d")

# zestaw: wymiary bryły [m] (x, y, z w Blenderze: z w górę), liczba komórek Voronoi (`cells`) albo skośnych cięć deski (`cuts`), ziarno
SETS = {
    # cegła / mur: kostka 1 m, 12 brył (plan: 6–14); skala w grze wg wielkości odłamka
    "brick": {"size": (1.0, 1.0, 1.0), "cells": 12, "seed": 87},
    # deski (skrzynia `k`, D1; potem barykady D2): listwa 1 × 0,11 × 0,03 m, 3 skośne cięcia → 4 drzazgi o ukośnych końcach
    "planks": {"size": (1.0, 0.03, 0.11), "cuts": 3, "seed": 41},
    # gruz zawału (D3, BARRIER_FIX_PLAN.md B0): głaz ok. 1 × 0,85 × 0,7 m (zniekształcona ikosfera), 10 brył — kamienie o jednej
    # chropowatej, zaokrąglonej stronie i płaskich przełomach, nie kostki muru
    "rock": {"size": (1.0, 0.85, 0.7), "cells": 10, "seed": 63, "shape": "boulder", "bumps": 0.12},
}


def _clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = color
    return m


def _boulder(bm, size, bumps, seed):
    """Głaz: ikosfera o promieniu 0,5 rozciągnięta do `size`, wierzchołki odsunięte promieniowo o ±`bumps` (to samo ziarno
    dla każdej komórki, więc komórki dalej razem wypełniają jedną bryłę)."""
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5)
    rng = random.Random(seed * 7919)
    for v in sorted(bm.verts, key=lambda v: (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))):
        v.co *= 1.0 + rng.uniform(-bumps, bumps)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)


def _cell(size, pts, i, spec=None):
    """Komórka `i`: prostopadłościan `size` (albo głaz, `shape` = boulder) przycięty płaszczyznami symetralnych do wszystkich innych punktów."""
    bm = bmesh.new()
    if spec and spec.get("shape") == "boulder":
        _boulder(bm, size, spec.get("bumps", 0.1), spec["seed"])
    else:
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


def _slice(size, cuts, i):
    """Kawałek deski `i`: prostopadłościan `size` między płaszczyzną `cuts[i - 1]` (zostaje strona dodatnia) a `cuts[i]` (ujemna)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    for f in bm.faces:
        f.material_index = 0
    for k, keep_pos in ((i - 1, True), (i, False)):
        if k < 0 or k >= len(cuts) or not bm.verts:
            continue
        co, n = cuts[k]
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=n,
                                     clear_inner=keep_pos, clear_outer=not keep_pos)
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if len(cut) >= 3:
            for f in bmesh.ops.holes_fill(bm, edges=cut, sides=0)["faces"]:
                f.material_index = 1
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm


def _plank_cuts(spec, rng):
    """Płaszczyzny cięć deski wzdłuż x: równe odstępy z rozrzutem, normalna pochylona o ±25–50° w płaszczyźnie deski (x–z)."""
    sx = spec["size"][0]
    n = spec["cuts"]
    out = []
    for k in range(n):
        x = (-0.5 + (k + 1) / (n + 1) + rng.uniform(-0.25, 0.25) / (n + 1)) * sx
        a = math.radians(rng.uniform(25.0, 50.0)) * rng.choice((-1.0, 1.0))
        out.append((Vector((x, 0.0, 0.0)), Vector((math.cos(a), rng.uniform(-0.1, 0.1), math.sin(a))).normalized()))
    return out


def build(name, spec):
    _clear()
    rng = random.Random(spec["seed"])
    sx, sy, sz = spec["size"]
    cuts = _plank_cuts(spec, rng) if "cuts" in spec else []
    span = 0.38 if spec.get("shape") == "boulder" else 0.5          # punkty komórek głazu w środku, nie poza zaokrąglonym brzegiem
    pts = [] if cuts else [Vector((rng.uniform(-span, span) * sx, rng.uniform(-span, span) * sy, rng.uniform(-span, span) * sz))
                           for _ in range(spec["cells"])]
    outer = _material("outer", (0.5, 0.3, 0.24, 1.0))
    inner = _material("inner", (0.75, 0.5, 0.4, 1.0))
    made = 0
    vol = 0.0
    for i in range(len(cuts) + 1 if cuts else len(pts)):
        bm = _slice(spec["size"], cuts, i) if cuts else _cell(spec["size"], pts, i, spec)
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
    print("[FRACTURE] %s: %d brył, objętość %.3f z %.3f m³ (prostopadłościan) -> %s" % (name, made, vol, sx * sy * sz, path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in (argv or list(SETS)):
        build(name, SETS[name])


main()
