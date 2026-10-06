extends RefCounted
## Podpowiedzi dla nowego gracza — krótkie, pokazywane jednorazowo w chwili, gdy mechanika się przydaje
## (a nie ścianą tekstu na starcie). Raz pokazana podpowiedź jest zapamiętana w Settings.seen_tips,
## więc weteran ich nie widzi; wyłącznik w menu pauzy.
##
## `update()` jest wołane co klatkę przez hud.gd i zwraca bieżący tekst ("" = brak) — hud tylko go rysuje.

const SHOW_S := 7.0                  ## ile sekund wisi podpowiedź
const GAP_S := 2.5                   ## przerwa między podpowiedziami
const FADE_S := 0.5

## [id, tekst]; kolejność = priorytet, gdy kilka warunków spełnia się naraz
const TIPS := [
	["move", "WASD to move  ·  SPACE to jump  ·  hold SHIFT to sneak — sneaking is silent"],
	["noise", "Every shot makes NOISE. Watch the meter in the top-left corner"],
	["broadcast", "The transmitter is live and HE heard it. Press Q to throw a lure and pull him away — then run for the exit"],
	["handcar", "Stand on the handcar and HOLD E to pump — more hands, more speed. You cannot shoot while pumping"],
	["generator", "Hold E at a generator to start it. The work is loud, and a running generator keeps humming"],
	["uneasy", "Something is listening. Stop shooting, sneak (SHIFT) — or press Q to lure it away"],
	["revive", "A friend is down — stand next to them and HOLD E to revive"],
	["downed", "You are down. Stay still — a teammate can revive you before you bleed out"],
	["light", "L toggles the flashlight. Light is noise too — turn it off to hide"],
	["flare", "F throws a flare: bait that draws enemies with light instead of noise"],
]

var current := ""                    ## tekst w tej chwili
var alpha := 0.0
var _id := ""
var _t := 0.0                        ## ile już wisi bieżąca podpowiedź
var _gap := 1.5                      ## odliczanie do następnej
var _session := 0.0
var _noise_seen := 0.0
var _queued := {}                    ## id → true (warunek spełniony, czeka na swoją kolej)

func reset() -> void:
	current = ""
	alpha = 0.0
	_id = ""
	_t = 0.0
	_gap = 1.5
	_session = 0.0
	_queued.clear()

## `p` = lokalny gracz (może być null).
func update(delta: float, p: Node) -> String:
	if not Settings.hints_on or p == null:
		alpha = maxf(0.0, alpha - delta / FADE_S)
		if alpha <= 0.0:
			current = ""
		return current
	_session += delta
	_collect(p)
	if _id != "":
		_t += delta
		alpha = clampf(minf(_t / FADE_S, (SHOW_S - _t) / FADE_S), 0.0, 1.0)
		if _t >= SHOW_S:
			Settings.mark_tip(_id)
			_id = ""
			current = ""
			_gap = GAP_S
	else:
		_gap -= delta
		if _gap <= 0.0:
			_start_next()
	return current

func _start_next() -> void:
	for tip in TIPS:
		var id: String = tip[0]
		if _queued.has(id) and not Settings.tip_seen(id):
			_id = id
			current = tip[1]
			_t = 0.0
			alpha = 0.0
			_queued.erase(id)
			return

func _collect(p: Node) -> void:
	# trwałe: warunek raz spełniony, podpowiedź czeka na swoją kolej
	_queue("move", _session > 2.0, true)
	_queue("noise", NoiseMgr.level >= 8.0, true)
	_queue("light", _session > 45.0, true)
	_queue("flare", _session > 150.0, true)
	# chwilowe: gdy sytuacja minie, zanim przyjdzie kolej, podpowiedź przepada
	_queue("uneasy", NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD or NoiseMgr.stalker_awake, false)
	_queue("downed", bool(p.dead), false)
	var friend_down := false
	for o in p.get_tree().get_nodes_in_group("players"):
		if o != p and bool(o.dead) and not o.is_queued_for_deletion() \
				and absf(o.global_position.x - p.global_position.x) < 160.0:
			friend_down = true
			break
	_queue("revive", friend_down, false)
	# misja 1.2: generator pod ręką; po ostatnim — lekcja Q na Stalkerze
	var near_gen := false
	for g in p.get_tree().get_nodes_in_group("generators"):
		if not g.running and absf(g.global_position.x - p.global_position.x) < 110.0 and absf(g.global_position.y - p.global_position.y) < 60.0:
			near_gen = true
			break
	_queue("generator", near_gen, false)
	var m = p.get_tree().current_scene.get("mission") if p.get_tree().current_scene else null
	var car = p.get_tree().get_first_node_in_group("handcar")
	_queue("handcar", car != null and car.enabled and not car.arrived and car.local_state != "", false)
	_queue("broadcast", m != null and m.kind == "generators" and m.phase == m.Phase.EXTRACT and NoiseMgr.stalker_awake, false)

func _queue(id: String, cond: bool, sticky: bool) -> void:
	if cond:
		if id != _id and not Settings.tip_seen(id):
			_queued[id] = true
	elif not sticky:
		_queued.erase(id)
