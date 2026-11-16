extends SceneTree
## Warstwa spoczynku wrogów (IDLE_PLAN.md I1–I2, idle_life.gd): to samo ziarno daje ten sam przebieg, różne ziarna rozjeżdżają fazę i okres
## oddechu, oddech nie zależy od liczby klatek, ciężar zmienia nogę w zadanym rytmie, tiki mają odstępy z profilu i gasną u niespokojnego.
## Na modelach dwunożnych: przez 30 s snu i czuwania dłonie zostają poniżej barków (tik nie wygląda jak zapowiedź ciosu), a pozy różnych
## egzemplarzy się różnią. Pozy snu według rodzaju (I2, SPEC `sleep_pose`): śpiący jest niski (najwyżej 2/3 wysokości strefy trafień),
## kości mieszczą się w szerokości hitboxa z symulacji (D1), a skóra nie wchodzi w podłogę (kolana, pięści, pośladki).
##   godot --headless --path prototype -s tools/test_idle_life.gd
const IdleLife := preload("res://scripts/idle_life.gd")
const Enemy3D := preload("res://scripts/enemy3d.gd")
const KINDS := ["slepiec", "podsluchacz", "stalker", "wolek", "kaplan", "rzeznik", "mimik"]
const PX := 1.8 / 22.0
var EnemyDefs: GDScript                      ## enemy_defs.gd używa autoloadów: ładowany po pierwszej klatce

var _fails := 0
var _frames := 0
var _models: Array = []                      ## [rodzaj, Enemy3D, animacja, max (dłoń − bark) w m, ślad pozy głowy]
var _heed: Array = []                        ## [rodzaj, nasłuchujący, kontrolny] — I4: ten sam sen, jeden „prawie usłyszał” hałas zza pleców
const HEED_KINDS := ["wolek", "kaplan", "slepiec", "rzeznik", "trzosek", "mimik"]

func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("[IDLE-LIFE] FAIL ", msg)

func _initialize() -> void:
	_test_determinism()
	_test_desync()
	_test_framerate()
	_test_shift()
	_test_tics()
	for k in KINDS:
		for anim in ["sleep", "idle"]:
			for seed_value in [11, 12]:
				var e: Node3D = Enemy3D.new()
				root.add_child(e)
				e.set("life_seed", seed_value)
				if not e.setup(k):
					_ok(false, "setup %s" % k)
					e.free()
					continue
				_models.append([k, e, anim, -INF, []])
	for k in HEED_KINDS:
		var pair := [k]
		for i in 2:
			var e: Node3D = Enemy3D.new()
			root.add_child(e)
			e.set("life_seed", 11)
			if not e.setup(k):
				_ok(false, "setup %s" % k)
			if i == 0:
				e.set("heed", Vector3(-150.0, -20.0, 1.0))      # za plecami (patrzy w prawo), trochę wyżej
			pair.append(e)
		_heed.append(pair)

func _trace(seed_value: int, dt: float, secs: float) -> Array:
	var l := IdleLife.new(seed_value, {"tics": ["jerk", "look"], "rate": [2.0, 5.0]})
	var out := []
	var n := int(secs / dt)
	for i in n:
		l.step(dt, false)
		out.append([l.breath(), l.shift, l.tic, l.tic_k])
	return out

func _test_determinism() -> void:
	_ok(_trace(7, 1.0 / 60.0, 30.0) == _trace(7, 1.0 / 60.0, 30.0), "to samo ziarno → ten sam przebieg")
	_ok(_trace(7, 1.0 / 60.0, 30.0) != _trace(8, 1.0 / 60.0, 30.0), "inne ziarno → inny przebieg")

