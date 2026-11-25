"""Rig i klipy Łupacza. Uruchom z katalogu repozytorium (Blender 5.2):
blender -b -P prototype/tools/rig_lupacz.py -- art_src/enemies/meshy/lupacz_shell_retopped.glb katalog_wynikowy [--variant=shell|fur]
Wejście po prep_enemy3d.py: przód +X, stopy na Z=0, --rot=90 --faces=30000 --tex=2048 --uvkeep.
Jednostki punktów szkieletu odpowiadają źródłu Meshy. Kształt i ruch eksportujemy razem w metrach.

Warianty (`VARIANTS`): „shell” (od 1.7.682, domyślny) — łysy kret bez oczu w skorupie z łupka (lupacz_shell_retopped.glb, wizualizacja
`reports/lupacz-pancerz-2026-11-25`): niższe ciało, krótsze łapy, dłuższy ogon; skorupa dzielona na trzy powierzchnie płyt `Plate0`
(kark z hełmem), `Plate1` (środek), `Plate2` (zad) — `enemy3d.gd` zamienia rozbitą płytę w surowe ciało (enemy_mole.gd, maska `shell`).
„fur” — pierwszy model w futrze (lupacz_retopped.glb, 1.7.647–1.7.681), bez płyt.
"""
from pathlib import Path
import colorsys
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

UNIT = 1.65 / 1.90346
FPS = 24
TAU = math.tau
AX = Vector((1, 0, 0))
AY = Vector((0, 1, 0))
AZ = Vector((0, 0, 1))
_args = sys.argv[sys.argv.index('--') + 1:]
source, destination = map(Path, [a for a in _args if not a.startswith('--')][:2])
destination.mkdir(exist_ok=True, parents=True)
VARIANT_NAME = next((a.split('=')[1] for a in _args if a.startswith('--variant=')), 'shell')

# Punkty szkieletu, wagi i zasięg ruchu łap dla każdej siatki. `spine`: (kość, rodzic, głowa, ogon); `front` / `hind`: bark, łokieć,
# nadgarstek, czubek pazura (strona +y); `axis`: kości tułowia wzdłuż osi x; `limb`: progi wag nóg; `reach`: mnożnik drogi przednich
# łap w ciosie i kopaniu (krótsze łapy), `stride`: mnożnik kroku. Wartości „shell” zmierzone z przekrojów siatki (2026-11-25).
VARIANTS = {
    'fur': {
        'spine': [('Hips','Root',(-.46,0,.47),(-.27,0,.58)), ('Spine','Hips',(-.27,0,.58),(.02,0,.72)), ('Chest','Spine',(.02,0,.72),(.30,0,.79)),
                  ('Neck','Chest',(.30,0,.79),(.51,0,.80)), ('Head','Neck',(.51,0,.80),(.93,0,.56)), ('Tail','Hips',(-.47,0,.42),(-.72,0,.24)),
                  ('TailEnd','Tail',(-.72,0,.24),(-.93,.015,.18))],
        'front': [(.24,.285,.66),(.17,.368,.365),(.435,.327,.106),(.665,.330,.040)],
        'hind': [(-.37,.280,.56),(-.13,.352,.325),(-.245,.345,.096),(-.035,.370,.040)],
        'axis': [(-.90,'TailEnd'),(-.65,'Tail'),(-.39,'Hips'),(-.12,'Spine'),(.18,'Chest'),(.42,'Neck'),(.64,'Head')],
        'tail_clamp': (.51, -.49),
        'limb': {'lateral': (.065,.27), 'low': (.38,.75), 'x_in': (-.61,-.38), 'x_out': (.66,.86), 'front_mix': (.002,.15),
                 'upper_front': (.23,.52), 'upper_hind': (.21,.47), 'wrist_front': .425, 'wrist_hind': -.245, 'paw_z': (.075,.195), 'paw_x': (.12,.045)},
        'reach': 1.0, 'stride': 1.0, 'plates': False,
    },
    'shell': {
        'spine': [('Hips','Root',(-.45,0,.36),(-.25,0,.42)), ('Spine','Hips',(-.25,0,.42),(.05,0,.46)), ('Chest','Spine',(.05,0,.46),(.38,0,.48)),
                  ('Neck','Chest',(.38,0,.48),(.58,0,.48)), ('Head','Neck',(.58,0,.48),(.96,0,.52)), ('Tail','Hips',(-.52,0,.30),(-.74,0,.17)),
                  ('TailEnd','Tail',(-.74,0,.17),(-.95,0,.10))],
        'front': [(.26,.24,.38),(.23,.29,.20),(.40,.30,.07),(.62,.31,.03)],
        'hind': [(-.37,.21,.35),(-.20,.25,.20),(-.30,.25,.075),(-.14,.26,.03)],
        'axis': [(-.90,'TailEnd'),(-.68,'Tail'),(-.42,'Hips'),(-.15,'Spine'),(.20,'Chest'),(.48,'Neck'),(.66,'Head')],
        'tail_clamp': (.30, -.55),
        'limb': {'lateral': (.10,.24), 'low': (.24,.40), 'x_in': (-.60,-.46), 'x_out': (.70,.80), 'front_mix': (-.04,.08),
                 'upper_front': (.13,.30), 'upper_hind': (.12,.30), 'wrist_front': .40, 'wrist_hind': -.30, 'paw_z': (.05,.13), 'paw_x': (.10,.04)},
        'reach': .62, 'stride': .75, 'plates': True,
        # skorupa: ciemny, chłodny łupek (jasność < SHELL_V albo niebieskawy odcień) nad krawędzią `skirt` i przed szyją;
        # grzbiet ponad `top` zawsze; podział na płyty po x (zad | środek | kark)
        'shell': {'skirt': .26, 'x': (-.66, .52), 'top': .62, 'top_x': .42, 'v': .36, 'split': (-.25, .12)},
    },
}
V = VARIANTS[VARIANT_NAME]

