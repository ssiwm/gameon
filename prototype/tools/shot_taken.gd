extends SceneTree
## Zrzut strzałki ku porwanemu graczowi i smugi krwi (Żerca, F4d): bot towarzysz pada, zostaje „porwany" i odciągnięty w prawo poza kadr,
## a co klatkę przesuwany jak przez Żercę (smuga). Dwa zrzuty: KATALOG/taken_trail.png (ofiara jeszcze w kadrze — widać smugę) i
## KATALOG/taken_arrow.png (ofiara poza kadrem — strzałka na krawędzi).
##   godot --path prototype --script tools/shot_taken.gd -- --view3dlit --mission=z1_m2 --dir=KATALOG
var _frames := 0
var _main: Node
var _dir := "/tmp/shots"
var _bot: Node2D
var _me: Node2D
var _x0 := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.host_game()
	if _frames == 90:
		for p in get_nodes_in_group("players"):
			if p.is_bot:
				_bot = p
			elif p.is_multiplayer_authority():
				_me = p
		if _bot == null or _me == null:
			print("brak bota albo gracza")
			quit()
			return false
		_bot.set_physics_process(false)
		_bot.call("_go_down")
		_x0 = _me.global_position.x + 40.0
	if _frames > 92 and _bot != null:
		# ciągnięcie: 3 px na klatkę w prawo, po ziemi pod graczem
		var x := _x0 + float(_frames - 92) * 3.0
		_bot.apply_take(true, Vector2(x, _me.global_position.y), maxf(1.0, 20.0 - float(_frames - 92) / 60.0))
	if _frames == 150:
		root.get_texture().get_image().save_png("%s/taken_trail.png" % _dir)
		print("saved trail")
	if _frames == 330:
		root.get_texture().get_image().save_png("%s/taken_arrow.png" % _dir)
		print("saved arrow")
		quit()
	return false
