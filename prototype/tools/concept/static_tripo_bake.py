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
ONLY = args[5].split(",") if len(args) > 5 else None          # tylko wskazane animacje (podgląd)
os.makedirs(OUT, exist_ok=True)

# frame = rozmiar klatki w pikselach świata (jak w starym arkuszu), fit = (oś, rozmiar potwora w pikselach świata), ppw = pikseli na piksel świata
SPEC = {
    "cma": {"frame": (26, 20), "fit": ("width", 18.0), "ppw": 8.0, "anims": [("idle", 4), ("sleep", 1)]},
    "nest": {"frame": (40, 34), "fit": ("height", 30.0), "ppw": 8.0, "anims": [("pulse", 3)]},
    "vein": {"frame": (128, 80), "fit": ("height", 66.0), "ppw": 5.0, "anims": [("dormant", 4), ("idle", 6), ("open", 4), ("windup", 3), ("spit", 3)]},
    "leech": {"frame": (96, 80), "fit": ("height", 66.0), "ppw": 4.0, "anims": [("idle", 8), ("peek", 4), ("strike", 6), ("grab", 6), ("spit", 6), ("hurt", 2), ("dive", 5), ("death", 8)]},
}[kind]


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- Pijawka (leech): deformacja w układzie modelu (X = przód, w stronę paszczy; Y = bok; Z = góra)
LEECH_SPINE = [0.059, 0.031, 0.030, 0.014, -0.021, -0.027, -0.041, -0.066, -0.058, -0.049, -0.043, -0.027, -0.014, 0.000, 0.006, 0.017, 0.008, 0.022, 0.032, 0.046, 0.053]
LEECH_MOUTH = (0.085, 0.0, 0.78)     # środek paszczy: x (m), y (m), z (ułamek wysokości)
LEECH_MOUTH_R = 0.058                # promień paszczy (m)


def _lerp(a, b, t):
    return a + (b - a) * t


def spine_x(t):
    """Środek przekroju ciała (x) na wysokości t = z/H (0..1) — linia, wokół której działa fala skurczu."""
    f = min(max(t, 0.0), 1.0) * (len(LEECH_SPINE) - 1)
    k = min(int(f), len(LEECH_SPINE) - 2)
    return _lerp(LEECH_SPINE[k], LEECH_SPINE[k + 1], f - k)


def leech_pose(anim, i):
    """Parametry klatki: yaw (° obrotu wokół pionu; −90 = paszcza w kamerę), bend (rad, + = do przodu), dz (ułamek H), sz (rozciągnięcie w pionie),
    close/wide (zamknięcie / otwarcie paszczy 0..1), amp/ph (fala skurczu), shake (m, drgania boku), headtilt (rad, dodatkowe zgięcie samej głowy), ox (m, przesunięcie w kadrze — skok w bok nie może wyjść poza klatkę)."""
    P = dict(yaw=-50.0, bend=0.0, dz=0.0, sz=1.0, close=0.0, wide=0.0, amp=0.0, ph=0.0, shake=0.0, headtilt=0.0, ox=0.0)
    if anim == "idle":                       # 8 kl., pętla: oddech, fala skurczu od ogona do głowy, paszcza pulsuje
        a = i / 8.0 * math.tau
        P.update(bend=0.07 * math.sin(a), sz=1.0 + 0.018 * math.sin(a + 1.0), amp=0.07, ph=a, wide=0.10 + 0.10 * (0.5 + 0.5 * math.sin(a * 2.0)), yaw=-50.0 + 4.0 * math.sin(a))
    elif anim == "peek":                     # 4 kl., pętla: zapowiedź zasadzki — nad wodą tylko czubek głowy, paszcza zamknięta, zerka
        P.update(yaw=-75.0 + 6.0 * math.sin(i / 4.0 * math.tau), dz=-0.70 + 0.012 * math.sin(i / 4.0 * math.tau), close=0.75, bend=-0.15, amp=0.05, ph=i * 1.5)
    elif anim == "strike":                   # 6 kl.: skulona → wyrzut w przód z paszczą szeroko → odbicie. Trafienie na klatce 2.
        P.update(yaw=[-70.0, -55.0, -22.0, -20.0, -30.0, -42.0][i], dz=[-0.45, -0.20, 0.02, 0.0, -0.02, 0.0][i], bend=[-0.55, -0.25, 0.60, 0.65, 0.40, 0.22][i], ox=[0.0, 0.0, -0.06, -0.06, -0.03, 0.0][i],
                 sz=[0.94, 1.08, 1.10, 1.05, 1.0, 1.0][i], close=[0.7, 0.4, 0.0, 0.0, 0.0, 0.0][i], wide=[0.0, 0.15, 0.7, 0.75, 0.45, 0.25][i], amp=0.07, ph=i * 1.3)
    elif anim == "grab":                     # 6 kl., pętla: głowa nisko, szarpie ofiarą i żuje (paszcza na przemian otwarta i zaciśnięta)
        a = i / 6.0 * math.tau
        P.update(yaw=-30.0, bend=0.42 + 0.07 * math.sin(a * 2.0), headtilt=0.12 + 0.08 * math.sin(a * 2.0 + 1.0), ox=-0.05, shake=0.012 * math.sin(a * 2.0), amp=0.09, ph=a * 2.0,
                 wide=0.6 if i % 2 == 0 else 0.0, close=0.0 if i % 2 == 0 else 0.5, sz=1.0 + 0.03 * math.sin(a * 2.0))
    elif anim == "spit":                     # 6 kl.: wychodzi z wody odchylona w tył, gardło nabrzmiewa, wyrzut (klatka 3), odrzut
        P.update(yaw=[-60.0, -60.0, -48.0, -25.0, -30.0, -45.0][i], dz=[-0.45, -0.18, 0.0, 0.0, 0.0, 0.0][i], bend=[-0.3, -0.45, -0.55, 0.35, 0.2, 0.05][i], ox=[0.0, 0.0, 0.0, -0.03, -0.02, 0.0][i],
                 close=[0.6, 0.25, 0.0, 0.0, 0.0, 0.0][i], wide=[0.0, 0.2, 0.6, 0.85, 0.5, 0.2][i], amp=[0.06, 0.12, 0.16, 0.05, 0.05, 0.05][i], ph=[0.0, 1.5, 3.0, 4.5, 5.0, 5.5][i],
                 sz=[1.06, 1.05, 1.05, 0.96, 1.0, 1.0][i])
    elif anim == "hurt":                     # 2 kl.: ściska się i odskakuje
        P.update(yaw=-50.0, bend=[-0.14, -0.05][i], sz=[0.92, 0.97][i], wide=[0.45, 0.25][i], amp=0.05, ph=i * 2.0, shake=[0.010, -0.005][i])
    elif anim == "dive":                     # 5 kl.: zwija się i opada pod wodę
        P.update(yaw=[-50.0, -55.0, -60.0, -65.0, -70.0][i], bend=[0.12, -0.10, -0.25, -0.35, -0.35][i], dz=[-0.05, -0.30, -0.58, -0.80, -0.97][i], close=[0.2, 0.5, 0.7, 0.75, 0.75][i],
                 sz=[1.04, 1.05, 1.03, 1.0, 1.0][i], amp=0.06, ph=i * 1.2)
    elif anim == "death":                    # 8 kl.: drgawki, szeroko otwarta paszcza, upada do przodu i tonie
        P.update(yaw=[-50.0, -45.0, -40.0, -35.0, -30.0, -30.0, -30.0, -30.0][i], bend=[-0.35, 0.20, -0.55, 0.40, 0.80, 1.00, 1.10, 1.15][i], ox=[0.0, 0.0, 0.0, -0.02, -0.04, -0.05, -0.05, -0.05][i], dz=[0.0, 0.0, 0.0, -0.05, -0.15, -0.35, -0.60, -0.85][i],
                 wide=[0.5, 0.7, 0.85, 0.85, 0.75, 0.6, 0.4, 0.2][i], shake=[0.014, -0.012, 0.016, -0.010, 0.006, 0.0, 0.0, 0.0][i], amp=[0.10, 0.10, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0][i], ph=i * 2.2,
                 sz=[1.0, 1.04, 0.96, 1.05, 1.0, 1.0, 1.0, 1.0][i])
    return P


