extends Control
## Renderer kanałów komunikatów (MESSAGES_PLAN.md §3), dziecko hud.gd: ALERT pod kartą celu, TOAST (stos) pod kartą RUN po prawej,
## TITLE (dolna trzecia po lewej, nad kartą drużyny). Treść bierze z autoloadu `Msg` (arbiter wybiera, co wygrywa w kanale); producenci
## (hud.gd, mission.gd, main.gd) tylko wołają `Msg.post()` / `Msg.hold()`. Pozycje podaje hud.gd przez `obj_bottom`, `run_bottom` i `squad_top`.

const UiTheme := preload("res://scripts/ui_theme.gd")

const MARGIN := 8.0
const ALERT_W := 300.0
const TOAST_W := 178.0
const TITLE_W := 380.0
const BG := Color(0.043, 0.047, 0.043, 0.92)

var obj_bottom := 70.0                 ## dolna krawędź karty celu [jednostki logiczne HUD]
var run_bottom := 70.0                 ## dolna krawędź karty RUN (prawy górny róg)
var squad_top := 380.0                 ## górna krawędź karty drużyny (lewy dół)

var _alert: PanelContainer
var _a_title: Label
var _a_sub: Label
var _a_alpha := 0.0
var _a_last: Dictionary = {}
var _a_text := ""
var _a_pop := 0.0
var _blink := 0.0

var _toast_box: VBoxContainer
var _toast_key := ""
var _toast_msgs: Array = []

