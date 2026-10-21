extends Node3D
## Ręce FPP z zasobu (strzelnica, RANGE_FPS_PLAN.md): `art/char3d/fp/fp_arms_<strój>.glb` z `tools/fp_arms.py` (rękawice, rękawy M65
## z karczkiem, zegarek; szkielet postaci) i `tools/fp_grip.py` (klip `grip_<broń>` — dłonie i palce ułożone na modelu broni do kontaktu,
## oraz węzeł `gunref_<broń>` na kości prawej dłoni). Model broni gry (gun_model.gd — części i nacięcia gracza) jest dzieckiem tego
## węzła, więc broń i dłonie poruszają się jako jedna bryła: chwyt jest taki, jak ułożony w Blenderze, co do milimetra.
## Broń bez ułożonego chwytu (`has_grip`) jest w kadrze sama (range_view.ARMS_FALLBACK; zapas — ręce z modelu postaci, fp_arms.gd).

const PATH := "res://art/char3d/fp/fp_arms_scav.glb"
const CYCLE_BACK := 0.025               ## s — suwadło w tył po strzale
const CYCLE_FWD := 0.035                ## s — i z powrotem
const TRIGGER_PULL := 12.0              ## ° — ściągnięcie języka spustu
const TRIGGER_PIVOT := Vector3(0.0588, 0.104, 0.0)   ## nasada języka spustu M-83 w układzie broni (gun_proc: trig x0+74…x0+132, z −38)
const ADS_SWITCH := 0.3                 ## część wejścia w przyrządy, w której lewa dłoń zmienia chwyt (krótko: pozy pośrednie odrywają dłoń od łoża)
const META := "res://art/char3d/fp/fp_arms_scav.json"   ## momenty przeładowań z fp_grip.py: {broń: {klip: {secs, mag_out, mag_in}}}

var ok := false
var key := ""                          ## broń z bieżącym chwytem ("" — brak)
var _scene: Node3D
var _anim: AnimationPlayer
var _ref: Node3D
var _skel: Skeleton3D
var _meta := {}
var _clip := ""                         ## bieżący klip ("grip_…" / "reload_…")
var _mag: Node3D                        ## magazynek modelu broni (węzeł „…__mag”) — w trakcie przeładowania jedzie z lewą dłonią
var _mag_rest := Transform3D.IDENTITY
var _mag_off := Transform3D.IDENTITY    ## magazynek względem lewej dłoni (z chwili chwytu)
var _mag_held := false
var _bolt: Node3D                       ## suwadło z rączką (węzeł „…__bolt”, gun_proc.py) — cofa się przy strzale i przy odciąganiu
var _bolt_rest := Transform3D.IDENTITY
var _trig: Node3D                       ## język spustu („…__trigger”)
var _trig_rest := Transform3D.IDENTITY
var _cycle_t := 1.0                     ## s od ostatniego strzału (cykl suwadła)
var _trig_t := 0.0                      ## 0..1 ściągnięcie spustu
var _rl_bolt := 0.0                     ## 0..1 suwadło odciągnięte ręką (klip przeładowania)
var _anchor := Transform3D.IDENTITY     ## broń w układzie rąk w pozie chwytu — kotwica kadru (przeładowanie rusza bronią względem niej)
var _anchor_ok := false
var _ads_rot := {}                      ## kość lewej ręki → obrót z klipu `grip_ads_<broń>` (podparcie łoża przy celowaniu)

