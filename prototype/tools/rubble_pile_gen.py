"""Zawał z symulacji fizyki (BARRIER_FIX_PLAN.md B0): po złamaniu stempla urwał się fragment stropu nad przejściem — górną krawędzią
został przy stropie nad tylną ścianą, dolną oparł się o podłogę przed płaszczyzną postaci i zamyka przejście od podłogi do stropu.
To, co odpadło przy urwaniu (rozkruszona stopa płyty, brzeg dziury w stropie), spada i układa się u jej stóp w symulacji brył
sztywnych Blendera (Bullet), więc każdy kawałek na czymś leży, a gruzu tyle, ile ubyło z płyty.

Dwa zestawy wg stropu nad strefą (view3d.gd `_cave_set`):
  concrete — budynek (strop „C”): płyta betonu na prętach zbrojenia, które trzymają ją przy stropie; w gruzie cegły;
  mine     — kopalnia (strop „#”): skalny blok oparty o strop, połamane deski okładziny (wiszą ze stropu i leżą w gruzie), ziemia.

Ograniczenia z widoku gry (kamera z przodu, postacie w płaszczyźnie y = −0,1 tuż obok kafla przegrody):
  * poza kaflem (|x| > EDGE) kawałek wyższy od LOW nie może wystawać przed postacie (y < −CHAR_GAP) — zasłoniłby je;
  * żaden nie spada z przedniej krawędzi terenu (y < −FRONT_EDGE);
kawałek, który je łamie, próbuje jeszcze kilka razy w innym miejscu, potem wypada.

Po odkopaniu (gra usuwa przegrodę): płyta rozbita na płaty leżące płasko za płaszczyzną postaci razem z resztą gruzu (druga
symulacja; ograniczenie postaci wszędzie — przejście jest wolne); ze stropu zwisają pręty (beton) albo deska (kopalnia). Oba stany
w jednym pliku:
  A_Wall (płyta), A_Rebar, A_Wood, A_Earth, A_Fall0..2, A_Brick0..1 — przed odkopaniem;
  B_Rebar, B_Wood, B_Earth, B_Fall0..2, B_Brick0..1 — po odkopaniu.
Układ: x w prawo, z w górę, y w głąb (kamera od −y); (0, 0, 0) = podłoga na osi przegrody, 0,6 m za jej płaszczyzną (view3d.gd
`RUBBLE_CORE_BACK`); tylna ściana w y ≈ 2,0. Materiały: outer (lico), inner (przełom), brick, rebar / rock, rock_in, wood, earth —
gra podmienia je na własne (bez UV, triplanarne).

Wynik: prototype/art/items3d/rubble_pile_<zestaw>_r<rzędy>_<wariant>.glb (warianty różnią się ziarnem i skosem płyty).

    blender -b --factory-startup -P prototype/tools/rubble_pile_gen.py
    blender -b --factory-startup -P prototype/tools/rubble_pile_gen.py -- concrete 5 0     # jeden plik: zestaw, rzędy, wariant
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "items3d")

T = 16.0 * 1.8 / 22.0          # kafel gry [m] (Level3D.T)
ROWS = (4, 5)                  # wysokości przejść z zawałem na mapach (z1_m3: 4, z1_m1 i z1_m2: 5)
VARIANTS = 2
SETS = ("concrete", "mine")
EDGE = 0.55 * T                # brzeg kafla przegrody z zapasem
CHAR_GAP = 0.15                # poza kaflem kawałek najdalej tyle przed y = 0 (postacie w y = −0,1)
FRONT_EDGE = 1.15              # przednia krawędź terenu (DEPTH_FRONT 1,1 + 0,1 − 0,1)
LOW = 0.22                     # m: kawałek niższy od tego może leżeć przed postaciami (zasłania najwyżej buty)
BACK = 2.0                     # tylna ściana tunelu
SLAB_W = 0.72                  # m: pół szerokości płyty (ok. kafla 1,31 m — poszarpane boki)
LEAN = 0.17                    # przechył w bok: górna krawędź o LEAN · h od osi, po stronie `side` (z dala od stempla) — z kamery
                               # z przodu widać płytę, której jeden koniec opadł, a nie słup
TOP_Y = 1.8                    # górna krawędź płyty przy stropie, tuż przed tylną ścianą
FOOT_Y = -0.2                  # stopa płyty na podłodze, tuż przed płaszczyzną postaci (w kaflu)
SLAB_T = {"concrete": 0.16, "mine": 0.24}
CELL = {"concrete": (0.24, 0.5), "mine": (0.3, 0.45)}   # komórki: przy stopie i przy krawędzi urwania / reszta płyty
HANG = {"concrete": 0.3, "mine": 0.0}                    # m (wzdłuż płyty): prześwit pod stropem, w którym płyta wisi na prętach
DENSITY = {"concrete": 2400.0, "mine": 2600.0, "brick": 1800.0, "wood": 550.0}


def _clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _voronoi_cell(lo, hi, pts, i, reach):
    """Komórka `i` w prostopadłościanie lo–hi (płyta w układzie własnym: grubość wzdłuż z): przycięta symetralnymi do punktów bliżej
    niż `reach`. Szerokie ściany płyty (±z) = lico, reszta = przełom."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = hi - lo
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(lo + hi) * 0.5, verts=bm.verts)
    for f in bm.faces:
        f.material_index = 0 if abs(f.normal.z) > 0.5 else 1
    p = pts[i]
    for j, q in enumerate(pts):
        if j == i or (q - p).length > reach or not bm.verts:
            continue
        n = (q - p).normalized()
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(p + q) * 0.5, plane_no=n, clear_outer=True)
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if len(cut) >= 3:
            for f in bmesh.ops.holes_fill(bm, edges=cut, sides=0)["faces"]:
                f.material_index = 1
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm


