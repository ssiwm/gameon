extends SceneTree
## Poślizg stóp w pętlach kroku (VOICE_MOCAP_PLAN.md B3): postać 3D biegnie w miejscu z prędkością gry, a stopa w podporze (najniżej,
## w pasie 2 cm nad najniższym położeniem) ma cofać się względem ciała w tempie ruchu — wtedy w świecie stoi na gruncie. Mierzy stosunek
## średniej prędkości stopy w podporze do prędkości postaci (1 = brak poślizgu) po klipie, IK i fazie kroku z `char3d.gd`, jak w widoku 3D.
##   godot --headless --path prototype -s tools/test_foot_slip.gd     → ostatni wiersz: [FOOT-SLIP] PASS / FAIL
## Bez progu poślizgu klip wyglądałby, jakby postać jechała po lodzie (stopa przesuwa się w podporze) albo drobiła w miejscu.

const Char3D := preload("res://scripts/char3d.gd")
const DT := 1.0 / 60.0
const STANCE_M := 0.02                       ## m: stopa w podporze — najwyżej tyle nad najniższym położeniem
## [stan, prędkość px/s, bieg tyłem, dolna granica stosunku, górna granica] — granice wokół stanu z 1.7.709 (bieg ok. 1,1–1,5).
## Marsz w kucaniu ślizga się z założenia: 45 px/s to ok. 3,7 m/s, a krok klipu (UAL i mocap) ma ok. 0,55 m przy ~1 cyklu/s,
## więc stopa w podporze cofa się tylko o ~0,15 prędkości postaci; próg pilnuje, żeby nie było gorzej.
const CASES := [
	["run", 95.0, false, 1.0, 1.7],
	["run", 70.0, false, 0.8, 1.4],
	["run", 95.0, true, 1.0, 1.7],
	["crouch_walk", 45.0, false, 0.12, 1.6],
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
		c.setup("male_scav", "m83")
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
			var low := -INF
			for p: Vector2 in tr:
				low = maxf(low, p.y)                              # y w px rośnie w dół: najniższe położenie stopy
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
		_check("%s %d px/s%s: stopa w podporze %.2f × prędkości postaci (L %.2f, P %.2f; %.2f–%.2f)" % [anim, int(speed), " tyłem" if back else "",
				r, ratios[0], ratios[1], cs[3], cs[4]], r >= float(cs[3]) and r <= float(cs[4]))
		c.free()
	print("[FOOT-SLIP] PASS (0)" if _fails == 0 else "[FOOT-SLIP] FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
