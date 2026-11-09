extends SceneTree
## Test kamery przekroju kryjówki „dwa pokłady” (`HUB_LAYOUT_PLAN.md` E3): `Camera2D` z granicami z `SectionCamera.band` (jak w grze:
## kamera 35 px nad stopami gracza, granice poziome z bounds mapy) dla każdego zbliżenia z `Settings.CAM_ZOOM` i proporcji okna 16:9,
## 21:9 i 16:10 (rozciąganie „keep” — kadr świata ma zawsze 640 × 360, reszta okna to pasy):
## (1) dane: `CAM_LOCK` [strop, podłoga] w mapie, pas wiersz podłogi parteru i piwnicy w środku, `EYE_UP` dodatni,
## (2) NORMAL i WIDE: cały pas (strop parteru i podłoga piwnicy) w kadrze w każdym punkcie obu pokładów, w skoku i w pionie, a środek
##     kadru w pionie stoi w miejscu (kamera jedzie tylko w poziomie),
## (3) CLOSE: kadr nie wychodzi poza pas, gracz (stopy i głowa) zawsze w kadrze, na parterze widać cały parter, w piwnicy całą piwnicę,
##     a przy zejściu pionem środek kadru przesuwa się co klatkę najwyżej o tyle, o ile gracz (bez skoków),
## (4) oko kamery 3D (`SectionCamera.eye_up_for`, view3d.gd): kryjówka bierze `EYE_UP`, misja `EYE_UP_M`; przy NORMAL i WIDE oko stoi wewnątrz parteru,
##     co najmniej EYE_ABOVE_FLOOR_M nad jego podłogą (podłoga czyta się jako pokład, a nie kreska), i ponad podłogą piwnicy.
## godot --headless --path prototype -s tools/test_hub_camera.gd   → ma wypisać PASS
const SectionCamera := preload("res://scripts/section_camera.gd")
const Hub := preload("res://scripts/maps/z1_hub.gd")
const Mission := preload("res://scripts/maps/z1_m1.gd")
const TILE := 16.0
const PX := 1.8 / 22.0                     ## m na px świata (Level3D.PX)
const CAM_OFF_Y := -35.0                   ## player.tscn: Camera2D 35 px nad stopami
const BASE := Vector2(640, 360)            ## project.godot: viewport_width × viewport_height, stretch „keep”
const HEAD_PX := 22.0                      ## sylwetka gracza nad stopami
const EYE_ABOVE_FLOOR_M := 2.5
const WINDOWS := {"16:9": Vector2i(2560, 1440), "21:9": Vector2i(3440, 1440), "16:10": Vector2i(1920, 1200)}
var _fail := 0
var _cam: Camera2D
var _anchor: Node2D

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fail += 1

## Kadr świata przy rozciąganiu „keep”: zawsze BASE (okno o innych proporcjach dostaje pasy).
func _visible_size(_win: Vector2i) -> Vector2:
	return BASE

## Środek kadru dla gracza o stopach w `feet` przy zoomie `z` (prawdziwy Camera2D z granicami).
func _center(feet: Vector2, z: float, band: Vector2i, w: float) -> Vector2:
	_anchor.position = feet
	_cam.zoom = Vector2(z, z)
	_cam.limit_left = 0
	_cam.limit_right = int(w)
	_cam.limit_top = band.x
	_cam.limit_bottom = band.y
	_cam.force_update_scroll()
	return _cam.get_screen_center_position()

