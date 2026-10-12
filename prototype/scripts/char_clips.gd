extends RefCounted
## Klipy animacji postaci 3D: wczytuje `art/char3d/anim/<nazwa>.glb` (tools/prep_anim3d.py), przelicza je na szkielet danego wyglądu
## i buduje `AnimationTree`, który miesza je z pozą spoczynkową. Drzewo daje ruch ciała (biodra, tułów, głowa, tor stóp);
## ręce z bronią i postawienie stóp na podłożu dalej liczy IK w `char3d.gd`, na wierzchu klipu.
##
## Klip niesie własną pozę spoczynkową, więc działa na każdym modelu z kośćmi Mixamo: obroty przenosimy względem spoczynku,
## przesunięcie bioder skalujemy wysokością bioder. Pozostałe przesunięcia i skale kości pomijamy (zmieniałyby proporcje modelu).
## Czas klipu ustawia gra (faza kroku z `char3d.gd`), nie zegar drzewa — krok klipu i krok z kodu są tą samą fazą.

const DIR := "res://art/char3d/anim/"
const HIPS := "mixamorig_Hips"
## Stan bazowy (AW_STATES w char3d.gd) → klip. phase0: ułamek cyklu, w którym prawa stopa ląduje (faza kroku gry ma wtedy 0,25 obrotu).
const CLIPS := {
	"run": {"file": "run", "phase0": 0.0},
}

static var enabled := true                   ## --noclips wyłącza klipy (same pozy z kodu, do porównań)
static var _src := {}                        ## stan → {"anim": Animation, "rest": {kość → Transform3D}, "hips_y": float} albo {} (brak pliku)
static var _libs := {}                       ## nazwa modelu → AnimationLibrary (klipy przeliczone na ten szkielet + "rest")
static var _blend: AnimationNodeBlendTree

static func has(state: String) -> bool:
	return enabled and not _source(state).is_empty()

## Klip źródłowy z pliku (raz na sesję).
static func _source(state: String) -> Dictionary:
	if _src.has(state):
		return _src[state]
	var out := {}
	var path := DIR + String((CLIPS.get(state, {}) as Dictionary).get("file", "")) + ".glb"
	if CLIPS.has(state) and ResourceLoader.exists(path):
		var scene: Node = (load(path) as PackedScene).instantiate()
		var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
		var aps := scene.find_children("*", "AnimationPlayer", true, false)
		if sk != null and not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			var names := ap.get_animation_list()
			if not names.is_empty():
				var rest := {}
				for i in sk.get_bone_count():
					rest[sk.get_bone_name(i)] = sk.get_bone_rest(i)
				var hi := sk.find_bone(HIPS)
				out = {"anim": ap.get_animation(names[0]), "rest": rest, "hips_y": sk.get_bone_global_rest(hi).origin.y if hi >= 0 else 1.0}
		scene.free()
	_src[state] = out
	return out

## Klip przeliczony na szkielet `sk`: ścieżki „<Skeleton3D>:<kość>”, obroty względem spoczynku celu, biodra w skali celu.
static func _retarget(src: Dictionary, sk: Skeleton3D) -> Animation:
	var a: Animation = src["anim"]
	var rest_s: Dictionary = src["rest"]
	var hi := sk.find_bone(HIPS)
	var k_h := sk.get_bone_global_rest(hi).origin.y / maxf(float(src["hips_y"]), 0.001) if hi >= 0 else 1.0
	var o := Animation.new()
	o.length = a.length
	o.loop_mode = Animation.LOOP_LINEAR
	for t in a.get_track_count():
		var bone := String(a.track_get_path(t).get_concatenated_subnames())
		var bi := sk.find_bone(bone)
		if bi < 0 or not rest_s.has(bone):
			continue
		var rs: Transform3D = rest_s[bone]
		var rt := sk.get_bone_rest(bi)
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				var fix := rt.basis.get_rotation_quaternion() * rs.basis.get_rotation_quaternion().inverse()
				var nt := o.add_track(Animation.TYPE_ROTATION_3D)
				o.track_set_path(nt, NodePath("%s:%s" % [sk.name, bone]))
				for k in a.track_get_key_count(t):
					o.rotation_track_insert_key(nt, a.track_get_key_time(t, k), (fix * (a.track_get_key_value(t, k) as Quaternion)).normalized())
			Animation.TYPE_POSITION_3D:
				if bone != HIPS:
					continue
				var np := o.add_track(Animation.TYPE_POSITION_3D)
				o.track_set_path(np, NodePath("%s:%s" % [sk.name, bone]))
				for k in a.track_get_key_count(t):
					o.position_track_insert_key(np, a.track_get_key_time(t, k), rt.origin + ((a.track_get_key_value(t, k) as Vector3) - rs.origin) * k_h)
	return o

