extends SceneTree
## Zrzut HUD-u przy zadanej rozdzielczości okna, rozmiarze HUD-u i liczbie graczy (test układu kart):
##   godot --path prototype --rendering-driver opengl3 --script tools/shot_hud.gd -- --size=1280x720 --ui=2 --humans=4 --out=hud.png
## --ui: 0 SMALL, 1 NORMAL, 2 LARGE (nie zapisuje się do settings.cfg); --humans: ile osób w drużynie (1–4, pozostałe sloty zajmują boty
## wg zasad sesji); --down: ostatnia osoba jest powalona (wiersz DOWN); --noise=N: poziom hałasu na mierniku; --wait=N: klatki.
var _frames := 0
var _main: Node
var _out := "hud.png"
var _wait := 200
var _humans := 1
var _ui := 1
var _down := false
var _size := Vector2i(1280, 720)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
		elif a.begins_with("--humans="):
			_humans = clampi(int(a.substr(9)), 1, 4)
		elif a.begins_with("--ui="):
			_ui = clampi(int(a.substr(5)), 0, 2)
		elif a == "--down":
			_down = true
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
	root.size = _size
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.host_game()
	if _frames == 20:
		for i in range(1, _humans):
			_main._spawn_player(1000 + i)
		var st := root.get_node("Settings")
		st.ui_idx = _ui
		st.changed.emit()
	if _frames == 60 and _down and _humans > 1:
		for p in get_nodes_in_group("players"):
			if not p.is_bot and int(p.display_id) == _humans:
				p.hp = 0
				p.dead = true
				p.bleed_left = 24.0
	if _frames == _wait:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out, " size=", root.size, " ui=", _ui, " humans=", _humans, " players=", get_nodes_in_group("players").size())
		quit()
	return false
