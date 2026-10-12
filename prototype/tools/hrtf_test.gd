extends SceneTree
## Eksperyment F7 (AUDIO_PLAN.md, bramka B): ślepy test kierunku dźwięku — obecna panorama stereo kontra HRTF (Steam Audio
## przez wtyczkę Nexus Resonance). NIE jest częścią gry: wtyczka leży lokalnie w addons/nexus_resonance/ (poza repo).
##
##   godot --path prototype -s tools/hrtf_test.gd                 # okno; koniecznie słuchawki
##   godot --path prototype -s tools/hrtf_test.gd -- --reps=4     # więcej prób (domyślnie 3 na kierunek i tryb = 24)
##   godot --headless --path prototype -s tools/hrtf_test.gd -- --auto   # test dymny bez słuchania (losowe odpowiedzi)
##   godot --headless --path prototype -s tools/hrtf_test.gd -- --measure   # pomiar wyjścia: poziom L/P i „jasność” na kierunek
##
## Każda próba gra głos Stalkera z jednego z czterech kierunków (lewo, prawo, góra, dół) jednym z dwóch trybów — nie wiesz
## którym. Strzałką wskazujesz kierunek, [R] powtarza dźwięk. Na końcu tabela trafień osobno dla trybów; wynik trafia też
## do user://hrtf_test_result.txt i na standardowe wyjście.

const DIRS := ["lewo", "prawo", "góra", "dół"]
const DIR_2D := [Vector2(-220, 0), Vector2(220, 0), Vector2(0, -220), Vector2(0, 220)]          # px, jak w grze (y w dół)
const DIR_3D := [Vector3(-3, 0, -1), Vector3(3, 0, -1), Vector3(0, 3, -1), Vector3(0, -3, -1)]  # m, słuchacz patrzy w −Z
const KEYS := {KEY_LEFT: 0, KEY_RIGHT: 1, KEY_UP: 2, KEY_DOWN: 3}
const SOUNDS := ["sfx/stalker/stalker_growl_1", "sfx/stalker/stalker_shriek_1", "sfx/stalker/stalker_growl_2", "sfx/stalker/stalker_shriek_2"]
const MODES := ["stereo (jak w grze)", "HRTF (Steam Audio)"]
const VOLUME_DB := -8.0
const HRTF_GAIN_DB := 2.0          # wyrównanie głośności trybów wg --measure (wtyczka liczy volume_db podwójnie: +2 dB daje +4 dB)

var _p2d: AudioStreamPlayer2D
var _p3d: AudioStreamPlayer3D
var _label: Label
var _trials: Array = []            # [tryb, kierunek, dźwięk]
var _i := -1
var _hits := {}                    # [tryb, oś] -> [trafione, wszystkie]; oś 0 = lewo/prawo, 1 = góra/dół
var _auto := false
var _done := false
var _wait_t := 0.0
var _measure_mode := false
var _binaural := -1                # --binaural=0/1: wymuszenie panoramy / HRTF w źródle (diagnostyka); -1 = ustawienie globalne
var _held := {}                    # klawisz -> czy był wciśnięty w poprzedniej klatce


func _initialize() -> void:
	var reps := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reps="):
			reps = maxi(1, int(a.trim_prefix("--reps=")))
		elif a == "--auto":
			_auto = true
		elif a == "--measure":
			_measure_mode = true
		elif a.begins_with("--binaural="):
			_binaural = int(a.trim_prefix("--binaural="))
	await process_frame
	if not ClassDB.class_exists("ResonancePlayer"):
		print("[HRTFTEST] brak wtyczki: skopiuj addons/nexus_resonance/ (wydanie 1.1.0) do prototype/addons/ i uruchom godot --import")
		quit(1)
		return
	_build()
	if _measure_mode:
		await _measure()
		quit(0)
		return
	for mode in 2:
		for d in 4:
			for r in reps:
				_trials.append([mode, d, SOUNDS[(d + r + mode) % SOUNDS.size()]])
	_trials.shuffle()
	for mode in 2:
		for axis in 2:
			_hits[[mode, axis]] = [0, 0]
	process_frame.connect(_tick)
	for i in 30:                                        # Steam Audio rozgrzewa wyjście przez kilka bloków
		await process_frame
	_next()


