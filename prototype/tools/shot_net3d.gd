extends SceneTree
## Test widoku sieciowego postaci 3D: dwa okna (host i klient) — każde zapisuje zrzut i wypisuje stan graczy (czy mają model 3D, broń, wygląd).
## godot --path prototype --script tools/shot_net3d.gd -- --host --port=8980 --out=/tmp/h.png --act     (host strzela i przeładowuje)
## godot --path prototype --script tools/shot_net3d.gd -- --join=127.0.0.1 --port=8980 --out=/tmp/c.png  (klient tylko patrzy)
var _f := 0
var _m: Node
var _out := "/tmp/net3d.png"
var _act := false
var _wait := 360
var _watch := false
var _seen := {}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--watch":
			_watch = true
		elif a == "--act":
			_act = true
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
	_m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_m)
	current_scene = _m
func _press(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)

func _process(_d: float) -> bool:
	_f += 1
	if _act:                                                     # pętla co 300 klatek: ruch, ogień, przeładowanie
		var k := _f % 300
		_press("move_right", k > 100 and k < 140)
		_press("fire", k > 150 and k < 200)
		_press("reload", k > 220 and k < 226)
	if _watch:                                                   # klient: zrzut, gdy ZDALNY człowiek strzela / przeładowuje
		for p in get_nodes_in_group("players"):
			if p.is_bot or p.is_multiplayer_authority():
				continue
			if p.w_firing and not _seen.has("fire") and _f > 120:
				_seen["fire"] = true
				root.get_texture().get_image().save_png(_out.replace(".png", "_fire.png"))
				print("remote FIRE seen f=", _f)
			if p.w_state == 2 and not _seen.has("reload") and _f > 120:
				_seen["reload"] = true
				root.get_texture().get_image().save_png(_out.replace(".png", "_reload.png"))
				print("remote RELOAD seen f=", _f)
	if _f == _wait - 20 or _f == _wait:
		var s := ""
		for p in get_nodes_in_group("players"):
			var c = p.c3d
			s += "[id=%s bot=%s local=%s c3d=%s gun=%s look=%s w=%s st=%s pos=%s] " % [p.display_id, p.is_bot, p.is_multiplayer_authority(), c != null, (c._gun_key if c != null else "-"), p.look, p.weapon, p.w_state, p.global_position.snapped(Vector2(1, 1))]
		print("NET3D f=", _f, " ", s)
	if _f == _wait:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
