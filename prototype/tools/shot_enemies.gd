extends SceneTree
## Teleportuje lokalnego gracza do wrogów każdego rodzaju i robi zrzuty.
var _frames := 0
var _main: Node
var _dir := "/tmp/shots"
var _queue: Array = []
var _cur := -1
var _wait_until := 0
var _targets := {}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
func _local_player() -> Node:
	for p in get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p
	return null
func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.host_game()
	if _frames == 30:
		_main.get_node("Darkness").color = Color(1, 1, 1)
		_main.get_node("UI/HUD").visible = false
	if _frames == 60:
		_main.get_node("UI/HUD").visible = false
		for e in get_nodes_in_group("enemies"):
			var k: String = String(e.get("kind")) if e.get("kind") != null else ""
			if e.is_in_group("boss"):
				k = "boss"
			elif e.get_script() != null and String(e.get_script().resource_path).ends_with("nest.gd"):
				k = "nest"
			if k != "" and not _targets.has(k):
				_targets[k] = e
		print("targets: ", _targets.keys())
		_queue = _targets.keys()
		_cur = -1
		_wait_until = _frames
	if _frames > 60 and _frames >= _wait_until:
		if _cur >= 0:
			var k: String = _queue[_cur]
			root.get_texture().get_image().save_png("%s/%s.png" % [_dir, k])
			print("saved ", k)
		_cur += 1
		if _cur >= _queue.size():
			quit()
			return false
		var e: Node2D = _targets[_queue[_cur]]
		var p := _local_player() as Node2D
		if p != null and is_instance_valid(e):
			p.global_position = e.global_position + Vector2(-70, 0)
			p.velocity = Vector2.ZERO
		_wait_until = _frames + 40
	return false