func _init() -> void:
	root.size = Vector2i(BASE)
	_anchor = Node2D.new()
	root.add_child(_anchor)
	_cam = Camera2D.new()
	_cam.position = Vector2(0.0, CAM_OFF_Y)
	_anchor.add_child(_cam)
	_cam.make_current()
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var consts := (Hub as GDScript).get_script_constant_map()
	var cl: Array = consts.get("CAM_LOCK", [])
	var rows: Array = consts.get("MAP", [])
	_check(cl.size() == 2 and int(cl[0]) < int(cl[1]), "CAM_LOCK [strop, podłoga] w danych kryjówki (%s)" % str(cl))
	if cl.size() != 2:
		_finish()
		return
	var lock := Vector2i(int(cl[0]), int(cl[1]))
	var w := float((rows[0] as String).length()) * TILE if not rows.is_empty() else 53.0 * TILE
	var parter := 9 * TILE                  # wiersz podłogi parteru (z1_hub.gd: znaczniki w wierszu 8)
	var cellar := 14 * TILE                 # wiersz podłogi piwnicy
	var band_top := float(lock.x) * TILE
	var band_bot := float(lock.y + 1) * TILE
	_check(lock.x * TILE < parter - 4.0 * TILE and lock.y * TILE == cellar, "pas: strop nad parterem, dół na podłodze piwnicy (%d–%d)" % [lock.x, lock.y])
	var eye_hub := float(consts.get("EYE_UP", -1.0))
	_check(eye_hub > 0.0, "EYE_UP w danych kryjówki (%.2f m)" % eye_hub)
	var xs := [3.0 * TILE, 12.0 * TILE, 23.5 * TILE, 40.0 * TILE, 50.0 * TILE]
	var zooms := _settings_array("CAM_ZOOM")
	var names := _settings_array("CAM_NAMES")
	_check(zooms.size() == 3 and names.size() == 3, "Settings.CAM_ZOOM i CAM_NAMES odczytane z settings.gd (%s)" % str(zooms))
	for wn in WINDOWS:
		var vis := _visible_size(WINDOWS[wn])
		for zi in zooms.size():
			var z := float(zooms[zi])
			var name := "%s %s" % [names[zi], wn]
			var h := vis.y / z
			var band := SectionCamera.band(lock, TILE, h)
			var fits := h >= band_bot - band_top
			# punkty: stopy na obu pokładach, w skoku (40 px) i w pionie co 2 px od parteru do piwnicy
			var pts: Array = []
			for x in xs:
				pts.append(Vector2(x, parter))
				pts.append(Vector2(x, parter - 40.0))
				pts.append(Vector2(x, cellar))
				pts.append(Vector2(x, cellar - 40.0))
			var shaft: Array = []
			var y := parter
			while y <= cellar:
				shaft.append(Vector2(23.5 * TILE, y))
				y += 2.0
			if fits:
				var all_in := true
				var ys := {}
				for p in pts + shaft:
					var c := _center(p, z, band, w)
					ys[snappedf(c.y, 0.01)] = true
					if c.y - h * 0.5 > band_top + 0.5 or c.y + h * 0.5 < band_bot - 0.5:
						all_in = false
				_check(all_in, "%s: strop parteru i podłoga piwnicy zawsze w kadrze (kadr %.0f px, pas %.0f px)" % [name, h, band_bot - band_top])
				_check(ys.size() == 1, "%s: środek kadru w pionie stały (%d wartości)" % [name, ys.size()])
			else:
				var inside := true
				var seen := true
				for p in pts + shaft:
					var c := _center(p, z, band, w)
					if c.y - h * 0.5 < band_top - 0.5 or c.y + h * 0.5 > band_bot + 0.5:
						inside = false
					if (p as Vector2).y - HEAD_PX < c.y - h * 0.5 or (p as Vector2).y > c.y + h * 0.5:
						seen = false
				_check(inside, "%s: kadr (%.0f px) nie wychodzi poza pas" % [name, h])
				_check(seen, "%s: gracz zawsze w kadrze (stopy i głowa)" % name)
				var cp := _center(Vector2(12.0 * TILE, parter), z, band, w)
				var cc := _center(Vector2(12.0 * TILE, cellar), z, band, w)
				_check(cp.y - h * 0.5 <= band_top + 0.5 and cp.y + h * 0.5 >= parter + 0.5,
					"%s: na parterze cały parter w kadrze (%.0f–%.0f px)" % [name, cp.y - h * 0.5, cp.y + h * 0.5])
				_check(cc.y + h * 0.5 >= band_bot - 0.5 and cc.y - h * 0.5 <= parter + TILE - 0.5,
					"%s: w piwnicy cała piwnica w kadrze (%.0f–%.0f px)" % [name, cc.y - h * 0.5, cc.y + h * 0.5])
				var jump := 0.0
				var prev := _center(shaft[0], z, band, w).y
				for i in range(1, shaft.size()):
					var cy := _center(shaft[i], z, band, w).y
					jump = maxf(jump, absf(cy - prev))
					prev = cy
				_check(jump <= 2.0 + 0.01, "%s: zejście pionem bez skoku kadru (największy krok %.2f px przy 2 px gracza)" % [name, jump])
			if zi <= 1:
				# oko kamery 3D ponad środkiem kadru: wewnątrz parteru, wyraźnie nad jego podłogą
				var c := _center(Vector2(23.5 * TILE, parter), z, band, w)
				var eye_y := c.y - eye_hub / PX
				_check(eye_y > band_top + TILE and eye_y < parter, "%s: oko w obrębie parteru (y %.0f px, parter %.0f–%.0f)" % [name, eye_y, band_top + TILE, parter])
				_check((parter - eye_y) * PX >= EYE_ABOVE_FLOOR_M,
					"%s: oko %.2f m nad podłogą parteru (≥ %.1f m)" % [name, (parter - eye_y) * PX, EYE_ABOVE_FLOOR_M])
	var hub_lvl := Node.new()
	hub_lvl.set_script(_level_stub(eye_hub))
	var m_lvl := Node.new()
	m_lvl.set_script(_level_stub(float((Mission as GDScript).get_script_constant_map().get("EYE_UP", -1.0))))
	_check(is_equal_approx(SectionCamera.eye_up_for(hub_lvl), eye_hub), "eye_up_for: kryjówka %.2f m" % SectionCamera.eye_up_for(hub_lvl))
	_check(is_equal_approx(SectionCamera.eye_up_for(m_lvl), SectionCamera.EYE_UP_M), "eye_up_for: misja bez EYE_UP → %.2f m" % SectionCamera.eye_up_for(m_lvl))
	_check(is_equal_approx(SectionCamera.eye_up_for(null), SectionCamera.EYE_UP_M), "eye_up_for: bez mapy → EYE_UP_M")
	hub_lvl.free()
	m_lvl.free()
	_finish()

## Tablica stałej z settings.gd (autoload — skrypt `-s` go nie skompiluje, więc czytamy tekst źródła).
func _settings_array(cname: String) -> Array:
	var src := FileAccess.get_file_as_string("res://scripts/settings.gd")
	var re := RegEx.create_from_string("const " + cname + r" := (\[[^\]]*\])")
	var m := re.search(src)
	if m == null:
		return []
	var v = JSON.parse_string(m.get_string(1))
	return v if v is Array else []

## Węzeł z polem `eye_up` jak level.gd.
func _level_stub(v: float) -> GDScript:
	var g := GDScript.new()
	g.source_code = "extends Node\nvar eye_up := %f\n" % v
	g.reload()
	return g

func _finish() -> void:
	print("[HUB-CAMERA] " + ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail > 0 else 0)
