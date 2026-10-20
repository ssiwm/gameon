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

## Składa model broni `key` z częściami `ids` (Parts.decode). `base_muzzle` = wylot fabryczny (Char3D.gun_info). Zwraca nowy węzeł (do dodania przez wołającego).
static func build(key: String, ids: Array, base_muzzle: Vector3) -> Node3D:
	var root := (load(DIR + "gun_%s.glb" % key) as PackedScene).instantiate() as Node3D
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
	return root
