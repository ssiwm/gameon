extends Control
## Menu pauzy (Esc / P): ustawienia, bestiariusz, opisy broni i ściąga sterowania (zakładki). Budowane w kodzie na wspólnym motywie.
##
## Gra solo (żaden zdalny gracz) jest naprawdę zatrzymywana. W kooperacji świat idzie dalej — host jest
## autorytetem, a zatrzymanie go zamroziłoby kolegów — i menu mówi to wprost. Na czas menu akcje gry
## są wycięte z InputMap (Settings.block_game_input), więc klik w przycisk nie strzela.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")
const Codex := preload("res://scripts/codex.gd")
const CodexPage := preload("res://scripts/codex_page.gd")

const CARD_W := 450.0
const PAGE_H := 270.0                ## stała wysokość zakładek — karta nie skacze przy przełączaniu
const TABS := ["SETTINGS", "BESTIARY", "WEAPONS", "GEAR", "PERKS", "CONTROLS"]
const BASE_SCALE := 0.7              ## jak HUD (hud.gd UI_SCALE): menu rysowane w 70%, razem z ustawieniem HUD SIZE

var _settings_page: VBoxContainer
var _controls_page: VBoxContainer
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _tab := 0
var _sub: Label
var _values := {}                    ## klucz → Label z bieżącą wartością
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _open := false
var _resume: Button
var _rebind_list: VBoxContainer
var _rebind_msg: Label
var _cap := {}                       ## trwające przypisywanie: id, dev, btn, text

func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS       # menu działa także przy zatrzymanym drzewie (solo)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	visible = false
	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_fit)
	_fit()

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	var card_bg := UiTheme.panel_box()
	card_bg.bg_color.a = 1.0                       # pełne krycie: napisy świata (tablice, ściana wyników) nie prześwitują przez opisy
	card.add_theme_stylebox_override("panel", card_bg)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	box.add_child(UiTheme.heading("PAUSED", 24, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_sub = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_sub)
	box.add_child(_rule())

	# zakładki
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	for i in TABS.size():
		var tb := Button.new()
		_compact(tb)
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	box.add_child(tabs)

	_settings_page = VBoxContainer.new()
	_settings_page.add_theme_constant_override("separation", 3)
	_build_settings()
	_controls_page = VBoxContainer.new()
	_build_controls()
	# kolejność = TABS; bestiariusz i bronie powstają przy pierwszym otwarciu zakładki
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, PAGE_H)
	box.add_child(holder)
	var bestiary := CodexPage.new()
	var arsenal := CodexPage.new()
	var gear := CodexPage.new()
	var perks := CodexPage.new()
	_pages = [_settings_page, bestiary, arsenal, gear, perks, _controls_page]
	for p in _pages:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		holder.add_child(p)
	bestiary.setup(Codex.bestiary())
	arsenal.setup(Codex.arsenal())
	gear.setup(Codex.gear())
	perks.setup(Codex.perks())

	box.add_child(_rule())
	var btns := HBoxContainer.new()
	var resume := Button.new()
	_resume = resume
	resume.text = "RESUME"
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.pressed.connect(close)
	btns.add_child(resume)
	var quit := Button.new()
	quit.text = "QUIT GAME"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.tooltip_text = "Closes the game (your squad keeps playing if you are the client)"
	quit.pressed.connect(func() -> void:
		close()
		get_tree().quit())
	btns.add_child(quit)
	box.add_child(btns)
	Settings.changed.connect(_refresh)
	Voice.changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if _open:
		close()

## Rozmiar logiczny = viewport / skala (tak samo jak HUD), żeby menu mieściło się na ekranie.
func _fit() -> void:
	var k := BASE_SCALE * Settings.ui_mult()
	scale = Vector2(k, k)
	size = get_viewport_rect().size / k

# ---------------------------------------------------------------- budowa

func _build_settings() -> void:
	_settings_page.add_child(_caption("AUDIO"))
	_stepper("master", "Master volume")
	_stepper("music", "Music & ambience")
	_stepper("sfx", "Effects")
	_settings_page.add_child(_caption("GAMEPLAY"))
	_cycler("shake", "Screen shake", Settings.cycle_shake)
	_cycler("wfx", "Weather effects", Settings.cycle_weather_fx)
	_cycler("hints", "Tips for new players", Settings.toggle_hints)
	_cycler("mic", "Microphone scream", Voice.cycle)
	_settings_page.add_child(_caption("DISPLAY"))
	_cycler("ui", "HUD size", Settings.cycle_ui)
	_cycler("full", "Fullscreen  (%s)" % Actions.text("fullscreen"), Settings.toggle_fullscreen)
	_cycler("hd", "Graphics (restart)", Settings.toggle_hd)
	_cycler("c3d", "Characters (restart)", Settings.toggle_char3d)

