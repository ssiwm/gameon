extends Control
## Ekran OPERATORZY (PROFILES_PLAN.md E3, D3): karty postaci tego komputera (do Characters.MAX) — kryptonim, miniatura wyglądu, poziom,
## następna misja kampanii, złom, czas gry, ostatnia gra; aktywna ma znacznik. Klik / [Enter] na karcie wybiera postać (Characters.activate:
## przeładowanie kampanii, profilu, rzeczy gracza i trudności) i wraca do menu; wolne miejsce albo NOWY OPERATOR otwiera kreator,
## ZMIEŃ NAZWĘ — okno kryptonimu dla zaznaczonej karty, WSTECZ / [Esc] zamyka.
##
## Kreator (D2, D3): kryptonim (2–16 znaków, Characters.validate_name) z „LOSUJ” z puli w klimacie radia (pierwsza propozycja: nazwa
## Steam), wybór sylwetki (płeć, strój Scavenger z L1 — reszta wyglądu w szafce w kryjówce). Pierwsze uruchomienie (postać z migracji albo
## świeża instalacja, `needs_name`) otwiera kreator bez „ANULUJ”. Reset i usuwanie postaci — etap E4.
##
## Współrzędne w pikselach makiety 1280×720 (korzeń skalowany jak w main_menu.gd).

signal closed

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Look := preload("res://scripts/look.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Level := preload("res://scripts/level.gd")

## Losowe kryptonimy (D2): zwierzęta, ptaki i zjawiska nocy — krótkie, czytelne przez radio.
const CALLSIGNS := ["Sowa", "Iskra", "Wilk", "Kruk", "Ryś", "Jastrząb", "Borsuk", "Lis", "Grot", "Szron", "Popiół", "Zmierzch", "Sęp",
	"Żbik", "Kos", "Puszczyk", "Bies", "Mróz", "Cień", "Echo", "Trzask", "Szum", "Dzik", "Nietoperz", "Grom", "Mgła", "Kaczor", "Bury"]
const CARD := Vector2(352, 214)
const ERR_TEXT := {
	"short": "At least 2 characters",
	"long": "At most 16 characters",
	"chars": "Letters, digits, space, - and _ only",
	"taken": "Another operator already uses this callsign",
	"limit": "No free slot — 6 operators at most",
}

## Nazwa Steam do pierwszej propozycji kryptonimu (ustawia main.gd); pusta Callable / "" = bez Steama.
var steam_name := Callable()

var _root: Control
var _grid: GridContainer
var _cards: Array = []
var _focus_id := ""
var _new_btn: Button
var _rename_btn: Button
var _back_btn: Button
var _dlg: PanelContainer
var _dlg_dim: ColorRect               ## przyciemnienie listy pod oknem kryptonimu (okno modalne)
var _dlg_title: Label
var _dlg_edit: LineEdit
var _dlg_err: Label
var _dlg_look_row: HBoxContainer
var _dlg_cancel: Button
var _dlg_ok: Button
var _dlg_mode := ""                   ## "new" / "rename" / "first"
var _dlg_id := ""
var _gender := 0
var _gender_tiles: Array = []

## Karta postaci: panel z fokusem (pad, klawiatura, mysz); `pressed` przy kliknięciu albo ui_accept.
class Card extends PanelContainer:
	signal pressed
	var id := ""
	var active := false
	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		clip_contents = true
	func _ready() -> void:
		_restyle()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			_restyle()
		elif what == NOTIFICATION_MOUSE_ENTER and is_visible_in_tree():
			grab_focus()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()
	func _restyle() -> void:
		var UT := preload("res://scripts/ui_theme.gd")
		var sb := StyleBoxFlat.new()
		sb.bg_color = UT.TILE_BG_SEL if has_focus() else Color(0.043, 0.047, 0.043, 0.92)
		sb.border_color = UT.DANGER if has_focus() else (UT.TEXT if active else UT.LINE)
		sb.set_border_width_all(2 if has_focus() or active else 1)
		sb.content_margin_left = 12
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		add_theme_stylebox_override("panel", sb)

## Miniatura sylwetki z renderu modelu 3D (art/portraits/look_<płeć>_<strój>.png), stopami na dole.
class Portrait extends Control:
	var tex: Texture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	func set_code(c: int) -> void:
		var L := preload("res://scripts/look.gd")
		var path := "res://art/portraits/look_%s_%s.png" % [L.gender_id(c), L.outfit_id(c)]
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03))
		if tex == null:
			return
		var ts := tex.get_size()
		var s := minf(size.x / ts.x, size.y / ts.y)
		var w := ts * s
		draw_texture_rect(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), false)

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.014, 0.012, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_root = Control.new()
	add_child(_root)
	var head := VBoxContainer.new()
	head.position = Vector2(88, 52)
	head.add_theme_constant_override("separation", 4)
	head.add_child(W.mono("SQUAD ROSTER", 13, UiTheme.MUTED, 0.34))
	head.add_child(W.stencil("OPERATORS", 54, Color("d9d4c3"), 0.02, HORIZONTAL_ALIGNMENT_LEFT, 900))
	_root.add_child(head)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.position = Vector2(88, 168)
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 20)
	_root.add_child(_grid)
	var foot := HBoxContainer.new()
	foot.position = Vector2(88, 640)
	foot.add_theme_constant_override("separation", 16)
	_root.add_child(foot)
	_new_btn = _button(foot, "NEW OPERATOR", "primary", func() -> void: _open_dialog("new", ""))
	_rename_btn = _button(foot, "RENAME", "", func() -> void:
		if _focus_id != "" and Characters.has(_focus_id):
			_open_dialog("rename", _focus_id))
	_back_btn = _button(foot, "BACK", "", close)
	_build_dialog()
	get_viewport().size_changed.connect(_fit)
	visible = false
	_fit()

