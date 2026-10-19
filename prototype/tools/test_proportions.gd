extends SceneTree
## Test proporcji świata: postać 1,8 m (22 px świata, 1 px = 0,082 m) kontra hitboxy, meble i znajdźki.
## (1) ciało gracza ma wysokość modelu postaci, (2) strefa trafień każdego wroga ma wysokość jego modelu (enemy3d.gd SPEC „fit"),
## (3) przedmioty w skali widoku 3D (view3d.gd ITEM_SCALE) mieszczą się w naturalnych wymiarach — meble jak prawdziwe, znajdźki najwyżej ok. 2×,
## (4) promień w głowę wysokiego wroga trafia jego strefę trafień, a przebicie nie liczy go dwa razy, (5) gablota na broń mieści broń w rzędach,
## (6) postacie MPFB (art/char3d/mpfb) mają proporcje dorosłego człowieka.
## godot --headless --path prototype -s tools/test_proportions.gd      → ma wypisać PASS
const PX := 1.8 / 22.0
const Char3D := preload("res://scripts/char3d.gd")
## Skrypty wrogów i widoku używają autoloadów, więc ładujemy je dopiero po pierwszej klatce (preload w skrypcie `-s` się nie kompiluje).
var Enemy: GDScript
var Enemy3D: GDScript
var Stalker: GDScript
var View3D: GDScript
var _frames := 0
## przedmiot → [wymiar: "h" wysokość / "max" najdłuższy bok, górna granica w m]
const LIMITS := {
	"table": ["h", 1.25], "chair": ["h", 1.0], "stool": ["h", 0.7], "cot": ["max", 2.0], "workshop": ["h", 1.45], "locker": ["h", 1.95],
	"shelf": ["h", 2.0], "radio_set": ["h", 1.25], "lamp": ["h", 0.55],
	"frag": ["max", 0.25], "smoke": ["max", 0.35], "phos": ["max", 0.35], "flare": ["max", 0.55], "mine": ["max", 0.55], "ammo": ["max", 0.55],
	"medkit": ["max", 0.75], "charge": ["max", 0.5], "defib": ["max", 0.6], "scanner": ["max", 0.6], "tag": ["max", 0.45], "padlock": ["max", 0.25],
}
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	print(("ok    " if ok else "FAIL  ") + msg)
	if not ok:
		_fail += 1

func _size(path: String) -> Vector3:
	var inst: Node = (load(path) as PackedScene).instantiate()
	var acc := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != inst:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var a := xf * mi.mesh.get_aabb()
		acc = a if first else acc.merge(a)
		first = false
	inst.free()
	return acc.size

var _dummy: Node2D
var _hc: Node2D                              ## postać 3D do sprawdzenia dłoni (_hands)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		Enemy = load("res://scripts/enemy.gd")
		Enemy3D = load("res://scripts/enemy3d.gd")
		Stalker = load("res://scripts/stalker.gd")
		View3D = load("res://scripts/view3d.gd")
		_run()
		# wróg na próbę: Ślepiec (ciało ruchu 17 px, model i strefa trafień 27 px) daleko od reszty świata
		_dummy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
		_dummy.set("kind", "slepiec")
		_dummy.position = Vector2(5000.0, 5000.0)
		root.add_child(_dummy)
		_hc = Char3D.new()
		root.add_child(_hc)
		_hc.setup("male_scav", "m83")
	elif _frames == 8:
		_hands()
		_rays()
		print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
		quit(0 if _fail == 0 else 1)
		return true
	return false

