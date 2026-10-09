extends Control
## Menu główne: tytuł i trzy przyciski (PLAY → lobby, SETTINGS → ustawienia z menu pauzy, QUIT z potwierdzeniem).
## Pokazuje je main.gd po starcie, gdy gra nie hostuje / nie dołącza z linii poleceń; lobby (host / join / tryb / trudność)
## jest osobnym ekranem z przyciskiem BACK. Budowane w kodzie na wspólnym motywie (ui_theme.gd).

signal play_requested
signal settings_requested

const UiTheme := preload("res://scripts/ui_theme.gd")
const CARD_W := 300.0
const QUIT_CONFIRM_S := 3.0

## Tło ekranu startowego: maszt radiowy z mrugającym światłem i rozchodzące się pierścienie — gra jest o nasłuchu i hałasie.
## „Reduce effects" zatrzymuje ruch pierścieni i mruganie.
class Backdrop extends Control:
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if visible:
			_t += delta * Settings.fx_mult()
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top := Color(0.03, 0.035, 0.04)
		var bottom := Color(0.075, 0.07, 0.06)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([top, top, bottom, bottom]))
		var gy := h * 0.80
		var mx := w * 0.82
		var ty := h * 0.30
		var ink := Color(UiTheme.TEXT, 0.20)
		draw_line(Vector2(0, gy), Vector2(w, gy), Color(UiTheme.TEXT, 0.10), 1.0)
		# maszt: dwie nogi, trzy poprzeczki, ramiona anteny
		draw_line(Vector2(mx - 12, gy), Vector2(mx, ty), ink, 1.5)
		draw_line(Vector2(mx + 12, gy), Vector2(mx, ty), ink, 1.5)
		for f in [0.35, 0.55, 0.78]:
			var yy: float = lerpf(ty, gy, f)
			var half: float = 12.0 * f
			draw_line(Vector2(mx - half, yy), Vector2(mx + half, yy), ink, 1.0)
		draw_line(Vector2(mx - 9, ty + 12), Vector2(mx + 9, ty + 12), ink, 1.5)
		# pierścienie: fala nadawana z czubka masztu
		var c := Vector2(mx, ty)
		for i in 4:
			var ph := fposmod(_t * 0.16 + float(i) * 0.25, 1.0)
			var a := pow(1.0 - ph, 2.0) * 0.20
			draw_arc(c, ph * w * 0.62, 0.0, TAU, 72, Color(UiTheme.TEXT, a), 1.0, true)
		# światło ostrzegawcze: krew, rzadkie mrugnięcie
		var on := 0.25 + 0.75 * clampf(sin(_t * 2.1) * 2.0, 0.0, 1.0) if Settings.fx_mult() > 0.0 else 0.8
		draw_circle(c, 3.2, Color(UiTheme.DANGER, 0.18 * on))
		draw_circle(c, 1.6, Color(UiTheme.DANGER, 0.95 * on))

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
	add_child(Backdrop.new())
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
