extends Node3D
## Strzelnica FPP — inni gracze na sąsiednich stanowiskach (RANGE_FPS_PLAN.md, etap 3). Każdy strzela u siebie (własne blachy, własna
## symulacja), ale widać go w tunelu: model postaci (char3d.gd, ten sam wygląd i broń co w grze) stoi na swoim stanowisku — a gdy to
## stanowisko zajmuje lokalny gracz, na najbliższym wolnym — patrzy i celuje tak, jak on (replikowane `player.range_pose`), klęka przy
## ławie, a jego strzał daje błysk, światło i dźwięk z jego miejsca (licznik `player.range_shots`). Obraz tylko lokalny (range_view.gd
## woła `tick`); w kryjówce ten sam gracz stoi zaparkowany przy drzwiach.

const Char3D := preload("res://scripts/char3d.gd")
const Weapons := preload("res://scripts/weapons.gd")
const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const BACK := 0.15                    ## m — postać za linią ognia (oczy na z ≈ 0, jak u lokalnego gracza)

var view: Node                        ## range_view.gd (dźwięk 3D)
var fp: Node                          ## fp_mode.gd lokalnego gracza
var _others := {}                     ## gracz → {c3, actor, shots, gun, flash, flash_t}

func setup(v: Node, f: Node) -> void:
	view = v
	fp = f

## Co klatkę: dołącza / zwalnia postacie graczy, którzy weszli / wyszli ze strzelnicy, i ustawia ich pozę.
func tick(delta: float) -> void:
	var me: Node = fp.player if fp != null and is_instance_valid(fp) else null
	var alive := {}
	for p in get_tree().get_nodes_in_group("players"):
		if p == me or p.is_queued_for_deletion() or bool(p.get("is_bot")) or not bool(p.get("in_range")):
			continue
		alive[p] = true
		if not _others.has(p):
			var o := _make(p)
			if o.is_empty():
				continue
			_others[p] = o
		_drive(p, _others[p], delta)
	for p in _others.keys():
		if not alive.has(p) or not is_instance_valid(p):
			_release(_others[p])
			_others.erase(p)

func _exit_tree() -> void:
	for p in _others.keys():
		_release(_others[p])
	_others.clear()

## Postać gracza w tunelu: osobny char3d (ten sam wygląd i kolory co w grze), model i broń przepięte do świata tunelu (jak view3d._make_rig).
func _make(p: Node) -> Dictionary:
	var src = p.get("c3d")
	var look := String(src._char_name) if src != null and is_instance_valid(src) else Char3D.DEFAULT_CHAR
	var c3 = Char3D.new()
	c3.name = "RangeOther_" + String(p.name)
	c3.visible = false
	view.add_child(c3)
	if not c3.setup(look):
		c3.queue_free()
		return {}
	if src != null and is_instance_valid(src):
		c3.set_palette(int(src._palette))
	for vp in [c3._vp, c3._vpn]:
		if vp != null:
			(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	c3._sprite.visible = false
	var actor := Node3D.new()
	actor.name = "Other_" + String(p.name)
	add_child(actor)
	var o := {"c3": c3, "actor": actor, "shots": int(p.get("range_shots")), "gun": "", "flash_t": 0.0}
	_adopt(o)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.75, 0.42)
	fl.omni_range = 5.0
	fl.light_energy = 0.0
	add_child(fl)
	o["flash"] = fl
	return o

## Model i broń z char3d do aktora w tunelu (po zmianie broni char3d buduje nowy model broni w swoim świecie).
func _adopt(o: Dictionary) -> void:
	var c3 = o["c3"]
	var actor := o["actor"] as Node3D
	for n in [c3._char_node, c3._gun]:
		if n != null and is_instance_valid(n) and (n as Node).get_parent() != actor:
			(n as Node).reparent(actor, false)
			for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).layers == 2:
					(mi as MeshInstance3D).visible = false          # kopie z przebiegu normalnych sprite'a 2D
	if c3._gun_n != null:
		c3._gun_n.visible = false

func _drive(p: Node, o: Dictionary, delta: float) -> void:
	var c3 = o["c3"]
	var pose: Vector4 = p.get("range_pose")
	var key := String(Weapons.def(int(p.get("weapon"))).key)
	if key != String(o["gun"]):
		o["gun"] = key
		c3.set_gun(key)
		_adopt(o)
	c3._on_screen = true
	c3.update(delta, "crouch" if pose.w > 0.5 else "idle", 1.0, Vector2.RIGHT.rotated(-pose.z), 0.0, true)
	var actor := o["actor"] as Node3D
	actor.position = Vector3(float(RangeSim.STATIONS[_slot(int(pose.x))]), 0.0, BACK)
	actor.basis = Basis(Vector3.UP, PI * 0.5 + pose.y)                # model patrzy w +x; obrót o 90° — w głąb tunelu (−z), plus odchylenie
	var shots := int(p.get("range_shots"))
	var fl := o["flash"] as OmniLight3D
	if shots != int(o["shots"]):
		o["shots"] = shots
		o["flash_t"] = 0.05
		var d := Weapons.def(int(p.get("weapon")))
		var up := 1.05 if pose.w > 0.5 else 1.45
		fl.global_position = actor.global_transform * Vector3(0.75 * cos(pose.z), up + 0.75 * sin(pose.z), 0.0)
		if not d.is_continuous():
			view._play3d(String(d.sfx), int(d.sfx_count), fl.global_position, float(d.sfx_vol) - 2.0, 0.04)
	o["flash_t"] = maxf(0.0, float(o["flash_t"]) - delta)
	fl.light_energy = 6.0 * float(o["flash_t"]) / 0.05

## Stanowisko do pokazania: własne, a gdy zajmuje je lokalny gracz — najbliższe wolne (dwaj gracze na jednym stanowisku nachodziliby na kamerę).
func _slot(st: int) -> int:
	var n := RangeSim.STATIONS.size()
	st = clampi(st, 0, n - 1)
	var mine := int(fp.station) if fp != null and is_instance_valid(fp) else -1
	if st != mine:
		return st
	for k in [1, -1, 2, -2]:
		var s2: int = st + k
		if s2 >= 0 and s2 < n:
			return s2
	return st

func _release(o: Dictionary) -> void:
	for k in ["actor", "flash"]:
		if o.has(k) and is_instance_valid(o[k]):
			(o[k] as Node).queue_free()
	if is_instance_valid(o["c3"]):
		(o["c3"] as Node).queue_free()
