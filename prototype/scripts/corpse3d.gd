extends "res://scripts/enemy3d.gd"
## Zwłoki w świecie (MIMIC_PLAN.md M3): operator Patrolu Siedem, technik radiostacji albo górnik leżący na podłodze — ten sam model i
## dopasowanie co Mimik (PROP_SPEC `corpse` w enemy3d.gd, strój wybiera `model_path`), żeby Mimik udający zwłoki (M5) wyglądał tak samo.
## Poza leżenia jest wypiekana raz przy budowie: koniec klipu upadku gracza (`down`, char_clips.gd) plus wariant ułożenia z ziarna
## i opadanie pod ciężarem (`_drape`: tułów, głowa i kończyny kładą się na gruncie, zamiast wisieć w pozie z klipu), potem szkielet stoi — bez klipów, IK i oddechu w każdej klatce, koszt zbliżony do rekwizytu. Ciało opiera się najniższym punktem
## otoczki skóry na gruncie. Przeszukane (M4) zmienia ułożenie o szczegół: ręka odsunięta od ciała, głowa na drugą stronę.
##
## Mimik-zwłoki (M5, `build(…, mimic = true)`): ta sama poza, strój i materiał; różnią go sygnały: brak plamy pod ciałem (view3d), oczy
## otwarte — w snopie latarki łapią połysk (`mimic_lit` z widoku, jak u stojącego Mimika), a po BREATH_AFTER s ciągłego światła klatka
## piersiowa zaczyna się unosić. Tylko on liczy coś w klatce (`_process`); prawdziwe zwłoki stoją wypieczone.
## Echo krzyku (M8, `mimic_echo` 1 → 0): ciało drga — klatka i głowa szarpią się kilka razy z gasnącą siłą, gdy spod niego dobiega echo.
##
## Demaskacja Mimika-zwłok (M7, `rise`): ciało wstaje „wstecz” — klip upadku od końca do początku, bez podparcia rąk, z łukiem pleców;
## ułożenie (przetoczenie, podkulone nogi) gaśnie w pierwszej części ruchu. W tym czasie przemiana jak u stojącego (przedramiona, nakładka
## materiału, żółte oczy). Po RISE_S widok przechodzi na model wroga, który stoi w miejscu stóp zwłok.
##
## Mimik jako powalony kolega (M9, `build("res://…glb", "downed", …, faded = false)`): model postaci kolegi, poza to czysty koniec klipu upadku
## (jak u powalonego gracza — bez przetoczenia i skrętu głowy) i bez wyblaknięcia stroju; sygnały, drgnięcie i wstawanie jak u Mimika-zwłok.

## Strój → plik modelu MPFB (te same, co operatorzy — w ciemności i z daleka czytelne jako „człowiek z drużyny”).
const OUTFITS := {
	"patrol": "res://art/char3d/mpfb/male_scav.glb",       # Patrol Siedem (1.1): mundur polowy
	"tech": "res://art/char3d/mpfb/male_hazmat.glb",        # obsługa radiostacji (1.2): kombinezon
	"miner": "res://art/char3d/mpfb/male_medic.glb",        # górnicy (1.3)
}
## Sprzęt na plecach i przy pasie (plecak, butla, torby): ciało opiera się na gruncie sobą, sprzęt chowa się pod podłogą — oparte na plecaku
## wisiało ok. 0,35 m nad ziemią. Z kamery gry (z przodu, lekko z góry) wierzch podłogi zasłania to, co pod nim.
const GEAR := ["backpack", "gear", "canteen", "medbag", "pouch_L", "pouch_R"]
const POSES := ["back", "side", "curl", "downed"]  ## ułożenia (wariant pozy z klipu upadku; „downed” — sam klip, jak powalony gracz, M9)
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
const ECHO_DEG := 9.0                            ## °: drgnięcie klatki piersiowej przy echu krzyku (M8)
const ECHO_HEAD_DEG := 16.0                      ## °: szarpnięcie głowy przy echu
const ECHO_JERKS := 2.5                          ## szarpnięcia w czasie drgnięcia (enemy_mimic.gd ECHO_VIEW_S)

