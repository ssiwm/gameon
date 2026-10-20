extends Node3D
## Ręce w widoku z oczu (strzelnica FPP, RANGE_FPS_PLAN.md): model postaci gracza (char3d.gd — MPFB ze szkieletem Mixamo, ta sama kurtka
## i rękawice, które widzą inni) przypięty do kamery tak, że oczy postaci są w kamerze. Ręce prowadzi to samo IK co w widoku z boku:
## `_arm_ik` (łokieć zgina się w swojej osi), `_hand_target` / `_left_hold` (dłoń z układu zmierzonego z siatki leży na chwycie i pod łożem),
## `_set_hand` (skręt nadgarstka dzielony z przedramieniem), `_apply_fingers` (palce obejmują chwyt). Z siatek postaci i ubrania zostają tylko
## trójkąty przypisane wagami do kości rąk (`_arms_only`) — tułów i głowa weszłyby w kamerę.
##
## Model nie wisi na oczach, tylko na broni: stopka kolby leży w zagłębieniu prawego barku, a tułów jest obrócony bokiem (postawa
## strzelecka, BLADE_DEG) — inaczej lewa ręka nie sięgała łoża broni trzymanej przed okiem. Głowa jest schowana, więc niezgodność oczu
## modelu z kamerą nie jest widoczna. Pistolet: barki ok. PISTOL_REACH za chwytem (ręce wyciągnięte).
##
## Układ modelu: postać patrzy w +x, góra +y, prawy bok +z — jak układ broni (gun_info), więc pozy z char3d (bieguny łokci, strona grzbietu
## dłoni) działają bez zmian. Na kamerę (−z w przód, +x w prawo) przechodzi przez bazę `TO_CAM`.

const Char3D := preload("res://scripts/char3d.gd")

const TO_CAM := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   ## model (x w przód, z w prawo) → kamera
const BLADE_DEG := 32.0               ## ° — tułów obrócony w prawo: lewy bark wysunięty ku łożu
const POCKET := Vector3(0.02, -0.06, -0.07)   ## m — zagłębienie barku względem stawu ramiennego (w przód, w dół, ku środkowi)
const BUTT_IN := 0.03                 ## m — stopka kolby wchodzi o tyle w ramię
const PISTOL_REACH := Vector3(-0.46, -0.15, 0.17)   ## m — prawy bark względem chwytu pistoletu (układ broni: w tył, w dół, w prawo) — postawa
                                                  ## równoramienna: barki ok. 15 cm pod linią wzroku, ręce wyciągnięte, tułów przodem
const ARM_BONES := ["Arm", "ForeArm", "Hand"]      ## kości (Left/Right + nazwa, także palce Hand…), których trójkąty zostają
const KEEP_W := 0.5                   ## wierzchołek zostaje, gdy kości rąk mają co najmniej tyle jego wagi
const POLE_R := Vector3(-0.35, -1.0, 0.75)    ## łokieć prawy: w dół i na zewnątrz (jak w char3d, mocniej w bok — z oczu widać przedramię)
const POLE_L := Vector3(-0.25, -1.0, -0.6)

var c3: Node2D                        ## char3d.gd użyty jako szkielet z IK (jego własny podgląd 2D jest wyłączony)
var ok := false
var _model: Node
var _sk_xf := Transform3D.IDENTITY    ## szkielet względem węzła modelu
var _pocket := Vector3.ZERO           ## zagłębienie prawego barku w przestrzeni szkieletu (spoczynek)

