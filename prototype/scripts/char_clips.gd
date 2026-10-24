extends RefCounted
## Klipy animacji postaci 3D: wczytuje `art/char3d/anim/<nazwa>.glb` (tools/prep_anim3d.py), przelicza je na szkielet danego wyglądu
## i buduje `AnimationTree`, który miesza je z pozą spoczynkową. Drzewo daje ruch ciała (biodra, tułów, głowa, tor stóp);
## ręce z bronią i postawienie stóp na podłożu dalej liczy IK w `char3d.gd`, na wierzchu klipu.
##
## Klip niesie własną pozę spoczynkową, więc działa na każdym modelu z kośćmi Mixamo: obroty przenosimy względem spoczynku,
## przesunięcie bioder skalujemy wysokością bioder. Pozostałe przesunięcia i skale kości pomijamy (zmieniałyby proporcje modelu).
## Czas klipu ustawia gra, nie zegar drzewa: pętle kroku idą fazą kroku z `char3d.gd` (krok klipu i krok z kodu to ta sama faza),
## pozostałe pętle (postój, kucanie) — zegarem postaci, klipy jednorazowe (upadek) — postępem 0..1, który gra już liczy,
## a pozy trzymane (klęczenie przy rannym) — czasem od wejścia w stan.

const DIR := "res://art/char3d/anim/"
const HIPS := "mixamorig_Hips"
## Kości tułowia i głowy: ich ruch z klipu można stłumić (`upper`), bo tułów ma przede wszystkim celować.
const UPPER := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftShoulder", "mixamorig_RightShoulder"]
## Stan → klip. Stany bazowe to AW_STATES z char3d.gd; „down" i „getup" to upadek i wstawanie (wagi i postęp z `char3d.gd`).
## Wartość w `progress` (CharClips.drive) znaczy: dla `scrub` postęp 0..1, dla `hold` sekundy od wejścia w stan.
## step: pętla kroku — czas z fazy kroku gry; phase0 to ułamek cyklu, w którym prawa stopa ląduje (klipy z `prep_anim3d.py --step-sync` mają 0).
## scrub: [t0, t1] — klip jednorazowy: postęp 0..1 z gry wybiera chwilę klipu między t0 a t1 (s); wstecz gra się go tym samym postępem.
## hold: [t0, t1, t2, wejście] — poza trzymana: przez `wejście` s klip idzie od t0 do t1 (zejście do pozy), potem chodzi tam i z powrotem
##   między t1 a t2 (praca rąk), dopóki stan trwa; wyjście to zwykłe mieszanie stanów.
##   Bez `step`, `scrub` i `hold` klip idzie zegarem postaci.
## arms: ręce z klipu zamiast IK, broń schowana (stan bez strzelania).
## upper: ile ruchu tułowia i głowy z klipu zostaje (1 = cały, 0 = tułów jak w spoczynku) — klipy z biblioteki pochylają tułów i skręcają barki
##   o kilkadziesiąt stopni, co przy celowaniu rzuca bronią.
## drop: o tyle metrów niżej stoją biodra niż w klipie (kucanie: sylwetka ma mieć wysokość hitboxa kucania, jak poza z kodu);
##   ujemne podnosi (leżenie: plecak modelu nie wchodzi w podłoże).
## bounce: ile pionowego kołysania bioder z klipu zostaje (1 = całe). Sprint z biblioteki kołysze ciałem o 11 cm, a z barkiem idzie chwyt broni,
##   czyli punkt, z którego gra liczy celowanie i wylot pocisku; stopy zostają na torze z klipu (IK nóg).
const CLIPS := {
	"idle": {"file": "idle", "upper": 0.5},
	"run": {"file": "run", "step": true, "phase0": 0.0, "upper": 0.55, "bounce": 0.8},
	"crouch": {"file": "crouch", "upper": 0.35, "drop": 0.05},
	"crouch_walk": {"file": "crouch_walk", "step": true, "phase0": 0.0, "upper": 0.5, "drop": 0.06},
	"revive": {"file": "kneel", "hold": [0.3, 1.0, 3.6, 0.4], "arms": true},
	"down": {"file": "down", "scrub": [0.15, 1.65], "drop": -0.05},
	"getup": {"file": "getup", "scrub": [0.1, 1.5]},
	"combat_chop": {"file": "combat_chop", "scrub": [0.0, 1.0], "additive": true},
	"combat_slash": {"file": "combat_slash", "scrub": [0.0, 1.0], "additive": true},
	"combat_reload": {"file": "combat_reload", "scrub": [0.0, 1.0], "additive": true},
	"combat_fire_rifle": {"file": "combat_fire_rifle", "scrub": [0.0, 1.0], "additive": true},
	"combat_fire_pistol": {"file": "combat_fire_pistol", "scrub": [0.0, 1.0], "additive": true},
	"combat_fire_heavy": {"file": "combat_fire_heavy", "scrub": [0.0, 1.0], "additive": true},
}
## Klipy wrogów dwunożnych (enemy3d.gd): chód. Faza kroku wroga ma lądowanie prawej stopy w połowie obrotu (u gracza w ćwierci), stąd phase0.
## Postawę potwora (pochylenie, ręce) dalej daje profil z enemy3d.gd; z klipu idą biodra, nogi i część ruchu tułowia.
## rise: o tyle (ułamek wysokości bioder w spoczynku) biodra stoją wyżej niż w klipie — chód zombie mocno obniża sylwetkę,
##   a wróg ma zostać czytelny względem swojego hitboxa.
## Dwa zestawy: „zombie" (powłóczysty krok potwora) i „human" (zwykły ludzki chód — Mimik udaje człowieka).
## Atak pazurami to jeden klip w dwóch stanach: „windup" trzyma chwilę, w której potwór unosi się z ręką w górze (zapowiedź ciosu trwa
## tyle, ile każe gra), „attack" gra rzut w dół i powrót postępem ciosu z enemy3d.gd. Ręce idą wtedy z klipu.
const ZOMBIE_CLIPS := {
	"walk": {"file": "zombie_walk", "step": true, "phase0": -0.25, "upper": 0.2, "rise": 0.05},
	"windup": {"file": "zombie_attack", "hold": [0.1, 0.5, 0.5, 0.25], "arms": true},
	"attack": {"file": "zombie_attack", "scrub": [0.5, 1.4], "arms": true},
}
const HUMAN_CLIPS := {
	"walk": {"file": "walk", "step": true, "phase0": -0.25, "upper": 0.15},
}
## Zestawy klipów: nazwa zestawu → tabela stan → klip. Drzewo pamięta swój zestaw (meta „set").
const SETS := {"player": CLIPS, "zombie": ZOMBIE_CLIPS, "human": HUMAN_CLIPS}

