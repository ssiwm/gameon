extends SceneTree
var _frames := 0
var _main: Node
var _out := "/tmp/game.png"
var _wait := 150
var _open_menu := false
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--wait="):
			_wait = int(a.substr(7))
		if a == "--menu":
			_open_menu = true
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.host_game()
	if _frames == _wait - 20 and _open_menu:
		_main.get_node("UI/PauseMenu").open()
	if _frames == _wait:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