## Buduje ręce z postaci `char_name` (palette — kolory stroju gracza). `host` — węzeł, pod którym żyje char3d (poza światem 3D).
func setup(host: Node, char_name: String, palette := 0) -> bool:
	c3 = Char3D.new()
	c3.name = "FpArmsRig"
	c3.visible = false
	host.add_child(c3)
	if not c3.setup(char_name):
		c3.queue_free()
		c3 = null
		return false
	c3.set_palette(palette)
	if c3._clips != null:
		(c3._clips as AnimationTree).active = false             # pozę daje tylko IK poniżej
	for vp in [c3._vp, c3._vpn]:
		if vp != null:
			(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	c3._sprite.visible = false
	_model = c3._char_node
	_model.reparent(self, false)
	var sk: Skeleton3D = c3._sk
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.layers == 2 or m.skin == null:
			m.visible = false                                      # kopie przebiegu normalnych sprite'a 2D, sztywne dodatki (głowa, sprzęt)
		else:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_arms_only(m, sk)
	_sk_xf = Char3D._xf_under(sk, _model) if _model is Node3D else Transform3D.IDENTITY
	if _model is Node3D:
		_sk_xf = (_model as Node3D).transform * _sk_xf
	_pocket = sk.get_bone_global_rest(sk.find_bone(Char3D.PRE + "RightArm")).origin + POCKET
	ok = true
	return true

func release() -> void:
	if c3 != null and is_instance_valid(c3):
		c3.queue_free()

## Poza rąk na broni `gun_xf` (układ kamery — rodzica tego węzła). key — klucz broni (WEAPON_POSE), info — Char3D.info_with,
## rear_x — tył broni (stopka kolby, najmniejsze x modelu), reload_u — postęp przeładowania 0..1 (< 0 brak),
## clearing — usuwanie zacięcia (lewa dłoń do zamka).
func pose(gun_xf: Transform3D, key: String, info: Dictionary, rear_x: float, reload_u: float, clearing: bool) -> void:
	if not ok:
		return
	# model ustawiony od broni: zagłębienie barku na stopce kolby (pistolet — bark za chwytem), tułów bokiem, pion jak kamera
	var wp0: Dictionary = Char3D.WEAPON_POSE.get(key, {})
	var grip: Vector3 = info["grip"]
	var anchor: Vector3
	var blade := BLADE_DEG
	if String(wp0.get("reload", "")) == "pistol" or float(info.get("length", 1.0)) < 0.45:
		anchor = gun_xf * (grip + PISTOL_REACH)
		blade = 0.0
	else:
		anchor = gun_xf * Vector3(rear_x + BUTT_IN, grip.y + 0.02, 0.0)
	var mb := TO_CAM * Basis(Vector3.UP, deg_to_rad(-blade))
	transform = Transform3D(mb, anchor - mb * (_sk_xf * _pocket))
	var sk: Skeleton3D = c3._sk
	sk.reset_bone_poses()
	# broń w przestrzeni szkieletu (tej, w której liczy char3d)
	var gx := (transform * _sk_xf).affine_inverse() * gun_xf
	gx.basis = gx.basis.orthonormalized()
	var wp: Dictionary = Char3D.WEAPON_POSE.get(key, {})
	var pistol := String(wp.get("reload", "")) == "pistol"
	var hands := int(info.get("hands", 2))
	c3._gun_len = float(info.get("length", 1.0))
	c3._rest_clavicles()
	var rh: Transform3D = c3._hand_target("Right", gx, (info["grip"] as Vector3) + Vector3(0.0, float(wp.get("grip_dy", 0.0)), 0.0),
		Char3D._wrist_dir(wp), Vector3.BACK, Char3D.GRIP_HALF)
	c3._reach_clavicle("Right", rh.origin, 0.22)
	c3._arm_ik("Right", rh.origin, POLE_R)
	c3._set_hand("Right", rh.basis)
	c3._curl["Right"] = 1.0
	if (hands == 2 or pistol) and key != "maczeta" and key != "kilof":
		var lh: Transform3D = c3._left_hold(gx, info, wp)
		var keep := 1.0
		if reload_u >= 0.0:
			var u := clampf(reload_u, 0.0, 1.0)
			keep = 1.0 - 0.85 * sin(PI * u)
			var kind := "bolt" if clearing else String(wp.get("reload", "mag"))
			if kind != "pistol":
				var palm: Vector3 = c3._left_path(kind, u, info["hold"] as Vector3)
				lh.origin += gx.basis * (palm - (info["hold"] as Vector3))
		c3._reach_clavicle("Left", lh.origin, 0.22)
		c3._arm_ik("Left", lh.origin, POLE_L)
		c3._set_hand("Left", lh.basis, keep)
		c3._curl["Left"] = lerpf(0.45, Char3D.CURL_HOLD, keep)
	else:
		c3._curl["Left"] = Char3D.CURL_RELAX
	c3._apply_fingers()

## Zostawia w siatce `mi` tylko trójkąty rąk: każdy z trzech wierzchołków ma ≥ KEEP_W wagi na kościach rąk (ramię, przedramię, dłoń, palce).
## Puste powierzchnie znikają (materiały nadpisane przez char3d idą razem ze swoją powierzchnią). Pusta siatka — węzeł chowany.
func _arms_only(mi: MeshInstance3D, sk: Skeleton3D) -> void:
	var arm_bind := {}
	for j in mi.skin.get_bind_count():
		var bn := String(mi.skin.get_bind_name(j))
		var bi := sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(j)
		var name := sk.get_bone_name(bi).trim_prefix(Char3D.PRE) if bi >= 0 else ""
		for side in ["Left", "Right"]:
			for b in ARM_BONES:
				if name.begins_with(side + b):
					arm_bind[j] = true
	var src := mi.mesh
	var out := ArrayMesh.new()
	var mats: Array = []
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if arr[Mesh.ARRAY_BONES] == null or vs.is_empty():
			continue
		var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bs.size() / vs.size()
		var keep := PackedByteArray()
		keep.resize(vs.size())
		for v in vs.size():
			var w := 0.0
			for k in per:
				if arm_bind.has(bs[v * per + k]):
					w += ws[v * per + k]
			keep[v] = 1 if w >= KEEP_W else 0
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		var nidx := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			if keep[idx[t]] == 1 and keep[idx[t + 1]] == 1 and keep[idx[t + 2]] == 1:
				nidx.append(idx[t])
				nidx.append(idx[t + 1])
				nidx.append(idx[t + 2])
		if nidx.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = nidx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		var m := mi.get_surface_override_material(si)
		mats.append(m if m != null else src.surface_get_material(si))
	if out.get_surface_count() == 0:
		mi.visible = false
		return
	mi.mesh = out
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