func _build() -> void:
	# --- tryb A: to, co robi gra — AudioStreamPlayer2D i słuchacz 2D (panorama tylko lewo/prawo)
	var world2d := Node2D.new()
	root.add_child(world2d)
	var l2 := AudioListener2D.new()
	world2d.add_child(l2)
	l2.make_current()
	_p2d = AudioStreamPlayer2D.new()
	_p2d.max_distance = 1600.0
	_p2d.attenuation = 1.1
	_p2d.volume_db = VOLUME_DB
	world2d.add_child(_p2d)
	# --- tryb B: Steam Audio — sam dźwięk bezpośredni z HRTF, bez odbić, zasłaniania i tłumienia odległością
	var world3d := Node3D.new()
	root.add_child(world3d)
	var runtime: Node = ClassDB.instantiate("ResonanceRuntime")
	var rcfg: Resource = load("res://addons/nexus_resonance/scripts/resonance_runtime_config.gd").create_default()
	rcfg.set("direct_binaural", true)
	rcfg.set("pathing_enabled", false)
	runtime.set("runtime", rcfg)
	world3d.add_child(runtime)
	# Steam Audio liczy parametry źródeł dopiero, gdy scena ma jakąkolwiek geometrię (inaczej dźwięk zostaje wyciszony):
	# jedna bryła daleko pod słuchaczem, bez wpływu na dźwięk bezpośredni.
	var slab := MeshInstance3D.new()
	slab.mesh = BoxMesh.new()
	slab.position = Vector3(0, -200, 0)
	world3d.add_child(slab)
	slab.add_child(ClassDB.instantiate("ResonanceGeometry") as Node)
	var cam := Camera3D.new()
	world3d.add_child(cam)
	cam.make_current()
	cam.add_child(ClassDB.instantiate("ResonanceListener") as Node)
	_p3d = ClassDB.instantiate("ResonancePlayer") as AudioStreamPlayer3D
	var pcfg: Resource = load("res://addons/nexus_resonance/scripts/resonance_player_config.gd").create_default()
	for off in ["reflections_enabled", "simulation_occlusion_enabled", "simulation_transmission_enabled", "air_absorption_enabled", "distance_attenuation"]:
		pcfg.set(off, false)
	pcfg.set("direct_binaural_override", _binaural)
	_p3d.set("player_config", pcfg)
	_p3d.volume_db = VOLUME_DB + HRTF_GAIN_DB
	world3d.add_child(_p3d)
	# --- ekran
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_label)


## Pomiar tego, co faktycznie wychodzi na szynę główną: poziom lewego i prawego kanału oraz udział góry pasma
## (przejścia przez zero) dla każdego trybu i kierunku. Pokazuje, czy tryb w ogóle koduje dany kierunek.
func _measure() -> void:
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(0, cap)
	for i in 40:
		await process_frame
	var srv := Engine.get_singleton("ResonanceServer")
	print("[HRTFTEST] Steam Audio: zainicjowany ", srv.call("is_initialized"), ", symulacja ", srv.call("is_simulating"),
		", wyjście przestrzenne gotowe ", srv.call("is_spatial_audio_output_ready"))
	print("[HRTFTEST] pomiar wyjścia (%s): poziom L / P [dB], różnica L−P, udział góry pasma w kanale" % SOUNDS[1])
	for mode in 2:
		for d in 4:
			_trials = [[mode, d, SOUNDS[1]]]
			_i = 0
			await create_timer(0.3).timeout                  # ogon poprzedniej próby
			cap.clear_buffer()
			_play()
			await create_timer(1.2).timeout
			_p2d.stop()
			_p3d.call("stop")
			var buf := cap.get_buffer(cap.get_frames_available())
			var sl := 0.0
			var sr := 0.0
			# pasma: poniżej ok. 700 Hz i powyżej ok. 3 kHz (filtry jednobiegunowe) — cień głowy i małżowina działają w górze
			var lo := Vector2.ZERO
			var mid := Vector2.ZERO
			var e_lo := Vector2.ZERO
			var e_hi := Vector2.ZERO
			var k_lo := 1.0 - exp(-TAU * 700.0 / 48000.0)
			var k_hi := 1.0 - exp(-TAU * 3000.0 / 48000.0)
			for j in buf.size():
				var v := buf[j]
				sl += v.x * v.x
				sr += v.y * v.y
				lo += (v - lo) * k_lo
				mid += (v - mid) * k_hi
				e_lo += lo * lo
				e_hi += (v - mid) * (v - mid)
			var n := maxf(1.0, float(buf.size()))
			var dl := _db10(sl / n)
			var dr := _db10(sr / n)
			print("[HRTFTEST]   %-20s %-6s  L %6.1f  P %6.1f  L−P %+5.1f | L−P dół pasma %+5.1f, góra pasma %+5.1f | góra/dół pasma w L %+6.2f" % [
				MODES[mode], DIRS[d], dl, dr, dl - dr, _db10(e_lo.x) - _db10(e_lo.y), _db10(e_hi.x) - _db10(e_hi.y),
				_db10(e_hi.x) - _db10(e_lo.x)])
	_i = -1


