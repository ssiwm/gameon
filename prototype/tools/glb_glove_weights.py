"""Poprawka wag rękawic w gotowych postaciach MPFB (art/char3d/mpfb/*.glb) bez przebudowy w Blenderze.

Rękawice MPFB („toigo_gloves_short”) mają w prawej rękawicy kilkanaście wierzchołków przypiętych do obojczyka (RightShoulder), 0,7 m od niego.
Gdy ręka idzie w górę, te wierzchołki zostają przy obojczyku i rozciągają rękawicę w długie „pręty” od dłoni do bioder. Skrypt przepina wagi
rękawic z kości spoza ręki (obojczyk, tułów) na dłoń tej strony, zmieniając wyłącznie bajty JOINTS_n / WEIGHTS_n w buforze — reszta pliku
zostaje bajt w bajt (tekstury, siatki, szkielet). Generator (`char_mpfb.py`, `fix_glove_weights`) robi to samo przy budowie postaci.

    python prototype/tools/glb_glove_weights.py prototype/art/char3d/mpfb/*.glb [--check]
--check: tylko raport (kod wyjścia 1, gdy coś jest do poprawy).
"""
import json
import struct
import sys

ARM = ("Hand", "ForeArm", "Arm")            # kości, do których rękawica może być przypięta (z palcami: *Hand*)
COMP = {5121: ("B", 1), 5123: ("H", 2), 5126: ("f", 4)}


def _side_of(name):
    for s in ("Left", "Right"):
        if s in name:
            return s
    return ""


def patch(path, check):
    data = open(path, "rb").read()
    magic, ver, total = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path
    jlen, jtype = struct.unpack_from("<II", data, 12)
    gl = json.loads(data[20:20 + jlen])
    bin_off = 20 + jlen + 8
    buf = bytearray(data)
    nodes = gl["nodes"]
    fixed = 0
    for ni, node in enumerate(nodes):
        if "mesh" not in node or "skin" not in node:
            continue
        mesh = gl["meshes"][node["mesh"]]
        if "gloves" not in mesh.get("name", "") and "gloves" not in node.get("name", ""):
            continue
        joints = gl["skins"][node["skin"]]["joints"]
        jname = [nodes[j].get("name", "") for j in joints]
        hand = {s: next(i for i, n in enumerate(jname) if n.endswith(s + "Hand")) for s in ("Left", "Right")}
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pairs = [(attrs["JOINTS_%d" % k], attrs["WEIGHTS_%d" % k]) for k in range(4) if "JOINTS_%d" % k in attrs]
            for ja, wa in pairs:
                A, W = gl["accessors"][ja], gl["accessors"][wa]
                bj, bw = gl["bufferViews"][A["bufferView"]], gl["bufferViews"][W["bufferView"]]
                jf, js = COMP[A["componentType"]]
                wf, ws = COMP[W["componentType"]]
                jstride = bj.get("byteStride", 4 * js)
                wstride = bw.get("byteStride", 4 * ws)
                j0 = bin_off + bj.get("byteOffset", 0) + A.get("byteOffset", 0)
                w0 = bin_off + bw.get("byteOffset", 0) + W.get("byteOffset", 0)
                for v in range(A["count"]):
                    jo, wo = j0 + v * jstride, w0 + v * wstride
                    js_ = list(struct.unpack_from("<4" + jf, buf, jo))
                    wv = list(struct.unpack_from("<4" + wf, buf, wo))
                    # strona rękawicy: kość ręki o największej wadze w tym wierzchołku
                    side = ""
                    best = -1.0
                    for k in range(4):
                        n = jname[js_[k]]
                        if wv[k] > best and any(a in n for a in ARM) and _side_of(n):
                            best, side = wv[k], _side_of(n)
                    changed = False
                    for k in range(4):
                        n = jname[js_[k]]
                        if wv[k] > 0 and not any(a in n for a in ARM):
                            s = side or _side_of(n)
                            if not s:
                                continue
                            h = hand[s]
                            if h in js_:                                   # dłoń już jest w innym slocie: dodaj tam wagę
                                m = js_.index(h)
                                wv[m] += wv[k]
                                wv[k] = 0
                            else:
                                js_[k] = h
                            changed = True
                    if changed:
                        fixed += 1
                        if not check:
                            struct.pack_into("<4" + jf, buf, jo, *js_)
                            struct.pack_into("<4" + wf, buf, wo, *wv)
    print("%s: %d wierzchołków rękawic do przepięcia%s" % (path, fixed, "" if check else " — poprawione"))
    if fixed and not check:
        open(path, "wb").write(bytes(buf))
    return fixed


def main():
    check = "--check" in sys.argv
    todo = sum(patch(p, check) for p in sys.argv[1:] if p.endswith(".glb"))
    sys.exit(1 if (check and todo) else 0)


if __name__ == "__main__":
    main()
