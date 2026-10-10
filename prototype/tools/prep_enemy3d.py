"""Przygotowuje model wroga 3D (rig z Tripo) do renderu w czasie rzeczywistym w widoku 3D gry (`enemy3d.gd`).

Uruchomienie (z korzenia repo, Blender w PATH): python prototype/tools/prep_enemy3d.py [--only=wolek,slepiec]
albo bezpośrednio: blender -b --factory-startup -P prototype/tools/prep_enemy3d.py -- SRC.glb DST.glb [--faces=6000] [--tex=1024] [--anim]
Co robi: usuwa śmieciowe siatki (bez wag kości), upraszcza siatkę (Decimate, wagi zostają), zmniejsza tekstury do --tex px i eksportuje GLB.
Skala zostaje natywna (pozy w `enemy3d.gd` używają stałych z tego samego modelu, co wypiek 2D w `concept/monster_tripo_bake.py`); wysokość
dopasowuje gra w czasie działania. --anim: zachowuje animację z pliku (Trzosek — „preset:quadruped:walk").
"""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_src", "enemies", "tripo")
OUT = os.path.join(ROOT, "prototype", "art", "enemy3d")

# rodzaj: (plik źródłowy, animacja z pliku)
KINDS = {
    "wolek": ("wolek_01_rig.glb", False),
    "slepiec": ("slepiec_01_rig.glb", False),
    "podsluchacz": ("podsluchacz_01_rig.glb", False),
    "stalker": ("stalker_01_rig.glb", False),
    "skoczek": ("skoczek_01_rig.glb", False),
    "trzosek": ("trzosek_01_anims.glb", True),
}


def run_in_blender():
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]
    faces = int(next((a.split("=")[1] for a in argv if a.startswith("--faces=")), 6000))
    tex = int(next((a.split("=")[1] for a in argv if a.startswith("--tex=")), 1024))
    anim = "--anim" in argv

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and len(o.vertex_groups) == 0:
            bpy.data.objects.remove(o, do_unlink=True)
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = body

    mod = body.modifiers.new("dec", "DECIMATE")
    mod.ratio = min(1.0, faces / max(len(body.data.polygons), 1))
    while body.modifiers[0] != mod:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print("FACES", len(body.data.polygons))

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
        f, anim = KINDS[k]
        cmd = [exe, "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--", os.path.join(SRC, f), os.path.join(OUT, k + ".glb")]
        if anim:
            cmd.append("--anim")
        print(">>", k)
        subprocess.run(cmd, check=True)


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
        run_in_blender()
    except ImportError:
        main()