func _button(parent: Control, text: String, kind: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	W.style_button(b, kind, 18)
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		action.call())
	parent.add_child(b)
	return b

func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(vp.x / 1280.0, vp.y / 720.0)
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	_root.position = (vp - Vector2(1280, 720) * k) * 0.5
	size = vp

## Pokazuje listę (fokus na aktywnej postaci).
func open() -> void:
	visible = true
	_dlg.visible = false
	_rebuild()

## Kreator przy pierwszym uruchomieniu: postać z migracji albo świeża czeka na kryptonim; bez „ANULUJ”.
func open_creator_first_run() -> void:
	visible = true
	_rebuild()
	_open_dialog("first", Characters.active_id)

func close() -> void:
	if _dlg.visible and _dlg_mode == "first":
		return
	visible = false
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel"):
		if _dlg.visible and _dlg_mode != "first":
			_dlg.visible = false
			_rebuild()
		elif not _dlg.visible:
			close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- karty

func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	var focus_card: Control = null
	for m in Characters.list():
		var sm: Dictionary = Characters.summary(String(m["id"]))
		var card := _card(sm)
		_grid.add_child(card)
		_cards.append(card)
		if String(sm["id"]) == (_focus_id if Characters.has(_focus_id) else Characters.active_id):
			focus_card = card
	if Characters.count() < Characters.MAX:
		var free := Card.new()
		free.custom_minimum_size = CARD
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(W.stencil("+", 46, UiTheme.MUTED, 0.0, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(W.mono("NEW OPERATOR", 13, UiTheme.MUTED, 0.2, HORIZONTAL_ALIGNMENT_CENTER))
		free.add_child(v)
		free.pressed.connect(func() -> void: _open_dialog("new", ""))
		_grid.add_child(free)
		_cards.append(free)
	_new_btn.disabled = Characters.count() >= Characters.MAX
	if not _dlg.visible:
		if focus_card != null:
			focus_card.call_deferred("grab_focus")
		elif not _cards.is_empty():
			_cards[0].call_deferred("grab_focus")

func _card(sm: Dictionary) -> Card:
	var card := Card.new()
	card.id = String(sm["id"])
	card.active = card.id == Characters.active_id
	card.custom_minimum_size = CARD
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var pic := Portrait.new()
	pic.custom_minimum_size = Vector2(96, 188)
	pic.set_code(int(sm["look"]))
	row.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 5)
	row.add_child(v)
	var cs := String(sm["name"])
	var nm := W.stencil(cs if cs != "" else tr("UNNAMED"), 22, Color("f1ecdc") if cs != "" else UiTheme.MUTED, 0.02)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	v.add_child(nm)
	var lv := ProfileScript.level_of(int(sm["xp"]))
	v.add_child(_line(tr("LV %d  ·  %d XP") % [lv, int(sm["xp"])], UiTheme.ACCENT if card.active else UiTheme.TEXT))
	v.add_child(W.hairline(UiTheme.LINE))
	v.add_child(_kv("NEXT", _next_mission(sm["cleared"] as Array)))
	v.add_child(_kv("SCRAP", str(int(sm["bank"]))))
	v.add_child(_kv("PLAYED", _duration(float(sm["play_time"]))))
	v.add_child(_kv("LAST", Time.get_date_string_from_unix_time(int(sm["last_played"])) if int(sm["last_played"]) > 0 else "—"))
	if card.active:
		var tag := _line(tr("ACTIVE"), UiTheme.OK)
		v.add_child(tag)
	card.pressed.connect(func() -> void: _pick(card.id))
	card.focus_entered.connect(func() -> void: _focus_id = card.id)
	return card

func _line(text: String, col: Color) -> Label:
	var l := W.mono(text, 12, col, 0.06)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	return l

func _kv(key: String, val: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var k := W.mono(key, 11, UiTheme.MUTED, 0.12)
	k.custom_minimum_size = Vector2(62, 0)
	r.add_child(k)
	var v := _line(val, UiTheme.TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(v)
	return r

## Następna misja kampanii postaci: pierwsza z Level.CAMPAIGN, której drużyna tej postaci jeszcze nie przeszła.
func _next_mission(cleared: Array) -> String:
	for id in Level.CAMPAIGN:
		if not cleared.has(id):
			var path := "res://scripts/maps/%s.gd" % id
			var s = load(path) if ResourceLoader.exists(path) else null
			return tr(String(s.TITLE)).replace("  ", " ") if s != null else String(id)
	return tr("ZONE I CLEARED")

func _duration(sec: float) -> String:
	var mins := int(sec / 60.0)
	if mins < 60:
		return tr("%d min") % mins
	return tr("%d h %02d min") % [mins / 60, mins % 60]

func _pick(id: String) -> void:
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	if id != Characters.active_id:
		Characters.activate(id)
	close()

# ---------------------------------------------------------------- okno kryptonimu (kreator / zmiana nazwy)

func _build_dialog() -> void:
	_dlg_dim = ColorRect.new()
	_dlg_dim.color = Color(0, 0, 0, 0.72)
	_dlg_dim.position = Vector2(-640, -360)
	_dlg_dim.size = Vector2(2560, 1440)
	_dlg_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dlg_dim)
	_dlg = PanelContainer.new()
	_dlg.visibility_changed.connect(func() -> void: _dlg_dim.visible = _dlg.visible)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0b0c0b")
	sb.border_color = UiTheme.TEXT
	sb.set_border_width_all(1)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	_dlg.add_theme_stylebox_override("panel", sb)
	_dlg.custom_minimum_size = Vector2(600, 0)
	_dlg.position = Vector2(340, 130)
	_root.add_child(_dlg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_dlg.add_child(v)
	_dlg_title = W.stencil("", 30, Color("f1ecdc"), 0.02)
	v.add_child(_dlg_title)
	v.add_child(W.mono("CALLSIGN", 12, UiTheme.MUTED, 0.22))
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 10)
	v.add_child(er)
	_dlg_edit = LineEdit.new()
	W.style_edit(_dlg_edit, 20)
	_dlg_edit.max_length = Characters.NAME_MAX
	_dlg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_edit.text_changed.connect(func(_t: String) -> void: _dlg_err.text = "")
	_dlg_edit.text_submitted.connect(func(_t: String) -> void: _confirm())
	er.add_child(_dlg_edit)
	_button(er, "RANDOM", "", func() -> void:
		_dlg_edit.text = _random_name()
		_dlg_err.text = "")
	_dlg_err = W.mono("", 12, UiTheme.DANGER, 0.04)
	_dlg_err.custom_minimum_size = Vector2(0, 16)
	v.add_child(_dlg_err)
	_dlg_look_row = HBoxContainer.new()
	_dlg_look_row.add_theme_constant_override("separation", 16)
	v.add_child(_dlg_look_row)
	for g in Look.GENDERS.size():
		var tile := Card.new()
		tile.custom_minimum_size = Vector2(140, 200)
		var pic := Portrait.new()
		pic.set_code(Look.code(g, 0))
		tile.add_child(pic)
		tile.pressed.connect(func() -> void:
			_gender = g
			_mark_gender())
		_dlg_look_row.add_child(tile)
		_gender_tiles.append(tile)
	var hint := W.whisper("More outfits unlock with level — change them at the locker in the safe room.", 13, UiTheme.BONE_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dlg_look_row.add_child(hint)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 16)
	v.add_child(br)
	_dlg_ok = _button(br, "CONFIRM", "primary", _confirm)
	_dlg_cancel = _button(br, "CANCEL", "", func() -> void:
		_dlg.visible = false
		_rebuild())
	_dlg.visible = false

func _open_dialog(mode: String, id: String) -> void:
	if mode == "new" and Characters.count() >= Characters.MAX:
		return
	_dlg_mode = mode
	_dlg_id = id
	_dlg_title.text = tr({"new": "NEW OPERATOR", "rename": "RENAME OPERATOR", "first": "WHO'S ON THE RADIO?"}[mode])
	_dlg_err.text = ""
	var current := String(Characters.meta(id)["name"]) if id != "" else ""
	_dlg_edit.text = current if current != "" else _suggest_name()
	# sylwetka: nowa postać i świeży profil; postać z postępem zmienia wygląd w szafce w kryjówce
	_dlg_look_row.visible = mode == "new" or (mode == "first" and Profile.xp == 0)
	_gender = Look.gender_of(Profile.look) if mode == "first" else 0
	_mark_gender()
	_dlg_cancel.visible = mode != "first"
	_dlg.visible = true
	_dlg_edit.call_deferred("grab_focus")
	_dlg_edit.call_deferred("select_all")

func _mark_gender() -> void:
	for i in _gender_tiles.size():
		(_gender_tiles[i] as Card).active = i == _gender
		(_gender_tiles[i] as Card)._restyle()

func _confirm() -> void:
	var text := _dlg_edit.text
	match _dlg_mode:
		"new":
			var err := Characters.validate_name(text)
			if err == "" and Characters.count() >= Characters.MAX:
				err = "limit"
			if err != "":
				_show_err(err)
				return
			var id := Characters.create(text)
			Characters.activate(id)
			Profile.set_look(Look.code(_gender, 0))
			Profile.save()
			_focus_id = id
		"rename", "first":
			var err := Characters.rename(_dlg_id, text)
			if err != "":
				_show_err(err)
				return
			if _dlg_mode == "first" and _dlg_look_row.visible:
				Profile.set_look(Look.code(_gender, 0))
				Profile.save()
			_focus_id = _dlg_id
	Audio.play("ui_confirm", Audio.BUS_UI, -8.0)
	var first := _dlg_mode == "first"
	_dlg.visible = false
	if first or _dlg_mode == "new":
		visible = false
		closed.emit()
		return
	_rebuild()

func _show_err(code: String) -> void:
	_dlg_err.text = tr(String(ERR_TEXT.get(code, code)))
	Audio.play("ui_deny", Audio.BUS_UI, -10.0)

## Pierwsza propozycja: nazwa Steam (po czyszczeniu i jeśli wolna), inaczej losowa z puli.
func _suggest_name() -> String:
	var s := String(steam_name.call()) if steam_name.is_valid() else ""
	s = Characters.display_clean(s)
	if s != "" and Characters.validate_name(s, _dlg_id) == "":
		return s
	return _random_name()

## Losowy wolny kryptonim z puli; gdy wszystkie zajęte — z numerem.
func _random_name() -> String:
	var pool := CALLSIGNS.duplicate()
	pool.shuffle()
	for n in pool:
		if Characters.validate_name(String(n), _dlg_id) == "" and String(n) != _dlg_edit.text:
			return String(n)
	return "%s %d" % [String(pool[0]), randi_range(2, 99)]