static var enabled := true                   ## --noclips wyłącza klipy (same pozy z kodu, do porównań)
static var _src := {}                        ## plik → {"anim": Animation, "rest": {kość → Transform3D}, "hips_y": float} albo {} (brak pliku)
static var _libs := {}                       ## nazwa modelu → AnimationLibrary (klipy przeliczone na ten szkielet + "rest")
static var _means := {}                      ## nazwa modelu → {stan → średnie pionowe przesunięcie bioder w klipie względem spoczynku (m)}
static var _blends := {}                     ## zestaw → AnimationNodeBlendTree
static var _flat := {}                       ## kość stopy / palców → globalny obrót w 1. klatce klipu idle (stopa płasko na ziemi); {} = brak klipu
static var _orders := {}                     ## zestaw → klipy w kolejności grafu: [stan, ścieżka wagi, ścieżka czasu, długość (s), czy pętla kroku, phase0, scrub albo null, hold albo null]

static func has(state: String, set_name := "player") -> bool:
	return enabled and not _source(state, set_name).is_empty()

## Parametr klipu danego stanu z tabeli zestawu (np. "drop").
static func param(state: String, key: String, default: float, set_name := "player") -> float:
	return float(((SETS[set_name] as Dictionary).get(state, {}) as Dictionary).get(key, default))