def leech_deform(anim, i, rest, H):
    P = leech_pose(anim, i)
    mx, my, mzf = LEECH_MOUTH
    mz = mzf * H
    R = LEECH_MOUTH_R
    px, pz = spine_x(0.1), 0.10 * H                       # zawias zgięcia: dolna część ciała
    yaw = math.radians(P["yaw"])
    cy_, sy_ = math.cos(yaw), math.sin(yaw)
    out = []
    for x, y, z in rest:
        t = min(max(z / H, 0.0), 1.0)
        # 1) paszcza: ściągnięcie (close) / rozwarcie (wide) wokół środka otworu, tylko z przodu głowy
        d = math.hypot(y - my, z - mz)
        w = (1.0 - smooth(0.8 * R, 1.7 * R, d)) * smooth(0.0, 0.05, x)
        f = 1.0 - 0.85 * P["close"] * w + 0.55 * P["wide"] * w
        y = my + (y - my) * f
        z = mz + (z - mz) * f
        # 2) fala skurczu: przekrój pulsuje wokół osi ciała, fala biegnie od ogona do głowy
        c = spine_x(t)
        s = 1.0 + P["amp"] * math.sin(math.tau * 2.2 * t - P["ph"])
        x = c + (x - c) * s
        y *= s
        # 3) rozciągnięcie w pionie (squash & stretch: objętość z grubsza zachowana)
        z *= P["sz"]
        k = 1.0 / math.sqrt(P["sz"])
        x = c + (x - c) * k
        y *= k
        # 4) zgięcie wokół zawiasu (kąt rośnie z wysokością), dodatkowe pochylenie samej głowy
        tt = min(max((z / H - 0.1) / 0.9, 0.0), 1.0)
        a = P["bend"] * tt ** 1.3 + P["headtilt"] * smooth(0.55, 0.95, t)
        dx, dz = x - px, z - pz
        x = px + dx * math.cos(a) + dz * math.sin(a)
        z = pz - dx * math.sin(a) + dz * math.cos(a)
        # 5) drgania boku (szarpanie ofiary / agonia) rosnące z wysokością
        y += P["shake"] * t * t
        # 6) przesunięcie w pionie (wynurzanie / zanurzanie) i obrót wokół pionu (kierunek, w którym patrzy paszcza)
        z += P["dz"] * H
        out.append((x * cy_ - y * sy_ + P["ox"], x * sy_ + y * cy_, z))
    return out


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
        out = leech_deform(anim, i, rest, H)
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
        if ONLY is not None and anim not in ONLY:
            continue
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
