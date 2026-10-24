"""Ciągła siatka i skinning humanoidów; moduł pomocniczy generatorów Blendera.

UV pozostają na narożnikach ścian. Odległość po powierzchni zapobiega
przypisywaniu fartucha/nóg do dłoni stojącej blisko ciała w pozycji spoczynkowej.
Nie wymaga bibliotek poza bpy, bmesh i numpy dostarczanymi z Blenderem.
"""
import heapq

import bmesh
import numpy as np


def weld_seams(body):
    """Scal geometryczne szwy przed Decimate; zachowaj wyspy UV i materiały."""
    points = np.array([v.co[:] for v in body.data.vertices])
    tolerance = max(float(np.ptp(points, axis=0).max()) * 1e-6, 1e-9)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=tolerance)
    bm.to_mesh(body.data)
    bm.free()
    body.data.validate()
    body.data.update()


def normalize_weights(body):
    """Decimate interpoluje wagi: ogranicz i normalizuj po jego zastosowaniu."""
    for vertex in body.data.vertices:
        weights = sorted(((g.group, g.weight) for g in vertex.groups if g.weight > 1e-7),
                         key=lambda item: -item[1])[:4]
        total = sum(weight for _, weight in weights)
        if total <= 0:
            raise RuntimeError("Wierzchołek bez wag: %s" % vertex.index)
        for group in list(vertex.groups):
            body.vertex_groups[group.group].remove([vertex.index])
        for group, weight in weights:
            body.vertex_groups[group].add([vertex.index], weight / total, "REPLACE")


def skin_by_surface_distance(body, arm, rigid_materials=None):
    """Deterministyczny skinning po połączonej powierzchni, maks. cztery kości.

Pięć nasion na odcinek kości, Dijkstra po krawędziach i miękki spadek wpływu.
Luźne detale bez ścieżki używają odległości przestrzennej z karą. Rekwizyt
może mieć jawne przypisanie materiał -> kość i nie łączy grafu z ciałem.
"""
    rigid_materials = rigid_materials or {}
    points = np.array([(body.matrix_world @ v.co)[:] for v in body.data.vertices])
    height = float(np.ptp(points, axis=0).max())
    rigid = {}
    used = set()
    for polygon in body.data.polygons:
        bone_name = rigid_materials.get(polygon.material_index)
        for index in polygon.vertices:
            if bone_name is None:
                used.add(index)
            else:
                rigid[index] = bone_name
    if not used or used.intersection(rigid):
        raise RuntimeError("Brak ciała albo wspólne wierzchołki ciała i rekwizytu")
    used = np.array(sorted(used), dtype=np.int64)
    adjacency = [{} for _ in points]
    for edge in body.data.edges:
        a, b = edge.vertices
        if a in rigid or b in rigid:
            continue
        length = float(np.linalg.norm(points[a] - points[b]))
        adjacency[a][b] = length
        adjacency[b][a] = length
    names, segments = [], []
    for bone in arm.data.bones:
        if bone.name.endswith(":Root"):
            continue
        a = np.array(arm.matrix_world @ bone.head_local)
        b = np.array(arm.matrix_world @ bone.tail_local)
        # glTF nie zapisuje końców liści; importer przedłuża Hand o całe
        # przedramię. Do wag użyj długości z rig_trellis, bez zmiany inverse bind.
        if bone.name.endswith(("Hand", "ToeBase")):
            length = height * (0.08 if bone.name.endswith("Hand") else 0.04)
            b = a + (b - a) / max(float(np.linalg.norm(b - a)), 1e-9) * length
        names.append(bone.name)
        segments.append((a, b))
    distances = np.empty((len(points), len(names)))
    for k, (a, b) in enumerate(segments):
        ab = b - a
        t = np.clip(((points - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
        spatial = np.linalg.norm(points - a - t[:, None] * ab, axis=1)
        surface = np.full(len(points), np.inf)
        queue = []
        for fraction in (0.0, 0.25, 0.5, 0.75, 1.0):
            sample = a + ab * fraction
            nearest = int(used[np.argmin(np.sum((points[used] - sample) ** 2, axis=1))])
            cost = float(np.linalg.norm(points[nearest] - sample))
            if cost < surface[nearest]:
                surface[nearest] = cost
                heapq.heappush(queue, (cost, nearest))
        while queue:
            distance, index = heapq.heappop(queue)
            if distance > surface[index] + 1e-12:
                continue
            for neighbour, length in adjacency[index].items():
                candidate = distance + length
                if candidate < surface[neighbour]:
                    surface[neighbour] = candidate
                    heapq.heappush(queue, (candidate, neighbour))
        distances[:, k] = np.where(np.isfinite(surface), surface, spatial + height * 0.25)
    weights = 1.0 / (distances + height * 0.025) ** 4
    for group in list(body.vertex_groups):
        body.vertex_groups.remove(group)
    groups = [body.vertex_groups.new(name=name) for name in names]
    for index in range(len(points)):
        if index in rigid:
            groups[names.index(rigid[index])].add([index], 1.0, "REPLACE")
            continue
        keep = np.argsort(-weights[index])[:4]
        values = weights[index, keep]
        values /= values.sum()
        for group, weight in zip(keep, values):
            groups[group].add([index], float(weight), "REPLACE")
    print("SURFACE WEIGHTS", len(points), "vertices,", len(names), "bones")