def vec(x, y, z):
    return Vector((x, y, z)) * UNIT

def ease(t):
    t = max(0.0, min(1.0, t))
    return t*t*(3.0-2.0*t)

def ramp(value, low, high):
    return ease((value-low)/(high-low))

def curve(t, keys):
    for (a, av), (b, bv) in zip(keys, keys[1:]):
        if t <= b:
            return av + (bv-av)*ramp(t, a, b)
    return keys[-1][1]

def angles(pitch=0, yaw=0, roll=0):
    return (Quaternion(AZ, math.radians(yaw)) @ Quaternion(AY, math.radians(pitch))
            @ Quaternion(AX, math.radians(roll))).to_matrix().to_4x4()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
body = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
body.name = 'Lupacz'
for material in body.data.materials:
    shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    # Na grafitowym futrze szeroki matowy odblask. Kredowe pazury wyróżnia ich albedo.
    for name, value in [('Metallic', 0.0), ('Roughness', 0.87), ('Specular IOR Level', 0.22)]:
        socket = shader.inputs[name]
        for link in list(socket.links):
            material.node_tree.links.remove(link)
        socket.default_value = value
    for node in material.node_tree.nodes:
        if node.type == 'NORMAL_MAP':
            node.inputs['Strength'].default_value = 0.7
body.data.transform(Matrix.Diagonal((UNIT, UNIT, UNIT, 1.0)) @ body.matrix_world)
body.parent = None
body.matrix_world = Matrix.Identity(4)
skel = bpy.data.armatures.new('Szkielet Łupacza')
arm = bpy.data.objects.new('Lupacz_Rig', skel)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
parts = {}
def bone(name, parent, head, tail, deform=True):
    b = skel.edit_bones.new(name)
    b.head, b.tail = vec(*head), vec(*tail)
    if parent:
        b.parent = skel.edit_bones[parent]
    b.use_deform = deform
    parts[name] = parent

bone('Root', None, (0,0,0), (0,0,.16), False)
for name, parent, head, tail in V['spine']:
    bone(name, parent, head, tail)

