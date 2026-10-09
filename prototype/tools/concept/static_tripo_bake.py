"""Bake modeli statycznych (bez rigu) z Tripo do klatek HD: Ćma (machanie skrzydłami), gniazdo (pulsowanie), bossowie Żyła i Pijawka (procedura: oddech, wychylenia, pochylenia).
Animacja = deformacja wierzchołków w Pythonie (bez szkieletu), render albedo + normalne świata jak w monster_tripo_bake.py.

Uruchomienie: blender -b --factory-startup -P prototype/tools/concept/static_tripo_bake.py -- KIND GLB OUT [ROT_Z_DEG] [CAM]   (Żyła: vein art_src/enemies/tripo/vein_01.glb OUT -90)
    KIND = cma | nest | vein | leech; ROT_Z = obrót modelu wokół pionu (czoło modelu w prawo kadru); CAM = −Y (domyślnie) | +Y | −X | +X
Wynik: OUT/KIND_<anim>_<i>.png (+ _n.png). Pakuje: tools/pack_monsters_hd.py (ppw wynika z rozmiaru klatki starego arkusza).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
kind, glb, OUT = args[:3]
ROT_Z = float(args[3]) if len(args) > 3 else 0.0
CAM = args[4] if len(args) > 4 else "-Y"
os.makedirs(OUT, exist_ok=True)

# frame = rozmiar klatki w pikselach świata (jak w starym arkuszu), fit = (oś, rozmiar potwora w pikselach świata), ppw = pikseli na piksel świata
SPEC = {
    "cma": {"frame": (26, 20), "fit": ("width", 18.0), "ppw": 8.0, "anims": [("idle", 4), ("sleep", 1)]},
    "nest": {"frame": (40, 34), "fit": ("height", 30.0), "ppw": 8.0, "anims": [("pulse", 3)]},
    "vein": {"frame": (128, 80), "fit": ("height", 66.0), "ppw": 5.0, "anims": [("dormant", 4), ("idle", 6), ("open", 4), ("windup", 3), ("spit", 3)]},
    "leech": {"frame": (96, 80), "fit": ("height", 66.0), "ppw": 6.0, "anims": [("rise", 4), ("idle", 6), ("grab", 3), ("dead", 1)]},
}[kind]


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def deform(kind, anim, i, n, rest, bb):
    """Zwraca listę nowych współrzędnych (x, y, z) wierzchołków dla klatki — `rest` w układzie modelu po ustawieniu na podłodze (z=0 u dołu, środek w x,y=0)."""
    ph = i / max(n, 1)
    H = bb["h"]
    out = []
    if kind == "nest":
        k = math.sin(ph * math.tau)
        for x, y, z in rest:
            out.append((x * (1 + 0.04 * k), y * (1 + 0.04 * k), z * (1 + 0.06 * k)))
    elif kind == "cma":
        # skrzydła leżą w płaszczyźnie YZ (ćma stoi twarzą do widza): machanie = obrót wokół pionowej osi ciała (o ±), sen = skrzydła złożone (większy kąt), do góry nogami
        ang = {"idle": [38.0, 8.0, -26.0, 8.0], "sleep": [70.0]}[anim][i]
        for x, y, z in rest:
            w = smooth(0.012, 0.045, abs(y))
            a = math.radians(ang) * w * (1 if y > 0 else -1)
            c, s = math.cos(a), math.sin(a)
            xr, yr = x * c - y * s, x * s + y * c
            out.append((xr, yr, z))
    elif kind == "vein":
        # Widok z przodu (ROT_Z −90: twarz do kamery, jak symetryczna sylwetka starego arkusza). Szczęka: ZAMKNIĘTA (jaw < 0: dolna szczęka unosi się do górnej,
        # kły się zazębiają) w uśpieniu, bezczynności i zapowiedzi ataku; OTWARTA (jaw > 0: dolna szczęka opada, wielka jama) w oknie podatności (`open`)
        # i przy pluciu. Paszcza = słaby punkt bossa (boss.gd: maw_open) — jej stan musi być czytelny na pierwszy rzut oka.
        k = math.sin(ph * math.tau)
        jaw = {"dormant": [-1.0] * 4, "idle": [-1.0] * 6, "open": [0.75, 1.0, 1.1, 0.95], "windup": [-0.9, -0.75, -0.55], "spit": [0.45, 0.9, 0.65]}[anim][i]
        for x, y, z in rest:
            sx = sy = sz = 1.0
            if anim == "dormant":                 # przycupnięta: niższa, szersza
                sz, sx, sy = 0.80 + 0.012 * k, 1.04, 1.04
            elif anim == "idle":
                sz, sx = 1.0 + 0.020 * k, 1.0 - 0.006 * k
            elif anim == "open":                  # unosi się i rozdyma
                sz, sx = 1.0 + 0.045 * (0.5 + 0.5 * math.sin(ph * math.pi)), 1.0 + 0.02 * ph
            elif anim == "windup":                # unosi się i kurczy przed plunięciem
                sz, sx = 1.05 + 0.02 * ph, 1.0 - 0.015 * ph
            elif anim == "spit":                  # wyrzut ku widzowi: większy w kadrze
                sz = sx = 1.03 + 0.03 * math.sin(ph * math.pi)
            oy = 0.0
            dz = 0.0
            if y < 0.05:                          # przednia strona (twarz; kamera po stronie −Y)
                wl = math.exp(-((x / 0.14) ** 2 + ((z - 0.585) / 0.075) ** 2))        # dolna szczęka (kły dolne, podbródek)
                wu = math.exp(-((x / 0.14) ** 2 + ((z - 0.70) / 0.05) ** 2))          # górna warga
                if jaw >= 0.0:
                    dz = -0.085 * wl * jaw + 0.020 * wu * jaw
                    oy = -0.03 * wl * jaw
                else:
                    dz = 0.052 * wl * -jaw - 0.022 * wu * -jaw
            out.append((x * sx, y * sy + oy, (z + dz) * sz))
    elif kind == "leech":
        for x, y, z in rest:
            t = z / H
            ox, oz, sc = 0.0, 0.0, 1.0
            if anim == "rise":                    # wynurza się: rośnie od 40% do 100% wysokości
                f = [0.45, 0.65, 0.85, 1.0][i]
                sc = f
            elif anim == "idle":
                ox = 0.045 * H * math.sin(ph * math.tau + 2.0 * t) * t
            elif anim == "grab":                  # rzut do przodu
                f = [0.2, 0.55, 0.9][i]
                ox = 0.40 * H * f * t * t
                oz = -0.10 * H * f * t * t
            elif anim == "dead":                  # opada bezwładnie
                ox = 0.55 * H * t * t
                oz = -0.40 * H * t * t
            out.append((x * sc + ox, y * sc, z * sc + oz))
    return out


def pass_material(src, normal):
    m = src.copy()
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for l in list(nt.links):
        if l.to_node == out:
            nt.links.remove(l)
    em = nt.nodes.new("ShaderNodeEmission")
    if normal:
        nm = next((n for n in nt.nodes if n.type == "NORMAL_MAP"), None)
        ma = nt.nodes.new("ShaderNodeVectorMath")
        ma.operation = "MULTIPLY_ADD"
        ma.inputs[1].default_value = (0.5, 0.5, 0.5)
        ma.inputs[2].default_value = (0.5, 0.5, 0.5)
        if nm is not None:
            nt.links.new(nm.outputs["Normal"], ma.inputs[0])
        else:
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            nt.links.new(geo.outputs["Normal"], ma.inputs[0])
        nt.links.new(ma.outputs["Vector"], em.inputs["Color"])
    else:
        link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color"), None)
        if link is not None:
            nt.links.new(link.from_socket, em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not mesh:
            bpy.data.objects.remove(o)
    # wierzchołki w świecie → obrót wokół pionu → postawienie na podłodze i wyśrodkowanie
    r = Matrix.Rotation(math.radians(ROT_Z), 3, "Z")
    pts = [r @ (mesh.matrix_world @ v.co) for v in mesh.data.vertices]
    mesh.parent = None
    mesh.matrix_world = Matrix.Identity(4)
    # usuń podstawkę (płytę pod modelem), jeśli Tripo ją dodał: wierzchołki w dolnych 4% wysokości o dużej rozpiętości
    zmin = min(p.z for p in pts)
    cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
    cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
    rest = [(p.x - cx, p.y - cy, p.z - zmin) for p in pts]
    bb = {"w": max(p[0] for p in rest) - min(p[0] for p in rest), "h": max(p[2] for p in rest)}
    sc = bpy.context.scene
    fit_axis, fit_wp = SPEC["fit"]
    ext = bb["w"] if fit_axis == "width" else bb["h"]
    m_per_wp = ext / fit_wp
    fw, fh = SPEC["frame"]
    PPW = SPEC["ppw"]
    FW, FH = int(fw * PPW), int(fh * PPW)
    ortho = max(fw, fh) * m_per_wp
    ppm = max(FW, FH) / ortho
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x, sc.render.resolution_y = FW, FH
    sc.world = bpy.data.worlds.new("w")
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    cz = FH * 0.5 / ppm if kind != "cma" else bb["h"] * 0.5            # ćma lata: wyśrodkowana w pionie, reszta stoi na dole kadru
    loc, rot = {"-Y": ((0, -9, cz), (90, 0, 0)), "+Y": ((0, 9, cz), (90, 0, 180)), "-X": ((-9, 0, cz), (90, 0, -90)), "+X": ((9, 0, cz), (90, 0, 90))}[CAM]
    cam.location, cam.rotation_euler = loc, tuple(math.radians(a) for a in rot)
    orig = mesh.data.materials[0]
    mats = {False: pass_material(orig, False), True: pass_material(orig, True)}
    print("INFO %s w=%.3f h=%.3f m_per_wp=%.4f frame=%dx%d" % (kind, bb["w"], bb["h"], m_per_wp, FW, FH))
    for anim, n in SPEC["anims"]:
        for i in range(n):
            new = deform(kind, anim, i, n, rest, bb)
            if kind == "cma" and anim == "sleep":                       # wisi do góry nogami pod sufitem kadru
                top = FH / ppm
                new = [(x, y, top - z) for x, y, z in new]
            for v, (x, y, z) in zip(mesh.data.vertices, new):
                v.co = (x, y, z)
            mesh.data.update()
            base = f"{OUT}/{kind}_{anim}_{i}"
            for normal, suffix, vt in ((False, "", "Standard"), (True, "_n", "Raw")):
                mesh.data.materials[0] = mats[normal]
                sc.view_settings.view_transform = vt
                sc.render.filepath = f"{base}{suffix}.png"
                bpy.ops.render.render(write_still=True)
        print("BAKED", kind, anim, n)
    print("DONE-STATIC")


main()