func setup() -> bool:
	if not ResourceLoader.exists(PATH):
		return false
	_scene = (load(PATH) as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_anim = _scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skel = _scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if FileAccess.file_exists(META):
		_meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	for mi in _scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 1.0                                  # siatka skinowana tuż przed kamerą: bez odrzucania po AABB spoczynku
	ok = _anim != null
	visible = false
	return ok

func has_grip(k: String) -> bool:
	return ok and _anim.has_animation("grip_" + k) and _scene.find_child("gunref_" + k, true, false) != null

## Poza chwytu broni `k` i przypięcie modelu broni `gun` do jej punktu odniesienia. false — brak chwytu (broń zostaje, gdzie była).
func set_weapon(k: String, gun: Node3D) -> bool:
	if not has_grip(k):
		key = ""
		visible = false
		return false
	key = k
	_clip = ""
	_anchor_ok = false
	_mag_held = false
	_pose("grip_" + k, 0.0)
	_ads_rot = _clip_rotations("grip_ads_" + k, "Left")
	_ref = _scene.find_child("gunref_" + k, true, false) as Node3D
	if gun.get_parent() != null:
		gun.get_parent().remove_child(gun)
	_ref.add_child(gun)
	gun.transform = Transform3D.IDENTITY
	_mag = null
	for n in gun.find_children("*__mag", "Node3D", true, false):
		_mag = n as Node3D
		_mag_rest = _mag.transform
		break
	_bolt = gun.find_children("*__bolt", "Node3D", true, false).front() if not gun.find_children("*__bolt", "Node3D", true, false).is_empty() else null
	_trig = gun.find_children("*__trigger", "Node3D", true, false).front() if not gun.find_children("*__trigger", "Node3D", true, false).is_empty() else null
	if _bolt != null:
		_bolt_rest = _bolt.transform
	if _trig != null:
		_trig_rest = _trig.transform
	visible = true
	return true

## Poza w danej chwili: chwyt albo przeładowanie (`empty` — z pustego, z odciągnięciem suwadła) w postępie `u` 0..1 (WeaponController.reload_progress).
## Magazynek przechodzi do lewej dłoni od `mag_out` do `mag_in` klipu. `ads` 0..1 — celowanie: lewa ręka przechodzi z chwytu z boku
## łoża (od biodra, jak w CS) do podparcia od spodu (palce na wierzchu osłony zasłaniałyby muszkę); prawa i broń bez zmian.
func animate(reloading: bool, empty: bool, u: float, ads := 0.0) -> void:
	if key == "":
		return
	var clip := ("reload_empty_" if empty else "reload_") + key
	if not reloading or not _anim.has_animation(clip):
		_release_mag()
		_pose("grip_" + key, 0.0)
		var w := smoothstep(0.0, ADS_SWITCH, ads)
		if w > 0.0:
			for bi in _ads_rot:
				_skel.set_bone_pose_rotation(bi, _skel.get_bone_pose_rotation(bi).slerp(_ads_rot[bi], w))
		_anchor = gun_in_rig()
		_anchor_ok = true
		return
	_pose(clip, u * _anim.get_animation(clip).length)
	var m: Dictionary = _meta.get(key, {}).get(clip.trim_suffix("_" + key), {})
	_rl_bolt = 0.0
	if m.has("bolt"):                                            # suwadło za rączką: chwyt → odciągnięcie (tor dłoni), puszczenie → powrót
		var b: Array = m["bolt"]
		if u >= float(b[0]) and u < float(b[2]):
			_rl_bolt = smoothstep(float(b[0]), float(b[1]), u)
	if _mag == null or m.is_empty():
		return
	var held := u >= float(m["mag_out"]) and u < float(m["mag_in"])
	if held and not _mag_held:
		_mag_off = hand_global("Left").affine_inverse() * _mag.global_transform
		_mag_held = true
	elif not held:
		_release_mag()
	if _mag_held:
		_mag.global_transform = hand_global("Left") * _mag_off

## Strzał: suwadło rusza w tył i wraca (ok. 60 ms), spust ściągnięty.
func shot() -> void:
	_cycle_t = 0.0
	_trig_t = 1.0

## Co klatkę: cykl suwadła po strzale albo odciągnięcie z klipu (większe wygrywa), spust (`held` — palec na spuście).
func tick_parts(delta: float, held: bool) -> void:
	_cycle_t += delta
	_trig_t = move_toward(_trig_t, 1.0 if held else 0.0, delta * 14.0)
	var travel := 0.08
	var mk: Dictionary = _meta.get(key, {}).get("reload_empty", {})
	if mk.has("bolt_travel"):
		travel = float(mk["bolt_travel"])
	var c := 0.0
	if _cycle_t < CYCLE_BACK:
		c = _cycle_t / CYCLE_BACK
	elif _cycle_t < CYCLE_BACK + CYCLE_FWD:
		c = 1.0 - (_cycle_t - CYCLE_BACK) / CYCLE_FWD
	if _bolt != null:
		_bolt.transform = _bolt_rest.translated_local(Vector3(-travel * maxf(c, _rl_bolt), 0.0, 0.0))
	if _trig != null:                                            # język spustu obraca się wokół nasady (pod komorą) w tył
		var piv := TRIGGER_PIVOT
		_trig.transform = _trig_rest * Transform3D(Basis(Vector3.BACK, deg_to_rad(-TRIGGER_PULL) * _trig_t), piv - Basis(Vector3.BACK, deg_to_rad(-TRIGGER_PULL) * _trig_t) * piv)

## Zdarzenia dźwiękowe klipu przeładowania (`[[u, klucz], …]` z fp_grip.py), puste — brak.
func events(empty: bool) -> Array:
	return _meta.get(key, {}).get("reload_empty" if empty else "reload", {}).get("events", [])

## Czy przeładowanie tej broni ma klip z własnymi dźwiękami mechaniki (wtedy ogólny dźwięk „reload” milczy).
func has_reload_clip(k: String) -> bool:
	return ok and _anim.has_animation("reload_" + k)

func _release_mag() -> void:
	if _mag != null and _mag_held:
		_mag.transform = _mag_rest
	_mag_held = false

## Obroty kości strony `side` z pierwszej klatki klipu (kość → kwaternion); pusty słownik — brak klipu.
func _clip_rotations(clip: String, side: String) -> Dictionary:
	var out := {}
	if not _anim.has_animation(clip):
		return out
	var a := _anim.get_animation(clip)
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(i).get_subname(0))
		var bi := _skel.find_bone(bone)
		if bone.contains(side) and bi >= 0:
			out[bi] = a.rotation_track_interpolate(i, 0.0)
	return out

func _pose(clip: String, t: float) -> void:
	if clip != _clip:
		_clip = clip
		_anim.play(clip)
		_anim.pause()
	_anim.seek(t, true)

## Kość dłoni w świecie (po bieżącej pozie).
func hand_global(side: String) -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sHand" % side))

## Kotwica kadru: broń w układzie rąk z pozy chwytu. Kadr ustawia ręce tak, żeby TA broń stała w zadanym miejscu, więc ruch broni
## w klipie przeładowania (przechył, podbicie, szarpnięcie suwadła) jest widoczny, a nie znoszony.
func anchor() -> Transform3D:
	return _anchor if _anchor_ok else gun_in_rig()

## Broń w układzie tego węzła (z bieżącej pozy szkieletu) — do ustawienia całych rąk tak, by broń stała w zadanym miejscu kadru.
func gun_in_rig() -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = _ref
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
