"""Kompresja VRAM tekstur modeli 3D (ustawienia w plikach *.import obok tekstur wyciągniętych z GLB).

Godot przy imporcie GLB wyciąga tekstury do plików obok modelu z `compress/mode=0` (bez strat, w pamięci wideo nieskompresowane RGBA8)
i `detect_3d/compress_to=1`. Przełączenie na kompresję VRAM po wykryciu użycia w 3D robi tylko edytor — import headless
(`godot --headless --import`, nasz zwykły tryb pracy) zostawia RGBA8. Test wydajności 2026-10-17: 371 takich tekstur = ok. 714 MB pamięci wideo
więcej (z1_m2, RTX 3080). Ten skrypt ustawia `compress/mode=2` (VRAM: S3TC/BPTC na PC, ETC2/ASTC na mobile) i wyłącza detekcję; mapy normalnych
(wg `normalTexture` w materiałach GLB, a w braku GLB — po nazwie z „normal") dostają `compress/normal_map=1` (kanały RG, bez sRGB).
Kompresja dzieje się przy imporcie (pliki .ctex w .godot/imported), więc działa też w wyeksportowanym buildzie.

Użycie (z prototype/): python tools/tex_vram.py [--check]  → potem godot --headless --path . --import
  --check: tylko wypisuje tekstury bez kompresji i kończy kodem 1, jeśli są (do CI / przed commitem).
"""
import glob
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
DIRS = ["art/enemy3d", "art/items3d", "art/world3d", "art/char3d"]


def image_source(texture):
    """WebP/KTX2 zapisują źródło w rozszerzeniu, zamiast w podstawowym polu glTF `source`."""
    if "source" in texture:
        return texture["source"]
    extensions = texture.get("extensions", {})
    for key in ("EXT_texture_webp", "KHR_texture_basisu"):
        if key in extensions:
            return extensions[key].get("source", -1)
    return -1


def glb_json(path):
    with open(path, "rb") as f:
        d = f.read(20)
        n = struct.unpack("<I", d[12:16])[0]
        return json.loads(f.read(n))


def normal_files(d):
    """Nazwy plików tekstur (bez rozszerzenia), które są mapami normalnych, wg materiałów GLB w katalogu `d`.
    Godot nazywa wyciągnięte obrazy `<model>_<nazwa obrazu>`, a powtórzoną nazwę obrazu uzupełnia o `_<indeks>`."""
    out = set()
    for g in glob.glob(os.path.join(d, "*.glb")):
        model = os.path.splitext(os.path.basename(g))[0]
        try:
            j = glb_json(g)
        except (OSError, ValueError, struct.error):
            continue
        images = j.get("images", [])
        seen = {}
        names = []
        for i, im in enumerate(images):
            nm = im.get("name", "image_%d" % i)
            names.append(nm if nm not in seen else "%s_%d" % (nm, i))
            seen[nm] = True
        textures = j.get("textures", [])
        # MPFB potrafi użyć obrazu brwi jednocześnie jako albedo i normalnej; nie niszczymy wtedy kanałów koloru kompresją RG.
        color_sources = set()
        for m in j.get("materials", []):
            for ct in (m.get("pbrMetallicRoughness", {}).get("baseColorTexture"), m.get("emissiveTexture")):
                if ct is not None and 0 <= ct.get("index", -1) < len(textures):
                    color_sources.add(image_source(textures[ct["index"]]))
        for m in j.get("materials", []):
            nt = m.get("normalTexture")
            if nt is None or not 0 <= nt.get("index", -1) < len(textures):
                continue
            src = image_source(textures[nt["index"]])
            if 0 <= src < len(names) and src not in color_sources:
                out.add("%s_%s" % (model, names[src]))
    return out


def main():
    check = "--check" in sys.argv
    os.chdir(ROOT)
    changed = 0
    bad = []
    stale = []
    # Zestawy postaci (np. mpfb) i kolejne modele mogą leżeć w podkatalogach; płaski glob pomijał ich tekstury w CI.
    asset_dirs = [d for base in DIRS for d, _, _ in os.walk(base)]
    for d in sorted(asset_dirs):
        normals = normal_files(d)
        for f in sorted(glob.glob(os.path.join(d, "*.import"))):
            if f.endswith(".glb.import"):
                continue
            with open(f, encoding="utf-8") as fh:
                s = fh.read()
            if 'importer="texture"' not in s:
                continue
            base = os.path.basename(f)[: -len(".import")]
            stem = os.path.splitext(base)[0]
            is_normal = stem in normals or "normal" in stem.lower()
            want = s.replace("\ncompress/mode=0\n", "\ncompress/mode=2\n").replace("\ncompress/mode=1\n", "\ncompress/mode=2\n")
            want = want.replace("\ndetect_3d/compress_to=1", "\ndetect_3d/compress_to=0")
            if is_normal:
                want = want.replace("\ncompress/normal_map=0\n", "\ncompress/normal_map=1\n")
            if want != s:
                bad.append(f.replace("\\", "/"))
                if not check:
                    with open(f, "w", encoding="utf-8", newline="\n") as fh:
                        fh.write(want)
                    changed += 1
            elif "\ncompress/mode=2\n" in s and '"vram_texture": false' in s:
                # parametry już VRAM, ale [remap] z importu sprzed zmiany (ścieżka do .ctex bez kompresji): import i tak przepisze plik, a cofnięcie
                # tej zmiany zostawia grę bez tekstury („Unable to open file … .ctex”) — po imporcie trzeba zatwierdzić przepisany .import
                stale.append(f.replace("\\", "/"))
    if check:
        for b in bad:
            print("bez kompresji VRAM:", b)
        for b in stale:
            print("nieaktualny [remap] (zaimportuj i zatwierdź .import):", b)
        print("tekstur do poprawy: %d" % (len(bad) + len(stale)))
        sys.exit(1 if bad or stale else 0)
    for b in stale:
        print("nieaktualny [remap] — po imporcie zatwierdź:", b)
    print("zmienione pliki .import: %d (teraz: godot --headless --path . --import)" % changed)


if __name__ == "__main__":
    main()
