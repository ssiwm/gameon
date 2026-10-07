extends Control
## Panel warsztatu (faza B złomu): lista broni ze stojaków kryjówki z cenami, podgląd statystyk wybranej, zakup za wspólny złom.
## Otwiera go workshop.gd ([E] przy ławie). Na czas panelu akcje gry są wycięte z InputMap (Settings.block_game_input),
## więc sterowanie idzie surowymi klawiszami: ↑/↓ (W/S) wybór, Enter kupuje, Esc/E/Backspace zamyka. Świat idzie dalej.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")

const CARD_W := 330.0
const GOLD := Color(0.95, 0.8, 0.4)
## Kolejność listy: najpierw dostępne za złom, potem zablokowane do późniejszych stref.
const LIST := [Weapons.SPREAD12, Weapons.LR7, Weapons.HKM9, Weapons.SRUT8, Weapons.SOKOL6, Weapons.CIEGNO6]

var _open := false
var _sel := 0
var _card: PanelContainer
var _wallet: Label
var _rows: Array = []                   ## [{name: Label, state: Label}]
var _detail_title: Label
var _detail_grid: GridContainer
var _detail_text: Label
var _msg: Label
var _msg_t := 0.0

func _ready() -> void:
	add_to_group("workshop_ui")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_card.add_child(box)
	var head := HBoxContainer.new()
	var title := UiTheme.label("WORKSHOP", 14, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_wallet = UiTheme.label("", 11, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_wallet)
	box.add_child(head)
	box.add_child(UiTheme.label("Spend the squad's scrap to unlock guns on the racks.", 8, UiTheme.MUTED))
	box.add_child(_rule())
	for w in LIST:
		var row := HBoxContainer.new()
		var n := UiTheme.label("", 10, UiTheme.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var st := UiTheme.label("", 10, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(st)
		box.add_child(row)
		_rows.append({"name": n, "state": st})
	box.add_child(_rule())
	_detail_title = UiTheme.label("", 11, UiTheme.ACCENT)
	box.add_child(_detail_title)
	_detail_grid = GridContainer.new()
	_detail_grid.columns = 2
	_detail_grid.add_theme_constant_override("h_separation", 14)
	_detail_grid.add_theme_constant_override("v_separation", 1)
	box.add_child(_detail_grid)
	_detail_text = UiTheme.label("", 8, UiTheme.TEXT)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(CARD_W - 26.0, 0)
	box.add_child(_detail_text)
	box.add_child(_rule())
	_msg = UiTheme.label("", 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_msg)
	box.add_child(UiTheme.label("↑ ↓ select   ·   [ENTER] buy   ·   [ESC] close", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_msg.text = ""
	_sel = 0
	Settings.block_game_input(true)
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Settings.block_game_input(false)
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(delta: float) -> void:
	if not _open:
		return
	_msg_t = maxf(0.0, _msg_t - delta)
	if _msg_t <= 0.0:
		_msg.text = ""
	# panel zamyka się, gdy gracz odejdzie od ławy / zginie / misja się zmieni
	var wk := get_tree().get_first_node_in_group("workshop")
	if wk == null or not wk.local_in_range or not NoiseMgr.safe_zone:
		close()
		return
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	_card.position = ((size - _card.size) * 0.5).round()

func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_UP or k == KEY_W:
		_move(-1)
	elif k == KEY_DOWN or k == KEY_S:
		_move(1)
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		Scrap.request_buy(int(LIST[_sel]))
	elif k == KEY_ESCAPE or k == KEY_E or k == KEY_BACKSPACE:
		close()
	get_viewport().set_input_as_handled()

func _move(d: int) -> void:
	_sel = posmod(_sel + d, LIST.size())
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _on_result(w: int, ok: bool, reason: String) -> void:
	if not _open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"ok":
			_say("%s unlocked — take it from the rack." % name, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say("Not enough scrap (%d needed)." % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			_say("%s is already unlocked." % name, UiTheme.MUTED)
		"later":
			_say("Not available yet — a later zone.", UiTheme.MUTED)
		_:
			_say("Cannot buy that.", UiTheme.DANGER)
	_refresh()

func _say(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg_t = 3.0

func _refresh() -> void:
	if not _open:
		return
	_wallet.text = "SCRAP  %d" % Scrap.bank
	for i in LIST.size():
		var w: int = LIST[i]
		var d: RefCounted = Weapons.def(w)
		var row: Dictionary = _rows[i]
		var sel := i == _sel
		(row["name"] as Label).text = ("▶ " if sel else "   ") + String(d.name)
		(row["name"] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.TEXT)
		var st: Label = row["state"]
		if Scrap.is_unlocked(w):
			st.text = "UNLOCKED"
			st.add_theme_color_override("font_color", UiTheme.OK)
		elif Scrap.LATER.has(w):
			st.text = "LATER ZONE"
			st.add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			var price := Scrap.price_of(w)
			st.text = "%d scrap" % price
			st.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)
	var sw: int = LIST[_sel]
	var sd: RefCounted = Weapons.def(sw)
	var notes: Array = Codex.WEAPON_TEXT.get(String(sd.key), ["", ""])
	_detail_title.text = String(sd.name)
	for ch in _detail_grid.get_children():
		_detail_grid.remove_child(ch)
		ch.free()
	for r in Codex._weapon_stats(sd):
		_detail_grid.add_child(UiTheme.label(String(r[0]), 9, UiTheme.MUTED))
		_detail_grid.add_child(UiTheme.label(String(r[1]), 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	_detail_text.text = String(notes[0])
	_card.reset_size()

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.10)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
