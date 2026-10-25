extends Control
## Ekran kalibracji jasności (ustawienie `Settings.brightness_idx`, ±1 EV). Trzy symbole oka na czystej czerni mają stałe jasności
## liniowe tuż przy progu, poniżej którego obraz nocy zapada się w czerń, i są renderowane przez tę samą gradację co świat gry
## (`Level3D.apply_grade`: tonemapping, kontrast, ekspozycja) — więc to, co gracz widzi na karcie, odpowiada nocy w grze na jego
## monitorze. Gracz zmienia jasność, aż środkowe oko jest ledwo widoczne, a lewe znika.
##
## Otwiera go menu główne przy pierwszym starcie (`Settings.brightness_calibrated`) i wiersz „Brightness” w ustawieniach. CONFIRM
## zapisuje, CANCEL / Esc przywraca wartość sprzed otwarcia. Współrzędne w pikselach makiety 1280×720 (jak pause_menu.gd).

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Level3D := preload("res://scripts/level3d.gd")

signal closed

const REF_SCALE := 0.5
const CARD_SIZE := Vector2(880, 560)
## Jasności liniowe symboli. Strojone `tools/probe_tonemap.gd`: przy 0 EV dają ok. 0, 6 i 20 na 255 — lewe tuż pod progiem czerni,
## środkowe tuż nad nim. Krok ±0,5 EV przesuwa próg mniej więcej o jeden symbol.
const LEVELS := [0.003, 0.005, 0.012]
const LABELS := ["NOT VISIBLE", "BARELY VISIBLE", "CLEARLY VISIBLE"]
const EYE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float level = 0.005;            // jasność liniowa (przed tonemappingiem)
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float lens = max(length(p - vec2(0.0, 0.55)) - 0.95, length(p + vec2(0.0, 0.55)) - 0.95);    // migdał oka
	float d = max(lens, 0.22 - length(p));                                                          // źrenica wycięta do czerni
	float aa = fwidth(d);
	ALBEDO = vec3(level * (1.0 - smoothstep(-aa, aa, d)));
}
"""

var _env: Environment
var _slider: HSlider
var _value: Label
var _start_idx := 0
var _first_run := false

## `first_run`: pierwszy start gry — bez przycisku CANCEL (Esc i tak zostawia domyślną jasność i nie pyta ponownie).
func setup(first_run := false) -> void:
	_first_run = first_run

func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_start_idx = Settings.brightness_idx
	get_viewport().size_changed.connect(_fit)
	_fit()

	var black := ColorRect.new()
	black.color = Color.BLACK                         # czysta czerń: symbole porównuje się z nią, nie z grą w tle
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = CARD_SIZE
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	col.add_child(W.stencil(tr("BRIGHTNESS"), 30, UiTheme.TEXT, 0.12, HORIZONTAL_ALIGNMENT_CENTER))
	var help := W.body(tr("Adjust until the middle eye is barely visible and the left one disappears. Darkness is part of the game — set it for your screen, not brighter."), 16, UiTheme.BONE_DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(help)

	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(CARD_SIZE.x, 200)
	col.add_child(view)
	view.add_child(_build_card())
	var labels := HBoxContainer.new()
	for t in LABELS:
		var l := W.mono(tr(t), 13, UiTheme.MUTED, 0.06, HORIZONTAL_ALIGNMENT_CENTER)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.add_child(l)
	col.add_child(labels)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(W.mono(tr("DARKER"), 13, UiTheme.MUTED, 0.06))
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = Settings.BRIGHTNESS_EV.size() - 1
	_slider.step = 1
	_slider.tick_count = Settings.BRIGHTNESS_EV.size()
	_slider.ticks_on_borders = true
	_slider.custom_minimum_size = Vector2(420, 20)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value = Settings.brightness_idx
	_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_brightness(int(v))
		Audio.play("ui_click", Audio.BUS_UI, -14.0))
	row.add_child(_slider)
	row.add_child(W.mono(tr("BRIGHTER"), 13, UiTheme.MUTED, 0.06))
	_value = W.mono("", 14, UiTheme.TEXT, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_value.custom_minimum_size = Vector2(90, 0)
	row.add_child(_value)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	var reset := Button.new()
	reset.text = tr("DEFAULT")
	W.style_button(reset, "secondary", 20)
	reset.pressed.connect(func() -> void: _slider.value = Settings.BRIGHTNESS_DEFAULT)
	foot.add_child(reset)
	if not _first_run:
		var cancel := Button.new()
		cancel.text = tr("CANCEL")
		W.style_button(cancel, "secondary", 20)
		cancel.pressed.connect(_cancel)
		foot.add_child(cancel)
	var ok := Button.new()
	ok.text = tr("CONFIRM")
	W.style_button(ok, "primary", 22)
	ok.pressed.connect(_confirm)
	foot.add_child(ok)

	Settings.changed.connect(_refresh)
	_refresh()
	_slider.grab_focus()                              # strzałki / pad od razu zmieniają jasność
	UiTheme.fade_in(col)

func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(REF_SCALE * Settings.ui_rel(), vp.y / (CARD_SIZE.y + 40.0))
	scale = Vector2(k, k)
	size = vp / k

## Karta 3D: trzy symbole (nieoświetlone, stała jasność liniowa) na czarnym tle, kamera ortogonalna, gradacja świata gry.
func _build_card() -> SubViewport:
	var vp := SubViewport.new()
	vp.transparent_bg = false
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 7.2
	cam.position = Vector3(0.0, 0.0, 5.0)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	Level3D.apply_grade(_env, Settings.exposure_mult())
	cam.environment = _env
	vp.add_child(cam)
	var sh := Shader.new()
	sh.code = EYE_SHADER
	for i in LEVELS.size():
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.9, 1.9)
		q.mesh = qm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("level", float(LEVELS[i]))
		q.material_override = m
		q.position = Vector3((i - 1) * 2.4, 0.0, 0.0)
		vp.add_child(q)
	return vp

func _refresh() -> void:
	if _env != null:
		_env.tonemap_exposure = Settings.exposure_mult()
	_slider.set_value_no_signal(Settings.brightness_idx)
	var ev := Settings.brightness_ev()
	_value.text = "0 EV" if is_zero_approx(ev) else "%+.2f EV" % ev

func _confirm() -> void:
	Settings.mark_brightness_calibrated()
	Audio.play("ui_confirm", Audio.BUS_UI, -8.0)
	_close()

func _cancel() -> void:
	if Settings.brightness_idx != _start_idx:
		Settings.set_brightness(_start_idx)
	if _first_run:
		Settings.mark_brightness_calibrated()          # pierwszy start: Esc zostawia domyślną jasność i nie pyta przy następnym
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_close()

func _close() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and get_viewport().gui_get_focus_owner() == _slider:
		_confirm()
		get_viewport().set_input_as_handled()
