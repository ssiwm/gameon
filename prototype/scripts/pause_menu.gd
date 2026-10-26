extends Control
## Menu pauzy (Esc / P / Start) w stylu makiety Pause.dc.html: panel „deck” 900×592, nagłówek (PAUSED + misja i czas, chip
## „świat idzie dalej”), lewa nawigacja sekcji, siatka ustawień w dwóch kolumnach (suwaki, przełączniki, segmenty), stopka
## z przyciskami (RESUME primary, LEAVE SESSION secondary, QUIT GAME danger z potwierdzeniem).
##
## Współrzędne w pikselach referencyjnego ekranu 1280×720: korzeń jest skalowany tak, żeby 1 jednostka = 1 piksel makiety.
## Gra solo (żaden zdalny gracz) jest naprawdę zatrzymywana. W kooperacji świat idzie dalej — host jest autorytetem,
## a zatrzymanie go zamroziłoby kolegów — i menu mówi to wprost. Na czas menu akcje gry są wycięte z InputMap
## (Settings.block_game_input), więc klik w przycisk nie strzela.

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Actions := preload("res://scripts/actions.gd")
const Codex := preload("res://scripts/codex.gd")
const CodexPage := preload("res://scripts/codex_page.gd")
const BrightnessScreen := preload("res://scripts/brightness_screen.gd")

signal leave_requested               ## „LEAVE SESSION": main.gd kończy sesję i wraca do ekranu startowego

const QUIT_CONFIRM_S := 3.0
const REF_SCALE := 0.5               ## viewport 640×360 → 1280×720 jednostek makiety
const CARD_SIZE := Vector2(900, 648)
const TABS := ["SETTINGS", "BESTIARY", "WEAPONS", "GEAR", "PERKS", "CONTROLS"]
const CODEX_K := 1.6                 ## strony kodeksu i sterowania powstały dla skali 0,8 (1 jednostka = 1,6 px makiety)

var _pages: Array[Control] = []
var _nav: Array = []
var _tab := 0
var _sub: Label
var _title: Label
var _chip_holder: HBoxContainer
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _open := false
var _resume: Button
var _card: PanelContainer
var _leave: Button
var _copy_id: Button
var _quit: Button
var _hint: Label
var _quit_t := 0.0                   ## >0: QUIT czeka na potwierdzenie
var _refreshers: Array[Callable] = []
var _rebind_list: VBoxContainer
var _rebind_msg: Label
var _pending_plan := {}
var _confirm_controls: ConfirmationDialog
var _profile_label: Label
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
	dim.color = Color(0.012, 0.016, 0.012, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = CARD_SIZE
	var deck := StyleBoxFlat.new()
	deck.bg_color = Color(7.0 / 255.0, 8.0 / 255.0, 7.0 / 255.0, 0.97)
	deck.border_color = UiTheme.LINE
	deck.set_border_width_all(1)
	deck.border_width_top = 1
	deck.shadow_size = 40
	deck.shadow_color = Color(0, 0, 0, 0.6)
	deck.shadow_offset = Vector2(0, 20)
	deck.set_content_margin_all(0)
	_card.add_theme_stylebox_override("panel", deck)
	center.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)

	col.add_child(_build_header())
	col.add_child(W.hairline())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_nav())
	body.add_child(W.vline())
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	body.add_child(holder)
	_build_pages(holder)
	col.add_child(W.hairline())
	col.add_child(_build_footer())

	Settings.changed.connect(_refresh)
	Voice.changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if _open:
		close()

## Korzeń skalujemy tak, żeby przy standardowym rozmiarze HUD 1 jednostka = 1 piksel makiety 1280×720.
func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(REF_SCALE * Settings.ui_rel(), vp.y / (CARD_SIZE.y + 24.0))     # duży HUD nie wypycha karty poza ekran
	scale = Vector2(k, k)
	size = vp / k

# ---------------------------------------------------------------- budowa

func _build_header() -> Control:
	var h := MarginContainer.new()
	h.add_theme_constant_override("margin_left", 26)
	h.add_theme_constant_override("margin_right", 26)
	h.add_theme_constant_override("margin_top", 16)
	h.add_theme_constant_override("margin_bottom", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	h.add_child(row)
	_title = W.stencil("PAUSED", 44, UiTheme.TEXT, 0.1, HORIZONTAL_ALIGNMENT_LEFT, 900)
	row.add_child(_title)
	_sub = W.mono("", 12, UiTheme.MUTED, 0.16)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_chip_holder = HBoxContainer.new()
	_chip_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chip_holder)
	return h