func _test_desync() -> void:
	var phases := []
	var periods := []
	for s in 40:
		var l := IdleLife.new(1000 + s)
		phases.append(l.breath_phase())
		periods.append(l.period)
		_ok(l.period >= 2.4 * (1.0 - IdleLife.BREATH_SPREAD) - 0.001 and l.period <= 2.4 * (1.0 + IdleLife.BREATH_SPREAD) + 0.001, "okres oddechu w rozrzucie: %.3f" % l.period)
	# fazy rozłożone na całym cyklu: w każdej ćwiartce coś jest
	var q := [0, 0, 0, 0]
	for ph in phases:
		q[int(fposmod(float(ph), TAU) / TAU * 4.0) % 4] += 1
	_ok(q.min() >= 4, "fazy oddechu 40 egzemplarzy rozłożone na ćwiartki: %s" % str(q))
	_ok(periods.max() - periods.min() > 0.3, "okresy oddechu różne")

func _test_framerate() -> void:
	# oddech zależy tylko od czasu: 30 i 144 kl./s po 10 s dają to samo wypełnienie płuc
	var a := IdleLife.new(3)
	var b := IdleLife.new(3)
	for i in 300:
		a.step(1.0 / 30.0, false)
	for i in 1440:
		b.step(1.0 / 144.0, false)
	_ok(absf(a.breath() - b.breath()) < 0.02, "oddech niezależny od FPS: %.3f vs %.3f" % [a.breath(), b.breath()])
	var c := IdleLife.new(3)
	var before := c.breath()
	c.step(0.0, false)
	_ok(c.breath() == before, "krok 0 s nic nie zmienia")

func _test_shift() -> void:
	var l := IdleLife.new(5)
	var changes := 0
	var last_side := signf(l.shift)
	var max_abs := 0.0
	var dt := 1.0 / 60.0
	for i in int(120.0 / dt):
		l.step(dt, false)
		max_abs = maxf(max_abs, absf(l.shift))
		var side := signf(l.shift)
		if side != 0.0 and side != last_side:
			changes += 1
			last_side = side
	_ok(max_abs <= 1.0, "ciężar w −1..1")
	# 120 s przy 4–9 s stania + 1,2 s przenoszenia → 11–23 zmian nogi
	_ok(changes >= 10 and changes <= 25, "zmiany nogi w 120 s: %d" % changes)

