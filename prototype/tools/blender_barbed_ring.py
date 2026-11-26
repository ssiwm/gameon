# Pierścień z drutu kolczastego wokół klawisza [E] (znacznik interakcji, INTERACT_KEY_PLAN.md K1): dwie skręcone żyły na okręgu
# i co 30° kolec — dwa krótkie druty owinięte wokół żył, końce odgięte na zewnątrz. Render z góry (kamera ortograficzna, tło przezroczyste),
# metal bez koloru — barwę (bursztyn → czerwień przy przytrzymaniu) i odsłanianie po kącie daje shader znacznika (interact_mark3d.gd).
# Wynik pakuje `tools/gen_interact_key.py` (luminancja, krycie i poświata w kanałach jednej tekstury).
#
#   blender -b --factory-startup -P prototype/tools/blender_barbed_ring.py -- --out=C:/tmp/barbed_ring.png [--size=512]
import bpy
import math
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "barbed_ring.png"
SIZE = 512
for a in argv:
	if a.startswith("--out="):
		OUT = a[len("--out="):]
	elif a.startswith("--size="):
		SIZE = int(a[len("--size="):])

R = 1.0            # promień osi pierścienia
WIRE_R = 0.026     # odsunięcie żył od osi (skręt)
WIRE_T = 0.0115    # promień przekroju drutu
TWISTS = 46        # skręty żył na pełny obwód
BARBS = 12         # kolce co 30°
BARB_LEN = 0.115   # długość odgiętego końca kolca

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def curve_obj(name, pts, radius=WIRE_T, cyclic=False):
	cu = bpy.data.curves.new(name, "CURVE")
	cu.dimensions = "3D"
	cu.bevel_depth = radius
	cu.bevel_resolution = 3
	cu.use_fill_caps = True
	sp = cu.splines.new("POLY")
	sp.points.add(len(pts) - 1)
	for i, p in enumerate(pts):
		sp.points[i].co = (p[0], p[1], p[2], 1.0)
	sp.use_cyclic_u = cyclic
	ob = bpy.data.objects.new(name, cu)
	scene.collection.objects.link(ob)
	return ob


def ring_frame(t):
	"""Punkt na osi i lokalna baza (promieniowa, z) dla kąta t."""
	c = (R * math.cos(t), R * math.sin(t), 0.0)
	rad = (math.cos(t), math.sin(t), 0.0)
	return c, rad


# dwie żyły skręcone wokół osi
N = 2400
for s in range(2):
	pts = []
	for i in range(N):
		t = TAU = 2.0 * math.pi
		t = TAU * i / N
		c, rad = ring_frame(t)
		ph = TWISTS * t + s * math.pi
		off = WIRE_R * math.cos(ph)
		z = WIRE_R * math.sin(ph)
		pts.append((c[0] + rad[0] * off, c[1] + rad[1] * off, z))
	curve_obj("strand%d" % s, pts, cyclic=True)

# kolce: dwa druty, każdy owinięty 2,5 raza wokół żył (zwój), końce odgięte na zewnątrz i do środka pod kątem
for b in range(BARBS):
	t0 = 2.0 * math.pi * (b + 0.5) / BARBS
	for w in range(2):
		pts = []
		coil_n = 60
		coil_span = 0.075                       # długość zwoju wzdłuż obwodu [rad · R]
		ph0 = w * math.pi
		for i in range(coil_n + 1):
			u = i / coil_n
			t = t0 + (u - 0.5) * coil_span
			c, rad = ring_frame(t)
			ph = ph0 + u * 2.5 * 2.0 * math.pi
			rr = WIRE_R + WIRE_T * 1.9
			off = rr * math.cos(ph)
			z = rr * math.sin(ph)
			pts.append((c[0] + rad[0] * off, c[1] + rad[1] * off, z))
		# końce: od początku i końca zwoju odgięte (jeden na zewnątrz, drugi do środka; drugi drut — odwrotnie), lekko wzdłuż obwodu
		for end, sign_t in ((0, -1.0), (-1, 1.0)):
			p = pts[end]
			out = (1.0 if (end == 0) == (w == 0) else -1.0)
			c, rad = ring_frame(t0 + sign_t * 0.03)
			tang = (-math.sin(t0), math.cos(t0), 0.0)
			tip = (
				p[0] + rad[0] * out * BARB_LEN + tang[0] * sign_t * BARB_LEN * 0.55,
				p[1] + rad[1] * out * BARB_LEN + tang[1] * sign_t * BARB_LEN * 0.55,
				p[2] + 0.02 * out,
			)
			seg = [(p[0] + (tip[0] - p[0]) * k / 8.0, p[1] + (tip[1] - p[1]) * k / 8.0, p[2] + (tip[2] - p[2]) * k / 8.0) for k in range(1, 9)]
			if end == 0:
				pts = list(reversed(seg)) + pts
			else:
				pts = pts + seg
		curve_obj("barb%d_%d" % (b, w), pts, radius=WIRE_T * 0.82)

# materiał: stal z nalotem, bez koloru (barwa w shaderze gry)
mat = bpy.data.materials.new("wire")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1.0)
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.42
for ob in scene.collection.objects:
	ob.data.materials.append(mat)

# światło z lewej góry (jak lampy kryjówki nad stanowiskami) i miękkie wypełnienie
sun = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(40), math.radians(-35), 0.0)
scene.collection.objects.link(sun)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
fill.data.energy = 1.2
fill.rotation_euler = (math.radians(-30), math.radians(40), 0.0)
scene.collection.objects.link(fill)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.35, 0.35, 1.0)
scene.world = world

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.0 * (R + BARB_LEN + 0.09)
cam.location = (0.0, 0.0, 5.0)
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("[BARBED-RING] zapisano", OUT, "ortho_scale", cam.data.ortho_scale)
