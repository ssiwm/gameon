extends Node
## Kompensacja opóźnienia (lag compensation) dla pocisków serwerowych — GDD §12 (do 150 ms).
##
## Problem: klient strzela w to, co widzi — a widzi wrogów z opóźnieniem (połowa RTT od serwera
## + interpolacja), a jego strzał dociera do serwera po kolejnej połowie RTT. Serwer, trafiając
## w aktualne pozycje, „pudłuje" w cel, który klient wyraźnie trafił.
##
## Rozwiązanie (rewind): wrogowie zapisują historię pozycji (enemy.gd `_hist`, 0,5 s). Gdy serwer
## przyjmuje strzał klienta, liczy `rewind_for(peer)` = RTT + opóźnienie interpolacji (maks.
## MAX_REWIND), a pocisk „dogania" czas strzału: leci tyle sekund krokami po STEP, testując
## trafienia w pozycje wrogów SPRZED rewind s (prostokąty z historii), ściany liczy zwykły promień.
## Po dogonieniu leci dalej w czasie rzeczywistym. Ten sam mechanizm obsługuje szynę (hitscan).
##
## RTT mierzy serwer sam (ping → pong), więc klient nie może go zawyżyć. Strzały hosta i botów
## nie są kompensowane (rewind = 0). Ciągłe bronie (promień, płomień) i cios wręcz — nie.

const MAX_REWIND := 0.15           ## s — twardy limit kompensacji (GDD §12: 150 ms)
const INTERP_DELAY := 0.05         ## s — o tyle klient widzi wrogów „wstecz" przez wygładzanie pozycji
const STEP := 1.0 / 60.0           ## s — krok dogonienia pocisku
const PING_EVERY := 0.5
const RTT_SMOOTH := 0.3            ## EMA: nowa próbka ma taką wagę

var _rtt := {}                     ## peer_id -> s (tylko serwer)
var _t_ping := 0.0

## Czas serwera (s). Wszystkie znaczniki historii używają tego samego zegara.
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Ile sekund cofnąć świat dla strzału tego peera (0 = bez kompensacji).
func rewind_for(peer_id: int) -> float:
	if not NoiseMgr.is_server() or peer_id <= 1 or not _rtt.has(peer_id):
		return 0.0
	return clampf(float(_rtt[peer_id]) + INTERP_DELAY, 0.0, MAX_REWIND)

func rtt_ms(peer_id: int) -> float:
	return float(_rtt.get(peer_id, 0.0)) * 1000.0

# ---------------------------------------------------------------- pomiar RTT

func _process(delta: float) -> void:
	if not NoiseMgr.is_server() or not NoiseMgr.has_network():
		return
	_t_ping -= delta
	if _t_ping > 0.0:
		return
	_t_ping = PING_EVERY
	for peer in multiplayer.get_peers():
		_ping.rpc_id(peer, now())

@rpc("authority", "call_remote", "unreliable")
func _ping(t: float) -> void:
	_pong.rpc_id(1, t)

@rpc("any_peer", "call_remote", "unreliable")
func _pong(t: float) -> void:
	if not NoiseMgr.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var sample := clampf(now() - t, 0.0, 1.0)
	_rtt[peer] = lerpf(float(_rtt.get(peer, sample)), sample, RTT_SMOOTH)

func forget(peer_id: int) -> void:
	_rtt.erase(peer_id)

# ---------------------------------------------------------------- trafienia w przeszłość

## Wrogowie z historią pozycji (enemy.gd) — ich fizyczne ciała pomijamy podczas kompensacji.
func rewound_rids() -> Array[RID]:
	var out: Array[RID] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("lag_rect"):
			out.append(e.get_rid())
	return out

## Najbliższy wróg trafiony odcinkiem [from, to] w pozycji z chwili `at_time`.
## → {} albo {node, pos, dist}. `skip` = RID-y już trafionych (przebicie).
func enemy_hit(from: Vector2, to: Vector2, at_time: float, skip: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("lag_rect") or not e.alive:
			continue
		if skip.has(e.get_rid()):
			continue
		var h := seg_rect(from, to, e.lag_rect(at_time))
		if h.is_empty():
			continue
		var d := from.distance_to(h["pos"])
		if d < best_d:
			best_d = d
			best = {"node": e, "pos": h["pos"], "dist": d}
	return best

## Odcinek vs prostokąt (metoda płyt). Zwraca {pos} punktu wejścia albo {} gdy nie przecina.
## Początek wewnątrz prostokąta = trafienie w punkcie startu.
static func seg_rect(a: Vector2, b: Vector2, r: Rect2) -> Dictionary:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return {}
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var lo := [r.position.x, r.position.y]
	var hi := [r.end.x, r.end.y]
	var o := [a.x, a.y]
	var dv := [d.x, d.y]
	for i in 2:
		if absf(dv[i]) < 0.00001:
			if o[i] < lo[i] or o[i] > hi[i]:
				return {}
		else:
			var ta: float = (lo[i] - o[i]) / dv[i]
			var tb: float = (hi[i] - o[i]) / dv[i]
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return {}
	return {"pos": a + d * t0}