legs = []
for suffix, sign in [('R',-1),('L',1)]:
    for front in (True, False):
        if front:
            pts = V['front']
            ids = ['UpperArm','Forearm','Forepaw']
        else:
            pts = V['hind']
            ids = ['Thigh','Shin','Hindpaw']
        pts=[(x,y*sign,z) for x,y,z in pts]
        chain=[n+'.'+suffix for n in ids]
        parent='Chest' if front else 'Hips'
        for i,name in enumerate(chain):
            bone(name,parent,pts[i],pts[i+1])
            parent=name
        legs.append((front,sign,chain, [vec(*p) for p in pts]))

bpy.ops.object.mode_set(mode='OBJECT')
mod = body.modifiers.new('Szkielet','ARMATURE')
mod.object = arm
mod.use_deform_preserve_volume = False
body.parent = arm
groups = {name:body.vertex_groups.new(name=name) for name in parts if name!='Root'}
axis_keys = V['axis']

# ---------------------------------------------------------------- skorupa: powierzchnie płyt (wariant „shell”)
# Ściana należy do skorupy, gdy ma kolor łupka (ciemny albo chłodny) nad krawędzią skorupy, albo leży wysoko na grzbiecie; potem
# wygładzanie większością sąsiadów (porosty na płytach są jasne jak skóra). Płyty dzieli x: zad | środek | kark. Materiały „Plate0–2”
# to kopie materiału ciała (ta sama tekstura) — w Godocie osobne powierzchnie siatki, które `enemy3d.gd` przełącza po rozbiciu.
shell_vertices = set()
if V['plates']:
    import numpy as np
    cfg = V['shell']
    base = body.data.materials[0]
    bsdf = next(n for n in base.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    img = bsdf.inputs['Base Color'].links[0].from_node.image
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    uv = body.data.uv_layers.active.data
    polys = body.data.polygons
    def looks_like_slate(f):
        u = sum(uv[i].uv.x for i in f.loop_indices) / f.loop_total
        v = sum(uv[i].uv.y for i in f.loop_indices) / f.loop_total
        r, g, b = px[min(H-1, max(0, int(v % 1.0 * H))), min(W-1, max(0, int(u % 1.0 * W))), :3]
        h, s, val = colorsys.rgb_to_hsv(float(r), float(g), float(b))
        return val < cfg['v'] or (.45 < h < .75 and s > .05)
    shell = []
    for f in polys:
        c = f.center / UNIT
        inside = cfg['x'][0] < c.x < cfg['x'][1] and c.z > cfg['skirt']
        shell.append(inside and (looks_like_slate(f) or (c.z > cfg['top'] and c.x < cfg['top_x'])))
    neighbours = [[] for _ in polys]
    by_edge = {}
    for f in polys:
        for key in f.edge_keys:
            by_edge.setdefault(key, []).append(f.index)
    for faces in by_edge.values():
        for a in faces:
            neighbours[a].extend(b for b in faces if b != a)
    for _ in range(4):
        shell = [(sum(shell[n] for n in neighbours[i]) * 2 > len(neighbours[i])) if neighbours[i] else shell[i] for i in range(len(polys))]
    for i in range(3):
        m = base.copy()
        m.name = 'Plate%d' % i
        body.data.materials.append(m)
    base.name = 'Body'
    counts = [0, 0, 0, 0]
    for f in polys:
        if not shell[f.index]:
            f.material_index = 0
            counts[0] += 1
            continue
        x = f.center.x / UNIT
        plate = 2 if x < cfg['split'][0] else (1 if x < cfg['split'][1] else 0)
        f.material_index = 1 + plate
        counts[1 + plate] += 1
        shell_vertices.update(f.vertices)
    print('SHELL faces body/plate0/plate1/plate2:', counts)

def body_weights(x,z):
    tz, tx = V['tail_clamp']
    coord=max(x,tx) if z>tz and x<tx else x
    if coord<=axis_keys[0][0]: return {axis_keys[0][1]:1.0}
    for (a,left),(b,right) in zip(axis_keys,axis_keys[1:]):
        if coord<=b:
            f=ramp(coord,a,b)
            return {left:1-f,right:f}
    return {'Head':1.0}

L = V['limb']
for vertex in body.data.vertices:
    x,y,z=vertex.co / UNIT
    side='R' if y<0 else 'L'
    lateral=ramp(abs(y),*L['lateral'])
    low=1-ramp(z,*L['low'])
    limb=low*(lateral+(1-lateral)*(1-ramp(z,.15,.34)))
    limb*=ramp(x,*L['x_in'])*(1-ramp(x,*L['x_out']))
    if vertex.index in shell_vertices:
        limb=0.0                                     # skorupa jest sztywna z tułowiem — krawędź nad łapą nie idzie za łapą
    front_mix=ramp(x,*L['front_mix'])
    weights={k:v*(1-limb) for k,v in body_weights(x,z).items()}
    for front, influence in [(True,limb*front_mix),(False,limb*(1-front_mix))]:
        if influence < .0001: continue
        names = ('UpperArm','Forearm','Forepaw') if front else ('Thigh','Shin','Hindpaw')
        wrist = L['wrist_front'] if front else L['wrist_hind']
        upper=ramp(z,*(L['upper_front'] if front else L['upper_hind']))
        paw=(1-ramp(z,*L['paw_z']))*ramp(x,wrist-L['paw_x'][0],wrist+L['paw_x'][1])
        for n,w in zip(names,(upper,(1-upper)*(1-paw),(1-upper)*paw)):
            weights[n+'.'+side]=influence*w
    keep=sorted([(v,k) for k,v in weights.items() if v>.00001], reverse=True)[:4]
    total=sum(v for v,k in keep)
    for v,k in keep:
        groups[k].add([vertex.index],v/total,'REPLACE')

# Dopasowanie dwukościowe trzyma palce na podłożu w podporze i zachowuje długość łapy.
rest = {k:skel.bones[k].matrix_local.copy() for k in parts}
ident = Matrix.Identity(4)
def solve_leg(out, chain, points, target, toe_angle, toe_yaw):
    upper,lower,paw=chain
    p0,p1,p2,_=points
    parent=parts[upper]
    start=out[parent] @ rest[parent].inverted() @ p0
    axis=(target-start).normalized()
    l1=(p1-p0).length
    l2=(p2-p1).length
    length=max(abs(l1-l2)+1e-5,min((target-start).length,l1+l2-.001))
    foot=start+axis*length
    along=(l1*l1-l2*l2+length*length)/(2*length)
    pole=(p1-p0) - (p2-p0).normalized()*(p1-p0).dot((p2-p0).normalized())
    perp=(pole-axis*pole.dot(axis)).normalized()
    knee=start+axis*along+perp*math.sqrt(max(0.0,l1*l1-along*along))
    for name,base,tip,oldbase,oldtip in [(upper,start,knee,p0,p1),(lower,knee,foot,p1,p2)]:
        rot=(oldtip-oldbase).rotation_difference(tip-base).to_matrix().to_4x4()
        rot @= rest[name].to_quaternion().to_matrix().to_4x4()
        rot.translation=base
        out[name]=rot
    out[paw]=angles(toe_angle,toe_yaw) @ rest[paw].to_quaternion().to_matrix().to_4x4()
    out[paw].translation=foot

def gait(t,offset):
    phase=(t+offset)%1.0
    stance=.61
    extent=.175*V['stride']
    if phase < stance:
        return extent-2*extent*phase/stance,0.0,0.0,0.0
    f=(phase-stance)/(1-stance)
    s=math.sin(math.pi*f)
    return -extent+2*extent*ease(f),.118*V['stride']*s*s,.047*V['stride']*s,(-15*math.sin(TAU*f))

ATTACK_FRAMES = 32
# Klatka, następnie przesunięcie bioder (x, y, z), pochylenie bioder,
# pochylenie, skręt i przechył klatki piersiowej, pochylenie i skręt głowy.
# 4: przysiad, 12–14: uniesienie na zadzie, 19: cios, 21: wyhamowanie.
ATTACK_BODY = [
    (0,  (   0,     0,     0,   0,   0,   0,   0,   0,   0)),
    (4,  (-.09,  .035, -.075,   8,   6,  -5,  -5,  -7,   5)),
    (12, (-.12,  .040, -.018, -26, -28, -24, -22,  27,  14)),
    (14, (-.10,  .045, -.018, -25, -27, -25, -23,  25,  12)),
    (19, ( .33, -.055, -.020,   7,  12,  25,  18, -17, -18)),
    (21, ( .36, -.065, -.037,   8,  12,  28,  16, -18, -18)),
    (25, ( .22, -.015, -.025,   6,   7,  14,   9,  -8, -11)),
    (32, (   0,     0,     0,   0,   0,   0,   0,   0,   0)),
]
# Ścieżki nadgarstków w przestrzeni podłoża względem pozycji spoczynkowej.
# Dodatnia wartość poprzeczna oznacza ruch na zewnątrz odpowiedniego barku.
# Pozycja, potem pochylenie i odchylenie pazurów w stopniach.
ATTACK_STRIKE_PAW = [
    (0,  (   0,    0,     0,   0,   0)),
    (4,  (   0,    0,     0,   0,   0)),
    (9,  (-.22,  .24,   .80, -40,  28)),
    (13, (-.37,  .25,  1.46, -70,  24)),
    (15, (-.06,  .41,  1.31, -42,  32)),
    (17, ( .78,  .16,   .71,  -5,   8)),
    (19, ( .76, -.08,   .25,  16, -28)),
    (21, ( .48, -.20,   .08,  15, -46)),
    (24, ( .41, -.17,  .015,   3, -28)),
    (28, ( .19,  .02,   .18, -13,   3)),
    (32, (   0,    0,     0,   0,   0)),
]
ATTACK_BRACE_PAW = [
    (0,  (   0,    0,    0,   0,   0)),
    (5,  (   0,    0,    0,   0,   0)),
    (12, (-.13,  .07,  .62,  25,  12)),
    (14, (-.03,  .09,  .58,  20,  10)),
    (18, ( .25,  .10,    0,   0,   6)),
    (25, ( .25,  .10,    0,   0,   6)),
    (28, ( .17,  .07,  .10, -11,   5)),
    (32, (   0,    0,    0,   0,   0)),
]

DIG_FRAMES = 16
# Kopanie w pościgu (enemy_mole.gd): pętla dwóch pociągnięć — przednie łapy na zmianę sięgają w przód na wysokość piersi
# i grabią skałę w dół i pod siebie. Faza łapy, potem pozycja (przód, góra) i pochylenie pazurów w stopniach.
DIG_PAW = [(0, (-.06, .02, 4)), (.30, (.36, .25, -32)), (.42, (.40, .21, -24)), (.70, (.06, .03, 16)), (1, (-.06, .02, 4))]

def dig_paw(f):
    f %= 1.0
    for (start, pose_a), (end, pose_b) in zip(DIG_PAW, DIG_PAW[1:]):
        if f <= end:
            blend = ramp(f, start, end)
            return tuple(a + (b-a)*blend for a, b in zip(pose_a, pose_b))
    return DIG_PAW[-1][1]

def attack_pose(frame, keys):
    for (start, pose_a), (end, pose_b) in zip(keys, keys[1:]):
        if frame <= end:
            blend = ramp(frame, start, end)
            return tuple(a + (b-a)*blend for a, b in zip(pose_a, pose_b))
    return keys[-1][1]

def build_pose(action,t):
    wave=math.sin(TAU*t)
    dx=dy=dz=0.0
    chest_pitch=chest_yaw=chest_roll=head_pitch=head_yaw=0.0
    pelvis_pitch=tail_yaw=0.0
    tail_yaw=3.4*wave
    if action=='idle':
        sniff=math.exp(-((t-.32)/.076)**2)+.75*math.exp(-((t-.49)/.070)**2)
        dz=.014*wave
        chest_pitch=-2.8*wave
        head_pitch=-6*sniff+2*wave
        head_yaw=12*(math.exp(-((t-.53)/.23)**2)-.0049)
        chest_roll=1.6*wave
    elif action=='walk':
        dz=.016*(1-math.cos(2*TAU*t))
        dy=.023*wave
        chest_roll=5*wave
        chest_pitch=2.8*math.sin(2*TAU*t)
        pelvis_pitch=-.9*math.sin(2*TAU*t)
        head_pitch=-.65*chest_pitch
        head_yaw=-2.8*wave
        tail_yaw=9*math.sin(TAU*t+.35)
    elif action=='attack':
        attack_frame = t * ATTACK_FRAMES
        (dx, dy, dz, pelvis_pitch, chest_pitch, chest_yaw, chest_roll,
         head_pitch, head_yaw) = attack_pose(attack_frame, ATTACK_BODY)
        dx *= V['reach']; dy *= V['reach']; dz *= V['reach']        # wypad tułowia w zasięgu krótszych tylnych łap
        tail_yaw = -.65 * chest_yaw
    elif action=='dig':
        stroke=math.sin(2*TAU*t)
        dx=.035+.025*stroke
        dz=-.045+.012*stroke
        pelvis_pitch=-3
        chest_pitch=11+3.5*stroke
        chest_roll=6*math.sin(TAU*t)
        head_pitch=15+4*stroke
        head_yaw=-5*math.sin(TAU*t)
        tail_yaw=7*math.sin(TAU*t+.6)
    elif action=='emerge':
        dx=curve(t,[(0,-1.64),(.12,-1.52),(.27,-1.34),(.40,-1.16),(.55,-.78),(.77,-.38),(.92,-.06),(1,0)])
        dz=curve(t,[(0,-.19),(.32,-.19),(.46,-.11),(.62,-.022),(.76,-.065),(.92,.022),(1,0)])
        chest_pitch=curve(t,[(0,12),(.20,10),(.39,-6),(.53,-12),(.68,5),(.83,2),(1,0)])
        head_pitch=curve(t,[(0,14),(.24,10),(.46,-13),(.61,-9),(.83,6),(1,0)])
        chest_roll=5*math.sin(TAU*t*1.6)*math.sin(math.pi*t)
        tail_yaw=9*math.sin(TAU*t*1.7)*math.sin(math.pi*t)
    rig={}
    def add(name, tilt=0, yaw=0, roll=0, offset=None):
        p=parts[name]
        base=(rig[p] @ rest[p].inverted() if p else ident) @ rest[name]
        mat=angles(tilt,yaw,roll) @ base
        mat.translation=base.translation + (offset if offset is not None else Vector((0,0,0)))
        rig[name]=mat
    add('Root',offset=vec(dx,0,0))
    pelvis_roll = (-.12 if action == 'attack' else -.4) * chest_roll
    add('Hips',pelvis_pitch,roll=pelvis_roll,offset=vec(0,dy,dz))
    add('Spine',chest_pitch*.45,yaw=chest_yaw*.45,roll=chest_roll*.45)
    add('Chest',chest_pitch*.55,yaw=chest_yaw*.55,roll=chest_roll*.55)
    add('Neck',head_pitch*.45,yaw=head_yaw*.50)
    add('Head',head_pitch*.55,yaw=head_yaw*.50)
    tail_lift = max(0.0, -pelvis_pitch) * .30 if action == 'attack' else 0.0
    add('Tail',tilt=tail_lift,yaw=tail_yaw*.55)
    add('TailEnd',yaw=tail_yaw*.65)
    for front,sign,chain,pts in legs:
        fx=fy=fz=toe=toe_yaw=0.0
        if action=='walk':
            offset=(0.0 if sign<0 else .5) if front else (.58 if sign<0 else .08)
            fx,fz,fy,toe=gait(t,offset)
            if not front:
                fz*=.76
                fy*=.55
        elif action=='attack':
            if front:
                keys = ATTACK_STRIKE_PAW if sign < 0 else ATTACK_BRACE_PAW
                fx, fy, fz, toe, toe_yaw = attack_pose(attack_frame, keys)
                fx *= V['reach']; fy *= V['reach']; fz *= V['reach']       # krótsze łapy skorupiaka: ta sama droga w skali łapy
            # Tylne łapy odpychają ciało, a przeciwległy nadgarstek łapie ciężar przed ciosem.
            fx -= dx
        elif action=='dig':
            if front:
                fx, fz, toe = dig_paw(t + (0.0 if sign < 0 else .5))
                fy = .03 * (1 - fz / .25)
                fx *= V['reach']; fz *= V['reach']
            # Tylne łapy stoją, a przednia w podporze trzyma ciężar pochylonego ciała.
            fx -= dx
        elif action=='emerge':
            offset=(.01 if sign<0 else .43) if front else (.56 if sign<0 else .08)
            if front and sign<0 and t < .58:
                fx=curve(t,[(0,.12),(.16,.41),(.30,.40),(.42,.25),(.58,-.10)])
                fz=curve(t,[(0,.18),(.17,.27),(.31,.135),(.43,.035),(.58,.009)])
                toe=curve(t,[(0,-28),(.20,-32),(.36,-4),(.49,12),(.58,0)])
            else:
                fx,fz,fy,toe=gait(1.85*t,offset)
                fade=math.sin(math.pi*min(1,t))**.65
                fx*=fade; fz*=fade; fy*=fade; toe*=fade
        # Czubek pazura obracanego w dół nadal opiera się o ziemię.
        fz=max(fz,.245*math.sin(math.radians(toe)))-(.010 if front else 0.0)
        target=pts[2]+vec(dx+fx,sign*fy,fz)
        solve_leg(rig,chain,pts,target,toe,sign*toe_yaw)
    return rig

scene=bpy.context.scene
scene.render.fps=FPS
arm.animation_data_create()
for clip, duration in [('idle',72),('walk',24),('emerge',48),('attack',ATTACK_FRAMES),('dig',DIG_FRAMES)]:
    action=bpy.data.actions.new(clip)
    arm.animation_data.action=action
    last={}
    for frame in range(duration+1):
        matrices=build_pose(clip,frame/duration)
        for name,parent in parts.items():
            local_rest=rest[parent].inverted() @ rest[name] if parent else rest[name]
            local_pose=matrices[parent].inverted() @ matrices[name] if parent else matrices[name]
            loc,quat,scale=(local_rest.inverted() @ local_pose).decompose()
            if name in last: quat.make_compatible(last[name])
            last[name]=quat.copy()
            pb=arm.pose.bones[name]
            pb.rotation_mode='QUATERNION'
            pb.location=loc
            pb.rotation_quaternion=quat
            pb.keyframe_insert('location',frame=frame,group=name)
            pb.keyframe_insert('rotation_quaternion',frame=frame,group=name)
    track=arm.animation_data.nla_tracks.new()
    track.name=clip
    strip=track.strips.new(clip,0,action)
    strip.name=clip
    track.mute=True
arm.animation_data.action=None
for pb in arm.pose.bones:
    pb.matrix_basis=Matrix.Identity(4)
scene.frame_start,scene.frame_end=0,72
arm.animation_data.action=bpy.data.actions['idle']
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active=arm
for im in bpy.data.images:
    if im.type=='IMAGE' and not im.packed_file:
        im.pack()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(destination/'lupacz.blend'))
settings=dict(filepath=str(destination/'lupacz.glb'),export_format='GLB',use_selection=True,export_animations=True,
              export_animation_mode='ACTIONS',export_image_format='JPEG',export_jpeg_quality=92,
              export_skins=True,export_all_influences=False)
bpy.ops.export_scene.gltf(**settings)
print('LUPACZ',VARIANT_NAME,len(body.data.vertices),'vertices,',len(arm.data.bones),'bones, clips:',[a.name for a in bpy.data.actions])
