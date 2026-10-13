extends RefCounted
## Klipy animacji postaci 3D: wczytuje `art/char3d/anim/<nazwa>.glb` (tools/prep_anim3d.py), przelicza je na szkielet danego wyglądu
## i buduje `AnimationTree`, który miesza je z pozą spoczynkową. Drzewo daje ruch ciała (biodra, tułów, głowa, tor stóp);
## ręce z bronią i postawienie stóp na podłożu dalej liczy IK w `char3d.gd`, na wierzchu klipu.
##
## Klip niesie własną pozę spoczynkową, więc działa na każdym modelu z kośćmi Mixamo: obroty przenosimy względem spoczynku,
## przesunięcie bioder skalujemy wysokością bioder. Pozostałe przesunięcia i skale kości pomijamy (zmieniałyby proporcje modelu).
## Czas klipu ustawia gra, nie zegar drzewa: pętle kroku idą fazą kroku z `char3d.gd` (krok klipu i krok z kodu to ta sama faza),
## pozostałe pętle (postój, kucanie) — zegarem postaci.

const DIR := "res://art/char3d/anim/"
const HIPS := "mixamorig_Hips"
## Kości tułowia i głowy: ich ruch z klipu można stłumić (`upper`), bo tułów ma przede wszystkim celować.
const UPPER := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftShoulder", "mixamorig_RightShoulder"]
## Stan bazowy (AW_STATES w char3d.gd) → klip.
## step: pętla kroku — czas z fazy kroku gry; phase0 to ułamek cyklu, w którym prawa stopa ląduje (klipy z `prep_anim3d.py --step-sync` mają 0).
##   Bez `step` klip idzie zegarem postaci.
## upper: ile ruchu tułowia i głowy z klipu zostaje (1 = cały, 0 = tułów jak w spoczynku) — klipy z biblioteki pochylają tułów i skręcają barki
##   o kilkadziesiąt stopni, co przy celowaniu rzuca bronią.
## drop: o tyle metrów niżej stoją biodra niż w klipie (kucanie: sylwetka ma mieć wysokość hitboxa kucania, jak poza z kodu).
## bounce: ile pionowego kołysania bioder z klipu zostaje (1 = całe). Sprint z biblioteki kołysze ciałem o 11 cm, a z barkiem idzie chwyt broni,
##   czyli punkt, z którego gra liczy celowanie i wylot pocisku; stopy zostają na torze z klipu (IK nóg).
const CLIPS := {
	"idle": {"file": "idle", "upper": 0.5},
	"run": {"file": "run", "step": true, "phase0": 0.0, "upper": 0.35, "bounce": 0.45},
	"crouch": {"file": "crouch", "upper": 0.35, "drop": 0.05},
	"crouch_walk": {"file": "crouch_walk", "step": true, "phase0": 0.0, "upper": 0.35, "drop": 0.06},
}

static var enabled := true                   ## --noclips wyłącza klipy (same pozy z kodu, do porównań)
static var _src := {}                        ## stan → {"anim": Animation, "rest": {kość → Transform3D}, "hips_y": float} albo {} (brak pliku)
static var _libs := {}                       ## nazwa modelu → AnimationLibrary (klipy przeliczone na ten szkielet + "rest")
static var _means := {}                      ## nazwa modelu → {stan → średnie pionowe przesunięcie bioder w klipie względem spoczynku (m)}
static var _blend: AnimationNodeBlendTree
static var _order: Array = []                ## klipy w kolejności grafu: [stan, ścieżka wagi, ścieżka czasu, długość (s), czy pętla kroku, phase0]

static func has(state: String) -> bool:
	return enabled and not _source(state).is_empty()