## Klip źródłowy stanu (pusty słownik, gdy stan nie ma klipu albo brak pliku).
static func _source(state: String, set_name := "player") -> Dictionary:
	var tab: Dictionary = SETS[set_name]
	return _load(String((tab[state] as Dictionary)["file"])) if tab.has(state) else {}

## Surowy klip z pliku `art/char3d/anim/<file>.glb` przeliczony na szkielet `sk` (bez dostrojenia) — do podglądów (tools/shot_clip3d.gd).
static func clip(file: String, sk: Skeleton3D) -> Animation:
	var src := _load(file)
	return _retarget(src, sk) if not src.is_empty() else null

## Klip źródłowy z pliku (raz na sesję).
static func _load(file: String) -> Dictionary:
	if _src.has(file):
		return _src[file]
	var out := {}
	var path := DIR + file + ".glb"
	if ResourceLoader.exists(path):
		var scene: Node = (load(path) as PackedScene).instantiate()
		var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
		var aps := scene.find_children("*", "AnimationPlayer", true, false)
		if sk != null and not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			var names := ap.get_animation_list()
			if not names.is_empty():
				var rest := {}
				var parent := {}
				var grest := {}
				for i in sk.get_bone_count():
					rest[sk.get_bone_name(i)] = sk.get_bone_rest(i)
					grest[sk.get_bone_name(i)] = sk.get_bone_global_rest(i)
					var pi := sk.get_bone_parent(i)
					parent[sk.get_bone_name(i)] = sk.get_bone_name(pi) if pi >= 0 else ""
				var hi := sk.find_bone(HIPS)
				out = {"anim": ap.get_animation(names[0]), "rest": rest, "grest": grest, "parent": parent,
						"hips_y": sk.get_bone_global_rest(hi).origin.y if hi >= 0 else 1.0}
		scene.free()
	_src[file] = out
	return out

## Stopy i palce źródła w pozie „stoi płasko” (1. klatka klipu idle, globalnie w przestrzeni szkieletu źródła). Poza spoczynkowa
## szkieletu biblioteki ma stopy inaczej ustawione niż przy staniu — przeniesienie względem spoczynku wyprostowywało stopy o ~19°
## w każdym klipie (postać stała na palcach, czubki pod podłogą). Stopy przenosimy więc względem tej pozy.
static func _flat_ref() -> Dictionary:
	if not _flat.is_empty():
		return _flat
	var src := _load(String((CLIPS["idle"] as Dictionary)["file"]))
	if src.is_empty():
		return _flat
	var a: Animation = src["anim"]
	var parent_s: Dictionary = src["parent"]
	var grest_s: Dictionary = src["grest"]
	var rot := {}
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot[String(a.track_get_path(t).get_concatenated_subnames())] = a.rotation_track_interpolate(t, 0.0)
	var g := {}
	var todo: Array = grest_s.keys()
	todo.sort_custom(func(x: String, y: String) -> bool: return _src_depth(parent_s, x) < _src_depth(parent_s, y))
	for bone: String in todo:
		var ps := String(parent_s[bone])
		var gp: Quaternion = g[ps] if g.has(ps) else Quaternion.IDENTITY
		var q: Quaternion = rot[bone] if rot.has(bone) else (src["rest"][bone] as Transform3D).basis.get_rotation_quaternion()
		g[bone] = gp * q
	for bone: String in g:
		if _is_foot(bone):
			_flat[bone] = (g[bone] as Quaternion).normalized()
	_flat["_grest"] = grest_s                      # spoczynek szkieletu idle: inne pliki z tym samym spoczynkiem dostają tę samą poprawkę
	return _flat

static func _is_foot(bone: String) -> bool:
	return bone.ends_with("Foot") or bone.contains("ToeBase")

static func _src_depth(parent_s: Dictionary, bone: String) -> int:
	var d := 0
	var b := String(parent_s.get(bone, ""))
	while b != "":
		d += 1
		b = String(parent_s.get(b, ""))
	return d

