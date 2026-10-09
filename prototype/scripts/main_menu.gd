extends Control
## Menu główne: tytuł i trzy przyciski (PLAY → lobby, SETTINGS → ustawienia z menu pauzy, QUIT z potwierdzeniem).
## Pokazuje je main.gd po starcie, gdy gra nie hostuje / nie dołącza z linii poleceń; lobby (host / join / tryb / trudność)
## jest osobnym ekranem z przyciskiem BACK. Budowane w kodzie na wspólnym motywie (ui_theme.gd).

signal play_requested
signal settings_requested

const UiTheme := preload("res://scripts/ui_theme.gd")
const CARD_W := 300.0
const QUIT_CONFIRM_S := 3.0

var _title: Label
var _play: Button
var _quit: Button
var _quit_t := 0.0                   ## >0: QUIT czeka na potwierdzenie (drugi klik w tym czasie zamyka grę)
var _t := 0.0

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	_title = UiTheme.heading("DEAD AIR '87", 32, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	box.add_child(UiTheme.label("Co-op horror run & gun", 9, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.ACCENT, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)

	_play = _button("PLAY", func() -> void: play_requested.emit())
	box.add_child(_play)
	box.add_child(_button("SETTINGS", func() -> void: settings_requested.emit()))
	_quit = _button("QUIT", _on_quit)
	box.add_child(_quit)
	box.add_child(UiTheme.label("Esc: settings", 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_play.grab_focus())
	_play.call_deferred("grab_focus")

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 26)
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		action.call())
	return b

func _on_quit() -> void:
	if _quit_t > 0.0:
		get_tree().quit()
		return
	_quit_t = QUIT_CONFIRM_S
	_quit.text = "CLICK AGAIN TO QUIT"

func focus_first() -> void:
	_play.grab_focus()

## Tytuł lekko „migocze" (jak w lobby) — rzadkie, krótkie zaniki; „Reduce Effects" wyłączy to razem z resztą.
func _process(delta: float) -> void:
	if visible and NoiseMgr.has_network():
		visible = false                  # sesja ruszyła inną drogą niż PLAY (zaproszenie Steam, dołączenie) — menu nie może zostać na wierzchu
	if not visible:
		return
	if _quit_t > 0.0:
		_quit_t -= delta
		if _quit_t <= 0.0:
			_quit.text = "QUIT"
	_t += delta
	var dip := 0.55 if (Settings.fx_mult() > 0.0 and (fmod(_t, 7.3) < 0.09 or (fmod(_t, 11.9) > 11.7 and fmod(_t, 0.07) < 0.035))) else 1.0
	_title.modulate.a = dip