func _test_tics() -> void:
	var dt := 1.0 / 60.0
	var l := IdleLife.new(9, {"tics": ["jerk"], "rate": [3.0, 6.0]})
	var starts := []
	var was := ""
	var max_k := 0.0
	for i in int(120.0 / dt):
		l.step(dt, false)
		if l.tic != "" and was == "":
			starts.append(l.t)
		was = l.tic
		max_k = maxf(max_k, l.tic_k)
	_ok(starts.size() >= 15 and starts.size() <= 42, "tików w 120 s (odstęp 3–6 s): %d" % starts.size())
	for i in range(1, starts.size()):
		_ok(starts[i] - starts[i - 1] >= 3.0 - 0.05, "odstęp tików ≥ 3 s: %.2f" % (starts[i] - starts[i - 1]))
	_ok(max_k > 0.9 and max_k <= 1.0, "obwiednia tiku do 1: %.2f" % max_k)
	# śpiący wierci się rzadziej
	var s := IdleLife.new(9, {"tics": ["jerk"], "rate": [3.0, 6.0]})
	var n_sleep := 0
	was = ""
	for i in int(120.0 / dt):
		s.step(dt, true)
		if s.tic != "" and was == "":
			n_sleep += 1
		was = s.tic
	_ok(n_sleep < starts.size(), "śpiący ma mniej tików: %d < %d" % [n_sleep, starts.size()])
	# niespokojny (zapowiedź, „zauważył”): tik gaśnie w ≤ 0,3 s i nowy się nie zaczyna
	var u := IdleLife.new(9, {"tics": ["look"], "rate": [0.5, 0.6]})
	while u.tic_k < 0.5:
		u.step(dt, false)
	for i in int(0.3 / dt):
		u.step(dt, false, false)
	_ok(u.tic_k < 0.01, "niespokojny: tik zgaszony (%.3f)" % u.tic_k)
	var started := false
	for i in int(5.0 / dt):
		u.step(dt, false, false)
		started = started or u.tic_k > 0.01
	_ok(not started, "niespokojny: brak nowych tików przez 5 s")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		EnemyDefs = load("res://scripts/enemy_defs.gd")
		return false
	if _frames <= 3 + 30 * 60:
		if _frames <= 3 + 120:
			for h in _heed:
				for i in [1, 2]:
					(h[i] as Node3D).call("pose", 1.0 / 60.0, "sleep", false, Color.WHITE)
		for m in _models:
			var e: Node3D = m[1]
			e.call("pose", 1.0 / 60.0, String(m[2]), false, Color.WHITE)
			var sk: Skeleton3D = e.get("_sk")
			var b: Dictionary = e.get("_b")
			for side in ["Right", "Left"]:
				var hand := sk.get_bone_global_pose(b[side + "Hand"]).origin
				var arm := sk.get_bone_global_pose(b[side + "Arm"]).origin
				m[3] = maxf(float(m[3]), hand.y - arm.y)
			if _frames % 30 == 0:
				(m[4] as Array).append(sk.get_bone_global_pose(b["Head"]).basis.get_euler())
		return false
	for m in _models:
		if String(m[2]) == "sleep" and int(m[1].get("life_seed")) == 11:
			_check_sleep(m[1], String(m[0]))
	for h in _heed:
		_check_heed(String(h[0]), h[1], h[2])
	var heads := {}
	for m in _models:
		_ok(float(m[3]) < 0.0, "%s %s (ziarno %s): dłoń poniżej barku (max %.3f m)" % [m[0], m[2], m[1].get("life_seed"), float(m[3])])
		var key := "%s/%s" % [m[0], m[2]]
		if not heads.has(key):
			heads[key] = []
		(heads[key] as Array).append(m[4])
	for key in heads:
		var tr: Array = heads[key]
		if tr.size() == 2:
			_ok(tr[0] != tr[1], "%s: dwa egzemplarze ruszają głową inaczej" % key)
		var moved := 0.0
		var t0: Array = tr[0]
		for v in t0:
			moved = maxf(moved, ((v as Vector3) - (t0[0] as Vector3)).length())
		_ok(moved > deg_to_rad(1.0), "%s: głowa nie stoi w miejscu przez 30 s (%.1f°)" % [key, rad_to_deg(moved)])
	print("[IDLE-LIFE] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
	return true

## Poza snu po 30 s: wysokość, szerokość względem hitboxa z symulacji i najniższy punkt skóry nad podłogą.
func _check_sleep(e: Node3D, k: String) -> void:
	var d: Dictionary = EnemyDefs.DEFS.get(k, {})
	if not d.has("size"):
		return                                        # Stalker: osobny skrypt i hitbox (stalker.gd), śpi na stojąco
	var w := float((d["size"] as Vector2).x) * PX
	var h := maxf(float(d.get("hurt_h", 0.0)), float((d["size"] as Vector2).y)) * PX
	var sk: Skeleton3D = e.get("_sk")
	var inv := e.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	var top := -INF
	for i in sk.get_bone_count():
		var p := inv * sk.get_bone_global_pose(i).origin
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
		top = maxf(top, p.y)
	var lowv: Array = _skin_low(e)
	var low := float(lowv[0])
	var styled := String((e.get("SPEC")[k] as Dictionary).get("sleep_pose", "stand")) != "stand"
	print("[IDLE-LIFE] %s śpi: kości x %.2f…%.2f (hitbox ±%.2f), góra %.2f / %.2f m, skóra najniżej %.3f m (%s)" % [k, lo, hi, w / 2.0, top, h, low, lowv[1]])
	_ok(lo >= -w / 2.0 - 0.12 and hi <= w / 2.0 + 0.12, "%s śpi: kości x %.2f…%.2f poza hitboxem ±%.2f m" % [k, lo, hi, w / 2.0])
	_ok(low > -0.04, "%s śpi: skóra %.3f m pod podłogą" % [k, low])
	if styled:
		_ok(top <= h * 0.67, "%s śpi: sylwetka niska (góra %.2f m ≤ 2/3 z %.2f m)" % [k, top, h])

## Nasłuch (IDLE_PLAN.md A5, I4): po 2 s snu z hałasem zza pleców głowa jest obrócona o ≥ 30° względem kontrolnego egzemplarza (to samo
## ziarno), twarzą ku kamerze (+Z), a biodra/korzeń stoją jak u kontrolnego (ciało się nie obraca). Mimik (przebranie) — bez zmian.
func _check_heed(k: String, a: Node3D, b: Node3D) -> void:
	var sk_a: Skeleton3D = a.get("_sk")
	var sk_b: Skeleton3D = b.get("_sk")
	var bones: Array = a.get("_heed_bones")
	var bd: Dictionary = a.get("_b")
	var head: int = int(bones[1]) if bones.size() == 2 else int(bd.get("Head", -1))
	var hips: int = int(bd.get("Hips", 0))
	if head < 0:
		_ok(false, "%s: nasłuch bez kości głowy" % k)
		return
	var ha := sk_a.get_bone_global_pose(head).basis.orthonormalized()
	var hb := sk_b.get_bone_global_pose(head).basis.orthonormalized()
	var ang := rad_to_deg(ha.get_rotation_quaternion().angle_to(hb.get_rotation_quaternion()))
	var r := ha * hb.inverse()
	var fwd := (sk_a.global_transform.basis * (r * (sk_a.global_transform.basis.inverse() * Vector3.RIGHT))).normalized()
	var hip := rad_to_deg(sk_a.get_bone_global_pose(hips).basis.orthonormalized().get_rotation_quaternion().angle_to(
			sk_b.get_bone_global_pose(hips).basis.orthonormalized().get_rotation_quaternion()))
	print("[IDLE-LIFE] %s nasłuch: głowa %.1f° od kontrolnego, przód głowy z = %.2f, biodra %.2f°" % [k, ang, fwd.z, hip])
	if k == "mimik":
		_ok(ang < 0.5, "mimik: nasłuch zdradza przebranie (głowa %.1f°)" % ang)
		return
	_ok(ang >= 30.0 and fwd.z > 0.3, "%s: hałas zza pleców obraca głowę o ≥ 30° ku kamerze (%.1f°, z %.2f)" % [k, ang, fwd.z])
	_ok(hip < 0.5, "%s: nasłuch obraca ciało (biodra %.2f°)" % [k, hip])

## Najniższy punkt skóry nad podłogą (co 5. wierzchołek; skinning liczony jak w audit_enemy_assets.gd).
func _skin_low(e: Node3D) -> Array:
	var sk: Skeleton3D = e.get("_sk")
	var low := INF
	var at := ""
	for node in e.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin == null or not mi.visible:
			continue
		var xf := sk.global_transform.affine_inverse() * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			for v in range(0, verts.size(), 5):
				var pt := Vector3.ZERO
				var main := ""
				var main_w := 0.0
				for slot in per:
					var wt := weights[v * per + slot]
					if wt <= 0.0:
						continue
					var bi := bones[v * per + slot]
					var bone := mi.skin.get_bind_bone(bi)
					if bone < 0:
						bone = sk.find_bone(mi.skin.get_bind_name(bi))
					if bone < 0:
						continue
					pt += sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bi) * (xf * verts[v]) * wt
					if wt > main_w:
						main_w = wt
						main = sk.get_bone_name(bone)
				var y := (sk.global_transform * pt).y - e.global_position.y
				if y < low:
					low = y
					at = "%s/%s" % [mi.name, main]
	return [low if is_finite(low) else 0.0, at]