var outfit := "patrol"
var pose_id := "back"
var searched := false
var seed_v := 0
var mimic := false                               ## Mimik-zwłoki (M5)
var mimic_lit := 0.0                             ## 0..1 snop latarki na nim (view3d z `view_info` Mimika)
var mimic_echo := 0.0                            ## 1 → 0 drgnięcie przy echu krzyku (view3d z `view_info` Mimika, M8)
var rise_u := -1.0                               ## 0..1 postęp wstawania (M7); < 0 = leży
const RISE_ARCH := 24.0                          ## °: łuk pleców w połowie wstawania
const RISE_VARIANT := 0.3                        ## ułamek wstawania, w którym gaśnie ułożenie (przetoczenie, nogi)
var _lie_rot := {}                               ## kość → obrót w wypieczonej pozie (początek wstawania)
var _rise_arc := PackedFloat32Array()            ## droga głowy i bioder od końca klipu upadku (0..1) w RISE_SAMPLES krokach — równe tempo wstawania
const RISE_SAMPLES := 48
var _lie_pos := {}
var lit_w := 0.0                                 ## wygładzone `lit` (połysk oczu)
var breath_w := 0.0                              ## 0..1 waga oddechu (rośnie po BREATH_AFTER s światła)
var _lit_s := 0.0
var _breath_t := 0.0
var _chest_rest := Quaternion.IDENTITY           ## wypieczony obrót Spine2 (oddech dokłada się do niego)
var _mimic_eyes: Array = []
## Opadanie pod ciężarem (`_drape`): [kość, największy obrót w stopniach, staw zawiasowy (łokieć, kolano — zgięcie tylko w jedną stronę),
## część skóry bez kończyn (tułów: ręce opadają osobno)]. Od tułowia na zewnątrz — rodzic leży, zanim opadnie dziecko.
const DRAPE := [
	["Spine", 18.0, false, true], ["Spine1", 18.0, false, true], ["Spine2", 18.0, false, true], ["Neck", 40.0, false, false], ["Head", 30.0, false, false],
	["LeftArm", 120.0, false, false], ["LeftForeArm", 140.0, true, false], ["LeftHand", 60.0, false, false],
	["RightArm", 120.0, false, false], ["RightForeArm", 140.0, true, false], ["RightHand", 60.0, false, false],
	["LeftUpLeg", 85.0, false, false], ["LeftLeg", 150.0, true, false], ["LeftFoot", 45.0, false, false],
	["RightUpLeg", 85.0, false, false], ["RightLeg", 150.0, true, false], ["RightFoot", 45.0, false, false],
]
const DRAPE_PASSES := 2                          ## przebiegi opadania
const UNPROP_TRIES := 3                          ## próby zdjęcia ciała z podpierającej kończyny (`_unprop`)
const DRAPE_STEP := 4.0                          ## °: krok szukania styku z gruntem (potem połowienie)
const DRAPE_TOL := 0.006                         ## m: styk z gruntem (najniższy punkt części skóry nad FLOOR_GAP)
const BEND_MAX := {"ForeArm": 145.0, "Leg": 150.0}   ## °: największe zgięcie łokcia i kolana (0 = prosto)
const UNBEND_MAX := 35.0                         ## °: o ile ciężar rozprostowuje łokieć albo kolano (sztywnieje — noga w bok nie prostuje się do końca)
var _drape_parts := {}                           ## kość → indeksy próbek otoczki jej części skóry (cache na model)

## Buduje model w stroju `out` (klucz OUTFITS albo ścieżka `res://…glb` — model gracza, M9) i ułożeniu `pose`; `flip` = −1 leży głową
## w drugą stronę (i drugim bokiem do kamery); `faded` — wyblakły, przybrudzony strój (zwłoki), bez niego świeży (powalony kolega).
func build(out: String, pose: String, s: int, flip := 1.0, is_mimic := false, faded := true) -> bool:
	mimic = is_mimic
	var own := out.begins_with("res://") and ResourceLoader.exists(out)
	outfit = out if OUTFITS.has(out) or own else "patrol"
	pose_id = pose if pose in POSES else "back"
	seed_v = s
	model_path = out if own else String(OUTFITS[outfit])
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
	if faded:
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
	if mimic:
		_prepare_rise()
		_bake()
	set_process(mimic)
	return true

## Mimik-zwłoki: połysk oczu w snopie i oddech po BREATH_AFTER s ciągłego światła; w ciemności wstrzymuje oddech i gasi połysk.
func _process(delta: float) -> void:
	step_mimic(delta)

