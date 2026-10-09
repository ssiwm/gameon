"""Przygotowuje WSZYSTKIE modele 3D gry (postacie i bronie) do renderu w czasie rzeczywistym — patrz prep_char3d.py / prep_gun3d.py.

Uruchomienie (z korzenia repo, Blender w PATH): python prototype/tools/prep_char3d_all.py [--guns] [--chars] [--only=m83,p64]
Długości broni to 0,8 × długość sprite'a 2D (broń w grze jest „komiksowo" duża; 3D trzymana dwiema rękami musi mieścić się w zasięgu ramion).
Ułamki chwytów (tylna dłoń fx/fz) pochodzą z arkusza guns.png (tools/concept/weapons_hd_bake.py geometry()); łoże = tylna + 0,31 (karabiny).
Pola: długość m, chwyt tylny (fx, fz), chwyt przedni (fx, fz) lub None = jedna ręka, flip lufy (heurystyka kolby się myli).
"""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "prototype", "art", "char3d")
SRC_W = os.path.join(ROOT, "art_src", "weapons", "tripo")
SRC_C = os.path.join(ROOT, "art_src", "characters", "tripo")

# klucz: (model źródłowy, długość m, rear_fx, rear_fz, fore_fx, fore_fz, rąk, flip)
GUNS = {
    "m83":      ("m83",      1.28, 0.30, 0.50, 0.64, 0.40, 2, False),
    "spread12": ("spread12", 1.28, 0.33, 0.53, 0.64, 0.45, 2, False),
    "p64":      ("p64",      0.75, 0.26, 0.50, None, None, 1, False),
    "srut8":    ("srut8",    1.28, 0.33, 0.53, 0.64, 0.45, 2, False),
    "lr7":      ("lr7",      1.24, 0.34, 0.50, 0.65, 0.45, 2, False),
    "hkm9":     ("hkm9",     1.15, 0.37, 0.53, 0.66, 0.45, 2, False),
    "gniew4":   ("gniew4",   1.18, 0.36, 0.45, 0.64, 0.50, 2, False),
    "sokol6":   ("sokol6",   1.15, 0.37, 0.53, 0.66, 0.45, 2, False),
    "widmo1":   ("lr7",      1.30, 0.33, 0.47, 0.64, 0.45, 2, False),      # brak własnego modelu — zastępczo LR-7
    "ciegno6":  ("ciegno6",  1.18, 0.36, 0.60, 0.62, 0.55, 2, False),
    "maczeta":  ("maczeta",  1.10, 0.18, 0.50, None, None, 1, False),
    "kilof":    ("kilof",    0.80, 0.23, 0.50, None, None, 1, True),
}
CHARS = [f"{g}_{o}" for g in ("male", "female") for o in ("scav", "hazmat", "medic")]


def blender_exe():
    exe = os.environ.get("BLENDER")
    if not exe and os.name == "nt":
        found = sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe"))
        exe = found[-1] if found else None
    exe = exe or shutil.which("blender")
    if not exe:
        raise SystemExit("Nie znaleziono Blendera (ustaw BLENDER=ścieżka)")
    return exe


def run(args):
    r = subprocess.run([blender_exe(), "-b", "--factory-startup", "-P"] + args, capture_output=True, text=True)
    bad = [l for l in (r.stdout + r.stderr).splitlines() if "Traceback" in l or "Error:" in l]
    if r.returncode != 0 or bad:
        print("\n".join(bad) or r.stdout[-800:])
        raise SystemExit("Blender zgłosił błąd")


def main():
    a = sys.argv[1:]
    only = next((x.split("=", 1)[1].split(",") for x in a if x.startswith("--only=")), None)
    do_guns = "--guns" in a or "--chars" not in a
    do_chars = "--chars" in a or "--guns" not in a
    if do_chars:
        for c in CHARS:
            if only and c not in only:
                continue
            run([os.path.join(HERE, "prep_char3d.py"), "--", os.path.join(SRC_C, c + "_01_rig.glb"), os.path.join(OUT, c + ".glb")])
            print("OK", c)
    if do_guns:
        for k, (src, ln, rfx, rfz, ffx, ffz, hands, flip) in GUNS.items():
            if only and k not in only:
                continue
            args = [os.path.join(HERE, "prep_gun3d.py"), "--", os.path.join(SRC_W, src + "_01.glb"), os.path.join(OUT, f"gun_{k}.glb"),
                    str(ln), str(rfx), str(rfz), str(ffx if ffx is not None else rfx), str(ffz if ffz is not None else rfz), f"--hands={hands}"]
            if flip:
                args.append("--flip")
            run(args)
            print("OK", k)


if __name__ == "__main__":
    main()