## Wiersz: opis po lewej, [−] wartość [+] po prawej.
func _stepper(kind: String, text: String) -> void:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, 9, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_small_button("−", func() -> void:
		Settings.set_volume(kind, float(Settings.volume[kind]) - Settings.STEP)))
	var v := UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(38, 0)
	_values[kind] = v
	row.add_child(v)
	row.add_child(_small_button("+", func() -> void:
		Settings.set_volume(kind, float(Settings.volume[kind]) + Settings.STEP)))
	_settings_page.add_child(row)

## Wiersz: opis po lewej, przycisk przełączający po prawej.
func _cycler(key: String, text: String, action: Callable) -> void:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, 9, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	_compact(b)
	b.custom_minimum_size = Vector2(96, 0)
	b.pressed.connect(func() -> void:
		action.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	_values[key] = b
	row.add_child(b)
	_settings_page.add_child(row)

func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	_compact(b)
	b.text = text
	b.custom_minimum_size = Vector2(22, 0)
	b.pressed.connect(func() -> void:
		action.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	return b

## Zakładka CONTROLS: lista akcji z przyciskami klawisza i pada. Klik → „press a key…" → następny klawisz (Esc anuluje) trafia do
## akcji; ten sam klawisz miała inna akcja? — zamieniają się miejscami. Zapis w settings.cfg, RESET przywraca domyślne.
func _build_controls() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, PAGE_H - 44.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_page.add_child(scroll)
	_rebind_list = VBoxContainer.new()
	_rebind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebind_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_rebind_list)
	var foot := HBoxContainer.new()
	_rebind_msg = UiTheme.label("Click a key, then press the new one  (Esc cancels)", 8, UiTheme.MUTED)
	_rebind_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_rebind_msg)
	var reset := Button.new()
	_compact(reset)
	reset.text = "RESET TO DEFAULTS"
	reset.pressed.connect(func() -> void:
		_cancel_capture()
		Actions.reset_defaults()
		_rebind_msg.text = "All controls reset to defaults."
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	foot.add_child(reset)
	_controls_page.add_child(foot)
	_fill_rebind()
	Settings.bindings_changed.connect(_fill_rebind)
	InputSetup.device_changed.connect(func(_pad: bool) -> void: _fill_rebind())

func _fill_rebind() -> void:
	_cap = {}
	for c in _rebind_list.get_children():
		_rebind_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	var h0 := UiTheme.label("ACTION", 7, UiTheme.ACCENT.darkened(0.15))
	h0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h0)
	var h1 := UiTheme.label("KEYBOARD / MOUSE", 7, UiTheme.ACCENT.darkened(0.15), HORIZONTAL_ALIGNMENT_CENTER)
	h1.custom_minimum_size = Vector2(118, 0)
	head.add_child(h1)
	var h2 := UiTheme.label("PAD", 7, UiTheme.ACCENT.darkened(0.15), HORIZONTAL_ALIGNMENT_CENTER)
	h2.custom_minimum_size = Vector2(92, 0)
	head.add_child(h2)
	_rebind_list.add_child(head)
	for id in Actions.rebindable():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var l := UiTheme.label(Actions.label_of(id), 8, UiTheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_rebind_button(id, Actions.DEV_KEY, 118.0))
		row.add_child(_rebind_button(id, Actions.DEV_PAD, 92.0))
		_rebind_list.add_child(row)

func _rebind_button(id: String, dev: int, w: float) -> Button:
	var b := Button.new()
	_compact(b)
	b.custom_minimum_size = Vector2(w, 0)
	b.clip_text = true
	b.text = Actions.text(id, false, dev)
	if dev == Actions.DEV_PAD and not Actions.pad_rebindable(id):
		b.disabled = true                        # drążki ruchu i celowania mają stałe osie
		b.tooltip_text = "Fixed"
	else:
		b.tooltip_text = "Click, then press the new %s" % ("key" if dev == Actions.DEV_KEY else "pad button")
		b.pressed.connect(_start_capture.bind(id, dev, b))
	return b

func _start_capture(id: String, dev: int, b: Button) -> void:
	_cancel_capture()
	_cap = {"id": id, "dev": dev, "btn": b, "text": b.text}
	b.text = "press a key…" if dev == Actions.DEV_KEY else "press a button…"
	_rebind_msg.text = "%s: press the new %s  (Esc cancels)" % [Actions.label_of(id), "key" if dev == Actions.DEV_KEY else "pad button"]
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _cancel_capture() -> void:
	if not _cap.is_empty() and is_instance_valid(_cap["btn"]):
		(_cap["btn"] as Button).text = String(_cap["text"])
	_cap = {}

