extends RefCounted
## Model 3D broni z częściami (GUNSMITH_PLAN.md etap 2b, od 1.7.320): broń bazowa `gun_<klucz>.glb` ma podzespoły w osobnych węzłach
## (`gun_<klucz>__mag`, `__stock`, `__front`, `__muzzle` — tools/gun_proc.py, `with comp(...)`), a części z modelem to osobne pliki
## `gunpart_<id>.glb` + `.json` {mount, hides, muzzle, muzzle_add} z tego samego generatora i w tej samej skali.
##
## Składanie: podzespoły, które część zastępuje (`hides`), znikają; część „frame” (magazynek, kolba, przód z lufą) siedzi w układzie broni,
## część „muzzle” (tłumik, płomieniotłumik, lufa z portami) — na wylocie założonej lufy. Fabryczne urządzenie wylotowe (`__muzzle`) jedzie razem
## z wylotem, gdy lufa jest dłuższa albo krótsza. Wylot pocisku (`muzzle`) = wylot lufy + o ile część wydłuża broń za nim (`muzzle_add`).
## Części bez modelu (np. dławik w środku lufy, mechanizm) nie zmieniają wyglądu.

const DIR := "res://art/char3d/"
const Parts := preload("res://scripts/parts.gd")

static var _pinfo: Dictionary = {}

## Dane modelu części w układzie Godota (x wzdłuż lufy, y w górę) albo pusty słownik, gdy część nie ma modelu.
static func part_info(id: String) -> Dictionary:
	if _pinfo.has(id):
		return _pinfo[id]
	var out := {}
	var path := DIR + "gunpart_%s.json" % id
	if FileAccess.file_exists(path) and ResourceLoader.exists(DIR + "gunpart_%s.glb" % id):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		out = {"mount": String(d.get("mount", "frame")), "hides": Array(d.get("hides", [])), "muzzle_add": float(d.get("muzzle_add", 0.0))}
		if d.has("muzzle"):
			var a: Array = d["muzzle"]
			out["muzzle"] = Vector3(float(a[0]), float(a[2]), -float(a[1]))       # Blender (x, y, z) → Godot (x, z, −y)
	_pinfo[id] = out
	return out

static func has_model(id: String) -> bool:
	return not part_info(id).is_empty()

## Wylot lufy z częściami `ids` (przód z lufą może go przesunąć) — bez urządzeń wylotowych.
static func barrel_muzzle(base_muzzle: Vector3, ids: Array) -> Vector3:
	var m := base_muzzle
	for id in ids:
		var pi := part_info(String(id))
		if pi.has("muzzle"):
			m = pi["muzzle"]
	return m

## Wylot pocisku: wylot lufy + wydłużenie za nim (tłumik, płomieniotłumik).
static func muzzle(base_muzzle: Vector3, ids: Array) -> Vector3:
	var add := 0.0
	for id in ids:
		add += float(part_info(String(id)).get("muzzle_add", 0.0))
	return barrel_muzzle(base_muzzle, ids) + Vector3(add, 0.0, 0.0)

## Składa model broni `key` z częściami `ids` (Parts.decode). `base_muzzle` = wylot fabryczny (Char3D.gun_info). `notches` — nacięcia na kolbie
## (historia broni, GUNSMITH_PLAN §7.4), z czego `deep` głębokich (bossowie). `src_dir` — katalog modelu bazowego (strzelnica FPP: `fp/` z
## teksturami 4K; brak pliku — model z gry). Zwraca nowy węzeł (do dodania przez wołającego).
static func build(key: String, ids: Array, base_muzzle: Vector3, notches := 0, deep := 0, src_dir := DIR) -> Node3D:
	var path := src_dir + "gun_%s.glb" % key
	var root := (load(path if ResourceLoader.exists(path) else DIR + "gun_%s.glb" % key) as PackedScene).instantiate() as Node3D
	var hide := {}
	for id in ids:
		for h in part_info(String(id)).get("hides", []):
			hide[String(h)] = true
	var bm := barrel_muzzle(base_muzzle, ids)
	for n in root.find_children("*__*", "MeshInstance3D", true, false):
		var compn := String(n.name).get_slice("__", 1)
		if hide.has(compn):
			n.get_parent().remove_child(n)
			n.free()
		elif compn == "muzzle":
			(n as Node3D).position += bm - base_muzzle          # fabryczne urządzenie wylotowe na końcu dłuższej / krótszej lufy
	for id in ids:
		var pi := part_info(String(id))
		if pi.is_empty():
			continue
		var pn := (load(DIR + "gunpart_%s.glb" % id) as PackedScene).instantiate() as Node3D
		if String(pi["mount"]) == "muzzle":
			pn.position = bm
		root.add_child(pn)
	if notches > 0:
		add_notches(root, notches, deep)
	return root