## Klip przeliczony na szkielet `sk`: ścieżki „<Skeleton3D>:<kość>”, biodra w skali celu. Przeliczenie w przestrzeni szkieletu: każda kość
## dostaje ten sam obrót względem swojej pozy spoczynkowej co kość źródłowa (świat szkieletu), niezależnie od osi lokalnych kości — klip ze
## szkieletu Tripo gra więc poprawnie na szkielecie MPFB (inne osie kości, inna poza spoczynkowa) i na każdym innym o tych samych nazwach.
## Przy identycznych osiach lokalnych wynik jest taki sam jak przy przeliczeniu lokalnym. upper < 1 tłumi ruch kości tułowia i głowy (UPPER)
## w stronę pozy spoczynkowej.
static func _retarget(src: Dictionary, sk: Skeleton3D, upper := 1.0) -> Animation:
	var a: Animation = src["anim"]
	var rest_s: Dictionary = src["rest"]
	var grest_s: Dictionary = src["grest"]
	var parent_s: Dictionary = src["parent"]
	var hi := sk.find_bone(HIPS)
	var k_h := sk.get_bone_global_rest(hi).origin.y / maxf(float(src["hips_y"]), 0.001) if hi >= 0 else 1.0
	var hp := sk.get_bone_parent(hi) if hi >= 0 else -1
	var up_axis := (sk.get_bone_global_rest(hp).basis if hp >= 0 else Basis.IDENTITY).inverse() * Vector3.UP   # pion szkieletu w układzie rodzica bioder (kość Root jest obrócona)
	# ścieżki obrotu źródła i czasy kluczy (klipy z prep_anim3d.py mają klucze co klatkę na wszystkich kościach)
	var rot_tr := {}
	var pos_tr := -1
	var times := PackedFloat32Array()
	for t in a.get_track_count():
		var bone := String(a.track_get_path(t).get_concatenated_subnames())
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and rest_s.has(bone):
			rot_tr[bone] = t
			if a.track_get_key_count(t) > times.size():
				times = PackedFloat32Array()
				for k in a.track_get_key_count(t):
					times.append(a.track_get_key_time(t, k))
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == HIPS:
			pos_tr = t
	# kości celu z odpowiednikiem w źródle, w kolejności rodzic przed dzieckiem
	var bones: Array = []
	for i in sk.get_bone_count():
		if rot_tr.has(sk.get_bone_name(i)):
			bones.append(i)
	bones.sort_custom(func(x: int, y: int) -> bool: return _depth(sk, x) < _depth(sk, y))
	# stopy: odniesieniem poza „stoi płasko” z klipu idle (o ile ten plik ma ten sam spoczynek stóp co idle)
	var flat := _flat_ref()
	var feet_ref := {}
	for bone: String in rest_s:
		if _is_foot(bone) and flat.has(bone):
			var gi: Transform3D = (flat["_grest"] as Dictionary).get(bone, Transform3D())
			var gs_rest: Quaternion = (grest_s[bone] as Transform3D).basis.get_rotation_quaternion()
			if gi.basis.get_rotation_quaternion().angle_to(gs_rest) < deg_to_rad(1.0):
				feet_ref[bone] = flat[bone]
	var o := Animation.new()
	o.length = a.length
	o.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	for bi in bones:
		var nt := o.add_track(Animation.TYPE_ROTATION_3D)
		o.track_set_path(nt, NodePath("%s:%s" % [sk.name, sk.get_bone_name(bi)]))
		tracks[bi] = nt
	for time in times:
		var gs := {}                                                  # nazwa → globalny obrót kości źródła w tej klatce
		var gt := {}                                                  # indeks → globalny obrót kości celu w tej klatce
		for bi in bones:
			var bone := sk.get_bone_name(bi)
			var q_src := a.rotation_track_interpolate(int(rot_tr[bone]), time)
			var ps := String(parent_s[bone])
			var gps: Quaternion = gs[ps] if gs.has(ps) else ((grest_s[ps] as Transform3D).basis.get_rotation_quaternion() if ps != "" else Quaternion.IDENTITY)
			gs[bone] = gps * q_src
			var ref: Quaternion = feet_ref[bone] if feet_ref.has(bone) else (grest_s[bone] as Transform3D).basis.get_rotation_quaternion()
			var delta: Quaternion = gs[bone] * ref.inverse()
			var g_t := (delta * sk.get_bone_global_rest(bi).basis.get_rotation_quaternion()).normalized()
			gt[bi] = g_t
			var pt := sk.get_bone_parent(bi)
			var gpt: Quaternion = gt[pt] if gt.has(pt) else (sk.get_bone_global_rest(pt).basis.get_rotation_quaternion() if pt >= 0 else Quaternion.IDENTITY)
			var q := (gpt.inverse() * g_t).normalized()
			if UPPER.has(bone) and upper < 1.0:
				q = sk.get_bone_rest(bi).basis.get_rotation_quaternion().slerp(q, upper)
			o.rotation_track_insert_key(int(tracks[bi]), time, q)
	if pos_tr >= 0 and hi >= 0:
		# biodra: przesunięcie względem spoczynku przeniesione przez przestrzeń szkieletu (rodzic bioder może mieć inne osie) i w skali celu
		var ps := String(parent_s[HIPS])
		var bs_src: Basis = (grest_s[ps] as Transform3D).basis if ps != "" else Basis.IDENTITY
		var bs_dst: Basis = sk.get_bone_global_rest(hp).basis if hp >= 0 else Basis.IDENTITY
		var rt := sk.get_bone_rest(hi)
		var rs: Transform3D = rest_s[HIPS]
		var np := o.add_track(Animation.TYPE_POSITION_3D)
		o.track_set_path(np, NodePath("%s:%s" % [sk.name, HIPS]))
		var up := 0.0
		for k in a.track_get_key_count(pos_tr):
			var off := bs_dst.inverse() * (bs_src * (((a.track_get_key_value(pos_tr, k) as Vector3) - rs.origin) * k_h))
			up += off.dot(up_axis)
			o.position_track_insert_key(np, a.track_get_key_time(pos_tr, k), rt.origin + off)
		o.set_meta("hips_mean", up / maxf(float(a.track_get_key_count(pos_tr)), 1.0))
	return o