func step_mimic(delta: float) -> void:
	if not mimic or _sk == null or rise_u >= 0.0:
		return
	lit_w = move_toward(lit_w, mimic_lit, delta / (0.3 if mimic_lit > lit_w else 0.6))
	_lit_s = _lit_s + delta if mimic_lit > 0.5 else 0.0
	breath_w = move_toward(breath_w, 1.0 if _lit_s >= BREATH_AFTER else 0.0, delta / (0.5 if _lit_s >= BREATH_AFTER else 1.5))
	_breath_t += delta
	var chest: int = _b["Spine2"]
	var head: int = _b["Head"]
	_sk.set_bone_pose_rotation(chest, _chest_rest)
	_sk.set_bone_pose_rotation(head, _lie_rot.get(head, _sk.get_bone_pose_rotation(head)))
	var lr := (_gp(_b["RightArm"]).origin - _gp(_b["LeftArm"]).origin).normalized()
	if breath_w > 0.001:
		_rot_world(chest, lr, deg_to_rad(BREATH_DEG) * breath_w * (0.5 - 0.5 * cos(_breath_t * TAU * BREATH_HZ)))
	if mimic_echo > 0.001:
		var jerk := echo_jerk(mimic_echo)
		_rot_world(chest, lr, deg_to_rad(ECHO_DEG) * jerk)
		_rot_world(head, _to_sk(_body_axis()), deg_to_rad(ECHO_HEAD_DEG) * jerk)
	_place_mimic_eyes()

## Drgnięcie przy echu (−1..1): `w` 1 → 0 w czasie drgnięcia; szarpnięcia gasną z kwadratem wagi.
static func echo_jerk(w: float) -> float:
	return w * w * sin((1.0 - w) * TAU * ECHO_JERKS)

## Oczy przy kości głowy (przestrzeń szkieletu → węzeł modelu), widoczne tylko z połyskiem.
func _place_mimic_eyes(shine := true) -> void:
	var hp := _gp(_b["Head"])
	var rest := _sk.get_bone_global_rest(_b["Head"])
	var rel := _transform_under(_sk, _model)
	for e in _mimic_eyes:
		var mi := e as MeshInstance3D
		var p := rest.origin + Vector3(EYE_OFF.x, EYE_OFF.y, EYE_OFF.z * float(mi.get_meta("side")))
		mi.position = rel * (hp * (rest.affine_inverse() * p))
		if shine:
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
	rise_u = -1.0
	_sk.reset_bone_poses()
	_down_at(DOWN_T)
	_variant()
	_settle()
	if pose_id != "downed":
		_drape()                                                  # powalony gracz (M9) leży jak w char3d.gd — Mimik musi wyglądać tak samo
	_sk.force_update_all_bone_transforms()
	_chest_rest = _sk.get_bone_pose_rotation(_b["Spine2"])
	for i in _sk.get_bone_count():
		_lie_rot[i] = _sk.get_bone_pose_rotation(i)
		_lie_pos[i] = _sk.get_bone_pose_position(i)

## Poza z klipu upadku gracza w chwili `t` (od zresetowanej pozy).
func _down_at(t: float) -> void:
	var anim := CharClips.clip("down", _sk)
	if anim == null:
		return
	for k in anim.get_track_count():
		var bone := _sk.find_bone(String(anim.track_get_path(k).get_concatenated_subnames()))
		if bone < 0:
			continue
		match anim.track_get_type(k):
			Animation.TYPE_ROTATION_3D:
				_sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(k, t))
			Animation.TYPE_POSITION_3D:
				_sk.set_bone_pose_position(bone, anim.position_track_interpolate(k, t))

## Klip upadku ma szybkie odcinki (sam upadek), więc wstawanie w równym czasie klipu szarpało: postęp `rise` idzie po drodze, jaką
## w klipie od końca przebywają głowa i biodra (po oparciu na gruncie), a nie po czasie.
func _prepare_rise() -> void:
	_rise_arc.clear()
	var prev: Array = []
	var acc := 0.0
	for i in RISE_SAMPLES + 1:
		_sk.reset_bone_poses()
		_down_at(DOWN_T * (1.0 - float(i) / RISE_SAMPLES))
		_settle()
		_sk.force_update_all_bone_transforms()
		var pts := [_node_pt(_b["Head"]), _node_pt(_b["Hips"])]
		if not prev.is_empty():
			acc += (pts[0] as Vector3).distance_to(prev[0]) + (pts[1] as Vector3).distance_to(prev[1])
		prev = pts
		_rise_arc.append(acc)
	if acc > 0.0:
		for i in _rise_arc.size():
			_rise_arc[i] /= acc

