extends "res://scripts/enemy3d.gd"
## Zwłoki w świecie (MIMIC_PLAN.md M3): operator Patrolu Siedem, technik radiostacji albo górnik leżący na podłodze — ten sam model i
## dopasowanie co Mimik (PROP_SPEC `corpse` w enemy3d.gd, strój wybiera `model_path`), żeby Mimik udający zwłoki (M5) wyglądał tak samo.
## Poza leżenia jest wypiekana raz przy budowie: koniec klipu upadku gracza (`down`, char_clips.gd) plus wariant ułożenia z ziarna,
## potem szkielet stoi — bez klipów, IK i oddechu w każdej klatce, koszt zbliżony do rekwizytu. Ciało opiera się najniższym punktem
## otoczki skóry na gruncie. Przeszukane (M4) zmienia ułożenie o szczegół: ręka odsunięta od ciała, głowa na drugą stronę.
##
## Mimik-zwłoki (M5, `build(…, mimic = true)`): ta sama poza, strój i materiał; różnią go sygnały: brak plamy pod ciałem (view3d), oczy
## otwarte — w snopie latarki łapią połysk (`mimic_lit` z widoku, jak u stojącego Mimika), a po BREATH_AFTER s ciągłego światła klatka
## piersiowa zaczyna się unosić. Tylko on liczy coś w klatce (`_process`); prawdziwe zwłoki stoją wypieczone.

## Strój → plik modelu MPFB (te same, co operatorzy — w ciemności i z daleka czytelne jako „człowiek z drużyny”).
const OUTFITS := {
	"patrol": "res://art/char3d/mpfb/male_scav.glb",       # Patrol Siedem (1.1): mundur polowy
	"tech": "res://art/char3d/mpfb/male_hazmat.glb",        # obsługa radiostacji (1.2): kombinezon
	"miner": "res://art/char3d/mpfb/male_medic.glb",        # górnicy (1.3)
}
## Sprzęt na plecach i przy pasie (plecak, butla, torby): ciało opiera się na gruncie sobą, sprzęt chowa się pod podłogą — oparte na plecaku
## wisiało ok. 0,35 m nad ziemią. Z kamery gry (z przodu, lekko z góry) wierzch podłogi zasłania to, co pod nim.
const GEAR := ["backpack", "gear", "canteen", "medbag", "pouch_L", "pouch_R"]
const POSES := ["back", "side", "curl"]          ## ułożenia (wariant pozy z klipu upadku)
const DOWN_T := 1.65                             ## s: koniec klipu upadku (char_clips.gd „down”, `scrub`)
const MOD := Color(0.78, 0.76, 0.72)             ## wyblakły, przybrudzony strój (ten sam u Mimika-zwłok, M5)
const FLOOR_GAP := 0.004                          ## m: najniższy punkt skóry nad gruntem
const FIT_H := 22.0                              ## px: wysokość ciała jak Mimik (`fit` Mimika w SPEC)
const BODY_H := 1.581671                         ## m: wysokość siatki „body” modelu MPFB w spoczynku (male_scav)
const EYE_OFF := Vector3(0.12, 0.095, 0.033)     ## m: oczy względem kości głowy w spoczynku (jak SPEC `mimik` „eye_off”)
const EYE_R := 0.012
const SHINE := Color(0.78, 1.0, 0.82)            ## połysk oczu w snopie (blady, zielonkawy — jak u stojącego Mimika)
const BREATH_AFTER := 1.0                        ## s ciągłego snopu, po których „przyłapany” zaczyna oddychać
const BREATH_DEG := 8.0                          ## °: wychylenie klatki piersiowej
const BREATH_HZ := 0.3                           ## oddechy na sekundę (płytki, szybszy niż śpiący — wstrzymywał oddech)

