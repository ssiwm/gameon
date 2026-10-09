extends SceneTree
## Pomiar kosztu postaci 3D (spike): średni czas klatki dla N postaci. godot --path prototype --script tools/bench_char3d.gd -- [--n=1,5,10] [--frames=240]
const Char3D := preload("res://scripts/char3d.gd")
var _counts: Array = [0, 1, 5, 10]
var _frames := 240
var _idx := -1
var _nodes: Array = []
var _t0 := 0
var _f := 0
var _gpu := 0.0
var _cpu := 0.0
var _upd := 0.0
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			_counts = []
			for s in a.substr(4).split(","):
				_counts.append(int(s))
		elif a == "--nonormals":
			Char3D.normals = false
		elif a == "--lq":
			Char3D.set_low_quality(true)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	_next()
func _next() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_idx += 1
	if _idx >= _counts.size():
		quit()
		return
	for i in int(_counts[_idx]):
		var c := Char3D.new()
		c.position = Vector2(80 + (i % 10) * 110, 200 + (i / 10) * 150)
		c.scale = Vector2(3, 3)
		root.add_child(c)
		c.setup("male_scav", "m83")
		_nodes.append(c)
		RenderingServer.viewport_set_measure_render_time(c._vp.get_viewport_rid(), true)
		if c._vpn != null:
			RenderingServer.viewport_set_measure_render_time(c._vpn.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_gpu = 0.0
	_cpu = 0.0
	_upd = 0.0
	_f = -30                                                   # rozgrzewka
func _process(delta: float) -> bool:
	var u0 := Time.get_ticks_usec()
	for i in _nodes.size():
		var a := float(i) * 0.4 + Time.get_ticks_msec() * 0.001
		_nodes[i].update(delta, "run" if i % 2 == 0 else "idle", 1.0, Vector2(cos(a), -sin(a) * 0.6), 95.0 if i % 2 == 0 else 0.0)
	var u1 := float(Time.get_ticks_usec() - u0) / 1000.0
	_f += 1
	if _f > 0:
		_upd += u1
		for c in _nodes:
			var r: RID = c._vp.get_viewport_rid()
			_gpu += RenderingServer.viewport_get_measured_render_time_gpu(r)
			_cpu += RenderingServer.viewport_get_measured_render_time_cpu(r)
			if c._vpn != null:
				var rn: RID = c._vpn.get_viewport_rid()
				_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rn)
				_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rn)
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	if _f == 0:
		_t0 = Time.get_ticks_usec()
	elif _f == _frames:
		var ms := float(Time.get_ticks_usec() - _t0) / 1000.0 / float(_frames)
		print("BENCH n=%d  render GPU %.2f ms  CPU %.2f ms  update() %.2f ms (na klatkę)" % [_counts[_idx], _gpu / _frames, _cpu / _frames, _upd / _frames])
		_next()
	return false
