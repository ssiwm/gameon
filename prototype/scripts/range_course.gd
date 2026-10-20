extends Node2D
## Strzelnica w kryjówce (GUNSMITH_PLAN.md §7.5, od 1.7.334): pięć stalowych tarcz (range_target.gd) w magazynie na dolnym poziomie.
## Pierwsze trafienie uruchamia stoper, ostatnia tarcza go zatrzymuje — czas przebiegu i rekord drużyny wiszą na tabliczce nad torem
## (view3d.gd, grupa „range_course”) i w toaście. Po RESET_T s tarcze wstają; przerwany przebieg (bez trafienia przez ABANDON_T s) też.
## Wszystko rozstrzyga serwer; wynik i rekord idą do wszystkich RPC. Rekord trzyma host (Settings.range_best, zapis w ustawieniach).

const RangeTarget := preload("res://scripts/range_target.gd")

const RESET_T := 3.0
const ABANDON_T := 12.0

var spots: Array = []                 ## [[x px, y px podłogi, wysokość blachy px], …] z RANGE danych mapy (level.gd)
var sign_pos := Vector2.ZERO          ## punkt tabliczki z wynikiem (px)
var last_time := -1.0                 ## s — ostatni przebieg (−1: jeszcze nie było)
var best := -1.0                      ## s — rekord (−1: brak)
var running := false
var runs := 0                         ## ukończone przebiegi (testy)

var _targets: Array = []
var _t0 := 0.0
var _left := 0
var _since_hit := 0.0
var _reset_in := -1.0

func _ready() -> void:
	add_to_group("range_course")
	best = float(Settings.range_best) if NoiseMgr.is_server() else -1.0
	for i in spots.size():
		var s: Array = spots[i]
		var t: StaticBody2D = RangeTarget.new()
		t.name = "RangeTarget%d" % (i + 1)
		t.index = i
		t.height = float(s[2])
		t.position = Vector2(float(s[0]), float(s[1]))
		t.knocked.connect(_on_knocked)
		get_parent().add_child.call_deferred(t)
		_targets.append(t)

func targets() -> Array:
	return _targets

func _process(delta: float) -> void:
	if not NoiseMgr.is_server():
		return
	if running:
		_since_hit += delta
		if _since_hit > ABANDON_T:
			running = false
			_reset_in = 0.01                                    # przerwany przebieg: tarcze wstają od razu
	if _reset_in > 0.0:
		_reset_in -= delta
		if _reset_in <= 0.0:
			_reset_in = -1.0
			for t in _targets:
				if is_instance_valid(t):
					t.raise()

## Serwer: tarcza trafiona — start stopera przy pierwszej, wynik przy ostatniej.
func _on_knocked(_index: int) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not running:
		running = true
		_t0 = now
		_left = _targets.size()
	_left -= 1
	_since_hit = 0.0
	if _left > 0:
		return
	running = false
	runs += 1
	var t := now - _t0
	var record := best < 0.0 or t < best
	if record:
		best = t
		Settings.range_best = t
		Settings.save_range_best()
	if NoiseMgr.has_network():
		_result_rpc.rpc(t, best, record)
	else:
		_result_rpc(t, best, record)
	_reset_in = RESET_T

@rpc("authority", "call_local", "reliable")
func _result_rpc(t: float, b: float, record: bool) -> void:
	last_time = t
	best = b
	Msg.post("range.result", Msg.Ch.TOAST, tr("Range: %d plates in %.2f s") % [_targets.size() if not _targets.is_empty() else 5, t],
		{"sub": tr("New squad record!") if record else tr("Record: %.2f s") % b, "style": Msg.Style.SUCCESS if record else Msg.Style.INFO, "ttl": 5.0, "prio": 70})
