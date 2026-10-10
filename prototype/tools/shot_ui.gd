extends SceneTree
## Zrzut ekranu menu do pliku: `--screen=main|lobby|pause` (`--tab=N` dla pauzy: 0 ustawienia … 5 sterowanie), `--pad` (podpowiedzi
## z przyciskami pada), `--out=PLIK.png`. Okno z renderowaniem:
##   godot --path prototype --rendering-driver opengl3 --script tools/shot_ui.gd -- --screen=main --out=main.png
## `--ui=0|1|2` ustawia rozmiar HUD-u (SMALL / NORMAL / LARGE) na czas zrzutu.
const Actions := preload("res://scripts/actions.gd")

var _frames := 0
var _screen := "main"
var _tab := 0
var _out := "shot.png"
var _node: Control
var _pause: Control
var _ui := -1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			_screen = a.substr(9)
		elif a.begins_with("--tab="):
			_tab = int(a.substr(6))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--pad":
			Actions.pad_mode = true
		elif a.begins_with("--ui="):
			_ui = clampi(int(a.substr(5)), 0, 2)          # rozmiar HUD: 0 SMALL, 1 NORMAL, 2 LARGE (bez zapisu)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	match _screen:
		"lobby":
			_node = (load("res://scripts/lobby.gd") as GDScript).new()
			ui.add_child(_node)
			_node.size = root.get_visible_rect().size
			_node.call_deferred("set_back_enabled", true)
		"pause":
			_pause = (load("res://scripts/pause_menu.gd") as GDScript).new()
			ui.add_child(_pause)
		_:
			_node = (load("res://scripts/main_menu.gd") as GDScript).new()
			ui.add_child(_node)
			_node.size = root.get_visible_rect().size

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2 and _ui >= 0:
		var st := root.get_node("Settings")     # autoload wczytuje settings.cfg dopiero po _initialize — ustawiamy po nim
		st.ui_idx = _ui
		st.changed.emit()
	if _frames == 3 and _pause != null:
		_pause.open()
		_pause._show_tab(_tab)
	if _frames == 12:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit()
	return false
