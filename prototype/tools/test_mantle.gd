extends SceneTree
## Podciąganie na pomost (STEPS_PLAN.md S3, char3d.gd `mantle_h` / `mantle_z`): skok jak w player.gd (−275 px/s, grawitacja 900, przy opadaniu ×1,35)
## spod pomostu, którego wierzch jest 30 px (krata z STEPS w 1.3) albo 32 px (deski, 2 kafle) nad podłogą. Sprawdza, w obie strony patrzenia:
##  1. gdy ciało zachodzi na pomost w pionie (głowa nad spodem pokładu, stopy pod wierzchem), model stoi przed przednią krawędzią:
##     mantle_z ≥ MANTLE_EDGE_Z + 0,2 (bark 0,2 m od osi);
##  2. wolna (lewa) dłoń leży na przedniej krawędzi, gdy wierzch jest w zasięgu barku (1,0–1,8 m nad stopami): wysokość ±0,12 m; w głębi ±0,05 m
##     patrząc w prawo, a patrząc w lewo lewa ręka sięga w poprzek ciała do krawędzi za plecami i brakuje jej zasięgu (do DZ_ACROSS, z kamery niewidoczne);
##  3. model wraca nad pokład: mantle_z = 0 najpóźniej 0,1 s po lądowaniu;
##  4. krótki skok (puszczony przycisk): stopy nie mijają wierzchu, a model nie cofa się w pomost, póki ciało na niego zachodzi; po powrocie na ziemię z = 0.
## godot --headless --path prototype -s tools/test_mantle.gd      → ma wypisać [MANTLE] PASS
const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const HEAD := 1.85                           ## m: czubek głowy nad stopami
const DECK_T := 0.25                         ## m: grubość pokładu pod wierzchem
const DZ_ACROSS := 0.4                       ## m: dopuszczalny brak zasięgu w głębi dla ręki sięgającej w poprzek ciała (zwrot w lewo) — dłoń
##                                             zostaje na wysokości krawędzi przed piersią; z kamery głębi nie widać
var _c: Node2D
var _fail := 0

func _initialize() -> void:
	_c = Char3D.new()
	root.add_child(_c)
	if not _c.setup("male_scav", "m83"):
		print("[MANTLE] FAIL: brak modelu postaci")
		quit(1)

func check(label: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("[MANTLE] %s  %s" % ["PASS" if ok else "FAIL", label])

func _frame(anim: String, side: float, h: float) -> void:
	_c.mantle_h = h
	_c.update(DT, anim, side, Vector2(side, 0.0), 0.0)

## Skok spod pomostu: wierzch `top_px` nad podłogą; `cut` = przycisk puszczony po tylu sekundach (krótki skok, jak JUMP_CUT w player.gd).
## Zwraca [najmniejsze mantle_z przy zachodzeniu na pomost, najgorszy błąd wysokości dłoni (m), mantle_z 0,1 s po lądowaniu, czy stopy minęły wierzch,
## najgorszy błąd głębi dłoni (m)].
func _jump(side: float, top_px: float, cut := -1.0) -> Array:
	for i in 40:
		_frame("idle", side, NAN)
	var y := 0.0                                  # px w górę od podłogi
	var vy := 275.0
	var t := 0.0
	var latched := true
	var landed_t := -1.0
	var min_z := INF
	var hand_err := 0.0
	var hand_dz := 0.0
	var over := false
	var on_deck := false
	while t < 1.2:
		t += DT
		if cut >= 0.0 and t >= cut and vy > 0.4 * 275.0:
			vy = 0.4 * 275.0
		vy -= (900.0 if vy > 0.0 else 900.0 * 1.35) * DT
		var ny := y + vy * DT
		if vy < 0.0 and over and ny <= top_px:                    # lądowanie na pomoście
			ny = top_px
			on_deck = true
		elif ny <= 0.0:
			ny = 0.0
		y = ny
		if y >= top_px:
			over = true
		var grounded := (on_deck and y == top_px) or (y == 0.0 and t > 0.05)
		var h := (top_px - y) / Char3D.WP_PER_M
		if grounded:
			latched = false                                       # player.gd `_mantle_h`: stanął na pomoście albo wrócił pod niego
			if landed_t < 0.0:
				landed_t = t
		_frame("idle" if grounded else ("jump" if vy > 0.0 else "fall"), side, h if latched else NAN)
		if latched and h > 0.0 and HEAD > h - DECK_T:
			min_z = minf(min_z, float(_c.mantle_z))
		if latched and h > 1.0 and h < 1.8:
			var lh: Vector3 = _c._gp(_c._b["LeftHand"]).origin
			var ez := (Char3D.MANTLE_EDGE_Z - float(_c.mantle_z)) * cos(float(_c.model_yaw))
			hand_err = maxf(hand_err, absf(lh.y - h))
			hand_dz = maxf(hand_dz, absf(lh.z - ez))
		if landed_t >= 0.0 and t >= landed_t + 0.1:
			break
	return [min_z, hand_err, float(_c.mantle_z), over, hand_dz]

func _process(_d: float) -> bool:
	_c._set_on_screen(true)
	for side in [1.0, -1.0]:
		var nm := "w prawo" if side > 0.0 else "w lewo"
		for top in [30.0, 32.0]:
			var r := _jump(side, top)
			check("%s, wierzch %d px: stopy minęły wierzch" % [nm, int(top)], bool(r[3]))
			check("%s, wierzch %d px: model przed krawędzią przy zachodzeniu (min z %.2f m)" % [nm, int(top), float(r[0])],
				float(r[0]) >= Char3D.MANTLE_EDGE_Z + 0.2)
			check("%s, wierzch %d px: dłoń na wysokości krawędzi (błąd %.3f m)" % [nm, int(top), float(r[1])], float(r[1]) < 0.12)
			check("%s, wierzch %d px: dłoń przy krawędzi w głębi (błąd %.3f m)" % [nm, int(top), float(r[4])], float(r[4]) < (0.05 if side > 0.0 else DZ_ACROSS))
			check("%s, wierzch %d px: po lądowaniu nad pokładem (z %.3f m)" % [nm, int(top), float(r[2])], absf(float(r[2])) < 0.001)
		var s := _jump(side, 32.0, 0.06)
		check("%s, krótki skok: stopy pod wierzchem" % nm, not bool(s[3]))
		check("%s, krótki skok: model przed krawędzią, póki zachodzi na pomost (min z %.2f m)" % [nm, float(s[0])], float(s[0]) >= Char3D.MANTLE_EDGE_Z + 0.2)
		check("%s, krótki skok: po powrocie na ziemię z = 0 (%.3f m)" % [nm, float(s[2])], absf(float(s[2])) < 0.001)
	print("[MANTLE] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)
	return true
