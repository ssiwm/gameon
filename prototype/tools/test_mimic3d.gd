extends SceneTree
## Widok 3D przebranego Mimika (MIMIC_PLAN.md M1–M2, enemy3d.gd SPEC `carry` / `eye_shine`): w przebraniu broń w obu dłoniach (chwyt w prawej,
## lufa w dół i do przodu — nie celuje), bez oddechu i bez świecących oczu; w snopie latarki oczy łapią połysk, klatka piersiowa oddycha,
## a twarz odwraca się od kamery; po demaskacji broń wypada z rąk i ląduje na ziemi, oczy świecą stale; przy ponownym przebraniu (restart)
## broń wraca do dłoni.
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
	# restart: znów przebrany
	_run(1.0, true, 0.0)
	var again: Node3D = _e.get("_carry_gun")
	_ok(again != null and again != dropped and again.visible, "ponowne przebranie (restart): nowa broń w dłoniach")
	print("[MIMIC-3D] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