func _build_nav() -> Control:
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(196, 0)
	nav.add_theme_constant_override("separation", 2)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	m.add_child(nav)
	for i in TABS.size():
		var it := W.NavItem.new()
		it.kind = i
		it.label = tr(TABS[i])
		it.pressed.connect(func() -> void:
			_show_tab(i)
			Audio.play("ui_click", Audio.BUS_UI, -10.0))
		nav.add_child(it)
		_nav.append(it)
	return m

func _build_pages(holder: Control) -> void:
	var settings_scroll := ScrollContainer.new()
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	_build_settings(settings_scroll)
	var bestiary := CodexPage.new()
	var arsenal := CodexPage.new()
	var gear := CodexPage.new()
	var perks := CodexPage.new()
	bestiary.setup(Codex.bestiary())
	arsenal.setup(Codex.arsenal())
	gear.setup(Codex.gear())
	perks.setup(Codex.perks())
	var controls := VBoxContainer.new()
	_build_controls(controls)
	_pages = [settings_scroll, _wrap_scaled(bestiary, holder), _wrap_scaled(arsenal, holder), _wrap_scaled(gear, holder),
		_wrap_scaled(perks, holder), _wrap_scaled(controls, holder)]
	for p in _pages:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		holder.add_child(p)

## Strona narysowana dla skali 0,8 — osadzona w kontenerze, który ją skaluje ×1,6 i dopasowuje rozmiar.
func _wrap_scaled(page: Control, _holder: Control) -> Control:
	var w := MarginContainer.new()
	w.add_theme_constant_override("margin_left", 18)
	w.add_theme_constant_override("margin_right", 18)
	w.add_theme_constant_override("margin_top", 14)
	w.add_theme_constant_override("margin_bottom", 14)
	var inner := Control.new()
	inner.clip_contents = true
	w.add_child(inner)
	inner.add_child(page)
	page.scale = Vector2(CODEX_K, CODEX_K)
	var fit := _fit_scaled_page.bind(page, inner)
	inner.resized.connect(fit)
	if page is VBoxContainer:
		# VBox może urosnąć przy przebudowie listy przed zakończeniem sortowania kontenerów.
		page.resized.connect(fit.call_deferred)
		page.minimum_size_changed.connect(fit.call_deferred)
	return w

func _fit_scaled_page(page: Control, inner: Control) -> void:
	if not is_instance_valid(page) or not is_instance_valid(inner):
		return
	var target := (inner.size / CODEX_K).max(page.get_combined_minimum_size())
	if not page.size.is_equal_approx(target):
		page.size = target

