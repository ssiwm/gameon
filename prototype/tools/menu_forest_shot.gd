extends SceneTree
## Kadr tła menu (`scripts/menu_forest.gd`) do pliku: źródło statycznego tła zastępczego `art/menu/backdrop.jpg` (tryb zgodności,
## headless, pierwsze klatki menu przed zbudowaniem sceny) i podgląd zmian sceny bez uruchamiania gry.
##   godot --path prototype --script tools/menu_forest_shot.gd -- --out=C:/tmp/menu_forest.png [--size=2560x1440] [--wait=90] [--t=0,20,40] [--live] [--perf=240]
## `--wait` — klatek po zbudowaniu (mgła wolumetryczna ustala się przez filtr czasowy); `--live` — mgła i światła w ruchu jak w menu
## (bez niego czas stoi, kadr jest powtarzalny); `--t` — czas mgły w sekundach, kilka wartości = kilka plików `<out>_t<N>.png`; `--perf=N` — zamiast zrzutu średni czas renderu sceny z N klatek. Okno — przed uruchomieniem `override.cfg` z katalogiem QA.

var _vp: SubViewport
var _out := "menu_forest.png"
var _size := Vector2i(2560, 1440)
var _wait := 90
var _live := false
var _after := -1
var _times: Array = []
var _perf := 0
var _gpu: Array = []
var _cpu: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			_size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
		elif a.begins_with("--t="):
			for v in a.substr(4).split(","):
				_times.append(float(v))
		elif a.begins_with("--perf="):
			_perf = int(a.substr(7))
		elif a == "--live":
			_live = true
	var st := root.get_node_or_null("Settings")
	if st != null:
		st.set("quality_idx", 2)                          # pełna jakość (cienie księżyca) bez względu na profil QA
	_vp = (load("res://scripts/menu_forest.gd") as GDScript).new()
	_vp.set("frozen", not _live)
	root.add_child(_vp)
	_vp.size = _size
	_vp.set_active(true)
	if _perf > 0:
		RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)

func _process(_d: float) -> bool:
	if _after < 0:
		if int(_vp.get("_stage")) > 5:
			_after = 0
		return false
	if _perf > 0:                                       # pomiar: średni czas GPU / CPU renderu sceny w ms
		_after += 1
		if _after > 30:
			_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid()))
			_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp.get_viewport_rid()))
		if _gpu.size() >= _perf:
			_gpu.sort()
			print("[MENU-FOREST] %dx%d GPU ms: średnio %.2f, mediana %.2f, p95 %.2f; CPU ms %.2f" % [_size.x, _size.y,
					_gpu.reduce(func(a, b): return a + b) / _gpu.size(), _gpu[_gpu.size() / 2], _gpu[int(_gpu.size() * 0.95)],
					_cpu.reduce(func(a, b): return a + b) / _cpu.size()])
			quit()
		return false
	if _after == 0 and not _times.is_empty():
		_vp.set("_t", _times[0])
	_after += 1
	if _after == _wait:
		var path := _out
		if not _times.is_empty():
			path = _out.get_basename() + "_t%d.png" % int(_times[0])
			_times.pop_front()
		var img := _vp.get_texture().get_image()
		img.save_png(path)
		print("[MENU-FOREST] zapisano ", path, " ", img.get_size())
		if _times.is_empty():
			quit()
		else:
			_after = 0
	return false
