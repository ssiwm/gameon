extends SceneTree
## Test proporcji świata: postać 1,8 m (22 px świata, 1 px = 0,082 m) kontra hitboxy, meble i znajdźki.
## (1) ciało gracza ma wysokość modelu postaci, (2) strefa trafień każdego wroga ma wysokość jego modelu (enemy3d.gd SPEC „fit"),
## (3) przedmioty w skali widoku 3D (view3d.gd ITEM_SCALE) mieszczą się w naturalnych wymiarach — meble jak prawdziwe, znajdźki najwyżej ok. 2×,
## (4) promień w głowę wysokiego wroga trafia jego strefę trafień, a przebicie nie liczy go dwa razy, (5) gablota na broń mieści broń w rzędach.
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
	"shelf": ["h", 2.0], "radio_set": ["h", 1.05], "lamp": ["h", 0.55],
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
	elif _frames == 8:
		_rays()
		print("PASS" if _fail == 0 else "FAIL (%d)" % _fail)
		quit(0 if _fail == 0 else 1)
		return true
	return false

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
