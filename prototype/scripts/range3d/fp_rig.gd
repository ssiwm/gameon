extends Node3D
## Ręce FPP z zasobu (strzelnica, RANGE_FPS_PLAN.md): `art/char3d/fp/fp_arms_<strój>.glb` z `tools/fp_arms.py` (rękawice, rękawy M65
## z karczkiem, zegarek; szkielet postaci) i `tools/fp_grip.py` (klip `grip_<broń>` — dłonie i palce ułożone na modelu broni do kontaktu,
## oraz węzeł `gunref_<broń>` na kości prawej dłoni). Model broni gry (gun_model.gd — części i nacięcia gracza) jest dzieckiem tego
## węzła, więc broń i dłonie poruszają się jako jedna bryła: chwyt jest taki, jak ułożony w Blenderze, co do milimetra.
## Broń bez ułożonego chwytu (`has_grip`) zostaje przy rękach z modelu postaci (fp_arms.gd).

const PATH := "res://art/char3d/fp/fp_arms_scav.glb"
const META := "res://art/char3d/fp/fp_arms_scav.json"   ## momenty przeładowań z fp_grip.py: {broń: {klip: {secs, mag_out, mag_in}}}

var ok := false
var key := ""                          ## broń z bieżącym chwytem ("" — brak)
var _scene: Node3D
var _anim: AnimationPlayer
var _ref: Node3D
var _skel: Skeleton3D
var _meta := {}
var _clip := ""                         ## bieżący klip ("grip_…" / "reload_…")
var _mag: Node3D                        ## magazynek modelu broni (węzeł „…__mag”) — w trakcie przeładowania jedzie z lewą dłonią
var _mag_rest := Transform3D.IDENTITY
var _mag_off := Transform3D.IDENTITY    ## magazynek względem lewej dłoni (z chwili chwytu)
var _mag_held := false

func setup() -> bool:
	if not ResourceLoader.exists(PATH):
		return false
	_scene = (load(PATH) as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_anim = _scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skel = _scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if FileAccess.file_exists(META):
		_meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	for mi in _scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 1.0                                  # siatka skinowana tuż przed kamerą: bez odrzucania po AABB spoczynku
	ok = _anim != null
	visible = false
	return ok

func has_grip(k: String) -> bool:
	return ok and _anim.has_animation("grip_" + k) and _scene.find_child("gunref_" + k, true, false) != null

## Poza chwytu broni `k` i przypięcie modelu broni `gun` do jej punktu odniesienia. false — brak chwytu (broń zostaje, gdzie była).
func set_weapon(k: String, gun: Node3D) -> bool:
	if not has_grip(k):
		key = ""
		visible = false
		return false
	key = k
	_clip = ""
	_mag_held = false
	_pose("grip_" + k, 0.0)
	_ref = _scene.find_child("gunref_" + k, true, false) as Node3D
	if gun.get_parent() != null:
		gun.get_parent().remove_child(gun)
	_ref.add_child(gun)
	gun.transform = Transform3D.IDENTITY
	_mag = null
	for n in gun.find_children("*__mag", "Node3D", true, false):
		_mag = n as Node3D
		_mag_rest = _mag.transform
		break
	visible = true
	return true

## Poza w danej chwili: chwyt albo przeładowanie (`empty` — z pustego, z odciągnięciem suwadła) w postępie `u` 0..1 (WeaponController.reload_progress).
## Magazynek przechodzi do lewej dłoni od `mag_out` do `mag_in` klipu.
func animate(reloading: bool, empty: bool, u: float) -> void:
	if key == "":
		return
	var clip := ("reload_empty_" if empty else "reload_") + key
	if not reloading or not _anim.has_animation(clip):
		_release_mag()
		_pose("grip_" + key, 0.0)
		return
	_pose(clip, u * _anim.get_animation(clip).length)
	var m: Dictionary = _meta.get(key, {}).get(clip.trim_suffix("_" + key), {})
	if _mag == null or m.is_empty():
		return
	var held := u >= float(m["mag_out"]) and u < float(m["mag_in"])
	if held and not _mag_held:
		_mag_off = hand_global("Left").affine_inverse() * _mag.global_transform
		_mag_held = true
	elif not held:
		_release_mag()
	if _mag_held:
		_mag.global_transform = hand_global("Left") * _mag_off

func _release_mag() -> void:
	if _mag != null and _mag_held:
		_mag.transform = _mag_rest
	_mag_held = false

func _pose(clip: String, t: float) -> void:
	if clip != _clip:
		_clip = clip
		_anim.play(clip)
		_anim.pause()
	_anim.seek(t, true)

## Kość dłoni w świecie (po bieżącej pozie).
func hand_global(side: String) -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sHand" % side))

## Broń w układzie tego węzła (z bieżącej pozy szkieletu) — do ustawienia całych rąk tak, by broń stała w zadanym miejscu kadru.
func gun_in_rig() -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = _ref
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