var outfit := "patrol"
var pose_id := "back"
var searched := false
var seed_v := 0
var mimic := false                               ## Mimik-zwłoki (M5)
var mimic_lit := 0.0                             ## 0..1 snop latarki na nim (view3d z `view_info` Mimika)
var lit_w := 0.0                                 ## wygładzone `lit` (połysk oczu)
var breath_w := 0.0                              ## 0..1 waga oddechu (rośnie po BREATH_AFTER s światła)
var _lit_s := 0.0
var _breath_t := 0.0
var _chest_rest := Quaternion.IDENTITY           ## wypieczony obrót Spine2 (oddech dokłada się do niego)
var _mimic_eyes: Array = []

## Buduje model w stroju `out` i ułożeniu `pose`; `flip` = −1 leży głową w drugą stronę (i drugim bokiem do kamery).
func build(out: String, pose: String, s: int, flip := 1.0, is_mimic := false) -> bool:
	mimic = is_mimic
	outfit = out if OUTFITS.has(out) else "patrol"
	pose_id = pose if pose in POSES else "back"
	seed_v = s
	model_path = String(OUTFITS[outfit])
	hull_skip = PackedStringArray(GEAR)
	life_seed = s
	if not setup("corpse"):
		return false
	if _ap != null:
		_ap.queue_free()                                  # odtwarzacz z pliku GLB co klatkę wracałby szkielet do pozy z pliku
		_ap = null
	# skala wspólna dla strojów: ten sam człowiek MPFB; siatka „body” pod kombinezonem jest ucięta (0,68 m), więc dopasowanie z niej powiększało
	# technika ok. 2,3×
	_scale = FIT_H * PX / BODY_H
	_pivot.scale = Vector3.ONE * _scale
	_pivot.position.x = -_x0 * _scale
	rotation.y = PI if flip < 0.0 else 0.0                # głową w drugą stronę (obrót, nie lustro — lustro odwraca ściany siatki)
	for sm in _mats:
		(sm as ShaderMaterial).set_shader_parameter("mod", Vector4(MOD.r, MOD.g, MOD.b, 1.0))
	_bake()
	if mimic:
		for sd in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = EYE_R
			sph.height = EYE_R * 2.0
			sph.radial_segments = 8
			sph.rings = 4
			mi.mesh = sph
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			em.albedo_color = Color(SHINE, 0.0)
			mi.material_override = em
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			mi.set_meta("side", sd)
			_model.add_child(mi)
			_mimic_eyes.append(mi)
	set_process(mimic)
	return true

## Mimik-zwłoki: połysk oczu w snopie i oddech po BREATH_AFTER s ciągłego światła; w ciemności wstrzymuje oddech i gasi połysk.
func _process(delta: float) -> void:
	step_mimic(delta)

func step_mimic(delta: float) -> void:
	if not mimic or _sk == null:
		return
	lit_w = move_toward(lit_w, mimic_lit, delta / (0.3 if mimic_lit > lit_w else 0.6))
	_lit_s = _lit_s + delta if mimic_lit > 0.5 else 0.0
	breath_w = move_toward(breath_w, 1.0 if _lit_s >= BREATH_AFTER else 0.0, delta / (0.5 if _lit_s >= BREATH_AFTER else 1.5))
	_breath_t += delta
	var chest: int = _b["Spine2"]
	_sk.set_bone_pose_rotation(chest, _chest_rest)
	if breath_w > 0.001:
		var lr := _gp(_b["RightArm"]).origin - _gp(_b["LeftArm"]).origin
		_rot_world(chest, lr.normalized(), deg_to_rad(BREATH_DEG) * breath_w * (0.5 - 0.5 * cos(_breath_t * TAU * BREATH_HZ)))
	_place_mimic_eyes()

