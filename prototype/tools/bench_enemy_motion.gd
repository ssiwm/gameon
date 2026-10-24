extends SceneTree
## Powtarzalny pomiar kosztu pozowania oraz czasu klatki przy widocznych modelach.
## Wymaga renderera: -s tools/bench_enemy_motion.gd -- --count=12 --out=WYNIK.json
const Enemy := preload("res://scripts/enemy3d.gd")
var actors: Array[Node3D] = []
var frame := 0
var count := 12
var output := "/tmp/enemy-bench.json"
var pose_ms: Array[float] = []
var frame_ms: Array[float] = []
var previous_us := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): count = clampi(arg.substr(8).to_int(), 1, 48)
		if arg.begins_with("--out="): output = arg.substr(6)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.19, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.shadow_enabled = true
	vp.add_child(light)
	var cols := 6
	var rows := ceili(count / float(cols))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(rows * 4.5, 16.0)
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, rows * 2.25, 35), Vector3(0, rows * 2.25, 0))
	cam.current = true
	var kinds := Enemy.SPEC.keys()
	for index in count:
		var actor := Enemy.new()
		vp.add_child(actor)
		actor.setup(String(kinds[index % kinds.size()]))
		actor.position = Vector3((index % cols - 2.5) * 4.2, (index / cols) * 4.5, 0)
		actors.append(actor)

func percentile(values: Array[float], ratio: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(sorted.size() * ratio))]

func _process(_dt: float) -> bool:
	frame += 1
	var start := Time.get_ticks_usec()
	var time := fposmod(frame / 60.0, 2.5)
	for actor in actors:
		actor.motion_context({"grounded": true, "winding": time < 0.8, "windup_duration": 0.8, "windup_remaining": maxf(0.8 - time, 0.0)})
		if frame % 150 == 48: actor.trigger("attack")
		actor.pose(1.0 / 60.0, "windup" if time < 0.8 else "walk", false, Color.WHITE)
	if frame > 120:
		pose_ms.append((Time.get_ticks_usec() - start) / 1000.0)
		frame_ms.append((start - previous_us) / 1000.0)
	previous_us = start
	if frame == 420:
		var report := {"count": count, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
			"resolution": [1280,720], "pose_p50_ms": percentile(pose_ms,0.5), "pose_p95_ms": percentile(pose_ms,0.95),
			"frame_p50_ms": percentile(frame_ms,0.5), "frame_p95_ms": percentile(frame_ms,0.95),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"video_memory_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
		print("PASS enemy benchmark: ", JSON.stringify(report))
		quit()
	return false