## (5) dłonie z bronią: żaden wierzchołek dłoni, palców i rękawicy nie odstaje od kości dłoni dalej niż dłoń jest długa (rękawice MPFB miały w prawej
## rękawicy wierzchołki przypięte do obojczyka — w pozie z bronią rozciągały się w „pręty” do bioder; tools/glb_glove_weights.py), a palce dłoni na chwycie
## są zgięte (char3d.gd `_apply_fingers`; w spoczynku modelu są wyprostowane). Skinning liczony na CPU z wag siatki i póz kości.
func _hands() -> void:
	if _hc == null or not _hc.ready_ok:
		_check(false, "dłonie: brak postaci 3D")
		return
	_hc._set_on_screen(true)
	for look in ["male_scav", "female_scav", "male_hazmat", "female_hazmat"]:
		if not _hc.set_look(look):
			continue
		for gun in ["m83", "spread12", "p64"]:
			_hc.set_gun(gun)
			for i in 40:
				_hc.update(1.0 / 60.0, "idle", 1.0, Vector2(1.0, -0.2).normalized(), 0.0)
			var sk: Skeleton3D = _hc._sk
			var worst := 0.0
			var worst_at := ""
			for n in _hc._char_node.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi.skin == null or mi.mesh == null:
					continue
				var xf := Char3D._xf_under(sk, _hc._char_node).affine_inverse() * Char3D._xf_under(mi, _hc._char_node)
				for si in mi.mesh.get_surface_count():
					var arr := mi.mesh.surface_get_arrays(si)
					if arr[Mesh.ARRAY_BONES] == null:
						continue
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
					var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
					var per := bs.size() / vs.size()
					for v in vs.size():
						var pos := Vector3.ZERO
						var top := -1
						var topw := 0.0
						for k in per:
							var w := ws[v * per + k]
							if w <= 0.0:
								continue
							var bone := mi.skin.get_bind_bone(bs[v * per + k])
							if bone < 0:
								bone = sk.find_bone(mi.skin.get_bind_name(bs[v * per + k]))
							pos += (sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bs[v * per + k]) * (xf * vs[v])) * w
							if w > topw:
								topw = w
								top = bone
						var bn := sk.get_bone_name(top)
						if not ("Hand" in bn):
							continue
						var side := "Left" if "Left" in bn else "Right"
						var d := pos.distance_to(sk.get_bone_global_pose(sk.find_bone("mixamorig_" + side + "Hand")).origin)
						if d > worst:
							worst = d
							worst_at = "%s/%s" % [mi.name, bn.trim_prefix("mixamorig_")]
			_check(worst <= 0.25, "%s + %s: wierzchołki dłoni najwyżej %.2f m od kości dłoni (≤ 0,25; najdalej %s)" % [look, gun, worst, worst_at])
			var idx: int = sk.find_bone("mixamorig_RightHandIndex1")
			if idx >= 0:
				var bend := rad_to_deg(sk.get_bone_rest(idx).basis.get_rotation_quaternion().angle_to(sk.get_bone_pose_rotation(idx)))
				_check(bend > 50.0, "%s + %s: palce prawej dłoni zgięte na chwycie (palec wskazujący %.0f°)" % [look, gun, bend])

## (4) promień poziomy na wysokości głowy wysokiego wroga trafia go (strefa trafień, hurtbox.gd), a nad modelem — nie.
func _rays() -> void:
	var Combat: GDScript = load("res://scripts/combat.gd")
	var space := root.get_world_2d().direct_space_state
	var feet := _dummy.global_position
	var head: Dictionary = Combat.trace(space, feet + Vector2(-60.0, -24.0), Vector2.RIGHT, 120.0, 0)
	var hits: Array = head["hits"]
	_check(hits.size() == 1 and hits[0]["collider"] == _dummy, "promień na wysokości 24 px trafia Ślepca (ciało ruchu 17 px, strefa trafień 27 px)")
	var over: Dictionary = Combat.trace(space, feet + Vector2(-60.0, -30.0), Vector2.RIGHT, 120.0, 0)
	_check((over["hits"] as Array).is_empty(), "promień na wysokości 30 px przechodzi nad Ślepcem")
	var pierce: Dictionary = Combat.trace(space, feet + Vector2(-60.0, -24.0), Vector2.RIGHT, 120.0, 3)
	_check((pierce["hits"] as Array).size() == 1, "przebicie nie trafia tego samego wroga drugi raz (ciało + strefa = jeden cel)")

