extends Node
## Rejestruje akcje wejściowe w kodzie, żeby project.godot był prosty.

func _enter_tree() -> void:
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("move_up", [KEY_W, KEY_UP])
	_add_keys("move_down", [KEY_S, KEY_DOWN])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("fire", [KEY_J])
	_add_keys("crouch", [KEY_SHIFT])
	_add_keys("overcharge", [KEY_Q])
	_add_keys("scream", [KEY_G])
	_add_keys("flare", [KEY_F])
	_add_keys("interact", [KEY_E])
	_add_keys("weapon_1", [KEY_1])
	_add_keys("weapon_2", [KEY_2])
	_add_keys("weapon_3", [KEY_3])
	_add_keys("restart", [KEY_ENTER, KEY_KP_ENTER])
	_add_keys("flashlight", [KEY_L])
	_add_keys("reload", [KEY_R])
	_add_keys("firemode", [KEY_B])
	_add_keys("throw", [KEY_T])
	_add_keys("throw_next", [KEY_X])
	_add_keys("melee", [KEY_V])
	_add_keys("help", [KEY_F1])
	_add_keys("pause", [KEY_ESCAPE, KEY_P])
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("melee", MOUSE_BUTTON_RIGHT)
	_add_mouse("weapon_next", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse("weapon_prev", MOUSE_BUTTON_WHEEL_UP)

func _add_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _add_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
