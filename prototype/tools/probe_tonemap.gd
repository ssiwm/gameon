extends SceneTree
## Krzywa obrazu widoku 3D i symbole kalibracji jasności (nie headless — potrzebny render).
## Płaskie, nieoświetlone pola o zadanej jasności liniowej renderowane przez gradację gry (`Level3D.apply_grade`) przy ekspozycjach z
## `Settings.BRIGHTNESS_EV`; wypisuje wynik 0–255 (po tonemappingu, sRGB i kontraście). Na końcu sprawdza symbole ekranu kalibracji
## (`BrightnessScreen.LEVELS`): przy 0 EV lewy w czerni, środkowy ledwo nad nią, prawy wyraźny; pełny zakres ±1 EV musi przesuwać
## środkowy między „znika” a „widoczny”. Wypisuje PASS / FAIL.
## godot --path prototype -s tools/probe_tonemap.gd
## Tylko Forward+ (renderer gry): tryb zgodności (`--rendering-driver opengl3`, CI) ma inną krzywą — karta kalibracji idzie wtedy jego
## potokiem i dalej pokazuje prawdę o obrazie, ale progi testu go nie dotyczą.

const Level3D := preload("res://scripts/level3d.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const RAMP := [0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.008, 0.012, 0.016, 0.024, 0.032, 0.048, 0.064, 0.1, 0.2]
const CELL := 8

var _levels: Array = []                ## BrightnessScreen.LEVELS (wczytane w trakcie: skrypt ekranu odwołuje się do autoloadu Settings)
var _values: Array = []
var _evs: Array = []
var _vp: SubViewport
var _env: Environment
var _frames := 0
var _ev_i := 0
var _out := {}

func _initialize() -> void:
	_levels = load("res://scripts/brightness_screen.gd").LEVELS
	_values = RAMP + _levels
	_evs = [SettingsScript.BRIGHTNESS_EV[0], -0.5, 0.0, 0.5, SettingsScript.BRIGHTNESS_EV[SettingsScript.BRIGHTNESS_EV.size() - 1]]
	_vp = SubViewport.new()
	_vp.size = Vector2i(_values.size() * CELL, CELL)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = float(_values.size())
	cam.position = Vector3(0, 0, 5)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	Level3D.apply_grade(_env, pow(2.0, float(_evs[0])))
	cam.environment = _env
	_vp.add_child(cam)
	for i in _values.size():
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 1.0)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var v := float(_values[i])
		m.albedo_color = Color(v, v, v).linear_to_srgb()        # albedo w sRGB; shader zamienia na liniowe
		q.material_override = m
		q.position = Vector3(i - (_values.size() - 1) * 0.5, 0, 0)
		_vp.add_child(q)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	var img := _vp.get_texture().get_image()
	var row: Array = []
	for i in _values.size():
		row.append(img.get_pixel(i * CELL + CELL / 2, CELL / 2).r8)
	_out[_ev_i] = row
	_ev_i += 1
	_frames = 0
	if _ev_i < _evs.size():
		_env.tonemap_exposure = pow(2.0, float(_evs[_ev_i]))
		return false
	_report()
	return true

func _report() -> void:
	var n := RAMP.size()
	print("liniowo: ", RAMP, "  symbole: ", _levels)
	for i in _evs.size():
		var row: Array = _out[i]
		print("EV %+.2f: %s  symbole: %s" % [float(_evs[i]), str(row.slice(0, n)), str(row.slice(n))])
	var lo: Array = (_out[0] as Array).slice(n)
	var mid: Array = (_out[2] as Array).slice(n)
	var hi: Array = (_out[_evs.size() - 1] as Array).slice(n)
	var fails: Array = []
	if int(mid[0]) > 2:
		fails.append("lewy symbol przy 0 EV widoczny (%d > 2)" % int(mid[0]))
	if int(mid[1]) < 3 or int(mid[1]) > 12:
		fails.append("środkowy przy 0 EV poza „ledwo widoczny” (%d, oczekiwane 3–12)" % int(mid[1]))
	if int(mid[2]) < 15:
		fails.append("prawy przy 0 EV za ciemny (%d < 15)" % int(mid[2]))
	if int(lo[1]) > 2:
		fails.append("przy −1 EV środkowy nie znika (%d)" % int(lo[1]))
	if int(hi[0]) < 3:
		fails.append("przy +1 EV lewy nie wychodzi z czerni (%d)" % int(hi[0]))
	print("PASS brightness calibration" if fails.is_empty() else "FAIL brightness calibration: " + "; ".join(fails))