func _build_settings(scroll: ScrollContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 36)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(grid)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for c in [left, right]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 6)
		grid.add_child(c)

	left.add_child(W.section(tr("AUDIO")))
	_slider(left, "master", tr("Master volume"))
	_slider(left, "music", tr("Music"))
	_slider(left, "ambience", tr("Ambience"))
	_slider(left, "sfx", tr("Effects"))
	_seg(left, tr("Microphone scream"), ["OFF", "LOW", "MED", "HIGH"], _mic_idx, _set_mic)
	left.add_child(_gap())
	left.add_child(W.section(tr("GAMEPLAY")))
	_seg(left, tr("Screen shake"), Settings.SHAKE_NAMES, func() -> int: return Settings.shake_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.shake_idx, Settings.cycle_shake, i, 3))
	_seg(left, tr("Weather effects"), Settings.WEATHER_FX_NAMES, func() -> int: return Settings.weather_fx_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.weather_fx_idx, Settings.cycle_weather_fx, i, 3))
	_toggle(left, tr("Tips for new players"), func() -> bool: return Settings.hints_on, Settings.toggle_hints)
	_seg(left, tr("Sneak key"), ["HOLD", "TOGGLE"], func() -> int: return 1 if Settings.crouch_toggle else 0,
		func(i: int) -> void:
			if (i == 1) != Settings.crouch_toggle:
				Settings.toggle_crouch_mode())
	_seg(left, tr("Weapon handling"), ["REALISTIC", "CLASSIC"], func() -> int: return 0 if Settings.realistic_handling else 1,
		func(i: int) -> void:
			if (i == 0) != Settings.realistic_handling:
				Settings.toggle_realistic_handling())
	_seg(left, tr("Weapon reliability"), Settings.RELIABILITY_NAMES, func() -> int: return Settings.reliability_idx, Settings.set_reliability)
	left.add_child(_gap())
	left.add_child(W.section(tr("FIRST PERSON (RANGE)")))
	_drop(left, tr("Field of view"), func() -> String: return "%d°" % int(Settings.fp_fov()), Settings.cycle_fp_fov)
	_drop(left, tr("Look sensitivity"), func() -> String: return "×%.2f" % Settings.fp_sens(), Settings.cycle_fp_sens)
	_seg(left, tr("Range brace key"), ["HOLD", "TOGGLE"], func() -> int: return 1 if Settings.fp_brace_toggle else 0,
		func(i: int) -> void:
			if (i == 1) != Settings.fp_brace_toggle:
				Settings.toggle_fp_brace())
	_toggle(left, tr("Invert look Y"), func() -> bool: return Settings.fp_invert_y, Settings.toggle_fp_invert_y)
	left.add_child(_gap())
	left.add_child(W.section(tr("SYSTEM")))
	_seg(left, tr("Language"), Settings.LOCALE_NAMES, func() -> int: return Settings.locale_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.locale_idx, Settings.cycle_locale, i, 2))

	right.add_child(W.section(tr("DISPLAY")))
	_toggle(right, tr("Fullscreen  (%s)") % Actions.text("fullscreen"), func() -> bool: return Settings.fullscreen, Settings.toggle_fullscreen)
	_drop(right, tr("Window size"), func() -> String:
			var r: Vector2i = Settings.RES_LIST[Settings.res_idx]
			return "FULLSCREEN" if Settings.fullscreen else "%d × %d" % [r.x, r.y],
		Settings.cycle_res)
	_seg(right, tr("V-Sync"), Settings.VSYNC_NAMES, func() -> int: return Settings.vsync_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.vsync_idx, Settings.cycle_vsync, i, 3))
	_drop(right, tr("Frame rate limit"), func() -> String:
			return "UNLIMITED" if Settings.FPS_LIST[Settings.fps_idx] == 0 else "%d" % Settings.FPS_LIST[Settings.fps_idx],
		Settings.cycle_fps)
	_seg(right, tr("Effects quality"), ["LOW", "MED", "HIGH"], func() -> int: return Settings.quality_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.quality_idx, Settings.cycle_quality, i, 3))
	_drop(right, tr("Render scale"), func() -> String:
			var sc := Settings.render_scale()
			return "100%" if sc >= 0.999 else "%d%% (FSR)" % roundi(sc * 100.0),
		Settings.cycle_render_scale)
	_seg(right, tr("HUD size"), ["S", "M", "L"], func() -> int: return Settings.ui_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.ui_idx, Settings.cycle_ui, i, 3))
	_seg(right, tr("Camera zoom"), Settings.CAM_NAMES, func() -> int: return Settings.cam_idx,
		func(i: int) -> void: _to_idx(func() -> int: return Settings.cam_idx, Settings.cycle_cam, i, 3))
	_drop(right, tr("Brightness"), func() -> String:
			var ev := Settings.brightness_ev()
			return "0 EV" if is_zero_approx(ev) else "%+.2f EV" % ev,
		open_brightness)
	right.add_child(_gap())
	right.add_child(W.section(tr("ACCESSIBILITY")))
	_toggle(right, tr("Reduce effects"), func() -> bool: return Settings.reduce_fx, Settings.toggle_reduce_fx)
	_toggle(right, tr("Sound captions"), func() -> bool: return Settings.captions, Settings.toggle_captions)
	_toggle(right, tr("Mono audio"), func() -> bool: return Settings.mono_audio, Settings.toggle_mono_audio)
	_drop(right, tr("Color vision"), func() -> String: return Settings.COLORBLIND_NAMES[Settings.colorblind_idx], Settings.cycle_colorblind)

func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c

