extends RefCounted
## Mechanika widocznej broni TPP: części rzeczywiście ruszają się razem z dłonią.
## Osobne instancje dla obrazu i mapy normalnych; brak zmian amunicji lub kolizji.
var _root: Node3D
var _parts: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _mag: Array[Node3D] = []
var _mag_center: Array[Vector3] = []

func bind(gun: Node3D) -> void:
	_root = gun
	for node in gun.find_children("*__*", "Node3D", true, false):
		var kind := String(node.name).get_slice("__", 1)
		if kind in ["mag", "bolt", "trigger", "pump"]:
			_parts.append(node)
			_rest.append(node.transform)
			if kind == "mag":
				_add_mag(node)
	for node in gun.get_children():
		if node is Node3D and (node.get_meta("replaces", []) as Array).has("mag"):
			_parts.append(node)
			_rest.append(node.transform)
			_add_mag(node)

func _add_mag(node: Node3D) -> void:
	_mag.append(node)
	var center := Vector3.ZERO
	if node is MeshInstance3D:
		center = (node as MeshInstance3D).get_aabb().get_center()
	else:
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var mesh: MeshInstance3D = meshes[0]
			center = node.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb().get_center())
	_mag_center.append(center)

func pose(hand: Transform3D, palm: Vector3, kind: String, reload_t: float, cycle_t: float, fire_t: float, info: Dictionary, variant: int) -> void:
	for i in _parts.size():
		_parts[i].transform = _rest[i]
	var pull := sin(PI * clampf((cycle_t - 0.12) / 0.6, 0.0, 1.0)) if kind == "shell" and cycle_t >= 0.0 else 0.0
	var slide := sin(PI * clampf(fire_t / 0.065, 0.0, 1.0)) if fire_t >= 0.0 else 0.0
	if reload_t >= 0.0 and variant in [1, 3]:
		slide = maxf(slide, sin(PI * clampf((reload_t - 0.80) / 0.12, 0.0, 1.0)))
	for node in _parts:
		var component := String(node.name).get_slice("__", 1)
		if component == "bolt":
			node.position.x -= float(info.get("slide", 0.06)) * slide
		elif component == "pump" and pull > 0.0:
			node.position.x -= 0.17 * pull
		elif component == "trigger" and fire_t >= 0.0 and fire_t < 0.12:
			var pivot: Vector3 = info.get("trigger", Vector3(0.0, -0.06, 0.0))
			var rotation := Basis(Vector3.BACK, deg_to_rad(-6.0) * (1.0 - fire_t / 0.12))
			node.transform *= Transform3D(rotation, pivot - rotation * pivot)
	if reload_t < 0.0 or kind not in ["mag", "pistol", "cell", "rail"] or variant == 3:
		return
	# W gnieździe → dłoń → gniazdo. Łączenie jest ciągłe także przy pierwszym snapshotcie w środku akcji.
	var carry := smoothstep(0.14, 0.28, reload_t) * (1.0 - smoothstep(0.64, 0.76, reload_t))
	for i in _mag.size():
		var node := _mag[i]
		var destination := node.global_transform
		destination.basis = destination.basis.slerp(hand.basis, carry * 0.25)
		destination.origin = palm - destination.basis * _mag_center[i]
		node.global_transform = node.global_transform.interpolate_with(destination, carry)