func _run() -> void:
	# (1) gracz
	var ps: Node = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	var cs := ps.get_node("CollisionShape2D") as CollisionShape2D
	var h := (cs.shape as RectangleShape2D).size.y
	_check(is_equal_approx(h, Char3D.CHAR_H_WP) and is_equal_approx(cs.position.y, -h * 0.5),
			"ciało gracza %.0f px = model %.0f px (%.2f m), od stóp w górę" % [h, Char3D.CHAR_H_WP, h * PX])
	ps.free()
	# (2) wrogowie
	for k in Enemy.KINDS:
		var spec: Dictionary = Enemy3D.SPEC.get(k, {})
		var fit: Array = spec.get("fit", [])
		if fit.is_empty() or String(fit[0]) != "height":
			continue
		var kd: Dictionary = Enemy.KINDS[k]
		var hurt := maxf(float(kd.get("hurt_h", 0.0)), (kd["size"] as Vector2).y)
		_check(is_equal_approx(hurt, float(fit[1])), "%s: strefa trafień %.0f px = model %.0f px (%.2f m)" % [k, hurt, float(fit[1]), hurt * PX])
	var cma: Dictionary = Enemy.KINDS["cma"]
	_check(float(cma.get("hurt_h", 0.0)) >= 16.0, "cma: strefa trafień %.0f px obejmuje skrzydła (model ok. 16 px wysokości)" % float(cma.get("hurt_h", 0.0)))
	var sh := float(Stalker.get("HURT_H"))
	_check(is_equal_approx(sh, float(Enemy3D.SPEC["stalker"]["fit"][1])), "stalker: strefa trafień %.0f px = model" % sh)
	# (3) przedmioty
	for name in LIMITS:
		var lim: Array = LIMITS[name]
		var sz := _size("res://art/items3d/%s.glb" % name) * PX * float(View3D.ITEM_SCALE.get(name, 1.0))
		var v := sz.y if String(lim[0]) == "h" else maxf(sz.x, maxf(sz.y, sz.z))
		_check(v <= float(lim[1]), "%s: %s %.2f m (granica %.2f)" % [name, "wysokość" if String(lim[0]) == "h" else "najdłuższy bok", v, float(lim[1])])
	# broń jako łup i na stojaku: naturalna długość modelu (gun_proc.py), minimum tylko dla najkrótszych
	for gk in ["m83", "p64", "maczeta"]:
		var glen := _size("res://art/char3d/gun_%s.glb" % gk).x
		var loot := maxf(glen, float(View3D.get("LOOT_MIN_M")))
		_check(loot <= maxf(glen * 1.05, 0.4), "%s jako łup: %.2f m (w ręku %.2f m)" % [gk, loot, glen])
	# gablota na broń (kryjówka): najdłuższa broń mieści się między bokami, rzędy nie nachodzą na siebie, gablota niższa niż 2,3 m
	var cab_w := float(View3D.get("CAB_W"))
	var rows: Array = View3D.get("CAB_ROWS")
	var longest := 0.0
	var tallest := 0.0
	for gk in ["spread12", "srut8", "lr7", "hkm9", "gniew4", "widmo1", "sokol6", "ciegno6"]:
		var gs := _size("res://art/char3d/gun_%s.glb" % gk)
		longest = maxf(longest, gs.x)
		tallest = maxf(tallest, gs.y)
	_check(longest <= cab_w - 0.25, "gablota %.2f m: najdłuższa broń %.2f m mieści się z zapasem" % [cab_w, longest])
	var gap := absf(float(rows[0]) - float(rows[1]))
	_check(tallest <= gap, "rzędy co %.2f m: najwyższa broń %.2f m nie nachodzi na sąsiedni rząd" % [gap, tallest])
	_check(float(View3D.get("CAB_H")) <= 2.3, "gablota: wysokość %.2f m (postać 1,8 m)" % float(View3D.get("CAB_H")))
	var fence := _size("res://art/items3d/fence.glb").y * PX * float(View3D.DECO_MODELS[6][1])
	_check(fence <= 2.5, "płot (dekoracja): wysokość %.2f m (granica 2,50)" % fence)
	_anatomy()

## (6) postacie MPFB: proporcje dorosłego człowieka liczone ze szkieletu (H = wzrost modelu: 1,8 m mężczyzna, 1,7 m kobieta).
## Kark 0,80–0,88 H, biodra 0,50–0,60 H (kość Hips rigu Mixamo leży nad stawem biodrowym), ręka (bark–nadgarstek) 0,28–0,36 H, noga (biodro–kostka) 0,42–0,52 H, rozstaw barków 0,18–0,26 H,
## od karku do wierzchu głowy z hełmem / kapturem najwyżej 0,22 H (modele Tripo miały 0,21–0,24 H bez szyi — głowa 1/4–1/5 wzrostu).
func _anatomy() -> void:
	var dir := "res://art/char3d/mpfb/"
	for g in ["male", "female"]:
		for o in ["scav", "hazmat", "medic"]:
			var path := dir + "%s_%s.glb" % [g, o]
			if not ResourceLoader.exists(path):
				continue
			var inst: Node = (load(path) as PackedScene).instantiate()
			var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
			var hgt := 1.8 if g == "male" else 1.7
			var b := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone("mixamorig_" + n)).origin
			var top := 0.0
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh != null and not String(m.name).begins_with("gear") and not String(m.name).begins_with("backpack") 						and not String(m.name).begins_with("bedroll") and not String(m.name).begins_with("airtank"):
					top = maxf(top, m.mesh.get_aabb().end.y)
			var arm: float = (b.call("RightArm") as Vector3).distance_to(b.call("RightForeArm")) + (b.call("RightForeArm") as Vector3).distance_to(b.call("RightHand"))
			var leg: float = (b.call("RightUpLeg") as Vector3).distance_to(b.call("RightLeg")) + (b.call("RightLeg") as Vector3).distance_to(b.call("RightFoot"))
			var sh: float = (b.call("RightArm") as Vector3).distance_to(b.call("LeftArm"))
			var neck: float = (b.call("Neck") as Vector3).y
			var hips: float = (b.call("Hips") as Vector3).y
			var name := "%s_%s" % [g, o]
			for c in [["kark", neck, 0.80, 0.88], ["biodra", hips, 0.50, 0.60], ["ręka", arm, 0.28, 0.36], ["noga", leg, 0.42, 0.52],
					["barki", sh, 0.18, 0.26]]:
				var r := float(c[1]) / hgt
				_check(r >= float(c[2]) and r <= float(c[3]), "%s: %s %.2f H (%.2f–%.2f)" % [name, c[0], r, c[2], c[3]])
			_check((top - neck) / hgt <= 0.22, "%s: głowa z nakryciem od karku %.2f H (≤ 0,22)" % [name, (top - neck) / hgt])
			inst.free()
