extends Node
## Zrzuty znacznika [E] w świecie (INTERACT_KEY_PLAN.md K4): gracz staje przy stanowisku kryjówki, a znacznik przechodzi po kolei przez
## wszystkie stany — spoczynek, naciśnięcie, przytrzymanie 25 / 50 / 75 / 97%, wybuch, okruchy, oferta niemożliwa i „zakłócenie” po [E].
## Stan przytrzymania i niemożliwej oferty jest wymuszony (`view3d.ekey_force`) — stanowisko kryjówki to obiekt „naciśnij”, a chodzi o wygląd.
## Okno, override.cfg z QA. Z Movie Makerem Godota (`--write-movie`, `--fixed-fps`) daje też klatki animacji ze stałym krokiem czasu:
##
##   godot --path prototype --resolution 1600x900 --fixed-fps 30 --write-movie C:/tmp/ekey/frames/f.png -- --host --nobot --mission=z1_hub --lang=pl --ekeyshots=C:/tmp/ekey [--ekeystation=workshop]
##
## Linie `[EKEY] nazwa klatka x y` — numer klatki filmu i położenie klawisza na ekranie (do kadrowania).

const Interact := preload("res://scripts/interact.gd")

var dir := ""
var station := "workshop"
var _v3d: Node
var _p: Node2D
var _st: Node2D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ekeyshots="):
			dir = a.substr("--ekeyshots=".length())
		elif a == "--ekeyflat":
			load("res://scripts/interact_mark3d.gd").flat = true            # płaska nakładka zamiast modelu (porównanie)
		elif a.begins_with("--ekeystation="):
			station = a.substr("--ekeystation=".length())
	DirAccess.make_dir_recursive_absolute(dir)
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, false).timeout

func _force(d: Dictionary) -> void:
	_v3d.set("ekey_force", d)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("ekey_%s.png" % name))
	var mark: Node3D = _v3d.get("_imark")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var sp := Vector2(-1, -1)
	if mark != null and cam != null:
		sp = cam.unproject_position(mark.global_position)
	print("[EKEY] %s %d %.0f %.0f %s" % [name, Engine.get_frames_drawn(), sp.x, sp.y, String(mark.get("state")) if mark != null else "-"])

func _run() -> void:
	for i in 40:                                                       # poziom i widok 3D wstają pod planszą — czekaj do 20 s
		await _wait(0.5)
		_v3d = get_tree().current_scene.get_node_or_null("View3D") if get_tree().current_scene else null
		_p = Interact.local_player(get_tree())
		for n in get_tree().get_nodes_in_group(Interact.GROUP):
			if n.is_in_group(station):
				_st = n
		if _v3d != null and _p != null and _st != null:
			break
	if _v3d == null or _p == null or _st == null:
		push_error("[EKEY] brak widoku 3D (%s), gracza (%s) albo stanowiska %s (%s)" % [_v3d, _p, station, _st])
		get_tree().quit(1)
		return
	var side := 12.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ekeyside="):
			side = float(a.substr("--ekeyside=".length()))      # gracz tyle px w bok od węzła obiektu (przy krawędzi ławy: ~34)
	_p.global_position = _st.global_position + Vector2(side, -14.0)
	_p.velocity = Vector2.ZERO
	print("[EKEY] start", " ", _st.global_position)
	await _wait(3.0)
	await _shot("01_ok")
	await _wait(0.9)
	_force({"pressed": true})
	await _wait(0.07)
	await _shot("02_press")
	_force({})
	await _wait(0.9)
	# przytrzymanie: postęp 0 → 1 w 1,8 s
	var t := 0.0
	var marks := [0.25, 0.5, 0.75, 0.97]
	var names := ["03_hold25", "04_hold50", "05_hold75", "06_hold97"]
	var mi := 0
	while t < 1.8:
		var p := t / 1.8
		_force({"prog": p, "kind": Interact.Kind.HOLD})
		if mi < marks.size() and p >= marks[mi]:
			await _shot(names[mi])
			mi += 1
		await get_tree().process_frame
		t += get_process_delta_time()
	_force({"prog": 0.99, "kind": Interact.Kind.HOLD})
	await get_tree().process_frame
	_force({"prog": -1.0, "kind": Interact.Kind.HOLD})                  # koniec przytrzymania → wybuch
	await _wait(0.06)
	await _shot("07_burst")
	await _wait(0.18)
	await _shot("08_burst_sparks")
	await _wait(0.3)
	await _shot("09_embers")
	await _wait(1.2)
	_force({"muted": true})
	await _wait(0.8)
	await _shot("10_muted")
	_force({"muted": true, "pressed": true})
	await _wait(0.05)
	await _shot("11_denied")
	_force({"muted": true})
	await _wait(0.6)
	_force({})
	await _wait(1.0)
	await _shot("12_ok_again")
	print("[EKEY] PASS")
	get_tree().quit()