## Parametr klipu danego stanu z tabeli CLIPS (np. "drop").
static func param(state: String, key: String, default: float) -> float:
	return float((CLIPS.get(state, {}) as Dictionary).get(key, default))

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
## upper < 1 tłumi ruch kości tułowia i głowy (UPPER) w stronę pozy spoczynkowej.
static func _retarget(src: Dictionary, sk: Skeleton3D, upper := 1.0) -> Animation:
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
				var rq := rt.basis.get_rotation_quaternion()
				var fix := rq * rs.basis.get_rotation_quaternion().inverse()
				var damp := upper if UPPER.has(bone) else 1.0
				var nt := o.add_track(Animation.TYPE_ROTATION_3D)
				o.track_set_path(nt, NodePath("%s:%s" % [sk.name, bone]))
				for k in a.track_get_key_count(t):
					var q := (fix * (a.track_get_key_value(t, k) as Quaternion)).normalized()
					o.rotation_track_insert_key(nt, a.track_get_key_time(t, k), rq.slerp(q, damp) if damp < 1.0 else q)
			Animation.TYPE_POSITION_3D:
				if bone != HIPS:
					continue
				var np := o.add_track(Animation.TYPE_POSITION_3D)
				o.track_set_path(np, NodePath("%s:%s" % [sk.name, bone]))
				var up := 0.0
				for k in a.track_get_key_count(t):
					var off := ((a.track_get_key_value(t, k) as Vector3) - rs.origin) * k_h
					up += off.y
					o.position_track_insert_key(np, a.track_get_key_time(t, k), rt.origin + off)
				o.set_meta("hips_mean", up / maxf(float(a.track_get_key_count(t)), 1.0))      # biodra to kość główna: jej Y to pion szkieletu
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
		var c: Dictionary = CLIPS[st]
		_order.append([st, StringName("parameters/mix_%s/blend_amount" % st), StringName("parameters/seek_%s/seek_request" % st),
				(_source(st)["anim"] as Animation).length, bool(c.get("step", false)), float(c.get("phase0", 0.0))])
	_blend.connect_node(&"output", 0, prev)
	return _blend

## Drzewo animacji dla szkieletu `sk` modelu `key` (nazwa wyglądu — biblioteka przeliczonych klipów jest wspólna dla wszystkich postaci tego modelu).
## Zwraca null, gdy nie ma żadnego klipu. Wołający dodaje drzewo jako dziecko rodzica szkieletu. raw: klipy bez tłumienia tułowia (porównania).
static func build(sk: Skeleton3D, key: String, raw := false) -> AnimationTree:
	if raw:
		key += "|raw"
	if not _libs.has(key):
		var lib := AnimationLibrary.new()
		var anims: Array = []
		var means := {}
		for st in CLIPS:
			var src := _source(st)
			if src.is_empty():
				continue
			var a := _retarget(src, sk, 1.0 if raw else float((CLIPS[st] as Dictionary).get("upper", 1.0)))
			lib.add_animation(StringName(st), a)
			anims.append(a)
			means[st] = float(a.get_meta("hips_mean", 0.0))
		if not anims.is_empty():
			lib.add_animation(&"rest", _rest_anim(sk, anims))
		_libs[key] = lib if not anims.is_empty() else null
		_means[key] = means
	if _libs[key] == null:
		return null
	var tree := AnimationTree.new()
	tree.name = "Clips"
	tree.set_meta("key", key)
	tree.set_meta("raw", raw)
	tree.add_animation_library(&"", _libs[key])
	tree.tree_root = _blend_tree()
	tree.root_node = NodePath("..")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree

## Poprawka kołysania (m, do dodania do pionu bioder po `drive`): zdejmuje część odchylenia bioder od średniej klipu wg `bounce` z CLIPS.
## hips_up = bieżące pionowe przesunięcie bioder względem spoczynku (po zmieszaniu klipów).
static func bounce_fix(tree: AnimationTree, weights: Dictionary, hips_up: float) -> float:
	if tree.get_meta("raw", false):
		return 0.0
	var means: Dictionary = _means.get(tree.get_meta("key", ""), {})
	var mean := 0.0
	var cut := 0.0
	var total := 0.0
	for st in weights:
		var w := float(weights[st])
		mean += w * float(means.get(st, 0.0))
		cut += w * (1.0 - param(st, "bounce", 1.0))
		total += w
	return -(hips_up - mean) * cut / total if total > 0.0001 else 0.0

## Ustawia pozę szkieletu z klipów: weights = {stan → waga 0..1} (reszta do 1 to poza spoczynkowa), phase = faza kroku gry w obrotach,
## time = zegar postaci (s) dla pętli bez kroku.
static func drive(tree: AnimationTree, weights: Dictionary, phase: float, time: float) -> void:
	var acc := 1.0
	for st in weights:
		acc -= float(weights[st])
	acc = maxf(acc, 0.0)
	for o in _order:
		var w := float(weights.get(o[0], 0.0))
		acc += w
		tree.set(o[1], w / acc if acc > 0.0001 else 0.0)
		if w > 0.0:                                               # klip bez wagi nie jest liczony — czas dostanie w klatce, w której wejdzie
			var dur: float = o[3]
			tree.set(o[2], fposmod(phase - 0.25 + float(o[5]), 1.0) * dur if o[4] else fposmod(time, dur))
	tree.advance(0.0)
