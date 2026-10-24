"""Przygotowuje model wroga 3D (rig z Tripo) do renderu w czasie rzeczywistym w widoku 3D gry (`enemy3d.gd`).

Uruchomienie (z korzenia repo, Blender w PATH): python prototype/tools/prep_enemy3d.py [--only=wolek,slepiec]
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/prep_enemy3d.py -- SRC.glb DST.glb [--faces=6000] [--tex=1024] [--anim]
Co robi: usuwa śmieciowe siatki (bez wag kości), scala geometryczne szwy UV, upraszcza siatkę (Decimate), normalizuje maks. cztery wagi,
zmniejsza tekstury do --tex px i eksportuje GLB. --surface-weights: przelicza wagi ciała po jego powierzchni; materiał 1 = tasak prawej dłoni (Rzeźnik).
Skala zostaje natywna (pozy w `enemy3d.gd` używają stałych z tego samego modelu, co wypiek 2D w `concept/monster_tripo_bake.py`); wysokość
dopasowuje gra w czasie działania. --uvkeep: decymacja respektuje granice wysp UV (modele z TRELLIS-a; wymaga większej liczby trójkątów). --anim: zachowuje animację z pliku (Trzosek — „preset:quadruped:walk").
"""
import glob
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_src", "enemies", "tripo")
OUT = os.path.join(ROOT, "prototype", "art", "enemy3d")

# rodzaj: (plik źródłowy, animacja z pliku, obrót wokół pionu dla modeli statycznych bez rigu lub None, liczba trójkątów, tekstura px)
# Modele statyczne (Ćma, gniazdo, Żyła, Pijawka) są animowane deformacją wierzchołków w shaderze (`enemy3d.gd`), więc dostają układ jak w wypieku
# `concept/static_tripo_bake.py`: obrót ROT_Z, postawienie na podłodze (z = 0) i wyśrodkowanie w x, y.
UVKEEP = {"kaplan", "rzeznik", "zerca"}             ## rodzaje z atlasem z TRELLIS-a: decymacja z `--uvkeep`
SURFACE_WEIGHTS = {"rzeznik"}

KINDS = {
    "wolek": ("wolek_01_rig.glb", False, None, 6000, 1024),
    # elity F4 (TRELLIS 2 → rig_trellis.py): szkieletowane statyczne siatki z art_src/enemies_f4
    "kaplan": ("../../enemies_f4/kaplan_rig.glb", False, None, 20000, 2048),
    "rzeznik": ("../../enemies_f4/rzeznik_rig.glb", False, None, 30000, 2048),
    "zerca": ("../../enemies_f4/zerca_rig.glb", False, None, 20000, 2048),
    "slepiec": ("slepiec_01_rig.glb", False, None, 6000, 1024),
    "podsluchacz": ("podsluchacz_01_rig.glb", False, None, 6000, 1024),
    "stalker": ("stalker_01_rig.glb", False, None, 6000, 1024),
    "skoczek": ("skoczek_01_rig.glb", False, None, 6000, 1024),
    "trzosek": ("trzosek_01_anims.glb", True, None, 6000, 1024),
    "cma": ("cma_01.glb", False, -90.0, 6000, 1024),
    "nest": ("nest_01.glb", False, 0.0, 6000, 1024),
    "vein": ("vein_01.glb", False, -90.0, 14000, 2048),
    "leech": ("leech_01.glb", False, 0.0, 14000, 2048),
}