static func _depth(sk: Skeleton3D, bi: int) -> int:
	var d := 0
	var p := sk.get_bone_parent(bi)
	while p >= 0:
		d += 1
		p = sk.get_bone_parent(p)
	return d

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

## Wspólny graf zestawu: rest → mix_<stan> ← seek_<stan> ← klip, po kolei dla każdego klipu; wynik ostatniego miksu idzie na wyjście.
static func _blend_tree(set_name: String) -> AnimationNodeBlendTree:
	if _blends.has(set_name):
		return _blends[set_name]
	var tab: Dictionary = SETS[set_name]
	var _blend := AnimationNodeBlendTree.new()
	var _order: Array = []
	_blends[set_name] = _blend
	_orders[set_name] = _order
	var n_rest := AnimationNodeAnimation.new()
	n_rest.animation = &"rest"
	_blend.add_node(&"rest", n_rest)
	var prev := &"rest"
	for st in tab:
		if _source(st, set_name).is_empty():
			continue
		var na := AnimationNodeAnimation.new()
		na.animation = StringName(st)
		_blend.add_node(StringName("a_" + st), na)
		_blend.add_node(StringName("seek_" + st), AnimationNodeTimeSeek.new())
		_blend.connect_node(StringName("seek_" + st), 0, StringName("a_" + st))
		var c: Dictionary = tab[st]
		var additive := bool(c.get("additive", false))
		var mix: AnimationNode = AnimationNodeAdd2.new() if additive else AnimationNodeBlend2.new()
		if additive:
			mix.filter_enabled = true
			# Nogi idą z lokomocji; IK utrzymuje stopy na ziemi po przeniesieniu ciężaru bioder.
			for bone in [HIPS, "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]:
				mix.set_filter_path(NodePath("Skeleton3D:" + bone), true)
		_blend.add_node(StringName("mix_" + st), mix)
		_blend.connect_node(StringName("mix_" + st), 0, prev)
		_blend.connect_node(StringName("mix_" + st), 1, StringName("seek_" + st))
		prev = StringName("mix_" + st)
		_order.append([st, StringName("parameters/mix_%s/%s" % [st, "add_amount" if additive else "blend_amount"]), StringName("parameters/seek_%s/seek_request" % st),
				(_source(st, set_name)["anim"] as Animation).length, bool(c.get("step", false)), float(c.get("phase0", 0.0)), c.get("scrub"), c.get("hold"), additive])
	_blend.connect_node(&"output", 0, prev)
	return _blend

## Drzewo animacji dla szkieletu `sk` modelu `key` (nazwa wyglądu — biblioteka przeliczonych klipów jest wspólna dla wszystkich postaci tego modelu).
## Zwraca null, gdy nie ma żadnego klipu. Wołający dodaje drzewo jako dziecko rodzica szkieletu. raw: klipy bez tłumienia tułowia (porównania).
## set_name: zestaw klipów („player" albo „enemy").
static func build(sk: Skeleton3D, key: String, raw := false, set_name := "player") -> AnimationTree:
	key = set_name + "|" + key
	if raw:
		key += "|raw"
	var tab: Dictionary = SETS[set_name]
	if not _libs.has(key):
		var lib := AnimationLibrary.new()
		var anims: Array = []
		var means := {}
		for st in tab:
			var src := _source(st, set_name)
			if src.is_empty():
				continue
			var a := _retarget(src, sk, 1.0 if raw else float((tab[st] as Dictionary).get("upper", 1.0)))
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
	tree.set_meta("set", set_name)
	tree.add_animation_library(&"", _libs[key])
	tree.tree_root = _blend_tree(set_name)
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
	var set_name := String(tree.get_meta("set", "player"))
	var mean := 0.0
	var cut := 0.0
	var total := 0.0
	for st in weights:
		var w := float(weights[st])
		mean += w * float(means.get(st, 0.0))
		cut += w * (1.0 - param(st, "bounce", 1.0, set_name))
		total += w
	return -(hips_up - mean) * cut / total if total > 0.0001 else 0.0

## Ustawia pozę szkieletu z klipów: weights = {stan → waga 0..1} (reszta do 1 to poza spoczynkowa), phase = faza kroku gry w obrotach,
## time = zegar postaci (s) dla pętli bez kroku, progress = {stan → postęp 0..1} dla klipów jednorazowych.
static func drive(tree: AnimationTree, weights: Dictionary, phase: float, time: float, progress: Dictionary) -> void:
	var acc := 1.0
	for st in weights:
		if not bool((SETS[tree.get_meta("set", "player")][st] as Dictionary).get("additive", false)):
			acc -= float(weights[st])
	acc = maxf(acc, 0.0)
	for o in (_orders[tree.get_meta("set", "player")] as Array):
		var w := float(weights.get(o[0], 0.0))
		if not bool(o[8]):
			acc += w
		tree.set(o[1], w if bool(o[8]) else (w / acc if acc > 0.0001 else 0.0))
		if w > 0.0:                                               # klip bez wagi nie jest liczony — czas dostanie w klatce, w której wejdzie
			var dur: float = o[3]
			if o[6] != null:
				tree.set(o[2], lerpf(float(o[6][0]), minf(float(o[6][1]), dur - 0.001), clampf(float(progress.get(o[0], 0.0)), 0.0, 1.0)))
			elif o[7] != null:
				var h: Array = o[7]
				var s := float(progress.get(o[0], 0.0))
				var t_in := float(h[3])
				tree.set(o[2], lerpf(float(h[0]), float(h[1]), smoothstep(0.0, 1.0, s / t_in)) if s < t_in
						else float(h[1]) + pingpong(s - t_in, float(h[2]) - float(h[1])))
			else:
				tree.set(o[2], fposmod(phase - 0.25 + float(o[5]), 1.0) * dur if o[4] else fposmod(time, dur))
	tree.advance(0.0)