## Zdarzenie dla trwającego przypisywania; true = zużyte.
func _capture_event(event: InputEvent) -> bool:
	if _cap.is_empty():
		return false
	var dev: int = _cap["dev"]
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	if dev == Actions.DEV_KEY and is_key:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			_rebind_msg.text = "Cancelled."
			return true
		return _finish_capture(event)
	if dev == Actions.DEV_PAD and (event is InputEventJoypadButton and event.pressed or event is InputEventJoypadMotion):
		var res := Actions.binding_from_event(event, dev)
		if not res.is_empty():
			return _finish_capture(event)
		return event is InputEventJoypadButton
	if is_key and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_cancel_capture()                        # Esc anuluje też przypisywanie pada
		_rebind_msg.text = "Cancelled."
		return true
	return false

func _finish_capture(event: InputEvent) -> bool:
	var id: String = _cap["id"]
	var dev: int = _cap["dev"]
	var res := Actions.set_binding(id, dev, event)
	if bool(res["ok"]):
		var sw := String(res["swapped"])
		_rebind_msg.text = "%s → %s" % [Actions.label_of(id), Actions.text(id, true, dev)] + ("   (swapped with %s)" % Actions.label_of(sw) if sw != "" else "")
		Audio.play("ui_confirm", Audio.BUS_UI, -8.0)
	else:
		_cancel_capture()
		_rebind_msg.text = "That key cannot be used here."
	return true

## Niższy przycisk (mniejsze marginesy pionowe) — wiersze ustawień nie rozpychają karty.
func _compact(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = theme.get_stylebox(state, "Button").duplicate()
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_font_size_override("font_size", 9)

func _caption(text: String) -> Label:
	return UiTheme.label(text, 7, UiTheme.ACCENT.darkened(0.15))

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.10)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------------------------------------------------------- stan

func _refresh() -> void:
	for kind in Settings.volume:
		_values[kind].text = "%d%%" % int(round(float(Settings.volume[kind]) * 100.0))
	_values["shake"].text = Settings.SHAKE_NAMES[Settings.shake_idx]
	_values["wfx"].text = Settings.WEATHER_FX_NAMES[Settings.weather_fx_idx]
	_values["hints"].text = "ON" if Settings.hints_on else "OFF"
	_values["mic"].text = Voice.label().replace("MIC: ", "")
	_values["ui"].text = Settings.UI_NAMES[Settings.ui_idx]
	_values["full"].text = "ON" if Settings.fullscreen else "OFF"
	_values["hd"].text = "HD" if Settings.graphics_hd else "CLASSIC"
	_values["c3d"].text = "3D (BETA)" if Settings.char3d else "SPRITES"

func _show_tab(i: int) -> void:
	_tab = i
	for j in _pages.size():
		_pages[j].visible = j == i
		_tab_buttons[j].set_pressed_no_signal(j == i)

func _lobby_visible() -> bool:
	var lobby := get_node_or_null("../Lobby") as Control
	return lobby != null and lobby.visible

func _solo() -> bool:
	return multiplayer.get_peers().is_empty()

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_sub.text = "The game is paused." if _solo() else "The game keeps running — your squad is still out there."
	get_tree().paused = _solo()
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_tab(_tab)
	_resume.grab_focus()                            # pad / klawiatura: nawigacja fokusem od przycisku RESUME
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func close() -> void:
	if not _open:
		return
	_open = false
	_cancel_capture()
	visible = false
	get_tree().paused = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(_delta: float) -> void:
	# ktoś dołączył do zatrzymanej gry solo — świat musi ruszyć
	if _open and get_tree().paused and not _solo():
		get_tree().paused = false
		_sub.text = "The game keeps running — your squad is still out there."

func _input(event: InputEvent) -> void:
	if _open and _capture_event(event):
		get_viewport().set_input_as_handled()
		return
	if _open and event is InputEventJoypadButton:
		# pad: B zamyka, LB / RB przełączają zakładki (D-pad / drążek i A działają przez fokus kontrolek)
		if event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
			return
		var dir := 1 if event.is_action_pressed("menu_tab") else (-1 if event.is_action_pressed("menu_tab_prev") else 0)
		if dir != 0:
			_show_tab((_tab + dir + TABS.size()) % TABS.size())
			Audio.play("ui_click", Audio.BUS_UI, -10.0)
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("pause"):
		return
	var ws := get_tree().get_first_node_in_group("workshop_ui")
	if ws != null and ws.is_open():
		return                                  # Esc zamyka panel warsztatu (workshop_ui.gd), nie otwiera pauzy
	if _open:
		close()
	elif NoiseMgr.has_network() and not _lobby_visible():     # w lobby Esc nic nie robi
		open()
	else:
		return
	get_viewport().set_input_as_handled()
