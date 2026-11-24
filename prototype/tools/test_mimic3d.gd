extends SceneTree
## Widok 3D przebranego Mimika (MIMIC_PLAN.md M1–M2, enemy3d.gd SPEC `carry` / `eye_shine`): w przebraniu broń w obu dłoniach (chwyt w prawej,
## lufa w dół i do przodu — nie celuje), bez oddechu i bez świecących oczu; w snopie latarki oczy łapią połysk, klatka piersiowa oddycha,
## a twarz odwraca się od kamery; po demaskacji broń wypada z rąk i ląduje na ziemi, oczy świecą stale; przy ponownym przebraniu (restart)
## broń wraca do dłoni. Przemiana (M7): przedramiona dłuższe o ~42%, nakładka materiału (skóra z żyłami, szary mundur), większe oczy,
## plecak spada i leży na ziemi, głowa skręca się za daleko w szarpnięciu, chód pochylony z rękami niżej; restart wraca do przebrania.
##   godot --headless --path prototype -s tools/test_mimic3d.gd
const Enemy3D := preload("res://scripts/enemy3d.gd")
const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0

var _fails := 0
var _e: Node3D

func _ok(cond: bool, msg: String) -> void:
	print("[MIMIC-3D] %s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		_fails += 1

func _initialize() -> void:
	_e = Enemy3D.new()
	root.add_child(_e)
	_e.set("life_seed", 11)
	_ok(_e.setup("mimik"), "model Mimika")
	_go.call_deferred()

func _ctx(disguised: bool, lit: float) -> void:
	_e.call("motion_context", {"disguised": disguised, "lit": lit, "grounded": true})

## `secs` s póz; zwraca rozrzut obrotu klatki piersiowej (Spine2) w stopniach — miara oddechu.
func _run(secs: float, disguised: bool, lit: float) -> float:
	var sk: Skeleton3D = _e.get("_sk")
	var b: Dictionary = _e.get("_b")
	var lo := INF
	var hi := -INF
	for i in int(secs / DT):
		_ctx(disguised, lit)
		_e.call("pose", DT, "idle", false, Color.WHITE)
		var q := sk.get_bone_global_pose(b["Spine2"]).basis.get_euler()
		lo = minf(lo, q.z)
		hi = maxf(hi, q.z)
	return rad_to_deg(hi - lo)

## `secs` s póz z czasem od demaskacji od `since0`.
func _run_since(secs: float, since0: float, anim := "idle") -> void:
	var t := since0
	for i in int(secs / DT):
		_e.call("motion_context", {"disguised": false, "lit": 0.0, "grounded": true, "since_reveal": t})
		_e.call("pose", DT, anim, false, Color.WHITE, 0.0, 1, true, 0.0, 0, false, 95.0, 95.0 * DT)
		t += DT

func _forearm() -> float:
	var sk: Skeleton3D = _e.get("_sk")
	var b: Dictionary = _e.get("_b")
	return sk.get_bone_global_pose(b["RightForeArm"]).origin.distance_to(sk.get_bone_global_pose(b["RightHand"]).origin)

func _hand_y() -> float:
	var sk: Skeleton3D = _e.get("_sk")
	var b: Dictionary = _e.get("_b")
	return (sk.global_transform * sk.get_bone_global_pose(b["RightHand"]).origin).y - _e.global_position.y

func _gear_mesh(n: String) -> MeshInstance3D:
	for m in (_e.get("_model") as Node).find_children("*", "MeshInstance3D", true, false):
		if String(m.name) == n:
			return m
	return null

func _eyes_visible() -> bool:
	for m in _e.get("_eyes"):
		if (m as Node3D).visible:
			return true
	return false

## Kierunek twarzy w świecie (oś przodu kości głowy w spoczynku → w pozie).
func _face_dir() -> Vector3:
	var sk: Skeleton3D = _e.get("_sk")
	var b: Dictionary = _e.get("_b")
	var head: int = b["Head"]
	var rest := sk.get_bone_global_rest(head)
	var pose := sk.get_bone_global_pose(head)
	var fwd_rest := rest.basis.inverse() * Vector3.RIGHT       # przód modelu (+X) w układzie kości głowy
	return (sk.global_transform.basis * (pose.basis * fwd_rest)).normalized()

func _go() -> void:
	await process_frame
	# przebrany, ciemno
	var calm := _run(4.0, true, 0.0)
	var gun: Node3D = _e.get("_carry_gun")
	_ok(gun != null and gun.visible and gun.get_parent() != _e.get_parent(), "przebrany: broń w dłoniach (widoczna, w modelu)")
	if gun != null:
		var sk: Skeleton3D = _e.get("_sk")
		var palm: Vector3 = sk.global_transform * Vector3(_e.call("_palm", "Right"))
		var info: Dictionary = Char3D.gun_info("m83")
		var grip: Vector3 = gun.global_transform * (info["rear"] as Vector3)
		var muzzle: Vector3 = gun.global_transform * (info["muzzle"] as Vector3)
		var fwd := _e.global_transform.basis * Vector3.RIGHT
		_ok(grip.distance_to(palm) < 0.03, "przebrany: chwyt w prawej dłoni (%.3f m)" % grip.distance_to(palm))
		var drop := grip.y - muzzle.y
		_ok(drop > 0.12 and (muzzle - grip).dot(fwd) > 0.2, "przebrany: lufa w dół i do przodu — nie celuje (spadek %.2f m)" % drop)
		var pl: Vector3 = sk.global_transform * Vector3(_e.call("_palm", "Left"))
		var axis := ((info["fore"] as Vector3) - (info["rear"] as Vector3)).normalized()
		var off := (pl - grip) - (gun.global_basis.orthonormalized() * axis) * (pl - grip).dot(gun.global_basis.orthonormalized() * axis)
		_ok(off.length() < 0.03, "przebrany: lewa dłoń na osi broni (%.3f m)" % off.length())
	_ok(calm < 0.15, "przebrany w ciemności nie oddycha (klatka %.2f°)" % calm)
	_ok(not _eyes_visible(), "przebrany w ciemności: oczy nie świecą")
	var face_dark := _face_dir()
	# snop latarki
	var lit := _run(4.0, true, 1.0)
	_ok(lit > 0.8, "w snopie oddycha głęboko (klatka %.2f°)" % lit)
	_ok(_eyes_visible(), "w snopie: połysk oczu")
	var face_lit := _face_dir()
	_ok(face_lit.z < face_dark.z - 0.3 and face_lit.y < face_dark.y, "w snopie: twarz odwrócona od kamery i opuszczona (z %.2f → %.2f, y %.2f → %.2f)" % [face_dark.z, face_lit.z, face_dark.y, face_lit.y])
	# demaskacja
	_run(0.2, false, 0.0)
	var dropped: Node3D = gun
	await create_timer(0.7).timeout             # tween upadku broni idzie w czasie gry, nie w pętli póz
	_ok(_e.get("_carry_gun") == null and dropped != null and is_instance_valid(dropped) and dropped.get_parent() == _e.get_parent(),
			"demaskacja: broń wypada z rąk do świata")
	if dropped != null and is_instance_valid(dropped):
		_ok(absf(dropped.global_position.y - (_e.global_position.y + 0.03)) < 0.02, "demaskacja: broń leży na ziemi (y %.3f)" % dropped.global_position.y)
		_ok(absf(dropped.global_basis.orthonormalized().x.y) < 0.05, "demaskacja: broń leży płasko")
	_ok(_eyes_visible(), "zdemaskowany: oczy świecą stale")
	var awake := _run(4.0, false, 0.0)
	_ok(awake > 0.15, "zdemaskowany oddycha zwyczajnie (klatka %.2f°)" % awake)
	# przemiana (M7)
	var arm0 := _forearm()
	_run_since(0.5, -1.0, "walk")
	var hand_walk0 := _hand_y()
	_run_since(0.3, 0.0)
	var face_turn := _face_dir()
	_run_since(1.2, 0.3)
	var face_after := _face_dir()
	var arm1 := _forearm()
	_ok(absf(arm1 / arm0 - 1.42) < 0.03, "przemiana: przedramiona dłuższe ×%.2f" % (arm1 / arm0))
	_ok(face_turn.angle_to(face_after) > deg_to_rad(35.0), "przemiana: głowa skręca się za daleko w szarpnięciu (%.0f°)" % rad_to_deg(face_turn.angle_to(face_after)))
	var mats: Array = _e.get("_morph_mats")
	var amount := float((mats[0] as ShaderMaterial).get_shader_parameter("amount")) if not mats.is_empty() else 0.0
	var skin := false
	for m in mats:
		skin = skin or float((m as ShaderMaterial).get_shader_parameter("skin")) > 0.5
	_ok(mats.size() >= 3 and skin and is_equal_approx(amount, 1.0), "przemiana: nakładka na stroju i skórze (%d, skóra %s, %.2f)" % [mats.size(), skin, amount])
	var eye_s := ((_e.get("_eyes") as Array)[0] as Node3D).scale.x
	_ok(eye_s > 1.7, "przemiana: oczy większe (×%.2f)" % eye_s)
	var pack := _gear_mesh("backpack")
	var lying: Node3D = _e.get("_gear_drop")
	await create_timer(0.6).timeout
	var bottom := INF
	if lying != null and is_instance_valid(lying):
		for c in lying.get_children():
			var mi := c as MeshInstance3D
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			bottom = minf(bottom, ab.position.y - _e.global_position.y)
	_ok(pack != null and not pack.visible and lying != null and is_instance_valid(lying) and lying.get_parent() == _e.get_parent()
			and absf(bottom) < 0.12 and absf(lying.global_position.x - _e.global_position.x) < 1.0,
			"przemiana: plecak spada z pleców i leży przy nim (spód %.2f m nad ziemią)" % bottom)
	_run_since(0.5, 2.0, "walk")
	var hand_walk1 := _hand_y()
	_ok(hand_walk1 < hand_walk0 - 0.1 and hand_walk1 > 0.15, "przemiana: chód pochylony, dłonie niżej (%.2f → %.2f m), nad ziemią" % [hand_walk0, hand_walk1])
	# hitbox kontra model po wydłużeniu (enemy_defs.gd: strefa trafień `hurt_h` 22 px, zasięg ciosu 14 px od krawędzi ciała 10 px)
	var sk: Skeleton3D = _e.get("_sk")
	var b: Dictionary = _e.get("_b")
	var worst_x := 0.0
	var top := 0.0
	var low := INF
	for i in 40:
		_run_since(DT * 3.0, 2.5 + i * 0.05, "walk" if i % 2 == 0 else "idle")
		for side in ["Left", "Right"]:
			var hp := sk.global_transform * sk.get_bone_global_pose(b[side + "Hand"]).origin
			worst_x = maxf(worst_x, absf(hp.x - _e.global_position.x))
			low = minf(low, hp.y - _e.global_position.y)
		top = maxf(top, (sk.global_transform * sk.get_bone_global_pose(b["Head"]).origin).y - _e.global_position.y)
	const PXM := 1.8 / 22.0
	_ok(worst_x < (5.0 + 14.0) * PXM and low > 0.1 and top < 22.0 * PXM, "przemiana: dłonie w zasięgu ciosu (%.2f m < %.2f) i nad ziemią (%.2f m), głowa w strefie trafień (%.2f m < %.2f)" % [worst_x, 19.0 * PXM, low, top, 22.0 * PXM])
	# restart: znów przebrany
	_run(1.0, true, 0.0)
	var again: Node3D = _e.get("_carry_gun")
	_ok(again != null and again != dropped and again.visible, "ponowne przebranie (restart): nowa broń w dłoniach")
	_ok(absf(_forearm() / arm0 - 1.0) < 0.01 and pack.visible and not is_instance_valid(lying) or (lying != null and lying.is_queued_for_deletion()),
			"restart: przedramiona i plecak wracają, leżący plecak znika")
	var amount2 := float((mats[0] as ShaderMaterial).get_shader_parameter("amount")) if not mats.is_empty() else -1.0
	_ok(is_zero_approx(amount2), "restart: bez nakładki przemiany")
	print("[MIMIC-3D] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