static func _db10(x: float) -> float:
	return 10.0 * log(x + 1e-12) / log(10.0)


func _stream(rel: String) -> AudioStream:
	for base in ["res://audio_licensed/", "res://audio/"]:           # tak jak gra: wersja z nagrań, jeśli jest
		if ResourceLoader.exists(base + rel + ".wav"):
			return load(base + rel + ".wav")
	return null


func _play() -> void:
	var t: Array = _trials[_i]
	_p2d.stop()
	_p3d.call("stop")
	if int(t[0]) == 0:
		_p2d.position = DIR_2D[int(t[1])]
		_p2d.stream = _stream(t[2])
		_p2d.play()
	else:
		_p3d.position = DIR_3D[int(t[1])]
		# przez call(): ResonancePlayer podmienia set_stream / play własnymi (wewnętrzny strumień z DSP Steam Audio);
		# typowane wywołanie na AudioStreamPlayer3D trafiłoby w metody klasy bazowej i ominęło wtyczkę
		_p3d.call("set_stream", _stream(t[2]))
		_p3d.call("play")


func _next() -> void:
	_i += 1
	if _i >= _trials.size():
		_finish()
		return
	_label.text = "Próba %d z %d\n\nSkąd dochodzi dźwięk?\nStrzałki: lewo / prawo / góra / dół      [R] powtórz      [Esc] przerwij" % [_i + 1, _trials.size()]
	_wait_t = 0.0
	_play()


func _answer(dir: int) -> void:
	var t: Array = _trials[_i]
	var axis := 0 if int(t[1]) < 2 else 1
	var h: Array = _hits[[int(t[0]), axis]]
	h[1] += 1
	if dir == int(t[1]):
		h[0] += 1
	_next()


func _tick() -> void:
	if _i < 0:
		return
	# MainLoop nie dostaje zdarzeń wejścia — klawisze czytamy sami, reagując na samo wciśnięcie
	var pressed := {}
	for key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_R, KEY_ESCAPE]:
		pressed[key] = Input.is_key_pressed(key) and not bool(_held.get(key, false))
		_held[key] = Input.is_key_pressed(key)
	if _done:
		if pressed[KEY_ESCAPE]:
			quit(0)
		return
	if _auto:
		_wait_t += root.get_process_delta_time()
		if _wait_t > 0.25:
			_answer(randi() % 4)
		return
	for key in KEYS:
		if pressed[key]:
			_answer(int(KEYS[key]))
			return
	if pressed[KEY_R]:
		_play()
	elif pressed[KEY_ESCAPE]:
		_finish()


func _finish() -> void:
	_done = true
	_p2d.stop()
	_p3d.call("stop")
	var lines: Array[String] = ["Test kierunku — trafienia (losowe zgadywanie = 25%)", ""]
	for mode in 2:
		var lr: Array = _hits[[mode, 0]]
		var ud: Array = _hits[[mode, 1]]
		lines.append("%s:  lewo/prawo %d z %d,  góra/dół %d z %d" % [MODES[mode], lr[0], lr[1], ud[0], ud[1]])
	var text := "\n".join(lines)
	print("[HRTFTEST]\n", text)
	var f := FileAccess.open("user://hrtf_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	_label.text = text + "\n\nWynik zapisany też w user://hrtf_test_result.txt.  [Esc] zamyka."
	if _auto:
		quit(0)
