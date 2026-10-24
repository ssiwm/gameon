"""Siatki Wołka/Rzeźnika: zamknięta powierzchnia, nowe UV i wypiek PBR z pełnego źródła.

Uruchomienie: python prototype/tools/prep_enemy3d.py --only=wolek,rzeznik
Blender: voxel remesh -> wygładzenie -> budżet LOD0 -> UV -> selected-to-active
albedo / tangent normal / ORM. Tasak pozostaje osobnym materiałem, sztywno na dłoni.
Nie przenosimy pociętej topologii ani wadliwych wag źródła na nową powierzchnię.
"""
import math
import time
import json
import struct

import bmesh
import bpy
import numpy as np

from enemy_mesh_repair import normalize_weights, skin_by_surface_distance, weld_seams


def _validate_export(path):
    """Sprawdź rzeczywistą topologię float32 GLB, po konwersji osi eksportera.

    Zaokrąglenie eksportu potrafi doczepić ostatnią płaską drobinę do ciała.
    Usuwamy tylko trójkąty z co najmniej dwiema otwartymi krawędziami;
    zamknięte ciało musi mieć po tym zero brzegów i krawędzi >2 ścian.
    """
    with open(path, "rb") as file:
        data = file.read()
    json_length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_length])
    binary = bytearray(data[28 + json_length:])
    primitive = doc["meshes"][0]["primitives"][0]
    types = {5123: "<u2", 5125: "<u4", 5126: "<f4"}

    def accessor(index, width):
        access = doc["accessors"][index]
        view = doc["bufferViews"][access["bufferView"]]
        dtype = np.dtype(types[access["componentType"]])
        offset = view.get("byteOffset", 0) + access.get("byteOffset", 0)
        stride = view.get("byteStride", width * dtype.itemsize)
        return np.ndarray((access["count"], width), dtype=dtype, buffer=binary,
                          offset=offset, strides=(stride, dtype.itemsize)).copy()

    points = accessor(primitive["attributes"]["POSITION"], 3)
    triangles = accessor(primitive["indices"], 1).reshape(-1, 3)
    _, weld = np.unique(points, axis=0, return_inverse=True)

    def topology(faces):
        f = weld[faces]
        edges = np.sort(np.concatenate((f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]])), axis=1)
        _, inverse, counts = np.unique(edges, axis=0, return_inverse=True, return_counts=True)
        face_ids = np.tile(np.arange(len(faces)), 3)
        boundary = np.bincount(face_ids[counts[inverse] == 1], minlength=len(faces))
        return boundary, counts

    boundary, counts = topology(triangles)
    clean = triangles[boundary < 2]
    boundary, counts = topology(clean)
    if int((counts == 1).sum()) or int((counts > 2).sum()):
        raise RuntimeError("Eksport ciała nie jest zamknięty: boundary=%d nonmanifold=%d" %
                           (int((counts == 1).sum()), int((counts > 2).sum())))
    removed = len(triangles) - len(clean)
    if removed:
        access = doc["accessors"][primitive["indices"]]
        view = doc["bufferViews"][access["bufferView"]]
        offset = view.get("byteOffset", 0) + access.get("byteOffset", 0)
        payload = clean.tobytes()
        binary[offset:offset + len(payload)] = payload
        access["count"] = int(clean.size)
        access["min"] = [int(clean.min())]
        access["max"] = [int(clean.max())]
        encoded = json.dumps(doc, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        binary += b"\0" * (-len(binary) % 4)
        result = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
        result += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
        result += struct.pack("<II", len(binary), 0x004E4942) + binary
        with open(path, "wb") as file:
            file.write(result)
    print("GLB CLOSED BODY", len(clean), "triangles; export dust removed", removed, flush=True)


def _cleaver_grip(source, arm, height):
    """Stała poza chwytu: źródłowe palce wisiały otwarte obok rękojeści.

    Zginamy dalszą część palców w płaszczyźnie dłoni; nadgarstek, obręcz,
    kciuk i tasak zachowują położenie. Model nie ma osobnego rigu palców.
    """
    hand = arm.data.bones["mixamorig:RightHand"]
    origin = arm.matrix_world @ hand.head_local
    direction = (arm.matrix_world.to_3x3() @ hand.matrix_local.col[1].to_3d()).normalized()
    across = (arm.matrix_world.to_3x3() @ hand.matrix_local.col[0].to_3d()).normalized()
    start = height * 0.075
    radius = height * 0.042
    changed = 0
    for vertex in source.data.vertices:
        point = source.matrix_world @ vertex.co
        distance = (point - origin).dot(direction)
        if distance <= start or point.y > origin.y + height * 0.025:
            continue
        length = distance - start
        angle = min(length / radius, 2.8)
        curved = direction * radius * math.sin(angle) - across * radius * (1.0 - math.cos(angle))
        point += curved - direction * length
        vertex.co = source.matrix_world.inverted() @ point
        changed += 1
    source.data.update()
    print("CLEAVER GRIP", changed, "vertices", flush=True)


def _active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _smooth_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    if obj.data.has_custom_normals:
        obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
    for face in obj.data.polygons:
        face.use_smooth = True
    obj.data.update()


def _reduce(obj, triangles):
    _active(obj)
    obj.data.calc_loop_triangles()
    mod = obj.modifiers.new("LOD0_budget", "DECIMATE")
    mod.ratio = min(1.0, triangles / max(len(obj.data.loop_triangles), 1))
    bpy.ops.object.modifier_apply(modifier=mod.name)


def _close_surface(obj, height):
    """Usuń zapadnięte ściany po redukcji i zamknij ich mikroszczeliny przed UV."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=height * 1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=height * 1e-5)
    dangling = [f for f in bm.faces if sum(e.is_boundary for e in f.edges) >= 2]
    if dangling:
        bmesh.ops.delete(bm, geom=dangling, context="FACES")
    # Remesh/Decimate zostawia płaskie, dwustronne drobiny (1–8 ścian).
    # Eksporter usuwa ich zduplikowaną stronę i zostawia wolne trójkąty.
    # To pył geometryczny, nie fragment powierzchni ciała.
    remaining = set(bm.faces)
    dust = []
    while remaining:
        queue = [remaining.pop()]
        component = []
        while queue:
            face = queue.pop()
            component.append(face)
            for edge in face.edges:
                for neighbour in edge.link_faces:
                    if neighbour in remaining:
                        remaining.remove(neighbour)
                        queue.append(neighbour)
        if len(component) <= 8:
            dust.extend(component)
    if dust:
        bmesh.ops.delete(bm, geom=dust, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate()


def _smooth_weights(obj):
    """Dyfuzja po sąsiedztwie eliminuje ostre uskoki wag na barkach i łokciach."""
    weights = np.zeros((len(obj.data.vertices), len(obj.vertex_groups)), dtype=np.float64)
    for v in obj.data.vertices:
        for g in v.groups:
            weights[v.index, g.group] = g.weight
    edges = np.array([e.vertices[:] for e in obj.data.edges], dtype=np.int64)
    a = np.concatenate((edges[:, 0], edges[:, 1]))
    b = np.concatenate((edges[:, 1], edges[:, 0]))
    degree = np.bincount(a, minlength=len(weights))[:, None]
    for _ in range(8):
        neighbours = np.zeros_like(weights)
        np.add.at(neighbours, a, weights[b])
        weights = weights * 0.55 + neighbours / np.maximum(degree, 1) * 0.45
    for v in obj.data.vertices:
        for group in list(v.groups):
            obj.vertex_groups[group.group].remove([v.index])
        keep = np.argsort(-weights[v.index])[:4]
        values = weights[v.index, keep]
        values /= values.sum()
        for group, weight in zip(keep, values):
            obj.vertex_groups[int(group)].add([v.index], float(weight), "REPLACE")


def _image_upstream(socket, seen=None):
    seen = seen or set()
    for link in socket.links:
        node = link.from_node
        if node in seen:
            continue
        seen.add(node)
        if node.type == "TEX_IMAGE" and node.image:
            return node.image
        for input_socket in node.inputs:
            image = _image_upstream(input_socket, seen)
            if image:
                return image
    return None


def prepare(src, dst, triangles, texture_size):
    start = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    source = max((o for o in bpy.data.objects if o.type == "MESH" and o.vertex_groups),
                 key=lambda o: len(o.data.vertices))
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and not obj.vertex_groups:
            bpy.data.objects.remove(obj, do_unlink=True)
    for mod in list(source.modifiers):
        source.modifiers.remove(mod)
    prop = None
    if len(source.data.materials) == 2:
        # W źródle tasak (59k) jest większą siatką niż ciało (58k).
        _active(source)
        body_material = source.data.materials[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="MATERIAL")
        bpy.ops.object.mode_set(mode="OBJECT")
        parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
        source = next(o for o in parts if o.data.materials[o.data.polygons[0].material_index] == body_material)
        prop = next(o for o in parts if o != source)
    if prop:
        _cleaver_grip(source, arm, max(source.dimensions))
    weld_seams(source)
    _smooth_normals(source)
    height = max(source.dimensions)
    source_bsdf = next(n for n in source.data.materials[0].node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    orm_source = _image_upstream(source_bsdf.inputs["Roughness"])
    albedo_source = _image_upstream(source_bsdf.inputs["Base Color"])
    # Mapa źródłowa opisuje stare, pocięte tangenty. Wypiek normalnych
    # bierze detal geometrii; przeniesienie starej mapy podwajałoby artefakty.
    for link in list(source_bsdf.inputs["Normal"].links):
        source.data.materials[0].node_tree.links.remove(link)

    body = source.copy()
    body.data = source.data.copy()
    bpy.context.collection.objects.link(body)
    body.name = "enemy_body"
    body.vertex_groups.clear()
    _active(body)
    body.data.remesh_voxel_size = height / (280.0 if prop else 300.0)
    body.data.use_remesh_preserve_volume = True
    bpy.ops.object.voxel_remesh()
    smooth = body.modifiers.new("surface_relax", "SMOOTH")
    smooth.factor = 0.5
    smooth.iterations = 3
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    # Zostaw zapas na trójkąty domykające zapadnięte detale redukcji.
    _reduce(body, triangles - (5000 if prop else 0) - 100)
    _close_surface(body, height)
    body.data.validate()
    _smooth_normals(body)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Wypiek nie zawiera świateł ani cieni. Nowa siatka wymaga nowej mapy tangent normal.
    bpy.ops.preferences.addon_enable(module="cycles")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = height * 0.025
    scene.render.bake.max_ray_distance = height * 0.06
    scene.render.bake.margin = 12
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    mat = bpy.data.materials.new("Body_PBR")
    mat.use_nodes = True
    body.data.materials.clear()
    body.data.materials.append(mat)
    for face in body.data.polygons:
        face.material_index = 0
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    target = mat.node_tree.nodes.new("ShaderNodeTexImage")
    images = {}
    _active(body)
    source.select_set(True)
    source_material = source.data.materials[0]
    source_output = next(n for n in source_material.node_tree.nodes if n.type == "OUTPUT_MATERIAL")
    original_surface = source_output.inputs["Surface"].links[0].from_socket
    for name, mode in [("Albedo", "EMIT"), ("Normal", "NORMAL"), ("ORM", "EMIT")]:
        image = bpy.data.images.new(name, width=texture_size, height=texture_size)
        image.colorspace_settings.name = "sRGB" if name == "Albedo" else "Non-Color"
        target.image = image
        mat.node_tree.nodes.active = target
        if name in ("Albedo", "ORM"):
            sm = source.data.materials[0]
            nodes = sm.node_tree.nodes
            output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
            emission = nodes.new("ShaderNodeEmission")
            emission.inputs["Color"].default_value = source_bsdf.inputs["Base Color"].default_value if name == "Albedo" else (1.0, 0.85, 0.0, 1.0)
            source_image = albedo_source if name == "Albedo" else orm_source
            if source_image:
                tex = nodes.new("ShaderNodeTexImage")
                tex.image = source_image
                sm.node_tree.links.new(tex.outputs["Color"], emission.inputs["Color"])
            sm.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
        else:
            source_material.node_tree.links.new(original_surface, source_output.inputs["Surface"])
        print("BAKE", name, texture_size, flush=True)
        bpy.ops.object.bake(type=mode)
        if name == "ORM":
            # AO źródła wypalało czarne plamy na ramionach i butach.
            # Zachowujemy delikatną mikrokawitację, bez wypalonych cieni.
            pixels = np.empty(texture_size * texture_size * 4, dtype=np.float32)
            image.pixels.foreach_get(pixels)
            pixels[0::4] = 0.7 + 0.3 * pixels[0::4]
            pixels[1::4] = np.clip(pixels[1::4], 0.55, 1.0)
            pixels[2::4] = 0.0
            image.pixels.foreach_set(pixels)
            image.update()
        images[name] = image
    mat.node_tree.nodes.remove(target)
    for name in images:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = images[name]
        if name == "Albedo":
            mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        elif name == "Normal":
            normal = mat.node_tree.nodes.new("ShaderNodeNormalMap")
            mat.node_tree.links.new(node.outputs["Color"], normal.inputs["Color"])
            mat.node_tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            split = mat.node_tree.nodes.new("ShaderNodeSeparateColor")
            mat.node_tree.links.new(node.outputs["Color"], split.inputs["Color"])
            mat.node_tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
            # Skóra, rogi i tkanina są dielektrykami. TRELLIS oznaczył całe
            # ciało jako metal; tasak zachowuje własny materiał i mapę.
            bsdf.inputs["Metallic"].default_value = 0.0
            # Eksporter glTF rozpoznaje AO przez standardową grupę glTF Material Output.
            group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
            group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
            ao = mat.node_tree.nodes.new("ShaderNodeGroup")
            ao.node_tree = group
            mat.node_tree.links.new(split.outputs["Red"], ao.inputs["Occlusion"])
    bpy.data.objects.remove(source, do_unlink=True)
    _active(body)
    skin_by_surface_distance(body, arm)
    _smooth_weights(body)
    body.modifiers.new("skin", "ARMATURE").object = arm
    if prop:
        weld_seams(prop)
        _reduce(prop, 5000)
        prop.vertex_groups.clear()
        hand = prop.vertex_groups.new(name="mixamorig:RightHand")
        hand.add(list(range(len(prop.data.vertices))), 1.0, "REPLACE")
        prop.modifiers.new("skin", "ARMATURE").object = arm
        prop.select_set(True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
    normalize_weights(body)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="AUTO",
                              export_animations=False, export_apply=False)
    _validate_export(dst)
    print("HERO OK", dst, len(body.data.polygons), "faces", round(time.time() - start, 1), "s", flush=True)