const NOTCH_W := 0.0045              ## m — szerokość nacięcia (wzdłuż broni)
const NOTCH_GAP := 0.011             ## m — odstęp między nacięciami
const NOTCH_H := 0.022               ## m — wysokość nacięcia; głębokie (boss) ×1,6
const NOTCH_FROM := 0.035            ## m od tyłu broni, gdzie zaczyna się rząd

static var _notch_mat: StandardMaterial3D

## Nacięcia nożem na kolbie (albo chwycie): rząd ciemnych rys po obu bokach broni, od tyłu do przodu. Każda rysa siada na prawdziwej powierzchni
## modelu — promień z boku w siatkę trójkątów (bez tego rysy wisiałyby w powietrzu przy kolbie o nieregularnym kształcie). Broń bez kolby
## (pistolet) dostaje je na chwycie — to też tył broni.
static func add_notches(root: Node3D, n: int, deep := 0) -> void:
	var meshes: Array = []
	var box := AABB()
	var first := true
	for mn in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mn as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _xf_in(mi, root)
		var bb: AABB = xf * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
		meshes.append([mi.mesh.generate_triangle_mesh(), xf])
	if first:
		return
	if _notch_mat == null:
		_notch_mat = StandardMaterial3D.new()
		_notch_mat.albedo_color = Color(0.06, 0.04, 0.03)
		_notch_mat.roughness = 1.0
	var bmesh := BoxMesh.new()
	for side in [1.0, -1.0]:
		for i in n:
			var x := box.position.x + NOTCH_FROM + float(i) * NOTCH_GAP
			var h := NOTCH_H * (1.6 if i < deep else 1.0)
			# najwyżej położony punkt boku broni w tym miejscu (szukamy od góry w dół): tam idzie rysa
			var hit := {}
			var y := box.end.y - 0.01
			while y > box.position.y and hit.is_empty():
				hit = _side_hit(meshes, Vector3(x, y, side * (box.size.z + 0.2)), Vector3(x, y, 0.0))
				y -= 0.006
			if hit.is_empty():
				continue
			var top: Vector3 = hit["position"]
			# środek rysy jest niżej niż krawędź (fazka) — bok w tym miejscu wyznacza drugi promień, inaczej rysa chowa się w drewnie
			var yc := top.y - h * 0.5 - 0.004
			var mid := _side_hit(meshes, Vector3(x, yc, side * (box.size.z + 0.2)), Vector3(x, yc, 0.0))
			var pz: float = (mid["position"] as Vector3).z if not mid.is_empty() else top.z
			var mi := MeshInstance3D.new()
			mi.name = "notch"
			mi.mesh = bmesh
			mi.material_override = _notch_mat
			mi.position = Vector3(x, yc, pz - side * 0.0008)
			mi.scale = Vector3(NOTCH_W, h, 0.003)
			root.add_child(mi)

static func _side_hit(meshes: Array, a: Vector3, b: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for m in meshes:
		var tm: TriangleMesh = m[0]
		var inv: Transform3D = (m[1] as Transform3D).affine_inverse()
		var r: Dictionary = tm.intersect_segment(inv * a, inv * b)
		if r.is_empty():
			continue
		var wp: Vector3 = (m[1] as Transform3D) * (r["position"] as Vector3)
		var d := a.distance_to(wp)
		if d < best_d:
			best_d = d
			best = {"position": wp}
	return best

static func _xf_in(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var up := n.get_parent()
	while up != null and up != root and up is Node3D:
		xf = (up as Node3D).transform * xf
		up = up.get_parent()
	return xf