def run_in_blender():
    import bpy
    sys.path.insert(0, HERE)
    from enemy_mesh_repair import normalize_weights, skin_by_surface_distance, weld_seams

    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]
    faces = int(next((a.split("=")[1] for a in argv if a.startswith("--faces=")), 6000))
    tex = int(next((a.split("=")[1] for a in argv if a.startswith("--tex=")), 1024))
    anim = "--anim" in argv
    uvkeep = "--uvkeep" in argv
    surface_weights = "--surface-weights" in argv
    rot = next((float(a.split("=")[1]) for a in argv if a.startswith("--rot=")), None)      # model statyczny: obrót wokół pionu (°)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    if rot is None:
        for o in list(bpy.data.objects):
            if o.type == "MESH" and len(o.vertex_groups) == 0:
                bpy.data.objects.remove(o, do_unlink=True)
        body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    else:
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        body = max(meshes, key=lambda o: len(o.data.vertices))
        for o in meshes:
            if o is not body:
                bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.objects.active = body

    # Osobne indeksy UV nie są osobnymi kawałkami ciała. Bez scalenia Decimate
    # otwiera tysiące szczelin; UV nadal żyją osobno na narożnikach ścian.
    weld_seams(body)
    if surface_weights:
        arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        skin_by_surface_distance(body, arm, {1: "mixamorig:RightHand"})

    def reduce_mesh(obj, budget):
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("dec", "DECIMATE")
        obj.data.calc_loop_triangles()
        mod.ratio = min(1.0, budget / max(len(obj.data.loop_triangles), 1))
        if uvkeep:
            mod.delimit = {"UV"}
        while obj.modifiers[0] != mod:
            bpy.ops.object.modifier_move_up(modifier=mod.name)
        bpy.ops.object.modifier_apply(modifier=mod.name)

    if surface_weights:
        # Pełny tasak ma więcej trójkątów niż ciało. Wspólna proporcja
        # zużywała połowę budżetu na ostrze: 25k dla ciała, 5k dla tasaka.
        prop_material = body.data.materials[1]
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="MATERIAL")
        bpy.ops.object.mode_set(mode="OBJECT")
        parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
        if len(parts) != 2:
            raise RuntimeError("Rzeźnik wymaga oddzielnego materiału ciała i tasaka")
        for part in parts:
            is_prop = part.data.materials[part.data.polygons[0].material_index] == prop_material
            reduce_mesh(part, faces // 6 if is_prop else faces - faces // 6)
            if not is_prop: body = part
        bpy.ops.object.select_all(action="DESELECT")
        for part in parts: part.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
    else:
        reduce_mesh(body, faces)
    body.data.validate()
    if body.vertex_groups:
        normalize_weights(body)
    print("FACES", len(body.data.polygons))

    if rot is not None:
        from mathutils import Matrix
        r = Matrix.Rotation(math.radians(rot), 3, "Z")
        pts = [r @ (body.matrix_world @ v.co) for v in body.data.vertices]
        body.parent = None
        body.matrix_world = Matrix.Identity(4)
        zmin = min(p.z for p in pts)
        cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
        cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
        for v, p in zip(body.data.vertices, pts):
            v.co = (p.x - cx, p.y - cy, p.z - zmin)
        body.data.update()
        print("SIZE", max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts), max(p.z for p in pts) - zmin)

    mat = body.data.materials[0]
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = 0.0
    for i in list(bpy.data.images):
        if i.size[0] > tex or i.size[1] > tex:
            i.scale(tex, tex)
        print("IMG", i.name, tuple(i.size))

    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88,
                              export_animations=anim, export_apply=False)
    print("OK", dst)


def main():
    only = next((a.split("=")[1].split(",") for a in sys.argv[1:] if a.startswith("--only=")), list(KINDS))
    exe = os.environ.get("BLENDER")
    if not exe and os.name == "nt":
        found = sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe"))
        exe = found[-1] if found else None
    exe = exe or shutil.which("blender")
    if not exe:
        raise SystemExit("Nie znaleziono Blendera (ustaw BLENDER=ścieżka)")
    os.makedirs(OUT, exist_ok=True)
    for k in only:
        f, anim, rot, faces, tex = KINDS[k]
        cmd = [exe, "-b", "--factory-startup", "--python-exit-code", "1", "-P", os.path.abspath(__file__), "--", os.path.join(SRC, f), os.path.join(OUT, k + ".glb"),
               "--faces=%d" % faces, "--tex=%d" % tex]
        if anim:
            cmd.append("--anim")
        if k in UVKEEP:
            cmd.append("--uvkeep")
        if k in SURFACE_WEIGHTS:
            cmd.append("--surface-weights")
        if rot is not None:
            cmd.append("--rot=%s" % rot)
        print(">>", k)
        subprocess.run(cmd, check=True)


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        main()
    else:
        run_in_blender()
