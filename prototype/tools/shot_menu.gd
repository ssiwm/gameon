extends SceneTree
## Zrzut menu pauzy (zakładka z argumentu --tab=N, opcjonalnie --pad = przyciski pada) do pliku. Uruchamiać pod xvfb z renderer'em GL.
const Actions := preload("res://scripts/actions.gd")

var _frames := 0
var _menu: Control
var _tab := 2
var _out := "/tmp/shot.png"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tab="):
			_tab = int(a.substr(6))
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a == "--pad":
			Actions.pad_mode = true            # podpowiedzi z przyciskami pada
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	_menu = (load("res://scripts/pause_menu.gd") as GDScript).new()
	ui.add_child(_menu)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 3:
		_menu.open()
		_menu._show_tab(_tab)
	if _frames == 12:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit()
	return false