## Czas klipu upadku dla postępu drogi `k` (0 = koniec klipu, leży; 1 = początek, stoi).
func _rise_time(k: float) -> float:
	var n := _rise_arc.size()
	if n < 2:
		return DOWN_T * (1.0 - k)
	for i in n - 1:
		if k <= _rise_arc[i + 1] or i == n - 2:
			var span := maxf(_rise_arc[i + 1] - _rise_arc[i], 0.0001)
			var f := clampf((k - _rise_arc[i]) / span, 0.0, 1.0)
			return DOWN_T * (1.0 - (float(i) + f) / (n - 1))
	return 0.0

## Wstawanie Mimika-zwłok (M7): `u` 0..1 → klip upadku od końca, ułożenie gaśnie do RISE_VARIANT, łuk pleców, przemiana `since` s od demaskacji.
func rise(u: float, since: float) -> void:
	if _sk == null:
		return
	rise_u = clampf(u, 0.0, 1.0)
	var k := smoothstep(0.0, 1.0, rise_u)
	_sk.reset_bone_poses()
	_down_at(_rise_time(k))
	var lw := 1.0 - smoothstep(0.0, RISE_VARIANT, rise_u)
	if lw > 0.0 and not _lie_rot.is_empty():
		for i in _lie_rot:
			_sk.set_bone_pose_rotation(i, _sk.get_bone_pose_rotation(i).slerp(_lie_rot[i], lw))
			_sk.set_bone_pose_position(i, _sk.get_bone_pose_position(i).lerp(_lie_pos[i], lw))
	var lr := (_gp(_b["RightArm"]).origin - _gp(_b["LeftArm"]).origin).normalized()
	var arch := deg_to_rad(RISE_ARCH) * sin(PI * rise_u)
	_rot_world(_b["Spine1"], lr, -arch * 0.5)                # pierś wypchnięta, głowa w tył — ciało ciągnie się w górę od mostka
	_rot_world(_b["Spine2"], lr, -arch * 0.5)
	_rot_world(_b["Head"], lr, -arch * 0.6)
	var w := morph_weight(since)
	_morph_bones(w)
	morph_overlay(w)
	_settle()
	_sk.force_update_all_bone_transforms()
	for e in _mimic_eyes:
		(e.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.8, 0.25).lerp(Color(1.0, 0.96, 0.62), w)
		e.scale = Vector3.ONE * (1.0 + MORPH_EYE * w)
		e.visible = true
	_place_mimic_eyes(false)