## Oczy przy kości głowy (przestrzeń szkieletu → węzeł modelu), widoczne tylko z połyskiem.
func _place_mimic_eyes() -> void:
	var hp := _gp(_b["Head"])
	var rest := _sk.get_bone_global_rest(_b["Head"])
	var rel := _transform_under(_sk, _model)
	for e in _mimic_eyes:
		var mi := e as MeshInstance3D
		var p := rest.origin + Vector3(EYE_OFF.x, EYE_OFF.y, EYE_OFF.z * float(mi.get_meta("side")))
		mi.position = rel * (hp * (rest.affine_inverse() * p))
		(mi.material_override as StandardMaterial3D).albedo_color = Color(SHINE, lit_w)
		mi.visible = lit_w > 0.02

## Przeszukane (M4): ułożenie zmienia się o szczegół, który widać z kamery gry.
func set_searched(on: bool) -> void:
	if on == searched or _sk == null:
		return
	searched = on
	_bake()

## Poza: koniec klipu upadku → wariant → oparcie na gruncie.
func _bake() -> void:
	_sk.reset_bone_poses()
	var anim := CharClips.clip("down", _sk)
	if anim != null:
		for t in anim.get_track_count():
			var bone := _sk.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
			if bone < 0:
				continue
			match anim.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					_sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(t, DOWN_T))
				Animation.TYPE_POSITION_3D:
					_sk.set_bone_pose_position(bone, anim.position_track_interpolate(t, DOWN_T))
	_variant()
	_settle()
	_sk.force_update_all_bone_transforms()
	_chest_rest = _sk.get_bone_pose_rotation(_b["Spine2"])

## Zbudowane przed wejściem do drzewa: skóra nie dostała zmiany pozy (szkielet odświeża ją dopiero w drzewie) — wypiekamy jeszcze raz.
func _ready() -> void:
	if _sk != null:
		_bake.call_deferred()

