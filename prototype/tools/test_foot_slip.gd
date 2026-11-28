extends SceneTree
## Poślizg stóp w pętlach kroku (VOICE_MOCAP_PLAN.md B3): postać 3D biegnie w miejscu z prędkością gry, a stopa w podporze (najniżej,
## w pasie 2 cm nad najniższym położeniem) ma cofać się względem ciała w tempie ruchu — wtedy w świecie stoi na gruncie. Mierzy stosunek
## średniej prędkości stopy w podporze do prędkości postaci (1 = brak poślizgu) po klipie, IK i fazie kroku z `char3d.gd`, jak w widoku 3D.
##   godot --headless --path prototype -s tools/test_foot_slip.gd     → ostatni wiersz: [FOOT-SLIP] PASS / FAIL
## Bez progu poślizgu klip wyglądałby, jakby postać jechała po lodzie (stopa przesuwa się w podporze) albo drobiła w miejscu.

const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const STANCE_M := 0.02                       ## m: stopa w podporze — najwyżej tyle nad najniższym położeniem
## [stan, prędkość px/s, bieg tyłem, wygląd, dolna granica stosunku, górna granica]. Od 1.7.711 tempo i długość kroku idą z prędkości
## (char3d.gd `GAIT`, `_step_rate`), więc w biegu stopa stoi (1,0 ± 0,15; wcześniej 1,1–1,5, przy mieszance sprintu i truchtu 0,8).
## Marsz w kucaniu: gra przesuwa kucającego o ok. 3,7 m/s, a krok klipu ma ok. 1 m przy najwyżej 1,9 cyklu/s i rozsunięciu ×1,7 —
## stopa w podporze cofa się o ok. 0,8–0,9 prędkości postaci (wcześniej 0,15); przy wolnym podłożu (25 px/s) stoi.
const CASES := [
	["run", 95.0, false, "male_scav", 0.85, 1.15],
	["run", 95.0, false, "female_scav", 0.85, 1.15],
	["run", 80.0, false, "male_scav", 0.85, 1.15],
	["run", 70.0, false, "male_scav", 0.85, 1.15],
	["run", 50.0, false, "female_scav", 0.85, 1.15],
	["run", 95.0, true, "male_scav", 0.85, 1.15],
	["run", 50.0, true, "female_scav", 0.85, 1.15],
	["crouch_walk", 45.0, false, "male_scav", 0.75, 1.15],
	["crouch_walk", 45.0, false, "female_scav", 0.7, 1.15],
	["crouch_walk", 25.0, false, "male_scav", 0.85, 1.15],
]

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[FOOT-SLIP] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for cs in CASES:
		var c: Node2D = Char3D.new()
		root.add_child(c)
		c.setup(String(cs[3]), "m83")
		var anim := String(cs[0])
		var speed := float(cs[1])
		var back := bool(cs[2])
		c.back_run = back
		var tracks := {"LeftFoot": [], "RightFoot": []}
		for i in 240:
			c.update(DT, anim, 1.0, Vector2(1.0, 0.0), speed, true)
			if i < 60:
				continue                                          # rozpęd i mieszanie stanów
			for bone in tracks:
				(tracks[bone] as Array).append(c._to_px(c._gp(c._b[bone]).origin))
		var dir := -1.0 if back else 1.0                          # bieg tyłem: postać zwrócona w prawo idzie w lewo
		var ratios := []
		for bone in tracks:
			var tr: Array = tracks[bone]
			var ys: Array = []
			for p: Vector2 in tr:
				ys.append(p.y)
			ys.sort()
			var low: float = ys[ys.size() * 9 / 10]                # y w px rośnie w dół: najniższe położenie stopy (10. percentyl — krótki dołek przy lądowaniu nie zawęża podpory)
			var band: float = STANCE_M * c.WP_PER_M
			var sum := 0.0
			var n := 0
			for k in range(1, tr.size()):
				if (tr[k] as Vector2).y >= low - band and (tr[k - 1] as Vector2).y >= low - band:
					sum += ((tr[k] as Vector2).x - (tr[k - 1] as Vector2).x) / DT
					n += 1
			# stopa w podporze cofa się względem ciała: -dir · prędkość stopy / prędkość postaci
			ratios.append(-dir * sum / maxf(n, 1) / speed if n > 0 else 0.0)
		var r := (float(ratios[0]) + float(ratios[1])) * 0.5
		_check("%s %s %d px/s%s: stopa w podporze %.2f × prędkości postaci (L %.2f, P %.2f; %.2f–%.2f)" % [cs[3], anim, int(speed), " tyłem" if back else "",
				r, ratios[0], ratios[1], cs[4], cs[5]], r >= float(cs[4]) and r <= float(cs[5]))
		c.free()
	_stop_start()
	print("[FOOT-SLIP] PASS (0)" if _fails == 0 else "[FOOT-SLIP] FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)


## Ruszanie i zatrzymanie (char3d.gd `_plant_foot`): prędkość zmienia się jak w player.gd (ACCEL 1100, DECEL 1500 px/s²), stan wg progu
## prędkości gracza. Sumuje przesunięcie w świecie stóp przy ziemi (w pasie 0,25 px od pozy postoju) w 50 klatkach po zatrzymaniu / 30 po
## ruszeniu, przy kilku fazach kroku. Bez blokady stóp: zatrzymanie 3–10 px, ruszanie 2–9 px (stopy sunęły do pozy postoju / biegu).
const STOP_MAX_PX := 1.0
const START_MAX_PX := 2.0


func _stop_start() -> void:
	for look in ["male_scav", "female_scav"]:
		for mode in [["run", "idle", 95.0, 10.0], ["crouch_walk", "crouch", 45.0, 8.0]]:
			var worst_stop := 0.0
			for k in 6:
				var run_n := 70 + k * 5                                 # różne fazy kroku w chwili zatrzymania
				worst_stop = maxf(worst_stop, _slide(look, mode, [[60, 0.0], [run_n, 1.0], [50, 0.0]], 60 + run_n, 50, true))
			_check("%s %s → %s: poślizg stóp po zatrzymaniu najwyżej %.2f px (≤ %.1f)" % [look, mode[0], mode[1], worst_stop, STOP_MAX_PX],
					worst_stop <= STOP_MAX_PX)
			var start := _slide(look, mode, [[60, 0.0], [40, 1.0]], 60, 30, false)
			_check("%s %s → %s: poślizg stóp przy ruszaniu %.2f px (≤ %.1f)" % [look, mode[1], mode[0], start, START_MAX_PX], start <= START_MAX_PX)


func _slide(look: String, mode: Array, prof: Array, n0: int, span: int, stop: bool) -> float:
	var c: Node2D = Char3D.new()
	root.add_child(c)
	c.setup(look, "m83")
	var v := 0.0
	var bx := 0.0
	var ys := {"LeftFoot": [], "RightFoot": []}
	var xs := {"LeftFoot": [], "RightFoot": []}
	for seg in prof:
		for i in int(seg[0]):
			var tgt := float(seg[1]) * float(mode[2])
			v = move_toward(v, tgt, (1500.0 if tgt < v else 1100.0) * DT)
			bx += v * DT
			c.update(DT, String(mode[0]) if v > float(mode[3]) else String(mode[1]), 1.0, Vector2(1.0, 0.0), v, true)
			for bone in ys:
				var p: Vector2 = c._to_px(c._gp(c._b[bone]).origin)
				(ys[bone] as Array).append(p.y)
				(xs[bone] as Array).append(p.x + bx)
	c.free()
	var slide := 0.0
	for bone in ys:
		var y: Array = ys[bone]
		var x: Array = xs[bone]
		var ground: float = y[y.size() - 1] if stop else y[n0 - 1]  # poza postoju: po zatrzymaniu / przed ruszeniem
		for i in range(n0 + 1, n0 + span):
			if float(y[i]) >= ground - 0.25 and float(y[i - 1]) >= ground - 0.25:
				slide += absf(float(x[i]) - float(x[i - 1]))
	return slide