var _tip: PanelContainer
var _tip_label: Label
var _title: PanelContainer
var _t_head: Label
var _t_sub: Label
var _t_kicker: Label
var _t_alpha := 0.0
var _t_last: Dictionary = {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _box(border: Color, left := 3) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = BG
	b.border_color = border
	b.border_width_left = left
	b.border_width_top = 1
	b.border_width_right = 1
	b.border_width_bottom = 1
	b.content_margin_left = 10.0
	b.content_margin_right = 12.0
	b.content_margin_top = 5.0
	b.content_margin_bottom = 6.0
	if UiTheme.hd_on():
		b.set_corner_radius_all(2)
	return b

func _build() -> void:
	_alert = PanelContainer.new()
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert.visible = false
	add_child(_alert)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 1)
	_alert.add_child(av)
	_a_title = UiTheme.heading("", UiTheme.T_TITLE, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	av.add_child(_a_title)
	_a_sub = UiTheme.label("", UiTheme.T_BODY - 1, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_a_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_a_sub.custom_minimum_size = Vector2(ALERT_W - 24.0, 0)
	av.add_child(_a_sub)
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.add_theme_stylebox_override("panel", _box(Color(UiTheme.ACCENT, 0.6), 3))
	add_child(_tip)
	var tr_row := HBoxContainer.new()
	tr_row.add_theme_constant_override("separation", 7)
	_tip.add_child(tr_row)
	tr_row.add_child(UiTheme.heading(tr("TIP"), UiTheme.T_CAPTION, UiTheme.ACCENT))
	_tip_label = UiTheme.whisper(UiTheme.label("", UiTheme.T_BODY - 1, UiTheme.TEXT))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(TITLE_W - 56.0, 0)
	tr_row.add_child(_tip_label)
	_title = PanelContainer.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.visible = false
	_title.add_theme_stylebox_override("panel", _box(UiTheme.DANGER, 4))
	add_child(_title)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	_title.add_child(tv)
	_t_kicker = UiTheme.mono(UiTheme.label("", UiTheme.T_CAPTION - 1, UiTheme.MUTED))
	tv.add_child(_t_kicker)
	_t_head = UiTheme.heading("", UiTheme.T_TITLE + 2, UiTheme.DANGER)
	tv.add_child(_t_head)
	_t_sub = UiTheme.label("", UiTheme.T_BODY - 1, UiTheme.TEXT)
	_t_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_t_sub.custom_minimum_size = Vector2(TITLE_W - 28.0, 0)
	tv.add_child(_t_sub)

func _style_col(style: int) -> Color:
	match style:
		Msg.Style.DANGER:
			return UiTheme.DANGER
		Msg.Style.SUCCESS:
			return UiTheme.OK
		Msg.Style.WARN:
			return UiTheme.WARM
		Msg.Style.ACTION:
			return UiTheme.ACCENT
	return UiTheme.TEXT

func _process(delta: float) -> void:
	_blink += delta
	_drive_alert(delta)
	_drive_toasts()
	_drive_title(delta)
	_drive_tip()

# ---------------------------------------------------------------- ALERT

func _drive_alert(delta: float) -> void:
	var m: Dictionary = Msg.current(Msg.Ch.ALERT)
	if m.is_empty():
		_a_alpha = maxf(0.0, _a_alpha - delta / 0.25)
	else:
		_a_alpha = minf(1.0, _a_alpha + delta / 0.12)
		_a_last = m
	_alert.visible = _a_alpha > 0.01 and not _a_last.is_empty()
	if not _alert.visible:
		return
	var big: bool = bool(_a_last.get("big", false))
	var col := _style_col(int(_a_last["style"]))
	var text := String(_a_last["text"])
	if text != _a_text:
		_a_text = text
		_a_pop = 1.0
	_a_pop = maxf(0.0, _a_pop - delta * 3.5)
	_a_title.text = text
	_a_title.add_theme_color_override("font_color", col)
	_a_title.add_theme_font_size_override("font_size", UiTheme.T_DISPLAY * 2 if big else UiTheme.T_TITLE)
	_a_sub.text = String(_a_last["sub"])
	_a_sub.visible = _a_sub.text != ""
	_a_sub.custom_minimum_size = Vector2(190.0 if big else ALERT_W - 24.0, 0)      # cyfra odliczania nie rozpycha karty
	_alert.add_theme_stylebox_override("panel", _box(col))
	_alert.reset_size()
	_alert.position = Vector2((size.x - _alert.size.x) * 0.5, obj_bottom + 6.0)
	_a_title.pivot_offset = _a_title.size * 0.5
	_a_title.scale = Vector2.ONE * (1.0 + (0.3 if big else 0.0) * _a_pop)
	var a := _a_alpha
	if int(_a_last["style"]) == Msg.Style.DANGER and not big:
		a *= lerpf(1.0, 0.6 + 0.4 * sin(_blink * 6.0), Settings.fx_mult())      # groźba pulsuje (wyłączane przez Reduce effects)
	_alert.modulate.a = a

# ---------------------------------------------------------------- TOAST

func _drive_toasts() -> void:
	var ts: Array = Msg.toasts()
	var parts: Array = []
	for t in ts:
		parts.append("%s:%s:%s" % [t["id"], t["text"], t["sub"]])
	var key := "|".join(parts)
	if key != _toast_key:
		_toast_key = key
		_toast_msgs = ts.duplicate()
		for c in _toast_box.get_children():
			_toast_box.remove_child(c)
			c.queue_free()
		for t in ts:
			var p := PanelContainer.new()
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.custom_minimum_size = Vector2(TOAST_W, 0)
			p.add_theme_stylebox_override("panel", _box(_style_col(int(t["style"]))))
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			p.add_child(v)
			var l := UiTheme.label(String(t["text"]), UiTheme.T_BODY, UiTheme.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(TOAST_W - 24.0, 0)
			v.add_child(l)
			if String(t["sub"]) != "":
				var s := UiTheme.label(String(t["sub"]), UiTheme.T_CAPTION, UiTheme.MUTED)
				s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				s.custom_minimum_size = Vector2(TOAST_W - 24.0, 0)
				v.add_child(s)
			_toast_box.add_child(p)
	# wygaszanie ostatnich 0,6 s życia
	for i in mini(_toast_box.get_child_count(), _toast_msgs.size()):
		var t: Dictionary = _toast_msgs[i]
		var m: Dictionary = Msg.live(String(t["id"]))
		if m.is_empty():
			m = t
		(_toast_box.get_child(i) as Control).modulate.a = clampf((float(m["ttl"]) - float(m["age"])) / 0.6, 0.0, 1.0)
	_toast_box.reset_size()
	_toast_box.position = Vector2(size.x - MARGIN - _toast_box.size.x, run_bottom + 6.0)

# ---------------------------------------------------------------- TITLE

func _drive_title(delta: float) -> void:
	var m: Dictionary = Msg.current(Msg.Ch.TITLE)
	if m.is_empty():
		_t_alpha = maxf(0.0, _t_alpha - delta / 0.5)
	else:
		_t_alpha = minf(1.0, _t_alpha + delta / 0.35)
		_t_last = m
	_title.visible = _t_alpha > 0.01 and not _t_last.is_empty()
	if not _title.visible:
		return
	_t_kicker.text = String(_t_last.get("kicker", ""))
	_t_kicker.visible = _t_kicker.text != ""
	_t_head.text = String(_t_last["text"])
	_t_sub.text = String(_t_last["sub"])
	_t_sub.visible = _t_sub.text != ""
	_title.reset_size()
	_title.position = Vector2(MARGIN, squad_top - _title.size.y - 10.0)
	_title.modulate.a = _t_alpha

# ---------------------------------------------------------------- TIP

## Porada dla nowego gracza (kanał TIP): lewy dół nad kartą drużyny; gdy trwa karta tytułowa, staje nad nią.
func _drive_tip() -> void:
	var m: Dictionary = Msg.current(Msg.Ch.TIP)
	_tip.visible = not m.is_empty()
	if not _tip.visible:
		return
	_tip_label.text = String(m["text"])
	_tip.reset_size()
	var base_y := squad_top - 10.0
	if _title.visible:
		base_y = _title.position.y - 6.0
	_tip.position = Vector2(MARGIN, base_y - _tip.size.y)
	_tip.modulate.a = float(m["alpha"])