## Ułożenie wg `pose_id` i ziarna. Kierunki liczone w przestrzeni węzła (ciało wzdłuż osi x, głowa w stronę −x, kamera gry od +z) i przeliczane
## do przestrzeni szkieletu (`_to_sk`) — dziś różnią się tylko skalą, ale poza nie zależy od tego, jak armatura siedzi w pliku GLB. Klip upadku kończy się w różnym przetoczeniu,
## więc tułów obracamy wokół osi ciała do zadanego: „back” — przodem ku górze (+y), „side” — przetoczony na bok przodem ku kamerze,
## wierzchnia noga zgięta, „curl” — na boku, obie nogi podkulone. Ziarno dobiera kąty i odchyla głowę, żeby dwa ciała w tym samym ułożeniu
## nie były bliźniakami. Przeszukane: ręka odciągnięta od ciała w stronę kamery, głowa na drugą stronę.
func _variant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var roll := 0.0
	match pose_id:
		"back": roll = deg_to_rad(rng.randf_range(-8.0, 8.0))
		"side": roll = deg_to_rad(rng.randf_range(58.0, 72.0))
		"curl": roll = deg_to_rad(rng.randf_range(70.0, 82.0))
	_roll_to(roll)
	if pose_id == "side":
		_leg_to("Right", 55.0, -35.0)                            # wierzchnia noga zgięta przed ciałem
	elif pose_id == "curl":
		_leg_to("Right", 62.0, -48.0)
		_leg_to("Left", 48.0, -60.0)
	var turn := deg_to_rad(rng.randf_range(15.0, 35.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
	if searched:
		turn = -turn
		_arm_out("Right")
	_rot_world(_b["Head"], _to_sk(_body_axis()), turn)

## Kierunek z przestrzeni węzła do przestrzeni szkieletu (znormalizowany).
func _to_sk(v: Vector3) -> Vector3:
	return (_transform_under(_sk, self).basis.inverse() * v).normalized()

## Punkt kości w przestrzeni węzła.
func _node_pt(i: int) -> Vector3:
	return _transform_under(_sk, self) * _gp(i).origin

## Oś ciała w przestrzeni węzła: od bioder ku głowie.
func _body_axis() -> Vector3:
	return (_node_pt(_b["Head"]) - _node_pt(_b["Hips"])).normalized()

## Przód tułowia w przestrzeni węzła (prostopadły do osi ciała i linii barków).
func chest_forward() -> Vector3:
	var lr := _node_pt(_b["RightArm"]) - _node_pt(_b["LeftArm"])
	return _body_axis().cross(lr).normalized()

## Obraca całe ciało (biodra) wokół osi ciała tak, żeby przód tułowia był `roll` radianów od pionu (+y) w stronę kamery (+z).
func _roll_to(roll: float) -> void:
	var a := _body_axis()
	var f := chest_forward()
	var want := Vector3(0.0, cos(roll), sin(roll))
	f = (f - a * f.dot(a)).normalized()
	want = (want - a * want.dot(a)).normalized()
	var ang := f.signed_angle_to(want, a)
	if absf(ang) > 0.001:
		_rot_world(_b["Hips"], _to_sk(a), ang)

## Noga `side` na płasko w płaszczyźnie x–z węzła: udo pod kątem `thigh` od osi ciała (+x, ku stopom) w stronę kamery (+z), goleń `shin`
## stopni od osi.
func _leg_to(side: String, thigh: float, shin: float) -> void:
	var up: int = _b[side + "UpLeg"]
	var knee: int = _b[side + "Leg"]
	var foot: int = _b[side + "Foot"]
	var lens: Array = _leg_len[side]
	var t := _to_sk(Vector3(cos(deg_to_rad(thigh)), 0.0, sin(deg_to_rad(thigh))))
	_point_bone(up, knee, _gp(up).origin + t * float(lens[0]))
	var sh := _to_sk(Vector3(cos(deg_to_rad(shin)), 0.0, sin(deg_to_rad(shin))))
	_point_bone(knee, foot, _gp(knee).origin + sh * float(lens[1]))

## Ręka odciągnięta od ciała ku kamerze i lekko ku głowie (przeszukane: ktoś ją odsunął, żeby dostać się do kieszeni).
func _arm_out(side: String) -> void:
	var arm: int = _b[side + "Arm"]
	var fore: int = _b[side + "ForeArm"]
	var hand: int = _b[side + "Hand"]
	var lens: Array = _arm_len[side]
	_point_bone(arm, fore, _gp(arm).origin + _to_sk(Vector3(-0.25, 0.1, 0.96)) * float(lens[0]))
	_point_bone(fore, hand, _gp(fore).origin + _to_sk(Vector3(0.35, 0.05, 0.93)) * float(lens[1]))

## Ciało opiera się najniższym punktem skóry na gruncie (y = 0 węzła). Liczone w przestrzeni węzła — działa też przed wejściem do drzewa.
func _settle() -> void:
	_tilt.position = Vector3.ZERO
	var low := skin_lowest()
	if is_finite(low):
		_tilt.position.y = FLOOR_GAP - low

## Najniższy punkt otoczki skóry w bieżącej pozie, y w przestrzeni węzła (bez jego obrotu); INF bez otoczki.
func skin_lowest() -> float:
	var bb := skin_bounds()
	return INF if _hull.is_empty() else bb.position.y

## Obrys otoczki skóry w bieżącej pozie w przestrzeni węzła (bez jego obrotu); pusty AABB bez otoczki. Testy: wysokość i długość leżącego ciała.
func skin_bounds() -> AABB:
	if _hull.is_empty():
		_prepare_hull()
	var xf := _transform_under(_sk, self)
	var poses := {}
	var bb := AABB()
	var first := true
	for sample in _hull:
		var point := Vector3.ZERO
		for influence in sample:
			var bone: int = influence[0]
			if not poses.has(bone): poses[bone] = _gp(bone)
			point += (poses[bone] as Transform3D) * (influence[1] as Vector3) * float(influence[2])
		var p := xf * point
		if first:
			bb = AABB(p, Vector3.ZERO)
			first = false
		else:
			bb = bb.expand(p)
	return bb