## Koniec wstawania (widok przeszedł na model wroga) albo restart: znów leży bez przemiany.
func end_rise() -> void:
	morph_overlay(0.0)
	for e in _mimic_eyes:
		e.scale = Vector3.ONE
	_bake()

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
	if pose_id == "downed":
		return                                                    # powalony gracz leży w samym końcu klipu upadku (char3d.gd)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var roll := 0.0
	match pose_id:
		"back": roll = deg_to_rad(rng.randf_range(-8.0, 8.0))
		"side": roll = deg_to_rad(rng.randf_range(58.0, 72.0))
		"curl": roll = deg_to_rad(rng.randf_range(70.0, 82.0))
	_roll_to(roll)
	if pose_id == "back":
		for side in ["Left", "Right"]:
			_arm_lay(side, rng)                                   # klip kończy się z dłońmi przy twarzy („bokser”) — ręce bezwładnie na ziemi
			_leg_out(side, deg_to_rad(rng.randf_range(20.0, 40.0)))  # stopy opadają na zewnątrz, nie stoją palcami w górę
	if pose_id == "side":
		_leg_to("Right", 55.0, -35.0)                            # wierzchnia noga zgięta przed ciałem
	elif pose_id == "curl":
		_leg_to("Right", 62.0, -48.0)
		_leg_to("Left", 48.0, -60.0)
	var turn := deg_to_rad(rng.randf_range(15.0, 35.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
	if searched:
		turn = -turn
		var top := "Right"
		if pose_id != "back" and _node_pt(_b["LeftArm"]).y > _node_pt(_b["RightArm"]).y:
			top = "Left"                                          # na boku odsunięta ręka to wierzchnia — przygniecionej nikt nie wyciągnie
		_arm_out(top)
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

## Ręka leżącego na plecach bezwładnie na ziemi: ramię odchylone od tułowia o 15–70° (od osi ciała ku stopom na zewnątrz), łokieć zgięty
## 5–45° w płaszczyźnie gruntu; kąty z ziarna, osobno dla każdej ręki. Wysokość dopasowuje potem `_drape`.
func _arm_lay(side: String, rng: RandomNumberGenerator) -> void:
	var arm: int = _b[side + "Arm"]
	var fore: int = _b[side + "ForeArm"]
	var hand: int = _b[side + "Hand"]
	var lens: Array = _arm_len[side]
	var feet := -_body_axis()
	feet = Vector3(feet.x, 0.0, feet.z).normalized()
	var o := _node_pt(arm) - _node_pt(_b["Spine2"])
	var out := Vector3(o.x, 0.0, o.z)
	out = (out - feet * out.dot(feet)).normalized()
	var a := deg_to_rad(rng.randf_range(15.0, 70.0))
	var bend := deg_to_rad(rng.randf_range(5.0, 45.0)) * (1.0 if rng.randf() < 0.6 else -1.0)
	var u := (feet * cos(a) + out * sin(a) + Vector3.DOWN * 0.08).normalized()
	var f := (feet * cos(a + bend) + out * sin(a + bend) + Vector3.DOWN * 0.04).normalized()
	_point_bone(arm, fore, _gp(arm).origin + _to_sk(u) * float(lens[0]))
	_point_bone(fore, hand, _gp(fore).origin + _to_sk(f) * float(lens[1]))

## Noga wyprostowana w kolanie i obrócona wokół własnej osi (biodro → kolano) tak, że palce stopy uciekają od osi ciała — u bezwładnego
## leżącego na plecach stopy opadają na boki.
func _leg_out(side: String, ang: float) -> void:
	var up: int = _b[side + "UpLeg"]
	var knee: int = _b[side + "Leg"]
	var toe := _sk.find_bone(PRE + side + "ToeBase")
	if toe < 0:
		return
	var ax := _node_pt(knee) - _node_pt(up)
	if ax.length() < 0.001:
		return
	ax = ax.normalized()
	var hips := _node_pt(_b["Hips"])
	var body := _body_axis()
	var lateral := func() -> float:
		var v := _node_pt(toe) - hips
		return (v - body * v.dot(body)).length()
	var foot: int = _b[side + "Foot"]
	_point_bone(knee, foot, _gp(knee).origin + _to_sk(ax) * float(_leg_len[side][1]))   # kolano prosto: przy zgiętym obrót uda zadzierał goleń
	_sk.force_update_all_bone_transforms()
	var before: float = lateral.call()
	_rot_world(up, _to_sk(ax), ang)
	if float(lateral.call()) < before:
		_rot_world(up, _to_sk(ax), -2.0 * ang)              # w drugą stronę — to była rotacja do środka

## Ręka odciągnięta od ciała ku kamerze i lekko ku głowie (przeszukane: ktoś ją odsunął, żeby dostać się do kieszeni).
func _arm_out(side: String) -> void:
	var arm: int = _b[side + "Arm"]
	var fore: int = _b[side + "ForeArm"]
	var hand: int = _b[side + "Hand"]
	var lens: Array = _arm_len[side]
	_point_bone(arm, fore, _gp(arm).origin + _to_sk(Vector3(-0.25, 0.1, 0.96)) * float(lens[0]))
	_point_bone(fore, hand, _gp(fore).origin + _to_sk(Vector3(0.35, 0.05, 0.93)) * float(lens[1]))

# ---------------------------------------------------------------- opadanie pod ciężarem

## Klip upadku kończy się w pozie żywego człowieka w chwili zderzenia z ziemią: głowa uniesiona, ręce i nogi w powietrzu (na plecach dłoń
## 0,3 m, na boku wierzchni łokieć 0,8 m nad gruntem) — zwłoki wyglądały jak manekin. Bez fizyki: po kolei (DRAPE) każda kość obraca się
## wokół swojego stawu w dół, aż najniższy punkt jej części skóry dotknie gruntu, najwyżej o zadany kąt; łokieć i kolano tylko na zawiasie
## i w granicach zgięcia. Część, która przy tym weszła pod grunt (ręka pod opadającym tułowiem), wraca na jego powierzchnię.
func _drape() -> void:
	if _hull.is_empty():
		_prepare_hull()
	if _hull.is_empty():
		return
	_prepare_drape_parts()
	for _pass in DRAPE_PASSES:
		_drape_pass()
	_sk.force_update_all_bone_transforms()
	for _i in UNPROP_TRIES:
		if not _unprop():
			break
		_sk.force_update_all_bone_transforms()
		_settle()
		_sk.force_update_all_bone_transforms()
		_drape_pass()
		_sk.force_update_all_bone_transforms()
	_sk.force_update_all_bone_transforms()
	_settle()

## Kończyna niżej niż tułów — wbita w grunt albo podpierająca go jak statyw (dolny łokieć pod ciałem na boku: po oparciu tułów wisiał
## 0,3 m nad gruntem): odchyla się w barku / biodrze do poziomu tułowia, który potem opada. Zwraca true, gdy coś odchylił.
func _unprop() -> bool:
	var torso := _sk.find_bone(PRE + "Spine")
	if torso < 0 or not _drape_parts.has(torso):
		return false
	var t_low := _part_low(torso)
	var moved := false
	for root_name in ["LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"]:
		var b := _sk.find_bone(PRE + root_name)
		if b < 0 or not _drape_parts.has(b):
			continue
		_sk.force_update_all_bone_transforms()
		if _part_low(b) < t_low - 0.03:
			_drop(b, deg_to_rad(120.0 if root_name.ends_with("Arm") else 60.0), false, -1, Vector3.ZERO, t_low)
			moved = true
	return moved

## Jeden przebieg opadania po DRAPE (drugi poprawia kości, które pierwszy położył na części, która potem opadła).
func _drape_pass() -> void:
	for d in DRAPE:
		var b := _sk.find_bone(PRE + String(d[0]))
		if b >= 0 and _drape_parts.has(b):
			_sk.force_update_all_bone_transforms()
			if String(d[0]).ends_with("Hand"):
				_hand_flat(String(d[0]).trim_suffix("Hand"))
				_sk.force_update_all_bone_transforms()
			_drop(b, deg_to_rad(float(d[1])), bool(d[2]))
			if bool(d[2]):
				_sk.force_update_all_bone_transforms()
				if absf(_part_low(b) - FLOOR_GAP) > DRAPE_TOL:
					# zawias nie sięga gruntu albo nie wyciąga części spod niego (odsunięta ręka przeszukanego): obrót w barku / biodrze
					# wokół osi ramienia / uda przetacza zgiętą część na ziemię
					var par := _sk.get_bone_parent(b)
					var seg := (_node_pt(b) - _node_pt(par)).normalized()
					var twist := 90.0 if String(d[0]).ends_with("ForeArm") else 45.0
					_drop(par, deg_to_rad(twist), false, b, seg)
					_sk.force_update_all_bone_transforms()
					_drop(b, deg_to_rad(float(d[1])), true)

## Dłoń płasko: nadgarstek prosto jak przedramię, potem obrót wokół osi dłoni, aż linia kostek (palec wskazujący → mały) jest pozioma —
## w klipie dłonie stały na krawędzi z palcami w górę (jak przy machaniu).
func _hand_flat(side: String) -> void:
	var hand := _sk.find_bone(PRE + side + "Hand")
	var fore := _sk.find_bone(PRE + side + "ForeArm")
	var mid := _sk.find_bone(PRE + side + "HandMiddle1")
	var idx := _sk.find_bone(PRE + side + "HandIndex1")
	var pky := _sk.find_bone(PRE + side + "HandPinky1")
	if hand < 0 or fore < 0 or mid < 0 or idx < 0 or pky < 0:
		return
	var g := _gp(hand).origin
	_point_bone(hand, mid, g + (g - _gp(fore).origin).normalized() * (_gp(mid).origin - g).length())
	_sk.force_update_all_bone_transforms()
	var ax := (_node_pt(mid) - _node_pt(hand)).normalized()
	var w := _node_pt(pky) - _node_pt(idx)
	w = (w - ax * w.dot(ax))
	var h := ax.cross(Vector3.UP)
	if w.length() < 0.0001 or h.length() < 0.05:
		return
	h = h.normalized()
	if h.dot(w) < 0.0:
		h = -h
	var ang := w.normalized().signed_angle_to(h, ax)
	if absf(ang) > 0.001:
		_rot_world(hand, _to_sk(ax), ang)

## Próbki otoczki przypisane do kości o największej wadze; część kości = ona i potomkowie (tułów bez rąk — od barku w dół opadają osobno).
func _prepare_drape_parts() -> void:
	if not _drape_parts.is_empty():
		return
	var owner := PackedInt32Array()
	for sample in _hull:
		var best := -1
		var bw := -1.0
		for inf in sample:
			if float(inf[2]) > bw:
				bw = float(inf[2])
				best = int(inf[0])
		owner.append(best)
	var arms := PackedInt32Array()
	for side in ["Left", "Right"]:
		var a := _sk.find_bone(PRE + side + "Arm")
		if a >= 0:
			arms.append(a)
	for d in DRAPE:
		var b := _sk.find_bone(PRE + String(d[0]))
		if b < 0:
			continue
		var idx := PackedInt32Array()
		for i in owner.size():
			var o := owner[i]
			if o >= 0 and _under(o, b) and not (bool(d[3]) and _under_any(o, arms)):
				idx.append(i)
		if not idx.is_empty():
			_drape_parts[b] = idx

func _under(bone: int, root_bone: int) -> bool:
	var x := bone
	while x >= 0:
		if x == root_bone:
			return true
		x = _sk.get_bone_parent(x)
	return false

func _under_any(bone: int, roots: PackedInt32Array) -> bool:
	for r in roots:
		if _under(bone, r):
			return true
	return false

## Najniższy punkt części skóry kości `b` (przestrzeń węzła).
func _part_low(b: int) -> float:
	var low := INF
	for q in _part_points(b):
		low = minf(low, q.y)
	return low

## Punkty części skóry kości `b` w przestrzeni węzła (bieżąca poza).
func _part_points(b: int) -> PackedVector3Array:
	var xf := _transform_under(_sk, self)
	var poses := {}
	var out := PackedVector3Array()
	for i in _drape_parts[b]:
		var point := Vector3.ZERO
		for inf in _hull[i]:
			var bone: int = inf[0]
			if not poses.has(bone):
				poses[bone] = _gp(bone)
			point += (poses[bone] as Transform3D) * (inf[1] as Vector3) * float(inf[2])
		out.append(xf * point)
	return out

## Obrót kości `b` wokół osi przez jej staw (przestrzeń węzła) tak, żeby najniższy punkt jej części leżał na gruncie: opuszcza wiszącą,
## podnosi wbitą w grunt; najwyżej `lim`. Wysokość punktu przy obrocie o θ: A + B·cos θ + C·sin θ (Rodrigues), bez przeliczania szkieletu.
func _drop(b: int, lim: float, hinge: bool, part := -1, axis := Vector3.ZERO, floor_y := FLOOR_GAP) -> void:
	var pts := _part_points(part if part >= 0 else b)
	if pts.is_empty():
		return
	var piv := _node_pt(b)
	var low := INF
	var c := Vector3.ZERO
	for q in pts:
		low = minf(low, q.y)
		c += q
	c /= float(pts.size())
	var raise := low < floor_y - DRAPE_TOL
	if absf(low - floor_y) <= DRAPE_TOL:
		return
	var k := axis if axis != Vector3.ZERO else _drop_axis(b, piv, c, hinge)
	if k == Vector3.ZERO:
		return
	var coef := PackedVector3Array()                 # (A, B, C) na punkt
	for q in pts:
		coef.append(_rot_coef(q, piv, k))
	var cc := _rot_coef(c, piv, k)
	var dir := 1.0
	var span := lim
	if raise:
		# wbita w grunt: w stronę, w którą najniższy punkt rośnie
		dir = 1.0 if _low_at(coef, 0.05) >= _low_at(coef, -0.05) else -1.0
	else:
		# wisząca: jak pod ciężarem — w stronę, w którą opada środek części, najwyżej do zwisu (środek najniżej)
		var th := atan2(-cc.z, -cc.y)
		if absf(th) < 0.002:
			return
		dir = signf(th)
		span = minf(absf(th), lim)
		if hinge and dir < 0.0:
			span = minf(span, deg_to_rad(UNBEND_MAX))         # oś zawiasu: + zgina, − prostuje
	var best := 0.0
	var prev := 0.0
	var t := 0.0
	while t < span:
		t = minf(t + deg_to_rad(DRAPE_STEP), span)
		if hinge and not _bend_ok(b, k, dir * t):
			break
		var y := _low_at(coef, dir * t)
		if (y <= floor_y and not raise) or (y >= floor_y and raise):
			var lo := prev
			var hi := t
			for _i in 8:
				var mid := (lo + hi) * 0.5
				if (_low_at(coef, dir * mid) <= floor_y) != raise:
					hi = mid
				else:
					lo = mid
			best = lo if not raise else hi
			prev = -1.0
			break
		prev = t
	if prev >= 0.0:
		best = prev                                   # bez styku: do zwisu, granicy stawu albo zgięcia
	if best > 0.0001:
		_rot_world(b, _to_sk(k), dir * best)

## Wysokość punktu `q` obróconego o θ wokół osi `k` przez `piv`: A + B·cos θ + C·sin θ → Vector3(A, B, C).
static func _rot_coef(q: Vector3, piv: Vector3, k: Vector3) -> Vector3:
	var v := q - piv
	var par := k * v.dot(k)
	var perp := v - par
	return Vector3(piv.y + par.y, perp.y, k.cross(perp).y)

func _low_at(coef: PackedVector3Array, th: float) -> float:
	var cs := cos(th)
	var sn := sin(th)
	var low := INF
	for e in coef:
		low = minf(low, e.x + e.y * cs + e.z * sn)
	return low

## Oś opadania (przestrzeń węzła). Staw kulisty: pozioma, prostopadła do kierunku od stawu do środka części — część pada „przed siebie”;
## część pionowa pada na zewnątrz ciała. Zawias (łokieć, kolano): oś zgięcia z bieżącej pozy (rodzic × kość); prosta kończyna — oś
## prostopadła do niej i do pionu.
func _drop_axis(b: int, piv: Vector3, c: Vector3, hinge: bool) -> Vector3:
	var d := c - piv
	if hinge:
		var par := _sk.get_bone_parent(b)
		var up_dir := (piv - _node_pt(par)).normalized()
		var lo_dir := d.normalized()
		var ax := up_dir.cross(lo_dir)
		if ax.length() < 0.05:
			ax = lo_dir.cross(Vector3.UP)
		return ax.normalized() if ax.length() > 0.001 else Vector3.ZERO
	var h := Vector3(d.x, 0.0, d.z)
	if h.length() < 0.15 * d.length():
		var out := piv - _node_pt(_b["Hips"])
		h = Vector3(out.x, 0.0, out.z)
		if h.length() < 0.001:
			h = Vector3(0.0, 0.0, 1.0)                # ku kamerze
	return Vector3.UP.cross(h.normalized()).normalized()

## Czy obrót zawiasu `b` o `th` wokół `k` zostawia zgięcie w granicach (0 = prosto … BEND_MAX), bez przeprostu w drugą stronę.
func _bend_ok(b: int, k: Vector3, th: float) -> bool:
	var par := _sk.get_bone_parent(b)
	var piv := _node_pt(b)
	var up_dir := (piv - _node_pt(par)).normalized()
	var ch := _first_child(b)
	if ch < 0:
		return true
	var lo_dir := (_node_pt(ch) - piv).normalized().rotated(k, th)
	var flex := up_dir.cross(lo_dir).dot(k)            # > 0: zgięcie w stronę osi zawiasu z bieżącej pozy
	var bend := rad_to_deg(up_dir.angle_to(lo_dir))
	var key := "ForeArm" if String(_sk.get_bone_name(b)).ends_with("ForeArm") else "Leg"
	return flex >= -0.02 and bend <= float(BEND_MAX[key])

func _first_child(b: int) -> int:
	var ch := _sk.get_bone_children(b)
	return ch[0] if ch.size() > 0 else -1

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
