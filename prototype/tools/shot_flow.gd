extends SceneTree
## Test przepływu ekranów na prawdziwej scenie gry (okno z renderowaniem, bez flag --host / --join):
## menu główne → GRAJ → lobby → HOSTUJ → gra. Zapisuje zrzut po każdym kroku do `--out=KATALOG` i drukuje [FLOW] PASS / FAIL.
##   godot --path prototype --rendering-driver opengl3 --script tools/shot_flow.gd -- --out=C:/tmp/flow
var _frames := 0
var _main: Node
var _out := "."
var _fail := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])

func _check(label: String, ok: bool) -> void:
	print("[FLOW] %s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fail += 1

func _process(_d: float) -> bool:
	_frames += 1
	var menu: Control = _main.get_node_or_null("UI/MainMenu")
	var lobby: Control = _main.get_node("UI/Lobby")
	match _frames:
		30:
			_check("start: menu główne widoczne, lobby ukryte", menu != null and menu.visible and not lobby.visible)
			_shot("1_main_menu")
			if menu != null:
				menu.play_requested.emit()
		60:
			_check("GRAJ: lobby widoczne, menu ukryte", lobby.visible and menu != null and not menu.visible)
			_shot("2_lobby")
			lobby.back_requested.emit()
		80:
			_check("WSTECZ: menu z powrotem", menu.visible and not lobby.visible)
			menu.play_requested.emit()
		100:
			lobby.host_requested.emit()
		260:
			_check("HOSTUJ: sesja trwa, lobby i menu ukryte", root.get_node("NoiseMgr").has_network() and not lobby.visible and not menu.visible)
			_shot("3_game")
			var pm: Control = _main.get_node("UI/PauseMenu")
			pm.open()
		290:
			_shot("4_pause_in_game")
			print("[FLOW] %s (%d błędów)" % ["PASS" if _fail == 0 else "FAIL", _fail])
			quit(1 if _fail > 0 else 0)
	return false
