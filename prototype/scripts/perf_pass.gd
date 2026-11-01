extends Node
## Dev (--perf): ile trwa cały przebieg `_process` i `_physics_process` w klatce: węzeł na początku i na końcu każdego przebiegu mierzy czas zegarem,
## bo Performance.TIME_* to sekundowe szczyty, a tryb --headless ma limit klatek i nie widzi widoku 3D. Reszta klatki to silnik: wejście, render, czekanie na vsync.

class Edge extends Node:
	var owner_pass: Node
	var last := false
	func _process(_delta: float) -> void:
		owner_pass.call("edge_proc", last)
	func _physics_process(_delta: float) -> void:
		owner_pass.call("edge_phys", last)

var proc_usec := 0
var phys_usec := 0
var phys_ticks := 0
var frames := 0
var _proc_t0 := 0
var _phys_t0 := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for last in [false, true]:
		var e := Edge.new()
		e.owner_pass = self
		e.last = last
		e.process_mode = Node.PROCESS_MODE_ALWAYS
		e.process_priority = 1000000 if last else -1000000
		e.process_physics_priority = 1000000 if last else -1000000
		add_child(e)

func edge_proc(last: bool) -> void:
	if not last:
		_proc_t0 = Time.get_ticks_usec()
		return
	proc_usec += Time.get_ticks_usec() - _proc_t0
	frames += 1

func edge_phys(last: bool) -> void:
	if not last:
		_phys_t0 = Time.get_ticks_usec()
		return
	phys_usec += Time.get_ticks_usec() - _phys_t0
	phys_ticks += 1

func reset() -> void:
	proc_usec = 0
	phys_usec = 0
	phys_ticks = 0
	frames = 0

## Średnie ms na klatkę: przebieg _process, przebieg fizyki (wszystkie kroki) i kroki fizyki na klatkę.
func report() -> String:
	var n := float(maxi(frames, 1))
	return "_process %.2f ms  _physics_process %.2f ms na klatkę (%.2f ms na krok, %.2f kroku na klatkę)" % [float(proc_usec) / 1000.0 / n, float(phys_usec) / 1000.0 / n, float(phys_usec) / 1000.0 / float(maxi(phys_ticks, 1)), float(phys_ticks) / n]
