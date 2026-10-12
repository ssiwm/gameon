"""Tymczasowa sonda: importuje GLB Trzoska, wypisuje kosci i renderuje T-pose + klatki chodu (Cycles CPU)."""
import bpy, os

GLB = r"C:\deadair87\gameon\prototype\art\enemy3d\trzosek.glb"
OUT = r"C:\deadair87\gameon\concepts"
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

arm = None
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        arm = o
        break
print("ARMATURE=", arm.name if arm else None)
if arm is not None:
    print("=== BONES (name | head_world | tail_world) ===")
    mw = arm.matrix_world
    for b in arm.data.bones:
        h = mw @ b.head_local
        t = mw @ b.tail_local
        print("BONE | %s | parent=%s | head=(%.3f,%.3f,%.3f) | tail=(%.3f,%.3f,%.3f)" % (
            b.name, b.parent.name if b.parent else "-", h.x, h.y, h.z, t.x, t.y, t.z))
    # ensure an action is active so frame_set animates
    if arm.animation_data is None and len(bpy.data.actions) > 0:
        arm.animation_data_create()
        arm.animation_data.action = bpy.data.actions[0]

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.render.resolution_x = 520
scene.render.resolution_y = 520
scene.render.image_settings.file_format = "PNG"

# camera + area light (side profile)
bpy.ops.object.camera_add(location=(2.2, 0.0, 0.9))
cam = bpy.context.object
cam.rotation_euler = (1.35, 0.0, 1.5708)  # look toward -X, from +X side
scene.camera = cam
bpy.ops.object.light_add(type="AREA", location=(1.5, -2.0, 3.0))
bpy.context.object.data.energy = 800.0

# transparent-ish dark world so silhouette reads
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.06, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

fps = scene.render.fps
print("FPS=", fps)

# frame 1 (rest), a mid-walk frame, and frame 1 from top
plan = [
    (1, "trzosek_pose_f01_side.png", "side"),
    (31, "trzosek_pose_f31_side.png", "side"),
    (1, "trzosek_pose_f01_top.png", "top"),
]
for fr, name, view in plan:
    scene.frame_set(fr)
    if view == "top":
        cam.location = (0.0, 0.0, 3.2)
        cam.rotation_euler = (0.0, 0.0, 0.0)
    else:
        cam.location = (2.2, 0.0, 0.9)
        cam.rotation_euler = (1.35, 0.0, 1.5708)
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name, "frame", fr)

print("DONE")