## Wiersz: opis po lewej, kontrolka po prawej (16 px).
func _row(parent: Control, label: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	r.custom_minimum_size = Vector2(0, 26)
	var l := W.body(label, 16, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(l)
	parent.add_child(r)
	return r

func _slider(parent: Control, kind: String, label: String) -> void:
	var r := _row(parent, label)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = Settings.STEP
	sl.custom_minimum_size = Vector2(150, 16)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(kind, v)
		Audio.play("ui_click", Audio.BUS_UI, -14.0))
	r.add_child(sl)
	var val := W.mono("", 14, UiTheme.TEXT, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(44, 0)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(val)
	_refreshers.append(func() -> void:
		sl.set_value_no_signal(float(Settings.volume[kind]))
		val.text = "%d%%" % int(round(float(Settings.volume[kind]) * 100.0)))

func _toggle(parent: Control, label: String, get_on: Callable, flip: Callable) -> void:
	var r := _row(parent, label)
	var st := W.mono("", 12, UiTheme.TEXT)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(st)
	var t := W.Toggle.new()
	t.toggled.connect(func(_on: bool) -> void:
		flip.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	r.add_child(t)
	_refreshers.append(func() -> void:
		var on: bool = get_on.call()
		t.set_on(on)
		st.text = "ON" if on else "OFF"
		st.add_theme_color_override("font_color", UiTheme.TEXT if on else Color("7d7a6d")))

func _seg(parent: Control, label: String, options: Array, get_idx: Callable, set_idx: Callable) -> void:
	var r := _row(parent, label)
	var s := W.Segmented.new()
	var names: Array = []
	for o in options:
		names.append(tr(String(o)))
	s.setup(names)
	s.selected.connect(func(i: int) -> void:
		set_idx.call(i)
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	r.add_child(s)
	_refreshers.append(func() -> void: s.set_index(int(get_idx.call())))

func _drop(parent: Control, label: String, get_text: Callable, action: Callable) -> void:
	var r := _row(parent, label)
	var d := W.Dropdown.new()
	d.clicked.connect(func() -> void:
		action.call()
		Audio.play("ui_click", Audio.BUS_UI, -10.0))
	r.add_child(d)
	_refreshers.append(func() -> void: d.set_text(tr(String(get_text.call()))))

## Ustawia wartość przez kolejne przełączenia (Settings ma tylko „cycle”): do `n` kroków.
func _to_idx(get_idx: Callable, cycle: Callable, target: int, n: int) -> void:
	for _i in n:
		if int(get_idx.call()) == target:
			return
		cycle.call()

func _mic_idx() -> int:
	return (1 + Voice.sens) if Voice.enabled else 0

func _set_mic(i: int) -> void:
	for _k in 4:
		if _mic_idx() == i:
			return
		Voice.cycle()

func _build_footer() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 26)
	m.add_theme_constant_override("margin_right", 26)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 12)
	m.add_child(f)
	_resume = Button.new()
	_resume.text = "RESUME"
	W.style_button(_resume, "primary", 24)
	_resume.pressed.connect(close)
	f.add_child(_resume)
	_copy_id = Button.new()
	_copy_id.text = tr("COPY LOBBY ID")
	W.style_button(_copy_id, "secondary", 20)
	_copy_id.tooltip_text = tr("Copies the Steam lobby ID to the clipboard — send it to friends (they paste it and press STEAM JOIN)")
	_copy_id.pressed.connect(func() -> void:
		var sn := _steam_net()
		if sn != null and int(sn.get("lobby_id")) != 0:
			DisplayServer.clipboard_set(str(int(sn.get("lobby_id"))))
			_sub.text = tr("Lobby ID copied: %s") % str(int(sn.get("lobby_id")))
			Audio.play("ui_confirm", Audio.BUS_UI, -8.0))
	f.add_child(_copy_id)
	_leave = Button.new()
	_leave.text = tr("LEAVE SESSION")
	W.style_button(_leave, "secondary", 22)
	_leave.tooltip_text = tr("Back to the start screen (the host's squad keeps playing if you are a client)")
	_leave.pressed.connect(func() -> void:
		close()
		leave_requested.emit())
	f.add_child(_leave)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_child(sp)
	_hint = W.mono(tr("Asks to confirm"), 12, UiTheme.MUTED, 0.04)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.add_child(_hint)
	_quit = Button.new()
	_quit.text = tr("QUIT GAME")
	W.style_button(_quit, "danger", 22)
	_quit.tooltip_text = tr("Closes the game (your squad keeps playing if you are the client)")
	_quit.pressed.connect(_on_quit)
	f.add_child(_quit)
	return m

## Zakładka CONTROLS: lista akcji z przyciskami klawisza i pada. Klik → „press a key…" → następny klawisz (Esc anuluje)
## tworzy plan z walidacją kontekstów i listą zmienianych akcji. Zatwierdzenie zapisuje settings.cfg; profile są opt-in.
## (Strona powstała dla skali 0,8 — osadza ją `_wrap_scaled`.)
func _build_controls(page: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_rebind_list = VBoxContainer.new()
	_rebind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebind_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_rebind_list)
	_profile_label = UiTheme.label("", 8, UiTheme.ACCENT)
	page.add_child(_profile_label)
	var presets := HBoxContainer.new()
	for name in ["classic", "modern"]:
		var button := Button.new()
		_compact(button)
		button.text = tr("APPLY CLASSIC") if name == "classic" else tr("APPLY MODERN")
		button.pressed.connect(_request_preset.bind(name))
		presets.add_child(button)
	page.add_child(presets)
	_rebind_msg = UiTheme.label(tr("Click to edit · + add · × remove · Esc cancels"), 8, UiTheme.MUTED)
	_rebind_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_rebind_msg)
	_confirm_controls = ConfirmationDialog.new()
	_confirm_controls.title = tr("Confirm control changes")
	_confirm_controls.confirmed.connect(_apply_pending_controls)
	_confirm_controls.canceled.connect(func() -> void: _pending_plan = {})
	add_child(_confirm_controls)
	_fill_rebind()
	Settings.bindings_changed.connect(_fill_rebind)
	InputSetup.device_changed.connect(func(_pad: bool) -> void: _fill_rebind())

func _fill_rebind() -> void:
	if not _cap.is_empty():
		return # zmiana urządzenia podczas oczekiwania nie anuluje przechwytywania
	for c in _rebind_list.get_children():
		_rebind_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	var h0 := UiTheme.label(tr("ACTION"), 7, UiTheme.MUTED)
	h0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h0)
	for spec in [["KEYBOARD / MOUSE", 114.0], ["PAD", 96.0]]:
		var label := UiTheme.label(tr(spec[0]), 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		label.custom_minimum_size.x = spec[1]
		head.add_child(label)
	_rebind_list.add_child(head)
	for id in Actions.rebindable():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var label := UiTheme.label(tr(Actions.label_of(id)), 8, UiTheme.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 100.0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_binding_cell(id, Actions.DEV_KEY, 114.0))
		row.add_child(_binding_cell(id, Actions.DEV_PAD, 96.0))
		_rebind_list.add_child(row)
	_profile_label.text = tr("Control profile: %s") % tr(Actions.preset_name())
	if not Actions.load_repairs.is_empty():
		_rebind_msg.text = tr("Conflicting saved controls restored: %s") % _changed_names(Actions.load_repairs)

func _binding_cell(id: String, dev: int, width: float) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = width
	col.add_theme_constant_override("separation", 1)
	if dev == Actions.DEV_PAD and not Actions.pad_rebindable(id):
		var axes := UiTheme.label(Actions.text(id, false, dev), 7, UiTheme.MUTED)
		axes.tooltip_text = tr("Fixed axes")
		col.add_child(axes)
		return col
	if id == "pause" and dev == Actions.DEV_KEY:
		var escape := UiTheme.label("Esc", 8, UiTheme.MUTED)
		escape.tooltip_text = tr("Esc is reserved for cancel and pause.")
		col.add_child(escape)
	var slots := Actions.editable_slots(id, dev)
	var add := Button.new()
	_compact(add)
	add.text = "+"
	add.tooltip_text = tr("Add binding")
	add.custom_minimum_size.x = 18.0
	add.pressed.connect(_start_capture.bind(id, dev, add, -1))
	for slot in slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.add_child(_rebind_button(id, dev, width - 44.0, slot))
		var remove := Button.new()
		_compact(remove)
		remove.text = "×"
		remove.tooltip_text = tr("Remove binding")
		remove.custom_minimum_size.x = 18.0
		remove.pressed.connect(_request_remove.bind(id, slot))
		row.add_child(remove)
		if slot == slots[0]:
			row.add_child(add)
		col.add_child(row)
	if slots.is_empty():
		col.add_child(add)
	return col

func _rebind_button(id: String, dev: int, width: float, slot := -2) -> Button:
	var button := Button.new()
	_compact(button)
	button.custom_minimum_size.x = width
	button.clip_text = true
	button.text = Actions.binding_name(id, slot) if slot >= 0 else Actions.text(id, false, dev)
	button.tooltip_text = button.text + " · " + tr("Click, then press the new %s") % (tr("key or mouse button") if dev == Actions.DEV_KEY else tr("pad button"))
	button.pressed.connect(_start_capture.bind(id, dev, button, slot))
	return button

func _start_capture(id: String, dev: int, button: Button, slot := -2) -> void:
	_cancel_capture()
	_cap = {"id": id, "dev": dev, "btn": button, "text": button.text, "slot": slot}
	button.text = tr("press a key…") if dev == Actions.DEV_KEY else tr("press a button…")
	_rebind_msg.text = tr("%s: press a key or button  (Esc cancels)") % tr(Actions.label_of(id))
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _cancel_capture() -> void:
	if not _cap.is_empty() and is_instance_valid(_cap.btn):
		_cap.btn.text = String(_cap.text)
	_cap = {}

func _capture_event(event: InputEvent) -> bool:
	if _cap.is_empty():
		return false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_cancel_capture()
		_rebind_msg.text = tr("Cancelled.")
		_fill_rebind()
		return true
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if pressed or event is InputEventJoypadMotion:
		var binding := Actions.binding_from_event(event, _cap.dev)
		if not binding.is_empty():
			return _finish_capture(event)
	# Niewłaściwe urządzenie i ruch drążka nie przenoszą fokusu ani nie zamykają panelu.
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion

func _finish_capture(event: InputEvent) -> bool:
	var plan := Actions.plan_binding(_cap.id, _cap.dev, event, _cap.slot)
	_cancel_capture()
	_confirm_plan(plan)
	return true

func _request_remove(id: String, slot: int) -> void:
	_confirm_plan(Actions.plan_remove(id, slot))

func _changed_names(ids: Array) -> String:
	var names := PackedStringArray()
	for id in ids:
		names.append(tr(Actions.label_of(id)))
	return ", ".join(names)

func _confirm_plan(plan: Dictionary) -> void:
	if not plan.ok:
		_rebind_msg.text = String(plan.reason)
		Audio.play("ui_click", Audio.BUS_UI, -16.0)
		return
	_pending_plan = plan
	_confirm_controls.dialog_text = tr("Apply changes to: %s?") % _changed_names(plan.changed)
	for id in plan.changed:
		var names := PackedStringArray()
		for b in plan.bindings[id]:
			names.append(Actions._name_of(b))
		_confirm_controls.dialog_text += "\n%s: %s" % [tr(Actions.label_of(id)), " / ".join(names) if not names.is_empty() else "—"]
	_confirm_controls.popup_centered(Vector2i(440, 160))

func _request_preset(name: String) -> void:
	_cancel_capture()
	var plan := Actions.plan_preset(name)
	if not plan.ok:
		_rebind_msg.text = String(plan.reason)
		return
	_pending_plan = plan
	_confirm_controls.dialog_text = tr("Apply %s? This replaces your current bindings.") % name.capitalize()
	_confirm_controls.popup_centered(Vector2i(440, 160))

func _apply_pending_controls() -> void:
	_confirm_controls.hide()
	var result := Actions.apply_plan(_pending_plan)
	_pending_plan = {}
	_rebind_msg.text = tr("Controls updated.") if result.ok else String(result.reason)
	Audio.play("ui_confirm", Audio.BUS_UI, -8.0) if result.ok else Audio.play("ui_click", Audio.BUS_UI, -16.0)

## Niższy przycisk (strony kodeksu i sterowania — skala 0,8).
func _compact(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = theme.get_stylebox(state, "Button").duplicate()
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_font_size_override("font_size", 9)

# ---------------------------------------------------------------- stan

func _refresh() -> void:
	for r in _refreshers:
		r.call()

func _show_tab(i: int) -> void:
	_tab = i
	for j in _pages.size():
		_pages[j].visible = j == i
		(_nav[j] as W.NavItem).active = j == i

## Węzeł Steam (main.gd tworzy go jako „SteamNet”) — null, gdy brak sceny gry.
func _steam_net() -> Node:
	var cs := get_tree().current_scene
	return cs.get_node_or_null("SteamNet") if cs != null else null

## Ekran kalibracji jasności (brightness_screen.gd) nad menu; po zamknięciu fokus wraca do przycisku RESUME.
func open_brightness() -> void:
	var bs := BrightnessScreen.new()
	get_parent().add_child(bs)                      # rodzeństwo za menu: dostaje wejście pierwsze (Esc zamyka kalibrację, nie pauzę)
	bs.closed.connect(func() -> void:
		if _open:
			_resume.grab_focus())

## Menu główne / lobby: otwiera menu w trybie ustawień (bez sesji).
func open_settings() -> void:
	_tab = 0
	open()

func _on_quit() -> void:
	if _quit_t > 0.0:
		close()
		Audio.quit_game()
		return
	_quit_t = QUIT_CONFIRM_S
	_quit.text = tr("CLICK AGAIN TO QUIT")
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _solo() -> bool:
	return multiplayer.get_peers().is_empty()

## Nagłówek: tytuł mapy i czas misji (z węzłów sceny) albo „Changes are saved automatically.” przed grą.
func _mission_line() -> String:
	var lvl := get_tree().get_first_node_in_group("level")
	var cs := get_tree().current_scene
	var m: Node = cs.get("mission") if cs != null else null
	if lvl == null or m == null:
		return ""
	var title := ""
	var id: String = String(lvl.get("map_id"))
	if lvl.MAPS.has(id):
		title = String(lvl.MAPS[id].TITLE).replace("  ", " ")
	var secs := int(m.get("elapsed"))
	return ("%s · %02d:%02d" % [title, secs / 60, secs % 60]).to_upper()

func _set_chip() -> void:
	for c in _chip_holder.get_children():
		c.queue_free()
	if not NoiseMgr.has_network():
		return
	if _solo():
		_chip_holder.add_child(W.chip(tr("SOLO · THE GAME IS PAUSED"), UiTheme.TEXT, UiTheme.LINE2))
	else:
		_chip_holder.add_child(W.chip(tr("CO-OP · THE WORLD KEEPS RUNNING"), UiTheme.DANGER, UiTheme.BLOOD_LINE, true))

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	var online := NoiseMgr.has_network()
	_title.text = tr("PAUSED") if online else tr("SETTINGS")
	_sub.text = _mission_line() if online else tr("Changes are saved automatically.")
	_set_chip()
	_resume.text = tr("RESUME") if online else tr("BACK")
	_leave.visible = online
	var sn := _steam_net()
	_copy_id.visible = online and sn != null and int(sn.get("lobby_id")) != 0       # tylko w sesji ze Steamowym lobby
	_quit_t = 0.0
	_quit.text = tr("QUIT GAME")
	get_tree().paused = online and _solo()
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_tab(_tab)
	_refresh()
	_resume.grab_focus()                            # pad / klawiatura: nawigacja fokusem od przycisku RESUME
	UiTheme.fade_in(_card)
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func close() -> void:
	if not _open:
		return
	_open = false
	_cancel_capture()
	_pending_plan = {}
	_confirm_controls.hide()
	visible = false
	get_tree().paused = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(delta: float) -> void:
	if _quit_t > 0.0:
		_quit_t -= delta
		if _quit_t <= 0.0:
			_quit.text = tr("QUIT GAME")
	# ktoś dołączył do zatrzymanej gry solo — świat musi ruszyć
	if _open and get_tree().paused and not _solo():
		get_tree().paused = false
		_set_chip()

func _input(event: InputEvent) -> void:
	if _confirm_controls.visible:
		return
	if _open and _capture_event(event):
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
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
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and fo.name == "ChatEdit":
		return                                      # Esc zamyka pole czatu (hud.gd), nie otwiera pauzy
	var ws := get_tree().get_first_node_in_group("workshop_ui")
	if ws != null and ws.is_open():
		return                                  # Esc zamyka panel warsztatu (workshop_ui.gd), nie otwiera pauzy
	if _open:
		close()
	else:
		open()                                                # przed grą (menu główne / lobby) otwiera same ustawienia
	get_viewport().set_input_as_handled()