## Poza spoczynkowa jako klip: tło, z którym drzewo miesza klipy (te same ścieżki co w klipach).
static func _rest_anim(sk: Skeleton3D, like: Array) -> Animation:
	var o := Animation.new()
	o.length = 0.1
	var done := {}
	for a in like:
		var an := a as Animation
		for t in an.get_track_count():
			var p := an.track_get_path(t)
			var id := "%d|%s" % [an.track_get_type(t), p]
			if done.has(id):
				continue
			done[id] = true
			var rest := sk.get_bone_rest(sk.find_bone(String(p.get_concatenated_subnames())))
			var nt := o.add_track(an.track_get_type(t))
			o.track_set_path(nt, p)
			if an.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				o.rotation_track_insert_key(nt, 0.0, rest.basis.get_rotation_quaternion())
			else:
				o.position_track_insert_key(nt, 0.0, rest.origin)
	return o

## Wspólny graf: rest → mix_<stan> ← seek_<stan> ← klip, po kolei dla każdego klipu; wynik ostatniego miksu idzie na wyjście.
static func _blend_tree() -> AnimationNodeBlendTree:
	if _blend != null:
		return _blend
	_blend = AnimationNodeBlendTree.new()
	var n_rest := AnimationNodeAnimation.new()
	n_rest.animation = &"rest"
	_blend.add_node(&"rest", n_rest)
	var prev := &"rest"
	for st in CLIPS:
		if _source(st).is_empty():
			continue
		var na := AnimationNodeAnimation.new()
		na.animation = StringName(st)
		_blend.add_node(StringName("a_" + st), na)
		_blend.add_node(StringName("seek_" + st), AnimationNodeTimeSeek.new())
		_blend.connect_node(StringName("seek_" + st), 0, StringName("a_" + st))
		_blend.add_node(StringName("mix_" + st), AnimationNodeBlend2.new())
		_blend.connect_node(StringName("mix_" + st), 0, prev)
		_blend.connect_node(StringName("mix_" + st), 1, StringName("seek_" + st))
		prev = StringName("mix_" + st)
	_blend.connect_node(&"output", 0, prev)
	return _blend

## Drzewo animacji dla szkieletu `sk` modelu `key` (nazwa wyglądu — biblioteka przeliczonych klipów jest wspólna dla wszystkich postaci tego modelu).
## Zwraca null, gdy nie ma żadnego klipu. Wołający dodaje drzewo jako dziecko rodzica szkieletu.
static func build(sk: Skeleton3D, key: String) -> AnimationTree:
	if not _libs.has(key):
		var lib := AnimationLibrary.new()
		var anims: Array = []
		for st in CLIPS:
			var src := _source(st)
			if src.is_empty():
				continue
			var a := _retarget(src, sk)
			lib.add_animation(StringName(st), a)
			anims.append(a)
		if not anims.is_empty():
			lib.add_animation(&"rest", _rest_anim(sk, anims))
		_libs[key] = lib if not anims.is_empty() else null
	if _libs[key] == null:
		return null
	var tree := AnimationTree.new()
	tree.name = "Clips"
	tree.add_animation_library(&"", _libs[key])
	tree.tree_root = _blend_tree()
	tree.root_node = NodePath("..")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree

## Ustawia pozę szkieletu z klipów: weights = {stan → waga 0..1} (reszta do 1 to poza spoczynkowa), phase = faza kroku gry w obrotach.
static func drive(tree: AnimationTree, weights: Dictionary, phase: float) -> void:
	var acc := 1.0
	for st in weights:
		acc -= float(weights[st])
	acc = maxf(acc, 0.0)
	for st in CLIPS:
		var src := _source(st)
		if src.is_empty():
			continue
		var w := float(weights.get(st, 0.0))
		acc += w
		tree.set("parameters/mix_%s/blend_amount" % st, w / acc if acc > 0.0001 else 0.0)
		var dur := (src["anim"] as Animation).length
		tree.set("parameters/seek_%s/seek_request" % st, fposmod(phase - 0.25 + float(CLIPS[st]["phase0"]), 1.0) * dur)
	tree.advance(0.0)