def _object(name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)       # zaślepki cięć (holes_fill) bywają odwrócone — w grze czarne od środka
    c = sum((v.co for v in bm.verts), Vector()) / max(1, len(bm.verts))
    bmesh.ops.translate(bm, vec=-c, verts=bm.verts)
    vol = abs(bm.calc_volume())
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for poly in me.polygons:
        poly.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    ob.location = c
    bpy.context.scene.collection.objects.link(ob)
    ob["vol"] = vol
    return ob


def _box(name, size, mats, mat_index=0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    for f in bm.faces:
        f.material_index = mat_index
    return _object(name, bm, mats)


def _rigid(ob, kind, material="concrete", friction=0.85):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.rigidbody.object_add(type=kind)
    rb = ob.rigid_body
    rb.collision_shape = "CONVEX_HULL" if kind == "ACTIVE" else ("BOX" if ob.name.startswith("Guard") else "MESH")   # nieruchome: jedna złączona siatka
    rb.use_margin = True
    rb.collision_margin = 0.004
    rb.friction = friction
    rb.restitution = 0.03
    if kind == "ACTIVE":
        rb.mass = max(0.3, ob["vol"] * DENSITY[material])
        rb.linear_damping = 0.25
        rb.angular_damping = 0.45
        rb.use_deactivation = True
        rb.deactivate_linear_velocity = 0.06
        rb.deactivate_angular_velocity = 0.1


def _simulate(frames):
    sc = bpy.context.scene
    if sc.rigidbody_world is None:
        bpy.ops.rigidbody.world_add()
    w = sc.rigidbody_world
    w.substeps_per_frame = 20
    w.solver_iterations = 30
    w.point_cache.frame_start = 1
    w.point_cache.frame_end = frames
    sc.frame_start = 1
    sc.frame_end = frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    out = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in sc.objects:
        out[ob.name] = ob.evaluated_get(dg).matrix_world.copy()
    return out


def _tree(ob, mw):
    vs = [mw @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return BVHTree.FromPolygons(vs, [tuple(p.vertices) for p in ob.data.polygons]), lo, hi


def _hits(a, b):
    """Czy bryły (drzewo, lo, hi) się przenikają: ściany się przecinają albo jedna w drugiej (pudełko w pudełku)."""
    if any(a[1][k] > b[2][k] or b[1][k] > a[2][k] for k in range(3)):
        return False
    if a[0].overlap(b[0]):
        return True
    inside = all(a[1][k] >= b[1][k] and a[2][k] <= b[2][k] for k in range(3)) or all(b[1][k] >= a[1][k] and b[2][k] <= a[2][k] for k in range(3))
    return inside


def _join(name, items):
    """Jeden obiekt z siatek `items` ([(obiekt, macierz)]) z wpieczonymi położeniami; materiały wspólne."""
    verts, faces, mat_idx, mats = [], [], [], []
    for ob, mw in items:
        base = len(verts)
        verts.extend(mw @ v.co for v in ob.data.vertices)
        for poly in ob.data.polygons:
            faces.append([base + k for k in poly.vertices])
            m = ob.data.materials[poly.material_index]
            if m not in mats:
                mats.append(m)
            mat_idx.append(mats.index(m))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    for m in mats:
        me.materials.append(m)
    for k, poly in enumerate(me.polygons):
        poly.material_index = mat_idx[k]
        poly.use_smooth = False
    me.validate()
    return bpy.data.objects.new(name, me)


def _world_verts(ob, mw):
    return [mw @ v.co for v in ob.data.vertices]


def _rod(name, a, b, mats, r=0.011):
    """Pręt zbrojenia od `a` do `b` (walec sześciokątny)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=r, radius2=r, depth=(b - a).length)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=bm.verts)
    for f in bm.faces:
        f.material_index = 0
    return _object(name, bm, mats)




def _slab_frame(h, side, rng):
    """[macierz układu płyty → świat, długość płyty]: u = x (stopa i górna krawędź poziomo — płyta ścięta w równoległobok),
    v = wzdłuż płyty od stopy ku stropowi, w = grubość (ku kamerze i w górę). Górna krawędź przy stropie nad tylną ścianą,
    przesunięta w bok o LEAN · h po stronie `side`; wariant obraca płytę lekko wokół pionu."""
    d = Vector((side * LEAN * h, TOP_Y - FOOT_Y, h))
    length = d.length
    d.normalize()
    n = Vector((1.0, 0.0, 0.0)).cross(d).normalized()
    base = Matrix(((1.0, d.x, n.x, 0.0), (0.0, d.y, n.y, FOOT_Y), (0.0, d.z, n.z, 0.0), (0.0, 0.0, 0.0, 1.0)))
    foot = Vector((side * rng.uniform(0.0, 0.05), FOOT_Y, 0.0))
    yaw = Matrix.Translation(foot) @ Matrix.Rotation(side * rng.uniform(0.03, 0.07), 4, "Z") @ Matrix.Translation(-Vector((0.0, FOOT_Y, 0.0)))
    return yaw @ base, length


def _connected(walls, anchors):
    """Komórki płyty połączone (przez stykające się komórki) z kotwicą — podłogą albo stropem; reszta odpada."""
    box = {}
    for w in walls:
        vs = [v.co + w.location for v in w.data.vertices]
        box[w.name] = (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))) - Vector((0.01, 0.01, 0.01)),
                       Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))) + Vector((0.01, 0.01, 0.01)))
    todo = [w for w in walls if w.name in anchors]
    seen = {w.name for w in todo}
    while todo:
        a = todo.pop()
        la, ha = box[a.name]
        for b in walls:
            if b.name in seen:
                continue
            lb, hb = box[b.name]
            if all(la[k] <= hb[k] and lb[k] <= ha[k] for k in range(3)) and _touch(a, b):
                seen.add(b.name)
                todo.append(b)
    return [w for w in walls if w.name in seen]


def _touch(a, b):
    """Czy komórki się stykają: najbliższy wierzchołek jednej do drugiej bliżej niż 1 cm (komórki Voronoi dzielą ściany)."""
    ta = BVHTree.FromPolygons([v.co + a.location for v in a.data.vertices], [tuple(p.vertices) for p in a.data.polygons])
    for v in b.data.vertices:
        if ta.find_nearest(v.co + b.location, 0.01)[0] is not None:
            return True
    return False


def _mound(name, rx, ry, hz, cy, mats, rng):
    """Kopiec ziemi (kopalnia): spłaszczona półkula z falującym obrysem, środek w (0, cy), podstawa tuż pod podłogą."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0)
    ph = [rng.uniform(0.0, 6.3) for _ in range(4)]
    for v in bm.verts:
        a = math.atan2(v.co.y, v.co.x)
        k = 1.0 + 0.13 * math.sin(3.0 * a + ph[0]) + 0.07 * math.sin(7.0 * a + ph[1]) + 0.05 * math.sin(5.0 * v.co.z + ph[2])
        v.co = Vector((v.co.x * rx * k, v.co.y * ry * k + cy, max(0.0, v.co.z) * hz * (1.0 + 0.15 * math.sin(4.0 * a + ph[3])) - 0.02))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    for f in bm.faces:
        f.material_index = 0
    return _object(name, bm, mats)


def _board(name, a, b, mats, w=0.14, t=0.035):
    """Deska okładziny od `a` do `b` (przekrój w × t)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((w, t, (b - a).length)), verts=bm.verts)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=bm.verts)
    for f in bm.faces:
        f.material_index = 0
    return _object(name, bm, mats)


def build(kind, rows, variant, attempt, path):
    """Jeden zawał do pliku `path`; zwraca, jaka część gruzu z płyty została w kupie (reszta odrzucona przez ograniczenia widoku)."""
    h = rows * T
    rng = random.Random(1000 * rows + 37 * variant + 5 + 7919 * attempt + (0 if kind == "concrete" else 500009))
    _clear()
    mine = kind == "mine"
    face = bpy.data.materials.new("rock" if mine else "outer")
    brk = bpy.data.materials.new("rock_in" if mine else "inner")
    brick = bpy.data.materials.new("brick")
    rebar = bpy.data.materials.new("rebar")
    wood = bpy.data.materials.new("wood")
    earth = bpy.data.materials.new("earth")
    side = 1.0 if variant % 2 == 0 else -1.0
    t = SLAB_T[kind]
    hang = HANG[kind]
    m_slab, length = _slab_frame(h, side, rng)

    # --- płyta w układzie własnym: komórki Voronoi (punkty w środku grubości — komórki na przestrzał), dalej od osi poszarpane boki;
    # stopa rozkruszona o podłogę, przy stropie urwana (beton: prześwit `hang` na prętach; kopalnia: oparta o strop) i brzeg dziury
    lo, hi = Vector((-SLAB_W - 0.06, -0.4, 0.0)), Vector((SLAB_W + 0.06, length + 0.35, t))
    c0, c1 = CELL[kind]
    pts = []
    for _ in range(20000):
        p = Vector((rng.uniform(lo.x, hi.x), rng.uniform(lo.y, hi.y), t * 0.5))
        s = c0 if p.y < 0.9 or p.y > length - hang - 0.6 else c1
        if all((q - p).length > s * 0.85 for q in pts if abs(q.y - p.y) < 0.8):
            pts.append(p)
    side_off = {}
    walls, falls = [], []
    for i, p in enumerate(pts):
        bm = _voronoi_cell(lo, hi, pts, i, 1.5 * c1)
        if len(bm.faces) < 4:
            bm.free()
            continue
        c = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        kv = round(c.y / 0.35)
        side_off.setdefault(kv, rng.uniform(-0.2, 0.05) if mine else rng.uniform(-0.12, 0.04))
        top = length - hang
        out = c.y < 0.0 or c.y > top or abs(c.x) > SLAB_W + side_off[kv] or (c.y < 0.45 and rng.random() < 0.3)
        ob = _object(("F%03d" if out else "W%03d") % i, bm, [face, brk])
        ob["v"] = c.y
        (falls if out else walls).append(ob)
    anchors = set()
    for w in walls:
        vs = [m_slab @ (v.co + w.location) for v in w.data.vertices]
        if min(v.z for v in vs) < 0.04 or w.location.y > length - hang - 0.7:
            anchors.add(w.name)
    kept = _connected(walls, anchors)
    for w in walls:
        if w not in kept:
            w.name = "F" + w.name[1:]
            falls.append(w)
    walls = kept
    if mine:                                                 # skała: komórki przesunięte w grubości — uskoki jak warstwy, nie gładka płyta
        for w in walls:
            w.location.z += rng.uniform(-0.07, 0.07)
    loc_a = {w.name: w.location.copy() for w in walls}       # druga symulacja przestawia płaty — eksport płyty z tych położeń
    for ob in falls:
        ob["tint"] = rng.randrange(3)
    fall_vol = sum(o["vol"] for o in falls)

    # --- beton: pręty z urwanej krawędzi do stropu (na nich płyta wisi) i z poszarpanych boków; kopalnia: deski okładziny ze stropu
    rods, hangs, extra = [], [], []
    hang_rods = []
    if not mine:
        for k in range(6):
            u = -SLAB_W * 0.8 + k * (1.6 * SLAB_W / 5.0) + rng.uniform(-0.05, 0.05)
            a = m_slab @ Vector((u, length - hang - 0.12, t * 0.5))
            b = m_slab @ Vector((u + rng.uniform(-0.12, 0.12), length + 0.06, t * 0.5))
            mid = (a + b) * 0.5 + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.08, 0.08), 0.0))
            rods += [_rod("R%02da" % k, a, mid, [rebar]), _rod("R%02db" % k, mid, b, [rebar])]
        for k in range(4):
            sg = -1.0 if k % 2 == 0 else 1.0
            v = rng.uniform(1.0, length - 1.6)
            a = m_slab @ Vector((sg * (SLAB_W - 0.12), v, t * 0.5))
            b = m_slab @ Vector((sg * (SLAB_W + rng.uniform(0.12, 0.3)), v + rng.uniform(-0.25, 0.25), t * 0.5 + rng.uniform(-0.1, 0.1)))
            rods.append(_rod("R%02ds" % k, a, b, [rebar]))
        for k in range(7):                                   # po odkopaniu: kikuty prętów zwisające ze stropu, gdzie płyta była przyczepiona
            a = Vector((side * LEAN * h + rng.uniform(-SLAB_W, SLAB_W), TOP_Y + rng.uniform(-0.15, 0.1), h + 0.03))
            mid = a + Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.15, 0.05), -rng.uniform(0.2, 0.45)))
            b = mid + Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.2, 0.1), -rng.uniform(0.08, 0.3)))
            hang_rods += [_rod("H%02da" % k, a, mid, [rebar]), _rod("H%02db" % k, mid, b, [rebar])]
        for i in range(40):
            extra.append(_box("K%03d" % i, (0.25 if i % 5 else 0.125, 0.12, 0.065), [brick]))
    else:
        for k in range(3):                                   # okładzina stropu: połamane deski wiszą przed górą bloku
            a = Vector((side * LEAN * h * 0.8 + rng.uniform(-0.7, 0.7), rng.uniform(TOP_Y - 1.1, TOP_Y - 0.3), h - 0.03))
            dirn = Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.6, 0.2), -1.0)).normalized()
            hangs.append(_board("Hw%02d" % k, a, a + dirn * rng.uniform(0.8, 1.5), [wood]))
        for i in range(6):
            extra.append(_box("D%03d" % i, (rng.uniform(0.5, 1.1), 0.14, 0.035), [wood]))
    for ob in extra:
        ob["tint"] = rng.randrange(2)
    mound_a = _mound("EarthA", 1.25, 0.8, 0.36, 0.4, [earth], rng) if mine else None
    mound_b = _mound("EarthB", 1.55, 0.85, 0.2, 0.55, [earth], rng) if mine else None

    floor = _box("Guard_floor", (14.0, 8.0, 1.0), [brk])
    floor.location = Vector((0.0, 0.0, -0.5))
    ceiling = _box("Guard_ceil", (14.0, 8.0, 1.0), [brk])
    ceiling.location = Vector((0.0, 0.0, h + 0.5))
    backw = _box("Guard_back", (14.0, 1.0, h + 2.0), [brk])
    backw.location = Vector((0.0, BACK + 0.5, h * 0.5))
    m0 = {}

    def mat_of(ob):
        return {"K": "brick", "D": "wood"}.get(ob.name[0], kind)

    def run(active, still, frames):
        """Symulacja `active` na nieruchomym podłożu: podłoga, strop, tylna ściana i `still` ([(obiekt, macierz)]) w jednej siatce."""
        sc = bpy.context.scene
        if sc.rigidbody_world is not None:
            bpy.ops.rigidbody.world_remove()
        ground = _join("Ground", still) if still else None
        passive = [floor, ceiling, backw]
        if ground is not None:
            sc.collection.objects.link(ground)
            passive.append(ground)
        for ob in passive:
            _rigid(ob, "PASSIVE")
        for ob in active:
            ob.matrix_world = m0[ob.name]
            _rigid(ob, "ACTIVE", mat_of(ob), 1.0)
        mats = _simulate(frames)
        for ob in list(active) + passive:
            bpy.ops.object.select_all(action="DESELECT")
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.rigidbody.object_remove()
        if ground is not None:
            bpy.data.objects.remove(ground, do_unlink=True)
        return mats

    def violates(ob, mw, everywhere):
        """0 = leży dobrze; 1 = przed postaciami (poza kaflem — po odkopaniu wszędzie — wyżej niż kostki); 2 = z krawędzi."""
        vs = _world_verts(ob, mw)
        if any(v.y < -FRONT_EDGE or v.z < -0.3 for v in vs):
            return 2
        if max(v.z for v in vs) > h - 0.05 or min(v.z for v in vs) > 2.0:   # wyrzucony w górę albo jeszcze w locie
            return 3
        if max(v.z for v in vs) > LOW and any((everywhere or abs(v.x) > EDGE) and v.y < -CHAR_GAP for v in vs):
            return 1
        return 0

    def drop(order, still, trees, spot, everywhere, wave, flat):
        """Fale po `wave` kawałków tuż nad tym, co już leży (mały spadek — zwarta kupa); co osiadło, staje się nieruchome dla
        następnych. Kawałek, który łamie ograniczenia widoku, próbuje jeszcze 4 razy w innym miejscu, potem wypada."""
        alive, tries, why = [], {}, [0, 0, 0, 0]
        mats_out = {}
        while order:
            batch, order = order[:wave], order[wave:]
            placed = []
            for ob in batch:
                x, y = spot(ob, tries.get(ob.name, 0))
                if flat(ob):                                 # płat płyty kładzie się płasko (grubość w osi z układu własnego)
                    rot = (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(-math.pi, math.pi))
                else:
                    rot = (rng.uniform(-math.pi, math.pi), rng.uniform(-0.6, 0.6), rng.uniform(-math.pi, math.pi))
                m = Matrix.LocRotScale(Vector((x, y, 0.05)), Euler(rot, "XYZ"), None)
                for _ in range(400):                        # w górę po 6 cm, aż nic nie przenika — potem jeszcze 12 cm spadku
                    tr = _tree(ob, m)
                    if not any(_hits(tr, p) for p in trees + placed):
                        break
                    m.translation.z += 0.06
                m.translation.z += 0.12
                m0[ob.name] = m
                placed.append(_tree(ob, m))
            mats = run(batch, still, 100)
            for ob in batch:
                bad = violates(ob, mats[ob.name], everywhere)
                if bad:
                    why[bad] += 1
                    tries[ob.name] = tries.get(ob.name, 0) + 1
                    if tries[ob.name] < 5:
                        order.append(ob)
                    continue
                ob.matrix_world = mats[ob.name]
                mats_out[ob.name] = mats[ob.name].copy()
                still.append((ob, mats[ob.name].copy()))
                trees.append(_tree(ob, mats[ob.name]))
                alive.append(ob)
        print("[RUBBLE]   leży %d, odrzucone %d razy (przed postaciami %d, z krawędzi %d, w locie %d)" % (len(alive), sum(why), why[1], why[2], why[3]))
        return alive, mats_out

    # --- przed odkopaniem: to, co odpadło, u stóp płyty — przed nią w kaflu, obok płyty za płaszczyzną postaci
    still_a = [(w, m_slab @ Matrix.Translation(w.location)) for w in walls] + [(o, Matrix.Translation(o.location)) for o in hangs]
    if mound_a is not None:
        still_a.append((mound_a, Matrix.Translation(mound_a.location)))
    trees_a = [_tree(o, mw) for o, mw in still_a]
    order = []
    falls.sort(key=lambda o: -o["vol"])
    for k, ob in enumerate(falls):
        order.append(ob)
        order += extra[k * 2:k * 2 + 2]
    order += extra[len(falls) * 2:]

    def spot_a(ob, tries):
        """Kawałek spada pod miejsce, z którego odpadł: stopa — przed płytą w kaflu, boki płyty — pod nimi, brzeg dziury w
        stropie — pod nią, obok górnej krawędzi płyty (w głębi, po stronie przechyłu); cegły i deski wokół stopy."""
        if ob.name.startswith("F"):
            f = max(0.0, min(1.0, ob["v"] / length))
            x = ob.location.x * 0.8 + side * LEAN * h * f + rng.gauss(0.0, 0.2)
            y = FOOT_Y + (TOP_Y - FOOT_Y) * f * 0.8 + rng.uniform(-0.3, 0.3)
        else:
            x = max(-1.7, min(1.7, rng.gauss(-side * 0.1, 0.6)))
            y = rng.uniform(-0.62, 1.3)
        if tries:
            x *= 0.6                                         # następna próba bliżej osi
        if abs(x) < EDGE * 0.95 and y < 0.1:
            return x, rng.uniform(-0.62, -0.32) + 0.08 * tries
        return x, max(0.12, min(1.7, y))

    alive, ma = drop(order, still_a, trees_a, spot_a, False, 8, lambda o: False)
    kept_vol = sum(o["vol"] for o in alive if o.name.startswith("F"))

    # --- po odkopaniu: płyty nie ma — jej płaty leżą płasko za płaszczyzną postaci, na nich reszta gruzu
    still_b = [(o, Matrix.Translation(o.location)) for o in hangs]
    if mound_b is not None:
        still_b.append((mound_b, Matrix.Translation(mound_b.location)))
    trees_b = [_tree(o, mw) for o, mw in still_b]

    def spot_b(ob, tries):
        return max(-3.4, min(3.4, rng.gauss(0.0, 1.5))), rng.uniform(0.08, 1.9) + 0.05 * tries   # szeroko i płasko: przejście wolne

    order_b = sorted(walls + alive, key=lambda o: -o["vol"])
    for w in walls:
        w["tint"] = rng.randrange(3)
    after, mb = drop(order_b, still_b, trees_b, spot_b, True, 12, lambda o: o.name.startswith("W"))

    # --- eksport: siatki połączone w grupy, położenia wpieczone
    groups = {"A_Wall": [(w, m_slab @ Matrix.Translation(loc_a[w.name])) for w in walls],
              "A_Rebar": [(r_, Matrix.Translation(r_.location)) for r_ in rods],
              "B_Rebar": [(r_, Matrix.Translation(r_.location)) for r_ in hang_rods]}
    for st in ("A", "B"):
        groups["%s_Wood" % st] = [(o, Matrix.Translation(o.location)) for o in hangs]
    if mine:
        groups["A_Earth"] = [(mound_a, Matrix.Translation(mound_a.location))]
        groups["B_Earth"] = [(mound_b, Matrix.Translation(mound_b.location))]
    for st, src, mm in (("A", alive, ma), ("B", after, mb)):
        for ob in src:
            if ob.name.startswith("K"):
                g = "%s_Brick%d" % (st, ob["tint"] % 2)
            elif ob.name.startswith("D"):
                g = "%s_Wood" % st
            else:
                g = "%s_Fall%d" % (st, ob["tint"])
            groups.setdefault(g, []).append((ob, Matrix(mm[ob.name])))
    out_objs = [_join(g, items) for g, items in groups.items() if items]
    for ob in list(bpy.context.scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for ob in out_objs:
        bpy.context.scene.collection.objects.link(ob)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_animations=False,
                              export_materials="EXPORT", export_texcoords=False)
    print("[RUBBLE] %s r%d v%d: płyta %d komórek, odpadło %.2f m³ (w kupie %.2f m³), w kupie %d kawałków, po odkopaniu %d -> %s"
          % (kind, rows, variant, len(walls), fall_vol, kept_vol, len(alive), len(after), path))
    return kept_vol / max(0.001, fall_vol)


def _best(kind, rows, variant, want=0.6, attempts=3):
    """Układ, w którym w kupie zostaje co najmniej `want` gruzu, który odpadł (kolejne ziarna; najlepszy z `attempts`)."""
    path = os.path.join(OUT, "rubble_pile_%s_r%d_%d.glb" % (kind, rows, variant))
    best, best_k = -1.0, 0
    for k in range(attempts):
        tmp = path.replace(".glb", "_try%d.glb" % k)
        ratio = build(kind, rows, variant, k, tmp)
        if ratio > best:
            best, best_k = ratio, k
        if ratio >= want:
            break
    for k in range(attempts):
        tmp = path.replace(".glb", "_try%d.glb" % k)
        if k == best_k:
            os.replace(tmp, path)
        elif os.path.exists(tmp):
            os.remove(tmp)
    print("[RUBBLE] %s r%d v%d: wybrany układ %d, w kupie %.0f%% gruzu" % (kind, rows, variant, best_k, best * 100.0))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) >= 3:
        _best(argv[0], int(argv[1]), int(argv[2]))
        return
    for kind in SETS:
        for r in ROWS:
            for v in range(VARIANTS):
                _best(kind, r, v)


main()
